--======================================================================
-- GeyserQuest.client.luau  (LocalScript)  -- Island 8 "Volcanic Vista" quest
--======================================================================
-- The volcano is about to erupt and wipe out the dinos! Six geysers (the user's
-- parts Geyser1..Geyser6) blast lava/steam. The player must PLUG every geyser:
--   1. Walk to a geyser -> [E] Plug Geyser -> a "PLUG IT!" tap mini-game.
--   2. Tap to shove a boulder in -> the geyser caps off, plume stops.
--   3. Plug all 6 -> the volcano calms -> a T-Rex egg appears (EggSpot8) -> hatch.
-- A red danger vignette fades as the pressure drops with each plug.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")
local player     = Players.LocalPlayer
local HatchBurst = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst"))

local CONFIG = {
	islandName    = "island8",
	count         = 6,            -- Geyser1..Geyser6
	tapsToPlug    = 6,            -- taps to plug one geyser
	plugTime      = 6,            -- seconds before the boulder pops back out
	petId         = "TyrannosaurusPet",
	petName       = "T-Rex",
	spawnFollower = "SpawnTyrannosaurusFollower",
	hatchEvent    = "TyrannosaurusHatched",
}

local st = { plugged = 0, busy = false, done = false, hatching = false, owns = false }
print("[Geyser] script loaded")

local function floatText(pos, text, color)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,220,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.MaxDistance=140; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=color or Color3.fromRGB(255,180,90); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.6, function() a:Destroy() end)
end

-- ===== HUD: counter + red danger vignette (fades as pressure drops) =====
local hudLbl, vignette
local function buildHUD()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "GeyserHUD"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 60; g.Parent = pgui
	vignette = Instance.new("Frame"); vignette.Size = UDim2.new(1,0,1,0); vignette.BackgroundColor3 = Color3.fromRGB(200,40,20)
	vignette.BackgroundTransparency = 0.82; vignette.BorderSizePixel = 0; vignette.ZIndex = 1; vignette.Parent = g
	local grad = Instance.new("UIGradient"); grad.Rotation = 90; grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.2), NumberSequenceKeypoint.new(0.5,1), NumberSequenceKeypoint.new(1,0.2) }); grad.Parent = vignette
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0); f.Position = UDim2.new(0.5,0,0,92); f.Size = UDim2.fromOffset(260,40)
	f.BackgroundColor3 = Color3.fromRGB(70,46,40); f.BackgroundTransparency = 0.1; f.ZIndex = 2; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,12); local s = Instance.new("UIStroke", f); s.Color = Color3.fromRGB(255,140,40); s.Thickness = 2
	hudLbl = Instance.new("TextLabel"); hudLbl.Size = UDim2.new(1,0,1,0); hudLbl.BackgroundTransparency = 1; hudLbl.ZIndex = 2
	hudLbl.Font = Enum.Font.FredokaOne; hudLbl.TextScaled = true; hudLbl.TextColor3 = Color3.fromRGB(255,225,180); hudLbl.Parent = f
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 20; c.Parent = hudLbl end
	-- subtle danger pulse
	task.spawn(function() while vignette and vignette.Parent and not st.done do
		local base = 0.82 + 0.13 * (st.plugged / CONFIG.count)
		vignette.BackgroundTransparency = base + 0.05*math.sin(os.clock()*3); task.wait(0.05) end end)
	-- only show the HUD while the player is ON island8
	task.spawn(function()
		while g.Parent do
			local isl = Workspace:FindFirstChild(CONFIG.islandName)
			local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local on = false
			if isl and hrp then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok then local d = hrp.Position - cf.Position; on = math.abs(d.X) <= size.X/2 + 35 and math.abs(d.Z) <= size.Z/2 + 35 and math.abs(d.Y) <= size.Y/2 + 80 end -- Y too (islands stack vertically)
			end
			g.Enabled = on and not st.owns
			task.wait(0.5)
		end
	end)
