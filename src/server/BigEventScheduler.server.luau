--======================================================================
-- BigEventScheduler.server.luau  (Script)  -- PORTED FROM THE FIRST REALM
--======================================================================
-- ONE scheduler for the BIG server-wide events. The first realm's rotation is Rocket + Meteor Storm; this
-- realm's big events are its own -- the MONSOON (thunderstorm) and the ICE AGE -- and the Meteor Storm is
-- deliberately left out (by request: the Dino Realm already has its storm and its ice age).
--
-- Each big-event manager registers itself into
--     _G.BigEvents[key] = { start = <fn>, isRunning = <fn returning bool> }
-- (Monsoon.server.luau and WeatherManager.server.luau already do), and timing is decided ONLY here.
--
-- RULES (the first realm's, unchanged):
--   * Only ONE big event runs at a time.
--   * Every SCHEDULE_INTERVAL (7 minutes) the scheduler randomly picks + starts ONE.
--   * NEVER the same event twice in a row.
--   * If a previous event (scheduled OR a /monsoon, /iceage test) is still active when the timer fires,
--     WAIT for it to end cleanly before starting the next -> no overlap, ever.
--   * The mini events (ServerEvents.server.luau) run independently on their own 240s loop, exactly as the
--     first realm's PlayerStats loop does; this governs ONLY the big ones.
--======================================================================

local SCHEDULE_INTERVAL = 420   -- seconds between big-event picks (7 minutes)
local FIRST_DELAY       = 420   -- wait before the FIRST scheduled big event (a fresh server isn't slammed)
local REGISTER_GRACE    = 10    -- let the big-event managers register into _G.BigEvents on startup
local ORDER = { "monsoon", "iceage" } -- the Dino Realm's big events (no Meteor Storm)

local lastKey = nil   -- the event started last time -> never picked again the very next time

-- True if ANY registered big event is currently running (so we never overlap).
local function anyRunning()
	local reg = _G.BigEvents
	if not reg then return false end
	for _, e in pairs(reg) do
		if e and e.isRunning and e.isRunning() then return true end
	end
	return false
end

-- Pick a registered big-event key that is NOT the one we ran last time.
local function pickNext()
	local reg = _G.BigEvents or {}
	local choices = {}
	for _, key in ipairs(ORDER) do
		if reg[key] and reg[key].start and key ~= lastKey then
			choices[#choices + 1] = key
		end
	end
	-- Only one registered? Allow it again rather than stall the scheduler.
	if #choices == 0 then
		for _, key in ipairs(ORDER) do
			if reg[key] and reg[key].start then choices[#choices + 1] = key end
		end
	end
	if #choices == 0 then return nil end
	return choices[math.random(1, #choices)]
end

task.spawn(function()
	task.wait(REGISTER_GRACE)  -- managers register on startup
	task.wait(FIRST_DELAY)     -- first big event ~7 min in
	while true do
		while anyRunning() do task.wait(1) end

		local key = pickNext()
		if key then
			lastKey = key
			print("[BigEventScheduler] starting big event: " .. key)
			local ok, err = pcall(_G.BigEvents[key].start)
			if not ok then
				warn("[BigEventScheduler] start error for " .. key .. ": " .. tostring(err))
			end
		else
			print("[BigEventScheduler] no big events registered yet -- retrying next cycle")
		end

		-- Roughly when the next one is due, for anything that wants to SHOW it. "Not before", not a promise.
		pcall(function() workspace:SetAttribute("NextBigEventAt", os.time() + SCHEDULE_INTERVAL) end)
		task.wait(SCHEDULE_INTERVAL)
	end
end)

print("[BigEventScheduler] active: one big event (Monsoon / Ice Age) every " .. SCHEDULE_INTERVAL ..
	"s, only one at a time, never the same twice in a row.")
