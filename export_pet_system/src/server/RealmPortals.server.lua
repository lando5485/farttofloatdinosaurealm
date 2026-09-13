--======================================================================
-- RealmPortals.server.lua  (Script)   [SENDING PLACE -- the islands]
--======================================================================
-- The three portals on Bean Island (Island 1), and the CHAIN that gates them:
--
--     SPACE REALM (open to all)  ->  DINO REALM  ->  CANDY REALM
--
-- You BEAT a realm to earn the next one -- there is no island requirement anywhere in here. Space is
-- open from day one; Dino needs Space finished; Candy needs Dino finished. Every kid lands on Bean
-- Island, so all three portals are always VISIBLE -- a locked one stands there dark with its
-- requirement written over it ("Complete the Space Realm"). It's a goal board as much as a door.
--
-- WHERE "COMPLETED" COMES FROM (this is the tricky part -- realms are separate PLACES, so leaderstats
-- and _G do NOT come back with the player; the only shared state is the universe-scoped DataStore):
--   * Space done  = SpaceRealm_PlayerState_v1 -> highestPlanetReached >= 8 (Neptune, the last planet).
--                   Same store + field PlanetSelectService already reads.
--   * Dino done   = DinoRealm_PlayerState_v1  -> dinoComplete == true. That place is still a stub and
--                   writes NOTHING yet, so this read comes back empty and Candy stays locked -- which is
--                   correct. The DAY the Dino place starts saving that field, Candy unlocks by itself.
-- Reads FAIL CLOSED: a DataStore blip means "you haven't unlocked it", never a free realm.
--
-- ASSIGNMENT: the BaseParts named "Portal" are sorted left-to-right (X, then Z) and handed a realm in
-- CHAIN order -- leftmost = Space, middle = Dino, rightmost = Candy -- so the row reads as the journey.
-- To pin a block instead, give it a string Attribute "Realm" = "space" | "dino" | "candy" in Studio.
--
-- SECURITY (same shape as BlackHoleTeleport): the client fires INTENT ONLY -- a realm KEY, never a
-- placeId. This server re-validates the key, checks the player is really standing at that portal, checks
-- the unlock, and only then teleports. The client never teleports itself.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local DataStoreService  = game:GetService("DataStoreService")
local Workspace         = game:GetService("Workspace")

-- ===== NAMED 'RealmPortalsHub' IN THE PROJECT, NOT 'RealmPortals' =====
-- Same story as the client. An old copy of this file is baked into the place under the name 'RealmPortals',
-- and both copies ran the same first-come-wins guard -- whoever booted first destroyed the other by name.
-- Roblox does not promise a boot order, so which version of the game you got was a coin flip. When the
-- stale one won, the teleport ran on ITS timings (the old 1.2s wait) and cut the client's outro off part
-- way through, which is one of the ways the transition "sometimes" did not happen.
--
-- Renaming the Rojo instance to 'RealmPortalsHub' makes this copy invisible to the old copy's name-matched
-- sweep, while the legacy-name list below still lets us shut IT down. The race is removed, not improved.
--
-- ⚠ Still delete the old 'RealmPortals' Script in Studio's ServerScriptService and republish.
local LEGACY_NAMES = { RealmPortals = true, RealmPortalsHub = true }

-- NOT a bail-out, on purpose: bailing here is how the current version used to lose. Take over instead.
local legacyWonTheRace = _G.__RealmPortalsServer == true
_G.__RealmPortalsServer = true

-- NEUTRALIZE STALE DUPLICATES: an OLD copy of this script baked into the place still runs alongside us. It
-- doesn't know about /unlock (its `space` is "locked"), so when you walk into a portal IT answers "locked"
-- and drowns out our "traveling"/teleport. Destroy every same-named sibling Script here (best effort, run
-- FIRST so if we load before the stale copy it never even connects). The clean fix is deleting it in Studio.
local STALE_SCAN = { "ServerScriptService", "ServerStorage", "ReplicatedStorage", "ReplicatedFirst", "Workspace" }
local function nukeStaleServerCopies()
	local removed = 0
	for _, svcName in ipairs(STALE_SCAN) do
		local ok, svc = pcall(function() return game:GetService(svcName) end)
		if ok and svc then
			for _, inst in ipairs(svc:GetDescendants()) do
				if inst ~= script and inst:IsA("Script") and LEGACY_NAMES[inst.Name] then
					pcall(function() inst.Disabled = true; inst:Destroy() end)
					removed = removed + 1
				end
			end
		end
	end
	if removed > 0 then
		warn("[RealmPortals] removed " .. removed .. " STALE duplicate server script(s). If portals are STILL locked, one lives elsewhere -- in Studio, search Explorer for 'RealmPortals' and delete every copy but the Rojo one.")
	end
