--======================================================================
-- BottomHUD.client.luau  (LocalScript)
--======================================================================
-- THE BOTTOM-CENTER HUD. Once three stacked panels (gut pill, gas meter, fart button),
-- now ONE:
--
--   LayoutOrder 1: THE GUT PANEL -- navy card holding the gut icon, the gut's name, the
--                  power bar, and TWO buttons built into its lower half: BUY DINO FOOD
--                  FIRST, and TAP TO FART directly beneath it. Both are integrated into
--                  the card the same way -- same width, radius, gold outline and depth --
--                  rather than the fart button being a separate pill below the panel.
--
-- Flying is that button OR the spacebar. Both call the same toggleFart.
--
-- HOW THE PLACEMENT WORKS: the panel lives in a container ("BottomStack") anchored
-- bottom-center, offset up from the screen edge far enough to sit centred in the band the
-- old three-panel stack occupied. A vertical UIListLayout (HorizontalAlignment Center,
-- VerticalAlignment Bottom, Padding 8) survives from when there was more than one panel --
-- it costs nothing with a single child and is what a second panel would slot back into.
-- The container is AutomaticSize=Y so it hugs its contents and cannot leave a gap where
-- the button used to be. ScreenGui IgnoreGuiInset=true, DisplayOrder 5 (above the world,
-- below menus at 100).
--
-- This is COSMETIC/visual only (no flight wiring).
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- scale: authored at FULL size (1.0) on every device, like the first realm. Device fitting is done
-- by ResponsiveUI (one UIScale per cluster = getScale() x extra). BottomStackGui's extra is 0.72,
-- set via the ResponsiveExtraShrink attribute on bottomStack below. Do NOT bake a mobile shrink here.
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = 1.0

-- ===== GUI HELPERS =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUT ASSETS -- per-tier emoji on the pill =====
-- READ OFF StomachTiers, not hand-listed here. This used to be a literal seven-entry table
-- keyed on tier NAME, and the lookup at the bottom falls back to "keep whatever is showing"
-- on a miss -- so when the tower went from six gut tiers to twelve, the six new ones would
-- have silently kept the previous gut's badge with nothing in the output to say so.
local GUT_EMOJI = {}
do
	local ok, ST = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers", 10))
	end)
	if ok and ST then
		for _, tier in ipairs(ST.LIST) do GUT_EMOJI[tier.name] = tier.emoji end
	end
end
local GUT_IMAGE = "rbxassetid://108585083746103" -- legacy; unused now that all tiers use emoji
local stomachName = "Hatchling Belly" -- the current gut tier (drives the pill icon + name)

-- ============================================================================
-- BOTTOM-CENTER STACK CONTAINER -- the three elements all parent into this.
-- ============================================================================
local bottomStackGui = Instance.new("ScreenGui")
bottomStackGui.Name = "BottomStackGui"; bottomStackGui.ResetOnSpawn = false
bottomStackGui.IgnoreGuiInset = true; bottomStackGui.DisplayOrder = 5; bottomStackGui.Parent = PlayerGui
local bottomStack = Instance.new("Frame")
bottomStack.Name = "BottomStack"; bottomStack.AnchorPoint = Vector2.new(0.5, 1)
-- THE ONE VERTICAL NUMBER, taken as the reference's AUTHORED offset:
--     CARD authoredPosY=(1, -20)  anchorY=1
-- Our anchor is (0.5, 1) and the card is the layout's only child, so -20 here is the
-- same authored value in the same form.
--
-- The reference's two other rows confirm the reading -- they are the same offsets this
-- file already derives, measured in the same parent:
--     GLOW authoredPosY=(1, -13) = -20 + GLOW_OUT(7)   -- the halo bleeds 7 below the card
--     SLOT authoredPosY=(1, -12) = PAD                 -- the button is inset 12 from it
--
-- WORTH KNOWING: on the reference this lands at gapFromBottom=78, because its card hangs
-- inside a parent that already sits 58px up from the viewport. Ours is anchored to the
-- screen, so -20 IS the gap -- the panel sits 20px off the bottom edge, 58px lower than
-- the reference's on-screen position. If the goal was to match where it LOOKS on screen
-- rather than how it is authored, this number is 78; it is one constant either way.
--
-- OFFSET, NOT SCALE, deliberately: the reference's is a fixed pixel count at every
-- viewport. A scale would match at 1044 tall and nowhere else.
local BOTTOM_GAP = 20
bottomStack.Position = UDim2.new(0.5, 0, 1, -BOTTOM_GAP); bottomStack.Size = UDim2.new(0, 470, 0, 0)
bottomStack.AutomaticSize = Enum.AutomaticSize.Y; bottomStack.BackgroundTransparency = 1; bottomStack.Parent = bottomStackGui
bottomStack:SetAttribute("ResponsiveExtraShrink", 0.72)  -- first-realm BottomStackGui cluster extra (mobile-only, applied by ResponsiveUI)
do
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Vertical; sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center; sl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	sl.Padding = UDim.new(0, 8); sl.Parent = bottomStack -- matches the first realm's bottom-stack spacing (padding 8)
end

-- ===== JUNGLE CHROME (match the Pet Hub / Shop / Stats panel) =====
local okJC, JC = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10)) end)
if not okJC then JC = nil end

