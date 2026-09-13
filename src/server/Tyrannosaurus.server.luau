--======================================================================
-- Tyrannosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- BUILD STAMP: printed at runtime. If you do not see this exact string in the server log,
-- the place you are testing is NOT running this file and nothing below has taken effect.
local BUILD_STAMP = "2026-08-24-B  ARMS-OUT  declarative-parts  teeth+nostrils-seated  xray"

--======================================================================
-- The T-REX pet -- the reward for Volcanic Vista, the finale quest, so it is the Legendary
-- at the top of the ladder and has to look the part.
--
-- WHY THIS FILE IS SHAPED LIKE THIS (read before editing)
--
-- The teeth and nostrils were reported floating for several rounds. They were authored by
-- writing coordinates and hoping, and the failure could not be found by reading the file --
-- you have to compare a number against a surface it is supposed to sit on. So:
--
--   1. THE GEOMETRY IS DATA. Every part is one row in STRUCT or FEATURES below, literal
--      numbers, no loops. tools/petxray.py parses those tables and draws the pet as ASCII
--      BEFORE it ships, and reports for every part whether it is attached, floating, or
--      buried inside another part. printXray() draws the same view at runtime.
--
--   2. STRUCT joins the ONE union; FEATURES are welded on top. The union is the cube plus
--      the seven body-coloured structural pieces = 30 solids, under the Triceratops's proven
--      32. Everything else is a welded primitive, so a CSG failure cannot detach it.
--
-- THE TEETH AND NOSTRILS MUST STRADDLE A SURFACE. Too far in and they vanish inside an opaque
-- part; too far out and they hang in the air. Their x values below are solved against the
-- ellipsoid they sit on -- see the comments on each row -- and verified by the x-ray.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace"))

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

-- ===== palette =====
local BODY  = Color3.fromRGB(122, 78, 62)   -- earthy red-brown (volcanic)
local BELLY = Color3.fromRGB(202,182,150)   -- tan belly / lower jaw
local TEETH = Color3.fromRGB(248,246,236)
local DARK  = Color3.fromRGB(30, 26, 24)    -- pupils / claws / nostrils / brow
local MOUTH = Color3.fromRGB(58, 30, 28)
local WHITE = Color3.fromRGB(250,250,250)

-- ===== THE GEOMETRY. Edit here and nowhere else. =====
-- UNSCALED studs; multiplied by PSS at build time. +X is the FRONT, +Y is up.
local PSS  = 0.85
local CUBE = { 3.80, 3.60, 3.40, 0.90 }   -- W, H, D, corner radius

-- STRUCT: body-coloured structural pieces that JOIN THE UNION with the cube.
-- These have to fuse: separate overlapping same-coloured parts shade independently and
-- Roblox creases at every join, so a welded head reads as a blob stuck to a box.
local STRUCT = {
	-- name        shape  sx    sy    sz    colour  x      y      z     [axis, deg]
	-- REVAMP: the head is the T-Rex. Enlarged ~20%% so the skull dominates the silhouette the
	-- way it does on every good chibi rex, with the snout deepened to match.
	-- ONE SKULL, per review: the snout is now MOSTLY INSIDE the head dome (tip x 2.70 vs dome
	-- front ~2.37 -- a 0.33 muzzle bump, not a 0.9 floating torpedo).
	{ "HeadBase",  BAL,  1.85, 2.15, 2.30, "BODY",  1.45,  0.55, 0.00 },
	-- MUZZLE: one tilted SLAB (nose-down 18 degrees) whose back half is inside the dome -- the
	-- snout literally grows out of the head as a single form, flat planes instead of a chain of
	-- ellipsoid blobs pinching at every junction.
	{ "Muzzle",    BLK,  1.35, 0.95, 1.30, "BODY",  2.30,  0.20, 0.00, "Z", -18 },
	-- THE TINY ARMS ARE THE SIGNATURE AND THEY WERE INVISIBLE. At x 1.20, z +/-1.30 both arms
	-- sat entirely INSIDE the body cube (which reaches x 1.83 at that height) and drew nothing
	-- at all. Moved out to x 1.95 so each one straddles the flank and actually shows.
	-- NO TILT. The arms used to be rotated +/-14 degrees about Z, which is mirrored, so the two
	-- arm TIPS ended up at different x -- and a single claw position could not sit on both. One
	-- claw attached, the other floated. Vertical arms are symmetric and the claws just work.
	-- ARMS = little HALF-SPHERES, per review: each is a ball centred exactly ON the cube's
	-- front face, so half sits inside and half sticks out -- a nub growing from the chest.
	-- The three tiny wedge claws per nub are added in code after the build (the declarative
	-- table can only express Part shapes, not WedgeParts).
	{ "ArmL",      BAL,  0.75, 0.75, 0.75, "BODY",  1.85, -0.55, 0.95 },
	{ "ArmR",      BAL,  0.75, 0.75, 0.75, "BODY",  1.85, -0.55,-0.95 },
	-- Tail pulled in and thickened: big head + shorter, chunkier tail = better proportions.
	{ "Tail",      BAL,  1.90, 1.20, 1.30, "BODY", -1.55, -0.05, 0.00 },
	{ "TailMid",   BAL,  1.40, 0.90, 0.95, "BODY", -2.15,  0.08, 0.00 },
	{ "TailTip",   BAL,  1.05, 0.60, 0.62, "BODY", -2.60,  0.18, 0.00 },
	-- HIPS: big thigh bulges on the rear flanks (proud 0.2 past the cube side), the other half
	-- of the classic rex silhouette -- huge legs under a huge head.
	{ "ThighL",    BAL,  1.55, 1.70, 1.00, "BODY", -0.70, -0.60, 1.60 },
	{ "ThighR",    BAL,  1.55, 1.70, 1.00, "BODY", -0.70, -0.60,-1.60 },
}

