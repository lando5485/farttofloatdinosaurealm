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

--======================================================================
-- Banner -- shares the cross-event slot table so it stacks under a Monsoon or
-- Ice Age banner instead of covering it (same contract MonsoonRain uses).
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "WindstormUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local banner = Instance.new("TextLabel")
banner.Name = "Banner"   -- TopCenterStack adopts this by name
banner.Size = UDim2.fromOffset(500, 65) -- the house banner: 500x65 authored (first-realm spec), not a % of the screen
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.BackgroundColor3 = Color3.fromRGB(0, 90, 100)
banner.BackgroundTransparency = 0.15
banner.TextColor3 = Color3.fromRGB(215, 250, 255)
banner.Font = Enum.Font.GothamBold
banner.TextScaled = true
banner.Text = ""
banner.Visible = false
banner.Parent = gui
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)

_G.__eventBannerSlots = _G.__eventBannerSlots or {}
local BANNER_BASE_Y, BANNER_SLOT_H = 0.05, 0.10
local bannerSlot = nil
-- A storm banner outranks us. MonsoonRain writes a deadline to _G.__bannerOverrideUntil
-- while its banner is up; we stay hidden until it passes, then draw normally. Checked as
-- a timestamp rather than a lock, so a crashed or departed owner cannot wedge us shut.
local function bannerSuppressed()
	local untilT = _G.__bannerOverrideUntil
	return untilT ~= nil and os.clock() < untilT
end

local function showBanner(text)
	if not bannerSlot then
		local slots = _G.__eventBannerSlots
		local i = 1
		while slots[i] do i = i + 1 end
		slots[i] = true; bannerSlot = i
	end
	-- Y owned by TopCenterStack (see MonsoonRain's note) -- rest at our container's top.
	banner.Position = UDim2.new(0.5, 0, 0, 0)
	banner.Text = text
	banner.Visible = true
end
local function hideBanner()
	banner.Visible = false; banner.Text = ""
	if bannerSlot then _G.__eventBannerSlots[bannerSlot] = nil; bannerSlot = nil end
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
	showBanner("\xF0\x9F\x8C\xAA  WINDSTORM -- the wind is insane!")

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
			-- re-checked every tick: a storm can start mid-windstorm and take the lane
			if bannerSuppressed() then
				banner.Visible = false
			else
				banner.Visible = true
				banner.Text = ("\xF0\x9F\x8C\xAA  WINDSTORM: %ds"):format(rem)
			end
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
