--======================================================================
-- Intro.client.luau  (LocalScript)
--======================================================================
-- THE OPENING CINEMATIC: a fast, cut-driven descent of the island tower, ending on a
-- full-screen title card.
--
-- Not one long glide -- a SHOT LIST. Each island gets a different move (punch-in, whip-by,
-- orbit, crane-down), each with its own field-of-view move, and we CUT hard between them.
-- The cuts and the FOV are what make it read as an edited trailer instead of a drone
-- flight.
--
-- NOTHING but the islands is on screen: every ScreenGui in the game is hidden for the
-- duration, plus the Roblox CoreGui. No buttons, no HUD, no chat.
--
--======================================================================
-- WHY THE CHARACTER FLIES TOO (this is the important bit)
--======================================================================
-- The place has StreamingEnabled, and Roblox streams geometry around the CHARACTER, not
-- the camera. Park the camera on Volcanic Vista while the body sits on Nesting Nook and
-- you film 19,000 studs of EMPTY SKY -- the islands aren't on this client at all.
--
-- So the intro carries the character up the tower with the camera:
--   * the body is made INVISIBLE and ANCHORED (it must not fall, or be seen),
--   * RequestStreamAroundAsync yields until each island is genuinely loaded,
--   * and the body is put back on the spawn at the end -- ALWAYS, even on skip or error.
--
-- The server guards the side effect: PetXPHooks skips its island/XP tick while the
-- "IntroPlaying" attribute is set, or this joyride would set HighestIsland = 11 and hand
-- a brand new player the entire progression bar before they'd moved.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local IntroPlay = ReplicatedStorage:WaitForChild("IntroPlay", 30)
local IntroDone = ReplicatedStorage:WaitForChild("IntroDone", 30)
if not (IntroPlay and IntroDone) then
	warn("[Intro] remotes missing -> intro disabled")
	return
end

--======================================================================
-- THE SHOT LIST. Fast. Varied. Cut, don't glide.
--======================================================================
-- fov0/fov1 = the camera's field of view across the shot. Widening on a whip-by and
-- narrowing on a punch-in is a cheap, very effective way to sell speed and weight.
local SHOTS = {
	{ island = 11, move = "punch", t = 1.8, fov0 = 95, fov1 = 55, label = "VOLCANIC VISTA"   },
	{ island = 8,  move = "whip",  t = 1.0, fov0 = 90, fov1 = 95, label = "INFERNO ISLE"     },
	{ island = 7,  move = "orbit", t = 1.4, fov0 = 70, fov1 = 62, label = "RAPTOR RIDGE"     },
	{ island = 5,  move = "whip",  t = 1.0, fov0 = 92, fov1 = 98, label = "MISTY MIRE"       },
	{ island = 3,  move = "orbit", t = 1.3, fov0 = 72, fov1 = 60, label = "FOSSIL FRONTIER"  },
	{ island = 1,  move = "crane", t = 2.4, fov0 = 80, fov1 = 70, label = "NESTING NOOK"     },
}

local DEFAULT_FOV = 70

local st = {
	running  = false,
	skipped  = false,
	homeCF   = nil,   -- where the character started (restored no matter what)
	hidden   = {},    -- [BasePart|Decal] = original Transparency
	guis     = {},    -- [ScreenGui] = original Enabled
	world    = {},    -- [BillboardGui] = original Enabled (world-anchored UI: counters, nametags, markers)
	worldConn = nil,  -- Workspace.DescendantAdded watcher: billboards born DURING the cinematic
	pguiConn = nil,   -- PlayerGui.DescendantAdded watcher: mid-intro ScreenGuis + PlayerGui-parented billboards
	enforce  = nil,   -- RenderStepped loop that re-asserts the hide against per-frame Enabled writers
	exclude  = nil,   -- the cinema's own ScreenGui (the ONE gui allowed to stay up)
	prompts  = nil,   -- ProximityPromptService.Enabled before we turned it off
	fx       = {},    -- Lighting post-process effects we added (removed on restore)
	shake    = 0,     -- current impact-shake amplitude (decays every frame)
	blur     = nil,   -- BlurEffect, punched on every cut
}

