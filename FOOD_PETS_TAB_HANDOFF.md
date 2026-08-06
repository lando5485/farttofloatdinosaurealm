# Food Realm pets in the Pet Hub — port handoff (Dino Realm → Space Realm)

How the Dino Realm shows the **Food Realm's** pet collection inside its own Pet Hub: a second
`🍔 PETS` tab listing all 11 food-realm species, each rendered as the **exact** fused model the
food realm builds, owned ones showing age/level/XP and locked ones showing
"Return to the Food Realm to complete".

Source of truth for the data itself: `FoodRealmPets_Data.md`.
Source of truth for the locked-card look: `LockedPetCard_Look.md`.

---

## 1. The three pieces

| # | Piece | Dino Realm file | Space Realm status |
|---|---|---|---|
| 1 | **Publish the models** — build the food pets' fused templates into ReplicatedStorage | `src/server/FoodPetTemplates.server.luau` | ✅ **already done** — this file IS Space Realm's `PetTemplates.server.luau`, copied over |
| 2 | **Feed the client the pet table** — a RemoteEvent carrying `{petId → {level, xp, count, rare}}` | `src/server/ArrivalReceiver.server.luau` (`FoodPetsEvent`) | ⚠️ **needs a different source** — see §3 |
| 3 | **The tab + cards** — catalog, card builders, grid, tab-bar entry | `src/client/PetHub.client.luau` + `src/client/PetHubTabs.client.luau` | ⬜ port as-is |

**Piece 1 is why the renders are exact.** `UnionAsync` is server-only, so the bodies have to be
fused on the server and replicated. The client never rebuilds a pet — it clones the published
template. That's the same single-source-of-truth pattern the Dino Realm already used for its own
`StegosaurusTemplate` / `VelociraptorTemplate` / etc.

> **Space Realm already runs this exact file.** `src/server/PetTemplates.server.luau` there
> publishes `BeanBuddyTemplate`, `PizzaDragonTemplate`, `BroccoliBunnyTemplate`,
> `CoconutCrabTemplate`, `PopcornSheepTemplate`, `ButterDuckTemplate`,
> `BurritoArmadilloTemplate`, `SunflowerBeeTemplate`, `MapleFoxTemplate`,
> `FrostPenguinTemplate`, `BlossomBunnyTemplate` (+ the 3 rebirth recolours). **Do not copy
> `FoodPetTemplates.server.luau` into Space Realm — you'd get duplicate models fighting over the
> same names.** Skip straight to §2.

---

## 2. Client: the icon builders (exact renders)

Add after the existing `PET_ICON_BUILDER` table in the Pet Hub client. This is the whole trick —
every food pet resolves to a **clone of the published template**, not a hand-built approximation.

```lua
-- FOOD REALM pet icons -- clone the EXACT fused templates the food realm builds.
-- Same single-source-of-truth pattern as the realm's own pet icons, so the tab shows
-- the real renders. Falls back to a legacy handmade builder where one exists, else an
-- empty placeholder (the viewport keeps its emoji).
local function foodTemplateIcon(templateName, fallbackBuilder)
	return function(scale)
		local t = RS:FindFirstChild(templateName) or RS:WaitForChild(templateName, 20)
		if t then
			local c = t:Clone(); petAnims[c] = nil
			return c
		end
		warn("[PetHub] " .. templateName .. " missing -> fallback icon")
		if fallbackBuilder then return fallbackBuilder(scale) end
		local ph = Instance.new("Model"); ph.Name = templateName
		local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4)
		r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph
		ph.PrimaryPart = r
		return ph
	end
end
PET_ICON_BUILDER.BeanBuddy        = foodTemplateIcon("BeanBuddyTemplate")
PET_ICON_BUILDER.PizzaDragon      = foodTemplateIcon("PizzaDragonTemplate")
PET_ICON_BUILDER.BroccoliPet      = foodTemplateIcon("BroccoliBunnyTemplate")  -- NOTE: petId ≠ template name
PET_ICON_BUILDER.CoconutCrab      = foodTemplateIcon("CoconutCrabTemplate")
PET_ICON_BUILDER.PopcornSheep     = foodTemplateIcon("PopcornSheepTemplate")
PET_ICON_BUILDER.ButterDuck       = foodTemplateIcon("ButterDuckTemplate")
PET_ICON_BUILDER.BurritoArmadillo = foodTemplateIcon("BurritoArmadilloTemplate")
PET_ICON_BUILDER.SunflowerBee     = foodTemplateIcon("SunflowerBeeTemplate")
PET_ICON_BUILDER.MapleFox         = foodTemplateIcon("MapleFoxTemplate")
PET_ICON_BUILDER.FrostPenguin     = foodTemplateIcon("FrostPenguinTemplate")
PET_ICON_BUILDER.BlossomBunny     = foodTemplateIcon("BlossomBunnyTemplate")
```

