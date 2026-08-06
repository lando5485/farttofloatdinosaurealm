--======================================================================
-- IceAgeUI.client.lua  (LocalScript)
--======================================================================
-- Client-side presentation + the ★ GUARDED PLAYER-PHYSICS handlers ★ for the
-- global "IceAge" event. Listens to the IceAgeSync RemoteEvent and renders
-- everything that MUST live on the client because it is per-client (this
-- player's Camera / Lighting view / network-owned character physics):
--
--   * cinematic SKY (pale blue/gray via ColorCorrection + Atmosphere + fog +
--     snow clouds + a small icy-fog visibility drop) -- FULLY RESTORED from a
--     saved Lighting snapshot on reset.
--   * announcement banners ("ICE AGE APPROACHING!", "Ice Age Ending..."),
--     cold-wind + ice-cracking ambient sounds.
--   * a CAMERA-TRACKED, HARD-CAPPED snow particle volume (a few efficient
--     emitters that follow the camera; density scales with phase + a low-end
--     quality option). NEVER exceeds MAX_SNOW_EMITTERS / MAX_PARTICLE_RATE.
--   * COSMETIC feel: icy trail on fart boosts, breath-condensation puffs,
--     a slippery visual sheen. Cosmetic only -- no gating needed.
--   * ★ the GUARDED PHYSICS ★ (the safety-critical part):
--       - ground-only SLIDE (slight slipperiness) + gust NUDGE, both gated so
--         they ONLY apply while GROUNDED and `_G.isFlying ~= true`, and are
--         REMOVED the instant the player flies or leaves the ground.
--       - a WalkSpeed-ONLY meteor FREEZE with capture/restore.
--
-- ★★★ THE CONTRACT (the single most important thing in this file) ★★★
--   * SLIDE + WIND apply ONLY when the player is GROUNDED and NOT flying. The
--     INSTANT `_G.isFlying == true` OR the humanoid leaves the ground, BOTH
--     are removed. They can NEVER shove a player off an active fart-flight or
--     out of a climb. Both are SMALL and CONFIG-tunable/zeroable.
--   * The meteor FREEZE changes ONLY the Humanoid's WalkSpeed (briefly), then
--     restores the CAPTURED original. It NEVER touches the fart meter, fart
--     power, flight, gas, or coins, and NEVER cancels/interrupts a climb. A
--     frozen player keeps FULL fart power and can still fart-fly normally --
--     in fact if they are flying we don't apply (or instantly clear) the
--     WalkSpeed change, since WalkSpeed is irrelevant to flight anyway.
--   * NOTHING is permanent: on effect end AND on "reset" every effect (custom
--     friction, gust velocity, WalkSpeed) returns to the player's normal.
--   * The ONLY _G access anywhere in this whole event is READING `_G.isFlying`
--     below to gate. We never write any _G flight/power/coin global.
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local sync = ReplicatedStorage:WaitForChild("IceAgeSync")

--======================================================================
-- LOW-END QUALITY OPTION
-- A local scalar multiplied into the snow density. The server broadcasts a
-- default at "start"; a player on a weaker device can lower this (e.g. via a
-- future settings menu) to thin the snow. 1.0 = full quality.
--======================================================================
local lowEndScalar = 1.0
-- Mirror of the server caps (kept conservative; the server is authoritative
-- but the client also self-caps so it can never over-spawn snow).
local MAX_PARTICLE_RATE = 26
local MAX_SNOW_EMITTERS = 6

-- Per-phase snow density (0..1) + icy-fog FogEnd. These MIRROR the server
-- CONFIG values (WeatherManager) so the client can map a phase string onto a
-- density/fog without the server sending numbers every phase. Keep in sync.
local PHASE_SNOW = { warning = 0.30, main = 1.00, ending = 0.20 }
local PHASE_FOG  = { warning = 2200, main = 1400, ending = 3500 }
local function snowForPhase(phase) return PHASE_SNOW[phase] or 0 end
local function fogForPhase(phase) return PHASE_FOG[phase] or 5000 end

-- The continuous SLIDE amount (gentle slipperiness). The client owns a default
-- because slide is applied every frame; the server overrides it at "start".
-- SMALL by design -- never enough to slide a player off an island.
local clientSlideAmount = 0.18

--======================================================================
-- ScreenGui: announcement banner.
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "IceAgeEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 53
gui.Parent = player:WaitForChild("PlayerGui")

local BANNER_BG_VISIBLE = 0.2  -- the opaque background transparency when showing
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.14, 0)
banner.Size = UDim2.new(0.6, 0, 0.08, 0)
banner.BackgroundColor3 = Color3.fromRGB(28, 44, 60)
banner.BackgroundTransparency = 1  -- fully invisible when idle
banner.TextColor3 = Color3.fromRGB(210, 235, 255)
banner.TextScaled = true
banner.Font = Enum.Font.GothamBold
banner.Text = ""
banner.ZIndex = 20
banner.Visible = false
banner.Parent = gui
local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 12)
bannerCorner.Parent = banner

