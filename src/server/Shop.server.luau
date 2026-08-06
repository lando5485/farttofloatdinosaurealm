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
	-- 120 buys most of a first tank of Eggs. At 25 you could not afford enough food
	-- for a profitable first flight and the run dead-locked before island 2.
	num("Coins", 120)            -- starting coins
	num("CurrentPower", 0)       -- current fart fuel in the tank
	num("StomachMax", 100)       -- tank size = Hatchling Belly (Tiny Gut tier)
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
-- succeed. That defeated the point of the price curve. It now funds a QUARTER TANK --
-- the floor that keeps the loop alive, not a free crossing. A quarter tank is always
-- enough to climb out of the hole because R > 1 at every row of `foods`: any flight,
-- however short, banks more coins than the fuel it burned, so the player compounds
-- back up to a full tank on their own.
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

	-- A QUARTER of the tank, in servings -- the smallest launch worth making, not the
	-- crossing. A serving is indivisible, so round UP: being one egg short of being
	-- able to fly at all is the exact situation this exists to prevent.
	local missing = (sm.Value * 0.25) - cp.Value
	if missing <= 0 then return end                  -- already holding a quarter tank
	local servings = math.max(1, math.ceil(missing / food.power))
	-- ...but never more than the tank can actually hold, or we would fund food that
	-- gets rejected as "not_enough_room".
	local roomServings = math.floor((sm.Value - cp.Value) / food.power)
	servings = math.min(servings, math.max(0, roomServings))
	if servings <= 0 then return end

	local needCoins = servings * food.price
	if coins.Value >= needCoins then return end      -- they can already afford it
	local grant = needCoins - coins.Value
	coins.Value = coins.Value + grant
	print(("[Shop] anti-strand: %s landed dry on slot %d with %d coins, needs %d for %d x %s (quarter tank) -> granted %d")
		:format(player.Name, slot, coins.Value - grant, needCoins, servings, food.name, grant))
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
	print("SERVER RECEIVED BUY:", player.Name, foodName)
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
	-- Distinguish TRULY FULL (no room at all -> "stomach_full") from HAS-ROOM-but-too-big ("not_enough_room").
	if newPower > effectiveMax then
		local remaining = effectiveMax - currentPower.Value
		if remaining <= 0 then
			print("STOMACH FULL:", player.Name, currentPower.Value, "/", effectiveMax, "(no room at all)")
			pcall(function() StomachFullEvent:FireClient(player, "stomach_full") end)    -- truly full
		else
			print("NOT ENOUGH ROOM:", player.Name, "+"..powerGain, ">", remaining, "remaining")
			pcall(function() StomachFullEvent:FireClient(player, "not_enough_room") end) -- has room, this food won't fit
		end
		return
	end
	coins.Value = coins.Value - food.price
	coinsSpentOnFood[player] = (coinsSpentOnFood[player] or 0) + food.price -- [BALANCE LOGGING] track food spend
	currentPower.Value = newPower
	-- Cosmetic TotalFartPower counter: unchanged -- still doubles with the pass as before.
	local bonusPower = has2x and food.power or 0
	totalPower.Value = totalPower.Value + food.power + bonusPower
	if totalEarned then totalEarned.Value = totalEarned.Value + food.price end
	pcall(function() RegenEvent:FireClient(player, food.power, currentPower.Value, stomachMax.Value) end)
	print("BOUGHT:", player.Name, foodName, "+", food.power, "power, total:", currentPower.Value)
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
	local oldMax = stomachMaxStat.Value
	stomachMaxStat.Value = newMaxN
	-- fillMeterForNextIsland: top the tank up to what the NEXT island needs, +10%.
	-- Flight time is power/stomachMax, so a bigger tank makes the SAME food give a
	-- much shorter flight -- carrying power over unchanged made every upgrade crater
	-- the player's income and could bankrupt them outright. Scale the existing fill
	-- to the new tank so an upgrade never leaves you worse off than before it.
	-- ...which is what the comment above always CLAIMED, but the code only ever
	-- scaled the old fill across (frac * newMax). That is not "what the next island
	-- needs" -- an upgrade bought on an empty tank stayed empty. It now fills to
	-- FlightTuning.courtesyPower: the crossing this gut unlocks, plus 10%.
	--
	-- MEASURED AGAINST THE GAP THE PLAYER IS ACTUALLY AT, not the new gut's own tier gap.
	-- Passing no slot gave a FULL tank every time, and that was the arithmetic being
	-- honest about a wrong question: a full tank is sized for the tier's OWN gap, but a
	-- gut is bought at the END of the previous tier, so the next crossing is the shorter
	-- one underneath it. Raptor Gut on slot 2 now arrives at 172/182 rather than 182/182.
	local cp = ls:FindFirstChild("CurrentPower")
	local carried = 0
	if cp then
		local slot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
		local gap  = FlightTuning.gapFromSlot(slot)
		local frac = (oldMax > 0) and (cp.Value / oldMax) or 0
		local scaled   = math.floor(frac * newMaxN)               -- never worse off than before
		local courtesy = FlightTuning.courtesyPower(newMaxN, gap) -- the trip in front of them + 10%
		cp.Value = math.clamp(math.max(scaled, courtesy), cp.Value, newMaxN)
		carried = cp.Value
		print(("[Shop] %s gut -> %d: courtesy fill %d/%d (next gap %s)")
			:format(player.Name, newMaxN, carried, newMaxN, gap and tostring(math.floor(gap)) or "unknown"))
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
