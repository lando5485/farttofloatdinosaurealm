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

-- ===== COSMETICS COME WITH THEM =====
-- The pets used to arrive UNDRESSED. This receiver only ever read `ownedPets` / `equippedPet`, but the
-- payload the other realms send also carries the whole cosmetic bundle -- `petSkins`, `equippedSkins`,
-- `collection`, `petMilestones`, `title` -- so a player who walked in from the Food Realm lost every skin
-- and trait they owned the moment they got here, and got them back only when they went home. That is the
-- one thing a shared universe must not do.
--
-- MERGE, NEVER ASSIGN -- the same rule their RealmReturnReceiver uses on the way back:
--   * skin counts take the MAX, never the sum (summing doubles a duplicate on every round trip);
--   * equipped skins are honoured only if the entry is actually owned after the merge;
--   * collection/milestone flag maps union (true wins, numbers max);
--   * a title only fills an EMPTY slot -- it never overwrites one earned here.
-- Legacy skin/trait ids ride through untouched: PetSkins.LEGACY / PetTraits.LEGACY resolve them wherever
-- they are read, and SkinCrateService upgrades them for good the next time the player equips.
--
-- CRATE TOKENS ARE DELIBERATELY NOT MERGED. They are an absolute balance owned by each place's own save;
-- assigning an incoming number here would either wipe what was earned in this realm or duplicate currency
-- on every hop. Their receiver takes a DELTA on the return trip and this realm should do the same.
local function restoreCosmetics(player, data)
	if type(data.petSkins) ~= "table" and type(data.equippedSkins) ~= "table"
		and type(data.collection) ~= "table" then return end
	task.spawn(function()
		local t0 = os.clock()
		while not _G.playerPetSkins and os.clock() - t0 < 15 do task.wait(0.1) end
		if not _G.playerPetSkins then
			warn("[DinoRealm] SkinCrateService never came up -> arriving skins/traits not restored")
			return
		end
		if not player.Parent then return end

		local skins = _G.playerPetSkins[player]
		if not skins then skins = {}; _G.playerPetSkins[player] = skins end
		local added = 0
		for key, count in pairs(data.petSkins or {}) do
			local n = tonumber(count) or 0
			if type(key) == "string" and n > 0 then
				local have = tonumber(skins[key]) or 0
				if n > have then skins[key] = n; added += 1 end   -- MAX, not sum
			end
		end

		local eq = _G.playerEquippedSkins and _G.playerEquippedSkins[player]
		if eq == nil and _G.playerEquippedSkins then eq = {}; _G.playerEquippedSkins[player] = eq end
		local worn = 0
		if eq then
			for petId, e in pairs(data.equippedSkins or {}) do
				if type(petId) == "string" and type(e) == "table" and e.skin then
					eq[petId] = { skin = e.skin, trait = e.trait }   -- rendering re-validates ownership
					worn += 1
				end
			end
		end

		if _G.playerCollection and type(data.collection) == "table" then
			local col = _G.playerCollection[player]
			if not col then col = {}; _G.playerCollection[player] = col end
			for k, v in pairs(data.collection) do
				if type(v) == "boolean" then
					if v then col[k] = true end
				elseif type(v) == "number" then
					if (tonumber(col[k]) or 0) < v then col[k] = v end
				elseif col[k] == nil then
					col[k] = v
				end
			end
		end

		-- TITLES: nothing in THIS realm publishes _G.playerTitle yet (the Food Realm's PetSystem owns
		-- titles over there), so this branch is inert here by design rather than by accident -- it is
		-- guarded, costs nothing, and starts working the day this place grows a title system. The
		-- attribute is set either way, so a visiting player's earned title can still be displayed.
		if type(data.title) == "string" and data.title ~= "" then
			pcall(function()
				if player:GetAttribute("Title") == nil or player:GetAttribute("Title") == "" then
					player:SetAttribute("Title", data.title)
				end
			end)
			if _G.playerTitle and (_G.playerTitle[player] == nil or _G.playerTitle[player] == "") then
				_G.playerTitle[player] = data.title
			end
		end

		-- repaint + push the new state to their client so the pet is wearing it immediately
		if _G.skinCrateApplyOnJoin then pcall(_G.skinCrateApplyOnJoin, player) end
		if _G.skinPushState then pcall(_G.skinPushState, player) end
		print(("[DinoRealm] %s's cosmetics: %d skin entr(ies) merged, %d equipped look(s) carried over")
			:format(player.Name, added, worn))
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
	restoreCosmetics(player, data)   -- their skins + traits come with them, not just the pets

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
