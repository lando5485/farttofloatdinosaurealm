--======================================================================
-- SpaceRealm_ArrivalReceiver.server.luau
-- PUT THIS IN THE **SPACE REALM** PLACE, in ServerScriptService.
-- It REPLACES export_pet_system/SpaceRealm/PetReceiver.server.luau.
--======================================================================
-- WHY THE OLD ONE HAD TO GO
-- PetReceiver (Aug 29) predates the cross-realm contract and breaks it in three ways:
--
--   1. IT ASSIGNS, IT DOES NOT MERGE:
--          _G.playerOwnedPets[player] = data.ownedPets
--      A player who levelled a pet in Space, hopped to Dino and came back had their Space
--      progress REPLACED by the snapshot Dino sent. The contract is union + per-field MAX
--      precisely so a round trip can never lose a level.
--   2. NO userId CHECK. Every other receiver in the universe refuses a payload stamped for
--      somebody else; a stale or forwarded payload was trusted here.
--   3. IT READS ONLY ownedPets + equippedPet. Tokens, skins, worn looks, collection flags,
--      the title and homePlaceId all arrived and were dropped on the floor.
--
-- WHAT THIS IMPLEMENTS
-- The contract in CROSS_REALM_PIPELINE.md sections 2.2, 2.3 and 2.5, mirrored from the Dino
-- realm's ArrivalReceiver.server.luau so the two behave identically.
--
-- ⚠ TWO HOOKS YOU MUST POINT AT SPACE'S OWN CODE -- see WIRING at the bottom. Until then this
-- stages everything into _G and warns once; it never silently half-works.
--======================================================================

local Players = game:GetService("Players")

--======================================================================
-- CONFIG -- set these to the Space realm's own values
--======================================================================
local SPACE_PLACE_ID = 125063266868039
local FOOD_PLACE_ID  = 120919484545190   -- the default "home" when a payload names none

-- Set true ONLY once Space reads/writes UniverseCrateTokens_v1 (the shared wallet).
-- While false, Space keeps a private wallet and MERGES tokens the way it always did.
local SPACE_ON_UNIVERSE_WALLET = false

--======================================================================
_G.playerOwnedPets      = _G.playerOwnedPets      or {}
_G.playerEquippedPet    = _G.playerEquippedPet    or {}
_G.playerPetSkins       = _G.playerPetSkins       or {}
_G.playerEquippedSkins  = _G.playerEquippedSkins  or {}
_G.playerCollection     = _G.playerCollection     or {}
_G.incomingFtFData      = _G.incomingFtFData      or {}
_G.spaceArrivalSettled  = _G.spaceArrivalSettled  or {}
_G.playerOwnedGutSkins  = _G.playerOwnedGutSkins  or {}   -- Space owns these; see the pass-through block
_G.playerEquippedGutSkin = _G.playerEquippedGutSkin or {}

local function countKeys(t)
	local n = 0; for _ in pairs(t or {}) do n += 1 end; return n
end
-- NaN and infinity both survive tonumber() and would corrupt a wallet record (and NaN ~= NaN,
-- so every later comparison silently fails). Rejected at the door, as Dino's setTokens does.
local function num(v)
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then return 0 end
	return math.floor(n)
end

--======================================================================
-- MERGE RULES (contract section 2.2) -- union, never assign
--======================================================================

-- Per-pet MAX of the numeric fields; `rare` is STICKY (once rare, always rare -- a realm that
-- does not track it sends nil, and nil must never un-rare a pet).
local function mergePets(player, incoming)
	local mine = _G.playerOwnedPets[player]
	if mine == nil then mine = {}; _G.playerOwnedPets[player] = mine end
	local added, bumped = 0, 0
	for petId, inc in pairs(incoming or {}) do
		if type(petId) == "string" and type(inc) == "table" then
			local cur = mine[petId]
			if cur == nil then
				mine[petId] = {
					level = num(inc.level) > 0 and num(inc.level) or 1,
					xp = num(inc.xp), height = tonumber(inc.height) or nil,
					time = num(inc.time), rare = inc.rare == true,
				}
				added += 1
			else
				local before = num(cur.level) + num(cur.xp)
				cur.level  = math.max(num(cur.level),  num(inc.level), 1)
				cur.xp     = math.max(num(cur.xp),     num(inc.xp))
				cur.time   = math.max(num(cur.time),   num(inc.time))
				if tonumber(inc.height) then
					cur.height = math.max(tonumber(cur.height) or 0, tonumber(inc.height))
				end
				if inc.rare == true then cur.rare = true end
				if (num(cur.level) + num(cur.xp)) > before then bumped += 1 end
			end
		end
	end
	return added, bumped
