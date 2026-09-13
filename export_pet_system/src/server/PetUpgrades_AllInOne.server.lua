--======================================================================
-- PetUpgrades_AllInOne.server.lua  (Server Script)
--======================================================================
-- The PET UPGRADE / EVOLVE / ROBUX system, lifted VERBATIM from
-- PetSystem.server.lua. This is the SERVER backbone that decides WHEN a pet
-- levels up; the client (PetMoveUpgrades_AllInOne.client.lua / PetFollow) then
-- shows the matching evolve look + trail when the new level arrives.
--
-- WHAT'S HERE (all server-authoritative -- the client only ever sends intents):
--   * XP CURVE        -- xpNeeded(L) = 80 * L^1.6 (1->8 quick, 20->25 a grind), cap 25.
--   * XP SOURCES      -- coins / distance-flown / gas-from-food / new-island feed XP
--                        to the EQUIPPED pet only (cosmetic -- never touches flight/coins).
--   * LEVEL UP        -- awardXP auto-levels carrying the remainder, fires the visual resync.
--   * EVOLVE TIERS    -- milestones at 3/8/13/18/23/25 (what unlocks each level: accessories,
--                        trail@5, aura@2, sparkles@8, orbs, ring, pulse, burst, gold@25).
--   * ROBUX TIER-SKIP -- 4 Developer Products (Common->...->Legendary). The client prompts the
--                        product; ProcessReceipt grants the jump, SERVER-AUTHORITATIVE (a cheap
--                        product can NEVER skip a higher tier -- validated by srcMin/srcMax).
--   * CRATE GRANT     -- _G.petGrantLevels(player, petId, n) for level-reward crates.
--
-- This file is SELF-CONTAINED: it keeps a tiny in-memory owned-pets store + its own
-- RemoteEvents so the whole flow RUNS + prints. In the real game these hooks live in
-- PetSystem and the store is persisted by PlayerStats. To watch it: it grants a demo pet
-- and feeds it XP so it evolves over ~seconds. Drop into ServerScriptService.
--======================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- ===== remotes (created if missing) =====
local function ev(name) local e = RS:FindFirstChild(name); if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end; return e end
local PetStateEvent      = ev("PetStateEvent")        -- s->c: re-apply the per-level evolve visual on the follower
local PetInventoryEvent  = ev("PetInventoryEvent")    -- s->c: refresh the card (level + XP bar)
local PetUpgradeEvent    = ev("PetUpgradeEvent")      -- c->s: free achievement upgrade
local PetProgressEvent   = ev("PetProgressEvent")     -- c->s: (petId, peakHeight, addTime)
local PetPendingUpgrade  = ev("PetPendingUpgradeEvent")-- c->s: (petId) declared before a Robux prompt

-- ============================================================================
-- IN-MEMORY STORE (the real game persists this via PlayerStats). owned[player][petId] = {level,xp,height,time,count,rare}
-- ============================================================================
_G.playerOwnedPets   = _G.playerOwnedPets   or {}
_G.playerEquippedPet = _G.playerEquippedPet or {}
local pendingRobuxPet = {}   -- [userId] = petId awaiting a Robux receipt
local upgradeReady    = {}   -- [player][petId] = last canUpgrade (avoid resend spam)

-- a tiny pet catalog (just enough to drive the system; the real one has 5+ pets w/ quest data)
local PETS = {
	BroccoliPet  = { displayName = "Broccoli Bunny", maxLevel = 25 },
	CoconutCrab  = { displayName = "Coconut Crab",   maxLevel = 25 },
	ButterDuck   = { displayName = "Butter Duck",    maxLevel = 25 },
}
local RARE_NAMES = { BroccoliPet="Emerald Bunny", CoconutCrab="Golden Crab", ButterDuck="Cosmic Duck" }

-- ============================================================================
-- ROBUX TIER-SKIP PRODUCTS (VERBATIM) -- 4 prices, each jumps to the FIRST level
-- of the NEXT tier. SERVER-AUTHORITATIVE: a receipt only applies if the pet is
-- actually in that product's SOURCE tier (srcMin..srcMax), so a cheap product can
-- NEVER be used to jump a higher tier. REPLACE the ids with real Developer Products.
-- ============================================================================
local PET_SKIP_PRODUCTS = {
	[123456701] = { target = 6,  srcMin = 1,  srcMax = 5,  price = 49,  to = "Uncommon"  }, -- Common  -> Uncommon
	[123456702] = { target = 11, srcMin = 6,  srcMax = 10, price = 99,  to = "Rare"      }, -- Uncommon-> Rare
	[123456703] = { target = 16, srcMin = 11, srcMax = 15, price = 299, to = "Epic"      }, -- Rare    -> Epic
	[123456704] = { target = 21, srcMin = 16, srcMax = 20, price = 599, to = "Legendary" }, -- Epic    -> Legendary
}

