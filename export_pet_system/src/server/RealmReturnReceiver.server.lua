--======================================================================
-- RealmReturnReceiver.server.lua  (Script)   [HOME PLACE -- the islands]
--======================================================================
-- The RECEIVING half of the trip HOME. Every other receiver in this project (SpaceRealm/PetReceiver,
-- DinoRealm/ArrivalReceiver) catches players LEAVING the islands. Nothing caught them coming BACK --
-- so until now, anything a player earned in the Dino Realm died at the place boundary.
--
-- THE PAIR: DinoRealm/ReturnSender.server.luau packs the payload -> this reads it back on join via
-- player:GetJoinData().TeleportData and MERGES it into the player's live state.
--
--======================================================================
-- THE ONE RULE THAT KEEPS SAVES SAFE:  MERGE, NEVER ASSIGN.
--======================================================================
-- This place's DataStore (PlayerData_v1, owned by PlayerStats) is the AUTHORITY for coins, island,
-- stomach and everything else. A returning payload is a SNAPSHOT taken minutes ago in another place --
-- if we assigned it, a player who earned 50k coins here, hopped to Dino and came back would have their
-- 50k overwritten by the stale number. So:
--
--   * ADDITIVE state (pets owned, skins owned, milestones) -> UNION. Owning a pet in either place = owned.
--   * PER-PET NUMBERS (level, xp, height, time)            -> MAX. Progress can only ever go UP.
--   * CURRENCY (coins, crate tokens)                       -> only the `earned` DELTA is added, never the
--                                                             absolute. A stale absolute can't wipe a balance,
--                                                             and a delta is what they actually earned abroad.
--   * ABSOLUTES WE NEVER TOUCH: coins/island/stomach/fartMeter. PlayerStats owns those, full stop.
--
-- Every merge is therefore IDEMPOTENT: applying the same payload twice changes nothing the second time
-- (except the currency delta -- see the dedupe guard below).
--
-- ORDERING (this is the subtle part): PlayerStats loads the save asynchronously and only THEN writes
-- _G.playerOwnedPets[player]. If we merged before that line ran, PlayerStats would overwrite us a moment
-- later and the whole trip would silently vanish. So we WAIT for that global to appear -- it is nil before
-- the load and nil again after they leave, which makes it an exact "the save has landed" signal.
-- If the load FAILS, PlayerStats kicks the player and the global never appears -> we time out and merge
-- NOTHING, which is correct: a merge that can't be saved is worse than no merge.
--
-- SECURITY: TeleportData is set SERVER-side in the Dino place, so it can't be forged by a client. It CAN
-- still be wrong (a bug over there), so the currency deltas are clamped and the payload's userId is checked.
--
-- ⚠ TEST ACCOUNTS: PlayerStats force-loads lando5485/broskie310111 as brand-new and never saves them, so a
-- merge for those accounts applies to the live session but will NOT persist. That's the test account working
-- as designed, not this script failing.
--======================================================================
local Players = game:GetService("Players")

-- Same globals PlayerStats/PetSystem/SkinCrateService use. Declared defensively so load order can't matter.
_G.playerOwnedPets      = _G.playerOwnedPets      or {}
_G.playerEquippedPet    = _G.playerEquippedPet    or {}
_G.playerPetSkins       = _G.playerPetSkins       or {}
_G.playerEquippedSkins  = _G.playerEquippedSkins  or {}
_G.playerCollection     = _G.playerCollection     or {}
_G.playerCrateTokens    = _G.playerCrateTokens    or {}
_G.playerPetMilestones  = _G.playerPetMilestones  or {}
_G.playerOwnedGutSkins  = _G.playerOwnedGutSkins  or {}
_G.playerEquippedGutSkin= _G.playerEquippedGutSkin or {}
_G.playerTitle          = _G.playerTitle          or {}

-- The raw payload, kept per player so other scripts can read what came back (e.g. an arrival cinematic).
_G.incomingRealmReturn  = _G.incomingRealmReturn  or {}

-- ANTI-ABUSE CLAMPS on the currency deltas. The Dino place is trusted (server-side sender), but a bug or a
-- future exploit over there must not be able to mint an unbounded balance here. A realm visit paying more
-- than this is a bug worth seeing in the log, not a payout worth honouring.
local MAX_COIN_GRANT  = 250000
local MAX_TOKEN_GRANT = 500

