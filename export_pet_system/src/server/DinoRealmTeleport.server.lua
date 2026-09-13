--======================================================================
-- DinoRealmTeleport.server.lua  (Script)   [SENDING PLACE]
--======================================================================
-- TEMPLATE -- a copy of the BlackHoleTeleport pattern, retargeted at the DINO REALM place.
-- Put this Script in whichever place the portal LIVES IN (e.g. the Space Realm place, if the portal
-- is on the space island). The matching client half is DinoPortal.client.luau.
--
-- THE PATTERN (do not deviate -- this is the secure shape):
--   1. CLIENT touches the portal -> fires DinoRealmEnterEvent:FireServer() with NO ARGUMENTS.
--      The client never says where to go, and never teleports itself.
--   2. SERVER (here) validates: gate/lock + per-player debounce.
--   3. SERVER replies with a STATUS STRING ("traveling"/"locked"/"error") so the client can show a
--      message. The client's only job is to render that string.
--   4. SERVER calls TeleportService:TeleportAsync with a TeleportData payload.
--      The DINO REALM place reads it back via player:GetJoinData().TeleportData.
--
-- DINO_REALM_PLACE_ID is set below; if it is ever reset to 0 this script refuses to teleport (it warns).
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

-- FART TO FLOAT [DINO REALM] -- a place inside the SAME universe/experience (Space Realm is 125063266868039).
local DINO_REALM_PLACE_ID = 110777788409412

-- ⚠ TESTER LOCK -- same shape as the Space Realm gate. Flip to false to open it to everyone.
--   ★ OPEN / REMOVE THIS GATE BEFORE PUBLIC LAUNCH. ★
local DINO_REALM_TESTERS_ONLY = true
local TESTER_IDS   = { [1086836724] = true, [1418148401] = true, [3911540303] = true }            -- lando5485, Broskie310111, Itsmaddmax1
-- lowercase keys, lookup lower-cases too -- a casing mismatch in the account name must not lock a tester out
local TESTER_NAMES = { ["lando5485"] = true, ["broskie310111"] = true, ["itsmaddmax1"] = true }
local function isTester(plr) return TESTER_IDS[plr.UserId] == true or TESTER_NAMES[string.lower(plr.Name)] == true end
local function allowed(plr) return (not DINO_REALM_TESTERS_ONLY) or isTester(plr) end

-- getOrCreate, so a missing project.json entry can't break the remote. The client WaitForChild's this name.
local enterEvent = ReplicatedStorage:FindFirstChild("DinoRealmEnterEvent")
if not enterEvent then
	enterEvent = Instance.new("RemoteEvent"); enterEvent.Name = "DinoRealmEnterEvent"; enterEvent.Parent = ReplicatedStorage
end

local teleporting = {} -- [player] = true -- server-side debounce: never double-teleport

--======================================================================
-- THE PAYLOAD
--======================================================================
-- Defined ONCE in ReplicatedStorage/Shared/RealmTransfer, shared with RealmPortals.server.lua so both doors
-- into the Dino Realm send the same shape (the receiver over there should never have to guess which door a
-- player used). See that module for what travels, what deliberately doesn't, and the size guard.
--
-- FALLBACK: if the module can't load, we still teleport -- with the old pets-only payload. A broken require
-- must not strand players at a portal that refuses to open; the worst it should cost is their cosmetics.
local RealmTransfer
do
	local ok, mod = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 20)
		return shared and require(shared:WaitForChild("RealmTransfer", 20))
	end)
	if ok then RealmTransfer = mod
	else warn("[DinoRealm] RealmTransfer module unavailable (" .. tostring(mod) .. ") -- falling back to a pets-only payload") end
end

local function buildTransferPayload(player, realmKey)
	if RealmTransfer then
		local ok, payload = pcall(function() return RealmTransfer.build(player, realmKey) end)
		if ok and type(payload) == "table" then return payload end
		warn("[DinoRealm] RealmTransfer.build failed (" .. tostring(payload) .. ") -- falling back to a pets-only payload")
	end
	return { -- the pre-module payload: enough for the pets to arrive, just without their cosmetics
		fromFartToFloat = true,
		payloadVersion  = 1,
		fromPlaceId     = game.PlaceId,
		homePlaceId     = game.PlaceId,
		toRealm         = realmKey,
		userId          = player.UserId,
		ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},
		equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil,
	}
end

enterEvent.OnServerEvent:Connect(function(player)
	if not player or teleporting[player] then return end

	if DINO_REALM_PLACE_ID == 0 then
		warn("[DinoRealm] DINO_REALM_PLACE_ID is not set -- cannot teleport")
		pcall(function() enterEvent:FireClient(player, "error") end)
		return
	end

	if not allowed(player) then
		print("[DinoRealm] " .. player.Name .. " touched portal -- BLOCKED by tester lock")
		pcall(function() enterEvent:FireClient(player, "locked") end) -- client shows "Coming soon!"
		return
	end

	teleporting[player] = true
	pcall(function() enterEvent:FireClient(player, "traveling") end) -- client shows "Traveling to Dino Realm..."
	task.wait(1.2) -- brief deliberate pause so the transition reads as intentional, THEN teleport
	if not player.Parent then teleporting[player] = nil; return end -- they left during the pause

	local ok, err = pcall(function()
		-- CARRY STATE ACROSS. TeleportData is set server-side here and read on the other side via
		-- player:GetJoinData().TeleportData. `fromFartToFloat` is the marker the receiver checks so it
		-- can tell a real portal arrival from someone who just joined the Dino place directly.
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData(buildTransferPayload(player, "dino"))
		TeleportService:TeleportAsync(DINO_REALM_PLACE_ID, { player }, options)
	end)

	print(string.format("[DinoRealm] teleport %s -> DinoRealm (placeId %d) result: %s",
		player.Name, DINO_REALM_PLACE_ID, ok and "ok" or ("err: " .. tostring(err))))

	if not ok then
		teleporting[player] = nil -- failed -> let them retry
		pcall(function() enterEvent:FireClient(player, "error") end)
	end
end)

Players.PlayerRemoving:Connect(function(p) teleporting[p] = nil end)

print("[DinoRealm] teleport handler ready (placeId " .. DINO_REALM_PLACE_ID ..
	", testersOnly=" .. tostring(DINO_REALM_TESTERS_ONLY) .. ")")
