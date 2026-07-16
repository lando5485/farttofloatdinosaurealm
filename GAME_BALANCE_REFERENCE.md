# Fart to Float — Balance & Economy Reference

> **Source of truth:** pulled directly from the code (`src/server/PlayerStats.server.lua`
> and `src/client/CoreClient.client.lua`), not from CLAUDE.md — CLAUDE.md's prices,
> gut tiers, and island heights are OUT OF DATE. These are the real live values.
> Last verified: 2026-07-16.

---

## 1. Islands — spacing & position

`ISLAND_POSITIONS` in `PlayerStats.server.lua`. Y is the height the island model is
positioned at (the stand/spawn sits a little above it). X/Z zig-zag left↔right so the
climb isn't a straight vertical line.

| # | Island            | X    | Y      | Z    | Gap to next (Y) |
|---|-------------------|------|--------|------|-----------------|
| 1 | Bean Farm         | 0    | 150    | 0    | 640             |
| 2 | Broccoli Bluff    | 120  | 790    | 60   | 890             |
| 3 | Cabbage Cliffs    | -160 | 1680   | 100  | 800             |
| 4 | Turnip Tranquil   | 180  | 2480   | -120 | 1100            |
| 5 | Coconut Cove      | -200 | 3580   | 160  | 1240            |
| 6 | Bread Board       | 220  | 4820   | -180 | 1640            |
| 7 | Pasta Peak        | -240 | 6460   | 200  | 1742            |
| 8 | Popcorn Pinnacle  | 260  | 8202   | -220 | 1530            |
| 9 | Milk Marsh        | -280 | 9732   | 240  | 2246            |
| 10| Butter Swamp      | 300  | 11978  | -260 | 2216            |
| 11| Ice Cream Isle    | -320 | 14194  | 280  | 2944            |
| 12| Burger Bluff      | 340  | 17138  | -300 | 3068            |
| 13| Burrito Barrens   | -360 | 20206  | 320  | 3811            |
| 14| Pizza Palms       | 380  | 24017  | -340 | —               |

**Gaps grow as you climb** (640 → ~3800), so each island is meant to take longer than
the last. Total climb from Bean Farm to Pizza Palms ≈ **23,867 studs**.

**Visual-only Y rotations** (`ISLAND_ROTATIONS`, cosmetic — never changes height/position):
- Island 3 Cabbage Cliffs: 180°
- Island 5 Coconut Cove: 180°
- Island 7 Pasta Peak: -90° (clockwise)

---

## 2. Food — price & power

`foods` table in `PlayerStats.server.lua` (client mirrors it). Each food is unlocked at
its island. **Power** = flight fuel it adds to your tank. **Price** = coins per purchase.

| Food     | Price | Power | Island | Coins per power |
|----------|-------|-------|--------|-----------------|
| Beans    | 5     | 8     | 1      | 0.63            |
| Broccoli | 24    | 25    | 2      | 0.96            |
| Cabbage  | 85    | 45    | 3      | 1.89            |
| Turnips  | 94    | 70    | 4      | 1.34            |
| Coconuts | 142   | 100   | 5      | 1.42            |
| Bread    | 138   | 140   | 6      | 0.99            |
| Pasta    | 202   | 185   | 7      | 1.09            |
| Popcorn  | 600   | 240   | 8      | 2.50            |
| Milk     | 500   | 300   | 9      | 1.67            |
| Butter   | 400   | 370   | 10     | 1.08            |
| IceCream | 560   | 450   | 11     | 1.24            |
| Burger   | 405   | 540   | 12     | 0.75            |
| Burrito  | 700   | 640   | 13     | 1.09            |
| Pizza    | 518   | 750   | 14     | 0.69            |

**Buy rules (server, `BuyFoodEvent`):**
- A purchase is rejected if `newPower > stomachMax` (uses `>`, so landing *exactly* on the
  cap is allowed).
- If the stomach is full, the server fires `StomachFullEvent` and returns **before**
  deducting coins — so a rejected buy costs you nothing.

---

## 3. Stomach / Gut tiers — price per gut

`stomachTiers` in `PlayerStats.server.lua`. `maxPower` is the tank capacity (how much food
power you can hold). All are bought with **Coins** except Infinite, which is **Robux**.

| Tier         | maxPower | Cost   | Currency | Height ceiling* |
|--------------|----------|--------|----------|-----------------|
| Tiny Gut     | 100      | 0      | Coins (default) | 1,450     |
| Small Gut    | 182      | 1,600  | Coins    | 2,598           |
| Medium Gut   | 520      | 3,000  | Coins    | 7,330           |
| Large Gut    | 1,075    | 5,200  | Coins    | 15,100          |
| XL Gut       | 2,146    | 8,000  | Coins    | 30,094          |
| Iron Gut     | 3,218    | 11,000 | Coins    | 45,102          |
| Infinite Gut | 9,999    | 499    | **Robux** | 140,036        |

\* **Height ceiling = `getMaxHeight() = 50 + stomachMax * 14`.** This gates which islands a
gut can reach (you can only land on an island whose Y ≤ your ceiling). Iron Gut (3,218) →
ceiling 45,102, which clears island 14 at Y=24,017, so **Iron is the top of the free path**.
Infinite Gut is a Robux premium that flies the whole map with no practical cap.

**Gut buy = `BuyStomachEvent`** → sets new `StomachMax` and resets `CurrentPower` to 0.

