--======================================================================
-- MosquitoQuest.client.luau  (LocalScript)  -- Island 5 "Misty Mire" swamp quest
--======================================================================
-- THE FLOW:
--   1. Big MOSQUITOS hover/drift in the air above island5 (clickable from the ground).
--   2. Click one -> a small "SWAT!" mini-game GUI pops up -> tap fast to squash it.
--   3. Squash 5 -> a NEST + dino egg appears on the island.
--   4. Press E to "Feed & Hatch" -> the mosquitos feed the baby dino -> cool hatch -> pet granted.
--
-- Self-contained (like the other island quests). Reward pet is configurable below.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")
local player     = Players.LocalPlayer
local HatchBurst = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst")) -- shared cool hatch FX

local CONFIG = {
	islandName    = "island5",
	count         = 5,            -- mosquitos to squash
	tapsToSwat    = 6,            -- taps in the mini-game to squash one
	swatTime      = 5,            -- seconds before the mosquito escapes the mini-game
	petId         = "SpinosaurusPet", -- the swamp dino reward
	petName       = "Spinosaurus",
	spawnFollower = "SpawnSpinosaurusFollower",
	hatchEvent    = "SpinosaurusHatched",
}

local st = { caught = 0, busy = false, done = false, hatching = false, owns = false, mossies = {} }

-- ===== generic helpers =====
local function floatText(pos, text, color)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,220,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.MaxDistance=120; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=color or Color3.fromRGB(180,230,140); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.6, function() a:Destroy() end)
end

