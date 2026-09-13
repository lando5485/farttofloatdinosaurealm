--======================================================================
-- SocialRewards.server.lua  (Script -> ServerScriptService)
--======================================================================
-- The "support the game" rewards every big game has: LIKE, FAVOURITE, and JOIN THE GROUP. Each is a ONE-TIME
-- claim worth +5 LEVELS on the pet you have equipped -- pick which pet gets it by equipping it first.
--
-- WHAT'S VERIFIABLE, WHAT ISN'T:
--   * GROUP is real -- IsInGroup is checked server-side, so the reward only pays a genuine member.
--   * LIKE / FAVOURITE cannot be detected by any Roblox API (there is no server-side "did they like it?").
--     Every game handles this the same way: the button opens the game page and the reward is granted on the
--     claim. It's trust-based by necessity, but it's ONE-TIME and persisted, so it can't be farmed.
--
-- The claimed flags PERSIST (a dedicated DataStore), so a reward can't be claimed again next session.
--======================================================================
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local GROUP_ID    = 758781978 -- MLR Studios (same group RewardsService rewards)
local LEVELS      = 5         -- levels granted per social reward
local BONUS_LEVELS = 5        -- extra levels, once, when all three are done (paid automatically)
local REWARDS     = { like = true, favorite = true, group = true } -- valid claim keys

local store = DataStoreService:GetDataStore("SocialRewards_v1")

local function getOrCreate(className, name)
	local o = ReplicatedStorage:FindFirstChild(name)
	if not o then o = Instance.new(className); o.Name = name; o.Parent = ReplicatedStorage end
	return o
end
-- client -> server: fire "claim", which. server -> client: fire "state", {like=,favorite=,group=} | "result", which, ok, msg
local remote = getOrCreate("RemoteEvent", "SocialRewardEvent")

local claimed    = {} -- [player] = { like=bool, favorite=bool, group=bool }  (loaded from the store)
local groupMember = {} -- [player] = bool

local function keyFor(userId) return "Player_" .. tostring(userId) end

local function load(player)
	local data
	local ok = pcall(function() data = store:GetAsync(keyFor(player.UserId)) end)
	claimed[player] = (ok and type(data) == "table") and data or {}
end
-- CLAIMS ARE TAKEN IN THE STORE, never SetAsync'd from this server's copy: the store is shared by every realm,
-- and writing back a table loaded at join would wipe a claim another realm made since.
local busy = {} -- [player] = true while a claim is in flight
-- Returns "ok" (now claimed), "claimed" (any realm already had it) or "store" (couldn't reach it).
local function reserve(player, which)
	local result, seen = "store", nil
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			local t = {}
			if type(old) == "table" then for k, v in pairs(old) do t[k] = v end end
			seen = t
			if t[which] then result = "claimed"; return nil end
			result = "ok"
			t[which] = true
			return t
		end)
	end)
	if not ok then return "store" end
	if seen then claimed[player] = seen end
	return result
end
-- Give a claim back when the reward didn't land.
local function release(player, which)
	pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			if type(old) ~= "table" or not old[which] then return nil end
			old[which] = nil
			return old
		end)
	end)
	if claimed[player] then claimed[player][which] = nil end
end

local function pushState(player)
	local c = claimed[player] or {}
	pcall(function()
		remote:FireClient(player, "state", {
			like = c.like == true, favorite = c.favorite == true, group = c.group == true,
			bonus = c.bonus == true, -- the all-three bonus has been paid
			isMember = groupMember[player] == true, groupId = GROUP_ID,
		})
	end)
end