-- ============================================================================
-- LEVELING (cosmetic prestige -- 1..25, XP-driven, NO gameplay effect) -- VERBATIM
-- ============================================================================
local PET_MAX_LEVEL = 25
-- Rising XP curve: each level needs progressively more (base * level^1.6) so 1->8 is quick and 20->25 a grind.
local PET_XP_BASE, PET_XP_EXP = 80, 1.6
local function xpNeeded(level)
	if level >= PET_MAX_LEVEL then return math.huge end
	return math.floor(PET_XP_BASE * (level ^ PET_XP_EXP))
end
-- XP award RATES (all tuning lives here). Cosmetic-only -- NEVER touch flight/gas/coins balance.
local XP_PER_COIN        = 0.15  -- coins earned -> XP (proportional)
local XP_PER_FLIGHT_TICK = 6     -- each 0.5s coin tick DURING FLIGHT -> "distance flown" XP
local XP_PER_GAS         = 0.5   -- gas/power from eating food -> XP
local XP_PER_ISLAND      = 600   -- reaching a NEW island -> a chunk of XP

-- The EVOLVE tier description for a level (what the look becomes) -- diagnostics + card hint. VERBATIM.
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

-- ===== ownership + data helpers (in-memory copies of the real ones) =====
local function ownsPet(player, petId)
	local op = _G.playerOwnedPets[player]; return op ~= nil and op[petId] ~= nil
end
local function getPetData(player, petId)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local v = op[petId]; if v == nil then return nil end
	if type(v) ~= "table" then v = {}; op[petId] = v end
	v.level = v.level or 1; v.xp = v.xp or 0; v.height = v.height or 0; v.time = v.time or 0
	v.count = math.max(1, math.floor(tonumber(v.count) or 1))
	if v.level > PET_MAX_LEVEL then v.level = PET_MAX_LEVEL; v.xp = 0 end
	return v
end

-- ===== visual resync: tell the client to re-apply the evolve look + trail for the new level =====
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
-- LEVEL UP + XP  (VERBATIM)
-- ============================================================================
local function levelUp(player, petId, via)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return false end
	if d.level >= PET_MAX_LEVEL then return false end
	d.level = d.level + 1
	print("[PetLvl] "..petId.." LEVELED UP to "..d.level.." (via "..tostring(via)..")")
	if isMilestone(d.level) then print("[PetLvl] "..petId.." hit milestone "..d.level.." -> "..tierVisual(d.level)) end
	sendState(player)     -- the follower re-applies its per-level cosmetic evolve visual (+ trail at 5+)
	sendInventory(player) -- the card shows the new level + reset XP bar
	return true
end
local lastInvSync = {}
local function syncXP(player, force)
	local now = os.clock()
	if force or not lastInvSync[player] or (now - lastInvSync[player]) >= 2.5 then
		lastInvSync[player] = now; sendInventory(player)
	end
end
-- Award XP to the EQUIPPED pet ONLY. Auto-levels carrying the remainder, up to MAX. Cosmetic -- never touches flight/coins.
local function awardXP(player, amount, source)
	amount = tonumber(amount) or 0; if amount <= 0 then return end
	local petId = _G.playerEquippedPet[player]; if not petId or not ownsPet(player, petId) then return end
	local d = getPetData(player, petId); if not d then return end
	if d.level >= PET_MAX_LEVEL then return end
	d.xp = d.xp + amount
	local leveled = false
	while d.level < PET_MAX_LEVEL do
		local need = xpNeeded(d.level)
		if d.xp < need then break end
		d.xp = d.xp - need
		levelUp(player, petId, "xp:"..tostring(source))
		leveled = true
	end
	if d.level >= PET_MAX_LEVEL then d.xp = 0 end
	if not leveled then syncXP(player, false) end
