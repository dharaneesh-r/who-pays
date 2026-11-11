# VENUE ATTRIBUTION — GPS, restaurants and the sponsorship business

Date: 2026-11-11. Context: [CONTEXT.md](CONTEXT.md) §8 (pricing) · [PENDING.md](PENDING.md) · [TODO.md](TODO.md)

Scope: what to do with the "use GPS to find restaurants" idea.

> **Superseded in part, 2026-11-11.** Sections 1–11 recommended attribution over
> discovery. The owner reviewed that argument and chose to build **discovery +
> group voting + bill splitting** anyway. That is the plan of record; it is
> specified in §12–§16. Sections 2 and 9 are kept because the risks they name
> (licensing, cost per query, incumbents) are real and still apply — they are
> now *things to manage*, not reasons not to build.

---

# 1. Decision log

| Idea | Outcome |
|---|---|
| GPS → list nearby restaurants, rank them, recommend the best | **Rejected** — loses to Google Maps/Zomato, costs per request, ranking data is not ours to license |
| GPS → recognise *which partner outlet this table is sitting in*, then attribute the game to it | **Chosen** — makes the restaurant-sponsorship line in CONTEXT.md §8 executable |
| GPS → 5 km nearby list → table votes → winner → play → split the bill | **Chosen by the owner, 2026-11-11**, overriding the row above. Specified in §12–§16. Attribution falls out of it for free: the winning venue *is* the attributed venue |

The two ideas use the same hardware and almost the same code. Only one has a
business behind it.

---

# 2. Why discovery loses

| Problem | Detail |
|---|---|
| Wrong moment | Nobody opens a dinner-table game to choose a restaurant. They already chose. They are sitting in it, phones face-down |
| Incumbents | Google Maps, Zomato and Swiggy have a decade of reviews, photos, menus and delivery data. We would ship a worse Zomato |
| Ranking data is licensed, not owned | "Tell us the best" needs ratings. Places' terms restrict caching and require attribution, so we cannot build our own ranking on their data. A licensing wall, not a coding problem |
| Cost per query | Places Nearby Search is billed per request (tens of USD per 1,000 calls at list price — re-check current rates). CONTEXT.md §8 projects **$50–65/month** India-only ad revenue. Discovery could cost more than the app earns |
| Install tax | The app asks for 4 benign permissions today. Location adds a runtime prompt, a Data Safety declaration, and confusion about what the app is |

---

# 3. The feature that works

Not *"where should we eat?"* but *"which partner restaurant are you in right now?"*

| Step | What happens |
|---|---|
| 1 | Host taps START. One **coarse, one-shot** location fix (no background, no tracking) |
| 2 | Match against the partner-venue list already cached on the phone. Distance maths on-device |
| 3 | Match found → show the outlet name, host can tap to correct it |
| 4 | Round plays exactly as it does today. Detection is untouched |
| 5 | Result card carries the sponsor's offer: *"Phones stayed down 31 min at Hotel Saravana Bhavan, T. Nagar — show this screen for 10% off dessert"* |
| 6 | The round is attributed to that outlet for reporting |

No match → the app behaves exactly as it does now. This is additive and
degrades to nothing.

---

# 4. What the restaurant is actually buying

CONTEXT.md §8 prices sponsorship at **₹5–25k/outlet/month** and calls it "the
real profit idea". Today we cannot prove a single game happened in any outlet,
so there is nothing to sell. Attribution is the product.

| Metric we can report | Why no one else can |
|---|---|
| Games played in this outlet | Needs presence at the table, not an order |
| Average phones-down minutes | Measures attention, which no delivery app sees |
| People per table | Group size, captured by the room |
| Offer views and redemption taps | Direct response for their spend |

Zomato knows who ordered. It does not know who sat at a table for 31 minutes
without touching their phone. That gap is the whole pitch.

---

# 5. Phases

## Phase A — no GPS, no permission, one afternoon

Optional free-text "Where are you?" at setup, stored on the round, surfaced in
stats. Costs nothing and no permission.

**It is the cheapest possible test of the real question:** if people will not
type a venue name, they will not grant location either. Learn that for free.

Done when: a round can carry a venue string and stats can group by it.

## Phase B — the money feature, 2–3 days

