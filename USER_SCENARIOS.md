# User scenarios — regression catalogue

Every user-visible scenario in Spilr, written as Given/When/Then so anyone —
not just someone reading test code — can tell what the app is supposed to
do. This is step 1 of a two-step pass: once this list is reviewed and
pruned, step 2 turns the ones that matter most into actual automated tests.

`TESTING.md` explains how the test suite is laid out. `MIRROR_V3_TEST_CASES.md`
is the deeper manual pass on Mirror specifically — whether the generated
*sentences* are worth reading, which nothing here checks; this list only
covers whether Mirror mechanically produces the right thing.

Two scoping decisions carried over from how this list will be automated,
noted here because they shape a few scenarios below:
- **Mirror** scenarios assume Gemini is stubbed on the server side too, the
  same way it already is for the app's own calls — no scenario here should
  ever cost real API money to run.
- **Photo** scenarios check that a photo renders from the local cache, not
  that it made a real round trip through cloud storage.

---

## 1. Launch & routing

**Opening the app signed out**
Given the user has no session
When they open the app
Then they land on the sign-in screen.

**Opening the app with an unverified email**
Given the user is signed in but hasn't verified their email
When they open the app
Then they land on the "verify your email" screen, not on Today.

**Opening the app before onboarding is finished**
Given the user is signed in, verified, and hasn't completed onboarding
When they open the app
Then they land on the welcome step of onboarding.

**Opening the app as a returning user**
Given the user is signed in, verified, and has completed onboarding
When they open the app
Then they land on the Today tab.

**Being asked about AI once**
Given the user has never been asked whether AI can read their entries
When they reach the main app
Then a sheet asks them to turn AI features on or keep things local-only.

**Turning AI on**
Given that AI consent sheet is showing
When the user taps "Agree & Enable AI Features"
Then the sheet closes and AI features are available from then on.

**Keeping things local-only**
Given that AI consent sheet is showing
When the user taps "Use local insights only"
Then the sheet closes and no AI features run — surfaces that would show AI
insight simply show nothing.

**The paywall waits for that decision**
Given the user has just finished onboarding and hasn't answered the AI
consent sheet yet
When the app goes to show the onboarding paywall
Then it waits until the AI decision is made before showing it. (Onboarding
now asks AI consent itself, as its own step — this only still matters for
whatever edge case reaches MainTabView with no decision on file.)

**Quitting mid-onboarding**
Given the user completed the goals and struggle steps, then quit before
finishing onboarding
When they reopen the app
Then they land back on the welcome step, but their goals and struggle answers
are pre-filled when they reach those steps again — each step's answer is only
remembered once they've actually advanced past it.

## 2. Signing up, signing in, signing out

**Signing up with an empty form**
Given the user is on the sign-up screen
When they submit with no email or password filled in
Then they see a validation error and nothing is sent to the server.

**Signing up with a malformed email**
Given the user is on the sign-up screen
When they enter something without an "@" as their email
Then they see a validation error.

**Signing up with too short a password**
Given the user is on the sign-up screen
When they enter a password under 6 characters
Then they see a validation error.

**Signing up with mismatched passwords**
Given the user is on the sign-up screen
When their password and confirmation don't match
Then they see a mismatch message and can't submit.

**Signing up successfully**
Given the user fills in a valid, unused email and a matching password
When they submit
Then their account is created and they land on the "verify your email"
screen.

**Signing in with the wrong password**
Given the user has an existing account
When they enter the wrong password
Then they see an error and stay on the sign-in screen.

**Signing in successfully**
Given the user has a verified account
When they sign in with the right credentials
Then they land on Today (or onboarding, if they never finished it).

**Forgetting a password**
Given the user is on the sign-in screen
When they tap "Forgot password?" and submit their email
Then they see a confirmation that a reset email was sent.

**Resending a verification email**
Given the user is stuck on the "verify your email" screen
When they tap resend
Then a new email is sent and the resend button is disabled for a short
cooldown.

**Continuing before actually verifying**
Given the user's email is still unverified
When they tap "I've verified — continue" without having verified
Then they stay on the verification screen.

**Continuing after verifying**
Given the user has clicked the link in their verification email
When they tap "I've verified — continue"
Then they're let through to the rest of the app.

**Switching accounts from the verification wall**
Given the user is stuck on the verification screen
When they tap "Use a different account"
Then they're signed out and back on the sign-in screen.

**The App Review demo account never bypasses the paywall**
Given the account is the one Apple's reviewers use
When it uses AI features
Then it still sees the paywall like any ordinary user — it gets no owner
treatment.

