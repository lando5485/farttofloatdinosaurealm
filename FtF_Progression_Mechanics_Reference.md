# Fart to Float — Island Spacing & Stomach/Power/Food Gating Reference

> Reference doc for porting FtF's flight-progression gating into **Space Realm**.
> Every number below is pulled from the live source, not from `CLAUDE.md` (which is
> stale on several values — see the "Where this differs from CLAUDE.md" note at the end).
>
> Source files scanned:
> - `src/server/PlayerStats.server.lua` — island positions, food table, stomach tiers, buy logic, coin accumulation
> - `src/client/CoreClient.client.lua` — flight physics, gas/power math, height ceiling, island unlock, coin earn
> - `src/client/ShopClient.client.lua` — food/stomach buying UI + buy events

---

## 1) ISLAND SPACING

### 1a. All 14 islands, exact Y, and gaps

Positions come from a **hardcoded table** of `{x, y, z}` literals. The server table
is `ISLAND_POSITIONS` (`PlayerStats.server.lua:83`) and the client mirrors it exactly
as `ISLAND_POS` (`CoreClient.client.lua:150`). They are identical. The "Positioned
Island_X at Y=…" print just echoes `ISLAND_POSITIONS[i].y` — there is **no computed
spacing formula**; every Y is a literal a designer tuned by hand.

| # | Island          | X    | **Y (height)** | Z    | **Gap to next** |
|---|-----------------|------|----------------|------|-----------------|
| 1 | Bean Farm       | 0    | **150**        | 0    | 640             |
| 2 | Broccoli Bluff  | 120  | **790**        | 60   | 890             |
| 3 | Cabbage Cliffs  | -160 | **1680**       | 100  | 800             |
| 4 | Turnip Tranquil | 180  | **2480**       | -120 | 1100            |
| 5 | Coconut Cove    | -200 | **3580**       | 160  | 1240            |
| 6 | Bread Board     | 220  | **4820**       | -180 | 1640            |
| 7 | Pasta Peak      | -240 | **6460**       | 200  | 1742            |
| 8 | Popcorn Pinnacle| 260  | **8202**       | -220 | 1530            |
| 9 | Milk Marsh      | -280 | **9732**       | 240  | 2246            |
| 10| Butter Swamp    | 300  | **11978**      | -260 | 2216            |
| 11| Ice Cream Isle  | -320 | **14194**      | 280  | 2944            |
| 12| Burger Bluff    | 340  | **17138**      | -300 | 3068            |
| 13| Burrito Barrens | -360 | **20206**      | 320  | 3811            |
| 14| Pizza Palms     | 380  | **24017**      | -340 | — (top)         |

Total vertical span: **150 → 24,017** (≈23,867 studs from island 1 to island 14).

### 1b. How spacing scales as you go up

The gaps **increase non-linearly** — they trend upward but are not a clean arithmetic
or geometric series (they were hand-tuned). Pattern:

- **Early (1→5):** ~640–1100 stud gaps. Small, easy hops.
- **Mid (5→9):** ~1100–1742. Gaps roughly +150–300 each step.
- **Late (9→14):** ~2200–3811. Gaps balloon; the last gap (13→14) is **3811**, ~6× the first gap (640).

So the curve is "gently widening early, sharply widening late." Each island is not a
fixed multiple of the previous — eyeballed ratios run ~1.3–1.9× early and settle near
~1.1–1.2× of the running height late (because absolute heights are already huge).

A useful way to express it for Space Realm: **cumulative height roughly doubles every
~3 islands** early and the **per-gap delta grows ~roughly linearly** in the late game
(gap ≈ 2200 → 3800 over islands 9→14).

### 1c. Stand / landing positions per island

There is **no separate stand-coordinate table**. The `{x,y,z}` in the island table *is*
the island's nominal position, and the player lands on / shops at the physical island
model placed there. At runtime the server **detects the real stand part** on each island
model and builds `standData[islandNum]` (`PlayerStats.server.lua:472`, populated ~8s
after start), used for respawns and "return to home island":

