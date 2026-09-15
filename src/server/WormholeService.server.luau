--[[
	WormholeService.server.luau  (ServerScriptService.DinosaurRealmServer.WormholeService)

	Server-authoritative Wormhole travel for the DINO REALM. Two request paths, both server-validated:

	  * RequestWarp(islandIndex 1..13)   — IN-PLACE hop to any island. *** TEMPORARY: the VISITED gate is
	    OFF and all 13 islands are open regardless of climb progress *** — see the revert note in
	    RequestWarp, and the matching temporary gate in WormholeClient. Still grounded-gated (feet on an
	    island, not mid-flight) and still index-range checked. Places the character on the island's live
	    surface using the SAME bounding-box landing IslandTeleport uses (model:GetBoundingBox + LANDING_OFFSET).

	  * RequestRealmWarp("Food" | "Space") — CROSS-PLACE hop to another realm in the shared F2F universe
	    via TeleportService:TeleportAsync. Grounded-gated. pcall-guarded; async failures notify the client.
	    Carries a full TeleportData payload (pets, skins, collection + the coins/tokens EARNED this visit)
	    so progress made here survives the hop — see "WHAT TRAVELS WITH THE PLAYER" below.

	Travel ONLY: never changes HighestIsland, unlocks anything, or grants progression. It just moves you.
	The payload is a REPORT of state the player already has, not a grant.

	Remotes (ReplicatedStorage/WormholeRemotes): RequestWarp (RemoteFunction), RequestRealmWarp
	(RemoteFunction), RealmWarpFailed (RemoteEvent, server->client async-failure notice).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService") -- JSONEncode, used only to MEASURE the teleport payload

-- ===== Place IDs (shared "Fart to Float" experience/universe 10236070926) =====
local DINO_PLACE_ID  = 110777788409412 -- this place
local FOOD_PLACE_ID  = 120919484545190 -- Food Realm (the original food-islands place)
local SPACE_PLACE_ID = 125063266868039 -- Space Realm
local CANDY_PLACE_ID = 133591422694132 -- Candy Realm (realm 2 -- the summit finale also sends you here)
local REALM_PLACE = { Food = FOOD_PLACE_ID, Space = SPACE_PLACE_ID, Candy = CANDY_PLACE_ID }

-- ===== Islands (shared source of truth: names + tower slot order) =====
local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local ISLAND_NAMES = IslandOrder.NAMES          -- island MODEL number -> display name
-- Kept for the revert of the TEMPORARY every-island unlock in RequestWarp below; Studio will flag it
-- as unused until that gate comes back. Do not delete.
local ISLAND_TO_SLOT = IslandOrder.ISLAND_TO_SLOT -- island MODEL number -> tower/climb slot
local ISLAND_COUNT = IslandOrder.COUNT
local LANDING_OFFSET = 8 -- studs above the island model's top (same value IslandTeleport uses)

-- ===== Remotes (self-contained folder) =====
local folder = ReplicatedStorage:FindFirstChild("WormholeRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "WormholeRemotes"
	folder.Parent = ReplicatedStorage
end
local function getOrMake(className, name)
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
	end
	return r
end
local RequestWarp = getOrMake("RemoteFunction", "RequestWarp")
local RequestRealmWarp = getOrMake("RemoteFunction", "RequestRealmWarp")
local RealmWarpFailed = getOrMake("RemoteEvent", "RealmWarpFailed")

-- Landing spot on island N from its LIVE model bounding box (identical to IslandTeleport.getLandingPosition).
local function getLandingPosition(index)
	local isl = Workspace:FindFirstChild("island" .. index)
	if not isl then return nil end

	-- THE ISLAND'S SPAWN PAD WINS. NestingNook_NPCs now puts an invisible "island<N>Spawn"
	-- on every island, sitting exactly where the hand-placed spawn block was -- so a warp
	-- drops you where you would have spawned, on ground someone chose.
	--
	-- The bounding-box fallback below is a GUESS and a bad one at this scale: an island's
	-- box top is half its HEIGHT above its centre, and island5's box is 462 studs tall, so
	-- that path drops you ~230 studs over the island and lets you fall the rest. On a pad
	-- you simply arrive.
	local pad = isl:FindFirstChild("island" .. index .. "Spawn", true)
	if pad and pad:IsA("BasePart") then
		return pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
	end

	local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
	if not ok or not cf or not size then return nil end
	return cf.Position + Vector3.new(0, size.Y / 2 + LANDING_OFFSET, 0)
end

-- ===== IN-PLACE ISLAND WARP =====
RequestWarp.OnServerInvoke = function(player, islandIndex)
	if type(islandIndex) ~= "number" then return { ok = false, reason = "invalid" } end
	local idx = math.floor(islandIndex)
	if idx ~= islandIndex or idx < 1 or idx > ISLAND_COUNT then
		print(("[Wormhole] BLOCKED warp: bad island index %s from %s"):format(tostring(islandIndex), player.Name))
		return { ok = false, reason = "invalid" }
	end

	-- *** TEMPORARY: EVERY ISLAND UNLOCKED. *** The VISITED gate is off -- any island in range
	-- is a legal destination regardless of climb progress. WormholeClient has the MATCHING
	-- temporary gate; both must be reverted together or the panel and the server disagree.
	--
	-- The index bounds check above still runs, and so does the GROUNDED gate below -- this
	-- opens the destination list, it does not make the remote unvalidated.
	--
	-- TO REVERT, restore the progression rule (and the same in WormholeClient):
	--     local slot = ISLAND_TO_SLOT[idx]
	--     local highestSlot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	--     if not slot or slot ~= highestSlot then ... return { ok = false, reason = "locked" } end
	--
	-- That rule gated by CLIMB SLOT, not by HighestIsland: island idx sits at tower slot
	-- ISLAND_TO_SLOT[idx], and gating on HighestIsland (max model number) would wrongly unlock
	-- the summit early, since the tower scrambles model numbers vs climb order. It required
	-- EXACTLY the highest slot, not "at most" it -- `slot <= highestSlot` let the wormhole carry
	-- you back DOWN the tower to any island you had stood on, a free ride past every crossing
	-- you already paid for.

	local char = player.Character
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 3))
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hrp then
		return { ok = false, reason = "notready" }
	end

	-- GROUNDED gate: no wormhole-hopping mid-flight (feet on an island). Same airborne signal the flight
	-- system uses (Humanoid.FloorMaterial == Air). Authoritative; the client also blocks + toasts.
	if not hum or hum.FloorMaterial == Enum.Material.Air then
		print(("[Wormhole] BLOCKED %s -> island %d: airborne (must be grounded)"):format(player.Name, idx))
		return { ok = false, reason = "airborne" }
	end

	local pos = getLandingPosition(idx)
	if not pos then
		warn(("[Wormhole] %s: island%d model/surface not ready"):format(player.Name, idx))
		return { ok = false, reason = "notready" }
	end
	char:PivotTo(CFrame.new(pos))
	pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end) -- no leftover fall velocity

	print(("[Wormhole] %s warped to island %d (%s)"):format(player.Name, idx, ISLAND_NAMES[idx] or "?"))
	return { ok = true, island = idx, name = ISLAND_NAMES[idx] }
