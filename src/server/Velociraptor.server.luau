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
	local BODY  = Color3.fromRGB(140,148,156)  -- cool grey
	local BELLY = Color3.fromRGB(238,232,212)   -- cream belly + snout underside
	local STRIPE= Color3.fromRGB(70,120,210)    -- blue stripe + eye markings + crest
	local DARK  = Color3.fromRGB(30,28,34)      -- pupils / nostrils
	local CLAW  = Color3.fromRGB(26,24,28)      -- dark claws
	local TEETH = Color3.fromRGB(248,244,230)   -- pointed teeth
	local AMBER = Color3.fromRGB(255,196,70)    -- amber iris accent
	local WHITE = Color3.fromRGB(250,250,250)

	-- BODY: UNCHANGED rounded-cube union (only the colour differs)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- FEET: 4 stubby feet, each with a raised "sickle claw" toe
	for _, fp in ipairs({ {0.95,0.78}, {0.95,-0.78}, {-0.95,0.78}, {-0.95,-0.78} }) do
		P("Foot", BLK, 0.95,0.8,0.95, BODY, fp[1],-1.55,fp[2])
		weldTo(P("SickleClaw", CYL, 0.55,0.16,0.16, CLAW, fp[1]+0.55, -1.35, fp[2], CFrame.Angles(0,0,math.rad(38))), body)
	end

	-- BELLY: pale patch low on the front
	weldTo(P("Belly", BAL, 0.45,1.0,1.9, BELLY, 1.45,-1.15,0), body)

	-- BLUE STRIPE along the TOP spine only (clean + flush). The side stripes were removed -- on the
	-- rounded cube they poked out near the curved edges and read as a random blue blob on the side.
	weldTo(P("Stripe", BLK, 3.0,0.16,0.7, STRIPE, -0.2,1.78,0), body)

	-- FACE: big flat-disc eyes low-center (+X): white eyeball + amber iris + dark pupil + glint,
	-- with a blue marking + an angled brow ridge over each eye (cute-but-fierce).
	for _, sgn in ipairs({1,-1}) do
		local zc = 0.5 * sgn
		weldTo(P("EyeMark", BAL, 0.42,0.5,0.72, STRIPE, 1.64,0.55,zc), body)                                   -- blue marking over the eye
		weldTo(P("Brow",    BLK, 0.55,0.16,0.72, DARK, 1.8,0.56,zc, CFrame.Angles(0,0,math.rad(sgn*16))), body) -- angled brow ridge
		weldTo(P("whitepartofeye", CYL, 0.20, 0.82, 0.82, WHITE, 1.70, 0.18, zc), body)                         -- white eyeball (flat disc)
		weldTo(P("EyeAmber",       CYL, 0.22, 0.60, 0.60, AMBER, 1.74, 0.16, zc), body)                         -- amber iris ring
		weldTo(P("blackpartofeye", CYL, 0.26, 0.40, 0.40, DARK,  1.78, 0.15, zc), body)                         -- dark pupil, proud
		weldTo(P("Glint",          CYL, 0.12, 0.18, 0.18, WHITE, 1.92, 0.32, zc + 0.12), body)                  -- bright glint
	end

	-- SNOUT: a longer, narrower muzzle pushing forward (+X) -- grey top, cream underside
	weldTo(P("Snout",      BAL, 1.5,0.7,0.85, BODY,  2.3,-0.22,0), body)
	weldTo(P("SnoutUnder", BAL, 1.25,0.4,0.7, BELLY, 2.3,-0.5,0), body)
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 2.98,-0.08, 0.18), body)
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 2.98,-0.08,-0.18), body)
	-- small head crest / brow ridge between the eyes
	weldTo(P("Crest", BLK, 0.55,0.24,0.55, STRIPE, 1.5,0.98,0, CFrame.Angles(0,0,math.rad(22))), body)
	-- open mouth + tiny pointed teeth (upper + lower rows)
	weldTo(P("MouthOpen", BAL, 0.95,0.32,0.62, Color3.fromRGB(60,34,40), 2.55,-0.5,0), body)
	for _, tz in ipairs({ -0.26, -0.09, 0.09, 0.26 }) do
		weldTo(P("Tooth", CYL, 0.22,0.1,0.1, TEETH, 2.82,-0.4, tz, CFrame.Angles(0,0,math.rad(90))), body)  -- upper
		weldTo(P("Tooth", CYL, 0.18,0.09,0.09, TEETH, 2.78,-0.6, tz, CFrame.Angles(0,0,math.rad(90))), body) -- lower
	end

	-- ARMS: 2 small NEAT arms tucked flat against the front sides with tiny clawed hands (grey, kept tight)
	for _, sgn in ipairs({1,-1}) do
		weldTo(P("Arm",  BLK, 0.26,0.6,0.26, BODY, 1.35,-0.45,1.05*sgn, CFrame.Angles(math.rad(18),0,0)), body)
		weldTo(P("Hand", BAL, 0.3,0.28,0.28, BODY, 1.55,-0.8,1.08*sgn), body)
		for _, cz in ipairs({ -0.1, 0, 0.1 }) do
			weldTo(P("Claw", CYL, 0.24,0.06,0.06, CLAW, 1.78,-0.84,1.08*sgn + cz, CFrame.Angles(0,math.rad(90),0)), body)
		end
	end

	-- TAIL: a long tapering tail off the BACK (-X), held straight, no spikes; blue stripe continues onto it
	weldTo(P("Tail", BAL, 1.3,1.1,1.1,  BODY, -1.9,0.0,0), body)
	weldTo(P("Tail", BAL, 1.0,0.8,0.8,  BODY, -2.8,0.14,0), body)
	weldTo(P("Tail", BAL, 0.7,0.55,0.55, BODY, -3.6,0.26,0), body)
	weldTo(P("TailTip", BAL, 0.46,0.38,0.38, BODY, -4.25,0.36,0), body)
	weldTo(P("Stripe", BLK, 2.6,0.14,0.5, STRIPE, -2.9,0.62,0), body)

	return m, err
end

-- ============================================================================
-- BUILD + PUBLISH (mirrors the stego): build in Workspace, clear any stale
-- VelociraptorTemplate, publish a fresh clone, print the part count.
-- ============================================================================
task.spawn(function()
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
