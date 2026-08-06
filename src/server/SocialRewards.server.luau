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
local function persist(player)
	pcall(function() store:SetAsync(keyFor(player.UserId), claimed[player] or {}) end)
end

local function pushState(player)
	local c = claimed[player] or {}
	pcall(function()
		remote:FireClient(player, "state", {
			like = c.like == true, favorite = c.favorite == true, group = c.group == true,
			isMember = groupMember[player] == true, groupId = GROUP_ID,
		})
	end)
end

remote.OnServerEvent:Connect(function(player, action, which)
	if action ~= "claim" or not REWARDS[which] then return end
	claimed[player] = claimed[player] or {}
	if claimed[player][which] then
		pcall(function() remote:FireClient(player, "result", which, false, "Already claimed") end)
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
	local added = (_G.petAddLevels and _G.petAddLevels(player, petKey, LEVELS)) or 0
	if added <= 0 then
		-- equipped pet is already maxed (or couldn't be resolved) -> don't consume the claim
		pcall(function() remote:FireClient(player, "result", which, false, "That pet is already max level -- equip another!") end)
		return
	end

	claimed[player][which] = true
	task.spawn(persist, player)
	print(("[Social] %s claimed '%s' -> +%d levels on %s"):format(player.Name, which, added, tostring(petKey)))
	pcall(function() remote:FireClient(player, "result", which, true, ("+%d levels!"):format(added)) end)
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
	end)
end

Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end
Players.PlayerRemoving:Connect(function(p) claimed[p] = nil; groupMember[p] = nil end)

print(("[Social] rewards ready -- like / favourite / group, +%d pet levels each, one-time"):format(LEVELS))