-- ALL-THREE BONUS: +BONUS_LEVELS on the equipped pet, once across every realm, paid automatically when all three
-- are done. Also retried on join and whenever a finished row is pressed, so a bonus held back (maxed pet, nothing
-- equipped, a store blip) is never lost for good.
-- `notify` = the player pressed the bonus row themselves, so tell them why nothing happened.
local function tryBonus(player, notify)
	local function say(msg)
		if notify then pcall(function() remote:FireClient(player, "result", "bonus", false, msg) end) end
	end
	local c = claimed[player] or {}
	if not (c.like and c.favorite and c.group) or c.bonus or busy[player] then return end
	local petKey = _G.playerEquippedPet and _G.playerEquippedPet[player]
	if not petKey then say("Equip a pet first -- it gets the bonus levels!"); return end
	busy[player] = true
	if reserve(player, "bonus") == "ok" then
		local extra = (_G.petAddLevels and _G.petAddLevels(player, petKey, BONUS_LEVELS)) or 0
		if extra > 0 then
			print(("[Social] %s finished all three -> bonus +%d levels"):format(player.Name, extra))
			pcall(function() remote:FireClient(player, "result", "bonus", true, ("All three done!  Bonus +%d levels!"):format(extra)) end)
		else
			release(player, "bonus")
			say("That pet is already max level -- equip another, then tap the bonus!")
		end
	else
		say("Couldn't reach your save -- try again!")
	end
	busy[player] = nil
	pushState(player)
end

remote.OnServerEvent:Connect(function(player, action, which)
	-- The ALL-THREE row is pressable while its bonus is unpaid (e.g. it was held back by a maxed pet).
	if action == "claim" and which == "bonus" then tryBonus(player, true); return end
	if action ~= "claim" or not REWARDS[which] then return end
	claimed[player] = claimed[player] or {}
	if claimed[player][which] then
		pcall(function() remote:FireClient(player, "result", which, false, "Already claimed") end)
		tryBonus(player)
		return
	end

	-- GROUP is the one we can actually verify.
	if which == "group" and not groupMember[player] then
		pcall(function() remote:FireClient(player, "result", which, false, "Join the group first, then rejoin!") end)
		return
	end

	-- pick the pet to level: the one they have EQUIPPED. No pet equipped -> tell them.
	local petKey = _G.playerEquippedPet and _G.playerEquippedPet[player]
	if not petKey then
		pcall(function() remote:FireClient(player, "result", which, false, "Equip a pet first -- it gets the +5 levels!") end)
		return
	end
	-- CROSS-REALM: every realm is a place in one experience and uses this same store + key, so a reward claimed in
	-- the Food Realm is claimed here too. Take it in the STORE first, in one transaction (not from what this
	-- server loaded at join), so two realms can't both pay it; give it back if the levels don't land.
	if busy[player] then return end
	busy[player] = true
	local taken = reserve(player, which)
	if taken ~= "ok" then
		busy[player] = nil
		pcall(function()
			remote:FireClient(player, "result", which, false,
				taken == "claimed" and "Already claimed (in another realm)" or "Couldn't reach your save -- try again!")
		end)
		pushState(player)
		return
	end

	local added = (_G.petAddLevels and _G.petAddLevels(player, petKey, LEVELS)) or 0
	if added <= 0 then
		-- equipped pet is already maxed (or couldn't be resolved) -> don't consume the claim
		release(player, which)
		busy[player] = nil
		pcall(function() remote:FireClient(player, "result", which, false, "That pet is already max level -- equip another!") end)
		return
	end
	busy[player] = nil
	print(("[Social] %s claimed '%s' -> +%d levels on %s"):format(player.Name, which, added, tostring(petKey)))
	pcall(function() remote:FireClient(player, "result", which, true, ("+%d levels!"):format(added)) end)

	tryBonus(player)
	pushState(player)
end)

local function onAdded(player)
	load(player)
	-- IsInGroup caches per session, so someone who joins mid-session must rejoin to be seen as a member.
	task.spawn(function()
		local ok, inGroup = pcall(function() return player:IsInGroup(GROUP_ID) end)
		groupMember[player] = ok and inGroup or false
		task.wait(3) -- let the client build its UI
		pushState(player)
		tryBonus(player)
	end)
end

Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end
Players.PlayerRemoving:Connect(function(p) claimed[p] = nil; groupMember[p] = nil end)

print(("[Social] rewards ready -- like / favourite / group, +%d pet levels each, one-time"):format(LEVELS))
