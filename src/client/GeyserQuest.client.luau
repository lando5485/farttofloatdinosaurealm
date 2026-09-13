--======================================================================
-- GeyserQuest.client.luau  (LocalScript)  -- Island 11 "Volcanic Vista" quest
-- island11 is the ENDING ISLAND (top of the tower) -- this is the FINALE quest.
--
-- IMPORTANT: the Geyser1..Geyser6 parts and the EggSpot8 marker must live inside
-- the island11 MODEL in Workspace. findNamed() searches all of Workspace so it
-- will still FIND them elsewhere, but CONFIG.islandName gates the on-screen HUD
-- ("only show while the player is ON this island") -- so if the geysers are still
-- parented under island8, the HUD shows on island11 while the geysers are on
-- island8 and the quest is unplayable.
--======================================================================
-- The volcano is about to erupt and wipe out the dinos! Six geysers (the user's
-- parts Geyser1..Geyser6) blast lava/steam. The player must PLUG every geyser:
--   1. Walk to a geyser -> [E] Plug Geyser -> a "PLUG IT!" tap mini-game.
--   2. Shove a boulder in against the vent pressure -> the geyser caps off,
--      plume stops. A rising ceiling holds each geyser to a flat 15s (PickupFloor),
--      so the six-geyser finale is 90s of work rather than ten seconds of mashing.
--   3. Plug all 6 -> the volcano calms -> a T-Rex egg appears (EggSpot8) -> hatch.
-- A red danger vignette fades as the pressure drops with each plug.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")

-- VERBOSE: per-item boot spam (one line per part/island/pet/serving). OFF by default --
-- it buried the progression telemetry in hundreds of lines. Flip to true to debug THIS
-- system specifically; every file that had a noisy loop uses the same flag name.
local VERBOSE = false

local player     = Players.LocalPlayer
local HatchBurst   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst"))
local ChevronTrail = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("ChevronTrail")) -- island1's ground chevron guide
local DoneCommand  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("DoneCommand"))  -- "/done" -> skip to the reward egg
local PickupFloor  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PickupFloor")) -- the 15s-per-collectible floor

local CONFIG = {
	islandName    = "island11",   -- "Volcanic Vista" -- the ENDING island
	count         = 6,            -- Geyser1..Geyser6
	shovesToPlug  = 10,           -- bar fraction per shove = 1/this (the leak below means ~13 real shoves)
	plugIdle      = 4.9,          -- seconds with NO shove before the boulder blows back out
	petId         = "TyrannosaurusPet",
	petName       = "T-Rex",
	spawnFollower = "SpawnTyrannosaurusFollower",
	hatchEvent    = "TyrannosaurusHatched",
}

-- ===== VENT HISS =====
-- The idle steam loop on each unplugged vent. Set to nil to turn it off entirely; the build
-- and the plug-fade both check for that, so nothing else needs changing.
--
-- KEEP IT QUIET. There are SIX of these playing at once on a live island and they overlap
-- wherever their rolloffs meet, so the level that sounds right standing at one vent is
-- roughly three times too loud standing in the middle of the field. VENT_HISS_VOLUME is
-- per-vent, not what you actually hear.
--
-- THE CLIP MUST LOOP SEAMLESSLY -- constant, no attack, no tail. The previous one did not:
-- it hissed, stopped dead and restarted, six copies out of phase, which is far more
-- irritating than silence. `Looped` just replays from frame zero; it cannot fix a clip that
-- has a shape of its own.
local VENT_HISS_ID     = "rbxassetid://9112780743"
local VENT_HISS_VOLUME = 0.35

-- st.geysers / st.island are filled in at BOOT; the FINALE (see runFinale) needs to
-- reach back into every built geyser to blow its plug off and crank the lava up.
local st = { plugged = 0, busy = false, done = false, hatching = false, owns = false, geysers = {}, island = nil, finale = false }
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
	-- only show the HUD while the player is ON island11 (CONFIG.islandName)
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
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-56,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255,225,180); title.Text = "PLUG THE GEYSER!"; title.Parent = panel
	local plug = Instance.new("TextButton"); plug.Size = UDim2.fromOffset(160,108); plug.Position = UDim2.new(0.5,0,0,56); plug.AnchorPoint = Vector2.new(0.5,0)
	plug.BackgroundColor3 = Color3.fromRGB(150,90,60); plug.Font = Enum.Font.FredokaOne; plug.TextScaled = true; plug.TextColor3 = Color3.new(1,1,1); plug.Text = "\xF0\x9F\xAA\xA8  PLUG!"; plug.Parent = panel
	Instance.new("UICorner", plug).CornerRadius = UDim.new(0,14); Instance.new("UIStroke", plug).Color = Color3.fromRGB(60,40,30)
	local barBg = Instance.new("Frame"); barBg.Size = UDim2.new(1,-40,0,18); barBg.Position = UDim2.new(0,20,1,-26); barBg.AnchorPoint = Vector2.new(0,1)
	barBg.BackgroundColor3 = Color3.fromRGB(40,28,24); barBg.Parent = panel; Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,9)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(0,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(255,150,50); bar.BorderSizePixel = 0; bar.Parent = barBg; Instance.new("UICorner", bar).CornerRadius = UDim.new(0,9)
	-- RISING CEILING (PickupFloor pattern 1) over a slow pressure leak.
	--
	-- This was six taps against a six-second clock: a mashing player capped a geyser in
	-- well under two seconds, so the volcano finale -- six geysers, the last quest in the
	-- game -- was about ten seconds of work. A ceiling now climbs 0 -> 1 over exactly 15s
	-- and the bar is clamped to it on every write, so no tap rate finishes early.
	--
	-- The leak is what makes it a fight rather than a wait: the vent pushes the boulder
	-- back out at PRESSURE_LEAK/sec, so standing still loses ground. Keeping pace with
	-- the ceiling costs (1/15 + 0.02) / (1/16) = ~1.4 shoves/sec, comfortably inside the
	-- ~2.7/sec mobile ceiling, and works out to ~21 shoves across the 15s.
	--
	-- DONE, not 1.0. The bar is CLAMPED to the ceiling, so a shove can put AT MOST exactly
	-- the ceiling's value into it -- and the leak then takes a sliver back out on the very
	-- next frame, before the completion test ever sees it. Testing for a literal 1.0 was a
	-- test nothing could pass: the boulder sat visibly seated and the vent never plugged,
	-- so island11's finale could not be finished at all. Threshold is one frame of leak
	-- (0.02/60 = 0.0003) clear of full, with room to spare.
	local PRESSURE_LEAK = 0.012
	local DONE = PickupFloor.DONE
	local fill, shoves, done = 0, 0, false
	local ceiling = PickupFloor.newCeiling(0)
	local lastShove = os.clock()
	local function finish(win) if done then return end; done = true; pcall(function() g:Destroy() end); if onDone then onDone(win) end end
	-- X closes it (and the geyser stays unplugged); the Modal backdrop never does
	PickupFloor.addCloseButton(panel, function() finish(false) end)
	plug.Activated:Connect(function()
		if done then return end
		lastShove = os.clock(); shoves += 1
		fill = ceiling:clamp(math.min(1, fill + 1 / CONFIG.shovesToPlug)) -- clamp on the INPUT path too
		plug.Text = (shoves % 2 == 0) and "\xF0\x9F\xAA\xA8  PLUG!" or "\xF0\x9F\x92\xA5  SHOVE!"
		-- the seating shove pays out HERE, not a frame later in the loop, which would
		-- charge it a frame of leak off a bar already sitting at the ceiling
		if fill >= DONE then bar.Size = UDim2.new(1, 0, 1, 0); finish(true) end
	end)
	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.1); last = now
			ceiling:step(dt)
			fill = ceiling:clamp(math.max(0, fill - PRESSURE_LEAK * dt))
			bar.Size = UDim2.new(fill, 0, 1, 0)
			if fill >= DONE then bar.Size = UDim2.new(1,0,1,0); finish(true); break end
			if now - lastShove > CONFIG.plugIdle then finish(false); break end -- stopped shoving -> it blows back out
			task.wait()
		end
	end)
end

