--!strict
-- ============================================================================================================
-- PET RARITY + FUSION -- the rules for the axis that NEVER changes.
-- ============================================================================================================
-- A pet has TWO INDEPENDENT AXES and conflating them is the bug this module exists to prevent:
--
--   AGE     Baby -> Kid -> Teen -> Adult -> Elder.  Derived from LEVEL, which is earned by flying and playing
--           (PetSystem.awardXP: distance/coins/gas/islands). It is GROWN. Everyone can reach Elder.
--   RARITY  Common -> Uncommon -> Rare -> Epic -> Legendary -> Gold.  Set when the pet is obtained and then
--           FROZEN FOREVER. It is never earned by playing. An Uncommon that grinds to Elder is still Uncommon;
--           it is just a very big Uncommon.
--
-- The ONLY thing that moves a pet up the rarity ladder is FUSION: hand in N duplicates of the same species at
-- the same rarity, get back one of that species at the next rarity up. Rarer pets otherwise come only from
-- crate spins (and from trading with players who pulled them).
--
-- THE LADDER IS NOT DEFINED HERE. It is PetSkins.TIER_ORDER / PetSkins.TierColor -- the exact same six bands
-- the crates already roll and the skins already use. Pets deliberately borrow that vocabulary instead of
-- inventing a parallel one, so "Epic" means one thing everywhere in the game and a colour never disagrees
-- with itself between a skin card and a pet card. Change a band there and it changes here for free.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared    = ReplicatedStorage:WaitForChild("Shared")
local PetSkins  = require(Shared:WaitForChild("PetSkins"))

local PetRarity = {}

-- The six bands, rarest last. Borrowed, not redefined -- see the header.
PetRarity.ORDER = PetSkins.TIER_ORDER
PetRarity.Color = PetSkins.TierColor
PetRarity.Rank  = PetSkins.TierRank

-- Every pet that is not explicitly something rarer is this. A quest pet is ALWAYS this: quests are a
-- guaranteed known reward, never a gamble.
PetRarity.DEFAULT = "Common"

PetRarity.TOP = PetRarity.ORDER[#PetRarity.ORDER] -- "Gold" -- nothing fuses past this

-- ---- FUSION COST -------------------------------------------------------------------------------------------
-- How many duplicates AT a band it costs to make one pet at the NEXT band up. Keyed by the band you are
-- fusing FROM.
--
-- The ramp is deliberate: cheap at the bottom so a new player can actually complete their first fuse and learn
-- that the system exists, dearer at the top so a Gold stays a genuine trophy. Flat pricing would either make
-- the first fuse feel unreachable or the last one feel free.
--
-- COMPOUNDING IS THE REAL COST. These are per-step, and each step needs pets that themselves had to be fused:
-- one Gold is 5*6*7*8*10 = 16,800 Commons if built from the very bottom. Nobody will do that -- which is the
-- point. Fusion is meant to finish a climb that crate luck started, not replace the crate.
PetRarity.FUSE_COST = {
	Common    = 5,
	Uncommon  = 6,
	Rare      = 7,
	Epic      = 8,
	Legendary = 10,
	-- Gold has no entry ON PURPOSE: it is the top of the ladder, so it can never be fused away. Any code that
	-- reads this table must treat a nil as "cannot fuse", not as "free".
}

-- The band above `rarity`, or nil at the top of the ladder.
function PetRarity.nextOf(rarity: string?): string?
	local r = PetRarity.Rank[rarity or ""] -- unknown band -> nil rank -> nil next (never a silent Common)
	if not r then return nil end
	return PetRarity.ORDER[r + 1]
end

-- How many duplicates it costs to fuse up from `rarity`. nil = this band cannot be fused (top, or unknown).
function PetRarity.costToFuse(rarity: string?): number?
	if not rarity or not PetRarity.Rank[rarity] then return nil end
	if not PetRarity.nextOf(rarity) then return nil end -- at the top: no upgrade exists to buy
	return PetRarity.FUSE_COST[rarity]
end

-- Is `rarity` a band this game actually has? Anything that fails this is treated as Common by normalise().
function PetRarity.isValid(rarity: string?): boolean
	return rarity ~= nil and PetRarity.Rank[rarity] ~= nil
end

-- Coerce anything -- nil, a legacy save, a typo, a malicious client value -- into a real band. Every entry
-- point that accepts a rarity from outside this module runs it through here first, so no downstream code has
-- to defend against a bad band.
function PetRarity.normalise(rarity: any): string
	return (type(rarity) == "string" and PetRarity.Rank[rarity]) and rarity or PetRarity.DEFAULT
end

-- Can this stack fuse right now? Returns ok, costOrReason -- callers show the reason in the UI.
-- `count` is the number of copies HELD (a stack of 1 is the pet itself, not a spare).
function PetRarity.canFuse(rarity: string?, count: number?): (boolean, any)
	local band = PetRarity.normalise(rarity)
	local have = tonumber(count) or 0
	local cost = PetRarity.costToFuse(band)
	if not cost then return false, "This is the highest rarity" end
	if have < cost then return false, cost - have end -- how many MORE are needed
	return true, cost
end

return PetRarity
