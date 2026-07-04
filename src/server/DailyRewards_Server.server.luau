--!nonstrict
--======================================================================
-- DailyRewards_Server  (put in ServerScriptService as a SERVER Script)
--======================================================================
-- SELF-CONTAINED server half of the Mystery Meteor Crate "Daily Rewards" system.
-- Bundles, in one file (so the other game only needs this + DailyRewards_Client):
--   * Constants (CRATE tuning) — inlined
--   * PlayerState (just the crate's needs: 6h-cooldown persistence + coin fallback + snapshot)
--   * StubPetProvider — gives every player ONE random always-owned pet so the crate can grant
--     LEVELS right now, before a real pet system exists.   >>> see DELETE note below <<<
--   * CrateService — server authority: rarity roll, pet-level grant, cooldown gate, coin fallback.
--
-- Server is the ONLY authority for eligibility/roll/grant. The client only animates the reveal.
-- Pairs with DailyRewards_Client (StarterPlayerScripts LocalScript). The HUD's MORE+ "Daily Rewards"
-- row fires OpenMeteorCrate, which the client listens for.
--======================================================================

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

--======================================================================
-- INLINED Constants.CRATE  (keep identical to DailyRewards_Client)
--======================================================================
local Constants = {
	CRATE = {
		COOLDOWN_SECONDS = 21600, -- 6 hours between free claims
		FALLBACK_COINS = 500,     -- coins when every owned pet is already maxed
		PET_MAX_LEVEL = 25,
		RARITY_WEIGHTS = { Uncommon = 55, Rare = 28, Epic = 13, Mythical = 4 },
		RARITY_ORDER = { "Uncommon", "Rare", "Epic", "Mythical" },
		RARITY_LEVELS = { Uncommon = 1, Rare = 2, Epic = 4, Mythical = 6 },
		RARITY_COLORS = {
			Uncommon = Color3.fromRGB(150, 160, 172),
			Rare     = Color3.fromRGB(70, 140, 255),
			Epic     = Color3.fromRGB(175, 90, 240),
			Mythical = Color3.fromRGB(255, 200, 60),
		},
	},
}
local CRATE = Constants.CRATE

--======================================================================
-- STUB PET PROVIDER  — every player gets ONE random always-owned pet.
--   >>> DELETE this whole section once you add a real PetSystem. <<<
--   A real PetSystem defines the SAME _G.petListOwned / petHasUnmaxed / petGrantLevels,
--   so leaving this in would fight it. The crate calls ONLY these three functions.
--======================================================================
-- StubPetProvider REMOVED. The REAL pet system (PetUpgrades.server.luau) now defines _G.petListOwned /
-- _G.petHasUnmaxed / _G.petGrantLevels from the player's ACTUAL hatched pets (Stegosaurus, Velociraptor,
-- Megalodon, Triceratops). The crate picker uses those -- no more random test pet.
print("[DailyRewards] using REAL owned pets from PetUpgrades (no stub).")

