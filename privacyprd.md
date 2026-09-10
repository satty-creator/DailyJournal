# Privacy & Trust PRD (Phase 0)

## Goal

Journal text is special-category health-adjacent data. Users must be able to trust the app before they will share anything real. Privacy and trust features are Phase 0 — they are prerequisites for every AI feature, not add-ons.

The design goal is: encryption and delete are table stakes, not differentiators. The differentiator is the clarity of what the app does and does not do with the data.

> **⚠️ This PRD describes intent, not current behaviour.** Several sections below —
> including At-Rest Encryption — specify a system that is not implemented. As of
> 2026-08-13 entry `content` is written to Firestore as **plaintext** under
> `users/{uid}/entries`, no `raw_text_encrypted` field exists, and there is no
> Keychain key anywhere in the app. Do not cite this document as a description of
> what ships. Export has been removed from scope entirely (see below).

---

## At-Rest Encryption

Journal text is encrypted on-device before being written to Firestore. The encryption key never leaves the device.

**Encrypted fields**

| Document | Field |
|---|---|
| `JournalEntry` | `content` |
| `EntryAnalysis` | `rawText` |

**Mechanism**

- AES-GCM, per-user symmetric key.
- Key stored in the iOS Keychain, scoped to the app.
- Firestore stores the ciphertext as `raw_text_encrypted` (Base64-encoded).
- Decryption happens on-device only, immediately before an AI call that requires the raw text (e.g., Prompt A on save).

**Hard design constraint: no raw text server-side**

Server-side mining (SM-1, Prompt B, Prompt C, Prompt CE) operates ONLY on structured EntryAnalysis fields — `inferredEmotions`, `protectiveStrategies`, `lifeDomains`, etc. Raw decrypted text is never sent to a Cloud Function or stored in a server-readable field.

This is not a preference — it is a structural constraint. If any server mining path required raw text, the privacy story would collapse. The EntryAnalysis schema exists precisely to make rich server-side inference possible without raw text.

If Prompt A (which runs client-side) needs the raw text to produce EntryAnalysis, it decrypts locally, calls the proxy, and the proxy receives the plaintext in the request body over HTTPS. The proxy does not log or store it. The response is the structured EntryAnalysis object.

---

## AI Depth Controls

Users control how deeply the AI infers from their entries.

**Setting name:** AI Depth  
**Options:** Gentle / Balanced / Deep  
**Storage:** user profile document at `users/{uid}/settings.aiDepth`

| Depth | What the AI may infer |
|---|---|
| Gentle | Explicit emotions only (named by the user), explicit needs only. No inference beyond what the user stated. |
| Balanced | Default. Inferred emotions (with confidence), needs, protectiveStrategies, avoidanceMarkers, cognitivePatterns — all at standard thresholds. |
| Deep | Full inference including cognitivePatterns, valuesConflict, protectiveStrategies at lower confidence thresholds, bodySignals, innerParts. |

Prompt A receives the `aiDepth` setting and applies it to determine which EntryAnalysis fields to populate. Fields outside the permitted depth are left null and not included in downstream prompts.

**Implementation note:** this is a client-side gate applied before prompt assembly, not a post-hoc filter on the LLM output.

---

## Quote Controls

**Setting name:** Use exact quotes  
**Type:** Toggle  
**Default:** On  
**Storage:** `users/{uid}/settings.useExactQuotes`

When Off:

- Evidence drawers in Today's Mirror show paraphrases instead of verbatim text.
- "Show proof" receipts in MirrorCards show paraphrases.
- NBQ-generated Mirror Seeds do not include verbatim phrases from past entries.

When On (default): verbatim quotes are used throughout.

This setting allows users who are uncomfortable seeing their own words reflected back to still receive insights, just at a paraphrase level.

---

## Name Tracking

**Setting name:** Track people names  
**Type:** Toggle  
**Default:** On  
**Storage:** `users/{uid}/settings.trackPeopleNames`

When Off:

- `peopleLikelyToAppear` from LifeContext is ignored in all prompts.
- Entity extraction (relationshipRoles, the people-names part of phrasesToTrack) is suppressed in Prompt A and SM-1.
- The `relationshipRoles` section of the Self Model is not populated.

This is enforced as a pre-prompt code gate, not as an instruction to the model.

---

## sensitiveTopicsDisabled

**Source:** LifeContext field `sensitiveTopicsDisabled[]`  
**Enforcement:** deterministic code gate, not a model instruction

Before any prompt is assembled, the app checks `sensitiveTopicsDisabled`. If a topic appears in this list:

1. All EntryAnalysis fields related to that topic are stripped from the prompt context before the LLM sees it.
2. The topic label is added to a `doNotAnalyse` array that is included at the top of every prompt.
3. Any PatternHypothesis or SelfModelHypothesis touching that topic is suppressed from all UI surfaces.

This means the model never processes the topic — not just "asked not to." The enforcement is in Swift code, not in the system prompt.

---

## Export — not in scope

Data export is **not a planned feature** and no code implements it. The previous
version of this section specified a JSON export delivered via the Files app; it was
never built, and it has been removed rather than left as a standing promise.

If export is revived, note the two dependencies the old spec assumed and that do not
exist: there is no `raw_text_encrypted` field and no Keychain key, so there is nothing
to decrypt — entry `content` is stored in Firestore as plaintext.

**Consequence to track:** UK-GDPR Article 15 gives users a right of access to their
personal data, and journal content is special-category data under Article 9. Without
export, that right has to be serviced manually on request (via support@spilr.app).
That is legally workable at current scale but does not scale, and it is a gap to
close before any enterprise or EU-facing commitment.

---

## Delete

### Full account deletion — implemented

