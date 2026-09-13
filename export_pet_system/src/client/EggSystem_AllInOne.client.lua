--======================================================================
-- EggSystem_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the "complete a quest -> an egg appears -> hatch
-- it -> a pet pops out" system from the main game (PetFollow.client.lua),
-- ready to drop into a NEW world with ZERO other scripts/remotes/server code.
--
-- Everything that matters is copied VERBATIM so it looks + sounds identical:
--   * EGG LOOK   -- twiggy brown nest + one ovoid "Shell" (Sphere mesh scaled
--                   3.0 x 4.2 x 3.0) + 9 green speckles, gentle bob/wiggle,
--                   green "ready" glow when the quest is done.
--   * EGG SOUNDS -- crack  rbxassetid://126450028713974 (vol 3)
--                   unlock rbxassetid://92880640988467  (vol 3)
--                   shatter rbxassetid://9116458024      (vol 0.6)
--   * HATCH FLOW -- 2s shake (ramping) -> crack particle burst + flung shell
--                   shards -> pet scale-pops out of the nest.
--
-- The QUEST is a stripped-down stand-in (collect N pieces) so the file runs
-- on its own. Swap the CONFIG / buildPet to taste. Drop this one script into
-- StarterPlayer > StarterPlayerScripts (or sync via Rojo) and it runs.
--======================================================================

-- ===== DO NOT ADD THIS FILE TO default.project.json ==========================================
-- THIS IS A STANDALONE DEMO COPY, not the quest the game actually runs.
--
-- It lays its own props out AROUND THE PLAYER at runtime so the whole quest can be dropped into a
-- BLANK world with no markers, no server code and no remotes. That is the opposite of what the real
-- game needs: PetFollow already builds this quest properly, from the island's own marker parts, at
-- the island it belongs to.
--
-- Syncing this file was tried and reverted. Both copies ran, and the result was the Burrito dig
-- quest appearing on BEAN FARM (island 1) and the fishing quest hunting for a lake that was not on
-- the island the player was standing on:
--     ISLAND LANDING DETECTED: 1
--     [BurritoDig] dig quest ready -- grab the shovel...
--     [Fish] no part/model named 'ButterLake' found in Workspace
-- while PetFollow had already built the real one at (-404, 20230, 321) on island 13.
--
-- Keep it here as the portable reference it was written to be. If you ever DO want it live, delete
-- PetFollow's version of the same quest first -- never run both.
--
-- The guard below stays regardless: it costs nothing and it stops two copies fighting if this file
-- is ever loaded twice by any route.
if _G.__EggSystemClient then
	warn("[EggSystem] a second copy is running -- this one is bailing out. Delete the stale " ..
		"LocalScript in StarterPlayerScripts and re-sync Rojo.")
	return
end
_G.__EggSystemClient = true
do
	local removed = 0
	for _, inst in ipairs(script.Parent:GetDescendants()) do
		if inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			pcall(function() inst.Disabled = true; inst:Destroy() end)
			removed += 1
		end
	end
	if removed > 0 then
		warn("[EggSystem] removed " .. removed .. " STALE duplicate copy/copies -- delete them in Studio for good")
	end
end
-- ===========================================================================================
local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TweenService    = game:GetService("TweenService")
local SoundService    = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris          = game:GetService("Debris")

local player = Players.LocalPlayer

-- ============================================================================
-- CONFIG -- tweak these for your world. Positions are world-space Vector3s.
-- ============================================================================
local CONFIG = {
	label     = "Pet",                          -- shown in prompts/floats ("Pet Piece", "Pet Egg")
	eggPos    = Vector3.new(0, 5, 0),           -- where the nest + egg sit
	pieces    = {                               -- collect ALL of these -> egg appears
		Vector3.new(-12, 5, 6),
		Vector3.new(10, 5, -8),
		Vector3.new(4, 5, 14),
	},
	eggShell   = Color3.fromRGB(208, 232, 178),  -- shell color (broccoli-green default)
	eggSpot    = Color3.fromRGB(70, 150, 70),    -- speckle color
	petColor   = Color3.fromRGB(120, 210, 70),   -- placeholder pet color
}

-- ============================================================================
-- SOUNDS -- created + PRELOADED ONCE so they play INSTANTLY (verbatim asset ids).
-- ============================================================================
local hatchCrackSound = Instance.new("Sound")
hatchCrackSound.Name = "HatchCrackSound"; hatchCrackSound.SoundId = "rbxassetid://126450028713974"
hatchCrackSound.Volume = 3; hatchCrackSound.Parent = SoundService
local hatchUnlockSound = Instance.new("Sound")
hatchUnlockSound.Name = "HatchUnlockSound"; hatchUnlockSound.SoundId = "rbxassetid://92880640988467"
hatchUnlockSound.Volume = 3; hatchUnlockSound.Parent = SoundService
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ hatchCrackSound, hatchUnlockSound }) end) end)

