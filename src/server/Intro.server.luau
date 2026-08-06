--======================================================================
-- Intro.server.luau  (Server Script)
--======================================================================
-- Owns "should this player get the intro?" and tells the client when to play it.
--======================================================================
-- TWO WAYS IN, AND THEY ARE GATED DIFFERENTLY. THIS IS THE WHOLE FILE.
--======================================================================
--
-- DIRECT JOIN (opened the Dino Realm from the Roblox site)
--   Normally FIRST JOIN ONLY -- the "seen it" flag is persisted in a DataStore, so a returning player
--   doesn't sit through the cinematic every single time. Wait for the character, let the HUD settle,
--   fire IntroPlay.
--
--   ⚠ ALWAYS_REPLAY (below) is currently TRUE, which ignores that flag and replays the intro on every
--   join for everyone -- you are testing. Set it back to false before launch.
--
-- RIFT ARRIVAL (teleported in from the Space Realm)
--   ALWAYS PLAYS. No DataStore gate at all -- and that is deliberate, because gating it is what broke
--   this in the live game:
--
--     In Studio, DataStores are blocked, hasSeen() always fails, and the intro always played -- so it
--     looked fine. In the PUBLISHED game the DataStore works, the player was already flagged as seen
--     from an earlier session, and the intro was silently skipped. The arrival cinematic then sat on
--     black waiting for an intro that was never coming, gave up, and faded into the world by itself.
--
--   Coming through the rift is a STORY BEAT, not first-join onboarding. You built a cinematic for the
--   arrival; the arrival gets it. Every time.
--
--   It also can't just fire on a timer, because the player arrives on a BLACK screen holding the
--   "65 MILLION YEARS AGO" card (ArrivalCinematic.client.luau). Starting the tower descent underneath
--   that black means two cinematics fighting -- they both hide every ScreenGui, both seize the CoreGui,
--   and both anchor the HumanoidRootPart. So we WAIT, and the arrival hands off (IntroRequest) the
--   moment its card is done. The intro's opening slam onto Volcanic Vista becomes the cut out of the
--   black.
--======================================================================

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local RunService         = game:GetService("RunService")

local STORE_NAME = "DinoRealmIntro_v1"

-- ⚠ TESTING: play the intro on EVERY join, for everyone, as if they were a brand new player.
--
-- FLIP THIS TO false BEFORE LAUNCH. With it true, a returning player sits through the full cinematic
-- every single time they join -- which is exactly what you want while you're iterating on it, and
-- exactly what you don't want shipped.
--
-- It only affects DIRECT joins. Rift arrivals ignore it and always play the intro regardless (see below).
local ALWAYS_REPLAY = true

-- The handoff lives on the CLIENT, so it can fail in ways we don't control (the script errored, an
-- exploiter stripped it). If the arrival never hands off, start the intro anyway rather than leaving
-- the player with no opening at all.
local RIFT_HANDOFF_TIMEOUT = 20

local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)

local function ev(name: string): RemoteEvent
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local IntroPlay    = ev("IntroPlay")    -- s->c: play the intro now
local IntroDone    = ev("IntroDone")    -- c->s: the player finished (or skipped) it
local IntroRequest = ev("IntroRequest") -- c->s: the arrival cinematic is done with its card -> hand off

-- A load FAILURE is treated as "not seen". Better to occasionally replay the intro than to silently
-- swallow it for someone whose data didn't load. (Only the DIRECT JOIN path consults this.)
local function hasSeen(player: Player): boolean
	if not store then return false end
	local ok, seen = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok then
		return false
	end
	return seen == true
end

local function markSeen(player: Player)
	if not store then return end
	pcall(function()
		store:SetAsync("u_" .. player.UserId, true)
	end)
end

local function arrivedViaRift(player: Player): boolean
	local ok, jd = pcall(function() return player:GetJoinData() end)
	if not ok then return false end
	local d = jd and jd.TeleportData
	return type(d) == "table" and d.fromFartToFloat == true and d.arrivedViaRift == true
end

local playing         = {} -- [player] = true once fired, so a duplicate request can't double-fire it
local awaitingHandoff = {} -- [player] = true while a rift arrival's client decides when to start
local requested       = {} -- [player] = true if IntroRequest arrived (possibly BEFORE we armed -- see below)

