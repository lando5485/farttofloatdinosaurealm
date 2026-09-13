--!nonstrict
-- PetCollection (ReplicatedStorage/Shared/PetCollection)
-- ============================================================================================================
-- The COLLECTION BOOK and its rewards.
--
-- Two jobs, and they're deliberately in one module because they're the same question asked twice:
--   1. "What's the complete list of skins for a pet, and which does this player have?"  -> the Collection Book
--   2. "Has this player finished a pet / the whole game?"                               -> Collection Rewards
--
-- COMPLETION IS TRAIT-AGNOSTIC. A pet is complete when the player owns every SKIN for it, in any trait. That is
-- a deliberate choice: with 21 traits x 17 skins x 11 pets there are 3927 trait-exact combinations, so a
-- trait-exact collection would be unfinishable in a human lifetime and the reward would be decoration rather
-- than a goal. Traits stay a per-item flex, not a completion requirement.
--
-- The book INCLUDES "Default" -- the no-skin look every pet starts with. It's always owned, so every pet's book
-- opens with one tick already filled in. That's intentional: an all-red page reads as "I have nothing" and is a
-- worse hook than "1 / 21, here's what's next".
--
-- Adding content: a new skin in PetSkins or a new pet in PetSystem flows through automatically -- the list is
-- derived, not hand-written. Only REWARDS below is authored, and even that falls back to a generated default.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetSkins = require(Shared:WaitForChild("PetSkins"))

local PetCollection = {}

-- The pseudo-skin every pet owns from the start. Not in PetSkins.Skins (it isn't a recolour -- it's the absence
-- of one), so it's named here and handled explicitly everywhere the book is built.
PetCollection.DEFAULT_ID    = "Default"
PetCollection.DEFAULT_NAME  = "Default"
PetCollection.DEFAULT_COLOR = Color3.fromRGB(190, 198, 214)

