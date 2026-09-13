--======================================================================
-- LivingFossil.client.luau  (LocalScript)
--======================================================================
-- Island3 "Fossil Frontier" (climb slot 5) quest: THE LIVING FOSSIL.
-- REPLACES BurritoDig's shovel dig-trail (6 E-taps per mound, five mounds --
-- cut for being a flat button-hold with zero decisions).
--
-- THE QUEST (a few minutes of detective work, ONE dig that matters):
--   1. Talk to the Digger (sets DigQuestAccepted -- same gate as before).
--   2. Take his AMBER LENS ([E] at the lens glowing by his hands; short
--      zoom-in handoff). The world tints amber and GHOST SKELETONS fade
--      in, glowing under the dirt at every buried-fossil signature.
--   3. One of those fossils has a HEARTBEAT. Walk near a signature and
--      you HEAR it: dead ones give a dull stone clack... the living one
--      goes thump-thump, faster and louder as you close in, with a
--      screen pulse on every beat.
--   4. He stamps you 3 EXCAVATION PERMITS, so you cannot dig everything
--      -- read the heartbeats before you spend one. A wrong dig is a
--      comedy reveal (an old boot, a rubber duck, a rock). Out of
--      permits? He sighs and stamps three more. No fail state.
--   5. The right dig uncovers a SLEEPING BABY BRACHIOSAURUS curled in
--      the earth -- it was never a fossil. "Wake Up Gently" -> yawn
--      cutscene -> it's your pet (fires the exact same grant BurritoDig
--      used: _G.SpawnBrachiosaurusFollower + Pet Hub card +
--      BrachiosaurusHatched; PetDigEvent still fires on the real find
--      so the server-side unlock is unchanged).
--
-- SIGNATURE SPOTS: the island's existing 'Dig' marker parts (Dig, Dig1,
-- ...) -- found ANYWHERE over island3, ghosted like all placement
-- markers. 5+ markers recommended (1 is the living one, the rest decoys).
-- Fewer than 3 found -> probed fallback spots + a warn.
--
-- All client-side and anchored (GeyserQuest's pattern). The amber tint is
-- a client ColorCorrection -- other players see nothing. /done (or
-- complete5) skips straight to the grant.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local TS        = game:GetService("TweenService")
local Lighting  = game:GetService("Lighting")

local DinoRealm   = RS:WaitForChild("DinosaurRealm")
local DoneCommand = require(DinoRealm:WaitForChild("DoneCommand"))
local HatchBurst  = require(DinoRealm:WaitForChild("HatchBurst"))

local player = Players.LocalPlayer

-- ===== tuning =====
local PERMITS_PER_BATCH = 3
local HEAR_RANGE  = 30      -- studs: how far out a signature becomes audible
local CHIME_ID = "rbxasset://sounds/electronicpingshort.wav"

-- pets face +X (the Brachio builder's ASCII side view: "pet faces RIGHT")
local FACE_FIX = CFrame.Angles(0, math.rad(90), 0)

-- SOUND IDS -- the owner's picks, already licensed to this game (see FernThief).
local SOUNDS = {
	rustle  = "rbxassetid://5108956689",     -- dirt burst
	woodHit = "rbxassetid://9118617342",     -- dig impact + the decoys' stone CLACK
	sadGag  = "rbxassetid://104211465655831",-- wrong-dig comedy sting
	shimmer = "rbxassetid://136730840543746",-- amber lens sparkle
	success = "rbxassetid://115778296381875",-- the living fossil is FOUND
	love    = "rbxassetid://130304040865448",-- the gentle wake-up
}

local AMBER  = Color3.fromRGB(255, 200, 110)
local BONE   = Color3.fromRGB(235, 225, 200)
local DIRT   = Color3.fromRGB(112, 84, 56)
local MUD    = Color3.fromRGB(78, 60, 42)
local WARM   = Color3.fromRGB(255, 210, 120)
local GOLDEN = Color3.fromRGB(255, 224, 130)

local st = { started = false, done = false, lensTaken = false, permits = 0,
	found = false }

-- ===== helpers (same idioms as FernThief) =====
local function floatText(pos, text, color, offY)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.CanTouch=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	-- MaxDistance is LOAD-BEARING: AlwaysOnTop offset-size billboards render at
	-- constant screen size from ANY distance (see FernThief's note).
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,52); bb.StudsOffset=Vector3.new(0,offY or 3,0); bb.AlwaysOnTop=true; bb.MaxDistance=250; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=24; lbl.TextColor3=color or Color3.fromRGB(235,225,190); lbl.Text=text; lbl.TextWrapped=true; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(2.4), {TextTransparency=1}):Play()
	task.delay(2.6, function() a:Destroy() end)
end

local function chime(parent, pitch, volume)
	local s = Instance.new("Sound")
	s.SoundId = CHIME_ID; s.PlaybackSpeed = pitch; s.Volume = volume or 0.8
	s.RollOffMinDistance = 14; s.RollOffMaxDistance = 260
	s.Parent = parent; s:Play()
	s.Ended:Once(function() s:Destroy() end); task.delay(4, function() pcall(function() s:Destroy() end) end)
end

local function sfx(parent, id, volume, pitch)
	if not parent or not id then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.7; s.PlaybackSpeed = pitch or 1
	s.RollOffMinDistance = 14; s.RollOffMaxDistance = 300
	s.Parent = parent; s:Play()
	s.Ended:Once(function() s:Destroy() end); task.delay(10, function() pcall(function() s:Destroy() end) end)
end

-- ===== on-screen objective banner (amber chrome) =====
local hudLbl, hudGui
local function buildHUD(isl)
	local pgui = player:WaitForChild("PlayerGui")
	hudGui = Instance.new("ScreenGui"); hudGui.Name = "LivingFossilHUD"; hudGui.ResetOnSpawn = false
	hudGui.IgnoreGuiInset = true; hudGui.DisplayOrder = 60; hudGui.Enabled = false; hudGui.Parent = pgui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0); f.Position = UDim2.new(0.5, 0, 0, 92)
	f.Size = UDim2.fromOffset(420, 44); f.BackgroundColor3 = Color3.fromRGB(62, 48, 30); f.BackgroundTransparency = 0.08; f.Parent = hudGui
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
	local s = Instance.new("UIStroke", f); s.Color = AMBER; s.Thickness = 2
	hudLbl = Instance.new("TextLabel"); hudLbl.Size = UDim2.new(1, -16, 1, 0); hudLbl.Position = UDim2.new(0, 8, 0, 0)
	hudLbl.BackgroundTransparency = 1; hudLbl.Font = Enum.Font.FredokaOne; hudLbl.TextScaled = true
	hudLbl.TextColor3 = Color3.fromRGB(250, 235, 205); hudLbl.Parent = f
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 21; c.Parent = hudLbl end
	task.spawn(function()
		while hudGui.Parent do
			local on = false
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and isl and isl.Parent then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and size.Magnitude > 1 then
					local d = hrp.Position - cf.Position
					on = math.abs(d.X) <= size.X/2 + 40 and math.abs(d.Z) <= size.Z/2 + 40 and math.abs(d.Y) <= size.Y/2 + 120
				end
			end
			hudGui.Enabled = on and st.started and not st.done and hudLbl.Text ~= ""
			task.wait(0.5)
		end
	end)
