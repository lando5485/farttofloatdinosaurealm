--!nonstrict
--[[
	MeteorBreak.luau   (ModuleScript)  —  the EXACT Space Realm meteor-crate break, extracted verbatim.

	This is the crate's open animation UP TO the reward — the meteor SHAKES, CRACKS, then BURSTS open with a
	flash + shard streaks + expanding rings (+ a legendary glow pulse). It does NOT build the reward card; at the
	burst it calls your `onReward(handles)` so you drop your own reward reveal onto `handles.stage`. Every colour,
	size, loop count, tween time and sound id below is copied 1:1 from CrateClient.client.luau — so it looks
	identical to the one in the Space Realm.

	WHERE IT GOES: a ModuleScript (ReplicatedStorage or StarterPlayerScripts), required by a LocalScript.

	HOW TO USE (client):
	    local MeteorBreak = require(path.to.MeteorBreak)
	    local handles = MeteorBreak.play({
	        rarityColor = Color3.fromRGB(255, 214, 92),  -- burst/shard/ring/glow tint (default GOLD)
	        isLegendary = false,                         -- true = bigger boom + more shards + legendary glow
	        onReward = function(h)
	            -- runs right after the meteor is gone (where the reward card would appear).
	            -- build your reward UI on h.stage (ZIndex >= 15), then close when done:
	            --   ... ; MeteorBreak.close()
	        end,
	    })
	-- play() yields through shake (~0.7s) -> cracks (~0.4s) -> burst (~0.5s) then fires onReward.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local MeteorBreak = {}

-- ===== PALETTE (exact) =====
local WHITE = Color3.fromRGB(245, 247, 255)
local GOLD = Color3.fromRGB(255, 214, 92)
local DEEP = Color3.fromRGB(10, 14, 32)
local METEOR_STROKE = Color3.fromRGB(255, 170, 60)
local ROCK = Color3.fromRGB(96, 86, 78)

-- ===== SHARED HELPERS (exact) =====
local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c
end
local function stroke(p, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s
end
local function textStroke(lbl, t)
	local s = Instance.new("UIStroke"); s.Color = Color3.new(0, 0, 0); s.Thickness = t or 2; s.Parent = lbl; return s
end
local function mkLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.RichText = false
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end
local function playSound(id, volume)
	if not id or id == "" then return end
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 5)
	end)
end

-- ===== FULL-SCREEN OVERLAY (built once, reused) =====
local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MeteorCrateReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200 -- on top of everything
	gui.Enabled = false
	gui.Parent = PlayerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = DEEP
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	-- Full-screen rarity glow (used for the reveal tint + Legendary screen flash).
	local rarityGlow = Instance.new("Frame")
	rarityGlow.Name = "RarityGlow"
	rarityGlow.Size = UDim2.new(1, 0, 1, 0)
	rarityGlow.BackgroundColor3 = WHITE
	rarityGlow.BackgroundTransparency = 1
	rarityGlow.BorderSizePixel = 0
	rarityGlow.ZIndex = 2
	rarityGlow.Parent = gui
	do
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		g.Rotation = 90
		g.Parent = rarityGlow
	end

	-- Arrival white flash (topmost during the burst).
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(240, 246, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 30
	flash.Parent = gui

	return {
		gui = gui,
		backdrop = backdrop,
		rarityGlow = rarityGlow,
		flash = flash,
	}
end

local overlay = buildOverlay()

-- Spawn one radial "shard" streak from the centre (reused from the wormhole burst look).
local function spawnShard(parent, color, zindex)
	local shard = Instance.new("Frame")
	shard.AnchorPoint = Vector2.new(0.5, 1)
	shard.Position = UDim2.new(0.5, 0, 0.5, 0)
	shard.Size = UDim2.new(0, 4 + math.random() * 4, 0, 14)
	shard.BackgroundColor3 = color
	shard.BackgroundTransparency = 0.05
	shard.BorderSizePixel = 0
	shard.Rotation = math.random(0, 360)
	shard.ZIndex = zindex
	shard.Parent = parent
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = 90
	g.Parent = shard
	pcall(function()
		TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 3, 0, 240 + math.random() * 260),
			BackgroundTransparency = 1,
		}):Play()
	end)
	Debris:AddItem(shard, 0.7)