end
local function updateHUD()
	if hudLbl then hudLbl.Text = ("\xF0\x9F\x8C\x8B  Geysers: %d / %d"):format(st.plugged, CONFIG.count) end
end

-- ===== PLUG mini-game (tap fast; modal so it works anywhere) =====
local function openPlugMinigame(onDone)
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "PlugGui"; g.ResetOnSpawn = false; g.DisplayOrder = 210; g.Parent = pgui
	local dim = Instance.new("TextButton"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false; dim.Text = ""; dim.Modal = true; dim.Active = true; dim.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromOffset(300,230); panel.Position = UDim2.fromScale(0.5,0.5); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(70,46,40); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(255,140,40); ps.Thickness = 3
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-20,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255,225,180); title.Text = "PLUG THE GEYSER!"; title.Parent = panel
	local plug = Instance.new("TextButton"); plug.Size = UDim2.fromOffset(160,108); plug.Position = UDim2.new(0.5,0,0,56); plug.AnchorPoint = Vector2.new(0.5,0)
	plug.BackgroundColor3 = Color3.fromRGB(150,90,60); plug.Font = Enum.Font.FredokaOne; plug.TextScaled = true; plug.TextColor3 = Color3.new(1,1,1); plug.Text = "\xF0\x9F\xAA\xA8  PLUG!"; plug.Parent = panel
	Instance.new("UICorner", plug).CornerRadius = UDim.new(0,14); Instance.new("UIStroke", plug).Color = Color3.fromRGB(60,40,30)
	local barBg = Instance.new("Frame"); barBg.Size = UDim2.new(1,-40,0,18); barBg.Position = UDim2.new(0,20,1,-26); barBg.AnchorPoint = Vector2.new(0,1)
	barBg.BackgroundColor3 = Color3.fromRGB(40,28,24); barBg.Parent = panel; Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,9)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(0,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(255,150,50); bar.BorderSizePixel = 0; bar.Parent = barBg; Instance.new("UICorner", bar).CornerRadius = UDim.new(0,9)
	local taps, done, t0 = 0, false, os.clock()
	local function finish(win) if done then return end; done = true; pcall(function() g:Destroy() end); if onDone then onDone(win) end end
	plug.Activated:Connect(function()
		if done then return end
		taps += 1
		TS:Create(bar, TweenInfo.new(0.08), { Size = UDim2.new(math.clamp(taps/CONFIG.tapsToPlug,0,1),0,1,0) }):Play()
		plug.Text = (taps % 2 == 0) and "\xF0\x9F\xAA\xA8  PLUG!" or "\xF0\x9F\x92\xA5  SHOVE!"
		if taps >= CONFIG.tapsToPlug then finish(true) end
	end)
	task.spawn(function() while not done do if os.clock() - t0 > CONFIG.plugTime then finish(false) end; task.wait(0.1) end end)
end

-- ===== build an erupting geyser AT the user's marker (the marker is only a position; WE build the geyser) =====
local function buildGeyser(inst)
	-- marker -> base position, then GHOST the marker (it shouldn't be visible -- it's just a spot)
	local mpos = (inst:IsA("BasePart") and inst.Position) or inst:GetBoundingBox().Position
	pcall(function()
		if inst:IsA("BasePart") then inst.Transparency = 1; inst.CanCollide = false; inst.CanQuery = false
		else for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false; d.CanQuery = false end end end
	end)
	-- find the ground under the marker so the built geyser sits on the island
	local grp = RaycastParams.new(); grp.FilterType = Enum.RaycastFilterType.Exclude; grp.FilterDescendantsInstances = { player.Character, inst }
	local ghit = Workspace:Raycast(mpos + Vector3.new(0, 12, 0), Vector3.new(0, -250, 0), grp)
	local base = Vector3.new(mpos.X, (ghit and ghit.Position.Y) or mpos.Y, mpos.Z)

	-- BUILD a LOW-POLY blocky volcanic chimney: stacked stretched rectangles, wide base -> narrow vent, each twisted a bit
	local model = Instance.new("Model"); model.Name = "GeyserVent"; model.Parent = Workspace
	local ROCK, ROCKD, DARK = Color3.fromRGB(62,52,49), Color3.fromRGB(46,38,36), Color3.fromRGB(22,18,17)
	local function blk(w, h, d, yc, rotY, color)
		local p = Instance.new("Part"); p.Shape = Enum.PartType.Block; p.Size = Vector3.new(w, h, d); p.Color = color; p.Material = Enum.Material.Slate
		p.Anchored = true; p.CanCollide = false; p.CanQuery = true; p.CastShadow = false
		p.CFrame = CFrame.new(base + Vector3.new(0, yc, 0)) * CFrame.Angles(0, math.rad(rotY), 0); p.Parent = model; return p
	end
	local mound = blk(6.4, 1.8, 6.4, 0.9, 12, ROCK)  -- wide base (also the prompt anchor)
	blk(5.0, 1.7, 5.0, 2.5, -20, ROCK)               -- mid
	blk(3.7, 1.6, 3.7, 4.0, 30, ROCKD)               -- upper
	blk(2.6, 1.0, 2.6, 5.1, -8, ROCKD)               -- neck
	blk(2.0, 0.7, 2.0, 5.8, 18, DARK)                -- dark vent rim / hole
	-- a few jagged low-poly rocks at the base (asymmetric, not a ring)
	for _, r in ipairs({ {1.7,1.3,1.4, 35}, {1.2,1.8,1.2, 150}, {1.9,1.1,1.4, 255} }) do
		local a = math.rad(r[4])
		local p = Instance.new("Part"); p.Shape = Enum.PartType.Block; p.Size = Vector3.new(r[1], r[2], r[3])
		p.Color = ROCKD; p.Material = Enum.Material.Slate; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false
		p.CFrame = CFrame.new(base + Vector3.new(math.cos(a)*3.3, 0.5, math.sin(a)*3.3)) * CFrame.Angles(0, a, math.rad(12)); p.Parent = model
	end
	local ventPos = base + Vector3.new(0, 6.4, 0)

	-- plume + glow rising from the vent
	local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(2,1,2); fx.CFrame=CFrame.new(ventPos); fx.Parent=model
	local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255,140,40); light.Brightness = 3; light.Range = 18; light.Parent = fx
	local lava = Instance.new("ParticleEmitter"); lava.Texture="rbxasset://textures/particles/fire_main.dds"
	lava.Color=ColorSequence.new(Color3.fromRGB(255,170,50), Color3.fromRGB(200,55,25)); lava.Lifetime=NumberRange.new(0.6,1.2); lava.Speed=NumberRange.new(20,34)
	lava.SpreadAngle=Vector2.new(10,10); lava.Acceleration=Vector3.new(0,-45,0); lava.Size=NumberSequence.new(2.2,0); lava.Rate=26; lava.LightEmission=0.85
	lava.EmissionDirection=Enum.NormalId.Top; lava.Rotation=NumberRange.new(0,360); lava.Parent=fx
	local steam = Instance.new("ParticleEmitter"); steam.Texture="rbxasset://textures/particles/smoke_main.dds"
	steam.Color=ColorSequence.new(Color3.fromRGB(120,110,105)); steam.Lifetime=NumberRange.new(1,2); steam.Speed=NumberRange.new(10,16); steam.SpreadAngle=Vector2.new(18,18)
	steam.Acceleration=Vector3.new(0,5,0); steam.Size=NumberSequence.new(3,6); steam.Rate=8; steam.Transparency=NumberSequence.new(0.4,1); steam.EmissionDirection=Enum.NormalId.Top; steam.Parent=fx
	local g = { inst=inst, model=model, anchor=mound, fx=fx, light=light, lava=lava, steam=steam, ventPos=ventPos, plugged=false }
	-- periodic eruption blob
	task.spawn(function()
		while not g.plugged and fx.Parent do
			task.wait(2 + math.random()*2.5)
			if g.plugged then break end
			local blob = Instance.new("Part"); blob.Shape=Enum.PartType.Ball; blob.Size=Vector3.new(1.7,1.7,1.7); blob.Color=Color3.fromRGB(255,120,40); blob.Material=Enum.Material.Neon
			blob.Anchored=true; blob.CanCollide=false; blob.CanQuery=false; blob.CFrame=CFrame.new(ventPos); blob.Parent=Workspace
			local up = ventPos + Vector3.new((math.random()-0.5)*3, 16+math.random()*8, (math.random()-0.5)*3)
			TS:Create(blob, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame=CFrame.new(up)}):Play()
			task.delay(0.5, function()
				TS:Create(blob, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame=CFrame.new(ventPos), Transparency=1, Size=Vector3.new(0.3,0.3,0.3)}):Play()
				Debris:AddItem(blob, 0.7)
			end)
		end
	end)
	-- LAVA SPEW: small blocky lava chunks constantly arc out of the vent and fall (on top of the fire particles)
	task.spawn(function()
		while not g.plugged and model.Parent do
			task.wait(0.3 + math.random()*0.45)
			if g.plugged then break end
			local sz = 0.5 + math.random()*0.6
			local chunk = Instance.new("Part"); chunk.Shape = Enum.PartType.Block; chunk.Size = Vector3.new(sz, sz, sz)
			chunk.Color = Color3.fromRGB(255, 110 + math.random(0,70), 40); chunk.Material = Enum.Material.Neon
			chunk.Anchored = true; chunk.CanCollide = false; chunk.CanQuery = false; chunk.CastShadow = false
			chunk.CFrame = CFrame.new(ventPos) * CFrame.Angles(math.random()*6, math.random()*6, math.random()*6); chunk.Parent = Workspace
			local dir = Vector3.new((math.random()-0.5)*2, 0, (math.random()-0.5)*2)
			local peak = ventPos + dir * (3 + math.random()*4) + Vector3.new(0, 7 + math.random()*6, 0)
			local land = ventPos + dir * (7 + math.random()*7) + Vector3.new(0, -3, 0)
			TS:Create(chunk, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * CFrame.Angles(math.random()*6, math.random()*6, 0) }):Play()
			task.delay(0.4, function()
				TS:Create(chunk, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(land), Transparency = 1, Size = Vector3.new(0.15,0.15,0.15) }):Play()
			end)
			Debris:AddItem(chunk, 1.0)
		end
	end)
	return g
