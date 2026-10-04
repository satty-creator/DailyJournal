# Spilr — Privacy Policy

**Last updated: 27 September 2026**

> **Maintainers:** this is the hostable copy of the text in
> `DailyJournal/App/PrivacyPolicyView.swift`. App Store Connect requires a publicly
> reachable privacy policy URL for the product page, which the in-app view does not
> satisfy — publish this file and paste that URL into App Store Connect.
> **Keep the two copies in sync.** Every claim here was written against the code; if
> you change what the app stores, change both files in the same commit.

---

## The short version

You write private things here, so you should know exactly where they go.

What you write is stored in your account on our servers, and it is linked to your
account — that is how it is still there tomorrow and on your other devices. It is not
anonymous, and we are not going to pretend it is.

Nobody else reads it. We do not sell it, we do not advertise against it, and we do not
use it to train AI models. You can delete all of it, permanently, from Settings.

---

## What we store

**Your entries.** The full text of everything you write, plus any title, tags, mood and
photo attached to it. Stored under your account.

**What we work out from your entries.** To make Today's Read, Echoes, Mirror and
Patterns work, the app derives and saves things like recurring themes, emotional
vocabulary, short quotes lifted from your own entries, and the names of people or places
you mention. These are stored under your account too. They are not anonymised or pooled
with other users.

**Your account details.** Email address, display name, sign-in method, time zone, and
the notification token for your device.

**Your Google Calendar, if you connect it.** This is entirely optional and off by
default. If you connect it, the app reads your primary calendar's event titles, times,
and locations, directly from Google, to show them to you in Spilr's own Calendar view.
We request read-only access and never create, edit, or delete anything on your calendar.
This data is not stored on our servers and not sent to any AI — it's fetched live from
Google each time you open the Calendar view, and only stays in memory on your device.
You can disconnect at any time from Settings, or revoke access entirely from your Google
Account's permissions page.

Spilr's use and transfer of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements. We use Google Calendar data only to show your
events to you in the app. We do not transfer it to anyone, use it for advertising, or
use it to train AI models, and no person at Spilr reads it.

That is the whole list. We do not collect your contacts, your location (beyond what
you've chosen to put in a connected calendar event), your health data, or your activity
in other apps.

---

## Who can see it

**You.** Other users cannot see your entries, and there is no social feed, following, or
sharing by default.

**Our infrastructure providers, as processors.** Your data lives in Google Firebase
(Firestore, Authentication, Cloud Storage, Cloud Functions).

**Us, in narrow circumstances.** Technically we hold the keys to the database, so we
could read your entries. We do not, as a matter of practice: no employee browses user
journals. We would only access specific data if you asked us to for support, or if we
were legally compelled. Your entries are not encrypted in a way that would make us
unable to read them — see "What we have not built".

**Nobody else.** We do not sell, rent, or share your data with advertisers, data
brokers, or analytics companies.

---

## AI, and what it is sent

The reflective features are powered by Google Gemini, reached through our own server so
that no AI key ever sits in the app.

**When AI Insights is on,** the text of your recent entries is sent to Gemini to
generate reflections, questions and patterns. Google processes it to return a result and
does not use it to train their models. We do not keep a separate copy of the prompt.

**When AI Insights is off,** nothing is sent to Gemini. The app falls back to on-device
logic, and every feature still works — just more simply. You can switch this in Settings
at any time.

**What the AI is not.** It is not a therapist, a doctor, or a diagnostic tool. It is
instructed never to diagnose you, never to use clinical language, and never to treat a
repeated feeling as a medical conclusion. It is a language model and it can still get
things wrong — if something it says does not sound like you, it isn't you, and you can
tell it so.

---

## Deleting your data

**Settings → Delete account** permanently erases your entries, everything derived from
them, your photos, and your account itself. It is immediate and it is not recoverable —
there is no restore.

If you want a copy of your data, or want specific entries removed rather than all of
them, email support@getspilr.com and we will do it by hand. There is no self-service export
in the app yet.

---

## What we have not built

We would rather tell you this than let you assume otherwise.

**Your entries are not end-to-end encrypted.** They are encrypted in transit and
encrypted at rest by our hosting provider, which is standard — but we hold the keys, not
you. A journal that only you could ever decrypt is a genuinely better design and it is
not what ships today.

**There is no in-app data export yet.** Ask us and we will send it.

We will update this page when either of those changes, rather than quietly leaving it
vague.

---

## Children

Spilr is not intended for anyone under 13, and we do not knowingly collect data from
children. If you believe a child has created an account, email us and we will delete it.

---

## Changes to this policy

If we change how we handle your data, we will update this page and the date at the top,
and surface a notice in the app rather than relying on you to re-read it.

---

## Contact

Questions, deletion requests, or a copy of your data: **support@getspilr.com**

If you are in the UK or EU, journal content counts as special-category data under
UK-GDPR / GDPR Article 9, and you have rights of access, correction, erasure and
objection. Email us and we will action it. The data controller is the publisher of
Spilr; processing by Google Firebase and Gemini is governed by our agreement with
Google Cloud.
