# MORE+ bundle → a new realm: read this before you start

Hand this to the assistant together with `FartToFloat_MorePlus_Bundle.zip`.

**Provenance, so you know what to trust:** everything in §2 is from the bundle's own
`README.md` and `docs/MORE_MENU_REFERENCE.md` — verified, not guessed. Everything in §3 is
from actually porting other Fart to Float systems (shop, economy, island layout, HUD) into a
different realm; those are the mistakes that cost real round-trips. Nothing here is invented.

---

## 1. THE JOB

Replace the contents of the MORE+ button's panel with the bundle's version: a centred
**700 × 520** dashboard with 7 cards, replacing whatever pop-out is there now.

**Do not blind-copy the whole bundle.** It ships `PlayerStats.server.lua` (151KB) and
`PetSystem.server.lua` (169KB) which own leaderstats, coins, DataStore saves, island
placement and food/gut buying. If the target realm already has those systems, dropping
these in gives you two scripts fighting over the same leaderstats. Port the **menu**; write
thin adapters for everything it calls.

---

## 2. TRAPS DOCUMENTED IN THE BUNDLE ITSELF

### 2.1 The bundle assumes `ReplicatedStorage/Shared`

11 ModuleScripts go to `ReplicatedStorage/Shared`. **Check the target's `default.project.json`
first.** If its shared folder is named something else, every `require` needs repointing.

> A `WaitForChild("Shared")` on a folder that doesn't exist **hangs forever without erroring**.
> The script simply never runs and prints nothing. This is the single most confusing failure
> mode in Roblox — you'll be looking for an error that never appears.

### 2.2 `CoreClient.client.lua` is at ~187 of Luau's 200-local ceiling

Adding one more top-level `local` makes the **entire script fail to compile — silently** —
taking every HUD element with it. That's why several things live on `_G` or inside `do`
blocks. Preserve that. If you need a new value, hang it on an existing table.

### 2.3 `MoreMenuGui` needs its `NoTextSweep` attribute

`repositionGUIs` force-sets `TextScaled = true` on *every* TextLabel under PlayerGui. The
dashboard is precise type — 21px titles beside 13px descriptions — so without the opt-out
every label rescales to fill its frame and the hierarchy collapses. This already destroyed
the Pet Hub's text once.

```lua
moreGui:SetAttribute("NoTextSweep", true)
```

### 2.4 Never sweep PlayerGui broadly

Blanket "destroy anything invisible" passes are what produced a black bar over the HUD. Other
menus legitimately park hidden frames. Evict stale duplicates **by name** only.

### 2.5 The rail variable names are deliberately wrong

MORE+ lives in `stomachSideFrame`; Stomach lives in `dailySideFrame`. Kept through two swaps
so the reposition/restyle/label passes keep targeting the right slot. **Renaming means finding
every one of those passes.** Leave them.

### 2.6 `repositionGUIs` overwrites the rail's authored sizes

Editing the `mkSideBtn` numbers alone does nothing. Final geometry is set by a pass that runs
at load, on every `ViewportSize` change, on `CharacterAdded`, and again at +3s. Desktop Y grid
is literally `{96, 203, 310, 417}`; phone raises the whole rail 96 → 66 to clear the joystick.

### 2.7 MORE+ is excluded from the restyle pass on purpose

It keeps `225,70,170`, corner 14, white stroke 2. If the target realm restyles its rail, MORE+
must be added explicitly or it won't match the other three buttons.

### 2.8 `FULL_Y = 342` is hardcoded

The 668×424 content box fits exactly 6 half-width cards + 1 full-width band. **Adding a 7th
half-width card makes the list scroll and requires moving `FULL_Y`.** Only one entry may have
`full = true`.

### 2.9 Menus close on the X button only

Never on a backdrop tap. A stray screen tap must not shut a panel.

### 2.10 Test flags ship ON

In `PlayerStats.server.lua`: `DISABLE_SAVE_FOR_TESTING`, `FORCE_NO_2X`, `FORCE_BASE_STOMACH`,
`FRESH_PLAYER_TEST`, `TEST_FULL_DATA`, `TEST_UNLOCK_ALL_DINOS`, `STUDIO_ALWAYS_SHOW`. Nothing
persists and every player reads as owning nothing until these are off.

### 2.11 Monetisation IDs point at the source experience

Gamepasses `TwoXForever` 1862015450, `GlitterTrail` 1859714979, `InfiniteGut` 1860686821.
Products `TwoXOneHour` 3600302990, `MidAirRecharge` 3600303163, `SkipIsland` 3600303265,
`BirdNuke` 3600303082. **These will not work in another experience.** Replace or the buttons
prompt for the wrong thing.

### 2.12 The source place has stale duplicates

The bundle's README reports the live place running an **older CoreClient** (5 rows instead of
7), plus **19 duplicate LocalScripts** and 8 duplicate ScreenGui names. If the target place has
anything similar, Rojo will appear not to sync. Check for a second copy baked into the place
before debugging code that is actually correct.

### 2.13 The 12 globals the menu calls

Every action is guarded (`if _G.x then _G.x() end`), so a missing panel makes the row a
**silent no-op** rather than an error — which means a half-ported menu looks fine and does
nothing. Wire or stub all of them:

`_G.toggleRebirth`, `_G.toggleDailyTasks`, `_G.dailyTasksAvailable`, `_G.dailyTasksPending`,
`_G.crateIsClaimable`, `_G.toggleSkinCrates`, `_G.toggleSocialRewards`, `_G.toggleSeasonPass`,
`PlayerGui.PetInvToggle` (BindableEvent), `openLocker` (local to CoreClient),
`_G.hudTextSweepSkip`, `_G.COIN_IMAGE` / `_G.GUT_IMAGE`.

