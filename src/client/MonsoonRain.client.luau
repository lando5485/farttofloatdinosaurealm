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
local SoundService = game:GetService("SoundService")

local sync = ReplicatedStorage:WaitForChild("MonsoonSync")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "MonsoonUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local PlayerGui = player:WaitForChild("PlayerGui")
gui.Parent = PlayerGui

--======================================================================
-- Banner (shares the cross-event slot table so it stacks under any Ice Age
-- banner instead of covering it).
--======================================================================
-- THE STORM BANNER IS THE OBJECTIVE CARD -- same builder, same 470x78, same slot. While
-- it is up the objective card is HIDDEN and this stands in its place, so the two must be
-- identical in shape or the swap reads as a glitch.
--
-- IT KEEPS ITS OWN COLOURS, and that is deliberate. The rain banner was originally a cold
-- blue-grey and that colour was doing real work: it read as weather at a glance. Matching
-- it to the island's bark-and-amber threw that away. DinoCard.STORM is that original blue,
-- wearing the shared silhouette.
local DinoCard = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("DinoCard"))
local card = DinoCard.build(gui, DinoCard.STORM, "Banner")
card:setIcon("\240\159\140\167")   -- rain cloud
local banner = card.frame
banner.Visible = false

-- Hide/show the objective card underneath. Its Holder is toggled (not the ScreenGui)
-- because TopCenterStack reads Holder.Visible to decide whether that lane takes up space
-- -- disabling the ScreenGui instead would leave the stack reserving a gap for a card
-- nobody can see, and the storm banner would sit below its own replacement.
local objHidden = false
local function setObjectiveCard(visible)
	local sg = PlayerGui:FindFirstChild("IslandBanner")
	local holder = sg and sg:FindFirstChild("Holder")
	if not holder then
		-- StackBox: TopCenterStack has already reparented it
		local box = sg and sg:FindFirstChild("StackBox")
		holder = box and box:FindFirstChild("Holder")
	end
	-- The flag is what actually holds the card down: Bootstrap's refresh loop re-evaluates
	-- Holder.Visible every 0.5s and would otherwise put the card straight back. Setting
	-- Holder here too just makes the swap instant instead of up to half a second late.
	_G.__objectiveCardHidden = not visible
	if holder then holder.Visible = visible end
end

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
	banner.Visible = false; card:setText("", "")
	if objHidden then setObjectiveCard(true); objHidden = false end
	freeBannerSlot()
end
-- STORM BANNERS PREEMPT EVERY OTHER EVENT BANNER, for as long as they are up.
--
-- There are three scripts that can put a banner top-centre now (this one, Windstorm and
-- ServerEvents) and they all share _G.__eventBannerSlots, which stacks them down the
-- screen. Stacking is right when two minor things coincide and wrong when the weather
-- turns: the storm is the loudest thing happening and should not be the third row.
--
-- The contract is one shared timestamp. Whoever preempts writes a deadline to
-- _G.__bannerOverrideUntil; the other two check it before drawing and hide if it is
-- live. It is a plain number rather than a lock so it CANNOT deadlock -- if this script
-- errors or the player leaves mid-storm, the deadline simply passes and everyone draws
-- again. Nothing has to be released.
local BANNER_SECONDS = 5   -- the storm banner is an announcement, not a HUD element
local bannerToken = 0      -- bumped per showBanner; the auto-hide only fires for the latest

