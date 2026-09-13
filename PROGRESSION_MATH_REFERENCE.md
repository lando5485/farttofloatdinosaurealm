# PROGRESSION MATH REFERENCE — Fart to Float: Dinosaur Realm

Auto-generated from the live source files. Every number below is the value the game
uses right now. Nothing is rounded unless a `~` is shown.

**Scope note:** this repository contains **ONE realm** — the Dinosaur Realm, 13 islands.
Comments in the source refer to a "first realm" / "Space Realm" that this was ported
from; that realm's code is NOT in this repo, so no numbers for it exist here.

**Source of truth files**

| System | File |
|---|---|
| Island order, names, positions | `src/shared/IslandOrder.luau` |
| Flight physics, tiers, gaps, speeds | `src/shared/FlightTuning.luau` |
| Gut tiers + prices | `src/shared/StomachTiers.luau` |
| Food prices + power | `src/shared/FoodMenu.luau` |
| Purchase validation, coin handler | `src/server/Shop.server.luau` |
| Flight loop, drain, climb coins | `src/client/BottomHUD.client.luau` |
| Gas/coin bubbles | `src/client/Bubbles.client.luau` |
| Bubble gas grant (server) | `src/server/GasBubble.server.luau` |
| Gamepass / dev-product grants | `src/server/PurchaseReceipts.server.luau` |

---

## 1. FOOD

`FoodMenu.LIST` — **row k is the food for CLIMB SLOT k**, not for island model k.
`island` names only which model physically hosts the stand.

| Slot | Food | Price (coins) | Power (fuel) | Coins per power | Host island # | Host island name | Gut tier at this slot |
|---|---|---|---|---|---|---|---|
| 1 | Eggs | 21 | 8 | 2.625 | 1 | Nesting Nook | Hatchling Belly |
| 2 | Chili Peppers | 53 | 25 | 2.120 | 9 | Jungle Junction | Raptor Gut |
| 3 | Lettuce | 79 | 45 | 1.756 | 5 | Misty Mire | Dilo Stomach |
| 4 | Grapes | 101 | 70 | 1.443 | 12 | Sunscorch Sands | Stego Stomach |
| 5 | Bananas | 118 | 100 | 1.180 | 3 | Fossil Frontier | Anky Belly |
| 6 | Popcorn | 136 | 140 | 0.971 | 13 | Glacier Gulch | Trike Gut |
| 7 | Fish | 147 | 185 | 0.795 | 4 | Coastal Crossing | Bronto Belly |
| 8 | Ribs | 156 | 240 | 0.650 | 2 | Fern Frontier | Spino Stomach |
| 9 | Potatoes | 159 | 300 | 0.530 | 10 | Petrified Pass | Rex Gut |
| 10 | Apples | 160 | 370 | 0.432 | 7 | Raptor Ridge | Ptero Belly |
| 11 | Mushrooms | 159 | 450 | 0.353 | 6 | Redwood Ridge | Fossil Gut |
| 12 | Chicken | 156 | 540 | 0.289 | 8 | Inferno Isle | Titan Gut |
| 13 | Steak | 185 | 640 | 0.289 | 11 | Volcanic Vista | Primal Gut |

### Food constants

| Constant | Value | Source |
|---|---|---|
| `POWER_PASS_MULT` | 1.4 | `Shop.server.luau` — the 2x Fart Power pass multiplier |
| `DISABLE_2X` | `false` | `Shop.server.luau` — when true, disables 2x in Studio only |
| `DISABLE_PERKS_FOR_BALANCE` | `false` | `Shop.server.luau` — forces 1x everywhere |
| `FORCE_NO_2X` | `false` | `Shop.server.luau` — marked REMOVE BEFORE LAUNCH |
| `TEST_FULL_DATA` | `false` | `Shop.server.luau` — free tier switching for sampling |

### Eating formula (`BuyFood`, Shop.server.luau)

```
has2x       = HasTwoXForever OR (TwoXHourExpiry > os.time())
powerGain   = has2x and floor(food.power * 1.4) or food.power
effectiveMax= has2x and floor(StomachMax * 1.4) or StomachMax
newPower    = CurrentPower + powerGain

REJECT if newPower > effectiveMax:
    remaining = effectiveMax - CurrentPower
    remaining <= 0  -> 'stomach_full'
    remaining  > 0  -> 'not_enough_room'      (no partial fills — all or nothing)

ON SUCCESS:
    Coins          -= food.price
    CurrentPower    = newPower
    TotalFartPower += food.power + (has2x and food.power or 0)   -- cosmetic counter, doubles
    TotalCoinsEarned unchanged (spending is not earning)
```

**Hidden behaviours**

- Food is **all-or-nothing**. There is no partial serving; if one full serving does not fit, the purchase is refused and no coins are taken.
- The 2x pass raises the **effective tank to `StomachMax * 1.4`**, but the HUD prints raw `StomachMax` as the denominator — so a 2x owner legitimately sees e.g. `130/100`.
- `TotalFartPower` adds `food.power` twice under 2x, but `CurrentPower` only gets `floor(power*1.4)`. These two counters intentionally disagree.

---

## 2. STOMACHS (GUTS)

`StomachTiers.LIST`. `maxPower` is both the tank size **and the ID the purchase is keyed on**.

