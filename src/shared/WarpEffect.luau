--!nonstrict
--[[
	WarpEffect.luau   (ModuleScript)  —  the EXACT wormhole warp cinematic + sound, extracted so you can reuse it.

	This is the same ~1.9s "wormhole tunnel" transition WormholeClient plays, pulled into a standalone module so
	ANY teleport can trigger it (Dino Rift, wormhole, a shop button, etc.). 100% procedural (frames + gradients +
	strokes) — no image assets — so it looks identical on every device/place.

	WHERE IT GOES: a ModuleScript in ReplicatedStorage (or StarterPlayerScripts). It must be required by a
	LocalScript (it builds a ScreenGui in the local player's PlayerGui on first require).

	HOW TO USE (client):
	    local WarpEffect = require(path.to.WarpEffect)
	    -- when the player picks a destination / you fire the teleport:
	    WarpEffect.playSound()                 -- the warp whoosh (fire once, right as it begins)
	    WarpEffect.play(function()
	        -- This runs at the PEAK (screen fully covered) — do the actual move here so it's hidden:
	        --   RequestWarp:InvokeServer(dest)      (server teleport within the place), or
	        --   TeleportService:Teleport(placeId)   (cross-place), etc.
	    end)
	-- play() yields ~1.9s (entry ~0.4s -> tunnel ~0.9s -> [onPeak] -> arrival ~0.55s) then eases out and
	-- restores FOV/blur. It's safe to call onPeak = nil if you teleport some other way.

	SOUNDS: the 3 ids below are PLACEHOLDERS — swap in your own whoosh / warp / landing assets. All plays are
	pcall-guarded, so a missing/invalid/empty id just plays nothing (never errors, never blocks the warp).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local WarpEffect = {}

-- ===== SOUND IDS (PLACEHOLDERS — swap for your own; "" disables one) =====
local WARP_SOUND_ID = "rbxassetid://75278076068709"  -- main warp whoosh, fired the instant the warp begins
-- DISABLED: 9046575207 IS A DEAD ASSET IN THIS GAME. It threw
--     Failed to load sound rbxassetid://9046575207: Asset type does not match requested type
-- on every single warp. ArrivalCinematic.client.luau already had this written down --
-- "the two ids this file shipped with were BOTH dead in this game: 9046575207" -- and that
-- note simply never made it over here, so one file knew and the other kept using it.
--
-- "" disables a sound (see the header), which is the honest state: the tunnel plays with
-- the WARP whoosh and the landing thud, and neither of those is broken. Put a real id here
-- and it comes straight back -- nothing else needs changing.
local WHOOSH_SOUND_ID = ""     -- low whoosh rising through entry + tunnel (no working asset yet)
local LANDING_SOUND_ID = "rbxassetid://9114065998"    -- soft landing on arrival

-- ONE persistent WARP sound, reused for every teleport (NOT recreated each time). pcall-guarded so a failed
-- asset load degrades to silence.
local warpSound = Instance.new("Sound")
warpSound.Name = "WarpWhoosh"
warpSound.SoundId = WARP_SOUND_ID
warpSound.Volume = 0.5
warpSound.Parent = SoundService

-- Play the warp whoosh (call once, right as the warp fires).
function WarpEffect.playSound()
	pcall(function()
		warpSound.TimePosition = 0 -- restart cleanly so back-to-back warps each whoosh
		warpSound:Play()
	end)
end

local RING_COLORS = { Color3.fromRGB(120, 170, 255), Color3.fromRGB(170, 110, 255), Color3.fromRGB(220, 240, 255) }

-- ===== BUILD THE WARP GUI (once) =====
local warpGui = Instance.new("ScreenGui")
warpGui.Name = "WarpEffect"
warpGui.ResetOnSpawn = false
warpGui.IgnoreGuiInset = true
warpGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
warpGui.DisplayOrder = 9000
warpGui.Enabled = false
warpGui.Parent = PlayerGui

-- Deep space-blue -> purple gradient backdrop (fades in).
local warpBackdrop = Instance.new("Frame")
warpBackdrop.Size = UDim2.new(1, 0, 1, 0)
warpBackdrop.BackgroundColor3 = Color3.fromRGB(10, 8, 34)
warpBackdrop.BackgroundTransparency = 1
warpBackdrop.BorderSizePixel = 0
warpBackdrop.ZIndex = 1
warpBackdrop.Parent = warpGui
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 70, 200)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(28, 16, 56)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 55, 200)),
	})
	g.Rotation = 90
	g.Parent = warpBackdrop