-- NOTE: the shared stoneFrame() panel builder and the olive palette it drew with are both
-- gone. It existed to stamp out the three bottom-HUD panels in one style; there is one
-- panel now, it is built inline below, and the fart button that was its last caller no
-- longer renders. The jungle-toned OLIVE / CREAM / BAMBOO / DARKTXT constants went with it.

local gui = {} -- holds the built elements

-- ============================================================================
-- (1+2) THE GUT PANEL  (LayoutOrder 1) -- ONE component, not two stacked panels
-- ============================================================================
-- The gut name pill and the gas meter used to be two separate rounded panels with an
-- 8px gap between them, and the "buy food" prompt was a third thing floating elsewhere.
-- All of it is one card now: icon + name + bar on top, the shop call-to-action built into
-- the bottom of the same frame.
--
-- WHAT DID NOT CHANGE: every name the flight code touches. `stomachHudIcon`,
-- `stomachHudLabel`, `updateStomachDisplay`, `gui.gasBg`, `gui.gasFill`,
-- `gui.gasGradient`, `gui.gasPowerText` and `setGas()` are all still here, still driven
-- by the same values from the same places. This is a reskin, not a rewire.
-- ======================= MEASURED AGAINST THE FIRST REALM =======================
-- Every number in this block is solved backwards from a live measurement of the
-- reference HUD, not chosen:
--     CARD  470x144  bottomGap 78      TRACK 382x36  at card-relative (76, 34)
--     GLOW  484x158  bottomGap 71      SLOT  446x52  at card-relative (12, 80)
-- Those five facts pin the whole layout, and they agree on PAD = 12:
--     the track ends at 76 + 382 = 458 = 470 - 12          -> right pad 12
--     the slot spans 12 .. 458                             -> both pads 12
--     12 + 16 + 6 + 36 + 10 + 52 + 12 = 144                -> the card's height
-- so the vertical stack below is forced. Change one and re-derive the rest; do not
-- nudge a single constant on its own.
local PANEL_W   = 470
local PAD       = 12
-- THE STAT ROW: gut name on top, badge and bar beneath it.
local TITLE_H   = 16   -- the gut name, directly above the bar
local TITLE_GAP = 6
local BAR_H     = 36
local ICON_D    = 52   -- circle diameter
local BAR_Y     = TITLE_H + TITLE_GAP              -- 22, from the card's padding box
local TOP_H     = BAR_Y + BAR_H                    -- 58
local SECTION_GAP = 10 -- the button stays CLOSE to the bar
local CTA_H     = 52
-- ONE action now. The buy-food button is gone, so this is a single button tall.
local PANEL_H   = PAD + TOP_H + SECTION_GAP + CTA_H + PAD -- 144
local PANEL_R   = 22
local GLOW_OUT  = 7    -- 470+14 = 484, 144+14 = 158, and 78-7 = 71. All three measured.

-- ONE border weight for the whole panel. Everything gold was 3-4px; at 2 it is a thin
-- warm outline rather than a frame, which is most of what separated this from the
-- reference. Stated once so the card, the icon ring, the bar and both buttons cannot
-- drift apart from each other.
local EDGE_W    = 2
-- and one text-outline weight, down from 3. "Subtle" is the whole note here: at 3 the
-- outline was competing with the letterforms at these smaller sizes.
local INK_W     = 1.5

-- THE DINO PALETTE. Not invented here: every value is lifted from the shared
-- DinosaurRealm/JungleChrome module that already skins the Shop, the Pet Hub and every
-- imported panel JungleTheme restyles. Picking fresh greens would have given the HUD a
-- jungle of its own that agreed with nothing it sits under.
--
-- WAS the first realm's navy/#F4C430-gold/royal-blue. The SIZES still match that realm
-- (see the measurement block above) -- only the colours are ours now.
-- BRIGHTENED, and the card moved family to do it: it was JungleChrome's HEADER green
-- (34,60,38), which is the darkest thing in that module. The body of every jungle panel
-- -- Shop, Pet Hub -- is the far lighter OLIVE from JungleChrome.stylePanel, so lifting
-- the card onto the olive is both brighter AND more canonical, not a departure.
local PANEL_LIT  = Color3.fromRGB(134, 158, 92)  -- sunlit olive, top of the card
local PANEL_DEEP = Color3.fromRGB(100, 122, 68)  -- the same olive shaded, bottom of the card
-- RECESSES STAY DARK ON PURPOSE. The track and the icon well used to share the card's
-- own dark green; on a light olive card that would make the meter a bright bar on a
-- bright trough with nothing between them. Holding these down is what lets the fill pop.
local RECESS     = Color3.fromRGB(38, 62, 36)    -- track + icon well interiors
local RECESS_DIM = Color3.fromRGB(26, 44, 26)    -- top of the track, so the fill sits down in it
local BAMBOO     = Color3.fromRGB(240, 214, 138) -- bright bamboo, every outline on the panel
-- The meter reads as the gas it measures: this is a fart-powered game and the flight
-- trail is already green (FartTrail), so the bar and the active button match it.
local FILL_LIT   = Color3.fromRGB(198, 252, 128) -- top of the progress fill
local FILL_DEEP  = Color3.fromRGB(104, 204, 76)  -- bottom of it
-- Carved wood, from JungleChrome's plaque, warmed up. Idle brown -> active green is a
-- much clearer state change than the old blue -> lighter blue, and it is the same shift
-- the trail makes.
local WOOD_LIT   = Color3.fromRGB(198, 138, 76)  -- top of the button
local WOOD_DEEP  = Color3.fromRGB(146, 94, 48)   -- bottom of it
local INK        = Color3.fromRGB(0, 0, 0)       -- text outline + shadow
local WHITE      = Color3.fromRGB(255, 255, 255) -- gloss highlights ONLY, never text
local CREAM      = Color3.fromRGB(255, 252, 238) -- all HUD text; INK_W stroke carries it on olive

