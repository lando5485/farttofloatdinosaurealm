--======================================================================
-- MonsoonRain.client.luau  (LocalScript)
--======================================================================
-- Client presentation for the Monsoon Rain event (server driver:
-- Monsoon.server.luau). Listens to the MonsoonSync RemoteEvent and applies:
--   * Heavy rain            -> a camera-tracked rain particle volume.
--   * Reduced visibility    -> tightened, gray-blue fog.
--   * Light mist over islands -> a soft Atmosphere haze + fog color.
--   * Wet conditions (-10% flight) -> sets _G.flightDistanceMultiplier, which
--     BottomHUD.client.luau multiplies the fart-flight ascent speed by.
-- Everything is fully restored on "reset" (Lighting snapshot, rain removed,
-- flight multiplier cleared, banner freed).
--======================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sync = ReplicatedStorage:WaitForChild("MonsoonSync")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "MonsoonUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

--======================================================================
-- Banner (shares the cross-event slot table so it stacks under any Ice Age
-- banner instead of covering it).
--======================================================================
local banner = Instance.new("TextLabel")
banner.Size = UDim2.new(0.44, 0, 0.08, 0)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.BackgroundColor3 = Color3.fromRGB(30, 45, 65)
banner.BackgroundTransparency = 0.15
banner.TextColor3 = Color3.fromRGB(220, 235, 255)
banner.Font = Enum.Font.GothamBold
banner.TextScaled = true
banner.Text = ""
banner.Visible = false
banner.Parent = gui
local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = banner

_G.__eventBannerSlots = _G.__eventBannerSlots or {}
local BANNER_BASE_Y, BANNER_SLOT_H = 0.05, 0.10
local bannerSlot = nil
local function claimBannerSlot()
	if bannerSlot then return bannerSlot end
	local slots = _G.__eventBannerSlots
	local i = 1
	while slots[i] do i = i + 1 end
	slots[i] = true; bannerSlot = i
	return i
end
local function freeBannerSlot()
	if bannerSlot then _G.__eventBannerSlots[bannerSlot] = nil; bannerSlot = nil end
end
local function hideBanner()
	banner.Visible = false; banner.Text = ""
	freeBannerSlot()
end
local function showBanner(text, duration)
	if not text then return end
	local slot = claimBannerSlot()
	banner.Position = UDim2.new(0.5, 0, BANNER_BASE_Y + (slot - 1) * BANNER_SLOT_H, 0)
	banner.Text = text
	banner.Visible = true
	if duration then
		task.delay(duration, function() if banner.Text == text then hideBanner() end end)
	end
end

