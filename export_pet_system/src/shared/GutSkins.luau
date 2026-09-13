--!strict
-- ============================================================================
-- GUT SKINS — shared cosmetic config (required by BellySystem, GutSkinService, GutSkinClient).
-- Skins are COSMETIC ONLY (never change tier size/power) and are EARNED BY CUMULATIVE PLAYTIME.
--
-- HOW A SKIN RENDERS (all optional except id/displayName/rarity/material/source):
--   color    : Color3 base tint applied to every gut part. nil = use the player's skin/torso colour (Default).
--   material : Enum.Material for every gut part.
--   decal    : rbxassetid string -> ONE decal on the FRONT face only. nil/""/".../0" = none.
--   animated : "rainbow" -> the OWNING client cycles the colour each frame.
--   glow     : Color3 -> faint PointLight.   sparkle : true -> Sparkles.
--   rarity   : "Common" | "Rare" | "Epic" | "Legendary".
--   source   : how it's obtained -> "default" (free) | "playtime" | "crate" | "event" | "code".
--              Playtime skins unlock at GutSkins.UnlockMinutes[id]; others are granted by their system.
-- ============================================================================

local GutSkins = {}

GutSkins.RarityColor = {
	Common    = Color3.fromRGB(190, 190, 200),
	Rare      = Color3.fromRGB(80, 150, 255),
	Epic      = Color3.fromRGB(180, 90, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
}

-- ===================== PLAYTIME UNLOCK THRESHOLDS (minutes) ==================
-- Easy to edit. A skin with source="playtime" is auto-granted once the player's TOTAL cumulative
-- playtime (across all sessions) reaches its minutes here.
GutSkins.UnlockMinutes = {
	Default = 0,    -- free, owned from the start
	Gold    = 30,   -- 30 minutes
	Lava    = 90,   -- 1.5 hours
	Diamond = 180,  -- 3 hours
	Galaxy  = 300,  -- 5 hours
	Rainbow = 480,  -- 8 hours
}

-- ===================== EASY-EDIT SKIN TABLE (add skins here) =================
GutSkins.Skins = {
	Default = { id = "Default", displayName = "Default", rarity = "Common", source = "default",
		material = Enum.Material.SmoothPlastic, color = nil }, -- nil -> matches the avatar's skin/torso colour

	Gold = { id = "Gold", displayName = "Gold", rarity = "Rare", source = "playtime",
		material = Enum.Material.Metal, color = Color3.fromRGB(212, 175, 55) },

	-- molten look: deep red/orange glowing Neon. The gut's built-in top-lighter / bottom-darker shading
	-- (Sheen 1.10 / Sag 0.85) gives it a subtle bright-to-dark vertical variation -> reads like cooling lava.
	Lava = { id = "Lava", displayName = "Lava", rarity = "Rare", source = "playtime",
		material = Enum.Material.Neon, color = Color3.new(1, 0.35, 0.05) },

	Diamond = { id = "Diamond", displayName = "Diamond", rarity = "Epic", source = "playtime",
		material = Enum.Material.Glass, color = Color3.fromRGB(150, 220, 255), sparkle = true },

	Galaxy = { id = "Galaxy", displayName = "Galaxy", rarity = "Epic", source = "playtime",
		material = Enum.Material.Neon, color = Color3.fromRGB(60, 30, 110), sparkle = true,
		decal = "" }, -- TODO: starfield rbxassetid for the front-face decal (kept "" so nothing broken renders)

	Rainbow = { id = "Rainbow", displayName = "Rainbow", rarity = "Legendary", source = "playtime",
		material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(255, 80, 80), animated = "rainbow" },
}

-- display order for the UI grid
GutSkins.Order = { "Default", "Gold", "Lava", "Diamond", "Galaxy", "Rainbow" }

function GutSkins.get(id)
	return (type(id) == "string" and GutSkins.Skins[id]) or nil
end
function GutSkins.exists(id)
	return GutSkins.get(id) ~= nil
end
function GutSkins.unlockMinutes(id)
	return GutSkins.UnlockMinutes[id] or 0
end
-- a decal texture is only usable if it's a non-empty id that isn't the ".../0" placeholder
function GutSkins.decalOf(skin)
	local t = skin and skin.decal
	if type(t) == "string" and t ~= "" and not t:match("//0$") then return t end
	return nil
end
-- "1h 12m" / "3h" / "30m" from a minute count (UI helper)
function GutSkins.formatMinutes(mins)
	mins = math.max(0, math.floor(mins))
	local h, m = math.floor(mins / 60), mins % 60
	if h > 0 and m > 0 then return string.format("%dh %dm", h, m) end
	if h > 0 then return string.format("%dh", h) end
	return string.format("%dm", m)
end

return GutSkins