end

-- The moving tunnel container (shaken on entry; holds the spokes / rings / streaks / core).
local tunnel = Instance.new("Frame")
tunnel.Size = UDim2.new(1, 0, 1, 0)
tunnel.BackgroundTransparency = 1
tunnel.ZIndex = 2
tunnel.Parent = warpGui

-- Bright white-blue CORE at the vanishing point (pulses, then flashes + bursts on arrival).
local core = Instance.new("Frame")
core.AnchorPoint = Vector2.new(0.5, 0.5)
core.Position = UDim2.new(0.5, 0, 0.5, 0)
core.Size = UDim2.new(0, 60, 0, 60)
core.BackgroundColor3 = Color3.fromRGB(215, 238, 255)
core.BackgroundTransparency = 0.1
core.BorderSizePixel = 0
core.ZIndex = 6
core.Visible = false
core.Parent = tunnel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = core
	local glow = Instance.new("UIStroke"); glow.Color = Color3.fromRGB(150, 200, 255); glow.Thickness = 16; glow.Transparency = 0.35; glow.Parent = core
end

-- Faint VIGNETTE (four edge gradients darkening the corners).
local vignette = Instance.new("Frame")
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundTransparency = 1
vignette.ZIndex = 5
vignette.Parent = warpGui
local function vignetteEdge(size, pos, anchor, rot, darkAtFar)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos; f.AnchorPoint = anchor
	f.BackgroundColor3 = Color3.fromRGB(4, 2, 16); f.BorderSizePixel = 0; f.ZIndex = 5
	f.Parent = vignette
	local g = Instance.new("UIGradient"); g.Rotation = rot
	if darkAtFar then
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	else
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	end
	g.Parent = f
end
vignetteEdge(UDim2.new(1, 0, 0.34, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 90, false)
vignetteEdge(UDim2.new(1, 0, 0.34, 0), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), 90, true)
vignetteEdge(UDim2.new(0.26, 0, 1, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 0, false)
vignetteEdge(UDim2.new(0.26, 0, 1, 0), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), 0, true)

-- Subtle chromatic-aberration fringe (cyan left edge, red right edge — faint, ramps in during the warp).
local function makeCA(color, atRight)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0.12, 0, 1, 0)
	f.AnchorPoint = Vector2.new(atRight and 1 or 0, 0)
	f.Position = UDim2.new(atRight and 1 or 0, 0, 0, 0)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = 7
	f.Parent = warpGui
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, atRight and 1 or 0),
		NumberSequenceKeypoint.new(1, atRight and 0 or 1),
	})
	g.Parent = f
	return f
end
local caLeft = makeCA(Color3.fromRGB(80, 220, 255), false)
local caRight = makeCA(Color3.fromRGB(255, 90, 120), true)

-- ARRIVAL white-bloom flash (topmost).
local flash = Instance.new("Frame")
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = Color3.fromRGB(238, 246, 255)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 9
flash.Parent = warpGui