end
nukeStaleServerCopies()
task.delay(1, nukeStaleServerCopies); task.delay(4, nukeStaleServerCopies); task.delay(9, nukeStaleServerCopies)

if legacyWonTheRace then
	warn("[RealmPortals] the STALE baked-in server copy booted BEFORE this one and has now been shut down. " ..
		"Delete the old 'RealmPortals' Script in Studio to stop this happening at all.")
end

-- THE PROOF LINE. If a crossing ever misbehaves again, look for this first: no line = the copy that booted
-- is not this file, and none of the timings below (including the 4.2s that the outro is cut to fit) applied.
print("[RealmPortals] SERVER BUILD 10 ACTIVE -- this is the Rojo copy (4.2s outro hold + enter receipts)")

-- Space Realm's save (universe-scoped, shared across places). These strings MUST match Space Realm's
-- Constants -- they're the same ones PlanetSelectService.server.lua reads.
local SPACE_STORE   = "SpaceRealm_PlayerState_v1"
local SPACE_PLANETS = 8 -- Neptune is #8; reaching it == Space Realm completed

-- Dino Realm's save. ⚠ The Dino place does not write this yet (it's a stub) -- see the header.
local DINO_STORE = "DinoRealm_PlayerState_v1"

local KEY_PREFIX = "Player_" -- Constants.DATASTORE_KEY_PREFIX, shared by both stores

-- placeId = 0 means "that place doesn't exist yet" -> the portal is built and touchable but says
-- "Coming soon!" instead of teleporting. Candy is the temporary one: fill in its placeId when you build
-- the place and it starts working with no other edits.
local REALMS = {
	space = {
		name = "Space Realm", placeId = 125063266868039, -- same place BlackHoleTeleport uses
		requires = "locked",                             -- LOCKED for now -> shows 🔒 + "not unlocked" message
		reqText  = "Not unlocked yet",
	},
	dino = {
		name = "Dino Realm", placeId = 110777788409412,
		requires = "space",                              -- must have finished Space Realm
		reqText  = "Complete the Space Realm",
	},
	candy = {
		name = "Candy Realm", placeId = 133591422694132, -- FART TO FLOAT [CANDY REALM] (same universe)
		requires = "locked",                             -- LOCKED, same as Space -> 🔒 + "not unlocked" message
		reqText  = "Not unlocked yet",
	},
}
local CHAIN = { "space", "dino", "candy" } -- progression order == left-to-right across the island

-- TESTER BYPASS -- who may use the /unlock command. UserId first; name (case-INSENSITIVE) as a fallback so
-- a Roblox rename or a casing mismatch can't lock them out. Studio always counts, so you can test there.
local RunService   = game:GetService("RunService")
local TESTER_IDS   = { [1086836724] = true, [1418148401] = true, [3911540303] = true }   -- lando5485, Broskie310111, Itsmaddmax1
local TESTER_NAMES = { ["lando5485"] = true, ["broskie310111"] = true, ["itsmaddmax1"] = true } -- lowercase keys; compared against Name:lower()
local function isTester(plr)
	return RunService:IsStudio()
		or TESTER_IDS[plr.UserId] == true
		or TESTER_NAMES[string.lower(plr.Name)] == true
end

local TOUCH_RANGE = 40 -- studs the player may be from a portal of that realm when their intent lands

local spaceStore = DataStoreService:GetDataStore(SPACE_STORE)
local dinoStore  = DataStoreService:GetDataStore(DINO_STORE)

-- getOrCreate, so a missing project.json entry can't break the remote. The client WaitForChild's this name.
local enterEvent = ReplicatedStorage:FindFirstChild("RealmPortalEvent")
if not enterEvent then
	enterEvent = Instance.new("RemoteEvent"); enterEvent.Name = "RealmPortalEvent"; enterEvent.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- who has completed what
