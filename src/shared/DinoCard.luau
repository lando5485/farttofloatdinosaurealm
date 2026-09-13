--======================================================================
-- DinoCard.luau  (ModuleScript -> ReplicatedStorage/DinosaurRealm)
--======================================================================
-- THE TOP-CENTRE CARD, built in one place.
--
-- The objective card ("what to do on this island") and the storm banner occupy the SAME
-- 470x78 slot -- the storm hides the objective card and stands in its place. That swap
-- only reads as one panel changing its mind if both are pixel-identical in shape, and
-- they were previously two hand-built copies in two LocalScripts with a comment begging
-- whoever edits one to remember the other. This module is that comment made structural.
--
-- SHAPE IS SHARED, COLOUR IS NOT, and that split is the whole design:
--   * Geometry, corners, gloss, rim, inset highlight, type scale -- identical for every
--     card, so any two can swap in the slot without the frame appearing to move.
--   * The PALETTE is per-card, because a storm banner has to look like a storm. The rain
--     banner was originally a cold blue-grey and that colour was doing real work: it read
--     as weather at a glance. Repainting it bark-brown to match the island card threw
--     that away. Now it keeps its blue AND the shared silhouette.
--
-- THE DEPTH TREATMENT is what separates this from a flat rectangle, and it is all cheap
-- layers, not a texture. Every one of them answers the same question -- where is the light
-- coming from? -- and they only work because they all answer it the SAME way: from above.
--   1. a top-lit gloss gradient on the body -- light at the top edge, shaded at the bottom
--   2. a white sheen over the top third that fades out by the middle: the gloss supplies
--      the LIGHTING, the sheen supplies the FINISH
--   3. a coloured rim that is itself gradient-lit, brighter along the top edge -- a flat
--      stroke reads as a border, a lit one reads as a bevel
--   4. a white inset highlight just inside the rim, FADING DOWNWARD. A highlight that is
--      equally bright all the way round describes a ring; fading it describes a raised
--      panel. Highest-value detail in the file.
--   5. the icon well runs its gradient INVERTED (dark at top, light at the bottom), because
--      a recess is shaded by its own near wall -- which is what makes it a socket the glyph
--      sits inside rather than a tile stuck on the front
--
-- THERE IS DELIBERATELY NO DROP SHADOW. It was removed by request: the card reads flatter
-- and cleaner against open sky, and the lit rim and inset highlight already carry the edge.
-- See build() before adding one back -- it cannot just be parented in.
--
-- ⚠ THESE GUIS USE THE DEFAULT ZIndexBehavior (Sibling), WHERE A CHILD ALWAYS DRAWS IN
-- FRONT OF ITS PARENT. Anything that must sit BEHIND the card body has to be its SIBLING;
-- see the wrapper note in build(). A negative ZIndex on a child buys nothing at all.
--======================================================================

local DinoCard = {}

local function tint(c, a)  -- toward white
	return Color3.new(c.R + (1 - c.R) * a, c.G + (1 - c.G) * a, c.B + (1 - c.B) * a)
end
local function shade(c, m)  -- toward black
	return Color3.new(c.R * m, c.G * m, c.B * m)
end

DinoCard.W, DinoCard.H = 470, 78

