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
local COIN_TICK     = 0.23   -- seconds of thrust between payouts (was 0.5; x0.455 with the
                             -- shorter flights). The PAYOUT is per stud climbed, so the
                             -- total is identical either way -- this only keeps each tick
                             -- covering the same slice of altitude it used to, so the coin
                             -- counter ticks up as smoothly as before instead of in jumps.
-- [BALANCE] coins per stud climbed.
--
-- DIVIDED BY SPACING_SCALE ON PURPOSE. Income here is billed per STUD, while every gut
-- price in StomachTiers.LIST is a fixed coin constant solved from `gap * COIN_PER_STUD`
-- (see the R = 1.91 derivation in Shop.server.luau). Shrinking the tower therefore cuts
-- earnings without touching prices: at SPACING_SCALE 0.325 a flat 0.14 drops R to 0.62,
-- and Shop's header spells out what that means -- "a flight costs more than it earns and
-- the player spirals down". You earn less each flight, can never afford the next gut, and
-- so stop gaining height at all.
--
-- Dividing by the scale keeps `gap * COIN_PER_STUD` invariant, so R stays put and the
-- existing prices remain correct at ANY spacing. Retune the tower freely; this follows.
-- Bubbles.client.luau does the same and the two must match.
--
-- 1.911 / SPACING_SCALE = 4.200 coins per stud climbed. THE SINGLE MOST LOAD-BEARING NUMBER
-- IN THE PROGRESSION, and it is solved, not chosen.
--
-- It sets R, the return on fuel -- how many coins a flight banks per coin of fuel it burned:
--       R = COIN_PER_STUD x (fuel per coin) x (climb / tank)
-- and R is what decides HOW MANY FLIGHTS a crossing takes, because the bank grows (R-1) of
-- whatever you spend. Every serving is a fixed step (see FoodMenu), so the number of flights
-- to climb one step is 1 / ((R-1) x steps-held).
--
-- WHY 4.2 AND NOT THE OLD 2.32. A crossing is three meals (FoodMenu's rule). To walk that
-- ladder without flying the identical fill twice, one flight at one meal has to earn most of
-- a second meal, which needs R near 2 at the bottom of the tower. At 2.32 the return was
-- 1.10 -- a flight banked a tenth of its own fuel -- so the opening crossing either took two
-- flights (if the starting bank nearly covered it) or a dozen (if it did not), and nothing
-- in between. 4.2 puts the opening at R = 1.99: one meal, two meals, three meals, done.
--
-- IT IS NOT A DIFFICULTY DIAL ANY MORE, and that is the important part. R no longer has to
-- be held down to keep the tower hard, because the ramp comes from capacity outgrowing climb
-- (FlightTuning.BASE_TIERS) -- R falls 1.99 -> 1.33 on its own as you climb, without this
-- constant moving. Raising it makes the BOTTOM of the tower faster, not the top.
--
-- THE OLD CEILING NO LONGER BINDS. It used to be capped by "crossing one gap must not fund
-- the next", which held R under ~1.32 -- and that cap was precisely what forced the tower's
-- difficulty into gut prices, which in turn forced the doomed 98% saving flights described
-- in StomachTiers. The surplus is now taken by the gut price on landing instead, which is a
-- purchase the player makes on purpose rather than a wall they bounce off. Guts are priced
-- against this rate; move it and re-solve them, or they stop being affordable on arrival.
--
-- MUST MATCH Bubbles.client's COIN_PER_STUD exactly -- a coin bubble is priced as a fraction
-- of what a flight pays, so the two drifting apart silently re-tunes the whole economy.
local COIN_PER_STUD = FlightTuning.COIN_PER_STUD_BASE / FlightTuning.SPACING_SCALE
local coinTimer, flightCoinsEarned, lastCoinY = 0, 0, 0
-- ===== THE DESCENT PAYS TOO =====
-- Coins are billed for DISTANCE TRAVELLED, not height gained. A failed attempt climbs d and
-- falls back down d, so it collects on both halves; a successful crossing lands and never
-- falls, so it collects the climb alone. See the long note on FlightTuning.DESCENT_PAY_MULT
-- for why that asymmetry is the thing holding up crossings 3/5/7/9/11 -- short version: how
-- many flights a crossing takes is set by the ratio between what a LANDING pays and what a
-- FAILED flight pays, and until now those were identical, so the term vanished.
--
-- descentFloorY is the altitude you launched from. Paying below it would turn a dive off the
-- summit into 20,000 studs of income, so the payout stops there. It survives stopFlying()
-- deliberately: the fall happens AFTER thrust ends, which is exactly when this has to work.
--
-- TRACK THE PEAK, NOT A RUNNING MINIMUM. The first version of this held a `lastDescentY`
-- that only ever moved DOWN, and disarmed itself when it reached the floor. Both of those
-- start life at the launch altitude, so on the very first Heartbeat of every flight
-- lastDescentY <= descentFloorY was already true and the payout switched itself off before
-- the player had climbed a single stud. It paid nothing, ever.
--
-- That is not a cosmetic miss: the descent IS the tuning lever, so with it dead a repeated
-- flight earned 1x instead of 3x, R collapsed to ~1.0, and crossing 1 stalled at 35% forever
-- -- buy a 320-coin Egg, earn ~320 back, never accumulate. Caught in the first playtest.
--
-- The peak is the honest quantity: you are owed the fall from the highest point you reached,
-- down to (but never below) where you launched.
-- ===== ARM ONLY AFTER A REAL CLIMB. THIS IS THE THIRD TIME THIS PAYOUT DIED. =====
--
-- v1 held a running minimum and disarmed at `min <= floor`; both start at the launch
-- altitude, so it disarmed on frame 1 of every flight and paid nothing, ever.
-- v2 tracked the peak instead -- correct -- but kept the same `bot <= floor` disarm, and
-- that still fires on the launch frame: BodyVelocity takes a frame to apply, so the
-- character SETTLES a fraction of a stud below where it launched. y < floor makes
-- bot = floor, fell = 0 (no payment, so no touchdown flag either) and the disarm trips.
-- Whether it tripped depended on sub-stud physics jitter on a single frame, so it killed
-- roughly one flight in three at random -- measured 3 of 12 earning 1.30 coins/stud
-- against the intended 3.96, which silently added flights to every crossing.
--
-- The fix is to refuse to consider the descent at all until the player is genuinely UP.
-- Below `DESCENT_ARM_HEIGHT` above the launch altitude nothing is owed and nothing can be
-- disarmed, so launch-frame jitter is unreachable by construction.
-- ===== PAY THE FALL ON THE WAY UP =====
-- The money was always right; WHEN it landed was not. The fall home is worth 2x the climb, and
-- it was settled in one lump at the apex -- so the counter crawled to 4,000 on the way up and
-- then snapped to 10,000 the instant you started falling. It read as "the flight was pointless
-- and the fall is where the money is", which is the exact opposite of what is happening.
--
-- IT CANNOT SIMPLY BE MOVED INTO THE CLIMB RATE, though. A crossing that LANDS never falls and
-- so is paid 1x; a flight that fails does the whole round trip and is paid 3x. That gap between
-- landing pay and failure pay is the single lever that decides how many flights a crossing
-- takes (see FlightTuning.DESCENT_PAY_MULT and tools/ladder.py). Pay every stud 3x and a
-- successful crossing suddenly pays triple, the player gets rich, and every crossing above this
-- one loses flights -- which is exactly the 45-minute target going out the window.
--
-- SO PREDICT INSTEAD OF CONFIRM. Whether a flight can reach the island is fixed the moment you
-- launch: it is a function of the fuel in the tank, via climbFor(). If the tank cannot possibly
-- reach the gap then this flight is ALREADY a failure, the 2x is already earned, and it can be
-- paid out continuously as the peak rises instead of dumped at the top. The totals are
-- identical to the coin -- the same 3x for a failed flight, the same 1x for a landing -- only
-- now the failed flight's money arrives while you are flying, which is where you earned it.
--
-- The 0.90 margin keeps the prediction one-sided: prepay only starts when the tank falls at
-- least 10% short of the gap, so a prepaid flight cannot surprise us by landing (which would
-- be the one case that overpays). A flight that could have made it and misses anyway still
-- settles at the apex the old way -- rarer, and never wrong, just less pretty.
local DESCENT_MULT   = FlightTuning.DESCENT_PAY_MULT or 0
local descentPrepay  = false  -- is this flight's fall being paid out as we climb?
local PREPAY_SAFETY  = 0.90   -- only prepay when the tank falls this far short of the gap
local DESCENT_ARM_HEIGHT = 25   -- studs above launch before the fall home starts counting
-- What fraction of your upward speed survives the fart ending. See the long note in
-- stopFlying: this is the gut-gate fix, and 0.4 is the value the three broken gates need.
local COAST_DAMPING  = 0.4
-- ===== WHERE THE FALL HOME GETS PAID =====
-- At the TOP OF THE ARC, not on touchdown. The trigger is the moment it becomes impossible
-- that you crossed: you are falling, and you are back under APEX_PAY_SHARE of the gap. For a
-- flight that ran out of gas at 40% that is a fraction of a second past the peak; for a 97%
-- near-miss it is a short way into the fall, still high in the sky. A flight that actually
-- crosses lands ABOVE that line and so never triggers it -- which is the whole point, because
-- a crossing pays 1x and a failure pays 3x, and mixing those up is what collapses the ladder.
--
-- 0.85 is deliberately slack. Islands are lumpy and a real crossing can touch down somewhat
-- below its nominal altitude; the margin is 15% of the gap (63 studs at the smallest, 508 at
-- the largest) so terrain can never push a successful crossing under the line.
local APEX_PAY_SHARE = 0.85
local APEX_DROP      = 6     -- studs below the peak before "falling" is real and not jitter
local descentFloorY  = nil   -- HIGH-WATER MARK OF WHAT IS ALREADY PAID. Starts at the ground
                             -- you left and ratchets up to each peak as that arc settles, so a
                             -- chain-tapped climb pays each new arc once and never twice.
                             -- nil = no trip in progress.
local descentBaseY   = nil   -- the ground this trip started from; never moves. The crossed test
                             -- measures against THIS, not the ratcheting floor.
local descentPeakY   = nil   -- highest point reached this flight; the top of what is owed
local descentArmed   = false -- has the player actually climbed clear of the launch pad yet?
-- The gap this flight is trying to cross, captured at launch. It is what tells a landing
-- "you are still on the island you left" apart from "you made it" -- see the payout block.
local descentGap     = nil
-- ===== THE LUMP IS COUNTED OUT, NOT DROPPED IN =====
-- A four-thousand-coin jump in one frame reads as a glitch. The climb pays every COIN_TICK
-- and feels like earning, so the fall home is queued here and drained on that same cadence:
-- identical rhythm, identical counter, just a couple of seconds of it after you crest.
local descentOwed    = 0     -- coins settled but not yet counted out to the player
local descentPayRate = 0     -- coins per second the counter is currently running at
local descentPayTick = 0     -- seconds since the last chunk went to the server
-- 0.15, NOT 1.6. The lump is EARNED BY THE CLIMB and settled at the apex -- but draining it
-- over 1.6 s meant the counter was still ticking up while the player was falling, which
-- reads as "I get paid for falling" even though not one stud of the fall was billed. At
-- 0.15 it lands as the flight tops out, which is when it was actually earned. Nothing about
-- the AMOUNT changes; this is purely when the number finishes moving.
local PAYOUT_SECONDS = 0.15  -- how long a whole lump takes to tick over
-- Debug accounting, reported per flight so a partial payout can never hide again.
local descentStuds   = 0     -- studs actually PAID for on the way down
local descentWhy     = "in flight"
local CoinEvent = nil        -- resolved below; the shop server creates it
local BurnFuelEvent = nil    -- resolved below; reports drained fuel so the server's CurrentPower goes DOWN too
local fuelSyncTimer = 0      -- seconds since the last in-flight fuel report
local stomachMax  = 120   -- gut's max raw power (from StomachMax); bigger gut = faster + higher
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
-- STOMACHMAX MUST BE PASSED. The speed bands are fractions of YOUR OWN tank now, not
-- absolute fuel amounts, so the lookup cannot tell "nearly empty on a Colossus" from
-- "most of a tank on a Hatchling" without it. Omit it and every gut flies at tier-1 speed.
local function getFlightSpeed(power)
	return FlightTuning.getFlightSpeed(power, stomachMax)
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

-- ============================================================================
-- TAKE A BITE OUT OF THE TANK -- the hook a hazard calls to cost the player fuel.
-- ============================================================================
-- BottomHUD owns the meter: gasMeter is the truth, currentPower is derived from it, and the
-- server only learns about either through reportFuel(). A hazard script that wrote to those
-- locals could not (they are upvalues here), and one that fired BurnFuelEvent itself would
-- desync the bar from the server -- the HUD would still show the fuel you no longer have.
-- So the drain lives here, next to the state it edits, and hazards ask for it by fraction.
--
-- FRACTION OF WHAT IS LEFT, NOT OF THE TANK. A bird costing 1/6 of a full Colossus would be
-- a bigger hit than the whole starting gut; 1/6 of what you are actually carrying scales
-- itself and can never stall you outright, because a sixth of nearly-nothing is nothing.
--
-- Returns the power actually removed so the caller can report it.
function _G.dinoDrainFuelFraction(frac)
	frac = math.clamp(tonumber(frac) or 0, 0, 1)
	if frac <= 0 or gasMeter <= 0 then return 0 end
	local before = currentPower
	gasMeter     = math.max(0, gasMeter * (1 - frac))
	currentPower = (gasMeter / maxGasMeter) * stomachMax
	updateGasMeter()
	reportFuel()
	return before - currentPower
end



-- ============================================================================
-- PROGDATA -- the whole progression run, in one pasteable block. F7, or /progdata.
--
-- WHY THIS EXISTS AND WHY IT IS SHAPED LIKE THIS. The progression is tuned against a
-- simulation of the coin economy, and that simulation only knows about the CLIMB payout.
-- Real play also has bubble pickups, event multipliers and imperfect flying, so predicted
-- flights-per-island and observed flights-per-island drift -- and reading it back out of
-- the server log meant reconstructing launches from `space left` fields on buy lines.
-- This records the run directly so ONE playthrough answers every tuning question.
--
-- THE THREE NUMBERS THE TUNING ACTUALLY TURNS ON:
--   launches  -- flights spent on a crossing. The whole design target (no 1s, 4-5 on a
--                purchase wall, 2 on a band wall). This is the headline row.
--   bonus%    -- coins banked that did NOT come from the climb payout. The economy is
--                solved assuming that is zero, so it says how far real income sits above
--                the model. If it is large, every predicted count is optimistic.
--   spare     -- fuel still in the tank on landing. A crossing that lands with a lot to
--                spare means the gap is too easy for that gut, and vice versa.
--
-- Client-side because this is the only place that sees launch/land, fuel at launch, and
-- the per-tick climb payout. Gut purchases and crossings are inferred from StomachMax and
-- HighestSlot changing, so no remotes were added for it.
-- ============================================================================
-- ============================================================================
-- WHAT WAS ADDED FOR THE DESCENT-PAY BALANCE PASS, and why each field is here.
--
-- The previous version of this dump recorded launches and crossings but NOT the two things
-- that turned out to decide the whole progression, so a broken build looked fine in the log:
--
--   1. THE PURCHASE SEQUENCE. The balance is solved against what BUY MAX actually buys from
--      the coins actually in hand. A shipped pass failed because the player could not afford
--      the food the ladder assumed -- BUY MAX silently fell back on cheap food, the effective
--      value per coin collapsed, and the crossing stalled. The log showed "5 launches, no
--      progress" with no way to see why. Every serving is now recorded with its price, power
--      and value, so the fallback is visible the moment it happens.
--
--   2. ASCENT PAY vs DESCENT PAY. Coins are now paid for distance TRAVELLED, so a failed
--      flight collects the climb AND the fall while a successful crossing collects the climb
--      alone. That asymmetry IS the tuning lever (see DESCENT_PAY_MULT). Lumped together
--      they are unreadable, so they are two counters.
--
-- The third addition is CLEAN-SAMPLE MARKING. Any flight that ran under a weather event, a
-- coin multiplier, a wind push or a bubble pickup is not a valid sample of the tuned economy,
-- and averaging it in is how a tuning pass gets aimed at the wrong number. Those flights are
-- flagged and the summary reports clean and dirty averages separately.
-- ============================================================================
local PROGDATA = {}
do
	local launches, cur = {}, nil
	local coinsAtLaunch, lastTank, lastSlot = 0, nil, nil
	local crossings, pending = {}, nil        -- pending = the crossing being worked on
	local gutBuys = {}                        -- slot -> {name, cost} bought while there
	local pendingBuys = {}                    -- servings bought since the last launch
	local totalServings = {}                  -- name -> lifetime count, the "inventory" line
	local sessionSpend, sessionEarn = 0, 0

	local function coinsNow()
		local ls = player:FindFirstChild("leaderstats")
		local c  = ls and ls:FindFirstChild("Coins")
		return c and c.Value or 0
	end
	local function slotNow() return math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1) end

	-- Every module that can bend a flight, read in one place so the flight record carries the
	-- exact conditions it flew under. `clean` is the AND of all of them being neutral.
	local function modifiersNow()
		local m, dirty = {}, false
		local function chk(label, v, neutral)
			if v ~= nil and math.abs((tonumber(v) or neutral) - neutral) > 1e-6 then
				m[#m + 1] = label .. "=" .. string.format("%.3f", v); dirty = true
			end
		end
		chk("coinMult",   _G.serverEventCoinMult,      1)
		chk("speedMult",  _G.serverEventSpeedMult,     1)
		chk("drainMult",  _G.serverEventGasDrainMult,  1)
		chk("heightMult", _G.serverEventHeightMult,    1)
		chk("ringMult",   _G.serverEventRingMult,      1)
		chk("distMult",   _G.flightDistanceMultiplier, 1)
		if _G.windstormActive then m[#m + 1] = "WINDSTORM"; dirty = true end
		if _G.thunderWindVec then m[#m + 1] = "THUNDERWIND"; dirty = true end
		if _G.fireballKnock  then m[#m + 1] = "FIREBALL"; dirty = true end
		if type(_G.BigEvents) == "table" and _G.BigEvents.active then
			m[#m + 1] = "EVENT:" .. tostring(_G.BigEvents.active); dirty = true
		end
		return (#m > 0) and table.concat(m, ",") or "none", dirty
	end

	-- THE PURCHASE HOOK. Shop.client calls this for every serving it sends to the server --
	-- single BUY and each step of BUY MAX alike -- because the client is the only place that
	-- knows WHICH food was chosen and in what order. `via` is "BUY", "MAX" or "MAX-topoff",
	-- which is what makes a BUY MAX fallback readable as a sequence rather than a total.
	function PROGDATA.onBuy(name, price, power, via)
		price, power = tonumber(price) or 0, tonumber(power) or 0
		sessionSpend = sessionSpend + price
		totalServings[name] = (totalServings[name] or 0) + 1
		if pending then pending.spend = (pending.spend or 0) + price end
		local last = pendingBuys[#pendingBuys]
		if last and last.name == name and last.via == via then
			last.qty = last.qty + 1                      -- collapse runs: "Ribs x7", not 7 rows
		else
			pendingBuys[#pendingBuys + 1] =
				{ name = name, price = price, power = power, qty = 1, via = via or "BUY" }
		end
	end
	_G.PROGDATA_buy = PROGDATA.onBuy

	local function startCrossing(slot)
		pending = { slot = slot, launches = 0, coinsIn = coinsNow(), climbPay = 0, totalPay = 0,
		            spend = 0, buys = {} }
	end
	-- A gut purchase is a StomachMax INCREASE. Watching the stat means no remote and no
	-- coupling to the shop -- it also catches /infinitegut and the Robux grant identically.
	local function watchTank()
		local ls = player:WaitForChild("leaderstats", 30); if not ls then return end
		local sm = ls:WaitForChild("StomachMax", 30); if not sm then return end
		lastTank = sm.Value
		sm.Changed:Connect(function(v)
			if lastTank and v > lastTank and pending then
				local nm, cost = "?", 0
				local ok, ST = pcall(function()
					return require(game:GetService("ReplicatedStorage").DinosaurRealm.StomachTiers)
				end)
				if ok and ST then
					if ST.NAME_BY_MAX then nm = ST.NAME_BY_MAX[v] or ("max " .. v) end
					local tier = ST.byMaxPower and ST.byMaxPower(v)
					if tier and not tier.robux then cost = tier.cost or 0 end
				end
				-- GUT AFFORDABILITY, captured at the only moment it can be: right after the
				-- purchase. What the player is left holding has to cover a meal for the crossing
				-- the gut just opened, or BUY MAX falls back on junk food and the crossing stalls.
				-- That exact failure shipped once; this line is how it gets caught next time.
				gutBuys[pending.slot] = { name = nm, cost = cost, from = lastTank, to = v,
				                          coinsAfter = coinsNow() }
				sessionSpend = sessionSpend + cost
			end
			lastTank = v
		end)
	end
	task.spawn(watchTank)

	-- THE ARRIVAL SIGNAL. HighestSlot going up is the server saying "you are standing on a
	-- higher island", which is the only trustworthy definition of a completed crossing --
	-- and it is what the anti-skip and food unlocks key off, so the telemetry agrees with
	-- the game by construction. Whichever launch was last is the one that made it.
	player:GetAttributeChangedSignal("HighestSlot"):Connect(function()
		local now = slotNow()
		if not pending or now <= pending.slot then return end
		if launches[#launches] then launches[#launches].made = true end
		pending.coinsOut = coinsNow()
		pending.gut = gutBuys[pending.slot]
		crossings[#crossings + 1] = pending
		startCrossing(now)
	end)

	function PROGDATA.onLaunch(y, fuel, tank)
		local slot = slotNow()
		-- ===== REJECT THE GHOST CROSSING =====
		-- HighestSlot is server-authoritative and takes a moment to replicate, so the first
		-- launch after landing on a new island is still tagged with the crossing you JUST
		-- finished. You are already standing at the destination altitude, so that hop records
		-- as an instant win -- a measured playtest logged "Frostbite Flats -> Misty Mire,
		-- SUCCESS, 15/712 studs, 2.1%" 0.85s after the real 769/712 crossing.
		--
		-- It is a replication artifact, not a one-try crossing, and left in it corrupts the
		-- flight counts this whole progression is judged on. If the launch altitude is already
		-- at the top of the gap, the slot reading is stale: skip the flight entirely rather
		-- than attribute it to either crossing.
		local gapNow = FlightTuning.gapFromSlot(slot)
		if gapNow and pending and pending.slot == slot and #(pending.ladder or {}) > 0 then
			local base = pending.launchY
			if base and (y - base) >= gapNow * 0.98 then
				cur = nil                 -- already at the next island; this is not an attempt
				return
			end
		end
		if not pending or pending.slot ~= slot then startCrossing(slot) end
		pending.launchY = pending.launchY or y
		coinsAtLaunch = coinsNow()
		local mods, dirty = modifiersNow()
		local gap = FlightTuning.gapFromSlot(slot)
		local tier = FlightTuning.tierFor(tank)
		cur = {
			slot = slot, y0 = y, fuel = fuel, tank = tank, t0 = os.clock(),
			climbPay = 0, descentPay = 0,
			gap = gap, climbCap = tier and tier.climb or 0,
			speed = FlightTuning.getFlightSpeed(fuel, tank),
			-- The purchases that funded THIS flight: everything bought since the last launch.
			buys = pendingBuys, coinsBefore = coinsAtLaunch,
			mods = mods, dirty = dirty,
		}
		pendingBuys = {}
		if pending then
			for _, b in ipairs(cur.buys) do pending.buys[#pending.buys + 1] = b end
		end
	end
	function PROGDATA.onClimbPay(amount) if cur then cur.climbPay = cur.climbPay + amount end end
	-- THE DESCENT IS PAID AFTER THE FLIGHT RECORD HAS ALREADY CLOSED, and that is not a bug
	-- to fix by moving the close. stopFlying runs the instant THRUST ends -- which is the top
	-- of the arc -- and the fall is paid over the following seconds as the player drops. So
	-- this posts backwards into the launch that just finished, and tops up its `paid` and its
	-- crossing's running total as the coins actually arrive. Routing it through `cur` instead
	-- would silently discard every descent coin, because `cur` is nil by then.
	function PROGDATA.onDescentPay(amount, studs)
		local f = launches[#launches]
		if not f then return end
		f.descentPay   = (f.descentPay or 0) + amount
		f.descentStuds = (f.descentStuds or 0) + (studs or 0)
		f.paid = (f.paid or 0) + amount
		if pending then pending.totalPay = (pending.totalPay or 0) + amount end
		sessionEarn = sessionEarn + amount
	end
	-- WHY THE FALL STOPPED PAYING. Recorded per flight so a payout that quietly dies can never
	-- again be mistaken for "that crossing is just slow" -- the bug this exists to catch cost
	-- one flight in three a third of its income and silently lengthened every crossing.
	function PROGDATA.onDescentEnd(reason)
		local f = launches[#launches]
		if f and not f.descentWhy then f.descentWhy = reason end
	end
	function PROGDATA.onLand(y, fuelLeft)
		if not cur then return end
		cur.rise  = y - cur.y0
		cur.secs  = os.clock() - cur.t0
		cur.paid  = coinsNow() - coinsAtLaunch
		cur.spare = fuelLeft
		cur.burned = (cur.fuel or 0) - (fuelLeft or 0)
		cur.pct    = (cur.gap and cur.gap > 0) and (cur.rise / cur.gap * 100) or 0
		-- A second modifier read: an event that STARTED mid-flight dirties the sample just as
		-- surely as one that was already running when the player launched.
		local mods2, dirty2 = modifiersNow()
		if dirty2 and not cur.dirty then cur.dirty = true; cur.mods = cur.mods .. "|+" .. mods2 end
		sessionEarn = sessionEarn + (cur.paid or 0)
		-- `made` IS NOT DECIDED HERE. stopFlying runs the instant thrust ends, which is
		-- before the character touches down and well before the SERVER credits HighestSlot
		-- (PetXPHooks only counts you as arrived once you are grounded on the island). Read
		-- the slot here and every successful crossing would look like a failure. The
		-- HighestSlot watcher below closes the crossing instead, and back-marks this launch.
		cur.made = false
		launches[#launches + 1] = cur
		if pending then
			pending.launches = pending.launches + 1
			pending.climbPay = pending.climbPay + cur.climbPay
			pending.totalPay = pending.totalPay + cur.paid
			pending.ladder = pending.ladder or {}
			pending.ladder[#pending.ladder + 1] = cur.pct
		end
		cur = nil
		if #launches > 400 then table.remove(launches, 1) end
	end

	-- ===== THE DUMP =====
	-- ONE CONTINUOUS BLOCK, DELIBERATELY UGLY. The brief is Ctrl+A / Ctrl+C / paste, so this
	-- optimises for "nothing is missing and nothing is truncated", not for reading in the
	-- output window. Four sections: per-flight, per-crossing, realm summary, and the exact
	-- config the run actually used. That last section is not optional -- a debug paste that
	-- does not say which numbers produced it cannot be acted on, and this realm has already
	-- lost one tuning pass to a stale constant printed next to live behaviour.
	function PROGDATA.dump()
		local FT = FlightTuning
		local out = {}
		local function w(s) out[#out + 1] = s end
		local function fmt(f, ...) return string.format(f, ...) end

		local ok, IO = pcall(function()
			return require(game:GetService("ReplicatedStorage").DinosaurRealm.IslandOrder)
		end)
		if not ok then IO = nil end
		local ok2, ST = pcall(function()
			return require(game:GetService("ReplicatedStorage").DinosaurRealm.StomachTiers)
		end)
		if not ok2 then ST = nil end
		local ok3, FM = pcall(function()
			return require(game:GetService("ReplicatedStorage").DinosaurRealm.FoodMenu)
		end)
		if not ok3 then FM = nil end

		local function islandOf(slot)
			local n = IO and IO.SLOT_TO_ISLAND and IO.SLOT_TO_ISLAND[slot]
			local nm = n and IO.NAMES and IO.NAMES[n]
			return n and fmt("island%d%s", n, nm and (" " .. nm) or "") or "?"
		end
		local function buySeq(buys)
			if not buys or #buys == 0 then return "(nothing bought)" end
			local parts = {}
			for _, b in ipairs(buys) do
				parts[#parts + 1] = fmt("%s x%d @%d/%dp(%.4f)[%s]",
					b.name, b.qty, b.price, b.power, b.power / math.max(1, b.price), b.via)
			end
			return table.concat(parts, " + ")
		end
		local function buyTotals(buys)
			local coins, power, n = 0, 0, 0
			for _, b in ipairs(buys or {}) do
				coins = coins + b.qty * b.price; power = power + b.qty * b.power; n = n + b.qty
			end
			return coins, power, n
		end

		w("=== PROGDATA RAW DUMP -- COPY EVERYTHING BETWEEN THE MARKERS ===")
		w(fmt("player=%s  slot=%d (%s)  coins=%d  tank=%d  fuel=%d  time=%s",
			player.Name, slotNow(), islandOf(slotNow()), math.floor(coinsNow()),
			math.floor(stomachMax), math.floor(currentPower), os.date("%Y-%m-%d %H:%M:%S")))
		w("")

		---------------------------------------------------------------- PER FLIGHT
		w("---------- SECTION 1: EVERY FLIGHT ----------")
		for i, f in ipairs(launches) do
			local spent, gained, n = buyTotals(f.buys)
			local bonus = (f.paid or 0) - (f.climbPay or 0) - (f.descentPay or 0)
			w(fmt("FLIGHT %d", i))
			w(fmt("  crossing      slot %d -> slot %d   (%s -> %s)",
				f.slot, f.slot + 1, islandOf(f.slot), islandOf(f.slot + 1)))
			w(fmt("  gut           %s  tank=%d  climbCap=%.0f  launchSpeed=%.1f studs/s",
				(ST and ST.NAME_BY_MAX and ST.NAME_BY_MAX[f.tank]) or ("max " .. tostring(f.tank)),
				f.tank or 0, f.climbCap or 0, f.speed or 0))
			-- coinsBefore is read AT LAUNCH, i.e. after the shop has been used, so the
			-- pre-shop wallet is reconstructed rather than guessed. Both are printed because
			-- the affordability question ("could they buy the good food?") is asked against
			-- the pre-shop number and the ladder is driven by the post-shop one.
			w(fmt("  before        coinsPreShop=%d  coinsAtLaunch=%d  fuel=%d/%d (%.1f%%)",
				math.floor((f.coinsBefore or 0) + spent), math.floor(f.coinsBefore or 0),
				math.floor(f.fuel or 0), math.floor(f.tank or 0),
				(f.tank or 0) > 0 and (f.fuel or 0) / f.tank * 100 or 0))
			w(fmt("  purchases     %s", buySeq(f.buys)))
			w(fmt("  purchaseTot   servings=%d  coinsSpent=%d  powerGained=%d  coinsLeft=%d  eff=%.4f",
				n, spent, gained, math.floor(f.coinsBefore or 0), gained / math.max(1, spent)))
			w(fmt("  target        gap=%.0f studs", f.gap or 0))
			w(fmt("  result        rise=%.0f  progress=%.1f%%  secs=%.2f  avg=%.1f studs/s  %s",
				f.rise or 0, f.pct or 0, f.secs or 0,
				(f.secs or 0) > 0 and (f.rise or 0) / f.secs or 0,
				f.made and "*** MADE IT ***" or "FELL SHORT"))
			w(fmt("  fuel          burned=%.0f  remaining=%.0f  returnFall=%.0f studs",
				f.burned or 0, f.spare or 0, f.made and 0 or (f.rise or 0)))
			w(fmt("  coins         ascent=%.1f  descent=%.1f  bonus/bubbles=%.1f  TOTAL=%.1f  net=%.1f",
				f.climbPay or 0, f.descentPay or 0, bonus, f.paid or 0, (f.paid or 0) - spent))
			-- ===== THE DESCENT AUDIT =====
			-- A failed flight climbs `rise` and falls the same `rise`, so it is owed
			-- rise * rate on the way up and rise * rate * MULT on the way down. Anything less
			-- than ~100% here means the payout died mid-flight and that crossing's flight count
			-- is inflated -- do NOT read pacing off a run with expected/actual below 95%.
			local rate    = COIN_PER_STUD * (_G.serverEventCoinMult or 1)
			local rise    = math.max(0, f.rise or 0)
			local expDesc = f.made and 0 or (rise * rate * DESCENT_MULT)
			local actDesc = f.descentPay or 0
			local expTot  = rise * rate + expDesc
			local actTot  = (f.climbPay or 0) + actDesc
			local pctD    = expDesc > 0 and (actDesc / expDesc * 100) or 100
			-- studsPaid counts the fall however it was billed -- prepaid on the way up (the normal
			-- case now) or settled at the apex. Either way it must equal the rise, so this line
			-- still reads ~100% and a payout that quietly dies still shows up here.
			w(fmt("  descentAudit  studsPaid=%.0f/%.0f  expected=%.1f  actual=%.1f  (%.0f%% paid)",
				f.descentStuds or 0, rise, expDesc, actDesc, pctD))
			w(fmt("  descentEnded  %s%s",
				f.descentWhy or (f.made and "n/a -- crossing succeeded" or "NEVER COMPLETED"),
				(not f.made and pctD < 95) and "   *** UNDERPAID -- THIS FLIGHT IS NOT A VALID SAMPLE ***" or ""))
			w(fmt("  coinTotals    expected=%.1f  actual=%.1f  (%.0f%% of intended)",
				expTot, actTot, expTot > 0 and (actTot / expTot * 100) or 100))
			w(fmt("  modifiers     %s", f.mods or "none"))
			w(fmt("  cleanSample   %s", f.dirty and "NO -- event/modifier active, do not average" or "YES"))
		end
		if #launches == 0 then w("  (no flights recorded)") end
		w("")

		---------------------------------------------------------------- PER CROSSING
		w("---------- SECTION 2: EVERY CROSSING ----------")
		local all = {}
		for _, c in ipairs(crossings) do all[#all + 1] = c end
		if pending and pending.launches > 0 then
			pending.inProgress = true; all[#all + 1] = pending
		end
		for _, c in ipairs(all) do
			local lad = c.ladder or {}
			local ladS, gains, worst, repeats = {}, {}, 0, 0
			for i, p in ipairs(lad) do
				ladS[#ladS + 1] = fmt("%.1f%%", p)
				if i > 1 then
					local d = p - lad[i - 1]
					gains[#gains + 1] = fmt("%+.1f", d)
					if math.abs(d) < 1.5 then repeats = repeats + 1 end
				end
				if i < #lad or c.inProgress then worst = math.max(worst, p) end
			end
			local gb = gutBuys[c.slot]
			local spent, gained, n = buyTotals(c.buys)
			w(fmt("CROSSING slot %d -> %d   (%s -> %s)%s",
				c.slot, c.slot + 1, islandOf(c.slot), islandOf(c.slot + 1),
				c.inProgress and "   [IN PROGRESS]" or ""))
			w(fmt("  flights       %d", c.launches))
			w(fmt("  ladder        %s", #ladS > 0 and table.concat(ladS, " -> ") or "(none)"))
			w(fmt("  gainPerTry    %s", #gains > 0 and table.concat(gains, ", ") or "(n/a)"))
			w(fmt("  worstMiss     %.1f%%   %s", worst,
				worst >= 90 and "*** 90%+ EDGING ***" or (worst >= 85 and "** 85%+ **" or "ok")))
			w(fmt("  repeatedTries %d  %s", repeats,
				repeats > 0 and "*** near-identical flights (<1.5% gain) ***" or "none"))
			w(fmt("  coins         in=%d  out=%s  earned=%d  spentOnFood=%d  net=%+d",
				math.floor(c.coinsIn or 0),
				c.coinsOut and tostring(math.floor(c.coinsOut)) or "(pending)",
				math.floor(c.totalPay or 0), spent, math.floor((c.totalPay or 0) - spent)))
			w(fmt("  foodBought    %d servings, %d coins: %s", n, spent, buySeq(c.buys)))
			if gb then
				-- The best-value food unlocked at this slot is what BUY MAX will reach for
				-- first, so that price is the affordability bar the gut must clear.
				local best, bestEff = nil, -1
				for k = 1, math.min(c.slot, FM and #FM.LIST or 0) do
					local fd = FM.LIST[k]
					if fd and fd.power / fd.price > bestEff then best, bestEff = fd, fd.power / fd.price end
				end
				w(fmt("  gutBought     %s  cost=%d  tank %d -> %d  coinsLeftAfter=%d",
					gb.name, gb.cost, gb.from, gb.to, math.floor(gb.coinsAfter or 0)))
				if best then
					local afford = (gb.coinsAfter or 0) >= best.price
					w(fmt("  gutAfford     needs %d for %s (best value %.4f) -> %s",
						best.price, best.name, bestEff,
						afford and "OK" or "*** FAILED -- cannot afford the intended food ***"))
				end
			else
				w("  gutBought     none")
			end
			if c.launches >= 3 and #lad >= 3 and (lad[#lad] - lad[1]) < 5 then
				w("  ECONOMIC STALL *** progress flat across the whole crossing -- income is not covering fuel ***")
			end
		end
		if #all == 0 then w("  (no crossings recorded)") end
		w("")

		---------------------------------------------------------------- SUMMARY
		w("---------- SECTION 3: REALM SUMMARY ----------")
		local counts, total = {}, 0
		for _, c in ipairs(all) do
			counts[#counts + 1] = fmt("%d:%d", c.slot, c.launches); total = total + c.launches
		end
		w(fmt("flightsPerCrossing  %s", table.concat(counts, "  ")))
		local curve = {}
		for _, c in ipairs(all) do curve[#curve + 1] = tostring(c.launches) end
		w(fmt("curve               [%s]", table.concat(curve, ", ")))
		w(fmt("totalFlights        %d   (recorded launches %d)", total, #launches))
		local function avg(lo, hi)
			local s, n = 0, 0
			for _, c in ipairs(all) do
				if c.slot >= lo and c.slot <= hi then s = s + c.launches; n = n + 1 end
			end
			return n > 0 and fmt("%.2f (n=%d)", s / n, n) or "n/a"
		end
		w(fmt("earlyAvg  slots 1-4   %s", avg(1, 4)))
		w(fmt("midAvg    slots 5-8   %s", avg(5, 8)))
		w(fmt("lateAvg   slots 9-12  %s", avg(9, 12)))
		w("")
		w("allLadders")
		for _, c in ipairs(all) do
			local s = {}
			for _, p in ipairs(c.ladder or {}) do s[#s + 1] = fmt("%.1f", p) end
			w(fmt("  slot %-3d %s", c.slot, table.concat(s, " -> ")))
		end
		w("")
		local worstAll, worstSlot, over85, over90 = 0, 0, {}, {}
		for _, c in ipairs(all) do
			local lad = c.ladder or {}
			for i, p in ipairs(lad) do
				if i < #lad or c.inProgress then
					if p > worstAll then worstAll, worstSlot = p, c.slot end
					if p >= 90 then over90[#over90 + 1] = fmt("slot %d try %d = %.1f%%", c.slot, i, p)
					elseif p >= 85 then over85[#over85 + 1] = fmt("slot %d try %d = %.1f%%", c.slot, i, p) end
				end
			end
		end
		w(fmt("worstMiss           %.1f%% on slot %d", worstAll, worstSlot))
		w(fmt("misses85plus        %s", #over85 > 0 and table.concat(over85, "; ") or "none"))
		w(fmt("misses90plus        %s", #over90 > 0 and table.concat(over90, "; ") or "NONE (edging clear)"))
		local reps, stalls = {}, {}
		for _, c in ipairs(all) do
			local lad = c.ladder or {}
			for i = 2, #lad do
				if math.abs(lad[i] - lad[i - 1]) < 1.5 then
					reps[#reps + 1] = fmt("slot %d try %d->%d (%.1f%% -> %.1f%%)", c.slot, i - 1, i, lad[i - 1], lad[i])
				end
			end
			if c.launches >= 3 and #lad >= 3 and (lad[#lad] - lad[1]) < 5 then
				stalls[#stalls + 1] = fmt("slot %d (%d flights, %.1f%% -> %.1f%%)", c.slot, c.launches, lad[1], lad[#lad])
			end
		end
		w(fmt("repeatedFlights     %s", #reps > 0 and table.concat(reps, "; ") or "none"))
		w(fmt("economicStalls      %s", #stalls > 0 and table.concat(stalls, "; ") or "none"))
		local affordFails, gutFails = {}, {}
		for _, c in ipairs(all) do
			local first = nil
			for _, f in ipairs(launches) do
				if f.slot == c.slot then first = f; break end
			end
			if first then
				local _, _, n = buyTotals(first.buys)
				if n == 0 then
					affordFails[#affordFails + 1] = fmt("slot %d: flight 1 launched with NO purchase (coins=%d)",
						c.slot, math.floor(first.coinsBefore or 0))
				end
			end
			local gb = gutBuys[c.slot]
			if gb and FM then
				local best, bestEff = nil, -1
				for k = 1, math.min(c.slot, #FM.LIST) do
					local fd = FM.LIST[k]
					if fd.power / fd.price > bestEff then best, bestEff = fd, fd.power / fd.price end
				end
				if best and (gb.coinsAfter or 0) < best.price then
					gutFails[#gutFails + 1] = fmt("slot %d: %s left %d coins, %s costs %d",
						c.slot, gb.name, math.floor(gb.coinsAfter or 0), best.name, best.price)
				end
			end
		end
		w(fmt("foodAffordFails     %s", #affordFails > 0 and table.concat(affordFails, "; ") or "none"))
		w(fmt("gutAffordFails      %s", #gutFails > 0 and table.concat(gutFails, "; ") or "none"))
		local easy, hard = {}, {}
		for _, c in ipairs(all) do
			if not c.inProgress then
				if c.launches <= 2 then easy[#easy + 1] = fmt("slot %d (%d)", c.slot, c.launches) end
				if c.launches >= 10 then hard[#hard + 1] = fmt("slot %d (%d)", c.slot, c.launches) end
			end
		end
		w(fmt("unusuallyEasy       %s", #easy > 0 and table.concat(easy, ", ") or "none (no 1-2 flight crossings)"))
		w(fmt("unusuallyHard       %s", #hard > 0 and table.concat(hard, ", ") or "none"))
		local cleanN, dirtyN = 0, 0
		for _, f in ipairs(launches) do
			if f.dirty then dirtyN = dirtyN + 1 else cleanN = cleanN + 1 end
		end
		w(fmt("cleanFlights        %d clean / %d event-affected  (%.0f%% clean)",
			cleanN, dirtyN, #launches > 0 and cleanN / #launches * 100 or 100))
		-- THE HEADLINE HEALTH CHECK. If this is not ~100%, the pacing in this dump is fiction.
		local underpaid, expSum, actSum = {}, 0, 0
		for i, f in ipairs(launches) do
			local rate = COIN_PER_STUD
			local rise = math.max(0, f.rise or 0)
			local e = rise * rate + (f.made and 0 or rise * rate * DESCENT_MULT)
			local a = (f.climbPay or 0) + (f.descentPay or 0)
			expSum, actSum = expSum + e, actSum + a
			if not f.made and e > 0 and a / e < 0.95 then
				underpaid[#underpaid + 1] = fmt("#%d slot %d (%.0f%%, %s)",
					i, f.slot, a / e * 100, f.descentWhy or "never completed")
			end
		end
		w(fmt("descentHealth       %d/%d failed flights fully paid; realm total %.0f%% of intended",
			#launches - #underpaid, #launches, expSum > 0 and actSum / expSum * 100 or 100))
		w(fmt("underpaidFlights    %s", #underpaid > 0
			and (table.concat(underpaid, "; ") .. "   *** PACING IN THIS DUMP IS NOT TRUSTWORTHY ***")
			or "none -- every failed flight received its full ascent + descent"))
		w(fmt("sessionCoins        earned=%d  spent=%d  net=%+d  onHand=%d",
			math.floor(sessionEarn), math.floor(sessionSpend),
			math.floor(sessionEarn - sessionSpend), math.floor(coinsNow())))
		local inv = {}
		for name, qty in pairs(totalServings) do inv[#inv + 1] = fmt("%s x%d", name, qty) end
		table.sort(inv)
		w(fmt("servingsBought      %s", #inv > 0 and table.concat(inv, ", ") or "none"))
		w("")

		---------------------------------------------------------------- CONFIG
		-- THE CONFIG SECTION IS THE POINT OF THE WHOLE DUMP. Everything above is an
		-- observation, and an observation without the constants that produced it cannot be
		-- acted on. This realm has already lost a tuning pass to a debug line printing a
		-- stale COIN_PER_STUD next to live behaviour -- so these are read out of the LIVE
		-- modules at dump time, never re-typed.
		w("---------- SECTION 4: EXACT CONFIG USED THIS RUN ----------")
		w(fmt("FLIGHT_SECONDS      %.4f", FT.FLIGHT_SECONDS))
		w(fmt("TANK_SECONDS        %.4f", FT.TANK_SECONDS))
		w(fmt("DRAIN_RATE          %.4f gas/sec", FT.DRAIN_RATE))
		w(fmt("MARGIN              %.4f", FT.MARGIN))
		w(fmt("SPACING_SCALE       %.4f  (IslandOrder=%.4f)",
			FT.SPACING_SCALE, IO and IO.SPACING_SCALE or -1))
		w(fmt("COIN_PER_STUD_BASE  %.4f", FT.COIN_PER_STUD_BASE))
		w(fmt("COIN_PER_STUD used  %.4f  (= BASE / SPACING_SCALE)", COIN_PER_STUD))
		w(fmt("DESCENT_PAY_MULT    %.4f  (a repeated flight earns %.2fx the climb)",
			FT.DESCENT_PAY_MULT or 0, 1 + (FT.DESCENT_PAY_MULT or 0)))
		w(fmt("COURTESY_FRACTION   %.4f", FT.COURTESY_FRACTION))
		local sh = {}
		for _, v in ipairs(FT.SPEED_SHAPE) do sh[#sh + 1] = fmt("%.3f", v) end
		w(fmt("SPEED_SHAPE         [%s]  taper=%.3fx",
			table.concat(sh, ", "), FT.SPEED_SHAPE[#FT.SPEED_SHAPE] / FT.SPEED_SHAPE[1]))
		w("")
		w("GUT TIERS   idx  name              tank    climb    gap   cost  unlockSlot  R=eff*cps*(1+phi)*climb/tank")
		local cps = COIN_PER_STUD * (1 + (FT.DESCENT_PAY_MULT or 0))
		for i, t in ipairs(FT.TIERS) do
			if t.maxPower ~= math.huge then
				local st = ST and ST.LIST and ST.LIST[i]
				-- the food this tier's crossings actually buy = best value unlocked by then
				local eff = 0.1
				if FM then
					local slot = math.min(#FM.LIST, i * 2)
					for k = 1, slot do eff = math.max(eff, FM.LIST[k].power / FM.LIST[k].price) end
				end
				w(fmt("            %3d  %-16s %6d %7.0f %6.0f %6d %10d  %.3f",
					i, st and st.name or "?", t.maxPower, t.climb, t.gap,
					st and st.cost or -1, st and st.unlockSlot or -1,
					eff * cps * t.climb / t.maxPower))
			end
		end
		w("")
		w("FOOD        slot  name             price  power  power/coin  mult   island")
		if FM then
			local base = FM.LIST[1].power / FM.LIST[1].price
			for i, fd in ipairs(FM.LIST) do
				w(fmt("            %4d  %-16s %5d %6d      %.4f  %.2fx  island%d",
					i, fd.name, fd.price, fd.power, fd.power / fd.price,
					(fd.power / fd.price) / base, fd.island))
			end
		end
		w("")
		w("TOWER       slot  island  Y position   gap to next   name")
		if IO and IO.SLOT_POS then
			for s = 1, (IO.COUNT or #IO.SLOT_TO_ISLAND) do
				local p, nx = IO.SLOT_POS[s], IO.SLOT_POS[s + 1]
				local isl = IO.SLOT_TO_ISLAND[s]
				if p then
					w(fmt("            %4d  %6d  %10.1f  %12s   %s",
						s, isl or -1, p.Y, nx and fmt("%.0f", nx.Y - p.Y) or "(summit)",
						(IO.NAMES and IO.NAMES[isl]) or "?"))
				end
			end
			w(fmt("            SLOT_TO_ISLAND = {%s}", table.concat(IO.SLOT_TO_ISLAND, ", ")))
		end
		w("")
		w(fmt("ANTI-STRAND         grants exactly ONE serving of the local food (no crossing is 1 meal)"))
		w(fmt("DRIBBLE FLOOR       R * SPEED_SHAPE[1] must exceed 1.0 at every tier (see table above)"))
		w(fmt("STARTING COINS      500  (Shop.server)"))
		w(fmt("BUY MAX             best power/coin first, then one top-off of the cheapest affordable"))
		w("=== END PROGDATA RAW DUMP ===")
		print(table.concat(out, "\n"))
	end

	-- TWO TRIGGERS ON PURPOSE. The other dev commands in this game (/infinitegut, /2x) are
	-- SERVER-side, where Player.Chatted is reliable. This has to be client-side, and
	-- LocalPlayer.Chatted does NOT reliably fire under TextChatService -- the default chat
	-- now. F7 always works; /progdata is the convenience. If chat does nothing, press F7.
	player.Chatted:Connect(function(msg)
		if string.lower((string.gsub(msg, "%s", ""))) == "/progdata" then PROGDATA.dump() end
	end)
	UserInputService.InputBegan:Connect(function(input, typing)
		if typing then return end            -- never steal the key from a text box
		if input.KeyCode == Enum.KeyCode.F7 then PROGDATA.dump() end
	end)
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
			PROGDATA.onClimbPay(pay)
			lastCoinY = fhrp.Position.Y
			pcall(function() CoinEvent:FireServer(pay) end)
		end
	end
	if fhrp then PROGDATA.onLand(fhrp.Position.Y, currentPower) end
	isFlying = false; _G.isFlying = false; setFartLook(false)
	reportFuel() -- sync the burned fuel down to the server the moment thrust ends
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end; hrp.Anchored = false end
	-- ===== DAMP THE LEFTOVER UPWARD VELOCITY. THIS IS A GATE FIX, NOT A FEEL TWEAK. =====
	-- Destroying the BodyVelocity leaves the character with its full rise speed, so it coasts
	-- v^2/2g further on NO FUEL. That coast is free altitude, it scales with the SQUARE of
	-- speed, and at the top of the tower it was large enough to defeat the gut walls outright:
	--
	--        gut      full-tank climb  + free coast  = reach   gap it must NOT make
	--        Trike         1706            +36          1742        1740   <- skipped the Rex
	--        Rex           2370            +70          2440        2417   <- skipped the Titan
	--        Titan         3318           +137          3455        3384   <- skipped the Colossus
	--
	-- Three of the six gut purchases were optional. A playtest also crossed slot 8->9 on 14% of
	-- a Rex tank by chain-tapping, harvesting the coast a dozen times instead of buying fuel.
	--
	-- 0.4 on the velocity is 0.16 on the coast (it goes as v^2), which restores all three:
	--        Trike 1712 < 1740     Rex 2381 < 2417     Titan 3340 < 3384
	--
	-- WHY DAMPING AND NOT A FUEL CHARGE. Charging fuel for the coast was the other candidate and
	-- it does not fit: the 97.2%-of-tank crossings have only 17-49 fuel of headroom and the toll
	-- would need 13-70, which makes crossing 11 flatly impossible. Damping costs no fuel, so
	-- nothing became unreachable -- every `need` figure in FlightTuning already assumes ZERO
	-- coast, so this makes the game match the model rather than making anything harder.
	--
	-- Do not raise this back toward 1.0 to "restore the float" without re-checking those three
	-- gate rows; they are the whole reason it exists.
	if hrp then
		local v = hrp.AssemblyLinearVelocity
		if v.Y > 0 then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * COAST_DAMPING, v.Z)
		end
	end
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
	PROGDATA.onLaunch(hrp.Position.Y, currentPower, stomachMax)
	isFlying = true; _G.isFlying = true; setFartLook(true)
	-- fresh earnings window per flight; peakHeight only ever RISES within a flight,
	-- so the cap never shrinks once you start descending
	coinTimer, flightCoinsEarned = 0, 0
	lastCoinY = hrp.Position.Y            -- climb is billed from the launch altitude
	-- ===== A RE-TAP IN MID-AIR IS THE SAME TRIP, NOT A NEW ONE =====
	-- This block used to run unconditionally, which meant every chain-tap moved the fall-home
	-- floor UP to wherever you happened to be in the sky. The trip you were already owed for
	-- was thrown away and only the last burst could ever be paid, so a player who tapped four
	-- times on the way up climbed 2,374 studs, fell every one of them back, and collected 1.29
	-- coins/stud instead of 3.96 -- the exact "I went further and came back with less" report.
	--
	-- Still in the air with a trip open = the same wasted trip: inherit it, keep the paid-up-to
	-- floor and the peak, and let the apex rule settle each new arc on its own. NOT compared
	-- against the floor -- the floor ratchets up to the peak as arcs are paid, so a re-tap on
	-- the way down is legitimately BELOW it and would otherwise start a fresh trip whose base
	-- overlapped ground already paid for. The ratchet is what stops double payment; this test
	-- only has to answer "same trip or not".
	--
	-- Anything else -- standing on an island, a Return teleport, a respawn -- starts fresh, so
	-- a stale floor from another island can never leak into the next crossing. The altitude
	-- band is the belt-and-braces version of that: a trip you are genuinely still inside spans
	-- base..peak, and nothing that moves you elsewhere lands you inside it while airborne.
	--
	-- The test is ALTITUDE, not Humanoid.FloorMaterial. LandingStabilizer disables the tumble
	-- states, and a humanoid that never leaves Freefall keeps reporting FloorMaterial = Air
	-- while standing perfectly still on an island -- so "airborne" lied, a finished trip was
	-- inherited by the next launch, and the new flight started with its floor already up at
	-- the OLD flight's peak. Everything below that line then counted as pre-paid: measured at
	-- 1,290 coins for a 752-stud round trip against the 2,978 owed, and the give-away is that
	-- the shortfall was exactly the previous peak (654 studs) every time.
	--
	-- Height cannot lie. Back at the altitude you launched from = that trip is over.
	local y0   = hrp.Position.Y
	local home = descentBaseY ~= nil and y0 <= descentBaseY + 5
	local midTrip = descentFloorY ~= nil and descentBaseY ~= nil
		and not home
		and y0 > descentBaseY - 25 and y0 < descentPeakY + 25
	if not midTrip then
		descentFloorY, descentBaseY = hrp.Position.Y, hrp.Position.Y
		descentPeakY, descentArmed  = hrp.Position.Y, false
		descentStuds, descentWhy = 0, "in flight"
		descentGap = FlightTuning.gapFromSlot(
			math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1))
		-- Can this tank reach the island at all? If not, the fall home is already certain and
		-- gets paid out during the climb instead of as a lump at the apex (see PREPAY_SAFETY).
		local reach = FlightTuning.climbFor(stomachMax, currentPower)
		descentPrepay = (descentGap ~= nil) and (reach < descentGap * PREPAY_SAFETY)
	end
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

	-- ===== PAY THE FALL HOME =====
	-- Runs OUTSIDE the isFlying branch on purpose: the fall is what happens after thrust
	-- ends, so a payout that only ran while flying would never fire. Same tick cadence as
	-- the climb payout, so the two cannot disagree about the rate.
	--
	-- Paid strictly for ground already covered: only movement DOWNWARD, and only above the
	-- altitude you launched from. Diving off the summit therefore earns exactly what the
	-- climb before it earned and not one stud more.
	if DESCENT_MULT > 0 and descentFloorY then
		local y = hrp.Position.Y
		-- ONE payout routine, used by the apex trigger and the landing backstop alike, so the
		-- two can never disagree about the rate or double-count a stud. Paying always ratchets
		-- the floor up to the peak: that IS the record of what has been settled.
		local function settle(reason)
			local fell = descentPeakY - descentFloorY
			if fell > 0 and CoinEvent then
				local pay = fell * COIN_PER_STUD * DESCENT_MULT * (_G.serverEventCoinMult or 1)
				flightCoinsEarned = flightCoinsEarned + pay
				descentStuds = descentStuds + fell
				PROGDATA.onDescentPay(pay, fell)
				-- QUEUED, not paid: the drain below counts it out on the climb's own cadence.
				-- The multiplier is baked in HERE, at the moment the trip settles, so an event
				-- expiring mid-count cannot shrink a payout the player already earned.
				descentOwed = descentOwed + pay
				descentPayRate = descentOwed / PAYOUT_SECONDS
			end
			descentFloorY = descentPeakY        -- everything under here is now paid for
			descentWhy = reason
		end
		if not descentArmed then
			-- NOTHING IS OWED AND NOTHING CAN BE DISARMED until the player is clearly above
			-- where they launched. This is the guard that makes the payout immune to the
			-- launch-frame settle that killed it twice (see the note on DESCENT_ARM_HEIGHT).
			if y > descentBaseY + DESCENT_ARM_HEIGHT then
				descentArmed = true
				descentPeakY = y
			end
		else
			if y > descentPeakY then
				local rise = y - descentPeakY
				descentPeakY = y                                 -- still climbing; raise the mark
				-- PREPAY: settle this slice of the fall right now, at the same instant the climb
				-- payout bills the same stud. Ratcheting descentFloorY up with the peak IS the
				-- record that it has been settled, so settle() at the apex finds fell == 0 and
				-- there is no lump left to drop. Nothing else in the payout path changes.
				if descentPrepay and rise > 0 and CoinEvent then
					local pay = rise * COIN_PER_STUD * DESCENT_MULT * (_G.serverEventCoinMult or 1)
					flightCoinsEarned = flightCoinsEarned + pay
					descentStuds = descentStuds + rise
					PROGDATA.onDescentPay(pay, rise)
					descentOwed = descentOwed + pay
					descentPayRate = descentOwed / PAYOUT_SECONDS
					descentFloorY = descentPeakY
					descentWhy = "prepaid on the climb"
				end
			end
			-- ===== HEIGHT IS NOT A CROSSING. LANDING ON THE ISLAND IS. =====
			-- There was briefly a rule here that treated "peak reached the destination altitude"
			-- as a crossing for good, so a flight that overshot to 107% and then slid off the edge
			-- paid 1x and no lump. It is the wrong rule and it is deliberately gone: you have to
			-- MAKE the island. Fly up past it, miss it, and fall all the way home and that is a
			-- failed attempt like any other -- you did the whole round trip, you get the whole 3x.
			--
			-- The cost of this rule is real and known: a near-full-gap flight that slips off pays
			-- 3x a near-full-gap climb, which is more income than a normal attempt on that crossing,
			-- and enough of them in a row can bankroll the next crossing in one flight. The answer
			-- to that is to stop the slipping (see the sideways offsets in IslandOrder.SLOT_POS --
			-- crossing 4->5 asks for more lateral travel per stud of climb than any other), NOT to
			-- quietly stop paying for a trip the player actually flew.
			-- ===== PAY AT THE TOP OF THE ARC =====
			-- The instant you are falling AND back below APEX_PAY_SHARE of the gap, the outcome
			-- is settled: you cannot be on the next island, so this trip was wasted and the whole
			-- climb gets its 3x. No money arrives during the fall and none on touchdown.
			--
			-- The floor then ratchets to the peak. Tap again and climb higher and only the NEW
			-- altitude is owed, so chain-tapping pays each arc exactly once.
			local falling  = y < descentPeakY - APEX_DROP
			local homeward = descentGap and (y - descentBaseY) < descentGap * APEX_PAY_SHARE
			if falling and homeward and descentPeakY > descentFloorY then
				settle("complete -- paid at the top of the arc")
			end
			-- ===== CLOSE THE TRIP WHEN YOU GET HOME =====
			-- Nothing is normally owed by now; this is the backstop for a flight that ended
			-- without ever tripping the apex rule (clipped a ledge, got swatted, teleported).
			-- Two ways home, because FloorMaterial alone was not trustworthy (see startFlying):
			-- standing still on something, OR simply back down at the altitude you left from.
			local grounded = hum.FloorMaterial ~= Enum.Material.Air
				and hrp.AssemblyLinearVelocity.Y > -5
			if grounded or y <= descentBaseY + 5 then
				-- ===== DID YOU CROSS, OR ARE YOU BACK WHERE YOU STARTED? =====
				-- Compare against the GAP, never against the exact stud you launched from.
				-- Islands are not flat: an earlier build cancelled the entire payout when you
				-- touched down two studs higher on the same island, which cost a third of a
				-- flight's income on a coin-flip of where your feet landed -- the measured
				-- 1.31 coins/stud against the intended 3.95.
				-- WHERE YOUR FEET STOPPED, not how high you got. Land up here and you made it.
				local crossed = descentGap and (y - descentBaseY) >= descentGap * 0.75
				if crossed then
					-- CROSSED. No lump: a successful crossing earns 1x its climb where a failure
					-- earns 3x, and that ratio is the engine the whole 93-flight ladder runs on.
					descentWhy = "no lump -- crossed to the next island"
				elseif descentPeakY > descentFloorY then
					-- Still owed something, so the apex rule never fired. Pay down to where the
					-- feet actually stopped, never below what is already settled.
					descentPeakY = math.max(math.min(y, descentPeakY), descentFloorY)
					settle("complete -- paid on landing (apex rule never tripped)")
				end
				descentFloorY = nil
				PROGDATA.onDescentEnd(descentWhy)
			end
		end
	end

	-- ===== COUNT THE LUMP OUT =====
	-- Outside every branch on purpose: once coins are owed they get counted out no matter what
	-- the player does next -- land, re-tap, cross, die. Same COIN_TICK the climb uses, so the
	-- counter keeps the exact rhythm it had a moment ago instead of jumping in one frame.
	if descentOwed > 0 and CoinEvent then
		descentPayTick = descentPayTick + dt
		if descentPayTick >= COIN_TICK then
			descentPayTick = 0
			-- LINEAR, off the rate fixed when the lump was queued. Taking a share of what is
			-- LEFT each tick would decay instead of count, and never actually finish.
			local chunk = math.min(descentOwed, descentPayRate * COIN_TICK)
			if descentOwed - chunk < 1 then chunk = descentOwed end   -- no lingering pennies
			descentOwed = descentOwed - chunk
			pcall(function() CoinEvent:FireServer(chunk) end)
		end
	end

	-- FLIGHT LOCK -- a hazard has knocked the wind out of you and you cannot thrust until
	-- it expires. Set by Pterodactyls.client (a bird swats you out of the sky); read here
	-- the same way _G.windstormDir and _G.fireballKnock are.
	--
	-- IT MUST CALL stopFlying(), NOT JUST SKIP THE THRUST. stopFlying() is what flushes the
	-- climb coins and reports your remaining fuel to the server; leaving isFlying true and
	-- silently not moving would keep the meter draining while you fall, and would resume
	-- thrust mid-air the instant the lock lifted -- so a knockdown would barely cost you
	-- anything. This makes it a real interruption: you let go, you fall, you fly again when
	-- you have recovered.
	if _G.flightLockUntil and os.clock() < _G.flightLockUntil then
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end
		return
	end

	if isFlying and gasMeter > 0 then
		-- Primal Gut never drains -- thrust (and therefore earning) runs until you let go
		if not player:GetAttribute("HasPrimalGut") then
			-- SERVER EVENT gas modifier (_G.serverEventGasDrainMult, set by ServerEvents.client).
			-- LOW GRAVITY slows the burn so a tank lasts longer. 1 when no event is running.
			-- PER-GUT drain. Was the flat DRAIN_RATE, which burned every tank in the same
			-- 22.75 s; above the Raptor a tank now burns LONGER and the band speeds drop by
			-- the same factor, so the distance covered is identical and only the wall-clock
			-- moves. FlightTuning.TIER_TIME owns the factors and explains why.
			local drain = 100 / FlightTuning.tankSecondsFor(stomachMax)
			gasMeter = math.max(0, gasMeter - drain * dt * (_G.serverEventGasDrainMult or 1)) -- DRAIN
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
			PROGDATA.onClimbPay(pay)
				CoinEvent:FireServer(pay)
			end
		end
		-- Base ascent speed, scaled by any active flight modifier (e.g. Monsoon Rain's
		-- "wet conditions" sets _G.flightDistanceMultiplier = 0.9 for -10% flight distance).
		-- ...and by any active SERVER EVENT (FART STORM / POWER SURGE speed it up, LOW
		-- GRAVITY slows it while the drain modifier above makes the tank last). Both
		-- default to 1, so flight outside an event is bit-for-bit unchanged.
		local speed = getFlightSpeed(currentPower)
			* (_G.flightDistanceMultiplier or 1)
			* (_G.serverEventSpeedMult or 1)
			* (_G.serverEventHeightMult or 1)
		local move = hum.MoveDirection                             -- camera-relative steer
		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		-- WINDSTORM SHOVE -- ported from the first realm's CoreClient, same numbers.
		-- While a windstorm runs, a STRONG horizontal push is added along _G.windstormDir
		-- (set and re-aimed by Windstorm.client). 150 studs/sec against the 48 steering
		-- speed is roughly 3x, so you are genuinely knocked off course and have to fly
		-- into the wind to hold a line -- that ratio IS the event. Both terms are zero
		-- when no windstorm is running, so normal flight is bit-for-bit unchanged.
		local wpx, wpz = 0, 0
		if _G.windstormActive and _G.windstormDir then
			wpx = _G.windstormDir.X * 150
			wpz = _G.windstormDir.Z * 150
		end
		-- LIGHT thunderstorm buffet -- a soft varying push set by ServerEvents.client.
		-- Much gentler than the windstorm shove, and they stack if both are somehow live
		-- (same as the first realm's CoreClient, which is where this pair comes from).
		local tw = _G.thunderWindVec
		if tw then wpx = wpx + tw.X; wpz = wpz + tw.Z end
		-- VOLCANO FIREBALL KNOCKBACK -- set by VolcanoFireballs.client when one clips you on
		-- the last crossings, and decayed to nil by that script over ~0.7s. It rides this
		-- channel for the same reason the two above do: this loop rewrites bodyVel.Velocity
		-- every frame, so a shove applied directly to the character is erased before it can
		-- be seen. HORIZONTAL ONLY, on purpose -- the crossings clear their gaps with 8% to
		-- spare, and a downward shove would spend margin the top of the tower does not have.
		local fk = _G.fireballKnock
		if fk then wpx = wpx + fk.X; wpz = wpz + fk.Z end
		bodyVel.Velocity = Vector3.new(
			move.X * FLIGHT_HORIZONTAL_SPEED + wpx,
			speed,
			move.Z * FLIGHT_HORIZONTAL_SPEED + wpz
		)
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
