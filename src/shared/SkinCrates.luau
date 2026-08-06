--!nonstrict
-- SkinCrates (ReplicatedStorage/Shared/SkinCrates)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for the CS:GO-style pet-skin crates: what's inside each crate, what it costs, the
-- rarity odds, and the Robux token packs.
--
-- BOTH sides require this module. The SERVER calls roll() to decide the reward; the CLIENT reads the same
-- CONTENTS to build the scrolling reel and the same RARITY_ODDS to print the odds panel. Because the numbers
-- the player is shown and the numbers the server rolls on come from ONE table, they can never disagree --
-- the honest-odds contract this file is the single source of truth for.
--
--   * Roblox POLICY: a paid random-chance item must publish TRUTHFUL odds. Do NOT add a secret re-roll, a pity
--     timer, or any visual rigging. The reel must land on the reward the server actually rolled.
--
-- HOW THE ROLL WORKS (exactly as specified):
--   1. Roll the RARITY from RARITY_ODDS (Common 79.92% ... Gold 0.08%).
--   2. Pick UNIFORMLY at random from that rarity's entries in the crate.
--   3. Roll the TRAIT separately -- see PetTraits.roll(). Independent of rarity.
--
-- A rarity band with NO entries in a crate is skipped and its weight redistributed to the bands that do have
-- entries (see roll()), so a half-filled crate is still openable while you're building it out.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("DinosaurRealm")
local PetSkins = require(Shared:WaitForChild("PetSkins"))

local SkinCrates = {}

