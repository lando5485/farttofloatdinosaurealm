-- ============================================================================
-- GUT SKIN SERVICE (server) — cosmetic gut-skin ownership, PLAYTIME unlocks, and equip. All validated here.
--   * Skins are EARNED BY CUMULATIVE PLAYTIME (GutSkins.UnlockMinutes), tracked server-side and persisted.
--   * Owns _G.playerOwnedGutSkins / _G.playerEquippedGutSkin / _G.playerPlaytimeSec (PlayerStats persists them).
--   * EquipGutSkin(skinId) -> validates OWNERSHIP, equips, re-skins the gut, saves, returns state.
--   * GetGutSkins() -> {owned, equipped, playtimeSec}.  GutSkinState pushes the same on changes.
--   * GutSkinUnlocked fires when playtime crosses a threshold -> client shows a banner.
--   * _G.grantGutSkin(player, skinId, autoEquip?) -> reuse from crates / codes / events (ignores playtime).
--   Skins are COSMETIC ONLY: equipping never changes the gut tier size or power.
-- ============================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local GutSkins = require(RS:WaitForChild("Shared"):WaitForChild("GutSkins"))

_G.playerOwnedGutSkins   = _G.playerOwnedGutSkins or {}   -- [player] = { Default=true, ... }
_G.playerEquippedGutSkin = _G.playerEquippedGutSkin or {} -- [player] = skin id
_G.playerPlaytimeSec     = _G.playerPlaytimeSec or {}     -- [player] = TOTAL cumulative seconds played (all sessions)

local function getOrCreate(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if not inst then inst = Instance.new(className); inst.Name = name; inst.Parent = parent end
	return inst
end
local EquipGutSkin   = getOrCreate(RS, "RemoteFunction", "EquipGutSkin")  -- client invoke -> {ok, msg, equipped, owned, playtimeSec}
local GetGutSkins    = getOrCreate(RS, "RemoteFunction", "GetGutSkins")   -- client invoke -> {owned, equipped, playtimeSec}
local GutSkinState   = getOrCreate(RS, "RemoteEvent",    "GutSkinState")  -- server -> client: {owned, equipped, playtimeSec}
local GutSkinUnlocked= getOrCreate(RS, "RemoteEvent",    "GutSkinUnlocked")-- server -> client: {id, displayName} (playtime unlock)

local function owned(p)
	local o = _G.playerOwnedGutSkins[p]
	if type(o) ~= "table" then o = { Default = true }; _G.playerOwnedGutSkins[p] = o end
	o.Default = true -- everyone always owns Default
	return o
end
local function playtime(p)
	local s = _G.playerPlaytimeSec[p]
	if type(s) ~= "number" then s = 0; _G.playerPlaytimeSec[p] = s end
	return s
end
local function equippedId(p) return _G.playerEquippedGutSkin[p] or "Default" end
local function stateFor(p) return { owned = owned(p), equipped = equippedId(p), playtimeSec = playtime(p) } end
local function pushState(p) pcall(function() GutSkinState:FireClient(p, stateFor(p)) end) end

GetGutSkins.OnServerInvoke = function(p) return stateFor(p) end

EquipGutSkin.OnServerInvoke = function(p, skinId)
	if type(skinId) ~= "string" or not GutSkins.exists(skinId) then return { ok = false, msg = "Unknown skin" } end
	-- SERVER-SIDE ownership check (never trust the client): must own it, or it's Default (free for everyone).
	if skinId ~= "Default" and not owned(p)[skinId] then return { ok = false, msg = "Not unlocked yet" } end
	_G.playerEquippedGutSkin[p] = skinId
	if _G.refreshGutSkin then pcall(_G.refreshGutSkin, p) end       -- BellySystem re-paints the gut (tier size kept)
	if _G.savePlayerData then pcall(_G.savePlayerData, p, "gutskin") end
	pushState(p)
	return { ok = true, equipped = skinId, owned = owned(p), playtimeSec = playtime(p) }
end

-- GRANT a skin from ANY source (playtime auto-grant below, or crates / codes / events). autoEquip optional.
_G.grantGutSkin = function(p, skinId, autoEquip)
	if not (p and GutSkins.exists(skinId)) then return false end
	local isNew = not owned(p)[skinId]
	owned(p)[skinId] = true
	if autoEquip then
		_G.playerEquippedGutSkin[p] = skinId
		if _G.refreshGutSkin then pcall(_G.refreshGutSkin, p) end
	end
	if _G.savePlayerData then pcall(_G.savePlayerData, p, "grantskin") end
	pushState(p)
	if isNew then print(("[GutSkins] granted '%s' to %s%s"):format(skinId, p.Name, autoEquip and " (equipped)" or "")) end
	return true
end

-- AUTO-GRANT: grant any playtime skin whose threshold the player's total playtime has crossed (skips owned).
local function checkUnlocks(p)
	local mins = playtime(p) / 60
	local o = owned(p)
	for _, id in ipairs(GutSkins.Order) do
		local skin = GutSkins.get(id)
		if skin and skin.source == "playtime" and not o[id] and mins >= GutSkins.unlockMinutes(id) then
			o[id] = true
			if _G.savePlayerData then pcall(_G.savePlayerData, p, "skinunlock") end
			pcall(function() GutSkinUnlocked:FireClient(p, { id = id, displayName = skin.displayName }) end) -- -> client banner
			print(("[GutSkins] %s reached %d min -> unlocked '%s'"):format(p.Name, math.floor(mins), id))
		end
	end
end

-- PLAYTIME TICK: every 60s add a minute to each player's TOTAL, check unlocks, and refresh the client state.
-- (PlayerStats autosave + leave-save persist _G.playerPlaytimeSec, so progress survives a crash.)
task.spawn(function()
	while true do
		task.wait(60)
		for _, p in ipairs(Players:GetPlayers()) do
			_G.playerPlaytimeSec[p] = playtime(p) + 60
			checkUnlocks(p)
			pushState(p)
		end
	end
end)

local function onJoin(p)
	owned(p); playtime(p) -- ensure tables exist even before PlayerStats finishes loading the save
	task.delay(2.5, function()
		if not p.Parent then return end
		checkUnlocks(p)                                   -- grant anything already earned from saved playtime
		if _G.refreshGutSkin then pcall(_G.refreshGutSkin, p) end -- apply the equipped skin to the freshly-built gut
		pushState(p)
	end)
	p.CharacterAdded:Connect(function()
		task.delay(1.2, function() if p.Parent and _G.refreshGutSkin then pcall(_G.refreshGutSkin, p) end end) -- re-skin on respawn
	end)
end
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
-- NOTE: don't clear the _G tables on PlayerRemoving here -- PlayerStats' save handler reads them during the
-- same removal, and clearing first would race it (tables are tiny + per-session).

print("[GutSkins] service ready (playtime unlocks; EquipGutSkin / GetGutSkins / GutSkinState / GutSkinUnlocked)")