Partner venues in Supabase, coarse one-shot fix at round start, on-device
distance match, sponsor offer on the result card, attribution written back.

**Gated on sales, not on code.** One signed outlet justifies building it. Do not
build it on spec.

## Phase C — only if B earns

Venue leaderboards: *"this restaurant has hosted 412 games."* Shareable social
proof, and again structurally impossible for a delivery app to show.

---

# 6. Data model sketch

```sql
-- Phase B. Small table; the whole active set is cached on the phone.
create table venues (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  area         text,                      -- "T. Nagar"
  lat          double precision not null,
  lng          double precision not null,
  radius_m     int  not null default 120,
  offer_text   text,                      -- shown on the result card
  active       bool not null default false,
  partner_from date,
  partner_to   date
);

-- One row per attributed round. No user identifiers beyond the existing device id.
create table venue_rounds (
  id           uuid primary key default gen_random_uuid(),
  venue_id     uuid references venues(id),
  played_at    timestamptz not null default now(),
  duration_s   int  not null,
  players      int  not null,
  confirmed    bool not null default false,  -- host corrected the match?
  offer_tapped bool not null default false
);
```

Follows the existing `supabase/migration_*.sql` convention; RLS as per
`migration_rls.sql` (venues readable by all, `venue_rounds` insert-only).

**Matching is local.** Pull the active venues once, cache in sqflite, compare
with a haversine from `dart:math`. No Places API, no per-request cost, no
third-party terms, and we only carry outlets we have actually sold.

---

# 7. Permissions and policy

| Item | Decision |
|---|---|
| Permission | `ACCESS_COARSE_LOCATION` only. **Never** `FINE`, **never** background |
| Pattern | One fix at round start. No tracking, no history of where the user has been |
| Plugin | `geolocator` (handles the runtime prompt itself) |
| Data Safety | Must be re-declared: approximate location, collected, optional, purpose "app functionality". Whether aggregate outlet counts sent to a partner count as *sharing* needs to be answered carefully before submitting — do not guess on the form |
| Prompt copy | Ask at the moment of use, explaining the offer, not at first launch |

## Timing gate — this does not go in v1

[TODO.md](TODO.md) makes the signing keystore and the hosted privacy policy the
two hard gates, and the 14-day / 12-tester closed test has not started.

**Adding a location permission before that clock starts means redoing the Data
Safety form and restarting review.** Ship v1 first.

---

# 8. Cost

| Item | Cost |
|---|---|
| Places / Maps APIs | **₹0 — not used.** Partner venues are our own rows |
| Supabase | ₹0 — two small tables inside the existing free tier |
| `geolocator` | ₹0, small APK delta |
| Ongoing per-game cost | **₹0** |

---

# 9. Risks

| Risk | Mitigation |
|---|---|
| **Chicken-and-egg: no partners, no value** | Phase B is gated on one signed outlet. Phase A tests demand at zero cost |
| Indoor GPS is poor — malls, food courts, multi-storey | 120 m default radius, and the host can always tap to correct the venue. Attribution is a convenience, never a gate on play |
| Permission refusal rate | Coarse-only, asked in context, app fully usable when denied |
| Looks like a tracking app | Never background, no location history stored, say so plainly in the prompt and the privacy policy |
| Distracts from the actual product | Detection is the product ([CONTEXT.md](CONTEXT.md) §12, §13). PENDING.md #19 still lists physical pick-up as untested on hardware. That outranks this entirely |
| Sales effort, not code effort | Phase B is 2–3 days of work and an unknown number of weeks of door-knocking. Budget accordingly |

---

# 10. Go / kill criteria

| Metric | Go | Stop |
|---|---|---|
| Phase A venue field filled in | >25% of rounds | <10% — users do not care where they are, drop the whole idea |
| Signed partner outlets before building Phase B | ≥1 | 0 — do not build it |
| Coarse-location grant rate | >50% | <30% — attribution too sparse to sell |
| Match accuracy on a real outlet visit | >80% uncorrected | <50% — radius or venue coordinates are wrong |
| Revenue per partner outlet | ≥₹5k/month | <₹2k — the sales time is worth more elsewhere |

---

# 11. Open decisions