-- A soft ambient shadow under a panel. Roblox cannot blur, so the falloff is faked with
-- three progressively larger and fainter rounded rects behind the thing casting it.
local function ambientShadow(parent, radius)
	for i = 3, 1, -1 do
		local grow = i * 3
		local sh = mkFrame(parent, {
			Name = "Shadow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, i * 2),
			Size = UDim2.new(1, grow, 1, grow),
			BackgroundColor3 = INK,
			-- LIGHT ambient only: lifted from 0.66 so the card sits on the screen rather
			-- than looking like it is floating well above it
			BackgroundTransparency = 0.76 + i * 0.07,
			BorderSizePixel = 0,
			ZIndex = 1,
		})
		mkCorner(sh, radius + math.floor(grow / 2))
	end
end

-- Bold white with a THICK black outline, plus an offset black copy behind it for the drop
-- shadow. Returns the front label; the shadow copy tracks it via a Changed hook so the
-- two can never say different things.
-- `maxText` is applied to BOTH copies. It has to be: these are TextScaled, so a shadow
-- without the same cap grows to fill its box while the front label stops at the cap, and
-- the "shadow" ends up bigger than the text it is meant to sit behind.
local function boldWhite(parent, props, outline, maxText)
	local shadow = mkLabel(parent, {
		Text = props.Text, Font = props.Font, TextScaled = props.TextScaled,
		TextColor3 = INK, TextTransparency = 0.55,
		Size = props.Size, Position = props.Position + UDim2.fromOffset(0, 2),
		AnchorPoint = props.AnchorPoint, TextXAlignment = props.TextXAlignment,
		TextYAlignment = props.TextYAlignment,
		ZIndex = (props.ZIndex or 1) - 1,
	})
	local front = mkLabel(parent, props)
	mkStroke(front, INK, outline or INK_W)
	if maxText then
		for _, lbl in ipairs({ front, shadow }) do
			local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxText; c.Parent = lbl
		end
	end
	front:GetPropertyChangedSignal("Text"):Connect(function() shadow.Text = front.Text end)
	return front, shadow
end

local gutWrap = mkFrame(bottomStack, { Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundTransparency = 1, LayoutOrder = 1 })
gutWrap.Name = "StomachHud"; gutWrap.ZIndex = 10
ambientShadow(gutWrap, PANEL_R)
-- The reference's 484x158 halo, sitting GLOW_OUT past the card on every side. It is a
-- sibling BEHIND the card (ZIndex 2 vs 3) rather than a stroke, because a stroke cannot
-- be soft and this has to read as light spilling out from under the panel.
local gutGlow = mkFrame(gutWrap, {
	Name = "GasMeterGlow", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, GLOW_OUT * 2, 1, GLOW_OUT * 2),
	BackgroundColor3 = BAMBOO, BackgroundTransparency = 0.68, BorderSizePixel = 0, ZIndex = 2,
})
mkCorner(gutGlow, PANEL_R + GLOW_OUT)
-- Named GasMeter (not "Card") so the reference's own measuring script finds it here too.
local gutContent = mkFrame(gutWrap, { Name = "GasMeter", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = PANEL_LIT, BorderSizePixel = 0, ZIndex = 3 })
mkCorner(gutContent, PANEL_R)
mkStroke(gutContent, BAMBOO, EDGE_W) -- thin, warm bamboo outline
do -- VERY SUBTLE vertical gradient: two navies a few steps apart, lighter at the top
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(PANEL_LIT, PANEL_DEEP); g.Parent = gutContent
end
do -- the inner liner stays, but at 0.6 transparency and 1px it is a hint of depth rather
	-- than the second border it had become. No bevel.
	local liner = mkFrame(gutContent, { Name = "InnerLine", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -5, 1, -5),
		BackgroundTransparency = 1, ZIndex = 4 })
	mkCorner(liner, PANEL_R - 3)
	local s = mkStroke(liner, PANEL_DEEP, 1); s.Transparency = 0.6
end

-- ---- TOP: badge + title + bar --------------------------------------------------------
-- THE BADGE NO LONGER TUCKS UNDER THE BAR, and it cannot at these proportions. The
-- measurement forces the track to start 76px in (it is 382 wide and ends at 470-12), and
-- a circle that reaches 76 from a 12px left margin would be 64+ across -- taller than the
-- 52px of vertical room between the title and the button, so it would hang over the CTA.
-- The badge is therefore 52 and sits clear of the track by 12, matching the 12 it sits in
-- from the card edge. Keeping the overlap would mean moving the track left, i.e. not
-- these sizes.
local ICON_X = PAD
local BAR_X  = 76                                   -- measured
local BAR_W  = (PANEL_W - PAD) - BAR_X              -- 382, measured
local BAR_TOP = PAD + BAR_Y                         -- 34, measured

