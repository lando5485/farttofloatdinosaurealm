--======================================================================
-- Haptics.client.luau   (StarterPlayerScripts)
--======================================================================
-- EVERY MOMENT IN THE GAME THAT SHOULD BE FELT, IN ONE PLACE.
--
-- Public API -- everything else in the game touches only these:
--   _G.hapticPulse(style)          fire a one-shot. Unknown style -> "milestone", never errors.
--   _G.hapticLoop(style, get)      start a LOOP. `get` is called each frame and returns 0-1 intensity.
--   _G.hapticLoopStop(style)       stop that loop (safe to call when it is not running).
--   _G.hapticEnabled(bool)         player setting. false = totally silent, loops included.
--   _G.hapticStyles                the style table, so callers can read durations.
--
-- ===== THE VOCABULARY IS MOSTLY TINY =====
-- 18 styles from an 8ms tick to a 3s rebirth. The important discipline is that the ones fired OFTEN are
-- nearly nothing: a game that buzzes hard constantly is exhausting, drains the battery, and trains the
-- player to ignore the buzz -- at which point the big moments stop landing too. Loud is rare on purpose.
--
-- `shake` is 0 for every frequent style. A camera shake on every button press would be miserable on
-- desktop, which is the platform that has no vibrator and therefore gets the thump as its stand-in.
--
-- ===== LATENCY IS THE WHOLE FEATURE =====
-- A buzz that arrives after the thing it reacts to reads as a second, unexplained event. Everything that is
-- ours is stripped out of the hot path:
--   * EFFECTS ARE PRE-BUILT at load -- no Instance.new/FloatCurveKey/reparent on the celebration frame.
--   * EVERY WAVEFORM LEADS WITH A TRANSIENT at t=0 on a Constant key. A curve that ramps in from quiet
--     feels late even when it started on time, because perceptually it did.
--   * NOTHING IS DEFERRED -- the motor's opening value and the camera's first offset are written
--     synchronously, on the calling frame, before the call returns.
--
-- ===== ONE SHAPE, THREE OUTPUTS =====
--   1. HapticEffect + SetWaveformKeys  -- the curve played natively. Newer phones, pads that route here.
--   2. SetMotor, stepped every frame   -- the handset vibrator AND controller rumble motors.
--   3. camera thump                    -- desktop has neither vibrator, and it should still land.
--
-- ===== TWO SEPARATE APIS, AND A PHONE NEEDS THE SECOND ONE =====
-- On mobile the handset's haptic engine is driven through the *Gamepad1 motor channel* -- SetMotor(Gamepad1)
-- is what actually buzzes a phone, and it is routinely the layer that works when HapticEffect does nothing.
-- This file used to early-return unless IsVibrationSupported(Gamepad1) was true; on a phone with no
-- controller paired that is FALSE, so the one layer that can buzz a handset was skipped on exactly the
-- devices it exists for. Every call is individually pcall'd instead, and both motors always get the full
-- value -- biasing a style low/high is nicer on a pad but silences it on a handset wired to one channel.
--
-- ===== THINGS THAT SILENCE HAPTICS AND ARE NOT BUGS IN THIS FILE =====
-- Run /haptic in game to print these along with what the device reports.
--   * Roblox in-game Settings -> Vibration must be ON.  * OS haptics on.
--   * Battery saver / Low Power Mode disables the vibrator.
--   * VOICE CHAT: widely reported to kill mobile haptics while enabled.
--   * Studio cannot buzz anything -- a "fires OK" log in Studio proves nothing.
--======================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local HapticService    = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")
local TextChatService  = game:GetService("TextChatService")

local player = Players.LocalPlayer

local MOTORS = { Enum.VibrationMotor.Small, Enum.VibrationMotor.Large }
local PAD    = Enum.UserInputType.Gamepad1

