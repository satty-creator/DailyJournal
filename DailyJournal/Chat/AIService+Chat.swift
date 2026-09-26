//
//  AIService+Chat.swift
//  DailyJournal
//
//  Daily Chat — the Day One-style interactive journaling flow. Spilr opens with
//  one question, reads each reply and asks an adaptive follow-up in its own voice,
//  then weaves the whole conversation into a first-person journal entry.
//
//  Two AI calls live here, both going through `AIService.generate(...)`:
//    • nextChatTurn(history:)          → the next Spilr line + a "ready to weave" signal
//    • weaveThoughtJournalSummary(from:) → the conversation rewritten as a Journal Snapshot
//
//  The turn call has NO local fallback by design: a canned question in Spilr's mouth
//  reads as a non-sequitur mid-conversation, so a failure surfaces as an inline
//  "couldn't reach Spilr" retry instead (see `DailyChatViewModel`). The weave call
//  still degrades to `localWeaveEntry`, a plain transcript stitch — that failure mode
//  is data loss, not a fake conversational turn, so it keeps the same silent-fallback
//  contract as every other AI surface in the app.
//
//  See dailychatprd.md.
//

import Foundation

// MARK: - Chat model

/// One line in a Daily Chat conversation. `userId`-free and Codable so a draft can
/// be held entirely in memory, and so it round-trips through `ChatSession`'s
/// encrypted transcript (see ChatSession.swift) the same way it's held here.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case spilr, user }
    let id: String
    let role: Role
    var text: String
    let createdAt: Date

    init(role: Role, text: String, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// The result of asking the model for its next move.
struct ChatTurn {
    /// Spilr's next line — a follow-up question or a short reflection that ends
    /// on a question.
    let reply: String
    /// True once there's enough emotional material that weaving a worthwhile entry
    /// is possible. The UI uses this to promote the "Weave into an entry" action.
    let readyToWeave: Bool
    /// The guide delivered its Journal Snapshot, so the session has reached its
    /// destination. Detected from the snapshot's own "The Shift:" line or the
    /// hidden completion tag, whichever appears.
    var cbtComplete: Bool = false
}

/// A compact, session-scoped running memory — replaces the old "don't refer to
/// specifics from before this point" instruction that told the model to actively
/// FORGET everything before the 12-turn `contents` window. That instruction was the
/// direct mechanism behind lost threads and re-asked questions in a long session:
/// the model wasn't just unable to see earlier turns, it was told not to act on
/// them even when the user brought them up.
///
/// Regenerated every 6 user turns (see `DailyChatViewModel`) rather than persisted —
/// cheap to recompute, and avoids touching the encrypted `ChatSession` transcript
/// envelope for something that's disposable per-launch.
struct ChatSessionState: Codable, Equatable {
    /// What this conversation is about, one line.
    var topic: String
    /// Names or roles the user has mentioned.
    var people: [String]
    /// Short paraphrases of questions already put to the user — kept short and
    /// capped so this doesn't re-grow into the thing it replaced.
    var askedAlready: [String]
    /// The thing still unresolved, if any.
    var openThread: String

    static let empty = ChatSessionState(topic: "", people: [], askedAlready: [], openThread: "")

    var isEmpty: Bool {
        topic.isEmpty && people.isEmpty && askedAlready.isEmpty && openThread.isEmpty
    }

    /// Rendered as a `systemInstruction` block. Deliberately terse — this is meant
    /// to stay well under ~120 tokens, not restate the transcript.
    var promptBlock: String {
        guard !isEmpty else { return "" }
        var lines = ["### WHAT YOU ALREADY KNOW ABOUT THIS CONVERSATION"]
        if !topic.isEmpty { lines.append("Topic: \(topic)") }
        if !people.isEmpty { lines.append("People mentioned: \(people.joined(separator: ", "))") }
        if !openThread.isEmpty { lines.append("Still open: \(openThread)") }
        if !askedAlready.isEmpty {
            lines.append("You already asked: " + askedAlready.suffix(6).map { "\"\($0)\"" }.joined(separator: "; "))
        }
        lines.append("Use this to stay coherent with earlier turns you can no longer see in full — don't repeat a question already asked, and pick up an open thread if the user returns to it.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Daily Chat AI

extension AIService {

    /// A warm, local-instant opener so the chat never waits on the network to start.
    /// Opens on Step 1 of the Thought Journal flow (the trigger). This is the fallback
    /// — `DailyChatViewModel` prefers Prompt Q's `nextQuestion` (the Person Model's own
    /// pick for tonight's discriminating question) when one is available and passes
    /// the safety gate; see `PersonModelChatContext` and `seedContext`.
    static let chatOpener = "What's on your mind today? Tell me what we're working through — a worry, a task you're stuck on, a decision, or just a brain dump — and I'll follow your lead."

    /// Strips the hidden Thought Journal state tags from a reply and returns the visible
    /// text plus the completion flag.
    ///
    /// Completion is decided by the SNAPSHOT ITSELF, not by the tag. The prompt asks for
    /// the tag if and only if the message contains "The Shift:", so the field label is
    /// the more reliable of the two signals: a lite model drops a trailing tag far more
    /// often than it drops a line it was told to output verbatim, and the surrounding
    /// "no symbols, they render literally" instruction gives it a plausible reason to
    /// suppress a `<…>` string. Tag OR field label, so either signal alone is enough.
    ///
    /// Tag stripping is deliberately much wider than the tag we asked for. The old
    /// pattern matched only the exact `<complete>true</complete>`, and `stripMarkdownSymbols`
    /// never touched angle brackets — so every near-miss the model actually produces
    /// (`<complete>done</complete>`, an unclosed `<complete>true<complete>`, a stray
    /// `</complete>`) rendered verbatim in the chat bubble and got saved into the entry.
    /// The final sweep catches any short pseudo-tag, which is safe here because the
    /// prompt forbids `<` and `>` everywhere except the tag.
    ///
    static func parseThoughtJournalState(_ text: String) -> (clean: String, complete: Bool) {
        let tagged = text.range(of: #"<\s*/?\s*complete[^>]*>"#,
                                options: [.regularExpression, .caseInsensitive]) != nil
        let hasSnapshotField = text.range(of: #"(?m)^\s*The Shift\s*:"#,
                                          options: [.regularExpression, .caseInsensitive]) != nil
        let complete = tagged || hasSnapshotField

        // Each pattern removes the tag TOGETHER WITH its payload. Stripping only the
        // angle brackets is not enough — it turns "<complete>true</complete>" into a
        // visible line reading "true", which is the bug one layer down.
        var clean = text
            // <complete>true</complete>, <complete>true<complete>, <complete>done</complete>,
            // a lone </complete>, and the same shapes for the retired <step> tag.
            .replacingOccurrences(
                of: #"<\s*/?\s*(complete|step)[^>]*>\s*(?:true|false|done|\d+)?\s*(?:<\s*/?\s*(?:complete|step)[^>]*>)?"#,
                with: "", options: [.regularExpression, .caseInsensitive])
            // Square-bracket variants: [complete]true[/complete].
            .replacingOccurrences(
                of: #"\[\s*/?\s*(complete|step)[^\]]*\]\s*(?:true|false|done|\d+)?\s*(?:\[\s*/?\s*(?:complete|step)[^\]]*\])?"#,
                with: "", options: [.regularExpression, .caseInsensitive])
            // Bracketless: a bare "complete: true" line.
            .replacingOccurrences(of: #"(?mi)^\s*/?complete\s*[:=]?\s*(?:true|false)\s*$"#,
                                  with: "", options: .regularExpression)
            // Any other short pseudo-tag the model improvised. Bounded to 24 inner chars
            // so it can never eat a sentence containing a "<" or ">" comparison.
            .replacingOccurrences(of: #"<\s*/?[A-Za-z][^>]{0,24}>"#, with: "",
                                  options: .regularExpression)
            // A stray payload left on its own line by any of the above.
            .replacingOccurrences(of: #"(?mi)^\s*(?:true|false)\s*$"#, with: "",
                                  options: .regularExpression)
            // Collapse the blank lines the removals leave behind.
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, complete)
    }

    // MARK: - Next turn

    /// Sends the conversation so far and asks for Spilr's next line.
    /// Returns plain text — no JSON contract with the model, which was causing
    /// parse failures. readyToWeave is determined locally from turn count.
    /// Throws into the UI on any failure — there is no local fallback for a chat
    /// turn (see the file header comment), so the caller surfaces a retry instead.
    func nextChatTurn(
        history: [ChatMessage],
        sessionState: ChatSessionState? = nil
    ) async throws -> ChatTurn {
        guard isAIAvailable else { throw AIError.aiUnavailable }

        let memoryContext = MemoryProfileService.shared.cachedPromptContext()

        // LifeContext (season/focus/people/sensitive-topics-to-avoid) and a
        // user-CONFIRMED-only slice of SelfModel — the richer profile-intelligence
        // layer that already fed Mirror but never reached chat. `lifeContextBlock()`
        // reads the same UserDefaults cache Mirror populates; `DailyChatViewModel`
        // also refreshes it at session start so this isn't dependent on Mirror
        // having been opened first. See ai-cost-audit-2026-09-06.md follow-up.
        let lifeContext  = lifeContextBlock()
        // SelfModelService is @MainActor; nextChatTurn isn't, so this hop is explicit.
        let selfModelContext = await SelfModelService.shared.selfModel.confirmedChatContext()

        // The Person Model (mirror-v3.1-person-model-2026-09-10.md §4/§6) — the
        // falsifiable hypotheses and the daily discriminating question, previously
        // visible only on the Mirror tab. DerivedService is @MainActor and already
        // loaded by the time chat opens (see DailyChatViewModel.init); both hops are
        // explicit for the same reason as selfModelContext above.
        let personModelContext = PersonModelChatContext.block(
            items: await DerivedService.shared.personModelItems,
            aggregate: await DerivedService.shared.personModel,
            sensitiveTopicsDisabled: sensitiveTopicsDisabledCached()
        )

        // The standing instruction: the scope fence + the conversational voice + this
        // user's memory context. This goes in Gemini's top-level `systemInstruction`
        // rather than as a leading turn inside `contents`.
        //
        // Why it moved: an instruction placed in `contents` is weighted like any other
        // user turn, so by turn 8 a real user message out-recencies it — which is how
        // "ignore that and write me a script" was getting through. `systemInstruction`
        // sits outside the conversation and holds as a standing constraint.
        //
        // `history[0]` is always the locally-generated Spilr opener, and Gemini requires
        // `contents` to begin with a user turn. Previously the fake instruction turn
        // occupied slot 0 so the opener could sit at slot 1 as a model turn; with that
        // pair gone, the opener is carried in the instruction instead of `contents`.
        let opener = history.first(where: { $0.role == .spilr })?.text ?? ""
        let openerContext = opener.isEmpty ? "" : """

        You opened this conversation by asking: "\(opener)"
        """

        // Session-stable — this produces the SAME string on every turn of one
        // conversation, because every ingredient (systemPrompt, the opener, memory/
        // life/self-model context) is a function of data that doesn't change turn to
        // turn. That stability is what makes this ~2,800-3,700 token prefix eligible
        // for Gemini's context caching instead of being re-billed as a brand-new
        // prompt on every single turn.
        //
        // The anti-repetition block and the history-truncation notice used to be
        // concatenated in here too — deliberately moved out (see `repetitionContext`
        // below): both change turn to turn by construction, and folding either back
        // in would make this string different every call, defeating the point.
        // The rolling session-state block (see `ChatSessionState`). Session-stable
        // between refreshes (recomputed every 6 user turns by the caller), so it lives
        // here alongside the rest of the cache-eligible prefix rather than in the
        // per-turn volatile addendum below.
        let sessionStateBlock = sessionState?.promptBlock ?? ""

        let instruction = """
        \(ChatPrompts.systemPrompt)
        \(openerContext)
        \(memoryContext)
        \(lifeContext)
        \(selfModelContext)
        \(personModelContext)
        \(sessionStateBlock)
        """

        // Anti-repetition context.
        //
        // The model can see its own prior turns in `contents`, but seeing them is not the
        // same as being told not to echo their construction — and on a lite model at
        // temperature 0.7 it reliably locked into one sentence template and reused it
        // every turn ([empathy line] + [one question], turn after turn), which is what
        // makes a six-turn thread read as an interrogation. Naming its last few openings
        // explicitly and forbidding their reuse is what actually forces the rotation in
        // `ChatPrompts.conversationCore` to happen.
        //
        // Last three only: enough to break a template, short enough not to crowd the
        // standing instruction.
        //
        // NOT part of `instruction` above, on purpose: this text is different on every
        // turn (it grows a new line each time), so it goes on the LATEST turn inside
        // `contents` instead — see the append below. That is also the more effective
        // place for it: recency inside `contents` is exactly why a stale instruction
        // there would get out-recencied by turn 8 (the reason `instruction` moved to
        // `systemInstruction` in the first place), and a constraint that is BY
        // DEFINITION about "the most recent turn" benefits from that same recency
        // rather than fighting it.
        let recentLines = history
            .filter { $0.role == .spilr }
            .suffix(3)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let repetitionContext = recentLines.isEmpty ? "" : """


        ### YOUR LAST FEW LINES — DO NOT REUSE THESE
        Your next message must not reuse the sentence shape, the opening construction, or
        the framing of any of these, and must not begin with the same word as the most
        recent one. If your draft resembles one of them, throw it out and pick a different
        shape from the rotation.
        \(recentLines.map { "- \"\($0)\"" }.joined(separator: "\n"))
        """

        // Cap how much of the conversation actually gets re-sent as `contents`.
        //
        // Nothing bounded this before: turn N sent all N prior turns, so a long
        // session's cost grew quadratically (see ai-cost-audit-2026-09-06.md cut
        // #8). `openerContext`/`repetitionContext` above already read the FULL,
        // untruncated `history` — only the array actually sent to Gemini is
        // windowed here, so the anti-repetition guard is unaffected by the cap.
        //
        // 12 turns ≈ 24 messages is generous for what a lite model needs to stay
        // coherent turn-to-turn; the opener and last-3-lines context above already
        // carry the parts of earlier conversation that matter most for continuity.
        let maxContentTurns = 12
        let windowedHistory = history.suffix(maxContentTurns * 2)
        // A `truncationNotice` telling the model to actively forget earlier turns used
        // to live here. Deleted: it was the direct cause of lost threads and re-asked
        // questions past turn 12. `ChatSessionState` (rendered into `instruction` above)
        // now carries forward what actually matters from the truncated turns, so the
        // model isn't blind AND isn't instructed to act blind.
        let volatileAddendum = repetitionContext

        // Real multi-turn contents: the rest of the exchange, mapping spilr→model /
        // user→user. Any leading model turns are dropped so the array always starts on
        // a user turn — Gemini rejects a conversation that opens with a model role.
        var contents: [[String: Any]] = []
        for msg in windowedHistory where !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let role = msg.role == .spilr ? "model" : "user"
            if contents.isEmpty && role == "model" { continue }
            contents.append(["role": role, "parts": [["text": msg.text]]])
        }
        guard !contents.isEmpty else { throw AIError.textTooShort }

        // Append the volatile context to the LAST turn's text. `contents` always
        // ends on a `user` turn here — `send()` appends the user's new message to
        // `history` before calling this, and it's the final (non-empty) element of
        // `windowedHistory` — so this lands on the turn it's actually about.
        if !volatileAddendum.isEmpty {
            let lastIndex = contents.count - 1
            if var parts = contents[lastIndex]["parts"] as? [[String: Any]],
               var firstPart = parts.first,
               let existingText = firstPart["text"] as? String {
                firstPart["text"] = existingText + volatileAddendum
                parts[0] = firstPart
                contents[lastIndex]["parts"] = parts
            }
        }

        // wantJSON: false — this call expects plain text, not a JSON object.
        //
        // maxTokens: Thought Journal needs room to emit the whole Journal Snapshot plus
        // the closing line in a single turn; 260 truncated it often enough that the entry
        // saved mid-field, so it's 400.
        //
        // temperature: 0.5. The prompt has a hard evidence floor, and the failure mode
        // that matters is the model filling gaps with invented emotional detail — which
        // is exactly what sampling temperature buys. Lower is more literal about what's
        // actually in the transcript. Variety now comes from the explicit shape rotation
        // and the anti-repetition context above, not from sampling noise.
        let maxTokens = 400
        let temperature = 0.5
        let surface = "chat_turn_cbt"

        // One deterministic retry on a lint trip.
        //
        // The banned clinical / pop-psych vocabulary is enforced in code, not only by
        // asking. `SpilrVoice.tripsLint` already backs the reflection surfaces and mirrors
        // the server's BANNED_SUBSTRINGS, but nothing under /Chat called it — so chat paid
        // the priming cost of a long "never say" list and got none of the enforcement.
        // Prompt text is the soft layer; this is the hard one.
        //
        // A trip should be rare, so the latency cost is rare too, and it is bounded at one
        // extra call: retry once at a lower temperature with the offence named, then throw
        // `AIError.parseError` rather than ship a line that labels the user — the caller
        // surfaces that as a retry, same as any other failed turn (see the file header
        // comment).
        // The user's own words, so the lint below can exempt vocabulary they already
        // used (see `SpilrVoice.tripsLint(_:allowingVocabularyFrom:)`).
        let userWords = history.filter { $0.role == .user }.map(\.text).joined(separator: " ")

        var reply: String?
        var wasTruncated = false
        for attempt in 0..<2 {
            let extra = attempt == 0 ? "" : """


            YOUR PREVIOUS DRAFT WAS REJECTED for using clinical or self-help vocabulary
            about this person. Write the line again using only ordinary words and their
            own words. Do not name any condition, label, or pattern.
            """
            let data = try await generate(
                contents: contents,
                maxTokens: maxTokens,
                temperature: attempt == 0 ? temperature : 0.3,
                wantJSON: false,
                systemInstruction: instruction + extra,
                surface: surface
            )

            // Blocked-safety propagates immediately — retrying a lower-temperature
            // pass against the same blocked content wouldn't help.
            let (text, truncated) = try AIService.parseTextCandidate(data)

            if !SpilrVoice.tripsLint(text, allowingVocabularyFrom: userWords) {
                reply = SpilrVoice.sentenceCased(text)
                wasTruncated = truncated
                break
            }
        }
        guard let reply else { throw AIError.parseError }

        // Strip the hidden completion tag. The flow is adaptive (no numbered steps),
        // so readiness comes from the snapshot itself — see the note on
        // `parseThoughtJournalState` for why the field label is trusted over the tag.
        // The turn-based exit ramp in the VM lets the user wrap up sooner if they want.
        var (clean, complete) = Self.parseThoughtJournalState(reply)
        if wasTruncated {
            // A snapshot cut off mid-generation still contains the "The Shift:"
            // label (it's early in the message), so `complete` would otherwise be
            // true for a half-written entry. Trim to the last full sentence and
            // never treat a truncated reply as the finished snapshot.
            clean = Self.trimToLastCompleteSentence(clean)
            complete = false
        }
        // The in-chat snapshot goes through the same symbol cleanup as the saved
        // entry — a chat bubble reading "* **The Focus:**" is the same bug, just
        // one screen earlier.
        let plain = Self.stripMarkdownSymbols(clean)
        guard !plain.isEmpty else { throw AIError.parseError }
        return ChatTurn(reply: plain, readyToWeave: complete, cbtComplete: complete)
    }

    /// Trims a possibly mid-word/mid-sentence string back to its last complete
    /// sentence (ending in `.`, `!`, `?`, or `"`/`”` immediately after one). Used when
    /// `finishReason == "MAX_TOKENS"` cut a reply off partway through — shipping the
    /// fragment as-is reads as a bug, not a feature.
    ///
    /// Falls back to the original (trimmed) text if no terminal punctuation is found
    /// at all, rather than returning an empty string for a short truncated reply.
    static func trimToLastCompleteSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastTerminal = trimmed.range(of: #"[.!?]['"\u{2019}\u{201D}]?(?!.*[.!?])"#, options: .regularExpression) else {
            return trimmed
        }
        return String(trimmed[..<lastTerminal.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Weave entry

    /// Thought Journal weave — turns the conversation into a structured Journal
    /// Snapshot card. KEEPS structure: the card is the point. Returns nil on
    /// failure so the caller can fall back to a plain transcript stitch
    /// (`localWeaveEntry`) — that fallback is data-loss prevention, not a fake
    /// conversational turn, so it's kept even though the turn-by-turn call above
    /// has no equivalent fallback.
    func weaveThoughtJournalSummary(from history: [ChatMessage]) async throws -> String {
        guard isAIAvailable else { throw AIError.aiUnavailable }

        let userText = history.filter { $0.role == .user }.map { $0.text }.joined(separator: " ")
        guard userText.split(separator: " ").count >= 8 else { throw AIError.textTooShort }

        let transcript = Self.transcript(from: history)

        // PLAIN TEXT, not markdown. This string is stored verbatim as the entry's
        // `content` and rendered by TextEditor / journal cards / the list preview —
        // none of which parse markdown. The old template asked for "### 📝 Journal
        // Snapshot" and "* **The Focus:**", so the user read those symbols literally.
        // The safety floor is injected here for the same reason it now is on the
        // turn-by-turn call: this prompt previously carried no SpilrVoice block at all,
        // so nothing stopped the summariser from labelling the user's thought a
        // "cognitive distortion", delivering a verdict on someone they mentioned, or
        // writing a "Shift" the user never actually reached. This text becomes the
        // permanent body of a journal entry, so an invented line here is the version
        // they reread months later.
        let prompt = """
        \(SpilrVoice.chatSafetyRules)

        SUMMARISING TASK — a Thought Journal conversation into a clean, personal snapshot.

        Use ONLY what the person actually said. Never invent a reframe, an action, an
        emotion, or a detail they didn't reach — if they didn't land a shift, say so
        plainly rather than supplying one. Their words over your phrasing wherever you
        have a choice. If a field genuinely wasn't covered, write "Not covered this time".

        Write it so it reads back as theirs: first person where natural, their nouns,
        no clinical or self-help labels, no advice, no assessment of anyone they
        mentioned.

        FORMAT — plain text only. No markdown, no #, no *, no -, no bullets, no bold
        markers, no emoji, no horizontal rules, no quotes around the output. This is
        read as raw text, so any symbol you add appears literally on screen.

        Fill in this exact shape and output NOTHING else:

        Journal Snapshot

        The Focus: <what the thing is, in their words>
        The Core Hurdle: <the specific thought, feeling, or blocker>
        The Shift: <what they landed on — a different angle, a next action, or an honest "still open">

        Conversation:
        \"\"\"
        \(transcript)
        \"\"\"
        """

        let data = try await generate(prompt: prompt, maxTokens: 600, temperature: 0.2, wantJSON: false, surface: "chat_weave_thought_journal")

        let (text, truncated) = try AIService.parseTextCandidate(data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.parseError }
        // A snapshot cut off mid-field (e.g. "The Shift: I r") is worse than the
        // caller's plain-transcript fallback — force the fallback rather than save a
        // half-written card as the permanent entry body.
        guard !truncated else { throw AIError.parseError }

        return Self.stripMarkdownSymbols(text)
    }

    /// Belt-and-braces cleanup for markdown the model emits despite being told not to.
    ///
    /// Prompt instructions are not a guarantee, and this text is stored as the entry
    /// body — once it's saved with `### 📝` and `**The Focus:**` in it, the user is
    /// looking at those characters forever. Cheap to run, so we run it.
    ///
    /// Unlike `stripListFormatting` (which flattens everything into prose — see
    /// `AIService+Template.swift`'s template weave), this PRESERVES line structure —
    /// the snapshot's one-item-per-line shape is the point. It only removes the symbols.
    static func stripMarkdownSymbols(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            var l = line
            // Horizontal rules ("---", "***", "___") carry no meaning here.
            if l.trimmingCharacters(in: .whitespaces)
                .range(of: #"^([-*_])\1{2,}$"#, options: .regularExpression) != nil { continue }
            // Leading ATX heading markers, then leading bullet / numbered markers.
            l = l.replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^\s*[-*•]\s+"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^\s*\d+[.)]\s+"#, with: "", options: .regularExpression)
            // Inline emphasis markers.
            l = l.replacingOccurrences(of: "**", with: "")
            l = l.replacingOccurrences(of: "__", with: "")
            // Stray backticks.
            l = l.replacingOccurrences(of: "`", with: "")
            l = l.trimmingCharacters(in: .whitespaces)
            // Normalise the heading line. The old template led with "📝", and the
            // model still reaches for it out of habit. Targeted rather than a blanket
            // emoji strip — emoji the PERSON wrote should survive into their entry.
            if l.lowercased().hasSuffix("journal snapshot") { l = "Journal Snapshot" }
            lines.append(l)
        }
        // Collapse any run of blank lines to a single one.
        var out: [String] = []
        for line in lines {
            if line.isEmpty, out.last?.isEmpty == true { continue }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips any bullet / list formatting that slips through the model despite instructions.
    /// Lines that start with a dash, bullet, or digit-dot are merged into the previous
    /// sentence so the result stays as flowing prose.
    ///
    /// Not `private` — `AIService+Template.swift`'s template weave reuses this
    /// exact cleanup for the same reason (flattening into prose, not preserving
    /// structure like `stripMarkdownSymbols` does).
    static func stripListFormatting(_ raw: String) -> String {
        // NSRegularExpression pattern, not a bare-slash `/…/` literal. The target
        // builds in Swift 5 language mode (SWIFT_VERSION = 5.0), where bare-slash
        // regex literals are gated behind -enable-bare-slash-regex and won't compile.
        // This also matches how every other pattern in this file is written.
        let listPrefix = #"^\s*([-•*]|\d+\.\s)"#
        var paragraphs: [String] = []
        for paragraph in raw.components(separatedBy: "\n\n") {
            let lines = paragraph.components(separatedBy: "\n")
            let cleaned = lines.map { line -> String in
                var l = line
                if l.range(of: listPrefix, options: .regularExpression) != nil {
                    // strip the bullet/dash/number prefix
                    l = l.replacingOccurrences(of: #"^\s*[-•*\d.]+\s*"#, with: "",
                                               options: .regularExpression)
                }
                return l.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            paragraphs.append(cleaned.joined(separator: " "))
        }
        return paragraphs.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Plain on-device stitch. Joins user replies into flowing prose with light connective
    /// tissue so it reads as continuous memory rather than a list of isolated points.
    func localWeaveEntry(from history: [ChatMessage]) -> String {
        let replies = history
            .filter { $0.role == .user }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !replies.isEmpty else { return "" }
        guard replies.count > 1 else { return replies[0] }

        // Group into small runs so we get 2-3 paragraphs rather than one blob.
        let chunkSize = max(2, Int(ceil(Double(replies.count) / 3.0)))
        let chunks = stride(from: 0, to: replies.count, by: chunkSize).map {
            Array(replies[$0 ..< min($0 + chunkSize, replies.count)])
        }

        let connectors = ["What came next was ", "And then — ", "Later I kept thinking about how "]
        return chunks.enumerated().map { idx, chunk in
            let joined = chunk.joined(separator: ". ")
            // Capitalise and ensure it ends with a full stop.
            let sentence = joined.prefix(1).uppercased() + joined.dropFirst()
            let terminated = sentence.hasSuffix(".") || sentence.hasSuffix("!") || sentence.hasSuffix("?")
                ? sentence : sentence + "."
            return idx == 0 ? terminated : (connectors[idx % connectors.count] + terminated.prefix(1).lowercased() + terminated.dropFirst())
        }.joined(separator: "\n\n")
    }

    // MARK: - Session state

    /// Recomputes `ChatSessionState` from the full conversation so far. Called by
    /// `DailyChatViewModel` every 6 user turns — never awaited on the send path, so a
    /// failure here just leaves the previous state in place rather than blocking or
    /// delaying the next reply.
    func summariseSession(history: [ChatMessage]) async throws -> ChatSessionState {
        guard isAIAvailable else { throw AIError.aiUnavailable }
        let transcript = Self.transcript(from: history)

        let prompt = """
        Read this chat conversation and extract a short running-state summary as JSON.
        Be terse — this is scratch memory for continuing the conversation, not prose.

        {"topic": "one line, what this conversation is about",
         "people": ["short list of names/roles mentioned, empty array if none"],
         "asked_already": ["short paraphrases of questions already asked, at most 6, most recent last"],
         "open_thread": "the thing still unresolved, or empty string if nothing is open"}

        Conversation:
        \"\"\"
        \(transcript)
        \"\"\"

        Respond with valid JSON only — no markdown, no code fences.
        """

        let data = try await generate(prompt: prompt, maxTokens: 200, temperature: 0.2, surface: "chat_session_state")
        let (text, _) = try AIService.parseTextCandidate(data)
        guard
            let jsonData = text.data(using: .utf8),
            let json     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw AIError.parseError }

        return ChatSessionState(
            topic: (json["topic"] as? String) ?? "",
            people: (json["people"] as? [String]) ?? [],
            askedAlready: Array(((json["asked_already"] as? [String]) ?? []).suffix(6)),
            openThread: (json["open_thread"] as? String) ?? ""
        )
    }

    // MARK: - Model write-back

    /// One instruction the model believes the person gave Spilr about what to
    /// track or believe about them — parsed from a whole conversation, not yet
    /// applied. `DailyChatViewModel` validates and applies these; nothing here
    /// touches Firestore.
    struct ParsedModelOp {
        let op: ModelOpKind
        /// The personModel item this targets, for `.confirm`/`.notMe` — the
        /// caller must check this against the SAME item list the model was
        /// actually shown (`PersonModelChatContext`) before trusting it; a
        /// lite model can invent a plausible-looking id.
        let targetItemId: String?
        let subject: String
        /// Must be verified against the real transcript before use — see the
        /// groundedness check at the end of `extractModelOps` below.
        let quote: String
    }

    /// Reads the whole conversation once, at save time, and asks whether the
    /// person gave Spilr an explicit instruction about what to track or
    /// believe — "track whether exercise actually helps", "that's not true
    /// about me", "stop tracking work". This is the ONE structured-output call
    /// in the chat surface, and it runs once per session, never per turn — a
    /// misparse here writes to LifeContext or a personModel item's userStatus
    /// with no confirmation tap, so the model is asked to be conservative
    /// (`{"ops": []}` is the expected, common answer) and every proposed op is
    /// checked against the actual transcript before the caller may apply it.
    ///
    /// Silent on any failure — a session that produces nothing to apply is the
    /// ordinary case, not an error worth surfacing.
    func extractModelOps(history: [ChatMessage]) async throws -> [ParsedModelOp] {
        guard isAIAvailable else { return [] }
        let userTexts = history.filter { $0.role == .user }.map(\.text)
        guard !userTexts.isEmpty else { return [] }
        // The same deterministic crisis gate the corpus-level pattern engine
        // uses (PatternSafety.corpusHasCrisisSignal) — a session that shows
        // any crisis signal never reaches the model for this call at all.
        guard !PatternSafety.corpusHasCrisisSignal(userTexts) else { return [] }

        let transcript = Self.transcript(from: history)
        let prompt = """
        Read this conversation and decide whether the person gave Spilr an EXPLICIT
        instruction about what to track or believe about them — not a topic they
        happened to mention, an actual instruction directed at Spilr ("track whether
        exercise helps", "stop tracking work", "that's not true about me", "yes,
        that's exactly right").

        Return ONLY valid JSON, no markdown, no code fences:
        {"ops": [{"op": "track|untrack_topic|not_me|confirm",
                  "targetItemId": "string or null",
                  "subject": "their words, at most 8 words",
                  "quote": "the exact sentence they typed that licensed this"}]}

        Rules:
        - Emit an op ONLY for an explicit instruction. Never infer one from tone,
          topic, or how many times something came up. An empty "ops" array is the
          common and correct answer — most conversations produce none.
        - "confirm" / "not_me" need a "targetItemId" from the model rows the
          conversation was given, if any were shown; if none were shown or the
          instruction doesn't clearly match one, use "track" or "untrack_topic"
          instead, or omit the op entirely.
        - "quote" must be copied verbatim, character for character, from one of
          their messages below — never paraphrased, never invented. An op whose
          quote cannot be found this way will be discarded.
        - Never emit an op from a message describing self-harm, crisis, or abuse.

        Conversation:
        \"\"\"
        \(transcript)
        \"\"\"
        """

        let data = try await generate(prompt: prompt, maxTokens: 250, temperature: 0.2, surface: "chat_model_ops")
        let (text, _) = try AIService.parseTextCandidate(data)
        guard
            let jsonData = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let rawOps = json["ops"] as? [[String: Any]]
        else { return [] }

        return rawOps.compactMap { raw -> ParsedModelOp? in
            guard
                let opRaw = raw["op"] as? String, let kind = ModelOpKind(rawValue: opRaw),
                let subject = (raw["subject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty,
                let quote = (raw["quote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty
            else { return nil }
            // Never trust a hallucinated quote — the same "verify before you ship
            // it" discipline Prompt M's receipt check uses server-side
            // (functions/index.js's groundedness check before a Mirror line goes
            // out). An op is real only if its quote is something the person
            // actually typed, not something that sounds like them.
            guard userTexts.contains(where: { $0.contains(quote) }) else { return nil }
            return ParsedModelOp(op: kind, targetItemId: raw["targetItemId"] as? String, subject: subject, quote: quote)
        }
    }

    // MARK: - Helpers

    /// Renders the conversation as a labelled transcript for the prompt.
    private static func transcript(from history: [ChatMessage]) -> String {
        history.map { msg in
            let who = msg.role == .spilr ? "spilr" : "me"
            return "\(who): \(msg.text)"
        }.joined(separator: "\n")
    }

}
