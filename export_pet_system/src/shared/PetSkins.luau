--!nonstrict
-- PetSkins (ReplicatedStorage/Shared/PetSkins)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for pet SKIN THEMES + the inventory KEY FORMAT.
--
-- A skin is a THEME shared by EVERY pet: "Cosmic" works on Pizza Dragon, Butter Duck, Bean Buddy, anything.
-- That is deliberate -- it means adding a pet instantly gives it the whole existing skin collection, and adding
-- a skin instantly gives it to every pet, with no per-pet art.
--
-- THE SKIN IS THE PET'S MAIN VISUAL IDENTITY AND ITS DISPLAY NAME: "Cosmic Duck", "Golden Crab". The TRAIT
-- (PetTraits) is the second, independent layer -- what the pet is WEARING -- and it never joins the name.
--
-- HOW A SKIN RENDERS (all optional except id/displayName/tier):
--   color      : Color3 recoloured onto every BODY part (parts tagged role="body"; eyes are skipped).
--   material   : Enum.Material for those same parts.
--   refl       : 0..1 Reflectance (metal/glass sheen).
--   trans      : 0..1 Transparency on the body (Crystal's glassiness). Snapshotted + restored like colour.
--   fx         : Color3 -> a matching sparkle/aura tint (the same field RARE_LOOK uses in PetFollow).
--   light      : true -> a soft PointLight in the pet's colour.
--   animated   : the owning client animates each frame -- "rainbow" (fast body cycle), "cosmic" (body stays
--                deep-space; the STARS + light swirl the vivid cycle -- the old Cosmic Duck treatment),
--                "pastel" (dreamy slow soft-tone drift), "ocean" (rolling blue-teal swell), "lava" (molten
--                orange pulse).
--   trail      : true -> a fixed rainbow ribbon Trail behind the pet (Rainbow's signature).
--   particle   : a full emitter spec { texture,color,size,rate,speed,lifetime,spread,transparency,accel } --
--                the SAME schema PetTraits uses, drawn by the same builder in PetSkinLook. This is what gives
--                Lava its embers, Ocean its bubbles, Toxic its drips, Arctic its snowfall.
--   deco       : "crystals" | "bolts" | "candy" | "leaves" | "boils" | "runes" -> small extra geometry built
--                by PetSkinLook (Crystal's shards, Robot's panel+antenna, Candy's gumdrops, Jungle's leaves,
--                Toxic's boils, Ancient's glowing rune marks). Kept small so the pet stays recognisable.
--   tier       : the skin's RARITY BAND (Common..Legendary -- skins never use Gold; that band belongs to pet
--                rarity and the crate jackpot machinery).
--
-- HIDDEN VALUES: every skin tier carries a hidden number (TIER_VALUE below). Skin value + trait value = the
-- pet's SCORE, and PetTier.luau turns that score into the ONE Overall Tier shown above the pet. Tune the
-- values here and in PetTraits, and the thresholds in PetTier -- nothing else needs editing.
--
-- This mirrors src/shared/GutSkins.luau (the gut cosmetic config) on purpose: same shape, same helper style,
-- so the two cosmetic systems read identically.
-- ============================================================================================================

local PetSkins = {}

-- ---- RARITY TIERS -------------------------------------------------------------------------------------------
-- Six bands, lowest to highest. "Gold" is the crate jackpot band and the top PET rarity -- it is NOT a skin
-- tier (no skin is Gold; the gold-COLOURED skin is "Golden", an Epic). It stays in this list because PetRarity
-- and the crate machinery borrow the ladder wholesale.
PetSkins.TIER_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Gold" }
PetSkins.TierColor = {
	Common    = Color3.fromRGB(176, 182, 194), -- grey
	Uncommon  = Color3.fromRGB( 92, 200, 122), -- green
	Rare      = Color3.fromRGB( 70, 140, 255), -- blue
	Epic      = Color3.fromRGB(180,  90, 235), -- purple
	Legendary = Color3.fromRGB(255, 140,  40), -- orange
	Gold      = Color3.fromRGB(255, 206,  92), -- gold (the knife tier -- pets/crates only)
}
-- Rank number for sorting/comparison (higher = rarer).
PetSkins.TierRank = {}
for i, t in ipairs(PetSkins.TIER_ORDER) do PetSkins.TierRank[t] = i end

-- ---- HIDDEN TIER VALUES -------------------------------------------------------------------------------------
-- The hidden number a skin of each tier contributes to the pet's SCORE. Deliberately not linear: the jump to
-- Legendary is what makes a Legendary component dominate the Overall Tier. PetTier.luau owns the thresholds
-- that turn a score back into a tier. Tune freely -- nothing but PetTier reads this.
PetSkins.TIER_VALUE = {
	Common    = 1,
	Uncommon  = 2,
	Rare      = 4,
	Epic      = 7,
	Legendary = 11,
	Gold      = 11, -- defensive: no skin is Gold, but a lookup must never come back nil
}

-- ---- THE SKIN THEMES ---------------------------------------------------------------------------------------
-- THE APPROVED LIST -- exactly these 17, no more (no Galaxy: Cosmic is the space skin). Add a theme here and
-- EVERY pet can wear it immediately. Nothing else needs editing except the crate that should drop it
-- (SkinCrates.CRATES).
--
-- Every skin is designed to a DISTINCT identity, not a palette swap: Lava is cracked magma, Toxic is glowing
-- sludge, Crystal is translucent glass with shard geometry, Robot is riveted metal with an antenna, and so on.
PetSkins.Skins = {
	-- ===== COMMON =====
	-- Classic is the pet AS IT NORMALLY IS: no recolour, no material change -- the render fields are absent
	-- on purpose, so applySkin leaves the body's own colours alone. It exists as a named, ownable, tradable
	-- "default look" (and the baseline /testpet shows every trait on), not as a paint job.
	Classic = { id="Classic", displayName="Classic", tier="Common" },
	-- Pastel's identity is the DRIFT: the body slowly floats through soft pastel tones instead of sitting on
	-- one flat pink, with a light dreamy shimmer.
	Pastel  = { id="Pastel",  displayName="Pastel",  tier="Common",
		color=Color3.fromRGB(255,182,220), material=Enum.Material.SmoothPlastic, refl=0.05, animated="pastel",
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,235,248),
			size=0.4, rate=5, speed=0.3, lifetime=1.6, spread=40, transparency=0.45 } },
	-- cartoon mud, not realistic mud: flat plastic brown with heavy drips falling off the body
	Muddy   = { id="Muddy",   displayName="Muddy",   tier="Common",
		color=Color3.fromRGB(112, 80, 54), material=Enum.Material.SmoothPlastic,
		particle={ texture="rbxasset://textures/particles/smoke_main.dds", color=Color3.fromRGB(86,62,42),
			size=0.34, rate=8, speed=0.4, lifetime=0.9, spread=8, transparency=0.25, accel=Vector3.new(0,-16,0) } },
	-- icy body + a steady little SNOWFALL around the pet
	Arctic  = { id="Arctic",  displayName="Arctic",  tier="Common",
		color=Color3.fromRGB(214,238,250), material=Enum.Material.Ice, refl=0.15,
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,255,255),
			size=0.4, rate=12, speed=0.6, lifetime=1.6, spread=55, transparency=0.3, accel=Vector3.new(0,-4,0) } },

	-- ===== UNCOMMON =====
	-- SCREAMS candy: glossy bubblegum body STUDDED with bright gumdrops (deco), under a sprinkle drizzle
	Candy   = { id="Candy",   displayName="Candy",   tier="Uncommon",
		color=Color3.fromRGB(255,105,180), material=Enum.Material.SmoothPlastic, refl=0.15, deco="candy",
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,240,250),
			size=0.3, rate=9, speed=0.5, lifetime=1.2, spread=35, transparency=0.3 } },
	-- ALIVE, not just green: the body breathes between deep jungle shade and sunlit leaf (animated
	-- "jungle" -- light moving through a canopy), wrapped in warm-yellow FIREFLIES and a soft glow
	Jungle  = { id="Jungle",  displayName="Jungle",  tier="Uncommon",
		color=Color3.fromRGB( 58,152, 50), material=Enum.Material.SmoothPlastic, animated="jungle",
		fx=Color3.fromRGB(255,240,140), light=true,
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,238,120),
			size=0.26, rate=10, speed=0.2, lifetime=2.6, spread=60, transparency=0.25 } },
	-- warm cartoon sand (no realistic stone texture) with dust blowing off the body
	Desert  = { id="Desert",  displayName="Desert",  tier="Uncommon",
		color=Color3.fromRGB(228,196,124), material=Enum.Material.SmoothPlastic,
		particle={ texture="rbxasset://textures/particles/smoke_main.dds", color=Color3.fromRGB(214,184,120),
			size=0.5, rate=7, speed=0.8, lifetime=1.1, spread=30, transparency=0.5, accel=Vector3.new(0,-6,0) } },
	-- WATER, not "shiny blue": the body visibly ROLLS between deep blue and aqua like a swell, glassy and lit,
	-- with bubbles streaming up
	Ocean   = { id="Ocean",   displayName="Ocean",   tier="Uncommon",
		color=Color3.fromRGB( 28,120,200), material=Enum.Material.Glass, refl=0.25, trans=0.08,
		animated="ocean", fx=Color3.fromRGB(120,220,255), light=true,
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(190,235,255),
			size=0.3, rate=9, speed=1.1, lifetime=1.4, spread=15, transparency=0.3, accel=Vector3.new(0,5,0) } },

	-- ===== RARE =====
	-- cartoon magma: the whole body is molten neon that PULSES between deep red and bright orange, throwing embers
	Lava    = { id="Lava",    displayName="Lava",    tier="Rare",
		color=Color3.fromRGB(255, 96, 24), material=Enum.Material.Neon, animated="lava",
		fx=Color3.fromRGB(255,150,60), light=true,
		particle={ texture="rbxasset://textures/particles/fire_main.dds", color=Color3.fromRGB(255,130,40),
			size=0.6, rate=12, speed=1.4, lifetime=0.8, spread=15, transparency=0.3, accel=Vector3.new(0,5,0) } },
	-- radioactive sludge: sickly green body with glowing NEON BOILS bubbling on it (deco), dripping goo, green glow
	Toxic   = { id="Toxic",   displayName="Toxic",   tier="Rare",
		color=Color3.fromRGB(124,186, 48), material=Enum.Material.SmoothPlastic, deco="boils",
		fx=Color3.fromRGB(170,255,80), light=true,
		particle={ texture="rbxasset://textures/particles/smoke_main.dds", color=Color3.fromRGB(120,255,60),
			size=0.4, rate=10, speed=0.4, lifetime=0.9, spread=10, transparency=0.25, accel=Vector3.new(0,-14,0) } },
	Crystal = { id="Crystal", displayName="Crystal", tier="Rare",
		color=Color3.fromRGB(190,150,240), material=Enum.Material.Glass, refl=0.4, trans=0.25,
		fx=Color3.fromRGB(215,180,255), deco="crystals" },
	-- riveted steel with an antenna, a chest control panel and blinky button lights (deco)
	Robot   = { id="Robot",   displayName="Robot",   tier="Rare",
		color=Color3.fromRGB(150,158,170), material=Enum.Material.Metal, refl=0.35,
		fx=Color3.fromRGB(90,220,255), light=true, deco="bolts" },

	-- ===== EPIC =====
	-- metallic gold under a slow rain of falling gold glitter
	Golden  = { id="Golden",  displayName="Golden",  tier="Epic",
		color=Color3.fromRGB(240,196, 60), material=Enum.Material.Metal, refl=0.55,
		fx=Color3.fromRGB(255,225,110), light=true,
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,220,110),
			size=0.5, rate=8, speed=0.5, lifetime=1.1, spread=25, transparency=0.25, accel=Vector3.new(0,-10,0) } },
	-- a PHANTOM, not just "dark": the body is faintly see-through, wrapped in thick violet wisps and a purple glow
	Shadow  = { id="Shadow",  displayName="Shadow",  tier="Epic",
		color=Color3.fromRGB( 18, 16, 26), material=Enum.Material.SmoothPlastic, trans=0.2,
		fx=Color3.fromRGB(120, 80,200), light=true,
		particle={ texture="rbxasset://textures/particles/smoke_main.dds", color=Color3.fromRGB(52,38,86),
			size=1.0, rate=12, speed=0.7, lifetime=1.5, spread=30, transparency=0.4, accel=Vector3.new(0,2,0) } },
	-- warm sandstone (cartoon, no rough texture) carved with GLOWING GOLD RUNES (deco), motes drifting up
	Ancient = { id="Ancient", displayName="Ancient", tier="Epic",
		color=Color3.fromRGB(196,176,138), material=Enum.Material.SmoothPlastic, deco="runes",
		fx=Color3.fromRGB(255,214,120),
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(255,210,110),
			size=0.5, rate=6, speed=0.3, lifetime=2.2, spread=40, transparency=0.35, accel=Vector3.new(0,1,0) } },

	-- ===== LEGENDARY =====
	-- THE COSMIC DUCK'S OWN LOOK, now a skin for every pet: deep-space body that NEVER cycles, with dense
	-- swirling stars and an aura light that ride the vivid rainbow cycle. (Body values copied from
	-- PetFollow's RARE_LOOK ButterDuck row -- the "showstopper" recipe.)
	-- plus the GALAXY dressing: nebula patches + star studs on the body (deco "cosmos"), and a little
	-- SOLAR SYSTEM -- three planets and three stars ORBITING the pet. Orbiters leave gaps as they
	-- circle, so the pet's own face and features stay visible (the old solid rings blocked them).
	Cosmic  = { id="Cosmic",  displayName="Cosmic",  tier="Legendary",
		color=Color3.fromRGB( 26, 20, 60), material=Enum.Material.SmoothPlastic, refl=0.1,
		fx=Color3.fromRGB(180,140,255), light=true, animated="cosmic", deco="cosmos",
		orbit={ radius=2.4, speed=1.6, items={
			{ size=0.46, color=Color3.fromRGB(255,150, 70) },              -- planets
			{ size=0.18, color=Color3.fromRGB(255,255,255), neon=true },   -- stars between them
			{ size=0.40, color=Color3.fromRGB( 90,200,255) },
			{ size=0.16, color=Color3.fromRGB(255,255,255), neon=true },
			{ size=0.34, color=Color3.fromRGB(190,110,255) },
			{ size=0.17, color=Color3.fromRGB(255,255,255), neon=true },
		} },
		particle={ texture="rbxasset://textures/particles/sparkles_main.dds", color=Color3.fromRGB(200,160,255),
			size=0.45, rate=55, speed=2.2, lifetime=1.2, spread=55, transparency=0.2 } },
	-- fast bright body cycle + the signature rainbow RIBBON trailing behind the pet
	Rainbow = { id="Rainbow", displayName="Rainbow", tier="Legendary",
		color=Color3.fromRGB(255, 80, 80), material=Enum.Material.SmoothPlastic, animated="rainbow",
		trail=true, fx=Color3.fromRGB(255,255,255) },
}