Detection order (first hit wins):
1. A child model literally named `Stand_<n>` → its PrimaryPart/first BasePart position.
2. Any `ProximityPrompt` on the island → walk up to its nearest BasePart.
3. The island model's `PrimaryPart`.
4. **Largest non-NPC BasePart** in the island (the platform) — robust catch-all.
5. **Fallback:** `ISLAND_POSITIONS[n]` itself (the table Y above).

The player is spawned `SPAWN_FRONT_DIST = 14` studs **in front** of the stand and
`STAND_OFFSET_Y = 10` studs **above** the stand part center. A "Return" prompt appears
if they fall `CATCH_MARGIN = 50` studs below their home stand.

> Practical takeaway for Space Realm: treat the table Y as the island's height; the
> "stand" is just a platform sitting at that Y that the player physically lands on.
> Three islands also get a **pure-visual Y rotation** (no height change): Cabbage 180°,
> Coconut 180°, Pasta −90° (`ISLAND_ROTATIONS`).

---

## 2) STOMACH / POWER / GAS SYSTEM

### 2a. Definitions — what each term means

| Term | What it is | Range |
|------|-----------|-------|
| **Power** (`CurrentPower`) | Raw fuel currently in the tank. Food adds power. This is the actual stored fuel. | 0 … StomachMax |
| **StomachMax** (gut tier) | The tank's **capacity** — the max power the gut can hold. Set by which gut you own. | 100 … 9999 |
| **Gas meter** (`gasMeter`) | A 0–100 **normalized display** of how full the tank is: `gasMeter = (CurrentPower / StomachMax) * 100`. It's the bar the player sees and what the flight loop drains. | 0 … 100 (`maxGasMeter`) |

Relationship, exactly as the code does it:

```
gasMeter   = (CurrentPower / StomachMax) * 100      -- normalize tank to a 0–100 bar
-- during flight, the loop drains gasMeter, then back-solves power:
scaledPower = (gasMeter / 100) * StomachMax          -- live power from remaining gas
CurrentPower = scaledPower
```

So **power and gas are the same quantity in two units**: power is raw (0..StomachMax),
gas is that same fill normalized to 0..100. Buying food raises power; flying drains gas
(which is just power expressed as a percentage of the gut).

### 2b. Stomach capacity tiers (the full gut progression)

From `stomachTiers` (`PlayerStats.server.lua:65`). Buying carries over the power already
in the tank — **only the max grows, the current fill is NOT reset** (`:1497-1502`).

| Tier | `maxPower` (capacity) | Cost | Currency |
|------|----------------------|------|----------|
| **Tiny Gut**     | 100  | 0       | — (default starting gut) |
| **Small Gut**    | 182  | 1,600   | Coins |
| **Medium Gut**   | 520  | 3,000   | Coins |
| **Large Gut**    | 1,075| 5,200   | Coins |
| **XL Gut**       | 2,146| 8,000   | Coins |
| **Iron Gut**     | 3,218| 11,000  | Coins |
| **Infinite Gut** | 9,999| 499     | **Robux** (premium; top of the map) |

`BuyStomachEvent` validates that the `(maxPower, cost)` pair matches a real non-Robux
tier and that the player can afford it before swapping `StomachMax`.

### 2c. Food data (price + power each food gives)

From the `foods` table — **identical in server (`PlayerStats.server.lua:46`) and client
(`CoreClient.client.lua:158`)**. Each food is the food sold at its island's stand.
The comment documents the intended pricing curve:
`price = round(power * (0.8 + (island-1)/13 * 2.2))` — though the live table has been
hand-edited away from that formula in several spots (e.g. Beans=5, Popcorn=600).

| Island | Food     | Price (coins) | **Power per buy** |
|--------|----------|---------------|-------------------|
| 1  | Beans    | 5    | 8   |
| 2  | Broccoli | 24   | 25  |
| 3  | Cabbage  | 85   | 45  |
| 4  | Turnips  | 94   | 70  |
| 5  | Coconuts | 142  | 100 |
| 6  | Bread    | 138  | 140 |
| 7  | Pasta    | 202  | 185 |
| 8  | Popcorn  | 600  | 240 |
| 9  | Milk     | 500  | 300 |
| 10 | Butter   | 400  | 370 |
| 11 | IceCream | 560  | 450 |
| 12 | Burger   | 405  | 540 |
| 13 | Burrito  | 700  | 640 |
| 14 | Pizza    | 518  | 750 |