| # | Name | maxPower (tank) | Cost | unlockSlot | Band speed (studs/s) | Full-tank climb (studs) | Gap it opens (studs) |
|---|---|---|---|---|---|---|---|
| 1 | Hatchling Belly | 110 | 0 | 1 | 26.325 | 1,184.6 | 1,096.9 |
| 2 | Raptor Gut | 150 | 1250 | 2 | 37.375 | 1,317.2 | 1,228.5 |
| 3 | Dilo Stomach | 200 | 1400 | 3 | 42.932 | 1,470.9 | 1,376.0 |
| 4 | Stego Stomach | 270 | 1550 | 4 | 47.743 | 1,646.6 | 1,541.2 |
| 5 | Anky Belly | 365 | 1750 | 5 | 53.560 | 1,845.3 | 1,726.1 |
| 6 | Trike Gut | 495 | 1950 | 6 | 59.995 | 2,069.7 | 1,933.4 |
| 7 | Bronto Belly | 675 | 2200 | 7 | 66.983 | 2,321.6 | 2,165.5 |
| 8 | Spino Stomach | 920 | 2450 | 8 | 75.140 | 2,603.8 | 2,425.5 |
| 9 | Rex Gut | 1260 | 2750 | 9 | 83.915 | 2,920.1 | 2,716.7 |
| 10 | Ptero Belly | 1725 | 3050 | 10 | 94.055 | 3,273.9 | 3,042.7 |
| 11 | Fossil Gut | 2360 | 3450 | 11 | 105.430 | 3,669.6 | 3,407.6 |
| 12 | Titan Gut | 3230 | 3850 | 12 | 118.105 | 4,112.7 | 3,816.5 |
| 13 | Primal Gut | 9999 | 499 R$ | 1 | — | — | — |

**Primal Gut** is Robux-only (499 R$), `maxPower = 9999`, `unlockSlot = 1`, and is
deliberately **not** slot-gated. It also sets the `HasPrimalGut` attribute, which
**disables fuel drain entirely** in the flight loop (see §4).

### Gut purchase rules (`BuyStomachEvent`, Shop.server.luau)

```
tier = StomachTiers.byMaxPower(requestedMaxPower)   -- server reads its OWN price
REJECT if tier == nil
REJECT if not StomachTiers.isUnlocked(tier, HighestSlot)
       isUnlocked = tier.robux or floor(HighestSlot) >= tier.unlockSlot
REJECT if Coins < tier.cost

ON SUCCESS:
    Coins      -= tier.cost
    StomachMax  = tier.maxPower
    CurrentPower = clamp( max(scaled, courtesy), oldCurrentPower, newMax )
        scaled   = floor( (oldCurrentPower / oldMax) * newMax )
        courtesy = FlightTuning.courtesyPower(newMax, gapFromSlot(HighestSlot))
```

There is **no upgrade-scaling formula** — every tier is a hand-set literal. The stated
derivation is `cost ≈ 4.25 × (one flight's surplus at the tier below)`.

---

## 3. ISLANDS

**Spacing knob:** `SPACING_SCALE = 0.325` — declared in BOTH `IslandOrder.luau`
and `FlightTuning.luau` and they must match (a runtime warning fires if they drift).

```
SLOT_POS[i].Y = 150 + (BASE_Y[i] - 150) * SPACING_SCALE       -- slot 1 stays at Y=150
TIERS[i].gap   = BASE_gap[i]   * SPACING_SCALE
TIERS[i].speed = BASE_speed[i] * SPACING_SCALE
```

### 3.1 Climb order and world positions

| Slot | Island # | Name | Type | X | Y (current) | Z | Y at scale 1.0 |
|---|---|---|---|---|---|---|---|
| 1 | 1 | Nesting Nook | Quest | 0 | 150.00 | 0 | 150 |
| 2 | 9 | Jungle Junction | Scenery | 120 | 1,246.88 | 60 | 3,525 |
| 3 | 5 | Misty Mire | Quest | -160 | 2,475.38 | 100 | 7,305 |
| 4 | 12 | Sunscorch Sands | Scenery | 180 | 3,851.43 | -120 | 11,539 |
| 5 | 3 | Fossil Frontier | Quest | -200 | 5,392.57 | 160 | 16,281 |
| 6 | 13 | Glacier Gulch | Scenery | 220 | 7,118.65 | -180 | 21,592 |
| 7 | 4 | Coastal Crossing | Quest | -240 | 9,052.08 | 200 | 27,541 |
| 8 | 2 | Fern Frontier | Quest | 260 | 11,217.55 | -220 | 34,204 |
| 9 | 10 | Petrified Pass | Scenery | -280 | 13,643.02 | 240 | 41,667 |
| 10 | 7 | Raptor Ridge | Quest | 300 | 16,359.70 | -260 | 50,026 |
| 11 | 6 | Redwood Ridge | Quest | -320 | 19,402.35 | 280 | 59,388 |
| 12 | 8 | Inferno Isle | Scenery | 340 | 22,809.98 | -300 | 69,873 |
| 13 | 11 | Volcanic Vista | Quest | -360 | 26,626.45 | 320 | 81,616 |

### 3.2 Consecutive gaps (the crossings)

