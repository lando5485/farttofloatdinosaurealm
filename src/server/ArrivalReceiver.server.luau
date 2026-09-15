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
-- CRATE TOKENS are handled separately in carryUniversals (below): shared-wallet senders are not merged at
-- all; private-wallet senders are merged once, through the service's own credit hook.
local function restoreCosmetics(player, data)
	if type(data.petSkins) ~= "table" and type(data.equippedSkins) ~= "table"
		and type(data.collection) ~= "table" then return end
	task.spawn(function()
		-- Wait for THIS PLAYER's save to have loaded (SkinCrateBridge sets the wallet entry last), not just
		-- for the tables to exist. Merging before the load meant the load then overwrote the merge wholesale,
		-- and the repaint below saved a half-built record on top of the real one.
		local t0 = os.clock()
		while not (_G.playerPetSkins and _G.playerCrateTokens and _G.playerCrateTokens[player]) and os.clock() - t0 < 20 do task.wait(0.1) end
		if not (_G.playerPetSkins and _G.playerCrateTokens and _G.playerCrateTokens[player]) then
			warn("[DinoRealm] SkinCrateService/Bridge never loaded " .. player.Name .. " -> arriving skins/traits not restored")
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

--======================================================================
-- WHAT CROSSES A REALM BOUNDARY: TOKENS AND THE TITLE. NEVER COINS.
--======================================================================
-- COINS ARE REALM-LOCAL AND MUST STAY THAT WAY. Every realm's coin economy is tuned against its own
-- island spacing and its own food prices, so a Food Realm balance dropped into this place would either
-- be pocket change or would buy the whole tower. The sending side already knows this -- the Food
-- Realm's RealmTransfer module says so in as many words and ships no coin field at all.
--
-- CRATE TOKENS ARE THE UNIVERSAL CURRENCY. They only ever buy cosmetics (skin crates), which is exactly
-- why they can travel: a token is worth one crate roll in any realm, and no progression gate anywhere
-- is priced in them. They were being DROPPED ON THE FLOOR here -- the payload carried them and nothing
-- read the field, so a player who crossed the rift arrived broke and their balance in the place they
-- came from was the only copy left.
--
-- TOKENS NOW LIVE IN ONE UNIVERSE WALLET (SkinCrateBridge: UniverseCrateTokens_v1). A sender on that
-- wallet is flagged `sharedTokens` and is NOT merged -- the balance is already ours. A sender still on a
-- private wallet (a realm not yet migrated) is merged ONCE: its earned delta is credited, then its
-- absolute is max-merged, both through the service's own credit hook so the clamp, the client push and
-- the immediate save all happen. Our own tokens coming back from such a realm are never re-merged.
--
-- THE TITLE rides along for the same reason: it is a pure brag cosmetic, it is earned once, and a
-- player who worked for "Beastmaster" should wear it in every realm. TitleTags reads the attribute.
local function carryUniversals(player, data)
	task.spawn(function()
		-- SkinCrateBridge loads the local balance asynchronously on join; merging before that lands
		-- would be merging against a nil and would then be overwritten by the load.
		local t0 = os.clock()
		while _G.playerCrateTokens == nil or _G.playerCrateTokens[player] == nil do
			if os.clock() - t0 > 15 or not player.Parent then break end
			task.wait(0.25)
		end
		if not player.Parent then return end

		-- A SENDER ON THE UNIVERSE WALLET already shares this balance: merging its absolute or crediting its
		-- delta on top would pay the same tokens twice. Only a realm still on its own private wallet gets
		-- merged (that is the migration path until every realm reads the shared store).
		local skipTokens = (data.sharedTokens == true)
		if skipTokens then
			print(("[DinoRealm] %s arrived on the universe wallet -> tokens already shared, no merge"):format(player.Name))
		end
		-- OUR OWN TOKENS COMING HOME: a private-wallet realm max-merges what we sent it and sends the same
		-- number back; merging it again would ratchet the shared wallet up by the earned delta every round
		-- trip. Anything that left THIS place is already in the wallet.
		if tonumber(data.fromPlaceId) == game.PlaceId then skipTokens = true end
		local incoming = skipTokens and 0 or math.floor(tonumber(data.crateTokens) or 0)
		-- A sender that only speaks the DELTA channel (an older sender may send only `earned`; Space sends
		-- both, Food sends flat): credit the delta ON TOP of the local balance, capped like Food's receiver
		-- caps it, then let the flat max-merge below settle whichever is larger. Applied once per arrival.
		local delta = skipTokens and 0 or ((type(data.earned) == "table") and math.floor(tonumber(data.earned.crateTokens) or 0) or 0)
		if delta > 0 and _G.addCrateTokensRaw and not data.__deltaApplied then
			data.__deltaApplied = true
			delta = math.min(delta, 500)
			pcall(_G.addCrateTokensRaw, player, delta, "earned abroad (arrival delta)") -- clamp + push + save
			print(("[DinoRealm] %s earned %d crate token(s) abroad -> credited"):format(player.Name, delta))
		end
		if incoming > 0 and _G.addCrateTokensRaw then
			local here = math.floor(tonumber(_G.playerCrateTokens[player]) or 0)
			if incoming > here then
				pcall(_G.addCrateTokensRaw, player, incoming - here, "carried in (private-wallet sender)") -- max-merge, via the hook
				print(("[DinoRealm] %s carried in %d crate token(s) (had %d here) -> %d")
					:format(player.Name, incoming, here, incoming))
			else
				print(("[DinoRealm] %s arrived with %d token(s); the %d already saved here wins")
					:format(player.Name, incoming, here))
			end
		end

		-- the title fills an EMPTY slot only; one earned in this realm is never overwritten
		if type(data.title) == "string" and data.title ~= "" then
			local cur = player:GetAttribute("Title")
			if cur == nil or cur == "" then
				player:SetAttribute("Title", data.title) -- TitleTags renders it above their head
				print(("[DinoRealm] %s wears the title %q, earned in another realm"):format(player.Name, data.title))
			end
		end
		_G.dinoArrivalSettled[player] = true -- WormholeService may now take its earned baseline
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
		_G.dinoArrivalSettled[player] = true -- nothing to merge: the earned baseline can be taken at once
		return
	end

	-- ANTI-CROSSWIRE. Every other receiver in the universe refuses a payload stamped for somebody else;
	-- this one did not. A stale or forwarded payload with the wrong userId is treated as a direct join.
	local stampedFor = tonumber(data.userId)
	if stampedFor and stampedFor ~= player.UserId then
		warn(("[DinoRealm] %s arrived with TeleportData stamped for user %d -- ignored, fresh start"):format(player.Name, stampedFor))
		_G.dinoArrivalSettled[player] = true
		return
	end
	-- The trip's origin becomes "home" for the hop back, unless the payload already names one (a
	-- Food -> Space -> Dino traveller still goes home to Food). WormholeService reads this stash to fill
	-- homePlaceId / returningHome and to forward the pass-through fields (gut skins, milestones, passes).
	if not tonumber(data.homePlaceId) then
		local from = tonumber(data.fromPlaceId)
		if from and from > 0 and from ~= game.PlaceId then data.homePlaceId = from end
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

	print(("[DinoRealm] %s arrived from place %s (via %s, v%s, home %s) carrying %d pet stack(s); equipped=%s; pass-through: gutSkins=%s milestones=%s passes=%s")
		:format(player.Name, tostring(data.fromPlaceId), tostring(data.fromPlanet or data.fromRealm), tostring(data.payloadVersion),
		        tostring(data.homePlaceId), countKeys(data.ownedPets), tostring(data.equippedPet),
		        tostring(type(data.ownedGutSkins) == "table"), tostring(type(data.petMilestones) == "table"), tostring(type(data.gamepasses) == "table")))

	restorePets(player, data)
	restoreCosmetics(player, data)   -- their skins + traits come with them, not just the pets
	carryUniversals(player, data)

	-- They came through the TIME RIFT -> their client is holding a black screen and fading up out of
	-- it. Keep them still until that lands, so the reveal is a reveal and not a stumble.
	if data.arrivedViaRift == true then
		holdAtEntrance(player)
	end
end

_G.dinoArrivalSettled = _G.dinoArrivalSettled or {} -- [player] = true once tokens carried in have been merged (or there were none)
Players.PlayerAdded:Connect(intake)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end -- players already in (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFData[p]  = nil
	_G.arrivedSpacePets[p] = nil
	_G.dinoArrivalSettled[p] = nil
end)

print("[DinoRealm] arrival receiver ready — reading TeleportData from rift arrivals")
