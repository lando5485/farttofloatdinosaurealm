--[[
	NotifyCenter.luau  (StarterPlayerScripts.NotifyCenter)

	THE ANNOUNCEMENTS BANNER — ported from Fart to Float's NotifyCenter, re-skinned to the space theme.

	ONE OWNER FOR EVERY TRANSIENT BANNER. In the first realm five separate ScreenGuis (arrival / announce /
	hud notice / purchase / event) all rested at the SAME top-centre pixel with nothing coordinating them —
	land on a new island while another player's news fires and the two banners drew straight through each
	other. Space Realm has the same shape of problem: PhoneHUD hands out ONE shared banner spot, and every
	banner client aims at it independently. This module is the coordinator that spot was always missing.

	Two ideas do the work (both lifted from FtF):
	  1) LANES. Notifications are placed by KIND, not all dumped top-centre.
	       HERO   = your own big moments (the shared PhoneHUD banner spot — the prime slot)
	       SOCIAL = other players' news (top-left, small pills, never blocks you)
	  2) PRIORITY. The HERO lane shows exactly ONE card at a time. A more important banner PREEMPTS a less
	     important one (the demoted one goes back on the queue, it is never eaten); equal-or-lower ones QUEUE.
	     So "WELCOME TO NEPTUNE" is never buried under "Daily Reward Ready".

	===== SIZING (FtF's hero card, measured and kept) =====
	FtF's card is 500 x 65 top-centre, corner 12, slides in over 0.4s (Back/Out) and out over 0.3s (Quad),
	default hold 3.5s. The card FOOTPRINT is FtF's and is UNTOUCHED: PhoneHUD.BANNER_SIZE (500x65), or 92 tall
	when the card carries a third line. What changed is the slot fractions INSIDE it, which are now sized around
	the type scale rather than the type being shrunk into them:
	    top  y 0.03  h 0.28  ->  at 500x92: y2.8 h25.8   (holds the 26px kicker)
	    main y 0.30  h 0.42  ->  at 500x92: y27.6 h38.6  (holds the 34px name)
	    sub  y 0.735 h 0.24  ->  at 500x92: y67.6 h22.1  (holds the 22px tagline)
	    main-only y 0.10 h 0.80 -> at 500x65: y6.5 h52
	Space Realm adds ONE slot FtF's card doesn't have: an optional third `sub` line for the planet-arrival
	taglines ("Closest world to the sun."). A card with a sub line grows to 92 on every device and the
	three lines re-flow; without one the geometry above is untouched.

	===== THEME =====
	FtF's card is a flat coloured rectangle with a black outline. This one is the Space Realm panel: deep navy
	starfield fill, top gloss, a neon gradient border + outer glow in the banner's ACCENT colour, FredokaOne
	headline over a Gotham kicker. The accent is per-banner (`spec.color`), so a Mercury arrival glows grey,
	Neptune blue, a purchase green — recoloured live on the one persistent card rather than rebuilt.

	===== PLACEMENT =====
	The hero card sits at the SHARED banner spot PhoneHUD owns (PhoneHUD.bannerOn/bannerOff), re-read at SHOW
	time so it always uses the live ResponsiveUI scale — the same spot the other banner clients already use.
	The SOCIAL lane is top-left (x12, from y10), capped at 2 pills so the stack always ends above the left
	rail (which starts at y96).

	===== USAGE =====
		local Notify = require(script.Parent:WaitForChild("NotifyCenter"))
		Notify.push({ top = "🚀 WELCOME TO", text = "NEPTUNE", sub = "…", color = …,
		              priority = Notify.PRIORITY.PLANET, duration = 4 })
		Notify.pin("watering", { text = "Fill the can at the water tank" })   -- standing instruction
		Notify.unpin("watering")

	===== TYPE IS EXPLICIT, NOT SCALED-TO-FIT (see THE BANNER TYPE SCALE below) =====
	Every line on every banner used to be TextScaled with a UITextSizeConstraint ceiling, which is a RESULT,
	not a size: the rendered size fell out of whichever slot the line happened to land in, so the same headline
	came out one size on an arrival card and another on a purchase card -- and the PLANET NAME, the one word
	the card exists to say, rendered SMALLER than the "WELCOME TO" kicker above it and the tagline below it.
	The lines now carry explicit TextSize values from ONE table (NotifyCenter.TEXT), so the hierarchy is
	identical on every banner and every planet: NAME (34) > HEADER (26) > SUB (22). All three are BOLD faces.
	TextScaled is off everywhere and no UITextSizeConstraint is left behind to clamp them. TextWrapped is
	opt-in and only for a headline that is a SENTENCE. (A UIScale scales explicit TextSize just as it scales
	everything else, so ResponsiveUI's phone pass keeps working untouched.)

	It is a MODULE, not a client script, deliberately: FtF's copy published `_G.NotifyCenter` and then had to
	fight a load-order race to keep it (see its "HOLD THE CLAIM" block). A require has no such race — the
	first caller builds the GUI, everyone else gets the same table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService") -- measures a headline so wrapping is opt-in, not blanket

-- DINO PORT: SpaceTheme does not exist here. The five things this module reads from it, in jungle colours
-- (JungleChrome: olive 122,142,82 / dark green 26,48,30 / edge 40,52,38 / parchment 232,209,158).
local SpaceTheme = {
	NeonCyan      = Color3.fromRGB(86, 170, 78),   -- default card accent: leaf green
	StarfieldFill = Color3.fromRGB(26, 48, 30),    -- the card before its first accent is painted
	Panel         = Color3.fromRGB(26, 48, 30),    -- social pill fill
	TextPrimary   = Color3.fromRGB(255, 250, 236), -- warm white type over the coloured card
}
function SpaceTheme.addNeonBorder(inst, col, th)
	local s = Instance.new("UIStroke"); s.Color = col or Color3.fromRGB(160, 200, 120); s.Thickness = th or 1.5
	s.Parent = inst; return s
end
-- DINO PORT: this realm's PhoneHUD is the OLD 300x80 spot. The banner spot is inlined at the first realm's
-- spec instead: 500x65 authored, anchor (0.5,0), X always 0.5,0. Resting Y is 0 because TopCenterStack wraps
-- NotifyHero in its container and adds the 8px top margin + stacks it from AbsoluteSize.
local PhoneHUD = {
	BANNER_SIZE   = UDim2.fromOffset(500, 65),
	BANNER_ANCHOR = Vector2.new(0.5, 0),
}
function PhoneHUD.bannerOn() return UDim2.new(0.5, 0, 0, 0) end
function PhoneHUD.bannerOff() return UDim2.new(0.5, 0, 0, -110) end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotifyCenter = {}

-- ===== PRIORITIES (higher wins the HERO slot) =====
-- Exported so callers name the moment instead of hard-coding a number. FtF's ladder, with ISLAND renamed.
local PRIORITY = {
	PLANET   = 100, -- "WELCOME TO NEPTUNE" — you physically arrived at a new planet. The biggest moment in the game.
	PURCHASE = 90,  -- a real Robux/gamepass purchase went through — must never be swallowed.
	EVENT    = 80,  -- a server event started (meteor shower, 2x coins, …).
	TASK     = 70,  -- planet task news: "All tasks done — see astronaut!", gate nudges, step hints.
	                --   Above REWARD (a task line is an INSTRUCTION the player is meant to act on right now, not a
	                --   nag) and below EVENT/PURCHASE (those are time-critical or paid-for and must not be delayed).
	REWARD   = 40,  -- "Daily Reward Ready" / "Stomach Upgrade Available" — a nudge, not news.
	SOCIAL   = 10,  -- another player's news. Routed to its own lane; never competes.
}
NotifyCenter.PRIORITY = PRIORITY

local ACCENT_DEFAULT = SpaceTheme.NeonCyan
local SHOW_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)  -- FtF: 0.4 Back/Out
local SHOW_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad)                            -- FtF: 0.3 Quad
local DEFAULT_DURATION = 3.5                                                          -- FtF: 3.5s hold

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end
-- Text outlines exist for CONTRAST, not for weight. They used to be a flat black 2px on every label, which on a
-- 65px card put a hard ink line around 16px type and turned the small lines to mush. They are thinner and
-- partly transparent now: still enough separation from the card, no longer a drawn border around each glyph.
-- FtF's outline, exactly: opaque black, 2px by default (1.5 on the tagline). It reads heavy written down and
-- is the reason white type stays legible on a saturated fill -- which is what the card is now.
local function textStroke(l, thickness)
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = thickness or 2
	s.Parent = l
	return s
