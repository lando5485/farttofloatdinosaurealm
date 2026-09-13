-- ============================================================================================================
-- /TESTPET -- developer-only visual inspection of EVERY skin and EVERY trait.  [REMOVE BEFORE LAUNCH]
-- ============================================================================================================
-- The tuning surface for the whole cosmetic system: type /testpet and a panel opens with two pages --
--
--   SKINS    every skin on the SELECTED pet, one preview each, NO trait. Switch pets along the top row to
--            walk the full "all skins x each pet" matrix one pet at a time.
--   TRAITS   every trait on the CLASSIC skin (the common baseline the spec names), again on the selected
--            pet -- so accessory placement can be checked against every body shape and fixed in
--            PetTraits.PET_OFFSETS, never by forking a trait.
--
-- WHAT THIS DELIBERATELY IS NOT: all skins x all traits x all pets. That cross product is thousands of
-- models and exactly the thing the spec forbids. One page is at most 21 previews (17 on Skins), built
-- lazily ONE PER FRAME behind placeholders, from ONE cached base model per pet cloned per cell -- and every
-- switch of pet or page destroys the previous page's models before building the next. Nothing here creates
-- inventory entries, touches the server, or persists anything: it is a lens, not a grant.
--
-- Dev-gated with the same allowlist DevCommands uses. For everyone else /testpet silently does nothing.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local PetSkins  = require(Shared:WaitForChild("PetSkins"))
local PetTraits = require(Shared:WaitForChild("PetTraits"))
local SkinCrates = require(Shared:WaitForChild("SkinCrates"))

-- [REMOVE BEFORE LAUNCH] same allowlist as DevCommands.server.luau -- keep the two in step.
local TEST_USER_IDS = { [1418148401] = true }
local TEST_USER_NAMES = {
	["lando5485"] = true, ["itsmaddmax1"] = true, ["itsmaddmax2"] = true, ["broskie310111"] = true,
}
local function isTestUser()
	return TEST_USER_IDS[player.UserId] == true or TEST_USER_NAMES[string.lower(player.Name)] == true
end

-- The species roster, derived from the crate contents (the same fallback DevUnlockAllSkins uses) so this
-- panel needs nothing from PetFollow beyond the model builder it already publishes.
local function speciesList()
	local seen, out = {}, {}
	for _, crate in ipairs(SkinCrates.CRATES) do
		for _, e in ipairs(SkinCrates.flatContents(crate.id)) do
			if e.pet and not seen[e.pet] then seen[e.pet] = true; out[#out + 1] = e.pet end
		end
	end
	table.sort(out)
	return out
end

-- ===== house UI helpers (same shapes as SkinCrateClient) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end
local function fit(o, maxSize)
	o.TextScaled = true
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
end

local PANEL      = Color3.fromRGB( 30, 120, 220)
local PANEL_DARK = Color3.fromRGB( 20,  60, 160)
local HEADER     = Color3.fromRGB( 15,  60, 140)
local CARD       = Color3.fromRGB( 20,  90, 200)
local GOLD       = Color3.fromRGB(255, 220,   0)
local RED        = Color3.fromRGB(255,  60,  60)
local WHITE      = Color3.new(1, 1, 1)

-- ===== THE PANEL =====
local gui = Instance.new("ScreenGui")
gui.Name = "TestPetPreviewGui"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.DisplayOrder = 210
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui:SetAttribute("NoTextSweep", true) -- keep CoreClient's TextScaled sweep off the authored sizes
gui.Parent = PlayerGui

local panel = mkFrame(gui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, Active = true, ClipsDescendants = true,
})
mkCorner(panel, 20); mkStroke(panel, PANEL_DARK, 3)

local header = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = HEADER })
mkCorner(header, 20)
local titleLbl = mkLabel(header, {
	Text = "\xF0\x9F\x94\xAC /TESTPET \xE2\x80\x94 SKIN & TRAIT INSPECTOR", Font = Enum.Font.FredokaOne,
	TextSize = 20, TextColor3 = GOLD, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 14, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})
fit(titleLbl, 20); mkStroke(titleLbl, Color3.new(0, 0, 0), 2)

-- X is the only way to close -- house rule: a stray screen tap must never shut a panel.
local closeBtn = mkButton(header, {
	Size = UDim2.new(0, 36, 0, 36), Position = UDim2.new(1, -44, 0, 6), BackgroundColor3 = RED,
	Text = "X", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHITE,
})
fit(closeBtn, 18); mkCorner(closeBtn, 8); mkStroke(closeBtn, Color3.fromRGB(150, 40, 32), 2)

