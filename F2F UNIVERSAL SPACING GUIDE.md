# F2F UNIVERSAL PROGRESSION GUIDE
### The master reference for building a Fart to Float realm

This document exists so that a future realm — Space, Candy, Ocean, anything — can be built
**without rediscovering how the Dinosaur Realm's progression works.**

It is not a spacing document. Spacing is one of nine interlocking systems, and changing it
alone is the single most reliable way to break a realm. The whole machine is documented here.

---

## HOW TO READ THIS DOCUMENT

Every value is tagged. **Do not skip the tags** — they are the difference between a number you
must copy and a number you must re-solve.

| Tag | Meaning |
|---|---|
| **[LIVE]** | Read directly out of a shipped file. This is what the game is running right now. |
| **[DERIVED]** | Computed from [LIVE] values. Recomputes automatically if the inputs change. |
| **[RULE]** | A universal design law. Applies to **every** realm. Breaking it breaks the realm. |
| **[REF]** | A Dinosaur-Realm-specific reference number. A new realm will have different ones. |
| **[UNKNOWN]** | Cannot be determined from the current files. Explicitly flagged, never guessed. |

**Verification date:** every [LIVE] value below was read from the working tree at the time of
writing and cross-checked against `tools/ladder.py`, which parses the same shipped files and
replays the entire climb. If a number here disagrees with the harness, the harness is right.

---

# 15. SOURCE OF TRUTH

*(Placed first because you need it to audit everything else.)*

| File | What came from it |
|---|---|
| `src/shared/IslandOrder.luau` | `SLOT_POS` (every island X/Y/Z), `SLOT_TO_ISLAND`, `NAMES`, `SPACING_SCALE` |
| `src/shared/FlightTuning.luau` | `FLIGHT_SECONDS`, `MARGIN`, `COIN_PER_STUD_BASE`, `DESCENT_PAY_MULT`, `TANK_SECONDS`, `DRAIN_RATE`, `SPACING_SCALE`, `TIER_TIME`, `BASE_TIERS`, `SPEED_SHAPE`, and the formulas `climbFor` / `powerForClimb` / `getFlightSpeed` / `tierFor` / `fullTankClimb` / `timeScaleFor` / `tankSecondsFor` / `gapFromSlot` / `courtesyPower` / `powerShortfall` |
| `src/shared/StomachTiers.luau` | Every gut: name, `maxPower`, `cost`, `robux`, `unlockSlot` |
| `src/shared/FoodMenu.luau` | Every food: name, `price`, `power`, `island` |
| `src/server/Shop.server.luau` | Starting coins, the anti-strand free meal, purchase validation |
| `src/server/ServerEvents.server.luau` | `EVENT_POOL` (names, weights, durations), `CONFIG` intervals |
| `src/client/ServerEvents.client.luau` | The actual per-event multipliers applied on the client |
| `src/client/Bubbles.client.luau` | `BUBBLE_SHARE`, `FEVER_SHARE`, `STREAK_STEP`, `baseBonus()` |
| `src/server/GasBubble.server.luau` | `GRANT_POWER`, rate limiter |
| `src/client/BottomHUD.client.luau` | Fuel drain, `COIN_TICK`, `COAST_DAMPING`, `PAYOUT_SECONDS`, the descent-pay state machine and prepay logic |
| `tools/ladder.py` | The regression harness. **Its assertions are the encoded design rules** and are the primary source for Section 11. |

### The harness is the real specification

`tools/ladder.py` parses the shipped Luau — not a copy, not a model — and replays all 13
islands. Run it after **any** tuning change:

```
python tools/ladder.py
```

Exit code 0 = every invariant holds. It is the only thing in the project that can tell you a
one-line edit quietly cost five flights. **A realm is not "done" until this passes.**

### Known documentation drift (flagged, not corrected)

Three comments in the live files are stale. The **code** is correct; the **comments** lag:

1. **[LIVE]** `FlightTuning.DRAIN_RATE` carries the inline comment `-- 1.25`, but it evaluates to
   `100 / 22.75 = 4.396`. It is also **not the value the game uses** — `BottomHUD` computes
   `100 / FlightTuning.tankSecondsFor(stomachMax)` per gut instead. Treat `DRAIN_RATE` as legacy.
2. **[LIVE]** `FlightTuning.TIERS[k].gap` is described in-file as *"documentation only; nothing
   reads it."* Tier 7's entry still reads `5076` while the live final gap is `6200`. Harmless,
   but do not treat that column as authoritative — `gapFromSlot()` measures real island positions.
3. **[LIVE]** `Shop.server.luau` says *"every tank is exactly five servings"* and cites Eggs at
   24 power. Live Eggs is 32 power and tanks run 3.75–20.1 servings. Stale.

---

# 1. ISLAND SPACING

## 1.1 Slot order vs island numbering — and why a new realm can ignore this

**[REF] — DINOSAUR-REALM BAGGAGE, NOT A DESIGN RULE.**

```lua
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 5, 12, 3, 13, 7, 4, 10, 2, 8, 6, 11 }
```

- **Slot** = climb position (1 = ground, 13 = summit). *All tuning is in slot space.*
- **Island number** = the model's name in Workspace (`island1`, `island9`, …).
- **`IslandOrder.NAMES` is keyed by ISLAND NUMBER, not slot.**

**Why it is scrambled here:** the island models were built and numbered *before* the climb order
was settled, and the order then had to be rearranged to fix **content pacing** (§1.1.1) without
renaming thirteen models and every script that references them. The scramble is a **retrofit**.

### [RULE] For a NEW realm: do not reproduce this.

Number your islands in climb order. `island1` at the bottom, `island2` above it, and so on. Then:

```lua
IslandOrder.SLOT_TO_ISLAND = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }   -- identity
```

…and slot number *is* island number. Everything below collapses to "name the islands bottom to
top." **You should never have to think about this again.**

**[RULE] Keep the table even when it is the identity.** Do not delete the indirection — 47 call
sites across the codebase (`WormholeClient`, `Bootstrap`, `ShopGlue`, `FoodStands`, `PetXPHooks`,
`IslandLayout`, `Shop`, and more) go through `SLOT_TO_ISLAND` / `ISLAND_TO_SLOT`. An identity
table costs nothing and leaves you able to reorder later without touching any of them. That
ability is exactly what saved this realm when its order had to change.

**[RULE]** Regardless of mapping, **all tuning stays in slot space.** Island numbering is a
content/art concern. Mixing the two is what puts the wrong pet on the wrong island.

### 1.1.1 The real rule hiding underneath: REWARD PACING

The scramble exists to serve four constraints that **are** universal. These are what you should
carry to a new realm — solve them by *choosing the order you name your islands in*, not by
building a lookup table.

**[LIVE]** From the header of `IslandOrder.luau`, the live layout is:

| Slot | Island # | Name | Quest? | Reward | Rarity |
|---:|---:|---|:---:|---|---|
| 1 | 1 | Nesting Nook | ✅ | Triceratops | Common |
| 2 | 9 | Frostbite Flats | — | | |
| 3 | 5 | Misty Mire | ✅ | Spinosaurus | Common |
| 4 | 12 | Sunscorch Sands | — | | |
| 5 | 3 | Fossil Frontier | ✅ | Brachiosaurus | Rare |
| 6 | 13 | Glacier Gulch | — | | |
| 7 | 7 | Claw Cliffs | ✅ | Therizinosaurus | Rare |
| 8 | 4 | Coastal Crossing | ✅ | Megalodon | Rare |
| 9 | 10 | Petrified Pass | — | | |
| 10 | 2 | Fern Frontier | ✅ | Stegosaurus | Epic |
| 11 | 8 | Inferno Isle | — | | |
| 12 | 6 | Redwood Ridge | ✅ | Velociraptor | Epic |
| 13 | 11 | Volcanic Vista | ✅ | T-Rex | **Legendary — FINALE** |

> The in-file table lists an older pet assignment (Stegosaurus at slot 1, Triceratops at slot 10).
> The **grant scripts** are the source of truth and were re-matched to island environments later;
> the column above reflects the live grants. The *structure* — which slots are quest islands — is
> unchanged and is what matters here.

**[RULE] 1 — Reward islands must alternate with blank islands.** No two islands granting a
*distinct* reward may be adjacent. A blank island between rewards is what makes the next reward
feel earned instead of automatic.

**[RULE] 2 — Reward rarity must climb with the tower.** Live: Common → Common → Rare → Rare →
Epic → Epic → Legendary. The player must be able to tell how far they have come from what they
are being given.

**[RULE] 3 — The spawn island must be slot 1, and it must be a reward island.** It is where every
player starts and it has to teach the quest loop immediately.

**[RULE] 4 — The finale island must be the top slot.** **[LIVE]** Rebirth gates on reaching the
summit, so the top slot is load-bearing, not just thematic.

**[DERIVED]** Rules 3 and 4 are why the alternation cannot start or end on a blank — both anchors
are forced to be reward islands, which fixes the parity of the whole ladder. With 13 slots and
both ends pinned, some doubling is unavoidable. Live has exactly two adjacent quest pairs:
**slots 7–8** and **slots 12–13**.

> ### ⚠ [LIVE] THE CURRENT REALM VIOLATES RULE 1 AT BOTH PAIRS
>
> The original design absorbed the doubling by making **three** islands grant the *same*
> `RaptorPet` — one in each adjacent pair — so a doubled-up crossing never handed out two
> **different** rewards back to back. The in-file comment in `IslandOrder.luau` still describes
> that arrangement.
>
> **It is no longer true.** The pets were later re-matched to their island environments (a
> deliberate change), and every quest island now grants a *distinct* pet:
>
> | Pair | Slot | Island | Reward |
> |---|---:|---|---|
> | 7–8 | 7 | Claw Cliffs | Therizinosaurus |
> | | 8 | Coastal Crossing | Megalodon |
> | 12–13 | 12 | Redwood Ridge | Velociraptor |
> | | 13 | Volcanic Vista | T-Rex |
>
> So the live realm **does** hand out two different pets back to back, twice. The effect is mild
> — both pairs sit in the top half where rewards are dense anyway, and rarity still climbs
> correctly across them (Rare→Rare, Epic→Legendary). It is recorded here as a **known, accepted
> deviation**, not as the pattern to copy.
>
> **[DERIVED] The layout itself is already optimal — there is nothing to fix by reordering.**
> See §1.1.2. Two adjacent pairs is the mathematical *minimum* for 8 reward islands in 13 slots.
> What was lost is not the ordering, it is the **duplicate-reward cushion** that used to sit in
> those two unavoidable pairs.
>
> **[RULE] For a new realm, resolve this at layout time, not afterwards.** Either pick a reward
> count that needs no adjacency (§1.1.2), or deliberately place a shared/duplicate reward in each
> forced pair the way the original design did. Deciding reward-to-island theming *after* the
> ladder is locked is what created this deviation.