end

-- Counts merge by MAX and NEVER by sum: summing doubles every duplicate on each round trip,
-- so a player who hops back and forth would mint infinite duplicates.
local function mergeSkins(player, incoming)
	local mine = _G.playerPetSkins[player]
	if mine == nil then mine = {}; _G.playerPetSkins[player] = mine end
	local n = 0
	for key, count in pairs(incoming or {}) do
		local c = num(count)
		if type(key) == "string" and c > 0 then
			local have = num(mine[key])
			if c > have then mine[key] = c; n += 1 end
		end
	end
	return n
end

-- true wins over false; numbers take the MAX; otherwise fill only if we have nothing.
local function mergeCollection(player, incoming)
	local mine = _G.playerCollection[player]
	if mine == nil then mine = {}; _G.playerCollection[player] = mine end
	local n = 0
	for flag, v in pairs(incoming or {}) do
		local cur = mine[flag]
		if v == true then
			if cur ~= true then mine[flag] = true; n += 1 end
		elseif tonumber(v) then
			if tonumber(cur) == nil or tonumber(v) > tonumber(cur) then mine[flag] = tonumber(v); n += 1 end
		elseif cur == nil then
			mine[flag] = v; n += 1
		end
	end
	return n
end

--======================================================================
-- INTAKE (contract section 2.5)
--======================================================================
local merged = {}   -- [player] = true once this arrival has been applied

