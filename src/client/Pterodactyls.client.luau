--======================================================================
-- Pterodactyls.client.luau  (LocalScript)
--======================================================================
-- PTERODACTYLS CROSSING THE FLIGHT PATH. On three of the tower's crossings a flock hunts
-- the airspace between the islands: they come in from any direction, at different heights,
-- and cut straight across the line you are climbing. Clip one and it swats you back down
-- to the last island you unlocked.
--
-- ===== WHICH CROSSINGS, AND WHY THESE THREE =====
-- Not every gap -- a hazard you meet twelve times in a row is a tax, not an event. Three,
-- spread out, each arriving when the climb has settled into a rhythm:
--
--   4 -> 5    Sunscorch Sands  -> Fossil Frontier    the first one. Short gap (1,913
--             studs), so the encounter is over quickly and the lesson is cheap.
--   7 -> 8    Claw Cliffs     -> Coastal Crossing    mid-tower, 3,638 studs, over open
--             water -- the silhouettes read cleanly against the sea.
--   9 -> 10   Petrified Pass   -> Fern Frontier       5,052 studs, the long one, right
--             before the volcano band starts.
--
-- THEY DO NOT OVERLAP THE FIREBALLS. VolcanoFireballs owns everything from slot 11 minus
-- 200 studs upward (Y 29,388+); crossing 9->10 tops out at 24,275. Stacking two dodge
-- hazards on one crossing was never the plan and the numbers keep it that way -- if you
-- move either hazard, re-check that.
--
-- ===== WHY CLIENT-SIDE, LIKE THE BUBBLES AND THE FIREBALLS =====
-- Every part here is anchored, non-collidable and moved by code only -- nothing touches
-- physics and nothing touches the character. Each player gets their own flock, so nobody
-- dodges a bird that lag has already moved, and two players are never handed the same
-- unfair spawn. Same argument Bubbles.client.luau makes for the pickups sharing this
-- airspace, and VolcanoFireballs.client.luau for the fireballs above it.
--
-- ===== THEY AIM WHERE YOU WILL BE, NOT WHERE YOU ARE =====
-- A bird launched at your CURRENT position always misses low: it spends ~4 seconds in the
-- air and you climb 200-600 studs in that time depending on your gut. So the spawn solves
-- for where you will be when it arrives, using your live vertical speed, and then throws
-- a deliberate jitter on top. Aiming perfectly would be unfair and aiming at your feet
-- would be harmless -- the jitter is what makes some a genuine threat and some a near
-- miss you can watch go past.
--
-- ===== THE HIT: YOU GET KNOCKED DOWN, NOT TELEPORTED =====
-- A bird swats you out of the sky and you FALL onto the island you launched from. No warp,
-- no fade -- you watch yourself come down. Four things happen, all in onHit():
--   * A squawk plays, parented to SoundService so it survives whatever happens to the
--     character on the way down.
--   * You lose A SIXTH OF THE FUEL YOU ARE STILL CARRYING, through BottomHUD's
--     _G.dinoDrainFuelFraction so the bar, the raw power and the server stay in step.
--   * A BodyVelocity drives you down AND steers you toward the island below, re-aimed every
--     frame -- a straight-down knock in a tower whose islands are offset by a few hundred
--     studs would drop you into the gap beside one rather than onto it, and a bearing set
--     once at the top of a long fall overshoots.
--   * _G.flightLockUntil stops BottomHUD thrusting THE WHOLE WAY DOWN, renewed on a short
--     lease until the Humanoid finds a floor. It used to be a flat 0.77 s, which expired in
--     mid-air and let you fly on from wherever you were -- a speed bump on a short crossing.
--     A hit now costs you the climb: you go back to the island below and you do not fly
--     again until you are standing on it.
-- (The volcano fireballs still use the ReturnToIslandEvent teleport. These two hazards
-- deliberately punish differently: the fireball takes the crossing off you instantly, the
-- bird makes you fall and watch it happen.)
--======================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local player      = Players.LocalPlayer

--======================================================================
-- TUNING
--======================================================================
-- Crossing N means "the gap from slot N up to slot N+1".
local HAZARD_CROSSINGS = { 4, 7, 9 }

local EDGE_MARGIN  = 150    -- studs of clear air left at each end of a gap, so the flock
                            -- never harasses you on the island itself

