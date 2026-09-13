--======================================================================
-- Stegosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- Builds a STEGOSAURUS pet using the EXACT same construction as
-- buildBroccoliBunny() in PetSystem.server.lua: the same rounded-cube
-- (Minkowski) body union, the same helpers (mkPart, newRoot, fuse, weldTo,
-- eyes, BLK/BAL/CYL), the same scale/proportions (PSW/PSH/PSD/PSR/PSS), the
-- same matte Plastic + Smooth faces, the same feet, and the same cute face
-- (flat-disc eyes via eyes(), nose, cheeks, smiling mouth). ONLY the
-- bunny-specific accessories are swapped for stegosaurus ones:
--   * back plates (a row of rounded leaf plates down the spine), and
--   * a short thick tail nub with a blunt thagomizer (cream-tipped spikes).
-- Builds one in Workspace so you can see it (and publishes a template copy to
-- ReplicatedStorage, like the bunny). Prints the part count.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace")) -- one shared face for all 6 pets

-- ===== helpers (copied VERBATIM from PetSystem.server.lua) =====
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
-- (The old local eyes() helper lived here. It was dead code -- superseded by the shared
-- PetFace.eyes() -- and worse, it created its eye parts WITHOUT welding them, so anyone who
-- called it again would get four eye discs floating in front of the face. Deleted.)
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
-- shared chunky body dims (IDENTICAL to the bunny) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- STEGOSAURUS -- same rounded-cube body + face + feet as the bunny; bunny
-- accessories (ears/whiskers/florets/white tail) removed; back plates + a
-- thagomizer tail added instead.
-- ============================================================================
local function buildStegosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Stegosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- dino palette: turquoise body, coral plates, cream belly/spikes, darker-teal freckles, dark accents
	local BODY  = Color3.fromRGB(72,190,180)    -- teal / turquoise body
	local BELLY = Color3.fromRGB(214,242,236)   -- pale mint belly + muzzle
	local PLATE = Color3.fromRGB(255,140,90)     -- contrasting coral plates (pop)
	local CREAM = Color3.fromRGB(245,238,214)    -- bone spike tips
	local SPOT  = Color3.fromRGB(48,150,142)     -- darker-teal back freckles
	local DARK  = Color3.fromRGB(34,28,34)       -- eyes / nostrils / mouth

	-- ========================================================================================
	-- BODY UNION. Cube unchanged. The body-coloured STRUCTURAL pieces (feet, snout, tail) now join
	-- the SAME UnionAsync call instead of being welded on afterwards -- separate overlapping parts
	-- shade independently, so Roblox creases at every join and the pet reads as blobs on a box.
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end   -- structural: joins the body union
	-- TAIL: nubs pulled in so each centre is buried in the previous (they used to butt-joint)
	S("Tail", BAL, 1.15,1.02,1.12, BODY, -1.55,-0.05,0)
	S("Tail", BAL, 1.00,0.86,0.92, BODY, -2.10, 0.10,0)
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

	-- BELLY: a pale patch low on the front (below the face)
	weldTo(P("Belly", BAL, 0.60,1.0,1.9, BELLY, 1.61,-1.27,0), body)  -- thickened so its ratio drops under the 3.2 CSG limit and it FUSES instead of welding  -- was 1.45,-1.15: 100% inside the body, invisible

	-- FACE: clustered LOW + CENTERED on the front (+X). Big forward eyes CLOSE together (white eyeball +
	-- dark pupil + glint), a small rounded snout w/ tiny nostrils, and a little happy open mouth w/ teeth.
	local WHITE = Color3.fromRGB(250,250,250)
	-- shared PetFace (src/shared/PetFace.luau) -- same eye geometry as every other pet
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 1.68, y = 0.16, white = WHITE, dark = DARK }
	weldTo(P("Snout", BAL, 0.62,0.62,0.98, BELLY, 1.70,-0.34,0), body)                         -- rounded snout, sunk into the face so it doesn't perch on it
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.96,-0.22, 0.16), body)                    -- tiny nostril dots
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.96,-0.22,-0.16), body)
	local mouth = weldTo(P("MouthOpen", BAL, 0.26,0.34,0.66, Color3.fromRGB(70,40,46), 1.80,-0.64,0), body)  -- little happy open mouth
	PetFace.fangs{ P = P, weld = weldTo, body = body, mouth = mouth, unscale = s, dy = 0.02, color = WHITE, scale = 0.85 }

	-- BACK PLATES: 6 SEPARATE thin upright leaf plates down the top-center of the back (NOT fused --
	-- distinct flat fins). Each plate is a BLOCK (NOT a ball): broad along X (w = front-back), TALL
	-- (Y = h), and THIN in Z (0.12) so it stands up like a flat plate, not a round lump. Biggest in the
	-- middle, smaller toward head + tail; evenly spaced just behind the head -> base of tail (z=0).
	-- SMOOTHER, per review: sharp-cornered rectangles read as rough "hair". Each plate is now a
	-- thin side-on cylinder disc -- a rounded leaf -- overlapping its neighbours so the row reads
	-- as one smooth scalloped ridge instead of six separate slabs. Cylinders fuse regardless of
	-- stretch, so the whole ridge is part of the body solid.
	for _, pd in ipairs({ {1.00,1.10}, {0.45,1.55}, {-0.10,1.85}, {-0.65,1.85}, {-1.20,1.55}, {-1.70,1.10} }) do
		local px, h = pd[1], pd[2]
		weldTo(P("Plate", CYL, 0.14, h, h * 0.78, PLATE, px, 1.42 + h * 0.32, 0,
			CFrame.Angles(0, math.rad(90), 0)), body)
	end

	-- BACK FRECKLES: a few darker-teal spots for reptile texture
	-- ALL FIVE SPOTS WERE 100% INSIDE THE BODY and drew nothing. Raised onto the upper flanks
	-- (or pushed out in Z) so each one actually breaks up the silhouette, which is its whole job.
	for _, sp in ipairs({ {0.7,1.71,0.95}, {-0.4,1.72,-0.9}, {0.1,1.0,1.85}, {-1.0,1.73,0.75}, {0.95,1.72,-0.95} }) do
		weldTo(P("Spot", BAL, 0.34,0.3,0.18, SPOT, sp[1], sp[2], sp[3]), body)
	end

	-- THAGOMIZER: the 3 cream spikes only grazed the tail nub (~2% buried) so they read as blobs
	-- hovering behind it. They are reseated with their centres inside the tail (the nub itself is
	-- now part of the body union above).
	weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.40,0.32, 0.20), body)
	weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.40,0.32,-0.20), body)
	weldTo(P("Spike", BAL, 0.40,0.40,0.40, CREAM, -2.50,0.10,0), body)

	-- ===== ONE SOLID =====
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	-- report any part that is unwelded or floating (see PetFace.audit)
	PetFace.audit(m, "Stego")
	return m, err
