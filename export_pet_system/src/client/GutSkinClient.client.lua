-- ============================================================================
-- GUT SKIN CLIENT — UI + animation for cosmetic gut skins.
--   * Injects a "Skins" tab into the existing Stomach menu (StomachShopGui.Panel), switching between the
--     stomach TIERS view and a scrolling SKINS grid. (Bottom HUD already hides while that menu is open.)
--   * Equip requests go to the server (EquipGutSkin); the server validates ownership + saves + re-skins the gut.
--   * Animated skins (Rainbow) are tweened on THIS client for the local player's gut; stops when a
--     non-animated skin is equipped.
-- ============================================================================

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local player       = Players.LocalPlayer
local playerGui    = player:WaitForChild("PlayerGui")
local GutSkins     = require(RS:WaitForChild("Shared"):WaitForChild("GutSkins"))

local EquipGutSkin   = RS:WaitForChild("EquipGutSkin", 60)
local GetGutSkins    = RS:WaitForChild("GetGutSkins", 60)
local GutSkinState   = RS:WaitForChild("GutSkinState", 60)
local GutSkinUnlocked= RS:WaitForChild("GutSkinUnlocked", 60)

local SKINTONE = Color3.fromRGB(255, 204, 153)
local localEquipped = "Default"
local localPlaytimeSec = 0 -- mirrors the server total; ticks up locally for live progress, re-synced on state events
local lastState = { owned = { Default = true }, equipped = "Default", playtimeSec = 0 }

-- ---- tiny UI helpers ----
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end
local function stroke(o, c, t) new("UIStroke", { Color = c or Color3.new(1,1,1), Thickness = t or 2 }, o) end
local function swatchColor(skin) return (skin and skin.color) or SKINTONE end
-- (The stomach-silhouette icon and its per-skin tint helper were dropped with the old grid cards: a row shows a
-- plain circular colour SWATCH now, so there is no image to tint and no image-failed fallback to guard against.)
-- red -> orange -> yellow -> green -> blue -> purple (the Rainbow skin's swatch gradient)
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 150, 40)),
	ColorSequenceKeypoint.new(0.40, Color3.fromRGB(245, 235, 50)),
	ColorSequenceKeypoint.new(0.60, Color3.fromRGB(70, 220, 90)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(70, 150, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(190, 80, 235)),
})
local function darken(c, amt) return c:Lerp(Color3.new(0, 0, 0), amt) end

-- ============================ RAINBOW ANIMATION =============================
local function findGutFolder()
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso"))
	return torso and torso:FindFirstChild("GutBelly")
end
local hue = 0
RunService.Heartbeat:Connect(function(dt)
	local skin = GutSkins.get(localEquipped)
	if not (skin and skin.animated == "rainbow") then return end -- only while a rainbow-type skin is equipped
	hue = (hue + dt * 0.15) % 1
	local folder = findGutFolder(); if not folder then return end
	local g = folder:FindFirstChild("Gut"); if not g then return end
	g.Color = Color3.fromHSV(hue, 0.85, 1)
	local sag = g:FindFirstChild("Sag");   if sag   then sag.Color   = Color3.fromHSV(hue, 0.85, 0.85) end
	local sheen = g:FindFirstChild("Sheen"); if sheen then sheen.Color = Color3.fromHSV(hue, 0.70, 1.00) end
	local navel = g:FindFirstChild("Navel"); if navel then navel.Color = Color3.fromHSV(hue, 0.90, 0.55) end
end)

-- =============================== SKINS GRID UI =============================
local skinsScroll     -- the grid ScrollingFrame (built once injected into the panel)
local rebuildSkins    -- forward declaration (assigned below)
local lockedCards = {} -- { {fill=, label=, thresholdSec=}, ... } updated live while the menu is open
local rainbowGradients = {} -- UIGradients (rainbow card bg + stomach icon) animated each frame; reset on rebuild

-- flow the rainbow over every rainbow gradient (preview cards) by rotating them; drops destroyed ones
RunService.Heartbeat:Connect(function(dt)
	for i = #rainbowGradients, 1, -1 do
		local g = rainbowGradients[i]
		if g and g.Parent then g.Rotation = (g.Rotation + dt * 60) % 360 else table.remove(rainbowGradients, i) end
	end
end)