--======================================================================
-- CINEMATIC GRADE: post-processing, added to Lighting for the intro only.
--======================================================================
-- The single biggest visual upgrade available for nearly free. Punching contrast and
-- saturation, blooming the highlights, and adding a shallow blur makes the same geometry
-- read as a trailer instead of a gameplay screenshot.
--
-- All of it is torn down in restore(), including on skip and on error -- leaving a
-- ColorCorrection clamped over someone's whole session would be a nasty thing to ship.
local function addGrade()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "IntroGrade"
	cc.Brightness = 0.03
	cc.Contrast = 0.22       -- crunchier blacks
	cc.Saturation = 0.20     -- richer greens/ambers
	cc.TintColor = Color3.fromRGB(255, 246, 232) -- a hair warm
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "IntroBloom"
	bloom.Intensity = 0.9
	bloom.Size = 28
	bloom.Threshold = 0.85   -- only the sky + lava actually bloom
	bloom.Parent = Lighting

	local blur = Instance.new("BlurEffect")
	blur.Name = "IntroBlur"
	blur.Size = 0            -- punched up on each cut, decays back to 0
	blur.Parent = Lighting

	st.fx = { cc, bloom, blur }
	st.blur = blur
end

local function removeGrade()
	for _, e in ipairs(st.fx) do
		pcall(function() e:Destroy() end)
	end
	st.fx = {}
	st.blur = nil
end

--======================================================================
-- AUDIO
--======================================================================
-- ⚠ SWAP THESE FOR YOUR OWN IDs IF YOU HAVE THEM -- this table is the only place to edit.
--
-- Every id below is one ALREADY USED AND WORKING elsewhere in this game, not a guess.
-- That matters: the previous version of this file used 1837709104, and your own output
-- log shows that exact asset failing --
--     Failed to load sound rbxassetid://1837709104: Asset type does not match requested type
-- Guessing sound ids gets you silence you don't find out about until launch.
--
-- Each cue is a LIST. If the first id fails to load we fall through to the next, so one
-- dead asset can't silence a whole cue.
-- WHICH IDS ACTUALLY WORK IN THIS PLACE (from your own output log):
--   * LONG ids (12-15 digits) PLAY  -- 126450028713974, 92880640988467, the fart sounds
--   * 10-digit "9xxxxxxxxx" ids are DEAD -- 9114402399, 9116367700, 9125402735 all fail
--     with "Asset type does not match requested type", including inside IceAgeUI and
--     GeyserQuest, where they were already silently broken before I got here.
-- So nothing in the 9xxxxxxxxx range is used below.
local SFX = {
	-- ⭐ THE SIGNATURE HIT (your id). Used exactly TWICE, deliberately:
	--      1. the opening slam onto Volcanic Vista
	--      2. the title card landing
	-- Bookending the piece with the same sound is what makes it feel composed. Firing it
	-- on all six cuts would burn it out by the third one -- the ear stops hearing a sound
	-- it's heard five times, and then the title has nothing left to land on.
	hit   = { "128842283247970" },

	-- the small ticks under the MIDDLE cuts. Quiet on purpose: they're punctuation, and
	-- keeping them low is what leaves room for the signature hit to feel big.
	cut   = { "126450028713974" },

	-- layered under the title for body (QuestGate/FishingQuest play this as their fanfare)
	boom  = { "92880640988467", "112825313814792" },

	-- ⚠ EMPTY ON PURPOSE. There is NO working ambience/wind asset anywhere in this
	-- project -- the one IceAgeUI uses (9114402399) is one of the dead 9xxxxxxxxx ids.
	-- Paste a wind/drone id here and the intro gains its best layer: a bed that rises in
	-- volume and drops in pitch as you fall, gluing six hard cuts into one piece.
	bed   = {},
}

local loaded: { [string]: boolean } = {}

-- Preload up front so the FIRST cut isn't silent while the asset streams in.
local function preloadSfx()
	local probes = {}
	for _, ids in pairs(SFX) do
		for _, id in ipairs(ids) do
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			s.Parent = SoundService
			probes[#probes + 1] = s
		end
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(probes)
	end)
	for _, s in ipairs(probes) do
		local id = s.SoundId:match("(%d+)")
		if id then loaded[id] = s.IsLoaded end
		s:Destroy()
	end
end

-- Play the first id in a cue that actually loaded. Never errors; warns once if a whole
-- cue is dead, so a silent intro is diagnosable instead of mysterious.
local function sfx(cue: string, vol: number, speed: number?)
	local ids = SFX[cue]
	if not ids then return nil end
	for _, id in ipairs(ids) do
		if loaded[id] ~= false then -- unknown (not preloaded yet) is worth a try
			local ok, snd = pcall(function()
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. id
				s.Volume = vol
				s.PlaybackSpeed = speed or 1
				s.Parent = SoundService
				s:Play()
				game:GetService("Debris"):AddItem(s, 8)
				return s
			end)
			if ok and snd then return snd end
		end
	end
	warn(("[Intro] sound cue '%s' has no loadable asset -- playing silent. Put a working id in SFX.%s")
		:format(cue, cue))
	return nil
