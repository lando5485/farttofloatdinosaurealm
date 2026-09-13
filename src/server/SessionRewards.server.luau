--======================================================================
-- SessionRewards.server.luau   (ServerScriptService)
--======================================================================
-- The TIMED tab of the Rewards hub, ported from the first realm (Fart to Float, push 8a5041b): six playtime
-- milestones -- 5, 10, 20, 30, 45 and 60 minutes. Cross a milestone, claim it. When all six are claimed the
-- track rolls over into the next "pass": the same six rungs an hour further out, paying 1.5x more.
--
-- SERVER-AUTHORITATIVE. The client draws a countdown and a CLAIM button; this file checks the clock it kept.
--
-- ===== ONE LADDER PER DAY, ACROSS EVERY REALM (differs from the first realm) =====
-- The first realm's ladder lived in memory and restarted every session -- so leaving and joining (or hopping to
-- another realm) handed you a fresh set of rungs. Here the ladder is a DAILY ladder in a store every realm
-- shares ("SessionRewardsDay_v1", keyed by UserId -- all realms are places in one experience, so one store):
--   * playtime ADDS UP across realms and rejoins for the UTC day -- 20 minutes in the Food Realm and 10 here
--     is 30 minutes on the ladder;
--   * a rung claimed in ANY realm is claimed in all of them, and so is the pass you're on;
--   * it all resets at UTC midnight.
-- A claim is ONE UpdateAsync against that store (not this server's copy), so a rung can't be claimed twice by
-- two realms, and it is given back if the payout fails.
--
-- ===== THE 300-TICKET DAY =====
-- Payouts go through RewardsHubCap (DAILY + TIMED, all realms, 300 tickets per UTC day). One full pass (270)
-- plus the best streak day (30) is exactly 300. Every card shows what will ACTUALLY pay -- a partial amount near
-- the cap, "Daily limit" at it.
--
-- Tickets, never coins: coins drive the planet progression.
--======================================================================

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService    = game:GetService("DataStoreService")

-- script.Parent, not ServerScriptService: in the Dino Realm the server scripts live in a DinosaurRealmServer folder.
local Cap = require(script.Parent:WaitForChild("RewardsHubCap"))

-- Shared by EVERY realm. Do not rename it per realm.
local store = DataStoreService:GetDataStore("SessionRewardsDay_v1")

local remote = ReplicatedStorage:FindFirstChild("SessionRewardEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SessionRewardEvent"
	remote.Parent = ReplicatedStorage
end

-- The ticket glyph; must equal CrateTokens.ICON (the client falls back to that constant for a rung with none).
local TOKEN_ICON = "\xF0\x9F\x8E\x9F"

-- ONE PASS. 5+10+20+40+75+120 = 270; with the streak's best day (30) that is the 300-ticket day exactly.
local BASE = {
	{ sec =  5 * 60, amount =   5 },
	{ sec = 10 * 60, amount =  10 },
	{ sec = 20 * 60, amount =  20 },
	{ sec = 30 * 60, amount =  40 },
	{ sec = 45 * 60, amount =  75 },
	{ sec = 60 * 60, amount = 120 },
}
local FULL_MASK = 2 ^ #BASE - 1

-- PASSES: an hour is a lap, not a finish line. The pass advances on the SIXTH CLAIM, not on the clock, so a
-- player who ignores the tab never loses a rung.
local PASS_SEC    = 60 * 60
local PASS_GROWTH = 1.5

local function passAmount(baseAmount, pass)
	local v = baseAmount * (PASS_GROWTH ^ pass)
	return math.max(1, math.floor(v / 5 + 0.5) * 5)
end

-- The ONLY place a pass's numbers are worked out, so the card and the claim cannot disagree.
local function rungsFor(pass)
	local out = {}
	for i, m in ipairs(BASE) do
		out[i] = { sec = pass * PASS_SEC + m.sec, amount = passAmount(m.amount, pass) }
	end
	return out
end

--======================================================================
-- THE DAY RECORD  { day, played (seconds today, all realms), pass, mask (claimed rungs, bit i-1 = rung i) }
-- A bitmask rather than a table of booleans: a sparse array does not survive a DataStore round-trip.
--======================================================================
local function today() return math.floor(os.time() / 86400) end
local function keyFor(player) return tostring(player.UserId) end
local function bit(i) return 2 ^ (i - 1) end

local function normalize(v)
	local d = today()
	if type(v) ~= "table" or tonumber(v.day) ~= d then
		return { day = d, played = 0, pass = 0, mask = 0 }
	end
	return {
		day = d,
		played = math.max(0, math.floor(tonumber(v.played) or 0)),
		pass = math.max(0, math.floor(tonumber(v.pass) or 0)),
		mask = bit32.band(math.floor(tonumber(v.mask) or 0), FULL_MASK),
	}
end

-- A finished pass becomes the next, empty one.
local function roll(r)
	if r.mask == FULL_MASK then r.pass += 1; r.mask = 0 end
	return r
end

-- Two views of the same day: the further pass wins; on the same pass, claims are unioned; playtime takes the max.
local function merge(a, b)
	local r = { day = a.day, played = math.max(a.played, b.played) }
	if a.pass > b.pass then
		r.pass, r.mask = a.pass, a.mask
	elseif b.pass > a.pass then
		r.pass, r.mask = b.pass, b.mask
	else
		r.pass, r.mask = a.pass, bit32.bor(a.mask, b.mask)
	end
	return roll(r)
end

local function encode(r) return { day = r.day, played = r.played, pass = r.pass, mask = r.mask } end

--======================================================================
-- PER-PLAYER STATE: the record as last synced, plus the clock since then
--======================================================================
local rec  = {} -- [player] = normalized record
local t0   = {} -- [player] = os.clock() when rec.played was last synced
local busy = {} -- [player] = true while a claim is in flight

local function live(player)
	local r = rec[player]
	if not r then return nil end
	if r.day ~= today() then -- UTC midnight rolled over mid-session: a fresh ladder
		r = { day = today(), played = 0, pass = 0, mask = 0 }
		rec[player], t0[player] = r, os.clock()
	end
	return r
end

local function elapsed(player)
	local r = live(player)
	if not r then return 0 end
	return r.played + math.max(0, math.floor(os.clock() - (t0[player] or os.clock())))
end

-- This server's view right now, playtime included.
local function current(player)
	local r = live(player)
	return { day = r.day, played = elapsed(player), pass = r.pass, mask = r.mask }
end

local function adopt(player, r)
	rec[player], t0[player] = r, os.clock()
end

local function save(player)
	if not live(player) then return end
	local mine = current(player)
	local merged = nil
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			merged = merge(normalize(old), mine)
			return encode(merged)
		end)
	end)
	if ok and merged and player.Parent then adopt(player, merged) end
