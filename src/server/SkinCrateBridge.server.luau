--======================================================================
-- SkinCrateBridge.server.luau  (server Script)
--======================================================================
-- The adapter that lets the Fart-to-Float SkinCrateService run in Dinosaur Realm.
--
-- That service was written against PlayerStats + PetSystem. Rather than importing
-- those (300KB that would fight this realm's own leaderstats and pet system), this
-- supplies the handful of hooks it actually reaches for. Everything it needs is
-- either already here or below:
--
--   already provided by PetUpgrades.server.luau:
--     _G.playerOwnedPets, _G.playerEquippedPet, _G.petGrantLevels,
--     _G.petListOwned, _G.petHasUnmaxed
--   provided here:
--     persistence for the three tables the service owns, _G.savePlayerData,
--     _G.petAllSpecies, _G.petSpeciesInfo, and the join handshake
--
-- WHY PERSISTENCE LIVES HERE. SkinCrateService deliberately does not save: it keeps
-- its state on _G.playerCrateTokens / _G.playerPetSkins / _G.playerEquippedSkins and
-- expects the host game's PlayerStats to write them out. This realm has no
-- PlayerStats, so without this file every crate opened is forgotten on leave.
--======================================================================
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local CrateTokens = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("CrateTokens"))

local STARTING_TOKENS = 500  -- a Starter crate is 250, so a new player can try it immediately

-- The service defaults these with `or {}` at its own load time; mirror that here so
-- load order between the two files cannot matter.
_G.playerCrateTokens   = _G.playerCrateTokens   or {}
_G.playerPetSkins      = _G.playerPetSkins      or {}
_G.playerEquippedSkins = _G.playerEquippedSkins or {}

local store
pcall(function() store = DataStoreService:GetDataStore("DinoSkinState_v1") end)

-- ONE TOKEN BALANCE FOR THE WHOLE UNIVERSE. Crate tokens are the currency that travels between realms, so
-- they must not live in a per-realm save: a player with 300 tokens in the Food realm and 40 here is one
-- player with one wallet. This store is keyed on the userId alone and named for the universe, not the
-- realm; every realm that reads and writes this exact name shares the wallet, and a gift credited in any
-- of them shows up in all of them. Skins / equipped looks stay in DinoSkinState_v1 (they are per-realm
-- cosmetics and travel by payload instead).
--
-- MIGRATION: the first time a player is seen with no universe record, their old DinoSkinState tokens seed
-- it (or STARTING_TOKENS for a brand-new player). After that the old `tokens` field is ignored on load
-- and only written as a mirror.
local UNIVERSE_TOKEN_STORE = "UniverseCrateTokens_v1"
local tokenStore
pcall(function() tokenStore = DataStoreService:GetDataStore(UNIVERSE_TOKEN_STORE) end)
local function tokenKey(player) return "u_" .. player.UserId end
local tokensLoaded = {} -- [player] = true once the universe store answered; a save before that could wipe a real wallet
local stateLoaded  = {} -- [player] = true once load() has finished; NO save of any kind before that
local lastPayload  = {} -- [player] = the last payload captured, so a coalesced re-save after leave never reads a wiped table

--======================================================================
-- SPECIES  -- ids must match PetUpgrades' PETS keys, because the skin service
-- decides whether a skin is equippable from _G.playerOwnedPets[player][petId].
--======================================================================
local SPECIES = { "StegoPet", "RaptorPet", "SharkPet", "TriceratopsPet", "SpinosaurusPet", "TyrannosaurusPet" }
local SPECIES_INFO = {
	StegoPet         = { displayName = "Stegosaurus"  },
	RaptorPet        = { displayName = "Velociraptor" },
	SharkPet         = { displayName = "Megalodon"    },
	TriceratopsPet   = { displayName = "Triceratops"  },
	SpinosaurusPet   = { displayName = "Spinosaurus"  },
	TyrannosaurusPet = { displayName = "T-Rex"        },
}
_G.petAllSpecies  = function() return table.clone(SPECIES) end
_G.petSpeciesInfo = function() return SPECIES_INFO end

--======================================================================
-- PERSISTENCE
--======================================================================
local function key(player) return "skin_" .. player.UserId end

