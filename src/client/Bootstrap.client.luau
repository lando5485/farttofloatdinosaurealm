--======================================================================
-- HUDClone.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of every always-on-screen HUD component from the main
-- game, ready to drop into a NEW world. Build order + exact sizes/positions/
-- colors/text are copied verbatim from CoreClient/SettingsMenu so it looks
-- identical. Components included:
--
--   1. CoinGui      -- top-right coin pill (icon + amount + "+" button)
--   2. SettingsGui  -- gear button (tucks left of the coins) + Music/SFX panel
--   3. RightPanelGui-- STATS panel on the RIGHT (Island/Max Height/Space Realm
--                      progress) + MID-AIR / 2X POWER / METEORITE EXPLOSION buttons
--   4. SidebarGui   -- LEFT-side buttons: SHOP / INVITE / Stomach / MORE
--
-- "Working" wiring is preserved but GUARDED: anything that needs the rest of
-- the game (shop menus, server remotes, leaderstats, player attributes) is
-- wrapped so it silently no-ops if those don't exist yet in the new world, and
-- starts working automatically the moment they're added. Drop this one script
-- into StarterPlayer > StarterPlayerScripts (or sync via Rojo) and it runs.
--======================================================================

local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService      = game:GetService("SocialService")
local SoundService       = game:GetService("SoundService")
local Workspace          = game:GetService("Workspace")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- HUD is authored at FULL size (scale = 1.0) on every device, exactly like the first realm. ALL
-- device fitting is done by ResponsiveUI.client.luau, which puts one UIScale per cluster =
-- getScale() x per-cluster extra. The extra (0.72/0.78, mobile-only) is set via the
-- ResponsiveExtraShrink attribute on each cluster frame below. Do NOT bake a mobile shrink here.
local scale    = 1.0

-- ===== GUI HELPERS (copied from CoreClient) =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== JUNGLE / CARTOON STYLE HELPERS =====
local JUNGLE_FONT = Enum.Font.FredokaOne
local LEAF_GREEN     = Color3.fromRGB(86, 170, 78)
local LEAF_GREEN_DK  = Color3.fromRGB(46, 110, 52)
local WOOD_DARK      = Color3.fromRGB(74, 48, 28)
local PARCHMENT      = Color3.fromRGB(232, 209, 158)
local CREAM          = Color3.fromRGB(248, 242, 222)

local function shade(c, f) return Color3.new(c.R * f, c.G * f, c.B * f) end
local function tint(c, f) return Color3.new(c.R + (1 - c.R) * f, c.G + (1 - c.G) * f, c.B + (1 - c.B) * f) end

-- Glossy top highlight gradient (lighter at the top, base toward the bottom).
local function glossGradient(parent, baseCol)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tint(baseCol, 0.45)),
		ColorSequenceKeypoint.new(0.5, baseCol),
		ColorSequenceKeypoint.new(1, shade(baseCol, 0.82)),
	})
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Bold rounded white text with a dark outline (the shared cartoon text token).
local function styleText(lbl)
	lbl.Font = JUNGLE_FONT
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	return lbl
end

-- Drop shadows removed from the HUD per request (buttons, stats panel, coin pill, etc.).
-- Kept as a no-op stub so every existing addShadow(...) call site still works; to restore the
-- soft shadow, put back the offset dark rounded frame that used to live here.
local function addShadow(frame, corner)
	return nil
end

-- A small cartoon leaf (rounded ellipse) tucked into a corner, overlapping the border.
local function addLeaf(parent, pos, rot, size, z)
	local leaf = Instance.new("Frame")
	leaf.Name = "Leaf"
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = pos
	leaf.Size = UDim2.fromOffset(size, math.floor(size * 0.6))
	leaf.Rotation = rot
	leaf.BackgroundColor3 = LEAF_GREEN
	leaf.BorderSizePixel = 0
	leaf.ZIndex = z or 12
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(1, 0); lc.Parent = leaf
	local ls = Instance.new("UIStroke"); ls.Color = LEAF_GREEN_DK; ls.Thickness = 1.5; ls.Parent = leaf
	glossGradient(leaf, LEAF_GREEN)
	leaf.Parent = parent
	return leaf
end

-- Cream circular icon badge holding an icon (text/emoji). Returns the badge frame.
local function addIconBadge(parent, diameter, posScaleY, iconText, iconSize)
	local badge = Instance.new("Frame")
	badge.Name = "IconBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, posScaleY, 0)
	badge.Size = UDim2.fromOffset(diameter, diameter)
	badge.BackgroundColor3 = CREAM
	badge.BorderSizePixel = 0
	badge.ZIndex = 6
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = badge
	local s = Instance.new("UIStroke"); s.Color = WOOD_DARK; s.Thickness = 2; s.Parent = badge
	-- Flat, very slightly top-lit. The old version stacked a strong gradient PLUS a
	-- second inset "Rim" frame with a semi-transparent brown stroke -- two concentric
	-- rings a couple of pixels apart, which is what read as a rough, dirty edge on a
	-- 44px circle. One clean fill and one clean outline instead.
	do
		local bg = Instance.new("UIGradient"); bg.Rotation = 90
		bg.Color = ColorSequence.new(tint(CREAM, 0.15), CREAM); bg.Parent = badge
	end
	if iconText and iconText ~= "" then
		if iconText == "+" then
			-- Drawn as two rounded bars rather than a font "+".
			-- The other three glyphs are colour-emoji, which the engine renders from a
			-- bitmap font at a fixed design size; a text "+" comes from the UI font and
			-- lands visually much smaller and thinner beside them. Two bars match their
			-- weight exactly and stay crisp at any scale.
			local g = math.max(2, math.floor(diameter * 0.075))  -- bar thickness
			local L = math.floor(diameter * 0.46)                -- bar length
			for _, dims in ipairs({ { L, g }, { g, L } }) do
				local bar = Instance.new("Frame")
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.fromScale(0.5, 0.5)
				bar.Size = UDim2.fromOffset(dims[1], dims[2])
				bar.BackgroundColor3 = Color3.fromRGB(38, 30, 20)
				bar.BorderSizePixel = 0
				bar.ZIndex = 7
				local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, math.floor(g / 2)); bc.Parent = bar
				bar.Parent = badge
			end
		else
			local il = Instance.new("TextLabel")
			il.BackgroundTransparency = 1
			-- Full-bleed box with both axes centred, so every glyph is measured against the
			-- same square and lands on the same optical centre regardless of its own metrics.
			il.Size = UDim2.fromScale(1, 1)
			il.TextXAlignment = Enum.TextXAlignment.Center
			il.TextYAlignment = Enum.TextYAlignment.Center
			il.Text = iconText
			il.Font = JUNGLE_FONT
			il.TextScaled = false
			il.TextSize = iconSize or math.floor(diameter * 0.55)
			-- hard cap so a taller emoji can never render bigger than its neighbours
			local tc = Instance.new("UITextSizeConstraint")
			tc.MaxTextSize = il.TextSize; tc.Parent = il
			il.TextColor3 = Color3.fromRGB(38, 30, 20)
			il.ZIndex = 7
			il.Parent = badge
		end
	end
	badge.Parent = parent
	return badge
end

-- ===== LUSH FOLIAGE + PREMIUM DETAIL HELPERS =====
local LEAF_LIGHT = Color3.fromRGB(120, 196, 96)
local LEAF_MED   = Color3.fromRGB(78, 158, 72)
local LEAF_DK    = Color3.fromRGB(46, 110, 52)
local LEAF_LINE  = Color3.fromRGB(33, 84, 40)

-- One cartoon leaf: rounded ellipse, dark outline, subtle top-lit gradient.
local function makeLeaf(parent, pos, rot, w, col, z)
	local lf = Instance.new("Frame")
	lf.Name = "Leaf"; lf.AnchorPoint = Vector2.new(0.5, 0.5); lf.Position = pos
	lf.Size = UDim2.fromOffset(w, math.max(4, math.floor(w * 0.55))); lf.Rotation = rot
	lf.BackgroundColor3 = col; lf.BorderSizePixel = 0; lf.ZIndex = z
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = lf
	local s = Instance.new("UIStroke"); s.Color = LEAF_LINE; s.Thickness = 1.5; s.Parent = lf
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(tint(col, 0.3), shade(col, 0.85)); g.Parent = lf
	lf.Parent = parent
	return lf
end

-- A lush cluster of 4 overlapping leaves (dark/back -> light/front) reclaiming a
-- corner. dx/dy (+/-1) flare the cluster inward from that corner.
local function addLeafCluster(parent, base, dx, dy, sz, z)
	z = z or 12
	makeLeaf(parent, base + UDim2.fromOffset(0, 0),                       12 * dx, math.floor(sz * 1.3),  LEAF_DK,    z)
	makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.6, dy * sz * 0.1), 48 * dx, math.floor(sz * 1.05), LEAF_MED,   z + 1)
	makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.15, dy * sz * 0.55), -32 * dx, math.floor(sz * 0.95), LEAF_MED,   z + 1)
	makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.45, dy * sz * 0.4),  16 * dx, math.floor(sz * 0.7),  LEAF_LIGHT, z + 2)
end

-- A thin vine/branch running down an edge with a couple of small leaves on it.
local function addVine(parent, x, y, length, z)
	z = z or 11
	local v = Instance.new("Frame"); v.Name = "Vine"; v.AnchorPoint = Vector2.new(0.5, 0)
	v.Position = UDim2.new(0, x, 0, y); v.Size = UDim2.fromOffset(3, length)
	v.BackgroundColor3 = Color3.fromRGB(74, 116, 54); v.BorderSizePixel = 0; v.ZIndex = z
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = v
	local s = Instance.new("UIStroke"); s.Color = LEAF_LINE; s.Thickness = 1; s.Parent = v
	v.Parent = parent
	makeLeaf(parent, UDim2.new(0, x + 2, 0, y + math.floor(length * 0.35)), -55, 12, LEAF_MED, z + 1)
	makeLeaf(parent, UDim2.new(0, x + 2, 0, y + math.floor(length * 0.65)), 60, 10, LEAF_LIGHT, z + 1)
end

-- Faint white inner highlight line just inside the border (premium bevel).
local function addInnerHighlight(frame, corner)
	local hl = Instance.new("Frame"); hl.Name = "InnerHighlight"
	hl.AnchorPoint = Vector2.new(0.5, 0.5); hl.Position = UDim2.fromScale(0.5, 0.5)
	hl.Size = UDim2.new(1, -6, 1, -6); hl.BackgroundTransparency = 1; hl.ZIndex = (frame.ZIndex or 1) + 1
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, math.max(2, (corner or 16) - 3)); c.Parent = hl
	local s = Instance.new("UIStroke"); s.Color = Color3.new(1, 1, 1); s.Transparency = 0.72; s.Thickness = 1.5; s.Parent = hl
	hl.Parent = frame; return hl
end

-- Subtle inner glow in the element's own color (stronger toward top/bottom).
local function addInnerGlow(frame, col, corner)
	local gl = Instance.new("Frame"); gl.Name = "InnerGlow"
	gl.AnchorPoint = Vector2.new(0.5, 0.5); gl.Position = UDim2.fromScale(0.5, 0.5)
	gl.Size = UDim2.new(1, -4, 1, -4); gl.BackgroundColor3 = tint(col, 0.55); gl.BorderSizePixel = 0
	gl.ZIndex = (frame.ZIndex or 1)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, math.max(2, (corner or 12) - 2)); c.Parent = gl
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.45, 0.88),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	g.Parent = gl
	gl.Parent = frame; return gl
end

-- A trailing vine draping a corner: soft shadow, a curved twin-segment stem,
-- leaves sprouting along it in 3 greens, a draping tip past the edge, and a
-- highlight on the top leaf. dx/dy (+/-1) flare it inward from the corner.
local function addVineCorner(parent, base, dx, dy, sz, z)
	z = z or 12
	-- soft shadow blob behind the foliage
	local sh = makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.3 + 2, dy * sz * 0.3 + 2), 20 * dx, math.floor(sz * 1.4), Color3.new(0, 0, 0), z - 1)
	sh.BackgroundTransparency = 0.6
	local shStroke = sh:FindFirstChildOfClass("UIStroke"); if shStroke then shStroke.Enabled = false end
	-- curved stem (two angled rounded segments)
	local function stem(off, rot, len)
		local s = Instance.new("Frame"); s.Name = "VineStem"; s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = base + off; s.Size = UDim2.fromOffset(3, len); s.Rotation = rot
		s.BackgroundColor3 = Color3.fromRGB(74, 116, 54); s.BorderSizePixel = 0; s.ZIndex = z
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = s
		local st = Instance.new("UIStroke"); st.Color = LEAF_LINE; st.Thickness = 1; st.Parent = s
		s.Parent = parent
	end
	stem(UDim2.fromOffset(dx * sz * 0.2, dy * sz * 0.25), 35 * dx, math.floor(sz * 1.6))
	stem(UDim2.fromOffset(dx * sz * 0.7, dy * sz * 0.65), 78 * dx, math.floor(sz * 1.25))
	-- leaves along the vine (the first drapes past the corner over the border)
	makeLeaf(parent, base + UDim2.fromOffset(-dx * sz * 0.22, -dy * sz * 0.22), 12 * dx, math.floor(sz * 1.1), LEAF_DK,  z + 1)
	makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.55, dy * sz * 0.18),   48 * dx, math.floor(sz * 1.0), LEAF_MED, z + 2)
	makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.2,  dy * sz * 0.62),  -34 * dx, math.floor(sz * 0.9), LEAF_MED, z + 2)
	local tip = makeLeaf(parent, base + UDim2.fromOffset(dx * sz * 0.55, dy * sz * 0.5), 16 * dx, math.floor(sz * 0.7), LEAF_LIGHT, z + 3)
	-- highlight on the top leaf
	local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5, 0.5)
	hl.Position = UDim2.fromScale(0.4, 0.38); hl.Size = UDim2.fromScale(0.34, 0.24)
	hl.BackgroundColor3 = Color3.new(1, 1, 1); hl.BackgroundTransparency = 0.5; hl.BorderSizePixel = 0; hl.ZIndex = z + 4
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(1, 0); hc.Parent = hl
	hl.Parent = tip
end

-- ===== SHARED IMAGE ASSETS (from CoreClient) =====
_G.COIN_IMAGE = _G.COIN_IMAGE or "rbxassetid://106760789458573" -- gold coin icon
_G.GUT_IMAGE  = _G.GUT_IMAGE  or "rbxassetid://108585083746103" -- stomach/gut icon

-- ===== UI CLICK SOUND (self-contained) =====
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound_HUDClone"
uiClickSound.SoundId = "rbxassetid://101638558691673"
uiClickSound.Volume = 0.5
uiClickSound.Parent = PlayerGui
local function playUIClick()
	local s = uiClickSound:Clone()
	s.Parent = PlayerGui
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (ported verbatim from CoreClient) =====
-- A tiny shared manager (ONE instance across all client scripts, via _G) so only ONE main menu
-- (premium shop / stomach shop) is open at a time. Opening any registered menu first CLOSES whichever
-- other is open. Guarded so whichever client script loads first creates it and the rest reuse it.
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end          -- each menu provides a full-hide fn
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD if this world has one
		local lp = game:GetService("Players").LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end                                       -- no-op if this world has no bottom HUD yet
	end
	function mgr.notifyOpened(name)                                             -- call right BEFORE showing a menu
		if mgr.current and mgr.current ~= name then
			local h = mgr.hiders[mgr.current]; if h then pcall(h) end           -- fully close the other open menu
		end
		mgr.current = name
		mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
-- toggle an Enabled-driven menu through the manager (open => first close any other; close => clear current)
local function toggleMainMenu(name, guiName)
	local g = PlayerGui:FindFirstChild(guiName); if not g then return end       -- menu not present in this world yet
	if g.Enabled then
		g.Enabled = false; _G.MainMenuManager.notifyClosed(name)
	else
		_G.MainMenuManager.notifyOpened(name)                                   -- direct switch: closes any other open main menu first
		g.Enabled = true
	end
end
_G.MainMenuManager.register("Premium", function() local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=false end end)
_G.MainMenuManager.register("Stomach", function() local g=PlayerGui:FindFirstChild("StomachShopGui"); if g then g.Enabled=false end end)

-- forward-declared so the MORE+ side button (built below) can toggle the popup that's built later in this script
local setMoreOpen
local moreOpenState = false

--======================================================================
-- 1) TOP-RIGHT: THE CURRENCY BAR  (CoinGui)
--======================================================================
-- TWO SEPARATE OBJECTS, and the separation is the point:
--   * a STANDALONE rounded-square settings button on the left, and
--   * a single capsule holding the token and coin sections, which run straight into each
--     other with no gap, no divider and no seam.
-- SET_GAP of clear air sits between them. The button is a sibling of the capsule, never a
-- section inside it, so no change to the capsule's interior can pull it back in.
--
-- THE NESTING, and why each level exists:
--   barRoot        -- transparent, draws nothing, spans BOTH objects. It is the
--                     ScreenGui's only top-level child, so ResponsiveUI hangs exactly one
--                     UIScale here and the button and the capsule can never scale apart.
--     settingsRoot -- shadow stack + the button face.
--     capsuleRoot  -- shadow stack + the capsule frame.
--       bar        -- the dark frame. Thin (BORDER), because the two colours are meant to
--                     carry this, not the border around them.
--         inner    -- rounded AND clipping. This is what makes the capsule continuous:
--                     the sections inside are plain rectangles that abut, and the clip
--                     supplies the round ends they do not have.
--======================================================================
-- SUPERSEDED BY CurrencyCapsule.client.luau
--======================================================================
-- The token/coin capsule below is NO LONGER SHOWN. CurrencyCapsuleGui draws the currency
-- HUD now: a self-contained, CONFIG-driven component that reads leaderstats.Coins and
-- _G.crateTokenBalance and owns its own layout.
--
-- The ScreenGui is DISABLED rather than the code deleted, for two reasons:
--   1. the settings button is built inside this tree (settingsRoot -> settingsSlot ->
--      gearBtn) and has to survive; it is reparented out to SettingsGui further down
--   2. everything here -- the pill geometry, the fills, the "+" buttons, the coin value
--      watcher -- is one interlocked block roughly 500 lines long, and unpicking it
--      blind is how you lose the gear or the settings panel's anchor with it
-- Disabled costs one hidden ScreenGui. Deleting it can wait for a pass that can be tested.
local coinGui = Instance.new("ScreenGui")
coinGui.Name = "CoinGui"; coinGui.ResetOnSpawn = false; coinGui.IgnoreGuiInset = true; coinGui.Parent = PlayerGui
coinGui.Enabled = false -- CurrencyCapsuleGui replaces it; see the note above

-- Design units at scale 1.0. Every measurement below derives from these four, so the
-- proportions hold at any size -- there are no independent magic numbers to re-tune.
-- TWO SEPARATE OBJECTS, not one bar. The settings button is a standalone rounded button
-- with a gap after it; the token and coin sections share ONE capsule, each on its own
-- solid colour, parted by a crisp divider rather than a gap. Sizes below reflect that.
local CAP_H     = 58                      -- the currency capsule
local BORDER    = 4                       -- frame thickness. Thin: the colour should carry
-- Sized off the TOKEN section, which is the constraint. The icon and the "+" eat a fixed
-- SEC_H - 10 between them whatever the padding is, so the balance gets (width - 90) to
-- live in -- and at 40% of a narrower capsule that came out at 34px, which scales "1,250"
-- down to nearly half the coin balance beside it. 348 gives the token number 46px.
local CAP_W     = 348
local SEC_H     = CAP_H - BORDER * 2      -- 50 -- the interior is most of the capsule
local INNER_W   = CAP_W - BORDER * 2      -- 340
local CAP_R     = math.floor(CAP_H / 2)   -- fully rounded: a capsule, never a rounded rect
local INNER_R   = CAP_R - BORDER          -- the interior follows the outer curve exactly

-- 40 / 60. The two currencies are NOT two panels -- they are two zones of ONE fill, and
-- these are the widths their icons, numbers and buttons are laid out against.
local TOKEN_FRAC = 0.40
local TOKEN_W    = math.floor(INNER_W * TOKEN_FRAC) -- 136
local COIN_W     = INNER_W - TOKEN_W                -- 204: the remainder, so the two zones
                                                    -- always sum to the interior exactly
-- The colour change between the two zones is a STEP, not a fade. This is the width of
-- that step as a fraction of the interior: 0.001 of 340px is a third of a pixel, so the
-- two colours meet on a hard edge. ColorSequence will not take two keypoints at the same
-- offset, which is the only reason this is not simply zero.
local STEP       = 0.001

local SET_SIZE = 56                      -- the standalone settings button
local SET_GAP  = 10                      -- clear air between it and the capsule
local SET_R    = 22                      -- thick rounded square, NOT a capsule
local TOTAL_W  = SET_SIZE + SET_GAP + CAP_W

local SET_NAVY   = Color3.fromRGB(38, 48, 76) -- top of the button's vertical gradient
local SET_NAVY_D = Color3.fromRGB(20, 27, 46) -- bottom
local GEAR_GREY  = Color3.fromRGB(202, 209, 221)

-- Reference palette. The frame is near-black navy, the token section a DEEP navy (the red
-- belongs to the ticket icon alone, never the panel behind it) and the coin section a warm,
-- fairly DESATURATED orange -- a fully saturated orange is what reads as toy plastic. The
-- one colour that is not the reference's is the bronze, which is a hairline and barely
-- separable from the frame at rest.
local FRAME_DARK  = Color3.fromRGB(24, 29, 43)   -- capsule + settings button
local FRAME_EDGE  = Color3.fromRGB(10, 13, 20)   -- dark outer border
local BRONZE      = Color3.fromRGB(146, 108, 62) -- weathered inner border
local TICKET_NAVY = Color3.fromRGB(28, 37, 62)   -- deepened
local COIN_ORANGE = Color3.fromRGB(230, 160, 88) -- desaturated from a hot 240,149,45
local PLUS_WHITE  = Color3.fromRGB(249, 250, 252)

-- Layered soft shadow. The shared addShadow() above is a deliberate no-op -- drop shadows
-- were pulled from this HUD -- so the bar carries its own rather than reviving that stub
-- and putting shadows back under every other element in the game.
local function addBarShadow(parent, radius)
	for i = 3, 1, -1 do -- widest and faintest first, so the stack reads as one soft falloff
		local grow = i * 3
		local sh = mkFrame(parent, {
			Name = "Shadow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, i * 2),
			Size = UDim2.new(1, grow, 1, grow),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.62 + i * 0.10,
			BorderSizePixel = 0,
			ZIndex = 1,
		})
		mkCorner(sh, radius + math.floor(grow / 2))
	end
end

-- A pod sits DOWN in the frame, so its fill darkens toward the top -- the opposite of
-- glossGradient(), which lights the top for something raised. Paired with the inner
-- shadow below it reads as recessed without any bevel or highlight ridge.
-- NOTE: there is no per-section shading helper any more. The interior's colour comes from
-- ONE horizontal cross-fade gradient, and its lighting from two overlays spanning the
-- whole capsule -- see the fill below. A vertical shading gradient applied per section is
-- what the split used to be made of.

-- NOTE: the fossil engravings that used to live here were dropped along with the thick
-- frame. At BORDER = 4 the only stone still visible is a 4px rim, and an engraving that
-- small is either invisible or, if pushed dark enough to read, a smudge on the outline.
-- The prehistoric mark that survived the slimming is the bronze inner hairline.

-- barRoot spans BOTH objects, so ResponsiveUI still hangs exactly one UIScale and the
-- button and the capsule can never scale apart from each other. It draws nothing itself.
local barRoot = mkFrame(coinGui, {
	Name = "CurrencyBar",
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.new(0, math.floor(TOTAL_W * scale), 0, math.floor(CAP_H * scale)),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	ClipsDescendants = false,
	ZIndex = 3,
})
barRoot:SetAttribute("ResponsiveExtraShrink", 0.78)  -- first-realm CoinGui cluster extra (mobile-only, applied by ResponsiveUI)

--------------------------------------------------------------------
-- THE SETTINGS BUTTON -- standalone, and deliberately NOT in the capsule
--------------------------------------------------------------------
-- Its own frame, its own shadow, its own border, separated by SET_GAP. It is a sibling
-- of the capsule rather than a section inside it, so nothing about the capsule's layout
-- can ever pull it in.
local settingsRoot = mkFrame(barRoot, {
	Name = "SettingsButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(SET_SIZE, SET_SIZE),
	BackgroundTransparency = 1,
	ZIndex = 3,
})
addBarShadow(settingsRoot, SET_R)
local settingsSlot = mkFrame(settingsRoot, {
	Name = "Face",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = SET_NAVY,
	BorderSizePixel = 0,
	ZIndex = 4,
})
mkCorner(settingsSlot, SET_R)
mkStroke(settingsSlot, FRAME_EDGE, 2)
do -- deep navy -> dark blue, straight down. This is the one place a gradient is meant to
	-- be read as a gradient rather than as ambient light.
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(SET_NAVY, SET_NAVY_D)
	g.Parent = settingsSlot
end
do -- subtle lighter inner border, one step in from the dark outer frame
	local hl = addInnerHighlight(settingsSlot, SET_R)
	local s = hl:FindFirstChildOfClass("UIStroke")
	if s then s.Color = Color3.fromRGB(150, 170, 205); s.Transparency = 0.62; s.Thickness = 1.5 end
