--======================================================================
-- PetUpgrades.server.luau  (Server Script)
--======================================================================
-- Server-authoritative pet XP / LEVEL / EVOLVE backbone, adapted from
-- PetUpgrades_AllInOne.server.lua for THIS game's STEGOSAURUS pet.
--
-- It drives:
--   * the PET HUB  -> PetInventoryEvent (card: level, XP bar, milestone hint)  [PetHub.client.luau listens]
--   * the FOLLOWER -> PetStateEvent     (re-apply the per-level evolve look + trail)  [PetFollow.client.luau listens]
--
-- Flow: the player hatches the Stego (QuestGate fires StegoHatched) -> the pet is granted + equipped.
-- XP from real sources (call the _G.petOn* hooks) auto-levels it 1..25; or press ] (PetUpgradeEvent)
-- to level it for testing. Milestones at 3/8/13/18/23/25 unlock the accessories/aura/trail/etc. the
-- client already builds in applyLevelVisual.
--
-- NOTE: this does NOT override MarketplaceService.ProcessReceipt (DailyRewards owns it). The Robux
-- tier-skip is exposed via _G.petsHandleReceipt(player, productId) for the central receipt handler to call.
--======================================================================

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")

-- ===== remotes (created if missing) =====
local function ev(name) local e = RS:FindFirstChild(name); if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end; return e end
local PetStateEvent     = ev("PetStateEvent")          -- s->c: re-apply the follower's per-level evolve visual
local PetInventoryEvent = ev("PetInventoryEvent")      -- s->c: refresh the hub card (level + XP bar)
local PetUpgradeEvent   = ev("PetUpgradeEvent")        -- c->s: free / test level-up
local PetProgressEvent  = ev("PetProgressEvent")       -- c->s: (petId, peakHeight, addTime)
local PetPendingUpgrade = ev("PetPendingUpgradeEvent") -- c->s: (petId) declared before a Robux prompt
local PetEquipEvent     = ev("PetEquipEvent")          -- c->s: the Pet Hub EQUIP/UNEQUIP button (created here so the hub finds it)
local StegoHatched      = ev("StegoHatched")           -- c->s: the player hatched the Stego -> grant it

-- ============================================================================
-- STORE (the real game would persist this). owned[player][petId] = {level,xp,height,time,count,rare}
-- ============================================================================
_G.playerOwnedPets   = _G.playerOwnedPets   or {}
_G.playerEquippedPet = _G.playerEquippedPet or {}
local pendingRobuxPet = {}

-- this game's pet catalog (just the Stego; petId "StegoPet" matches the Hub icon builder + hatch grant)
local PETS = {
	StegoPet  = { displayName = "Stegosaurus",  maxLevel = 25 },
	RaptorPet = { displayName = "Velociraptor", maxLevel = 25 },
	SharkPet  = { displayName = "Megalodon",    maxLevel = 25 },
	TriceratopsPet = { displayName = "Triceratops", maxLevel = 25 },
	SpinosaurusPet = { displayName = "Spinosaurus", maxLevel = 25 },
	TyrannosaurusPet = { displayName = "T-Rex", maxLevel = 25 },
}
local RARE_NAMES = { StegoPet = "Cosmic Stegosaurus", RaptorPet = "Alpha Velociraptor", SharkPet = "Ancient Megalodon", TriceratopsPet = "Elder Triceratops", SpinosaurusPet = "Swamp King Spinosaurus", TyrannosaurusPet = "Volcano Tyrant Rex" }

-- ROBUX TIER-SKIP products (placeholder ids -- REPLACE with real Developer Products before launch)
local PET_SKIP_PRODUCTS = {
	[123456701] = { target = 6,  srcMin = 1,  srcMax = 5,  price = 49,  to = "Uncommon"  },
	[123456702] = { target = 11, srcMin = 6,  srcMax = 10, price = 99,  to = "Rare"      },
	[123456703] = { target = 16, srcMin = 11, srcMax = 15, price = 299, to = "Epic"      },
	[123456704] = { target = 21, srcMin = 16, srcMax = 20, price = 599, to = "Legendary" },
}

-- ============================================================================
-- LEVELING (cosmetic prestige 1..25, XP-driven) -- VERBATIM curve
-- ============================================================================
local PET_MAX_LEVEL = 25
local PET_XP_BASE, PET_XP_EXP = 80, 1.6
local function xpNeeded(level)
	if level >= PET_MAX_LEVEL then return math.huge end
	return math.floor(PET_XP_BASE * (level ^ PET_XP_EXP))
end
local XP_PER_COIN, XP_PER_FLIGHT_TICK, XP_PER_GAS, XP_PER_ISLAND = 0.15, 6, 0.5, 600

