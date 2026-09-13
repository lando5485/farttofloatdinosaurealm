--======================================================================
-- Triceratops.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A TRICERATOPS pet on the EXACT same pipeline as the Stego/Raptor/Shark pets:
-- same rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), same flat-disc face
-- (whitepartofeye/blackpartofeye/Glint), same 4 stubby feet, same matte/smooth,
-- same publish (destroy old TriceratopsTemplate -> fresh clone).
-- FEATURES: a big rounded NECK FRILL behind the head, THREE blunt horns (two
-- brow + one nose), a small parrot BEAK, big cute eyes, a short stubby tail.
-- Earthy olive body, darker frill, cream/bone horns + beak, light belly.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PetFace   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace")) -- one shared face for all 6 pets

-- ===== helpers (VERBATIM from Velociraptor/Shark.server.luau) =====
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
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.SmoothingAngle = 60 end)
		u.Parent = model
		PetFace.forcePrecise(u, model.Name)
		return u, nil
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name.."Chunk" end
		return nil, tostring(u)
	end
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
-- shared chunky body dims (IDENTICAL to the stego/raptor/shark) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- TRICERATOPS -- same rounded-cube body + flat-disc face + 4 feet;
-- shark fins removed; neck frill + 3 horns + beak + stubby tail added.
-- ============================================================================
local function buildTriceratops()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Triceratops"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- triceratops palette
	local BODY  = Color3.fromRGB(143,181,104)  -- soft sage / olive green
	local FRILL = Color3.fromRGB(111,154,78)    -- darker green frill
	local BELLY = Color3.fromRGB(200,220,165)   -- lighter cream-green belly
	local HORN  = Color3.fromRGB(236,225,196)   -- cream / bone horns
	local BEAK  = Color3.fromRGB(214,196,150)   -- tan / bone beak
	local DARK  = Color3.fromRGB(28,26,32)      -- pupils / nostrils
	local MOUTH = Color3.fromRGB(90,58,52)       -- smile
	local WHITE = Color3.fromRGB(250,250,250)

	-- ========================================================================================
	-- BODY UNION. Cube unchanged. Body-coloured STRUCTURAL pieces (the tail) join the SAME
	-- UnionAsync call instead of being welded on afterwards -- separate overlapping parts shade
	-- independently, so Roblox creases at every join and the pet reads as blobs stuck to a box.
	--
	-- FEET ARE THE ONE EXCEPTION, AND IT IS NOT A STYLE CHOICE. They used to be S() pieces here,
	-- which handed them to UnionAsync -- and fuse() DESTROYS every source part after unioning, so
	-- the four Foot parts did not exist in the published template at all. PetFollow's walk cycle
	-- finds its feet by name (p.Name:sub(1,4) == "Foot"), so it found ZERO on this pet and the
	-- Triceratops was the only quest dino that slid around rigid while the others stepped.
	-- Welded AFTER the union instead, exactly like Stegosaurus/Velociraptor/Spinosaurus do
	-- (PetFace.fuseAll then keeps them out on its own -- see isMovingPart).
	-- The cost is the documented faint seam at each ankle; the payoff is legs that actually step.
	-- ========================================================================================
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local function S(...) src[#src+1] = P(...) end   -- structural: joins the body union
	-- TAIL pulled in so the tip's centre is buried in the tail and the tail's in the body
	S("Tail",    BAL, 1.1,0.95,0.95, BODY, -1.55,-0.10,0)
	S("TailTip", BAL, 0.6,0.55,0.55, BODY, -2.05, 0.02,0)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- FEET: welded onto the finished union so the walk cycle can step them.
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		weldTo(P("Foot", BLK, 0.95,0.8,0.95, BODY, fp[1],-1.55,fp[2]), body)
	end

	-- ===== tapered-cone horn helper: 3 cylinder segments (thick base -> thin) + a rounded ball tip, laid along `dir`.
	-- The base end sits at (bx,by,bz) so sinking that point into the face/frill embeds the horn (no float). =====
	local function horn(nm, bx,by,bz, dir, len, baseR, tipR)
		dir = dir.Unit
		local rot = CFrame.lookAt(Vector3.new(0,0,0), dir) * CFrame.Angles(0, math.rad(90), 0) -- CYL length (local X) -> along dir
		local segN = 3
		for i = 0, segN-1 do
			local r = baseR + (tipR - baseR) * (i / (segN - 1))
			local c = Vector3.new(bx,by,bz) + dir * (len * (i + 0.5) / segN)
			weldTo(P(nm, CYL, len/segN + 0.08, r*2, r*2, HORN, c.X, c.Y, c.Z, rot), body) -- +0.08 overlap so segments merge smoothly
		end
		local tip = Vector3.new(bx,by,bz) + dir * len
		weldTo(P(nm.."Tip", BAL, tipR*2, tipR*2, tipR*2, HORN, tip.X, tip.Y, tip.Z), body) -- rounded point
	end

	-- NECK FRILL: a wide rounded shield behind/above the head, leaning back, framing the face. Built FIRST so the
	-- eyes/horns/beak sit in front of it. SCALLOPED edge = 5 rounded bumps placed ON the (leaned) frill's top rim --
	-- transformed by the frill's own CFrame so they sit on the shield + overlap it (NOT floating above the body).
	local frillCF = CFrame.new(0.15, 1.0, 0) * CFrame.Angles(0,0,math.rad(-20))
	weldTo(P("Frill", BAL, 0.6, 2.9, 3.9, FRILL, frillCF.X, frillCF.Y, frillCF.Z, frillCF - frillCF.Position), body)
	for _, a in ipairs({ -60, -30, 0, 30, 60 }) do
		local wp = frillCF * CFrame.new(0, math.cos(math.rad(a)) * 1.3, math.sin(math.rad(a)) * 1.7) -- on the leaned rim, just inside the edge
		weldTo(P("FrillScallop", BAL, 0.7, 1.05, 1.05, FRILL, wp.X, wp.Y, wp.Z), body)
	end

	-- BELLY: lighter cream-green panel low on the front
	weldTo(P("Belly", BAL, 0.5,1.3,2.2, BELLY, 1.3,-1.0,0), body)

	-- FACE: two BIG glossy eyes close together (+X front): white eyeball + dark pupil + bright glint
	-- shared PetFace (src/shared/PetFace.luau) -- this pet's proportions are the ones the whole set
	-- is now tuned to, so it looks the same as before; the numbers just live in one place now.
	PetFace.eyes{ P = P, weld = weldTo, body = body, x = 1.66, y = 0.08, white = WHITE, dark = DARK }

	-- THREE TAPERED HORNS (cream/bone). Brow horns ~1.4x the nose horn; bases sunk into the upper face / snout.
	horn("BrowHorn",  1.35, 0.75,  0.45, Vector3.new(0.45, 1.0,  0.34), 2.0, 0.40, 0.10) -- right brow: up + forward + out
	horn("BrowHorn",  1.35, 0.75, -0.45, Vector3.new(0.45, 1.0, -0.34), 2.0, 0.40, 0.10) -- left  brow
	horn("NoseHorn",  1.45,-0.10,  0.00, Vector3.new(0.62, 1.0,  0.00), 1.4, 0.50, 0.14) -- nose: shorter + thicker, up-forward

	-- BEAK: a small parrot-like beak (tan) at the front of the mouth, with a hooked tip + 2 nostril dots
	weldTo(P("BeakTop",  BAL, 0.8,0.5,0.8, BEAK, 1.68,-0.35,0), body)
	weldTo(P("BeakHook", BAL, 0.45,0.45,0.55, BEAK, 1.94,-0.53,0), body)  -- the hooked point curving down
	weldTo(P("BeakLow",  BAL, 0.55,0.36,0.62, BEAK, 1.6,-0.66,0), body)
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Nostril", BAL, 0.17,0.17,0.17, DARK, 1.94,-0.28,0.2*sgn), body) -- 2 tiny nostril dots, sunk into the beak
	end
	-- a small happy SMILE curve just below the beak
	weldTo(P("Smile", BAL, 0.35,0.22,1.15, MOUTH, 1.5,-0.95,0), body)

	-- ===== ONE SOLID =====
	-- NOTE: this pet's GEOMETRY is deliberately untouched -- every part is the same size and in
	-- the same place it has always been. Fusing changes only how those parts are RENDERED (one
	-- surface instead of many), so it stays exactly the pet that was signed off, minus the seams.
	-- Everything welded above is now fused into a single part (eyes excepted -- they blink).
	-- This is what stops the pet reading as "shapes that aren't connected" in the world: a union
	-- is ONE surface with one set of normals, so there are no part boundaries left for the
	-- world's lighting to draw a hard line across. See the long note on PetFace.fuseAll.
	PetFace.ensureRoot(m)
	body = PetFace.fuseAll(m, body, PetFace.ANIMATED)
	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the shark): build in Workspace, clear any stale
-- TriceratopsTemplate, publish a fresh clone, print the part count.
-- ============================================================================
task.spawn(function()
	local ok, model, err = pcall(buildTriceratops)
	if not (ok and model) then warn("[Trike] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Trike] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the others")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Trike] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "TriceratopsTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "TriceratopsTemplate"; tmpl.Parent = RS
	print(("[Trike] published ReplicatedStorage.TriceratopsTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))

	-- visible copy in Workspace (offset so it doesn't overlap the other pets)
	local target = CFrame.new(30, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(20, 6, -10) end
	pcall(function() model:PivotTo(target) end)

	print(("[Trike] Triceratops built: %d parts (body union %s). Visible copy in Workspace, template -> ReplicatedStorage.TriceratopsTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN (mirrors HatchRaptorSpawn): the client fires HatchTriceratopsSpawn
-- with a CFrame; the server clones the union template there + floats it.
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchTriceratopsSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("TriceratopsTemplate") or RS:WaitForChild("TriceratopsTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedTrike_" .. player.Name; pet.Parent = Workspace
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
