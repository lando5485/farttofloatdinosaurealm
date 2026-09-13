--!nonstrict
-- PetTraits (ReplicatedStorage/Shared/PetTraits)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for pet TRAITS -- the second, INDEPENDENT roll that happens after a skin is chosen.
--
-- A trait is WHAT THE PET IS WEARING/DOING: a character theme built from accessories -- hats, glasses,
-- clothing pieces, back gear, small effects. King, Mafia, Wizard, Astronaut. It is NOT part of the pet's
-- display name ("Cosmic Duck" + "Trait: King", never "Cosmic King Duck") and it must never hide the pet or
-- its skin -- the player has to be able to read all three at a glance.
--
-- EVERY TRAIT WORKS ON EVERY PET. Accessories are authored ONCE against named ATTACH POINTS (Head / Face /
-- Neck / Back / Body) that PetSkinLook derives from each pet's MAIN BODY MASS, then scales to the pet's
-- size. Thin protrusions (Bean Buddy's head vine, antennae, ears, tails...) are filtered out of that maths,
-- so a hat rests ON the head/shell/body itself and glasses sit on the face, never on a sprout or a beak. A
-- pet that still needs a nudge gets an entry in PET_OFFSETS below -- position/rotation/scale per attach
-- point -- rather than a second copy of the trait. That is the whole reusability contract.
--
-- BOTH sides require this module: the server calls roll() and the client builds the accessories from the SAME
-- table, so the odds shown to players can never drift from the odds rolled -- the same honest-odds contract
-- src/shared/SkinCrates.luau follows for the crates.
--
-- THE ROLL is rarity-first, independent of the skin roll: TIER_ODDS picks a band, then a uniform pick inside
-- it. Every crate pull now grants a trait -- there is no "None" outcome any more. "" (no trait) still exists
-- as a VALUE for legacy pets from old saves and for non-crate grants; get()/isNone() handle it.
--
-- HIDDEN VALUES: TIER_VALUE below is the trait's contribution to the pet's SCORE (skin value + trait value);
-- PetTier.luau turns the score into the ONE Overall Tier shown above the pet.
--
-- HOW A TRAIT RENDERS (PetSkinLook reads these; all optional except id/displayName/tier):
--   attach     : default attach point for `parts` ("Head" / "Face" / "Neck" / "Back" / "Body").
--   parts      : list of primitive part specs, each relative to the attach frame (+Y up, -Z forward):
--                  { shape="Block"|"Ball"|"Cylinder", size={x,y,z}, pos={x,y,z}, rot={x,y,z} (degrees),
--                    color=Color3, material=Enum.Material?, refl?, trans?, attach=<override point>?,
--                    sway={amp=degrees, speed=n}? }
--                `sway` marks CLOTH: PetSkinLook flutters the part about a hinge at its top edge, so capes,
--                tails and the bandana blow in the wind instead of hanging rigid.
--                Units (see the TRAITS header): Head/Face/Neck are drawn for a unit head and scale to the
--                pet's crown; Body/Back positions are FRACTIONS of the body's half-extents.
--   particle   : { texture, color, size, rate, speed, lifetime, spread, transparency, accel }
--                -> one ParticleEmitter on the pet's root (small flavour effects only).
--   sparkles   : Color3   -> a Sparkles instance in this colour.
--   light      : { color, brightness, range } -> a PointLight on the root.
--   orbit      : { count, color, size, radius, speed, neon } -> N small parts circling the pet.
-- ============================================================================================================

local PetTraits = {}

-- ---- RARITY ODDS + HIDDEN VALUES ----------------------------------------------------------------------------
-- The REAL percent chance of each trait rarity band. MUST sum to 100 (asserted at the bottom). Rolled
-- independently of the skin, so Legendary Skin + Common Trait and Common Skin + Legendary Trait are both live
-- outcomes -- that mix is what the Overall Tier is computed from.
PetTraits.TIER_ODDS = {
	Common    = 50.00,
	Uncommon  = 27.00,
	Rare      = 14.00,
	Epic      =  7.00,
	Legendary =  2.00,
}
PetTraits.TIER_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- The hidden number a trait of each tier adds to the pet's SCORE. Same scale as PetSkins.TIER_VALUE on
-- purpose -- skin and trait pull the Overall Tier with equal weight. Tune freely; only PetTier reads it.
PetTraits.TIER_VALUE = {
	Common    = 1,
	Uncommon  = 2,
	Rare      = 4,
	Epic      = 7,
	Legendary = 11,
}

PetTraits.ODDS_NOTE = "These are the real trait chances."

-- ---- SHARED COLOURS (accessory palette) ---------------------------------------------------------------------
local BLACK   = Color3.fromRGB( 28,  28,  34)
local WHITE   = Color3.fromRGB(245, 245, 245)
local GOLD    = Color3.fromRGB(255, 206,  92)
local LEATHER = Color3.fromRGB(140,  96,  58)
local DARKLEA = Color3.fromRGB( 92,  60,  36)
local RED     = Color3.fromRGB(215,  56,  50)
local KHAKI   = Color3.fromRGB(212, 196, 150)

-- ---- THE TRAITS ---------------------------------------------------------------------------------------------
-- THE APPROVED LIST -- exactly these 21, no more (no Samurai). `color` is the UI accent for the trait's name.
--
-- AUTHORING UNITS (PetSkinLook normalises these per pet):
--   * Head / Face / Neck specs are drawn for a UNIT HEAD (half-width ~0.95) -- sizes AND positions scale
--     uniformly to the pet's actual crown, so a hat brim always wraps the head it rests on.
--   * Body / Back POSITIONS are FRACTIONS of the body's own half-extents: x = 1 is the flank surface,
--     z = -1 the chest, z = 1 the rear, y = 1 the top. That is what puts pauldrons on the shoulders and
--     straps on the sides of a crab, a duck and a dragon alike. Sizes stay uniform (body units).
PetTraits.TRAITS = {
	-- ===== COMMON =====
	{
		id = "Sunglasses", displayName = "Sunglasses", tier = "Common",
		color = Color3.fromRGB(70, 76, 92), attach = "Face",
		-- CLASSIC WAYFARERS, built as ONE rigid frame (every part `uniform`, one scale, so the pieces can
		-- never drift apart): chunky black plastic all the way around -- bold brow bar, thick bottom and
		-- side rims, a solid bridge post -- with see-through smoke lenses, little silver hinge dots at the
		-- corners, and stout arms back over the ears. Centred on the eye line on every pet.
		parts = {
			{ shape="Block", size={1.50,0.17,0.11}, pos={0, 0.24,0}, uniform=true, color=BLACK },         -- brow bar
			{ shape="Block", size={0.58,0.40,0.06}, pos={-0.37,-0.03,-0.02}, uniform=true,
				color=Color3.fromRGB(55,55,66), material=Enum.Material.Glass, trans=0.5, refl=0.1 },       -- smoke lenses (see-through)
			{ shape="Block", size={0.58,0.40,0.06}, pos={ 0.37,-0.03,-0.02}, uniform=true,
				color=Color3.fromRGB(55,55,66), material=Enum.Material.Glass, trans=0.5, refl=0.1 },
			{ shape="Block", size={0.68,0.09,0.10}, pos={-0.37,-0.26,0}, uniform=true, color=BLACK },     -- bottom rims
			{ shape="Block", size={0.68,0.09,0.10}, pos={ 0.37,-0.26,0}, uniform=true, color=BLACK },
			{ shape="Block", size={0.09,0.47,0.10}, pos={-0.71,-0.04,0}, uniform=true, color=BLACK },     -- outer rims
			{ shape="Block", size={0.09,0.47,0.10}, pos={ 0.71,-0.04,0}, uniform=true, color=BLACK },
			{ shape="Block", size={0.15,0.42,0.10}, pos={0,-0.03,0},     uniform=true, color=BLACK },     -- bridge post
			{ shape="Ball",  size={0.08,0.08,0.08}, pos={-0.73,0.22,0.04}, uniform=true,
				color=Color3.fromRGB(200,204,214), material=Enum.Material.Metal, refl=0.3 },               -- silver hinge dots
			{ shape="Ball",  size={0.08,0.08,0.08}, pos={ 0.73,0.22,0.04}, uniform=true,
				color=Color3.fromRGB(200,204,214), material=Enum.Material.Metal, refl=0.3 },
			{ shape="Block", size={0.09,0.09,0.75}, pos={-0.71,0.20,0.36}, uniform=true, color=BLACK },   -- slim ear arms
			{ shape="Block", size={0.09,0.09,0.75}, pos={ 0.71,0.20,0.36}, uniform=true, color=BLACK },
		},
	},
	{
		id = "Bowtie", displayName = "Bowtie", tier = "Common",
		color = RED, attach = "Neck",
		-- bigger and PROUD of the chest surface, so it can't be swallowed by a round body
		parts = {
			{ shape="Block", size={0.62,0.42,0.16}, pos={-0.36,0,-0.06}, rot={0,0, 10}, color=RED },
			{ shape="Block", size={0.62,0.42,0.16}, pos={ 0.36,0,-0.06}, rot={0,0,-10}, color=RED },
			{ shape="Ball",  size={0.26,0.26,0.26}, pos={0,0,-0.10},                    color=Color3.fromRGB(160,36,32) },
		},
	},
	{
		id = "Bandana", displayName = "Bandana", tier = "Common",
		color = Color3.fromRGB(226, 88, 60), attach = "Neck",
		-- a folded NECKERCHIEF BIB on the chest -- two layered diamonds and a knot, no ring through the body
		parts = {
			{ shape="Block", size={0.78,0.78,0.12}, pos={0,-0.12,-0.06}, rot={12,0,45}, sway={amp=4, speed=2.6}, color=Color3.fromRGB(226,88,60) },
			{ shape="Block", size={0.58,0.58,0.12}, pos={0,-0.28,-0.10}, rot={12,0,45}, sway={amp=5, speed=2.6}, color=Color3.fromRGB(186,64,44) },
			{ shape="Ball",  size={0.16,0.16,0.16}, pos={-0.34,0.16,-0.04}, color=Color3.fromRGB(226,88,60) }, -- the knot
			{ shape="Ball",  size={0.16,0.16,0.16}, pos={ 0.34,0.16,-0.04}, color=Color3.fromRGB(226,88,60) },
		},
	},
	{
		id = "Backpack", displayName = "Backpack", tier = "Common",
		color = LEATHER, attach = "Back",
		-- a real pack: buckled flap + pocket, straps HUGGING the flanks and running over the top
		parts = {
			{ shape="Block", size={0.95,1.15,0.50}, pos={0,0.12,0.35},   color=LEATHER },
			{ shape="Block", size={0.98,0.34,0.52}, pos={0,0.55,0.35},   color=DARKLEA },                   -- flap
			{ shape="Block", size={0.50,0.42,0.16}, pos={0,-0.18,0.62},  color=DARKLEA },                   -- pocket
			{ shape="Block", size={0.10,0.16,0.06}, pos={-0.22,0.30,0.62}, color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- buckles
			{ shape="Block", size={0.10,0.16,0.06}, pos={ 0.22,0.30,0.62}, color=GOLD, material=Enum.Material.Metal, refl=0.3 },
			{ shape="Block", size={0.13,0.90,0.15}, pos={-0.98,0.10,-0.60}, rot={6,0,0},  color=DARKLEA }, -- flank straps
			{ shape="Block", size={0.13,0.90,0.15}, pos={ 0.98,0.10,-0.60}, rot={6,0,0},  color=DARKLEA },
			{ shape="Block", size={0.13,0.12,0.95}, pos={-0.50,0.75,-0.35}, rot={-8,0,0}, color=DARKLEA }, -- over the top
			{ shape="Block", size={0.13,0.12,0.95}, pos={ 0.50,0.75,-0.35}, rot={-8,0,0}, color=DARKLEA },
		},
	},
	{
		id = "Beanie", displayName = "Beanie", tier = "Common",
		color = Color3.fromRGB(56, 122, 196), attach = "Head",
		-- a snug knit cap: ONE half-sphere dome (ellipsoid mesh) sitting on the head over a fold band
		parts = {
			{ shape="Dome",     size={1.85,1.00,1.85}, pos={0,0.30,0},  color=Color3.fromRGB(56,122,196) }, -- the dome cap
			{ shape="Cylinder", size={0.32,1.92,1.92}, pos={0,0.05,0},  rot={0,0,90}, color=Color3.fromRGB(36,88,150) }, -- fold band
			{ shape="Ball",     size={0.40,0.40,0.40}, pos={0,0.82,0},  color=WHITE },                       -- pom-pom
		},
	},

	-- ===== UNCOMMON =====
	{
		id = "Cowboy", displayName = "Cowboy", tier = "Uncommon",
		color = LEATHER, attach = "Head",
		-- personality pass: creased crown, banded with a gold buckle, a sheriff badge, and a lasso coil on the hip
		parts = {
			{ shape="Cylinder", size={0.09,2.15,2.15}, pos={0,0.05,0}, rot={0,0,90}, color=LEATHER },       -- brim
			{ shape="Cylinder", size={0.60,1.20,1.20}, pos={0,0.38,0}, rot={0,0,90}, color=LEATHER },       -- crown
			{ shape="Block",    size={0.55,0.20,0.95}, pos={0,0.70,0},               color=Color3.fromRGB(122,82,48) }, -- the crease
			{ shape="Cylinder", size={0.16,1.26,1.26}, pos={0,0.16,0}, rot={0,0,90}, color=DARKLEA },       -- band
			{ shape="Block",    size={0.16,0.16,0.07}, pos={0,0.16,-0.63},           color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- buckle
			{ shape="Cylinder", size={0.05,0.26,0.26}, pos={0,0.42,-0.58}, rot={0,90,0}, color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- badge
			{ shape="Cylinder", size={0.10,0.55,0.55}, pos={1.02,0.05,0.15}, attach="Body", color=Color3.fromRGB(164,120,72) }, -- lasso coil
			{ shape="Block",    size={0.08,0.30,0.08}, pos={1.05,-0.28,0.15}, attach="Body", color=Color3.fromRGB(164,120,72) }, -- rope tail
		},
	},
	{
		id = "Chef", displayName = "Chef", tier = "Uncommon",
		color = WHITE, attach = "Head",
		-- an actual TOQUE: tall white column with the puffy cluster ON TOP of it
		parts = {
			{ shape="Cylinder", size={0.42,1.35,1.35}, pos={0,0.10,0}, rot={0,0,90}, color=WHITE },         -- base band
			{ shape="Cylinder", size={0.70,1.18,1.18}, pos={0,0.60,0}, rot={0,0,90}, color=WHITE },         -- column
			{ shape="Ball",     size={0.85,0.85,0.85}, pos={0,1.05,0},  color=WHITE },                       -- the puff
			{ shape="Ball",     size={0.55,0.55,0.55}, pos={-0.33,0.95,0.19}, color=WHITE },
			{ shape="Ball",     size={0.55,0.55,0.55}, pos={ 0.33,0.95,0.19}, color=WHITE },
			{ shape="Ball",     size={0.55,0.55,0.55}, pos={0,0.95,-0.38},    color=WHITE },
			-- the spatula tucked into the band, blade up -- says CHEF from across the island
			{ shape="Cylinder", size={0.55,0.09,0.09}, pos={0.72,0.55,0}, rot={0,0,55}, color=Color3.fromRGB(120,84,48) }, -- handle
			{ shape="Block",    size={0.30,0.38,0.05}, pos={0.98,0.95,0}, rot={0,0,-35},
				color=Color3.fromRGB(196,200,210), material=Enum.Material.Metal, refl=0.25 },                -- blade
		},
	},
	{
		id = "Party", displayName = "Party", tier = "Uncommon",
		color = Color3.fromRGB(255, 120, 200), attach = "Head",
		-- a SMOOTH striped cone (six close-stacked rings, not three cake layers) + brim + topper
		parts = {
			{ shape="Cylinder", size={0.07,1.20,1.20}, pos={0,0.02,0}, rot={0,0,90}, color=GOLD },          -- brim ring
			{ shape="Cylinder", size={0.24,1.05,1.05}, pos={0,0.14,0}, rot={0,0,90}, color=Color3.fromRGB(255,120,200) },
			{ shape="Cylinder", size={0.24,0.88,0.88}, pos={0,0.38,0}, rot={0,0,90}, color=Color3.fromRGB(90,205,255) },
			{ shape="Cylinder", size={0.24,0.72,0.72}, pos={0,0.62,0}, rot={0,0,90}, color=Color3.fromRGB(255,120,200) },
			{ shape="Cylinder", size={0.24,0.56,0.56}, pos={0,0.86,0}, rot={0,0,90}, color=Color3.fromRGB(90,205,255) },
			{ shape="Cylinder", size={0.24,0.40,0.40}, pos={0,1.10,0}, rot={0,0,90}, color=Color3.fromRGB(255,120,200) },
			{ shape="Cylinder", size={0.24,0.26,0.26}, pos={0,1.34,0}, rot={0,0,90}, color=Color3.fromRGB(90,205,255) },
			{ shape="Ball",     size={0.30,0.30,0.30}, pos={0,1.56,0}, color=Color3.fromRGB(255,222,80) },  -- topper
		},
		particle = { texture = "rbxasset://textures/particles/sparkles_main.dds",
			color = Color3.fromRGB(255, 200, 240), size = 0.4, rate = 6, speed = 0.8, lifetime = 1.2,
			spread = 40, transparency = 0.3 },
	},
	{
		id = "Explorer", displayName = "Explorer", tier = "Uncommon",
		color = KHAKI, attach = "Head",
		-- pith helmet with proper explorer kit: strapped GOGGLES resting on the front
		parts = {
			{ shape="Dome",     size={1.62,0.95,1.62}, pos={0,0.20,0},  color=KHAKI },                       -- half-sphere dome
			{ shape="Cylinder", size={0.10,1.95,1.95}, pos={0,0.00,0},  rot={0,0,90}, color=KHAKI },         -- brim
			{ shape="Cylinder", size={0.18,1.60,1.60}, pos={0,0.12,0},  rot={0,0,90}, color=DARKLEA },       -- band
			{ shape="Cylinder", size={0.13,1.66,1.66}, pos={0,0.36,0},  rot={0,0,90}, color=Color3.fromRGB(58,58,64) }, -- goggle strap
			{ shape="Cylinder", size={0.14,0.32,0.32}, pos={-0.28,0.36,-0.78}, rot={0,90,0}, color=Color3.fromRGB(196,150,72), material=Enum.Material.Metal, refl=0.2 },
			{ shape="Cylinder", size={0.16,0.22,0.22}, pos={-0.28,0.36,-0.82}, rot={0,90,0}, color=Color3.fromRGB(40,44,52) },
			{ shape="Cylinder", size={0.14,0.32,0.32}, pos={ 0.28,0.36,-0.78}, rot={0,90,0}, color=Color3.fromRGB(196,150,72), material=Enum.Material.Metal, refl=0.2 },
			{ shape="Cylinder", size={0.16,0.22,0.22}, pos={ 0.28,0.36,-0.82}, rot={0,90,0}, color=Color3.fromRGB(40,44,52) },
		},
	},
	{
		id = "TopHat", displayName = "Top Hat", tier = "Uncommon",
		color = BLACK, attach = "Head",
		parts = {
			{ shape="Cylinder", size={0.10,1.60,1.60}, pos={0,0.04,0}, rot={0,0,90}, color=BLACK },          -- brim
			{ shape="Cylinder", size={1.05,1.00,1.00}, pos={0,0.60,0}, rot={0,0,90}, color=BLACK },          -- crown
			{ shape="Cylinder", size={0.20,1.06,1.06}, pos={0,0.24,0}, rot={0,0,90}, color=RED },            -- band
			{ shape="Block",    size={0.18,0.18,0.06}, pos={0,0.24,-0.53}, color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- buckle
		},
	},

	-- ===== RARE =====
	{
		id = "Astronaut", displayName = "Astronaut", tier = "Rare",
		color = Color3.fromRGB(200, 228, 250), attach = "Head",
		-- HALF-SPHERE helmet dome seated on the head (ellipsoid mesh, one piece), tinted visor anchored on
		-- the eyes so the face shows through, ear pods on the rim
		parts = {
			{ shape="Dome",     size={2.05,1.30,2.05}, pos={0,0.12,0}, color=WHITE, refl=0.08 },            -- dome shell
			{ shape="Cylinder", size={0.22,2.10,2.10}, pos={0,0.02,0}, rot={0,0,90},
				color=Color3.fromRGB(200,206,216), material=Enum.Material.Metal, refl=0.15 },                -- rim ring
			{ shape="Block",    size={1.35,0.72,0.28}, pos={0,0.02,-0.12}, attach="Face",
				color=Color3.fromRGB(150,210,240), material=Enum.Material.Glass, trans=0.5, refl=0.2 },      -- visor, on the eyes
			{ shape="Cylinder", size={0.24,0.46,0.46}, pos={-1.02,0.10,0}, color=Color3.fromRGB(168,174,186), material=Enum.Material.Metal, refl=0.2 }, -- ear pods
			{ shape="Cylinder", size={0.24,0.46,0.46}, pos={ 1.02,0.10,0}, color=Color3.fromRGB(168,174,186), material=Enum.Material.Metal, refl=0.2 },
			{ shape="Block",    size={0.06,0.36,0.06}, pos={0.60,0.92,0}, color=WHITE },                     -- antenna
			{ shape="Ball",     size={0.13,0.13,0.13}, pos={0.60,1.14,0}, color=RED, material=Enum.Material.Neon },
		},
	},
	{
		id = "Pirate", displayName = "Pirate", tier = "Rare",
		color = Color3.fromRGB(40, 40, 48), attach = "Head",
		-- rounded tricorn (half-sphere dome + swept-up brims + gold trim) with the skull-and-bones up front,
		-- and a round eyepatch sitting square on the eye
		parts = {
			{ shape="Dome",     size={1.58,0.90,1.58}, pos={0,0.12,0}, color=BLACK },                        -- dome cap
			{ shape="Block",    size={1.55,0.13,0.60}, pos={0,0.30,-0.60}, rot={ 25,0,0}, color=BLACK },     -- front sweep
			{ shape="Block",    size={0.60,0.13,1.30}, pos={-0.62,0.30,0.20}, rot={0,0,-25}, color=BLACK },  -- side sweeps
			{ shape="Block",    size={0.60,0.13,1.30}, pos={ 0.62,0.30,0.20}, rot={0,0, 25}, color=BLACK },
			{ shape="Block",    size={1.55,0.05,0.10}, pos={0,0.42,-0.82}, rot={25,0,0}, color=GOLD },       -- gold trim
			{ shape="Ball",     size={0.22,0.22,0.22}, pos={0,0.30,-0.72}, color=WHITE },                    -- skull
			{ shape="Block",    size={0.30,0.05,0.05}, pos={0,0.18,-0.74}, rot={0,0, 40}, color=WHITE },     -- crossbones
			{ shape="Block",    size={0.30,0.05,0.05}, pos={0,0.18,-0.74}, rot={0,0,-40}, color=WHITE },
			{ shape="Cylinder", size={0.10,0.55,0.55}, pos={1.0,0,-0.03},  attach="Face", rot={0,90,0}, color=BLACK }, -- eyepatch: ON and COVERING the eye
			-- the strap hugs the head: a fitted front band plus two short segments angling back around the
			-- sides -- no more bar shooting off past the head (uniform = locked to the frame scale)
			{ shape="Block", size={1.50,0.09,0.06}, pos={0,0.15,0.02},     attach="Face", uniform=true, rot={0,0,8}, color=BLACK },
			{ shape="Block", size={0.08,0.09,0.55}, pos={-0.74,0.10,0.26}, attach="Face", uniform=true, color=BLACK },
			{ shape="Block", size={0.08,0.09,0.55}, pos={ 0.74,0.20,0.26}, attach="Face", uniform=true, color=BLACK },
		},
	},
	{
		id = "Viking", displayName = "Viking", tier = "Rare",
		color = Color3.fromRGB(186, 192, 204), attach = "Head",
		parts = {
			{ shape="Dome",     size={1.62,1.00,1.62}, pos={0,0.15,0}, color=Color3.fromRGB(150,156,168),
				material=Enum.Material.Metal, refl=0.25 },                                                    -- helm dome (half-sphere)
			{ shape="Cylinder", size={0.18,1.68,1.68}, pos={0,0.04,0}, rot={0,0,90},
				color=Color3.fromRGB(110,116,128), material=Enum.Material.Metal },                            -- rim
			-- ONE-PIECE horns: a single solid wedge each, rooted in a socket on the helm and tapering to a
			-- point -- connected from base to tip, no floating segments
			{ shape="Ball",  size={0.42,0.42,0.42}, pos={-0.72,0.30,0}, color=Color3.fromRGB(110,116,128),
				material=Enum.Material.Metal },                                                               -- horn sockets
			{ shape="Ball",  size={0.42,0.42,0.42}, pos={ 0.72,0.30,0}, color=Color3.fromRGB(110,116,128),
				material=Enum.Material.Metal },
			{ shape="Wedge", size={0.26,1.15,0.55}, pos={-0.95,0.72,0}, rot={0, 90, 32}, color=Color3.fromRGB(232,222,196) },
			{ shape="Wedge", size={0.26,1.15,0.55}, pos={ 0.95,0.72,0}, rot={0,-90,-32}, color=Color3.fromRGB(232,222,196) },
		},
	},
	{
		id = "Detective", displayName = "Detective", tier = "Rare",
		color = Color3.fromRGB(148, 112, 72), attach = "Head",
		-- smooth deerstalker (no fabric texture) + a MONOCLE that sits exactly on the eye, chain and all
		parts = {
			{ shape="Dome",  size={1.50,0.85,1.50}, pos={0,0.12,0}, color=Color3.fromRGB(148,112,72) },      -- cap dome
			{ shape="Block", size={0.80,0.10,0.50}, pos={0,0.00,-0.80}, rot={-12,0,0}, color=Color3.fromRGB(122,90,56) }, -- front brim
			{ shape="Block", size={0.80,0.10,0.50}, pos={0,0.00, 0.80}, rot={ 12,0,0}, color=Color3.fromRGB(122,90,56) }, -- back brim
			{ shape="Block", size={0.12,0.34,0.55}, pos={-0.68,0.12,0}, color=Color3.fromRGB(122,90,56) },   -- side flaps
			{ shape="Block", size={0.12,0.34,0.55}, pos={ 0.68,0.12,0}, color=Color3.fromRGB(122,90,56) },
			{ shape="Ball",  size={0.16,0.16,0.16}, pos={0,0.75,0},  color=Color3.fromRGB(122,90,56) },      -- top button
			{ shape="Cylinder", size={0.05,0.50,0.50}, pos={1.0,0,-0.03}, attach="Face", rot={0,90,0},
				color=GOLD, material=Enum.Material.Metal, refl=0.3 },                                         -- monocle rim, ON the eye
			{ shape="Cylinder", size={0.03,0.42,0.42}, pos={1.0,0,-0.06}, attach="Face", rot={0,90,0},
				color=Color3.fromRGB(210,235,250), material=Enum.Material.Glass, trans=0.45 },                -- lens
			{ shape="Ball", size={0.07,0.07,0.07}, pos={1.18,-0.18,0}, attach="Face", color=GOLD },          -- chain
			{ shape="Ball", size={0.07,0.07,0.07}, pos={1.30,-0.36,0}, attach="Face", color=GOLD },
			{ shape="Ball", size={0.07,0.07,0.07}, pos={1.38,-0.54,0}, attach="Face", color=GOLD },
		},
	},
	{
		id = "Ninja", displayName = "Ninja", tier = "Rare",
		color = Color3.fromRGB(36, 38, 46), attach = "Head",
		-- rebuilt: forehead-plate headband with knot + flowing tails, and a KATANA slung across the back
		parts = {
			{ shape="Cylinder", size={0.30,1.90,1.90}, pos={0,0.18,0}, rot={0,0,90}, color=BLACK },          -- headband
			{ shape="Block",    size={0.34,0.22,0.08}, pos={0,0.18,-0.93},
				color=Color3.fromRGB(178,184,196), material=Enum.Material.Metal, refl=0.3 },                  -- forehead plate
			{ shape="Block",    size={0.20,0.20,0.14}, pos={0,0.16,0.95}, color=BLACK },                     -- knot
			{ shape="Block",    size={0.15,0.55,0.20}, pos={-0.12,0.00,1.05}, rot={-40,0,0}, sway={amp=13, speed=3.0}, color=BLACK }, -- tails, fluttering
			{ shape="Block",    size={0.15,0.48,0.20}, pos={ 0.14,-0.06,1.02}, rot={-55,0,0}, sway={amp=15, speed=3.4}, color=BLACK },
			{ shape="Block",    size={0.16,1.70,0.16}, pos={0,0.10,0.30},  attach="Back", rot={0,0,40}, color=Color3.fromRGB(30,30,38) }, -- sheath
			{ shape="Block",    size={0.13,0.50,0.13}, pos={-0.66,0.88,0.30}, attach="Back", rot={0,0,40}, color=Color3.fromRGB(140,40,44) }, -- handle
			{ shape="Block",    size={0.30,0.07,0.22}, pos={-0.52,0.72,0.30}, attach="Back", rot={0,0,40}, color=GOLD, material=Enum.Material.Metal, refl=0.25 }, -- guard
		},
	},

	-- ===== EPIC =====
	{
		id = "Mafia", displayName = "Mafia", tier = "Epic",
		color = Color3.fromRGB(52, 52, 62), attach = "Head",
		-- fedora PLUS the suit that makes it read mafia: black lapels, white shirt and a red tie on the chest
		parts = {
			{ shape="Cylinder", size={0.08,1.95,1.95}, pos={0,0.05,0}, rot={0,0,90}, color=Color3.fromRGB(36,36,44) }, -- brim
			{ shape="Cylinder", size={0.55,1.20,1.20}, pos={0,0.34,0}, rot={0,0,90}, color=Color3.fromRGB(36,36,44) }, -- crown
			{ shape="Block",    size={0.50,0.16,0.95}, pos={0,0.60,0}, color=Color3.fromRGB(28,28,36) },     -- pinch
			{ shape="Cylinder", size={0.15,1.26,1.26}, pos={0,0.14,0}, rot={0,0,90}, color=WHITE },          -- silk band
			-- the suit hangs on the CHEST LINE (Neck attach: the front surface guaranteed below the face)
			{ shape="Block", size={0.40,0.66,0.10}, pos={-0.28,-0.10,-0.03}, attach="Neck", rot={0,0, 22}, color=Color3.fromRGB(24,24,30) }, -- lapels
			{ shape="Block", size={0.40,0.66,0.10}, pos={ 0.28,-0.10,-0.03}, attach="Neck", rot={0,0,-22}, color=Color3.fromRGB(24,24,30) },
			{ shape="Block", size={0.34,0.34,0.08}, pos={0,0.06,-0.06},  attach="Neck", rot={0,0,45}, color=WHITE }, -- shirt
			{ shape="Block", size={0.20,0.58,0.08}, pos={0,-0.32,-0.09}, attach="Neck", color=RED },         -- tie
			{ shape="Block", size={0.24,0.16,0.09}, pos={0,0.06,-0.10},  attach="Neck", rot={0,0,45}, color=RED }, -- knot
		},
	},
	{
		id = "Wizard", displayName = "Wizard", tier = "Epic",
		color = Color3.fromRGB(122, 72, 220), attach = "Head",
		-- the same smooth-cone treatment as Party: six close rings taper to a starred point
		parts = {
			{ shape="Cylinder", size={0.10,1.75,1.75}, pos={0,0.04,0}, rot={0,0,90}, color=Color3.fromRGB(88,50,170) },  -- brim
			{ shape="Cylinder", size={0.18,1.16,1.16}, pos={0,0.14,0}, rot={0,0,90}, color=GOLD },           -- gold band
			{ shape="Cylinder", size={0.26,1.08,1.08}, pos={0,0.34,0}, rot={0,0,90}, color=Color3.fromRGB(104,60,196) },
			{ shape="Cylinder", size={0.26,0.90,0.90}, pos={0,0.60,0}, rot={0,0,90}, color=Color3.fromRGB(96,54,184) },
			{ shape="Cylinder", size={0.26,0.72,0.72}, pos={0,0.86,0}, rot={0,0,90}, color=Color3.fromRGB(104,60,196) },
			{ shape="Cylinder", size={0.26,0.54,0.54}, pos={0,1.12,0}, rot={0,0,90}, color=Color3.fromRGB(96,54,184) },
			{ shape="Cylinder", size={0.26,0.36,0.36}, pos={0,1.38,0}, rot={0,0,90}, color=Color3.fromRGB(104,60,196) },
			{ shape="Ball",     size={0.22,0.22,0.22}, pos={0,1.60,0}, color=GOLD, material=Enum.Material.Neon }, -- tip star
			{ shape="Ball",     size={0.14,0.14,0.14}, pos={-0.32,0.50,-0.42}, color=GOLD, material=Enum.Material.Neon },
			{ shape="Ball",     size={0.14,0.14,0.14}, pos={ 0.30,0.95,-0.22}, color=GOLD, material=Enum.Material.Neon },
		},
		particle = { texture = "rbxasset://textures/particles/sparkles_main.dds",
			color = Color3.fromRGB(190, 140, 255), size = 0.4, rate = 8, speed = 0.5, lifetime = 1.4,
			spread = 35, transparency = 0.3 },
	},
	{
		id = "King", displayName = "King", tier = "Epic",
		color = GOLD, attach = "Head",
		-- royal set: fur-trimmed jewelled crown AND the red cape with white trim off the back
		parts = {
			{ shape="Cylinder", size={0.18,1.62,1.62}, pos={0,0.04,0}, rot={0,0,90}, color=WHITE },          -- fur base
			{ shape="Cylinder", size={0.42,1.50,1.50}, pos={0,0.28,0}, rot={0,0,90},
				color=GOLD, material=Enum.Material.Metal, refl=0.35 },                                        -- crown band
			-- (the points are generated below, evenly around the band)
			{ shape="Ball", size={0.15,0.15,0.15}, pos={0,0.30,-0.76},    color=RED,                        material=Enum.Material.Glass, refl=0.3 }, -- gems
			{ shape="Ball", size={0.15,0.15,0.15}, pos={-0.66,0.30,0.37}, color=Color3.fromRGB(60,120,255), material=Enum.Material.Glass, refl=0.3 },
			{ shape="Ball", size={0.15,0.15,0.15}, pos={ 0.66,0.30,0.37}, color=Color3.fromRGB(90,220,120), material=Enum.Material.Glass, refl=0.3 },
			-- the royal cape: white fur yoke + ONE red cloth panel, fluttering as one sheet
			{ shape="Block", size={1.20,0.26,0.12}, pos={0,0.44,0.12},   attach="Back", color=WHITE },       -- fur yoke
			{ shape="Block", size={1.30,1.90,0.08}, pos={0,-0.62,0.42},  attach="Back", rot={-10,0,0},
				sway={amp=6, speed=1.8}, color=Color3.fromRGB(184,34,42) },                                   -- THE cape
			{ shape="Ball",  size={0.16,0.16,0.16}, pos={-0.50,0.48,0.12}, attach="Back", color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- clasps
			{ shape="Ball",  size={0.16,0.16,0.16}, pos={ 0.50,0.48,0.12}, attach="Back", color=GOLD, material=Enum.Material.Metal, refl=0.3 },
		},
		light = { color = GOLD, brightness = 0.9, range = 7 },
	},
	{
		id = "Superhero", displayName = "Superhero", tier = "Epic",
		color = Color3.fromRGB(226, 54, 54), attach = "Back",
		-- ONE cape: a single cloth panel hanging from a clasped yoke, fluttering as ONE sheet (hinged at its
		-- top edge). Mask is two framed eye pieces (fits every eye spacing, never overshoots the head);
		-- the emblem hangs small on the chest line, well below any mouth.
		parts = {
			{ shape="Block", size={1.15,0.26,0.12}, pos={0,0.38,0.12},                 color=Color3.fromRGB(196,40,40) }, -- yoke
			{ shape="Ball",  size={0.15,0.15,0.15}, pos={-0.48,0.40,0.04}, color=GOLD, material=Enum.Material.Metal, refl=0.3 }, -- clasps
			{ shape="Ball",  size={0.15,0.15,0.15}, pos={ 0.48,0.40,0.04}, color=GOLD, material=Enum.Material.Metal, refl=0.3 },
			{ shape="Block", size={1.35,2.00,0.07}, pos={0,-0.72,0.45}, rot={-12,0,0}, sway={amp=8, speed=2.1},
				color=Color3.fromRGB(220,50,50) },                                                            -- THE cape
			-- the mask is SEE-THROUGH over the eyes (tinted, not solid) and slimmer, so it frames the eyes
			-- instead of blacking them out
			{ shape="Block", size={0.64,0.34,0.08}, pos={-0.44,0.02,0.01}, attach="Face", uniform=true,
				color=Color3.fromRGB(40,58,150), material=Enum.Material.Glass, trans=0.45 },               -- mask eye pieces
			{ shape="Block", size={0.64,0.34,0.08}, pos={ 0.44,0.02,0.01}, attach="Face", uniform=true,
				color=Color3.fromRGB(40,58,150), material=Enum.Material.Glass, trans=0.45 },
			{ shape="Block", size={0.26,0.24,0.08}, pos={0,0.06,0},       attach="Face", uniform=true, color=Color3.fromRGB(40,58,150) }, -- mask bridge
			-- the emblem is thicker and tucked INTO the chest plane, so on round-chested pets it meets the
			-- curved surface instead of hovering in front of it
			{ shape="Cylinder", size={0.18,0.44,0.44}, pos={0,-0.15,0.02},  attach="Neck", rot={0,90,0}, color=RED }, -- emblem disc
			{ shape="Ball",     size={0.26,0.26,0.26}, pos={0,-0.15,-0.02}, attach="Neck", color=GOLD, material=Enum.Material.Neon }, -- emblem core
		},
	},

	-- ===== LEGENDARY =====
	{
		id = "Celestial", displayName = "Celestial", tier = "Legendary",
		color = Color3.fromRGB(255, 244, 180), attach = "Head",
		-- significant now: a double halo, glowing LIGHT-WINGS off the back, five orbiting stars, aura + light
		parts = {
			{ shape="Cylinder", size={0.10,1.95,1.95}, pos={0,1.15,0}, rot={0,0,90},
				color=Color3.fromRGB(255,240,170), material=Enum.Material.Neon, trans=0.10 },                 -- outer halo
			{ shape="Cylinder", size={0.06,1.45,1.45}, pos={0,1.15,0}, rot={0,0,90},
				color=WHITE, material=Enum.Material.Neon, trans=0.30 },                                       -- inner glow ring
			{ shape="Block", size={0.70,1.15,0.08}, pos={-0.72,0.30,0.18}, attach="Back", rot={0, 28, 22},
				color=Color3.fromRGB(255,240,190), material=Enum.Material.Neon, trans=0.25 },                 -- light-wings (rooted against the back)
			{ shape="Block", size={0.70,1.15,0.08}, pos={ 0.72,0.30,0.18}, attach="Back", rot={0,-28,-22},
				color=Color3.fromRGB(255,240,190), material=Enum.Material.Neon, trans=0.25 },
		},
		orbit = { count = 5, color = Color3.fromRGB(255, 240, 180), size = 0.22, radius = 2.1, speed = 1.6, neon = true },
		particle = { texture = "rbxasset://textures/particles/sparkles_main.dds",
			color = Color3.fromRGB(255, 246, 200), size = 0.5, rate = 14, speed = 0.4, lifetime = 1.8,
			spread = 40, transparency = 0.25 },
		light = { color = Color3.fromRGB(255, 246, 200), brightness = 2.2, range = 13 },
	},
	{
		id = "Titan", displayName = "Titan", tier = "Legendary",
		color = Color3.fromRGB(255, 130, 40), attach = "Body",
		-- REDESIGNED: no big plates that can sit across a face. The Titan is shoulder pauldrons with molten
		-- trim (conforming to the flanks), glowing gauntlet bands low on the sides, a molten-core belt on
		-- the chest line, and three molten rocks ORBITING the pet -- presence through aura, not slabs.
		parts = {
			{ shape="Block", size={0.68,0.36,0.68}, pos={-1.04,0.60,0}, rot={0,0, 12},
				color=Color3.fromRGB(96,74,52), material=Enum.Material.Metal, refl=0.15 },                    -- pauldrons
			{ shape="Block", size={0.68,0.36,0.68}, pos={ 1.04,0.60,0}, rot={0,0,-12},
				color=Color3.fromRGB(96,74,52), material=Enum.Material.Metal, refl=0.15 },
			{ shape="Block", size={0.70,0.10,0.70}, pos={-1.04,0.80,0}, rot={0,0, 12},
				color=Color3.fromRGB(255,130,40), material=Enum.Material.Neon },                              -- molten trim
			{ shape="Block", size={0.70,0.10,0.70}, pos={ 1.04,0.80,0}, rot={0,0,-12},
				color=Color3.fromRGB(255,130,40), material=Enum.Material.Neon },
			{ shape="Block", size={0.16,0.34,0.60}, pos={-1.00,-0.30,0},
				color=Color3.fromRGB(255,130,40), material=Enum.Material.Neon, trans=0.15 },                  -- gauntlet bands, on the flanks
			{ shape="Block", size={0.16,0.34,0.60}, pos={ 1.00,-0.30,0},
				color=Color3.fromRGB(255,130,40), material=Enum.Material.Neon, trans=0.15 },
			{ shape="Block", size={0.85,0.20,0.20}, pos={0,-0.50,0.03}, attach="Neck",
				color=Color3.fromRGB(96,74,52), material=Enum.Material.Metal, refl=0.15 },                    -- belt, tucked into the chest plane
			{ shape="Block", size={0.24,0.24,0.14}, pos={0,-0.50,-0.03}, attach="Neck",
				color=Color3.fromRGB(255,130,40), material=Enum.Material.Neon },                              -- molten core
		},
		orbit = { count = 3, color = Color3.fromRGB(255, 120, 40), size = 0.30, radius = 2.2, speed = 2.4, neon = true }, -- molten rocks
		particle = { texture = "rbxasset://textures/particles/fire_main.dds",
			color = Color3.fromRGB(255, 140, 50), size = 0.5, rate = 10, speed = 1.2, lifetime = 0.7,
			spread = 20, transparency = 0.35, accel = Vector3.new(0, 4, 0) },
		light = { color = Color3.fromRGB(255, 140, 50), brightness = 1.6, range = 11 },
	},
}

-- KING'S POINTS, generated rather than hand-typed so they stay evenly spaced if the crown is resized.
do
	local king
	for _, t in ipairs(PetTraits.TRAITS) do if t.id == "King" then king = t break end end
	local R, Y = 0.62, 0.58
	for k = 0, 4 do
		local a = math.rad(k * 72)
		king.parts[#king.parts + 1] = {
			shape = "Block", size = {0.16, 0.44, 0.16},
			pos = { math.cos(a) * R, Y, math.sin(a) * R },
			color = GOLD, material = Enum.Material.Metal, refl = 0.35,
		}
	end
end

-- ---- THE "NONE" VALUE (legacy only) -------------------------------------------------------------------------
-- Not in TRAITS (it can never be rolled) but still a valid stored value: pets from old saves, collection-book
-- cosmetics and other non-crate grants may carry no trait. get()/displayName()/color() resolve it here.
local NONE = { id = "", displayName = "None", tier = "Common", color = Color3.fromRGB(170, 176, 188) }

-- ---- LEGACY TRAIT IDS ---------------------------------------------------------------------------------------
-- The first-generation traits were pure effects (Sparkly, Crowned, ...). Old saves map to the closest new
-- character theme; nothing is wiped.
PetTraits.LEGACY = {
	Sparkly = "Party", Smoky = "Ninja", Flaming = "Superhero", Frozen = "Viking",
	Charged = "Wizard", Glowing = "Celestial", CosmicAura = "Celestial", Crowned = "King",
}

-- ---- LOOKUP -------------------------------------------------------------------------------------------------
PetTraits.ById = {}
for _, t in ipairs(PetTraits.TRAITS) do PetTraits.ById[t.id] = t end
PetTraits.ById[""] = NONE

-- Traits grouped by tier, in authored order -- what the roll picks uniformly from.
PetTraits.ByTier = {}
for _, t in ipairs(PetTraits.TRAITS) do
	local list = PetTraits.ByTier[t.tier]
	if not list then list = {}; PetTraits.ByTier[t.tier] = list end
	list[#list + 1] = t
end

-- Coerce any trait id -- current, legacy, "", nil, or garbage -- into a valid stored value.
-- Returns "" for anything unrecognised (never invents a trait a player didn't have).
function PetTraits.normalise(id)
	if id == nil or id == "" then return "" end
	if type(id) ~= "string" then return "" end
	if PetTraits.ById[id] then return id end
	local mapped = PetTraits.LEGACY[id]
	if mapped and PetTraits.ById[mapped] then return mapped end
	return ""
end

-- traitId may be nil or "" -- both mean "no trait", and both return the None entry.
function PetTraits.get(traitId)
	return PetTraits.ById[PetTraits.normalise(traitId)] or NONE
end
function PetTraits.exists(traitId)
	local id = traitId or ""
	return PetTraits.ById[id] ~= nil or PetTraits.LEGACY[id] ~= nil
end
function PetTraits.isNone(traitId)
	return PetTraits.normalise(traitId) == ""
end
function PetTraits.displayName(traitId)
	return PetTraits.get(traitId).displayName
end
function PetTraits.color(traitId)
	return PetTraits.get(traitId).color
end
function PetTraits.tierOf(traitId)
	if PetTraits.isNone(traitId) then return nil end
	return PetTraits.get(traitId).tier
end
-- The hidden score value of a trait (by its tier). 0 for no trait.
function PetTraits.valueOf(traitId)
	local tier = PetTraits.tierOf(traitId)
	if not tier then return 0 end
	return PetTraits.TIER_VALUE[tier] or 0
end

function PetTraits.totalChance()
	local sum = 0
	for _, w in pairs(PetTraits.TIER_ODDS) do sum = sum + w end
	return sum
end

-- ---- PER-PET ATTACH OFFSETS ---------------------------------------------------------------------------------
-- PetSkinLook derives Head/Face/Neck/Back/Body from each pet's MAIN BODY MASS (protrusions like vines, ears
-- and antennae are filtered out first -- see its PROTRUSION_NAMES + footprint filter), which seats hats on
-- the actual head/shell/body on most pets. A pet whose anatomy still needs a nudge gets an entry here:
-- position (studs, pre-scale), rotation (degrees) and a scale multiplier PER ATTACH POINT. This is the
-- tuning surface -- use /testpet's TRY buttons to check every trait on every pet and adjust here, never by
-- forking a trait per pet.
-- EMPTY BY DESIGN after the per-pet normalisation pass: head gear now sizes itself to each pet's crown and
-- body gear positions itself in fractions of each pet's own extents, so the old hand-guessed nudges are
-- superseded. Walk every pet with /testpet's TRY buttons and add entries ONLY for what still reads wrong --
-- pos is in that attach's own units, rot in degrees, scale multiplies both size and reach.
PetTraits.PET_OFFSETS = {
	CoconutCrab = { -- its eyes ride on STALKS above the shell: hats sit a touch higher and smaller so the
		-- brim never caps the eye stalks (the /scanpet x-ray flagged OVER-EYE on most head gear)
		Head = { pos = {0, 0.30, 0}, scale = 0.85 },
	},
}

-- ---- THE ROLL -----------------------------------------------------------------------------------------------
-- SERVER-ONLY in practice. `rng` is a Roblox Random so the server owns the randomness.
--   1. Roll the trait RARITY from TIER_ODDS.
--   2. Uniform pick among that tier's traits.
-- ALWAYS returns a real trait -- every crate pull grants a skin AND a trait now. Returns the trait's id plus
-- the entry, so the caller can log/display it without a second lookup.
--
-- Independent of the skin roll by design: a Classic Bean Buddy has exactly the same 2% shot at a Legendary
-- trait as a Cosmic Pizza Dragon does. That's what makes a low-tier drop with a top trait worth keeping.
function PetTraits.roll(rng)
	local total = PetTraits.totalChance()
	local pick = rng:NextNumber(0, total)
	local acc, chosenTier = 0, PetTraits.TIER_ORDER[#PetTraits.TIER_ORDER]
	for _, tier in ipairs(PetTraits.TIER_ORDER) do
		acc = acc + (PetTraits.TIER_ODDS[tier] or 0)
		if pick < acc then chosenTier = tier break end
	end
	local pool = PetTraits.ByTier[chosenTier]
	local t = pool[rng:NextInteger(1, #pool)]
	return t.id, t
end

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
do
	local total = PetTraits.totalChance()
	assert(math.abs(total - 100) < 1e-6,
		string.format("[PetTraits] TIER_ODDS must sum to 100, got %s", tostring(total)))
	for _, tier in ipairs(PetTraits.TIER_ORDER) do
		assert(PetTraits.ByTier[tier] and #PetTraits.ByTier[tier] > 0,
			"[PetTraits] tier '" .. tier .. "' has weight but no traits -- a roll landing there would error")
	end
	local VALID_ATTACH = { Head = true, Face = true, Neck = true, Back = true, Body = true }
	for _, t in ipairs(PetTraits.TRAITS) do
		assert(PetTraits.TIER_VALUE[t.tier], "[PetTraits] trait '" .. t.id .. "' has unknown tier '" .. tostring(t.tier) .. "'")
		assert(t.attach == nil or VALID_ATTACH[t.attach],
			"[PetTraits] trait '" .. t.id .. "' has unknown attach point '" .. tostring(t.attach) .. "'")
		for _, p in ipairs(t.parts or {}) do
			assert(p.attach == nil or VALID_ATTACH[p.attach],
				"[PetTraits] trait '" .. t.id .. "' part has unknown attach point '" .. tostring(p.attach) .. "'")
		end
	end
	for old, new in pairs(PetTraits.LEGACY) do
		assert(PetTraits.ById[new],
			"[PetTraits] LEGACY maps '" .. old .. "' to unknown trait '" .. tostring(new) .. "'")
	end
end

return PetTraits
