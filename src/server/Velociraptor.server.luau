--======================================================================
-- Velociraptor.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A VELOCIRAPTOR pet built on the EXACT same pipeline as the Stegosaurus pet:
-- same rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), same flat-disc face
-- (whitepartofeye/blackpartofeye/Glint), same 4 stubby feet, same matte/smooth,
-- same publish (destroy old VelociraptorTemplate -> publish a fresh clone).
-- Only the FEATURES change: no plates/thagomizer; instead a longer snout with
-- pointed teeth, brow ridges + a crest, a long straight tail, little clawed arms,
-- and sickle-claw toes. Cool-grey body, blue stripe + eye markings, cream belly.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace")) -- one shared face for all 6 pets

-- ===== helpers (VERBATIM from Stegosaurus.server.luau) =====
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
-- shared chunky body dims (IDENTICAL to the stego/bunny) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- VELOCIRAPTOR -- same rounded-cube body + flat-disc face + 4 feet as the stego;
-- stego plates/spikes removed; snout/teeth/brow/crest/tail/arms/sickle-claws added.
-- ============================================================================
local function buildVelociraptor()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Velociraptor"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- raptor palette
	local BODY  = Color3.fromRGB(122,138,124)  -- sage grey-green (was flat battleship grey -- the single biggest "looks like a brick" factor)
	local BELLY = Color3.fromRGB(238,232,212)   -- cream belly + snout underside
	local STRIPE= Color3.fromRGB(70,120,210)    -- blue stripe + eye markings + crest
	local DARK  = Color3.fromRGB(30,28,34)      -- pupils / nostrils
	local CLAW  = Color3.fromRGB(26,24,28)      -- dark claws
	local TEETH = Color3.fromRGB(248,244,230)   -- pointed teeth
	local AMBER = Color3.fromRGB(255,196,70)    -- amber iris accent
	local WHITE = Color3.fromRGB(250,250,250)

	-- ========================================================================================
	-- BODY UNION. The rounded cube is UNCHANGED -- that chunky cube silhouette is the house style.
	-- What changed: every body-coloured STRUCTURAL piece (skull, muzzle, legs, arms, tail) now goes
	-- into the SAME UnionAsync call instead of being welded on afterwards. Separate overlapping
	-- parts each shade independently, so Roblox draws a hard crease at every join and the pet reads
	-- as a pile of blobs stuck to a box. Fused into one solid with SmoothingAngle they blend into a
	-- single continuous creature -- which is what "not fully connected" was really about.
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end   -- structural: joins the body union
	local function SW(n, sx, sy, sz, c, x, y, z, rot)   -- structural WEDGE: also joins the union
		local p = Instance.new("WedgePart"); p.Name = n
		p.Size = Vector3.new(sx*s, sy*s, sz*s); p.Color = c
		local cf = CFrame.new(x*s, y*s, z*s); if rot then cf = cf * rot end
		p.CFrame = cf; flagPart(p); p.Parent = m; src[#src+1] = p; return p
	end

	-- SNOUT: a short rounded muzzle on the cube's front face -- deliberately NOT a separate skull.
	-- The face belongs ON the cube like the triceratops; a projecting head made this pet read wrong.
	-- SEPARATE PROJECTING HEAD + LONG NARROW WEDGE SNOUT, per review: the face sitting flat on
	-- the cube front read as a mammal, not a raptor. The head is a wide dome pushed ~0.8 out of
	-- the cube; the snout is a long, low wedge running out of it. Both fuse into the body, and
	-- the silhouette finally says "raptor" on its own.
	S("Head",  BAL, 1.5,1.5,1.9, BODY, 1.75, 0.50,0)
	-- MUZZLE: the T-Rex recipe (the one the review calls "close"), raptor-tuned -- a LONGER,
	-- NARROWER tilted slab whose back half is buried in the head dome. The snout grows out of
	-- the head as one form; no giant separate wedge (that read as pasted-on).
	S("Muzzle", BLK, 1.5, 0.62, 0.85, BODY, 2.45, 0.10, 0, CFrame.Angles(0,0,math.rad(-12)))

	-- FEET: 4 stubby feet, same as the other pets

	-- ARMS: small forelimbs tucked against the front sides
	for _, sgn in ipairs({1,-1}) do
		-- FORWARD-FACING raptor arms per review (the old sticks read as dangling twigs):
		-- short horizontal forearms reaching ahead of the chest, small hands at the tips.
		-- ARM = a little HALF-SPHERE sticking out of the chest, per review: a ball centred on
		-- the cube front, half in / half out. Claws: three tiny wedges, added below.
		S("Arm", BAL, 0.80,0.80,0.80, BODY, 1.85,-0.50,0.95*sgn)
	end
	-- POWERFUL HIND LEGS read through hip bulges on the rear flanks (proud of the cube side)
	for _, sgn in ipairs({1,-1}) do
		S("Thigh", BAL, 1.55,1.75,0.95, BODY, -0.75,-0.60,1.66*sgn)  -- substantially thicker, per review
	end

	-- TAIL: a long tapering tail off the BACK (-X). Segments were previously spaced further apart
	-- than their own radii so the last two broke off into free-floating blobs.
	-- REVAMP: the old tail ran long and FLAT, which made the whole pet a low grey slab. Raptors
	-- carry the tail swept UP -- same overlap between segments, but each one steps higher, and
	-- the whole thing is a touch shorter. Reads athletic instead of dragging.
	S("Tail",    BAL, 1.45,1.15,1.15, BODY, -1.75,0.05,0)
	S("Tail",    BAL, 1.15,0.90,0.90, BODY, -2.35,0.30,0)
	S("Tail",    BAL, 0.90,0.70,0.70, BODY, -2.85,0.60,0)
	S("TailTip", BAL, 0.62,0.50,0.50, BODY, -3.20,0.90,0)

	-- FEET JOIN THE UNION. They are BODY-COLOURED, and a body-coloured part welded on rather than
	-- fused shades independently -- Roblox draws a crease at the join, which reads as the leg not
	-- being attached to the animal. They only had to be separate parts while PetFollow's walk
	-- cycle moved them; that is off (PetFollow.WALK_CYCLE), so they fuse and the legs are part of
	-- the body again. Turn the walk cycle back on and these must come back out.
	local body, err = fuse(m, src, "BodyUnion", BODY)
	-- FEET BACK OUT OF THE UNION: the walk cycle is ON again (PetFollow.WALK_CYCLE = true)
	-- and a fused foot is rigid with the body -- it physically cannot step. Welded feet can,
	-- and fuseAll now always keeps Foot* parts welded.
	-- Back feet BIGGER, per review ("large three-toed feet" under the powerful legs)
	weldTo(P("Foot", BLK, 0.90,0.95,0.90, BODY,  0.95,-1.50, 0.78), body)
	weldTo(P("Foot", BLK, 0.90,0.95,0.90, BODY,  0.95,-1.50,-0.78), body)
	weldTo(P("Foot", BLK, 1.15,0.95,1.15, BODY, -0.95,-1.50, 0.82), body)
	weldTo(P("Foot", BLK, 1.15,0.95,1.15, BODY, -0.95,-1.50,-0.82), body)

	-- FEET LIVE OUTSIDE THE BODY UNION so they can swing independently -- PetFollow's walk cycle
	-- drives every part named "Foot". A fused foot is welded into one rigid solid with the body
	-- and physically cannot move on its own, so this is the price of a walk cycle: a faint seam
	-- where the leg meets the body, in exchange for legs that actually step.

	-- sickle claws + belly (different colours, so they stay welded on top of the union)
	for _, fp in ipairs({ {-0.95,0.82}, {-0.95,-0.82} }) do
		-- THE sickle claw: one BIG curved claw per REAR foot only, per review -- the raptor's
		-- signature. (Front feet keep plain toes; four sickles read as clutter.)
		weldTo(P("FootClaw", CYL, 0.84,0.26,0.26, CLAW, fp[1]+0.80, -1.78, fp[2], CFrame.Angles(0,0,math.rad(38))), body)  -- Foot* name: the walk cycle carries it in lockstep with its foot
		-- was y -1.38, which is INSIDE the cube (half-height 1.8). All four toe claws were invisible.
		-- Dropped below the cube and pushed forward so each sits on the front of its own foot.
	end
	weldTo(P("Belly", BAL, 0.60,1.0,1.9, BELLY, 1.61,-1.27,0), body)  -- thickened so its ratio drops under the 3.2 CSG limit and it FUSES instead of welding  -- was fully buried

	-- BLUE STRIPE along the TOP spine only (clean + flush). The side stripes were removed -- on the
	-- rounded cube they poked out near the curved edges and read as a random blue blob on the side.
	weldTo(P("Stripe", BLK, 3.2,0.18,0.95, STRIPE, -0.2,1.76,0), body)  -- bolder racing stripe

	-- FACE: the shared PetFace (see src/shared/PetFace.luau). The raptor's face used to carry
	-- 22 overlapping pieces on one flat cube face -- eye markings, brow ridges, an amber ring, a
	-- muzzle, an under-jaw, a mouth, eight tooth halves, nostrils and a crest all piled together.
	-- That jumble is what read as "bunched together weird shapes". It is now the same clean
	-- eye pair every other pet uses, plus a mouth and two small fangs. Amber iris kept -- that
	-- is the raptor's signature colour.
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 2.34, y = 0.55, step = 0.03,
	              white = WHITE, dark = DARK, iris = AMBER }
	weldTo(P("Jaw", BLK, 1.65,0.28,0.78, BELLY, 2.15,-0.35,0, CFrame.Angles(0,0,math.rad(-6))), body)  -- cream lower jaw, EXTENDED BACK INTO THE BODY like the T-Rex chin (spans 1.32..2.98: rear 0.38 inside the cube, tip at the muzzle tip)
	-- FACE REBUILT BRACHIOSAURUS-STYLE (the approved look): flat CYL discs, not squashed balls.
	-- The old Mouth was a 0.90x0.28x0.60 Ball at x 2.45 -- ratio 3.2, so it was left welded, and
	-- the exposure audit measured it 0% exposed: swallowed whole by the snout, an invisible mouth.
	-- Discs fuse (no rotation, no Ball), and the raycast seating pass places them ON the measured
	-- snout surface before the fuse, so they cannot end up buried or floating again.
	-- The flat disc mouth on the snout tip read as "a large round purple NOSE" -- exactly the
	-- mammal signal the review flagged. Real raptor mouth instead: a small dark ellipse tucked
	-- under the snout tip between the jaws, two tiny teeth straddling its front (solved against
	-- its ellipsoid: surface x = 3.32 at dz +/-0.14), and two tiny nostril DOTS up on the snout.
	-- MOUTH = the dark seam sandwiched between the snout's flat underside and the jaw plate --
	-- recessed into the head form, not a ball on the nose. Two tiny teeth hang at the jaw's lip.
	-- Mouth = the recessed dark seam between muzzle and jaw (same construction as the T-Rex),
	-- two tiny teeth at the lip, small nostrils built into the muzzle's top plane near the tip.
	weldTo(P("Mouth", BLK, 0.65,0.14,0.72, Color3.fromRGB(60,34,40), 2.65,-0.18,0, CFrame.Angles(0,0,math.rad(-10))), body)
	weldTo(P("Tooth", BLK, 0.10,0.13,0.10, TEETH, 2.95,-0.26, 0.16), body)
	weldTo(P("Tooth", BLK, 0.10,0.13,0.10, TEETH, 2.95,-0.26,-0.16), body)
	weldTo(P("Nostril", BAL, 0.09,0.09,0.09, DARK, 2.95, 0.31, 0.14), body)
	weldTo(P("Nostril", BAL, 0.09,0.09,0.09, DARK, 2.95, 0.31,-0.14), body)
	-- CREST REMOVED per review: "the blue object on top of the head looks like a random hat".
	-- The raptor identity now comes from the silhouette itself -- snout, tail, legs, claws.

	-- little clawed hands (dark claws stay welded -- different colour from the union)
	for _, sgn in ipairs({1,-1}) do
		for _, cz in ipairs({ -0.16, 0, 0.16 }) do
			-- three tiny WEDGE claws fanned on each arm nub, tips forward-down, backs buried
			-- (nub surface is at x ~2.06 at these offsets, so each claw straddles it)
			local cl = Instance.new("WedgePart"); cl.Name = "Claw"
			cl.Size = Vector3.new(0.11, 0.15, 0.28) * s
			cl.Color = CLAW
			cl.CFrame = CFrame.new(2.21 * s, -0.58 * s, (0.95 * sgn + cz) * s)
				* CFrame.Angles(0, math.rad(-90), 0)
			flagPart(cl); cl.Parent = m
			weldTo(cl, body)
		end
	end

	-- blue stripe continues onto the tail
	weldTo(P("Stripe", BLK, 1.8,0.14,0.50, STRIPE, -2.35,0.72,0), body)  -- follows the upswept tail

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	-- report any part that is unwelded or floating (see PetFace.audit)
	PetFace.audit(m, "Raptor")
	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the stego): build in Workspace, clear any stale
-- VelociraptorTemplate, publish a fresh clone, print the part count.
-- ============================================================================
task.spawn(function()
	print("[Raptor] BUILD 2026-08-24-B  ARMS-OUT  geometry-audited -- no buried/floating parts")
	local ok, model, err = pcall(buildVelociraptor)
	if not (ok and model) then warn("[Raptor] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Raptor] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the stego")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Raptor] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "VelociraptorTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "VelociraptorTemplate"; tmpl.Parent = RS
	print(("[Raptor] published ReplicatedStorage.VelociraptorTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	-- visible copy in Workspace (offset from the stego's so they don't overlap)
	local target = CFrame.new(10, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(10, 6, -10) end
	pcall(function() model:PivotTo(target) end)

	print(("[Raptor] Velociraptor built: %d parts (body union %s). Visible copy in Workspace, template -> ReplicatedStorage.VelociraptorTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN (mirrors HatchStegoSpawn): the client fires HatchRaptorSpawn with
-- a CFrame; the server clones the union template there + floats it.
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchRaptorSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("VelociraptorTemplate") or RS:WaitForChild("VelociraptorTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedRaptor_" .. player.Name; pet.Parent = Workspace
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
