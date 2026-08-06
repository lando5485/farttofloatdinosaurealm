--======================================================================
-- IceMeteor.lua  (ModuleScript)
--======================================================================
-- Giant frozen meteors for the global "IceAge" event (SERVER-authoritative).
--
-- Occasionally during MAIN, a glowing blue/white frozen meteor falls from
-- the sky with an icy mist trail and slams into a random island. On impact
-- it produces (all SERVER-created + replicated parts, so everyone sees it):
--   * an expanding + fading FREEZING SHOCKWAVE ring
--   * a frozen "scorch" patch (a pale-blue frosted disc)
--   * jagged ICE SPIKES + cracks radiating out
--   * a SNOW BURST + drifting frozen debris chunks
--   * a cold boom + a brief PointLight flash
-- All impact parts are CanCollide=false, fade out, and auto-destroy.
--
-- On impact it ALSO triggers the proximity WalkSpeed-only freeze via
-- IcePhysics (which messages nearby clients). Caps simultaneous meteors at
-- CONFIG.MAX_ICE_METEORS and every emitter Rate at CONFIG.MAX_PARTICLE_RATE.
--
-- GAMEPLAY SAFETY:
--   * EVERY meteor / shockwave / spike / debris part is CanCollide=false
--     (+ CanQuery=false / CanTouch=false) so it can never block, trap, or
--     change island collision/shape.
--   * The ONLY player-facing effect is the proximity freeze, which is
--     delegated to IcePhysics -> client and changes ONLY WalkSpeed briefly.
--     Nothing here touches the fart meter / power / flight / gas / coins.
--======================================================================

local IceMeteor = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Wired by init().
local CONFIG = nil
local IceAgeSync = nil
local IcePhysics = nil

-- State.
local meteorFolder = nil       -- holds falling meteors
local debrisFolder = nil       -- holds impact debris (separate so cleanup is clean)
local activeConnections = {}   -- Heartbeat connections driving falls
local liveMeteorCount = 0      -- meteors currently falling (the simultaneous cap)
local running = false          -- spawn-loop control
local spawnThread = nil

--------------------------------------------------------------------
-- init(config, syncEvent, icePhysics): wire shared dependencies.
--------------------------------------------------------------------
function IceMeteor.init(config, syncEvent, icePhysics)
	CONFIG = config
	IceAgeSync = syncEvent
	IcePhysics = icePhysics
end

--------------------------------------------------------------------
-- Folder helpers (fresh folders, parented to workspace).
--------------------------------------------------------------------
local function ensureMeteorFolder()
	if not meteorFolder or not meteorFolder.Parent then
		meteorFolder = Instance.new("Folder")
		meteorFolder.Name = "IceAgeMeteors"
		meteorFolder.Parent = workspace
	end
	return meteorFolder
end

local function ensureDebrisFolder()
	if not debrisFolder or not debrisFolder.Parent then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "IceAgeMeteorDebris"
		debrisFolder.Parent = workspace
	end
	return debrisFolder
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped emitter helper (Rate clamped to the
-- shared MAX_PARTICLE_RATE so heavy meteors can never spike particle counts).
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = math.min(props.Rate or 10, CONFIG.MAX_PARTICLE_RATE)
	pe.Lifetime = props.Lifetime or NumberRange.new(0.6, 1.2)
	pe.Speed = props.Speed or NumberRange.new(2, 5)
	pe.SpreadAngle = props.SpreadAngle or Vector2.new(20, 20)
	pe.Rotation = props.Rotation or NumberRange.new(0, 360)
	pe.Size = props.Size or NumberSequence.new(2)
	pe.Transparency = props.Transparency or NumberSequence.new(0.2)
	pe.Color = props.Color or ColorSequence.new(Color3.new(1, 1, 1))
	pe.LightEmission = props.LightEmission or 0
	pe.Acceleration = props.Acceleration or Vector3.new(0, 0, 0)
	pe.Enabled = props.Enabled ~= false
	pe.Parent = parent
	return pe
end

