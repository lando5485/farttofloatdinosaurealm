--======================================================================
-- Monsoon.server.luau  (Server Script)
--======================================================================
-- Orchestrates the "Monsoon Rain" weather event.
--
-- Heavy tropical rain sweeps across the dinosaur realm:
--   * Heavy rain reduces visibility (CLIENT tightens fog).           [visual]
--   * A light mist covers the islands (CLIENT fog/atmosphere tint).  [visual]
--   * Wet conditions reduce flight distance by 10% (CLIENT sets
--     _G.flightDistanceMultiplier = 0.9; BottomHUD reads it).        [gameplay]
--   * Dinosaurs roar more frequently (SERVER plays a roar Sound on
--     dino / follower-pet models on a short cadence).                [gameplay]
--
-- Mirrors the Ice Age event's conventions:
--   * All sequencing runs on the SERVER; presentation is broadcast to every
--     client via the MonsoonSync RemoteEvent as (phase, payload).
--   * _G.BigEvents.monsoon = { start, isRunning } registry entry.
--   * _G.startMonsoon manual trigger + a MonsoonTrigger RemoteEvent driven by
--     the "/monsoon" chat command (MonsoonCommand.client.luau).
--   * Everything is restored / cleaned up on reset (no leftovers).
--======================================================================

--======================================================================
-- CONFIG  -- everything here is tunable.
--======================================================================
local CONFIG = {
	-- ---------------- TIMINGS (seconds) ----------------
	WARNING_DURATION = 8,   -- rain builds, sky darkens, mist creeps in
	MAIN_DURATION    = 90,  -- the full downpour (roars + flight penalty here)
	ENDING_DURATION  = 10,  -- rain eases, fog clears, sky restores

	-- ---------------- GAMEPLAY ----------------
	-- Wet conditions: -10% flight distance. The client sets
	-- _G.flightDistanceMultiplier to this during MAIN; BottomHUD multiplies the
	-- ascent speed by it. 1.0 = no penalty, 0.9 = -10%.
	FLIGHT_MULTIPLIER = 0.9,

	-- Dino roars: how often (random in this range) a roar plays somewhere in the
	-- world during MAIN. Shorter = more frequent roars.
	ROAR_INTERVAL_MIN = 4,
	ROAR_INTERVAL_MAX = 8,
	-- ★ SET THIS ★ to your preferred dinosaur-roar audio asset (e.g.
	-- "rbxassetid://<id>"). Left blank => roars are silently skipped (the rest of
	-- the event still runs). This game had NO roar sound before, so pick one.
	ROAR_SOUND_ID     = "",
	ROAR_VOLUME       = 1,
	ROAR_MAX_DISTANCE = 240,  -- studs the roar can be heard from (positional)

	-- ---------------- VISUALS (client applies these) ----------------
	-- Fog end (visibility). Lower = thicker rain/mist. Kept playable.
	FOG_END_WARNING = 2200,
	FOG_END_MAIN    = 900,
	FOG_START_MAIN  = 40,
	FOG_END_ENDING  = 3500,
	FOG_COLOR       = { 150, 165, 180 }, -- gray-blue rain haze (R,G,B)
}

--======================================================================
-- Services + RemoteEvents.
--======================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- MonsoonSync: server -> client presentation (phase, payload).
local MonsoonSync = ReplicatedStorage:FindFirstChild("MonsoonSync")
if not MonsoonSync then
	MonsoonSync = Instance.new("RemoteEvent")
	MonsoonSync.Name = "MonsoonSync"
	MonsoonSync.Parent = ReplicatedStorage
end

-- MonsoonTrigger: client -> server "start it now" (the /monsoon command).
local MonsoonTrigger = ReplicatedStorage:FindFirstChild("MonsoonTrigger")
if not MonsoonTrigger then
	MonsoonTrigger = Instance.new("RemoteEvent")
	MonsoonTrigger.Name = "MonsoonTrigger"
	MonsoonTrigger.Parent = ReplicatedStorage
end

--======================================================================
-- State.
--======================================================================
local eventRunning = false -- guard so we never run two monsoons at once

-- Broadcast a lifecycle phase to every client. (Also stashes the current phase
-- for any late-join replay system, mirroring the Ice Age convention -- harmless
-- if none exists.)
local function fireSync(phase, payload)
	MonsoonSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.monsoon
	if e then e.currentPhase, e.currentPayload = phase, payload end
end

--======================================================================
-- DINO ROARS (added from scratch -- this game had no roar system).
-- Find dinosaur-ish models in the world and play a positional roar on one.
-- Candidates: the world dinos (dino1 / MamaRaptor / RaptorModel) and every
-- follower-pet clone (named "<Something>Follower", PrimaryPart = "Root", parented
-- to workspace by PetFollow.client.luau).
--======================================================================
local function isDinoModel(m)
	if not m:IsA("Model") then return false end
	local n = m.Name
	return n:match("Follower$") ~= nil
		or n == "dino1" or n == "MamaRaptor" or n == "RaptorModel"
		or n:find("Raptor") ~= nil
