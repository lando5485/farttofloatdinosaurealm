--[[
	WormholeClient.client.luau  (StarterPlayerScripts.WormholeClient)

	The Wormhole travel menu + warp transition. Publishes an "OpenWormhole" BindableEvent (the HUD sidebar's
	Wormhole button fires it, mirroring the food shop's OpenFoodShop). The menu lists all 13 islands in CLIMB
	order (IslandOrder.SLOT_TO_ISLAND). Tapping an open island plays a full-screen wormhole-tunnel warp (~1.5s)
	and asks the SERVER to teleport — the server re-checks the same rule before moving them.

	*** TEMPORARY: EVERY ISLAND IS UNLOCKED *** — isVisited() below is stubbed open, so no row is ever greyed
	out or locked ("Visit it first"). WormholeService carries the MATCHING temporary gate; revert both together
	or the panel will offer islands the server refuses. Revert instructions sit at isVisited().

	Travel only: it never unlocks islands or grants tiers — it just requests a move.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== DINO ISLANDS: shared tower order + names (single source of truth). SLOT 1 = the FIRST island
-- (bottom) ... SLOT 13 = the SUMMIT / FINALE. We list islands in CLIMB order and gate each by HighestSlot. =====
local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND -- slot -> island MODEL number
local ISLAND_NAMES = IslandOrder.NAMES            -- island MODEL number -> display name
local ISLAND_TO_SLOT = IslandOrder.ISLAND_TO_SLOT
local ISLAND_COUNT = IslandOrder.COUNT

-- Open signal: a BindableEvent both the HUD's WORMHOLE sidebar button and this script get-or-create under
-- ReplicatedStorage, so it resolves regardless of client load order (Dino equivalent of the Space realm's
-- HudSignals "OpenWormhole"). The sidebar button :Fire()s it; we connect .Event below.
local openSignal = ReplicatedStorage:FindFirstChild("OpenWormhole")
if not openSignal then
	openSignal = Instance.new("BindableEvent")
	openSignal.Name = "OpenWormhole"
	openSignal.Parent = ReplicatedStorage
end

-- Remotes (the server creates them). Timeouts so a slow replication under heavy load can NEVER permanently
-- block the rest of this script (that would stop the OpenWormhole hookup at the bottom from ever running, so
-- the button would do nothing). The warp helpers guard against a nil remote.
local wormholeRemotes = ReplicatedStorage:WaitForChild("WormholeRemotes", 30)
local RequestWarp = wormholeRemotes and wormholeRemotes:WaitForChild("RequestWarp", 30)             -- in-place island warp
local RequestRealmWarp = wormholeRemotes and wormholeRemotes:WaitForChild("RequestRealmWarp", 30)   -- cross-place realm hop ("Food"/"Space")
local RealmWarpFailed = wormholeRemotes and wormholeRemotes:WaitForChild("RealmWarpFailed", 30)     -- async teleport-failure notice

-- ===== Palette =====
local PANEL = Color3.fromRGB(18, 24, 52)
local PANEL_DEEP = Color3.fromRGB(10, 14, 32)
local ACCENT = Color3.fromRGB(150, 90, 230)
local TITLE_BAR = Color3.fromRGB(28, 22, 60)
local WHITE = Color3.fromRGB(235, 242, 255)
local LOCK_GREY = Color3.fromRGB(46, 50, 66)
local MUTED = Color3.fromRGB(150, 160, 195)

-- per-island accent colour, spread around the hue wheel so each row reads distinctly.
local function islandColor(i)
	return Color3.fromHSV(((i - 1) / 13) % 1, 0.55, 1)
end

-- ===== State (visited by CLIMB SLOT, from the replicated HighestSlot attribute) =====
-- Progress is the highest tower SLOT reached (PetXPHooks sets HighestSlot; it's the clean climb signal —
-- HighestIsland can't be used, the tower scrambles model numbers vs climb order). While the TEMPORARY
-- unlock below is in place this attribute gates NOTHING here — every slot is tappable.
-- Kept for the revert of the TEMPORARY every-island unlock in isVisited below; Studio will flag it
-- as unused until that gate comes back. Do not delete.
local function highestSlot()
	return math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
end
-- *** TEMPORARY: EVERY ISLAND UNLOCKED. *** Every slot is tappable regardless of climb
-- progress. WormholeService has the MATCHING temporary gate -- both must be reverted
-- together or the panel offers islands the server refuses.
--
-- TO REVERT, restore the progression rule (and the same in WormholeService):
--     return slot >= 1 and slot == highestSlot()
--
-- That rule was ONLY THE HIGHEST SLOT, not everything up to it: an earlier
-- `slot <= highestSlot()` left every island you had ever reached open, making the wormhole
-- a free ride back down the tower. It matched the Return button -- the one destination
-- either could produce was the furthest point you actually climbed to.
local function isVisited(slot)
	return slot >= 1 and slot <= ISLAND_COUNT
end
-- current climb slot = the slot of the island model the player stands in (nearest otherwise); labels "Here".
local function currentSlot()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 1 end
	local pos = hrp.Position
	local best, bestD = 1, math.huge
	for slot = 1, ISLAND_COUNT do
		local isl = Workspace:FindFirstChild("island" .. SLOT_TO_ISLAND[slot])
		if isl then
			local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
			if ok and cf and size then
				local dx, dz = pos.X - cf.Position.X, pos.Z - cf.Position.Z
				if math.abs(dx) <= size.X / 2 and math.abs(dz) <= size.Z / 2 then return slot end
				local d = dx * dx + dz * dz
				if d < bestD then bestD = d; best = slot end
			end
		end
	end
	return best
end

-- ===== MENU GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "WormholeMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 160
gui.Enabled = false
gui.Parent = PlayerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.Active = true
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
-- HUB PARITY: same box the Pet Hub and the MORE+ popup use -- 700x520 at 0.5/0.5 with a
-- -16 lift. All three are full-screen popups opened from the same rail, and three different
-- sizes made switching between them look like three different games.
--
-- This was 0.9-of-screen wide x 470, capped by a UISizeConstraint to 460x470. Both the
-- percentage and the cap are gone: ResponsiveUI puts ONE global UIScale on every ScreenGui,
-- so a fixed pixel box is the house pattern here and small screens are handled centrally --
-- which is exactly why neither the hub nor MORE+ carries a constraint of its own. Leaving
-- the 460 cap in place would have pinned this panel at 460 while the other two grew to 700.
--
-- Safe to widen: everything inside is relative (rows are UDim2.new(1, -6, 0, 50)) and the
-- destination list is an AutomaticCanvasSize ScrollingFrame, so a taller panel simply shows
-- more islands before scrolling.
panel.Position = UDim2.new(0.5, 0, 0.5, -16)
panel.Size = UDim2.new(0, 700, 0, 520)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = ACCENT; s.Thickness = 2; s.Transparency = 0.2; s.Parent = panel
	-- (no UISizeConstraint -- see the hub-parity note on panel.Size above)
end
-- The panel has its OWN UIScale (panelScale, for the open pop), so the generic ResponsiveUI pass skips it.
-- REST scale = the SAME getScale() the HUD + other menus use. ResponsiveUI publishes it as the LocalPlayer
-- "ResponsiveScale" attribute on mobile (unset on desktop -> 1). POP keeps the pop-in proportional.
local function restScale() return player:GetAttribute("ResponsiveScale") or 1 end
local WORMHOLE_POP_FRAC = 0.7
local WORMHOLE_REST = restScale()
local WORMHOLE_POP = WORMHOLE_POP_FRAC * WORMHOLE_REST
local panelScale = Instance.new("UIScale"); panelScale.Scale = WORMHOLE_POP; panelScale.Parent = panel
player:GetAttributeChangedSignal("ResponsiveScale"):Connect(function()
	WORMHOLE_REST = restScale()
	WORMHOLE_POP = WORMHOLE_POP_FRAC * WORMHOLE_REST
	if gui.Enabled then -- live-resize the open menu to the new device scale
		panelScale.Scale = WORMHOLE_REST
	end
end)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 56)
titleBar.BackgroundColor3 = TITLE_BAR
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = titleBar
	local mask = Instance.new("Frame")
	mask.AnchorPoint = Vector2.new(0, 1); mask.Position = UDim2.new(0, 0, 1, 0); mask.Size = UDim2.new(1, 0, 0, 20)
	mask.BackgroundColor3 = TITLE_BAR; mask.BorderSizePixel = 0; mask.Parent = titleBar
end
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.new(0, 16, 0.5, 0)
title.Size = UDim2.new(1, -70, 1, -14)
title.Font = Enum.Font.FredokaOne
title.Text = "\u{1F300} WORMHOLE"
title.TextColor3 = WHITE
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar
do
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = title
	local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0); st.Thickness = 1.5; st.Transparency = 0.4; st.Parent = title
end
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
closeBtn.Font = Enum.Font.FredokaOne
closeBtn.Text = "X"
closeBtn.TextColor3 = WHITE
closeBtn.TextScaled = true
closeBtn.Parent = titleBar
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn end

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.new(0.5, 0, 0, 62)
subtitle.Size = UDim2.new(1, -32, 0, 22)
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "Warp to a world you've already visited"
subtitle.TextColor3 = MUTED
subtitle.TextScaled = true
subtitle.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 16; cns.Parent = subtitle end

-- Scrolling list of planet rows.
local scroll = Instance.new("ScrollingFrame")
scroll.AnchorPoint = Vector2.new(0.5, 0)
scroll.Position = UDim2.new(0.5, 0, 0, 92)
scroll.Size = UDim2.new(1, -24, 1, -104)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local warping = false -- guard taps during a warp
local closeMenu -- fwd

-- Build one tappable/locked row per planet; returns a refresh function.
local rowRefreshers = {}
for slot = 1, ISLAND_COUNT do
	local islandNum = SLOT_TO_ISLAND[slot]
	local islandName = ISLAND_NAMES[islandNum]
	local col = islandColor(slot)
	local row = Instance.new("TextButton")
	row.Name = "Slot" .. slot
	row.LayoutOrder = slot
	row.Size = UDim2.new(1, -6, 0, 50)
	row.AutoButtonColor = true
	row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP
	row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = ACCENT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.4; rowStroke.Parent = row

	-- Island ICON: a coloured disc showing the CLIMB position (1..13, first -> summit); no external asset.
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 11, 0.5, 0)
	iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = row
	local disc = Instance.new("TextLabel")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.new(0.5, 0, 0.5, 0)
	disc.Size = UDim2.new(1, 0, 1, 0)
	disc.BackgroundColor3 = col
	disc.Font = Enum.Font.FredokaOne
	disc.Text = tostring(slot)
	disc.TextColor3 = Color3.new(1, 1, 1)
	disc.TextScaled = true
	disc.Parent = iconHolder
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 12, 24); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
	end
	-- Grey "locked" disc laid over the icon (shown until the island is visited) so locked rows stay dimmed.
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockDim"
	lockOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
	lockOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(54, 58, 74)
	lockOverlay.BackgroundTransparency = 0.15
	lockOverlay.BorderSizePixel = 0
	lockOverlay.ZIndex = 6
	lockOverlay.Visible = false
	lockOverlay.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = lockOverlay end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.AnchorPoint = Vector2.new(0, 0.5)
	nameLbl.Position = UDim2.new(0, 50, 0.5, 0)
	nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Text = islandName
	nameLbl.TextColor3 = WHITE
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.BackgroundTransparency = 1
	statusLbl.AnchorPoint = Vector2.new(1, 0.5)
	statusLbl.Position = UDim2.new(1, -14, 0.5, 0)
	statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.Text = ""
	statusLbl.TextColor3 = MUTED
	statusLbl.TextScaled = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Right
	statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	-- (the tap handler is wired AFTER warpTo is defined, near the bottom)

	rowRefreshers[slot] = function()
		local here = currentSlot()
		if isVisited(slot) then
			row.BackgroundColor3 = PANEL_DEEP
			rowStroke.Color = col
			rowStroke.Transparency = 0.25
			lockOverlay.Visible = false -- full-colour island disc
			nameLbl.TextColor3 = WHITE
			statusLbl.Text = (slot == here) and "Here" or "Warp \u{27A4}"
			statusLbl.TextColor3 = (slot == here) and MUTED or col
			row.Active = true
			row.AutoButtonColor = true
		else
			row.BackgroundColor3 = LOCK_GREY
			rowStroke.Color = Color3.fromRGB(70, 74, 92)
			rowStroke.Transparency = 0.5
			lockOverlay.Visible = true -- dim the disc while locked
			nameLbl.TextColor3 = MUTED
			statusLbl.Text = "\u{1F512} Visit it first"
			statusLbl.TextColor3 = MUTED
			row.Active = false
			row.AutoButtonColor = false
		end
	end