--======================================================================
-- THE PALETTE
--======================================================================
-- keys = { timeMilliseconds, intensity 0-1, interpolation }
--   "Constant" holds until the next key -- square edges, sharp onset. Every style STARTS on one.
--   "Linear"/"Cubic" ramp -- swells, roars, decays.
-- fallback = built-in HapticEffectType if this client is too old for custom waveforms.
-- shake    = desktop camera-thump scale. 0 for anything fired often.
-- rank     = precedence. A louder pulse interrupts a quieter one; a quieter one during a louder one is
--            dropped rather than muddling it. Landing on a new island fires land + unlock + a banner
--            milestone on the same frame; without rank that is mush.
local WAVES = {
	-- ---------- micro: fired constantly, must be nearly nothing ----------
	tick = { rank = 1, fallback = "UIClick", shake = 0, keys = {
		{ 0, 0.45, "Constant" }, { 8, 0.00, "Constant" } } },

	tock = { rank = 1, fallback = "UIClick", shake = 0, keys = {
		{ 0, 0.70, "Constant" }, { 15, 0.00, "Constant" } } },

	coin = { rank = 2, fallback = "UIClick", shake = 0, keys = {
		{ 0, 0.80, "Constant" }, { 18, 0.35, "Constant" }, { 30, 0.00, "Constant" } } },

	-- ---------- light ----------
	bump = { rank = 3, fallback = "GameplayCollision", shake = 0.05, keys = {
		{ 0, 0.85, "Constant" }, { 25, 0.40, "Cubic" }, { 60, 0.00, "Cubic" } } },

	grab = { rank = 2, fallback = "UIClick", shake = 0, keys = {
		{ 0, 0.55, "Constant" }, { 30, 0.75, "Linear" }, { 70, 0.00, "Linear" } } },

	-- Two flat low buzzes. Deliberately dull and slightly unpleasant -- this is the "no" and it should not
	-- feel like a reward. Failures are currently silent, which is why players re-press a refused button.
	fail = { rank = 4, fallback = "GameplayCollision", shake = 0, keys = {
		{ 0, 0.55, "Constant" }, { 45, 0.00, "Constant" }, { 70, 0.55, "Constant" },
		{ 120, 0.00, "Constant" } } },

	-- ---------- medium ----------
	purchase = { rank = 4, fallback = "UINotification", shake = 0.06, keys = {
		{ 0, 1.00, "Constant" }, { 30, 0.00, "Constant" }, { 45, 0.45, "Cubic" },
		{ 100, 0.60, "Cubic" }, { 140, 0.00, "Cubic" } } },

	milestone = { rank = 6, fallback = "UINotification", shake = 0.13, keys = {
		{ 0, 1.00, "Constant" }, { 45, 1.00, "Constant" }, { 50, 0.00, "Constant" },
		{ 110, 0.00, "Constant" }, { 115, 0.85, "Constant" }, { 160, 0.85, "Constant" },
		{ 165, 0.00, "Constant" } } },

	-- A rising jab. Fish bite, bird strike, incoming meteor -- things that want your attention NOW.
	alert = { rank = 5, fallback = "GameplayCollision", shake = 0.10, keys = {
		{ 0, 0.90, "Constant" }, { 40, 0.50, "Linear" }, { 90, 1.00, "Linear" },
		{ 130, 1.00, "Constant" }, { 180, 0.00, "Constant" } } },

	-- ---------- heavy ----------
	-- ===== THE BIGGEST MOMENT A PLAYER GETS FOR FREE =====
	-- 1620ms -- three times the length it started at, and structured as an actual event rather than a buzz:
	--   0-370   FOUR cracks, speeding up and hardening. The shell is losing.
	--   375-480 THE BREAK. The longest single hit in the whole palette, held at full.
	--   480-1000 the pet pushes out -- a slow warm swell up to a peak. This is the part that feels ALIVE.
	--   1100-1620 a three-tap flourish, each bigger than the last, then a long fall to nothing.
	-- Rank 8 (was 7) because it now runs for over a second and a half: at 7 it tied with `unlock`, and a tie
	-- lets the newer pulse interrupt -- so a quest completing mid-hatch could have cut the reveal in half.
	hatch = { rank = 8, fallback = "GameplayCollision", shake = 0.28, keys = {
		{    0, 1.00, "Constant" },   -- crack 1
		{   35, 1.00, "Constant" },
		{   40, 0.00, "Constant" },
		{   95, 0.00, "Constant" },
		{  100, 1.00, "Constant" },   -- crack 2
		{  140, 1.00, "Constant" },
		{  145, 0.00, "Constant" },
		{  200, 0.00, "Constant" },
		{  205, 1.00, "Constant" },   -- crack 3 -- the gaps are closing
		{  245, 1.00, "Constant" },
		{  250, 0.00, "Constant" },
		{  290, 0.00, "Constant" },
		{  295, 1.00, "Constant" },   -- crack 4 -- rapid now, the shell is giving way
		{  330, 1.00, "Constant" },
		{  335, 0.00, "Constant" },
		{  370, 0.00, "Constant" },
		{  375, 1.00, "Constant" },   -- THE BREAK
		{  470, 1.00, "Constant" },   -- held: the longest hit in the palette
		{  480, 0.25, "Cubic"    },   -- shell falls away
		{  600, 0.55, "Cubic"    },   -- and it pushes out
		{  780, 0.85, "Cubic"    },
		{  900, 1.00, "Cubic"    },   -- fully out
		{ 1000, 0.78, "Cubic"    },
		{ 1100, 0.95, "Constant" },   -- flourish 1
		{ 1150, 0.42, "Cubic"    },
		{ 1220, 0.95, "Constant" },   -- flourish 2
		{ 1270, 0.40, "Cubic"    },
		{ 1340, 1.00, "Constant" },   -- flourish 3, the biggest
		{ 1420, 1.00, "Constant" },
		{ 1500, 0.55, "Cubic"    },
		{ 1620, 0.00, "Cubic"    } } },

	unlock = { rank = 7, fallback = "UINotification", shake = 0.20, keys = {
		{ 0, 1.00, "Constant" }, { 55, 1.00, "Constant" }, { 60, 0.20, "Constant" },
		{ 150, 0.45, "Cubic" }, { 320, 0.85, "Cubic" }, { 480, 1.00, "Cubic" },
		{ 560, 0.70, "Cubic" }, { 700, 0.00, "Cubic" } } },

	-- Five escalating taps. Rhythm, not volume, is what makes this read as "something special".
	rare = { rank = 9, fallback = "UINotification", shake = 0.22, keys = {
		{ 0, 0.50, "Constant" }, { 30, 0.00, "Constant" }, { 130, 0.62, "Constant" },
		{ 160, 0.00, "Constant" }, { 290, 0.74, "Constant" }, { 320, 0.00, "Constant" },
		{ 470, 0.86, "Constant" }, { 500, 0.00, "Constant" }, { 650, 1.00, "Constant" },
		{ 760, 1.00, "Constant" }, { 900, 0.00, "Cubic" } } },

	-- ---------- event ----------
	warp = { rank = 8, fallback = "GameplayExplosion", shake = 0.30, keys = {
		{ 0, 0.90, "Constant" }, { 60, 0.55, "Cubic" }, { 500, 0.18, "Cubic" },
		{ 850, 0.05, "Cubic" }, { 1000, 0.00, "Constant" }, { 1060, 1.00, "Constant" },
		{ 1130, 1.00, "Constant" }, { 1200, 0.00, "Cubic" } } },

	quake = { rank = 9, fallback = "GameplayExplosion", shake = 0.60, keys = {
		{ 0, 1.00, "Constant" }, { 90, 1.00, "Constant" }, { 140, 0.55, "Cubic" },
		{ 300, 0.85, "Cubic" }, { 480, 0.45, "Cubic" }, { 700, 0.70, "Cubic" },
		{ 950, 0.30, "Cubic" }, { 1400, 0.00, "Cubic" } } },

	launch = { rank = 9, fallback = "GameplayExplosion", shake = 0.55, keys = {
		{ 0, 1.00, "Constant" }, { 60, 1.00, "Constant" }, { 70, 0.45, "Linear" },
		{ 250, 0.60, "Linear" }, { 450, 0.80, "Linear" }, { 650, 1.00, "Linear" },
		{ 820, 1.00, "Constant" }, { 1000, 0.85, "Cubic" }, { 1400, 0.50, "Cubic" },
		{ 1850, 0.16, "Cubic" }, { 2200, 0.00, "Cubic" } } },

	-- The biggest thing in the game. Winds down to nothing -- the silence is the held breath -- then everything.
	rebirth = { rank = 10, fallback = "GameplayExplosion", shake = 0.70, keys = {
		{ 0, 0.85, "Constant" }, { 200, 0.55, "Cubic" }, { 700, 0.22, "Cubic" },
		{ 1200, 0.04, "Cubic" }, { 1500, 0.00, "Constant" }, { 1700, 0.00, "Constant" },
		{ 1750, 1.00, "Constant" }, { 2100, 1.00, "Constant" }, { 2400, 0.75, "Cubic" },
		{ 2700, 0.40, "Cubic" }, { 3000, 0.00, "Cubic" } } },

	-- Three dying coughs as the tank empties. Ends in silence deliberately: the ABSENCE is the message.
	sputter = { rank = 5, fallback = "GameplayCollision", shake = 0.09, keys = {
		{ 0, 0.80, "Constant" }, { 50, 0.00, "Constant" }, { 160, 0.55, "Constant" },
		{ 200, 0.00, "Constant" }, { 330, 0.30, "Constant" }, { 370, 0.00, "Constant" } } },
}

