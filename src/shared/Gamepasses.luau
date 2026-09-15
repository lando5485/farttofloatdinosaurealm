--!nonstrict
-- ============================================================================================================
-- GAMEPASSES -- the SINGLE source of truth for every gamepass id in this realm.
-- ============================================================================================================
-- PORTED FROM THE SPACE REALM (src/shared/Gamepasses.luau). The ids, the legacy ids and the attribute names
-- are COPIED EXACTLY and must stay that way: all the Fart to Float realms are one experience, so a pass is
-- bought once and owned everywhere. A different id here is not a different pass, it is a pass that silently
-- does nothing for the player who paid for it.
--
-- ---- WHY THIS FILE EXISTS IN THE DINO REALM ------------------------------------------------------------------
-- Dino knew about THREE of the six passes, hardcoded separately in four places that had already drifted:
--
--     Bootstrap.client:1480     { TwoXForever, GlitterTrail }
--     Shop.client:11            { TwoXForever, GlitterTrail }
--     ShopKit.client:54         { TwoXForever, GlitterTrail, PrimalGut }
--     PurchaseReceipts.server:26 { TwoXForever, GlitterTrail, PrimalGut }
--
-- Nothing here had ever heard of LuckyPass, VIP or CoinMagnet. A player who bought VIP in the Space Realm
-- crossed the rift and it evaporated -- not disabled, not degraded: the realm had no idea the pass existed.
-- That is the bug this file closes.
--
-- ---- LEGACY IDS ARE NOT OPTIONAL ------------------------------------------------------------------------------
-- Space shipped its own "Lucky Crates" (89 R$) and "VIP" (69 R$) before its shared module existed, and people
-- really bought them. Ownership must check the current id AND every superseded one, granting on ANY match.
-- Only the current id is ever OFFERED for sale -- this list is a promise to existing customers, not a second
-- storefront.
--
-- ---- THE 0 = UNSET RULE ---------------------------------------------------------------------------------------
-- A pass may be listed with id 0 before its Robux product exists. 0 means UNSET: allIdsFor filters it out, so
-- the server never asks Roblox about it and nothing can grant it. A fake-looking id is worse than no id.
-- ============================================================================================================

local Gamepasses = {}

-- ---- THE IDS -------------------------------------------------------------------------------------------------
-- ⚠ MUST MATCH SpaceRealm/src/shared/Gamepasses.luau EXACTLY.
Gamepasses.IDS = {
	TwoXForever  = 1862015450,
	GlitterTrail = 1859714979,
	InfiniteGut  = 1860686821,   -- this realm calls the perk "Primal Gut"; SAME pass, same id
	LuckyPass    = 1875286225,
	CoinMagnet   = 1874638222,
	VIP          = 1874992233,
}

-- Older passes granting the SAME perk. These must keep working forever.
Gamepasses.LEGACY_IDS = {
	LuckyPass = { 1884292287 }, -- Space Realm's original "Lucky Crates", 89 R$
	VIP       = { 1883020301 }, -- Space Realm's original "VIP", 69 R$
}

-- ---- OWNERSHIP IS AN ATTRIBUTE --------------------------------------------------------------------------------
-- Player attributes replicate to every client for free: no remotes, late joiners work, and either side can
-- just ask. HasTwoXForever / HasGlitterTrail are already used across this realm, so those names are load-
-- bearing -- the three new ones follow the same convention.
Gamepasses.ATTR = {
	TwoXForever  = "HasTwoXForever",
	GlitterTrail = "HasGlitterTrail",
	InfiniteGut  = "HasPrimalGut",    -- ⚠ Dino's own name for this attribute; see NOTE below
	LuckyPass    = "HasLuckyPass",
	VIP          = "HasVIP",
	CoinMagnet   = "HasCoinMagnet",
}
-- NOTE ON InfiniteGut/HasPrimalGut: Space sets "HasInfiniteGut"; this realm has always called the same perk
-- Primal Gut and reads "HasPrimalGut". The ID is what the purchase is, the attribute is just this realm's
-- local name for it -- PurchaseReceipts sets BOTH so a script ported either direction keeps working.

Gamepasses.NAMES = {
	TwoXForever  = "2x Fart Power Forever",
	GlitterTrail = "Glitter Fart Trail",
	InfiniteGut  = "Primal Gut",
	LuckyPass    = "Lucky Pass",
	VIP          = "VIP",
	CoinMagnet   = "Coin Magnet",
}

Gamepasses.PRICE = {   -- what the shop CARD prints; Roblox is the authority on what is charged
	TwoXForever = 249, GlitterTrail = 49, InfiniteGut = 499,
	LuckyPass = 75, VIP = 100, CoinMagnet = 125,
}

-- ---- TUNING (copied from Space so the two realms grant the same thing) -----------------------------------------
Gamepasses.LUCKY_MULT        = 2.0    -- multiplies the weight of every crate band above the commonest
Gamepasses.LUCK_MAX          = 5.0    -- ceiling on total luck, or rare bands could overtake common
Gamepasses.VIP_COIN_PERK     = 0.25   -- +25% flight coins
Gamepasses.VIP_DAILY_COINS   = 500    -- once per UTC day
Gamepasses.VIP_TAG_TEXT      = "\226\173\144 VIP"
Gamepasses.VIP_TAG_COLOR     = Color3.fromRGB(255, 215, 0)
Gamepasses.MAGNET_BUBBLE_RANGE = 90   -- studs; gas bubbles are bounded, so a generous pull is free
Gamepasses.MAGNET_COIN_RANGE   = 28   -- studs; ring/coin value is NOT capped per flight, so keep it short

-- Every id that grants `key` -- current first, then superseded. Unset (0) ids filtered out.
function Gamepasses.allIdsFor(key)
	local out = {}
	local cur = Gamepasses.IDS[key]
	if type(cur) == "number" and cur > 0 then out[#out + 1] = cur end
	for _, old in ipairs(Gamepasses.LEGACY_IDS[key] or {}) do
		if type(old) == "number" and old > 0 then out[#out + 1] = old end
	end
	return out
end

-- key -> every id, flattened. Used by the join-time ownership sweep.
function Gamepasses.allKeys()
	local keys = {}
	for k in pairs(Gamepasses.IDS) do keys[#keys + 1] = k end
	table.sort(keys)   -- deterministic, so logs from two servers read the same
	return keys
end

-- Which key does this id grant? Covers legacy ids, so a purchase prompt for a superseded
-- pass still resolves. nil when the id belongs to no pass here.
function Gamepasses.keyForId(id)
	id = tonumber(id)
	if not id then return nil end
	for key in pairs(Gamepasses.IDS) do
		for _, candidate in ipairs(Gamepasses.allIdsFor(key)) do
			if candidate == id then return key end
		end
	end
	return nil
end

return Gamepasses
