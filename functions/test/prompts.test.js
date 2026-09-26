/* node:test — the four prompt builders are pure string assembly; these tests
 * just confirm the interpolation points work and the verbatim instructions
 * survive, not that the model obeys them (that needs a live call).
 */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const {
  buildFormulationPrompt, buildNextQuestionPrompt, buildMirrorMPrompt, buildAskPrompt,
  DO_NOT_INFER_LINE,
} = require("../lib/prompts");

test("buildFormulationPrompt interpolates every block and keeps the hard rules", () => {
  const p = buildFormulationPrompt({
    safetyRules: "SAFETY", spilrVoice: "VOICE", lifeContext: "", styleRules: "",
    signalsBlock: "SIGNAL_MARKER", candidatesBlock: "CANDIDATE_MARKER",
    currentModelBlock: "MODEL_MARKER",
  });
  assert.ok(p.includes("SAFETY") && p.includes("VOICE"));
  assert.ok(p.includes("SIGNAL_MARKER"));
  assert.ok(p.includes("CANDIDATE_MARKER"));
  assert.ok(p.includes("MODEL_MARKER"));
  assert.ok(p.includes("A signature needs >= 3 entries"));
  assert.ok(p.includes(DO_NOT_INFER_LINE));
  assert.ok(p.includes('"retire"'));
});

test("buildNextQuestionPrompt names the banned self-analysis question", () => {
  const p = buildNextQuestionPrompt({
    safetyRules: "SAFETY", openHypothesesBlock: "H1", askedRecentlyBlock: "",
  });
  assert.ok(p.includes("H1"));
  assert.ok(p.includes("(none)"));
  assert.ok(p.includes("what's the pattern?"));
});

test("buildMirrorMPrompt carries the shape rules and the exact BAD/GOOD example", () => {
  const p = buildMirrorMPrompt({
    safetyRules: "SAFETY", spilrVoice: "VOICE", styleRules: "",
    itemBlock: "ITEM_MARKER", shape: "SIGNATURE", quotesBlock: "QUOTE_MARKER",
    testQuestion: "Q_MARKER",
  });
  assert.ok(p.includes("ITEM_MARKER") && p.includes("QUOTE_MARKER") && p.includes("Q_MARKER"));
  assert.ok(p.includes('"shape": "SIGNATURE"'));
  assert.ok(p.includes("An empty day turns into a project"));
});

test("buildAskPrompt quotes the user's question and cites the do-not-infer guard", () => {
  const p = buildAskPrompt({
    safetyRules: "SAFETY", question: "Why do I always end up doing everything?",
    modelBlock: "MODEL_MARKER",
  });
  assert.ok(p.includes('"Why do I always end up doing everything?"'));
  assert.ok(p.includes("MODEL_MARKER"));
  assert.ok(p.includes(DO_NOT_INFER_LINE));
});