--======================================================================
-- Lighting snapshot / fog + mist.
--======================================================================
local saved = nil
local monsoonAtmos = nil
local function snapshot()
	if saved then return end
	saved = {
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
end

local function applyWeather(payload)
	snapshot()
	local c = payload.fogColor or { 150, 165, 180 }
	local fogColor = Color3.fromRGB(c[1], c[2], c[3])

	-- Light mist over the islands: a soft atmospheric haze.
	if not monsoonAtmos then
		monsoonAtmos = Lighting:FindFirstChild("MonsoonAtmosphere")
		if not monsoonAtmos then
			monsoonAtmos = Instance.new("Atmosphere")
			monsoonAtmos.Name = "MonsoonAtmosphere"
			monsoonAtmos.Parent = Lighting
		end
	end
	TweenService:Create(monsoonAtmos, TweenInfo.new(3), {
		Density = 0.35, Haze = 2.4, Glare = 0,
		Color = Color3.fromRGB(180, 195, 210),
		Decay = Color3.fromRGB(120, 135, 150),
	}):Play()

	-- Reduced visibility + rain-gray sky.
	TweenService:Create(Lighting, TweenInfo.new(3), {
		FogColor = fogColor,
		FogEnd = payload.fogEnd or 900,
		FogStart = payload.fogStart or 40,
		Brightness = math.max(1, (saved.Brightness or 2) * 0.75),
		OutdoorAmbient = Color3.fromRGB(120, 135, 150),
	}):Play()
end

local function restoreWeather()
	if saved then
		TweenService:Create(Lighting, TweenInfo.new(3), {
			FogColor = saved.FogColor,
			FogEnd = saved.FogEnd,
			FogStart = saved.FogStart,
			Brightness = saved.Brightness,
			OutdoorAmbient = saved.OutdoorAmbient,
		}):Play()
	end
	if monsoonAtmos then
		local a = monsoonAtmos; monsoonAtmos = nil
		local t = TweenService:Create(a, TweenInfo.new(2.5), { Density = 0, Haze = 0 })
		t:Play(); t.Completed:Connect(function() a:Destroy() end)
	end
end

-- (The earlier procedural "close-camera" rain layers were removed on request, so
-- only the generated Heavy Rain below shows -- makes it obvious whether it works.)

--======================================================================
-- "Heavy Rain" object -- an effect the game already has (placed in Studio, so
-- it is NOT in the source; we find it at runtime by name). We take its
-- ParticleEmitter(s), mount them on a huge sheet parented to the camera, and
-- keep that sheet centered above the player every frame -- so the rain spans the
-- whole width of the island AND follows you up/down the entire tower (it never
-- runs out of coverage = "infinite"). Restored/removed on reset.
--======================================================================
local HEAVY_RAIN_SPAN = 340  -- studs wide -- covers the whole island footprint (+margin)

-- Normalize a name so "Heavy Rain" / "heavy_rain" / "HeavyRain" all match.
local function normName(s) return (s:lower():gsub("[%s_%-]", "")) end

-- Search the places a Studio-placed effect could live for something named
-- "heavy rain". Returns the instance (emitter, part, model, or folder) or nil.
local function findHeavyRainSource()
	for _, root in ipairs({ workspace, Lighting, ReplicatedStorage }) do
		if normName(root.Name) == "heavyrain" then return root end
		for _, inst in ipairs(root:GetDescendants()) do
			if normName(inst.Name) == "heavyrain" then return inst end
		end
	end
	return nil
end

-- The in-game "heavy rain" object turned out to be an EMPTY Model (no particles,
-- no parts, bbox 0x0x0), so there is nothing inside it to switch on. Instead we
-- BUILD the Heavy Rain here: a dense, island-spanning downpour on a sheet that
-- follows the player, so it covers the whole width of the island and keeps
-- covering you all the way up/down the tower ("infinite").
local function buildHeavyLayer(part, name, rate, dropSize, trans, speedMin, speedMax, squash, light)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(0.45, 0.7)           -- short-lived = short droplets, not long lines
	pe.Speed = NumberRange.new(speedMin, speedMax)
	pe.Acceleration = Vector3.new(10, -90, 0)          -- gravity + slight wind slant (gentler)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Rotation = NumberRange.new(6, 12)
	pe.Squash = NumberSequence.new(squash)             -- long rain streaks
	pe.Size = NumberSequence.new(dropSize)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, trans),
		NumberSequenceKeypoint.new(0.85, trans),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.LightEmission = light
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 218, 242))
	pe.Parent = part
end

local heavyObj = nil
local heavyConn = nil
local function startHeavyRain()
	if heavyObj then return end
	-- Informational: note the empty placed object if it exists.
	local src = findHeavyRainSource()
	if src then
		print("[Monsoon] note: in-game 'heavy rain' object is empty (" .. src:GetFullName()
			.. ") -> generating the effect instead.")
	end

	-- Wide invisible sheet held high above the player, spanning the whole island.
	local part = Instance.new("Part")
	part.Name = "MonsoonHeavyRain"
	part.Size = Vector3.new(HEAVY_RAIN_SPAN, 8, HEAVY_RAIN_SPAN)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Parent = workspace.CurrentCamera or workspace

	-- Two dense layers = a proper island-wide downpour. Short droplets (not
	-- full-screen streaks): low Squash + low Speed + short Lifetime so each
	-- drop reads as a small falling droplet. Rate kept high for density.
	buildHeavyLayer(part, "HeavyFar",  48000, 0.55, 0.00, 70, 100, 2.2, 0.6)
	buildHeavyLayer(part, "HeavyNear", 24000, 0.95, 0.00, 85, 120, 2.8, 0.85)

	heavyObj = part
	heavyConn = RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam and heavyObj then
			-- Kept just overhead so the short-lived droplets fall through the
			-- player's view. Short drops die fast, so if the sheet sits too high
			-- they vanish before reaching you and "nothing comes down".
			heavyObj.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
		end
	end)
	print("[Monsoon] Heavy Rain generated -- island-wide downpour (" .. HEAVY_RAIN_SPAN
		.. " studs) following the player.")
	print("RAIN LOOK FIXED")
end

local function stopHeavyRain()
	if heavyConn then heavyConn:Disconnect(); heavyConn = nil end
	if heavyObj then
		for _, pe in ipairs(heavyObj:GetChildren()) do
			if pe:IsA("ParticleEmitter") then pe.Enabled = false end
		end
		local p = heavyObj; heavyObj = nil
		task.delay(2.5, function() if p then p:Destroy() end end)
	end
end