| Crossing | Δ Y (studs) | True 3-D distance | TIERS.gap | Full-tank climb | climb ÷ gap | Gut that opens it |
|---|---|---|---|---|---|---|
| 1 → 2 | 1,096.88 | 1,105.05 | 1,096.88 | 1,184.62 | 1.0800 | Hatchling Belly |
| 2 → 3 | 1,228.50 | 1,260.64 | 1,228.50 | 1,317.22 | 1.0722 | Raptor Gut |
| 3 → 4 | 1,376.05 | 1,434.40 | 1,376.05 | 1,470.91 | 1.0689 | Dilo Stomach |
| 4 → 5 | 1,541.15 | 1,611.81 | 1,541.15 | 1,646.56 | 1.0684 | Stego Stomach |
| 5 → 6 | 1,726.08 | 1,808.68 | 1,726.08 | 1,845.31 | 1.0691 | Anky Belly |
| 6 → 7 | 1,933.43 | 2,023.40 | 1,933.42 | 2,069.72 | 1.0705 | Trike Gut |
| 7 → 8 | 2,165.48 | 2,261.79 | 2,165.47 | 2,321.58 | 1.0721 | Bronto Belly |
| 8 → 9 | 2,425.47 | 2,527.08 | 2,425.47 | 2,603.79 | 1.0735 | Spino Stomach |
| 9 → 10 | 2,716.68 | 2,822.54 | 2,716.68 | 2,920.15 | 1.0749 | Rex Gut |
| 10 → 11 | 3,042.65 | 3,151.78 | 3,042.65 | 3,273.91 | 1.0760 | Ptero Belly |
| 11 → 12 | 3,407.62 | 3,519.08 | 3,407.62 | 3,669.56 | 1.0769 | Fossil Gut |
| 12 → 13 | 3,816.47 | 3,929.36 | 3,816.47 | 4,112.68 | 1.0776 | Titan Gut |

`climb ÷ gap` must stay **above 1.0** or the crossing is impossible, and the NEXT gap must
exceed this tank's climb or the gut wall disappears. Both hold at every row.

### 3.3 Full pairwise distance matrix (true 3-D, studs)

| slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1** | — | 1,105 | 2,333 | 3,708 | 5,249 | 6,974 | 8,908 | 11,073 | 13,498 | 16,215 | 19,257 | 22,665 | 26,481 |
| **2** | 1,105 | — | 1,261 | 2,611 | 4,159 | 5,878 | 7,815 | 9,976 | 12,404 | 15,117 | 18,162 | 21,567 | 25,385 |
| **3** | 2,333 | 1,261 | — | 1,434 | 2,918 | 4,667 | 6,578 | 8,758 | 11,169 | 13,897 | 16,929 | 20,345 | 24,153 |
| **4** | 3,708 | 2,611 | 1,434 | — | 1,612 | 3,268 | 5,227 | 7,367 | 9,809 | 12,510 | 15,564 | 18,960 | 22,786 |
| **5** | 5,249 | 4,159 | 2,918 | 1,612 | — | 1,809 | 3,660 | 5,855 | 8,251 | 10,987 | 14,011 | 17,432 | 21,235 |
| **6** | 6,974 | 5,878 | 4,667 | 3,268 | 1,809 | — | 2,023 | 4,099 | 6,557 | 9,242 | 12,304 | 15,692 | 19,523 |
| **7** | 8,908 | 7,815 | 6,578 | 5,227 | 3,660 | 2,023 | — | 2,262 | 4,591 | 7,342 | 10,351 | 13,779 | 17,575 |
| **8** | 11,073 | 9,976 | 8,758 | 7,367 | 5,855 | 4,099 | 2,262 | — | 2,527 | 5,142 | 8,221 | 11,593 | 15,431 |
| **9** | 13,498 | 12,404 | 11,169 | 9,809 | 8,251 | 6,557 | 4,591 | 2,527 | — | 2,823 | 5,760 | 9,204 | 12,984 |
| **10** | 16,215 | 15,117 | 13,897 | 12,510 | 10,987 | 9,242 | 7,342 | 5,142 | 2,823 | — | 3,152 | 6,451 | 10,304 |
| **11** | 19,257 | 18,162 | 16,929 | 15,564 | 14,011 | 12,304 | 10,351 | 8,221 | 5,760 | 3,152 | — | 3,519 | 7,224 |
| **12** | 22,665 | 21,567 | 20,345 | 18,960 | 17,432 | 15,692 | 13,779 | 11,593 | 9,204 | 6,451 | 3,519 | — | 3,929 |
| **13** | 26,481 | 25,385 | 24,153 | 22,786 | 21,235 | 19,523 | 17,575 | 15,431 | 12,984 | 10,304 | 7,224 | 3,929 | — |

### 3.4 Vertical-only pairwise distance (Δ Y, studs)

| slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1** | — | 1,097 | 2,325 | 3,701 | 5,243 | 6,969 | 8,902 | 11,068 | 13,493 | 16,210 | 19,252 | 22,660 | 26,476 |
| **2** | 1,097 | — | 1,228 | 2,605 | 4,146 | 5,872 | 7,805 | 9,971 | 12,396 | 15,113 | 18,155 | 21,563 | 25,380 |
| **3** | 2,325 | 1,228 | — | 1,376 | 2,917 | 4,643 | 6,577 | 8,742 | 11,168 | 13,884 | 16,927 | 20,335 | 24,151 |
| **4** | 3,701 | 2,605 | 1,376 | — | 1,541 | 3,267 | 5,201 | 7,366 | 9,792 | 12,508 | 15,551 | 18,959 | 22,775 |
| **5** | 5,243 | 4,146 | 2,917 | 1,541 | — | 1,726 | 3,660 | 5,825 | 8,250 | 10,967 | 14,010 | 17,417 | 21,234 |
| **6** | 6,969 | 5,872 | 4,643 | 3,267 | 1,726 | — | 1,933 | 4,099 | 6,524 | 9,241 | 12,284 | 15,691 | 19,508 |
| **7** | 8,902 | 7,805 | 6,577 | 5,201 | 3,660 | 1,933 | — | 2,165 | 4,591 | 7,308 | 10,350 | 13,758 | 17,574 |
| **8** | 11,068 | 9,971 | 8,742 | 7,366 | 5,825 | 4,099 | 2,165 | — | 2,425 | 5,142 | 8,185 | 11,592 | 15,409 |
| **9** | 13,493 | 12,396 | 11,168 | 9,792 | 8,250 | 6,524 | 4,591 | 2,425 | — | 2,717 | 5,759 | 9,167 | 12,983 |
| **10** | 16,210 | 15,113 | 13,884 | 12,508 | 10,967 | 9,241 | 7,308 | 5,142 | 2,717 | — | 3,043 | 6,450 | 10,267 |
| **11** | 19,252 | 18,155 | 16,927 | 15,551 | 14,010 | 12,284 | 10,350 | 8,185 | 5,759 | 3,043 | — | 3,408 | 7,224 |
| **12** | 22,660 | 21,563 | 20,335 | 18,959 | 17,417 | 15,691 | 13,758 | 11,592 | 9,167 | 6,450 | 3,408 | — | 3,816 |
| **13** | 26,476 | 25,380 | 24,151 | 22,775 | 21,234 | 19,508 | 17,574 | 15,409 | 12,983 | 10,267 | 7,224 | 3,816 | — |

---

## 4. FLIGHT

### 4.1 Constants

| Constant | Value | Source / meaning |
|---|---|---|
| `FLIGHT_SECONDS` | 45 | seconds of thrust on a FULL tank, every tier |
| `TANK_SECONDS` | 45 | = FLIGHT_SECONDS; same for all tiers by design |
| `DRAIN_RATE` | 2.222222 | `100 / TANK_SECONDS` — meter points per second |
| `maxGasMeter` | 100 | the meter is normalised 0..100 |
| `MARGIN` | 1.08 | full tank overshoots its gap by this factor |
| `FLIGHT_HORIZONTAL_SPEED` | 48 | sideways steering speed, studs/s, constant |
| `COIN_TICK` | 0.5 | seconds of thrust between coin payouts |
| `COIN_PER_STUD` | 0.430769 | `0.14 / SPACING_SCALE` |
| `SPACING_SCALE` | 0.325 | world compression factor |

> **Stale comment warning:** `FlightTuning.luau` annotates `DRAIN_RATE` as *"1.25 (was 0.513 at 195s)"*.
> That is left over from an 80-second tank. The real current value is `100/45 = 2.2222`.

### 4.2 How flying works, exactly

Thrust is a **`BodyVelocity`** on the HumanoidRootPart, recreated each frame while flying:

```
bodyVel.MaxForce = Vector3(50000, 1e6, 50000)
bodyVel.Velocity = Vector3( moveDir.X * 48,
                            getFlightSpeed(currentPower) * (_G.flightDistanceMultiplier or 1),
                            moveDir.Z * 48 )
```

Vertical speed is set **directly**, not as an impulse — so climb is exactly `speed × time`
and gravity plays no part while thrusting. This linearity is why halving gaps and speeds
together leaves pacing unchanged.

### 4.3 Fuel drain

```
PER FRAME, only while (isFlying AND gasMeter > 0):
    if NOT player:GetAttribute('HasPrimalGut') then
        gasMeter = max(0, gasMeter - DRAIN_RATE * dt)
    end
    currentPower = (gasMeter / 100) * StomachMax
    every 1.0s: BurnFuelEvent:FireServer(currentPower)   -- server adopts DOWNWARD only
    if gasMeter <= 0 then currentPower = 0; stopFlying() end
```

- **`HasPrimalGut` skips the drain entirely** — infinite flight, not merely a big tank.
- Drain is **client-authoritative**; the server clamps reports so fuel can only fall.
- Because the meter is normalised, **a full tank always lasts 45 s at every tier**. A bigger gut does not fly LONGER, it flies FASTER.

### 4.4 Speed bands

`getFlightSpeed(power)` returns the band for the **current draining power**, so speed
steps DOWN as the tank empties.

```
for tier in TIERS:  if power <= tier.maxPower then return tier.speed
return TIERS[last].speed
```

| Power band | Speed (studs/s, current) | Speed at scale 1.0 |
|---|---|---|
| 0 < p ≤ 110 | 26.3250 | 81.0 |
| 110 < p ≤ 150 | 37.3750 | 115.0 |
| 150 < p ≤ 200 | 42.9325 | 132.1 |
| 200 < p ≤ 270 | 47.7425 | 146.9 |
| 270 < p ≤ 365 | 53.5600 | 164.8 |
| 365 < p ≤ 495 | 59.9950 | 184.6 |
| 495 < p ≤ 675 | 66.9825 | 206.1 |
| 675 < p ≤ 920 | 75.1400 | 231.2 |
| 920 < p ≤ 1,260 | 83.9150 | 258.2 |
| 1,260 < p ≤ 1,725 | 94.0550 | 289.4 |
| 1,725 < p ≤ 2,360 | 105.4300 | 324.4 |
| 2,360 < p ≤ 3,230 | 118.1050 | 363.4 |
| 3,230 < p ≤ ∞ | 136.5000 | 420.0 |

### 4.5 Climb integral

```
fullTankClimb(max) = (FLIGHT_SECONDS / max) * SUM over bands[ speed_j * (min(M_j,max) - M_(j-1)) ]

powerForClimb(max, dist):          -- exact inverse, no search
    need = dist * max / FLIGHT_SECONDS
    walk bands accumulating span = (top-prev)*speed until sum+span >= need
    return min(max, prev + (need - sum) / speed)

courtesyPower(max, gap) = floor( min(max, powerForClimb(max, gap) * 1.10) + 0.5 )
```

