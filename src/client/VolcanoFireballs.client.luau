--======================================================================
-- VolcanoFireballs.client.luau  (LocalScript)
--======================================================================
-- FALLING FIREBALLS over the top of the tower. The volcano on the summit island is in the
-- EARLY stages of waking up, so it lobs the occasional fireball out of the crater instead
-- of erupting -- and those rain down through the last crossings, where you fly around them.
--
-- WHERE: from slot FIRST_SLOT up to the summit -- by default the final TWO crossings.
--
-- IT GETS WORSE AS YOU CLIMB. Down at slot 11 it is a few stray embers falling past you;
-- by the run into the summit it is a steady fall. Both the spawn rate and the cap on how
-- many can be in the air at once are interpolated on your ALTITUDE (see intensity()), so
-- the pressure builds across the last two crossings instead of being flat. The calm start
-- is what makes the top read as intense -- if it were this heavy the whole way it would
-- just be noise.
--
-- MOST FALL PAST THE ISLANDS, SOME LAND ON THEM. Only about ISLAND_HIT_CHANCE of the rain
-- is allowed to be positioned over an island; the rest is deliberately steered into open
-- air. One that does come down on an island RAYCASTS to the real surface, lands on it,
-- flashes, and cools off over a couple of seconds leaving a scorch mark. Nothing ever
-- sinks through the ground -- that was the first version's bug and the landing test is
-- what replaced it.
--
-- STANDING ON AN ISLAND MAKES YOU SAFE. Grounded (Humanoid.FloorMaterial is anything but
-- Air) means fireballs pass you by: no hit, no shove. The hazard belongs to the CROSSING,
-- and being knocked around on the island you just fought your way to would read as the
-- game cheating. It also removes the worst case outright -- being shoved off the summit
-- and having to fly the whole gap again.
--
-- WHY CLIENT-SIDE, LIKE THE BUBBLES. Fireballs are anchored, non-collidable and moved by
-- code only -- they never touch physics and never touch the character. Each player gets
-- their own set, so nobody dodges a fireball that lag has already moved, and two players
-- are never handed the same unfair spawn. Identical to the argument Bubbles.client.luau
-- makes for the gas and coin pickups, which share this airspace.
--
-- THE HIT DOES NOT COST FUEL, AND THAT IS A BALANCE DECISION. Every crossing is solved to
-- clear its gap on one tank with 8% to spare (IslandOrder's SLOT_POS note, FlightTuning's
-- MARGIN). Anything that drains gas or pushes you DOWN eats into that 8%, and on a wall
-- crossing that turns a fair attempt into an unwinnable one -- doubly so here, since this
-- hazard sits on the two hardest gaps in the game. So a hit spends the one currency the
-- margin can absorb: it shoves you SIDEWAYS and costs you the seconds to get back on line.
-- To make it bite harder, see the marked line in onHit().
--
-- THE KNOCKBACK GOES THROUGH _G, because BottomHUD's flight loop rewrites the BodyVelocity
-- every single frame -- a velocity set on the character here would be erased before the
-- next render. _G.fireballKnock is read and added by that loop, exactly like
-- _G.windstormDir and _G.thunderWindVec already are. That hook in BottomHUD.client.luau
-- is the other half of this file.
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local player      = Players.LocalPlayer

--======================================================================
-- TUNING -- "nothing crazy" lives in these numbers.
--======================================================================
-- FIRST_SLOT 11 = the last three islands (11, 12, 13), so the final TWO crossings.
-- Set it to 10 for three. Below 10 the hazard starts on islands the volcano is not
-- visible from, which reads as fireballs coming out of clear sky.
local FIRST_SLOT   = 11

-- DISTANCES SCALED x0.455 WITH THE TOWER; SPEEDS DELIBERATELY DID NOT.
--
-- SPAWN_ABOVE went 700 -> 318 because it is a vertical distance and 700 was taller than the
-- first four gaps. FALL_SPEED and DRIFT are back at their original 150 and 22, because the
-- PLAYER's climb speed is also back to its original value -- a fireball is only dangerous
-- relative to how fast you are moving, and that ratio is what makes a dodge feel the same.
-- (An interim pass scaled these to 68 and 10 to match a slowed-down player; that player is
-- gone.)
--
-- WARNING TIME therefore scales rather than staying fixed: SPAWN_ABOVE / FALL_SPEED is now
-- 2.1 s where it was 4.7 s. That is correct -- the whole crossing is 2.2x shorter, so 2.1 s
-- is the same FRACTION of a flight it always was.
--
-- SPAWN_RADIUS is HORIZONTAL and stays: the X/Z spiral did not move, and neither did the
-- player or the islands.
local FALL_SPEED   = 150    -- studs/sec, CONSTANT -- see the note above spawnRain()
local SPAWN_ABOVE  = 318    -- studs above you one appears => 318/150 = 2.1s of warning
local SPAWN_RADIUS = 260    -- horizontal scatter around you; wider = feels sparser
local DRIFT        = 22     -- sideways drift, so they fall on a slant instead of straight