-- base = card body | wood = gradient's light end | rim = stroke | text = title | sub = second line
-- | stroke = the outline behind the type
--
-- ===== ISLAND IS NOT INVENTED, IT IS THE REALM'S OWN SIGNAGE =====
-- Every panel in this game is themed by JungleChrome, and its wooden plaque -- the thing a
-- title already sits on everywhere else -- is a WARM MID-BROWN with a dark brown stroke and
-- cream lettering. This card used to be near-black with a gold rim, which belonged to no
-- other surface in the realm: next to a jungle-green panel with a wood plaque on it, the
-- banner read as a UI element borrowed from a different game.
-- These values are lifted from JungleChrome so the two cannot drift apart:
--     plaque body      Color3.fromRGB(126, 84, 48)      JungleChrome.luau:140
--     plaque gradient  (152,106,62) -> (108,70,38)      JungleChrome.luau:142
--     plaque stroke    Color3.fromRGB( 74, 46, 24)      JungleChrome.luau:141
--     title text       Color3.fromRGB(250,242,214)      JungleChrome.luau:145
--     title outline    Color3.fromRGB( 60, 38, 18)      JungleChrome.luau:147
--     bamboo (STONE_A) Color3.fromRGB(224,204,150)      JungleChrome.luau:16
-- If the chrome is ever retuned, retune these to match -- the reference lines are above so
-- the next person does not have to go hunting for where the brown came from.
-- BRIGHTENED off that reference rather than away from it: the hue and the relationships are
-- the plaque's, lifted about 30% in value so the card carries the top of the screen instead
-- of sinking into it. The rim goes back to warm gold -- the plaque's near-black stroke is
-- right when a plaque sits ON a lit green panel, but this card floats over open sky with
-- nothing behind it, and a dark edge there just reads as a hole.
DinoCard.ISLAND = {   -- the realm's wooden plaque, brightened for a card that stands alone
	base   = Color3.fromRGB(168, 116,  66),
	wood   = Color3.fromRGB(202, 150,  92),
	rim    = Color3.fromRGB(238, 196, 112),
	text   = Color3.fromRGB(255, 251, 236),
	sub    = Color3.fromRGB(244, 228, 186),
	stroke = Color3.fromRGB( 72,  44,  20),
}
-- The weather palettes stay COLD on purpose. Repainting them brown to "match" would throw
-- away the one thing their colour is doing -- reading as weather before a word is read --
-- and the shared silhouette already carries the family resemblance. What they DO share with
-- the plaque is brightness: all three sit at the same value, so swapping one for another in
-- the slot changes the hue and nothing else. A dim banner following a bright one reads as
-- the screen dimming rather than the message changing.
DinoCard.STORM = {    -- rain: cold blue, lifted to the same brightness as the plaque
	base   = Color3.fromRGB( 66,  96, 134),
	wood   = Color3.fromRGB( 96, 136, 182),
	rim    = Color3.fromRGB(158, 206, 244),
	text   = Color3.fromRGB(244, 250, 255),
	sub    = Color3.fromRGB(202, 226, 248),
	stroke = Color3.fromRGB( 20,  34,  52),
}
DinoCard.ICE = {      -- spare, for the Ice Age banner if it ever wants the same slot
	base   = Color3.fromRGB( 78, 124, 146),
	wood   = Color3.fromRGB(112, 168, 192),
	rim    = Color3.fromRGB(186, 236, 250),
	text   = Color3.fromRGB(246, 253, 255),
	sub    = Color3.fromRGB(210, 238, 248),
	stroke = Color3.fromRGB( 22,  42,  54),
}