end
do -- INSET, not glossy: a soft dark wash inside the top edge, no highlight ridge
	local ins = mkFrame(settingsSlot, { Name = "InnerShadow", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 4 })
	mkCorner(ins, SET_R)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.74), NumberSequenceKeypoint.new(0.38, 1), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = ins
end

--------------------------------------------------------------------
-- THE CURRENCY CAPSULE -- token and coin, one continuous container
--------------------------------------------------------------------
local capsuleRoot = mkFrame(barRoot, {
	Name = "Capsule",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(CAP_W, CAP_H),
	BackgroundTransparency = 1,
	ZIndex = 3,
})
addBarShadow(capsuleRoot, CAP_R)

local bar = mkFrame(capsuleRoot, {
	Name = "Frame",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = FRAME_DARK,
	BorderSizePixel = 0,
	ZIndex = 4,
})
mkCorner(bar, CAP_R)
mkStroke(bar, FRAME_EDGE, 2) -- thinner than before: the colour carries the bar, not the frame
do -- the subtle inner border, a hairline inside the dark outer one. Weathered bronze
	-- rather than white -- and this hairline is now the ONLY prehistoric mark on the
	-- capsule, because a 4px frame has no room for carved detail that would still read.
	local hl = addInnerHighlight(bar, CAP_R)
	local s = hl:FindFirstChildOfClass("UIStroke")
	if s then s.Color = BRONZE; s.Transparency = 0.6; s.Thickness = 1 end
end
do -- soft gradient only: barely lighter along the top so it reads as lit from above
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Color = ColorSequence.new(tint(FRAME_DARK, 0.10), shade(FRAME_DARK, 0.84))
	g.Parent = bar
end
do -- gentle top-edge highlight, faded at both ends so it doesn't stop in two hard dots
	local top = mkFrame(bar, { Name = "TopEdge", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.new(1, -34, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.84, BorderSizePixel = 0, ZIndex = 7 })
	mkCorner(top, 1)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = top
end

-- VINES: much smaller, and BEHIND the capsule rather than laid over it. ZIndex 2 puts
-- them under the frame (4) and under the shadow, so all that shows is the tip of a
-- tendril past the outer edge -- the frame hides where it comes from. They hang off
-- capsuleRoot because the capsule itself has no room to spare at a 4px border.
local function tuckVine(xScale, dir, len)
	local stem = mkFrame(capsuleRoot, {
		Name = "BorderVine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(xScale, 0, dir > 0 and 1 or 0, dir * -2),
		Size = UDim2.fromOffset(len, 2),
		Rotation = dir > 0 and 10 or -10,
		BackgroundColor3 = Color3.fromRGB(72, 108, 54),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 2, -- BEHIND the capsule frame: only the tip clears the edge
	})
	mkCorner(stem, 99)
	makeLeaf(capsuleRoot, UDim2.new(xScale, math.floor(len * 0.34), dir > 0 and 1 or 0, dir * 2), 46 * dir, 6, LEAF_MED, 2)
	makeLeaf(capsuleRoot, UDim2.new(xScale, -math.floor(len * 0.30), dir > 0 and 1 or 0, dir * 1), -42 * dir, 5, LEAF_LIGHT, 2)
end
-- Foliage removed (both calls). Doubly dead now -- this whole capsule lives in the
-- disabled CoinGui that CurrencyCapsule replaced -- but the calls went with the rest of
-- the leaf accents so nothing re-renders them if that GUI is ever switched back on.

-- THE INTERIOR: one rounded surface, INNER_R, which is the outer capsule's radius less
-- the border -- so the inside curve is exactly concentric with the outside one rather
-- than merely close to it.
--
-- The fill inside is rounded in its own right rather than relying on this frame's clip to
-- shape it: ClipsDescendants clips to the rectangle, and whether it honours a UICorner is
-- not something to bet the capsule's outline on. The clip stays as a backstop; the fill
-- fits it exactly, so it removes nothing.
local inner = mkFrame(bar, {
	Name = "Inner",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -BORDER * 2, 1, -BORDER * 2),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 5,
})
mkCorner(inner, INNER_R)

-- ONE FILL OBJECT carrying TWO SOLID COLOURS that meet on a hard edge. Each zone is a
-- flat, unmixed colour -- there is no blending anywhere between them.
--
-- Why one object rather than two abutting frames: the interior has to stay a single
-- rounded shape. Two frames each need their own UICorner, which rounds their INNER
-- corners as well as their outer ones and cuts a notch down the middle of the capsule;
-- squaring that back off takes an extra patch per side. One frame is rounded once, and a
-- hard-stepped gradient puts the colour boundary exactly where it belongs.
--
-- BackgroundColor3 is white on purpose: UIGradient MULTIPLIES the background colour, so a
-- white base lets the gradient state both colours exactly rather than tinting them.
local fill = mkFrame(inner, {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 5,
})
mkCorner(fill, INNER_R) -- the interior's own curve, following the outer capsule exactly
local EDGE_FRAC = TOKEN_W / INNER_W -- where the two currencies meet, as a fraction
do
	local g = Instance.new("UIGradient")
	g.Rotation = 0 -- horizontal: this gradient carries COLOUR, not lighting
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, TICKET_NAVY),
		ColorSequenceKeypoint.new(EDGE_FRAC - STEP, TICKET_NAVY), -- solid navy right up to the edge
		ColorSequenceKeypoint.new(EDGE_FRAC, COIN_ORANGE),        -- and solid amber from it
		ColorSequenceKeypoint.new(1, COIN_ORANGE),
	})
	g.Parent = fill
end

-- The lighting is layered ON TOP of the colour rather than mixed into it, because an
-- object gets exactly one UIGradient and the fill has spent its own stating the two
-- colours. Both of these span the WHOLE interior, and that is deliberate: the capsule is
-- one component with two zones in it, so the light running across it has to be continuous
-- even though the colour underneath it steps. Shading each zone separately would put a
-- second, softer seam beside the crisp one.
do -- SOFT INNER SHADOW: a dark wash inside the top edge. Sets the interior back.
	local ins = mkFrame(inner, { Name = "InnerShadow", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 6 })
	mkCorner(ins, INNER_R)
	local g = Instance.new("UIGradient"); g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(0.34, 1), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = ins
end
do -- SUBTLE TOP HIGHLIGHT: one hairline just inside the interior's top edge, running the
	-- full width and fading out at both ends so it never terminates in two hard dots.
	local gloss = mkFrame(inner, { Name = "TopGloss", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.new(1, -INNER_R, 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72,
		BorderSizePixel = 0, ZIndex = 7 })
	mkCorner(gloss, 1)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = gloss
end

do -- THE DIVIDER: a crisp vertical line on the colour boundary, full interior height.
	--
	-- TWO hairlines, not one. A single dark line reads as a line drawn ON the surface; a
	-- dark line with a faint light one immediately to its right reads as a groove cut
	-- INTO it, which is the inset the reference uses. Both are kept low-contrast -- the
	-- divider's job is to separate the two colours, not to become a third element.
	--
	-- It sits at ZIndex 7, above the fill and the inner shadow but below the content (8).
	-- Nothing overlaps it either way: the icons and numbers live inside their own zones,
	-- and this falls exactly between them.
	-- the dark side, ending ON the boundary
	mkFrame(inner, {
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(EDGE_FRAC, 0, 0, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 16),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 7,
	})
	-- the lit side, starting ON the boundary
	mkFrame(inner, {
		Name = "DividerLight",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(EDGE_FRAC, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = 7,
	})
end

-- ONE factory for both currencies, so there is no second copy of the layout to drift.
-- The factory no longer builds any colour: the fill above already covers both currencies
-- as one surface. All this lays out is a transparent CONTENT ZONE -- icon, number, "+" --
-- over its share of that fill.
--
-- The zone sits at ZIndex 8, above the inner shadow (6) and the top gloss (7), so the
-- capsule-wide lighting passes UNDER the icons and numbers instead of over them. Under
-- Sibling ZIndex an overlay outranks a sibling's entire subtree, so content nested inside
-- a coloured fill would be washed over by anything layered above that fill.
local function makeCurrencySection(xOffset, width, baseCol, onPlus)
	local pod = mkFrame(inner, {
		Name = "Content",
		Position = UDim2.fromOffset(xOffset, 0),
		Size = UDim2.new(0, width, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 8,
	})

	-- PADDING. One number, applied to the icon's left inset, the "+"'s right inset and the
	-- air on both sides of the number, so the content sits in a consistent margin instead
	-- of three insets that happen to look similar.
	local PAD = 8

	-- ICON: sits directly on the fill, vertically centred. No badge disc behind it -- the
	-- reference puts the bare icon on the colour, and a disc under it reads as a busier bar.
	-- Sized off the padding rather than off SEC_H, so widening the margin shrinks the icon
	-- with it and the vertical air above and below always matches the air at the left.
	local ICON_D = SEC_H - PAD * 2
	local iconHolder = mkFrame(pod, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD, 0.5, 0),
		Size = UDim2.fromOffset(ICON_D, ICON_D),
		BackgroundTransparency = 1,
		ZIndex = 8,
	})

	-- "+": small WHITE disc against the right, on the same margin as the icon. Deliberately
	-- smaller than the icon -- it is a control, and it must not compete with the value.
	local PLUS_D = SEC_H - PAD * 2 - 10
	local plus = mkButton(pod, {
		Name = "Plus",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PAD, 0.5, 0),
		Size = UDim2.fromOffset(PLUS_D, PLUS_D),
		BackgroundColor3 = PLUS_WHITE,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
	})
	mkCorner(plus, 999)
	do -- the faintest shading, top-lit. A white disc with a hard gradient is exactly the
		-- glossy-plastic read the reference avoids.
		local g = Instance.new("UIGradient"); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.new(1, 1, 1), shade(PLUS_WHITE, 0.94)); g.Parent = plus
	end
	do -- the "+" as two rounded bars, not a font glyph. A text "+" comes from the UI font
		-- and lands visibly thinner and smaller than the icon beside it (same reasoning as
		-- addIconBadge above); two bars match its weight and stay crisp at any scale. Cut
		-- in the section's own darkened colour, so each "+" belongs to its section.
		local g = math.max(2, math.floor(PLUS_D * 0.15))
		local L = math.floor(PLUS_D * 0.48)
		for _, dims in ipairs({ { L, g }, { g, L } }) do
			local barPiece = mkFrame(plus, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(dims[1], dims[2]), BackgroundColor3 = shade(baseCol, 0.72),
				BorderSizePixel = 0, ZIndex = 9 })
			mkCorner(barPiece, math.floor(g / 2))
		end
	end
	if onPlus then
		plus.MouseButton1Click:Connect(function() playUIClick(); onPlus() end)
	end

	-- AMOUNT: centred in the gap the icon and the "+" leave behind, so the number stays
	-- optically centred in the pod however wide the value grows.
	--
	-- TextScaled UNDER a MaxTextSize cap, rather than a fixed size. A balance of "50" wants
	-- the full 22px the reference uses, but "125,400" at 22px is wider than the space the
	-- icon and the "+" leave and would truncate to "125,4...". Capped-scaled text renders
	-- short balances at exactly 22 and quietly steps a rich player's number down instead
	-- of hiding digits -- and the sections keep their widths either way.
	local leftEdge  = PAD + ICON_D + PAD
	local rightEdge = PAD + PLUS_D + PAD
	local amount = mkLabel(pod, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, leftEdge, 0.5, 0),
		Size = UDim2.new(1, -(leftEdge + rightEdge), 0, math.floor(SEC_H * 0.58)),
		Text = "0",
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 8,
	})
	do
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = math.floor(22 * scale)
		c.MinTextSize = 11
		c.Parent = amount
	end
	styleText(amount) -- bold rounded white with the thin black outline, the house token
	return pod, iconHolder, amount
end

-- SECTION ORDER inside the capsule, left to right: token, then coin. The coin section is
-- the wider of the two -- see TOKEN_W / COIN_W above. The settings button is NOT in here;
-- it is a separate object built above.

-- CRATE TOKENS (leaderstats.CrateTokens) -- the cosmetic currency, kept strictly apart
-- from coins (see DinosaurRealm/CrateTokens). "+" opens the crate shop, the only place
-- tokens are ever spent.
--
-- FindFirstChild, deliberately NOT WaitForChild: this runs on the main body of the
-- bootstrap, so a yield here would hold up every HUD element built after it -- settings,
-- the right panel, the shop -- for as long as the wait. The folder is replicated at join
-- so it is always already there; if it somehow is not, the fallbacks below are the same
-- icon bytes and the same formatting the module would have supplied.
local CrateTokens = nil
pcall(function()
	local realm = game:GetService("ReplicatedStorage"):FindFirstChild("DinosaurRealm")
	local mod = realm and realm:FindFirstChild("CrateTokens")
	if mod then CrateTokens = require(mod) end
end)
-- The panel is NAVY; the red belongs to the ticket icon sitting on it. x = 0: the token
-- section starts hard against the left of the interior, and the coin section starts at
-- exactly TOKEN_W -- the two therefore share an edge with nothing between them.
local tokenPod, tokenIconHolder, tokenAmountLabel = makeCurrencySection(0, TOKEN_W, TICKET_NAVY, function()
	toggleMainMenu("SkinCrates", "SkinCrateGui")
end)
local tokenIcon = mkLabel(tokenIconHolder, {
	Name = "TokenIcon",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	Text = (CrateTokens and CrateTokens.ICON) or "\xF0\x9F\x8E\x9F",
	Font = JUNGLE_FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 9,
})
do -- TextScaled under a cap: the emoji renders from a bitmap font at a fixed design size,
	-- so scaling it to the box keeps it crisp instead of resampling a fixed TextSize.
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.floor(SEC_H * 0.78)
	c.Parent = tokenIcon
end

-- FOOD COINS (leaderstats.Coins) -- "+" opens the premium shop, as it always has.
local coinPod, coinIconHolder, coinAmountLabel = makeCurrencySection(TOKEN_W, COIN_W, COIN_ORANGE, function()
	toggleMainMenu("Premium", "PremiumShopGui")
end)
local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.Size = UDim2.fromScale(1, 1)
coinIcon.Position = UDim2.fromScale(0.5, 0.5)
coinIcon.AnchorPoint = Vector2.new(0.5, 0.5)
coinIcon.BackgroundTransparency = 1
coinIcon.Image = _G.COIN_IMAGE
coinIcon.ResampleMode = Enum.ResamplerMode.Default -- crisp downscale of the source art
coinIcon.ScaleType = Enum.ScaleType.Fit
coinIcon.ZIndex = 9
coinIcon.Parent = coinIconHolder

-- Live numbers: mirror the leaderstats values if they exist (so this "just works" when
-- the stats are present) and no-op gracefully otherwise. Both currencies are formatted
-- with thousands separators -- a bare five-digit balance is the one thing that would
-- overflow a fixed-width pod.
local function commas(n)
	if CrateTokens then return CrateTokens.format(n) end
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	if not ls then return end
	local function bind(statName, label)
		local stat = ls:FindFirstChild(statName)
		if not stat then
			-- the stat may be created after leaderstats itself; catch it when it lands
			local conn
			conn = ls.ChildAdded:Connect(function(child)
				if child.Name == statName then conn:Disconnect(); bind(statName, label) end
			end)
			return
		end
		local function refresh() label.Text = commas(stat.Value) end
		refresh()
		stat:GetPropertyChangedSignal("Value"):Connect(refresh)
	end
	bind("Coins", coinAmountLabel)
	bind("CrateTokens", tokenAmountLabel)
end)

--======================================================================
-- 2) SETTINGS: gear button (fills the currency bar's utility slot) + Music/SFX panel
--    Fully self-contained -- works standalone with no other game systems.
--======================================================================
local musicOn = true
local sfxOn   = true
_G.musicEnabled = true

-- SFX routing group: every NON-music sound plays through this so one toggle mutes all SFX.
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "GameSFX_HUDClone"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService
local function routeSound(snd)
	if typeof(snd) ~= "Instance" or not snd:IsA("Sound") then return end
	if snd.SoundGroup == nil then pcall(function() snd.SoundGroup = sfxGroup end) end
end
for _, d in ipairs(Workspace:GetDescendants())    do routeSound(d) end
for _, d in ipairs(SoundService:GetDescendants()) do routeSound(d) end
Workspace.DescendantAdded:Connect(routeSound)
SoundService.DescendantAdded:Connect(routeSound)
local function applySFX()   sfxGroup.Volume = sfxOn and 1 or 0 end
local function applyMusic() _G.musicEnabled = musicOn; if _G.refreshMusicVolume then pcall(_G.refreshMusicVolume) end end

local settingsGui = Instance.new("ScreenGui")
settingsGui.Name = "SettingsGui"; settingsGui.ResetOnSpawn = false; settingsGui.IgnoreGuiInset = true; settingsGui.DisplayOrder = 60; settingsGui.Parent = PlayerGui

-- The gear lives INSIDE the currency bar's utility slot, not loose in this ScreenGui.
-- It therefore fills its slot (no size of its own) and rides the bar's single UIScale,
-- which is what keeps it locked to the pods on every device -- the old copy floated in
-- SettingsGui and had to be re-placed from the coin pill's AbsolutePosition whenever
-- that moved, with its own scale to keep in step.
local gearBtn = Instance.new("TextButton")
gearBtn.Name = "SettingsGearBtn"
gearBtn.AnchorPoint = Vector2.new(0.5, 0.5)
gearBtn.Position = UDim2.fromScale(0.5, 0.5)
gearBtn.Size = UDim2.fromScale(1, 1)
-- The button's FACE -- gradient, borders, shadow and inset -- is built with the currency
-- bar above (settingsSlot), because that is where its geometry belongs. All that is left
-- here is the transparent hit target that fills it and the gear glyph on top.
--
-- CLEAN AND MINIMAL, by instruction: no vines, leaves, wood, stone or fossils touch this
-- button. The only prehistoric mark anywhere near it is the weathered edge on its outer
-- frame, and that is a single darkened hairline you would have to go looking for.
gearBtn.BackgroundTransparency = 1 -- settingsSlot is the visible face; this is just the input
gearBtn.Text = ""                  -- no text, ever: the glyph below is the whole button
gearBtn.AutoButtonColor = false
gearBtn.Size = UDim2.fromScale(1, 1)
gearBtn.Position = UDim2.fromScale(0.5, 0.5)
gearBtn.AnchorPoint = Vector2.new(0.5, 0.5)
gearBtn.ZIndex = 9
gearBtn.Parent = settingsSlot
do -- extremely subtle weathered edge: one short darkened arc on the outer frame, at 0.86
	-- transparency. This is the ENTIRE dinosaur styling on the settings button.
	local worn = mkFrame(settingsSlot, { Name = "WornEdge", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.62, 0, 0, 1), Size = UDim2.fromOffset(14, 2),
		BackgroundColor3 = Color3.fromRGB(120, 96, 62), BackgroundTransparency = 0.86,
		BorderSizePixel = 0, ZIndex = 6 })
	mkCorner(worn, 99)
end
do -- LARGE light-grey gear, dead centre, with generous padding around it. The soft emboss
	-- is a darker copy one pixel BELOW the light one -- the glyph then catches the same
	-- top-down light as the button, without a bevel or an outline.
	local GEAR_GLYPH = "\xE2\x9A\x99"
	local function gearLayer(col, dy, z)
		return mkLabel(settingsSlot, {
			Name = dy == 0 and "GearIcon" or "GearEmboss",
			Text = GEAR_GLYPH,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = col,
			Size = UDim2.fromScale(0.54, 0.54), -- generous padding: just over half the face
			Position = UDim2.new(0.5, 0, 0.5, dy),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = z,
		})
	end
	gearLayer(Color3.fromRGB(12, 16, 28), 1, 7) -- the shadow underneath
	gearLayer(GEAR_GREY, 0, 8)                  -- the gear itself
end

-- ---- HAND THE BUTTON TO THE CAPSULE -------------------------------------------------
-- Built above as a child of barRoot, whose ScreenGui (CoinGui) is now disabled -- so left
-- where it was, the settings button would simply vanish with the bar it was nested in.
--
-- It moves out INTACT, face and all: `settingsRoot` is the visible button (frame, shadow,
-- borders, gear glyph, worn edge) and gearBtn inside it is only the hit target. That is
-- why CurrencyCapsule's CONFIG.GEAR_BTN names THIS frame and not gearBtn.
--
-- Reparented here rather than at creation because it has to be finished first: the slot,
-- the hit target, the worn edge and both gear layers are all added above.
--
-- Position/AnchorPoint are not set: CurrencyCapsule adopts this into a UIListLayout, which
-- ignores a child's Position entirely and re-asserts its AnchorPoint every frame.
settingsRoot.Parent = settingsGui

local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Size = UDim2.new(0, 260, 0, 150)
settingsPanel.AnchorPoint = Vector2.new(1, 0)
settingsPanel.Position = UDim2.new(1, -10, 0, 64)
settingsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
settingsPanel.BorderSizePixel = 0
settingsPanel.Visible = false
settingsPanel.ZIndex = 20
settingsPanel.Parent = settingsGui
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=settingsPanel end
do local s=Instance.new("UIStroke"); s.Color=Color3.fromRGB(255,255,255); s.Thickness=2; s.Parent=settingsPanel end

local sTitle = Instance.new("TextLabel")
sTitle.Size = UDim2.new(1, -54, 0, 34); sTitle.Position = UDim2.new(0, 12, 0, 6); sTitle.BackgroundTransparency = 1
sTitle.Text = "Settings"; sTitle.Font = Enum.Font.GothamBold; sTitle.TextSize = 20; sTitle.TextColor3 = Color3.fromRGB(255,255,255)
sTitle.TextXAlignment = Enum.TextXAlignment.Left; sTitle.ZIndex = 21; sTitle.Parent = settingsPanel

local sCloseBtn = Instance.new("TextButton")
sCloseBtn.Size = UDim2.new(0, 30, 0, 30); sCloseBtn.Position = UDim2.new(1, -38, 0, 8); sCloseBtn.AnchorPoint = Vector2.new(0, 0)
sCloseBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60); sCloseBtn.Text = "X"; sCloseBtn.Font = Enum.Font.GothamBold
sCloseBtn.TextScaled = true; sCloseBtn.TextColor3 = Color3.fromRGB(255,255,255); sCloseBtn.ZIndex = 21; sCloseBtn.Parent = settingsPanel
do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=sCloseBtn end

local function makeToggleRow(yOff, labelText, getOn, setOn)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 40); row.Position = UDim2.new(0, 12, 0, yOff); row.BackgroundTransparency = 1
	row.ZIndex = 21; row.Parent = settingsPanel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -90, 1, 0); lbl.Position = UDim2.new(0, 0, 0, 0); lbl.BackgroundTransparency = 1
	lbl.Text = labelText; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16; lbl.TextColor3 = Color3.fromRGB(235,235,245)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 21; lbl.Parent = row
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 76, 0, 30); btn.Position = UDim2.new(1, -76, 0.5, 0); btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 15; btn.TextColor3 = Color3.fromRGB(255,255,255); btn.ZIndex = 21; btn.Parent = row
	do local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=btn end
	local function refresh()
		local on = getOn()
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(50, 190, 70) or Color3.fromRGB(120, 120, 130)
	end
	btn.MouseButton1Click:Connect(function() setOn(not getOn()); refresh() end)
	refresh()
end
makeToggleRow(46,  "Music",         function() return musicOn end, function(v) musicOn = v; applyMusic() end)
makeToggleRow(96,  "Sound Effects", function() return sfxOn   end, function(v) sfxOn   = v; applySFX()   end)

gearBtn.MouseButton1Click:Connect(function() playUIClick(); settingsPanel.Visible = not settingsPanel.Visible end)
sCloseBtn.MouseButton1Click:Connect(function() playUIClick(); settingsPanel.Visible = false end)
applySFX(); applyMusic()

-- Hang the settings panel under the currency row. The GEAR still needs no placing -- a
-- UIListLayout positions it, CurrencyCapsule's now -- so this only follows the row for the
-- drop-down panel, which lives in its own ScreenGui (DisplayOrder 60) to stay above
-- everything it covers.
--
-- ANCHORED TO THE GEAR, NOT THE OLD BAR. barRoot is inside the disabled CoinGui: a hidden
-- ScreenGui's descendants report AbsoluteSize 0, so `place()` would hit the guard below and
-- return every time, leaving the panel parked at wherever it was authored. The gear is the
-- thing the panel drops out of anyway, so following it is also the more honest anchor --
-- and it keeps working wherever the capsule's row puts it.
task.spawn(function()
	local function place()
		local size = settingsRoot.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		local pos = settingsRoot.AbsolutePosition
		-- ABSOLUTE width, not Size.X.Offset: ResponsiveUI puts a UIScale on the panel, so
		-- its authored 260 is not its rendered width on a phone. Right-aligning off the
		-- authored number pushed the panel off the screen edge at any scale below 1.
		local panelW = settingsPanel.AbsoluteSize.X
		if panelW <= 0 then panelW = settingsPanel.Size.X.Offset end
		-- DROPS FROM THE GEAR, RIGHT-ALIGNS TO THE ROW. The gear gives the Y (it is what the
		-- panel opens out of) but it is only 56 wide -- right-aligning a 260px panel to a
		-- 56px button would hang it off to the left of the capsule instead of under the
		-- cluster. The row is the full [gear + capsule] width, so its right edge is the one
		-- the panel should line up with, exactly as the old bar's right edge used to be.
		local row = _G.CurrencyCapsule and _G.CurrencyCapsule.row
		local rightX = pos.X + size.X
		if row and row.Parent and row.AbsoluteSize.X > 0 then
			rightX = row.AbsolutePosition.X + row.AbsoluteSize.X
		end
		settingsPanel.AnchorPoint = Vector2.new(0, 0)
		settingsPanel.Position = UDim2.fromOffset(rightX - panelW, pos.Y + size.Y + 6)
	end
	place()
	settingsRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	settingsRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	settingsPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end)

