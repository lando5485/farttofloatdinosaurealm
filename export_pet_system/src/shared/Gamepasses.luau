--!nonstrict
-- (nonstrict on purpose: the helpers index IDS/ATTR with a runtime string key, which --!strict rejects.)
-- ============================================================================================================
-- GAMEPASSES -- the SINGLE source of truth for every gamepass id, what it is called, and what it does.
-- ============================================================================================================
-- WHY THIS FILE EXISTS. Before it, GAMEPASS_IDS was copy-pasted into SIX places in this place alone
-- (HUD_AllInOne.client:482, ShopClient.client:11, Shop_AllInOne.client:11, PlayerStats.server:169,
-- PurchaseBanner_AllInOne.server:24, shared/RealmTransfer.luau:28) plus two more in CandyRealm -- and they had
-- ALREADY drifted: the three client copies are missing InfiniteGut entirely. Every new pass was a six-file
-- edit with a guaranteed drift bug waiting in it.
--
-- New code reads THIS. The old duplicated tables are left in place for now (ripping them out is a sweep across
-- a 94k-line codebase and a second place) -- but nothing new should ever add a seventh copy.
--
-- ---- THE 0 = UNSET RULE -------------------------------------------------------------------------------------
-- ALL SIX PASSES ARE LIVE. The rule below still governs any pass added in future, and the guards it describes
-- are still in force -- there is just nothing sitting at 0 right now.
--
-- A pass may be added here with id 0 before its Robux product exists. 0 means UNSET and every helper refuses to
-- act on it: `isConfigured` is false, `prompt` no-ops, the server never asks Roblox about it, and the shop card
-- renders as COMING SOON with a dead button. So an unconfigured pass is INERT -- unbuyable, grants nothing.
--
-- This is deliberately NOT how the pet tier-skip products were left. Those carry real-LOOKING ids
-- (123456701-704 in PetSystem.server:276 and PetFollow.client:177) which sail past every guard and open a
-- broken Robux prompt on a live player. A fake id is worse than no id. Use 0.
--
-- TO GO LIVE: create the pass on Roblox, paste its id below, done. Nothing else needs to change.
-- ============================================================================================================

local MarketplaceService = game:GetService("MarketplaceService")

local Gamepasses = {}

-- ---- THE IDS ------------------------------------------------------------------------------------------------
Gamepasses.IDS = {
	-- live
	TwoXForever  = 1862015450,
	GlitterTrail = 1859714979,
	InfiniteGut  = 1860686821,
	LuckyPass    = 1875286225,
	CoinMagnet   = 1874638222,
	VIP          = 1874992233,
}

-- ---- LEGACY / SUPERSEDED IDS --------------------------------------------------------------------------------
-- Older passes that grant the SAME perk as a key above and must keep working forever.
--
-- Space Realm shipped its own "Lucky Crates" (89 R$) and "VIP" (69 R$) before this module existed. Those are
-- REAL passes people have really bought. Because the F2F realms are ONE experience, a purchase of either is
-- visible from every realm -- so a Space VIP buyer must get VIP in Food and Candy too, not just in Space.
--
-- Ownership therefore checks the current id AND every legacy id, and grants on ANY match. The current id is the
-- only one ever OFFERED for sale (see prompt()), so this list only ever grows when a pass is superseded --
-- it is a promise to existing customers, not a second storefront.
Gamepasses.LEGACY_IDS = {
	LuckyPass = { 1884292287 }, -- Space Realm's original "Lucky Crates", 89 R$
	VIP       = { 1883020301 }, -- Space Realm's original "VIP", 69 R$
}