end
-- XP SOURCE HOOKS (called from PlayerStats' coin/food/island handlers in the real game). --
_G.petAwardXP      = function(player, amount, source) awardXP(player, amount, source) end
_G.petOnCoins      = function(player, coins) awardXP(player, (tonumber(coins) or 0) * XP_PER_COIN, "coins") end
_G.petOnFlightTick = function(player)        awardXP(player, XP_PER_FLIGHT_TICK, "distance") end
_G.petOnGas        = function(player, gas)   awardXP(player, (tonumber(gas) or 0) * XP_PER_GAS, "gas") end
_G.petOnIsland     = function(player)        awardXP(player, XP_PER_ISLAND, "island") end

-- CRATE: grant N levels to an owned pet (level-reward crate). VERBATIM.
_G.petGrantLevels = function(player, petId, n)
	n = math.floor(tonumber(n) or 0); if n <= 0 then return nil end
	if not ownsPet(player, petId) then return nil end
	local d = getPetData(player, petId); if not d then return nil end
	local oldLevel = d.level
	if oldLevel >= PET_MAX_LEVEL then return oldLevel, oldLevel, 0 end
	local target = math.min(PET_MAX_LEVEL, oldLevel + n)
	while d.level < target do if not levelUp(player, petId, "crate") then break end end
	return oldLevel, d.level, (d.level - oldLevel)
end

-- ============================================================================
-- TIER SKIP (the Robux upgrade)  (VERBATIM)
-- ============================================================================
local function nextTierTarget(level)
	if level <= 5 then return 6
	elseif level <= 10 then return 11
	elseif level <= 15 then return 16
	elseif level <= 20 then return 21
	else return nil end -- Legendary (top tier) -> nothing to skip
end
-- Apply a one-tier jump from the CURRENT level (test path; computed server-side so it can never skip >1 tier).
local function tierSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	local target = nextTierTarget(d.level)
	if not target then return false end
	d.level = target; d.xp = 0
	sendState(player); sendInventory(player)
	print("[PetLvl] tier-skip "..tostring(via).." for "..petId.." -> Lvl "..d.level)
	return true
end

-- ===== ROBUX SKIP path: client declares which pet it's skipping, THEN prompts the Developer Product. The actual
-- jump is gated behind ProcessReceipt (a real purchase). VERBATIM. =====
PetPendingUpgrade.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	-- ⚠ TEST skip path: test accounts skip INSTANTLY (no real purchase) so the flow is testable. REMOVE BEFORE LAUNCH.
	if _G.isAllowedTestUser and _G.isAllowedTestUser(player) then
		tierSkip(player, petId, "test")
		return
	end
	pendingRobuxPet[player.UserId] = petId
end)
-- Apply the tier-skip after a real receipt. SERVER-AUTHORITATIVE: only applies in this product's source tier.
_G.petsHandleReceipt = function(player, productId)
	local prod = PET_SKIP_PRODUCTS[productId]
	if not prod then return false end -- not one of our tier-skip products
	local petId = pendingRobuxPet[player.UserId]; pendingRobuxPet[player.UserId] = nil
	if not (petId and ownsPet(player, petId)) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= prod.srcMin and d.level <= prod.srcMax then
		d.level = prod.target; d.xp = 0 -- only applies in this product's SOURCE tier (cheap product can't jump a higher tier)
		sendState(player); sendInventory(player)
		print("[PetLvl] tier-skip PURCHASED (to "..prod.to..") for "..petId.." -> Lvl "..d.level)
		return true
	end
	warn("[PetLvl] tier-skip product "..tostring(productId).." not applicable for "..petId.." (Lvl "..d.level.."); consumed, no jump")
	return true
end
-- Wire the receipt handler. In the real game PlayerStats owns the SINGLE ProcessReceipt and calls
-- _G.petsHandleReceipt; here we own it so the Robux path is complete + real end-to-end.
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local ok = _G.petsHandleReceipt(player, info.ProductId)
	if ok then return Enum.ProductPurchaseDecision.PurchaseGranted end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ===== FREE (achievement) upgrade + flight-progress gate (VERBATIM-ish; thresholds simplified here) =====
PetUpgradeEvent.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	levelUp(player, petId, "achievement")
end)
PetProgressEvent.OnServerEvent:Connect(function(player, petId, peakHeight, addTime)
	if not ownsPet(player, petId) then return end
	if _G.playerEquippedPet[player] ~= petId then return end -- only the equipped pet accrues progress
	local d = getPetData(player, petId)
	peakHeight = tonumber(peakHeight) or 0; addTime = tonumber(addTime) or 0
	if peakHeight > d.height then d.height = peakHeight end
	if addTime > 0 and addTime <= 30 then d.time = d.time + addTime end
	-- here flight progress simply feeds XP (the real game also gates a free achievement upgrade on height/time)
	awardXP(player, XP_PER_FLIGHT_TICK, "distance")
end)

-- ============================================================================
-- DEMO: grant a pet on join + feed it XP so it EVOLVES over ~seconds, so you can
-- watch the level-ups + milestones print and the client visuals + trail update.
-- ============================================================================
local function setupDemo(player)
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerOwnedPets[player]["CoconutCrab"] = { level = 1, xp = 0, height = 0, time = 0 }
	_G.playerEquippedPet[player] = "CoconutCrab"
	sendState(player); sendInventory(player)
	print("[PetUpgrades] granted demo CoconutCrab to "..player.Name.." (Lv1) -- feeding XP...")
	task.spawn(function()
		while player.Parent and (getPetData(player, "CoconutCrab") or {}).level < PET_MAX_LEVEL do
			task.wait(1)
			_G.petOnCoins(player, 220) -- simulate coins earned -> XP (220 * 0.15 = 33 XP/sec; ramps the early levels fast)
		end
		if player.Parent then print("[PetUpgrades] CoconutCrab reached MAX (Lv25) for "..player.Name) end
	end)
end
Players.PlayerAdded:Connect(setupDemo)
for _, p in ipairs(Players:GetPlayers()) do setupDemo(p) end

print("[PetUpgrades] upgrade/evolve/Robux system loaded (XP curve, tier-skip products, ProcessReceipt)")