end

-- The ambient bed: a wind loop that RISES through the descent. Starts thin and distant on
-- the volcano, thickens and drops in pitch as you fall toward the ground. This is what
-- glues six hard cuts into one continuous piece instead of six disconnected clips.
local function startBed(totalTime: number)
	local ids = SFX.bed
	if #ids == 0 then
		print("[Intro] no ambience id configured (SFX.bed is empty) -> playing without the wind bed")
		return function() end
	end
	local s
	for _, id in ipairs(ids) do
		if loaded[id] ~= false then
			local ok, snd = pcall(function()
				local x = Instance.new("Sound")
				x.SoundId = "rbxassetid://" .. id
				x.Looped = true
				x.Volume = 0
				x.PlaybackSpeed = 1.35 -- thin + high up on the summit
				x.Parent = SoundService
				x:Play()
				return x
			end)
			if ok and snd then s = snd; break end
		end
	end
	if not s then return function() end end

	task.spawn(function()
		local t0 = os.clock()
		while s.Parent and not st.skipped do
			local a = math.clamp((os.clock() - t0) / totalTime, 0, 1)
			s.Volume = 0.15 + 0.45 * a          -- swells as you descend
			s.PlaybackSpeed = 1.35 - 0.55 * a   -- drops in pitch = falling
			RunService.RenderStepped:Wait()
		end
	end)

	-- returns a stopper that fades it out rather than cutting it dead
	return function()
		pcall(function()
			TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
			game:GetService("Debris"):AddItem(s, 1.5)
		end)
	end
end

--======================================================================
-- helpers
--======================================================================

