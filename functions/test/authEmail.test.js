/* node:test — branded auth emails (lib/authEmail.js). */

"use strict";

const test = require("node:test");
const assert = require("node:assert");

const { buildAuthEmail, rewriteVerifyLink, greetingName, VERIFY_ACTION_URL } = require("../lib/authEmail");

const FIREBASE_LINK =
  "https://spilr-100f7.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=abc123&apiKey=KEY&continueUrl=https%3A%2F%2Fspilr-100f7.web.app%2F&lang=en";

test("rewriteVerifyLink moves the link onto our action page, query intact", () => {
  const out = rewriteVerifyLink(FIREBASE_LINK);
  assert.ok(out.startsWith(VERIFY_ACTION_URL + "?"));
  const q = new URL(out).searchParams;
  assert.strictEqual(q.get("mode"), "verifyEmail");
  assert.strictEqual(q.get("oobCode"), "abc123");
  assert.strictEqual(q.get("apiKey"), "KEY");
  assert.strictEqual(q.get("continueUrl"), "https://spilr-100f7.web.app/");
});

test("verify email has a real button link and a plain-text alternative", () => {
  const link = rewriteVerifyLink(FIREBASE_LINK);
  const { subject, html, text } = buildAuthEmail("verifyEmail", { link, displayName: "Satty K" });
  assert.strictEqual(subject, "Confirm your email for Spilr");
  assert.ok(html.includes(`href="${link.replace(/&/g, "&amp;")}"`));
  assert.ok(html.includes("Hi Satty,"));
  assert.ok(text.includes(link));
  assert.ok(!html.includes("%APP_NAME%"));
});

test("greeting falls back when there's no name, and escapes what there is", () => {
  assert.strictEqual(greetingName(""), "");
  assert.strictEqual(greetingName(undefined), "");
  const { html } = buildAuthEmail("resetPassword", { link: "https://x.test/?a=1", displayName: "<b>x</b>" });
  assert.ok(!html.includes("<b>x</b>"));
  assert.ok(buildAuthEmail("resetPassword", { link: "https://x.test/" }).html.includes("Hi there,"));
});

test("unknown kind throws", () => {
  assert.throws(() => buildAuthEmail("nope", { link: "https://x.test/" }));
});
