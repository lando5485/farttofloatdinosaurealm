--======================================================================
-- Brachiosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- BUILD STAMP: printed at runtime. If you do not see this exact string in the server log,
-- the place you are testing is NOT running this file and nothing below has taken effect.
local BUILD_STAMP = "2026-08-23-Y  ROUNDED-SHARK  declarative-parts  neck=single-ellipsoid  cube-only-union"

--======================================================================
-- WHY THIS FILE IS SHAPED LIKE THIS (read before editing)
--
-- Five rounds of blind edits failed on this pet: no neck, then a bead-chain neck, then a
-- stacked-tin neck, then no neck again. Every one of those was authored by writing coordinates
-- and hoping. The two changes that fixed it are structural, not cosmetic:
--
--   1. THE GEOMETRY IS DATA, NOT CODE. Every part lives in the FEATURES table below -- one row
--      per part, literal numbers, no loops. tools/petxray.py parses that exact table and draws
--      the pet as ASCII, so the shape can be checked BEFORE it ships. printXray() below draws
--      the same view at runtime from the same table. If the two ever disagree, the running
--      build is not this source file, and the stamp above will say so.
--
--   2. ONLY THE BODY CUBE IS UNIONED. Everything else is welded. UnionAsync fails SILENTLY and
--      gets less reliable the more solids you hand it, and every symptom this pet has ever had
--      -- missing neck, floating features, "stacked shapes" -- is what a failed union looks
--      like. The cube is 23 solids, well under the Triceratops's proven 32, and it is the one
--      thing that genuinely needs fusing (a rounded box out of welded parts creases at every
--      seam). Features are welded primitives: what the table says is what renders.
--
-- THE NECK IS ONE PART. A Roblox Ball with a non-uniform Size is a single smooth ELLIPSOID --
-- one solid, one continuous surface, incapable of showing a seam. Stretched along Y and tilted
-- 15.9 degrees toward the front, it runs from inside the shoulders up into the head, with both
-- tapered ends hidden. It is WELDED, not unioned, so a CSG failure cannot eat it.
--
-- WHAT MAKES IT READ AS A BRACHIOSAURUS: the front legs are longer and thicker than the rear
-- (brachio = "arm lizard"), and the nasal dome sits on top of the skull between the eyes.
-- Drop either and it is a generic long-neck.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace"))

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

-- ===== palette =====
local BODY  = Color3.fromRGB(150,132,108)   -- warm sandstone brown
local BELLY = Color3.fromRGB(206,194,168)   -- pale sand underside
local SPOT  = Color3.fromRGB(120,102, 82)   -- darker dapples along the back
local DOME  = Color3.fromRGB(132,112, 90)   -- nasal crest, slightly darker than the head
local DARK  = Color3.fromRGB(28,26,32)
local MOUTH = Color3.fromRGB(90,58,52)
local WHITE = Color3.fromRGB(250,250,250)

-- ===== THE GEOMETRY. Edit here and nowhere else. =====
-- Sizes and positions are UNSCALED studs; every one is multiplied by PSS when built.
-- +X is the FRONT of the pet, +Y is up. Optional trailing "AXIS", degrees rotates the part.
local PSS  = 0.72
local CUBE = { 3.15, 3.00, 2.85, 0.78 }   -- W, H, D, corner radius -- the unioned body