--======================================================================
-- buildImpact(pos, radius): the frozen impact -- shockwave + frosted disc +
-- ice spikes + cracks + snow burst + drifting frozen debris + flash + boom.
-- Everything CanCollide=false, fades, and auto-destroys.
--======================================================================
local function buildImpact(pos, radius)
	local folder = ensureDebrisFolder()

	-- Group this impact's parts under one model for tidy fade + destroy.
	local zone = Instance.new("Model")
	zone.Name = "IceImpact"
	zone.Parent = folder

	local frostRadius = radius * 2.6
	local fadeParts = {} -- parts we will tween to transparent then destroy

	-- ---- Frosted ground disc (thin, flat, pale blue, sits ON the surface). ----
	local disc = Instance.new("Part")
	disc.Name = "FrostDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Glacier
	disc.Color = Color3.fromRGB(205, 230, 245)
	disc.Size = Vector3.new(0.4, frostRadius * 2, frostRadius * 2)
	disc.Anchored = true
	disc.CanCollide = false -- never blocks players / never changes island shape
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Transparency = 0.1
	disc.Parent = zone
	table.insert(fadeParts, disc)

	-- ---- Jagged ice spikes radiating from the center (capped count). ----
	local spikeCount = math.clamp(math.floor(5 + radius), 5, 12)
	for i = 1, spikeCount do
		local ang = math.rad((360 / spikeCount) * i + math.random(-15, 15))
		local dist = frostRadius * (0.3 + math.random() * 0.6)
		local h = math.random(20, 50) / 10 * (1 + radius * 0.08)
		local spike = Instance.new("Part")
		spike.Name = "IceSpike_" .. i
		spike.Material = Enum.Material.Ice
		spike.Color = Color3.fromRGB(180, 220, 245)
		spike.Transparency = 0.15
		spike.Size = Vector3.new(math.random(6, 12) / 10, h, math.random(6, 12) / 10)
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		-- Lean each spike slightly outward from center.
		spike.CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * dist, h / 2, math.sin(ang) * dist))
			* CFrame.Angles(math.rad(math.random(-18, 18)), ang, math.rad(math.random(-18, 18)))
		spike.Parent = zone
		table.insert(fadeParts, spike)
	end

	-- ---- Frost cracks along the ground (thin neon-ish frozen lines). ----
	local crackCount = math.clamp(math.floor(4 + radius * 0.6), 4, 10)
	for i = 1, crackCount do
		local ang = math.rad((360 / crackCount) * i + math.random(-20, 20))
		local len = frostRadius * (0.4 + math.random() * 0.6)
		local crack = Instance.new("Part")
		crack.Name = "FrostCrack_" .. i
		crack.Material = Enum.Material.Neon
		crack.Color = Color3.fromRGB(150, 205, 255)
		crack.Transparency = 0.25
		crack.Size = Vector3.new(len, 0.2, math.random(3, 6) / 10)
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		crack.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0))
			* CFrame.Angles(0, ang, 0)
			* CFrame.new(len / 2, 0, 0)
		crack.Parent = zone
		table.insert(fadeParts, crack)
	end

	-- ---- Drifting frozen debris chunks around the rim (CanCollide=false). ----
	local chunkCount = math.clamp(math.floor(3 + radius * 0.5), 3, 8)
	for i = 1, chunkCount do
		local ang = math.random() * math.pi * 2
		local dist = frostRadius * (0.5 + math.random() * 0.6)
		local sz = math.random(6, 14) / 10 * (1 + radius * 0.06)
		local chunk = Instance.new("Part")
		chunk.Name = "FrozenDebris_" .. i
		chunk.Material = Enum.Material.Glacier
		chunk.Color = Color3.fromRGB(200, 225, 240)
		chunk.Transparency = 0.1
		chunk.Size = Vector3.new(sz, sz * 0.8, sz)
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * dist, sz * 0.4, math.sin(ang) * dist))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = zone
		table.insert(fadeParts, chunk)
	end

	-- ---- Expanding + fading freezing shockwave ring (thin neon disc). ----
	local ring = Instance.new("Part")
	ring.Name = "FreezeShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(210, 240, 255)
	ring.Size = Vector3.new(0.5, radius * 3, radius * 3)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = folder
	local target = CONFIG.FREEZE_SHOCKWAVE_RADIUS * 2
	TweenService:Create(ring, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.5, target, target), Transparency = 1 }):Play()
	Debris:AddItem(ring, 1.5)

	-- ---- Snow burst + cold mist + sparkle (capped emitters on a hub). ----
	local hub = Instance.new("Part")
	hub.Name = "ImpactHub"
	hub.Size = Vector3.new(1, 1, 1)
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.CFrame = CFrame.new(pos + Vector3.new(0, radius * 0.5, 0))
	hub.Parent = zone

	local snowBurst = makeEmitter(hub, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = CONFIG.MAX_PARTICLE_RATE,
		Lifetime = NumberRange.new(1.0, 2.2),
		Speed = NumberRange.new(12, 26),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(radius * 3),
		Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Acceleration = Vector3.new(0, -4, 0),
	})
	local sparkle = makeEmitter(hub, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = math.floor(CONFIG.MAX_PARTICLE_RATE * 0.6),
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(120, 120),
		Size = NumberSequence.new(0.5),
		Color = ColorSequence.new(Color3.fromRGB(190, 225, 255)),
		LightEmission = 1,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	task.delay(0.5, function()
		if snowBurst then snowBurst.Enabled = false end
		if sparkle then sparkle.Enabled = false end
	end)

	-- ---- Brief blue flash light. ----
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(170, 215, 255)
	flash.Brightness = 6
	flash.Range = math.clamp(radius * 10, 30, 110)
	flash.Parent = hub
	TweenService:Create(flash, TweenInfo.new(0.7), { Brightness = 0 }):Play()

	-- ---- Cold boom (positional). ----
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://5801257793" -- shared low boom (cold-tuned by pitch)
	snd.Volume = 1   -- unified volume: matches the meteor intro sound
	snd.PlaybackSpeed = 0.8
	snd.RollOffMaxDistance = 6000
	snd.Parent = hub
	snd:Play()

	-- ---- Fade the whole frozen zone, then destroy it. ----
	local life = CONFIG.METEOR_DEBRIS_LIFETIME
	task.delay(life * 0.55, function()
		for _, p in ipairs(fadeParts) do
			if p and p.Parent then
				TweenService:Create(p, TweenInfo.new(life * 0.45, Enum.EasingStyle.Linear),
					{ Transparency = 1 }):Play()
			end
		end
	end)
	-- Final destroy (also covered by cleanup() if the event ends sooner).
	Debris:AddItem(zone, life + 1)
end

--======================================================================
-- spawnMeteor(targetPos): build one falling ice meteor and animate it down
-- to targetPos via a Heartbeat lerp + PivotTo (never teleported). On landing
-- it builds the impact + fires the proximity freeze + a per-client camera
-- shake. Respects the MAX_ICE_METEORS simultaneous cap.
--======================================================================
local function spawnMeteor(targetPos)
	if liveMeteorCount >= CONFIG.MAX_ICE_METEORS then
		return -- at the simultaneous cap; skip (perf)
	end
	local folder = ensureMeteorFolder()

	local radius = CONFIG.METEOR_SIZE_MIN
		+ math.random() * (CONFIG.METEOR_SIZE_MAX - CONFIG.METEOR_SIZE_MIN)

	-- The frozen meteor body: a rough icy ball, glowing blue/white.
	local rock = Instance.new("Part")
	rock.Name = "IceMeteor"
	rock.Shape = Enum.PartType.Ball
	rock.Material = Enum.Material.Glacier
	rock.Color = Color3.fromRGB(190, 220, 245)
	rock.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false

	-- Start high above the target, offset a little so it falls at an angle.
	local startPos = targetPos + Vector3.new(
		(math.random() - 0.5) * 120,
		CONFIG.METEOR_SPAWN_HEIGHT,
		(math.random() - 0.5) * 120)
	rock.CFrame = CFrame.new(startPos)
	rock.Parent = folder

	-- Glow.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(160, 210, 255)
	light.Brightness = 4
	light.Range = math.clamp(radius * 6, 20, 90)
	light.Parent = rock

	-- Icy mist trail + sparkle (capped emitters).
	makeEmitter(rock, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = CONFIG.MAX_PARTICLE_RATE,
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new(radius * 1.6),
		Color = ColorSequence.new(Color3.fromRGB(225, 240, 255), Color3.fromRGB(150, 200, 255)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	makeEmitter(rock, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = math.floor(CONFIG.MAX_PARTICLE_RATE * 0.5),
		Lifetime = NumberRange.new(0.4, 1.0),
		Speed = NumberRange.new(1, 4),
		Size = NumberSequence.new(0.6),
		Color = ColorSequence.new(Color3.fromRGB(210, 235, 255)),
		LightEmission = 1,
		Transparency = NumberSequence.new(0.2),
	})
	-- A bluish Trail behind the meteor (cheap, single instance).
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, radius, 0); a0.Parent = rock
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -radius, 0); a1.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255), Color3.fromRGB(120, 180, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = rock

	liveMeteorCount = liveMeteorCount + 1

	-- Animate the fall.
	local fallTime = CONFIG.METEOR_FALL_TIME_MIN
		+ math.random() * (CONFIG.METEOR_FALL_TIME_MAX - CONFIG.METEOR_FALL_TIME_MIN)
	local elapsed = 0
	local spin = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not rock.Parent then
			-- Destroyed by cleanup mid-fall: release this connection + count.
			conn:Disconnect()
			activeConnections[conn] = nil
			return
		end
		elapsed = elapsed + dt
		local alpha = math.clamp(elapsed / fallTime, 0, 1)
		-- Ease-in so it accelerates downward.
		local eased = alpha * alpha
		local pos = startPos:Lerp(targetPos, eased)
		spin = spin + dt * 4
		rock.CFrame = CFrame.new(pos) * CFrame.Angles(spin, spin * 0.7, 0)

		if alpha >= 1 then
			-- Landed: stop driving, tear the meteor down, build the impact.
			conn:Disconnect()
			activeConnections[conn] = nil
			liveMeteorCount = math.max(0, liveMeteorCount - 1)

			buildImpact(targetPos, radius)

			-- Per-client camera shake + boom cue (camera shake is per-client).
			if IceAgeSync then
				IceAgeSync:FireAllClients("meteorImpact", {
					position = targetPos,
					intensity = math.clamp(radius / CONFIG.METEOR_SIZE_MAX, 0.3, 1) * 0.7,
				})
			end

			-- Proximity WalkSpeed-only freeze on nearby players (server-decided
			-- -> client-applied). Never touches power/flight/coins.
			if IcePhysics then
				IcePhysics.applyFreeze(targetPos)
			end

			-- Remove the meteor body now its job is done (impact parts persist).
			rock:Destroy()
		end
	end)
	activeConnections[conn] = true
