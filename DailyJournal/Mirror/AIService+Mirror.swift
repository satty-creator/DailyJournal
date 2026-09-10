// AIService+Mirror.swift
// DailyJournal
//
// Mirror Engine AI layer: per-entry deep analysis, plus the client's read side
// of the server-generated Mirror card deck.
// Prompt A (mirror-extract-v1)   — analyzeEntry          → EntryAnalysis
// Prompt F (mirror-narrative-v1) — generateMirrorNarrative → MirrorNarrative?
//
// Prompts B/D/E (mining, card write, card guard) moved server-side —
// functions/index.js `mineHypothesesForUser` / `generateMirrorDeck` /
// `bootstrapMirror`. The Mirror tab no longer makes an LLM call on open; it
// only reads `patternHypotheses` and the pre-generated `mirrorCards` deck.
// See the Mirror re-architecture plan and ai-cost-audit-2026-09-06.md cut #1.
//
// All calls are non-throwing. Failures degrade silently to local fallbacks or nil.

import Foundation
import FirebaseFirestore
import FirebaseAppCheck
import CryptoKit

extension AIService {

    // MARK: - Analyse entry (Prompt A, mirror-extract-v1)

    /// Stable SHA256 hex digest of the trimmed entry text — used only to detect
    /// "this is the same content we already analysed," never for anything
    /// cryptographic. `String.hashValue` is unusable here: it's randomised per
    /// process, so it can't be compared against a value written in an earlier
    /// app launch.
    private func stableContentHash(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns a deep structural analysis of the entry text.
    /// Never throws — returns `EntryAnalysis.local(...)` on any failure.
    ///
    /// Content-hash guard: `JournalEditorViewModel.save()` re-runs this on every
    /// save of an existing entry, including a save that only fixed a typo — see
    /// ai-cost-audit-2026-09-06.md §3.3. If the stored analysis already carries a
    /// hash of this exact text, skip the call and return the stored analysis
    /// unchanged rather than paying to re-derive the same structure.
    func analyzeEntry(
        entryId: String,
        userId: String,
        text: String,
        // Typed passthrough for a guided-template entry (Phase 5) — never
        // model output, so there's nothing here for the model to invent.
        templateId: String? = nil,
        templateScaleBefore: Int? = nil,
        templateScaleAfter: Int? = nil
    ) async -> EntryAnalysis {
        let templateDelta: TemplateDelta? = {
            guard let templateId, let before = templateScaleBefore, let after = templateScaleAfter else { return nil }
            return TemplateDelta(templateId: templateId, before: before, after: after)
        }()

        guard isAIAvailable else {
            return EntryAnalysis.local(entryId: entryId, userId: userId, text: text)
        }
        guard text.count > 30 else {
            return EntryAnalysis.local(entryId: entryId, userId: userId, text: text)
        }

        let hash = stableContentHash(text)
        let docRef = Firestore.firestore()
            .collection("users").document(userId)
            .collection("entryAnalyses").document(entryId)

        // Cache-first (covers the common same-session re-edit instantly), then a
        // live fetch so the guard also holds across an app restart.
        let cachedSnapshot = try? await docRef.getDocument(source: .cache)
        let snapshot = (cachedSnapshot?.exists == true) ? cachedSnapshot : try? await docRef.getDocument()
        if let snapshot, snapshot.exists,
           snapshot.get("contentHash") as? String == hash,
           let existing = EntryAnalysis(from: snapshot.data() ?? [:]) {
            // Promote on the cache-hit path too — an entry re-opened (not just
            // freshly analysed) is a free chance to backfill its episodes into
            // `events` if this build shipped after the entry was first
            // analysed. Idempotent (see JournalEvent.id), so this is never
            // wasted work even when it's already there.
            EventService.shared.promote(from: existing)
            return existing
        }

        let prompt = buildMirrorExtractPrompt(text: text)

        guard let data = try? await generate(
            prompt: prompt,
            maxTokens: 1200,
            temperature: 0.3,
            surface: "mirror_analyze_entry"
        ) else {
            return EntryAnalysis.local(entryId: entryId, userId: userId, text: text)
        }

        guard var analysis = parseMirrorExtractResponse(
            data,
            entryId: entryId,
            userId: userId,
            text: text
        ) else {
            return EntryAnalysis.local(entryId: entryId, userId: userId, text: text)
        }
        if templateDelta != nil {
            analysis = analysis.withTemplateDelta(templateDelta)
        }

        // Fire-and-forget persist (completion-handler form, no try/await — matches app-wide pattern)
        var doc = analysis.toFirestoreData()
        doc["contentHash"] = hash
        docRef.setData(doc) { _ in }

        // Promote this analysis's episodes to first-class `events` docs — see
        // JournalEvent.swift. Same data Prompt A just produced; no extra AI cost.
        EventService.shared.promote(from: analysis)

        return analysis
    }

    // MARK: - Mirror bootstrap (server-side one-time mine + deck)

    /// Triggers the server's one-time Mirror bootstrap for a brand-new user who
    /// has crossed the mining threshold (≥3 entry analyses) before the server's
    /// own nightly mine has ever run for them. Runs the SAME mine + deck code
    /// the nightly job uses (`functions:bootstrapMirror`), just invoked
    /// synchronously instead of waiting up to 24h for the next 4am UTC run.
    ///
    /// Fire this, then reload hypotheses (`MirrorGraphService.loadHypotheses`)
    /// and the card deck as usual — this call's response carries nothing the
    /// caller needs to read. Never throws; a failure here just means the user
    /// waits for the next nightly mine, same as any other AI degrade in this
    /// app. The server's own `lastMineRunAt` claim (see `claimMirrorBootstrap`
    /// in functions/index.js) is what makes repeat calls safe and cheap —
    /// there is no client-side result to branch on.
    func bootstrapMirror(userId: String) async {
        guard isAIAvailable, let token = await idToken() else { return }

        var request = URLRequest(url: URL(string: Self.mirrorBootstrapURLString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        // The server chains a mine call plus up to MIRROR_DECK_SIZE card
        // generations — materially longer than a single Gemini round trip
        // (generate()'s 25s), so this needs its own, longer timeout. A
        // client-side timeout here does NOT mean the work was lost: the server
        // keeps running independently, and the next Mirror load picks up
        // whatever it wrote.
        request.timeoutInterval = 90

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Fetch a card from the server-generated deck

    /// Reads one card from `users/{uid}/mirrorCards/{hypothesisId}` — the deck
    /// `functions:mineUserInsights` / `functions:bootstrapMirror` write to.
    /// Returns nil if this hypothesis hasn't earned a card yet (it wasn't in
    /// the last mine's top-scoring set, or its card was suppressed by the
    /// server-side guard). No AI call — this is a pure Firestore read.
    ///
    /// Cache-first: the deck only changes when a mine runs (at most every few
    /// days per `MIN_NEW_ANALYSES_TO_MINE`/`MINE_MAX_STALENESS_HOURS`), so
    /// there's no reason to pay a server round-trip on every Mirror open the
    /// way the old per-date `mirrors/{yyyy-MM-dd}` read did.
    func fetchMirrorCard(hypothesisId: String, userId: String) async -> MirrorCard? {
        guard let snapshot = try? await FirestoreCacheFirst.document(
            Firestore.firestore()
                .collection("users").document(userId)
                .collection("mirrorCards").document(hypothesisId),
            key: "mirrorCard.\(userId).\(hypothesisId)"
        ), let data = snapshot.data()
        else { return nil }

        return MirrorCard(from: data)
    }

    // MARK: - Narrative synthesis (Prompt F, mirror-narrative-v1)

    /// Generates a 3-4 sentence psychological sketch from the top hypotheses.
    /// Returns nil on failure — never throws. Cached weekly by the caller.
    func generateMirrorNarrative(
        userId: String,
        hypotheses: [PatternHypothesis]
    ) async -> MirrorNarrative? {
        guard isAIAvailable, hypotheses.count >= 3 else { return nil }

        let prompt = buildMirrorNarrativePrompt(hypotheses: hypotheses)
        guard let data = try? await generate(
            prompt: prompt,
            maxTokens: 500,
            temperature: 0.5,
            surface: "mirror_narrative"
        ) else { return nil }

        return parseMirrorNarrativeResponse(data)
    }

    private func buildMirrorNarrativePrompt(hypotheses: [PatternHypothesis]) -> String {
        let rendered = hypotheses.prefix(5).enumerated().map { idx, h in
            let quotes = h.evidence.prefix(2).map { "\"\($0.quote)\"" }.joined(separator: "; ")
            let daysSince = Calendar.current.dateComponents([.day], from: h.firstSeenAt, to: Date()).day ?? 0
            return """
            \(idx + 1). "\(h.userFacingTitle)"
               Hypothesis: \(h.coreHypothesis)
               Protection: \(h.protection ?? "—")
               Cost: \(h.cost ?? "—")
               Evidence: \(quotes.isEmpty ? "—" : quotes)
               Seen \(h.timesSeen)× over \(daysSince) days
            """
        }.joined(separator: "\n\n")

        let exceptions = hypotheses
            .filter { $0.patternType == .exception }
            .prefix(3)
            .map { "- \($0.userFacingTitle): \($0.coreHypothesis)" }
            .joined(separator: "\n")

        let phrases = hypotheses
            .flatMap(\.evidence)
            .prefix(6)
            .map { "\"\($0.quote)\"" }
            .joined(separator: ", ")

        return """
        \(SpilrVoice.safetyRules)

        TASK: Write a 3-4 sentence sketch of this person based on their patterns.
        Talk to them directly ("you"). Plain English, no poetry.

        RULES:
        - Every sentence must be immediately clear on first read. 8th-grade reading level.
          If you reach for a metaphor, delete it and say what you actually mean.
        - Use their exact phrases in quotes — the sketch must sound like THEM, not like a therapist
        - Name specific situations, people, and days — not abstractions
        - Name what's WORKING (exceptions, what softens) alongside what loops
        - Everything is a hypothesis — "seems", "may", "might"
        - No diagnosis, no clinical terms, no trauma inference, no self-help language
        - Must pass the horoscope test: must contain details only this person would recognize
        - Write like a smart friend summarizing what they've noticed, not a wellness app
        - NEVER name a psychological label, even a popular one — not
          "perfectionism", "people-pleasing", "catastrophising", "imposter
          syndrome", "fear of failure", "inner critic", "core belief", and not
          "your worth is tied to your productivity". A label is interchangeable
          across millions of people, which makes it the exact opposite of a
          sketch of THIS person. Say what they DO, in the words they used.
        - Every sentence must be checkable against a specific entry. If you
          cannot point at the entry it came from, cut the sentence.

        PATTERNS (ranked by evidence strength):
        \(rendered)

        EXCEPTIONS (what helped):
        \(exceptions.isEmpty ? "(none yet)" : exceptions)

        VOCABULARY (their distinctive phrases):
        \(phrases.isEmpty ? "(none)" : phrases)

        \(MemoryProfileService.shared.cachedPromptContext())

        Return ONLY valid JSON:
        {
          "narrative": "3-4 sentences, direct address, their language",
          "shifting": [
            {"direction": "growing|fading", "signal": "what specifically", "evidence": "brief"}
          ],
          "openQuestion": "one question this sketch raises but can't yet answer"
        }
        """
    }

    private func parseMirrorNarrativeResponse(_ data: Data) -> MirrorNarrative? {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let first   = cands.first,
            let content = first["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let rawText = parts.first?["text"] as? String,
            let jsonData = rawText.data(using: .utf8),
            let json    = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let narrative = json["narrative"] as? String,
            !narrative.isEmpty
        else { return nil }

        // OUTPUT-SIDE LINT. The narrative is the first thing the user reads on
        // the Mirror screen and it previously shipped straight to Firestore with
        // no deterministic check — the only profile surface with none. Prompt
        // rules are a request; this is the enforcement. Silence beats a bad
        // sketch, so a trip returns nil and the section simply doesn't render.
        guard !SpilrVoice.tripsLint(narrative) else {
            #if DEBUG
            print("Mirror narrative suppressed by lint")
            #endif
            return nil
        }

        let shifting: [MirrorNarrative.ShiftSignal] = (json["shifting"] as? [[String: Any]] ?? [])
            .compactMap { item in
                guard
                    let direction = item["direction"] as? String,
                    let signal    = item["signal"]    as? String
                else { return nil }
                guard !SpilrVoice.tripsLint(signal) else { return nil }
                return MirrorNarrative.ShiftSignal(
                    direction: direction == "growing" ? .growing : .fading,
                    signal: SpilrVoice.sentenceCased(signal),
                    evidence: item["evidence"] as? String ?? ""
                )
            }

        let openQuestion = json["openQuestion"] as? String
        return MirrorNarrative(
            narrative: SpilrVoice.sentenceCased(narrative),
            shifting: shifting,
            openQuestion: openQuestion.flatMap {
                SpilrVoice.tripsLint($0) ? nil : SpilrVoice.sentenceCased($0)
            }
        )
    }

    // MARK: - Life context injection

    /// Not private: Daily Chat reads this too (`nextChatTurn`), not just Mirror's
    /// own prompt builders below — see ai-cost-audit-2026-09-06.md follow-up on
    /// chat context. Both read the same UserDefaults-cached block; `cacheLifeContext`
    /// is what keeps it fresh, called from both Mirror's and Chat's load paths.
    func lifeContextBlock() -> String {
        UserDefaults.standard.string(forKey: "cachedLifeContextBlock") ?? ""
    }

    /// Call once at load time to cache the rendered life context block.
    static func cacheLifeContext(_ ctx: LifeContext) {
        guard ctx.currentSeason != nil || !ctx.primaryFocus.isEmpty else {
            UserDefaults.standard.removeObject(forKey: "cachedLifeContextBlock")
            return
        }
        var lines: [String] = []
        if let season = ctx.currentSeason { lines.append("Life season: \(season.rawValue.replacingOccurrences(of: "_", with: " "))") }
        if !ctx.primaryFocus.isEmpty { lines.append("Focus areas: \(ctx.primaryFocus.joined(separator: ", "))") }
        if !ctx.sensitiveTopicsDisabled.isEmpty {
            lines.append("DO NOT surface patterns about: \(ctx.sensitiveTopicsDisabled.joined(separator: ", "))")
        }
        let depthNote: String
        switch ctx.preferredDepth {
        case .gentle: depthNote = "Preferred depth: gentle — hedge heavily, shorter observations."
        case .balanced: depthNote = ""
        case .deep: depthNote = "Preferred depth: deep — user wants full structural observations."
        }
        if !depthNote.isEmpty { lines.append(depthNote) }
        let block = "\nLIFE CONTEXT (user-supplied, shape tone accordingly):\n" + lines.joined(separator: "\n")
        UserDefaults.standard.set(block, forKey: "cachedLifeContextBlock")
    }

    // MARK: - Prompt builders

    private func buildMirrorExtractPrompt(text: String) -> String {
        """
        \(SpilrVoice.system)

        MIRROR EXTRACTION — read this journal entry and return a structured JSON analysis.

        Rules:
        - All inferences need a confidence (0.0–1.0). Silence (omit) beats low-confidence noise.
        - Use the person's own words for evidenceQuote and phrase fields.
        - Protective strategies are adaptive, not pathological. Frame them that way.
        - Do NOT infer diagnosis, trauma origin, attachment style, or mental disorder.
        - "may/might/seems" language throughout — these are observations, not verdicts.

        Return ONLY valid JSON matching this exact schema:
        {
          "surfaceSummary": "1 sentence — what's actually happening beneath the words",
          "lifeDomains": ["work"|"rest"|"relationships"|"body"|"money"|"creativity"|"meaning"],
          "explicitEmotions": ["emotions the user named directly"],
          "inferredEmotions": [{"emotion":"","confidence":0.0,"evidenceQuote":""}],
          "needs": ["underlying needs, e.g. rest/connection/certainty/control/recognition"],
          "protectiveStrategies": [{"strategy":"","protectsAgainst":"","confidence":0.0,"evidence":""}],
          "avoidanceMarkers": [{"type":"topic|person|feeling","phrase":"","function":"what avoiding this may protect"}],
          "cognitivePatterns": ["e.g. all-or-nothing, perfectionism, catastrophising — only if strongly evidenced"],
          "valuesPresent": ["values visible in the writing"],
          "valuesConflict": ["e.g. 'wants rest but feels productivity is the only valid use of time'"],
          "bodySignals": ["physical sensations mentioned or implied"],
          "relationshipRoles": ["e.g. fixer, peacekeeper, invisible one"],
          "openLoops": ["unresolved situations or decisions mentioned"],
          "phrasesToTrack": ["distinctive words/phrases worth watching across future entries"],
          "possibleTinyAct": "one small, concrete experiment (optional — omit if nothing fits)",
          "episodes": [
            {
              "episodeId": "ep1",
              "situation": "what was happening",
              "emotions": [""],
              "bodySignals": [""],
              "protectiveStrategy": "",
              "need": "",
              "outcome": ""
            }
          ]
        }

        Entry:
        \"\"\"
        \(text)
        \"\"\"

        \(MemoryProfileService.shared.cachedPromptContext())
        """
    }

    // MARK: - Response parsers

    private func parseMirrorExtractResponse(
        _ data: Data,
        entryId: String,
        userId: String,
        text: String
    ) -> EntryAnalysis? {
        guard
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cands   = root["candidates"] as? [[String: Any]],
            let first   = cands.first,
            let content = first["content"] as? [String: Any],
            let parts   = content["parts"] as? [[String: Any]],
            let rawText = parts.first?["text"] as? String,
            let jsonData = rawText.data(using: .utf8),
            let json    = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        let surfaceSummary   = json["surfaceSummary"]   as? String ?? ""
        let lifeDomains      = json["lifeDomains"]      as? [String] ?? []
        let explicitEmotions = json["explicitEmotions"] as? [String] ?? []
        let needs            = json["needs"]            as? [String] ?? []
        let cognitivePatterns  = json["cognitivePatterns"]  as? [String] ?? []
        let valuesPresent      = json["valuesPresent"]      as? [String] ?? []
        let valuesConflict     = json["valuesConflict"]     as? [String] ?? []
        let bodySignals        = json["bodySignals"]        as? [String] ?? []
        let relationshipRoles  = json["relationshipRoles"]  as? [String] ?? []
        let openLoops          = json["openLoops"]          as? [String] ?? []
        let phrasesToTrack     = json["phrasesToTrack"]     as? [String] ?? []
        let possibleTinyAct    = json["possibleTinyAct"]    as? String

        let inferredEmotions: [InferredEmotion] = (json["inferredEmotions"] as? [[String: Any]] ?? [])
            .compactMap { InferredEmotion(from: $0) }

        let protectiveStrategies: [ProtectiveStrategy] = (json["protectiveStrategies"] as? [[String: Any]] ?? [])
            .compactMap { ProtectiveStrategy(from: $0) }

        let avoidanceMarkers: [AvoidanceMarker] = (json["avoidanceMarkers"] as? [[String: Any]] ?? [])
            .compactMap { AvoidanceMarker(from: $0) }

        let episodes: [EpisodeFrame] = (json["episodes"] as? [[String: Any]] ?? [])
            .compactMap { dict -> EpisodeFrame? in
                guard let situation = dict["situation"] as? String else { return nil }
                return EpisodeFrame(
                    episodeId:           dict["episodeId"]         as? String ?? UUID().uuidString,
                    situation:           situation,
                    emotions:            dict["emotions"]          as? [String] ?? [],
                    bodySignals:         dict["bodySignals"]       as? [String] ?? [],
                    protectiveStrategy:  dict["protectiveStrategy"] as? String,
                    need:                dict["need"]              as? String,
                    outcome:             dict["outcome"]           as? String
                )
            }

        guard !surfaceSummary.isEmpty else { return nil }

        return EntryAnalysis(
            entryId:              entryId,
            userId:               userId,
            surfaceSummary:       surfaceSummary,
            lifeDomains:          lifeDomains,
            explicitEmotions:     explicitEmotions,
            inferredEmotions:     inferredEmotions,
            needs:                needs,
            protectiveStrategies: protectiveStrategies,
            avoidanceMarkers:     avoidanceMarkers,
            cognitivePatterns:    cognitivePatterns,
            valuesPresent:        valuesPresent,
            valuesConflict:       valuesConflict,
            bodySignals:          bodySignals,
            relationshipRoles:    relationshipRoles,
            openLoops:            openLoops,
            phrasesToTrack:       phrasesToTrack,
            possibleTinyAct:      possibleTinyAct,
            episodes:             episodes,
            promptVersion:        "mirror-extract-v1"
        )
    }
}
