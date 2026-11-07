# What's left — Who Pays?

Last verified against the live systems: **7 Nov 2026**.

The app is built and works. Everything below needs an account, a device or a
decision that is yours — none of it is waiting on more code.

**Order matters.** Steps 1 and 2 are the only true gates: Play will not accept
the listing without a live privacy URL, and will not accept the binary without
a real signing key. The 14-day closed-test clock cannot start until both are
done, so do them first even though steps 3 and 4 are quicker.

---

## 1. Create the signing keystore — 2 minutes

Release builds are currently signed with the **debug** key. Play rejects those
outright.

```bash
bash tools/make_keystore.sh
```

It asks for a password twice. Nothing leaves your machine.

Then **back up `android/upload-keystore.jks` and `android/key.properties`
somewhere off this computer** — a password manager, a private drive, anywhere
that is not this laptop.

> If you lose this file you can never publish an update to this app again.
> Play identifies an app by its signature. There is no recovery, no support
> ticket, no workaround. It is the single most important file in the project.
>
> For the same reason: never commit it to git. Deleting it in a later commit
> does not remove it — git history is permanent and GitHub indexes contents.

Done when: `tools/build.sh appbundle` no longer falls back to the debug key.

---

## 2. Deploy the guest site — 15 minutes

`who-pays.pages.dev` does not resolve. That kills two things at once: the
privacy policy URL Play requires, and **every QR code the app prints**.

1. vercel.com → **Add New → Project** → import `dharaneesh-r/who-pays`
2. **Root Directory: `web_guest`** ← the only setting that matters
3. Framework Preset *Other*. Build Command and Output Directory both empty.
4. Deploy.

Then check all four:

| URL | Should show |
|---|---|
| `/` | the join screen asking for a code |
| `/j/ABCD` | the join screen with **ABCD** already filled in |
| `/privacy` | the privacy policy |
| `/app.js` | JavaScript, not a 404 |

`/j/ABCD` is the one that matters — `/` and `/privacy` work even on a broken
config. If it 404s, Root Directory was not set to `web_guest`.

Then rebuild so the QR codes point at the real place:

```bash
tools/build.sh appbundle --dart-define=JOIN_HOST=https://your-domain.vercel.app
```

Full detail in [web_guest/DEPLOY.md](web_guest/DEPLOY.md).

Done when: scanning a QR code from the app opens the join page.

---

## 3. Fix the database — blocked on one piece of information

Three attempts to run the migrations have all landed in a **different Supabase
project** than the app uses. This was proved, not guessed: a marker table
created from your SQL editor was still invisible from the app's database after
70 seconds of retries.

Until this is resolved, three things stay broken:

- a player who force-closes the app freezes that table
- the purge jobs never run, so the privacy policy's deletion promises are not true
- **anyone holding the publishable key can delete any table** — codes are four
  characters from a 24-letter alphabet, about 331,000 combinations, trivially
  enumerated

**What to do:** open the SQL editor and copy the full URL from the address
bar. It looks like `https://supabase.com/dashboard/project/XXXXXXXX/sql/...`.
The app uses project `uhslpvssmpmhtmlmncxo`. If the `XXXXXXXX` differs, that
is the entire problem.

This link forces the correct project:

**https://supabase.com/dashboard/project/uhslpvssmpmhtmlmncxo/sql/new**

Run these three, in this order, each on its own:

1. `supabase/probe.sql` — tells us we are finally on the right database
2. `supabase/migration_fix.sql` — the missing column, the view, the purge cron
3. `supabase/migration_rls.sql` — the access lockdown

Two things that cause a silent "success" with nothing applied:

- **Any text selected in the editor** — Supabase runs only the selection. This
  is the most likely explanation for all three failed attempts.
- **"Success. No rows returned"** — every file ends with a SELECT returning
  `true`/`false`. If you see no result table, the script did not reach the end.

Done when: I can read the probe table from outside, and all checks return
`true`. Send me a message after each one and I will verify independently.

> Nothing is broken on your phone meanwhile. The app detects both the missing
> column and the missing function and falls back, so it works either way.

---

## 4. Real AdMob IDs — 10 minutes

The app currently serves **Google's test ads**, which earn nothing.

1. apps.admob.com → create the app → create an **Interstitial** ad unit
2. Copy the app id (`ca-app-pub-…~…`) and the unit id (`ca-app-pub-…/…`)
3. Build with both:

```bash
tools/build.sh appbundle \
  --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXXX/YYYY \
  -PadmobAppId=ca-app-pub-XXXX~ZZZZ
```

`tools/build.sh` warns on every build that omits these, so you cannot ship
test ads by accident.

> Do **not** tap your own live ads while testing — that gets the AdMob account
> banned. Keep the test ids until the build you actually submit.

Done when: a real ad shows after a round on a production build.

---

## 5. Validate the detector — 1 minute on the phone

The thresholds that decide who pays have never been checked against a real
table. Too sensitive and a thump blames someone who never touched their phone;
too blunt and a cheat gets away with it. This cannot be settled from a
simulation — a thin café table transmits a knock nothing like a heavy one.

On the phone: **Settings → Sensor test → RECORD A TRACE → START RECORDING**.

It takes 63 seconds and tells you what to do at each step. Do it on the kind of
table you would really play on.

Then tell me, and I will pull it and fit the numbers to it:

```bash
adb pull /sdcard/Android/data/in.nearle.who_pays/files/ traces/
dart run tools/analyse_trace.dart traces/trace_<timestamp>.csv
```

Background in [DETECTOR_TUNING.md](DETECTOR_TUNING.md).

Done when: the analyser reports no false positives on thumps and no misses on
the gentlest lift.

---

## 6. Play Console — the long pole

**Start this the moment steps 1 and 2 are done.** The 14-day clock is calendar
time you cannot buy back; everything else can be fixed while it runs.

1. Pay the one-off **$25** developer registration
2. Create the app, fill the store listing (copy in `store/listing.md`)
3. Upload the screenshots and feature graphic
4. Complete the declarations: Data Safety, content rating, target audience,
   ads (**yes**), privacy policy URL (step 2 + `/privacy`)
5. Upload the `.aab` from step 1's signed build
6. Create a **closed test** and recruit **12 testers**
7. Keep them opted in for **14 consecutive days**

Then apply for production access.

Done when: production access granted.

---

## 7. iOS — later

Not configured. Needs a Mac and $99/year. A separate project; nothing here
blocks the Android launch.

---

## Shortest path

Today: step 1 (2 min) → step 2 (15 min) → step 6 up to the closed test.
While the 14-day clock runs: steps 3, 4 and 5.
