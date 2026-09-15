--[[
	DINO REALM COPY of the Space realm's DailyCrateService. Same store (RealmDailyCrate_v1), same key, same
	rule, so a claim in either realm closes the day in both. Only the `realm` tag written into the record differs.
	Requires _G.skinCrateFreeSpin from this realm's SkinCrateService (the paid roll with no price).

	DailyCrateService.server.luau  (ServerScriptService.DailyCrateService)

	ONE FREE CRATE SPIN PER DAY, PER PLAYER, ACROSS THE WHOLE GAME.

	This replaces the Meteor Crate's old reward. Claiming no longer rolls a jetpack-flame cosmetic — it opens a
	real SKIN CRATE, with the reel, the odds and the reveal the paid crates use. The player gets the good part of
	the crate system for free, once a day, and the paid packs stay the way to spin it MORE.

	WHO OWNS WHAT
	  * This file owns WHETHER you may spin today. Nothing else may decide that.
	  * SkinCrateService owns WHAT you get (_G.skinCrateFreeSpin -> the same roll the paid path uses).
	  Splitting it that way is what stops the daily crate quietly becoming a second loot table with its own odds.

	=== THE CROSS-REALM RULE, AND WHAT IT CAN ACTUALLY ENFORCE ===
	The ask was: open it in one realm, and you cannot hop to another realm and get a second one. How well that
	can be enforced depends on where the realm lives, and Roblox draws a hard line here:

	  * SPACE REALM <-> DINO REALM — the SAME universe (DinoRift's own comment: "It MUST be a place inside the
	    SAME universe/experience"). DataStores are scoped to the universe, so the claim below is genuinely
	    shared: claim in Dino and Space sees it instantly, and the reverse. This is airtight.

	  * FOOD REALM — ⚠ UNVERIFIED WHETHER THIS IS A DIFFERENT EXPERIENCE. This file says it is;
	    CROSS_REALM_PIPELINE.md says all three places share universe 10236070926. Both cite the same
	    number, so one is wrong. Run tools/RealmPipelineProbe.server.luau in each realm and compare the
	    GameId lines to settle it. The payload stamp below is correct EITHER WAY (it is redundant when
	    the store is shared, and the only channel when it is not), so this code needs no change — but
	    the rest of the shared-store design in section 3 of that document does, if Food is separate.
	    Assuming Food IS separate: NOTHING server-side
	    is shared across experiences: not DataStores, not MemoryStores. So the claim is carried in the TELEPORT
	    PAYLOAD instead — WormholeService stamps today's claim on the way out (payload field `dailyCrateDay`;
	    it genuinely does now — that line was documented here long before the sender existed), and the
	    receiving realm honours it
	    (onJoin below reads TeleportData.dailyCrateDay). That covers travel through the wormhole, which is
	    how players actually move between realms.

	    IT DOES NOT COVER a player who claims here, leaves, and opens the Food Realm from the Roblox website in a
	    fresh session — no teleport, no payload, and no store to check. Closing that hole needs an external HTTP
	    service both experiences call, which is a bigger piece of infrastructure than this. Flagged rather than
	    pretended-away.

	THE DAY BOUNDARY is a UTC day NUMBER (floor(os.time() / 86400)), not a "YYYY-MM-DD" string and not a rolling
	24h timer. A rolling timer drifts later every day until the reward lands at an hour the player is asleep; a
	date string needs real calendar arithmetic to compare, which is exactly the code that breaks on the 1st of
	March. An integer compare cannot do either.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- Which crate the free daily spin opens. "Starter" on purpose: the daily is a reliable trickle, not a jackpot,
-- and pointing it at Mythic would make every paid crate pointless.
local DAILY_CRATE_ID = "Starter"

-- Shared by EVERY PLACE IN THIS UNIVERSE — that is what makes Space <-> Dino airtight. Do not rename it per
-- realm, or each realm gets its own daily and the whole rule collapses.
local store = DataStoreService:GetDataStore("RealmDailyCrate_v1")

local function keyFor(userId)
	return "daily_" .. userId
end

local function today()
	return math.floor(os.time() / 86400)
end

local claimedDay = {} -- [player] = the UTC day number they last claimed (nil = not loaded yet)
local loaded = {}     -- [player] = true once a load finished; gates claiming

--======================================================================
-- REMOTES
--======================================================================
local remotes = ReplicatedStorage:FindFirstChild("DailyCrateRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "DailyCrateRemotes"
	remotes.Parent = ReplicatedStorage
end
local function getOrCreate(className, name)
	local o = remotes:FindFirstChild(name)
	if not o then
		o = Instance.new(className)
		o.Name = name
		o.Parent = remotes
	end
	return o
end
local ClaimDaily = getOrCreate("RemoteFunction", "ClaimDaily") -- c->s RF: () -> the same result a paid open returns
local DailyState = getOrCreate("RemoteEvent", "DailyState")    -- s->c: { ready = bool, secondsLeft = n }

--======================================================================
-- STATE
--======================================================================
local function isReady(player)
	if not loaded[player] then return false end
	return claimedDay[player] ~= today()
end

-- Seconds until the next UTC midnight — what the HUD counts down when the crate is spent.
local function secondsLeft()
	return (today() + 1) * 86400 - os.time()
end

local function push(player)
	pcall(function()
		DailyState:FireClient(player, { ready = isReady(player), secondsLeft = secondsLeft() })
	end)
end

-- Published for the HUD (the MORE+ crate card reads these instead of the old 6h cosmetic-crate timer).
_G.dailyCrateReady = function(player)
	return isReady(player)
end
_G.dailyCrateSecondsLeft = secondsLeft
-- Read by WormholeService on the way out, so the claim rides the teleport payload into an experience that
-- cannot see this store. 0 = hasn't claimed today.
_G.dailyCrateClaimedDay = function(player)
	return claimedDay[player] or 0
end

--======================================================================
-- JOIN
--======================================================================
local function onJoin(player)
	local day = nil

	-- 1. The store: authoritative, and shared with every place in this universe (Space <-> Dino).
	local ok, data = pcall(function()
		return store:GetAsync(keyFor(player.UserId))
	end)
	if ok and type(data) == "table" then
		day = tonumber(data.day)
	elseif not ok then
		-- A failed READ must not hand out a free crate: if we cannot prove they haven't claimed, assume they
		-- have. The alternative is a DataStore outage becoming an unlimited crate faucet.
		warn(("[DailyCrate] LOAD FAILED for %s (%s) — assuming today is already claimed so an outage can't be "
			.. "farmed"):format(player.Name, tostring(data)))
		claimedDay[player] = today()
		loaded[player] = true
		push(player)
		return
	end

	-- 2. The teleport payload: covers the Food Realm, which is a different EXPERIENCE and shares no store with
	-- this one. Whichever is more recent wins, so arriving with a claim stamped can only ever TAKE the crate
	-- away, never hand one back.
	local okJoin, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if okJoin and type(joinData) == "table" and type(joinData.TeleportData) == "table" then
		local stamped = tonumber(joinData.TeleportData.dailyCrateDay)
		if stamped and (not day or stamped > day) then
			day = stamped
			print(("[DailyCrate] %s arrived with a claim stamped for day %d (another realm) — honoured")
				:format(player.Name, stamped))
			-- Write it into OUR store too, so the next join in this universe doesn't need the payload.
			pcall(function()
				store:SetAsync(keyFor(player.UserId), { day = stamped, realm = "carried" })
			end)
		end
	end

	claimedDay[player] = day
	loaded[player] = true
	push(player)
	print(("[DailyCrate] %s: %s"):format(player.Name,
		isReady(player) and "a free crate is WAITING" or ("already claimed today; next in " .. secondsLeft() .. "s")))
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onJoin, player)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, p)
end
Players.PlayerRemoving:Connect(function(player)
	claimedDay[player] = nil
	loaded[player] = nil
end)

--======================================================================
-- CLAIM
--======================================================================
-- SERVER-AUTHORITATIVE, and the write happens BEFORE the roll. If the order were reversed, two claims arriving
-- in the same instant could both pass the check and both spin.
ClaimDaily.OnServerInvoke = function(player)
	if not loaded[player] then
		return { ok = false, reason = "loading" }
	end
	if not isReady(player) then
		return { ok = false, reason = "already_claimed", secondsLeft = secondsLeft() }
	end

	local day = today()
	claimedDay[player] = day -- close the window immediately, in memory

	local okWrite, err = pcall(function()
		store:SetAsync(keyFor(player.UserId), { day = day, realm = "dino" })
	end)
	if not okWrite then
		-- The write is what makes this cross-realm. Without it the claim would not survive a hop to Dino, so
		-- the spin is refused rather than granted un-recorded.
		claimedDay[player] = nil
		warn(("[DailyCrate] SAVE FAILED for %s: %s — claim refused rather than granted un-recorded")
			:format(player.Name, tostring(err)))
		return { ok = false, reason = "save_failed" }
	end

	if not _G.skinCrateFreeSpin then
		claimedDay[player] = nil
		warn("[DailyCrate] _G.skinCrateFreeSpin missing (is SkinCrateService loaded?) — claim refunded")
		return { ok = false, reason = "no_crate_service" }
	end

	local result = _G.skinCrateFreeSpin(player, DAILY_CRATE_ID)
	if type(result) ~= "table" or not result.ok then
		-- The spin itself failed (an empty crate, say). Give the day back — they got nothing for it.
		claimedDay[player] = nil
		pcall(function() store:SetAsync(keyFor(player.UserId), { day = 0, realm = "dino" }) end)
		warn(("[DailyCrate] spin failed for %s (%s) — day given back")
			:format(player.Name, type(result) == "table" and tostring(result.reason) or "no result"))
		push(player)
		return result or { ok = false, reason = "spin_failed" }
	end

	print(("[DailyCrate] %s claimed the daily crate -> [%s] (day %d)")
		:format(player.Name, tostring(result.rarity), day))
	result.daily = true
	push(player)
	return result
end

--======================================================================
-- ROLLOVER
--======================================================================
-- A player online across UTC midnight should see the crate come back without rejoining. One check a minute is
-- plenty for a daily.
task.spawn(function()
	local lastDay = today()
	while true do
		task.wait(60)
		local d = today()
		if d ~= lastDay then
			lastDay = d
			for _, player in ipairs(Players:GetPlayers()) do
				push(player)
			end
			print("[DailyCrate] UTC day rolled over — everyone's crate is ready again")
		end
	end
end)

print(("[DailyCrate] online — one free %s Crate spin per UTC day, shared across every place in this universe "
	.. "(Space <-> Dino). Food Realm is a separate experience: the claim rides the teleport payload."):format(DAILY_CRATE_ID))
if RunService:IsStudio() then
	print("[DailyCrate] Studio: DataStore access must be enabled (Game Settings > Security) or every load fails "
		.. "closed and the crate never appears ready.")
end
