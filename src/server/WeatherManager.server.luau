--======================================================================
-- WeatherManager.server.lua  (Script)
--======================================================================
-- Orchestrates the global "IceAge" spectacle event.
--
-- A creeping global freeze sweeps the whole map: the sky turns pale
-- blue/gray, snow clouds roll in, a heavy snowstorm covers everything,
-- islands gradually gain (VISUAL-ONLY) snow/ice cover, icicles hang under
-- floating islands, giant frozen meteors occasionally fall, and blizzard
-- gusts sweep across. Rare variants (frozen lightning, a giant snowball,
-- an ice dragon overhead, northern lights, and an "Absolute Zero" crystal
-- mode) add flavour. Then everything melts away and the world restores.
--
-- DESIGN / SAFETY (mirrors the Rocket / Meteor / UFO events' contract):
--   * This is a SPECTACLE + a few GENTLE, CONFIG-gated, server-decided +
--     CLIENT-APPLIED player-physics touch-points ONLY. It NEVER reads or
--     modifies the fart meter, fart power, flight code, food prices, gut
--     stats, island heights, the normal coin earn rate, coins, the falling
--     junk hazard, the planes, or any other event. The ONLY _G access in
--     the whole event is READING `_G.isFlying` on the client to gate the
--     guarded physics.
--   * All sequencing/timing runs on the SERVER. Server-created snow/ice/
--     meteor parts replicate to every client automatically, so the whole
--     server sees the same Ice Age. The IceAgeSync RemoteEvent carries
--     client-side presentation (sky, banners, camera, ambient sound, the
--     capped camera-tracked snow volume) AND the per-client guarded-physics
--     messages (gust nudges + proximity WalkSpeed freezes).
--   * ★ GUARDED PHYSICS ★ Player characters are client-owned, so the server
--     only DECIDES timing + proximity of gusts and meteor-freezes and
--     messages the affected clients; the CLIENT applies them, gated so they
--     ONLY happen when grounded + not flying (slide/wind) or touch ONLY
--     WalkSpeed (freeze). They can NEVER shove a player off a fart-flight /
--     climb, and nothing flight/power/coin-related is ever touched. See
--     IcePhysics.lua + IceAgeUI.client.lua for the full contract.
--   * Everything is capped (MAX_ICE_METEORS, MAX_PARTICLE_RATE, snow/ice
--     part caps) and fully cleaned up on reset (no leaks).
--======================================================================

--======================================================================
-- CONFIG  -- EDIT ANYTHING HERE. Every value is tunable; the gameplay-
-- adjacent (guarded-physics) values are deliberately GENTLE and can be
-- zeroed to disable a feature without breaking the spectacle.
--======================================================================
local CONFIG = {
	-- ---------------- TIMINGS (seconds) ----------------
	EVENT_INTERVAL    = 1500, -- seconds between auto-runs of the Ice Age (25 min)
	WARNING_DURATION  = 20,   -- WARNING phase: light snow, frost creeps in, wind builds
	MAIN_DURATION     = 75,   -- MAIN phase: the full freezing storm (meteors + gusts here)
	ENDING_DURATION   = 12,   -- ENDING phase: snow weakens, ice melts, sky restores

	-- Ice meteor spawn cadence during MAIN (random in this range).
	METEOR_INTERVAL_MIN = 7,  -- min seconds between ice meteors
	METEOR_INTERVAL_MAX = 14, -- max seconds between ice meteors

	-- Blizzard wind-gust cadence during MAIN (random in this range).
	GUST_INTERVAL_MIN = 8,    -- min seconds between strong sweeping gusts
	GUST_INTERVAL_MAX = 16,   -- max seconds between strong sweeping gusts

	-- Short snow-intensity "spike" cadence during MAIN (random in this range).
	SNOW_SPIKE_INTERVAL_MIN = 12, -- min seconds between heavy snow bursts
	SNOW_SPIKE_INTERVAL_MAX = 22, -- max seconds between heavy snow bursts
	SNOW_SPIKE_DURATION     = 4,  -- how long a heavy snow burst lasts

	-- ---------------- STORM INTENSITY / SNOW ----------------
	-- Snow density (a 0..1 phase value the client maps onto its CAPPED snow
	-- emitter rate). The client multiplies by MAX_PARTICLE_RATE + the low-end
	-- quality scalar, so these never blow past the hard cap.
	SNOW_DENSITY_WARNING = 0.30, -- light snow during WARNING
	SNOW_DENSITY_MAIN    = 1.00, -- heavy snow during MAIN
	SNOW_DENSITY_SPIKE   = 1.00, -- (same as main; spikes just hold it high)
	SNOW_DENSITY_ENDING  = 0.20, -- fading snow during ENDING

	-- Icy fog visibility drop per phase (client tweens Lighting.FogEnd toward
	-- this; SMALL drop only -- the world must stay readable + navigable).
	FOG_END_WARNING = 2200, -- mild haze
	FOG_END_MAIN    = 1400, -- thicker icy fog (still very playable)
	FOG_END_ENDING  = 3500, -- clearing

	-- Particle / part caps (PERFORMANCE is the #1 risk with heavy snow).
	MAX_PARTICLE_RATE = 26, -- HARD cap on EVERY ParticleEmitter Rate (server + client)
	MAX_SNOW_EMITTERS = 6,  -- HARD cap on the client's camera-tracked snow emitters
	MAX_ICE_PARTS     = 320,-- HARD cap on simultaneous world snow/ice/icicle parts (IceVFX)

	-- Low-end quality: clients may flip this to scale snow density DOWN. The
	-- manager broadcasts it as a default; the client also exposes a local
	-- toggle. 1.0 = full, lower = lighter snow on weaker devices.
	LOW_END_DEFAULT_SCALAR = 1.0,  -- broadcast default snow scalar (1.0 = full quality)

	-- ---------------- ★ GUARDED PHYSICS ★ (gentle defaults, all zeroable) --
	-- Slight ground slipperiness. Applied CLIENT-SIDE, ONLY when the player is
	-- GROUNDED and `_G.isFlying ~= true`. A SMALL friction reduction / gentle
	-- carry on movement. MUST be small -- never enough to slide a player off an
	-- island. 0 disables. (Lua CustomPhysicalProperties friction floor we tween
	-- toward; lower = slightly more slide.)
	ICE_SLIDE_AMOUNT = 0.18,  -- 0..1 "slipperiness" (0 = normal grip, 1 = max slide). Small!

	-- Gentle sideways nudge during a gust. Applied CLIENT-SIDE, ONLY when
	-- GROUNDED and not flying. A small horizontal velocity bump in the gust
	-- direction. MUST be small. 0 disables. (studs/sec added briefly.)
	WIND_PUSH_FORCE = 8,      -- studs/sec gentle horizontal nudge per gust (small!)
	GUST_PUSH_DURATION = 0.8, -- seconds the gentle nudge is applied (then it decays)

	-- ICE METEOR proximity freeze: MOVEMENT-ONLY. Briefly reduces the
	-- Humanoid's WalkSpeed, then restores the captured original. It NEVER
	-- touches the fart meter / power / flight / gas / coins and NEVER cancels a
	-- climb. A frozen player keeps FULL fart power and can still fart-fly.
	FREEZE_DURATION   = 2.5,  -- brief seconds the WalkSpeed reduction lasts
	FREEZE_WALKSPEED  = 6,    -- the reduced WalkSpeed during a freeze (default run is 16)
	FREEZE_RADIUS     = 26,   -- studs from an ice-meteor impact a player gets the slow

	-- ---------------- ICE METEORS ----------------
	MAX_ICE_METEORS   = 4,    -- HARD cap on simultaneous falling ice meteors (perf)
	METEOR_SPAWN_HEIGHT = 850,-- studs above the target an ice meteor starts at
	METEOR_SIZE_MIN   = 6,    -- min ice-meteor radius (studs)
	METEOR_SIZE_MAX   = 12,   -- max ice-meteor radius (studs)
	METEOR_FALL_TIME_MIN = 2.4, -- min seconds an ice meteor takes to fall
	METEOR_FALL_TIME_MAX = 3.8, -- max seconds an ice meteor takes to fall
	FREEZE_SHOCKWAVE_RADIUS = 30, -- studs the visual freezing shockwave expands to
	METEOR_DEBRIS_LIFETIME = 12,  -- seconds frozen scorch/spikes/debris linger then fade

	-- ---------------- RARE VARIANT CHANCES (rolled where noted) ----------------
	FROZEN_LIGHTNING_CHANCE = 0.10, -- chance (per MAIN tick window) of a frozen lightning storm
	SNOWBALL_CHANCE         = 0.08, -- chance of a giant snowball rolling between islands
	ICE_DRAGON_CHANCE       = 0.06, -- chance of an ice dragon flying overhead
	NORTHERN_LIGHTS_CHANCE  = 0.12, -- chance of aurora / northern lights in the sky
	ABSOLUTE_ZERO_CHANCE    = 0.02, -- VERY small: whole-event crystal-blue "Absolute Zero" mode

	-- ---------------- TARGETING ----------------
	-- Fallback island top-surface positions (X,Y,Z) if a model can't be found
	-- or a raycast fails. Sourced from the game's ISLAND_POSITIONS (top surfaces
	-- are found by raycast at runtime; these are safe defaults).
	FALLBACK_TARGETS = {
		Vector3.new(0, 150, 0), Vector3.new(120, 1620, 60), Vector3.new(-160, 3090, 100),
		Vector3.new(180, 4930, -120), Vector3.new(-200, 6770, 160), Vector3.new(220, 9420, -180),
		Vector3.new(-240, 12070, 200), Vector3.new(260, 15610, -220), Vector3.new(-280, 19150, 240),
		Vector3.new(300, 23570, -260), Vector3.new(-320, 27990, 280), Vector3.new(340, 33710, -300),
		Vector3.new(-360, 39430, 320),
	},
}

--======================================================================
-- Services + module requires.
--======================================================================
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sibling ModuleScripts (this script + the modules all live in the same
-- DinosaurRealmServer folder), so require them as SIBLINGS, not off SSS root.
local here = script.Parent
local IcePhysics = require(here:WaitForChild("IcePhysics"))
local Blizzard   = require(here:WaitForChild("Blizzard"))
local IceMeteor  = require(here:WaitForChild("IceMeteor"))
local IceVFX     = require(here:WaitForChild("IceVFX"))

-- The sync RemoteEvent. The original game created it via default.project.json;
-- here we create it at runtime (the client IceAgeUI + IceAgeCommand WaitForChild it).
local IceAgeSync = ReplicatedStorage:FindFirstChild("IceAgeSync")
if not IceAgeSync then
	IceAgeSync = Instance.new("RemoteEvent")
	IceAgeSync.Name = "IceAgeSync"
	IceAgeSync.Parent = ReplicatedStorage
end
-- [LATE-JOIN] Record the last LIFECYCLE phase + payload into _G.BigEvents.iceage so LateJoinEventSync
-- can replay the EXACT current visuals (sky variant + the current snow-density phase) to a late-joiner.
-- The FireAllClients inside is IDENTICAL to the direct call -- this ONLY also stashes phase/payload
-- (purely additive). Transient effects (gust/aurora/meteorImpact/etc.) keep firing directly.
local function icePhase(phase, payload)
	IceAgeSync:FireAllClients(phase, payload)
	local e = _G.BigEvents and _G.BigEvents.iceage
	if e then
		e.currentPhase, e.currentPayload = phase, payload
		if phase == "start" then e.startPayload = payload end
	end
end

-- Wire the modules together (CONFIG is owned here; pass it down).
IcePhysics.init(CONFIG, IceAgeSync)            -- decides gusts + freeze proximity, messages clients
IceMeteor.init(CONFIG, IceAgeSync, IcePhysics) -- falling meteors; on impact -> IcePhysics freeze
Blizzard.init(CONFIG, IceAgeSync, IcePhysics)  -- gusts + snow spikes (uses IcePhysics for gust pushes)
IceVFX.init(CONFIG, IceAgeSync)                -- world snow/ice cover + rare variants

--======================================================================
-- State.
--======================================================================
local eventRunning = false -- guard so we never run two Ice Ages at once

--======================================================================
-- TARGETING: resolve island top-surface positions.
-- Scan Workspace for the island models (named "Island_<n>_..."), take a
-- model's horizontal center, and RAYCAST DOWN to its top surface so snow
-- caps, icicles, and meteor impacts line up with island GROUND. Fall back
-- to CONFIG.FALLBACK_TARGETS.
--======================================================================

-- snapToGround: raycast straight down at (x,z) to find the top surface Y.
-- Excludes players + the Farmer + our own event folders so we never raycast
-- onto a player, an NPC, or a prior ice prop.
local function snapToGround(x, z, fromY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then table.insert(exclude, tut) end
	-- Exclude our own event folders so we never raycast onto our own ice.
	for _, name in ipairs({ "IceAgeVFX", "IceAgeMeteors", "IceAgeMeteorDebris" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(exclude, f) end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -8000, 0), params)
	return hit and hit.Position.Y or nil
end

-- detectIslandSurface(model): find the island's WALKABLE GROUND plane + its
-- horizontal extent, for a single SNOW CIRCLE. We do NOT inspect part shapes
-- (that picked roofs/props). Instead we cast a GRID of downward rays over the
-- island and find the DOMINANT (most-hit) height band -- that is the big flat
-- walking surface (the grass), whether it's a Part or Terrain. Roofs/props are
-- a higher minority band, the base is a lower minority band, so neither wins.
-- Rays hit the TOP thing first, so the base under the grass is never measured.
-- Returns { topY (surface), cx, cz (center of that surface), extentX, extentZ,
-- bboxY } or nil.
local function detectIslandSurface(model)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok or not cf or not size then return nil end

	-- Rays may hit ANYTHING except players, the tutorial NPCs, and our own ice
	-- folders -- so a Terrain grass top is detected too (a model-only whitelist
	-- was why the grass was missed before).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excl = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then excl[#excl + 1] = plr.Character end
	end
	local tut = workspace:FindFirstChild("TutorialNPCs")
	if tut then excl[#excl + 1] = tut end
	for _, n in ipairs({ "IceAgeVFX", "IceAgeMeteors", "IceAgeMeteorDebris" }) do
		local f = workspace:FindFirstChild(n)
		if f then excl[#excl + 1] = f end
	end
	params.FilterDescendantsInstances = excl
	params.IgnoreWater = true

	local cx, cz = cf.Position.X, cf.Position.Z
	local searchHalf = math.max(size.X, size.Z) * 0.5 + 10
	local startY = cf.Position.Y + size.Y / 2 + 30
	local rayLen = size.Y + 200

	local GRID = 13
	local hits = {}
	for ix = 0, GRID - 1 do
		for iz = 0, GRID - 1 do
			local x = cx + (ix / (GRID - 1) - 0.5) * 2 * searchHalf
			local z = cz + (iz / (GRID - 1) - 0.5) * 2 * searchHalf
			local hit = workspace:Raycast(Vector3.new(x, startY, z), Vector3.new(0, -rayLen, 0), params)
			if hit then hits[#hits + 1] = { x = x, z = z, y = hit.Position.Y } end
		end
	end
	if #hits == 0 then return nil end

	-- Dominant (most-populated) height band = the grass walking surface.
	local BIN = 4
	local bins, bestBin, bestCount = {}, nil, 0
	for _, h in ipairs(hits) do
		local b = math.floor(h.y / BIN)
		local rec = bins[b] or { count = 0, sumY = 0 }
		rec.count = rec.count + 1
		rec.sumY = rec.sumY + h.y
		bins[b] = rec
		if rec.count > bestCount then bestCount = rec.count; bestBin = b end
	end
	local bandY = bins[bestBin].sumY / bins[bestBin].count

	-- Footprint = X/Z extent of just the hits ON that surface band.
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, h in ipairs(hits) do
		if math.abs(h.y - bandY) <= BIN * 1.5 then
			if h.x < minX then minX = h.x end
			if h.x > maxX then maxX = h.x end
			if h.z < minZ then minZ = h.z end
			if h.z > maxZ then maxZ = h.z end
		end
	end
	if minX > maxX then return nil end

	return {
		topY    = bandY,                        -- walkable surface (snow sits here)
		cx      = (minX + maxX) / 2,
		cz      = (minZ + maxZ) / 2,
		extentX = math.max(maxX - minX, 8),
		extentZ = math.max(maxZ - minZ, 8),
		bboxY   = size.Y,
	}
end

-- getIslandTargets: gather one descriptor per island present in the
-- Workspace. Returns a list of { index, position (top surface), size, model }.
-- IceVFX uses size to scale snow caps; IceMeteor uses position for impacts.
local function getIslandTargets()
	local targets = {}
	for i = 1, 13 do
		local found = false
		-- This game names its islands "island1" .. "island13" (single model each),
		-- so look the model up directly. Wrapping the (possibly nil) result in a
		-- table keeps the original loop/`break` structure below intact.
		for _, child in ipairs({ workspace:FindFirstChild("island" .. i) }) do
			if child:IsA("Model") then
				if true then
					-- Per-island walking-surface detection -> one snow CIRCLE sized a
					-- bit bigger than the grass footprint (slight overhang wanted).
					local surf = detectIslandSurface(child)
					if surf then
						-- Diameter = 1.1x the LARGER surface dimension, so the disc
						-- fully covers the ground with a small overhang past the edges.
						local diameter = math.max(surf.extentX, surf.extentZ) * 1.1
						table.insert(targets, {
							index = i,
							-- Centered on the surface, AT the surface Y (disc sits flush).
							position = Vector3.new(surf.cx, surf.topY, surf.cz),
							-- X/Z = the circle DIAMETER; Y = model height (for icicles).
							size = Vector3.new(diameter, surf.bboxY, diameter),
							model = child,
						})
						found = true
						-- Per-island report: surface footprint + chosen circle diameter.
						print(string.format(
							"ICEAGE SNOW: island %d | surface=%.0f x %.0f | circle diameter=%.0f (1.10x) | surfaceY=%.1f",
							i, surf.extentX, surf.extentZ, diameter, surf.topY))
					else
						-- Fallback: bounding box -> circle from its larger horizontal dim.
						local ok, cf, size = pcall(function() return child:GetBoundingBox() end)
						if ok and cf and size then
							local cx, cz = cf.Position.X, cf.Position.Z
							local topY = cf.Position.Y + size.Y / 2
							local gy = snapToGround(cx, cz, topY + 20)
							local diameter = math.max(size.X, size.Z) * 1.1
							table.insert(targets, {
								index = i,
								position = Vector3.new(cx, gy or topY, cz),
								size = Vector3.new(diameter, size.Y, diameter),
								model = child,
							})
							found = true
							print(string.format(
								"ICEAGE SNOW: island %d | FALLBACK bbox | circle diameter=%.0f | surfaceY=%.1f",
								i, diameter, gy or topY))
						end
					end
					break
				end
			end
		end
		-- If the model was missing, use the configured fallback for this island.
		if not found and CONFIG.FALLBACK_TARGETS[i] then
			local fb = CONFIG.FALLBACK_TARGETS[i]
			local gy = snapToGround(fb.X, fb.Z, fb.Y + 200)
			table.insert(targets, {
				index = i,
				position = Vector3.new(fb.X, gy or fb.Y, fb.Z),
				size = Vector3.new(154, 40, 154), -- safe default circle diameter (~140 x 1.1)
				model = nil,
			})
			print(string.format(
				"ICEAGE SNOW: island %d | MODEL MISSING -> fallback | circle diameter=154 | surfaceY=%.1f",
				i, gy or fb.Y))
		end
	end
	-- Absolute fallback so the event always has somewhere to be.
	if #targets == 0 then
		for i, fb in ipairs(CONFIG.FALLBACK_TARGETS) do
			table.insert(targets, { index = i, position = fb, size = Vector3.new(140, 40, 140) })
		end
	end
	return targets
end

-- pickEventVariant: roll the once-per-event "Absolute Zero" crystal mode.
-- Other variants (lightning / snowball / dragon / aurora) are rolled
-- repeatedly during MAIN so several can occur; Absolute Zero recolors the
-- whole event so it is a single up-front roll.
local function pickEventVariant()
	if math.random() < CONFIG.ABSOLUTE_ZERO_CHANCE then
		return "absoluteZero"
	end
	return "normal"
end

--======================================================================
-- Full event sequence. Returns when the whole thing is done + cleaned.
--======================================================================
local function runEvent()
	if eventRunning then return end
	eventRunning = true

	-- Roll the whole-event variant once.
	local variant = pickEventVariant()

	-- Wrap in pcall so a failure still cleans up + clears the guard.
	local ok, err = pcall(function()
		local targets = getIslandTargets()

		-- ---- 1) START ----
		-- Sky slowly turns pale blue/gray, snow clouds roll across, cold wind.
		icePhase("start", {
			text = "\u{1F9CA} ICE AGE APPROACHING!",
			variant = variant,
			lowEndScalar = CONFIG.LOW_END_DEFAULT_SCALAR,
			slideAmount = CONFIG.ICE_SLIDE_AMOUNT, -- client applies this gentle slide (0 disables)
		})

		-- ---- 2) WARNING (~WARNING_DURATION) ----
		-- Light snow begins, wind intensifies, frost creeps over island
		-- surfaces, distant ice-cracking, small ice particles drift.
		icePhase("warning", { variant = variant })
		IceVFX.startFrost(targets, variant) -- thin frost creeps over island tops
		task.wait(CONFIG.WARNING_DURATION)

		-- ---- 3) MAIN: the full freezing storm ----
		icePhase("main", { variant = variant })

		-- ---- 4) WORLD EFFECTS: islands gain snow/ice cover, icicles, props ----
		IceVFX.startWorldFreeze(targets, variant) -- snow caps, icicles, frozen props (VISUAL ONLY)

		-- ---- 5 + 6) Meteors + blizzard phases run on their own loops during MAIN.
		IceMeteor.start(targets, variant)  -- spawns ice meteors on its own cadence
		Blizzard.start(targets, variant)   -- gusts + snow spikes on their own cadence

		-- During MAIN, occasionally roll the repeatable rare variants. IceVFX
		-- caps how many run at once + cleans them up.
		local mainDeadline = os.clock() + CONFIG.MAIN_DURATION
		while os.clock() < mainDeadline do
			if math.random() < CONFIG.NORTHERN_LIGHTS_CHANCE then
				IceAgeSync:FireAllClients("aurora") -- client paints northern lights
			end
			if math.random() < CONFIG.FROZEN_LIGHTNING_CHANCE then
				IceVFX.frozenLightning(targets) -- frozen lightning storm strike
			end
			if math.random() < CONFIG.SNOWBALL_CHANCE then
				IceVFX.giantSnowball(targets)   -- giant snowball rolls between islands
			end
			if math.random() < CONFIG.ICE_DRAGON_CHANCE then
				IceVFX.iceDragon(targets)       -- ice dragon flies overhead
			end
			task.wait(6)
		end

		-- Stop the spawners (they release their internal loops + caps).
		IceMeteor.stop()
		Blizzard.stop()

		-- ---- 7) ENDING (ENDING_DURATION): snow weakens, ice melts, sky clears.
		icePhase("ending", { text = "\u{1F9CA} Ice Age Ending\u{2026}", variant = variant })
		IceVFX.startMelt() -- begin fading all world ice/snow gradually
		task.wait(CONFIG.ENDING_DURATION)
	end)

	if not ok then
		warn("[IceAge] event errored: " .. tostring(err))
	end

	-- ---- RESET: restore everyone + destroy everything, no leftovers ----
	-- Client restores Lighting/sky, removes its snow volume, and clears ALL
	-- guarded-physics (friction/WalkSpeed/forces back to normal).
	IceAgeSync:FireAllClients("reset")
	IceMeteor.stop()
	Blizzard.stop()
	IcePhysics.cleanup() -- clears any pending server-side gust/freeze scheduling
	IceMeteor.cleanup()  -- destroy all meteors + frozen debris
	IceVFX.cleanup()     -- destroy all snow/ice cover + restore any modified prop textures
	eventRunning = false
