--!nonstrict
-- PetTraits (ReplicatedStorage/Shared/PetTraits)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for pet TRAITS -- the second, INDEPENDENT roll that happens after a skin is chosen.
--
-- A trait is a pure EFFECT layer: particles, light, an orbiting or floating element. It is NOT a body change --
-- no wings, no horns, no extra limbs, no silhouette edits. That rule exists so every trait works on every pet
-- (a wing looks wrong on a crab and impossible on a bean) and so a new pet needs zero trait art.
--
-- BOTH sides require this module: the server calls roll() and the client draws the effect from the SAME table,
-- so the odds shown to players can never drift from the odds rolled -- the same honest-odds contract
-- src/shared/SkinCrates.luau follows for the crates.
--
-- HOW A TRAIT RENDERS (PetSkinLook reads these; all optional):
--   particle   : { texture, color, size, rate, speed, lifetime, spread, transparency, accel }
--                -> one ParticleEmitter on the pet's root. The workhorse -- covers sparkle/smoke/fire/frost.
--   sparkles   : Color3   -> a Sparkles instance (Roblox's built-in glitter) in this colour.
--   light      : { color, brightness, range } -> a PointLight on the root.
--   orbit      : { count, color, size, radius, speed, neon } -> N small parts circling the pet.
--   halo       : { color, size, neon } -> ONE part floating above the pet (rings, crowns).
--   crown      : true -> the halo part is built as a little 5-point crown instead of a flat ring.
--   flicker    : true -> the light's brightness stutters (electric).
-- ============================================================================================================

local PetTraits = {}

-- ---- THE TRAITS ---------------------------------------------------------------------------------------------
-- `chance` is the REAL percent chance. These MUST sum to 100 (asserted at the bottom of this file).
-- Order here is the order shown in the odds panel: None first, then rarest-last.
PetTraits.TRAITS = {
	{
		id = "", displayName = "None", chance = 85.00,
		color = Color3.fromRGB(170, 176, 188),
		-- no render fields: a pet with no trait renders exactly as its skin
	},
	{
		id = "Sparkly", displayName = "Sparkly", chance = 6.00,
		color = Color3.fromRGB(255, 236, 140),
		sparkles = Color3.fromRGB(255, 240, 160),
	},
	{
		id = "Smoky", displayName = "Smoky", chance = 3.50,
		color = Color3.fromRGB(130, 130, 140),
		particle = { texture = "rbxasset://textures/particles/smoke_main.dds", color = Color3.fromRGB(70, 70, 78),
			size = 1.5, rate = 9, speed = 1.4, lifetime = 1.4, spread = 18, transparency = 0.55, accel = Vector3.new(0, 2, 0) },
	},
	{
		id = "Flaming", displayName = "Flaming", chance = 2.00,
		color = Color3.fromRGB(255, 130, 40),
		particle = { texture = "rbxasset://textures/particles/fire_main.dds", color = Color3.fromRGB(255, 140, 40),
			size = 1.1, rate = 22, speed = 2.2, lifetime = 0.7, spread = 12, transparency = 0.25, accel = Vector3.new(0, 6, 0) },
		light = { color = Color3.fromRGB(255, 140, 50), brightness = 1.6, range = 9 },
	},
	{
		id = "Frozen", displayName = "Frozen", chance = 1.50,
		color = Color3.fromRGB(150, 220, 255),
		particle = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(180, 230, 255),
			size = 0.8, rate = 16, speed = 0.8, lifetime = 1.6, spread = 30, transparency = 0.35, accel = Vector3.new(0, -1.5, 0) },
		light = { color = Color3.fromRGB(150, 215, 255), brightness = 1.2, range = 8 },
	},
	{
		id = "Charged", displayName = "Charged", chance = 1.00,
		color = Color3.fromRGB(90, 200, 255),
		orbit = { count = 3, color = Color3.fromRGB(120, 220, 255), size = 0.28, radius = 1.9, speed = 5.5, neon = true },
		light = { color = Color3.fromRGB(110, 205, 255), brightness = 2.0, range = 10 },
		flicker = true,
	},
	{
		id = "Glowing", displayName = "Glowing", chance = 0.70,
		color = Color3.fromRGB(255, 250, 180),
		halo = { color = Color3.fromRGB(255, 250, 190), size = 2.0, neon = true },
		light = { color = Color3.fromRGB(255, 248, 190), brightness = 2.4, range = 13 },
	},
	{
		id = "CosmicAura", displayName = "Cosmic Aura", chance = 0.20,
		color = Color3.fromRGB(180, 120, 255),
		orbit = { count = 5, color = Color3.fromRGB(200, 150, 255), size = 0.24, radius = 2.2, speed = 2.2, neon = true },
		particle = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(200, 150, 255),
			size = 0.7, rate = 14, speed = 0.6, lifetime = 2.0, spread = 40, transparency = 0.3 },
		light = { color = Color3.fromRGB(185, 130, 255), brightness = 2.2, range = 12 },
	},
	{
		id = "Crowned", displayName = "Crowned", chance = 0.10,
		color = Color3.fromRGB(255, 210, 80),
		halo = { color = Color3.fromRGB(255, 206, 92), size = 1.5, neon = false },
		crown = true, -- the floating element is built as a little crown (a hovering accessory, not a body change)
		sparkles = Color3.fromRGB(255, 225, 120),
		light = { color = Color3.fromRGB(255, 214, 110), brightness = 1.4, range = 9 },
	},
}