**The owner's own account bypasses the paywall**
Given the account belongs to the app's owner
When they use AI features
Then they never see the paywall, however much they've used.

**Signing out**
Given the user is signed in
When they sign out from Profile
Then they land on the sign-in screen, and reopening the app doesn't sign
them back in.

**Signing in with Google** — manual check only.

**Signing in with Apple** — manual check only.

## 3. Onboarding

Onboarding is a short personal intake, not a 3-tap skim: welcome → goals →
struggle → people (optional) → baseline → tone → AI consent → guided first
entry → payoff → paywall.

**The welcome tour**
Given the user is on the welcome step
When they swipe through the 3 cards and tap "Get started"
Then they land on the goals step.

**Selecting a goal**
Given the user is on the goals step with nothing selected
When they tap one goal
Then Continue becomes tappable.

**No goal selected**
Given the user is on the goals step
When they haven't tapped anything
Then Continue stays disabled.

**Changing your mind about goals**
Given the user has selected two goals
When they tap one again to deselect it
Then only the remaining goal is kept.

**The struggle chips follow the chosen goals**
Given the user picked "Quiet my head at night" and "Make a decision I'm
stuck on" on the goals step
When they reach the struggle step
Then the chip list is the union of both goals' options, each shown once.

**Picking a struggle and adding detail**
Given the user is on the struggle step
When they tap a chip and optionally type something in "in your words"
Then Continue becomes tappable, and both are saved when they advance.

**A crisis signal in the struggle detail**
Given the user types something in "in your words" that trips the crisis-signal
gate (`PatternSafety.corpusHasCrisisSignal`)
Then a quiet, dismissible resource card appears inline on the same step, and
the guided first entry's opening question falls back to the static one
instead of being written by the model.

**Skipping the people step**
Given the user is on the "who's in your life" step
When they tap "Skip for now"
Then no people are saved and they move on to the baseline step.

**Naming a person**
Given the user taps the "partner" chip on the people step
When they type a name into the field that appears
Then that name (not just the role) is what's saved and later shown to Spilr.

**Setting the baseline**
Given the user is on the baseline step
When they tap a number from 0 to 10
Then Continue becomes tappable, and that value is logged as the first point
on the Mirror tab's heaviness chart once they advance.

**Tone is pre-selected from the goals**
Given the user picked "Quiet my head at night" and reaches the tone step for
the first time
Then "gentle" is already selected and marked as the suggestion (not always
"curious" — the suggestion follows whichever goal was picked).

**Picking a different tone**
Given the user is on the tone step
When they tap a different tone than the one suggested
Then that tone is saved, and going back to this step later keeps the user's
own choice rather than re-applying the suggestion.

**AI consent is an equal choice**
Given the user is on the consent step
When they read the two buttons, "Use AI reflections" and "Keep it local only"
Then neither reads as the "real" answer and the other as a decline — both are
the same size and weight.

**Going back**
Given the user is partway through onboarding
When they tap Back
Then they return to the previous step with their earlier choices intact.

**The guided first entry's question is written by Spilr**
Given the user granted AI consent and answered the goals/struggle/people/
baseline steps
When they reach the first-entry card
Then the question shown was written from those answers (not the old fixed
opener) — or, if it's still resolving, a brief "finding the right question…"
placeholder is shown first.

**The AI question never arrives**
Given AI consent was declined, or the call fails, or it doesn't resolve
within a few seconds of tapping "Answer it"
Then the guided entry opens on the same static fallback question either way
— indistinguishable to the user from an AI-written one.

**Skipping the first entry**
Given the user reaches the first-entry card
When they tap "I'll do this later"
Then onboarding finishes and they land on Today directly — no paywall.

**Backing out of the guided entry without saving**
Given the user opened the guided first entry and exits (X, "Save for later",
or "Discard answers") without completing it
Then they're back on the first-entry card and onboarding isn't finished — no
paywall yet either.

**Completing the guided first entry**
Given the user rates how heavy things feel, answers the 5 thought-record
steps, rates it again, and saves from the review screen
Then a journal entry is created with both ratings attached, and "Second
look" — the payoff screen — appears next, not the paywall directly.

**The payoff shows the delta only when it eased**
Given the "before" rating was higher than the "after" rating on the guided
entry
Then "Second look" shows "You came in at X, you're leaving at Y." A rise or
an unchanged rating shows no delta line at all.