--------------------------------------------------------------------------------
-- Both reads FAIL CLOSED: on a DataStore error we return false ("not completed"). If the store blips,
-- the safe answer is "you haven't earned it", never "here, have a realm".
local function readCompleted(store, userId, check, label)
	local data
	local ok, err = pcall(function() data = store:GetAsync(KEY_PREFIX .. tostring(userId)) end)
	if not ok then
		warn(("[RealmPortals] %s read failed for %d: %s -- failing CLOSED"):format(label, userId, tostring(err)))
		return false
	end
	if type(data) ~= "table" then return false end -- never been there (or the place saves nothing yet)
	return check(data) == true
end

local function spaceCompleted(userId)
	return readCompleted(spaceStore, userId, function(d)
		return type(d.highestPlanetReached) == "number" and math.floor(d.highestPlanetReached) >= SPACE_PLANETS
	end, "SpaceRealm")
end

local function dinoCompleted(userId)
	return readCompleted(dinoStore, userId, function(d)
		return d.dinoComplete == true -- ⚠ nothing writes this yet -- Candy stays locked until the Dino place does
	end, "DinoRealm")
end

-- Cached per player: the DataStore reads happen ONCE on join (a realm can only be completed in ANOTHER
-- place, which means they teleported away and rejoined -- so a join-time read can't go stale), plus a
-- throttled refresh when they actually walk into a locked portal, as a belt-and-braces retry.
local completed = {} -- [player] = { space = bool, dino = bool }
local lastRefresh = {} -- [player] = os.clock()
local forceUnlocked = {} -- [player] = true -- set by the "/unlock" chat command (testers only); opens every realm

-- Has this player actually EARNED the realm? No tester bypass here -- this is the honest progression, and
-- it's what the portals DISPLAY. So a tester sees the 🔒 exactly like a normal player would (which is what
-- you want when checking how the locked state looks), even though the bypass below still lets them travel.
local function progressUnlocked(player, key)
	local realm = REALMS[key]
	local c = completed[player] or {}
	if forceUnlocked[player] then return true end       -- "/unlock" override -> every realm open (and shown unlocked)
	if realm.requires == "none"   then return true end  -- open to everyone
	if realm.requires == "locked" then return false end -- always locked (place not open to players yet)
	if realm.requires == "space"  then return c.space == true end
	if realm.requires == "dino"   then return c.dino  == true end
	return false
end

-- May this player TRAVEL through? NOTE: the tester bypass was removed on request -- lando5485 and
-- Broskie310111 now experience every realm as a normal NEW player would (locked, with the 🔒 message),
-- so what you see IS what a real player sees. Re-add `if isTester(player) then return true end` to test.
local function unlockedFor(player, key)
	return progressUnlocked(player, key)
end

-- Tell one player the state of all three portals, so their client can render each sign: unlocked, or the
-- exact thing they still have to do. This is PER PLAYER (a part Attribute can't be -- it's global).
local function pushState(player)
	local state = {}
	for _, key in ipairs(CHAIN) do
		local realm = REALMS[key]
		state[key] = {
			unlocked = progressUnlocked(player, key), -- what they've EARNED -> testers see the lock too
			built    = realm.placeId ~= 0,            -- false -> "Coming soon!"
			reqText  = realm.reqText,
		}
	end
	pcall(function() enterEvent:FireClient(player, "state", state) end)
end

local function refresh(player, force)
	local now = os.clock()
	if not force and lastRefresh[player] and (now - lastRefresh[player]) < 15 then return end -- throttle DataStore reads
	lastRefresh[player] = now
	local uid = player.UserId
	completed[player] = {
		space = spaceCompleted(uid), -- yields
		dino  = dinoCompleted(uid),  -- yields
	}
	if player.Parent then
		print(("[RealmPortals] %s -- spaceDone=%s dinoDone=%s")
			:format(player.Name, tostring(completed[player].space), tostring(completed[player].dino)))
		pushState(player)
	end
end

-- CHAT COMMANDS (testers only): "/unlock" opens every realm for you; "/lock" puts the gates back.
-- Gated to isTester so a normal player can't type their way past the whole progression chain.
local function handleChat(player, message)
	local cmd = tostring(message):lower():match("^%s*(%S+)") or "" -- first word, so "/unlock now" still matches
	if cmd ~= "/unlock" and cmd ~= "/lock" then return end          -- not one of ours -> ignore quietly
	if not isTester(player) then
		print(("[RealmPortals] %s (UserId %d) tried %s but isn't a tester -- ignoring"):format(player.Name, player.UserId, cmd))
		return
	end
	if cmd == "/unlock" then
		forceUnlocked[player] = true
		pushState(player) -- redraw the portals as unlocked right away
		print("[RealmPortals] " .. player.Name .. " used /unlock -- all realms open")
	else -- "/lock"
		forceUnlocked[player] = nil
		pushState(player)
		print("[RealmPortals] " .. player.Name .. " used /lock -- realms gated again")
	end