-- INTENSITY RAMP: calm at the bottom of the band, heaviest on the summit run.
-- THE PEAK IS THE OLD FLAT RATE. 0.70s / 14 alive is exactly what the first version ran
-- everywhere, and it was the right density -- it was just on from the first moment, which
-- is what made it feel like too much. Now you only meet it on the final approach, and the
-- climb up to it is the calm half.
-- INTERVALS SCALED x0.455 (were 1.90 and 0.70). Flights are 2.2x shorter in wall-clock, so
-- a fixed interval would have more than halved the number of fireballs you actually meet on
-- a crossing. Scaling the interval keeps the DENSITY PER CROSSING identical, which is the
-- thing the ramp was tuned for -- not the rate per second.
local SPAWN_EVERY_CALM = 0.86   -- seconds between spawns at slot FIRST_SLOT
local SPAWN_EVERY_PEAK = 0.32   -- ...and at the summit
local MAX_ALIVE_CALM   = 3      -- how many may be in the air at once, low down
local MAX_ALIVE_PEAK   = 14     -- ...and at the top

local ISLAND_HIT_CHANCE = 0.22  -- fraction of rain allowed to come down ON an island

local BALL_SIZE    = 12     -- diameter
local HIT_RADIUS   = 11     -- centre-to-centre; a little tighter than the visual ball
-- KNOCK is a SPEED and stays at its original 95. The three times below scaled x0.455
-- (were 0.70 / 3.00 / 0.35) along with every other wall-clock duration.
local KNOCK        = 95     -- studs/sec sideways jolt while the knockdown plays
local KNOCK_DECAY  = 0.32   -- seconds for that jolt to fade to nothing
local IFRAMES      = 1.37   -- seconds of immunity after a hit -- must outlast the teleport
local KNOCKDOWN_DELAY = 0.16 -- seconds between the impact and being sent back down

-- ---- crater eruptions ----
local ERUPT_MIN    = 2      -- fireballs thrown per eruption...
local ERUPT_MAX    = 4      -- ...picked fresh each time, so no two look alike

local LAND_FADE    = 2.60   -- seconds a landed fireball takes to burn out
local SCORCH_FADE  = 7.00   -- ...and how long its mark lingers after that

-- ---- crater launches: the ones that visibly come OUT of Volcanospot ----
-- THE LOB, UNDER THE SAME RULE AS EVERYTHING ELSE: distances x0.455, times x0.455, speeds
-- unchanged -- and ACCELERATIONS therefore x1/0.455, because an acceleration is distance
-- over time SQUARED and only one of those two scalings cancels.
--
--   LAUNCH_RANGE  7000 -> 3185   vertical distance
--   CULL_BELOW    1600 ->  728   vertical distance
--   LAUNCH_UP      300            SPEED -- unchanged
--   ARC_GRAVITY    105 ->  231    ACCELERATION -- x1/0.455
--   LAUNCH_EVERY  3.00 -> 1.37   time
--   ISLAND_CLEAR   140            horizontal clearance; the island did not shrink
--
-- THE ARC STAYS SOLVED. Clearance depends on T = 2 * LAUNCH_UP / ARC_GRAVITY, which is a
-- TIME and so had to fall to 2.60 s (from 5.71). Raising gravity while holding launch speed
-- is exactly what produces that -- the lob is the same height and speed off the lip, it just
-- comes back down sooner. `outward` is then derived from the island's unchanged radius over
-- that shorter T, so it rises automatically and every lob still clears the island by
-- construction. Scaling only one of the pair would have silently broken it.
local LAUNCH_EVERY = 1.37   -- seconds between lobs while the crater is in range (x0.455)
local LAUNCH_RANGE = 3185   -- only lob when you are near enough to actually see it happen
local LAUNCH_UP    = 300    -- initial upward speed out of the throat (a SPEED -- unscaled)
local ARC_GRAVITY  = 231    -- pull on a lobbed fireball, until it reaches FALL_SPEED
local ISLAND_CLEAR = 140    -- studs of daylight to leave between a fireball and the volcano
local CULL_BELOW   = 728    -- studs below you one is dropped (it is long out of sight)

