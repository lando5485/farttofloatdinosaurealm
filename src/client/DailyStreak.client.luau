--======================================================================
-- DailyStreak.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE REWARDS HUB -- everything you can claim for free, behind three tabs:
--
--   DAILY      the 7-day login streak ladder      (DailyStreakEvent   -> DailyStreak.server)
--   TIMED      six session-playtime milestones    (SessionRewardEvent -> SessionRewards.server)
--   COMMUNITY  like / favourite / join the group  (SocialRewardEvent  -> SocialRewards.server)
--
-- SERVER-AUTHORITATIVE THROUGHOUT. Every tab draws state pushed by its own server and fires an intent; not
-- one of the three decides whether a claim is allowed. The CLAIM buttons are requests.
--
-- ===== THIS FILE WAS RECOVERED, NOT WRITTEN FROM SCRATCH =====
-- DailyStreak existed ONLY baked into the place file -- no repo source, absent from default.project.json,
-- flagged NOT-IN-MANIFEST by SecurityWatchdog every boot. Its source was extracted from the place snapshot,
-- which is what made it editable at all. Hence the retirement code at the bottom: until the baked-in copy is
-- DELETED IN STUDIO two copies run, both build a DailyStreakGui and both assign _G.toggleDailyStreak, so
-- without a guard whichever loaded last would win and this file would look like it changed nothing.
--
-- The file keeps its old name because _G.toggleDailyStreak is the handle the rest of the game already calls
-- and because that is the identity the retirement sweep matches on. It is the Rewards hub now.
--
-- ===== WHY THE THREE PANELS DID NOT GET MERGED =====
-- COMMUNITY talks to SocialRewards' remote directly rather than opening SocialRewards' own panel, and the
-- DAILY ladder is drawn here rather than in DailyStreak's. But the SERVERS are untouched: three remotes,
-- three sources of truth, exactly as before. A second copy of any of their state would be a second thing
-- that can disagree with the server, and the disagreement always surfaces as a reward a player believes they
-- earned and did not get.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")
local Debris       = game:GetService("Debris")
local RSx          = game:GetService("ReplicatedStorage")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

-- SPACE PORT: every remote is looked up with a bounded wait and every use is guarded. A missing remote costs
-- its tab its data, never the whole hub (the first realm hard-waited on DailyStreakEvent).
local dailyRemote  = RSx:WaitForChild("DailyStreakEvent", 10)
local timedRemote  = RSx:WaitForChild("SessionRewardEvent", 5)
local socialRemote = RSx:WaitForChild("SocialRewardEvent", 5)

-- DINO PORT: the jungle palette (JungleChrome's olive panel, dark-green header, parchment text) in place of
-- Space's SpaceTheme. The bamboo shell is added from outside by JungleTheme.client.luau, like the other menus.
local JUNGLE = { PanelTop = Color3.fromRGB(122, 142, 82), PanelBottom = Color3.fromRGB(96, 116, 66),
	PanelStroke = Color3.fromRGB(40, 52, 38), Background = Color3.fromRGB(26, 48, 30) }

-- Dino mounts src/shared as ReplicatedStorage.DinosaurRealm (Space mounts it at the root).
local CrateTokens
pcall(function()
	local shared = RSx:FindFirstChild("DinosaurRealm") or RSx:FindFirstChild("Shared") or RSx
	CrateTokens = require(shared:WaitForChild("CrateTokens", 5))
end)
local TOKEN_ICON = (CrateTokens and CrateTokens.ICON) or "\xF0\x9F\x8E\x9F"
local function fmt(n)
	if CrateTokens and CrateTokens.format then return CrateTokens.format(n) end
	return tostring(math.max(0, math.floor(tonumber(n) or 0)))
end

--======================================================================
-- PALETTE
--======================================================================
-- JUNGLE PALETTE: the first realm's pinks swapped for the realm's olive / dark-green / parchment set. The function
-- colours (gold claim, green done, orange, red close, brown back) are unchanged -- they carry meaning.
local PANEL_FILL  = JUNGLE.PanelTop        -- body; a PanelTop -> PanelBottom gradient is laid on it below
local PANEL_EDGE  = JUNGLE.PanelStroke
local HEADER_FILL = JUNGLE.Background
local WELL        = Color3.fromRGB( 58,  70,  40)
local CARD_DONE   = Color3.fromRGB( 70,  86,  50)
-- LOCKED is its own colour, not CARD_DONE dimmed at render time: a locked rung and a claimed rung are
-- different states, and telling them apart at a glance is most of what this row is for.
local CARD_LOCK   = Color3.fromRGB( 62,  70,  48)
local CARD_LIVE   = Color3.fromRGB(116, 140,  80)
local CARD_GIFT   = Color3.fromRGB(150, 100,  40)
local GIFT_EDGE   = Color3.fromRGB(255, 200,  90)
local DESC        = Color3.fromRGB(232, 209, 158)
local WHITE       = Color3.new(1, 1, 1)
local INK         = Color3.fromRGB( 20,  24,  14)
local LOCK_FILL   = Color3.fromRGB( 50,  58,  38)
local LOCK_TEXT   = Color3.fromRGB(196, 186, 150)
local LOCK_EDGE   = Color3.fromRGB( 40,  52,  38)
local ACT_LIP     = Color3.fromRGB(  6,  10,  28)
local GOLD        = Color3.fromRGB(255, 214,  56)
local GOLD_DEEP   = Color3.fromRGB(214, 150,  10)
local ORANGE      = Color3.fromRGB(255, 148,  40)
local ORANGE_DEEP = Color3.fromRGB(188,  92,   8)
local GREEN       = Color3.fromRGB( 74, 200, 108)
local GREEN_DEEP  = Color3.fromRGB( 32, 118,  56)
local BROWN       = Color3.fromRGB(150,  96,  46)
local BROWN_DEEP  = Color3.fromRGB( 92,  56,  24)
local RED         = Color3.fromRGB(224,  62,  58)
local RED_DEEP    = Color3.fromRGB(132,  26,  24)

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
-- BORDER stroke: for FRAMES and BUTTONS, where the outline wanted is the object's own edge.
local function stroke(o, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = o; return s
end

-- GLYPH stroke: for TEXT. THIS IS THE DIFFERENCE THAT MADE THE TITLE, THE STREAK CHIP AND EVERY QUANTITY
-- LABEL LOOK LIKE THEY SAT IN BOXES.
--
-- ApplyStrokeMode.Border on a TextLabel outlines the LABEL'S RECTANGLE, not its letters -- so a transparent
-- label asking for a "dark outline" drew a dark box around empty space instead of an outline around the
-- words. Contextual (the default) is the mode that traces the glyphs. All text on this page uses this; all
-- frames and buttons use the one above.
local function tstroke(o, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; s.Parent = o; return s
end

-- A soft drop shadow for free-floating text: the same string, dark, one layer back and nudged down.
local function textShadow(lbl, dy)
	local sh = lbl:Clone()
	for _, c in ipairs(sh:GetChildren()) do c:Destroy() end
	sh.Name = "Shadow"
	sh.TextColor3 = Color3.fromRGB(0, 2, 12)
	sh.TextTransparency = 0.45
	sh.ZIndex = math.max(1, lbl.ZIndex - 1)
	sh.Position = UDim2.new(lbl.Position.X.Scale, lbl.Position.X.Offset,
		lbl.Position.Y.Scale, lbl.Position.Y.Offset + (dy or 3))
	sh.Parent = lbl.Parent
	return sh
end
local function label(parent, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent; return l
end
local function frame(parent, props)
	local f = Instance.new("Frame"); f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent; return f
end
local function button(parent, props)
	local b = Instance.new("TextButton"); b.BorderSizePixel = 0; b.AutoButtonColor = false
	for k, v in pairs(props) do b[k] = v end
	b:SetAttribute("BTS_Skip", true)  -- these buttons' COLOUR is their state; keep the legibility sweep off
	b.Parent = parent; return b
end

-- THE RAISED 3D LOOK, and it is a frame rather than a gradient: a darker slab of the same colour peeking out
-- from under the bottom edge. A gradient makes a button look LIT; a lip makes it look like it STICKS UP,
-- which is the chunky-toy read this game's UI is built on.
local function raised(btn, deep, lift)
	local r = 10
	local c = btn:FindFirstChildOfClass("UICorner")
	if c then r = c.CornerRadius.Offset end
	local lip = frame(btn.Parent, {
		Size = btn.Size,
		Position = UDim2.new(btn.Position.X.Scale, btn.Position.X.Offset,
			btn.Position.Y.Scale, btn.Position.Y.Offset + (lift or 4)),
		AnchorPoint = btn.AnchorPoint, BackgroundColor3 = deep,
		ZIndex = math.max(1, btn.ZIndex - 1),
	})
	corner(lip, r)
	return lip
end

-- A LIGHTER TOP HIGHLIGHT: a bright band across the top third, faded downward. The other half of the raised
-- look the lip gives from below -- together they read as a moulded plastic key.
local function sheen(o, r)
	local hi = frame(o, {
		Name = "Sheen", Size = UDim2.new(1, -6, 0.42, 0), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72,
		ZIndex = (o.ZIndex or 1) + 1,
	})
	corner(hi, math.max(4, (r or 10) - 3))
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = hi
	return hi
end

-- A vertical shading gradient: lighter at the top, darker at the bottom. UIGradient MULTIPLIES the fill, so
-- ONE gradient shades a card whatever colour it happens to be this frame -- which matters here, because a
-- card's fill changes with its state on every render.
local function shade(o, topBoost, bottomCut)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(
		Color3.new(topBoost or 1, topBoost or 1, topBoost or 1),
		Color3.new(bottomCut or 0.78, bottomCut or 0.78, bottomCut or 0.78))
	g.Parent = o
	return g
end

-- HOVER + PRESS. Scale only, no colour swap: these buttons already use colour to say which state they are
-- in, and a hover tint would collide with that.
local function feel(btn)
	local sc = btn:FindFirstChildOfClass("UIScale")
	if not sc then sc = Instance.new("UIScale"); sc.Parent = btn end
	local function to(v, t)
		if btn:GetAttribute("MS_Pulsing") then return end -- the pulse owns the scale while it runs
		TweenService:Create(sc, TweenInfo.new(t, Enum.EasingStyle.Quad), { Scale = v }):Play()
	end
	btn.MouseEnter:Connect(function() if btn.Active then to(1.06, 0.10) end end)
	btn.MouseLeave:Connect(function() to(1.00, 0.12) end)
	btn.MouseButton1Down:Connect(function() if btn.Active then to(0.94, 0.06) end end)
	btn.MouseButton1Up:Connect(function() if btn.Active then to(1.06, 0.08) end end)
	return sc
end

-- THE PULSE on the one button you are meant to press. Started and stopped by paintAction, so there is never
-- more than one running and it cannot outlive the state that asked for it.
local function pulse(btn, on)
	local sc = btn:FindFirstChildOfClass("UIScale")
	if not sc then sc = Instance.new("UIScale"); sc.Parent = btn end
	if not on then btn:SetAttribute("MS_Pulsing", false); return end
	if btn:GetAttribute("MS_Pulsing") then return end
	btn:SetAttribute("MS_Pulsing", true)
	task.spawn(function()
		while btn.Parent and btn:GetAttribute("MS_Pulsing") do
			TweenService:Create(sc, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1.07 }):Play()
			task.wait(0.6)
			if not btn:GetAttribute("MS_Pulsing") then break end
			TweenService:Create(sc, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1.0 }):Play()
			task.wait(0.6)
		end
		if sc and sc.Parent then sc.Scale = 1 end
	end)
end

-- A red "!" badge. Used on the tabs, and only ever when something is genuinely claimable RIGHT NOW -- a
-- badge that means "new" or "look here" trains people to ignore it, which then costs you the one time it
-- meant "there is free money on this tab".
local function badge(parent)
	-- Sits OUTSIDE the tab's top-right corner, not on its border. Overlapping the edge made it read as part
	-- of the tab's outline rather than as a thing stuck to it, and it clipped against the 3px stroke.
	-- The dark ring is what lets one badge colour work on both the pink and the orange fill.
	local d = frame(parent, {
		Name = "Badge", Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, 5, 0, -7), AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60), ZIndex = 20, Visible = false,
	})
	corner(d, 999); stroke(d, INK, 3)
	label(d, { Text = "!", Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = WHITE,
		Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 })
	return d
