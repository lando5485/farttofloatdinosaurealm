# Progression & Economy — Full Reference

How coins are earned while flying, the starting state, how the stomach (gut)
upgrades work, and how that progression is gated by island spacing. Copy this
system into another game. Source of truth: `CoreClient.client.lua` (flight +
coin loop + height ceiling) and `PlayerStats.server.lua` (defaults + coin
accumulation + stomach purchase). NOTE: the formulas in `CLAUDE.md` are STALE —
the numbers below are the LIVE ones.

---

## 1. Starting state (new player)

`PlayerStats.server.lua` defaults:
- **Coins = 25**
- **StomachMax = 100** (Tiny Gut)
- **Island = 1**, CurrentPower / gas meter = 0

```lua
local DEFAULT_COINS, DEFAULT_STOMACH, DEFAULT_ISLAND = 25, 100, 1
```

---

## 2. Coins earned WHILE FLYING

Two separate income streams: **height coins** (capped) and **ring bonuses** (uncapped).

### A) Height coins — every 0.5s of flight (client, CoreClient)

```lua
local FLIGHT_COIN_CAP = 80   -- floor: minimum per-flight height-coin cap
local CAP_PER_HEIGHT  = 0.2  -- per-flight cap = max(FLIGHT_COIN_CAP, peakHeight * this)
local flightCoinsEarned = 0  -- height coins already sent THIS flight

-- inside the flight loop, accumulate dt; every 0.5s:
coinTimer = coinTimer + dt
if coinTimer >= 0.5 then
    coinTimer = 0
    local height = math.max(1, hrp.Position.Y)
    local tickCoins = height * 0.0044 * (_G.serverEventCoinMult or 1) -- mult=1 normally, 2 during COIN_RUSH
    -- per-flight cap SCALES with how high you fly (peakHeight only rises -> never shrinks mid-descent)
    local dynCap = math.max(FLIGHT_COIN_CAP, (_G.peakHeight or height) * CAP_PER_HEIGHT)
    local pay = math.min(tickCoins, dynCap - flightCoinsEarned)
    if pay > 0 then
        flightCoinsEarned = flightCoinsEarned + pay
        CoinEvent:FireServer(pay * 0.70) -- [BALANCE] pays out 70% of the capped flight coins
    end
end
```

Plain English:
- Each 0.5s you earn `height × 0.0044` coins (so higher = more per tick).
- But total HEIGHT coins per flight are capped at `max(80, peakHeight × 0.2)` —
  flying higher RAISES the cap, so deep flights pay far more than shallow ones.
- Only 70% of that is actually sent (a balance knob).
- `flightCoinsEarned` resets to 0 at the start of each flight; `peakHeight` is
  the max Y reached this flight.

### B) Ring bonus — on each ring collected (separate, NOT capped)

```lua
ringStreak = ringStreak + 1
ringMultiplier = 1 + ringStreak * 0.2                       -- +20% per ring in the streak
local bonus = math.floor(15 * ringMultiplier * (_G.serverEventRingMult or 1))
CoinEvent:FireServer(bonus)
-- on LAND: ringStreak = 0; ringMultiplier = 1  (streak resets each flight)
```

### C) Server accumulation (PlayerStats — `CoinEvent`)

The client sends fractional amounts; the server accumulates and floors them into
`Coins` + `TotalCoinsEarned`:

```lua
local playerCoinAccum = {}
CoinEvent.OnServerEvent:Connect(function(player, amount)
    local ls = player:FindFirstChild("leaderstats"); if not ls then return end
    local coins = ls:FindFirstChild("Coins")
    local tce   = ls:FindFirstChild("TotalCoinsEarned")
    if not coins or not tce then return end
    local amt = tonumber(amount) or 0; if amt <= 0 then return end
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

## 3. The STOMACH (gut) system

### Tiers (coin-bought except the last, which is Robux)

```lua
local stomachTiers = {
    {name="Tiny Gut",     maxPower=100,  cost=0,      robux=false},
    {name="Small Gut",    maxPower=182,  cost=1600,   robux=false},
    {name="Medium Gut",   maxPower=520,  cost=3000,   robux=false},
    {name="Large Gut",    maxPower=1075, cost=5200,   robux=false},
    {name="XL Gut",       maxPower=2146, cost=8000,   robux=false},
    {name="Iron Gut",     maxPower=3218, cost=11000,  robux=false},
    {name="Infinite Gut", maxPower=9999, cost=499,    robux=true},  -- Robux
}
```

### What stomachMax does — the HEIGHT CEILING

```lua
local function getMaxHeight()
    return 50 + (stomachMax * 14)   -- the gut's height ceiling (gates island unlocks only)
