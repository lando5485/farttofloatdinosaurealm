--======================================================================
-- Shark.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A SHARK / MEGALODON pet on the EXACT same pipeline as the Stegosaurus +
-- Velociraptor pets: same rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), same
-- flat-disc face (whitepartofeye/blackpartofeye/Glint), same 4 stubby feet/fins,
-- same matte/smooth, same publish (destroy old SharkTemplate -> fresh clone).
-- FEATURES: projecting rounded SNOUT dome fused into the front face, one simple
-- oval MOUTH with 5 tiny teeth, triangular DORSAL fin, 2 pectoral fins, a
-- two-lobed CAUDAL tail (taller top lobe), gill lines. Blue-grey body, lighter
-- blue-grey belly (no cream/white pieces -- they kept reading as random balls).
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace")) -- one shared face for all 6 pets

-- ===== helpers (VERBATIM from Velociraptor/Stegosaurus.server.luau) =====
local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
-- ===================== THE ONE THAT BROKE EVERYTHING =====================
-- The old version handed EVERY solid to UnionAsync in a single call and, if that call failed,
-- returned NIL. That nil is the bug behind essentially every "things aren't attached" report:
--
--   local body = fuse(...)          -- nil when the union fails
--   weldTo(P("Tooth", ...), body)   -- weldTo does NOTHING when the target is nil
--
-- So one failed union does not just cost you a smooth body -- it silently skips the weld on
-- EVERY tooth, eye, claw, horn and belly patch on the pet at once. The parts still get built
-- and still get placed, so the pet looks complete when it spawns and then comes apart the
-- moment it moves. That is why the failure always presented as "the teeth and stuff are not
-- attached" and never as "the union failed", and why re-tuning tooth coordinates never helped:
-- the coordinates were mostly fine, the welds were never created.
--
-- And UnionAsync's reliability falls off with the number of input solids, which is exactly why
-- the pets that broke were the busiest ones (~35-50 solids) while the triceratops (32) has
-- always been fine.
--
-- This version fixes both halves:
--   1. It folds the solids in a FEW AT A TIME instead of all at once, which is far more
--      reliable than one big call.
--   2. It ALWAYS returns a real part. A batch that refuses to union is WELDED on instead of
--      being thrown away, so the worst case is a visible seam on one lump -- never a pet whose
--      every decoration is floating loose.
local function fuse(model, src, name, color)
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
			flagPart(uFlat); uFlat.Name = name; uFlat.UsePartColor = true; uFlat.Color = color
			-- set AFTER parenting, and verified -- see PetFace.forcePrecise
			pcall(function() uFlat.SmoothingAngle = 60 end)
			uFlat.Parent = model
			return uFlat, nil
		end
	end
	local pieces = {}
	for i, p in ipairs(src) do pieces[i] = p end
	local base = table.remove(pieces, 1)
	local stray, batches, refused = {}, 0, 0
	while #pieces > 0 do
		local batch = {}
		for _ = 1, math.min(6, #pieces) do batch[#batch + 1] = table.remove(pieces, 1) end
		batches += 1
		local ok, u = pcall(function() return base:UnionAsync(batch) end)
		if ok and typeof(u) == "Instance" then
			base:Destroy()
			for _, p in ipairs(batch) do p:Destroy() end
			base = u
			base.Parent = model
		else
			refused += 1
			for _, p in ipairs(batch) do stray[#stray + 1] = p end
		end
	end
	flagPart(base); base.Name = name; base.UsePartColor = true; base.Color = color
	pcall(function() base.SmoothingAngle = 60 end)
	base.Parent = model
	PetFace.forcePrecise(base, model.Name)
	-- anything that refused to fuse gets welded on, so it travels with the pet regardless
	for _, p in ipairs(stray) do
		p.Name = name .. "Piece"
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = base; w.Part1 = p; w.Parent = p
	end
	if refused > 0 then
		warn(("[%s] union: %d of %d batches refused -> %d part(s) welded on instead of fused")
			:format(name, refused, batches, #stray))
	end
	return base, (refused > 0) and ("%d batch(es) welded"):format(refused) or nil
end
local function newRoot(model)
	local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
end
local function weldTo(part, target)
	if part and target then
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
	end
	return part
end
local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
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
-- shared chunky body dims (IDENTICAL to the stego/raptor) + display scale
local PSW, PSH, PSD, PSR, PSS = 4.4, 3.0, 3.4, 0.9, 0.85   -- SQUASHED + WIDE per style spec: a collectible-toy loaf, not a tall box (front depth unchanged: the face solves stay valid)

-- ============================================================================
-- SHARK -- same rounded-cube body + flat-disc face + 4 feet as the raptor;
-- raptor snout/arms/tail removed; shark dorsal/smile/pectorals/tail/gills added.
-- ============================================================================
local function buildShark()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Shark"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- shark palette
	local BODY  = Color3.fromRGB(110,130,150)  -- classic cartoon-shark blue-grey
	-- BELLY is a slightly lighter blue-grey, per spec -- NOT cream/white (the cream chin/belly
	-- pieces are what kept reading as "a random white ball on the front" in past reviews).
	local BELLY = Color3.fromRGB(196,210,222)
	-- FINS MUST CONTRAST WITH THE BODY. These were 84,100,120 against a body of 110,130,150 --
	-- barely 26 RGB apart, which at pet size on screen is no contrast at all. The dorsal fin was
	-- reported as MISSING when it was actually present and simply invisible against the back.
	-- A shark reads as a shark because of its fin silhouette, so the fins are now clearly darker.
	local FIN   = Color3.fromRGB(52, 66, 86)    -- deep slate: reads against the blue-grey body
	local DARK  = Color3.fromRGB(28,26,32)      -- pupils / gills
	local MOUTH = Color3.fromRGB(70,40,46)       -- dark mouth interior
	local TEETH = Color3.fromRGB(250,250,246)    -- white teeth
	local WHITE = Color3.fromRGB(250,250,250)

	-- ========================================================================================
	-- BODY UNION. Cube unchanged. The body-coloured TAIL BASE now joins the same UnionAsync call so
	-- the tail flows out of the body instead of creasing at the join (separate overlapping parts
	-- shade independently, which is what made every pet read as blobs stuck to a box).
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end   -- structural: joins the body union
	-- HEAD: one broad ellipsoid fused over the whole front face. Half its depth (0.8) is buried
	-- in the cube, so the front of the cube BECOMES a rounded snout projecting ~0.4 with a smooth
	-- transition -- one cohesive head, not a piece stuck on. It is narrower (3.4) and shorter
	-- (2.7) than the body (4.4 x 3.0), which gives the slight shark-nose taper. Aspect ratio 2.1,
	-- unrotated: safe for CSG (the ban is on ROTATED stretched balls; unrotated is proven fine).
	S("Snout", BAL, 1.6,2.7,3.4, BODY, 1.30,0.10,0)
	-- TAIL: chunky body -> thick tapering trunk -> narrow stem -> (caudal lobes added below).
	-- Both balls are buried deep in their neighbour so the rear narrows continuously instead of
	-- reading as a featureless square back.
	S("TailBase", BAL, 2.2,2.4,1.7, BODY, -1.80,0.00,0)   -- thick tail TRUNK the rear narrows into
	S("TailStem", BAL, 1.3,1.4,1.0, BODY, -2.65,0.05,0)   -- narrowing STEM the big fork grows from
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- NO LEGS, per review: sharks do not have them. With nothing named Foot* the walk cycle
	-- finds zero feet and the follower simply glides -- which on a shark reads as swimming,
	-- carried by the sculling pectoral fins.

	-- BELLY: a small lighter blue-grey patch on the underside, per review -- footprint scaled to
	-- 1/3 of the old full-hull plate. Thickness stays 0.35 so it still straddles the hull bottom
	-- (y -1.5, plate spans -1.595..-1.245): shrinking that too would sink it entirely inside the
	-- body and it would vanish. Fuses into the union below like everything else.
	weldTo(P("Belly", BLK, 1.07, 0.35, 1.20, BELLY, 0.20, -1.42, 0), body)

	-- FACE: the shared PetFace (src/shared/PetFace.luau) -- identical eye geometry to every other pet.
	-- LARGE CUTE EYES on the upper/front of the snout dome. Dome surface at (y 0.75, z +/-0.44)
	-- solves to x = 1.97; the 0.20-thick white disc centred at 1.94 straddles it exactly.
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 1.94, y = 0.75, step = 0.05, white = WHITE, dark = DARK }

	-- ONE SIMPLE MOUTH, per spec: a single shallow dark ellipse -- a CYLINDER disc, never a
	-- stretched Ball (the one shape CSG mangles). It faces the viewer as a wide oval 1.5 x 0.55
	-- (~34% of the 4.4 face width), mostly buried in the snout dome with its flat front face at
	-- x 2.05, just 0.05 proud of the dome surface there (x 2.00 at y -0.55). It fuses into the
	-- head below: a dark curved opening IN the face, not an object stuck on it.
	local mouthP = weldTo(P("Mouth", CYL, 0.40, 0.55, 1.50, MOUTH, 1.85, -0.55, 0), body)
	-- FIVE TINY TEETH, per spec (4-6, small, subtle): 3 hanging near the mouth's top edge,
	-- 2 rising from its bottom edge, evenly spaced. Tooth trick: an UNROTATED WedgePart shows
	-- its triangular profile to a viewer looking at the face; flipped 180 about X it points
	-- DOWN; alternating a 180 yaw mirrors the slant. Each tooth is 0.10 deep centred exactly on
	-- the mouth's flat front face (x 2.05): half in the dark, half proud -- attached by
	-- construction. Welded to the MOUTH, not the body, so the seat pass carries them with it.
	local flipDown = CFrame.Angles(math.rad(180), 0, 0)
	local mirror   = CFrame.Angles(0, math.rad(180), 0)
	for i, tz in ipairs({ -0.45, 0, 0.45 }) do          -- upper 3, pointing down
		local tw = Instance.new("WedgePart"); tw.Name = "ToothW"
		tw.Size = Vector3.new(0.10, 0.12, 0.14) * s
		tw.Color = TEETH
		local rot = (i % 2 == 0) and (flipDown * mirror) or flipDown
		tw.CFrame = CFrame.new(2.05 * s, -0.40 * s, tz * s) * rot
		flagPart(tw); tw.Parent = m
		weldTo(tw, mouthP)
	end
	for i, tz in ipairs({ -0.22, 0.22 }) do             -- lower 2, pointing up
		local tw = Instance.new("WedgePart"); tw.Name = "ToothW"
		tw.Size = Vector3.new(0.10, 0.11, 0.13) * s
		tw.Color = TEETH
		local rot = (i % 2 == 0) and mirror or nil
		tw.CFrame = CFrame.new(2.05 * s, -0.72 * s, tz * s) * (rot or CFrame.identity)
		flagPart(tw); tw.Parent = m
		weldTo(tw, mouthP)
	end

	-- ==================== FINS: CYLINDER DISCS, NOT BALLS -- SO THEY FUSE ====================
	-- Every fin used to be a rotated, stretched Ball, which is the ONE shape CSG destroys, so
	-- fuseAll left all five welded. Five separate parts shade separately, crease at every join,
	-- and read as "not connected" in world lighting even though the geometry overlaps -- while the
	-- Hub's flat viewport lighting hides the seams, which is exactly the menu-vs-equipped gap.
	--
	-- A rotated stretched CYLINDER fuses fine (the Brachiosaurus neck is one, fused in a single
	-- flat call). A cylinder seen from the side is a disc; half-bury a disc in the body and the
	-- visible half IS a fin silhouette. So every fin is now a leaning disc, welded here and then
	-- FUSED by PetFace.fuseAll into the one body solid: one surface, no seams, and it cannot
	-- render differently equipped than it does in the menu because it is the same solid.
	-- Cylinder axis = local X = the THIN side; Angles(0,90,0) turns that axis side-to-side.
	-- WEDGES, NOT DISCS, per review: a half-buried round disc reads as a mohawk hump, "not like
	-- a shark". A shark fin is a swept TRIANGLE, and a WedgePart is exactly that -- and wedges
	-- fuse into the union like any block. Orientation notes: a stock wedge has its tall vertical
	-- face at its local +Z and its sharp edge at the front-bottom; yaw +90 turns the tall face
	-- toward the pet's +X (leading edge forward, trailing slope sweeping down-back = dorsal),
	-- yaw -90 turns it backward (tall trailing edge at the rear = tail lobes).
	local function W(n, sx, sy, sz, c, x, y, z, rot)
		local p = Instance.new("WedgePart"); p.Name = n
		p.Size = Vector3.new(sx*s, sy*s, sz*s); p.Color = c
		local cf = CFrame.new(x*s, y*s, z*s); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = m; return p
	end
	local FWD  = CFrame.Angles(0, math.rad(90), 0)
	local BACK = CFrame.Angles(0, math.rad(-90), 0)
	local BACKFLIP = CFrame.Angles(math.rad(180), 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	-- DORSAL: the signature triangle mid-back -- long swept leading slope rising to a peak at
	-- the rear-top, tall trailing edge behind it (that is what BACK gives). Wide base (2.2),
	-- moderate height: bottom at y 1.2 is embedded 0.3 in the body top (1.5), 1.2 stands proud.
	weldTo(W("Dorsal", 0.70, 1.5, 2.2, FIN, -0.35, 1.95, 0, BACK), body)
	-- PECTORALS: chunky swept wedges angled out, down and slightly back from the lower flanks
	-- (half-width 2.2, so z 2.0 buries the base). They stay WELDED (fuseAll keeps Pectoral
	-- parts) so PetFollow's fin flap can actually swim them.
	for _, sgn in ipairs({1,-1}) do
		weldTo(W("Pectoral", 0.60, 1.6, 1.5, FIN, 0.45, -0.60, 2.00*sgn,
			CFrame.Angles(math.rad(115 * sgn), 0, 0) * FWD), body)
	end
	-- CAUDAL FIN: the classic two-lobed shark tail, grown out of the fused TailStem -- upper
	-- lobe larger, sweeping up-back; lower lobe mirrored down-back; tall edges at the very rear.
	-- Sized to be obvious from a 3/4 or side view: the fork reaches y 2.35 up and x -3.9 back.
	weldTo(W("TailTop", 0.55, 2.6, 1.8, FIN, -3.00,  1.05, 0, BACK), body)
	weldTo(W("TailBot", 0.50, 1.9, 1.4, FIN, -2.90, -0.90, 0, BACKFLIP), body)

	-- GILL LINES: 3 thin dark slits on each side, just behind the head, tilted slightly so they
	-- read as curved. z 2.16 straddles the flank at 2.2 -- at +/-1.42 they were ALL invisible,
	-- and gill slits are most of what makes a blob read as a shark.
	for _, sgn in ipairs({1,-1}) do
		for _, gx in ipairs({ 1.1, 0.75, 0.4 }) do
			weldTo(P("Gill", BLK, 0.1,0.95,0.14, DARK, gx,0.0,2.16*sgn, CFrame.Angles(0,0,math.rad(10))), body)
		end
	end

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	-- report any part that is unwelded or floating (see PetFace.audit)
	PetFace.audit(m, "Shark")
	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the raptor): build in Workspace, clear any stale
-- SharkTemplate, publish a fresh clone, print the part count.
-- ============================================================================
-- ============================================================================
-- OVERRIDE HOOK -- the "fix it for good" path.
--
-- Six code-built sharks in a row have been rejected, because the person writing the numbers
-- cannot see the model. This hook removes that bottleneck: put ANY model you like -- a free
-- toolbox shark, or one you assembled/edited in Studio -- anywhere in the place, named exactly
--     SharkOverride
-- (ReplicatedStorage, Workspace or ServerStorage all work). On the next play it is picked up
-- automatically: scripts stripped, every part anchored/non-colliding, scaled to pet height
-- (~3 studs), rotated so its front faces the pet system's +X (build the model facing the
-- normal Roblox -Z front and the hook handles it), given a Root pivot, and published as
-- SharkTemplate. The Pet Hub icon, equipping, hatching and skins all read SharkTemplate, so
-- the whole pipeline just works with YOUR model. Delete SharkOverride to fall back to the
-- code-built shark below.
-- ============================================================================
local function findOverride()
	for _, root in ipairs({ RS, Workspace, game:GetService("ServerStorage") }) do
		local o = root:FindFirstChild("SharkOverride", true)
		if o and (o:IsA("Model") or o:IsA("BasePart")) then return o end
	end
	return nil
end
local function publishOverride(src)
	local m
	if src:IsA("BasePart") then
		m = Instance.new("Model"); m.Name = "Shark"
		local c = src:Clone(); c.Parent = m
	else
		m = src:Clone(); m.Name = "Shark"
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.CastShadow = false; d.Massless = true
		end
	end
	-- face +X: models are normally built facing -Z, the pet system's front is +X
	m:PivotTo(CFrame.Angles(0, math.rad(-90), 0))
	local _, size = m:GetBoundingBox()
	local h = math.max(size.Y, 0.05)
	local sc = 3.1 / h
	if sc > 0.01 and sc < 100 then pcall(function() m:ScaleTo(sc) end) end
	-- centre the bounding box on the origin (CFrame - Vector3 = pure translation)
	local cf2 = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() - cf2.Position)
	local root = m:FindFirstChild("Root")
	if not root then
		root = Instance.new("Part"); root.Name = "Root"; root.Shape = Enum.PartType.Ball
		root.Size = Vector3.new(0.4, 0.4, 0.4); root.Transparency = 1
		root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.CanTouch = false
		root.CastShadow = false; root.Massless = true
		root.CFrame = CFrame.new(0, 0, 0); root.Parent = m
	end
	m.PrimaryPart = root
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "SharkTemplate" then c:Destroy() end end
	local tmpl = m:Clone(); tmpl.Name = "SharkTemplate"; tmpl.Parent = RS
	m:Destroy()
	local n = 0
	for _, d in ipairs(tmpl:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	print(("[Shark] OVERRIDE ACTIVE: published YOUR SharkOverride model as SharkTemplate (%d parts, scaled x%.2f to pet height). Delete SharkOverride to go back to the code-built shark."):format(n, sc))
end

task.spawn(function()
	local override = findOverride()
	if override then
		local okO, errO = pcall(publishOverride, override)
		if okO then return end
		warn("[Shark] override failed (" .. tostring(errO) .. ") -> falling back to the code-built shark")
	else
		print("[Shark] no SharkOverride model found -> using the code-built shark. To use your own model: drop any shark model into the place, name it 'SharkOverride', and it becomes the pet automatically.")
	end
	print("[Shark] BUILD 2026-08-24-N  COHESIVE-HEAD redesign: projecting snout dome, oval mouth + 5 teeth, big caudal fork -- geometry-audited")
	local ok, model, err = pcall(buildShark)
	if not (ok and model) then warn("[Shark] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Shark] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the stego/raptor")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Shark] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "SharkTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "SharkTemplate"; tmpl.Parent = RS
	print(("[Shark] published ReplicatedStorage.SharkTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	-- visible copy in Workspace (offset so it doesn't overlap the stego/raptor)
	local target = CFrame.new(20, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(-10, 6, -10) end
	pcall(function() model:PivotTo(target) end)

	print(("[Shark] Shark built: %d parts (body union %s). Visible copy in Workspace, template -> ReplicatedStorage.SharkTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN (mirrors HatchRaptorSpawn): the client fires HatchSharkSpawn with
-- a CFrame; the server clones the union template there + floats it.
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchSharkSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("SharkTemplate") or RS:WaitForChild("SharkTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedShark_" .. player.Name; pet.Parent = Workspace
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
