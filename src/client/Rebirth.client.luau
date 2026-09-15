--[[
	Rebirth.client.luau  (StarterPlayerScripts.DinosaurRealmClient.Rebirth)

	The REBIRTH menu. Opened from the MORE+ menu's "Rebirth" row, which :Fire()s the shared "OpenRebirth"
	BindableEvent (and by _G.toggleRebirth, which MenuBackButton's BACK row calls). The server
	(Rebirth.server.luau) is authoritative: this only presents the replicated attributes
	(Rebirths / RebirthMult / HighestSlot) and calls DoRebirth.

	===== THE LOOK (design brief) =====
	A premium low-poly / cartoon adventure panel: rich dark jungle-green body, bright lime, gold, blue and
	orange accents, chunky 3px outlines, offset drop shadows for depth, big readable type. The header is a
	little scene -- sky, clouds, a mountain range and trees -- built from plain rounded/rotated Frames, so
	it costs no images and scales with everything else. Sections, in order, are exactly:
	    header  ->  REBIRTHS + COIN MULTIPLIER tiles  ->  SUMMIT PROGRESS  ->  WHAT A REBIRTH DOES  ->  button
	Nothing is decorative for its own sake: every shape is one Frame with a corner and an outline.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local DinoShared = ReplicatedStorage:WaitForChild("DinosaurRealm")
local IslandOrder = require(DinoShared:WaitForChild("IslandOrder"))
local TOP_SLOT = IslandOrder.COUNT

-- these mirror Rebirth.server.luau; display only, the server is the truth
local BONUS_PER_REBIRTH = 0.25
local COIN_BONUS_PER_REBIRTH = 125

local openSignal = ReplicatedStorage:FindFirstChild("OpenRebirth")
if not openSignal then
	openSignal = Instance.new("BindableEvent"); openSignal.Name = "OpenRebirth"; openSignal.Parent = ReplicatedStorage
end
local rebirthRemotes = ReplicatedStorage:WaitForChild("RebirthRemotes", 30)
local DoRebirth = rebirthRemotes and rebirthRemotes:WaitForChild("DoRebirth", 30)

-- ===== PALETTE =====
local BODY       = Color3.fromRGB(24, 52, 36)     -- deep jungle green, the panel
local BODY_LINE  = Color3.fromRGB(12, 30, 20)     -- the panel's own outline (darkest green)
local TILE       = Color3.fromRGB(36, 74, 50)     -- section tiles, a step lighter than the body
local TILE_LINE  = Color3.fromRGB(14, 34, 22)     -- chunky tile outlines
local WELL       = Color3.fromRGB(16, 36, 24)     -- recessed things (the bar track)
local LIME       = Color3.fromRGB(156, 232, 46)
local LIME_DEEP  = Color3.fromRGB(96, 178, 30)
local GOLD       = Color3.fromRGB(255, 194, 58)
local GOLD_DEEP  = Color3.fromRGB(214, 140, 22)
local BLUE       = Color3.fromRGB(61, 165, 255)
local BLUE_DEEP  = Color3.fromRGB(28, 110, 200)
local ORANGE     = Color3.fromRGB(255, 140, 58)
local ORANGE_DEEP= Color3.fromRGB(210, 92, 24)
local CREAM      = Color3.fromRGB(255, 250, 235)
local MUTED      = Color3.fromRGB(178, 214, 176)
local LOCK_FILL  = Color3.fromRGB(64, 80, 66)
local LOCK_LINE  = Color3.fromRGB(28, 40, 30)
local RED        = Color3.fromRGB(232, 72, 64)
local RED_DEEP   = Color3.fromRGB(160, 36, 30)
local INK        = Color3.fromRGB(8, 20, 12)
local SKY        = Color3.fromRGB(104, 184, 240)
local SKY_TOP    = Color3.fromRGB(64, 138, 222)
local MTN_FAR    = Color3.fromRGB(58, 108, 150)
local MTN_NEAR   = Color3.fromRGB(46, 92, 72)
local SNOW       = Color3.fromRGB(240, 248, 255)
local TREE       = Color3.fromRGB(52, 150, 62)
local TREE_DARK  = Color3.fromRGB(32, 108, 46)
local TRUNK      = Color3.fromRGB(112, 74, 40)

local LINE_W = 3   -- the one outline weight on the panel: chunky, cartoon

-- ===== builders =====
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function outline(o, col, t, tr)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or LINE_W; s.Transparency = tr or 0
	s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = o; return s
end
local function textOutline(l, t) local s = outline(l, INK, t or 2); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; return s end
local function maxsize(l, n) local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = n; c.Parent = l; return c end
-- A UIGradient MULTIPLIES with the object's BackgroundColor3. Colouring both (a dark fill under a dark
-- gradient) squares the colour and turns the whole panel near-black, so the base goes WHITE and the
-- gradient alone decides the colour. Anything recoloured later while its gradient is on must stay white too.
local WHITE_BASE = Color3.new(1, 1, 1)
local function vgrad(o, a, b) o.BackgroundColor3 = WHITE_BASE; local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(a, b); g.Parent = o; return g end
local function frame(parent, props)
	local f = Instance.new("Frame"); f.BorderSizePixel = 0; f.ZIndex = 2
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent; return f
end
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.TextScaled = true; l.TextColor3 = CREAM; l.Font = Enum.Font.FredokaOne
	l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 4
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent; return l
end
-- A drop shadow is one dark rounded frame sitting a few px down-right behind the thing. Chunky and cheap.
local function shadowed(parent, x, y, w, h, r, fill, line)
	local sh = frame(parent, { Name = "Shadow", Position = UDim2.fromOffset(x + 4, y + 5), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BackgroundTransparency = 0.55, ZIndex = 1 })
	corner(sh, r)
	local f = frame(parent, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = fill, ZIndex = 2 })
	corner(f, r); outline(f, line)
	vgrad(f, Color3.fromRGB(52, 102, 68), Color3.fromRGB(34, 72, 48))
	-- LAYERED BORDER: a thin lighter inner line just inside the dark outline, plus a soft highlight along
	-- the top edge, so every tile reads as a raised slab rather than a flat rectangle.
	local inner = frame(f, { Name = "InnerLine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, ZIndex = 3 })
	corner(inner, math.max(4, r - 3)); outline(inner, Color3.fromRGB(96, 150, 104), 1.5, 0.55)
	local hi = frame(f, { Name = "TopLight", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(1, -24, 0, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.78, ZIndex = 3 })
	corner(hi, 2)
	return f
end
-- A round icon badge: coloured disc, dark outline, emoji on top.
local function badge(parent, x, y, d, col, colDeep, emoji, size)
	local b = frame(parent, { Name = "Badge", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d), BackgroundColor3 = col, ZIndex = 4 })
	corner(b, 999); outline(b, INK, 2.5); vgrad(b, col, colDeep)
	local l = label(b, { Name = "Icon", Text = emoji, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, ZIndex = 5 })
	maxsize(l, size or math.floor(d * 0.6))
	return b
end
local function heading(parent, x, y, w, text, col)
	-- section headings are chunky WHITE with a dark outline: they have to read over a green tile at a glance
	local l = label(parent, { Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 22), TextColor3 = col or CREAM, Font = Enum.Font.FredokaOne })
	maxsize(l, 19); textOutline(l, 2); return l
end

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "RebirthGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 155; gui.Enabled = false
gui.Parent = PlayerGui

local backdrop = Instance.new("TextButton")
backdrop.Size = UDim2.new(1, 0, 1, 0); backdrop.BackgroundColor3 = Color3.new(0, 0, 0); backdrop.BackgroundTransparency = 0.5
backdrop.AutoButtonColor = false; backdrop.Text = ""; backdrop.Active = true; backdrop.Parent = gui

-- the panel's own drop shadow, then the panel
local PW, PH = 700, 538 -- HUB PARITY: the Rewards hub (DailyStreak.client) is 700x538 at (0.5,-45); this matches it exactly -- a size up from the other hubs: bigger type, taller cards, still one screen on a phone via ResponsiveScale
-- THE PANEL IS CREATED FIRST, THE SHADOW SECOND. MenuBackButton.client finds "the panel" as the first
-- big Frame child of this ScreenGui; when the shadow came first it adopted the SHADOW, saw no back button
-- in it, and injected a second BACK there (top-left). Creation order is what it keys on; ZIndex still draws
-- the shadow underneath. The shadow is also an ImageLabel, not a Frame, so it can never be mistaken again.
local panel = frame(gui, { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -45), Size = UDim2.fromOffset(PW, PH), BackgroundColor3 = BODY, ClipsDescendants = true, ZIndex = 2 })
corner(panel, 24); outline(panel, BODY_LINE, 4)
local panelShadow = Instance.new("ImageLabel")
panelShadow.Name = "PanelShadow"; panelShadow.AnchorPoint = Vector2.new(0.5, 0.5); panelShadow.Position = UDim2.new(0.5, 6, 0.5, -45 + 8)
panelShadow.Size = UDim2.fromOffset(PW, PH); panelShadow.BackgroundColor3 = INK; panelShadow.BackgroundTransparency = 0.5
panelShadow.BorderSizePixel = 0; panelShadow.ZIndex = 1; panelShadow.Parent = gui
corner(panelShadow, 24)
vgrad(panel, Color3.fromRGB(24, 52, 36), Color3.fromRGB(14, 34, 22))

-- device scale (the shadow rides the same scale so it never drifts from the panel)
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel
local shadowScale = Instance.new("UIScale"); shadowScale.Parent = panelShadow
local function restScale() return player:GetAttribute("ResponsiveScale") or 1 end
local function applyScale(v) panelScale.Scale = v; shadowScale.Scale = v end
applyScale(restScale())
player:GetAttributeChangedSignal("ResponsiveScale"):Connect(function() if gui.Enabled then applyScale(restScale()) end end)
gui:GetPropertyChangedSignal("Enabled"):Connect(function() if gui.Enabled then applyScale(restScale()) end end)

-- ============================================================================
-- HEADER: a sky with clouds, a mountain range, trees, the title on a plaque
-- ============================================================================
local HEADER_H = 88
local header = frame(panel, { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = SKY, ClipsDescendants = true, ZIndex = 2 })
corner(header, 24)
vgrad(header, SKY_TOP, SKY)
-- square off the header's bottom corners (the panel corner only belongs on top)
frame(header, { Position = UDim2.new(0, 0, 1, -30), Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = SKY, ZIndex = 2 })

-- clouds: three overlapping discs each
local function cloud(x, y, s, z)
	for _, part in ipairs({ { 0, 6, 1.0 }, { 0.55, 0, 1.15 }, { 1.2, 8, 0.85 } }) do
		local d = math.floor(s * part[3])
		local c = frame(header, { Position = UDim2.fromOffset(x + math.floor(s * part[1]), y + part[2] + (s - d)), Size = UDim2.fromOffset(d, d), BackgroundColor3 = SNOW, BackgroundTransparency = 0.08, ZIndex = z })
		corner(c, 999)
	end
end
cloud(130, 8, 22, 3); cloud(300, 4, 18, 3); cloud(470, 14, 26, 3); cloud(600, 4, 16, 3); cloud(690, 12, 22, 3)
-- SUN: a warm disc with a soft halo, top-left, so the sky is not an empty field of blue
do
	local halo = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(62, 30), Size = UDim2.fromOffset(74, 74), BackgroundColor3 = GOLD, BackgroundTransparency = 0.72, ZIndex = 2 })
	corner(halo, 999)
	local sun = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(62, 30), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = GOLD, ZIndex = 3 })
	corner(sun, 999); outline(sun, INK, 2.5); vgrad(sun, Color3.fromRGB(255, 232, 120), GOLD_DEEP)