local function showBanner(text, duration)
	if not text then return end
	duration = duration or BANNER_SECONDS
	-- claim the lane: other event banners stand down until this one expires
	_G.__bannerOverrideUntil = os.clock() + duration
	_G.__bannerOverrideOwner = "monsoon"
	-- Y IS NOT SET HERE ANY MORE. TopCenterStack reparents this label into a container
	-- and moves that, so writing a stacked Y here would fight it. Rest at the top of our
	-- own container and let the stack decide where the container sits.
	claimBannerSlot()
	banner.Position = UDim2.new(0.5, 0, 0, 0)
	card:setText(text, "")
	banner.Visible = true
	setObjectiveCard(false); objHidden = true   -- we are standing in its place
	-- "IS THIS STILL MY BANNER?" ASKED WITH A TOKEN, NOT BY COMPARING THE TEXT.
	-- This used to re-read card.title.Text and compare it to `text`, which assumed the
	-- card displays exactly what it was handed. DinoCard now caps titles at five words,
	-- so a longer message would never match itself, the timer would decline to hide it,
	-- and the storm banner would sit on screen forever. A counter cannot be rewritten
	-- by the card.
	bannerToken += 1
	local myToken = bannerToken
	task.delay(duration, function()
		if bannerToken == myToken then
			hideBanner()
			if _G.__bannerOverrideOwner == "monsoon" then
				_G.__bannerOverrideUntil = nil
				_G.__bannerOverrideOwner = nil
			end
		end
	end)
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
		-- ADDED WITH THE STORM DARKENING. Anything applyWeather touches MUST be captured
		-- here -- restoreWeather only writes back what this table holds, so a property
		-- that is dimmed but not snapshotted stays dimmed for the rest of the session.
		Ambient = Lighting.Ambient,
		ClockTime = Lighting.ClockTime,
		ExposureCompensation = Lighting.ExposureCompensation,
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
	-- Heavier, darker haze: denser air and a much darker Decay, so distance reads as
	-- gloom instead of white-out. Decay is what tints the sky away from the sun, so
	-- dropping it is most of what makes the SKY itself look stormy rather than just hazy.
	TweenService:Create(monsoonAtmos, TweenInfo.new(3), {
		Density = 0.52, Haze = 3.0, Glare = 0,
		Color = Color3.fromRGB(96, 108, 124),
		Decay = Color3.fromRGB(48, 58, 72),
	}):Play()

	-- STORM DARKNESS. The old pass only dimmed Brightness to 75% and greyed the ambient,
	-- which reads as "overcast" rather than "storm". Four levers together, because no
	-- single one darkens both the sky AND the ground:
	--   ClockTime            -> drops the sun toward evening; this is what darkens the SKY
	--   Brightness / Ambient -> the sun's strength and the global fill on every surface
	--   OutdoorAmbient       -> the colour bouncing onto outdoor faces
	--   ExposureCompensation -> pulls the whole image down after all of the above
	-- Fog is darkened RELATIVE to whatever the server sent rather than overridden, so a
	-- payload that asks for a particular fog colour still gets its hue, just heavier.
	local dark = 0.55
	local darkFog = Color3.fromRGB(
		math.floor(fogColor.R * 255 * dark),
		math.floor(fogColor.G * 255 * dark),
		math.floor(fogColor.B * 255 * dark)
	)
	TweenService:Create(Lighting, TweenInfo.new(3), {
		FogColor = darkFog,
		FogEnd = payload.fogEnd or 900,
		FogStart = payload.fogStart or 40,
		Brightness = math.max(0.4, (saved.Brightness or 2) * 0.32),
		Ambient = Color3.fromRGB(38, 46, 58),
		OutdoorAmbient = Color3.fromRGB(56, 66, 80),
		ClockTime = 16.8,                       -- late, low sun -- dark without going night
		ExposureCompensation = (saved.ExposureCompensation or 0) - 0.45,
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
			Ambient = saved.Ambient,
			ClockTime = saved.ClockTime,
			ExposureCompensation = saved.ExposureCompensation,
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

--======================================================================
-- THE RAIN BED. Loops for as long as the downpour is on screen.
--======================================================================
-- 2D ON PURPOSE. The rain sheet is a part that rides 45 studs above the camera, so
-- parenting the loop to it would attenuate with distance and pan as you turn -- rain
-- is all around you, not coming from a point overhead. Parented to SoundService, it
-- has no position at all, which is what a weather bed wants.
--
-- FADED AT BOTH ENDS, and the fade-out length is not arbitrary: stopHeavyRain disables
-- the emitters and then destroys the sheet 2.5s later, so the drops already on screen
-- finish falling. Cutting the audio instantly would leave visible rain in silence, so
-- the fade matches that 2.5s exactly.
local RAIN_SOUND_ID = "rbxassetid://1516791621"
local RAIN_VOLUME   = 1.0
local rainSnd = nil

local function startRainSound()
	if rainSnd then return end
	local s = Instance.new("Sound")
	s.Name = "MonsoonRainLoop"
	s.SoundId = RAIN_SOUND_ID
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	rainSnd = s
	pcall(function() s:Play() end)
	task.spawn(function()
		local t0 = os.clock()
		while rainSnd == s and s.Parent and os.clock() - t0 < 1.5 do
			s.Volume = RAIN_VOLUME * ((os.clock() - t0) / 1.5)
			task.wait(0.05)
		end
		if rainSnd == s and s.Parent then s.Volume = RAIN_VOLUME end
	end)
end

local function stopRainSound()
	local s = rainSnd; rainSnd = nil
	if not s then return end
	task.spawn(function()
		local v0, t0 = s.Volume, os.clock()
		while s.Parent and os.clock() - t0 < 2.5 do
			s.Volume = v0 * (1 - (os.clock() - t0) / 2.5)
			task.wait(0.05)
		end
		pcall(function() s:Stop(); s:Destroy() end)
	end)
end
--======================================================================
-- THE ISLAND1 CAMPFIRE -- out while it rains, relit 8s after the storm clears.
--======================================================================
-- The campfire is a STUDIO-PLACED prop; nothing in this repo builds it, so there is no
-- constructor to edit. It is found at runtime like every other placed object here
-- (barrel, ButterLake, Geyser1), and matched on its EFFECTS rather than its name --
-- name-matching would have to guess between "Campfire" / "Camp Fire" / "Firepit" and
-- would silently do nothing if the model is called something else. A campfire IS its
-- Fire / flame-particle / light instances. Scoped to island1 so it can never reach the
-- volcano, the geysers or a pet's fire trail.
--
-- IT RESTORES WHAT IT FOUND, rather than assuming defaults. Doused state is captured per
-- instance on the way out and written back on the way in, so a fire tuned in Studio comes
-- back exactly as authored instead of at some hardcoded Size/Brightness.
local CAMPFIRE_ISLAND = "island1"
local RELIGHT_DELAY   = 8      -- seconds after the rain stops
local DOUSE_FADE      = 1.4
local FLAME_WORDS = { "fire", "flame", "ember", "spark", "smoke", "smoulder", "smolder" }

local campSaved = nil   -- [inst] = { ...original props... } while doused
local relightToken = 0  -- bumped on every state change, so a pending relight can be cancelled

local function looksLikeFlame(name)
	local n = (name or ""):lower():gsub("[^%a]", "")
	for _, w in ipairs(FLAME_WORDS) do if n:find(w, 1, true) then return true end end
	return false
end

local function campfireEffects()
	local root = workspace:FindFirstChild(CAMPFIRE_ISLAND)
	if not root then return {} end
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		local pname = d.Parent and d.Parent.Name or ""
		if d:IsA("Fire") or d:IsA("Smoke") then
			out[#out+1] = d
		elseif d:IsA("ParticleEmitter") and (looksLikeFlame(d.Name) or looksLikeFlame(pname)) then
			out[#out+1] = d
		elseif (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and looksLikeFlame(pname) then
			out[#out+1] = d
		end
	end
	return out
end

local function douseCampfire()
	relightToken += 1
	if campSaved then return end                 -- already out
	local fx = campfireEffects()
	if #fx == 0 then return end                  -- island not streamed in, or no fire here
	campSaved = {}
	for _, d in ipairs(fx) do
		if d:IsA("Fire") or d:IsA("Smoke") then
			campSaved[d] = { Enabled = d.Enabled, Size = d.Size,
			                 Heat = d:IsA("Fire") and d.Heat or nil,
			                 Opacity = d:IsA("Smoke") and d.Opacity or nil }
			-- shrink out rather than vanish in a frame; the rain is putting it out
			local goal = d:IsA("Fire") and { Size = 0, Heat = 0 } or { Size = 0, Opacity = 0 }
			TweenService:Create(d, TweenInfo.new(DOUSE_FADE), goal):Play()
			task.delay(DOUSE_FADE, function() if campSaved and campSaved[d] and d.Parent then d.Enabled = false end end)
		elseif d:IsA("ParticleEmitter") then
			campSaved[d] = { Enabled = d.Enabled }
			d.Enabled = false                     -- particles already in the air finish naturally
		else
			campSaved[d] = { Enabled = d.Enabled, Brightness = d.Brightness }
			TweenService:Create(d, TweenInfo.new(DOUSE_FADE), { Brightness = 0 }):Play()
			task.delay(DOUSE_FADE, function() if campSaved and campSaved[d] and d.Parent then d.Enabled = false end end)
		end
	end
	print(("[Campfire] rain -> put out %d effect(s) on %s"):format(#fx, CAMPFIRE_ISLAND))
end

local function relightCampfire()
	relightToken += 1
	local token = relightToken
	task.delay(RELIGHT_DELAY, function()
		-- Cancelled if the storm came back during the wait, or it was already relit.
		if token ~= relightToken or not campSaved then return end
		local saved = campSaved; campSaved = nil
		local n = 0
		for d, props in pairs(saved) do
			if d.Parent then
				d.Enabled = props.Enabled
				if props.Size ~= nil then TweenService:Create(d, TweenInfo.new(DOUSE_FADE), { Size = props.Size }):Play() end
				if props.Heat ~= nil then TweenService:Create(d, TweenInfo.new(DOUSE_FADE), { Heat = props.Heat }):Play() end
				if props.Opacity ~= nil then TweenService:Create(d, TweenInfo.new(DOUSE_FADE), { Opacity = props.Opacity }):Play() end
				if props.Brightness ~= nil then TweenService:Create(d, TweenInfo.new(DOUSE_FADE), { Brightness = props.Brightness }):Play() end
				n += 1
			end
		end
		print(("[Campfire] storm cleared %ds ago -> relit %d effect(s)"):format(RELIGHT_DELAY, n))
	end)
end

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
	startRainSound()
	douseCampfire()
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

--======================================================================
-- STEAM OFF THE LAVA when the storm clears.
--======================================================================
-- Volcanic Vista's vents run a lava emitter the whole time they are unplugged, so the
-- moment the rain stops there is hot rock that has just been rained on. This puffs steam
-- off every vent once, then lets it die -- it is a punctuation mark on the storm ending,
-- not another ambient layer.
--
-- Found by MODEL NAME rather than by talking to GeyserQuest: the two are separate
-- LocalScripts with no shared remote, and buildGeyser names every vent "GeyserVent" in
-- Workspace. If island11 has not streamed in, GetDescendants simply finds none and this
-- does nothing, which is the correct behaviour -- there is no lava on screen to steam.
local function steamOffLava()
	local vents = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == "GeyserVent" then vents[#vents+1] = d end
	end
	if #vents == 0 then return end

	for _, vent in ipairs(vents) do
		local ok, cf = pcall(function() return vent:GetPivot() end)
		if ok and cf then
			local a = Instance.new("Part")
			a.Name = "LavaSteam"
			a.Size = Vector3.new(2, 1, 2)
			a.CFrame = cf + Vector3.new(0, 3, 0)
			a.Transparency = 1
			a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
			a.Parent = workspace

			local em = Instance.new("ParticleEmitter")
			em.Texture = "rbxasset://textures/particles/smoke_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(228, 228, 232))
			em.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			em.Size = NumberSequence.new(3, 14)
			em.Lifetime = NumberRange.new(1.6, 3.2)
			em.Speed = NumberRange.new(7, 13)
			em.SpreadAngle = Vector2.new(24, 24)
			em.Acceleration = Vector3.new(0, 9, 0)   -- steam RISES, unlike the vent's falling ash
			em.Rate = 0
			em.EmissionDirection = Enum.NormalId.Top
			em.Parent = a

			-- A burst, then a short tail -- rain hitting hot rock flashes off rather than
			-- smouldering. Rate is dropped to 0 after the tail so nothing keeps emitting
			-- while the part waits to be collected.
			em:Emit(26)
			em.Rate = 9
			task.delay(2.2, function() if em.Parent then em.Rate = 0 end end)
			game:GetService("Debris"):AddItem(a, 7)
		end
	end
	print(("[Monsoon] storm cleared -> steam off %d lava vent(s)"):format(#vents))
end

local function stopHeavyRain()
	stopRainSound()
	steamOffLava()
	relightCampfire()
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
-- FLOODING IS OFF, by request. Emptying the list rather than deleting startFlood keeps
-- the whole effect one line away from coming back -- put the island numbers in and it
-- pools again exactly as before. startFlood/stopFlood no-op cleanly over an empty list.
local FLOOD_ISLANDS  = { } -- was { 1, ... , 13 } -- standing water disabled
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
		showBanner(payload.text, BANNER_SECONDS)
		applyWeather(payload)
		startHeavyRain()
		startFlood() -- standing water pools in from the very start of the storm
		_G.flightDistanceMultiplier = payload.flightMultiplier or 1
	elseif phase == "main" then
		showBanner(payload.text, BANNER_SECONDS)
		applyWeather(payload)
		startHeavyRain()
		startFlood()
		_G.flightDistanceMultiplier = payload.flightMultiplier or 0.9
	elseif phase == "ending" then
		showBanner(payload.text, BANNER_SECONDS)
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