-- FEATURES: welded on top of the union. Different colour, or must move (the feet).
local FEATURES = {
	-- ---- JAW + MOUTH ----
	-- Tan LOWER JAW: a flat chin slab under the muzzle. EXTENDED BACK INTO THE BODY, per
	-- review: at 0.90 deep its rear edge stopped at x 1.99 while the cube front is 1.70 -- a
	-- 0.29 gap, the chin visibly hanging in air. Now spans 1.33..2.97: rear 0.37 inside the
	-- cube, tip unchanged.
	{ "Jaw",       BLK,  1.60, 0.40, 1.20, "BELLY", 2.15, -0.55, 0.00, "Z",  -8 },
	-- MOUTH + TEETH REBUILT, per review ("the teeth are detached from everything else").
	-- Four little cubes straddling a curved mouth BALL could only ever poke out as isolated
	-- white specks. Both are flat plates now: a dark mouth plate straddling the snout/jaw front
	-- (back edge buried in the fused Jaw at every point across its width), and ONE continuous
	-- white tooth band overlapping the mouth plate's bottom edge -- a grin strip that is flanked
	-- by dark above and tan jaw below, so it physically cannot read as detached.
	-- SMALL ROUNDED MOUTH per review ("remove the huge dark rectangular block covering the
	-- mouth"): a modest dark ellipse tucked between the snout and the tan jaw, following the
	-- head's curve, with two TINY soft round teeth straddling its front (solved against the
	-- mouth ellipsoid: surface x = 3.16 at dy -0.10, dz +/-0.28).
	-- MOUTH = the dark SEAM sandwiched between muzzle and jaw (recessed INTO the head form,
	-- per review -- "the mouth should look like part of the head"), with three tiny teeth
	-- sitting in that seam, flanked on every side.
	{ "Mouth",     BLK,  0.75, 0.22, 1.10, "MOUTH", 2.55, -0.36, 0.00, "Z", -12 },
	-- The side teeth sat at x 2.80 -- 0.06 BEHIND the mouth slab's front face (x 2.94 at their
	-- height), so only the centre tooth ever showed. All three now clear the face by ~0.05.
	{ "ToothA",    BLK,  0.15, 0.18, 0.15, "TEETH", 2.90, -0.44, 0.30 },
	{ "ToothB",    BLK,  0.15, 0.18, 0.15, "TEETH", 2.94, -0.42, 0.00 },
	{ "ToothC",    BLK,  0.15, 0.18, 0.15, "TEETH", 2.90, -0.44,-0.30 },
	-- ---- NOSTRILS. Solved against the Snout ellipsoid (half 1.10 x 0.575 x 0.85 at x 2.20). ----
	-- At dy +0.20, dz +/-0.20 the snout's surface is x 3.20. They were at 3.05 -- a full 0.15
	-- INSIDE an opaque snout, drawing nothing at all.
	-- NO nostril dots: every small dark sphere so far has been flagged as "a random black
	-- button". The Triceratops has none and reads perfectly -- clean muzzle wins.
	-- ---- BROWS: a low ridge set BEHIND the eye. As a fat ball further forward it buried the
	-- eye discs entirely and the T-Rex read as eyeless. ----
	-- BROWS REMOVED per review: dark half-buried lumps read as "random black circular bumps /
	-- buttons", not brows. The big PetFace eyes carry the expression alone -- cleaner face.
	-- (arm claws are three tiny wedges per nub, built in code after the union -- see below)
	-- ---- BELLY ----
	-- The pale belly panel has to sit ON the front-lower surface. At x 1.30 it was completely
	-- swallowed by the cube (surface x 1.89 at this height) -- a pale patch nobody could see.
	{ "Belly",     BAL,  0.66, 1.30, 2.10, "BELLY", 1.80, -1.05, 0.00 },
	-- ---- FEET: welded, not fused -- the walk cycle steps them (fuseAll keeps Foot* welded).
	-- Back pair chunkier, sitting under the new thigh bulges. ----
	{ "FootFL",    BLK,  1.00, 1.00, 1.00, "BODY",  0.95, -1.48, 0.78 },
	{ "FootFR",    BLK,  1.00, 1.00, 1.00, "BODY",  0.95, -1.48,-0.78 },
	{ "FootBL",    BLK,  1.15, 1.05, 1.15, "BODY", -0.95, -1.46, 0.82 },
	{ "FootBR",    BLK,  1.15, 1.05, 1.15, "BODY", -0.95, -1.46,-0.82 },
}

