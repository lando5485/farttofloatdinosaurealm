--[[
============================================================================================================
 GUT GROW CINEMATIC  (LocalScript -> StarterPlayerScripts)
============================================================================================================
 PORTABLE. This file is IDENTICAL in all four realms (food / candy / dino / space). It configures itself at
 runtime -- it reads the stomach max from whichever place the realm keeps it, and it drives the belly itself
 only in the realms that have no BellyPuff to drive it. Copy it around verbatim; do not fork it per realm.

 WHAT IT IS FOR
   Buying a gut is the biggest decision in the game and it was invisible. Coins went down, a number in the
   HUD went up, and the belly you just paid for grew silently BEHIND the shop panel you were still staring
   at. This is that moment made visible: the UI steps aside, the camera swings around to your belly, and you
   watch it stretch to its new size while it groans.

 WHAT TRIGGERS IT
   Your own stomach max going UP -- nothing else. Not the buy button and not the remote, because those fire
   on a purchase the server then REFUSES (locked island, unfinished quest, not enough coins) and a refusal
   must never play the shot. The value only rises after the coins have actually moved. It is read from, in
   order, whichever the realm has:
       1. player.leaderstats.StomachMax      (food / candy / dino)
       2. player:GetAttribute("StomachMax")  (space -- PlayerState publishes it every state push)

 LANDED ONLY
   The camera and the stretch sound only happen with your feet on the ground. Hijacking the camera mid-flight
   would cost someone the crossing they are in the middle of, and a gut can be bought from a shop panel while
   airborne. An airborne buy therefore plays nothing at all -- the gut just grows, as it always did.

 NO PURCHASE JINGLE
   There is deliberately no "congratulations" / item-bought cue on a gut buy. The stretch is the sound of the
   purchase; a jingle on top of it made the moment read as a shop confirmation instead of the belly growing.

 WHY IT HIDES THE UI
   Every realm's stomach shop stays OPEN after a successful buy (it repaints the row to OWNED). A camera move
   behind a 700x520 panel shows the player a panel. So the shot disables every ScreenGui that is currently
   enabled and re-enables exactly those at the end -- never a blanket sweep of PlayerGui, and never a destroy.
   A watchdog re-enables them even if this script errors mid-shot, because the one unacceptable outcome here
   is a player left with no HUD.

 HOW THE BELLY ACTUALLY GROWS
   Whoever already owns the belly's size keeps owning it; this script only changes the PACE.
     * Realms with BellyPuff.client (food, candy): it already lerps the local belly toward the tier size every
       frame. This script publishes two timestamps -- _G.gutGrowHoldUntil (freeze at the old size while the
       camera flies in) and _G.gutGrowSlowUntil (grow slowly while the camera watches) -- and BellyPuff reads
       them. No tier table is duplicated here, so there is nothing to drift.
     * Realms without it (space, dino): this script drives the size itself for the length of the shot, by
       sampling the size BEFORE the change and lerping to the size the server replicates after it. Same
       trick, still no tier table. The geometry below is copied from BellySystem.server / BellyPuff and is
       marked [BellySystem]; if that is ever retuned, paste the new numbers here too.

 IF THE REALM HAS NO BELLY AT ALL
   It says so once in the log and falls back to camera + sounds. Install the belly by pasting
   tools/GutBelly_OtherRealms.server.luau into that place's ServerScriptService -- that is the whole install.
============================================================================================================
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Debris           = game:GetService("Debris")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer

--==================== TUNABLES ====================
-- No BUY / "congratulations" cue: see NO PURCHASE JINGLE above. The stretch is the only sound this shot makes.
local STRETCH_SOUND  = "rbxassetid://9125405388"      -- stomach stretch/groan, played once as the growth starts
local STRETCH_VOLUME = 0.9

-- The shot, in seconds. MOVE_IN is the camera flying in while the belly is HELD at its old size, GROW is the
-- stretch itself, MOVE_OUT hands the camera back. Keep the total near 2.5s: it is an interruption, and a long
-- one stops being a reward.
local MOVE_IN  = 0.45
local GROW     = 1.55
local MOVE_OUT = 0.50
local GRACE    = 0.60 -- no skip-input is accepted for this long, so the tap that bought the gut cannot skip it
local SLOW_PAD = 0.35 -- extra slack on the slow-growth window so the belly is not still moving when we cut

-- Camera path, in the CHARACTER's frame: an arc across the FRONT of the body (so you see the belly, not the
-- back of the head) that dollies in and drops to belly height as it goes.
local START_ANGLE, END_ANGLE = math.rad(-42), math.rad(26)
local START_DIST,  END_DIST  = 9.0, 5.6
local START_LIFT,  END_LIFT  = 2.0, 0.9

--==================== [BellySystem] GEOMETRY ====================
-- Only used on the no-BellyPuff path (space / dino), to keep the weld and the Sag/Sheen/Navel details correct
-- while this script is the one writing the size. MUST match BellySystem.server / BellyPuff.
local EMBED    = 0.40
local TOP_TUCK = 0.30

local function computeC0(torso, sz)
	local torsoFront = -torso.Size.Z * 0.5          -- -Z is forward
	local centerZ    = torsoFront + EMBED - sz.Z * 0.5
	local topY       = torso.Size.Y * 0.32
	local centerY    = topY - sz.Y * 0.5
	local pitch      = math.asin(math.clamp(TOP_TUCK / (sz.Y * 0.5), -0.5, 0.5))
	return CFrame.new(0, centerY, centerZ) * CFrame.Angles(pitch, 0, 0)
end

local function styleGut(gut, sz)
	local sag = gut:FindFirstChild("Sag")
	if sag then
		sag.Size = Vector3.new(sz.X * 1.00, sz.Y * 0.64, sz.Z * 1.00)
		local w = sag:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, -sz.Y * 0.27, -sz.Z * 0.03) end
	end
	local sheen = gut:FindFirstChild("Sheen")
	if sheen then
		sheen.Size = Vector3.new(sz.X * 0.55, sz.Y * 0.50, sz.Z * 0.94)
		local w = sheen:FindFirstChildWhichIsA("Weld"); if w then w.C0 = CFrame.new(0, sz.Y * 0.06, -sz.Z * 0.05) end
	end
	local navel = gut:FindFirstChild("Navel")
	if navel then
		local d = sz.Z * 0.22
		navel.Size = Vector3.new(0.06, d, d)
		local w = navel:FindFirstChildWhichIsA("Weld")
		if w then w.C0 = CFrame.new(0, -sz.Y * 0.05, -sz.Z * 0.5 + 0.03) * CFrame.Angles(0, math.rad(90), 0) end
	end
