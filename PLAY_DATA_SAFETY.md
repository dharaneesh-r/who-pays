# Play Console — App content answers

Fill these in at **Play Console → your app → Policy → App content**. Every
answer below is checked against what the code actually does; if the app changes,
change these too, because a Data safety form that disagrees with the app is a
policy violation.

Privacy policy URL: `https://who-pays.pages.dev/privacy`
(see [web_guest/privacy.html](web_guest/privacy.html) — change the host if the
Cloudflare project is named differently)

---

## Data safety

### Does your app collect or share any of the required user data types?
**Yes.**

### Is all of the user data collected by your app encrypted in transit?
**Yes.** Everything goes to Supabase over HTTPS.

### Do you provide a way for users to request that their data be deleted?
**Yes.** Email request, plus in-app deletion by uninstalling. The Settings
screen shows the device ID so a request can be matched.

---

### Data types to declare

| Category | Type | Collected | Shared | Purpose | Required? |
|---|---|---|---|---|---|
| Personal info | **Name** | Yes | No | App functionality | Optional |
| App activity | **Other user-generated content** (the name shown at a table) | Yes | No | App functionality | Optional |
| App info and performance | **Other app performance data** (round events) | Yes | No | Analytics | Optional |
| Device or other IDs | **Device or other IDs** | Yes | **Yes** | Advertising, Analytics, App functionality | Required |

**Notes for each answer:**

- **Name** — only what the player types for a table. It is optional, never
  verified, and not linked to any account because there are no accounts.
- **Device or other IDs** — two separate things: our own randomly generated
  app-install ID, and the Android advertising ID that **Google AdMob** collects.
  The advertising ID is what makes this "shared" and "required".
- **Analytics** — anonymous event counts. Tick *Analytics* as a purpose.

### Do NOT declare these — the app does not collect them

Location · Financial info · Health · Messages · Photos or videos · Audio ·
Files · Calendar · Contacts · Search history · Installed apps · Email address ·
Phone number · Payment info

The accelerometer, gyroscope and camera are **used but never collected** —
sensor readings are processed in memory and the camera only decodes a QR code.
Play's Data safety form is about data that *leaves* the device, so none of
these get declared. The camera still needs its runtime permission, which is
separate.

---

## Ads

**Does your app contain ads? → Yes.**

Ad format: interstitial. Shown once, after a round ends, never during play.

## Target audience and content

- **Target age group:** 18 and over.
- **Do not** select any under-18 group. The app would then fall under the
  Families policy, which restricts ad serving and would cut revenue sharply.
- Appeal to children: **No**.

## Content rating questionnaire

Answer **No** to violence, sexual content, drugs, gambling and profanity. The
Table Talk conversation packs are everyday questions, but read them once before
answering so the declaration is yours:
[assets/cards](assets/cards).

Expect a rating of roughly PEGI 3 / ESRB Everyone, with an "in-app ads" notice.

## Government apps / financial features / health

**No** to all. "Who pays the bill" is a social forfeit — no money moves through
the app, there are no payments, and nothing is processed.

---

## Before you submit, check these still match the code

| Claim | Where it is true in the code |
|---|---|
| No accounts | No auth anywhere; `supabase_init.dart` disables token refresh |
| Random device ID, not the ad ID | [device_identity.dart](lib/data/local/device_identity.dart) — `Uuid().v4()` |
| Table data deleted after a day | `purge_old_rooms()` in [schema.sql](supabase/schema.sql) |
| Events deleted after a year | `purge_old_events()` in [analytics.sql](supabase/analytics.sql) |
| Sensor data never leaves the device | [pickup_detector.dart](lib/features/detector/domain/pickup_detector.dart) is pure, with no I/O |
| No photo is stored from the camera | [scan_qr_screen.dart](lib/features/room/presentation/scan_qr_screen.dart) reads barcodes only |
| Phones cannot read others' events | `app_events` has an insert-only RLS policy |

**Both purge functions need scheduling.** They exist but nothing calls them —
set them up under Supabase → Integrations → Cron, or the retention periods
promised in the privacy policy will not actually happen.