### 1.1.2 [DERIVED] How many reward islands can you actually alternate?

Perfect alternation is a counting problem, not a taste one. With `n` slots and `k` reward
islands there are `n − k` blanks, which can separate the rewards into at most `n − k + 1` runs.
Every reward beyond that count has to join an existing run:

```
minimum unavoidable adjacent reward pairs  =  max(0, k − (n − k + 1))
```

**[REF]** For the live 13-slot tower:

| Reward islands | Minimum adjacent pairs |
|---:|---:|
| 5 | 0 |
| 6 | 0 |
| **7** | **0** ← the largest count with perfect alternation |
| **8** | **2** ← live |
| 9 | 4 |

**[DERIVED]** The live realm runs **8 reward islands and has exactly 2 adjacent pairs** — the
minimum the count allows. The order cannot be improved. Eight is simply one more reward island
than a 13-slot tower can alternate cleanly.

**[RULE] Decide `k` against this formula before you place anything.** If you want every reward to
stand alone, `k ≤ (n + 1) / 2`. If you want more rewards than that, accept the forced pairs and
plan a duplicate or lower-value reward for each one.

**[DERIVED]** Rarity does hold across the whole ladder — verified against the live catalogue:

| Slot | 1 | 3 | 5 | 7 | 8 | 10 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|
| Rarity | Common | Common | Rare | Rare | Rare | Epic | Epic | **Legendary** |

**[RULE]** When you design a new realm's ladder, do this on paper first — decide which slots are
reward islands and what rarity each grants — **then** name the models in that order. The scramble
problem never appears.

## 1.2 Live positions

**[LIVE]** `IslandOrder.SLOT_POS`, with names resolved through `SLOT_TO_ISLAND` → `NAMES`:

| Slot | Island # | Name | X | **Y** | Z |
|---:|---:|---|---:|---:|---:|
| 1 | 1 | Nesting Nook | 0 | **150** | 0 |
| 2 | 9 | Frostbite Flats | 120 | **780** | 60 |
| 3 | 5 | Misty Mire | −160 | **1848** | 100 |
| 4 | 12 | Sunscorch Sands | 180 | **3090** | −120 |
| 5 | 3 | Fossil Frontier | −200 | **4395** | 160 |
| 6 | 13 | Glacier Gulch | 220 | **6187.5** | −180 |
| 7 | 7 | Claw Cliffs | −240 | **8073** | 200 |
| 8 | 4 | Coastal Crossing | 260 | **10555.5** | −220 |
| 9 | 10 | Petrified Pass | −280 | **13165.5** | 240 |
| 10 | 2 | Fern Frontier | 300 | **16614** | −260 |
| 11 | 8 | Inferno Isle | −320 | **20239.5** | 280 |
| 12 | 6 | Redwood Ridge | 340 | **25066.5** | −300 |
| 13 | 11 | Volcanic Vista | −360 | **31266.5** | 320 |

**[DERIVED]** X and Z alternate sign and grow slowly (±120 → ±360, ±60 → ±320). This is a
**readability device, not a mechanic**: nothing in the flight model reads X or Z. It makes the
tower visibly spiral so the player can see they are making progress, and stops islands from
occluding each other when you look straight up. **[RULE]** Keep some lateral offset; a perfectly
vertical stack reads as a single column and kills the sense of altitude.

## 1.3 The gaps

**[DERIVED]** `gap[c] = SLOT_POS[c+1].Y − SLOT_POS[c].Y`

| Crossing | From → To (slot) | **Gap** | Cumulative | Growth vs previous |
|---:|---|---:|---:|---:|
| c1 | 1 → 2 | **630.0** | 630.0 | — |
| c2 | 2 → 3 | **1068.0** | 1698.0 | ×1.695 |
| c3 | 3 → 4 | **1242.0** | 2940.0 | ×1.163 |
| c4 | 4 → 5 | **1305.0** | 4245.0 | ×1.051 |
| c5 | 5 → 6 | **1792.5** | 6037.5 | ×1.374 |
| c6 | 6 → 7 | **1885.5** | 7923.0 | ×1.052 |
| c7 | 7 → 8 | **2482.5** | 10405.5 | ×1.317 |
| c8 | 8 → 9 | **2610.0** | 13015.5 | ×1.051 |
| c9 | 9 → 10 | **3448.5** | 16464.0 | ×1.321 |
| c10 | 10 → 11 | **3625.5** | 20089.5 | ×1.051 |
| c11 | 11 → 12 | **4827.0** | 24916.5 | ×1.331 |
| c12 | 12 → 13 | **6200.0** | 31116.5 | ×1.284 |

**[DERIVED]** Total climb: **31,116.5 studs**. Realm spans Y = 150 → 31,266.5.

## 1.4 The structural pattern — this is the important part

**[DERIVED]** The growth column alternates: **×1.05, then ×1.3–1.4, then ×1.05, then ×1.3–1.4…**

That is not decoration. It encodes the **two-crossing tier cycle**:

```
        ┌─ SHORT crossing  (the WALL)  — growth ×1.05
TIER k  │  gap is ~2% beyond tier k−1's full-tank climb.
        │  You physically cannot make it on the old gut. Buy the gut.
        └─ LONG crossing   (the STRETCH) — growth ×1.3–1.4
           gap is ~97% of tier k's full-tank climb.
           The new gut's headroom is consumed, setting up the next wall.
```

**[RULE] Every gut must cover exactly two crossings: one wall, one stretch.**
The file's own history explains why. An earlier build paired gaps two-per-gut with six guts for
twelve crossings, and the playtest read **3, 1, 3, 1, 6, 1** flights — half the tower was free,
because a gut is the only thing that forces saving, and six guts can only wall six crossings.

## 1.5 Choosing gaps for a new realm

**[RULE]** Do not choose gaps directly. **Solve them from the tier climbs.** The procedure:

```
Given tier climbs C[1..n]:
  wall gap of tier k    = C[k−1] × 1.020        (2% past the old gut's reach)
  stretch gap of tier k = C[k]   ÷ 1.031        (97% of the new gut's reach)
```

**[DERIVED]** Verified against live values:

| Tier | Tank | Climb | Wall gap (= prev climb × 1.020) | Stretch gap (= climb ÷ 1.031) |
|---:|---:|---:|---|---|
| 1 | 120 | 853.5 | — (ground) | 630.0 → *1.355× headroom, deliberately loose* |
| 2 | 270 | 1279.5 | 1068.0 = 853.5 × 1.251 † | 1242.0 = 1279.5 ÷ 1.030 |
| 3 | 470 | 1848.0 | 1305.0 = 1279.5 × 1.020 | 1792.5 = 1848.0 ÷ 1.031 |
| 4 | 620 | 2559.0 | 1885.5 = 1848.0 × 1.020 | 2482.5 = 2559.0 ÷ 1.031 |
| 5 | 1080 | 3555.0 | 2610.0 = 2559.0 × 1.020 | 3448.5 = 3555.0 ÷ 1.031 |
| 6 | 1710 | 4977.0 | 3625.5 = 3555.0 × 1.020 | 4827.0 = 4977.0 ÷ 1.031 |
| 7 | 2600 | 7110.0 | 6200.0 = 4977.0 × 1.246 † | — (top tier) |

† **[LIVE]** Two crossings deliberately break the 1.020 rule:
- **c2 (the tutorial exit)** sits 25.1% past tier 1's reach, not 2%. Tier 1 is a tutorial tank
  with 1.355× headroom on its only gap; the player is meant to clear c1 comfortably and then hit
  an unmistakable wall.
- **c12 (the summit)** sits 24.6% past tier 6's reach. This was widened deliberately to make the
  final crossing the longest grind in the game (16 flights).

## 1.6 The four gap qualities

**[RULE]** Classify every gap you author against this table before shipping it.

| Quality | Signature | How to detect | Live example |
|---|---|---|---|
| **Good increasing gap** | Failed flights climb in visible steps; last miss lands 80–93% | Harness `THE CLIMB` ladder shows steady growth, worst miss < 95% | c9: 44→48→60→73→86% |
| **Unnecessarily huge gap** | Double-digit flight count with tiny early percentages | First attempts under ~15% of the gap | c12: starts at **11%** — 16 flights. Intentional here (summit), a bug anywhere else |
| **Repeated near-miss gap** | 90%+ appearing more than once, or before the final try | Harness fails `90%+ misses only ever happen on the last try` | None live. Caused by **R too low** (see §5.4), not by gap size |
| **1-flight crossing** | Crossing cleared on first launch | Harness fails `no crossing is under 3 flights` | None live. Minimum is 3 (c1) |

**[RULE] Never author an intentional 1-flight crossing.** It reads as a bug: the player buys
food, launches, lands, and never learns that the tower is a saving game.

## 1.7 Avoiding runaway spacing at altitude

**[RULE]** Gap growth is capped from above by **wall-clock**, not by feel. Because a tier's climb
is fixed, a longer gap does not make the player poorer — coins are paid *per stud climbed*, so a
bigger gap pays proportionally more. What it costs is **time**.

Live evidence: widening c12 from 5076 → 6200 (+22%) bought exactly **+2 flights** (14 → 16). The
lever is weak and expensive.

**[RULE]** If a crossing needs more flights, **do not reach for a bigger gap.** Reach for `R`
(§5.4). Gap size sets *how long each flight takes*; `R` sets *how many flights there are*.

## 1.8 How spacing is perceived

**[DERIVED]** Because the *stretch* gap of every tier is pinned at ~97% of the tank, the player's
last failed attempt on those crossings always lands in the 80s or low 90s — close enough to feel
achievable, never close enough to feel cheated. Because the *wall* gap is only 2% past the old
gut's reach, the failure that forces a purchase is unmistakable: you get 97%+ of the way with a
full tank and still cannot land. **That 2% is the entire "you need a bigger gut" message**, and
it is delivered by the flight, not by a UI popup.

