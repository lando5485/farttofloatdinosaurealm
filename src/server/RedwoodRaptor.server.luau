--======================================================================
-- RedwoodRaptor.server.luau  (server Script)
--======================================================================
-- Island6 ("Redwood Ridge") raptor hunt:
--   * RaptorSpot -> a big BLOCKY MAMA RAPTOR (organic dino model, NOT the cube pet) wanders
--     near the spot. Get too close and she charges + STEALS fart power (CurrentPower).
--   * SniperSpot -> a big SNIPER LOCKER; grab a sniper Tool.
--   * Shoot the mama 4 times -> she tips over, fades, and a RAPTOR EGG rises.
--   * Hatch the egg -> the Velociraptor PET (the cube pet template), follower + Pet Hub.
--======================================================================

local RS            = game:GetService("ReplicatedStorage")
local Workspace     = game:GetService("Workspace")
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TS            = game:GetService("TweenService")
local ServerStorage     = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
-- wait for IslandLayout to space the islands first, so the mama raptor lands at the NEW island6 position
do local t0 = os.clock(); while not _G.islandsPositioned and os.clock() - t0 < 5 do task.wait() end end

-- FULL inspector: dumps EVERY instance inside a model (class, size, attachment/value positions, mesh,
-- CollectionService tags, attributes, joints) so we can see exactly what's available to move/animate.
local function inspectModel(model)
	print("===== [Inspect] FULL DUMP: " .. model:GetFullName() .. " =====")
	local function line(d, depth)
		local extra = ""
		if d:IsA("BasePart") then extra = (" size=(%.2f,%.2f,%.2f)"):format(d.Size.X, d.Size.Y, d.Size.Z) end
		if d:IsA("Attachment") then local p = d.Position; extra = (" pos=(%.2f,%.2f,%.2f)"):format(p.X, p.Y, p.Z) end
		if d:IsA("Motor6D") then extra = (" %s -> %s"):format(d.Part0 and d.Part0.Name or "?", d.Part1 and d.Part1.Name or "?") end
		if d:IsA("ValueBase") then extra = " value=" .. tostring((d :: any).Value) end
		if d:IsA("SpecialMesh") then extra = " meshId=" .. tostring(d.MeshId) end
		if d:IsA("MeshPart") then extra = extra .. " meshId=" .. tostring(d.MeshId) end
		local tags = CollectionService:GetTags(d)
		local tagstr = (#tags > 0) and (" tags=[" .. table.concat(tags, ",") .. "]") or ""
		local astr = ""
		for k, v in pairs(d:GetAttributes()) do astr = astr .. (" @%s=%s"):format(k, tostring(v)) end
		print(("[Inspect]%s%s (%s)%s%s%s"):format(string.rep("  ", depth), d.Name, d.ClassName, extra, tagstr, astr))
	end
	local function recurse(parent, depth)
		for _, c in ipairs(parent:GetChildren()) do line(c, depth); recurse(c, depth + 1) end
	end
	line(model, 0); recurse(model, 1)
	print("===== [Inspect] end =====")
end

local function ev(name)
	local e = RS:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end
	return e
end
local RaptorShot   = ev("RaptorShot")
local RedwoodHatch = ev("RedwoodRaptorHatch")

local MAX_HITS, DETECT, STEAL_DIST, STEAL_CD, STEAL_AMT = 4, 24, 7, 2.5, 8
local WANDER_R, CHASE_R, WANDER_SPD, CHASE_SPD = 32, 55, 6, 12 -- bigger roam area

-- ========================= MAMA RAPTOR model (blocky / structured, dino1-style) =========================
local function buildMamaRaptor()
	local BODY, BODY2 = Color3.fromRGB(96, 120, 70), Color3.fromRGB(82, 104, 58)
	local BELLY, DARK = Color3.fromRGB(202, 206, 172), Color3.fromRGB(40, 44, 34)
	local CLAW, TEETH = Color3.fromRGB(28, 26, 24), Color3.fromRGB(240, 235, 215)
	local EYE, STRIPE = Color3.fromRGB(235, 185, 60), Color3.fromRGB(60, 76, 44)
	local BLK, BALL = Enum.PartType.Block, Enum.PartType.Ball
	local m = Instance.new("Model"); m.Name = "MamaRaptor"
	local function mk(name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
		p.Material = Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false; p.CanQuery = true; p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end; p.CFrame = cf; p.Parent = m; return p
	end
	local root = mk("Root", BALL, 0.4, 0.4, 0.4, BODY, 0, 0, 0); root.Transparency = 1; m.PrimaryPart = root
	-- TORSO (blocks, leaning forward)
	mk("Body",  BLK, 4.4, 2.3, 2.2, BODY,  0.5, 0.4, 0, CFrame.Angles(0, 0, math.rad(-6)))
	mk("Chest", BLK, 1.9, 2.0, 2.0, BODY,  2.1, 0.95, 0, CFrame.Angles(0, 0, math.rad(-16)))
	mk("Hip",   BLK, 2.2, 2.2, 2.1, BODY, -1.4, 0.3, 0, CFrame.Angles(0, 0, math.rad(4)))
	mk("Belly", BLK, 3.2, 1.0, 1.8, BELLY, 0.7, -0.7, 0)
	-- NECK
	mk("Neck",  BLK, 1.2, 2.2, 1.1, BODY, 2.7, 1.55, 0, CFrame.Angles(0, 0, math.rad(42)))
	-- HEAD
	local hx, hy = 4.5, 2.9
	mk("Head",  BLK, 1.7, 1.25, 1.05, BODY, hx, hy, 0, CFrame.Angles(0, 0, math.rad(-6)))
	mk("Snout", BLK, 1.8, 0.7, 0.85, BODY, hx + 1.4, hy - 0.22, 0)
	mk("Jaw",   BLK, 1.6, 0.4, 0.78, BELLY, hx + 1.35, hy - 0.64, 0)
	for _, tz in ipairs({ -0.26, 0, 0.26 }) do mk("Tooth", BLK, 0.42, 0.22, 0.1, TEETH, hx + 1.95, hy - 0.44, tz) end
	mk("Nostril", BALL, 0.14, 0.14, 0.14, DARK, hx + 2.2, hy - 0.02, 0.22)
	mk("Nostril", BALL, 0.14, 0.14, 0.14, DARK, hx + 2.2, hy - 0.02, -0.22)
	for _, sgn in ipairs({ 1, -1 }) do
		mk("whitepartofeye", BLK, 0.5, 0.5, 0.12, Color3.fromRGB(250, 250, 250), hx + 0.45, hy + 0.35, 0.55 * sgn)
		mk("Iris",  BLK, 0.38, 0.38, 0.1, EYE,  hx + 0.5, hy + 0.36, 0.6 * sgn)
		mk("Pupil", BLK, 0.18, 0.28, 0.1, DARK, hx + 0.55, hy + 0.37, 0.63 * sgn)
		mk("Brow",  BLK, 0.85, 0.22, 0.5, DARK, hx + 0.35, hy + 0.74, 0.5 * sgn, CFrame.Angles(0, 0, math.rad(sgn * -12)))
	end
	mk("Crest", BLK, 0.5, 0.6, 0.2, STRIPE, hx - 0.3, hy + 0.98, 0, CFrame.Angles(0, 0, math.rad(12)))
	-- TAIL (tapering blocks, angling up)
	mk("Tail",  BLK, 2.3, 1.5, 1.6, BODY, -2.7, 0.5, 0, CFrame.Angles(0, 0, math.rad(7)))
	mk("Tail2", BLK, 1.9, 1.0, 1.1, BODY, -4.2, 0.85, 0, CFrame.Angles(0, 0, math.rad(11)))
	mk("Tail3", BLK, 1.4, 0.62, 0.7, BODY, -5.5, 1.2, 0, CFrame.Angles(0, 0, math.rad(15)))
	mk("Tail4", BLK, 0.8, 0.4, 0.42, BODY, -6.4, 1.45, 0)
	-- LEGS x2 (blocky raptor stance)
	for _, sgn in ipairs({ 1, -1 }) do
		local z = 1.0 * sgn
		mk("Thigh", BLK, 1.3, 2.1, 1.2, BODY2, -0.5, -0.9, z, CFrame.Angles(0, 0, math.rad(14)))
		mk("Shin",  BLK, 0.85, 2.0, 0.85, BODY2, 0.2, -2.5, z, CFrame.Angles(0, 0, math.rad(-32)))
		mk("Foot",  BLK, 1.6, 0.42, 0.9, DARK, 1.0, -3.6, z)
		for _, cz in ipairs({ -0.28, 0, 0.28 }) do mk("ToeClaw", BLK, 0.46, 0.22, 0.16, CLAW, 1.85, -3.65, z + cz) end
		mk("Sickle", BLK, 0.6, 0.2, 0.16, CLAW, 1.25, -3.15, z, CFrame.Angles(0, 0, math.rad(40)))
	end
	-- ARMS x2 (small blocky)
	for _, sgn in ipairs({ 1, -1 }) do
		local z = 1.15 * sgn
		mk("Arm",  BLK, 0.4, 1.1, 0.4, BODY2, 2.4, -0.3, z, CFrame.Angles(0, 0, math.rad(52)))
		mk("Hand", BLK, 0.42, 0.42, 0.42, BODY2, 2.85, -1.0, z)
		for _, cz in ipairs({ -0.12, 0.12 }) do mk("Claw", BLK, 0.3, 0.12, 0.1, CLAW, 3.1, -1.05, z + cz) end
	end
	-- back RIDGE plates (stripe colour)
	for _, sx in ipairs({ 1.6, 0.6, -0.4, -1.4, -2.4 }) do mk("Ridge", BLK, 0.5, 0.6, 1.6, STRIPE, sx, 1.6, 0, CFrame.Angles(0, 0, math.rad(8))) end
	return m
end

-- FREEZE the RaptorModel immediately at server start so an unanchored top-heavy rig can't fall/tip
-- before the setup runs (that physics tumble is what made it spawn flipped).
do
	local rm = Workspace:FindFirstChild("RaptorModel", true) or ServerStorage:FindFirstChild("RaptorModel", true) or RS:FindFirstChild("RaptorModel", true)
	if rm then for _, d in ipairs(rm:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end end
end

task.spawn(function()
	local island6 = Workspace:WaitForChild("island6", 90)
	if not island6 then warn("[Redwood] island6 not found -- raptor hunt skipped"); return end

	local function findPart(name)
		for _, d in ipairs(island6:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then return d end
		end
	end
	local raptorSpot = findPart("RaptorSpot")
	local sniperSpot = findPart("SniperSpot")
	if not raptorSpot then warn("[Redwood] 'RaptorSpot' not found in island6") end
	if not sniperSpot then warn("[Redwood] 'SniperSpot' not found in island6") end
	for _, p in ipairs({ raptorSpot, sniperSpot }) do
		if p then p.Transparency = 1; p.CanCollide = false; p.CanQuery = false end
	end

	local REF_Y = (raptorSpot and raptorSpot.Position.Y) or (sniperSpot and sniperSpot.Position.Y) or 50
	local ignoreForGround = {}
	-- exclude the mama/egg/locker AND every player character, so the ray always finds the real floor
	-- (a player standing in the mama's space must NOT count as ground, or she snaps + vanishes into the map)
	local function buildIgnore()
		local filt = table.clone(ignoreForGround)
		for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then filt[#filt + 1] = plr.Character end end
		return filt
	end
	-- returns the floor Y, or NIL if the ray missed. `fromY` = where to start the down-ray (default high);
	-- for wandering we start it just above the current foot level + short range, so it finds the FLOOR
	-- below and never snaps onto a tree canopy high overhead (Redwood Ridge = tall trees).
	local function groundY(x, z, fromY, dist)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = buildIgnore()
		local hit = Workspace:Raycast(Vector3.new(x, fromY or (REF_Y + 120), z), Vector3.new(0, -(dist or 400), 0), rp)
		return hit and hit.Position.Y or nil
	end

	local function floaty(hrp, text, color)
		local p = Instance.new("Part"); p.Size = Vector3.new(0.2, 0.2, 0.2); p.Transparency = 1; p.Anchored = true; p.CanCollide = false
		p.CFrame = hrp.CFrame * CFrame.new(0, 3, 0); p.Parent = Workspace
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(190, 44); bb.AlwaysOnTop = true; bb.Adornee = p; bb.Parent = p
		local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne
		l.TextScaled = true; l.TextColor3 = color or Color3.fromRGB(255, 110, 110); l.TextStrokeTransparency = 0; l.Text = text; l.Parent = bb
		TS:Create(p, TweenInfo.new(1.2), { CFrame = p.CFrame * CFrame.new(0, 3, 0) }):Play()
		task.delay(1.3, function() pcall(function() p:Destroy() end) end)
	end

	-- ===== RAPTOR EGG -> Hatch -> the PET =====
	local function spawnEgg(atX, atZ)
		local gy = groundY(atX, atZ, REF_Y + 120, 400) or REF_Y
		local egg = Instance.new("Model"); egg.Name = "RaptorEgg"; egg.Parent = Workspace
		ignoreForGround[#ignoreForGround + 1] = egg
		local shell = Instance.new("Part"); shell.Name = "Shell"; shell.Shape = Enum.PartType.Ball; shell.Size = Vector3.new(3, 4, 3)
		shell.Color = Color3.fromRGB(224, 194, 148); shell.Material = Enum.Material.SmoothPlastic; shell.Anchored = true; shell.CanCollide = false; shell.Parent = egg; egg.PrimaryPart = shell
		for i = 1, 6 do
			local a = (i - 1) * (math.pi / 3)
			local s = Instance.new("Part"); s.Name = "Speck"; s.Shape = Enum.PartType.Ball; s.Size = Vector3.new(0.55, 0.55, 0.55)
			s.Color = Color3.fromRGB(176, 118, 64); s.Anchored = true; s.CanCollide = false; s.Parent = egg
			s.CFrame = CFrame.new(atX + math.sin(a) * 1.05, gy + 2 + (i % 2 == 0 and 0.6 or -0.6), atZ + math.cos(a) * 1.05)
		end
		local restCF = CFrame.new(atX, gy + 2.2, atZ)
		egg:PivotTo(restCF * CFrame.new(0, -3.2, 0))
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(235, 205, 150); hl.FillTransparency = 0.5; hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = egg; hl.Parent = egg -- occluded so it doesn't glow through from other islands
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 1.2 and egg.Parent do local p = (os.clock() - t0) / 1.2; pcall(function() egg:PivotTo(restCF * CFrame.new(0, -3.2 + 3.2 * p, 0)) end); task.wait() end
			local t = 0
			while egg.Parent do t += 0.05; pcall(function() egg:PivotTo(restCF * CFrame.new(0, math.sin(t * 2) * 0.25, 0)) end); task.wait(0.05) end
		end)
		local prompt = Instance.new("ProximityPrompt"); prompt.ActionText = "Hatch"; prompt.ObjectText = "Raptor Egg"; prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 14; prompt.RequiresLineOfSight = false; prompt.Parent = shell
		prompt.Triggered:Connect(function(plr)
			prompt.Enabled = false
			RedwoodHatch:FireClient(plr, restCF)
			task.delay(1.4, function() if egg.Parent then egg:Destroy() end end)
		end)
		print("[Redwood] Mama down -> Raptor Egg rose. Hatch it!")
	end

	-- ===== SNIPER TOOL (low-poly but rifle-proportioned: long thin barrel, scope, stock, grip, bipod) =====
	local function buildSniperTool()
		local GM    = Color3.fromRGB(40, 42, 48)   -- gunmetal body
		local MT    = Color3.fromRGB(86, 90, 98)   -- steel barrel
		local FURN  = Color3.fromRGB(74, 80, 56)   -- olive stock/grip
		local GLASS = Color3.fromRGB(120, 180, 210)
		local tool = Instance.new("Tool"); tool.Name = "Sniper"; tool.RequiresHandle = true; tool.CanBeDropped = false
		tool.ToolTip = "Hold RIGHT-CLICK to scope, LEFT-CLICK to shoot (4 hits)"
		-- Handle = the slim receiver (barrel runs along +X)
		local handle = Instance.new("Part"); handle.Name = "Handle"; handle.Size = Vector3.new(2.2, 0.3, 0.22)
		handle.Color = GM; handle.Material = Enum.Material.Metal; handle.CanCollide = false; handle.Massless = true; handle.Anchored = false; handle.Parent = tool
		local function part(name, shape, size, color, mat, cf)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.Metal
			p.CanCollide = false; p.Massless = true; p.Anchored = false; p.CFrame = cf; p.Parent = tool
			local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
			return p
		end
		-- BARREL: long + thin
		part("Barrel",     Enum.PartType.Cylinder, Vector3.new(3.3, 0.12, 0.12), MT, Enum.Material.Metal, CFrame.new(2.45, 0.02, 0))
		part("Handguard",  Enum.PartType.Block,    Vector3.new(1.3, 0.24, 0.26), GM, Enum.Material.Metal, CFrame.new(1.5, 0.02, 0))
		part("Muzzle",     Enum.PartType.Cylinder, Vector3.new(0.5, 0.16, 0.16), GM, Enum.Material.Metal, CFrame.new(4.15, 0.02, 0))
		part("FrontSight", Enum.PartType.Block,    Vector3.new(0.1, 0.22, 0.1),  GM, Enum.Material.Metal, CFrame.new(3.5, 0.18, 0))
		-- SCOPE on top
		part("ScopeMnt", Enum.PartType.Block,    Vector3.new(0.16, 0.2, 0.14), GM, Enum.Material.Metal, CFrame.new(-0.1, 0.28, 0))
		part("ScopeMnt", Enum.PartType.Block,    Vector3.new(0.16, 0.2, 0.14), GM, Enum.Material.Metal, CFrame.new(0.8, 0.28, 0))
		part("ScopeTube",  Enum.PartType.Cylinder, Vector3.new(1.9, 0.15, 0.15), GM, Enum.Material.Metal, CFrame.new(0.35, 0.46, 0))
		part("ScopeBell",  Enum.PartType.Cylinder, Vector3.new(0.2, 0.24, 0.24), GM, Enum.Material.Metal, CFrame.new(1.3, 0.46, 0))   -- front objective
		part("ScopeEye",   Enum.PartType.Cylinder, Vector3.new(0.18, 0.21, 0.21), GM, Enum.Material.Metal, CFrame.new(-0.62, 0.46, 0)) -- eyepiece
		local lens = part("Lens", Enum.PartType.Cylinder, Vector3.new(0.06, 0.2, 0.2), GLASS, Enum.Material.Glass, CFrame.new(1.42, 0.46, 0)); lens.Transparency = 0.3; lens.Reflectance = 0.2
		part("Turret",     Enum.PartType.Block,    Vector3.new(0.14, 0.16, 0.14), GM, Enum.Material.Metal, CFrame.new(0.35, 0.62, 0))
		-- STOCK (back), cheek rest, butt pad
		part("Stock",  Enum.PartType.Block, Vector3.new(1.5, 0.42, 0.2), FURN, Enum.Material.SmoothPlastic, CFrame.new(-1.7, -0.16, 0) * CFrame.Angles(0, 0, math.rad(-6)))
		part("Cheek",  Enum.PartType.Block, Vector3.new(1.0, 0.16, 0.2), FURN, Enum.Material.SmoothPlastic, CFrame.new(-1.6, 0.12, 0))
		part("Butt",   Enum.PartType.Block, Vector3.new(0.18, 0.62, 0.22), GM,  Enum.Material.Metal, CFrame.new(-2.45, -0.26, 0) * CFrame.Angles(0, 0, math.rad(-6)))
		-- PISTOL GRIP + trigger
		part("PGrip",     Enum.PartType.Block, Vector3.new(0.26, 0.72, 0.22), FURN, Enum.Material.SmoothPlastic, CFrame.new(-0.45, -0.5, 0) * CFrame.Angles(0, 0, math.rad(20)))
		part("TrigGuard", Enum.PartType.Block, Vector3.new(0.5, 0.1, 0.14),  GM,   Enum.Material.Metal, CFrame.new(-0.12, -0.42, 0))
		part("Trigger",   Enum.PartType.Block, Vector3.new(0.08, 0.2, 0.08), GM,   Enum.Material.Metal, CFrame.new(-0.16, -0.32, 0))
		-- MAGAZINE
		part("Mag", Enum.PartType.Block, Vector3.new(0.3, 0.6, 0.22), GM, Enum.Material.Metal, CFrame.new(0.35, -0.5, 0) * CFrame.Angles(0, 0, math.rad(-6)))
		-- BIPOD (front, folded down in a V)
		part("BipodMnt", Enum.PartType.Block,    Vector3.new(0.16, 0.16, 0.2),  GM, Enum.Material.Metal, CFrame.new(3.0, -0.12, 0))
		part("BipodLeg", Enum.PartType.Cylinder, Vector3.new(1.0, 0.06, 0.06),  GM, Enum.Material.Metal, CFrame.new(3.1, -0.55, 0.14) * CFrame.Angles(0, 0, math.rad(72)) * CFrame.Angles(math.rad(12), 0, 0))
		part("BipodLeg", Enum.PartType.Cylinder, Vector3.new(1.0, 0.06, 0.06),  GM, Enum.Material.Metal, CFrame.new(3.1, -0.55, -0.14) * CFrame.Angles(0, 0, math.rad(72)) * CFrame.Angles(math.rad(-12), 0, 0))
		-- held ACROSS the body, barrel pointing FORWARD (tweak if it sits off)
		tool.Grip = CFrame.new(0.4, -0.3, 0.6) * CFrame.Angles(0, math.rad(-90), 0)
		return tool
	end

	-- ===== MAMA RAPTOR: spawn + wander/chase/steal =====
	local mama, hits, dead = nil, 0, false
	if raptorSpot then
		-- locate the user's RaptorModel (Workspace / ServerStorage / ReplicatedStorage)
		local src
		for _, where in ipairs({ Workspace, ServerStorage, RS }) do
			local f = where:FindFirstChild("RaptorModel", true)
			if f then src = f; break end
		end
		-- ASSESS it so we can see how it's built (parts / joints / humanoid)
		if src then
			-- inspectModel(src) -- (full dump available if needed; commented out to keep Output clean)
			local nb, nj, hum0 = 0, 0, src:FindFirstChildOfClass("Humanoid")
			for _, d in ipairs(src:GetDescendants()) do
				if d:IsA("BasePart") then nb += 1 elseif d:IsA("Motor6D") or d:IsA("Weld") then nj += 1 end
			end
			print(("===== [Redwood] RaptorModel: %s (%s) | parts=%d joints=%d humanoid=%s ====="):format(src:GetFullName(), src.ClassName, nb, nj, tostring(hum0 ~= nil)))
			for _, d in ipairs(src:GetDescendants()) do
				if d:IsA("BasePart") then print(("[Redwood]   part  %-18s size=(%.2f, %.2f, %.2f)"):format(d.Name, d.Size.X, d.Size.Y, d.Size.Z)) end
			end
			for _, d in ipairs(src:GetDescendants()) do
				if d:IsA("Motor6D") then print(("[Redwood]   motor %-16s %s -> %s"):format(d.Name, d.Part0 and d.Part0.Name or "?", d.Part1 and d.Part1.Name or "?")) end
			end
		end
		-- use the model as the mama (fallback to the code raptor if it's missing)
		if src and src:IsA("Model") then
			mama = src; mama.Name = "MamaRaptor"
			if not mama:IsDescendantOf(Workspace) then mama.Parent = Workspace end
		elseif src and src:IsA("BasePart") then
			mama = Instance.new("Model"); mama.Name = "MamaRaptor"; mama.Parent = Workspace; src.Parent = mama; mama.PrimaryPart = src
		elseif src then
			mama = Instance.new("Model"); mama.Name = "MamaRaptor"; mama.Parent = Workspace
			for _, c in ipairs(src:GetChildren()) do c.Parent = mama end; pcall(function() src:Destroy() end)
		else
			warn("[Redwood] RaptorModel not found anywhere -> using the code-built raptor")
			mama = buildMamaRaptor(); mama.Parent = Workspace
		end
		pcall(function() mama.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end) -- never stream out
		ignoreForGround[#ignoreForGround + 1] = mama

		-- find the rig ROOT (joint hub -> common names -> biggest part), and whether it's a jointed rig
		local hasJoints, jointHub = false, nil
		do
			local cnt = {}
			for _, d in ipairs(mama:GetDescendants()) do
				if d:IsA("Motor6D") then hasJoints = true; if d.Part0 then cnt[d.Part0] = (cnt[d.Part0] or 0) + 1 end end
			end
			local bn = 0; for p, n in pairs(cnt) do if n > bn then bn = n; jointHub = p end end
		end
		local root = mama:FindFirstChild("HumanoidRootPart", true) or jointHub
			or mama:FindFirstChild("Torso", true) or mama:FindFirstChild("Root", true)
		if not root then local best, bv = nil, -1
			for _, d in ipairs(mama:GetDescendants()) do if d:IsA("BasePart") then local v = d.Size.X * d.Size.Y * d.Size.Z; if v > bv then bv = v; best = d end end end
			root = best end
		mama.PrimaryPart = root

		-- ANCHOR EVERY PART (fully rigid -> no physics bounce / tipping / vanishing). Moved with PivotTo.
		for _, d in ipairs(mama:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = true end
		end

		-- COLOUR: a raptor palette (not flat green) + amber EYES on the head
		local function paint(name, color)
			local p = mama:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then p.Color = color; p.Material = Enum.Material.SmoothPlastic end
		end
		paint("Velociraptor2", Color3.fromRGB(86, 118, 72))   -- body: green
		paint("Velociraptor",  Color3.fromRGB(205, 178, 128)) -- underside/legs: tan
		paint("Velociraptor3", Color3.fromRGB(150, 95, 60))   -- head: warm brown

		-- PLAY the model's animations (the "things that make it alive") so the legs/tail move
		local animsPlayed = 0
		do
			local hum = mama:FindFirstChildOfClass("Humanoid")
			local animator
			if hum then
				animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator"); animator.Parent = hum
			else
				local ac = mama:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController"); ac.Parent = mama
				animator = ac:FindFirstChildOfClass("Animator") or Instance.new("Animator"); animator.Parent = ac
			end
			for _, d in ipairs(mama:GetDescendants()) do
				if d:IsA("Animation") and d.AnimationId ~= "" then
					local ok, tr = pcall(function() return animator:LoadAnimation(d) end)
					if ok and tr then tr.Looped = true; pcall(function() tr:Play() end); animsPlayed += 1 end
				end
			end
			print(("[Redwood] mama: joints=%s animationsPlayed=%d root=%s"):format(tostring(hasJoints), animsPlayed, root and root.Name or "?"))
		end

		-- ORIENTATION DUMP: shows exactly how the model is rotated so the upright fix can be computed.
		do
			local rp = mama:GetPivot()
			local ax, ay, az = rp:ToOrientation()
			print(("[Redwood][ORIENT] pivot orient(deg) X=%.0f Y=%.0f Z=%.0f"):format(math.deg(ax), math.deg(ay), math.deg(az)))
			print(("[Redwood][ORIENT] pivot Up=(%.2f,%.2f,%.2f) Look=(%.2f,%.2f,%.2f) Right=(%.2f,%.2f,%.2f)"):format(
				rp.UpVector.X, rp.UpVector.Y, rp.UpVector.Z, rp.LookVector.X, rp.LookVector.Y, rp.LookVector.Z, rp.RightVector.X, rp.RightVector.Y, rp.RightVector.Z))
			local _, sz = mama:GetBoundingBox()
			print(("[Redwood][ORIENT] bbox size=(%.1f,%.1f,%.1f)"):format(sz.X, sz.Y, sz.Z))
			for _, d in ipairs(mama:GetDescendants()) do
				if d:IsA("BasePart") then
					local rel = rp:Inverse() * d.CFrame
					local ox, oy, oz = d.CFrame:ToOrientation()
					print(("[Redwood][ORIENT] %-14s relPos=(%.1f,%.1f,%.1f) orient(deg)=(%.0f,%.0f,%.0f) size=(%.1f,%.1f,%.1f)"):format(
						d.Name, rel.Position.X, rel.Position.Y, rel.Position.Z, math.deg(ox), math.deg(oy), math.deg(oz), d.Size.X, d.Size.Y, d.Size.Z))
				end
			end
		end

		-- <<< UPRIGHT CORRECTION (applied in the model's LOCAL space). Set once the [Redwood][ORIENT] dump is read.
		-- Examples: on its head -> CFrame.Angles(math.rad(180),0,0); lying on a side -> Angles(0,0,math.rad(90)).
		local ORIENT_FIX = CFrame.Angles(math.rad(90), 0, 0) -- model body is 13 tall on Y (built vertical) -> pitch it horizontal
		local placedRot = mama:GetPivot().Rotation * ORIENT_FIX
		mama:PivotTo(CFrame.new(mama:GetPivot().Position) * placedRot) -- apply the fix so grounding uses the corrected pose
		pcall(function() mama:ScaleTo(1.5) end) -- 1.5x bigger overall

		-- footOffset: pivot height above the model's TRUE WORLD bottom. (GetBoundingBox is pivot-ORIENTED, which
		-- gives a wrong height for a rotated rig -> PivotTo drops it underground and FallenPartsDestroyHeight
		-- deletes it = "spawns then disappears".) Compute the lowest world corner of every part instead.
		local function worldBottomY()
			local minY = math.huge
			for _, d in ipairs(mama:GetDescendants()) do
				if d:IsA("BasePart") then
					local cf, sz = d.CFrame, d.Size
					for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz2 = -1, 1, 2 do
						local y = (cf * CFrame.new(sx * sz.X / 2, sy * sz.Y / 2, sz2 * sz.Z / 2)).Y
						if y < minY then minY = y end
					end end end
				end
			end
			return (minY < math.huge) and minY or mama:GetPivot().Position.Y
		end
		-- FEET ON GROUND: ground off the actual FOOT BONES' rest height (so the feet sit exactly on the floor),
		-- falling back to the mesh box only if the bones aren't readable.
		local footTune = 0 -- nudge if needed: + raises it, - lowers it
		local footY = math.huge
		for _, n in ipairs({ "FrontFoot.R", "FrontFoot.L", "BackFoot.R", "BackFoot.L", "BackLowLeg.R", "BackLowLeg.L" }) do
			local b = mama:FindFirstChild(n, true)
			if b and b:IsA("Bone") then
				local ok, y = pcall(function() return b.WorldCFrame.Position.Y end)
				if ok and y then footY = math.min(footY, y) end
			end
		end
		local footOffset
		if footY < math.huge then
			footOffset = mama:GetPivot().Position.Y - footY + footTune
		else
			footOffset = mama:GetPivot().Position.Y - worldBottomY() + footTune
		end
		print(("[Redwood] footOffset=%.2f (grounded from %s)"):format(footOffset, footY < math.huge and "foot bones" or "mesh box"))

		local home = Vector3.new(raptorSpot.Position.X, 0, raptorSpot.Position.Z)
		local pos  = Vector3.new(home.X, 0, home.Z)
		local dir  = Vector3.new(0, 0, 1)
		local target = pos
		local lastGY = groundY(home.X, home.Z, REF_Y + 120, 400) or REF_Y
		local homeGY = lastGY -- island surface level; never let it drop far below this (no falling to map bottom)
		-- ISLAND BOUNDS: keep the raptor on island6 (inset from the edges) so it can NEVER wander/fall off
		local i6cf, i6size = island6:GetBoundingBox()
		local i6cx, i6cz = i6cf.Position.X, i6cf.Position.Z
		local i6hx, i6hz = math.max(4, i6size.X / 2 - 10), math.max(4, i6size.Z / 2 - 10)
		local function onIsland(x, z) return math.abs(x - i6cx) <= i6hx and math.abs(z - i6cz) <= i6hz end
		local function newTarget()
			for _ = 1, 10 do
				local a = math.random() * 2 * math.pi
				local d = 4 + math.random() * (WANDER_R - 4)
				local tx, tz = home.X + math.cos(a) * d, home.Z + math.sin(a) * d
				if onIsland(tx, tz) then target = Vector3.new(tx, 0, tz); return end
			end
			target = Vector3.new(home.X, 0, home.Z) -- fallback: head back home
		end
		newTarget()

		local head = mama:FindFirstChild("Head", true) or root
		local bb = Instance.new("BillboardGui"); bb.Name = "MamaHP"; bb.Adornee = head; bb.Size = UDim2.fromOffset(170, 40)
		bb.StudsOffset = Vector3.new(0, 6, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 140; bb.Parent = mama -- only show near island6 (not from other islands)
		local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 120, 120); lbl.TextStrokeTransparency = 0
		lbl.Text = ("Mama Raptor  %d/%d"):format(MAX_HITS, MAX_HITS); lbl.Parent = bb

		-- keep the model's EXACT placed orientation (never reorient -> it can NEVER flip); just translate + a tiny bob
		local origRot = mama:GetPivot().Rotation -- = the corrected (pitched-upright) rotation
		local bobT = 0
		local curYaw = math.atan2(-dir.X, -dir.Z)
		local function place(dt)
			pcall(function()
				local hop = math.abs(math.sin(bobT * 9)) * 0.3
				local targetYaw = math.atan2(-dir.X, -dir.Z)
				local diff = (targetYaw - curYaw + math.pi) % (2 * math.pi) - math.pi  -- shortest signed angle
				curYaw = curYaw + diff * math.clamp((dt or 0.03) * 5, 0, 1)             -- SMOOTH turn (no violent spinning)
				mama:PivotTo(CFrame.new(pos.X, lastGY + footOffset + hop, pos.Z) * CFrame.Angles(0, curYaw, 0) * origRot)
			end)
		end
		place(0)

		-- EYES: the imported mesh's eyes are baked in (can't recolor them), so add glowing eye parts on the head.
		do
			local hb = mama:FindFirstChild("Head", true)
			local headMesh = mama:FindFirstChild("Velociraptor3", true) or root
			if hb and hb:IsA("Bone") then
				local base = CFrame.new(hb.WorldCFrame.Position) * mama:GetPivot().Rotation -- head pos, model's facing
				for _, sgn in ipairs({ 1, -1 }) do
					local e = Instance.new("Part"); e.Name = "RaptorEye"; e.Shape = Enum.PartType.Ball; e.Size = Vector3.new(0.7, 0.7, 0.7)
					e.Color = Color3.fromRGB(255, 45, 45); e.Material = Enum.Material.Neon
					e.Anchored = true; e.CanCollide = false; e.CanQuery = false
					e.CFrame = base * CFrame.new(0.7 * sgn, 0.5, -0.8) -- sides / up / forward of the head (best guess)
					e.Parent = mama
					local w = Instance.new("WeldConstraint"); w.Part0 = headMesh; w.Part1 = e; w.Parent = e
				end
				print("[Redwood] eyes added on the head (Head bone)")
			end
		end

		local lastSteal = {}
		RunService.Heartbeat:Connect(function(dt)
			if dead or not mama.Parent then return end
			bobT += dt -- advance the alive bob/sway
			local gy = groundY(pos.X, pos.Z, lastGY + 15, 50); if gy and gy >= homeGY - 12 and gy <= homeGY + 30 then lastGY = gy end -- stay near island level

			local nearest, nd = nil, DETECT
			for _, plr in ipairs(Players:GetPlayers()) do
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local d = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
					local fromHome = (Vector3.new(hrp.Position.X - home.X, 0, hrp.Position.Z - home.Z)).Magnitude
					if d < nd and fromHome < CHASE_R then nd = d; nearest = plr end
				end
			end

			local speed = WANDER_SPD
			if nearest then
				local hrp = nearest.Character.HumanoidRootPart
				target = Vector3.new(hrp.Position.X, 0, hrp.Position.Z); speed = CHASE_SPD
				if nd < STEAL_DIST then
					local now = os.clock()
					if now - (lastSteal[nearest] or 0) > STEAL_CD then
						lastSteal[nearest] = now
						local ls = nearest:FindFirstChild("leaderstats")
						local cp = ls and ls:FindFirstChild("CurrentPower")
						if cp and cp.Value > 0 then
							local steal = math.min(cp.Value, STEAL_AMT); cp.Value = cp.Value - steal
							floaty(hrp, ("-%d Fart Power!"):format(steal), Color3.fromRGB(255, 110, 110))
						end
					end
				end
			else
				-- roam freely: new wander point when we reach the current one OR when the target is a stale
				-- out-of-bounds chase point (so it heads back inside instead of bouncing on the edge)
				local tHome = (Vector3.new(target.X - home.X, 0, target.Z - home.Z)).Magnitude
				if (Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)).Magnitude < 2 or tHome > WANDER_R then newTarget() end
			end

			local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if flat.Magnitude > 0.6 then
				dir = flat.Unit
				local rpF = RaycastParams.new(); rpF.FilterType = Enum.RaycastFilterType.Exclude; rpF.FilterDescendantsInstances = buildIgnore()
				local blocked = Workspace:Raycast(Vector3.new(pos.X, lastGY + 2, pos.Z), dir * 4.5, rpF)
				if blocked then
					if not nearest then newTarget() end
				else
					local nx = pos + dir * speed * dt
					local fh = Vector3.new(nx.X - home.X, 0, nx.Z - home.Z)
					if fh.Magnitude > CHASE_R then nx = Vector3.new(home.X, 0, home.Z) + fh.Unit * CHASE_R end
					-- step only onto SOLID ground AND while staying ON the island (never fall/wander off the edge)
					local cgy = groundY(nx.X, nx.Z, lastGY + 15, 50)
					-- step only onto solid ground that's ON the island AND near the island's surface level
					if cgy and onIsland(nx.X, nx.Z) and cgy >= homeGY - 12 and cgy <= homeGY + 30 then
						pos = Vector3.new(nx.X, 0, nx.Z); lastGY = cgy
					elseif not nearest then
						newTarget()
					end
				end
			end
			place(dt)
		end)

		local function killMama()
			if dead then return end
			dead = true
			pcall(function() bb:Destroy() end)
			local cf = mama:GetPivot()
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 0.9 and mama.Parent do
					local p = (os.clock() - t0) / 0.9
					pcall(function() mama:PivotTo(cf * CFrame.Angles(0, 0, math.rad(82 * p))) end); task.wait()
				end
				for _, d in ipairs(mama:GetDescendants()) do
					if d:IsA("BasePart") then TS:Create(d, TweenInfo.new(0.8), { Transparency = 1 }):Play() end
				end
				task.wait(1.0)
				local dp = mama:GetPivot().Position
				pcall(function() mama:Destroy() end)
				spawnEgg(dp.X, dp.Z)
			end)
		end

		-- watchdog: log the mama's position so we can confirm it's present + where (every 2s)
		task.spawn(function()
			while mama and mama.Parent and not dead do
				local p = mama:GetPivot().Position
				print(("[Redwood] mama at (%.1f, %.1f, %.1f)"):format(p.X, p.Y, p.Z))
				task.wait(2)
			end
			if not (mama and mama.Parent) and not dead then warn("[Redwood] mama VANISHED (destroyed) -- not by death") end
		end)

		RaptorShot.OnServerEvent:Connect(function()
			if dead or not mama.Parent then return end
			hits += 1
			pcall(function() lbl.Text = ("Mama Raptor  %d/%d"):format(math.max(0, MAX_HITS - hits), MAX_HITS) end)
			pcall(function()
				local b = mama:FindFirstChild("Body")
				if b then local c = b.Color; b.Color = Color3.fromRGB(255, 90, 90); task.delay(0.12, function() if b.Parent then b.Color = c end end) end
			end)
			if hits >= MAX_HITS then killMama() end
		end)
		print("[Redwood] Mama Raptor (blocky model) spawned -- wanders, chases + steals fart power")
	end

	-- ===== BIG SNIPER LOCKER at SniperSpot =====
	if sniperSpot then
		local sp = sniperSpot.Position
		local gy = groundY(sp.X, sp.Z, sp.Y + 120, 400) or REF_Y
		local locker = Instance.new("Model"); locker.Name = "SniperLocker"; locker.Parent = Workspace
		ignoreForGround[#ignoreForGround + 1] = locker
		local STEELC, DARKC = Color3.fromRGB(78, 84, 94), Color3.fromRGB(48, 52, 60)
		local base = CFrame.new(sp.X, gy + 3.0, sp.Z) * CFrame.Angles(0, math.rad(180), 0) -- spun 180
		local function lp(name, size, color, cf, mat, collide)
			local p = Instance.new("Part"); p.Name = name; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.Metal
			p.Anchored = true; p.CanCollide = collide ~= false; p.CFrame = cf; p.Parent = locker; return p
		end
		lp("Back",   Vector3.new(5.0, 6.0, 0.5), STEELC, base * CFrame.new(0, 0, -1.0))
		lp("Left",   Vector3.new(0.4, 6.0, 2.2), DARKC,  base * CFrame.new(-2.3, 0, 0))
		lp("Right",  Vector3.new(0.4, 6.0, 2.2), DARKC,  base * CFrame.new(2.3, 0, 0))
		lp("Top",    Vector3.new(5.0, 0.5, 2.2), DARKC,  base * CFrame.new(0, 3.0, 0))
		lp("Bottom", Vector3.new(5.0, 0.6, 2.2), DARKC,  base * CFrame.new(0, -3.0, 0))
		lp("Shelf",  Vector3.new(4.4, 0.2, 1.9), STEELC, base * CFrame.new(0, 0.2, 0), nil, false)
		lp("Feet1",  Vector3.new(0.5, 0.8, 0.5), DARKC,  CFrame.new(sp.X - 1.9, gy + 0.4, sp.Z))
		lp("Feet2",  Vector3.new(0.5, 0.8, 0.5), DARKC,  CFrame.new(sp.X + 1.9, gy + 0.4, sp.Z))
		local glass = lp("Glass", Vector3.new(4.6, 5.6, 0.12), Color3.fromRGB(150, 200, 230), base * CFrame.new(0, 0, 1.05), Enum.Material.Glass, false)
		glass.Transparency = 0.55; glass.Reflectance = 0.15
		for i = -1, 1 do
			lp("RifleDecor", Vector3.new(0.22, 3.4, 0.2), Color3.fromRGB(40, 42, 48), base * CFrame.new(i * 1.1, 0.6, 0.2) * CFrame.Angles(0, 0, math.rad(6)), Enum.Material.Metal, false)
			lp("RifleBarrel", Vector3.new(0.14, 2.0, 0.14), Color3.fromRGB(70, 74, 82), base * CFrame.new(i * 1.1 + 0.12, 1.5, 0.2), Enum.Material.Metal, false)
		end
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(180, 220, 255); pl.Brightness = 1.4; pl.Range = 14; pl.Parent = locker:FindFirstChild("Top")
		local signbb = Instance.new("BillboardGui"); signbb.Adornee = locker:FindFirstChild("Top"); signbb.Size = UDim2.fromOffset(230, 50)
		signbb.StudsOffset = Vector3.new(0, 1.8, 0); signbb.AlwaysOnTop = true; signbb.MaxDistance = 140; signbb.Parent = locker -- only show near island6
		local sl = Instance.new("TextLabel"); sl.Size = UDim2.fromScale(1, 1); sl.BackgroundTransparency = 1; sl.Font = Enum.Font.FredokaOne
		sl.TextScaled = true; sl.TextColor3 = Color3.fromRGB(255, 225, 120); sl.TextStrokeTransparency = 0; sl.Text = "\xF0\x9F\x94\xAB Sniper Locker"; sl.Parent = signbb

		local prompt = Instance.new("ProximityPrompt"); prompt.ActionText = "Grab Sniper"; prompt.ObjectText = "Sniper Locker"
		prompt.HoldDuration = 0.3; prompt.MaxActivationDistance = 14; prompt.RequiresLineOfSight = false; prompt.Parent = glass
		prompt.Triggered:Connect(function(plr)
			local bp = plr:FindFirstChildOfClass("Backpack")
			local has = (plr.Character and plr.Character:FindFirstChild("Sniper")) or (bp and bp:FindFirstChild("Sniper"))
			if has then return end
			local t = buildSniperTool(); t.Parent = bp or plr.Character
		end)
		print("[Redwood] Big Sniper Locker built at SniperSpot")
	end
end)
