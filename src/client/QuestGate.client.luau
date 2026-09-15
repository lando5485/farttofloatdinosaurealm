--[[
	QuestGate.client.luau  (StarterPlayerScripts -> DinosaurRealmClient)

	When the player tries to collect an egg before talking to the miner ("the
	Researcher"), the server fires ReplicatedStorage.NestingNook.QuestGate to this
	client. We then:
	  * flash a top-middle banner: "Talk To The Researcher First To Claim Your Quest"
	  * show a green guide arrow above the player's head that points the way to the
	    miner, so they know where to go.
]]

print("[QuestGate] script loaded")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HatchBurst   = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst"))   -- shared cool hatch FX
local ChevronTrail = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("ChevronTrail")) -- shared ground chevron guide

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local folder = ReplicatedStorage:WaitForChild("NestingNook")
local questGate = folder:WaitForChild("QuestGate")

local BANNER_TIME = 4 -- seconds the banner stays up
local GUIDE_TIME = 7  -- seconds the guide arrow points the way
local ARROW_COLOR = Color3.fromRGB(50, 220, 80)

-- Recursive WaitForChild: the island1 NPCs live one model deeper
-- (Workspace.island1.island1.dino1 / .miner), so a plain WaitForChild on the
-- outer island times out and the reward egg used to fall back to (0,5,0) --
-- 250 studs below the island, where nobody could ever hatch it.
local function waitForDescendant(root: Instance?, name: string, timeout: number): Instance?
	if not root then return nil end
	local deadline = os.clock() + timeout
	repeat
		local found = root:FindFirstChild(name, true)
		if found then return found end
		task.wait(0.25)
	until os.clock() > deadline
	warn(("[QuestGate] '%s' not found under %s after %ds"):format(name, root:GetFullName(), timeout))
	return nil
end

-- Find the miner NPC so we can point at it.
local island = workspace:WaitForChild("island1", 90)
local miner = waitForDescendant(island, "miner", 90)

----------------------------------------------------------------------
-- Top-middle banner -- through the ONE banner system (NotifyCenter), TASK priority
----------------------------------------------------------------------
local Notify = require(script.Parent:WaitForChild("NotifyCenter"))
local function showBanner()
	Notify.push({ text = "Talk To The Researcher First To Claim Your Quest", wrap = true,
		color = ARROW_COLOR, priority = Notify.PRIORITY.TASK, duration = BANNER_TIME })
end

----------------------------------------------------------------------
-- Guide arrow above the player's head, pointing toward the miner
----------------------------------------------------------------------

local arrowGui: BillboardGui? = nil
local arrowLabel: TextLabel? = nil
local guideUntil = 0

local function ensureArrow(): BillboardGui?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	if arrowGui and arrowGui.Adornee == hrp and arrowGui.Parent then
		return arrowGui
	end
	if arrowGui then
		arrowGui:Destroy()
	end
	arrowGui = Instance.new("BillboardGui")
	arrowGui.Name = "QuestGuideArrow"
	arrowGui.Adornee = hrp
	arrowGui.Size = UDim2.fromOffset(70, 70) -- constant on-screen size
	arrowGui.StudsOffset = Vector3.new(0, 3.5, 0) -- above the head
	arrowGui.AlwaysOnTop = true
	arrowGui.LightInfluence = 0
	arrowGui.Parent = playerGui

	arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.fromScale(1, 1)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.SourceSansBold
	arrowLabel.TextScaled = true
	arrowLabel.TextColor3 = ARROW_COLOR
	arrowLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	arrowLabel.TextStrokeTransparency = 0.3
	arrowLabel.Text = "▲" -- points "ahead"; rotated toward the miner each frame
	arrowLabel.Parent = arrowGui
	return arrowGui
end