**How buying food works** (`BuyFoodEvent`, `PlayerStats.server.lua:757`):
1. Reject if `coins < price`.
2. Compute `newPower = CurrentPower + food.power`.
3. **Stomach-full check uses `>` (strict):** if `newPower > effectiveMax` → reject, fire
   `StomachFullEvent`, and **return BEFORE deducting coins** (player keeps their coins).
   A buy that lands exactly on the max is allowed.
4. Otherwise deduct coins, set `CurrentPower = newPower`.
5. **BUY MAX** (client) buys `min(fits-in-stomach, can-afford)` at once.

The 2× Fart Power perk (`POWER_PASS_MULT = 1.4`) multiplies both the power each food
gives **and** the effective tank size by 1.4× when active. *(Note: currently neutralized
in balance testing — `DISABLE_PERKS_FOR_BALANCE`/`DISABLE_2X` — so baseline is 1.0×.)*

### 2d. How power converts into flight (height & distance)

Two separate things matter: the **hard height ceiling** (gates unlocks) and the
**flight speed bands** (how fast you physically climb).

**Hard ceiling — the gut's reach** (`CoreClient.client.lua:1691`):
```
getMaxHeight() = 50 + (StomachMax * 14)
```
This depends on **StomachMax (the gut tier), NOT current power.** It is the height ceiling
used to decide which islands a gut is *allowed* to unlock. Per tier:

| Gut | StomachMax | **Ceiling = 50 + max·14** | Highest island Y it permits |
|-----|-----------|---------------------------|------------------------------|
| Tiny     | 100  | **1,450**   | Island 2 (790) — island 3 is 1680, blocked |
| Small    | 182  | **2,598**   | Island 4 (2480) |
| Medium   | 520  | **7,330**   | Island 7 (6460) |
| Large    | 1,075| **15,100**  | Island 11 (14194) |
| XL       | 2,146| **30,094**  | Island 14 (24017) — ceiling clears the whole map |
| Iron     | 3,218| **45,102**  | Island 14 (all) |
| Infinite | 9,999| **140,036** | Island 14 (all) |

**Flight speed bands — how fast you rise** (`getFlightSpeed(power)`, `CoreClient.client.lua:1937`).
While farting, the BodyVelocity's **Y velocity = `getFlightSpeed(scaledPower)`** (studs/sec),
and `scaledPower` falls as gas drains, so the player steps **down** through these bands
during a flight:

| Current power | Rise speed (studs/s) |
|---------------|----------------------|
| ≤ 100  | 40  |
| ≤ 182  | 62  |
| ≤ 611  | 84  |
| ≤ 1075 | 126 |
| ≤ 2146 | 144 |
| ≤ 3218 | 226 |
| > 3218 | 280 |

Speed is then ×`serverEventSpeedMult` (event bonus, default 1) and ×2 if a 2× boost is
active. Horizontal steering is a flat `FLIGHT_HORIZONTAL_SPEED = 48` studs/s on X/Z
(independent of vertical rise). The full velocity each frame:
`BodyVelocity.Velocity = Vector3(moveX*48 + wind, riseSpeed, moveZ*48 + wind)`.

**Gas drain:** `DRAIN_RATE = 3.5` gas/second → a full 100-gas tank lasts **~28.6 seconds**
of continuous farting (`CoreClient.client.lua:231, 1991`).

> **Important nuance:** Vertical motion is pure physics — `BodyVelocity` Y = riseSpeed
> while thrusting, then gravity after gas runs out (coast up, then fall). There is **no
> "you reach exactly height = f(power)" formula.** Peak height = how high the player
> physically climbs given their speed bands and ~28s of fuel. The `getMaxHeight()`
> ceiling is only the *eligibility gate* for unlocking, applied on top of the actual
> peak. To unlock island N you need **both**: `peakHeight ≥ island Y` **and**
> `island Y ≤ getMaxHeight()`.

---

## 3) HOW THEY GATE PROGRESSION (the core loop)

### 3a. The core loop