-- strain and thrust are LOOPS -- no fixed curve, the caller supplies intensity every frame.
local LOOPS = {
	strain = { rank = 3, fallback = "GameplayCollision" },
	thrust = { rank = 3, fallback = "GameplayExplosion" },
}

for _, w in pairs(WAVES) do
	w.duration = w.keys[#w.keys][1] / 1000
end

_G.hapticStyles = WAVES

local function sample(keys, tMs: number): number
	if tMs <= keys[1][1] then return keys[1][2] end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if tMs >= a[1] and tMs <= b[1] then
			if a[3] == "Constant" then return a[2] end
			local span = b[1] - a[1]
			local f = (span > 0) and ((tMs - a[1]) / span) or 1
			return a[2] + (b[2] - a[2]) * f
		end
	end
	return keys[#keys][2]
end

--======================================================================
-- PLAYER SETTING
--======================================================================
-- One gate for everything. Off means off -- one-shots, loops, camera thump, the lot -- and any live loop is
-- torn down on the spot rather than left humming until the player next flies.
local enabled = true
local loops = {}   -- style -> live loop state

local stopLoop      -- forward-declared (loops is torn down by the setting gate above its real body)

_G.hapticEnabled = function(on)
	enabled = (on ~= false)
	if not enabled then
		for name in pairs(loops) do stopLoop(name) end
	end
end

--======================================================================
-- LAYER 1 -- THE WAVEFORM API, PRE-BUILT
--======================================================================
-- One HapticEffect per style, created at load and left parented. Firing one is then a Position write and a
-- Play() -- no Instance.new, no FloatCurveKey construction, no reparent on the celebration frame.
local pool = {}

local function buildEffect(name: string)
	local wave = WAVES[name] or LOOPS[name]
	if not wave then return end
	pcall(function()
		local fx = Instance.new("HapticEffect")
		fx.Name = "Haptic_" .. name
		fx.Radius = 500
		fx.Parent = workspace    -- parented BEFORE SetWaveformKeys, matching the documented example

		if wave.keys then
			-- Type defaults to Custom, and a Custom effect with no keys plays SILENCE -- so if anything here
			-- throws (old client, no FloatCurveKey) the type MUST go back to a built-in one or the fallback
			-- would be a buzz that does nothing.
			local custom = pcall(function()
				fx.Type = Enum.HapticEffectType.Custom
				local keys = {}
				for i, k in ipairs(wave.keys) do
					keys[i] = FloatCurveKey.new(k[1], k[2], Enum.KeyInterpolationMode[k[3]])
				end
				fx:SetWaveformKeys(keys)
			end)
			if not custom then fx.Type = Enum.HapticEffectType[wave.fallback] end
		else
			fx.Type = Enum.HapticEffectType[wave.fallback]
			fx.Looped = true
		end

		pool[name] = fx
	end)
end

for name in pairs(WAVES) do buildEffect(name) end
for name in pairs(LOOPS) do buildEffect(name) end

local function playerPos(): Vector3
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.Position end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.new()
end

local function deviceBuzz(name: string): boolean
	local fx = pool[name]
	if not fx or not fx.Parent then
		buildEffect(name)
		fx = pool[name]
		if not fx then return false end
	end
	-- Stop is its OWN pcall: it exists only so a repeat of the same style restarts rather than being
	-- swallowed, and if it throws (never played, older client) it must not take Play() down with it.
	pcall(function() fx:Stop() end)
	return (pcall(function()
		fx.Position = playerPos()
		fx:Play()
	end))
end

--======================================================================
-- LAYER 2 -- THE MOTOR (PHONE VIBRATOR *AND* CONTROLLER RUMBLE)
--======================================================================
-- motorGen: a new pulse claims the motor, older loops see the change and stop writing. Without it a pulse
-- starting mid-launch would be killed by the launch's own "set back to 0", and the newer, more important
-- buzz would be the one that vanished.
local motorGen = 0
local activeRank = 0      -- rank of the one-shot currently owning the motor
local activeUntil = 0

local function setMotors(v: number): boolean
	local any = false
	for _, motor in ipairs(MOTORS) do
		if pcall(HapticService.SetMotor, HapticService, PAD, motor, v) then any = true end
	end
	return any
end

-- Loop intensity is mixed UNDER one-shots: while a pulse owns the motor the loop stops writing, then resumes
-- when it ends. Otherwise a 0.3 flight hum would smear every crisp tick fired during flight into nothing.
local function loopFloor(): number
	local v = 0
	for _, st in pairs(loops) do
		local ok, got = pcall(st.get)
		if ok and type(got) == "number" then v = math.max(v, math.clamp(got, 0, 1)) end
	end
	return v
end

local function rumble(wave): boolean
	motorGen += 1
	local mine = motorGen
	if not setMotors(sample(wave.keys, 0)) then return false end   -- the strike, right now

	local t0, conn = os.clock(), nil
	conn = RunService.Heartbeat:Connect(function()
		if motorGen ~= mine then conn:Disconnect(); return end
		local elapsed = os.clock() - t0
		if elapsed >= wave.duration then
			conn:Disconnect()
			if motorGen == mine then
				activeRank = 0
				setMotors(loopFloor())    -- hand the motor back to any running loop
			end
			return
		end
		setMotors(math.max(sample(wave.keys, elapsed * 1000), loopFloor() * 0.35))
	end)
	return true
end

--======================================================================
-- LAYER 3 -- THE SCREEN
--======================================================================
-- Desktop has no vibrator. Amplitude reads off the same curve so a launch swells on screen the way it swells
-- in the hand. MULTIPLIES the camera CFrame rather than setting it, so it rides whatever the camera is
-- already doing. First offset is applied immediately -- waiting a frame is a visible 16ms of lateness.
local function thump(wave)
	if wave.shake <= 0 or not workspace.CurrentCamera then return end

	local function offset(amp: number)
		local c = workspace.CurrentCamera
		if not c then return end
		c.CFrame = c.CFrame * CFrame.new(
			(math.random() - 0.5) * amp, (math.random() - 0.5) * amp, 0)
	end

	offset(sample(wave.keys, 0) * wave.shake)

	local t0, conn = os.clock(), nil
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= wave.duration then conn:Disconnect(); return end
		offset(sample(wave.keys, elapsed * 1000) * wave.shake)
	end)
end

--======================================================================
-- ONE-SHOTS
--======================================================================
-- Throttled per style. CoinPulse and ring pickups can fire many times a second; unthrottled that is a solid
-- buzz for the length of a flight, which is both awful and a battery drain.
local lastAt = {}
local THROTTLE = 0.11        -- ~9/sec ceiling for any single style

local loggedOnce = false

local function hapticPulse(style: string?)
	if not enabled then return end

	local name = (style and WAVES[style]) and style or "milestone"
	local wave = WAVES[name]
	local now = os.clock()

	if (now - (lastAt[name] or 0)) < THROTTLE then return end
	-- Precedence: a quieter pulse never interrupts a louder one that is still playing.
	if now < activeUntil and wave.rank < activeRank then return end
	lastAt[name] = now
	activeRank, activeUntil = wave.rank, now + wave.duration

	local fxOk  = deviceBuzz(name)
	local motOk = rumble(wave)
	thump(wave)

	if not loggedOnce then
		loggedOnce = true
		print(("[Haptics] first pulse -- HapticEffect played=%s, SetMotor accepted=%s. Neither proves the device "
			.. "physically buzzed; run /haptic on the phone to test the layers.")
			:format(tostring(fxOk), tostring(motOk)))
	end
end

--======================================================================
-- LOOPS  (thrust, strain)
--======================================================================
-- The flight hum is the most valuable haptic in the game: intensity tracks gas remaining, so the player
-- FEELS the tank emptying without looking at the meter, and it dies as they start to fall.
--
-- `get` is polled every frame and returns 0-1. The loop owns no timing of its own -- the caller decides what
-- the number means -- which is why one implementation serves both the flight hum and a charge-up strain.
stopLoop = function(name: string)
	local st = loops[name]
	if not st then return end
	loops[name] = nil
	if st.conn then st.conn:Disconnect() end
	local fx = pool[name]
	if fx then pcall(function() fx:Stop() end) end
	if not next(loops) and activeRank == 0 then setMotors(0) end
end

local function hapticLoop(style: string, get)
	if not enabled or not LOOPS[style] or type(get) ~= "function" then return end
	if loops[style] then loops[style].get = get; return end   -- already running: just retarget it

	local st = { get = get }
	loops[style] = st

	local fx = pool[style]
	if fx then pcall(function() fx.Position = playerPos(); fx:Play() end) end

	st.conn = RunService.Heartbeat:Connect(function()
		if loops[style] ~= st then st.conn:Disconnect(); return end
		local ok, v = pcall(get)
		if not ok or type(v) ~= "number" then return end
		v = math.clamp(v, 0, 1)
		if fx and fx.Parent then pcall(function() fx.Position = playerPos() end) end
		-- Silent while a one-shot owns the motor; it resumes the moment that pulse ends.
		if os.clock() >= activeUntil then setMotors(v) end
	end)
end

_G.hapticPulse    = hapticPulse
_G.hapticLoop     = hapticLoop
_G.hapticLoopStop = stopLoop

-- A pad left buzzing through a death is the kind of bug players report as "my controller broke".
player.CharacterAdded:Connect(function()
	motorGen += 1
	activeRank, activeUntil = 0, 0
	for name in pairs(loops) do stopLoop(name) end
	setMotors(0)
end)

--======================================================================
-- /haptic
--======================================================================
-- Studio cannot answer this: no motor, no haptic engine, every call "succeeds". Fires the device layers
-- separately so whoever is holding the phone can say which one they felt, then walks the whole palette.
local function probe(fn): string
	local ok, v = pcall(fn)
	return ok and tostring(v) or "unavailable"
end

local ORDER = { "tick", "tock", "coin", "grab", "bump", "fail", "purchase", "alert",
	"milestone", "hatch", "unlock", "rare", "sputter", "warp", "quake", "launch", "rebirth" }

local function diagnose()
	print("==================== [Haptics] /haptic ====================")
	print(("enabled setting   : %s"):format(tostring(enabled)))
	print(("touch device      : %s"):format(probe(function() return UserInputService.TouchEnabled end)))
	print(("gamepad connected : %s"):format(probe(function() return UserInputService:GetGamepadConnected(PAD) end)))
	print(("IsVibrationSupported(Gamepad1): %s   <- often FALSE on a phone that still buzzes")
		:format(probe(function() return HapticService:IsVibrationSupported(PAD) end)))
	for _, motor in ipairs(MOTORS) do
		print(("IsMotorSupported(%s): %s"):format(motor.Name,
			probe(function() return HapticService:IsMotorSupported(PAD, motor) end)))
	end
	local built = 0
	for _ in pairs(pool) do built += 1 end
	print(("pre-built effects : %d (custom waveforms %s)"):format(built,
		(pool.launch and pool.launch.Type == Enum.HapticEffectType.Custom) and "OK" or "UNSUPPORTED, using built-ins"))
	if RunService:IsStudio() then
		print("STUDIO -- no vibrator here. This can tell you the code runs; it can never buzz.")
	end

	task.spawn(function()
		print("-- WHICH LAYER --")
		print("   [1/2] HapticEffect only NOW")
		deviceBuzz("launch")
		task.wait(3)
		print("   [2/2] motor only, full power 0.6s NOW  <- usually the one that buzzes a phone")
		setMotors(1); task.wait(0.6); setMotors(0)
		task.wait(1.5)

		print("-- THE PALETTE, quietest to loudest --")
		for _, name in ipairs(ORDER) do
			print(("   %-10s %.2fs"):format(name, WAVES[name].duration))
			lastAt[name] = 0; activeRank = 0; activeUntil = 0
			hapticPulse(name)
			task.wait(math.max(WAVES[name].duration, 0.2) + 0.7)
		end

		print("-- THE FLIGHT LOOP: 3s, fading out like an emptying tank --")
		local t0 = os.clock()
		hapticLoop("thrust", function()
			return math.max(0, 0.55 * (1 - (os.clock() - t0) / 3))
		end)
		task.wait(3.2)
		stopLoop("thrust")
		hapticPulse("sputter")

		print("Felt NOTHING? Check: 1) Roblox Settings -> Vibration ON  2) OS haptics on")
		print("   3) Battery saver OFF  4) Voice chat OFF")
		print("===========================================================")
	end)
end

local function onCommand(msg)
	msg = tostring(msg or ""):lower()
	if msg:sub(1, 7) == "/haptic" then diagnose() end
end

pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

print("[Haptics] ready -- 17 one-shot styles + 2 loops, pre-built and fired synchronously. "
	.. "_G.hapticPulse / hapticLoop / hapticLoopStop / hapticEnabled. Type /haptic on a phone to test.")
