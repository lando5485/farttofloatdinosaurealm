--======================================================================
-- RedwoodRaptor.client.luau  (LocalScript)
--======================================================================
-- Island6 raptor hunt, client half:
--   * Hold the "Sniper" tool. RIGHT-CLICK to scope (zoom + scope overlay), LEFT-CLICK to fire.
--     When scoped we shoot from the screen centre; otherwise from the mouse. A hit on the
--     MamaRaptor tells the server (RaptorShot).
--   * On RedwoodRaptorHatch -> spawn the Velociraptor follower + add the Pet Hub card + grant it.
--======================================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local TS         = game:GetService("TweenService")
local Debris     = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")
local HatchBurst = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst")) -- shared cool hatch FX

local player    = Players.LocalPlayer
local cam       = workspace.CurrentCamera
local PlayerGui = player:WaitForChild("PlayerGui")

local RaptorShot    = RS:WaitForChild("RaptorShot", 30)
local RedwoodHatch  = RS:WaitForChild("RedwoodRaptorHatch", 30)
local RaptorHatched = RS:FindFirstChild("RaptorHatched") or RS:WaitForChild("RaptorHatched", 30)

local BASE_FOV, SCOPE_FOV = 70, 22
-- Aim sensitivity down the scope. Lower = steadier/less twitchy (was effectively 1.0).
-- Roughly matches the zoom ratio so the reticle doesn't fly across a zoomed-in target.
local SCOPE_SENSITIVITY = 0.28

-- ===== scope overlay GUI =====
local sg = Instance.new("ScreenGui"); sg.Name = "SniperScope"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
sg.DisplayOrder = 200; sg.Enabled = false; sg.Parent = PlayerGui
local dim = Instance.new("Frame"); dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 0.55; dim.BorderSizePixel = 0; dim.Parent = sg
local ring = Instance.new("Frame"); ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromScale(0.5, 0.5)
ring.BackgroundTransparency = 1; ring.Parent = sg
Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
local rs = Instance.new("UIStroke", ring); rs.Color = Color3.new(0, 0, 0); rs.Thickness = 6
local function sizeRing()
	local vp = cam.ViewportSize; local d = math.min(vp.X, vp.Y) * 0.8
	ring.Size = UDim2.fromOffset(d, d)
end
sizeRing(); cam:GetPropertyChangedSignal("ViewportSize"):Connect(sizeRing)
-- crosshair (thin lines + centre dot)
local function line(w, h) local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h); f.BackgroundColor3 = Color3.new(0, 0, 0); f.BorderSizePixel = 0; f.Parent = sg end
line(2, 9999); line(9999, 2)
local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6); dot.BackgroundColor3 = Color3.fromRGB(255, 60, 60); dot.BorderSizePixel = 0; dot.Parent = sg
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

