--======================================================================
-- IceVFX.lua  (ModuleScript)
--======================================================================
-- World visuals for the global "IceAge" event (SERVER-authoritative; all
-- parts replicate so every client sees the same frozen world).
--
-- Responsibilities:
--   * FROST creep (WARNING): a thin frosted sheen begins over island tops.
--   * WORLD FREEZE (MAIN): islands gradually gain SNOW/ICE COVER (thin caps
--     over island tops), ICICLES hang under the floating islands, frozen
--     wind particles drift, and a partial shiny-surface freeze is applied.
--   * RARE VARIANTS: frozen lightning storm strikes, a giant snowball that
--     rolls between islands, an ice dragon that flies overhead, northern
--     lights (handled client-side via "aurora"), and the whole-event
--     "Absolute Zero" crystal-blue mode (a stronger tint of everything).
--   * FUN DETAILS: NPCs shiver / some slip + fall, frozen fart SFX cue, and
--     snow piles forming in corners.
--   * MELT (ENDING): gradually fades all ice/snow before cleanup destroys it.
--
-- ★ HARD RULES ★
--   * SNOW / ICE / ICICLE / FROST IS VISUAL ONLY. EVERY part created here is
--     CanCollide=false (+ CanQuery=false / CanTouch=false). It must NOT
--     change island collision/shape, block movement/walking, or block shop
--     access. The thin caps sit slightly ABOVE the surface and never replace
--     or resize island geometry.
--   * PERFORMANCE: a HARD running cap of CONFIG.MAX_ICE_PARTS simultaneous
--     snow/ice parts, every emitter Rate clamped to CONFIG.MAX_PARTICLE_RATE,
--     a capped number of icicles/snow caps per island.
--   * If we ever change a prop's texture/color for the "frozen prop" look we
--     SAVE the original and RESTORE it on cleanup (no permanent world change).
--   * This module never touches the fart meter / power / flight / coins.
--======================================================================

local IceVFX = {}

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Wired by init().
local CONFIG = nil
local IceAgeSync = nil

-- State.
local vfxFolder = nil          -- holds every snow/ice/icicle/frost part
local variantFolder = nil      -- holds rare-variant props (snowball, dragon, etc.)
local icePartCount = 0         -- live count toward MAX_ICE_PARTS
local fadeParts = {}           -- all parts we will fade on melt()
local activeConns = {}         -- Heartbeat connections (snowball, dragon) to release
local restoreList = {}         -- { instance, prop, originalValue } to restore on cleanup
local currentVariant = "normal"

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies.
--------------------------------------------------------------------
function IceVFX.init(config, syncEvent)
	CONFIG = config
	IceAgeSync = syncEvent
end

--------------------------------------------------------------------
-- Folder helpers.
--------------------------------------------------------------------
local function ensureVFXFolder()
	if not vfxFolder or not vfxFolder.Parent then
		vfxFolder = Instance.new("Folder")
		vfxFolder.Name = "IceAgeVFX"
		vfxFolder.Parent = workspace
	end
	return vfxFolder
end

local function ensureVariantFolder()
	if not variantFolder or not variantFolder.Parent then
		variantFolder = Instance.new("Folder")
		variantFolder.Name = "IceAgeVariants"
		variantFolder.Parent = workspace
	end
	return variantFolder
end

--------------------------------------------------------------------
-- canSpawnIce(n): true if we can add `n` more parts under the hard cap.
-- This is the central PERFORMANCE guard for all world ice/snow.
--------------------------------------------------------------------
local function canSpawnIce(n)
	return (icePartCount + (n or 1)) <= CONFIG.MAX_ICE_PARTS
end

--------------------------------------------------------------------
-- iceColor(): variant-aware ice tint ("Absolute Zero" is a colder crystal
-- blue; normal is a soft white-blue).
--------------------------------------------------------------------
local function iceColor()
	if currentVariant == "absoluteZero" then
		return Color3.fromRGB(150, 200, 255)
	end
	return Color3.fromRGB(225, 240, 250)
end

