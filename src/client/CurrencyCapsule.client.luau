--======================================================================
-- CurrencyCapsule.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE CURRENCY CAPSULE -- tokens and coins as ONE premium component.
--
-- PORTABLE COPY. This is the top-right currency HUD from Fart to Float, lifted out whole and
-- cut free of that game: the original read the coin value out of CoreClient's own GUI, adopted
-- CoreClient's "+" button, and pulled tokens off a _G global. All three are now CONFIG, so this
-- file builds and owns everything itself and can be dropped into any realm untouched.
--
-- The shape is THREE NESTED CAPSULES, not one box with two rectangles cut out of it: a dark
-- navy outer capsule, and floating inside it on a consistent inset, two fully rounded pills --
-- navy tokens and gold coins. The frame showing through the gap between them IS the divider, so
-- it follows the same curve as everything else and there is no square corner anywhere in it.
--
-- The pills are MATCHED and SELF-SIZING. Each is only as wide as its own icon + digits + "+",
-- then both are squared off to the wider of the two, so there is never a slab of dead gold after
-- the coin count and the halves always look like a pair.
--
--     [ gear ] <-GAP-> (( ticket 1,234 )( $ 5,678 ))
--
-- NO DROP SHADOW BEHIND IT. Soft shadow frames stacked behind the capsule show through as a
-- visible shaded slab on a bright HUD rather than reading as depth -- Roblox has no real blur,
-- so a "soft" shadow is just a bigger flat rectangle. All the depth comes from inside the
-- component: gradients, inner shadows, rim highlights and contact shadows.
--
-- ===== WHY THE LAYOUT IS A UIListLayout AND NOTHING IS MEASURED =====
-- HUD ScreenGuis do NOT share a coordinate space. In one and the same frame, different guis can
-- report an 800x600 space and the real 2015x1042 viewport. Any version of this that measured
-- pixels in one gui and wrote them into another computed correctly and landed wrong -- and the
-- diagnostics, printed early in a join before the viewport settles, agreed with the maths
-- instead of with the screen.
--
-- So no position is measured. The gear (if this realm has one) and the capsule are REPARENTED
-- into one row frame and a UIListLayout does the spacing: one space, one scale, one owner. A
-- rival script writing Position on either is simply ignored -- children of a list layout do not
-- use their own Position at all.
--
-- ===== WIRING IT UP =====
-- Everything you need to change is in CONFIG. The value sources are tried in order:
--     1. whatever was last passed to _G.CurrencyCapsule.setCoins() / .setTokens()
--     2. leaderstats.<COIN_STAT> / leaderstats.<TOKEN_STAT>
--     3. _G[<COIN_GLOBAL>] / _G[<TOKEN_GLOBAL>]
--     4. an existing TextLabel elsewhere in PlayerGui, named in MIRROR_COIN_LABEL
-- so a realm with leaderstats needs no code at all, and one that keeps its balance in a script
-- just calls the setter. Set SHOW_TOKENS = false for a coins-only realm; the capsule closes up
-- around the single pill and stays the same component.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

