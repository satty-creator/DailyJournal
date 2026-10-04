// AIService+Mirror.swift
// DailyJournal
//
// Mirror Engine AI layer: per-entry deep analysis, plus the client's read side
// of the server-generated Mirror card deck.
// Prompt A (mirror-extract-v2)   — analyzeEntry → EntryAnalysis. The ONLY
// LLM call this file still makes: Prompt F (mirror-narrative-v1) was deleted
// in Mirror v3, so the Mirror surface now makes no client-side model call at
// all, on open or otherwise.
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
        // The ENTRY's own createdAt — typed passthrough, not model output.
        // Mirror v3's FactsJob needs it to bucket the entry into the right
        // local day/band without depending on `entryAnalyses.createdAt`
        // (which is when this ANALYSIS ran, and moves on re-analysis —
        // mirror-v3-prd-2026-09-10.md §1.3).
        entryCreatedAt: Date? = nil,
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
        // Same formula as `JournalEntry.wordCount` — computed here, not
        // passed by the caller, so the two numbers can never disagree.
        // Available regardless of AI outcome; `content` is encrypted at rest,
        // so this is the server's only way to ever see it.
        let wordCount = text.split(separator: " ").count

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
        analysis = analysis.withEntryMeta(entryCreatedAt: entryCreatedAt, wordCount: wordCount)

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

    /// Triggers the server's on-demand derived-layer recompute
    /// (`functions:refreshDerived`) for an account whose `derived/facts` /
    /// `derived/threads` / `readings/{date}` have never been written — most
    /// commonly a RETURNING user on a fresh install, where `bootstrapMirror`
    /// above refuses outright (it only ever fires once per account, gated on
    /// `lastMineRunAt`). This is the fallback for that case: same
    /// `runDerivedForUser` the nightly cron calls, invoked synchronously
    /// instead of waiting for the next 04:00 UTC run.
    ///
    /// Pure arithmetic server-side — no Gemini call, no cost ceiling to
    /// respect — so this can be called far more liberally than
    /// `bootstrapMirror`. The server still enforces its own short cooldown
    /// per uid; `MirrorViewModel.refreshDerivedIfNeeded` adds a longer local
    /// one on top just to avoid a pointless round trip on every Mirror open.
    ///
    /// Never throws; a failure just means the user waits for the next
    /// nightly run, same as any other AI-adjacent degrade in this app.
    func refreshDerived(userId: String) async {
        guard let token = await idToken() else { return }

        var request = URLRequest(url: URL(string: Self.refreshDerivedURLString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        // Pure arithmetic over a bounded lookback window — much faster than
        // bootstrapMirror's mine + deck chain, but still give it real
        // headroom rather than the 25s single-round-trip default.
        request.timeoutInterval = 60

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Prompt ASK (mirror-v3.1), server-side

    struct MirrorAskCitation {
        let itemId: String
        let quote: String
        let date: String?
    }

    struct MirrorAskResult {
        let answer: String
        let citations: [MirrorAskCitation]
    }

    /// Prompt ASK, server-side — `functions:mirrorAsk`. The client sends only
    /// the question; the server answers from the Person Model with receipts.
    /// Never throws — a failure reads to the caller as `nil`, same degrade
    /// contract as every other AI-adjacent call in this file.
    func askMirror(question: String, userId: String) async -> MirrorAskResult? {
        guard let token = await idToken() else { return nil }

        var request = URLRequest(url: URL(string: Self.mirrorAskURLString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["question": question])
        request.timeoutInterval = 30

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 402 {
            // Spilr Pro gate (preview over) — same handling as geminiProxy's 402.
            Self.handlePaymentRequired(data)
            return nil
        }
        guard http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = root["answer"] as? String, !answer.isEmpty
        else { return nil }

        let citations = (root["citations"] as? [[String: Any]] ?? []).compactMap { c -> MirrorAskCitation? in
            guard let itemId = c["itemId"] as? String, let quote = c["quote"] as? String,
                  !itemId.isEmpty, !quote.isEmpty else { return nil }
            return MirrorAskCitation(itemId: itemId, quote: quote, date: c["date"] as? String)
        }
        return MirrorAskResult(answer: answer, citations: citations)
    }

    // MARK: - Narrative synthesis (Prompt F, mirror-narrative-v1)

    /// Generates a 3-4 sentence psychological sketch from the top hypotheses.
    /// Returns nil on failure — never throws. Cached weekly by the caller.
    // MARK: - generateMirrorNarrative — DELETED (Mirror v3, Week 6)
    //
    // Prompt F (mirror-narrative-v1) and its prompt/parser helpers are gone.
    // This was the LAST client-side LLM call on the Mirror surface: a third
    // prose writer over the same `patternHypotheses` the server already writes
    // Mirror cards and the weekly letter from, generating on tab open, with no
    // output lint beyond a banned-term check.
    //
    // §5.5's weekly letter replaces it — same job, but built on counted facts
    // plus exactly one deterministic observation, linted against the full §6
    // copy contract, dated, and archived so last month's is still readable.
    // `SelfModelViewModel.loadNarrative` now only READS a narrative that was
    // generated before this shipped.

    // MARK: - Life context injection

    /// Not private: Daily Chat reads this too (`nextChatTurn`), not just Mirror's
    /// own prompt builders below — see ai-cost-audit-2026-09-06.md follow-up on
    /// chat context. Both read the same UserDefaults-cached block; `cacheLifeContext`
    /// is what keeps it fresh, called from both Mirror's and Chat's load paths.
    func lifeContextBlock() -> String {
        UserDefaults.standard.string(forKey: "cachedLifeContextBlock") ?? ""
    }

    /// The raw `sensitiveTopicsDisabled` list, cached alongside the prose
    /// block above. Chat's Person Model context (`PersonModelChatContext`)
    /// needs the actual strings to apply as a deterministic code gate — the
    /// prose block's "DO NOT surface patterns about: …" is an instruction to
    /// the model, which the privacy PRD is explicit is not the same thing as
    /// enforcement.
    func sensitiveTopicsDisabledCached() -> [String] {
        UserDefaults.standard.stringArray(forKey: "cachedSensitiveTopicsDisabled") ?? []
    }

    /// Call once at load time to cache the rendered life context block.
    static func cacheLifeContext(_ ctx: LifeContext) {
        UserDefaults.standard.set(ctx.sensitiveTopicsDisabled, forKey: "cachedSensitiveTopicsDisabled")
        guard ctx.currentSeason != nil || !ctx.primaryFocus.isEmpty || !ctx.peopleLikelyToAppear.isEmpty else {
            UserDefaults.standard.removeObject(forKey: "cachedLifeContextBlock")
            return
        }
        var lines: [String] = []
        if let season = ctx.currentSeason { lines.append("Life season: \(season.rawValue.replacingOccurrences(of: "_", with: " "))") }
        if !ctx.primaryFocus.isEmpty { lines.append("Focus areas: \(ctx.primaryFocus.joined(separator: ", "))") }
        if !ctx.peopleLikelyToAppear.isEmpty {
            lines.append("People in their life: \(ctx.peopleLikelyToAppear.joined(separator: ", "))")
        }
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
        - For "people": list at most 5 people actually named in the entry, by
          first name or nickname exactly as the writer used it — never a
          surname, and never someone the writer didn't name. "role" is the
          part they play in this entry (e.g. "fixer", "the one I lean on"),
          optional if nothing specific fits. Omit entirely if no one is named.

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
          "people": [{"name":"first name or nickname as written, max 5","role":"optional, e.g. fixer"}],
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

        // Cap at 5 and de-dupe by lowercased name (last mention wins, keeping
        // whatever role text came with it) — the prompt already asks for
        // this, but a model can still ignore instructions.
        var peopleByName: [String: PersonMention] = [:]
        var peopleOrder: [String] = []
        for dict in (json["people"] as? [[String: Any]] ?? []) {
            guard let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let key = name.lowercased()
            if peopleByName[key] == nil { peopleOrder.append(key) }
            peopleByName[key] = PersonMention(name: name, role: dict["role"] as? String, mentions: 1)
        }
        let people: [PersonMention] = peopleOrder.prefix(5).compactMap { peopleByName[$0] }

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
            people:               people,
            openLoops:            openLoops,
            phrasesToTrack:       phrasesToTrack,
            possibleTinyAct:      possibleTinyAct,
            episodes:             episodes,
            promptVersion:        "mirror-extract-v2"
        )
    }
}
