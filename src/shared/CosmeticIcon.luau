--!nonstrict
-- CosmeticIcon (ReplicatedStorage/Shared/CosmeticIcon)
-- Builds a stylized 2D reveal-card icon for any cosmetic, purely from CosmeticConfig data
-- (no asset ids). Used by CrateClient.playReveal. The icon is a self-contained GuiObject the
-- caller parents into the reveal card.
--
--   CosmeticIcon.build(cosmetic, parent[, size]) -> Frame
--
-- The look keys off cosmetic.type and color/gradient: a rounded tile tinted by the cosmetic
-- color (or a UIGradient sweep for multi-color legendaries) with a per-type glyph on top.

local CosmeticConfig = require(script.Parent:WaitForChild("CosmeticConfig"))

local CosmeticIcon = {}

local GLYPHS = {
	JetpackFlames = "🔥",
	FartTrails    = "💨",
	Pets          = "🪐",
	LaunchEffects = "🚀",
	Auras         = "✨",
}

local function makeGradient(colors)
	local keys = {}
	local n = #colors
	for i, col in ipairs(colors) do
		local t = (n == 1) and 0 or (i - 1) / (n - 1)
		table.insert(keys, ColorSequenceKeypoint.new(t, col))
	end
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(keys)
	grad.Rotation = 45
	return grad
end

-- Build the reveal icon. Returns the root Frame (already parented if `parent` given).
function CosmeticIcon.build(cosmetic, parent, size)
	size = size or 132

	local color = (cosmetic and cosmetic.color) or Color3.fromRGB(150, 160, 172)
	local rarity = cosmetic and cosmetic.rarity or "Common"
	local rarityColor = CosmeticConfig.RARITY_COLORS[rarity] or color

	local root = Instance.new("Frame")
	root.Name = "CosmeticIcon"
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundColor3 = Color3.fromRGB(24, 26, 38)
	root.BorderSizePixel = 0

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 16)
	rootCorner.Parent = root

	-- Rarity-tinted stroke around the whole tile.
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = 3
	stroke.Parent = root

	-- The colored "chip" filling most of the tile (gradient for multi-color items).
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.Position = UDim2.fromScale(0.5, 0.5)
	chip.Size = UDim2.fromScale(0.78, 0.78)
	chip.BackgroundColor3 = color
	chip.BorderSizePixel = 0
	chip.Parent = root

	local chipCorner = Instance.new("UICorner")
	-- Pets read as "round" when their shape is a Ball; everything else is a soft-rounded square.
	if cosmetic and cosmetic.type == "Pets" and cosmetic.shape == "Ball" then
		chipCorner.CornerRadius = UDim.new(1, 0)
	else
		chipCorner.CornerRadius = UDim.new(0, 12)
	end
	chipCorner.Parent = chip

	if cosmetic and cosmetic.gradient and #cosmetic.gradient > 1 then
		makeGradient(cosmetic.gradient).Parent = chip
	end

	-- Neon pets glow a touch brighter.
	if cosmetic and cosmetic.neon then
		local glow = Instance.new("UIStroke")
		glow.Color = color
		glow.Thickness = 4
		glow.Transparency = 0.35
		glow.Parent = chip
	end

	-- Per-type glyph on top of the chip.
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = GLYPHS[cosmetic and cosmetic.type] or "★"
	glyph.TextScaled = true
	glyph.Font = Enum.Font.GothamBold
	glyph.TextColor3 = Color3.fromRGB(255, 255, 255)
	glyph.Parent = chip

	local glyphPad = Instance.new("UIPadding")
	glyphPad.PaddingTop = UDim.new(0.18, 0)
	glyphPad.PaddingBottom = UDim.new(0.18, 0)
	glyphPad.PaddingLeft = UDim.new(0.18, 0)
	glyphPad.PaddingRight = UDim.new(0.18, 0)
	glyphPad.Parent = glyph

	if parent then
		root.Parent = parent
	end
	return root
end

return CosmeticIcon