--======================================================================
-- CONFIG -- the whole of what a new realm has to think about
--======================================================================
local CONFIG = {
	-- ---- what it shows -------------------------------------------------------------
	SHOW_TOKENS = true,          -- false = coins only; the capsule closes up around one pill
	TOKEN_ICON  = "\xF0\x9F\x8E\x9F",  -- the ticket emoji. Emoji render in their OWN colours --
	                             -- TextColor3 is ignored on them -- so if you want a recoloured
	                             -- icon here, use an ImageLabel instead of this string.

	-- ---- where the numbers come from ------------------------------------------------
	COIN_STAT    = "Coins",      -- leaderstats value name, or nil to skip
	TOKEN_STAT   = nil,          -- leaderstats value name for tokens, or nil
	COIN_GLOBAL  = nil,          -- e.g. "coinBalance" -> reads _G.coinBalance
	TOKEN_GLOBAL = "crateTokenBalance",
	MIRROR_COIN_LABEL = nil,     -- last resort: the NAME of an existing TextLabel in PlayerGui to
	                             -- copy digits out of, for a realm whose balance only exists on
	                             -- screen. Leave nil unless you need it.

	-- ---- what the buttons do ---------------------------------------------------------
	-- Called on click. Left nil, a "+" is simply not drawn on that pill -- better than a button
	-- that does nothing.
	ON_COIN_PLUS  = function() local f = _G.openCoinShop  or _G.togglePremiumShop if type(f) == "function" then pcall(f) end end,
	ON_TOKEN_PLUS = function() local f = _G.openTokenShop or _G.toggleSkinCrates  if type(f) == "function" then pcall(f) end end,
	ON_TOKEN_TAP  = function() local f = _G.openTokenShop or _G.toggleSkinCrates  if type(f) == "function" then pcall(f) end end,
	CLICK_SOUND   = "playUIClick",  -- _G function name to call on any click, or nil

	-- ---- where it sits ---------------------------------------------------------------
	RIGHT_MARGIN = 10,           -- px from the right edge of the screen
	TOP          = 10,           -- px down from the top
	GEAR_GUI     = "SettingsGui",      -- adopt a gear button into the row if these exist...
	-- "SettingsButton", NOT "SettingsGearBtn". In this realm SettingsGearBtn is only the
	-- transparent hit target -- the visible face (frame, gradient, borders, shadow, gear
	-- glyph, worn edge) is its PARENT, built by Bootstrap as `settingsRoot`. Adopting the
	-- hit target alone would put an invisible 56x56 hole in the row and leave the button
	-- itself behind in the old bar. Bootstrap reparents `settingsRoot` into SettingsGui
	-- for us -- see the note there.
	GEAR_BTN     = "SettingsButton",   -- ...otherwise the capsule sits alone. nil = never look.
	DISPLAY_ORDER = 20,
}

--======================================================================
-- LOOK -- change colours here, not in the build
--======================================================================
local CAP_H     = 60    -- the component's height; everything else is derived from it
local PAD       = 6     -- inset between the outer frame and the inner pills
local INNER_GAP = 6     -- gap between the two inner pills -- this is the divider
local GAP       = 8     -- breathing room between the gear and the capsule

local INNER_H = CAP_H - PAD * 2
local START_W = 120     -- each pill's width before fit() measures the real digits
local MIN_W   = 120     -- a pill never gets narrower than this, however short the number

-- DINO PALETTE. The same jungle set BottomHUD uses, so the two ends of the HUD belong to
-- one realm: dark forest recess, bamboo outlines, cream text.
--
-- THE OUTER FRAME IS A TROUGH, NOT A PANEL. It was navy -- a dark container -- and it stays
-- dark here rather than going olive like the bottom card, because the pills sitting in it
-- are the bright element. That is exactly the bottom HUD's own logic: dark track, bright
-- fill. Olive frame + bright pills would be two mid-tones with nothing between them.
local FRAME_TOP  = Color3.fromRGB( 58,  86,  52)  -- outer frame, lit upper edge
local FRAME_MID  = Color3.fromRGB( 38,  62,  36)
local FRAME_BOT  = Color3.fromRGB( 26,  44,  26)  -- outer frame, shaded underside
-- Bamboo, not a dark hairline: in this realm EVERY outer outline is bamboo, and it is the
-- single strongest cue tying this capsule to the card at the bottom of the screen.
local FRAME_LINE = Color3.fromRGB(240, 214, 138)
-- TOKENS GO LEAF-GREEN (was royal blue). Green reads as the realm, and it is the one hue
-- that stays clearly distinct from the coins beside it -- which have to remain gold.
local NAVY_TOP   = Color3.fromRGB(140, 206, 104)  -- token pill
local NAVY_MID   = Color3.fromRGB( 86, 158,  70)
local NAVY_BOT   = Color3.fromRGB( 52, 112,  52)
local NAVY_LINE  = Color3.fromRGB( 28,  62,  30)
-- COINS STAY GOLD, warmed toward amber. Coins are gold in every game and recolouring them
-- past recognition costs more than the theming gains -- amber is also about as prehistoric
-- as a colour gets, so this one needed shifting rather than replacing.
local GOLD_TOP   = Color3.fromRGB(255, 226, 140)  -- coin pill: gold, through amber, to bark
local GOLD_MID   = Color3.fromRGB(240, 186,  72)
local GOLD_BOT   = Color3.fromRGB(206, 132,  34)
local GOLD_LINE  = Color3.fromRGB(128,  72,  16)
local CREAM      = Color3.fromRGB(255, 252, 238)  -- every digit and "+" on the capsule