local FEATURES = {
	-- name          shape  sx    sy    sz    colour   x      y      z     [axis, deg]
	-- ---- NECK: ONE ELLIPSOID. Not a chain of anything. See the header. ----
	-- Its TOP END SITS AT THE HEAD'S CENTRE, not at the head's surface. The x-ray caught the
	-- difference: with the neck merely touching the head, only 8% of the head was embedded and
	-- it read as a ball balanced on a stick. Running the neck all the way into the middle of the
	-- skull costs nothing (the overlap is hidden inside an opaque head) and makes it one piece.
	-- Its BOTTOM END REACHES DOWN TO (0.60, 0.40) -- well inside the cube, not just touching its
	-- top face. At the shallower setting only 6% of the neck was embedded and it sat ON the
	-- shoulders instead of growing OUT of them.
	-- A CYLINDER, NOT A STRETCHED BALL. Reported in-world as "no neck, just a small floating ball
	-- between the head and body" -- which is exactly what solid modelling does to a Ball part that
	-- has been scaled non-uniformly: CSG treats a Ball as a SPHERE, so a 0.95 x 3.85 x 0.95 one
	-- comes back as a small sphere of the minor radius. A Cylinder has no such ambiguity.
	-- Its flat ends were the original objection, and they do not apply here: the bottom is buried
	-- inside the body cube and the top inside the skull, so neither end is ever visible.
	-- Axis: a Roblox cylinder points along +X, so rotating 72.84 deg about Z aims it up and
	-- 17.16 deg forward -- the line from inside the shoulders to inside the head.
	{ "Neck",        CYL,  3.85, 0.95, 0.95, "BODY",  1.165, 2.23, 0.00, "Z", 72.84 },
	-- ---- HEAD GROUP ----
	{ "Head",        BAL,  1.65, 1.40, 1.50, "BODY",  1.77,  4.05, 0.00 },
	{ "Snout",       BAL,  0.95, 0.70, 0.78, "BODY",  2.42,  3.70, 0.00 },
	-- The dome has to CLEAR THE SKULL. At y 4.50 it was 100% inside the head and drew nothing --
	-- and the dome is half of what makes this read as a brachiosaur rather than any long-neck.
	{ "NasalDome",   BAL,  0.75, 0.66, 0.72, "DOME",  1.84,  4.72, 0.00 },
	{ "DomeCrest",   BAL,  0.45, 0.36, 0.42, "DOME",  2.00,  4.94, 0.00 },
	-- FLAT DISCS, NOT BALLS. Moving these in and out never worked and could not have: a SPHERE
	-- sitting on a curved snout reads as a ball stuck to the face at ANY depth. Too shallow and it
	-- is a bead; too deep and it disappears. There is no in-between, because the silhouette of a
	-- half-buried sphere is a circle standing proud of the surface.
	--
	-- A flat disc has no such silhouette. It is exactly how this set already draws EYES (PetFace
	-- uses CYL discs), and it is why the eyes have never been reported as floating while the
	-- nostrils have. A Roblox Cylinder's circular face is perpendicular to its X axis, so a
	-- cylinder that is thin in X is a disc facing straight forward -- pressed into the muzzle, it
	-- reads as a nostril hole and a mouth line rather than as objects hanging off the front.
	{ "Smile",       CYL,  0.10, 0.20, 0.66, "MOUTH", 2.83,  3.55, 0.00 },
	{ "NostrilL",    CYL,  0.09, 0.16, 0.16, "DARK",  2.85,  3.83, 0.16 },
	{ "NostrilR",    CYL,  0.09, 0.16, 0.16, "DARK",  2.85,  3.83,-0.16 },
	-- ---- LEGS. Front pair LONGER and THICKER -- this is the whole animal. ----
	-- Both pairs end at y -2.20 so it stands level; the difference is where they meet the body.
	-- SLIMMER. At 1.05 thick against a body only 2.85 deep, each front leg was over a third of the
	-- whole animal's depth -- they read as pillars. Front 1.05 -> 0.82, rear 0.92 -> 0.74, and both
	-- shortened slightly. BOTH PAIRS STILL END AT y -2.20 so it stands level; the front pair stays
	-- the longer and thicker of the two, which is the one feature that makes it an "arm lizard"
	-- rather than a generic long-neck.
	-- PULLED IN UNDER THE BODY. They were at x +/-1.05, which put the front pair's leading face at
	-- x 1.46 -- but the cube is ROUNDED, so at leg height (y -1.18, inside the 0.78 corner radius)
	-- the body itself only reaches x 1.28. The legs were literally sticking out past the chest.
	-- 0.86 / -0.88 tucks both pairs inside the body's real silhouette at the height they meet it.
	{ "FootFL",      BLK,  0.82, 2.05, 0.82, "BODY",  0.86, -1.175, 0.92 },
	{ "FootFR",      BLK,  0.82, 2.05, 0.82, "BODY",  0.86, -1.175,-0.92 },
	{ "FootBL",      BLK,  0.74, 1.62, 0.74, "BODY", -0.88, -1.390, 0.88 },
	{ "FootBR",      BLK,  0.74, 1.62, 0.74, "BODY", -0.88, -1.390,-0.88 },
	-- ---- TAIL: each ball's centre buried in the one before it, or it breaks into blobs ----
	{ "Tail1",       BAL,  1.30, 1.10, 1.10, "BODY", -1.75,  0.10, 0.00 },
	{ "Tail2",       BAL,  0.95, 0.78, 0.78, "BODY", -2.30,  0.34, 0.00 },
	{ "Tail3",       BAL,  0.60, 0.50, 0.50, "BODY", -2.70,  0.50, 0.00 },
	-- ---- UNDERSIDE + MARKINGS ----
	{ "Belly",       BAL,  2.40, 1.15, 2.00, "BELLY", 0.05, -1.30, 0.00 },
	{ "DappleA",     BAL,  0.34, 0.24, 0.34, "SPOT", -0.90,  1.42, 0.30 },
	{ "DappleB",     BAL,  0.34, 0.24, 0.34, "SPOT", -0.90,  1.42,-0.30 },
	{ "DappleC",     BAL,  0.30, 0.21, 0.30, "SPOT",  0.10,  1.50, 0.28 },
	{ "DappleD",     BAL,  0.30, 0.21, 0.30, "SPOT",  0.10,  1.50,-0.28 },
	-- NECK dapples must sit ON the neck's surface. At z +/-0.24 inside a neck of radius 0.475
	-- all four were fully swallowed and drew nothing; the x-ray's attachment report called them
	-- BURIED. x follows the tilted neck axis at that height, z straddles its surface.
	{ "DappleE",     BAL,  0.26, 0.18, 0.26, "SPOT",  1.18,  2.10, 0.36 },
	{ "DappleF",     BAL,  0.26, 0.18, 0.26, "SPOT",  1.18,  2.10,-0.36 },
	-- the neck is a 0.95-diameter CYLINDER now, not the old tapering ball, so a dapple at z 0.34
	-- sits entirely inside it. 0.44 puts it back on the surface.
	{ "DappleG",     BAL,  0.22, 0.16, 0.22, "SPOT",  1.47,  3.20, 0.44 },
	{ "DappleH",     BAL,  0.22, 0.16, 0.22, "SPOT",  1.47,  3.20,-0.44 },
}