end
-- ===== THE BANNER TYPE SCALE =====
-- ONE definition of how big each line on a banner is, and it is EXPLICIT. Every banner in the realm reads
-- these numbers -- the hero card below, and the frames other clients build and hand to styleAsBanner -- so
-- "how big is a banner's text" is decided here and inherited, never re-guessed per planet or per caller.
--
-- The ORDER is the point: NAME > HEADER > SUB. The name line is the biggest thing on the card.
NotifyCenter.TEXT = {
	HEADER    = 26, -- the kicker line ("WELCOME TO")
	NAME      = 34, -- the headline ("MERCURY") -- the largest line on the card
	SUB       = 22, -- the tagline ("Closest world to the sun.")
	NAME_WRAP = 20, -- a headline that is a SENTENCE and wraps onto 2-3 rows of the tall card
	PILL      = 18, -- a standing readout on a banner-styled card (the race climb / timer)
	PILL_SUB  = 16, -- its secondary line (the race leader)
	PILL_BIG  = 26, -- a readout that is the ONLY line on its card (the event countdown)
	SENTENCE  = 20, -- a banner whose whole content is one sentence (friend crate, sun explosion) -- wraps
	SOCIAL    = 17, -- the top-left social pills
}

-- The faces. ALL BOLD. FredokaOne is a single-weight display face and is already the heavy one, so the name
-- line keeps it (it IS the bold weight of the family the banners are built in); the kicker moves up to Black,
-- and the tagline comes off Gotham Regular, which was the one genuinely light thing on the card.
NotifyCenter.FONT = {
	HEADER    = Enum.Font.GothamBlack,
	NAME      = Enum.Font.FredokaOne,
	SUB       = Enum.Font.GothamBold,
	NAME_WRAP = Enum.Font.FredokaOne,
	PILL      = Enum.Font.FredokaOne,
	PILL_SUB  = Enum.Font.FredokaOne,
	PILL_BIG  = Enum.Font.FredokaOne,
	SENTENCE  = Enum.Font.FredokaOne,
	SOCIAL    = Enum.Font.GothamBold,
}