local function tierVisual(level)
	if level >= 25 then return "MAX (all accessories + gold + shimmer)"
	elseif level >= 23 then return "5 accessories + full trail/aura/sparkles"
	elseif level >= 18 then return "4 accessories + sparkles + growing"
	elseif level >= 15 then return "3 accessories + sparkles + growing"
	elseif level >= 13 then return "3 accessories + aura + growing"
	elseif level >= 10 then return "2 accessories + aura + growing"
	elseif level >= 8 then return "2 accessories + trail + growing"
	elseif level >= 5 then return "1 accessory + trail + growing"
	elseif level >= 3 then return "1 accessory, growing"
	else return "starter (growing)" end
end
local function nextMilestoneHint(level)
	if level >= 25 then return "MAX reached"
	elseif level >= 23 then return "Lvl 25: MAX (gold + shimmer)"
	elseif level >= 18 then return "Lvl 23: accessory #5"
	elseif level >= 13 then return "Lvl 18: accessory #4"
	elseif level >= 8 then return "Lvl 13: accessory #3 (hat)"
	elseif level >= 3 then return "Lvl 8: accessory #2 (glasses)"
	else return "Lvl 3: accessory #1" end
end
local function isMilestone(level) return level==3 or level==8 or level==13 or level==18 or level==23 or level==25 end

-- ===== ownership helpers =====
local function ownsPet(player, petId) local op = _G.playerOwnedPets[player]; return op ~= nil and op[petId] ~= nil end
local function getPetData(player, petId)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local v = op[petId]; if v == nil then return nil end
	if type(v) ~= "table" then v = {}; op[petId] = v end
	v.level = v.level or 1; v.xp = v.xp or 0; v.height = v.height or 0; v.time = v.time or 0
	v.count = math.max(1, math.floor(tonumber(v.count) or 1))
	if v.level > PET_MAX_LEVEL then v.level = PET_MAX_LEVEL; v.xp = 0 end
	return v
end

-- ===== resync to the client =====
local function sendState(player)
	local petId = _G.playerEquippedPet[player]
	local d = petId and getPetData(player, petId)
	pcall(function() PetStateEvent:FireClient(player, {
		[petId or "none"] = d and { owns = true, equipped = true, level = d.level, rare = d.rare or false } or nil,
	}) end)
end
local function sendInventory(player)
	local payload = { owned = {}, totalPets = 0 }
	for petId, def in pairs(PETS) do
		payload.totalPets = payload.totalPets + 1
		local d = ownsPet(player, petId) and getPetData(player, petId)
		if d then
			payload.owned[petId] = {
				petId = petId, displayName = def.displayName, level = d.level, maxLevel = PET_MAX_LEVEL,
				xp = math.floor(d.xp), xpNeed = (d.level >= PET_MAX_LEVEL) and 0 or xpNeeded(d.level),
				milestone = nextMilestoneHint(d.level), tierVisual = tierVisual(d.level),
				equipped = (_G.playerEquippedPet[player] == petId),
				rare = d.rare and true or false, rareName = d.rare and RARE_NAMES[petId] or nil, count = d.count or 1,
			}
		end
	end
	pcall(function() PetInventoryEvent:FireClient(player, payload) end)
end

-- ============================================================================
-- LEVEL UP + XP
-- ============================================================================
local function levelUp(player, petId, via)
	local def, d = PETS[petId], getPetData(player, petId)
	if not (def and d) or d.level >= PET_MAX_LEVEL then return false end
	d.level = d.level + 1
	print("[PetLvl] "..petId.." LEVELED UP to "..d.level.." (via "..tostring(via)..")")
	if isMilestone(d.level) then print("[PetLvl] "..petId.." milestone "..d.level.." -> "..tierVisual(d.level)) end
	sendState(player); sendInventory(player)
	return true
end
local lastInvSync = {}
local function syncXP(player, force)
	local now = os.clock()
	if force or not lastInvSync[player] or (now - lastInvSync[player]) >= 2.5 then lastInvSync[player] = now; sendInventory(player) end
end
local function awardXP(player, amount, source)
	amount = tonumber(amount) or 0; if amount <= 0 then return end
	local petId = _G.playerEquippedPet[player]; if not petId or not ownsPet(player, petId) then return end
	local d = getPetData(player, petId); if not d or d.level >= PET_MAX_LEVEL then return end
	d.xp = d.xp + amount
	local leveled = false
	while d.level < PET_MAX_LEVEL do
		local need = xpNeeded(d.level)
		if d.xp < need then break end
		d.xp = d.xp - need; levelUp(player, petId, "xp:"..tostring(source)); leveled = true
	end
	if d.level >= PET_MAX_LEVEL then d.xp = 0 end
	if not leveled then syncXP(player, false) end