local function hrp(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Hide the player's own body -- the camera flies right past it.
local function setBodyHidden(hide: boolean)
	local char = player.Character
	if not char then return end
	if hide then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				st.hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	else
		for d, t in pairs(st.hidden) do
			if d.Parent then pcall(function() d.Transparency = t end) end
		end
		st.hidden = {}
	end
end

local function freezeBody(freeze: boolean)
	local h = hrp()
	if h then h.Anchored = freeze end -- an unanchored body 19,000 studs up simply falls
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = freeze and 0 or 16
		hum.JumpPower = freeze and 0 or 50
	end
end

-- HIDE THE WORLD'S OWN UI TOO. ScreenGuis live in PlayerGui, but a BillboardGui is
-- anchored to a PART -- it is not in PlayerGui and the sweep below never touched it. So
-- the cinematic flew past quest counters, NPC nametags, objective markers and egg/prompt
-- labels floating over the islands. Same principle as the ScreenGui sweep: hide the CLASS,
-- never a hand-written list of names, so it can't rot when a new billboard is added.
--
-- Two things make this more than a one-shot sweep:
--   * StreamingEnabled. Islands stream in WHILE the cinematic plays and their scripts build
--     billboards on arrival (the mosquito counter appears ~8s in, mid-intro). A single pass
--     at the start would miss every one of those -- hence the DescendantAdded watcher.
--   * ProximityPrompts render their own world-space label. The body is frozen so nothing can
--     be interacted with anyway; disabling the service is the only way to keep their labels
--     off screen.
-- SurfaceGuis are deliberately left alone: those are painted onto the scenery (signs,
-- screens) and read as part of the world, not as UI over it.
local function setWorldUiHidden(hide: boolean)
	if hide then
		if st.worldConn then return end -- already hidden
		local pgui = player:FindFirstChildOfClass("PlayerGui")
		-- the cinema's gui is the ONE gui allowed to stay up. st.exclude is set by
		-- setAllGuis once it exists; the name check covers the window before that.
		local function isCinema(inst: Instance)
			if inst.Name == "IntroCinema" or inst.Name == "IntroTitle" then return true end -- IntroTitle: the end card is born mid-cinematic too, and this watcher was hiding it the instant it appeared
			return st.exclude ~= nil and (inst == st.exclude or inst:IsDescendantOf(st.exclude))
		end
		local function grab(d: Instance)
			if isCinema(d) then return end
			if d:IsA("BillboardGui") then
				-- wherever it lives: parts in Workspace, OR PlayerGui with an Adornee --
				-- NPCWaypointArrow parents its arrow to PlayerGui, which a Workspace-only
				-- sweep walked straight past.
				if st.world[d] == nil then st.world[d] = d.Enabled; d.Enabled = false end
			elseif d:IsA("ScreenGui") then
				-- ScreenGuis born DURING the cinematic. StreamingEnabled means island quest
				-- scripts build their HUDs when their island streams in -- MosquitoHUD
				-- appears ~5s INTO the intro, so the one-shot setAllGuis sweep (which ran
				-- before it existed) never saw it.
				if st.guis[d] == nil then st.guis[d] = d.Enabled; d.Enabled = false end
			end
		end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BillboardGui") then grab(d) end
		end
		if pgui then -- PlayerGui-parented billboards (ScreenGuis here are setAllGuis's job)
			for _, d in ipairs(pgui:GetDescendants()) do
				if d:IsA("BillboardGui") then grab(d) end
			end
		end
		-- watchers: UI born mid-cinematic, on either side
		-- (defer: a gui is usually parented before its Enabled/adornee are set)
		st.worldConn = Workspace.DescendantAdded:Connect(function(d)
			task.defer(function() if d.Parent then pcall(grab, d) end end)
		end)
		if pgui then
			st.pguiConn = pgui.DescendantAdded:Connect(function(d)
				task.defer(function() if d.Parent then pcall(grab, d) end end)
			end)
		end
		pcall(function()
			st.prompts = ProximityPromptService.Enabled
			ProximityPromptService.Enabled = false
		end)

		-- RE-ASSERT THE HIDE EVERY FRAME. Setting Enabled once is not enough: several
		-- scripts DRIVE Enabled from their own loops and simply set it back -- e.g.
		-- NPCWaypointArrow:176 rewrites its arrow's Enabled on every Heartbeat, and the
		-- Mosquito/Geyser HUDs re-enable themselves on a 0.5s island-proximity loop.
		-- Chasing each writer with an `if _G.introPlaying` guard would mean editing every
		-- script that ever drives a GUI and would rot the moment someone adds another.
		--
		-- RenderStepped is the fix: it is the LAST thing to run before the frame is drawn,
		-- so whatever those loops set earlier in the frame is overwritten before any of it
		-- reaches the screen.
		st.enforce = RunService.RenderStepped:Connect(function()
			for d in pairs(st.world) do
				if d.Parent and d.Enabled then d.Enabled = false end
			end
			for g in pairs(st.guis) do
				if g.Parent and g.Enabled and not isCinema(g) then g.Enabled = false end
			end
		end)
	else
		-- Kill the enforcer FIRST -- restoring while it still runs would just re-hide.
		if st.enforce then st.enforce:Disconnect(); st.enforce = nil end
		if st.worldConn then st.worldConn:Disconnect(); st.worldConn = nil end
		if st.pguiConn then st.pguiConn:Disconnect(); st.pguiConn = nil end
		for d, wasEnabled in pairs(st.world) do
			if d.Parent then pcall(function() d.Enabled = wasEnabled end) end
		end
		st.world = {}
		if st.prompts ~= nil then
			pcall(function() ProximityPromptService.Enabled = st.prompts end)
			st.prompts = nil
		end
	end
end

-- HIDE EVERYTHING. Every ScreenGui in the game, not a hand-written list of names.
-- (The old version listed names and got one WRONG -- the HUD is "BottomStackGui", not
-- "BottomHUDGui" -- so the fart button sat on screen through the whole cinematic. A
-- generic sweep can't rot when a GUI is renamed or a new one is added.)
local function setAllGuis(on: boolean, exclude: ScreenGui?)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, on) end)
	if not on then st.exclude = exclude end -- tell the watchers/enforcer which gui is the cinema's
	-- FIRST, both directions. Hiding: the world sweep must not be gated behind the
	-- PlayerGui check below (it doesn't need PlayerGui, and the early return was skipping
	-- it entirely). Restoring: this stops the enforcer before the loop below puts the
	-- ScreenGuis back, so it can't immediately re-hide them.
	setWorldUiHidden(not on)
	if on then st.exclude = nil end
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return end

	if not on then
		for _, g in ipairs(pgui:GetDescendants()) do
			if g:IsA("ScreenGui") and g ~= exclude then
				st.guis[g] = g.Enabled
				g.Enabled = false
			end
		end
	else
		for g, wasEnabled in pairs(st.guis) do
			if g.Parent then pcall(function() g.Enabled = wasEnabled end) end
		end
		st.guis = {}
	end
end

local function islandInfo(n: number)
	local isl = Workspace:FindFirstChild("island" .. n)
	if not isl then return nil end
	local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
	if not (ok and cf and size) then return nil end
	return cf.Position, size
end

-- MOVE THE BODY to an island and WAIT for it to stream in. This is the only reason the
-- islands exist on this client at all.
local function travelTo(n: number)
	local pos, size = islandInfo(n)
	if not pos then return nil, nil end

	local h = hrp()
	if h then
		h.CFrame = CFrame.new(pos + Vector3.new(0, (size and size.Y / 2 or 50) + 20, 0))
	end

	local done = false
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(pos) end)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 3 do task.wait() end

	-- re-read: the bbox was probably (0,0,0) before the parts arrived
	local pos2, size2 = islandInfo(n)
	return pos2 or pos, size2 or size