--======================================================================
-- PLAYER STATE  (trimmed to the crate's needs: lastCrateClaim persistence + coin fallback + snapshot)
--   Persists to its OWN DataStore ("CrateState_v1") so it never clobbers other saves.
--   In Studio it only persists if "Enable Studio Access to API Services" is on; otherwise it
--   runs on defaults for the session (still fully playable).
--======================================================================
local PlayerState = {}
do
	local DATASTORE_NAME = "CrateState_v1"
	local AUTOSAVE_INTERVAL = 120
	local states = {} -- [player] = { lastCrateClaim, dirty, loaded }

	-- StateRemotes: server creates the folder + the two RemoteEvents the client snapshot stream uses.
	local function getOrCreate(parent, className, name)
		local o = parent:FindFirstChild(name)
		if not o then o = Instance.new(className); o.Name = name; o.Parent = parent end
		return o
	end
	local stateFolder = getOrCreate(ReplicatedStorage, "Folder", "StateRemotes")
	local StateChanged = getOrCreate(stateFolder, "RemoteEvent", "StateChanged")
	local RequestState = getOrCreate(stateFolder, "RemoteEvent", "RequestState")

	local store = nil
	do
		local ok, ds = pcall(function() return game:GetService("DataStoreService"):GetDataStore(DATASTORE_NAME) end)
		if ok then store = ds else warn("[DailyRewards] DataStore unavailable (" .. tostring(ds) .. ") — cooldown won't persist this session") end
	end

	local function pushSnapshot(player)
		local s = states[player]; if not s then return end
		pcall(function() StateChanged:FireClient(player, { lastCrateClaim = s.lastCrateClaim or 0 }) end)
	end
	PlayerState.pushSnapshot = pushSnapshot

	local function loadPlayer(player)
		local s = { lastCrateClaim = 0, dirty = false, loaded = false }
		states[player] = s
		if store then
			local ok, data = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
			if ok and type(data) == "table" then
				s.lastCrateClaim = tonumber(data.lastCrateClaim) or 0
			elseif not ok then
				-- DataStore unavailable (e.g. Studio API access OFF, or the service is down). Do NOT block the
				-- crate -- run with an in-memory default profile (claimable now), and flag it so we never SAVE
				-- over the player's real data this session.
				warn("[DailyRewards] load failed for " .. player.Name .. " (" .. tostring(data) .. ") -> in-memory default, no save this session")
				s.lastCrateClaim = 0; s.noSave = true
			end
		end
		s.loaded = true
		pushSnapshot(player)
	end

	local function savePlayer(player, trigger)
		local s = states[player]
		if not s or not s.loaded or not s.dirty or not store or s.noSave then return end -- noSave: load failed, don't clobber real data
		local ok, err = pcall(function() store:SetAsync(tostring(player.UserId), { lastCrateClaim = s.lastCrateClaim or 0 }) end)
		if ok then s.dirty = false else warn("[DailyRewards] save (" .. tostring(trigger) .. ") failed for " .. player.Name .. ": " .. tostring(err)) end
	end

	function PlayerState.isLoaded(player) local s = states[player]; return s ~= nil and s.loaded == true end
	function PlayerState.getLastCrateClaim(player) local s = states[player]; return s and s.lastCrateClaim or 0 end
	function PlayerState.setLastCrateClaim(player, t)
		local s = states[player]; if not s then return end
		s.lastCrateClaim = t; s.dirty = true; pushSnapshot(player)
	end
	-- coin fallback / owns-all reward: add to the leaderstats Coins if the game has them (no-op otherwise)
	function PlayerState.addCoins(player, n)
		local ls = player:FindFirstChild("leaderstats"); if not ls then return end
		local coins = ls:FindFirstChild("Coins"); if coins then coins.Value = coins.Value + n end
		local tce = ls:FindFirstChild("TotalCoinsEarned"); if tce then tce.Value = tce.Value + n end
	end

	RequestState.OnServerEvent:Connect(function(player) pushSnapshot(player) end)
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player) savePlayer(player, "leave"); states[player] = nil end)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadPlayer, p) end
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, p in ipairs(Players:GetPlayers()) do savePlayer(p, "autosave") end
		end
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do savePlayer(p, "BindToClose") end
		task.wait(1)
	end)
end

--======================================================================
-- CRATE SERVICE  — server authority for the claim (verbatim logic from CrateService).
--======================================================================
local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local crateRemotes = getOrCreate(ReplicatedStorage, "Folder", "CrateRemotes")
local ClaimCrate   = getOrCreate(crateRemotes, "RemoteFunction", "ClaimCrate")
local CrateResult  = getOrCreate(crateRemotes, "RemoteEvent", "CrateResult")
local GetOwnedPets = getOrCreate(crateRemotes, "RemoteFunction", "GetOwnedPets")
local PreviewRoll  = getOrCreate(crateRemotes, "RemoteFunction", "PreviewRoll")
print("[DailyRewards] CrateRemotes ready (ClaimCrate, CrateResult, GetOwnedPets, PreviewRoll)")

local rng = Random.new()

-- A rarity roll PRE-rolled by PreviewRoll (so the picker shows the rolled rarity/amount before the
-- player picks). The matching ClaimCrate grant reuses it so the displayed roll == the granted roll.
local pendingRoll = {} -- [player] = { rarity, levels }
Players.PlayerRemoving:Connect(function(p) pendingRoll[p] = nil end)

-- ===== pet helpers (provided above by the stub via _G; guarded) =====
local function listOwnedPets(player)
	if type(_G.petListOwned) == "function" then
		local ok, list = pcall(_G.petListOwned, player)
		if ok and type(list) == "table" then return list end
	end
	return {}
end

local function hasUnmaxedPet(player)
	if type(_G.petHasUnmaxed) == "function" then
		local ok, res = pcall(_G.petHasUnmaxed, player)
		if ok then return res == true end
	end
	return false