-- Apply one role of the scale to a label: TextScaled OFF, an explicit TextSize, a bold face -- and any
-- UITextSizeConstraint on the label REMOVED. That last part matters: a UITextSizeConstraint clamps the
-- TextSize property whether or not TextScaled is on, so a leftover MaxTextSize = 17 would quietly undo the
-- size we just set and put us straight back in the bug.
--
-- `wrapped` is opt-in, for lines that genuinely overflow their slot (a sentence, not a planet name).
function NotifyCenter.styleBannerText(label: TextLabel, role: string, wrapped: boolean?): TextLabel
	label.TextScaled = false
	label.Font = NotifyCenter.FONT[role] or NotifyCenter.FONT.NAME
	label.TextSize = NotifyCenter.TEXT[role] or NotifyCenter.TEXT.NAME
	label.TextWrapped = wrapped == true
	for _, d in ipairs(label:GetChildren()) do
		if d:IsA("UITextSizeConstraint") then
			d:Destroy()
		end
	end
	return label
end

-- The card's footprint. ONE authored size on every device -- PhoneHUD.BANNER_SIZE, which is the house 500x65.
--
-- ===== THERE IS NO PHONE BRANCH ANY MORE =====
-- This used to return 500x65 on desktop and PhoneHUD.BANNER_SIZE on a phone, back when that constant was the
-- post-scale 300x80. So the same card was authored at two different sizes AND aspect ratios depending on the
-- device, and the phone one was then scaled a second time by ResponsiveUI -- roughly 180x48 of real pixels
-- against the desktop card's 500x65. Author the design size once; ResponsiveUI's global UIScale is the only
-- thing that should be turning it into device pixels.
--
-- `tall` is true for a card that needs the extra row: one with a sub line, or a WRAPPED one (a task line is a
-- whole sentence and has to wrap onto 2-3 rows instead of shrinking to nothing on one). Both use the SAME height,
-- so cardSize(true) is still the tallest card there is and pillSpot below stays correct.
local function cardSize(tall: boolean): UDim2
	return UDim2.fromOffset(PhoneHUD.BANNER_SIZE.X.Offset, tall and 92 or PhoneHUD.BANNER_SIZE.Y.Offset)
end

-- ===== HERO lane: the shared banner spot, one card at a time =====
local heroGui = Instance.new("ScreenGui")
heroGui.Name = "NotifyHero"; heroGui:SetAttribute("NoTextSweep", true) -- DINO: opt out of repositionGUIs' TextScaled sweep
heroGui.ResetOnSpawn = false
heroGui.IgnoreGuiInset = true
heroGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- so the glow/shadow siblings sit behind the card
heroGui.DisplayOrder = 95 -- above the HUD, below the shops (100) and the crate reveal
heroGui.Parent = playerGui

-- A transparent ROOT is what slides and resizes; the card fills it at scale (1,1). The glow/shadow that
-- SpaceTheme.addPanelDepth parents alongside the card are sized in scale too, so they follow the root's height
-- when a card with a sub line grows — which they could not do if they were pinned to a fixed offset size.
local root = Instance.new("Frame")
root.Name = "Hero"
root.AnchorPoint = PhoneHUD.BANNER_ANCHOR
root.Position = PhoneHUD.bannerOff()
root.Size = cardSize(false)
root.BackgroundTransparency = 1
root.Visible = false
root.Parent = heroGui

local card = Instance.new("Frame")
card.Name = "Card"
card.Size = UDim2.fromScale(1, 1)
card.BackgroundColor3 = SpaceTheme.StarfieldFill
card.BorderSizePixel = 0
card.ZIndex = 2
card.Parent = root
corner(card, 16)

-- ===== THE FINISH IS THE FOOD REALM'S, EXACTLY =====
-- Pulled straight off FtF's hero card, which is deliberately plain: a SOLID COLOUR BLOCK, corner 12, a black
-- 2px stroke, and white text with black outlines. That is the whole treatment. No starfield, no gloss, no
-- neon gradient border, no outer glow, no drop shadow.
--
-- This card had all six of those. On a 500x65 strip they read as noise and the one word the banner exists to
-- say -- usually a planet name -- had to compete with every one of them. It is not that the effects were bad;
-- it is that a banner is a label, and FtF's works because there is nothing on it but the words.
--
-- SPACE-THEMED means the COLOURS, not the construction: the fill is whatever accent the caller passes (a
-- Mercury arrival is grey, the cosmic race is cyan), and "white" is SpaceTheme.TextPrimary -- the palette's
-- blue-white -- rather than pure 255s. Geometry, corner, stroke weights and type are FtF's numbers untouched.
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = card
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(0, 0, 0); st.Thickness = 2; st.Parent = card
end

-- Recolour the one persistent card to the banner's accent, rather than rebuilding the card per banner.
-- In FtF the accent IS the card: spec.color is painted straight onto the fill and the text stays white over
-- it. This used to tint a border gradient, an outer glow and the kicker text instead, leaving the card itself
-- permanently dark -- so the colour a caller passed was a thin rim rather than the banner.
local function setAccent(c: Color3)
	card.BackgroundColor3 = c
end

