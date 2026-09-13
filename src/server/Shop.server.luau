--======================================================================
-- Shop_AllInOne.server.lua  (Server Script)
--======================================================================
-- The SERVER half of the shop, copied VERBATIM from PlayerStats.server.lua:
-- the food-buy + stomach-upgrade handlers, the foods + stomachTiers data, and
-- the exact validation rules. This is what the shop CLIENT (Shop_AllInOne.client
-- / ShopClient) talks to via the remotes.
--
-- It's self-contained: it creates the remotes, sets up the leaderstats stats the
-- handlers read (Coins / CurrentPower / StomachMax / TotalFartPower /
-- TotalCoinsEarned), and copies the BuyFood + BuyStomach logic 1:1. Drop into
-- ServerScriptService. (Robux products -- 2x pass, Meteorite Explosion, etc. -- go through
-- MarketplaceService.ProcessReceipt in the real game; that lives elsewhere and is
-- noted at the bottom, not duplicated here.)
--
-- KEY RULES (verbatim):
--   * COINS are checked FIRST (the common blocker) -> "not_enough_coins".
--   * Then stomach capacity: TRULY full -> "stomach_full", else has room but the
--     food won't fit -> "not_enough_room". Stomach-full uses `>` (a buy landing
--     EXACTLY on the max is allowed), and coins are NOT deducted when full.
--   * Stomach upgrade validates the (maxPower, cost) pair against a real,
--     non-Robux tier and carries the current power over (only the max grows).
--======================================================================

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

-- shared tower order: island MODEL number -> climb slot, for the food unlock gate
local IslandOrder  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
-- the flight pacing the tank is filled against -- shared with BottomHUD.client so the
-- shop can never sell a tank that does not reach
local FlightTuning = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("FlightTuning"))
local StomachTiers = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers"))
local FoodMenu     = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("FoodMenu"))

-- ===== remotes (created if missing) =====
local function ev(name) local e = RS:FindFirstChild(name); if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end; return e end
local BuyFoodEvent      = ev("BuyFoodEvent")       -- c->s: (foodName)
local BuyStomachEvent   = ev("BuyStomachEvent")    -- c->s: (newMax, cost)
local StomachFullEvent  = ev("StomachFullEvent")   -- s->c: (reason) "not_enough_coins"/"stomach_full"/"not_enough_room"
local StomachUpdateEvent= ev("StomachUpdateEvent") -- s->c: (newMax, tierName)
local RegenEvent        = ev("RegenEvent")         -- s->c: (powerAdded, currentPower, stomachMax)
local CoinEvent         = ev("CoinEvent")          -- c->s: (amount) -- coins earned during flight
local BurnFuelEvent     = ev("BurnFuelEvent")      -- c->s: (remainingPower) -- flight drained the tank
-- created (never fired here) so the shop client's WaitForChild()s return INSTANTLY instead of blocking
-- it for 30s/10s (this game has no food stands, and gamepass state is provided via _G.playerGamepasses)
ev("StandsReadyEvent")
ev("GamepassEvent")