local BAND_BOTTOM = IslandOrder.SLOT_POS[FIRST_SLOT].Y - 200
local BAND_TOP_Y  = IslandOrder.SLOT_POS[IslandOrder.COUNT].Y
local BAND_TOP    = BAND_TOP_Y + 1400

-- 0 at the bottom of the band, 1 at the summit. Everything that scales with "how bad is
-- it right now" reads this.
local function intensity(y)
	return math.clamp((y - BAND_BOTTOM) / math.max(1, BAND_TOP_Y - BAND_BOTTOM), 0, 1)
end
local function lerp(a, b, t) return a + (b - a) * t end

--======================================================================
-- WORLD GEOMETRY, published by VolcanoFireballs.server.luau.
--
-- None of this can be measured on the client: with StreamingEnabled the summit's parts are
-- not replicated while the player is still down at slot 11, and a model whose parts have
-- not arrived reports a zero-size box at the origin. The server always has the whole
-- Workspace, so it measures and publishes; this side just reads.
--======================================================================
local SUMMIT_FALLBACK = IslandOrder.SLOT_POS[IslandOrder.COUNT] + Vector3.new(0, 260, 0)
local posValue    = ReplicatedStorage:WaitForChild("VolcanoSpotPos", 30)
local centerValue = ReplicatedStorage:WaitForChild("VolcanoIslandCenter", 30)
local sizeValue   = ReplicatedStorage:WaitForChild("VolcanoIslandSize", 30)
local boundsFolder = ReplicatedStorage:WaitForChild("VolcanoIslandBounds", 30)

-- The knockdown. Shared with the "Return to <island>" button on purpose -- see onHit().
local ReturnToIslandEvent = ReplicatedStorage:FindFirstChild("ReturnToIslandEvent")
	or ReplicatedStorage:WaitForChild("ReturnToIslandEvent", 30)

local function craterPos()
	if posValue and posValue.Value.Magnitude > 1 then return posValue.Value end
	return SUMMIT_FALLBACK
end

-- Fallbacks used only until the server has measured the real models. Generous on purpose:
-- guessing too BIG just keeps fireballs a little further out, while guessing too small
-- puts them back inside the rock.
local FALLBACK_RADIUS = 420
local FALLBACK_HALF_H = 260

-- The VOLCANO island: a no-go box, because a fireball must never be seen passing through
-- the island its own crater sits on. Returns centre, horizontal radius, top Y, bottom Y.
local function volcanoBounds()
	if centerValue and sizeValue and sizeValue.Value.Magnitude > 1 then
		local c, s = centerValue.Value, sizeValue.Value
		return c, math.max(s.X, s.Z) * 0.5, c.Y + s.Y * 0.5, c.Y - s.Y * 0.5
	end
	local c = IslandOrder.SLOT_POS[IslandOrder.COUNT]
	return c, FALLBACK_RADIUS, c.Y + FALLBACK_HALF_H, c.Y - FALLBACK_HALF_H
end

local function insideVolcano(pos)
	local c, r, top, bottom = volcanoBounds()
	if pos.Y > top or pos.Y < bottom then return false end
	local dx, dz = pos.X - c.X, pos.Z - c.Z
	return (dx * dx + dz * dz) <= r * r
end

-- Every island in the hazard's reach, so a falling fireball knows when there is ground
-- under it. Refreshed on a slow timer -- the server republishes every 5s and these only
-- change if the layout is re-tuned.
local islands = {}
local function refreshIslands()
	if not boundsFolder then return end
	local out = {}
	for slot = 1, IslandOrder.COUNT do
		local c = boundsFolder:GetAttribute("Center_" .. slot)
		local s = boundsFolder:GetAttribute("Size_" .. slot)
		if typeof(c) == "Vector3" and typeof(s) == "Vector3" and s.Magnitude > 1 then
			table.insert(out, {
				center = c,
				radius = math.max(s.X, s.Z) * 0.5,
				top    = c.Y + s.Y * 0.5,
				bottom = c.Y - s.Y * 0.5,
			})
		end
	end
	if #out > 0 then islands = out end
end
refreshIslands()
task.spawn(function()
	while true do
		task.wait(5)
		refreshIslands()
	end
end)

-- The island a point would come down on, if any.
local function islandUnder(pos)
	for _, isl in ipairs(islands) do
		if pos.Y > isl.bottom then
			local dx, dz = pos.X - isl.center.X, pos.Z - isl.center.Z
			if (dx * dx + dz * dz) <= isl.radius * isl.radius then return isl end
		end
	end
	return nil
end