### 4.6 Bubbles (pickups during flight)

Two bubble types, **six of each per gap**, placed at fractions `t` along the gap and
spread sideways off the centreline. Entirely client-spawned.

| Property | GAS bubble | COIN bubble |
|---|---|---|
| Purpose | refuels | pays coins |
| `T_POSITIONS` (fraction up the gap) | 0.10, 0.26, 0.42, 0.58, 0.74, 0.90 | 0.18, 0.34, 0.50, 0.66, 0.82, 0.94 |
| `SPREAD_MIN` .. `SPREAD_MAX` (studs off centreline) | 60 .. 160 | 85 .. 200 |
| Ball diameter | 30 | 36 |
| `COLLECT_RADIUS` | 26 | 22 |
| `RESPAWN` | (gas value) | 30 s |
| Angular placement | `2π / 6` = 60° apart | `2π / 6` = 60° apart, interleaved with gas |

**Gas bubble grant (server-authoritative, `GasBubble.server.luau`)**

```
grant = max(1, ceil(StomachMax * 0.02))          -- 2% of tank, never flat
CurrentPower = min(StomachMax, CurrentPower + grant)

RATE LIMIT (a budget, not a proof — bubbles do not exist server-side):
    MIN_INTERVAL   = 0.75 s between accepted grants
    WINDOW_SECONDS = 60
    WINDOW_MAX     = 12 accepted grants per window
```

**Coin bubble value (client-computed)**

```
baseBonus() = gapFromSlot(HighestSlot) * (COIN_PER_STUD / SPACING_SCALE) * BUBBLE_SHARE
            = gap * 0.14/0.325 * 0.032        (falls back to flat 15 if FlightTuning missing)

multiplier  = 1 + streak * 0.2                -- streak = bubbles popped without landing
bonus       = max(1, floor(baseBonus * multiplier * eventMult))
            eventMult = _G.serverEventCoinMult or _G.serverEventRingMult or 1
streak resets to 0 on landing (RESET_ON_LANDING = true)
```

| Slot | Gap | 1 bubble (x1.0) | x1.2 (streak 1) | x2.0 (streak 5) | all 6 at x1.0 |
|---|---|---|---|---|---|
| 1 | 1,097 | 15.12 | 18.14 | 30.24 | 91 |
| 2 | 1,228 | 16.93 | 20.32 | 33.87 | 102 |
| 3 | 1,376 | 18.97 | 22.76 | 37.94 | 114 |
| 4 | 1,541 | 21.24 | 25.49 | 42.49 | 127 |
| 5 | 1,726 | 23.79 | 28.55 | 47.59 | 143 |
| 6 | 1,933 | 26.65 | 31.98 | 53.30 | 160 |
| 7 | 2,165 | 29.85 | 35.82 | 59.70 | 179 |
| 8 | 2,425 | 33.43 | 40.12 | 66.87 | 201 |
| 9 | 2,717 | 37.45 | 44.94 | 74.90 | 225 |
| 10 | 3,043 | 41.94 | 50.33 | 83.88 | 252 |
| 11 | 3,408 | 46.97 | 56.37 | 93.95 | 282 |
| 12 | 3,816 | 52.61 | 63.13 | 105.22 | 316 |

---

## 5. ECONOMY

### 5.1 The only income sources

```
1. CLIMB COINS  (the dominant source)
   every COIN_TICK (0.5 s) of thrust:
       gained = currentY - lastCoinY          -- studs climbed since last tick
       if gained > 0:
           pay = gained * COIN_PER_STUD * (_G.serverEventCoinMult or 1)
           CoinEvent:FireServer(pay)
   Paid ONLY while thrusting. Falling pays 0. Descending ticks pay 0 (gained <= 0).
   You are billed the DELTA, charged once each — not absolute altitude.

2. COIN BUBBLES — see 4.6

3. Anti-strand top-up (Shop.server) — grants the SHORTFALL only, when a flight ends dry
```

**Server-side coin accumulator** (`CoinEvent.OnServerEvent`):

```
reject if amount <= 0 or amount ~= amount (NaN)
accum[player] += amount
toAdd = floor(accum[player])
accum[player] -= toAdd;  Coins += toAdd;  TotalCoinsEarned += toAdd
```
Fractional payouts are accumulated, never floored away.

### 5.2 Earnings per full-tank flight, per slot

| Slot | Gut | Climb (studs) | Coins earned | Food | Servings to fill | Refill cost | Net surplus | R = earn/cost |
|---|---|---|---|---|---|---|---|---|
| 1 | Hatchling Belly | 1,185 | 510 | Eggs | 13.75 | 289 | 222 | 1.767 |
| 2 | Raptor Gut | 1,317 | 567 | Chili Peppers | 6.00 | 318 | 249 | 1.784 |
| 3 | Dilo Stomach | 1,471 | 634 | Lettuce | 4.44 | 351 | 283 | 1.805 |
| 4 | Stego Stomach | 1,647 | 709 | Grapes | 3.86 | 390 | 320 | 1.821 |
| 5 | Anky Belly | 1,845 | 795 | Bananas | 3.65 | 431 | 364 | 1.846 |
| 6 | Trike Gut | 2,070 | 892 | Popcorn | 3.54 | 481 | 411 | 1.854 |
| 7 | Bronto Belly | 2,322 | 1,000 | Fish | 3.65 | 536 | 464 | 1.865 |
| 8 | Spino Stomach | 2,604 | 1,122 | Ribs | 3.83 | 598 | 524 | 1.876 |
| 9 | Rex Gut | 2,920 | 1,258 | Potatoes | 4.20 | 668 | 590 | 1.884 |
| 10 | Ptero Belly | 3,274 | 1,410 | Apples | 4.66 | 746 | 664 | 1.891 |
| 11 | Fossil Gut | 3,670 | 1,581 | Mushrooms | 5.24 | 834 | 747 | 1.896 |
| 12 | Titan Gut | 4,113 | 1,772 | Chicken | 5.98 | 933 | 839 | 1.899 |