-- ===== ONE DEFINITION OF "WHAT A BANNER LOOKS LIKE" =====
-- The standing readouts styled as banners -- the cosmic-race climb/leader/timer, the server-event
-- countdown -- are the same object as the card above them at a different moment, so they should not be
-- re-deriving the look from copied numbers. They were: 420x46 corner 14 with a 2.5px accent stroke, and
-- 124x40 corner (1,0) with a 2.5px WHITE stroke. Three shapes, three borders, one column.
--
-- Callers pass their own accent (the race keeps its cyan, an event keeps its own colour) -- only the
-- GEOMETRY and the finish are shared. Deliberately WITHOUT the card's outer glow/shadow: those are siblings
-- of the frame and need the ScreenGui on ZIndexBehavior.Sibling to sit behind it, and a standing readout
-- that is on screen for a whole race should carry less visual weight than a card that flashes past anyway.
--
-- Idempotent: it reuses an existing UICorner/UIStroke/UIGradient rather than stacking a second one, so a
-- caller that still creates its own is corrected instead of doubled.
function NotifyCenter.styleAsBanner(frame: GuiObject, accent: Color3?): UIStroke
	local c = accent or ACCENT_DEFAULT

	frame.Size = PhoneHUD.BANNER_SIZE
	frame.BackgroundColor3 = c          -- FtF: the accent IS the card, on the pills as much as the hero
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0

	local uic = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	uic.CornerRadius = UDim.new(0, 16)  -- FtF's pills are 16; only its hero card is 12
	uic.Parent = frame

	local st = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(0, 0, 0)
	st.Transparency = 0
	st.Parent = frame

	-- FtF's type over a coloured fill: white with a black outline. Matches whatever the caller built.
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("TextLabel") then
			d.TextColor3 = SpaceTheme.TextPrimary
			local ds = d:FindFirstChildOfClass("UIStroke")
			if ds then
				ds.Color = Color3.fromRGB(0, 0, 0)
				ds.Thickness = 2
				ds.Transparency = 0
			end
		end
	end
	return st
end

-- Some banners are tappable (a reward nag that opens a panel). ONE transparent button covers the card and is
-- rebound per banner, then cleared when nothing is showing.
local heroBtn = Instance.new("TextButton")
heroBtn.Name = "Hit"
heroBtn.Size = UDim2.fromScale(1, 1)
heroBtn.BackgroundTransparency = 1
heroBtn.Text = ""
heroBtn.AutoButtonColor = false
heroBtn.Visible = false
heroBtn.Active = false
heroBtn.ZIndex = 6
heroBtn.Parent = card

local heroOnClick = nil
heroBtn.Activated:Connect(function()
	local f = heroOnClick
	if f then
		pcall(f)
	end
end)

-- The kicker ("🚀 WELCOME TO"): the HEADER role -- 26px GothamBlack. It is the second-largest line on the
-- card, deliberately: it labels the moment, the NAME line under it IS the moment.
local topLbl = Instance.new("TextLabel")
topLbl.Name = "Kicker"
topLbl.AnchorPoint = Vector2.new(0.5, 0)
topLbl.BackgroundTransparency = 1
topLbl.TextColor3 = SpaceTheme.TextPrimary -- FtF: white. The ACCENT is the card now, so the kicker
                                           -- cannot also be it -- it would vanish into the fill.
topLbl.Text = ""
topLbl.ZIndex = 3
topLbl.Parent = card
NotifyCenter.styleBannerText(topLbl, "HEADER") -- 26px GothamBlack, TextScaled off, no size constraint
textStroke(topLbl)

-- The headline ("NEPTUNE"): the NAME role -- 34px FredokaOne, the LARGEST line on the card. This is the line
-- the whole banner exists for and it used to render smaller than both lines around it.
local mainLbl = Instance.new("TextLabel")
mainLbl.Name = "Headline"
mainLbl.AnchorPoint = Vector2.new(0.5, 0)
mainLbl.BackgroundTransparency = 1
mainLbl.TextColor3 = SpaceTheme.TextPrimary
mainLbl.Text = ""
mainLbl.ZIndex = 3
mainLbl.Parent = card
NotifyCenter.styleBannerText(mainLbl, "NAME") -- 34px FredokaOne, TextScaled off, no size constraint
textStroke(mainLbl)
-- No text gloss. FtF's headline is flat white over the fill; a sheen on top of a saturated card is the
-- seventh treatment competing with the word.

-- The tagline: the Space Realm addition, used by the planet arrival banner.
local subLbl = Instance.new("TextLabel")
subLbl.Name = "Tagline"
subLbl.AnchorPoint = Vector2.new(0.5, 0)
subLbl.BackgroundTransparency = 1
subLbl.TextColor3 = Color3.fromRGB(238, 244, 255) -- FtF's near-white sub (242,252,244), cooled for space
subLbl.Text = ""
subLbl.Visible = false
subLbl.ZIndex = 3
subLbl.Parent = card
NotifyCenter.styleBannerText(subLbl, "SUB") -- 22px GothamBold (was Gotham Regular + TextScaled), no constraint
textStroke(subLbl, 1.5) -- FtF: 1.5 on the sub, 2 everywhere else