-- PARALLAX SPOKES: many radial gradient blades at varied rotations/speeds/opacities -> rotating spiral layers.
local spokes = {} -- { frame, speed }
for i = 1, 14 do
	local spoke = Instance.new("Frame")
	spoke.AnchorPoint = Vector2.new(0.5, 0.5)
	spoke.Position = UDim2.new(0.5, 0, 0.5, 0)
	spoke.Size = UDim2.new(0, 7 + (i % 3) * 5, 1.9, 0)
	spoke.BackgroundColor3 = RING_COLORS[(i % #RING_COLORS) + 1]
	spoke.BorderSizePixel = 0
	spoke.Rotation = i * (360 / 14)
	spoke.ZIndex = 2
	spoke.Visible = false
	spoke.Parent = tunnel
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ -- bright near the centre, fading to the tips (radial motion blur)
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.45 + (i % 3) * 0.14),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = 90
	g.Parent = spoke
	spokes[i] = { frame = spoke, speed = 35 + (i % 5) * 45 } -- varied speeds -> parallax depth
end

-- Concentric RINGS rushing out past the bright vanishing point (accelerate outward -> forward-motion depth).
local function spawnRing()
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.new(0, 26, 0, 26)
	ring.BackgroundTransparency = 1
	ring.Rotation = math.random(0, 360)
	ring.ZIndex = 3
	ring.Parent = tunnel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Color = RING_COLORS[math.random(1, #RING_COLORS)]
	s.Thickness = 3 + math.random() * 4
	s.Transparency = 0.15
	s.Parent = ring
	pcall(function()
		TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 1400, 0, 1400), Rotation = ring.Rotation + 50,
		}):Play()
		TweenService:Create(s, TweenInfo.new(0.85), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(ring, 0.95)
end

-- STAR-STRETCH streaks: thin bright lines shooting radially out from the centre (motion-blur stars at warp).
local function spawnStreak()
	local streak = Instance.new("Frame")
	streak.AnchorPoint = Vector2.new(0.5, 1) -- inner end anchored at the centre; it grows/stretches outward
	streak.Position = UDim2.new(0.5, 0, 0.5, 0)
	streak.Size = UDim2.new(0, 2 + math.random() * 2, 0, 16)
	streak.BackgroundColor3 = Color3.fromRGB(225, 238, 255)
	streak.BackgroundTransparency = 0.05
	streak.BorderSizePixel = 0
	streak.Rotation = math.random(0, 360)
	streak.ZIndex = 4
	streak.Parent = tunnel
	local g = Instance.new("UIGradient") -- bright at the outer tip, fading back toward the centre
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.7, 0.5), NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = 90
	g.Parent = streak
	pcall(function()
		TweenService:Create(streak, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 2, 0, 320 + math.random() * 280),
		}):Play()
		TweenService:Create(streak, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end)
	Debris:AddItem(streak, 0.6)
end

-- Play a sound from SoundService in pcall; missing/invalid/empty ids are skipped gracefully (no error).
local function playSound(id, volume)
	if not id or id == "" then
		return nil
	end
	local s
	pcall(function()
		s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.Parent = SoundService
		s:Play()
	end)
	return s
end