local SPEED        = 130    -- studs/sec across the path
local SPAWN_DIST   = 520    -- studs out when one appears => 520/130 = 4.0s of warning
-- SPAWN_EVERY scaled x0.455 (was 2.30). You are in a hazard band for 2.2x fewer seconds
-- now, so a fixed interval would have more than halved the birds you actually meet on a
-- crossing. Scaling it keeps the ENCOUNTER COUNT PER CROSSING identical.
--
-- MAX_ALIVE HAD TO RISE WITH IT, and this is easy to miss: a bird lives (SPAWN_DIST * 2.1)
-- / SPEED = 8.4 s, which is HORIZONTAL travel and did not scale. At one arrival every
-- 1.05 s that is eight birds in the air at once, so a cap of 4 would have silently
-- throttled the spawner back to half rate and undone the interval change. 8 restores it.
local SPAWN_EVERY  = 1.05   -- seconds between arrivals
local MAX_ALIVE    = 8      -- how many may be in the air at once

-- NOTHING IN THE APPROACH GEOMETRY CHANGED, and that is a result rather than an oversight.
-- SPEED and SPAWN_DIST are horizontal, in a column whose X/Z never moved, so the flight in
-- is still 520/130 = 4.0 s. The player's climb speed is back to its original value too, so
-- they still rise ~200 studs during that approach -- which means HEIGHT_JITTER belongs at
-- its original 130. (An interim pass cut it to 59 to match a slowed-down player; that
-- player is gone.)
--
-- The intercept solve needs no adjustment at all: it reads the player's LIVE vertical
-- velocity, so it follows whatever the flight physics are doing on its own.
local HEIGHT_JITTER = 130   -- studs of vertical scatter around the predicted intercept
local AIM_SPREAD    = 55    -- studs of sideways scatter -- some are near misses on purpose

local HIT_RADIUS   = 13     -- centre-to-centre against the body

-- ---- the knockdown ----
-- Both times scaled x0.455 (were 4.00 and 1.70). The stun had to move or a hit would have
-- become a far bigger setback than it used to be: at 170 studs/sec for 1.70 s it dropped
-- you 289 studs, which was 15% of the old 1,913-stud crossing but would be 33% of the new
-- 870-stud one. At 0.77 s it is back to ~15%.
local IFRAMES      = 1.82   -- must outlast the stun so one hit is one knockdown
local STUN_SECONDS = 0.77   -- how long the DOWNWARD SHOVE lasts (the lock now runs longer)

-- ===== A HIT NOW RIDES YOU ALL THE WAY DOWN =====
-- It used to be a 0.77 s shove: you got knocked down a few hundred studs, the lock expired
-- in mid-air and you simply flew on from wherever you happened to be. On the short crossings
-- that made a bird a speed bump. The brief lets it cost the whole crossing instead -- you go
-- back to the island below and you do not fly again until you are standing on it.
--
-- SO THE LOCK IS NOW A CONDITION, NOT A TIMER: held while airborne, released the moment the
-- Humanoid reports a floor. It is still WRITTEN as a timestamp because that is the contract
-- BottomHUD reads, and a timestamp fails safe -- if this script dies mid-fall the lock runs
-- out on its own instead of grounding the player forever. The watchdog just keeps pushing it
-- forward while you are still in the air.
local LOCK_LEASE   = 0.60   -- how far ahead the lock is renewed each tick while airborne
local RIDE_TIMEOUT = 20     -- hard ceiling on one knockdown, so a bad landing cannot trap you
local FUEL_BITE    = 1/6    -- fraction of REMAINING fuel a hit costs

-- Reuploaded on this account? If this ever logs "did NOT load", that is audio privacy, not
-- this script -- same failure the sniper's shot sound hit.
local HIT_SFX      = "rbxassetid://9125474519"
local HIT_VOL      = 1.6
-- BOTH ARE SPEEDS AND BOTH STAY at their original values -- the shorter STUN_SECONDS above
-- is what rescales the knockdown, not a slower shove. Cutting the speed instead would have
-- made a bird hit feel mushy; cutting the duration keeps the impact and shortens the fall.
--
-- KNOCK_STEER has a second reason to stay put: it has to cover the same unchanged
-- horizontal distance to the island below, and it now has less time to do it in.
local KNOCK_DOWN   = 170    -- studs/sec driven DOWNWARD while stunned
local KNOCK_STEER  = 90     -- studs/sec of horizontal steer toward the island below