end

--======================================================================
-- WHAT TRAVELS WITH THE PLAYER
--======================================================================
-- A realm hop used to carry `{ fromDinoRealm = true, fromPlaceId = ... }` and nothing else, so everything
-- a player did in the Dino Realm evaporated the moment they left. TeleportData is the ONLY way state
-- crosses a place boundary -- _G, workspace and leaderstats do NOT come with them -- so the payload below
-- is the whole trip.
--
-- SECURITY: TeleportData is set SERVER-side here, so the far side may trust it for things like "which pets
-- do they own". Never set TeleportData from a client.
--
-- CURRENCY IS DELTAS, NEVER ABSOLUTES. The receiving place's DataStore owns the player's real balance, so
-- we can say "add 250" but never "your balance is 250" -- an absolute would wipe whatever they banked at
-- home while they were here. Everything under `earned` measures CHANGE across this visit.
--======================================================================

-- Coins live in leaderstats.Coins (Shop.server.luau:122) and crate tokens in _G.playerCrateTokens
-- (SkinCrateService.server.luau:69). Both are snapshotted on join and diffed at travel time, so this works
-- with zero wiring from the rest of the game.
local joinSnapshot = {} -- [player] = { coins = n, crateTokens = n } -- balances the moment they arrived
local earnedBonus  = {} -- [player] = { coins = n, crateTokens = n } -- grants that bypass those two sources

local function countKeys(t) -- these tables are string-keyed, so #t is always 0 -- count properly
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function coinsNow(player)
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	return c and math.floor(tonumber(c.Value) or 0) or 0
end

local function tokensNow(player)
	return math.floor(tonumber(_G.playerCrateTokens and _G.playerCrateTokens[player]) or 0)
