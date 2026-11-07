# AdMob & Publishing Setup

What is already in the app, and what you must do outside it before a single
rupee arrives. Nothing here is code — it is all account setup.

---

## 1. Money: what is actually free

| Item | Cost | Mandatory? |
|---|---|---|
| **Google Play developer account** | **$25 (~₹2,100) one-time** | **YES — you cannot publish without it** |
| AdMob account | Free | Yes, to earn |
| Firebase | Free tier | No (recommended) |
| Supabase | Free tier | Already set up |
| Cloudflare Pages | Free | For the guest page |
| Flutter, Android SDK, NDK | Free | Done |
| Apple Developer | $99/year | Only if you ship iOS |

**So: one payment of $25, once, ever.** Everything else is free at this scale.

---

## 2. How the app earns — two streams, not one

The app as built has **both**:

| Stream | Where | Status |
|---|---|---|
| **Interstitial ad** | Shown when leaving the result screen | Built, using **test** ids |
| **Pro unlock** (one-time ₹149 / $3.99) | Paywall after 3 free rounds a day | Built, needs Play products |
| Card packs (₹49–99 each) | Table Talk packs | Entitlement logic built, packs not written yet |

**Ads alone will not pay for this in India.** At 100k Indian installs, ad revenue
is roughly **$50–65/month** — eCPM here is $0.30–1.50. The same users in the
US/UK are worth 10–20×. The Pro unlock is what makes an Indian launch viable,
which is why it is built in.

If you genuinely want ads-only, delete the paywall call in
`setup_view.dart` and the free-round limit in `entitlements.dart`. I would not.

---

## 3. AdMob setup — step by step

### Create the account and the ids

1. Go to **admob.google.com** → sign in with your Google account → create an
   AdMob account (free).
2. **Apps → Add app → Android → "Is your app listed on a store?" → No**
   (you can link it to Play later, after publishing).
3. Name it `Who Pays?`. You now get an **App ID** like
   `ca-app-pub-1234567890123456~1234567890` (note the **`~`**).
4. **Ad units → Add ad unit → Interstitial.** Name it `Result interstitial`.
   You now get an **Ad unit ID** like
   `ca-app-pub-1234567890123456/1234567890` (note the **`/`**).

### Put them in the app

**App ID** — edit `android/app/src/main/AndroidManifest.xml`, replace the value:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-YOUR~ID" />
```

**Ad unit ID** — pass at build time, no code change:

```bash
flutter build appbundle --release --no-tree-shake-icons --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-YOUR/UNIT
```

### Get paid

5. **AdMob → Payments** → fill in name and address exactly as on your bank records.
6. **Tax info** — India: PAN. Google will also ask for a tax form (usually W-8BEN
   equivalent, handled in the flow).
7. **Add your bank account** (name must match the AdMob account holder).
8. **Address verification**: once you earn **$10**, Google posts a PIN to your
   address. Enter it, or payments stay blocked.
9. **Payment threshold is $100.** Below that it rolls over month to month.

### Rules that get accounts banned

- **Never click your own ads.** Not once, not "just to test".
- **Never ship the test ids** — they earn nothing.
- **Never test against live ad units.** Register your phone as a test device in
  AdMob → Settings → Test devices.
- Do not ask users to click ads, or place ads where they get tapped by accident.

---

## 4. The things most people miss — all required for ads

| Requirement | Why | Where |
|---|---|---|
| **Privacy policy URL** | **Mandatory** for any app serving ads. Play rejects the listing without it | Host a page anywhere (a second Cloudflare Pages file works) |
| **Data safety form** | Play requires declaring what data is collected. Ads SDK collects device/ad id | Play Console → App content → Data safety |
| **Ads declaration** | Play asks "does your app contain ads?" — answer **yes** | Play Console → App content |
| **Target audience & content rating** | Decides which ads can serve. Declare **not** aimed at children, or ad revenue collapses under Families policy | Play Console → App content |
| **EEA/UK consent (UMP)** | Since 2024 Google requires a certified consent platform to serve ads in Europe | AdMob → Privacy & messaging → create a GDPR message. **Not yet wired in the app** |
| `app-ads.txt` | Prevents ad fraud using your app's name; raises eligible demand | Only if you have a website |
| Link AdMob ↔ Play Console | Better targeting and reporting | After publishing |

**Two of these are not done in code yet:**

- **UMP consent SDK** is not integrated. Fine if you launch India-only; required
  before you push the US/UK installs the revenue plan depends on.
- **Privacy policy** — you need to write and host one. It must say the app uses
  Google AdMob, collects an advertising identifier, and stores game history on
  the device plus room data in Supabase.

---

## 5. In-app purchase setup (if you keep the Pro unlock)

1. Play Console → your app → **Monetise → Products → In-app products**.
2. Create one product per id in
   [entitlements.dart](lib/features/paywall/domain/entitlements.dart):
   `who_pays_pro`, `pack_couples`, `pack_team`, `pack_deep_talk`, `pack_desi`.
3. Type: **one-time product** (not subscription). Set India and US prices.
4. IAP only works on a build **uploaded to Play** (internal testing is enough)
   and installed from Play, signed with your upload key. It will never work on
   a sideloaded debug APK — that is expected, not a bug.

---

## 6. Order to do all this

1. Keystore → sign a real release.
2. Play account ($25) → create the app listing.
3. Privacy policy → host it → add the URL.
4. Upload the `.aab` to **internal testing** → start the 12-tester / 14-day clock.
5. AdMob account → ids → rebuild with the real ids.
6. Create the IAP products.
7. Data safety, ads declaration, content rating.
8. Production release.
9. UMP consent before any Europe/US push.
