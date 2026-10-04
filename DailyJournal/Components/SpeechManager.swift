//
//  SpeechManager.swift
//  DailyJournal
//
//  Real-time speech-to-text using SFSpeechRecognizer.
//  Appends recognised words onto whatever text is already in the field.
//

import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechManager: ObservableObject {

    @Published var isRecording = false
    @Published var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    // The partial transcript from the current session only (committed
    // utterances + the in-progress one). The caller should append this to
    // their existing content.
    @Published var partialTranscript = ""

    // The full text to show in the editor *live* while recording: the text that
    // existed before recording started, plus the running transcript. The editor
    // binds its content to this so words appear as they're spoken.
    @Published var liveText = ""

    // Snapshot of the editor's text at the moment recording started. The live
    // transcript is appended onto this so we never clobber what the user
    // already wrote.
    private var baseText = ""

    // Finalised utterances from this session, joined together. In a continuous
    // dictation session `bestTranscription.formattedString` describes only the
    // CURRENT utterance and resets to near-empty once the recognizer decides an
    // utterance is done — without this accumulator, everything said before a
    // pause would vanish the moment the next utterance starts building. See
    // `handleResult`.
    private var committedTranscript = ""

    /// Whether we've asked the recognizer for punctuation this session. Some
    /// locales/OS combinations fail outright with `addsPunctuation = true`; if
    /// the very first result errors out before any words arrive, we retry once
    /// with it off rather than lose dictation entirely.
    private var punctuationEnabled = true

    /// Set once any non-empty result has been delivered — gates the
    /// punctuation-retry fallback so we only retry on an immediate failure.
    private var receivedAnyResult = false

    /// True once the user has tapped the mic to stop (`finish()`), as opposed
    /// to the recognizer ending the task on its own (e.g. a server-based
    /// session's internal time cap). Distinguishes "wrap up" from "keep going
    /// under the hood" in `handleResult`.
    private var userRequestedStop = false

    /// Set by `stop()`, cleared by `start()`. Gates the recognition callback so a
    /// result that was already in flight when the session ended can't write back to
    /// `liveText` after the caller has taken the transcript and moved on.
    private var discardPendingResults = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // NOTE: AVAudioEngine must be recreated each session — reusing a stopped
    // engine causes silent failure when start() is called a second time.
    private var audioEngine: AVAudioEngine?

    /// Grace-period fallback for `finish()`: if the recognizer never delivers a
    /// final result after we stop feeding it audio, force a hard stop so the mic
    /// doesn't hang open forever.
    private var finishTimeoutTask: Task<Void, Never>?

    init() {
        recognizer = SFSpeechRecognizer(locale: .current)
        authStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Request permissions
    func requestPermissions() async {
        // Only ask if we haven't already determined status
        if authStatus == .notDetermined {
            let speechStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }
            authStatus = speechStatus
        }

        // Microphone — iOS 17+ async API; request only if not yet determined
        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .undetermined {
            do {
                let granted = try await AVAudioApplication.requestRecordPermission()
                if !granted {
                    errorMessage = "Microphone access is needed to record voice entries."
                }
            } catch {
                errorMessage = "Couldn't request microphone access."
            }
        }
    }

    // MARK: - Toggle
    func toggle(existingText: String) async {
        if isRecording {
            finish()
        } else {
            await start(existingText: existingText)
        }
    }

    // MARK: - Start
    private func start(existingText: String, punctuationEnabled: Bool = true) async {
        // Request permissions if not already granted
        if authStatus != .authorized || AVAudioApplication.shared.recordPermission != .granted {
            await requestPermissions()
        }

        guard authStatus == .authorized else {
            errorMessage = "Speech recognition isn't authorised. Go to Settings → Privacy → Speech Recognition."
            return
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            errorMessage = "Microphone access is needed. Go to Settings → Privacy → Microphone."
            return
        }

        // Refresh recognizer in case locale changed or first init returned nil
        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: .current)
        }
        guard let recognizer else {
            errorMessage = "Speech recognition isn't supported for your current language."
            return
        }
        guard recognizer.isAvailable else {
            // On Simulator this is always false; on device it needs a moment
            // after the on-device speech models finish setting up.
            errorMessage = "Speech recognition is unavailable right now — this doesn't work on the Simulator."
            return
        }

        // Reset state. Capture the existing text so the live transcript appends
        // onto it rather than replacing it.
        partialTranscript = ""
        committedTranscript = ""
        baseText = existingText
        liveText = existingText
        errorMessage = nil
        discardPendingResults = false
        receivedAnyResult = false
        userRequestedStop = false
        self.punctuationEnabled = punctuationEnabled
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil

        do {
            // Configure audio session.
            // Use .playAndRecord (not .record) so the session works on all device
            // configurations — pure .record with .duckOthers is rejected on some hardware.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Build recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.addsPunctuation = punctuationEnabled
            // On-device recognition has no ~1 minute time cap, works offline, and
            // keeps journal audio on the phone — use it whenever the current
            // locale's speech model is installed.
            if recognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            }

            // Create a FRESH engine every session (reusing a stopped engine is unreliable)
            let engine = AVAudioEngine()
            self.audioEngine = engine

            // Access inputNode FIRST — this implicitly wires it into the engine's internal
            // graph. Calling prepare() before any node is attached causes a fatal assertion
            // "inputNode != nullptr || outputNode != nullptr" on iOS 26 / Simulator.
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Guard against a zero-sample-rate format (simulator / hardware not ready)
            guard recordingFormat.sampleRate > 0 else {
                errorMessage = "Audio input isn't available on this device."
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            // prepare() after the tap is installed — engine graph is fully wired at this point
            engine.prepare()
            try engine.start()
            isRecording = true

            recognitionTask = makeRecognitionTask(request: recognitionRequest)
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            stop()
        }
    }

    private func makeRecognitionTask(request: SFSpeechAudioBufferRecognitionRequest) -> SFSpeechRecognitionTask? {
        recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleResult(result, error)
            }
        }
    }

    // MARK: - Result handling
    private func handleResult(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        // Drop anything that arrives after an explicit stop(). Cancelling
        // the recognition task doesn't cancel callbacks already in flight,
        // and each one hops to the main actor separately — so a straggler
        // could land after the caller had already taken the transcript and
        // cleared its field, silently re-populating it. Note stop() (called
        // below) runs AFTER this write, so a genuine final correction is
        // still delivered.
        guard !discardPendingResults else { return }

        if let result {
            let spoken = result.bestTranscription.formattedString
            // CRITICAL: ignore empty transcriptions. When recording is
            // stopped/cancelled the recognizer often fires a FINAL
            // callback with an empty string; writing that through would
            // reset liveText back to baseText and wipe the words the
            // user just spoke (the whole field, if they spoke into an
            // empty editor). Only ever advance on real text.
            if !spoken.isEmpty {
                receivedAnyResult = true
                if result.speechRecognitionMetadata != nil {
                    // The recognizer attaches metadata once it considers an
                    // utterance complete — even mid-session, well before the
                    // whole task finishes. Fold it into the committed transcript
                    // now: the NEXT utterance's formattedString starts over from
                    // (near) empty rather than continuing, so without this the
                    // words spoken before a pause would otherwise be overwritten.
                    committedTranscript = compose(committedTranscript, spoken)
                    publish(current: "")
                } else {
                    publish(current: spoken)
                }
            }
        }

        if let error {
            let nsErr = error as NSError
            // Code 301 = cancelled (normal stop), 1110 = no speech detected
            if nsErr.code != 301 && nsErr.code != 1110 {
                if punctuationEnabled && !receivedAnyResult {
                    // Some locale/OS combinations fail outright with
                    // addsPunctuation set. We haven't lost any words yet
                    // (nothing was transcribed), so retry once with it off
                    // instead of surfacing an error to the user.
                    let existing = baseText
                    teardownAudioAndRequest()
                    Task { await self.start(existingText: existing, punctuationEnabled: false) }
                } else {
                    errorMessage = "Recognition stopped — tap the mic to try again."
                    stop()
                }
                return
            }
        }

        if result?.isFinal == true {
            if userRequestedStop {
                stop()
            } else {
                // The recognizer ended this task on its own — e.g. a
                // server-based session's internal ~1 minute cap — while the
                // user is still dictating. Start a fresh task on the same
                // running audio engine rather than silently cutting them off.
                restartTaskInPlace()
            }
        }
    }

    private func compose(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    private func publish(current: String) {
        let full = compose(committedTranscript, current)
        partialTranscript = full
        // Publish the live, composed text so the editor updates word-by-word
        // as the user speaks — no need to stop first.
        let sep = (baseText.isEmpty || full.isEmpty) ? "" : " "
        liveText = baseText + sep + full
    }

    /// Swaps in a fresh recognition request/task on the still-running audio
    /// engine, keeping the tap (and everything transcribed so far) intact.
    private func restartTaskInPlace() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        guard isRecording, let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = punctuationEnabled
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        receivedAnyResult = false
        recognitionTask = makeRecognitionTask(request: request)
    }

    private func teardownAudioAndRequest() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil  // release — next start() creates a fresh instance

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Finish (graceful stop — the mic button)
    /// Ends audio input but keeps listening briefly for the recognizer's FINAL
    /// result, which carries corrections and the last ~1s of speech that an
    /// immediate cancel would throw away. Falls back to a hard `stop()` after a
    /// short timeout in case the recognizer never delivers one.
    func finish() {
        guard isRecording else { return }
        userRequestedStop = true

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()

        finishTimeoutTask?.cancel()
        finishTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.isRecording else { return }
            self.stop() // recognizer never finalised in time — don't hang the mic open
        }
    }

    // MARK: - Stop (hard, immediate cancel)
    func stop() {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil

        // Close the gate first: from here on, any recognition callback still in
        // flight is stale and must not write back to `liveText`.
        discardPendingResults = true
        userRequestedStop = false

        teardownAudioAndRequest()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
