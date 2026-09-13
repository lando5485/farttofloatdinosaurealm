--======================================================================
-- PetBarn.server.lua  (Script -> ServerScriptService)   [Bean Island]
--======================================================================
-- THE PET HUT. A small builder's hut on Bean Farm with a row of little beds outside its door. Walk up,
-- open the panel, pick one of your pets and drop it off. It curls up on a bed and goes to sleep. While it
-- naps it trickles a few coins -- exactly the shape of the campfire: a cozy nice-to-have, never a reason to
-- stop playing (the campfire's ceiling is 36 coins/min, this tops out at 30, active flight beats both ~50x).
--
-- ===== WHY THE PETS ARE VISIBLE TO EVERYONE =====
-- The obvious version of this feature is "pets sleep after their owner leaves", and it is worthless: nobody
-- is there to see it. The whole value is that the door step is a PILE OF EVERYONE'S PETS, with name tags, that
-- you walk past while you play. So the nap roster is SERVER state broadcast to every client, and every
-- client renders every sleeping pet -- yours and everyone else's.
--
-- ===== WHAT THIS SCRIPT OWNS =====
-- OWNS:      the BUILDING (wall/roof/beds), who is napping, which bed they hold, the coin trickle.
-- DOES NOT:  equip state. Dropping a pet off has to UNEQUIP it (or it would both follow you and sleep), and
--            equipping is PetSystem's business -- its sendState() is what makes PetFollow spawn/despawn the
--            follower, and that function is local to it. So the CLIENT fires PetEquipEvent (PetSystem's own
--            remote) alongside its drop/take, which routes the change through the normal path. We ALSO clear
--            _G.playerEquippedPet here so the authoritative flag is right even if a client skips its call.
-- DOES NOT:  the sleeping pet MODELS. Those are built per-client (see PetBarn.client.lua) from the same Union
--            templates PetFollow clones -- two dozen pets replicating CFrames every frame is not worth it for
--            scenery nobody inspects that closely.
--
-- ===== NO OFFLINE FARMING =====
-- The trickle only pays while the OWNER IS IN THE SERVER. Leaving does not bank coins. What leaving does do
-- is leave your pet asleep outside the hut for AWAY_KEEP minutes, greyed out and tagged "away" -- so the hut
-- still looks lived-in, and if you rejoin in that window your pet is still there waiting for you.
--
-- ===== THE MARKER, AND WHERE THE BEDS COME FROM =====
-- A Part named "pethouse" is the MARKER: its position and its facing decide where the hut goes and which
-- way its door points. The marker itself is hidden -- the hut is built on top of it, the same way Campfire
-- builds a fire on "CampfireSpot".
--
-- The beds are built HERE and named NapBed_0 .. NapBed_(MAX_SLOTS-1). The client finds a bed by name and
-- stands the pet on it. That is deliberate: the alternative is the server and the client each computing slot
-- positions from shared constants, which drift the moment one of them is edited. There is one layout, it
-- exists as actual parts in the world, and both sides read the same parts.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DUPLICATE GUARD ---------------------------------------------------------------------------------------
-- Same treatment Campfire and RealmPortals use, for the same reason: Rojo ADDS, it never overwrites, so a
-- stale copy baked into the place file runs alongside this one. Two copies here means two houses built on
-- the same spot, z-fighting through each other, and two coin trickles paying for one sleeping pet.
if _G.__PetBarnServer then
	warn("[PetBarn] a SECOND copy of PetBarn.server is running -- this one is bailing out. " ..
		"Delete the stale Script in Studio (Explorer > search 'PetBarn') and re-sync Rojo.")
	return
end
_G.__PetBarnServer = true

--======================================================================
-- TUNING
--======================================================================
local HOUSE_PART_NAME = "pethouse" -- matched case-insensitively; the Part already placed on Bean Farm
local DROP_RADIUS     = 70         -- studs: how close you must be to drop off / take back. Server-checked.
local AWAY_KEEP       = 15 * 60    -- seconds a pet stays in the beds after its owner leaves, then it's evicted

local TICK            = 10         -- seconds between coin payouts
-- Coins per tick, by the pet's AGE (level). Level 1 -> 1 coin/10s (6/min); level 25 -> 5 coins/10s (30/min).
-- Deliberately under the campfire's 36/min ceiling, and it scales with age so there's a reason to nap your
-- best pet rather than your throwaway one.
local function coinsForLevel(level)
	return math.clamp(1 + math.floor((tonumber(level) or 1) / 6), 1, 5)
end

-- ===== HUT DIMENSIONS (studs) =====
-- HUT_R and the marker's position/facing are FIXED: the path, the pavilion and the trees are laid out around
-- that circle. Everything else is free.
local MODEL_NAME  = "PetHut"
local HUT_R       = 5.5   -- radius of the round wall  [FIXED]
local HUT_H       = 7.8   -- wall height. Set by the DOOR, not by taste. The arch crown reaches
                          -- DOOR_STRAIGHT + doorHalf + 2*jamb = 6.93, and the TOP TRIM BAND occupies the
                          -- last 0.6 studs of the wall -- so the wall has to finish 0.6 ABOVE the crown, not
                          -- level with it, or the arch grows straight through the trim. Thickening the arch
                          -- frame is what pushed this from 7.0.
local WALL_T      = 0.9
local WALL_SEGS   = 14    -- blocks the wall ring is made of
local DOOR_SEGS   = 3     -- blocks left out for the entrance. MUST BE ODD: the gap is segment 0 plus a
                          -- matched pair either side, which is the only way it lands centred on the front.
local DOOR_STRAIGHT = 2.4 -- straight height of the opening; the arch adds (doorHalf + jamb) on top

local FOUND_R     = HUT_R + 2.6 -- stone foundation
local FOUND_H1    = 0.5
local FOUND_H2    = 0.4
local TRIM_H      = 1.0   -- wooden trim band at the foot of the wall

local PILLARS     = 2     -- rounded pillars PER SIDE (4 total). Four implies structure; six became a
local PILLAR_START = math.rad(100) -- colonnade. Angles clear both the entrance gap and the windows.
local PILLAR_ARC   = math.rad(55)

local WINDOW_ANGLE = math.rad(66) -- far enough round that the frame clears the 45-degree entrance gap
local WINDOW_R     = 1.05

local ROOF_TIERS  = 5     -- thick shingle courses. Five reads as layered; more just costs parts.
local ROOF_R      = 9.4   -- widest point, at the eaves -- 3.9 studs proud of the wall
local ROOF_TOP_R  = 1.0
local ROOF_H      = 5.6

local LAMP_BRIGHT = 2.0
local LAMP_RANGE  = 15
local SIGN_X      = HUT_R + 3.2  -- where the POST stands
local SIGN_BEAM_LEN = 6.6 -- how far the beam cantilevers out from the post. This is the number that keeps the
                          -- post off the board: the board is centred at SIGN_X - BEAM_LEN/2 and is 5.2 wide,
                          -- so its near edge lands 0.36 studs clear of the post's face. Shorten the beam and
                          -- the post starts covering the sign again, which is the bug this replaced.
local PATH_SLABS  = 3     -- see the note where they are laid: the run stops short of the bed arc
local PATH_STEP   = 1.4

local MAX_SLOTS   = 8     -- a hut sleeps a handful of pets, not a car park
local BED_ARC_R   = 14.0  -- far enough out to clear both the eaves (9.4) and the end of the path
local BED_ARC_SPREAD = math.rad(150)

-- ===== GLOW ===== two switches, because "glowing lantern" and "bright hut" are different things.
--
-- LIT  -- PointLights. OFF. Nothing here throws light onto the world, blooms, or washes out the colours
--         around it. This is what was asked for and it stays off.
-- GLOW -- emissive surfaces. ON, and ONLY on the two lantern bulbs. A Neon bulb the size of a fist reads as
--         a lit lantern from across the yard without lighting anything, which is the look the brief wants:
--         warm glowing lanterns flanking the door, on a hut that is not itself bright.
--
-- Everything that could emit in this file goes through emissive()/addLight(), so these two lines are the
-- whole lighting story. The windows, the counter and the finial are deliberately NOT emissive: three more
-- glowing things would be exactly the "bright" this is trying to avoid.
local LIT         = false
local GLOW        = true
local LAMP_COL    = Color3.fromRGB(255, 214, 150) -- the one warm tone every light in the file uses

-- ===== PALETTE ===== cream walls, warm timber, stone, and one gold for the finial
-- Warm and light throughout: nothing in here goes below ~40% value, because "dark colours" is on the avoid
-- list and a brown that reads rich in isolation reads muddy against cream at distance.
local CREAM   = Color3.fromRGB(248, 238, 216)   -- plaster walls
local CREAM_D = Color3.fromRGB(232, 216, 188)   -- their soft shaded bevel
local WOOD    = Color3.fromRGB(186, 138, 86)    -- trim, pillars, sign plank
local WOOD_D  = Color3.fromRGB(140, 96, 56)     -- archway, brackets, caps -- lifted out of near-black brown
local STONE   = Color3.fromRGB(196, 192, 182)   -- foundation top, path
local STONE_D = Color3.fromRGB(164, 158, 148)   -- foundation base, rocks
local SHINGLE_A = Color3.fromRGB(214, 172, 116) -- TAN shingle courses, alternating...
local SHINGLE_B = Color3.fromRGB(196, 152, 98)
local SHINGLE_LIT = Color3.fromRGB(234, 198, 146) -- ...and the lighter bevel under each edge
local GOLD    = Color3.fromRGB(240, 196, 88)    -- finial + door handles
local IRON    = Color3.fromRGB(104, 102, 108)
local GREEN   = Color3.fromRGB(126, 190, 92)    -- bushes, stems
local FLOWER  = Color3.fromRGB(240, 142, 172)
local FLOWER2 = Color3.fromRGB(250, 212, 106)
local CLAY    = Color3.fromRGB(198, 120, 86)    -- pots
local CLAY_D  = Color3.fromRGB(166, 96, 68)
local MAT     = Color3.fromRGB(214, 184, 140)   -- welcome mat + interior mat
local MAT_D   = Color3.fromRGB(150, 116, 78)    -- its border and the carved paw
local CUSHION_A = Color3.fromRGB(232, 214, 186) -- the bed pads, two muted tones instead of four bright ones
local CUSHION_B = Color3.fromRGB(206, 186, 158)
-- SIGN timber, three tones warm-to-warmer so post, border and face read apart without a texture between them
local SIGN_DARK = Color3.fromRGB(152, 106, 62)  -- post, beam, brace, carved paw
local SIGN_MID  = Color3.fromRGB(184, 136, 84)  -- the thick rounded border
local SIGN_FACE = Color3.fromRGB(214, 172, 116) -- the inset panel the lettering sits on
-- The three warm surfaces, in their lit and unlit values. See the LIT note above for why they differ.
local PANE    = Color3.fromRGB(236, 216, 176)   -- window glass: painted, not lit
local LAMP_FILL= GLOW and Color3.fromRGB(255, 228, 166) or Color3.fromRGB(230, 204, 148) -- lantern bulbs: a
                                                -- colour picked to glow reads washed-out when it doesn't
local ORB     = Color3.fromRGB(226, 190, 124)   -- counter glow

--======================================================================
-- REMOTES
--======================================================================
local function getOrCreateRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local PetBarnEvent = getOrCreateRemote("PetBarnEvent") -- c->s: ("drop", storageKey) / ("take") / ("sync")
local PetBarnState = getOrCreateRemote("PetBarnState") -- s->c: (array of nap entries)

--======================================================================
-- FINDING THE MARKER
--======================================================================
-- StreamingEnabled is on and the world loads in pieces, so the part is routinely not there yet when this
-- script starts. Poll rather than WaitForChild -- and match the name case-insensitively, because
-- "pethouse" / "PetHouse" / "petHouse" are the same intent and a capital letter should not break it.
-- Returns (cframe, size). A Model named "pethouse" is accepted as well as a Part -- if the thing in the place
-- file turns out to be a grouped placeholder rather than a single brick, silently doing nothing would be a
-- miserable way to find that out.
local function findMarker()
	local want = HOUSE_PART_NAME:lower()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name:lower() == want and not (d:FindFirstAncestor(MODEL_NAME) or d:FindFirstAncestor("PetHouse")) then
			if d:IsA("BasePart") then
				return d, d.CFrame, d.Size
			elseif d:IsA("Model") then
				local ok, cf, size = pcall(function()
					local c, s = d:GetBoundingBox()
					return c, s
				end)
				if ok and cf then return d, cf, size end
			end
		end
	end
	return nil
end

--======================================================================
-- BUILDING THE HOUSE
--======================================================================
local houseCF = nil     -- flattened (yaw-only) CFrame at ground level under the hut

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = true; p.CastShadow = true
	local SM = Enum.SurfaceType.Smooth
	p.TopSurface = SM; p.BottomSurface = SM; p.LeftSurface = SM; p.RightSurface = SM; p.FrontSurface = SM; p.BackSurface = SM
	p.Parent = parent
	return p
end
local function deco(p) -- scenery: no collision, no queries, cheap
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	return p
end
-- The only two ways this file is allowed to make something glow, so LIT above can switch all of it at once.
local function emissive(p)
	if GLOW then p.Material = Enum.Material.Neon end
	return p
end
local function addLight(parent, brightness, range)
	if not LIT then return nil end
	local l = Instance.new("PointLight")
	l.Color = LAMP_COL; l.Brightness = brightness; l.Range = range; l.Shadows = false
	l.Parent = parent
	return l
end
--======================================================================
-- BUILDING THE HUT
--======================================================================
-- Cream drum on a clean stone foundation, rounded corner pillars, a wide arched entrance, and a shingled
-- cone with a golden finial. Built for READ AT DISTANCE: big shapes, few of them, clean silhouette.
--
-- ===== SIMPLICITY IS THE BRIEF =====
-- Every detail here has to earn its place from twenty studs away. The previous pass had a fence railing with
-- balusters, plank seams across the deck, eighteen grass tufts and a shelf of supply crates -- none of which
-- resolve at play distance, all of which cost parts and muddy the outline. They are gone. What is left is
-- fewer, larger, rounder shapes: that is what makes it read as a finished asset rather than a busy one.
--
-- ===== WHAT IS FIXED =====
-- The marker's position and facing, HUT_R, and the bed arc in front of the door. The path, the pavilion and
-- the trees are laid out around those.
--
-- ===== THE BEDS ARE PARTS, NOT MATHS =====
-- Named NapBed_0 .. NapBed_(MAX_SLOTS-1). The client stands a sleeping pet on one BY NAME, so this file is
-- the only place the layout exists and the two can never disagree about where a pet is standing.

local function buildHouse(markerCF, markerSize)
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local look = markerCF.LookVector
	local yaw  = math.atan2(-look.X, -look.Z)
	local pos  = markerCF.Position
	local groundY = pos.Y - markerSize.Y / 2
	local base = CFrame.new(Vector3.new(pos.X, groundY, pos.Z)) * CFrame.Angles(0, yaw, 0)

	-- Hut space: +X right, +Y up, -Z out the front door.
	local function at(x, y, z, rx, ry, rz)
		local cf = base * CFrame.new(x, y, z)
		if rx or ry or rz then cf = cf * CFrame.Angles(rx or 0, ry or 0, rz or 0) end
		return cf
	end
	-- A flat disc lying face-up. A Cylinder's axis is its own X, so rolling it 90 degrees stands it on its face.
	local function disc(parent, name, radius, thick, y, color)
		local p = part(parent, name, Vector3.new(thick, radius * 2, radius * 2),
			at(0, y, 0, 0, 0, math.rad(90)), color, Enum.Material.SmoothPlastic)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- Somewhere on the wall circle at angle `a`, `out` studs proud of it, turned to face outward.
	local function onWall(a, y, out)
		local r = HUT_R + (out or 0)
		return at(math.sin(a) * r, y, -math.cos(a) * r, 0, -a, 0)
	end
	-- An upright cylinder (a rounded post). Rolling 90 degrees about Z stands the axis up.
	local function post(parent, name, radius, height, cf, color)
		local p = part(parent, name, Vector3.new(height, radius * 2, radius * 2),
			cf * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.SmoothPlastic)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- A low-poly paw print: a pad and four splayed toes, laid in the CFrame's X/Z plane and thin along its Y.
	-- Used three times (mat, wall, sign) from one definition, so they always match.
	--
	-- ===== WHY THESE ARE CYLINDERS AND NOT BALLS =====
	-- They were Ball parts sized (0.95, 0.16, 0.8) -- an ellipsoid, if Roblox had one. It does not. A Ball
	-- part ALWAYS renders a true sphere and takes the SMALLEST axis as its diameter, so every piece of this
	-- collapsed to a 0.16-stud bead: the pad became a dot, the four toes became four smaller dots, and the
	-- paw print became five brown dots in a rough cross. That is exactly what it looked like in game.
	--
	-- A Cylinder is the shape Roblox will actually squash. Rolled 90 degrees about Z its length runs along
	-- the print's local Y (so Size.X is the THICKNESS off the surface) and its cross-section is a real
	-- ELLIPSE in the local X/Z plane -- so the pad can be wider than it is deep and the toes can be longer
	-- than they are wide, which is the whole difference between "a paw" and "a dot".
	local function pawDisc(parent, name, cf, thick, w, d, color)
		local p = deco(part(parent, name, Vector3.new(thick, w, d),
			cf * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.SmoothPlastic))
		p.Shape = Enum.PartType.Cylinder; p.CastShadow = false
		return p
	end
	local function pawPrint(parent, name, cf, s, color)
		-- THE PAD: set back, and wider than it is deep. A circle here reads as a button; the squash is what
		-- makes it a heel.
		pawDisc(parent, name, cf * CFrame.new(0, 0, 0.22 * s), 0.16 * s, 1.04 * s, 0.78 * s, color)
		-- FOUR TOES on an arc in front of it. Three things make them read as toes rather than as beads:
		-- they are longer than they are wide (0.34 x 0.46), the middle pair sits further FORWARD than the
		-- outer pair, and each one is splayed outward a little so they fan the way real toes do.
		for _, i in ipairs({ -1.5, -0.5, 0.5, 1.5 }) do
			local lead = (1.5 - math.abs(i)) * 0.10 -- middle toes lead
			pawDisc(parent, name .. "Toe",
				cf * CFrame.new(i * 0.32 * s, 0, -(0.40 + lead) * s) * CFrame.Angles(0, math.rad(-i * 14), 0),
				0.15 * s, 0.34 * s, 0.46 * s, color)
		end
	end

	local step     = (2 * math.pi) / WALL_SEGS
	local doorHalf = HUT_R * math.sin(DOOR_SEGS * step / 2)
	-- THE DOOR PLANE. The entrance frame is flat, but the wall it sits in is a circle -- so the frame has to
	-- sit on the CHORD that closes the gap, not out at -HUT_R. Built at -HUT_R the jambs stood 1.4 studs
	-- forward of where the wall actually curves back to, with clear daylight between frame and building.
	-- On the chord they land right on the wall's cut ends.
	local doorZ    = -HUT_R * math.cos(DOOR_SEGS * step / 2)
	local FLOOR_Y  = FOUND_H1 + FOUND_H2
	local wallTop  = FLOOR_Y + HUT_H

	--======================================================================
	-- FOUNDATION -- two clean stone discs, the upper one inset, so the edge is a soft step not a cliff
	--======================================================================
	do
		local s1 = disc(model, "FoundationBase", FOUND_R, FOUND_H1, FOUND_H1 / 2, STONE_D)
		s1.CanCollide = true; s1.CanQuery = false
		-- CHAMFER: a slightly narrower, lighter ring capping the base. Roblox has no bevelled cylinder, and a
		-- single inset ring is the cheapest honest way to break the hard 90-degree rim -- without it the
		-- foundation reads as a cut disc, which is the "sharp edge" the brief rules out.
		deco(disc(model, "FoundationChamfer", FOUND_R - 0.28, 0.22, FOUND_H1 - 0.06, STONE))
		local s2 = disc(model, "FoundationTop", FOUND_R - 0.7, FOUND_H2, FOUND_H1 + FOUND_H2 / 2, STONE)
		s2.CanCollide = true; s2.CanQuery = false
		deco(disc(model, "FoundationTopChamfer", FOUND_R - 0.95, 0.18, FOUND_H1 + FOUND_H2 - 0.05, STONE))
		-- one step at the door, sunk 0.02 so it can never share a plane with the foundation it sits on
		local stp = part(model, "Step", Vector3.new(doorHalf * 2 + 1.2, FLOOR_Y, 1.6),
			at(0, FLOOR_Y / 2 - 0.02, -(FOUND_R - 0.2)), STONE, Enum.Material.SmoothPlastic)
		stp.CanCollide = true; stp.CanQuery = false
	end

	--======================================================================
	-- WALLS -- cream drum, wooden trim top and bottom, rounded corner pillars
	--======================================================================
	do
		local segW = (2 * math.pi * HUT_R / WALL_SEGS) * 1.2 -- overlap so the joins don't show
		local skip = {}
		skip[0] = true -- segment 0 is dead centre of the front; skipping outward from it centres the door
		for k = 1, math.floor(DOOR_SEGS / 2) do skip[k] = true; skip[WALL_SEGS - k] = true end
		for i = 0, WALL_SEGS - 1 do
			if not skip[i] then
				part(model, "Wall", Vector3.new(segW, HUT_H, WALL_T), onWall(i * step, FLOOR_Y + HUT_H / 2, 0),
					CREAM, Enum.Material.SmoothPlastic)
			end
		end
		-- rich wooden trim: a thick band at the foot and a matching one under the eaves, each capped by a
		-- narrower lighter ring so the band rolls off into the plaster instead of ending on a hard lip
		-- RADIUS MATTERS HERE. The wall blocks are centred on HUT_R and are WALL_T thick, so their outer face
		-- is at HUT_R + WALL_T/2 = 5.95. Every one of these rings was authored at HUT_R + 0.4 or less, which
		-- put all four of them INSIDE the wall -- invisible. They have to clear 5.95 to exist at all.
		deco(disc(model, "TrimBase", HUT_R + 0.8, TRIM_H, FLOOR_Y + TRIM_H / 2, WOOD))
		deco(disc(model, "TrimBaseBevel", HUT_R + 0.62, 0.22, FLOOR_Y + TRIM_H - 0.05, CREAM_D))
		deco(disc(model, "TrimTop",  HUT_R + 0.8, 0.6, wallTop - 0.3, WOOD))
		deco(disc(model, "TrimTopBevel", HUT_R + 0.62, 0.2, wallTop - 0.62, CREAM_D))
		-- ROUNDED CORNER PILLARS. Cylinders, not blocks: a round pillar on a round wall is the detail that
		-- stops the drum reading as a stack of flat panels, and four is enough to imply structure without
		-- turning the wall into a colonnade.
		for i = 0, PILLARS - 1 do
			local a = PILLAR_START + i * (PILLAR_ARC / (PILLARS - 1))
			for _, sgn in ipairs({ 1, -1 }) do
				local aa = sgn * a
				-- 0.55 out, not 0.42: the trim rings now reach r=6.30, and at 0.42 the pillar stood only 0.14
				-- proud of them -- close enough to read as a bump in the trim rather than a pillar in front of it.
				deco(post(model, "Pillar", 0.52, HUT_H + 0.2, onWall(aa, FLOOR_Y + (HUT_H + 0.2) / 2, 0.55), WOOD))
				deco(post(model, "PillarFoot", 0.7, 0.55, onWall(aa, FLOOR_Y + 0.28, 0.55), STONE_D))
				deco(post(model, "PillarCap", 0.68, 0.4, onWall(aa, FLOOR_Y + HUT_H + 0.05, 0.55), WOOD_D))
			end
		end
	end

	--======================================================================
	-- ENTRANCE -- one polished archway, deliberately wide
	--======================================================================
	do
		-- ONE arch ring, standing proud of the wall. There was a second recessed ring behind it for depth --
		-- 9 parts -- but once the doors shut and the tympanum filled the head, all of it sat half a stud
		-- BEHIND an opaque surface. Depth you cannot see is just part count.
		local jambR = 0.55
		for _, sx in ipairs({ -1, 1 }) do
			deco(post(model, "ArchJamb", jambR, DOOR_STRAIGHT + 0.3,
				at(sx * (doorHalf + jambR), FLOOR_Y + (DOOR_STRAIGHT + 0.3) / 2, doorZ - 0.12), WOOD_D))
		end
		-- ARCH: seven voussoirs. At this radius seven already reads as a curve, and every extra one is a part
		-- that changes nothing you can see from the path.
		local aR = doorHalf + jambR
		for i = 0, 6 do
			local a = math.pi * ((i + 0.5) / 7)
			local ay = FLOOR_Y + DOOR_STRAIGHT + 0.15
			deco(part(model, "Arch", Vector3.new(1.35, jambR * 2, 1.5),
				at(math.cos(a) * aR, ay + math.sin(a) * aR, doorZ - 0.12, 0, 0, a + math.rad(90)),
				WOOD_D, Enum.Material.SmoothPlastic))
		end
		-- NO HEAD PANEL. It used to be a full disc of radius doorHalf centred on the arch's springing point,
		-- which meant its lower half sat squarely across the opening -- a cream plate filling the doorway the
		-- doors had just been swung clear of. Roblox has no half-cylinder to replace it with, and faking one
		-- from stepped slabs is four parts to close a hole that looks better open: through the arch you now
		-- see the lit counter, which is the point of having the doors open at all.

		-- ===== THE DOORS ARE SHUT, AND THEY FILL THE WHOLE ARCH =====
		-- You are not meant to get inside the hut, so the entrance is closed with real geometry rather than an
		-- invisible slab: the two leaves meet on the centre line and collide like wall, because with the doors
		-- shut that is exactly what they are.
		--
		-- THE FIX THIS BLOCK EXISTS FOR. The leaves used to be plain DOOR_STRAIGHT-tall rectangles, and the
		-- half-round above them was filled by a separate CREAM "tympanum" -- so the entrance read as a short
		-- door with a big pale panel above it, and the pale panel was where your eye went. There is no
		-- tympanum any more. Each leaf now carries its own stepped top tracing the arch, in the same wood as
		-- the rest of the door, so the opening is DOOR from the threshold all the way to the crown.
		--
		-- WHY EACH STEP TAKES ITS WIDTH AT ITS OWN BOTTOM EDGE. Sized to its TOP edge a step would be
		-- narrower than the curve for its whole height and leave a sliver of daylight down each side -- the
		-- exact gap this is fixing. Sized to its BOTTOM edge it always reaches past the curve instead, and the
		-- overhang is swallowed by the arch ring, which is 1.1 studs thick: the worst outer corner lands at
		-- r=3.92 against a ring spanning 3.43..4.53. Overshoot is free; undershoot is a hole.
		local ARCH_STEPS = 6
		local SEAM       = 0.02   -- half-gap either side of the centre line: a seam you can see, not a gap
		local DOOR_T     = 0.34
		local springY    = FLOOR_Y + DOOR_STRAIGHT + 0.15   -- where the straight part ends and the curve begins
		local lowerH     = springY - FLOOR_Y
		local faceZ      = -(DOOR_T / 2 + 0.05)             -- just proud of the leaf, for every applied detail

		for _, sx in ipairs({ -1, 1 }) do
			-- LOWER LEAF -- threshold up to the springing line
			local lowW = doorHalf - SEAM
			local lowCF = at(sx * (SEAM + lowW / 2), FLOOR_Y + lowerH / 2, doorZ + 0.05)
			part(model, "DoorLeaf", Vector3.new(lowW, lowerH, DOOR_T), lowCF, WOOD, Enum.Material.SmoothPlastic)

			-- ARCHED TOP -- stepped slices tracing the curve, same wood, same plane, +0.02 tall so
			-- consecutive steps overlap instead of meeting on a shared face
			for k = 0, ARCH_STEPS - 1 do
				local yBot = (k / ARCH_STEPS) * doorHalf
				local w = math.sqrt(math.max(doorHalf * doorHalf - yBot * yBot, 0)) - SEAM
				local h = doorHalf / ARCH_STEPS
				part(model, "DoorArchTop", Vector3.new(w, h + 0.02, DOOR_T),
					at(sx * (SEAM + w / 2), springY + yBot + h / 2, doorZ + 0.05), WOOD, Enum.Material.SmoothPlastic)
			end

			-- PLANK LINES -- full height of the straight part
			for k = 1, 2 do
				deco(part(model, "DoorPlank", Vector3.new(0.12, lowerH - 0.25, 0.1),
					lowCF * CFrame.new((k - 1.5) * (lowW / 2.2), 0, faceZ), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
			end
			-- CROSS-BRACE -- one dark band across the leaf
			deco(part(model, "DoorBrace", Vector3.new(lowW - 0.12, 0.3, 0.12),
				lowCF * CFrame.new(0, lowerH * 0.16, faceZ), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
			-- HINGE PLATES -- on the OUTER edge, against the jamb, which is what makes it read as hung
			for _, hy in ipairs({ -0.72, 0.72 }) do
				deco(part(model, "DoorHinge", Vector3.new(0.85, 0.22, 0.12),
					lowCF * CFrame.new(sx * (lowW / 2 - 0.45), hy, faceZ), IRON, Enum.Material.SmoothPlastic)).CastShadow = false
			end
			-- RING PULL at the seam -- backplate first, so the ring has something to read against
			local rx = -sx * (lowW / 2 - 0.3)
			deco(part(model, "DoorPlate", Vector3.new(0.34, 0.34, 0.1),
				lowCF * CFrame.new(rx, 0.1, faceZ), IRON, Enum.Material.SmoothPlastic)).CastShadow = false
			local ring = deco(part(model, "DoorRing", Vector3.new(0.12, 0.5, 0.5),
				lowCF * CFrame.new(rx, -0.12, faceZ - 0.05) * CFrame.Angles(0, math.rad(90), 0),
				GOLD, Enum.Material.SmoothPlastic))
			ring.Shape = Enum.PartType.Cylinder; ring.CastShadow = false
		end

		-- WELCOME MAT with a carved paw, laid across the threshold
		-- OUTSIDE the door plane, on the deck, where you actually wipe your feet
		local matZ = doorZ - 1.1
		deco(part(model, "Mat", Vector3.new(doorHalf * 1.7, 0.14, 1.5), at(0, FLOOR_Y + 0.07, matZ), MAT, Enum.Material.SmoothPlastic)).CanCollide = false
		deco(part(model, "MatEdge", Vector3.new(doorHalf * 1.85, 0.1, 1.7), at(0, FLOOR_Y + 0.05, matZ), MAT_D, Enum.Material.SmoothPlastic)).CastShadow = false
		pawPrint(model, "MatPaw", at(0, FLOOR_Y + 0.15, matZ), 1.0, MAT_D)
	end

	-- CARVED PAWS in the plaster, one either side, sat between the window and the pillar where the wall is
	-- otherwise blank. Recessed rather than raised (CREAM_D, barely proud) so they read as pressed into the
	-- render, not stuck on it -- a raised paw here would compete with the one on the sign.
	-- On a PLAQUE, not straight onto the render. The wall is a ring of flat chords, so its outer surface sits
	-- anywhere from 5.95 to 6.05 depending on the angle -- and a paw print is only 0.09 studs thick, far too
	-- thin to reliably straddle that. The plaque is thick enough to bite into the wall at any angle, and the
	-- paw then only has to sit on the plaque.
	for _, sgn in ipairs({ -1, 1 }) do
		local a = sgn * math.rad(87.5)
		local pl = part(model, "WallPlaque", Vector3.new(0.5, 2.0, 2.0),
			onWall(a, FLOOR_Y + HUT_H * 0.55, 0.5) * CFrame.Angles(0, math.rad(90), 0), CREAM_D, Enum.Material.SmoothPlastic)
		pl.Shape = Enum.PartType.Cylinder; deco(pl)
		pawPrint(model, "WallPaw", onWall(a, FLOOR_Y + HUT_H * 0.55, 0.78) * CFrame.Angles(math.rad(90), 0, 0), 0.62, WOOD)
	end

	--======================================================================
	-- WINDOWS -- two, framed, quiet
	--======================================================================
	for _, sgn in ipairs({ -1, 1 }) do
		local a = sgn * WINDOW_ANGLE
		local y = FLOOR_Y + HUT_H * 0.58
		-- Pushed out past the wall's 5.95 outer face (they were at 5.6-5.8, i.e. buried). The frame straddles
		-- the face so it is anchored in the wall; the pane sits BEHIND the frame's outer lip so the window
		-- reads as recessed rather than as a disc stuck on the render.
		local f = part(model, "WindowFrame", Vector3.new(0.5, (WINDOW_R + 0.34) * 2, (WINDOW_R + 0.34) * 2),
			onWall(a, y, 0.62) * CFrame.Angles(0, math.rad(90), 0), WOOD_D, Enum.Material.SmoothPlastic)
		f.Shape = Enum.PartType.Cylinder; deco(f)
		local pane = part(model, "WindowPane", Vector3.new(0.4, WINDOW_R * 2, WINDOW_R * 2),
			onWall(a, y, 0.55) * CFrame.Angles(0, math.rad(90), 0), PANE, Enum.Material.SmoothPlastic)
		pane.Shape = Enum.PartType.Cylinder; deco(pane); pane.CastShadow = false
		addLight(pane, 1.4, 13)
		-- the bar sits on the PANE (which reaches 6.25), not on the wall -- 0.72 is measured to meet the glass
		deco(part(model, "WindowBar", Vector3.new(0.13, WINDOW_R * 2 - 0.1, 0.14), onWall(a, y, 0.72), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
	end

	--======================================================================
	-- ROOF -- thick shingle courses, soft bevelled edges, deeper overhang on clean brackets
	--======================================================================
	do
		local tierH = ROOF_H / ROOF_TIERS
		-- BRACKETS under the eave. Six, evenly spaced, angled out to meet the overhang -- this is what makes a
		-- deep overhang look supported instead of stuck on.
		-- EIGHT chunky brackets on an even 36-degree pitch, mirrored about the front. The sweep deliberately
		-- starts at 52 degrees and stops at 160: the entrance gap runs to 38.6 degrees, and an evenly-spaced
		-- ring that ignored it would hang a bracket in the open doorway held up by nothing. Spacing inside the
		-- run is identical, which is the part the eye actually checks.
		for i = 0, 3 do
			for _, sgn in ipairs({ 1, -1 }) do
				local a = sgn * math.rad(52 + i * 36)
				-- Depth and offset are set so the outer end BITES INTO the eave: at 30 degrees the radial
				-- half-reach is (depth*cos30 + width*sin30)/2, so 2.6 deep at r=7.05 tops out at 8.60, past
				-- tier 0's 8.56. At the old 1.9/1.0 it stopped 0.81 short and the roof sat on nothing -- and
				-- merely touching at 8.55 would still leave a hairline where the two meet.
				deco(part(model, "Bracket", Vector3.new(0.62, 1.7, 2.6),
					onWall(a, wallTop - 1.1, 1.55) * CFrame.Angles(math.rad(-30), 0, 0), WOOD_D, Enum.Material.SmoothPlastic))
				-- a small square boss where each bracket meets the wall, so it lands on something
				deco(part(model, "BracketBoss", Vector3.new(0.9, 0.9, 0.4),
					onWall(a, wallTop - 1.35, 0.55), WOOD, Enum.Material.SmoothPlastic)).CastShadow = false
			end
		end
		for i = 0, ROOF_TIERS - 1 do
			-- Radius sampled at each course's OWN MID-HEIGHT. Sampling at the base leaves the top course a
			-- full step too wide for any finial to close, which is the flat stub this shape keeps having to
			-- avoid; at mid-height the courses step down evenly AND the last one is narrow enough to cap.
			local t = (i + 0.5) / ROOF_TIERS
			local r = ROOF_R + (ROOF_TOP_R - ROOF_R) * t
			local yBase = wallTop - 0.15 + tierH * i -- bite into the wall top; flush would leave a seam
			-- BEVEL: a slightly wider, lighter disc under each course. Reads as a soft chamfered edge catching
			-- the light, which is the difference between "layered shingles" and "stacked plates".
			local bev = disc(model, "ShingleBevel", r + 0.28, tierH * 0.26, yBase + tierH * 0.14, SHINGLE_LIT)
			bev.CanCollide = false; bev.CanQuery = false; bev.CanTouch = false
			-- THICK course, alternating two tones so the cone is not one flat mass
			local d = disc(model, "Shingle", r, tierH * 0.84, yBase + tierH * 0.56,
				(i % 2 == 0) and SHINGLE_A or SHINGLE_B)
			d.CanCollide = (i == 0)
			if i > 0 then d.CanQuery = false; d.CanTouch = false end
		end

		-- GOLDEN FINIAL, refined: a short wooden neck, a turned gold collar, and one clean sphere. The collar
		-- is sized to overlap the top course so the ornament grows out of the roof rather than balancing on it.
		-- MEASURED OFF THE ACTUAL TOP COURSE, not off wallTop + ROOF_H. The courses start 0.15 below wallTop
		-- so they bite into the wall instead of sitting flush -- which left the whole finial 0.16 studs above
		-- the roof it is supposed to stand on. Derived, so the stack cannot drift apart again.
		local topR = ROOF_R + (ROOF_TOP_R - ROOF_R) * ((ROOF_TIERS - 0.5) / ROOF_TIERS)
		local lastTop = wallTop - 0.15 + tierH * (ROOF_TIERS - 1 + 0.98)
		deco(disc(model, "FinialCollar", topR * 1.02, 0.42, lastTop + 0.16, WOOD_D))
		deco(disc(model, "FinialRing", topR * 0.62, 0.3, lastTop + 0.50, GOLD))
		deco(post(model, "FinialNeck", 0.16, 0.85, at(0, lastTop + 1.0, 0), WOOD_D))
		local orb = deco(part(model, "FinialOrb", Vector3.new(1.05, 1.05, 1.05), at(0, lastTop + 1.75, 0), GOLD, Enum.Material.SmoothPlastic))
		orb.Shape = Enum.PartType.Ball
		addLight(orb, LAMP_BRIGHT, LAMP_RANGE + 6)
	end

	--======================================================================
	-- LANTERNS -- two, flanking the entrance, from one builder so they cannot drift apart
	--======================================================================
	local function lantern(name, cf, s)
		s = s or 1
		deco(post(model, name .. "Hook", 0.08 * s, 0.8 * s, cf * CFrame.new(0, 0.8 * s, 0), IRON)).CastShadow = false
		deco(part(model, name .. "Cap", Vector3.new(0.9 * s, 0.22 * s, 0.9 * s), cf * CFrame.new(0, 0.46 * s, 0), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
		local bulb = deco(part(model, name, Vector3.new(0.78 * s, 0.92 * s, 0.78 * s), cf, LAMP_FILL, Enum.Material.SmoothPlastic))
		bulb.CastShadow = false
		deco(part(model, name .. "Base", Vector3.new(0.9 * s, 0.2 * s, 0.9 * s), cf * CFrame.new(0, -0.5 * s, 0), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
		emissive(bulb); addLight(bulb, LAMP_BRIGHT, LAMP_RANGE * s)
		return bulb
	end
	-- ON THE WALL, by angle. Placed by x/z they sat at a fixed z either side of the door, which on a round
	-- wall left them hanging three studs out in front of it. 46 degrees clears the entrance gap (38.6) on one
	-- side and the window (from 51.8) on the other.
	for _, sgn in ipairs({ -1, 1 }) do
		local a, ly = sgn * math.rad(46), FLOOR_Y + HUT_H * 0.6
		-- The arm FIRST: lantern() draws a hook rising out of the bulb, and without something for that hook to
		-- reach the whole lamp hangs off thin air. This block straddles the wall face and runs out to the
		-- lantern's axis, so the hook lands on it.
		deco(part(model, "LanternArm", Vector3.new(0.26, 0.26, 0.95), onWall(a, ly + 1.2, 0.6), WOOD_D, Enum.Material.SmoothPlastic)).CastShadow = false
		deco(part(model, "LanternArmBoss", Vector3.new(0.5, 0.5, 0.3), onWall(a, ly + 1.2, 0.52), WOOD, Enum.Material.SmoothPlastic)).CastShadow = false
		lantern((sgn < 0) and "LanternL" or "LanternR", onWall(a, ly, 0.95))
	end

	--======================================================================
	-- PLANTING -- two bushes and two pots, at the entrance only
	--======================================================================
	do
		local function potPlant(x, z)
			-- sunk 0.03 into the deck: a base face at exactly FLOOR_Y is coplanar with the deck's top face,
			-- which is the textbook z-fight even though the pot is "resting on" it
			deco(post(model, "Pot", 0.6, 1.0, at(x, FLOOR_Y + 0.47, z), CLAY))
			deco(post(model, "PotRim", 0.7, 0.24, at(x, FLOOR_Y + 0.95, z), CLAY_D)).CastShadow = false
			local b = deco(part(model, "PotBush", Vector3.new(1.35, 1.2, 1.35), at(x, FLOOR_Y + 1.55, z), GREEN, Enum.Material.SmoothPlastic))
			b.Shape = Enum.PartType.Ball
			for _, o in ipairs({ { -0.42, 0.2 }, { 0.4, -0.24 } }) do
				local f = deco(part(model, "Flower", Vector3.new(0.42, 0.42, 0.42),
					at(x + o[1], FLOOR_Y + 2.0, z + o[2]), FLOWER, Enum.Material.SmoothPlastic))
				f.Shape = Enum.PartType.Ball; f.CastShadow = false
			end
		end
		-- Just the two potted ones flanking the door. The loose bushes that sat on the grass beside them were
		-- six more parts saying the same thing two studs away.
		potPlant(-(doorHalf + 1.5), -(HUT_R - 1.3)); potPlant(doorHalf + 1.5, -(HUT_R - 1.3))
	end

	--======================================================================
	-- SIGN -- a freestanding gallows sign: post, cantilevered beam, board hung clear of both
	--======================================================================
	-- ===== WHY THE POST MOVED =====
	-- The old build put the post at SIGN_X and centred the board at SIGN_X - 1.4 with a half-width of 2.3, so
	-- the board's right end ran to SIGN_X + 0.9 -- the post stood INSIDE the board and covered part of the
	-- lettering. The fix is not to nudge it: the post has to sit entirely outside the board's span, and the
	-- beam has to cantilever far enough that the board hangs over open air. Everything below is driven off
	-- SIGN_BEAM_LEN so that relationship can't quietly break again.
	--
	-- The player approaches from -Z looking toward +Z, which puts +X on their LEFT. The post is at the
	-- largest X and the board hangs at smaller X, so the post frames the sign from the left as asked.
	do
		local px, sz  = SIGN_X, -(HUT_R + 2.2)
		local postR   = 0.34
		local beamY   = FLOOR_Y + 6.0
		local boardW, boardH, boardT = 5.2, 2.6, 0.65   -- thick enough to read as sturdy from the path
		local bx      = px - SIGN_BEAM_LEN / 2           -- board centred under the beam's span
		local boardY  = FLOOR_Y + 3.95
		local capR    = 0.5                              -- corner rounding radius

		-- POST + BEAM. The beam runs from the post out to px - SIGN_BEAM_LEN; the board's far edge sits at
		-- bx - boardW/2, so the beam finishes a little past it rather than stopping short.
		-- The post runs from the GROUND, not from FLOOR_Y. It stands out on the grass past the foundation, so
		-- starting it at the hut's floor level would leave it hanging half a stud above its own footing.
		local postH = beamY + 0.5
		deco(post(model, "SignPost", postR, postH, at(px, postH / 2, sz), SIGN_DARK)).CanCollide = true
		deco(post(model, "SignPostCap", postR * 1.35, 0.3, at(px, postH + 0.05, sz), SIGN_MID)).CastShadow = false
		deco(post(model, "SignPostFoot", postR * 1.7, 0.5, at(px, 0.25, sz), STONE_D))
		deco(part(model, "SignBeam", Vector3.new(SIGN_BEAM_LEN, 0.42, 0.42),
			at(px - SIGN_BEAM_LEN / 2, beamY, sz), SIGN_DARK, Enum.Material.SmoothPlastic))

		-- DIAGONAL BRACE from the post down-and-out to the beam. Rotating a block about Z by the angle of the
		-- run is what makes it meet both ends flush instead of floating between them.
		do
			local x1, y1 = px - 0.3, beamY - 1.5      -- on the post
			local x2, y2 = px - 2.2, beamY - 0.28     -- under the beam
			local dx, dy = x2 - x1, y2 - y1
			deco(part(model, "SignBrace", Vector3.new(math.sqrt(dx * dx + dy * dy), 0.3, 0.3),
				at((x1 + x2) / 2, (y1 + y2) / 2, sz, 0, 0, math.atan2(dy, dx)), SIGN_DARK, Enum.Material.SmoothPlastic))
		end

		-- TWO SHORT CHAINS from the beam down to the board's top edge, so it hangs rather than floats.
		local chainTop, chainBot = beamY - 0.21, boardY + boardH / 2
		for _, ox in ipairs({ -1.7, 1.7 }) do
			deco(post(model, "SignChain", 0.09, chainTop - chainBot, at(bx + ox, (chainTop + chainBot) / 2, sz), IRON)).CastShadow = false
			local ring = deco(part(model, "SignRing", Vector3.new(0.12, 0.34, 0.34), at(bx + ox, chainBot + 0.1, sz, 0, math.rad(90), 0), IRON, Enum.Material.SmoothPlastic))
			ring.Shape = Enum.PartType.Cylinder; ring.CastShadow = false
		end

		-- ROUNDED-RECT BORDER. Roblox has no rounded box, so a real one is two overlapping slabs (one short of
		-- the corners horizontally, one short of them vertically) plus a cylinder at each corner. Capping the
		-- ENDS of a slab -- what the last version did -- gives a stadium, not rounded corners.
		local function roundedRect(name, w, h, t, cf, colour)
			deco(part(model, name, Vector3.new(w - capR * 2, h, t), cf, colour, Enum.Material.SmoothPlastic))
			deco(part(model, name, Vector3.new(w, h - capR * 2, t), cf, colour, Enum.Material.SmoothPlastic))
			for _, c in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
				local q = deco(part(model, name .. "Corner", Vector3.new(t, capR * 2, capR * 2),
					cf * CFrame.new(c[1] * (w / 2 - capR), c[2] * (h / 2 - capR), 0) * CFrame.Angles(0, math.rad(90), 0),
					colour, Enum.Material.SmoothPlastic))
				q.Shape = Enum.PartType.Cylinder; q.CastShadow = false
			end
		end
		roundedRect("SignBorder", boardW, boardH, boardT, at(bx, boardY, sz), SIGN_MID)
		-- the face panel, inset and a shade lighter -- that step is the "carved" read, no fine detail needed
		local face = part(model, "SignFace", Vector3.new(boardW - 0.85, boardH - 0.85, boardT * 0.55),
			at(bx, boardY, sz - boardT * 0.34), SIGN_FACE, Enum.Material.SmoothPlastic)
		deco(face)

		-- PAW centred ABOVE the text, standing proud of the face.
		pawPrint(model, "SignPaw", at(bx, boardY + 0.62, sz - boardT * 0.62, math.rad(90), 0, 0), 0.5, SIGN_DARK)

		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(340, 210); sg.LightInfluence = 1; sg.Parent = face
		local t = Instance.new("TextLabel")
		-- lower 45% of the panel: the raised paw occupies the top, and text under it would otherwise collide
		t.BackgroundTransparency = 1; t.Size = UDim2.new(1, -24, 0.45, 0); t.Position = UDim2.new(0, 12, 0.5, 0)
		t.Font = Enum.Font.FredokaOne; t.TextScaled = true; t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextColor3 = Color3.fromRGB(88, 52, 20); t.Text = "PET HUT"; t.Parent = sg
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(226, 190, 138); st.Thickness = 1.6; st.Transparency = 0.35; st.Parent = t
	end

	--======================================================================
	-- INTERIOR -- a mat, a bowl and a lit counter. Nothing else: the doorway only shows a slice of it.
	--======================================================================
	do
		deco(disc(model, "InnerFloor", HUT_R - 0.5, 0.3, FLOOR_Y + 0.15, WOOD_D))
		deco(part(model, "CounterBase", Vector3.new(3.2, 0.9, 1.5), at(0, FLOOR_Y + 0.6, 2.6), WOOD_D, Enum.Material.SmoothPlastic))
		deco(part(model, "CounterTop", Vector3.new(3.6, 0.3, 1.9), at(0, FLOOR_Y + 1.2, 2.6), WOOD, Enum.Material.SmoothPlastic))
		-- sunk 0.02 into the counter top rather than resting exactly on it: two faces at the same height is
		-- the definition of z-fighting
		local glow = deco(part(model, "CounterGlow", Vector3.new(2.6, 0.14, 1.2), at(0, FLOOR_Y + 1.38, 2.6), ORB, Enum.Material.SmoothPlastic))
		glow.CastShadow = false
		addLight(glow, 2.2, 16)
		-- THE LAMP NEEDS A CORD. A ball floating a stud and a half under the roofline is the single most
		-- obvious "unfinished" tell in an interior, and this one had nothing above it at all.
		local lampY = wallTop - 1.2
		deco(part(model, "LampCord", Vector3.new(0.12, wallTop - lampY + 0.3, 0.12), at(0, (lampY + wallTop) / 2 + 0.15, 0.5), IRON, Enum.Material.SmoothPlastic)).CastShadow = false
		local lamp = deco(part(model, "InnerLamp", Vector3.new(0.7, 0.7, 0.7), at(0, lampY, 0.5), LAMP_FILL, Enum.Material.SmoothPlastic))
		lamp.Shape = Enum.PartType.Ball; lamp.CastShadow = false
		addLight(lamp, 3.0, 26)
		-- both of these met the inner floor exactly at its top face; dropped so they bite into it instead
		deco(part(model, "BedMat", Vector3.new(3.2, 0.26, 2.2), at(-2.0, FLOOR_Y + 0.36, 1.0, 0, math.rad(14), 0), MAT, Enum.Material.SmoothPlastic)).CastShadow = false
		local fb = deco(post(model, "InnerBowl", 0.65, 0.5, at(2.3, FLOOR_Y + 0.48, 1.0), WOOD))
	end

	-- The doorway is what players walk at, so the model's PrimaryPart lives there. NAME AND PLACEMENT ARE
	-- LOAD BEARING: the client hangs its ProximityPrompt and its "N pets asleep" sign on this exact part.
	local anchor = part(model, "HouseAnchor", Vector3.new(1.6, 1.6, 1.6), at(0, FLOOR_Y + DOOR_STRAIGHT * 0.5, doorZ - 0.6), CREAM)
	anchor.Transparency = 1; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CastShadow = false
	model.PrimaryPart = anchor

	--======================================================================
	-- GROUND -- a stone path to the door, then the bed arc, then a few accents
	--======================================================================
	do
		-- PATH: slabs stepping out from the foundation down the approach, alternating tone, each one turned a
		-- couple of degrees so the run reads as laid rather than extruded.
		-- The run STOPS short of the arc. It cannot pass through it: eight beds on a 150-degree sweep leave
		-- only ~1.9 studs between the two centre rims, and no path worth laying fits down that. So it reads as
		-- a path leading away from the door into the yard, and the arc sits beyond its end.
		for i = 0, PATH_SLABS - 1 do
			local z = -(FOUND_R + 0.5 + i * PATH_STEP)
			local even = (i % 2 == 0)
			deco(part(model, "PathSlab", Vector3.new(even and 3.3 or 2.9, 0.24, 1.2),
				at(even and 0.12 or -0.12, 0.12, z, 0, math.rad(even and 3 or -3), 0),
				even and STONE or STONE_D, Enum.Material.SmoothPlastic)).CastShadow = false
		end

		-- BEDS. One clean arc, evenly spaced, in two muted tones rather than four bright ones -- the old
		-- rainbow of pads was the loudest thing in the yard and it was competing with the building.
		local beds = Instance.new("Folder"); beds.Name = "Beds"; beds.Parent = model
		local half = BED_ARC_SPREAD / 2
		local gap  = (MAX_SLOTS > 1) and (BED_ARC_SPREAD / (MAX_SLOTS - 1)) or 0
		for i = 0, MAX_SLOTS - 1 do
			local a = -half + gap * i
			local x, z = math.sin(a) * BED_ARC_R, -math.cos(a) * BED_ARC_R
			local rim = part(beds, "BedRim", Vector3.new(0.36, 3.5, 3.5), at(x, 0.18, z, 0, 0, math.rad(90)), WOOD, Enum.Material.SmoothPlastic)
			rim.Shape = Enum.PartType.Cylinder; deco(rim)
			local bed = part(beds, "NapBed_" .. i, Vector3.new(0.46, 2.9, 2.9), at(x, 0.42, z, 0, 0, math.rad(90)),
				(i % 2 == 0) and CUSHION_A or CUSHION_B, Enum.Material.SmoothPlastic)
			bed.Shape = Enum.PartType.Cylinder
			bed.CanCollide = false; bed.CanQuery = false; bed.CanTouch = false
		end

		-- ACCENTS: a handful of rocks and flower clumps, placed BEHIND and BESIDE the arc so they never sit
		-- where a pet or a player stands.
		for _, spec in ipairs({ { -122, 17.0 }, { 122, 17.0 }, { 180, 13.5 } }) do
			local a, r = math.rad(spec[1]), spec[2]
			local rk = deco(part(model, "Rock", Vector3.new(1.5, 1.1, 1.3),
				at(math.sin(a) * r, 0.35, -math.cos(a) * r, 0, math.rad(spec[1]), 0), STONE_D, Enum.Material.SmoothPlastic))
			rk.Shape = Enum.PartType.Ball
		end
		-- Two clumps of two, not three of three. Eighteen thumbnail-sized parts scattered over the grass is
		-- clutter by definition at this scale: you cannot pick any of them out individually, and together
		-- they just make the ground noisy.
		for _, spec in ipairs({ { -96, 17.6 }, { 96, 17.6 } }) do
			local a, r = math.rad(spec[1]), spec[2]
			local cx, cz = math.sin(a) * r, -math.cos(a) * r
			for k = 0, 1 do
				local f = deco(part(model, "Flower", Vector3.new(0.45, 0.45, 0.45),
					at(cx + k * 0.62, 0.55, cz + (k == 0 and 0.4 or 0)), (k == 0) and FLOWER2 or FLOWER, Enum.Material.SmoothPlastic))
				f.Shape = Enum.PartType.Ball; f.CastShadow = false
				-- 0.24, not 0.28: a 0.5-tall stem centred at 0.28 starts 0.03 above the grass, and three flowers
				-- hovering by a hair is exactly the kind of thing that reads as "unfinished" without being
				-- nameable. Below half its height it plants instead.
				deco(part(model, "Stem", Vector3.new(0.14, 0.5, 0.14), at(cx + k * 0.62, 0.24, cz + (k == 0 and 0.4 or 0)), GREEN, Enum.Material.SmoothPlastic)).CastShadow = false
			end
		end
	end

	-- FINAL SWEEP.
	-- ANCHORED: part() sets it, but assert it -- one unanchored part in a build this size falls through the
	-- island and takes a chunk of the hut with it.
	-- FLAT: matte SmoothPlastic, zero reflectance. Roblox's Wood / Slate / Grass materials carry their own
	-- surface textures, which is the one thing that would stop this reading as low-poly. Neon is skipped so
	-- the LIT switch keeps working.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Reflectance = 0
			if d.Material ~= Enum.Material.Neon then d.Material = Enum.Material.SmoothPlastic end
		end
	end

	-- StreamingEnabled is ON. Without this the hut unloads for anyone more than a chunk away -- wrong for a
	-- landmark players are meant to spot on the way down.
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = Workspace

	houseCF = base
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
	print(string.format("[PetBarn] hut built at %s facing %.0f deg -- %d beds, %d parts, lights %s",
		tostring(base.Position), math.deg(yaw), MAX_SLOTS, n, LIT and "ON" or "OFF"))
	return model
end

-- Tear down anything a previous run (or a stale duplicate that got in first) left behind, so a rebuild never
-- stacks two houses on the same spot.
local function clearOldHouses()
	-- "PetHouse" is the name the PREVIOUS version of this build used. It stays on this list so the first run
	-- after the rebuild clears the old hut out instead of standing the new one up inside it -- which is
	-- exactly the z-fighting, half-buried mess the rebuild is supposed to remove.
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and (m.Name == MODEL_NAME or m.Name == "PetHouse") then m:Destroy() end
	end
end

--======================================================================
-- NAP ROSTER
--======================================================================
-- [userId] = { userId, name, skey, petId, level, isRare, skin, trait, slot, since, earned, away, awayAt }
--   skey  = the STORAGE KEY ("BeanBuddy" or "BeanBuddy#R") -- what _G.playerOwnedPets is keyed by
--   petId = the SPECIES -- what the client renders (templates + display names are per species)
local napping = {}
local slotTaken = {} -- [slotIndex] = userId

local RARE_SUFFIX = "#R" -- MUST match PetSystem's
local function speciesOf(key)
	if type(key) ~= "string" then return key end
	return (key:gsub(RARE_SUFFIX .. "$", ""))
end

-- Read ownership straight off PetSystem's global rather than trusting the client's word for it. The value is
-- either `true` (legacy saves) or a {level,height,time,count,rare} table -- both mean "owned".
local function ownedData(player, skey)
	local op = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if not op then return nil end
	local d = op[skey]
	if d == nil then return nil end
	if type(d) ~= "table" then return { level = 1 } end
	return d
end

-- Published for PetSystem: the STORAGE KEY this player currently has asleep, or nil. PetSystem's equip
-- handler refuses to equip it -- a pet cannot be following you and asleep in the hut at the same time.
_G.petBarnNapKeyOf = function(player)
	local e = player and napping[player.UserId]
	return e and e.skey or nil
end

local function freeSlot()
	for i = 0, MAX_SLOTS - 1 do
		if not slotTaken[i] then return i end
	end
	return nil
end

local function buildPayload()
	local out = {}
	for _, e in pairs(napping) do
		out[#out + 1] = {
			userId = e.userId, name = e.name, petId = e.petId, level = e.level,
			-- skey (the STORAGE KEY) rides along because the owner's client hands it back to PetEquipEvent to
			-- re-equip the right VARIANT on wake-up -- petId alone would re-equip the normal one for someone
			-- whose RARE is asleep. It leaks nothing isRare doesn't already say.
			skey = e.skey,
			isRare = e.isRare, skin = e.skin, trait = e.trait,
			slot = e.slot, since = e.since, earned = math.floor(e.earned), away = e.away and true or false,
		}
	end
	return out
end

local function broadcast(reason)
	local payload = buildPayload()
	pcall(function() PetBarnState:FireAllClients(payload) end)
	print(string.format("[PetBarn] state broadcast -- %d napping (reason=%s)", #payload, tostring(reason)))
end

--======================================================================
-- COINS
--======================================================================
-- Credited HERE, on the server, from server-owned state. The client is never asked how long its pet slept and
-- never sends an amount. Same rule the campfire follows.
local function creditCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + amount end
	if tce   then tce.Value   = tce.Value   + amount end
end

--======================================================================
-- DROP OFF / TAKE BACK
--======================================================================
local function nearHouse(player)
	if not houseCF then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	return (hrp.Position - houseCF.Position).Magnitude <= DROP_RADIUS
end

local function dropOff(player, skey)
	if type(skey) ~= "string" then return end
	if napping[player.UserId] then return end -- one sleeping pet each: the beds is a crowd, not a kennel
	if not nearHouse(player) then
		print("[PetBarn] " .. player.Name .. " tried to drop off from out of range -- ignored")
		return
	end
	local d = ownedData(player, skey)
	if not d then
		print("[PetBarn] " .. player.Name .. " tried to drop off a pet they don't own (" .. skey .. ") -- ignored")
		return
	end
	local slot = freeSlot()
	if not slot then
		print("[PetBarn] every bed is taken -- " .. player.Name .. " turned away")
		return
	end

	local petId = speciesOf(skey)
	local skin, trait = nil, nil
	if _G.skinEquippedFor then
		local ok, s, t = pcall(_G.skinEquippedFor, player, petId)
		if ok then skin, trait = s, t end
	end

	slotTaken[slot] = player.UserId
	napping[player.UserId] = {
		userId = player.UserId, name = player.DisplayName or player.Name,
		skey = skey, petId = petId, level = d.level or 1, isRare = d.rare and true or false,
		skin = skin, trait = trait, slot = slot, since = os.time(), earned = 0, away = false,
	}

	-- Clear the equip flag ourselves so the authoritative state is right immediately. The client ALSO fires
	-- PetEquipEvent(false), which is what actually makes PetFollow despawn the follower (sendState is local to
	-- PetSystem). Doing both means a client that skips its call still cannot end up with a pet that is
	-- simultaneously asleep in a bed and walking around behind them.
	if _G.playerEquippedPet and _G.playerEquippedPet[player] == skey then
		_G.playerEquippedPet[player] = nil
		if _G.petRebroadcastEquip then pcall(_G.petRebroadcastEquip, player, "petbarn-drop") end
	end

	print(string.format("[PetBarn] %s dropped off %s (age %d) in bed %d", player.Name, skey, d.level or 1, slot))
	broadcast("drop")
end

local function takeBack(player)
	local e = napping[player.UserId]
	if not e then return end
	if not nearHouse(player) then
		print("[PetBarn] " .. player.Name .. " tried to collect from out of range -- ignored")
		return
	end
	slotTaken[e.slot] = nil
	napping[player.UserId] = nil
	print(string.format("[PetBarn] %s collected %s after %ds asleep (+%d coins)",
		player.Name, e.skey, os.time() - e.since, math.floor(e.earned)))
	-- Re-equipping is the client's PetEquipEvent call, same as the drop. We only free the bed.
	broadcast("take")
end

PetBarnEvent.OnServerEvent:Connect(function(player, action, skey)
	if action == "drop" then dropOff(player, skey)
	elseif action == "take" then takeBack(player)
	elseif action == "sync" then
		pcall(function() PetBarnState:FireClient(player, buildPayload()) end)
	end
end)

--======================================================================
-- LEAVING AND COMING BACK
--======================================================================
-- Leaving does NOT bank coins and does NOT collect your pet. The pet stays asleep in its bed, marked away
-- (the client greys its name tag), so the beds keeps looking lived-in and your pet is still there if you come
-- back soon. After AWAY_KEEP it is evicted so the beds cannot fill with ghosts.
Players.PlayerRemoving:Connect(function(player)
	local e = napping[player.UserId]
	if not e then return end
	e.away = true
	e.awayAt = os.clock()
	print(string.format("[PetBarn] %s left -- their %s stays asleep for %d more minutes",
		player.Name, e.skey, math.floor(AWAY_KEEP / 60)))
	broadcast("owner-left")
end)

Players.PlayerAdded:Connect(function(player)
	local e = napping[player.UserId]
	if not e then return end
	e.away = false
	e.awayAt = nil
	e.name = player.DisplayName or player.Name
	print("[PetBarn] " .. player.Name .. " rejoined -- their " .. e.skey .. " is still asleep")
	broadcast("owner-back")
	-- Tell THIS client its pet is waiting. Delayed because a client that just joined has not connected its
	-- handlers yet -- a fire that lands before the listener exists is simply lost, the same join-order trap
	-- PetSystem's own catch-up burst documents.
	task.delay(8, function()
		if player.Parent and napping[player.UserId] then
			pcall(function() PetBarnState:FireClient(player, buildPayload()) end)
		end
	end)
end)

--======================================================================
-- BOOT: build, then run the trickle + eviction loop
--======================================================================
task.spawn(function()
	-- WAIT FOR THE ISLANDS TO BE POSITIONED. This is not optional and it is not a race we can skip.
	-- PlayerStats REPOSITIONS every island at runtime, seconds after the server starts -- island 1 alone
	-- travels from its authored Y to about Y=240. The "pethouse" marker travels with it, because it is a
	-- child of the island; the house we build does not, because it is parented to Workspace.
	--
	-- Building before that move is exactly the bug it looks like: the log says "house built at ... -21" and
	-- then, two seconds later, "Positioned Island_1_BeanFarm at Y=150" -- and the whole building, its beds,
	-- its prompt and its sign are left sitting 260 studs under the farm where nobody will ever walk into them.
	--
	-- Workspace's "StandsReady" attribute is the signal PlayerStats sets when it has finished. Campfire,
	-- CommunityGarden, IslandNPCs, FarmerNPC and PetSystem all wait on it before reading a marker position.
	-- Same 90-second budget Campfire uses.
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
	if Workspace:GetAttribute("StandsReady") then
		print(string.format("[PetBarn] StandsReady after %.1fs -- islands are positioned, safe to read the marker", waited))
	else
		warn("[PetBarn] StandsReady never set after 90s -- building anyway, but if the house ends up buried " ..
			"under the island that is why")
	end

	local marker, markerCF, markerSize
	for _ = 1, 60 do
		marker, markerCF, markerSize = findMarker()
		if marker then break end
		task.wait(1)
	end
	if not marker then
		warn("[PetBarn] no Part named '" .. HOUSE_PART_NAME .. "' found in Workspace after 60s -- " ..
			"the pet house is inactive. Add the part (any size, anywhere on the ground) and rejoin.")
		return
	end

	clearOldHouses()
	buildHouse(markerCF, markerSize)

	-- WHERE-AM-I CHECK. "I built the house" and "the player can find the house" are different claims, and the
	-- only thing standing between them is where the marker Part happens to be sitting in Studio. Print the
	-- distance to island 1's spawn so the log answers that question outright instead of leaving someone to
	-- fly around looking for a building that is technically fine and 800 studs away.
	do
		local island = Workspace:FindFirstChild("Island_1_BeanFarm")
		local spawn = island and island:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawn then
			local d = (spawn.Position - markerCF.Position).Magnitude
			local dy = markerCF.Position.Y - spawn.Position.Y
			print(string.format("[PetBarn] marker is %.0f studs from the island 1 spawn (%.0f of that is height)", d, dy))
			if d > 400 then
				warn(string.format(
					"[PetBarn] the '%s' Part is %.0f studs from Bean Farm's spawn -- the house IS built, at %s, " ..
					"but that is nowhere a player walks. Move the Part onto Bean Farm in Studio and rejoin.",
					HOUSE_PART_NAME, d, tostring(markerCF.Position)))
			end
		end
	end
	-- The marker did its job: it said WHERE and WHICH WAY. Hide it rather than delete it, so it is still
	-- there in Studio to drag around and a rebuild can find it again.
	for _, p in ipairs(marker:IsA("BasePart") and { marker } or marker:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
		end
	end

	broadcast("boot")

	while true do
		task.wait(TICK)
		local changed = false
		local now = os.clock()
		for userId, e in pairs(napping) do
			if e.away then
				if e.awayAt and (now - e.awayAt) >= AWAY_KEEP then
					slotTaken[e.slot] = nil
					napping[userId] = nil
					changed = true
					print("[PetBarn] evicted " .. tostring(e.name) .. "'s " .. tostring(e.skey) .. " (owner away too long)")
				end
			else
				local owner = Players:GetPlayerByUserId(userId)
				if owner then
					local coins = coinsForLevel(e.level)
					creditCoins(owner, coins)
					e.earned = e.earned + coins
				end
			end
		end
		if changed then broadcast("evict") end
	end
end)
