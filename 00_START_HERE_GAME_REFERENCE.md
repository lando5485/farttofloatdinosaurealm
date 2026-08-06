# Fart to Float — Game Reference

Every number here was read out of the live source, not from memory or from `CLAUDE.md`.
Where the two disagree, **this file is right and `CLAUDE.md` is stale** — see [Corrections](#corrections-to-claudemd).

| | |
|---|---|
| Islands | 14, stacked vertically from Y 150 to Y 24,017 |
| Core loop | buy food → fills the gut → hold fart → climb → earn coins by height → buy more food |
| Authority | server owns coins, power, gut size and island progress; the client drives flight |

---

## 1. The core loop

```
buy FOOD  ──►  CurrentPower rises (capped at StomachMax)
                      │
                      ▼
        hold the FART button ──►  climb at getFlightSpeed(power)
                      │            gas drains 3.5/sec
                      ▼
        every 0.5s: coins = height × 0.0044   (×0.70, capped per flight)
                      │
                      ▼
        run dry ──►  fall ──►  land on the highest island you cleared
                      │
                      ▼
        that island's stand sells better food  ──►  repeat
```

Two separate currencies of progress:

* **CurrentPower** — your fuel *right now*. Spent every flight, refilled by buying food.
* **StomachMax** — the size of the tank. Bought once per tier with coins, permanent.

You cannot out-fly your tank. `StomachMax` sets a hard height ceiling regardless of how much food you buy.

---

## 2. Island placement

`ISLAND_POSITIONS` in `src/server/PlayerStats.server.lua:123`. X and Z alternate sign so the
stack zig-zags rather than being a straight tower.

| # | Island | X | Y | Z | power to reach | cheapest gut that can |
|---|---|---|---|---|---|---|
| 1 | Bean Farm | 0 | 150 | 0 | 7 | Tiny |
| 2 | Broccoli Bluff | 120 | 790 | 60 | 53 | Tiny |
| 3 | Cabbage Cliffs | −160 | 1,680 | 100 | 116 | Small |
| 4 | Turnip Tranquil | 180 | 2,480 | −120 | 174 | Small |
| 5 | Coconut Cove | −200 | 3,580 | 160 | 252 | Medium |
| 6 | Bread Board | 220 | 4,820 | −180 | 341 | Medium |
| 7 | Pasta Peak | −240 | 6,460 | 200 | 458 | Medium |
| 8 | Popcorn Pinnacle | 260 | 8,202 | −220 | 582 | Large |
| 9 | Milk Marsh | −280 | 9,732 | 240 | 692 | Large |
| 10 | Butter Swamp | 300 | 11,978 | −260 | 852 | Large |
| 11 | Ice Cream Isle | −320 | 14,194 | 280 | 1,010 | Large |
| 12 | Burger Bluff | 340 | 17,138 | −300 | 1,221 | XL |
| 13 | Burrito Barrens | −360 | 20,206 | 320 | 1,440 | XL |
| 14 | Pizza Palms | 380 | 24,017 | −340 | 1,712 | XL |

Gaps grow steadily: 640 → 890 → 800 → 1,100 → 1,240 → 1,640 → 1,742 → 1,530 → 2,246 → 2,216 → 2,944 → 3,068 → 3,811.

### How an island unlocks

`checkPeakUnlock()` — `src/client/CoreClient.client.lua:2751`. Runs every flight frame:

```lua
if iy and peakY >= iy and iy <= getMaxHeight() then
```

Both conditions must hold — you must **physically fly to that altitude**, and your gut's ceiling
must reach it. The client then fires `UnlockIslandEvent:FireServer(n)`.

Separately the server tracks `highestIslandReached` from its own downward raycast, which only
counts when you **actually stand on** an island. Flying past does not count. The two markers
legitimately disagree for a while, which is why the food gate reads the higher of the pair.

---

## 3. Flight

`src/client/CoreClient.client.lua`

| Constant | Value | Line |
|---|---|---|
| `maxGasMeter` | 100 | 268 |
| `DRAIN_RATE` | 3.5 gas/sec → a full tank lasts **~28.6 s** | 284 |
| `FLIGHT_HORIZONTAL_SPEED` | 48 studs/s | 288 |
| `POWER_PASS_MULT` | 1.4 (2× Fart Power gamepass) | 273 |

### The two numbers, and how they relate

* `gasMeter` is the 0–100 bar you see.
* `currentPower` is the raw value, scaled to your tank.

```
currentPower = (gasMeter / 100) × StomachMax
gasMeter     = (currentPower / StomachMax) × 100
```

At the base Tiny Gut (max 100) they are the same number. On an Iron Gut, one bar point is 32 power.

### Height ceiling

```
getMaxHeight() = 50 + (StomachMax × 14)
```

| Gut | maxPower | cost | ceiling | tops out at |
|---|---|---|---|---|
| Tiny Gut | 100 | 0 (default) | 1,450 | island 2 |
| Small Gut | 182 | 1,600 | 2,598 | island 4 |
| Medium Gut | 520 | 3,000 | 7,330 | island 7 |
| Large Gut | 1,075 | 5,200 | 15,100 | island 11 |
| XL Gut | 2,146 | 8,000 | 30,094 | island 14 |
| Iron Gut | 3,218 | 11,000 | 45,102 | island 14 |
| Infinite Gut | 9,999 | **499 R$** | 140,036 | island 14 |

XL is the last gut you *need*. Iron and Infinite are headroom.

### Climb speed

`getFlightSpeed(power)` — line 2990. Stepped by **current** power, so you slow down as you drain:

| current power | climb speed |
|---|---|
| ≤ 100 | 40 |
| ≤ 182 | 62 |
| ≤ 611 | 84 |
| ≤ 1,075 | 126 |
| ≤ 2,146 | 144 |
| ≤ 3,218 | 226 |
| above | 280 |

Applied as `bodyVel.Velocity = Vector3.new(move.X × 48 + wind, speed, move.Z × 48 + wind)`,
then multiplied by `_G.serverEventSpeedMult` and doubled while a 2× boost is live.

### Losing fuel

| Source | Effect |
|---|---|
| Normal drain | 3.5 gas/sec while holding fart |
| Bird hit | −20% of **current gas** (`BIRD_GAS_DRAIN_PCT`) |
| Landing / respawn | `currentPower = 0` |

---

## 4. Coins

### Height income

Every 0.5 s during flight, `CoreClient:3138`:

```lua
tickCoins = height × 0.0044 × serverEventCoinMult
dynCap    = math.max(80, peakHeight × 0.2)          -- per-flight ceiling
pay       = math.min(tickCoins, dynCap - earnedSoFar)
CoinEvent:FireServer(pay × 0.70)                     -- 30% balance haircut
```

Three things throttle this:

1. **The 0.70 multiplier** — a flat balance haircut applied after everything else.
2. **A per-flight cap** of `max(80, peakHeight × 0.2)`. Flying higher raises your own ceiling,
   and because `peakHeight` only ever rises, the cap never shrinks on the way down.
3. **Height is live `hrp.Position.Y`**, so you keep earning while falling.

### Rings

Separate, and **uncapped**:

```lua
ringStreak     = ringStreak + 1
ringMultiplier = 1 + ringStreak × 0.2
bonus          = math.floor(15 × ringMultiplier × serverEventRingMult)
```

The streak resets to 0 on landing, so a long chain in one flight is worth far more than the same
rings spread over several. Rings re-spawn 30 s after collection and collect whether rising or falling.

### Gas bubbles

Touching one within 20 studs pops it and grants **+2 gas** (`BUBBLE_GAS_BOOST`, `CoreClient:2904`).
At the base gut that is exactly +2 fart power; on bigger guts it stays 2% of the tank. Re-spawns
after 45 s, and pops whether you are rising or falling.

### Multipliers stacked on the server

`PlayerStats:1292` — applied to every coin tick:

```
final = amount × coinBonusMult × rebirthMult
```

* `coinBonusMult` — friend in server +25%, MLR group member +10%, stackable
* `rebirthMult` — from `RebirthSystem`

---

## 5. Food

`foods` in `src/server/PlayerStats.server.lua:65` — identical table on the client.

| Food | Price | Power | Island | coins per power |
|---|---|---|---|---|
| Beans | 5 | 8 | 1 | 0.62 |
| Broccoli | 24 | 25 | 2 | 0.96 |
| Cabbage | 85 | 45 | 3 | 1.89 |
| Turnips | 94 | 70 | 4 | 1.34 |
| Coconuts | 142 | 100 | 5 | 1.42 |
| Bread | 138 | 140 | 6 | 0.99 |
| Pasta | 202 | 185 | 7 | 1.09 |
| Popcorn | 600 | 240 | 8 | 2.50 |
| Milk | 500 | 300 | 9 | 1.67 |
| Butter | 400 | 370 | 10 | 1.08 |
| IceCream | 560 | 450 | 11 | 1.24 |
| Burger | 405 | 540 | 12 | 0.75 |
| Burrito | 700 | 640 | 13 | 1.09 |
| Pizza | 518 | 750 | 14 | 0.69 |

Power **accumulates** across purchases up to `StomachMax` — you buy repeatedly to fill the tank.

### The two gates

1. **Island lock** — a food unlocks when you have reached **its** island. Locked foods still show
   in the grid, greyed with a 🔒 and `???` instead of a price. Enforced on the client
   (`ShopClient.isUnlocked`) *and* the server (`BuyFoodEvent` check 0, reason `food_locked`).
2. **Coin price** — the only other gate.

**Stands themselves are not locked.** Every stand opens for everyone and lists all 14 foods.
The old pet-quest wall on islands 2/5/8/10/13 is gone; `foodStandUnlocked()` is a permanent `true`.

### Overfill rules

* The check is `newPower > stomachMax` → **reject**, so landing exactly on the cap is allowed.
* On rejection the server fires `StomachFullEvent` and **returns before deducting coins** — you
  keep your money.

---

## 6. Buying a gut

`BuyStomachEvent` — `src/server/PlayerStats.server.lua`

Validation order:

1. the `(maxPower, cost)` pair must be a real non-Robux tier;
2. **it must be a strict upgrade** (`newMax > StomachMax`) — this stops re-buying your current gut
   and stops silent downgrades;
3. you must be able to afford it.

### The purchase fill

Buying a gut does **not** leave you empty, and does not fill you to the brim.
`fillMeterForNextIsland()` tops you up to exactly what the **next** island needs plus 10%:

```lua
powerForNext = (nextIslandY - 50) / 14
target       = powerForNext × 1.10
fill         = clamp(target, 0, newMax)
```

On the real ladder this lands between 53% and 70% of the new tank:

| you're on | you buy | fill | as % of tank |
|---|---|---|---|
| island 2 | Small | 128 / 182 | 70% |
| island 4 | Medium | 277 / 520 | 53% |
| island 7 | Large | 641 / 1,075 | 60% |
| island 11 | XL | 1,343 / 2,146 | 63% |
| island 14 | Iron | 1,883 / 3,218 | 59% |

Because the upgrade-only rule is enforced, the fill can never clamp to a full tank.

### When power resets to 0

1. island unlocked (`UnlockIslandEvent`)
2. character respawn / `stopFlying` / landing

---

## 7. Data ownership

| Value | Lives in | Written by |
|---|---|---|
| `Coins`, `TotalCoinsEarned` | leaderstats | server, from `CoinEvent` |
| `CurrentPower` | leaderstats | server, on food buy / gut buy / landing |
| `StomachMax` | leaderstats | server, on gut buy |
| `Island` | leaderstats | server, on `UnlockIslandEvent` (peak height) |
| `highestIslandReached` | server memory + save | server raycast, physical landing only |
| `gasMeter`, live height | client only | flight loop |

---

## Corrections to CLAUDE.md

`CLAUDE.md` is out of date on every table. Do not trust it for numbers.

| | CLAUDE.md says | actually |
|---|---|---|
| Island 14 Y | 45,000 | **24,017** |
| Island 2 Y | 600 | **790** |
| Drain rate | 4/sec | **3.5/sec** |
| Climb speeds | 28 / 35 / 45 / 58 / 75 / 95 / 120 | **40 / 62 / 84 / 126 / 144 / 226 / 280** |
| Coin formula | `h×0.008 + (h/500)²` | **`h × 0.0044`, ×0.70, capped** |
| Beans price | 10 | **5** |
| Pizza price | 900,000 | **518** |
| Tiny Gut max | 40 | **100** |
| Iron Gut cost | 200,000 | **11,000** |
| Stomach purchase | not described | **fills to next island +10%** |
| Food island lock | not described | **enforced client + server** |

Also unmentioned there: the per-flight coin cap, the 0.70 haircut, ring streaks, gas bubbles,
rebirth/friend multipliers, and the horizontal flight speed.
