--======================================================================
-- Windstorm.server.luau  (Server Script)  -- driver for the WINDSTORM event
--======================================================================
-- Schedules the windstorm and broadcasts it on WindstormSync, so every player in the
-- server gets the same storm at the same time. The presentation and the actual shove
-- both live on the client (Windstorm.client.luau + BottomHUD's flight loop) -- exactly
-- the split Monsoon.server / MonsoonRain.client already use here.
--
-- WHY THE SERVER DRIVES IT AT ALL. The first realm ran windstorms purely client-side out
-- of EventClient. That is fine for a solo demo and wrong for a live server: two players
-- on the same island would be blown in different directions by different storms. The
-- direction itself is still rolled per-client (it wanders, and nobody can tell the
-- difference) -- only the START and STOP are authoritative here.
--
-- Sends (phase, payload) to match MonsoonSync's shape:
--     "start"  { duration = <seconds> }
--     "reset"  (no payload)
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	ENABLED        = false,  -- OWN TIMER OFF: the first realm's mini-event rotation (ServerEvents.server) starts it now
	DURATION       = 20,     -- first realm's windstorm length
	INTERVAL_MIN   = 240,    -- 4 minutes between storms, at the earliest
	INTERVAL_MAX   = 480,    -- 8 at the latest
	FIRST_DELAY_MIN = 120,   -- never on the first minute of a fresh server -- a new
	FIRST_DELAY_MAX = 240,   -- player getting blown off island 1 reads as a bug
	MIN_PLAYERS    = 1,
}

-- The sync RemoteEvent. Created here if missing, the same way MonsoonSync is, so the
-- event works whether or not it was added to default.project.json.
local WindstormSync = ReplicatedStorage:FindFirstChild("WindstormSync")
if not WindstormSync then
	WindstormSync = Instance.new("RemoteEvent")
	WindstormSync.Name = "WindstormSync"
	WindstormSync.Parent = ReplicatedStorage
end

local running = false

local function broadcast(phase, payload)
	WindstormSync:FireAllClients(phase, payload)
end

local currentDuration = CONFIG.DURATION

local function runWindstorm(duration)
	if running then return end
	running = true
	currentDuration = tonumber(duration) or CONFIG.DURATION
	broadcast("start", { duration = currentDuration })
	print(("[Windstorm] started (%ds)"):format(currentDuration))

	task.delay(currentDuration, function()
		broadcast("reset")
		running = false
		print("[Windstorm] ended")
	end)
end

-- THE MINI-EVENT ROTATION STARTS IT NOW. The first realm's WIND STORM is one row of its PlayerStats event
-- pool, on the same 240s clock as the others -- so ServerEvents.server.luau calls this, and the timer below is
-- switched off (AUTO_SCHEDULE) so the storm is not ALSO rolling on a clock of its own.
_G.startWindstorm = runWindstorm
_G.windstormRunning = function() return running end

-- A player joining mid-storm would otherwise fly in dead calm while everyone else is
-- being blown sideways. Hand them the remainder rather than nothing.
Players.PlayerAdded:Connect(function(plr)
	if running then
		task.wait(2) -- let their client scripts come up first
		if running then WindstormSync:FireClient(plr, "start", { duration = CONFIG.DURATION }) end
	end
end)

task.spawn(function()
	if not CONFIG.ENABLED then return end
	task.wait(math.random(CONFIG.FIRST_DELAY_MIN, CONFIG.FIRST_DELAY_MAX))
	while true do
		if #Players:GetPlayers() >= CONFIG.MIN_PLAYERS then
			runWindstorm()
			task.wait(CONFIG.DURATION + 5)
		end
		task.wait(math.random(CONFIG.INTERVAL_MIN, CONFIG.INTERVAL_MAX))
	end
end)

-- Dev trigger, matching the /done and /2x chat commands already in this project.
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		if msg:lower():gsub("%s", "") == "/windstorm" then
			print("[Windstorm] /windstorm by " .. plr.Name)
			runWindstorm()
		end
	end)
end)

print("[Windstorm] service online (every " .. CONFIG.INTERVAL_MIN .. "-" .. CONFIG.INTERVAL_MAX .. "s; /windstorm to force)")
