--======================================================================
-- LandingImpact.client.luau   -- LocalScript, StarterPlayer > StarterPlayerScripts
--======================================================================
-- WHAT IT DOES. Land after a real fall and the ground answers: a puff of dust the
-- colour of whatever you hit, a thud that drops in pitch the harder you came down,
-- a short camera jolt, and a pair of footprints pressed where you touched.
--
-- IT IS ALL ONE NUMBER. Everything below is a curve on `t` -- a 0..1 "how hard was
-- that", taken from your PEAK downward speed during the fall. Dust count, dust
-- size, volume, pitch and shake are all just functions of t. That is what keeps a
-- small landing from feeling like a scripted event and a huge one from feeling
-- identical to a small one: there is no threshold where the effect switches on, it
-- grows continuously with the drop.
--
-- THE DUST IS THE COLOUR OF THE FLOOR. A raycast reads the part you actually
-- landed on and tints the dust to match, so this needs no per-area table: grass
-- throws green-brown, metal throws grey, snow throws white. A fixed dust colour
-- looks wrong everywhere except the one place it was picked for.
--
-- SETUP: none. Drop it in and it runs. No tags, no remotes, no dependencies beyond
-- stock Roblox services -- every knob worth touching is in CONFIG below.
--======================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Debris       = game:GetService("Debris")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ---- WHAT COUNTS AS A FALL ----
	-- MIN_SPEED is the whole feel of this. It MUST sit above the speed a normal
	-- jump lands at, or you kick up dust every hop and it reads as a bug rather
	-- than as weight. Check your game: a default jump lands near 50, but higher
	-- JumpPower or lower gravity pushes that up. MAX_SPEED is where the effect
	-- maxes out -- past it everything clamps, so a 40,000-stud drop and a 4,000
	-- stud drop both bottom out at "enormous" instead of one being 10x sillier.
	MIN_SPEED    = 95,    -- studs/sec down: below this a landing is silent
	MAX_SPEED    = 260,   -- studs/sec: full-strength effect at or above this
	-- A landing only counts if you were airborne for a moment. Without this every
	-- respawn and teleport slams the camera, because the character technically
	-- "arrives" at speed.
	MIN_AIR_TIME = 0.35,  -- seconds

	-- ---- SOUND ----
	-- Pitch matters more than volume here. The same sample played LOWER reads as
	-- bigger and heavier, which is what makes a huge landing sound like a
	-- different event instead of a louder small one. Keep the pitch curve.
	SOUND_ID     = "rbxassetid://5801257793", -- low boom
	VOLUME_MIN   = 0.25,  VOLUME_MAX   = 1.00,
	PITCH_LIGHT  = 1.45,  PITCH_HEAVY  = 0.70,  -- light = quick high tap, heavy = deep slow boom
	SOUND_RANGE  = 220,

	-- ---- DUST ----
	DUST_TEXTURE = "rbxassetid://243664672", -- stock soft smoke puff
	DUST_MIN     = 9,     DUST_MAX     = 55,   -- particles emitted at t=0 / t=1
	DUST_FALLBACK= Color3.fromRGB(150, 140, 125), -- if the floor raycast finds nothing

	-- ---- CAMERA ----
	SHAKE_FROM   = 0.30,  -- t below this does not move the screen at all
	SHAKE_SECS   = 0.30,
	SHAKE_MAX    = 2.2,   -- degrees of jolt at t=1

	-- ---- FOOTPRINTS ----
	FOOTPRINTS   = true,  -- set false for a dust-and-thud-only build
	STEP_DIST    = 2.6,   -- studs between prints -- about one stride at WalkSpeed 16
	FOOT_FADE    = 2.6,   -- seconds to fade out
	FOOT_WIDTH   = 0.55,
	FOOT_LEN     = 1.05,
	FOOT_SPREAD  = 0.55,  -- studs either side of centre, so left/right do not overlap
	FOOT_ALPHA   = 0.35,  -- starting transparency; opaque prints look like paint, not pressure
	FOOT_DARK    = 0.65,  -- how far toward black from the floor's own colour
	MAX_PRINTS   = 40,    -- hard cap: without it a long walk quietly spawns hundreds of parts
}

--======================================================================
-- SHARED RAYCAST -- reused for both the floor colour and each footprint.
--======================================================================
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
ray.IgnoreWater = true

local function groundUnder(char, from, depth)
	ray.FilterDescendantsInstances = { char }
	return Workspace:Raycast(from, Vector3.new(0, -(depth or 12), 0), ray)
end

--======================================================================
-- FOOTPRINTS
--
-- Pressed, not painted: each print is a DARKER version of the floor it sits on, so
-- it reads as compressed earth rather than a black sticker.
--======================================================================
local prints = {} -- oldest first; the cap is enforced by destroying prints[1]

