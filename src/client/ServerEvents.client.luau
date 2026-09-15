--======================================================================
-- ServerEvents.client.luau  (LocalScript)  -- presentation for the server-wide events
--======================================================================
-- The client half of ServerEvents.server.luau. Ported from the first realm's
-- EventClient.client.lua handlers; every multiplier below is theirs EXCEPT the three
-- marked RETUNED, which had to move because this realm's flight economy is different.
--
-- THE THREE RETUNES, and why -- read these before "fixing" them back to the originals:
--
--   LOW_GRAVITY   first realm: speed 0.5, gasDrain 0.1
--                 Distance flown = speed x time, so that is 0.5 x 10 = FIVE TIMES the
--                 normal climb. In a realm where one full tank is deliberately tuned to
--                 about one island gap (see IslandOrder), five gaps in a single flight
--                 skips most of the tower. Here: speed 0.6, gasDrain 0.5 -> 1.2x
--                 distance, which keeps the "slow but you hang up there forever" feel
--                 without handing over three islands.
--
--   POWER_SURGE   first realm: height 1.5 AND speed 1.5. In this realm both land on the
--                 same number -- ascent speed IS height -- so applying both is 2.25x.
--                 Height is left at 1 and speed carries it.
--
--                 THE DRAIN HALF WAS MISSING, and that is what this fix adds. Distance
--                 flown = speed / drain (LOW_GRAVITY above is tuned on exactly that
--                 identity). Drain is charged per SECOND, so a 1.5x speed with no drain
--                 change is also 1.5x distance PER UNIT OF FUEL -- flying faster was
--                 flying cheaper. On a flight that only had to clear the gap, the surge
--                 did not fly you higher; it made you ARRIVE HOLDING FUEL YOU NEVER
--                 SPENT. Measured on the 17:26 run: clearing crossing 2 costs 84.3% of
--                 tank clean, the surge cleared it on 55.2%, and 79 power -- 29% of a
--                 whole tank -- carried into crossing 3, where the event was long over.
--                 That deleted the first rung of the next crossing and turned a 4-flight
--                 crossing into a 2-flight one.
--
--                 A 20s event must not still be paying out minutes later. Pairing the
--                 drain at 1.25 gives 1.5 / 1.25 = 1.2x distance -- the SAME figure
--                 LOW_GRAVITY is deliberately tuned to -- so the surge is still a real
--                 boost and still visibly rockets you, but the surplus it can leave in
--                 your tank drops from 79 power to 37, which is under the next
--                 crossing's first rung (122) and so cannot skip a flight any more.
--
--   RING_FEVER    IT IS A BUBBLE EVENT AND ONLY A BUBBLE EVENT. It reached the bubbles
--                 by setting serverEventCoinMult, which BottomHUD also pays FLIGHTS on
--                 -- so for 30 seconds every climb tick and the whole descent lump paid
--                 4x. Worth ~7 coins on a bubble; worth +17,000 on a late flight, which
--                 is two to three full tanks from one windfall. Bubbles.client now reads
--                 ringMult first, so only the line below is needed.
--
--                 first realm: ringMult 10. Here that multiplies COIN BUBBLE value, and
--                 bubbles were just cut to 0.008 specifically to stop them bankrolling a
--                 one-flight crossing (see Bubbles.client). 10x would undo that and put
--                 bubbles at 3x their pre-fix strength. 4x lands them back at the old
--                 0.032 for 30 seconds, which is a real fever and still safe.
--
-- Everything resets to nil on "reset" -- never to a hardcoded 1 -- so a stacked event
-- (a Monsoon running underneath) is not silently overwritten with a default.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ServerEventUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- ONE BANNER SYSTEM. Every announcement in this realm goes through NotifyCenter's hero card (the
-- module beside this script) -- no private ScreenGui, no private slot table, no private Y.
local Notify = require(script.Parent:WaitForChild("NotifyCenter"))

local PIN_ID = "serverevent"
local lastBannerText, lastBannerColor = nil, nil
local function showBanner(text, color)
	if text == lastBannerText and color == lastBannerColor then return end -- repaint only on change
	lastBannerText, lastBannerColor = text, color
	Notify.pin(PIN_ID, { top = "\xE2\x9A\xA1 SERVER EVENT", text = text, color = color or Color3.fromRGB(90, 90, 110),
		priority = Notify.PRIORITY.EVENT })
end
local function hideBanner()
	lastBannerText, lastBannerColor = nil, nil
	Notify.unpin(PIN_ID)
end

local function screenFlash(color, alpha, dur)
	local f = Instance.new("Frame")
	f.Name = "Flash"   -- named so TopCenterStack's banner lookup can never grab it
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (alpha or 0.3)
	f.ZIndex = 50
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(dur or 0.15), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, (dur or 0.15) + 0.2)
end

--======================================================================
-- THUNDERSTORM lighting. Same snapshot/restore discipline MonsoonRain uses: anything
-- touched here MUST be captured, or it stays changed for the rest of the session.
--======================================================================
local savedLight = nil
local function stormLightOn()
	if savedLight then return end
	savedLight = {
		FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		Brightness = Lighting.Brightness, OutdoorAmbient = Lighting.OutdoorAmbient,
		ClockTime = Lighting.ClockTime,
	}
	TweenService:Create(Lighting, TweenInfo.new(2), {
		FogColor = Color3.fromRGB(48, 52, 66),
		FogEnd = 700, FogStart = 30,
		Brightness = math.max(0.5, (savedLight.Brightness or 2) * 0.45),
		OutdoorAmbient = Color3.fromRGB(62, 68, 84),
		ClockTime = 17.4,
	}):Play()
