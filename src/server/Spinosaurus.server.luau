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
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end)
		u.Parent = model
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

	-- BODY: UNCHANGED rounded-cube union (only the colour differs)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- SAIL: the signature -- a big rounded fan on top (+Y) running front->back (X), thin side-to-side (Z),
	-- base sunk into the back. Built FIRST so the head sits in front of it.
	weldTo(P("Sail", BAL, 3.4, 2.8, 0.5, SAIL, -0.1, 1.7, 0), body)
	for _, sx0 in ipairs({ -1.15, -0.45, 0.3, 1.05 }) do -- darker spine ridges across the sail
		weldTo(P("Spine", CYL, 2.5, 0.16, 0.16, SAILDK, sx0, 1.55, 0.2, CFrame.Angles(0,0,math.rad(90))), body)
	end

	-- FEET: 4 stubby feet
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		weldTo(P("Foot", BLK, 0.95,0.85,0.95, BODY, fp[1],-1.55,fp[2]), body)
	end

	-- BELLY: pale patch low on the front
	weldTo(P("Belly", BAL, 0.5,1.2,2.1, BELLY, 1.3,-1.05,0), body)

	-- FACE: big flat-disc eyes (+X front), set a bit high above the long snout
	for _, sgn in ipairs({1,-1}) do
		local zc = 0.55 * sgn
		weldTo(P("whitepartofeye", CYL, 0.20, 0.86, 0.86, WHITE, 1.66, 0.62, zc), body)
		weldTo(P("blackpartofeye", CYL, 0.26, 0.46, 0.46, DARK,  1.74, 0.60, zc), body)
		weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 1.90, 0.76, zc + 0.12), body)
	end

	-- SNOUT: a long crocodile-like snout jutting from the front (+X), upper + lower jaw, with teeth
	weldTo(P("SnoutBase", BLK, 0.9,1.1,1.3, BODY, 1.65,-0.15,0), body)         -- connects face -> snout
	weldTo(P("SnoutTop",  BLK, 2.2,0.62,1.0, BODY, 2.75,0.0,0), body)          -- upper jaw
	weldTo(P("SnoutBot",  BLK, 2.0,0.42,0.9, BELLY, 2.65,-0.48,0), body)       -- lower jaw
	weldTo(P("Mouth",     BLK, 1.9,0.18,0.85, MOUTH, 2.65,-0.26,0), body)      -- dark mouth line
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Nostril", BAL, 0.2,0.2,0.2, DARK, 2.45,0.3,0.22*sgn), body)  -- nostril bumps on top
		for _, tx in ipairs({ 2.1, 2.7, 3.3 }) do                              -- small teeth along each jaw
			weldTo(P("Tooth", BAL, 0.18,0.34,0.18, TEETH, tx, -0.26, 0.42*sgn), body)
		end
	end

	-- ARMS: little forelimbs at the front-lower sides
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Arm", BAL, 0.5,1.0,0.5, BODY, 1.15,-0.85,1.25*sgn, CFrame.Angles(0,0,math.rad(-12*sgn))), body)
		weldTo(P("Claw", BAL, 0.26,0.4,0.26, DARK, 1.35,-1.45,1.35*sgn), body)
	end

	-- TAIL: a tapered tail off the BACK (-X)
	weldTo(P("Tail",    BAL, 1.6,0.95,1.0, BODY, -2.0,-0.1,0), body)
	weldTo(P("TailTip", BAL, 1.3,0.62,0.7, BODY, -2.95,0.02,0), body)

	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the others)
-- ============================================================================
task.spawn(function()
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