--======================================================================
-- 3) RIGHT PANEL: STATS + IMPULSE BUTTONS  (RightPanelGui)
--======================================================================
local rightPanel = Instance.new("Frame")
do
	local rightGui = Instance.new("ScreenGui")
	rightGui.Name = "RightPanelGui"; rightGui.ResetOnSpawn = false
	rightGui.IgnoreGuiInset = true; rightGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rightGui.Parent = PlayerGui
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0,230,0,500); rightPanel.Position = UDim2.new(1,-5,0,85)
	rightPanel.AnchorPoint = Vector2.new(1,0); rightPanel.BackgroundColor3 = PARCHMENT
	rightPanel.ZIndex = 3; rightPanel.Parent = rightGui
end
rightPanel:SetAttribute("ResponsiveExtraShrink", 0.78)  -- first-realm RightPanelGui cluster extra (mobile-only, applied by ResponsiveUI)
mkCorner(rightPanel,18); mkStroke(rightPanel,WOOD_DARK,3)
addShadow(rightPanel,18)
glossGradient(rightPanel, PARCHMENT)
addInnerHighlight(rightPanel, 18)
-- Foliage removed, same call as the side buttons above. The two top-corner vines ran at
-- ZIndex 14 -- above the panel's own content -- so a 28px cluster sat over the top of the
-- STATS banner. The wooden frame, the gloss and the skull already say jungle; the leaves
-- were only covering the numbers people open this panel to read.

-- stats section (y=8, height=175)
local statsSection = Instance.new("Frame")
statsSection.Size = UDim2.new(1,-16,0,175); statsSection.Position = UDim2.new(0,8,0,8)
statsSection.BackgroundTransparency = 1; statsSection.Parent = rightPanel

local statsTitle = Instance.new("Frame")
statsTitle.Name = "StatsBanner"
statsTitle.Size = UDim2.new(1,-8,0,36); statsTitle.Position = UDim2.new(0,8,0,0)
statsTitle.BackgroundColor3 = WOOD_DARK; statsTitle.BorderSizePixel = 0; statsTitle.ZIndex = 4; statsTitle.Parent = statsSection
mkCorner(statsTitle,12); mkStroke(statsTitle,Color3.fromRGB(40,26,14),2)
glossGradient(statsTitle, WOOD_DARK)
addInnerHighlight(statsTitle, 12)
do
	-- centered chunky title, kept fully in FRONT of the banner (bug fix)
	local t = mkLabel(statsTitle,{Name="Title",Text="STATS",TextColor3=Color3.new(1,1,1),Font=JUNGLE_FONT,TextScaled=true,Size=UDim2.new(1,-66,1,-8),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,ZIndex=10})
	t.TextStrokeColor3=Color3.new(0,0,0); t.TextStrokeTransparency=0
	do local tc=Instance.new("UITextSizeConstraint"); tc.MaxTextSize=22; tc.Parent=t end
	-- dino-skull icon to the RIGHT of the title (clear of the text)
	mkLabel(statsTitle,{Name="Skull",Text="\xF0\x9F\xA6\x96",TextScaled=true,Size=UDim2.new(0,26,0,26),Position=UDim2.new(1,-8,0.5,0),AnchorPoint=Vector2.new(1,0.5),BackgroundTransparency=1,ZIndex=9})
	-- Leaves removed. The skull on the right is the banner's only ornament now, which
	-- also re-centres STATS optically: it was flanked by foliage on one side and a
	-- glyph on the other.
end

local islandLabel = Instance.new("TextLabel")
islandLabel.Size = UDim2.new(1,0,0,36); islandLabel.Position = UDim2.new(0,0,0,36)
islandLabel.BackgroundTransparency = 1; islandLabel.Text = "\xF0\x9F\x8F\x9d\xef\xb8\x8f Island: 1"
islandLabel.Font = Enum.Font.GothamBold; islandLabel.TextSize = 22; islandLabel.TextColor3 = Color3.fromRGB(255,255,255)
islandLabel.TextScaled = true; islandLabel.RichText = false
islandLabel.TextXAlignment = Enum.TextXAlignment.Left; islandLabel.Parent = statsSection

-- live: STATS island number = the island the player is standing on (XZ footprint -> nearest), island1..island13
do
	local WorkspaceSvc = game:GetService("Workspace")
	local function curIsland()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return 1 end
		local pos = hrp.Position
		local best, bestD = nil, math.huge
		for i = 1, 13 do
			local isl = WorkspaceSvc:FindFirstChild("island" .. i)
			if isl then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and cf and size then
					local dx, dz = pos.X - cf.Position.X, pos.Z - cf.Position.Z
					if math.abs(dx) <= size.X/2 and math.abs(dz) <= size.Z/2 then return i end
					local d = dx*dx + dz*dz
					if d < bestD then bestD = d; best = i end
				end
			end
		end
		return best or 1
	end
	task.spawn(function()
		while true do
			islandLabel.Text = "\xF0\x9F\x8F\x9d\xef\xb8\x8f Island: " .. curIsland()
			task.wait(0.5)
		end
	end)
end

local heightLabel = Instance.new("TextLabel")
heightLabel.Size = UDim2.new(1,0,0,36); heightLabel.Position = UDim2.new(0,0,0,76)
heightLabel.BackgroundTransparency = 1; heightLabel.Text = "\xF0\x9F\x8f\x86 Max Height: 0"
heightLabel.Font = Enum.Font.GothamBold; heightLabel.TextSize = 22; heightLabel.TextColor3 = Color3.fromRGB(255,255,255)
heightLabel.TextScaled = true; heightLabel.RichText = false
heightLabel.TextXAlignment = Enum.TextXAlignment.Left; heightLabel.Parent = statsSection

-- Space Realm progress bar
local SPACE_TOTAL_ISLANDS = 13
local spaceRealmTitle = Instance.new("TextLabel")
spaceRealmTitle.Size = UDim2.new(1,0,0,22); spaceRealmTitle.Position = UDim2.new(0,0,0,116)
spaceRealmTitle.BackgroundTransparency = 1; spaceRealmTitle.Text = "\xF0\x9F\x9A\x80 TO NEXT REALM"
spaceRealmTitle.Font = Enum.Font.GothamBold; spaceRealmTitle.TextSize = 16; spaceRealmTitle.TextColor3 = Color3.fromRGB(255,255,255)
spaceRealmTitle.TextScaled = true; spaceRealmTitle.RichText = false
spaceRealmTitle.TextXAlignment = Enum.TextXAlignment.Left; spaceRealmTitle.Parent = statsSection
local spaceBarBG = Instance.new("Frame")
spaceBarBG.Size = UDim2.new(1,-2,0,22); spaceBarBG.Position = UDim2.new(0,0,0,142)
spaceBarBG.BackgroundColor3 = Color3.fromRGB(10,14,36); spaceBarBG.BorderSizePixel = 0; spaceBarBG.ZIndex = 4; spaceBarBG.Parent = statsSection
mkCorner(spaceBarBG, 11); mkStroke(spaceBarBG, Color3.fromRGB(8,10,28), 1)
-- inner shadow along the top of the track
do local sh=mkFrame(spaceBarBG,{Size=UDim2.new(1,-4,0,5),Position=UDim2.new(0.5,0,0,2),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.55,BorderSizePixel=0,ZIndex=4}); mkCorner(sh,6) end
local spaceFill = Instance.new("Frame")
spaceFill.Size = UDim2.new(0,0,1,0); spaceFill.BackgroundColor3 = Color3.fromRGB(104,224,128); spaceFill.BorderSizePixel = 0; spaceFill.ZIndex = 5; spaceFill.Parent = spaceBarBG
mkCorner(spaceFill, 11)
do local g=Instance.new("UIGradient"); g.Rotation=90; g.Color=ColorSequence.new(Color3.fromRGB(160,248,180), Color3.fromRGB(66,188,104)); g.Parent=spaceFill end
local spacePctLabel = Instance.new("TextLabel")
spacePctLabel.Size = UDim2.new(1,-8,1,0); spacePctLabel.Position = UDim2.new(0,4,0,0); spacePctLabel.BackgroundTransparency = 1
spacePctLabel.Font = Enum.Font.GothamBold; spacePctLabel.TextSize = 13; spacePctLabel.TextColor3 = Color3.new(1,1,1)
spacePctLabel.TextScaled = true; spacePctLabel.RichText = false; spacePctLabel.ZIndex = 5; spacePctLabel.Parent = spaceBarBG
mkStroke(spacePctLabel, Color3.new(0,0,0), 1)
local function updateSpaceRealmProgress()
	local hi = math.clamp(math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1), 1, SPACE_TOTAL_ISLANDS)
	local frac = hi / SPACE_TOTAL_ISLANDS
	spaceFill.Size = UDim2.new(frac, 0, 1, 0)
	spaceFill.BackgroundColor3 = (hi >= SPACE_TOTAL_ISLANDS) and Color3.fromRGB(170,110,255) or Color3.fromRGB(90,200,120)
	spacePctLabel.Text = "Island " .. hi .. "/" .. SPACE_TOTAL_ISLANDS .. "  -  " .. math.floor(frac * 100 + 0.5) .. "%"
end
updateSpaceRealmProgress()
player:GetAttributeChangedSignal("HighestIsland"):Connect(updateSpaceRealmProgress)

-- divider (y=187)
do
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1,-16,0,2); divider.Position = UDim2.new(0,8,0,187)
	divider.BackgroundColor3 = Color3.fromRGB(255,255,255); divider.BackgroundTransparency = 0.7; divider.Parent = rightPanel
end

-- MID-AIR RECHARGE button (y=197)
local midAir = Instance.new("TextButton")
midAir.Name = "MidAirBtn"; midAir.Size = UDim2.new(1,-16,0,90); midAir.Position = UDim2.new(0,8,0,197)
midAir.BackgroundColor3 = Color3.fromRGB(50,120,220); midAir.Text = ""; midAir.ZIndex = 4; midAir.Parent = rightPanel
mkCorner(midAir,12); mkStroke(midAir,Color3.fromRGB(255,255,255),1.5)
local midAirIcon = Instance.new("TextLabel")
midAirIcon.Size = UDim2.new(0,60,0,60); midAirIcon.Position = UDim2.new(0,8,0.5,0); midAirIcon.AnchorPoint = Vector2.new(0,0.5); midAirIcon.BackgroundTransparency = 1
midAirIcon.Text = "\xe2\x9a\xa1\xe2\x98\x81\xef\xb8\x8f"; midAirIcon.TextSize = 36; midAirIcon.Font = Enum.Font.Gotham
midAirIcon.RichText = false; midAirIcon.TextXAlignment = Enum.TextXAlignment.Center; midAirIcon.TextYAlignment = Enum.TextYAlignment.Center; midAirIcon.ZIndex = 5; midAirIcon.Parent = midAir
local midAirTitle = Instance.new("TextLabel")
midAirTitle.Size = UDim2.new(1,-76,0,28); midAirTitle.Position = UDim2.new(0,76,0,8); midAirTitle.BackgroundTransparency = 1
midAirTitle.Text = "MID-AIR"; midAirTitle.Font = Enum.Font.GothamBold; midAirTitle.TextSize = 20; midAirTitle.TextColor3 = Color3.fromRGB(255,255,255)
midAirTitle.TextScaled = true; midAirTitle.RichText = false; midAirTitle.TextXAlignment = Enum.TextXAlignment.Left; midAirTitle.TextYAlignment = Enum.TextYAlignment.Center; midAirTitle.ZIndex = 5; midAirTitle.Parent = midAir
local midAirSub = Instance.new("TextLabel")
midAirSub.Size = UDim2.new(1,-76,0,22); midAirSub.Position = UDim2.new(0,76,0,38); midAirSub.BackgroundTransparency = 1
midAirSub.Text = "RECHARGE"; midAirSub.Font = Enum.Font.Gotham; midAirSub.TextSize = 16; midAirSub.TextColor3 = Color3.fromRGB(220,220,220)
midAirSub.TextScaled = true; midAirSub.RichText = false; midAirSub.TextXAlignment = Enum.TextXAlignment.Left; midAirSub.TextYAlignment = Enum.TextYAlignment.Center; midAirSub.ZIndex = 5; midAirSub.Parent = midAir
local midAirPrice = Instance.new("TextLabel")
midAirPrice.Size = UDim2.new(1,-76,0,22); midAirPrice.Position = UDim2.new(0,76,0,62); midAirPrice.BackgroundTransparency = 1
midAirPrice.Text = "39 R$"; midAirPrice.Font = Enum.Font.GothamBold; midAirPrice.TextSize = 16; midAirPrice.TextColor3 = Color3.fromRGB(100,255,100)
midAirPrice.TextScaled = true; midAirPrice.RichText = false; midAirPrice.TextXAlignment = Enum.TextXAlignment.Left; midAirPrice.TextYAlignment = Enum.TextYAlignment.Center; midAirPrice.ZIndex = 5; midAirPrice.Parent = midAir
midAir.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600303163) end) end)

-- 2X POWER button (y=295)
local twoX = Instance.new("TextButton")
twoX.Name = "TwoXBtn"; twoX.Size = UDim2.new(1,-16,0,90); twoX.Position = UDim2.new(0,8,0,295)
twoX.BackgroundColor3 = Color3.fromRGB(130,50,200); twoX.Text = ""; twoX.ZIndex = 4; twoX.Parent = rightPanel
mkCorner(twoX,12); mkStroke(twoX,Color3.fromRGB(255,255,255),1.5)
local twoXIcon = Instance.new("TextLabel")
twoXIcon.Size = UDim2.new(0,60,0,60); twoXIcon.Position = UDim2.new(0,8,0.5,0); twoXIcon.AnchorPoint = Vector2.new(0,0.5); twoXIcon.BackgroundTransparency = 1
twoXIcon.Text = "\xe2\x9a\xa1"; twoXIcon.TextSize = 36; twoXIcon.Font = Enum.Font.Gotham
twoXIcon.RichText = false; twoXIcon.TextXAlignment = Enum.TextXAlignment.Center; twoXIcon.TextYAlignment = Enum.TextYAlignment.Center; twoXIcon.ZIndex = 5; twoXIcon.Parent = twoX
local twoXTitle = Instance.new("TextLabel")
twoXTitle.Size = UDim2.new(1,-76,0,28); twoXTitle.Position = UDim2.new(0,76,0,8); twoXTitle.BackgroundTransparency = 1
twoXTitle.Text = "2X POWER"; twoXTitle.Font = Enum.Font.GothamBold; twoXTitle.TextSize = 20; twoXTitle.TextColor3 = Color3.fromRGB(255,255,255)
twoXTitle.TextScaled = true; twoXTitle.RichText = false; twoXTitle.TextXAlignment = Enum.TextXAlignment.Left; twoXTitle.TextYAlignment = Enum.TextYAlignment.Center; twoXTitle.ZIndex = 5; twoXTitle.Parent = twoX
local twoXSub = Instance.new("TextLabel")
twoXSub.Size = UDim2.new(1,-76,0,22); twoXSub.Position = UDim2.new(0,76,0,38); twoXSub.BackgroundTransparency = 1
twoXSub.Text = "1 HOUR"; twoXSub.Font = Enum.Font.Gotham; twoXSub.TextSize = 16; twoXSub.TextColor3 = Color3.fromRGB(220,220,220)
twoXSub.TextScaled = true; twoXSub.RichText = false; twoXSub.TextXAlignment = Enum.TextXAlignment.Left; twoXSub.TextYAlignment = Enum.TextYAlignment.Center; twoXSub.ZIndex = 5; twoXSub.Parent = twoX
local twoXPrice = Instance.new("TextLabel")
twoXPrice.Size = UDim2.new(1,-76,0,22); twoXPrice.Position = UDim2.new(0,76,0,62); twoXPrice.BackgroundTransparency = 1
twoXPrice.Text = "59 R$"; twoXPrice.Font = Enum.Font.GothamBold; twoXPrice.TextSize = 16; twoXPrice.TextColor3 = Color3.fromRGB(100,255,100)
twoXPrice.TextScaled = true; twoXPrice.RichText = false; twoXPrice.TextXAlignment = Enum.TextXAlignment.Left; twoXPrice.TextYAlignment = Enum.TextYAlignment.Center; twoXPrice.ZIndex = 5; twoXPrice.Parent = twoX
twoX.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3600302990) end) end)

-- METEORITE EXPLOSION button (y=393)
local meteorBtn = Instance.new("TextButton")
meteorBtn.Name = "MeteoriteExplosionBtn"; meteorBtn.Size = UDim2.new(1,-16,0,90); meteorBtn.Position = UDim2.new(0,8,0,393)
meteorBtn.BackgroundColor3 = Color3.fromRGB(232,108,40); meteorBtn.Text = ""; meteorBtn.ZIndex = 4; meteorBtn.Parent = rightPanel
mkCorner(meteorBtn,12); mkStroke(meteorBtn,Color3.fromRGB(255,255,255),1.5)
local meteorIcon = Instance.new("TextLabel")
meteorIcon.Size = UDim2.new(0,60,0,60); meteorIcon.Position = UDim2.new(0,8,0.5,0); meteorIcon.AnchorPoint = Vector2.new(0,0.5); meteorIcon.BackgroundTransparency = 1
meteorIcon.Text = "\xE2\x98\x84\xEF\xB8\x8F"; meteorIcon.TextSize = 36; meteorIcon.Font = Enum.Font.Gotham
meteorIcon.RichText = false; meteorIcon.TextXAlignment = Enum.TextXAlignment.Center; meteorIcon.TextYAlignment = Enum.TextYAlignment.Center; meteorIcon.ZIndex = 5; meteorIcon.Parent = meteorBtn
local meteorTitle = Instance.new("TextLabel")
meteorTitle.Size = UDim2.new(1,-76,0,28); meteorTitle.Position = UDim2.new(0,76,0,8); meteorTitle.BackgroundTransparency = 1
meteorTitle.Text = "METEORITE EXPLOSION"; meteorTitle.Font = Enum.Font.GothamBold; meteorTitle.TextSize = 20; meteorTitle.TextColor3 = Color3.fromRGB(255,255,255)
meteorTitle.TextScaled = true; meteorTitle.RichText = false; meteorTitle.TextXAlignment = Enum.TextXAlignment.Left; meteorTitle.TextYAlignment = Enum.TextYAlignment.Center; meteorTitle.ZIndex = 5; meteorTitle.Parent = meteorBtn
local meteorPrice = Instance.new("TextLabel")
meteorPrice.Size = UDim2.new(1,-76,0,22); meteorPrice.Position = UDim2.new(0,76,0,62); meteorPrice.BackgroundTransparency = 1
meteorPrice.Text = "79 R$"; meteorPrice.Font = Enum.Font.GothamBold; meteorPrice.TextSize = 16; meteorPrice.TextColor3 = Color3.fromRGB(100,255,100)
meteorPrice.TextScaled = true; meteorPrice.RichText = false; meteorPrice.TextXAlignment = Enum.TextXAlignment.Left; meteorPrice.TextYAlignment = Enum.TextYAlignment.Center; meteorPrice.ZIndex = 5; meteorPrice.Parent = meteorBtn
meteorBtn.MouseButton1Click:Connect(function() playUIClick(); pcall(function() MarketplaceService:PromptProductPurchase(player,3606893853) end) end)

-- Jungle restyle for the three right-side action buttons: glossy fill, dark
-- border, cream circular icon badge on the left, bold outlined text.
local function styleActionBtn(btn, iconLbl, baseCol)
	-- match the left plaques exactly: corner 18, stroke 3, shadow, gloss, glow (no foliage)
	local cn = btn:FindFirstChildOfClass("UICorner"); if cn then cn.CornerRadius = UDim.new(0, 18) end
	local st = btn:FindFirstChildOfClass("UIStroke"); if st then st.Color = shade(baseCol, 0.45); st.Thickness = 3 end
	addShadow(btn, 18)
	glossGradient(btn, baseCol)
	addInnerGlow(btn, baseCol, 18)
	addInnerHighlight(btn, 18)
	-- stronger top specular gloss strip
	local g2 = mkFrame(btn,{Size=UDim2.new(1,-16,0,14),Position=UDim2.new(0.5,0,0,5),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.8,BorderSizePixel=0,ZIndex=6}); mkCorner(g2,7)
	-- cream circular icon badge, vertically centered on the left
	local badge = mkFrame(btn,{Size=UDim2.new(0,56,0,56),Position=UDim2.new(0,10,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=CREAM,BorderSizePixel=0,ZIndex=5})
	mkCorner(badge,999); mkStroke(badge,WOOD_DARK,2)
	do -- embossed cream badge (top-lit gradient + inner rim shadow)
		local bg=Instance.new("UIGradient"); bg.Rotation=90; bg.Color=ColorSequence.new(tint(CREAM,0.4),shade(CREAM,0.9)); bg.Parent=badge
		local rim=Instance.new("Frame"); rim.AnchorPoint=Vector2.new(0.5,0.5); rim.Position=UDim2.fromScale(0.5,0.5); rim.Size=UDim2.new(1,-4,1,-4); rim.BackgroundTransparency=1; rim.ZIndex=5
		local rc=Instance.new("UICorner"); rc.CornerRadius=UDim.new(1,0); rc.Parent=rim
		local rs=Instance.new("UIStroke"); rs.Color=Color3.fromRGB(150,125,90); rs.Transparency=0.4; rs.Thickness=2; rs.Parent=rim; rim.Parent=badge
	end
	if iconLbl then iconLbl.ZIndex = 7; iconLbl.TextColor3 = Color3.fromRGB(60,45,30) end
	-- Foliage removed. These three buttons live INSIDE rightPanel, so their corner vines
	-- read as part of the stats panel's decoration rather than their own -- stripping the
	-- panel and leaving them would have left leaves scattered down its right side.
	for _,d in ipairs(btn:GetChildren()) do
		if d:IsA("TextLabel") then
			d.Font = JUNGLE_FONT; d.TextStrokeColor3 = Color3.new(0,0,0); d.TextStrokeTransparency = 0
			if d.ZIndex < 7 then d.ZIndex = 7 end
			if d.TextColor3.G > 0.7 and d.TextColor3.R < 0.6 and d.TextColor3.B < 0.7 then
				d.TextColor3 = Color3.fromRGB(120,255,140) -- brighter green price
			end
		end
	end
end
styleActionBtn(midAir, midAirIcon, Color3.fromRGB(50,120,220))
styleActionBtn(twoX, twoXIcon, Color3.fromRGB(130,50,200))
styleActionBtn(meteorBtn, meteorIcon, Color3.fromRGB(232,108,40))

--======================================================================
-- 4) LEFT-SIDE BUTTONS  (SidebarGui): SHOP / INVITE / Stomach / MORE
--======================================================================
local sidebarGui = Instance.new("ScreenGui")
sidebarGui.Name = "SidebarGui"; sidebarGui.ResetOnSpawn = false; sidebarGui.Parent = PlayerGui

-- All 4 side buttons live in ONE cluster frame so ResponsiveUI scales the rail as a single unit
-- (button size AND the spacing between them) about its top-left corner -- exactly like the first
-- realm. Without this wrapper each button would scale its size but keep its authored Y, pushing the
-- lower buttons (y up to ~512) off a short phone viewport. SidebarGui's cluster extra is 1.00 (none),
-- so no ResponsiveExtraShrink attribute here -- it just rides getScale() (1.0 desktop / ~0.60 phone).
local sidebarCluster = mkFrame(sidebarGui,{Size=UDim2.new(0,120,0,520),Position=UDim2.new(0,0,0,0),AnchorPoint=Vector2.new(0,0),BackgroundTransparency=1})