-- Builds the card into `parent`. Returns a handle with :setText(title, sub) and
-- :setIcon(glyph); `frame` is the card itself, which is what a banner shows/hides and
-- what TopCenterStack adopts.
function DinoCard.build(parent, pal, name)
	pal = pal or DinoCard.ISLAND

	-- NO DROP SHADOW. The card sat on a soft dark pool behind it; removed by request -- it
	-- reads flatter and cleaner against the sky, and the lit rim plus the inset highlight
	-- already give the edge enough relief to separate it from the world.
	--
	-- ⚠ IF A SHADOW IS EVER WANTED BACK, IT CANNOT SIMPLY BE PARENTED TO THIS FRAME.
	-- These ScreenGuis use the default ZIndexBehavior (Sibling), where a child ALWAYS draws
	-- in FRONT of its parent -- a negative ZIndex buys nothing. That is exactly how the old
	-- shadow behaved: parented to the card, it was never behind it, it was a black sheet laid
	-- OVER the whole banner muddying every colour. It has to be a SIBLING, which means
	-- reintroducing a transparent wrapper frame to hold both.
	local frame = Instance.new("Frame")
	frame.Name = name or "Banner"
	frame.Size = UDim2.fromOffset(DinoCard.W, DinoCard.H)
	frame.Position = UDim2.new(0.5, 0, 0, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = pal.base
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = parent

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 16)

	-- 2) TOP-LIT GLOSS. Light at the top edge, base through the middle, shaded at the
	--    bottom -- the card reads as a solid object catching overhead light.
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   tint(pal.wood, 0.18)),
		ColorSequenceKeypoint.new(0.5, pal.base),
		ColorSequenceKeypoint.new(1,   shade(pal.base, 0.88)),   -- was 0.78: too dark under a bright body
	})
	g.Rotation = 90
	g.Parent = frame

	-- 2b) TOP SHEEN. A white wash over the upper third that fades to nothing by the middle,
	--     sitting ABOVE the base gradient. This is the layer that reads as a polished
	--     surface rather than a flat fill -- the base gradient gives the card its lighting,
	--     this gives it its FINISH. Kept subtle (0.88 at its strongest) because a sheen you
	--     consciously notice looks like a mistake.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.new(1, -6, 0, 34)
	sheen.Position = UDim2.new(0.5, 0, 0, 3)
	sheen.AnchorPoint = Vector2.new(0.5, 0)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	sheen.ZIndex = frame.ZIndex + 1
	sheen.Parent = frame
	Instance.new("UICorner", sheen).CornerRadius = UDim.new(0, 13)
	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	sg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	sg.Parent = sheen

	-- 3) RIM, lit from above. A single flat colour round the whole edge is what makes a
	--    stroke look like a border instead of a bevel, so the rim carries its own gradient:
	--    brightened at the top where the light is, darkened at the bottom. Same trick as the
	--    body gloss, applied to the edge, and it costs one instance.
	local st = Instance.new("UIStroke")
	st.Name = "Rim"
	st.Color = pal.rim
	st.Thickness = 3
	st.Parent = frame
	local rg = Instance.new("UIGradient")
	rg.Rotation = 90
	rg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tint(pal.rim, 0.35)),
		ColorSequenceKeypoint.new(0.55, pal.rim),
		ColorSequenceKeypoint.new(1, shade(pal.rim, 0.62)),
	})
	rg.Parent = st

	-- 4) INSET HIGHLIGHT -- the carved edge. Inset 5px, corner radius stepped down to
	--    match, white at high transparency so it reads as a lit bevel, not a second rim.
	local hl = Instance.new("Frame")
	hl.Name = "InnerHighlight"
	hl.AnchorPoint = Vector2.new(0.5, 0.5)
	hl.Position = UDim2.fromScale(0.5, 0.5)
	hl.Size = UDim2.new(1, -5, 1, -5)
	hl.BackgroundTransparency = 1
	hl.ZIndex = frame.ZIndex + 1
	hl.Parent = frame
	Instance.new("UICorner", hl).CornerRadius = UDim.new(0, 13)
	local hs = Instance.new("UIStroke")
	hs.Color = Color3.new(1, 1, 1); hs.Transparency = 0.74; hs.Thickness = 1.5; hs.Parent = hl
	-- ...and the bevel FADES DOWNWARD. A lit edge that is equally bright all the way round
	-- describes a ring, not a carved surface: light comes from above, so the highlight has
	-- to die out by the bottom. Fading it is what turns the rectangle into a raised panel.
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	hg.Parent = hs

	-- ICON WELL, left. A darkened recess so a glyph sits IN the card rather than on it.
	local well = Instance.new("Frame")
	well.Name = "IconWell"
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.new(0, 12, 0.5, 0)
	well.Size = UDim2.fromOffset(52, 52)
	well.BackgroundColor3 = shade(pal.base, 0.62)
	well.BackgroundTransparency = 0.25
	well.BorderSizePixel = 0
	well.Visible = false
	well.ZIndex = frame.ZIndex + 2
	well.Parent = frame
	Instance.new("UICorner", well).CornerRadius = UDim.new(0, 13)
	local ws = Instance.new("UIStroke"); ws.Color = pal.rim; ws.Transparency = 0.45; ws.Thickness = 1.5; ws.Parent = well
	-- RECESSED, not raised. The body is lit from the top; a hole in it is therefore DARKEST
	-- at the top, where the near wall shades it, and lightest at the bottom where light
	-- reaches the floor. That is the exact inverse of the card's own gloss, and running the
	-- gradient the other way is the whole reason this reads as a socket the glyph sits
	-- inside rather than a second tile stuck on the front.
	local wg = Instance.new("UIGradient")
	wg.Rotation = 90
	wg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, shade(pal.base, 0.45)),
		ColorSequenceKeypoint.new(1, tint(pal.base, 0.10)),
	})
	wg.Parent = well

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.FredokaOne
	icon.TextScaled = true
	icon.Text = ""
	icon.ZIndex = well.ZIndex + 1
	icon.Parent = well

	-- TEXT. Both lines live in one column so the pair can centre together when there is
	-- no sub-line -- a one-line instruction sitting high with a gap under it looks broken.
	local col = Instance.new("Frame")
	col.Name = "Text"
	col.BackgroundTransparency = 1
	col.AnchorPoint = Vector2.new(0.5, 0.5)
	col.Position = UDim2.fromScale(0.5, 0.5)
	col.Size = UDim2.new(1, -28, 1, -14)
	col.ZIndex = frame.ZIndex + 2
	col.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = pal.text
	title.TextScaled = true
	-- OUTLINE COMES FROM THE PALETTE. It was hardcoded near-black, which is a colour no
	-- palette here contains: on a warm brown card that put a cold grey halo round every
	-- letter. Each palette carries its own darkest tone so the outline reads as shadow in
	-- that colour family instead of a sticker edge.
	title.TextStrokeColor3 = pal.stroke or Color3.fromRGB(12, 8, 4)
	title.TextStrokeTransparency = 0.2
	title.Text = ""
	title.ZIndex = col.ZIndex + 1
	title.Parent = col
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 25; c.Parent = title end

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextColor3 = pal.sub
	sub.TextScaled = true
	sub.TextStrokeColor3 = pal.stroke or Color3.fromRGB(12, 8, 4)
	sub.TextStrokeTransparency = 0.45
	sub.Text = ""
	sub.ZIndex = col.ZIndex + 1
	sub.Parent = col
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = sub end

	-- With the shadows gone there is nothing to keep in sync, so `frame` is simply the card.
	-- `body` stays as an alias so anything written against the wrapper era still resolves.
	local handle = { frame = frame, body = frame, title = title, sub = sub,
		icon = icon, well = well, rim = st, pal = pal }

	-- One line or two. Laid out here rather than by the caller so every card that uses
	-- this module breathes the same way.
	-- ===== FIVE WORDS, ENFORCED HERE =====
	-- A banner is read at a glance while the player is moving, and the card is ONE line of
	-- fixed width -- past about five words TextScaled just shrinks the type until it is
	-- unreadable, which is the worst of both outcomes: too long AND too small.
	-- Enforced in the builder rather than trusted to every caller, so a quest string added
	-- later cannot quietly reintroduce a nine-word instruction. The strings themselves have
	-- been rewritten to fit, so in normal play nothing is actually cut -- this is the net,
	-- not the plan.
	local MAX_WORDS = 5
	local function clampWords(str)
		if str == "" then return str end
		local words, n = {}, 0
		for w in string.gmatch(str, "%S+") do
			n += 1
			if n > MAX_WORDS then
				-- Trailing punctuation on the last kept word would read as a finished
				-- sentence when it is not, so it is stripped before the ellipsis.
				words[#words] = string.gsub(words[#words], "[%p]+$", "")
				return table.concat(words, " ") .. "\226\128\166"   -- U+2026 ellipsis
			end
			words[#words + 1] = w
		end
		return str
	end

	function handle:setText(t, s)
		t = clampWords(t or "")
		s = clampWords(s or "")
		title.Text = t
		sub.Text = s
		local pad = well.Visible and 64 or 0
		col.Size = UDim2.new(1, -28 - pad, 1, -14)
		col.Position = UDim2.new(0.5, pad / 2, 0.5, 0)
		if s == "" then
			title.AnchorPoint = Vector2.new(0.5, 0.5)
			title.Position = UDim2.fromScale(0.5, 0.5)
			title.Size = UDim2.fromScale(1, 0.72)
			sub.Visible = false
		else
			title.AnchorPoint = Vector2.new(0.5, 0)
			title.Position = UDim2.new(0.5, 0, 0, 0)
			title.Size = UDim2.new(1, 0, 0.58, 0)
			sub.AnchorPoint = Vector2.new(0.5, 1)
			sub.Position = UDim2.new(0.5, 0, 1, 0)
			sub.Size = UDim2.new(1, 0, 0.36, 0)
			sub.Visible = true
		end
	end

	function handle:setIcon(glyph)
		if glyph and glyph ~= "" then
			icon.Text = glyph
			well.Visible = true
		else
			well.Visible = false
		end
		self:setText(title.Text, sub.Text)  -- re-flow: the well steals width from the column
	end

	return handle
end

return DinoCard