local PLUS_W  = 26   -- the little "+" at the end of each pill
local TRAIL   = 12   -- air after the "+" before the pill's rounded cap
local TOKEN_X = 53   -- where each pill's number starts, measured from its own left edge
local COIN_X  = 66

--======================================================================
-- HELPERS
--======================================================================
local function corner(inst, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst; return c
end
local function stroke(inst, col, t, trans)
	local s = Instance.new("UIStroke")
	s.Color = col; s.Thickness = t; s.Transparency = trans or 0
	s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = inst; return s
end
local function grad(inst, seq, rot)
	local g = Instance.new("UIGradient"); g.Color = seq; g.Rotation = rot or 90; g.Parent = inst; return g
end
local function three(a, b, c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.55, b), ColorSequenceKeypoint.new(1, c),
	})
end
local function click()
	local name = CONFIG.CLICK_SOUND
	if name and type(_G[name]) == "function" then pcall(_G[name]) end
end

-- INNER SHADOW -- a soft dark ring hugging the inside of a pill's edge. This is what gives a
-- rounded panel the sense of sitting DOWN in its frame, and with no drop shadow behind the
-- component it is doing most of the work.
local function innerShadow(pill, radius, col, thickness, trans)
	local sh = Instance.new("Frame")
	sh.Name = "InnerShadow"
	sh.BackgroundTransparency = 1
	sh.Size = UDim2.new(1, 0, 1, 0)
	sh.ZIndex = pill.ZIndex + 1
	sh.Parent = pill
	corner(sh, radius)
	stroke(sh, col, thickness, trans)
	return sh
end

-- RIM HIGHLIGHT -- a short hairline of light along the top of a pill, fading out at both ends.
-- Gentle: it suggests one soft light source rather than a reflective strip.
local function rimLight(pill, widthFrac, trans)
	local r = Instance.new("Frame")
	r.Name = "RimLight"
	r.AnchorPoint = Vector2.new(0.5, 0)
	r.Position = UDim2.new(0.5, 0, 0, 3)
	r.Size = UDim2.new(widthFrac, 0, 0, 2)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BackgroundTransparency = trans
	r.BorderSizePixel = 0
	r.ZIndex = pill.ZIndex + 3
	r.Parent = pill
	corner(r, 1)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = r
	return r
end

-- CONTACT SHADOW -- the small soft pool an icon casts on the panel under it. Tiny, but it is the
-- difference between an icon sitting ON the surface and floating above it. Safe here because it
-- is INSIDE a pill, over a known colour, so it reads as shading and not as a slab.
local function contactShadow(parent, host, w, h)
	local sh = Instance.new("Frame")
	sh.Name = "ContactShadow"
	sh.AnchorPoint = Vector2.new(0.5, 0.5)
	sh.Position = UDim2.new(0, host.Position.X.Offset + host.Size.X.Offset / 2, 0.5, 7)
	sh.Size = UDim2.fromOffset(w, h)
	sh.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	sh.BackgroundTransparency = 0.72
	sh.BorderSizePixel = 0
	sh.ZIndex = host.ZIndex - 1
	sh.Parent = parent
	corner(sh, math.floor(h / 2))
	return sh
end

-- THE NUMBER -- white, thick clean outline, a soft drop shadow behind it for readability over
-- both the navy and the gold. The label is AutomaticSize.X, so it is exactly as wide as its
-- digits. That is what lets each pill hug its own value instead of reserving a fixed slot.
--
-- The drop shadow is SCALE-sized inside the box rather than auto-sized, so it is excluded from
-- the box's content measurement -- otherwise both labels would try to define the width and the
-- box would fight itself.
local function autoNumber(parent, size, x)
	local box = Instance.new("Frame")
	box.Name = "ValueBox"
	box.BackgroundTransparency = 1
	box.AutomaticSize = Enum.AutomaticSize.X
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.new(0, x, 0.5, 0)
	box.Size = UDim2.fromOffset(0, 32)
	box.ZIndex = 8
	box.Parent = parent

	local shadow = Instance.new("TextLabel")
	shadow.Name = "ValueShadow"
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.new(0, 0, 0, 2)
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.Font = Enum.Font.FredokaOne
	shadow.TextSize = size
	shadow.TextColor3 = Color3.new(0, 0, 0)
	shadow.TextTransparency = 0.62
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.Text = "0"
	shadow.ZIndex = 8
	shadow.Parent = box

	local t = Instance.new("TextLabel")
	t.Name = "Value"
	t.BackgroundTransparency = 1
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 32)
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = CREAM   -- cream, not pure white: the same text colour as the bottom card
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = "0"
	t.ZIndex = 10
	t.Parent = box
	stroke(t, Color3.new(0, 0, 0), 3)

	t:GetPropertyChangedSignal("Text"):Connect(function() shadow.Text = t.Text end)
	return t
