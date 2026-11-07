# Play Store listing

Copy and paste. Character counts are Play's hard limits.

---

## App name (30 max)

```
Who Pays? Phone Down Game
```

Alternatives if that one is taken:

```
Who Pays? Party Game          (25)
Phones Down — Who Pays?       (23)
```

The name carries two keywords people actually search — "phone down" and
"party game" — without reading like a keyword list.

---

## Short description (80 max) — **73**

```
Phones face down on the table. First one to pick theirs up pays the bill.
```

This is the whole game in one sentence, which is the only job this field has.
It appears under the icon in search results.

---

## Full description (4000 max) — ~1,650

```
Put every phone face down in the middle of the table. Start the round. The
first person who picks theirs up pays the bill.

That's it. That's the game.

HOW IT WORKS

One person starts a table and shares a four-letter code or a QR. Everyone
joins from their own phone. Phones go face down, the timer starts, and nobody
is allowed to touch theirs.

Your phone knows. It uses the accelerometer and gyroscope to tell a real
pick-up from someone bumping the table, so you cannot cheat and you cannot be
blamed for a passing truck. Leave the app or unlock your screen and it knows
that too.

The moment someone cracks, every phone at the table sounds a siren and shows
their name. The round carries on for everyone still in.

NO APP? NO PROBLEM

Only the host needs the app installed. Everyone else scans the QR code and
plays from their browser. No download, no account, no sign-up, nothing to
install at a restaurant with bad wifi.

SOMETHING TO TALK ABOUT

Taking phones away leaves a gap, so the app fills it. A conversation prompt
appears every 45 seconds — six packs covering friends, family, couples, team
lunches, deep talk and desi humour. Tap to skip one you don't like.

PICK YOUR STAKE

Loser pays the bill. Buys the next round. Does the dishes. Does the chores. Or
write your own.

KEEP SCORE

Every round is saved. See who cracks first most often, how long you can last,
and build a streak of phone-free dinners.

FREE, EVERYTHING UNLOCKED

Every feature, every conversation pack, unlimited rounds. One short advert
after a round ends — that's what pays for the app. No subscription, nothing to
buy, no account required.

WORKS WHERE YOU ACTUALLY ARE

No internet needed to play on your own. Your game history never leaves your
phone. Nothing to sign up for, ever.

Good for restaurants, family dinners, team lunches, long train journeys,
first dates and anyone who has ever said "put your phone away".
```

---

## What's new (500 max) — first release

```
First release.

Play on one phone, or start a table and have everyone join by code or QR —
they don't even need the app. Six conversation packs, group scoreboards,
phone-free dinner streaks, and a siren nobody enjoys hearing.
```

---

## Category and tags

- **Application type:** Game
- **Category:** Casual *(or Social — Casual ranks better for party games)*
- **Tags:** party, multiplayer, friends, family, social, casual

---

## Contact details

- **Email:** care@dharaneesh.in
- **Website:** https://who-pays.pages.dev
- **Privacy policy:** https://who-pays.pages.dev/privacy

---

## Assets in this folder

| File | Use | Spec |
|---|---|---|
| `icon-512.png` | Store icon | 512×512 ✅ |
| `feature-graphic.png` | Feature graphic | 1024×500 ✅ |
| `screenshots/1-home.png` | Phone screenshot | 800×1600 ✅ |
| `screenshots/2-setup.png` | Phone screenshot | 800×1600 ✅ |
| `screenshots/3-round.png` | Phone screenshot | 800×1600 ✅ |
| `screenshots/4-caught.png` | Phone screenshot | 800×1600 ✅ |
| `screenshots/5-settings.png` | Phone screenshot | 800×1600 ✅ |

All five screenshots are real captures from a Realme RMX2030, padded from
720×1600 to 800×1600. Play rejects anything where the long side is more than
twice the short side, and 720×1600 is 2.22:1 — the padding brings it to
exactly 2:1 without cropping anything.

`feature-graphic.html` is the design source if you ever want to restyle it.

### Screenshot order matters

Play shows the first two in search results, so lead with the ones that explain
the game:

1. **Home** — the name and the one-line rule
2. **Round** — the big timer, which is the game
3. **Caught** — the payoff
4. **Setup** — stakes and conversation packs
5. **Settings** — reassurance, least important

Consider swapping 2 and 3 so the pair shown in search is the hook (the timer)
and the punchline (CAUGHT).

---

## Things to fix before submitting

- The listing promises the guest page works. **Deploy `web_guest/` first**, or
  "no download needed" is false advertising.
- Target age **18+**. Phrases like "family dinners" in the description are
  about who you play with, not who the app is for — do not let that tempt you
  into ticking a younger age bracket.