-- Aligned to where the TRACK begins, so the name and the bar share one left edge.
local stomachHudLabel = boldWhite(gutContent, {
	Name = "StomachHudLabel", Text = stomachName, Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = CREAM, Size = UDim2.fromOffset(BAR_W, TITLE_H),
	Position = UDim2.fromOffset(BAR_X, PAD),
	AnchorPoint = Vector2.new(0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
}, INK_W, 16)
-- NOTE: updateStomachDisplay and the StomachMax watcher now live BELOW the badge, because
-- the badge is built after the bar (it has to draw on top of it) and this function writes
-- to the icon inside it.

-- The progress bar lives in the SAME card, so there is no second panel and no gap. The
-- old 480x85 "GAS METER" frame with its gold title is gone; the title is the gut's name
-- above the bar now, which is the only label this row ever needed.
gui.gasMeterPanel = gutWrap -- kept: the name other code reached for when this was its own panel
gui.gasBg = mkFrame(gutContent, { Name = "Track", Size = UDim2.fromOffset(BAR_W, BAR_H),
	Position = UDim2.fromOffset(BAR_X, BAR_TOP), BackgroundColor3 = RECESS,
	ZIndex = 5, BorderSizePixel = 0 })
mkCorner(gui.gasBg, math.floor(BAR_H / 2)) -- fully rounded ends
mkStroke(gui.gasBg, BAMBOO, EDGE_W)          -- thin bamboo outline, same weight as the card
do -- recessed track: darkest at the top, so the fill sits down inside it
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(RECESS_DIM, RECESS); g.Parent = gui.gasBg
end
-- The fill now runs the FULL track. It used to be inset by the width the badge covered,
-- so that low power was not spent entirely behind the circle -- with the badge clear of
-- the track that correction would just leave a dead notch at the left end.
-- setGas still writes a plain 0..1 fraction, as it always did.
local fillArea = mkFrame(gui.gasBg, { Name = "FillArea",
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 6 })
-- YELLOW -> ORANGE fill, fully rounded so the leading end stays a cap at every width
gui.gasFill = mkFrame(fillArea, { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = FILL_LIT, ZIndex = 6, BorderSizePixel = 0 })
mkCorner(gui.gasFill, math.floor(BAR_H / 2))
gui.gasGradient = Instance.new("UIGradient"); gui.gasGradient.Rotation = 90
gui.gasGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, FILL_LIT), ColorSequenceKeypoint.new(1, FILL_DEEP) })
gui.gasGradient.Parent = gui.gasFill
do -- SOFT HIGHLIGHT ACROSS THE TOP OF THE FILL. A child of the fill, so it grows with it
	-- and never floats over empty track.
	local sheen = mkFrame(gui.gasFill, { Name = "Sheen", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -14, 0, 6),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.66, BorderSizePixel = 0, ZIndex = 7 })
	mkCorner(sheen, 3)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = sheen
end
-- Centred in the whole track, now that nothing covers either end of it.
gui.gasPowerText = boldWhite(gui.gasBg, {
	Name = "PowerText", Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 0),
	AnchorPoint = Vector2.new(0, 0), Text = "0/100", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = CREAM, ZIndex = 10, TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
}, INK_W, 20)

-- ---- THE BADGE, drawn LAST so it sits ON the bar ------------------------------------
-- Built after the track on purpose: it has to cover the bar's left cap for the two to
-- read as one shape. Its vertical centre is the BAR's centre, not the row's -- that is
-- what attaches it to the bar rather than leaving it floating beside the row.
local iconWell = mkFrame(gutContent, { Name = "IconWell", AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(ICON_X, BAR_TOP + math.floor(BAR_H / 2)),
	Size = UDim2.fromOffset(ICON_D, ICON_D), BackgroundColor3 = RECESS,
	BorderSizePixel = 0, ZIndex = 8 })
mkCorner(iconWell, 999)
mkStroke(iconWell, BAMBOO, EDGE_W) -- thin bamboo ring, same weight as every other outline
do -- recessed: darker at the TOP, the opposite of the card, which is what makes the circle
	-- read as sunk into it
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(RECESS_DIM, RECESS); g.Parent = iconWell
end
-- Centred on BOTH axes inside the circle, and sized off the circle so it stays centred at
-- any ICON_D. Emoji have uneven glyph boxes, so the full-bleed square plus centre-centre
-- alignment is what actually lands it in the middle rather than an eyeballed offset.
local stomachHudIcon = mkLabel(iconWell, { Name = "GutIcon", Text = (GUT_EMOJI[stomachName] or ""), Font = Enum.Font.GothamBold, TextScaled = true, Size = UDim2.fromScale(0.66, 0.66), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 9 })

-- Both halves of the display exist now, so the name/icon sync can be wired.
local function updateStomachDisplay()
	stomachHudLabel.Text = stomachName
	stomachHudIcon.Text = GUT_EMOJI[stomachName] or stomachHudIcon.Text
end
updateStomachDisplay()
-- DYNAMIC name: keep the display synced to the bought gut tier (reads StomachMax from leaderstats)
do
	-- The THIRD copy of this map, until now. Shop.server and Bootstrap each had the tier
	-- list too and those two drifted badly enough to break gut purchases outright; this one
	-- only names things, so it would have drifted silently instead. Shared module now.
	local STOMACH_BY_MAX = require(game:GetService("ReplicatedStorage")
		:WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers")).NAME_BY_MAX
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30); local sm = ls and ls:WaitForChild("StomachMax", 30)
		if not sm then return end
		local function refresh() stomachName = STOMACH_BY_MAX[sm.Value] or stomachName; updateStomachDisplay() end
		refresh(); sm:GetPropertyChangedSignal("Value"):Connect(refresh)
	end)