end
local function objective(text)
	if hudLbl then hudLbl.Text = (text and text ~= "") and ("\u{1F9B4} " .. text) or "" end
end

-- ===== boot =====
task.spawn(function()
	local isl = Workspace:FindFirstChild("island3") or Workspace:WaitForChild("island3", 120)
	if not isl then warn("[LivingFossil] island3 not found -- quest not built"); return end
	local function streamedIn()
		local ok, _, size = pcall(function() return isl:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end
	if not streamedIn() then
		print("[LivingFossil] island3 has not streamed in yet -- waiting until the player reaches it...")
		while not streamedIn() do task.wait(1) end
	end
	local bcf, bsize = isl:GetBoundingBox()
	buildHUD(isl)

	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { isl }
	local function groundAt(x, z, fallbackY, fromY)
		local origin = Vector3.new(x, fromY or (bcf.Position.Y + bsize.Y/2 + 60), z)
		for _ = 1, 6 do
			local hit = Workspace:Raycast(origin, Vector3.new(0, -(bsize.Y + 150), 0), rp)
			if not hit then return fallbackY end
			if hit.Instance.CanCollide and hit.Instance.Transparency < 0.95 then return hit.Position.Y end
			origin = hit.Position - Vector3.new(0, 0.1, 0)
		end
		return fallbackY
	end
	local function playerOnIsland()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
		local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
		if not (ok and size.Magnitude > 1) then return false end
		local d = hrp.Position - cf.Position
		return math.abs(d.X) <= size.X/2 + 40 and math.abs(d.Z) <= size.Z/2 + 40 and math.abs(d.Y) <= size.Y/2 + 120
	end

	-- ===== the quest-giver: the DigMiner =====
	local npc = Workspace:FindFirstChild("DigMiner") or Workspace:WaitForChild("DigMiner", 30)
	local function npcPos()
		if npc and npc.Parent then
			local ok, cf = pcall(function() return npc:GetPivot() end)
			if ok then return cf.Position end
		end
		return Vector3.new(bcf.Position.X, groundAt(bcf.Position.X, bcf.Position.Z, bcf.Position.Y), bcf.Position.Z)
	end
	local function speak(text) floatText(npcPos() + Vector3.new(0, 6.5, 0), text, WARM) end
	if not npc then warn("[LivingFossil] DigMiner not found on island3 -- narrating from the island centre") end

	-- ===== signature spots: the island's 'Dig' markers, found ANYWHERE over island3 =====
	local spots = {}
	local seenMarkers = {}
	local function overIsland(p)
		local d = p - bcf.Position
		return math.abs(d.X) <= bsize.X/2 + 60 and math.abs(d.Z) <= bsize.Z/2 + 60
			and math.abs(d.Y) <= bsize.Y/2 + 200
	end
	local function scanForMarkers(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") and not seenMarkers[d] and d.Name:lower():match("^dig") then
				seenMarkers[d] = true
				if overIsland(d.Position) then
					local top = d.Position + Vector3.new(0, d.Size.Y/2, 0)
					local y = groundAt(top.X, top.Z, top.Y, top.Y + 12)
					table.insert(spots, { pos = Vector3.new(top.X, y, top.Z) })
					d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
					print(("[LivingFossil] signature %d: '%s' at (%.0f, %.0f, %.0f)"):format(#spots, d.Name, top.X, top.Y, top.Z))
				end
			end
		end
	end
	scanForMarkers(isl); scanForMarkers(Workspace)
	do -- StreamingEnabled can deliver loose markers late; rescan briefly
		local t0 = os.clock()
		while #spots < 3 and os.clock() - t0 < 20 do
			task.wait(2); scanForMarkers(isl); scanForMarkers(Workspace)
		end
	end
	if #spots < 3 then
		warn(("[LivingFossil] only %d 'Dig' marker(s) over island3 -> adding probed fallback spots. Place ~5 parts named Dig1..Dig5 around the dig site."):format(#spots))
		for i = 1, 8 do
			if #spots >= 5 then break end
			local ang = math.random() * 2 * math.pi
			local r = (0.2 + math.random() * 0.15) * math.min(bsize.X, bsize.Z)
			local x, z = bcf.Position.X + math.cos(ang) * r, bcf.Position.Z + math.sin(ang) * r
			local y = groundAt(x, z, nil)
			if y then table.insert(spots, { pos = Vector3.new(x, y, z) }) end
		end
	end
	print(("[LivingFossil] %d fossil signatures on island3"):format(#spots))
	if #spots < 2 then warn("[LivingFossil] not enough signatures -- quest disabled; /done still grants.") end
	local liveSpot = spots[math.random(math.max(1, #spots))]   -- the one with the heartbeat

	-- ===== props =====
	local props = Instance.new("Model"); props.Name = "LivingFossilQuest"; props.Parent = Workspace
	local function part(name, sz, col, cf, mat, shape, parent)
		local p = Instance.new("Part"); p.Name = name
		if shape then p.Shape = shape end
		p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.Slate
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
		p.CFrame=cf; p.Parent=parent or props; return p
	end
	local function dirtBurst(pos, big)
		local snd = part("BurstSnd", Vector3.new(0.4, 0.4, 0.4), DIRT, CFrame.new(pos))
		snd.Transparency = 1
		sfx(snd, SOUNDS.rustle, 0.8)
		task.delay(5, function() snd:Destroy() end)
		for k = 1, big and 12 or 8 do
			local ang = k * math.pi * 2 / (big and 12 or 8)
			local d = part("Dirt", Vector3.new(0.8, 0.5, 0.6), (k % 2 == 0) and DIRT or MUD, CFrame.new(pos + Vector3.new(0, 0.8, 0)), Enum.Material.Ground)
			TS:Create(d, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * (big and 5 or 3.2), 2.4 + math.random(), math.sin(ang) * (big and 5 or 3.2))) * CFrame.Angles(math.random(), math.random(), 0),
				Transparency = 1,
			}):Play()
			task.delay(0.9, function() d:Destroy() end)
		end
	end

	-- per-spot: dirt mound (always) + GHOST SKELETON (fades in when the lens is
	-- taken): translucent amber bones half-sunk in the ground -- the lens-vision.
	for i, spot in ipairs(spots) do
		local p = spot.pos
		spot.anchor = part("Sig" .. i, Vector3.new(0.5, 3.4, 4.4), MUD, CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Ground, Enum.PartType.Cylinder)
		part("Mound" .. i, Vector3.new(3.2, 1.1, 2.6), DIRT, CFrame.new(p + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, i * 1.1, 0), Enum.Material.Ground, Enum.PartType.Ball)
		-- the ghost bones sit UNDER the ground, so plain parts would be invisible --
		-- a Highlight in AlwaysOnTop mode is what draws them through the terrain.
		-- That IS the lens-vision.
		spot.ghostModel = Instance.new("Model"); spot.ghostModel.Name = "GhostFossil"; spot.ghostModel.Parent = props
		local yaw = i * 2.3
		for k = 1, 3 do   -- three rib arcs
			part("Ghost", Vector3.new(2.6 + k * 0.3, 0.35, 0.35), BONE, CFrame.new(p + Vector3.new(0, -0.4, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new((k - 2) * 1.1, 0, 0) * CFrame.Angles(math.rad(90), 0, math.rad(90)), Enum.Material.Neon, Enum.PartType.Cylinder, spot.ghostModel)
		end
		part("Ghost", Vector3.new(1.3, 1.1, 1.1), BONE, CFrame.new(p + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(2.2, 0, 0), Enum.Material.Neon, Enum.PartType.Ball, spot.ghostModel)
		spot.ghostHL = Instance.new("Highlight")
		spot.ghostHL.FillColor = AMBER; spot.ghostHL.FillTransparency = 0.6
		spot.ghostHL.OutlineColor = BONE; spot.ghostHL.OutlineTransparency = 0.2
		spot.ghostHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		spot.ghostHL.Enabled = false; spot.ghostHL.Parent = spot.ghostModel
	end
	local function showGhosts()
		for _, spot in ipairs(spots) do
			if not spot.dug and spot.ghostHL then spot.ghostHL.Enabled = true end
		end
	end
	local function hideGhost(spot)
		if spot.ghostModel then spot.ghostModel:Destroy(); spot.ghostModel = nil; spot.ghostHL = nil end
	end

	-- ===== the amber lens tint (this client only) =====
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "AmberLens"; cc.Enabled = false
	cc.TintColor = Color3.fromRGB(255, 228, 185); cc.Saturation = -0.08; cc.Parent = Lighting
	-- the tint is lens-vision for THIS dig site: it switches off whenever the player
	-- leaves the island mid-quest (and back on when they return with the lens)
	task.spawn(function()
		while cc.Parent and not st.done do
			if st.lensTaken then cc.Enabled = playerOnIsland() end
			task.wait(1)
		end
		cc.Enabled = false
	end)
	local function pulseScreen()
		cc.Brightness = 0.07
		TS:Create(cc, TweenInfo.new(0.28), { Brightness = 0 }):Play()
	end

	-- ===== the heartbeat / clack audio (nearest undug signature only) =====
	task.spawn(function()
		while props.Parent and not st.done and not st.found do
			if st.lensTaken then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local best, bestD = nil, HEAR_RANGE
				if hrp then
					for _, spot in ipairs(spots) do
						if not spot.dug then
							local d = (hrp.Position - spot.pos).Magnitude
							if d < bestD then best, bestD = spot, d end
						end
					end
				end
				if best then
					local closeness = 1 - bestD / HEAR_RANGE          -- 0 far .. 1 on top
					local interval = 1.5 - closeness * 1.1            -- 1.5s .. 0.4s
					if best == liveSpot then
						-- THUMP-thump: two low pings + a screen pulse, the living tell
						chime(best.anchor, 0.42, 0.35 + closeness * 0.6)
						pulseScreen()
						task.delay(0.14, function() if not st.done then chime(best.anchor, 0.36, 0.3 + closeness * 0.55) end end)
					else
						-- dead stone CLACK
						sfx(best.anchor, SOUNDS.woodHit, 0.12 + closeness * 0.25, 1.6)
					end
					task.wait(interval)
				else
					task.wait(0.3)
				end
			else
				task.wait(0.5)
			end
		end
	end)

	-- ===== junk gags for wrong digs =====
	local JUNK = {
		{ text = "An old boot?! Who buries a BOOT?", build = function(pos)
			local m = Instance.new("Model"); m.Name = "Junk"; m.Parent = props
			part("Boot", Vector3.new(1.2, 1.4, 2.2), Color3.fromRGB(90, 70, 50), CFrame.new(pos + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 1, 0.2), Enum.Material.Fabric, nil, m)
			return m end },
		{ text = "A rubber duck. In the CRETACEOUS?!", build = function(pos)
			local m = Instance.new("Model"); m.Name = "Junk"; m.Parent = props
			part("Duck", Vector3.new(1.6, 1.3, 1.6), Color3.fromRGB(255, 220, 60), CFrame.new(pos + Vector3.new(0, 0.8, 0)), Enum.Material.SmoothPlastic, Enum.PartType.Ball, m)
			part("Bill", Vector3.new(0.7, 0.3, 0.5), Color3.fromRGB(255, 150, 60), CFrame.new(pos + Vector3.new(0.9, 0.9, 0)), Enum.Material.SmoothPlastic, nil, m)
			return m end },
		{ text = "That's... just a rock.", build = function(pos)
			local m = Instance.new("Model"); m.Name = "Junk"; m.Parent = props
			part("Rock", Vector3.new(1.8, 1.4, 1.6), Color3.fromRGB(130, 130, 125), CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0.4, 1, 0.2), Enum.Material.Slate, Enum.PartType.Ball, m)
			return m end },
	}
	local junkIndex = 0

	-- ===== the reveal / wake-up ending =====
	local sleeper = nil
	local function grantPet(atCF)
		if _G.SpawnBrachiosaurusFollower then pcall(function() _G.SpawnBrachiosaurusFollower(atCF) end) end
		if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("BrachiosaurusPet", { petId="BrachiosaurusPet", displayName="Brachiosaurus", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
		do local rh = RS:FindFirstChild("BrachiosaurusHatched"); if rh then pcall(function() rh:FireServer() end) end end
	end
	local function revealSleeper(spot)
		st.found = true
		hideGhost(spot); spot.dug = true
		dirtBurst(spot.pos, true)
		sfx(spot.anchor, SOUNDS.woodHit, 0.9)
		sfx(spot.anchor, SOUNDS.success, 0.9)
		do local ev = RS:FindFirstChild("PetDigEvent"); if ev then pcall(function() ev:FireServer() end) end end   -- server unlock, same as the old dig
		-- the sleeping baby: the real pet model, curled up and snoring
		local tpl = RS:FindFirstChild("BrachiosaurusTemplate") or RS:WaitForChild("BrachiosaurusTemplate", 8)
		local lift = 1.2
		if tpl then
			sleeper = tpl:Clone(); sleeper.Name = "SleepingBrachio"
			for _, d in ipairs(sleeper:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanQuery=false; d.CanTouch=false end
			end
			pcall(function() sleeper:ScaleTo(0.7) end)
			local okB, _, tsz = pcall(function() return sleeper:GetBoundingBox() end)
			lift = ((okB and tsz) and tsz.Y/2 or 1.2) + 0.05
			local hl = Instance.new("Highlight")
			hl.FillColor = GOLDEN; hl.FillTransparency = 0.88; hl.OutlineColor = GOLDEN; hl.OutlineTransparency = 0.1
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = sleeper
			sleeper:PivotTo(CFrame.new(spot.pos + Vector3.new(0, lift, 0)) * FACE_FIX)
			sleeper.Parent = Workspace
		end
		speak("By my beard... that fossil is ALIVE! Wake it GENTLY now!")
		objective("You found the LIVING fossil! Wake it up... GENTLY.")
		-- snore loop until woken
		task.spawn(function()
			local t = 0
			while sleeper and sleeper.Parent and not st.done do
				t += 1
				if t % 3 == 1 then chime(spot.anchor, 0.3, 0.4) end
				floatText(spot.pos + Vector3.new(0, 2.6, 0), "Zzz...", Color3.fromRGB(190, 210, 255), 1.5)
				-- gentle breathing bob
				for i = 1, 25 do
					if not (sleeper and sleeper.Parent) or st.done then break end
					pcall(function() sleeper:PivotTo(CFrame.new(spot.pos + Vector3.new(0, lift + math.sin(i / 25 * math.pi) * 0.12, 0)) * FACE_FIX) end)
					task.wait(0.1)
				end
			end
		end)
		local bar = sleeper and sleeper:FindFirstChildWhichIsA("BasePart", true) or spot.anchor
		local wake = Instance.new("ProximityPrompt")
		wake.ObjectText = "Sleeping Baby"; wake.ActionText = "Wake Up Gently"
		wake.KeyboardKeyCode = Enum.KeyCode.E; wake.HoldDuration = 1
		wake.MaxActivationDistance = 12; wake.RequiresLineOfSight = false; wake.Parent = bar
		wake.Triggered:Once(function()
			st.done = true
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local at = hrp and (hrp.CFrame * CFrame.new(0, 0, -5)) or CFrame.new(spot.pos + Vector3.new(0, 1, 0))
			-- wake-up cutscene: side close-up -> yawn -> hello -> hatch-burst -> pan
			local cam = Workspace.CurrentCamera
			local usedCam = cam and hrp and sleeper and true or false
			if usedCam then
				cam.CameraType = Enum.CameraType.Scriptable
				task.delay(11, function() pcall(function() cam.CameraType = Enum.CameraType.Custom end) end)
				local eye = spot.pos + Vector3.new(0, 1.4, 0)
				local toPlayer = Vector3.new(hrp.Position.X - eye.X, 0, hrp.Position.Z - eye.Z)
				if toPlayer.Magnitude < 0.05 then toPlayer = Vector3.new(0, 0, -1) end
				local side = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(55)) * toPlayer.Unit
				TS:Create(cam, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.lookAt(eye + side * 7 + Vector3.new(0, 2, 0), eye) }):Play()
			end
			sfx(bar, SOUNDS.love, 0.9)
			-- the yawn: it stretches up slowly, then settles
			if sleeper then
				for i = 1, 30 do
					local a = i / 30
					pcall(function() sleeper:PivotTo(CFrame.new(spot.pos + Vector3.new(0, lift + math.sin(a * math.pi) * 0.9, 0)) * CFrame.Angles(0, 0, math.sin(a * math.pi) * 0.18) * FACE_FIX) end)
					task.wait(0.045)
				end
			end
			floatText(spot.pos + Vector3.new(0, 1.8, 0), "*yaaawn*... oh! Hi!", GOLDEN, 0.6)
			task.wait(1.3)
			-- happy hop
			if sleeper then
				for i = 1, 24 do
					local a = i / 24
					pcall(function() sleeper:PivotTo(CFrame.new(spot.pos + Vector3.new(0, lift + math.abs(math.sin(a * 3 * math.pi)) * 0.6, 0)) * CFrame.Angles(0, a * 2 * math.pi, 0) * FACE_FIX) end)
					task.wait(0.04)
				end
			end
			HatchBurst.play(spot.pos + Vector3.new(0, 1, 0), AMBER)
			if sleeper then sleeper:Destroy(); sleeper = nil end
			grantPet(at)
			objective("")
			cc.Enabled = false
			if usedCam and hrp then
				TS:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ CFrame = CFrame.lookAt((hrp.CFrame * CFrame.new(2.5, 3, -9)).Position, hrp.Position + Vector3.new(0, 1, 0)) }):Play()
				task.wait(2.2)
				pcall(function() cam.CameraType = Enum.CameraType.Custom end)
			end
			floatText(at.Position + Vector3.new(0, 4, 0), "The sleepy giant is YOUR Brachiosaurus now! \u{1F995}", GOLDEN)
			print("[LivingFossil] woken -> Brachiosaurus granted (same path the old dig used)")
		end)
	end

	-- ===== excavation prompts =====
	local function permitsText()
		return ("Find the fossil with a HEARTBEAT! Permits: %d"):format(st.permits)
	end
	for _, spot in ipairs(spots) do
		local ep = Instance.new("ProximityPrompt")
		ep.ObjectText = "Fossil Signature"; ep.ActionText = "Excavate"
		ep.KeyboardKeyCode = Enum.KeyCode.E; ep.HoldDuration = 0.4
		ep.MaxActivationDistance = 10; ep.RequiresLineOfSight = false
		ep.Enabled = false; ep.Parent = spot.anchor
		spot.prompt = ep
		ep.Triggered:Connect(function()
			if st.done or st.found or not st.lensTaken or st.permits <= 0 or spot.dug then return end
			spot.dug = true; spot.prompt.Enabled = false
			st.permits -= 1
			if spot == liveSpot then
				revealSleeper(spot)
				for _, s2 in ipairs(spots) do if s2.prompt then s2.prompt.Enabled = false end end
				return
			end
			-- WRONG: comedy junk rises out of the hole
			hideGhost(spot)
			dirtBurst(spot.pos, false)
			sfx(spot.anchor, SOUNDS.woodHit, 0.8)
			junkIndex = junkIndex % #JUNK + 1
			local gag = JUNK[junkIndex]
			local m = gag.build(spot.pos)
			task.delay(0.35, function() sfx(spot.anchor, SOUNDS.sadGag, 0.8) end)
			floatText(spot.pos + Vector3.new(0, 3.5, 0), gag.text, WARM)
			task.delay(3, function() if m then for _, p2 in ipairs(m:GetDescendants()) do if p2:IsA("BasePart") then TS:Create(p2, TweenInfo.new(0.6), { Transparency = 1 }):Play() end end task.delay(0.7, function() m:Destroy() end) end end)
			if st.permits > 0 then
				objective(permitsText())
			else
				objective("Out of permits! The Digger is stamping more...")
				task.delay(2.5, function()
					if st.done or st.found then return end
					st.permits = PERMITS_PER_BATCH
					speak("*sigh* Three MORE permits. LISTEN for the thump-thump!")
					objective(permitsText())
					for _, s2 in ipairs(spots) do
						if s2.prompt and not s2.dug then s2.prompt.Enabled = true end
					end
				end)
				for _, s2 in ipairs(spots) do if s2.prompt then s2.prompt.Enabled = false end end
			end
		end)
	end
	local function enablePrompts()
		for _, spot in ipairs(spots) do
			if spot.prompt and not spot.dug then spot.prompt.Enabled = st.lensTaken and st.permits > 0 end
		end
	end

	-- ===== the amber lens offer at the NPC =====
	local lensOffer = nil
	local function offerLens()
		if lensOffer then lensOffer:Destroy(); lensOffer = nil end
		local look = Vector3.new(0, 0, -1)
		pcall(function()
			local lv = npc:GetPivot().LookVector
			local f = Vector3.new(lv.X, 0, lv.Z)
			if f.Magnitude > 0.05 then look = f.Unit end
		end)
		local lensPos = npcPos() + look * 2.2 + Vector3.new(0, 1.6, 0)
		local m = Instance.new("Model"); m.Name = "AmberLensOffer"; m.Parent = props
		local disc = part("Lens", Vector3.new(0.3, 1.6, 1.6), AMBER, CFrame.new(lensPos) * CFrame.Angles(0, 0, math.rad(20)), Enum.Material.Neon, Enum.PartType.Cylinder, m)
		disc.Transparency = 0.25
		part("Handle", Vector3.new(0.25, 1.2, 0.25), DIRT, CFrame.new(lensPos + Vector3.new(0, -1.1, 0)), Enum.Material.Wood, nil, m)
		local gl = Instance.new("PointLight"); gl.Color = AMBER; gl.Range = 8; gl.Brightness = 1.2; gl.Parent = disc
		sfx(disc, SOUNDS.shimmer, 0.6)
		local op = Instance.new("ProximityPrompt")
		op.ObjectText = "The Digger"; op.ActionText = "Take Amber Lens"
		op.KeyboardKeyCode = Enum.KeyCode.E; op.HoldDuration = 0.3
		op.MaxActivationDistance = 12; op.RequiresLineOfSight = false; op.Parent = disc
		lensOffer = m
		op.Triggered:Once(function()
			if st.done then return end
			op.Enabled = false
			local cam = Workspace.CurrentCamera
			local hrp2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local lensPosNow = lensPos
			-- face him to the player + move the lens to his new front (FernThief's lesson)
			if hrp2 then
				pcall(function()
					local np = npc:GetPivot().Position
					npc:PivotTo(CFrame.lookAt(np, Vector3.new(hrp2.Position.X, np.Y, hrp2.Position.Z)))
					local f = Vector3.new(hrp2.Position.X - np.X, 0, hrp2.Position.Z - np.Z)
					if f.Magnitude > 0.05 then look = f.Unit end
				end)
				local newPos = npcPos() + look * 2.2 + Vector3.new(0, 1.6, 0)
				pcall(function() m:PivotTo(m:GetPivot() + (newPos - lensPos)) end)
				lensPosNow = newPos
			end
			if cam and hrp2 then
				cam.CameraType = Enum.CameraType.Scriptable
				task.delay(7, function() pcall(function() cam.CameraType = Enum.CameraType.Custom end) end)
				local dir = Vector3.new(lensPosNow.X - hrp2.Position.X, 0, lensPosNow.Z - hrp2.Position.Z)
				if dir.Magnitude < 0.05 then dir = look else dir = dir.Unit end
				local right = Vector3.new(-dir.Z, 0, dir.X)
				TS:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.lookAt(hrp2.Position - dir * 1.5 + right * 2.0 + Vector3.new(0, 2.2, 0), lensPosNow) }):Play()
			end
			sfx(disc, SOUNDS.shimmer, 0.9)
			speak("This AMBER LENS shows what sleeps beneath the dirt...")
			task.wait(2.2)
			if not st.done then speak("ONE of those fossils has a HEARTBEAT. Find it -- 3 permits!") end
			for _, p2 in ipairs(m:GetDescendants()) do
				if p2:IsA("BasePart") then
					TS:Create(p2, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ CFrame = p2.CFrame * CFrame.new(0, 2.5, 0), Transparency = 1 }):Play()
				end
			end
			task.wait(0.9)
			if cam then pcall(function() cam.CameraType = Enum.CameraType.Custom end) end
			if lensOffer then lensOffer:Destroy(); lensOffer = nil end
			if st.done then return end
			st.lensTaken = true
			st.permits = PERMITS_PER_BATCH
			cc.Enabled = true      -- the world goes amber...
			showGhosts()           -- ...and the buried skeletons fade in
			enablePrompts()
			objective(permitsText())
		end)
	end

	-- ===== /done skip =====
	DoneCommand.bind(isl, "LivingFossil", function()
		if st.done then return end
		st.done = true
		cc.Enabled = false
		if lensOffer then lensOffer:Destroy(); lensOffer = nil end
		if sleeper then sleeper:Destroy(); sleeper = nil end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(0, 0, -5)) or CFrame.new(npcPos() + Vector3.new(0, 2, 0))
		HatchBurst.play(at.Position + Vector3.new(0, 1, 0), AMBER)
		grantPet(at)
		objective("")
		floatText(at.Position + Vector3.new(0, 4, 0), "The sleepy giant is YOUR Brachiosaurus now! \u{1F995}", GOLDEN)
	end)

	-- ===== main flow =====
	print("[LivingFossil] island3 'Fossil Frontier' quest ready: find the fossil with a heartbeat. /done to skip.")
	if player:GetAttribute("DigQuestAccepted") ~= true then
		while not st.done and player:GetAttribute("DigQuestAccepted") ~= true do task.wait(0.5) end
	end
	if st.done or #spots < 2 then return end
	while not st.done and not playerOnIsland() do task.wait(1) end
	if st.done then return end
	st.started = true
	offerLens()
	speak("Over here! You'll need my Amber Lens for this...")
	objective("Take the AMBER LENS from the Digger!")
end)
