# Metrics Dashboard: What to Watch

A quick visual reference for understanding your analytics dashboard and what data matters for product decisions.

---

## Daily Metrics Snapshot (Firebase Real-Time Tab)

```
┌─────────────────────────────────────────────────────┐
│ REAL-TIME ANALYTICS (last 30 minutes)               │
├─────────────────────────────────────────────────────┤
│ Active Users Now:        47 👥                      │
│ Sessions in Progress:    42                         │
│                                                     │
│ Top Screens:                                        │
│  • screen_home_today          18 views              │
│  • screen_journal_list        14 views              │
│  • screen_entry_editor         8 views              │
│                                                     │
│ Top Events:                                         │
│  • entry_created               4 events             │
│  • ai_insights_generated       3 events             │
│  • echo_answered               2 events             │
│  • ai_consent_granted          1 event              │
└─────────────────────────────────────────────────────┘
```

**What this means:**
- ✅ >0 users = app is alive
- ✅ Home tab has most views = core experience working
- ✅ Entry creation = users writing
- ✅ AI events = users engaging with features

---

## Weekly Dashboard: Engagement Trends

### Key Metrics to Build in Firebase/Google Sheets

| Metric | Day 1 | Day 3 | Day 7 | Trend | Target |
|--------|-------|-------|-------|-------|--------|
| **DAU** (Daily Active Users) | 150 | 120 | 95 | ↓ -37% | ↑ Stable/growing |
| **Entries/day** | 180 | 140 | 90 | ↓ -50% | ↑ Growing |
| **Avg session time** | 8:42 | 7:15 | 5:30 | ↓ | ↑ >5 min |
| **AI consent rate** | 65% | 68% | 70% | ↑ | >60% |
| **Echo answer rate** | 35% | 42% | 48% | ↑ | >40% |
| **Crash rate** | 0.3% | 0.2% | 0.1% | ↑ | <1% |

**Analysis:**
- ⚠️ DAU declining = retention issue (normal drop Day 1→7, but watch curve)
- ✅ AI consent growing = good adoption
- ✅ Echo answer rate growing = feature resonates
- ✅ Session time stable = engagement holds

---

## Retention Cohort Analysis

```
Cohort Retention (% of day-0 users who return)

         Day 0   Day 1   Day 3   Day 7   Day 14  Day 30
Week 1:  100%    55%     42%     28%     18%     12%
Week 2:  100%    52%     40%     26%     16%     10%
Week 3:  100%    58%     45%     31%     20%     14%
Week 4:  100%    61%     48%     34%     23%     16%

Target:  100%    >50%    >35%    >25%    >15%    >10%

Status:  ✅      ✅      ✅      ✅      ✅      ⚠️ Low
```

**What's happening:**
- Day 1 retention at 55% = decent (30-40% is typical)
- Day 7 retention at 28% = good (15-30% is normal)
- Day 30 retention at 12% = watch this (should stay >10%)

**If Day 7 drops to <20%:** Investigate quick—something broke the core loop.

---

## Funnel Analysis: User Journey

### Funnel 1: Signup → Onboarding → First Entry (Conversion Funnel)

```
100 users start signup
    ↓
92 complete signup (-8% drop)
    ↓
78 start onboarding (-15% drop) ⚠️ RED FLAG
    ↓
62 complete onboarding (-20% drop) ⚠️ RED FLAG
    ↓
48 write first entry (-23% drop) ⚠️ RED FLAG
    ↓
Overall conversion: 48% (target: >50%)

DIAGNOSIS: Onboarding is too long/hard
ACTION: Simplify onboarding, test shorter version
```

**Interpretation:**
- Signup completion: 92% ✅ (good)
- Onboarding start: 78% ⚠️ (acceptable, but could improve)
- Onboarding completion: 62% ❌ (too many dropouts)
- First entry: 48% ❌ (half of users never write)

→ **Priority #1: Fix onboarding**

---

### Funnel 2: Today's Read → Hint Ladder → Entry Written

```
100 users see Today's Read card
    ↓
68 click on it (-32%) ✅ Good engagement
    ↓
55 start hint ladder (-19%)
    ↓
38 complete hint ladder (-31%) ⚠️ High drop
    ↓
35 write entry (-8%)
    ↓
Overall: 35% of Today's Read viewers write entry

DIAGNOSIS: Hint ladder too long or not compelling
ACTION: Test shorter hint ladder, or move compose button earlier
```