end

-- NO ROTATED FRAMES ANYWHERE. Roblox does not clip a rotated GuiObject with ClipsDescendants, so the
-- earlier rotated-square mountains and tree canopies spilled out of the header as giant diamonds over the
-- stat tiles. Everything in this scene is now an unrotated rounded rectangle or disc, and the header clips
-- the lot cleanly.

-- mountains: each peak is a stack of ever-narrower rounded bars (a stepped low-poly pyramid), snow on top.
local function peak(cx, baseY, w, h, col, z)
	local steps = 5
	for i = 1, steps do
		local k = (steps - i + 1) / steps          -- 1.0 at the base .. 0.2 at the tip
		local bw = math.floor(w * k)
		local bh = math.ceil(h / steps) + 4          -- overlap so no seams show
		local by = baseY - math.floor(h * (i / steps))
		local bar = frame(header, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx, by), Size = UDim2.fromOffset(bw, bh), BackgroundColor3 = (i == steps) and SNOW or col, ZIndex = z })
		corner(bar, 8)
	end
end
for _, p in ipairs({ { 50, 96, 180, 58 }, { 220, 96, 230, 74 }, { 410, 96, 200, 64 }, { 580, 96, 230, 80 }, { 700, 96, 170, 54 } }) do peak(p[1], p[2], p[3], p[4], MTN_FAR, 4) end
for _, p in ipairs({ { 10, 102, 160, 46 }, { 160, 102, 190, 54 }, { 350, 102, 210, 50 }, { 530, 102, 180, 52 }, { 680, 102, 170, 44 } }) do peak(p[1], p[2], p[3], p[4], MTN_NEAR, 6) end