-- ============================================================================
-- HELPERS
-- ============================================================================
-- newPart: the same simple part factory the main game uses for the egg pieces.
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

local function addPrompt(part, action, object, fn)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action; pr.ObjectText = object
	pr.KeyboardKeyCode = Enum.KeyCode.E; pr.HoldDuration = 0
	pr.MaxActivationDistance = 14; pr.RequiresLineOfSight = false
	pr.Parent = part
	pr.Triggered:Connect(fn)
	return pr
end

local function floatText(pos, text)
	local part = Instance.new("Part")
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false
	part.Transparency = 1; part.Size = Vector3.new(1,1,1); part.CFrame = CFrame.new(pos + Vector3.new(0,3,0)); part.Parent = Workspace
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,200,0,50); bb.AlwaysOnTop = true; bb.Parent = part
	local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1,1)
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true; lbl.TextColor3 = Color3.new(1,1,1)
	lbl.TextStrokeTransparency = 0; lbl.Text = text; lbl.Parent = bb
	TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { CFrame = part.CFrame + Vector3.new(0,3,0) }):Play()
	TweenService:Create(lbl, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(part, 1.3)
end

-- ============================================================================
-- PLACEHOLDER PET -- swap this for your real pet builder. It just needs to
-- return a Model with a PrimaryPart so the hatch pop animation can scale it.
-- ============================================================================
local function buildPet()
	local m = Instance.new("Model"); m.Name = "HatchedPet"
	local body = newPart(m, "Body", Enum.PartType.Ball, Vector3.new(2.4, 2.4, 2.4), CONFIG.petColor, nil)
	local eyeL = newPart(m, "EyeL", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(1,1,1), body.CFrame * CFrame.new(0.55, 0.4, 1.0))
	local eyeR = newPart(m, "EyeR", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(1,1,1), body.CFrame * CFrame.new(-0.55, 0.4, 1.0))
	m.PrimaryPart = body
	return m
end

-- ============================================================================
-- EGG STATE
-- ============================================================================
local st = {
	collected = {},   -- [i] = true
	pieces    = {},   -- [i] = piece model
	egg       = nil,  -- the egg container model (nest + visual)
	eggVisual = nil,  -- the BOBBING sub-model that cracks
	eggBaseCF = nil,
	eggPos    = CONFIG.eggPos,
	eggGlow   = nil,
	hatching  = false,
	owns      = false,
	pet       = nil,
}

-- ----------------------------------------------------------------------------
-- setEggGlow: the green "ready to hatch" highlight + point light + sparkles
-- (verbatim from PetFollow.client.lua:setEggGlow).
-- ----------------------------------------------------------------------------
local function setEggGlow(on)
	if on and not st.eggGlow and st.egg then
		local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(120,255,120); hl.FillTransparency=0.45
		hl.OutlineColor=Color3.fromRGB(230,255,180); hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = st.eggVisual or st.egg; hl.Parent = st.egg; st.eggGlow = hl
		local shell = st.egg:FindFirstChild("Shell", true)
		if shell then
			local pl=Instance.new("PointLight"); pl.Name="EggGlowLight"; pl.Color=Color3.fromRGB(150,255,150); pl.Brightness=4; pl.Range=26; pl.Parent=shell
			local em=Instance.new("ParticleEmitter"); em.Name="EggGlowSparkle"; em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Rate=16; em.Lifetime=NumberRange.new(0.6,1.1); em.Speed=NumberRange.new(2,6); em.Size=NumberSequence.new(0.9); em.LightEmission=0.85; em.Parent=shell
		end
	elseif not on and st.eggGlow then
		st.eggGlow:Destroy(); st.eggGlow=nil
		local shell = st.egg and st.egg:FindFirstChild("Shell", true)
		if shell then for _,n in ipairs({"EggGlowLight","EggGlowSparkle"}) do local o=shell:FindFirstChild(n); if o then o:Destroy() end end end
	end
end

-- ----------------------------------------------------------------------------
-- HATCH: press E -> shake -> crack -> pet pops out -> floats up.
-- (verbatim shake/crack/pop flow from PetFollow.client.lua:hatchEgg)
-- ----------------------------------------------------------------------------
local function hatchEgg()
	if not st or st.hatching or st.owns then return end
	st.hatching = true
	-- HATCH SOUND #1: the PRELOADED egg-CRACK sound the INSTANT the hatch begins.
	pcall(function() hatchCrackSound.TimePosition = 0; hatchCrackSound:Play() end)
	local prompt = st.egg and st.egg:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then prompt.Enabled = false end
	setEggGlow(false)
	local visual = st.eggVisual
	local base = st.eggBaseCF or CFrame.new((st.eggPos or Vector3.zero) + Vector3.new(0, 2.6, 0))

	-- 1) SHAKE ~2.0s, intensity ramps up
	local SHAKE, t0 = 2.0, os.clock()
	while os.clock() - t0 < SHAKE do
		local p = (os.clock() - t0) / SHAKE
		local amp = 0.1 + p * p * 0.9
		if visual and visual.PrimaryPart then
			pcall(function()
				visual:PivotTo(base
					* CFrame.new((math.random()-0.5)*amp*1.4, math.abs(math.sin((os.clock()-t0)*22))*amp*0.5, (math.random()-0.5)*amp*1.4)
					* CFrame.Angles(math.rad((math.random()-0.5)*amp*55), math.rad((math.random()-0.5)*amp*80), math.rad((math.random()-0.5)*amp*55)))
			end)
		end
		task.wait()
	end

	-- 2) CRACK: particle burst + sound, fling shell shards, remove the intact egg visual
	-- HATCH SOUND #2: the PRELOADED PET-UNLOCK sound lands HERE at the crack/shatter beat.
	pcall(function() hatchUnlockSound.TimePosition = 0; hatchUnlockSound:Play() end)
	pcall(function()
		local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(1,1,1); fx.CFrame=base; fx.Parent=Workspace
		local em=Instance.new("ParticleEmitter"); em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Lifetime=NumberRange.new(0.4,0.8); em.Speed=NumberRange.new(8,16); em.SpreadAngle=Vector2.new(180,180); em.Size=NumberSequence.new(1.4); em.Rate=0; em.LightEmission=0.9; em.Parent=fx
		em:Emit(40)
		local snd=Instance.new("Sound"); snd.SoundId="rbxassetid://9116458024"; snd.Volume=0.6; snd.Parent=fx; snd:Play()
		Debris:AddItem(fx, 1.2)
	end)
	if visual then
		pcall(function()
			for s = 1, 6 do
				local ang = (s-1) * (2*math.pi/6)
				local shard = Instance.new("Part"); shard.Shape=Enum.PartType.Ball; shard.Size=Vector3.new(1.1,0.7,1.1); shard.Color=Color3.fromRGB(210,234,182); shard.Material=Enum.Material.SmoothPlastic
				shard.Anchored=true; shard.CanCollide=false; shard.CanQuery=false; shard.CastShadow=false; shard.CFrame=base*CFrame.new(0,1,0); shard.Parent=Workspace
				TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{CFrame=base*CFrame.new(math.cos(ang)*5, math.random()*3-1, math.sin(ang)*5), Transparency=1, Size=Vector3.new(0.2,0.2,0.2)}):Play()
				Debris:AddItem(shard, 0.8)
			end
		end)
		pcall(function() visual:Destroy() end); st.eggVisual = nil
	end

	-- 3) PET POPS OUT: spawn it, scale-pop at the nest, then float up
	local pet = buildPet()
	pet.Parent = Workspace
	pcall(function() pet:PivotTo(base) end)
	st.pet = pet
	pcall(function() pet:ScaleTo(0.2) end)
	local POP, pop0 = 0.45, os.clock()
	while os.clock() - pop0 < POP do
		local p = (os.clock() - pop0) / POP
		pcall(function() pet:ScaleTo(0.2 + p * 0.8); pet:PivotTo(base * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
		task.wait()
	end
	pcall(function() pet:ScaleTo(1) end)

	st.owns = true
	st.hatching = false
	-- gentle idle float for the hatched pet
	task.spawn(function()
		local t = 0
		while st.pet and st.pet.Parent do
			t = t + 0.05
			pcall(function() st.pet:PivotTo(base * CFrame.new(0, 1.5 + math.sin(t*2)*0.4, 0) * CFrame.Angles(0, t*0.6, 0)) end)
			task.wait(0.05)
		end
	end)
	-- clean up the nest container after the pet is out
	task.delay(2.0, function() if st.egg then pcall(function() st.egg:Destroy() end); st.egg = nil end end)
end

-- ----------------------------------------------------------------------------
-- buildEgg: the EXACT egg look -- twiggy nest + ovoid shell + green speckles,
-- gentle bob/wiggle, Hatch prompt. (verbatim from PetFollow.client.lua:2356+)
-- Built hidden; revealed when the quest completes.
-- ----------------------------------------------------------------------------
local function buildEgg()
	local eggPos = st.eggPos
	local egg = Instance.new("Model"); egg.Name = CONFIG.label.."Egg" -- CONTAINER (egg visual + nest)

	-- NEST: low-poly brown twig ring/bowl the egg nestles into (STATIC -- does not bob).
	local nest = Instance.new("Model"); nest.Name = "Nest"; nest.Parent = egg
	local nestCenter = CFrame.new(eggPos + Vector3.new(0, 1.0, 0))
	for k = 1, 14 do
		local a = (k-1) * (2*math.pi/14)
		local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.2, 0.55, 0.55), Color3.fromRGB(105, 65, 38), nil, Enum.Material.SmoothPlastic)
		twig.CFrame = nestCenter * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.7) * CFrame.Angles(0, math.rad(90), math.rad(18))
	end
	for k = 1, 10 do -- a lower second layer for a bowl look
		local a = (k-1) * (2*math.pi/10) + 0.3
		local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.0, 0.5, 0.5), Color3.fromRGB(90, 55, 32), nil, Enum.Material.SmoothPlastic)
		twig.CFrame = nestCenter * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), math.rad(30))
	end

	-- EGG VISUAL: an ovoid (taller than wide) with green speckles. This sub-model BOBS and CRACKS.
	local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
	-- ONE smooth egg ovoid: a unit Part with a Sphere SpecialMesh stretched taller-than-wide.
	local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1, 1, 1), CONFIG.eggShell, nil)
	shell.Reflectance = 0.06 -- slight gloss
	local eggMesh = Instance.new("SpecialMesh")
	eggMesh.MeshType = Enum.MeshType.Sphere
	eggMesh.Scale = Vector3.new(3.0, 4.2, 3.0) -- W x H x D: taller than wide = egg shape
	eggMesh.Parent = shell
	visual.PrimaryPart = shell
	-- green speckles dusted around the single ovoid surface
	for j = 1, 9 do
		local a = (j-1) * (2*math.pi/9)
		local y = math.sin(a*1.8) * 1.05
		local r = 1.42 * math.sqrt(math.max(0, 1 - (y/2.1)^2)) + 0.04
		newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), CONFIG.eggSpot,
			CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
	end

	st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 2.6, 0)) -- the egg sits IN the nest
	st.eggVisual = visual
	visual:PivotTo(st.eggBaseCF)
	st.egg = egg

	addPrompt(shell, "Hatch", CONFIG.label.." Egg", function()
		if st.owns or st.hatching then return end
		hatchEgg()
	end)

	-- gentle idle bob/wiggle for the EGG VISUAL only (paused during the hatch); the nest stays still
	task.spawn(function()
		local t = 0
		while st.egg do
			t = t + 0.05
			if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
				pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.12, math.rad(math.sin(t*2)*5))) end)
			end
			task.wait(0.05)
		end
	end)

	egg.Parent = Workspace
