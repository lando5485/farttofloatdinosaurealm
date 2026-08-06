--!nonstrict
-- CosmeticConfig (ReplicatedStorage/Shared/CosmeticConfig)
-- Master cosmetic list for the Space Realm. Single source of truth for ids, names, rarities,
-- colors and the WINNABLE crate pool. Required by CrateService (roll/grant), PlayerState
-- (default-owned starters + ownership), CrateClient + HudSidebarStats (reveal cards / labels).
--
-- POOL RULES (must hold — asserted at the bottom):
--   * 47 total cosmetics across 5 types.
--   * WINNABLE = 46 (everything EXCEPT shape == "none", i.e. pet_none, which is the empty pet slot).
--   * Per-rarity winnable counts: Common 12, Rare 12, Epic 12, Legendary 10.
--   * Exactly one default-owned starter per type (auto-owned + equipped on first load).

local CosmeticConfig = {}

-- ===== RARITY COLORS (reveal headers, strokes, badges) =====
CosmeticConfig.RARITY_COLORS = {
	Common    = Color3.fromRGB(150, 160, 172),
	Rare      = Color3.fromRGB(70, 140, 255),
	Epic      = Color3.fromRGB(175, 90, 240),
	Legendary = Color3.fromRGB(255, 200, 60),
}

