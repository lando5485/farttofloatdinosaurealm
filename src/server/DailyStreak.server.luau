--======================================================================
-- DailyStreak.server.luau   (ServerScriptService)
--======================================================================
-- The DAILY tab of the Rewards hub, ported from the first realm (Fart to Float, push 8a5041b): one login
-- claim per UTC day. Showing up on consecutive days walks a 7-day ladder; after day 7 it LOOPS (day 8 = day 1)
-- while the streak number keeps counting. Miss a day and the next claim starts again at day 1.
--
-- SERVER-AUTHORITATIVE: the client sends only "claim". Same remote + state fields as the first realm, so the
-- ported client (DailyStreak.client.luau) reads: canClaim, streak, day, ladder, ladderLen, claimedToday,
-- todayReward, nextReward.
--
-- ===== ONE STREAK ACROSS EVERY REALM =====
-- The store is "DailyStreak_v1" keyed by UserId with { streak, lastDay } -- the SAME name, key and shape the
-- first realm uses, and every realm is a place in one experience (universe 10236070926), so they all share it.
-- Claim today in the Food Realm and the claim is already spent here, and the reverse; the streak you build in
-- one realm is the streak you see in all of them.
--
-- The claim is taken with ONE UpdateAsync on that shared store, checked against what the STORE says -- not
-- what this server loaded at join -- so a teleport that lands before the other realm's write is visible can't
-- claim the same day twice. The day is taken first and given back if the payout fails.
--
-- ===== WHAT ELSE DIFFERS FROM THE FIRST REALM =====
-- * TICKETS THROUGH THE 300/DAY CAP (RewardsHubCap -- DAILY + TIMED, all realms). If the day's limit is
--   already spent the claim STILL counts for the streak (a run is never broken by the cap) and pays nothing.
-- * The ladder {5,8,10,12,15,20,30} is kept HERE rather than in CrateTokens.LOGIN_STREAK: DailyTasks already
--   pays that table on its own all-tasks bonus and must not change.
-- * DAY 7 is a free STARTER crate spin (the cheapest) instead of the first realm's Mythic: a 1,200-ticket crate
--   would be worth four days of the whole hub's cap. DAY7_CRATE below is the single line to change.
--======================================================================

local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- script.Parent, not ServerScriptService: in the Dino Realm the server scripts live in a DinosaurRealmServer folder.
local Cap = require(script.Parent:WaitForChild("RewardsHubCap"))

local LADDER = { 5, 8, 10, 12, 15, 20, 30 }
local LADDER_LEN = #LADDER
local DAY7_CRATE = "Starter"

-- Shared by EVERY realm (same name, key and shape as the first realm's). Do not rename it.
local store = DataStoreService:GetDataStore("DailyStreak_v1")

-- client -> server: "claim".  server -> client: "state", <table> | "result", ok, amount, msg
local remote = ReplicatedStorage:FindFirstChild("DailyStreakEvent")
if not remote then
	remote = Instance.new("RemoteEvent"); remote.Name = "DailyStreakEvent"; remote.Parent = ReplicatedStorage
end

-- Integer UTC day: "was the last claim yesterday?" is `last == today - 1`. Matches DailyTasks' day maths.
local function dayNumber() return math.floor(os.time() / 86400) end
local function keyFor(player) return tostring(player.UserId) end

local data = {} -- [player] = { streak = n, lastDay = dayNumber }  (a copy of the store, for drawing the panel)
local busy = {} -- [player] = true while a claim is in flight

local function decode(v)
	if type(v) == "table" then
		return { streak = tonumber(v.streak) or 0, lastDay = tonumber(v.lastDay) or 0 }
	end
	return { streak = 0, lastDay = 0 }
end

local function ladderDay(streak)
	local s = math.max(1, math.floor(streak or 1))
	return ((s - 1) % LADDER_LEN) + 1
end
local function rewardFor(day) return LADDER[math.clamp(day, 1, LADDER_LEN)] end

-- The live streak for TODAY, without mutating: claimed today -> keep; claimed yesterday -> ready to advance;
-- anything older -> broken run, next claim is day 1.
local function resolve(d)
	local today = dayNumber()
	local last  = tonumber(d.lastDay) or 0
	local streak = tonumber(d.streak) or 0
	if last == today then
		return streak, false
	elseif last == today - 1 then
		return streak, true
	else
		return 0, true
	end
end

local function buildState(player)
	local d = data[player] or { streak = 0, lastDay = 0 }
	local curStreak, canClaim = resolve(d)
	local shownStreak = canClaim and (curStreak + 1) or curStreak
	local shownDay    = ladderDay(shownStreak)
	return {
		streak       = shownStreak,
		day          = shownDay,
		ladderLen    = LADDER_LEN,
		ladder       = LADDER,
		canClaim     = canClaim,
		claimedToday = not canClaim,
		todayReward  = rewardFor(shownDay),
		nextReward   = rewardFor(ladderDay(shownStreak + 1)),
		day7Crate    = _G.skinCrateFreeSpin and DAY7_CRATE or nil, -- extra: the day-7 crate; nil = no free spin here, day 7 pays tickets
		capLeft      = Cap.remaining(player), capLimit = Cap.LIMIT, -- extra: the hub's 300-ticket day
	}
end

local function pushState(player)
	pcall(function() remote:FireClient(player, "state", buildState(player)) end)
end

local function load(player)
	local ok, v = pcall(function() return store:GetAsync(keyFor(player)) end)
	-- A failed read only affects what the panel DRAWS: the claim itself re-checks the store atomically.
	data[player] = decode(ok and v or nil)
end

-- TAKE TODAY'S CLAIM in the shared store, in one transaction. Returns newStreak, nil, previous on success;
-- nil, "claimed", stored when any realm already claimed today; nil, "store" when the store can't be reached.
local function takeDay(player)
	local newStreak, prev, already = nil, nil, false
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			local d = decode(old)
			prev = d
			local cur, can = resolve(d)
			if not can then already = true; newStreak = nil; return nil end
			already = false
			newStreak = cur + 1
			return { streak = newStreak, lastDay = dayNumber() }
		end)
	end)
	if not ok then return nil, "store", nil end
	if already then return nil, "claimed", prev end
	return newStreak, nil, prev