---

### Funnel 3: Echo Surfaced → Answered → Shared? (Engagement Funnel)

```
100 echoes surface to users
    ↓
75 are viewed/interacted (-25%) ✅ Good
    ↓
45 are answered (-40% of viewed) ⚠️ Room to improve
    ↓
12 are shared/explored further (-73%)
    ↓
GOAL: Increase answer rate from 45% → 60%
```

**If answer rate <30%:**
- Echoes might not be relevant
- Maybe confidence threshold is too low (surfacing low-quality echoes)
- Try: Increase confidence threshold from 0.7 → 0.8

---

## Feature Adoption Metrics

### By Feature

| Feature | Adoption | D7 Return Rate | Notes |
|---------|----------|----------------|-------|
| **Core: Write Entry** | 95% | 45% | ✅ Core feature working |
| **Mood Logging** | 62% | 38% | ⚠️ Could promote |
| **Echo System** | 48% | 52% | ✅ High engagement |
| **Pattern Detection** | 31% | 41% | ⚠️ Low visibility? |
| **Mirror/Self-Model** | 18% | 29% | ⚠️ Discovery issue |
| **Daily Chat** | 12% | 58% | ⚠️ Low adoption but high retention |
| **Hint Ladder** | 38% | 44% | ⚠️ Could improve UX |

**Interpretation:**
- ✅ Core features (write, mood) have high adoption
- ⚠️ Mirror has low adoption → most users never discover it
- ⚠️ Pattern detection low → maybe not surfacing enough?
- ✅ Echo system high engagement → invest here