-- ===== TYPE LABELS (the "type • rarity" reveal line) =====
CosmeticConfig.TYPE_LABELS = {
	JetpackFlames = "Jetpack Flames",
	FartTrails    = "Fart Trail",
	Pets          = "Pet",
	LaunchEffects = "Launch Effect",
	Auras         = "Aura",
}

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- ===== MASTER LIST =====
-- Fields: id, name, type, rarity, color. Optional: default (starter), owned (auto-grant),
-- shape ("none" => excluded from winnable; pet display shape otherwise), material, size, neon,
-- gradient (extra colors for multi-color legendary/rainbow icons — the COUNT matches the spec).
CosmeticConfig.ALL = {
	-- ----- JetpackFlames -----
	{ id = "flames_orange",       name = "Orange",        type = "JetpackFlames", rarity = "Common",    color = c(255,140,40), default = true, owned = true },
	{ id = "flames_red",          name = "Red",           type = "JetpackFlames", rarity = "Common",    color = c(255,60,40) },
	{ id = "flames_yellow",       name = "Yellow",        type = "JetpackFlames", rarity = "Common",    color = c(255,220,60) },
	{ id = "flames_blue",         name = "Blue",          type = "JetpackFlames", rarity = "Rare",      color = c(80,150,255) },
	{ id = "flames_green",        name = "Green",         type = "JetpackFlames", rarity = "Rare",      color = c(80,230,120) },
	{ id = "flames_purple",       name = "Purple",        type = "JetpackFlames", rarity = "Rare",      color = c(175,90,240) },
	{ id = "flames_ice",          name = "Ice-white",     type = "JetpackFlames", rarity = "Epic",      color = c(200,235,255) },
	{ id = "flames_pink_plasma",  name = "Pink Plasma",   type = "JetpackFlames", rarity = "Epic",      color = c(255,120,210) },
	{ id = "flames_toxic",        name = "Toxic Neon",    type = "JetpackFlames", rarity = "Epic",      color = c(160,255,60) },
	{ id = "flames_rainbow",      name = "Rainbow",       type = "JetpackFlames", rarity = "Legendary", color = c(255,90,90),
		gradient = { c(255,90,90), c(255,170,60), c(255,235,80), c(90,230,120), c(80,150,255), c(175,90,240) } }, -- 6-color
	{ id = "flames_blackhole",    name = "Black-hole",    type = "JetpackFlames", rarity = "Legendary", color = c(120,40,200),
		gradient = { c(120,40,200), c(40,10,60), c(190,80,230) } }, -- 3-color

	-- ----- FartTrails -----
	{ id = "trail_gray_puff",     name = "Gray Puff",     type = "FartTrails", rarity = "Common",    color = c(170,170,175), default = true, owned = true },
	{ id = "trail_brown_cloud",   name = "Brown Cloud",   type = "FartTrails", rarity = "Common",    color = c(140,100,70) },
	{ id = "trail_white_wisp",    name = "White Wisp",    type = "FartTrails", rarity = "Common",    color = c(235,235,240) },
	{ id = "trail_stardust",      name = "Stardust",      type = "FartTrails", rarity = "Rare",      color = c(255,240,180) },
	{ id = "trail_bubble",        name = "Bubble",        type = "FartTrails", rarity = "Rare",      color = c(160,220,255) },
	{ id = "trail_smoke_streak",  name = "Smoke Streak",  type = "FartTrails", rarity = "Rare",      color = c(110,110,120) },
	{ id = "trail_comet",         name = "Comet",         type = "FartTrails", rarity = "Epic",      color = c(130,200,255) },
	{ id = "trail_nebula",        name = "Nebula",        type = "FartTrails", rarity = "Epic",      color = c(200,100,220) },
	{ id = "trail_plasma",        name = "Plasma",        type = "FartTrails", rarity = "Epic",      color = c(255,120,200) },
	{ id = "trail_galaxy",        name = "Galaxy",        type = "FartTrails", rarity = "Legendary", color = c(150,110,255),
		gradient = { c(150,110,255), c(90,60,200), c(200,160,255) } }, -- 3-color
	{ id = "trail_supernova",     name = "Supernova",     type = "FartTrails", rarity = "Legendary", color = c(255,180,80),
		gradient = { c(255,180,80), c(255,120,40), c(255,230,150) } }, -- 3-color

	-- ----- Pets ----- (pet_none is the empty slot: shape "none" => NOT winnable)
	{ id = "pet_none",            name = "None",          type = "Pets", rarity = "Common",    color = c(120,120,120), shape = "none", default = true, owned = true },
	{ id = "pet_tiny_asteroid",   name = "Tiny Asteroid", type = "Pets", rarity = "Common",    color = c(120,110,100), shape = "Ball",  material = "Slate",         size = 1.1 },
	{ id = "pet_moon_rock",       name = "Moon Rock",     type = "Pets", rarity = "Common",    color = c(165,165,170), shape = "Ball",  material = "Concrete",      size = 1.2 },
	{ id = "pet_satellite",       name = "Satellite",     type = "Pets", rarity = "Rare",      color = c(200,205,215), shape = "Block", material = "Metal",         size = 1.1 },
	{ id = "pet_mini_moon",       name = "Mini Moon",     type = "Pets", rarity = "Rare",      color = c(215,215,205), shape = "Ball",  material = "Sand",          size = 1.5 },
	{ id = "pet_ufo",             name = "UFO",           type = "Pets", rarity = "Epic",      color = c(120,235,150), shape = "Ball",  material = "Neon",          size = 1.6, neon = true },
	{ id = "pet_baby_alien",      name = "Baby Alien",    type = "Pets", rarity = "Epic",      color = c(150,255,150), shape = "Ball",  material = "SmoothPlastic", size = 1.2 },
	{ id = "pet_blackhole_orb",   name = "Black Hole Orb", type = "Pets", rarity = "Legendary", color = c(60,20,90),   shape = "Ball",  material = "Neon",          size = 1.5, neon = true },
	{ id = "pet_mini_sun",        name = "Mini Sun",      type = "Pets", rarity = "Legendary", color = c(255,200,60),  shape = "Ball",  material = "Neon",          size = 1.7, neon = true },

	-- ----- LaunchEffects -----
	{ id = "launch_dust_puff",       name = "Dust Puff",        type = "LaunchEffects", rarity = "Common",    color = c(185,175,155), default = true, owned = true },
	{ id = "launch_small_smoke",     name = "Small Smoke",      type = "LaunchEffects", rarity = "Common",    color = c(150,150,155) },
	{ id = "launch_fire_blast",      name = "Fire Blast",       type = "LaunchEffects", rarity = "Rare",      color = c(255,120,40) },
	{ id = "launch_spark_ring",      name = "Spark Ring",       type = "LaunchEffects", rarity = "Rare",      color = c(255,220,120) },
	{ id = "launch_shockwave",       name = "Shockwave Ring",   type = "LaunchEffects", rarity = "Epic",      color = c(150,210,255) },
	{ id = "launch_plasma_burst",    name = "Plasma Burst",     type = "LaunchEffects", rarity = "Epic",      color = c(220,120,255) },
	{ id = "launch_rocket_inferno",  name = "Rocket Inferno",   type = "LaunchEffects", rarity = "Legendary", color = c(255,90,30),
		gradient = { c(255,90,30), c(255,160,40), c(200,40,20) } }, -- 3-color
	{ id = "launch_cosmic_explosion", name = "Cosmic Explosion", type = "LaunchEffects", rarity = "Legendary", color = c(170,120,255),
		gradient = { c(170,120,255), c(120,80,220), c(220,180,255) } }, -- 3-color

	-- ----- Auras -----
	{ id = "aura_faint_white",    name = "Faint White",       type = "Auras", rarity = "Common",    color = c(235,235,240), default = true, owned = true },
	{ id = "aura_soft_blue",      name = "Soft Blue",         type = "Auras", rarity = "Common",    color = c(140,180,255) },
	{ id = "aura_green_glow",     name = "Green Glow",        type = "Auras", rarity = "Rare",      color = c(90,230,120) },
	{ id = "aura_purple_glow",    name = "Purple Glow",       type = "Auras", rarity = "Rare",      color = c(175,90,240) },
	{ id = "aura_fiery",          name = "Fiery Aura",        type = "Auras", rarity = "Epic",      color = c(255,120,40) },
	{ id = "aura_electric",       name = "Electric Crackle",  type = "Auras", rarity = "Epic",      color = c(120,200,255) },
	{ id = "aura_galaxy",         name = "Galaxy Aura",       type = "Auras", rarity = "Legendary", color = c(150,110,255),
		gradient = { c(150,110,255), c(90,60,200), c(210,170,255) } }, -- 3-color
	{ id = "aura_rainbow",        name = "Rainbow Prismatic", type = "Auras", rarity = "Legendary", color = c(255,120,120),
		gradient = { c(255,120,120), c(255,220,120), c(120,230,140), c(120,180,255), c(190,120,255) } }, -- 5-color
}