end

-- ===== THE CLAIM SOUND =====
-- Its own sound, not the UI click. Claiming is the one thing this whole panel exists for, and it should not
-- sound the same as changing tabs -- the click says "you pressed something", this says "you got it".
--
-- Cloned per play rather than replayed on one instance: two claims in quick succession (tab across, claim
-- again) would otherwise cut each other off, and the second press would feel like it did not register.
local CLAIM_SOUND_ID = "rbxassetid://4612378364"
local claimSoundTemplate
do
	local snd = Instance.new("Sound")
	snd.Name = "RewardClaimSound"
	snd.SoundId = CLAIM_SOUND_ID
	snd.Volume = 0.65
	snd.PlaybackSpeed = 1.18   -- a touch brighter than the click it sits next to
	snd.Parent = PlayerGui
	claimSoundTemplate = snd
end
local function playClaim()
	-- Prefer the shared cue table if this place has one wired: a project-wide sound set should win over a
	-- local id the moment it exists, without this file needing to know which cue it picked.
	if _G.sfxPlay then
		local ok = pcall(_G.sfxPlay, "claim")
		if ok then return end
	end
	local c = claimSoundTemplate:Clone()
	c.Parent = PlayerGui
	c:Play()
	Debris:AddItem(c, 4)
end

local function mmss(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

--======================================================================
-- SHELL
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "DailyStreakGui"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.DisplayOrder = 101; gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui:SetAttribute("NoTextSweep", true)  -- CoreClient's TextScaled sweep: this page is precise type sizes
-- MenuSkin adopts any 700x520 opaque panel and forces the house 3px WHITE rim + 24px radius. This page is
-- authored to a thick DARK border, so it takes the documented opt-out rather than fighting that sweep on
-- every open.
gui:SetAttribute("NoMenuSkin", true)
gui.Parent = PlayerGui

-- NO DIM. This full-screen frame used to sit behind the panel at 45% black, shading the whole game while
-- Rewards was open. The panel is a 700px card with its own dark border on a bright pink ground -- it already
-- separates from the world without pushing the world down a stop, and dimming a flight in progress behind a
-- menu you opened for two seconds reads worse than leaving it alone.
--
-- KEPT, AT FULL TRANSPARENCY, RATHER THAN DELETED. `Active = true` is what stops a click landing on the world
-- (or on the HUD button behind the card) while the panel is up -- an invisible frame still swallows input, a
-- deleted one does not. So the shade goes and the click-blocking stays.
frame(gui, {
	Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1, Active = true,
})

-- DESKTOP / TABLET / MOBILE. The card is authored at 700x520 and scaled as ONE unit when the viewport cannot
-- hold it, so every inset, gap and type size keeps its proportion instead of each needing a breakpoint.
-- ResponsiveUI's global phone scale still applies on top; this only ever shrinks further.
-- SPACE PORT: 46px taller than the first realm's 492, and only so the DAILY tab can hold the Daily Crate row
-- under the streak ladder. Every other measurement is the first realm's.
local PANEL_H = 538
local shell = frame(gui, {
	Size = UDim2.fromOffset(700, PANEL_H), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
})
local fitScale = Instance.new("UIScale"); fitScale.Scale = 1; fitScale.Parent = shell
local function refit()
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	if not v or v.X < 1 then return end
	fitScale.Scale = math.clamp(math.min((v.X - 24) / 700, (v.Y - 24) / PANEL_H), 0.42, 1)
end
refit()
local function watchCam()
	local cam = Workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
end
watchCam()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() refit(); watchCam() end)

-- NO DROP-SHADOW SLAB. There was a dark rounded frame behind the panel, offset down by 10 -- which is
-- exactly a black lip hanging off the bottom edge, because a hard-edged rectangle peeking out from under a
-- rounded card does not read as a shadow, it reads as a second card behind the first.
--
-- A real soft shadow needs a blurred image, and the CSP on what this place can load makes that a bigger job
-- than it is worth here. The panel already separates from the world on the dimmed backdrop and its own 5px
-- dark border, so the honest fix is to let it end cleanly at its own rounded corners.

local panel = frame(shell, {
	Size = UDim2.fromOffset(700, PANEL_H), BackgroundColor3 = WHITE, Active = true, ZIndex = 1,
})
corner(panel, 26); stroke(panel, PANEL_EDGE, 5)
do -- SpaceTheme's panel body: PanelTop -> PanelBottom (white fill so the gradient IS the colour)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(PANEL_FILL, JUNGLE.PanelBottom)
	g.Parent = panel
end

--======================================================================
-- HEADER
--======================================================================
local header = frame(panel, { Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = HEADER_FILL, ZIndex = 2 })
corner(header, 26)
-- square off the band's lower corners: the 26px radius is wanted only where it meets the panel's own top
frame(header, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26),
	BackgroundColor3 = HEADER_FILL, ZIndex = 2 })
-- A hairline under the band. The header and the body are only ~55 RGB apart, which at a glance is one
-- surface with a slightly odd top; a single light rule is enough to say "these are two sections" without
-- adding another border to a panel that already has plenty.
frame(panel, { Size = UDim2.new(1, -36, 0, 2), Position = UDim2.fromOffset(18, 88),
	BackgroundColor3 = Color3.fromRGB(120, 160, 255), BackgroundTransparency = 0.55, ZIndex = 3 })