-- ===== build an erupting geyser AT the user's marker (the marker is only a position; WE build the geyser) =====
local function buildGeyser(inst)
	-- marker -> base position, then GHOST the marker (it shouldn't be visible -- it's just a spot)
	local mpos = (inst:IsA("BasePart") and inst.Position) or inst:GetBoundingBox().Position
	pcall(function()
		if inst:IsA("BasePart") then inst.Transparency = 1; inst.CanCollide = false; inst.CanQuery = false
		else for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false; d.CanQuery = false end end end
	end)
	-- Find the ground under the marker so the built geyser sits flush on the island.
	--
	-- THE MARKER IS THE SOURCE OF TRUTH. The raycast is only a nudge to settle the
	-- chimney onto the exact surface height. If the ray result disagrees with the
	-- marker by more than SNAP_TOLERANCE, we IGNORE it and build at the marker.
	--
	-- Why: if the island mesh isn't queryable at that spot, the ray punches straight
	-- THROUGH the island and hits whatever is underneath -- burying every geyser ~190
	-- studs below the walkable surface (a few chimneys poke out of uneven ground, the
	-- rest vanish -> "some built, some not"). Clamping to the marker makes that
	-- impossible: worst case the geyser sits exactly where you put the block.
	local SNAP_TOLERANCE = 15 -- studs the ray may move the geyser before we distrust it
	local grp = RaycastParams.new(); grp.FilterType = Enum.RaycastFilterType.Exclude
	-- exclude the player, this marker, and every geyser vent already built (so a ray
	-- can't land on a neighbouring chimney)
	local exclude = { player.Character, inst }
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m.Name == "GeyserVent" then exclude[#exclude + 1] = m end
	end
	grp.FilterDescendantsInstances = exclude

	local ghit = Workspace:Raycast(mpos + Vector3.new(0, 12, 0), Vector3.new(0, -250, 0), grp)
	local groundY = mpos.Y
	if ghit then
		if math.abs(ghit.Position.Y - mpos.Y) <= SNAP_TOLERANCE then
			groundY = ghit.Position.Y -- sane hit -> snap flush to the surface
		else
			warn(("[Geyser] %s: ground ray landed %.0f studs from the marker (fell through the island?) -> building AT the marker instead")
				:format(inst.Name, ghit.Position.Y - mpos.Y))
		end
	end
	local base = Vector3.new(mpos.X, groundY, mpos.Z)

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
	-- basePos = the GROUND the chimney stands on. ventPos is 6.4 studs higher (the top of
	-- the vent). The FINALE's lava pools must use basePos -- pooling them at ventPos left
	-- the lava discs hovering in mid-air above the terrain.
	-- STEAM HISS -- one looping emitter PER VENT, parented to the plume part so it is
	-- properly positional. Six copies is fine here where six mosquito buzzes were not:
	-- geysers are static and metres apart, so the rolloff separates them instead of
	-- letting them drift together and stack. That separation is the point -- with the
	-- vents audible individually you can hear which ones are still live from across the
	-- island, which is exactly the information this quest asks you to track.
	local hiss = nil
	if VENT_HISS_ID then
		hiss = Instance.new("Sound")
		hiss.Name = "GeyserHiss"
		hiss.SoundId = VENT_HISS_ID
		hiss.Looped = true
		hiss.Volume = VENT_HISS_VOLUME
		hiss.RollOffMode = Enum.RollOffMode.Linear
		hiss.RollOffMinDistance = 14   -- standing at the vent
		hiss.RollOffMaxDistance = 130  -- gone by the far side of the island
		hiss.Parent = fx
		pcall(function() hiss:Play() end)
	end

	local g = { inst=inst, model=model, anchor=mound, fx=fx, light=light, lava=lava, steam=steam, hiss=hiss, ventPos=ventPos, basePos=base, plugged=false }
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

-- `silent` skips the boulder slam only. Used by the bulk-plug in onAllPlugged, where six
-- vents are capped in the same frame and six copies of the same slam would stack into one
-- loud mush rather than reading as six impacts.
local function plugGeyser(g, silent)
	if g.plugged then return end
	g.plugged = true
	g.lava.Rate = 0; g.steam.Rate = 3 -- a little lingering steam
	g.light.Brightness = 0.5; g.light.Color = Color3.fromRGB(120,120,120)
	-- a boulder slams down to cap the vent
	local cap = Instance.new("Part"); cap.Shape=Enum.PartType.Ball; cap.Size=Vector3.new(3.2,2.6,3.2); cap.Color=Color3.fromRGB(78,70,66); cap.Material=Enum.Material.Slate
	cap.Anchored=true; cap.CanCollide=false; cap.CanQuery=false; cap.CastShadow=false; cap.CFrame=CFrame.new(g.ventPos + Vector3.new(0,8,0)); cap.Parent=Workspace
	TS:Create(cap, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(g.ventPos + Vector3.new(0,0.6,0)) }):Play()

	-- THE VENT GOES QUIET. Fade rather than cut: an instant Stop on a loop clicks, and
	-- the plume itself lingers (steam.Rate drops to 3, not 0), so the audio should too.
	if g.hiss then
		local h = g.hiss; g.hiss = nil
		task.spawn(function()
			local v0, t0 = h.Volume, os.clock()
			while h.Parent and os.clock() - t0 < 0.5 do
				h.Volume = v0 * (1 - (os.clock() - t0) / 0.5)
				task.wait(0.05)
			end
			pcall(function() h:Stop(); h:Destroy() end)
		end)
	end

	-- THE BOULDER. Delayed to 0.30s so the impact lands with the cap actually hitting the
	-- vent -- the tween above takes 0.35s, and firing at t=0 put the slam a third of a
	-- second before the picture. Shift this if the clip has a long wind-up of its own.
	task.delay(0.30, function()
		if silent then return end
		local s = Instance.new("Sound")
		s.Name = "GeyserPlug"
		s.SoundId = "rbxassetid://139818366003696"
		s.Volume = 2.2
		s.RollOffMode = Enum.RollOffMode.Linear
		s.RollOffMinDistance = 20
		s.RollOffMaxDistance = 200
		s.Parent = cap
		pcall(function() s:Play() end)
		pcall(function() s.Ended:Once(function() pcall(function() s:Destroy() end) end) end)
	end)

	floatText(g.ventPos + Vector3.new(0,3,0), "Plugged!", Color3.fromRGB(200,200,200))
	g.cap = cap -- keep it: the FINALE blows this boulder off the vent
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
	-- SAME GUIDE AS ISLAND 1: the flat green chevron runway laid on the ground toward
	-- the egg (ChevronTrail -- the shared module island1's Mama Dino guide uses), NOT
	-- the old floating "^" billboard over the player's head.
	local trail = ChevronTrail.start(
		function() return eggPos end,      -- point at the reward egg
		function() return st.owns end      -- hatched -> tear the trail down for good
	)

	-- banner text follows the trail: swap to "press E" once you're on top of the egg
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if st.owns then -- hatched -> clean up the banner (the trail cleans itself up)
			pcall(function() g:Destroy() end)
			pcall(function() trail:Destroy() end)
			if conn then conn:Disconnect() end
			return
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then g.Enabled = false; return end
		local d = eggPos - hrp.Position
		local flat = Vector3.new(d.X, 0, d.Z)

		-- HIDE IT OFF-ISLAND. A ScreenGui doesn't disappear just because you left the
		-- island -- without this it stays stuck on screen while you fly the rest of the
		-- tower, still shouting about a volcano egg you're nowhere near. The islands are
		-- a vertical tower, so the altitude gap is the reliable "am I still here" test.
		g.Enabled = math.abs(d.Y) <= 250 and flat.Magnitude <= 500
		if not g.Enabled then return end

		if flat.Magnitude < 12 then
			banner.Text = "\xF0\x9F\xA5\x9A Press E to hatch the egg!"
		else
			banner.Text = "\xF0\x9F\x8C\x8B Volcano saved! Go hatch the egg!"
		end
	end)
end

-- FORWARD DECLARATION. The FINALE is written further down (it needs plugGeyser's
-- boulders and the built geyser list), but the egg's hatch prompt -- created below --
-- has to call it. Without this, the hatch closure would capture a nil global.
local runFinale

--======================================================================
-- THE NEST -- stands at the EggSpot marker from the moment the quest starts.
--======================================================================
-- Nothing used to be here until the volcano was calmed. The marker block was ghosted
-- at setup and a ring of 12 rocks was built as PART OF THE EGG MODEL -- so the reward
-- spot was a blank patch of ash you had no reason to look at, and the "nest" existed
-- only for the 1.4 seconds between hatching and the egg model being destroyed.
--
-- Now it is a real prop with a life of its own: empty while the geysers still blow,
-- holding the egg once they are all plugged, and still standing after the hatch. That
-- gives the finale somewhere to point at and makes the reward feel placed rather than
-- conjured out of thin air.
--
-- CHARRED, NOT WOODLAND. This is the summit of an erupting volcano, so the twigs are
-- burnt black with embers still glowing down in the weave. A tidy brown bird's nest
-- would read as dropped in from another game.
--
-- Built from parts rather than a mesh on purpose: no asset to upload or approve (this
-- realm has already lost one sound to audio privacy), and it sits on whatever ground
-- the marker happens to be on.
local function buildNest(pos)
	local nest = Instance.new("Model")
	-- MUST NOT contain "eggspot" or "geyser": setup sweeps Workspace for those names and
	-- ghosts everything it finds, which would turn the nest invisible the moment it built.
	nest.Name = "VolcanoNest"

	local base = CFrame.new(pos)
	local function piece(sz, col, cf, mat, shape)
		local p = Instance.new("Part")
		p.Size, p.Color, p.CFrame = sz, col, cf
		p.Material = mat or Enum.Material.Wood
		if shape then p.Shape = shape end
		-- CanCollide FALSE, like the geyser boulders: a solid nest at the top of the
		-- tower is something to get wedged in on the one island you cannot fall off of.
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = nest
		return p
	end

	-- ash mound + the bowl the egg sits in (squashed spheres = low-poly domes)
	piece(Vector3.new(6.0, 1.1, 6.0), Color3.fromRGB(52, 46, 44),
		base * CFrame.new(0, 0.15, 0), Enum.Material.Slate, Enum.PartType.Ball)
	piece(Vector3.new(4.5, 0.75, 4.5), Color3.fromRGB(36, 30, 28),
		base * CFrame.new(0, 0.60, 0), Enum.Material.Sand, Enum.PartType.Ball)

	-- TWO WOVEN RINGS, the upper one offset half a step so the twigs cross rather than
	-- stack. Each twig is laid TANGENT to the circle (the extra 90 deg yaw) and rolled a
	-- little, which is what stops it reading as a cog wheel.
	local TWIG = { Color3.fromRGB(46, 36, 32), Color3.fromRGB(68, 53, 44), Color3.fromRGB(34, 26, 24) }
	local function ring(n, radius, y, len, tilt, phase)
		for i = 1, n do
			local a = phase + (i - 1) * (2 * math.pi / n)
			piece(Vector3.new(0.36, 0.36, len), TWIG[(i % #TWIG) + 1],
				base * CFrame.Angles(0, a, 0) * CFrame.new(0, y, radius)
					* CFrame.Angles(0, math.rad(90), math.rad(tilt)))
		end
	end
	ring(14, 2.60, 0.85, 3.3,  14, 0)
	ring(12, 2.30, 1.35, 2.9, -20, math.pi / 12)

	-- embers down in the weave + one warm light, so the nest glows faintly at night and
	-- ties to the lava rather than sitting on the island as a cold grey prop
	for i = 1, 6 do
		local a = (i - 1) * (2 * math.pi / 6) + 0.4
		local e = piece(Vector3.new(0.34, 0.34, 0.34), Color3.fromRGB(255, 128, 44),
			base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.55, 2.15),
			Enum.Material.Neon, Enum.PartType.Ball)
		e.Transparency = 0.15
	end
	local lamp = Instance.new("PointLight")
	lamp.Color, lamp.Brightness, lamp.Range, lamp.Shadows = Color3.fromRGB(255, 140, 60), 0.7, 11, false
	lamp.Parent = nest:FindFirstChildWhichIsA("BasePart")

	-- loose stones around the outside -- breaks the perfect circle
	for i = 1, 5 do
		local a = (i - 1) * (2 * math.pi / 5) + 0.9
		local s = 0.85 + (i % 3) * 0.28
		piece(Vector3.new(s, s * 0.72, s), Color3.fromRGB(58, 50, 47),
			base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, 3.15),
			Enum.Material.Slate, Enum.PartType.Ball)
	end

	nest.Parent = Workspace
	return nest
end

-- ===== reward egg (volcanic) -> hatch the T-Rex =====
local function spawnRewardEgg(eggPos)
	local egg = Instance.new("Model"); egg.Name = "GeyserRewardEgg"
	local function part(name, sh, sz, col, cf, mat)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	-- The 12-rock ring that used to be built here is GONE -- buildNest() now stands at this
	-- exact spot from the start of the quest and outlives the egg. Rebuilding it here would
	-- double it up, and it would still vanish with the egg 1.4s after the hatch.
	local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
	local shell = Instance.new("Part"); shell.Name="Shell"; shell.Shape=Enum.PartType.Ball; shell.Size=Vector3.new(1,1,1); shell.Color=Color3.fromRGB(74,64,60); shell.Material=Enum.Material.SmoothPlastic
	shell.Anchored=true; shell.CanCollide=false; shell.CanQuery=false; shell.Parent=visual
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType=Enum.MeshType.Sphere; mesh.Scale=Vector3.new(3.0,4.0,3.0); mesh.Parent=shell
	visual.PrimaryPart = shell
	for j = 1, 9 do local a=(j-1)*(2*math.pi/9); local y=math.sin(a*1.8)*1.0; local r=1.3*math.sqrt(math.max(0,1-(y/2.1)^2))+0.05
		part("Ember", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(255,140,50), shell.CFrame * CFrame.new(math.sin(a)*r, y, math.cos(a)*r), Enum.Material.Neon) end
	-- SEAT HEIGHT. Was 1.9, which put the shell's underside level with the ground -- fine
	-- when it sat in a flat ring of rocks. The nest has a raised rim (~1.5) and a bowl
	-- floor, so 2.3 drops the egg's bottom third INSIDE the weave instead of through it.
	-- The idle bob is +/-0.28, so it never rises clear of the rim.
	local baseCF = CFrame.new(eggPos + Vector3.new(0, 2.3, 0)); visual:PivotTo(baseCF)
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
		HatchBurst.play(eggPos + Vector3.new(0,2.3,0), Color3.fromRGB(120,80,66))
		floatText(eggPos + Vector3.new(0,3,0), CONFIG.petName .. " hatched! \xF0\x9F\xA6\x96")
		local grantCF = CFrame.new(eggPos)
		if _G[CONFIG.spawnFollower] then pcall(function() _G[CONFIG.spawnFollower](grantCF) end) end
		if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet(CONFIG.petId, { petId=CONFIG.petId, displayName=CONFIG.petName, level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
		do local he = RS:FindFirstChild(CONFIG.hatchEvent); if he then pcall(function() he:FireServer() end) end end
		st.owns = true; st.hatching = false
		task.delay(1.4, function() pcall(function() egg:Destroy() end) end)
		print("[Geyser] island11 'Volcanic Vista' FINALE complete -> T-Rex hatched")
		-- THE PET IS YOURS. runFinale opens with REVEAL_PAUSE seconds of NOTHING so the T-Rex
		-- reveal is not stepped on, then builds -- vents letting go one at a time, the skull
		-- shattering, blasts closing in -- before the volcano finally goes. The pause lives
		-- inside runFinale rather than here so the whole running order is readable in one
		-- place. task.spawn so the prompt's Triggered handler returns immediately instead of
		-- blocking for the entire sequence.
		task.spawn(function() pcall(runFinale) end)
	end)
end

--======================================================================
-- THE FINALE -- runs the moment the T-Rex egg hatches (st.owns).
--======================================================================
-- Beat 1  (t=0)  The plug boulders BLOW OFF the vents and tumble into the sky.
-- Beat 2  (t=0)  Every geyser erupts far harder than before -- lava fired straight
--                up into the sky, huge glow, roaring steam.
-- Beat 3  (t=0+) Lava LEAKS across the ground: pools spread out from every vent and
--                keep creeping outward for the whole countdown.
-- Beat 4  (t=7)  The volcano detonates FROM THE DINO SKULL: white flash, shockwave
--                ring, lava chunks, screen goes red.
-- Beat 5  (t=7)  The player dies...
-- Beat 6         ...and the CANDY REALM intro card takes over. (Placeholder realm.)
--
-- This is all CLIENT-SIDE spectacle: every part here was created by this LocalScript,
-- so unanchoring / destroying them only affects this player. Nothing is replicated.
--======================================================================

--======================================================================
-- THE SHAPE OF THE FINALE. Three numbers, and the order of them IS the drama.
--
--   REVEAL_PAUSE  Nothing happens at all. You just hatched a T-Rex -- you get to LOOK at
--                 it. The finale used to open with a full-screen orange wash on the same
--                 frame as the hatch, which buried the reward the whole island was for.
--                 The pet reveal is the payoff; the volcano is the encore.
--
--   BUILD_TIME    The slow burn. It OPENS on the skull blowing apart -- that is the
--                 starting gun -- then the vents blow their caps ONE AT A TIME, the ground
--                 starts shaking, and small blasts land further and further from the
--                 crater, faster and faster. Nothing here is big except the skull. It is
--                 all setup, and it is the part that makes the payoff land.
--
--   CHAOS_TIME    Everything at once, accelerating, until the big one.
--
-- The whole point is that the big blast now has something to be the top of. Firing it all
-- on one frame -- which is what this did before -- spends the spectacle in half a second
-- and leaves ten seconds of nothing after it.
--======================================================================
local REVEAL_PAUSE = 3.0    -- see your pet. Nothing else happens.
local BUILD_TIME   = 7.0    -- the slow build
local CHAOS_TIME   = 2.0    -- everything at once, then the big one

local FINALE_FUSE = BUILD_TIME + CHAOS_TIME  -- total from "it starts" to "the island goes"

-- Big red warning banner + the panic line, up for the whole fuse.
local function showEruptionWarning()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "GeyserEruptionWarning"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 400; g.Parent = pgui

	-- ===== ONE FRAME, SO THE TOP-CENTRE STACK CAN OWN IT =====
	-- The warning and its countdown used to be two loose labels pinned at y=120 and y=188,
	-- outside TopCenterStack entirely -- so the island blowing up drew straight through a
	-- windstorm banner or the objective card. Every announcement in this realm belongs in
	-- the stack, so both labels now live in a single "Banner" frame, which is the child
	-- TopCenterStack adopts and repositions. Nothing here tweens Position, so the stack can
	-- move the frame freely; the alarm pulse below only touches colours and text.
	local wrap = Instance.new("Frame")
	wrap.Name = "Banner"
	wrap.AnchorPoint = Vector2.new(0.5, 0)
	wrap.Position = UDim2.new(0.5, 0, 0, 0)   -- the stack supplies the Y offset
	wrap.Size = UDim2.fromOffset(700, 108)    -- 62 banner + 6 gap + 40 countdown
	wrap.BackgroundTransparency = 1
	wrap.Parent = g

	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 0)
	banner.Size = UDim2.fromOffset(700, 62)
	banner.BackgroundColor3 = Color3.fromRGB(90, 22, 12)
	banner.BackgroundTransparency = 0.08
	banner.Font = Enum.Font.FredokaOne
	banner.TextScaled = true
	banner.TextColor3 = Color3.fromRGB(255, 220, 170)
	-- THE PLUGS FAILED -- that is the story beat, and the old line did not tell it. "THE
	-- GEYSERS ARE ERUPTING" describes the vents, which the player can already see erupting;
	-- what they cannot see is WHY, or that the thing now going off is the mountain itself.
	banner.Text = "\xE2\x9A\xA0\xEF\xB8\x8F THE PLUGS FAILED! THE VOLCANO IS EXPLODING!"
	banner.Parent = wrap
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
	local bs = Instance.new("UIStroke", banner); bs.Color = Color3.fromRGB(255, 120, 40); bs.Thickness = 3
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 32; c.Parent = banner end

	-- countdown under it, so the 10s fuse reads as a threat and not just noise
	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, 68)
	sub.Size = UDim2.fromOffset(520, 40)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 150, 90)
	sub.TextStrokeColor3 = Color3.new(0, 0, 0)
	sub.TextStrokeTransparency = 0.4
	-- The countdown is no longer counting DOWN TO the eruption -- that already happened, on
	-- the same frame this banner appeared. It now counts down to the island going under.
	sub.Text = "THE ISLAND IS COMING APART! GET OUT!"
	sub.Parent = wrap
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 26; c.Parent = sub end

	-- pulse the banner so it reads as an alarm
	task.spawn(function()
		local t0 = os.clock()
		while g.Parent and os.clock() - t0 < FINALE_FUSE + 1 do
			local k = 0.5 + 0.5 * math.sin(os.clock() * 7)
			bs.Thickness = 2 + k * 3
			banner.BackgroundColor3 = Color3.fromRGB(90 + math.floor(60 * k), 22, 12)
			local left = math.max(0, FINALE_FUSE - (os.clock() - t0))
			sub.Text = ("THE ISLAND GOES IN %.0f..."):format(left)
			task.wait()
		end
	end)

	Debris:AddItem(g, FINALE_FUSE + 1.2)
	return g