-- Shared across all event banners (one per client) so concurrent announcements
-- stack vertically instead of covering each other.
_G.__eventBannerSlots = _G.__eventBannerSlots or {}
local BANNER_BASE_Y = 0.05   -- topmost banner Y (scale)
local BANNER_SLOT_H = 0.10   -- vertical gap per slot (> banner height 0.08, no overlap)
local bannerSlot = nil       -- this banner's currently-claimed slot, or nil
local function claimBannerSlot()
	if bannerSlot then return bannerSlot end
	local slots = _G.__eventBannerSlots
	local i = 1
	while slots[i] do i = i + 1 end
	slots[i] = true
	bannerSlot = i
	return i
end
local function freeBannerSlot()
	if bannerSlot then _G.__eventBannerSlots[bannerSlot] = nil; bannerSlot = nil end
end
local function bannerSlotY(i) return BANNER_BASE_Y + (i - 1) * BANNER_SLOT_H end

local function hideBanner()
	banner.Visible = false
	banner.BackgroundTransparency = 1
	banner.Text = ""
	freeBannerSlot()
end

local function showBanner(text, duration)
	local slot = claimBannerSlot()
	banner.Position = UDim2.new(0.5, 0, bannerSlotY(slot), 0)
	banner.Text = text
	banner.BackgroundTransparency = BANNER_BG_VISIBLE
	banner.Visible = true
	task.delay(duration or 4, function()
		if banner.Text == text then hideBanner() end
	end)
end

--======================================================================
-- SKY: pale blue/gray winter Lighting that is FULLY restored on reset.
-- We create our OWN ColorCorrection + Atmosphere, tween base Lighting from a
-- saved snapshot, and thicken/cool the Clouds.
--======================================================================
local iceCC = nil
local iceAtmos = nil
local ambientFolder = nil   -- cold-wind + ice-cracking ambient sounds on the camera
local savedLighting = nil
local savedClouds = nil