end

--======================================================================
-- the shots
--======================================================================
--======================================================================
-- HANDHELD + IMPACT SHAKE
--======================================================================
-- A camera on a perfect mathematical path looks like a CAD render. A little continuous
-- drift (as if a human were holding it) plus a sharp decaying jolt on each cut is what
-- makes it feel shot rather than computed.
--
-- Applied as an OFFSET to the composed CFrame, so it never fights the shot's own motion.
local function handheld(cf: CFrame, a: number): CFrame
	local t = os.clock()
	-- slow, low-amplitude drift -- two out-of-phase sines so it never visibly loops
	local dx = math.sin(t * 1.7) * 0.35 + math.sin(t * 0.6) * 0.20
	local dy = math.cos(t * 1.3) * 0.28 + math.sin(t * 0.9) * 0.15
	local roll = math.sin(t * 0.8) * math.rad(0.5)

	-- impact shake: sharp, random, decays fast
	local s = st.shake
	if s > 0.01 then
		dx += (math.random() - 0.5) * s * 3.0
		dy += (math.random() - 0.5) * s * 3.0
		roll += (math.random() - 0.5) * s * math.rad(2.5)
		st.shake = s * 0.86 -- decay
	else
		st.shake = 0
	end

	return cf * CFrame.new(dx, dy, 0) * CFrame.Angles(0, 0, roll)
end

local function playShot(shot, cinema)
	local pos, size = travelTo(shot.island)
	if not pos or st.skipped then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local r = math.max(90, (size and math.max(size.X, size.Z) or 200) * 0.75)
	cinema.setLabel(shot.label)

	local t0 = os.clock()
	local last = t0
	local function frame(): number?
		if st.skipped then return nil end
		local now = os.clock()
		local dt = now - last
		last = now
		local a = (now - t0) / shot.t
		if a >= 1 then return nil end
		cam.FieldOfView = shot.fov0 + (shot.fov1 - shot.fov0) * a
		-- the cut's blur punch decays away across the opening beat of every shot.
		-- NOTE: dt from the clock, NOT RenderStepped:Wait() -- the shot loops already
		-- wait once per frame, and waiting again in here would halve their framerate.
		if st.blur and st.blur.Size > 0 then
			st.blur.Size = math.max(0, st.blur.Size - 90 * dt)
		end
		return a
	end

	if shot.move == "punch" then
		local ang = math.rad(35)
		local from = pos + Vector3.new(math.cos(ang) * r * 2.2, r * 1.2, math.sin(ang) * r * 2.2)
		local to   = pos + Vector3.new(math.cos(ang) * r * 0.7, r * 0.30, math.sin(ang) * r * 0.7)
		while true do
			local a = frame(); if not a then break end
			local k = TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, k), pos), a)
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "orbit" then
		local a0, sweep = math.rad(math.random(0, 360)), math.rad(80)
		while true do
			local a = frame(); if not a then break end
			local e = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local ang = a0 + sweep * e
			local p = pos + Vector3.new(math.cos(ang) * r * 1.15, r * (0.60 - 0.20 * e), math.sin(ang) * r * 1.15)
			cam.CFrame = handheld(CFrame.lookAt(p, pos), a)
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "whip" then
		local ang = math.rad(math.random(0, 360))
		local side = Vector3.new(math.cos(ang), 0, math.sin(ang)) * r * 1.8
		local from = pos + side + Vector3.new(0, r * 0.18, 0)
		local to   = pos - side + Vector3.new(0, r * 0.26, 0)
		while true do
			local a = frame(); if not a then break end
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, a), pos), a) -- linear = it really rips past
			RunService.RenderStepped:Wait()
		end

	elseif shot.move == "crane" then
		-- the landing: fall out of the sky and settle exactly where the normal camera sits
		local land = st.homeCF and st.homeCF.Position or (pos + Vector3.new(0, 10, 0))
		local look = st.homeCF and st.homeCF.LookVector or Vector3.new(0, 0, -1)
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, -1)
		local from = land + Vector3.new(0, r * 1.5, 0) - flat * r * 1.1
		local to   = land - flat * 16 + Vector3.new(0, 6, 0)
		while true do
			local a = frame(); if not a then break end
			local k = TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local focus = land + Vector3.new(0, 2 - 0.5 * k, 0)
			cam.CFrame = handheld(CFrame.lookAt(from:Lerp(to, k), focus), a)
			RunService.RenderStepped:Wait()
		end
	end