```
Buy food (costs coins, adds power up to StomachMax)
   → tank fills (gas meter rises)
      → hold fart button: rise at speed(power), gas drains 3.5/s (~28s)
         → peak height reached; islands unlock where peakY ≥ islandY AND islandY ≤ getMaxHeight()
            → earn coins from height during the flight
               → land, buy more food / save for next gut
                  → if the gut ceiling blocks the next island, BUY THE NEXT GUT
                     → repeat
```

Two gates stack:
1. **Gut ceiling** (`50 + StomachMax·14`) — a hard cap. You physically cannot unlock an
   island above your gut's ceiling no matter how you fly. This is what forces gut upgrades.
2. **Fuel + speed** — even under the ceiling, you must actually climb to the island's Y
   within ~28s of gas. Bigger gut → more power → higher speed band → climbs faster/higher
   before fuel runs out.

So **gut upgrades are the true progression gate**; food is the per-flight consumable that
fills whatever gut you currently own.

### 3b. Island unlock logic (exact)

`checkPeakUnlock(peakY)` (`CoreClient.client.lua:1698`), called every flight frame:
```lua
for n = highestUnlocked+1, 14 do
    iy = ISLAND_POS[n].y
    if peakY >= iy and iy <= getMaxHeight() then
        unlock island n
    else
        break   -- must unlock in strict order; stop at the first one you can't reach
    end
end
```
Islands unlock **strictly in order**. Reaching the *peak* unlocks the island (lets you shop
there); the server's separate physical-landing raycast is what fires the "You reached
[Island]!" welcome and sets the home base.

### 3c. Power/stomach needed per gap (how requirement scales)

Because climb is physics-driven, the dev tuned the **speed bands so each gut tier "clears"
a specific block of islands.** The authoritative ceilings (3d table) plus the dev's own
inline balance notes in `getFlightSpeed` map to:

| Gut (StomachMax) | Ceiling | Islands it can reach (intended) |
|------------------|---------|---------------------------------|
| Tiny (100)   | 1,450  | 1 → **2** (gates at 3) |
| Small (182)  | 2,598  | up to **4** (gates at 5) |
| Medium (520) | 7,330  | up to **7** (clears 7,8 per dev notes; ceiling caps at 7) |
| Large (1075) | 15,100 | up to **11** (clears 9,10,11) |
| XL (2146)    | 30,094 | up to **13** (clears 11,12) |
| Iron (3218)  | 45,102 | **14** (clears 13,14) — top of the FREE path |
| Infinite (9999) | 140,036 | **14** — premium, flies the whole map trivially |

> The ceiling and the dev's speed comments don't line up perfectly (e.g. Medium's ceiling
> is 7,330 ≈ island 7, while the speed comment says it "clears 7,8"). The **ceiling is the
> hard rule in code**; the speed comments are the designer's playtest intent. For Space
> Realm, the clean model is: **each gut tier ≈ a 2–3 island band**, and the player must
> upgrade the gut to break past its ceiling.

Roughly, the **power needed to clear gap N scales with island Y**: since ceiling is linear
in StomachMax (`Y_reachable ≈ 14·StomachMax`), the StomachMax needed to be *eligible* for
island N is about `StomachMax ≈ (islandY − 50) / 14`. Eligibility-power per island:

| To unlock island | island Y | Min StomachMax for ceiling (`(Y−50)/14`) |
|------------------|----------|-------------------------------------------|
| 2  | 790    | ~53   (Tiny 100 ✓) |
| 3  | 1680   | ~117  (needs Small 182) |
| 4  | 2480   | ~174  (Small 182 ✓, barely) |
| 5  | 3580   | ~252  (needs Medium 520) |
| 6  | 4820   | ~341  (Medium ✓) |
| 7  | 6460   | ~458  (Medium ✓) |
| 8  | 8202   | ~582  (needs Large 1075) |
| 9  | 9732   | ~691  (Large ✓) |
| 10 | 11978  | ~852  (Large ✓) |
| 11 | 14194  | ~1010 (Large 1075 ✓, barely) |
| 12 | 17138  | ~1221 (needs XL 2146) |
| 13 | 20206  | ~1440 (XL ✓) |
| 14 | 24017  | ~1712 (XL ✓; or Iron) |