end

local function plugGeyser(g)
	if g.plugged then return end
	g.plugged = true
	g.lava.Rate = 0; g.steam.Rate = 3 -- a little lingering steam
	g.light.Brightness = 0.5; g.light.Color = Color3.fromRGB(120,120,120)
	-- a boulder slams down to cap the vent
	local cap = Instance.new("Part"); cap.Shape=Enum.PartType.Ball; cap.Size=Vector3.new(3.2,2.6,3.2); cap.Color=Color3.fromRGB(78,70,66); cap.Material=Enum.Material.Slate
	cap.Anchored=true; cap.CanCollide=false; cap.CanQuery=false; cap.CastShadow=false; cap.CFrame=CFrame.new(g.ventPos + Vector3.new(0,8,0)); cap.Parent=Workspace
	TS:Create(cap, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(g.ventPos + Vector3.new(0,0.6,0)) }):Play()
	floatText(g.ventPos + Vector3.new(0,3,0), "Plugged!", Color3.fromRGB(200,200,200))
end

-- ===== "QUEST COMPLETE" banner + a directional arrow guiding the player to the reward egg =====
local function showCompleteGuide(eggPos)
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "GeyserComplete"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 80; g.Parent = pgui
	local banner = Instance.new("TextLabel"); banner.AnchorPoint = Vector2.new(0.5,0); banner.Position = UDim2.new(0.5,0,0,140); banner.Size = UDim2.fromOffset(540,56)
	banner.BackgroundColor3 = Color3.fromRGB(70,46,40); banner.BackgroundTransparency = 0.1; banner.Font = Enum.Font.FredokaOne; banner.TextScaled = true
	banner.TextColor3 = Color3.fromRGB(255,225,180); banner.Text = "\xF0\x9F\x8C\x8B Volcano saved! Go hatch the egg!"; banner.Parent = g
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0,12); local bs = Instance.new("UIStroke", banner); bs.Color = Color3.fromRGB(255,140,40); bs.Thickness = 2
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 26; c.Parent = banner end
	local arrowGui, arrowLbl, conn
	conn = RunService.RenderStepped:Connect(function()
		if st.owns then pcall(function() g:Destroy() end); if arrowGui then arrowGui:Destroy() end; if conn then conn:Disconnect() end; return end -- hatched -> clean up
		local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart"); local cam = Workspace.CurrentCamera
		if not (hrp and cam) then return end
		local d = eggPos - hrp.Position; local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude < 12 then if arrowGui then arrowGui.Enabled = false end; banner.Text = "\xF0\x9F\xA5\x9A Press E to hatch the egg!"; return end
		banner.Text = "\xF0\x9F\x8C\x8B Volcano saved! Go hatch the egg!"
		if not (arrowGui and arrowGui.Adornee == hrp and arrowGui.Parent) then
			if arrowGui then arrowGui:Destroy() end
			arrowGui = Instance.new("BillboardGui"); arrowGui.Name = "EggArrow"; arrowGui.Adornee = hrp; arrowGui.Size = UDim2.fromOffset(84,84); arrowGui.StudsOffset = Vector3.new(0,3.6,0); arrowGui.AlwaysOnTop = true; arrowGui.LightInfluence = 0; arrowGui.Parent = pgui
			arrowLbl = Instance.new("TextLabel"); arrowLbl.BackgroundTransparency = 1; arrowLbl.Size = UDim2.fromScale(1,1); arrowLbl.Font = Enum.Font.SourceSansBold; arrowLbl.TextScaled = true; arrowLbl.TextColor3 = Color3.fromRGB(255,160,60); arrowLbl.TextStrokeColor3 = Color3.new(0,0,0); arrowLbl.TextStrokeTransparency = 0.3; arrowLbl.Text = "\xE2\x96\xB2"; arrowLbl.Parent = arrowGui
		end
		arrowGui.Enabled = true
		local b = flat.Unit; local camCF = cam.CFrame
		local relX = b.X*camCF.RightVector.X + b.Z*camCF.RightVector.Z
		local relZ = b.X*camCF.LookVector.X + b.Z*camCF.LookVector.Z
		arrowLbl.Rotation = math.deg(math.atan2(relX, relZ))
	end)