-- CLEAR TRY-ON -- undoes the live preview and puts the real equip back on the follower. Sits in the header
-- so it is reachable from either page, and it works even after the panel was closed and reopened (the
-- try-on deliberately survives closing the panel: walking around wearing the preview is the whole point).
local clearBtn = mkButton(header, {
	Size = UDim2.new(0, 130, 0, 30), Position = UDim2.new(1, -184, 0, 9),
	BackgroundColor3 = Color3.fromRGB(120, 130, 145), Text = "CLEAR TRY-ON",
	Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = WHITE, Visible = false,
})
fit(clearBtn, 13); mkCorner(clearBtn, 8); mkStroke(clearBtn, Color3.fromRGB(70, 78, 92), 2)
clearBtn:SetAttribute("BTS_Skip", true)
clearBtn.MouseButton1Click:Connect(function()
	if _G.petSkinTryOn then pcall(_G.petSkinTryOn, nil) end
	clearBtn.Visible = false
	if _G.showHudBanner then pcall(_G.showHudBanner, "Try-on cleared -- back to your real skin", Color3.fromRGB(205, 224, 255), 3) end
end)

-- The TRY action every card's button routes through: paints the combo onto the live follower (and every
-- other pet this client renders) via PetSkinLook's try-on override. Preview only -- nothing is granted,
-- nothing is saved, and other players still see the real equip.
local function tryOnCombo(skinId, traitId, label)
	if not _G.petSkinTryOn then
		if _G.showHudBanner then pcall(_G.showHudBanner, "Renderer not ready yet -- try again in a second", Color3.fromRGB(255, 150, 90), 3) end
		return
	end
	local ok = false
	pcall(function() ok = _G.petSkinTryOn(skinId, traitId) end)
	if ok then
		clearBtn.Visible = true
		if _G.showHudBanner then
			pcall(_G.showHudBanner,
				"Trying on " .. tostring(label) .. " -- only YOU see it. Equip anything (or CLEAR TRY-ON) to remove",
				Color3.fromRGB(150, 255, 170), 4)
		end
	end
end

-- page tabs (SKINS / TRAITS)
local activePage = "skins"
local activePet -- set on open
local rebuild -- forward

local tabBar = mkFrame(panel, { Size = UDim2.new(0, 350, 0, 30), Position = UDim2.new(0, 10, 0, 54), BackgroundTransparency = 1 })
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 8); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = tabBar
end
local tabButtons = {}
for i, t in ipairs({ { id = "skins", label = "SKINS" }, { id = "traits", label = "TRAITS" },
	{ id = "combo", label = "COMBO" } }) do
	local b = mkButton(tabBar, {
		Size = UDim2.new(0, 110, 1, 0), LayoutOrder = i, BackgroundColor3 = CARD, Text = t.label,
		Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = GOLD,
	})
	fit(b, 14); mkCorner(b, 8); mkStroke(b, WHITE, 1.5)
	b:SetAttribute("BTS_Skip", true)
	tabButtons[t.id] = b
	b.MouseButton1Click:Connect(function() activePage = t.id; rebuild() end)
end

-- the page's one-line explainer, so whoever is testing knows exactly what they are looking at
local subLbl = mkLabel(panel, {
	Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Color3.fromRGB(205, 224, 255),
	Size = UDim2.new(1, -380, 0, 30), Position = UDim2.new(0, 370, 0, 54),
	TextXAlignment = Enum.TextXAlignment.Right,
})
fit(subLbl, 12)

-- ===== EQUIP PET (playtest the selected species) =====
-- Grants the full roster through DevCommands' test-only remote (idempotent, same _G.petsGrantAll as
-- /allpets), then equips the SELECTED pet through the ordinary PetEquipEvent path -- so the follower that
-- shows up is the production one, and TRY combos land on the species being inspected.
local DevTestPetAccess = ReplicatedStorage:WaitForChild("DevTestPetAccess", 15)
local PetEquipEvent = ReplicatedStorage:WaitForChild("PetEquipEvent", 15)
local equipBtn = mkButton(panel, {
	Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(1, -140, 0, 90),
	BackgroundColor3 = Color3.fromRGB(50, 220, 50), Text = "EQUIP PET",
	Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = WHITE,
})
fit(equipBtn, 14); mkCorner(equipBtn, 8); mkStroke(equipBtn, Color3.fromRGB(30, 130, 30), 2)
equipBtn:SetAttribute("BTS_Skip", true)
-- HANDSHAKE, NOT A TIMER: the first press asks the server for the roster grant and parks the equip; the
-- server fires back once ownership actually exists, and THEN the equip goes out -- so it can never race the
-- grant. Later presses skip straight to the equip.
local granted = false
local pendingEquip = nil
local function fireEquip(petId)
	print("[TestPet] equipping " .. tostring(petId) .. " via PetEquipEvent")
	PetEquipEvent:FireServer(petId)
	if _G.showHudBanner then
		pcall(_G.showHudBanner, "Equipped " .. PetSkins.prettyPet(petId) .. " -- go playtest it!",
			Color3.fromRGB(150, 255, 170), 3)
	end
end
if DevTestPetAccess then
	DevTestPetAccess.OnClientEvent:Connect(function()
		granted = true
		print("[TestPet] server confirmed the pet grant")
		if pendingEquip then
			local p = pendingEquip; pendingEquip = nil
			fireEquip(p)
		end
	end)