end

-- ===== FOOD REALM (single cross-place destination) =====
-- ONE button that teleports to the Food Realm place. Same row/card style as the island rows above. The tap is
-- wired at the bottom (after warpToRealm is defined), passing "Food".
do
	local FOOD_TINT = Color3.fromRGB(255, 150, 70)

	-- Section divider so Food Realm reads as its own area, below the planets.
	local divider = Instance.new("TextLabel")
	divider.Name = "OtherRealmsHeader"
	divider.LayoutOrder = 100
	divider.Size = UDim2.new(1, -6, 0, 24)
	divider.BackgroundTransparency = 1
	divider.Font = Enum.Font.GothamBold
	divider.Text = "\u{1F30C} OTHER REALMS"
	divider.TextColor3 = MUTED
	divider.TextScaled = true
	divider.TextXAlignment = Enum.TextXAlignment.Left
	divider.Parent = scroll
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 14; cns.Parent = divider end

	local row = Instance.new("TextButton")
	row.Name = "FoodRealm"
	row.LayoutOrder = 101
	row.Size = UDim2.new(1, -6, 0, 50)
	row.AutoButtonColor = true -- tappable: cross-place teleport to the Food Realm place
	row.Active = true
	row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP
	row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = FOOD_TINT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.35; rowStroke.Parent = row

	-- Food-themed icon: a soft tinted disc with a food glyph (distinct from the realistic planet icons).
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 11, 0.5, 0)
	iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = row
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.Size = UDim2.new(1, 0, 1, 0)
	glow.BackgroundColor3 = FOOD_TINT
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = glow end
	local disc = Instance.new("TextLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.new(0.5, 0, 0.5, 0)
	disc.Size = UDim2.new(0.82, 0, 0.82, 0)
	disc.BackgroundColor3 = FOOD_TINT
	disc.BorderSizePixel = 0
	disc.Font = Enum.Font.FredokaOne
	disc.Text = "\u{1F354}" -- 🍔 food
	disc.TextColor3 = Color3.new(1, 1, 1)
	disc.TextScaled = true
	disc.ZIndex = 3
	disc.Parent = iconHolder
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 12, 24); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.AnchorPoint = Vector2.new(0, 0.5)
	nameLbl.Position = UDim2.new(0, 50, 0.5, 0)
	nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Text = "Food Realm"
	nameLbl.TextColor3 = WHITE
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.BackgroundTransparency = 1
	statusLbl.AnchorPoint = Vector2.new(1, 0.5)
	statusLbl.Position = UDim2.new(1, -14, 0.5, 0)
	statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.Text = "Warp \u{27A4}"
	statusLbl.TextColor3 = FOOD_TINT
	statusLbl.TextScaled = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Right
	statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	print("[Wormhole] Food Realm cross-place button added.")