do
	local tile = frame(header, {
		Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(18, 16),
		BackgroundColor3 = WELL, ZIndex = 3,
	})
	corner(tile, 14); stroke(tile, PANEL_EDGE, 2)
	label(tile, { Text = "\xF0\x9F\x8E\x81", Font = Enum.Font.FredokaOne, TextSize = 30,
		Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
end

do
	local t = label(header, { Text = "REWARDS", Font = Enum.Font.FredokaOne, TextSize = 36, TextColor3 = WHITE,
		Size = UDim2.new(0, 340, 0, 40), Position = UDim2.fromOffset(86, 12),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	tstroke(t, INK, 3); textShadow(t, 3)
end
label(header, { Text = "Everything you can claim for free", Font = Enum.Font.Gotham, TextSize = 14,
	TextColor3 = DESC, Size = UDim2.new(0, 340, 0, 18), Position = UDim2.fromOffset(88, 52),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })

local backBtn = button(header, {
	Size = UDim2.fromOffset(46, 42), Position = UDim2.new(1, -114, 0, 22),
	-- "<" rather than U+276E: the heavy chevron renders as a blank box in FredokaOne, which is exactly why
	-- this button looked empty. A plain less-than exists in every font on every platform.
	BackgroundColor3 = BROWN, Text = "<", Font = Enum.Font.FredokaOne, TextSize = 26,
	TextColor3 = WHITE, AutoButtonColor = true, ZIndex = 4,
})
corner(backBtn, 12); stroke(backBtn, INK, 3); raised(backBtn, BROWN_DEEP, 4); sheen(backBtn, 12)
tstroke(backBtn, INK, 2); feel(backBtn)

local closeBtn = button(header, {
	Size = UDim2.fromOffset(46, 42), Position = UDim2.new(1, -60, 0, 22),
	BackgroundColor3 = RED, Text = "X", Font = Enum.Font.FredokaOne, TextSize = 22,
	TextColor3 = WHITE, AutoButtonColor = true, ZIndex = 4,
})
corner(closeBtn, 12); stroke(closeBtn, INK, 3); raised(closeBtn, RED_DEEP, 4); sheen(closeBtn, 12)
tstroke(closeBtn, INK, 2); feel(closeBtn)

--======================================================================
-- TAB BAR
--======================================================================
-- One recessed well holding three equal pills, laid out by UIListLayout: three tabs and two gaps is exactly
-- the sum that drifts the moment a width changes.
local TAB_W, TAB_H = 210, 40
local tabWell = frame(panel, {
	Size = UDim2.new(1, -40, 0, 48), Position = UDim2.fromOffset(20, 98),
	BackgroundColor3 = WELL, ZIndex = 2,
})
corner(tabWell, 16); stroke(tabWell, PANEL_EDGE, 2)
do
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.VerticalAlignment = Enum.VerticalAlignment.Center
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 8)
	ll.Parent = tabWell
end

local TABS = { { id = "daily", text = "DAILY" }, { id = "timed", text = "TIMED" }, { id = "community", text = "COMMUNITY" } }
local tabBtn, tabBadge, pages = {}, {}, {}
local activeTab = "daily"

for i, t in ipairs(TABS) do
	local b = button(tabWell, {
		Size = UDim2.fromOffset(TAB_W, TAB_H), LayoutOrder = i, BackgroundColor3 = CARD_DONE,
		Text = "", ZIndex = 3,
	})
	corner(b, 12); stroke(b, PANEL_EDGE, 2)
	-- The word is a CHILD label: a UIStroke on a filled text object outlines the object's BORDER, not its
	-- glyphs, so the only way to get a dark outline on the letters is a transparent label on top.
	local l = label(b, { Name = "Label", Text = t.text, Font = Enum.Font.FredokaOne, TextSize = 19,
		TextColor3 = WHITE, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	tstroke(l, INK, 2)
	l:SetAttribute("BTS_Skip", true)
	tabBtn[t.id] = b
	tabBadge[t.id] = badge(b)
end

-- The content area every page is built into. One rect, so no page can drift from another.
local body = frame(panel, {
	Size = UDim2.new(1, -40, 0, PANEL_H - 170), Position = UDim2.fromOffset(20, 154),
	BackgroundTransparency = 1, ZIndex = 2,
})
for _, t in ipairs(TABS) do
	pages[t.id] = frame(body, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 2 })
end

local function syncTabs()
	for _, t in ipairs(TABS) do
		local on = (activeTab == t.id)
		local b  = tabBtn[t.id]
		b.BackgroundColor3 = on and GOLD or CARD_DONE
		-- THE LABEL DOES NOT CHANGE ON SELECTION. It used to go dark-on-gold while its glyph stroke stayed
		-- dark, so the selected tab was dark text wearing a heavy dark outline on orange -- the two were
		-- fighting and the word all but vanished. White with a dark outline is what every other piece of text
		-- on this panel does, it survives both the pink and the orange fill, and it means selection is said by
		-- ONE thing (the gold gradient and its border) instead of three that have to agree.
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then st.Color = on and GOLD_DEEP or PANEL_EDGE; st.Thickness = on and 3 or 2 end
		-- the selected tab's yellow-orange: a gradient rather than a flat fill, so it reads as lit next to
		-- two flat pink ones
		local g = b:FindFirstChildOfClass("UIGradient")
		if on and not g then
			g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(GOLD, ORANGE)
			g.Rotation = 90; g.Parent = b
		elseif g and not on then
			g:Destroy()
		end
		pages[t.id].Visible = on
	end
end

local function showTab(id)
	if not pages[id] then return end
	activeTab = id
	syncTabs()
end
for _, t in ipairs(TABS) do
	tabBtn[t.id].MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		showTab(t.id)
	end)
end

--======================================================================
-- SHARED: the three button states every claim card uses
--======================================================================
-- One instance with three looks, rather than three overlaid instances: exactly one thing to get right, and
-- nothing can ever be visible underneath something else.
-- THREE LOOKS, ONE INSTANCE. Not three overlaid buttons: exactly one thing to get right, and nothing can
-- ever be left visible underneath something else.
--
-- CLAIM is the only state that gets a gradient, a lip, a sheen and a pulse, because it is the only state
-- that is a BUTTON. DONE and LOCKED are read-outs wearing a button shape, so they go FLAT AND INSET: lip
-- hidden, sheen hidden, fill darker than the card behind them. That inset/raised split is what makes
-- "press me" legible from across the row without reading a single word.
local function paintAction(btn, lip, strokeObj, mode)
	local grad   = btn:FindFirstChildOfClass("UIGradient")
	local sheenF = btn:FindFirstChild("Sheen")

	if mode == "claim" then
		btn.BackgroundColor3 = GOLD; btn.TextColor3 = INK; btn.Text = "CLAIM"
		btn.Active = true; btn.AutoButtonColor = false; btn.TextSize = 17
		btn.Font = Enum.Font.FredokaOne
		if grad then
			grad.Enabled = true
			grad.Color = ColorSequence.new(GOLD, ORANGE)
			grad.Rotation = 90
		end
		if sheenF then sheenF.Visible = true end
		lip.Visible = true; lip.BackgroundColor3 = ORANGE_DEEP
		strokeObj.Color = INK; strokeObj.Thickness = 3
		pulse(btn, true)
	elseif mode == "done" then
		pulse(btn, false)
		btn.BackgroundColor3 = GREEN; btn.TextColor3 = WHITE; btn.Text = "\xE2\x9C\x93"
		btn.Active = false; btn.AutoButtonColor = false; btn.TextSize = 22
		if grad then grad.Enabled = false end
		if sheenF then sheenF.Visible = false end
		lip.Visible = false
		strokeObj.Color = GREEN_DEEP; strokeObj.Thickness = 2
	else
		pulse(btn, false)
		-- Flat inset: darker than the card, no lip, no sheen. A lock is not pressable and must not look it.
		btn.BackgroundColor3 = LOCK_FILL
		btn.TextColor3 = LOCK_TEXT
		btn.Text = "\xF0\x9F\x94\x92"
		btn.Active = false; btn.AutoButtonColor = false; btn.TextSize = 18
		if grad then grad.Enabled = false end
		if sheenF then sheenF.Visible = false end
		lip.Visible = false
		strokeObj.Color = LOCK_EDGE; strokeObj.Thickness = 2
	end
end

local function sparkle(atFrame)
	if not atFrame or not atFrame.Parent then return end
	local origin = atFrame.AbsolutePosition + atFrame.AbsoluteSize / 2 - panel.AbsolutePosition
	for _ = 1, 12 do
		local sp = label(panel, { Text = "\xE2\x9C\xA6", Font = Enum.Font.GothamBold, TextColor3 = GOLD,
			TextSize = math.random(14, 24), Size = UDim2.fromOffset(24, 24), ZIndex = 40,
			AnchorPoint = Vector2.new(0.5, 0.5), Rotation = math.random(0, 359) })
		sp.Position = UDim2.fromOffset(origin.X, origin.Y)
		local ang, reach = math.rad(math.random(0, 359)), math.random(50, 150)
		local dur = 0.5 + math.random() * 0.4
		TweenService:Create(sp, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(origin.X + math.cos(ang) * reach, origin.Y + math.sin(ang) * reach),
			TextTransparency = 1, Rotation = sp.Rotation + math.random(-180, 180),
		}):Play()
		Debris:AddItem(sp, dur + 0.1)
	end
end

--======================================================================
-- PAGE 1: DAILY  (7-day login streak)
--======================================================================
local DAYS = 7
-- 85 x 234 with an 8px gap and an 8px margin either side: 7*85 + 6*8 + 16 = 659, inside the 660 the body
-- gives. Written as arithmetic rather than three magic numbers so the next person to add a day can see
-- immediately what has to give.
local CARD_W, CARD_H, CARD_GAP, ROW_MARGIN = 85, 234, 8, 8
local dailyPage = pages.daily
local dayCards, dailyClaimable = {}, false

-- THE PILL IS BACK, but as a real pill this time: a dark rounded well with padding around the words, not
-- the square bordered box the Border-mode stroke was drawing before. The chip is the anchor for the whole
-- row -- without a background the flame and the number floated on the magenta with nothing holding them.
local streakChip = frame(dailyPage, {
	Size = UDim2.fromOffset(250, 38), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(8, 12, 30), ZIndex = 3,
})
corner(streakChip, 19); stroke(streakChip, PANEL_EDGE, 2.5)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16); pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = streakChip
end
-- RichText so the DAY NUMBER can be gold inside an otherwise white sentence without splitting the chip into
-- three labels that then have to be re-laid-out every time the number changes width.
local streakLbl = label(streakChip, {
	Text = "\xF0\x9F\x94\xA5 DAY 0 STREAK", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHITE,
	RichText = true, Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0),
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
})
tstroke(streakLbl, INK, 2)

