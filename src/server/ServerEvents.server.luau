--======================================================================
-- ServerEvents.server.luau  (Server Script)  -- the server-wide MINI event loop
--======================================================================
-- PORTED FROM THE FIRST REALM: PlayerStats.server.lua's eventPool + "SERVER-WIDE EVENT LOOP", and
-- EventClient.client.lua's handlers (the client half lives in ServerEvents.client.luau). What changed is the
-- plumbing (a Sync RemoteEvent, matching how Monsoon/Ice Age/Windstorm are wired HERE) and three multipliers
-- retuned for this realm's flight economy -- called out in the client.
--
-- ===== THE FIRST REALM'S TIMER AND POOL, NOW EXACT =====
--   * 240s before the first event, then 240s after each one ENDS (first realm: task.wait(240) on both ends).
--   * The pick is a flat random over the pool -- the first realm ships a weight column and then picks with
--     math.random over the list, so its weights never did anything. Same here.
--   * Durations are the first realm's: FART_STORM 7, COIN_RUSH 7, HIGH GRAVITY 10, POWER_SURGE 8,
--     RING FEVER 30, THUNDERSTORM 40, WIND STORM 20.
--   * The event ends dur + 2 later (the first realm's beat, so the last countdown frame lands).
--   * THE 20-SECOND HEADS-UP for the three events that work AGAINST the player (THUNDERSTORM, WIND STORM,
--     HIGH GRAVITY): warn, wait 20s, THEN fire -- landing before it starts is the whole point. Buffs arrive
--     unannounced, as a pleasant surprise.
--
-- WIND STORM IS IN THE POOL NOW, like the first realm. Its presentation and shove still live in
-- Windstorm.server / Windstorm.client (its own remote, its own banner): this loop just starts it through
-- _G.startWindstorm, and Windstorm.server no longer runs a timer of its own.
--
-- The BIG events (Monsoon, Ice Age) run on BigEventScheduler.server.luau's 7-minute clock, independently,
-- exactly as the first realm splits the two tiers.
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	ENABLED       = true,
	FIRST_DELAY   = 240,   -- the first realm's: 4 minutes before the first event
	INTERVAL      = 240,   -- ...and 4 minutes after each one ends
	WARN_SECONDS  = 20,    -- heads-up before a hazard
	MIN_PLAYERS   = 1,
}

-- The hazards that get the heads-up (see header).
local WARNED = { THUNDERSTORM = true, WINDSTORM = true, LOW_GRAVITY = true }

