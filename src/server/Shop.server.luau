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

-- ===== remotes (created if missing) =====
local function ev(name) local e = RS:FindFirstChild(name); if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end; return e end
local BuyFoodEvent      = ev("BuyFoodEvent")       -- c->s: (foodName)
local BuyStomachEvent   = ev("BuyStomachEvent")    -- c->s: (newMax, cost)
local StomachFullEvent  = ev("StomachFullEvent")   -- s->c: (reason) "not_enough_coins"/"stomach_full"/"not_enough_room"
local StomachUpdateEvent= ev("StomachUpdateEvent") -- s->c: (newMax, tierName)
local RegenEvent        = ev("RegenEvent")         -- s->c: (powerAdded, currentPower, stomachMax)
local CoinEvent         = ev("CoinEvent")          -- c->s: (amount) -- coins earned during flight
-- created (never fired here) so the shop client's WaitForChild()s return INSTANTLY instead of blocking
-- it for 30s/10s (this game has no food stands, and gamepass state is provided via _G.playerGamepasses)
ev("StandsReadyEvent")
ev("GamepassEvent")

-- ============================================================================
-- DATA (VERBATIM from PlayerStats.server.lua) -- the client mirrors this exactly.
-- ============================================================================
local foods = {
	{name="Eggs",          price=5,    power=8,   island=1},  -- Nesting Nook
	{name="Lettuce",       price=24,   power=25,  island=2},  -- Fern Frontier
	{name="Bananas",       price=85,   power=45,  island=3},  -- Jungle Junction
	{name="Fish",          price=94,   power=70,  island=4},  -- Coastal Crossing
	{name="Ribs",          price=142,  power=100, island=5},  -- Fossil Frontier
	{name="Mushrooms",     price=138,  power=140, island=6},  -- Misty Mire
	{name="Apples",        price=202,  power=185, island=7},  -- Redwood Ridge
	{name="Chicken",       price=600,  power=240, island=8},  -- Raptor Ridge
	{name="Chili Peppers", price=500,  power=300, island=9},  -- Volcanic Vista
	{name="Potatoes",      price=400,  power=370, island=10}, -- Petrified Pass
	{name="Steak",         price=560,  power=450, island=11}, -- Inferno Isle
	{name="Grapes",        price=405,  power=540, island=12}, -- Crystal Crest
	{name="Popcorn",       price=700,  power=640, island=13}, -- Crater Crossing
	{name="Turkey Legs",   price=518,  power=750, island=14}, -- Predator's Peak
}
-- getMaxHeight(maxPower) = 50 + maxPower*14. Iron is the top of the free path; Infinite is a Robux-only premium gut.
local stomachTiers = {
	{name="Hatchling Belly", maxPower=100,  cost=0,      robux=false},
	{name="Raptor Gut",      maxPower=182,  cost=1600,   robux=false},
	{name="Stego Stomach",   maxPower=520,  cost=3000,   robux=false},
	{name="Bronto Belly",    maxPower=1075, cost=5200,   robux=false},
	{name="Rex Gut",         maxPower=2146, cost=8000,   robux=false},
	{name="Fossil Gut",      maxPower=3218, cost=11000,  robux=false},
	{name="Primal Gut",      maxPower=9999, cost=499,    robux=true},
}
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
	num("Coins", 25)             -- starting coins (matches the other realm's progression spec)
	num("CurrentPower", 0)       -- current fart fuel in the tank
	num("StomachMax", 100)       -- tank size = Hatchling Belly (Tiny Gut tier)
	num("TotalFartPower", 0)     -- cosmetic lifetime counter
	num("TotalCoinsEarned", 0)
	num("Island", 1)
end
Players.PlayerAdded:Connect(setupStats)
for _, p in ipairs(Players:GetPlayers()) do setupStats(p) end

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
	if costN <= 0 or newMaxN <= 0 then return end
	local valid = false
	for _, tier in ipairs(stomachTiers) do
		if tier.maxPower == newMaxN and tier.cost == costN and not tier.robux then
			valid = true; break
		end
	end
	if not valid or coins.Value < costN then return end
	coins.Value = coins.Value - costN
	coinsSpentOnGuts[player] = (coinsSpentOnGuts[player] or 0) + costN -- [BALANCE LOGGING] track gut spend
	stomachMaxStat.Value = newMaxN
	-- CARRY OVER the power already in the tank (don't reset). Only the tank's MAX grows; the current fill stays.
	local cp = ls:FindFirstChild("CurrentPower")
	local carried = 0
	if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end
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
print("[Shop] server buy handlers loaded (food + stomach). Robux products go through your ProcessReceipt.")
