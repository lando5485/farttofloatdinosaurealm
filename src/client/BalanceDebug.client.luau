--======================================================================
-- BalanceDebug.client.luau  (LocalScript)   *** TEMPORARY DIAGNOSTIC ***
--======================================================================
-- Instruments the distance-to-tank progression and writes it to the Output window, so a
-- balance problem can be read off the log instead of guessed at.
--
-- SET `ENABLED = false` (or delete this file) TO TURN IT ALL OFF. It writes nothing to the
-- world, touches no gameplay value, and never fires a remote -- it only observes.
--
-- ===== WHAT IT WATCHES, AND WHY IT CAN WATCH IT FROM HERE =====
-- Everything this needs already replicates or already lives on the client:
--     leaderstats.StomachMax / CurrentPower / Coins    the tank and what is in it
--     HighestSlot attribute                            which crossing you are on
--     _G.isFlying                                      BottomHUD's own flight flag
--     HumanoidRootPart.Position.Y                      distance travelled
-- so nothing in BottomHUD, Shop or FlightTuning had to be edited to make this work. That
-- matters: a diagnostic that changes the thing it is measuring is worthless.
--
-- ===== EVERY THRESHOLD IS DERIVED, NOT TYPED =====
-- The classifications come out of the game's own numbers rather than from picked
-- percentages, so they stay correct if the tuning moves:
--
--   EDGE LINE   = 1 - (one serving's worth of reach / the gap)
--       A failure inside one serving of clearing is the definition of edging: the player
--       cannot buy a smaller step than one serving, so the next attempt is a coin-flip on
--       a single food item. Below that line a failure is a real, visible increment.
--
--   LOW LINE    = how far the ANTI-STRAND handout alone would carry you
--       Shop.server hands a genuinely stranded player exactly ONE MEAL. Progress under that
--       is worse than the free floor the game already guarantees, so it is the honest
--       definition of "made very little progress".
--
--   TOO EASY    = cleared on less than one meal
--       Same anchor from the other side: if a crossing falls to less fuel than the game
--       hands out for free, it is not costing the player anything.
--
--   MEALS       = ceil(fuel needed / one meal), printed per crossing
--       The tower is solved so that every crossing is TWO meals (three on the two starter
--       islands), because the last failed attempt is always one meal short of the fill that
--       clears -- so meal count is what decides whether a miss lands at 55% of the gap or at
--       95%. Any row outside 2-3 is flagged; that is the drift check to watch.
--======================================================================

local ENABLED = true
if not ENABLED then return end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DinoRealm     = ReplicatedStorage:WaitForChild("DinosaurRealm")
local IslandOrder   = require(DinoRealm:WaitForChild("IslandOrder"))
local FlightTuning  = require(DinoRealm:WaitForChild("FlightTuning"))
local StomachTiers  = require(DinoRealm:WaitForChild("StomachTiers"))
local FoodMenu      = require(DinoRealm:WaitForChild("FoodMenu"))

local player = Players.LocalPlayer

local SAMPLE_EVERY   = 0.5   -- seconds between in-flight lines (the brief's cadence)
-- The anti-strand floor is now exactly ONE MEAL rather than a fraction of a tank, so this
-- is read per slot from FoodMenu instead of being a constant. Kept as a fallback only.
local ANTI_STRAND    = 0.30
-- Every crossing is solved to TWO meals, except the two starter crossings which are three
-- (FoodMenu's header). One meal would be a crossing you cannot fail; four or more pushes the
-- last miss back into the edging band. Anything outside 2..3 means a row has drifted.
local MEALS_MIN, MEALS_MAX = 2, 3
local TAG            = "[DINO BALANCE]"

--======================================================================
-- READERS
--======================================================================
local function stat(name)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end

local function slotNow()
	return math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, IslandOrder.COUNT)
end

local function gapFrom(slot)
	local a, b = IslandOrder.SLOT_POS[slot], IslandOrder.SLOT_POS[slot + 1]
	if not (a and b) then return nil end
	return b.Y - a.Y
end

local function islandName(slot)
	local num = IslandOrder.SLOT_TO_ISLAND[slot]
	return num and IslandOrder.NAMES[num] or "?"
end

-- The gut a player is EXPECTED to hold on this slot -- the highest whose unlockSlot has
-- been reached. Used only for the predicted table; live readouts use the real tank.
local function expectedTier(slot)
	local best = StomachTiers.LIST[1]
	for _, t in ipairs(StomachTiers.LIST) do
		if not t.robux and t.unlockSlot and t.unlockSlot <= slot then best = t end
	end
	return best
end

local function foodForSlot(slot)
	return FoodMenu.LIST[math.clamp(slot, 1, #FoodMenu.LIST)]
end

-- Anything that is quietly changing the numbers. Printed loudly, because a balance log
-- taken with InfiniteGut on is not a balance log.
local function modifiers()
	local out = {}
	if player:GetAttribute("InfiniteGut") then table.insert(out, "InfiniteGut=ON") end
	if player:GetAttribute("HasPrimalGut") then table.insert(out, "HasPrimalGut=ON (drain disabled)") end
	if player:GetAttribute("HasTwoXForever") then table.insert(out, "2x tank=ON") end
	local fd = _G.flightDistanceMultiplier
	if fd and math.abs(fd - 1) > 1e-6 then table.insert(out, ("flightDistanceMult=%.2f"):format(fd)) end
	local ss = _G.serverEventSpeedMult
	if ss and math.abs(ss - 1) > 1e-6 then table.insert(out, ("eventSpeedMult=%.2f"):format(ss)) end
	local sh = _G.serverEventHeightMult
	if sh and math.abs(sh - 1) > 1e-6 then table.insert(out, ("eventHeightMult=%.2f"):format(sh)) end
	local sg = _G.serverEventGasDrainMult
	if sg and math.abs(sg - 1) > 1e-6 then table.insert(out, ("eventGasDrainMult=%.2f"):format(sg)) end
	local sc = _G.serverEventCoinMult
	if sc and math.abs(sc - 1) > 1e-6 then table.insert(out, ("eventCoinMult=%.2f"):format(sc)) end
	if _G.windstormActive then table.insert(out, "WINDSTORM") end
	if _G.flightLockUntil and os.clock() < _G.flightLockUntil then table.insert(out, "flightLock") end
	return out
end

--======================================================================
-- DERIVED THRESHOLDS
--======================================================================
-- One serving of food, expressed as a fraction of THIS gap. Measured at the top speed band
-- because that is where the final serving is actually spent.
local function servingReach(slot, tank, climb, gap)
	local food = foodForSlot(slot)
	if not (food and tank > 0 and gap > 0) then return 0.05 end
	local shape = FlightTuning.SPEED_SHAPE
	local top = shape[#shape] or 1
	return (food.power / tank) * (climb / gap) * top
end

local function edgeLine(slot, tank, climb, gap)
	return 1 - servingReach(slot, tank, climb, gap)
end

-- How far the free floor alone carries you. That floor is now exactly ONE MEAL, so this
-- reads the meal off FoodMenu rather than using a fraction of the tank.
local function lowLine(slot, tank, climb, gap)
	if gap <= 0 or tank <= 0 then return 0.4 end
	local food = foodForSlot(slot)
	local free = food and food.power or (tank * ANTI_STRAND)
	return FlightTuning.climbFor(tank, math.min(tank, free)) / gap
end

-- How many MEALS this crossing costs. The whole tower is solved to three (see FoodMenu);
-- anything else here means a food row or a tank has drifted out of its window, and it is the
-- single most useful number in this log -- meal count is what pins the last miss.
local function mealsFor(slot, tank, need)
	local food = foodForSlot(slot)
	if not (food and food.power > 0) then return 0 end
	return math.ceil(need / food.power)
end

-- Tank usage -> a word. Anchored on the free floor (one meal) and on 1.0 (a full tank).
-- `cleared` distinguishes "this crossing needs more than a tank" from "you spent the whole
-- tank and made it". The log caught the old version calling a 100%-tank SUCCESS "IMPOSSIBLE".
local function difficultyWord(frac, cleared, mealFrac)
	if frac >= 1.0 then
		return cleared and "MAXIMUM (took the entire tank)" or "IMPOSSIBLE (needs a bigger gut)"
	end
	if frac >= 0.90 then return "VERY HARD" end
	if frac >= 0.70 then return "HARD" end
	if frac >= (mealFrac or ANTI_STRAND) then return "MODERATE" end
	return "TOO EASY (under the free one-meal floor)"
end

--======================================================================
-- SESSION TABLES
--======================================================================
local function printBalanceTable()
	print(("%s ==================== BALANCE TABLE ===================="):format(TAG))
	print(("%s COIN_PER_STUD=%.4f  FLIGHT_SECONDS=%.3f  DRAIN=%.3f/s  MARGIN=%.2f")
		:format(TAG, (FlightTuning.COIN_PER_STUD_BASE or 0.637) / (FlightTuning.SPACING_SCALE or 1),
			FlightTuning.FLIGHT_SECONDS, FlightTuning.DRAIN_RATE, FlightTuning.MARGIN))
	print(("%s %-9s %-34s %7s %-16s %7s %8s %7s %6s  %s")
		:format(TAG, "crossing", "route", "gap", "expected gut", "tank", "needPow", "%tank", "meals", "difficulty"))

	for slot = 1, IslandOrder.COUNT - 1 do
		local gap = gapFrom(slot)
		if gap then
			local tier = expectedTier(slot)
			local tank = tier.maxPower
			local climb = FlightTuning.fullTankClimb(tank)
			local need = FlightTuning.powerForClimb(tank, gap)
			local frac = (tank > 0) and (need / tank) or 0
			local meals = mealsFor(slot, tank, need)
			local food  = foodForSlot(slot)
			local mealFrac = (food and tank > 0) and (food.power / tank) or ANTI_STRAND
			-- The last failed attempt is always one meal short of the fill that clears, so
			-- meal count alone predicts how close the miss lands. Flag anything off the
			-- three-meal design: 2 means the crossing can be bought in one jump, 4+ means the
			-- final miss creeps back up toward the gap and it starts to feel like edging.
			local flag = (meals >= MEALS_MIN and meals <= MEALS_MAX) and ""
				or ("  <== %d MEALS, EXPECTED %d-%d"):format(meals, MEALS_MIN, MEALS_MAX)
			print(("%s %-9s %-34s %7d %-16s %7d %8.1f %6.1f%% %6d  %s%s")
				:format(TAG, ("%d->%d"):format(slot, slot + 1),
					("%s -> %s"):format(islandName(slot), islandName(slot + 1)),
					gap, tier.name, tank, need, frac * 100, meals,
					difficultyWord(frac, false, mealFrac), flag))
		end
	end
	print(("%s ======================================================="):format(TAG))
end

local function printGutTable()
	print(("%s ====================== GUT TABLE ======================"):format(TAG))
	local shape = FlightTuning.SPEED_SHAPE
	for _, t in ipairs(StomachTiers.LIST) do
		local tank = t.maxPower
		if tank < 1e6 then
			local climb = FlightTuning.fullTankClimb(tank)
			local mean = climb / FlightTuning.FLIGHT_SECONDS
			-- which crossings a FULL tank of this gut can and cannot make
			local reach, short = {}, {}
			for slot = 1, IslandOrder.COUNT - 1 do
				local gap = gapFrom(slot)
				if gap then
					if climb >= gap then table.insert(reach, slot) else table.insert(short, slot) end
				end
			end
			local food = foodForSlot(t.unlockSlot or 1)
			print(("%s %-16s tank %5d  climb %6d  speed %6.1f (%.1f-%.1f)  drain %.2f/s  cost %5d")
				:format(TAG, t.name, tank, climb, mean, mean * shape[1], mean * shape[#shape],
					FlightTuning.DRAIN_RATE * tank / 100, t.cost or 0))
			print(("%s %-16s food at unlock: %s (%d pow / %d coins) = %.1f%% of tank per serving")
				:format(TAG, "", food and food.name or "?", food and food.power or 0,
					food and food.price or 0, food and (food.power / tank * 100) or 0))
			print(("%s %-16s reaches crossings: %s")
				:format(TAG, "", #reach > 0 and table.concat(reach, ",") or "(none)"))
			print(("%s %-16s CANNOT reach:      %s")
				:format(TAG, "", #short > 0 and table.concat(short, ",") or "(none -- clears the tower)"))
		end
	end
	print(("%s ======================================================="):format(TAG))
end

--======================================================================
-- FLIGHT TRACKING
--======================================================================
local flight = nil   -- nil when not flying

local function takeoff(hrp)
	local slot = slotNow()
	local gap = gapFrom(slot)
	local tank = stat("StomachMax")
	local power = stat("CurrentPower")
	local climb = FlightTuning.fullTankClimb(tank)
	local predicted = FlightTuning.climbFor(tank, power)

	flight = {
		slot = slot, gap = gap, tank = tank,
		startPower = power, startY = hrp.Position.Y,
		startCoins = stat("Coins"), startClock = os.clock(),
		climb = climb, predicted = predicted,
		nextSample = os.clock() + SAMPLE_EVERY,
		peakY = hrp.Position.Y,
	}

	local mods = modifiers()
	print(("%s ---------------- TAKEOFF ----------------"):format(TAG))
	print(("%s %s (slot %d) -> %s (slot %d)")
		:format(TAG, islandName(slot), slot, islandName(slot + 1), slot + 1))
	print(("%s gut: tank %d  fullTankClimb %d  speed %.1f-%.1f studs/s")
		:format(TAG, tank, climb,
			FlightTuning.getFlightSpeed(1, tank), FlightTuning.getFlightSpeed(tank, tank)))
	print(("%s fuel: %.1f / %d  (%.1f%% of tank)  gas meter %.1f%%")
		:format(TAG, power, tank, tank > 0 and power / tank * 100 or 0,
			tank > 0 and power / tank * 100 or 0))
	if gap then
		print(("%s gap: %d studs   Y %.0f -> %.0f   predicted climb %.0f (%.1f%% of gap)")
			:format(TAG, gap, flight.startY, flight.startY + gap, predicted, predicted / gap * 100))
		local need = FlightTuning.powerForClimb(tank, gap)
		print(("%s required: %.1f power (%.1f%% of tank) -- you launched with %.1f%%")
			:format(TAG, need, tank > 0 and need / tank * 100 or 0,
				tank > 0 and power / tank * 100 or 0))
	else
		print(("%s gap: n/a (top of the tower)"):format(TAG))
	end
	if #mods > 0 then
		print(("%s *** MODIFIERS ACTIVE: %s ***"):format(TAG, table.concat(mods, ", ")))
		print(("%s *** numbers below are NOT a clean balance sample ***"):format(TAG))
	end
end

local function sample(hrp)
	local f = flight
	local tank = stat("StomachMax")
	local power = stat("CurrentPower")
	local travelled = hrp.Position.Y - f.startY
	local t = os.clock() - f.startClock

	local gapTxt, remTxt, pctTxt = "n/a", "n/a", "n/a"
	if f.gap and f.gap > 0 then
		gapTxt = ("%d"):format(f.gap)
		remTxt = ("%.0f"):format(math.max(0, f.gap - travelled))
		pctTxt = ("%.1f%%"):format(travelled / f.gap * 100)
	end

	print(("%s   t=%5.2fs  up %6.0f / %s (%s, %s left)  fuel %6.1f/%d (%.1f%% used)  speed %.1f")
		:format(TAG, t, travelled, gapTxt, pctTxt, remTxt, power, tank,
			f.tank > 0 and (f.startPower - power) / f.tank * 100 or 0,
			FlightTuning.getFlightSpeed(power, tank)))

	local mods = modifiers()
	if #mods > 0 then
		print(("%s     modifiers: %s"):format(TAG, table.concat(mods, ", ")))
	end
end

local function landing(hrp)
	local f = flight
	flight = nil
	if not f then return end

	local travelled = math.max(0, f.peakY - f.startY)
	local power = stat("CurrentPower")
	local usedPower = math.max(0, f.startPower - power)
	local usedFrac = (f.tank > 0) and (usedPower / f.tank) or 0
	local dur = os.clock() - f.startClock
	local coins = stat("Coins") - f.startCoins

	print(("%s ---------------- RESULT ----------------"):format(TAG))
	print(("%s %s -> %s"):format(TAG, islandName(f.slot), islandName(f.slot + 1)))

	if not f.gap or f.gap <= 0 then
		print(("%s Result: (no gap above -- summit)  climbed %.0f in %.1fs"):format(TAG, travelled, dur))
		print(("%s ----------------------------------------"):format(TAG))
		return
	end

	local progress = travelled / f.gap
	local success = progress >= 0.995 or slotNow() > f.slot
	local edge = edgeLine(f.slot, f.tank, f.climb, f.gap)
	local low = lowLine(f.slot, f.tank, f.climb, f.gap)
	local foodHere = foodForSlot(f.slot)
	local mealFrac = (foodHere and f.tank > 0) and (foodHere.power / f.tank) or ANTI_STRAND

	print(("%s Result: %s"):format(TAG, success and "SUCCESS" or "FAILED"))
	print(("%s Gap: %d"):format(TAG, f.gap))
	print(("%s Distance: %.0f / %d"):format(TAG, travelled, f.gap))
	print(("%s Progress: %.1f%%"):format(TAG, progress * 100))
	print(("%s Tank Used: %.1f%%   Tank Remaining: %.1f%%")
		:format(TAG, usedFrac * 100, math.max(0, 100 - usedFrac * 100)))
	print(("%s Flight time: %.1fs   Coins earned: %d"):format(TAG, dur, coins))

	if success then
		local word = difficultyWord(usedFrac, true, mealFrac)
		print(("%s Progression: %s"):format(TAG, word))
		if usedFrac < mealFrac then
			print(("%s *** TOO EASY: cleared on %.0f%% of a tank, under the %.0f%% ONE MEAL the "
				.. "game hands a stranded player for free ***"):format(TAG, usedFrac * 100, mealFrac * 100))
		end
	else
		local shortfall = f.gap - travelled
		print(("%s Shortfall: %.0f studs"):format(TAG, shortfall))
		print(("%s Thresholds: edge line %.1f%%   low line %.1f%%"):format(TAG, edge * 100, low * 100))
		if progress >= edge then
			print(("%s EDGING RISK: HIGH -- failed within ONE SERVING of clearing "
				.. "(%s buys %.1f%% of this gap)"):format(TAG,
				foodForSlot(f.slot) and foodForSlot(f.slot).name or "one serving",
				servingReach(f.slot, f.tank, f.climb, f.gap) * 100))
		elseif progress < low then
			print(("%s Classification: LOW PROGRESS -- under the free one-meal floor"):format(TAG))
		else
			print(("%s Classification: HEALTHY FAILURE -- a visible, affordable step short"):format(TAG))
		end
		local need = FlightTuning.powerForClimb(f.tank, f.gap)
		local food = foodForSlot(f.slot)
		if food and food.power > 0 then
			local more = math.max(0, math.ceil((need - f.startPower) / food.power))
			print(("%s To clear: %.1f power (%.1f%% of tank) = %d more %s (%d coins)")
				:format(TAG, need, f.tank > 0 and need / f.tank * 100 or 0, more, food.name,
					more * food.price))
		end
	end
	print(("%s ----------------------------------------"):format(TAG))
end

--======================================================================
-- BOOT + LOOP
--======================================================================
task.spawn(function()
	-- Let leaderstats and the tuning modules settle before printing the tables.
	task.wait(6)
	print(("%s debug instrumentation ACTIVE (set ENABLED=false in BalanceDebug.client to silence)"):format(TAG))
	local mods = modifiers()
	if #mods > 0 then
		print(("%s *** SESSION MODIFIERS: %s ***"):format(TAG, table.concat(mods, ", ")))
		print(("%s *** any balance reading this session is INVALID while these are on ***"):format(TAG))
	end
	printBalanceTable()
	printGutTable()
end)

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local flying = _G.isFlying == true

	if flying and not flight then
		-- IGNORE FUEL DREGS. Landing from a failed flight usually leaves a few percent in the
		-- tank, and tapping thrust on that produces a "flight" that climbs a couple of hundred
		-- studs and logs a full TAKEOFF/RESULT block. The playtest log was more than half these,
		-- and they drown the real attempts. Under one serving of the local food there is not
		-- enough fuel to be a genuine attempt at anything.
		local food = foodForSlot(slotNow())
		if food and stat("CurrentPower") < food.power then return end
		takeoff(hrp)
	elseif flying and flight then
		if hrp.Position.Y > flight.peakY then flight.peakY = hrp.Position.Y end
		-- Thrust came back before the grace window expired. That is one ATTEMPT, not two:
		-- BottomHUD's isFlying follows the button, and players tap it. Clearing the flag
		-- makes the pending score a no-op and the attempt carries on.
		flight.scoring = false
		if os.clock() >= flight.nextSample then
			flight.nextSample = os.clock() + SAMPLE_EVERY
			sample(hrp)
		end
	elseif (not flying) and flight then
		-- Keep tracking the high-water mark through the coast after thrust stops.
		if hrp.Position.Y > flight.peakY then flight.peakY = hrp.Position.Y end

		-- SCHEDULE THE SCORE ONCE. `flight.scoring` is the guard, and it is not optional:
		-- this branch runs every frame the player is on the ground with a flight still open,
		-- so without it the first grounded frame would queue a delayed call and so would the
		-- next hundred -- a burst of duplicate RESULT blocks for one flight.
		--
		-- The 1.2 s grace is so peakY is the real apex: releasing thrust mid-arc still
		-- carries you upward for a moment, and scoring on the release frame would under-report
		-- every flight's distance.
		if not flight.scoring then
			flight.scoring = true
			local f = flight
			task.delay(1.2, function()
				-- Score only if THIS attempt is still the open one and nobody re-pressed
				-- thrust in the meantime (which clears `scoring` above).
				if flight ~= f or not f.scoring then return end
				local char2 = player.Character
				local hrp2 = char2 and char2:FindFirstChild("HumanoidRootPart")
				if hrp2 then landing(hrp2) end
			end)
		end
	end
end)