end

-- 1234567 -> "1,234,567". Big numbers are the point of a simulator HUD; an unbroken run of
-- digits is the one thing that makes them unreadable.
local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- A "+" BUTTON -- a bare white glyph, no chip behind it. A green circle reads as a third element
-- competing with the icon and the number; the plus alone says the same thing and lets each pill
-- stay one clean shape. It keeps the numbers' dark outline so it is as legible on gold as on
-- navy, and it is still a full-size hit target.
local function plusButton(parent, onClick)
	local b = Instance.new("TextButton")
	b.Name = "PlusBtn"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -TRAIL, 0.5, 0)
	b.Size = UDim2.fromOffset(PLUS_W, PLUS_W)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 26
	b.TextColor3 = CREAM
	b.Text = "+"
	b.ZIndex = 12
	b.Parent = parent
	local ts = Instance.new("UIStroke")  -- the same dark edge the numbers carry
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 2.5
	ts.LineJoinMode = Enum.LineJoinMode.Round
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.Parent = b
	b.MouseButton1Click:Connect(function() click(); onClick() end)
	return b
end

--======================================================================
-- THE CAPSULE
--======================================================================
local tokenValue, coinValue             -- the two number labels, read by the value pass
local capRef, tokenPillRef, coinPillRef -- resized from those values, see fit()

-- FIT -- each pill is sized from its own content, then both are squared off to the WIDER of the
-- two so the capsule stays symmetrical. TextBounds is the natural width of the digits and is
-- independent of the pill's own size, so there is no feedback loop between the two.
local function fit()
	if not (capRef and coinPillRef and coinValue) then return end
	local w = math.max(COIN_X + coinValue.TextBounds.X + 8 + PLUS_W + TRAIL, MIN_W)
	if tokenPillRef and tokenValue then
		w = math.max(w, TOKEN_X + tokenValue.TextBounds.X + 8 + PLUS_W + TRAIL)
	end
	if math.abs(coinPillRef.Size.X.Offset - w) <= 0.5 then return end

	coinPillRef.Size = UDim2.fromOffset(w, INNER_H)
	if tokenPillRef then
		tokenPillRef.Size = UDim2.fromOffset(w, INNER_H)
		capRef.Size = UDim2.fromOffset(PAD * 2 + w * 2 + INNER_GAP, CAP_H)
	else
		capRef.Size = UDim2.fromOffset(PAD * 2 + w, CAP_H)
	end
end

