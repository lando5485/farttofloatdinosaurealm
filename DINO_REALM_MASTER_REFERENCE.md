# Dinosaur Realm — Master Reference (Placement + Progression)

Every number below was read out of **this repo's live source**, not from the Fart to Float
reference docs. Where they disagree, this file is right for Dinosaur Realm — the reference
docs describe the ORIGINAL 14-island game.

| | |
|---|---|
| Islands | **13**, stacked vertically from Y 150 to Y 19,200 |
| Total climb | **19,050 studs** (slot 1 → slot 13) |
| Core loop | buy food → fills the gut → hold fart → climb → reach the next island → better food |
| Summit | slot 13 = `island11` "Volcanic Vista" (geyser finale, grants the T-Rex) |
| Authority | server owns Coins / CurrentPower / StomachMax / HighestIsland; the client drives flight |

> **The one thing that trips everyone up:** an island's **model number** (`island8` in
> Workspace) is NOT its **climb position**. `IslandLayout` scatters model numbers across the
> tower so quest and blank islands alternate. Slot = climb order. Always use slot.

---

## 1. ISLAND PLACEMENT — the full coordinate table

Source: `SLOT_POS` in `src/server/IslandLayout.server.luau:41` +
`SLOT_TO_ISLAND` in `src/shared/IslandOrder.luau:22`.

| Slot | X | Y | Z | Model | Display name | Type | ΔY from below |
|---|---|---|---|---|---|---|---|
| 1 (bottom) | 0 | 150 | 0 | `island1` | Nesting Nook | QUEST | — |
| 2 | 120 | 790 | 60 | `island9` | Jungle Junction | blank | 640 |
| 3 | −160 | 1,680 | 100 | `island2` | Fern Frontier | QUEST | 890 |
| 4 | 180 | 2,480 | −120 | `island12` | Sunscorch Sands | blank | 800 |
| 5 | −200 | 3,580 | 160 | `island3` | Fossil Frontier | QUEST | 1,100 |
| 6 | 220 | 4,820 | −180 | `island13` | Glacier Gulch | blank | 1,240 |
| 7 | −240 | 6,460 | 200 | `island4` | Coastal Crossing | QUEST | 1,640 |
| 8 | 260 | 8,202 | −220 | `island5` | Misty Mire | QUEST | 1,742 |
| 9 | −280 | 9,732 | 240 | `island10` | Petrified Pass | blank | 1,530 |
| 10 | 300 | 11,978 | −260 | `island7` | Raptor Ridge | QUEST | 2,246 |
| 11 | −320 | 14,194 | 280 | `island6` | Redwood Ridge | QUEST | 2,216 |
| 12 | 340 | 16,600 | −300 | `island8` | Inferno Isle | blank | 2,406 |
| 13 (SUMMIT) | −360 | 19,200 | 320 | `island11` | **Volcanic Vista** | QUEST | 2,600 |

**Quest islands (8):** models 1, 2, 3, 4, 5, 6, 7, 11
**Blank scenery islands (5):** models 8, 9, 10, 12, 13

### How the spacing works

- **Y** — gaps grow as you climb: 640 → 2,600. Each island is meant to take longer than the last.
- **X** — alternates sign every slot and grows +20 per step: 0, 120, −160, 180, −200, 220, −240, 260, −280, 300, −320, 340, −360.
- **Z** — same zig-zag: 0, 60, 100, −120, 160, −180, 200, −220, 240, −260, 280, −300, 320.

So the tower zig-zags side-to-side *and* front-to-back while the vertical gaps stretch out.

### Copy-paste (Lua)