---

# 2. FLIGHT SPEED / FLIGHT PHYSICS

## 2.1 SPEED_SHAPE — the taper

**[LIVE]** `src/shared/FlightTuning.luau`

```lua
local SPEED_SHAPE = { 0.944, 0.960, 0.975, 0.991, 1.007, 1.024, 1.041, 1.058 }
local NBANDS = #SPEED_SHAPE          -- 8
local CUM = { 0 }
for i, v in ipairs(SPEED_SHAPE) do CUM[i + 1] = CUM[i] + v / NBANDS end
```

Eight bands across the tank. **Index 1 is the EMPTY end**, index 8 is full. So a full tank flies
5.8% above the tier mean and a nearly-dry tank flies 5.6% below it.

**[DERIVED]** The shape averages exactly 1.0 (`sum/8 = 1.000`), which is why
`fullTankClimb()` can return `tier.climb` directly with no integration.

**[RULE]** Keep the mean at 1.0. If it drifts, `climb` stops meaning "what a full tank travels"
and every gate in §3 silently moves.

**[RULE]** Keep the taper **mild** (live spread is 0.944→1.058, a 12% swing). The taper exists so
a nearly-empty tank still makes visible progress — the harness asserts
`R × SPEED_SHAPE[1] > 1`, i.e. *a dribble flight still pays for itself.* A steep taper breaks
that and creates dead flights at the bottom of every ladder.

## 2.2 Current speed

**[LIVE]**
```lua
function FlightTuning.getFlightSpeed(power: number, stomachMax: number?): number
	local max = tonumber(stomachMax) or FlightTuning.TIERS[1].maxPower
	if max <= 0 then return 0 end
	local tier = FlightTuning.tierFor(max)
	local avg  = tier.climb / FlightTuning.tankSecondsFor(max)   -- the tier's mean speed
	local x    = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local band = math.min(NBANDS, math.floor(x * NBANDS) + 1)
	return avg * SPEED_SHAPE[band]
end
```

**[RULE] `stomachMax` is not optional in spirit.** The band is a fraction of *your own tank*, so
the same 100 fuel is "nearly empty" on a Colossus and "most of a tank" on a Hatchling. A caller
that omits it silently gets tier 1 behaviour.

## 2.3 Flight duration — the wall-clock dial

**[LIVE]**
```lua
FlightTuning.FLIGHT_SECONDS = 22.75
FlightTuning.TANK_SECONDS   = FlightTuning.FLIGHT_SECONDS

local TIER_TIME = {
	{ 120 , 1.00 },   -- Hatchling
	{ 270 , 1.00 },   -- Raptor
	{ 470 , 1.35 },   -- Dilo
	{ 620 , 1.50 },   -- Trike
	{ 1080, 1.55 },   -- Rex
	{ 1710, 1.60 },   -- Titan
	{ 2600, 1.60 },   -- Colossus
}

function FlightTuning.timeScaleFor(stomachMax) ... end          -- first row where max <= row[1]
function FlightTuning.tankSecondsFor(stomachMax)
	return FlightTuning.TANK_SECONDS * FlightTuning.timeScaleFor(stomachMax)
end
```

**[RULE] Speed and duration are ONE number, not two.** `speed = climb ÷ time`. Scaling a tier's
duration and dividing its speed by the same factor leaves `climb` **identical**, so *nothing that
gates the tower moves*. This is the only safe way to buy wall-clock time.

**[RULE] Speed must still rise with every gut.** This caps `TIER_TIME` from below. The Raptor is
fixed at 56.2 studs/s, so the Dilo's factor can never exceed **1.44** — past that, a *paid
upgrade flies slower than the gut before it*, which reads as a punishment for buying.

**[DERIVED]** Live per-tier physics:

| Tier | Gut | Tank | Flight secs | Mean speed | Drain %/s |
|---:|---|---:|---:|---:|---:|
| 1 | Hatchling Belly | 120 | 22.75 | **37.5** | 4.396 |
| 2 | Raptor Gut | 270 | 22.75 | **56.2** | 4.396 |
| 3 | Dilo Stomach | 470 | 30.71 | **60.2** | 3.256 |
| 4 | Trike Gut | 620 | 34.12 | **75.0** | 2.930 |
| 5 | Rex Gut | 1080 | 35.26 | **100.8** | 2.836 |
| 6 | Titan Gut | 1710 | 36.40 | **136.7** | 2.747 |
| 7 | Colossus Gut | 2600 | 36.40 | **195.3** | 2.747 |

> **Note:** `tools/ladder.py` prints `speeds [37.5, 56.2, 81.2, 112.5, 156.3, 218.8, 312.5]`.
> Those are `climb ÷ FLIGHT_SECONDS` — the **unscaled** figures, before `TIER_TIME`. The table
> above is what the player actually experiences. Both are correct; they answer different questions.

## 2.4 Fuel drain

**[LIVE]** `src/client/BottomHUD.client.luau`
```lua
local drain = 100 / FlightTuning.tankSecondsFor(stomachMax)   -- percent of meter per second
```

The meter is normalised 0–100 regardless of tank size. **[LIVE]** `FlightTuning.DRAIN_RATE`
(`100 / TANK_SECONDS`) is the legacy flat version and is **not** what the HUD uses — see the
drift note in §15.

## 2.5 Climb — the two core formulas

**[LIVE]** Distance a partially-filled tank travels:
```lua
function FlightTuning.climbFor(stomachMax: number, power: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local x = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local j = math.min(NBANDS - 1, math.floor(x * NBANDS))
	return FlightTuning.tierFor(max).climb * (CUM[j + 1] + (x - j / NBANDS) * SPEED_SHAPE[j + 1])
end
```

**[LIVE]** Its exact inverse — how full the tank must be to travel a distance:
```lua
function FlightTuning.powerForClimb(stomachMax: number, distance: number): number
	local max  = tonumber(stomachMax) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or dist <= 0 then return 0 end
	local y = dist / FlightTuning.tierFor(max).climb
	if y >= 1 then return max end
	for j = 1, NBANDS do
		if CUM[j + 1] >= y then
			return max * ((j - 1) / NBANDS + (y - CUM[j]) / SPEED_SHAPE[j])
		end
	end
	return max
end
```

**[RULE] Neither formula contains `FLIGHT_SECONDS`.** That is deliberate and load-bearing: it
makes every gate in the game **scale-free**. You can retime the entire realm without moving a
single gate. Do not introduce a time term into either function.

**[LIVE]** Full-tank climb is a straight lookup, because the shape averages 1:
```lua
function FlightTuning.fullTankClimb(stomachMax) return FlightTuning.tierFor(max).climb end
```

## 2.6 The ballistic coast

**[LIVE]** `BottomHUD.client.luau`: `local COAST_DAMPING = 0.4`

When thrust ends, leftover upward velocity is damped to 40%, which cuts the coast **distance** to
`0.4² = 0.16` of undamped. **[DERIVED]** The harness accounts for this in its gate check —
the coast adds only **1 to 22 studs** across the seven tiers, small enough that no gut gate leaks.

**[RULE]** Always verify gates against **climb + coast**, never climb alone. Without damping, the
free coast can push a tier over the next wall gap and silently make a gut optional.

## 2.7 What is universal vs realm-specific

| Universal — copy as-is | Realm-specific — re-solve |
|---|---|
| `SPEED_SHAPE` (8 bands, mean 1.0, mild taper) | `FLIGHT_SECONDS` (pacing preference) |
| `climbFor` / `powerForClimb` / `getFlightSpeed` | `TIER_TIME` factors (wall-clock target) |
| `COAST_DAMPING = 0.4` | `BASE_TIERS` climbs and tank sizes |
| The rule that climb formulas are time-free | Number of tiers |

---

# 3. STOMACHS / TANK PROGRESSION

## 3.1 The live table

**[LIVE]** `src/shared/StomachTiers.luau`

| # | Gut | `maxPower` | `cost` | `unlockSlot` | Currency |
|---:|---|---:|---:|---:|---|
| 1 | Hatchling Belly | 120 | 0 | 1 | — |
| 2 | Raptor Gut | 270 | 1,000 | 2 | coins |
| 3 | Dilo Stomach | 470 | 2,000 | 4 | coins |
| 4 | Trike Gut | 620 | 4,000 | 6 | coins |
| 5 | Rex Gut | 1,080 | 5,000 | 8 | coins |
| 6 | Titan Gut | 1,710 | 6,000 | 10 | coins |
| 7 | Colossus Gut | 2,600 | 11,500 | 12 | coins |
| — | Primal Gut | 9,999 | 499 | 1 | **Robux** |

**[RULE]** `unlockSlot` steps by 2 because each gut covers two crossings. **[RULE]** The purchase
is keyed on `maxPower`, not on the name — renaming a gut is free, changing its `maxPower` is not.

**[RULE]** `StomachTiers` tanks **must** equal `FlightTuning` tanks. The harness asserts this
(`StomachTiers tanks == FlightTuning tanks`). Two copies of the same number is how the shop ends
up pricing a tower that no longer exists.

## 3.2 The gate — how a gut becomes mandatory

**[RULE]** This is the central structural law of the entire game:

```
For every tier k:
    climb[k] ≥ max( gaps assigned to tier k )        ← the gut CAN clear its own crossings
    climb[k] <  min( gaps assigned to tier k+1 )     ← the gut CANNOT reach the next tier's
```

Break the first and a crossing is impossible. Break the second and the next gut becomes optional,
the wall disappears, and the crossing collapses to a 1-flight crossing.

**[DERIVED]** Live headroom, verified:

| Tier | Tank | Climb | Longest own gap | Headroom | Next tier's shortest gap | Shortfall |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 120 | 853.5 | 630.0 | **1.355×** | 1068.0 | **25.1% short** |
| 2 | 270 | 1279.5 | 1242.0 | **1.030×** | 1305.0 | **2.0% short** |
| 3 | 470 | 1848.0 | 1792.5 | **1.031×** | 1885.5 | **2.0% short** |
| 4 | 620 | 2559.0 | 2482.5 | **1.031×** | 2610.0 | **2.0% short** |
| 5 | 1080 | 3555.0 | 3448.5 | **1.031×** | 3625.5 | **2.0% short** |
| 6 | 1710 | 4977.0 | 4827.0 | **1.031×** | 6200.0 | **24.6% short** |
| 7 | 2600 | 7110.0 | 6200.0 | **1.147×** | — | top tier |

