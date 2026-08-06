--======================================================================
-- ArrivalReceiver.server.luau  (Server Script)   [RECEIVING PLACE — the DINO REALM]
--======================================================================
--[[
	The far half of DinoRift.server.luau (which lives in the Space Realm place). It pairs with
	ArrivalCinematic.client.luau.

	The sending place attached a payload with TeleportOptions:SetTeleportData{...}. Over here we read it
	back with player:GetJoinData().TeleportData. This is the ONLY way state crosses a place boundary —
	_G, workspace and leaderstats do NOT come with the player.

	SECURITY: GetJoinData() is filled in by the SERVER on the sending side, so it is trustworthy for
	things that matter. The client-side GetLocalPlayerTeleportData() used by ArrivalCinematic is
	spoofable — that is why the cinematic only ever uses it for COSMETICS. Keep that split.

	GetJoinData() is EMPTY for anyone who opens the Dino Realm place directly from the Roblox site, so
	we check the `fromFartToFloat` marker before trusting anything. A direct join must read as a normal
	fresh start, not as a corrupt arrival.
]]
--======================================================================
-- ⚠ THE PETS DO NOT COME ACROSS, AND THEY MUST NOT.
--======================================================================
-- The sender ships `_G.playerOwnedPets[player]` verbatim from the SPACE REALM. That table is keyed by
-- the SPACE catalog — BroccoliPet, CoconutCrab, ButterDuck, BurritoArmadillo — which has NOTHING in
-- common with this game's (StegoPet, RaptorPet, SharkPet, TriceratopsPet, SpinosaurusPet,
-- TyrannosaurusPet).
--
-- The stock version of this file did `_G.playerOwnedPets[player] = data.ownedPets`, which is not merely
-- useless here, it is DESTRUCTIVE:
--
--   * PetUpgrades' ownsPet() would return TRUE for "BroccoliPet" (it just checks that table), so
--     awardXP() pours every point of XP into it — PetUpgrades.server.luau:168.
--   * sendInventory() only iterates this game's PETS catalog, so the Hub still reads "No Pets Unlocked".
--   * PetFollow's EQUIP_TMPL has no entry for it (PetFollow.client.luau:561), so no follower spawns —
--     it just warns "has no template mapping".
--
-- Net effect: the arriving player gets an invisible equipped pet that silently eats all their XP, and
-- no real dino pet can gain a single point while it stays equipped.
--
-- So the payload is FILTERED, not merged. PetUpgrades owns the catalog, so it owns the filter
-- (_G.petsRestoreFromArrival). Anything it rejects is kept read-only in _G.arrivedSpacePets, where a
-- future "you brought your Broccoli Bunny with you" feature can find it without touching live pet state.
--======================================================================
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")

_G.incomingFtFData  = _G.incomingFtFData  or {} -- [player] = the whole TeleportData payload
_G.arrivedSpacePets = _G.arrivedSpacePets or {} -- [player] = their SPACE REALM pet table (read-only souvenir)