```lua
-- slot -> world position (bottom = 1, summit = 13)
local SLOT_POS = {
	[1]  = Vector3.new(   0,   150,    0),
	[2]  = Vector3.new( 120,   790,   60),
	[3]  = Vector3.new(-160,  1680,  100),
	[4]  = Vector3.new( 180,  2480, -120),
	[5]  = Vector3.new(-200,  3580,  160),
	[6]  = Vector3.new( 220,  4820, -180),
	[7]  = Vector3.new(-240,  6460,  200),
	[8]  = Vector3.new( 260,  8202, -220),
	[9]  = Vector3.new(-280,  9732,  240),
	[10] = Vector3.new( 300, 11978, -260),
	[11] = Vector3.new(-320, 14194,  280),
	[12] = Vector3.new( 340, 16600, -300),
	[13] = Vector3.new(-360, 19200,  320),
}

-- slot -> island MODEL number in Workspace
local SLOT_TO_ISLAND = { 1, 9, 2, 12, 3, 13, 4, 5, 10, 7, 6, 8, 11 }

-- island MODEL number -> display name
local NAMES = {
	"Nesting Nook", "Fern Frontier", "Fossil Frontier", "Coastal Crossing", "Misty Mire",
	"Redwood Ridge", "Raptor Ridge", "Inferno Isle", "Jungle Junction", "Petrified Pass",
	"Volcanic Vista", "Sunscorch Sands", "Glacier Gulch",
}

local QUEST = { [1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[11]=true }
```

The coordinate is the island model's **pivot**; `IslandLayout` moves each model with
`PivotTo` so rotation is preserved and children come along. Players stand a little above it.

### Planned 15-slot expansion (not live)

Commented at `IslandLayout.server.luau:88-106`. Adding two blank islands would let the
tower alternate quest/blank perfectly all the way up:

```lua
[14] = Vector3.new( 380, 21900, -340),
[15] = Vector3.new(-400, 24800,  360),
-- order: 1, 9, 2, 12, 3, 13, 4, 10, 5, 8, 6, 14, 7, 15, 11
```

---

## 2. FOOD — price, power, and where it unlocks

Source: `foods` in `src/server/Shop.server.luau:50`, mirrored exactly in
`src/client/ShopGlue.client.luau:17`. **`island=` is the MODEL number**, so the unlock
order in climb terms is the second table below.

### By model number (as written in code)

| Food | Price | Power | Model island | Coins/power |
|---|---|---|---|---|
| Eggs | 5 | 8 | 1 | 0.63 |
| Lettuce | 24 | 25 | 2 | 0.96 |
| Bananas | 85 | 45 | 3 | 1.89 |
| Fish | 94 | 70 | 4 | 1.34 |
| Ribs | 142 | 100 | 5 | 1.42 |
| Mushrooms | 138 | 140 | 6 | 0.99 |
| Apples | 202 | 185 | 7 | 1.09 |
| Chicken | 600 | 240 | 8 | 2.50 |
| Chili Peppers | 500 | 300 | 9 | 1.67 |
| Potatoes | 400 | 370 | 10 | 1.08 |
| Steak | 560 | 450 | 11 | 1.24 |
| Grapes | 405 | 540 | 12 | 0.75 |
| Popcorn | 700 | 640 | 13 | 1.09 |

*(Turkey Legs — island 14, 518/750 — was retired with island14. It was also a dominated
option: cheaper AND stronger than the food below it.)*

### By climb slot (the order a player actually meets them)

| Slot | Island | Food | Price | Power | Buyable on the tank you'd have? |
|---|---|---|---|---|---|
| 1 | Nesting Nook | Eggs | 5 | 8 | yes |
| 2 | Jungle Junction | Chili Peppers | 500 | 300 | **no** — 300 > Hatchling's 100 |
| 3 | Fern Frontier | Lettuce | 24 | 25 | yes |
| 4 | Sunscorch Sands | Grapes | 405 | 540 | **no** — 540 > Raptor's 182 |
| 5 | Fossil Frontier | Bananas | 85 | 45 | yes |
| 6 | Glacier Gulch | Popcorn | 700 | 640 | **no** — 640 > Stego's 520 |
| 7 | Coastal Crossing | Fish | 94 | 70 | yes |
| 8 | Misty Mire | Ribs | 142 | 100 | yes |
| 9 | Petrified Pass | Potatoes | 400 | 370 | yes (Bronto) |
| 10 | Raptor Ridge | Apples | 202 | 185 | yes |
| 11 | Redwood Ridge | Mushrooms | 138 | 140 | yes |
| 12 | Inferno Isle | Chicken | 600 | 240 | yes |
| 13 | Volcanic Vista | Steak | 560 | 450 | yes |