end

-- setGas(pct): drives the fill exactly as before. `cur`/`max` are OPTIONAL and only
-- change what the label reads -- passing neither still works and still shows a sane
-- number, so every existing call site is safe.
local function setGas(pct, cur, max)
	pct = math.clamp(pct, 0, 100)
	gui.gasFill.Size = UDim2.new(pct/100, 0, 1, 0)
	if cur and max and max > 0 then
		gui.gasPowerText.Text = string.format("%d/%d", math.floor(cur), math.floor(max))
	else
		gui.gasPowerText.Text = string.format("%d/100", math.floor(pct))
	end
end
setGas(0)

-- ---- THE CTA SLOT: one button ------------------------------------------------------
-- WAS a two-high block: BUY DINO FOOD FIRST stacked on TAP TO FART, joined by a seam
-- patch so the pair read as a single control. The buy button is gone -- the food shop
-- already opens on its own when you walk up to a stand (ShopGlue's proximity loop), so
-- the CTA was a second door to a room that opens itself.
--
-- Everything that existed only to fuse two halves went with it: actionHalf(), the seam
-- patches, the Join/JoinLight crease, and the shared Shell that had to wrap the pair
-- because per-half decoration would have made them look like two buttons touching. One
-- button needs none of that -- it just carries its own outline, gloss and inset ring.
local GROUP_H = CTA_H                          -- 52, measured
local GROUP_R = math.floor(CTA_H / 2)
local GROUP_Y = PAD + TOP_H + SECTION_GAP      -- 80, measured

-- Named CTASlot / FartButton to match the reference's measuring script.
local btnGroup = mkFrame(gutContent, {
	Name = "CTASlot",
	Size = UDim2.fromOffset(PANEL_W - PAD * 2, GROUP_H),   -- 446 x 52, measured
	Position = UDim2.fromOffset(PAD, GROUP_Y),
	BackgroundTransparency = 1,
	ZIndex = 5,
})

local fartHalf = mkFrame(btnGroup, {
	Name = "FartFill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WOOD_LIT,
	BorderSizePixel = 0,
	ZIndex = 5,
})
mkCorner(fartHalf, GROUP_R)
local fartGrad = Instance.new("UIGradient")
fartGrad.Rotation = 90
fartGrad.Color = ColorSequence.new(WOOD_LIT, WOOD_DEEP)
fartGrad.Parent = fartHalf

do -- outline, gloss and inset ring, the same weights the block carried
	local shell = mkFrame(btnGroup, { Name = "Shell", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 9 })
	mkCorner(shell, GROUP_R)
	mkStroke(shell, BAMBOO, EDGE_W)
	local ins = mkFrame(btnGroup, { Name = "InsetShade", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -3, 1, -3),
		BackgroundTransparency = 1, ZIndex = 9 })
	mkCorner(ins, math.max(2, GROUP_R - 2))
	local s = mkStroke(ins, Color3.fromRGB(96, 60, 30), 1); s.Transparency = 0.6
	local sheen = mkFrame(btnGroup, { Name = "Sheen", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(1, -34, 0, 5),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = 6 })
	mkCorner(sheen, 3)
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	sg.Parent = sheen
end

-- HIT AREA: one transparent button over everything, so a tap anywhere counts. The text
-- lives on its own label at ZIndex 11 -- above the gloss (6) and the shell (9) -- because
-- anything under those gets washed by them.
gui.fartBtn = mkButton(btnGroup, {
	Name = "FartButton", Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 10,
})
gui.fartBtnFrame = fartHalf                  -- setFartLook recolours this
gui.fartLabel = boldWhite(btnGroup, {
	Name = "FartText", Text = "TAP TO FART!", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = CREAM, Size = UDim2.new(1, -32, 0, 28), Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 11,
}, INK_W, 24)
-- kept only because the flight code still holds this handle; there is no icon on the button
gui.fartCloudLabel = mkLabel(btnGroup, { Name = "CloudIcon", Text = "", Visible = false, ZIndex = 7 })

-- setFartLook() still reads all four handles. The seam patch no longer exists, so those
-- two point at the fill's own objects -- recolouring them is harmless and it keeps every
-- existing call site working untouched.
gui.fartBtnGradient   = fartGrad
gui.fartPatch         = fartHalf
gui.fartPatchGradient = fartGrad

-- (3) -- the fart button is no longer a panel of its own. It is built into the gut card
-- above, directly under the buy button. There is nothing to construct here.

-- ============================================================================
-- FART PROPEL / FLIGHT  (copied verbatim from PropelSystem_AllInOne):
--   tap fart -> BodyVelocity drives you straight UP (hands-free) while the gas
--   meter DRAINS; tap again BEFORE empty -> cancel but KEEP leftover gas (next
--   tap resumes); run dry -> auto-stop + fall; respawn -> reset to 0.
-- Fuel = the real food/gut stats (CurrentPower / StomachMax), so eating fills
-- the tank and a bigger gut flies faster + higher.
-- ============================================================================
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- THE PACING NUMBERS LIVE IN DinosaurRealm/FlightTuning, because the SHOP has to
-- agree with them: it hands you a tank sized against the crossing this file flies.
-- Two copies of "how long is a flight" is how the shop starts selling a tank that
-- does not reach.
local FlightTuning = require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("FlightTuning"))