**[DERIVED]** Tier climb growth: ×1.50, ×1.44, ×1.38, ×1.39, ×1.40, ×1.43. **[RULE]** Keep tier
climb growth in the **1.35–1.50** band. Below ~1.3 the headroom arithmetic stops working (a tier
cannot both clear its stretch gap at 97% and fall 2% short of the next wall). Above ~1.6 the
stretch gap becomes a huge flight-count spike.

## 3.3 "Player choice, not forced UI" — how it is achieved

The brief: *a player should not be forced to buy a gut the moment it is affordable, but the
current gut should eventually become genuinely insufficient.*

**[DERIVED]** The Dinosaur Realm achieves this with **three** independent mechanisms:

1. **Affordable long before it is necessary.** Gut costs are priced *below what the previous
   crossing pays out*. A gut is buyable well before the wall. The harness's
   `FLIGHT-1 AFFORDABILITY` block shows the player holding e.g. 9,247 coins at c9 against a
   1,840 meal — there is real slack to spend or save.
2. **The wall is physical, not a prompt.** No UI ever says "you must upgrade." The player flies
   into a gap that is 2% past their reach, gets ~97% of the way with a *full* tank, and draws the
   conclusion themselves. It cannot be argued with and it cannot be missed.
3. **[LIVE] `COURTESY_FRACTION = 0` and `COURTESY_FULL_TANK = false`.** A freshly bought gut
   arrives **empty**. This is deliberate and was changed from 1.10 → 0.30 → 0.15 → 0. At 1.10, a
   new gut held more fuel than the next crossing needed, so *every gut purchase handed out a free
   crossing* and the wall crossing was always cleared on the very next launch. Now you buy the
   gut, then go and earn a meal for it — the purchase is a step, not a teleport.

**[RULE]** Never auto-fill a purchased tank. It converts the most meaningful decision in the game
into a cutscene.

## 3.4 The "stomach wall"

**[DERIVED]** The wall occurs on crossings **c2, c4, c6, c8, c10, c12** — the first crossing of
each new tier. At those points the previous gut reaches 97.2%+ of the gap on a full tank and
still cannot land.

**[REF]** Fraction of the **new** tank needed for each wall crossing: 84.3% (c2), 71.9% (c4),
74.9% (c6), 74.7% (c8), 74.1% (c10), 87.9% (c12). **[RULE]** Aim for ~75%. That leaves the player
able to clear the wall crossing without a perfect refill, which keeps the purchase feeling like
relief rather than another obstacle.

---

# 4. FOOD ECONOMY

## 4.1 The live menu

**[LIVE]** `src/shared/FoodMenu.luau` — `island` is the **island model number**; resolved through
`ISLAND_TO_SLOT`, food *n* sits on climb slot *n*.

| Slot | Food | Price | Power | Power/coin | vs Eggs | Island # |
|---:|---|---:|---:|---:|---:|---:|
| 1 | Eggs | 1,280 | 32 | 0.0250 | 1.00× | 1 |
| 2 | Chili Peppers | 1,480 | 40 | 0.0270 | 1.08× | 9 |
| 3 | Lettuce | 1,480 | 40 | 0.0270 | 1.08× | 5 |
| 4 | Grapes | 1,520 | 45 | 0.0296 | 1.18× | 12 |
| 5 | Bananas | 1,520 | 45 | 0.0296 | 1.18× | 3 |
| 6 | Popcorn | 1,720 | 55 | 0.0320 | 1.28× | 13 |
| 7 | Fish | 1,720 | 55 | 0.0320 | 1.28× | 7 |
| 8 | Ribs | 1,840 | 65 | 0.0353 | 1.41× | 4 |
| 9 | Potatoes | 1,840 | 65 | 0.0353 | 1.41× | 10 |
| 10 | Apples | 2,200 | 85 | 0.0386 | 1.55× | 2 |
| 11 | Mushrooms | 2,200 | 85 | 0.0386 | 1.55× | 8 |
| 12 | Chicken | 3,080 | 130 | 0.0422 | 1.69× | 6 |
| 13 | Steak | 3,080 | 130 | 0.0422 | 1.69× | 11 |

**[DERIVED]** Foods come in **identical pairs** (two slots share a price and power). One food per
island, thirteen islands, thirteen foods.

## 4.2 THE CRITICAL RULE — later food is never worse value

**[RULE]** `power/price` must be **monotonically non-decreasing** up the slot ladder.

Harness assertions:
```python
chk(all(eff[i] <= eff[i+1] + 1e-9 for i in range(12)), "food value never decreases up the tower")
chk(all(FOOD[i][2] <= FOOD[i+1][2] for i in range(12)), "food power never decreases up the tower")
chk(eff[-1] / eff[0] >= 1.5, "late food is a real upgrade")
```

**[DERIVED]** Live spread: **1.69×** from Eggs to Steak. This is the relationship that prevents
*"why would I buy this, my old food is better?"* — because it never is.

**[RULE] The value spread is capped from ABOVE by affordability, not by taste.** A wider spread
requires a bigger, pricier late meal, and every meal must cost less than the player is holding on
flight 1 of its own crossing. The harness demands ≥1.5× and the live menu delivers 1.69×; an
earlier attempt to force 1.8× could only be met by making late food expensive, which is exactly
the failure mode described in §4.4.

**[RULE]** Food power must also be non-decreasing. Cheaper-but-weaker late food would technically
pass the value test while being useless — you cannot fill a 2,600 tank efficiently out of 32-power
servings.

## 4.3 Servings, tanks and the meal-share rule

**[DERIVED]** Servings to fill a full tank with the tier's best food:

| Tier | Tank | Best food | Power | Servings/tank |
|---:|---:|---|---:|---:|
| 1 | 120 | Eggs | 32 | 3.75 |
| 2 | 270 | Chili Peppers | 40 | 6.75 |
| 3 | 470 | Grapes | 45 | 10.44 |
| 4 | 620 | Popcorn | 55 | 11.27 |
| 5 | 1080 | Ribs | 65 | 16.62 |
| 6 | 1710 | Apples | 85 | 20.12 |
| 7 | 2600 | Chicken | 130 | 20.00 |

**[DERIVED]** Servings actually needed per crossing, and the meal's share of its crossing:

| Crossing | Gap | Tier | Tank % needed | Power needed | Servings | Meal = % of crossing |
|---|---:|---:|---:|---:|---:|---:|
| c1 | 630.0 | 1 | 75.0% | 90.1 | 2.81 × Eggs | **36%** (tutorial, exempt) |
| c2 | 1068.0 | 2 | 84.3% | 227.7 | 5.69 × Chili | 18% |
| c3 | 1242.0 | 2 | 97.2% | 262.5 | 6.56 × Chili | 15% |
| c4 | 1305.0 | 3 | 71.9% | 338.1 | 7.51 × Grapes | 13% |
| c5 | 1792.5 | 3 | 97.2% | 456.7 | 10.15 × Grapes | 10% |
| c6 | 1885.5 | 4 | 74.9% | 464.5 | 8.45 × Popcorn | 12% |
| c7 | 2482.5 | 4 | 97.2% | 602.5 | 10.95 × Popcorn | 9% |
| c8 | 2610.0 | 5 | 74.7% | 806.4 | 12.41 × Ribs | 8% |
| c9 | 3448.5 | 5 | 97.2% | 1049.4 | 16.14 × Ribs | 6% |
| c10 | 3625.5 | 6 | 74.1% | 1267.2 | 14.91 × Apples | 7% |
| c11 | 4827.0 | 6 | 97.2% | 1661.3 | 19.54 × Apples | 5% |
| c12 | 6200.0 | 7 | 87.9% | 2285.5 | 17.58 × Chicken | 6% |

**[RULE]** `no meal past the tutorial exceeds 20% of its crossing` (live worst: 18% at c2).

Note how cleanly the **97.2%** figure repeats on every stretch crossing — that is §1.5's
`climb ÷ 1.031` showing up on the other side of the arithmetic.

## 4.4 Flight-1 affordability — the check that caught a failed ship

**[RULE]** *The player must be able to afford the food the ladder is solved for on the **first**
flight of a crossing.*

If they cannot, BUY MAX falls back on cheap food, effective value per coin collapses to the bottom
of the menu, `R` drops toward 1.0 and **the crossing never progresses**. A previous build shipped
a Rex-tier meal at 61% of its crossing and sat at 40% of the gap for nine flights.

**[REF]** Live margins (holdings vs best-food price):

| c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8 | c9 | c10 | c11 | c12 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2000 / 1280 | 2492 / 1480 | 4189 / 1480 | 4268 / 1520 | 5579 / 1520 | 2544 / 1720 | 6746 / 1720 | 6360 / 1840 | 9247 / 1840 | 7595 / 2200 | 12921 / 2200 | 6027 / 3080 |

## 4.5 Open choice

**[LIVE]** The server does **not** lock food to its own island — verified by the harness
(`the server does NOT lock food to its own island`). BUY MAX exists and sorts by **fuel-per-coin**,
not array order.

**[RULE]** Keep food purchasable anywhere. It converts food from a checkpoint into a decision:
a player can hoard cheap food or splurge on a better rung. Combined with the monotonic value rule,
this is safe — buying "ahead" is never a trap, and buying "behind" is never optimal.

---

# 5. COIN ECONOMY

## 5.1 The live constants

**[LIVE]**
```lua
FlightTuning.COIN_PER_STUD_BASE = 2.4024
FlightTuning.SPACING_SCALE      = 0.6825
FlightTuning.DESCENT_PAY_MULT   = 2.0
FlightTuning.MARGIN             = 1.08
```
**[LIVE]** `Shop.server.luau`: starting coins = **2,000**.
**[DERIVED]** `COIN_PER_STUD = COIN_PER_STUD_BASE / SPACING_SCALE = 2.4024 / 0.6825 = ` **3.5200**

**[RULE] `SPACING_SCALE` must be identical in `IslandOrder` and `FlightTuning`.** FlightTuning
warns at runtime if they drift. Its whole job is to divide `COIN_PER_STUD_BASE` at the point of
use so that respacing the tower does not change what a flight pays.

**[RULE]** `COIN_PER_STUD` must match in **`BottomHUD`** (the climb payout) and **`Bubbles`**
(bubble pricing). A coin bubble is priced as a fraction of what a flight pays; the two drifting
apart silently re-tunes the whole economy.