local function mkSideBtn(yTop,bgCol,iconTxt,labelTxt)
	-- Wooden-plaque cartoon button: glossy saturated fill, thick dark rounded
	-- border, leafy corner accents, cream icon badge, outlined label.
	-- Layout matches the main Fart-to-Float HUD: 95x95, pinned TOP-LEFT (anchor 0,0) at
	-- X=12 on a fixed top-down Y grid (yTop = 96/203/310/417, 107px pitch) -- NOT centre-anchored.
	local btn=mkFrame(sidebarCluster,{Size=UDim2.new(0,95,0,95),Position=UDim2.new(0,12,0,yTop),AnchorPoint=Vector2.new(0,0),BackgroundColor3=bgCol})
	btn.ZIndex = 3
	addShadow(btn, 18)
	mkCorner(btn,18)
	mkStroke(btn, shade(bgCol, 0.5), 3)
	glossGradient(btn, bgCol)
	-- glossy specular highlight strip near the top
	local gloss=mkFrame(btn,{Size=UDim2.new(1,-16,0,18),Position=UDim2.new(0.5,0,0,6),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.78,ZIndex=4})
	mkCorner(gloss,9)
	-- faint inner highlight bevel just inside the border
	addInnerHighlight(btn, 18)
	-- Foliage removed. The left-edge vine ran at ZIndex 11 and the two corner clusters at
	-- 13, all ABOVE the icon badge's ZIndex 6, so leaves were drawn straight over the
	-- glyph on a 95px button -- the badge is 44px and the top-left cluster overlapped it
	-- directly. The buttons keep their gloss, bevel and outline; only the overlap is gone.
	-- circular icon badge, uniform size and position on all four buttons
	addIconBadge(btn, math.floor(44*scale), 0.1, iconTxt, math.floor(24*scale))
	-- outlined white label lower, with a clear gap below the badge
	local textL=mkLabel(btn,{Name="Label",Text=labelTxt,TextScaled=true,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-8,0,22),Position=UDim2.new(0,4,1,-10),AnchorPoint=Vector2.new(0,1),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,ZIndex=6})
	styleText(textL)
	do local tc=Instance.new("UITextSizeConstraint"); tc.MaxTextSize=math.floor(16*scale); tc.Parent=textL end
	local clickBtn=mkButton(btn,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",ZIndex=20})
	return btn,clickBtn
end

local shopSideFrame,shopSideClick     = mkSideBtn(96,Color3.fromRGB(50,180,50),"\xF0\x9F\x9b\x92","SHOP")
-- PETS takes over the old Invite/Wormhole slot: opens the Pet Hub directly. The Wormhole
-- travel menu moved into the MORE+ popup (see MORE_ENTRIES below) -- swapped by request.
local petsSideFrame,petsSideClick = mkSideBtn(203,Color3.fromRGB(70,150,235),"\xF0\x9F\x90\xBE","PETS")
-- STOMACH (was the "Pets" paw button).
-- The Pet Hub is NOT orphaned by this: PetHub.client.luau builds its own paw button in
-- the bottom-left corner, which is the real way in -- this sidebar slot was a duplicate.
-- The Stomach Shop, meanwhile, was buried inside the MORE+ popup, so the gut upgrade -- a
-- core progression purchase -- had no button of its own. Now it does.
--
-- Note this slot was ALWAYS meant to be Stomach: the "gut upgrade affordable" wiggle
-- further down still targets this frame and still calls it the Stomach button. While it
-- held the paw icon, that wiggle was shaking the PETS button whenever you could afford a
-- gut. Swapping it back makes that animation correct again.
local gutSideFrame,gutSideClick       = mkSideBtn(310,Color3.fromRGB(235,140,60),"\xF0\x9F\xA6\x95","STOMACH")
local stomachSideFrame,stomachSideClick = mkSideBtn(417,Color3.fromRGB(225,70,170),"+","MORE")
-- (the "!" badge on the MORE+ button is the toggling crate dot added later via mkCrateDot(stomachSideFrame);
--  it only shows when something is actually claimable, so no permanent badge here.)

shopSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	toggleMainMenu("Premium", "PremiumShopGui")
end)
gutSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- open the STOMACH SHOP (gut tiers). Same call the MORE+ menu's "Stomachs" entry
	-- makes, so both routes go through MainMenuManager and can't end up double-open.
	toggleMainMenu("Stomach", "StomachShopGui")
end)
stomachSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- MORE+ popup is built below in this same script; toggle it open/closed.
	if setMoreOpen then setMoreOpen(not moreOpenState) end
end)
petsSideClick.MouseButton1Click:Connect(function()
	playUIClick()
	-- Open the Pet Hub -- the same path the MORE+ Pets card used. _G.togglePetHub first
	-- (the PetInvToggle BindableEvent can be swept out of PlayerGui by GUI cleanup);
	-- the event stays as a fallback for a hub build that predates the global.
	if _G.togglePetHub then _G.togglePetHub(true) return end
	local ev = PlayerGui:FindFirstChild("PetInvToggle") or PlayerGui:WaitForChild("PetInvToggle", 5)
	if ev then ev:Fire()
	else warn("[Bootstrap] PETS side button: PetInvToggle not found (is PetHub.client.luau running?)") end
end)

--======================================================================
-- 5) REAL MENUS: Premium Shop + Stomach Shop + MORE+ popup
--    These make the coin "+" / SHOP / Stomach / MORE+ buttons open real, WORKING
--    menus instead of no-ops. Every size/position/color/wiring is copied verbatim
--    from ShopClient (Premium Shop) and CoreClient (Stomach Shop + MORE menu).
--    Server-dependent actions (stomach purchase fires BuyStomachEvent; the MORE+
--    sub-items fire crate/pet/locker events) are GUARDED so they no-op cleanly in a
--    world that doesn't have those systems yet, and start working the moment it does.
--======================================================================
local RS  = game:GetService("ReplicatedStorage")
local RSx = RS
local MPS = MarketplaceService
local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979}
local PRODUCT_IDS  = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, MeteoriteExplosion=3606893853}

-- per-tier gut emoji (used by the stomach shop icons/labels), BUILT FROM StomachTiers rather
-- than hand-listed -- this table only had the six original tiers, and every consumer of it
-- falls back to "leave the icon alone" on a miss, so the twelve-tier tower would have shown
-- stale badges with nothing in the output to say why. Guarded so it is shared if already set.
if not _G.GUT_EMOJI then
	_G.GUT_EMOJI = {}
	for _, t in ipairs(require(RS:WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers")).LIST) do
		_G.GUT_EMOJI[t.name] = t.emoji
	end
end

-- insufficient-funds error sound + "can't afford" button shake (from CoreClient)
local errorSound = Instance.new("Sound")
errorSound.Name="InsufficientFundsSound_HUDClone"; errorSound.SoundId="rbxassetid://87486053112716"; errorSound.Volume=0.6; errorSound.Parent=PlayerGui
local function playErrorSound() local s=errorSound:Clone(); s.Parent=PlayerGui; s:Play(); game:GetService("Debris"):AddItem(s,3) end
local SHAKE_OFFSET = 8
local function shakeButton(btn)
	if not btn or btn:GetAttribute("Shaking") then return end
	btn:SetAttribute("Shaking", true)
	local orig = btn.Position
	local ti = TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.spawn(function()
		for _ = 1, 3 do
			local a = TweenService:Create(btn, ti, {Position = orig + UDim2.fromOffset(-SHAKE_OFFSET, 0)}); a:Play(); a.Completed:Wait()
			local b = TweenService:Create(btn, ti, {Position = orig + UDim2.fromOffset(SHAKE_OFFSET, 0)}); b:Play(); b.Completed:Wait()
		end
		local c = TweenService:Create(btn, ti, {Position = orig}); c:Play(); c.Completed:Wait()
		btn.Position = orig
		btn:SetAttribute("Shaking", false)
	end)
end

--======================================================================
-- 5a) PREMIUM SHOP -- MOVED OUT.
--     This script used to build its own "PremiumShopGui" here, and Shop.client.luau built a
--     SECOND ScreenGui under the same name, so PlayerGui held two shop panels and the SHOP
--     button toggled whichever FindFirstChild returned first. Both are gone: ShopKit.client.luau
--     is now the only thing that builds PremiumShopGui.
--     The SHOP rail button and the coin "+" button below are unchanged -- they still call
--     toggleMainMenu("Premium", "PremiumShopGui"), which resolves the GUI by name at CLICK time,
--     so they pick up the new panel with no wiring change.
--======================================================================

--======================================================================
-- 5b) STOMACH SHOP  (opened by the "Stomach" side button)
--     Verbatim from CoreClient (the Shop GUI part). The 7 gut tiers fire
--     BuyStomachEvent to the server; the current-tier label + "OWNED" badges
--     read leaderstats. All server reads are guarded, so the GUI builds + opens
--     even with no server, and the buys start working once leaderstats exist.
--======================================================================
-- local gut state (CoreClient keeps these script-level; default to Tiny Gut)
local stomachName  = "Hatchling Belly"
local stomachMax   = 100
local currentPower = 0
local stomachEmoji = _G.GUT_EMOJI["Hatchling Belly"]
local updateStomachDisplay -- nil here (this clone has no bottom gut pill); stomach-shop handler guards on it
task.spawn(function()
	local stomachShopGui=Instance.new("ScreenGui"); stomachShopGui.Name="StomachShopGui"; stomachShopGui.ResetOnSpawn=false; stomachShopGui.Enabled=false; stomachShopGui.DisplayOrder=100; stomachShopGui.Parent=PlayerGui
	-- jungle chrome (matches the Shop + Pet Hub) -- applied to the panel/cards/buttons below
	local okJC, JC = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10)) end)
	if not okJC then JC = nil end
	local currentStomachLabel; local scrollFrame; local ttlIcon; local ttlIconImg
	do
		local stomachPanel=Instance.new("Frame"); stomachPanel.Size=UDim2.new(0,700,0,520)
		stomachPanel.Position=UDim2.new(0.5,0,0.5,-16); stomachPanel.AnchorPoint=Vector2.new(0.5,0.5)  -- HUB PARITY: -16 = the hub's on-screen panel spot in an inset-ignoring gui (no phone clipping)
		stomachPanel.BackgroundColor3=Color3.fromRGB(30,120,220); stomachPanel.BorderSizePixel=0; stomachPanel.Active=true; stomachPanel.Parent=stomachShopGui
		mkCorner(stomachPanel,20); mkStroke(stomachPanel,Color3.fromRGB(20,60,160),3)
		if JC then pcall(function() JC.buildShell(stomachShopGui); JC.stylePanel(stomachPanel) end) end -- bamboo border + olive panel
		do
			local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
			bg.BackgroundTransparency=1; bg.Active=false; bg.BorderSizePixel=0; bg.ZIndex=0; bg.Parent=stomachShopGui
			ttlIcon=Instance.new("TextLabel"); ttlIcon.Name="GutIcon"; ttlIcon.BackgroundTransparency=1
			ttlIcon.Text=(_G.GUT_EMOJI[stomachName] or ""); ttlIcon.Font=Enum.Font.GothamBold; ttlIcon.TextScaled=true
			ttlIcon.Size=UDim2.new(0,46,0,46); ttlIcon.Position=UDim2.new(0,12,0,9); ttlIcon.Parent=stomachPanel
			ttlIconImg=Instance.new("ImageLabel"); ttlIconImg.Name="GutIconImg"; ttlIconImg.BackgroundTransparency=1
			ttlIconImg.Image=_G.GUT_IMAGE; ttlIconImg.ScaleType=Enum.ScaleType.Fit
			ttlIconImg.Size=UDim2.new(0,46,0,46); ttlIconImg.Position=UDim2.new(0,12,0,9); ttlIconImg.Parent=stomachPanel
			ttlIconImg.Visible=false -- dino guts use emoji icons (no image special-case)
			local ttl=mkLabel(stomachPanel,{Size=UDim2.new(1,-116,0,55),Position=UDim2.new(0,64,0,5),Text="DINO STOMACHS",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(250,242,214),TextXAlignment=Enum.TextXAlignment.Left})
			mkStroke(ttl,Color3.fromRGB(0,0,0),2)
		end
		do
			local sc=mkButton(stomachPanel,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,8),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0})
			mkCorner(sc,8); mkStroke(sc,Color3.fromRGB(160,20,20),2); if JC then pcall(function() JC.styleButton(sc) end) end
			sc.MouseButton1Click:Connect(function() playUIClick(); stomachShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Stomach") end)
		end
		currentStomachLabel=mkLabel(stomachPanel,{Size=UDim2.new(1,-20,0,35),Position=UDim2.new(0,10,0,62),BackgroundColor3=Color3.fromRGB(40,52,38),BackgroundTransparency=0,Text="Current: Hatchling Belly (100 max power)",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(250,242,214),BorderSizePixel=0})
		mkCorner(currentStomachLabel,10); mkStroke(currentStomachLabel,Color3.fromRGB(74,94,68),2)
		scrollFrame=Instance.new("ScrollingFrame"); scrollFrame.Size=UDim2.new(1,-20,1,-110)
		scrollFrame.Position=UDim2.new(0,10,0,105); scrollFrame.BackgroundTransparency=1
		scrollFrame.ScrollBarThickness=6; scrollFrame.CanvasSize=UDim2.new(0,0,0,0)
		scrollFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollFrame.BorderSizePixel=0; scrollFrame.Parent=stomachPanel
		do
			local ll=Instance.new("UIListLayout"); ll.Padding=UDim.new(0,8); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=scrollFrame
			local lp=Instance.new("UIPadding"); lp.PaddingLeft=UDim.new(0,4); lp.PaddingRight=UDim.new(0,4); lp.Parent=scrollFrame
		end
	end

	-- SHARED WITH THE SERVER, deliberately. This was a local copy, and Shop.server had its
	-- own; they drifted to 1600 vs 112 for the Raptor Gut, and since the purchase handler
	-- refused any price that did not match ITS table, every free gut became unbuyable with
	-- no error anywhere. One table now, in ReplicatedStorage.
	local StomachTiers = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers"))
	local IslandOrder  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
	local tierDefs = StomachTiers.LIST
	-- How far up the tower this player has actually been. Guts are gated on it so nobody can
	-- park on island 1 and buy their way to the summit -- see StomachTiers.isUnlocked.
	local function reachedSlot()
		return math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	end
	-- The name the lock should tell you to go and reach.
	local function slotName(slot)
		local isl = IslandOrder.SLOT_TO_ISLAND[slot]
		return (isl and IslandOrder.NAMES[isl]) or ("Island " .. tostring(slot))
	end
	local BuyStomachEvent=RS:WaitForChild("BuyStomachEvent",30)
	local StomachUpdateEvent=RS:WaitForChild("StomachUpdateEvent",30)

	-- gut-upgrade-affordable wiggle on the LEFT "STOMACH" side button.
	-- This always pointed at this frame -- it just used to be the Pets/paw button, so the
	-- wiggle was shaking PETS when you could afford a gut upgrade. Now it shakes the
	-- button it was always describing.
	local gutSideIcon = gutSideFrame
	local gutWiggling = false
	local gutWiggleTween = nil
	local function stopGutWiggle()
		if not gutWiggling then return end
		gutWiggling = false
		if gutWiggleTween then pcall(function() gutWiggleTween:Cancel() end); gutWiggleTween = nil end
		if gutSideIcon then gutSideIcon.Rotation = 0 end
	end
	local function startGutWiggle()
		if not gutSideIcon then return end
		if gutWiggling then return end
		gutWiggling = true
		gutSideIcon.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		gutWiggleTween = TweenService:Create(gutSideIcon, info, { Rotation = 8 })
		gutWiggleTween:Play()
	end
	-- The cheapest gut this player could actually buy right now. UNLOCKED ones only: the
	-- side button wiggles when this is affordable, and pointing it at a gut the server will
	-- refuse would be an advert for a locked purchase.
	local function nextCoinGutTier(curMax)
		local reached = reachedSlot()
		local best = nil
		for _, t in ipairs(tierDefs) do
			if (not t.robux) and t.cost > 0 and t.maxPower > curMax and StomachTiers.isUnlocked(t, reached) then
				if (not best) or t.maxPower < best.maxPower then best = t end
			end
		end
		return best
	end
	local function checkGutAfford()
		local ls = player:FindFirstChild("leaderstats")
		if not ls then stopGutWiggle(); _G.gutUpgradeAffordable = false; return end
		local sm = ls:FindFirstChild("StomachMax"); local c = ls:FindFirstChild("Coins")
		if not (sm and c) then stopGutWiggle(); _G.gutUpgradeAffordable = false; return end
		local nextTier = nextCoinGutTier(sm.Value)
		local affordable = (nextTier ~= nil) and (c.Value >= nextTier.cost)
		if affordable then startGutWiggle() else stopGutWiggle() end
		_G.gutUpgradeAffordable = affordable
	end
	_G.forceGutWiggle = startGutWiggle
	_G.checkGutAfford = checkGutAfford
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30); if not ls then return end
		local coins = ls:WaitForChild("Coins", 30)
		local smv = ls:WaitForChild("StomachMax", 30)
		if coins then coins:GetPropertyChangedSignal("Value"):Connect(checkGutAfford) end
		if smv then smv:GetPropertyChangedSignal("Value"):Connect(checkGutAfford) end
		checkGutAfford()
	end)

	for i,tier in ipairs(tierDefs) do
		do
			local card=Instance.new("Frame"); card.Size=UDim2.new(1,0,0,70); card.BorderSizePixel=0
			card.LayoutOrder = (tier.name == "Primal Gut") and 1 or (i + 1)
			card.BackgroundColor3=Color3.fromRGB(110,130,76); card.Parent=scrollFrame
			mkCorner(card,12); mkStroke(card,Color3.fromRGB(40,52,38),2)
			do
				local ic=Instance.new("TextLabel"); ic.Name="GutIcon"; ic.BackgroundTransparency=1
				ic.Text=(tier.emoji or _G.GUT_EMOJI[tier.name] or ""); ic.Font=Enum.Font.GothamBold; ic.TextScaled=true
				ic.Size=UDim2.new(0,52,0,52); ic.Position=UDim2.new(0,12,0.5,0); ic.AnchorPoint=Vector2.new(0,0.5)
				ic.Parent=card
			end
			do
				local nl=mkLabel(card,{Size=UDim2.new(0,220,0,32),Position=UDim2.new(0,72,0,8),Text=tier.name,Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Left})
				mkStroke(nl,Color3.fromRGB(0,0,0),2)
			end
			mkLabel(card,{Size=UDim2.new(0,220,0,24),Position=UDim2.new(0,72,0,38),TextXAlignment=Enum.TextXAlignment.Left,Text=(tier.maxPower>=9999 and "\xe2\x88\x9e Unlimited power" or tostring(tier.maxPower).." max power"),Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(180,220,255)})
			local buyBtn=Instance.new("TextButton"); buyBtn.Size=UDim2.new(0,150,0,46)
			buyBtn.Position=UDim2.new(1,-158,0.5,0); buyBtn.AnchorPoint=Vector2.new(0,0.5); buyBtn.BorderSizePixel=0
			if tier.cost==0 then buyBtn.BackgroundColor3=Color3.fromRGB(100,100,100); buyBtn.Text="\xe2\x9c\x93 FREE"
			elseif tier.robux then buyBtn.BackgroundColor3=Color3.fromRGB(255,160,20); buyBtn.Text=tostring(tier.cost).." R$"
			else buyBtn.BackgroundColor3=Color3.fromRGB(50,220,50); buyBtn.Text="\xF0\x9F\xAA\x99 "..tostring(tier.cost) end
			buyBtn.Font=Enum.Font.FredokaOne; buyBtn.TextScaled=true; buyBtn.TextColor3=Color3.fromRGB(255,255,255); buyBtn.Parent=card
			mkCorner(buyBtn,10); mkStroke(buyBtn,Color3.fromRGB(0,0,0),2); if JC then pcall(function() JC.styleButton(buyBtn) end) end
			-- LOCKED / OWNED / BUYABLE, refreshed together.
			--
			-- The card used to only ever learn one thing (OWNED) and only from a 1-second poll.
			-- A gut is now also LOCKED until you have reached the island it belongs to, and
			-- that state changes the instant HighestSlot does -- so it is driven by the
			-- attribute as well as the poll, and both go through the same function rather than
			-- each writing the button's colours in their own way.
			local UNLOCKED_COLOR, UNLOCKED_TEXT = buyBtn.BackgroundColor3, buyBtn.Text
			local CARD_LIT, CARD_LOCKED = card.BackgroundColor3, Color3.fromRGB(74, 86, 58)
			local locked = false
			local function refreshCard()
				local ls = player:FindFirstChild("leaderstats")
				local sm = ls and ls:FindFirstChild("StomachMax")
				if sm and tier.maxPower <= sm.Value then
					locked = false
					buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80); buyBtn.Text = "\xe2\x9c\x93 OWNED"
					card.BackgroundColor3 = CARD_LIT
					return
				end
				locked = not StomachTiers.isUnlocked(tier, reachedSlot())
				if locked then
					buyBtn.BackgroundColor3 = Color3.fromRGB(68, 74, 62)
					buyBtn.Text = "\xF0\x9F\x94\x92 " .. slotName(tier.unlockSlot or 1)
					card.BackgroundColor3 = CARD_LOCKED
				else
					buyBtn.BackgroundColor3 = UNLOCKED_COLOR; buyBtn.Text = UNLOCKED_TEXT
					card.BackgroundColor3 = CARD_LIT
				end
			end
			buyBtn.MouseButton1Click:Connect(function()
				if tier.cost==0 then return end
				-- Do not even fire when locked. The server refuses it anyway (a greyed button
				-- is not a check), but firing would spend the click on nothing and give no
				-- feedback -- the shake says "not yet" in the same language as "can't afford".
				if locked then playErrorSound(); shakeButton(buyBtn); return end
				if tier.robux then pcall(function() game:GetService("MarketplaceService"):PromptGamePassPurchase(player,1860686821) end)
				elseif BuyStomachEvent then
					local coinsVal, ownedMax = 0, 0
					pcall(function()
						local ls=player:FindFirstChild("leaderstats")
						if ls then
							local c=ls:FindFirstChild("Coins"); if c then coinsVal=c.Value end
							local sm=ls:FindFirstChild("StomachMax"); if sm then ownedMax=sm.Value end
						end
					end)
					if tier.maxPower>ownedMax and coinsVal<tier.cost then
						playErrorSound()
						shakeButton(buyBtn)
					end
					pcall(function() BuyStomachEvent:FireServer(tier.maxPower, tier.cost) end)
				end
			end)
			pcall(refreshCard)
			player:GetAttributeChangedSignal("HighestSlot"):Connect(function() pcall(refreshCard) end)
			task.spawn(function()
				while true do
					task.wait(1)
					pcall(refreshCard)
				end
			end)
		end
	end

	-- maxPower -> {emoji, name} for the "Current: ..." readout. Derived from tierDefs (which
	-- IS StomachTiers.LIST) rather than typed out again: this was a literal seven-row table
	-- of the OLD tank sizes, and `if info then` means an unlisted size leaves the previous
	-- gut's name and icon on screen -- so after the six->twelve retier, buying a Dilo would
	-- have kept saying "Raptor Gut" and nothing would have complained.
	local stomachNames = {}
	for _, t in ipairs(tierDefs) do stomachNames[t.maxPower] = { t.emoji, t.name } end
	if StomachUpdateEvent then
		StomachUpdateEvent.OnClientEvent:Connect(function(newMax)
			pcall(function()
				local oldMax = stomachMax; stomachMax = tonumber(newMax) or stomachMax
				currentPower = math.min(currentPower, stomachMax)
				local info = stomachNames[stomachMax]
				if info then stomachEmoji = info[1]; stomachName = info[2] end
				local maxStr = stomachMax >= 9999 and "\xe2\x88\x9e" or tostring(stomachMax)
				currentStomachLabel.Text = "Current: " .. stomachName .. " (" .. maxStr .. " max power)"
				if updateStomachDisplay then updateStomachDisplay() end
				checkGutAfford()
				if ttlIcon then
					ttlIcon.Text = _G.GUT_EMOJI[stomachName] or ttlIcon.Text -- dino guts: emoji icon
					if ttlIconImg then ttlIconImg.Visible = false end
				end
			end)
		end)
	end
	stomachSideClick.MouseButton1Click:Connect(function()
		pcall(function()
			local ls=player:FindFirstChild("leaderstats"); if not ls then return end
			local sm=ls:FindFirstChild("StomachMax"); if not sm then return end
			local tierName2="Custom"
			for _,t in ipairs(tierDefs) do if t.maxPower==sm.Value then tierName2=t.name; break end end
			local maxStr=sm.Value>=9999 and "\xe2\x88\x9e" or tostring(sm.Value)
			currentStomachLabel.Text="Current: "..tierName2.." ("..maxStr.." max power)"
		end)
	end)
end)

