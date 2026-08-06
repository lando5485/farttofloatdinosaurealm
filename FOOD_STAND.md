# Food Stand — spec + copy (for porting to Candy Realm)

Three files own it:
- `src/client/ShopGlue.client.luau` — finds the stands in Workspace, opens/closes on proximity
- `src/client/Shop.client.luau` — builds the shop panel UI (lines 70–143), buy handlers (814–876)
- `src/server/Shop.server.luau` — food/tier data (50–78), authoritative BuyFood (116–176), BuyStomach (181–226)

---

## ⚠️ Read this first: the stand's geometry is NOT in code

No script anywhere builds the stall's parts, roof, counter, or decor. The stands are
**models authored by hand in Studio and placed in Workspace**. `default.project.json`
only syncs `src/shared`, `src/server`, `src/client` — there are no `.rbxmx` files in the repo,
so **you cannot port the physical stall from this repo.** You'll have to rebuild or
copy/paste the model in Studio.

What the code *does* rely on is a naming contract, and that ports cleanly:

- A `BasePart`, **or** a `Model` containing at least one BasePart
- Named case-insensitively `shop` or `stand`, with an optional number suffix
- Matched by `^shop%d*$` / `^stand%d*$` (`ShopGlue.client.luau:102`)
- Valid: `Stand`, `stand`, `Stand5`, `Shop9`, `SHOP`

The only server-side geometry code is `AnchorIslands.server.luau:109-120`, which anchors
every `^stand%d*$` part **and all its descendants** so the stall doesn't fall apart at runtime.
Port that — it fixes a real bug.

### How a stand knows which island (→ which food) it sells

`ShopGlue.client.luau:65-93`, three tiers, most explicit first:
1. **Number in its own name** — `Stand5` → island 5
2. **Ancestor model named `island<N>`** — `Workspace.island6.…Stand` → island 6
3. **Nearest island by bounding-box distance** — last resort for a loose stand

Fallback is island 1. For Candy Realm just keep tier 1 and 2; tier 3 is a safety net.

---

## How it ACTS

**No ProximityPrompt, no BillboardGui, no SurfaceGui.** It opens purely on walk-up proximity.

`ShopGlue.client.luau:188-221`:

| Constant | Value |
|---|---|
| `OPEN_DIST` | 7.5 studs |
| `CLOSE_DIST` | 8 studs |
| Poll rate | `task.wait(0.15)` |
| Workspace re-scan | every 20 ticks (~3s), catches stands that stream in late |
| Initial gather retries | 60 × 1s |

- **Hysteresis** — opens at ≤7.5, closes at >8. The 0.5-stud gap stops the panel flickering when you stand right on the boundary.
- **Distance is measured to the nearest SURFACE** of the stand part (`surfaceDist`, `:165-175`), not its center — so a big stall model works, not just a small block.
- **`manualClosed` flag** (`:205`) — if you X out while still standing at the stand, it won't auto-reopen until you walk away past `CLOSE_DIST`.
- **Opens with the specific stand's island number**, `_G.OpenFoodShop(island)` at `:215`. The comment there documents the old bug where a hardcoded `1` made every stand on every island sell island-1 Eggs.
- Checks `_G.MainMenuManager.isOtherOpen("FoodShop")` before opening so it doesn't fight another menu.

### Dead code — don't port it

`Shop.client.luau:940-1012` is a second, older proximity implementation (`STAND_TRIGGER_RADIUS = 12`, requires grounded / not flying, 2s re-arm). It is **inert**: it waits on `StandsReadyEvent`, which the server creates but never fires (`Shop.server.luau:37-40`). `#stands == 0` so it early-returns at `:964`. Two competing implementations in one codebase — port only the ShopGlue one.

---

## How it LOOKS

`Shop.client.luau:70-143`. `ScreenGui` named `FoodShopGui`, `ResetOnSpawn=false`, `DisplayOrder=100` (definitively above the HUD, which is ≤5).