-- SWATCH: the circular colour chip at the left of a skin row. It is filled with THAT SKIN'S OWN colour taken
-- straight from GutSkins -- no new palette is invented here:
--   * Default has no colour (it matches the avatar's own skin tone), so it shows SKINTONE,
--   * Rainbow gets the same animated RAINBOW_SEQ gradient its preview always used,
--   * everything else gets its colour with the existing top-bright / bottom-dark vertical tint, which is the
--     same shading relationship the belly itself has (Sheen 1.10 above, Sag 0.85 below).
-- Galaxy keeps its little stars and Lava keeps its neon ring, so each skin still reads as itself at a glance.
local function buildSwatch(row, skin, isOwned, size)
	local isRainbow = (skin.animated == "rainbow")
	local sw = new("Frame", { Name = "Swatch", BorderSizePixel = 0,
		BackgroundColor3 = isRainbow and Color3.fromRGB(40, 40, 55) or swatchColor(skin),
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(size, size) }, row)
	-- CornerRadius (1,0) on a square frame = a perfect circle at any size.
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, sw)
	stroke(sw, Color3.fromRGB(255, 205, 90), 2) -- gold-ish ring, as in the reference

	if isRainbow then
		rainbowGradients[#rainbowGradients + 1] = new("UIGradient", { Color = RAINBOW_SEQ, Rotation = 0 }, sw)
	else
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(swatchColor(skin), darken(swatchColor(skin), 0.45)) }, sw)
	end

	if skin.id == "Lava" then
		stroke(sw, Color3.fromRGB(255, 180, 60), 2) -- neon ring instead of the gold one
	elseif skin.id == "Galaxy" then
		for _, p in ipairs({ {0.28, 0.30}, {0.70, 0.34}, {0.55, 0.70} }) do
			new("TextLabel", { Text = "\xE2\x9C\xA6", Font = Enum.Font.GothamBold, TextScaled = true, BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(235, 225, 255), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(p[1], p[2]), Size = UDim2.fromOffset(9, 9), ZIndex = 3 }, sw)
		end
	end
	if not isOwned then sw.BackgroundTransparency = 0.35 end -- dimmed while still locked
	return sw
end

local function equip(skinId)
	task.spawn(function()
		local ok, res = pcall(function() return EquipGutSkin:InvokeServer(skinId) end)
		if ok and type(res) == "table" and res.ok then
			localEquipped = res.equipped or skinId
			localPlaytimeSec = res.playtimeSec or localPlaytimeSec
			lastState = { owned = res.owned or lastState.owned, equipped = localEquipped, playtimeSec = localPlaytimeSec }
			if _G.gutSkinBarRefresh then pcall(_G.gutSkinBarRefresh) end -- "Current skin: X" follows the equip
			if skinsScroll then rebuildSkins(lastState) end
		end
	end)
end

-- LIVE PROGRESS toward a locked skin, ticked once a second while the menu is open.
-- The old grid card had a dedicated progress BAR for this. The row layout has no room for one, so the same
-- numbers ride the subtitle instead -- "Rare  •  12m / 1h 30m" -- and the pill beside it carries the target.
-- Losing the readout entirely would have made the locked rows silent about how close you are, which is the
-- one thing a locked row is for.
local function refreshLockedProgress()
	for _, lc in ipairs(lockedCards) do
		if lc.label and lc.label.Parent then
			lc.label.Text = (lc.rarity or "")
				.. "  \xE2\x80\xA2  " .. GutSkins.formatMinutes(localPlaytimeSec / 60)
				.. " / " .. GutSkins.formatMinutes(lc.thresholdSec / 60)
		end
	end
end

-- ============================================================================================================
-- ONE ROW PER SKIN  (list, not a grid -- matches the Space Realm skins layout)
-- ============================================================================================================
-- Row: 78px tall, blue (35,60,180), corner 14, stroke (120,160,255) x3. Circular swatch left, bold name +
-- light-blue subtitle in the middle, status pill right. The EQUIPPED row takes a bright white stroke so the
-- one you are wearing is obvious at a glance.
--
-- THE SKIN LIST ITSELF IS UNTOUCHED. Rows are walked in GutSkins.Order and read straight out of GutSkins --
-- same six skins, same order, same names, same unlock rules. Nothing here adds, hides, renames or reprices
-- anything; the whole change is how a row is drawn.
local ROW_H, GAP = 78, 8