local LOAD_WAIT_SECONDS = 60   -- PlayerStats retries GetAsync 4x with 2s gaps, so its load can legitimately take a while
local LOAD_POLL         = 0.25

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function isTable(v) return type(v) == "table" end

local function count(t)
	local n = 0
	if isTable(t) then for _ in pairs(t) do n = n + 1 end end
	return n
end

-- Bigger of two values, treating nil/garbage as 0. Every per-pet number goes through this, which is what
-- makes "progress only goes up" true even when one side has never heard of the field.
local function maxNum(a, b)
	return math.max(tonumber(a) or 0, tonumber(b) or 0)
end

-- Wait for PlayerStats to finish its DataStore load, using TWO signals that both live in the same
-- yield-free stretch of its load function:
--
--   * the SeenGardenIntro attribute (PlayerStats.server.lua:1033) -- set ONLY on the load success path,
--     and by nothing else in the project. This is the real "the save has landed" proof.
--   * _G.playerOwnedPets[player]    (PlayerStats.server.lua:1038) -- the table we're about to merge into.
--
-- Why both: the pets table on its own is a weak signal, because any script that does
-- `_G.playerOwnedPets[p] = _G.playerOwnedPets[p] or {}` before the load finishes would make it look ready,
-- we'd merge into that throwaway table, and PlayerStats would overwrite the lot a moment later -- a silent
-- loss that only shows up as "my Dino pets vanished". The attribute closes that hole.
--
-- Bails early if the player leaves (or gets kicked by a failed load) -- there is nothing to merge into then.
local function waitForSaveLoaded(player)
	local waited = 0
	while waited < LOAD_WAIT_SECONDS do
		if not player.Parent then return false end        -- left / kicked mid-load
		if player:GetAttribute("SeenGardenIntro") ~= nil and _G.playerOwnedPets[player] ~= nil then
			return true
		end
		task.wait(LOAD_POLL)
		waited = waited + LOAD_POLL
	end
	return false
end

--------------------------------------------------------------------------------
-- the merges  (each one is idempotent -- running it twice is the same as running it once)
--------------------------------------------------------------------------------

-- PETS. Union of ownership; per-pet numbers take the max. `rare` is sticky: a pet that is rare in EITHER
-- place stays rare, because rare is an unlock, not a stat.
local function mergePets(player, incoming)
	if not isTable(incoming) then return 0, 0 end
	local owned = _G.playerOwnedPets[player]
	local added, improved = 0, 0

	for key, inc in pairs(incoming) do
		if type(key) == "string" and isTable(inc) then
			local cur = owned[key]
			if not isTable(cur) then
				-- Brand-new to this place: copy the fields explicitly rather than the table itself, so a
				-- malformed payload can't smuggle extra keys into a table that gets written to the DataStore.
				owned[key] = {
					level  = math.max(1, math.floor(tonumber(inc.level) or 1)),
					xp     = math.max(0, tonumber(inc.xp) or 0),
					height = math.max(0, tonumber(inc.height) or 0),
					time   = math.max(0, tonumber(inc.time) or 0),
					rare   = (inc.rare == true) or (key:match("#R$") ~= nil),
				}
				added = added + 1
			else
				local before = (tonumber(cur.level) or 0) + (tonumber(cur.xp) or 0)
				cur.level  = math.max(1, math.floor(maxNum(cur.level, inc.level)))
				cur.xp     = maxNum(cur.xp, inc.xp)
				cur.height = maxNum(cur.height, inc.height)
				cur.time   = maxNum(cur.time, inc.time)
				cur.rare   = (cur.rare == true) or (inc.rare == true)
				if ((tonumber(cur.level) or 0) + (tonumber(cur.xp) or 0)) > before then improved = improved + 1 end
			end
		end
	end
	return added, improved
end

-- SKIN INVENTORY. petSkins is ["Pet|Skin|Trait"] = duplicate count. Take the MAX of the two counts, never the
-- sum: summing would double every duplicate the player already owned each time they walked through a portal.
local function mergePetSkins(player, incoming)
	if not isTable(incoming) then return 0 end
	local skins = _G.playerPetSkins[player]
	local added = 0
	for key, n in pairs(incoming) do
		if type(key) == "string" then
			local cur = tonumber(skins[key]) or 0
			local new = math.max(cur, math.floor(tonumber(n) or 0))
			if new > 0 and cur == 0 then added = added + 1 end
			if new > 0 then skins[key] = new end
		end
	end
	return added
