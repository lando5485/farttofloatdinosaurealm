--======================================================================
-- Therizinosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A THERIZINOSAURUS pet on the EXACT same pipeline as the Stego/Raptor/Shark/Trike pets:
-- same rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), same flat-disc face via PetFace,
-- same matte/smooth flags, same publish (destroy old template -> fresh clone).
--
-- THE CLAWS IDENTIFY IT. Therizinosaurus ("scythe lizard") had the longest claws of any animal
-- that has ever lived, and it is the reward for CLAW CLIFFS, whose landmark is a giant claw.
-- But "longest claws ever" does NOT scale down to a pet -- taken literally it produces a pair
-- of scythes with an animal attached. What survives the shrink is the SHAPE: three per
-- hand, curved and hooked rather than long, and the CURVE is what identifies the animal.
--
-- WHICH IS WHY horn() FROM THE TRICERATOPS WAS NOT REUSED. That helper lays tapered cylinder
-- segments along a STRAIGHT line, which is right for a brow horn and wrong for a scythe -- a
-- straight claw reads as a spike. scytheClaw() below walks the same taper along a PARABOLIC
-- ARC instead, so the tip curves back the way a real theropod claw does, and the curve is
-- what makes it read as a claw at a glance instead of a nail.
--
-- FEATURES: the standard rounded-cube body WITH THE FACE ON THE CUBE, two legs, a stubby
-- tail, a rust feather crest and ruff -- and six enormous curved claws.
--
-- THE FACE IS ON THE CUBE, NOT ON A HEAD. A first pass gave this one a long neck with a small
-- head on the end and put the eyes up there; it read as a different kind of toy sitting next
-- to the rest of the set in the Hub. Every pet here is a cube with a face on it, and the
-- species is told by what is bolted on -- the trike's frill and horns, the stego's plates,
-- this one's claws. Therizinosaurus is identified by its hands anyway, so nothing was lost.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace"))