end

-- ===== reward egg (volcanic) -> hatch the T-Rex =====
local function spawnRewardEgg(eggPos)
	local egg = Instance.new("Model"); egg.Name = "GeyserRewardEgg"
	local function part(name, sh, sz, col, cf, mat)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	local nestCenter = CFrame.new(eggPos + Vector3.new(0, 0.5, 0))
	for k = 1, 12 do local a=(k-1)*(2*math.pi/12)
		part("Rock", Enum.PartType.Ball, Vector3.new(1.1,0.8,1.1), Color3.fromRGB(60,50,46), nestCenter * CFrame.Angles(0,a,0) * CFrame.new(0,0,2.4), Enum.Material.Slate) end
	local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
	local shell = Instance.new("Part"); shell.Name="Shell"; shell.Shape=Enum.PartType.Ball; shell.Size=Vector3.new(1,1,1); shell.Color=Color3.fromRGB(74,64,60); shell.Material=Enum.Material.SmoothPlastic
	shell.Anchored=true; shell.CanCollide=false; shell.CanQuery=false; shell.Parent=visual
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType=Enum.MeshType.Sphere; mesh.Scale=Vector3.new(3.0,4.0,3.0); mesh.Parent=shell
	visual.PrimaryPart = shell
	for j = 1, 9 do local a=(j-1)*(2*math.pi/9); local y=math.sin(a*1.8)*1.0; local r=1.3*math.sqrt(math.max(0,1-(y/2.1)^2))+0.05
		part("Ember", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(255,140,50), shell.CFrame * CFrame.new(math.sin(a)*r, y, math.cos(a)*r), Enum.Material.Neon) end
	local baseCF = CFrame.new(eggPos + Vector3.new(0, 1.9, 0)); visual:PivotTo(baseCF)
	egg.Parent = Workspace
	local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(255,150,60); hl.FillTransparency=0.5; hl.OutlineColor=Color3.fromRGB(255,120,40); hl.DepthMode=Enum.HighlightDepthMode.Occluded; hl.Adornee=visual; hl.Parent=egg
	task.spawn(function() local t=0 while egg.Parent and not st.hatching do t+=0.05; pcall(function() visual:PivotTo(baseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end); task.wait(0.05) end end)
	local pp = Instance.new("ProximityPrompt"); pp.ActionText="Hatch"; pp.ObjectText="Volcano Egg"; pp.KeyboardKeyCode=Enum.KeyCode.E; pp.HoldDuration=0.4; pp.MaxActivationDistance=14; pp.RequiresLineOfSight=false; pp.Parent=shell
	pp.Triggered:Connect(function()
		if st.hatching or st.owns then return end
		st.hatching = true; pp.Enabled = false
		if visual then local t0=os.clock()
			while os.clock()-t0 < 0.9 and visual.Parent do local p=(os.clock()-t0)/0.9; local amp=0.1+p*p*0.95
				pcall(function() visual:PivotTo(baseCF * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*70),0)) end); task.wait() end
			pcall(function() visual:Destroy() end)
		end
		HatchBurst.play(eggPos + Vector3.new(0,1.9,0), Color3.fromRGB(120,80,66))
		floatText(eggPos + Vector3.new(0,3,0), CONFIG.petName .. " hatched! \xF0\x9F\xA6\x96")
		local grantCF = CFrame.new(eggPos)
		if _G[CONFIG.spawnFollower] then pcall(function() _G[CONFIG.spawnFollower](grantCF) end) end
		if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet(CONFIG.petId, { petId=CONFIG.petId, displayName=CONFIG.petName, level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
		do local he = RS:FindFirstChild(CONFIG.hatchEvent); if he then pcall(function() he:FireServer() end) end end
		st.owns = true; st.hatching = false
		task.delay(1.4, function() pcall(function() egg:Destroy() end) end)
		print("[Geyser] island8 quest complete -> T-Rex hatched")
	end)
end

-- ===== BOOT =====
task.spawn(function()
	local isl = Workspace:FindFirstChild(CONFIG.islandName) or Workspace:WaitForChild(CONFIG.islandName, 60)
	if not isl then warn("[Geyser] " .. CONFIG.islandName .. " not found -> volcano quest skipped"); return end
	pcall(function() player:SetAttribute("Island8QuestAccepted", true) end) -- no NPC yet -> auto-accept so the banner shows the task

	-- robust per-name finder (exact anywhere -> case/space-insensitive)
	local function findNamed(want)
		local exact = Workspace:FindFirstChild(want, true); if exact then return exact end
		local w = want:lower():gsub("[^%w]", "") -- strip spaces / parens / underscores, e.g. "Geyser (1)" -> "geyser1"
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower():gsub("[^%w]", "") == w then return d end
		end
		return nil
	end

	-- island centre (for the egg fallback)
	local bcf, bsize = isl:GetBoundingBox()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { player.Character }
	local topY = bcf.Position.Y + bsize.Y/2
	local hit = Workspace:Raycast(Vector3.new(bcf.Position.X, topY + 60, bcf.Position.Z), Vector3.new(0,-400,0), rp)
	local center = Vector3.new(bcf.Position.X, (hit and hit.Position.Y or topY), bcf.Position.Z)

	buildHUD(); updateHUD()

	local function onAllPlugged()
		if st.done then return end
		st.done = true
		if vignette then TS:Create(vignette, TweenInfo.new(1.5), { BackgroundTransparency = 1 }):Play() end
		floatText(center + Vector3.new(0,6,0), "The volcano is calm! An egg appears...", Color3.fromRGB(255,210,140))
		-- find EggSpot8 NOW (it has surely streamed in by the time all geysers are plugged); fallback = island centre
		local eggSpot = findNamed("EggSpot8")
		local eggPos = (eggSpot and ((eggSpot:IsA("BasePart") and eggSpot.Position) or eggSpot:GetPivot().Position)) or center
		if eggSpot then pcall(function() eggSpot.Transparency=1; eggSpot.CanCollide=false; eggSpot.CanQuery=false end); print("[Geyser] using EggSpot8 at " .. tostring(eggPos)) end
		task.wait(0.8)
		spawnRewardEgg(eggPos)
		showCompleteGuide(eggPos) -- "Volcano saved! Go hatch the egg" + arrow pointing to it
	end

	-- wait for the Geyser parts to replicate / stream in (they often don't exist yet at client load).
	local geyserParts = {}
	for attempt = 1, 40 do
		local n = 0
		for i = 1, CONFIG.count do
			if not geyserParts[i] then
				local inst = findNamed("Geyser" .. i)
				if inst and (inst:IsA("BasePart") or inst:IsA("Model")) then geyserParts[i] = inst end
			end
			if geyserParts[i] then n += 1 end
		end
		if n >= CONFIG.count then break end
		task.wait(0.5)
	end

	-- build + wire each geyser (accepts a Part OR a Model named Geyser#)
	local found = 0
	for i = 1, CONFIG.count do
		local inst = geyserParts[i]
		if inst and (inst:IsA("BasePart") or inst:IsA("Model")) then
			local g = buildGeyser(inst)
			local promptParent = g.anchor
			if not promptParent then warn("[Geyser] Geyser" .. i .. " has no BasePart -> no prompt"); else
			found += 1
			print(("[Geyser] built Geyser%d at %s"):format(i, tostring(g.ventPos)))
			local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Plug Geyser"; pp.ObjectText = "Geyser " .. i
			pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.2; pp.MaxActivationDistance = 16; pp.RequiresLineOfSight = false; pp.Parent = promptParent
			pp.Triggered:Connect(function()
				if st.busy or g.plugged or st.done then return end
				st.busy = true
				openPlugMinigame(function(win)
					st.busy = false
					if win and not g.plugged then
						plugGeyser(g); pp.Enabled = false
						st.plugged += 1; updateHUD()
						if st.plugged >= found then onAllPlugged() end
					elseif not g.plugged then
						floatText(g.ventPos + Vector3.new(0,2,0), "It blew you back! Try again.", Color3.fromRGB(255,120,80))
					end
				end)
			end)
			end -- close: if not promptParent then ... else (build)
		else
			warn("[Geyser] Geyser" .. i .. " not found")
		end
	end
	if found == 0 then warn("[Geyser] no Geyser1..6 parts found -> quest inactive (name parts 'Geyser1'..'Geyser6')"); return end
	print(("[Geyser] island8 volcano quest ready: %d geysers erupting -- plug them all!"):format(found))
end)