**R is the single most important balance number.** It must stay **> 1.0** at every row or
a flight costs more than it earns and the player spirals down. Target is a flat ~1.91;
actual range is **1.767 .. 1.899**.

### 5.3 Cumulative coins to reach each island

Assumes: buy the gut for each crossing, fly full tanks, no bubbles.

| Crossing | Earn/flight | Refill cost | Net/flight | Next gut cost | Flights to afford | Cumulative earned | Cumulative spent |
|---|---|---|---|---|---|---|---|
| 1 → 2 | 510 | 289 | 222 | 1250 | 5.64 | 2,879 | 2,879 |
| 2 → 3 | 567 | 318 | 249 | 1400 | 5.61 | 6,064 | 6,064 |
| 3 → 4 | 634 | 351 | 283 | 1550 | 5.49 | 9,540 | 9,540 |
| 4 → 5 | 709 | 390 | 320 | 1750 | 5.47 | 13,423 | 13,423 |
| 5 → 6 | 795 | 431 | 364 | 1950 | 5.35 | 17,679 | 17,679 |
| 6 → 7 | 892 | 481 | 411 | 2200 | 5.36 | 22,455 | 22,455 |
| 7 → 8 | 1,000 | 536 | 464 | 2450 | 5.28 | 27,738 | 27,738 |
| 8 → 9 | 1,122 | 598 | 524 | 2750 | 5.25 | 33,629 | 33,629 |
| 9 → 10 | 1,258 | 668 | 590 | 3050 | 5.17 | 40,130 | 40,130 |
| 10 → 11 | 1,410 | 746 | 664 | 3450 | 5.19 | 47,454 | 47,454 |
| 11 → 12 | 1,581 | 834 | 747 | 3850 | 5.15 | 55,603 | 55,603 |
| 12 → 13 | 1,772 | 933 | 839 | — | 1.00 | 57,374 | 56,536 |

### 5.4 Multipliers affecting earnings

| Multiplier | Value | Applies to | Source |
|---|---|---|---|
| `_G.serverEventCoinMult` | 1 (default) | climb coins AND bubble bonus | set by a server event; no setter found in repo |
| `_G.serverEventRingMult` | 1 (fallback) | bubble bonus only | legacy alias |
| Coin streak | `1 + streak*0.2` | bubble bonus only | resets on landing |
| `_G.flightDistanceMultiplier` | 1 (default); 0.9 during Monsoon Rain | vertical SPEED, so indirectly climb coins | `MonsoonRain.client.luau` |
| `POWER_PASS_MULT` | 1.4 | food power + effective tank; NOT coins | 2x Fart Power pass |

---

## 6. PROGRESSION

### 6.1 Intended order

The loop for every crossing k → k+1:

```
1. Stand on slot k. Buy food (row k of FoodMenu) until tank is full.
2. Fly. Earn climb coins. Land — early attempts fall short.
3. Repeat, banking surplus, until you can afford gut tier k+1.
4. Buy gut k+1 (requires HighestSlot >= its unlockSlot).
5. That gut's full-tank climb now exceeds gap k, so the next flight lands you on slot k+1.
```

The **gut is the wall**. Prices are set so a gut costs ≈4.25 flights of surplus, which is
what produces "3–5 attempts per island". Food prices cannot set the try count, because
R > 1 means you always eventually afford the next tank.

### 6.2 Expected gut owned on arrival at each island

| Slot | Island | Gut you should own | Tank | Gut cost | Unlocks at | Food sold here | Food price | Food power |
|---|---|---|---|---|---|---|---|---|
| 1 | Nesting Nook | Hatchling Belly | 110 | free | slot 1 | Eggs | 21 | 8 |
| 2 | Jungle Junction | Raptor Gut | 150 | 1250 | slot 2 | Chili Peppers | 53 | 25 |
| 3 | Misty Mire | Dilo Stomach | 200 | 1400 | slot 3 | Lettuce | 79 | 45 |
| 4 | Sunscorch Sands | Stego Stomach | 270 | 1550 | slot 4 | Grapes | 101 | 70 |
| 5 | Fossil Frontier | Anky Belly | 365 | 1750 | slot 5 | Bananas | 118 | 100 |
| 6 | Glacier Gulch | Trike Gut | 495 | 1950 | slot 6 | Popcorn | 136 | 140 |
| 7 | Coastal Crossing | Bronto Belly | 675 | 2200 | slot 7 | Fish | 147 | 185 |
| 8 | Fern Frontier | Spino Stomach | 920 | 2450 | slot 8 | Ribs | 156 | 240 |
| 9 | Petrified Pass | Rex Gut | 1260 | 2750 | slot 9 | Potatoes | 159 | 300 |
| 10 | Raptor Ridge | Ptero Belly | 1725 | 3050 | slot 10 | Apples | 160 | 370 |
| 11 | Redwood Ridge | Fossil Gut | 2360 | 3450 | slot 11 | Mushrooms | 159 | 450 |
| 12 | Inferno Isle | Titan Gut | 3230 | 3850 | slot 12 | Chicken | 156 | 540 |
| 13 | Volcanic Vista | Primal Gut | 9999 | 499 | slot 1 | Steak | 185 | 640 |