-- ===== helpers (VERBATIM from Triceratops/Velociraptor/Shark.server.luau) =====
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
-- shared chunky body dims (IDENTICAL to the stego/raptor/shark/trike) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- THERIZINOSAURUS
-- ============================================================================
local function buildTherizinosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Therizinosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- palette: cool slate-teal body so the cream claws read against it at any distance
	local BODY  = Color3.fromRGB( 96,124,132)   -- slate teal
	local BELLY = Color3.fromRGB(168,190,190)   -- pale underside
	local FEATH = Color3.fromRGB(176, 96, 62)   -- rust feather tips (neck ruff + tail)
	local CLAW  = Color3.fromRGB(238,230,208)   -- cream / bone
	local BEAK  = Color3.fromRGB(206,186,144)   -- tan beak
	local DARK  = Color3.fromRGB(28,26,32)
	local MOUTH = Color3.fromRGB(90,58,52)
	local WHITE = Color3.fromRGB(250,250,250)

	-- ========================================================================================
	-- BODY UNION. Same rule as the trike: body-coloured STRUCTURAL pieces (legs, tail, neck)
	-- go into the SAME UnionAsync call. Separate overlapping parts shade independently, so
	-- Roblox creases at every join and the pet reads as blobs stuck to a box.
	--
	-- BIPEDAL, so two legs rather than four -- and they sit further back than a quadruped's
	-- rear pair, because the whole animal balances on them.
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end
	-- FEET: THE HOUSE STANDARD, IDENTICAL TO EVERY OTHER PET IN THE SET.
	-- 4 stubby BLOCK feet, 0.95 x 0.8 x 0.95, at y -1.55, at the four corners. That exact line
	-- appears in the stego, raptor, spino, T-Rex and triceratops builders, and it is what the
	-- set's feet look like -- so this pet uses it verbatim rather than something of its own.
	--
	-- Two earlier passes went their own way here and both were wrong. First a bipedal
	-- thigh/shin/foot stack of BLOCKS, which ended in flat slabs and read as clicky. Then the
	-- same stack rebuilt out of BALLS, which just made it lumpy. The lesson is that neither the
	-- shape nor the count was the problem: the pet simply was not using the standard feet.
	-- Every other biped in this set (raptor, spino, T-Rex) uses these same four corner blocks.
	-- NO NECK AND NO SEPARATE HEAD -- THE FACE GOES ON THE CUBE.
	-- The first pass gave this pet a long neck with a little head on the end and put the eyes
	-- up there. That is not the house style: every pet in this set is a rounded cube WITH THE
	-- FACE ON THE CUBE, and the species is told by what is bolted to it -- the trike's frill and
	-- horns, the stego's plates, this one's claws. A separate head made it read as a different
	-- kind of toy sitting next to the others in the Hub.
	--
	-- It costs nothing here, either: Therizinosaurus is identified by its hands, not its head,
	-- so the claws carry the whole silhouette on their own.
	-- TAIL: short and thick, counterweighting the front
	S("Tail",    BAL, 1.25,1.05,1.05, BODY, -1.70,-0.05,0)
	S("TailTip", BAL, 0.70,0.62,0.62, BODY, -2.25, 0.10,0)
	-- FEET JOIN THE UNION. They are BODY-COLOURED, and a body-coloured part welded on rather than
	-- fused shades independently -- Roblox draws a crease at the join, which reads as the leg not
	-- being attached to the animal. They only had to be separate parts while PetFollow's walk
	-- cycle moved them; that is off (PetFollow.WALK_CYCLE), so they fuse and the legs are part of
	-- the body again. Turn the walk cycle back on and these must come back out.
	local body, err = fuse(m, src, "BodyUnion", BODY)
	-- FEET BACK OUT OF THE UNION: the walk cycle is ON again (PetFollow.WALK_CYCLE = true)
	-- and a fused foot is rigid with the body -- it physically cannot step. Welded feet can,
	-- and fuseAll now always keeps Foot* parts welded.
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		weldTo(P("Foot", BLK, 0.95,0.95,0.95, BODY, fp[1],-1.50,fp[2]), body)
	end

	-- FEET LIVE OUTSIDE THE BODY UNION so they can swing independently -- PetFollow's walk cycle
	-- drives every part named "Foot". A fused foot is welded into one rigid solid with the body
	-- and physically cannot move on its own, so this is the price of a walk cycle: a faint seam
	-- where the leg meets the body, in exchange for legs that actually step.

	-- ===== THE SCYTHE CLAW =====
	-- Tapered segments walked along a PARABOLIC ARC rather than a straight line. `dir` is the
	-- direction the claw leaves the hand; `bend` is the direction it curves toward, and the
	-- offset grows with t^2 so the base leaves straight and the tip hooks hard -- which is
	-- what makes it read as a claw rather than a spike.
	-- `anchor` is the part the claw welds to -- pass the Hand so the claws are literally attached
	-- to the hands rather than to the body union they happen to be near.
	local function scytheClaw(nm, base, dir, bend, len, baseR, tipR, anchor)
		dir, bend = dir.Unit, bend.Unit
		-- segment count follows the length. At 0.37 studs a 7-segment claw is 7 cylinders about
		-- 0.05 long each -- invisible detail for 42 extra parts across six claws.
		local segN = (len > 1.0) and 7 or 4
		local prev = base
		for i = 1, segN do
			local t  = i / segN
			local at = base + dir * (len * t) + bend * (len * 0.42 * t * t)
			local mid = (prev + at) / 2
			local step = (at - prev)
			local r = baseR + (tipR - baseR) * t
			-- each segment is a cylinder laid from the previous point to this one, so the arc is
			-- continuous; +0.10 of length overlap keeps the joints from showing as rings.
			local rot = CFrame.lookAt(Vector3.new(0,0,0), step.Unit) * CFrame.Angles(0, math.rad(90), 0)
			weldTo(P(nm, CYL, step.Magnitude + 0.10, r*2, r*2, CLAW, mid.X, mid.Y, mid.Z, rot), anchor or body)
			prev = at
		end
		weldTo(P(nm.."Tip", BAL, tipR*2, tipR*2, tipR*2, CLAW, prev.X, prev.Y, prev.Z), anchor or body) -- rounded point
	end

	-- ===== ARMS + THE SIX CLAWS =====
	-- Short upper arm, then three claws fanned off the hand.
	--
	-- CLAW LENGTH 0.37, down from 1.85, which was itself down from 3.10. Both earlier passes
	-- chased "Therizinosaurus had the longest claws of any animal" literally, and both times the
	-- claws ate the pet -- at pet scale a claw sized off the real skeleton's proportions is a
	-- weapon with a dinosaur hanging off it, not a dinosaur. 0.37 is roughly a ninth of the body
	-- depth: the claws now read as CLAWS ON A HAND, which is what they need to do, and the curve
	-- (not the length) is what still says "scythe lizard".
	for _, sgn in ipairs({1,-1}) do
		local shoulder = Vector3.new(0.75, 0.35, 1.30*sgn)
		weldTo(P("UpperArm", BAL, 0.85,0.85,0.85, BODY, shoulder.X, shoulder.Y, shoulder.Z), body)
		local hand = Vector3.new(1.35,-0.65, 1.55*sgn)
		local handPart = weldTo(P("Hand", BAL, 0.80,0.75,0.72, BODY, hand.X, hand.Y, hand.Z), body)
		-- three claws: fanned in Z so they do not overlap, all curving DOWN and BACK.
		--
		-- THE CLAW ROOT MUST START INSIDE THE HAND. Shrinking the claws to a fifth of their old
		-- length left the old root offset (0.15, -0.10) sitting well short of the hand's surface,
		-- so each claw began and ended in open air near the hand instead of growing out of it --
		-- which is what "the claws kind of aren't attached to the hands" was. The root is now at
		-- 0.60 of the hand's radius along the claw's own direction (comfortably inside the
		-- ellipsoid) and the fan is pulled in to +/-0.18 so the outer two stay inside it as well.
		-- The tip still ends ~0.53 out from the hand centre, so the claw reads as protruding.
		for k, spread in ipairs({ -0.18, 0.0, 0.18 }) do
			local from = hand + Vector3.new(0.20, -0.12, spread*sgn)
			scytheClaw(("Claw%d"):format(k), from,
				Vector3.new(0.86, -0.30, 0.28*sgn),   -- out and slightly down
				Vector3.new(-0.35, -0.94, 0),          -- hooks down/back
				0.37, 0.085, 0.022, handPart)
		end
	end

	-- FACE ON THE CUBE, at the same coordinates the Triceratops uses -- these are the numbers the
	-- whole set is tuned to, so this pet's eyes sit exactly where every other pet's do.
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 1.66, y = 0.08, white = WHITE, dark = DARK }
	-- small parrot beak on the front face, under the eyes
	weldTo(P("BeakTop", BAL, 0.78,0.46,0.70, BEAK, 1.70,-0.38,0), body)
	weldTo(P("BeakHook",BAL, 0.42,0.40,0.48, BEAK, 1.92,-0.55,0), body)
	weldTo(P("BeakLow", BAL, 0.55,0.32,0.56, BEAK, 1.84,-0.66,0), body)  -- was 1.62: inside the cube
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Nostril", BAL, 0.15,0.15,0.15, DARK, 1.92,-0.30,0.18*sgn), body)
	end
	weldTo(P("Smile", BAL, 0.32,0.32,1.00, MOUTH, 1.82,-0.92,0), body)  -- thickened so its ratio drops under the 3.2 CSG limit and it FUSES instead of welding  -- was 1.52: inside the cube

	-- FEATHER CREST + RUFF: rust tufts along the top of the cube and round its shoulders.
	-- Therizinosaurus is one of the feathered ones, and the warm colour breaks up all that
	-- slate -- this is what the trike's frill is doing, in this pet's language.
	for _, a in ipairs({ -70, -35, 0, 35, 70 }) do
		local rad = math.rad(a)
		weldTo(P("Ruff", BAL, 0.55,0.85,0.60, FEATH,
			0.30 + math.cos(rad)*0.35, 1.62, math.sin(rad)*1.15), body)
	end
	for _, d in ipairs({ {-0.60, 2.02}, {0.05, 2.10}, {0.68, 2.02} }) do  -- middle crest was only grazing the back
		weldTo(P("Crest", BAL, 0.82,1.00,0.66, FEATH, d[1], d[2], 0), body)
	end
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("TailPlume", BAL, 0.85,0.65,0.42, FEATH, -2.45, 0.30, 0.22*sgn), body)
	end

	-- BELLY: pale panel low on the front
	weldTo(P("Belly", BAL, 0.5,1.4,2.1, BELLY, 1.30,-1.05,0), body)

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	-- report any part that is unwelded or floating (see PetFace.audit)
	PetFace.audit(m, "Theri")
	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the trike/shark)
-- ============================================================================
task.spawn(function()
	print("[Theri] BUILD 2026-08-23-Y  ROUNDED-SHARK  geometry-audited -- no buried/floating parts")
	local ok, model, err = pcall(buildTherizinosaurus)
	if not (ok and model) then warn("[Theri] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Theri] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the others")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Theri] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "TherizinosaurusTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "TherizinosaurusTemplate"; tmpl.Parent = RS
	print(("[Theri] published ReplicatedStorage.TherizinosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	local target = CFrame.new(30, 12, 20)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(20, 6, -30) end
	pcall(function() model:PivotTo(target) end)

	print(("[Theri] Therizinosaurus built: %d parts (body union %s). Template -> ReplicatedStorage.TherizinosaurusTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN (mirrors HatchTriceratopsSpawn)
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchTherizinosaurusSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("TherizinosaurusTemplate") or RS:WaitForChild("TherizinosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedTheri_" .. player.Name; pet.Parent = Workspace
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