-- trees along the bottom edge: a trunk and two stacked round canopies
local function tree(x, h, z)
	local trunk = frame(header, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, x, 1, 2), Size = UDim2.fromOffset(8, h), BackgroundColor3 = TRUNK, ZIndex = z })
	corner(trunk, 3); outline(trunk, INK, 2)
	for i, k in ipairs({ 1.0, 0.7 }) do
		local d = math.floor(h * 0.95 * k)
		local c = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x, 1, -h + math.floor(h * 0.1) - (i - 1) * math.floor(h * 0.4)), Size = UDim2.fromOffset(d, d), BackgroundColor3 = (i == 1) and TREE_DARK or TREE, ZIndex = z + i })
		corner(c, 999); outline(c, INK, 2)
	end
end
for _, t in ipairs({ { 22, 28 }, { 58, 40 }, { 104, 26 }, { 140, 34 }, { 178, 24 }, { 580, 30 }, { 618, 42 }, { 660, 26 }, { 700, 36 }, { 738, 28 } }) do tree(t[1], t[2], 8) end
-- THE CLIMB, drawn into the scenery: a trail of footholds rising from the trees on the left up to a flag
-- planted on the tallest far peak. Discs and rectangles only.
do
	local flagX, flagY = 530, 14
	for i, pt in ipairs({ { 200, 78 }, { 250, 70 }, { 300, 62 }, { 350, 54 }, { 400, 46 }, { 450, 38 }, { 490, 30 }, { 515, 24 } }) do
		local d = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pt[1], pt[2]), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = CREAM, BackgroundTransparency = 0.35, ZIndex = 7 })
		corner(d, 999)
	end
	local pole = frame(header, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(flagX, flagY), Size = UDim2.fromOffset(4, 26), BackgroundColor3 = INK, ZIndex = 8 })
	corner(pole, 2)
	local cloth = frame(header, { Position = UDim2.fromOffset(flagX + 2, flagY), Size = UDim2.fromOffset(20, 13), BackgroundColor3 = ORANGE, ZIndex = 9 })
	corner(cloth, 3); outline(cloth, INK, 2)
end
-- a dino on the ridge, right of the plaque: the one cartoon icon the scene gets
do
	local dino = label(header, { Text = "\u{1F996}", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, 555, 1, -4), Size = UDim2.fromOffset(40, 40), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, ZIndex = 11 })
	maxsize(dino, 32)