1. **Venue admin** — the `admin/` folder exists; partner venues need a way in that is not raw SQL.
2. **Guests** — does the guest web page (`web_guest/`) get the offer too? Guests outnumber hosts 3–8×, which is where redemption volume is, but the browser Geolocation API needs its own permission prompt on a stranger's phone.
3. **Redemption** — screenshot-and-show is free and forgeable. Per-round codes are honest but need staff training. Start with screenshots.
4. **Pilot size** — is one outlet a useful pilot, or does a chain (5–20 outlets) have to be the first sale?

---

# 12. PLAN OF RECORD — discovery, voting, split

Decided 2026-11-11. Supersedes the recommendation in §1.

## The flow

| # | Step | Where |
|---|---|---|
| 1 | Host opens the app, taps **FIND A PLACE** | Home |
| 2 | Coarse location permission requested *at this tap*, explaining why | App |
| 3 | One location fix → nearby restaurant search, **5 km radius** | App → provider |
| 4 | Candidates written to `room_venues` for this room code | Supabase |
| 5 | Host shows the QR; guests join as they do today and see the same list | App + guest page |
| 6 | **Everyone taps every place they are willing to go.** Tallies update live | App + guest page |
| 7 | Host closes voting. Most approvals wins; the rest drop off | App |
| 8 | Winner shown with distance and a maps link | Both |
| 9 | The round plays **exactly as it does today** — detection untouched | App + guest page |
| 10 | After the result: **SPLIT THE BILL**, stake-aware | App |
| 11 | Share card to WhatsApp, reusing `screenshot` + `share_plus` | App |

**The candidate list is fetched once, by the host, and shared.** Guests never
call the places provider and are never asked for location. Everyone is at the
same table, so one fix is the correct number of fixes. This is what keeps the
cost at one API call per dinner instead of one per person, and keeps the
browser geolocation prompt off 3–8 strangers' phones.

## New room status

Voting happens before the round, so `rooms.status` gains `voting`:

`lobby → voting → settling → running → finished`

The `check` constraint in [schema.sql](supabase/schema.sql) must be widened, and
`roomStatusFrom()` in `room_models.dart` already falls back to `lobby` for
unknown values — so an old guest page meeting a `voting` room degrades to the
lobby rather than crashing. **Verify that before shipping**, because the guest
page is deployed separately from the app and will lag it.

---

# 13. Voting rules

**Approval voting, one round.** Not ranked, not multi-round.

| Rule | Detail |
|---|---|
| Ballot | A device may approve **any number** of venues, including none |
| Storage | One row per `(room_code, device_id, venue_id)`. Tapping again deletes the row |
| Tally | Count of **distinct devices** approving that venue |
| Live update | Realtime on `venue_votes`, same channel pattern as `room_players` |
| "Least selected removed" | Once any vote exists, the lowest-scoring venues grey out and fall to the bottom; the host can collapse them away entirely |
| Winner | Most approvals. Tie → **nearest by distance**. Still tied → alphabetical, so every phone computes the same answer without asking the server |
| Who closes it | Host only |
| Late joiners | Anyone arriving after voting closed sees the winner, not a ballot |
| Nobody votes | No winner. Host may reopen voting or pick a venue by hand |

Tie-breaking must be **deterministic and local**, for the same reason
`RoomSnapshot.loser` is: two phones must never disagree about the result.

---

# 14. Place provider

```dart
abstract interface class PlaceProvider {
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    required int radiusM,
    int limit,
  });
}
```

| Implementation | Use |
|---|---|
| `GooglePlacesProvider` | **Built.** Places API (New) `searchNearby`. Key injected by `--dart-define=PLACES_KEY=...`, the same pattern `tools/build.sh` already uses for AdMob ids. Falls back to the fake with no key, so a debug build never spends anything |
| `FakePlaceProvider` | Tests and offline development. Fixed list, no network, no key |
| `OverpassProvider` | Optional fallback if the Google billing-account requirement is rejected |

**Why an interface:** the owner asked for "whichever is free and accurate".
No single source is both. Google is accurate and, at one call per dinner, fits
inside its free monthly allowance — but it still requires a billing account on
file. OSM needs no card and is patchy in India. The interface means that choice
can change later without touching the voting code, and it means **none of this
work is blocked on an API key**.

**Non-negotiable when the key is added:** set a hard request quota cap in the
Google Cloud console. A loop bug without a cap is an unbounded bill.

