# Dino Realm — Island Spacing & Full Economy (exact copy)

Source of truth, pulled directly from the live code on 2026-08-06:
- `src/shared/IslandOrder.luau` — slot order + exact positions
- `src/shared/FlightTuning.luau` — flight seconds, drain, band speeds, margins
- `src/shared/StomachTiers.luau` — gut tiers (prices, sizes, unlock slots)
- `src/shared/FoodMenu.luau` — food prices/power per climb slot
- `src/client/BottomHUD.client.luau` — coins-per-stud flight earning loop
- `src/server/Shop.server.luau` — starting coins, coin accumulation, anti-strand

NOTE: `ISLAND_SPACING.md`, `PROGRESSION_ECONOMY.md` and `GAME_BALANCE_REFERENCE.md`
in this repo describe the FIRST realm (Bean Farm → Pizza Palms). This document is
the DINO REALM's own system, which is different in almost every number.

---

## 1. Island spacing — the 13-slot tower

13 islands, one vertical zig-zag tower. **Slot** = climb position (1 = bottom,
13 = summit). Slots map to island MODELS via `IslandOrder.SLOT_TO_ISLAND =
{1, 9, 5, 12, 3, 13, 4, 2, 10, 7, 6, 8, 11}`.

### Exact positions (`IslandOrder.SLOT_POS`)

| Slot | Island model | Name             | Type  | X    | Y      | Z    | Gap to next (Y) |
|------|--------------|------------------|-------|------|--------|------|-----------------|
| 1    | island1      | Nesting Nook     | QUEST | 0    | 150    | 0    | 3,375           |
| 2    | island9      | Jungle Junction  | blank | 120  | 3,525  | 60   | 3,780           |
| 3    | island5      | Misty Mire       | QUEST | -160 | 7,305  | 100  | 4,234           |
| 4    | island12     | Sunscorch Sands  | blank | 180  | 11,539 | -120 | 4,742           |
| 5    | island3      | Fossil Frontier  | QUEST | -200 | 16,281 | 160  | 5,311           |
| 6    | island13     | Glacier Gulch    | blank | 220  | 21,592 | -180 | 5,949           |
| 7    | island4      | Coastal Crossing | QUEST | -240 | 27,541 | 200  | 6,663           |
| 8    | island2      | Fern Frontier    | QUEST | 260  | 34,204 | -220 | 7,463           |
| 9    | island10     | Petrified Pass   | blank | -280 | 41,667 | 240  | 8,359           |
| 10   | island7      | Raptor Ridge     | QUEST | 300  | 50,026 | -260 | 9,362           |
| 11   | island6      | Redwood Ridge    | QUEST | -320 | 59,388 | 280  | 10,485          |
| 12   | island8      | Inferno Isle     | blank | 340  | 69,873 | -300 | 11,743          |
| 13   | island11     | Volcanic Vista   | QUEST | -360 | 81,616 | 320  | — (summit)      |

Quest islands (by model number): 1, 2, 3, 4, 5, 6, 7, 11. Blank scenery: 8, 9, 10, 12, 13.
Volcanic Vista (island11) is pinned to the summit — the volcano/geyser finale that grants the T-Rex.

### The spacing rules (why these numbers)

- **X and Z zig-zag**: alternate sign every slot and grow by 20 studs of magnitude
  per step (X: 0, 120, -160, 180, -200… Z: 0, 60, 100, -120, 160…).
- **Y gaps grow 12% per crossing**: 3,375 → 11,743, twelve gaps for twelve crossings.
  **12% is load-bearing**: a full tank climbs its own gap × MARGIN (1.08), so a gut is
  locked out of the NEXT gap only if gaps grow by MORE than 8%. 12% clears that at
  every step. (An earlier pass at ~8% growth made two guts silently unnecessary.)
- **One gap per gut tier, 1:1.** Twelve gut tiers, twelve gaps. A gut is the wall
  that forces saving; with fewer guts than crossings, some islands are free by
  construction (a playtest with 6 guts / 12 crossings ran 3, 1, 3, 1, 6, 1 attempts).
- **Each gap is what a full tank climbs ÷ 1.08** — a clean run only just makes it.
  No gut reaches the gap ABOVE its own (3,645 < 3,780; 4,082 < 4,234; … 11,324 < 11,743),
  which is what makes the gut shop mandatory rather than optional.
- Summit at 81,616 keeps well clear of ~100k+ where float precision jitters parts.

### Copy-paste (Luau)

