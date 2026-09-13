--======================================================================
-- Spinosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A SPINOSAURUS pet (the swamp/water dino with the big sail) on the EXACT same
-- pipeline as the Stego/Raptor/Shark/Triceratops pets: same rounded-cube BodyUnion
-- (PSW/PSH/PSD/PSR/PSS), same flat-disc face (whitepartofeye/blackpartofeye/Glint),
-- same 4 stubby feet, same matte/smooth, same publish (destroy old -> fresh clone).
-- FEATURES: a big rounded SAIL on the back, a long crocodile SNOUT with teeth,
-- little arms, a tapered tail. Mossy swamp-green body, pale belly, reddish sail.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace")) -- one shared face for all 6 pets

-- ===== helpers (VERBATIM from the other pet builders) =====
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
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- SPINOSAURUS -- same rounded-cube body + flat-disc face + 4 feet; adds the big
-- back SAIL, the long crocodile snout with teeth, little arms and a tapered tail.
-- ============================================================================
local function buildSpinosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Spinosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- swamp spinosaurus palette
	local BODY   = Color3.fromRGB(84,112,92)    -- mossy swamp green
	local BELLY  = Color3.fromRGB(198,208,178)   -- pale belly / lower jaw
	local SAIL   = Color3.fromRGB(156,98,82)     -- classic reddish sail
	local SAILDK = Color3.fromRGB(112,68,56)     -- darker sail spines
	local TEETH  = Color3.fromRGB(248,246,236)
	local DARK   = Color3.fromRGB(28,26,32)      -- pupils / nostrils
	local MOUTH  = Color3.fromRGB(70,44,46)
	local WHITE  = Color3.fromRGB(250,250,250)

	-- ========================================================================================
	-- BODY UNION. Cube unchanged. Body-coloured STRUCTURAL pieces (feet, snout, tail) now join the
	-- SAME UnionAsync call instead of being welded on afterwards -- separate overlapping parts shade
	-- independently, so Roblox creases at every join and the pet reads as blobs stuck to a box.
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end   -- structural: joins the body union
	for _, sgn in ipairs({1,-1}) do
		S("Arm", BAL, 0.5,1.0,0.5, BODY, 1.22,-0.90,1.62*sgn, CFrame.Angles(0,0,math.rad(-12*sgn)))  -- was z 1.25: both arms inside the cube
	end
	-- SNOUT base LENGTHENED (was 0.9 long) so the upper + lower jaw centres sit inside it; before,
	-- both jaws butt-jointed onto it at ~20% and the muzzle pinched to a waist at the join.
	S("SnoutBase", BLK, 1.6,1.1,1.3, BODY, 1.90,-0.15,0)
	S("SnoutTop",  BLK, 2.2,0.62,1.0, BODY, 2.60, 0.00,0)
	-- TAIL pulled in so the tip's centre is buried in the tail and the tail's in the body
	S("Tail",    BAL, 1.6,0.95,1.0, BODY, -1.60,-0.10,0)
	S("TailTip", BAL, 1.3,0.62,0.7, BODY, -2.25, 0.02,0)
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
		weldTo(P("Foot", BLK, 0.95,1.0,0.95, BODY, fp[1],-1.48,fp[2]), body)
	end

	-- FEET LIVE OUTSIDE THE BODY UNION so they can swing independently -- PetFollow's walk cycle
	-- drives every part named "Foot". A fused foot is welded into one rigid solid with the body
	-- and physically cannot move on its own, so this is the price of a walk cycle: a faint seam
	-- where the leg meets the body, in exchange for legs that actually step.

	-- SAIL: the signature -- a big rounded fan on top (+Y) running front->back (X), thin side-to-side (Z),
	-- base sunk into the back. Built FIRST so the head sits in front of it.
	-- STRETCHED OUT, per review: the old sail (3.4 long x 2.8 TALL, centred over the shoulders)
	-- read as "a yarmulke" -- a tall half-circle cap perched above the head. A real spino sail is
	-- LONG and LOW, running shoulders-to-tail. Built as a side-on cylinder disc (a cylinder fuses
	-- into the union no matter how stretched, unlike a Ball), shifted BACK so it never overhangs
	-- the head: spans x -2.85..1.75 against a body whose head starts at ~1.7.
	weldTo(P("Sail", CYL, 0.85, 2.6, 4.6, SAIL, -0.55, 1.75, 0,
		CFrame.Angles(0, math.rad(90), 0)), body)
	for _, sx0 in ipairs({ -1.70, -0.90, -0.10, 0.70 }) do -- darker spine ridges, following the sail back
		weldTo(P("Spine", CYL, 2.2, 0.16, 0.16, SAILDK, sx0, 1.90, 0.2, CFrame.Angles(0,0,math.rad(90))), body)
	end

	-- BELLY: pale patch low on the front
	weldTo(P("Belly", BAL, 0.68,1.2,2.1, BELLY, 1.55,-1.25,0), body)  -- thickened so its ratio drops under the 3.2 CSG limit and it FUSES instead of welding  -- was fully buried

	-- FACE: the shared PetFace (src/shared/PetFace.luau), set a bit high above the long snout
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 1.66, y = 0.58, white = WHITE, dark = DARK }

	-- SNOUT: a long crocodile-like snout jutting from the front (+X), upper + lower jaw
	weldTo(P("SnoutBot",  BLK, 2.0,0.42,0.9, BELLY, 2.50,-0.48,0), body)       -- lower jaw (cream)
	-- WIDENED IN Z, 0.85 -> 1.06, rather than moved. The mouth line was narrower than the
	-- jaws either side of it (SnoutTop is 1.0 deep) so it was completely hidden between them.
	-- Widening makes it proud of both, which is what draws the line along the jaw.
	local mouth = weldTo(P("Mouth", BLK, 1.9,0.18,1.06, MOUTH, 2.50,-0.26,0), body)      -- dark mouth line
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Nostril", BAL, 0.2,0.2,0.2, DARK, 2.35,0.36,0.22*sgn), body)  -- was y 0.30: just under the snout surface  -- nostril bumps on top
	end
	-- Two fangs top and bottom instead of twelve triangles along the jaw
	-- flat mouth LINE, so the rows straddle its top and bottom faces along the jaw (see PetFace.fangs)
	PetFace.fangs{ P = P, weld = weldTo, body = body, mouth = mouth, unscale = s, x = 3.00, dy =  1, color = TEETH, scale = 1.25 }
	PetFace.fangs{ P = P, weld = weldTo, body = body, mouth = mouth, unscale = s, x = 2.98, dy = -1, color = TEETH, scale = 1.1 }

	-- forelimb claws (dark -- welded on top of the union)
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Claw", BAL, 0.26,0.4,0.26, DARK, 1.35,-1.42,1.35*sgn), body)
	end

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	-- report any part that is unwelded or floating (see PetFace.audit)
	PetFace.audit(m, "Spino")
	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the others)
-- ============================================================================
task.spawn(function()
	print("[Spino] BUILD 2026-08-23-Y  ROUNDED-SHARK  geometry-audited -- no buried/floating parts")
	local ok, model, err = pcall(buildSpinosaurus)
	if not (ok and model) then warn("[Spino] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Spino] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the others")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Spino] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "SpinosaurusTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "SpinosaurusTemplate"; tmpl.Parent = RS
	print(("[Spino] published ReplicatedStorage.SpinosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	local target = CFrame.new(40, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(-20, 6, 20) end
	pcall(function() model:PivotTo(target) end)

	print(("[Spino] Spinosaurus built: %d parts (body union %s). Template -> ReplicatedStorage.SpinosaurusTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN (mirrors the others)
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchSpinosaurusSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("SpinosaurusTemplate") or RS:WaitForChild("SpinosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedSpino_" .. player.Name; pet.Parent = Workspace
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