end

-- ===== SPACE REALM (cross-place destination) =====
do
	local SPACE_TINT = Color3.fromRGB(150, 110, 255)

	local row = Instance.new("TextButton")
	row.Name = "SpaceRealm"
	row.LayoutOrder = 102
	row.Size = UDim2.new(1, -6, 0, 50)
	row.AutoButtonColor = true -- tappable: cross-place teleport to the Space Realm place
	row.Active = true
	row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP
	row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = SPACE_TINT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.35; rowStroke.Parent = row

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 11, 0.5, 0)
	iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = row
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.Size = UDim2.new(1, 0, 1, 0)
	glow.BackgroundColor3 = SPACE_TINT
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = glow end
	local disc = Instance.new("TextLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.new(0.5, 0, 0.5, 0)
	disc.Size = UDim2.new(0.82, 0, 0.82, 0)
	disc.BackgroundColor3 = SPACE_TINT
	disc.BorderSizePixel = 0
	disc.Font = Enum.Font.FredokaOne
	disc.Text = "\u{1FA90}" -- 🪐 space
	disc.TextColor3 = Color3.new(1, 1, 1)
	disc.TextScaled = true
	disc.ZIndex = 3
	disc.Parent = iconHolder
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(10, 12, 24); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.AnchorPoint = Vector2.new(0, 0.5)
	nameLbl.Position = UDim2.new(0, 50, 0.5, 0)
	nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Text = "Space Realm"
	nameLbl.TextColor3 = WHITE
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.BackgroundTransparency = 1
	statusLbl.AnchorPoint = Vector2.new(1, 0.5)
	statusLbl.Position = UDim2.new(1, -14, 0.5, 0)
	statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.Text = "Warp \u{27A4}"
	statusLbl.TextColor3 = SPACE_TINT
	statusLbl.TextScaled = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Right
	statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	print("[Wormhole] Space Realm cross-place button added.")
end

-- ===== CANDY REALM (cross-place destination) -- same card as Space, candy-pink =====
do
	local CANDY_TINT = Color3.fromRGB(255, 140, 200)

	local row = Instance.new("TextButton")
	row.Name = "CandyRealm"
	row.LayoutOrder = 103
	row.Size = UDim2.new(1, -6, 0, 50)
	row.AutoButtonColor = true -- tappable: cross-place teleport to the Candy Realm place
	row.Active = true
	row.Text = ""
	row.BackgroundColor3 = PANEL_DEEP
	row.Parent = scroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row end
	local rowStroke = Instance.new("UIStroke"); rowStroke.Color = CANDY_TINT; rowStroke.Thickness = 1.5; rowStroke.Transparency = 0.35; rowStroke.Parent = row

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.new(0, 11, 0.5, 0)
	iconHolder.Size = UDim2.new(0, 30, 0, 30)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = row
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.Size = UDim2.new(1, 0, 1, 0)
	glow.BackgroundColor3 = CANDY_TINT
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Parent = iconHolder
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = glow end
	local disc = Instance.new("TextLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.new(0.5, 0, 0.5, 0)
	disc.Size = UDim2.new(0.82, 0, 0.82, 0)
	disc.BackgroundColor3 = CANDY_TINT
	disc.BorderSizePixel = 0
	disc.Font = Enum.Font.FredokaOne
	disc.Text = "\u{1F36D}" -- 🍭 candy
	disc.TextColor3 = Color3.new(1, 1, 1)
	disc.TextScaled = true
	disc.ZIndex = 3
	disc.Parent = iconHolder
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60, 16, 40); s.Thickness = 1; s.Transparency = 0.2; s.Parent = disc
	end

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.AnchorPoint = Vector2.new(0, 0.5)
	nameLbl.Position = UDim2.new(0, 50, 0.5, 0)
	nameLbl.Size = UDim2.new(0.5, 0, 1, -12)
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Text = "Candy Realm"
	nameLbl.TextColor3 = WHITE
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = nameLbl end

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.BackgroundTransparency = 1
	statusLbl.AnchorPoint = Vector2.new(1, 0.5)
	statusLbl.Position = UDim2.new(1, -14, 0.5, 0)
	statusLbl.Size = UDim2.new(0.5, -10, 1, -14)
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.Text = "Warp \u{27A4}"
	statusLbl.TextColor3 = CANDY_TINT
	statusLbl.TextScaled = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Right
	statusLbl.Parent = row
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 15; cns.Parent = statusLbl end

	print("[Wormhole] Candy Realm cross-place button added.")
end

print("[Wormhole] row indicators upgraded to planet icons (matching STATS race-row style).")

-- ===== WARP TRANSITION — delegated to the shared WarpEffect module =====
-- The ~1.9s wormhole cinematic + warp sounds now live in ReplicatedStorage.DinosaurRealm.WarpEffect (a reusable
-- module), replacing the copy that used to be inlined here. playWarpSound()/playWarp(onPeak) are thin wrappers so
-- the call sites below are unchanged.
-- Load WarpEffect (ReplicatedStorage.DinosaurRealm.WarpEffect). pcall + timeout so a missing/unsynced module
-- can NEVER hard-break the wormhole: if it's absent we still teleport (no cinematic) and warn loudly so you
-- know to add it. THIS is the module that owns the exact warp cinematic + the 3 warp sounds.
local WarpEffect
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("WarpEffect", 10))
	end)
	WarpEffect = ok and mod or nil
	if not WarpEffect then
		warn("[Wormhole] WarpEffect module NOT found in ReplicatedStorage.DinosaurRealm — the warp cinematic + "
			.. "sounds will NOT play. Make sure WarpEffect.luau is synced there (rojo path: src/shared/WarpEffect.luau).")
	end
