--!nonstrict
-- CrateService (ServerScriptService/CrateService) — SERVER AUTHORITY for the Mystery Meteor Crate.
--
-- Responsibilities:
--   * Create ReplicatedStorage/CrateRemotes + ClaimCrate (RemoteFunction) + CrateResult (RemoteEvent)
--     + GetOwnedPets (RemoteFunction, feeds the client pet picker).
--   * Own ServerScriptService/DevForceCrate (BindableEvent) for the dev /crate path. [REMOVE BEFORE LAUNCH]
--   * performClaim(): cooldown gate, rarity roll, PET-LEVEL grant to the player's chosen owned pet
--     (clamped at the level cap), coin fallback when every owned pet is maxed, 6h timer reset.
--
-- REWARD: pet levels (not cosmetics). Rarity -> levels: Uncommon +1, Rare +2, Epic +4, Mythical +6.
-- The chosen pet is validated server-side; the client only animates + sends the chosen petId.
-- All eligibility/roll/grant/timer-reset is decided HERE.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- ===== remotes ===== (created FIRST, before the requires below, so the client's WaitForChild can
-- never hang waiting on a slow/failed module require — the row's open trigger always has its remotes)
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
local ClaimCrate = getOrCreate(crateRemotes, "RemoteFunction", "ClaimCrate")
local CrateResult = getOrCreate(crateRemotes, "RemoteEvent", "CrateResult")
local GetOwnedPets = getOrCreate(crateRemotes, "RemoteFunction", "GetOwnedPets")
local PreviewRoll = getOrCreate(crateRemotes, "RemoteFunction", "PreviewRoll")
print("[CrateService] CrateRemotes ready (ClaimCrate, CrateResult, GetOwnedPets)")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Gamepasses = require(Shared:WaitForChild("Gamepasses"))
local PlayerState = require(ServerScriptService:WaitForChild("PlayerState"))

local CRATE = Constants.CRATE
local rng = Random.new()

-- A rarity roll PRE-rolled by PreviewRoll (so the picker can show the rolled rarity/amount before the
-- player picks). The matching ClaimCrate grant reuses it so the displayed roll == the granted roll.
-- Same roll weights / clamp / cooldown as before — this only caches WHEN the single roll happens.
-- WHICH crate the daily reward hands out. A plain constant so the daily can be re-pointed at Starter (or a
-- seasonal crate) with a one-word edit rather than a hunt through the claim path. Must be an id that exists
-- in SkinCrates.CRATES -- if it ever isn't, the free open returns unknown_crate and the claim falls through
-- to the old level/coin behaviour rather than failing.
local DAILY_CRATE_ID = "Premium"

local pendingRoll = {} -- [player] = { rarity, levels }
Players.PlayerRemoving:Connect(function(p) pendingRoll[p] = nil end)

-- ===== pet helpers (provided by PetSystem via _G; guarded if it hasn't loaded) =====
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
-- `luck` (optional) multiplies every band above the commonest one and the sum below renormalises, exactly as
-- SkinCrates.liveRarities does -- one luck rule for every crate in the game rather than two that drift.
-- Omitted / 1 leaves the weights untouched, so the daily crate rolls identically for a player with no rebirths
-- and no Lucky Pass.
local function rollRarity(luck)
	local order = CRATE.RARITY_ORDER
	local weights = Gamepasses.applyLuck(CRATE.RARITY_WEIGHTS, order, luck or 1)
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
	return order[#order] -- numeric edge: fall to the last rarity
end

-- ===== core claim logic =====
-- performClaim(player, chosenPetId, isDev):
--   isDev = true -> bypass the 6h cooldown (dev /crate). Same roll/grant/timer-reset otherwise.
--   chosenPetId  -> which owned pet to level (client pick). nil/invalid/maxed -> server picks the
--                   first owned not-yet-maxed pet (deterministic). Dev path passes nil.
-- Returns one of:
--   { ok=true,  kind="levels", petId, rarity, levelsAdded, newLevel }
--   { ok=true,  kind="coins", coins }            (owns pets but every one is at the cap)
--   { ok=false, reason="no_pets" }               (owns ZERO pets: no grant, timer NOT consumed)
--   { ok=false, reason="cooldown", nextClaimAt }
--   { ok=false, reason="no_profile" }
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

	-- ===== THE DAILY REWARD IS A FREE PREMIUM CRATE =====
	-- It used to be pet LEVELS, which had two problems. It was worth nothing to a player with no pets (the
	-- claim was refused outright) and nothing to one whose pets were all maxed (it quietly paid coins
	-- instead) -- so the headline daily reward was dead for both ends of the player base. And levels now
	-- route through the post-open picker, so a level payout here would have opened a SECOND picker off a
	-- panel that has nothing to do with the crate shop.
	--
	-- A Premium skin crate has neither problem: it is worth the same to everyone, on day one and at max
	-- level, and it reuses the crate reveal the game already has. It is granted through
	-- _G.skinCrateFreeOpen, which is the ordinary paid open with the price skipped -- same roll, same
	-- Collection Book, same Gold announce -- so the free crate cannot drift away from the bought one.
	if type(_G.skinCrateFreeOpen) == "function" then
		local res = _G.skinCrateFreeOpen(player, DAILY_CRATE_ID)
		if type(res) == "table" and res.ok then
			PlayerState.setLastCrateClaim(player, now)
			return { ok = true, kind = "skincrate", crateId = DAILY_CRATE_ID, crate = res }
		end
		-- The skin service refused (empty band, open cooldown, service not up). Do NOT consume the daily
		-- timer for a crate the player never received -- fall through to the old paths below so the claim is
		-- still worth something rather than being silently eaten.
		warn(("[Crate] free %s open failed for %s (%s) -- falling back to levels/coins")
			:format(DAILY_CRATE_ID, player.Name, type(res) == "table" and tostring(res.reason) or "no result"))
	end

	local owned = listOwnedPets(player)

	-- FALLBACK PATHS BELOW. Reached only if the skin service could not hand out a crate; they are the old
	-- level/coin behaviour, kept precisely so a failure there still pays the player something.
	if #owned == 0 then
		return { ok = false, reason = "no_pets" }
	end

	if not hasUnmaxedPet(player) then
		return coinFallback()
	end

	-- Resolve the target pet: the client's choice if it's owned and NOT maxed, else the first
	-- owned not-yet-maxed pet (deterministic, list is petId-sorted).
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
		return coinFallback() -- defensive: hasUnmaxedPet said true but nothing resolved
	end

	-- Rarity -> levels granted. Reuse the PreviewRoll for this player if one is pending (so the picker's
	-- shown rarity/amount EXACTLY matches the grant); otherwise roll fresh (e.g. the dev path). Server
	-- still applies + clamps to the cap inside _G.petGrantLevels.
	local rarity, levels
	local pend = pendingRoll[player]
	if pend then
		rarity, levels = pend.rarity, pend.levels
		pendingRoll[player] = nil
	else
		rarity = rollRarity(Gamepasses.luckFor(player))
		levels = CRATE.RARITY_LEVELS[rarity] or 1
	end

	local oldLevel, newLevel, levelsAdded = nil, nil, 0
	if type(_G.petGrantLevels) == "function" then
		local ok, a, b, c = pcall(_G.petGrantLevels, player, petId, levels)
		if ok then oldLevel, newLevel, levelsAdded = a, b, c end
	end

	-- The pet turned out maxed (race), or the grant failed -> coin fallback so the claim is never void.
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

-- Feeds the client pet picker: list of owned pets { petId, displayName, level, maxed }.
GetOwnedPets.OnServerInvoke = function(player)
	return listOwnedPets(player)
end

-- Rolls the rarity for THIS open WITHOUT granting or consuming the cooldown, caches it (so the
-- matching ClaimCrate grant reuses it), and returns { ok=true, rarity, levelsAdded } for the picker
-- header. Mirrors performClaim's pre-checks. Roll weights / cooldown gating / grant logic unchanged.
PreviewRoll.OnServerInvoke = function(player)
	if not PlayerState.isLoaded(player) then return { ok = false, reason = "no_profile" } end
	local now = os.time()
	local last = PlayerState.getLastCrateClaim(player)
	if last ~= 0 and now < last + CRATE.COOLDOWN_SECONDS then
		return { ok = false, reason = "cooldown", nextClaimAt = last + CRATE.COOLDOWN_SECONDS }
	end
	if #listOwnedPets(player) == 0 then return { ok = false, reason = "no_pets" } end
	if not hasUnmaxedPet(player) then return { ok = true, kind = "coins" } end -- all maxed -> coins on claim
	-- The PREVIEW is the roll that actually gets granted (performClaim reuses pendingRoll), so luck must be
	-- applied HERE too -- otherwise a Lucky Pass owner would preview at boosted odds and be granted at base,
	-- or the reverse, and the picker would be lying about the reward it is showing.
	local rarity = rollRarity(Gamepasses.luckFor(player))
	local levels = CRATE.RARITY_LEVELS[rarity] or 1
	pendingRoll[player] = { rarity = rarity, levels = levels }
	return { ok = true, rarity = rarity, levelsAdded = levels }
end

-- [REMOVE BEFORE LAUNCH] Dev force path: ServerScriptService/DevForceCrate (BindableEvent, payload=Player)
-- fired by DevCommands (/crate). Bypasses the 6h gate; grants levels the SAME way (server picks the
-- pet since there's no client picker on this path) and PUSHES the result via CrateResult so the
-- reveal animates without a tap.
local DevForceCrate = getOrCreate(ServerScriptService, "BindableEvent", "DevForceCrate")
DevForceCrate.Event:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local result = performClaim(player, nil, true)
	CrateResult:FireClient(player, result)
end)