end

-- ground strip so the scene sits on the panel body
frame(header, { Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = LIME_DEEP, ZIndex = 12 })
frame(header, { Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, ZIndex = 12 })

-- the title plaque, centred over the scene, with its own drop shadow
local plaqueShadow = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 5, 0.5, 0), Size = UDim2.fromOffset(300, 58), BackgroundColor3 = INK, BackgroundTransparency = 0.45, ZIndex = 13 })
corner(plaqueShadow, 18)
local plaque = frame(header, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -6), Size = UDim2.fromOffset(300, 58), BackgroundColor3 = ORANGE, ZIndex = 14 })
corner(plaque, 18); outline(plaque, INK, 3.5); vgrad(plaque, ORANGE, ORANGE_DEEP)
badge(plaque, 7, 6, 46, LIME, LIME_DEEP, "\u{1F504}", 24)
local title = label(plaque, { Name = "Title", Text = "REBIRTH", Position = UDim2.fromOffset(60, 3), Size = UDim2.fromOffset(232, 32), TextColor3 = CREAM, ZIndex = 15 })
maxsize(title, 30); textOutline(title, 3)
local subtitle = label(plaque, { Name = "Subtitle", Text = "Reset the climb. Keep the power.", Position = UDim2.fromOffset(60, 36), Size = UDim2.fromOffset(232, 18), TextColor3 = Color3.fromRGB(70, 30, 6), Font = Enum.Font.GothamBold, ZIndex = 15 })
maxsize(subtitle, 14)

-- close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"; closeBtn.AnchorPoint = Vector2.new(0, 0); closeBtn.Position = UDim2.new(1, -60, 0, 22); closeBtn.Size = UDim2.fromOffset(46, 42) -- the Rewards hub's X, to the pixel
closeBtn.BackgroundColor3 = RED; closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"; closeBtn.TextColor3 = INK; closeBtn.TextScaled = true; closeBtn.AutoButtonColor = false; closeBtn.ZIndex = 16; closeBtn.Parent = header
corner(closeBtn, 14); outline(closeBtn, INK, 3); vgrad(closeBtn, RED, RED_DEEP); maxsize(closeBtn, 26) -- a BLACK X on the red disc, by request

-- ============================================================================
-- BACK: top-right of the header, immediately LEFT of the X with an 8px gap -- the same spot the Rewards hub
-- (DailyStreak.client) puts its BACK, so the two hubs read the same way. Warm brown-orange, thick dark outline, a top highlight
-- and its own soft shadow, with a white left arrow. Named RG_Back so MenuBackButton.client sees a back button
-- already exists here and does not inject its own beside the X. Click = close this menu, reopen MORE+ (the
-- same two steps the shared script performs), debounced so a double-tap cannot close-and-reopen.
-- ============================================================================
local BACK_BROWN, BACK_BROWN_DEEP = Color3.fromRGB(196, 118, 52), Color3.fromRGB(132, 74, 30)
local backShadow = frame(header, { Name = "BackShadow", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(1, -114 + 3, 0, 22 + 4), Size = UDim2.fromOffset(46, 42), BackgroundColor3 = INK, BackgroundTransparency = 0.5, ZIndex = 15 })
corner(backShadow, 14)
local backBtn = Instance.new("TextButton")
backBtn.Name = "RG_Back"; backBtn.AnchorPoint = Vector2.new(0, 0); backBtn.Position = UDim2.new(1, -114, 0, 22); backBtn.Size = UDim2.fromOffset(46, 42) -- the Rewards hub's BACK, to the pixel
backBtn.BackgroundColor3 = BACK_BROWN; backBtn.AutoButtonColor = false; backBtn.Text = ""; backBtn.ZIndex = 16; backBtn.Parent = header
corner(backBtn, 14); outline(backBtn, INK, 3); vgrad(backBtn, BACK_BROWN, BACK_BROWN_DEEP)
do local hl = frame(backBtn, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -16, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, ZIndex = 17 }); corner(hl, 2) end
-- the arrow is a plain "<" glyph in the chunky face: white, dark outline, dead centre
local backArrow = label(backBtn, { Text = "<", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = CREAM, Font = Enum.Font.FredokaOne, ZIndex = 18 })
maxsize(backArrow, 28); textOutline(backArrow, 2)
do
	local sc = Instance.new("UIScale"); sc.Parent = backBtn
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	backBtn.MouseEnter:Connect(function() TweenService:Create(sc, ti, { Scale = 1.06 }):Play() end)
	backBtn.MouseLeave:Connect(function() TweenService:Create(sc, ti, { Scale = 1 }):Play() end)
	backBtn.MouseButton1Down:Connect(function() TweenService:Create(sc, TweenInfo.new(0.06), { Scale = 0.94 }):Play() end)
	backBtn.MouseButton1Up:Connect(function() TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end)
end

-- ============================================================================
-- BODY
-- ============================================================================
local PAD, GAP = 20, 12
local INNER_W = PW - PAD * 2
local y = HEADER_H + 12

-- ---- REBIRTHS + COIN MULTIPLIER ----
local STAT_H = 80
local TILE_W = math.floor((INNER_W - GAP) / 2)