-- ===== DERIVED LOOKUPS =====

-- id -> cosmetic
CosmeticConfig.BY_ID = {}
for _, item in ipairs(CosmeticConfig.ALL) do
	CosmeticConfig.BY_ID[item.id] = item
end

-- Default-owned starters (one Common per type): flames_orange, trail_gray_puff, pet_none,
-- launch_dust_puff, aura_faint_white. Auto-owned + equipped on first load.
CosmeticConfig.DEFAULT_OWNED = {}
for _, item in ipairs(CosmeticConfig.ALL) do
	if item.default then
		table.insert(CosmeticConfig.DEFAULT_OWNED, item.id)
	end
end

-- WINNABLE pool = every cosmetic EXCEPT shape == "none" (pet_none). 46 items.
CosmeticConfig.WINNABLE = {}
-- Per-rarity winnable buckets (used by getByRarity for the uniform pick).
CosmeticConfig.WINNABLE_BY_RARITY = { Common = {}, Rare = {}, Epic = {}, Legendary = {} }
for _, item in ipairs(CosmeticConfig.ALL) do
	if item.shape ~= "none" then
		table.insert(CosmeticConfig.WINNABLE, item)
		local bucket = CosmeticConfig.WINNABLE_BY_RARITY[item.rarity]
		if bucket then
			table.insert(bucket, item)
		end
	end
end

-- getByRarity(rarity) -> array of winnable cosmetics of that rarity (the uniform-pick pool).
function CosmeticConfig.getByRarity(rarity)
	return CosmeticConfig.WINNABLE_BY_RARITY[rarity] or {}
end

-- ===== SELF-CHECK (guards the spec'd counts; logs loudly if a future edit breaks them) =====
do
	local counts = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for _, item in ipairs(CosmeticConfig.WINNABLE) do
		counts[item.rarity] = (counts[item.rarity] or 0) + 1
	end
	local expected = { Common = 12, Rare = 12, Epic = 12, Legendary = 10 }
	local ok = (#CosmeticConfig.WINNABLE == 46)
	for r, n in pairs(expected) do
		if counts[r] ~= n then ok = false end
	end
	if not ok then
		warn(string.format(
			"[CosmeticConfig] WINNABLE pool mismatch! total=%d (want 46) C=%d R=%d E=%d L=%d (want 12/12/12/10)",
			#CosmeticConfig.WINNABLE, counts.Common, counts.Rare, counts.Epic, counts.Legendary))
	end
end

return CosmeticConfig