--======================================================================
-- 5c) MORE+ POPUP  (opened by the MORE+ side button)
--     Three rows: Rebirth, Rewards, Pets. Each hands off to the system that owns
--     it -- OpenRebirth / _G.toggleSocialRewards / _G.togglePetHub -- and warns
--     rather than failing silently if that system is not loaded. Seasonal Pets and
--     Season Pass were removed; Daily Rewards was merged into Rewards (its DAILY
--     LOGIN section); Skin Crates moved INSIDE the Pet Hub (CRATES / TOKENS tabs).
--======================================================================
do
	local moreGui = Instance.new("ScreenGui"); moreGui.Name = "MoreMenuGui"; moreGui.ResetOnSpawn = false
	-- DisplayOrder 9, not 8. Any stale second "MoreMenuGui" baked into the place also uses 8,
	-- and at equal DisplayOrder the winner is whichever was created last -- so the old design
	-- can render OVER this one. 9 makes this one win outright.
	moreGui.DisplayOrder = 9; moreGui.Parent = PlayerGui
	-- LOAD-BEARING. repositionGUIs force-sets TextScaled = true on every TextLabel under
	-- PlayerGui. The dashboard is precise type -- 21px titles beside 13px descriptions --
	-- so without this opt-out every label rescales to fill its frame and the hierarchy
	-- collapses into same-size mush.
	moreGui:SetAttribute("NoTextSweep", true)

	-- Full-screen blocker so clicks can't reach the HUD behind the panel. It does NOT
	-- close the menu: a stray tap anywhere on screen must not shut a panel you are
	-- reading. The X button is the only way out.
	local catcher = mkButton(moreGui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 1, Visible = false, Active = true })

	-- 660x480 PANEL so the FINISHED MENU IS 700x520 -- the same footprint as the Pet Hub
	-- and the Wormhole. The old 196x206 pop-out beside the rail button showed 3 of its rows
	-- and buried the rest below the fold.
	--
	-- WHY NOT 700x520 LIKE THE OTHER TWO: this is the only one of the three wrapped in a
	-- JungleChrome bamboo shell, and fitShell() below builds that shell at PANEL SIZE + 40
	-- (20px of bamboo per side). At 700x520 the panel matched the hub on paper while
	-- rendering as a 740x560 object -- visibly the odd one out, which is the whole thing
	-- being fixed here. The number that has to match is the OUTER edge, so the panel gives
	-- back exactly what the shell adds.
	--
	-- Change this and the shell follows automatically (fitShell is bound to Size), but the
	-- 40 has to stay in step with the +40 below or the footprints drift apart again.
	local panel = mkFrame(moreGui, { Size = UDim2.new(0, 660, 0, 480), Position = UDim2.new(0.5, 0, 0.5, -16), -- hub-parity screen spot (-45 equivalent in this inset-ignoring gui)
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(122, 142, 82),
		Visible = false, Active = true, ZIndex = 2 })
	mkCorner(panel, 20); mkStroke(panel, Color3.fromRGB(40, 52, 38), 3)
	-- same jungle chrome the Stomach shop and Pet Hub use: bamboo shell behind the panel,
	-- olive panel fill. Applied through the shared module so all three stay identical.
	do
		local okJC, JC = pcall(function()
			return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10))
		end)
		if okJC and JC then pcall(function() JC.stylePanel(panel) end) end
		-- The bamboo frame is REBUILT at the panel's real size, not resized.
		--
		-- buildShell() is hard-coded to 740x560 and pins its rocks and leaves at absolute
		-- offsets (bottom row at y=544, corner knots at 724/544). Simply resizing that Frame
		-- shrank the tan backing and left the stonework scattered around the old footprint --
		-- a border wrapped around empty space. buildShellAround() lays the decoration out
		-- from w/h instead, so it hugs whatever the panel currently is.
		--
		-- It also has to follow POSITION (this panel sits 45px above centre, buildShell
		-- assumes dead centre) and VISIBILITY (the ScreenGui stays enabled while only
		-- `panel.Visible` toggles, so an unbound shell sits on screen from join onward).
		if okJC and JC and JC.buildShellAround then
			local lastW, lastH
			local function fitShell()
				local w = panel.Size.X.Offset + 40   -- 20px of bamboo on every side
				local h = panel.Size.Y.Offset + 40
				if w ~= lastW or h ~= lastH then     -- only rebuild when the SIZE actually changed
					lastW, lastH = w, h
					pcall(function() JC.buildShellAround(moreGui, w, h) end)
				end
				local shell = moreGui:FindFirstChild("JungleShell")
				if shell then
					shell.AnchorPoint = panel.AnchorPoint
					shell.Position    = panel.Position
					shell.Visible     = panel.Visible
				end
			end
			fitShell()
			for _, prop in ipairs({ "Visible", "Size", "Position", "AnchorPoint" }) do
				panel:GetPropertyChangedSignal(prop):Connect(fitShell)
			end
		end
	end

	local hdr = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Color3.fromRGB(26, 48, 30), ZIndex = 2 })
	mkCorner(hdr, 20)
	-- square patch over the header's bottom edge -- kills the lower rounding so the header
	-- meets the body flush instead of showing two pink slivers
	mkFrame(hdr, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), BackgroundColor3 = Color3.fromRGB(26, 48, 30), BorderSizePixel = 0, ZIndex = 2 })
	mkLabel(hdr, { Text = "MORE", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = Color3.fromRGB(255, 220, 0),
		Size = UDim2.new(0, 300, 0, 38), Position = UDim2.new(0, 20, 0, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	mkLabel(hdr, { Text = "Everything else lives here", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(232, 209, 158),
		Size = UDim2.new(0, 300, 0, 16), Position = UDim2.new(0, 22, 0, 46), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local moreX = mkButton(hdr, { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -52, 0, 16),
		BackgroundColor3 = Color3.fromRGB(210, 60, 55), Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	mkCorner(moreX, 10); mkStroke(moreX, Color3.new(0, 0, 0), 2)
	mkFrame(panel, { Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 0, 74),
		BackgroundColor3 = Color3.fromRGB(160, 200, 120), BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 3 })

	local entryScroll = Instance.new("ScrollingFrame")
	entryScroll.Name = "EntryList"
	entryScroll.BackgroundTransparency = 1
	entryScroll.BorderSizePixel = 0
	entryScroll.Position = UDim2.new(0, 16, 0, 82)
	entryScroll.Size = UDim2.new(1, -32, 1, -96)   -- 628 x 384 against the 660x480 panel
	entryScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	entryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	entryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y  -- measured from the cards, which are
	entryScroll.ScrollBarThickness = 6                      -- parented DIRECTLY here (no wrapper frame)
	entryScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0)
	entryScroll.ClipsDescendants = true
	entryScroll.ZIndex = 2
	entryScroll.Parent = panel

	-- Two INDEPENDENT dot groups. Claiming the crate must not clear the tasks dot and vice
	-- versa, so they are separate lists that happen to share one wiggle.
	local crateReadyDots, taskPendingDots = {}, {}
	local function mkDot(parent, group, xOff)
		local dot = Instance.new("Frame")
		dot.Name = "ReadyDot"
		dot.Size = UDim2.fromOffset(18, 18)
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, xOff or -2, 0, -2)
		dot.BackgroundColor3 = Color3.fromRGB(225, 50, 50)
		dot.ZIndex = 8
		dot.Visible = false
		dot.Parent = parent
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
		local bang = Instance.new("TextLabel")
		bang.BackgroundTransparency = 1; bang.Size = UDim2.fromScale(1, 1)
		bang.Font = Enum.Font.GothamBlack; bang.Text = "!"; bang.TextSize = 13
		bang.TextColor3 = Color3.new(1, 1, 1); bang.ZIndex = 9; bang.Parent = dot
		group[#group + 1] = dot
		return dot
	end
	local function mkCrateDot(parent) return mkDot(parent, crateReadyDots, -2) end

	--------------------------------------------------------------------
	-- CARD ICONS -- drawn, not typed.
	--
	-- These were emoji (ð etc.) rendered in Gotham, which has no glyphs for
	-- them, so every icon came out as tofu boxes. Roblox only renders emoji from its colour
	-- emoji font, and the UI fonts do not fall back to it -- so ANY emoji in a styled label
	-- is a tofu risk. Drawn from Frames instead: no font dependency, crisp at any scale, and
	-- no asset upload needed.
	--
	-- `mask` is the icon square's own fill, used to knock a gap out of the Rebirth ring.
	--------------------------------------------------------------------
	local ICON_INK = Color3.fromRGB(38, 30, 20)
	local function drawCardIcon(parent, kind, mask)
		local D = 62 -- the icon square is 62x62
		local function box(w, h, x, y, col, radius, rot)
			local f = mkFrame(parent, {
				Size = UDim2.fromOffset(w, h), Position = UDim2.new(0.5, x, 0.5, y),
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = col or ICON_INK,
				BorderSizePixel = 0, ZIndex = 7 })
			if rot then f.Rotation = rot end
			if radius then mkCorner(f, radius) end
			return f
		end
		local function ring(d, thick, col)
			local f = mkFrame(parent, {
				Size = UDim2.fromOffset(d, d), Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 7 })
			mkCorner(f, math.floor(d / 2)); mkStroke(f, col or ICON_INK, thick)
			return f
		end

		if kind == "rebirth" then
			-- a ring with a bite taken out, plus an arrowhead: the recycle/reset symbol
			ring(34, 5)
			box(14, 14, 11, -11, mask)                 -- mask the gap in the ring's top-right
			box(13, 13, 10, -12, ICON_INK, 2, 45)      -- arrowhead (a rotated square)
		elseif kind == "gift" then
			box(34, 22, 0, 7, ICON_INK, 3)             -- the box
			box(38, 9, 0, -6, ICON_INK, 2)             -- lid
			box(6, 22, 0, 7, mask)                     -- vertical ribbon gap
			box(9, 9, -6, -13, ICON_INK, 4)            -- bow, left loop
			box(9, 9, 6, -13, ICON_INK, 4)             -- bow, right loop
		elseif kind == "paw" then
			box(22, 18, 0, 7, ICON_INK, 9)             -- main pad
            for _, t in ipairs({ {-12,-6}, {-4,-12}, {5,-12}, {13,-6} }) do
				box(9, 11, t[1], t[2], ICON_INK, 5)    -- four toes
			end
		elseif kind == "crate" then
			box(36, 30, 0, 0, ICON_INK, 3)             -- the crate
			box(36, 6, 0, -4, mask)                    -- tape across
			box(6, 30, 0, 0, mask)                     -- tape down
		elseif kind == "lock" then
			box(22, 16, 0, 6, ICON_INK, 3)             -- body
			ring(18, 4); box(20, 10, 0, 6, mask)       -- shackle, lower half masked off
		elseif kind == "wormhole" then
			-- a portal: concentric rings around a centre dot
			ring(38, 4)
			ring(22, 4)
			box(8, 8, 0, 0, ICON_INK, 4)
		end
	end

	--------------------------------------------------------------------
	-- ENTRIES
	--
	-- `locked` marks a row whose backing system does not exist in this realm yet.
	-- It is rendered greyed and refuses the click rather than being wired to a
	-- guarded no-op -- a silent no-op looks identical to a working row until you
	-- tap it, which is the single easiest way to ship a broken menu.
	--------------------------------------------------------------------
	local MORE_ENTRIES = {
		{ order = 1, label = "Rebirth", desc = "Reset your progress for permanent multipliers.",
		  tint = Color3.fromRGB(90, 200, 255), icon = "rebirth", action = function()
			local rs = game:GetService("ReplicatedStorage")
			local sig = rs:FindFirstChild("OpenRebirth")
			if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenRebirth"; sig.Parent = rs end
			sig:Fire()
		end },
		-- REWARDS = the old "Daily Rewards" and "Free Rewards" rows, merged.
		--
		-- They were two rows for one habit, and the player had to already know they were
		-- different menus. Daily Rewards had no panel of its own either -- it claimed the
		-- crate outright -- so it now lives as the DAILY LOGIN section inside the rewards
		-- panel (SocialRewards.client.luau) alongside the FREE REWARDS rows.
		--
		-- Both dot groups ride this single row: readyDot for the crate, tasksDot kept for a
		-- daily-tasks system if one is ever added. They stay INDEPENDENT, so claiming the
		-- crate cannot clear the other badge.
		{ order = 2, label = "Rewards", desc = "Daily crate and free rewards, all in one place.",
		  tint = Color3.fromRGB(255, 175, 45), icon = "gift", readyDot = true, tasksDot = true,
		  action = function()
			if _G.toggleSocialRewards then _G.toggleSocialRewards()
			else warn("[Bootstrap] MORE+ -> Rewards: SocialRewards.client.luau not loaded") end
		end },
		-- WORMHOLE swapped in here from the left sidebar (the Pets button took its rail slot).
		-- Same OpenWormhole BindableEvent the side button used to fire; get-or-create it so
		-- the load order of the two client scripts never matters.
		{ order = 3, label = "Wormhole", desc = "Travel between islands and realms.",
		  tint = Color3.fromRGB(110, 90, 225), icon = "wormhole", action = function()
			local rs = game:GetService("ReplicatedStorage")
			local sig = rs:FindFirstChild("OpenWormhole")
			if not sig then sig = Instance.new("BindableEvent"); sig.Name = "OpenWormhole"; sig.Parent = rs end
			sig:Fire()
		end },
		-- Skin Crates card REMOVED from the HUD menu (by request): crates are reached
		-- through the Pet Hub only -- its CRATES / TOKENS tabs route to
		-- _G.toggleSkinCrates(true, tab). The crate panel itself is untouched.
		-- Seasonal Pets and Season Pass removed. Seasonal Pets was never reachable here (its
		-- locker lives inside the source game's CoreClient), and Season Pass is gone by
		-- request. SeasonPass.client/server are still installed and still expose
		-- _G.toggleSeasonPass -- nothing in the HUD calls it now.
	}
	table.sort(MORE_ENTRIES, function(a, b) return (a.order or 99) < (b.order or 99) end)

	-- Sized against the 628x384 content box (panel 660x480, less 32 wide / 96 tall of inset):
	--   columns  304 + 20 gutter + 304  = 628
	--   4 cards  2 rows x 116 + 20      = 252, so there is room to spare
	--
	-- THESE TRACK THE PANEL WIDTH BY HAND. The cards are positioned in absolute pixels, so
	-- they do NOT follow the panel the way the ScrollingFrame above does. When the panel
	-- shrank from 700 to 660 (to make room for the bamboo shell and land the finished menu
	-- on the hub's 700x520), 324+20+324 = 668 no longer fit in 628 and the right-hand column
	-- ran off the edge. Move the panel and these two lines move with it or the columns break.
	-- Positioned by hand rather than by a UIGridLayout, because the FULL_* path lets one
	-- card span both columns and a grid cannot make one cell double-width.
	-- NOTE nothing sets `full = true` any more (that was the Season Pass card), so FULL_W/
	-- FULL_H/FULL_Y and the `e.full` branches below are currently unused. They are kept
	-- because a future full-width row is one flag away; FULL_Y = 342 assumes SIX half-width
	-- cards above it, so re-check it if you add one.
	local CARD_W, CARD_H, GAP = 304, 116, 20 -- 2 x 304 + 20 = 628, the content box exactly (was 324, sized for the old 700 panel)
	local FULL_W, FULL_H, FULL_Y = 628, 82, 342 -- FULL_W spans both columns; FULL_Y still assumes the old 424-tall box, so re-check it if a full-width card is ever re-enabled

	local halfIdx = 0
	for _, e in ipairs(MORE_ENTRIES) do
		local w = e.full and FULL_W or CARD_W
		local h = e.full and FULL_H or CARD_H
		local cx, cy
		if e.full then
			cx, cy = FULL_W / 2, FULL_Y + h / 2
		else
			cx = (halfIdx % 2) * (CARD_W + GAP) + CARD_W / 2
			cy = math.floor(halfIdx / 2) * (CARD_H + GAP) + h / 2
			halfIdx += 1
		end

		-- anchored from the CENTRE so the hover scale grows evenly on all four sides
		-- instead of shoving the card down and right
		local row = mkButton(entryScroll, { Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(cx, cy),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = e.locked and Color3.fromRGB(88, 96, 70) or Color3.fromRGB(96, 116, 66),
			Text = "", AutoButtonColor = false, ClipsDescendants = true, ZIndex = 3 })
		mkCorner(row, 16); mkStroke(row, Color3.fromRGB(40, 52, 38), 2)

		-- gloss: always on, this is what makes the tile read as a panel rather than a flat block
		local gloss = mkFrame(row, { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4 })
		mkCorner(gloss, 16)
		do local g = Instance.new("UIGradient"); g.Rotation = 90
			g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.84), NumberSequenceKeypoint.new(1, 1) })
			g.Parent = gloss end

		-- shine: parked off the left edge, swept across on hover
		local shine = mkFrame(row, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5 })
		mkCorner(shine, 16)
		local shineGrad = Instance.new("UIGradient"); shineGrad.Rotation = 18
		shineGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.74), NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1) })
		shineGrad.Offset = Vector2.new(-1, 0); shineGrad.Parent = shine

		local icon = mkFrame(row, { Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = e.locked and Color3.fromRGB(92, 96, 74) or e.tint, ZIndex = 6 })
		mkCorner(icon, 14); mkStroke(icon, Color3.fromRGB(40, 52, 38), 2)
		drawCardIcon(icon, e.icon, e.locked and Color3.fromRGB(92, 96, 74) or e.tint)

		mkLabel(row, { Text = e.label, Font = Enum.Font.GothamBold, TextSize = 21,
			TextColor3 = e.locked and Color3.fromRGB(196, 186, 150) or Color3.new(1, 1, 1),
			Size = UDim2.new(0, w - 126, 0, 24), Position = UDim2.new(0, 92, 0, e.full and 14 or 18),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 })
		mkLabel(row, { Text = e.locked and (e.lockNote or "Not in this realm yet.") or e.desc, Font = Enum.Font.Gotham, TextSize = 13,
			TextColor3 = Color3.fromRGB(232, 209, 158),
			Size = UDim2.new(0, w - 126, 0, e.full and 24 or 36), Position = UDim2.new(0, 92, 0, e.full and 42 or 44),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 6 })
		mkLabel(row, { Text = "\xE2\x9D\xAF", Font = Enum.Font.FredokaOne, TextSize = 20,
			TextColor3 = Color3.fromRGB(160, 200, 120), Size = UDim2.new(0, 24, 1, 0),
			Position = UDim2.new(0, w - 34, 0, 0), ZIndex = 6 })

		-- badges sit SIDE BY SIDE, not stacked -- they are independent, and stacking hid
		-- whichever one drew second
		if e.readyDot then mkDot(row, crateReadyDots, -10) end
		if e.tasksDot then mkDot(row, taskPendingDots, -32) end

		if not e.locked then
			local scale = Instance.new("UIScale"); scale.Parent = row
			row.MouseEnter:Connect(function()
				TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.03 }):Play()
				shineGrad.Offset = Vector2.new(-1, 0)
				TweenService:Create(shineGrad, TweenInfo.new(0.5), { Offset = Vector2.new(1, 0) }):Play()
			end)
			row.MouseLeave:Connect(function()
				TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
			row.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false); pcall(e.action) end)
		end
	end

	--------------------------------------------------------------------
	-- SHRINK THE PANEL TO ITS CONTENT
	--
	-- The 700x520 box was authored for SEVEN rows. With four, the bottom ~210px was
	-- dead space and the grid floated in the top half of an oversized panel. Measure
	-- what was actually laid out and size the panel to header + grid + even padding.
	--
	-- Computed rather than hardcoded so this stays correct if rows are added or
	-- removed later. The bamboo shell tracks panel.Size (see the fitShell binding
	-- above), so it resizes with this instead of framing empty space.
	--------------------------------------------------------------------
	do
		local halfCount, hasFull = 0, false
		for _, e in ipairs(MORE_ENTRIES) do
			if e.full then hasFull = true else halfCount += 1 end
		end
		local rows = math.ceil(halfCount / 2)
		local gridH = rows > 0 and (rows * CARD_H + (rows - 1) * GAP) or 0
		if hasFull then gridH = math.max(gridH, FULL_Y + FULL_H) end

		local TOP = 82   -- header (72) + divider + breathing room, matches entryScroll's Y
		local BOT = 38   -- HUB PARITY: with two 116px rows + 20px gutter this lands the panel at the hub's 700x372
		entryScroll.Size = UDim2.new(1, -32, 0, gridH)
		panel.Size = UDim2.new(0, 700, 0, TOP + gridH + BOT)
	end

	mkCrateDot(stomachSideFrame) -- "!" dot on the MORE+ button itself
	local moreWiggling, moreWiggleTween = false, nil
	local function stopMoreWiggle()
		if not moreWiggling then return end
		moreWiggling = false
		if moreWiggleTween then pcall(function() moreWiggleTween:Cancel() end); moreWiggleTween = nil end
		stomachSideFrame.Rotation = 0
	end
	local function startMoreWiggle()
		if moreWiggling then return end
		moreWiggling = true
		stomachSideFrame.Rotation = -8
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		moreWiggleTween = TweenService:Create(stomachSideFrame, info, { Rotation = 8 })
		moreWiggleTween:Play()
	end
	task.spawn(function()
		while true do
			-- two independent predicates feeding two independent dot groups; either one
			-- wiggles the rail button
			local ready   = (_G.crateIsClaimable  and _G.crateIsClaimable())  == true
			local pending = (_G.dailyTasksPending and _G.dailyTasksPending()) == true
			for _, d in ipairs(crateReadyDots)  do d.Visible = ready end
			for _, d in ipairs(taskPendingDots) do d.Visible = pending end
			if ready or pending then startMoreWiggle() else stopMoreWiggle() end
			task.wait(1)
		end
	end)

	-- No repositioning: the panel is centred, so it opens in the same place regardless of
	-- where repositionGUIs left the rail button on this device.
	setMoreOpen = function(open)
		moreOpenState = open and true or false
		panel.Visible = moreOpenState
		catcher.Visible = moreOpenState
	end
	-- deliberately NO catcher click-to-close: a stray tap must not shut the panel
	moreX.MouseButton1Click:Connect(function() playUIClick(); setMoreOpen(false) end)
end

-- (Pets inventory is the full Pet Hub built in PetHub.client.luau. The LEFT sidebar's
--  Pets button was replaced by STOMACH, so the Pet Hub is reached via MORE+ -> Pets,
--  which calls _G.togglePetHub (with the PetInvToggle BindableEvent as a fallback).
--  Skin Crates open from INSIDE the hub -- its CRATES / TOKENS tabs.)

--======================================================================
-- TOP-MIDDLE: current island name + current task (stacked)
--======================================================================
do
	local RSvc = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")
	-- THE 13 ISLANDS. Islands 1-8 have quests; 9-13 are blank (scenery only, no
	-- NPC / no quest), so their `task` is "" and the task banner hides itself.
	-- Island NUMBER is the model name in Workspace ("island8"), NOT the tower slot
	-- -- IslandLayout.server.luau maps number -> slot (quest / no-quest alternating).
	local ISLANDS = {
		-- QUEST islands
		[1]  = { name = "Nesting Nook",     task = "Bring the lost eggs to the nest" },
		[2]  = { name = "Fern Frontier",    task = "Find and hatch the Triceratops egg" },
		[3]  = { name = "Fossil Frontier",  task = "Dig up the ancient fossils to find the egg" },
		[4]  = { name = "Coastal Crossing", task = "Fish the ButterLake to hatch a Megalodon" },
		[5]  = { name = "Misty Mire",       task = "Swat the mosquitos, then feed the egg!" },
		[6]  = { name = "Redwood Ridge",    task = "Explore Redwood Ridge" },
		[7]  = { name = "Raptor Ridge",     task = "Carry meat to the nest -- feed it 5 pieces!" },
		-- VOLCANIC VISTA (island11) = THE ENDING ISLAND, pinned to the TOP tower slot
		-- (slot 13, see IslandLayout.server.luau). It owns the volcano / geyser FINALE
		-- quest and grants the T-Rex. The geyser quest USED to live on island8 -- it
		-- moved here, so island8 is now a BLANK island named "Inferno Isle".
		[11] = { name = "Volcanic Vista",   task = "Plug all 6 geysers before the volcano erupts!" },
		-- BLANK islands (no code, no quest) -- name only, empty task
		[8]  = { name = "Inferno Isle",     task = "" },  -- volcanic (NO quest -- it moved to island11)
		[9]  = { name = "Jungle Junction",  task = "" },  -- jungle
		[10] = { name = "Petrified Pass",   task = "" },  -- desert
		[12] = { name = "Sunscorch Sands",  task = "" },  -- desert
		[13] = { name = "Glacier Gulch",    task = "" },  -- snow / glacier
	}
	-- which island the player is standing on: XZ footprint match -> else nearest (islands are island1..island13)
	local function currentIslandNum()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return 1 end
		local pos = hrp.Position
		local best, bestD = nil, math.huge
		for i = 1, 13 do
			local isl = Workspace:FindFirstChild("island" .. i)
			if isl then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and cf and size then
					local dx, dz = pos.X - cf.Position.X, pos.Z - cf.Position.Z
					if math.abs(dx) <= size.X/2 and math.abs(dz) <= size.Z/2 then return i end
					local d = dx*dx + dz*dz
					if d < bestD then bestD = d; best = i end
				end
			end
		end
		return best or 1
	end

	local islandGui = Instance.new("ScreenGui")
	islandGui.Name = "IslandBanner"; islandGui.ResetOnSpawn = false; islandGui.IgnoreGuiInset = true
	islandGui.DisplayOrder = 40; islandGui.Parent = PlayerGui

	local holder = mkFrame(islandGui,{Name="Holder",Size=UDim2.fromOffset(440,78),Position=UDim2.new(0.5,0,0,8),AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,ZIndex=2})

	-- island NAME banner (wood)
	local nameBar = mkFrame(holder,{Name="IslandName",Size=UDim2.fromOffset(300,42),Position=UDim2.new(0.5,0,0,0),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=WOOD_DARK,ZIndex=3})
	mkCorner(nameBar,14); mkStroke(nameBar,Color3.fromRGB(40,26,14),3)
	glossGradient(nameBar, WOOD_DARK); addShadow(nameBar,14); addInnerHighlight(nameBar,14)
	-- Foliage removed. On a 300x42 bar the two corner vines ate both ends of the island
	-- name, which is the one thing this banner exists to show.
	local nameLbl = mkLabel(nameBar,{Name="Text",Text="Nesting Nook",TextColor3=Color3.new(1,1,1),TextScaled=true,Size=UDim2.new(1,-56,1,-8),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,ZIndex=20})
	styleText(nameLbl)
	do local c=Instance.new("UITextSizeConstraint"); c.MaxTextSize=26; c.Parent=nameLbl end

	-- TASK banner (parchment, below)
	local taskBar = mkFrame(holder,{Name="Task",Size=UDim2.fromOffset(430,30),Position=UDim2.new(0.5,0,0,46),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=PARCHMENT,ZIndex=3})
	mkCorner(taskBar,12); mkStroke(taskBar,WOOD_DARK,2)
	glossGradient(taskBar, PARCHMENT); addShadow(taskBar,12); addInnerHighlight(taskBar,12)
	local taskLbl = mkLabel(taskBar,{Name="Text",Text="Go Talk To The Researcher To Accept The Quest",TextColor3=Color3.fromRGB(60,42,20),Font=JUNGLE_FONT,TextScaled=true,Size=UDim2.new(1,-16,1,-6),Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1,ZIndex=20})
	do local c=Instance.new("UITextSizeConstraint"); c.MaxTextSize=17; c.Parent=taskLbl end

	-- live wiring: island name + task (+ egg progress from the quest folder)
	task.spawn(function()
		local nook = RSvc:WaitForChild("NestingNook", 30)
		local total = nook and nook:WaitForChild("TotalEggs", 5)
		local got = nook and nook:WaitForChild("EggsReturned", 5)
		local function refresh()
			local n = currentIslandNum()
			local data = ISLANDS[n] or { name = "Island " .. n, task = "" }
			nameLbl.Text = data.name
			local txt = data.task
			if n == 1 then
				if not player:GetAttribute("NestingNookQuestClaimed") then
					txt = "Go Talk To The Researcher To Accept The Quest"
				elseif total and got then
					if total.Value > 0 and got.Value >= total.Value then
						txt = "All eggs returned - quest complete!"
					else
						txt = ("%s  (%d/%d)"):format(data.task, got.Value, total.Value)
					end
				end
			elseif n == 3 then
				if not player:GetAttribute("DigQuestAccepted") then
					txt = "Go Talk To The Digger To Accept The Quest"
				else
					txt = "Dig up the ancient fossils to find the egg!"
				end
			elseif n == 2 or n == 4 or n == 5 or n == 6 or n == 7 or n == 11 then
				-- other QUEST islands (11 = Volcanic Vista, the geyser finale -- it used
				-- to be 8, but that quest moved and island8 is a blank island now):
				-- direct the player to the Researcher until they accept (Island<N>QuestAccepted)
				if not player:GetAttribute("Island" .. n .. "QuestAccepted") then
					txt = "Go Talk To The Researcher To Accept The Quest"
				else
					txt = data.task
				end
			end
			taskLbl.Text = txt
			-- blank islands (9-13) have no quest -> hide the task banner entirely
			-- rather than show an empty parchment bar under the island name.
			taskBar.Visible = (txt ~= "")
		end
		refresh()
		player:GetAttributeChangedSignal("NestingNookQuestClaimed"):Connect(refresh)
		player:GetAttributeChangedSignal("DigQuestAccepted"):Connect(refresh)
		for _, i in ipairs({2,4,5,6,7,11}) do
			player:GetAttributeChangedSignal("Island" .. i .. "QuestAccepted"):Connect(refresh)
		end
		player:GetAttributeChangedSignal("CurrentIsland"):Connect(refresh)
		player:GetAttributeChangedSignal("Island"):Connect(refresh)
		if got then got.Changed:Connect(refresh) end
		if total then total.Changed:Connect(refresh) end
		-- island is detected by position (no attribute fires while walking), so re-check periodically
		task.spawn(function() while true do refresh(); task.wait(0.5) end end)
	end)