end

local function snapshot(player)
	task.spawn(function()
		-- Shop.server builds leaderstats on join and SkinCrateBridge loads tokens out of the DataStore;
		-- both land AFTER PlayerAdded. Snapshotting too early reads 0 and counts the player's entire
		-- existing balance as "earned here" -- paying it out a second time on the far side.
		local ls = player:WaitForChild("leaderstats", 20)
		if ls then ls:WaitForChild("Coins", 10) end
		local t0 = os.clock()
		while not (_G.playerCrateTokens and _G.playerCrateTokens[player]) and os.clock() - t0 < 20 do
			task.wait(0.25)
		end
		if not player.Parent then return end
		if not (_G.playerCrateTokens and _G.playerCrateTokens[player]) then
			warn("[Wormhole] wallet never loaded for " .. player.Name .. " -- no earned baseline, this visit pays out 0")
			return -- no snapshot = earnedFor() returns 0; never treat a late-loading balance as profit
		end
		-- THE ARRIVAL MERGE MUST LAND FIRST. ArrivalReceiver may still be crediting tokens that arrived WITH
		-- the player (a legacy sender's absolute balance or earned delta). Baselining before that lands
		-- would count those tokens as "earned here" and send them home again as a delta = paid twice.
		-- ArrivalReceiver raises _G.dinoArrivalSettled[player] when it is done (immediately for a direct join).
		local t1 = os.clock()
		while not (_G.dinoArrivalSettled and _G.dinoArrivalSettled[player]) and os.clock() - t1 < 20 do
			task.wait(0.25)
		end
		if not player.Parent then return end
		joinSnapshot[player] = { coins = coinsNow(player), crateTokens = tokensNow(player) }
	end)
end

local function earnedFor(player)
	local snap  = joinSnapshot[player]
	local bonus = earnedBonus[player] or {}
	-- No snapshot means we never established a baseline (they travelled before their save finished
	-- loading). Paying out an unmeasured balance would duplicate currency, so the honest answer is
	-- "nothing measured" -- the far side's own save still has everything they actually own.
	local dCoins  = snap and math.max(0, coinsNow(player)  - snap.coins)       or 0
	local dTokens = snap and math.max(0, tokensNow(player) - snap.crateTokens) or 0
	return {
		coins       = dCoins  + math.max(0, math.floor(tonumber(bonus.coins) or 0)),
		crateTokens = dTokens + math.max(0, math.floor(tonumber(bonus.crateTokens) or 0)),
	}
end

-- ⚠ ONLY for currency granted WITHOUT passing through leaderstats.Coins / _G.playerCrateTokens. Anything
-- that DOES touch those is already counted by the diff above; calling this for it pays the player twice.
_G.dinoAddEarnedCoins = function(player, n)
	n = math.floor(tonumber(n) or 0); if n <= 0 or not player then return end
	earnedBonus[player] = earnedBonus[player] or { coins = 0, crateTokens = 0 }
	earnedBonus[player].coins = earnedBonus[player].coins + n
end

_G.dinoAddEarnedTokens = function(player, n)
	n = math.floor(tonumber(n) or 0); if n <= 0 or not player then return end
	earnedBonus[player] = earnedBonus[player] or { coins = 0, crateTokens = 0 }
	earnedBonus[player].crateTokens = earnedBonus[player].crateTokens + n
end

-- ===== SIZE GUARD =====
-- Roblox caps TeleportData, and going over does NOT truncate -- TeleportAsync THROWS, so realm travel would
-- break for exactly the players who have played the most. A completionist's skin inventory is combinatorial
-- (every pet x every skin x every trait is its own key), so measure and shed if needed. Pets and the
-- `earned` deltas are NEVER dropped -- they are the whole point of the trip.
local BUDGET_BYTES = 28000

local function encodedSize(t)
	local ok, json = pcall(function() return HttpService:JSONEncode(t) end)
	if not ok then return math.huge end
	return #json
end

local function fit(payload, playerName)
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	if type(payload.petSkins) == "table" then -- duplicate counts matter least; which skins you OWN matters
		local flat = {}
		for k, v in pairs(payload.petSkins) do
			if (tonumber(v) or 0) > 0 then flat[k] = 1 end
		end
		payload.petSkins = flat
		warn(("[Wormhole] %s payload oversized -- collapsed skin duplicate counts"):format(playerName))
		if encodedSize(payload) <= BUDGET_BYTES then return payload end
	end

	payload.collection = nil -- re-derivable on the far side from the inventory already saved there
	warn(("[Wormhole] %s payload still oversized -- dropped collection"):format(playerName))
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	payload.petMilestones = nil -- forwarded flags; the home save still has them
	payload.petSkins      = nil -- last resort: their home save still has every skin, nothing is lost for good
	payload.equippedSkins = nil
	warn(("[Wormhole] %s payload STILL oversized -- dropped the skin inventory"):format(playerName))
	return payload
end

-- Where "home" is for this player: the place the arriving payload named, else the Food realm. Read from
-- the stash ArrivalReceiver keeps (_G.incomingFtFData), so a player who came Food -> Space -> Dino still
-- goes home to Food and not to Space.
local function homeFor(player)
	local d = _G.incomingFtFData and _G.incomingFtFData[player]
	local h = d and tonumber(d.homePlaceId)
	if h and h > 0 and h ~= DINO_PLACE_ID then return h end
	return FOOD_PLACE_ID
end
-- A field this realm carries but does not own: forwarded exactly as it arrived.
local function passthrough(player, key)
	local d = _G.incomingFtFData and _G.incomingFtFData[player]
	return d and d[key] or nil
end
local function titleOf(player)
	local t = player:GetAttribute("Title")
	if type(t) == "string" and t ~= "" then return t end
	return nil
end

local function buildTravelPayload(player, placeId)
	local function g(name, default)
		local t = _G[name]
		local v = t and t[player]
		if v == nil then return default end
		return v
	end

	return fit({
		-- MARKERS. `fromDinoRealm` is what the Food/Space receivers already key off, and `fromFartToFloat`
		-- is the project-wide "this is a real portal arrival" flag every receiver checks before trusting a
		-- payload -- including this place's own ArrivalReceiver.server.luau:135. Sending BOTH means nothing
		-- on the far side has to change for travel to keep working exactly as it does today.
		--
		-- Deliberately NOT set: `arrivedViaRift`. That flag belongs to the Space Realm's time-rift entrance
		-- and makes the receiver hold the player still for a cinematic (ArrivalReceiver.server.luau:100).
		-- A wormhole hop is not that, and claiming it would freeze them for 7s on arrival.
		fromDinoRealm   = true,
		fromFartToFloat = true,
		payloadVersion  = 2,                          -- matches the Food realm's RealmTransfer VERSION
		fromPlaceId     = (game.PlaceId ~= 0) and game.PlaceId or DINO_PLACE_ID, -- live id; the constant only in Studio
		fromRealm       = "dino",
		userId          = player.UserId, -- the far side can refuse a payload stamped for somebody else
		sentAt          = os.time(),

		-- THE WAY HOME. The Food realm's RealmReturnReceiver refuses ANY payload without `returningHome`
		-- (its gate is returningHome AND fromFartToFloat), so every earned coin and token this realm has
		-- ever sent to Food was silently dropped. `homePlaceId` is whatever the arriving payload said
		-- home was (stashed by ArrivalReceiver), defaulting to the Food realm; the flag goes up when the
		-- hop is TO that place.
		homePlaceId     = homeFor(player),
		returningHome   = (placeId == homeFor(player)),

		-- The cosmetic bundle, so anything unlocked/levelled/equipped here survives the hop. Receivers
		-- MERGE these (union + max), so re-sending state they already have is harmless.
		ownedPets     = g("playerOwnedPets", {}),     -- PetUpgrades.server.luau:37
		equippedPet   = g("playerEquippedPet", nil),  -- PetUpgrades.server.luau:38
		petSkins      = g("playerPetSkins", {}),      -- SkinCrateService.server.luau:70
		equippedSkins = g("playerEquippedSkins", {}), -- SkinCrateService.server.luau:71
		collection    = g("playerCollection", {}),    -- SkinCrateService.server.luau:241

		-- CURRENCY, BOTH CHANNELS. `earned` is the DELTA Food's return receiver pays out (it never reads
		-- an absolute), and `crateTokens` is the ABSOLUTE balance the Space realm's FoodTransfer and this
		-- realm's own ArrivalReceiver max-merge (they never read the delta). Sending only the delta, as this
		-- did, meant a Dino -> Space hop arrived with zero tokens. Space's own sender ships both on purpose.
		earned      = earnedFor(player),
		crateTokens = math.floor(tonumber(g("playerCrateTokens", 0)) or 0),
		-- This realm keeps tokens in the universe wallet (UniverseCrateTokens_v1). A receiver on the same
		-- wallet must NOT merge crateTokens / earned.crateTokens (it already has them); a receiver still on
		-- its own private wallet ignores this flag and merges as before.
		sharedTokens = true,

		-- THE TITLE rides with them: the Food and Space receivers both read it, and a title carried INTO
		-- this realm was being lost on the next hop out. Nothing here publishes _G.playerTitle, so the
		-- attribute (set by ArrivalReceiver.carryUniversals) is the source.
		title = titleOf(player),

		-- PASS-THROUGH. Systems this realm does not have (gut skins, per-pet milestones, gamepass flags)
		-- still belong to the player: whatever they arrived with is forwarded UNCHANGED so a Food player's
		-- gut skin and 2x pass do not go dark for having visited the dinosaurs. Nil when they arrived with
		-- nothing (or joined directly), which every receiver treats as "no change".
		petMilestones   = passthrough(player, "petMilestones"),
		ownedGutSkins   = passthrough(player, "ownedGutSkins"),
		equippedGutSkin = passthrough(player, "equippedGutSkin"),
		gamepasses      = passthrough(player, "gamepasses"),
		gamepassIds     = passthrough(player, "gamepassIds"),
	}, player.Name)