Radius is 5 km per the decision, capped at **20 candidates** — a 5 km radius in
a city centre can return hundreds, and a ballot of hundreds is not a ballot.
Ranking for that cut is by rating then distance.

---

# 15. Bill splitting — stake-aware

## What "stake-aware" means

The app's whole premise is *the loser pays*. A plain equal split would
contradict that: the app would announce "Bala pays the bill" and then ask
everyone for a quarter of it. So the split reads the stake that was played for:

| Stake played | Who owes what |
|---|---|
| **pays the bill** | The loser owes the **whole total**. Everyone else owes **₹0** |
| buys the next round | Split **equally**. The next round is settled separately, off-app |
| does the dishes | Split **equally**. The dishes are not money |
| does the chores | Split **equally** |
| custom | Split **equally**, and show the custom stake text next to the loser's name |

One screen, two different answers, decided by what the table actually bet.

## Worked example

Table of four — Asha, Bala, Chitra, Dev. Bill **₹2,400**. Bala cracked first.

| Stake was… | Asha | Bala *(loser)* | Chitra | Dev |
|---|---|---|---|---|
| **pays the bill** | ₹0 | **₹2,400** | ₹0 | ₹0 |
| buys the next round | ₹600 | ₹600 | ₹600 | ₹600 |

That is the entire idea: when the bet was about money, the bet decides the
bill; when the bet was about anything else, the bill is just divided.

## Rules

| Rule | Detail |
|---|---|
| Input | Total amount, optional tip %, and who is in the split |
| Tip | Added to the total **before** splitting |
| Exclusions | Anyone who did not eat can be dropped from the split |
| Rounding | Amounts are held as integer **minor units** (paise, cents) — never a `double`, because `0.1 + 0.2` is not `0.3`. Any indivisible remainder goes to the loser, or to the first person listed when there is no loser |
| **Invariant** | **The shares must sum to exactly the total.** Worth a test — a split that loses ₹1 to rounding is the kind of bug people notice at the table |
| Money movement | **None.** Amounts and a share card only. No UPI links, no payment rails, no settle-up ledger |
| Currency | Follows the device locale via `intl`, which is already a dependency |

Deliberately excluded for now: itemised "who ate what", UPI deep links, and
cross-dinner settle-up. Each was considered and declined on 2026-11-11 —
the first for the typing it demands at a table, the latter two for the Play
Store financial-feature scrutiny they attract.

---

# 16. What this changes from §7 and §8

| Item | Before | Now |
|---|---|---|
| Permission | Coarse, one fix at round start | **Unchanged** — coarse is plenty for a 5 km search. Still one fix, still host-only, still never background |
| Data Safety | Re-declare approximate location | **Same, and now unavoidable.** Discovery is the headline feature, not an optional extra |
| Provider cost | ₹0, no API at all | **One Nearby Search per dinner.** Inside the free allowance at expected volume; needs a quota cap regardless |
| Guest page | No change needed | **Now needs the voting UI.** `app.js` is 16 KB today and CONTEXT.md §12 budgets the whole page under 50 KB for bad restaurant wifi. Watch that budget |
| Timing | Ship v1 first | **Unchanged and more important.** Adding a location permission before the 14-day closed test restarts Data Safety review — see §7 |

The §9 risk table still stands. Indoor GPS accuracy matters less here than for
attribution — a 5 km radius tolerates a sloppy fix, where a 120 m venue match
does not.

---

# 17. What is built

Audited against the source on 2026-11-11, not from memory.
`flutter analyze` clean · 222 tests passing.

| Piece | File | State |
|---|---|---|
| Ballot, tally, winner, trailing | `lib/features/venue/domain/venue_models.dart` | ✅ |
| Place provider interface + fake + haversine | `lib/features/venue/domain/place_provider.dart` | ✅ |
| Location source interface + fixed point | `lib/features/venue/data/location_source.dart` | ✅ |
| Venue repository (Supabase) | `lib/features/venue/data/venue_repository.dart` | ✅ |
| Venue session (table **and** solo modes) | `lib/features/venue/application/venue_session.dart` | ✅ |
| Ballot screen | `lib/features/venue/presentation/venue_ballot_screen.dart` | ✅ |
| Stake-aware split | `lib/features/bill/domain/bill_split.dart` | ✅ |
| Money parsing and formatting | `lib/features/bill/domain/money.dart` | ✅ |
| Split screen | `lib/features/bill/presentation/bill_split_screen.dart` | ✅ |
| Schema | `supabase/migration_venues.sql` | ✅ written, **not applied** |
| Entry points | Home footer, room lobby, result screen | ✅ |