end
local function playWarpSound() if WarpEffect then WarpEffect.playSound() end end
local function playWarp(onPeak)
	if WarpEffect then
		WarpEffect.play(onPeak)          -- exact reference cinematic + warp/whoosh/landing sounds
	elseif onPeak then
		task.spawn(onPeak)               -- fallback: still teleport even without the cinematic
	end
end

-- ===== OPEN / CLOSE / WARP =====
local function refreshMenu()
	for _, fn in pairs(rowRefreshers) do
		fn()
	end
end

local function openMenu()
	if warping then
		return
	end
	refreshMenu()
	-- log: menu opened + the visited list (in travel order)
	local names = {}
	for slot = 1, ISLAND_COUNT do
		if isVisited(slot) then
			table.insert(names, ISLAND_NAMES[SLOT_TO_ISLAND[slot]])
		end
	end
	print(("[Wormhole] menu opened by %s (visited: %s)"):format(player.Name, (#names > 0) and table.concat(names, ", ") or "none"))
	gui.Enabled = true
	panelScale.Scale = WORMHOLE_POP
	pcall(function()
		TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = WORMHOLE_REST }):Play()
	end)
end

closeMenu = function()
	gui.Enabled = false
end

-- ===== GROUNDED GATE =====
-- The wormhole only works with your feet on an island — no travelling mid-flight. Uses the same airborne
-- signal FlightService/JupiterTask use (Humanoid.FloorMaterial == Air). The server re-checks this too.
local function isGrounded()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
end
-- "land first" toast — its own ScreenGui so it shows over the closed menu (mirrors the travel-error toast below).
local landToastGui = Instance.new("ScreenGui")
landToastGui.Name = "WormholeLandFirst"; landToastGui.ResetOnSpawn = false; landToastGui.IgnoreGuiInset = true
landToastGui.DisplayOrder = 9500; landToastGui.Enabled = false; landToastGui.Parent = PlayerGui
local landToast = Instance.new("TextLabel")
landToast.AnchorPoint = Vector2.new(0.5, 0); landToast.Position = UDim2.new(0.5, 0, 0, 90); landToast.Size = UDim2.new(0, 470, 0, 52)
landToast.BackgroundColor3 = Color3.fromRGB(14, 20, 44); landToast.BackgroundTransparency = 0.05
landToast.Font = Enum.Font.FredokaOne; landToast.Text = "\u{1FA90}  Land on an island to use the wormhole!"
landToast.TextColor3 = Color3.fromRGB(210, 226, 255); landToast.TextScaled = true; landToast.Parent = landToastGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = landToast
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(90, 150, 255); s.Thickness = 2; s.Parent = landToast
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = landToast
end
local landTok = 0
local function showLandFirst()
	landTok += 1; local mine = landTok
	landToastGui.Enabled = true
	task.delay(2.6, function() if landTok == mine then landToastGui.Enabled = false end end)
end

local function warpTo(slot)
	if warping then
		return
	end
	if not isVisited(slot) then
		return -- locked; not tappable, but guard anyway
	end
	if not isGrounded() then
		closeMenu()
		showLandFirst() -- feet must be on an island — block before any sound/tunnel plays
		return
	end
	warping = true
	closeMenu()
	playWarpSound() -- warp sound fires ONCE here: destination picked → teleport firing / transition beginning
	playWarp(function()
		-- Server validates the slot (<= HighestSlot) + grounded and moves the character (mid-warp, hidden by the
		-- tunnel + flash). We send the island MODEL number the server places by.
		if RequestWarp then
			local islandNum = SLOT_TO_ISLAND[slot]
			local ok, result = pcall(function()
				return RequestWarp:InvokeServer(islandNum)
			end)
			if not (ok and type(result) == "table" and result.ok) then
				-- Server refused (shouldn't happen for a visited island) — the warp still eases out where they are.
			end
		end
	end)
	warping = false
end

-- Brief "couldn't travel" toast — its OWN ScreenGui so it shows even with the menu closed + the warp gui torn down.
local errToastGui = Instance.new("ScreenGui")
errToastGui.Name = "WormholeTravelError"
errToastGui.ResetOnSpawn = false
errToastGui.IgnoreGuiInset = true
errToastGui.DisplayOrder = 9500
errToastGui.Enabled = false
errToastGui.Parent = PlayerGui
local errToast = Instance.new("TextLabel")
errToast.AnchorPoint = Vector2.new(0.5, 0)
errToast.Position = UDim2.new(0.5, 0, 0, 90)
errToast.Size = UDim2.new(0, 420, 0, 52)
errToast.BackgroundColor3 = Color3.fromRGB(40, 16, 24)
errToast.BackgroundTransparency = 0.05
errToast.Font = Enum.Font.FredokaOne
errToast.Text = "Couldn't travel \u{2014} try again"
errToast.TextColor3 = Color3.fromRGB(255, 212, 212)
errToast.TextScaled = true
errToast.Parent = errToastGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = errToast
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(220, 90, 90); s.Thickness = 2; s.Parent = errToast
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = errToast
end
local errTok = 0
local function showTravelError()
	errTok += 1
	local mine = errTok
	errToastGui.Enabled = true
	task.delay(2.6, function()
		if errTok == mine then
			errToastGui.Enabled = false
		end
	end)
end

-- Cross-place teleport to the FOOD ISLANDS place. Plays the SAME warp sound + tunnel transition, then at the peak
-- (fully covered) asks the SERVER — which re-validates the island index 1–14 — to TeleportAsync. On success the
-- player is teleported away mid-warp; on failure we're still here, so we surface the message and never leave them
-- stuck (the menu just closed; the warp eased back out).
local function warpToRealm(realm)
	if warping then
		return
	end
	if not isGrounded() then
		closeMenu()
		showLandFirst() -- same grounded gate as the island warp
		return
	end
	warping = true
	closeMenu()
	playWarpSound()
	local failed = false
	playWarp(function()
		if not RequestRealmWarp then failed = true; return end
		local ok, result = pcall(function()
			return RequestRealmWarp:InvokeServer(realm)
		end)
		if not (ok and type(result) == "table" and result.ok) then
			failed = true
		end
	end)
	if failed then
		showTravelError()
	end
	warping = false
end

-- Async teleport failure (server accepted it, then it failed to init) — clear the guard + tell the player.
if RealmWarpFailed then
	RealmWarpFailed.OnClientEvent:Connect(function()
		warping = false
		showTravelError()
	end)
end

closeBtn.Activated:Connect(closeMenu)
-- NO click-outside-to-close: the backdrop covers the whole screen, so a stray tap anywhere
-- shut the travel menu and it read as closing at random -- worse here than elsewhere, since
-- a mis-tap while picking a destination loses your place in the island list. It still
-- SWALLOWS the click (Active, so nothing behind it reacts) -- it just no longer closes.
-- Explicit actions only: the X button, picking a destination, or its own toggle.
openSignal.Event:Connect(openMenu)

-- Wire each island row's tap to warpTo now that it exists (replaces the placeholder in the build loop).
for slot = 1, ISLAND_COUNT do
	local row = scroll:FindFirstChild("Slot" .. slot)
	if row and row:IsA("TextButton") then
		row.Activated:Connect(function()
			if not warping and isVisited(slot) then
				warpTo(slot)
			end
		end)
	end
end

-- Wire the FOOD REALM + SPACE REALM buttons → cross-place teleport to the other realms.
do
	local foodRow = scroll:FindFirstChild("FoodRealm")
	if foodRow and foodRow:IsA("TextButton") then
		foodRow.Activated:Connect(function()
			if not warping then warpToRealm("Food") end
		end)
	end
	local spaceRow = scroll:FindFirstChild("SpaceRealm")
	if spaceRow and spaceRow:IsA("TextButton") then
		spaceRow.Activated:Connect(function()
			if not warping then warpToRealm("Space") end
		end)
	end
	local candyRow = scroll:FindFirstChild("CandyRealm")
	if candyRow and candyRow:IsA("TextButton") then
		candyRow.Activated:Connect(function()
			if not warping then warpToRealm("Candy") end
		end)
	end
end

print("[Wormhole][client] online (Dino Realm) — island travel menu + warp transition")
print("[WormholeSound] warp sound fires on destination-select → teleport.")
print("[Wormhole] destinations: 13 Dino islands (visited-gated) + Food / Space / Candy Realm cross-place hops.")