end
-- XP SOURCE HOOKS -- call these from your coin/food/island handlers to feed the EQUIPPED pet.
_G.petAwardXP      = function(player, amount, source) awardXP(player, amount, source) end
_G.petOnCoins      = function(player, coins) awardXP(player, (tonumber(coins) or 0) * XP_PER_COIN, "coins") end
_G.petOnFlightTick = function(player)        awardXP(player, XP_PER_FLIGHT_TICK, "distance") end
_G.petOnGas        = function(player, gas)   awardXP(player, (tonumber(gas) or 0) * XP_PER_GAS, "gas") end
_G.petOnIsland     = function(player)        awardXP(player, XP_PER_ISLAND, "island") end

-- CRATE: grant N levels to an owned pet
_G.petGrantLevels = function(player, petId, n)
	n = math.floor(tonumber(n) or 0); if n <= 0 or not ownsPet(player, petId) then return nil end
	local d = getPetData(player, petId); if not d then return nil end
	local oldLevel = d.level
	if oldLevel >= PET_MAX_LEVEL then return oldLevel, oldLevel, 0 end
	local target = math.min(PET_MAX_LEVEL, oldLevel + n)
	while d.level < target do if not levelUp(player, petId, "crate") then break end end
	return oldLevel, d.level, (d.level - oldLevel)
end

-- CRATE: the player's REAL owned pets (Stego / Velociraptor / Megalodon / Triceratops -- whatever they've hatched).
-- DailyRewards_Server calls these; defining them here replaces the test StubPetProvider so the picker shows real pets.
_G.petListOwned = function(player)
	local out = {}
	local op = _G.playerOwnedPets[player]
	if op then
		for petId in pairs(op) do
			local def = PETS[petId]; local d = getPetData(player, petId)
			if def and d then
				out[#out+1] = { petId = petId, displayName = def.displayName, level = d.level, maxed = d.level >= PET_MAX_LEVEL }
			end
		end
	end
	return out
end
_G.petHasUnmaxed = function(player)
	local op = _G.playerOwnedPets[player]
	if not op then return false end
	for petId in pairs(op) do
		local d = getPetData(player, petId)
		if d and d.level < PET_MAX_LEVEL then return true end
	end
	return false
end

-- ============================================================================
-- TIER SKIP (Robux). Test users skip instantly; real receipts route via _G.petsHandleReceipt.
-- ============================================================================
local function nextTierTarget(level)
	if level <= 5 then return 6 elseif level <= 10 then return 11 elseif level <= 15 then return 16 elseif level <= 20 then return 21 else return nil end
end
local function tierSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	local target = nextTierTarget(d.level); if not target then return false end
	d.level = target; d.xp = 0; sendState(player); sendInventory(player)
	print("[PetLvl] tier-skip "..tostring(via).." for "..petId.." -> Lvl "..d.level)
	return true
end
PetPendingUpgrade.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	if _G.isAllowedTestUser and _G.isAllowedTestUser(player) then tierSkip(player, petId, "test"); return end
	pendingRobuxPet[player.UserId] = petId
end)
-- central ProcessReceipt (DailyRewards) should call this for pet tier-skip products
_G.petsHandleReceipt = function(player, productId)
	local prod = PET_SKIP_PRODUCTS[productId]; if not prod then return false end
	local petId = pendingRobuxPet[player.UserId]; pendingRobuxPet[player.UserId] = nil
	if not (petId and ownsPet(player, petId)) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= prod.srcMin and d.level <= prod.srcMax then
		d.level = prod.target; d.xp = 0; sendState(player); sendInventory(player)
		print("[PetLvl] tier-skip PURCHASED (to "..prod.to..") for "..petId.." -> Lvl "..d.level)
		return true
	end
	return true
end

-- ===== free / test level-up + flight progress =====
PetUpgradeEvent.OnServerEvent:Connect(function(player, petId)
	petId = petId or _G.playerEquippedPet[player]
	if petId and ownsPet(player, petId) then levelUp(player, petId, "manual") end
end)
PetProgressEvent.OnServerEvent:Connect(function(player, petId, peakHeight, addTime)
	if not ownsPet(player, petId) or _G.playerEquippedPet[player] ~= petId then return end
	local d = getPetData(player, petId)
	peakHeight = tonumber(peakHeight) or 0; addTime = tonumber(addTime) or 0
	if peakHeight > d.height then d.height = peakHeight end
	if addTime > 0 and addTime <= 30 then d.time = d.time + addTime end
	awardXP(player, XP_PER_FLIGHT_TICK, "distance")
end)