--======================================================================
-- Flooding: a rising layer of water pools on top of some islands during the
-- storm, then drains away on reset. (Client-side visual, like the rest of the
-- event.)
--======================================================================
-- Modeled on the Ice Age snow cap (IceVFX.makeSnowDisc): a thin round Cylinder
-- laid FLAT and flush on the island's top surface, faded in. Water-styled and a
-- bit smaller than the snow so it reads as a shallow flooded layer.
local FLOOD_ISLANDS  = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } -- every island pools standing water
local FLOOD_SPAN     = 0.95                -- disc diameter as a fraction of the island footprint (covers most of it)
local FLOOD_THICK    = 0.8                 -- disc thickness (a deeper standing pool)
local FLOOD_Y_OFFSET = 1.5                 -- studs above the surface so it clearly sits on top (no burial/z-fight)
local floodFolder = nil

-- Find the island's top walking surface Y (a few downward rays; take the highest hit).
local function islandSurfaceY(isl, cf, size)
	local cx, cz = cf.Position.X, cf.Position.Z
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { isl }
	params.IgnoreWater = true
	local fromY = cf.Position.Y + size.Y / 2 + 20
	local best = nil
	local offs = {
		Vector2.new(0, 0), Vector2.new(size.X * 0.2, 0), Vector2.new(-size.X * 0.2, 0),
		Vector2.new(0, size.Z * 0.2), Vector2.new(0, -size.Z * 0.2),
	}
	for _, o in ipairs(offs) do
		local hit = workspace:Raycast(Vector3.new(cx + o.X, fromY, cz + o.Y), Vector3.new(0, -(size.Y + 80), 0), params)
		if hit and (not best or hit.Position.Y > best) then best = hit.Position.Y end
	end
	-- Fallback: the TOP of the bounding box (never the center -- centering would
	-- bury the disc inside the island where it can't be seen).
	return best or (cf.Position.Y + size.Y / 2)
end

local function startFlood()
	if floodFolder then return end
	floodFolder = Instance.new("Folder")
	floodFolder.Name = "MonsoonFlood"
	floodFolder.Parent = workspace

	for _, i in ipairs(FLOOD_ISLANDS) do
		local isl = workspace:FindFirstChild("island" .. i)
		if isl and isl:IsA("Model") then
			local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
			if ok and cf and size then
				local surfaceY = islandSurfaceY(isl, cf, size)
				local diameter = math.max(size.X, size.Z) * FLOOD_SPAN

				-- Thin water disc laid flat on the surface (same trick as the snow cap:
				-- a Cylinder rotated 90deg so its round face points up).
				local w = Instance.new("Part")
				w.Name = "Flood_island" .. i
				w.Shape = Enum.PartType.Cylinder
				w.Material = Enum.Material.Glass
				w.Color = Color3.fromRGB(45, 95, 155)
				w.Reflectance = 0.35          -- water sheen (not a full mirror)
				w.Transparency = 1 -- fade in
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.Size = Vector3.new(FLOOD_THICK, diameter, diameter)
				w.CFrame = CFrame.new(cf.Position.X, surfaceY + FLOOD_Y_OFFSET, cf.Position.Z)
					* CFrame.Angles(0, 0, math.rad(90))
				w.Parent = floodFolder
				-- Clearly visible standing water (fades in to a shallow, semi-opaque pool).
				TweenService:Create(w, TweenInfo.new(3), { Transparency = 0.12 }):Play()
				print(("[Monsoon]   flood island%d: surfaceY=%.1f diameter=%.0f"):format(i, surfaceY, diameter))
			end
		end
	end
	print("[Monsoon] flooding (water disc) on islands " .. table.concat(FLOOD_ISLANDS, ", "))
end

local function stopFlood()
	if not floodFolder then return end
	local f = floodFolder; floodFolder = nil
	-- Drain: fade the discs out, then destroy the folder.
	for _, w in ipairs(f:GetChildren()) do
		if w:IsA("BasePart") then
			TweenService:Create(w, TweenInfo.new(2.5), { Transparency = 1 }):Play()
		end
	end
	task.delay(2.7, function() if f then f:Destroy() end end)
end

--======================================================================
-- Phase handler.
--======================================================================
sync.OnClientEvent:Connect(function(phase, payload)
	payload = payload or {}
	if phase == "start" then
		showBanner(payload.text, 5)
		applyWeather(payload)
		startHeavyRain()
		startFlood() -- standing water pools in from the very start of the storm
		_G.flightDistanceMultiplier = payload.flightMultiplier or 1
	elseif phase == "main" then
		showBanner(payload.text, 6)
		applyWeather(payload)
		startHeavyRain()
		startFlood()
		_G.flightDistanceMultiplier = payload.flightMultiplier or 0.9
	elseif phase == "ending" then
		showBanner(payload.text, 5)
		applyWeather(payload)
		_G.flightDistanceMultiplier = payload.flightMultiplier or 1
	elseif phase == "reset" then
		hideBanner()
		stopHeavyRain()
		stopFlood()
		restoreWeather()
		_G.flightDistanceMultiplier = nil
	end
end)

print("[Monsoon] client ready -- listening for Monsoon Rain phases")
