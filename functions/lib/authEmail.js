/* Branded auth emails (verify address, reset password).
 *
 * Why these exist: Firebase locks template editing on new projects ("Email
 * template updates are currently unavailable for this project"), so the
 * built-in emails ship with a raw 400-character URL, a "noreply" sender and
 * Firebase's stock copy. That combination reads as phishing and lands in
 * spam. `sendAuthEmail` (index.js) generates the same action links with the
 * Admin SDK and sends these instead.
 *
 * Pure — no network, no Admin SDK — so it's covered by test/authEmail.test.js.
 */

"use strict";

// Where the app handles verify links. The domain's apple-app-site-association
// claims /*, so with the app installed iOS opens it straight into
// `AuthViewModel.handleVerificationLink`; in a browser, public/auth/action.html
// applies the code. Reset links are NOT rewritten: the app has no reset UI, and
// sending them here would open the app and do nothing.
const VERIFY_ACTION_URL = "https://spilr-100f7.web.app/auth/action";

// AppTheme "paper" / "ink" / "inkSoft" / "terracottaDeep".
const C = {
  paper: "#FFF8F2",
  card: "#FFFDFB",
  ink: "#2B2440",
  inkSoft: "#766F84",
  accent: "#E0567C",
};

/** Moves a Firebase-generated verify link onto our own action page, keeping
 *  its query (mode, oobCode, apiKey, continueUrl, lang) intact. */
function rewriteVerifyLink(firebaseLink) {
  const u = new URL(firebaseLink);
  return VERIFY_ACTION_URL + u.search;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** First name only, trimmed, capped — it goes in a greeting, not a letterhead. */
function greetingName(displayName) {
  const first = String(displayName || "").trim().split(/\s+/)[0] || "";
  return first.slice(0, 40);
}

const COPY = {
  verifyEmail: {
    subject: "Confirm your email for Spilr",
    heading: "One tap and you're in",
    body: "Confirm this is your email address so we can keep your journal safe and help you get back into it if you ever lose access.",
    button: "Confirm email",
    footer: "If you didn't create a Spilr account, you can ignore this email — nothing will happen.",
  },
  resetPassword: {
    subject: "Reset your Spilr password",
    heading: "Reset your password",
    body: "We got a request to reset the password for your Spilr account. Tap below to choose a new one. The link expires in an hour.",
    button: "Choose a new password",
    footer: "If you didn't ask for this, you can ignore this email — your password won't change.",
  },
};

/**
 * @param {"verifyEmail"|"resetPassword"} kind
 * @param {{ link: string, displayName?: string }} opts  link must already be final
 * @returns {{ subject: string, html: string, text: string }}
 */
function buildAuthEmail(kind, { link, displayName }) {
  const copy = COPY[kind];
  if (!copy) throw new Error(`Unknown auth email kind: ${kind}`);
  const name = greetingName(displayName);
  const hello = name ? `Hi ${name},` : "Hi there,";
  const href = escapeHtml(link);

  const text = [
    hello,
    "",
    copy.body,
    "",
    `${copy.button}: ${link}`,
    "",
    copy.footer,
    "",
    "— Spilr",
  ].join("\n");

  // Table layout + inline styles: the only thing every mail client renders.
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light">
<title>${escapeHtml(copy.subject)}</title>
</head>
<body style="margin:0;padding:0;background:${C.paper};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.paper};">
<tr><td align="center" style="padding:32px 16px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:${C.card};border-radius:20px;">
  <tr><td style="padding:36px 32px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:${C.ink};">
    <div style="font-size:30px;font-style:italic;font-weight:700;letter-spacing:-0.5px;margin-bottom:28px;">spilr.</div>
    <h1 style="font-size:22px;line-height:1.3;margin:0 0 16px;font-weight:700;">${escapeHtml(copy.heading)}</h1>
    <p style="font-size:16px;line-height:1.6;margin:0 0 8px;">${escapeHtml(hello)}</p>
    <p style="font-size:16px;line-height:1.6;margin:0 0 28px;">${escapeHtml(copy.body)}</p>
    <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:999px;background:${C.accent};">
      <a href="${href}" style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:999px;">${escapeHtml(copy.button)}</a>
    </td></tr></table>
    <p style="font-size:13px;line-height:1.6;color:${C.inkSoft};margin:28px 0 0;">${escapeHtml(copy.footer)}</p>
  </td></tr>
  </table>
  <p style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;color:${C.inkSoft};margin:20px 0 0;">Spilr · your private journal</p>
</td></tr>
</table>
</body>
</html>`;

  return { subject: copy.subject, html, text };
}

module.exports = { buildAuthEmail, rewriteVerifyLink, greetingName, VERIFY_ACTION_URL };