-- Re-flow the three slots. See the SIZING block up top. The fractions are still SCALE (so one layout serves
-- every device), but they are now cut to FIT THE TYPE rather than to squeeze it: each slot is at least as tall
-- as the explicit TextSize that lands in it, so nothing has to shrink to be inside its box.
--
--   TALL card (92): kicker 25.8 > name 38.6 > tagline 22.1  = 86.5 of 92, with the margins FtF had.
--   SHORT card (65): kicker 27.3 over name 34.5             = 61.8 of 65.
local function layout(hasTop: boolean, hasSub: boolean, wrap: boolean)
	if wrap and not hasSub then
		-- A wrapped sentence gets the whole card below the kicker, on the TALL card (see cardSize). The name
		-- line drops to NAME_WRAP (20) here because it is 2-3 rows of prose, not a word.
		if hasTop then
			topLbl.Position = UDim2.new(0.5, 0, 0.02, 0)
			topLbl.Size = UDim2.new(1, -18, 0.30, 0)   -- 27.6px at 92 — holds the 26px kicker
			mainLbl.Position = UDim2.new(0.5, 0, 0.32, 0)
			mainLbl.Size = UDim2.new(1, -26, 0.66, 0)  -- 60.7px — ~2.5 rows of 20px prose
		else
			mainLbl.Position = UDim2.new(0.5, 0, 0.06, 0)
			mainLbl.Size = UDim2.new(1, -26, 0.88, 0)  -- 81px — ~3 rows
		end
	elseif hasSub then
		-- THE PLANET ARRIVAL CARD. kicker 26 / name 34 / tagline 22, in that visual order of weight.
		topLbl.Position = UDim2.new(0.5, 0, 0.03, 0)
		topLbl.Size = UDim2.new(1, -18, 0.28, 0)       -- 25.8px at 92 — holds the 26px kicker
		subLbl.Position = UDim2.new(0.5, 0, 0.735, 0)
		subLbl.Size = UDim2.new(1, -24, 0.24, 0)       -- 22.1px — holds the 22px tagline
		if hasTop then
			mainLbl.Position = UDim2.new(0.5, 0, 0.30, 0)
			mainLbl.Size = UDim2.new(1, -18, 0.42, 0)  -- 38.6px — holds the 34px name with air around it
		else
			mainLbl.Position = UDim2.new(0.5, 0, 0.08, 0)
			mainLbl.Size = UDim2.new(1, -18, 0.63, 0)  -- 58px — the name takes the space the kicker isn't using
		end
	elseif hasTop then
		topLbl.Position = UDim2.new(0.5, 0, 0.04, 0)
		topLbl.Size = UDim2.new(1, -18, 0.42, 0)       -- 27.3px at 65 — holds the 26px kicker
		mainLbl.Position = UDim2.new(0.5, 0, 0.44, 0)
		mainLbl.Size = UDim2.new(1, -18, 0.53, 0)      -- 34.5px — holds the 34px name
	else
		-- With no kicker the headline uses the whole card instead of sitting low.
		mainLbl.Position = UDim2.new(0.5, 0, 0.10, 0)
		mainLbl.Size = UDim2.new(1, -18, 0.80, 0)      -- 52px at 65
	end
end

-- ===== SOCIAL lane: top-left, small, stacks, never competes with HERO =====
local socialGui = Instance.new("ScreenGui")
socialGui.Name = "NotifySocial"; socialGui:SetAttribute("NoTextSweep", true)
socialGui.ResetOnSpawn = false
socialGui.IgnoreGuiInset = true
socialGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
socialGui.DisplayOrder = 94
socialGui.Parent = playerGui

local SOCIAL_MAX = 2   -- FtF allowed 3; two keeps the stack clear of the left rail, which starts at y96
local SOCIAL_H = 34
local SOCIAL_GAP = 6
local SOCIAL_W = 300
local socialPills = {} -- newest last

local function layoutSocial()
	for i, pill in ipairs(socialPills) do
		local y = 10 + (i - 1) * (SOCIAL_H + SOCIAL_GAP)
		TweenService:Create(pill, TweenInfo.new(0.2), { Position = UDim2.new(0, 12, 0, y) }):Play()
	end
end

local function popSocial(pill)
	for i, p in ipairs(socialPills) do
		if p == pill then
			table.remove(socialPills, i)
			break
		end
	end
	TweenService:Create(pill, TweenInfo.new(0.25), { Position = UDim2.new(0, -(SOCIAL_W + 20), 0, pill.Position.Y.Offset) }):Play()
	task.delay(0.3, function()
		if pill.Parent then
			pill:Destroy()
		end
	end)
	layoutSocial()
end