end

-- THE ERUPTION BLAST -- the one-shot bang when the volcano finally lets go.
--
-- Fired on the SAME beat as the "THE GEYSERS ARE ERUPTING!" banner and the rumble, so
-- the bang lands with the picture. One instance at the crater, NOT one per geyser: the
-- finale megaErupts all six vents in the same frame, so six copies would stack to six
-- times the volume and flam against each other instead of reading as one eruption.
--
-- The rolloff is deliberately huge (silent only past 700 studs) because this is the
-- finale of the ENDING island -- it should be audible anywhere on Volcanic Vista, not
-- just standing on the vent. startRumble's separate low loop still carries the fuse.
local ERUPTION_SOUND_ID = "rbxassetid://139900006476219"  -- the final volcano detonation
local GEYSER_BLAST_ID   = "rbxassetid://140615626179933"  -- one vent letting go

-- One-shot POSITIONAL sound on a throwaway anchor part. Both blasts below go through this
-- rather than each rebuilding the same anchor-and-cleanup dance.
--
-- THE DEBRIS BACKSTOP IS NOT REDUNDANT. Ended never fires if the asset fails to load or has
-- been moderated, and without the timer the anchor part would leak for the rest of the
-- session -- once per vent, per eruption.
local function playAt(pos, id, opts)
	opts = opts or {}

	local a = Instance.new("Part")
	a.Name = opts.name or "OneShotSound"
	a.Size = Vector3.new(1, 1, 1)
	a.CFrame = CFrame.new(pos)
	a.Transparency = 1
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Parent = Workspace

	local s = Instance.new("Sound")
	s.Name = a.Name
	s.SoundId = id
	s.Volume = opts.volume or 2
	s.PlaybackSpeed = opts.speed or 1
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = opts.minD or 40
	s.RollOffMaxDistance = opts.maxD or 400
	s.Parent = a
	pcall(function() s:Play() end)
	pcall(function() s.Ended:Once(function() pcall(function() a:Destroy() end) end) end)
	Debris:AddItem(a, opts.life or 20)
	return s