end

-- ===== CROSS-PLACE REALM HOP =====
RequestRealmWarp.OnServerInvoke = function(player, realm)
	local placeId = REALM_PLACE[realm]
	if not placeId then return { ok = false, reason = "invalid" } end
	if placeId == DINO_PLACE_ID then return { ok = false, reason = "here" } end -- never teleport to self

	-- GROUNDED gate (same rule as the island warp).
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.FloorMaterial == Enum.Material.Air then
		print(("[Wormhole] BLOCKED %s -> %s Realm: airborne (must be grounded)"):format(player.Name, realm))
		return { ok = false, reason = "airborne" }
	end

	local payload = buildTravelPayload(player, placeId)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(payload)

	local ok, err = pcall(function()
		return TeleportService:TeleportAsync(placeId, { player }, options)
	end)
	if not ok then
		warn(("[Wormhole] realm TeleportAsync failed for %s -> %s (%d): %s")
			:format(player.Name, realm, placeId, tostring(err)))
		return { ok = false, reason = "failed" } -- client shows "couldn't travel", stays put
	end
	local earned = payload.earned
	print(("[Wormhole] %s teleporting -> %s Realm (place %d)%s carrying %d pet(s), %d skin stack(s), %d token(s) abs; earned +%d coins, +%d token(s); title=%s")
		:format(player.Name, realm, placeId, payload.returningHome and " [HOME]" or "", countKeys(payload.ownedPets), countKeys(payload.petSkins),
		        payload.crateTokens or 0, earned.coins, earned.crateTokens, tostring(payload.title)))
	return { ok = true, realm = realm }
