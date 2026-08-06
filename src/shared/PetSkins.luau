--!nonstrict
-- PetSkins (ReplicatedStorage/Shared/PetSkins)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for pet SKIN THEMES + the inventory KEY FORMAT.
--
-- A skin is a THEME shared by EVERY pet: "Galaxy" works on Pizza Dragon, Butter Duck, Bean Buddy, anything.
-- That is deliberate -- it means adding a pet instantly gives it the whole existing skin collection, and adding
-- a skin instantly gives it to every pet, with no per-pet art.
--
-- HOW A SKIN RENDERS (all optional except id/displayName/tier):
--   color      : Color3 recoloured onto every BODY part (parts tagged role="body"; eyes are skipped).
--   material   : Enum.Material for those same parts.
--   refl       : 0..1 Reflectance (metal/glass sheen).
--   fx         : Color3 -> a matching sparkle/aura tint (the same field RARE_LOOK uses in PetFollow).
--   light      : true -> a soft PointLight in the pet's colour.
--   animated   : "rainbow" -> the owning client cycles the hue each frame.
--   tier       : the DEFAULT rarity band shown in the inventory when a skin arrives from outside a crate
--                (a code, an event grant). Crates declare their own rarity per entry -- see SkinCrates.
--
-- This mirrors src/shared/GutSkins.luau (the gut cosmetic config) on purpose: same shape, same helper style,
-- so the two cosmetic systems read identically. The render fields also mirror PetFollow's RARE_LOOK table
-- (body / mat / refl / fx / light), which is what actually paints a pet -- so PetSkinLook can hand a skin
-- straight to the existing renderer with no translation layer.
-- ============================================================================================================

local PetSkins = {}

-- ---- RARITY TIERS -------------------------------------------------------------------------------------------
-- Six bands, lowest to highest. "Gold" is the TOP TIER ONLY -- it is never a skin theme name (the gold-coloured
-- skin theme is called "Gilded"), so "Gold" in the UI always means the rarity, never a look.
PetSkins.TIER_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Gold" }
PetSkins.TierColor = {
	Common    = Color3.fromRGB(176, 182, 194), -- grey
	Uncommon  = Color3.fromRGB( 92, 200, 122), -- green
	Rare      = Color3.fromRGB( 70, 140, 255), -- blue
	Epic      = Color3.fromRGB(180,  90, 235), -- purple
	Legendary = Color3.fromRGB(255, 140,  40), -- orange
	Gold      = Color3.fromRGB(255, 206,  92), -- gold (the knife tier)
}
-- Rank number for sorting/comparison (higher = rarer).
PetSkins.TierRank = {}
for i, t in ipairs(PetSkins.TIER_ORDER) do PetSkins.TierRank[t] = i end

