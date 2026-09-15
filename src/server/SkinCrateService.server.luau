-- ============================================================================================================
-- SKIN CRATE SERVICE (server) -- AUTHORITY for pet skins, traits, Crate Tokens, and crate openings.
-- ============================================================================================================
-- COSMETIC ONLY. Nothing in this file touches flight, gas, coins, or progression. It cannot: the only currency
-- it reads or writes is CrateTokens, and the only thing it grants is inventory entries.
--
-- WHAT IT OWNS
--   * The Crate Tokens balance          -> _G.playerCrateTokens   (persisted by PlayerStats as saved.crateTokens)
--   * The skin inventory                -> _G.playerPetSkins      (persisted as saved.petSkins)
--   * The equipped skin per pet         -> _G.playerEquippedSkins (persisted as saved.equippedSkins)
--   * The crate ROLL. The server picks the reward; the client only animates to it.
--
-- WHAT IT DELIBERATELY DOES NOT OWN
--   * Pet UNLOCKS. Those stay with PetSystem's island quests, untouched. This service only READS ownership
--     (to decide whether a skin is equippable yet) via _G.playerOwnedPets.
--   * Trading. The existing PetSystem trade session handles the handshake; this file just exposes the four
--     hooks it needs to move a skin entry (see the TRADE HOOKS section).
--   * Food Coins. Never read, never written. A skin crate cannot be bought with coins by construction.
--
-- SERVER-AUTHORITATIVE ROLL: the client sends only "open crate X". This file checks the balance, spends the
-- tokens, rolls rarity -> skin -> trait through the SHARED config, writes the inventory, and returns the result
-- WITH the reel index the client must land on. A tampered client can change what the animation looks like and
-- nothing else -- the granted item is already decided and already saved.
-- ============================================================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