end

--------------------------------------------------------------------
-- Public starter (used by the interval timer + test triggers).
--------------------------------------------------------------------
local function startEvent()
	if eventRunning then
		warn("[IceAge] start ignored: an Ice Age is already running.")
		return
	end
	task.spawn(runEvent)
end

--======================================================================
-- Main interval timer loop.
--======================================================================
-- BIG-EVENT SCHEDULER: this event's own interval timer is DISABLED. The single
-- BigEventScheduler now drives all five big events (one at a time, every 7 min,
-- never the same twice in a row). We just register start + running-state.
_G.BigEvents = _G.BigEvents or {}
_G.BigEvents.iceage = { start = startEvent, isRunning = function() return eventRunning end }

--======================================================================
-- "/iceage" chat command trigger.
--======================================================================
-- The client half (IceAgeCommand.client.luau) parses "/iceage" from chat and
-- fires this RemoteEvent; here we start the event on demand. There is no
-- BigEventScheduler in this game, so this (or a manual _G call) is how the
-- Ice Age runs.
local trigger = ReplicatedStorage:FindFirstChild("IceAgeTrigger")
if not trigger then
	trigger = Instance.new("RemoteEvent")
	trigger.Name = "IceAgeTrigger"
	trigger.Parent = ReplicatedStorage
end

trigger.OnServerEvent:Connect(function(player)
	print(("[IceAge] /iceage triggered by %s"):format(player.Name))
	startEvent()
end)

-- Also expose a manual server-console trigger.
_G.startIceAge = startEvent

print("[IceAge] ready -- type '/iceage' in chat to start the Ice Age event.")