-- ---- THE SKIN THEMES ---------------------------------------------------------------------------------------
-- Add a theme here and EVERY pet can wear it immediately. Nothing else needs editing except the crate that
-- should drop it (SkinCrates.CRATES).
PetSkins.Skins = {
	-- ===== earthy / starter looks =====
	Stone     = { id="Stone",     displayName="Stone",     tier="Common",   color=Color3.fromRGB(142,146,152), material=Enum.Material.Slate },
	Sand      = { id="Sand",      displayName="Sand",      tier="Common",   color=Color3.fromRGB(226,202,144), material=Enum.Material.Sand },
	Moss      = { id="Moss",      displayName="Moss",      tier="Common",   color=Color3.fromRGB( 96,138, 74), material=Enum.Material.Grass },
	Mud       = { id="Mud",       displayName="Mud",       tier="Common",   color=Color3.fromRGB( 96, 72, 50), material=Enum.Material.Mud },
	Chocolate = { id="Chocolate", displayName="Chocolate", tier="Common",   color=Color3.fromRGB( 84, 52, 34), material=Enum.Material.SmoothPlastic, refl=0.08 },
	Honey     = { id="Honey",     displayName="Honey",     tier="Common",   color=Color3.fromRGB(232,168, 48), material=Enum.Material.Glass, refl=0.15 },

	-- ===== mid looks =====
	Ice       = { id="Ice",       displayName="Ice",       tier="Uncommon", color=Color3.fromRGB(168,222,246), material=Enum.Material.Glass, refl=0.30, fx=Color3.fromRGB(200,240,255) },
	Emerald   = { id="Emerald",   displayName="Emerald",   tier="Uncommon", color=Color3.fromRGB( 20,150, 80), material=Enum.Material.Glass, refl=0.25, fx=Color3.fromRGB( 70,255,150) },
	Coral     = { id="Coral",     displayName="Coral",     tier="Uncommon", color=Color3.fromRGB(248,116,104), material=Enum.Material.SmoothPlastic, refl=0.05 },
	Gilded    = { id="Gilded",    displayName="Gilded",    tier="Uncommon", color=Color3.fromRGB(232,186, 62), material=Enum.Material.Metal, refl=0.40, fx=Color3.fromRGB(255,225, 90) }, -- the gold-COLOURED look; "Gold" is a rarity tier, not a skin
	Crystal   = { id="Crystal",   displayName="Crystal",   tier="Uncommon", color=Color3.fromRGB(190,150,240), material=Enum.Material.Glass, refl=0.35, fx=Color3.fromRGB(215,180,255) },

	-- ===== flashy looks =====
	Neon      = { id="Neon",      displayName="Neon",      tier="Rare",     color=Color3.fromRGB( 60,255,170), material=Enum.Material.Neon, fx=Color3.fromRGB(120,255,200), light=true },
	Toxic     = { id="Toxic",     displayName="Toxic",     tier="Rare",     color=Color3.fromRGB(150,235, 40), material=Enum.Material.Neon, fx=Color3.fromRGB(190,255, 90), light=true },
	Magma     = { id="Magma",     displayName="Magma",     tier="Rare",     color=Color3.fromRGB(255, 88, 24), material=Enum.Material.Neon, fx=Color3.fromRGB(255,150, 60), light=true },

	-- ===== top looks =====
	Galaxy    = { id="Galaxy",    displayName="Galaxy",    tier="Epic",     color=Color3.fromRGB( 40, 30, 92), material=Enum.Material.Neon, refl=0.10, fx=Color3.fromRGB(170,130,255), light=true },
	Rainbow   = { id="Rainbow",   displayName="Rainbow",   tier="Epic",     color=Color3.fromRGB(255, 80, 80), material=Enum.Material.SmoothPlastic, animated="rainbow", fx=Color3.fromRGB(255,255,255) },
	Cyber     = { id="Cyber",     displayName="Cyber",     tier="Epic",     color=Color3.fromRGB( 24,232,232), material=Enum.Material.Neon, refl=0.20, fx=Color3.fromRGB(120,255,255), light=true },
	Shadow    = { id="Shadow",    displayName="Shadow",    tier="Legendary",color=Color3.fromRGB( 18, 16, 26), material=Enum.Material.SmoothPlastic, refl=0.05, fx=Color3.fromRGB( 90, 60,150), light=true },
	Celestial = { id="Celestial", displayName="Celestial", tier="Legendary",color=Color3.fromRGB(252,246,208), material=Enum.Material.Neon, fx=Color3.fromRGB(255,250,190), light=true },
	Cosmic    = { id="Cosmic",    displayName="Cosmic",    tier="Gold",     color=Color3.fromRGB( 30, 24, 66), material=Enum.Material.Neon, refl=0.15, fx=Color3.fromRGB(180,140,255), light=true, animated="cosmic" },
}