-- ===== FOOD REALM PETS -> CLIENT (the Pet Hub's FOOD tab) =====
-- The Hub shows the food-realm collection read-only, so the client just needs a copy of
-- _G.arrivedSpacePets. This script owns that table, so the remote lives here. Push on
-- arrival + answer client requests (covers whichever side loads first).
local FoodPetsEvent = RS:FindFirstChild("FoodPetsEvent")
if not FoodPetsEvent then
	FoodPetsEvent = Instance.new("RemoteEvent"); FoodPetsEvent.Name = "FoodPetsEvent"; FoodPetsEvent.Parent = RS
end
local function sendFoodPets(player)
	pcall(function() FoodPetsEvent:FireClient(player, _G.arrivedSpacePets[player] or {}) end)
end
FoodPetsEvent.OnServerEvent:Connect(sendFoodPets)

-- How long we hold them still on the entrance while their screen is black.
--
-- Must cover ArrivalCinematic's full wake-up in the case where it reveals the world ITSELF -- the path
-- taken when there's no intro to hand off to, e.g. a returning player who has already seen it
-- (1.0 hold + 1.4 + 0.9 + 0.8 card-out + 2.4 fade ≈ 6.5s). Keep a little margin; if you retime the
-- cinematic, retime this.
--
-- On the HANDOFF path this timer doesn't decide anything: the tower intro will have taken the body
-- over long before it expires, and the check below leaves it alone.
local FROZEN_SECONDS = 7.0

local ENTRANCE_ISLAND = "island1" -- Nesting Nook, the bottom of the tower

local function countKeys(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

-- Put them on the entrance, then hold them there for the length of the fade-up.
--
-- Both halves have to happen in ONE task, in this order: while the screen is BLACK the player is still
-- a live character in a live world — they can walk, and they can walk off a cliff they cannot see.
-- (WalkSpeed alone isn't enough: gravity still applies.)
local function holdAtEntrance(player)
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end

		-- Their screen is black right now, so this move is completely invisible. That is the whole
		-- point of the black — any repositioning done before the fade-up simply never happened.
		local island = Workspace:FindFirstChild(ENTRANCE_ISLAND)
		local spawn  = island and island:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawn then
			hrp.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
		else
			warn(("[DinoRealm] no SpawnLocation under %s -> leaving %s on the default spawn")
				:format(ENTRANCE_ISLAND, player.Name))
		end

		hrp.Anchored = true
		task.wait(FROZEN_SECONDS)

		-- THE TOWER INTRO MAY HAVE TAKEN OVER BY NOW (the arrival cinematic hands off to it, and
		-- Intro.server sets IntroPlaying before firing it). The intro anchors the body itself and flies
		-- it 19,000 studs up the tower, and its own restore() unanchors at the end. Unanchoring here
		-- would drop the player out of the sky in the middle of the cinematic.
		if player:GetAttribute("IntroPlaying") then
			return
		end

		-- Only unanchor if it's still the same character (they may have died/respawned meanwhile).
		if hrp.Parent and player.Character == char then
			hrp.Anchored = false
		end
	end)
end

local function restorePets(player, data)
	task.spawn(function()
		-- Script load order within ServerScriptService is not guaranteed, so PetUpgrades may not have
		-- exposed its filter yet when a player is already in (Studio / hot reload).
		local t0 = os.clock()
		while not _G.petsRestoreFromArrival and os.clock() - t0 < 15 do task.wait(0.1) end
		if not _G.petsRestoreFromArrival then
			warn("[DinoRealm] PetUpgrades never exposed petsRestoreFromArrival -> arriving pets not restored")
			return
		end
		if not player.Parent then return end

		local kept, dropped = _G.petsRestoreFromArrival(player, data.ownedPets, data.equippedPet)
		print(("[DinoRealm] %s's pets: %d kept (this game's catalog), %d left behind in space")
			:format(player.Name, kept, dropped))
	end)
end

local function intake(player)
	local data
	pcall(function()
		local jd = player:GetJoinData()
		data = jd and jd.TeleportData
	end)

	-- Not a portal arrival (joined the place directly, or the payload was lost) -> normal start.
	if type(data) ~= "table" or data.fromFartToFloat ~= true then
		print("[DinoRealm] " .. player.Name .. " joined WITHOUT teleport data -> fresh start")
		return
	end

	_G.incomingFtFData[player]  = data
	_G.arrivedSpacePets[player] = (type(data.ownedPets) == "table") and data.ownedPets or {}
	sendFoodPets(player) -- feed the Pet Hub's FOOD tab (it also requests on load, either works)

	-- SERVER-SET so it actually replicates, and so anything else in the place can ask "did this player
	-- come through the rift?" without re-reading the join data.
	--
	-- The tower intro still plays for them — it just can't play AT THE SAME TIME as the arrival
	-- cinematic (they'd fight over the camera, the CoreGui and this very body's Anchored flag). So
	-- Intro.server holds it, and the arrival cinematic hands off when its card is done.
	player:SetAttribute("ArrivedViaRift", data.arrivedViaRift == true)

	print(("[DinoRealm] %s arrived from place %s (via %s) carrying %d pet stack(s); equipped=%s")
		:format(player.Name, tostring(data.fromPlaceId), tostring(data.fromPlanet),
		        countKeys(data.ownedPets), tostring(data.equippedPet)))

	restorePets(player, data)

	-- They came through the TIME RIFT -> their client is holding a black screen and fading up out of
	-- it. Keep them still until that lands, so the reveal is a reveal and not a stumble.
	if data.arrivedViaRift == true then
		holdAtEntrance(player)
	end
end

Players.PlayerAdded:Connect(intake)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end -- players already in (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFData[p]  = nil
	_G.arrivedSpacePets[p] = nil
end)

print("[DinoRealm] arrival receiver ready — reading TeleportData from rift arrivals")