end

local function writeSize(gut, sz)
	local folder = gut.Parent
	local torso  = folder and folder.Parent -- Gut -> GutBelly folder -> torso
	gut.Size = sz
	local w = gut:FindFirstChildWhichIsA("Weld")
	if w and torso and torso:IsA("BasePart") then w.C0 = computeC0(torso, sz) end
	styleGut(gut, sz)
end

--==================== CHARACTER / BELLY LOOKUP ====================
local function rig()
	local char = player.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return nil end
	return char, hum, hrp
end

local function gutPart()
	local char = player.Character
	if not char then return nil end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso")
	local folder = torso and torso:FindFirstChild("GutBelly")
	local gut = folder and folder:FindFirstChild("Gut")
	if gut and gut:IsA("BasePart") then return gut end
	return nil
end

-- Frame on the belly if there is one, the torso otherwise -- so the shot still points somewhere sane in a
-- realm that has not had the belly installed.
local function focusOf(char, hrp)
	local gut = gutPart()
	if gut then return gut.Position end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	return (torso and torso.Position) or hrp.Position
end

--==================== SOUND ====================
-- Routed through SoundService.SFXGroup where the realm has one, so the Settings "Sound Effects" toggle mutes
-- these like every other cue. Parented to SoundService (not the character) so they are 2D: this is the local
-- player's own purchase, not a noise in the world.
local function playSfx(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume  = volume
	local grp = SoundService:FindFirstChild("SFXGroup")
	if grp and grp:IsA("SoundGroup") then s.SoundGroup = grp end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

--==================== UI STAND-DOWN ====================
local function hideScreenGuis()
	local hidden = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return hidden end
	for _, g in ipairs(pg:GetDescendants()) do
		if g:IsA("ScreenGui") and g.Enabled then
			g.Enabled = false
			hidden[#hidden + 1] = g
		end
	end
	return hidden
end

local function showScreenGuis(hidden)
	for _, g in ipairs(hidden) do
		if g.Parent then pcall(function() g.Enabled = true end) end
	end
end

--==================== THE SHOT ====================
local busy = false

-- LAST KNOWN OLD SIZE, sampled every frame (no-BellyPuff realms only).
--
-- The shot cannot just read gut.Size when it starts. The server resizes the belly in the SAME frame it raises
-- the stomach max, so both replicate together and the size can already be the NEW one by the time the stat's
-- Changed handler runs -- there would be nothing left to animate from and the belly would simply appear big.
-- So the size from two frames ago is kept on hand, which is unambiguously the pre-purchase one.
local prevSize, curSize = nil, nil
RunService.Heartbeat:Connect(function()
	if busy or _G.bellyPuffActive then return end -- BellyPuff realms drive their own size; don't shadow it
	local gut = gutPart()
	if not gut then return end
	prevSize, curSize = curSize, gut.Size
end)

local function smooth(a) -- smoothstep: no snap at either end of a camera move
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function shotCFrame(hrp, focus, a)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude > 1e-3) and flat.Unit or Vector3.new(0, 0, -1)
	local ang  = START_ANGLE + (END_ANGLE - START_ANGLE) * a
	local dist = START_DIST  + (END_DIST  - START_DIST)  * a
	local lift = START_LIFT  + (END_LIFT  - START_LIFT)  * a
	local pos  = focus + (CFrame.Angles(0, ang, 0) * flat) * dist + Vector3.new(0, lift, 0)
	return CFrame.lookAt(pos, focus)
end

local function runCinematic()
	if busy then return end
	local char, hum, hrp = rig()
	if not char then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end

	busy = true
	_G.gutGrowCinematicActive = true

	local savedType    = cam.CameraType
	local savedSubject = cam.CameraSubject
	local savedRel     = hrp.CFrame:ToObjectSpace(cam.CFrame) -- where the camera was RELATIVE to the player, so
	                                                          -- it can be handed back even if they walked
	local hidden = hideScreenGuis()

	-- The no-BellyPuff path drives the size itself: start from the size the sampler was holding before the
	-- purchase, and learn the target the moment the server's new size shows up on the part.
	local drivesBelly = not _G.bellyPuffActive
	local gut      = drivesBelly and gutPart() or nil
	local fromSize = gut and (prevSize or curSize) or nil
	local toSize   = nil

	local cancelled, finished = false, false
	local conns = {}
	local function finish()
		if finished then return end
		finished = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		showScreenGuis(hidden)
		if cam then
			-- Never hand back a nil subject: the default camera would have nothing to follow. Fall back to the
			-- humanoid, which is what it would have been anyway.
			cam.CameraSubject = savedSubject or hum
			-- Never hand back Scriptable: if something else owned the camera when we started, the player would
			-- be left staring at a frozen frame with no way out.
			cam.CameraType = (savedType == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or savedType
		end
		_G.gutGrowHoldUntil = 0
		_G.gutGrowSlowUntil = 0
		_G.gutGrowCinematicActive = nil
		busy = false
	end
	-- THE HUD COMES BACK NO MATTER WHAT. If the loop below throws, yields forever, or the place shuts the
	-- character down mid-shot, this still fires and re-enables everything we disabled.
	task.delay(MOVE_IN + GROW + MOVE_OUT + 5, finish)

	conns[#conns + 1] = hum.Died:Connect(function() cancelled = true end)
	conns[#conns + 1] = player.CharacterRemoving:Connect(function() cancelled = true end)
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Escape
			or input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			cancelled = true
		end
	end)

	cam.CameraType = Enum.CameraType.Scriptable
	local entry     = cam.CFrame -- where the default camera was sitting; the move-in starts from here
	local started   = os.clock()
	local total     = MOVE_IN + GROW + MOVE_OUT
	local stretched = false

	-- Hold the belly at the old size until the camera is framed, then let it grow over GROW.
	_G.gutGrowHoldUntil = started + MOVE_IN
	_G.gutGrowSlowUntil = started + MOVE_IN + GROW + SLOW_PAD

	while not finished do
		RunService.RenderStepped:Wait()
		local t = os.clock() - started
		if t >= total or cancelled then break end

		local live, liveHum, liveHrp = rig()
		if not live or liveHum ~= hum then break end
		-- Walking away cancels it. The camera is Scriptable, so movement input during the orbit is
		-- disorienting; the player asking to move is the player asking for their camera back.
		if t > GRACE and liveHum.MoveDirection.Magnitude > 0.1 then break end

		local focus = focusOf(live, liveHrp)
		if t < MOVE_IN then
			cam.CFrame = entry:Lerp(shotCFrame(liveHrp, focus, 0), smooth(t / MOVE_IN))
		elseif t < MOVE_IN + GROW then
			if not stretched then
				stretched = true
				playSfx(STRETCH_SOUND, STRETCH_VOLUME)
			end
			cam.CFrame = shotCFrame(liveHrp, focus, smooth((t - MOVE_IN) / GROW))
		else
			local a = (t - MOVE_IN - GROW) / MOVE_OUT
			cam.CFrame = shotCFrame(liveHrp, focus, 1):Lerp(liveHrp.CFrame * savedRel, smooth(a))
		end

		if drivesBelly and gut and gut.Parent and fromSize then
			if not toSize and (gut.Size - fromSize).Magnitude > 1e-3 then
				toSize = gut.Size -- the server has finished resizing the moment the part differs from the sample
			end
			if toSize then
				writeSize(gut, fromSize:Lerp(toSize, smooth(math.clamp((t - MOVE_IN) / GROW, 0, 1))))
			else
				writeSize(gut, fromSize) -- freeze at the old size until the new one arrives
			end
		end
	end

	-- Land the belly exactly on its target rather than wherever the loop happened to stop.
	if drivesBelly and gut and gut.Parent and toSize then pcall(writeSize, gut, toSize) end
	finish()
end

--==================== TRIGGER: STOMACH MAX WENT UP ====================
local lastMax = nil

local function onMax(value)
	local v = tonumber(value)
	if not v then return end
	local prev = lastMax
	lastMax = v
	if prev == nil or v <= prev then return end -- first read, a reload, or a shrink: not a purchase

	local landed = false
	local char, hum, hrp = rig()
	if char then
		landed = not _G.isFlying
			and hum.FloorMaterial ~= Enum.Material.Air
			and math.abs(hrp.AssemblyLinearVelocity.Y) < 12
	end
	local cam = Workspace.CurrentCamera
	local camFree = cam ~= nil and not busy and not _G.introPlaying
		and (cam.CameraType == Enum.CameraType.Custom or cam.CameraType == Enum.CameraType.Follow)

	-- Set the hold BEFORE anything yields, so BellyPuff cannot sneak a frame of fast growth in between the
	-- stat replicating and the shot starting.
	if landed and camFree then
		_G.gutGrowHoldUntil = os.clock() + MOVE_IN
		_G.gutGrowSlowUntil = os.clock() + MOVE_IN + GROW + SLOW_PAD
	end

	if not landed then return end  -- airborne: no camera, no stretch. The gut still grows as it always did.
	if not camFree then return end -- an intro / quest / outro cinematic already owns the camera; leave it alone
	task.spawn(runCinematic)
end

--==================== WIRE UP WHATEVER THIS REALM PUBLISHES ====================
-- BOTH sources are wired, and neither waits on the other. No realm publishes the stomach max in both places,
-- so only one of them ever fires -- and wiring them in sequence would have been a 30-second blind spot right
-- after joining in Space Realm, which HAS a leaderstats folder (SkinCrateService builds it for CrateTokens)
-- but keeps the stomach max on an attribute. The WaitForChild for it would simply have timed out.
player:GetAttributeChangedSignal("StomachMax"):Connect(function()
	onMax(player:GetAttribute("StomachMax"))
end)
if player:GetAttribute("StomachMax") ~= nil then onMax(player:GetAttribute("StomachMax")) end

task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 60)
	local sm = ls and ls:WaitForChild("StomachMax", 60)
	if not sm then return end
	onMax(sm.Value)
	sm.Changed:Connect(onMax)
	print("[GutGrow] watching leaderstats.StomachMax")
end)

-- A new character has a new belly at whatever size the tier says; nothing to animate across a respawn.
player.CharacterAdded:Connect(function()
	_G.gutGrowHoldUntil = 0
	_G.gutGrowSlowUntil = 0
end)

task.delay(8, function()
	if not gutPart() then
		warn("[GutGrow] no GutBelly on this character -- the shot will play with nothing to watch. "
			.. "Install the belly by pasting tools/GutBelly_OtherRealms.server.luau into ServerScriptService.")
	end
end)

print("[GutGrow] gut purchase cinematic ready (camera + stretch on a landed buy, no purchase jingle)")
