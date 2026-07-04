--======================================================================
-- BurritoDig_AllInOne.client.lua  (LocalScript)
--======================================================================
-- EXACTLY how Burrito Barrens (island 13) does its DIGGING quest + animation,
-- lifted VERBATIM from buildBurritoWorld (PetFollow.client.lua). Self-contained:
-- it lays the props out in front of you at runtime and runs the whole hunt.
--
-- THE QUEST (a ~3-minute hunt):
--   1. GRAB a shovel from the wooden barrel (E, 0.3s hold) -> a low-poly shovel
--      rides on your right hand, blade pointed down-forward.
--   2. DIG the mounds, ONE AT A TIME (the "Armadillo Trail"). Each E-tap = one
--      SWING: the mound SHRINKS a step (ScaleTo), bursts dirt, plays a dig sound,
--      and kicks the camera. 6 swings fully digs a mound.
--   3. A fully-dug DECOY reveals JUNK that RISES out of the hole + lays ARMADILLO
--      TRACKS toward the NEXT mound (which then appears). 5 decoys, then...
--   4. The final BuriedEggSpot reveals the real ARMADILLO EGG, which RISES up out
--      of the hole -> "Hatch" prompt -> hatch.
--
-- SERVER GATE (anti-cheat, noted at the bottom): digging the REAL spot fires
-- PetDigEvent so the server unlocks the claim -- the client can't fake the catch.
--
-- Drop into StarterPlayer > StarterPlayerScripts. (PetDigEvent is fired only if
-- the remote exists, so it runs standalone.)
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")
local HatchBurst = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst")) -- shared cool hatch FX

local player = Players.LocalPlayer
local petId  = "BurritoArmadillo"
local def    = {}
local PetDigEvent = RS:FindFirstChild("PetDigEvent") -- c->s: dug the REAL spot -> server unlocks the claim (optional here)

-- ===== generic helpers (from PetFollow.client.lua) =====
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end
local function addPrompt(rootPart, actionText, objectText, onTriggered)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText; pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0
	pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = rootPart
	pp.Triggered:Connect(onTriggered)
	return pp
end
local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,200,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(235,205,150); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(a, TweenInfo.new(1.4), {Transparency=1}):Play()
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.5, function() a:Destroy() end)
end
local function setVisible(model, on) if model then model.Parent = on and Workspace or nil end end

-- ===== single-pet state (the real game keys this per pet) =====
local st = { built=false, owns=false, hatching=false, hasShovel=false, eggCaught=false, digProps={} }
-- minimal quest-progress HUD stub (the game shows "Mounds X/6"); here it just prints
local localQuestProg = { [petId] = { found = 0 } }
local function pushQuestProg(id, fields) local lp = localQuestProg[id] or {}; for k,v in pairs(fields) do lp[k]=v end; localQuestProg[id]=lp
	if fields.found then print("[Dig][HUD] Mounds "..fields.found.."/"..(fields.total or 6)) end
	if fields.complete then print("[Dig][HUD] armadillo quest COMPLETE") end
end