-- Every id that grants `key` -- current first, then any superseded ones. Unset (0) ids are filtered out.
function Gamepasses.allIdsFor(key: string): { number }
	local out = {}
	local cur = Gamepasses.IDS[key]
	if type(cur) == "number" and cur > 0 then out[#out + 1] = cur end
	for _, old in ipairs(Gamepasses.LEGACY_IDS[key] or {}) do
		if type(old) == "number" and old > 0 then out[#out + 1] = old end
	end
	return out
end

-- ---- OWNERSHIP IS AN ATTRIBUTE ------------------------------------------------------------------------------
-- The server sets these on owners; player attributes replicate to EVERY client for free, so ownership needs no
-- remotes, works for late joiners, and any script on either side can just ask. Same mechanism HasInfiniteGut
-- already uses (CoreClient:3301) and the one TitleTags is built on.
Gamepasses.ATTR = {
	TwoXForever  = "HasTwoXForever",
	GlitterTrail = "HasGlitterTrail",
	InfiniteGut  = "HasInfiniteGut",
	LuckyPass    = "HasLuckyPass",
	VIP          = "HasVIP",
	CoinMagnet   = "HasCoinMagnet",
}

-- Shop-facing Robux prices. These are what the CARD prints -- Roblox itself is the authority on what is
-- actually charged, so if you change a pass's price on the site, change it here too or the shop will lie.
Gamepasses.PRICE = {
	TwoXForever  = 249,
	GlitterTrail = 49,
	InfiniteGut  = 499,
	LuckyPass    = 75,
	VIP          = 100,
	CoinMagnet   = 125,
}

Gamepasses.NAMES = {
	TwoXForever  = "2x Fart Power Forever",
	GlitterTrail = "Glitter Fart Trail",
	InfiniteGut  = "Infinite Gut",
	LuckyPass    = "Lucky Pass",
	VIP          = "VIP",
	CoinMagnet   = "Coin Magnet",
}

-- ---- TUNING -------------------------------------------------------------------------------------------------
-- Every number the three new passes are worth, in one place, so balancing them never means grepping.

-- LUCKY PASS: multiplies the weight of every band ABOVE the commonest one, then the roll renormalises. At 2x
-- that turns Gold 0.08% -> 0.16% and Common 79.92% -> ~59.8%. Multiplying only the good bands (rather than
-- raising each band by its rank) keeps the curve's SHAPE and makes the pass exactly as strong as it advertises.
Gamepasses.LUCKY_MULT = 2.0

-- Rebirth luck per rebirth. THIS IS THE AUTHORITY -- RebirthSystem.server requires it from here rather than
-- keeping its own copy, so the number the Rebirth panel promises and the number the crates roll cannot drift.
Gamepasses.REBIRTH_LUCK_PER = 0.15

-- Hard ceiling on TOTAL luck (rebirth x pass). Without it a deep-rebirth player with the pass could push the
-- rare bands past the common one and invert the whole rarity ladder, which would make Gold meaningless.
Gamepasses.LUCK_MAX = 5.0

-- VIP: a flat coin perk that STACKS with the friend/group boosts in RewardsService (they are all summed into
-- _G.coinBonusMult), plus a coin stipend granted once per join-day.
Gamepasses.VIP_COIN_PERK   = 0.25   -- +25% flight coins
Gamepasses.VIP_DAILY_COINS = 500    -- once per UTC day
Gamepasses.VIP_TAG_TEXT    = "\xE2\xAD\x90 VIP"
Gamepasses.VIP_TAG_COLOR   = Color3.fromRGB(255, 215, 0)

-- COIN MAGNET: pull ranges, in studs. The pass does NOT change what a pickup is worth or how often it respawns
-- -- it only drags the pickup to you, so the existing collection radii in CoreClient (20 for bubbles, 16 for
-- rings) still do the actual collecting.
--
-- THE TWO RANGES ARE DELIBERATELY VERY DIFFERENT. A gas bubble is bounded (max 6% of the tank, 45s respawn), so
-- a generous pull is free. A RING is not: its bonus is `15 * ringMultiplier * serverEventRingMult`, the streak
-- multiplier compounds all flight, and NOTHING caps ring coins per flight (only height coins are capped). A
-- big ring magnet would be a coin printer, so it gets a short range -- you still have to fly roughly at them.
Gamepasses.MAGNET_BUBBLE_RANGE = 90
Gamepasses.MAGNET_RING_RANGE   = 40
Gamepasses.MAGNET_PULL_SPEED   = 120  -- studs/sec the pickup travels toward you once caught

-- ---- HELPERS ------------------------------------------------------------------------------------------------

-- Is this pass actually purchasable yet? False for any id left at 0.
function Gamepasses.isConfigured(key: string): boolean
	return (Gamepasses.IDS[key] or 0) > 0
end

-- Every pass that has a real id. Iterate THIS rather than IDS so an unset pass is never sent to Roblox.
function Gamepasses.configured(): { [string]: number }
	local out = {}
	for key, id in pairs(Gamepasses.IDS) do
		if id > 0 then out[key] = id end
	end
	return out
end

-- ---- TESTING: FORCE EVERY PASS UN-OWNED ---------------------------------------------------------------------
-- ⚠ TRUE RIGHT NOW. Set to false before you publish, or nobody's passes work.
--
-- WHY THIS IS NEEDED AT ALL: you CANNOT test a pass you created. Roblox reports the creator of a gamepass as
-- owning it, so UserOwnsGamePassAsync is true for you on all six, forever. Without this switch every shop card
-- reads OWNED on your account and there is no way to see the buy flow, the price, or any non-owner behaviour.
--
-- Flipping this makes owns() return false for EVERYONE, which turns off the perk everywhere in one move --
-- luck falls back to rebirth-only, VIP stops paying, the magnet stops pulling, the tag disappears and the shop
-- cards go back to BUY GAMEPASS. It does not stop a purchase going through; it only stops ownership READING as
-- true, which is exactly what you want while testing.
--
-- This is the shared module, so it covers the Food realm, Candy realm and Space realm at once.
Gamepasses.FORCE_UNOWNED = true

-- Does this player own it? Reads the replicated attribute, so it is correct on the client AND the server and
-- costs no web call. An unconfigured pass is never owned by anyone.
function Gamepasses.owns(player: Player, key: string): boolean
	if Gamepasses.FORCE_UNOWNED then return false end
	if not Gamepasses.isConfigured(key) then return false end
	local attr = Gamepasses.ATTR[key]
	return attr ~= nil and player:GetAttribute(attr) == true
end

-- Open the Robux prompt. Guarded twice: an unset id never prompts (that is the whole point of the 0 rule), and
-- the call is pcall'd because MarketplaceService throws on a moderated or deleted pass.
function Gamepasses.prompt(player: Player, key: string): boolean
	if not Gamepasses.isConfigured(key) then
		warn(("[Gamepasses] '%s' has no id yet -- prompt suppressed (set Gamepasses.IDS.%s)"):format(key, key))
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, Gamepasses.IDS[key])
	end)
	return ok