-- ===== top HUD counter =====
local hudLbl
local function buildHUD()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "MosquitoHUD"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 60; g.Parent = pgui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0); f.Position = UDim2.new(0.5,0,0,92); f.Size = UDim2.fromOffset(240,40)
	f.BackgroundColor3 = Color3.fromRGB(122,142,82); f.BackgroundTransparency = 0.1; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,12); local s = Instance.new("UIStroke", f); s.Color = Color3.fromRGB(40,52,38); s.Thickness = 2
	hudLbl = Instance.new("TextLabel"); hudLbl.Size = UDim2.new(1,0,1,0); hudLbl.BackgroundTransparency = 1
	hudLbl.Font = Enum.Font.FredokaOne; hudLbl.TextScaled = true; hudLbl.TextColor3 = Color3.fromRGB(250,242,214); hudLbl.Parent = f
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = hudLbl end
	-- only show the HUD while the player is ON island5 (so it doesn't clutter other islands)
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
	return g
end
local function updateHUD()
	if hudLbl then hudLbl.Text = ("\xF0\x9F\xA6\x9F  Mosquitos: %d / %d"):format(st.caught, CONFIG.count) end
end

-- ===== a big, clearly-visible mosquito model =====
local function buildMosquito(homePos)
	local m = Instance.new("Model"); m.Name = "SwampMosquito"
	local function p(name, shape, sz, color, rel, trans)
		local pt = Instance.new("Part"); pt.Name=name; pt.Shape=shape; pt.Size=sz; pt.Color=color; pt.Material=Enum.Material.SmoothPlastic
		pt.Transparency = trans or 0; pt.Anchored=true; pt.CanCollide=false; pt.CanQuery=true; pt.CastShadow=false
		pt.CFrame = CFrame.new(homePos) * rel; pt.Parent = m; return pt
	end
	local DARK = Color3.fromRGB(58,64,52); local WING = Color3.fromRGB(205,224,212)
	local body = p("Body", Enum.PartType.Ball, Vector3.new(1.4,1.2,3.0), DARK, CFrame.new()) -- thorax + abdomen, big enough to see
	m.PrimaryPart = body
	p("Head", Enum.PartType.Ball, Vector3.new(1.1,1.1,1.1), DARK, CFrame.new(0,0.15,1.7))
	p("Proboscis", Enum.PartType.Cylinder, Vector3.new(1.8,0.14,0.14), Color3.fromRGB(35,35,35), CFrame.new(0,0,2.8)*CFrame.Angles(0,math.rad(90),0))
	for _, sgn in ipairs({1,-1}) do
		p("Eye", Enum.PartType.Ball, Vector3.new(0.38,0.38,0.38), Color3.fromRGB(190,40,40), CFrame.new(0.34*sgn,0.3,2.0))
		p("Wing", Enum.PartType.Block, Vector3.new(2.8,0.07,1.2), WING, CFrame.new(1.9*sgn,0.6,0.1)*CFrame.Angles(0,0,math.rad(22*sgn)), 0.5)
		for _, lz in ipairs({0.7,0,-0.7}) do
			p("Leg", Enum.PartType.Cylinder, Vector3.new(1.8,0.09,0.09), DARK, CFrame.new(0.5*sgn,-0.5,lz)*CFrame.Angles(0,0,math.rad(58*sgn))*CFrame.Angles(0,math.rad(18),0))
		end
	end
	m.Parent = Workspace
	return m, body
end

-- ===== the SWAT mini-game (rapid tap; works anywhere on screen via a modal backdrop) =====
local function openSwatMinigame(onDone)
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "SwatGui"; g.ResetOnSpawn = false; g.DisplayOrder = 210; g.Parent = pgui
	local dim = Instance.new("TextButton"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false; dim.Text = ""; dim.Modal = true; dim.Active = true; dim.Parent = g -- sinks input so it works anywhere
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromOffset(300,230); panel.Position = UDim2.fromScale(0.5,0.5); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local g2 = Instance.new("UIGradient"); g2.Rotation = 90; g2.Color = ColorSequence.new(Color3.fromRGB(126,146,86), Color3.fromRGB(118,138,80)); g2.Parent = panel
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-20,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "SWAT THE MOSQUITO!"; title.Parent = panel
	local swat = Instance.new("TextButton"); swat.Size = UDim2.fromOffset(160,108); swat.Position = UDim2.new(0.5,0,0,56); swat.AnchorPoint = Vector2.new(0.5,0)
	swat.BackgroundColor3 = Color3.fromRGB(90,170,90); swat.Font = Enum.Font.FredokaOne; swat.TextScaled = true; swat.TextColor3 = Color3.new(1,1,1); swat.Text = "\xF0\x9F\xA6\x9F  SWAT!"; swat.Parent = panel
	Instance.new("UICorner", swat).CornerRadius = UDim.new(0,14); Instance.new("UIStroke", swat).Color = Color3.fromRGB(40,80,40)
	local barBg = Instance.new("Frame"); barBg.Size = UDim2.new(1,-40,0,18); barBg.Position = UDim2.new(0,20,1,-26); barBg.AnchorPoint = Vector2.new(0,1)
	barBg.BackgroundColor3 = Color3.fromRGB(40,52,38); barBg.Parent = panel; Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,9)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(0,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(126,217,87); bar.BorderSizePixel = 0; bar.Parent = barBg; Instance.new("UICorner", bar).CornerRadius = UDim.new(0,9)
	local taps, done, t0 = 0, false, os.clock()
	local function finish(win) if done then return end; done = true; pcall(function() g:Destroy() end); if onDone then onDone(win) end end
	swat.Activated:Connect(function()
		if done then return end
		taps += 1
		TS:Create(bar, TweenInfo.new(0.08), { Size = UDim2.new(math.clamp(taps/CONFIG.tapsToSwat,0,1),0,1,0) }):Play()
		swat.Text = (taps % 2 == 0) and "\xF0\x9F\xA6\x9F  SWAT!" or "\xF0\x9F\x92\xA5  SMACK!"
		if taps >= CONFIG.tapsToSwat then finish(true) end
	end)
	task.spawn(function() while not done do if os.clock() - t0 > CONFIG.swatTime then finish(false) end; task.wait(0.1) end end)
end

-- ===== squash splat =====
local function squashMosquito(m)
	local pos = m:GetPivot().Position
	local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(1,1,1); fx.CFrame=CFrame.new(pos); fx.Parent=Workspace
	local em = Instance.new("ParticleEmitter"); em.Texture="rbxasset://textures/particles/smoke_main.dds"
	em.Color=ColorSequence.new(Color3.fromRGB(130,170,90)); em.Lifetime=NumberRange.new(0.4,0.8); em.Speed=NumberRange.new(7,14)
	em.SpreadAngle=Vector2.new(180,180); em.Size=NumberSequence.new(1.4,0); em.Rate=0; em.Parent=fx; em:Emit(22)
	Debris:AddItem(fx, 1.1)
	floatText(pos + Vector3.new(0,1,0), "Squashed!")
	pcall(function() m:Destroy() end)
end

-- ===== the reward: dino egg + nest -> feed & hatch =====
local function hatchEgg(eggModel, visual, baseCF, eggPos)
	if st.hatching or st.owns then return end
	st.hatching = true
	if visual then local t0 = os.clock()
		while os.clock()-t0 < 0.9 and visual.Parent do local p=(os.clock()-t0)/0.9; local amp=0.1+p*p*0.95
			pcall(function() visual:PivotTo(baseCF * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*70),0)) end); task.wait() end
		pcall(function() visual:Destroy() end)
	end
	HatchBurst.play(eggPos + Vector3.new(0,1,0), Color3.fromRGB(180,200,150)) -- cool hatch
	floatText(eggPos + Vector3.new(0,3,0), CONFIG.petName .. " hatched! \xF0\x9F\xA5\x9A")
	local grantCF = CFrame.new(eggPos)
	if _G[CONFIG.spawnFollower] then pcall(function() _G[CONFIG.spawnFollower](grantCF) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet(CONFIG.petId, { petId=CONFIG.petId, displayName=CONFIG.petName, level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	do local he = RS:FindFirstChild(CONFIG.hatchEvent); if he then pcall(function() he:FireServer() end) end end
	st.owns = true; st.hatching = false
	task.delay(1.4, function() if eggModel then pcall(function() eggModel:Destroy() end) end end)
	print("[Mosquito] island5 quest complete -> " .. CONFIG.petName .. " hatched")
end

-- ===== FEED mini-game: tap to feed each caught mosquito to the egg (gives the "feeding" feel before it hatches) =====
local function openFeedMinigame(onDone)
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "FeedGui"; g.ResetOnSpawn = false; g.DisplayOrder = 210; g.Parent = pgui
	local dim = Instance.new("TextButton"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false; dim.Text = ""; dim.Modal = true; dim.Active = true; dim.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromOffset(320,300); panel.Position = UDim2.fromScale(0.5,0.5); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local gr = Instance.new("UIGradient"); gr.Rotation = 90; gr.Color = ColorSequence.new(Color3.fromRGB(126,146,86), Color3.fromRGB(118,138,80)); gr.Parent = panel
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-20,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "FEED THE EGG!"; title.Parent = panel
	local eggIco = Instance.new("TextLabel"); eggIco.Size = UDim2.fromOffset(120,120); eggIco.Position = UDim2.new(0.5,0,0,50); eggIco.AnchorPoint = Vector2.new(0.5,0)
	eggIco.BackgroundTransparency = 1; eggIco.Font = Enum.Font.FredokaOne; eggIco.TextScaled = true; eggIco.Text = "\xF0\x9F\xA5\x9A"; eggIco.Parent = panel
	local counter = Instance.new("TextLabel"); counter.Size = UDim2.new(1,-20,0,24); counter.Position = UDim2.new(0,10,0,174); counter.BackgroundTransparency = 1
	counter.Font = Enum.Font.GothamBold; counter.TextScaled = true; counter.TextColor3 = Color3.fromRGB(250,242,214); counter.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = counter end
	local feed = Instance.new("TextButton"); feed.Size = UDim2.fromOffset(190,66); feed.Position = UDim2.new(0.5,0,1,-72); feed.AnchorPoint = Vector2.new(0.5,0)
	feed.BackgroundColor3 = Color3.fromRGB(90,170,90); feed.Font = Enum.Font.FredokaOne; feed.TextScaled = true; feed.TextColor3 = Color3.new(1,1,1); feed.Text = "\xF0\x9F\xA6\x9F  FEED"; feed.Parent = panel
	Instance.new("UICorner", feed).CornerRadius = UDim.new(0,14); Instance.new("UIStroke", feed).Color = Color3.fromRGB(40,80,40)
	local left, done = CONFIG.count, false
	local function refresh() counter.Text = ("Mosquitos to feed: %d"):format(left) end
	refresh()
	feed.Activated:Connect(function()
		if done then return end
		left -= 1; refresh()
		-- a mosquito flies up into the egg, and the egg "chomps" (scale punch + yum face)
		local fly = Instance.new("TextLabel"); fly.Size = UDim2.fromOffset(40,40); fly.AnchorPoint = Vector2.new(0.5,0.5); fly.Position = UDim2.new(0.5,0,1,-104)
		fly.BackgroundTransparency = 1; fly.Font = Enum.Font.FredokaOne; fly.TextScaled = true; fly.Text = "\xF0\x9F\xA6\x9F"; fly.ZIndex = 3; fly.Parent = panel
		TS:Create(fly, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5,0,0,110), Size = UDim2.fromOffset(8,8), TextTransparency = 1 }):Play()
		task.delay(0.32, function() fly:Destroy() end)
		eggIco.Text = "\xF0\x9F\x98\x8B"
		TS:Create(eggIco, TweenInfo.new(0.12), { Size = UDim2.fromOffset(142,142) }):Play()
		task.delay(0.16, function() TS:Create(eggIco, TweenInfo.new(0.12), { Size = UDim2.fromOffset(120,120) }):Play(); task.delay(0.14, function() if not done then eggIco.Text = "\xF0\x9F\xA5\x9A" end end) end)
		if left <= 0 then
			done = true; counter.Text = "Yum! It's hatching..."
			task.delay(0.55, function() pcall(function() g:Destroy() end); if onDone then onDone() end end)
		end
	end)
end

local function spawnEggNest(center)
	local egg = Instance.new("Model"); egg.Name = "MosquitoRewardEgg"
	local function part(name, sh, sz, col, cf, mat)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	-- twig nest
	local nestCenter = CFrame.new(center + Vector3.new(0, 0.5, 0))
	for k = 1, 12 do
		local a = (k-1) * (2*math.pi/12)
		local twig = part("Twig", Enum.PartType.Cylinder, Vector3.new(2.2,0.5,0.5), Color3.fromRGB(96,70,42), nestCenter * CFrame.Angles(0,a,0) * CFrame.new(0,0,2.4) * CFrame.Angles(0,math.rad(90),math.rad(16)), Enum.Material.Wood)
	end
	-- egg
	local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
	local shell = Instance.new("Part"); shell.Name="Shell"; shell.Shape=Enum.PartType.Ball; shell.Size=Vector3.new(1,1,1); shell.Color=Color3.fromRGB(196,212,160); shell.Material=Enum.Material.SmoothPlastic; shell.Reflectance=0.05
	shell.Anchored=true; shell.CanCollide=false; shell.CanQuery=false; shell.Parent=visual
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType=Enum.MeshType.Sphere; mesh.Scale=Vector3.new(3.0,4.0,3.0); mesh.Parent=shell
	visual.PrimaryPart = shell
	for j = 1, 8 do local a=(j-1)*(2*math.pi/8); local y=math.sin(a*1.7)*1.0; local r=1.3*math.sqrt(math.max(0,1-(y/2)^2))+0.05
		part("Spot", Enum.PartType.Ball, Vector3.new(0.45,0.45,0.45), Color3.fromRGB(120,150,90), shell.CFrame * CFrame.new(math.sin(a)*r, y, math.cos(a)*r)) end
	local baseCF = CFrame.new(center + Vector3.new(0, 1.9, 0)) -- egg rests in the nest ON the spot (not floating)
	visual:PivotTo(baseCF)
	egg.Parent = Workspace
	local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(180,230,140); hl.FillTransparency=0.5; hl.OutlineColor=Color3.fromRGB(120,200,90); hl.DepthMode=Enum.HighlightDepthMode.Occluded; hl.Adornee=visual; hl.Parent=egg
	-- gentle bob
	task.spawn(function() local t=0 while egg.Parent and not st.hatching do t+=0.05; pcall(function() visual:PivotTo(baseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end); task.wait(0.05) end end)
	-- prompt
	local pp = Instance.new("ProximityPrompt"); pp.ActionText="Feed & Hatch"; pp.ObjectText="Hungry Egg"; pp.KeyboardKeyCode=Enum.KeyCode.E; pp.HoldDuration=0.4; pp.MaxActivationDistance=14; pp.RequiresLineOfSight=false; pp.Parent=shell
	pp.Triggered:Connect(function()
		if st.hatching or st.owns then return end
		pp.Enabled = false
		openFeedMinigame(function() hatchEgg(egg, visual, baseCF, center + Vector3.new(0,1.9,0)) end) -- feed first, THEN hatch
	end)
	floatText(center + Vector3.new(0,4.2,0), "Feed the mosquitos to the egg!", Color3.fromRGB(230,236,150))
	print("[Mosquito] all mosquitos squashed -> reward egg + nest spawned")
end

-- ===== BOOT: find island5, spawn the swarm, run the quest =====
task.spawn(function()
	local isl = Workspace:FindFirstChild(CONFIG.islandName) or Workspace:WaitForChild(CONFIG.islandName, 60)
	if not isl then warn("[Mosquito] " .. CONFIG.islandName .. " not found -> swamp quest skipped"); return end
	-- this island's quest has no NPC (no spawn point) -> auto-accept so the banner shows the task
	pcall(function() player:SetAttribute("Island5QuestAccepted", true) end)

	local bcf, bsize = isl:GetBoundingBox()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { player.Character }
	local topY = bcf.Position.Y + bsize.Y/2
	local hit = Workspace:Raycast(Vector3.new(bcf.Position.X, topY + 60, bcf.Position.Z), Vector3.new(0,-400,0), rp)
	local surfaceY = (hit and hit.Position.Y) or topY
	local center = Vector3.new(bcf.Position.X, surfaceY, bcf.Position.Z)

	buildHUD(); updateHUD()

	-- the egg appears at the user's EggSpot5 marker. ROBUST find: exact name anywhere -> then any part/model
	-- whose name (case/space-insensitive) is "eggspot5" or contains "eggspot". Fallback = island centre.
	local function findSpot()
		local exact = Workspace:FindFirstChild("EggSpot5", true)
		if exact then return exact end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Model") then
				local n = d.Name:lower():gsub("%s", "")
				if n == "eggspot5" or n:find("eggspot", 1, true) then return d end
			end
		end
		return nil
	end
	local function onAllCaught()
		if st.done then return end
		st.done = true
		-- find EggSpot5 NOW (it has surely streamed in by the time all mosquitos are swatted); fallback = island centre
		local eggSpot = findSpot()
		local eggPos = center
		if eggSpot then
			eggPos = (eggSpot:IsA("BasePart") and eggSpot.Position) or eggSpot:GetPivot().Position
			print("[Mosquito] using EggSpot5 -> " .. eggSpot:GetFullName() .. " at " .. tostring(eggPos))
			if eggSpot:IsA("BasePart") then pcall(function() eggSpot.Transparency = 1; eggSpot.CanCollide = false; eggSpot.CanQuery = false end) end
		else
			warn("[Mosquito] EggSpot5 NOT found -> using island centre. Name a part 'EggSpot5'.")
		end
		spawnEggNest(eggPos)
	end

	-- spawn the swarm SPREAD OUT in a ring around the island (evenly spaced angles), each at its own radius + height
	local ringR = math.clamp(math.max(bsize.X, bsize.Z) * 0.34, 22, 60)
	for i = 1, CONFIG.count do
		local ang = (i - 1) * (2 * math.pi / CONFIG.count) + math.random() * 0.5  -- 72 deg apart (for 5) + jitter
		local r   = ringR * (0.55 + math.random() * 0.5)                          -- varied distance from centre
		local home = center + Vector3.new(math.cos(ang) * r, 14 + math.random() * 14, math.sin(ang) * r)
		local m, body = buildMosquito(home)
		st.mossies[#st.mossies+1] = m
		-- bob + slow drift around the home point
		task.spawn(function()
			local t = math.random() * 12
			while m.Parent and not st.done do
				t += 0.05
				local off = Vector3.new(math.sin(t*0.6 + i)*6, math.sin(t*1.4 + i)*1.6, math.cos(t*0.5 + i)*6)
				pcall(function() m:PivotTo(CFrame.new(home + off) * CFrame.Angles(0, t*0.5, 0)) end)
				task.wait(0.05)
			end
		end)
		-- click -> swat mini-game
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance = 130; cd.Parent = body
		cd.MouseClick:Connect(function()
			if st.busy or st.done or not m.Parent then return end
			st.busy = true
			openSwatMinigame(function(win)
				st.busy = false
				if win and m.Parent then
					squashMosquito(m)
					st.caught += 1; updateHUD()
					if st.caught >= CONFIG.count then onAllCaught() end
				elseif m.Parent then
					floatText(m:GetPivot().Position + Vector3.new(0,1,0), "It got away!", Color3.fromRGB(235,120,120))
				end
			end)
		end)
	end
	print(("[Mosquito] island5 swamp quest ready: %d mosquitos hovering -- click to swat"):format(CONFIG.count))
end)