end

--======================================================================
-- SNAPSHOT
--======================================================================
local function labelFor(player, amount)
	local p = math.min(amount, Cap.remaining(player))
	if p <= 0 then return "Daily limit" end
	return p .. " Tickets"
end

local function snapshot(player)
	local r = live(player) or { pass = 0, mask = 0 }
	local rungs = {}
	for i, m in ipairs(rungsFor(r.pass)) do
		rungs[i] = { sec = m.sec, icon = TOKEN_ICON, label = labelFor(player, m.amount),
			claimed = bit32.btest(r.mask, bit(i)) }
	end
	return {
		sessionSec = elapsed(player), rungs = rungs, total = #BASE,
		pass = r.pass, passStart = r.pass * PASS_SEC,
		capLeft = Cap.remaining(player), capLimit = Cap.LIMIT, -- extra: the hub's 300-ticket day
	}
end

local function push(player)
	if not player or not player.Parent or not rec[player] then return end
	pcall(function() remote:FireClient(player, "state", snapshot(player)) end)
end

local function reply(player, ok, amount, msg)
	pcall(function() remote:FireClient(player, "result", ok, amount, msg) end)
end

--======================================================================
-- CLAIM
--======================================================================
-- Mark the rung in the SHARED store, in one transaction. Returns "ok"|"claimed"|"locked"|"bad"|"store",
-- plus the amount and the pass it was claimed on.
local function mark(player, index)
	local mine = current(player)
	local result, amount, onPass, merged = "bad", 0, 0, nil
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			local m = merge(normalize(old), mine)
			merged = m
			local rung = rungsFor(m.pass)[index]
			if not rung then result = "bad"; return nil end
			if bit32.btest(m.mask, bit(index)) then result = "claimed"; return nil end
			-- THE CLOCK THE REALMS KEPT (max of the store's and ours), never a number the client sent.
			if m.played < rung.sec then result = "locked"; return nil end
			result, amount, onPass = "ok", rung.amount, m.pass
			local out = { day = m.day, played = m.played, pass = m.pass, mask = bit32.bor(m.mask, bit(index)) }
			merged = roll(out)
			return encode(merged)
		end)
	end)
	if not ok then return "store", 0, 0 end
	if merged then adopt(player, merged) end
	return result, amount, onPass
