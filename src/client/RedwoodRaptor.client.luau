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
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = on and 8 or 16 end
end

local function isMama(inst)
	local m = inst
	while m do if m.Name == "MamaRaptor" then return true end; m = m.Parent end
	return false
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
	if hit and hit.Instance and isMama(hit.Instance) then
		RaptorShot:FireServer()
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
player.CharacterAdded:Connect(function() scoped = false; sg.Enabled = false; cam.FieldOfView = BASE_FOV; player.CameraMode = Enum.CameraMode.Classic; hideHUD(false) end)

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

-- ===== LIVING RAPTOR: animate the Mama Raptor's bones locally (server only moves its body;
-- Bone.Transform doesn't replicate, so each client must drive it) -- tail swish + leg walk + head bob =====
task.spawn(function()
	local RunService = game:GetService("RunService")
	local mama = workspace:WaitForChild("MamaRaptor", 90)
	if not mama then return end
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
	local t, walkT, moveTimer = 0, 0, 0
	local prev = mama:GetPivot().Position
	RunService.RenderStepped:Connect(function(dt)
		if not mama.Parent then return end
		t += dt
		local now = mama:GetPivot().Position
		if (Vector3.new(now.X - prev.X, 0, now.Z - prev.Z)).Magnitude > 0.02 then moveTimer = 0.4 end
		prev = now
		moveTimer = math.max(0, moveTimer - dt)
		local moving = moveTimer > 0 -- stays true between throttled position updates so the legs keep walking
		if moving then walkT += dt * 9 end
		-- tail: travelling side-to-side wave
		for i, b in ipairs(tailB) do if b then b.Transform = CFrame.Angles(0, math.sin(t * 4 - i * 0.7) * math.rad(13), 0) end end
		-- head + neck: gentle scan/bob
		if neckB then neckB.Transform = CFrame.Angles(math.sin(t * 1.6) * math.rad(4), math.sin(t * 1.1) * math.rad(7), 0) end
		if headB then headB.Transform = CFrame.Angles(math.sin(t * 2.2) * math.rad(4), 0, 0) end
		if torsoB then torsoB.Transform = CFrame.Angles(0, 0, math.sin(walkT) * (moving and math.rad(4) or 0)) end
		-- legs: walk cycle (only while moving)
		local amp = moving and math.rad(34) or 0
		for _, e in ipairs(legB) do local b, ph = e[1], e[2]; if b then b.Transform = CFrame.Angles(math.sin(walkT + ph) * amp, 0, 0) end end
	end)
	print("[Redwood] mama bone animation running (tail/legs/head)")
end)

print("[Redwood] client ready -- RIGHT-CLICK to scope, LEFT-CLICK to fire")