### 6.3 Balancing assumptions baked into the numbers

```
* One attempt = 45 s of thrust (FLIGHT_SECONDS), NOT one 3-minute flight.
* An island should take 3-5 attempts, landing near 3.0 minutes total.
* Gut price = 4.25 x one flight's surplus at the tier below.
* Each gap is 12% larger than the last; MARGIN is 8%. Gap growth MUST beat MARGIN
  or a gut clears the next gap too and stops being a wall.
* R (earn/cost) held flat at ~1.91 across all 12 crossings.
* Every tank carries +10 over the original 100/140/190/... sizes. Prices and speeds
  were NOT re-solved for it; it costs ~0.8% of margin.
* One gut per crossing: 12 tiers, 12 gaps. A paired scheme (6 guts) left half the
  islands with no wall and produced 3,1,3,1,6,1 attempt counts.
```

---

## 7. GAMEPLAY TIMING

Derived, not measured. A flight is `45 × (power/max)` seconds of thrust.

| Crossing | Flights saving | Total attempts | Time thrusting | Servings/refill | Time buying (~1 s/click) | Island total | Cumulative |
|---|---|---|---|---|---|---|---|
| 1 → 2 | 5.64 | 6.64 | 299s | 13.8 | 91s | 6.5 min | 6.5 min |
| 2 → 3 | 5.61 | 6.61 | 298s | 6.0 | 40s | 5.6 min | 12.1 min |
| 3 → 4 | 5.49 | 6.49 | 292s | 4.4 | 29s | 5.3 min | 17.5 min |
| 4 → 5 | 5.47 | 6.47 | 291s | 3.9 | 25s | 5.3 min | 22.7 min |
| 5 → 6 | 5.35 | 6.35 | 286s | 3.6 | 23s | 5.2 min | 27.9 min |
| 6 → 7 | 5.36 | 6.36 | 286s | 3.5 | 22s | 5.1 min | 33.0 min |
| 7 → 8 | 5.28 | 6.28 | 283s | 3.6 | 23s | 5.1 min | 38.1 min |
| 8 → 9 | 5.25 | 6.25 | 281s | 3.8 | 24s | 5.1 min | 43.2 min |
| 9 → 10 | 5.17 | 6.17 | 278s | 4.2 | 26s | 5.1 min | 48.3 min |
| 10 → 11 | 5.19 | 6.19 | 279s | 4.7 | 29s | 5.1 min | 53.4 min |
| 11 → 12 | 5.15 | 6.15 | 277s | 5.2 | 32s | 5.2 min | 58.6 min |
| 12 → 13 | 0.00 | 1.00 | 45s | 6.0 | 6s | 0.8 min | 59.4 min |

**Caveats on these figures**

- Assumes every flight is a **full tank flown to empty**. Real early attempts launch part-full and are shorter.
- Ignores fall time, walking to the stand, and menu navigation.
- Ignores coin/gas bubbles, which shorten the saving phase.
- "Time buying" assumes ~1 second per purchase click and one click per serving; the shop has no bulk-buy.
- Total tower ≈ **59 minutes** of thrust+buying under these assumptions.

---

## 8. EVERY FORMULA

```
# ---- WORLD ----
SLOT_POS[i].Y      = 150 + (BASE_Y[i] - 150) * SPACING_SCALE
TIERS[i].gap       = BASE_gap[i] * SPACING_SCALE
TIERS[i].speed     = BASE_speed[i] * SPACING_SCALE
gapFromSlot(s)     = SLOT_POS[s+1].Y - SLOT_POS[s].Y

# ---- FUEL ----
DRAIN_RATE         = 100 / TANK_SECONDS
gasMeter          -= DRAIN_RATE * dt          (skipped entirely if HasPrimalGut)
currentPower       = (gasMeter / 100) * StomachMax
tankSecondsFor(m)  = TANK_SECONDS             (constant for all tiers)
flightDuration     = FLIGHT_SECONDS * (power / StomachMax)

# ---- SPEED ----
getFlightSpeed(p)  = first TIERS[j].speed where p <= TIERS[j].maxPower
verticalVelocity   = getFlightSpeed(currentPower) * (flightDistanceMultiplier or 1)
horizontalVelocity = moveDirection * 48

# ---- DISTANCE ----
fullTankClimb(max) = (FLIGHT_SECONDS/max) * SUM_j[ speed_j * (min(M_j,max) - M_(j-1)) ]
powerForClimb(max,d): need = d*max/FLIGHT_SECONDS; walk bands until sum >= need
courtesyPower(m,g) = floor(min(m, powerForClimb(m,g) * 1.10) + 0.5)

# ---- CAPACITY ----
StomachMax         = tier.maxPower                    (literal, no formula)
effectiveMax       = has2x and floor(StomachMax*1.4) or StomachMax

# ---- COINS ----
COIN_PER_STUD      = 0.14 / SPACING_SCALE
climbPay           = (Y - lastCoinY) * COIN_PER_STUD * (serverEventCoinMult or 1)
                     paid every 0.5 s of thrust, only when the delta is positive
bubbleBase         = gapFromSlot(HighestSlot) * COIN_PER_STUD * 0.032
bubbleMultiplier   = 1 + streak * 0.2
bubbleBonus        = max(1, floor(bubbleBase * bubbleMultiplier * eventMult))
gasGrant           = max(1, ceil(StomachMax * 0.02))

# ---- PRICES ----
foodPrice          = gap * MARGIN * COIN_PER_STUD / (R * (tierMaxPower / foodPower))
                     solved for flat R = 1.91
gutCost            = 4.25 * (one flight's surplus at the tier below)   [design rule]
R                  = fullTankClimb(max)*COIN_PER_STUD / (price * (max/foodPower))

# ---- PURCHASE GATES ----
isUnlocked(tier,s) = tier.robux or floor(s) >= tier.unlockSlot
foodFits           = (CurrentPower + powerGain) <= effectiveMax    (all-or-nothing)
```