end

--======================================================================
-- CINEMA UI: island chip + skip hint + the CUT flash.
-- (No buttons, no HUD -- this is the ONLY thing on screen besides the islands.)
--
-- NO LETTERBOX. There used to be two black bars here, tweened to 11% of the screen at the top and
-- bottom. They're gone: on a phone they ate a fifth of the screen, and the shot is the point -- the
-- descent sells itself without a frame drawn around it. The chip and the skip hint still sit where
-- they did (they were anchored to the screen edges, not to the bars).
--======================================================================
local function buildCinemaUI()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "IntroCinema"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 900; g.Parent = pgui

	local chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0, 42, 1, -66)
	chip.Size = UDim2.fromOffset(460, 38)
	chip.BackgroundTransparency = 1
	chip.Font = Enum.Font.FredokaOne
	chip.TextScaled = true
	chip.TextColor3 = Color3.fromRGB(255, 255, 255)
	chip.TextStrokeColor3 = Color3.new(0, 0, 0)
	chip.TextStrokeTransparency = 0.15
	chip.TextXAlignment = Enum.TextXAlignment.Left
	chip.Text = ""
	chip.TextTransparency = 1
	chip.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = chip end

	local skip = Instance.new("TextLabel")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -42, 1, -66)
	skip.Size = UDim2.fromOffset(260, 26)
	skip.BackgroundTransparency = 1
	skip.Font = Enum.Font.GothamBold
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(215, 215, 215)
	skip.TextTransparency = 0.3
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.Text = "press any key / tap to skip"
	skip.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = skip end

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1); flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(0, 0, 0); flash.BackgroundTransparency = 1
	flash.ZIndex = 5; flash.Parent = g

	local api = {}
	function api.setLabel(text: string)
		chip.Text = text
		chip.TextTransparency = 1
		TweenService:Create(chip, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
	end
	-- THE CUT: a black snap + a blur punch + a jolt of camera shake, all on the same
	-- frame. One black frame alone reads as a glitch; the three together read as an EDIT.
	-- The blur decays away over the opening beat of the next shot (see playShot's frame()),
	-- so every cut lands like an impact instead of a fade.
	-- `n` is which cut this is (2nd shot, 3rd shot...). The pitch RISES with it, so the
	-- descent audibly builds toward the title instead of being five identical clicks.
	-- Quiet, too -- these are punctuation, not the star. The star is the signature hit.
	function api.cut(n: number)
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
		if st.blur then st.blur.Size = 22 end
		st.shake = 1.0
		local rise = 1.15 + 0.12 * (n or 1) -- each cut a semitone-ish higher
		sfx("cut", 0.32, rise)
	end
	function api.destroy() pcall(function() g:Destroy() end) end
	api.gui = g
	return api
end

--======================================================================
-- THE TITLE CARD -- same treatment as the Candy Realm card at the end of the game:
-- full-screen gradient wash, big FredokaOne title punched in over it, subtitle beneath,
-- hold, fade away. Jungle/amber palette instead of bubblegum.
--======================================================================
local function showTitleCard()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "IntroTitle"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 950; g.Parent = pgui

	-- KEEP THE CAMERA ALIVE UNDER THE CARD.
	-- The shot loops have finished, so nothing is driving cam.CFrame any more -- without
	-- this the world behind the title is a dead, frozen frame (and the title's impact
	-- shake would do literally nothing, since shake is applied inside handheld()).
	-- A slow drift + a gentle push-in keeps it breathing.
	task.spawn(function()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local base = cam.CFrame
		local t0, last = os.clock(), os.clock()
		while g.Parent and not st.skipped do
			local now = os.clock()
			local dt = now - last
			last = now
			local a = math.min(1, (now - t0) / 5)
			-- creep forward very slightly -- a static frame reads as a screenshot
			local push = base * CFrame.new(0, 0, -3 * a)
			cam.CFrame = handheld(push, a)
			-- decay the title's blur punch. The shot loops did this, but they've finished
			-- by now -- without it the blur from the title hit would just stay on screen.
			if st.blur and st.blur.Size > 0 then
				st.blur.Size = math.max(0, st.blur.Size - 40 * dt)
			end
			RunService.RenderStepped:Wait()
		end
	end)

	-- fade up from black over the last shot
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(8, 12, 8); bg.BackgroundTransparency = 1
	bg.Parent = g
	TweenService:Create(bg, TweenInfo.new(0.7), { BackgroundTransparency = 0 }):Play()
	task.wait(0.7)

	-- prehistoric gradient wash (the Candy card's move, dino palette)
	bg.BackgroundColor3 = Color3.fromRGB(255, 240, 210)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 176, 84)),  -- volcanic amber (the summit)
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(250, 226, 168)), -- warm haze
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(96, 190, 118)),  -- jungle green (the ground)
	})
	grad.Parent = bg

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.44)
	title.Size = UDim2.fromOffset(980, 120)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(88, 40, 16)
	title.TextTransparency = 1
	title.Text = "FART TO FLOAT" -- no emoji: this realm's UI fonts render them as tofu boxes
	title.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 88; c.Parent = title end
	local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(255, 255, 255); ts.Thickness = 5; ts.Parent = title

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.57)
	sub.Size = UDim2.fromOffset(700, 52)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(56, 92, 48)
	sub.TextTransparency = 1
	sub.Text = "WELCOME TO THE DINOSAUR REALM"
	sub.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 40; c.Parent = sub end
	local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(255, 255, 255); ss.Thickness = 3; ss.Parent = sub

	-- tagline, under the subtitle
	local tag = Instance.new("TextLabel")
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 0.655)
	tag.Size = UDim2.fromOffset(640, 32)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(72, 56, 40)
	tag.TextTransparency = 1
	tag.Text = "13 ISLANDS.  ONE CLIMB."
	tag.Parent = g
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = tag end

	-- PUNCH the title in (overshoot + settle) with a shake + boom, then stack the
	-- subtitle and tagline underneath.
	--======================================================================
	-- ⭐ THE TITLE LANDING -- the signature hit's second and last appearance.
	--======================================================================
	-- LAYERED, not a single copy. Three passes of the same asset at different pitches and
	-- offsets is how you make one sound feel like a wall:
	--   * a deep pass (0.72) for weight -- it's what you feel
	--   * the hit at full pitch for the attack -- it's what you hear
	--   * a bright pass a beat later for shine -- it's what makes it sparkle
	-- ...plus the hatch fanfare underneath for tail. One thin copy just goes "tick".
	title.Size = UDim2.fromOffset(1240, 152)
	sfx("hit", 1.0, 0.72)                                     -- weight
	sfx("hit", 0.75, 1.0)                                     -- attack
	sfx("boom", 0.6, 0.9)                                     -- tail / body
	task.delay(0.12, function() sfx("hit", 0.4, 1.5) end)     -- shine, a beat behind
	st.shake = 1.8          -- the card lands HARD
	if st.blur then st.blur.Size = 26 end
	TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextTransparency = 0, Size = UDim2.fromOffset(980, 120) }):Play()
	task.wait(0.28)
	TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.wait(0.22)
	TweenService:Create(tag, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()

	-- SHIMMER: a bright band swept across the title. A UIGradient's Offset animates for
	-- free and gives the logo that "polished metal / gloss" flick you see on real title
	-- cards. Applied to the STROKE so the letterforms themselves keep their solid fill.
	task.spawn(function()
		local shim = Instance.new("UIGradient")
		shim.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 248, 190)), -- the highlight band
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 255, 255)),
		})
		shim.Parent = ts
		for pass = 1, 2 do
			shim.Offset = Vector2.new(-1, 0)
			local t0 = os.clock()
			while os.clock() - t0 < 0.85 do
				local a = (os.clock() - t0) / 0.85
				shim.Offset = Vector2.new(-1 + 2 * a, 0)
				RunService.RenderStepped:Wait()
			end
			task.wait(0.5)
		end
		pcall(function() shim:Destroy() end)
	end)

	task.wait(2.4)
	TweenService:Create(tag, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()

	-- fade the whole card away to reveal the game
	TweenService:Create(title, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	TweenService:Create(sub,   TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	TweenService:Create(ts,    TweenInfo.new(0.7), { Transparency = 1 }):Play()
	TweenService:Create(ss,    TweenInfo.new(0.7), { Transparency = 1 }):Play()
	TweenService:Create(bg,    TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	task.wait(1.1)
	pcall(function() g:Destroy() end)
end

--======================================================================
-- MAIN
--======================================================================
local function restore()
	-- ALWAYS runs -- on finish, on skip, on error. A player left invisible and anchored
	-- 19,000 studs in the air is the worst possible failure here, so this cannot be
	-- allowed to be skipped by any path.
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = DEFAULT_FOV
	end
	local h = hrp()
	if h and st.homeCF then h.CFrame = st.homeCF end
	freezeBody(false)
	setBodyHidden(false)
	setAllGuis(true)
	removeGrade() -- never leave a ColorCorrection/Bloom/Blur clamped over the session
	st.shake = 0
	_G.introPlaying = false
	-- the server clears its own "IntroPlaying" attribute when it receives IntroDone
end

local function playIntro()
	if st.running then return end
	st.running = true
	st.skipped = false

	local h = hrp()
	if not h then st.running = false; return end
	st.homeCF = h.CFrame

	-- SpawnCamera (also client-side) checks this and stands down.
	-- NOTE the "IntroPlaying" ATTRIBUTE is deliberately NOT set here -- a client-set
	-- attribute does not replicate to the server, so PetXPHooks would never see it. The
	-- SERVER sets it (Intro.server.luau) before firing IntroPlay, and clears it on
	-- IntroDone. Setting it here too would just be a lie that looks like a guard.
	_G.introPlaying = true

	-- HIDE THE WORLD'S UI IMMEDIATELY -- before the cinema is even built. The full
	-- setAllGuis() sweep has to wait for cinema.gui (it needs it as the exclusion), but
	-- the world billboards and prompts have no such dependency, and they are the ones
	-- the camera flies straight past. Idempotent, so the setAllGuis call below is a
	-- no-op for this half.
	setWorldUiHidden(true)

	local cinema = buildCinemaUI()

	-- SKIP -- but not for the first moment.
	--
	-- Without the grace window the intro skipped ITSELF instantly:
	--     01:24:55.108  playing the intro
	--     01:24:56.528  [Intro] done (skipped)
	-- The listener armed before the first frame and caught the very click that focuses
	-- the game window (in Studio, the click into the viewport; in a browser, the click
	-- that gives the canvas focus). Every player would have "skipped" an intro they
	-- never saw. Arm it only once the cinematic is actually up.
	local SKIP_GRACE = 1.25
	local armAt = os.clock() + SKIP_GRACE

	local skipConn
	skipConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if os.clock() < armAt then return end
		-- only real intent: a key, a click, or a tap
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Gamepad1 then
			st.skipped = true
		end
	end)

	-- how long the descent runs, so the wind bed can ramp across exactly that
	local totalTime = 0
	for _, s in ipairs(SHOTS) do totalTime += s.t end

	local stopBed = function() end

	local ok, err = pcall(function()
		setAllGuis(false, cinema.gui) -- hide EVERY other ScreenGui + the CoreGui
		setBodyHidden(true)
		freezeBody(true)
		addGrade()                    -- contrast / saturation / bloom / blur
		preloadSfx()                  -- so the FIRST cut isn't silent while it streams
		stopBed = startBed(totalTime) -- rising wind under the whole descent

		local cam = Workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable

		for i, shot in ipairs(SHOTS) do
			if st.skipped then break end
			if i == 1 then
				-- ⭐ THE OPENING SLAM. The signature hit, full weight, landing on the
				-- volcano as the camera punches in. This is the first thing the player
				-- ever hears in the game.
				sfx("hit", 1.0, 1.0)
				st.shake = 1.6
				if st.blur then st.blur.Size = 30 end
			else
				cinema.cut(i - 1) -- HARD CUT between beats, pitch rising each time
			end
			playShot(shot, cinema)
		end

		if not st.skipped then
			cinema.destroy()
			showTitleCard()
		end
	end)

	if skipConn then skipConn:Disconnect() end
	pcall(stopBed) -- fade the wind out rather than cutting it dead
	cinema.destroy()
	restore()

	if not ok then
		warn("[Intro] cinematic errored (player restored safely): " .. tostring(err))
	end

	pcall(function() IntroDone:FireServer() end)
	st.running = false
	print("[Intro] done" .. (st.skipped and " (skipped)" or ""))
end

IntroPlay.OnClientEvent:Connect(function()
	task.spawn(playIntro)
end)

print("[Intro] client ready -- waiting for the first-join cinematic")
