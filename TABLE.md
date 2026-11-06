# TABLE / "Who Pays?" — Spec Sheet

## Overview

| Item | Detail |
|---|---|
| App name | **Who Pays?** (better than "Table" — names the stake, searchable) |
| Type | Real-world party game, offline play, online room |
| Core rule | All phones face-down on the table. First to pick up loses. |
| Stake | Loser pays the bill / buys the round / does the dishes |
| Round length | 15 / 30 / 60 min or open-ended |
| Players | 2–10 |
| Guest install | **Not needed** — guests join by QR in the browser |
| Platform | Android first, iOS after validation |
| App size | **15–20 MB** |
| Offline | Yes for solo/streak; room needs data |
| Build time | **3 weeks to testable v1** |

## How it works

| Step | What happens |
|---|---|
| 1 | Host sets stake + timer, gets QR + 4-letter code |
| 2 | Others scan QR → join via web page, no install |
| 3 | Phones go face-down, all screens show same live timer, screen stays awake |
| 4 | Caught by: accelerometer motion, app losing foreground, or screen unlock |
| 5 | Siren + vibration + name on every screen: "RAMESH CRACKED. 7 min" |
| 6 | Exemptions: incoming call free (flagged), one 30-sec emergency pass each |
| 7 | Result card + group all-time tally → shared to WhatsApp |

## Modes

| Mode | For | Purpose |
|---|---|---|
| Dinner | Friend groups out | Viral entry point |
| Streak | Families, couples | Daily phone-free dinner streak — only real D30 lever |
| Focus Duel | Flatmates, colleagues | Async daily usage |
| Table Talk | Anyone | Conversation prompts, no stake |

## Table Talk cards (anti-churn feature + best IAP)

| Pack | Price |
|---|---|
| Friends (free) | ₹0 |
| Couples / Family / Team / Deep Talk / Desi humour / Would You Rather | ₹49–99 · $0.99 each |

## Users & age

| Segment | Age | Why they play | Value |
|---|---|---|---|
| Friend groups, college, hostel/PG, young professionals | **20–32** | Dares + bets are already their behaviour; they film it | **Core** — growth engine |
| Parents wanting phone-free dinners | **35–55** | No tool exists for this today | **Pays the money** — best IAP |
| Couples, date night | 22–40 | "Phones down, talk to me" | Good IAP + retention |
| Team lunch / offsite / HR | 25–45 | Icebreaker with a joke | B2B door |
| Wedding & party hosts | 25–50 | Phone-free ceremony | Seasonal spikes |
| **Sweet spot** | **22–45** | Works 18–55. Skip under-18 (privacy compliance, no revenue) | |

## Country strategy

| Phase | Markets | Why |
|---|---|---|
| 1. Validate (mo 0–3) | **India** — Tier 1 + 2 | Group dining is default; "loser pays" already a real bet; WhatsApp distribution; 95% Android; CPI ₹8–20; creators ₹2–5k/video |
| 2. Monetise (mo 3+) | **US, UK, Canada, Australia** | eCPM 10–20× India |
| 3. Second bet | **UAE, Saudi** | Huge family dining, high ARPU, Ramadan/Eid hook |
| 4. Later | Brazil, Indonesia, Philippines, Mexico | Same group-dining behaviour + Android share |

## Pricing & revenue

| Stream | Price | Verdict |
|---|---|---|
| Free tier | ₹0, with ads | Entry |
| **Pro unlock** | **₹149 / $3.99 one-time** | No ads, custom stakes, full stats, themes. Best for 35–55 segment |
| Card packs | ₹49–99 / $0.99 | Highest margin — just text files |
| Ads (AdMob) | Interstitial on result + rewarded for emergency pass | Primary revenue, but only at Western volume |
| **Restaurant sponsorship** | ₹5–25k/outlet/mo | **The real profit idea** — "phones down 30 min, 10% off dessert". Unserved market |
| Subscription | — | **Do not.** Nobody subscribes to a 4×/month game |

## Revenue math (100k installs, 6 months)

| Scenario | Ads/month | IAP | Verdict |
|---|---|---|---|
| India only | **$50–65** | ~₹2.2 L one-time (1.5% × ₹149) | Effectively nothing |
| 20% from US/UK/CA/AU | **$1,500–3,000** | **~$10,000** (2.5% × $3.99) + packs | Real side income |
| **Conclusion** | India = the lab, not the market. Real money needs Western installs or restaurant deals. | | |

## Growth

| Lever | Detail |
|---|---|
| ASO | **Weak** — nobody searches "put your phone down game". Don't rely on it |
| Organic | Mechanic is inherently filmable — 6-sec clips of someone getting sirened |
| Creators | 20–50 micro-creators in India, ₹2–5k each, film a real dinner not a review |
| Paid | Instagram Reels + Shorts. CPI ₹8–20 India, $1.50–3 US |
| Viral loop | Every game exposes 3–8 people. 20% guest→install = coefficient >1. **The whole bet** |
| Seasonality | Diwali, Christmas, New Year, Ramadan/Eid, Valentine's, wedding season |
| Retention (realistic) | D1 25–35%, D7 10–15%, D30 ~5% |

## Technology

| Layer | Choice |
|---|---|
| Framework | Flutter + Riverpod + go_router |
| Detection | `sensors_plus` (accel/gyro), `WidgetsBindingObserver` (app-switch), screen-unlock channel |
| Feedback | `audioplayers` (siren — *is* the mechanic), `vibration` |
| Screen | `wakelock_plus` |
| Join | `qr_flutter` (host) + `mobile_scanner` (guest) |
| Guest web join | Vite/Next.js on **Vercel** — DeviceMotion API + Page Visibility API |
| Realtime | **Supabase Realtime** — room, presence, "caught" events. Free tier → ~$25/mo |
| Local DB | **Drift (SQLite)** — tallies, history, stats |
| Share | `screenshot` + `share_plus` |
| Money | `google_mobile_ads`, `in_app_purchase` or RevenueCat |
| Analytics | Firebase Analytics + Crashlytics (day 1), AppsFlyer (when paid spend starts) |
| Tuning | Firebase Remote Config for detection thresholds |

## Costs to launch

| Item | Cost |
|---|---|
| Play Store account | $25 one-time |
| Supabase | ₹0 → ~$25/mo |
| Vercel | ₹0 |
| Creator seeding | ₹50k–2.5L (20–50 videos) |
| Paid install test | ₹50k–1L |
| Apple (later) | $99/yr |

## Risks

| Risk | Mitigation |
|---|---|
| **False positives kill trust** | Weeks of threshold tuning on cheap Androids + "contest this" button to overrule the app |
| Needs a social instigator per group | Host-led design, make hosting 2 taps |
| Party-trick churn (base case) | Streak mode + card packs |
| People genuinely need phones | Generous, visible exemptions |
| Low ARPU in launch market | Plan geo-expansion before spending on installs |

## Build plan

| Week | Deliverable |
|---|---|
| 1 | **Pick-up detector** — sensor fusion, thresholds, lifecycle catch, siren, haptics. Test on 4–5 cheap Androids. This *is* the product |
| 2 | Supabase rooms, QR join, shared timer, catch broadcast, result card, local tallies |
| 3 | Guest web page, Table Talk cards, Streak mode, AdMob + Pro unlock, Play internal test |
| Then | 20 creator videos in India. Watch guest→install. >15% = fund US/UK installs. <15% = viral bet failed, stop |