end
equipBtn.MouseButton1Click:Connect(function()
	if not activePet then return end
	print("[TestPet] EQUIP PET pressed for " .. tostring(activePet)
		.. " (granted=" .. tostring(granted) .. ", remotes=" .. tostring(DevTestPetAccess ~= nil) .. "/" .. tostring(PetEquipEvent ~= nil) .. ")")
	if not (DevTestPetAccess and PetEquipEvent) then
		if _G.showHudBanner then pcall(_G.showHudBanner, "Dev pet remotes missing -- is DevCommands running?", Color3.fromRGB(255, 150, 90), 3) end
		return
	end
	if granted then
		fireEquip(activePet)
	else
		pendingEquip = activePet
		DevTestPetAccess:FireServer()
		if _G.showHudBanner then pcall(_G.showHudBanner, "Unlocking all pets for testing...", Color3.fromRGB(205, 224, 255), 2) end
	end
end)

-- ===== ADJUST MODE: live per-pet fitting =====
-- TUNE (in the header) opens a nudge bar along the panel's bottom: pick an attach point, tap X/Y/Z to move
-- that anchor on the SELECTED pet in its own units, S to grow/shrink its gear, and watch the live follower
-- update instantly (equip the pet + TRY something first). PRINT dumps the finished numbers to the Output as
-- a paste-ready PetTraits.PET_OFFSETS entry -- fit each pet by eye, then make it permanent config.
local ADJ_ATTACHES = { "Head", "Face", "Neck", "Back", "Body" }
local adjIdx = 1
local adjBar = mkFrame(panel, {
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 1, -34),
	BackgroundColor3 = HEADER, Visible = false, ZIndex = 30,
})
mkCorner(adjBar, 8); mkStroke(adjBar, GOLD, 1)
local function adjButton(x, w, text, fn)
	local b = mkButton(adjBar, {
		Size = UDim2.new(0, w, 1, -6), Position = UDim2.new(0, x, 0, 3),
		BackgroundColor3 = CARD, Text = text, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = WHITE, ZIndex = 31,
	})
	fit(b, 12); mkCorner(b, 6); b:SetAttribute("BTS_Skip", true)
	b.MouseButton1Click:Connect(fn)
	return b
end
local attachBtn
attachBtn = adjButton(4, 84, "@ Head", function()
	adjIdx = adjIdx % #ADJ_ATTACHES + 1
	attachBtn.Text = "@ " .. ADJ_ATTACHES[adjIdx]
end)
local ADJ_STEP = 0.06
local function nudge(dx, dy, dz, ds)
	if not (activePet and _G.petSkinAdjust) then return end
	_G.petSkinAdjust(activePet, ADJ_ATTACHES[adjIdx], dx, dy, dz, ds)
end
adjButton( 92, 40, "X-", function() nudge(-ADJ_STEP, 0, 0, 0) end)
adjButton(134, 40, "X+", function() nudge( ADJ_STEP, 0, 0, 0) end)
adjButton(176, 40, "Y-", function() nudge(0, -ADJ_STEP, 0, 0) end)
adjButton(218, 40, "Y+", function() nudge(0,  ADJ_STEP, 0, 0) end)
adjButton(260, 40, "Z-", function() nudge(0, 0, -ADJ_STEP, 0) end)
adjButton(302, 40, "Z+", function() nudge(0, 0,  ADJ_STEP, 0) end)
adjButton(344, 40, "S-", function() nudge(0, 0, 0, -0.05) end)
adjButton(386, 40, "S+", function() nudge(0, 0, 0,  0.05) end)
do
	local b = mkButton(adjBar, {
		Size = UDim2.new(0, 92, 1, -6), Position = UDim2.new(1, -96, 0, 3),
		BackgroundColor3 = Color3.fromRGB(50, 220, 50), Text = "PRINT", Font = Enum.Font.GothamBold,
		TextSize = 12, TextColor3 = WHITE, ZIndex = 31,
	})
	fit(b, 12); mkCorner(b, 6); b:SetAttribute("BTS_Skip", true)
	b.MouseButton1Click:Connect(function()
		if activePet and _G.petSkinAdjustDump then _G.petSkinAdjustDump(activePet) end
	end)
end
local tuneBtn = mkButton(header, {
	Size = UDim2.new(0, 56, 0, 30), Position = UDim2.new(1, -246, 0, 9),
	BackgroundColor3 = CARD, Text = "TUNE", Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = GOLD,
})
fit(tuneBtn, 13); mkCorner(tuneBtn, 8); mkStroke(tuneBtn, GOLD, 1.5)
tuneBtn:SetAttribute("BTS_Skip", true)
tuneBtn.MouseButton1Click:Connect(function()
	adjBar.Visible = not adjBar.Visible
	tuneBtn.BackgroundColor3 = adjBar.Visible and GOLD or CARD
	tuneBtn.TextColor3 = adjBar.Visible and Color3.fromRGB(92, 58, 8) or GOLD
end)

-- pet selector: one chip per species, horizontally scrollable (leaves room for the EQUIP PET button)
local petBar = Instance.new("ScrollingFrame")
petBar.Size = UDim2.new(1, -160, 0, 32); petBar.Position = UDim2.new(0, 10, 0, 90)
petBar.BackgroundTransparency = 1; petBar.BorderSizePixel = 0; petBar.ScrollBarThickness = 4
petBar.ScrollBarImageColor3 = GOLD; petBar.CanvasSize = UDim2.new(0, 0, 0, 0)
petBar.AutomaticCanvasSize = Enum.AutomaticSize.X; petBar.ScrollingDirection = Enum.ScrollingDirection.X
petBar.Parent = panel
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 6); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = petBar
end
local petButtons = {}