--======================================================================
-- The fireballs live in one client-only folder, so nothing else in the world has to know
-- about them and a single Destroy cleans the whole hazard up.
--======================================================================
local bin = Instance.new("Folder")
bin.Name = "VolcanoFireballs"
bin.Parent = Workspace

local alive = {}          -- array of { part, vel, arc, dieAt, landed, fadeAt, light, emitters }

_G.fireballKnock = nil    -- the interface BottomHUD reads. nil = no shove, normal flight.

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { bin }
rayParams.IgnoreWater = true

local function refreshRayFilter()
	local char = player.Character
	rayParams.FilterDescendantsInstances = char and { bin, char } or { bin }
end
player.CharacterAdded:Connect(refreshRayFilter)
refreshRayFilter()

--======================================================================
-- The expanding flash used by every impact -- a landing, a hit on you, and the crater
-- going off. DECLARED UP HERE, ahead of all three callers: Luau resolves a `local
-- function` by lexical position, so one declared further down the file is not an upvalue
-- to anything above it -- the call would silently read a nil GLOBAL and throw. eruptVFX
-- calling this is exactly that mistake, so it lives above eruptVFX.
--======================================================================
local function burst(pos, scale)
	local f = Instance.new("Part")
	f.Shape = Enum.PartType.Ball
	f.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE) * scale
	f.Position = pos
	f.Anchored = true; f.CanCollide = false; f.CanQuery = false; f.CanTouch = false
	f.CastShadow = false
	f.Material = Enum.Material.Neon
	f.Color = Color3.fromRGB(255, 190, 90)
	f.Transparency = 0.15
	f.Parent = bin

	task.spawn(function()
		for i = 1, 8 do
			f.Size = f.Size + Vector3.new(4, 4, 4) * scale
			f.Transparency = 0.15 + (i / 8) * 0.85
			task.wait(0.03)
		end
		f:Destroy()
	end)
	Debris:AddItem(f, 1.5)
end

--======================================================================
-- One fireball: a neon rock with a fire trail and a light.
--======================================================================
local function buildFireball(pos)
	local p = Instance.new("Part")
	p.Name = "Fireball"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	p.Position = pos
	p.Anchored = true          -- moved by the loop below, never by physics
	p.CanCollide = false       -- it must never ram the character; the shove is scripted
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 140, 45)
	p.Parent = bin

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 40)
	light.Brightness = 2.4
	light.Range = 34
	light.Shadows = false
	light.Parent = p

	-- Trailing smoke + sparks. The trail is what makes one readable against a bright sky
	-- from far enough away to actually dodge it -- the ball alone is too small at 700
	-- studs. Emitters are parented to the part so they die with it.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://241650934"
	smoke.Rate = 26
	smoke.Lifetime = NumberRange.new(1.1, 1.9)
	smoke.Speed = NumberRange.new(0, 2)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.LightEmission = 0.2
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, BALL_SIZE * 0.9),
		NumberSequenceKeypoint.new(1, BALL_SIZE * 2.6),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 70, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 42, 42)),
	})
	smoke.Parent = p

	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 34
	sparks.Lifetime = NumberRange.new(0.5, 1.0)
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 60, 20)),
	})
	sparks.Parent = p

	return p, light, { smoke, sparks }
end

local function addFireball(pos, vel, arcing, life)
	local p, light, emitters = buildFireball(pos)
	table.insert(alive, {
		part = p, light = light, emitters = emitters,
		vel = vel, arc = arcing,
		dieAt = os.clock() + life,
		landed = false,
	})
end

