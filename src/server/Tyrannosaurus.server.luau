--======================================================================
-- Tyrannosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- A T-REX pet (island8 "Volcanic Vista" reward) on the EXACT same pipeline as
-- the other pets: rounded-cube BodyUnion (PSW/PSH/PSD/PSR/PSS), flat-disc eyes
-- (whitepartofeye/blackpartofeye/Glint), 4 stubby feet, matte/smooth, same publish.
-- FEATURES: a BIG toothy head + jaws, the signature tiny arms, brow ridges,
-- and a long heavy tail. Earthy red-brown body (volcanic), tan belly, white teeth.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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

local function buildTyrannosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Tyrannosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	local function W(n,sx,sy,sz,c,x,y,z,r) -- scaled WedgePart for triangular teeth
		local p = Instance.new("WedgePart"); p.Name=n; p.Size=Vector3.new(sx*s,sy*s,sz*s); p.Color=c
		local cf=CFrame.new(x*s,y*s,z*s); if r then cf=cf*r end; p.CFrame=cf; flagPart(p); p.Parent=m; return p
	end
	newRoot(m)
	local BODY  = Color3.fromRGB(122,78,62)    -- earthy red-brown (volcanic)
	local BELLY = Color3.fromRGB(202,182,150)   -- tan belly / lower jaw
	local TEETH = Color3.fromRGB(248,246,236)
	local DARK  = Color3.fromRGB(30,26,24)      -- pupils / claws / nostrils / brow
	local MOUTH = Color3.fromRGB(58,30,28)
	local WHITE = Color3.fromRGB(250,250,250)

	-- BODY
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- BIG ROUNDED HEAD jutting from the front (+X) -- T-Rex signature, kept cute/rounded like the other pets
	weldTo(P("HeadBase", BAL, 1.5,1.95,2.1, BODY, 1.5,0.5,0), body)        -- rounded head joining the body
	weldTo(P("Snout", BAL, 1.9,1.15,1.7, BODY, 2.8,0.2,0), body)          -- rounded upper muzzle
	weldTo(P("Jaw",   BAL, 1.6,0.75,1.55, BELLY, 2.7,-0.6,0), body)       -- rounded lower jaw
	weldTo(P("Mouth", BAL, 1.6,0.32,1.4, MOUTH, 2.78,-0.15,0), body)      -- dark mouth
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Nostril", BAL, 0.2,0.2,0.2, DARK, 3.5,0.42,0.22*sgn), body) -- nostrils on the snout tip
		for _, tx in ipairs({ 2.4, 3.0, 3.5 }) do                             -- triangular teeth, clean rows
			weldTo(W("Tooth", 0.42,0.3,0.2, TEETH, tx, 0.0, 0.6*sgn, CFrame.Angles(math.rad(180),0,0)), body) -- upper (point down)
			weldTo(W("Tooth", 0.38,0.26,0.18, TEETH, tx, -0.36, 0.56*sgn), body)                              -- lower (point up)
		end
	end

	-- FACE: big flat-disc eyes high + forward on the head, with soft rounded brows
	for _, sgn in ipairs({1,-1}) do
		local zc = 0.68 * sgn
		weldTo(P("Brow", BAL, 0.7,0.5,0.85, BODY, 2.15,1.32,zc), body)                 -- rounded brow bump
		weldTo(P("whitepartofeye", CYL, 0.20, 0.82, 0.82, WHITE, 2.3, 0.98, zc), body)
		weldTo(P("blackpartofeye", CYL, 0.26, 0.46, 0.46, DARK,  2.38, 0.96, zc), body)
		weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 2.52, 1.12, zc + 0.1), body)
	end

	-- TINY ARMS (the famous little T-Rex arms) at the front-lower sides
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Arm", BAL, 0.42,0.85,0.42, BODY, 1.2,-0.35,1.3*sgn, CFrame.Angles(0,0,math.rad(-14*sgn))), body)
		weldTo(P("Claw", BAL, 0.22,0.34,0.22, DARK, 1.4,-0.95,1.4*sgn), body)
	end

	-- FEET: 4 stubby feet
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		weldTo(P("Foot", BLK, 1.0,0.85,1.0, BODY, fp[1],-1.55,fp[2]), body)
	end

	-- BELLY
	weldTo(P("Belly", BAL, 0.5,1.3,2.1, BELLY, 1.3,-1.05,0), body)

	-- LONG HEAVY TAIL off the BACK (-X), tapering
	weldTo(P("Tail",    BAL, 1.8,1.1,1.2, BODY, -2.0,-0.05,0), body)
	weldTo(P("TailMid", BAL, 1.4,0.85,0.9, BODY, -3.0,0.05,0), body)
	weldTo(P("TailTip", BAL, 1.1,0.58,0.6, BODY, -3.85,0.12,0), body)

	return m, err
end

task.spawn(function()
	local ok, model, err = pcall(buildTyrannosaurus)
	if not (ok and model) then warn("[TRex] build error: " .. tostring(model or err)); return end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[TRex] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89"):format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[TRex] BodyUnion not found -- CSG union failed")
	end
	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "TyrannosaurusTemplate" then c:Destroy(); removed += 1 end end
	local tmpl = model:Clone(); tmpl.Name = "TyrannosaurusTemplate"; tmpl.Parent = RS
	print(("[TRex] published ReplicatedStorage.TyrannosaurusTemplate (%d parts), cleared %d stale"):format(n, removed))
	local target = CFrame.new(50, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(20, 6, 20) end
	pcall(function() model:PivotTo(target) end)
	print(("[TRex] T-Rex built: %d parts (body union %s). Template -> ReplicatedStorage.TyrannosaurusTemplate"):format(n, err and "FAILED" or "ok"))
end)

-- HATCH SPAWN (mirrors the others)
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
			pcall(function() pet:PivotTo(hover * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end); task.wait()
		end
		local t = 0
		while pet.Parent do t = t + 0.05
			pcall(function() pet:PivotTo(hover * CFrame.new(0, 1.5 + math.sin(t*2)*0.4, 0) * CFrame.Angles(0, t*0.6, 0)) end); task.wait(0.05)
		end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	if activePets[p] then pcall(function() activePets[p]:Destroy() end); activePets[p] = nil end
end)