-- the preview grid
local grid = Instance.new("ScrollingFrame")
grid.Size = UDim2.new(1, -20, 1, -140); grid.Position = UDim2.new(0, 10, 0, 130)
grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 6
grid.ScrollBarImageColor3 = GOLD; grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y; grid.Parent = panel
do
	local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.new(0, 160, 0, 172)
	gl.CellPadding = UDim2.new(0, 8, 0, 8); gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Center; gl.Parent = grid
end

-- ===== COMBO PAGE =====
-- Pick ONE skin + ONE trait and see them together on the selected pet: a single big preview, its Overall
-- Tier, and a TRY button. One combination at a time -- this is how skins x traits are inspected together
-- WITHOUT ever generating the forbidden all-combos grid.
local comboFrame = mkFrame(panel, {
	Size = UDim2.new(1, -20, 1, -140), Position = UDim2.new(0, 10, 0, 130),
	BackgroundTransparency = 1, Visible = false,
})
local comboSkin, comboTrait = "Classic", "King" -- opening pair; "" as trait = skin alone

local comboHolder = mkFrame(comboFrame, {
	Size = UDim2.new(0, 300, 0, 268), BackgroundColor3 = HEADER, BackgroundTransparency = 0.25,
})
mkCorner(comboHolder, 10); mkStroke(comboHolder, PANEL_DARK, 2)

local comboName = mkLabel(comboFrame, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = WHITE,
	Size = UDim2.new(0, 300, 0, 22), Position = UDim2.new(0, 0, 0, 274),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
fit(comboName, 16); mkStroke(comboName, Color3.new(0, 0, 0), 1.5)

local comboChip = mkFrame(comboFrame, {
	Size = UDim2.new(0, 150, 0, 24), Position = UDim2.new(0, 0, 0, 302),
	BackgroundColor3 = Color3.fromRGB(120, 130, 145),
})
mkCorner(comboChip, 10)
local comboChipLbl = mkLabel(comboChip, {
	Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.fromRGB(30, 30, 40),
	Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0),
})
fit(comboChipLbl, 13)

local comboTry = mkButton(comboFrame, {
	Size = UDim2.new(0, 90, 0, 30), Position = UDim2.new(0, 160, 0, 299),
	BackgroundColor3 = Color3.fromRGB(50, 220, 50), Text = "TRY",
	Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = WHITE,
})
fit(comboTry, 15); mkCorner(comboTry, 8); mkStroke(comboTry, Color3.fromRGB(30, 130, 30), 2)
comboTry:SetAttribute("BTS_Skip", true)