end

--======================================================================
-- start(targets, variant): begin the meteor spawn loop. Picks a random
-- island target each time + waits a random interval. Runs until stop().
--======================================================================
function IceMeteor.start(targets, _variant)
	if running then return end
	running = true

	spawnThread = task.spawn(function()
		-- Small initial delay so MAIN doesn't open with an instant impact.
		task.wait(CONFIG.METEOR_INTERVAL_MIN)
		while running do
			if targets and #targets > 0 then
				local t = targets[math.random(1, #targets)]
				-- Jitter the impact point across the island surface.
				local jx = (math.random() - 0.5) * (t.size and t.size.X or 100) * 0.5
				local jz = (math.random() - 0.5) * (t.size and t.size.Z or 100) * 0.5
				local pos = t.position + Vector3.new(jx, 0, jz)
				spawnMeteor(pos)
			end
			local wait = CONFIG.METEOR_INTERVAL_MIN
				+ math.random() * (CONFIG.METEOR_INTERVAL_MAX - CONFIG.METEOR_INTERVAL_MIN)
			task.wait(wait)
		end
	end)
end

--------------------------------------------------------------------
-- stop(): halt the spawn loop. In-flight meteors keep falling + land
-- normally; cleanup() does the hard teardown. Safe to call repeatedly.
--------------------------------------------------------------------
function IceMeteor.stop()
	running = false
	spawnThread = nil
end

--======================================================================
-- cleanup(): disconnect every fall connection + destroy all meteor + debris
-- instances. No leaks.
--======================================================================
function IceMeteor.cleanup()
	running = false
	for conn in pairs(activeConnections) do
		if conn.Connected then conn:Disconnect() end
	end
	activeConnections = {}
	liveMeteorCount = 0
	if meteorFolder and meteorFolder.Parent then meteorFolder:Destroy() end
	if debrisFolder and debrisFolder.Parent then debrisFolder:Destroy() end
	meteorFolder = nil
	debrisFolder = nil
end

return IceMeteor