local maxGasMeter = 100     -- 0..100 normalized fuel bar
-- 1.25 gas/sec -> a full tank is FLIGHT_SECONDS (80s) of thrust, for EVERY gut.
-- The meter is normalised, so this is tier-independent: a bigger gut does not fly
-- LONGER, it flies FASTER -- see FlightTuning.
local DRAIN_RATE  = FlightTuning.DRAIN_RATE
local FLIGHT_HORIZONTAL_SPEED = 48   -- unchanged: steering stays as responsive as before

-- ---- HEIGHT COINS ----
-- Paid only WHILE THRUSTING: the tick lives inside the `isFlying and gasMeter > 0`
-- branch, so releasing the button or running dry stops earning. The fall pays 0.
--
-- You are paid for the studs you CLIMB, charged once each, not for how high the
-- world happens to be under you. The other realm pays `absoluteY * 0.0044` EVERY
-- tick, which re-bills the same altitude ~57 times a flight and needs a cap bolted
-- on to stop it running away -- and it means a launch from Inferno Isle earns
-- thousands before you gain a stud. Billing the delta is linear in the climb you
-- actually bought, so no cap is needed and the pacing is tunable.
local COIN_TICK     = 0.5    -- seconds of thrust between payouts
local COIN_PER_STUD = 0.14   -- [BALANCE] coins per stud climbed
local coinTimer, flightCoinsEarned, lastCoinY = 0, 0, 0
local CoinEvent = nil        -- resolved below; the shop server creates it
local BurnFuelEvent = nil    -- resolved below; reports drained fuel so the server's CurrentPower goes DOWN too
local fuelSyncTimer = 0      -- seconds since the last in-flight fuel report
local stomachMax  = 100   -- gut's max raw power (from StomachMax); bigger gut = faster + higher
local gasMeter    = 0     -- 0..100 normalized fuel (THE meter)
local currentPower= 0     -- raw power = (gasMeter/100)*stomachMax
local isFlying    = false
local bodyVel     = nil

-- Rise speed by current (gas-scaled) power -- one band per gut tier, exactly the
-- Space Realm's riseSpeedFor(): the band is read from the DRAINING power, so a
-- flight starts in the top band its gut reaches and steps DOWN as the tank empties.
--
-- The band VALUES now live in FlightTuning, because they are solved against
-- DRAIN_RATE and the SLOT_POS gaps and the three cannot be edited apart. The old
-- literals (40/62/84/126/144/226/280) were tuned for a 40-second tank; left in
-- place beside a re-timed one they overshot the first island by 5x.
local function getFlightSpeed(power)
	return FlightTuning.getFlightSpeed(power)
end

-- meter fill from currentPower/stomachMax (== gasMeter%)
local function updateGasMeter()
	local pct = stomachMax > 0 and math.clamp(currentPower / stomachMax, 0, 1) * 100 or 0
	-- the bar still fills on the percentage; the LABEL now reads the raw power out of the
	-- gut's capacity, which is what the food shop prices against
	setGas(pct, currentPower, stomachMax)
end

-- fart button look: idle vs farting
local function setFartLook(on)
	if on then
		-- ACTIVE: the wood lights up FART GREEN -- the same green as the meter it is
		-- draining and as the trail behind you (FartTrail). Brown -> green is a far
		-- louder state change than the blue -> lighter-blue this used to do, which was
		-- easy to miss mid-flight.
		--
		-- The on/off LOGIC and every caller are untouched. The text goes to gui.fartLabel
		-- because the button itself carries no text: the label sits above the gloss band,
		-- where the button's own text would sit under it.
		local lit, deep = Color3.fromRGB(210, 255, 146), Color3.fromRGB(118, 216, 84)
		local seq = ColorSequence.new({ColorSequenceKeypoint.new(0, lit), ColorSequenceKeypoint.new(1, deep)})
		gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(162, 238, 112)
		gui.fartPatch.BackgroundColor3    = Color3.fromRGB(162, 238, 112)
		gui.fartBtnGradient.Color   = seq
		gui.fartPatchGradient.Color = seq
		gui.fartLabel.Text = "FARTING! (TAP TO STOP)"
	else
		local seq = ColorSequence.new({ColorSequenceKeypoint.new(0, WOOD_LIT), ColorSequenceKeypoint.new(1, WOOD_DEEP)})
		gui.fartBtnFrame.BackgroundColor3 = WOOD_LIT
		gui.fartPatch.BackgroundColor3    = WOOD_LIT
		gui.fartBtnGradient.Color   = seq
		gui.fartPatchGradient.Color = seq
		gui.fartLabel.Text = "TAP TO FART!"
	end
end