**Action if feature adoption <20%:**
1. Is it discoverable? (Can users find it?)
2. Is it valuable? (Do users understand why they'd use it?)
3. Is it easy? (Does it have friction?)

---

## Performance Metrics

### AI Call Performance

```
AI Insights Generation Latency (should be <2000ms)

Percentile    Latency    Status
p50 (median)  850ms      ✅ Good
p75           1200ms     ✅ Good
p90           1800ms     ✅ Good
p95           2400ms     ⚠️ Watch
p99           3200ms     ⚠️ Slow users

Average: 1050ms
Target: <1500ms average
Status: ✅ PASS
```

**If p95 > 3s:**
- Might be rate-limited by Gemini
- Or network issues
- Add caching or reduce token budget

### Crash Rate

```
Crash Rate by Screen

Screen          Crashes   Rate    Status
Home (Today)    2         0.1%    ✅ Good
Journal         1         0.05%   ✅ Good
Mirror          4         0.3%    ⚠️ Watch
Onboarding      0         0%      ✅ Good
Overall:        7         0.12%   ✅ Good (target: <1%)
```

**If crash rate >1%:**
- Check Xcode console for which screen
- Review recent changes on that screen

---

## Cohort Comparison: AI Users vs Non-AI Users

```
AI Enabled: YES          AI Enabled: NO
├─ DAU:          240      ├─ DAU:          180
├─ Entries/day:  2.4      ├─ Entries/day:  1.2
├─ D7 Retain:    35%      ├─ D7 Retain:    22%
├─ Avg Session:  12:30    ├─ Avg Session:  6:15
└─ Mood Log %:   78%      └─ Mood Log %:   51%
```

**Finding: AI users are more engaged!**
- 2x more entries
- 1.6x higher D7 retention
- 2x longer sessions
- 1.5x higher mood logging

→ **Action: Promote AI features more, or make them default-on after first entry**

---

## Health Dashboard: Critical Alerts

```
┌─ ALERTS ──────────────────────────────────────────┐
│                                                   │
│ 🟢 Signup funnel: 90% complete (was 78%)          │
│ 🟡 D7 retention: 26% (target 25%, OK)            │
│ 🟡 Echo answer rate: 38% (target 40%, close)     │
│ 🔴 Crash rate: 2.3% (OVER TARGET OF 1%)          │
│ 🔴 Pattern detection: 8 failed calls today        │
│                                                   │
│ Action needed: Investigate Mirror crashes        │
│               Debug pattern detection failures   │
│                                                   │
└───────────────────────────────────────────────────┘
```

---

## Weekly Review Checklist

Every Monday morning, check:

- [ ] **DAU:** Stable, growing, or declining? (flag if >20% drop)
- [ ] **D7 Retention:** >25%? (if <20%, investigate)
- [ ] **Crash Rate:** <1%? (if higher, debug immediately)
- [ ] **Entry Creation:** Stable? (track daily)
- [ ] **AI Adoption:** Growing? (should be >60% by week 4)
- [ ] **Funnel completion:** Signup → Onboarding → Entry >50%?
- [ ] **Feature adoption:** Any feature <15%? (might need to cut)
- [ ] **Performance:** p95 latency <3s? (if not, optimize)

**Traffic light system:**
- 🟢 All green = ship more features
- 🟡 1-2 yellow = investigate, no new features
- 🔴 Any red = prioritize fix above all else

---

## Example Weekly Report

```
WEEK 1 ANALYTICS REPORT
───────────────────────────────────────────

📊 KEY METRICS
  • DAU (avg):              142 ↑ +12%
  • D1 Retention:           55% ✅
  • D7 Retention:           28% ✅ (target: >25%)
  • Avg Session Length:     7:45 ✅
  • Entries Written:        340 (avg 34/day) ✅

🎯 FUNNEL PERFORMANCE
  • Signup → 1st Entry:     48% ⚠️ NEEDS WORK
    - Signup complete:      92% ✅
    - Onboarding complete:  62% ⚠️ Drop here
    - First entry written:  48% ⚠️ Drop here

  • Today's Read → Entry:   35% ⚠️
    - Hint ladder complete: 58% ⚠️ Ladder too long?

  • Echo → Answer:          45% ✅
    - Good engagement; keep promoting

🛠️ TECHNICAL
  • Crash Rate:             0.12% ✅
  • AI Latency (p95):       2200ms ⚠️ Watch
  • Network Errors:         <0.1% ✅

👥 COHORT INSIGHTS
  • AI-enabled users:       68% of DAU
  • AI adoption rate:       68% ✅ (target: >60%)
  • AI users' D7 retention: 35% vs 20% non-AI ✅
    → AI is a retention lever

💡 PRIORITIES FOR WEEK 2
  1. FIX ONBOARDING: 40% drop-off (from 92% signup to 62% complete)
  2. Reduce Today's Read friction (hint ladder too long?)
  3. Monitor AI latency (getting close to 3s ceiling)
  4. Promote Echo feature (performing well, can go harder)

```

---

## Sharing with Stakeholders

**Weekly standup deck template:**

```
Slide 1: Big Number
  "142 daily active users, up 12% week-over-week"

Slide 2: Retention Curve
  "D7 Retention: 28% (target: 25%)"
  📈 [graph showing Day 1→7]

Slide 3: Top Problem
  "Onboarding drop-off: Only 48% of signups write first entry"
  → Priority: Shorten onboarding to 5 steps

Slide 4: What's Working
  "Echo system is a hit—45% of users answer echoes"
  → Action: Increase surface frequency

Slide 5: What We're Shipping Next
  "Simpler onboarding + more echo types"
```

---

## When to Escalate

| Metric | Red Flag | Action |
|--------|----------|--------|
| **DAU** | -50% in 1 day | Page team, debug immediately |
| **Crash Rate** | >5% on 1 screen | Rollback that screen's latest changes |
| **AI Latency** | p95 > 5s | May hit rate limits; add caching |
| **Funnel completion** | <30% on critical funnel | Run A/B test alternative |
| **Feature adoption** | <10% after 2 weeks | Consider sunset or redesign |
| **D7 Retention** | <15% for new cohort | Core product not working; investigate |

---

## Tools You'll Use

1. **Firebase Console** (free) — Real-time, retention, funnels, cohorts
2. **Google Sheets** (free) — Manual weekly dashboard
3. **Slack Integration** (optional) — Daily digest alerts
4. **Tableau/Looker** (paid) — Advanced dashboarding

**Recommendation:** Start with Firebase Console + Google Sheets. Upgrade to Tableau if you grow to 10k+ DAU.

---

## Next: Set Up Automated Alerts

In Firebase Console → Analytics → Reporting → Alerts:

1. Create alert: **Crash rate exceeds 1%** → Slack notification
2. Create alert: **DAU drops >30% day-over-day** → Slack notification
3. Create alert: **AI latency p95 exceeds 3000ms** → Email

You'll be notified before you notice the problem.