---

## 9. COMPLETE CONFIGURATION DUMP

| Constant | Value | File |
|---|---|---|
| `SPACING_SCALE` | 0.325 | IslandOrder.luau AND FlightTuning.luau (must match) |
| `FLIGHT_SECONDS` | 45 | FlightTuning.luau |
| `TANK_SECONDS` | 45 | FlightTuning.luau |
| `DRAIN_RATE` | 2.222222 | FlightTuning.luau (derived) |
| `MARGIN` | 1.08 | FlightTuning.luau |
| `maxGasMeter` | 100 | BottomHUD.client.luau |
| `FLIGHT_HORIZONTAL_SPEED` | 48 | BottomHUD.client.luau |
| `COIN_TICK` | 0.5 | BottomHUD.client.luau |
| `COIN_PER_STUD` (base) | 0.14 | BottomHUD + Bubbles |
| `COIN_PER_STUD` (effective) | 0.430769 | derived |
| `POWER_PASS_MULT` | 1.4 | Shop.server.luau |
| `GRANT_PERCENT` | 0.02 | GasBubble.server.luau |
| `MIN_INTERVAL` | 0.75 | GasBubble.server.luau |
| `WINDOW_SECONDS` | 60 | GasBubble.server.luau |
| `WINDOW_MAX` | 12 | GasBubble.server.luau |
| `BUBBLE_SHARE` | 0.032 | Bubbles.client.luau |
| `STREAK_STEP` | 0.2 | Bubbles.client.luau |
| `BASE_BONUS` (fallback) | 15 | Bubbles.client.luau |
| `RESET_ON_LANDING` | true | Bubbles.client.luau |
| `DISABLE_2X` | false | Shop.server.luau |
| `DISABLE_PERKS_FOR_BALANCE` | false | Shop.server.luau |
| `FORCE_NO_2X` | false | Shop.server.luau |
| `TEST_FULL_DATA` | false | Shop.server.luau |
| `MAX_ISLAND` | 13 | PurchaseReceipts.server.luau |
| Starting `StomachMax` | 100 | Shop.server.luau `num("StomachMax", 100)` |

### Monetisation IDs

| Kind | Name | ID | Effect |
|---|---|---|---|
| Dev product | 2x Power (1 Hour) | 3600302990 | sets `TwoXHourExpiry = os.time()+3600` |
| Dev product | Mid-Air Recharge | 3600303163 | `CurrentPower = StomachMax` |
| Dev product | Skip Island | 3600303265 | `HighestIsland += 1` + teleport |
| Dev product | Meteorite Explosion | 3606893853 | server-wide meteor event |
| Gamepass | 2x Fart Power Forever | 1862015450 | `HasTwoXForever` → 1.4x food power AND 1.4x tank |
| Gamepass | Glitter Fart Trail | 1859714979 | `HasGlitterTrail` (cosmetic) |
| Gamepass | Primal Gut | 1860686821 | `HasPrimalGut` → `StomachMax=9999` **and disables drain** |

Both `HasTwoXForever` and `HasPrimalGut` grants are **Studio-gated** (the place owner
implicitly owns their own passes). Dev toggles: `/infinitegut`, `/2x`.

### Raw tables

```lua
IslandOrder.SLOT_TO_ISLAND = {1, 9, 5, 12, 3, 13, 4, 2, 10, 7, 6, 8, 11}
IslandOrder.QUEST          = {1,2,3,4,5,6,7,11}   -- rest are scenery

-- BASE (pre-scale) island Y: 150, 3525, 7305, 11539, 16281, 21592, 27541,
--                            34204, 41667, 50026, 59388, 69873, 81616
-- BASE (pre-scale) gaps:     3375, 3780, 4234, 4742, 5311, 5949,
--                            6663, 7463, 8359, 9362, 10485, 11743
-- BASE (pre-scale) speeds:   81.0, 115.0, 132.1, 146.9, 164.8, 184.6,
--                            206.1, 231.2, 258.2, 289.4, 324.4, 363.4, 420.0
```

### Known inconsistencies

1. `DRAIN_RATE` comment says 1.25 / 80 s; actual is 2.2222 / 45 s.
2. HUD prints raw `StomachMax` as the denominator; with the 2x pass the real cap is `×1.4`, so it displays e.g. `130/100`.
3. `FORCE_NO_2X` is marked *REMOVE BEFORE LAUNCH* and is still present.
4. `ISLAND_SPACING.md` is stale — it lists food-realm island names and pre-retier positions. Ignore it.
5. `_G.serverEventCoinMult` is read in two places but no setter exists in this repo.
6. Gut `cost` values are literals; the "4.25 × surplus" rule is documentation, not code.