RunService.RenderStepped:Connect(function()
	if os.clock() > guideUntil or not miner then
		if arrowGui then
			arrowGui.Enabled = false
		end
		return
	end

	local gui = ensureArrow()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not (gui and hrp and cam and arrowLabel) then
		return
	end
	gui.Enabled = true

	-- Camera-relative bearing to the miner: up = ahead, rotates toward it.
	local dir = miner:GetPivot().Position - hrp.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.5 then
		return
	end
	local camCF = cam.CFrame
	local relX = dir.X * camCF.RightVector.X + dir.Z * camCF.RightVector.Z
	local relZ = dir.X * camCF.LookVector.X + dir.Z * camCF.LookVector.Z
	arrowLabel.Rotation = math.deg(math.atan2(relX, relZ))
end)

----------------------------------------------------------------------
-- Server tells us the player tried to grab an egg too early
----------------------------------------------------------------------

questGate.OnClientEvent:Connect(function()
	showBanner()
	guideUntil = os.clock() + GUIDE_TIME
end)

----------------------------------------------------------------------
-- QUEST REWARD: when all eggs are returned (5/5), a glowing reward egg
-- appears beside the Mama Dino (dino1). An arrow + bottom-edge hint guide
-- the player to her; near her they can press E to hatch it into a pet.
-- (Adapted from EggSystem_AllInOne: nest + ovoid shell + speckles + glow +
-- shake/crack/pet-pop hatch.) Client-side reward visual.
----------------------------------------------------------------------
do
	local TweenService = game:GetService("TweenService")
	local SoundService = game:GetService("SoundService")
	local ContentProvider = game:GetService("ContentProvider")
	local Debris = game:GetService("Debris")

	local crackS = Instance.new("Sound"); crackS.SoundId = "rbxassetid://126450028713974"; crackS.Volume = 3; crackS.Parent = SoundService
	local unlockS = Instance.new("Sound"); unlockS.SoundId = "rbxassetid://92880640988467"; unlockS.Volume = 3; unlockS.Parent = SoundService
	task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ crackS, unlockS }) end) end)

	local EGG_SHELL = Color3.fromRGB(208, 232, 178)
	local EGG_SPOT  = Color3.fromRGB(70, 150, 70)
	local PET_COLOR = Color3.fromRGB(120, 210, 70)

	local function newPart(parent, name, shape, size, color, cf, material)
		local p = Instance.new("Part")
		p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		if cf then p.CFrame = cf end
		p.Parent = parent
		return p
	end

	local st = { hatching = false, owns = false }

	-- ===== STEGOSAURUS PET =====
	-- (No local build here anymore. The ONE source of truth is ReplicatedStorage.StegosaurusTemplate,
	-- published by src/server/Stegosaurus.server.luau. The hatch spawns via the server, and the local
	-- fallback below CLONES that same template -- so the in-game pet can never drift from the Hub.)
	local petAnims = setmetatable({}, { __mode = "k" })

	local function pivotRotate(pivot, rot) return CFrame.new(pivot) * rot * CFrame.new(-pivot) end
	local function animatePet(model, dt)
		local A = petAnims[model]; if not A then return end
		local root = model.PrimaryPart; if not (root and root.Parent) then return end
		local rootCF = root.CFrame; local s = A.s
		A.t = A.t + dt; local t = A.t
		local pos = rootCF.Position
		if A.lastPos then
			local d = pos - A.lastPos
			local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
			A.move = A.move + (math.clamp(sp / (26 * s), 0, 1) - A.move) * math.clamp(dt * 5, 0, 1)
		end
		A.lastPos = pos; local mv = A.move
		local bobY = math.sin(t * 1.5) * 0.06 * s + math.sin(t * (3.0 + 1.5 * mv)) * 0.09 * s * mv
		local globalT = CFrame.new(0, bobY, 0) * pivotRotate(Vector3.zero, CFrame.Angles(0, math.rad(3) * math.sin(t * 0.8), -math.rad(13) * mv + math.rad(2) * math.sin(t * 1.1)))
		local headBob = math.sin(t * 1.7 + 0.5) * 0.05 * s
		local headRot = CFrame.Angles(0, math.rad(8) * math.sin(t * 0.6), 0) * CFrame.Angles(0, 0, math.rad(5) * math.sin(t * 1.1) - math.rad(7) * mv)
		local headT = CFrame.new(0, headBob, 0) * pivotRotate(Vector3.new(1.2 * s, 0.6 * s, 0), headRot)
		local tailRot = pivotRotate(Vector3.new(-1.5 * s, 0, 0), CFrame.Angles(0, math.sin(t * (2.2 + 3 * mv)) * (math.rad(14) + math.rad(16) * mv), 0))
		A.blink = A.blink - dt; local eyeY = 1
		if A.blink <= 0 then
			local since = -A.blink
			if since < 0.16 then eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1)) else A.blink = 1.8 + math.random() * 3.4 end
		end
		for _, e in ipairs(A.parts) do
			local localCF
			if e.role == "head" then localCF = globalT * headT * e.base
			elseif e.role == "tail" then localCF = globalT * tailRot * e.base
			elseif e.role == "leg" then
				local bx, bz = e.base.Position.X, e.base.Position.Z
				local phase = ((bx >= 0) == (bz >= 0)) and 0 or math.pi
				localCF = globalT * pivotRotate(Vector3.new(bx, -0.7 * s, bz), CFrame.Angles(0, 0, math.rad(18) * mv * math.sin(t * (9 + 3 * mv) + phase))) * e.base
			else localCF = globalT * e.base end
			e.part.CFrame = rootCF * localCF
			if e.eye then e.part.Size = Vector3.new(e.baseSize.X, e.baseSize.Y * eyeY, e.baseSize.Z) end
		end
	end
	RunService.RenderStepped:Connect(function(dt)
		if st.owns and st.pet and st.pet.Parent then pcall(function() animatePet(st.pet, dt) end) end
	end)

	local function setGlow()
		if st.glow or not st.egg then return end
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(120,255,120); hl.FillTransparency = 0.45
		hl.OutlineColor = Color3.fromRGB(230,255,180); hl.OutlineTransparency = 0; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = st.visual or st.egg; hl.Parent = st.egg; st.glow = hl
		local shell = st.egg:FindFirstChild("Shell", true)
		if shell then
			local pl = Instance.new("PointLight"); pl.Name = "EggGlowLight"; pl.Color = Color3.fromRGB(150,255,150); pl.Brightness = 4; pl.Range = 26; pl.Parent = shell
			local em = Instance.new("ParticleEmitter"); em.Name = "EggGlowSparkle"; em.Texture = "rbxasset://textures/particles/sparkles_main.dds"; em.Color = ColorSequence.new(Color3.fromRGB(210,255,180)); em.Rate = 16; em.Lifetime = NumberRange.new(0.6,1.1); em.Speed = NumberRange.new(2,6); em.Size = NumberSequence.new(0.9); em.LightEmission = 0.85; em.Parent = shell
		end
	end

	local function buildPet(base)
		local m = Instance.new("Model"); m.Name = "HatchedPet"
		local body = newPart(m, "Body", Enum.PartType.Ball, Vector3.new(2.4,2.4,2.4), PET_COLOR, nil)
		newPart(m, "EyeL", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(1,1,1), body.CFrame * CFrame.new(0.55,0.4,1.0))
		newPart(m, "EyeR", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(1,1,1), body.CFrame * CFrame.new(-0.55,0.4,1.0))
		m.PrimaryPart = body
		return m
	end

	local function hatch()
		if st.hatching or st.owns then return end
		st.hatching = true
		pcall(function() crackS.TimePosition = 0; crackS:Play() end)
		local pr = st.egg and st.egg:FindFirstChildWhichIsA("ProximityPrompt", true); if pr then pr.Enabled = false end
		if st.glow then st.glow:Destroy(); st.glow = nil end
		local visual, base = st.visual, st.baseCF
		local SHAKE, t0 = 2.0, os.clock()
		while os.clock() - t0 < SHAKE do
			local p = (os.clock() - t0) / SHAKE; local amp = 0.1 + p * p * 0.9
			if visual and visual.PrimaryPart then
				pcall(function() visual:PivotTo(base * CFrame.new((math.random()-0.5)*amp*1.4, math.abs(math.sin((os.clock()-t0)*22))*amp*0.5, (math.random()-0.5)*amp*1.4) * CFrame.Angles(math.rad((math.random()-0.5)*amp*55), math.rad((math.random()-0.5)*amp*80), math.rad((math.random()-0.5)*amp*55))) end)
			end
			task.wait()
		end
		pcall(function() unlockS.TimePosition = 0; unlockS:Play() end)
		HatchBurst.play(base.Position, EGG_SHELL) -- shared COOL hatch explosion (flash + ring + sparkles + shards)
		if visual then pcall(function() visual:Destroy() end); st.visual = nil end
		-- SPAWN THE PET ON THE SERVER. A client-side clone of a server UnionOperation renders in a
		-- ViewportFrame (the Hub) but NOT reliably in the open world -- so we ask the server to clone
		-- StegosaurusTemplate into Workspace at `base` and float it. Server-owned unions render for
		-- everyone, identical to the Hub. (Fallback: local parts blob if the spawner isn't present.)
		local spawnEvt = ReplicatedStorage:FindFirstChild("HatchStegoSpawn")
		-- TRICERATOPS follower, matching the Mama Triceratops whose nest this is -- see the
		-- grant note below. The HatchStegoSpawn fallback below keeps its old name because it
		-- is a server remote; only the species the preferred path spawns has changed.
		if _G.SpawnTriceratopsFollower then
			-- preferred: the client FOLLOWER (emerges here, then follows you) -- PetFollow.client.luau
			print("[QuestGate] hatch -> spawning Triceratops follower (clones TriceratopsTemplate, then follows you)")
			pcall(function() _G.SpawnTriceratopsFollower(base) end)
		elseif spawnEvt then
			print("[QuestGate] hatch -> firing HatchStegoSpawn (server floating pet, fallback)")
			pcall(function() spawnEvt:FireServer(base) end)
		else
			-- Fallback (server spawner not present): clone the SAME StegosaurusTemplate locally -- never a
			-- separate build, so the in-game pet can't drift from the Hub. Rise-pop (no ScaleTo on a union).
			local tmpl = ReplicatedStorage:FindFirstChild("StegosaurusTemplate") or ReplicatedStorage:WaitForChild("StegosaurusTemplate", 8)
			if tmpl then
				local pet = tmpl:Clone(); pet.Parent = workspace; st.pet = pet
				local n = 0; for _, d in ipairs(pet:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
				print(("[QuestGate] fallback in-game pet -> CLONED StegosaurusTemplate (%d parts)"):format(n))
				pcall(function() pet:PivotTo(base) end)
				local POP, p0 = 0.45, os.clock()
				while os.clock() - p0 < POP do
					local p = (os.clock() - p0) / POP
					pcall(function() pet:PivotTo(base * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
					task.wait()
				end
				task.spawn(function()
					local t = 0
					while st.pet and st.pet.Parent do
						t = t + 0.05
						pcall(function() st.pet:PivotTo(base * CFrame.new(0, 1.5 + math.sin(t*2)*0.4, 0) * CFrame.Angles(0, t*0.6, 0)) end)
						task.wait(0.05)
					end
				end)
			else
				warn("[QuestGate] StegosaurusTemplate not found -> no pet (resync + replay Stegosaurus.server.luau)")
			end
		end
		st.owns = true; st.hatching = false
		-- ===== NESTING NOOK HATCHES A TRICERATOPS, NOT A STEGOSAURUS =====
		-- The NPC standing over this nest is a MAMA TRICERATOPS. Handing out a Stego from her
		-- eggs was the one pet in the game that contradicted the island it came from, and it
		-- was the very first pet a new player ever earns. Swapped with Fern Frontier, which
		-- was giving the Triceratops and now gives the Stego -- see TriceratopsQuest.
		--
		-- NOTHING ELSE HAD TO MOVE. The Lost Eggs are a generic egg model, not a species one,
		-- so the egg, the nest and the rocking minigame are all unchanged; only which remote
		-- fires at the end of it does.
		if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("TriceratopsPet", { petId="TriceratopsPet", displayName="Triceratops", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
		-- tell the server to grant + equip it (PetUpgrades.server.luau drives level/XP/evolve)
		do local sh = ReplicatedStorage:FindFirstChild("TriceratopsHatched"); if sh then pcall(function() sh:FireServer() end) end end
		-- destroy the brown twig nest / egg shell IMMEDIATELY so it doesn't overlap the new pet
		if st.egg then pcall(function() st.egg:Destroy() end); st.egg = nil end
	end

	local function buildEgg(eggPos)
		local egg = Instance.new("Model"); egg.Name = "MamaDinoEgg"
		local nest = Instance.new("Model"); nest.Name = "Nest"; nest.Parent = egg
		local nestCenter = CFrame.new(eggPos + Vector3.new(0, 1.0, 0))
		for k = 1, 14 do
			local a = (k-1) * (2*math.pi/14)
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.2, 0.55, 0.55), Color3.fromRGB(105,65,38), nil, Enum.Material.Wood)
			twig.CFrame = nestCenter * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.7) * CFrame.Angles(0, math.rad(90), math.rad(18))
		end
		for k = 1, 10 do
			local a = (k-1) * (2*math.pi/10) + 0.3
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.0, 0.5, 0.5), Color3.fromRGB(90,55,32), nil, Enum.Material.Wood)
			twig.CFrame = nestCenter * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), math.rad(30))
		end
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), EGG_SHELL, nil); shell.Reflectance = 0.06
		local mesh = Instance.new("SpecialMesh"); mesh.MeshType = Enum.MeshType.Sphere; mesh.Scale = Vector3.new(3.0, 4.2, 3.0); mesh.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 9 do
			local a = (j-1) * (2*math.pi/9); local y = math.sin(a*1.8) * 1.05
			local r = 1.42 * math.sqrt(math.max(0, 1 - (y/2.1)^2)) + 0.04
			newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), EGG_SPOT, CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
		end
		st.baseCF = CFrame.new(eggPos + Vector3.new(0, 2.6, 0)); st.visual = visual; visual:PivotTo(st.baseCF); st.egg = egg
		local pr = Instance.new("ProximityPrompt"); pr.ActionText = "Hatch"; pr.ObjectText = "Mama's Egg"; pr.KeyboardKeyCode = Enum.KeyCode.E; pr.HoldDuration = 0; pr.MaxActivationDistance = 14; pr.RequiresLineOfSight = false; pr.Parent = shell
		pr.Triggered:Connect(function() hatch() end)
		task.spawn(function()
			local t = 0
			while st.egg do
				t = t + 0.05
				if st.egg.Parent and st.baseCF and st.visual and not st.hatching then
					pcall(function() st.visual:PivotTo(st.baseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.12, math.rad(math.sin(t*2)*5))) end)
				end
				task.wait(0.05)
			end
		end)
		egg.Parent = workspace
	end

	-- bottom-edge hint message
	local function showMamaHint()
		local sg = Instance.new("ScreenGui"); sg.Name = "MamaDinoHint"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 45; sg.Parent = playerGui
		local lbl = Instance.new("TextLabel"); lbl.AnchorPoint = Vector2.new(0.5, 1); lbl.Position = UDim2.new(0.5, 0, 1, -26); lbl.Size = UDim2.fromOffset(440, 46)
		lbl.BackgroundColor3 = Color3.fromRGB(20,20,20); lbl.BackgroundTransparency = 0.3; lbl.TextColor3 = Color3.fromRGB(255,255,255); lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.Text = "Talk to the Mama Dinosaur!"; lbl.Parent = sg
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = lbl
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(50,200,80); s.Thickness = 2; s.Parent = lbl
		local szc = Instance.new("UITextSizeConstraint"); szc.MaxTextSize = 26; szc.Parent = lbl

		-- HIDE IT OFF-ISLAND. This is a ScreenGui, so without a gate it stays stuck to the
		-- screen the whole time you fly up the rest of the tower, still telling you to go
		-- talk to a dinosaur 19,000 studs below. The chevron trail already hides itself
		-- off-island (ChevronTrail); the banner has to do the same.
		task.spawn(function()
			local island1 = workspace:FindFirstChild("island1")
			while sg.Parent do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local on = false
				if hrp and island1 then
					local ok, cf, size = pcall(function() return island1:GetBoundingBox() end)
					if ok and cf and size and size.Magnitude > 1 then
						local d = hrp.Position - cf.Position
						on = math.abs(d.X) <= size.X / 2 + 80
							and math.abs(d.Z) <= size.Z / 2 + 80
							and math.abs(d.Y) <= size.Y / 2 + 150
					end
				end
				sg.Enabled = on
				task.wait(0.4)
			end
		end)

		return sg
	end

	-- SLEEK GREEN CHEVRON RUNWAY on the ground -> the Mama Dino (same style as the island4 rod trail), plus the hint.
	-- Appears once all 5 eggs are returned (completeNow) and clears as you reach her / once the reward egg is hatched.
	-- The chevron runway itself now lives in the SHARED ChevronTrail module, so the
	-- island11 geyser quest (and any future quest) points at its reward with the exact
	-- same guide instead of re-implementing a different-looking arrow.
	local function guideToDino(dino)
		local hint = showMamaHint()
		local trail = ChevronTrail.start(
			function()
				return (dino and dino.Parent) and dino:GetPivot().Position or nil
			end,
			function()
				-- reward egg hatched, or the Mama Dino is gone -> tear down for good
				local done = st.owns or not (dino and dino.Parent)
				if done and hint then hint:Destroy(); hint = nil end
				return done
			end
		)
		return trail
	end

	-- trigger on quest completion (all eggs returned), or via the /done command
	task.spawn(function()
		local nook = ReplicatedStorage:WaitForChild("NestingNook", 60)
		local total = nook and nook:WaitForChild("TotalEggs", 10)
		local got = nook and nook:WaitForChild("EggsReturned", 10)
		local island = workspace:WaitForChild("island1", 60)
		local dino = waitForDescendant(island, "dino1", 60)
		local done = false
		local function completeNow()
			if done then return end
			done = true
			-- fallback: the nest centre (from the NestingNook attributes), never (0,5,0) in the void
			local pos = Vector3.new(
				tonumber(nook and nook:GetAttribute("NestX")) or 0,
				(tonumber(nook and nook:GetAttribute("NestY")) or 0) + 5,
				tonumber(nook and nook:GetAttribute("NestZ")) or 0
			)
			if dino then
				local pivot = dino:GetPivot()
				local cf, size = dino:GetBoundingBox()
				local bottom = cf.Position.Y - size.Y / 2
				local off = pivot.Position + pivot.RightVector * 8 -- beside the Mama Dino
				pos = Vector3.new(off.X, bottom + 7.5, off.Z) -- 7.5 studs up from the dino's surface
			end
			buildEgg(pos)
			setGlow()
			guideToDino(dino)
		end
		local function check()
			if total and got and total.Value > 0 and got.Value >= total.Value then completeNow() end
		end
		if got then got.Changed:Connect(check) end
		if total then total.Changed:Connect(check) end
		check()

		-- /done : skip straight to the reward (arrow + hint to the Mama Dino + hatchable egg)
		--
		-- "complete1" does the same from anywhere in the tower, whitelisted via DevAccess --
		-- the same pair DoneCommand.luau binds for every other quest. This island does NOT use
		-- that module (its completion is driven by the NestingNook egg counters above, not by a
		-- one-shot function), so the pair is spelled out here instead. Nesting Nook is slot 1
		-- AND model island1, so the number is 1 either way -- but it is the CLIMB SLOT that is
		-- being matched, same as every other complete<N>.
		local DevAccess = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("DevAccess"))
		local function onMessage(text)
			if not text then return end
			local cmd = string.gsub(string.lower(text), "%s", "")
			if cmd == "/done" then
				completeNow()
			elseif cmd == "complete1" or cmd == "/complete1" then
				if DevAccess.isAllowed(player) then completeNow() end
			end
		end
		player.Chatted:Connect(onMessage)
		pcall(function()
			local TextChatService = game:GetService("TextChatService")
			TextChatService.SendingMessage:Connect(function(m) onMessage(m.Text) end)
		end)
	end)
end
