--!nonstrict
-- PlayerState (ServerScriptService/PlayerState) — SERVER-ONLY data authority module.
--
-- Owns the persistent player state that the Mystery Meteor Crate system depends on:
--   * lastCrateClaim  (unix os.time of last successful claim; 0 = never)
--   * owned cosmetics (set of cosmetic ids)
--   * equipped cosmetic per type
--
-- Persistence is a SEPARATE DataStore ("CrateState_v1") keyed by UserId, so it NEVER clobbers
-- the food-game save in PlayerStats.server.lua ("PlayerData_v1"). On first require this module
-- wires PlayerAdded/Removing load+save, an autosave loop, BindToClose, the CosmeticRemotes/
-- EquipCosmetic RemoteFunction, and the StateRemotes snapshot stream (Remotes.getRequestState /
-- getStateChanged). All grants/timer-resets happen here; the client only animates.
--
-- API:
--   PlayerState.getLastCrateClaim(player) -> number
--   PlayerState.setLastCrateClaim(player, t)   (marks dirty + pushes snapshot)
--   PlayerState.ownsCosmetic(player, id) -> boolean
--   PlayerState.grantCosmetic(player, id) -> boolean (false if unknown id / already owned)
--   PlayerState.ownsAllWinnable(player) -> boolean
--   PlayerState.equipCosmetic(player, id) -> boolean
--   PlayerState.isLoaded(player) -> boolean      (false => treat as "no_profile")
--   PlayerState.addCoins(player, n)             (adds to the food-game leaderstats Coins)
--   PlayerState.pushSnapshot(player)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmeticConfig = require(Shared:WaitForChild("CosmeticConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerState = {}

local DATASTORE_NAME = "CrateState_v1"
local AUTOSAVE_INTERVAL = 120

-- ===== in-memory state =====
-- states[player] = { lastCrateClaim=number, owned={[id]=true}, equipped={[type]=id}, dirty=bool, loaded=bool }
local states: { [Player]: any } = {}

-- ===== DataStore (pcall-guarded; Studio without API access -> nil -> runs on defaults, no persist) =====
local store = nil
do
	local ok, ds = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = ds
	else
		warn("[PlayerState] DataStore unavailable (" .. tostring(ds) .. ") — crate state will not persist this session")
	end
end

local function freshState()
	-- lastStayReward: os.time() of the last retention "stay" crate (0 = never). Lives HERE rather than in a
	-- store of its own because it is the same shape and lifetime as lastCrateClaim, and because the whole
	-- point of persisting it is that leaving and rejoining must NOT reset it -- so it has to ride the save
	-- that already survives a rejoin.
	local s = { lastCrateClaim = 0, lastStayReward = 0, owned = {}, equipped = {}, dirty = false, loaded = false }
	-- Default-owned starters: auto-owned + equipped, one Common per type.
	for _, id in ipairs(CosmeticConfig.DEFAULT_OWNED) do
		local item = CosmeticConfig.BY_ID[id]
		if item then
			s.owned[id] = true
			s.equipped[item.type] = id
		end
	end
	return s
end

-- ===== snapshot =====
-- The snapshot carries lastCrateClaim (what the crate UI needs) plus owned/equipped for any
-- future UI; client readiness is derived purely from lastCrateClaim + the shared cooldown.
local function buildSnapshot(player)
	local s = states[player]
	if not s then return nil end
	local ownedList = {}
	for id in pairs(s.owned) do
		table.insert(ownedList, id)
	end
	return {
		lastCrateClaim = s.lastCrateClaim or 0,
		ownedCosmetics = ownedList,
		equipped = s.equipped,
	}
end

function PlayerState.pushSnapshot(player)
	local snap = buildSnapshot(player)
	if not snap then return end
	pcall(function()
		Remotes.getStateChanged():FireClient(player, snap)
	end)
end

-- ===== load / save =====
local function loadPlayer(player)
	local s = freshState()
	states[player] = s
	if store then
		local key = tostring(player.UserId)
		local ok, data = pcall(function() return store:GetAsync(key) end)
		if ok and type(data) == "table" then
			s.lastCrateClaim = tonumber(data.lastCrateClaim) or 0
			-- absent in saves written before the retention feature existed -> 0 = never given, so an
			-- existing player is eligible the first time they go to leave. That is the intended migration.
			s.lastStayReward = tonumber(data.lastStayReward) or 0
			if type(data.owned) == "table" then
				for _, id in ipairs(data.owned) do
					if CosmeticConfig.BY_ID[id] then s.owned[id] = true end
				end
			end
			if type(data.equipped) == "table" then
				for typ, id in pairs(data.equipped) do
					if CosmeticConfig.BY_ID[id] then s.equipped[typ] = id end
				end
			end
		elseif not ok then
			-- Load failed: don't persist over a possibly-real save this session.
			warn("[PlayerState] load failed for " .. player.Name .. ": " .. tostring(data))
			s.loaded = false
			PlayerState.pushSnapshot(player)
			return
		end
	end
	s.loaded = true
	PlayerState.pushSnapshot(player)
end

local function savePlayer(player, trigger)
	local s = states[player]
	if not s or not s.loaded then return end
	if not s.dirty then return end
	if not store then return end
	local ownedList = {}
	for id in pairs(s.owned) do table.insert(ownedList, id) end
	local data = { lastCrateClaim = s.lastCrateClaim or 0, lastStayReward = s.lastStayReward or 0,
		owned = ownedList, equipped = s.equipped }
	local ok, err = pcall(function() store:SetAsync(tostring(player.UserId), data) end)
	if ok then
		s.dirty = false
	else
		warn("[PlayerState] save (" .. tostring(trigger) .. ") failed for " .. player.Name .. ": " .. tostring(err))
	end
end

-- ===== public API =====
function PlayerState.isLoaded(player)
	local s = states[player]
	return s ~= nil and s.loaded == true
end

function PlayerState.getLastCrateClaim(player)
	local s = states[player]
	return s and s.lastCrateClaim or 0
end

function PlayerState.setLastCrateClaim(player, t)
	local s = states[player]
	if not s then return end
	s.lastCrateClaim = t
	s.dirty = true
	PlayerState.pushSnapshot(player)
end

-- ===== RETENTION STAY REWARD =====
-- Read/stamped by RetentionService. os.time() (absolute), NOT os.clock(), so the rolling 24h is comparable
-- across sessions -- an os.clock() value would reset to ~0 every server start and hand out a crate per join.
function PlayerState.getLastStayReward(player)
	local s = states[player]
	return s and s.lastStayReward or 0
end

function PlayerState.setLastStayReward(player, t)
	local s = states[player]
	if not s then return end
	s.lastStayReward = t
	s.dirty = true
end

-- Force an immediate write. RetentionService calls this the moment it grants on a LEAVE attempt: the player
-- is on their way out, and the PlayerRemoving save would usually catch it -- but "usually" is not good enough
-- when the failure mode is rejoining to dodge the 24h cooldown.
function PlayerState.save(player, trigger)
	savePlayer(player, trigger or "forced")
end

function PlayerState.ownsCosmetic(player, id)
	local s = states[player]
	return (s and s.owned[id]) == true
end

function PlayerState.grantCosmetic(player, id)
	local s = states[player]
	if not s then return false end
	if not CosmeticConfig.BY_ID[id] then return false end
	if s.owned[id] then return false end
	s.owned[id] = true
	s.dirty = true
	PlayerState.pushSnapshot(player)
	return true
end

function PlayerState.ownsAllWinnable(player)
	local s = states[player]
	if not s then return false end
	for _, item in ipairs(CosmeticConfig.WINNABLE) do
		if not s.owned[item.id] then return false end
	end
	return true
end

function PlayerState.equipCosmetic(player, id)
	local s = states[player]
	if not s then return false end
	local item = CosmeticConfig.BY_ID[id]
	if not item then return false end
	if not s.owned[id] then return false end -- can only equip what you own
	s.equipped[item.type] = id
	s.dirty = true
	PlayerState.pushSnapshot(player)
	return true
end

-- Adds coins to the food-game leaderstats (the crate's coin fallback / owns-all reward).
function PlayerState.addCoins(player, n)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	if coins then coins.Value = coins.Value + n end
	local tce = ls:FindFirstChild("TotalCoinsEarned")
	if tce then tce.Value = tce.Value + n end
end

-- ===== setup (runs once on first require, server only) =====
local started = false
local function start()
	if started or not RunService:IsServer() then return end
	started = true

	-- CosmeticRemotes/EquipCosmetic (RemoteFunction) — reused by the crate reveal's EQUIP NOW.
	local cosmeticRemotes = ReplicatedStorage:FindFirstChild("CosmeticRemotes")
	if not cosmeticRemotes then
		cosmeticRemotes = Instance.new("Folder")
		cosmeticRemotes.Name = "CosmeticRemotes"
		cosmeticRemotes.Parent = ReplicatedStorage
	end
	local equip = cosmeticRemotes:FindFirstChild("EquipCosmetic")
	if not equip then
		equip = Instance.new("RemoteFunction")
		equip.Name = "EquipCosmetic"
		equip.Parent = cosmeticRemotes
	end
	equip.OnServerInvoke = function(player, id)
		if type(id) ~= "string" then return { ok = false } end
		local ok = PlayerState.equipCosmetic(player, id)
		return { ok = ok }
	end

	-- Snapshot handshake: client asks for fresh state once its UI is built.
	Remotes.getRequestState().OnServerEvent:Connect(function(player)
		PlayerState.pushSnapshot(player)
	end)

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player, "leave")
		states[player] = nil
	end)
	-- Any players already present (module required after join).
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, p)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, p in ipairs(Players:GetPlayers()) do
				savePlayer(p, "autosave")
			end
		end
	end)

	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			savePlayer(p, "BindToClose")
		end
		task.wait(1)
	end)
end

start()

return PlayerState