local function fireIntro(player: Player)
	if playing[player] or not player.Parent then return end
	playing[player] = true

	-- THE SERVER OWNS THIS FLAG. It must be set here, not on the client.
	--
	-- A client-set player attribute DOES NOT REPLICATE TO THE SERVER. The first version set it in
	-- Intro.client.luau, so PetXPHooks (server-side) never saw it, the guard did nothing, and the
	-- intro's flight up the tower registered as real progress:
	--     [PetXP] ... reached island 11 (new best) -> HighestIsland = 11
	-- i.e. every new player was handed the whole progression bar during the cinematic.
	--
	-- ArrivalReceiver reads it too: it will NOT unanchor a rift arrival while the intro has the body.
	player:SetAttribute("IntroPlaying", true)

	print(("[Intro] playing the intro for %s"):format(player.Name))
	IntroPlay:FireClient(player)

	-- Safety net: never leave the flag stuck on. If the client dies, disconnects, or errors
	-- mid-cinematic without sending IntroDone, XP would be frozen forever.
	task.delay(60, function()
		if player.Parent and player:GetAttribute("IntroPlaying") then
			warn(("[Intro] %s never reported the intro finishing -> clearing IntroPlaying"):format(player.Name))
			player:SetAttribute("IntroPlaying", false)
		end
	end)
end

-- The arrival cinematic has finished its card and is ready to be cut out of. Go.
--
-- REMEMBER THE REQUEST EVEN IF WE AREN'T ARMED YET. The client can genuinely beat us here: it fires
-- ~4s after its character exists, while this server script is still waiting on CharacterAdded /
-- WaitForChild. Dropping an early request (which is what "if not awaitingHandoff then return end"
-- alone did) meant the intro didn't start on the handoff -- it ambushed the player 20 seconds later
-- off the fallback timer, long after they'd been let into the world.
IntroRequest.OnServerEvent:Connect(function(player)
	requested[player] = true
	if not awaitingHandoff[player] then return end -- not armed yet (or not a rift arrival) -- handled below
	awaitingHandoff[player] = nil
	fireIntro(player)
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- wait for the character, so the client has something to point the camera at
		local char = player.Character or player.CharacterAdded:Wait()
		if not char then return end
		char:WaitForChild("HumanoidRootPart", 15)
		if not player.Parent then return end

		-- CHECK THE RIFT FIRST -- before hasSeen(). GetJoinData is instant; hasSeen() is a DataStore
		-- round trip that can take seconds under live load, and we must not put that latency in front of
		-- an arriving player who is sitting on a black screen waiting for us.
		if arrivedViaRift(player) then
			print(("[Intro] %s arrived through the rift -> holding the intro for the handoff"):format(player.Name))
			awaitingHandoff[player] = true

			if requested[player] then -- the client already asked while we were still waiting on its character
				awaitingHandoff[player] = nil
				fireIntro(player)
				return
			end

			task.delay(RIFT_HANDOFF_TIMEOUT, function()
				if awaitingHandoff[player] and player.Parent then
					warn(("[Intro] %s never handed off from the arrival cinematic -> starting the intro anyway")
						:format(player.Name))
					awaitingHandoff[player] = nil
					fireIntro(player)
				end
			end)
			return
		end

		-- ---- direct join: first time only, unless we're replaying for everyone ----
		if not ALWAYS_REPLAY and hasSeen(player) then
			print(("[Intro] %s has already seen the intro -> skipping"):format(player.Name))
			return
		end

		task.wait(1) -- let the HUD + island layout settle before hijacking the camera
		if not player.Parent then return end
		fireIntro(player)
	end)
end)

IntroDone.OnServerEvent:Connect(function(player)
	markSeen(player)
	print(("[Intro] %s finished the intro -> flagged as seen%s")
		:format(player.Name, RunService:IsStudio() and " (NOT saved -- DataStores are blocked in Studio)" or ""))

	-- Clear IntroPlaying only once the character is actually back down at the spawn.
	--
	-- The cinematic carries the BODY up the whole tower (StreamingEnabled loads geometry
	-- around the character, not the camera) and the CLIENT restores its position at the
	-- end -- so for a few frames after "done" arrives, the server still sees the character
	-- standing on island11, the summit. PetXPHooks polls every frame and only skips while
	-- IntroPlaying is set, so clearing the flag immediately banked the entire tower as
	-- "reached": HighestIsland 11, HighestSlot 13, and every wormhole destination unlocked
	-- on a brand-new join.
	--
	-- island1 sits at Y 150 and the next island up at Y 1620, so 800 is an unambiguous
	-- "back at the bottom" line. The 5s cap means a player who somehow never lands still
	-- gets progression back rather than being stuck with XP disabled forever.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 5 do
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < 800 then break end
			task.wait(0.1)
		end
		if player.Parent then
			player:SetAttribute("IntroPlaying", false) -- XP/progression resumes
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playing[player]         = nil
	awaitingHandoff[player] = nil
	requested[player]       = nil
end)

print(("[Intro] server ready -- rift arrivals ALWAYS get the intro; direct joins: %s")
	:format(ALWAYS_REPLAY and "REPLAYING FOR EVERYONE (⚠ testing -- set ALWAYS_REPLAY = false before launch)"
	                       or ("first join only, gated on " .. STORE_NAME)))