local function intake(player)
	-- ONE MERGE PER ARRIVAL. PlayerAdded and the catch-up loop below cannot normally both fire
	-- for the same player, but a second pass would credit the earned-token delta twice, and
	-- "probably cannot happen" is not a good enough reason to allow duplicate currency.
	if merged[player] then return end
	merged[player] = true
	local data
	pcall(function()
		local jd = player:GetJoinData()
		data = jd and jd.TeleportData
	end)

	-- Not a portal arrival -> normal start. Settle at once so anything measuring an "earned
	-- here" baseline can start immediately.
	if type(data) ~= "table" or data.fromFartToFloat ~= true then
		_G.spaceArrivalSettled[player] = true
		return
	end

	-- ANTI-CROSSWIRE: a payload stamped for another account is refused outright.
	local stampedFor = tonumber(data.userId)
	if stampedFor and stampedFor ~= player.UserId then
		warn(("[SpaceArrival] %s arrived with TeleportData stamped for user %d -- ignored, fresh start")
			:format(player.Name, stampedFor))
		_G.spaceArrivalSettled[player] = true
		return
	end

	-- THE WAY HOME. Forward whatever the payload named; otherwise the origin becomes home
	-- (unless the origin is this place), defaulting to Food.
	if not tonumber(data.homePlaceId) then
		local from = tonumber(data.fromPlaceId)
		data.homePlaceId = (from and from > 0 and from ~= SPACE_PLACE_ID) and from or FOOD_PLACE_ID
	end
	_G.incomingFtFData[player] = data

	--==================================================================
	-- ⚠ WAIT FOR SPACE'S OWN SAVE TO LAND BEFORE MERGING ANYTHING.
	--==================================================================
	-- PlayerStats.server.lua loads with HARD ASSIGNMENT, not a merge:
	--     _G.playerCrateTokens[player]   = math.floor(tonumber(saved.crateTokens) or 0)
	--     _G.playerPetSkins[player]      = saved.petSkins or {}
	--     _G.playerEquippedSkins[player] = saved.equippedSkins or {}
	--     _G.playerCollection[player]    = saved.collection or {}
	-- Merging before that runs is pointless: the load overwrites the merged tables wholesale
	-- and everything the player carried in -- skins, collection, tokens -- is silently gone.
	--
	-- The signal is _G.playerCrateTokens[player] going non-nil, because that same load sets it.
	-- No new hook is needed in Space, and this is exactly how the Dino realm sequences its own
	-- arrival merge against SkinCrateBridge.
	local t0 = os.clock()
	while _G.playerCrateTokens == nil or _G.playerCrateTokens[player] == nil do
		if os.clock() - t0 > 15 or not player.Parent then break end
		task.wait(0.25)
	end
	if not player.Parent then return end
	if _G.playerCrateTokens == nil or _G.playerCrateTokens[player] == nil then
		warn(("[SpaceArrival] %s: player data never loaded (15s) -- merging anyway, but a late load "
			.. "may still overwrite it. Check PlayerStats is running."):format(player.Name))
	end

	local addedPets, bumpedPets = mergePets(player, data.ownedPets)

	-- equippedPet applies only if they actually own it AFTER the merge.
	if type(data.equippedPet) == "string" and (_G.playerOwnedPets[player] or {})[data.equippedPet] then
		_G.playerEquippedPet[player] = data.equippedPet
	end

	local nSkins = mergeSkins(player, data.petSkins)

	local eq = _G.playerEquippedSkins[player]
	if eq == nil then eq = {}; _G.playerEquippedSkins[player] = eq end
	local worn = 0
	for petId, e in pairs(data.equippedSkins or {}) do
		if type(petId) == "string" and type(e) == "table" and e.skin then
			eq[petId] = { skin = e.skin, trait = e.trait }   -- rendering re-validates ownership
			worn += 1
		end
	end

	local nFlags = mergeCollection(player, data.collection)

	--==================================================================
	-- PASS-THROUGH FIELDS (contract section 2.2)
	--==================================================================
	-- Dino forwards five fields it has no system for: petMilestones, ownedGutSkins,
	-- equippedGutSkin, gamepasses, gamepassIds. Space is NOT in the same position -- it really
	-- does own gut skins and gamepasses -- so "forward blindly" is the wrong answer here and each
	-- one is handled on its merits.

	-- GUT SKINS: real earned player data, and Space has _G.playerOwnedGutSkins. Union the owned
	-- set (never assign -- the same reasoning as pets), and honour the worn one only if they own
	-- it after the merge. Default is force-owned because PlayerStats guarantees it.
	if type(data.ownedGutSkins) == "table" then
		local mine = _G.playerOwnedGutSkins
		if mine then
			mine[player] = mine[player] or {}
			local n = 0
			for id, owned in pairs(data.ownedGutSkins) do
				if owned and mine[player][id] == nil then mine[player][id] = true; n += 1 end
			end
			mine[player].Default = true
			if type(data.equippedGutSkin) == "string" and mine[player][data.equippedGutSkin]
				and _G.playerEquippedGutSkin then
				_G.playerEquippedGutSkin[player] = data.equippedGutSkin
			end
			if n > 0 then
				print(("[SpaceArrival] %s carried in %d gut skin(s)"):format(player.Name, n))
			end
		end
	end

	-- ⚠ GAMEPASSES ARE NOT APPLIED FROM THE PAYLOAD, ON PURPOSE.
	-- They are ENTITLEMENTS, not progress. The only honest source is MarketplaceService, which
	-- Space already consults (PlayerStats reads Gamepasses.IDS). Granting a 2x multiplier or a
	-- premium gut because a teleport payload claimed one would make the pass reachable without
	-- ever buying it, and would keep working for as long as the player kept hopping realms.
	-- The payload IS still stashed in _G.incomingFtFData above, so Space's own outbound sender
	-- can forward these fields unchanged to the next realm -- carrying them is fine, TRUSTING
	-- them is not. petMilestones is stashed for the same forward-only reason.

	-- TITLE fills an EMPTY slot only; one earned in Space is never overwritten.
	if type(data.title) == "string" and data.title ~= "" then
		local cur = player:GetAttribute("Title")
		if cur == nil or cur == "" then player:SetAttribute("Title", data.title) end
	end

	player:SetAttribute("ArrivedViaRift", data.arrivedViaRift == true)

	--==================================================================
	-- TOKENS (contract section 2.3)
	--==================================================================
	-- A sender on the SHARED wallet already shares this balance with us -- merging it would
	-- pay the same tokens twice. That only applies once Space is on that wallet too; while
	-- Space keeps a private one, its balance is genuinely separate and must be merged.
	local skipTokens = (SPACE_ON_UNIVERSE_WALLET and data.sharedTokens == true)
	-- Our own tokens coming home never get re-merged either.
	if tonumber(data.fromPlaceId) == SPACE_PLACE_ID then skipTokens = true end

	if skipTokens then
		print(("[SpaceArrival] %s: tokens already shared with the sender -- no merge"):format(player.Name))
	elseif _G.spaceAddCrateTokens then
		-- DELTA first (what they earned abroad), capped exactly as the other realms cap it...
		local earned = (type(data.earned) == "table") and num(data.earned.crateTokens) or 0
		if earned > 0 then
			pcall(_G.spaceAddCrateTokens, player, math.min(earned, 500), "earned abroad (arrival delta)")
		end
		-- ...then MAX-merge the absolute, so whichever is larger settles.
		local incoming = num(data.crateTokens)
		local here = num(_G.playerCrateTokens and _G.playerCrateTokens[player])
		if incoming > here then
			pcall(_G.spaceAddCrateTokens, player, incoming - here, "carried in (absolute max-merge)")
		end
	else
		warn("[SpaceArrival] _G.spaceAddCrateTokens is not defined -- tokens were NOT merged. "
			.. "See WIRING at the bottom of this file.")
	end

	_G.spaceArrivalSettled[player] = true

	print(("[SpaceArrival] %s from place %s (v%s, home %s): pets +%d/%dbumped, skins +%d, worn %d, flags +%d")
		:format(player.Name, tostring(data.fromPlaceId), tostring(data.payloadVersion),
			tostring(data.homePlaceId), addedPets, bumpedPets, nSkins, worn, nFlags))

	-- Hand off to Space's own renderer once it exists.
	task.spawn(function()
		for _ = 1, 50 do
			if _G.petsApplyOnJoin then pcall(_G.petsApplyOnJoin, player); return end
			task.wait(0.1)
		end
		warn("[SpaceArrival] no _G.petsApplyOnJoin -- pets are staged in _G.playerOwnedPets "
			.. "but nothing rendered them.")
	end)