-- The status pill on the right. Which one you get is decided ENTIRELY by the existing data:
--   equipped      -> gold/orange, "✓ EQUIPPED"
--   owned         -> grey-tan,    "OWNED"
--   coin price    -> gold,        "<price> 🪙"   (only if a skin ever gains a `price` field)
--   robux price   -> gold,        "<price> R$"   (only if a skin ever gains a `robux` field)
--   locked        -> grey,        "🔒 " + THE GAME'S OWN unlock wording
-- The Fart Realm's gut skins are all PLAYTIME unlocks, so today only the first, second and last ever appear.
-- The two price branches are here so the layout is complete if pricing is added later -- they invent no data
-- and render nothing while `price`/`robux` are absent.
local function buildPill(row, kind, text)
	local bg, fg =
		Color3.fromRGB(150, 150, 160), Color3.new(1, 1, 1)
	if kind == "equipped" then bg = Color3.fromRGB(255, 180, 40)
	elseif kind == "owned" then bg = Color3.fromRGB(176, 160, 132)
	elseif kind == "price"  then bg = Color3.fromRGB(255, 200, 60); fg = Color3.fromRGB(60, 40, 0)
	elseif kind == "locked" then bg = Color3.fromRGB(120, 120, 132) end

	local pill = new("Frame", { Name = "Status", BorderSizePixel = 0, BackgroundColor3 = bg,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(178, 40) }, row)
	corner(pill, 10)
	local lbl = new("TextLabel", { Text = text, Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = fg, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, pill)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, lbl)
	new("UITextSizeConstraint", { MaxTextSize = 20 }, lbl)
	if kind == "equipped" then stroke(lbl, Color3.fromRGB(0, 0, 0), 2) end
	return pill
end

