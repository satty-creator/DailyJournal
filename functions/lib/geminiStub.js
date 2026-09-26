/* geminiStub.js — canned Gemini responses for the LOCAL EMULATOR ONLY.
 *
 * The iOS UI tests (DailyJournalUITests) run the app against the Firebase
 * Emulator Suite so they never touch production data, never spend model
 * money, and never flake on model output. geminiProxy returns these instead
 * of calling Gemini when BOTH are true:
 *   - FUNCTIONS_EMULATOR === "true"   (set by the emulator itself; never in prod)
 *   - SPILR_GEMINI_STUB  === "1"      (set by scripts/run-e2e.sh)
 * Everything BEFORE the upstream call — auth, the Spilr Pro gate, the 402s —
 * still runs for real, which is the part the tests exist to exercise.
 */

"use strict";

const STUB_CHAT_REPLY = "What part of that stayed with you most?";

function isStubEnabled(env = process.env) {
  return env.FUNCTIONS_EMULATOR === "true" && env.SPILR_GEMINI_STUB === "1";
}

function stubText(surface, wantJSON) {
  if (!wantJSON) {
    if (surface === "chat_turn" || surface === "chat_turn_cbt") return STUB_CHAT_REPLY;
    return "Today I wrote about what was on my mind, and it felt lighter after.";
  }
  if (surface === "journal_insights") {
    return JSON.stringify({
      bullets: [
        "You name the pressure, then move straight past it.",
        "The small thing at the end carries more weight than the list.",
      ],
      anchors: ["", ""],
      question: "What would today have looked like without the list?",
      sentiment: "Reflective",
    });
  }
  return "{}";
}

/** A response in Gemini's generateContent shape, so client parsers run unchanged. */
function stubGeminiResponse(surface, generationConfig) {
  const wantJSON = !!(generationConfig && generationConfig.responseMimeType === "application/json");
  return {
    candidates: [{
      content: { role: "model", parts: [{ text: stubText(surface, wantJSON) }] },
      finishReason: "STOP",
    }],
    usageMetadata: { promptTokenCount: 1000, candidatesTokenCount: 100, totalTokenCount: 1100 },
  };
}

module.exports = { isStubEnabled, stubGeminiResponse, STUB_CHAT_REPLY };