-- ---- RARITY ODDS --------------------------------------------------------------------------------------------
-- The REAL drop chances, in percent. These MUST sum to 100 (asserted at the bottom of this file).
-- This is the BASELINE, used by the Starter crate and by any crate that doesn't set its own `odds`. The higher
-- tiers DO override it (that's what makes them worth more tokens) -- but an override is asserted to sum to 100
-- too, and the odds panel always prints the same table the roll reads, so no crate can be quietly stingier
-- than what it advertises.
SkinCrates.RARITY_ODDS = {
	Common    = 79.92,
	Uncommon  = 16.00,
	Rare      =  3.20,
	Epic      =  0.64,
	Legendary =  0.16,
	Gold      =  0.08,
}
-- Roll order, lowest to highest. Also the display order in the odds panel.
SkinCrates.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Gold" }

SkinCrates.ODDS_NOTE = "These are the real drop chances."

-- A crate MAY override RARITY_ODDS with its own `odds` table -- that's how the Premium/Elite/Mythic tiers below
-- get "better odds" than Starter. Everything downstream (roll, liveRarities, effectiveOdds, and the percentages
-- the UI prints) reads through this ONE accessor, so a crate's published odds and its rolled odds are guaranteed
-- to be the same table. A crate with no `odds` field uses the shared default.
function SkinCrates.oddsFor(crate)
	return (crate and crate.odds) or SkinCrates.RARITY_ODDS
end

-- The GOLD tier is the "knife pull" -- it gets its own sound, its own reel flash, and a server-wide announcement.
-- Everything below it reveals normally.
SkinCrates.GOLD_TIER = "Gold"

-- ---- THE CRATES ---------------------------------------------------------------------------------------------
-- Each entry is { pet = <petId>, skin = <skinId> }. petId must exist in PetSystem's PETS catalogue; skinId must
-- exist in PetSkins.Skins. Both are validated at require-time by the assert block at the bottom, so a typo fails
-- loudly on load instead of producing an unobtainable reward.
--
-- IMPORTANT: a player can receive a skin for a pet they have NOT unlocked. That is deliberate -- it stops anyone
-- deliberately staying locked to farm better odds. The skin sits in the inventory reading
-- "Unlock <Pet> to equip", and becomes wearable the moment they unlock that pet. See SkinCrateService.
SkinCrates.CRATES = {
	-- THE PET LEVEL CRATE. Replaces the Robux Pet Wheel, which is gone: this is where pet levels come from
	-- now. It runs on the EXACT same machinery as the skin crates -- roll a rarity band, pick uniformly
	-- inside it, animate the reel to the index the server actually rolled -- so the honest-odds contract and
	-- every anti-rigging guarantee carry over unchanged. The only difference is what an entry HOLDS:
	-- `levels = N` instead of `pet`/`skin`. kind = "levels" is what tells the roll, the validator, the
	-- server grant and the reel which shape to expect.
	--
	-- ODDS + AMOUNTS are carried over from the old wheel so the value of a level did not silently change:
	-- the wheel paid an average of 1.70 levels per spin, this pays 1.78 per open.
	--   0.52*1 + 0.30*2 + 0.13*3 + 0.04*5 + 0.009*7 + 0.001*10 = 1.783
	--
	-- PRICE is the one number to tune. At the token pack rate (0.4 R$/token) 150 tokens is about R$60, where
	-- a wheel spin was R$15. It is deliberately dearer than the wheel and deliberately CHEAPER than the
	-- Starter crate, so it reads as the entry-level utility crate rather than a cosmetic pull. For exact
	-- parity with the old wheel price, set this to 40.
	{
		id = "PetLevels", displayName = "Pet Level Crate",
		blurb = "Nothing but pet levels. Every single pull levels up a pet.",
		price = 150, color = Color3.fromRGB(120, 200, 120), icon = "\xE2\xAD\x90", -- star
		kind = "levels", -- entries are { levels = N }, NOT { pet, skin }
		odds = { Common = 52.00, Uncommon = 30.00, Rare = 13.00, Epic = 4.00, Legendary = 0.90, Gold = 0.10 },
		contents = {
			Common    = { { levels = 1  } },
			Uncommon  = { { levels = 2  } },
			Rare      = { { levels = 3  } },
			Epic      = { { levels = 5  } },
			Legendary = { { levels = 7  } },
			Gold      = { { levels = 10 } },
		},
	},
	{
		id = "Starter", displayName = "Starter Crate",
		blurb = "Cheap and cheerful. Mostly Common, but every tier is in here.",
		price = 250, color = Color3.fromRGB(64, 120, 245), icon = "\xF0\x9F\x93\xA6", -- box
		-- no `odds` field -> the shared baseline. This is the crate players learn the odds from.
		contents = {
			Common = {
				{ pet = "StegoPet", skin = "Stone" }, { pet = "TriceratopsPet", skin = "Sand" },
				{ pet = "RaptorPet", skin = "Moss" }, { pet = "SpinosaurusPet", skin = "Mud" },
				{ pet = "SharkPet", skin = "Chocolate" }, { pet = "TyrannosaurusPet", skin = "Honey" },
			},
			Uncommon = {
				{ pet = "StegoPet", skin = "Ice" }, { pet = "StegoPet", skin = "Emerald" },
				{ pet = "SpinosaurusPet", skin = "Coral" }, { pet = "RaptorPet", skin = "Gilded" },
				{ pet = "TriceratopsPet", skin = "Crystal" },
			},
			Rare = {
				{ pet = "TyrannosaurusPet", skin = "Neon" }, { pet = "SharkPet", skin = "Toxic" },
				{ pet = "RaptorPet", skin = "Magma" }, { pet = "TyrannosaurusPet", skin = "Gilded" },
			},
			Epic = {
				{ pet = "TyrannosaurusPet", skin = "Galaxy" }, { pet = "SpinosaurusPet", skin = "Rainbow" },
				{ pet = "TyrannosaurusPet", skin = "Cyber" },
			},
			Legendary = { { pet = "TyrannosaurusPet", skin = "Shadow" }, { pet = "TriceratopsPet", skin = "Celestial" } },
			Gold      = { { pet = "TyrannosaurusPet", skin = "Cosmic" } },
		},
	},

	{
		id = "Premium", displayName = "Premium Crate",
		blurb = "Better odds across the board. Half the Commons of a Starter.",
		price = 600, color = Color3.fromRGB(72, 200, 120), icon = "\xF0\x9F\x8E\x81", -- gift
		-- BETTER ODDS: Common roughly halved, everything above it lifted. Still sums to 100 (asserted below).
		odds = { Common = 58.00, Uncommon = 30.00, Rare = 9.00, Epic = 2.20, Legendary = 0.60, Gold = 0.20 },
		contents = {
			Common = {
				{ pet = "SharkPet", skin = "Stone" }, { pet = "TriceratopsPet", skin = "Sand" },
				{ pet = "RaptorPet", skin = "Mud" }, { pet = "StegoPet", skin = "Chocolate" },
			},
			Uncommon = {
				{ pet = "SharkPet", skin = "Coral" }, { pet = "TriceratopsPet", skin = "Ice" },
				{ pet = "TyrannosaurusPet", skin = "Crystal" }, { pet = "SharkPet", skin = "Gilded" },
				{ pet = "RaptorPet", skin = "Emerald" },
			},
			Rare = {
				{ pet = "StegoPet", skin = "Neon" }, { pet = "SpinosaurusPet", skin = "Toxic" },
				{ pet = "RaptorPet", skin = "Magma" }, { pet = "StegoPet", skin = "Neon" },
			},
			Epic = {
				{ pet = "RaptorPet", skin = "Galaxy" }, { pet = "StegoPet", skin = "Cyber" },
				{ pet = "TriceratopsPet", skin = "Rainbow" },
			},
			Legendary = { { pet = "SharkPet", skin = "Shadow" }, { pet = "TriceratopsPet", skin = "Celestial" } },
			Gold      = { { pet = "SharkPet", skin = "Cosmic" } },
		},
	},

	{
		id = "Elite", displayName = "Elite Crate",
		blurb = "Expensive. Rare or better more often than not.",
		price = 1500, color = Color3.fromRGB(248, 150, 56), icon = "\xF0\x9F\x92\x8E", -- gem
		-- HIGH CHANCE OF RARE+: Rare/Epic/Legendary/Gold together are 55% of this crate.
		odds = { Common = 20.00, Uncommon = 25.00, Rare = 34.00, Epic = 15.00, Legendary = 5.00, Gold = 1.00 },
		contents = {
			Common   = { { pet = "TyrannosaurusPet", skin = "Stone" }, { pet = "SharkPet", skin = "Moss" } },
			Uncommon = {
				{ pet = "TyrannosaurusPet", skin = "Crystal" }, { pet = "StegoPet", skin = "Emerald" },
				{ pet = "RaptorPet", skin = "Gilded" },
			},
			Rare = {
				{ pet = "TyrannosaurusPet", skin = "Neon" }, { pet = "SharkPet", skin = "Toxic" },
				{ pet = "TriceratopsPet", skin = "Magma" }, { pet = "TriceratopsPet", skin = "Neon" },
			},
			Epic = {
				{ pet = "SharkPet", skin = "Galaxy" }, { pet = "StegoPet", skin = "Cyber" },
				{ pet = "SharkPet", skin = "Rainbow" }, { pet = "TyrannosaurusPet", skin = "Galaxy" },
			},
			Legendary = {
				{ pet = "SpinosaurusPet", skin = "Shadow" }, { pet = "TyrannosaurusPet", skin = "Celestial" },
				{ pet = "StegoPet", skin = "Shadow" },
			},
			Gold = { { pet = "SpinosaurusPet", skin = "Cosmic" }, { pet = "TyrannosaurusPet", skin = "Cosmic" } },
		},
	},

	{
		id = "Mythic", displayName = "Mythic Crate",
		blurb = "Limited collection. Events, Season Pass and Robux bundles only.",
		price = 3000, color = Color3.fromRGB(240, 96, 180), icon = "\xE2\x9C\xA8", -- sparkles
		-- The event crate: no Commons at all, and the best Gold rate in the game.
		odds = { Common = 0.00, Uncommon = 18.00, Rare = 40.00, Epic = 28.00, Legendary = 11.00, Gold = 3.00 },
		limited = true, -- flagged for the UI: not bought with tokens in the normal shop
		contents = {
			Uncommon = { { pet = "TyrannosaurusPet", skin = "Ice" }, { pet = "StegoPet", skin = "Crystal" } },
			Rare = {
				{ pet = "TyrannosaurusPet", skin = "Toxic" }, { pet = "TriceratopsPet", skin = "Magma" },
				{ pet = "SharkPet", skin = "Neon" },
			},
			Epic = {
				{ pet = "TyrannosaurusPet", skin = "Cyber" }, { pet = "TriceratopsPet", skin = "Galaxy" },
				{ pet = "StegoPet", skin = "Rainbow" }, { pet = "SharkPet", skin = "Cyber" },
			},
			Legendary = {
				{ pet = "SharkPet", skin = "Shadow" }, { pet = "RaptorPet", skin = "Celestial" },
				{ pet = "StegoPet", skin = "Shadow" },
			},
			Gold = {
				{ pet = "TriceratopsPet", skin = "Cosmic" }, { pet = "SharkPet", skin = "Cosmic" },
				{ pet = "RaptorPet", skin = "Cosmic" },
			},
		},
	},

}

-- ---- ROBUX TOKEN PACKS (Developer Products) -----------------------------------------------------------------
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- !!!  PLACEHOLDER DEVELOPER PRODUCT IDS -- REPLACE BEFORE LAUNCH.                                          !!!
-- !!!  Create four Developer Products (Creator Dashboard > Store > Developer Products) at the R$ prices      !!!
-- !!!  below, then paste their real assetIds over these placeholders. Until you do, leave TEST_MODE = true   !!!
-- !!!  and use /givetokens to test.                                                                        !!!
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
SkinCrates.SINGLE_TOKEN_ROBUX = 0.4 -- reference rate (R$ per token) used only to compute the "Save X%" tags
SkinCrates.TOKEN_PACKS = {
	{ id = "tok250",  productId = 900000001, tokens =  250, robux =  99,                    label = "250 Tokens"   },
	{ id = "tok700",  productId = 900000002, tokens =  700, robux = 249, tag = "Popular",    label = "700 Tokens"   },
	{ id = "tok1800", productId = 900000003, tokens = 1800, robux = 599, tag = "Best Value", label = "1,800 Tokens" },
	{ id = "tok5000", productId = 900000004, tokens = 5000, robux = 1499,                    label = "5,000 Tokens" },
}

-- ---- TEST MODE (no Robux) -----------------------------------------------------------------------------------
-- While TEST_MODE is true the token packs do NOT open a Roblox purchase prompt (there is no real product yet).
-- The client fires "buy" and the SERVER credits tokens through the SAME addTokens() the real ProcessReceipt path
-- calls, so every downstream step (balance, save, crate open, roll, grant, reveal) behaves exactly as it will on
-- launch. The only difference is where the credit comes from.
--
-- TO GO LIVE: create the products, paste the real ids above, set this to false. The server then refuses the
-- "buy" verb outright, so a shipped build can't be farmed for free tokens by an old client.
SkinCrates.TEST_MODE = true

-- ---- TRADE UPS ---------------------------------------------------------------------------------------------
-- CS:GO's trade-up contract: hand in TRADE_UP.COST skins of one rarity, get 1 random skin of the next rarity up.
-- The pet is random, the skin is random, and the trait rolls fresh -- so a trade-up is its own little pull.
--
-- This is the sink that gives duplicates a purpose. Without it a second Stone Bean Buddy is worth nothing and
-- the inventory just accumulates; with it every duplicate is 1/10th of a step up the ladder.
SkinCrates.TRADE_UP = {
	COST = 10, -- how many same-rarity skins one contract consumes
	-- What each rarity trades UP into. Gold is deliberately absent: it's the top, so it has nothing to become.
	NEXT = {
		Common    = "Uncommon",
		Uncommon  = "Rare",
		Rare      = "Epic",
		Epic      = "Legendary",
		Legendary = "Gold",
	},
}

-- The rarity a given tier trades up into, or nil if it's the top of the ladder.
function SkinCrates.tradeUpTarget(tier)
	return SkinCrates.TRADE_UP.NEXT[tier]
end

-- Every (pet, skin) pair that can come OUT of a trade-up at `tier`, gathered from every crate so the result pool
-- isn't limited to one crate's collection. Deduped -- the same pair often appears in more than one crate.
function SkinCrates.tradeUpPool(tier)
	local seen, out = {}, {}
	for _, crate in ipairs(SkinCrates.CRATES) do
		-- A level crate stocks no skins, so it can neither feed nor receive a trade-up contract.
		for _, e in ipairs((not SkinCrates.isLevelCrate(crate)) and crate.contents[tier] or {}) do
			local k = e.pet .. "|" .. e.skin
			if not seen[k] then seen[k] = true; out[#out + 1] = { pet = e.pet, skin = e.skin } end
		end
	end
	return out
end

-- ---- LOOKUPS ------------------------------------------------------------------------------------------------
SkinCrates.ById = {}
for _, c in ipairs(SkinCrates.CRATES) do SkinCrates.ById[c.id] = c end

-- Does this crate pay out pet LEVELS instead of skins? Everything that has to branch on payout shape asks
-- here rather than testing `kind` directly, so adding a third kind later is one edit, not a search.
function SkinCrates.isLevelCrate(crateOrId)
	local c = type(crateOrId) == "table" and crateOrId or SkinCrates.getCrate(crateOrId)
	return c ~= nil and c.kind == "levels"
end

function SkinCrates.getCrate(id)
	return (type(id) == "string" and SkinCrates.ById[id]) or nil
end
function SkinCrates.packById(id)
	for _, p in ipairs(SkinCrates.TOKEN_PACKS) do if p.id == id then return p end end
	return nil
end
function SkinCrates.packByProductId(productId)
	for _, p in ipairs(SkinCrates.TOKEN_PACKS) do if p.productId == productId then return p end end
	return nil
end

-- Every entry in a crate, flattened to { pet, skin, rarity } in RARITY_ORDER. Used by the client to build the
-- reel and the crate's contents list, and by the require-time validator below.
function SkinCrates.flatContents(crateId)
	local crate = SkinCrates.getCrate(crateId)
	local out = {}
	if not crate then return out end
	for _, rarity in ipairs(SkinCrates.RARITY_ORDER) do
		for _, e in ipairs(crate.contents[rarity] or {}) do
			out[#out + 1] = { pet = e.pet, skin = e.skin, levels = e.levels, rarity = rarity }
		end
	end
	return out
end

-- Which rarity bands this crate actually has entries for, and their total weight. A crate mid-build (some bands
-- empty) stays openable: the empty bands' weight is redistributed proportionally across the filled ones.
function SkinCrates.liveRarities(crateId)
	local crate = SkinCrates.getCrate(crateId)
	local live, total = {}, 0
	if not crate then return live, 0 end
	local odds = SkinCrates.oddsFor(crate)
	for _, rarity in ipairs(SkinCrates.RARITY_ORDER) do
		local pool = crate.contents[rarity]
		if pool and #pool > 0 then
			local w = odds[rarity] or 0
			live[#live + 1] = { rarity = rarity, weight = w, count = #pool }
			total = total + w
		end
	end
	return live, total
end

-- The EFFECTIVE percent chance of each rarity in THIS crate (after empty-band redistribution). This is what the
-- odds panel must print -- not the raw RARITY_ODDS -- or the published odds would be wrong for a partial crate.
function SkinCrates.effectiveOdds(crateId)
	local live, total = SkinCrates.liveRarities(crateId)
	local out = {}
	if total <= 0 then return out end
	for _, l in ipairs(live) do
		out[l.rarity] = (l.weight / total) * 100
	end
	return out
end

function SkinCrates.totalRarityWeight()
	local t = 0
	for _, r in ipairs(SkinCrates.RARITY_ORDER) do t = t + (SkinCrates.RARITY_ODDS[r] or 0) end
	return t
end

-- ---- THE ROLL -----------------------------------------------------------------------------------------------
-- SERVER-ONLY in practice (the client never calls this). `rng` is a Roblox Random so the SERVER owns the
-- randomness. Rarity first, then a uniform pick inside that rarity -- exactly the specified order.
--
-- Returns: rarity, entry, entryIndex
--   entryIndex is the position in flatContents(crateId), so the client can scroll its reel to the exact item
--   the server picked -- the animation can never show a different reward than the one granted.
-- Returns nil if the crate id is unknown or completely empty.
function SkinCrates.roll(rng, crateId)
	local crate = SkinCrates.getCrate(crateId)
	if not crate then return nil end
	local live, total = SkinCrates.liveRarities(crateId)
	if total <= 0 then return nil end

	-- 1) RARITY
	local pick = rng:NextNumber(0, total)
	local acc, chosen = 0, live[#live].rarity
	for _, l in ipairs(live) do
		acc = acc + l.weight
		if pick < acc then chosen = l.rarity; break end
	end

	-- 2) UNIFORM pick inside that rarity
	local pool = crate.contents[chosen]
	local entry = pool[rng:NextInteger(1, #pool)]

	-- 3) the entry's index in the flattened list, for the client's reel
	local idx = 0
	local isLevels = SkinCrates.isLevelCrate(crate)
	for i, e in ipairs(SkinCrates.flatContents(crateId)) do
		-- Match on whichever payload this crate uses. A level crate has no pet/skin, so comparing those would
		-- compare nil to nil, match the FIRST entry of the band every time, and land the reel on the wrong cell.
		local same = false
		if e.rarity == chosen then
			if isLevels then same = (e.levels == entry.levels)
			else same = (e.pet == entry.pet and e.skin == entry.skin) end
		end
		if same then idx = i; break end
	end

	return chosen, entry, idx
end

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
-- Fails loudly on load rather than shipping a crate with an unobtainable or mis-typed reward.
do
	local total = SkinCrates.totalRarityWeight()
	assert(math.abs(total - 100) < 1e-6,
		string.format("[SkinCrates] RARITY_ODDS must sum to 100, got %s", tostring(total)))

	for _, crate in ipairs(SkinCrates.CRATES) do
		assert(type(crate.id) == "string" and crate.id ~= "", "[SkinCrates] every crate needs an id")
		assert(type(crate.price) == "number" and crate.price > 0,
			string.format("[SkinCrates] crate '%s' needs a positive token price", tostring(crate.id)))
		local count = 0
		for rarity, pool in pairs(crate.contents) do
			assert(SkinCrates.RARITY_ODDS[rarity] ~= nil,
				string.format("[SkinCrates] crate '%s' has unknown rarity band '%s'", crate.id, tostring(rarity)))
			for _, e in ipairs(pool) do
				if SkinCrates.isLevelCrate(crate) then
					-- a level entry must actually pay something, or an open would charge tokens for nothing
					assert(type(e.levels) == "number" and e.levels > 0 and e.levels % 1 == 0,
						string.format("[SkinCrates] crate '%s' / %s: level entries need a positive whole `levels`",
							crate.id, rarity))
				else
					assert(type(e.pet) == "string" and e.pet ~= "",
						string.format("[SkinCrates] crate '%s' / %s has an entry with no pet", crate.id, rarity))
					assert(PetSkins.exists(e.skin),
						string.format("[SkinCrates] crate '%s' / %s: skin '%s' is not in PetSkins.Skins",
							crate.id, rarity, tostring(e.skin)))
				end
				count = count + 1
			end
		end
		assert(count > 0, string.format("[SkinCrates] crate '%s' is empty", crate.id))

		-- A crate that overrides the odds must ALSO sum to 100, and may only name rarities we know about.
		-- Without this a typo'd override ("Rate = 34") would silently vanish 34% of the weight and quietly
		-- change every published percentage in that crate.
		if crate.odds then
			local ot = 0
			for rarity, w in pairs(crate.odds) do
				assert(SkinCrates.RARITY_ODDS[rarity] ~= nil,
					string.format("[SkinCrates] crate '%s' odds has unknown rarity '%s'", crate.id, tostring(rarity)))
				assert(type(w) == "number" and w >= 0,
					string.format("[SkinCrates] crate '%s' odds for '%s' must be a number >= 0", crate.id, rarity))
				ot = ot + w
			end
			assert(math.abs(ot - 100) < 1e-6,
				string.format("[SkinCrates] crate '%s' odds must sum to 100, got %s", crate.id, tostring(ot)))
		end
	end

	-- TRADE UPS: every rung of the ladder must actually be reachable. If a tier trades up into a rarity that no
	-- crate stocks, a contract would consume 10 skins and return nothing -- so refuse to load instead.
	for from, to in pairs(SkinCrates.TRADE_UP.NEXT) do
		assert(SkinCrates.RARITY_ODDS[from] ~= nil and SkinCrates.RARITY_ODDS[to] ~= nil,
			string.format("[SkinCrates] TRADE_UP.NEXT names an unknown rarity: %s -> %s", tostring(from), tostring(to)))
		assert(#SkinCrates.tradeUpPool(to) > 0,
			string.format("[SkinCrates] TRADE_UP %s -> %s: no crate stocks any '%s' skin, so the contract "
				.. "could never pay out", from, to, to))
	end
end

return SkinCrates