--------------------------------------------------------------------
-- newIcePart(props): create + register one CanCollide=false ice/snow part.
-- Centralizes the safety flags + the cap accounting + the melt-fade list.
-- Returns the part, or nil if the cap is hit.
--------------------------------------------------------------------
local function newIcePart(props)
	if not canSpawnIce(1) then return nil end
	local p = Instance.new("Part")
	p.Name = props.Name or "Ice"
	p.Material = props.Material or Enum.Material.Glacier
	p.Color = props.Color or iceColor()
	p.Transparency = props.Transparency or 0.1
	p.Size = props.Size or Vector3.new(1, 1, 1)
	p.Anchored = true
	-- ★ VISUAL ONLY: never collide / never block / never change island shape. ★
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if props.Shape then p.Shape = props.Shape end
	if props.Reflectance then p.Reflectance = props.Reflectance end
	p.CFrame = props.CFrame or CFrame.new()
	p.Parent = props.Parent or ensureVFXFolder()
	icePartCount = icePartCount + 1
	table.insert(fadeParts, p)
	return p
end

--------------------------------------------------------------------
-- makeEmitter(parent, props): capped emitter helper.
--------------------------------------------------------------------
local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = math.min(props.Rate or 8, CONFIG.MAX_PARTICLE_RATE)
	pe.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	pe.Speed = props.Speed or NumberRange.new(1, 3)
	pe.SpreadAngle = props.SpreadAngle or Vector2.new(30, 30)
	pe.Size = props.Size or NumberSequence.new(0.5)
	pe.Transparency = props.Transparency or NumberSequence.new(0.3)
	pe.Color = props.Color or ColorSequence.new(Color3.fromRGB(230, 245, 255))
	pe.LightEmission = props.LightEmission or 0.2
	pe.Acceleration = props.Acceleration or Vector3.new(0, -2, 0)
	pe.Enabled = props.Enabled ~= false
	pe.Parent = parent
	return pe
end

--------------------------------------------------------------------
-- SNOW DISC: one thin Cylinder (flat round disc) laid flush on an island's
-- walking surface. `pos` is the surface centre (at the surface Y), `diameter`
-- comes from the detected grass footprint (already 1.1x in WeatherManager, so
-- it slightly overhangs the edges). The Cylinder's round face is laid
-- horizontal (rotate 90deg about Z so its length axis points up). Registered
-- like every other ice part (cap accounting + melt-fade + cleanup).
--------------------------------------------------------------------
local SNOW_Y_OFFSET = 0.5   -- studs above the surface so the disc sits on top
local SNOW_THICK    = 0.6   -- disc thickness