local countTile = shadowed(panel, PAD, y, TILE_W, STAT_H, 18, TILE, TILE_LINE)
badge(countTile, 12, 12, 56, ORANGE, ORANGE_DEEP, "\u{1F504}", 28)
heading(countTile, 80, 10, 140, "REBIRTHS")
-- THE "0" IS THE HERO OF THIS TILE: it sits in its own dark well with a lime rim, oversized, so the count
-- reads first and the label second.
local countGlow = frame(countTile, { Name = "Glow", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(110, 68), BackgroundColor3 = ORANGE, BackgroundTransparency = 0.72, ZIndex = 3 })
corner(countGlow, 22)
local countWell = frame(countTile, { Name = "Well", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(98, 58), BackgroundColor3 = WELL, ZIndex = 4 })
corner(countWell, 16); outline(countWell, GOLD, 3)
vgrad(countWell, Color3.fromRGB(28, 54, 36), Color3.fromRGB(12, 28, 18))
local countLbl = label(countWell, { Name = "Count", Text = "0", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = ORANGE, ZIndex = 5 })
maxsize(countLbl, 48); textOutline(countLbl, 3.5)
task.spawn(function() -- the glow breathes, slowly, so the tile has a pulse without moving anything
	local up = true
	while countGlow.Parent do
		if gui.Enabled then TweenService:Create(countGlow, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = up and 0.6 or 0.82 }):Play(); up = not up end
		task.wait(1.4)
	end
end)
local countSub = label(countTile, { Text = "times reborn", Position = UDim2.fromOffset(80, 36), Size = UDim2.fromOffset(140, 22), TextColor3 = CREAM, Font = Enum.Font.GothamBold })
maxsize(countSub, 15); textOutline(countSub, 1.5)

local multTile = shadowed(panel, PAD + TILE_W + GAP, y, TILE_W, STAT_H, 18, TILE, TILE_LINE)
badge(multTile, 12, 12, 56, GOLD, GOLD_DEEP, "\u{1F4B0}", 28)
heading(multTile, 80, 10, 190, "COIN MULTIPLIER")
local multGlow = frame(multTile, { Name = "Glow", Position = UDim2.fromOffset(74, 28), Size = UDim2.fromOffset(128, 48), BackgroundColor3 = LIME, BackgroundTransparency = 0.8, ZIndex = 3 })
corner(multGlow, 18)
local multLbl = label(multTile, { Name = "Mult", Text = "x1.00", Position = UDim2.fromOffset(80, 31), Size = UDim2.fromOffset(120, 42), TextColor3 = LIME })
maxsize(multLbl, 40); textOutline(multLbl, 3)
-- "Next: x1.25" as a blue pill so it reads as the upgrade on offer
local nextPill = frame(multTile, { Name = "Next", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 40), Size = UDim2.fromOffset(108, 30), BackgroundColor3 = BLUE, ZIndex = 4 })
corner(nextPill, 10); outline(nextPill, INK, 2.5); vgrad(nextPill, BLUE, BLUE_DEEP)
do local hl = frame(nextPill, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(1, -16, 0, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, ZIndex = 5 }); corner(hl, 2) end
local nextLbl = label(nextPill, { Text = "Next: x1.25", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
maxsize(nextLbl, 15); textOutline(nextLbl, 2)
y += STAT_H + GAP

-- ---- SUMMIT PROGRESS ----
local PROG_H = 92
local progTile = shadowed(panel, PAD, y, INNER_W, PROG_H, 18, TILE, TILE_LINE)
badge(progTile, 12, 9, 36, BLUE, BLUE_DEEP, "\u{1F3D4}", 20)
heading(progTile, 58, 11, 200, "SUMMIT PROGRESS")
local progText = label(progTile, { Name = "Where", Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 11), Size = UDim2.fromOffset(220, 24), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = LIME })
maxsize(progText, 17); textOutline(progText, 2)
local track = frame(progTile, { Name = "Track", Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -28, 0, 36), BackgroundColor3 = WELL, ZIndex = 3 })
corner(track, 18); outline(track, INK, 3)
do -- inner shade at the top of the trough so the fill sits DOWN in it
	local sh = frame(track, { Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.7, ZIndex = 3 })
	corner(sh, 18)
end
local fill = frame(track, { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = LIME, ZIndex = 4 })
corner(fill, 18); outline(fill, INK, 2)
do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(196, 250, 96)), ColorSequenceKeypoint.new(0.5, LIME), ColorSequenceKeypoint.new(1, LIME_DEEP) }); g.Parent = fill end
fill.BackgroundColor3 = WHITE_BASE -- the three-stop gradient alone colours the fill
do -- soft glow around the fill, a child so it grows with it
	local glow = frame(fill, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 8, 1, 8), BackgroundColor3 = LIME, BackgroundTransparency = 0.7, ZIndex = 3 })
	corner(glow, 22)
end
do -- gloss strip across the top of the fill; a child, so it grows with it and never floats over empty track
	local gl = frame(fill, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -18, 0, 9), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.62, ZIndex = 5 })
	corner(gl, 4)
