# Launch checklist

Everything that needs an account, a credential or your hands. The code is done;
this is what is left.

Ordered so each step unblocks the next. **Total cost: $25.**

---

## A · Finish the backend — free, ~15 minutes

The app works without these, but three things it promises do not.

### A1. Run the presence migration

Supabase → **SQL Editor** → **New query** → paste
[supabase/migration_presence.sql](supabase/migration_presence.sql) → **Run**.

Until this runs, a player who closes the app mid-round freezes that table
forever.

- [ ] Done — `room_players` now has a `last_seen` column

### A2. Schedule the three cleanup jobs

Supabase → **Integrations** → **Cron** → enable it, then add three jobs:

| Name | Schedule | SQL |
|---|---|---|
| `purge-rooms` | `0 * * * *` (hourly) | `select public.purge_old_rooms();` |
| `purge-absent` | `*/5 * * * *` (every 5 min) | `select public.purge_absent_players();` |
| `purge-events` | `0 3 * * *` (daily 3am) | `select public.purge_old_events();` |

**These functions already exist but nothing calls them.** Your published
privacy policy says table data is deleted after a day and events after a year.
Until these run, that is not true — and a Data Safety declaration that
disagrees with reality is a policy violation.

- [ ] Done — all three jobs listed and enabled

### A3. Deploy the guest page and privacy policy