**The payoff's reflection, with AI on**
Given AI consent was granted
Then "Second look" shows Spilr's bullets on what was written, via the same
placeholder → arrived → (rare) never-arrived states as the reflection on any
other entry.

**The payoff's reflection, with AI off or unavailable**
Given AI consent was declined, or the call fails or times out
Then "Second look" shows a short excerpt of the user's own entry instead of
any generated text — never a canned observation.

**Finishing onboarding through the guided entry queues the paywall**
Given the user completed "Second look" and tapped Continue
Then onboarding finishes and the Spilr Pro paywall is what they land on.

**The onboarding paywall only shows once**
Given the user has already seen and dismissed the onboarding paywall
When they relaunch the app
Then the paywall doesn't appear again.

**"Not yet" takes a moment to respond**
Given the onboarding paywall is showing
When the user immediately taps "Not yet"
Then there's a brief pause before it responds, then it works.

**Celebrating the first entry, written from Today**
Given the user skipped onboarding's guided entry and later writes their
first entry from Today
Then a celebration screen appears once, and never again after that.

**No duplicate celebration for the onboarding entry**
Given the user completed onboarding's guided first entry and saw "Second
look"
Then Home's separate first-entry celebration sheet never also appears for
that same entry.

**Seeing AI insight appear after saving (outside onboarding)**
Given the user just saved their first entry from Today and AI is available
Then a "reading what you wrote…" placeholder is replaced by real insight
bullets once Spilr's reply comes back.

**AI insight never arriving (outside onboarding)**
Given the user just saved their entry and the AI call fails or times out
Then the placeholder disappears after about 20 seconds and nothing
made-up takes its place.

## 4. Today (Home)

**Starting a chat from Today**
Given the user is on Today
When they tap "Type or talk"
Then Daily Chat opens (showing the one-time intro the first time).

**Writing a blank entry from Today**
Given the user is on Today
When they tap "Blank page"
Then a blank entry composer opens full-screen.

**Opening a template from Today**
Given the user is on Today
When they tap "Templates"
Then the template picker opens.

**Seeing how many days this week they've written**
Given the user has written on some days this week
Then the week-dots row shows exactly those days, no more and no fewer.

**Jumping to today's entry**
Given the user has already written today
When they tap the "written today" row
Then the Journal tab opens with that entry highlighted.

**Seeing a past letter or echo**
Given there's a scheduled letter that's arrived, or an Echo ready to show
Then the right one appears in Today's past slot.

**Jumping to Mirror from a notice**
Given Mirror has something new to show
When the user taps "Spilr noticed"
Then the Mirror tab opens.

**Undoing an auto-save**
Given something was just auto-saved in the background
When the user taps Undo on the toast that appears
Then that save is reverted.

**Seeing the crisis resource card**
Given something the user wrote trips the crisis-language safety check
Then a resource card appears, and no pattern insight is generated from that
entry.

## 5. Writing and editing entries

**Saving a plain entry**
Given the user is writing a new entry with no photo
When they save
Then the entry is created with no photo field at all.

**Saving an entry with a photo**
Given the user attaches a photo while writing
When they save
Then the photo shows up on the entry — checked against the local photo
cache, not by uploading to real cloud storage.

**Getting a different hint**
Given the composer is showing a suggested prompt
When the user taps the re-roll button
Then a different prompt appears.

**Mood and pebbles become tags**
Given the user picks a mood and some pebbles while writing
When they save
Then those become tags on the entry, up to five, alongside anything
detected from the text itself.

**Recovering an unsaved draft**
Given the user typed something and left without saving
When they come back to the composer
Then their draft text is still there.

**Writing a letter to your future self**
Given the user chooses to send an entry to their future self
When they save it
Then it's stored as a scheduled letter rather than an ordinary entry.

**Saving with no network** — manual check only.

**Seeing the card fall back gracefully**
Given AI insight failed or hasn't arrived for an entry
Then the entry's card shows its own title or an excerpt — never a made-up
or generic line standing in for real insight.

**No canned Spilr-voice text, ever**
Given AI is unavailable anywhere in the app
Then nothing presented as Spilr's own observation, question, or reflection
ever appears — the surface stays empty instead.

**Editing an entry's text**
Given the user opens an existing entry
When they change the text and save
Then the update is saved and the entry's "last updated" time changes.

**Editing an entry's tags**
Given the user is editing an entry's tags
When they add duplicates, mixed case, or more than five
Then the tags end up deduplicated, lowercased, and capped at five.

**Replacing an entry's photo**
Given an existing entry already has a photo
When the user picks a new one and saves
Then the new photo replaces the old one everywhere it's shown.