end

-- WHAT EACH PET IS WEARING. This is a preference, not progress, so the choice they made abroad wins -- but
-- only for a skin they actually own after the inventory merge above, so a bad payload can't equip a phantom.
local function mergeEquippedSkins(player, incoming)
	if not isTable(incoming) then return end
	local owned    = _G.playerPetSkins[player]
	local equipped = _G.playerEquippedSkins[player]
	for petKey, skinKey in pairs(incoming) do
		if type(petKey) == "string" and type(skinKey) == "string" then
			if (tonumber(owned[skinKey]) or 0) > 0 then
				equipped[petKey] = skinKey
			end
		end
	end
end

-- COLLECTION BOOK + MILESTONES. Both are "have I done this yet" records: true wins over false/absent, and a
-- number only ever climbs. Shallow by design -- these tables are flat flag maps.
local function mergeFlagMap(target, incoming)
	if not isTable(incoming) or not isTable(target) then return end
	for k, v in pairs(incoming) do
		if v == true then
			target[k] = true
		elseif type(v) == "number" then
			target[k] = maxNum(target[k], v)
		elseif isTable(v) and isTable(target[k]) then
			mergeFlagMap(target[k], v) -- collection entries can nest one level (per-pet completion records)
		elseif isTable(v) and target[k] == nil then
			target[k] = v
		end
	end
end

-- GUT SKINS. Union of ownership; Default is always owned (PlayerStats enforces the same invariant on load).
local function mergeGutSkins(player, ownedIncoming, equippedIncoming)
	local owned = _G.playerOwnedGutSkins[player]
	if not isTable(owned) then return end
	if isTable(ownedIncoming) then
		for id, v in pairs(ownedIncoming) do
			if v == true and type(id) == "string" then owned[id] = true end
		end
	end
	owned.Default = true
	if type(equippedIncoming) == "string" and owned[equippedIncoming] then
		_G.playerEquippedGutSkin[player] = equippedIncoming
	end
end

-- CURRENCY. The ONLY place absolute values would be dangerous, so only the delta lands, clamped, and only
-- if it's positive. Coins go through the leaderstats (what PlayerStats saves from), tokens through the global.
local function grantEarned(player, earned)
	if not isTable(earned) then return 0, 0 end

	local coins = math.floor(tonumber(earned.coins) or 0)
	if coins > MAX_COIN_GRANT then
		warn(("[RealmReturn] %s returned with an absurd coin delta (%d) -- clamped to %d")
			:format(player.Name, coins, MAX_COIN_GRANT))
		coins = MAX_COIN_GRANT
	end
	if coins > 0 then
		local ls = player:FindFirstChild("leaderstats")
		local c  = ls and ls:FindFirstChild("Coins")
		local t  = ls and ls:FindFirstChild("TotalCoinsEarned")
		if c then c.Value = c.Value + coins else coins = 0 end -- no leaderstats yet -> don't pretend we paid
		if t then t.Value = t.Value + coins end
	else
		coins = 0
	end

	local tokens = math.floor(tonumber(earned.crateTokens) or 0)
	if tokens > MAX_TOKEN_GRANT then
		warn(("[RealmReturn] %s returned with an absurd token delta (%d) -- clamped to %d")
			:format(player.Name, tokens, MAX_TOKEN_GRANT))
		tokens = MAX_TOKEN_GRANT
	end
	if tokens > 0 then
		_G.playerCrateTokens[player] = math.floor(tonumber(_G.playerCrateTokens[player]) or 0) + tokens
	else
		tokens = 0
	end

	return coins, tokens
end