end

-- THE BIG ONE. Fired exactly once, at the end -- see the note at its call site. The rolloff
-- is deliberately huge (silent only past 700 studs) because this is the finale of the
-- ENDING island: it should be audible anywhere on Volcanic Vista, not just at the crater.
local function playEruptionBlast(pos)
	playAt(pos, ERUPTION_SOUND_ID, {
		name = "EruptionBlast", volume = 4.5, minD = 60, maxD = 700,
	})
end

-- ONE VENT. Tighter rolloff than the big blast so the six of them read as six separate
-- events across the island rather than one wall of noise on top of you.
--
-- PITCH IS RANDOMISED PER VENT, and that matters more than it sounds: six plays of an
-- identical clip inside five seconds is instantly recognisable as one sample repeating,
-- which makes a chaotic moment read as a loop. A few percent either way breaks that.
local function playGeyserBlast(pos)
	playAt(pos, GEYSER_BLAST_ID, {
		name = "GeyserBlast", volume = 2.6, minD = 30, maxD = 340,
		speed = 0.88 + math.random() * 0.28,
	})
end

-- SCATTERED FIRING ORDER. Walking st.geysers in its own order fires them in whatever
-- sequence the markers were found, which is usually the order they were placed -- so
-- neighbours go off back to back and the eruption reads as a tidy wave rolling across the
-- island. This picks a random vent, then repeatedly takes the one FURTHEST from the last,
-- which guarantees no two consecutive blasts are side by side.
local function scatterOrder(list)
	local pool = {}
	for _, g in ipairs(list) do table.insert(pool, g) end

	local out = {}
	if #pool == 0 then return out end

	local cur = table.remove(pool, math.random(#pool))
	table.insert(out, cur)

	while #pool > 0 do
		local bestI, bestD = 1, -1
		for i, g in ipairs(pool) do
			local a = g.ventPos or g.basePos
			local b = cur.ventPos or cur.basePos
			local d = (a and b) and (a - b).Magnitude or 0
			if d > bestD then bestD, bestI = d, i end
		end
		cur = table.remove(pool, bestI)
		table.insert(out, cur)
	end
	return out
end

-- Sustained ground rumble + screen shake for the whole fuse, ramping UP as the
-- eruption builds. CameraOffset is the safe way to shake -- it rides on top of
-- Roblox's camera instead of fighting it for control.
local function startRumble(duration)
	local host = Workspace:FindFirstChildWhichIsA("Camera") or Workspace

	-- low, growing roar
	local snd = Instance.new("Sound")
	snd.Name = "VolcanoRumble"
	snd.SoundId = "rbxassetid://9125402735" -- low rumble
	snd.Looped = true
	snd.Volume = 0.4
	snd.RollOffMode = Enum.RollOffMode.Linear
	snd.Parent = host
	pcall(function() snd:Play() end)

	-- THE BED. An avalanche-ish wash that comes in AUDIBLE from the very first frame of the
	-- build and stays under everything.
	--
	-- It exists because the rumble alone starts at 0.4 and climbs, which left the opening of
	-- the finale nearly silent -- so the sequence went quiet, quiet, quiet, BANG, and the
	-- build had nothing carrying it. The bed fills that floor. The two are deliberately
	-- different jobs: the bed is PRESENT and barely moves, the rumble is quiet and RISES.
	-- Layering a mover under a constant is what reads as pressure building rather than as
	-- one sample getting louder.
	local bed = Instance.new("Sound")
	bed.Name = "VolcanoBed"
	bed.SoundId = "rbxassetid://5530239453"
	bed.Looped = true
	bed.Volume = 1.35
	bed.RollOffMode = Enum.RollOffMode.Linear
	bed.Parent = host
	pcall(function() bed:Play() end)

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local p = (os.clock() - t0) / duration -- 0 -> 1 as the fuse burns down
			pcall(function() bed.Volume = 1.35 + p * 0.75 end)
			local char = player.Character
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			if hum then
				-- shake grows from a light tremor to a violent quake
				local amp = 0.35 + p * p * 2.6
				hum.CameraOffset = Vector3.new(
					(math.random() - 0.5) * amp,
					(math.random() - 0.5) * amp,
					(math.random() - 0.5) * amp
				)
			end
			pcall(function() snd.Volume = 0.4 + p * 0.9; snd.PlaybackSpeed = 0.85 + p * 0.4 end)
			task.wait()
		end
		pcall(function() snd:Stop(); snd:Destroy() end)

		-- The bed FADES rather than cutting. It runs out at the exact moment the big blast
		-- lands, and dropping a loop dead on that frame leaves an audible hole underneath
		-- the one sound that most needs something behind it.
		task.spawn(function()
			local v0, f0 = bed.Volume, os.clock()
			while bed.Parent and os.clock() - f0 < 2.0 do
				pcall(function() bed.Volume = v0 * (1 - (os.clock() - f0) / 2.0) end)
				task.wait()
			end
			pcall(function() bed:Stop(); bed:Destroy() end)
		end)

		-- do NOT zero CameraOffset here: volcanoExplosion() takes over the shake
		-- immediately and would fight this on the same frame.
	end)
end

-- Find the dino skull the explosion originates from. Island first, then anywhere.
-- Accepts "DinoSkull", "dino skull", "Skull", "skull_01", ... (punctuation-insensitive)
local function findSkull()
	local function scan(root)
		if not root then return nil end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Model") then
				local n = d.Name:lower():gsub("[^%w]", "")
				if n:find("dinoskull", 1, true) or n:find("skull", 1, true) then return d end
			end
		end
		return nil
	end
	return scan(st.island) or scan(Workspace)
end

local function posOf(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	local ok, pivot = pcall(function() return inst:GetPivot().Position end)
	return ok and pivot or nil
end

-- Drop a ray to find the walkable surface under a point (for the lava pools).
-- `fallbackY` is used when the ray misses -- island11's mesh is only partly
-- raycast-queryable, so a miss is COMMON here. Callers pass the geyser's basePos
-- (the ground the chimney was built on), never ventPos, or the pool ends up
-- hovering 6+ studs in the air.
local function groundAt(pos, fallbackY)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character }
	-- start well above and search well below: the pools sit on uneven volcanic ground
	local hit = Workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), rp)
	if hit then return hit.Position.Y end
	return fallbackY or pos.Y
end

-- A flat disc of lava that spreads outward. Cylinder rotated 90deg about Z so its
-- circular face lies FLAT on the ground (Size = height, diameter, diameter).
local function spreadLavaPool(pos, maxRadius, growTime)
	local p = Instance.new("Part")
	p.Name = "LavaLeak"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.35, 2, 2)
	-- pos is already a GROUND position (a geyser's basePos), so it doubles as the
	-- fallback height when the surface ray misses -> the pool always lies flat on the
	-- terrain instead of floating above it.
	p.CFrame = CFrame.new(pos.X, groundAt(pos, pos.Y) + 0.15, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = Color3.fromRGB(255, 95, 25)
	p.Material = Enum.Material.Neon
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Parent = Workspace
	TS:Create(p, TweenInfo.new(growTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.35, maxRadius * 2, maxRadius * 2),
	}):Play()
	return p
end

-- BEAT 1: pop the plug boulder off the vent and hurl it skyward.
local function blowCapOff(g)
	local cap = g.cap
	if not (cap and cap.Parent) then return end
	cap.Anchored = false
	cap.CanCollide = false
	cap.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 60, 130 + math.random() * 60, (math.random() - 0.5) * 60)
	cap.AssemblyAngularVelocity = Vector3.new((math.random() - 0.5) * 24, (math.random() - 0.5) * 24, (math.random() - 0.5) * 24)
	Debris:AddItem(cap, 10)
	g.cap = nil