**An entry's content survives a save/reload round trip**
Given an entry with any content
When it's saved and then read back
Then the content comes back exactly as written.

**Reading an older, unencrypted entry**
Given an entry was written before encryption existed
When it's opened
Then it reads correctly as plain text, with no attempt to decrypt it.

**A corrupted entry doesn't crash the app**
Given a journal document is missing a required field
When the app tries to load it
Then it's skipped rather than crashing anything.

**An entry with no title falls back sensibly**
Given the user never gave an entry a title
Then its card shows the start of the entry's own text instead.

## 6. The journal list

**Remembering list vs. collage view**
Given the user switches to collage view
When they relaunch the app
Then it opens in collage view again.

**Searching entries**
Given the user has several entries
When they type into search
Then only matching entries are shown.

**Filtering by tag**
Given entries have different tags
When the user taps a tag chip
Then only entries with that tag show, and tapping "All" clears the filter.

**Entries are grouped by month, newest first**
Given entries span several months
Then the list groups them by month with the most recent month on top.

**A photo wins the collage tile**
Given an entry has both a photo and, say, a short quote
Then its collage tile shows the photo, not the quote.

**Deleting an entry**
Given the user long-presses an entry
When they choose Delete
Then it's gone from the list and from storage.

**Jumping to a highlighted entry**
Given the user navigated to the journal list from elsewhere in the app
Then the entry they came from is briefly highlighted.

**An empty journal**
Given the user has no entries yet
Then the list shows an empty state with a way to start writing.

**A photo appearing after it finishes uploading**
Given an entry was saved with a photo that's still uploading in the
background
When the upload finishes
Then the photo appears on the already-visible card without the screen
needing to reload.

## 7. Daily Chat & Thought Journal

**Seeing the intro once**
Given this is the first time the user opens chat from Today
Then a short intro to the Thought Journal appears, and never shows again
after that.

**Getting a reply**
Given the user sends a message
Then Spilr replies.

**A reply failing**
Given Spilr's reply fails to arrive
Then the user sees an inline "couldn't reach Spilr" message with a retry —
never a fabricated reply standing in.

**Wrapping up a session**
Given the conversation has gone on long enough
When the user taps "wrap up"
Then it moves into review/save.

**Choosing to keep talking**
Given the app has suggested wrapping up
When the user chooses to keep talking instead
Then the conversation continues.

**Saving a woven entry**
Given a chat session has ended
Then it's woven into a single journal entry that the user can review and
save.

**Weaving without AI**
Given the weaving step itself fails
Then the entry is still stitched together locally from exactly what the
user wrote — nothing invented is added.

**Closing a chat outside onboarding**
Given the user is mid-conversation outside the onboarding flow
When they tap close
Then it auto-saves without asking — no discard/keep prompt like onboarding
has.

**Resuming an unfinished session**
Given the user has an unfinished chat from earlier the same day
When they open chat again
Then they're offered the chance to resume it.

**A crisis message during chat**
Given the user writes something that clearly signals crisis
Then a resource card appears.

**A metaphor doesn't trigger the crisis flow**
Given the user writes something like "dying to see this movie"
Then nothing crisis-related is triggered.

**Attaching a photo in chat**
Given the user is in the chat composer
When they attach a photo
Then it behaves the same way attaching one in the entry editor does.

**Talking instead of typing in chat** — manual check only.

## 8. Mirror

*This section covers whether Mirror mechanically produces and shows the
right thing. Whether the sentences it writes are actually worth reading is
covered separately in `MIRROR_V3_TEST_CASES.md`.*

**Mirror while it's loading**
Given the user opens the Mirror tab
Then a loading indicator shows until it's ready.

**A brand-new account's Mirror**
Given the user has no self-model yet
Then Mirror shows its empty state rather than a broken or blank screen.

**A self-model with nothing to show yet**
Given a self-model exists but has no profile content
Then a distinct "nothing here yet" state shows, not the brand-new-account
one.

**Mirror unlocking gradually with more entries**
Given the user has written a given number of entries
Then Mirror's maturity level matches that count at each of its thresholds
(0, 1, 3, 7, 14, 30, 90 entries).

**Client and server agreeing on the unlock thresholds**
Given the app and the server both define when features unlock
Then their thresholds match — a mismatch would silently unlock something on
one side before the other.

**The "Ask" feature unlocking**
Given the user has fewer than five entries
Then "Ask your journal" isn't offered yet; once they reach five, it is.