-- one selector column builder: a titled scrolling list of chips. Chips are built ONCE (the lists never
-- change); only the highlight and the single preview rebuild on a pick.
local function comboColumn(x, w, titleText)
	local title = mkLabel(comboFrame, {
		Text = titleText, Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = GOLD,
		Size = UDim2.new(0, w, 0, 20), Position = UDim2.new(0, x, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	fit(title, 14); mkStroke(title, Color3.new(0, 0, 0), 1.5)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0, w, 1, -24); list.Position = UDim2.new(0, x, 0, 24)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = GOLD; list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.Parent = comboFrame
	local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
	return list
end

local updateCombo -- forward: chips are wired before the updater exists
local skinChips, traitChips = {}, {}

do
	local skinList = comboColumn(315, 170, "SKIN")
	for i, skinId in ipairs(PetSkins.Order) do
		local s = PetSkins.Skins[skinId]
		local b = mkButton(skinList, {
			Size = UDim2.new(1, -8, 0, 24), LayoutOrder = i, BackgroundColor3 = CARD,
			Text = s.displayName .. "  \xC2\xB7  " .. s.tier,
			Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
		})
		fit(b, 12); mkCorner(b, 6); mkStroke(b, PetSkins.tierColor(s.tier), 1.5)
		b:SetAttribute("BTS_Skip", true)
		skinChips[skinId] = b
		b.MouseButton1Click:Connect(function() comboSkin = skinId; updateCombo() end)
	end

	local traitList = comboColumn(495, 175, "TRAIT")
	-- "None" first, so a skin can be inspected alone from this page too
	local noneBtn = mkButton(traitList, {
		Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 0, BackgroundColor3 = CARD,
		Text = "None", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
	})
	fit(noneBtn, 12); mkCorner(noneBtn, 6); mkStroke(noneBtn, Color3.fromRGB(170, 176, 188), 1.5)
	noneBtn:SetAttribute("BTS_Skip", true)
	traitChips[""] = noneBtn
	noneBtn.MouseButton1Click:Connect(function() comboTrait = ""; updateCombo() end)
	for i, t in ipairs(PetTraits.TRAITS) do
		local b = mkButton(traitList, {
			Size = UDim2.new(1, -8, 0, 24), LayoutOrder = i, BackgroundColor3 = CARD,
			Text = t.displayName .. "  \xC2\xB7  " .. t.tier,
			Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
		})
		fit(b, 12); mkCorner(b, 6); mkStroke(b, PetSkins.tierColor(t.tier), 1.5)
		b:SetAttribute("BTS_Skip", true)
		traitChips[t.id] = b
		b.MouseButton1Click:Connect(function() comboTrait = t.id; updateCombo() end)
	end
end

-- ===== LAZY PREVIEW BUILDER =====
-- ONE base model per pet, cached and cloned per cell; builds drain one per frame so a page of 21 viewports
-- never spikes a frame. A generation counter voids the queue whenever the page rebuilds, so previews for a
-- page that no longer exists are skipped instead of built into destroyed cells.
local baseCache = {}   -- [petId] = unparented model
local queue = {}
local working = false
local generation = 0

local function baseModel(petId)
	local hit = baseCache[petId]
	if hit then return hit end
	if not _G.petBuildModel then return nil end
	local ok, built = pcall(_G.petBuildModel, petId)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then return nil end
	built.Parent = nil
	baseCache[petId] = built
	return built
end

local function pumpQueue()
	if working then return end
	working = true
	task.spawn(function()
		while #queue > 0 do
			local req = table.remove(queue, 1)
			if req.gen == generation and req.vp and req.vp.Parent then
				local base = baseModel(req.petId)
				if base then
					pcall(function()
						for _, old in ipairs(req.vp:GetChildren()) do
							if not old:IsA("Camera") then old:Destroy() end
						end
						local clone = base:Clone()
						if _G.applyPetSkinPreview then
							_G.applyPetSkinPreview(clone, req.skin, req.trait, true) -- static: colours + geometry, no FX
						end
						clone.Parent = req.vp
						local cf, size = clone:GetBoundingBox()
						local reach = math.max(size.X, size.Y, size.Z)
						local dist = reach * 1.8 + 1
						local centre = cf.Position
						req.cam.CFrame = CFrame.lookAt(centre + Vector3.new(dist * 0.6, dist * 0.4, dist * 0.72), centre)
					end)
				end
			end
			task.wait() -- one build per frame
		end
		working = false
		if #queue > 0 then pumpQueue() end
	end)
end

local function makePreview(parent, petId, skinId, traitId)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, -12, 0, 104); vp.Position = UDim2.new(0, 6, 0, 6)
	vp.BackgroundColor3 = HEADER; vp.BackgroundTransparency = 0.25
	vp.Ambient = Color3.fromRGB(190, 190, 200); vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5)
	vp.Parent = parent
	mkCorner(vp, 8)
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp
	vp.CurrentCamera = cam
	mkLabel(vp, {
		Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextSize = 40, TextScaled = true,
		TextColor3 = Color3.fromRGB(150, 180, 235), Size = UDim2.new(1, 0, 1, 0),
	})
	queue[#queue + 1] = { gen = generation, vp = vp, cam = cam, petId = petId, skin = skinId, trait = traitId }
	pumpQueue()
	return vp
end

-- one labelled preview card
local function buildCard(order, petId, skinId, traitId, nameText, tierText, tierColor)
	local card = mkFrame(grid, { Size = UDim2.new(0, 160, 0, 172), LayoutOrder = order, BackgroundColor3 = CARD })
	mkCorner(card, 10); mkStroke(card, tierColor or WHITE, 2)
	makePreview(card, petId, skinId, traitId)
	local nm = mkLabel(card, {
		Text = nameText, Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = WHITE,
		Size = UDim2.new(1, -12, 0, 20), Position = UDim2.new(0, 6, 0, 114),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	fit(nm, 14); mkStroke(nm, Color3.new(0, 0, 0), 1.5)
	local chip = mkFrame(card, {
		Size = UDim2.new(0, 92, 0, 18), Position = UDim2.new(0, 6, 0, 140),
		BackgroundColor3 = tierColor or Color3.fromRGB(120, 130, 145),
	})
	mkCorner(chip, 9)
	local ct = mkLabel(chip, {
		Text = tierText or "", Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = Color3.fromRGB(30, 30, 40), Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0),
	})
	fit(ct, 11)
	-- TRY -- put this exact combo on the live follower pet, out in the world, full effects. Preview only.
	local tryBtn = mkButton(card, {
		Size = UDim2.new(0, 50, 0, 22), Position = UDim2.new(1, -56, 0, 138),
		BackgroundColor3 = Color3.fromRGB(50, 220, 50), Text = "TRY",
		Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = WHITE,
	})
	fit(tryBtn, 13); mkCorner(tryBtn, 8); mkStroke(tryBtn, Color3.fromRGB(30, 130, 30), 2)
	tryBtn:SetAttribute("BTS_Skip", true)
	tryBtn.MouseButton1Click:Connect(function()
		tryOnCombo(skinId, traitId, nameText)
	end)
	return card
end

-- ===== THE COMBO UPDATER =====
-- Assigned HERE, below makePreview, so the chips' click handlers (wired above through the forward local)
-- resolve a real function -- declared any earlier, makePreview would compile as a nil global. One preview
-- rebuilds per pick; the lists themselves are never rebuilt.
updateCombo = function()
	if not activePet then return end
	for _, ch in ipairs(comboHolder:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end -- the previous preview model goes with its viewport
	end
	local traitOrNil = comboTrait ~= "" and comboTrait or nil
	local vp = makePreview(comboHolder, activePet, comboSkin, traitOrNil)
	vp.Size = UDim2.new(1, -12, 1, -12) -- the card-sized default is too small for the one big preview
	comboName.Text = PetSkins.displayName(comboSkin, PetSkins.prettyPet(activePet))
		.. (traitOrNil and ("  +  " .. PetTraits.displayName(comboTrait)) or "")
	-- the pair's ONE Overall Tier -- the same maths the pet wears overhead
	local ovT
	if _G.petSkinOverallTier then
		local okOv, a = pcall(_G.petSkinOverallTier, comboSkin, traitOrNil)
		if okOv then ovT = a end
	end
	ovT = ovT or PetSkins.tierOf(comboSkin)
	comboChip.BackgroundColor3 = PetSkins.tierColor(ovT)
	comboChipLbl.Text = "Tier: " .. tostring(ovT)
	for id, b in pairs(skinChips) do
		b.BackgroundColor3 = (id == comboSkin) and GOLD or CARD
		b.TextColor3 = (id == comboSkin) and Color3.fromRGB(92, 58, 8) or WHITE
	end
	for id, b in pairs(traitChips) do
		b.BackgroundColor3 = (id == comboTrait) and GOLD or CARD
		b.TextColor3 = (id == comboTrait) and Color3.fromRGB(92, 58, 8) or WHITE
	end
end
comboTry.MouseButton1Click:Connect(function()
	tryOnCombo(comboSkin, comboTrait ~= "" and comboTrait or nil, comboName.Text)
end)

-- ===== PAGE BUILDS =====
rebuild = function()
	generation = generation + 1 -- voids every queued preview from the previous page
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end -- previews and their cloned models go with the cells
	end
	grid.Visible = (activePage ~= "combo")
	comboFrame.Visible = (activePage == "combo")
	for id, b in pairs(tabButtons) do
		local on = (id == activePage)
		b.BackgroundColor3 = on and GOLD or CARD
		b.TextColor3 = on and Color3.fromRGB(92, 58, 8) or GOLD
	end
	for id, b in pairs(petButtons) do
		local on = (id == activePet)
		b.BackgroundColor3 = on and GOLD or CARD
		b.TextColor3 = on and Color3.fromRGB(92, 58, 8) or WHITE
	end
	if not activePet then return end

	if activePage == "skins" then
		-- EVERY skin on the selected pet, no trait -- the "all skins x each pet" half of the matrix.
		subLbl.Text = "All " .. #PetSkins.Order .. " skins on " .. PetSkins.prettyPet(activePet) .. " \xE2\x80\x94 no trait"
		for i, skinId in ipairs(PetSkins.Order) do
			local s = PetSkins.Skins[skinId]
			buildCard(i, activePet, skinId, nil,
				PetSkins.displayName(skinId, PetSkins.prettyPet(activePet)),
				s.tier, PetSkins.tierColor(s.tier))
		end
	elseif activePage == "combo" then
		-- ONE chosen skin + ONE chosen trait, together -- a single preview at a time, never the grid.
		subLbl.Text = "Pick a skin + a trait \xE2\x80\x94 TRY wears the pair on your follower"
		updateCombo()
	else
		-- EVERY trait on the CLASSIC skin -- the "all traits x one common skin" half. Never the full cross
		-- product: that is what this command exists to avoid.
		subLbl.Text = "All " .. #PetTraits.TRAITS .. " traits on Classic " .. PetSkins.prettyPet(activePet)
		for i, t in ipairs(PetTraits.TRAITS) do
			buildCard(i, activePet, "Classic", t.id, t.displayName, t.tier, PetSkins.tierColor(t.tier))
		end
	end
end

-- ===== OPEN / CLOSE =====
local function setOpen(open)
	if open then
		if not activePet then
			-- pet chips are built once, on first open, from the live crate roster
			local pets = speciesList()
			activePet = pets[1]
			for i, petId in ipairs(pets) do
				local b = mkButton(petBar, {
					Size = UDim2.new(0, 118, 1, -6), LayoutOrder = i, BackgroundColor3 = CARD,
					Text = PetSkins.prettyPet(petId), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
				})
				fit(b, 12); mkCorner(b, 8); mkStroke(b, WHITE, 1)
				b:SetAttribute("BTS_Skip", true)
				petButtons[petId] = b
				b.MouseButton1Click:Connect(function() activePet = petId; rebuild() end)
			end
		end
		if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, "TestPetPreview") end
		gui.Enabled = true
		rebuild()
	else
		generation = generation + 1
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end -- nothing 3D lives on while the panel is closed
		end
		gui.Enabled = false
		if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyClosed, "TestPetPreview") end
	end
end
if _G.MainMenuManager then pcall(_G.MainMenuManager.register, "TestPetPreview", function() gui.Enabled = false end) end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

-- ===== /scanpet: THE GEOMETRY X-RAY =====
-- Scripts can't screenshot, but they can MEASURE. This walks EVERY pet x EVERY trait (plus each skin's
-- deco), builds the combo invisibly, and computes exact fit numbers: is a part buried inside the body,
-- floating detached from it, sitting over an eye, or crossing the mouth band? Only violations print,
-- between SCAN BEGIN/END markers -- copy that block out of the Output and it is the "x-ray" a human (or
-- Claude) can tune PET_OFFSETS and the trait specs from, combo by combo, without guessing.
local function aabbOf(p)
	local cf, h = p.CFrame, p.Size / 2
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for ix = -1, 1, 2 do for iy = -1, 1, 2 do for iz = -1, 1, 2 do
		local c = cf:PointToWorldSpace(Vector3.new(ix * h.X, iy * h.Y, iz * h.Z))
		mn = Vector3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
		mx = Vector3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
	end end end
	return mn, mx