## 5.2 What a flight pays

**[RULE]** Coins are billed for **distance travelled**, not height gained.

| Outcome | Pays |
|---|---|
| **Crossing lands** | `gap × COIN_PER_STUD` (climb only — you never fall) |
| **Flight fails** | `d × COIN_PER_STUD × (1 + DESCENT_PAY_MULT)` = **3× the climb** |

**[RULE] That asymmetry is the single lever that sets flight counts.** It is not cosmetic. When
the descent payout was accidentally dead in an early build, a repeated flight earned 1× instead of
3×, `R` collapsed to ~1.0, and crossing 1 stalled at 35% forever — buy a meal, earn the meal back,
never accumulate.

**[LIVE]** Fuel is **not** wiped on touchdown. The harness confirms `TOUCHDOWN_EMPTIES = False`.
Leftover fuel carries to the next flight — the player keeps what they earned.

## 5.3 When the descent is paid (prepay)

**[LIVE]** `BottomHUD.client.luau`
```lua
local PREPAY_SAFETY = 0.90   -- only prepay when the tank falls this far short of the gap
```

The 2× fall bonus used to be settled in one lump at the apex, which made the counter snap upward
the instant the player started falling. It now works like this:

- **At launch**, `climbFor(stomachMax, currentPower)` predicts the peak. If the tank cannot reach
  `gap × 0.90`, the flight is **already** a failure and the 2× is already earned.
- **During the climb**, the fall is paid out continuously as the peak rises, on the same stud as
  the climb payout. The apex settle-up then finds nothing owing.
- **Totals are identical** — still 3× for a failure, 1× for a landing.
- The 0.90 margin is **one-sided on purpose**: a prepaid flight cannot surprise us by landing,
  which is the only case that would overpay.

**[RULE]** Never move the descent multiplier into the base climb rate. Paying every stud 3× makes
a *successful* crossing pay triple, which enriches the player at the top of every crossing and
costs flights all the way up. Predict the failure instead.

## 5.4 R — the return on a repeated flight

**[DERIVED]** This is the most important derived quantity in the game.

```python
R[c] = eff[c] × COIN_PER_STUD × (1 + DESCENT_PAY_MULT) × CLIMB[tier] / TANK[tier]
```
where `eff[c]` is the power-per-coin of the best affordable food.

**R is "how much further the next flight goes than this one."** R = 1.2 means each attempt
reaches ~20% higher than the last.

**[REF]** Live R per crossing:
```
[1.878, 1.353, 1.353, 1.229, 1.229, 1.394, 1.394, 1.228, 1.228, 1.187, 1.187, 1.219]
```

**[RULE]** Harness assertions on R:
- `R × SPEED_SHAPE[1] > 1` everywhere — *a dribble flight still pays for itself.*
- `min(R) ≥ 1.15`. **[DERIVED]** `100 / 1.187 = 84%` — this is what guarantees the last failed
  attempt lands around 84% rather than grinding through the 90s. **This single number is what
  prevents repeated near-misses.**

**[RULE]** To change flight counts, change **R**, not the gap. Lower R = more flights.

## 5.5 The one-flight-crossing law

**[LIVE]** Quoted from `Bubbles.client.luau`:

> a crossing pays `gap × COIN_PER_STUD`, and that pays for the NEXT crossing's fuel, so the next
> crossing is a one-flight crossing as soon as
> **`R_eff × gap[c] ≥ gap[c+1]`**
> (the tier climb cancels out)

**[DERIVED]** Live consecutive-gap ratios *within a tier* (no gut purchase between them):
c2→c3 = 1.163, c4→c5 = 1.373, c6→c7 = 1.317, c8→c9 = 1.321, c10→c11 = 1.331.

> **[UNKNOWN] / flagged:** the source comment cites `3638/2763 = 1.317` as the tightest pair.
> Those figures predate the current spacing and no longer appear in `SLOT_POS`. The *law* is
> sound and is what `CHAIN` is budgeted against; the specific example is historical. Re-derive
> the tightest pair for any new realm rather than copying 1.317.

## 5.6 The coin wall, and why it should not dominate

**[RULE]** The player will sometimes need extra flights on an island purely to bank enough for the
next gut. **This is a texture, not the loop.** It should emerge from how the player spends, saves,
refills, flies, whether they chase bubbles, and which events they happen to catch — so that two
players see meaningfully different runs.

How the live realm keeps it secondary:
- Guts are priced **below** the previous crossing's payout, so saving is short, not punishing.
- The **anti-strand floor** (§5.7) means a dry landing never becomes a dead end.
- Bubbles (§9) let an engaged player shave flights without ever being required.
- Events (§8) inject variance that the baseline does not depend on.

## 5.7 Anti-strand

**[LIVE]** `Shop.server.luau`: if a player lands dry and cannot afford a meal, the shop grants
exactly enough coins for **one serving** of the local food.

**[RULE]** The free meal must never hand over a crossing. Harness: `the free meal peaks at 36% of
a crossing` — asserted `< 100%`. An earlier version priced the top-up against
`powerShortfall()`, which handed the player a *whole crossing* on their first dry landing and
pinned every island at two attempts.

**[LIVE]** `FlightTuning.powerShortfall()` still exists but is documented in-file as **NOT WIRED**
for exactly this reason. It is kept for a possible HUD readout. **[RULE]** Never hand its answer
to the player as coins.

## 5.8 Uniform rescaling — the one safe economy edit

**[RULE]** Dividing (or multiplying) **every** coin quantity by the same factor is *provably*
balance-neutral, because every check in the harness is a ratio.

**[RULE]** But it is only neutral if it is **exact**. Prices must stay whole numbers, and this
ladder has almost no slack. A tested ÷2.3 forced sub-0.1% rounding and that alone cost **5
flights** (95 → 90), pushed the worst miss to 98%, and added a second flat flight. A ÷2 needed no
rounding at all and came back bit-identical.

**[RULE]** A rescale must touch **every** coin site, including ones outside the core loop.
Live inventory (9 files, 46 numbers):

| Site | File |
|---|---|
| 13 food prices | `src/shared/FoodMenu.luau` |
| 7 gut costs (coin only — **not** the Robux row) | `src/shared/StomachTiers.luau` |
| `COIN_PER_STUD_BASE` | `src/shared/FlightTuning.luau` |
| Starting coins | `src/server/Shop.server.luau` |
| `COIN_BONUS_PER_REBIRTH` | `src/server/Rebirth.server.luau` |
| 20 season-pass rewards | `src/server/SeasonPass.server.luau` |
| `FALLBACK_COINS` **× 3 copies** | `Constants.luau`, `DailyRewards_Server`, `Bootstrap.client` |

**[RULE]** Bubbles, the anti-strand meal and the Mercury payout are computed as fractions of
`COIN_PER_STUD` or of a food price, so they follow automatically. Do **not** rescale them again.

**[RULE]** A uniform rescale **cannot** change the ratio between the cheapest food and the most
expensive gut (live: 1,280 vs 11,500 ≈ **9×**). If a realm needs a wider spread than that, the
constraint is structural: food value-per-coin must not collapse (§4.2) and tank size caps how
much fuel a player can hold, so the whole economy's dynamic range is bounded by **tank growth**
(live: 120 → 2,600, ≈ 22×). Widening it requires per-tier income scaling with tier-dependent food
prices — a real system, not a relabel.

---

# 6. FLIGHTS BETWEEN ISLANDS

## 6.1 The reference ladder

**[REF]** Live flight curve — **this is a reference player, not a rule**:

```
FLIGHT CURVE [3, 7, 4, 8, 7, 8, 4, 10, 6, 13, 9, 16]   total 95
```

| Crossing | c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8 | c9 | c10 | c11 | c12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Flights | 3 | 7 | 4 | 8 | 7 | 8 | 4 | 10 | 6 | 13 | 9 | **16** |

**[DERIVED]** ~45–50 minutes of wall clock for that reference run.

## 6.2 The rules that shape it

**[RULE]** All asserted by the harness:
- `no crossing is under 3 flights` (live min: 3)
- `the opening crossing stays short` (≤ 4 flights; live: 3)
- `the late game reaches 8+ flights` (max of last four; live: 16)
- `flights generally increase: the back half is longer than the front`

**[RULE] Do not make every crossing identical.** The live curve deliberately alternates long and
short — 7, 4, 8, 7, 8, 4, 10, 6, 13, 9, 16. The short ones (c3, c7 at 4 flights) are the *stretch*
crossings where the player already owns the right gut and is simply spending it. They are the
breather between walls, and removing them makes the tower feel like one undifferentiated grind.

**[RULE]** The reference ladder assumes: no events, no bubbles, always buying the best affordable
food, and always flying the full tank. Real players will land above and below it. That is the
intent.

---

# 7. FAILED FLIGHT PROGRESSION

**This section is the heart of how a crossing feels.**

## 7.1 How to measure it

**[DERIVED]** For each attempt, record `reached ÷ gap` as a percentage. The sequence of those
percentages across a crossing is the **ladder**, and the harness prints it for all twelve.

## 7.2 The live ladders

**[REF]**

| Crossing | Gap | Tier | Ladder (each failed attempt as % of the gap) | Worst |
|---|---:|---|---|---:|
| c1 | 630.0 | Hatchling | 34 → 70 | 70% |
| c2 | 1068.0 | Raptor | 19 → 34 → 34 → 51 → 69 → 87 | 87% |
| c3 | 1242.0 | Raptor | 45 → 59 → 91 | 91% |
| c4 | 1305.0 | Dilo | 28 → 39 → 48 → 52 → 66 → 79 → 93 | 93% |
| c5 | 1792.5 | Dilo | 33 → 38 → 48 → 58 → 68 → 88 | 88% |
| c6 | 1885.5 | Trike | 14 → 23 → 30 → 34 → 46 → 65 → 82 | 82% |
| c7 | 2482.5 | Trike | 47 → 62 → 87 | 87% |
| c8 | 2610.0 | Rex | 25 → 31 → 38 → 39 → 47 → 55 → 69 → 80 → 97 | **97%** |
| c9 | 3448.5 | Rex | 44 → 48 → 60 → 73 → 86 | 86% |
| c10 | 3625.5 | Titan | 22 → 26 → 29 → 32 → 37 → 39 → 46 → 52 → 59 → 69 → 80 → 92 | 92% |
| c11 | 4827.0 | Titan | 34 → 38 → 43 → 50 → 55 → 65 → 76 → 90 | 90% |
| c12 | 6200.0 | Colossus | 11 → 13 → 14 → 16 → 19 → 22 → 25 → 27 → 33 → 38 → 44 → 53 → 61 → 73 → 88 | 88% |