local COLORS = { BODY = BODY, BELLY = BELLY, TEETH = TEETH, DARK = DARK,
                 MOUTH = MOUTH, WHITE = WHITE }

-- ===== part helpers =====
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
local function rotOf(axis, deg)
	if axis == "Z" then return CFrame.Angles(0, 0, math.rad(deg)) end
	if axis == "Y" then return CFrame.Angles(0, math.rad(deg), 0) end
	if axis == "X" then return CFrame.Angles(math.rad(deg), 0, 0) end
	return nil
end

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

local function fuse(model, src, color)
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
			flagPart(uFlat); uFlat.Name = "BodyUnion"; uFlat.UsePartColor = true; uFlat.Color = color
			-- set AFTER parenting, and verified -- see PetFace.forcePrecise
			pcall(function() uFlat.SmoothingAngle = 60 end)
			uFlat.Parent = model
			return uFlat
		end
	end
	-- Incremental, and it ALWAYS returns a real part. A nil return here used to skip the weld on
	-- every feature at once (weldTo does nothing with a nil target) -- one failed union detached
	-- every tooth, eye and claw on the pet simultaneously.
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
	flagPart(base); base.Name = "BodyUnion"; base.UsePartColor = true; base.Color = color
	pcall(function() base.SmoothingAngle = 60 end)
	base.Parent = model
	PetFace.forcePrecise(base, model.Name)
	for _, p in ipairs(stray) do
		p.Name = "BodyUnionPiece"
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = base; w.Part1 = p; w.Parent = p
	end
	if refused > 0 then
		warn(("[TRex] union: %d batch(es) refused -> %d part(s) welded on instead"):format(refused, #stray))
	end
	return base
end

-- ============================================================================
-- RUNTIME X-RAY -- draws the pet from the SAME tables, into the log.
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
	local x, y, z = rotIntoLocal(wx - f[7], wy - f[8], wz - f[9], f[10], f[11] or 0)
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
local function glyphFor(name)
	if name:find("Tooth")   then return "T" end
	if name:find("Nostril") then return "*" end
	if name:find("Head")    then return "H" end
	if name:find("Snout")   then return "h" end
	if name:find("Jaw")     then return "J" end
	if name:find("Mouth")   then return "m" end
	if name:find("Brow")    then return "^" end
	if name:find("Claw")    then return "c" end
	if name:find("Arm")     then return "a" end
	if name:find("Tail")    then return "~" end
	if name:find("Belly")   then return ":" end
	if name:find("Foot")    then return "L" end
	return "#"
end
local function printXray()
	local ALL = {}
	for _, f in ipairs(STRUCT)   do ALL[#ALL + 1] = f end
	for _, f in ipairs(FEATURES) do ALL[#ALL + 1] = f end
	local COLS, ROWS = 60, 26
	for _, view in ipairs({ "SIDE", "FRONT" }) do
		local minA, maxA, minY, maxY = 1e9, -1e9, 1e9, -1e9
		local function acc(a, b, sa, sb)
			minA = math.min(minA, a - sa/2); maxA = math.max(maxA, a + sa/2)
			minY = math.min(minY, b - sb/2); maxY = math.max(maxY, b + sb/2)
		end
		acc(0, 0, CUBE[1], CUBE[2])
		for _, f in ipairs(ALL) do
			if view == "SIDE" then acc(f[7], f[8], f[3], f[4]) else acc(f[9], f[8], f[5], f[4]) end
		end
		minA -= 0.4; maxA += 0.4; minY -= 0.4; maxY += 0.4
		local sa, sy = (maxA - minA) / COLS, (maxY - minY) / ROWS
		print(("[TRex] %s VIEW  (%s)"):format(view,
			view == "SIDE" and "+X right, +Y up -- pet faces RIGHT" or "+Z right, +Y up -- head on"))
		for r = 0, ROWS - 1 do
			local wy = maxY - (r + 0.5) * sy
			local line = {}
			for c = 0, COLS - 1 do
				local wa = minA + (c + 0.5) * sa
				local ch, bestDepth = " ", -1e9
				for _, f in ipairs(ALL) do
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
			print("[TRex] |" .. (table.concat(line):gsub("%s+$", "")))
		end
	end
end

-- ============================================================================
-- BUILD
-- ============================================================================
local function buildTyrannosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Tyrannosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end

	local root = mkPart(m, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0)
	root.Transparency = 1; m.PrimaryPart = root

	-- ONE union: the cube + the structural pieces (23 + 7 = 30 solids)
	local src = {}
	roundedCubeInto(src, P, CUBE[1], CUBE[2], CUBE[3], CUBE[4], BODY)
	for _, f in ipairs(STRUCT) do
		src[#src + 1] = P(f[1], f[2], f[3], f[4], f[5], COLORS[f[6]] or BODY, f[7], f[8], f[9], rotOf(f[10], f[11]))
	end
	local body = fuse(m, src, BODY)

	-- welded features, straight from the table
	for _, f in ipairs(FEATURES) do
		weldTo(P(f[1], f[2], f[3], f[4], f[5], COLORS[f[6]] or BODY, f[7], f[8], f[9], rotOf(f[10], f[11])), body)
	end

	-- shared flat-disc eyes. Seated on the head surface at this height -- they used to sit at
	-- x 2.30 / y 0.98, which is BEYOND the head ellipsoid and ABOVE the snout, so both eyes,
	-- both pupils and both glints hovered in empty air in front of the face.
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 2.22, y = 0.78, step = 0.03, white = WHITE, dark = DARK }  -- flat stack: eyes sit ON the head, not in front of it
	-- THREE TINY WEDGE CLAWS per arm nub, per review: dark spikes fanned across the front of
	-- each half-sphere arm, tips pointing forward-down, backs buried in the nub (its surface
	-- is at x ~2.03 at these offsets, so each claw straddles it).
	for _, sgn in ipairs({ 1, -1 }) do
		for _, dz in ipairs({ -0.17, 0, 0.17 }) do
			local cl = Instance.new("WedgePart"); cl.Name = "ArmClaw"
			cl.Size = Vector3.new(0.10, 0.14, 0.26) * PSS
			cl.Color = DARK
			cl.CFrame = CFrame.new(2.17 * PSS, -0.60 * PSS, (0.95 * sgn + dz) * PSS)
				* CFrame.Angles(0, math.rad(-90), 0)
			flagPart(cl); cl.Parent = body.Parent
			weldTo(cl, body)
		end
	end

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	PetFace.audit(m, "TRex")
	return m
end

-- ============================================================================
-- BUILD + PUBLISH
-- ============================================================================
task.spawn(function()
	print("[TRex] BUILD " .. BUILD_STAMP)
	local ok, model = pcall(buildTyrannosaurus)
	if not (ok and model) then warn("[TRex] build error: " .. tostring(model)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[TRex] BodyUnion %.2f x %.2f x %.2f"):format(bu.Size.X, bu.Size.Y, bu.Size.Z))
	else
		warn("[TRex] no BodyUnion -- the union failed entirely")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "TyrannosaurusTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "TyrannosaurusTemplate"; tmpl.Parent = RS
	print(("[TRex] published TyrannosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	printXray()

	local target = CFrame.new(30, 12, 40)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(-20, 6, -50) end
	pcall(function() model:PivotTo(target) end)
end)

-- ============================================================================
-- HATCH SPAWN
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchTyrannosaurusSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("TyrannosaurusTemplate") or RS:WaitForChild("TyrannosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedTRex_" .. player.Name; pet.Parent = Workspace
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
