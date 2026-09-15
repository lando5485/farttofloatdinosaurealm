--======================================================================
-- Windstorm.client.luau  (LocalScript)  -- presentation for the WINDSTORM event
--======================================================================
-- PORTED FROM THE FIRST REALM, from EventClient.client.lua's startWindstorm(). The
-- mechanic, the numbers and the feel are that script's; only the plumbing changed, to
-- match how events are wired HERE (a server driver + a Sync RemoteEvent, the way
-- Monsoon.server/MonsoonRain.client work) instead of the first realm's single
-- client-side EventClient reacting to ServerEventNotify.
--
-- WHAT CAME ACROSS UNCHANGED, because it is what makes the event feel like itself:
--   * The wind is a HORIZONTAL SHOVE, not a slowdown. BottomHUD adds
--     _G.windstormDir * WIND_PUSH to the flight BodyVelocity's X/Z.
--   * WIND_PUSH = 150 studs/sec against a steering speed of 48 -- roughly 3x, so you
--     genuinely get blown off course and have to fight it. That ratio is the event.
--   * The direction WANDERS: every 4s a fresh random direction is blended in with
--     (dir + newDir).Unit, so it never settles and never simply reverses.
--   * One reusable Looped Sound. Re-triggering restarts it rather than stacking a
--     second copy on top -- the first realm's comment on this is load-bearing.
--
-- _G IS THE INTERFACE, and deliberately so: BottomHUD's flight loop reads
-- _G.windstormActive / _G.windstormDir every frame. Same contract as
-- _G.flightDistanceMultiplier, which MonsoonRain already sets for its -10%.
--======================================================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local Debris           = game:GetService("Debris")

local player = Players.LocalPlayer

-- ===== tuning (first realm's values) =====
local WIND_SOUND_ID   = "rbxassetid://101642229651469"
local WIND_VOLUME     = 0.5
local DURATION        = 20    -- seconds
local DIR_CHANGE_EVERY = 4    -- seconds between direction blends
local STREAK_EVERY    = 0.1   -- seconds between visual streaks
local STREAK_SPEED    = 60

_G.windstormActive = false
_G.windstormDir    = Vector3.new(1, 0, 0)

-- ONE instance, reused. Playing an already-playing Sound restarts it instead of layering
-- a second one, which is exactly the behaviour we want if the event re-triggers.
local windSound = Instance.new("Sound")
windSound.Name = "WindstormSound"
windSound.SoundId = WIND_SOUND_ID
windSound.Looped = true
windSound.Volume = WIND_VOLUME
windSound.Parent = SoundService

-- ONE BANNER SYSTEM. Every announcement in this realm goes through NotifyCenter's hero card (the
-- module beside this script) -- no private ScreenGui, no private slot table, no private Y.
local Notify = require(script.Parent:WaitForChild("NotifyCenter"))

local WIND_COLOR = Color3.fromRGB(0, 120, 135)
local PIN_ID = "windstorm"
local lastBannerText = nil
local function showBanner(text)
	if text == lastBannerText then return end -- repaint only when the wording changes
	lastBannerText = text
	Notify.pin(PIN_ID, { top = "\xF0\x9F\x8C\xAA WINDSTORM", text = text, color = WIND_COLOR, priority = Notify.PRIORITY.EVENT })
end
local function hideBanner()
	lastBannerText = nil
	Notify.unpin(PIN_ID)
end

--======================================================================
-- Wind streaks -- first realm's spawnWindStreak, verbatim in behaviour.
--======================================================================
local function spawnWindStreak(dir)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local streak = Instance.new("Part")
	streak.Name = "WindStreak"
	streak.Size = Vector3.new(0.1, 0.1, 4)
	streak.Color = Color3.new(1, 1, 1)
	streak.Material = Enum.Material.Neon
	streak.Transparency = 0.4
	streak.CanCollide = false
	streak.CanQuery = false   -- added: the dino realm raycasts for islands and dig spots,
	streak.CanTouch = false   -- and a cloud of streaks would otherwise sit in those rays
	streak.CastShadow = false
	streak.Anchored = false
	streak.Position = hrp.Position + Vector3.new(math.random(-20, 20), math.random(-5, 15), math.random(-20, 20))
	streak.Parent = workspace

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	bv.Velocity = (dir or Vector3.new(1, 0, 0)) * STREAK_SPEED
	bv.Parent = streak

	Debris:AddItem(streak, 1)
end

--======================================================================
-- The event itself.
--======================================================================
local running = false

local function randomDir()
	local rx = (math.random(1, 2) == 1) and math.random(-10, -3) or math.random(3, 10)
	local rz = (math.random(1, 2) == 1) and math.random(-10, -3) or math.random(3, 10)
	return Vector3.new(rx, 0, rz).Unit
end

local function stopWindstorm()
	running = false
	_G.windstormActive = false
	windSound:Stop()
	hideBanner()
end

local function startWindstorm(duration)
	duration = tonumber(duration) or DURATION
	if running then                      -- re-trigger: re-aim and extend, never stack
		_G.windstormDir = randomDir()
		return
	end
	running = true
	_G.windstormActive = true
	_G.windstormDir = randomDir()
	windSound:Play()
	showBanner("The wind is insane!")

	task.spawn(function()
		local endT = os.clock() + duration
		local dirTimer, streakTimer = 0, 0
		while os.clock() < endT and _G.windstormActive do
			local dt = task.wait(0.05) or 0.05
			dirTimer = dirTimer + dt
			streakTimer = streakTimer + dt

			-- BLEND, do not replace. A hard swap reads as the wind teleporting; blending
			-- the old direction with a new one makes it swing round.
			if dirTimer >= DIR_CHANGE_EVERY then
				dirTimer = 0
				_G.windstormDir = (_G.windstormDir + randomDir()).Unit
			end

			if streakTimer >= STREAK_EVERY then
				streakTimer = 0
				pcall(function() spawnWindStreak(_G.windstormDir) end)
			end

			local rem = math.max(0, math.ceil(endT - os.clock()))
			showBanner(("The wind is insane!  %ds"):format(rem))
		end
		stopWindstorm()
	end)
end

--======================================================================
-- Server sync. Mirrors MonsoonSync: (phase, payload).
--======================================================================
local sync = ReplicatedStorage:WaitForChild("WindstormSync", 30)
if sync then
	sync.OnClientEvent:Connect(function(phase, payload)
		if phase == "start" then
			startWindstorm(payload and payload.duration)
		elseif phase == "reset" or phase == "stop" then
			stopWindstorm()
		end
	end)
end

-- Safety: never leave the shove on if this script is torn down (character reset, teleport).
player.CharacterRemoving:Connect(function()
	if not running then _G.windstormActive = false end
end)

print("[Windstorm] client ready (push " .. tostring(150) .. " vs steering 48; " .. DURATION .. "s)")
