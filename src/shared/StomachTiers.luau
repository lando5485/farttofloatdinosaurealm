--======================================================================
-- StomachTiers.luau  (ModuleScript -> ReplicatedStorage/DinosaurRealm)
--======================================================================
-- THE GUT TIERS, in one place, because the SHOP UI (Bootstrap.client) and the PURCHASE
-- HANDLER (Shop.server) both need them and the server rejects any purchase whose price
-- does not match its own table exactly.
--
-- THIS EXISTS BECAUSE THEY DRIFTED. Bootstrap listed Raptor Gut at 1600 and Shop.server
-- listed it at 112. The panel showed 1600, the player paid 1600, and the server compared
-- 1600 against its own 112, found no match, and returned WITHOUT A WORD -- no error, no
-- refusal message, nothing in the output. Every non-Robux gut in the game was unbuyable
-- and the only symptom was a button that did nothing.
--
-- The prices here are the ones the PLAYER WAS ALWAYS SHOWN (Bootstrap's), not the server's
-- -- those were never seen by anyone and were far too cheap for the current economy: at
-- 112, a gut cost an eighth of a single flight's income.
--
-- SAME RULE AS FlightTuning AND IslandOrder: one table, required by both sides. If you
-- need a price change, change it HERE. A second copy anywhere is the bug above, again.
--======================================================================

local StomachTiers = {}

-- maxPower   -- the tank size, and the ID the purchase is keyed on
-- cost       -- coins, or Robux when robux = true
-- emoji      -- the shop card's icon, and (via EMOJI_BY_MAX) the HUD badge
-- unlockSlot -- the climb slot you must have REACHED before this gut can be bought
-- ONE GUT PER CROSSING -- 12 tiers for 12 crossings, which is the whole point of this table.
--
-- IT USED TO BE SIX, AND THAT IS WHY HALF THE ISLANDS WERE FREE. A gut is the wall that
-- forces saving, so with six guts and twelve crossings exactly six islands had a wall and
-- six did not. The tested run came out 3, 1, 3, 1, 6, 1, 3+ attempts -- alternating
-- perfectly. No amount of spacing changes that ratio: wherever the gaps go, only as many
-- crossings can be walls as there are guts to buy. Twelve guts, twelve walls.
--
-- PRICES ARE 4.25 FLIGHTS OF SURPLUS AT THE TIER BELOW -- this is the "3-5 tries per island"
-- dial, and it is the only thing setting it. Surplus is what one flight nets after buying
-- the food for it (earnings minus fuel), so a gut costing 4.25x that takes ~4 flights to
-- save for, and a flight is 45 s: four flights + the crossing lands each island at 3.0
-- minutes. 3.0x gave 2-3 tries, 5.0x gave 4-6 and drifted; 4.25 is flat 4 nearly everywhere.
--
-- EVERY TANK CARRIES +10, AND NOTHING ELSE MOVED WITH IT. The brief was capacity only: no
-- change to what food costs, what a gut costs, or what a flight earns. So these prices are
-- still the ones derived against the ORIGINAL 100/140/190/... sizes, and so are the band
-- speeds in FlightTuning. The whole cost is ~0.8% of flight margin -- see the note on
-- FlightTuning.TIERS, which carries the full-tank-climb check proving no crossing broke.
--
-- unlockSlot IS THE ANTI-SKIP RULE. Tier k opens the crossing from slot k to slot k+1, so it
-- is bought while STANDING on slot k -- and without a check on that, a player could sit on
-- island 1 farming Eggs and buy the Titan Gut outright, skipping every wall the tiers exist
-- to build. The server enforces it (see BuyStomachEvent in Shop.server); the shop panel just
-- draws the lock. Primal is Robux and deliberately NOT slot-gated -- it is a purchase, not a
-- progression step.
--
-- THE OLD 1600 / 3000 / 5200 / 8000 / 11000 SET DOES NOT SURVIVE THE RETIER -- it was five
-- numbers for five purchases and there are eleven now. It was also mis-shaped: it rose ~7x
-- up the tower while a flight's surplus only doubled, so a gut cost 6.5 flights of saving
-- at the bottom and 21 at the top. These track surplus instead, which is why they only span
-- 3x. Raising one raises that island's try count and nothing else.
--
-- Names and icons on the six NEW tiers are placeholders -- rename freely. Nothing keys off
-- the name except display; the purchase is keyed on maxPower.
StomachTiers.LIST = {
	{ name = "Hatchling Belly", maxPower = 110,  cost = 0,    robux = false, unlockSlot = 1,  emoji = "\xF0\x9F\xA5\x9A" }, -- crossing 1 -> 2
	{ name = "Raptor Gut",      maxPower = 150,  cost = 1250, robux = false, unlockSlot = 2,  emoji = "\xF0\x9F\xA6\x8E" }, -- crossing 2 -> 3
	{ name = "Dilo Stomach",    maxPower = 200,  cost = 1400, robux = false, unlockSlot = 3,  emoji = "\xF0\x9F\x90\x8A" }, -- crossing 3 -> 4
	{ name = "Stego Stomach",   maxPower = 270,  cost = 1550, robux = false, unlockSlot = 4,  emoji = "\xF0\x9F\xA6\xB4" }, -- crossing 4 -> 5
	{ name = "Anky Belly",      maxPower = 365,  cost = 1750, robux = false, unlockSlot = 5,  emoji = "\xF0\x9F\x90\xA2" }, -- crossing 5 -> 6
	{ name = "Trike Gut",       maxPower = 495,  cost = 1950, robux = false, unlockSlot = 6,  emoji = "\xF0\x9F\xA6\x8F" }, -- crossing 6 -> 7
	{ name = "Bronto Belly",    maxPower = 675,  cost = 2200, robux = false, unlockSlot = 7,  emoji = "\xF0\x9F\xA6\x95" }, -- crossing 7 -> 8
	{ name = "Spino Stomach",   maxPower = 920,  cost = 2450, robux = false, unlockSlot = 8,  emoji = "\xF0\x9F\xA6\x88" }, -- crossing 8 -> 9
	{ name = "Rex Gut",         maxPower = 1260, cost = 2750, robux = false, unlockSlot = 9,  emoji = "\xF0\x9F\xA6\x96" }, -- crossing 9 -> 10
	{ name = "Ptero Belly",     maxPower = 1725, cost = 3050, robux = false, unlockSlot = 10, emoji = "\xF0\x9F\xA6\x85" }, -- crossing 10 -> 11
	{ name = "Fossil Gut",      maxPower = 2360, cost = 3450, robux = false, unlockSlot = 11, emoji = "\xF0\x9F\xAA\xA8" }, -- crossing 11 -> 12
	{ name = "Titan Gut",       maxPower = 3230, cost = 3850, robux = false, unlockSlot = 12, emoji = "\xF0\x9F\x8F\x94" }, -- crossing 12 -> 13
	{ name = "Primal Gut",      maxPower = 9999, cost = 499,  robux = true,  unlockSlot = 1,  emoji = "\xF0\x9F\x8C\x8B" },
}

-- Look a tier up by the tank size the client asked for. This is what makes the server
-- authoritative: it takes the maxPower as the request and reads the PRICE off its own
-- table, so a client that sends the wrong cost -- stale, edited or exploited -- cannot
-- change what it pays, and an honest client that disagrees is no longer silently refused.
function StomachTiers.byMaxPower(maxPower: number)
	local target = tonumber(maxPower)
	if not target then return nil end
	for _, tier in ipairs(StomachTiers.LIST) do
		if tier.maxPower == target then return tier end
	end
	return nil
end

-- Has this player reached far enough up the tower to buy this gut?
--
-- The abuse it blocks: every gut is affordable from island 1 given enough grinding, and
-- without this a player could farm the bottom island and buy their way straight to the
-- Titan Gut, walking past every wall the twelve tiers exist to build. Gating on REACH (not
-- on owning the previous tier) means the ladder cannot be skipped but can still be
-- back-filled -- a returning player who somehow owns a small tank high up is not stuck.
--
-- Robux tiers are exempt on purpose: Primal is a purchase, not a progression step.
function StomachTiers.isUnlocked(tier, highestSlot: number?): boolean
	if not tier then return false end
	if tier.robux then return true end
	return (math.floor(tonumber(highestSlot) or 1)) >= (tier.unlockSlot or 1)
end

-- maxPower -> display name, for anything that only has the number (HUD, save data).
StomachTiers.NAME_BY_MAX = {}
for _, tier in ipairs(StomachTiers.LIST) do
	StomachTiers.NAME_BY_MAX[tier.maxPower] = tier.name
end

return StomachTiers