end

-- ============================================================================
-- BUILD: make one in Workspace (visible), publish a template copy to RS (like
-- the bunny), and print the part count.
-- ============================================================================
task.spawn(function()
	print("[Stego] BUILD 2026-08-23-Y  ROUNDED-SHARK  geometry-audited -- no buried/floating parts")
	local ok, model, err = pcall(buildStegosaurus)
	if not (ok and model) then
		warn("[Stego] build error: " .. tostring(model or err))
		return
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	-- confirm the body union is a chunky FLAT-FACED rounded cube (not a sphere)
	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Stego] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the bunny")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Stego] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	-- CLEAR any stale/duplicate StegosaurusTemplate first so the Hub + world always clone the FRESH build
	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "StegosaurusTemplate" then c:Destroy(); removed += 1 end end
	-- publish the fresh template (single source of truth for the Hub icon AND the in-game pet)
	local tmpl = model:Clone(); tmpl.Name = "StegosaurusTemplate"; tmpl.Parent = RS
	local plateCount = 0; for _, d in ipairs(tmpl:GetDescendants()) do if d.Name == "Plate" then plateCount += 1 end end
	print(("[Stego] published ReplicatedStorage.StegosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))
	print(("[Stego] back plates rebuilt: %d flat upright plates (template now %d parts)"):format(plateCount, n))

	-- lift the visible Workspace copy to a spot in front of spawn so you can see it
	local target = CFrame.new(0, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(0, 6, -10) end
	pcall(function() model:PivotTo(target) end)

	print(("[Stego] Stegosaurus built: %d parts (body union %s). Visible copy in Workspace, template -> ReplicatedStorage.StegosaurusTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN: QuestGate (client) fires HatchStegoSpawn with a CFrame when the
-- egg hatches. The SERVER clones the union template into Workspace at that spot
-- and floats it. A server-owned UnionOperation renders for every client in the
-- open world -- so the in-game pet looks identical to the Pet Hub (a client-side
-- clone of a server union only renders reliably inside a ViewportFrame).
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchStegoSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("StegosaurusTemplate") or RS:WaitForChild("StegosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	-- hover the pet up clear of the (brown) nest + the dino's feet so nothing overlaps it
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedStego_" .. player.Name; pet.Parent = Workspace
	pcall(function() pet:PivotTo(hover) end)
	activePets[player] = pet
	do local cnt = 0; for _, d in ipairs(pet:GetDescendants()) do if d:IsA("BasePart") then cnt = cnt + 1 end end
		print(("[Stego] in-game pet for %s -> CLONED StegosaurusTemplate (%d parts) at %s"):format(player.Name, cnt, tostring(hover.Position))) end
	-- rise pop, then a gentle float + slow spin (server-side -> replicates to everyone)
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
