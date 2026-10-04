# Knowing when Gemini is failing

Spilr's AI all flows through the `geminiProxy` Cloud Function. When Gemini
itself errors or times out, the call already fails *safely* (surfaces render
nothing, chat shows an inline retry) — which is good for users but means a
sustained Gemini outage is otherwise **invisible**. This is how to get a metric
and an alarm.

## What the code already emits

**Server (`functions/index.js`, `geminiProxy`)** — every upstream Gemini failure
now logs a structured error to Cloud Logging:

```js
logger.error("gemini_upstream_failure", {
  event: "gemini_upstream_failure",
  uid, surface, timedOut, status, error,
});
```

Plus the normal `console.log("aiFinish", { finishReason, blockReason, … })` and
`console.log("aiUsage", …)` telemetry on success.

**Client (`AIService.swift` → Firebase Analytics)** — already fires:
`network_error` (timeout / no network), `ai_service_error` (non-2xx from the
proxy, with `status_code`), and `ai_insights_failed`.

Neither of these alarms on its own — that's the one-time setup below.

---

## Recommended: server-side log-based metric + alert (near-real-time, no app release)

Uses the structured log above. Run once (needs `gcloud` auth on the
`spilr-100f7` project and the Monitoring Admin role).

```bash
PROJECT=spilr-100f7
gcloud config set project "$PROJECT"

# 1. A log-based counter metric that counts Gemini failures.
gcloud logging metrics create gemini_upstream_failures \
  --description="geminiProxy upstream Gemini errors/timeouts" \
  --log-filter='resource.type="cloud_run_revision"
    resource.labels.service_name="geminiproxy"
    severity=ERROR
    jsonPayload.event="gemini_upstream_failure"'

# 2. A notification channel (email shown; Slack/PagerDuty also supported).
#    Skip if you already have one — list existing with:
#      gcloud beta monitoring channels list
gcloud beta monitoring channels create \
  --display-name="Spilr alerts" \
  --type=email \
  --channel-labels=email_address=satakshi1710@gmail.com
# Note the returned channel id: projects/$PROJECT/notificationChannels/XXXX
```

Then create the alert policy. Save as `gemini-alert-policy.json` (replace the
channel id), and apply it:

```json
{
  "displayName": "Gemini upstream failures spiking",
  "combiner": "OR",
  "conditions": [{
    "displayName": "gemini_upstream_failure > 5 in 5 min",
    "conditionThreshold": {
      "filter": "metric.type=\"logging.googleapis.com/user/gemini_upstream_failures\" resource.type=\"cloud_run_revision\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 5,
      "duration": "0s",
      "aggregations": [{
        "alignmentPeriod": "300s",
        "perSeriesAligner": "ALIGN_SUM"
      }]
    }
  }],
  "notificationChannels": ["projects/spilr-100f7/notificationChannels/XXXX"]
}
```

```bash
gcloud alpha monitoring policies create --policy-from-file=gemini-alert-policy.json
```

That's it — you'll get an email whenever more than 5 Gemini failures land in any
5-minute window. Tune `thresholdValue` / `alignmentPeriod` to taste. Because the
log carries `surface` and `timedOut`, you can add a second condition or group by
those in the Cloud Monitoring UI to tell "Gemini is down" from "one surface's
prompt is too slow".

> The Cloud Run service name is lower-cased (`geminiproxy`). If the filter
> returns nothing, confirm the exact name with:
> `gcloud logging read 'jsonPayload.event="gemini_upstream_failure"' --limit=1`

---

## Alternative: client-side Firebase alert (catches the user's-network-side failures too)

The server metric can't see failures that never reach the server (the user's
own connectivity). For that, in the Firebase console:

1. **Analytics → Custom definitions / Events** → mark `ai_service_error` (and/or
   `network_error`) as a **key event**.
2. **Analytics → Custom insights** → create an insight that triggers when the
   daily count of that event rises above your baseline → deliver by email.

This is batched (hours of latency), so it's a trend backstop, not a pager. Use
the server metric as the real alarm and this to watch the client-side rate.

For a real-time client signal you'd route the three `AIService.swift` catch
blocks through `Crashlytics.recordError` as non-fatals — not wired today, and it
needs an app release, so only worth it if the batched Analytics insight proves
too slow.