-- ============================================================================
-- GRANT on hatch: QuestGate fires StegoHatched -> the player owns + equips the Stego.
-- ============================================================================
local function grantPet(player, petId)
	if not PETS[petId] then return end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	if not _G.playerOwnedPets[player][petId] then
		_G.playerOwnedPets[player][petId] = { level = 1, xp = 0, height = 0, time = 0 }
		print(("[PetUpgrades] granted %s to %s (Lv1)"):format(petId, player.Name))
	end
	_G.playerEquippedPet[player] = petId
	sendState(player); sendInventory(player)
end
StegoHatched.OnServerEvent:Connect(function(player) grantPet(player, "StegoPet") end)
local RaptorHatched = ev("RaptorHatched")  -- c->s: the player hatched the Velociraptor (dig quest) -> grant it
RaptorHatched.OnServerEvent:Connect(function(player) grantPet(player, "RaptorPet") end)
local SharkHatched = ev("SharkHatched")    -- c->s: the player pulled the egg from ButterLake (island4) -> grant the Shark
SharkHatched.OnServerEvent:Connect(function(player) grantPet(player, "SharkPet") end)
local TriceratopsHatched = ev("TriceratopsHatched") -- c->s: the player completed the Triceratops island quest -> grant it
TriceratopsHatched.OnServerEvent:Connect(function(player) grantPet(player, "TriceratopsPet") end)
local SpinosaurusHatched = ev("SpinosaurusHatched") -- c->s: the player completed the island5 mosquito quest -> grant it
SpinosaurusHatched.OnServerEvent:Connect(function(player) grantPet(player, "SpinosaurusPet") end)
local TyrannosaurusHatched = ev("TyrannosaurusHatched") -- c->s: the player plugged all island8 geysers -> grant it
TyrannosaurusHatched.OnServerEvent:Connect(function(player) grantPet(player, "TyrannosaurusPet") end)

-- ===== EQUIP from the Pet Hub: set the equipped pet, refresh the hub badge, and tell the client to spawn
-- THAT pet's follower (or despawn on unequip). This is what makes "equip any pet I press" actually work. =====
PetEquipEvent.OnServerEvent:Connect(function(player, arg)
	if arg == false or arg == nil then
		_G.playerEquippedPet[player] = nil
	elseif type(arg) == "string" and ownsPet(player, arg) then
		_G.playerEquippedPet[player] = arg
	else
		return -- don't own it / bad arg
	end
	sendState(player); sendInventory(player)
	pcall(function() PetEquipEvent:FireClient(player, _G.playerEquippedPet[player] or false) end) -- client spawns/despawns the follower
	print(("[PetUpgrades] %s equipped: %s"):format(player.Name, tostring(_G.playerEquippedPet[player] or "(none)")))
end)

-- ===== /allpets : DEV command -- grant BOTH pets via the normal grant path (de-duped + Hub refresh) =====
local function giveAllPets(player)
	grantPet(player, "StegoPet")   -- same path as the NestingNook/hatch grant
	grantPet(player, "RaptorPet")  -- same path as the BurritoDig/PetUpgrades grant
	grantPet(player, "SharkPet")   -- same path as the ButterLake/island4 fishing grant
	grantPet(player, "TriceratopsPet") -- same path as the Triceratops island grant
	grantPet(player, "SpinosaurusPet") -- same path as the island5 mosquito grant
	grantPet(player, "TyrannosaurusPet") -- same path as the island8 geyser grant
	local owned = {}
	for id in pairs(_G.playerOwnedPets[player] or {}) do owned[#owned+1] = id end
	print(("[/allpets] granted Stego + Raptor + Megalodon + Triceratops + Spinosaurus + T-Rex to %s; hub refreshed"):format(player.Name))
	print("[/allpets] owned pets: " .. (#owned > 0 and table.concat(owned, ", ") or "(none)"))
end
local function hookAllPetsChat(player)
	player.Chatted:Connect(function(msg)
		if string.gsub(string.lower(msg), "%s", "") == "/allpets" then giveAllPets(player) end
	end)
end
Players.PlayerAdded:Connect(hookAllPetsChat)
for _, p in ipairs(Players:GetPlayers()) do hookAllPetsChat(p) end
Players.PlayerRemoving:Connect(function(p) _G.playerOwnedPets[p] = nil; _G.playerEquippedPet[p] = nil; lastInvSync[p] = nil end)
-- send the initial (empty) inventory shortly after join so the Hub shows "No Pets Unlocked" until hatched
local function initInv(p) task.delay(2.5, function() if p.Parent then sendInventory(p) end end) end
Players.PlayerAdded:Connect(initInv)
for _, p in ipairs(Players:GetPlayers()) do initInv(p) end

print("[PetUpgrades] loaded -- Stegosaurus XP/level/evolve (grant on hatch, ] to level, _G.petOn* for XP)")