function rebuildSkins(state)
	if not skinsScroll then return end
	lockedCards = {}
	rainbowGradients = {} -- old gradients live on destroyed rows; the animator drops them, but reset so we don't grow
	for _, c in ipairs(skinsScroll:GetChildren()) do if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end end
	local owned = (state and state.owned) or { Default = true }
	local equipped = (state and state.equipped) or "Default"

	for i, id in ipairs(GutSkins.Order) do
		local skin = GutSkins.get(id); if skin then
			local isOwned = (id == "Default") or owned[id] == true
			local isEquipped = (id == equipped)

			-- The whole row is the button: clicking an owned skin equips it, exactly as the old EQUIP button did.
			local row = new("TextButton", { Name = "Skin_" .. id, LayoutOrder = i, Text = "", AutoButtonColor = false,
				BackgroundColor3 = Color3.fromRGB(35, 60, 180), BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, ROW_H) }, skinsScroll)
			corner(row, 14)
			-- equipped row gets the bright outer highlight from the reference; the rest keep the blue outline
			stroke(row, isEquipped and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(120, 160, 255), isEquipped and 4 or 3)
			if not isOwned then row.BackgroundColor3 = Color3.fromRGB(28, 44, 120) end -- locked rows sit back a little

			buildSwatch(row, skin, isOwned, 54)

			-- NAME + SUBTITLE. The subtitle keeps the wording the card already used -- the skin's RARITY -- so no
			-- new copy is invented. Locked rows append the live playtime progress after it, which is the only
			-- place that information still fits now the progress bar is gone.
			local textX = 12 + 54 + 12
			local nameLbl = new("TextLabel", { Name = "SkinName", Text = skin.displayName, Font = Enum.Font.FredokaOne,
				TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true,
				TextColor3 = isOwned and Color3.new(1, 1, 1) or Color3.fromRGB(205, 205, 215),
				BackgroundTransparency = 1, Position = UDim2.fromOffset(textX, 12),
				Size = UDim2.new(1, -(textX + 200), 0, 30) }, row)
			stroke(nameLbl, Color3.fromRGB(0, 0, 0), 2)
			new("UITextSizeConstraint", { MaxTextSize = 30 }, nameLbl)
			local sub = new("TextLabel", { Name = "SkinSub", Text = skin.rarity, Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true,
				TextColor3 = Color3.fromRGB(170, 205, 255), BackgroundTransparency = 1,
				Position = UDim2.fromOffset(textX, 44), Size = UDim2.new(1, -(textX + 200), 0, 20) }, row)
			new("UITextSizeConstraint", { MaxTextSize = 16 }, sub)

			if isEquipped then
				buildPill(row, "equipped", "\xE2\x9C\x93 EQUIPPED")
			elseif isOwned then
				buildPill(row, "owned", "OWNED")
				row.MouseButton1Click:Connect(function() equip(id) end)
			elseif type(skin.price) == "number" then
				-- coin purchase (no gut skin carries a price today -- see the note above buildPill)
				buildPill(row, "price", tostring(skin.price) .. " \xF0\x9F\xAA\x99")
				row.MouseButton1Click:Connect(function() equip(id) end) -- server validates + refuses if unaffordable
			elseif type(skin.robux) == "number" then
				buildPill(row, "price", tostring(skin.robux) .. " R$")
				row.MouseButton1Click:Connect(function() equip(id) end)
			else
				-- LOCKED -- worded exactly as the game already words it ("Unlocks at 1h 30m"), just with a lock.
				local mins = GutSkins.unlockMinutes(id)
				local pill = buildPill(row, "locked", "\xF0\x9F\x94\x92 Unlocks at " .. GutSkins.formatMinutes(mins))
				-- keep the LIVE progress the old card had: it now rides the subtitle ("Rare  •  12m / 1h 30m")
				lockedCards[#lockedCards + 1] = { fill = nil, label = sub, thresholdSec = mins * 60, rarity = skin.rarity, pill = pill }
			end
		end
	end
	refreshLockedProgress()
end

local function refreshFromServer()
	task.spawn(function()
		local ok, state = pcall(function() return GetGutSkins:InvokeServer() end)
		if ok and type(state) == "table" then
			lastState = state
			localEquipped = state.equipped or localEquipped
			if type(state.playtimeSec) == "number" then localPlaytimeSec = state.playtimeSec end
			rebuildSkins(state)
		end
	end)
end

GutSkinState.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then return end
	lastState = state
	localEquipped = state.equipped or localEquipped
	if type(state.playtimeSec) == "number" then localPlaytimeSec = state.playtimeSec end -- re-sync the live timer
	if _G.gutSkinBarRefresh then pcall(_G.gutSkinBarRefresh) end
	if skinsScroll and skinsScroll.Visible then rebuildSkins(state) end
end)

-- PLAYTIME UNLOCK -> banner through the shared (no-overlap, event-gated) scheduler + refresh the grid
GutSkinUnlocked.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or not info.id then return end
	if lastState.owned then lastState.owned[info.id] = true end
	if _G.enqueueReminderBanner then
		_G.enqueueReminderBanner("\xF0\x9F\x8E\x89 Unlocked the " .. (info.displayName or info.id) .. " gut skin!", "skinunlock_" .. info.id)
	end
	if skinsScroll and skinsScroll.Visible then rebuildSkins(lastState) end
end)

-- tick the local playtime mirror so locked progress bars move in real time while the menu is open
task.spawn(function()
	while true do
		task.wait(1)
		localPlaytimeSec = localPlaytimeSec + 1
		if skinsScroll and skinsScroll.Visible then refreshLockedProgress() end
	end
end)