end

print("[HUDClone] all on-screen HUD components built: Coins, Settings, Right Stats Panel, Left Sidebar, Premium Shop, Stomach Shop, MORE+ menu, Island Banner")


-- ===== Daily Rewards client (folded into Bootstrap; standalone client file would not sync) =====
;(function()
--!nonstrict
-- CrateClient (StarterPlayerScripts/CrateClient)
-- Client presentation for the Mystery Meteor Crate. The server (CrateService) is the sole
-- authority — this script only:
--   * Mirrors lastCrateClaim from the state snapshot to compute LOCAL readiness, exposed as
--     _G.crateIsClaimable so the existing More menu (CoreClient) drives the ready "!" dot.
--   * The live entry point is the "Daily Rewards" row in the existing in-game More menu, which
--     fires the OpenMeteorCrate BindableEvent (this script has NO HUD button of its own).
--   * Shows a pet picker (which OWNED pet receives the levels), then ClaimCrate:InvokeServer(petId)
--     and plays the crack-open reveal of the result (rarity + "+N Levels" + "Lv X -> Y").
--   * Also reveals the dev /crate result pushed via CrateResult (no tap needed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== INLINED Constants (was Shared/Constants) — this file is SELF-CONTAINED, no Shared folder needed =====
-- These MUST stay identical to the server bundle (DailyRewards_Server) — both sides roll/clamp the same.
local Constants = {
	CRATE = {
		COOLDOWN_SECONDS = 28800, -- 8 hours between free claims
		FALLBACK_COINS = 500,     -- coins when every owned pet is maxed
		PET_MAX_LEVEL = 25,
		RARITY_WEIGHTS = { Uncommon = 55, Rare = 28, Epic = 13, Mythical = 4 },
		RARITY_ORDER = { "Uncommon", "Rare", "Epic", "Mythical" },
		RARITY_LEVELS = { Uncommon = 1, Rare = 2, Epic = 4, Mythical = 6 },
		RARITY_COLORS = {
			Uncommon = Color3.fromRGB(150, 160, 172),
			Rare     = Color3.fromRGB(70, 140, 255),
			Epic     = Color3.fromRGB(175, 90, 240),
			Mythical = Color3.fromRGB(255, 200, 60),
		},
	},
}

-- ===== INLINED Remotes shim (was Shared/Remotes) — client side of the StateRemotes snapshot stream =====
local Remotes = {}
do
	local FOLDER_NAME, STATE_CHANGED, REQUEST_STATE = "StateRemotes", "StateChanged", "RequestState"
	local function getFolder()
		return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) or ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	local function getRemote(name)
		local folder = getFolder()
		return folder:WaitForChild(name, 30) or folder:WaitForChild(name)
	end
	function Remotes.getStateChanged() return getRemote(STATE_CHANGED) end
	function Remotes.getRequestState() return getRemote(REQUEST_STATE) end
end

local CRATE = Constants.CRATE

-- ===== OPEN TRIGGER (connected FIRST, before any blocking WaitForChild) =====
-- The More menu's "Daily Rewards" row fires ReplicatedStorage/OpenMeteorCrate. We create + connect
-- that listener immediately so a row tap is ALWAYS received on the correct shared instance, even if
-- the crate remotes below are still replicating. `attemptOpen` is forward-declared and assigned far
-- below once everything is built; until then a tap is a harmless no-op (logged).
local attemptOpen -- forward declaration (assigned near the bottom)
local OpenMeteorCrate = ReplicatedStorage:FindFirstChild("OpenMeteorCrate")
if not OpenMeteorCrate then
	OpenMeteorCrate = Instance.new("BindableEvent")
	OpenMeteorCrate.Name = "OpenMeteorCrate"
	OpenMeteorCrate.Parent = ReplicatedStorage
end
OpenMeteorCrate.Event:Connect(function()
	if attemptOpen then
		attemptOpen()
	else
		warn("[CrateClient] Daily Rewards tapped before the crate finished loading — try again in a moment")
	end
end)
print("[CrateClient] OpenMeteorCrate listener connected")

-- ===== remotes ===== (timeout + warn so a missing remote is diagnosable instead of an infinite hang)
local crateRemotes = ReplicatedStorage:WaitForChild("CrateRemotes", 30)
if not crateRemotes then
	warn("[CrateClient] CrateRemotes folder never appeared — is CrateService running on the server?")
	crateRemotes = ReplicatedStorage:WaitForChild("CrateRemotes")
end
local ClaimCrate = crateRemotes:WaitForChild("ClaimCrate")
local CrateResult = crateRemotes:WaitForChild("CrateResult")
local GetOwnedPets = crateRemotes:WaitForChild("GetOwnedPets")
local PreviewRoll = crateRemotes:WaitForChild("PreviewRoll")

-- petId -> displayName cache, refreshed whenever we fetch the owned-pet list (picker / reveal).
local petNameById = {}
local function fetchOwnedPets()
	local ok, list = pcall(function() return GetOwnedPets:InvokeServer() end)
	if ok and type(list) == "table" then
		for _, p in ipairs(list) do
			if p.petId then petNameById[p.petId] = p.displayName or p.petId end
		end
		return list
	end
	return {}
end

-- ===== local readiness mirror =====
local lastCrateClaim = 0

local function isClaimable()
	if lastCrateClaim == 0 then return true end
	return os.time() >= lastCrateClaim + CRATE.COOLDOWN_SECONDS
end
-- Exposed so the existing More menu (CoreClient) can drive the ready "!" dot on the Daily Rewards
-- row + the MORE button without owning the crate snapshot.
_G.crateIsClaimable = isClaimable

-- Snapshot wiring runs in its own thread so a slow StateRemotes replication can NEVER stall the
-- rest of this script (which must reach the OpenMeteorCrate connection so row taps open the crate).
task.spawn(function()
	Remotes.getStateChanged().OnClientEvent:Connect(function(snap)
		if type(snap) == "table" and snap.lastCrateClaim ~= nil then
			lastCrateClaim = tonumber(snap.lastCrateClaim) or 0
		end
	end)
	-- On-ready handshake: ask the server for a fresh snapshot.
	pcall(function() Remotes.getRequestState():FireServer() end)
end)

-- ===== sounds (pcall-guarded, 5s Debris cleanup) =====
local function playSound(id, volume)
	if not id then return end -- a nil id means "no sound" (used to disable SND_TAP in the daily-rewards crate)
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.Volume = volume or 0.6
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 5)
	end)
end

local SND_TAP        = nil             -- disabled: no tap/eat sound in the daily-rewards crate (was 103794849233173)
local SND_SHAKE      = 9116367700       -- meteor shake begins (vol 0.5)
local SND_CRACK      = 199578212        -- cracks form (vol 0.6)
local SND_BURST      = 1837709104       -- burst, non-Legendary (vol 0.85)
local SND_BURST_LEG  = 1839687588       -- burst, Legendary, larger (vol 0.85)


----------------------------------------------------------------------------------------
-- Reveal flow
----------------------------------------------------------------------------------------
local revealGui = Instance.new("ScreenGui")
revealGui.Name = "MeteorCrateReveal"
revealGui.ResetOnSpawn = false
revealGui.IgnoreGuiInset = true
revealGui.DisplayOrder = 100 -- match the shop ScreenGuis (DisplayOrder 100) so it layers above the HUD the same way
revealGui.Enabled = false
revealGui.Parent = playerGui

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 1
dim.Parent = revealGui

local revealing = false
local opening = false -- declared here (above freshReveal) so the reveal teardown can clear it

-- showMessage(text): brief TOP-CENTER banner (used for the no-pets case "Unlock A Pet To Receive
-- Levels"). Independent of the reveal flow; auto-dismisses. Never consumes the crate timer. Sits at the
-- top-middle of the screen (out of the player's way), like the other event banners.
local function showMessage(text)
	if revealing then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MeteorCrateMessage"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 12) -- top-middle, just below the top edge (out of the player's way)
	frame.Size = UDim2.fromOffset(360, 70)
	frame.BackgroundColor3 = Color3.fromRGB(26, 28, 42)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 16); fc.Parent = frame
	local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(255, 200, 60); fs.Thickness = 2; fs.Transparency = 1; fs.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextTransparency = 1
	label.Text = text
	label.Parent = frame
	local lp = Instance.new("UIPadding"); lp.PaddingLeft = UDim.new(0, 14); lp.PaddingRight = UDim.new(0, 14); lp.Parent = label
	TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 0.1 }):Play()
	TweenService:Create(fs, TweenInfo.new(0.2), { Transparency = 0 }):Play()
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(1.9, function()
		TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(fs, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		Debris:AddItem(gui, 0.5)
	end)
end

-- Build + animate the burst (flash + shards + rings; bigger for Legendary).
local function playBurst(isLegendary)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 0.1
	flash.ZIndex = 5
	flash.Parent = revealGui
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(0, 0)
	center.BackgroundTransparency = 1
	center.ZIndex = 6
	center.Parent = revealGui
	Debris:AddItem(center, 1.2)

	local ringCount = isLegendary and 3 or 2
	local maxRing = isLegendary and 520 or 360
	for i = 1, ringCount do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromOffset(40, 40)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 6
		ring.Parent = center
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local rs = Instance.new("UIStroke")
		rs.Color = isLegendary and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(180, 200, 255)
		rs.Thickness = 5
		rs.Parent = ring
		local sz = maxRing + i * 60
		TweenService:Create(ring, TweenInfo.new(0.5 + i * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(sz, sz) }):Play()
		TweenService:Create(rs, TweenInfo.new(0.5 + i * 0.08), { Transparency = 1 }):Play()
	end

	local shardCount = isLegendary and 18 or 10
	for i = 1, shardCount do
		local shard = Instance.new("Frame")
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Position = UDim2.fromScale(0.5, 0.5)
		shard.Size = UDim2.fromOffset(10, 10)
		shard.BackgroundColor3 = isLegendary and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(200, 210, 230)
		shard.ZIndex = 6
		shard.Parent = center
		local ang = (i / shardCount) * math.pi * 2
		local dist = (isLegendary and 320 or 220) + (i % 3) * 30
		TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		}):Play()
	end
end

-- Build the reveal card for a result and wire its button. closeFn tears the whole reveal down.
--   kind == "levels": rarity header, the pet that leveled, "+N Levels", "Lv X -> Y".
--   kind == "coins" : COINS! card (all owned pets maxed) -> AWESOME! only.
-- Forward-declared here (defined further down, in the icon-helper section) so the result card can
-- reuse the SAME pet avatar as the picker rows.
local drawPetIcon, petModelToViewport

local function buildCard(result, closeFn)
	local isCoins = (result.kind == "coins")
	local rarity = (not isCoins) and result.rarity or nil
	local rarityColor = (rarity and CRATE.RARITY_COLORS[rarity]) or Color3.fromRGB(255, 200, 60)
	local petName = (not isCoins) and (petNameById[result.petId] or result.petId) or nil
	local levelsAdded = result.levelsAdded or 0
	local newLevel = result.newLevel or 0
	local oldLevel = math.max(0, newLevel - levelsAdded)

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.42) -- raised above center so the bottom HUD never covers it
	card.Size = UDim2.fromOffset(320, 420)
	card.BackgroundColor3 = Color3.fromRGB(126, 146, 86) -- olive (matches Shop + Pet Hub panel)
	card.ZIndex = 10
	card.Parent = revealGui
	-- soft drop shadow — parented to revealGui BEHIND the card (NOT as a child of the card: the card has
	-- a UIListLayout, which would lay these big frames out in its content column and shove the reward
	-- content off-screen — that was the "popup never appears" bug).
	for i, sp in ipairs({ 70, 48, 28 }) do
		local sh = Instance.new("Frame"); sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Position = UDim2.new(0.5, 0, 0.42, 6); sh.Size = UDim2.fromOffset(320 + sp, 420 + sp)
		sh.BackgroundColor3 = Color3.fromRGB(0, 12, 44); sh.BackgroundTransparency = ({ 0.86, 0.74, 0.58 })[i]
		sh.BorderSizePixel = 0; sh.ZIndex = 9; sh.Parent = revealGui
		local shc = Instance.new("UICorner"); shc.CornerRadius = UDim.new(0, 30); shc.Parent = sh
	end
	local cardCorner = Instance.new("UICorner"); cardCorner.CornerRadius = UDim.new(0, 24); cardCorner.Parent = card
	local cardGrad = Instance.new("UIGradient"); cardGrad.Rotation = 90 -- olive top -> bottom (Pet Hub OliveGrad)
	cardGrad.Color = ColorSequence.new(Color3.fromRGB(126, 146, 86), Color3.fromRGB(118, 138, 80)); cardGrad.Parent = card
	local cardStroke = Instance.new("UIStroke"); cardStroke.Color = Color3.fromRGB(40, 52, 38); cardStroke.Thickness = 3; cardStroke.Parent = card -- dark olive border (Pet Hub)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18); pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18); pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = card

	-- Rarity / reward header.
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 30)
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 24
	header.ZIndex = 11
	header.LayoutOrder = 1
	if isCoins then
		header.Text = "COINS!"
		header.TextColor3 = Color3.fromRGB(255, 210, 70)
	else
		header.Text = string.upper(rarity)
		header.TextColor3 = Color3.fromRGB(126, 217, 87) -- lime rarity (#7ed957)
	end
	header.Parent = card

	-- Icon: coin tile for the coin reward; for a level grant, the SAME avatar as the picker rows —
	-- the real in-game pet model in a ViewportFrame (spinning), vector-icon fallback if it can't clone.
	local iconHolder = Instance.new("Frame")
	iconHolder.BackgroundTransparency = 1
	iconHolder.Size = UDim2.fromOffset(140, 140)
	iconHolder.ZIndex = 11
	iconHolder.LayoutOrder = 2
	iconHolder.Parent = card
	if isCoins then
		local tile = Instance.new("TextLabel")
		tile.Size = UDim2.fromOffset(132, 132)
		tile.Position = UDim2.fromScale(0.5, 0.5)
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Font = Enum.Font.GothamBlack
		tile.TextScaled = true
		tile.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		tile.Text = "💰"
		tile.TextColor3 = Color3.fromRGB(80, 60, 10)
		tile.ZIndex = 11
		tile.Parent = iconHolder
		local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 16); tc.Parent = tile
	else
		-- glossy blue "radial-glow" square holding the spinning real pet model, ringed with sparkles
		local avatar = Instance.new("Frame")
		avatar.Size = UDim2.fromOffset(132, 132)
		avatar.Position = UDim2.fromScale(0.5, 0.5)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.BackgroundColor3 = Color3.fromRGB(70, 150, 250)
		avatar.ClipsDescendants = true
		avatar.ZIndex = 11
		avatar.Parent = iconHolder
		local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 22); ac.Parent = avatar
		local ast = Instance.new("UIStroke"); ast.Color = Color3.fromRGB(255, 255, 255); ast.Thickness = 2; ast.Parent = avatar
		local ag = Instance.new("UIGradient"); ag.Rotation = 90
		ag.Color = ColorSequence.new(Color3.fromRGB(96, 176, 255), Color3.fromRGB(28, 96, 206)); ag.Parent = avatar
		-- soft radial glow disc behind the model (bright center)
		local glow = Instance.new("Frame"); glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.fromScale(0.86, 0.86); glow.BackgroundColor3 = Color3.fromRGB(192, 226, 255)
		glow.BackgroundTransparency = 0.5; glow.BorderSizePixel = 0; glow.ZIndex = 11; glow.Parent = avatar
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1, 0); gc.Parent = glow
		local petObj = { petId = result.petId, displayName = petName }
		if not petModelToViewport(avatar, petObj) then
			drawPetIcon(avatar, petName) -- fallback: code-drawn vector icon
		end
		-- lime / cyan sparkle dots over the glow square
		local LIME, CYAN = Color3.fromRGB(126, 217, 87), Color3.fromRGB(94, 198, 255)
		for _, sp in ipairs({ {0.16, 0.18, 5, LIME}, {0.84, 0.24, 4, CYAN}, {0.22, 0.82, 4, CYAN}, {0.82, 0.80, 4.5, LIME} }) do
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.fromScale(sp[1], sp[2]); s.Size = UDim2.fromOffset(sp[3] * 2, sp[3] * 2)
			s.BackgroundColor3 = sp[4]; s.BackgroundTransparency = 0.05
			s.BorderSizePixel = 0; s.ZIndex = 14; s.Parent = avatar
			local scn = Instance.new("UICorner"); scn.CornerRadius = UDim.new(1, 0); scn.Parent = s
		end
	end

	-- Name: pet name (level grant) or coins amount.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 22
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.ZIndex = 11
	nameLabel.LayoutOrder = 3
	nameLabel.Text = isCoins and (tostring(result.coins) .. " Coins") or tostring(petName)
	nameLabel.Parent = card

	if not isCoins then
		-- "+N Levels" line.
		local gain = Instance.new("TextLabel")
		gain.BackgroundTransparency = 1
		gain.Size = UDim2.new(1, 0, 0, 26)
		gain.Font = Enum.Font.GothamBlack
		gain.TextSize = 24
		gain.TextColor3 = Color3.fromRGB(126, 217, 87) -- large lime (#7ed957)
		gain.ZIndex = 11
		gain.LayoutOrder = 4
		gain.Text = "+" .. tostring(levelsAdded) .. (levelsAdded == 1 and " Level" or " Levels")
		gain.Parent = card
		local gainGlow = Instance.new("UIStroke"); gainGlow.Color = Color3.fromRGB(126, 217, 87)
		gainGlow.Thickness = 2; gainGlow.Transparency = 0.35; gainGlow.Parent = gain -- lime glow

		-- "Lv X -> Y" line.
		local lv = Instance.new("TextLabel")
		lv.BackgroundTransparency = 1
		lv.Size = UDim2.new(1, 0, 0, 22)
		lv.Font = Enum.Font.GothamSemibold
		lv.TextSize = 17
		lv.TextColor3 = Color3.fromRGB(188, 234, 255) -- light blue
		lv.ZIndex = 11
		lv.LayoutOrder = 5
		lv.Text = "Lv " .. tostring(oldLevel) .. " → " .. tostring(newLevel)
		lv.Parent = card
	end

	-- Buttons. Coins -> AWESOME! only. Levels -> EQUIP NOW (equip the pet that leveled) + CLOSE.
	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, 46)
	btnRow.ZIndex = 11
	btnRow.LayoutOrder = 6
	btnRow.Parent = card
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = btnRow

	-- glossy beveled cartoon button: white->grey top-lit gradient + a darker rounded stroke
	local function makeBtn(text, color, strokeCol, order, width)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(width or 130, 44)
		b.BackgroundColor3 = color
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Text = text
		b.ZIndex = 12
		b.LayoutOrder = order
		b.Parent = btnRow
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = b
		local bg = Instance.new("UIGradient"); bg.Rotation = 90
		bg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(204, 204, 204)); bg.Parent = b
		local bs = Instance.new("UIStroke"); bs.Color = strokeCol; bs.Thickness = 2; bs.Parent = b
		return b
	end

	if isCoins then
		local awesome = makeBtn("AWESOME!", Color3.fromRGB(58, 214, 108), Color3.fromRGB(34, 162, 76), 1, 190)
		awesome.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			closeFn()
		end)
	else
		local equip = makeBtn("EQUIP NOW", Color3.fromRGB(46, 156, 255), Color3.fromRGB(22, 104, 210), 1) -- glossy cyan-blue
		equip.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			-- Equip the leveled pet via the same remote the pet inventory uses (best-effort).
			local ev = game:GetService("ReplicatedStorage"):FindFirstChild("PetEquipEvent")
			if ev and result.petId then pcall(function() ev:FireServer(result.petId) end) end
			closeFn()
		end)
		local close = makeBtn("CLOSE", Color3.fromRGB(46, 86, 152), Color3.fromRGB(30, 60, 114), 2) -- slate
		close.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			closeFn()
		end)
	end

	-- Pop-in.
	card.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(320, 420) }):Play()
end

-- ===== BOTTOM HUD HIDE/RESTORE =====
-- While ANY Daily Rewards UI is up (picker modal OR reward popup), hide ONLY the bottom HUD — fart
-- meter, stomach bar, and the bottom buttons — so nothing covers the modal, then restore them EXACTLY
-- to their prior Enabled state when it closes. The LEFT-SIDE buttons (Shop / Invite / Stomach / More /
-- Return to Island, in SidebarGui) stay visible and are deliberately NOT in this list.
-- (Does not touch gameplay — purely shows/hides the GUIs.)
local HUD_GUIS = { "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }
local hudPrevEnabled = nil
local function setHudHidden(hidden)
	if hidden then
		if hudPrevEnabled then return end -- already hidden; don't re-capture
		hudPrevEnabled = {}
		for _, name in ipairs(HUD_GUIS) do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				hudPrevEnabled[name] = g.Enabled
				g.Enabled = false
			end
		end
	else
		if not hudPrevEnabled then return end
		for _, name in ipairs(HUD_GUIS) do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and hudPrevEnabled[name] ~= nil then
				g.Enabled = hudPrevEnabled[name]
			end
		end
		hudPrevEnabled = nil
	end
end

-- freshReveal(): enable + clean the reveal layer, fade the dim in, and return a closeReveal()
-- teardown. Force-cleans any stale/stuck reveal (e.g. one interrupted by a respawn) so an open can
-- NEVER be blocked by leftover state — that was the stuck-flag trap behind the "missing reveal".
local function freshReveal()
	for _, ch in ipairs(revealGui:GetChildren()) do
		if ch ~= dim then ch:Destroy() end
	end
	revealing = true
	revealGui.Enabled = true
	setHudHidden(true) -- hide the bottom HUD for the whole Daily Rewards UI (picker + reward popup)
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
	local function closeReveal()
		for _, ch in ipairs(revealGui:GetChildren()) do
			if ch ~= dim then ch:Destroy() end
		end
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function()
			revealGui.Enabled = false
			revealing = false
			opening = false
			setHudHidden(false) -- Daily Rewards UI fully closed -> restore the bottom HUD
		end)
	end
	return closeReveal
end