-- CONSTANT FALL SPEED, NOT GRAVITY. A fireball genuinely dropped from the crater would be
-- doing ~2,400 studs/sec by the time it reached slot 11 -- far past anything you could see
-- coming, let alone dodge. 150 studs/sec sits just above the flight ascent speed, so one
-- falling past you reads fast and dangerous while still giving ~4.6 seconds of warning.
-- Real ballistics are the wrong answer here.
--
-- RAIN: the ones that simply appear in the air above you.
--   * Never over the VOLCANO island -- it would have to fall through the rock its own
--     crater sits on.
--   * Mostly not over the OTHER islands either. Each spawn rolls once: usually it is
--     steered into open air, and only ISLAND_HIT_CHANCE of the time is it allowed to come
--     down on ground. Without that roll almost every fireball lands, because the islands
--     are wide and you spend the whole crossing directly above one.
local function spawnRain(alt, aroundXZ)
	local vc, vr, _, vbottom = volcanoBounds()
	local vclear = (vr + ISLAND_CLEAR) * (vr + ISLAND_CLEAR)
	local mayLand = math.random() < ISLAND_HIT_CHANCE

	for attempt = 1, 12 do
		local ang = math.random() * math.pi * 2
		local rad = SPAWN_RADIUS * math.sqrt(math.random())   -- sqrt = even spread over the disc
		local x = aroundXZ.X + math.cos(ang) * rad
		local z = aroundXZ.Z + math.sin(ang) * rad
		local pos = Vector3.new(x, alt, z)

		-- hard rule: never above the volcano island's footprint
		local dx, dz = x - vc.X, z - vc.Z
		local overVolcano = (alt > vbottom) and ((dx * dx + dz * dz) <= vclear)

		-- soft rule: only sometimes above any other island. On the last attempt take
		-- whatever is left rather than dropping the spawn -- a slightly-too-common landing
		-- is a much smaller flaw than the rain stuttering.
		local overGround = islandUnder(pos) ~= nil
		local ok = (not overVolcano) and (mayLand or not overGround or attempt == 12)

		if ok then
			local driftAng = math.random() * math.pi * 2
			addFireball(
				pos,
				Vector3.new(math.cos(driftAng) * DRIFT, -FALL_SPEED, math.sin(driftAng) * DRIFT),
				false,
				-- Live long enough to fall well past the player, then go. The 410 is the
				-- overshoot past your position and is a DISTANCE, so it scaled with the
				-- tower (was 900) -- left at 900 a fireball would outlive its own crossing.
				(SPAWN_ABOVE + 410) / FALL_SPEED
			)
			return
		end
	end
	-- Every attempt sat over the volcano: you are directly under the summit with nowhere
	-- legal to put one. Skipping is right -- the crater lobs still cover you up there.
end

-- LAUNCH: the ones that visibly come out of Volcanospot. Thrown UP and OUT, with the
-- outward speed SOLVED rather than guessed, so clearing the island is guaranteed:
--
--   A lob returns to its launch height after  T = 2 * LAUNCH_UP / ARC_GRAVITY  seconds.
--   The furthest it could ever need to travel to leave the island's disc is
--   (radius + clearance + how far the crater sits from the island centre) -- the worst
--   case being a lob aimed straight across to the far side. Divide by T and every
--   direction is safe, so the direction can stay random.
--
-- Past the peak it keeps accelerating until it hits FALL_SPEED, at which point it is an
-- ordinary falling fireball dropping into the gap below -- a real hazard for anyone
-- crossing up toward the summit, which is the point of throwing it clear rather than
-- deleting it.
-- THE CRATER GOING OFF. The server's ambient dressing (smoke column, throat glow) is the
-- volcano at REST -- deliberately restrained, because it is on screen the whole time you
-- are up here. This is the opposite: a hard, loud, short blast that only happens at the
-- moment fireballs are actually thrown, so an eruption is an EVENT rather than a
-- background texture. The two are meant to be a big contrast.
--
-- Built and destroyed per eruption rather than kept around with Enabled toggled, because
-- :Emit() on a one-shot rig is what gives the instant punch -- a Rate-driven emitter ramps
-- up, which reads as a leak instead of a blast.
local function eruptVFX(origin)
	local rig = Instance.new("Part")
	rig.Name = "EruptionRig"
	rig.Size = Vector3.new(1, 1, 1)
	rig.Position = origin
	rig.Transparency = 1
	rig.Anchored = true; rig.CanCollide = false; rig.CanQuery = false; rig.CanTouch = false
	rig.CastShadow = false
	rig.Parent = bin

	local att = Instance.new("Attachment")
	att.Parent = rig

	-- Ash punched straight up, fast and wide.
	local ash = Instance.new("ParticleEmitter")
	ash.Texture = "rbxassetid://241650934"
	ash.Rate = 0                                   -- one-shot; see :Emit() below
	ash.Lifetime = NumberRange.new(2.5, 5.0)
	ash.Speed = NumberRange.new(120, 260)
	ash.SpreadAngle = Vector2.new(35, 35)
	ash.Rotation = NumberRange.new(0, 360)
	ash.RotSpeed = NumberRange.new(-40, 40)
	ash.LightEmission = 0.25
	ash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 18),
		NumberSequenceKeypoint.new(1, 130),
	})
	ash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	ash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 84, 78)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 36, 36)),
	})
	ash.Parent = att

	-- Sparks thrown far wider than the ash, so the blast has a hard bright edge.
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 0
	spray.Lifetime = NumberRange.new(1.2, 2.4)
	spray.Speed = NumberRange.new(180, 380)
	spray.SpreadAngle = Vector2.new(70, 70)
	spray.LightEmission = 1
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 7),
		NumberSequenceKeypoint.new(1, 0),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 55, 15)),
	})
	spray.Parent = att

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 140, 50)
	flash.Brightness = 9
	flash.Range = 260
	flash.Shadows = false
	flash.Parent = rig

	ash:Emit(46)
	spray:Emit(130)
	burst(origin, 2.8)

	-- Fade the flash rather than cutting it: a light that vanishes in one frame reads as a
	-- rendering hitch, not as a blast dying down.
	task.spawn(function()
		for i = 1, 14 do
			flash.Brightness = 9 * (1 - i / 14)
			task.wait(0.045)
		end
		flash.Enabled = false
	end)

	Debris:AddItem(rig, 7)   -- outlives the longest particle, then takes the whole rig