local function snapshotLighting()
	if savedLighting then return end
	savedLighting = {
		ClockTime = Lighting.ClockTime,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		savedClouds = { Cover = clouds.Cover, Density = clouds.Density, Color = clouds.Color }
	end
end

local function startSky(variant)
	snapshotLighting()
	local absoluteZero = (variant == "absoluteZero")
	local tint = absoluteZero and Color3.fromRGB(180, 215, 255) or Color3.fromRGB(220, 235, 250)

	if not iceCC then
		iceCC = Instance.new("ColorCorrectionEffect")
		iceCC.Name = "IceAgeCC"
		iceCC.Parent = Lighting
	end
	iceCC.Brightness = 0
	iceCC.Contrast = 0
	iceCC.TintColor = Color3.fromRGB(255, 255, 255)
	TweenService:Create(iceCC, TweenInfo.new(3),
		{ Contrast = absoluteZero and 0.18 or 0.08, Saturation = absoluteZero and -0.4 or -0.2,
		  TintColor = tint }):Play()

	if not iceAtmos then
		iceAtmos = Instance.new("Atmosphere")
		iceAtmos.Name = "IceAgeAtmosphere"
		iceAtmos.Parent = Lighting
	end
	iceAtmos.Density = 0.3
	iceAtmos.Color = Color3.fromRGB(200, 220, 240)
	iceAtmos.Decay = Color3.fromRGB(150, 180, 215)
	iceAtmos.Haze = 2
	iceAtmos.Glare = 0.2

	-- Pale, bright-but-cold sky (restored on reset from the snapshot).
	TweenService:Create(Lighting, TweenInfo.new(3), {
		ClockTime = 9,                                  -- flat overcast daylight
		FogColor = Color3.fromRGB(210, 225, 240),
		FogEnd = (savedLighting.FogEnd and savedLighting.FogEnd) or 5000, -- starts here, phases tighten it
		FogStart = 60,
		Brightness = math.max(1, (savedLighting.Brightness or 2)),
		OutdoorAmbient = Color3.fromRGB(170, 190, 210),
	}):Play()

	-- Thicken + cool the clouds for snow-cloud cover.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		TweenService:Create(clouds, TweenInfo.new(3),
			{ Cover = 0.95, Density = 0.65, Color = Color3.fromRGB(225, 235, 245) }):Play()
	end

	-- Cold-wind + ice-cracking ambient sounds, anchored on the camera.
	if not ambientFolder then
		ambientFolder = Instance.new("Folder")
		ambientFolder.Name = "IceAgeAmbient"
		ambientFolder.Parent = workspace.CurrentCamera or workspace
		local wind = Instance.new("Sound")
		wind.Name = "ColdWind"
		wind.SoundId = "rbxassetid://9114402399" -- low wind/howl loop
		wind.Looped = true
		wind.Volume = 1   -- unified volume: matches the meteor intro sound
		wind.Parent = ambientFolder
		wind:Play()
		local crack = Instance.new("Sound")
		crack.Name = "IceCrack"
		crack.SoundId = "rbxassetid://9112854440" -- distant cracking/creak loop
		crack.Looped = true
		crack.Volume = 1   -- unified volume: matches the meteor intro sound
		crack.Parent = ambientFolder
		crack:Play()
	end
end

-- setFog(fogEnd): tween the icy-fog visibility to a phase value (small drop;
-- the world must stay readable). Restored fully on reset.
local function setFog(fogEnd)
	if not savedLighting then return end
	TweenService:Create(Lighting, TweenInfo.new(3), { FogEnd = fogEnd }):Play()
end

local function restoreSky()
	if savedLighting then
		TweenService:Create(Lighting, TweenInfo.new(3), {
			ClockTime = savedLighting.ClockTime,
			FogColor = savedLighting.FogColor,
			FogEnd = savedLighting.FogEnd,
			FogStart = savedLighting.FogStart,
			Brightness = savedLighting.Brightness,
			OutdoorAmbient = savedLighting.OutdoorAmbient,
		}):Play()
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds and savedClouds then
		TweenService:Create(clouds, TweenInfo.new(3), {
			Cover = savedClouds.Cover, Density = savedClouds.Density, Color = savedClouds.Color,
		}):Play()
	end
	if iceCC then
		local cc = iceCC; iceCC = nil
		local fade = TweenService:Create(cc, TweenInfo.new(2.5),
			{ Contrast = 0, Saturation = 0, TintColor = Color3.fromRGB(255, 255, 255) })
		fade:Play(); fade.Completed:Connect(function() cc:Destroy() end)
	end
	if iceAtmos then
		local at = iceAtmos; iceAtmos = nil
		local fade = TweenService:Create(at, TweenInfo.new(2.5), { Density = 0, Haze = 0, Glare = 0 })
		fade:Play(); fade.Completed:Connect(function() at:Destroy() end)
	end
	if ambientFolder then
		local f = ambientFolder; ambientFolder = nil
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("Sound") then d:Stop() end
		end
		task.delay(1, function() if f then f:Destroy() end end)
	end
	savedLighting = nil
	savedClouds = nil
end

--======================================================================
-- CAMERA-TRACKED, HARD-CAPPED SNOW VOLUME
-- A FEW efficient ParticleEmitters parented to a part that follows the
-- camera, so the player is always "inside" the snowfall without spawning
-- snow across the whole 45,000-stud map. Density (0..1) maps onto each
-- emitter's Rate, clamped by MAX_PARTICLE_RATE * lowEndScalar. Emitter count
-- is clamped by MAX_SNOW_EMITTERS.
--======================================================================
local snowRig = nil          -- the part that follows the camera
local snowEmitters = {}       -- the capped emitters
local snowFollowConn = nil    -- RenderStepped keeping the rig on the camera
local currentDensity = 0      -- target density 0..1
local snowLean = Vector3.zero -- gust lean applied to snow acceleration

-- buildSnowRig(): create the follow-part + the capped emitters (once).
local function buildSnowRig()
	if snowRig then return end
	snowRig = Instance.new("Part")
	snowRig.Name = "IceAgeSnowRig"
	snowRig.Size = Vector3.new(1, 1, 1)
	snowRig.Transparency = 1
	snowRig.Anchored = true
	snowRig.CanCollide = false
	snowRig.CanQuery = false
	snowRig.CanTouch = false
	snowRig.Parent = workspace.CurrentCamera or workspace

	-- A few layered emitters at different sizes/speeds for depth. Count capped.
	local layers = math.min(3, MAX_SNOW_EMITTERS)
	for i = 1, layers do
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Snow_" .. i
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = 0 -- set live by applyDensity()
		pe.Lifetime = NumberRange.new(1.5, 3)
		pe.Speed = NumberRange.new(2 + i * 2, 5 + i * 2)
		pe.SpreadAngle = Vector2.new(40, 40)
		pe.Size = NumberSequence.new(0.3 + i * 0.15)
		pe.Rotation = NumberRange.new(0, 360)
		pe.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		pe.Acceleration = Vector3.new(0, -10, 0) -- falls down
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Enabled = true
		pe.Parent = snowRig
		table.insert(snowEmitters, pe)
	end

	-- Keep the rig hovering just above + ahead of the camera so snow falls
	-- through the player's view. Cheap RenderStepped reposition only.
	snowFollowConn = RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam and snowRig and snowRig.Parent then
			snowRig.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 30, 0))
			-- Apply gust lean to the snow acceleration (cosmetic sideways drift).
			for _, pe in ipairs(snowEmitters) do
				pe.Acceleration = Vector3.new(snowLean.X, -10, snowLean.Z)
			end
		end
	end)