1. [cloudflare.com](https://cloudflare.com) → sign up (free)
2. **Workers & Pages** → **Create** → **Pages** → **Upload assets**
3. Project name: **`who-pays`** (this exact name — the app's QR codes point at
   `who-pays.pages.dev`)
4. Upload the **contents** of `web_guest/`: `index.html`, `app.js`,
   `privacy.html`, `_redirects`
5. Deploy

Check both:
- `https://who-pays.pages.dev/privacy` → the policy
- `https://who-pays.pages.dev/j/TEST` → the join page with TEST filled in

If you used a different project name, rebuild the app with
`--dart-define=JOIN_HOST=https://your-name.pages.dev` or every QR code will be
dead.

- [ ] Done — both URLs load

---

## B · Test the detector — free, one evening, **nobody else can do this**

The thresholds in `detection_config.dart` were tuned against a simulated phone.
A real pick-up has fired on your Realme, but **a hard table thump has never
been tested**. If it falsely catches people, the game does not work.

Open the app → **long-press "WHO PAYS?"** → sensor read-out. Then work through
[DEVICE_TEST.md](DEVICE_TEST.md).

The five that matter:

| Do this | Expect | If wrong, change |
|---|---|---|
| Phone flat, untouched | ARMED in ~1.5s | `stillnessTolerance` |
| **Thump the table hard** | **No catch** | `sustainedMotionWindow` ↑ |
| Thump 8–10 times over a minute | Still no catch | `gravityUpdateGate` ↓ |
| Pick it up normally | CAUGHT in ~0.2s | `pickUpAccelThreshold` ↓ |
| Pick it up very slowly | Still caught | `pickUpGyroThreshold` ↓ |

Do this **before** the 14-day tester round, so testers see sane behaviour.

- [ ] Done — thresholds confirmed or adjusted on real hardware

---

## C · Firebase — free, ~10 minutes

Matters for one reason: **Remote Config lets detection thresholds be tuned
without shipping a release.** Without it, every adjustment from tester feedback
needs a full store update and another review.

1. [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → `who-pays`
2. Add an **Android** app
   - Package name: **`in.dharaneesh.who_pays`** (must match exactly)
   - Nickname: Who Pays?
   - SHA-1: skip for now
3. Download **`google-services.json`**
4. Put it at **`android/app/google-services.json`**
5. Tell me — I will wire Analytics, Crashlytics and Remote Config

Do this **before** the tester round, not after.

- [ ] Done — `google-services.json` in place

---

## D · AdMob — free, ~20 minutes

The app currently ships **Google's public test ad IDs**. They serve fake ads
and earn nothing.

### D1. Create the IDs

1. [admob.google.com](https://admob.google.com) → sign in → create account
2. **Apps → Add app → Android → "on a store?" No**, name it `Who Pays?`
3. Copy the **App ID** — `ca-app-pub-XXXX~YYYY` (note the **`~`**)
4. **Ad units → Add ad unit → Interstitial**, name it `Result interstitial`
5. Copy the **Ad unit ID** — `ca-app-pub-XXXX/ZZZZ` (note the **`/`**)

### D2. Put them in the app

App ID → `android/app/src/main/AndroidManifest.xml`, replace the value of
`com.google.android.gms.ads.APPLICATION_ID`.

Ad unit ID → passed at build time, no code change:

```bash
flutter build appbundle --release --no-tree-shake-icons --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXXX/ZZZZ
```

### D3. Publish the GDPR message

**Privacy & messaging → GDPR → Create message** → publish. The consent code is
already in the app; it stays dormant until a message exists.

### D4. Register your phone as a test device

**Settings → Test devices → Add**. Clicking a live ad on your own app gets the
account banned — permanently, with no appeal.

### D5. Payments

**Payments** → name and address exactly as on your bank records → **PAN** and
the tax form → bank account. Google posts a PIN to your address once you earn
$10; payout threshold is $100.

- [ ] Real IDs in the app, GDPR message published, test device registered, payments set up

---

## E · Google Play — **$25 one-time**

### E1. Developer account

[play.google.com/console](https://play.google.com/console) → **$25**, once ever.

Choose **Personal** unless you have a D-U-N-S number. Personal accounts must
run a **closed test with 12 testers for 14 continuous days** before production —
so start E6 as early as possible.

- [ ] Account created

### E2. Create the upload keystore

Run once, in PowerShell:

```powershell
keytool -genkey -v -keystore "$env:USERPROFILE\who-pays-upload.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (gitignored):

```
storePassword=<what you typed>
keyPassword=<what you typed>
keyAlias=upload
storeFile=C:/Users/hp/who-pays-upload.jks
```

**Back the .jks file up somewhere other than this laptop.** Lose it and you can
never update the app on Play again — not a recoverable mistake.

- [ ] Keystore created, `key.properties` written, **backup stored elsewhere**

### E3. Build the signed bundle

```bash
cd /c/Users/hp/Desktop/app-development && flutter build appbundle --release --no-tree-shake-icons --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXXX/ZZZZ
```

Output: `build/app/outputs/bundle/release/app-release.aab`

- [ ] Signed `.aab` built

### E4. Store listing

Create the app in Play Console. You will need:

| Asset | Spec |
|---|---|
| App icon | 512×512 PNG |
| Feature graphic | 1024×500 PNG |
| Screenshots | 2–8 phone shots |
| Short description | ≤80 characters |
| Full description | ≤4000 characters |

There are real screenshots from your Realme in the scratchpad already — ask me
and I will prepare the listing assets and copy.

- [ ] Listing filled in

### E5. App content declarations

All the answers are worked out in
[PLAY_DATA_SAFETY.md](PLAY_DATA_SAFETY.md). The three that are easy to get
wrong:

- **Privacy policy URL** → `https://who-pays.pages.dev/privacy` (needs A3 done)
- **Target age → 18+.** Any under-18 group pulls the app into the Families
  policy, which restricts ad serving and cuts revenue sharply
- **Device IDs → "shared" = Yes.** That is the AdMob advertising ID

- [ ] Data safety, ads, content rating, target audience all submitted

### E6. Closed test — **start the clock early**

Upload the `.aab` to **Closed testing**, add **12 testers** by email, and leave
it running **14 continuous days**. The count resets if you drop below 12.

Line those 12 people up now; it is the longest single wait in this list.

- [ ] 12 testers opted in, day 1 recorded: ____________

### E7. Production

After 14 days: apply for production access, submit, wait for review (a few
hours to a few days).

- [ ] Live

---

## Fastest sensible order

| When | Do |
|---|---|
| **Today** | A1, A2, A3 — backend finished, policy hosted |
| **Tonight** | B — the detector test |
| **Tomorrow** | C, D — Firebase and AdMob |
| **Then** | E1–E6 — and start the 14-day clock immediately |
| **Day 15** | E7 — production |

Nothing after A depends on me. The only thing I am waiting on is
`google-services.json` for the Firebase wiring.