end

-- ONE ERUPTION = the crater going off + a handful of fireballs, not a single lonely ball
-- lobbed out in silence. The count varies so no two eruptions look the same.
local function erupt()
	local origin = craterPos()
	local c, r = volcanoBounds()

	local T = 2 * LAUNCH_UP / ARC_GRAVITY
	local dx, dz = origin.X - c.X, origin.Z - c.Z
	local craterOffset = math.sqrt(dx * dx + dz * dz)
	local outward = (r + ISLAND_CLEAR + craterOffset) / T

	eruptVFX(origin)

	-- Spread the throws around the compass instead of rolling each direction blind, so a
	-- burst never comes out as three fireballs stacked on the same arc.
	local n = math.random(ERUPT_MIN, ERUPT_MAX)
	local base = math.random() * math.pi * 2
	for i = 1, n do
		local ang = base + (i - 1) * (math.pi * 2 / n) + (math.random() - 0.5) * 0.6
		-- BOTH JITTERS ONLY EVER SCALE UP, and that is load-bearing. `outward` is solved so
		-- that outward x T exactly clears the island, where T comes from LAUNCH_UP. Rolling
		-- either factor BELOW 1 shortens the throw under that solve, and the fireball comes
		-- down on the island -- where the backstop cull deletes it mid-air, so eruptions
		-- would visibly pop out of existence over the summit. Up is free; down is not.
		local speed = outward   * (1.00 + math.random() * 0.35)
		local up    = LAUNCH_UP * (1.00 + math.random() * 0.30)
		addFireball(
			origin,
			Vector3.new(math.cos(ang) * speed, up, math.sin(ang) * speed),
			true,
			30
		)
	end
end

-- The mark left behind. Flat disc laid along the surface normal, fading out slowly, so a
-- landing leaves evidence for a few seconds instead of vanishing the instant it cools.
local function scorch(pos, normal)
	local d = Instance.new("Part")
	d.Name = "Scorch"
	d.Shape = Enum.PartType.Cylinder
	d.Size = Vector3.new(0.6, BALL_SIZE * 2.1, BALL_SIZE * 2.1)

	-- Cylinders point along X, so build a frame with X down the surface normal, and lift it
	-- a hair off the ground to keep it from z-fighting with what it is painted on.
	--
	-- BUILT BY HAND RATHER THAN WITH CFrame.lookAt, WHICH IS DEGENERATE HERE. lookAt's
	-- default up vector is (0,1,0) and almost every island surface has a normal of exactly
	-- (0,1,0) -- parallel to the up vector, which is the one case it cannot solve. The
	-- helper axis below is picked to never be parallel to the normal, so flat ground and
	-- a sheer cliff both come out right.
	local vX = normal.Unit
	local helper = (math.abs(vX.Y) > 0.99) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local vZ = vX:Cross(helper).Unit
	local vY = vZ:Cross(vX).Unit
	d.CFrame = CFrame.fromMatrix(pos + vX * 0.15, vX, vY, vZ)
	d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
	d.CastShadow = false
	d.Material = Enum.Material.Slate
	d.Color = Color3.fromRGB(28, 22, 20)
	d.Transparency = 0.15
	d.Parent = bin

	task.spawn(function()
		local steps = 24
		for i = 1, steps do
			d.Transparency = 0.15 + (i / steps) * 0.85
			task.wait(SCORCH_FADE / steps)
		end
		d:Destroy()
	end)
	Debris:AddItem(d, SCORCH_FADE + 2)
end

-- Turn a falling fireball into a landed, cooling one. It stops dead, flashes, drops a
-- scorch mark, and the move loop fades it out over LAND_FADE.
local function landFireball(fb, hitPos, normal)
	fb.landed = true
	fb.fadeAt = os.clock() + LAND_FADE
	fb.vel = Vector3.zero

	local p = fb.part
	p.Position = hitPos + normal * (BALL_SIZE * 0.28)   -- sat in the ground, not floating on it

	-- Stop the trail: a landed fireball that keeps streaming smoke upward looks like it is
	-- still moving. The emitters stay parented so they die with the part.
	for _, e in ipairs(fb.emitters) do e.Enabled = false end

	burst(hitPos, 1.15)
	scorch(hitPos, normal)