end
local function aabbGap(aMin, aMax, bMin, bMax) -- 0 when touching/overlapping
	local dx = math.max(bMin.X - aMax.X, aMin.X - bMax.X, 0)
	local dy = math.max(bMin.Y - aMax.Y, aMin.Y - bMax.Y, 0)
	local dz = math.max(bMin.Z - aMax.Z, aMin.Z - bMax.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function scanCombo(petId, skinId, traitId, out)
	local base = baseModel(petId)
	if not base then return end
	local clone = base:Clone()
	-- BODY census, before any accessories exist: overall box, PER-PART boxes (burial is judged against
	-- real chunks of body, so a hat between two tall ears never reads "inside the body") and eye points
	local bMin = Vector3.new(math.huge, math.huge, math.huge)
	local bMax = -bMin
	local eyes = {}
	local bodyBoxes = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Eye" or d.Name == "Pupil" then eyes[#eyes + 1] = d.Position end
			local mn, mx = aabbOf(d)
			bodyBoxes[#bodyBoxes + 1] = { mn, mx }
			bMin = Vector3.new(math.min(bMin.X, mn.X), math.min(bMin.Y, mn.Y), math.min(bMin.Z, mn.Z))
			bMax = Vector3.new(math.max(bMax.X, mx.X), math.max(bMax.Y, mx.Y), math.max(bMax.Z, mx.Z))
		end
	end
	if bMin.X == math.huge then clone:Destroy(); return end
	local bC = (bMin + bMax) / 2
	local bH = bMax.Y - bMin.Y
	local eyeC = nil
	if #eyes > 0 then
		local s = Vector3.new()
		for _, e in ipairs(eyes) do s = s + e end
		eyeC = s / #eyes
	end
	-- the MOUTH BAND: on the eye side of the body, a strip just under the eye line. In STUDS, matching the
	-- renderer's chest-line units -- the old body-height fraction ballooned on tall pets (bunny ears count
	-- toward body height) and flagged correctly-seated chest gear forever.
	local mouthTop, mouthBot = nil, nil
	if eyeC then mouthTop = eyeC.Y - 0.12; mouthBot = eyeC.Y - 0.80 end

	if _G.applyPetSkinPreview then pcall(_G.applyPetSkinPreview, clone, skinId, traitId, true) end

	local buried, floating, eyeHits, mouthHits, worstBury = 0, 0, 0, 0, 0
	local groupBoxes = {} -- [attach] = {mn, mx}: floating is judged per ASSEMBLY, not per part -- a
	-- cone hat's top ring is far from the body but its base touches, and that is not floating
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "PetSkinAcc" or d.Name == "PetSkinDeco") then
			local attach = d:GetAttribute("PetSkinAttach") or "?"
			local mn, mx = aabbOf(d)
			local g = groupBoxes[attach]
			if g then
				g[1] = Vector3.new(math.min(g[1].X, mn.X), math.min(g[1].Y, mn.Y), math.min(g[1].Z, mn.Z))
				g[2] = Vector3.new(math.max(g[2].X, mx.X), math.max(g[2].Y, mx.Y), math.max(g[2].Z, mx.Z))
			else
				groupBoxes[attach] = { mn, mx }
			end
			-- BURIED: the whole part sits inside ONE real chunk of body -> genuinely invisible gear.
			-- (v1 tested the whole-body box, which "buried" every hat between a pair of tall ears.)
			for _, bb in ipairs(bodyBoxes) do
				local m1, m2 = bb[1], bb[2]
				if mn.X > m1.X and mx.X < m2.X and mn.Y > m1.Y and mx.Y < m2.Y and mn.Z > m1.Z and mx.Z < m2.Z then
					buried = buried + 1
					local d2 = math.min(mn.X - m1.X, m2.X - mx.X, mn.Z - m1.Z, m2.Z - mx.Z)
					if d2 > worstBury then worstBury = d2 end
					break
				end
			end
			-- EYE COVER: a non-Face part sitting over an eye point
			if attach ~= "Face" then
				for _, e in ipairs(eyes) do
					if e.X > mn.X and e.X < mx.X and e.Y > mn.Y and e.Y < mx.Y and e.Z > mn.Z and e.Z < mx.Z then
						eyeHits = eyeHits + 1
						break
					end
				end
			end
			-- MOUTH COVER: overlaps the band by a REAL margin, on the eye side. Head gear is above it and
			-- Face gear sits on the eye line by design, so only chest/body/back pieces are judged.
			if mouthTop and attach ~= "Head" and attach ~= "Face"
				and mn.Y < mouthTop - 0.08 and mx.Y > mouthBot + 0.08 then
				local onEyeSide = (eyeC.Z < bC.Z and mn.Z < bC.Z) or (eyeC.Z >= bC.Z and mx.Z > bC.Z)
				if onEyeSide and math.abs((mn.X + mx.X) / 2 - eyeC.X) < 0.6 * (bMax.X - bMin.X) / 2 then
					mouthHits = mouthHits + 1
				end
			end
		end
	end
	-- FLOATING: an attach group whose ENTIRE assembly is detached from the whole body by a visible gap.
	-- Celestial is exempt: its halo HOVERS above the head on purpose.
	if traitId ~= "Celestial" then
		for _, g in pairs(groupBoxes) do
			if aabbGap(g[1], g[2], bMin, bMax) > 0.35 then floating = floating + 1 end
		end
	end
	clone:Destroy()
	if buried + floating + eyeHits + mouthHits > 0 then
		local bits = {}
		if buried > 0 then bits[#bits + 1] = string.format("BURIED %d (depth %.2f)", buried, worstBury) end
		if floating > 0 then bits[#bits + 1] = "FLOATING " .. floating end
		if eyeHits > 0 then bits[#bits + 1] = "OVER-EYE " .. eyeHits end
		if mouthHits > 0 then bits[#bits + 1] = "OVER-MOUTH " .. mouthHits end
		out[#out + 1] = string.format("%s + %s%s: %s", petId,
			traitId ~= "" and traitId or ("skin:" .. tostring(skinId)),
			(traitId ~= "" and skinId ~= "Classic") and (" (" .. tostring(skinId) .. ")") or "",
			table.concat(bits, ", "))
	end
end

local scanning = false
local function runScan()
	if scanning then return end
	scanning = true
	task.spawn(function()
		local pets = speciesList()
		local out = {}
		local combos = 0
		print("[Scan] ===== SCAN BEGIN (copy everything down to SCAN END) =====")
		for _, petId in ipairs(pets) do
			for _, t in ipairs(PetTraits.TRAITS) do
				scanCombo(petId, "Classic", t.id, out)
				combos = combos + 1
				task.wait() -- one combo per frame keeps the client responsive
			end
			-- each skin that builds deco geometry gets checked too
			for _, skinId in ipairs(PetSkins.Order) do
				if PetSkins.Skins[skinId].deco then
					scanCombo(petId, skinId, "", out)
					combos = combos + 1
					task.wait()
				end
			end
			print("[Scan] " .. petId .. " done")
		end
		if #out == 0 then
			print("[Scan] no violations found across " .. combos .. " combos")
		else
			for _, line in ipairs(out) do print("[Scan] " .. line) end
			print(string.format("[Scan] %d issue line(s) across %d combos", #out, combos))
		end
		print("[Scan] ===== SCAN END =====")
		if _G.showHudBanner then
			pcall(_G.showHudBanner, "Scan done: " .. #out .. " issues -- copy the [Scan] block from Output",
				Color3.fromRGB(150, 255, 170), 5)
		end
		scanning = false
	end)
end

-- ===== THE COMMAND =====
-- Registered on BOTH chat paths, same as /crates: TextChatService (the one this place actually uses -- it
-- does not fire Player.Chatted) plus the legacy path for places still on the old chat.
local function onCommand()
	if not isTestUser() then return end -- silently nothing for everyone else
	print("[TestPet] /testpet -> toggling inspector")
	setOpen(not gui.Enabled)
end

local function onScanCommand()
	if not isTestUser() then return end
	print("[TestPet] /scanpet -> scanning every pet x trait combo")
	runScan()
end

player.Chatted:Connect(function(msg)
	local cmd = string.lower((string.gsub(msg, "^%s*(.-)%s*$", "%1")))
	if cmd == "/testpet" then onCommand()
	elseif cmd == "/scanpet" then onScanCommand() end
end)
do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "TestPetCommand"
		cmd.PrimaryAlias = "/testpet"
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(onCommand)
		local scan = Instance.new("TextChatCommand")
		scan.Name = "ScanPetCommand"
		scan.PrimaryAlias = "/scanpet"
		scan.Parent = TextChatService
		scan.Triggered:Connect(onScanCommand)
	end)
	if not ok then warn("[TestPet] TextChatService command registration failed: " .. tostring(err)) end
end

_G.scanPets = onScanCommand -- console convenience, same gate

_G.toggleTestPet = onCommand -- console convenience, same gate

print("[TestPet] /testpet inspector ready (" .. #PetSkins.Order .. " skins, " .. #PetTraits.TRAITS .. " traits)")