```lua
local SLOT_TO_ISLAND = { 1, 9, 5, 12, 3, 13, 4, 2, 10, 7, 6, 8, 11 }
local SLOT_POS = {
	Vector3.new(   0,   150,    0),
	Vector3.new( 120,  3525,   60),
	Vector3.new(-160,  7305,  100),
	Vector3.new( 180, 11539, -120),
	Vector3.new(-200, 16281,  160),
	Vector3.new( 220, 21592, -180),
	Vector3.new(-240, 27541,  200),
	Vector3.new( 260, 34204, -220),
	Vector3.new(-280, 41667,  240),
	Vector3.new( 300, 50026, -260),
	Vector3.new(-320, 59388,  280),
	Vector3.new( 340, 69873, -300),
	Vector3.new(-360, 81616,  320),
}
```

At startup `IslandLayout.server.luau` PivotTo()s each island model to its slot
position (rotation preserved), then sets `_G.islandsPositioned = true` so
island-dependent scripts (NPCs, eggs, spawns) wait before placing things.

---

## 2. Starting state (new player)

From `Shop.server.luau` `setupStats`:

```lua
num("Coins", 120)            -- starting coins
num("CurrentPower", 0)       -- current fart fuel in the tank
num("StomachMax", 100)       -- tank size (Hatchling Belly tier)
num("TotalFartPower", 0)     -- cosmetic lifetime counter
num("TotalCoinsEarned", 0)
num("Island", 1)
```

**Coins = 120** (not the first realm's 25 — at 25 you couldn't afford enough food
for a profitable first flight and the run dead-locked before island 2).

---

## 3. Coins earned while flying — EXACT numbers

**This is the big difference from the first realm.** The first realm pays
`absoluteY × 0.0044` every 0.5s with a per-flight cap. The Dino Realm pays
**per stud CLIMBED, charged once each, no cap needed**:

```lua
-- BottomHUD.client.luau
local COIN_TICK     = 0.5    -- seconds of thrust between payouts
local COIN_PER_STUD = 0.14   -- [BALANCE] coins per stud climbed

-- inside the flight loop (only runs while thrusting with gas > 0):
coinTimer = coinTimer + dt
if coinTimer >= COIN_TICK then
	coinTimer = 0
	local gained = y - lastCoinY          -- studs climbed since the last tick
	lastCoinY = y
	if gained > 0 and CoinEvent then
		local pay = gained * COIN_PER_STUD * (_G.serverEventCoinMult or 1)
		flightCoinsEarned = flightCoinsEarned + pay
		CoinEvent:FireServer(pay)
	end
end
```

Rules:
- **0.14 coins per stud climbed**, paid every 0.5s of thrust.
- Paid only WHILE THRUSTING — release the button or run dry and earning stops.
  The fall pays 0.
- Billed on the DELTA from launch altitude (`lastCoinY` starts at the launch Y),
  so you're paid for climb you actually bought, not for how high the island under
  you is. No cap, no 70% payout knob — those existed to patch the absolute-Y model.
- On landing/flight end there is one final flush of any remaining delta.
- `_G.serverEventCoinMult` is an event multiplier (1 normally).

**Earning intuition:** a full-tank flight climbs `gap × 1.08`, so it earns
`gap × 1.08 × 0.14` coins — e.g. slot 1→2 (gap 3,375) ≈ **510 coins per full flight**,
slot 12→13 (gap 11,743) ≈ **1,775 coins**.

### Server accumulation (`Shop.server.luau` — CoinEvent)

The client sends fractional amounts; the server accumulates and only moves whole
coins into stats (otherwise sub-1.0 payouts would floor to 0):

```lua
local playerCoinAccum = {}
CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0
	if amt <= 0 or amt ~= amt then return end       -- reject negatives and NaN
	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
end)
```

---

## 4. Flight model (what turns fuel into height)

From `FlightTuning.luau` — same SHAPE as the Space Realm / first realm model:

```lua
FLIGHT_SECONDS = 45              -- a full tank = 45 s of thrust, for EVERY gut
MARGIN         = 1.08            -- full tank climbs gap × 1.08 (a clean run only just makes it)
TANK_SECONDS   = FLIGHT_SECONDS  -- same for every tier (distance is bought with SPEED, not time)
DRAIN_RATE     = 100 / TANK_SECONDS  -- ≈ 2.222 gas/sec on the 0–100 normalised meter

-- per frame:
gasMeter     = gasMeter - DRAIN_RATE * dt
currentPower = (gasMeter / 100) * stomachMax
riseSpeed    = getFlightSpeed(currentPower)   -- band lookup on the DRAINING power
BodyVelocity.Y = riseSpeed
-- horizontal: move.X/Z × 48 (FLIGHT_HORIZONTAL_SPEED)
```

The band is read from the DRAINING power, so a flight starts in the top band its
gut reaches and steps DOWN through every band beneath it as the tank empties —
the speed taper is the mechanic.

### Band speeds (`FlightTuning.TIERS`) — solved, not guessed