---

## 4. Flight system — how flying up works

All in `CoreClient.client.lua`. Hold the fart button → a `BodyVelocity` drives you straight
up while gas drains. Release or run dry → the velocity is removed and you fall under gravity.

**Fuel / gas meter:**
- `maxGasMeter = 100` (the 0–100 normalized fuel bar).
- **Drain rate: `DRAIN_RATE = 3.5` gas per second** → a full tank lasts **~28 seconds**.
  Drain: `gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt)`. (Infinite Gut owners never drain.)
- Gas ↔ power relationship:
  - `gasMeter = (currentPower / stomachMax) * 100`
  - During flight: `currentPower = (gasMeter / maxGasMeter) * stomachMax`
  - `scaledPower = (gasMeter / maxGasMeter) * stomachMax` (power scaled by remaining gas — this is
    what feeds the speed lookup)
- When gas hits 0, power hits 0 and flight stops.

**Flight speed** — `getFlightSpeed(power)` by current (scaled) power:

| Power ≤ | Vertical speed | Gut band  |
|---------|----------------|-----------|
| 100     | 40             | Tiny      |
| 182     | 62             | Small     |
| 611     | 84             | Medium    |
| 1,075   | 126            | Large     |
| 2,146   | 144            | XL        |
| 3,218   | 226            | Iron      |
| > 3,218 | 280            | Infinite  |

Final velocity: `bodyVel.Velocity = Vector3.new(move.X*48 + wind, speed, move.Z*48 + wind)`
- Vertical `speed` is then multiplied by `_G.serverEventSpeedMult` (event bonus) and
  `_G.rebirthSpeedMult` (+3% per rebirth).
- Horizontal move speed: `FLIGHT_HORIZONTAL_SPEED = 48`.

**Height:** live height read from `hrp.Position.Y`; `_G.peakHeight` tracks the max Y reached
this flight.

**Boosts:**
- **2× Fart Power** (gamepass/product): `POWER_PASS_MULT = 1.4` — food power and effective
  tank both ×1.4, so the internal meter can fill to `100 * 1.4 = 140` for a longer/higher flight
  (displayed bar still clamps to 0–100). Must match the same constant in PlayerStats.
- **Bubble ring** in flight: `+15` gas (`BUBBLE_GAS_BOOST`).

---

## 5. Coins — where & when money is earned flying up

Coins are sent to the server via `CoinEvent:FireServer(...)`. Two independent sources:

### A) Height coins (the main earn), every 0.5s of flight
```
height    = math.max(1, hrp.Position.Y)
tickCoins = height * 0.0044 * serverEventCoinMult     -- mult = 1 normally, 2 during COIN_RUSH
```
- **Per-flight cap** (so flying higher pays more, but a single flight can't runaway):
  `dynCap = math.max(FLIGHT_COIN_CAP, peakHeight * CAP_PER_HEIGHT)`
  where `FLIGHT_COIN_CAP = 80` (floor) and `CAP_PER_HEIGHT = 0.2`. `peakHeight` only rises,
  so the cap never shrinks mid-descent.
- Only the remaining headroom is paid each tick: `pay = min(tickCoins, dynCap - flightCoinsEarned)`.
- **Actual coins sent = `pay * 0.70`** — a flat 70% payout on capped height coins (a balance knob).
- NOTE: the old `(height/500)^2` term from CLAUDE.md is **gone** — earnings are now linear in height.

### B) Ring bonus (separate, uncapped)
```
ringMultiplier = 1 + ringStreak * 0.2
bonus          = math.floor(15 * ringMultiplier * serverEventRingMult)
```
Sent immediately on ring pickup via `CoinEvent:FireServer(bonus)`. Streak resets on landing.

### Server side (`CoinEvent.OnServerEvent`)
Fractional amounts accumulate in `playerCoinAccum`; once the total reaches a whole number,
`math.floor` of it is added to both `Coins` and `TotalCoinsEarned`.

**Rough earn intuition:** height coins ≈ `maxPower * 14 * 0.2 * 0.70` per capped flight, so a
bigger gut both reaches higher islands *and* raises its own coin ceiling.

---

## 6. Power / height / island cheat-sheet

- `getMaxHeight() = 50 + stomachMax * 14` → which islands you can reach.
- Food power stacks in the tank up to `stomachMax`; you cannot exceed the cap (buy rejected).
- Flight converts held power → gas → vertical speed via the band table above.
- To reach island N, your gut's height ceiling must be ≥ that island's Y (see §1), and you
  need enough speed/fuel to actually climb there before the tank drains.

---

## 7. ⚠️ Test flags currently ON (distort live balance — flip before launch)

In `PlayerStats.server.lua`:
- `FORCE_BASE_STOMACH = true` — every player forced to the base Tiny Gut; all gut upgrades
  read as un-owned (real saved StomachMax is preserved through save). Set **false** to restore.
- `DISABLE_2X = true` — in Studio, 2× Fart Power is ignored (food gives 1× power).
- Master **no-perks switch** — while on, ALL gamepass/product perks are ignored (fresh-player run).
- `DISABLE_SAVE_FOR_TESTING` / `[NOSAVE TEST]` — saving off, forced 25 coins on join.

These make a Studio test look like a brand-new no-perks player; the LIVE game is unaffected by
the Studio-only ones, but `FORCE_BASE_STOMACH` and the no-perks switch affect **everyone** until
turned off.