end

-- ----------------------------------------------------------------------------
-- buildPiece: a simple collectible. Collect ALL of them -> the egg appears.
-- (Swap buildBlob for your real collectible model if you have one.)
-- ----------------------------------------------------------------------------
local function buildPiece(i, pos)
	local m = Instance.new("Model"); m.Name = CONFIG.label.."Piece"
	local body = newPart(m, "Body", Enum.PartType.Ball, Vector3.new(1.6, 1.6, 1.6), CONFIG.eggSpot, CFrame.new(pos))
	m.PrimaryPart = body
	m.Parent = Workspace
	-- little glow so they're findable
	local pl = Instance.new("PointLight"); pl.Color = CONFIG.petColor; pl.Brightness = 2; pl.Range = 12; pl.Parent = body
	st.pieces[i] = m

	addPrompt(body, "Collect", CONFIG.label.." Piece", function()
		if st.collected[i] or st.owns then return end
		st.collected[i] = true
		m:Destroy()
		local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
		floatText(pos, CONFIG.label.." piece "..count.."/"..#CONFIG.pieces.."!")
		if count >= #CONFIG.pieces then
			-- QUEST COMPLETE -> reveal the egg with the green "ready" glow
			buildEgg()
			setEggGlow(true)
			floatText(st.eggPos, "Egg appeared! Press E to hatch")
		end
	end)
end

-- ============================================================================
-- BOOT
-- ============================================================================
for i, pos in ipairs(CONFIG.pieces) do
	buildPiece(i, pos)
end
print("[EggSystem] ready -- collect "..#CONFIG.pieces.." pieces to reveal the egg")