local function showSocial(text: string, color: Color3?)
	local accent = color or ACCENT_DEFAULT

	local pill = Instance.new("TextLabel")
	pill.Name = "SocialPill"
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Position = UDim2.new(0, -(SOCIAL_W + 20), 0, 10) -- slides in from off the left edge
	pill.Size = UDim2.new(0, SOCIAL_W, 0, SOCIAL_H)
	pill.BackgroundColor3 = SpaceTheme.Panel
	pill.BorderSizePixel = 0
	pill.TextColor3 = SpaceTheme.TextPrimary
	pill.Text = "  " .. text
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.Parent = socialGui
	corner(pill, 10)
	SpaceTheme.addNeonBorder(pill, accent, 1.5)
	textStroke(pill, 1.5)
	NotifyCenter.styleBannerText(pill, "SOCIAL") -- 17px GothamBold, TextScaled off (was scaled, clamped at 15)

	socialPills[#socialPills + 1] = pill
	if #socialPills > SOCIAL_MAX then
		popSocial(socialPills[1])
	end
	layoutSocial()
	task.delay(4.5, function()
		if pill.Parent then
			popSocial(pill)
		end
	end)
end

-- ===== HERO scheduler: one at a time, priority-ordered, preemptable =====
local queue = {}   -- pending specs, highest priority first (stable within a priority)
local showing = nil -- the spec currently on screen
local token = 0     -- invalidates the in-flight hide timer when a banner is replaced
local lastText, lastAt = nil, 0

local function hideHero(after)
	TweenService:Create(root, SHOW_OUT, { Position = PhoneHUD.bannerOff() }):Play()
	task.delay(SHOW_OUT.Time + 0.02, function()
		root.Visible = false
		if after then
			after()
		end
	end)
end

local drain -- forward declaration (mutually recursive with presentHero)

-- Paint the card. Split out of presentHero because a PINNED banner repaints IN PLACE as its instruction changes,
-- and re-running the slide-in on every text change would make a standing instruction flap at the top of the screen.
-- Does this headline fit ONE row of the card at the full NAME size? Measured against the AUTHORED slot width
-- (the card is 500 wide and the headline slot insets 18), which is the right frame of reference because the
-- TextSize we are testing is authored too -- a UIScale shrinks both together, so the answer holds on a phone.
local HEADLINE_SLOT_W = PhoneHUD.BANNER_SIZE.X.Offset - 18
local function headlineOverflows(text: string): boolean
	if text == nil or text == "" then
		return false
	end
	local ok, size = pcall(function()
		return TextService:GetTextSize(text, NotifyCenter.TEXT.NAME, NotifyCenter.FONT.NAME, Vector2.new(10000, 10000))
	end)
	return ok and size.X > HEADLINE_SLOT_W
end

local function paintHero(spec)
	local hasTop = spec.top ~= nil and spec.top ~= ""
	local hasSub = spec.sub ~= nil and spec.sub ~= ""
	-- WRAP: for banners whose headline is a SENTENCE rather than a word. A caller opts in (TaskNotice), or the
	-- measurement below finds the line genuinely does not fit one row. Wrapped, "Collected! Talk to the Research
	-- Worker inside the outpost first." fills 2-3 rows of the tall card at NAME_WRAP instead of running off it.
	local wrap = spec.wrap == true and not hasSub
	local accent = spec.color or ACCENT_DEFAULT

	topLbl.Text = spec.top or ""
	topLbl.Visible = hasTop
	mainLbl.Text = spec.text or ""
	subLbl.Text = spec.sub or ""
	subLbl.Visible = hasSub

	-- WRAP IS OPT-IN, AND ONLY WHERE IT IS NEEDED. A caller asks for it (TaskNotice, whose headline is a whole
	-- sentence), or the line is measured to genuinely not fit one row of the card at the NAME size -- a long
	-- purchase line like "SomeLongName — Cosmic Crate!" or a server-event message. A planet name never trips
	-- either test, so an arrival card is always one big unwrapped word.
	if not wrap and not hasSub and headlineOverflows(mainLbl.Text) then
		wrap = true
	end
	NotifyCenter.styleBannerText(mainLbl, wrap and "NAME_WRAP" or "NAME", wrap)

	layout(hasTop, hasSub, wrap)
	root.Size = cardSize(hasSub or wrap) -- a tagline/wrapped card is taller; the depth layers follow it (scale-sized)
	setAccent(accent)

	heroOnClick = spec.onClick
	heroBtn.Visible = spec.onClick ~= nil
	heroBtn.Active = spec.onClick ~= nil
end

--======================================================================
-- HOLD: keep the lane shut while something else owns the screen
--======================================================================
-- The intro cinematic hides the whole HUD and takes the camera. A banner that fires during it is not delayed,
-- it is DESTROYED — it slides in behind an opaque backdrop, runs its timer and leaves, and the player never
-- sees it. That is exactly what happened to the very first "WELCOME TO MERCURY": the server fired the arrival
-- at 33.29s and the cinematic started at 34.49s, so the one banner that matters most played to a black screen.
--
-- A hold shuts the hero lane WITHOUT dropping anything: pushes queue as normal, and the queue drains the moment
-- the last holder releases. So the arrival banner needs no knowledge of the intro at all — it pushes when the
-- server says so, and it plays when the screen is actually free.
--
-- Holds are keyed and counted, so two systems holding at once (say an intro and a cutscene) both have to release.
-- Every hold carries an AUTO-RELEASE BACKSTOP: a holder that dies without releasing would otherwise silence every
-- banner for the rest of the session, which is a far worse failure than a banner arriving late.
local holds = {}
local holdCount = 0
local pinPending = false -- a pin was requested while held; it slides in when the hold lifts

local function heroBlocked(): boolean
	return holdCount > 0
end

local function slideHeroIn()
	-- Both endpoints are re-read HERE, not cached: PhoneHUD computes the spot from the LIVE ResponsiveUI scale,
	-- so a rotation or window resize between banners still lands this one in the right place.
	root.Position = PhoneHUD.bannerOff()
	root.Visible = true
	TweenService:Create(root, SHOW_IN, { Position = PhoneHUD.bannerOn() }):Play()
end

local function clearHeroClick()
	heroOnClick = nil
	heroBtn.Visible = false
	heroBtn.Active = false
end

local function presentHero(spec)
	showing = spec
	token += 1
	local mine = token

	-- ===== THE MOMENT GETS A BEAT =====
	-- Hooked HERE rather than at each celebration's own call site, because every one of them already comes
	-- through this function: the WELCOME TO <PLANET> arrival, a gamepass going through, whatever the next one
	-- is. One hook means the banner somebody writes next month is felt too, without anybody wiring it.
	--
	-- Gated at PURCHASE and above so it stays a CELEBRATION -- exactly the arrival banner and a real paid
	-- purchase. Event notices, task nudges and reward nags come through here as well, and a phone that buzzes
	-- every time a banner slides in is a phone the player turns Vibration off on. (Haptics.client.luau)
	if spec.priority and spec.priority >= PRIORITY.PURCHASE and _G.hapticPulse then
		pcall(_G.hapticPulse, "milestone")
	end

	paintHero(spec)
	slideHeroIn()

	if spec.sound then
		pcall(spec.sound)
	end

	task.delay(spec.duration or DEFAULT_DURATION, function()
		if token ~= mine then
			return -- preempted or replaced -> that path owns the hide
		end
		hideHero(function()
			if token ~= mine then
				return
			end
			showing = nil
			clearHeroClick()
			if spec.onDone then
				pcall(spec.onDone) -- let the caller's own queue advance
			end
			drain()
			if not showing and pinned then
				-- nothing else outranks the pin: put the standing readout back where it was
				paintHero(pinned)
				slideHeroIn()
			end
		end)
	end)
end

--======================================================================
-- PINNED banner: ONE standing instruction that owns the slot until it's done
--======================================================================
-- Ordinary banners are NEWS — they appear, they say a thing, they leave on a timer. A pinned banner is an
-- INSTRUCTION: it stays until the thing it asks for has actually happened, which is exactly what a timed banner
-- gets wrong (it expires while the player is still walking to the thing).
--
-- While a pin is up nothing preempts it — not even PLANET. Other banners are not dropped, they QUEUE, and they
-- play in priority order the moment the pin releases. Nothing is lost; a standing instruction just refuses to be
-- talked over while it is still standing. That is why pinning is a separate call and not "a very high priority".
local pinned = nil   -- the spec currently pinned, or nil
local pinnedId = nil -- the caller's id for it, so an unpin can't cancel somebody else's pin

-- Insert by priority: strictly-greater priorities go ahead, equals keep arrival order (FIFO). Declared HERE,
-- above pin(), because pin() re-queues the banner it displaces.
local function enqueue(spec)
	local i = #queue + 1
	for k = 1, #queue do
		if spec.priority > queue[k].priority then
			i = k
			break
		end
	end
	table.insert(queue, i, spec)
end

function drain()
	-- A pin holds the slot: queued banners wait for it, they do not play underneath or beside it.
	-- A hold shuts the lane entirely (see above) — the queue simply waits.
	if heroBlocked() or showing or #queue == 0 then
		return
	end
	-- A pin holds the slot against everything at or below its own priority. Something that OUTRANKS it (a
	-- real purchase over a 20s windstorm countdown, an arrival over anything) plays over the top for its own
	-- duration and the pin comes back the moment it is done. This is what makes a standing event readout
	-- (windstorm / monsoon / server event countdowns) safe to pin at all -- see the STANDING EVENTS note.
	if pinned and queue[1].priority <= (pinned.priority or 0) then
		return
	end
	presentHero(table.remove(queue, 1))
end

--- Shut the hero lane until `release(id)` is called. Pushes still queue; nothing is dropped.
--- `maxSeconds` is the auto-release backstop (default 90s) — a holder that never releases cannot silence
--- the lane forever.
function NotifyCenter.hold(id, maxSeconds)
	if holds[id] then
		return
	end
	holds[id] = true
	holdCount += 1
	local limit = tonumber(maxSeconds) or 90
	task.delay(limit, function()
		if holds[id] then
			warn(("[NotifyCenter] hold %q never released after %ds \u{2014} auto-releasing so banners aren't lost")
				:format(tostring(id), limit))
			NotifyCenter.release(id)
		end
	end)
end

--- Lift a hold. When the last one lifts, whatever queued up behind it plays immediately, in priority order.
function NotifyCenter.release(id)
	if not holds[id] then
		return
	end
	holds[id] = nil
	holdCount = math.max(0, holdCount - 1)
	if holdCount > 0 then
		return
	end
	if pinned and pinPending then
		pinPending = false
		slideHeroIn() -- the pin was painted when it was requested; only its entrance was deferred
		return
	end
	drain()
end

--- Pin a standing instruction to the hero slot. Calling it again with the SAME id repaints in place (no
--- re-animation), which is how a pin changes its wording as the player's situation changes.
function NotifyCenter.pin(id, spec)
	if type(spec) ~= "table" or not spec.text then
		return
	end
	spec.priority = spec.priority or PRIORITY.REWARD

	if pinned and pinnedId == id then
		pinned = spec
		if not showing then
			paintHero(spec) -- live update only: re-sliding on every text change would make it flap
		end
		-- (if a higher-priority banner is interrupting, it repaints from `pinned` when it finishes)
		return
	end

	pinnedId, pinned = id, spec
	token += 1 -- orphan any in-flight hide timer from the banner we're displacing
	if showing then
		-- The displaced banner still deserves its moment: back on the queue, played once the pin releases.
		enqueue(showing)
		showing = nil
	end
	paintHero(spec)
	if heroBlocked() then
		-- Painted but not shown: the pin takes the slot the instant the hold lifts (see release).
		pinPending = true
		return
	end
	slideHeroIn()
	if spec.sound then
		pcall(spec.sound)
	end
end

--- Release the pin. `id` must match the pin that is up, so a late unpin from a finished flow cannot tear down a
--- newer one that has since taken the slot.
function NotifyCenter.unpin(id)
	if not pinned or (id ~= nil and pinnedId ~= id) then
		return
	end
	pinned, pinnedId = nil, nil
	if showing then
		return -- a higher-priority banner is on the card right now; its own timer drains the queue
	end
	token += 1
	hideHero(function()
		showing = nil
		clearHeroClick()
		drain() -- whatever queued up behind the pin now gets its turn
	end)
end

--- push a notification.
--- spec = { text, top?, sub?, wrap?, color?, priority?, duration?, lane? ("hero"|"social"), sound? (fn),
---          onClick? (fn), onDone? (fn) }
--- `wrap = true` -> the headline is a sentence: it wraps onto the tall card instead of shrinking to fit one line.
function NotifyCenter.push(spec)
	if type(spec) ~= "table" or not spec.text then
		return
	end
	spec.priority = spec.priority or PRIORITY.REWARD

	if spec.lane == "social" or spec.priority <= PRIORITY.SOCIAL then
		showSocial(spec.text, spec.color)
		return
	end

	-- Drop an exact repeat within 2s (nag banners re-fire on a loop). onDone MUST still fire: callers hold a
	-- "banner showing" flag that only clears on onDone, so silently swallowing the spec would wedge their queue.
	local now = os.clock()
	if spec.text == lastText and (now - lastAt) < 2 then
		if spec.onDone then
			task.defer(function()
				pcall(spec.onDone)
			end)
		end
		return
	end
	lastText, lastAt = spec.text, now

	-- A pin owns the slot. Everything else waits its turn behind it, in priority order — nothing is dropped, it
	-- just does not get to talk over a standing instruction. A hold shuts the lane the same way.
	if heroBlocked() then
		enqueue(spec)
		return
	end
	if pinned and spec.priority <= (pinned.priority or 0) then
		enqueue(spec)
		return
	end

	if not showing then
		presentHero(spec)
		return
	end

	if spec.priority > showing.priority then
		-- PREEMPT: the current banner is less important. Put it back at the head of the queue (it still deserves
		-- its moment) and swap the new one in immediately.
		token += 1 -- orphan the outgoing banner's hide timer
		local demoted = showing
		showing = nil
		enqueue(demoted)
		hideHero(function()
			if not showing then
				drain()
			end
		end)
		table.insert(queue, 1, spec) -- the preempting spec must lead the queue
		return
	end

	enqueue(spec) -- equal or lower -> wait your turn
end

--======================================================================
-- THE STANDING-INFO SLOT: directly below the banner card
--======================================================================
-- Some things are not banners. A server event's "15s" countdown and the Cosmic Race's climb/leader/timer strip
-- are STANDING INFO: they belong on screen for as long as the event runs, and they have to stay readable while
-- banners come and go around them.
--
-- They cannot go through the hero lane. `pin` is the right shape (it holds the slot and repaints in place) but
-- the wrong DURATION: a pin outranks everything, so pinning a 6-minute race timer would silence every arrival
-- and purchase banner for six minutes. A banner delayed that long may as well have been dropped.
--
-- So they get their own slot, one row down. It is computed from the TALLEST card (the three-line arrival one),
-- not the card currently showing, so a standing pill never has to move when a taller banner slides in above it
-- — it is clear of every variant by construction.
local PILL_GAP = 10

-- STANDING EVENTS (windstorm / monsoon / ice age / server events / the volcano finale) are PINS at
-- PRIORITY.EVENT: `pin(id, spec)` on start, repainted with the countdown, `unpin(id)` on stop. A pin only
-- blocks banners at or below its own priority, so a purchase (90) or an arrival (100) still plays over a
-- countdown and the countdown comes straight back. Everything announcing itself in this realm goes through
-- this ONE card -- there are no separate top-centre banners any more.
--
-- CURRENTLY UNUSED. The two readouts that used this row -- the server-event countdown and the cosmic-race
-- climb/timer -- were moved onto the shared banner SPOT itself (they show only while this lane is empty, so
-- one card owns that pixel at a time). Kept because it is the right answer for any future readout that must
-- coexist with a banner rather than take turns with it.
function NotifyCenter.pillSpot(): UDim2
	local base = PhoneHUD.bannerOn()
	local tallest = cardSize(true).Y.Offset
	return UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + tallest + PILL_GAP)
end

function NotifyCenter.isBusy(): boolean
	return showing ~= nil or pinned ~= nil
end

function NotifyCenter.isPinned(): boolean
	return pinned ~= nil
end

print("[NotifyCenter] ready \u{2014} HERO lane (shared banner spot, priority queue + pinned instructions) + SOCIAL lane (top-left)")

return NotifyCenter