-- ===== REMOTES (created FIRST, before the requires below, so a slow or failing module require can never leave
-- the client's WaitForChild hanging -- the same ordering CrateService.server.luau uses) =====
local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local SkinRemotes    = getOrCreate(ReplicatedStorage, "Folder", "SkinRemotes")
local GetSkinState   = getOrCreate(SkinRemotes, "RemoteFunction", "GetSkinState")   -- c->s RF: () -> full state
local OpenCrate      = getOrCreate(SkinRemotes, "RemoteFunction", "OpenCrate")      -- c->s RF: (crateId) -> result
local TradeUp        = getOrCreate(SkinRemotes, "RemoteFunction", "TradeUp")        -- c->s RF: (tier, keys[]) -> result
local EquipSkin      = getOrCreate(SkinRemotes, "RemoteEvent",    "EquipSkin")      -- c->s: (petId, skinId, traitId|false)
local BuyTokens      = getOrCreate(SkinRemotes, "RemoteEvent",    "BuyTokens")      -- c->s: (packId)
local SetTitle       = getOrCreate(SkinRemotes, "RemoteEvent",    "SetTitle")       -- c->s: (titleId|"")
local SkinStateEvent = getOrCreate(SkinRemotes, "RemoteEvent",    "SkinStateEvent") -- s->c: (state) push
local GoldAnnounce   = getOrCreate(SkinRemotes, "RemoteEvent",    "GoldAnnounce")   -- s->ALL: a Gold-tier pull
local CollectAnnounce = getOrCreate(SkinRemotes, "RemoteEvent",   "CollectAnnounce")-- s->c / s->ALL: a completed collection
print("[SkinCrate] SkinRemotes ready (GetSkinState, OpenCrate, TradeUp, EquipSkin, BuyTokens, SetTitle, "
	.. "SkinStateEvent, GoldAnnounce, CollectAnnounce)")

local Shared      = ReplicatedStorage:WaitForChild("DinosaurRealm")
local PetSkins    = require(Shared:WaitForChild("PetSkins"))
local PetTraits   = require(Shared:WaitForChild("PetTraits"))
local SkinCrates  = require(Shared:WaitForChild("SkinCrates"))
local CrateTokens = require(Shared:WaitForChild("CrateTokens"))
local PetCollection = require(Shared:WaitForChild("PetCollection"))

local rng = Random.new()

-- ===== PERSISTED STATE =====
-- Declared on _G (not as locals) and defaulted with `or {}` because server script load ORDER is not guaranteed:
-- PlayerStats' join handler may run before or after this file, and indexing a nil table would error out the
-- whole load path. This is the same defensive pattern PlayerStats uses for _G.playerOwnedPets / ownedGutSkins.
_G.playerCrateTokens   = _G.playerCrateTokens   or {} -- [player] = number
_G.playerPetSkins      = _G.playerPetSkins      or {} -- [player] = { ["PizzaDragon|Galaxy|Crowned"] = 3, ... }
_G.playerEquippedSkins = _G.playerEquippedSkins or {} -- [player] = { PizzaDragon = { skin="Galaxy", trait="Crowned" } }

-- Per-session, per-source token totals for the DAILY_CAPS safety net. Not persisted on purpose: these caps exist
-- to stop a BUG in a caller becoming an infinite faucet, not to limit a legitimate player, so a session-scoped
-- counter is the right blast radius. A designed daily limit belongs in the quest system that awards it.
local earnedThisSession = {} -- [player] = { [source] = number }

Players.PlayerRemoving:Connect(function(p)
	earnedThisSession[p] = nil
	-- lastOpen / lastPullGold are declared further down (next to openCrate); cleared here too so a rejoining
	-- player never inherits a stale open cooldown or a stale Gold flag.
	if _G.__skinCrateForget then _G.__skinCrateForget(p) end
end)

-- ============================================================================================================
-- PET WHEEL REMOVAL SWEEP
-- ============================================================================================================
-- The Pet Wheel is gone: its three source files are deleted and its Rojo entries removed. That stops Rojo
-- SYNCING it -- it does not remove the copies already saved into the place file, which keep running and keep
-- serving spins. Rojo only ever adds.
--
-- So the wheel is torn out at runtime too: its scripts, its remote folder, and its shared config. Levels come
-- from the Pet Level Crate now, and two systems both handing out pet levels -- one of them with published
-- odds, one of them not -- is exactly the kind of thing that quietly doubles a payout.
--
-- Safe to run more than once, and safe if the wheel was never in this place: everything is a lookup-then-
-- destroy on a name we no longer ship.
local function sweepPetWheel()
	local killed = 0
	for _, svcName in ipairs({ "ServerScriptService", "ServerStorage", "ReplicatedStorage", "ReplicatedFirst", "Workspace" }) do
		local ok, svc = pcall(function() return game:GetService(svcName) end)
		if ok and svc then
			for _, inst in ipairs(svc:GetDescendants()) do
				local n = inst.Name
				if (n == "PetWheel" and (inst:IsA("Script") or inst:IsA("LocalScript")))
					or (n == "PetWheelConfig" and inst:IsA("ModuleScript"))
					or n == "PetWheel_v1" then
					pcall(function()
						if inst:IsA("BaseScript") then inst.Disabled = true end
						inst:Destroy()
					end)
					killed = killed + 1
				end
			end
		end
	end
	if killed > 0 then
		warn(("[SkinCrate] removed %d leftover Pet Wheel instance(s) baked into the place. The wheel is retired --"
			.. " pet levels come from the Pet Level Crate. Delete them in Studio to stop this running every join.")
			:format(killed))
	end
end
sweepPetWheel()
task.delay(2, sweepPetWheel); task.delay(8, sweepPetWheel) -- again, for a stale copy that loads after us

-- ============================================================================================================
-- PET OWNERSHIP (read-only view of PetSystem's data)
-- ============================================================================================================
-- PetSystem stores ownership under a STORAGE KEY that is either a species id ("ButterDuck") or a species id plus
-- its rare suffix ("ButterDuck#R"). A skin belongs to the SPECIES, so a player who owns either variant can wear
-- it. This mirrors PetSystem's own speciesOf()/ownsSpecies() without reaching into its locals.
local RARE_SUFFIX = "#R"
local function speciesOf(key)
	if type(key) ~= "string" then return key end
	return (key:gsub(RARE_SUFFIX .. "$", ""))
end

local function ownsPetSpecies(player, petId)
	local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if not owned then return false end
	for key in pairs(owned) do
		if speciesOf(key) == petId then return true end
	end
	return false
end

-- The set of species this player has unlocked, for the client's "Unlock <Pet> to equip" labelling.
local function unlockedSet(player)
	local out = {}
	local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if owned then
		for key in pairs(owned) do out[speciesOf(key)] = true end
	end
	return out
end

-- ============================================================================================================
-- TOKENS
-- ============================================================================================================
local function tokenStat(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(CrateTokens.LEADERSTAT)
end

local function getTokens(player)
	return math.max(0, math.floor(tonumber(_G.playerCrateTokens[player]) or 0))
end

-- Writes the balance in ONE place so the in-memory value, the leaderstat, and the client push can never diverge.
local function setTokens(player, n)
	n = tonumber(n) or 0
	if n ~= n or n == math.huge or n == -math.huge then n = 0 end -- NaN / inf can never become a balance (NaN also breaks every save)
	n = math.clamp(math.floor(n), 0, CrateTokens.MAX_BALANCE)
	_G.playerCrateTokens[player] = n
	local st = tokenStat(player)
	if st then st.Value = n end
	-- SAVE ON EVERY CHANGE. The wallet is shared by every realm, so it cannot wait for the leave-save: a
	-- gift credited here must already be in the store when the friend's next realm reads it, and a server
	-- crash must not eat a purchase. The bridge coalesces bursts into one write.
	if _G.savePlayerData then pcall(_G.savePlayerData, player, "tokens") end
	return n
end

-- Raw credit. `reason` is for the log only. Returns the new balance.
local function addTokens(player, amount, reason)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return getTokens(player) end
	local newBal = setTokens(player, getTokens(player) + amount)
	print(string.format("[SkinCrate] +%d tokens to %s (%s) -> %d", amount, player.Name, tostring(reason or "?"), newBal))
	return newBal
end

local function spendTokens(player, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return true end
	local bal = getTokens(player)
	if bal < amount then return false end
	setTokens(player, bal - amount)
	return true
end

-- ============================================================================================================
-- INVENTORY
-- ============================================================================================================
local function inv(player)
	local t = _G.playerPetSkins[player]
	if not t then t = {}; _G.playerPetSkins[player] = t end
	return t
end

local function countOf(player, key)
	return math.max(0, math.floor(tonumber(inv(player)[key]) or 0))
end

-- Add ONE of a (pet, skin, trait) entry. Duplicates STACK on the same key; a different trait is a different key
-- and therefore a separate entry with its own count -- exactly the behaviour the spec describes.
local function addSkinEntry(player, petId, skinId, traitId, howMany)
	local key = PetSkins.makeKey(petId, skinId, traitId)
	local n = math.max(1, math.floor(tonumber(howMany) or 1))
	local t = inv(player)
	t[key] = countOf(player, key) + n
	return key, t[key]
end

-- Remove ONE. Drops the key entirely at zero so an empty entry never lingers in the save or the UI.
local function removeSkinEntry(player, key)
	local t = inv(player)
	local c = countOf(player, key)
	if c <= 0 then return false end
	if c <= 1 then t[key] = nil else t[key] = c - 1 end
	return true
end

-- ============================================================================================================
-- COLLECTION BOOK + COLLECTION REWARDS
-- ============================================================================================================
-- A pet is COMPLETE when the player owns every skin for it in any trait (see PetCollection's header for why
-- completion is trait-agnostic). Completing one pays out a title, an aura, a badge and an exclusive cosmetic;
-- completing every pet pays out the full-collection reward.
--
-- Rewards are recorded as OWNED, never as "granted once". checkCollection is idempotent and safe to call after
-- every single grant: it re-derives completion from the inventory and only acts on pets that aren't already in
-- completedPets. That matters because skins arrive from four different places now (crate, trade, trade-up,
-- dev command) and none of them should have to remember to run a reward step of their own.
local BadgeService = game:GetService("BadgeService")

_G.playerCollection = _G.playerCollection or {} -- [player] = { completedPets, titles, auras, activeTitle, activeAura, full }

local function collection(player)
	local c = _G.playerCollection[player]
	if not c then
		c = { completedPets = {}, titles = {}, auras = {}, activeTitle = "", activeAura = "", full = false }
		_G.playerCollection[player] = c
	end
	-- Defensive: a save written before a field existed loads without it.
	c.completedPets = c.completedPets or {}
	c.titles        = c.titles or {}
	c.auras         = c.auras or {}
	c.activeTitle   = c.activeTitle or ""
	c.activeAura    = c.activeAura or ""
	return c
end

-- [petId] = { [skinId] = true }, collapsing traits away. One pass over the inventory rather than one pass per
-- pet -- the book asks about all 11 pets at once and the inventory can run to a few hundred entries.
local function ownedSkinSetsByPet(player)
	local sets = {}
	for key, count in pairs(inv(player)) do
		if (tonumber(count) or 0) > 0 then
			local petId, skinId = PetSkins.parseKey(key)
			if petId and skinId then
				local s = sets[petId]
				if not s then s = {}; sets[petId] = s end
				s[skinId] = true
			end
		end
	end
	return sets
end
_G.skinOwnedSetsByPet = ownedSkinSetsByPet

local function awardBadge(player, badgeId)
	if type(badgeId) ~= "number" or badgeId <= 0 then return end -- 0 = badge not created yet; skip silently
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
		if ok and has then return end
		pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
	end)
end

-- Re-derive completion and pay out anything newly earned. Returns a list of reward notices for the client to
-- celebrate, or an empty table. Does NOT push state -- the caller does, so a grant + reward is one push.
local function checkCollection(player)
	local c = collection(player)
	local sets = ownedSkinSetsByPet(player)
	local info = {}
	if _G.petSpeciesInfo then
		local ok, t = pcall(_G.petSpeciesInfo)
		if ok and type(t) == "table" then info = t end
	end

	local species = {}
	if _G.petAllSpecies then
		local ok, list = pcall(_G.petAllSpecies)
		if ok and type(list) == "table" then species = list end
	end

	local notices = {}
	local completeCount = 0

	for _, petId in ipairs(species) do
		local done = PetCollection.isComplete(sets[petId])
		if done then completeCount = completeCount + 1 end
		if done and not c.completedPets[petId] then
			c.completedPets[petId] = true
			local petName = (info[petId] and info[petId].displayName) or petId
			local reward = PetCollection.rewardFor(petId, petName)

			if reward.title and reward.title ~= "" then c.titles[reward.title] = true end
			if reward.aura and PetCollection.AURAS[reward.aura] then c.auras[reward.aura] = true end
			awardBadge(player, reward.badgeId)
			-- The "exclusive cosmetic" is a real inventory entry: it lands with no trait so it stacks with any
			-- copy the player already had, and it shows up in the book like any other skin.
			if reward.cosmetic and PetSkins.exists(reward.cosmetic) then
				addSkinEntry(player, petId, reward.cosmetic, nil, 1)
			end

			notices[#notices + 1] = {
				kind = "pet", pet = petId, petName = petName,
				title = reward.title, aura = reward.aura, cosmetic = reward.cosmetic,
			}
			print(string.format("[SkinCrate] %s COMPLETED the %s collection -> title '%s', aura '%s'",
				player.Name, petName, tostring(reward.title), tostring(reward.aura)))
		end
	end

	-- FULL COLLECTION: every species complete. Guarded on #species > 0 so an early call, before PetSystem has
	-- published its catalogue, can't award the game's rarest prize for owning nothing.
	if #species > 0 and completeCount >= #species and not c.full then
		c.full = true
		local F = PetCollection.FULL_COLLECTION
		if F.title and F.title ~= "" then c.titles[F.title] = true end
		if F.aura and PetCollection.AURAS[F.aura] then c.auras[F.aura] = true end
		awardBadge(player, F.badgeId)
		if F.grantSkinOnEveryPet and PetSkins.exists(F.grantSkinOnEveryPet) then
			for _, petId in ipairs(species) do
				addSkinEntry(player, petId, F.grantSkinOnEveryPet, nil, 1)
			end
		end
		notices[#notices + 1] = { kind = "full", title = F.title, aura = F.aura, cosmetic = F.grantSkinOnEveryPet }
		print("[SkinCrate] *** " .. player.Name .. " COMPLETED THE FULL COLLECTION ***")
		if F.announce then
			pcall(function()
				CollectAnnounce:FireAllClients({ playerName = player.Name, kind = "full", title = F.title })
			end)
		end
	end

	if #notices > 0 then
		pcall(function() CollectAnnounce:FireClient(player, { kind = "earned", notices = notices }) end)
	end
	return notices
end
_G.skinCheckCollection = checkCollection

-- ============================================================================================================
-- STATE PUSH
-- ============================================================================================================
-- One payload the client renders everything from: balance, inventory, what's equipped, and which pets are
-- unlocked (so a skin for a locked pet can show "Unlock <Pet> to equip" without a second round-trip).
local function buildState(player)
	local equipped = {}
	for petId, e in pairs(_G.playerEquippedSkins[player] or {}) do
		if type(e) == "table" then equipped[petId] = { skin = e.skin, trait = e.trait } end
	end
	local c = collection(player)
	return {
		tokens   = getTokens(player),
		skins    = inv(player),
		equipped = equipped,
		unlocked = unlockedSet(player),
		-- Collection Book + rewards. Sent on every push so the book, the completion ticks and the title/aura
		-- pickers all repaint from the same payload the inventory does -- there is no second fetch that could
		-- show a stale "you're missing Galaxy" a moment after Galaxy landed.
		collection = {
			completedPets = c.completedPets,
			titles        = c.titles,
			auras         = c.auras,
			activeTitle   = c.activeTitle,
			activeAura    = c.activeAura,
			full          = c.full,
		},
	}
end

local function pushState(player)
	if not player.Parent then return end
	-- Collection rewards are evaluated HERE, on the way out, rather than at each of the four places a skin can
	-- arrive (crate open, trade, trade-up, dev grant). Every one of those already ends in a pushState, so hanging
	-- the check off this single point means no future grant path can forget to run it. checkCollection is
	-- idempotent and never calls back into pushState, so this cannot loop; any cosmetic it grants is written
	-- before buildState reads the inventory, and therefore ships in this same payload.
	pcall(checkCollection, player)
	pcall(function() SkinStateEvent:FireClient(player, buildState(player)) end)
end

-- ============================================================================================================
-- EQUIP
-- ============================================================================================================
-- Rules, all enforced here:
--   * You must OWN the exact (pet, skin, trait) entry.
--   * You must have UNLOCKED that pet's species. A skin for a locked pet stays in the inventory and is refused
--     here -- which is why the client shows "Unlock <Pet> to equip" rather than hiding it. The moment the pet is
--     unlocked through its normal quest, this check starts passing with no migration step: nothing about the
--     stored skin changes, so it "becomes usable automatically".
--   * skinId = false/nil clears the pet back to its default look.
local function equipSkin(player, petId, skinId, traitId)
	if type(petId) ~= "string" then return false, "bad_pet" end

	local eq = _G.playerEquippedSkins[player]
	if not eq then eq = {}; _G.playerEquippedSkins[player] = eq end

	-- clear
	if skinId == false or skinId == nil then
		eq[petId] = nil
		pushState(player)
		return true
	end

	if not PetSkins.exists(skinId) then return false, "bad_skin" end
	if traitId == false then traitId = nil end
	if traitId ~= nil and not PetTraits.exists(traitId) then return false, "bad_trait" end

	-- UPGRADE LEGACY IDS ON THE WAY IN. The first-generation skins/traits (Stone, Galaxy, Crowned,
	-- Sparkly...) still exist in old saves and in trades; exists() accepts them, so without this they
	-- would be stored back verbatim forever and every reader would have to re-map them. normalise()
	-- resolves each to its modern identity once, here, at the single point where an equip is recorded.
	-- Both maps cover every id this realm ever shipped, so nothing is dropped -- see PetSkins.LEGACY
	-- and PetTraits.LEGACY.
	skinId = PetSkins.normalise and PetSkins.normalise(skinId) or skinId
	if traitId ~= nil and PetTraits.normalise then traitId = PetTraits.normalise(traitId) end

	local key = PetSkins.makeKey(petId, skinId, traitId)
	if countOf(player, key) <= 0 then return false, "not_owned" end
	if not ownsPetSpecies(player, petId) then return false, "pet_locked" end

	eq[petId] = { skin = skinId, trait = traitId }
	print(string.format("[SkinCrate] %s equipped %s on %s%s", player.Name, skinId, petId,
		traitId and (" (" .. traitId .. ")") or ""))
	-- pushState is what makes the pet repaint: the client's applyState calls repaintAll on every push, so the
	-- follower re-skins the moment this lands. No separate render hook is needed.
	pushState(player)
	return true
end

-- ============================================================================================================
-- THE CRATE OPEN
-- ============================================================================================================
-- Returns a result table the client animates from:
--   { ok=true, crateId, rarity, pet, skin, trait, key, reelIndex, isGold, newCount, tokens, locked }
--   { ok=false, reason = "unknown_crate" | "not_enough_tokens" | "empty_crate" | "cooldown" }
--
-- ORDER OF OPERATIONS matters for anti-dupe: tokens are spent BEFORE the grant, and the grant is written to the
-- in-memory inventory synchronously (no yields between spend and grant), so there is no window where a second
-- request could ride the same balance. The save is kicked off afterwards.
local OPEN_COOLDOWN = 0.35 -- seconds; stops a held/scripted button spamming rolls faster than the reveal can play
local lastOpen = {}        -- [player] = tick()
local lastPullGold = {}    -- [player] = boolean  [REMOVE BEFORE LAUNCH] only /goldtest reads this
-- Cleanup hook for the PlayerRemoving handler above (which runs before these locals exist).
-- lastTradeUp lives even further down (next to doTradeUp); the same hook clears it, guarded because this
-- function is defined before that table exists.
_G.__skinCrateForget = function(p)
	lastOpen[p] = nil
	lastPullGold[p] = nil
	if _G.__skinTradeUpForget then _G.__skinTradeUpForget(p) end
end

-- `noSave` is for the DEV force-open path ONLY. /goldtest can fire thousands of opens to find a 0.08% pull, and
-- one DataStore write per open would throttle the whole game's saving. The grant itself is identical either way;
-- only the persist call is skipped, and the next ordinary save writes everything anyway.
-- ============================================================================================================
-- PET LEVEL CRATES
-- ============================================================================================================
-- The Pet Level Crate pays LEVELS, not skins. It rides the same roll, the same reel index and the same honest
-- odds as every other crate -- only the payout differs -- so there is no second lottery to audit.
--
-- WHERE THE LEVELS GO: the pet you have EQUIPPED first, then any other unmaxed pet, lowest level first. The
-- spill matters because levels clamp at the cap: pulling +7 onto a pet two levels off max would silently bin
-- five of them. Spilling means a paid open is never partly wasted, and levelling the pet you are actually
-- looking at is what a player expects without having to be asked.
--
-- The old wheel solved this by holding levels 'pending' and making you pick a pet in a second panel. Choosing
-- for you removes that whole step and cannot leave levels stranded in a pending bucket.
local function grantPetLevels(player, amount)
	local owned = (_G.petListOwned and _G.petListOwned(player)) or {}
	local queue = {}
	for _, p in ipairs(owned) do if not p.maxed then queue[#queue + 1] = p end end
	if #queue == 0 then return nil end -- caller refuses the open; see all_pets_maxed

	-- equipped pet to the front, then lowest level first so the spill tops up your weakest
	local equipped = _G.playerEquippedPet and _G.playerEquippedPet[player]
	local eqSpecies = equipped and speciesOf(equipped) or nil
	table.sort(queue, function(a, b)
		local ae, be = (a.petId == eqSpecies), (b.petId == eqSpecies)
		if ae ~= be then return ae end
		if a.level ~= b.level then return a.level < b.level end
		return a.petId < b.petId
	end)

	local left, grants = amount, {}
	for _, p in ipairs(queue) do
		if left <= 0 then break end
		local old, new, added = _G.petGrantLevels(player, p.petId, left)
		if added and added > 0 then
			left = left - added
			grants[#grants + 1] = { petId = p.petId, name = p.displayName, from = old, to = new, added = added }
		end
	end
	if #grants == 0 then return nil end -- every pet turned out to be maxed after all
	return grants, (amount - left)
end

local function openCrate(player, crateId, noSave)
	local crate = SkinCrates.getCrate(crateId)
	if not crate then return { ok = false, reason = "unknown_crate" } end

	local now = tick()
	if lastOpen[player] and (now - lastOpen[player]) < OPEN_COOLDOWN and not noSave then
		return { ok = false, reason = "cooldown" }
	end

	if getTokens(player) < crate.price then
		return { ok = false, reason = "not_enough_tokens", need = crate.price, have = getTokens(player) }
	end

	-- A level crate with nothing to level would charge for nothing. Refuse BEFORE spending -- the same rule
	-- BuyFoodEvent follows when the stomach is full: the player keeps their tokens.
	if SkinCrates.isLevelCrate(crate) and _G.petHasUnmaxed and not _G.petHasUnmaxed(player) then
		return { ok = false, reason = "all_pets_maxed" }
	end

	-- ROLL FIRST, so a crate that turns out to be unopenable (all bands empty) costs nothing.
	local rarity, entry, reelIndex = SkinCrates.roll(rng, crateId)
	if not rarity or not entry then return { ok = false, reason = "empty_crate" } end
	local traitId = PetTraits.roll(rng)

	-- SPEND then GRANT, synchronously.
	if not spendTokens(player, crate.price) then
		return { ok = false, reason = "not_enough_tokens", need = crate.price, have = getTokens(player) }
	end
	lastOpen[player] = now

	-- LEVEL CRATE: grant levels and return early. Deliberately does NOT touch the skin inventory, does not roll
	-- into the Collection Book, and cannot announce a Gold skin -- there is no skin involved at any point.
	if SkinCrates.isLevelCrate(crate) then
		local grants, applied = grantPetLevels(player, entry.levels)
		if not grants then
			-- Every pet maxed between the check above and here (a level-up landed mid-open). Refund and bail:
			-- the tokens are already spent at this point, so returning without this would just eat them.
			addTokens(player, crate.price, "refund: level crate had nothing to level")
			return { ok = false, reason = "all_pets_maxed" }
		end
		print(string.format("[SkinCrate] %s opened %s -> [%s] +%d pet level(s), %d applied across %d pet(s)",
			player.Name, crate.id, rarity, entry.levels, applied, #grants))
		pushState(player)
		if not noSave and _G.savePlayerData then pcall(function() _G.savePlayerData(player, "crate_open") end) end
		return {
			ok = true, crateId = crate.id, rarity = rarity, kind = "levels",
			levels = entry.levels, applied = applied, grants = grants,
			reelIndex = reelIndex, isGold = (rarity == SkinCrates.GOLD_TIER),
			tokens = getTokens(player),
		}
	end

	local key, newCount = addSkinEntry(player, entry.pet, entry.skin, traitId, 1)

	local isGold = (rarity == SkinCrates.GOLD_TIER)
	local locked = not ownsPetSpecies(player, entry.pet)
	lastPullGold[player] = isGold -- [REMOVE BEFORE LAUNCH] /goldtest polls this

	print(string.format("[SkinCrate] %s opened %s -> [%s] %s %s%s%s (x%d)%s",
		player.Name, crate.id, rarity, entry.skin, entry.pet,
		PetTraits.isNone(traitId) and "" or (" +" .. traitId),
		locked and " [PET LOCKED]" or "", newCount, isGold and "  *** GOLD ***" or ""))

	pushState(player)

	-- GOLD is the knife pull: everyone hears about it. Fired to ALL clients so the reveal can be celebrated
	-- server-wide, the same way a rare pet hatch broadcasts today.
	if isGold then
		pcall(function()
			GoldAnnounce:FireAllClients({
				playerName = player.Name, crateId = crate.id, crateName = crate.displayName,
				pet = entry.pet, skin = entry.skin, trait = traitId,
			})
		end)
	end

	-- Persist now: a crate open is a purchase-equivalent event, so it must survive a crash the same way a trade
	-- does. PlayerStats owns the actual write. Skipped on the dev force-open path (see `noSave` above).
	if not noSave and _G.savePlayerData then pcall(function() _G.savePlayerData(player, "crate_open") end) end

	return {
		ok = true, crateId = crate.id, rarity = rarity,
		pet = entry.pet, skin = entry.skin, trait = traitId,
		key = key, reelIndex = reelIndex, isGold = isGold,
		newCount = newCount, tokens = getTokens(player), locked = locked,
	}
end

-- ============================================================================================================
-- TRADE UPS
-- ============================================================================================================
-- Hand in SkinCrates.TRADE_UP.COST skins of ONE rarity, get back 1 random skin of the next rarity up. The pet is
-- random, the skin is random, and the trait rolls fresh -- a trade-up is its own pull, not a guaranteed upgrade
-- of what went in.
--
-- The client sends the exact inventory keys it wants to spend, so the player chooses which duplicates burn. The
-- server re-validates all of it: every key must exist, must be owned in sufficient quantity (the SAME key may
-- legitimately appear several times when spending a stack of duplicates), and must be the claimed rarity.
--
-- ANTI-DUPE: the whole consume-then-grant runs with no yields, so two requests can't both pass validation
-- against the same stack. Validation is done in full against a tally BEFORE anything is removed, so a request
-- that turns out to be short leaves the inventory untouched rather than half-consumed.
local TRADEUP_COOLDOWN = 0.5
local lastTradeUp = {} -- [player] = tick()
_G.__skinTradeUpForget = function(p) lastTradeUp[p] = nil end

local function doTradeUp(player, tier, keys)
	if type(tier) ~= "string" or type(keys) ~= "table" then return { ok = false, reason = "bad_request" } end

	local target = SkinCrates.tradeUpTarget(tier)
	if not target then return { ok = false, reason = "top_of_ladder" } end

	local need = SkinCrates.TRADE_UP.COST
	if #keys ~= need then return { ok = false, reason = "wrong_count", need = need, got = #keys } end

	local now = tick()
	if lastTradeUp[player] and (now - lastTradeUp[player]) < TRADEUP_COOLDOWN then
		return { ok = false, reason = "cooldown" }
	end

	-- VALIDATE EVERYTHING FIRST. `want` tallies how many of each key this contract consumes, so submitting the
	-- same key 10 times is only legal when the player actually holds 10 of it.
	local want = {}
	for _, key in ipairs(keys) do
		if type(key) ~= "string" then return { ok = false, reason = "bad_key" } end
		local petId, skinId = PetSkins.parseKey(key)
		if not petId or not skinId or not PetSkins.exists(skinId) then
			return { ok = false, reason = "bad_key" }
		end
		if PetSkins.tierOf(skinId) ~= tier then
			return { ok = false, reason = "wrong_rarity", key = key }
		end
		want[key] = (want[key] or 0) + 1
	end
	for key, n in pairs(want) do
		if countOf(player, key) < n then
			return { ok = false, reason = "not_owned", key = key, need = n, have = countOf(player, key) }
		end
	end

	-- ROLL BEFORE CONSUMING, so a target rarity that somehow has no pool costs the player nothing.
	local pool = SkinCrates.tradeUpPool(target)
	if #pool == 0 then return { ok = false, reason = "empty_pool", target = target } end
	local won = pool[rng:NextInteger(1, #pool)]
	local traitId = PetTraits.roll(rng)

	-- CONSUME, then GRANT. No yields in between.
	lastTradeUp[player] = now
	for _, key in ipairs(keys) do
		removeSkinEntry(player, key)
	end
	local newKey, newCount = addSkinEntry(player, won.pet, won.skin, traitId, 1)

	local isGold = (target == SkinCrates.GOLD_TIER)
	local locked = not ownsPetSpecies(player, won.pet)
	print(string.format("[SkinCrate] %s traded up %dx %s -> [%s] %s %s%s%s",
		player.Name, need, tier, target, won.skin, won.pet,
		PetTraits.isNone(traitId) and "" or (" +" .. traitId),
		locked and " [PET LOCKED]" or ""))

	pushState(player)

	if isGold then
		pcall(function()
			GoldAnnounce:FireAllClients({
				playerName = player.Name, crateId = "TradeUp", crateName = "Trade Up",
				pet = won.pet, skin = won.skin, trait = traitId,
			})
		end)
	end

	-- Persist: a trade-up destroys 10 items, so it must survive a crash exactly like a trade does.
	if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "trade_up") end) end

	return {
		ok = true, from = tier, rarity = target,
		pet = won.pet, skin = won.skin, trait = traitId,
		key = newKey, newCount = newCount, isGold = isGold, locked = locked,
		consumed = need, tokens = getTokens(player),
	}
end

-- ============================================================================================================
-- REMOTE WIRING
-- ============================================================================================================
GetSkinState.OnServerInvoke = function(player)
	return buildState(player)
end

OpenCrate.OnServerInvoke = function(player, crateId)
	if type(crateId) ~= "string" then return { ok = false, reason = "unknown_crate" } end
	local ok, result = pcall(openCrate, player, crateId)
	if not ok then
		warn("[SkinCrate] openCrate error: " .. tostring(result))
		return { ok = false, reason = "error" }
	end
	return result
end

TradeUp.OnServerInvoke = function(player, tier, keys)
	local ok, result = pcall(doTradeUp, player, tier, keys)
	if not ok then
		warn("[SkinCrate] tradeUp error: " .. tostring(result))
		return { ok = false, reason = "error" }
	end
	return result
end

EquipSkin.OnServerEvent:Connect(function(player, petId, skinId, traitId)
	pcall(equipSkin, player, petId, skinId, traitId)
end)

-- Display title / aura. Both are cosmetic-only and must already be OWNED -- passing "" clears. Anything the
-- player hasn't earned is silently refused rather than errored, so a stale client can't spam warnings.
SetTitle.OnServerEvent:Connect(function(player, titleId, auraId)
	local c = collection(player)
	if titleId ~= nil then
		if titleId == "" or titleId == false then c.activeTitle = ""
		elseif type(titleId) == "string" and c.titles[titleId] then c.activeTitle = titleId end
	end
	if auraId ~= nil then
		if auraId == "" or auraId == false then c.activeAura = ""
		elseif type(auraId) == "string" and c.auras[auraId] then c.activeAura = auraId end
	end
	pushState(player)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "collection_title") end) end
end)

-- Token packs. In TEST_MODE the server credits directly (the same addTokens the real receipt path calls) so the
-- whole flow is testable before the Developer Products exist. Once TEST_MODE is false this verb is refused
-- outright, so an old client can't farm free tokens from a shipped build.
BuyTokens.OnServerEvent:Connect(function(player, packId)
	local pack = SkinCrates.packById(packId)
	if not pack then return end
	-- THE FREE-TOKEN FAUCET ONLY EXISTS IN STUDIO. TEST_MODE credits packs without Robux so the flow can be
	-- tested before the products exist -- but the wallet is universe-wide now, so a shipped build with this
	-- open would let any client mint unlimited tokens and gift them into every realm. Outside Studio the
	-- flag is ignored and the real purchase prompt runs.
	if SkinCrates.TEST_MODE and game:GetService("RunService"):IsStudio() then
		addTokens(player, pack.tokens, "TEST_MODE pack " .. pack.id)
		pushState(player)
		if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "tokens_test") end) end
	else
		pcall(function() MarketplaceService:PromptProductPurchase(player, pack.productId) end)
	end
end)

-- ============================================================================================================
-- DEVELOPER PRODUCT RECEIPTS
-- ============================================================================================================
-- PlayerStats owns MarketplaceService.ProcessReceipt (only one script may assign it), and calls into each
-- system's handler in turn -- the same pattern as _G.petsHandleReceipt. Returns true
-- only when THIS system recognised and granted the product, so PlayerStats knows to report PurchaseGranted.
_G.skinCrateHandleReceipt = function(player, productId)
	local pack = SkinCrates.packByProductId(productId)
	if not pack then return false end
	addTokens(player, pack.tokens, "product " .. tostring(productId))
	pushState(player)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "tokens_purchase") end) end
	return true
end

-- ============================================================================================================
-- PUBLIC API for the rest of the game (quests, realms, streaks, events, codes)
-- ============================================================================================================
-- ONE entry point, so every token grant in the game goes through the same cap + clamp + log + save. Callers pass
-- a SOURCE NAME from CrateTokens.REWARDS rather than an amount, which means retuning the economy is a one-line
-- edit in the shared config and never a hunt through call sites.
--
--   _G.crateTokensAward(player, "dailyTask")
--   _G.crateTokensAward(player, "loginStreak", 5)     -- day 5 of the streak
--   _G.crateTokensAward(player, "promoCode", nil, 500) -- explicit override amount
_G.crateTokensAward = function(player, source, arg, overrideAmount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return 0 end
	local amount = tonumber(overrideAmount) or CrateTokens.amountFor(source, arg)
	amount = math.floor(amount or 0)
	if amount <= 0 then return 0 end

	-- DAILY_CAPS safety net (see earnedThisSession above for why this is session-scoped).
	local cap = CrateTokens.dailyCap(source)
	if cap then
		local bucket = earnedThisSession[player]
		if not bucket then bucket = {}; earnedThisSession[player] = bucket end
		local already = bucket[source] or 0
		if already >= cap then
			print(string.format("[SkinCrate] token cap hit for %s on '%s' (%d/%d) -- granting 0",
				player.Name, tostring(source), already, cap))
			return 0
		end
		amount = math.min(amount, cap - already)
		bucket[source] = already + amount
	end

	addTokens(player, amount, source)
	pushState(player)
	return amount
end

-- Grant a specific skin outside a crate (an event reward, a promo code, a quest-line prize). Rolls a trait too
-- unless one is passed, so an event skin can still surprise you.
_G.skinGrant = function(player, petId, skinId, traitId, howMany)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
	if type(petId) ~= "string" or not PetSkins.exists(skinId) then return nil end
	if traitId == nil then traitId = PetTraits.roll(rng) end
	if traitId ~= "" and not PetTraits.exists(traitId) then traitId = "" end
	local key, newCount = addSkinEntry(player, petId, skinId, traitId, howMany or 1)
	print(string.format("[SkinCrate] granted %s %s %s%s (x%d)", player.Name, skinId, petId,
		PetTraits.isNone(traitId) and "" or (" +" .. traitId), newCount))
	pushState(player)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "skin_grant") end) end
	return key, newCount
end

-- Read helpers other systems can use without touching the tables directly.
_G.crateTokensBalance = function(player) return getTokens(player) end

-- Move Crate Tokens between two players as ONE synchronous step, for the trade window. Returns true only if the
-- whole move happened. Called from PetSystem's executeTrade, which has already validated everything else.
--
-- Food Coins are deliberately NOT tradeable and there is no equivalent of this function for them: tradeable
-- gameplay currency is how a progression economy gets laundered by alt accounts. Tokens are cosmetic-only, so
-- moving them can't buy anyone a shortcut through the islands.
_G.crateTokensTrade = function(from, to, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return true end -- nothing to move is a success, not a failure
	if not (from and to and from.Parent and to.Parent) then return false end
	if getTokens(from) < amount then return false end
	-- Cap check BEFORE debiting, so a transfer that would overflow the receiver is refused outright rather than
	-- silently burning the difference.
	if getTokens(to) + amount > CrateTokens.MAX_BALANCE then return false end
	setTokens(from, getTokens(from) - amount)
	setTokens(to,   getTokens(to)   + amount)
	print(string.format("[SkinCrate] trade moved %d tokens: %s -> %s", amount, from.Name, to.Name))
	return true
end

-- ===== GIFTING HOOKS (for Gifting.server -- the MORE+ "Send a Gift" card, same contract as Space / Food) =====
-- ONLINE gift: debit and credit in one call with no yield between them, so a gift can never mint tokens.
_G.giftCrateTokens = function(sender, recipient, amount)
	amount = tonumber(amount) or 0
	if amount ~= amount or amount == math.huge then return false, "bad amount" end
	amount = math.floor(amount)
	if amount <= 0 then return false, "bad amount" end
	if not (typeof(sender) == "Instance" and sender:IsA("Player")
		and typeof(recipient) == "Instance" and recipient:IsA("Player")) then
		return false, "bad players"
	end
	if getTokens(sender) < amount then return false, "not enough tokens" end
	if getTokens(recipient) + amount > CrateTokens.MAX_BALANCE then return false, "their token wallet is full" end
	setTokens(sender, getTokens(sender) - amount)
	setTokens(recipient, getTokens(recipient) + amount)
	pushState(sender); pushState(recipient)
	return true
end
-- OFFLINE debit: taken BEFORE the mailbox write (the reverse order is a minting bug).
_G.debitCrateTokensForGift = function(sender, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false, "bad amount" end
	if getTokens(sender) < amount then return false, "not enough tokens" end
	setTokens(sender, getTokens(sender) - amount)
	pushState(sender)
	return true
end
-- RAW credit: mailbox claims and refunds. NOT routed through _G.crateTokensAward -- these tokens were already
-- debited from a real sender, so the anti-farm caps must never eat part of them.
_G.addCrateTokensRaw = function(player, amount, reason)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end
	addTokens(player, amount, reason or "gift")
	pushState(player)
	return true
end

-- What a trade window should show as this player's spendable balance.
_G.crateTokensCanAfford = function(player, amount)
	return getTokens(player) >= math.max(0, math.floor(tonumber(amount) or 0))
end
_G.skinLastPullWasGold = function(player) return lastPullGold[player] == true end -- [REMOVE BEFORE LAUNCH] /goldtest
_G.skinOwnsEntry = function(player, key) return countOf(player, key) > 0 end
_G.skinEquippedFor = function(player, petId)
	local e = (_G.playerEquippedSkins[player] or {})[petId]
	if type(e) ~= "table" then return nil end
	return e.skin, e.trait
end
_G.skinPushState = pushState

-- ============================================================================================================
-- TRADE HOOKS  (consumed by PetSystem's existing trade session)
-- ============================================================================================================
-- The pet trade already handles the request/offer/confirm/execute handshake and re-validates ownership at
-- execution. A skin offer travels over the SAME PetTradeOfferEvent as a "SKIN:<key>" string, and PetSystem calls
-- these four functions for any key with that prefix. So skins become tradable without a second trade system,
-- a second window, or any change to the handshake.
--
-- Duplicates are tradable, which falls out for free: a stack is just a count, and removeOne/addOne move exactly
-- one unit. Trading a skin for a pet you HAVEN'T unlocked is allowed on purpose -- it lands in the inventory as
-- "Unlock <Pet> to equip" and becomes wearable the moment you unlock that pet.

-- Display payload for one offered skin, for the trade window.
_G.skinTradeBrief = function(player, key)
	local petId, skinId, traitId = PetSkins.parseKey(key)
	if not petId then return nil end
	if countOf(player, key) <= 0 then return nil end
	local skin = PetSkins.get(skinId)
	return {
		kind    = "skin",
		key     = PetSkins.toTradeKey(key),
		petId   = petId,
		skin    = skinId,
		trait   = traitId,
		name    = PetSkins.displayName(skinId, petId),
		tier    = (skin and skin.tier) or "Common",
		count   = countOf(player, key),
	}
end

_G.skinTradeOwns = function(player, key)
	return countOf(player, key) > 0
end

-- Snapshot what's being given, so the receiving side can be credited even after the giver's entry is removed.
_G.skinTradeUnit = function(player, key)
	local petId, skinId, traitId = PetSkins.parseKey(key)
	if not petId then return nil end
	if countOf(player, key) <= 0 then return nil end
	return { pet = petId, skin = skinId, trait = traitId }
end

_G.skinTradeRemoveOne = function(player, key)
	local removed = removeSkinEntry(player, key)
	if removed then
		-- If they just traded away the LAST copy of the skin they were wearing, clear the equip so the pet
		-- doesn't keep rendering a skin its owner no longer has.
		local petId, skinId, traitId = PetSkins.parseKey(key)
		local eq = petId and (_G.playerEquippedSkins[player] or {})[petId]
		if eq and eq.skin == skinId and (eq.trait or nil) == traitId and countOf(player, key) <= 0 then
			_G.playerEquippedSkins[player][petId] = nil
		end
	end
	return removed
end

_G.skinTradeAddOne = function(player, unit)
	if type(unit) ~= "table" or type(unit.pet) ~= "string" then return false end
	addSkinEntry(player, unit.pet, unit.skin, unit.trait, 1)
	return true
end

_G.skinTradeAfter = function(player)
	pushState(player)
end

-- ============================================================================================================
-- JOIN / OWNERSHIP WATCHER
-- ============================================================================================================
-- PlayerStats calls this once the save has loaded (the same handshake _G.petsApplyOnJoin uses), so the first
-- push carries the real balance and inventory rather than an empty default.
_G.skinCrateApplyOnJoin = function(player)
	-- Before the bridge has loaded this player there is NO balance to mirror: getTokens would read nil as
	-- 0, write it back, and that 0 would then be the "loaded" wallet everything else keys off.
	if _G.playerCrateTokens[player] == nil then return end
	setTokens(player, getTokens(player)) -- mirror the loaded balance onto the leaderstat
	pushState(player)
	print(string.format("[SkinCrate] join state for %s: %d tokens, %d skin entries",
		player.Name, getTokens(player), (function() local n = 0; for _ in pairs(inv(player)) do n = n + 1 end; return n end)()))
end

-- A skin for a locked pet must become equippable the moment that pet is unlocked. Rather than patching every
-- place PetSystem can grant a pet (quest claim, seasonal harvest, starter grant, collection milestone, trade),
-- we watch the ownership SIGNATURE and re-push when it changes. One cheap string compare per player per 2s,
-- and it can never miss a grant path -- including ones added later.
task.spawn(function()
	local lastSig = {} -- [player] = string
	while true do
		task.wait(2)
		for _, player in ipairs(Players:GetPlayers()) do
			local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
			if owned then
				local keys = {}
				for k in pairs(owned) do keys[#keys + 1] = k end
				table.sort(keys)
				local sig = table.concat(keys, ",")
				if lastSig[player] ~= sig then
					lastSig[player] = sig
					pushState(player)
				end
			end
		end
	end
end)

-- ============================================================================================================
-- [REMOVE BEFORE LAUNCH] DEV HOOKS
-- ============================================================================================================
-- BindableEvents DevCommands fires, so the dev path shares the EXACT production functions (no test-only branch
-- that could behave differently from the real thing).
local DevGiveTokens = getOrCreate(ServerScriptService, "BindableEvent", "DevGiveTokens")
DevGiveTokens.Event:Connect(function(player, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	addTokens(player, tonumber(amount) or 1000, "dev")
	pushState(player)
end)

-- /unlockall -- grant EVERY skin on EVERY pet, plus one of each trait, so the whole cosmetic set can be looked
-- at without opening ~200 crates. Writes through addSkinEntry (the same function a real pull uses), so what you
-- get is indistinguishable from earned entries: it stacks, equips, trades and saves identically.
local DevUnlockAllSkins = getOrCreate(ServerScriptService, "BindableEvent", "DevUnlockAllSkins")
DevUnlockAllSkins.Event:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end

	-- The full roster comes from PetSystem. Fall back to whatever appears in the crate pools if it hasn't loaded
	-- (or was removed), so this still does something useful rather than erroring.
	local pets = {}
	if _G.petAllSpecies then
		local ok, list = pcall(_G.petAllSpecies)
		if ok and type(list) == "table" then pets = list end
	end
	if #pets == 0 then
		local seen = {}
		for _, crate in ipairs(SkinCrates.CRATES) do
			for _, e in ipairs(SkinCrates.flatContents(crate.id)) do
				-- skip level-crate entries: they have no pet, and `seen[nil] = true` is a runtime error
				if e.pet and not seen[e.pet] then seen[e.pet] = true; pets[#pets + 1] = e.pet end
			end
		end
		table.sort(pets)
	end

	-- 1) every pet x every skin, no trait -- the clean base set.
	local granted = 0
	for _, petId in ipairs(pets) do
		for _, skinId in ipairs(PetSkins.Order) do
			addSkinEntry(player, petId, skinId, "", 1)
			granted = granted + 1
		end
	end

	-- 2) one of every TRAIT, all on the same pet+skin, so the trait renderers can be compared side by side in
	--    the inventory instead of hunting for a Crowned pull. Cosmic is the loudest skin to show them on.
	local showcasePet = pets[1]
	if showcasePet then
		for _, t in ipairs(PetTraits.TRAITS) do
			if not PetTraits.isNone(t.id) then
				addSkinEntry(player, showcasePet, "Cosmic", t.id, 1)
				granted = granted + 1
			end
		end
	end

	pushState(player)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(player, "dev_unlockall") end) end
	print(string.format("[SkinCrate][DEV] /unlockall -> %d entries for %s (%d pets x %d skins + %d traits)",
		granted, player.Name, #pets, #PetSkins.Order, #PetTraits.TRAITS - 1))
end)

local DevOpenCrate = getOrCreate(ServerScriptService, "BindableEvent", "DevOpenCrate")
DevOpenCrate.Event:Connect(function(player, crateId, quiet)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local crate = SkinCrates.getCrate(crateId) or SkinCrates.CRATES[1]
	addTokens(player, crate.price, "dev crate comp") -- comp the price so /opencrate always works
	-- noSave = true: the dev path never writes to the DataStore, so /goldtest's thousands of opens can't throttle
	-- real saving. Everything else -- the roll, the grant, the push, the Gold announcement -- is the production path.
	local result = openCrate(player, crate.id, true)
	if not quiet then
		-- a level pull has no skin/pet to name; concatenating them would error out the dev path
		local what = result.reason
		if result.ok then
			what = result.kind == "levels" and (result.rarity .. " +" .. tostring(result.levels) .. " levels")
				or (result.rarity .. " " .. tostring(result.skin) .. " " .. tostring(result.pet))
		end
		print("[SkinCrate][DEV] forced open ->", what)
	end
end)

print("[SkinCrate] service ready -- " .. #SkinCrates.CRATES .. " crates, " ..
	#PetSkins.Order .. " skins, " .. #PetTraits.TRAITS .. " traits" ..
	(SkinCrates.TEST_MODE and "  [TEST_MODE: token packs credit without Robux]" or ""))