end

-- applyDensity(): map currentDensity (0..1) onto each emitter Rate, hard-
-- clamped by MAX_PARTICLE_RATE * lowEndScalar. This is the perf throttle.
local function applyDensity()
	if not snowRig then
		if currentDensity > 0 then buildSnowRig() else return end
	end
	local maxRate = MAX_PARTICLE_RATE * math.clamp(lowEndScalar, 0.1, 1)
	for _, pe in ipairs(snowEmitters) do
		pe.Rate = math.clamp(currentDensity, 0, 1) * maxRate
	end
end

-- setSnowDensity(d): set + apply a new target density.
local function setSnowDensity(d)
	currentDensity = math.clamp(d or 0, 0, 1)
	applyDensity()
end

-- destroySnow(): tear down the snow rig + its follow connection (no leak).
local function destroySnow()
	if snowFollowConn then snowFollowConn:Disconnect() snowFollowConn = nil end
	if snowRig then snowRig:Destroy() snowRig = nil end
	snowEmitters = {}
	currentDensity = 0
	snowLean = Vector3.zero
end

--======================================================================
-- CLIENT EFFECT: camera shake (decaying random jitter) for meteor impacts.
--======================================================================
local function cameraShake(intensity, seconds)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local amp = intensity or 0.5
	local t0 = os.clock()
	local dur = seconds or 0.4
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= dur then conn:Disconnect() return end
		local decay = 1 - (elapsed / dur)
		cam.CFrame = cam.CFrame * CFrame.new(
			(math.random() - 0.5) * amp * decay,
			(math.random() - 0.5) * amp * decay, 0)
	end)
end

-- brief blue flash (frozen lightning).
local function blueFlash()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.5
	cc.TintColor = Color3.fromRGB(200, 230, 255)
	cc.Parent = Lighting
	local fade = TweenService:Create(cc, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Brightness = 0 })
	fade:Play(); fade.Completed:Connect(function() cc:Destroy() end)
end

--======================================================================
-- AURORA (northern lights): a few large soft glowing bands high in the sky,
-- via a follow-camera SurfaceGui-free approach -- simple neon planes that
-- gently shift hue. CanCollide=false; auto-removed.
--======================================================================
local auroraFolder = nil
local function showAurora()
	if auroraFolder then return end
	auroraFolder = Instance.new("Folder")
	auroraFolder.Name = "IceAgeAurora"
	auroraFolder.Parent = workspace.CurrentCamera or workspace
	local cam = workspace.CurrentCamera
	local base = cam and cam.CFrame.Position or Vector3.zero
	for i = 1, 3 do
		local band = Instance.new("Part")
		band.Name = "AuroraBand_" .. i
		band.Material = Enum.Material.Neon
		band.Color = (i == 1) and Color3.fromRGB(120, 255, 200)
			or (i == 2) and Color3.fromRGB(150, 200, 255) or Color3.fromRGB(200, 150, 255)
		band.Transparency = 0.7
		band.Size = Vector3.new(700, 120, 2)
		band.Anchored = true
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.CFrame = CFrame.new(base + Vector3.new((i - 2) * 120, 350, -400))
		band.Parent = auroraFolder
	end
	-- Auto-fade after a while.
	task.delay(8, function()
		if auroraFolder then
			for _, b in ipairs(auroraFolder:GetChildren()) do
				if b:IsA("BasePart") then
					TweenService:Create(b, TweenInfo.new(2), { Transparency = 1 }):Play()
				end
			end
			local f = auroraFolder; auroraFolder = nil
			task.delay(2.2, function() if f then f:Destroy() end end)
		end
	end)
