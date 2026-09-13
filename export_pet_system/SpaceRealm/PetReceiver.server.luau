--======================================================================
-- PetReceiver.server.luau   — PUT THIS IN THE *SPACE REALM* PLACE
-- (ServerScriptService). It is the RECEIVING half of the pet transfer.
--======================================================================
-- The main Fart to Float place (BlackHoleTeleport.server.lua) teleports the
-- player here with their collected pets attached as TeleportData:
--
--     {
--       fromFartToFloat = true,
--       ownedPets   = { [petKey] = { level, height, time, rare, xp } },
--       equippedPet = "<petKey>"  -- the pet that was following them
--     }
--
-- This script reads that payload on join and stages it into the SAME globals
-- the pet code uses:  _G.playerOwnedPets / _G.playerEquippedPet.
--
-- ► IF the Space Realm also contains the pet-rendering scripts (PetSystem +
--   PetFollow + the pet RemoteEvents), this calls _G.petsApplyOnJoin(player)
--   and the equipped pet spawns + follows exactly like on the islands.
-- ► IF it does NOT, the data is still staged in _G.playerOwnedPets so your own
--   Space-Realm follower code can read it. (Ask me for a standalone follower
--   that needs no PetSystem if you want the pet to follow without copying it.)
--======================================================================

local Players = game:GetService("Players")

_G.playerOwnedPets   = _G.playerOwnedPets   or {}
_G.playerEquippedPet = _G.playerEquippedPet or {}
_G.incomingFtFPets   = _G.incomingFtFPets   or {} -- raw payload kept around for custom code

local function countStacks(t)
	local n = 0; for _ in pairs(t or {}) do n += 1 end; return n
end

--======================================================================
-- SERVE the imported pets to the client so your EXISTING "Pets" button can list them.
-- A RemoteFunction the button's open-handler invokes: returns a plain list ->
--   { { key="ButterDuck#R", name="Butter Duck", level=25, rare=true }, ... }
-- (key = the stored pet key; "#R" suffix = the rare/cosmic variant.)
--======================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local getPets = ReplicatedStorage:FindFirstChild("GetSpaceRealmPets")
if not getPets then
	getPets = Instance.new("RemoteFunction")
	getPets.Name = "GetSpaceRealmPets"
	getPets.Parent = ReplicatedStorage
end

local function prettyName(key)
	local base = key:gsub("#R$", "")                       -- drop the rare suffix
	base = base:gsub("(%l)(%u)", "%1 %2")                  -- ButterDuck -> Butter Duck
	return base
end

local function buildOwnedList(player)
	local list = {}
	local equippedKey = _G.playerEquippedPet[player]
	for key, d in pairs(_G.playerOwnedPets[player] or {}) do
		d = (type(d) == "table") and d or {}
		table.insert(list, {
			key      = key,
			name     = prettyName(key),
			level    = d.level or 1,
			rare     = (d.rare == true) or key:match("#R$") ~= nil,
			equipped = (key == equippedKey), -- which pet was following them when they teleported in
		})
	end
	table.sort(list, function(a, b) return a.key < b.key end) -- deterministic order
	return list
end

getPets.OnServerInvoke = function(player)
	return buildOwnedList(player)
end

local function intake(player)
	local data
	pcall(function()
		local jd = player:GetJoinData()
		data = jd and jd.TeleportData
	end)
	if type(data) ~= "table" or data.fromFartToFloat ~= true then
		return -- joined some other way (not via the black hole) -> nothing to import
	end

	_G.incomingFtFPets[player]   = data
	_G.playerOwnedPets[player]   = (type(data.ownedPets) == "table") and data.ownedPets or {}
	_G.playerEquippedPet[player] = data.equippedPet

	print(("[SpaceRealm PetReceiver] %s arrived with %d pet stack(s); equipped=%s")
		:format(player.Name, countStacks(_G.playerOwnedPets[player]), tostring(data.equippedPet)))

	-- If this place has the pet scripts, render them. Deferred so PetSystem has finished its own init,
	-- and retried briefly in case this receiver ran before PetSystem set up the handshake.
	task.spawn(function()
		for _ = 1, 50 do                       -- up to ~5s waiting for PetSystem
			if _G.petsApplyOnJoin then
				pcall(_G.petsApplyOnJoin, player)
				return
			end
			task.wait(0.1)
		end
		warn("[SpaceRealm PetReceiver] no _G.petsApplyOnJoin in this place — pets are staged in _G.playerOwnedPets but nothing rendered them. Copy PetSystem/PetFollow here, or ask for a standalone follower.")
	end)
end

Players.PlayerAdded:Connect(intake)
for _, p in ipairs(Players:GetPlayers()) do intake(p) end -- handle anyone already in (script loaded late)
Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFPets[p] = nil
	-- If PetSystem is present it owns the lifecycle of these globals (and may still need them during its own
	-- leave/save handler, whose run-order vs this one isn't guaranteed) -> don't yank them out from under it.
	-- If PetSystem is NOT present, nothing else ever clears them, so we must, or every leaver leaks a table.
	if not _G.petsApplyOnJoin then
		_G.playerOwnedPets[p]   = nil
		_G.playerEquippedPet[p] = nil
	end
end)

print("[SpaceRealm PetReceiver] ready — importing collected pets from Fart to Float teleports.")