(That's the *ceiling* requirement. Actual play also needs enough speed/fuel to physically
climb there, which is why the real upgrade cadence lands ~1 gut per 2–3 islands.)

### 3d. Economy / pacing — coin earn rate

Coins are earned **during flight from height**, sent to the server every 0.5s
(`CoreClient.client.lua:2030`):

```
every 0.5s:  tickCoins = height * 0.0044 * serverEventCoinMult     -- (height = max(1, currentY))
             paid = min(tickCoins, dynCap - earnedThisFlight)
             CoinEvent:FireServer( paid * 0.70 )                   -- only 70% of capped coins actually paid
```

- **Per-flight cap (dynamic):** `dynCap = max(80, peakHeight * 0.2)`
  (`FLIGHT_COIN_CAP = 80`, `CAP_PER_HEIGHT = 0.2`). Flying higher raises your own cap, so a
  deep flight pays out far more than a shallow one. The cap never shrinks mid-descent
  (peakHeight only rises).
- **70% payout:** only 70% of the (capped) height coins are actually credited — a global
  earn-rate knob.
- **Server accumulation:** `CoinEvent.OnServerEvent` accumulates fractional coins in
  `playerCoinAccum` and adds `math.floor` to `Coins` + `TotalCoinsEarned` once it crosses a
  whole number (`PlayerStats.server.lua:806`).
- **Ring bonus (separate, uncapped):** collecting a ring gives
  `bonus = floor(15 * ringMultiplier * serverEventRingMult)`, where
  `ringMultiplier = 1 + ringStreak * 0.2` (streak resets on land). Rings are an optional
  earn booster layered on top of height coins.

**Intended difficulty curve:** the designer target (from `CLAUDE.md` "Known Issues") is
~**2 min for island 1→2** and ~**3 min base per subsequent island**, +1–3 min per island
from random events, for a **~65–70 min total** playthrough. The economy paces this by
(a) capping per-flight coins, (b) paying only 70%, and (c) gut costs that jump roughly
1.5–2× per tier (1,600 → 3,000 → 5,200 → 8,000 → 11,000) while food stays cheap, so the
grind is dominated by **saving for the next gut**, not by buying food.

### 3e. In-flight gas mechanics that affect reaching the next island

- **Drain:** gas falls at `3.5/s` (full tank ≈ 28.6s of thrust). When gas hits 0, thrust
  ends and the player falls under gravity — peak is whatever they reached.
- **Gas pockets / "fart bubbles":** **PURE VISUAL.** Touching one pops it (particles +
  sound) but gives **ZERO gas and ZERO power** (`CoreClient.client.lua:2066`). They do
  **not** help you reach the next island. (Don't replicate them as a fuel source.)
- **Mid-Air Recharge (Robux product):** refills gas to 100% mid-flight — a paid second wind.
- **Infinite Gut (Robux):** gas meter is locked full and **never drains** → unlimited
  continuous flight.
- **Server events** can multiply speed, coins, ring value, gas-drain, and height
  (`serverEvent*Mult` globals) — e.g. LOW_GRAVITY, POWER_SURGE — adding the "+1–3 min per
  island" variance. *(Currently `DISABLE_EVENTS`/`DISABLE_PERKS_FOR_BALANCE` gate these
  during balance testing.)*
- **Hazards** (birds, etc.) can reduce `currentPower` mid-flight, shortening a climb.

---

## 4) THE NUMBERS TABLE (everything tied together)