local FLAP_HZ      = 2.4    -- wingbeats per second
local FLAP_AMP     = 0.55   -- radians of wing travel

local SCALE        = 1.6    -- overall size multiplier for the bird

--======================================================================
-- WHERE THE HAZARD LIVES
--======================================================================
-- One band per chosen crossing, resolved once from the shared ladder. SLOT_POS is used
-- rather than the island models because with StreamingEnabled a distant island's parts are
-- not replicated -- exactly the reason Bubbles reads the ladder too.
local bands = {}
for _, n in ipairs(HAZARD_CROSSINGS) do
	local a, b = IslandOrder.SLOT_POS[n], IslandOrder.SLOT_POS[n + 1]
	if a and b then
		table.insert(bands, {
			crossing = n,
			bottom = a.Y + EDGE_MARGIN,
			top    = b.Y - EDGE_MARGIN,
		})
	end
end

local function inBand(y)
	for _, band in ipairs(bands) do
		if y >= band.bottom and y <= band.top then return band end
	end
	return nil
end

--======================================================================
-- The flock lives in one client-only folder -- a single Destroy cleans the lot up.
--======================================================================
local bin = Instance.new("Folder")
bin.Name = "Pterodactyls"
bin.Parent = Workspace

local alive = {}   -- { model, parts…, dir, phase, dieAt }

-- The island you are climbing AWAY from -- the highest one at or below you. The knockdown
-- steers toward it so being swatted actually puts you back on ground rather than dropping
-- you into the gap beside it. Read off the shared ladder, not the world, for the usual
-- StreamingEnabled reason.
local function islandBelow(y)
	local best
	for slot = 1, IslandOrder.COUNT do
		local p = IslandOrder.SLOT_POS[slot]
		if p and p.Y <= y then best = p else break end
	end
	return best
end

--======================================================================
-- BUILDING ONE
--======================================================================
-- Anchored parts in a Model, driven entirely by the move loop below. The wings are kept as
-- separate handles rather than welded, because they have to be re-framed every frame to
-- flap -- a welded wing would need the weld's C0 rewritten instead, which is more work for
-- the same result on a part that never touches physics.
--======================================================================
-- COLOURS -- every bird rolls its own.
--
-- A flock of identical models reads as clones the instant two share a screen, so each one
-- picks a palette and then jitters it. The palettes are natural pterosaur schemes -- greys,
-- sands, olives, charcoals -- with the CREST as the one loud element, which is where the
-- real animals put their colour too.
--======================================================================
local PALETTES = {
	{ name = "slate",    hide = Color3.fromRGB( 96,102,110), memb = Color3.fromRGB(132,138,146), crest = Color3.fromRGB(168, 62, 48), beak = Color3.fromRGB( 54, 58, 64) },
	{ name = "sand",     hide = Color3.fromRGB(166,138, 98), memb = Color3.fromRGB(198,174,140), crest = Color3.fromRGB(206,116, 42), beak = Color3.fromRGB( 92, 74, 52) },
	{ name = "olive",    hide = Color3.fromRGB( 96,102, 68), memb = Color3.fromRGB(140,144,108), crest = Color3.fromRGB(212,178, 58), beak = Color3.fromRGB( 58, 60, 44) },
	{ name = "rust",     hide = Color3.fromRGB(128, 82, 60), memb = Color3.fromRGB(170,128,102), crest = Color3.fromRGB(150, 44, 34), beak = Color3.fromRGB( 66, 44, 34) },
	{ name = "charcoal", hide = Color3.fromRGB( 62, 64, 72), memb = Color3.fromRGB( 98,104,116), crest = Color3.fromRGB(226,222,214), beak = Color3.fromRGB( 38, 40, 46) },
}

-- A few points either way per channel, so two birds on the same palette are still not twins.
local function jitter(c, amount)
	local function ch(v) return math.clamp(v + (math.random() - 0.5) * 2 * amount, 0, 1) end
	return Color3.new(ch(c.R), ch(c.G), ch(c.B))
end