-- name | display | weight | duration | message   (the first realm's rows)
local EVENT_POOL = {
	{ name = "FART_STORM",   disp = "\xF0\x9F\x92\xA8 FART STORM",   weight = 15, dur = 7,
	  msg = "\xF0\x9F\x92\xA8 FART STORM! Everyone flies faster!",        color = {100, 200, 255} },

	{ name = "COIN_RUSH",    disp = "\xF0\x9F\x92\xB0 COIN RUSH",    weight = 15, dur = 7,
	  msg = "\xF0\x9F\x92\xB0 COIN RUSH! Double coins!",                  color = {255, 200,   0} },

	-- Shown as HIGH GRAVITY, keyed LOW_GRAVITY -- the first realm's own display-only rename.
	{ name = "LOW_GRAVITY",  disp = "\xF0\x9F\x8C\x99 HIGH GRAVITY", weight = 15, dur = 10,
	  msg = "\xF0\x9F\x8C\x99 HIGH GRAVITY! Float like a cloud!",         color = {150, 100, 255} },

	{ name = "POWER_SURGE",  disp = "\xE2\x9A\xA1 POWER SURGE",      weight = 15, dur = 8,
	  msg = "\xE2\x9A\xA1 POWER SURGE! Fly higher than ever!",            color = {255, 255,   0} },

	{ name = "RING_FEVER",   disp = "\xF0\x9F\x8E\xAF BUBBLE FEVER", weight = 15, dur = 30,
	  msg = "\xF0\x9F\x8E\xAF BUBBLE FEVER! Bubbles are worth a fortune!", color = {255, 100, 200} },

	{ name = "THUNDERSTORM", disp = "\xE2\x9B\x88 THUNDERSTORM",     weight = 15, dur = 40,
	  msg = "\xE2\x9B\x88 THUNDERSTORM! Hard to see!",                    color = { 50,  50,  80} },

	-- Started through Windstorm.server (its own remote + banner); see header.
	{ name = "WINDSTORM",    disp = "\xF0\x9F\x92\xA8 WIND STORM",   weight = 10, dur = 20,
	  msg = "\xF0\x9F\x92\xA8 WIND STORM! Fighting the wind!",            color = {100, 150, 200}, external = true },
}

local Sync = ReplicatedStorage:FindFirstChild("ServerEventSync")
if not Sync then
	Sync = Instance.new("RemoteEvent")
	Sync.Name = "ServerEventSync"
	Sync.Parent = ReplicatedStorage
end

local running = nil   -- the active event's row, or nil
local warning = false -- a heads-up is counting down

local function pickEvent()
	return EVENT_POOL[math.random(1, #EVENT_POOL)] -- flat, like the first realm (see header)
end

local function payloadFor(e)
	return { name = e.name, disp = e.disp, duration = e.dur, msg = e.msg, color = e.color }
end

-- Heads-up for a hazard, then wait it out. Returns at once for a buff.
local function warnBefore(e)
	if not WARNED[e.name] then return end
	warning = true
	print(("[ServerEvents] %s in %ds -- warning players"):format(e.name, CONFIG.WARN_SECONDS))
	Sync:FireAllClients("warn", { name = e.name, disp = e.disp, seconds = CONFIG.WARN_SECONDS, color = e.color })
	task.wait(CONFIG.WARN_SECONDS)
	warning = false
end

local function runEvent(e)
	if running then return end
	running = e
	workspace:SetAttribute("ActiveServerEvent", e.name)
	workspace:SetAttribute("ActiveServerEventName", e.disp)
	workspace:SetAttribute("ActiveServerEventEndsAt", os.time() + e.dur)

	if e.external then
		-- WIND STORM: Windstorm.server owns the start/stop broadcast and the banner.
		if _G.startWindstorm then pcall(_G.startWindstorm, e.dur) end
	else
		Sync:FireAllClients("start", payloadFor(e))
	end
	print(("[ServerEvents] %s for %ds"):format(e.name, e.dur))

	task.delay(e.dur + 2, function()   -- the first realm's dur + 2 beat
		if not e.external then Sync:FireAllClients("reset") end
		workspace:SetAttribute("ActiveServerEvent", nil)
		workspace:SetAttribute("ActiveServerEventName", nil)
		workspace:SetAttribute("ActiveServerEventEndsAt", nil)
		running = nil
		print(("[ServerEvents] %s ended"):format(e.name))
	end)
end

-- Someone joining mid-event gets the rest of it, rather than standing in a server where everyone else is
-- buffed and they are not. (Windstorm.server hands over its own storm.)
Players.PlayerAdded:Connect(function(plr)
	if running and not running.external then
		task.wait(2) -- let their client scripts come up
		if running and not running.external then Sync:FireClient(plr, "start", payloadFor(running)) end
	end
end)

task.spawn(function()
	if not CONFIG.ENABLED then return end
	task.wait(CONFIG.FIRST_DELAY)
	while true do
		if #Players:GetPlayers() >= CONFIG.MIN_PLAYERS and not running then
			local e = pickEvent()
			warnBefore(e)          -- hazards only; returns instantly for a buff
			runEvent(e)
			task.wait(e.dur + 2)
			while running do task.wait(0.5) end
		end
		task.wait(CONFIG.INTERVAL)
	end
end)

-- Dev triggers. "/event" rolls a random one; "/event coin_rush" forces a specific one (no heads-up, so a
-- test does not wait 20s); "/eventwarn" shows the heads-up banner on its own.
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		local m = msg:lower()
		if m:gsub("%s", "") == "/eventwarn" then
			local e = EVENT_POOL[6]
			Sync:FireAllClients("warn", { name = e.name, disp = e.disp, seconds = CONFIG.WARN_SECONDS, color = e.color })
			return
		end
		if m:sub(1, 6) ~= "/event" then return end
		local want = m:sub(7):gsub("%s", ""):upper()
		if want == "" then
			runEvent(pickEvent())
		else
			for _, e in ipairs(EVENT_POOL) do
				if e.name == want then runEvent(e); return end
			end
			warn("[ServerEvents] no such event: " .. want)
		end
	end)
end)

print("[ServerEvents] online -- " .. #EVENT_POOL .. " mini events (first realm's pool), first at "
	.. CONFIG.FIRST_DELAY .. "s then every " .. CONFIG.INTERVAL .. "s after each ends, 20s heads-up on hazards"
	.. "  (/event, /event <name>, /eventwarn)")
