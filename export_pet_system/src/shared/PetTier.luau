--!nonstrict
-- PetTier (ReplicatedStorage/Shared/PetTier)
-- ============================================================================================================
-- THE OVERALL PET TIER -- the ONE label shown above a pet.
--
--   Skin hidden value  +  Trait hidden value  =  PET SCORE  ->  Overall Tier (Common .. Legendary)
--
-- The hidden values live with their owners (PetSkins.TIER_VALUE / PetTraits.TIER_VALUE); THIS file owns the
-- thresholds that turn a score back into a tier. All three tables are plain config -- retuning the whole
-- economy of "how good is this combination" never touches code.
--
-- With the shipped values (Common 1 / Uncommon 2 / Rare 4 / Epic 7 / Legendary 11 on both axes), same-tier
-- pairs score 2 / 4 / 8 / 14 / 22 and the thresholds below map each of those back to its own tier:
--
--   Cosmic (L=11)  + King (E=7)      = 18 -> Legendary     (two high values make the top band)
--   Crystal (R=4)  + Astronaut (R=4) =  8 -> Rare
--   Rainbow (L=11) + Bowtie (C=1)    = 12 -> Epic          (a top skin with a low trait lands one band down)
--   Classic (C=1)  + Titan (L=11)    = 12 -> Epic          (symmetric: the trait can carry a pet too)
--
-- The overhead display shows ONLY this tier -- never "Legendary Skin" + "Epic Trait" stacked above a pet.
-- The detail card in the pet menu is where the per-part rarities are spelled out.
--
-- Overall tiers never include Gold: Gold is the crate-jackpot band and the top PET rarity, not a cosmetic
-- score. The colours come from PetSkins.TierColor so "Epic" is the same purple everywhere in the game.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared    = ReplicatedStorage:WaitForChild("Shared")
local PetSkins  = require(Shared:WaitForChild("PetSkins"))
local PetTraits = require(Shared:WaitForChild("PetTraits"))

local PetTier = {}

-- Score thresholds, checked TOP-DOWN: the first entry whose `min` the score reaches wins. Ordered rarest
-- first so the loop reads the way the ladder does.
PetTier.THRESHOLDS = {
	{ tier = "Legendary", min = 18 },
	{ tier = "Epic",      min = 11 },
	{ tier = "Rare",      min =  6 },
	{ tier = "Uncommon",  min =  3 },
	{ tier = "Common",    min =  0 },
}

-- The combined hidden score for a (skin, trait) pair. Either may be nil/"" (legacy pets); a missing part
-- simply contributes 0.
function PetTier.score(skinId, traitId)
	return PetSkins.valueOf(skinId) + PetTraits.valueOf(traitId)
end

-- Score -> tier name.
function PetTier.tierForScore(score)
	score = tonumber(score) or 0
	for _, row in ipairs(PetTier.THRESHOLDS) do
		if score >= row.min then return row.tier end
	end
	return "Common"
end

-- THE main entry point: the Overall Tier for a (skin, trait) pair, plus its colour.
-- No skin AND no trait -> nil (an unskinned legacy pet shows its age alone, exactly as before).
function PetTier.overall(skinId, traitId)
	local hasSkin  = PetSkins.exists(skinId)
	local hasTrait = not PetTraits.isNone(traitId)
	if not hasSkin and not hasTrait then return nil, nil end
	local tier = PetTier.tierForScore(PetTier.score(skinId, traitId))
	return tier, PetSkins.tierColor(tier)
end

-- ---- REQUIRE-TIME VALIDATION --------------------------------------------------------------------------------
do
	local last
	for _, row in ipairs(PetTier.THRESHOLDS) do
		assert(PetSkins.TierRank[row.tier], "[PetTier] threshold names unknown tier '" .. tostring(row.tier) .. "'")
		assert(row.tier ~= "Gold", "[PetTier] Overall Tier can never be Gold")
		assert(type(row.min) == "number" and (last == nil or row.min < last),
			"[PetTier] THRESHOLDS must be ordered rarest-first with strictly falling mins")
		last = row.min
	end
	assert(PetTier.THRESHOLDS[#PetTier.THRESHOLDS].min <= 0,
		"[PetTier] the lowest threshold must catch a zero score")
end

return PetTier
