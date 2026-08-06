--======================================================================
-- Blizzard.lua  (ModuleScript)
--======================================================================
-- Blizzard phases for the global "IceAge" event (SERVER-authoritative).
--
-- This module owns two periodic, self-contained loops that run during the
-- event's MAIN phase:
--   * STRONG WIND GUSTS that sweep across the map: it picks a random
--     horizontal direction, tells every client to lean its snow + play a
--     gust sound (IceAgeSync "gustVisual"), and asks IcePhysics to deliver
--     the GENTLE, CLIENT-APPLIED sideways nudge (grounded + not-flying only).
--   * SHORT SNOW-INTENSITY SPIKES: it tells clients to briefly ramp their
--     CAPPED snow emitter rate up to the spike density, then back down.
--
-- It creates NO Workspace parts of its own (the snow volume lives on each
-- client's camera; the gust push lives on each affected client). It holds
-- only loop-control state, fully released on stop().
--
-- SAFETY: the only player-facing effect is the gentle gust nudge, which is
-- delegated to IcePhysics -> client and is grounded/not-flying gated there.
-- Nothing here touches fart meter / power / flight / coins.
--======================================================================

local Blizzard = {}

-- Wired by init().
local CONFIG = nil
local IceAgeSync = nil
local IcePhysics = nil

-- Loop-control state.
local running = false
local gustThread = nil
local spikeThread = nil

--------------------------------------------------------------------
-- init(config, syncEvent, icePhysics): wire shared dependencies.
--------------------------------------------------------------------
function Blizzard.init(config, syncEvent, icePhysics)
	CONFIG = config
	IceAgeSync = syncEvent
	IcePhysics = icePhysics
end

--------------------------------------------------------------------
-- randomGustDirection(): a random flat (XZ) unit direction for a gust.
--------------------------------------------------------------------
local function randomGustDirection()
	local ang = math.random() * math.pi * 2
	return Vector3.new(math.cos(ang), 0, math.sin(ang))
end

--------------------------------------------------------------------
-- doGust(): fire one gust -- a sweeping visual lean + sound for everyone,
-- plus the gentle client-applied nudge via IcePhysics.
--------------------------------------------------------------------
local function doGust()
	local dir = randomGustDirection()
	-- Visual lean of the snow + a whoosh, for EVERY client (cosmetic).
	if IceAgeSync then
		IceAgeSync:FireAllClients("gustVisual", { dir = dir })
	end
	-- Gentle physical nudge (grounded + not-flying gated on the client).
	if IcePhysics then
		IcePhysics.broadcastGust(dir)
	end
end

--------------------------------------------------------------------
-- doSnowSpike(): tell clients to briefly ramp snow up to the spike density,
-- hold for SNOW_SPIKE_DURATION, then return to the MAIN density. The client
-- maps density onto its CAPPED emitter rate, so spikes never exceed the cap.
--------------------------------------------------------------------
local function doSnowSpike()
	if not IceAgeSync then return end
	IceAgeSync:FireAllClients("snowSpike", {
		density = CONFIG.SNOW_DENSITY_SPIKE,
		duration = CONFIG.SNOW_SPIKE_DURATION,
	})
end

--------------------------------------------------------------------
-- start(targets, variant): begin the gust + snow-spike loops. They run on
-- their own threads until stop() is called (or the event resets). `targets`
-- and `variant` are accepted for parity/future tuning; gusts are global.
--------------------------------------------------------------------
function Blizzard.start(_targets, _variant)
	if running then return end
	running = true

	-- Gust loop.
	gustThread = task.spawn(function()
		-- A small initial delay so the very first MAIN moment isn't a gust.
		task.wait(CONFIG.GUST_INTERVAL_MIN)
		while running do
			doGust()
			local wait = CONFIG.GUST_INTERVAL_MIN
				+ math.random() * (CONFIG.GUST_INTERVAL_MAX - CONFIG.GUST_INTERVAL_MIN)
			task.wait(wait)
		end
	end)

	-- Snow-spike loop.
	spikeThread = task.spawn(function()
		task.wait(CONFIG.SNOW_SPIKE_INTERVAL_MIN)
		while running do
			doSnowSpike()
			local wait = CONFIG.SNOW_SPIKE_INTERVAL_MIN
				+ math.random() * (CONFIG.SNOW_SPIKE_INTERVAL_MAX - CONFIG.SNOW_SPIKE_INTERVAL_MIN)
			task.wait(wait)
		end
	end)
end

--------------------------------------------------------------------
-- stop(): halt the loops. The `running` flag breaks the while-loops at their
-- next task.wait boundary (no orphaned threads, no leaks). Safe to call more
-- than once.
--------------------------------------------------------------------
function Blizzard.stop()
	running = false
	gustThread = nil
	spikeThread = nil
end

return Blizzard