local dayRow = frame(dailyPage, {
	Size = UDim2.new(1, 0, 0, CARD_H), Position = UDim2.fromOffset(0, 46), BackgroundTransparency = 1, ZIndex = 2,
})
do
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, CARD_GAP)
	ll.Parent = dayRow
	-- The cards were touching the panel edge because the row filled the body exactly. This inset matches the
	-- tab bar above it, so the two rows share one left/right margin instead of each having its own.
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, ROW_MARGIN); pad.PaddingRight = UDim.new(0, ROW_MARGIN)
	pad.Parent = dayRow
end

-- ============================================================================================================
-- ONE CARD, BUILT ON FIXED SLOTS
-- ============================================================================================================
-- Every element inside a card is a row in a UIListLayout with a FIXED HEIGHT, not a hand-placed offset. That
-- is what makes the seven cards line up: the icon centre, the x-amount and the button sit at the same y on
-- every card BY CONSTRUCTION, because each is the Nth slot of an identical stack.
--
-- Day 7 is the reason this matters. It carries two extra caption lines, and with hand-placed offsets those
-- lines pushed its content past the others and broke the row. Now every card -- day 7 included -- owns the
-- SAME caption slot; days 1-6 simply leave theirs empty, and day 7 fits two small lines inside it. Same
-- height, same baselines, no special case in the layout.
local SLOT_DAY, SLOT_ICON, SLOT_QTY, SLOT_CAP, SLOT_BTN = 18, 76, 26, 32, 44

