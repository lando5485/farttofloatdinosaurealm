--======================================================================
-- Shark.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A SHARK / MEGALODON pet on the EXACT same pipeline as the Stegosaurus +
-- Velociraptor pets: same rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), same
-- flat-disc face (whitepartofeye/blackpartofeye/Glint), same 4 stubby feet/fins,
-- same matte/smooth, same publish (destroy old SharkTemplate -> fresh clone).
-- FEATURES: big rounded DORSAL fin, wide toothy happy SMILE, 2 pectoral fins,
-- a forked TAIL (taller top lobe), gill lines. Blue-grey body, cream belly.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
-- shared chunky body dims (IDENTICAL to the stego/raptor) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- SHARK -- same rounded-cube body + flat-disc face + 4 feet as the raptor;
-- raptor snout/arms/tail removed; shark dorsal/smile/pectorals/tail/gills added.
-- ============================================================================
local function buildShark()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Shark"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	local function W(n,sx,sy,sz,c,x,y,z,r) -- scaled WedgePart (triangular teeth)
		local p = Instance.new("WedgePart"); p.Name = n; p.Size = Vector3.new(sx*s,sy*s,sz*s); p.Color = c
		local cf = CFrame.new(x*s,y*s,z*s); if r then cf = cf*r end; p.CFrame = cf; flagPart(p); p.Parent = m; return p
	end
	newRoot(m)
	-- shark/megalodon palette
	local BODY  = Color3.fromRGB(110,130,150)  -- classic shark blue-grey
	local BELLY = Color3.fromRGB(236,230,208)   -- cream/white belly + chin
	local FIN   = Color3.fromRGB(84,100,120)    -- slightly darker grey fins
	local DARK  = Color3.fromRGB(28,26,32)      -- pupils / gills
	local MOUTH = Color3.fromRGB(70,40,46)       -- dark mouth interior
	local TEETH = Color3.fromRGB(250,250,246)    -- white teeth
	local WHITE = Color3.fromRGB(250,250,250)

	-- BODY: UNCHANGED rounded-cube union (only the colour differs)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- FEET: 4 stubby feet/fins (same as the raptor)
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		weldTo(P("Foot", BLK, 0.95,0.8,0.95, FIN, fp[1],-1.55,fp[2]), body)
	end

	-- BELLY + CHIN: pale cream patch low on the front
	weldTo(P("Belly", BAL, 0.5,1.2,2.1, BELLY, 1.35,-1.05,0), body)

	-- FACE: big flat-disc eyes low-center (+X): white eyeball + dark pupil + glint (same as the others)
	for _, sgn in ipairs({1,-1}) do
		local zc = 0.6 * sgn
		weldTo(P("whitepartofeye", CYL, 0.20, 0.98, 0.98, WHITE, 1.66, 0.42, zc), body) -- big flat white eye
		weldTo(P("blackpartofeye", CYL, 0.26, 0.52, 0.52, DARK,  1.74, 0.40, zc), body) -- big dark pupil
		weldTo(P("Glint",          CYL, 0.12, 0.22, 0.22, WHITE, 1.90, 0.58, zc + 0.12), body) -- bright glint
	end

	-- SMILE: a wide happy open mouth on the front face, with a row of small white triangular teeth (top + bottom)
	weldTo(P("Mouth", BAL, 0.7,0.7,2.1, MOUTH, 1.45,-0.5,0), body)
	weldTo(P("Chin",  BAL, 0.7,0.55,1.7, BELLY, 1.3,-0.98,0), body)
	for _, tz in ipairs({ -0.8, -0.4, 0, 0.4, 0.8 }) do
		weldTo(W("Tooth", 0.16, 0.30, 0.26, TEETH, 1.9, -0.24, tz, CFrame.Angles(math.rad(180),0,0)), body) -- upper (point down)
		weldTo(W("Tooth", 0.16, 0.26, 0.24, TEETH, 1.9, -0.78, tz), body)                                   -- lower (point up)
	end

	-- DORSAL FIN: the classic big shark triangle standing up on top, slightly rounded (flattened ball), leaning back
	weldTo(P("Dorsal", BAL, 1.7,2.7,0.5, FIN, -0.1,1.4,0, CFrame.Angles(0,0,math.rad(-16))), body)

	-- PECTORAL FINS: 2 fins sticking out the lower sides, angled out + back
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Pectoral", BAL, 1.4,0.4,1.6, FIN, 0.3,-0.95,1.35*sgn, CFrame.Angles(math.rad(22*sgn),0,math.rad(8))), body)
	end

	-- TAIL: a vertical forked tail off the BACK (-X) -- taller TOP lobe + shorter bottom lobe
	weldTo(P("TailBase", BAL, 1.3,1.0,0.8, BODY, -1.5,0.1,0), body)                                       -- embeds into the body
	weldTo(P("TailTop",  BAL, 0.5,1.9,1.0, FIN, -2.05,0.85,0, CFrame.Angles(0,0,math.rad(20))), body)     -- tall top lobe (overlaps base)
	weldTo(P("TailBot",  BAL, 0.5,1.15,0.85, FIN, -2.0,-0.55,0, CFrame.Angles(0,0,math.rad(-12))), body)  -- shorter bottom lobe

	-- GILL LINES: 3 thin dark slits on each side
	for _, sgn in ipairs({1,-1}) do
		for _, gx in ipairs({ 0.7, 0.35, 0.0 }) do
			weldTo(P("Gill", BLK, 0.1,0.95,0.14, DARK, gx,0.05,1.42*sgn, CFrame.Angles(0,0,math.rad(10))), body)
		end
	end

	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the raptor): build in Workspace, clear any stale
-- SharkTemplate, publish a fresh clone, print the part count.
-- ============================================================================
task.spawn(function()
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