-- THE COIN -- built in layers so it has real depth: a shaded thick edge, a lit face, a milled
-- inner ring, an embossed $ (dark cut over a light lower lip), and one small glint.
local function buildCoin(coinPill)
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 14, 0.5, 0)
	coin.Size = UDim2.fromOffset(38, 38)
	coin.BackgroundColor3 = Color3.fromRGB(186, 118, 22)
	coin.BorderSizePixel = 0
	coin.ZIndex = 8
	coin.Parent = coinPill
	corner(coin, 19)
	stroke(coin, Color3.fromRGB(96, 58, 12), 2)
	contactShadow(coinPill, coin, 30, 8)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.new(0.5, 0, 0.5, -1)
	face.Size = UDim2.fromOffset(32, 32)
	face.BackgroundColor3 = Color3.fromRGB(248, 202, 84)
	face.BorderSizePixel = 0
	face.ZIndex = 9
	face.Parent = coin
	corner(face, 16)
	grad(face, three(Color3.fromRGB(255, 240, 190), Color3.fromRGB(246, 198, 78),
		Color3.fromRGB(200, 132, 30)), 90)

	local ring = Instance.new("Frame")   -- milled inner ring
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.fromOffset(25, 25)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 10
	ring.Parent = face
	corner(ring, 13)
	stroke(ring, Color3.fromRGB(176, 112, 20), 1.5, 0.25)

	local lip = Instance.new("TextLabel")  -- lit lower lip of the embossed cut
	lip.Name = "DollarLip"
	lip.BackgroundTransparency = 1
	lip.Position = UDim2.new(0, 0, 0, 1)
	lip.Size = UDim2.new(1, 0, 1, 0)
	lip.Font = Enum.Font.FredokaOne
	lip.TextSize = 21
	lip.TextColor3 = Color3.fromRGB(255, 240, 186)
	lip.Text = "$"
	lip.ZIndex = 10
	lip.Parent = face

	local dollar = Instance.new("TextLabel")
	dollar.Name = "Dollar"
	dollar.BackgroundTransparency = 1
	dollar.Size = UDim2.new(1, 0, 1, 0)
	dollar.Font = Enum.Font.FredokaOne
	dollar.TextSize = 21
	dollar.TextColor3 = Color3.fromRGB(140, 84, 14)
	dollar.Text = "$"
	dollar.ZIndex = 11
	dollar.Parent = face

	local glint = Instance.new("Frame")  -- one small specular, upper left, at an angle
	glint.Name = "Glint"
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.new(0.33, 0, 0.26, 0)
	glint.Size = UDim2.fromOffset(11, 6)
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.BackgroundTransparency = 0.3
	glint.BorderSizePixel = 0
	glint.Rotation = -34
	glint.ZIndex = 12
	glint.Parent = face
	corner(glint, 3)
end

local function build(parent)
	-- ---- OUTER FRAME ------------------------------------------------------------------
	-- Dark navy rather than flat black, gradient-lit from above, with one thin containing
	-- outline. Nothing is drawn BEHIND it -- see the header note on drop shadows.
	local cap = Instance.new("Frame")
	cap.Name = "CurrencyCapsule"
	cap.Size = UDim2.fromOffset(START_W * 2, CAP_H)
	cap.BackgroundColor3 = FRAME_BOT
	cap.BorderSizePixel = 0
	cap.ZIndex = 3
	cap.Parent = parent
	corner(cap, CAP_H / 2)
	grad(cap, three(FRAME_TOP, FRAME_MID, FRAME_BOT), 90)
	stroke(cap, FRAME_LINE, 2)
	rimLight(cap, 0.86, 0.70)   -- the frame's own bevel, nothing more

	-- ---- TOKEN PILL (left) -------------------------------------------------------------
	-- A fully rounded capsule, inset by PAD on every side. A TextButton, because tapping it
	-- opens wherever tokens are spent.
	local tokenPill
	if CONFIG.SHOW_TOKENS then
		tokenPill = Instance.new("TextButton")
		tokenPill.Name = "TokenPill"
		tokenPill.AnchorPoint = Vector2.new(0, 0.5)
		tokenPill.Position = UDim2.new(0, PAD, 0.5, 0)
		tokenPill.Size = UDim2.fromOffset(START_W, INNER_H)
		tokenPill.BackgroundColor3 = NAVY_BOT
		tokenPill.BorderSizePixel = 0
		tokenPill.AutoButtonColor = false
		tokenPill.Text = ""
		tokenPill.ZIndex = 5
		tokenPill.Parent = cap
		corner(tokenPill, INNER_H / 2)
		grad(tokenPill, three(NAVY_TOP, NAVY_MID, NAVY_BOT), 90)
		stroke(tokenPill, NAVY_LINE, 2)
		innerShadow(tokenPill, INNER_H / 2, Color3.fromRGB(14, 40, 18), 3, 0.55)
		rimLight(tokenPill, 0.62, 0.72)

		local ticket = Instance.new("TextLabel")
		ticket.Name = "Ticket"
		ticket.BackgroundTransparency = 1
		ticket.AnchorPoint = Vector2.new(0, 0.5)
		ticket.Position = UDim2.new(0, 13, 0.5, 0)
		ticket.Size = UDim2.fromOffset(32, 32)
		ticket.Font = Enum.Font.FredokaOne
		ticket.TextSize = 28
		ticket.Text = CONFIG.TOKEN_ICON
		ticket.ZIndex = 8
		ticket.Parent = tokenPill
		contactShadow(tokenPill, ticket, 26, 7)

		tokenValue = autoNumber(tokenPill, 26, TOKEN_X)

		if CONFIG.ON_TOKEN_PLUS then plusButton(tokenPill, CONFIG.ON_TOKEN_PLUS) end
		if CONFIG.ON_TOKEN_TAP then
			tokenPill.MouseButton1Click:Connect(function() click(); CONFIG.ON_TOKEN_TAP() end)
		end
	end

	-- ---- COIN PILL (right) -------------------------------------------------------------
	-- Its own rounded capsule, INNER_GAP away from the token pill. The dark frame showing
	-- through that gap is the divider -- so the divider is curved, like everything else.
	local coinPill = Instance.new("Frame")
	coinPill.Name = "CoinPill"
	coinPill.AnchorPoint = Vector2.new(1, 0.5)
	coinPill.Position = UDim2.new(1, -PAD, 0.5, 0)
	coinPill.Size = UDim2.fromOffset(START_W, INNER_H)
	coinPill.BackgroundColor3 = GOLD_BOT
	coinPill.BorderSizePixel = 0
	coinPill.ZIndex = 5
	coinPill.Parent = cap
	corner(coinPill, INNER_H / 2)
	grad(coinPill, three(GOLD_TOP, GOLD_MID, GOLD_BOT), 90)
	stroke(coinPill, GOLD_LINE, 2)
	innerShadow(coinPill, INNER_H / 2, Color3.fromRGB(120, 62, 10), 3, 0.6)
	rimLight(coinPill, 0.5, 0.74)

	buildCoin(coinPill)
	coinValue = autoNumber(coinPill, 28, COIN_X)
	if CONFIG.ON_COIN_PLUS then plusButton(coinPill, CONFIG.ON_COIN_PLUS) end

	capRef, tokenPillRef, coinPillRef = cap, tokenPill, coinPill
	fit()
	return cap