## Real places and real GPS — both built, both gated

Neither is a stub any more. Both are selected at build time, and the default
build behaves exactly as it did before: fake places, fixed point, no network,
no permission, nothing spent.

| Real implementation | Turned on by | Falls back to |
|---|---|---|
| `GooglePlacesProvider` — Places API (New) `searchNearby`, 16 tests | `--dart-define=PLACES_KEY=AIza…` | `FakePlaceProvider` when the key is absent |
| `GeolocatorLocationSource` — one coarse fix, 15 s limit | **both** uncommenting `ACCESS_COARSE_LOCATION` in `AndroidManifest.xml` **and** `--dart-define=LOCATION=true` | `FixedLocationSource` (central Chennai) |

The location gate is two steps on purpose. The flag alone does nothing, and the
manifest line sits in the manifest commented out with the reason next to it, so
whoever flips it reads why it was off: declaring that permission needs a new
Play Data Safety declaration, and adding one after the 14-day closed test has
started restarts the review (§7, §16).

### What the Places integration costs and promises

| | |
|---|---|
| Requests | **One per dinner.** The host searches; the rows go to `room_venues` and every guest reads those. A ten-person table is one request, not ten |
| Field mask | Only `id`, `displayName`, `formattedAddress`, `location`, `rating`. The mask is mandatory on this API and every extra field is billed |
| Result cap | 20, which is both the API's limit for `searchNearby` and the cap the ballot wants |
| Caching | Place data lands in `room_venues`, which cascades from `rooms`, which `purge_old_rooms()` deletes after a day — so their content lives **at most 24 hours**. Place *ids* may be kept indefinitely, which is why `place_id` identifies a venue rather than its name. **If that purge job is ever switched off, that claim stops being true** |
| Attribution | `attribution` is on the `PlaceProvider` interface, not inside one class, so a new provider cannot be added without deciding. The ballot screen renders "Powered by Google" — a licence requirement when their place data is shown without a Google map, not polish |
| Quota | **Set a hard request cap in the Google Cloud console.** A loop bug without one is an unbounded bill |

The app still **runs and demonstrates end to end** with no key and no
permission — search, vote, live tally, lock in, split, share.

## Solo mode

The session works with no room at all: candidates and votes stay in memory on
one phone. Not a test shim — someone who has just opened the app and wants to
know where to eat should not have to host a table first. `VenueBallot` does not
know which mode it is in, so there is no second code path for the tally.

## Still missing

| # | What | Notes |
|---|---|---|
| 1 | ~~Guest web page cannot vote~~ **BUILT** | `web_guest/ballot.js` ports `VenueBallot` and is tested against the same cases as the Dart (`node --test test/guest_ballot_test.mjs`, 17 tests). Guests vote from the lobby; the host still searches and locks in. The page is 34 KB of the 50 KB CONTEXT.md §12 allows |
| 2 | **`voting` room status is unused** | The migration widens the constraint and `Room` carries `decided_venue_id`, but no code sets `status = 'voting'` yet. Harmless, and the lobby entry point works without it |
| 3 | **Widget tests** | The domain, session and provider layers are covered; neither screen has a widget test. Consistent with the rest of the app (PENDING.md #18) |
| 5 | **No real place data has ever been fetched** | `GooglePlacesProvider` is tested against recorded response shapes, not against Google. The first call with a real key is still a first call |
| 6 | **GPS has never run on a device** | `GeolocatorLocationSource` is written but unexercised: the permission is commented out, so nothing has asked a real phone for a fix |
| 4 | **Venue attribution** | §3–§4 — the sponsorship reporting the winning venue makes possible. Not built; the data to do it is now being collected |

## One thing to verify on a device

`roomStatusFrom()` falls back to `lobby` for an unrecognised status, so an old
guest page meeting a `voting` room should degrade rather than crash. **That is
reasoned, not observed.** The guest page deploys separately from the app and
will lag it, so confirm it on hardware before shipping either.