| # | Island | Y | Gap to next | Min StomachMax for ceiling `(Y−50)/14` | Gut tier you'd own here | Gut ceiling `50+max·14` | Food sold (power) | Rise speed band |
|---|--------|-----|------|--------|--------------------------|--------|------------------|-------|
| 1 | Bean Farm        | 150   | 640  | ~7    | **Tiny** (100)   | 1,450  | Beans (8)     | 40  |
| 2 | Broccoli Bluff   | 790   | 890  | ~53   | Tiny (100)        | 1,450  | Broccoli (25) | 40  |
| 3 | Cabbage Cliffs   | 1,680 | 800  | ~117  | **Small** (182)  | 2,598  | Cabbage (45)  | 62  |
| 4 | Turnip Tranquil  | 2,480 | 1,100| ~174  | Small (182)       | 2,598  | Turnips (70)  | 62  |
| 5 | Coconut Cove     | 3,580 | 1,240| ~252  | **Medium** (520) | 7,330  | Coconuts (100)| 84  |
| 6 | Bread Board      | 4,820 | 1,640| ~341  | Medium (520)      | 7,330  | Bread (140)   | 84  |
| 7 | Pasta Peak       | 6,460 | 1,742| ~458  | Medium (520)      | 7,330  | Pasta (185)   | 84  |
| 8 | Popcorn Pinnacle | 8,202 | 1,530| ~582  | **Large** (1075) | 15,100 | Popcorn (240) | 126 |
| 9 | Milk Marsh       | 9,732 | 2,246| ~691  | Large (1075)      | 15,100 | Milk (300)    | 126 |
| 10| Butter Swamp     | 11,978| 2,216| ~852  | Large (1075)      | 15,100 | Butter (370)  | 126 |
| 11| Ice Cream Isle   | 14,194| 2,944| ~1,010| Large (1075)      | 15,100 | IceCream (450)| 126 |
| 12| Burger Bluff     | 17,138| 3,068| ~1,221| **XL** (2146)    | 30,094 | Burger (540)  | 144 |
| 13| Burrito Barrens  | 20,206| 3,811| ~1,440| XL (2146)         | 30,094 | Burrito (640) | 144 |
| 14| Pizza Palms      | 24,017| —    | ~1,712| **XL/Iron** (2146/3218) | 30,094 / 45,102 | Pizza (750) | 144 / 226 |

**Gut purchase cadence (free path):** Tiny → Small (1,600) before island 3 → Medium (3,000)
before island 5 → Large (5,200) before island 8 → XL (8,000) before island 12 → Iron
(11,000) to comfortably finish 13–14. Iron is the top of the free progression; Infinite Gut
(499 Robux, max 9,999) is a premium shortcut that flies the entire map.

---

## Where this differs from `CLAUDE.md` (it's stale — trust the code)

`CLAUDE.md` documents an **older balance pass.** The live code differs:

| Thing | `CLAUDE.md` (stale) | **Live code (authoritative)** |
|-------|---------------------|-------------------------------|
| Island Y values | 50, 600, 1400 … 45000 | **150, 790, 1680 … 24017** |
| Stomach maxPower | 40/96/282/603/1425/2639/99999 | **100/182/520/1075/2146/3218/9999** |
| Gut costs | 200/1500/8000/40000/200000/499 | **1600/3000/5200/8000/11000/499** |
| Food prices | 10/250/450 … 900000 | **5/24/85 … 518** (see table) |
| Food power | 8/25/45 … 750 | **same (8/25/45 … 750)** ✓ |
| Gas drain | 4/sec | **3.5/sec** |
| Flight speeds | 28/35/45/58/75/95/120 | **40/62/84/126/144/226/280** |
| Coin formula | `height*0.008 + (height/500)^2` | **`height*0.0044`, then ×0.70 payout, dynamic cap `max(80, peak*0.2)`** |
| Power reset on gut buy | "resets to 0" | **carries over (only max grows)** |
| `getMaxHeight` | `50 + currentPower*14` | **`50 + StomachMax*14`** (gut tier, not current power) |

---

### Quick port checklist for Space Realm
1. Hardcode the 14 island Y values (col "Y" above) — hand-tuned, not formula-driven.
2. Tank model: `power` (raw, 0..max) ↔ `gas` (power/max·100). Food adds power; flight drains gas at 3.5/s (~28s tank).
3. Gut ceiling = `50 + max·14` — the hard unlock gate. Each gut ≈ a 2–3 island band; upgrading the gut is the real progression lock.
4. Unlock island N when `peakHeight ≥ Yₙ AND Yₙ ≤ ceiling`, strictly in order.
5. Earn coins from height (`h·0.0044`, 70% payout, per-flight cap `max(80, peak·0.2)`); save coins to buy the next gut (costs jump ~1.5–2× per tier).
6. Gas pockets are cosmetic — don't make them refuel.