-- ===== THE CINEMATIC =====
-- Play the ~1.9s wormhole warp. `onPeak` runs at the most-covered moment (do the teleport there).
function WarpEffect.play(onPeak)
	warpGui.Enabled = true
	local cam = Workspace.CurrentCamera
	local origFov = cam and cam.FieldOfView or 70
	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting

	for _, sp in ipairs(spokes) do sp.frame.Visible = true end
	core.Visible = true
	core.Size = UDim2.new(0, 56, 0, 56)
	core.BackgroundTransparency = 0.1
	flash.BackgroundTransparency = 1

	local active = true
	-- spin the parallax spokes (each at its own speed)
	local spinConn = RunService.RenderStepped:Connect(function(dt)
		for _, sp in ipairs(spokes) do
			if sp.frame and sp.frame.Parent then
				sp.frame.Rotation += dt * sp.speed
			end
		end
	end)
	-- continuous ring + star-streak spawners
	task.spawn(function()
		while active do
			spawnRing()
			task.wait(0.06)
		end
	end)
	task.spawn(function()
		while active do
			for _ = 1, 3 do spawnStreak() end
			task.wait(0.05)
		end
	end)

	-- a low whoosh rising through entry + tunnel
	local whoosh = playSound(WHOOSH_SOUND_ID, 0.0)
	if whoosh then
		pcall(function() TweenService:Create(whoosh, TweenInfo.new(1.0), { Volume = 0.7 }):Play() end)
	end

	-- ALWAYS restore (FOV / blur / GUI) even if a tween errors.
	local function teardown()
		active = false
		if spinConn then spinConn:Disconnect(); spinConn = nil end
		if cam then pcall(function() cam.FieldOfView = origFov end) end
		pcall(function() if blur then blur:Destroy(); blur = nil end end)
		for _, sp in ipairs(spokes) do sp.frame.Visible = false end
		core.Visible = false
		tunnel.Position = UDim2.new(0, 0, 0, 0)
		warpGui.Enabled = false
	end

	local ok, err = pcall(function()
		-- (1) ENTRY (~0.4s): FOV widens, backdrop + blur + chromatic fringe ramp in, slight screen shake.
		pcall(function()
			TweenService:Create(warpBackdrop, TweenInfo.new(0.4), { BackgroundTransparency = 0.02 }):Play()
			TweenService:Create(blur, TweenInfo.new(0.4), { Size = 16 }):Play()
			TweenService:Create(caLeft, TweenInfo.new(0.4), { BackgroundTransparency = 0.82 }):Play()
			TweenService:Create(caRight, TweenInfo.new(0.4), { BackgroundTransparency = 0.82 }):Play()
			if cam then
				TweenService:Create(cam, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = math.min(110, origFov + 14) }):Play()
			end
		end)
		local sh0 = os.clock()
		while os.clock() - sh0 < 0.4 do
			local m = 7 * (1 - (os.clock() - sh0) / 0.4)
			tunnel.Position = UDim2.new(0, (math.random() * 2 - 1) * m, 0, (math.random() * 2 - 1) * m)
			RunService.RenderStepped:Wait()
		end
		tunnel.Position = UDim2.new(0, 0, 0, 0)

		-- (2) TUNNEL (~0.9s): fly through — FOV stays wide, the core grows toward the viewer.
		pcall(function()
			if cam then
				TweenService:Create(cam, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { FieldOfView = math.min(115, origFov + 18) }):Play()
			end
			TweenService:Create(core, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(0, 150, 0, 150) }):Play()
		end)
		task.wait(0.9)

		-- PEAK: do the teleport while fully covered.
		if onPeak then
			pcall(onPeak)
		end

		-- (3) ARRIVAL (~0.55s): bright flash + core burst, then fade out to the destination; FOV/blur/fringe clear.
		pcall(function()
			TweenService:Create(flash, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.04 }):Play()
			TweenService:Create(core, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 1700, 0, 1700), BackgroundTransparency = 1 }):Play()
		end)
		task.wait(0.14)
		active = false -- stop spawning new rings/streaks
		if whoosh then
			pcall(function() TweenService:Create(whoosh, TweenInfo.new(0.3), { Volume = 0 }):Play() end)
			Debris:AddItem(whoosh, 0.5)
		end
		playSound(LANDING_SOUND_ID, 0.6) -- whoosh resolves into a soft landing
		pcall(function()
			TweenService:Create(flash, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(warpBackdrop, TweenInfo.new(0.34), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(blur, TweenInfo.new(0.4), { Size = 0 }):Play()
			TweenService:Create(caLeft, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(caRight, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			if cam then
				TweenService:Create(cam, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = origFov }):Play()
			end
		end)
		task.wait(0.4)
	end)
	if not ok then
		warn("[WarpEffect] warp visual error: " .. tostring(err))
	end
	teardown()
end

return WarpEffect