-- fuel from the real food/gut system: seed from leaderstats + refuel on RegenEvent (BuyFood)
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local sm = ls and ls:WaitForChild("StomachMax", 30)
	local cp = ls and ls:WaitForChild("CurrentPower", 30)
	if sm then
		stomachMax = sm.Value
		sm:GetPropertyChangedSignal("Value"):Connect(function() stomachMax = sm.Value; updateGasMeter() end)
	end
	if cp then
		currentPower = cp.Value
		gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
		-- adopt the server's CurrentPower only when it INCREASES (a refuel); flying drains locally
		cp:GetPropertyChangedSignal("Value"):Connect(function()
			if cp.Value > currentPower then
				currentPower = cp.Value
				gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
				updateGasMeter()
			end
		end)
	end
	CoinEvent = ReplicatedStorage:FindFirstChild("CoinEvent") or ReplicatedStorage:WaitForChild("CoinEvent", 20)
	if not CoinEvent then warn("[BottomHUD] CoinEvent missing -- flying will not pay coins") end
	BurnFuelEvent = ReplicatedStorage:FindFirstChild("BurnFuelEvent") or ReplicatedStorage:WaitForChild("BurnFuelEvent", 20)
	if not BurnFuelEvent then warn("[BottomHUD] BurnFuelEvent missing -- the server's CurrentPower will never drain, so stands will read FULL") end
	local regen = ReplicatedStorage:FindFirstChild("RegenEvent") or ReplicatedStorage:WaitForChild("RegenEvent", 20)
	if regen then
		regen.OnClientEvent:Connect(function(_added, newCurrent, newMax)
			if newMax then stomachMax = newMax end
			if newCurrent and newCurrent > currentPower then currentPower = newCurrent end
			gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
			updateGasMeter()
		end)
	end
	updateGasMeter()
end)

-- Report the tank's remaining fuel to the server. The drain above is client-side
-- only; without this the server's CurrentPower rises forever and every food stand
-- eventually reads FULL / NO ROOM even with an empty gas meter.
local function reportFuel()
	if BurnFuelEvent then pcall(function() BurnFuelEvent:FireServer(currentPower) end) end
end

-- start/stop (stopFlying KEEPS the meter -- only respawn zeroes it)
local function stopFlying()
	if not isFlying then return end
	-- bank the climb since the last 0.5s payout FIRST: thrust can end mid-tick
	-- (cancel, run dry, death) and that final sliver of climb was silently dropped
	local fchar = player.Character
	local fhrp = fchar and fchar:FindFirstChild("HumanoidRootPart")
	if fhrp and CoinEvent then
		local gained = fhrp.Position.Y - lastCoinY
		if gained > 0 then
			local pay = gained * COIN_PER_STUD * (_G.serverEventCoinMult or 1)
			flightCoinsEarned = flightCoinsEarned + pay
			lastCoinY = fhrp.Position.Y
			pcall(function() CoinEvent:FireServer(pay) end)
		end
	end
	isFlying = false; _G.isFlying = false; setFartLook(false)
	reportFuel() -- sync the burned fuel down to the server the moment thrust ends
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end; hrp.Anchored = false end
end
-- fart launch sounds: pick one at RANDOM each fart (toggle-on), 2D via SoundService
local FART_VOLUME = 0.6
local FART_SOUND_IDS = {
	"rbxassetid://137105349517966",
	"rbxassetid://136812322649032",
	"rbxassetid://119702591396866",
	"rbxassetid://123499328258921",
	"rbxassetid://92449881602559",
	"rbxassetid://109574021376037",
	"rbxassetid://129402830763074",
}
local fartSound = Instance.new("Sound"); fartSound.Name = "FartSound"; fartSound.Volume = FART_VOLUME
fartSound.Parent = game:GetService("SoundService")
local function playFartSound()
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	fartSound.SoundId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound:Play()
end

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 or gasMeter <= 0 then return end -- no fuel -> can't launch
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true; _G.isFlying = true; setFartLook(true)
	-- fresh earnings window per flight; peakHeight only ever RISES within a flight,
	-- so the cap never shrinks once you start descending
	coinTimer, flightCoinsEarned = 0, 0
	lastCoinY = hrp.Position.Y            -- climb is billed from the launch altitude
	_G.peakHeight = hrp.Position.Y
	playFartSound() -- random fart sound on every launch
	-- tell the server the coins + fart power we launched with (Meteorite Explosion restores this on death)
	pcall(function() local e = ReplicatedStorage:FindFirstChild("MeteorLaunchSnapshot"); if e then e:FireServer() end end)
end
local function toggleFart()
	if isFlying then stopFlying()                 -- cancel ascent; leftover gas preserved
	elseif gasMeter > 0 then startFlying() end    -- begin/resume ascent
end

-- DEATH MID-FLIGHT (fell without landing / reset character): the flight must not
-- cost you what you already earned. stopFlying() banks both the moment you die:
--   1. COINS -- its flush pays the climb since the last 0.5s tick instead of
--      dropping it, so a reset always credits the full flight's earnings.
--   2. FART POWER -- its reportFuel() tells the server the power you died with;
--      nothing on the server zeroes CurrentPower on death, so the respawn
--      re-seed below hands the same amount straight back.
local function onDied()
	stopFlying()
end
gui.fartBtn.Activated:Connect(toggleFart)
UserInputService.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Space then toggleFart() end
end)