end
-- THE JOURNEY: 13 checkpoints sit ON the path, one per island, evenly spaced. Reached ones are lime, the
-- one you are on is a bigger gold disc with a halo, the rest are subdued grey -- so the bar reads as a climb
-- with stops, not a percentage.
local checkpoints = {}
for i = 1, TOP_SLOT - 1 do -- the 13th stop IS the summit: the gold star badge below stands in for it
	local cx = (i - 0.5) / TOP_SLOT
	local halo = frame(track, { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cx, 0, 0.5, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = GOLD, BackgroundTransparency = 1, ZIndex = 6 })
	corner(halo, 999)
	local cp = frame(track, { Name = "Checkpoint" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cx, 0, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = LOCK_FILL, ZIndex = 7 })
	corner(cp, 999); outline(cp, INK, 2)
	checkpoints[i] = { disc = cp, halo = halo }
end
-- the count sits UNDER the path in its own pill, centred, so it never fights the checkpoints
local countPill = frame(progTile, { Name = "CountPill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(150, 24), BackgroundColor3 = WELL, ZIndex = 4 })
corner(countPill, 12); outline(countPill, INK, 2)
local progCount = label(countPill, { Name = "Count", Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
maxsize(progCount, 16); textOutline(progCount, 2)
-- the summit flag at the far end of the bar: the thing the fill is climbing towards
local flagRing = frame(progTile, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 14 + math.floor((INNER_W - 28) * (TOP_SLOT - 0.5) / TOP_SLOT), 0, 62), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = GOLD, BackgroundTransparency = 0.7, ZIndex = 6 })
corner(flagRing, 999)
local flag = frame(progTile, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 14 + math.floor((INNER_W - 28) * (TOP_SLOT - 0.5) / TOP_SLOT), 0, 62), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = GOLD, ZIndex = 7 })
corner(flag, 999); outline(flag, INK, 3); vgrad(flag, Color3.fromRGB(255, 226, 120), GOLD_DEEP)
do local fl = label(flag, { Text = "\u{2B50}", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, ZIndex = 8 }); maxsize(fl, 17) end
y += PROG_H + GAP

-- ---- WHAT A REBIRTH DOES ----
local BTN_H, BTN_MARGIN = 60, 14
local LIST_H = PH - y - BTN_H - BTN_MARGIN - GAP
local listTile = shadowed(panel, PAD, y, INNER_W, LIST_H, 18, TILE, TILE_LINE)
heading(listTile, 14, 10, 300, "WHAT A REBIRTH DOES")
local ROWS = {
	{ col = ORANGE, deep = ORANGE_DEEP, icon = "\u{1F501}", text = "Island progress resets to Nesting Nook" },
	{ col = GOLD,   deep = GOLD_DEEP,   icon = "\u{1FA99}", text = "" }, -- filled by refresh()
	{ col = LIME,   deep = LIME_DEEP,   icon = "\u{1F996}", text = "Pets, skins, tokens and gut stay yours" },
}
local rowLabels = {}
do
	-- EACH BENEFIT IS ITS OWN ROW: a darker rounded strip, a big coloured badge, one line of large type.
	local top, gap = 34, 6
	local rowH = math.floor((LIST_H - top - 12 - gap * (#ROWS - 1)) / #ROWS)
	for i, r in ipairs(ROWS) do
		local ry = top + (i - 1) * (rowH + gap)
		local row = frame(listTile, { Name = "Row" .. i, Position = UDim2.fromOffset(12, ry), Size = UDim2.new(1, -24, 0, rowH), BackgroundColor3 = WELL, ZIndex = 3 })
		corner(row, 12); outline(row, INK, 2)
		-- tinted toward the row's own colour, with a solid accent stripe down the left edge
		do local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(r.deep:Lerp(WELL, 0.72), WELL); g.Parent = row; row.BackgroundColor3 = WHITE_BASE end
		local stripe = frame(row, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = r.col, ZIndex = 4 })
		corner(stripe, 12)
		local bd = math.min(rowH - 6, 40)
		badge(row, 12, math.floor((rowH - bd) / 2), bd, r.col, r.deep, r.icon, math.floor(bd * 0.58))
		local tx = label(row, { Text = r.text, Position = UDim2.fromOffset(bd + 24, 0), Size = UDim2.new(1, -(bd + 34), 1, 0), TextColor3 = CREAM, Font = Enum.Font.FredokaOne, TextWrapped = true, ZIndex = 5 })
		maxsize(tx, 19); textOutline(tx, 2.5)
		rowLabels[i] = tx
	end
end

-- ---- THE BUTTON ----
local btnShadow = frame(panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 4, 1, -BTN_MARGIN + 5), Size = UDim2.new(1, -PAD * 2, 0, BTN_H), BackgroundColor3 = INK, BackgroundTransparency = 0.5, ZIndex = 2 })
corner(btnShadow, 20)
local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Name = "RebirthButton"; rebirthBtn.AnchorPoint = Vector2.new(0.5, 1); rebirthBtn.Position = UDim2.new(0.5, 0, 1, -BTN_MARGIN); rebirthBtn.Size = UDim2.new(1, -PAD * 2, 0, BTN_H)
rebirthBtn.BackgroundColor3 = LOCK_FILL; rebirthBtn.Font = Enum.Font.FredokaOne; rebirthBtn.Text = ""; rebirthBtn.TextColor3 = CREAM
rebirthBtn.TextScaled = true; rebirthBtn.AutoButtonColor = false; rebirthBtn.ZIndex = 3; rebirthBtn.Parent = panel
corner(rebirthBtn, 20)
local btnLine = outline(rebirthBtn, LOCK_LINE, 3.5)
-- a darker band along the bottom while LOCKED: the button reads as sunk into the panel, not raised off it
local btnInset = frame(rebirthBtn, { Name = "Inset", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = INK, BackgroundTransparency = 0.7, ZIndex = 3 })
corner(btnInset, 20)
local btnGrad = vgrad(rebirthBtn, LIME, LIME_DEEP)
local btnScale = Instance.new("UIScale"); btnScale.Parent = rebirthBtn
local btnBadge = badge(rebirthBtn, 10, math.floor((BTN_H - 46) / 2), 46, GOLD, GOLD_DEEP, "\u{1F512}", 23)
-- REWARD CHIP on the right: what is waiting behind the lock, so the button teases the goal instead of only
-- refusing. Repainted by refresh() with the live "next" multiplier.
local rewardChip = frame(rebirthBtn, { Name = "Reward", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(136, 36), BackgroundColor3 = GOLD, ZIndex = 5 })
corner(rewardChip, 12); outline(rewardChip, INK, 2.5); vgrad(rewardChip, GOLD, GOLD_DEEP)
local rewardLbl = label(rewardChip, { Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(70, 40, 6), Font = Enum.Font.FredokaOne, ZIndex = 6 })
maxsize(rewardLbl, 14)
local btnText = label(rebirthBtn, { Name = "Label", Text = "", Position = UDim2.fromOffset(66, 6), Size = UDim2.new(1, -220, 0, 28), TextColor3 = CREAM, ZIndex = 5 })
maxsize(btnText, 24); textOutline(btnText, 3)
local btnSub = label(rebirthBtn, { Name = "Sub", Text = "", Position = UDim2.fromOffset(66, 35), Size = UDim2.new(1, -220, 0, 20), TextColor3 = MUTED, Font = Enum.Font.GothamBold, ZIndex = 5 })
maxsize(btnSub, 14); textOutline(btnSub, 1.5)
-- breathing halo once unlocked
local btnGlow = frame(rebirthBtn, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 16, 1, 16), BackgroundColor3 = LIME, BackgroundTransparency = 1, ZIndex = 2 })
corner(btnGlow, 26)
task.spawn(function()
	local up = true
	while btnGlow.Parent do
		if gui.Enabled and rebirthBtn.Active then
			TweenService:Create(btnGlow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = up and 0.55 or 0.85 }):Play()
			up = not up
		else
			btnGlow.BackgroundTransparency = 1
		end
		task.wait(0.9)
	end