end

-- BEAT 2: the vent goes from "capped" to a full sky-high eruption column.
local function megaErupt(g)
	-- NOTE: buildGeyser's idle "eruption blob" loop is `while not g.plugged` -- it
	-- already exited for good when this vent was plugged, and clearing g.plugged would
	-- NOT restart it. So don't bother: drive the eruption straight off the emitters.
	g.lava.Rate        = 320
	g.lava.Speed       = NumberRange.new(150, 240) -- straight up into the sky
	g.lava.Lifetime    = NumberRange.new(1.8, 3.4)
	g.lava.Size        = NumberSequence.new(7, 0)
	g.lava.SpreadAngle = Vector2.new(7, 7)
	g.lava.Acceleration = Vector3.new(0, -70, 0)

	g.steam.Rate     = 90
	g.steam.Size     = NumberSequence.new(9, 26)
	g.steam.Speed    = NumberRange.new(30, 55)
	g.steam.Lifetime = NumberRange.new(2, 4)

	g.light.Brightness = 14
	g.light.Range      = 70
	g.light.Color      = Color3.fromRGB(255, 120, 30)

	-- a glowing column shooting up out of the vent
	local beam = Instance.new("Part")
	beam.Name = "EruptionColumn"
	beam.Size = Vector3.new(3.2, 220, 3.2)
	beam.CFrame = CFrame.new(g.ventPos + Vector3.new(0, 110, 0))
	beam.Color = Color3.fromRGB(255, 140, 45)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.Anchored = true; beam.CanCollide = false; beam.CanQuery = false; beam.CastShadow = false
	beam.Parent = Workspace
	TS:Create(beam, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(7, 420, 7), Transparency = 0.25,
	}):Play()
	Debris:AddItem(beam, FINALE_FUSE + 3)
end

-- THE DETONATION, centred on the dino skull.
--
-- NO LAVA. The ejecta used to be neon orange balls, which read as the volcano vomiting
-- lava; it is now shattered ROCK -- dark stone, a few pieces still glowing from the heat.
-- The geysers are what throw bright columns; the volcano throws the mountain.
--
-- @param origin Vector3
-- @param opts   { scale: number?, full: boolean? }
--   scale -- 1 is the main blast; the aftershocks through the fuse use ~0.3.
--   full  -- screen wash + camera kick. Main blast only; an aftershock that re-washed the
--            screen red every two seconds would strobe rather than build.
local function volcanoExplosion(origin, opts)
	opts = opts or {}
	local scale = opts.scale or 1
	local full  = opts.full ~= false

	-- white-hot core
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(6, 6, 6)
	flash.CFrame = CFrame.new(origin)
	flash.Color = Color3.fromRGB(255, 250, 235)
	flash.Material = Enum.Material.Neon
	flash.Anchored = true; flash.CanCollide = false; flash.CanQuery = false; flash.CastShadow = false
	flash.Parent = Workspace
	local flashTo = 900 * scale
	TS:Create(flash, TweenInfo.new(1.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(flashTo, flashTo, flashTo), Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 1.6)

	local pl = Instance.new("PointLight")
	pl.Brightness = 60 * scale; pl.Range = 480 * scale; pl.Color = Color3.fromRGB(255, 175, 90); pl.Parent = flash

	-- ASH DOME -- a dark boiling ball chasing the white core out. Without it the blast is a
	-- flash of light and nothing else; the dome is what gives it mass.
	local dome = Instance.new("Part")
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(10, 10, 10)
	dome.CFrame = CFrame.new(origin)
	dome.Color = Color3.fromRGB(46, 38, 36)
	dome.Material = Enum.Material.Slate
	dome.Transparency = 0.1
	dome.Anchored = true; dome.CanCollide = false; dome.CanQuery = false; dome.CastShadow = false
	dome.Parent = Workspace
	local domeTo = 620 * scale
	TS:Create(dome, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(domeTo, domeTo, domeTo), Transparency = 1,
	}):Play()
	Debris:AddItem(dome, 2.5)

	-- TWO ground shockwaves, not one: a fast thin leading edge and a slower fat one behind
	-- it. A single ring reads as a graphic; two reads as a pressure wave.
	local groundY = groundAt(origin) + 1
	for i, spec in ipairs({
		{ time = 1.3, to = 1700, thick = 1.5, color = Color3.fromRGB(255, 235, 190), trans = 0.1 },
		{ time = 2.4, to = 1150, thick = 5.0, color = Color3.fromRGB(255, 120, 40), trans = 0.3 },
	}) do
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(spec.thick, 8, 8)
		ring.CFrame = CFrame.new(origin.X, groundY + i, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = spec.color
		ring.Material = Enum.Material.Neon
		ring.Transparency = spec.trans
		ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
		ring.Parent = Workspace
		local to = spec.to * scale
		TS:Create(ring, TweenInfo.new(spec.time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(spec.thick, to, to), Transparency = 1,
		}):Play()
		Debris:AddItem(ring, spec.time + 0.4)
	end

	-- ROCK blown out of the crater. Chunky, tumbling, mostly dark with a few still glowing.
	for _ = 1, math.floor(70 * scale) do
		local c = Instance.new("Part")
		local s = 3 + math.random() * 9
		c.Size = Vector3.new(s, s * (0.5 + math.random() * 0.8), s * (0.6 + math.random() * 0.7))
		c.CFrame = CFrame.new(origin + Vector3.new((math.random() - 0.5) * 14, 3, (math.random() - 0.5) * 14))
			* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		local hot = math.random() < 0.28
		c.Color = hot and Color3.fromRGB(255, 120 + math.random(0, 70), 45)
			or Color3.fromRGB(38 + math.random(0, 26), 32 + math.random(0, 20), 30)
		c.Material = hot and Enum.Material.Neon or Enum.Material.Slate
		c.Anchored = false; c.CanCollide = false; c.CastShadow = false
		c.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 420 * scale,
			150 + math.random() * 300 * scale,
			(math.random() - 0.5) * 420 * scale)
		c.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 40, (math.random() - 0.5) * 40, (math.random() - 0.5) * 40)
		c.Parent = Workspace
		Debris:AddItem(c, 9)
	end

	if not full then return end

	-- screen goes red
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "VolcanoBlast"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 500; g.Parent = pgui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(255, 80, 30); fill.BackgroundTransparency = 1; fill.Parent = g
	-- Snap to a hard white-hot wash, THEN settle to a red haze. The old single half-second
	-- fade to 0.15 was a tint; a blast should hit the eye before it colours the screen.
	TS:Create(fill, TweenInfo.new(0.08), { BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 240, 220) }):Play()
	task.delay(0.12, function()
		if fill.Parent then
			TS:Create(fill, TweenInfo.new(0.9), { BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(255, 70, 25) }):Play()
		end
	end)
	Debris:AddItem(g, 4)

	-- camera kick (CameraOffset is the safe way to shake without fighting Roblox's camera)
	task.spawn(function()
		local char = player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if not hum then return end
		local t0, dur = os.clock(), 3.0
		while os.clock() - t0 < dur and hum.Parent do
			-- Starts at 9 (was 3.5) and decays on a CURVE rather than a straight line, so the
			-- first half second is a genuine slam and the tail still rattles.
			local k = 1 - (os.clock() - t0) / dur
			local amp = 9 * k * k
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * amp, (math.random() - 0.5) * amp, (math.random() - 0.5) * amp)
			task.wait()
		end
		if hum.Parent then hum.CameraOffset = Vector3.zero end
	end)
end

-- SkullExplode -- the builder's own part, blown to pieces on the same frame as everything
-- else. Optional: if no part by that name exists the finale is unchanged.
--
-- A MODEL is unanchored and every part hurled outward. A single PART is shattered into
-- FRAGMENTS instead of being thrown whole -- one part sailing off intact reads as a prop
-- falling over, not as something exploding. The original is hidden rather than destroyed
-- so nothing else on the island that references it breaks.
local function skullExplode()
	local root = st.island or Workspace

	-- TWO PASSES, AND THE SECOND ONE IS THE IMPORTANT ONE.
	--
	-- Pass 1 looks for a part named exactly "SkullExplode" -- a dedicated prop, if the
	-- builder made one.
	--
	-- Pass 2 falls back to THE DINO SKULL ITSELF, via the same loose matcher findSkull()
	-- uses for the explosion origin ("DinoSkull", "dino skull", "Skull", "skull_01"...).
	-- Without this fallback the whole flourish silently did nothing on any island that has
	-- a DinoSkull but no part called SkullExplode -- which is every island as built. The
	-- head then never came apart at all, and the only skull moment left was the final
	-- detonation firing FROM it, at the very end, where it cannot be seen.
	--
	-- Shattering the origin part is safe: runFinale captured `origin` as a Vector3 long
	-- before this runs, so the explosion still knows where to go once the skull is gone.
	local target
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and string.lower(d.Name) == "skullexplode" then
			target = d
			break
		end
	end
	if not target then target = findSkull() end

	if not target then
		print("[Geyser] FINALE: no skull found (looked for 'SkullExplode', then any "
			.. "skull-named part) -- skipping that flourish")
		return
	end
	print(("[Geyser] FINALE: blowing apart '%s'"):format(target:GetFullName()))

	local function hurl(p, centre)
		local dir = (p.Position - centre)
		dir = (dir.Magnitude > 0.1) and dir.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		p.Anchored = false
		p.CanCollide = false
		p.CastShadow = false
		p.AssemblyLinearVelocity = dir * (140 + math.random() * 180) + Vector3.new(0, 190 + math.random() * 190, 0)
		p.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 50, (math.random() - 0.5) * 50, (math.random() - 0.5) * 50)
		Debris:AddItem(p, 9)
	end

	if target:IsA("Model") then
		local ok, cf = pcall(function() return (target:GetBoundingBox()) end)
		local centre = ok and cf and cf.Position or target:GetPivot().Position
		for _, p in ipairs(target:GetDescendants()) do
			if p:IsA("BasePart") then hurl(p, centre) end
		end
		print("[Geyser] FINALE: SkullExplode model blown apart")
		return centre
	end

	-- Single part: build fragments from it, then hide the original.
	local centre = target.Position
	local size = target.Size
	for _ = 1, 22 do
		local f = target:Clone()
		f.Name = "SkullShard"
		f:ClearAllChildren()
		f.Size = Vector3.new(
			math.max(0.4, size.X * (0.15 + math.random() * 0.25)),
			math.max(0.4, size.Y * (0.15 + math.random() * 0.25)),
			math.max(0.4, size.Z * (0.15 + math.random() * 0.25)))
		f.CFrame = CFrame.new(centre + Vector3.new(
			(math.random() - 0.5) * size.X,
			(math.random() - 0.5) * size.Y,
			(math.random() - 0.5) * size.Z)) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		f.Transparency = 0
		f.Parent = Workspace
		hurl(f, centre)
	end
	target.Transparency = 1
	pcall(function() target.CanCollide = false end)
	print("[Geyser] FINALE: SkullExplode shattered into 22 shards")
	return centre