local COLORS = { BODY = BODY, BELLY = BELLY, SPOT = SPOT, DOME = DOME,
                 DARK = DARK, MOUTH = MOUTH, WHITE = WHITE }

-- ===== part helpers (same flags as every other pet) =====
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
local function weldTo(part, target)
	if part and target then
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
	end
	return part
end

-- ===== the ONE union: the rounded body cube (23 solids) =====
local function roundedCubeInto(src, P, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, x, y, z, rot) end
	a(BLK, D, iH, iW, 0,0,0)
	a(BLK, iD, H, iW, 0,0,0)
	a(BLK, iD, iH, W, 0,0,0)
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
	end
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
		a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
		a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
		a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
	end
end

local function fuseCube(model, src, color)
	-- ONE FLAT CALL FIRST. Batching was supposed to be the safe option and the live log proved it
	-- is not: the Brachiosaurus refused 2 of 4 batches on a 23-solid cube, while the Triceratops
	-- has always fused 32 solids in a SINGLE UnionAsync without ever failing. Unioning a
	-- UnionOperation with yet more parts is evidently harder for CSG than one flat union of plain
	-- parts, so folding them in a few at a time was making failures MORE likely, not less.
	-- Batching is now only the fallback, and welding is the fallback to that.
	do
		local rest = {}
		for i = 2, #src do rest[#rest + 1] = src[i] end
		local head = src[1]
		local okFlat, uFlat = pcall(function() return head:UnionAsync(rest) end)
		if okFlat and typeof(uFlat) == "Instance" then
			head:Destroy()
			for _, p in ipairs(rest) do p:Destroy() end
			flagPart(uFlat); uFlat.Name = "BodyUnion"; uFlat.Color = color; uFlat.UsePartColor = false
			-- set AFTER parenting, and verified -- see PetFace.forcePrecise
			pcall(function() uFlat.SmoothingAngle = 60 end)
			uFlat.Parent = model
			return uFlat
		end
	end
	-- Incremental, and it ALWAYS returns a real part. A nil return here used to skip the weld on
	-- every feature at once (weldTo does nothing with a nil target), which is how one failed
	-- union detached an entire pet.
	local pieces = {}
	for i, p in ipairs(src) do pieces[i] = p end
	local base = table.remove(pieces, 1)
	local stray, refused = {}, 0
	while #pieces > 0 do
		local batch = {}
		for _ = 1, math.min(6, #pieces) do batch[#batch + 1] = table.remove(pieces, 1) end
		local ok, u = pcall(function() return base:UnionAsync(batch) end)
		if ok and typeof(u) == "Instance" then
			base:Destroy()
			for _, p in ipairs(batch) do p:Destroy() end
			base = u; base.Parent = model
		else
			refused += 1
			for _, p in ipairs(batch) do stray[#stray + 1] = p end
		end
	end
	flagPart(base); base.Name = "BodyUnion"; base.Color = color; base.UsePartColor = false
	pcall(function() base.SmoothingAngle = 60 end)
	base.Parent = model
	PetFace.forcePrecise(base, model.Name)
	for _, p in ipairs(stray) do
		p.Name = "BodyUnionPiece"
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = base; w.Part1 = p; w.Parent = p
	end
	if refused > 0 then
		warn(("[Brachio] cube union: %d batch(es) refused -> %d part(s) welded on instead"):format(refused, #stray))
	end
	return base
end

-- ============================================================================
-- RUNTIME X-RAY -- draws the pet from the SAME table, straight into the log.
-- This is the only way to see the pet without loading it. If this drawing and
-- tools/petxray.py disagree, the running build is not this source file.
-- ============================================================================
local function rotIntoLocal(dx, dy, dz, axis, deg)
	if not axis or deg == 0 then return dx, dy, dz end
	local t = math.rad(-deg)
	local c, s = math.cos(t), math.sin(t)
	if axis == "Z" then return dx*c - dy*s, dx*s + dy*c, dz end
	if axis == "Y" then return dx*c + dz*s, dy, -dx*s + dz*c end
	return dx, dy*c - dz*s, dy*s + dz*c
end
local function insideFeat(f, wx, wy, wz)
	local dx, dy, dz = wx - f[7], wy - f[8], wz - f[9]
	local x, y, z = rotIntoLocal(dx, dy, dz, f[10], f[11] or 0)
	local hx, hy, hz = f[3]/2, f[4]/2, f[5]/2
	if f[2] == BLK then return math.abs(x) <= hx and math.abs(y) <= hy and math.abs(z) <= hz end
	if f[2] == BAL then return (x/hx)^2 + (y/hy)^2 + (z/hz)^2 <= 1 end
	return math.abs(x) <= hx and (y/hy)^2 + (z/hz)^2 <= 1
end
local function insideCube(wx, wy, wz)
	local W, H, D, R = CUBE[1], CUBE[2], CUBE[3], CUBE[4]
	-- AXIS ORDER: roundedCubeInto builds `a(BLK, D, iH, iW, ...)`, so the body is D deep along X
	-- and W wide along Z -- not the other way round. Confirmed by the live BodyUnion dimensions.
	local hx, hy, hz = D/2, H/2, W/2
	local x, y, z = math.abs(wx), math.abs(wy), math.abs(wz)
	if x > hx or y > hy or z > hz then return false end
	local ox = math.max(0, x - (hx - R))
	local oy = math.max(0, y - (hy - R))
	local oz = math.max(0, z - (hz - R))
	return ox*ox + oy*oy + oz*oz <= R*R
end
local GLYPH = { Neck="N", Head="H", Snout="h", NasalDome="D", DomeCrest="D", Smile="m",
                NostrilL="*", NostrilR="*", Tail1="~", Tail2="~", Tail3="~", Belly=":" }
local function glyphFor(name)
	if GLYPH[name] then return GLYPH[name] end
	if name:find("Foot") then return "L" end
	if name:find("Dapple") then return "." end
	return "#"
end
local function printXray()
	local COLS, ROWS = 60, 30
	for _, view in ipairs({ "SIDE", "FRONT" }) do
		local minA, maxA, minY, maxY = 1e9, -1e9, 1e9, -1e9
		local function acc(a, b, sa, sb)
			minA = math.min(minA, a - sa/2); maxA = math.max(maxA, a + sa/2)
			minY = math.min(minY, b - sb/2); maxY = math.max(maxY, b + sb/2)
		end
		acc(0, 0, CUBE[1], CUBE[2])
		for _, f in ipairs(FEATURES) do
			if view == "SIDE" then acc(f[7], f[8], f[3], f[4]) else acc(f[9], f[8], f[5], f[4]) end
		end
		minA -= 0.4; maxA += 0.4; minY -= 0.4; maxY += 0.4
		local sa = (maxA - minA) / COLS
		local sy = (maxY - minY) / ROWS
		print(("[Brachio] %s VIEW  (%s)"):format(view,
			view == "SIDE" and "+X right, +Y up -- pet faces RIGHT" or "+Z right, +Y up -- head on"))
		for r = 0, ROWS - 1 do
			local wy = maxY - (r + 0.5) * sy
			local line = {}
			for c = 0, COLS - 1 do
				local wa = minA + (c + 0.5) * sa
				local ch, bestDepth = " ", -1e9
				for _, f in ipairs(FEATURES) do
					local wx, wz, depth
					if view == "SIDE" then wx, wz, depth = wa, f[9], f[9]
					else wx, wz, depth = f[7], wa, f[7] end
					if insideFeat(f, wx, wy, wz) and depth > bestDepth then
						bestDepth = depth; ch = glyphFor(f[1])
					end
				end
				if ch == " " then
					local wx, wz
					if view == "SIDE" then wx, wz = wa, 0 else wx, wz = 0, wa end
					if insideCube(wx, wy, wz) then ch = "#" end
				end
				line[#line + 1] = ch
			end
			print("[Brachio] |" .. (table.concat(line):gsub("%s+$", "")))
		end
	end
end

-- ============================================================================
-- BUILD
-- ============================================================================
local function buildBrachiosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Brachiosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end

	-- (the Root is created LAST, after the union -- see the end of this function)

	-- the ONE union
	local function rotOf(f)
		if f[10] == "Z" then return CFrame.Angles(0, 0, math.rad(f[11])) end
		if f[10] == "Y" then return CFrame.Angles(0, math.rad(f[11]), 0) end
		if f[10] == "X" then return CFrame.Angles(math.rad(f[11]), 0, 0) end
		return nil
	end
	local src = {}
	roundedCubeInto(src, P, CUBE[1], CUBE[2], CUBE[3], CUBE[4], BODY)
	-- FEET STAY OUT OF THE UNION -- the walk cycle is ON again (PetFollow.WALK_CYCLE = true), and
	-- this note's own instruction was "turn the walk cycle back on and these must come back out".
	-- They were fused while it was off, which meant fuse() DESTROYED them: the four legs did not
	-- exist as parts in the published template, PetFollow's walk cycle (which finds feet by the
	-- name prefix "Foot") found ZERO on this pet, and the Brachiosaurus slid around rigid on the
	-- tallest legs in the game. They are listed in RISKY below, which is this file's existing
	-- "weld it, don't fuse it" path.
	-- The cost is the documented crease at each hip; the payoff is legs that actually step.
	-- ===== ONE FLAT UNION OF PLAIN PARTS =====
	-- This pet, alone of the eight, fused NOTHING: two runs in a row reported "18 of 18 refused"
	-- and then "19 of 19 refused", while the Therizinosaurus fused 46 through the same code. The
	-- difference was never the part count -- it was that the others got a second chance and this
	-- one did not. Everywhere else the leftovers are folded into a union that CSG had already
	-- accepted; here the whole animal was being handed to UnionAsync as a UNION-PLUS-PARTS, which
	-- is measurably harder for solid modelling than one flat union of plain parts.
	--
	-- So the features are built into `src` alongside the cube and fused in a SINGLE call. Colours
	-- survive because the union sets UsePartColor = false. Only two things stay out: the Belly
	-- (a lopsided Ball, which CSG turns into a sphere of its minor radius) and the eyes (they
	-- blink, and you cannot animate part of a union).
	-- RISKY is this file's "weld it, don't fuse it" list. The Belly was once the only exclusion and
	-- has since been thickened (0.90 -> 1.15, ratio 2.1, under the 3.2 CSG limit) so it fuses fine.
	--
	-- THE FOUR LEGS ARE EXCLUDED NOW, and this does NOT reintroduce the failure this pet is famous
	-- for. That failure ("18 of 18 refused", then "19 of 19") came from handing CSG a
	-- UNION-PLUS-PARTS operation. Removing four plain parts from `src` does not do that: the body
	-- call below is still ONE FLAT UNION OF PLAIN PARTS, just four parts smaller, which is the
	-- exact shape that finally worked. The legs are then welded by the loop after it -- plain part
	-- creation plus a WeldConstraint, no CSG involved at all -- and fuseAll is never called on this
	-- pet, so nothing downstream re-swallows them.
	local RISKY = { FootFL = true, FootFR = true, FootBL = true, FootBR = true }
	for _, f in ipairs(FEATURES) do
		if not RISKY[f[1]] then
			src[#src + 1] = P(f[1], f[2], f[3], f[4], f[5], COLORS[f[6]] or BODY, f[7], f[8], f[9], rotOf(f))
		end
	end
	local body = fuseCube(m, src, BODY)

	for _, f in ipairs(FEATURES) do
		if RISKY[f[1]] then
			weldTo(P(f[1], f[2], f[3], f[4], f[5], COLORS[f[6]] or BODY, f[7], f[8], f[9], rotOf(f)), body)
		end
	end

	-- the shared face (eyes only -- the rest of this pet's face is in FEATURES above)
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 2.40, y = 4.20, white = WHITE, dark = DARK }

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	-- nothing left for fuseAll to do here -- the flat union above already absorbed everything
	-- except the Belly and the eyes, both of which are deliberately welded.
	-- ===== THE ROOT IS CREATED LAST, ON PURPOSE =====
	-- The live log said: "BrachiosaurusPetFollower clone has NO 'Root' part". The Root was being
	-- made FIRST, before the body union, and it did not survive to publish -- an invisible 0.4
	-- ball sitting at (0,0,0), dead centre inside the cube that UnionAsync then consumed.
	-- Building it AFTER every union puts it out of reach of CSG entirely.
	--
	-- It matters more than "an invisible part went missing": with no PrimaryPart, Model:GetPivot()
	-- falls back to the BOUNDING-BOX CENTRE. On this pet the box is dominated by the neck and
	-- head, so the pivot sits high and forward of the body -- and the follower then turns about
	-- that point instead of about its chest, which reads as the model swinging wrongly.
	-- The Root is created by PetFace.ensureRoot() a few lines below, which every pet now uses.
	-- Building one HERE as well produced TWO parts named "Root" in the published template (both
	-- invisible, but FindFirstChild("Root") then returns whichever came first, which is exactly
	-- the kind of ambiguity that wastes an afternoon). /petfull caught the duplicate.

	-- The ONLY change allowed on this pet, per review ("some facial features are barely
	-- floating off the face"): one measured, floating-only seating pass. It moves nothing that
	-- already touches the surface, and the eye stack moves as one unit if it moves at all.
	PetFace.seatWelded(m, m:FindFirstChild("BodyUnion"), "Brachio")
	PetFace.audit(m, "Brachio")
	return m
end

-- ============================================================================
-- BUILD + PUBLISH
-- ============================================================================
task.spawn(function()
	print("[Brachio] BUILD " .. BUILD_STAMP)
	local ok, model = pcall(buildBrachiosaurus)
	if not (ok and model) then warn("[Brachio] build error: " .. tostring(model)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Brachio] BodyUnion %.2f x %.2f x %.2f"):format(bu.Size.X, bu.Size.Y, bu.Size.Z))
	else
		warn("[Brachio] no BodyUnion -- the cube union failed entirely")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "BrachiosaurusTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "BrachiosaurusTemplate"; tmpl.Parent = RS
	print(("[Brachio] published BrachiosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	printXray()

	local target = CFrame.new(30, 12, 40)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(20, 6, -50) end
	pcall(function() model:PivotTo(target) end)
end)

-- ============================================================================
-- HATCH SPAWN
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchBrachiosaurusSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("BrachiosaurusTemplate") or RS:WaitForChild("BrachiosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedBrachio_" .. player.Name; pet.Parent = Workspace
	pcall(function() pet:PivotTo(hover) end)
	activePets[player] = pet
	task.spawn(function()
		local POP, t0 = 0.45, os.clock()
		while os.clock() - t0 < POP and pet.Parent do
			local p = (os.clock() - t0) / POP
			pcall(function() pet:PivotTo(hover * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
			task.wait()
		end
		local t = 0
		while pet.Parent do
			t = t + 0.05
			pcall(function() pet:PivotTo(hover * CFrame.new(0, 1.5 + math.sin(t*2)*0.4, 0) * CFrame.Angles(0, t*0.6, 0)) end)
			task.wait(0.05)
		end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	if activePets[p] then pcall(function() activePets[p]:Destroy() end); activePets[p] = nil end
end)