-- ---- LEGACY SKIN IDS ----------------------------------------------------------------------------------------
-- The first-generation skin list (Stone, Sand, Galaxy, ...) was replaced by the approved 16 above. Saves and
-- trades can still carry the old ids, so every entry point runs them through normalise() -- an old id maps to
-- the closest new identity and merges into the player's inventory; nothing is ever wiped.
PetSkins.LEGACY = {
	Stone = "Classic", Sand = "Desert",  Moss = "Jungle",  Mud = "Muddy", Chocolate = "Muddy", Honey = "Candy",
	Ice = "Arctic",    Emerald = "Jungle", Coral = "Ocean", Gilded = "Golden",
	Neon = "Toxic",    Magma = "Lava",
	Galaxy = "Cosmic", Cyber = "Robot",  Celestial = "Cosmic",
	-- Toxic / Crystal / Rainbow / Shadow / Cosmic kept their names and need no entry.
}

-- Coerce any skin id -- current, legacy, or garbage -- into a real one, or nil if it maps to nothing.
function PetSkins.normalise(id)
	if type(id) ~= "string" then return nil end
	if PetSkins.Skins[id] then return id end
	local mapped = PetSkins.LEGACY[id]
	if mapped and PetSkins.Skins[mapped] then return mapped end
	return nil