local function load(player)
	local data
	if store then
		local ok, saved = pcall(function() return store:GetAsync(key(player)) end)
		if ok and type(saved) == "table" then data = saved end
	end
	data = data or {}
	-- the wallet: universe store first; the old per-realm field only seeds a missing record
	local tokens = nil
	if tokenStore then
		local okT, rec = pcall(function() return tokenStore:GetAsync(tokenKey(player)) end)
		if okT then
			tokensLoaded[player] = true
			if type(rec) == "table" and tonumber(rec.tokens) then
				tokens = math.floor(tonumber(rec.tokens))
			end
		else
			warn(("[SkinBridge] universe token store read failed for %s -- balance NOT saved this session: %s"):format(player.Name, tostring(rec)))
		end
	end
	if tokens == nil then
		tokens = math.floor(tonumber(data.tokens) or STARTING_TOKENS) -- migrate the old realm-local wallet (or start fresh)
		if tokensLoaded[player] then print(("[SkinBridge] %s: seeded the universe wallet with %d token(s) from the old realm save"):format(player.Name, tokens)) end
	end
	_G.playerCrateTokens[player]   = tokens
	_G.playerPetSkins[player]      = type(data.skins) == "table" and data.skins or {}
	_G.playerEquippedSkins[player] = type(data.equipped) == "table" and data.equipped or {}

	-- Hand off to the service now that real data is in place. This is the handshake it
	-- documents: without it the first state push carries an empty default and the panel
	-- opens showing zero tokens even for a returning player.
	stateLoaded[player] = true -- from here on saves are allowed (and skinCrateApplyOnJoin's mirror is safe)
	if _G.skinCrateApplyOnJoin then
		pcall(_G.skinCrateApplyOnJoin, player)
	end
end

local saving, dirty = {}, {}
local save
-- COALESCE, never drop: a save requested while one is in flight marks the player dirty and runs again the
-- moment the first finishes, with the newest balance. The old guard silently dropped the second request,
-- which with per-change saves would have lost whichever token change landed during a write.
local function finish(player)
	saving[player] = false
	if dirty[player] then dirty[player] = nil; save(player, "coalesced") end
end
save = function(player, why)
	if not (store or tokenStore) then return end
	-- NEVER before the load: a save triggered by an early token mirror or an arrival merge would write a
	-- default wallet / half-built inventory over the real record.
	if not stateLoaded[player] then return end
	if saving[player] then dirty[player] = true; return end
	saving[player] = true
	-- Capture NOW. A coalesced re-save can run after PlayerRemoving has wiped the _G entries; it must
	-- re-use the last real snapshot rather than read nil and save an empty record.
	local live = _G.playerCrateTokens[player]
	local payload
	if live ~= nil then
		payload = {
			tokens   = live,
			skins    = _G.playerPetSkins[player] or {},
			equipped = _G.playerEquippedSkins[player] or {},
		}
		lastPayload[player] = payload
	else
		payload = lastPayload[player]
		if not payload then saving[player] = false; return end
	end
	local tokens = math.floor(tonumber(payload.tokens) or 0)
	task.spawn(function()
		if store then
			local ok, err = pcall(function() store:SetAsync(key(player), payload) end)
			if not ok then warn(("[SkinBridge] save failed for %s (%s): %s"):format(player.Name, tostring(why), tostring(err))) end
		end
		-- the universe wallet. Only once the read succeeded (see tokensLoaded): a blind write on a failed
		-- read would overwrite a real balance with this session's fallback.
		if tokenStore and tokensLoaded[player] then
			local okT, errT = pcall(function()
				tokenStore:UpdateAsync(tokenKey(player), function(old)
					local rec = (type(old) == "table") and old or {}
					rec.tokens = tokens
					rec.updatedAt = os.time()
					rec.lastRealm = "dino"
					return rec
				end)
			end)
			if not okT then warn(("[SkinBridge] universe token save failed for %s (%s): %s"):format(player.Name, tostring(why), tostring(errT))) end
		end
		finish(player)
	end)
end

-- The service calls this after every grant, trade-up, purchase and title change.
_G.savePlayerData = _G.savePlayerData or function(player, why) save(player, why) end

Players.PlayerAdded:Connect(function(p) task.spawn(load, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end

Players.PlayerRemoving:Connect(function(p)
	save(p, "leave")
	task.delay(3, function()
		_G.playerCrateTokens[p]   = nil
		_G.playerPetSkins[p]      = nil
		_G.playerEquippedSkins[p] = nil
	end)
	-- the bookkeeping waits for the in-flight save (and any coalesced follow-up) to finish
	task.spawn(function()
		local t0 = os.clock()
		while (saving[p] or dirty[p]) and os.clock() - t0 < 30 do task.wait(0.5) end
		tokensLoaded[p] = nil; stateLoaded[p] = nil; lastPayload[p] = nil; saving[p] = nil; dirty[p] = nil
	end)
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do save(p, "shutdown") end
	task.wait(1)
end)

print(("[SkinBridge] ready -- %d species, persistence + savePlayerData + join handshake wired. Tokens live in the UNIVERSE wallet '%s' (shared by every realm that uses that name).")
	:format(#SPECIES, UNIVERSE_TOKEN_STORE))