-- One-line disclosure for the odds panel, matching the wheel's wording.
PetTraits.ODDS_NOTE = "These are the real trait chances."

-- ---- LOOKUP -------------------------------------------------------------------------------------------------
PetTraits.ById = {}
for _, t in ipairs(PetTraits.TRAITS) do PetTraits.ById[t.id] = t end

-- traitId may be nil or "" -- both mean "no trait", and both return the None entry.
function PetTraits.get(traitId)
	return PetTraits.ById[traitId or ""] or PetTraits.ById[""]
end
function PetTraits.exists(traitId)
	return PetTraits.ById[traitId or ""] ~= nil
end
function PetTraits.isNone(traitId)
	return traitId == nil or traitId == ""
end
function PetTraits.displayName(traitId)
	local t = PetTraits.get(traitId)
	return t and t.displayName or "None"
end
function PetTraits.color(traitId)
	local t = PetTraits.get(traitId)
	return (t and t.color) or Color3.fromRGB(170, 176, 188)
end

function PetTraits.totalChance()
	local sum = 0
	for _, t in ipairs(PetTraits.TRAITS) do sum = sum + t.chance end
	return sum
end

-- ---- THE ROLL -----------------------------------------------------------------------------------------------
-- SERVER-ONLY in practice. `rng` is a Roblox Random so the server owns the randomness. Returns the trait's id
-- ("" for none) plus the entry, so the caller can log/display it without a second lookup.
--
-- Independent of the skin roll by design: an ordinary Stone Bean Buddy has exactly the same 0.1% shot at Crowned
-- as a Cosmic Pizza Dragon does. That's what makes a low-tier drop with a top trait interesting to keep.
function PetTraits.roll(rng)
	local total = PetTraits.totalChance()
	local pick = rng:NextNumber(0, total)
	local acc = 0
	for _, t in ipairs(PetTraits.TRAITS) do
		acc = acc + t.chance
		if pick < acc then return t.id, t end
	end
	-- float safety: pick == total exactly -> award the last (rarest) entry
	local last = PetTraits.TRAITS[#PetTraits.TRAITS]
	return last.id, last
end

-- Sanity assert at require-time: chances MUST sum to 100. If someone edits one and breaks the sum this errors
-- loudly on load rather than silently shipping odds that don't match what the UI prints.
do
	local total = PetTraits.totalChance()
	assert(math.abs(total - 100) < 1e-6,
		string.format("[PetTraits] trait chances must sum to 100, got %s", tostring(total)))
end

return PetTraits