-- MeteorBreak: the shared meteor-crate OPENING animation (shake -> cracks -> burst; burst sound 4612378364),
-- extracted verbatim from the Space Realm. Guarded require so a missing/unsynced module can't break the crate.
local MeteorBreak
do
	local ok, mod = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("MeteorBreak", 10))
	end)
	MeteorBreak = ok and mod or nil
	if not MeteorBreak then
		warn("[CrateClient] MeteorBreak module NOT found in ReplicatedStorage.DinosaurRealm — the crate will open "
			.. "straight to the reward with no meteor animation. Add MeteorBreak.luau (rojo: src/shared/MeteorBreak.luau).")
	end
end

-- playMeteor(big, onDone): the OPENING animation shown BEFORE the reward — now the shared MeteorBreak module's
-- exact meteor shake -> cracks -> burst. At the burst it hands off to onDone (which shows the reward on
-- revealGui) and tears down the MeteorBreak overlay so the reward reveal shows.
local function playMeteor(big, onDone)
	if MeteorBreak then
		MeteorBreak.play({
			isLegendary = big and true or false,
			onReward = function()
				task.spawn(onDone)   -- reward reveal (picker / result card) lives on revealGui
				MeteorBreak.close()  -- fade + clear the MeteorBreak overlay so the reward shows
			end,
		})
	else
		task.spawn(onDone) -- fallback: skip the animation, go straight to the reward
	end
end

-- showResultCard(result, closeReveal): ensure the pet's name is known, then build the result card
-- (pcall'd so a card error can never leave the reveal stuck).
local function showResultCard(result, closeReveal)
	if result.kind == "levels" and result.petId and not petNameById[result.petId] then
		fetchOwnedPets()
	end
	revealGui.Enabled = true -- the reward popup lives here; make sure the layer is on
	local okCard, err = pcall(buildCard, result, closeReveal)
	if okCard then
		print("[CrateClient] reward popup built (kind=" .. tostring(result.kind) .. ")")
	else
		warn("[CrateClient] reward popup FAILED to build: " .. tostring(err))
		closeReveal()
	end
end

----------------------------------------------------------------------------------------
-- Open flow
----------------------------------------------------------------------------------------

-- claimAndReveal(petId, closeReveal): claim the chosen pet, then morph the already-open reveal into
-- the result card. The meteor/burst has already played; this only resolves what the card shows.
local function claimAndReveal(petId, closeReveal)
	task.spawn(function()
		local ok, result = pcall(function() return ClaimCrate:InvokeServer(petId) end)
		if ok and type(result) == "table" then
			if result.ok then
				showResultCard(result, closeReveal)
				return
			elseif result.reason == "cooldown" then
				if result.nextClaimAt then lastCrateClaim = result.nextClaimAt - CRATE.COOLDOWN_SECONDS end
			end
		end
		-- Any failure (cooldown / no_profile / unexpected) -> just close the reveal cleanly.
		closeReveal()
	end)
end

-- ===== "Choose a Pet to Level Up" daily-crate modal — JUNGLE theme to MATCH the Shop + Pet Hub (olive/wood/green) =====
local C = {
	bg       = Color3.fromRGB(18, 30, 18),     -- dark jungle backdrop
	panel    = Color3.fromRGB(126, 146, 86),   -- olive panel gradient TOP (Pet Hub olive)
	panelDk  = Color3.fromRGB(118, 138, 80),   -- olive panel gradient BOTTOM
	row      = Color3.fromRGB(110, 130, 76),   -- olive row body
	rowHi    = Color3.fromRGB(126, 148, 88),   -- hover lighten
	rowSel   = Color3.fromRGB(118, 140, 82),   -- selected fill (lime outline is the cue)
	rowEdge  = Color3.fromRGB(70, 86, 50),     -- darker bottom edge of rows
	navy     = Color3.fromRGB(40, 52, 34),     -- dark-olive XP track
	line     = Color3.fromRGB(150, 178, 110),  -- light-olive inner line
	text     = Color3.fromRGB(250, 242, 214),  -- cream (Pet Hub title color)
	muted    = Color3.fromRGB(228, 236, 196),
	gold     = Color3.fromRGB(255, 210, 74),   -- gold accents (kept; Pet Hub uses gold too)
	goldDk   = Color3.fromRGB(208, 150, 24),
	lime     = Color3.fromRGB(126, 217, 87),   -- selection outline + accents
	limeA    = Color3.fromRGB(154, 232, 74),   -- "Level Up" gradient TOP
	limeB    = Color3.fromRGB(108, 198, 46),   -- "Level Up" gradient BOTTOM
	greenDk  = Color3.fromRGB(74, 150, 32),
	slate    = Color3.fromRGB(126, 84, 48),    -- Cancel / CLOSE -> wood brown (plaque wood)
	slateDk  = Color3.fromRGB(108, 70, 38),
	cyan     = Color3.fromRGB(86, 168, 96),    -- "EQUIP NOW" -> jungle green
	cyanDk   = Color3.fromRGB(54, 124, 66),
	xp       = Color3.fromRGB(126, 200, 96),   -- green XP fill
	xpLt     = Color3.fromRGB(184, 226, 150),
	white    = Color3.fromRGB(255, 255, 255),
	avatarA  = Color3.fromRGB(98, 118, 68),    -- olive avatar inset (gradient top)
	avatarB  = Color3.fromRGB(72, 92, 52),     -- avatar inset bottom
	dark     = Color3.fromRGB(74, 52, 0),      -- dark text on the gold badge
	shadow   = Color3.fromRGB(10, 16, 8),      -- soft drop shadow
	-- legacy keys kept (recolored) so existing references restyle automatically:
	violet   = Color3.fromRGB(250, 242, 214),
	violetLt = Color3.fromRGB(184, 226, 150),
	emerald  = Color3.fromRGB(124, 210, 70),   -- confirm lime-green base
}
local F_DISPLAY = Enum.Font.FredokaOne
local F_BODY    = Enum.Font.Gotham
local F_MED     = Enum.Font.GothamMedium
local F_BOLD    = Enum.Font.GothamBold

-- Emoji per pet, keyed on the food/animal in the name (checked in priority order so e.g. "Blossom
-- Bunny" -> blossom, "Broccoli Bunny" -> broccoli, "Pepper Pup" -> pepper). Falls back to a paw.
local PET_EMOJI = {
	blossom="🌸", broccoli="🥦", burrito="🌯", butter="🧈", coconut="🥥", popcorn="🍿",
	sunflower="🌻", maple="🍁", frost="❄️", penguin="🐧", pepper="🌶️", armadillo="🦔",
	bunny="🐰", rabbit="🐰", duck="🦆", crab="🦀", bee="🐝", fox="🦊", sheep="🐑", cat="🐱",
	pup="🐶", dog="🐶", moose="🫎", pig="🐷", bear="🐻", seal="🦭", gecko="🦎", sun="☀️",
	moon="🌙", star="⭐", milk="🥛", bread="🍞", pasta="🍝", pizza="🍕", burger="🍔",
	turnip="🥔", bean="🫘", cabbage="🥬", cherry="🍒", melon="🍈", pumpkin="🎃", sushi="🍣",
	banana="🍌", grape="🍇",
}
local PET_EMOJI_ORDER = {
	"blossom","broccoli","burrito","butter","coconut","popcorn","sunflower","maple","frost",
	"pepper","armadillo","penguin","bunny","rabbit","duck","crab","bee","fox","sheep","cat",
	"pup","dog","moose","pig","bear","seal","gecko","sun","moon","star","milk","bread","pasta",
	"pizza","burger","turnip","bean","cabbage","cherry","melon","pumpkin","sushi","banana","grape",
}
local function emojiFor(name)
	local l = string.lower(name or "")
	for _, key in ipairs(PET_EMOJI_ORDER) do
		if string.find(l, key, 1, true) then return PET_EMOJI[key] end
	end
	return "🐾"
end

local function mk(class, parent, props)
	local o = Instance.new(class)
	if props then for k, v in pairs(props) do o[k] = v end end
	o.Parent = parent
	return o
end
local function corner(inst, r) mk("UICorner", inst, { CornerRadius = UDim.new(0, r) }) end
local function stroke(inst, color, thick, transp)
	return mk("UIStroke", inst, { Color = color, Thickness = thick, Transparency = transp or 0 })
end
-- gloss(btn, strokeCol): glossy/beveled cartoon button — a vertical white->grey brightness ramp over
-- the button's color (top-lit sheen) plus a darker rounded stroke for the bevel edge.
local function gloss(btn, strokeCol)
	local g = mk("UIGradient", btn, { Rotation = 90 })
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(204, 204, 204))
	if strokeCol then stroke(btn, strokeCol, 2, 0) end
end

-- dropShadow(obj, padPx): soft drop shadow = a few concentric translucent dark rounded frames BEHIND
-- the object (no image asset). padPx compensates for the object's own UIPadding so the layers still
-- extend OUTSIDE its edges. Fine for fixed-size panels/cards (not AutomaticSize).
local function dropShadow(obj, padPx)
	padPx = padPx or 0
	local base = obj.ZIndex or 10
	for i, s in ipairs({ {66, 0.86}, {46, 0.74}, {26, 0.58} }) do
		local extra = padPx * 2 + s[1]
		local sh = mk("Frame", obj, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.new(1, extra, 1, extra), BackgroundColor3 = C.shadow,
			BackgroundTransparency = s[2], BorderSizePixel = 0, ZIndex = base - 4 + i,
		})
		mk("UICorner", sh, { CornerRadius = UDim.new(0, 30) })
	end
end

-- ===== code-drawn vector pet icons (Frames + UICorner; no text emoji, so they render in published
-- games where emoji glyphs are missing). shape() parents one colored block into the avatar, sized +
-- positioned by SCALE (0..1 of the 48px square). opts: circle=true (full round), r=<px> (corner), rot,
-- z. PET_ICONS[keyword](avatar) draws that food/animal from a few shapes. =====
local function shape(av, color, sx, sy, sxp, syp, opts)
	opts = opts or {}
	local f = mk("Frame", av, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sxp, syp),
		Size = UDim2.fromScale(sx, sy), BackgroundColor3 = color, BorderSizePixel = 0,
		BackgroundTransparency = opts.t or 0, Rotation = opts.rot or 0, ZIndex = opts.z or 13,
	})
	if opts.circle then
		mk("UICorner", f, { CornerRadius = UDim.new(1, 0) })
	elseif opts.r then
		mk("UICorner", f, { CornerRadius = UDim.new(0, opts.r) })
	end
	-- opts.grad = true adds a brightness ramp (white -> gradLo grey) that MULTIPLIES the base color,
	-- giving cheap round/3D shading. gradRot picks the light direction (90 = top-lit, the default).
	if opts.grad then
		local lo = opts.gradLo or 0.62
		local g = mk("UIGradient", f, { Rotation = opts.gradRot or 90 })
		g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(lo, lo, lo))
	end
	return f
end

local PET_ICONS = {
	coconut = function(a)
		shape(a, Color3.fromRGB(120, 80, 50), 0.86, 0.86, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.55 })
		shape(a, Color3.fromRGB(238, 222, 204), 0.46, 0.46, 0.50, 0.52, { circle = true, grad = true, gradLo = 0.8, z = 14 })
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.43, 0.47, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.57, 0.47, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.50, 0.60, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(255, 255, 255), 0.16, 0.16, 0.33, 0.31, { circle = true, t = 0.55, z = 16 }) -- sheen
	end,
	broccoli = function(a)
		shape(a, Color3.fromRGB(150, 196, 120), 0.14, 0.36, 0.50, 0.76, { r = 4, grad = true, gradRot = 0 }) -- stalk
		shape(a, Color3.fromRGB(52, 132, 66), 0.66, 0.52, 0.50, 0.40, { circle = true, grad = true, gradLo = 0.58 }) -- crown
		shape(a, Color3.fromRGB(74, 158, 86), 0.34, 0.34, 0.32, 0.30, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(74, 158, 86), 0.34, 0.34, 0.68, 0.30, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(90, 178, 100), 0.32, 0.32, 0.50, 0.24, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(255, 255, 255), 0.12, 0.12, 0.36, 0.26, { circle = true, t = 0.6, z = 15 }) -- sheen
	end,
	burrito = function(a)
		shape(a, Color3.fromRGB(220, 184, 126), 0.82, 0.42, 0.50, 0.50, { r = 12, rot = -22, grad = true, gradLo = 0.66 })
		shape(a, Color3.fromRGB(180, 142, 92), 0.82, 0.08, 0.50, 0.41, { r = 4, rot = -22, z = 14 }) -- seam
		shape(a, Color3.fromRGB(120, 196, 110), 0.16, 0.18, 0.76, 0.40, { r = 4, rot = -22, z = 15 }) -- lettuce
		shape(a, Color3.fromRGB(224, 92, 72), 0.12, 0.14, 0.72, 0.50, { r = 3, rot = -22, z = 16 }) -- salsa
		shape(a, Color3.fromRGB(255, 255, 255), 0.5, 0.06, 0.46, 0.40, { r = 3, rot = -22, t = 0.62, z = 15 }) -- sheen
	end,
	butter = function(a)
		shape(a, Color3.fromRGB(150, 116, 40), 0.66, 0.22, 0.52, 0.66, { r = 5 }) -- shaded base
		shape(a, Color3.fromRGB(245, 205, 80), 0.66, 0.44, 0.50, 0.56, { r = 6, grad = true, gradLo = 0.74 })
		shape(a, Color3.fromRGB(252, 228, 140), 0.66, 0.16, 0.50, 0.40, { r = 5, z = 14 }) -- top slab
		shape(a, Color3.fromRGB(255, 255, 255), 0.16, 0.1, 0.36, 0.40, { r = 3, t = 0.5, z = 15 }) -- sheen
	end,
	pepper = function(a)
		shape(a, Color3.fromRGB(200, 48, 40), 0.50, 0.62, 0.50, 0.60, { r = 16, rot = 6, grad = true, gradLo = 0.62 })
		shape(a, Color3.fromRGB(248, 120, 100), 0.10, 0.40, 0.40, 0.58, { r = 6, rot = 6, t = 0.35, z = 15 }) -- highlight
		shape(a, Color3.fromRGB(70, 150, 70), 0.16, 0.22, 0.52, 0.22, { r = 4, z = 14 }) -- stem
		shape(a, Color3.fromRGB(86, 176, 90), 0.24, 0.10, 0.44, 0.18, { r = 3, rot = -25, z = 14 }) -- leaf
	end,
	bunny = function(a)
		shape(a, Color3.fromRGB(236, 236, 244), 0.20, 0.42, 0.40, 0.28, { circle = true, grad = true, gradLo = 0.82 }) -- ear
		shape(a, Color3.fromRGB(236, 236, 244), 0.20, 0.42, 0.60, 0.28, { circle = true, grad = true, gradLo = 0.82 }) -- ear
		shape(a, Color3.fromRGB(245, 200, 212), 0.09, 0.26, 0.40, 0.29, { circle = true, z = 14 }) -- inner ear
		shape(a, Color3.fromRGB(245, 200, 212), 0.09, 0.26, 0.60, 0.29, { circle = true, z = 14 }) -- inner ear
		shape(a, Color3.fromRGB(246, 246, 250), 0.58, 0.54, 0.50, 0.62, { circle = true, grad = true, gradLo = 0.84, z = 14 }) -- head
		shape(a, Color3.fromRGB(40, 36, 44), 0.07, 0.08, 0.40, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(40, 36, 44), 0.07, 0.08, 0.60, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(248, 170, 188), 0.10, 0.07, 0.50, 0.69, { circle = true, z = 15 }) -- nose
	end,
	blossom = function(a)
		local petal = Color3.fromRGB(248, 168, 200)
		shape(a, petal, 0.34, 0.34, 0.50, 0.26, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.50, 0.74, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.26, 0.50, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.74, 0.50, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, Color3.fromRGB(250, 206, 84), 0.30, 0.30, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.72, z = 15 }) -- center
		shape(a, Color3.fromRGB(190, 140, 40), 0.07, 0.07, 0.50, 0.50, { circle = true, z = 16 }) -- pollen dot
	end,
	popcorn = function(a)
		local cream = Color3.fromRGB(250, 240, 202)
		shape(a, cream, 0.38, 0.38, 0.38, 0.30, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, cream, 0.38, 0.38, 0.64, 0.28, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, cream, 0.40, 0.40, 0.50, 0.44, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, Color3.fromRGB(228, 90, 80), 0.56, 0.34, 0.50, 0.80, { r = 4, z = 14 }) -- box
		shape(a, Color3.fromRGB(245, 245, 245), 0.10, 0.34, 0.42, 0.80, { z = 15 }) -- stripe
		shape(a, Color3.fromRGB(245, 245, 245), 0.10, 0.34, 0.58, 0.80, { z = 15 }) -- stripe
	end,
	sunflower = function(a)
		local petal = Color3.fromRGB(250, 198, 66)
		shape(a, petal, 0.30, 0.30, 0.50, 0.22, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.50, 0.78, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.26, 0.36, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.74, 0.36, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.26, 0.64, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.74, 0.64, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, Color3.fromRGB(104, 68, 36), 0.42, 0.42, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.7, z = 15 }) -- seed center
	end,
	maple = function(a)
		local o = Color3.fromRGB(222, 98, 42)
		shape(a, o, 0.48, 0.48, 0.50, 0.44, { r = 6, rot = 45, grad = true, gradLo = 0.7 }) -- center lobe
		shape(a, o, 0.30, 0.30, 0.28, 0.36, { r = 4, rot = 45 }) -- lobe
		shape(a, o, 0.30, 0.30, 0.72, 0.36, { r = 4, rot = 45 }) -- lobe
		shape(a, o, 0.26, 0.26, 0.50, 0.22, { r = 4, rot = 45 }) -- top lobe
		shape(a, Color3.fromRGB(150, 92, 52), 0.05, 0.28, 0.50, 0.80, { r = 3 }) -- stem
		shape(a, Color3.fromRGB(255, 206, 160), 0.06, 0.22, 0.46, 0.46, { r = 2, rot = 45, t = 0.4, z = 15 }) -- vein
	end,
	frost = function(a)
		local w = Color3.fromRGB(206, 232, 252)
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 0, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 60, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 120, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.13, 0.13, 0.50, 0.15, { circle = true, z = 15 }) -- tip
		shape(a, w, 0.13, 0.13, 0.50, 0.85, { circle = true, z = 15 }) -- tip
		shape(a, Color3.fromRGB(240, 250, 255), 0.22, 0.22, 0.50, 0.50, { circle = true, z = 16 }) -- core
	end,
	penguin = function(a)
		shape(a, Color3.fromRGB(40, 44, 54), 0.64, 0.82, 0.50, 0.52, { circle = true, grad = true, gradLo = 0.62 }) -- body
		shape(a, Color3.fromRGB(240, 242, 248), 0.36, 0.56, 0.50, 0.60, { circle = true, grad = true, gradLo = 0.86, z = 14 }) -- belly
		shape(a, Color3.fromRGB(20, 22, 28), 0.08, 0.08, 0.42, 0.36, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(20, 22, 28), 0.08, 0.08, 0.58, 0.36, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.03, 0.03, 0.43, 0.35, { circle = true, z = 17 }) -- glint
		shape(a, Color3.fromRGB(246, 160, 50), 0.15, 0.12, 0.50, 0.45, { r = 3, rot = 45, z = 16 }) -- beak
		shape(a, Color3.fromRGB(244, 150, 44), 0.16, 0.08, 0.40, 0.93, { r = 3, z = 15 }) -- foot
		shape(a, Color3.fromRGB(244, 150, 44), 0.16, 0.08, 0.60, 0.93, { r = 3, z = 15 }) -- foot
	end,
	armadillo = function(a)
		shape(a, Color3.fromRGB(152, 122, 94), 0.74, 0.52, 0.46, 0.56, { r = 18, grad = true, gradLo = 0.6 }) -- shell
		shape(a, Color3.fromRGB(120, 94, 70), 0.08, 0.50, 0.38, 0.56, { z = 14 }) -- band
		shape(a, Color3.fromRGB(120, 94, 70), 0.08, 0.50, 0.50, 0.56, { z = 14 }) -- band
		shape(a, Color3.fromRGB(170, 140, 108), 0.28, 0.30, 0.80, 0.50, { circle = true, grad = true, gradLo = 0.72 }) -- head
		shape(a, Color3.fromRGB(28, 24, 22), 0.06, 0.06, 0.85, 0.46, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.4, 0.06, 0.44, 0.42, { r = 3, t = 0.6, z = 15 }) -- sheen
	end,
	duck = function(a)
		shape(a, Color3.fromRGB(248, 206, 70), 0.60, 0.48, 0.44, 0.60, { circle = true, grad = true, gradLo = 0.7 }) -- body
		shape(a, Color3.fromRGB(250, 216, 90), 0.36, 0.36, 0.64, 0.38, { circle = true, grad = true, gradLo = 0.8, z = 14 }) -- head
		shape(a, Color3.fromRGB(238, 222, 138), 0.30, 0.22, 0.40, 0.62, { r = 8, t = 0.2, z = 14 }) -- wing
		shape(a, Color3.fromRGB(242, 150, 44), 0.18, 0.10, 0.82, 0.42, { r = 3, z = 15 }) -- bill
		shape(a, Color3.fromRGB(26, 26, 30), 0.06, 0.06, 0.66, 0.32, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.025, 0.025, 0.67, 0.31, { circle = true, z = 17 }) -- glint
	end,
	crab = function(a)
		shape(a, Color3.fromRGB(220, 62, 50), 0.66, 0.42, 0.50, 0.58, { r = 14, grad = true, gradLo = 0.66 }) -- shell
		shape(a, Color3.fromRGB(232, 86, 74), 0.22, 0.22, 0.24, 0.36, { circle = true, grad = true, gradLo = 0.75 }) -- claw
		shape(a, Color3.fromRGB(232, 86, 74), 0.22, 0.22, 0.76, 0.36, { circle = true, grad = true, gradLo = 0.75 }) -- claw
		shape(a, Color3.fromRGB(20, 20, 24), 0.07, 0.07, 0.42, 0.50, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(20, 20, 24), 0.07, 0.07, 0.58, 0.50, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.4, 0.06, 0.46, 0.46, { r = 3, t = 0.6, z = 15 }) -- sheen
	end,
	bee = function(a)
		shape(a, Color3.fromRGB(248, 204, 70), 0.62, 0.46, 0.52, 0.56, { r = 13, grad = true, gradLo = 0.7 }) -- body
		shape(a, Color3.fromRGB(40, 36, 32), 0.11, 0.46, 0.46, 0.56, { z = 14 }) -- stripe
		shape(a, Color3.fromRGB(40, 36, 32), 0.11, 0.46, 0.62, 0.56, { z = 14 }) -- stripe
		shape(a, Color3.fromRGB(236, 244, 252), 0.26, 0.32, 0.30, 0.34, { circle = true, t = 0.15, z = 15 }) -- wing
		shape(a, Color3.fromRGB(40, 36, 32), 0.18, 0.18, 0.74, 0.50, { circle = true, z = 15 }) -- head
		shape(a, Color3.fromRGB(255, 255, 255), 0.05, 0.05, 0.78, 0.46, { circle = true, z = 16 }) -- eye glint
	end,
	fox = function(a)
		local o = Color3.fromRGB(228, 124, 46)
		shape(a, o, 0.26, 0.26, 0.30, 0.28, { r = 3, rot = 45, grad = true, gradLo = 0.7 }) -- ear
		shape(a, o, 0.26, 0.26, 0.70, 0.28, { r = 3, rot = 45, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(40, 30, 26), 0.10, 0.10, 0.30, 0.23, { r = 2, rot = 45, z = 14 }) -- ear tip
		shape(a, Color3.fromRGB(40, 30, 26), 0.10, 0.10, 0.70, 0.23, { r = 2, rot = 45, z = 14 }) -- ear tip
		shape(a, o, 0.62, 0.56, 0.50, 0.56, { r = 16, grad = true, gradLo = 0.74 }) -- head
		shape(a, Color3.fromRGB(246, 246, 250), 0.34, 0.32, 0.50, 0.66, { r = 9, z = 14 }) -- snout
		shape(a, Color3.fromRGB(30, 24, 22), 0.07, 0.07, 0.40, 0.52, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(30, 24, 22), 0.07, 0.07, 0.60, 0.52, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(26, 22, 20), 0.10, 0.08, 0.50, 0.71, { circle = true, z = 16 }) -- nose
	end,
	sheep = function(a)
		local wfl = Color3.fromRGB(244, 244, 248)
		shape(a, wfl, 0.36, 0.36, 0.32, 0.38, { circle = true, grad = true, gradLo = 0.82 }) -- fluff
		shape(a, wfl, 0.36, 0.36, 0.68, 0.38, { circle = true, grad = true, gradLo = 0.82 }) -- fluff
		shape(a, wfl, 0.40, 0.40, 0.50, 0.32, { circle = true, grad = true, gradLo = 0.82 }) -- fluff top
		shape(a, wfl, 0.62, 0.50, 0.50, 0.58, { circle = true, grad = true, gradLo = 0.86, z = 13 }) -- fluff body
		shape(a, Color3.fromRGB(72, 68, 80), 0.32, 0.36, 0.50, 0.60, { circle = true, grad = true, gradLo = 0.72, z = 14 }) -- face
		shape(a, Color3.fromRGB(245, 245, 250), 0.06, 0.07, 0.44, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(245, 245, 250), 0.06, 0.07, 0.56, 0.58, { circle = true, z = 15 }) -- eye
	end,
	pup = function(a)
		shape(a, Color3.fromRGB(138, 94, 58), 0.24, 0.42, 0.28, 0.36, { r = 8, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(138, 94, 58), 0.24, 0.42, 0.72, 0.36, { r = 8, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(172, 122, 80), 0.60, 0.56, 0.50, 0.52, { r = 16, grad = true, gradLo = 0.76 }) -- head
		shape(a, Color3.fromRGB(216, 184, 144), 0.32, 0.30, 0.50, 0.66, { r = 9, z = 14 }) -- snout
		shape(a, Color3.fromRGB(34, 28, 26), 0.10, 0.09, 0.50, 0.62, { circle = true, z = 15 }) -- nose
		shape(a, Color3.fromRGB(34, 28, 26), 0.07, 0.08, 0.38, 0.46, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(34, 28, 26), 0.07, 0.08, 0.62, 0.46, { circle = true, z = 15 }) -- eye
	end,
}
PET_ICONS.rabbit = PET_ICONS.bunny -- name aliases (same icon)
PET_ICONS.dog = PET_ICONS.pup

-- drawPetIcon(avatar, name): same keyword priority as emojiFor; draws the matching vector icon, or a
-- generic rounded dot if nothing matches. (Assigns the forward-declared upvalue above.)
function drawPetIcon(av, name)
	local l = string.lower(name or "")
	for _, key in ipairs(PET_EMOJI_ORDER) do
		local fn = PET_ICONS[key]
		if fn and string.find(l, key, 1, true) then
			fn(av)
			return
		end
	end
	-- generic fallback: a soft shaded dot with a small sheen
	shape(av, Color3.fromRGB(150, 160, 200), 0.50, 0.50, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.62 })
	shape(av, Color3.fromRGB(255, 255, 255), 0.16, 0.16, 0.40, 0.38, { circle = true, t = 0.55, z = 14 })
end

-- ===== REAL pet model in a ViewportFrame (primary avatar display) =====
-- PetSystem builds the fused pet templates and parents them to ReplicatedStorage, named
-- "<DisplayNameNoSpaces>Template" (e.g. "Broccoli Bunny" -> BroccoliBunnyTemplate, "Coconut Crab" ->
-- CoconutCrabTemplate). We clone that exact model so the avatar matches the in-game pet.
-- explicit petId -> template (the real pets whose template name doesn't match the display name,
-- e.g. SharkPet's model is "SharkTemplate" but its display name is "Megalodon").
local PET_TEMPLATE_BY_ID = {
	StegoPet = "StegosaurusTemplate", RaptorPet = "VelociraptorTemplate",
	SharkPet = "SharkTemplate", TriceratopsPet = "TriceratopsTemplate",
	SpinosaurusPet = "SpinosaurusTemplate", TyrannosaurusPet = "TyrannosaurusTemplate",
}
local function findPetTemplate(p)
	local dn = (p.displayName or ""):gsub("%s+", "")
	local id = p.petId or ""
	local mapped = PET_TEMPLATE_BY_ID[id]
	for _, nm in ipairs({ mapped, dn .. "Template", dn, id .. "Template", id }) do
		if nm and nm ~= "" and nm ~= "Template" then
			local m = ReplicatedStorage:FindFirstChild(nm) or workspace:FindFirstChild(nm)
			if m and m:IsA("Model") then return m end
		end
	end
	return nil
end

-- petModelToViewport(avatar, p): clone the real pet model into a ViewportFrame filling the avatar,
-- frame a camera on it and light it so it reads at 48px. Returns true on success, false if there's no
-- model to clone (caller then draws the vector icon). The avatar's gradient shows behind (viewport bg
-- is transparent); ClipsDescendants on the avatar rounds the viewport to the square's corners.
local VIEWPORT_SPIN_SPEED = 0.9 -- radians/sec — slow continuous Y-axis turn, like the pets HUD

function petModelToViewport(avatar, p)
	local template = findPetTemplate(p)
	if not template then return false end
	local vp = mk("ViewportFrame", avatar, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 13,
		Ambient = Color3.fromRGB(150, 154, 170),       -- fill so the model isn't muddy at small size
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.55).Unit, -- key light from upper-front
	})
	local ok = pcall(function()
		local clone = template:Clone()
		clone.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 50
		cam.Parent = vp
		vp.CurrentCamera = cam
		-- frame the model: aim at its bounding-box center from a 3/4 angle, far enough to fit it.
		local cf, size = clone:GetBoundingBox()
		local center = cf.Position
		local extent = math.max(size.X, size.Y, size.Z, 0.1)
		local dist = (extent * 0.5) / math.tan(math.rad(cam.FieldOfView * 0.5)) * 1.45 + extent * 0.2
		local baseDir = Vector3.new(0.5, 0.42, 1).Unit
		-- CONTINUOUS SPIN: orbit the camera around the model's vertical axis every frame (keeps the
		-- model + welds untouched). The connection self-disconnects once the viewport is destroyed.
		local angle = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not vp.Parent then conn:Disconnect(); return end
			angle = angle + dt * VIEWPORT_SPIN_SPEED
			cam.CFrame = CFrame.lookAt(center + (CFrame.Angles(0, angle, 0) * baseDir) * dist, center)
		end)
		vp.Destroying:Connect(function() conn:Disconnect() end)
	end)
	if not ok then
		vp:Destroy()
		return false
	end
	return true