local function rollPalette()
	local p = PALETTES[math.random(#PALETTES)]
	return {
		name  = p.name,
		hide  = jitter(p.hide,  0.05),
		memb  = jitter(p.memb,  0.05),
		crest = jitter(p.crest, 0.07),
		beak  = jitter(p.beak,  0.04),
	}
end

--======================================================================
-- BUILDING ONE -- eleven blocks.
--======================================================================
-- BLOCKS ONLY, NO SPHERES. The previous pass used stretched Ball parts for the body, neck,
-- skull and beak; at any real distance a chain of ellipsoids reads as a string of blobs
-- rather than an animal. Flat faces and hard edges hold a silhouette far better, and the
-- silhouette is all you ever actually see of one of these.
--
-- TAPERS ARE STEPPED, NOT SLOPED. The beak is two shrinking blocks, and the wing narrows in
-- chord between its two segments. A WedgePart would give a true taper, but its slope
-- direction is easy to get backwards and this has to be right without a Studio pass --
-- stepped blocks are unambiguous, and they suit the low-poly look anyway.
--
-- Anchored, driven entirely by the move loop. The wings are separate handles rather than
-- welded because they are re-framed every frame to flap.
local function mk(model, name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * SCALE
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- { length out from the joint, chord front-to-back, thickness, resting dihedral, share of
--   the flap }. Two segments per wing, not three -- one bend is enough to sell a wingbeat.
local WING_SEGMENTS = {
	{ len =  9.0, chord = 6.5, thick = 0.55, dihedral = 0.10, lag = 1.00 },  -- arm
	{ len = 13.0, chord = 3.4, thick = 0.45, dihedral = 0.04, lag = 0.45 },  -- finger, to the tip
}

-- Half the widest chord. Every segment is pushed back by its own half-chord minus this, so
-- all the LEADING EDGES line up and the trailing edge sweeps in toward the tip -- which is
-- the actual shape of a pterosaur wing. Centring each segment on the bone instead would
-- step the leading edge inward at the wrist and look broken.
local WING_LEAD = WING_SEGMENTS[1].chord * 0.5

local function buildPtero()
	local m = Instance.new("Model")
	m.Name = "Pterodactyl"
	local pal = rollPalette()

	local b = { model = m, pal = pal, wings = { L = {}, R = {} } }

	b.body  = mk(m, "Body",  Vector3.new(4.4, 3.2, 10.5), pal.hide)
	b.neck  = mk(m, "Neck",  Vector3.new(1.9, 1.9,  5.2), pal.hide)
	b.head  = mk(m, "Head",  Vector3.new(2.2, 1.9,  4.0), pal.hide)
	b.beak1 = mk(m, "Beak1", Vector3.new(1.3, 1.1,  4.4), pal.beak)
	b.beak2 = mk(m, "Beak2", Vector3.new(0.6, 0.6,  3.6), pal.beak)
	b.crest = mk(m, "Crest", Vector3.new(0.4, 2.8,  4.2), pal.crest)
	b.tail  = mk(m, "Tail",  Vector3.new(0.8, 0.8,  5.4), pal.hide)

	for _, side in ipairs({ "L", "R" }) do
		for i, seg in ipairs(WING_SEGMENTS) do
			local w = mk(m, ("Wing%s%d"):format(side, i),
				Vector3.new(seg.len, seg.thick, seg.chord), pal.memb)
			w.Transparency = 0.08   -- membrane is skin over bone, not hide
			b.wings[side][i] = w
		end
	end

	m.PrimaryPart = b.body
	m.Parent = bin
	return b
end

-- Lay the whole animal out for this frame. `flap` is the shoulder angle in radians.
-- Local space: X right, Y up, -Z forward (the model faces -Z, matching CFrame.lookAt).
local function poseBird(b, cf, flap)
	local S = SCALE

	b.body.CFrame = cf

	-- Neck rakes up and forward out of the shoulders; the head carries on from it, nose down
	-- a touch. Chaining the head off the NECK frame rather than the body keeps the two joined
	-- no matter how the neck is aimed.
	local neckCF = cf * CFrame.new(0, 1.0 * S, -6.6 * S) * CFrame.Angles(math.rad(-16), 0, 0)
	b.neck.CFrame = neckCF

	local headCF = neckCF * CFrame.new(0, 0.35 * S, -4.2 * S) * CFrame.Angles(math.rad(10), 0, 0)
	b.head.CFrame  = headCF
	b.beak1.CFrame = headCF * CFrame.new(0, -0.20 * S, -4.0 * S)
	b.beak2.CFrame = headCF * CFrame.new(0, -0.30 * S, -7.6 * S)

	-- The crest sweeps BACK off the skull rather than standing up on it. That backward rake
	-- against a long forward beak is the one silhouette cue that reads "pterodactyl" instead
	-- of "bird", and it is why the crest is worth a part of its own at this budget.
	b.crest.CFrame = headCF * CFrame.new(0, 1.7 * S, 1.6 * S) * CFrame.Angles(math.rad(-34), 0, 0)

	b.tail.CFrame = cf * CFrame.new(0, 0.4 * S, 6.6 * S) * CFrame.Angles(math.rad(9), 0, 0)

	-- WINGS. Walk out from the shoulder, one segment at a time.
	--
	-- `joint` TRACKS THE END OF THE LAST SEGMENT, never its middle. That distinction is the
	-- difference between a wing and a broken one: rotating about a segment's midpoint swings
	-- its inner end away from where the previous segment finished, so every bend opens a gap
	-- at the wrist that grows with the flap angle. Hinging at the joint keeps them meeting end
	-- to end through the whole beat.
	--
	-- The outer segment takes a smaller share of the flap (`lag`), so the shoulder leads and
	-- the tip trails on every stroke -- the detail that most makes a wingbeat look alive.
	for _, side in ipairs({ "L", "R" }) do
		local sign = (side == "L") and -1 or 1
		local joint = cf * CFrame.new(sign * 1.9 * S, 0.9 * S, -1.4 * S)

		for i, seg in ipairs(WING_SEGMENTS) do
			local angle = (flap * seg.lag + seg.dihedral) * sign
			joint = joint * CFrame.Angles(0, 0, angle)

			b.wings[side][i].CFrame =
				joint * CFrame.new(sign * seg.len * 0.5 * S, 0, (seg.chord * 0.5 - WING_LEAD) * S)

			joint = joint * CFrame.new(sign * seg.len * S, 0, 0)   -- step to this segment's END
		end
	end
end

--======================================================================
-- SPAWNING
--======================================================================
local function spawnPtero(hrp)
	-- A random compass heading -- they come from every direction, never a fixed side.
	local ang = math.random() * math.pi * 2
	local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))

	-- Solve for where the player will BE when it arrives, not where they are now. Vertical
	-- speed comes off the character because the fart flight drives a BodyVelocity, so the
	-- climb shows up in AssemblyLinearVelocity like any other motion.
	local travel = SPAWN_DIST / SPEED
	local vy = hrp.AssemblyLinearVelocity.Y
	local aimY = hrp.Position.Y + vy * travel + (math.random() - 0.5) * 2 * HEIGHT_JITTER

	-- Sideways scatter, perpendicular to the flight line. This is what separates a bird you
	-- must dodge from one that sails past -- both are wanted.
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local aim = Vector3.new(hrp.Position.X, aimY, hrp.Position.Z)
		+ perp * ((math.random() - 0.5) * 2 * AIM_SPREAD)

	local b = buildPtero()
	b.dir = dir
	b.phase = math.random() * math.pi * 2      -- so a flock is never flapping in unison
	b.pos = aim - dir * SPAWN_DIST
	-- Live long enough to cross well past the player, then go. Anything still alive after
	-- that is behind you and pointing away.
	b.dieAt = os.clock() + (SPAWN_DIST * 2.1) / SPEED

	poseBird(b, CFrame.lookAt(b.pos, b.pos + dir), 0)
	table.insert(alive, b)
end

local function killBird(i)
	local b = alive[i]
	if b and b.model then b.model:Destroy() end
	table.remove(alive, i)
end

--======================================================================
-- THE HIT
--======================================================================
local immuneTil = 0

local function isGrounded(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
end

-- `featherColor` is the palette of the bird that actually hit you, so the debris matches
-- the animal rather than a fixed colour that would be wrong four times in five.
local function impactPuff(pos, featherColor)
	local f = Instance.new("Part")
	f.Shape = Enum.PartType.Ball
	f.Size = Vector3.new(6, 6, 6)
	f.Position = pos
	f.Anchored = true; f.CanCollide = false; f.CanQuery = false; f.CanTouch = false
	f.CastShadow = false
	f.Material = Enum.Material.Neon
	f.Color = Color3.fromRGB(255, 240, 210)
	f.Transparency = 0.2
	f.Parent = bin
	task.spawn(function()
		for i = 1, 8 do
			f.Size = f.Size + Vector3.new(5, 5, 5)
			f.Transparency = 0.2 + (i / 8) * 0.8
			task.wait(0.03)
		end
		f:Destroy()
	end)
	Debris:AddItem(f, 1.2)

	-- A few loose feathers, because a bird hitting you should leave something behind.
	for _ = 1, 10 do
		local q = Instance.new("Part")
		q.Size = Vector3.new(0.3, 1.6, 0.7)
		q.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		q.Color = featherColor
		q.Material = Enum.Material.SmoothPlastic
		q.Anchored = false; q.CanCollide = false; q.CastShadow = false
		q.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 60, 10 + math.random() * 30, (math.random() - 0.5) * 60)
		q.Parent = bin
		Debris:AddItem(q, 4)
	end
end

local function onHit(hrp, atPos, pal)
	local now = os.clock()
	if now < immuneTil then return end
	immuneTil = now + IFRAMES

	impactPuff(atPos, (pal and pal.memb) or Color3.fromRGB(150, 140, 130))

	-- Camera kick, so the swat lands before the world changes under you.
	task.spawn(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local t0, dur = os.clock(), 0.45
		while os.clock() - t0 < dur and hum.Parent do
			local k = 1 - (os.clock() - t0) / dur
			local amp = 4.5 * k * k
			hum.CameraOffset = Vector3.new(
				(math.random() - 0.5) * amp, (math.random() - 0.5) * amp, (math.random() - 0.5) * amp)
			task.wait()
		end
		if hum.Parent then hum.CameraOffset = Vector3.zero end
	end)

	-- ===== KNOCKED DOWN, NOT TELEPORTED =====
	-- You get swatted out of the sky and you FALL. Two parts to it:
	--
	--   1. THE FLIGHT LOCK. _G.flightLockUntil stops BottomHUD thrusting for STUN_SECONDS.
	--      Without it, a player holding the fart button simply keeps climbing through the
	--      hit and the bird costs them nothing. BottomHUD calls stopFlying() on the lock
	--      rather than quietly skipping the thrust, so the meter stops draining while you
	--      drop and you have to actually start flying again afterwards.
	--
	--   2. THE DRIVE. A temporary BodyVelocity pushes you down hard AND steers you toward
	--      the island you launched from, because a straight-down knock in a tower whose
	--      islands are offset by a few hundred studs would drop you into the gap BESIDE the
	--      island rather than onto it. The steer is what makes "knocked down onto the
	--      island" true instead of "knocked into the void".
	--
	-- It expires after STUN_SECONDS and normal physics finishes the fall -- and the "Return
	-- to <island>" button is still there if the landing goes wrong. Falling is the game.
	_G.flightLockUntil = now + math.max(STUN_SECONDS, LOCK_LEASE)

	-- ===== THE SQUAWK =====
	-- Parented to SoundService, not the character: the character can be knocked around,
	-- respawned or streamed while this plays, and a Sound inside it dies with it.
	do
		local s = Instance.new("Sound")
		s.SoundId, s.Volume = HIT_SFX, HIT_VOL
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 6)
		task.delay(3, function()
			if not s.IsLoaded then
				warn(("[Ptero] hit sound %s did NOT load -- usually audio privacy " ..
					"('Asset is not approved for the requester'). Reupload it on this account.")
					:format(HIT_SFX))
			end
		end)
	end

	-- ===== THE FUEL IT COSTS =====
	-- A sixth of what you are still carrying. Taken through BottomHUD's hook so the bar, the
	-- raw power and the server all move together -- see _G.dinoDrainFuelFraction.
	if type(_G.dinoDrainFuelFraction) == "function" then
		local lost = _G.dinoDrainFuelFraction(FUEL_BITE)
		if lost and lost > 0 then
			print(("[Ptero] hit -- knocked down, %.0f fuel lost (1/6 of what was left)"):format(lost))
		end
	end

	-- ===== RIDDEN DOWN TO THE ISLAND BELOW =====
	-- One BodyVelocity, re-aimed every frame, held until the Humanoid finds a floor. Re-aiming
	-- matters: the steer is a bearing to an island several hundred studs sideways, and a
	-- velocity set once at the top of a long fall overshoots it. Recomputing keeps you pointed
	-- at the island the whole way down instead of sailing past it into the gap.
	task.spawn(function()
		local drive = Instance.new("BodyVelocity")
		drive.Name = "PteroKnockdown"
		drive.MaxForce = Vector3.new(28000, 1e6, 28000)  -- firm, but the player still has weight
		drive.Parent = hrp

		local t0 = os.clock()
		while os.clock() - t0 < RIDE_TIMEOUT do
			local char = player.Character
			if not (char and hrp.Parent) then break end
			-- Grounded ends it -- but not in the first instant, before the shove has moved
			-- anyone, or a hit taken while brushing a ledge would cancel itself immediately.
			if os.clock() - t0 > 0.25 and isGrounded(char) then break end

			local target = islandBelow(hrp.Position.Y)
			local steer  = Vector3.zero
			if target then
				local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
				if flat.Magnitude > 1 then steer = flat.Unit * KNOCK_STEER end
			end
			drive.Velocity = Vector3.new(steer.X, -KNOCK_DOWN, steer.Z)

			-- Renew the lease rather than setting it once: a timestamp that is always ~0.6 s
			-- ahead keeps thrust off for as long as this loop is alive, and expires by itself
			-- if the loop ever is not.
			_G.flightLockUntil = os.clock() + LOCK_LEASE
			RunService.Heartbeat:Wait()
		end

		drive:Destroy()
		_G.flightLockUntil = 0   -- landed (or timed out): fly again
	end)