end

-- GIVE THE DAY BACK when the payout failed -- but only if the store still holds exactly the claim we wrote.
local function giveBack(player, newStreak, prev)
	pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			local d = decode(old)
			if d.streak == newStreak and d.lastDay == dayNumber() then
				return { streak = prev.streak, lastDay = prev.lastDay }
			end
			return nil
		end)
	end)
end

local function reply(player, ok, amount, msg)
	pcall(function() remote:FireClient(player, "result", ok, amount, msg) end)
end

local function claim(player)
	local d = data[player]; if not d then return end

	local _, canClaim = resolve(d)
	if not canClaim then
		reply(player, false, 0, "Come back tomorrow to keep your streak!")
		return
	end

	local newStreak, why, prev = takeDay(player)
	if why == "claimed" then
		data[player] = prev -- another realm got there first: draw what the store says
		reply(player, false, 0, "You already claimed today's streak in another realm -- come back tomorrow!")
		pushState(player)
		return
	elseif why == "store" or not newStreak then
		reply(player, false, 0, "Couldn't reach your save -- try again!")
		return
	end

	local day = ladderDay(newStreak)
	local granted, isCrate, capped = 0, false, false

	if day >= LADDER_LEN and _G.skinCrateFreeSpin then -- a realm without the free spin pays day 7 in tickets below
		-- DAY 7: a server-rolled free crate spin, banked before the reveal is pushed.
		local ok, res = false, nil
		if _G.skinCrateFreeSpin then ok, res = pcall(_G.skinCrateFreeSpin, player, DAY7_CRATE) end
		if not (ok and type(res) == "table" and res.ok) then
			giveBack(player, newStreak, prev)
			reply(player, false, 0, "Couldn't open your crate -- try again!")
			return
		end
		isCrate = true
	else
		local got, reason = Cap.pay(player, rewardFor(day), "loginStreak")
		if got > 0 then
			granted = got
		elseif reason == "cap" then
			capped = true -- the day's tickets are spent (in any realm): still count the streak, pay nothing
		else
			giveBack(player, newStreak, prev)
			reply(player, false, 0, "One moment -- try again!")
			return
		end
	end

	data[player] = { streak = newStreak, lastDay = dayNumber() }

	if isCrate then
		print(("[DailyStreak] %s claimed day %d (streak %d) -> FREE %s SPIN"):format(player.Name, day, newStreak, DAY7_CRATE))
		reply(player, true, 0, ("Day 7!  Free %s Crate spin!"):format(DAY7_CRATE))
	elseif capped then
		print(("[DailyStreak] %s claimed day %d (streak %d) -> daily ticket limit reached, 0 paid"):format(player.Name, day, newStreak))
		reply(player, true, 0, ("Day %d streak kept!  (Today's %d-ticket limit is reached)"):format(day, Cap.LIMIT))
	else
		print(("[DailyStreak] %s claimed day %d (streak %d) -> +%d tickets"):format(player.Name, day, newStreak, granted))
		reply(player, true, granted, ("Day %d streak!  +%d Tickets"):format(day, granted))
	end
	pushState(player)
end

remote.OnServerEvent:Connect(function(player, action)
	if action ~= "claim" or busy[player] then return end
	busy[player] = true
	local ok, err = pcall(claim, player)
	busy[player] = nil
	if not ok then warn("[DailyStreak] claim error for " .. player.Name .. ": " .. tostring(err)) end
end)

-- Other systems (the MORE+ badge, the hub's own badge) ask "is a claim waiting?" without a remote round-trip.
_G.dailyStreakPending = function(player)
	local d = data[player]; if not d then return false end
	local _, canClaim = resolve(d)
	return canClaim == true
end

local function onAdded(player)
	load(player)
	task.spawn(function()
		task.wait(3) -- let the client build its UI and SkinCrateService register the faucet
		if player.Parent then pushState(player) end
	end)
end

Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onAdded, p) end
-- No save on leave: the store is written at the moment of the claim, and only then.
Players.PlayerRemoving:Connect(function(p) data[p] = nil; busy[p] = nil end)

-- UTC midnight while online: redraw so the new day's claim lights up without a rejoin.
task.spawn(function()
	local last = dayNumber()
	while true do
		task.wait(60)
		if dayNumber() ~= last then
			last = dayNumber()
			for _, p in ipairs(Players:GetPlayers()) do pushState(p) end
		end
	end
end)

print(("[DailyStreak] ready -- one claim per UTC day shared by every realm, tickets {5..20} + day-7 %s crate, capped at %d/day"):format(
	DAY7_CRATE, Cap.LIMIT))