end

-- The modern chat (TextChatService) does NOT fire Player.Chatted, so ALSO register real slash commands.
-- Harmless on the legacy chat (the command just never triggers there -- Player.Chatted covers that case).
do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "RealmUnlockCommand"
		cmd.PrimaryAlias   = "/unlock"
		cmd.SecondaryAlias = "/lock"
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(function(source, unfilteredText)
			local plr = source and Players:GetPlayerByUserId(source.UserId)
			if plr then handleChat(plr, unfilteredText) end
		end)
	end)
	if ok then print("[RealmPortals] /unlock + /lock registered as TextChatService commands")
	else warn("[RealmPortals] TextChatService command registration failed: " .. tostring(err)) end
end

local function onPlayerAdded(player)
	completed[player] = { space = false, dino = false } -- fail closed until the reads land
	-- STUDIO: auto-open the realms so you never need to type /unlock (the chat can be hidden in Studio).
	-- Live servers are unaffected -- this only fires in Studio, where teleports don't work anyway.
	if RunService:IsStudio() then forceUnlocked[player] = true end
	pushState(player)                                    -- draw the portals immediately, don't wait on DataStore
	task.spawn(refresh, player, true)                    -- then correct them once the reads come back
	player.Chatted:Connect(function(msg) handleChat(player, msg) end) -- legacy chat path
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end -- players already in (Studio / hot reload)

Players.PlayerRemoving:Connect(function(p)
	completed[p]     = nil
	lastRefresh[p]   = nil
	forceUnlocked[p] = nil
end)

--------------------------------------------------------------------------------
-- finding + assigning the blocks
--------------------------------------------------------------------------------
local partsByRealm = {} -- [realmKey] = { BasePart, ... } -- what the proximity check validates against
for key in pairs(REALMS) do partsByRealm[key] = {} end

local function collectPortalParts()
	local list = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Portal" then list[#list + 1] = d end
	end
	table.sort(list, function(a, b)
		if math.abs(a.Position.X - b.Position.X) > 0.5 then return a.Position.X < b.Position.X end
		return a.Position.Z < b.Position.Z
	end)
	return list
end

local function tagPart(part, key)
	part:SetAttribute("Realm", key) -- the client reads this to know which portal to BUILD here

	-- The block is a PLACEMENT MARKER, never scenery: it says where the portal goes and which way it
	-- faces, and then it gets out of the way. Hidden here on the SERVER (so it replicates invisible to
	-- everybody, even before that client has built its portal), and hidden again client-side as a
	-- belt-and-braces. It's still visible in Studio's editor, so you can always find and move it.
	part.Transparency = 1
	part.CanCollide   = false -- you walk through it
	part.CanTouch     = false -- the portal's FORCE FIELD is what starts a transfer, not this brick
	part.CastShadow   = false -- an invisible brick casting a shadow is a classic giveaway
	part.Anchored     = true

	table.insert(partsByRealm[key], part)
end

