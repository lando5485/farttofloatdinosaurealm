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
	_G.playerCrateTokens[player]   = tonumber(data.tokens) or STARTING_TOKENS
	_G.playerPetSkins[player]      = type(data.skins) == "table" and data.skins or {}
	_G.playerEquippedSkins[player] = type(data.equipped) == "table" and data.equipped or {}

	-- Hand off to the service now that real data is in place. This is the handshake it
	-- documents: without it the first state push carries an empty default and the panel
	-- opens showing zero tokens even for a returning player.
	if _G.skinCrateApplyOnJoin then
		pcall(_G.skinCrateApplyOnJoin, player)
	end
end

local saving = {}
local function save(player, why)
	if not store or saving[player] then return end
	saving[player] = true
	local payload = {
		tokens   = _G.playerCrateTokens[player] or 0,
		skins    = _G.playerPetSkins[player] or {},
		equipped = _G.playerEquippedSkins[player] or {},
	}
	task.spawn(function()
		local ok, err = pcall(function() store:SetAsync(key(player), payload) end)
		if not ok then warn(("[SkinBridge] save failed for %s (%s): %s"):format(player.Name, tostring(why), tostring(err))) end
		saving[player] = false
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
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do save(p, "shutdown") end
	task.wait(1)
end)

print(("[SkinBridge] ready -- %d species, persistence + savePlayerData + join handshake wired.")
	:format(#SPECIES))