end

-- Undo a mark whose payout failed -- only on the pass it was made on (rolled over or not).
local function unmark(player, index, onPass)
	local restored = nil
	pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			local r = normalize(old)
			if r.pass == onPass then
				r.mask = bit32.band(r.mask, bit32.bnot(bit(index)))
			elseif r.pass == onPass + 1 and r.mask == 0 then
				r.pass, r.mask = onPass, FULL_MASK - bit(index) -- that claim had finished the pass: reopen it
			else
				return nil
			end
			restored = r
			return encode(r)
		end)
	end)
	if restored and player.Parent then
		restored.played = math.max(restored.played, elapsed(player))
		adopt(player, restored)
	end
end

local function claim(player, index)
	if not live(player) then return end
	local r = live(player)
	local m = rungsFor(r.pass)[index]
	if not m then return end

	if bit32.btest(r.mask, bit(index)) then reply(player, false, 0, "Already claimed."); return end
	if elapsed(player) < m.sec then
		reply(player, false, 0, "Not unlocked yet -- keep playing!"); push(player); return
	end
	if Cap.remaining(player) <= 0 then
		reply(player, false, 0, ("You've reached today's %d-ticket limit -- come back tomorrow!"):format(Cap.LIMIT))
		push(player); return
	end

	local result, amount, onPass = mark(player, index)
	if result == "claimed" then
		reply(player, false, 0, "Already claimed (in another realm)."); push(player); return
	elseif result == "locked" then
		reply(player, false, 0, "Not unlocked yet -- keep playing!"); push(player); return
	elseif result ~= "ok" then
		reply(player, false, 0, "Couldn't reach your save -- try again!"); push(player); return
	end

	local got, reason = Cap.pay(player, amount, "sessionReward")
	if got <= 0 then
		unmark(player, index, onPass) -- nothing was paid: don't eat the rung
		if reason == "cap" then
			reply(player, false, 0, ("You've reached today's %d-ticket limit -- come back tomorrow!"):format(Cap.LIMIT))
		else
			reply(player, false, 0, "Couldn't pay that out -- try again.")
		end
		push(player); return
	end

	print(("[SessionRewards] %s claimed pass %d rung %d -> %d tickets (%d left today)"):format(
		player.Name, onPass, index, got, Cap.remaining(player)))
	reply(player, true, got, ("Claimed  %d Tickets!"):format(got))
	if live(player).pass > onPass then
		reply(player, true, 0, "Pass " .. (onPass + 1) .. " unlocked -- bigger rewards!")
	end
	push(player)
end

remote.OnServerEvent:Connect(function(player, action, index)
	if action ~= "claim" then return end
	index = tonumber(index)
	if not index or busy[player] then return end
	busy[player] = true
	local ok, err = pcall(claim, player, index)
	busy[player] = nil
	if not ok then warn("[SessionRewards] claim error for " .. player.Name .. ": " .. tostring(err)) end
end)

--======================================================================
-- LIFECYCLE
--======================================================================
local function onJoin(player)
	-- Today's record from the shared store: playtime and claims carried in from any realm. A failed read starts
	-- at zero -- harmless, because every save and claim MERGES with the store rather than overwriting it.
	local ok, v = pcall(function() return store:GetAsync(keyFor(player)) end)
	if not player.Parent then return end
	adopt(player, roll(normalize(ok and v or nil)))
	for _, d in ipairs({ 1, 3, 8 }) do
		task.wait(d)
		if player.Parent then push(player) end
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(onJoin, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

Players.PlayerRemoving:Connect(function(player)
	save(player) -- bank this session's playtime for the next realm / rejoin
	rec[player], t0[player], busy[player] = nil, nil, nil
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(save, p) end
	task.wait(2)
end)

-- ONE TIMER FOR THE WHOLE SERVER: push every 20s (corrects client drift, announces the cap changing) and bank
-- playtime every minute, so a crash loses at most a minute of ladder progress.
task.spawn(function()
	local n = 0
	while true do
		task.wait(20)
		n += 1
		for _, p in ipairs(Players:GetPlayers()) do
			if n % 3 == 0 then task.spawn(function() save(p); push(p) end) else push(p) end
		end
	end
end)

print(("[SessionRewards] ready -- %d rungs per pass (5..60 min, 270 tickets), one ladder per day across realms, capped at %d/day"):format(
	#BASE, Cap.LIMIT))