**The weekly letter banner**
Given a new weekly letter is ready and unread
Then a banner appears for it; reading it clears the unread state.

**Mirror kicking off its first analysis**
Given a new-ish account has no hypotheses yet, AI is available, and it's
been at least a day since the last attempt
Then Mirror triggers analysis once — and won't trigger again immediately
after.

**Mirror respecting a used-up preview**
Given the user's free preview has run out
When Mirror would otherwise try to analyze their entries
Then it doesn't, and the user is routed to the paywall instead of getting a
silent failure.

**A full night's worth of Mirror generation**
Given a seeded account with real entries, and Gemini stubbed so no real API
call happens
When nightly generation runs
Then facts, observations, threads, the self-model, the person model and
Mirror cards are all produced, and the Mirror tab renders them.

**Mirror's underlying arithmetic**
Given a sample body of entries
Then the facts, first-seen dates, observations, readings, threads and decay
computed from them are all correct.

**Mirror showing why there's nothing new**
Given Mirror has nothing new to show
Then it says why — not enough hypotheses yet, below its confidence
threshold, or nothing novel since last time — rather than just looking
empty.

**Mirror assembling itself from hypotheses alone**
Given there's no server-built self-model yet but at least three hypotheses
exist
Then Mirror puts together a provisional self-model from those on its own.

**An entry analysis falling back locally**
Given the AI call to analyze a specific entry fails
Then a local fallback analysis is used instead of leaving the entry
unanalyzed.

**Deciding which insight is confident enough to show**
Given a candidate insight has a certain amount of supporting evidence and
history
Then it only gets shown once it clears the confidence bar for that kind of
insight.

**Mirror's writing passing its own style rules**
Given a candidate line for Mirror
Then it passes every one of Mirror's copy rules (length, must reference the
user's own words, no jargon, no hedging, ends with a real question where
required) before ever reaching the user.

**Finding real patterns worth surfacing**
Given a body of entries with a repeated or contrasting pattern in them
Then Mirror's mining correctly finds candidates like "you say X but do Y,"
"this happens across different situations," or "X seems to lead to Y" —
and doesn't invent one where there isn't enough evidence.

**Correcting Mirror**
Given the user tells Mirror a hypothesis is wrong
Then that hypothesis is suppressed and doesn't reappear until enough new,
contradicting evidence has piled up.

**Seeing the evidence behind a Mirror insight**
Given a hypothesis Mirror is showing
Then the entries that produced it are visible to back it up. (There's
currently no dedicated view for this in the app — see open questions.)

## 9. Echoes

**A low-confidence Echo is never shown**
Given the AI's confidence in a possible Echo is below the quality bar
Then no Echo is created from it.

**An Echo with nothing to quote is never shown**
Given the AI didn't actually produce a quotable line
Then no Echo is saved, however confident the model claims to be.

**Skipping an Echo**
Given an Echo is showing
When the user skips it
Then it's dismissed without being marked answered.

**Deferring an Echo**
Given an Echo is showing
When the user taps "Not yet"
Then it may resurface later rather than disappearing for good.

**Answering an Echo**
Given an Echo is showing
When the user answers it
Then their answer is written as a new entry once they close the answer
screen.

**Reading an entry and its Echo together**
Given the user has answered an Echo
When they choose "Read them together"
Then the original entry and the answer are shown side by side.

**Never more than one Echo at a time**
Given several Echoes are eligible to show
Then the user only ever sees one at a time, never a list.

## 10. Themes

**Opening the theme picker**
Given the user is in Profile
When they open Appearance
Then the theme picker opens.

**Applying a theme**
Given the theme picker is open
When the user taps a theme
Then the whole app's colors and fonts switch to it immediately.

**A theme choice persists**
Given the user picked a theme
When they relaunch the app
Then the same theme is still applied.

## 11. Profile, privacy & account

**Editing your display name**
Given the user is in Profile
When they edit their name and save
Then it's updated; canceling instead leaves it unchanged.

**Turning AI Insights off**
Given the user turns off AI Insights in Profile
Then no further AI calls happen anywhere in the app, and nothing canned
takes their place.

**Seeing what Spilr remembers**
Given the user opens "What Spilr remembers" from Profile
Then their memory profile is shown.

**Opening notifications settings** — manual check only (system permission
dialog).

**Reading the privacy policy**
Given the user taps the privacy policy link in Profile
Then it opens.

**Checking Pro status**
Given the user's subscription status
Then Profile always reflects it correctly, and tapping it opens the
paywall if they're not subscribed.