> ⚠️ **Balance note.** Because food power was left on the original model numbering while the
> tower reorders the islands, power along the climb goes
> **8 → 300 → 25 → 540 → 45 → 640 → 70 → 100 → 370 → 185 → 140 → 240 → 450** — it swings
> instead of ramping. Three foods (Chili Peppers, Grapes, Popcorn) unlock on a slot where
> the player's tank is physically too small to accept a single serving, so the buy is
> rejected outright (`newPower > effectiveMax`). They become buyable several guts later.
> If you want a clean ramp, re-key `foods` by **slot** instead of model number.

### Buy rules (`BuyFoodEvent`, `Shop.server.luau:116`)

Checked in this order:

1. **Coins first** — `coins < price` → fires `StomachFullEvent("not_enough_coins")`, no charge.
2. **Capacity** — `newPower > effectiveMax` → rejected **before** coins are deducted, so a
   failed buy is free. Two distinct reasons:
   - no room at all → `"stomach_full"`
   - has room but this food is too big → `"not_enough_room"`
3. Uses `>`, so landing **exactly** on the cap is allowed.

On success: coins deducted, `CurrentPower += powerGain`, `TotalFartPower += power (×2 with the pass)`,
`RegenEvent` fired to the client, and `_G.petOnGas` awards pet XP.

### The 2× Fart Power pass

`POWER_PASS_MULT = 1.4` (`Shop.server.luau:84`). When owned (`HasTwoXForever` attribute, or
an unexpired `TwoXHourExpiry`):

```lua
powerGain    = floor(food.power * 1.4)
effectiveMax = floor(stomachMax * 1.4)   -- the tank grows too
```

Kill switches, all currently `false` (i.e. the pass is live): `DISABLE_2X`,
`DISABLE_PERKS_FOR_BALANCE`, `FORCE_NO_2X`.

### Island lock

`Shop.client.luau:26` — a food shows locked unless `unlockedIslands[islandNum]` or
`_G.unlockedIslands[islandNum]` is set. Island 1 starts unlocked. Locked foods still appear
in the grid, greyed out and not buyable.

---

## 3. GUT (stomach) TIERS

`stomachTiers` — `src/server/Shop.server.luau:70`. Height ceiling = `50 + maxPower × 14`.

| Tier | maxPower | Cost | Currency | Height ceiling | Highest slot it reaches |
|---|---|---|---|---|---|
| Hatchling Belly | 100 | 0 (default) | — | 1,450 | slot 2 (Y 790) |
| Raptor Gut | 182 | 1,600 | Coins | 2,598 | slot 4 (Y 2,480) |
| Stego Stomach | 520 | 3,000 | Coins | 7,330 | slot 7 (Y 6,460) |
| Bronto Belly | 1,075 | 5,200 | Coins | 15,100 | slot 11 (Y 14,194) |
| Rex Gut | 2,146 | 8,000 | Coins | 30,094 | **slot 13 — summit** |
| Fossil Gut | 3,218 | 11,000 | Coins | 45,102 | summit + headroom |
| Primal Gut | 9,999 | **499 R$** | Robux | 140,036 | summit + everything |

**Rex Gut is the last one you need** (8,000 coins clears the whole tower). Fossil and Primal
are pure headroom. Total coin cost of the free path: **1,600 + 3,000 + 5,200 + 8,000 = 17,800**
(28,800 if you also buy Fossil).

### Buying a gut (`BuyStomachEvent`, `Shop.server.luau:181`)

1. `(maxPower, cost)` must match a real **non-Robux** tier — blocks made-up pairs.
2. Must afford it.
3. Deduct coins, set `StomachMax`, then **carry the current power over**:
   `cp.Value = math.min(cp.Value, newMax)` — only the tank's max grows, your fill stays.