end

--======================================================================
-- THE LOOP
--======================================================================
local spawnTimer = 0

RunService.Heartbeat:Connect(function(dt)
	local now  = os.clock()
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local band = inBand(hrp.Position.Y)
	local grounded = isGrounded(char)

	-- ---- spawn ----
	if band and #alive < MAX_ALIVE then
		spawnTimer = spawnTimer + dt
		if spawnTimer >= SPAWN_EVERY then
			spawnTimer = 0
			spawnPtero(hrp)
		end
	else
		spawnTimer = 0
	end

	-- ---- fly, flap, test ----
	for i = #alive, 1, -1 do
		local b = alive[i]
		if not b.model or not b.model.Parent then
			table.remove(alive, i)
		else
			b.pos = b.pos + b.dir * (SPEED * dt)

			-- Bank slightly into the flap so the bird is never dead level.
			local flap = math.sin(now * FLAP_HZ * math.pi * 2 + b.phase) * FLAP_AMP
			local roll = math.sin(now * FLAP_HZ * math.pi * 2 + b.phase) * 0.10
			poseBird(b, CFrame.lookAt(b.pos, b.pos + b.dir) * CFrame.Angles(0, 0, roll), flap)

			-- Grounded players are immune -- the hazard belongs to the crossing, and being
			-- swatted off an island you already earned would read as the game cheating.
			-- (Between islands you are never grounded, so this only matters at the edges.)
			if not grounded and (b.pos - hrp.Position).Magnitude <= HIT_RADIUS then
				onHit(hrp, b.pos, b.pal)
				killBird(i)
			elseif now >= b.dieAt then
				killBird(i)
			end
		end
	end
end)

-- Clear the sky on respawn -- otherwise dying mid-crossing leaves a flock circling over
-- the island you come back on.
player.CharacterAdded:Connect(function()
	for i = #alive, 1, -1 do killBird(i) end
end)

do
	local names = {}
	for _, band in ipairs(bands) do
		local from = IslandOrder.NAMES[IslandOrder.SLOT_TO_ISLAND[band.crossing]] or "?"
		local to   = IslandOrder.NAMES[IslandOrder.SLOT_TO_ISLAND[band.crossing + 1]] or "?"
		table.insert(names, ("%d->%d (%s -> %s)"):format(band.crossing, band.crossing + 1, from, to))
	end
	print("[Ptero] ready -- crossings: " .. table.concat(names, ", "))
end