-- ============================================================================
-- DATA (VERBATIM from PlayerStats.server.lua) -- the client mirrors this exactly.
-- ============================================================================
-- NOTE: the `-- Name` comments here USED TO follow an old 14-island design that
-- disagreed with the real island numbering (it had Fossil Frontier at 5, Volcanic
-- Vista at 9, etc). The quests are wired to the numbering in Bootstrap's ISLANDS
-- table, so that is the source of truth -- the names below now match it.
-- Prices / power are UNTOUCHED (balance), only the comments were corrected.
-- Power and price are keyed to the island's CLIMB SLOT, not its model number.
-- The names stay put (Eggs are still Nesting Nook's), but the numbers now follow
-- the tower order from IslandOrder.SLOT_TO_ISLAND = {1,9,5,12,3,13,4,2,10,7,6,8,11}.
--
-- Before this, `foods` was keyed by model number while the tower reorders the
-- islands, so along the actual route power ran 8 -> 300 -> 25 -> 540 -> 45 -> 640...
-- and Chili Peppers, Grapes and Popcorn each unlocked on a slot where the player's
-- tank was too small to hold one serving -- the buy was rejected outright.
--
-- PRICES ARE DERIVED, AND THIS IS THE DIAL THAT SETS "HOW MANY TRIES PER ISLAND".
--
-- You cannot cross on a part-full tank -- running dry drops you back to the island you
-- launched from (nothing in the gap to land on). So an "attempt" is: buy what you can
-- AFFORD, fly until dry, bank the climb coins, fall, buy more. Attempts stop when you
-- can finally afford a FULL tank. That makes the whole thing geometric: each attempt
-- multiplies your coins by
--       R = (coins a full flight earns) / (coins a full refill costs)
-- and the number of attempts is log(fullTankCost / startingCoins) / log(R).
--
-- R WAS NOT CONSTANT and nobody had checked: with the old prices it ran 4.5x at Eggs
-- down to 1.8x at Steak. At 4.5x one partial flight paid for a full tank outright, so
-- island 1 was over in two attempts however long the flight was -- retuning
-- FLIGHT_SECONDS could never have fixed that, because coins are billed per STUD, not
-- per second, and the studs did not change.
--
-- Every row below is now solved for a FLAT R = 1.91:
--       price = gap * MARGIN * COIN_PER_STUD / (R * (tierMaxPower / power))
-- which puts the opening island at 3 attempts and holds that shape up the tower. R must
-- stay ABOVE 1 at every row or a flight costs more than it earns and the player spirals
-- down -- that, not the price, is the number to protect when editing.
--
-- R > 1 IS ALSO WHY PRICES CANNOT SET THE TRY COUNT. Earning more than your fuel is the
-- same statement as always landing able to afford the next full tank, which is the same
-- statement as crossing in one pass. So a solvent economy gives one-pass islands by
-- construction, and the ONLY thing that can make an island take several tries is a WALL:
-- a gut you cannot yet afford. That is what StomachTiers.LIST is for, and why there is now
-- one gut per crossing instead of one per two. Do not try to buy try-count with prices.
--
-- COIN_PER_STUD (0.14, in BottomHUD) is the other half of R. Change one, re-solve both.
--
-- THE TABLE ITSELF MOVED OUT, same as the gut tiers did and for the same reason: this list
-- was also typed out in ShopGlue.client, the two drifted (Eggs 21 here vs 16 there, Steak
-- 185 vs 150), and the stand was quoting one price while the server charged another.
-- Re-solved for the TWELVE-TIER tower -- the tank sizes moved (100/182/520/1075/2146/3218
-- became twelve steps of 100..3220) and so did every gap, and both are in the formula, so
-- the old prices against the new tanks would have put R anywhere from 1.2 to 3.4.
-- Per-SERVING buy logging. Off: the client fires one BuyFood per serving, so this was
-- 24 lines per full tank. Flip on only to debug the purchase remote itself.
local VERBOSE_BUY = false

local foods = FoodMenu.LIST
-- Titan Gut is the top of the free path; Primal is a Robux-only premium gut. (The line that
-- used to be here described a getMaxHeight() from the source game and a tier called "Iron" --
-- neither exists in this one. Reach is FlightTuning.fullTankClimb now.)
--
-- THE TIER TABLE MOVED OUT. It used to be duplicated here and in Bootstrap.client, the two
-- drifted (112 here vs 1600 in the shop panel), and because the handler below demanded an
-- exact price match, every free gut in the game silently stopped being buyable. Both sides
-- now read the shared module -- see the note at the top of StomachTiers.luau.
--
-- There are TWELVE tiers there now, not six -- one per crossing, because a gut is the only
-- thing that can make an island take more than one try (see the R > 1 note above) and six
-- guts across twelve crossings left every other island free. Prices are 1250..3850, each
-- ~4.25 flights of saving at the tier below it -- unchanged by the +10 capacity bump, which
-- was asked for as capacity only.
local stomachTiers = StomachTiers.LIST
-- expose for the client (the real game sets these in CoreClient; harmless if already set)
_G.foods = _G.foods or foods
_G.stomachTiers = _G.stomachTiers or stomachTiers

-- ===== config flags the handlers read (VERBATIM values) =====
local POWER_PASS_MULT = 1.4   -- the 2x-power pass multiplier (food power + tank both scale by this when owned)
local DISABLE_2X = false      -- 2x boost ENABLED (also in Studio for testing)
local DISABLE_PERKS_FOR_BALANCE = false -- [BALANCE] force normal 1x power everywhere
local FORCE_NO_2X = false     -- 2x respected (owned via the gamepass / 1-hour product)
local TEST_FULL_DATA = false  -- [TEST] free switch to any tier (ignore cost+coins) to sample every tier's reach

-- balance-logging tables the handlers touch (kept so the copy is 1:1)
local coinsSpentOnFood, coinsSpentOnGuts = {}, {}
local gutPurchases, highestIslandReached, sessionStartTime, flightsOfSaving, sessionFlights = {}, {}, {}, {}, {}
local playerCoinAccum = {}

-- ============================================================================
-- LEADERSTATS setup (the handlers read these stats; the real game builds them
-- in PlayerStats). Created here so the shop runs standalone.
-- ============================================================================
local function setupStats(player)
	if player:FindFirstChild("leaderstats") then return end
	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local function num(name, v) local n = Instance.new("IntValue"); n.Name = name; n.Value = v; n.Parent = ls; return n end
	-- 500 = ONE EGG AND CHANGE. This one number sets the shape of the whole opening crossing,
	-- because a player spends everything they have on food every time they land, and the
	-- opening is the only crossing with no income history behind it.
	--
	-- IT IS SET AGAINST THE MEAL SIZE, NOT PICKED. Eggs are 320 coins for 32 power, and
	-- crossing 1 takes THREE of them (FoodMenu's rule for every crossing in the tower):
	--     1 x 320 =  320  -> 32 power, 27% tank,  34% of the gap
	--     2 x 320 =  640  -> 64 power, 53% tank,  70% of the gap   <- the last miss
	--     3 x 320 =  960  -> 96 power, 80% tank, 135% of the gap   <- clears, comfortably
	-- 500 buys exactly one, and the ladder walks itself from there: the first flight banks
	-- 622 coins, which with the 180 left over affords two meals but not three; the second
	-- banks 1276, which affords the rest. Three flights, and the same three whether or not
	-- the player pops a single coin bubble -- the window is ~200 coins wide at each rung.
	--
	-- The bank has to sit in [320, 639]:
	--     >= 640 -> the opening starts at two meals and finishes in TWO flights. 900 used to
	--         buy the crossing outright, which is why island 2 fell on the first try.
	--      < 320 -> cannot afford a meal at all, so the anti-strand floor hands one over and
	--         the number stops meaning anything.
	--
	-- Retune this against ladder.py, not by feel, and re-check it whenever FoodMenu row 1
	-- moves: the window above is defined entirely by that row's price.
	num("Coins", 2000)             -- starting coins
	num("CurrentPower", 0)       -- current fart fuel in the tank
	-- 120 = StomachTiers.LIST[1].maxPower (Hatchling Belly). It is FIVE servings of Eggs
	-- (24 power each) exactly -- every tank in the game is exactly five servings of its
	-- island's food, so a tank always fills without truncation. Keep it in step with
	-- StomachTiers.LIST[1] or a new player starts on a tank that matches no tier.
	-- Five, not twenty: see the note at the top of FoodMenu for why the serving size is
	-- the only thing that decides how far short the last failed attempt falls.
	num("StomachMax", 120)       -- tank size = Hatchling Belly
	num("TotalFartPower", 0)     -- cosmetic lifetime counter
	num("TotalCoinsEarned", 0)
	num("Island", 1)
end
Players.PlayerAdded:Connect(setupStats)
for _, p in ipairs(Players:GetPlayers()) do setupStats(p) end

-- ============================================================================
-- COINS EARNED WHILE FLYING (VERBATIM from PlayerStats.server.lua)
-- ============================================================================
-- The client sends FRACTIONAL amounts every 0.5s of thrust. Accumulate them and
-- only ever move whole coins into the stats, keeping the remainder for next tick --
-- otherwise every sub-1.0 payout would floor to 0 and low flights would earn nothing.
CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0
	if amt <= 0 or amt ~= amt then return end       -- reject non-numbers, negatives and NaN
	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerCoinAccum[player] = nil
	coinsSpentOnFood[player], coinsSpentOnGuts[player] = nil, nil
end)

-- ============================================================================
-- FUEL BURNED WHILE FLYING. The flight loop drains gas CLIENT-side only, so the
-- server's CurrentPower used to only ever RISE (BuyFood) -- once it reached
-- StomachMax, every food stand showed FULL / NO ROOM forever, even after long
-- flights emptied the real tank. The client now reports its remaining fuel; the
-- server adopts it ONLY DOWNWARD (a burn can never refill the tank), so this is
-- no more spoofable than the client-side drain it mirrors.
-- ============================================================================
-- ANTI-STRAND TOP-UP. Run when a flight ends with the tank at zero.
--
-- Space Realm has no equivalent, and does not need one: there, each planet's TASK
-- pays out exactly the next stomach's cost ("cost = the coins the Mercury task pays
-- out" -- StomachTiers.luau), so the funding is baked into the reward table. This
-- tower earns coins from CLIMB HEIGHT instead, which is variable -- a short flight
-- can land you with less than one serving of the local food costs, and then there is
-- no way back up. This closes that hole: it prices the food you are standing next to
-- against the fuel the next crossing needs and grants only the SHORTFALL.
--
-- It grants coins, never fuel, so the player still walks to the stand and buys --
-- the loop is intact, it just cannot dead-end.
--
-- IT USED TO FUND THE WHOLE CROSSING (powerShortfall = fill to what the gap needs),
-- which quietly capped every island at two attempts: fail once, get topped up to full,
-- succeed. That defeated the point of the price curve.
--
-- IT THEN FUNDED A QUARTER TANK, on the reasoning that "R > 1 at every row of `foods`,
-- so any flight banks more coins than the fuel it burned." THAT REASONING IS FALSE and
-- it is what this constant exists to correct. R is not a property of the food row, it is
-- a property of the food row AND HOW FULL THE TANK IS:
--
--     coins earned = climb(M, p) * COIN_PER_STUD,  climb(M, p) = (FLIGHT_SECONDS / M) * S(p)
--
-- The drain is NORMALISED (see FlightTuning): a full tank always burns in FLIGHT_SECONDS
-- regardless of size, so raw fuel drains at M / FLIGHT_SECONDS per second -- a bigger tank
-- burns proportionally faster. Fuel below a given band's cap flies at that band's speed on
-- EVERY gut, because the bands are absolute, not a fraction of the tank. So a part-full big
-- tank pays more fuel for the same distance. Measured R by fill, on the shipped tables:
--
--     gut   food      25%    50%    75%   100%   break-even
--     120   20/10    1.63   1.63   1.63   1.63      10%
--     144   24/12    1.36   1.36   1.36   1.57      10%
--     168   27/14    1.21   1.21   1.26   1.62      10%
--     192   30/16    1.09   1.09   1.26   1.70      10%
--     228   35/19    0.93   0.93   1.28   1.69      60%
--     264   40/22    0.81   0.89   1.31   1.71      60%
--     360   54/30    0.60   0.88   1.30   1.71      60%
--     492   73/41    0.46   0.88   1.30   1.70      60%
--     780  113/65    0.46   0.89   1.29   1.71      60%
--
-- A flight under ~60% full still LOSES money on the upper guts. A quarter tank sits deep in
-- that loss region, so the old floor did not break the death spiral -- it fed it: the player
-- was topped back up to another LOSING quarter tank, launched, lost coins, and was topped up
-- again, forever. Against the previous tables (capacities growing 1.70x per tier, so
-- break-even sat at 80-90%) that was an unbounded stall at island 3 -- hundreds of top-ups,
-- zero progress. Capacity growth is now 1.16x, well under the 1.70 full-tank return, which
-- is what pulls break-even down to 60% and keeps a fresh gut solvent on its first launch.
--
-- 0.50 IS ABOVE THE BREAK-EVEN LINE FOR EVERY ROW, which is the entire requirement: the
-- granted flight must at least pay for its own fuel, or the grant just funds the next loss.
-- On the CURRENT tables break-even is 1 serving out of 12 on the lower guts and 5 of 12 on
-- the upper ones -- 42% at worst -- so half a tank clears it everywhere with margin.
--
-- IT WAS 0.85, sized for a far harsher set of tables (capacity grew 1.70x per tier against
-- a 1.16 return, which put break-even at 80-90% and stalled the tower outright). Capacity
-- growth is 1.28x against a 2.20 return now, so the loss region has nearly vanished and
-- 0.85 was handing over most of a tank for nothing. Re-derive this from the break-even
-- table above whenever the tiers move; do not carry the old number forward on faith.
--
-- THERE IS NO FILL FRACTION ANY MORE. The grant is exactly ONE MEAL, read off the food sold
-- where the player is standing -- see the function below, and FoodMenu's header for why one
-- and not two. The old ANTI_STRAND_FILL = 0.50 constant is gone with it: half a tank rounded
-- UP to two meals at most slots, which handed over the middle rung of every three-rung ladder
-- in the tower. One meal is a quarter to a third of a tank depending on the slot, and the
-- lightest crossing in the game needs 71.9%, so the floor cannot hand anybody a crossing.
local function ensureCanRefuel(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local cp    = ls:FindFirstChild("CurrentPower")
	local sm    = ls:FindFirstChild("StomachMax")
	if not (coins and cp and sm) or sm.Value <= 0 then return end

	-- The food sold where they are standing. `foods` is keyed by CLIMB SLOT, and
	-- HighestSlot is the climb position -- see the note on the foods table.
	local slot = math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, #foods)
	local food = foods[slot]
	if not food or food.power <= 0 then return end

	-- THE DEAD-END TEST, AND IT IS THE ONLY TRIGGER: can they buy even ONE serving?
	--
	-- WITHOUT THIS LINE THIS FUNCTION IS A COIN FAUCET, and a playtest log caught it doing
	-- exactly that. The rule below tops the player up to ANTI_STRAND_FILL of a tank, and it
	-- ran on EVERY dry landing -- so a player who had 74 coins, could comfortably afford
	-- three Eggs and fly again, was still handed 146 coins for free because 74 was short of
	-- a 220-coin 85% tank. Repeat that after every failed attempt and the player is never
	-- short of anything: the crossings stop being paced by earning and the flight counts
	-- collapse. Landing dry is the NORMAL failure case this whole progression is built on;
	-- it is not the emergency.
	--
	-- The emergency is being unable to launch AT ALL -- no fuel, and not one serving's worth
	-- of coins. That is the dead end with no way out, and it is the only thing worth paying
	-- for. Above that line the player can always fly, and every flight returns more than its
	-- fuel cost (see the table above), so they climb out under their own power.
	if coins.Value >= food.price then return end
	-- EXACTLY ONE MEAL, NEVER TWO, AND THAT IS THE WHOLE RULE.
	--
	-- Every crossing in this tower is three meals (see FoodMenu's header), so one meal is
	-- precisely "enough to launch, nowhere near enough to cross" -- a floor, not a leg-up.
	-- Two would hand over the middle rung of a three-rung ladder and quietly delete an
	-- attempt from every crossing the player ever gets stuck on.
	--
	-- It used to grant up to ANTI_STRAND_FILL (50%) of a tank, which rounded UP to two meals
	-- at most slots and did exactly that. The fill fraction is kept below only so the log
	-- line and BalanceDebug can still report what fraction of a tank one meal comes to.
	local servings = 1
	if cp.Value + food.power > sm.Value then
		-- No room for a whole meal. The shop tops off and clamps in that case (see BuyFood),
		-- so this is still a launchable flight -- but if the tank is genuinely full there is
		-- nothing to grant and nothing stranding them.
		if sm.Value - cp.Value <= 0 then return end
	end

	local needCoins = servings * food.price
	if coins.Value >= needCoins then return end      -- they can already afford it
	local grant = needCoins - coins.Value
	coins.Value = coins.Value + grant
	print(("[Shop] anti-strand: %s landed dry on slot %d with %d coins, needs %d for %d x %s (%.0f%% of tank -- a crossing is 3) -> granted %d")
		:format(player.Name, slot, coins.Value - grant, needCoins, servings, food.name,
			food.power / math.max(1, sm.Value) * 100, grant))
end

BurnFuelEvent.OnServerEvent:Connect(function(player, remaining)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower"); if not cp then return end
	local r = tonumber(remaining)
	if not r or r ~= r then return end               -- reject non-numbers and NaN
	r = math.floor(math.clamp(r, 0, cp.Value))       -- fuel only ever burns DOWN
	if r < cp.Value then cp.Value = r end
	if r <= 0 then ensureCanRefuel(player) end       -- landed dry -> make sure they can buy their way back up
end)

-- ============================================================================
-- BUY FOOD (VERBATIM)
-- ============================================================================
BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	-- WAS AN UNCONDITIONAL PRINT, AND IT FIRED PER SERVING. The client sends one BuyFood
	-- per serving, so filling a 12-serving tank produced 12 of these plus 12 "BOUGHT:"
	-- lines -- 24 lines for one shop visit, repeated every launch. That is what buried the
	-- progression telemetry in the playtest logs. The per-launch summary the tuning
	-- actually needs is PROGDATA in BottomHUD.client (F7); this is per-serving plumbing.
	if VERBOSE_BUY then print("SERVER RECEIVED BUY:", player.Name, foodName) end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local coins        = stats:FindFirstChild("Coins")
	local totalPower   = stats:FindFirstChild("TotalFartPower")
	local totalEarned  = stats:FindFirstChild("TotalCoinsEarned")
	local currentPower = stats:FindFirstChild("CurrentPower")
	local stomachMax   = stats:FindFirstChild("StomachMax")
	if not coins or not totalPower then return end
	local food = nil
	for _, f in ipairs(foods) do
		if f.name == foodName then food = f; break end
	end
	if not food then
		print("FOOD NOT FOUND:", foodName)
		return
	end
	-- FAILURE CHECK 0 (ISLAND LOCK): a food only unlocks once you have REACHED its island.
	-- Gated on HighestSlot (climb position) because the tower scrambles model numbers against
	-- climb order -- island9 is the SECOND island you reach, island5 is the third. Enforced
	-- here as well as in the shop UI: the client greying a cell is cosmetic, this is the rule.
	local reached = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	local foodSlot = IslandOrder.ISLAND_TO_SLOT[food.island]
	if foodSlot and foodSlot > reached then
		print(("FOOD LOCKED: %s tried %s (slot %d) but has only reached slot %d")
			:format(player.Name, foodName, foodSlot, reached))
		pcall(function() StomachFullEvent:FireClient(player, "food_locked") end)
		return
	end
	-- NO LOCAL-STAND RULE. Any UNLOCKED food is buyable from any stand, deliberately -- the shop is
	-- an open-choice system and mixing foods is a player decision, not an exploit. A stand-lock was
	-- tried here and removed; if you are reading this because the ladder is smooth again, the answer
	-- is the BUY MAX rule and the efficiency curve, not a restriction. See FoodMenu's header.
	-- FAILURE CHECK 1 (COINS FIRST -- the common blocker): not enough coins -> "not_enough_coins".
	if coins.Value < food.price then
		print("NOT ENOUGH COINS:", player.Name, coins.Value, "<", food.price)
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end) -- specific reason for the client
		return
	end
	if not currentPower or not stomachMax then return end
	-- 2x Fart Power pass (forever) OR an active 1-hour product both grant the real power boost.
	local has2x = player:GetAttribute("HasTwoXForever") or
		(player:GetAttribute("TwoXHourExpiry") and player:GetAttribute("TwoXHourExpiry") > os.time())
	if DISABLE_2X and RunService:IsStudio() then has2x = false end -- [TESTING] no 2x boost in Studio
	if DISABLE_PERKS_FOR_BALANCE then has2x = false end -- [BALANCE] force normal 1x power
	if FORCE_NO_2X then has2x = false end -- [NOSAVE TEST] 2x forced un-owned. REMOVE BEFORE LAUNCH.
	-- With the pass, food adds POWER_PASS_MULT x its power to ACTUAL flight fuel, and the
	-- effective tank grows to stomachMax * POWER_PASS_MULT (so the player flies higher).
	local powerGain   = has2x and math.floor(food.power * POWER_PASS_MULT) or food.power
	local effectiveMax = has2x and math.floor(stomachMax.Value * POWER_PASS_MULT) or stomachMax.Value
	local newPower = currentPower.Value + powerGain
	-- FAILURE CHECK 2 (only reached when coins are sufficient): does it fit the REMAINING stomach space?
	--
	-- TRULY FULL is still a refusal. A LAST SERVING THAT OVERFLOWS IS NOT -- it tops the tank
	-- off and clamps, at full price. That used to be refused outright ("not_enough_room"),
	-- and refusing it is what was quietly manufacturing the near-misses this progression
	-- keeps being accused of.
	--
	-- Here is the mechanism. You keep whatever fuel you land with, so you arrive at the next
	-- island holding a few percent of a tank -- never a whole number of servings. The tank
	-- then fits one FEWER serving than it holds: land on slot 2 with 7 power, buy Raptor
	-- servings of 36 into a 180 tank, and floor((180-7)/36) = 4, so you launch on 151/180 =
	-- 84.1% when the crossing needs 84.3%. Short by a fifth of a percent, with the coins to
	-- cover it sitting in your pocket and the shop refusing to take them. Across the tower
	-- that artefact was worth five crossings that ended in a 95-98% miss.
	--
	-- IT CANNOT BE FARMED, because the overflow is charged in full: the top-off is the worst
	-- value in the game, not the best, and it only exists at all when the tank is within one
	-- serving of full. The next buy after it sees remaining <= 0 and refuses as before, so
	-- the client's fill-up loop still terminates on "stomach_full".
	if newPower > effectiveMax then
		local remaining = effectiveMax - currentPower.Value
		if remaining <= 0 then
			print("STOMACH FULL:", player.Name, currentPower.Value, "/", effectiveMax, "(no room at all)")
			pcall(function() StomachFullEvent:FireClient(player, "stomach_full") end)    -- truly full
			return
		end
		-- has room, but not a whole serving's worth -> top off and clamp
		powerGain = remaining
		newPower  = effectiveMax
	end
	coins.Value = coins.Value - food.price
	coinsSpentOnFood[player] = (coinsSpentOnFood[player] or 0) + food.price -- [BALANCE LOGGING] track food spend
	currentPower.Value = newPower
	-- Cosmetic TotalFartPower counter: unchanged -- still doubles with the pass as before.
	local bonusPower = has2x and food.power or 0
	totalPower.Value = totalPower.Value + food.power + bonusPower
	if totalEarned then totalEarned.Value = totalEarned.Value + food.price end
	-- The float text reads the FIRST argument. Send the smaller of the listed power and what
	-- actually went in, so a clamped top-off does not announce "+36" after adding 29 -- the
	-- 2x pass case is unaffected, since powerGain is larger there and food.power still wins.
	pcall(function() RegenEvent:FireClient(player, math.min(food.power, powerGain), currentPower.Value, stomachMax.Value) end)
	if VERBOSE_BUY then print("BOUGHT:", player.Name, foodName, "+", food.power, "power, total:", currentPower.Value) end
	-- PET XP (cosmetic-only): eating food = "collecting gas" -> XP for the equipped pet.
	if _G.petOnGas then _G.petOnGas(player, powerGain) end
end)

-- ============================================================================
-- BUY STOMACH (coin tiers) (VERBATIM)
-- ============================================================================
BuyStomachEvent.OnServerEvent:Connect(function(player, newMax, cost)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local stomachMaxStat = ls:FindFirstChild("StomachMax")
	if not coins or not stomachMaxStat then return end
	local newMaxN = tonumber(newMax) or 0
	local costN   = tonumber(cost)   or 0
	-- [TEST] TEST_FULL_DATA: free switch to ANY real tier (ignore cost + coins) so every tier's reach can be sampled.
	if TEST_FULL_DATA then
		if newMaxN <= 0 then return end
		local ok = false
		for _, tier in ipairs(stomachTiers) do if tier.maxPower == newMaxN then ok = true; break end end
		if not ok then return end
		stomachMaxStat.Value = newMaxN
		local cp = ls:FindFirstChild("CurrentPower"); local carried = 0
		if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end
		pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
		local nameStr = "Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == newMaxN then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, nameStr) end)
		print("TEST_FULL_DATA: "..player.Name.." switched to "..nameStr.." (maxPower "..newMaxN..") for FREE")
		return
	end
	if newMaxN <= 0 then return end
	-- THE PRICE IS THE SERVER'S, NOT THE CLIENT'S.
	--
	-- This used to require `tier.cost == costN` -- the client had to send a price matching
	-- the server's table exactly, or the purchase was dropped with no message at all. The
	-- two tables drifted (panel said 1600, server said 112) and every non-Robux gut in the
	-- game quietly became unbuyable: the button worked, the coins were there, and nothing
	-- happened. Both sides now read ReplicatedStorage.DinosaurRealm.StomachTiers, so they
	-- cannot disagree -- and even if a client sends a wrong `cost`, it is IGNORED and the
	-- server charges its own. `cost` stays in the signature only so old clients still fire.
	local tier = StomachTiers.byMaxPower(newMaxN)
	if not tier or tier.robux then return end
	costN = tier.cost
	if costN <= 0 then return end
	-- STRICT UPGRADE ONLY. Without this a client could "buy" a cheaper tier it can
	-- afford and shrink its own tank.
	if newMaxN <= stomachMaxStat.Value then return end
	-- YOU MUST HAVE REACHED THE ISLAND THE GUT IS FOR.
	--
	-- Tier k opens the crossing from slot k to slot k+1, so it belongs to slot k. Nothing
	-- stopped a player from parking on island 1, farming Eggs, and buying straight up to the
	-- Titan Gut -- every price is reachable from the bottom given enough flights. That skips
	-- every wall the twelve tiers exist to build and turns the tower into one long grind
	-- followed by a free ride to the summit.
	--
	-- Checked HERE and not only in the shop panel: the panel greys the card, but the remote
	-- takes a maxPower from the client and a greyed button is not a check. This is.
	local reached = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	if not StomachTiers.isUnlocked(tier, reached) then
		print(("[Shop] %s cannot buy %s yet: on slot %d, needs slot %d")
			:format(player.Name, tier.name, reached, tier.unlockSlot or 1))
		pcall(function() StomachFullEvent:FireClient(player, "gut_locked") end)
		return
	end
	if coins.Value < costN then
		print(("[Shop] %s cannot afford %s: %d < %d"):format(player.Name, tier.name, coins.Value, costN))
		return
	end
	coins.Value = coins.Value - costN
	coinsSpentOnGuts[player] = (coinsSpentOnGuts[player] or 0) + costN -- [BALANCE LOGGING] track gut spend
	local oldMax = stomachMaxStat.Value  -- logging only; fuel is NOT rescaled by it
	stomachMaxStat.Value = newMaxN
	-- FUEL CARRIES OVER RAW. It does NOT keep its fill FRACTION, and that distinction is
	-- the whole purchase wall.
	--
	-- This used to do `scaled = floor(cp.Value / oldMax * newMaxN)` -- keep the same PERCENT
	-- of the tank across the upgrade -- under a comment about never leaving a player "worse
	-- off". It reads generous and it is actually a free fuel grant that scales with the size
	-- of the upgrade. A playtest caught it exactly: 82 fuel in a 120 tank, buy the 180 Raptor
	-- Gut, and the tank comes out holding 123. Forty-one fuel from nowhere, 50% more than was
	-- paid for, handed over at the precise moment the design wants the player to be empty and
	-- saving. That crossing is meant to take ~4 flights; it took ONE.
	--
	-- The wall only exists because buying the gut leaves you with a big tank you cannot yet
	-- fill. Pre-filling it to the old percentage removes the wall and refunds the upgrade.
	-- You keep every unit of fuel you paid for -- you are never worse off in absolute terms --
	-- but a bigger tank now reads as emptier, which is the honest and intended result.
	--
	-- COURTESY_FRACTION is 0 for the same reason; see FlightTuning. If you ever want a
	-- welcome gift on upgrade, put it here deliberately rather than smuggling it in as a
	-- percentage, and re-run the progression solve with it.
	local cp = ls:FindFirstChild("CurrentPower")
	local carried = 0
	if cp then
		local slot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
		local gap  = FlightTuning.gapFromSlot(slot)
		local courtesy = FlightTuning.courtesyPower(newMaxN, gap)   -- 0 unless deliberately raised
		cp.Value = math.clamp(math.max(cp.Value, courtesy), 0, newMaxN)
		carried = cp.Value
		print(("[Shop] %s gut %d -> %d: carried %d/%d fuel (%d%% full, next gap %s)"):format(
			player.Name, oldMax, newMaxN, carried, newMaxN,
			math.floor(carried / newMaxN * 100 + 0.5),
			gap and tostring(math.floor(gap)) or "unknown"))
	end
	pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
	local tierNameStr = "Gut"
	for _, t in ipairs(stomachTiers) do
		if t.maxPower == newMaxN then tierNameStr = t.name; break end
	end
	pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, tierNameStr) end)
	print("BOUGHT GUT:", player.Name, tierNameStr, "maxPower "..newMaxN.." for "..costN.." coins")
end)

-- ============================================================================
-- ROBUX products (2x pass, 2x-1hr, Mid-Air Recharge, Skip Island, Meteorite Explosion):
-- in the real game these go through MarketplaceService.ProcessReceipt + the
-- gamepass-owned check (UserOwnsGamePassAsync) in PlayerStats. They're NOT
-- duplicated here because only ONE script may own ProcessReceipt. The shop
-- CLIENT already prompts them (MPS:PromptGamePassPurchase / PromptProductPurchase
-- with GAMEPASS_IDS / PRODUCT_IDS); wire those product IDs into your existing
-- ProcessReceipt to grant the effects.
-- ============================================================================
print("[Shop] server handlers loaded (food + stomach + flight coins). Robux products go through your ProcessReceipt.")