end

-- ===== rarity roll (weights summed defensively) =====
local function rollRarity()
	local weights = CRATE.RARITY_WEIGHTS
	local order = CRATE.RARITY_ORDER
	local total = 0
	for _, k in ipairs(order) do
		total = total + (weights[k] or 0)
	end
	if total <= 0 then return order[1] end
	local r = rng:NextNumber() * total
	local acc = 0
	for _, k in ipairs(order) do
		acc = acc + (weights[k] or 0)
		if r <= acc then return k end
	end
	return order[#order]
end

-- ===== core claim logic =====
local function performClaim(player, chosenPetId, isDev)
	if not PlayerState.isLoaded(player) then
		return { ok = false, reason = "no_profile" }
	end

	local now = os.time()
	local last = PlayerState.getLastCrateClaim(player)
	if not isDev then
		if last ~= 0 and now < last + CRATE.COOLDOWN_SECONDS then
			return { ok = false, reason = "cooldown", nextClaimAt = last + CRATE.COOLDOWN_SECONDS }
		end
	end

	local function coinFallback()
		PlayerState.addCoins(player, CRATE.FALLBACK_COINS)
		PlayerState.setLastCrateClaim(player, now)
		return { ok = true, kind = "coins", coins = CRATE.FALLBACK_COINS }
	end

	local owned = listOwnedPets(player)

	if #owned == 0 then
		return { ok = false, reason = "no_pets" }
	end

	if not hasUnmaxedPet(player) then
		return coinFallback()
	end

	local petId = nil
	if type(chosenPetId) == "string" then
		for _, p in ipairs(owned) do
			if p.petId == chosenPetId and not p.maxed then petId = p.petId; break end
		end
	end
	if not petId then
		for _, p in ipairs(owned) do
			if not p.maxed then petId = p.petId; break end
		end
	end
	if not petId then
		return coinFallback()
	end

	local rarity, levels
	local pend = pendingRoll[player]
	if pend then
		rarity, levels = pend.rarity, pend.levels
		pendingRoll[player] = nil
	else
		rarity = rollRarity()
		levels = CRATE.RARITY_LEVELS[rarity] or 1
	end

	local oldLevel, newLevel, levelsAdded = nil, nil, 0
	if type(_G.petGrantLevels) == "function" then
		local ok, a, b, c = pcall(_G.petGrantLevels, player, petId, levels)
		if ok then oldLevel, newLevel, levelsAdded = a, b, c end
	end

	if not newLevel or (levelsAdded or 0) <= 0 then
		return coinFallback()
	end

	PlayerState.setLastCrateClaim(player, now)
	return {
		ok = true,
		kind = "levels",
		petId = petId,
		rarity = rarity,
		levelsAdded = levelsAdded,
		newLevel = newLevel,
	}
end

-- ===== remote wiring =====
ClaimCrate.OnServerInvoke = function(player, chosenPetId)
	return performClaim(player, chosenPetId, false)
end

GetOwnedPets.OnServerInvoke = function(player)
	return listOwnedPets(player)
end

PreviewRoll.OnServerInvoke = function(player)
	if not PlayerState.isLoaded(player) then return { ok = false, reason = "no_profile" } end
	local now = os.time()
	local last = PlayerState.getLastCrateClaim(player)
	if last ~= 0 and now < last + CRATE.COOLDOWN_SECONDS then
		return { ok = false, reason = "cooldown", nextClaimAt = last + CRATE.COOLDOWN_SECONDS }
	end
	if #listOwnedPets(player) == 0 then return { ok = false, reason = "no_pets" } end
	if not hasUnmaxedPet(player) then return { ok = true, kind = "coins" } end
	local rarity = rollRarity()
	local levels = CRATE.RARITY_LEVELS[rarity] or 1
	pendingRoll[player] = { rarity = rarity, levels = levels }
	return { ok = true, rarity = rarity, levelsAdded = levels }
end

-- [optional dev path] ServerScriptService/DevForceCrate (BindableEvent, payload=Player): bypasses the
-- 6h gate, grants levels the same way (server picks the pet), pushes the reveal via CrateResult.
local DevForceCrate = getOrCreate(ServerScriptService, "BindableEvent", "DevForceCrate")
DevForceCrate.Event:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local result = performClaim(player, nil, true)
	CrateResult:FireClient(player, result)
end)

print("[DailyRewards] server ready.")