-- ===== HATCH (island1-style: shake -> crack burst + shell shards -> pet pops + follower/hub) =====
local function hatchEgg()
	if st.hatching or st.owns then return end
	st.hatching = true
	print("[Dig] hatching the fossil egg!")
	local visual = st.eggVisual
	local base = st.eggBaseCF or CFrame.new((st.eggPos or Vector3.zero) + Vector3.new(0,1.7,0))
	-- crack sound the instant it starts
	pcall(function() local s = Instance.new("Sound"); s.SoundId = "rbxassetid://126450028713974"; s.Volume = 3; s.Parent = Workspace; s:Play(); Debris:AddItem(s, 2) end)
	-- 1) SHAKE ~1.6s, intensity ramps
	if visual then
		local t0 = os.clock()
		while os.clock() - t0 < 1.6 do
			local p = (os.clock()-t0)/1.6; local amp = 0.1 + p*p*0.9
			pcall(function() visual:PivotTo(base
				* CFrame.new((math.random()-0.5)*amp, math.abs(math.sin((os.clock()-t0)*22))*amp*0.4, (math.random()-0.5)*amp)
				* CFrame.Angles(0, math.rad((math.random()-0.5)*70), 0)) end)
			task.wait()
		end
	end
	-- 2) CRACK: shared COOL hatch explosion (flash + shockwave ring + sparkle blast + shell shards)
	HatchBurst.play(base.Position, Color3.fromRGB(224,194,148))
	if visual then pcall(function() visual:Destroy() end); st.eggVisual = nil end
	floatText((st.eggPos or Vector3.zero) + Vector3.new(0,3,0), "A baby Velociraptor hatched! \xF0\x9F\xA6\x96")
	st.owns = true; st.hatching = false
	if st.shovelTool then pcall(function() st.shovelTool:Destroy() end); st.shovelTool = nil end -- done digging -> put the shovel away
	-- 3) GIVE THE PET: spawn the raptor follower + add its Pet Hub card (exactly like island1's stego)
	if _G.SpawnRaptorFollower then pcall(function() _G.SpawnRaptorFollower(base) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("RaptorPet", { petId="RaptorPet", displayName="Velociraptor", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	-- grant + equip it server-side so the Pet Hub (driven by PetInventoryEvent) shows it, exactly like island1's stego
	do local rh = game:GetService("ReplicatedStorage"):FindFirstChild("RaptorHatched"); if rh then pcall(function() rh:FireServer() end) end end
	task.delay(1.0, function() if st.egg then pcall(function() st.egg:Destroy() end); st.egg = nil end end)
end

-- ============================================================================
-- THE DIG WORLD (VERBATIM from buildBurritoWorld). `positions` carries the marker
-- coords; the real game gets them from the server, here we lay them out in front
-- of the player.
-- ============================================================================
local function buildBurritoWorld(positions)
	if st.built then return end
	st.built = true; st.isDigging = true
	local extra = positions.extra or {}
	local shovelPos = extra.shovel
	local buriedPos = extra.buriedegg
	-- ARMADILLO TRAIL order: DigSpot1 -> 2 -> 3 -> 4 -> 5 -> BuriedEggSpot (one mound active at a time)
	local digSpots = {
		{ key="dig1", pos=extra.dig1, real=false, label="DigSpot1" },
		{ key="dig2", pos=extra.dig2, real=false, label="DigSpot2" },
		{ key="dig3", pos=extra.dig3, real=false, label="DigSpot3" },
		{ key="dig4", pos=extra.dig4, real=false, label="DigSpot4" },
		{ key="dig5", pos=extra.dig5, real=false, label="DigSpot5" },
		{ key="buriedegg", pos=buriedPos, real=true, label="BuriedEggSpot" },
	}
	st.digProps = {}

	local pgui = player:WaitForChild("PlayerGui")
	-- ===== HUD: a status pill for dig-result messages =====
	local hud = Instance.new("ScreenGui"); hud.Name = "BurritoDigHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 88; hud.Parent = pgui
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,470,0,40)
	status.BackgroundColor3 = Color3.fromRGB(150,96,40); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,225,150); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(t) statusText.Text = t; status.Visible = true end
	local function hideStatus() status.Visible = false end
	-- desert junk items (the in-world reveal that RISES out of a decoy hole uses these emoji)
	-- DINOSAUR BONES dug from the decoy spots (different fossil each time)
	local DIG_JUNK = { "a fossilized rib", "a dino skull", "a giant femur", "a clawed toe bone", "a spiky vertebra", "an ancient jawbone", "a curved tail bone" }
	local DIG_JUNK_EMOJI = { ["a fossilized rib"]="\xF0\x9F\xA6\xB4", ["a dino skull"]="\xF0\x9F\x92\x80", ["a giant femur"]="\xF0\x9F\xA6\xB4", ["a clawed toe bone"]="\xF0\x9F\xA6\xB4", ["a spiky vertebra"]="\xF0\x9F\xA6\xB4", ["an ancient jawbone"]="\xF0\x9F\xA6\xB4", ["a curved tail bone"]="\xF0\x9F\xA6\xB4" }

	-- ===== SHOVEL STYLE (classic spade: steel-blue blade, brown shaft, brown D-grip) =====
	local SH_WOOD   = Color3.fromRGB(120,75,45)    -- shaft + grip wood
	local SH_STEEL  = Color3.fromRGB(180,205,220)  -- light steel-blue blade
	local SH_COLLAR = Color3.fromRGB(90,100,110)   -- dark metal collar
	local SH_LEN    = 2.4                            -- shaft length
	-- Build the shovel as a real TOOL. Handle = the round wooden SHAFT (a Cylinder -- its long axis is local X).
	-- Built along local X: -X = UP (grip), +X = DOWN (blade). Tool.Grip stands it vertical with the blade down.
	local function buildShovelTool()
		local tool = Instance.new("Tool")
		tool.Name = "Shovel"; tool.ToolTip = "Dig"
		tool.RequiresHandle = true; tool.CanBeDropped = false

		local handle = Instance.new("Part")
		handle.Name = "Handle"; handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(SH_LEN, 0.18, 0.18)  -- round wooden shaft (long axis = X)
		handle.Color = SH_WOOD; handle.Material = Enum.Material.Wood
		handle.CanCollide = false; handle.Massless = true; handle.Anchored = false; handle.Parent = tool

		-- weld a part (positioned in handle-LOCAL space; handle starts at identity) to the Handle
		local function add(p, localCF)
			p.CanCollide = false; p.Massless = true; p.Anchored = false; p.CFrame = localCF; p.Parent = tool
			local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
			return p
		end
		local function part(name, shape, size, color, mat, localCF)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
			return add(p, localCF)
		end
		local function strut(name, a, b, r, color)
			local mid = (a + b) / 2; local len = (b - a).Magnitude
			return part(name, Enum.PartType.Cylinder, Vector3.new(len, r, r), color, Enum.Material.Wood,
				CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0))
		end

		local top = -SH_LEN / 2   -- grip end (UP, -X)
		local bot =  SH_LEN / 2   -- blade end (DOWN, +X)

		-- D-GRIP: a small brown triangular loop on TOP of the shaft (3 thin cylinders)
		local apex = Vector3.new(top + 0.02, 0, 0)
		local bl   = Vector3.new(top - 0.5, 0, -0.35)
		local br   = Vector3.new(top - 0.5, 0,  0.35)
		strut("Grip", apex, bl, 0.09, SH_WOOD)
		strut("Grip", apex, br, 0.09, SH_WOOD)
		part("Grip", Enum.PartType.Cylinder, Vector3.new(0.72, 0.09, 0.09), SH_WOOD, Enum.Material.Wood, CFrame.new(top - 0.5, 0, 0) * CFrame.Angles(math.rad(90), 0, 0)) -- cross-bar

		-- COLLAR: dark metal band at the shaft bottom (hides the blade<->shaft join)
		part("Collar", Enum.PartType.Cylinder, Vector3.new(0.25, 0.24, 0.24), SH_COLLAR, Enum.Material.Metal, CFrame.new(bot - 0.02, 0, 0))

		-- BLADE: ONE clean flattened oval STEEL spade. Its TOP is welded right at the collar and it extends
		-- straight DOWN the shaft to a rounded point. (A flattened Cylinder = one smooth blade -- no seams, no
		-- floating; offset along its OWN length axis so the top always touches the collar.)
		local join = bot + 0.05
		local bladeCF = CFrame.new(join, 0, 0) * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 0.8, 0)
		part("Blade", Enum.PartType.Cylinder, Vector3.new(0.14, 1.6, 1.3), SH_STEEL, Enum.Material.SmoothPlastic, bladeCF)

		-- GRIP the MIDDLE of the shaft; +90 about Z stands the shaft vertical with the blade pointing DOWN
		tool.Grip = CFrame.Angles(0, 0, math.rad(90))

		-- VERIFY: print each part's position relative to the Handle (X = shaft axis: + = down/blade, - = up/grip)
		for _, p in ipairs(tool:GetChildren()) do
			if p:IsA("BasePart") then
				local rel = (handle.CFrame:Inverse() * p.CFrame).Position
				print(("[Shovel] %-7s alongShaft(X)=%+.2f  (Y=%.2f, Z=%.2f)"):format(p.Name, rel.X, rel.Y, rel.Z))
			end
		end
		return tool
	end

	-- ===== AUTO-GIVE the shovel as a held TOOL (the Digger hands you one when the quest is accepted) =====
	local function equipFreshShovel()
		if st.owns then return end
		if st.shovelTool then pcall(function() st.shovelTool:Destroy() end) end
		local tool = buildShovelTool(); st.shovelTool = tool
		local char = player.Character
		local bp = player:FindFirstChildOfClass("Backpack")
		tool.Parent = bp or char or Workspace
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then task.defer(function() pcall(function() hum:EquipTool(tool) end) end) end
	end
	st.hasShovel = true
	equipFreshShovel()
	player.CharacterAdded:Connect(function() task.wait(0.4); equipFreshShovel() end) -- re-give after respawn (Backpack resets)
	print("[Pet] shovel TOOL given by the Digger -- dig the mounds now")

	local N_SWINGS = 6 -- E-taps ("swings") to fully dig a mound away
	-- a dug-up JUNK item RISES out of the decoy hole (in-world reveal), holds, then fades
	local function junkRise(pos, junkName)
		local j = newPart(Workspace, petId.."DugJunk", Enum.PartType.Ball, Vector3.new(1.3,1.3,1.3), Color3.fromRGB(232,224,202), CFrame.new(pos + Vector3.new(0, -3.0, 0)), Enum.Material.SmoothPlastic)
		st.digProps[#st.digProps+1] = j
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,64,0,64); bb.StudsOffset = Vector3.new(0,2.0,0); bb.AlwaysOnTop = true; bb.Adornee = j; bb.Parent = j
		local lb = Instance.new("TextLabel"); lb.Size = UDim2.new(1,0,1,0); lb.BackgroundTransparency = 1; lb.Font = Enum.Font.GothamBold; lb.TextSize = 50; lb.Text = DIG_JUNK_EMOJI[junkName] or "\xF0\x9F\xA6\xB4"; lb.Parent = bb
		TS:Create(j, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) }):Play()
		task.delay(2.4, function()
			pcall(function() lb.TextTransparency = 1 end)
			TS:Create(j, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.6, function() pcall(function() j:Destroy() end) end)
		end)
	end

	-- ===== the ARMADILLO EGG RISES UP out of the real hole -> Hatch prompt =====
	local function spawnArmadilloEgg(atPos)
		if st.egg then return end
		st.eggPos = atPos; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(224,194,148), nil)
		shell.Reflectance = 0.05
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 6 do local a = (j-1)*(2*math.pi/6); newPart(visual, "Speck", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(176,118,64), CFrame.new(math.sin(a)*1.2, (j%2==0 and 0.5 or -0.5), math.cos(a)*1.2)) end
		local eggCenter = atPos + Vector3.new(0, 1.7, 0)
		st.eggBaseCF = CFrame.new(eggCenter); st.eggVisual = visual
		local startCF = CFrame.new(atPos + Vector3.new(0, -3.4, 0)) -- start DOWN inside the dug hole...
		st.eggRising = true; visual:PivotTo(startCF)
		st.egg = egg; egg.Parent = Workspace; st.digProps[#st.digProps+1] = egg
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(235,205,150); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(210,168,90); hl.Adornee = visual; hl.Parent = egg
		local hp = addPrompt(shell, "Hatch", "Armadillo Egg", function()
			if st.owns or st.hatching then return end
			hatchEgg()
		end)
		hp.Enabled = false -- can't hatch until it has fully risen out of the ground
		-- RISE: tween the egg UP out of the hole (a CFrame lerp via a NumberValue, since Models can't tween directly)
		task.spawn(function()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; pcall(function() visual:PivotTo(startCF:Lerp(st.eggBaseCF, t)) end) end)
			TS:Create(nv, TweenInfo.new(1.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
			task.wait(1.2); st.eggRising = false; pcall(function() nv:Destroy() end); hp.Enabled = true
		end)
		-- gentle bob (only AFTER it has risen + while not hatching)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching and not st.eggRising then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] armadillo egg rose out of the ground for "..player.Name)
	end

	-- ===== ARMADILLO TRAIL: low-poly dirt mounds dug ONE AT A TIME =====
	local DIRT, DIRT2 = Color3.fromRGB(150,110,70), Color3.fromRGB(134,96,58)
	-- a LOW-POLY DIRT PILE: stacked, rotated square blocks tapering up into a faceted pile. Digging shrinks the model.
	local function buildMound(pos)
		local m = Instance.new("Model"); m.Name = petId.."DigMound"
		local base
		for i, L in ipairs({
			{ w=5.4, h=1.3, y=0.65, yaw=0,  col=DIRT  },
			{ w=4.0, h=1.3, y=1.75, yaw=45, col=DIRT2 },
			{ w=2.7, h=1.2, y=2.75, yaw=20, col=DIRT  },
			{ w=1.5, h=1.1, y=3.6,  yaw=58, col=DIRT2 },
		}) do
			local p = newPart(m, "MoundLayer", Enum.PartType.Block, Vector3.new(L.w, L.h, L.w), L.col, CFrame.new(pos + Vector3.new(0, L.y, 0)) * CFrame.Angles(0, math.rad(L.yaw), 0), Enum.Material.Sand)
			if i == 1 then base = p end
		end
		m.PrimaryPart = base
		m.Parent = Workspace
		return m
	end
	-- ARMADILLO TRACKS: a line of footprint marks (flat oval + 3 toe dots) leading MOST of the way to the next mound.
	local function spawnTracks(fromPos, toPos)
		if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then return end
		local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
		local dist = flat.Magnitude; if dist < 3 then return end
		local dir = flat.Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local n = math.clamp(math.floor(dist / 4), 5, 30)  -- denser trail
		for k = 1, n do
			local frac = (k / (n + 1)) * 0.9 + 0.05
			local p = fromPos + dir * (dist * frac)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character }; rp.IgnoreWater = true
			local hit = Workspace:Raycast(p + Vector3.new(0,14,0), Vector3.new(0,-90,0), rp)
			local y = hit and hit.Position.Y or p.Y
			local side = (k % 2 == 0) and 1 or -1
			local fp = Vector3.new(p.X, y + 0.14, p.Z) + right * (side * 0.7)
			local cf = CFrame.lookAt(fp, fp + dir)
			-- BIG GLOWING footprint (neon) + 3 toe dots, all fading in
			local prints = {}
			local foot = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(1.35,0.2,2.0), Color3.fromRGB(255,196,84), cf, Enum.Material.Neon)
			foot.Transparency = 1; st.digProps[#st.digProps+1] = foot; prints[#prints+1] = foot
			for _, tx in ipairs({ -0.45, 0, 0.45 }) do
				local toe = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.4,0.16,0.4), Color3.fromRGB(255,216,120), cf * CFrame.new(tx, 0, -1.05), Enum.Material.Neon)
				toe.Transparency = 1; st.digProps[#st.digProps+1] = toe; prints[#prints+1] = toe
			end
			-- rising golden sparkle on each print so the trail pops from a distance
			local em = Instance.new("ParticleEmitter")
			em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(255,228,150)); em.LightEmission = 0.85
			em.Lifetime = NumberRange.new(0.6,1.2); em.Rate = 7; em.Speed = NumberRange.new(0.6,1.8)
			em.Size = NumberSequence.new(0.55); em.Rotation = NumberRange.new(0,360)
			em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.2), NumberSequenceKeypoint.new(1,1) })
			em.EmissionDirection = Enum.NormalId.Top; em.Parent = foot
			for _, pr in ipairs(prints) do TS:Create(pr, TweenInfo.new(0.3), { Transparency = 0.05 }):Play() end
		end
	end

	local spots = {}   -- [i] = { spot, mound, prompt } (or false if the marker position is missing)
	local activateStep -- forward-decl (doSwing advances the trail via this)
	local activeBeacon -- floating "DIG HERE" marker over the current dig spot
	local guideTarget  -- active dig-spot pos the dynamic footprint trail leads to (nil = no trail)

	for i, spot in ipairs(digSpots) do
		if typeof(spot.pos) ~= "Vector3" then
			spots[i] = false
		else
			local mound = buildMound(spot.pos); setVisible(mound, false) -- built hidden; shown when active
			st.digProps[#st.digProps+1] = mound
			-- the "Dig" prompt rides on its OWN persistent anchor, so shrinking the mound never removes it -> re-arms each E.
			local promptAnchor = newPart(Workspace, petId.."DigPrompt", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(spot.pos + Vector3.new(0,1.5,0)))
			promptAnchor.Transparency = 1; st.digProps[#st.digProps+1] = promptAnchor
			local swings, fxAnchor, em, snd, done = 0, nil, nil, nil, false
			local prompt -- forward-decl so doSwing can disable it on the final swing
			local function doSwing()
				if not fxAnchor then
					fxAnchor = newPart(Workspace, petId.."DigFX", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,84,52), CFrame.new(spot.pos + Vector3.new(0,0.6,0)))
					fxAnchor.Transparency = 1
					em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/smoke_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(150,110,70), Color3.fromRGB(110,78,46)); em.Lifetime = NumberRange.new(0.4,0.85)
					em.Speed = NumberRange.new(10,18); em.SpreadAngle = Vector2.new(40,40); em.EmissionDirection = Enum.NormalId.Top
					em.Acceleration = Vector3.new(0,-44,0); em.Size = NumberSequence.new(0.9); em.Rate = 0; em.Rotation = NumberRange.new(0,360); em.Parent = fxAnchor
					snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://9114065998"; snd.Volume = 0.55; snd.Parent = fxAnchor -- PLACEHOLDER dirt/shovel dig sound -- swap freely
				end
				swings = swings + 1
				pcall(function() mound:ScaleTo(math.max(0.06, 1 - swings / N_SWINGS)) end) -- SHRINK the low-poly mound away one step
				pcall(function() em:Emit(20) end)                              -- DIRT burst this swing
				pcall(function() snd.TimePosition = 0; snd:Play() end)         -- dig SOUND this swing
				pcall(function()                                               -- small camera kick for feel
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then hum.CameraOffset = Vector3.new((math.random()-0.5)*0.5, -0.35, 0); TS:Create(hum, TweenInfo.new(0.18), {CameraOffset = Vector3.zero}):Play() end
				end)
				print(string.format("[Pet][DIG] swing %d/%d on %s", swings, N_SWINGS, spot.label))
				if swings >= N_SWINGS then -- mound fully dug -> reveal + advance the trail
					done = true; prompt.Enabled = false
					if activeBeacon then pcall(function() activeBeacon:Destroy() end); activeBeacon = nil end -- clear the beacon
					guideTarget = nil -- stop the trail until the next spot activates
					pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1, total = #digSpots }) -- HUD: "Mounds X/6"
					pcall(function() setVisible(mound, false) end)
					if em then task.delay(0.4, function() em.Enabled = false end) end
					if fxAnchor then Debris:AddItem(fxAnchor, 1.2) end
					if spot.real then
						print("[Pet][DIG] BuriedEggSpot dug -> EGG rises")
						if PetDigEvent then pcall(function() PetDigEvent:FireServer(petId) end) end -- server unlocks the claim (anti-cheat gate)
						pushQuestProg(petId, { complete = true })
						setStatus("You unearthed the fossilized egg! \xF0\x9F\xA5\x9A"); task.delay(2.6, hideStatus)
						spawnArmadilloEgg(spot.pos)
					else
						local junk = DIG_JUNK[math.random(1, #DIG_JUNK)]
						junkRise(spot.pos, junk)
						-- (the live guide trail re-points to the next spot when it activates below)
						setStatus("You dug up: "..junk.."! Follow the glowing tracks..."); task.delay(2.6, hideStatus)
						task.delay(0.4, function() activateStep(i + 1) end)
					end
				end
			end
			prompt = addPrompt(promptAnchor, "Dig", "Dig Spot", function() -- each E-tap = ONE swing (HoldDuration 0)
				if st.owns or st.eggCaught or done then return end
				if not st.hasShovel then floatText(spot.pos + Vector3.new(0,3,0), "Grab a shovel first!"); return end
				doSwing()
			end)
			prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12; prompt.Enabled = false -- enabled by activateStep when active
			spots[i] = { spot = spot, mound = mound, prompt = prompt }
		end
	end

	-- show + enable the active step's mound (one at a time); skip any step whose marker is missing
	activateStep = function(n)
		if n > #digSpots then return end
		local e = spots[n]
		if not e then return activateStep(n + 1) end
		setVisible(e.mound, true)
		-- floating beacon so the player can spot the active dig site from afar
		if activeBeacon then pcall(function() activeBeacon:Destroy() end); activeBeacon = nil end
		local bcn = newPart(Workspace, petId.."DigBeacon", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(e.spot.pos + Vector3.new(0, 4.5, 0)))
		bcn.Transparency = 1; st.digProps[#st.digProps+1] = bcn
		local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(255,210,110); pl.Brightness = 3; pl.Range = 18; pl.Parent = bcn
		local bb = Instance.new("BillboardGui"); bb.Adornee = bcn; bb.AlwaysOnTop = true; bb.Size = UDim2.fromOffset(150, 64); bb.Parent = bcn
		local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1,1); lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255,225,120); lbl.TextStrokeColor3 = Color3.new(0,0,0); lbl.TextStrokeTransparency = 0; lbl.Text = "\xE2\x9B\x8F DIG HERE"; lbl.Parent = bb
		activeBeacon = bcn
		guideTarget = e.spot.pos -- the live footprint trail now leads here
		if not st.owns and not st.eggCaught then e.prompt.Enabled = true end
		print(string.format("[Pet][DIG] active mound: %s (trail step %d/%d)", e.spot.label, n, #digSpots))
	end
	if not st.owns then activateStep(1) end -- start the Armadillo Trail at the first mound

	-- LIVE GUIDE: glowing footprints re-laid from the PLAYER toward the active dig spot every frame,
	-- so the trail always leads the way -- if you walk off course, the prints point back toward the spot.
	do
		local POOL = 6
		local pool = {}
		for i = 1, POOL do
			local fp = newPart(Workspace, petId.."GuideTrack", Enum.PartType.Ball, Vector3.new(1.3,0.2,1.95), Color3.fromRGB(255,196,84), CFrame.new(0,-1000,0), Enum.Material.Neon)
			fp.Transparency = 0.05; st.digProps[#st.digProps+1] = fp; pool[i] = fp
		end
		local function hideAll() for _, fp in ipairs(pool) do fp.CFrame = CFrame.new(0, -1000, 0) end end
		RunService.RenderStepped:Connect(function()
			if st.owns then return hideAll() end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not (hrp and typeof(guideTarget) == "Vector3") then return hideAll() end
			local flat = Vector3.new(guideTarget.X - hrp.Position.X, 0, guideTarget.Z - hrp.Position.Z)
			local d = flat.Magnitude
			if d < 6 then return hideAll() end -- close enough: the beacon + dig prompt take over
			local dir = flat.Unit
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { char }; rp.IgnoreWater = true
			for i, fp in ipairs(pool) do
				local ahead = 2.5 + (i - 1) * 3 -- 2.5, 5.5, 8.5 ... studs from the player toward the spot
				if ahead > d - 2 then fp.CFrame = CFrame.new(0, -1000, 0) -- don't overshoot the spot
				else
					local base = hrp.Position + dir * ahead
					local hit = Workspace:Raycast(base + Vector3.new(0,10,0), Vector3.new(0,-60,0), rp)
					local y = hit and hit.Position.Y or base.Y
					local side = (i % 2 == 0) and 1 or -1
					local pos = Vector3.new(base.X, y + 0.14, base.Z) + right * (side * 0.6)
					fp.CFrame = CFrame.lookAt(pos, pos + dir)
				end
			end
		end)
	end
end

-- ============================================================================
-- LAYOUT: drop the shovel barrel + a wandering 6-stop trail in front of the
-- player (the real game gets these positions from the server's island markers).
-- ============================================================================
-- Build the dig spots from the 5 parts named "Dig" inside island3 (the player's markers).
-- The markers are HIDDEN (just position anchors); the LAST one along the path becomes the real
-- BuriedEggSpot, the rest are decoys. The shovel barrel is placed just beside the first spot.
local function makePositions()
	local island3 = Workspace:WaitForChild("island3", 30)
	local markers = {}
	if island3 then
		for _, d in ipairs(island3:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Dig" then markers[#markers+1] = d end
		end
	end
	if #markers == 0 then
		warn("[BurritoDig] no parts named 'Dig' found inside island3 -> dig quest not built")
		return { extra = {} }
	end
	-- HIDE the marker blocks (invisible, non-colliding, skipped by raycasts)
	for _, m in ipairs(markers) do m.Transparency = 1; m.CanCollide = false; m.CanQuery = false end

	-- order the markers into a walkable path (greedy nearest-neighbour from the first found)
	local ordered, remaining = {}, {}
	for _, m in ipairs(markers) do remaining[#remaining+1] = m end
	local cur = table.remove(remaining, 1); ordered[1] = cur
	while #remaining > 0 do
		local bi, bd = 1, math.huge
		for i, m in ipairs(remaining) do
			local dd = (m.Position - cur.Position).Magnitude
			if dd < bd then bd = dd; bi = i end
		end
		cur = table.remove(remaining, bi); ordered[#ordered+1] = cur
	end

	-- ground a point to island3's floor (markers are CanQuery=false, so they're ignored)
	local function ground(p)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character }
		local hit = Workspace:Raycast(p + Vector3.new(0,12,0), Vector3.new(0,-200,0), rp)
		return hit and Vector3.new(p.X, hit.Position.Y, p.Z) or p
	end

	-- map ordered markers -> dig stops; the LAST marker is the real buried egg
	local extra = {}
	local keys = { "dig1", "dig2", "dig3", "dig4", "dig5" }
	local n = #ordered
	for i = 1, n do
		local mk = ordered[i]
		local pos = Vector3.new(mk.Position.X, mk.Position.Y - mk.Size.Y / 2, mk.Position.Z) -- mound base = marker's bottom (where it meets the ground)
		if i == n then extra.buriedegg = pos else extra[keys[i] or ("dig" .. i)] = pos end
	end
	-- shovel barrel RIGHT BY the Digger NPC so the player grabs it straight after the chat
	local npc = Workspace:FindFirstChild("DigMiner")
	if npc then
		local pv = npc:GetPivot()
		extra.shovel = ground(pv.Position + pv.LookVector * 4)
	else
		extra.shovel = ground(ordered[1].Position + Vector3.new(6, 0, 0))
	end
	print(("[BurritoDig] built %d dig spot(s) on island3 (%d decoys + 1 buried egg)"):format(n, math.max(0, n - 1)))
	return { extra = extra }
end

-- Hide the "Dig" marker blocks right away (they're just position anchors), even before the quest starts.
task.spawn(function()
	local island3 = Workspace:WaitForChild("island3", 30)
	if island3 then
		for _, d in ipairs(island3:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Dig" then d.Transparency = 1; d.CanCollide = false; d.CanQuery = false end
		end
	end
end)

-- Build the dig trail ONLY after the island3 "Digger" NPC grants the quest (DigQuestAccepted attribute).
local function startDig()
	buildBurritoWorld(makePositions())
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	floatText((hrp and hrp.Position or Vector3.new(0,5,0)) + Vector3.new(0,4,0), "Grab the shovel + follow the tracks to dig up the egg! \xE2\x9B\x8F")
	print("[BurritoDig] dig quest STARTED (Digger NPC accepted)")
end
if player:GetAttribute("DigQuestAccepted") then
	startDig()
else
	local conn
	conn = player:GetAttributeChangedSignal("DigQuestAccepted"):Connect(function()
		if player:GetAttribute("DigQuestAccepted") then
			if conn then conn:Disconnect() end
			startDig()
		end
	end)
	print("[BurritoDig] waiting for the island3 Digger NPC to grant the dig quest...")
end

-- ===== /done : instantly unlock the Velociraptor (skip the digging) -- follower + Pet Hub card =====
local function grantRaptorNow()
	if st.owns then return end
	st.owns = true
	if st.shovelTool then pcall(function() st.shovelTool:Destroy() end); st.shovelTool = nil end -- put the shovel away
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local at = hrp and (hrp.CFrame * CFrame.new(0, 0, -6)) or CFrame.new(0, 8, 0)
	if _G.SpawnRaptorFollower then pcall(function() _G.SpawnRaptorFollower(at) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("RaptorPet", { petId="RaptorPet", displayName="Velociraptor", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	do local rh = game:GetService("ReplicatedStorage"):FindFirstChild("RaptorHatched"); if rh then pcall(function() rh:FireServer() end) end end -- server grant -> Pet Hub card
	if PetDigEvent then pcall(function() PetDigEvent:FireServer(petId) end) end
	floatText((hrp and hrp.Position or Vector3.zero) + Vector3.new(0,4,0), "Velociraptor unlocked! \xF0\x9F\xA6\x96")
	print("[BurritoDig] /done -> Velociraptor granted (follower + Pet Hub)")
end
local function onRaptorChat(text)
	if text and string.gsub(string.lower(text), "%s", "") == "/done" then grantRaptorNow() end
end
player.Chatted:Connect(onRaptorChat)
pcall(function()
	game:GetService("TextChatService").SendingMessage:Connect(function(m) onRaptorChat(m.Text) end)
end)

-- ============================================================================
-- SERVER GATE (for reference -- in PetSystem.server.lua):
--   PetDigEvent.OnServerEvent: digEggReady[player] = true  (set when the REAL spot is dug)
--   PetClaimEvent: rejects the BurritoArmadillo claim unless digEggReady[player] is set,
--   so a client can never fake unearthing the egg. digEggReady is session-only (re-dig on rejoin).
-- ============================================================================