4. Fires `RegenEvent` + `StomachUpdateEvent` to refresh the HUD.

> **Divergence from the original game.** Fart to Float's `fillMeterForNextIsland()` topped
> you up to "next island's requirement + 10%" on purchase. Dinosaur Realm does **not** — it
> just carries your existing fill. There is also **no strict-upgrade check here**, so a
> client could in principle buy a *lower* tier it can afford and shrink its own tank. Add
> `if newMaxN <= stomachMaxStat.Value then return end` if you want the original's guard.

`TEST_FULL_DATA` (line 88, currently `false`) lets you switch to any tier for free, ignoring
cost and coins — for sampling each tier's reach. Leave it off in production.

---

## 4. FLIGHT

All client-side in `src/client/BottomHUD.client.luau:184-360`.

| Constant | Value | Line |
|---|---|---|
| `maxGasMeter` | 100 | 194 |
| `DRAIN_RATE` | 3.5 gas/sec → a full tank lasts **~28.6 s** | 195 |
| `FLIGHT_HORIZONTAL_SPEED` | 48 studs/s | 196 |

### Gas ↔ power

```
gasMeter     = (currentPower / stomachMax) × 100     -- the 0..100 bar you see
currentPower = (gasMeter / 100) × stomachMax         -- recomputed every frame while flying
```

At Hatchling Belly (max 100) they're the same number. On a Fossil Gut, one bar point is 32 power.

### Climb speed — `getFlightSpeed(power)`, line 204

Stepped by **current** (gas-scaled) power, so you slow down as you drain:

| current power ≤ | rise speed | gut band |
|---|---|---|
| 100 | 40 | Hatchling |
| 182 | 62 | Raptor |
| 611 | 84 | Stego |
| 1,075 | 126 | Bronto |
| 2,146 | 144 | Rex |
| 3,218 | 226 | Fossil |
| above | 280 | Primal |

Applied as:

```lua
local speed = getFlightSpeed(currentPower) * (_G.flightDistanceMultiplier or 1)
bodyVel.Velocity = Vector3.new(move.X * 48, speed, move.Z * 48)
bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
```

`_G.flightDistanceMultiplier` is the weather hook — Monsoon Rain sets it to **0.9** (−10% flight).

### Controls & fuel loss

- **Toggle**, not hold: tap the fart button or **Space** to start; tap again to cancel.
- Cancelling **keeps** leftover gas — the next tap resumes.
- Running dry auto-stops and you fall.
- **Only respawn zeroes the meter** (`CharacterAdded`, line 344). Landing does not.
- Launch fires `MeteorLaunchSnapshot` so Meteorite Explosion can restore your coins + power on death.
- 7 fart sounds, picked at random per launch (line 277).

---

## 5. COINS — and the gap

Starting state (`Shop.server.luau:99`, `setupStats`):

```
Coins = 25,  CurrentPower = 0,  StomachMax = 100,  Island = 1,
TotalFartPower = 0,  TotalCoinsEarned = 0
```

### ⚠️ The height-coin loop is NOT implemented in this realm

`CoinEvent` is **created** at `Shop.server.luau:36` but nothing in `src/` ever fires it and
nothing handles `CoinEvent.OnServerEvent`. The original game's two income streams are both
absent here:

```lua
-- MISSING (client, every 0.5s of flight):
tickCoins = height * 0.0044 * (_G.serverEventCoinMult or 1)
dynCap    = math.max(80, (_G.peakHeight or height) * 0.2)   -- per-flight ceiling
pay       = math.min(tickCoins, dynCap - flightCoinsEarned)
CoinEvent:FireServer(pay * 0.70)                             -- 30% balance haircut

-- MISSING (client, on ring pickup — uncapped):
ringStreak     = ringStreak + 1
ringMultiplier = 1 + ringStreak * 0.2
CoinEvent:FireServer(math.floor(15 * ringMultiplier))

-- MISSING (server): playerCoinAccum accumulation + math.floor into Coins/TotalCoinsEarned
```