end
```

### Buying a gut (server — `BuyStomachEvent(newMax, cost)`)

Validates the `(maxPower, cost)` pair against a real, non-Robux tier, deducts coins,
sets StomachMax, and CARRIES the current power over (only the MAX grows):

```lua
BuyStomachEvent.OnServerEvent:Connect(function(player, newMax, cost)
    local ls = player:FindFirstChild("leaderstats"); if not ls then return end
    local coins = ls:FindFirstChild("Coins"); local stomachMaxStat = ls:FindFirstChild("StomachMax")
    if not coins or not stomachMaxStat then return end
    local newMaxN, costN = tonumber(newMax) or 0, tonumber(cost) or 0
    if costN <= 0 or newMaxN <= 0 then return end
    local valid = false
    for _, t in ipairs(stomachTiers) do
        if t.maxPower == newMaxN and t.cost == costN and not t.robux then valid = true break end
    end
    if not valid or coins.Value < costN then return end
    coins.Value = coins.Value - costN
    stomachMaxStat.Value = newMaxN
    local cp = ls:FindFirstChild("CurrentPower")
    if cp then cp.Value = math.min(cp.Value, newMaxN) end -- carry power over (only the tank max grows)
    -- fire RegenEvent / StomachUpdateEvent to refresh the HUD
end)
```

(The full buy handlers — food + stomach — are already in
`src/server/Shop_AllInOne.server.lua`. The stomach upgrade MENU + the stomach
button live in `CoreClient.client.lua`; say the word for a standalone copy.)

---

## 4. How progression is GATED BY ISLAND SPACING

This is the core loop. An island N unlocks only when BOTH are true:
1. Your **peak flight height** has reached island N's Y, AND
2. Your gut's **ceiling** (`getMaxHeight`) is high enough to reach that Y.

```lua
local function checkPeakUnlock(peakY)
    for n = highestUnlockedByHeight + 1, 14 do
        local iy = ISLAND_POS[n] and ISLAND_POS[n].y
        if iy and peakY >= iy and iy <= getMaxHeight() then
            highestUnlockedByHeight = n
            -- ... mark island n unlocked
        end
    end
end
```

So you **must keep buying bigger guts** to raise your ceiling past the next
island's height. The gut ceiling each tier reaches (`50 + maxPower×14`) maps to
the island band it can unlock (island Ys: 150, 790, 1680, 2480, 3580, 4820,
6460, 8202, 9732, 11978, 14194, 17138, 20206, 24017):

| Gut          | maxPower | Cost        | Ceiling (50+pwr×14) | Highest island it can reach |
|--------------|----------|-------------|---------------------|------------------------------|
| Tiny Gut     | 100      | 0           | 1,450               | Island 2 (790)               |
| Small Gut    | 182      | 1,600       | 2,598               | Island 4 (2,480)             |
| Medium Gut   | 520      | 3,000       | 7,330               | Island 7 (6,460)             |
| Large Gut    | 1,075    | 5,200       | 15,100              | Island 11 (14,194)           |
| XL Gut       | 2,146    | 8,000       | 30,094              | Island 14 (24,017)           |
| Iron Gut     | 3,218    | 11,000      | 45,102              | Island 14 (+ headroom)       |
| Infinite Gut | 9,999    | 499 Robux   | 140,036             | Everything + Space Realm     |

(Reaching the height itself also needs enough fart POWER: food power → fuel →
height. The food table — price/power, island-gated — is in `Shop_AllInOne` /
`PlayerStats`.)

### The full progression loop
1. Buy food (uses coins, fills the gut up to `stomachMax`).
2. Hold-to-fart → fly up → earn **height coins** (`height×0.0044`, capped at
   `max(80, peakHeight×0.2)`, 70% paid) + **ring bonuses** (`15 × (1+streak×0.2)`).
3. Spend coins on a **bigger gut** → raises `getMaxHeight` → unlock the next
   island band → buy its stronger food → fly higher → earn more. Repeat to 14.

---

## What to copy into the other game
- Defaults: `coins=25, stomachMax=100, island=1`.
- The flight coin loop (§2A) + ring bonus (§2B) on the client.
- `CoinEvent` accumulation (§2C) + `BuyStomachEvent` (§3) on the server.
- `stomachTiers` + `getMaxHeight` + `checkPeakUnlock` (§3–4).
- Your island Y positions (see `ISLAND_SPACING.md`) so the unlock gate lines up.
```
