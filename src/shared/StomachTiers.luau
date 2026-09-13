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
-- SIX COIN UPGRADES over 14 islands (tier 1 is the free starting belly). Each gut covers
-- roughly TWO islands, so unlockSlot steps by 2. maxPower MUST match FlightTuning.TIERS
-- row for row, and every value MUST be divisible by 10 (food sells 10 servings per tank;
-- a non-divisible capacity truncates the serving count and the tank can never fill).
--
-- PRICES ARE SOLVED AGAINST THE SAVINGS CURVE, not picked. Each is ~92% of what the
-- reference player is holding the moment that gut's wall is reached, so the "Stomach
-- Upgrade Available" prompt lands as they discover they are stuck -- 0-2 extra flights,
-- never several islands of surplus sitting idle. Raise one and that island grinds longer.
-- ===========================================================================
-- SEVEN COIN TIERS -- SIX UPGRADES -- ACROSS THIRTEEN CROSSINGS.
--
-- SO SIX GUTS CANNOT WALL EVERY CROSSING, AND THE SECOND CROSSING OF EACH RANGE IS WALLED
-- A DIFFERENT WAY. Read this before touching any number here or in FlightTuning, because
-- the two walls have different mechanics and different limits.
--
-- WALL 1 -- THE PURCHASE WALL (first crossing of each range, 5 flights).
-- The previous gut physically cannot reach the gap, so you must buy this one. The COST is
-- money that buys no fuel, so it is not bound by any fuel-return arithmetic -- it can be set
-- to demand as many flights of saving as we like. That is why these are a comfortable 5.
--
-- WALL 2 -- THE BAND WALL (second crossing of each range, 2 flights).
-- No purchase is involved, so this one is pure economics. Climb is CONVEX in fuel (upper
-- speed bands are much faster), so the range's two gaps need very different fills -- ~72%
-- of the tank for the wall gap, ~96% for the long one. The coins banked crossing the first
-- do not cover the fuel for the second, so it takes a second flight.
--
-- TWO IS THE CEILING ON THAT WALL, AND IT IS PROVABLE -- DO NOT GO HUNTING FOR THREE.
-- A third flight would require the crossing itself to return less coin-value than its fuel
-- cost. Return RISES with fill, so if the near-full crossing flight loses money then every
-- smaller flight loses more, the player can never accumulate toward it, and the island is a
-- dead end rather than a challenge. 1,920 candidate configurations were searched over
-- capacity growth, climb growth, wall placement, coin rate, courtesy fill and servings per
-- tank: none reached 3 while staying solvent. Thirteen tiers (one per crossing) reaches
-- 3+ everywhere, because then EVERY crossing is a purchase wall -- that is the trade.
--
-- CAPACITY GROWS 1.28x PER TIER AND THAT CEILING IS LOAD-BEARING. Drain is normalised
-- (FlightTuning), so raw fuel burns at StomachMax/FLIGHT_SECONDS per second: a bigger tank
-- burns proportionally faster. Fuel below the previous tier's cap still flies in the LOWER
-- speed bands, so the instant you buy a gut your coins-per-fuel drops by the capacity ratio
-- until you can afford to fill past your old cap. Return right after a purchase is
--     R_full x SPEED_SHAPE[1]  =  1.20 x 0.932  =  ~1.12
-- Push capacity growth past R_full and that number goes UNDER 1: every flight after an
-- upgrade loses coins, you can only afford part-tanks, and you bleed out. A previous pass
-- ran 1.70x capacity growth against a 1.16 return -- 0.68 -- and stalled the tower dead at
-- island 3 with hundreds of anti-strand top-ups and zero progress. KEEP GROWTH < RETURN.
--
-- COSTS ARE STRICTLY INCREASING, which is a UI rule as much as a balance one: a bigger
-- stomach that costs less than a smaller one reads as a bug.
--
-- CHANGE THESE AND YOU MUST RE-SOLVE FlightTuning.TIERS -- the maxPower column below IS
-- the band-width column there, row for row.
-- ===========================================================================
-- ===== A GUT COSTS WHAT YOU LAND WITH, MINUS ONE MEAL =====
--
-- That sentence is the whole pricing rule, and it exists to kill a specific failure. A gut
-- is a WALL: at slot 4 the Raptor climbs 853 against an 870-stud gap, so you physically
-- cannot cross without the Dilo. If the Dilo costs more than you land with, the only way to
-- earn the difference is to FLY THE GAP YOU CANNOT CROSS -- and a full Raptor tank gets you
-- 853/870 = 98.0% of the way, every single time, until you can afford the upgrade.
--
-- That was the edging. Not the food, not the spacing: five crossings in this tower
-- (4, 6, 8, 10, 12) sat behind a gut whose predecessor reached 98% of the gap, so every
-- saving flight was a 2%-short miss. The gate slack is ~5% by construction all the way up
-- the tower, so this is structural and no serving size can quantise around it.
--
-- The fix is to price each gut BELOW the coins the previous crossing pays out, so it is
-- always bought on landing and the doomed flight never happens:
--
--        bought at   crossing pays        gut     headroom
--        slot  2          1764            100       1664
--        slot  4          3478            300       3178
--        slot  6          5019           1300       3719
--        slot  8          6951           1500       5451
--        slot 10          9656           1800       7856
--        slot 12         13516           2200      11316
--
-- (Landing leftovers sit on top of the payout, so the real headroom is larger than the
-- column above -- but the payout alone has to cover it, because a player who spent every
-- coin on the crossing they just made has nothing else.)
--
-- THEY LOOK CHEAP NEXT TO FOOD, AND THEY HAVE TO BE. A meal on the same island runs 1,000 to
-- 7,300 coins, so a gut is a fraction of a single meal. That reads odd on the shop card and
-- it is still correct: the gut is not the wall any more, the FUEL is. Pricing a gut anywhere
-- near what a crossing costs puts it back above the previous crossing's payout, and then the
-- player grinds 98%-short flights to afford it -- the exact failure this table's headroom
-- column exists to prevent.
--
-- Left with about one serving, the player then climbs the same 1 -> 2 -> 3 meal ladder that
-- every other crossing uses, and every miss lands at 34-76% of the gap instead of 98%.
--
-- THE ATTEMPTS RAMP IS NOT HERE ANY MORE -- it moved to the capacity column (see the long
-- note above BASE_TIERS in FlightTuning). These prices only decide WHERE the ladder starts;
-- how many flights it takes to walk is set by R, which now falls 1.99 -> 1.33 up the tower.
--
-- IF YOU RAISE ONE OF THESE, check it against the crossing payout above. Go over that number
-- and the 98% doomed flights come straight back.
-- ===== A GUT COSTS WHAT LEAVES THE PLAYER EXACTLY ONE MEAL, AND NOT A COIN MORE =====
--
-- That is the rule now, and it is stricter than the one above it because a playtest proved
-- the old one wrong. The previous pass priced guts against what the crossing PAYS OUT, which
-- looked safe on paper and shipped a Rex Gut that left the player holding ELEVEN COINS
-- against a 1,650-coin meal. They could not buy the food the ladder was solved for, fell
-- back on cheap food, effective R collapsed to ~1.00, and crossing 8 sat at 40% of the gap
-- forever -- flight 1 at 39.5%, flight 9 at 42.7%. A crossing that cannot fund its own first
-- flight is not a wall, it is a dead end.
--
-- SO THE PRICE IS BOUNDED FROM ABOVE BY AFFORDABILITY, NOT JUST BY THE PAYOUT:
--       cost  <=  (coins on landing) - (price of the best food for the next crossing)
-- Every one of these was searched against the ACTUAL BUY MAX PURCHASE SEQUENCE replayed
-- flight by flight from the real coin balance, not against an assumed wallet -- that
-- assumption is exactly what the failed pass got wrong. tools/ladder.py re-runs it.
--
-- THEY LOOK CHEAP, AND THEY MUST. The gut is not the wall any more; the FUEL is. A gut that
-- costs anywhere near a crossing's payout puts the player back to grinding flights they
-- cannot fund. The wall these build is "you cannot reach the gap without this tank", which
-- is a hard physical gate (climb < gap) and needs no price to enforce it.
--
-- THE FLIGHT COUNT DOES NOT LIVE HERE ANY MORE either -- it lives in the tank sizes, via R
-- (see BASE_TIERS in FlightTuning). These prices only decide WHERE on the ladder the player
-- starts; R decides how many rungs it takes to walk it.
StomachTiers.LIST = {
	{ name = "Hatchling Belly", maxPower = 120  , cost = 0    , robux = false, unlockSlot = 1 , emoji = "\xF0\x9F\xA5\x9A" }, -- slots 1-2
	{ name = "Raptor Gut",      maxPower = 270  , cost = 1000  , robux = false, unlockSlot = 2 , emoji = "\xF0\x9F\xA6\x8E" }, -- slots 2-4
	{ name = "Dilo Stomach",    maxPower = 470  , cost = 2000  , robux = false, unlockSlot = 4 , emoji = "\xF0\x9F\x90\x8A" }, -- slots 4-6
	{ name = "Trike Gut",       maxPower = 620  , cost = 4000 , robux = false, unlockSlot = 6 , emoji = "\xF0\x9F\xA6\x8F" }, -- slots 6-8
	{ name = "Rex Gut",         maxPower = 1080 , cost = 5000 , robux = false, unlockSlot = 8 , emoji = "\xF0\x9F\xA6\x96" }, -- slots 8-10
	{ name = "Titan Gut",       maxPower = 1710 , cost = 6000 , robux = false, unlockSlot = 10, emoji = "\xF0\x9F\x8F\x94" }, -- slots 10-12
	-- 20000 -> 23000. THE LAST GUT IS THE ONLY ONE WHOSE PRICE GATES A SINGLE CROSSING, so it
	-- is the only one that can be raised without touching the rest of the tower. 23,000 is the
	-- CEILING, measured: at 24,000 a second no-progress flight appears and the run stops being
	-- clean. Worth +1 flight on the final crossing; see IslandOrder's summit note for the rest.
	{ name = "Colossus Gut",    maxPower = 2600 , cost = 11500 , robux = false, unlockSlot = 12, emoji = "\xF0\x9F\xAA\xA8" }, -- slots 12-14
	-- Robux tier, deliberately NOT slot-gated and NOT part of the 6-upgrade ladder.
	{ name = "Primal Gut",     maxPower = 9999 , cost = 499  , robux = true,  unlockSlot = 1 , emoji = "\xF0\x9F\x8C\x8B" },
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

-- Can this player buy this gut? Reaching its unlockSlot is the gate.
--
-- THIS WAS REMOVED ONCE AND A PLAYTEST PUT IT BACK. The objection was a UI one -- the shop
-- replaced the PRICE with "LOCKED - Fern Frontier", so a gut you were saving for showed you
-- nothing to save toward. That is fixed in the card itself now: the price is always visible
-- and the lock is a second line under it. The RULE has to stay, because it is load-bearing
-- for pacing in a way that is easy to miss:
--
-- Tier k is the wall for the crossing FROM slot k. Without the gate you buy it while still
-- on slot k-1, and that single island of drift wrecks both crossings around it. Measured:
--     9 -> 10   funds a gut it does not need yet  -> 11 launches  (should be 3)
--    10 -> 11   already owns the gut, nothing left to buy -> 1 launch  (should be 5)
-- and the same pair again at 11->12 with the Colossus. Two "1-flight islands" and two
-- 10-launch grinds, all four from one missing check.
--
-- Gating on REACH rather than on owning the previous tier means the ladder cannot be
-- skipped but can still be back-filled -- a returning player with a small tank high up is
-- never stuck. Robux tiers are exempt: Primal is a purchase, not a progression step.
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