end

-- BEAT 6: the CANDY REALM intro card -- and now the actual TELEPORT. The card used
-- to be a "coming soon" placeholder; the realm exists, so once the card is up this
-- waits for the respawn, then hops through the Wormhole's own RequestRealmWarp
-- ("Candy") -- same remote the travel menu uses, so pets/skins/earned-coin deltas
-- travel exactly like a wormhole trip. If travel is unavailable (Studio blocks
-- teleports; the place could be private) it fades out gracefully instead.
local function showCandyRealmIntro()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "CandyRealmIntro"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 600; g.Parent = pgui

	-- fade up from black over the death
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(12, 6, 14); bg.BackgroundTransparency = 1; bg.Parent = g
	TS:Create(bg, TweenInfo.new(1.2), { BackgroundTransparency = 0 }):Play()
	task.wait(1.2)

	-- candy gradient wash
	bg.BackgroundColor3 = Color3.fromRGB(255, 235, 245)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 170, 215)), -- bubblegum
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 225, 240)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(170, 225, 255)), -- cotton candy blue
	})
	grad.Parent = bg

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.46)
	title.Size = UDim2.fromOffset(760, 96)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(120, 30, 90)
	title.TextTransparency = 1
	title.Text = "\xF0\x9F\x8D\xAD  THE CANDY REALM"
	title.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 74; c.Parent = title end
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(255, 255, 255); ts.Thickness = 4; ts.Parent = title

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.58)
	sub.Size = UDim2.fromOffset(620, 44)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(90, 60, 110)
	sub.TextTransparency = 1
	sub.Text = "The eruption is sending you there..."
	sub.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = sub end

	TS:Create(title, TweenInfo.new(1.0), { TextTransparency = 0 }):Play()
	task.wait(0.35)
	TS:Create(sub, TweenInfo.new(1.0), { TextTransparency = 0 }):Play()

	print("[Geyser] CANDY REALM intro shown -- waiting for respawn, then warping to the Candy Realm")

	-- ===== THE ACTUAL TRIP =====
	-- The player just died to the eruption, so wait for the respawned character to be
	-- alive and GROUNDED (the warp's server gate refuses airborne players), then ask
	-- the Wormhole service for the Candy hop. A few retries, because the respawn can
	-- take a beat; the card stays up the whole time so the teleport happens "inside"
	-- the candy wash instead of showing the island again first.
	local RSs = game:GetService("ReplicatedStorage")
	local warp
	pcall(function()
		local folder = RSs:WaitForChild("WormholeRemotes", 10)
		warp = folder and folder:WaitForChild("RequestRealmWarp", 5)
	end)
	local travelled, hardFails = false, 0
	local t0 = os.clock()
	while warp and os.clock() - t0 < 30 and hardFails < 3 do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air then
			local okI, result = pcall(function() return warp:InvokeServer("Candy") end)
			if okI and type(result) == "table" and result.ok then
				travelled = true
				break
			end
			hardFails += 1 -- server said no (teleport failed / Studio) -- don't grind forever
		end
		task.wait(0.5)
	end
	if travelled then
		sub.Text = "Welcome to the CANDY REALM!"
		task.wait(8) -- the teleport takes over mid-wait; the card never comes down
		pcall(function() g:Destroy() end) -- only reached if the teleport silently stalled
		return
	end

	-- travel unavailable (Studio, private place, no remote) -> the old graceful fade
	sub.Text = "The portal fizzles... come back through the Wormhole!"
	task.wait(3)
	TS:Create(title, TweenInfo.new(1.0), { TextTransparency = 1 }):Play()
	TS:Create(sub,   TweenInfo.new(1.0), { TextTransparency = 1 }):Play()
	TS:Create(bg,    TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
	task.wait(1.6)
	pcall(function() g:Destroy() end)
end

-- (assigns to the local forward-declared above the reward egg)
function runFinale()
	if st.finale then return end -- one shot
	st.finale = true

	local skull = findSkull()
	local origin = posOf(skull)
	if origin then
		print(("[Geyser] FINALE: explosion origin = '%s' at %s"):format(skull.Name, tostring(origin)))
	else
		-- no skull in the place -> fall back to the middle of the geyser field so the
		-- finale still plays instead of silently doing nothing.
		local sum, n = Vector3.zero, 0
		for _, g in ipairs(st.geysers) do sum += g.ventPos; n += 1 end
		origin = (n > 0) and (sum / n) or (posOf(st.island) or Vector3.new(0, 0, 0))
		warn("[Geyser] FINALE: no 'DinoSkull' found -> exploding from the centre of the geyser field instead. "
			.. "Name a part/model 'DinoSkull' on island11 to set the crater.")
	end

	-- ============================================================
	-- BEAT 0 -- THE PET. Nothing happens at all for REVEAL_PAUSE seconds.
	--
	-- This wait is why the finale reads properly now. It used to open on the SAME FRAME as
	-- the hatch, so a full-screen orange wash landed over the T-Rex the player had just
	-- spent a whole island earning -- they never saw it. The volcano can wait three
	-- seconds. The pet is the reward; the volcano is the encore.
	-- ============================================================
	task.wait(REVEAL_PAUSE)

	-- ============================================================
	-- BEAT 1 -- THE BUILD (BUILD_TIME). All setup, nothing big yet.
	--
	-- NO MORE CREEPING LAVA. spreadLavaPool used to paint discs out from every vent for the
	-- full fuse; the volcano throws rock and ash now, not lava.
	--
	-- spreadLavaPool is left in the file and now has NO callers at all -- kept deliberately,
	-- because "put the lava back" is otherwise a rewrite rather than two lines. If it is
	-- still unused next time someone passes through here, delete it.
	-- ============================================================
	showEruptionWarning()
	startRumble(FINALE_FUSE)   -- ramps up over its duration on its own

	-- THE SKULL GOES FIRST -- the opening image of the whole sequence, on the same frame the
	-- eruption starts. It is the loudest single thing in the build, and putting it up front
	-- is what announces that the finale has begun: the head pops apart, and THEN the island
	-- starts coming undone around it.
	--
	-- (It sat at 55% through the build for one revision. That was wrong twice over -- it
	-- arrived after the player had already worked out what was happening, and it landed in
	-- the middle of the accelerating blasts where it read as just another one of them.)
	do
		local at = skullExplode()
		if at then
			volcanoExplosion(at, { scale = 0.55, full = false })
			floatText(at + Vector3.new(0, 12, 0), "THE SKULL BLOWS APART!", Color3.fromRGB(255, 210, 140))
		else
			floatText(origin + Vector3.new(0, 10, 0), "THE PLUGS ARE FAILING!", Color3.fromRGB(255, 150, 60))
		end
	end

	-- Caps come off ONE AT A TIME across the first ~72% of the build, each vent erupting and
	-- sounding off as it goes, and all of them done well before the big blast. Six bangs you
	-- can count is a build; six in one frame is a noise.
	--
	-- TWO THINGS MAKE IT FEEL CHAOTIC RATHER THAN MECHANICAL:
	--   * ORDER is scattered (scatterOrder) -- each vent is the furthest one from the last,
	--     so the eruption jumps across the island instead of rolling along the row.
	--   * SPACING is irregular. Evenly spaced blasts read as a metronome no matter what
	--     order they are in. The jitter multiplier averages 1.0, so the whole run still
	--     lands inside its budget.
	task.spawn(function()
		local order = scatterOrder(st.geysers)
		local n = math.max(#order, 1)
		local base = (BUILD_TIME * 0.72) / n

		for _, g in ipairs(order) do
			blowCapOff(g)
			megaErupt(g)
			playGeyserBlast(g.ventPos or g.basePos)
			-- a small burst under the vent as it lets go, so the cap popping has weight
			volcanoExplosion(g.basePos or g.ventPos, { scale = 0.16, full = false })
			task.wait(base * (0.45 + math.random() * 1.10))
		end
	end)

	-- Small blasts creeping outward from the crater and speeding up. This is the pressure
	-- gauge: at the start they are a beat apart, by the end they are almost on top of
	-- each other -- which is what tells the player something much bigger is coming.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < BUILD_TIME do
			local k = (os.clock() - t0) / BUILD_TIME              -- 0 -> 1 across the build
			local a, r = math.random() * math.pi * 2, 25 + math.random() * (40 + 140 * k)
			volcanoExplosion(
				origin + Vector3.new(math.cos(a) * r, math.random() * 25, math.sin(a) * r),
				{ scale = 0.10 + 0.22 * k, full = false })
			task.wait(1.10 - 0.75 * k)                            -- 1.1s apart -> 0.35s apart
		end
	end)

	task.wait(BUILD_TIME)

	-- ============================================================
	-- BEAT 2 -- CHAOS (CHAOS_TIME). Everything, accelerating, nothing held back.
	-- Still no screen wash: washing the screen out here would strobe for four seconds and
	-- leave the real blast with nowhere left to go.
	-- ============================================================
	floatText(origin + Vector3.new(0, 14, 0), "IT'S GOING!", Color3.fromRGB(255, 90, 40))
	local chaosEnd = os.clock() + CHAOS_TIME
	while os.clock() < chaosEnd do
		local k = 1 - (chaosEnd - os.clock()) / CHAOS_TIME        -- 0 -> 1 across the chaos
		local a, r = math.random() * math.pi * 2, 15 + math.random() * 190
		volcanoExplosion(
			origin + Vector3.new(math.cos(a) * r, math.random() * 60, math.sin(a) * r),
			{ scale = 0.30 + 0.50 * k, full = false })
		task.wait(0.34 - 0.24 * k)                                -- 0.34s apart -> 0.10s apart
	end

	-- ============================================================
	-- BEAT 3 -- THE BIG ONE. The only blast in the whole finale that washes the screen.
	-- ============================================================
	playEruptionBlast(origin)
	volcanoExplosion(origin)

	-- BEAT 4: the player doesn't survive it
	task.wait(0.45)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then hum.Health = 0 end

	-- BEAT 5: on into the (placeholder) next realm
	showCandyRealmIntro()
end

-- ===== BOOT =====
task.spawn(function()
	local isl = Workspace:FindFirstChild(CONFIG.islandName) or Workspace:WaitForChild(CONFIG.islandName, 60)
	if not isl then warn("[Geyser] " .. CONFIG.islandName .. " not found -> volcano quest skipped"); return end
	st.island = isl -- the FINALE searches this island for the DinoSkull
	-- NO AUTO-ACCEPT. This used to set Island11QuestAccepted itself, with the note "no NPC
	-- yet -> auto-accept so the banner shows the task". There IS an NPC now -- the AshWarden
	-- is placed on island11 by NestingNook_NPCs and sets that attribute when talked to -- so
	-- the script granting it on arrival meant the quest was ALWAYS already accepted and the
	-- AshWarden was decorative. Plugging is gated on the real attribute below; only he sets it.

	-- Robust per-name finder. SEARCHES ISLAND11 FIRST, then falls back to the rest of
	-- Workspace. The island-first order matters: if stale Geyser1..6 marker blocks are
	-- still parented under the OLD island8, a Workspace-wide search would find those
	-- first and build the geysers on island8 -- while the HUD only shows on island11,
	-- making the quest unplayable. Scoping to the island makes the live markers win.
	-- Each scope: exact name -> then case/punctuation-insensitive ("Geyser (1)" -> "geyser1").
	-- NOTE the TYPE CHECK on the exact-name hit. Without it, anything named "Geyser1"
	-- that is NOT a BasePart/Model (a Folder, Attachment, Configuration, ...) would be
	-- returned, the `or` in findNamed would short-circuit, the Workspace fallback would
	-- never run, and the caller -- which only accepts a BasePart/Model -- would silently
	-- reject it and report "Geyser1 not found". Only ever hand back a usable instance.
	local function usable(d)
		return d ~= nil and (d:IsA("BasePart") or d:IsA("Model"))
	end
	local function findIn(root, want)
		local exact = root:FindFirstChild(want, true)
		if usable(exact) then return exact end
		local w = want:lower():gsub("[^%w]", "")
		for _, d in ipairs(root:GetDescendants()) do
			if usable(d) and d.Name:lower():gsub("[^%w]", "") == w then return d end
		end
		return nil
	end
	local function findNamed(want)
		return findIn(isl, want) or findIn(Workspace, want) -- island11 first, then anywhere
	end

	-- THE EGG SPOT, found ONCE and used by two callers -- setup (which builds the nest on
	-- it) and onAllPlugged (which drops the egg into that nest). They used to duplicate
	-- this search, which is exactly how a nest and an egg end up in different places.
	--
	-- Exact "EggSpot8" first, then ANY part on this island whose name looks like an egg
	-- spot: island11 inherited island8's naming, so the block may be called EggSpot8 /
	-- EggSpot11 / EggSpot / eggspot_1.
	local function findEggSpot()
		local spot = findNamed("EggSpot8")
		if spot then return spot end
		for _, d in ipairs(isl:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():gsub("[^%w]", ""):find("eggspot", 1, true) then
				warn(("[Geyser] no 'EggSpot8' -> using the egg marker '%s' found on %s instead."):format(d.Name, CONFIG.islandName))
				return d
			end
		end
		return nil
	end

	-- Hide a placement block without moving it. CanQuery goes false too, which also keeps
	-- the nest's ground raycast from hitting the marker instead of the island.
	local function ghostMarker(inst)
		pcall(function()
			if inst:IsA("BasePart") then
				inst.Transparency = 1; inst.CanCollide = false; inst.CanQuery = false; inst.CanTouch = false
			end
			for _, p in ipairs(inst:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
				end
			end
		end)
	end

	--------------------------------------------------------------------
	-- WAIT FOR ISLAND 11 TO STREAM IN. Do not skip this.
	--------------------------------------------------------------------
	-- The place has StreamingEnabled. The island MODEL replicates to the client at
	-- join, but its PARTS do not -- they only arrive once the player is near it.
	-- island11 is the TOP of a 19,000-stud tower, so at spawn (island1) it is an
	-- EMPTY SHELL on this client:
	--     Workspace:FindFirstChild("island11")  -> the Model (exists)
	--     island11:GetBoundingBox()             -> size (0, 0, 0)   <- no parts
	--     island11:FindFirstChild("Geyser1")    -> nil              <- not streamed
	--
	-- The old code just retried for 20s and then declared the markers "missing from
	-- the place" and auto-placed fake ones. They were never missing -- the client
	-- simply hadn't been sent them yet. It only ever worked when the player happened
	-- to teleport to island11 inside that 20s window.
	--
	-- So: block here until the island actually has geometry. This task is doing
	-- nothing useful before then anyway -- the quest only exists on island11.
	local function islandHasStreamedIn()
		local ok, _, size = pcall(function() return isl:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end

	if not islandHasStreamedIn() then
		print("[Geyser] island11 has not streamed in yet (0 parts on this client) -- waiting until the player reaches it...")
		local waited = 0
		while not islandHasStreamedIn() do
			task.wait(1)
			waited += 1
			if waited % 30 == 0 then
				if VERBOSE then print(("[Geyser]   still waiting for island11 to stream in (%ds)"):format(waited)) end
			end
		end
		print(("[Geyser] island11 streamed in after %ds -> looking for the Geyser markers"):format(waited))
	end

	-- island centre (for the egg fallback) -- computed AFTER streaming, or the bbox
	-- would be a zero-size box at the island's pivot and every fallback would be wrong.
	local bcf, bsize = isl:GetBoundingBox()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { player.Character }
	local topY = bcf.Position.Y + bsize.Y/2
	local hit = Workspace:Raycast(Vector3.new(bcf.Position.X, topY + 60, bcf.Position.Z), Vector3.new(0,-400,0), rp)
	local center = Vector3.new(bcf.Position.X, (hit and hit.Position.Y or topY), bcf.Position.Z)

	buildHUD(); updateHUD()

	local function onAllPlugged()
		if st.done then return end
		st.done = true
		st.plugged = CONFIG.count -- keep the HUD honest if we got here via /done
		updateHUD()

		-- ACTUALLY PLUG THE VENTS. This used to only move the counter, which was fine in
		-- normal play -- you got here BY plugging all six -- and quietly broken on the
		-- /done and complete13 skip paths, where no vent was ever plugged:
		--
		--   * SIX LOOPING STEAM HISSES NEVER STOPPED. The fade lives in plugGeyser, so a
		--     skipped quest left all six sizzling for the rest of the session, straight
		--     through the reveal and the finale.
		--   * The idle "eruption blob" loops kept running (they spin on `not g.plugged`).
		--   * NO CAP BOULDERS EVER APPEARED -- so the finale's blowCapOff had nothing to
		--     blow off, and the whole "caps come off one at a time" beat was invisible.
		--
		-- Silent, because six boulder slams in one frame stack into mush. In normal play
		-- every geyser is already plugged and this whole loop is a no-op.
		for _, g in ipairs(st.geysers) do plugGeyser(g, true) end
		if vignette then TS:Create(vignette, TweenInfo.new(1.5), { BackgroundTransparency = 1 }):Play() end
		floatText(center + Vector3.new(0,6,0), "The volcano is calm! An egg appears...", Color3.fromRGB(255,210,140))
		-- WHERE THE EGG GOES. Setup has already found the marker, ghosted it and stood the
		-- nest on it, so in normal play this is a straight lookup. Reusing the STORED
		-- position rather than re-finding the marker is the whole point: it is what
		-- guarantees the egg lands IN the nest instead of a couple of studs beside it.
		local eggPos = st.nestPos
		if not eggPos then
			-- No nest -- the marker was missing when setup ran. Fall back to the old
			-- behaviour so the finale still completes rather than dead-ending.
			local eggSpot = findEggSpot()
			eggPos = (eggSpot and ((eggSpot:IsA("BasePart") and eggSpot.Position) or eggSpot:GetPivot().Position)) or center
			if eggSpot then
				ghostMarker(eggSpot)
				print(("[Geyser] no nest -> egg at marker '%s' %s (ghosted)"):format(eggSpot.Name, tostring(eggPos)))
			else
				warn("[Geyser] no egg marker found -> reward egg spawns at the island centre. Name a part 'EggSpot8' on island11.")
			end
		end
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

	--------------------------------------------------------------------
	-- SAFETY NET: the marker blocks are missing from the place.
	--------------------------------------------------------------------
	-- island11 is the FINALE island -- if its Geyser1..6 blocks get deleted, the whole
	-- endgame (plug the geysers -> T-Rex -> volcano -> Candy Realm) silently dies and
	-- the summit is just scenery. Rather than leave it dead, auto-place the missing
	-- vents in a ring on the island's surface and carry on.
	--
	-- This is a FALLBACK, not the intended layout -- it warns loudly. To control where
	-- the geysers actually go, put parts named Geyser1..Geyser6 on island11.
	local missing = {}
	for i = 1, CONFIG.count do
		if not geyserParts[i] then missing[#missing + 1] = i end
	end
	if #missing > 0 then
		local bcf, bsize = isl:GetBoundingBox()

		-- CENTRE THE RING ON THE DINO SKULL. The skull IS the crater (it's where the
		-- finale explosion originates), so a ring around it lands the vents in the
		-- volcano's mouth rather than dumped in the middle of the island. Only fall
		-- back to the island's bounding-box centre if there is no skull.
		local skull = findSkull()
		local centre = posOf(skull) or bcf.Position
		local from = skull and ("DinoSkull '" .. skull.Name .. "'") or "island bounding-box centre"

		-- A FIXED radius. The old formula (min(bsizeX,bsizeZ) * 0.22) collapsed to its
		-- 18-stud floor on island11 and bunched all six vents into a tiny ring in the
		-- middle of the map. The real geyser field sat 70-130 studs out, so use a radius
		-- in that ballpark and clamp it to the island so the vents can't fall off it.
		local radius = math.clamp(55, 18, math.max(18, math.min(bsize.X, bsize.Z) * 0.5 - 10))

		-- NOTE: we only get here AFTER island11 has streamed in, so the island really does
		-- have its geometry on this client and these blocks really are absent from it --
		-- this is no longer the "not streamed yet" false alarm.
		warn(("[Geyser] island11 IS streamed in, but %d of %d Geyser marker block(s) are genuinely absent "
			.. "-> auto-placing a %d-stud ring around the %s. THIS IS A GUESS -- add parts named "
			.. "Geyser1..Geyser%d to island11 to put them where you actually want them.")
			:format(#missing, CONFIG.count, radius, from, CONFIG.count))
		print(("[Geyser]   island11 bbox: centre=(%.0f, %.0f, %.0f) size=(%.0f, %.0f, %.0f)")
			:format(bcf.Position.X, bcf.Position.Y, bcf.Position.Z, bsize.X, bsize.Y, bsize.Z))

		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character }

		for _, i in ipairs(missing) do
			local a = (i - 1) * (2 * math.pi / CONFIG.count)
			local x = centre.X + math.cos(a) * radius
			local z = centre.Z + math.sin(a) * radius

			-- Drop onto the walkable surface. Ray from well ABOVE the ring's own height.
			-- island11's mesh is only partly raycast-queryable (that's what buried the
			-- geysers earlier), so if the ray misses, keep the ring's own Y rather than
			-- snapping to the bbox top -- the bbox top is the volcano PEAK (~20424),
			-- 200 studs above the ground the player actually stands on (~20206).
			local hit = Workspace:Raycast(Vector3.new(x, centre.Y + 150, z), Vector3.new(0, -400, 0), rp)
			local y = hit and hit.Position.Y or centre.Y

			-- an invisible stand-in marker -- buildGeyser takes a BasePart and reads its
			-- position, so it can't tell the difference from a real placement block.
			local m = Instance.new("Part")
			m.Name = "Geyser" .. i
			m.Size = Vector3.new(2, 2, 2)
			m.CFrame = CFrame.new(x, y, z)
			m.Anchored = true; m.CanCollide = false; m.CanQuery = false; m.CanTouch = false
			m.Transparency = 1; m.CastShadow = false
			m.Parent = Workspace
			geyserParts[i] = m
			print(("[Geyser]   auto-placed Geyser%d at (%.0f, %.0f, %.0f)%s")
				:format(i, x, y, z, hit and "" or "  [no ground hit -> used ring height]"))
		end
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
			st.geysers[#st.geysers + 1] = g -- the FINALE re-erupts every one of these
			print(("[Geyser] built Geyser%d at %s"):format(i, tostring(g.ventPos)))
			local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Plug Geyser"; pp.ObjectText = "Geyser " .. i
			pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.2; pp.MaxActivationDistance = 16; pp.RequiresLineOfSight = false; pp.Parent = promptParent
			pp.Triggered:Connect(function()
				-- QUEST GATE: the AshWarden has to hand the job over first.
				--
				-- The prompt stays ENABLED while locked, unlike the island2 egg's. That is
				-- deliberate: a disabled prompt just vanishes, and a player standing at an
				-- erupting geyser with no "E" has no idea whether it is locked or broken.
				-- Letting the press through and answering it is the only way to say WHY.
				if player:GetAttribute("Island11QuestAccepted") ~= true then
					floatText(g.ventPos + Vector3.new(0, 3, 0),
						"Talk to the AshWarden first!", Color3.fromRGB(255, 210, 120))
					return
				end
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
	if found == 0 then
		warn("[Geyser] no Geyser1..6 parts found -> quest inactive (name parts 'Geyser1'..'Geyser6')")
		-- DIAGNOSTIC: don't leave the user guessing. Dump every instance -- ANY class --
		-- whose name mentions "geyser", so the log says exactly what exists and where.
		-- If this prints nothing, the marker blocks genuinely aren't in the place file.
		local hits = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d.Name:lower():find("geyser", 1, true) then
				hits += 1
				if hits <= 20 then
					warn(("[Geyser]   found '%s' (%s) under %s"):format(d.Name, d.ClassName, d.Parent and d.Parent:GetFullName() or "?"))
				end
			end
		end
		if hits == 0 then
			warn(("[Geyser]   NOTHING in Workspace has 'geyser' in its name. The placement blocks are missing from %s -- re-add them."):format(CONFIG.islandName))
		else
			warn(("[Geyser]   %d instance(s) mention 'geyser' (listed above). They must be a Part or Model named exactly Geyser1..Geyser6."):format(hits))
		end
		return
	end

	-- HIDE EVERY PLACEMENT BLOCK -- geyser vents AND the reward-egg spot.
	--
	-- buildGeyser() already ghosts the marker it builds on, but only the ones it USED.
	-- Leftovers / duplicates (old blocks on island8, spares lying around) would stay
	-- visible as floating boxes. Sweep all of Workspace and ghost every marker.
	--
	-- The EGG marker is matched by SUBSTRING ("eggspot"), not by the exact name
	-- "EggSpot8" -- island11 inherited island8's naming, so the block may be called
	-- EggSpot8 / EggSpot11 / EggSpot / eggspot_1. Any of them now gets hidden.
	--
	-- Ghosting only changes Transparency/CanCollide/CanQuery/CanTouch -- positions are
	-- untouched, so the built geysers and the egg spawn point are unaffected.
	do
		local exact = {}
		for i = 1, CONFIG.count do exact["geyser" .. i] = true end
		local hidden = 0
		local function ghost(p)
			pcall(function()
				p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			end)
			hidden += 1
		end
		for _, d in ipairs(Workspace:GetDescendants()) do
			local key = d.Name:lower():gsub("[^%w]", "")
			-- exact geyser name, OR anything that looks like an egg-spot marker
			if exact[key] or key:find("eggspot", 1, true) then
				if d:IsA("BasePart") then
					ghost(d)
				elseif d:IsA("Model") then
					for _, p in ipairs(d:GetDescendants()) do
						if p:IsA("BasePart") then ghost(p) end
					end
				end
			end
		end
		print(("[Geyser] ghosted %d placement-block part(s) (Geyser1..%d + any *EggSpot*)"):format(hidden, CONFIG.count))
	end

	--------------------------------------------------------------------
	-- THE NEST goes up NOW, empty, and waits for the egg.
	--------------------------------------------------------------------
	-- AFTER the marker sweep above, deliberately: that sweep ghosts anything named
	-- *EggSpot*, so building first would just make the nest invisible. It also sets the
	-- marker's CanQuery false, which is what lets the ground ray below fall THROUGH the
	-- placement block and hit the island instead of landing on top of the marker.
	do
		local spot = findEggSpot()
		if spot then
			ghostMarker(spot)
			local p = (spot:IsA("BasePart") and spot.Position) or spot:GetPivot().Position

			-- SIT IT ON THE GROUND. The marker is a block whose centre floats half its own
			-- height up, and it may have been dragged loose in Studio. Ray down for the real
			-- surface -- but only trust a hit that broadly agrees with the marker, the same
			-- clamp the island NPCs use: if the island mesh is not query-able the ray punches
			-- straight through and would bury the nest a few hundred studs below the summit.
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character, spot }
			local hit = Workspace:Raycast(p + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), rp)
			if hit and math.abs(hit.Position.Y - p.Y) <= 25 then
				p = Vector3.new(p.X, hit.Position.Y, p.Z)
			elseif hit then
				warn(("[Geyser] nest ground ray landed %.0f studs off the marker -> standing the nest AT the marker instead")
					:format(hit.Position.Y - p.Y))
			end

			st.nestPos = p
			buildNest(p)
			print(("[Geyser] nest built at the egg spot '%s' (%.0f, %.0f, %.0f) -- the egg drops in here when all %d geysers are plugged")
				:format(spot.Name, p.X, p.Y, p.Z, CONFIG.count))
		else
			warn("[Geyser] no EggSpot marker on island11 -> no nest. Name a part 'EggSpot8' on the island and the nest will build on it.")
		end
	end

	-- /done -> skip the geysers, spawn the T-Rex egg. Hatching it still runs the FULL
	-- finale (plugs blow off -> eruption -> 10s fuse -> volcano -> Candy Realm).
	DoneCommand.bind(isl, "Geyser", function() onAllPlugged() end)

	print(("[Geyser] island11 'Volcanic Vista' volcano quest ready: %d geysers erupting -- plug them all!  (/done to skip to the egg)"):format(found))
end)