end)

-- ===== state =====
local function slotNow() return math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, TOP_SLOT) end
local function eligible() return slotNow() >= TOP_SLOT end
local armed, armToken = false, 0

local function paintButton()
	local icon = btnBadge:FindFirstChild("Icon")
	if eligible() then
		btnGrad.Enabled = true
		if armed then
			rebirthBtn.BackgroundColor3 = WHITE_BASE; btnGrad.Color = ColorSequence.new(GOLD, GOLD_DEEP); btnLine.Color = INK
			btnText.Text = "TAP AGAIN TO CONFIRM"; btnSub.Text = "This resets your island progress"
			if icon then icon.Text = "\u{26A0}" end
		else
			rebirthBtn.BackgroundColor3 = WHITE_BASE; btnGrad.Color = ColorSequence.new(LIME, LIME_DEEP); btnLine.Color = INK
			btnText.Text = "REBIRTH NOW"; btnSub.Text = "You are at the summit"
			if icon then icon.Text = "\u{1F504}" end
		end
		btnText.TextColor3 = CREAM; btnSub.TextColor3 = Color3.fromRGB(30, 60, 20)
		btnBadge.BackgroundColor3 = WHITE_BASE -- gold comes from its gradient, re-enabled on the next line
		local bg = btnBadge:FindFirstChildOfClass("UIGradient"); if bg then bg.Enabled = true end
		btnInset.Visible = false; btnShadow.BackgroundTransparency = 0.5
		rebirthBtn.Active = true
	else
		-- DISABLED, and it should look it: flat grey, no gradient, no gloss, muted text and a grey padlock
		-- badge. Still rounded and outlined, so it belongs to the same family as the live button.
		btnGrad.Enabled = false
		rebirthBtn.BackgroundColor3 = LOCK_FILL; btnLine.Color = LOCK_LINE; btnLine.Transparency = 0
		btnText.Text = "LOCKED  \u{2014}  REACH THE SUMMIT FIRST"
		btnSub.Text = ("Climb to Volcanic Vista (island %d of %d) to unlock Rebirth"):format(TOP_SLOT, TOP_SLOT)
		btnText.TextColor3 = Color3.fromRGB(196, 204, 194); btnSub.TextColor3 = Color3.fromRGB(168, 178, 166)
		if icon then icon.Text = "\u{1F512}" end
		btnBadge.BackgroundColor3 = Color3.fromRGB(110, 120, 108)
		local bg = btnBadge:FindFirstChildOfClass("UIGradient"); if bg then bg.Enabled = false end
		btnInset.Visible = true; btnShadow.BackgroundTransparency = 0.75
		rebirthBtn.Active = false
	end
end

