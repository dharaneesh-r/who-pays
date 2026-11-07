# First Device Test

The only part of this app that cannot be verified without real hardware. The
detection thresholds in
[detection_config.dart](lib/core/constants/detection_config.dart) were tuned
against a simulated phone; this session is where you find out whether they suit
a real one.

Budget an evening. Do it before anything else.

---

## Install

APK is on your Desktop as `WhoPays.apk` (27.6 MB, arm64 — right for any phone
made in the last ~8 years).

**Option A — copy the file**

1. Plug the phone in, pick **File transfer / MTP** on the phone.
2. Copy `WhoPays.apk` into the phone's Downloads folder.
3. On the phone open **Files → Downloads → WhoPays.apk**.
4. Allow "install from unknown sources" when asked.

**Option B — adb** (faster for repeat installs)

1. Phone: **Settings → About phone → tap Build number 7 times** to unlock
   Developer options.
2. **Settings → Developer options → USB debugging: on.**
3. Plug in, accept the "Allow USB debugging?" prompt on the phone.

```bash
export PATH="$PATH:/c/Users/hp/AppData/Local/Android/sdk/platform-tools" && adb devices
```

```bash
export PATH="$PATH:/c/Users/hp/AppData/Local/Android/sdk/platform-tools" && adb install -r "/c/Users/hp/Desktop/WhoPays.apk"
```

Play Protect may warn: the APK is debug-signed. **Install anyway** is correct
here. It disappears once the app is signed with a real upload key.

---

## Test 1 — the detector (the important one)

Home screen → **Dev · sensor detector**. This screen exists so detection can
always be diagnosed on real hardware; it stays in the app permanently.

Tap **PUT PHONE DOWN & WATCH**, then work through this:

| # | Do this | Expect | If it fails |
|---|---|---|---|
| 1 | Phone flat on a table, don't touch | Badge goes **SETTLING** → **ARMED** within ~1.5 s, stillness bar fills | If it never arms, `stillnessTolerance` (0.35) is too strict for this phone's sensor noise. Raise it |
| 2 | Watch the idle numbers while armed | Linear accel < 0.35, rotation < 0.35 | Noisy readings at rest mean the same fix as above |
| 3 | **Thump the table hard** with your fist | Motion bar jumps but **does NOT catch** | If it catches, raise `sustainedMotionWindow` (180 ms) or `pickUpAccelThreshold` (1.6) |
| 4 | Thump it **8–10 times** over a minute | Still no catch, and the idle reading returns to near zero | A drift upward means the gravity gate is leaking — lower `gravityUpdateGate` (0.5) |
| 5 | **Slide** the phone across the table | Judgement call — sliding is arguably cheating | Tune to taste |
| 6 | **Pick it up normally** | **CAUGHT** within ~0.2 s, reason "Picked the phone up" | Slow or missed → lower `pickUpAccelThreshold` or shorten the window |
| 7 | Pick it up **very slowly and gently** | Should still catch | This is the hardest case. If it misses, the gyroscope usually saves you — lower `pickUpGyroThreshold` (1.1) |
| 8 | Flip it face up without lifting | **CAUGHT**, reason "Turned the phone over" | |
| 9 | Press home / switch apps while armed | **CAUGHT**, reason "Left the app" | |
| 10 | Put it on a **sofa or your lap**, then lift | Should still arm and catch | Soft surfaces are the worst case for stillness |
| 11 | Walk past heavily / knock the table leg | No catch | |

**After each change** to `detection_config.dart`:

```bash
cd /c/Users/hp/Desktop/app-development && flutter test && flutter run --release
```

The 15 detector unit tests will catch any change that breaks the logic — if a
test like "does NOT catch a brief table bump" starts failing, the new numbers
are wrong, not the test.

**If you change the thresholds, change `CFG` in
[web_guest/app.js](web_guest/app.js) to match**, or app players and web players
are playing different games.

---

## Test 2 — a real round

Home → **JUST ME** → pick a stake → 15 min → **PHONES DOWN**.

- [ ] Timer is readable from across a table
- [ ] Screen never sleeps during the round
- [ ] Table Talk prompt appears and rotates after ~45 s
- [ ] Tapping the prompt skips to another one — and does **not** count as a catch
- [ ] Pick the phone up → **siren is loud enough to be embarrassing in a restaurant**
- [ ] Vibration fires
- [ ] **SILENCE THE SIREN** stops it
- [ ] Result shows how long you lasted
- [ ] **My record** now lists the round
- [ ] Play 3 rounds → the 4th shows the paywall

The siren is the whole enforcement mechanism. If it is not loud and ugly, the
game does not work — raise the volume or regenerate it with a harsher waveform.

---

## Test 3 — a table (needs 2+ phones)

Install on a second phone, or use the guest page once it's deployed.

- [ ] Phone A: **HOST A TABLE** → code and QR appear
- [ ] Phone B: **JOIN WITH CODE** → types the code → appears in A's list
- [ ] Phone B: **SCAN THE QR** instead → joins
- [ ] Host taps **PHONES DOWN** → **both phones start together**
- [ ] Both arm independently
- [ ] Pick up B → A sees B struck through **within a second or two**
- [ ] Both phones name the same loser
- [ ] Pick up A afterwards → the loser does **not** change
- [ ] **SHARE THE DAMAGE** produces a card that is legible in a WhatsApp thread

Point 8 is the one to watch: being caught second must never make you the loser.

---

## Test 4 — the awkward cases

- [ ] Incoming call while armed → exempt, flagged, not caught
- [ ] Alarm goes off → not caught
- [ ] Phone face **up** instead of down → still works
- [ ] Airplane mode → solo play still works; home screen says "Offline"
- [ ] Deny the camera permission → QR scan degrades to "type the code"
- [ ] Battery: a 30-minute round should cost only a few percent

---

## What to record

For every false positive or miss, note **phone model, surface, what you did,
and the live numbers** from the dev screen. That is what the 12-tester closed
test is really for, and it is the data that makes the thresholds right.