**Deleting the account**
Given the user confirms account deletion
Then the account and every piece of data it wrote — entries, echoes, chat
sessions, derived Mirror data, everything — is erased.

**No in-app data export exists today** — flagged in open questions rather
than as a scenario, since it's not clear whether this is intended.

## 12. Paywall & entitlements

**The paywall shows what App Review requires**
Given the paywall is showing
Then the trial terms, price, and cancellation terms are all stated clearly
and correctly for whichever plan is selected.

**Running out of free preview**
Given the user's free AI preview has been used up
When they try to use an AI feature
Then they're shown the paywall.

**Buying Pro**
Given the user picks a plan and completes purchase
Then their account is marked as paid and Profile reflects it immediately.

**The debug bypass never leaks into a real build**
Given a build is a real release build, not a developer's debug build
Then the "skip the paywall" shortcut used during development is completely
absent.

**The AI-limit paywall doesn't nag**
Given the user was just shown the paywall for hitting a usage limit
Then it won't show again for that reason for about 20 hours.

**A subscription event updates entitlement correctly**
Given RevenueCat reports a purchase, renewal, cancellation, or expiration
Then the user's access is updated to match, and a lapsed subscription is
enforced even if the "it expired" event never arrives.

## 13. AI safety and Spilr's voice

**Every reflective prompt carries the safety rules**
Given any prompt built for Echo, Mirror, or Read surfaces
Then it includes the safety rules that tell the model to return nothing
rather than something ungrounded or unsafe.

**Every chat prompt carries its own safety rules**
Given any prompt built for a live conversation
Then it includes the conversational safety rules, whose fallback is asking
a plain question rather than staying silent.

**Client and server safety rules staying in sync**
Given the safety rules exist in two places — the app and the server
Then the two copies say the same thing; a drift between them would be easy
to miss otherwise.

**The crisis check runs before any pattern analysis**
Given a body of entries that shows crisis signals
Then the safety check catches it before any pattern-insight call is made,
never after.

**An unsafe or empty model response shows nothing**
Given the model can't produce something safe and grounded
Then the surface it was meant for stays empty — never filled with a
fallback sentence in Spilr's voice.

## 14. Security rules

**A user can't make themselves paid**
Given a signed-in user
When they try to write directly to their own usage or entitlement record
Then it's rejected.

**A user can't touch the RevenueCat record**
Given a signed-in user
When they try to read or write the RevenueCat entitlement document
Then it's rejected.

**Rate limits are server-only**
Given a signed-in user
When they try to write to the rate-limit collection
Then it's rejected.

**Entries are private to their owner**
Given two different users
Then each can read and write only their own entries, never the other's.

**Signed-out access is refused entirely**
Given no one is signed in
Then every read is refused.

**Push tokens are private to their owner**
Given a signed-in user
Then they can save their own push token but not write one for someone
else.

**Derived Mirror data can't be forged by the client**
Given a signed-in user
When they try to write directly into their own derived-data documents
Then it's rejected — those are server-written only.

**Photos are private to their owner**
Given a signed-in user
Then they can read and write only their own uploaded photos in storage,
never another user's.

## 15. Working offline or when things fail

**Writing and browsing with no network** — manual check only.

**AI failing anywhere degrades silently**
Given AI is unavailable, wherever in the app that matters
Then the surface that would have shown AI insight simply shows nothing —
never a crash, never a placeholder pretending to be Spilr's voice.

**Saves never block the screen** — manual check only (needs artificial
network latency to observe).

---

## Open questions

These came up while writing the scenarios above and are product questions,
not scenarios to automate:

1. **First-entry celebration during onboarding.** The celebration logic
   only appears to be wired to entries written from Today, not to an entry
   written inside the onboarding chat itself. Worth confirming whether
   that's intended.
2. **`FirstSketchView` looks unused.** Nothing in the app currently shows
   it — worth confirming it's genuinely retired before writing scenarios
   for it.
3. **The "Today's Read" card views look unused too**, aside from one static
   preview in the theme picker.
4. **Two chat-related prompts have no safety rules attached**
   (`summariseSession` and `extractModelOps`). One is gated by the crisis
   check upstream; the other doesn't appear to be — worth confirming that's
   deliberate.
5. **No in-app data export exists**, though the privacy PRD may describe
   one. Worth reconciling once PRD updates are back on (per CLAUDE.md's
   current pause).
6. **No evidence view exists for Mirror insights**, though the Mirror PRD's
   feature table describes one. Same PRD-vs-code note as above.