end

-- Spawn an expanding ring at the centre.
local function spawnRing(parent, color, zindex)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.new(0, 40, 0, 40)
	ring.BackgroundTransparency = 1
	ring.ZIndex = zindex
	ring.Parent = parent
	corner(ring, 9999)
	local s = stroke(ring, color, 5)
	s.Transparency = 0.1
	pcall(function()
		TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 700, 0, 700),
		}):Play()
		TweenService:Create(s, TweenInfo.new(0.7), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(ring, 0.8)
end

local breakBusy = false

-- ===========================================================================
-- THE METEOR BREAK (shake -> cracks -> burst), verbatim through to the reward.
-- ===========================================================================
-- opts = { rarityColor = Color3?, isLegendary = boolean?, onReward = function(handles)? }
-- Returns the overlay handles { gui, stage, backdrop, rarityGlow, flash } for your reward reveal.
function MeteorBreak.play(opts)
	opts = opts or {}
	if breakBusy then return end
	breakBusy = true

	local rarityColor = opts.rarityColor or GOLD
	local isLegendary = opts.isLegendary == true

	local gui = overlay.gui
	local backdrop = overlay.backdrop
	local rarityGlow = overlay.rarityGlow
	local flash = overlay.flash

	-- Clear any leftover stage content from a previous open.
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.Name == "Stage" then ch:Destroy() end
	end

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.Size = UDim2.new(1, 0, 1, 0)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 5
	stage.Parent = gui

	gui.Enabled = true
	flash.BackgroundTransparency = 1
	rarityGlow.BackgroundTransparency = 1
	backdrop.BackgroundTransparency = 1
	pcall(function()
		TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.25 }):Play()
	end)

	-- ---- 1) THE METEOR (a rocky orb that shakes) ----
	local rockColor = ROCK
	local meteor = Instance.new("Frame")
	meteor.Name = "Meteor"
	meteor.AnchorPoint = Vector2.new(0.5, 0.5)
	meteor.Position = UDim2.new(0.5, 0, 0.46, 0)
	meteor.Size = UDim2.new(0, 180, 0, 180)
	meteor.BackgroundColor3 = rockColor
	meteor.BorderSizePixel = 0
	meteor.ZIndex = 10
	meteor.Parent = stage
	corner(meteor, 9999)
	local meteorStroke = stroke(meteor, METEOR_STROKE, 4)
	meteorStroke.Transparency = 0.1
	-- A few craters for texture.
	for i = 1, 5 do
		local crater = Instance.new("Frame")
		crater.AnchorPoint = Vector2.new(0.5, 0.5)
		crater.Position = UDim2.new(math.random(25, 75) / 100, 0, math.random(25, 75) / 100, 0)
		crater.Size = UDim2.new(0, math.random(16, 34), 0, math.random(16, 34))
		crater.BackgroundColor3 = Color3.fromRGB(70, 62, 56)
		crater.BorderSizePixel = 0
		crater.ZIndex = 11
		crater.Parent = meteor
		corner(crater, 9999)
	end
	-- Hot glow growing inside (the crack-to-come).
	local innerGlow = Instance.new("Frame")
	innerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	innerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerGlow.Size = UDim2.new(0, 10, 0, 10)
	innerGlow.BackgroundColor3 = Color3.fromRGB(255, 200, 120)
	innerGlow.BackgroundTransparency = 0.2
	innerGlow.BorderSizePixel = 0
	innerGlow.ZIndex = 12
	innerGlow.Parent = meteor
	corner(innerGlow, 9999)

	local titleHint = mkLabel(stage, {
		Text = "MYSTERY METEOR CRATE",
		Font = Enum.Font.FredokaOne,
		TextColor3 = GOLD,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0, 460, 0, 40),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 10,
	})
	textStroke(titleHint)
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 34; cns.Parent = titleHint end

	-- Shake: progressively bigger jitter + the inner glow swelling.
	playSound("rbxassetid://9116367700", 0.5) -- rumble (pcall-guarded; harmless if absent)
	local base = meteor.Position
	for i = 1, 16 do
		local mag = math.floor(2 + i * 0.9)
		meteor.Position = base + UDim2.fromOffset(math.random(-mag, mag), math.random(-mag, mag))
		innerGlow.Size = UDim2.new(0, 10 + i * 4, 0, 10 + i * 4)
		innerGlow.BackgroundTransparency = math.max(0, 0.2 - i * 0.01)
		task.wait(0.045)
	end
	meteor.Position = base

	-- ---- 2) CRACKS ----
	playSound("rbxassetid://199578212", 0.6) -- crack/snap
	for i = 1, 6 do
		local crack = Instance.new("Frame")
		crack.AnchorPoint = Vector2.new(0.5, 0.5)
		crack.Position = UDim2.new(0.5, 0, 0.5, 0)
		crack.Size = UDim2.new(0, 4, 0, 0)
		crack.BackgroundColor3 = Color3.fromRGB(255, 220, 140)
		crack.BorderSizePixel = 0
		crack.Rotation = (360 / 6) * i + math.random(-15, 15)
		crack.ZIndex = 12
		crack.Parent = meteor
		pcall(function()
			TweenService:Create(crack, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 4, 0, 150) }):Play()
		end)
		task.wait(0.05)
	end
	-- ---- 3) BURST ----
	-- Fire the boom ~0.3s BEFORE the visual burst so the sound (which has load latency) is already audible by
	-- the time the meteor actually blows apart -- removes the perceived sound lag.
	playSound("rbxassetid://4612378364", 0.85) -- boom (working audio id; same for legendary + normal)
	task.wait(0.3)

	-- The meteor blows apart: scale up + fade.
	pcall(function()
		TweenService:Create(meteor, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 320, 0, 320),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(meteorStroke, TweenInfo.new(0.28), { Transparency = 1 }):Play()
	end)
	-- White flash.
	flash.BackgroundTransparency = isLegendary and 0 or 0.15
	pcall(function()
		TweenService:Create(flash, TweenInfo.new(isLegendary and 0.55 or 0.35), { BackgroundTransparency = 1 }):Play()
	end)
	-- Rings + shards radiating outward.
	local shardCount = isLegendary and 46 or 24
	for _ = 1, shardCount do
		spawnShard(stage, rarityColor, 8)
	end
	spawnRing(stage, rarityColor, 7)
	if isLegendary then
		spawnRing(stage, Color3.fromRGB(255, 240, 180), 7)
		task.delay(0.12, function() spawnRing(stage, rarityColor, 7) end)
		-- Full-screen legendary glow pulse.
		rarityGlow.BackgroundColor3 = rarityColor
		pcall(function()
			rarityGlow.BackgroundTransparency = 0.35
			TweenService:Create(rarityGlow, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.78 }):Play()
		end)
	else
		rarityGlow.BackgroundColor3 = rarityColor
		pcall(function()
			rarityGlow.BackgroundTransparency = 0.7
			TweenService:Create(rarityGlow, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.86 }):Play()
		end)
	end
	task.wait(0.22)
	meteor:Destroy()
	pcall(function()
		TweenService:Create(titleHint, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
	end)

	-- ---- INTO THE REWARD ----
	-- The meteor is gone and the burst is settling — this is exactly where the Space Realm builds its reward
	-- card. Hand off so YOU build your reward on `stage` (use ZIndex >= 15 so it sits above the shards).
	breakBusy = false
	local handles = { gui = gui, stage = stage, backdrop = backdrop, rarityGlow = rarityGlow, flash = flash }
	if opts.onReward then
		pcall(opts.onReward, handles)
	end
	return handles
end

-- End the overlay (fade the backdrop, clear the stage, hide). Call when your reward flow is done.
function MeteorBreak.close()
	local gui = overlay.gui
	pcall(function()
		TweenService:Create(overlay.backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(overlay.rarityGlow, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(0.28, function()
		for _, ch in ipairs(gui:GetChildren()) do
			if ch.Name == "Stage" then ch:Destroy() end
		end
		gui.Enabled = false
	end)
end

return MeteorBreak