end

Players.PlayerAdded:Connect(function(p) task.spawn(intake, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(intake, p) end
Players.PlayerRemoving:Connect(function(p)
	_G.incomingFtFData[p] = nil
	_G.spaceArrivalSettled[p] = nil
	merged[p] = nil
end)

print("[SpaceArrival] ready -- full cross-realm contract (pets, skins, collection, title, tokens)")

--======================================================================
-- WIRING -- the two things this file cannot know on its own
--======================================================================
-- 1. _G.spaceAddCrateTokens(player, amount, reason)
--    Point this at whatever Space already uses to credit tokens -- the SAME function the
--    crate shop uses, so the clamp, the client push and the save all happen exactly once.
--    Without it tokens are NOT merged and the warning above fires every arrival.
--
-- 2. SPACE_ON_UNIVERSE_WALLET (top of this file)
--    Leave FALSE until Space actually reads/writes UniverseCrateTokens_v1 under "u_"..userId.
--    Flipping it early makes Space skip merges for a balance it does not share -> tokens
--    vanish on arrival. Flipping it late double-pays. Flip it in the SAME change that moves
--    Space onto the shared wallet.
--
-- 3. YOUR OUTBOUND SENDER MUST FORWARD THE PASS-THROUGH FIELDS.
--    This file only RECEIVES. Whatever builds Space's teleport payload has to re-send the
--    fields Space does not own, or they die here: a Food player's milestones and gamepass
--    flags would survive Food -> Space but vanish on Space -> Dino. Dino does it in one
--    helper (WormholeService.passthrough) and it is worth copying verbatim:
--
--        local function passthrough(player, key)
--            local d = _G.incomingFtFData and _G.incomingFtFData[player]
--            return d and d[key] or nil
--        end
--
--    then in the payload:  petMilestones = passthrough(player, "petMilestones"), and the
--    same for gamepasses / gamepassIds. Gut skins are different -- Space OWNS those, so send
--    its live _G.playerOwnedGutSkins / _G.playerEquippedGutSkin, not the stashed copy.
--
-- STILL OUTSTANDING for Space (CROSS_REALM_PIPELINE.md section 4):
--    * rename the gift mailbox store SpaceGiftMailbox_v1 -> GiftMailbox_v1
--    * subscribe to the "GiftDelivery_v1" topic and drain the local recipient's mailbox
--    * set the Rebirths / RebirthMult attributes on load (Dino reads attributes)
--    * install Dino's SessionRewards + DailyStreak + RewardsHubCap (change only require paths)
--======================================================================