--------------------------------------------------------------------------------
-- intake
--------------------------------------------------------------------------------
local function intake(player)
	local data
	pcall(function()
		local jd = player:GetJoinData()
		data = jd and jd.TeleportData
	end)

	-- Not a return trip. Either they joined the islands normally (the overwhelmingly common case), or they
	-- arrived with a payload that isn't ours. Either way: nothing to do, and NO log spam on a normal join.
	if not isTable(data) or data.returningHome ~= true or data.fromFartToFloat ~= true then
		return
	end

	-- SANITY: the payload is built per-player in the sending place, so a mismatch means something is wrong
	-- over there (a shared table, a stale capture). Refuse rather than apply someone else's progress.
	if data.userId ~= nil and tonumber(data.userId) ~= player.UserId then
		warn(("[RealmReturn] %s arrived with a payload stamped for userId %s -- REFUSING to apply it")
			:format(player.Name, tostring(data.userId)))
		return
	end

	_G.incomingRealmReturn[player] = data

	print(("[RealmReturn] %s came back from %s (place %s) -- waiting for their save to load")
		:format(player.Name, tostring(data.fromRealm or "?"), tostring(data.fromPlaceId)))

	if not waitForSaveLoaded(player) then
		if player.Parent then
			warn(("[RealmReturn] %s -- PlayerStats never finished loading within %ds; merged NOTHING (their " ..
				"save is the authority and a merge we can't persist would be a lie)"):format(player.Name, LOAD_WAIT_SECONDS))
		end
		return
	end

	-- Defensive: these are created by PlayerStats' load alongside playerOwnedPets, but a partial/legacy load
	-- path could leave one nil, and indexing nil here would abort the whole merge.
	_G.playerPetSkins[player]      = _G.playerPetSkins[player]      or {}
	_G.playerEquippedSkins[player] = _G.playerEquippedSkins[player] or {}
	_G.playerCollection[player]    = _G.playerCollection[player]    or {}
	_G.playerPetMilestones[player] = _G.playerPetMilestones[player] or {}
	_G.playerOwnedGutSkins[player] = _G.playerOwnedGutSkins[player] or { Default = true }

	-- ---- merge, each step guarded so one bad field can't abort the rest of the trip ----
	local addedPets, improvedPets, addedSkins = 0, 0, 0
	pcall(function() addedPets, improvedPets = mergePets(player, data.ownedPets) end)
	pcall(function() addedSkins = mergePetSkins(player, data.petSkins) end)
	pcall(function() mergeEquippedSkins(player, data.equippedSkins) end)
	pcall(function() mergeFlagMap(_G.playerCollection[player], data.collection) end)
	pcall(function() mergeFlagMap(_G.playerPetMilestones[player], data.petMilestones) end)
	pcall(function() mergeGutSkins(player, data.ownedGutSkins, data.equippedGutSkin) end)

	-- EQUIPPED PET: honour the pet that was following them in the other realm, but only if they own it here
	-- after the merge -- otherwise leave whatever their save chose.
	if type(data.equippedPet) == "string" and _G.playerOwnedPets[player][data.equippedPet] then
		_G.playerEquippedPet[player] = data.equippedPet
	end

	-- TITLE: an earned title at home outranks a carried one. Only fill an empty slot -- never overwrite.
	if type(data.title) == "string" and _G.playerTitle[player] == nil then
		_G.playerTitle[player] = data.title
	end

	local coins, tokens = 0, 0
	pcall(function() coins, tokens = grantEarned(player, data.earned) end)

	print(("[RealmReturn] %s merged: +%d new pet(s), %d levelled, +%d new skin(s), +%d coins, +%d token(s)")
		:format(player.Name, addedPets, improvedPets, addedSkins, coins, tokens))

	-- REBUILD what the player sees. petsApplyOnJoin re-renders the follower + pushes the pet inventory to the
	-- client; skinCrateApplyOnJoin mirrors the token balance onto the leaderstat and re-pushes the skin state.
	-- Both already ran once during PlayerStats' load with the pre-merge data, so without this second pass the
	-- merged pets exist server-side but the player's screen keeps showing what they left with.
	if _G.petsApplyOnJoin then pcall(function() _G.petsApplyOnJoin(player) end) end
	if _G.skinCrateApplyOnJoin then pcall(function() _G.skinCrateApplyOnJoin(player) end) end

	-- Persisting is automatic: PlayerStats saves straight out of these globals on autosave/leave, so the
	-- merged state goes to disk on the next save without this script touching the DataStore at all.
end

Players.PlayerAdded:Connect(function(player) task.spawn(intake, player) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end -- Studio / hot reload

Players.PlayerRemoving:Connect(function(p)
	_G.incomingRealmReturn[p] = nil
	-- The per-player globals above belong to PlayerStats -- it clears them AFTER its own leave-save reads them.
	-- Clearing them here would race that save and could drop the merge on the floor.
end)

print("[RealmReturn] ready -- merging state carried home from the other realms")