end

local function gatherRoarParts()
	local parts = {}
	for _, m in ipairs(workspace:GetDescendants()) do
		if isDinoModel(m) then
			local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
			if part then parts[#parts + 1] = part end
		end
	end
	return parts
end

local function playRoar()
	if CONFIG.ROAR_SOUND_ID == "" then return end -- no asset set -> skip silently
	local parts = gatherRoarParts()
	if #parts == 0 then return end
	local part = parts[math.random(#parts)]
	if not part or not part.Parent then return end

	local s = Instance.new("Sound")
	s.Name = "MonsoonRoar"
	s.SoundId = CONFIG.ROAR_SOUND_ID
	s.Volume = CONFIG.ROAR_VOLUME
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = CONFIG.ROAR_MAX_DISTANCE
	s.Parent = part
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(10, function() if s and s.Parent then s:Destroy() end end) -- safety cleanup
end

-- Roar loop: runs only while `active` stays true (MAIN phase). Each roar waits a
-- random ROAR_INTERVAL, so shorter intervals = more frequent roars.
local function runRoarLoop(active)
	task.spawn(function()
		while active() do
			playRoar()
			local wait = CONFIG.ROAR_INTERVAL_MIN
				+ math.random() * (CONFIG.ROAR_INTERVAL_MAX - CONFIG.ROAR_INTERVAL_MIN)
			local t0 = os.clock()
			while active() and os.clock() - t0 < wait do task.wait(0.25) end
		end
	end)
end

--======================================================================
-- Full event sequence. Returns when done + cleaned.
--======================================================================
local function runEvent()
	if eventRunning then return end
	eventRunning = true

	local mainActive = false
	local function roarActive() return mainActive end

	local ok, err = pcall(function()
		local fogColor = CONFIG.FOG_COLOR

		-- ---- 1) START / WARNING: rain builds, sky darkens, mist creeps in ----
		fireSync("start", {
			text = "\u{1F327}\u{FE0F} HEAVY RAIN INCOMING!",
			fogEnd = CONFIG.FOG_END_WARNING,
			fogStart = 80,
			fogColor = fogColor,
			flightMultiplier = 1, -- penalty only kicks in at MAIN
		})
		task.wait(CONFIG.WARNING_DURATION)

		-- ---- 2) MAIN: the full downpour ----
		fireSync("main", {
			text = "\u{1F327}\u{FE0F} Heavy Rain",
			fogEnd = CONFIG.FOG_END_MAIN,
			fogStart = CONFIG.FOG_START_MAIN,
			fogColor = fogColor,
			flightMultiplier = CONFIG.FLIGHT_MULTIPLIER, -- -10% flight distance
		})
		mainActive = true
		runRoarLoop(roarActive) -- dinos roar more frequently during MAIN
		task.wait(CONFIG.MAIN_DURATION)
		mainActive = false      -- stops the roar loop

		-- ---- 3) ENDING: rain eases, fog clears ----
		fireSync("ending", {
			text = "\u{1F327}\u{FE0F} Heavy Rain Passing\u{2026}",
			fogEnd = CONFIG.FOG_END_ENDING,
			fogStart = 120,
			fogColor = fogColor,
			flightMultiplier = 1, -- flight back to normal as it clears
		})
		task.wait(CONFIG.ENDING_DURATION)
	end)

	if not ok then
		warn("[Monsoon] event errored: " .. tostring(err))
	end

	-- ---- RESET: client restores Lighting + removes rain + clears the flight
	-- multiplier. Roar loop is already stopped (mainActive = false).
	mainActive = false
	fireSync("reset", {})
	eventRunning = false
end

--======================================================================
-- Public starter + triggers.
--======================================================================
local function startEvent()
	if eventRunning then
		warn("[Monsoon] start ignored: a Monsoon is already running.")
		return
	end
	task.spawn(runEvent)
end

-- Registry (mirrors _G.BigEvents.iceage) + manual console trigger.
_G.BigEvents = _G.BigEvents or {}
_G.BigEvents.monsoon = { start = startEvent, isRunning = function() return eventRunning end }
_G.startMonsoon = startEvent

-- "/monsoon" chat command (client half in MonsoonCommand.client.luau).
MonsoonTrigger.OnServerEvent:Connect(function(player)
	print(("[Monsoon] /monsoon triggered by %s"):format(player.Name))
	startEvent()
end)

print("[Monsoon] ready -- type '/monsoon' in chat to start the Monsoon Rain event.")