| Tier | Gut name        | maxPower | Gap it opens (slot k→k+1) | Rise speed |
|------|-----------------|----------|---------------------------|------------|
| 1    | Hatchling Belly | 110      | 3,375 (1→2)               | 81.0       |
| 2    | Raptor Gut      | 150      | 3,780 (2→3)               | 115.0      |
| 3    | Dilo Stomach    | 200      | 4,234 (3→4)               | 132.1      |
| 4    | Stego Stomach   | 270      | 4,742 (4→5)               | 146.9      |
| 5    | Anky Belly      | 365      | 5,311 (5→6)               | 164.8      |
| 6    | Trike Gut       | 495      | 5,949 (6→7)               | 184.6      |
| 7    | Bronto Belly    | 675      | 6,663 (7→8)               | 206.1      |
| 8    | Spino Stomach   | 920      | 7,463 (8→9)               | 231.2      |
| 9    | Rex Gut         | 1,260    | 8,359 (9→10)              | 258.2      |
| 10   | Ptero Belly     | 1,725    | 9,362 (10→11)             | 289.4      |
| 11   | Fossil Gut      | 2,360    | 10,485 (11→12)            | 324.4      |
| 12   | Titan Gut       | 3,230    | 11,743 (12→13)            | 363.4      |
| 13   | Primal Gut      | ∞        | 13,000                    | 420.0      |

The speeds are the unique solution to "every full tank climbs its own gap × 1.08"
given the taper integral: gut of size M spends `45 × (M_j − M_j-1) / M` seconds in
band j, total climb = `(45 / M) × Σ v_j × (M_j − M_j-1)`. **Hand-editing one row
silently breaks every tier above it** — re-solve instead. Gaps, band speeds, food
prices and gut costs are one interlocked set.

(The tank sizes carry a +10 over the solved 100/140/190/260/355/485/665/910/1250/
1715/2350/3220 — capacity only; effective margin lands at ~1.072 instead of 1.080
and every crossing still clears.)

---

## 5. Gut (stomach) tiers — exact prices