There's a full-screen backdrop Frame at `:72` with `Active=false` — deliberately, so clicks *outside* the panel fall through to the HUD menu buttons (lets you click straight from shop to another menu). The panel itself is `Active=true` so its own clicks don't leak.

**Panel** — `0.92 × 0.78` screen, centered, bg `RGB(240,248,255)`, corner 16, stroke `RGB(100,180,255)` @ 4px.
**Header** — 55px tall, `RGB(80,160,255)`, corner 16. Title `"🏝️ ISLAND 1 FOOD STAND"` Gotham 24 white with a 2px black stroke; retitled live at `:306` to `"🏝️ ISLAND "..islandNum.." FOOD STAND"`. Close button 40×40 `RGB(255,60,60)`, "X", GothamBold 20, corner 8, at `(1,-45),(0,7)`.

**Left "featured food" panel** — 280px wide, full height minus 65, white, corner 12:
- 120×120 icon box at top. Two overlapping nodes — a `TextLabel` emoji (TextSize 80) and an `ImageLabel`; exactly one is visible. If the food is in `foodImages` the image shows, else the emoji.
- Name — GothamBold 26, centered, y=135
- Price row — a horizontal `UIListLayout` pairing a 22×22 coin `ImageLabel` with the price text (Gotham 20, `RGB(200,140,0)`). This exists because the 🪙 emoji doesn't render in Roblox's font — same reason `foodImages` exists at all.
- Power — GothamBold 18, `RGB(0,160,60)`, y=206
- **BUY FOOD** — `0.44` width × 50px, `RGB(50,200,50)`, corner 12, at `(0.04,0),(1,-58)`
- **BUY MAX** — `0.44` × 50px, `RGB(255,140,0)`, corner 12, at `(0.52,0),(1,-58)`
- Locked overlay — full-cover `RGB(240,240,240)` frame, 🔒 at 64px, "Fly here to unlock!" GothamBold 20 red

**Right "ALL FOODS" grid** — fills the rest, `RGB(248,248,248)`, corner 12. Header label GothamBold 18. `ScrollingFrame`, bar thickness 6, `AutomaticCanvasSize = Y`. `UIGridLayout` CellSize `155×70`, padding `6×6`.
Each cell: `RGB(200,240,200)` bg, corner 8, stroke `RGB(150,200,150)` @2px; 55×55 emoji frame pinned left, name GothamBold 13 at x=60, 14×14 coin icon + price Gotham 12 `RGB(120,80,0)` below.

Note `:697-795` is a later restyle pass that overrides some of the above (left panel → `RGB(20,90,200)`, fonts → FredokaOne, buy buttons reparented and resized to 130×48). If you port, **pick one style** — the double-styling is why the file reads inconsistently.

`COIN_IMAGE = "rbxassetid://106760789458573"` (`:16`) — shared with the coin counter and daily rewards.

---

## What happens on use

**Client** (`Shop.client.luau:814-830`) — BUY FOOD fires `_G.BuyFoodEvent:FireServer(f.name)`, plays `rbxassetid://103794849233173` at volume 0.8, floats a `+N power!` label.

**BUY MAX** (`:832-876`) — greedily fills from the featured island's food downward, largest power first, capped by *both* remaining stomach space and coins.

**Server** (`Shop.server.luau:116-176`) is the authority. Check order is deliberate:
1. Food exists in the server's own list → else silently return
2. **Coins first** — the common blocker → `"not_enough_coins"`
3. Then fit: if `remaining <= 0` → `"stomach_full"`, else → `"not_enough_room"` (has room, this food is too big). Two distinct messages for two distinct player situations.

Then: deduct price, add `food.power` to `CurrentPower`, bump `TotalFartPower`/`TotalCoinsEarned`, fire `RegenEvent` to the client, and grant pet XP via `_G.petOnGas(player, powerGain)`.