## 7.3 Healthy ranges

**[RULE]**

| Band | Meaning |
|---|---|
| **First attempt 20–50%** | Healthy. Below ~15% the crossing reads as hopeless (c12's 11% is the deliberate exception). |
| **Middle attempts** | Must show **visible** movement. A step under ~3 percentage points reads as no progress. |
| **Final failed attempt 80–93%** | The sweet spot: "I nearly had it." |
| **Any attempt ≥ 94%** | Allowed **only** as the very last try before clearing. Live worst is 97% (c8). |
| **Two or more 90%+** | ❌ Broken. This is the "90 → 97 → 97 → 99" pattern to avoid at all costs. |

Harness assertions:
```python
chk(not early90,  "90%+ misses only ever happen on the last try before clearing")
chk(worst < 98,   "worst failed flight is X% and it is a final-try near-miss")
chk(len(flat) <= 1, "at most one flat flight in the whole tower")
```

**[REF]** Live: exactly **one** flat flight in the entire tower — `c2 try 3: 34% → 34%`. That is
the accepted budget.

## 7.4 Diagnosing a bad ladder

**[RULE]** The *cause* is almost never the gap. It is almost always `R`.

| Symptom | Real cause | Fix |
|---|---|---|
| Repeated 90%+ near-misses | `R` too low — each flight barely improves | Raise `R`: better food value, or raise `COIN_PER_STUD` |
| Flat flights (no visible movement) | `R` near 1.0, or the player cannot afford the intended food | Check flight-1 affordability first (§4.4) |
| Crossing cleared in 1–2 flights | `R` too high, or a gut gate is leaking | Verify `climb[k] < min(gaps of tier k+1)` **including coast** |
| First attempt under 10% | Gap genuinely too large for the tier | Reduce the gap, or move the crossing to the next tier |
| Whole tower too fast | — | Scale `TIER_TIME` (§2.3) — this changes wall clock **without** touching a single gate |

**[RULE] To tune spacing without destroying the economy:** change gaps only to fix a *gate*
(§3.2). For pacing, use `TIER_TIME`. For flight counts, use `R`. These three levers are
independent; mixing them is what makes tuning feel impossible.

---

# 8. RANDOM EVENTS

## 8.1 The live pool

**[LIVE]** `src/server/ServerEvents.server.luau` + `src/client/ServerEvents.client.luau`

```lua
CONFIG = {
	ENABLED = true, INTERVAL_MIN = 150, INTERVAL_MAX = 300,
	FIRST_DELAY_MIN = 90, FIRST_DELAY_MAX = 180, MIN_PLAYERS = 1,
}
```

| Event | Display | Weight | Duration | Speed | Gas drain | Coins | Bubbles | **Net climb effect** |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `FART_STORM` | 💨 FART STORM | 15 | 7 s | ×1.3 | — | — | — | **×1.30** |
| `COIN_RUSH` | 💰 COIN RUSH | 15 | 7 s | — | — | ×2 | — | none |
| `LOW_GRAVITY` | 🌙 HIGH GRAVITY † | 15 | 10 s | ×0.6 | ×0.5 | — | — | **×1.20** |
| `POWER_SURGE` | ⚡ POWER SURGE | 15 | 20 s | ×1.5 | ×1.25 | — | — | **×1.20** |
| `RING_FEVER` | 🎯 BUBBLE FEVER | 15 | 30 s | — | — | — | ×4 ring mult | none |
| `THUNDERSTORM` | ⛈ THUNDERSTORM | 15 | 20 s | — | — | — | — | **none — visual only** |

† Keyed `LOW_GRAVITY`, displayed "HIGH GRAVITY". A display-only rename inherited from the first
realm, kept so handler names line up.

**[DERIVED]** All weights are 15, so each event is exactly **1/6** likely.
**[DERIVED]** Climb effect is `speed ÷ drain` — this is the identity the event tuning is built on.
Note `POWER_SURGE` pairs a 1.5× speed with a 1.25× drain *deliberately*, so it lands on the same
1.2× climb as `LOW_GRAVITY` rather than an unpaired 1.5×.

**[UNKNOWN]** `THUNDERSTORM` sets **no gameplay multiplier** in the live client — it is a visual
event only. Whether it is *intended* to have a mechanical effect cannot be determined from the
files.

## 8.2 The rule

**[RULE] Events must never be part of baseline progression.** They are random in *type*, *timing*
and *whether they land during a flight at all*. Every number in §6 and §7 is computed with events
**off**. `tools/ladder.py` does not model them.

**[RULE]** Bound the best case. Live: the strongest climb event is ×1.30 for 7 seconds. Against a
22.75–36.4 s flight, that is at most a fraction of one flight's climb — enough to occasionally
save an attempt, never enough to skip a crossing.

**[RULE]** First-event delay must be non-trivial (live: 90–180 s). A brand-new player being buffed
in their first minute reads as a bug rather than a bonus.

---

# 9. BUBBLES / OPTIONAL BONUSES

## 9.1 Coin bubbles

**[LIVE]** `src/client/Bubbles.client.luau`
```lua
BUBBLE_SHARE = 0.0008,   -- fraction of ONE FLIGHT'S EARNINGS per bubble at the first streak step
STREAK_STEP  = 0.2,      -- multiplier = 1 + streak * 0.2
FEVER_SHARE  = 0.05,     -- RING_FEVER's per-bubble share
```
```lua
function COIN.baseBonus()  return gap * rate * COIN.BUBBLE_SHARE  end
```

**[DERIVED]** Bubbles are priced as a **fraction of the gap the player is currently crossing**,
not as a flat amount. That is what keeps them proportionate at every altitude. Six bubbles per gap
with the streak multiplier sum to `0.0008 × 9 = 0.72%` of a flight's earnings — the harness's
`CHAIN`.

**[RULE]** `CHAIN < (min(R) − 1) × 0.25`. **[DERIVED]** Live: `0.72% < 4.68%` ✅ — a full bubble
chain stays under a quarter of the thinnest per-flight margin in the tower.

**History that makes the rule concrete:** `BUBBLE_SHARE` was once **0.032**. Six bubbles then paid
`0.032 × 9 = 28.8%` of a crossing *on top of the crossing itself*, which pushed `R_eff` to ~1.42
and blew straight through the one-flight-crossing threshold of §5.5.

**[LIVE]** During `RING_FEVER`, `eventMult = FEVER_SHARE / BUBBLE_SHARE`, so a bubble pays
`gap × rate × 0.05` — about 2% of a full tank at **every** height, rather than a flat multiplier
that would be trivial low down and enormous up top.

## 9.2 Gas bubbles

**[LIVE]** `src/server/GasBubble.server.luau`
```lua
local GRANT_POWER  = 2      -- flat fart power per gas bubble, every gut, every tank
local MIN_INTERVAL = 0.34   -- seconds between accepted grants
local WINDOW_MAX   = 12     -- accepted grants per window
```

**[RULE]** A **flat** grant, deliberately — so it decays into irrelevance as tanks grow. That is
*the point, not a flaw*. An earlier percentage-based version (`GRANT_PERCENT = 0.002`) grew back
into the late game through rounding and rescued flights that should have failed.

## 9.3 The rule

**[RULE] Baseline progression must work with zero bubbles collected.** The harness models none.
Bubbles are a skill expression that shaves flights for an engaged player; they must never be the
difference between progressing and stalling.

**[RULE]** Because bubbles are gap-scaled and the core payout is stud-scaled, they stay
proportionate automatically when you respace a realm. Keep that property.

---

# 10. SPEED + SPACING + ECONOMY AS ONE SYSTEM

**Do not tune these separately.** This is the full dependency chain, with the live lever at each
step:

```
                    ISLAND GAP            [IslandOrder.SLOT_POS]
                         │
                         ▼
                  REQUIRED CLIMB          gap must be ≤ tier climb
                         │
                         ▼
                   FUEL REQUIRED          powerForClimb(tank, gap)
                         │
                         ▼
                  SERVINGS OF FOOD        power ÷ food.power
                         │
                         ▼
                     FOOD COST            servings × food.price
                         │
                         ▼
                  COINS REQUIRED          must be ≤ what the player holds on FLIGHT 1
                         │
                         ▼
                   FAILED FLIGHTS         each pays d × CPS × (1 + DESCENT)
                         │
                         ▼
                    COINS EARNED          R = eff × CPS × 3 × climb / tank
                         │
                         ▼
                 ABILITY TO REFILL        next attempt reaches R × previous
                         │
                         ▼
               ABILITY TO AFFORD GUT      gut cost < previous crossing's payout
                         │
                         ▼
                  NEW TANK CAPACITY       StomachTiers.maxPower
                         │
                         ▼
                NEW CLIMB CAPABILITY      FlightTuning climb (×1.35–1.50 per tier)
                         │
                         ▼
                  NEXT ISLAND GAP         wall = prev climb × 1.020
                                          stretch = new climb ÷ 1.031
```

## 10.1 What breaks what

**[RULE]** Consult this table **before** changing any single value:

| Change this… | …and this silently breaks | Why |
|---|---|---|
| A gap | The gut gate above **and** below it | `climb[k] ≥ max(own gaps)` and `climb[k] < min(next gaps)` |
| A tank size | Every gate, every serving count, R | `climb` is per-tier; R divides by tank |
| A food price | R, flight counts, flight-1 affordability | R is directly proportional to `power/price` |
| A food power | R **and** the monotonic-value rule | Both `eff` ordering and servings-per-tank |
| `COIN_PER_STUD` | R everywhere, **and bubble values** | Bubbles are a fraction of it |
| `DESCENT_PAY_MULT` | The landing-vs-failure asymmetry — i.e. **all** flight counts | It is the `(1 + D)` term in R |
| A gut cost | Flight-1 affordability of the **next** crossing | Coins spent on the gut are not available for food |
| `FLIGHT_SECONDS` / `TIER_TIME` | **Nothing structural** ✅ | Climb formulas are time-free — this is the safe pacing lever |
| `SPACING_SCALE` (both files) | **Nothing structural** ✅ | It cancels out of the coin rate by design |
| All coin values, uniformly & exactly | **Nothing** ✅ | Every check is a ratio (§5.8) |

**[RULE]** The last three rows are the **only** free levers. Everything else requires a harness
re-run and probably a re-tune.

---

# 11. UNIVERSAL RULES — DO NOT BREAK

### Structure
1. **Every gut covers exactly two crossings: one wall, one stretch.** Fewer, and half the tower has no saving pressure.
2. **`climb[k] ≥ max(gaps of tier k)`** — every crossing must be physically possible.
3. **`climb[k] < min(gaps of tier k+1)`, verified WITH the ballistic coast** — every gut must stay mandatory.
4. **Wall gap = previous climb × ~1.020.** The 2% shortfall *is* the "you need a bigger gut" message.
5. **Stretch gap = own climb ÷ ~1.031** (needs ~97% of the tank).
6. **Tier climb growth stays in 1.35–1.50×.**
7. **Tanks strictly increasing; gut prices strictly increasing.** A gut that costs less than a smaller one reads as a bug.
8. **Keep gut count small** (live: 7). Upgrades must stay milestones.

### Flights
9. **No intentional 1-flight crossings.** Live minimum is 3.
10. **The opening crossing stays short** (≤ 4).
11. **The late game reaches 8+ flights**; the back half is longer than the front.
12. **Every failed flight must make visible progress.** At most one flat flight in an entire realm.
13. **90%+ misses only on the last try before clearing.** Never 90 → 97 → 97 → 99.
14. **Worst failed flight < 98%.**
15. **`min(R) ≥ 1.15`** — this is what mechanically prevents rule 13.
16. **`R × SPEED_SHAPE[1] > 1`** — even a nearly-empty tank pays for itself.
17. **Do not make every crossing identical.** Alternating long/short is the intended texture.

### Food
18. **Later food must NEVER be worse value per coin.** Monotonic `power/price`, always.
19. **Food power must also be non-decreasing.**
20. **Late food ≥ 1.5× the value of the first food** — an upgrade must be a real upgrade.
21. **The player must afford the intended food on FLIGHT 1 of its crossing.** This is the check whose absence sank a previous ship.
22. **No meal past the tutorial exceeds 20% of its own crossing.**
23. **Food is buyable anywhere; BUY MAX sorts by fuel-per-coin.**

### Economy
24. **A failed flight pays 3×; a landing pays 1×.** This asymmetry is the flight-count lever — never flatten it.
25. **Never move the descent multiplier into the base climb rate.** Predict the failure at launch instead (§5.3).
26. **Do not wipe fuel on touchdown.** The player keeps what they earned.
27. **Do not auto-fill a purchased tank** (`COURTESY_FRACTION = 0`).
28. **Gut cost < the previous crossing's payout**, so saving is short.
29. **The anti-strand meal must never hand over a crossing** (live peak: 36%).
30. **`COIN_PER_STUD` must match in FlightTuning, BottomHUD and Bubbles.**
31. **`SPACING_SCALE` must match in IslandOrder and FlightTuning.**
32. **Uniform coin rescales must be EXACT** (no rounding) **and must touch every coin site**, including season pass, rebirth and all three `FALLBACK_COINS` copies.

### Speed
33. **`SPEED_SHAPE` must average exactly 1.0.**
34. **Keep the taper mild** (~12% spread).
35. **Climb formulas must remain time-free** — no `FLIGHT_SECONDS` in `climbFor`/`powerForClimb`.
36. **Speed must rise with every gut.** This caps how far `TIER_TIME` can stretch a tier.
37. **`speed = climb ÷ time`** — retiming is the only structurally free pacing lever.

### Reward pacing
38a. **Reward islands must alternate with blanks** — no two distinct rewards adjacent. Check the
     count first: `min adjacent pairs = max(0, k − (n − k + 1))`. For perfect alternation,
     `k ≤ (n + 1) / 2`.
38b. **Reward rarity must climb with the tower.**
38c. **Spawn island = slot 1, and it must be a reward island.**
38d. **Finale island = top slot** (Rebirth gates on the summit).

### Optional systems
38. **Random events can never be required.** All baseline numbers are computed with events off.
39. **Bubbles can never be required.** `CHAIN < (min(R) − 1) × 0.25`.
40. **Price bubbles as a fraction of the current gap**, never as a flat amount.
41. **Keep gas-bubble grants flat**, so they decay into irrelevance as tanks grow.

### Process
42. **`tools/ladder.py` must pass before shipping.** It parses the shipped files, not a model.
43. **All tuning lives in slot space, not island-number space.** Number a new realm's islands in
    climb order so `SLOT_TO_ISLAND` is the identity — but keep the table, because 47 call sites
    read it and it is what lets you reorder later.
44. **One copy of every number.** A second copy anywhere is a future desync bug.

---

# 12. FORMULAS + CALCULATIONS

Every formula below is **[LIVE]**, copied from the shipped source.

### 12.1 `climbFor(stomachMax, power)` — distance a partial tank travels
- **Variables:** tier climb, `SPEED_SHAPE`, `CUM`, fill fraction `power/max`
- **Realm-specific:** tier climb. **Universal:** the band walk, `SPEED_SHAPE`.
- **Increase tier climb →** every gap in that tier becomes easier; the gate above may leak.
- **Decrease →** the tier may not clear its own stretch gap; crossing becomes impossible.

### 12.2 `powerForClimb(stomachMax, distance)` — exact inverse of the above
- **Used by:** courtesy fill, the harness's `NF`, anti-strand sizing.
- **Increase distance →** required fill rises non-linearly (the taper means the last 10% of a gap costs more than the first 10%).

### 12.3 `getFlightSpeed(power, stomachMax)`
```
avg  = tier.climb / tankSecondsFor(stomachMax)
band = min(8, floor((power/max) * 8) + 1)
speed = avg * SPEED_SHAPE[band]
```
- **Increase `TIER_TIME[k]` →** that tier flies slower and longer; **climb is unchanged**.
- **Decrease →** faster, shorter; climb still unchanged. **This is the wall-clock dial.**

### 12.4 `tankSecondsFor(stomachMax) = TANK_SECONDS × timeScaleFor(stomachMax)`
- **Universal:** the shape of the relationship. **Realm-specific:** `FLIGHT_SECONDS`, the factors.

### 12.5 Fuel drain
```
drain (%/sec) = 100 / tankSecondsFor(stomachMax)
```
- Meter is normalised 0–100 for all tanks, so the bar always empties in one flight.

### 12.6 Coin rate
```
COIN_PER_STUD = COIN_PER_STUD_BASE / SPACING_SCALE
```
- **Increase →** everything gets easier and every crossing loses flights.
- **Decrease →** more flights, but food may become unaffordable on flight 1 (§4.4). **Not a safe standalone lever.**

### 12.7 Flight payout
```
landing  : gap × COIN_PER_STUD
failure  : d   × COIN_PER_STUD × (1 + DESCENT_PAY_MULT)
```

### 12.8 R — return on a repeated flight
```
R[c] = (food.power / food.price) × COIN_PER_STUD × (1 + DESCENT_PAY_MULT)
       × CLIMB[tier(c)] / TANK[tier(c)]
```
- **The single most important derived value.** **Increase →** fewer flights. **Decrease →** more flights, until it falls under ~1.15 and the ladder starts grinding through the 90s.

### 12.9 Bubble value
```
baseBonus       = gap × COIN_PER_STUD × BUBBLE_SHARE
streak multiplier = 1 + streak × STREAK_STEP
RING_FEVER      : eventMult = FEVER_SHARE / BUBBLE_SHARE
CHAIN           = BUBBLE_SHARE × 9      (six bubbles with the streak stack)
```

### 12.10 Event climb effect
```
climb multiplier = serverEventSpeedMult / serverEventGasDrainMult
```

### 12.11 Gap solving (the inverse design problem)
```
wall gap of tier k    = climb[k−1] × 1.020
stretch gap of tier k = climb[k]   ÷ 1.031
```

### 12.12 Coast
```
coast distance ≈ undamped × COAST_DAMPING²      (0.4² = 0.16)
```

### 12.13 Not wired — do not use
```lua
FlightTuning.powerShortfall(stomachMax, currentPower)  -- = (1/MARGIN) × max − currentPower
```
**[LIVE]** Documented in-file as NOT WIRED. **[RULE]** Never pay its answer out as coins.

> **[UNKNOWN]** `FlightTuning.MARGIN = 1.08` is live and is referenced by `powerShortfall` (unwired)
> and by the food-price derivation comment. But the live tiers run at **1.031** headroom on their
> stretch gaps, not 1.08. The two do not currently agree, and which one a new realm should target
> cannot be settled from the files. **Use the empirical 1.031 / 1.020 pair from §1.5** — those are
> what the shipped tower actually does and what the harness validates.

---

# 13. HOW TO BUILD A NEW REALM

Work in this order. **Each step depends on the one before it.** Do not jump ahead — in particular,
do not place islands until step 4.

### Step 1 — Decide the shape (no numbers yet)
- How many islands? (Live: 13 → 12 crossings.)
- How many guts? **[RULE]** crossings = 2 × (guts − 1). Live: 7 guts → 12 crossings.
- Target run length in minutes.

### Step 2 — Choose tank sizes
- Pick tier 1 (live: 120) and grow at **×1.35–1.50 per tier**.
- **[RULE]** Strictly increasing.

### Step 3 — Solve tier climbs
- Choose tier 1's climb as a comfortable multiple of your intended first gap (live: 853.5 vs a 630 gap = 1.355× — deliberately loose for the tutorial).
- Grow climbs at **×1.35–1.50** per tier.
- These are `BASE_TIERS[k].climb`.

### Step 3b — Lay out reward pacing *(on paper, before you name anything)*
- Decide which slots are **reward/quest** islands and which are blanks.
- **[RULE]** Alternate them; rarity climbs bottom→top; slot 1 and the top slot are both rewards.
- **[RULE]** Check the count against §1.1.2 *now*: `k ≤ (n + 1) / 2` alternates perfectly. Going
  over means forced adjacent pairs — decide their duplicate/shared rewards here, not later.
- **Then** name your island models in climb order, so `SLOT_TO_ISLAND` is the identity
  `{1, 2, 3, …}`. Do not inherit the Dinosaur Realm's scramble — it is a retrofit, not a pattern.

### Step 4 — Solve the gaps *(now you can place islands)*
```
tier 1 : one gap at climb[1] ÷ 1.355        (loose tutorial)
tier k : wall    = climb[k−1] × 1.020
         stretch = climb[k]   ÷ 1.031
top    : the summit gap may be widened for a long final grind (live: +24.6%)
```
- Accumulate into Y positions from your ground island's Y.
- Alternate X/Z offsets so the tower reads as a spiral.
- Write `SLOT_POS`, `SLOT_TO_ISLAND`, `NAMES`.

### Step 5 — Verify the gates *before anything else*
```
climb[k] ≥ max(gaps of tier k)
climb[k] + coast < min(gaps of tier k+1)
```
**Do not proceed until these hold.** Everything downstream assumes them.

### Step 6 — Set the pacing
- Pick `FLIGHT_SECONDS` and per-tier `TIER_TIME` factors to hit your minute target.
- **[RULE]** Check that mean speed **rises** at every tier. That caps the early factors.
- This step **cannot** break step 5 — climb is time-free.

### Step 7 — Design the food menu
- One food per island. **[RULE]** `power/price` monotonically non-decreasing; power non-decreasing; last ÷ first ≥ 1.5.
- Size power so the tier's best food gives a sane serving count (live: 3.75 → 20 per tank).
- Set prices so **no meal past the tutorial exceeds 20% of its crossing**.

### Step 8 — Set the coin rate and solve R
```
R[c] = eff[c] × CPS × (1 + DESCENT) × climb[tier] / tank[tier]
```
- Tune `COIN_PER_STUD` until **`min(R) ≥ 1.15`** and the flight curve lands where you want.
- Keep `DESCENT_PAY_MULT = 2.0` unless you have a specific reason.

### Step 9 — Price the guts
- **[RULE]** Each gut costs **less than the previous crossing's total payout**.
- Strictly increasing.

### Step 10 — Set starting coins
- Enough for the tutorial ladder (live: 2,000 against a 1,280 first meal — a 3-rung ladder off the starting bank, not off income).

### Step 11 — Run the harness
```
python tools/ladder.py
```
- Fix failures **in the order the harness prints them** — gates first, then food, then R, then the ladder.

### Step 12 — Verify flight-1 affordability
- The harness's `FLIGHT-1 AFFORDABILITY` block must be all-OK. This is the check that has sunk a build before.

### Step 13 — Layer the optional systems last
- Events: verify the strongest climb multiplier can't skip a crossing.
- Bubbles: verify `CHAIN < (min(R) − 1) × 0.25`.
- Neither may be needed for the baseline.

### Step 14 — Wall-clock check
- Play or estimate the run. If it is off target, go back to **step 6 only**. Never fix pacing with spacing.

---

# 14. DINOSAUR REALM — CURRENT LIVE REFERENCE

> **These are REFERENCE values for one specific realm. They are NOT universal constants.**
> Copy the *rules* from §11 and the *procedure* from §13. Re-solve these numbers for a new realm.

## 14.1 Master crossing table

| Slot | Island # | Name | X | Y | Z | Gap up | Cumul. | Tier | Gut | Tank | Gut cost | Tier climb | Tank % needed | Food here | Price | Power | Ref. flights |
|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---|---:|---:|---:|
| 1 | 1 | Nesting Nook | 0 | 150 | 0 | 630.0 | 0 | 1 | Hatchling Belly | 120 | 0 | 853.5 | 75.0% | Eggs | 1,280 | 32 | **3** |
| 2 | 9 | Frostbite Flats | 120 | 780 | 60 | 1068.0 | 630.0 | 2 | Raptor Gut | 270 | 1,000 | 1279.5 | 84.3% | Chili Peppers | 1,480 | 40 | **7** |
| 3 | 5 | Misty Mire | −160 | 1848 | 100 | 1242.0 | 1698.0 | 2 | Raptor Gut | 270 | — | 1279.5 | 97.2% | Lettuce | 1,480 | 40 | **4** |
| 4 | 12 | Sunscorch Sands | 180 | 3090 | −120 | 1305.0 | 2940.0 | 3 | Dilo Stomach | 470 | 2,000 | 1848.0 | 71.9% | Grapes | 1,520 | 45 | **8** |
| 5 | 3 | Fossil Frontier | −200 | 4395 | 160 | 1792.5 | 4245.0 | 3 | Dilo Stomach | 470 | — | 1848.0 | 97.2% | Bananas | 1,520 | 45 | **7** |
| 6 | 13 | Glacier Gulch | 220 | 6187.5 | −180 | 1885.5 | 6037.5 | 4 | Trike Gut | 620 | 4,000 | 2559.0 | 74.9% | Popcorn | 1,720 | 55 | **8** |
| 7 | 7 | Claw Cliffs | −240 | 8073 | 200 | 2482.5 | 7923.0 | 4 | Trike Gut | 620 | — | 2559.0 | 97.2% | Fish | 1,720 | 55 | **4** |
| 8 | 4 | Coastal Crossing | 260 | 10555.5 | −220 | 2610.0 | 10405.5 | 5 | Rex Gut | 1,080 | 5,000 | 3555.0 | 74.7% | Ribs | 1,840 | 65 | **10** |
| 9 | 10 | Petrified Pass | −280 | 13165.5 | 240 | 3448.5 | 13015.5 | 5 | Rex Gut | 1,080 | — | 3555.0 | 97.2% | Potatoes | 1,840 | 65 | **6** |
| 10 | 2 | Fern Frontier | 300 | 16614 | −260 | 3625.5 | 16464.0 | 6 | Titan Gut | 1,710 | 6,000 | 4977.0 | 74.1% | Apples | 2,200 | 85 | **13** |
| 11 | 8 | Inferno Isle | −320 | 20239.5 | 280 | 4827.0 | 20089.5 | 6 | Titan Gut | 1,710 | — | 4977.0 | 97.2% | Mushrooms | 2,200 | 85 | **9** |
| 12 | 6 | Redwood Ridge | 340 | 25066.5 | −300 | 6200.0 | 24916.5 | 7 | Colossus Gut | 2,600 | 11,500 | 7110.0 | 87.9% | Chicken | 3,080 | 130 | **16** |
| 13 | 11 | Volcanic Vista | −360 | 31266.5 | 320 | — | 31116.5 | 7 | Colossus Gut | 2,600 | — | 7110.0 | — | Steak | 3,080 | 130 | — |

## 14.2 Speed reference

| Tier | Gut | Tank | Climb | Flight secs | Mean speed | Drain %/s | `TIER_TIME` |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Hatchling Belly | 120 | 853.5 | 22.75 | 37.5 | 4.396 | 1.00 |
| 2 | Raptor Gut | 270 | 1279.5 | 22.75 | 56.2 | 4.396 | 1.00 |
| 3 | Dilo Stomach | 470 | 1848.0 | 30.71 | 60.2 | 3.256 | 1.35 |
| 4 | Trike Gut | 620 | 2559.0 | 34.12 | 75.0 | 2.930 | 1.50 |
| 5 | Rex Gut | 1,080 | 3555.0 | 35.26 | 100.8 | 2.836 | 1.55 |
| 6 | Titan Gut | 1,710 | 4977.0 | 36.40 | 136.7 | 2.747 | 1.60 |
| 7 | Colossus Gut | 2,600 | 7110.0 | 36.40 | 195.3 | 2.747 | 1.60 |

## 14.3 Economy reference

| Value | Live |
|---|---|
| Starting coins | 2,000 |
| `COIN_PER_STUD_BASE` | 2.4024 |
| `SPACING_SCALE` | 0.6825 |
| **Effective `COIN_PER_STUD`** | **3.5200** |
| `DESCENT_PAY_MULT` | 2.0 |
| `MARGIN` | 1.08 *(see §12.13 caveat)* |
| `FLIGHT_SECONDS` / `TANK_SECONDS` | 22.75 |
| `COIN_TICK` | 0.23 s |
| `PAYOUT_SECONDS` | 0.15 s |
| `COAST_DAMPING` | 0.4 |
| `PREPAY_SAFETY` | 0.90 |
| `COURTESY_FRACTION` | 0 |
| `COURTESY_FULL_TANK` | false |
| `BUBBLE_SHARE` | 0.0008 |
| `FEVER_SHARE` | 0.05 |
| `STREAK_STEP` | 0.2 |
| Gas bubble `GRANT_POWER` | 2 |
| R per crossing | `[1.878, 1.353, 1.353, 1.229, 1.229, 1.394, 1.394, 1.228, 1.228, 1.187, 1.187, 1.219]` |
| Bubble `CHAIN` | 0.72% of a flight |
| Total climb | 31,116.5 studs |
| Reference flight curve | `[3,7,4,8,7,8,4,10,6,13,9,16]` = **95 flights** |
| Worst failed flight | 97% (c8, final try) |
| Flat flights | 1 (c2 try 3) |

---

## APPENDIX — Harness assertion index

Every check in `tools/ladder.py`, which is the executable form of §11:

```
food value never decreases up the tower
food power never decreases up the tower
late food is a real upgrade (≥1.5× the value of the first food)
no meal past the tutorial exceeds 20% of its crossing
exactly 7 guts -- gut upgrades stay milestones
tier k climb reaches its longest gap                      (×7)
tier k climb does NOT reach the next tier's shortest gap  (×6)
tier k reaches climb + coast and still cannot make the next gap -- gut stays MANDATORY (×6)
StomachTiers tanks == FlightTuning tanks
tanks strictly increasing
gut prices strictly increasing
R × SPEED_SHAPE[1] > 1 everywhere (a dribble flight still pays)
R never drops so low the ladder must step through the 90s (min ≥ 1.15)
a bubble chain stays small against the thinnest margin
every crossing can afford its best food on flight 1
no crossing is under 3 flights
90%+ misses only ever happen on the last try before clearing
worst failed flight < 98% and it is a final-try near-miss
the late game reaches 8+ flights
flights generally increase: the back half is longer than the front
the opening crossing stays short (≤4)
at most one flat flight in the whole tower
the free meal peaks at <100% of a crossing
the server does NOT lock food to its own island
BUY MAX still exists
BUY MAX sorts by fuel-per-coin rather than array order
```

---

*End of guide. When this document and the code disagree, the code is right — re-derive and update
this file. When this document and `tools/ladder.py` disagree, the harness is right.*