end

-- showPicker(pets, closeReveal, onPick): the "Choose a Pet to Level Up" modal, rendered INSIDE the
-- already-open reveal (after the burst). All OWNED pets are listed; maxed pets are greyed + "MAX" and
-- not selectable. Select -> Level Up confirm -> onPick(petId); Cancel -> closeReveal() tears it down.
-- header colors for the rolled rarity (driven by the server's PreviewRoll result)
local RARITY_HEX = { Uncommon = "#9fe1cb", Rare = "#85b7eb", Epic = "#afa9ec", Mythical = "#ffc83d" }
local MAX_LV = CRATE.PET_MAX_LEVEL or 25

local function showPicker(pets, roll, closeReveal, onPick)
	local done = false
	local selected = nil          -- the chosen pet entry (non-maxed); only WHICH pet is chosen
	local tokens = 1              -- the available daily-crate claim, shown as a spendable token
	local rowApis = {}
	-- The rolled rarity + level amount are decided by the SERVER (PreviewRoll), not the player.
	local rarity = roll and roll.rarity or nil
	local levelsAdded = (roll and roll.levelsAdded) or 1
	local rarityHex = (rarity and RARITY_HEX[rarity]) or "#8b93b5"

	-- ----- modal panel: EXACT same Size/Position/AnchorPoint as the Pets Hub / shop panel (copied
	-- verbatim: 700 x 520 fixed, centered, nudged up 45px) + the SAME adaptive UIScale factor the shops
	-- get via _G.applyHudScaling — so it opens at identical dimensions and scale. (DisplayOrder 100.) ---
	local panel = mk("Frame", revealGui, {
		Name = "PetPicker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -16),  -- hub-parity screen spot (no phone clipping)
		Size = UDim2.new(0, 700, 0, 520), BackgroundColor3 = C.panel, ZIndex = 10,
	})
	corner(panel, 24)
	stroke(panel, C.white, 4, 0) -- thick white rounded cartoon border
	dropShadow(panel, 24) -- soft drop shadow behind the panel
	local panelGrad = mk("UIGradient", panel, { Rotation = 90 }) -- #1a4fd6 -> #0e3bb0 vertical gradient
	panelGrad.Color = ColorSequence.new(C.panel, C.panelDk)
	mk("UIPadding", panel, {
		PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 22),
		PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22),
	})
	-- adaptive UIScale: ride the SAME getScale() ResponsiveUI applies to the HUD and every other menu
	-- (1.0 desktop / ~0.60 phone / ~1.07 iPad, with NO per-cluster extra) so the Pet Picker opens at
	-- the shops' exact scale. ResponsiveUI publishes getScale() as the LocalPlayer "ResponsiveScale"
	-- attribute on mobile; on desktop it's unset so we stay at 1.0. (Was: hardcoded
	-- min(vp.X/1280, vp.Y/720, 1), which gave ~0.517 on phone instead of 0.60 and mis-sized on iPad.)
	local uiScale = mk("UIScale", panel, { Scale = 1 })
	local function applyShopScale()
		uiScale.Scale = player:GetAttribute("ResponsiveScale") or 1
	end
	applyShopScale()
	player:GetAttributeChangedSignal("ResponsiveScale"):Connect(applyShopScale)

	-- inner content FILLS the panel (header pinned top, list fills the middle, footer pinned bottom —
	-- the shop layout). The token pill floats top-right as a separate child of `panel`.
	local HEADER_H, FOOTER_H, GAP = 112, 64, 10
	local content = mk("Frame", panel, {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 11,
	})

	-- ----- token pill (top-right, gold coin "↑" + count) -----
	local pill = mk("Frame", panel, { -- gold rounded pill, white outline
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(74, 34), BackgroundColor3 = C.gold, ZIndex = 14,
	})
	corner(pill, 999)
	stroke(pill, C.white, 2, 0)
	local pillGrad = mk("UIGradient", pill, { Rotation = 90 }) -- gold gloss
	pillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 214, 214))
	mk("UIListLayout", pill, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 7),
	})
	mk("UIPadding", pill, { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10) })
	local coin = mk("TextLabel", pill, { -- gold star coin (white disc so the star reads)
		Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.white, Font = F_DISPLAY, Text = "★",
		TextSize = 14, TextColor3 = C.goldDk, ZIndex = 15, LayoutOrder = 1,
	})
	corner(coin, 999)
	stroke(coin, C.goldDk, 1, 0)
	local tokenCount = mk("TextLabel", pill, {
		Size = UDim2.fromOffset(20, 22), BackgroundTransparency = 1, Font = F_BOLD,
		Text = tostring(tokens), TextSize = 15, TextColor3 = C.dark, -- dark count on the gold pill
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15, LayoutOrder = 2,
	})

	-- ----- header (pinned top, centered) -----
	local header = mk("Frame", content, {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 11,
	})
	mk("UIListLayout", header, {
		FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})
	-- gold "DAILY CRATE" with a small gold star
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, -80, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
		Font = F_BOLD, Text = "★ DAILY CRATE", TextSize = 12, TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12, LayoutOrder = 1,
	})
	-- white bold title (~26px) with a gold star before it
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = F_DISPLAY, RichText = true, Text = '<font color="#ffd24a">★</font> Choose a Pet to Level Up',
		TextSize = 26, TextColor3 = C.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12, LayoutOrder = 2,
	})
	-- Subtitle shows the SERVER-ROLLED rarity (colored) + the matching "+N levels" amount, e.g.
	-- "EPIC roll — pick a pet to grant +4 levels." Falls back to the plain line if no roll came back.
	local subText
	if rarity then
		subText = string.format(
			'<font color="#7ed957"><b>%s</b></font> roll — pick a pet to grant <font color="#7ed957"><b>+%d level%s</b></font>.',
			string.upper(rarity), levelsAdded, (levelsAdded == 1) and "" or "s")
	else
		subText = "Spend a token to grant the next level instantly."
	end
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = F_BODY, RichText = true, Text = subText, TextSize = 13,
		TextColor3 = C.muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12, LayoutOrder = 3,
	})

	-- ----- scrollable list: fills the middle (between the pinned header and footer) -----
	local list = mk("ScrollingFrame", content, {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, HEADER_H + GAP),
		Size = UDim2.new(1, 0, 1, -(HEADER_H + FOOTER_H + GAP * 2)),
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.violet, ScrollBarImageTransparency = 0.35,
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 11,
	})
	mk("UIListLayout", list, {
		FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	})
	mk("UIPadding", list, { PaddingRight = UDim.new(0, 6) })

	-- footer/confirm refs are declared before the rows so selection can update the button
	local confirmEnabled = false
	local confirmBtn, confirmLabel, costChip, confirmGrad

	local function setConfirm(on)
		confirmEnabled = on
		confirmBtn.BackgroundColor3 = C.white -- the UIGradient supplies the fill color
		if on then
			confirmGrad.Color = ColorSequence.new(C.limeA, C.limeB) -- #9ae84a -> #6cc62e glossy lime
			confirmBtn.AutoButtonColor = true
			confirmLabel.TextColor3 = C.white -- white bold text
			confirmLabel.Text = "Level Up +" .. tostring(levelsAdded) -- amount is the server roll, not the pet
			costChip.Visible = true
		else
			confirmGrad.Color = ColorSequence.new(Color3.fromRGB(150, 170, 210), Color3.fromRGB(96, 124, 182)) -- dim
			confirmBtn.AutoButtonColor = false
			confirmLabel.TextColor3 = C.muted
			confirmLabel.Text = (selected and tokens <= 0) and "Out of Tokens" or "Level Up"
			costChip.Visible = false
		end
	end
	local function refreshConfirm()
		setConfirm(selected ~= nil and tokens > 0)
	end

	-- ----- one pet row -----
	for i, p in ipairs(pets) do
		local maxed = p.maxed == true
		local row = mk("TextButton", list, {
			Text = "", AutoButtonColor = false, Selectable = not maxed,
			Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.row, ZIndex = 11, LayoutOrder = i,
		})
		corner(row, 16)
		local rowStroke = stroke(row, C.line, 1.5, 0) -- light-blue inner outline
		local rowGrad = mk("UIGradient", row, { Rotation = 90 }) -- inner top highlight -> darker bottom edge
		rowGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 192, 226))

		-- check mark (top-right, shown when selected) — lime to match the selected outline
		local check = mk("TextLabel", row, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = C.lime, Font = F_BOLD, Text = "✓", TextSize = 13,
			TextColor3 = Color3.fromRGB(18, 70, 20), Visible = false, ZIndex = 14,
		})
		corner(check, 999)
		stroke(check, C.white, 2, 0)

		-- avatar (rounded 48px square, gradient bg) showing the REAL in-game pet MODEL in a ViewportFrame;
		-- only falls back to the code-drawn vector icon if that pet's model can't be found/cloned.
		local avatar = mk("Frame", row, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = C.avatarA, ClipsDescendants = true, ZIndex = 12,
		})
		corner(avatar, 14)
		stroke(avatar, C.white, 1.5, 0) -- white border (darker-blue inset behind the viewport)
		local ag = mk("UIGradient", avatar, { Rotation = 90 })
		ag.Color = ColorSequence.new(C.avatarA, C.avatarB)
		if not petModelToViewport(avatar, p) then
			drawPetIcon(avatar, p.displayName) -- fallback: code-drawn vector icon
		end

		-- info column (name + xp bar + %)
		local info = mk("Frame", row, {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 76, 0.5, 0), Size = UDim2.new(1, -76 - 96, 0, 44), ZIndex = 12,
		})
		mk("UIListLayout", info, {
			FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7),
		})
		mk("TextLabel", info, {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Font = F_DISPLAY,
			Text = p.displayName or p.petId, TextSize = 16, TextColor3 = maxed and C.muted or C.text,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 12, LayoutOrder = 1,
		})
		local xpRow = mk("Frame", info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 8), ZIndex = 12, LayoutOrder = 2 })
		local track = mk("Frame", xpRow, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -40, 0, 7),
			BackgroundColor3 = C.navy, BackgroundTransparency = 0, ZIndex = 12, -- dark-navy track
		})
		corner(track, 999)
		local fill = mk("Frame", track, {
			Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = maxed and C.muted or C.xp, ZIndex = 13,
		})
		corner(fill, 999)
		if not maxed then
			local fg = mk("UIGradient", fill, { Rotation = 0 }) -- light-blue XP gradient
			fg.Color = ColorSequence.new(C.xp, C.xpLt)
		end
		mk("TextLabel", xpRow, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(34, 14),
			BackgroundTransparency = 1, Font = F_MED, Text = maxed and "MAX" or (tostring(math.floor(p.xpPct or 0)) .. "%"),
			TextSize = 11, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12,
		})
		TweenService:Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new((p.xpPct or 0) / 100, 0, 1, 0) }):Play()

		-- level column (gold "Lv N" badge + "-> N+1", or "MAX")
		local level = mk("Frame", row, {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(80, 44), ZIndex = 12,
		})
		mk("UIListLayout", level, {
			FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
		})
		local badge = mk("TextLabel", level, { -- gold gradient pill: WHITE star + DARK "Lv N"
			BackgroundColor3 = C.gold, BackgroundTransparency = maxed and 0.55 or 0,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22),
			Font = F_DISPLAY, RichText = true,
			Text = maxed and "MAX" or ('<font color="#ffffff">★</font> Lv ' .. tostring(p.level)),
			TextSize = 13, TextColor3 = maxed and C.muted or C.dark, ZIndex = 13, LayoutOrder = 1,
		})
		corner(badge, 999)
		stroke(badge, C.white, 1.5, maxed and 0.4 or 0)
		if not maxed then local bgr = mk("UIGradient", badge, { Rotation = 90 }); bgr.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(220,196,120)) end -- gold gloss
		mk("UIPadding", badge, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
		if not maxed then
			-- preview = current level + the ROLLED amount, clamped at the cap (same for every pet)
			mk("TextLabel", level, {
				BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 13),
				Font = F_MED, Text = "→ Lv " .. tostring(math.min(MAX_LV, p.level + levelsAdded)),
				TextSize = 11, TextColor3 = C.xp, ZIndex = 12, LayoutOrder = 2, -- light blue
			})
		end

		-- selection / hover behaviour
		local function setSelected(on)
			rowStroke.Color = on and C.lime or C.line -- bright lime outline when selected
			rowStroke.Thickness = on and 3 or 1.5
			row.BackgroundColor3 = on and C.rowSel or C.row
			check.Visible = on
		end
		rowApis[i] = { entry = p, setSelected = setSelected }

		if maxed then
			row.BackgroundTransparency = 0.35 -- greyed / dimmed; not selectable
		else
			local rowScale = mk("UIScale", row, { Scale = 1 }) -- hover "lift" (visual only; layout unaffected)
			row.MouseEnter:Connect(function()
				if selected ~= p then row.BackgroundColor3 = C.rowHi end
				TweenService:Create(rowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1.02 }):Play()
			end)
			row.MouseLeave:Connect(function()
				if selected ~= p then row.BackgroundColor3 = C.row end
				TweenService:Create(rowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			end)
			row.Activated:Connect(function()
				if done then return end
				playSound(SND_TAP, 0.6)
				selected = p
				for _, a in ipairs(rowApis) do a.setSelected(a.entry == p) end
				refreshConfirm()
			end)
		end
	end

	-- ----- footer (Cancel + Level Up) -----
	local footer = mk("Frame", content, {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, FOOTER_H), ZIndex = 11,
	})
	mk("Frame", footer, { -- top border line
		BackgroundColor3 = C.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 0), ZIndex = 11,
	})
	local cancelBtn = mk("TextButton", footer, { -- slate-blue, glossy
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 6), Size = UDim2.fromOffset(116, 46),
		BackgroundColor3 = C.slate, AutoButtonColor = true,
		Font = F_BOLD, Text = "Cancel", TextSize = 15, TextColor3 = C.white, ZIndex = 12,
	})
	corner(cancelBtn, 14)
	gloss(cancelBtn, C.slateDk)

	confirmBtn = mk("TextButton", footer, { -- glossy lime-green gradient (colors set in setConfirm)
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 6), Size = UDim2.new(1, -128, 0, 46),
		BackgroundColor3 = C.white, AutoButtonColor = false, Text = "", ZIndex = 12,
	})
	corner(confirmBtn, 14)
	stroke(confirmBtn, C.greenDk, 2, 0)
	confirmGrad = mk("UIGradient", confirmBtn, { Rotation = 90 })
	-- faint white sparkles scattered on the Level Up button
	for _, sp in ipairs({ {0.16, 0.32, 3}, {0.46, 0.70, 2.5}, {0.78, 0.30, 3}, {0.62, 0.4, 2} }) do
		local s = mk("Frame", confirmBtn, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sp[1], sp[2]),
			Size = UDim2.fromOffset(sp[3] * 2, sp[3] * 2), BackgroundColor3 = C.white,
			BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 12,
		})
		mk("UICorner", s, { CornerRadius = UDim.new(1, 0) })
	end
	mk("UIListLayout", confirmBtn, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10),
	})
	confirmLabel = mk("TextLabel", confirmBtn, {
		BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20),
		Font = F_BOLD, Text = "Level Up", TextSize = 15, TextColor3 = C.muted, ZIndex = 13, LayoutOrder = 1,
	})
	costChip = mk("Frame", confirmBtn, {
		BackgroundColor3 = C.dark, BackgroundTransparency = 0.78, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22), Visible = false, ZIndex = 13, LayoutOrder = 2,
	})
	corner(costChip, 999)
	mk("UIListLayout", costChip, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	})
	mk("UIPadding", costChip, { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 9) })
	local chipCoin = mk("TextLabel", costChip, {
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.gold, Font = F_DISPLAY, Text = "★",
		TextSize = 11, TextColor3 = Color3.fromRGB(120, 78, 0), ZIndex = 14, LayoutOrder = 1,
	})
	corner(chipCoin, 999)
	mk("TextLabel", costChip, {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 16), Font = F_BOLD, Text = "1",
		TextSize = 12, TextColor3 = C.dark, ZIndex = 14, LayoutOrder = 2,
	})

	local function teardown() panel:Destroy() end

	cancelBtn.Activated:Connect(function()
		if done then return end
		done = true
		playSound(SND_TAP, 0.6)
		-- Cancel backs out: clears selection and closes the modal + reveal (the daily claim is NOT
		-- consumed — only Confirm/ClaimCrate spends it — so the crate stays available).
		selected = nil
		teardown()
		closeReveal()
	end)

	confirmBtn.Activated:Connect(function()
		if done or not confirmEnabled or not selected then return end
		done = true
		playSound(SND_TAP, 0.6)
		tokens = tokens - 1
		tokenCount.Text = tostring(tokens)
		local petId = selected.petId
		teardown()
		onPick(petId) -- claim -> result card (bumps level / resets XP in the reveal)
	end)

	refreshConfirm()
end

-- attemptOpen(): triggered by the More menu's "Daily Rewards" row (assigns the forward-declared
-- upvalue connected at the top). Otherwise fetch owned pets, pick (or auto-select), then claim. The
-- server applies the levels to the chosen pet and rolls the rarity.
attemptOpen = function()
	print("[CrateClient] Daily Rewards open requested (claimable=" .. tostring(isClaimable()) .. ")")
	playSound(SND_TAP, 0.6)
	if not isClaimable() then return end
	-- Recover from any leftover/stuck crate UI (a prior reveal interrupted by a respawn, etc.) so a
	-- tap is NEVER silently swallowed. A live reveal covers the screen + closes the menu, so this only
	-- ever fires on a genuinely stuck state, not on a real in-progress open.
	if revealing or opening then
		for _, ch in ipairs(revealGui:GetChildren()) do
			if ch ~= dim then ch:Destroy() end
		end
		revealGui.Enabled = false
		revealing = false
		opening = false
	end
	opening = true
	task.spawn(function()
		local owned = fetchOwnedPets()
		if #owned == 0 then
			-- Owns ZERO pets: do NOT claim (no coins, no timer consumed). Show the message, stay ready.
			opening = false
			showMessage("Unlock A Pet To Receive Levels")
			return
		end
		local hasUnmaxed = false
		for _, p in ipairs(owned) do
			if not p.maxed then hasUnmaxed = true; break end
		end
		-- FULL OPEN SEQUENCE: meteor shake -> cracks -> burst FIRST, then the "Choose a Pet to Level Up"
		-- modal listing ALL owned pets (maxed ones greyed + not selectable). The server PRE-ROLLS the
		-- rarity (PreviewRoll) so the header/rows/confirm can show the rolled tier + "+N levels"; the
		-- player only picks WHICH pet. Confirming claims it (reusing that same roll) -> result reveal.
		local closeReveal = freshReveal()
		playMeteor(false, function()
			if not hasUnmaxed then
				claimAndReveal(nil, closeReveal) -- owns pets but ALL maxed -> coin fallback (unchanged)
				return
			end
			local roll = nil -- { rarity, levelsAdded } from the server, or nil if the preview failed
			local okR, res = pcall(function() return PreviewRoll:InvokeServer() end)
			if okR and type(res) == "table" and res.ok and res.rarity then roll = res end
			showPicker(owned, roll, closeReveal, function(petId) claimAndReveal(petId, closeReveal) end)
		end)
	end)
end

print("[CrateClient] fully loaded — Daily Rewards is now live")

-- Dev /crate path: the server already decided the result. Play the SAME full sequence (meteor shake
-- -> cracks -> burst -> result card); no picker (the server already chose the pet), and the burst is
-- rarity-aware here since we know the result up front.
CrateResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if result.ok then
		if revealing or opening then
			for _, ch in ipairs(revealGui:GetChildren()) do
				if ch ~= dim then ch:Destroy() end
			end
			revealGui.Enabled = false; revealing = false; opening = false
		end
		local closeReveal = freshReveal()
		local big = (result.kind == "levels") and (result.rarity == "Mythical")
		playMeteor(big, function() showResultCard(result, closeReveal) end)
	elseif result.reason == "no_pets" then
		showMessage("Unlock A Pet To Receive Levels")
	end
end)

end)()