From `StomachTiers.luau`. **Twelve coin tiers, one per crossing**, plus a Robux one.
`unlockSlot` = the climb slot you must have REACHED before it can be bought
(server-enforced anti-skip — you can't farm island 1 and buy the Titan Gut).

| # | Name            | maxPower | Cost       | unlockSlot | Opens crossing |
|---|-----------------|----------|------------|------------|----------------|
| 1 | Hatchling Belly | 110      | 0 (default)| 1          | 1 → 2          |
| 2 | Raptor Gut      | 150      | 1,250      | 2          | 2 → 3          |
| 3 | Dilo Stomach    | 200      | 1,400      | 3          | 3 → 4          |
| 4 | Stego Stomach   | 270      | 1,550      | 4          | 4 → 5          |
| 5 | Anky Belly      | 365      | 1,750      | 5          | 5 → 6          |
| 6 | Trike Gut       | 495      | 1,950      | 6          | 6 → 7          |
| 7 | Bronto Belly    | 675      | 2,200      | 7          | 7 → 8          |
| 8 | Spino Stomach   | 920      | 2,450      | 8          | 8 → 9          |
| 9 | Rex Gut         | 1,260    | 2,750      | 9          | 9 → 10         |
| 10| Ptero Belly     | 1,725    | 3,050      | 10         | 10 → 11        |
| 11| Fossil Gut      | 2,360    | 3,450      | 11         | 11 → 12        |
| 12| Titan Gut       | 3,230    | 3,850      | 12         | 12 → 13        |
| 13| Primal Gut      | 9,999    | **499 Robux** | — (not gated) | everything |

**Prices are 4.25 flights of surplus at the tier below** — this is the sole
"3–5 tries per island" dial. Surplus = what one flight nets after buying its fuel;
a gut costing 4.25× that takes ~4 flights to save for, and at 45 s per flight each
island lands at ~3.0 minutes. Prices deliberately span only ~3× (1,250 → 3,850)
because a flight's surplus only roughly doubles up the tower.

Purchase is keyed on `maxPower`; the server reads the PRICE off its own table
(client-sent costs are ignored), unlockSlot is validated, coins deducted, and the
new gut gets a **courtesy fill**: enough power to cross the gap actually in front
of the player × 1.10 (`FlightTuning.courtesyPower`), never more than the tank.

---

## 6. Food — exact prices & power

From `FoodMenu.luau`. **Ordered by CLIMB SLOT** (the order the player meets them),
NOT by island model number. One food stand per island.

| Slot | Food          | Price | Power | Host island (model)   | Gut tier there |
|------|---------------|-------|-------|-----------------------|----------------|
| 1    | Eggs          | 21    | 8     | island1 Nesting Nook  | Hatchling      |
| 2    | Chili Peppers | 53    | 25    | island9 Jungle Junction | Raptor       |
| 3    | Lettuce       | 79    | 45    | island5 Misty Mire    | Dilo           |
| 4    | Grapes        | 101   | 70    | island12 Sunscorch Sands | Stego       |
| 5    | Bananas       | 118   | 100   | island3 Fossil Frontier | Anky         |
| 6    | Popcorn       | 136   | 140   | island13 Glacier Gulch | Trike         |
| 7    | Fish          | 147   | 185   | island4 Coastal Crossing | Bronto      |
| 8    | Ribs          | 156   | 240   | island2 Fern Frontier | Spino          |
| 9    | Potatoes      | 159   | 300   | island10 Petrified Pass | Rex          |
| 10   | Apples        | 160   | 370   | island7 Raptor Ridge  | Ptero          |
| 11   | Mushrooms     | 159   | 450   | island6 Redwood Ridge | Fossil         |
| 12   | Chicken       | 156   | 540   | island8 Inferno Isle  | Titan          |
| 13   | Steak         | 185   | 640   | island11 Volcanic Vista | Titan (summit) |

**Prices are DERIVED, not picked.** Every row is solved for a flat

```
R = (coins a full flight earns) / (coins a full refill costs) = 1.91
price = gap × MARGIN × COIN_PER_STUD / (R × (tierMaxPower / power))
```

against the gap and tank size AT THAT SLOT. Rules that matter:
- **R must stay above 1 at every row** or a flight costs more than it earns and the
  player spirals down. That, not the price, is the number to protect.
- **R > 1 means prices CANNOT set the try count** — a solvent economy gives one-pass
  islands by construction. The only thing that makes an island take several tries is
  a WALL: a gut you can't yet afford. That's what the 12 gut tiers are for.
- `COIN_PER_STUD` (0.14) is the other half of R. Change one, re-solve both.

Buy rules (server `BuyFoodEvent`): coins checked FIRST → "not_enough_coins";
then room check (landing EXACTLY on the cap allowed) → "stomach_full" /
"not_enough_room"; coins never deducted on a rejected buy.

---

## 7. Anti-strand top-up (the economy's safety net)

When a flight ends with the tank at ZERO (`BurnFuelEvent` reports 0 remaining),
the server checks whether the player can afford a **quarter tank** of the food on
the slot they're standing on, and grants only the coin SHORTFALL:

- Funds a **quarter tank** (rounded UP to whole servings), never the whole crossing —
  it used to fund the full crossing, which quietly capped every island at 2 attempts.
- Grants COINS, never fuel — the player still walks to the stand and buys.
- A quarter tank always compounds back to full because R > 1 at every food row.

---

## 8. Other coin sources (exact values)

| Source | Amount | Where |
|--------|--------|-------|
| Rebirth bonus | **250 × rebirth count** lump sum per rebirth | `Rebirth.server.luau` (`COIN_BONUS_PER_REBIRTH = 250`) |
| Daily crate fallback | **500 coins** when every owned pet is already max level | `DailyRewards_Server.server.luau` (`FALLBACK_COINS = 500`, crate cooldown 28,800 s = 8 h) |
| Event multiplier | `_G.serverEventCoinMult` scales flight coins (1 normally) | `WeatherManager` / events |

---

## 9. The full progression loop (how it all locks together)

1. Start with **120 coins** on Nesting Nook (slot 1), Hatchling Belly (tank 110*).
2. Buy the local food → fills the tank up to `StomachMax`.
3. Hold-to-fart → climb at the gut's band speed for up to 45 s → earn
   **0.14 coins per stud climbed**.
4. A full tank climbs the next gap × 1.08 — a clean run just makes the crossing.
   Running dry mid-gap = fall back to the launch island (nothing to land on);
   the anti-strand grant guarantees you can always refuel a quarter tank.
5. Each flight nets 1.91× its fuel cost, so ~4 flights of surplus (4.25×) buys the
   next gut (1,250 … 3,850 coins) — which is the WALL: no gut can climb the gap
   above its own.
6. Buy the gut (unlockSlot-gated to the island you're standing on), get a courtesy
   fill sized for the crossing in front of you × 1.10, cross, repeat.
7. 12 crossings later: Volcanic Vista (Y = 81,616), the finale quest, the T-Rex.

Target pacing: ~3 minutes and 3–5 attempts per island, 45 s per attempt.

\* The leaderstats default is `StomachMax = 100`; the Hatchling tier itself is 110
(every tank carries a +10 capacity bump over the solved sizes).

---

## Change discipline (copy this warning too)

`IslandOrder.SLOT_POS` (gaps), `FlightTuning.TIERS` (band speeds), `FoodMenu.LIST`
(prices/power) and `StomachTiers.LIST` (gut costs) are **one interlocked set**,
all solved from `FLIGHT_SECONDS = 45`, `MARGIN = 1.08`, `COIN_PER_STUD = 0.14`,
`R = 1.91`, and 12% gap growth. Retune together or not at all — nothing errors
when they drift apart; islands just silently become free or unwinnable.