end

-- key for a given id, or nil. Lets a receipt/purchase handler name what was just bought without a second table.
-- Checks legacy ids too, so a purchase of a superseded pass still resolves to the perk it grants.
function Gamepasses.keyForId(id: number): string?
	if type(id) ~= "number" or id <= 0 then return nil end
	for key in pairs(Gamepasses.IDS) do
		for _, passId in ipairs(Gamepasses.allIdsFor(key)) do
			if passId == id then return key end
		end
	end
	return nil
end

-- ---- COMBINED LUCK ------------------------------------------------------------------------------------------
-- The one function that decides how lucky a player is, for every roll in the game.
--
-- ⚠ THIS FIXES A STAT THAT DID NOTHING. RebirthSystem.server:99 writes _G.rebirthLuck[player] and its comment
-- says it is "applied in PetSystem's rare roll" -- but NOTHING in the entire repo ever read it, and the rare
-- roll it names was deleted (PetSystem.server:2438 hardcodes `isRare = false`; quest pets are never rare any
-- more). So the Rebirth panel has been advertising "Luck x1.15" for a stat with no effect whatsoever. Routing
-- rebirth luck through here is what finally connects it to the crate rolls, which is where rares now live.
-- WORKS ON BOTH SIDES. On the server it reads _G.rebirthLuck (the authoritative table RebirthSystem writes).
-- On the CLIENT that global does not exist, so it derives the same number from the replicated Rebirths
-- leaderstat -- exactly how CoreClient:319 already derives _G.rebirthSpeedMult. That matters because the crate
-- ODDS PANEL is client-side: without the fallback a rebirthed player would be shown odds lower than the ones
-- the server is really about to roll them at.
--
-- The server is still the only thing that DECIDES a roll. The client copy exists purely to display honestly.
function Gamepasses.luckFor(player: Player): number
	local luck = 1.0

	local rebirth = _G.rebirthLuck
	if type(rebirth) == "table" and type(rebirth[player]) == "number" and rebirth[player] > 0 then
		luck = luck * rebirth[player]                                  -- server: authoritative
	else
		local ls = player:FindFirstChild("leaderstats")                -- client: derive from the replicated stat
		local rb = ls and ls:FindFirstChild("Rebirths")
		local n  = (rb and tonumber(rb.Value)) or 0
		if n > 0 then luck = luck * (1 + Gamepasses.REBIRTH_LUCK_PER * n) end
	end

	if Gamepasses.owns(player, "LuckyPass") then
		luck = luck * Gamepasses.LUCKY_MULT
	end

	return math.clamp(luck, 1.0, Gamepasses.LUCK_MAX)
end

-- Apply a luck value to a weight table, returning a NEW table (never mutates the caller's odds -- the published
-- odds must stay the published odds).
--
-- `order` is lowest-rarity-first. The FIRST band is the "common" one that absorbs the change: every other band
-- is multiplied by `luck`, and because the roll renormalises on the total, the common band's share shrinks by
-- exactly as much as the rest gained. Luck 1.0 returns the weights untouched, bit for bit.
function Gamepasses.applyLuck(weights: { [string]: number }, order: { string }, luck: number): { [string]: number }
	local out = {}
	for rarity, w in pairs(weights) do out[rarity] = w end
	if luck <= 1.0 then return out end

	for i, rarity in ipairs(order) do
		if i > 1 and out[rarity] then
			out[rarity] = out[rarity] * luck
		end
	end
	return out
end

return Gamepasses