-- Display order for inventory grids: by default tier, then alphabetical inside a tier.
PetSkins.Order = (function()
	local list = {}
	for id in pairs(PetSkins.Skins) do list[#list+1] = id end
	table.sort(list, function(a, b)
		local ra = PetSkins.TierRank[PetSkins.Skins[a].tier] or 0
		local rb = PetSkins.TierRank[PetSkins.Skins[b].tier] or 0
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	return list
end)()

-- ============================================================================================================
-- THE INVENTORY KEY
-- ============================================================================================================
-- One inventory entry = one (pet, skin, trait) combination. Two of the same pet+skin with DIFFERENT traits are
-- SEPARATE entries that stack independently -- which is exactly what the spec calls for:
--     "PizzaDragon|Galaxy|"         x4      (Galaxy Pizza Dragon, no trait)
--     "PizzaDragon|Galaxy|Crowned"  x1      (same skin, Crowned -- a different entry)
--
-- Format: petId .. "|" .. skinId .. "|" .. traitId    (traitId is "" when the pet rolled no trait)
--
-- Why a flat string and not a nested table: it matches how the pet system already stores things
-- (_G.playerOwnedPets is keyed by a flat storage key like "ButterDuck#R"), it survives a DataStore round-trip
-- as a plain table key, and it can be passed through the EXISTING trade remotes as a single string with no
-- protocol change -- see TRADE_PREFIX below.
PetSkins.SEP = "|"

-- Trade offers travel over PetTradeOfferEvent, which already carries pet storage keys. A skin offer is the same
-- string with this prefix, so the pet system can tell the two apart with one string check and route skin keys to
-- the skin service's hooks. No new remote, no change to the trade handshake.
PetSkins.TRADE_PREFIX = "SKIN:"

function PetSkins.makeKey(petId, skinId, traitId)
	return tostring(petId) .. PetSkins.SEP .. tostring(skinId) .. PetSkins.SEP .. tostring(traitId or "")
end

-- "PizzaDragon|Galaxy|Crowned" -> "PizzaDragon", "Galaxy", "Crowned"
-- "PizzaDragon|Galaxy|"        -> "PizzaDragon", "Galaxy", nil
-- Returns nil on a malformed key (so callers can reject client input in one line).
function PetSkins.parseKey(key)
	if type(key) ~= "string" then return nil end
	local pet, skin, trait = key:match("^([^|]+)|([^|]+)|([^|]*)$")
	if not pet then return nil end
	if trait == "" then trait = nil end
	return pet, skin, trait
end

function PetSkins.isTradeKey(key)
	return type(key) == "string" and key:sub(1, #PetSkins.TRADE_PREFIX) == PetSkins.TRADE_PREFIX
end
function PetSkins.toTradeKey(key) return PetSkins.TRADE_PREFIX .. key end
function PetSkins.fromTradeKey(key)
	if not PetSkins.isTradeKey(key) then return nil end
	return key:sub(#PetSkins.TRADE_PREFIX + 1)
end

-- ---- HELPERS -----------------------------------------------------------------------------------------------
function PetSkins.get(id)
	return (type(id) == "string" and PetSkins.Skins[id]) or nil
end
function PetSkins.exists(id) return PetSkins.get(id) ~= nil end
function PetSkins.tierOf(id)
	local s = PetSkins.get(id)
	return (s and s.tier) or "Common"
end
function PetSkins.tierColor(tier)
	return PetSkins.TierColor[tier] or PetSkins.TierColor.Common
end

-- "Galaxy Pizza Dragon" -- the display name for a skinned pet. petDisplayName is the pet's own name, passed in
-- so this module never needs to know the pet catalogue (which lives server-side in PetSystem).
-- Pet IDS are CamelCase ("BurritoArmadillo") because they are keys. Nothing user-facing should ever print
-- one raw, so this splits them on the capitals: "Burrito Armadillo". OVERRIDES cover the handful whose real
-- catalogue name is not just their id with spaces -- PetSystem's PETS table is the authority on those, but it
-- is server-only, so the few that differ are mirrored here.
PetSkins.PRETTY_OVERRIDES = {
	BroccoliPet = "Broccoli Bunny",
}
function PetSkins.prettyPet(petId)
	if type(petId) ~= "string" or petId == "" then return "Pet" end
	local over = PetSkins.PRETTY_OVERRIDES[petId]
	if over then return over end
	-- insert a space before each capital that follows a lower-case letter or a digit
	local out = petId:gsub("(%l)(%u)", "%1 %2"):gsub("(%d)(%u)", "%1 %2")
	return out
end

function PetSkins.displayName(skinId, petDisplayName)
	local s = PetSkins.get(skinId)
	local sk = (s and s.displayName) or skinId or "?"
	return sk .. " " .. tostring(petDisplayName or "Pet")
end

return PetSkins