end

--======================================================================
-- Getting hit.
--======================================================================
local knockUntil = 0
local knockVec   = Vector3.zero
local immuneTil  = 0

-- Standing on solid ground makes you immune -- see the header. FloorMaterial is the test
-- rather than _G.isFlying, because FALLING is neither flying nor safe and must still be
-- hittable; only actually being on the ground counts.
local function isGrounded(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
end

local function onHit(hrp, ballPos)
	local now = os.clock()
	if now < immuneTil then return end
	immuneTil = now + IFRAMES

	-- The jolt. Shoves you AWAY from the fireball, horizontally only. Flat first, then
	-- normalised -- one landing straight on your head has no horizontal direction to push
	-- along, so fall back to a random one rather than dividing by zero.
	--
	-- This is now COSMETIC: it plays for the third of a second between the hit landing and
	-- the knockdown firing, so the fireball visibly swats you before the world changes.
	-- The knockdown is the real cost.
	local away = Vector3.new(hrp.Position.X - ballPos.X, 0, hrp.Position.Z - ballPos.Z)
	if away.Magnitude < 0.1 then
		local a = math.random() * math.pi * 2
		away = Vector3.new(math.cos(a), 0, math.sin(a))
	else
		away = away.Unit
	end

	knockVec   = away * KNOCK
	knockUntil = now + KNOCK_DECAY

	burst(ballPos, 1)

	-- KNOCKED BACK DOWN TO THE LAST ISLAND YOU REACHED.
	--
	-- Fired through ReturnToIslandEvent -- the SAME remote the "Return to <island>" button
	-- uses -- rather than teleporting the character here. That is not laziness, it is the
	-- only correct way to do it:
	--   * THE SERVER PICKS THE DESTINATION. This message carries no slot and no position;
	--     ReturnIsland.server recomputes where the player actually got to from HighestSlot.
	--     A client that could name its own destination could name the summit, which is
	--     precisely the exploit ReturnIsland's header warns against. Do not "optimise" this
	--     by passing a slot.
	--   * IT LANDS ON THE WALKABLE SURFACE. ReturnIsland raycasts each island's real ground
	--     (and prefers its island<N>Spawn pad), because a bounding box wraps the treetops
	--     and the volcano -- teleporting to bbox-top would drop you out of the canopy.
	--   * IT KILLS THE FALL VELOCITY on arrival, so you do not land carrying the drop and
	--     slide straight back off.
	-- Every one of those already exists and is already debugged. A second copy here would
	-- be a second copy of the bugs its comments describe.
	--
	-- The delay lets the impact read before the screen changes -- teleporting on the same
	-- frame as the flash makes it look like the fireball missed and the game glitched.
	if ReturnToIslandEvent then
		task.delay(KNOCKDOWN_DELAY, function()
			ReturnToIslandEvent:FireServer()
		end)
	else
		warn("[Volcano] ReturnToIslandEvent missing -- a fireball hit could not knock the player down")
	end
end

--======================================================================
-- The loop: spawn, move, land, collide, expire.
--======================================================================
local spawnTimer  = 0
local launchTimer = 0

RunService.Heartbeat:Connect(function(dt)
	local now  = os.clock()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")

	-- ---- knockback decay -> _G, the channel BottomHUD's flight loop reads ----
	if now < knockUntil then
		local left = (knockUntil - now) / KNOCK_DECAY   -- 1 -> 0
		_G.fireballKnock = knockVec * left
	elseif _G.fireballKnock then
		_G.fireballKnock = nil
	end

	if not hrp then return end
	local y = hrp.Position.Y
	local active = (y >= BAND_BOTTOM and y <= BAND_TOP)
	local grounded = isGrounded(char)

	local t         = intensity(y)
	local maxAlive  = math.floor(lerp(MAX_ALIVE_CALM, MAX_ALIVE_PEAK, t) + 0.5)
	local spawnRate = lerp(SPAWN_EVERY_CALM, SPAWN_EVERY_PEAK, t)
	local crater    = craterPos()

	-- ---- rain: appears in the air above you ----
	if active and #alive < maxAlive then
		spawnTimer = spawnTimer + dt
		if spawnTimer >= spawnRate then
			spawnTimer = 0
			-- Never spawn above the crater itself -- a fireball has to come FROM the
			-- volcano, so the highest it can appear is the crater lip.
			local top = math.min(y + SPAWN_ABOVE, crater.Y)

			-- ...and never up inside the volcano island. Dropped to just under its belly
			-- rather than skipped, so the rain keeps coming as you close on the summit
			-- instead of thinning out at the exact moment the crossing gets hardest --
			-- they simply start appearing out from under the island, which is where they
			-- read best anyway. Once you are ON the summit this puts `top` below you and
			-- the test below stops the rain entirely: up there, only the crater lobs.
			local _, _, _, belly = volcanoBounds()
			if top > belly then top = belly - 20 end

			if top > y + 120 then
				spawnRain(top, hrp.Position)
			end
		end
	else
		spawnTimer = 0
	end

	-- ---- launches: thrown out of Volcanospot, only while you are close enough to see ----
	if #alive < maxAlive + 4 and (hrp.Position - crater).Magnitude <= LAUNCH_RANGE then
		launchTimer = launchTimer + dt
		if launchTimer >= LAUNCH_EVERY then
			launchTimer = 0
			erupt()
		end
	else
		launchTimer = 0
	end

	-- ---- move + test, walking backwards so removals are safe ----
	for i = #alive, 1, -1 do
		local fb = alive[i]
		local p = fb.part

		if not p or not p.Parent then
			table.remove(alive, i)

		elseif fb.landed then
			-- Cooling off: dim from neon orange down to dead black, then go.
			local left = math.clamp((fb.fadeAt - now) / LAND_FADE, 0, 1)
			p.Transparency = 1 - left
			p.Color = Color3.fromRGB(255, 140, 45):Lerp(Color3.fromRGB(45, 20, 12), 1 - left)
			if fb.light then fb.light.Brightness = 2.4 * left end
			if now >= fb.fadeAt then
				p:Destroy()
				table.remove(alive, i)
			end

		else
			-- A lobbed fireball is still under the arc until it reaches terminal speed;
			-- after that it behaves exactly like a rain one.
			if fb.arc then
				local vy = math.max(fb.vel.Y - ARC_GRAVITY * dt, -FALL_SPEED)
				fb.vel = Vector3.new(fb.vel.X, vy, fb.vel.Z)
			end

			local nextPos = p.Position + fb.vel * dt

			-- GROUND TEST, only while descending and only while there is actually an
			-- island underneath -- a raycast every frame for every fireball over open sky
			-- would be pure waste. Cast from where it is to where it is about to be (plus
			-- its own radius) so a fast one cannot step straight over a thin surface.
			local landed = false
			if fb.vel.Y < 0 then
				local isl = islandUnder(p.Position)
				if isl and p.Position.Y <= isl.top + 60 then
					local delta = nextPos - p.Position
					local reach = delta.Magnitude + BALL_SIZE * 0.5
					local hit = Workspace:Raycast(p.Position, Vector3.new(0, -reach, 0), rayParams)
					if hit then
						landFireball(fb, hit.Position, hit.Normal)
						landed = true
					end
				end
			end

			if not landed then
				p.Position = nextPos

				local dead, hit = false, false
				-- Grounded players are immune, so do not even test the distance.
				if not grounded and (p.Position - hrp.Position).Magnitude <= HIT_RADIUS then
					dead, hit = true, true
				elseif now >= fb.dieAt
					or p.Position.Y < BAND_BOTTOM - 600
					or p.Position.Y < hrp.Position.Y - CULL_BELOW then
					dead = true
				elseif fb.vel.Y < 0 and insideVolcano(p.Position) then
					-- BACKSTOP. Nothing should reach here: rain refuses to spawn over the
					-- volcano and a launch is solved to clear it. Tested on DESCENT only,
					-- because a lob legitimately starts inside the box on its way up out of
					-- the crater. Killed silently -- a burst would draw the eye to exactly
					-- the glitch this is hiding.
					dead = true
				end

				if dead then
					if hit then onHit(hrp, p.Position) end
					p:Destroy()
					table.remove(alive, i)
				end
			end
		end
	end
end)

-- Wipe the field on respawn. Without this, dying mid-crossing leaves a dozen fireballs
-- hanging in the sky above the island you respawn on.
player.CharacterAdded:Connect(function()
	for i = #alive, 1, -1 do
		if alive[i].part then alive[i].part:Destroy() end
		table.remove(alive, i)
	end
	knockUntil = 0
	_G.fireballKnock = nil
end)

print(("[Volcano] fireballs ready -- Y %d (slot %d) to the summit, ramping %.2fs -> %.2fs between spawns")
	:format(BAND_BOTTOM, FIRST_SLOT, SPAWN_EVERY_CALM, SPAWN_EVERY_PEAK))