-- Re-runnable: only ever touches parts that don't have a realm yet, so a Portal that streams in or gets
-- rebuilt later still gets wired. Never a one-shot attach.
local assigning = false
local function assignPortals()
	if assigning then return end
	assigning = true

	local unassigned = {}
	for _, part in ipairs(collectPortalParts()) do
		local pinned = part:GetAttribute("Realm") -- hand-pinned in Studio? respect it
		if type(pinned) == "string" and REALMS[pinned] then
			if not table.find(partsByRealm[pinned], part) then tagPart(part, pinned) end
		else
			unassigned[#unassigned + 1] = part
		end
	end

	local slot = 1
	for _, part in ipairs(unassigned) do
		while CHAIN[slot] and #partsByRealm[CHAIN[slot]] > 0 do slot = slot + 1 end -- skip realms already claimed
		local key = CHAIN[slot]
		if not key then
			warn("[RealmPortals] more 'Portal' blocks than realms -- ignoring the extra at " .. tostring(part.Position))
			break
		end
		tagPart(part, key)
		print(("[RealmPortals] Portal at %s -> %s"):format(tostring(part.Position), REALMS[key].name))
		slot = slot + 1
	end

	assigning = false
end

assignPortals()
Workspace.DescendantAdded:Connect(function(d) -- a Portal built or streamed in after us still gets wired
	if d:IsA("BasePart") and d.Name == "Portal" then task.defer(assignPortals) end
end)

--------------------------------------------------------------------------------
-- the teleport
--------------------------------------------------------------------------------
-- Is the player actually AT a portal for the realm they asked for? Stops a fired remote from teleporting
-- somebody who never walked to the block.
local function atPortal(player, key)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	for _, part in ipairs(partsByRealm[key] or {}) do
		if part.Parent and (part.Position - hrp.Position).Magnitude <= TOUCH_RANGE then return true end
	end
	return false
end

local teleporting = {} -- [player] = true -- server-side debounce: never double-teleport

--======================================================================
-- THE PAYLOAD
--======================================================================
-- Defined ONCE in ReplicatedStorage/Shared/RealmTransfer, shared with DinoRealmTeleport.server.lua -- a
-- player can reach the Dino Realm through either door, and the receivers over there must see the same shape
-- whichever one they used. See that module for what travels, what deliberately doesn't, and the size guard.
--
-- `realm` is passed as an extra because the existing receivers already read that key by name.
--
-- FALLBACK: if the module can't load we still teleport, with the old pets-only payload. A broken require must
-- not strand players at a portal that refuses to open; the worst it should cost is their cosmetics.
local RealmTransfer
do
	local ok, mod = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 20)
		return shared and require(shared:WaitForChild("RealmTransfer", 20))
	end)
	if ok then RealmTransfer = mod
	else warn("[RealmPortals] RealmTransfer module unavailable (" .. tostring(mod) .. ") -- falling back to a pets-only payload") end
end

local function buildTransferPayload(player, realmKey)
	if RealmTransfer then
		local ok, payload = pcall(function()
			return RealmTransfer.build(player, realmKey, { realm = realmKey })
		end)
		if ok and type(payload) == "table" then return payload end
		warn("[RealmPortals] RealmTransfer.build failed (" .. tostring(payload) .. ") -- falling back to a pets-only payload")
	end
	return { -- the pre-module payload: enough for the pets to arrive, just without their cosmetics
		fromFartToFloat = true,
		payloadVersion  = 1,
		fromPlaceId     = game.PlaceId,
		homePlaceId     = game.PlaceId,
		realm           = realmKey,
		toRealm         = realmKey,
		userId          = player.UserId,
		ownedPets   = (_G.playerOwnedPets   and _G.playerOwnedPets[player])   or {},
		equippedPet = (_G.playerEquippedPet and _G.playerEquippedPet[player]) or nil,
	}
end

--------------------------------------------------------------------
-- LAND THEM WITH THEIR FRIENDS.
--------------------------------------------------------------------
-- A portal that drops you into a random empty server has technically worked and has actually failed: the
-- reason two kids walk through together is to still be together on the other side. Roblox will not do this
-- on its own -- TeleportAsync picks whatever instance it likes -- so the sending place has to look up where
-- the friends already are and name the instance explicitly.
--
-- BEST EFFORT, ALWAYS. Every part of this can fail for reasons that are nobody's fault: the friend list is a
-- web call, GetPlayerPlaceInstanceAsync respects the other player's join-privacy setting, and the server it
-- finds may fill in the seconds before the teleport lands. So it is wrapped end to end, capped, and every
-- failure path falls through to the ordinary teleport rather than blocking the trip. Nobody is ever stuck at
-- a portal because a friend lookup timed out.
local FRIEND_SCAN_CAP  = 24    -- friends to check at most; a 200-friend list is not worth 200 web calls
local FRIEND_TIME_CAP  = 1.5   -- seconds; past this the player is just standing at a portal waiting

local function friendInstanceIn(player, placeId)
	local deadline = os.clock() + FRIEND_TIME_CAP
	local found, checked = nil, 0

	local ok = pcall(function()
		local page = Players:GetFriendsAsync(player.UserId)
		while true do
			for _, f in ipairs(page:GetCurrentPage()) do
				if found or checked >= FRIEND_SCAN_CAP or os.clock() > deadline then return end
				checked = checked + 1
				-- Returns (success, errorMessage, placeId, instanceId). It is only allowed to answer for
				-- players whose privacy permits it, so a `false` here is a normal outcome, not an error.
				local callOk, success, _, pid, iid =
					pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, f.Id)
				if callOk and success and pid == placeId and iid then
					found = iid
					return
				end
			end
			if page.IsFinished then break end
			page:AdvanceToNextPageAsync()
		end
	end)

	if not ok then return nil end
	return found