-- ---- THE BOOK -----------------------------------------------------------------------------------------------
-- Every skin id a pet can have, in display order: Default first, then PetSkins.Order (already sorted by tier,
-- then name). Cached because the Collection Book asks for this once per pet per repaint.
local skinListCache
function PetCollection.skinList()
	if not skinListCache then
		skinListCache = { PetCollection.DEFAULT_ID }
		for _, id in ipairs(PetSkins.Order) do
			skinListCache[#skinListCache + 1] = id
		end
	end
	return skinListCache
end

function PetCollection.totalSkins()
	return #PetCollection.skinList()
end

-- Build the book page for one pet.
--   ownedSkinIds : a SET of skin ids the player owns for THIS pet, e.g. { Stone = true, Galaxy = true }.
--                  Trait-agnostic -- the caller collapses "PizzaDragon|Galaxy|Crowned" down to "Galaxy" first.
-- Returns: rows (array of { skin, name, tier, color, owned }), ownedCount, total
-- Default always comes back owned -- see the header note.
function PetCollection.page(ownedSkinIds)
	ownedSkinIds = ownedSkinIds or {}
	local rows, owned = {}, 0
	for _, id in ipairs(PetCollection.skinList()) do
		local isDefault = (id == PetCollection.DEFAULT_ID)
		local has = isDefault or (ownedSkinIds[id] == true)
		if has then owned = owned + 1 end
		rows[#rows + 1] = {
			skin  = id,
			name  = isDefault and PetCollection.DEFAULT_NAME or PetSkins.displayName(id),
			tier  = isDefault and "Common" or PetSkins.tierOf(id),
			color = isDefault and PetCollection.DEFAULT_COLOR or PetSkins.tierColor(id),
			owned = has,
		}
	end
	return rows, owned, #PetCollection.skinList()
end

-- True when this pet's page has no misses left.
function PetCollection.isComplete(ownedSkinIds)
	local _, owned, total = PetCollection.page(ownedSkinIds)
	return owned >= total
end

-- ---- COLLECTION REWARDS -------------------------------------------------------------------------------------
-- Finishing ONE pet's book pays out four things, exactly as specified: a badge, a title, an aura, and an
-- exclusive cosmetic. Finishing EVERY pet pays out something that cannot be obtained any other way.
--
-- BADGES: badgeId 0 means "not created yet" and is silently skipped -- the title/aura/cosmetic still grant, so
-- the reward works before you've made the badges. Create them in the Creator Dashboard (Experience > Badges)
-- and paste the real ids in. See the same placeholder pattern in SkinCrates.TOKEN_PACKS.
--
-- AURAS: a persistent particle ring around the player's equipped pet. Rendered client-side by
-- PetSkinLook.client.lua, which reads `color` and `rate` off this table -- so a new aura is a config line, not
-- new render code.
PetCollection.AURAS = {
	Bronze  = { name = "Bronze Aura",    color = Color3.fromRGB(205, 127,  50), rate =  6 },
	Silver  = { name = "Silver Aura",    color = Color3.fromRGB(206, 212, 222), rate =  8 },
	Golden  = { name = "Golden Aura",    color = Color3.fromRGB(255, 205,  70), rate = 10 },
	Verdant = { name = "Verdant Aura",   color = Color3.fromRGB( 96, 226, 130), rate =  8 },
	Frost   = { name = "Frost Aura",     color = Color3.fromRGB(150, 224, 255), rate =  9 },
	Ember   = { name = "Ember Aura",     color = Color3.fromRGB(255, 132,  62), rate = 10 },
	Void    = { name = "Void Aura",      color = Color3.fromRGB(126,  74, 220), rate = 11 },
	Prism   = { name = "Prismatic Aura", color = Color3.fromRGB(255, 120, 220), rate = 14, rainbow = true },
}

-- Per-pet overrides. A pet with no entry here still gets a reward -- see rewardFor() -- so this table is for
-- flavour, not for coverage, and a newly added pet is never left without a payout.
PetCollection.REWARDS = {
	BeanBuddy        = { title = "Bean Counter",     aura = "Verdant", badgeId = 0, cosmetic = "Golden"  },
	BroccoliPet      = { title = "Tree Hugger",      aura = "Verdant", badgeId = 0, cosmetic = "Jungle"  },
	CoconutCrab      = { title = "Shell Shocked",    aura = "Frost",   badgeId = 0, cosmetic = "Ocean"   },
	PopcornSheep     = { title = "Kernel",           aura = "Golden",  badgeId = 0, cosmetic = "Candy"   },
	ButterDuck       = { title = "Butterball",       aura = "Golden",  badgeId = 0, cosmetic = "Rainbow" },
	BurritoArmadillo = { title = "Fully Wrapped",    aura = "Ember",   badgeId = 0, cosmetic = "Lava"    },
	PizzaDragon      = { title = "Deep Dish",        aura = "Ember",   badgeId = 0, cosmetic = "Shadow"  },
	SunflowerBee     = { title = "Pollinator",       aura = "Golden",  badgeId = 0, cosmetic = "Toxic"   },
	MapleFox         = { title = "Sap Sipper",       aura = "Bronze",  badgeId = 0, cosmetic = "Robot"   },
	FrostPenguin     = { title = "Cold Blooded",     aura = "Frost",   badgeId = 0, cosmetic = "Arctic"  },
	BlossomBunny     = { title = "In Full Bloom",    aura = "Prism",   badgeId = 0, cosmetic = "Crystal" },
}

-- What completing `petId` pays out. Falls back to a generated reward so a pet added tomorrow still works today.
function PetCollection.rewardFor(petId, petDisplayName)
	local r = PetCollection.REWARDS[petId]
	if r then return r end
	return {
		title    = (petDisplayName or petId) .. " Collector",
		aura     = "Silver",
		badgeId  = 0,
		cosmetic = nil, -- nothing exclusive by default; author an entry above to add one
	}
end

-- ---- THE FULL COLLECTION ------------------------------------------------------------------------------------
-- Every skin on every pet. This is the "extremely rare" payout -- the thing a completionist plays for after the
-- realms are done. Deliberately NOT obtainable from any crate, trade-up, or purchase: earning it is the only way
-- anyone ever has it, which is what makes it worth chasing.
PetCollection.FULL_COLLECTION = {
	title    = "Living Legend",
	aura     = "Prism",
	badgeId  = 0,
	-- A Cosmic skin on EVERY pet at once, granted as real inventory entries so it shows up in the book and can
	-- be equipped like anything else.
	grantSkinOnEveryPet = "Cosmic",
	announce = true, -- server-wide announcement, same treatment as a Gold pull
}

-- ---- TITLES -------------------------------------------------------------------------------------------------
-- A player can hold many titles but display one. Empty string = none shown.
PetCollection.NO_TITLE = ""

return PetCollection