The 2x pass multiplies **both** food power and effective tank size by `POWER_PASS_MULT = 1.4` (`:84`) — so despite being sold as "2x", the multiplier is 1.4. Worth deciding intentionally rather than inheriting.

**BuyStomach** (`:181-226`) validates the exact `(maxPower, cost)` pair against a non-Robux tier, then carries the current fill over — only the max grows, `CurrentPower` is not reset.

**Starting leaderstats** (`:99-109`): `Coins=25`, `CurrentPower=0`, `StomachMax=100`, `TotalFartPower=0`, `TotalCoinsEarned=0`, `Island=1`.

---

## The data

**Foods** (`Shop.server.luau:50-68`) — one per island, price / power:

| Island | Food | Price | Power |
|--:|---|--:|--:|
| 1 | Eggs | 5 | 8 |
| 2 | Lettuce | 24 | 25 |
| 3 | Bananas | 85 | 45 |
| 4 | Fish | 94 | 70 |
| 5 | Ribs | 142 | 100 |
| 6 | Mushrooms | 138 | 140 |
| 7 | Apples | 202 | 185 |
| 8 | Chicken | 600 | 240 |
| 9 | Chili Peppers | 500 | 300 |
| 10 | Potatoes | 400 | 370 |
| 11 | Steak | 560 | 450 |
| 12 | Grapes | 405 | 540 |
| 13 | Popcorn | 700 | 640 |

Turkey Legs (island 14, 518/750) was retired — it was a **dominated option in reverse**: cheaper than Popcorn but stronger, so it strictly beat the food below it. Worth checking your candy list for the same trap; note islands 6, 10 and 12 are already cheaper than the food above them.

**Stomach tiers** (`:70-78`), `getMaxHeight(maxPower) = 50 + maxPower*14`:

| Tier | maxPower | Cost |
|---|--:|---|
| Hatchling Belly | 100 | free |
| Raptor Gut | 182 | 1,600 |
| Stego Stomach | 520 | 3,000 |
| Bronto Belly | 1,075 | 5,200 |
| Rex Gut | 2,146 | 8,000 |
| Fossil Gut | 3,218 | 11,000 |
| Primal Gut | 9,999 | **499 Robux** |

**Consistency risk:** the food list is duplicated in `ShopGlue.client.luau:16-28` and `Shop.server.luau:50-68`, kept in sync only by a comment. The server validates against its own copy, so any drift makes a client-buyable food silently rejected. **Fix this in the port** — put the list in one `src/shared/CandyData.luau` ModuleScript and require it from both sides.

---

## Port plan for Candy Realm

1. **Rebuild the stall model in Studio** (can't come from the repo). Name it `Stand<N>` or drop it under `island<N>`. Candy-cane posts, gumdrop roof, lollipop signage.
2. **Copy `AnchorIslands.server.luau:109-120`** — anchor the stand + descendants.
3. **Copy `ShopGlue.client.luau:60-221` wholesale** — island resolution, gather, coverage report, proximity loop. Change `ISLAND_NAMES` and the 1–13 bounds to your realm's.
4. **Put foods + tiers in `src/shared/CandyData.luau`**, require from both server and client. Do not duplicate.
5. **Copy the UI builder** (`Shop.client.luau:70-143`) and recolor — swap the blue/green palette for candy: panel `RGB(255,240,248)`, header `RGB(232,110,170)`, stroke `RGB(214,92,158)`, cells `RGB(255,220,235)` with `RGB(240,170,200)` stroke, BUY button `RGB(255,105,180)`. Skip the `:697-795` restyle pass entirely and style once.
6. **Copy the server handlers** (`:116-226`) verbatim — the failure-message logic is well-worked-out and worth keeping exactly.
7. **Don't port** `Shop.client.luau:940-1012` (the dead second proximity system) or the `StandsReadyEvent` plumbing.
8. **Decide on `POWER_PASS_MULT`** — 1.4 while the pass is marketed as 2x.