> ⚠️ **`BroccoliPet` → `BroccoliBunnyTemplate`.** The pet's id and its template name disagree in
> the source game (id `BroccoliPet`, display name "Broccoli Bunny", template named after the
> display name). Every other pet matches. Getting this wrong = one silently-empty card.

`petAnims[c] = nil` matters: the builder table's other entries register into `petAnims` for the
follower animator, and a cloned template must not.

---

## 3. Server: feeding the pet table to the client

**This is the piece that differs between realms**, because the two realms get the data from
different places.

### 3a. What Dino Realm does (arrival souvenir — read-only)

Dino Realm has no food pets of its own; it only has whatever the teleport carried in. Its
`ArrivalReceiver.server.luau` already parks that table in `_G.arrivedSpacePets[player]`
(deliberately kept **out** of live pet state, since the catalogs don't overlap). The tab just
mirrors it:

```lua
local FoodPetsEvent = RS:FindFirstChild("FoodPetsEvent")
if not FoodPetsEvent then
	FoodPetsEvent = Instance.new("RemoteEvent"); FoodPetsEvent.Name = "FoodPetsEvent"; FoodPetsEvent.Parent = RS
end
local function sendFoodPets(player)
	pcall(function() FoodPetsEvent:FireClient(player, _G.arrivedSpacePets[player] or {}) end)
end
FoodPetsEvent.OnServerEvent:Connect(sendFoodPets)   -- client asks on load
-- ...and push once at intake, right after _G.arrivedSpacePets[player] is filled:
sendFoodPets(player)
```

Both directions exist on purpose — whichever of the two scripts loads second still gets a payload.

### 3b. What Space Realm should do instead

**Space Realm owns these pets for real.** It runs the same catalog, `_G.playerOwnedPets[player]`
is already keyed by `BeanBuddy` / `ButterDuck` / `ButterDuck#R` / …, and `SpacePetFollower`
already spawns them. So don't read arrival data — read the live table, and push again whenever
it changes:

```lua
-- FoodPetsFeed.server.luau  (ServerScriptService)
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local FoodPetsEvent = RS:FindFirstChild("FoodPetsEvent")
if not FoodPetsEvent then
	FoodPetsEvent = Instance.new("RemoteEvent"); FoodPetsEvent.Name = "FoodPetsEvent"; FoodPetsEvent.Parent = RS
end

local function send(player)
	if not (player and player.Parent) then return end
	pcall(function()
		FoodPetsEvent:FireClient(player, (_G.playerOwnedPets and _G.playerOwnedPets[player]) or {})
	end)
end

FoodPetsEvent.OnServerEvent:Connect(send)                 -- client handshake on load
Players.PlayerAdded:Connect(function(p) task.delay(2.5, send, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(send, p) end

-- Re-push after anything that mutates ownership/level (hatch, level-up, crate, trade).
-- Cheapest wiring: call this from wherever the Space Realm already calls its own
-- sendInventory()/PetInventoryEvent refresh.
_G.sendFoodPetsToClient = send
```

> **If Space Realm's own hub already sends a `PetInventoryEvent` in this exact shape, skip the
> remote entirely** and point the tab's listener at that instead — see §7.

**Payload shape** (per `FoodRealmPets_Data.md` §8) — keys are *storage keys*: `petId` for a
normal, `petId .. "#R"` for the rare variant; both can exist at once and each renders its own
card. Each value: `{ level, xp, height, time, rare, count }`. Only `level`, `xp` and `count` are
read by the cards.

---

## 4. Client: catalog + the food realm's level vocabulary

```lua
-- The 10 main collection pets + the Pizza Dragon secret. Rebirth pets (Molten Bean /
-- Void Dragon / Prism Fox) are recolour clones and deliberately left out -- add them
-- here if the realm wants them shown.
local FOOD_CATALOG = {
	{ key = "BeanBuddy",        displayName = "Bean Buddy",        where = "Bean Farm",                        emoji = "\xF0\x9F\x8C\xB1" },
	{ key = "BroccoliPet",      displayName = "Broccoli Bunny",    where = "Broccoli Bluff",                   emoji = "\xF0\x9F\xA5\xA6" },
	{ key = "CoconutCrab",      displayName = "Coconut Crab",      where = "Coconut Cove",                     emoji = "\xF0\x9F\xA6\x80" },
	{ key = "PopcornSheep",     displayName = "Popcorn Sheep",     where = "Popcorn Pinnacle",                 emoji = "\xF0\x9F\x8D\xBF" },
	{ key = "ButterDuck",       displayName = "Butter Duck",       where = "Butter Swamp",                     emoji = "\xF0\x9F\xA6\x86" },
	{ key = "BurritoArmadillo", displayName = "Burrito Armadillo", where = "Burrito Barrens",                  emoji = "\xF0\x9F\x8C\xAF" },
	{ key = "SunflowerBee",     displayName = "Sunflower Bee",     where = "Community Garden \xC2\xB7 Summer", emoji = "\xF0\x9F\x8C\xBB" },
	{ key = "MapleFox",         displayName = "Maple Fox",         where = "Community Garden \xC2\xB7 Autumn", emoji = "\xF0\x9F\x8D\x81" },
	{ key = "FrostPenguin",     displayName = "Frost Penguin",     where = "Community Garden \xC2\xB7 Winter", emoji = "\xF0\x9F\x90\xA7" },
	{ key = "BlossomBunny",     displayName = "Blossom Bunny",     where = "Community Garden \xC2\xB7 Spring", emoji = "\xF0\x9F\x8C\xB8" },
	{ key = "PizzaDragon",      displayName = "Pizza Dragon",      where = "Secret Pet",                       emoji = "\xF0\x9F\x8D\x95", secret = true },
}
local FOOD_RARE_NAMES = { BroccoliPet = "Emerald Bunny", CoconutCrab = "Golden Crab",
	PopcornSheep = "Cloud Sheep", BurritoArmadillo = "Crystal Armadillo", ButterDuck = "Cosmic Duck" }

-- Food realm levels display as AGE words, never rarity words (rarity vocabulary belongs
-- to skin crates over there). Rares override the age entirely -- Exotic cyan; ButterDuck's
-- rare is the 1-in-10,000 Mythical magenta.
local function foodAge(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230)
		else return "Exotic", Color3.fromRGB(40,235,225) end
	end
	if level <= 5      then return "Baby",  Color3.fromRGB(175,180,190)
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90,210,90)
	elseif level <= 15 then return "Teen",  Color3.fromRGB(70,140,255)
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235)
	else                    return "Elder", Color3.fromRGB(255,170,40) end
end
local function foodXpNeeded(level) -- the food realm's exact curve: floor(80 * L^1.6)
	if level >= 25 then return 0 end
	return math.floor(80 * level ^ 1.6)
end
```

The emoji is **not** the card art — it's only the viewport placeholder shown for the frame or two
before the template clone lands.

---

## 5. Client: the page

Build it through **the same section helper as the main pets page**, pinned to the same band, so
it's identical furniture and only the cards differ:

```lua
local foodOverlay, foodScroll = makeSection(12, 676, "\xF0\x9F\x8D\x94 PETS")
foodOverlay.Name = "FoodOverlay"                        -- the tab router's fallback finds it by name
foodOverlay.Size = UDim2.new(1, -24, 1, -74)            -- ← copy these two from your own pets section,
foodOverlay.Position = UDim2.new(0, 12, 0, 68)          --   whatever they are in this realm
foodOverlay.Visible = false
local foTitle = foodOverlay:FindFirstChildOfClass("TextLabel")
local foodGrid = Instance.new("UIGridLayout")
foodGrid.CellSize = UDim2.new(0,322,0,252); foodGrid.CellPadding = UDim2.new(0,10,0,12)
foodGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; foodGrid.Parent = foodScroll
do
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = foodScroll
end
```

### ⚠️ The one real gotcha: **swap pages, never stack them**

Section frames built by `makeSection` are **translucent**. If you show the food page while the
main pets grid is still visible underneath, the pets grid **bleeds through the food grid's empty
cells** — with 11 cards the last row's right-hand cell is a window straight onto the other grid's
last card. It reads as a phantom extra pet.

So every page-switch entry point must hide the other section:

```lua
_G.PetHubShowPets = function()
	foodOverlay.Visible = false
	petsSection.Visible = true            -- ← restore
	title.Text = "PETS"; subtitle.Text = subtitleDino
end
_G.PetHubShowFood = function()
	petsSection.Visible = false           -- ← swap, never stack
	foodOverlay.Visible = true
	title.Text = "PETS"; subtitle.Text = subtitleFood
end
```

…and `openPanel(open)` must restore `petsSection.Visible = true` on **both** open and close,
otherwise closing the hub while on the food tab reopens it with no grid at all. Opaque overlays
(quests/trade) don't have this problem, which is why only this page needed it.

---

## 6. Client: the cards

Two builders, both 322×252 to match the grid. Full source is in
`src/client/PetHub.client.luau` — search `buildFoodOwnedCard` / `buildFoodLockedCard`. The
shapes:

**Owned** — blue card `RGB(20,70,160)` (rares dark purple `RGB(46,28,86)` + a coloured stroke and
an Exotic/Mythical corner tag), spinning 3D model 310×140 at top, name (rare name if rare),
`"<Age>  Lv N"` in the age colour, XP bar on the `80·L^1.6` curve (gold `MAX` at 25), an orange
`xN` chip for stacked duplicates, then — **in place of the EQUIP/SKIP row** — a pointer home,
then the `where` line.

**Locked** — the `LockedPetCard_Look.md` spec exactly: **same blue card, pet in FULL COLOUR,
never greyed**, 28×28 padlock badge at `Position (1,-12,0,12)` anchored `(1,0)` over the
picture's top-right, gold `RGB(255,190,60)` thickness-2 border, gold `"🔒 LOCKED • <where>"`
line, a `"Food Realm · Pet N of 11"` progress line, the how-to text, and a gold-brown
`RGB(150,110,30)` button.

**The "task" copy is the deliberate cross-realm bit** — every locked card points back rather than
describing a quest this realm can't run:

```lua
how.Text = entry.secret and "Return to the Food Realm and collect all 10 pets to unlock this secret pet"
	or "Return to the Food Realm to complete this pet's quest"
more.Text = "\xF0\x9F\x94\x92 RETURN TO FOOD REALM TO COMPLETE"
```

> **Decision point for Space Realm.** Space Realm *can* equip and level these pets (it has the
> catalog and `SpacePetFollower`). If you want the tab live rather than read-only, swap the
> "EQUIP & LEVEL IN THE FOOD REALM" button for a real EQUIP button firing your `PetEquipEvent`
> with the storage key, and change the locked copy to the actual quest text. Everything else —
> icons, ages, XP curve, rares, layout — stays as-is.

---

## 7. Client: the rebuild + wiring

```lua
local latestFoodPets = {}
local function rebuildFoodPets(pets)
	local ok, err = pcall(function()
		if type(pets) == "table" then latestFoodPets = pets end
		-- drop queued icon builds for cards we're about to destroy
		for i = #iconQueue, 1, -1 do
			local q = iconQueue[i]
			if q.vp and (not q.vp.Parent or q.vp:IsDescendantOf(foodScroll)) then table.remove(iconQueue, i) end
		end
		for _, c in ipairs(foodScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end

		-- split normal vs "#R" rare -- both can be owned, each gets its own card
		local ownedNormal, ownedRare = {}, {}
		for skey, v in pairs(latestFoodPets) do
			if type(skey) == "string" and type(v) == "table" then
				if skey:sub(-2) == "#R" then ownedRare[skey:sub(1, -3)] = v else ownedNormal[skey] = v end
			end
		end

		local order, cards, ownedSpecies = 0, 0, 0
		for i, entry in ipairs(FOOD_CATALOG) do
			local n, r = ownedNormal[entry.key], ownedRare[entry.key]
			if n or r then ownedSpecies = ownedSpecies + 1 end   -- a species counts ONCE
			if r then order += 1; cards += 1; pcall(buildFoodOwnedCard, entry, r, true, order) end
			if n then order += 1; cards += 1; pcall(buildFoodOwnedCard, entry, n, false, order) end
			if not n and not r then order += 1; cards += 1; pcall(buildFoodLockedCard, entry, order, i) end
		end
		foodScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(cards / 2) * 264 + 20)
		if foTitle then foTitle.Text = ("\xF0\x9F\x8D\x94 PETS   %d / %d"):format(ownedSpecies, #FOOD_CATALOG) end
	end)
	if not ok then warn("[PetInv] ERROR building food pets: " .. tostring(err)) end
end

rebuildFoodPets({})   -- paint the full LOCKED catalog immediately; live data overwrites it
task.spawn(function()
	local ev = RS:FindFirstChild("FoodPetsEvent") or RS:WaitForChild("FoodPetsEvent", 20)
	if not ev then return end                       -- no server half -> the locked catalog stands
	ev.OnClientEvent:Connect(rebuildFoodPets)
	pcall(function() ev:FireServer() end)           -- request, in case the server pushed before we loaded
end)
```

Painting the locked catalog **before** any data arrives is deliberate: the panel is never blank,
and a player who never carried anything across still sees the full "go earn these" grid.

---

## 8. The tab

In the hub's tab-bar config, add the entry and re-solve the button width:

```lua
TABS = {
	{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS"   },   -- 🐾 this realm
	{ id = "food",   label = "\xF0\x9F\x8D\x94 PETS"   },   -- 🍔 Food Realm -- the emoji tells them apart
	{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" },
	-- ...
},
-- 6 x 106 + 5 x 8 padding = 676 -> fills a 676-wide panel body exactly.
-- Re-solve if you add/remove a tab:  BTN_W = (panelWidth - 20 - PADDING*(n-1)) / n
BTN_W = 106,
```

and route it in the page-shower:

```lua
local hubShow = ({ pets = _G.PetHubShowPets, food = _G.PetHubShowFood,
                   quests = _G.PetHubShowQuests, trade = _G.PetHubShowTrade })[id]
```

Both pet tabs are **named PETS on purpose** — it's the same menu the player knows from the other
realm; the emoji and the header subtitle say which collection they're looking at.

---

## 9. Performance: you're adding 11 more spinning ViewportFrames

This doubled the icon count and needed the spinner rewritten. Port this too — it's in the same
file, search `THE SPINNER`:

1. **Orbit the camera, not the model.** `model:PivotTo()` rewrites the CFrame of *every part* —
   28 for Blossom Bunny, 53 for a raptor. Rotating the camera around a stationary model is **one**
   CFrame write per icon and looks identical:
   ```lua
   angle = (angle - dt * 0.6) % (2*math.pi)   -- NEGATIVE: orbiting one way turns the pet the other
   local rot = CFrame.Angles(0, angle, 0)
   -- per icon, where `offset` is the camera's rest offset captured at build time:
   ic.cam.CFrame = CFrame.lookAt(ic.center + rot * ic.offset, ic.center)
   ```
2. **Skip icons whose page isn't up.** Record each icon's ancestor chain at build time and check
   it before doing work. Check the **whole chain**, not just the parent — an inner view can stay
   `Visible` while only the overlay above it flips.
3. **Cull scrolled-off cards with `vp.Visible = false`.** Each ViewportFrame is its own render
   pass, so an off-screen card is real GPU work. This is the biggest win of the three.

Net: cost scales with what's on screen (2–4 icons) instead of with what exists (17).

---

## 10. Port checklist

- [ ] **Skip piece 1** — Space Realm already publishes the templates. Confirm with the
      `[SpaceRealm PetTemplates] … built (N parts) -> XTemplate` output lines.
- [ ] Add `FoodPetsFeed.server.luau` (§3b) — or point the tab at the existing inventory remote.
- [ ] Add `foodTemplateIcon` + the 11 `PET_ICON_BUILDER` entries (§2). **Watch `BroccoliPet` →
      `BroccoliBunnyTemplate`.**
- [ ] Add `FOOD_CATALOG` / `FOOD_RARE_NAMES` / `foodAge` / `foodXpNeeded` (§4).
- [ ] Build the page with your realm's own `makeSection`, matching your pets section's
      Size/Position (§5).
- [ ] **Hide the other section on switch** — the stacking bug (§5).
- [ ] Port `buildFoodOwnedCard` / `buildFoodLockedCard` / `rebuildFoodPets` (§6–7).
- [ ] Add the tab + re-solve `BTN_W` (§8).
- [ ] Port the spinner rewrite (§9).
- [ ] Decide: read-only souvenir, or live equip (§6 decision point).

### Things that bit us

| Symptom | Cause |
|---|---|
| One card is an empty spinning nothing | `BroccoliPet` pointed at `BroccoliPetTemplate`; it's `BroccoliBunnyTemplate` |
| A phantom pet in the bottom-right empty cell | Translucent section stacked over the other grid — §5 |
| Hub reopens with no grid | `openPanel` didn't restore `petsSection.Visible` |
| Icons show as emoji forever | Templates never published — check the server build log |
| Frame stutter with the tab open | Spinner still doing `PivotTo` per part — §9 |
| Panel closes on a stray click | Unrelated, but fixed at the same time: full-screen backdrops whose press handler closed the panel. Keep the backdrop `Active` (so it swallows the click) but **don't** close on it |
