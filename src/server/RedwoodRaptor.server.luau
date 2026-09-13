--======================================================================
-- RedwoodRaptor.server.luau  (server Script)
--======================================================================
-- Island6 ("Redwood Ridge") raptor hunt:
--   * RaptorSpot -> a big BLOCKY MAMA RAPTOR (organic dino model, NOT the cube pet) wanders
--     near the spot. Get too close and she charges + STEALS fart power (CurrentPower).
--   * SniperSpot -> a big SNIPER LOCKER; grab a sniper Tool.
--   * Shoot the mama 4 times -> she tips over, fades, and a RAPTOR EGG rises.
--   * Hatch the egg -> the Velociraptor PET (the cube pet template), follower + Pet Hub.
--
-- WHY THIS QUEST HAS NO PickupFloor MINIGAME (it is not an oversight)
-- ------------------------------------------------------------------
-- Every other island holds each collectible to a 15s floor (see
-- ReplicatedStorage/DinosaurRealm/PickupFloor). This one is deliberately exempt,
-- on two counts:
--
--   1. It has ONE collectible, not five. The raptors are not items -- the EGG is,
--      and only one raptor hides it. Downing all five is the single 15s of work
--      that buys it, and the floor is a per-COLLECTIBLE rule.
--   2. Nothing here is handed over on a prompt trigger. The floor exists to kill
--      free grabs; a wandering target that charges you and steals CurrentPower is
--      already work. It also already has PickupFloor's pattern 4 (natural rate
--      limit): RedwoodRaptor.client.luau enforces a 0.5s gap between shots, so
--      the optimal loop is 5 raptors x 4 hits x 0.5s = 9.5s of pure firing before
--      any of the travel spent finding five raptors across the island.
--
-- So do NOT "fix" this by inflating MAX_HITS -- 11 sniper shots to drop one raptor
-- would hit the number and wreck the weapon. If the island ever grows a real
-- multi-item collect step, THAT step gets the floor, not the shooting.
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
local WANDER_R, CHASE_R, WANDER_SPD, CHASE_SPD = 16, 55, 6, 12 -- tighter roam so the 5 raptors stay spread out

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
	--
	-- CANOPY REJECTION (`nearY`) -- why a raptor stood in mid-air on a tree.
	--
	-- The initial placement casts from 120 studs OVER a 'putdino' marker, and Redwood Ridge
	-- is tall trees: if a marker sits under a branch, that ray meets the CANOPY before it
	-- meets the island. The hit is perfectly real, so the old code grounded on it and the
	-- raptor was planted on top of the foliage. The blurb above only ever held for the
	-- WANDER casts, which start just above the feet on a short 50-stud range -- placement
	-- used the long cast and had no such protection.
	--
	-- Pass `nearY` (the marker's own height) and a hit more than CANOPY_CLEARANCE above it
	-- is treated as foliage: the ray restarts just below that hit and keeps descending until
	-- it reaches something at the marker's actual level. MosquitoQuest solves the identical
	-- island5 problem with its SURFACE_BAND clamp.
	--
	-- CALLERS THAT PASS NO nearY ARE UNCHANGED -- the eggs and the sniper locker ground
	-- exactly as before. A raptor already standing correctly is unchanged too: its first hit
	-- is inside the clearance, so the loop returns on the first pass. Only a raptor that was
	-- grounding on foliage moves, which is what "fix the green one, leave the rest" needs.
	local CANOPY_CLEARANCE = 8
	local function groundY(x, z, fromY, dist, nearY)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = buildIgnore()
		local startY = fromY or (REF_Y + 120)
		local endY = startY - (dist or 400)
		for _ = 1, 12 do -- 12 is a runaway guard, not a budget: one pass per layer of branches
			if startY <= endY then return nil end
			local hit = Workspace:Raycast(Vector3.new(x, startY, z), Vector3.new(0, -(startY - endY), 0), rp)
			if not hit then return nil end
			local hy = hit.Position.Y
			if not nearY or hy <= nearY + CANOPY_CLEARANCE then return hy end
			startY = hy - 0.05 -- drop just under the foliage we hit and keep going down
		end
		return nil
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

	-- ===== MAMA RAPTORS: 5 wandering raptors, ONE hides the secret egg =====
	-- Identical behaviour, different colours. Players must shoot each one down (4
	-- hits) to discover which raptor was hiding the egg. Only ONE raptor may chase
	-- a player at a time (shared `activeChaser` claim) -- you never get swarmed.
	local raptorByModel = {}   -- raptor model -> its hit handler (a shot routes here by the model hit)
	local activeChaser  = nil  -- index of the raptor currently chasing (only one at a time)

	-- Find the user's RaptorModel ONCE and keep it as a hidden template we clone per
	-- raptor (the old code used the single placed model directly).
	local template
	for _, where in ipairs({ Workspace, ServerStorage, RS }) do
		local f = where:FindFirstChild("RaptorModel", true)
		if f and f:IsA("Model") then template = f; break end
	end
	if template then
		for _, d in ipairs(template:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
		template.Parent = ServerStorage -- stash out of view; we spawn clones of it
	end

	-- 5 distinct raptor palettes: { body, underside/legs, head }
	local RAPTOR_PALETTES = {
		{ Color3.fromRGB(86, 118, 72),  Color3.fromRGB(205, 178, 128), Color3.fromRGB(150, 95, 60) },  -- forest green
		{ Color3.fromRGB(130, 72, 58),  Color3.fromRGB(214, 170, 138), Color3.fromRGB(96, 52, 44) },   -- rusty red-brown
		{ Color3.fromRGB(72, 98, 132),  Color3.fromRGB(172, 192, 212), Color3.fromRGB(52, 72, 102) },  -- slate blue
		{ Color3.fromRGB(158, 138, 64), Color3.fromRGB(222, 206, 150), Color3.fromRGB(116, 98, 46) },  -- sandy gold
		{ Color3.fromRGB(104, 84, 128), Color3.fromRGB(186, 168, 210), Color3.fromRGB(74, 56, 98) },   -- dusk purple
	}
	-- distinct names so the 5 raptors aren't all called the same thing (the client
	-- identifies them by the "RedwoodRaptor" attribute below, not by name).
	local RAPTOR_NAMES = { "GreenRaptor", "RustRaptor", "SlateRaptor", "GoldRaptor", "VioletRaptor" }

	-- Build one raptor at (homeX, homeZ) with the given palette. hasEgg = holds the secret egg.
	local function spawnRaptor(index, palette, hasEgg, homeX, homeZ, homeY)
		local mama, hits, dead = nil, 0, false
		if template then
			mama = template:Clone()
		else
			if index == 1 then warn("[Redwood] RaptorModel not found anywhere -> using the code-built raptor") end
			mama = buildMamaRaptor()
		end
		mama.Name = RAPTOR_NAMES[index] or ("Raptor" .. index) -- distinct names, not all "MamaRaptor"
		mama:SetAttribute("RedwoodRaptor", true) -- how the client identifies a raptor (names now vary)
		mama.Parent = Workspace
		pcall(function() mama.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end) -- never stream out
		ignoreForGround[#ignoreForGround + 1] = mama

		-- find the rig ROOT (joint hub -> common names -> biggest part), and whether it's a jointed rig
		local hasJoints, jointHub = false, nil
		do
			local cnt = {}
			for _, d in ipairs(mama:GetDescendants()) do
				if d:IsA("Motor6D") then hasJoints = true; if d.Part0 then cnt[d.Part0] = (cnt[d.Part0] or 0) + 1 end end
			end
			-- DETERMINISTIC PICK. This was a bare `pairs(cnt)` scan keeping the highest count,
			-- and pairs() over an Instance-keyed table has NO defined order -- so whenever two
			-- parts tied on joint count, which one became the rig's root varied from boot to
			-- boot. The root becomes PrimaryPart, PrimaryPart defines the pivot, and the pivot
			-- is what GetBoundingBox and footOffset are measured against: a different winner is
			-- a different pivot, which is one way the footOffset clamp below gets tripped.
			-- Ties now break on NAME, so the same rig resolves the same way every time.
			local bn = 0
			for p, n in pairs(cnt) do
				if n > bn or (n == bn and jointHub and p.Name < jointHub.Name) then bn = n; jointHub = p end
			end
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
		paint("Velociraptor2", palette[1]) -- body
		paint("Velociraptor",  palette[2]) -- underside/legs
		paint("Velociraptor3", palette[3]) -- head

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

		-- ORIENTATION DUMP (first raptor only -- keeps the log clean with 6 raptors).
		if index == 1 then
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
		-- FEET ON GROUND: ground off the model's TRUE LOWEST part bottom so the feet rest
		-- flush on the surface and nothing is buried. (Foot BONES sit up inside the ankle,
		-- above the actual sole -- grounding off them sank the raptors underground.)
		local footTune = 0 -- nudge if needed: + raises it, - lowers it
		local footOffset = mama:GetPivot().Position.Y - worldBottomY() + footTune

		-- SANITY CLAMP -- this goes wrong INTERMITTENTLY and puts every raptor in orbit.
		--
		-- Seen in the wild: bbox size=(692.8, 30.5, 700.7) and footOffset=1050.29, on a rig
		-- whose parts are all under 14 studs. A bounding box the size of the ISLAND means the
		-- pivot and the body had drifted apart -- one stray part (or a PrimaryPart left at the
		-- origin while the rest of the rig moved with island6) stretches the box across the
		-- whole map, and footOffset is measured off that box. The raptors then stood ~1,050
		-- studs above the ground, which is the bug this catches.
		--
		-- It is intermittent because it depends on boot ORDER against IslandLayout, so it
		-- cannot be relied on to show up in testing -- most runs are fine, as this one was.
		--
		-- A raptor is ~13 studs tall before the 1.5x scale, so anything past MAX_FOOT is not
		-- a tall raptor, it is a broken measurement. Fall back to half the model's height,
		-- which is right for a centred pivot and is never catastrophically wrong.
		local MAX_FOOT = 40
		if footOffset ~= footOffset or math.abs(footOffset) > MAX_FOOT then -- NaN or absurd
			local _, sz = mama:GetBoundingBox()
			local fallback = math.min(sz.Y * 0.5, MAX_FOOT)
			warn(("[Redwood] %s: footOffset %.1f is impossible for a raptor (bbox %.0fx%.0fx%.0f) "
				.. "-> pivot/body drift, using %.2f instead. If this repeats, check RaptorModel for a "
				.. "stray part far from the rig."):format(mama.Name, footOffset, sz.X, sz.Y, sz.Z, fallback))
			footOffset = fallback
		end
		print(("[Redwood] footOffset=%.2f (grounded from lowest part bottom)"):format(footOffset))

		local home = Vector3.new(homeX, 0, homeZ)
		local pos  = Vector3.new(home.X, 0, home.Z)
		local dir  = Vector3.new(0, 0, 1)
		local target = pos
		-- ground from THIS home's own elevation (the putdino marker's height), not
		-- RaptorSpot's -- so a marker on a rise/rock grounds correctly and every raptor
		-- ends up flush at its own spot (no odd-one-out floating/sunk).
		local baseY = homeY or REF_Y
		-- baseY (the marker's own height) doubles as the canopy-rejection reference, so a ray
		-- that snags a branch overhead keeps descending to the island instead of grounding
		-- the raptor on the foliage. See the CANOPY REJECTION note on groundY.
		local lastGY = groundY(home.X, home.Z, baseY + 120, 400, baseY) or baseY
		-- Per-raptor grounding line, so a floating one is identifiable from the log instead of
		-- by walking the island. All five should read within a few studs of each other.
		print(("[Redwood] %s: marker Y=%.1f -> ground Y=%.1f (feet at %.1f)")
			:format(mama.Name, baseY, lastGY, lastGY + footOffset))
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

		--------------------------------------------------------------------
		-- PANIC -- what a shot raptor does instead of carrying on grazing.
		--------------------------------------------------------------------
		-- Getting hit used to flash the body red and change NOTHING about how the animal
		-- moved: it kept ambling to its next wander point at the same 6 studs/sec as if
		-- nothing had happened, which made the whole hunt feel like shooting a prop.
		--
		-- Now a hit throws it into a bolt: fast, erratic, AWAY from whoever shot, and it
		-- re-picks a direction every few tenths of a second so it scatters rather than
		-- running one clean line off into the trees. It also drops any chase it was on --
		-- a wounded animal is not still coming for you.
		--
		-- panicUntil doubles as the flag; nothing else has to be reset when it lapses.
		local panicUntil, panicNext = 0, 0
		local PANIC_TIME  = 4.5   -- seconds of bolting per hit (a second hit re-arms it)
		local PANIC_SPD   = 22    -- vs WANDER 6 / CHASE 12 -- clearly running for its life
		local PANIC_TURN  = 0.35  -- seconds between new scatter points; low = frantic
		local PANIC_HOP   = 14    -- how far each scatter point is thrown

		-- Pick somewhere to bolt to. Biased directly away from `from` (the shooter) when we
		-- know who that is, then jittered wide so five panicking raptors don't stack into a
		-- single stream. Falls back to the normal wander picker if the island edge blocks
		-- every candidate, so a panicking raptor can still never run off the island.
		local function panicTarget(from: Vector3?)
			local awayA
			if from then
				awayA = math.atan2(pos.Z - from.Z, pos.X - from.X)
			else
				awayA = math.random() * 2 * math.pi
			end
			for _ = 1, 12 do
				local a = awayA + (math.random() - 0.5) * math.rad(150) -- wide cone, not a line
				local d = PANIC_HOP * (0.6 + math.random() * 0.8)
				local tx, tz = pos.X + math.cos(a) * d, pos.Z + math.sin(a) * d
				-- STAY ON THE LEASH. This was CHASE_R (55) and that is what put raptors up in
				-- the trees: normal roaming never leaves WANDER_R (16) of home, so the ground
				-- within that ring is known-good, while a panic that threw them 55 studs out
				-- sent them scrambling onto rocks and root systems they had never touched.
				-- 1.5x the wander ring is enough room to look frantic without leaving the
				-- clearing the raptor actually lives in.
				local fh = Vector3.new(tx - home.X, 0, tz - home.Z)
				if onIsland(tx, tz) and fh.Magnitude <= WANDER_R * 1.5 then
					target = Vector3.new(tx, 0, tz)
					return
				end
			end
			newTarget()
		end

		--------------------------------------------------------------------
		-- OVERHEAD: NOTHING, UNTIL YOU ACTUALLY HIT IT.
		--------------------------------------------------------------------
		-- This used to be a permanent nameplate reading "Velociraptor  4/4" over every
		-- raptor on the island -- five floating labels announcing themselves before you had
		-- even drawn the rifle, which told you which models were targets and killed any
		-- sense of hunting something. Both the name and the counter are gone.
		--
		-- What replaces it is a HEALTH BAR that is invisible until this raptor is shot, then
		-- shows for a few seconds and fades back out. It is built PER RAPTOR inside
		-- spawnRaptor, so `bb`/`fill` below are this animal's own -- hitting one cannot
		-- light up the other four, which is the thing that makes it read as damage to a
		-- specific creature rather than a group HUD.
		local head = mama:FindFirstChild("Head", true) or root
		local HP_SHOW_TIME = 3.5   -- seconds of no further hits before it hides again

		local bb = Instance.new("BillboardGui")
		bb.Name = "MamaHP"
		bb.Adornee = head
		bb.Size = UDim2.fromOffset(140, 14)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220        -- was 140; you shoot these from across the clearing
		bb.Enabled = false          -- <== the whole point: silent until hit
		bb.Parent = mama

		local track = Instance.new("Frame")
		track.Size = UDim2.fromScale(1, 1)
		track.BackgroundColor3 = Color3.fromRGB(26, 18, 16)
		track.BorderSizePixel = 0
		track.Parent = bb
		do
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = track
			local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(12, 8, 8); s.Thickness = 2; s.Parent = track
		end

		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(96, 220, 112)
		fill.BorderSizePixel = 0
		fill.Parent = track
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = fill end

		-- Token, not a plain task.delay: every hit bumps it, so an older pending hide can
		-- never switch the bar off a moment after a fresh hit turned it back on.
		local hpToken = 0
		local function showHP()
			local frac = math.clamp((MAX_HITS - hits) / MAX_HITS, 0, 1)
			fill.BackgroundColor3 = (frac > 0.5 and Color3.fromRGB(96, 220, 112))
				or (frac > 0.25 and Color3.fromRGB(255, 190, 70))
				or Color3.fromRGB(240, 70, 60)
			bb.Enabled = true
			TS:Create(fill, TweenInfo.new(0.22), { Size = UDim2.fromScale(frac, 1) }):Play()
			hpToken += 1
			local mine = hpToken
			task.delay(HP_SHOW_TIME, function()
				if mine == hpToken and bb.Parent then bb.Enabled = false end
			end)
		end

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

		-- EYES: the imported mesh's eyes are baked in (can't recolor them), so add our
		-- own eyes on the head. Instead of two flat red dots we build a natural eye per
		-- side: a dark glossy eyeball + a bright glowing red iris + a small black pupil.
		do
			local hb = mama:FindFirstChild("Head", true)
			local headMesh = mama:FindFirstChild("Velociraptor3", true) or root
			if hb and hb:IsA("Bone") then
				local base = CFrame.new(hb.WorldCFrame.Position) * mama:GetPivot().Rotation -- head pos, model's facing
				local function eyePart(name, size, color, material, cf)
					local p = Instance.new("Part"); p.Name = name; p.Shape = Enum.PartType.Ball; p.Size = size
					p.Color = color; p.Material = material
					p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
					p.CFrame = cf; p.Parent = mama
					local w = Instance.new("WeldConstraint"); w.Part0 = headMesh; w.Part1 = p; w.Parent = p
					return p
				end
				for _, sgn in ipairs({ 1, -1 }) do
					-- eye socket centre: side + (down into the eye-crease) + forward of the
					-- head. Lowered from +0.5 to +0.1 so the eyes sit flush in the socket
					-- indent on either side of the skull instead of floating above the head.
					local eye = base * CFrame.new(0.6 * sgn, 0.1, -0.78)
					-- eyeball (sclera): dark, glossy, slightly recessed
					eyePart("RaptorEye", Vector3.new(0.5, 0.5, 0.5),
						Color3.fromRGB(24, 12, 12), Enum.Material.SmoothPlastic, eye)
					-- iris: bright glowing red on the outer-front of the eyeball
					eyePart("RaptorEyeIris", Vector3.new(0.34, 0.34, 0.34),
						Color3.fromRGB(255, 40, 40), Enum.Material.Neon,
						eye * CFrame.new(0.10 * sgn, 0.02, -0.16))
					-- pupil: small black dot in the middle of the iris
					eyePart("RaptorEyePupil", Vector3.new(0.15, 0.15, 0.15),
						Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic,
						eye * CFrame.new(0.13 * sgn, 0.02, -0.26))
				end
				print("[Redwood] natural red eyes added on the head (Head bone)")
				print("EYES REPOSITIONED")
			end
		end

		local lastSteal = {}
		RunService.Heartbeat:Connect(function(dt)
			if dead or not mama.Parent then return end
			bobT += dt -- advance the alive bob/sway
			-- CANOPY REJECTION ON THE WANDER RAY TOO (the `homeGY` argument).
			-- Only the initial PLACEMENT passed a nearY, so a walking raptor had no protection
			-- against its down-ray meeting a branch: step under a redwood, the ray hits foliage
			-- 20 studs up, that hit passes the `<= homeGY + 30` band, and the animal is left
			-- standing on thin air. Passing the home's own surface level makes groundY() reject
			-- anything more than CANOPY_CLEARANCE above it and keep descending to real ground.
			local gy = groundY(pos.X, pos.Z, lastGY + 15, 50, homeGY); if gy and gy >= homeGY - 12 and gy <= homeGY + 30 then lastGY = gy end -- stay near island level

			local nearest, nd = nil, DETECT
			for _, plr in ipairs(Players:GetPlayers()) do
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local d = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
					local fromHome = (Vector3.new(hrp.Position.X - home.X, 0, hrp.Position.Z - home.Z)).Magnitude
					if d < nd and fromHome < CHASE_R then nd = d; nearest = plr end
				end
			end

			-- Only ONE raptor may actively chase at a time -> if another already holds
			-- the claim, ignore the player here and keep wandering (players never get swarmed).
			if nearest and not (activeChaser == nil or activeChaser == index) then nearest = nil end

			-- PANIC OVERRIDES EVERYTHING. A raptor that has just been shot is not hunting
			-- anybody, so the chase is dropped (and its claim on the single chase slot
			-- released, or one wounded animal would lock every other raptor out of chasing
			-- for as long as it kept getting hit).
			local panicking = os.clock() < panicUntil
			if panicking then
				nearest = nil
				if activeChaser == index then activeChaser = nil end
			end

			local speed = WANDER_SPD
			if panicking then
				speed = PANIC_SPD
				-- new scatter point several times a second -> darting, not one long sprint
				if os.clock() >= panicNext then
					panicNext = os.clock() + PANIC_TURN
					panicTarget(nil)
				-- reached this one early? bolt again immediately rather than standing still
				elseif (Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)).Magnitude < 2 then
					panicTarget(nil)
				end
			elseif nearest then
				if activeChaser == nil then activeChaser = index end -- claim the single chase slot
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
				if activeChaser == index then activeChaser = nil end -- release the chase claim when not chasing
				-- roam freely: new wander point when we reach the current one OR when the target is a stale
				-- out-of-bounds chase point (so it heads back inside instead of bouncing on the edge)
				local tHome = (Vector3.new(target.X - home.X, 0, target.Z - home.Z)).Magnitude
				if (Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)).Magnitude < 2 or tHome > WANDER_R then newTarget() end
			end

			local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if flat.Magnitude > 0.6 then
				dir = flat.Unit
				local rpF = RaycastParams.new(); rpF.FilterType = Enum.RaycastFilterType.Exclude; rpF.FilterDescendantsInstances = buildIgnore()
				-- Look ahead far enough to clear the raptor's body + the next step, and
				-- check both a low and a higher ray, so it never steps INTO an object
				-- (tree/rock/etc). When blocked it simply doesn't move this frame.
				local ahead = 6 + speed * dt
				local blocked = Workspace:Raycast(Vector3.new(pos.X, lastGY + 1.5, pos.Z), dir * ahead, rpF)
					or Workspace:Raycast(Vector3.new(pos.X, lastGY + 5, pos.Z), dir * ahead, rpF)
				if blocked then
					-- A panicking raptor that runs into a tree picks another escape line
					-- instead of falling back to a calm wander point next to its home.
					if panicking then panicTarget(nil)
					elseif not nearest then newTarget() end
				else
					local nx = pos + dir * speed * dt
					local fh = Vector3.new(nx.X - home.X, 0, nx.Z - home.Z)
					if fh.Magnitude > CHASE_R then nx = Vector3.new(home.X, 0, home.Z) + fh.Unit * CHASE_R end
					-- step only onto SOLID ground AND while staying ON the island (never fall/wander off the edge)
					-- same canopy rejection as the pose ray above: never step ONTO foliage
					local cgy = groundY(nx.X, nx.Z, lastGY + 15, 50, homeGY)
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
			raptorByModel[mama] = nil                            -- stop routing shots to a dead raptor
			if activeChaser == index then activeChaser = nil end -- free the single chase slot
			pcall(function() bb:Destroy() end)

			-- ===== THE DEATH CRY =====
			-- POSITIONAL and on its own anchored emitter, not on the raptor: the body is
			-- pivoted over, faded out and DESTROYED about two seconds from now, and a Sound
			-- dies with its parent -- parenting the cry to `mama` would cut it off mid-roar.
			-- The emitter outlives the corpse and cleans itself up.
			-- Server-side so every player nearby hears it, not just whoever pulled the trigger.
			if root and root.Parent then
				pcall(function()
					local a = Instance.new("Part")
					a.Name = "RaptorDeathCry"
					a.Size = Vector3.new(1, 1, 1)
					a.CFrame = CFrame.new(root.Position)
					a.Transparency = 1
					a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
					a.Parent = Workspace
					local s = Instance.new("Sound")
					s.Name = "RaptorDeath"
					s.SoundId = "rbxassetid://244510423"
					s.Volume = 1.6
					s.RollOffMode = Enum.RollOffMode.Linear
					s.RollOffMinDistance = 40    -- full volume anywhere in the clearing
					s.RollOffMaxDistance = 320   -- gone by the time you are off Redwood Ridge
					s.Parent = a
					s:Play()
					-- task.delay, not Debris: this file has no Debris local and uses delay
					-- for its other self-cleaning parts. 8s is well clear of the clip.
					task.delay(8, function() pcall(function() a:Destroy() end) end)
				end)
			end
			-- announce whether THIS raptor was hiding the secret egg
			if root and root.Parent then
				if hasEgg then floaty(root, "\xF0\x9F\xA5\x9A The secret egg!", Color3.fromRGB(235, 205, 150))
				else floaty(root, "No egg here\xE2\x80\xA6", Color3.fromRGB(225, 225, 225)) end
			end
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
				if hasEgg then spawnEgg(dp.X, dp.Z) end -- only the secret raptor drops the egg
			end)
		end

		-- Route shots at THIS raptor to its own hit handler; the central RaptorShot
		-- dispatcher below calls it based on the model the client reported hitting.
		raptorByModel[mama] = function(shooter: Player?)
			if dead or not mama.Parent then return end
			hits += 1
			pcall(showHP)   -- this raptor's bar only; the other four stay hidden
			pcall(function()
				local b = mama:FindFirstChild("Body")
				if b then local c = b.Color; b.Color = Color3.fromRGB(255, 90, 90); task.delay(0.12, function() if b.Parent then b.Color = c end end) end
			end)

			-- BOLT. Re-armed on every hit, so keeping the pressure on keeps it running.
			-- The first scatter point is thrown immediately and biased AWAY from whoever
			-- fired -- waiting for the next PANIC_TURN tick would leave it standing in the
			-- open for a third of a second looking like the shot missed.
			panicUntil = os.clock() + PANIC_TIME
			panicNext  = os.clock() + PANIC_TURN
			local from
			local shooterChar = shooter and shooter.Character
			local shooterHrp = shooterChar and shooterChar:FindFirstChild("HumanoidRootPart")
			if shooterHrp and shooterHrp:IsA("BasePart") then from = shooterHrp.Position end
			panicTarget(from)

			if hits >= MAX_HITS then killMama() end
		end
	end -- spawnRaptor

	-- Central shot dispatcher: the client passes the raptor MODEL it hit, so the hit
	-- is applied to that specific raptor (not all of them at once).
	RaptorShot.OnServerEvent:Connect(function(plr, model)
		local onHit = typeof(model) == "Instance" and raptorByModel[model]
		-- the shooter is passed through so the raptor can bolt AWAY from them rather than
		-- picking a random direction that might run it straight at the gun
		if onHit then onHit(plr) end
	end)

	-- Spawn the 5 raptors on island6; ONE holds the secret egg. Each raptor is placed
	-- on a "putdino" part (one per part); they then wander near that home but their
	-- forward look-ahead keeps them from walking inside trees/rocks/other objects.
	if raptorSpot then
		local RAPTOR_COUNT = #RAPTOR_PALETTES
		local secretIndex = math.random(1, RAPTOR_COUNT)
		local i6cf, i6size = island6:GetBoundingBox()
		local i6cx, i6cz = i6cf.Position.X, i6cf.Position.Z
		local i6hx, i6hz = math.max(6, i6size.X / 2 - 12), math.max(6, i6size.Z / 2 - 12)
		-- true only if (x,z) is over island6's OWN ground (an Include ray hits island6)
		local groundRP = RaycastParams.new()
		groundRP.FilterType = Enum.RaycastFilterType.Include
		groundRP.FilterDescendantsInstances = { island6 }
		groundRP.IgnoreWater = true
		local function onIslandGround(x, z)
			if math.abs(x - i6cx) > i6hx or math.abs(z - i6cz) > i6hz then return false end
			return Workspace:Raycast(Vector3.new(x, raptorSpot.Position.Y + 80, z), Vector3.new(0, -300, 0), groundRP) ~= nil
		end

		-- Place one raptor on each part named "putdino" on island6 (ghosted so it
		-- doesn't block the raptor's grounding). There are 5, one per raptor. If fewer
		-- than 5 are found, the remaining raptors are spread on island ground below.
		-- Each home records a reference elevation `y` (its marker's own height) so the
		-- raptor grounds from ITS marker's level -- a marker on a rise/rock grounds
		-- correctly instead of every raptor using RaptorSpot's height.
		local homes = {}
		local spots = {}
		for _, d in ipairs(island6:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower():sub(1, 7) == "putdino" then
				d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
				ignoreForGround[#ignoreForGround + 1] = d
				spots[#spots + 1] = d
			end
		end
		for _, s in ipairs(spots) do
			if #homes >= RAPTOR_COUNT then break end
			homes[#homes + 1] = { x = s.Position.X, z = s.Position.Z, y = s.Position.Y }
		end
		if #spots == 0 then
			warn("[Redwood] no 'putdino' part on island6 -> spreading raptors on island ground")
		else
			print(("[Redwood] placing raptors on %d 'putdino' part(s) on island6"):format(#spots))
		end

		-- Spread any remaining raptors (only if fewer than 5 'putdino' parts) on island6
		-- ground, each kept at least MIN_SEP studs from the others so nothing overlaps.
		local MIN_SEP = 18
		local function gather(enforceSep)
			for _ = 1, 150 do
				if #homes >= RAPTOR_COUNT then return end
				local x = i6cx + (math.random() * 2 - 1) * i6hx
				local z = i6cz + (math.random() * 2 - 1) * i6hz
				if onIslandGround(x, z) then
					local ok = true
					if enforceSep then
						for _, h in ipairs(homes) do
							if (Vector3.new(x - h.x, 0, z - h.z)).Magnitude < MIN_SEP then ok = false; break end
						end
					end
					if ok then homes[#homes + 1] = { x = x, z = z, y = raptorSpot.Position.Y } end
				end
			end
		end
		gather(true)  -- prefer spread-out homes
		gather(false) -- fill any remaining with on-island ground (spacing relaxed)
		while #homes < RAPTOR_COUNT do
			homes[#homes + 1] = { x = raptorSpot.Position.X, z = raptorSpot.Position.Z, y = raptorSpot.Position.Y }
		end

		for i = 1, RAPTOR_COUNT do
			spawnRaptor(i, RAPTOR_PALETTES[i], i == secretIndex, homes[i].x, homes[i].z, homes[i].y)
			task.wait(0.05)
		end
		print(("[Redwood] 5 raptors spawned on island6 -- secret egg on raptor #%d"):format(secretIndex))
		print("RAPTORS GROUNDED")
	end

	-- ===== BIG SNIPER LOCKER at SniperSpot =====
	if sniperSpot then
		local sp = sniperSpot.Position

		-- ===== THE LOCKER STANDS ON THE MARKER, NOT ON A RAYCAST =====
		-- This used to ground itself with `groundY(sp.X, sp.Z, sp.Y + 120, 400)` and build at
		-- that height, which is why it kept turning up somewhere other than the block you put
		-- down. Two ways that goes wrong on THIS island in particular:
		--
		--   1. THE MARKER IS INVISIBLE TO THE RAY. SniperSpot has CanQuery = false (set with
		--      RaptorSpot up at the top), so the ray passes straight through it and reports
		--      whatever is underneath. Put the marker on a ledge, a rock or a platform and the
		--      locker drops to the floor below it.
		--   2. NO CANOPY REJECTION. This call passes no `nearY`, so unlike the raptors it has
		--      no protection against the ray meeting a BRANCH on the way down -- and Redwood
		--      Ridge is the tall-tree island. A marker under foliage put the locker up in it.
		--
		-- The marker is the authority now: the cabinet's base sits on the marker's TOP FACE,
		-- so it lands exactly where you place the block and follows it when you move it. The
		-- ground ray is still taken, but only to PRINT alongside -- if the two ever disagree
		-- wildly the log says so instead of the locker silently wandering off.
		local markerTop = sp.Y + sniperSpot.Size.Y / 2
		local rayY = groundY(sp.X, sp.Z, sp.Y + 120, 400)
		local gy = markerTop
		local locker = Instance.new("Model"); locker.Name = "SniperLocker"; locker.Parent = Workspace
		ignoreForGround[#ignoreForGround + 1] = locker
		local STEELC, DARKC = Color3.fromRGB(78, 84, 94), Color3.fromRGB(48, 52, 60)
		-- ===== THE LOCKER FACES THE MARKER'S +Z FACE =====
		-- This was `CFrame.Angles(0, math.rad(180), 0)` -- a hardcoded half turn that threw
		-- away the marker's own rotation entirely. However you turned SniperSpot in Studio the
		-- locker came out pointing the same way, and that way was world -Z (the 180 flips the
		-- default CFrame's -Z look round, and the glass hangs off local +Z).
		--
		-- Now it inherits the marker's YAW, so the front face -- the glass with the rifles
		-- behind it -- sits on the marker's +Z side and you aim the locker by rotating the
		-- block. Every panel below is already positioned in base-local space with the glass at
		-- +Z and the back panel at -Z, so nothing else had to move.
		--
		-- YAW ONLY, deliberately: pitch and roll are dropped so a marker left tilted in Studio
		-- still produces a locker standing upright on the ground instead of one lying over.
		-- HALF TURN ON TOP OF THE MARKER'S YAW. Putting the glass on the marker's +Z put the
		-- cabinet the wrong way round in game, so it gets spun to face the other face. This is
		-- one number: set it to 0 to put the glass back on +Z, 180 to keep it on -Z.
		local LOCKER_FACE_OFFSET = 180
		local _mx, markerYaw = sniperSpot.CFrame:ToEulerAnglesYXZ()
		markerYaw = markerYaw + math.rad(LOCKER_FACE_OFFSET)
		local base = CFrame.new(sp.X, gy + 3.0, sp.Z) * CFrame.Angles(0, markerYaw, 0)
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
		-- The feet were the one pair placed in WORLD space, which was harmless while the
		-- rotation was a hardcoded constant and wrong the moment it became the marker's --
		-- the cabinet would turn and leave its legs behind. Base-local now, like everything
		-- else. -2.6 puts them back at gy+0.4 (base sits at gy+3.0).
		lp("Feet1",  Vector3.new(0.5, 0.8, 0.5), DARKC,  base * CFrame.new(-1.9, -2.6, 0))
		lp("Feet2",  Vector3.new(0.5, 0.8, 0.5), DARKC,  base * CFrame.new( 1.9, -2.6, 0))
		local glass = lp("Glass", Vector3.new(4.6, 5.6, 0.12), Color3.fromRGB(150, 200, 230), base * CFrame.new(0, 0, 1.05), Enum.Material.Glass, false)
		glass.Transparency = 0.55; glass.Reflectance = 0.15
		for i = -1, 1 do
			lp("RifleDecor", Vector3.new(0.22, 3.4, 0.2), Color3.fromRGB(40, 42, 48), base * CFrame.new(i * 1.1, 0.6, 0.2) * CFrame.Angles(0, 0, math.rad(6)), Enum.Material.Metal, false)
			lp("RifleBarrel", Vector3.new(0.14, 2.0, 0.14), Color3.fromRGB(70, 74, 82), base * CFrame.new(i * 1.1 + 0.12, 1.5, 0.2), Enum.Material.Metal, false)
		end
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(180, 220, 255); pl.Brightness = 1.4; pl.Range = 14; pl.Parent = locker:FindFirstChild("Top")
		-- ===== NO FLOATING "Sniper Locker" SIGN =====
		-- A billboard hanging over the cabinet was doing the job of navigation: it advertised
		-- the locker through the trees from 140 studs out, so there was nothing to find. Every
		-- other quest on this tower guides you with the green chevron runway on the ground
		-- instead, and island6 now does the same -- RedwoodRaptor.client lays a trail to the
		-- locker the moment the RidgeWarden hands the job over. The PointLight on the cabinet
		-- stays: that is the locker lighting ITSELF, not a label pointing at it.

		local prompt = Instance.new("ProximityPrompt"); prompt.ActionText = "Grab Sniper"; prompt.ObjectText = "Sniper Locker"
		prompt.HoldDuration = 0.3; prompt.MaxActivationDistance = 14; prompt.RequiresLineOfSight = false; prompt.Parent = glass
		prompt.Triggered:Connect(function(plr)
			-- QUEST GATE: the RidgeWarden hands this job out, same as every other island.
			--
			-- island6 was the ONE quest with no gate at all -- the locker handed out a rifle
			-- to anyone who walked past, so the raptors could be hunted without ever meeting
			-- the RidgeWarden and he was decorative. Gating the LOCKER rather than the trigger
			-- is what makes this cheap: no sniper means no shooting, so one check covers the
			-- whole quest and the player is never left clicking a gun that silently refuses.
			if plr:GetAttribute("Island6QuestAccepted") ~= true then
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if hrp then floaty(hrp, "Talk to the RidgeWarden first!", Color3.fromRGB(255, 210, 120)) end
				return
			end
			local bp = plr:FindFirstChildOfClass("Backpack")
			local has = (plr.Character and plr.Character:FindFirstChild("Sniper")) or (bp and bp:FindFirstChild("Sniper"))
			if has then return end
			local t = buildSniperTool(); t.Parent = bp or plr.Character
		end)
		print(("[Redwood] Big Sniper Locker built ON SniperSpot at (%.1f, %.1f, %.1f) -- marker top %.1f, "
			.. "facing its +Z (yaw %.0f deg). Ground ray said %s%s")
			:format(sp.X, gy, sp.Z, markerTop, math.deg(markerYaw),
				rayY and ("%.1f"):format(rayY) or "nothing",
				(rayY and math.abs(rayY - markerTop) > 6)
					and ("  <== %.1f studs apart; the marker is not sitting on the floor"):format(rayY - markerTop)
					or ""))
	end
end)