end

-- Display order for inventory grids: by tier, then alphabetical inside a tier.
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
-- SEPARATE entries that stack independently:
--     "PizzaDragon|Cosmic|"       x4      (Cosmic Pizza Dragon, no trait -- legacy entries only)
--     "PizzaDragon|Cosmic|King"   x1      (same skin, King -- a different entry)
--
-- Format: petId .. "|" .. skinId .. "|" .. traitId    (traitId is "" for a legacy pet that rolled no trait --
-- every NEW crate pull rolls a trait, so "" only ever arrives from old saves and non-crate grants)
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

-- "PizzaDragon|Cosmic|King" -> "PizzaDragon", "Cosmic", "King"
-- "PizzaDragon|Cosmic|"     -> "PizzaDragon", "Cosmic", nil
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
-- get() resolves legacy ids too, so a renderer handed an old save's "Galaxy" paints Cosmic rather than nothing.
function PetSkins.get(id)
	local real = PetSkins.normalise(id)
	return (real and PetSkins.Skins[real]) or nil
end
function PetSkins.exists(id) return PetSkins.get(id) ~= nil end
function PetSkins.tierOf(id)
	local s = PetSkins.get(id)
	return (s and s.tier) or "Common"
end
function PetSkins.tierColor(tier)
	return PetSkins.TierColor[tier] or PetSkins.TierColor.Common
end
-- The hidden score value of a skin (by its tier). 0 for no skin at all.
function PetSkins.valueOf(id)
	local s = PetSkins.get(id)
	if not s then return 0 end
	return PetSkins.TIER_VALUE[s.tier] or 0
end

-- "Cosmic Duck" -- the display name for a skinned pet. THE TRAIT NEVER JOINS THE NAME ("Cosmic King Duck" is
-- wrong by spec); it is shown separately as "Trait: King". petDisplayName is the pet's own name, passed in
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

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
do
	for id, s in pairs(PetSkins.Skins) do
		assert(s.id == id, "[PetSkins] skin '" .. tostring(id) .. "' id field disagrees with its key")
		assert(PetSkins.TierRank[s.tier], "[PetSkins] skin '" .. id .. "' has unknown tier '" .. tostring(s.tier) .. "'")
		assert(s.tier ~= "Gold", "[PetSkins] no skin may be Gold tier -- that band belongs to pet rarity")
	end
	for old, new in pairs(PetSkins.LEGACY) do
		assert(PetSkins.Skins[new],
			"[PetSkins] LEGACY maps '" .. old .. "' to unknown skin '" .. tostring(new) .. "'")
	end
end

return PetSkins