local function stampFoot(char, hrp, sign)
	if not CONFIG.FOOTPRINTS then return end
	local hit = groundUnder(char, hrp.Position, 8)
	if not (hit and hit.Instance and hit.Instance:IsA("BasePart")) then return end

	-- Lay the print FLAT ON THE SURFACE, not flat on the world. On any slope a
	-- world-level print sinks half into the hillside and floats off the other half.
	local up    = hit.Normal
	local right = hrp.CFrame.LookVector:Cross(up)
	if right.Magnitude < 0.01 then return end -- facing straight along the normal: no sane orientation
	right = right.Unit
	local fwd = up:Cross(right).Unit

	local pos = hit.Position + up * 0.03 + right * (CONFIG.FOOT_SPREAD * sign) -- 0.03 up, or it z-fights

	local p = Instance.new("Part")
	p.Name         = "Footprint"
	p.Size         = Vector3.new(CONFIG.FOOT_WIDTH, 0.05, CONFIG.FOOT_LEN)
	p.CFrame       = CFrame.fromMatrix(pos, right, up, -fwd)
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false -- so the NEXT print's raycast does not land on THIS one and stack upward forever
	p.CanTouch     = false
	p.CastShadow   = false
	p.Material     = Enum.Material.SmoothPlastic
	p.Color        = hit.Instance.Color:Lerp(Color3.new(0, 0, 0), CONFIG.FOOT_DARK)
	p.Transparency = CONFIG.FOOT_ALPHA
	p.Parent       = Workspace

	local m = Instance.new("SpecialMesh") -- squashed sphere = a soft oval sole; a bare block reads as a domino
	m.MeshType = Enum.MeshType.Sphere
	m.Parent   = p

	prints[#prints + 1] = p
	if #prints > CONFIG.MAX_PRINTS then
		local oldest = table.remove(prints, 1)
		if oldest then oldest:Destroy() end
	end

	TweenService:Create(p, TweenInfo.new(CONFIG.FOOT_FADE, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(p, CONFIG.FOOT_FADE + 0.2)
end

--======================================================================
-- DUST
--
-- One burst from a temporary anchored part at the feet -- NOT an emitter parented
-- to the character. A burst that follows you as you walk away is not dust, it is a
-- jetpack.
--======================================================================
local function puff(pos, color, t)
	local anchor = Instance.new("Part")
	anchor.Name         = "LandingDust"
	anchor.Size         = Vector3.new(0.6, 0.2, 0.6) -- thin plate: an emitter fires from the whole VOLUME of a
	anchor.Anchored     = true                       -- part, so a big cube sprays dust from inside your shins
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.CastShadow   = false
	anchor.Transparency = 1
	anchor.CFrame       = CFrame.new(pos) -- unrotated on purpose, so "up" means world up
	anchor.Parent       = Workspace

	local e = Instance.new("ParticleEmitter")
	e.Texture        = CONFIG.DUST_TEXTURE
	e.Color          = ColorSequence.new(color)
	e.Orientation    = Enum.ParticleOrientation.FacingCamera -- same thickness from any angle
	e.LightInfluence = 0.6
	e.Rotation       = NumberRange.new(0, 360) -- or the ring looks stamped from a mould
	e.RotSpeed       = NumberRange.new(-40, 40)

	-- Dust goes OUT, not up. Real impact dust is thrown sideways along the ground
	-- and only drifts upward as it slows; a plume that shoots straight up reads as
	-- a smoke grenade rather than as something hitting the floor.
	e.SpreadAngle  = Vector2.new(85, 85)
	e.Speed        = NumberRange.new(6 + 22 * t, 12 + 40 * t)
	e.Acceleration = Vector3.new(0, 5, 0) -- gentle lift as it slows, so it billows instead of dropping flat
	e.Drag         = 3.5                  -- and dies quickly, which is what makes it read as heavy dust

	e.Lifetime = NumberRange.new(0.5, 0.9 + 0.7 * t)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2 + 4.5 * t),
		NumberSequenceKeypoint.new(1, 3.5 + 11 * t), -- expands as it disperses
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rate    = 0
	e.Enabled = false
	e.Parent  = anchor

	e:Emit(math.floor(CONFIG.DUST_MIN + (CONFIG.DUST_MAX - CONFIG.DUST_MIN) * t))
	Debris:AddItem(anchor, 3) -- outlives the puffs, then removes itself: nothing accumulates
end

--======================================================================
-- THUD
--======================================================================
local function thud(hrp, t)
	local s = Instance.new("Sound")
	s.SoundId            = CONFIG.SOUND_ID
	s.Volume             = CONFIG.VOLUME_MIN + (CONFIG.VOLUME_MAX - CONFIG.VOLUME_MIN) * t
	s.PlaybackSpeed      = CONFIG.PITCH_LIGHT + (CONFIG.PITCH_HEAVY - CONFIG.PITCH_LIGHT) * t
	s.RollOffMaxDistance = CONFIG.SOUND_RANGE
	s.Parent             = hrp
	s:Play()
	Debris:AddItem(s, 6)
end

--======================================================================
-- CAMERA
--
-- The offset is written each frame and DECAYS to zero, then simply stops -- it
-- never restores a snapshot. Anything that snapshots the camera and puts it back
-- fights the player's own mouse look and stutters. Fading to nothing leaves the
-- camera exactly where the player pointed it.
--======================================================================
local function shake(t)
	if t < CONFIG.SHAKE_FROM then return end
	-- Never fight a cinematic for the camera. Intro.client.luau flies the camera
	-- through the tower on first join and SpawnCamera yields to the same flag; a
	-- landing jolt during that reads as a bug, not as weight.
	if _G.introPlaying then return end
	local mag = CONFIG.SHAKE_MAX * t
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < CONFIG.SHAKE_SECS do
			local cam = Workspace.CurrentCamera
			if not cam then return end
			local left = 1 - (os.clock() - t0) / CONFIG.SHAKE_SECS -- linear fade to zero
			local m = math.rad(mag * left)
			cam.CFrame = cam.CFrame * CFrame.Angles(
				(math.random() - 0.5) * m,
				(math.random() - 0.5) * m,
				(math.random() - 0.5) * m * 0.5
			)
			RunService.RenderStepped:Wait()
		end
	end)
end

--======================================================================
-- DETECTION
--
-- The touchdown FRAME is useless for measuring the fall -- the collision has
-- already killed the velocity by the time FloorMaterial changes. So speed is
-- sampled continuously while airborne and the PEAK downward value is kept; that
-- peak is what the landing is scored on.
--======================================================================
local function watch(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) then return end

	local airborne, airStart, peakFall = false, 0, 0
	local wasAir = hum.FloorMaterial == Enum.Material.Air

	-- Prints are spaced by DISTANCE TRAVELLED, not by a timer. A timer drops them
	-- in a heap while you stand still and spreads them miles apart under a speed
	-- boost; distance gives a real stride that stays correct at any WalkSpeed.
	local walked, lastPos, footSign = 0, hrp.Position, 1

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not (char.Parent and hrp.Parent and hum.Parent) then conn:Disconnect(); return end

		local inAir = hum.FloorMaterial == Enum.Material.Air
		local here  = hrp.Position

		-- ---- FOOTPRINTS: only while actually walking on the ground ----
		if inAir then
			lastPos = here -- do not bank distance covered in the air, or you touch down and instantly
			               -- stamp a print for every stud you flew
		else
			local flat = Vector3.new(here.X - lastPos.X, 0, here.Z - lastPos.Z) -- horizontal only:
			lastPos = here                                                       -- riding a lift is not walking
			walked += flat.Magnitude
			if walked >= CONFIG.STEP_DIST then
				walked = 0
				stampFoot(char, hrp, footSign)
				footSign = -footSign -- left, right, left...
			end
		end

		if inAir then
			if not airborne then
				airborne, airStart, peakFall = true, os.clock(), 0
			end
			-- Only DOWNWARD motion counts. A flight that rose 40,000 studs and then
			-- drifted gently down is a soft landing, not a huge one.
			local vy = hrp.AssemblyLinearVelocity.Y
			if vy < 0 and -vy > peakFall then peakFall = -vy end

		elseif wasAir then
			-- ---- TOUCHDOWN ----
			local airTime = os.clock() - airStart
			-- `not _G.introPlaying`: the first-join cinematic joyrides the character
			-- through the tower, and every touchdown along the way would fire a full
			-- dust-and-thud over the top of it.
			if airborne and not _G.introPlaying
				and airTime >= CONFIG.MIN_AIR_TIME and peakFall >= CONFIG.MIN_SPEED then
				local t = math.clamp(
					(peakFall - CONFIG.MIN_SPEED) / (CONFIG.MAX_SPEED - CONFIG.MIN_SPEED), 0, 1)

				-- At the FEET, not the root: the root sits at chest height, and dust
				-- from your chest is not dust, it is a chest wound.
				local feet = hrp.Position - Vector3.new(0, hrp.Size.Y * 0.5 + 1.4, 0)
				local hit  = groundUnder(char, hrp.Position, 12)
				local col  = (hit and hit.Instance and hit.Instance:IsA("BasePart"))
					and hit.Instance.Color or CONFIG.DUST_FALLBACK

				puff(feet, col, t)
				thud(hrp, t)
				shake(t)
				-- Both feet, where you actually came down -- you landed on two.
				stampFoot(char, hrp, 1)
				stampFoot(char, hrp, -1)
			end
			airborne, peakFall, walked = false, 0, 0 -- walked reset so the landing does not
		end                                          -- immediately trigger a stray third print

		wasAir = inAir
	end)
end

if player.Character then task.spawn(watch, player.Character) end
player.CharacterAdded:Connect(function(c) task.spawn(watch, c) end)

print(("[LandingImpact] ready -- dust + thud + shake over %d..%d studs/s, footprints %s")
	:format(CONFIG.MIN_SPEED, CONFIG.MAX_SPEED, CONFIG.FOOTPRINTS and "on" or "off"))