for i = 1, DAYS do
	local isGift = (i == DAYS)
	local c = frame(dayRow, {
		Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = isGift and CARD_GIFT or CARD_LOCK,
		LayoutOrder = i, ZIndex = 3,
	})
	corner(c, 18)
	local st = stroke(c, isGift and GIFT_EDGE or PANEL_EDGE, 3)
	shade(c, 1.10, 0.78)  -- lighter at the top; multiplies whatever fill the current state sets
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = c

	do
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Vertical
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Padding = UDim.new(0, 4)
		ll.Parent = c
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 12)
		pad.PaddingLeft = UDim.new(0, 5); pad.PaddingRight = UDim.new(0, 5)
		pad.Parent = c
	end

	-- slot 1: DAY N
	label(c, { Text = "DAY " .. i, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = DESC,
		Size = UDim2.new(1, 0, 0, SLOT_DAY), LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })

	-- slot 2: the icon, with its glow behind it. A wrapper so the layout only has to place ONE thing and the
	-- glow can sit behind the glyph without being a sibling the layout would try to stack.
	local iconSlot = frame(c, {
		Size = UDim2.new(1, 0, 0, SLOT_ICON), LayoutOrder = 2, BackgroundTransparency = 1, ZIndex = 3,
	})

	-- RADIAL GLOW, shown only on the live day. A circle with a transparency gradient reads as a glow and
	-- costs no image asset, which is the point of doing it in UIGradient.
	local glow = frame(iconSlot, {
		Size = UDim2.fromOffset(76, 76), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.45, ZIndex = 3, Visible = false,
	})
	corner(glow, 999)
	do
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.55, 0.62),
			NumberSequenceKeypoint.new(1, 1) })
		g.Rotation = 90; g.Parent = glow
	end

	if isGift then
		local blob = frame(iconSlot, {
			Size = UDim2.fromOffset(64, 64), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, ZIndex = 5,
		})
		corner(blob, 999); stroke(blob, WHITE, 2)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  90, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 205,  70)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(110, 235, 130)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB( 90, 190, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(200, 120, 255)) })
		g.Rotation = 35; g.Parent = blob
		-- the only motion on the page, and it is what makes the last rung read as the prize
		task.spawn(function()
			while g.Parent do g.Rotation = (g.Rotation + 1) % 360; task.wait(0.05) end
		end)
		label(blob, { Text = "?", Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = INK,
			Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		-- SHINE: a soft white ellipse up-left, the highlight every glossy sphere has.
		do
			local shine = frame(blob, {
				Size = UDim2.fromOffset(22, 14), Position = UDim2.fromOffset(12, 9),
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, ZIndex = 7,
			})
			corner(shine, 999)
			local sg = Instance.new("UIGradient")
			sg.Rotation = 90
			sg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
			sg.Parent = shine
		end
	else
		-- 60px, up from 46: a reward icon should be the biggest thing on the card, and at 46 in an 85px card
		-- it still read as a bullet point. The shadow is the same glyph, dark and offset, one layer back --
		-- the same trick the title uses, and it is what stops the icon looking pasted on.
		local ic = label(iconSlot, {
			Text = TOKEN_ICON, Font = Enum.Font.FredokaOne, TextSize = 60,
			Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
		})
		textShadow(ic, 3)
	end

	-- slot 3: the quantity
	local amt = label(c, { Text = "x0", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = WHITE,
		Size = UDim2.new(1, 0, 0, SLOT_QTY), LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	tstroke(amt, INK, 2)

	-- slot 4: the caption. PRESENT ON EVERY CARD, empty on days 1-6 -- that is what keeps the button slot on
	-- the same baseline across the row instead of day 7 pushing its own down.
	local capSlot = frame(c, {
		Size = UDim2.new(1, 0, 0, SLOT_CAP), LayoutOrder = 4, BackgroundTransparency = 1, ZIndex = 3,
	})
	local crateLbl, spinLbl = nil, nil
	if isGift then
		-- NAMES THE PRIZE NOW. "MYSTERY / SPECIAL REWARD!" was accurate while day 7 paid tokens like every
		-- other day -- it was mysterious because there was nothing to say. It pays a free spin of the rarest
		-- crate in the game, and that is worth advertising six days ahead: a player who can see what is at the
		-- end of the week has a reason to finish it. The "?" ball above stays -- what you WIN is still unknown.
		crateLbl = label(capSlot, { Text = "STARTER CRATE", Font = Enum.Font.FredokaOne, TextSize = 12, TextColor3 = GOLD,
			Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
		spinLbl = label(capSlot, { Text = "FREE SPIN!", Font = Enum.Font.GothamBold, TextSize = 9,
			TextColor3 = WHITE, TextScaled = false,
			Size = UDim2.new(1, 0, 0, 13), Position = UDim2.fromOffset(0, 15),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	end

	-- slot 5: the action button
	local btnSlot = frame(c, {
		Size = UDim2.new(1, 0, 0, SLOT_BTN), LayoutOrder = 5, BackgroundTransparency = 1, ZIndex = 3,
	})
	local act = button(btnSlot, {
		Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WELL, Text = "\xF0\x9F\x94\x92", Font = Enum.Font.FredokaOne, TextSize = 18,
		TextColor3 = LOCK_TEXT, ZIndex = 5,
	})
	corner(act, 12)
	local actStroke = stroke(act, INK, 3)
	local actLip = raised(act, ACT_LIP, 4); actLip.ZIndex = 4
	do local g = Instance.new("UIGradient"); g.Enabled = false; g.Parent = act end
	sheen(act, 12); feel(act)

	dayCards[i] = { frame = c, amt = amt, act = act, lip = actLip, st = actStroke,
		cardStroke = st, scale = sc, glow = glow, isGift = isGift, crateLbl = crateLbl, spinLbl = spinLbl }
end

local dailyStatus = label(dailyPage, {
	Text = "Log in every day -- keep the streak alive!", Font = Enum.Font.FredokaOne, TextSize = 20,
	TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 288),
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
})
tstroke(dailyStatus, INK, 2.5)

--======================================================================
-- PAGE 2: TIMED  (session playtime milestones)
--======================================================================
local timedPage = pages.timed
local timedCards, timedState, timedClaimable = {}, nil, false
local RUNGS = 6

do
	local barWrap = frame(timedPage, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 3 })
	-- The same left/right inset the card row below uses, so the label, the bar and the cards all start and
	-- end on one margin instead of the bar running edge to edge over them.
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_MARGIN); pad.PaddingRight = UDim.new(0, ROW_MARGIN)
		pad.Parent = barWrap
	end
	-- Named, because once the track can roll over this caption has to say WHICH lap you are looking at --
	-- otherwise pass 2's cards read as a bug ("why does the first one say 125 MIN?").
	label(barWrap, { Name = "PassCaption", Text = "SESSION PROGRESS", Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = DESC, Size = UDim2.new(0, 320, 0, 16), Position = UDim2.fromOffset(0, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local track = frame(barWrap, {
		Name = "Track", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 20),
		BackgroundColor3 = WELL, ZIndex = 3, ClipsDescendants = true,
	})
	corner(track, 9); stroke(track, PANEL_EDGE, 2)
	-- THE FILL IS A BAR, AND THE CIRCLE IS ITS LEADING CAP.
	--
	-- It looked like a lone dot at the far left because a 9px corner radius on a frame only a few pixels wide
	-- rounds the whole thing away -- at low progress the bar WAS the circle. The cap is now its own child
	-- pinned to the fill's right edge, so it rides along as the bar grows and the bar behind it stays a bar.
	-- The track clips, so the cap can never poke out past the rounded end.
	local fill = frame(track, { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = GOLD, ZIndex = 4 })
	corner(fill, 9)
	do
		local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(GOLD, ORANGE); g.Parent = fill
	end
	do
		local cap = frame(fill, {
			Name = "Cap", Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = ORANGE, ZIndex = 5, Visible = false,
		})
		corner(cap, 999); stroke(cap, Color3.fromRGB(255, 236, 170), 2)
	end
	-- the count-up readout, unchanged: minutes played over the whole track
	label(track, { Name = "Text", Text = "00:00", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
		Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
end

local rungRow = frame(timedPage, {
	Size = UDim2.new(1, 0, 0, 202), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, ZIndex = 2,
})
do
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, CARD_GAP)
	ll.Parent = rungRow
	-- Same inset as the day row and the progress bar: one margin for the whole tab.
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, ROW_MARGIN); pad.PaddingRight = UDim.new(0, ROW_MARGIN)
	pad.Parent = rungRow
end

for i = 1, RUNGS do
	local c = frame(rungRow, {
		-- 100 wide: 6 cards + 5 eight-pixel gaps + the row's 16px of margin = 656, inside the 660 available.
		Size = UDim2.fromOffset(100, 202), BackgroundColor3 = CARD_LOCK, LayoutOrder = i, ZIndex = 3,
	})
	corner(c, 18)
	local cst = stroke(c, PANEL_EDGE, 3)
	shade(c, 1.10, 0.80)
	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = c

	local mins = label(c, { Text = "-- MIN", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = GOLD,
		Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 8),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	tstroke(mins, INK, 2)

	local glow = frame(c, {
		Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0.5, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = GOLD, BackgroundTransparency = 0.55, ZIndex = 3, Visible = false,
	})
	corner(glow, 999)
	do
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.55, 0.72),
			NumberSequenceKeypoint.new(1, 1) })
		g.Rotation = 90; g.Parent = glow
	end

	-- TextScaled inside a FIXED BOX, not a fixed TextSize -- because emoji do not share a common size at a
	-- given TextSize. A gift glyph is drawn noticeably larger than a ticket at the same 44, which is why the
	-- 60 MIN rung looked out of scale with the rest. Scaling to the box makes every rung's icon occupy the
	-- same 54px regardless of which glyph the server sent; the constraint stops it growing past 44.
	local icon = label(c, { Text = TOKEN_ICON, Font = Enum.Font.FredokaOne, TextScaled = true,
		Size = UDim2.new(1, -18, 0, 54), Position = UDim2.fromOffset(9, 34),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	do local ic = Instance.new("UITextSizeConstraint"); ic.MaxTextSize = 44; ic.Parent = icon end

	local qty = label(c, { Text = "--", Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = WHITE,
		Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 92),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	tstroke(qty, INK, 2)

	-- the live countdown line -- only the NEXT rung ever fills this in
	-- ALWAYS PRESENT, usually empty. Reserving the slot on every card is what keeps the six the same height
	-- whether or not this one happens to be the rung that is counting down.
	local sub = label(c, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 12, TextColor3 = GOLD,
		Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 114),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	tstroke(sub, INK, 2)

	local act = button(c, {
		Size = UDim2.fromOffset(83, 38), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = WELL, Text = "\xF0\x9F\x94\x92", Font = Enum.Font.FredokaOne, TextSize = 17,
		TextColor3 = LOCK_TEXT, ZIndex = 5,
	})
	corner(act, 12)
	local ast = stroke(act, INK, 3)
	local lip = raised(act, ACT_LIP, 4); lip.ZIndex = 4
	do local g = Instance.new("UIGradient"); g.Enabled = false; g.Parent = act end
	sheen(act, 12); feel(act)

	timedCards[i] = { frame = c, mins = mins, icon = icon, qty = qty, sub = sub,
		act = act, lip = lip, st = ast, cardStroke = cst, scale = sc, glow = glow }
end

local timedNote = label(timedPage, {
	Text = "Claim all six and the track starts again -- bigger. Time only counts while you're playing.",
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = DESC,
	Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 262),
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
})

--======================================================================
-- PAGE 3: COMMUNITY  (like / favourite / group + an all-three bonus)
--======================================================================
local communityPage = pages.community
local socialState, socialRows, socialClaimable = {}, {}, false

local COMMUNITY = {
	{ id = "like",     icon = "\xF0\x9F\x91\x8D", title = "LIKE THE GAME",    hint = "Tap the thumbs-up on the game page" },
	{ id = "favorite", icon = "\xE2\xAD\x90",     title = "FAVORITE THE GAME", hint = "Tap the star on the game page" },
	{ id = "group",    icon = "\xF0\x9F\x91\xA5", title = "JOIN THE GROUP",   hint = "Join MLR Studios, then claim" },
}

for i, t in ipairs(COMMUNITY) do
	local row = frame(communityPage, {
		Size = UDim2.new(1, 0, 0, 74), Position = UDim2.fromOffset(0, (i - 1) * 82),
		BackgroundColor3 = CARD_LOCK, ZIndex = 3,
	})
	corner(row, 18)
	local rst = stroke(row, PANEL_EDGE, 3)
	shade(row, 1.08, 0.84)

	-- The header's gift tile, repeated: 14px radius, the same well fill, the same 2px edge and a sheen. Three
	-- icons in a row are the most repeated shape on this tab, so matching them to the one at the top of the
	-- panel is most of what makes the page feel like one design.
	local tile = frame(row, {
		Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(12, 10),
		BackgroundColor3 = WELL, ZIndex = 4,
	})
	corner(tile, 14); stroke(tile, PANEL_EDGE, 2); sheen(tile, 14)
	label(tile, { Text = t.icon, Font = Enum.Font.FredokaOne, TextScaled = true,
		Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })

	local nameLbl = label(row, { Text = t.title, Font = Enum.Font.FredokaOne, TextSize = 19, TextColor3 = WHITE,
		Size = UDim2.new(1, -240, 0, 22), Position = UDim2.fromOffset(76, 13),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	tstroke(nameLbl, INK, 2)
	label(row, { Text = t.hint, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = DESC,
		Size = UDim2.new(1, -240, 0, 16), Position = UDim2.fromOffset(76, 36),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	label(row, { Text = "+5 PET LEVELS", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = GOLD,
		Size = UDim2.new(1, -240, 0, 14), Position = UDim2.fromOffset(76, 53),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })

	local act = button(row, {
		Size = UDim2.fromOffset(132, 44), Position = UDim2.new(1, -16, 0.5, -2), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = ORANGE, Text = "CLAIM", Font = Enum.Font.FredokaOne, TextSize = 17,
		TextColor3 = INK, AutoButtonColor = true, Active = true, ZIndex = 5,
	})
	corner(act, 12)
	local ast = stroke(act, INK, 3)
	local lip = raised(act, ORANGE_DEEP, 4); lip.ZIndex = 4
	do local g = Instance.new("UIGradient"); g.Enabled = false; g.Parent = act end
	sheen(act, 12); feel(act)

	socialRows[t.id] = { row = row, act = act, lip = lip, st = ast, cardStroke = rst }
end

local bonusRow = frame(communityPage, {
	Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 250),
	BackgroundColor3 = CARD_GIFT, ZIndex = 3,
})
corner(bonusRow, 18)
local bonusStroke = stroke(bonusRow, GIFT_EDGE, 3)
label(bonusRow, { Text = "\xF0\x9F\x8F\x86", Font = Enum.Font.FredokaOne, TextSize = 26,
	Size = UDim2.fromOffset(44, 56), Position = UDim2.fromOffset(12, 0),
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
local bonusLbl = label(bonusRow, {
	Text = "ALL THREE DONE -- 0 / 3", Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = WHITE,
	Size = UDim2.new(1, -80, 0, 22), Position = UDim2.fromOffset(64, 8),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
tstroke(bonusLbl, INK, 2)
local bonusSub = label(bonusRow, {
	Text = "Finish all three community tasks for a bonus", Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = WHITE, Size = UDim2.new(1, -80, 0, 16), Position = UDim2.fromOffset(64, 32),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
-- Both banner lines get the dark glyph outline the rest of the panel's status text has. Bare text on the
-- day-7 pink was the one place on the page where a line had nothing separating it from its background.
tstroke(bonusSub, INK, 2)

--======================================================================
-- BADGES
--======================================================================
-- Recomputed whenever ANY tab's state moves, because the badge on a tab you are not looking at is the whole
-- point: it is the only thing telling you the other two tabs have something waiting.
local crateClaimable = false -- SPACE: the Daily Crate row on the DAILY tab (see below)
local function syncBadges()
	tabBadge.daily.Visible     = dailyClaimable or crateClaimable
	tabBadge.timed.Visible     = timedClaimable
	tabBadge.community.Visible = socialClaimable
end

--======================================================================
-- SPACE: DAILY CRATE ROW  (DAILY tab, under the streak ladder)
--======================================================================
-- Space's free daily crate spin, kept reachable from the hub. State comes off the server's push on
-- DailyCrateRemotes.DailyState ({ ready = bool, secondsLeft = number }); before the first push it falls back to
-- the HUD's _G.crateIsClaimable(). The SPIN button closes this panel and hands off to _G.skinCrateDailySpin().
local crateKnown, crateIsReady, crateSeconds = false, false, 0
local function crateReady()
	if crateKnown then return crateIsReady end
	return _G.crateIsClaimable ~= nil and _G.crateIsClaimable() == true
end
local function hms(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

local crateRow = frame(dailyPage, {
	Size = UDim2.new(1, -ROW_MARGIN * 2, 0, 40), Position = UDim2.fromOffset(ROW_MARGIN, 322),
	BackgroundColor3 = CARD_LOCK, ZIndex = 3,
})
corner(crateRow, 14)
local crateStroke = stroke(crateRow, PANEL_EDGE, 3)
shade(crateRow, 1.08, 0.84)
do
	local tile = frame(crateRow, {
		Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(6, 5), BackgroundColor3 = WELL, ZIndex = 4,
	})
	corner(tile, 9); stroke(tile, PANEL_EDGE, 2)
	label(tile, { Text = "\xF0\x9F\x8E\x81", Font = Enum.Font.FredokaOne, TextScaled = true,
		Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	local t = label(crateRow, { Text = "DAILY CRATE", Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHITE,
		Size = UDim2.fromOffset(140, 40), Position = UDim2.fromOffset(46, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	tstroke(t, INK, 2)
end
local crateStatus = label(crateRow, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = DESC,
	Size = UDim2.new(1, -330, 0, 40), Position = UDim2.fromOffset(186, 0),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
tstroke(crateStatus, INK, 2)
local crateAct = button(crateRow, {
	Size = UDim2.fromOffset(120, 30), Position = UDim2.new(1, -8, 0.5, -2), AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = WELL, Text = "\xF0\x9F\x94\x92", Font = Enum.Font.FredokaOne, TextSize = 16,
	TextColor3 = LOCK_TEXT, ZIndex = 5,
})
corner(crateAct, 10)
local crateActStroke = stroke(crateAct, INK, 3)
local crateLip = raised(crateAct, ACT_LIP, 4); crateLip.ZIndex = 4
do local g = Instance.new("UIGradient"); g.Enabled = false; g.Parent = crateAct end
sheen(crateAct, 10); feel(crateAct)

local function renderCrate()
	local ready = crateReady()
	crateClaimable = ready
	if ready then
		crateRow.BackgroundColor3 = CARD_LIVE
		crateStroke.Color = GOLD; crateStroke.Thickness = 4
		crateStatus.Text = "READY!"; crateStatus.TextColor3 = GOLD
		paintAction(crateAct, crateLip, crateActStroke, "claim")
		crateAct.Text = "SPIN!"
	else
		crateRow.BackgroundColor3 = CARD_LOCK
		crateStroke.Color = PANEL_EDGE; crateStroke.Thickness = 3
		crateStatus.Text = crateKnown and ("Next crate in " .. hms(crateSeconds)) or "Checking..."
		crateStatus.TextColor3 = DESC
		paintAction(crateAct, crateLip, crateActStroke, "locked")
	end
	syncBadges()
end

task.spawn(function()
	local remotes = RSx:WaitForChild("DailyCrateRemotes", 30)
	local ev = remotes and remotes:WaitForChild("DailyState", 10)
	if not ev then
		warn("[Rewards] DailyCrateRemotes/DailyState missing -- the Daily Crate row falls back to _G.crateIsClaimable")
		return
	end
	ev.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then return end
		crateIsReady = state.ready == true
		crateSeconds = tonumber(state.secondsLeft) or 0
		crateKnown = true
		renderCrate()
	end)
end)

-- the countdown tick: the server pushes occasionally; this fills the seconds in between.
task.spawn(function()
	while true do
		task.wait(1)
		if crateKnown and not crateIsReady and crateSeconds > 0 then
			crateSeconds = crateSeconds - 1
		end
		renderCrate()
	end
end)

local crateBusy = false
crateAct.MouseButton1Click:Connect(function()
	if crateBusy or not crateReady() then return end
	crateBusy = true
	task.delay(1.5, function() crateBusy = false end)
	if _G.playUIClick then pcall(_G.playUIClick) end
	-- The crate reveal is its own full-screen moment: get this panel out of its way first.
	gui.Enabled = false
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then pcall(_G.MainMenuManager.notifyClosed, "Rewards") end
	-- A realm without the skin-crate daily spin (the Dino Realm) opens its Meteor Crate instead.
			if not _G.skinCrateDailySpin then local ev = game:GetService("ReplicatedStorage"):FindFirstChild("OpenMeteorCrate"); if ev then ev:Fire() end end
			if _G.skinCrateDailySpin then
		pcall(_G.skinCrateDailySpin)
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, "Crate is loading -- try again in a moment!", Color3.fromRGB(255, 170, 60), 3)
	end
end)
renderCrate()

--======================================================================
-- DAILY: render
--======================================================================
local dailyLatest, dailyBusy = nil, false

local function renderDaily(s)
	dailyLatest = s
	dailyClaimable = s.canClaim == true

	streakLbl.Text = string.format("\xF0\x9F\x94\xA5 DAY <font color=\"#FFD638\">%d</font> STREAK", s.streak or 0)

	local ladder = s.ladder or {}
	local curDay = s.day or 1
	for i = 1, DAYS do
		local card    = dayCards[i]
		local claimed = (i < curDay) or (i == curDay and s.claimedToday == true)
		local current = (i == curDay and s.canClaim == true)

		-- Day 7 does not pay from the token ladder any more, so it must not read from it: the server still
		-- sends the whole {20,30,...,200} array (it is one shared table and days 1-6 do use it), and printing
		-- ladder[7] here would advertise 200 Tokens for a card that pays a crate.
		card.amt.Text = (card.isGift and s.day7Crate) and "x1 SPIN" or ("x" .. tostring(ladder[i] or 0))
		card.glow.Visible = current
		-- Space: the server names the day-7 crate (Starter -- the hub caps tickets at 300/day, a Mythic would dwarf it).
		-- No day7Crate = this realm has no free spin (the Dino Realm): day 7 pays its ladder tickets instead.
		local spins = type(s.day7Crate) == "string"
		if card.crateLbl then card.crateLbl.Text = spins and (string.upper(s.day7Crate) .. " CRATE") or "BIG DAY" end
		if card.spinLbl then card.spinLbl.Text = spins and "FREE SPIN!" or "TICKETS!" end

		if current then
			card.frame.BackgroundColor3 = CARD_LIVE
			card.cardStroke.Color = GOLD; card.cardStroke.Thickness = 5
			paintAction(card.act, card.lip, card.st, "claim")
		elseif claimed then
			card.frame.BackgroundColor3 = CARD_DONE
			card.cardStroke.Color = GREEN; card.cardStroke.Thickness = 3
			paintAction(card.act, card.lip, card.st, "done")
		else
			-- LOCKED sits on its own darker, less saturated fill, so the row reads as THREE distinct states
			-- rather than "the bright one and six others".
			card.frame.BackgroundColor3 = card.isGift and CARD_GIFT or CARD_LOCK
			card.cardStroke.Color = card.isGift and GIFT_EDGE or PANEL_EDGE
			card.cardStroke.Thickness = 3
			paintAction(card.act, card.lip, card.st, "locked")
		end
	end

	if s.canClaim then
		dailyStatus.Text = "Day " .. tostring(curDay) .. " is ready -- claim " .. TOKEN_ICON .. " +" .. tostring(s.todayReward or 0)
		dailyStatus.TextColor3 = GOLD
	else
		dailyStatus.Text = "Claimed! Back tomorrow for " .. TOKEN_ICON .. " +" .. tostring(s.nextReward or 0)
		dailyStatus.TextColor3 = DESC
	end
	syncBadges()
end

-- ONE CLAIM PATH for all seven buttons: the server decides which day that means. Seven buttons, one action.
local function claimDaily()
	if not dailyClaimable or dailyBusy then return end
	if _G.playUIClick then pcall(_G.playUIClick) end
	playClaim()
	dailyBusy = true
	for _, c in ipairs(dayCards) do c.act.Active = false; c.act.AutoButtonColor = false end
	pcall(function() dailyRemote:FireServer("claim") end)
	task.delay(1.2, function() dailyBusy = false end) -- the server re-pushes; this only debounces double-taps
end
for _, c in ipairs(dayCards) do c.act.MouseButton1Click:Connect(claimDaily) end

if dailyRemote then dailyRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "state" and type(a) == "table" then
		renderDaily(a)
	elseif kind == "result" then
		local ok, _amt, msg = a, b, c
		if ok then
			local d = dailyLatest and dailyLatest.day or 1
			local card = dayCards[d]
			if card then
				card.scale.Scale = 1
				TweenService:Create(card.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.14 }):Play()
				task.delay(0.18, function()
					TweenService:Create(card.scale, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
				end)
				sparkle(card.frame)
			end
			if _G.showHudBanner then pcall(_G.showHudBanner, TOKEN_ICON .. " " .. tostring(msg or "Streak claimed!"), GOLD, 3) end
		else
			if _G.showHudBanner then pcall(_G.showHudBanner, tostring(msg or "Come back tomorrow!"), Color3.fromRGB(255, 170, 60), 3) end
		end
	end
end) end

--======================================================================
-- TIMED: render + live countdown
--======================================================================
local timedBusy = false
local localSessionSec, lastPushAt = 0, os.clock()

local function renderTimed()
	local s = timedState
	if not s then return end
	local rungs = s.rungs or {}
	local now = localSessionSec
	timedClaimable = false

	-- EVERY rung counts down to ITS OWN milestone, not just the next one. The card is the thing a player
	-- points at ("how long until the 45?"), and answering that on one card only meant the other five were
	-- unreadable until their turn came round. Each line below is computed from that card's own r.sec, so the
	-- 10 MIN card counts to ten minutes while the 60 MIN card counts to an hour.

	for i = 1, RUNGS do
		local card = timedCards[i]
		local r = rungs[i]
		if not r then
			card.frame.Visible = false
		else
			card.frame.Visible = true
			card.mins.Text = math.floor(r.sec / 60) .. " MIN"
			card.icon.Text = r.icon or TOKEN_ICON
			card.qty.Text  = r.label or ""

			local ready = (not r.claimed) and now >= r.sec
			card.glow.Visible = ready
			if ready then timedClaimable = true end

			-- THE SUB LINE NOW SPEAKS ON EVERY CARD, in one of three states: counting down, arrived, or
			-- collected. It is still the same reserved fixed-height slot built with the card (16px at y=114,
			-- occupied whether or not there is text in it), so the six cards stay exactly the same height and
			-- nothing below it moves as a card changes state -- which is the whole reason the slot is fixed
			-- rather than auto-sized.
			if r.claimed then
				card.frame.BackgroundColor3 = CARD_DONE
				card.cardStroke.Color = GREEN; card.cardStroke.Thickness = 3
				card.sub.Text = "CLAIMED"
				card.sub.TextColor3 = GOLD
				paintAction(card.act, card.lip, card.st, "done")
			elseif ready then
				card.frame.BackgroundColor3 = CARD_LIVE
				card.cardStroke.Color = GOLD; card.cardStroke.Thickness = 5
				card.sub.Text = "READY"
				card.sub.TextColor3 = GOLD
				paintAction(card.act, card.lip, card.st, "claim")
			else
				card.frame.BackgroundColor3 = CARD_LOCK
				card.cardStroke.Color = PANEL_EDGE; card.cardStroke.Thickness = 3
				-- max(0, ...) because localSessionSec is extrapolated from os.clock() between server pushes
				-- and can tick a hair past r.sec before the push that flips this rung to ready lands. Without
				-- it the card would flash "READY IN -0:01" in that gap.
				card.sub.Text = "READY IN " .. mmss(math.max(0, r.sec - now))
				card.sub.TextColor3 = GOLD
				paintAction(card.act, card.lip, card.st, "locked")
			end
		end
	end

	-- SESSION PROGRESS runs to the LAST rung, so the bar answers "how far through the whole track am I",
	-- not "how far to the next card" -- the cards already answer the second question, each for itself.
	-- MEASURED ACROSS THE CURRENT PASS, not the whole session. passStart is where this lap began (0 on the
	-- first one), so the bar runs 0..100% on every lap instead of sitting pinned near full from pass 1 on,
	-- when `now` is an hour bigger than the lap it is drawing.
	local last  = rungs[RUNGS] and rungs[RUNGS].sec or 3600
	local start = s.passStart or 0
	local track = timedPage:FindFirstChild("Track", true)
	if track then
		local fill = track:FindFirstChild("Fill")
		local txt  = track:FindFirstChild("Text")
		local pct  = math.clamp((now - start) / math.max(1, last - start), 0, 1)
		if fill then
			fill.Size = UDim2.new(pct, 0, 1, 0)
			local cap = fill:FindFirstChild("Cap")
			-- The cap is the head of the bar, so it only exists once the bar does. Showing it at zero would
			-- put a floating dot at the left edge, which is the thing this replaced.
			if cap then cap.Visible = pct > 0.005 end
		end
		if txt then txt.Text = mmss(now) .. "  /  " .. mmss(last) end
	end

	-- PASS 1 is left unlabelled: on the very first lap there is no second lap to distinguish it from, and
	-- "PASS 1" on a track nobody has looped yet is a question rather than an answer.
	local cap = timedPage:FindFirstChild("PassCaption", true)
	if cap then
		local pass = s.pass or 0
		cap.Text = (pass > 0) and ("SESSION PROGRESS  â¢  PASS " .. (pass + 1)) or "SESSION PROGRESS"
	end
	syncBadges()
end

local function claimTimed(index)
	if timedBusy or not timedRemote then return end
	local r = timedState and timedState.rungs and timedState.rungs[index]
	if not r or r.claimed or localSessionSec < r.sec then return end
	if _G.playUIClick then pcall(_G.playUIClick) end
	playClaim()
	timedBusy = true
	pcall(function() timedRemote:FireServer("claim", index) end)
	task.delay(1.0, function() timedBusy = false end)
end
for i = 1, RUNGS do
	timedCards[i].act.MouseButton1Click:Connect(function() claimTimed(i) end)
end

if timedRemote then
	timedRemote.OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "state" and type(a) == "table" then
			timedState = a
			-- The server's clock is the truth; the local one only fills the gap BETWEEN pushes so the
			-- countdown ticks every second instead of jumping every twenty.
			localSessionSec = a.sessionSec or 0
			lastPushAt = os.clock()
			renderTimed()
		elseif kind == "result" then
			local ok, _amt, msg = a, b, c
			if ok then
				if _G.showHudBanner then pcall(_G.showHudBanner, tostring(msg or "Claimed!"), GOLD, 3) end
			else
				if _G.showHudBanner then pcall(_G.showHudBanner, tostring(msg or "Not yet!"), Color3.fromRGB(255, 170, 60), 3) end
			end
		end
	end)
end

-- the countdown tick. Cheap, and it stops mattering the moment the panel is closed.
task.spawn(function()
	while true do
		task.wait(1)
		if timedState then
			localSessionSec = (timedState.sessionSec or 0) + math.floor(os.clock() - lastPushAt)
			if gui.Enabled and activeTab == "timed" then renderTimed() else syncBadges() end
		end
	end
end)

--======================================================================
-- COMMUNITY: render
--======================================================================
local function renderSocial()
	local doneCount = 0
	socialClaimable = false
	for _, t in ipairs(COMMUNITY) do
		local row = socialRows[t.id]
		local done = socialState[t.id] == true
		if done then doneCount = doneCount + 1 else socialClaimable = true end
		if done then
			row.row.BackgroundColor3 = CARD_DONE
			row.cardStroke.Color = GREEN; row.cardStroke.Thickness = 3
			paintAction(row.act, row.lip, row.st, "done")
			-- The WORD, not just a tick. On a row this wide a lone checkmark on a green slab still reads as a
			-- button you could press; "CLAIMED" cannot be misread, and it is the difference between the three
			-- rows saying "done" and saying "do me".
			row.act.Text = "CLAIMED"; row.act.TextSize = 15
			row.act.TextColor3 = Color3.fromRGB(214, 255, 224)
		else
			row.row.BackgroundColor3 = CARD_LOCK
			row.cardStroke.Color = PANEL_EDGE; row.cardStroke.Thickness = 3
			paintAction(row.act, row.lip, row.st, "claim")
		end
	end

	bonusLbl.Text = "ALL THREE DONE -- " .. doneCount .. " / 3"
	if doneCount >= 3 then
		bonusStroke.Color = GOLD; bonusStroke.Thickness = 4
		bonusLbl.TextColor3 = GOLD
		-- Space: the server pays the bonus itself the moment the third lands (state.bonus = paid).
		bonusSub.Text = (socialState.bonus == true) and "Bonus +5 pet levels paid -- thanks for supporting the game!"
			or "Complete! TAP HERE to collect +5 pet levels on your equipped pet"
		bonusSub.TextColor3 = WHITE
	else
		bonusStroke.Color = GIFT_EDGE; bonusStroke.Thickness = 3
		bonusLbl.TextColor3 = WHITE
		bonusSub.Text = "Finish all three for a bonus +5 pet levels"
		bonusSub.TextColor3 = WHITE
	end
	syncBadges()
end

-- THE ALL-THREE ROW IS A BUTTON while its bonus is unpaid: the server pays it automatically when the third reward
-- lands, but a maxed or missing pet holds it back -- this is how the player collects it after equipping another.
do
	local lastBonusTap = 0
	bonusRow.Active = true
	bonusRow.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not (socialState.like and socialState.favorite and socialState.group) or socialState.bonus then return end
		if os.clock() - lastBonusTap < 1 then return end
		lastBonusTap = os.clock()
		if _G.playUIClick then pcall(_G.playUIClick) end
		if socialRemote then pcall(function() socialRemote:FireServer("claim", "bonus") end) end
	end)
end

for _, t in ipairs(COMMUNITY) do	socialRows[t.id].act.MouseButton1Click:Connect(function()
		if socialState[t.id] then return end
		if _G.playUIClick then pcall(_G.playUIClick) end
		playClaim()
		-- Fires the SAME intent SocialRewards' own panel fires. The server checks group membership for real
		-- and owns the one-time flags, so this is a request in exactly the way that panel's button is.
		if socialRemote then pcall(function() socialRemote:FireServer("claim", t.id) end) end
	end)
end

if socialRemote then
	socialRemote.OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "state" and type(a) == "table" then
			socialState = a; renderSocial()
		elseif kind == "result" then
			local which, ok, msg = a, b, c
			if ok and which then
				socialState[which] = true
				local row = socialRows[which]
				if row then sparkle(row.row) end
				renderSocial()
			end
			if _G.showHudBanner then
				pcall(_G.showHudBanner, tostring(msg or (ok and "Claimed!" or "Couldn't claim")),
					ok and GOLD or Color3.fromRGB(255, 170, 60), 3)
			end
		end
	end)
end

--======================================================================
-- OPEN / CLOSE   (the same surface the recovered file exposed)
--======================================================================
local function setOpen(open)
	gui.Enabled = open and true or false
	if open then
		panel.Visible = true
		refit()
		if activeTab == "timed" then renderTimed() end
		renderCrate()
		if _G.MainMenuManager and _G.MainMenuManager.notifyOpened then pcall(_G.MainMenuManager.notifyOpened, "Rewards") end
	else
		if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then pcall(_G.MainMenuManager.notifyClosed, "Rewards") end
	end
end

closeBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	setOpen(false)
end)
backBtn.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	setOpen(false)
	-- MORE+ is where this page is reached from, so BACK goes there rather than dropping you on the world.
	if _G.railGuardOpenMore then pcall(_G.railGuardOpenMore)
	elseif _G.setMoreOpen then pcall(_G.setMoreOpen, true) end
end)
-- The dim backdrop is a Frame, not a button: closing is the X, matching every other panel in this game, so a
-- stray screen tap can never shut the page mid-claim.

-- SPACE: registered as "Rewards" (the name Space's menu manager and MORE+ already use), retried until the
-- manager exists, the same way RewardsClient does it.
task.spawn(function()
	for _ = 1, 100 do
		if _G.MainMenuManager and _G.MainMenuManager.register then
			pcall(_G.MainMenuManager.register, "Rewards", function() gui.Enabled = false end)
			return
		end
		task.wait(0.1)
	end
end)

local function openOn(tab) showTab(tab); setOpen(true) end
local function anyPending() return dailyClaimable or crateClaimable or timedClaimable or socialClaimable end
-- Every handle this hub owns, in one place, so the stale-copy guard below can re-assert them in one call.
local function publish()
	_G.toggleDailyStreak  = function() setOpen(not gui.Enabled) end
	_G.openDailyStreak    = function() setOpen(true) end
	_G.dailyStreakPending = function() return dailyClaimable end
	-- The whole hub's badge, for the MORE+ "Rewards" card: true when ANY tab (or the Daily Crate) has something.
	_G.rewardsPending     = anyPending
	_G.toggleRewardsHub   = function() setOpen(not gui.Enabled) end
	-- Space's older Rewards panel names, forwarded here so every existing caller lands on this hub.
	_G.toggleRewards      = function()
		if gui.Enabled then setOpen(false) else openOn("daily") end
	end
	_G.toggleDailyRewards  = function() openOn("daily") end
	_G.toggleSocialRewards = function() openOn("community") end
	_G.rewardsAnythingClaimable = anyPending
end
publish()

syncTabs()
renderSocial()

--======================================================================
-- RETIRE THE STALE BAKED-IN COPY
--======================================================================
-- Rojo only ADDS. Until the old DailyStreak LocalScript is deleted in Studio it runs alongside this one,
-- builds a SECOND DailyStreakGui and overwrites _G.toggleDailyStreak -- so MORE+ would open whichever panel
-- happened to load last, and this hub would look like it did nothing.
do
	local retired = 0
	local function sweep()
		for _, g in ipairs(PlayerGui:GetChildren()) do
			if g ~= gui and g:IsA("ScreenGui") and g.Name == "DailyStreakGui" then
				g:Destroy(); retired = retired + 1
			end
		end
	end
	sweep()
	PlayerGui.ChildAdded:Connect(function(ch)
		if ch ~= gui and ch:IsA("ScreenGui") and ch.Name == "DailyStreakGui" then
			task.defer(function() if ch.Parent then ch:Destroy(); retired = retired + 1 end end)
		end
	end)
	task.spawn(function()
		local mine = _G.toggleDailyStreak
		for _ = 1, 12 do
			task.wait(0.5)
			sweep()
			-- SPACE: RewardsClient publishes the same toggleRewards / rewardsAnythingClaimable names, so those
			-- are watched too -- whichever script loads last, the handles end up pointing at THIS hub.
			if _G.toggleDailyStreak ~= mine or _G.rewardsAnythingClaimable ~= anyPending then
				publish()
				mine = _G.toggleDailyStreak
			end
		end
		if retired > 0 then
			warn("[Rewards] retired " .. retired .. " STALE duplicate panel(s) from a baked-in DailyStreak copy. "
				.. "Delete the old DailyStreak LocalScript in Studio for good.")
		end
	end)
end

print("[Rewards] hub ready -- DAILY / TIMED / COMMUNITY (_G.toggleRewardsHub, _G.toggleDailyStreak)")