-- hide ALL on-screen HUD while scoped (leave only the scope); restore on unscope
local hiddenGuis = {}
local function hideHUD(on)
	if on then
		hiddenGuis = {}
		for _, g in ipairs(PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= sg and g.Enabled then g.Enabled = false; hiddenGuis[#hiddenGuis + 1] = g end
		end
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	else
		for _, g in ipairs(hiddenGuis) do if g and g.Parent then g.Enabled = true end end
		hiddenGuis = {}
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
	end
end

-- ===== state =====
local function holdingSniper()
	local char = player.Character
	local t = char and char:FindFirstChildOfClass("Tool")
	return t and t.Name == "Sniper"
end

local scoped = false
local function setScope(on)
	if on == scoped then return end
	if on and not holdingSniper() then return end
	scoped = on
	sg.Enabled = on
	-- force FIRST PERSON down the scope (so you aim where the barrel points, not at your own head)
	player.CameraMode = on and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	hideHUD(on) -- only the scope shows while aiming
	-- hide the GUN model while looking through the optic (LocalTransparencyModifier = client-only)
	local ch = player.Character; local t0 = ch and ch:FindFirstChild("Sniper")
	if t0 then for _, d in ipairs(t0:GetDescendants()) do if d:IsA("BasePart") then d.LocalTransparencyModifier = on and 1 or 0 end end end
	TS:Create(cam, TweenInfo.new(0.18), { FieldOfView = on and SCOPE_FOV or BASE_FOV }):Play()
	-- steady the aim while scoped; restore full sensitivity when un-scoped
	UIS.MouseDeltaSensitivity = on and SCOPE_SENSITIVITY or 1
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = on and 8 or 16 end
end

-- Return the raptor MODEL that `inst` belongs to, or nil. Raptors are tagged with
-- the "RedwoodRaptor" attribute (their names vary), so we detect by that -- and we
-- must tell the server WHICH raptor was hit, so we pass this model.
local function mamaModelOf(inst)
	local m = inst
	while m do if m:IsA("Model") and m:GetAttribute("RedwoodRaptor") then return m end; m = m.Parent end
	return nil
end

-- bright tracer round from the muzzle to the impact
local function tracer(a, b)
	if (b - a).Magnitude < 0.5 then return end
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = Color3.fromRGB(255, 230, 150); p.Transparency = 0.15
	p.Size = Vector3.new(0.1, 0.1, (b - a).Magnitude); p.CFrame = CFrame.lookAt((a + b) / 2, b); p.Parent = workspace
	Debris:AddItem(p, 0.09)
end
local function muzzleFlash(pos)
	local f = Instance.new("Part"); f.Shape = Enum.PartType.Ball; f.Size = Vector3.new(0.7, 0.7, 0.7); f.Color = Color3.fromRGB(255, 220, 120)
	f.Material = Enum.Material.Neon; f.Anchored = true; f.CanCollide = false; f.CanQuery = false; f.CastShadow = false; f.Transparency = 0.2; f.CFrame = CFrame.new(pos); f.Parent = workspace
	local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255, 220, 120); pl.Brightness = 6; pl.Range = 14; pl.Parent = f
	Debris:AddItem(f, 0.08)
end
local function recoil(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local up = scoped and 0.38 or 0.2 -- bigger jolt through the scope
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * 0.12, up, 0.55) -- kick up + back
		TS:Create(hum, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CameraOffset = Vector3.zero }):Play()
	end
	local fov = scoped and SCOPE_FOV or BASE_FOV
	cam.FieldOfView = fov + 4
	TS:Create(cam, TweenInfo.new(0.22), { FieldOfView = fov }):Play()
	if scoped then -- kick the OPTICAL: the reticle jumps up then settles
		ring.Position = UDim2.new(0.5, 0, 0.5, -28); dot.Position = UDim2.new(0.5, 0, 0.5, -28)
		TS:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
		TS:Create(dot, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end
end

local lastShot = 0
local function shoot()
	if not holdingSniper() then return end
	if os.clock() - lastShot < 0.5 then return end
	lastShot = os.clock()
	local char = player.Character
	local origin, dirv
	if scoped then
		origin = cam.CFrame.Position; dirv = cam.CFrame.LookVector * 1000 -- straight down the scope
	else
		local mp = UIS:GetMouseLocation(); local ray = cam:ViewportPointToRay(mp.X, mp.Y)
		origin = ray.Origin; dirv = ray.Direction * 1000
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(origin, dirv, rp)
	-- shot FX: muzzle flash + tracer (from the gun's muzzle) + recoil kick + crack sound
	local tool = char and char:FindFirstChild("Sniper")
	local muzzle = tool and tool:FindFirstChild("Muzzle")
	local startPos
	if scoped then
		startPos = (cam.CFrame * CFrame.new(0.3, -0.25, -1.3)).Position -- fire from inside the scope view
	else
		startPos = (muzzle and muzzle.Position) or (cam.CFrame.Position + cam.CFrame.LookVector * 2)
	end
	local endPos = (hit and hit.Position) or (origin + dirv)
	muzzleFlash(startPos); tracer(startPos, endPos); recoil(char)
	if scoped then -- guaranteed flash IN the optic (the world flash can be clipped at scope zoom)
		local fl = Instance.new("Frame"); fl.Size = UDim2.fromScale(1, 1); fl.BackgroundColor3 = Color3.fromRGB(255, 235, 160)
		fl.BackgroundTransparency = 0.4; fl.BorderSizePixel = 0; fl.ZIndex = 50; fl.Parent = sg
		TS:Create(fl, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play(); Debris:AddItem(fl, 0.2)
	end
	pcall(function() local s = Instance.new("Sound"); s.SoundId = "rbxassetid://9114065998"; s.Volume = 0.7; s.Parent = cam; s:Play(); Debris:AddItem(s, 1) end)
	local hitMama = hit and hit.Instance and mamaModelOf(hit.Instance)
	if hitMama then
		RaptorShot:FireServer(hitMama) -- tell the server WHICH raptor was hit
	end
end

UIS.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.UserInputType == Enum.UserInputType.MouseButton2 then setScope(true)
	elseif io.UserInputType == Enum.UserInputType.MouseButton1 then shoot() end
end)
UIS.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton2 then setScope(false) end
end)

-- drop the scope if the sniper is unequipped / character changes
task.spawn(function()
	while true do
		if scoped and not holdingSniper() then setScope(false) end
		task.wait(0.3)
	end
end)
player.CharacterAdded:Connect(function() scoped = false; sg.Enabled = false; cam.FieldOfView = BASE_FOV; player.CameraMode = Enum.CameraMode.Classic; UIS.MouseDeltaSensitivity = 1; hideHUD(false) end)

-- ===== TARGET LOCK: outline the Mama Raptor + light up the reticle when your
-- aim is actually on her, so it's obvious what you're about to shoot. =====
local RunSvc = game:GetService("RunService")
local lockHL = Instance.new("Highlight")
lockHL.Name = "RaptorTargetLock"
lockHL.FillColor = Color3.fromRGB(255, 55, 55)
lockHL.FillTransparency = 0.55
lockHL.OutlineColor = Color3.fromRGB(255, 30, 30)
lockHL.OutlineTransparency = 0
lockHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- readable even through brush
lockHL.Enabled = false
lockHL.Parent = PlayerGui

local DOT_IDLE, DOT_LOCK = Color3.fromRGB(255, 60, 60), Color3.fromRGB(60, 255, 90)

-- Raycast down the current aim (scope center or mouse) and return the hit.
local function aimHit()
	local char = player.Character
	local origin, dirv
	if scoped then
		origin = cam.CFrame.Position; dirv = cam.CFrame.LookVector * 1000
	else
		local mp = UIS:GetMouseLocation(); local ray = cam:ViewportPointToRay(mp.X, mp.Y)
		origin = ray.Origin; dirv = ray.Direction * 1000
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	return workspace:Raycast(origin, dirv, rp)
end

RunSvc.RenderStepped:Connect(function()
	if not holdingSniper() then
		if lockHL.Enabled then lockHL.Enabled = false; lockHL.Adornee = nil end
		return
	end
	local hit = aimHit()
	local mdl = hit and hit.Instance and mamaModelOf(hit.Instance) -- the SPECIFIC raptor under the aim
	if mdl then
		lockHL.Adornee = mdl
		lockHL.Enabled = true
		dot.BackgroundColor3 = DOT_LOCK
		dot.Size = UDim2.fromOffset(11, 11)
	else
		lockHL.Enabled = false; lockHL.Adornee = nil
		dot.BackgroundColor3 = DOT_IDLE
		dot.Size = UDim2.fromOffset(6, 6)
	end
end)

-- ===== hatch -> the PET =====
RedwoodHatch.OnClientEvent:Connect(function(cf)
	if typeof(cf) == "CFrame" then HatchBurst.play(cf.Position + Vector3.new(0,1,0), Color3.fromRGB(235,205,150)) end -- COOL hatch explosion
	if _G.SpawnRaptorFollower then pcall(function() _G.SpawnRaptorFollower(cf) end) end
	if _G.PetHubAddPet then
		pcall(function()
			_G.PetHubAddPet("RaptorPet", { petId = "RaptorPet", displayName = "Velociraptor", level = 1, xp = 0, xpNeed = 100, maxLevel = 25, milestone = "Newly hatched!" })
		end)
	end
	if RaptorHatched then pcall(function() RaptorHatched:FireServer() end) end
	print("[Redwood] hatched the Velociraptor -> follower + Pet Hub")
end)

-- ===== LIVING RAPTORS: animate EVERY raptor's bones locally (server only moves the
-- bodies; Bone.Transform doesn't replicate, so each client must drive it) -- tail
-- swish + leg walk + head bob. Runs for all 5 raptors, current and future. =====
task.spawn(function()
	local RunService = game:GetService("RunService")

	-- Drive one raptor model's bones. Same motion for every raptor, with a per-raptor
	-- phase offset so they don't all sway in robotic lockstep.
	local function animateRaptor(mama)
		local function bone(n) local b = mama:FindFirstChild(n, true); return (b and b:IsA("Bone")) and b or nil end
		local tailB = {}; for i = 1, 5 do tailB[i] = bone("Tail" .. i) end
		-- diagonal gait: front-right + back-left in phase, front-left + back-right opposite
		local legB = {
			{ bone("FrontUpLeg.R"), 0.0 }, { bone("FrontLowLeg.R"), 0.5 },
			{ bone("BackUpLeg.L"),  0.0 }, { bone("BackLowLeg.L"),  0.5 },
			{ bone("FrontUpLeg.L"), math.pi }, { bone("FrontLowLeg.L"), math.pi + 0.5 },
			{ bone("BackUpLeg.R"),  math.pi }, { bone("BackLowLeg.R"),  math.pi + 0.5 },
		}
		local neckB, headB, torsoB = bone("Neck"), bone("Head"), bone("Torso")
		local t, walkT, moveTimer, gaitW = math.random() * 10, 0, 0, 0 -- random start phase = desync
		local prev = mama:GetPivot().Position
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not mama.Parent then conn:Disconnect(); return end
			dt = math.min(dt, 1/30) -- clamp so a frame hitch can't jolt the pose
			t += dt
			local now = mama:GetPivot().Position
			if (Vector3.new(now.X - prev.X, 0, now.Z - prev.Z)).Magnitude > 0.02 then moveTimer = 0.4 end
			prev = now
			moveTimer = math.max(0, moveTimer - dt)
			local moving = moveTimer > 0 -- stays true between throttled position updates so the legs keep walking
			-- ease the walk<->idle blend so the gait starts and stops smoothly (no snapping)
			gaitW += ((moving and 1 or 0) - gaitW) * math.min(dt * 7, 1)
			walkT += dt * (5 + 4 * gaitW)             -- stride a touch quicker at full walk
			local breath = math.sin(t * 1.5)          -- slow idle breathing

			-- tail: a travelling wave (vertical + horizontal), livelier while walking for balance
			local tailAmp = math.rad(10 + 9 * gaitW)
			for i, b in ipairs(tailB) do
				if b then b.Transform = CFrame.Angles(
					math.sin(t * (2 + gaitW) - i * 0.6) * math.rad(3),
					math.sin(t * (3 + gaitW) - i * 0.7) * tailAmp, 0) end
			end
			-- neck + head: organic scanning; dips slightly forward-down as she walks
			if neckB then neckB.Transform = CFrame.Angles(
				math.sin(t * 1.3) * math.rad(3) + gaitW * math.rad(5),
				math.sin(t * 0.9) * math.rad(8), math.sin(t * 1.1) * math.rad(2)) end
			if headB then headB.Transform = CFrame.Angles(
				math.sin(t * 2.0) * math.rad(3) - gaitW * math.rad(4),
				math.sin(t * 0.7) * math.rad(5), 0) end
			-- torso: subtle vertical stride-bob + roll sway, plus gentle idle breathing
			if torsoB then
				local bob = math.sin(walkT * 2) * 0.05 * gaitW + breath * 0.015 * (1 - gaitW)
				torsoB.Transform = CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, math.sin(walkT) * math.rad(3 + 3 * gaitW))
			end
			-- legs: diagonal walk cycle, amplitude eased in/out by the gait blend
			local amp = math.rad(32) * gaitW
			for _, e in ipairs(legB) do
				local b, ph = e[1], e[2]
				if b then b.Transform = CFrame.Angles(math.sin(walkT + ph) * amp, 0, 0) end
			end
		end)
	end

	-- Discover every raptor (each tagged with the "RedwoodRaptor" attribute, parented
	-- to Workspace) as it streams in, and animate it once.
	local seen = {}
	local function tryAnimate(inst)
		if inst:IsA("Model") and inst:GetAttribute("RedwoodRaptor") and not seen[inst] then
			seen[inst] = true
			task.spawn(function() task.wait(0.2); animateRaptor(inst) end) -- let bones replicate first
		end
	end
	for _, c in ipairs(workspace:GetChildren()) do tryAnimate(c) end
	workspace.ChildAdded:Connect(tryAnimate)
	print("[Redwood] raptor bone animation running for all raptors (tail/legs/head)")
end)

print("[Redwood] client ready -- RIGHT-CLICK to scope, LEFT-CLICK to fire")