end

-- ===== EARNINGS BASELINE =====
-- Every player gets a snapshot on join, including anyone already in (Studio / hot reload), so a live-edit
-- session doesn't leave them with no baseline and a permanently empty `earned`.
Players.PlayerAdded:Connect(snapshot)
for _, p in ipairs(Players:GetPlayers()) do snapshot(p) end

Players.PlayerRemoving:Connect(function(p)
	joinSnapshot[p] = nil
	earnedBonus[p]  = nil
end)

-- Async teleport failures (accepted, then failed to init) -> tell that player's client so it isn't stuck.
TeleportService.TeleportInitFailed:Connect(function(plr, result, errMsg, placeId)
	if placeId == FOOD_PLACE_ID or placeId == SPACE_PLACE_ID or placeId == CANDY_PLACE_ID then
		warn(("[Wormhole] TeleportInitFailed for %s (place %d): %s (%s)")
			:format(plr.Name, placeId, tostring(result), tostring(errMsg)))
		pcall(function() RealmWarpFailed:FireClient(plr) end)
	end
end)

print("[Wormhole] service online (Dino Realm) — visited-only island warps + Food/Space realm hops (travel only, no unlocks).")
print(("[Wormhole] realm hops: Food -> %d, Space -> %d, Candy -> %d (grounded-gated, pcall-guarded)."):format(FOOD_PLACE_ID, SPACE_PLACE_ID, CANDY_PLACE_ID))
print(("[Wormhole] realm hops carry pets/skins/collection + earned coin & token DELTAS (<= %d byte payload)."):format(BUDGET_BYTES))