local function refresh()
	local n = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0)
	local mult = tonumber(player:GetAttribute("RebirthMult")) or (1 + BONUS_PER_REBIRTH * n)
	countLbl.Text = tostring(n)
	multLbl.Text = ("x%.2f"):format(mult)
	nextLbl.Text = ("Next: x%.2f"):format(mult + BONUS_PER_REBIRTH)
	rewardLbl.Text = ("\u{1F381} x%.2f coins"):format(mult + BONUS_PER_REBIRTH)
	local slot = slotNow()
	local islandNum = IslandOrder.SLOT_TO_ISLAND[slot]
	local name = (islandNum and IslandOrder.NAMES[islandNum]) or ("Island " .. slot)
	progText.Text = eligible() and "\u{2B50} AT THE SUMMIT" or name
	progCount.Text = ("%d / %d islands"):format(slot, TOP_SLOT)
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(slot / TOP_SLOT, 0, 1, 0) }):Play()
	for i, c in ipairs(checkpoints) do
		if i < slot then
			c.disc.BackgroundColor3 = LIME_DEEP; c.disc.Size = UDim2.fromOffset(18, 18); c.halo.BackgroundTransparency = 1
		elseif i == slot then
			c.disc.BackgroundColor3 = GOLD; c.disc.Size = UDim2.fromOffset(22, 22); c.halo.BackgroundTransparency = 0.6
		else
			c.disc.BackgroundColor3 = LOCK_FILL; c.disc.Size = UDim2.fromOffset(16, 16); c.halo.BackgroundTransparency = 1
		end
	end
	rowLabels[2].Text = ("+%d coins now, and +%d%% coins forever"):format(COIN_BONUS_PER_REBIRTH * (n + 1), math.floor(BONUS_PER_REBIRTH * 100))
	paintButton()
end

local function disarm() armed = false; armToken += 1; paintButton() end
local function openMenu()
	for _, d in ipairs(gui:GetDescendants()) do -- any BACK that is not ours (an earlier injection) goes
		if d.Name == "RG_Back" and d ~= backBtn then d:Destroy() end
	end
	disarm(); refresh()
	gui.Enabled = true
	applyScale(0.7 * restScale())
	local target = restScale()
	pcall(function()
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(panelScale, ti, { Scale = target }):Play()
		TweenService:Create(shadowScale, ti, { Scale = target }):Play()
	end)
end
local function closeMenu() gui.Enabled = false; disarm() end
_G.toggleRebirth = function() if gui.Enabled then closeMenu() else openMenu() end end

closeBtn.Activated:Connect(closeMenu)
do
	local lastBack = 0
	backBtn.Activated:Connect(function()
		local now = os.clock()
		if now - lastBack < 0.35 then return end
		lastBack = now
		if _G.playUIClick then pcall(_G.playUIClick) end
		closeMenu()
		-- deferred: closing notifies the menu manager, which may close other menus in the same frame
		task.defer(function()
			if _G.railGuardOpenMore then pcall(_G.railGuardOpenMore)
			elseif _G.setMoreOpen then pcall(_G.setMoreOpen, true) end
		end)
	end)
end
openSignal.Event:Connect(openMenu)
player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
player:GetAttributeChangedSignal("RebirthMult"):Connect(refresh)
player:GetAttributeChangedSignal("HighestSlot"):Connect(refresh)

-- press feel
local function press(btn, sc)
	btn.MouseButton1Down:Connect(function() if btn.Active then TweenService:Create(sc, TweenInfo.new(0.06), { Scale = 0.96 }):Play() end end)
	local function up() TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
	btn.MouseButton1Up:Connect(up); btn.MouseLeave:Connect(up)
end
press(rebirthBtn, btnScale)
do local cs = Instance.new("UIScale"); cs.Parent = closeBtn; press(closeBtn, cs) end

local busy = false
rebirthBtn.Activated:Connect(function()
	if busy or not eligible() or not DoRebirth then return end
	if not armed then
		-- FIRST TAP ARMS. A rebirth throws away a whole climb; one stray tap must not be able to do that.
		armed = true; armToken += 1; local mine = armToken; paintButton()
		task.delay(3, function() if armToken == mine and armed then disarm() end end)
		return
	end
	busy = true
	btnText.Text = "REBIRTHING\u{2026}"
	local ok, result = pcall(function() return DoRebirth:InvokeServer() end)
	busy = false
	disarm()
	if ok and type(result) == "table" and result.ok then
		refresh(); closeMenu()
		-- THE MOMENT: arrival-class banner, milestone buzz and a chime.
		local n = tonumber(result.rebirths) or 0
		local mult = tonumber(result.mult) or 1
		pcall(function()
			local snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://112825313814792"; snd.Volume = 0.9; snd.Parent = workspace; snd:Play()
			game:GetService("Debris"):AddItem(snd, 5)
		end)
		if _G.hapticPulse then pcall(_G.hapticPulse, "milestone") end
		local Notify = _G.NotifyCenter
		if Notify then
			Notify.push({ top = "\u{1F504} REBIRTH " .. n, text = ("x%.2f COINS FOREVER"):format(mult),
				sub = "Back to Nesting Nook. Climb it again, faster.", color = GOLD,
				priority = Notify.PRIORITY.PLANET, duration = 5 })
		end
	else
		refresh()
	end
end)

print("[Rebirth][client] menu ready \u{2014} jungle/mountain header, chunky tiles, summit bar, two-tap confirm. Opens from MORE+ / _G.toggleRebirth.")