end

--======================================================================
-- VALUES -- four sources, tried in order, first one that answers wins
--======================================================================
local override = {}   -- filled by the public setters below

local function readStat(statName, globalName, key, mirrorName)
	if override[key] then return override[key] end

	if statName then
		local ls = player:FindFirstChild("leaderstats")
		local v = ls and ls:FindFirstChild(statName)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
	end
	if globalName then
		local n = tonumber(_G[globalName])
		if n then return n end
	end
	if mirrorName then
		for _, d in ipairs(PlayerGui:GetDescendants()) do
			if d.Name == mirrorName and d:IsA("TextLabel") then
				local digits = d.Text:gsub("[^%d]", "")
				if #digits > 0 then return tonumber(digits) end
			end
		end
	end
	return nil
end

-- The public handle. A realm that keeps its balance in a script just calls these; anything set
-- here outranks leaderstats and the globals, so it is also the clean way to drive the HUD from
-- a RemoteEvent.
_G.CurrencyCapsule = {
	setCoins  = function(n) override.coins  = tonumber(n) or 0 end,
	setTokens = function(n) override.tokens = tonumber(n) or 0 end,
	config    = CONFIG,
}

--======================================================================
-- THE LAYOUT + VALUE PASS
--======================================================================
local warnedTwinGear = false          -- the duplicate-gear warning is worth saying once
local ZERO_ANCHOR    = Vector2.new(0, 0)

local gui = Instance.new("ScreenGui")
gui.Name = "CurrencyCapsuleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = CONFIG.DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

local row = Instance.new("Frame")
row.Name = "TopRightRow"
row.BackgroundTransparency = 1
row.AnchorPoint = Vector2.new(1, 0)
row.Position = UDim2.new(1, -CONFIG.RIGHT_MARGIN, 0, CONFIG.TOP)
row.Size = UDim2.fromOffset(0, 0)
row.AutomaticSize = Enum.AutomaticSize.XY   -- exactly as wide as its contents
row.ZIndex = 20
row.Parent = gui
-- Inherited from the bar this replaced. ResponsiveUI (attachScale) reads this attribute off
-- whatever it hangs a UIScale on and multiplies it into the global phone scale; the old
-- CoinGui cluster carried 0.78, so without it the capsule renders noticeably larger than
-- the HUD it sits in on a phone. Desktop is unaffected -- the phone branch never runs.
row:SetAttribute("ResponsiveExtraShrink", 0.78)