local function makeSnowDisc(pos, diameter, opts)
	return newIcePart({
		Name = opts.Name or "SnowDisc",
		Material = opts.Material or Enum.Material.Snow,
		Color = opts.Color or Color3.fromRGB(245, 250, 255),
		Transparency = 1, -- fade in via tween
		Reflectance = opts.Reflectance or 0,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(opts.thickness or SNOW_THICK, diameter, diameter),
		-- Lay the cylinder flat (length axis -> vertical) so the round face is up.
		CFrame = CFrame.new(pos + Vector3.new(0, SNOW_Y_OFFSET, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
end

--======================================================================
-- startFrost(targets, variant): WARNING-phase thin frosted sheen over island
-- tops + a few drifting frozen-wind particles. Light + cheap.
--======================================================================
function IceVFX.startFrost(targets, variant)
	currentVariant = variant or "normal"
	ensureVFXFolder()
	for _, t in ipairs(targets or {}) do
		-- A thin, translucent frosted DISC that fades IN over the island ground.
		local diameter = (t.size and t.size.X) or 140
		local frost = makeSnowDisc(t.position, diameter, {
			Name = "FrostSheen_" .. tostring(t.index),
			Material = Enum.Material.Ice,
			Color = iceColor(),
			Reflectance = 0.1,
			thickness = 0.2,
		})
		if frost then
			TweenService:Create(frost, TweenInfo.new(CONFIG.WARNING_DURATION * 0.8),
				{ Transparency = 0.55 }):Play()
		end
	end
end

--======================================================================
-- startWorldFreeze(targets, variant): MAIN-phase world cover.
--   * a thicker SNOW/ICE CAP over each island top (thin, CanCollide=false)
--   * ICICLES hanging UNDER each floating island
--   * drifting frozen-wind particles
--   * "snow piles" forming at island corners (small wedge-ish parts)
--   * a frozen-fart SFX cue broadcast to clients
--   * NPC shiver / occasional slip broadcast to clients
-- All capped by MAX_ICE_PARTS + MAX_PARTICLE_RATE.
--======================================================================
function IceVFX.startWorldFreeze(targets, variant)
	currentVariant = variant or currentVariant
	ensureVFXFolder()

	for _, t in ipairs(targets or {}) do
		local sx = (t.size and t.size.X or 120)
		local sy = (t.size and t.size.Y or 40)
		local sz = (t.size and t.size.Z or 120)

		-- ---- Snow CAP: ONE thin round DISC laid flush on the ground, sized a
		--      bit bigger than the grass footprint (slight overhang wanted). ----
		local capColor = (currentVariant == "absoluteZero")
			and Color3.fromRGB(205, 230, 255) or Color3.fromRGB(245, 250, 255)
		do
			local cap = makeSnowDisc(t.position, sx, {
				Name = "SnowCap_" .. tostring(t.index),
				Material = Enum.Material.Snow,
				Color = capColor,
				thickness = 0.6,
			})
			if cap then
				TweenService:Create(cap, TweenInfo.new(4), { Transparency = 0.05 }):Play()
			end
		end

		-- ---- A shiny partial ICE patch on top (smaller, glossy). ----
		local shine = newIcePart({
			Name = "IceShine_" .. tostring(t.index),
			Material = Enum.Material.Ice,
			Color = iceColor(),
			Transparency = 1,
			Size = Vector3.new(sx * 0.45, 0.25, sz * 0.45),
			CFrame = CFrame.new(t.position + Vector3.new(
				(math.random() - 0.5) * sx * 0.3, 0.7, (math.random() - 0.5) * sz * 0.3)),
		})
		if shine then
			shine.Reflectance = 0.4
			TweenService:Create(shine, TweenInfo.new(4), { Transparency = 0.1 }):Play()
		end

		-- ---- Snow piles near the corners (small low wedges). Pulled in to 0.3 so
		--      they stay ON the deck even for round/irregular islands. ----
		local corners = {
			Vector3.new(sx * 0.3, 0, sz * 0.3),
			Vector3.new(-sx * 0.3, 0, sz * 0.3),
			Vector3.new(sx * 0.3, 0, -sz * 0.3),
			Vector3.new(-sx * 0.3, 0, -sz * 0.3),
		}
		for _, c in ipairs(corners) do
			local pile = newIcePart({
				Name = "SnowPile",
				Material = Enum.Material.Snow,
				Color = Color3.fromRGB(248, 252, 255),
				Transparency = 0.1,
				Size = Vector3.new(math.random(40, 70) / 10, math.random(15, 30) / 10, math.random(40, 70) / 10),
				CFrame = CFrame.new(t.position + c + Vector3.new(0, 0.6, 0)),
			})
			if not pile then break end -- hit the cap
		end

		-- ---- ICICLES hanging UNDER the floating island. ----
		-- t.position.Y is now the island TOP for every island, and sy is the
		-- model height, so (top - sy) is the island BOTTOM: icicles hang from
		-- under the island, consistently per island.
		local icicleCount = 6
		local underY = t.position.Y - sy
		for i = 1, icicleCount do
			local ang = math.random() * math.pi * 2
			local rad = math.min(sx, sz) * 0.4 * math.random()
			local len = math.random(20, 60) / 10
			local icicle = newIcePart({
				Name = "Icicle",
				Material = Enum.Material.Ice,
				Color = iceColor(),
				Transparency = 0.1,
				Shape = Enum.PartType.Block,
				Size = Vector3.new(math.random(4, 9) / 10, len, math.random(4, 9) / 10),
				CFrame = CFrame.new(t.position.X + math.cos(ang) * rad, underY - len / 2,
					t.position.Z + math.sin(ang) * rad),
			})
			if not icicle then break end -- hit the cap
		end

		-- ---- Drifting frozen-wind particles above the island (one hub). ----
		local hub = newIcePart({
			Name = "WindParticleHub",
			Material = Enum.Material.Glacier,
			Transparency = 1,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(t.position + Vector3.new(0, 12, 0)),
		})
		if hub then
			makeEmitter(hub, {
				Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Rate = 8,
				Lifetime = NumberRange.new(2, 4),
				Speed = NumberRange.new(2, 5),
				SpreadAngle = Vector2.new(80, 80),
				Size = NumberSequence.new(0.4),
				Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
				Acceleration = Vector3.new(3, -1, 0), -- drift sideways like blown snow
			})
		end
	end

	-- Frozen-fart SFX cue + NPC shiver/slip flavour (client-side cosmetics).
	if IceAgeSync then
		IceAgeSync:FireAllClients("frozenFartSFX")
		IceAgeSync:FireAllClients("npcShiver")
	end
end

--======================================================================
-- frozenLightning(targets): a brief frozen lightning strike -- a tall pale
-- neon bolt over a random island + a client flash cue. VISUAL ONLY.
--======================================================================
function IceVFX.frozenLightning(targets)
	if not targets or #targets == 0 then return end
	if not canSpawnIce(1) then return end
	local t = targets[math.random(1, #targets)]
	local folder = ensureVariantFolder()

	local bolt = Instance.new("Part")
	bolt.Name = "FrozenBolt"
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(200, 230, 255)
	bolt.Transparency = 0.1
	bolt.Size = Vector3.new(1.2, 400, 1.2)
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.CFrame = CFrame.new(t.position + Vector3.new(
		(math.random() - 0.5) * 40, 200, (math.random() - 0.5) * 40))
		* CFrame.Angles(0, 0, math.rad(math.random(-8, 8)))
	bolt.Parent = folder
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(200, 230, 255)
	pl.Brightness = 8
	pl.Range = 120
	pl.Parent = bolt
	TweenService:Create(bolt, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	Debris:AddItem(bolt, 0.6)

	if IceAgeSync then
		IceAgeSync:FireAllClients("frozenLightning", { position = t.position })
	end
end

--======================================================================
-- giantSnowball(targets): a giant snowball rolls between two islands. A
-- single big CanCollide=false ball lerped along an arc, then destroyed.
--======================================================================
function IceVFX.giantSnowball(targets)
	if not targets or #targets < 2 then return end
	if not canSpawnIce(1) then return end
	local folder = ensureVariantFolder()

	local a = targets[math.random(1, #targets)]
	local b = targets[math.random(1, #targets)]
	if a.index == b.index then return end

	local ball = Instance.new("Part")
	ball.Name = "GiantSnowball"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Snow
	ball.Color = Color3.fromRGB(248, 252, 255)
	ball.Size = Vector3.new(24, 24, 24)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(a.position + Vector3.new(0, 14, 0))
	ball.Parent = folder
	makeEmitter(ball, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 12,
		Lifetime = NumberRange.new(0.6, 1.4),
		Size = NumberSequence.new(6),
		Color = ColorSequence.new(Color3.fromRGB(245, 250, 255)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	})

	local startP = a.position + Vector3.new(0, 14, 0)
	local endP = b.position + Vector3.new(0, 14, 0)
	local dur = 4
	local elapsed, spin = 0, 0
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not ball.Parent then conn:Disconnect() activeConns[conn] = nil return end
		elapsed = elapsed + dt
		local alpha = math.clamp(elapsed / dur, 0, 1)
		spin = spin + dt * 6
		-- A gentle arc (rises in the middle) between the two islands.
		local pos = startP:Lerp(endP, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * 30, 0)
		ball.CFrame = CFrame.new(pos) * CFrame.Angles(spin, 0, 0)
		if alpha >= 1 then
			conn:Disconnect()
			activeConns[conn] = nil
			ball:Destroy()
		end
	end)
	activeConns[conn] = true
	Debris:AddItem(ball, dur + 1)
end

--======================================================================
-- iceDragon(targets): an ice dragon flies overhead -- a simple glowing
-- crystalline body with an icy trail, sweeping across the island band, then
-- gone. Single moving part (cheap).
--======================================================================
function IceVFX.iceDragon(targets)
	if not targets or #targets == 0 then return end
	if not canSpawnIce(1) then return end
	local folder = ensureVariantFolder()

	-- Fly across the vertical middle of the island band.
	local minY, maxY = math.huge, -math.huge
	for _, t in ipairs(targets) do
		minY = math.min(minY, t.position.Y); maxY = math.max(maxY, t.position.Y)
	end
	local midY = (minY + maxY) / 2 + 150

	local body = Instance.new("Part")
	body.Name = "IceDragon"
	body.Material = Enum.Material.Ice
	body.Color = Color3.fromRGB(170, 215, 255)
	body.Transparency = 0.1
	body.Reflectance = 0.3
	body.Size = Vector3.new(8, 8, 28)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Parent = folder
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(180, 220, 255); pl.Brightness = 3; pl.Range = 60
	pl.Parent = body
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0, 12); a0.Parent = body
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, 0, -12); a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0; trail.Attachment1 = a1; trail.Lifetime = 1.2
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.fromRGB(120, 180, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = body

	local startP = Vector3.new(-900, midY, math.random(-200, 200))
	local endP = Vector3.new(900, midY, math.random(-200, 200))
	local dur = 6
	local elapsed = 0
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not body.Parent then conn:Disconnect() activeConns[conn] = nil return end
		elapsed = elapsed + dt
		local alpha = math.clamp(elapsed / dur, 0, 1)
		local pos = startP:Lerp(endP, alpha) + Vector3.new(0, math.sin(alpha * math.pi * 2) * 20, 0)
		-- Face direction of travel.
		body.CFrame = CFrame.lookAt(pos, pos + (endP - startP))
		if alpha >= 1 then
			conn:Disconnect()
			activeConns[conn] = nil
			body:Destroy()
		end
	end)
	activeConns[conn] = true
	Debris:AddItem(body, dur + 1)

	if IceAgeSync then
		IceAgeSync:FireAllClients("iceDragon")
	end
end

--======================================================================
-- startMelt(): ENDING -- fade all world ice/snow/icicles toward transparent
-- so the world visibly thaws before cleanup() destroys everything.
--======================================================================
function IceVFX.startMelt()
	local dur = math.max(2, CONFIG.ENDING_DURATION - 1)
	for _, p in ipairs(fadeParts) do
		if p and p.Parent then
			TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear),
				{ Transparency = 1 }):Play()
		end
	end
end

--======================================================================
-- cleanup(): disconnect every variant connection, destroy all ice/snow/
-- variant parts, and RESTORE any prop textures/colors we changed. No leaks,
-- no permanent world change.
--======================================================================
function IceVFX.cleanup()
	-- Release moving-variant connections.
	for conn in pairs(activeConns) do
		if conn.Connected then conn:Disconnect() end
	end
	activeConns = {}

	-- Restore any modified prop properties (we save originals in restoreList).
	for _, entry in ipairs(restoreList) do
		local inst = entry.instance
		if inst and inst.Parent then
			pcall(function() inst[entry.prop] = entry.value end)
		end
	end
	restoreList = {}

	-- Destroy all our folders.
	if vfxFolder and vfxFolder.Parent then vfxFolder:Destroy() end
	if variantFolder and variantFolder.Parent then variantFolder:Destroy() end
	vfxFolder = nil
	variantFolder = nil

	-- Reset counters/state.
	fadeParts = {}
	icePartCount = 0
	currentVariant = "normal"
end

return IceVFX