-- flight loop: thrust up while flying + gas left; drain; scale power by gas; stop at 0
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end
	-- dead corpse: stop immediately (through onDied, so the coin flush is never
	-- skipped by a race with the Humanoid.Died hook -- both paths are idempotent).
	-- Without this the loop kept draining gas and reporting it down to the server
	-- while the body fell, eroding the fart power the player died with before the
	-- respawn re-seed could give it back.
	if hum.Health <= 0 then if isFlying then onDied() end return end
	if hrp.Anchored then hrp.Anchored = false end
	if isFlying and gasMeter > 0 then
		-- Primal Gut never drains -- thrust (and therefore earning) runs until you let go
		if not player:GetAttribute("HasPrimalGut") then
			gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt)      -- DRAIN
		end
		currentPower = (gasMeter / maxGasMeter) * stomachMax        -- power scaled by REMAINING gas
		-- keep the SERVER's CurrentPower in step with the drain (once a second), so the
		-- food stands' fit/afford checks see the real remaining tank, not a full one
		fuelSyncTimer = fuelSyncTimer + dt
		if fuelSyncTimer >= 1 then fuelSyncTimer = 0; reportFuel() end

		-- ---- climb coins, every COIN_TICK seconds of thrust ----
		local y = hrp.Position.Y
		if y > (_G.peakHeight or 0) then _G.peakHeight = y end
		coinTimer = coinTimer + dt
		if coinTimer >= COIN_TICK then
			coinTimer = 0
			local gained = y - lastCoinY          -- studs climbed since the last tick
			lastCoinY = y
			if gained > 0 and CoinEvent then
				local pay = gained * COIN_PER_STUD * (_G.serverEventCoinMult or 1)
				flightCoinsEarned = flightCoinsEarned + pay
				CoinEvent:FireServer(pay)
			end
		end
		-- Base ascent speed, scaled by any active flight modifier (e.g. Monsoon Rain's
		-- "wet conditions" sets _G.flightDistanceMultiplier = 0.9 for -10% flight distance).
		local speed = getFlightSpeed(currentPower) * (_G.flightDistanceMultiplier or 1)
		local move = hum.MoveDirection                             -- camera-relative steer
		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		bodyVel.Velocity = Vector3.new(move.X * FLIGHT_HORIZONTAL_SPEED, speed, move.Z * FLIGHT_HORIZONTAL_SPEED)
		updateGasMeter()
		if gasMeter <= 0 then currentPower = 0; updateGasMeter(); stopFlying() end -- ran dry
	else
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	end
end)

-- respawn reset + death hook. The meter zeroes here, then re-seeds from the
-- server -- and because onDied() synced the at-death power up before the reset,
-- "re-seed" means "get back exactly the fart amount you died with".
local function hookCharacter(char)
	local hum = char:FindFirstChild("Humanoid") or char:WaitForChild("Humanoid", 10)
	if hum then hum.Died:Connect(onDied) end
end
if player.Character then task.spawn(hookCharacter, player.Character) end
player.CharacterAdded:Connect(function(char)
	task.spawn(hookCharacter, char)
	isFlying = false; _G.isFlying = false; if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	currentPower = 0; gasMeter = 0; setFartLook(false); updateGasMeter()
	-- re-seed fuel from the server shortly after spawn: restores the fart power you died
	-- with (any death -- fell off an island, reset, meteor storm; the server never zeroes
	-- CurrentPower on death, and Meteorite Explosion restores its own snapshot on top)
	task.spawn(function()
		task.wait(0.4)
		local ls = player:FindFirstChild("leaderstats"); local cp = ls and ls:FindFirstChild("CurrentPower")
		if cp then currentPower = cp.Value; gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0; updateGasMeter() end
	end)
end)

updateGasMeter()

setFartLook(false) -- idle look on the (unrendered) fart button
updateGasMeter()
print(("[BottomHUD] gut panel ready -- icon + name + power bar + TAP TO FART (buy-food "
	.. "button removed; stands open on approach). card=%dx%d glow=%dx%d track=%dx%d "
	.. "slot=%dx%d | bottomGap card=%d glow=%d slot=%d -- first-realm sizes + height. "
	.. "Flight needs power > 0.")
	:format(PANEL_W, PANEL_H, PANEL_W + GLOW_OUT * 2, PANEL_H + GLOW_OUT * 2,
		BAR_W, BAR_H, PANEL_W - PAD * 2, CTA_H,
		BOTTOM_GAP, BOTTOM_GAP - GLOW_OUT, BOTTOM_GAP + PAD))

-- ---- DUPLICATE-HUD TRIPWIRE ------------------------------------------------------
-- Measuring scripts find objects BY NAME and stop at the first hit, so a second panel
-- carrying these names makes every measurement report a panel nobody is editing -- the
-- HUD then looks like it ignores changes, because the thing being measured is not this
-- one. `SpaceRealmHUD` is not in this repo, so if it is in the PlayerGui it came from
-- the place file (a leftover ScreenGui in StarterGui) or another Studio window.
--
-- This only REPORTS. It never deletes anything: a stray ScreenGui might be deliberate,
-- and quietly destroying somebody's GUI is not this script's call to make.
task.delay(3, function()
	-- EXCLUDE OUR WHOLE TREE, not just the card. The first version excluded only gutContent,
	-- so it reported this panel's OWN GasMeterGlow and CTASlot as duplicates of itself --
	-- a false alarm printed every single session, which is exactly how a real one gets
	-- ignored. Anything under gutWrap is ours by definition.
	local dupes = {}
	for _, d in ipairs(PlayerGui:GetDescendants()) do
		if d:IsA("GuiObject") and not d:IsDescendantOf(gutWrap) and d ~= gutWrap
			and (d.Name == "GasMeter" or d.Name == "CTASlot" or d.Name == "GasMeterGlow") then
			dupes[#dupes + 1] = d:GetFullName()
		end
	end
	if #dupes > 0 then
		warn(("[BottomHUD] %d OTHER GuiObject(s) share this HUD's names -- a by-name lookup "
			.. "will find one of these instead of ours (ours is %s):\n  %s")
			:format(#dupes, gutContent:GetFullName(), table.concat(dupes, "\n  ")))
	end
end)
