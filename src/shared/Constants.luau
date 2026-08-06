--!nonstrict
-- Constants (ReplicatedStorage/Shared/Constants)
-- Shared tuning values for the Space Realm Mystery Meteor Crate system. Required by both
-- the server authority (CrateService / PlayerState) and the client (CrateClient / HudSidebarStats).
-- Server is the ONLY authority for eligibility/roll/grant; these numbers must match on both sides.

local Constants = {}

-- ===== MYSTERY METEOR CRATE =====
-- REWARD: pet levels (not cosmetics). Rarity decides how many levels are added to the player's
-- chosen owned pet, hard-capped at PET_MAX_LEVEL. If every owned pet is maxed -> FALLBACK_COINS.
Constants.CRATE = {
	-- 8 hours between free claims (8 * 60 * 60).
	COOLDOWN_SECONDS = 28800,
	-- Coins granted when every owned pet is already at the level cap (nothing left to level).
	FALLBACK_COINS = 500,
	-- Pet level cap (mirrors PetSystem.PET_MAX_LEVEL; grants clamp here).
	PET_MAX_LEVEL = 25,
	-- Rarity roll weights. Sum = 100, but consumers compute the total defensively so any
	-- future re-weighting still works without touching the roll code.
	RARITY_WEIGHTS = {
		Uncommon = 55,
		Rare = 28,
		Epic = 13,
		Mythical = 4,
	},
	-- Deterministic rarity order (used when iterating weights for a stable cumulative roll).
	RARITY_ORDER = { "Uncommon", "Rare", "Epic", "Mythical" },
	-- Levels granted per rarity (clamped to PET_MAX_LEVEL on apply).
	RARITY_LEVELS = {
		Uncommon = 1,
		Rare = 2,
		Epic = 4,
		Mythical = 6,
	},
	-- Reveal-card header / accent color per rarity.
	RARITY_COLORS = {
		Uncommon  = Color3.fromRGB(150, 160, 172),
		Rare      = Color3.fromRGB(70, 140, 255),
		Epic      = Color3.fromRGB(175, 90, 240),
		Mythical  = Color3.fromRGB(255, 200, 60),
	},
}

return Constants