**Daily Rewards branches** — a brand-new player has no task list, so the panel refuses to open
and the reward becomes unreachable. Keep the fallback that fires `OpenMeteorCrate` directly.

---

## 3. WHAT ACTUALLY COST TIME PORTING FtF SYSTEMS ELSEWHERE

These are realm-integration mistakes, not bundle bugs. They generalise.

### 3.1 Island MODEL number ≠ island CLIMB position

**The single most expensive assumption.** In the realm I ported into, the tower is deliberately
reordered so quest and blank islands alternate: `SLOT_TO_ISLAND = {1,9,2,12,3,13,4,5,10,7,6,8,11}`.
The second island you actually climb to is `island9`. `island5` sits eighth.

Every table keyed by island number is a landmine. Concretely, this broke:

- **Food unlocks** — gating on "highest island number reached" unlocked islands 2–9 all at once
  the moment the player reached the second island.
- **Every food lookup** — `foods[island]` silently returned the wrong food once the array was
  reordered, so every shop featured someone else's item.
- **A "buy max" loop** that iterated `for i = feat.island, 1, -1` over an array indexed by slot.
- **A ported waypoint arrow** whose name-reveal gate compared a model number against a
  progress counter, leaking six island names at once.

**Rule:** ask the target realm whether climb order equals model order. If not, gate on a
*slot/climb* value and look tables up by an explicit `island` field, never by array index.

### 3.2 Client and server both hold the same table

The shop kept its food/price table in **both** `Shop.server.luau` and `ShopGlue.client.luau`
with a comment saying "MUST match". Change one and purchases silently fail: the client offers
an item the server rejects. After any economy edit, diff the two programmatically — don't eyeball.

### 3.3 Remotes declared but never wired at one end

`CoinEvent` existed in ReplicatedStorage, was referenced on the server, and **nothing ever fired
it and nothing handled it**. Flying paid zero coins. It looked wired because the remote was there.

**Check both ends of every remote the bundle expects.** Existence proves nothing.

### 3.4 Remotes fired into the void

`StomachFullEvent` was fired by the server with a reason on every rejected purchase, and **no
client listened**. Refused buys did nothing visible and read as a broken button. Grep for a
listener for each remote the bundle fires.

### 3.5 Client-side gates with no server enforcement

The shop greyed out locked foods and the server never checked. Cosmetic only. Any gate the
bundle draws must also be enforced server-side or it is decoration.

### 3.6 `ProcessReceipt` is single-owner

Only **one** script may own `MarketplaceService.ProcessReceipt`. The bundle's services assume
they can handle their own product purchases. If the target realm already has a receipt handler,
you must hand off to the bundle's product IDs from inside the existing one — otherwise purchases
charge Robux and grant nothing.

### 3.7 Check the Rojo map before assuming any path

`default.project.json` may map whole folders wholesale (`src/server` → `ServerScriptService`),
in which case new files are picked up with no manifest edit — or it may not. Read it first.

### 3.8 Streaming: models replicate, parts don't

A distant island's **model** replicates at join; its **parts** arrive only when the player is
near. `GetPivot()` still works (the pivot replicates), but anything reading **size or bounding
box** gets garbage from an empty model. The realm's quest scripts explicitly wait and log
*"island4 has not streamed in yet (0 parts on this client)"*. If a bundle panel measures a world
object, it must wait for parts.

> I wasted a cycle "fixing" a working arrow on a wrong streaming theory. Verify the failure before
> theorising about it — ask for the actual output first.

### 3.9 Islands are named differently

The bundle expects `Island_1_BeanFarm` … `Island_14_PizzaPalms` and **14** islands. The realm I
worked in uses `island1` … `island13` and **13**. Anything iterating `1..14` or matching by full
name needs adjusting, and the 14th food/island must be handled as absent.

### 3.10 PowerShell writes a BOM

`Set-Content`/`Out-File` on Windows PowerShell 5.1 default to UTF-8 **with BOM** or the system
ANSI codepage. Pass `-Encoding utf8` deliberately, and prefer the assistant's own file tools.
Reading a UTF-8 file with `Get-Content` and writing it back **mangles every non-ASCII character**
— which is how emoji in a UI table turn into `Â·` garbage.

---

## 4. VERIFY BEFORE REPORTING DONE

1. `[MORE]`-ish startup print appears — if not, the script isn't in the place or is stuck on a
   `WaitForChild` for a folder that doesn't exist.
2. All 7 cards render, and **each one opens something**. A guarded no-op looks identical to a
   working row until you click it. Click all 7.
3. The panel is 700×520 and centred, matching the realm's other menus.
4. Titles are 21px and descriptions 13px — if they're all the same size, `NoTextSweep` is missing.
5. Both badge dots can show at once, side by side.
6. Test on a **phone viewport**, not just desktop: the rail moves up 30px and the pitch tightens.
7. Buy something through a bundle panel and confirm the server actually granted it — not just
   that the UI animated.
8. Rejoin and confirm it persisted (needs Studio API Access enabled *and* the save flags off).

---

## 5. TELL ME, DON'T GUESS

If the target realm turns out to differ on any of these, say so and ask rather than adapting
silently:

- Climb order vs model order (§3.1) — changes the gating logic everywhere.
- Whether it already owns leaderstats/coins/pets — changes port vs adapter.
- Whether it already owns `ProcessReceipt` — changes how purchases are wired.
- Island count and naming.

State which of §2 and §3 actually applied, and which didn't. A short "N/A because X" is more
useful than silence.
