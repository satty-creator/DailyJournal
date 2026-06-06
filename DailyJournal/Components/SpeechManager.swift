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

    // The partial transcript from the current session only.
    // The caller should append this to their existing content.
    @Published var partialTranscript = ""

    // The full text to show in the editor *live* while recording: the text that
    // existed before recording started, plus the running transcript. The editor
    // binds its content to this so words appear as they're spoken.
    @Published var liveText = ""

    // Snapshot of the editor's text at the moment recording started. The live
    // transcript is appended onto this so we never clobber what the user
    // already wrote.
    private var baseText = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // NOTE: AVAudioEngine must be recreated each session — reusing a stopped
    // engine causes silent failure when start() is called a second time.
    private var audioEngine: AVAudioEngine?

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
            stop()
        } else {
            await start(existingText: existingText)
        }
    }

    // MARK: - Start
    private func start(existingText: String) async {
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
            // On Simulator this is always false; on device it needs a network connection.
            errorMessage = "Speech recognition is unavailable — this feature requires an internet connection and doesn't work on the Simulator."
            return
        }

        // Reset state. Capture the existing text so the live transcript appends
        // onto it rather than replacing it.
        partialTranscript = ""
        baseText = existingText
        liveText = existingText
        errorMessage = nil

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
            // addsPunctuation can cause silent failures on certain locales — omit it

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

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        self.partialTranscript = spoken
                        // Publish the live, composed text so the editor updates
                        // word-by-word as the user speaks — no need to stop first.
                        let sep = self.baseText.isEmpty ? "" : " "
                        self.liveText = self.baseText + sep + spoken
                    }
                    if let error {
                        let nsErr = error as NSError
                        // Code 301 = cancelled (normal stop), 1110 = no speech detected
                        if nsErr.code != 301 && nsErr.code != 1110 {
                            self.errorMessage = "Recognition stopped — tap the mic to try again."
                            self.stop()
                        }
                    }
                    if result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            stop()
        }
    }

    // MARK: - Stop
    func stop() {
        // Remove tap before stopping the engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil  // release — next start() creates a fresh instance

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