`playerCoinAccum` is declared at `Shop.server.luau:93` but never used. So right now coins
only arrive from Rebirth lump sums, Daily Rewards, and Robux products — **there is no way to
earn coins by flying.** With the gut ladder costing 17,800 coins, that's the blocker on the
whole progression. See `PROGRESSION_ECONOMY.md` §2 for the drop-in implementation.

### What *does* watch coins

`PetXPHooks.server.luau:131` polls `leaderstats.Coins` and awards pet XP on any increase,
whatever the source — so you don't have to patch each award site when you add the flight loop.

---

## 6. PROGRESSION TRACKING

| Value | Where | Written by |
|---|---|---|
| `Coins`, `TotalCoinsEarned` | leaderstats | server |
| `CurrentPower` | leaderstats | server, on food buy / gut buy |
| `StomachMax` | leaderstats | server, on gut buy |
| `Island` | leaderstats | server |
| `HighestIsland` | player attribute | `PetXPHooks` — highest **model number** stood on |
| `HighestSlot` | player attribute | `PetXPHooks` — highest **climb slot** stood on |
| `gasMeter`, live height | client only | flight loop |

**Unlock is physical, not peak-height based.** `PetXPHooks.server.luau:146-170` polls which
island the player is standing on and bumps `HighestIsland` / `HighestSlot` when it's a new
best (+600 pet XP once per island). There is **no `checkPeakUnlock()`** here — flying past an
island at altitude does not unlock it; you have to land on it.

**Use `HighestSlot`, not `HighestIsland`, for anything progression-shaped.** The tower
scrambles model numbers against climb order, so `HighestIsland` is a max model number and
sorts wrong. `WormholeService.server.luau:76` gates on the slot for exactly this reason.
The Bootstrap "TO NEXT REALM" bar (line 613) still reads `HighestIsland / 13` — that bar is
inaccurate whenever the two disagree.

Other consumers: `MeteoriteExplosion` (respawn island), `PurchaseReceipts` (Skip Island
product bumps `HighestIsland`), `Rebirth` (resets it to 1).

---

## 7. RELATED SYSTEMS

| Topic | File |
|---|---|
| Anchoring islands so nothing falls, while rigs still animate | `ISLAND_ANCHORING.md` |
| Food stands | `FOOD_STAND.md` |
| Pets | `PET_SYSTEM.md` |
| NPC dialogue | `NPC_DIALOGUE.md` |
| HUD layout | `HUD_LAYOUT_REFERENCE.md` |
| Original 14-island game (for comparison) | `00_START_HERE_GAME_REFERENCE.md`, `ISLAND_SPACING.md`, `PROGRESSION_ECONOMY.md`, `GAME_BALANCE_REFERENCE.md` |

**Debug:** `/island N` teleports to island **model** N (1–13), reading positions live from
Workspace — `src/server/IslandTeleport.server.luau`.

---

## 8. DIFFERENCES FROM THE ORIGINAL FART TO FLOAT

| | Fart to Float | Dinosaur Realm |
|---|---|---|
| Islands | 14 | **13** (island14 + Turkey Legs retired) |
| Top island Y | 24,017 | **19,200** |
| Slots 12–13 Y | 17,138 / 20,206 | **16,600 / 19,200** (recomputed for 13) |
| Climb order | model number = slot | **scrambled** — quest/blank alternate |
| Gut purchase | tops up to next island +10% | **carries existing power over** |
| Strict-upgrade check on gut buy | yes | **no** |
| Island unlock | peak flight height + gut ceiling | **physical landing only** |
| Height coins / ring streaks / gas bubbles | yes | **not implemented** |
| Food/gut names | Beans…Pizza, Tiny…Infinite | Eggs…Popcorn, Hatchling…Primal |
| Prices & powers | — | **identical** |
| Flight constants | — | **identical** (3.5 drain, 48 horizontal, same 7 speed bands) |