end

enterEvent.OnServerEvent:Connect(function(player, key)
	-- FIRST LINE, BEFORE EVERY GUARD. The three early returns below are all silent, so a request that dies
	-- on one of them looks identical to a request that never arrived -- and that ambiguity is exactly what
	-- made this hard to pin down: the client logged "portal entered", the server logged nothing at all, and
	-- there was no way to tell "the remote never landed" from "it landed and was dropped without a word".
	-- This line is the arrival receipt. If you see it, the message got here and the fault is below;
	-- if you DON'T see it after a client-side "portal entered", the message never made it off the client.
	print(("[RealmPortals] RECEIVED enter from %s key=%s (teleporting=%s)")
		:format(tostring(player and player.Name), tostring(key), tostring(teleporting[player] ~= nil)))

	if not player or teleporting[player] then return end

	local realm = type(key) == "string" and REALMS[key] -- VALIDATE: one of these three keys, never a raw placeId
	if not realm then
		print("[RealmPortals] DROPPED -- key " .. tostring(key) .. " is not one of space/dino/candy")
		return
	end

	if not atPortal(player, key) then
		print("[RealmPortals] " .. player.Name .. " asked for " .. realm.name .. " but isn't at that portal -- ignored")
		return
	end

	-- LOCKED first, so a locked realm always gives the "not unlocked" message -- even Candy, whose place
	-- doesn't exist yet (its placeId is 0). Only an actually-unlocked realm reaches the "coming soon" check.
	if not unlockedFor(player, key) then
		pcall(function() enterEvent:FireClient(player, "status", key, "locked", realm.reqText) end)
		task.spawn(refresh, player, false) -- they may have JUST earned it; re-read so a stale cache can't strand them
		print(("[RealmPortals] %s -> %s LOCKED (%s)"):format(player.Name, realm.name, realm.reqText))
		return
	end

	if realm.placeId == 0 then -- unlocked, but the place isn't built yet
		pcall(function() enterEvent:FireClient(player, "status", key, "soon") end)
		return
	end

	teleporting[player] = true
	pcall(function() enterEvent:FireClient(player, "status", key, "traveling") end)
	-- MUST match PORTAL_CINEMATIC_SECONDS in RealmPortals.client.luau. The client's outro hides the HUD,
	-- peels it off screen, opens the portal iris and ends holding on a black title card -- the teleport
	-- happens under that black, which is what hides the place boundary. Teleporting early (this was 1.2s)
	-- cuts the shot off mid-crossing.
	task.wait(4.2)
	if not player.Parent then teleporting[player] = nil; return end -- they left during the pause

	-- Looked up BEFORE the options are built and outside the teleport pcall, so a slow or refused lookup
	-- can never turn into a failed teleport -- worst case it returns nil and they travel normally.
	local friendInstance = friendInstanceIn(player, realm.placeId)

	local ok, err = pcall(function()
		-- Carry state across. Read on the far side via player:GetJoinData().TeleportData -- the receivers
		-- (SpaceRealm/PetReceiver, DinoRealm/ArrivalReceiver) check `fromFartToFloat` to tell a real portal
		-- arrival from someone who opened that place directly.
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData(buildTransferPayload(player, key))
		if friendInstance then options.ServerInstanceId = friendInstance end
		TeleportService:TeleportAsync(realm.placeId, { player }, options)
	end)

	if friendInstance then
		print(("[RealmPortals] %s routed into a friend's %s server"):format(player.Name, realm.name))
	end

	print(("[RealmPortals] teleport %s -> %s (placeId %d): %s")
		:format(player.Name, realm.name, realm.placeId, ok and "ok" or ("err: " .. tostring(err))))

	if not ok then
		teleporting[player] = nil -- failed -> let them retry
		pcall(function() enterEvent:FireClient(player, "status", key, "error") end)
	end
end)

Players.PlayerRemoving:Connect(function(p) teleporting[p] = nil end)

print(("[RealmPortals] ready -- chain: islands -> Space(%d) -> Dino(%d) -> Candy(%d)  [0 = not built yet]")
	:format(REALMS.space.placeId, REALMS.dino.placeId, REALMS.candy.placeId))