**Entry point:** Profile → "Delete account" (destructive button, confirmation dialog required).

**What is deleted**

All data is stored as subcollections under `users/{uid}`. The following collections are batch-deleted before the Firebase Auth user record is removed:

| Subcollection | Content |
|---|---|
| `entries` | JournalEntry documents |
| `entryAnalyses` | EntryAnalysis documents |
| `patternHypotheses` | Pattern hypothesis documents |
| `patternCallbacks` | Pattern callback cards |
| `selfModel` | Self-model document (`current`) |
| `profileCorrections` | Profile correction documents |
| `lifeContext` | Life context document (`current`) |
| `mirrors` | Mirror card documents |
| `reads` | Today's Read receipts |
| `echoes` | Echo documents |
| `moods` | Mood log documents |

After all subcollections are cleared the root `users/{uid}` document is also deleted, followed by the Firebase Auth user record.

**Apple Sign In users — token revocation**

Apple requires `Auth.auth().revokeToken(withAuthorizationCode:)` before deleting an Apple-linked account (App Store guideline 5.1.1v). For users who signed in with Apple, tapping "Delete account" presents a one-time Sign in with Apple sheet to obtain a fresh `authorizationCode`. The code is passed to `revokeToken` before calling `user.delete()`.

**Re-authentication requirement**

Firebase requires a recent sign-in (within ~5 minutes) before `user.delete()` succeeds. If the session is stale the delete call throws `requiresRecentLogin` and the user is shown: *"For your security, please sign out and sign back in before deleting your account."*

**Keychain encryption key**

The at-rest encryption key is scoped to the app and is removed automatically when the app is uninstalled. Explicit in-app Keychain deletion on account delete is a planned improvement (tracked separately).

**Implementation**

- `AuthService.deleteAccount(appleAuthorizationCode:)` — batch-deletes Firestore data, revokes Apple token if applicable, then calls `user.delete()`.
- `AuthViewModel.deleteAccount(appleAuthorizationCode:)` — drives UI state (`isDeletingAccount`, `deleteErrorMessage`). The auth state listener fires `.unauthenticated` automatically after deletion.
- `ProfileView` — shows the "Delete account" row, confirmation dialog, and (for Apple users) the re-auth sheet.

No undo is offered — deletion is permanent and immediate.

---

### Delete Self Model only (PI-008)

Clears:

- `selfModel/current`
- All `profileCorrections/` documents

Preserves all journal entries, EntryAnalysis documents, MirrorCards, and PatternHypotheses.

This option appears separately from full delete in settings, clearly labelled: "Delete my self model" with a description: "Removes Spilr's hypotheses about you. Your journal entries are kept."

*Status: designed, not yet implemented.*

---

## LifeContext Privacy

LifeContext is stored at `users/{uid}/lifeContext` — a separate document from entries and the Self Model.

- Not mixed with entry content in any document.
- Separately deletable: "Clear my context" option in settings removes `lifeContext` without touching entries or the Self Model.
- Not included in analytics events.
- `sensitiveTopicsDisabled` within LifeContext is the authoritative list for content filtering — it is not derived from entry content.

---

## Analytics Events

The following analytics events are required for product audit and trust verification. Raw journal content must never appear in any analytics event.

| Event | Fields logged |
|---|---|
| `entry_analyzed` | entryId, aiDepth, promptVersion, durationMs, episodeCount, fieldCount |
| `pattern_mined` | runId, hypothesisCount, patternTypes[], promptVersion |
| `mirror_generated` | mirrorDate, hypothesisId, patternType, promptVersion, safetyGatePassed |
| `self_model_updated` | version, operationCounts{add,strengthen,weaken,retire}, correctionCount |
| `correction_applied` | correctionId, targetHypothesisId, category, updateProfile |

No event may include: raw journal text, EntryAnalysis rawText, hypothesis text that is derived from raw text without CE-pass, or any personally identifying information beyond the Firebase UID (which is already tied to the authenticated session).

---

## Compliance

**UK-GDPR / ICO**

Journal content is health-adjacent special-category data under UK-GDPR Article 9. Processing requires explicit consent (collected at onboarding) and a lawful basis. Users have the right to access, rectify (Teach Spilr / ProfileCorrection), erase (Delete), and object to processing (AI Depth: Gentle, sensitiveTopicsDisabled).

Note: the right of access is **not** serviced by an in-app export — that feature is out
of scope (see Export above) — and must be handled manually via support until built.

The data controller is the app publisher. Processing by the Gemini proxy is governed by the terms of the Firebase / Google Cloud agreement.

**FTC Health Breach Notification Rule**

The FTC's Health Breach Notification Rule (16 CFR Part 318) applies to non-HIPAA health apps that handle personal health records. Spilr is a journaling app, not a health provider — but to the extent users record health-adjacent information (mood, symptoms, mental states), the FTC Rule is relevant. A breach of encrypted journal data must be notified to affected users and the FTC within 60 days.

**FDA Software as a Medical Device (SaMD)**

Spilr is positioned as a self-reflection tool, not a diagnostic or treatment tool. The Mirror Engine's language rules (no disorder names, no diagnosis, no medical advice) and the Safety guard (Prompt E) maintain this positioning. If Spilr were to claim to diagnose, treat, or predict a clinical condition, it would require FDA oversight under the Software as a Medical Device guidance. It does not make such claims.

**AI Act (EU)**

Spilr does not profile users for consequential decisions (employment, credit, healthcare access) and does not use biometric identification. It is not a high-risk AI system under the EU AI Act. The transparency requirement (users must know they are interacting with an AI) is met via the onboarding disclosure and the in-app AI attribution on every Mirror card.