end
local function stormLightOff()
	if not savedLight then return end
	local s = savedLight; savedLight = nil
	TweenService:Create(Lighting, TweenInfo.new(2.5), {
		FogColor = s.FogColor, FogEnd = s.FogEnd, FogStart = s.FogStart,
		Brightness = s.Brightness, OutdoorAmbient = s.OutdoorAmbient, ClockTime = s.ClockTime,
	}):Play()
end

--======================================================================
-- Clear EVERY modifier. Called on reset and before applying a new event, so two
-- events can never leave a stale multiplier behind.
--======================================================================
local active = false
local function clearAll()
	active = false
	_G.serverEventCoinMult     = nil
	_G.serverEventRingMult     = nil
	_G.serverEventSpeedMult    = nil
	_G.serverEventHeightMult   = nil
	_G.serverEventGasDrainMult = nil
	_G.thunderWindVec          = nil
	stormLightOff()
	hideBanner()
end

local function applyEvent(p)
	clearAll()
	active = true
	local col = p.color and Color3.fromRGB(p.color[1], p.color[2], p.color[3]) or nil
	showBanner(p.msg or p.disp or "EVENT", col)

	local name = p.name

	if name == "FART_STORM" then
		_G.serverEventSpeedMult = 1.3

	elseif name == "COIN_RUSH" then
		_G.serverEventCoinMult = 2

	elseif name == "LOW_GRAVITY" then
		_G.serverEventSpeedMult    = 0.6   -- RETUNED (see header)
		_G.serverEventGasDrainMult = 0.5   -- RETUNED

	elseif name == "POWER_SURGE" then
		_G.serverEventSpeedMult    = 1.5
		_G.serverEventHeightMult   = 1      -- RETUNED: speed already carries it here
		-- THE MISSING HALF (see header). Distance = speed / drain, so 1.5 / 1.25 = 1.2x
		-- climb -- LOW_GRAVITY's own tuned figure -- instead of an unpaired 1.5x that
		-- also made fuel go 50% further and leaked the surplus into the next crossing.
		_G.serverEventGasDrainMult = 1.25   -- RETUNED
		task.spawn(function()
			for _ = 1, 3 do
				if not active then return end
				screenFlash(Color3.fromRGB(255, 255, 0), 0.3, 0.15)
				task.wait(0.4)
			end
		end)

	elseif name == "RING_FEVER" then
		-- RING MULT ONLY. This used to set serverEventCoinMult = 4 as well, because
		-- Bubbles.client read coinMult first and that was the only way to reach the
		-- bubbles -- but coinMult is what BottomHUD pays FLIGHTS on, so a bubble event
		-- was quadrupling the whole flight economy for 30 seconds. Bubbles.client now
		-- reads ringMult first, so this line alone does the job. Do not add coinMult
		-- back: see the note at the eventMult line in Bubbles.client.
		_G.serverEventRingMult = 4          -- RETUNED (see header)

	elseif name == "THUNDERSTORM" then
		stormLightOn()
		-- A soft buffet that wanders, much gentler than the windstorm's 150. BottomHUD
		-- adds this to the same X/Z term, so the two stack if both are somehow live.
		task.spawn(function()
			while active do
				local a = math.random() * math.pi * 2
				local mag = 8 + math.random() * 14
				_G.thunderWindVec = Vector3.new(math.cos(a) * mag, 0, math.sin(a) * mag)
				task.wait(1.2 + math.random())
			end
			_G.thunderWindVec = nil
		end)
		task.spawn(function()
			while active do
				task.wait(3 + math.random() * 5)
				if not active then break end
				screenFlash(Color3.fromRGB(235, 240, 255), 0.45, 0.12) -- lightning
			end
		end)
	end

	-- Countdown in the banner, so the player can see it running out.
	local dur = tonumber(p.duration) or 10
	task.spawn(function()
		local endT = os.clock() + dur
		while active and os.clock() < endT do
			local rem = math.max(0, math.ceil(endT - os.clock()))
			showBanner(("%s  (%ds)"):format(p.disp or "EVENT", rem), col)
			task.wait(0.25)
		end
	end)
end

local Sync = ReplicatedStorage:WaitForChild("ServerEventSync", 30)
if Sync then
	Sync.OnClientEvent:Connect(function(phase, payload)
		if phase == "start" and payload then
			applyEvent(payload)
		elseif phase == "warn" and payload then
			-- THE 20-SECOND HEADS-UP (the first realm's EventWarn): a hazard is coming, land now. Counts down in
			-- the event banner; the event itself replaces it when it starts.
			if active then return end
			local secs = tonumber(payload.seconds) or 20
			local col = payload.color and Color3.fromRGB(payload.color[1], payload.color[2], payload.color[3]) or nil
			task.spawn(function()
				local endT = os.clock() + secs
				while not active and os.clock() < endT do
					local rem = math.max(0, math.ceil(endT - os.clock()))
					showBanner(("\xE2\x9A\xA0 %s IN %ds -- LAND NOW!"):format(tostring(payload.disp or "STORM"), rem), col)
					task.wait(0.25)
				end
				if not active then hideBanner() end
			end)
		elseif phase == "reset" or phase == "stop" then
			clearAll()
		end
	end)
end

print("[ServerEvents] client ready")