local lay = Instance.new("UIListLayout")
lay.FillDirection = Enum.FillDirection.Horizontal
lay.HorizontalAlignment = Enum.HorizontalAlignment.Right
lay.VerticalAlignment = Enum.VerticalAlignment.Center
lay.SortOrder = Enum.SortOrder.LayoutOrder
lay.Padding = UDim.new(0, GAP)
lay.Parent = row

local capsule = build(row)
_G.CurrencyCapsule.gui, _G.CurrencyCapsule.row, _G.CurrencyCapsule.capsule = gui, row, capsule

task.spawn(function()
	local nextCount = 0
	while true do
		-- ---- VALUES, four times a second ------------------------------------------------
		if os.clock() >= nextCount then
			nextCount = os.clock() + 0.25
			local c = readStat(CONFIG.COIN_STAT, CONFIG.COIN_GLOBAL, "coins", CONFIG.MIRROR_COIN_LABEL)
			if c and coinValue then coinValue.Text = commas(c) end
			if tokenValue then
				local t = readStat(CONFIG.TOKEN_STAT, CONFIG.TOKEN_GLOBAL, "tokens", nil)
				tokenValue.Text = commas(t or 0)
			end
			fit()   -- both pills re-hug their digits, then square off to the wider one
		end

		-- ---- THE GEAR, IF THIS REALM HAS ONE ---------------------------------------------
		-- THERE MAY BE TWO: more than one script can build a ScreenGui with the same name, and
		-- FindFirstChild would return only one of them. Every copy is collected; the first is
		-- laid out, the rest are hidden as the duplicates they are.
		if CONFIG.GEAR_GUI and CONFIG.GEAR_BTN then
			local gear, extras = nil, 0
			for _, sg in ipairs(PlayerGui:GetChildren()) do
				if sg:IsA("ScreenGui") and sg.Name == CONFIG.GEAR_GUI then
					local g = sg:FindFirstChild(CONFIG.GEAR_BTN)
					if g and g:IsA("GuiObject") then
						if gear == nil then gear = g
						elseif g.Visible then g.Visible = false; extras = extras + 1 end
					end
				end
			end
			if gear == nil then gear = row:FindFirstChild(CONFIG.GEAR_BTN) end
			if extras > 0 and not warnedTwinGear then
				warnedTwinGear = true
				warn("[Capsule] hid " .. extras .. " DUPLICATE '" .. CONFIG.GEAR_BTN
					.. "' button(s) -- two scripts build a '" .. CONFIG.GEAR_GUI .. "'. Delete one.")
			end

			-- ADOPT: move it into the row once, then only keep its order. AnchorPoint is
			-- re-asserted EVERY frame, not just on the way in: a UIListLayout ignores a child's
			-- Position but NOT its AnchorPoint, and a rival script re-stamping (1, 0) would slide
			-- the element a full width sideways inside the row.
			if gear and gear.Parent then
				if gear.Parent ~= row then
					gear.Position = UDim2.new()
					gear.Parent = row
				end
				if gear.AnchorPoint ~= ZERO_ANCHOR then gear.AnchorPoint = ZERO_ANCHOR end
				gear.LayoutOrder = 1
			end
		end
		capsule.LayoutOrder = 2   -- the capsule always sits at the right-hand end of the row

		RunService.RenderStepped:Wait()
	end
end)

print(("[Capsule] currency capsule ready -- %s, right-aligned %dpx from the edge. "
	.. "Values: leaderstats(%s/%s) -> _G(%s/%s) -> _G.CurrencyCapsule.setCoins/setTokens."):format(
	CONFIG.SHOW_TOKENS and "[ticket | coins]" or "[coins]", CONFIG.RIGHT_MARGIN,
	tostring(CONFIG.COIN_STAT), tostring(CONFIG.TOKEN_STAT),
	tostring(CONFIG.COIN_GLOBAL), tostring(CONFIG.TOKEN_GLOBAL)))