-- =================== INJECT THE "SKINS" TAB INTO THE STOMACH MENU ===========
task.spawn(function()
	local gui = playerGui:WaitForChild("StomachShopGui", 120); if not gui then return end
	local panel = gui:WaitForChild("Panel", 30); if not panel then return end
	local tierList = panel:WaitForChild("TierList", 30)
	local currentLabel = panel:WaitForChild("CurrentLabel", 30)

	-- make room: drop the current-gut label + tier list down so a tab row fits above them
	currentLabel.Position = UDim2.fromOffset(10, 100)
	tierList.Position = UDim2.new(0, 10, 0, 143)
	tierList.Size = UDim2.new(1, -20, 1, -148)

	-- ========================================================================================================
	-- SHELL RESTYLE  (dark navy, to match the Space Realm skins window)
	-- ========================================================================================================
	-- The window itself is built by CoreClient. It is NOT rebuilt here -- the existing instances are re-coloured
	-- in place. That matters twice over: CoreClient sits at Luau's 200-local ceiling (one more top-level local
	-- there takes the whole HUD down), and a baked-in copy of CoreClient in the place would shadow any edit made
	-- to its file anyway. Mutating what is already on screen works whichever copy built it.
	--
	-- This is the SHARED shell, so the STOMACHS tab sits in the same window. Its tier rows still carry the old
	-- warm-brown palette -- restyling those was not part of this brief.
	panel.BackgroundColor3 = Color3.fromRGB(12, 10, 32)
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("UIGradient") then c:Destroy() end -- kill the warm brown gradient; the reference is flat navy
		if c:IsA("UICorner") then c.CornerRadius = UDim.new(0, 20) end
		if c:IsA("UIStroke") then c.Color = Color3.fromRGB(90, 120, 255); c.Thickness = 4 end
	end
	-- outer glow: a slightly larger frame sitting BEHIND the panel (ZIndex 0), so the window reads as lit
	if not panel:FindFirstChild("OuterGlow") then
		local glow = new("Frame", { Name = "OuterGlow", BackgroundColor3 = Color3.fromRGB(90, 120, 255),
			BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 18, 1, 18) }, panel)
		corner(glow, 26)
	end
	-- TITLE: white, black-stroked, ~44px. The realm's existing gut icon at the left is left exactly where it is.
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("TextLabel") and c.Text == "STOMACH SHOP" then
			c.TextColor3 = Color3.new(1, 1, 1)
			c.TextScaled = true
			new("UITextSizeConstraint", { MaxTextSize = 44 }, c)
			local s = c:FindFirstChildOfClass("UIStroke")
			if s then s.Color = Color3.fromRGB(0, 0, 0); s.Thickness = 2 end
		end
	end
	-- COIN PILL + CLOSE: the X already exists (CoreClient owns its close handler, so it is only MOVED, never
	-- rebuilt -- rebuilding it would drop that handler and the shop would stop closing). The coin pill is new
	-- and slots in to its left.
	local closeBtn
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("TextButton") and c.Text == "X" then closeBtn = c end
	end
	if closeBtn then
		closeBtn.Position = UDim2.new(1, -48, 0, 8)
		local cc = closeBtn:FindFirstChildOfClass("UICorner"); if cc then cc.CornerRadius = UDim.new(0, 8) end
	end
	if not panel:FindFirstChild("CoinPill") then
		local pill = new("Frame", { Name = "CoinPill", BackgroundColor3 = Color3.fromRGB(255, 200, 60), BorderSizePixel = 0,
			Position = UDim2.new(1, -214, 0, 10), Size = UDim2.fromOffset(158, 36) }, panel)
		corner(pill, 10); stroke(pill, Color3.fromRGB(190, 140, 20), 2)
		local lbl = new("TextLabel", { Name = "Amount", Text = "\xF0\x9F\xAA\x99 0", Font = Enum.Font.FredokaOne,
			TextScaled = true, TextColor3 = Color3.fromRGB(60, 40, 0), BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1) }, pill)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, lbl)
		new("UITextSizeConstraint", { MaxTextSize = 22 }, lbl)
		-- Read the SAME leaderstats value the HUD coin counter reads, and follow it, so the pill can never
		-- disagree with the number on screen behind the shop.
		local function bindCoins()
			local ls = player:FindFirstChild("leaderstats")
			local coins = ls and ls:FindFirstChild("Coins")
			if not coins then return false end
			local function paint() lbl.Text = "\xF0\x9F\xAA\x99 " .. tostring(coins.Value) end
			coins.Changed:Connect(paint); paint()
			return true
		end
		if not bindCoins() then
			task.spawn(function()
				local waited = 0
				while waited < 30 and not bindCoins() do task.wait(0.5); waited += 0.5 end
			end)
		end
	end

	-- skins list lives in the same rect as the tier list, hidden until the Skins tab is picked
	skinsScroll = new("ScrollingFrame", { Name = "SkinsList", Visible = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 143), Size = UDim2.new(1, -20, 1, -148),
		ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,  -- same setup as PetInventory/Locker
		ScrollBarThickness = 6, ScrollBarImageColor3 = Color3.fromRGB(120, 160, 255), ClipsDescendants = true }, panel)
	-- ONE ROW PER SKIN, full width, 8px apart -- the grid is gone.
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, skinsScroll)
	new("UIPadding", { PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6) }, skinsScroll)

	-- CURRENT BAR (Skins tab). A SEPARATE bar rather than reusing CoreClient's CurrentLabel: that label is
	-- rewritten by CoreClient every time the gut tier changes ("Current: Tiny Gut (100 max power)"), so writing
	-- a skin name into it would be overwritten the moment a stomach is bought.
	local skinBar = new("Frame", { Name = "SkinCurrentBar", Visible = false, BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(30, 25, 60),
		Position = UDim2.new(0, 10, 0, 100), Size = UDim2.new(1, -20, 0, 35) }, panel)
	corner(skinBar, 10)
	local skinBarLbl = new("TextLabel", { Name = "Text", Text = "Current skin: Default", Font = Enum.Font.FredokaOne,
		TextScaled = true, TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1) }, skinBar)
	new("UITextSizeConstraint", { MaxTextSize = 22 }, skinBarLbl)
	local function refreshSkinBar()
		local s = GutSkins.get(localEquipped)
		skinBarLbl.Text = "Current skin: " .. ((s and s.displayName) or localEquipped or "Default")
	end
	_G.gutSkinBarRefresh = refreshSkinBar -- so the state handlers below can update it without a rebuild

	-- two tabs at the top, pill shaped
	local function mkTab(text, x)
		local b = new("TextButton", { Text = text, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1,1,1),
			BackgroundColor3 = Color3.fromRGB(25, 30, 70), Position = UDim2.fromOffset(x, 62), Size = UDim2.fromOffset(150, 32), BorderSizePixel = 0 }, panel)
		corner(b, 8); stroke(b, Color3.fromRGB(24,14,8), 1.5) -- thin DARK outline (a white stroke here bloomed the white text into an unreadable glow)
		b.TextColor3 = Color3.new(1,1,1); b.TextXAlignment = Enum.TextXAlignment.Center; b.TextYAlignment = Enum.TextYAlignment.Center
		new("UITextSizeConstraint", { MaxTextSize = 18 }, b)
		b:SetAttribute("BTS_Skip", true) -- the tab's colour IS which tab you're on; keep the legibility sweep off it
		return b
	end
	local tabStomachs = mkTab("STOMACHS", 10)
	local tabSkins    = mkTab("SKINS", 168)

	local function showTab(which)
		local skinsOn = (which == "skins")
		skinsScroll.Visible = skinsOn
		skinBar.Visible = skinsOn
		tierList.Visible = not skinsOn
		currentLabel.Visible = not skinsOn
		-- active = blue (60,140,255), inactive = dark navy (25,30,70)
		tabSkins.BackgroundColor3    = skinsOn and Color3.fromRGB(60, 140, 255) or Color3.fromRGB(25, 30, 70)
		tabStomachs.BackgroundColor3 = skinsOn and Color3.fromRGB(25, 30, 70) or Color3.fromRGB(60, 140, 255)
		if skinsOn then refreshSkinBar(); refreshFromServer() end -- pull the latest owned/equipped each time Skins opens
	end
	tabStomachs.MouseButton1Click:Connect(function() showTab("stomachs") end)
	tabSkins.MouseButton1Click:Connect(function() showTab("skins") end)
	-- whenever the Stomach menu re-opens, default back to the Stomachs (tiers) tab
	gui:GetPropertyChangedSignal("Enabled"):Connect(function() if gui.Enabled then showTab("stomachs") end end)
	showTab("stomachs")
end)

-- know the equipped skin early (so Rainbow animates even before the menu is opened)
refreshFromServer()

print("[GutSkinClient] ready (Skins tab in Stomach menu, equip + rainbow animation)")