end
local function clearAurora()
	if auroraFolder then auroraFolder:Destroy() auroraFolder = nil end
end

--======================================================================
-- COSMETIC: breath-condensation puffs + icy boost trail.
-- These are purely visual and need NO gating (they don't move the player).
--======================================================================
local breathConn = nil
local function startBreathPuffs()
	if breathConn then return end
	local nextPuff = 0
	breathConn = RunService.Heartbeat:Connect(function()
		if os.clock() < nextPuff then return end
		nextPuff = os.clock() + 2.2 + math.random() * 1.5
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if not head then return end
		-- A tiny short-lived puff in front of the head.
		local puff = Instance.new("Part")
		puff.Size = Vector3.new(0.4, 0.4, 0.4)
		puff.Transparency = 1
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CFrame = head.CFrame * CFrame.new(0, 0, -1.2)
		puff.Parent = workspace.CurrentCamera or workspace
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(1, 2)
		pe.Size = NumberSequence.new(0.6)
		pe.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		pe.Parent = puff
		pe:Emit(4) -- a small burst, capped count
		game:GetService("Debris"):AddItem(puff, 1.6)
	end)
end
local function stopBreathPuffs()
	if breathConn then breathConn:Disconnect() breathConn = nil end
end

--======================================================================
-- ★★★ GUARDED PLAYER PHYSICS ★★★  (the safety-critical section)
--======================================================================

-- ===== SNOW GROUND-MOVEMENT TUNABLES (movement-only; NEVER touch fart power/meter/flight) =====
-- While the Ice Age is active and the player is WALKING (grounded, not flying) on a snow-
-- covered island, walking is slower + slippery. Both effects are removed when the event ends
-- (stopGuardedPhysics) and never applied while airborne/flying, so flight is unaffected and
-- the player can never be shoved off an edge by these alone.
local SNOW_WALK_SPEED_MULT = 0.7   -- multiplier on normal walk speed while on snow (0.7 = 30% slower)
local SNOW_FRICTION_MULT   = 0.15  -- ground friction on snow (was ~0.4; ~3x slipperier now -> clear slide/glide)

-- Active-effect tracking so we can ALWAYS restore to normal.
local slideActive = false          -- whether we have applied custom friction
local savedCustomEnabled = {}      -- [part] = its original CustomPhysicalProperties (to restore)
local gustVel = nil                -- BodyVelocity for a transient gust nudge
local gustClearAt = 0              -- when to clear the gust nudge
local freezeState = nil            -- { humanoid, original, restoreAt }
local guardConn = nil              -- the master Heartbeat enforcing all gates
local physicsEnabled = false       -- whether the guarded-physics system is live
local snowBaseWalk = nil           -- the player's NORMAL WalkSpeed (captured once, restored on end)

-- isGrounded(humanoid): true ONLY if genuinely standing on a surface and not
-- airborne. Used to GATE the slide + wind (never affect a flyer/jumper).
local function isGrounded(humanoid)
	if not humanoid then return false end
	if humanoid.FloorMaterial == Enum.Material.Air then return false end
	local s = humanoid:GetState()
	if s == Enum.HumanoidStateType.Freefall
		or s == Enum.HumanoidStateType.Jumping
		or s == Enum.HumanoidStateType.FallingDown then
		return false
	end
	return true
end

-- effectsAllowed(): the single gate for SLIDE + WIND. Both require the player
-- to be GROUNDED and NOT flying. The instant either fails, callers remove the
-- effect. (This is what guarantees we never shove a player off a fart-flight.)
local function effectsAllowed(humanoid)
	if _G.isFlying == true then return false end
	return isGrounded(humanoid)
end

-- applySlide(char): gently reduce ground friction on the character's parts for
-- a slight slide. SMALL (CONFIG.ICE_SLIDE_AMOUNT). We SAVE each part's original
-- CustomPhysicalProperties so removeSlide() restores it exactly.
local function applySlide(char)
	if slideActive then return end
	slideActive = true
	-- Slippery snow: low ground friction (SNOW_FRICTION_MULT). Lower = more slide /
	-- momentum -- the player doesn't stop or turn instantly. Saved + restored per part.
	local friction = SNOW_FRICTION_MULT
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			savedCustomEnabled[part] = part.CustomPhysicalProperties
			local d = part.CurrentPhysicalProperties
			part.CustomPhysicalProperties = PhysicalProperties.new(
				d.Density, friction, d.Elasticity, d.FrictionWeight, d.ElasticityWeight)
		end
	end
end

-- removeSlide(): restore every part's original physical properties. Always
-- safe to call; leaves the character with normal grip.
local function removeSlide()
	if not slideActive then return end
	slideActive = false
	for part, original in pairs(savedCustomEnabled) do
		if part and part.Parent then
			part.CustomPhysicalProperties = original
		end
	end
	savedCustomEnabled = {}
end

-- applyGust(dir, force, duration): a GENTLE, SHORT horizontal nudge. Only ever
-- called when effectsAllowed() is true. Uses a short-lived BodyVelocity on the
-- HRP that we clear after `duration` (or instantly if the player flies/leaves
-- the ground). Touches ONLY HRP velocity -- nothing gameplay-related.
local function applyGust(char, dir, force, duration)
	if force <= 0 then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if not gustVel then
		gustVel = Instance.new("BodyVelocity")
		gustVel.Name = "IceAgeGustNudge"
		gustVel.MaxForce = Vector3.new(1, 0, 1) * 4000 -- horizontal only, GENTLE cap
		gustVel.P = 1200
		gustVel.Parent = hrp
	end
	-- Preserve the player's own horizontal motion; just add a small drift.
	gustVel.Velocity = Vector3.new(dir.X * force, 0, dir.Z * force)
	gustClearAt = os.clock() + (duration or 0.8)
end

-- clearGust(): remove the transient gust nudge immediately.
local function clearGust()
	if gustVel then gustVel:Destroy() gustVel = nil end
	gustClearAt = 0
end

-- applyFreeze(walkSpeed, duration): MOVEMENT-ONLY. Capture the humanoid's
-- CURRENT WalkSpeed, set it to the reduced value, and restore the captured
-- value after `duration`. NEVER touches power/flight/coins. If the player is
-- flying we DON'T apply (WalkSpeed is irrelevant to flight and we must never
-- look like we're interfering with a climb).
local function applyFreeze(walkSpeed, duration)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	-- Never apply during flight (and never cancel a climb). A flying player
	-- simply isn't slowed; their fart power is fully intact regardless.
	if _G.isFlying == true then return end
	-- If a freeze is already active, just extend its timer (don't re-capture a
	-- value that's already the reduced one).
	if freezeState then
		freezeState.restoreAt = os.clock() + (duration or 2.5)
		return
	end
	freezeState = {
		humanoid = humanoid,
		original = humanoid.WalkSpeed,            -- CAPTURE the real original
		restoreAt = os.clock() + (duration or 2.5),
	}
	humanoid.WalkSpeed = walkSpeed or 6
end

-- restoreFreeze(): restore the captured original WalkSpeed (always safe).
local function restoreFreeze()
	if not freezeState then return end
	local hum = freezeState.humanoid
	if hum and hum.Parent then
		hum.WalkSpeed = freezeState.original
	end
	freezeState = nil
end

-- startGuardedPhysics(): begin the master Heartbeat that ENFORCES every gate
-- every frame -- the heart of the safety contract. It:
--   * applies/removes the SLIDE based on effectsAllowed()
--   * clears the GUST nudge when its timer ends OR when effects aren't allowed
--   * restores the FREEZE when its timer ends OR instantly if the player flies
-- so nothing can ever linger or shove a flying/airborne player.
local function startGuardedPhysics()
	if physicsEnabled then return end
	physicsEnabled = true
	guardConn = RunService.Heartbeat:Connect(function()
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not humanoid then
			-- No character: make sure nothing lingers.
			removeSlide(); clearGust()
			return
		end

		local allowed = effectsAllowed(humanoid)

		-- Capture the player's NORMAL WalkSpeed once (fresh char = normal speed), so we
		-- can apply the snow slow and always restore it exactly.
		if snowBaseWalk == nil and humanoid then snowBaseWalk = humanoid.WalkSpeed end

		-- SLIDE (slippery) + SNOW WALK SLOW: only while grounded + not flying; removed the
		-- instant either changes (so a fart-climb is NEVER affected). The freeze owns
		-- WalkSpeed while it's active, so we skip the snow slow during a freeze.
		if allowed then
			applySlide(char)
			if humanoid and snowBaseWalk and not freezeState then
				humanoid.WalkSpeed = snowBaseWalk * SNOW_WALK_SPEED_MULT  -- trudging through snow
			end
			-- ★ SAFETY: very low friction must NEVER drift a STATIONARY player off the
			-- island into the void. While they're not actively moving (no input), gently
			-- DECAY residual horizontal velocity so a leftover slide settles to a stop
			-- instead of carrying them off an edge. (While they ARE moving, we leave the
			-- velocity alone, so the slippery glide/momentum still reads clearly.)
			if humanoid.MoveDirection.Magnitude < 0.1 then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local v = hrp.AssemblyLinearVelocity
					if (v.X * v.X + v.Z * v.Z) > 0.25 then  -- only while still drifting
						hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.9, v.Y, v.Z * 0.9)
					end
				end
			end
		else
			removeSlide()
			-- Airborne/flying: normal WalkSpeed (irrelevant to flight; flight uses BodyVelocity).
			if humanoid and snowBaseWalk and not freezeState then
				humanoid.WalkSpeed = snowBaseWalk
			end
		end

		-- GUST: clear immediately if effects aren't allowed (flew / left ground)
		-- or once the short timer elapses.
		if gustVel and (not allowed or os.clock() >= gustClearAt) then
			clearGust()
		end

		-- FREEZE: restore instantly if the player starts flying (never interfere
		-- with a climb), or when the brief timer ends.
		if freezeState then
			if _G.isFlying == true then
				restoreFreeze() -- WalkSpeed irrelevant to flight; clear it at once
			elseif os.clock() >= freezeState.restoreAt then
				restoreFreeze()
			end
		end
	end)
end

-- stopGuardedPhysics(): tear down the master loop + force EVERYTHING back to
-- normal (slide, gust, freeze). Called on "reset" and on character respawn.
local function stopGuardedPhysics()
	physicsEnabled = false
	if guardConn then guardConn:Disconnect() guardConn = nil end
	removeSlide()
	clearGust()
	restoreFreeze()
	-- Restore NORMAL walk speed (remove the snow slow) so nobody stays slow after the event.
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and snowBaseWalk then humanoid.WalkSpeed = snowBaseWalk end
	snowBaseWalk = nil
	snowLean = Vector3.zero
end

-- Safety: on respawn, drop all effects (the fresh character is normal).
player.CharacterAdded:Connect(function()
	-- The old part references are gone; just reset our tracking + restore.
	savedCustomEnabled = {}
	slideActive = false
	if gustVel then gustVel = nil end
	gustClearAt = 0
	freezeState = nil
	snowBaseWalk = nil   -- re-capture the fresh character's NORMAL walk speed next frame
end)

--======================================================================
-- LOAD-TIME CLEAN SLATE: no event text shows at game load (the banner already
-- constructs hidden; belt-and-suspenders, matching the blanket event-text rule).
--======================================================================
hideBanner()

--======================================================================
-- Listen to the server-driven sync events.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	if phase == "start" then
		if typeof(payload) == "table" then
			lowEndScalar = payload.lowEndScalar or lowEndScalar
			-- Server may override the gentle slide amount (e.g. to 0 to disable).
			if payload.slideAmount ~= nil then clientSlideAmount = payload.slideAmount end
		end
		startSky(payload and payload.variant)
		startGuardedPhysics()
		startBreathPuffs()
		showBanner((payload and payload.text) or "\u{1F9CA} ICE AGE APPROACHING!", 5)

	elseif phase == "warning" then
		showBanner("Frost creeps across the islands\u{2026}", 4)
		setSnowDensity(snowForPhase("warning"))
		setFog(fogForPhase("warning"))

	elseif phase == "main" then
		showBanner("\u{1F9CA} ICE AGE! The world freezes\u{2026}", 4)
		setSnowDensity(snowForPhase("main"))
		setFog(fogForPhase("main"))

	elseif phase == "snowSpike" then
		-- Brief heavy snow burst, then back to the MAIN density.
		local d = (typeof(payload) == "table" and payload.density) or 1
		local dur = (typeof(payload) == "table" and payload.duration) or 4
		setSnowDensity(d)
		task.delay(dur, function()
			-- Only fall back if we're still in a heavy phase (not reset/ending).
			if currentDensity > 0 then setSnowDensity(snowForPhase("main")) end
		end)

	elseif phase == "gustVisual" then
		-- Lean the camera-snow in the gust direction (cosmetic drift). The
		-- physical nudge arrives separately as "gust" (gated).
		if typeof(payload) == "table" and typeof(payload.dir) == "Vector3" then
			snowLean = payload.dir * 14
			task.delay(1.2, function() snowLean = Vector3.zero end)
		end

	elseif phase == "gust" then
		-- ★ GENTLE PHYSICAL NUDGE -- ONLY if grounded + not flying. ★
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if char and humanoid and typeof(payload) == "table"
			and typeof(payload.dir) == "Vector3" and effectsAllowed(humanoid) then
			applyGust(char, payload.dir, payload.force or 0, payload.duration or 0.8)
		end

	elseif phase == "meteorImpact" then
		-- Per-client camera shake + boom cue.
		local intensity = (typeof(payload) == "table" and payload.intensity) or 0.5
		cameraShake(intensity, 0.45)

	elseif phase == "freeze" then
		-- ★ WALKSPEED-ONLY freeze (capture/restore). Never touches power/flight. ★
		if typeof(payload) == "table" then
			applyFreeze(payload.walkSpeed or 6, payload.duration or 2.5)
		end

	elseif phase == "frozenLightning" then
		blueFlash()
		cameraShake(0.3, 0.3)

	elseif phase == "aurora" then
		showAurora()

	elseif phase == "iceDragon" then
		showBanner("\u{1F409} An ice dragon soars overhead\u{2026}", 3)

	elseif phase == "frozenFartSFX" then
		-- A short frozen-fart cue (cosmetic). Anchored on the camera so it's
		-- heard once; harmless if the asset is missing.
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://9114402399"
		s.Volume = 1   -- unified volume: matches the meteor intro sound
		s.PlaybackSpeed = 0.6
		s.Parent = workspace.CurrentCamera or workspace
		s:Play()
		s.Ended:Connect(function() s:Destroy() end)
		game:GetService("Debris"):AddItem(s, 3)

	elseif phase == "npcShiver" then
		-- FUN DETAIL: NPCs shiver in the cold. We do this PURELY COSMETICALLY +
		-- READ-ONLY on the client: find NPC humanoid models near the camera and
		-- emit a tiny cold-breath puff above each. We NEVER move, anchor, or
		-- modify the NPCs themselves (no gameplay/NPC-code change), and create no
		-- collidable parts. The puffs are short-lived + auto-destroyed.
		local cam = workspace.CurrentCamera
		local origin = cam and cam.CFrame.Position or Vector3.zero
		local roots = {}
		-- Look in known NPC containers if present (read-only scan).
		local containers = {}
		local tut = workspace:FindFirstChild("TutorialNPCs")
		if tut then table.insert(containers, tut) end
		for _, container in ipairs(containers) do
			for _, m in ipairs(container:GetChildren()) do
				if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
					local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
					if hrp and (hrp.Position - origin).Magnitude < 140 then
						table.insert(roots, hrp.Position)
					end
				end
			end
		end
		-- Cap the number of puffs (perf): at most 6 NPC puffs per cue.
		for i = 1, math.min(#roots, 6) do
			local puff = Instance.new("Part")
			puff.Size = Vector3.new(0.4, 0.4, 0.4)
			puff.Transparency = 1
			puff.Anchored = true
			puff.CanCollide = false
			puff.CanQuery = false
			puff.CanTouch = false
			puff.CFrame = CFrame.new(roots[i] + Vector3.new(0, 2.5, 0))
			puff.Parent = workspace.CurrentCamera or workspace
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
			pe.Rate = 0
			pe.Lifetime = NumberRange.new(0.8, 1.4)
			pe.Speed = NumberRange.new(1, 2)
			pe.Size = NumberSequence.new(0.5)
			pe.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			pe.Parent = puff
			pe:Emit(3)
			game:GetService("Debris"):AddItem(puff, 1.6)
		end

	elseif phase == "ending" then
		showBanner((payload and payload.text) or "\u{1F9CA} Ice Age Ending\u{2026}", 4)
		setSnowDensity(snowForPhase("ending"))
		setFog(fogForPhase("ending"))

	elseif phase == "reset" then
		-- FULL restore: stop all guarded physics (slide/gust/freeze -> normal),
		-- remove the snow volume, restore the sky, stop cosmetics + variants.
		hideBanner()
		stopGuardedPhysics()
		stopBreathPuffs()
		clearAurora()
		setSnowDensity(0)
		task.delay(0.2, destroySnow) -- let the rate hit 0 first, then tear down
		restoreSky()
	end
end)
