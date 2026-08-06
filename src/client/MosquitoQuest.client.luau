--======================================================================
-- MosquitoQuest.client.luau  (LocalScript)  -- Island 5 "Misty Mire" swamp quest
--======================================================================
-- THE FLOW:
--   1. Big MOSQUITOS hover/drift in the air above island5 (clickable from the ground).
--   2. Click one -> a "SWAT!" mini-game GUI pops up -> the bug flies around the
--      panel and you hit it each time it LANDS. 12 landings, 1.25s apart, so a
--      mosquito is a flat 15s of hunting however fast you tap (see PickupFloor).
--   3. Squash 5 -> a NEST + dino egg appears on the island.
--   4. Press E to "Feed & Hatch" -> the mosquitos feed the baby dino -> cool hatch -> pet granted.
--
-- Self-contained (like the other island quests). Reward pet is configurable below.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")
local Debris     = game:GetService("Debris")
local player     = Players.LocalPlayer
local HatchBurst   = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst"))   -- shared cool hatch FX
local ChevronTrail = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("ChevronTrail")) -- shared ground chevron guide
local DoneCommand  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("DoneCommand"))  -- "/done" -> skip to the reward egg
local PickupFloor  = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PickupFloor")) -- the 15s-per-collectible floor

local CONFIG = {
	islandName    = "island5",
	count         = 5,            -- mosquitos to squash
	hitsToSwat    = 12,           -- landings you have to connect with to squash one
	escapeIdle    = 6,            -- seconds with NO swing at all before the mosquito escapes
	petId         = "SpinosaurusPet", -- the swamp dino reward
	petName       = "Spinosaurus",
	spawnFollower = "SpawnSpinosaurusFollower",
	hatchEvent    = "SpinosaurusHatched",
}

local st = { caught = 0, busy = false, done = false, hatching = false, owns = false, mossies = {}, swatter = nil }

--======================================================================
-- THE FLY SWATTER -- the MireWatcher hands this over when you accept the quest.
-- Same shape as BurritoDig's shovel: a real Tool with a welded Handle, built on the
-- client. Handle is a cylinder shaft (long axis = local X), so -X is the grip and +X
-- is the pad; Tool.Grip stands it upright in the hand.
--======================================================================
local SW_GRIP   = Color3.fromRGB(32, 34, 40)    -- black rubber grip
local SW_SHAFT  = Color3.fromRGB(70, 74, 84)    -- grey metal shaft
local SW_WIRE   = Color3.fromRGB(150, 158, 170) -- bright metal neck wires
local SW_FRAME  = Color3.fromRGB(150, 32, 42)   -- dark red pad frame
local SW_MESH   = Color3.fromRGB(228, 66, 76)   -- red mesh
local SW_LEN    = 2.4

-- Rest pose of the swatter in the hand. The 180-degree yaw FLIPS the paddle around to
-- face forward; without it the mesh points back at the player. Every smack animates
-- relative to this.
local SW_BASE_GRIP = CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(0, 0, math.rad(90))

-- A proper fly swatter: rubber grip -> metal shaft -> two springy neck wires -> a flat
-- rectangular PADDLE with a framed mesh grid.
--
-- Built in handle-LOCAL space. The Handle is a cylinder, so its long axis is local X:
--   -X = the grip end (what you hold)    +X = the paddle end
-- The paddle is FLAT IN Y -- i.e. its face points up/down like a ping-pong bat, in the
-- same plane as the shaft. (The old pad was thin along X, which made it a lollipop disc
-- stuck on the end of a stick instead of a swatter.)
local function buildSwatterTool()
	local tool = Instance.new("Tool")
	tool.Name = "FlySwatter"
	tool.ToolTip = "Swat the mosquitos!"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"; handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(SW_LEN, 0.15, 0.15)
	handle.Color = SW_SHAFT; handle.Material = Enum.Material.Metal
	handle.CanCollide = false; handle.Massless = true; handle.Anchored = false
	handle.Parent = tool

	local function add(p, localCF)
		p.CanCollide = false; p.Massless = true; p.Anchored = false
		p.CastShadow = false
		p.CFrame = localCF; p.Parent = tool
		local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = p; w.Parent = p
		return p
	end
	local function part(name, shape, size, color, mat, localCF, trans)
		local p = Instance.new("Part")
		p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Transparency = trans or 0
		return add(p, localCF)
	end

	local gripEnd = -SW_LEN / 2 -- -X
	local shaftEnd =  SW_LEN / 2 -- +X

	----------------------------------------------------------------
	-- GRIP: rubber sleeve + three raised finger ridges
	----------------------------------------------------------------
	part("Grip", Enum.PartType.Cylinder, Vector3.new(0.85, 0.24, 0.24), SW_GRIP, Enum.Material.SmoothPlastic,
		CFrame.new(gripEnd + 0.42, 0, 0))
	for i = 0, 2 do
		part("Ridge", Enum.PartType.Cylinder, Vector3.new(0.07, 0.28, 0.28), Color3.fromRGB(20, 21, 25), Enum.Material.SmoothPlastic,
			CFrame.new(gripEnd + 0.20 + i * 0.22, 0, 0))
	end
	-- butt cap with a hanging loop
	part("ButtCap", Enum.PartType.Cylinder, Vector3.new(0.10, 0.30, 0.30), SW_FRAME, Enum.Material.SmoothPlastic,
		CFrame.new(gripEnd + 0.02, 0, 0))

	----------------------------------------------------------------
	-- NECK: two springy wires fanning from the shaft out to the paddle
	----------------------------------------------------------------
	local padCX  = shaftEnd + 1.15 -- paddle centre, out past the shaft
	local padLen = 2.10            -- along the shaft (X)
	local padWid = 1.80            -- across       (Z)
	local padThk = 0.07            -- flat in Y

	for _, sgn in ipairs({ 1, -1 }) do
		-- angled strut from the shaft tip to the near corner of the paddle
		local a = Vector3.new(shaftEnd - 0.05, 0, 0)
		local b = Vector3.new(padCX - padLen / 2, 0, (padWid / 2 - 0.18) * sgn)
		local mid, len = (a + b) / 2, (b - a).Magnitude
		part("NeckWire", Enum.PartType.Cylinder, Vector3.new(len, 0.075, 0.075), SW_WIRE, Enum.Material.Metal,
			CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0))
	end

	----------------------------------------------------------------
	-- PADDLE: framed mesh grid, flat in Y (face up/down)
	----------------------------------------------------------------
	-- frame: two long rails (along X) + two end bars (along Z)
	for _, sgn in ipairs({ 1, -1 }) do
		part("FrameRail", Enum.PartType.Block, Vector3.new(padLen, 0.10, 0.13), SW_FRAME, Enum.Material.SmoothPlastic,
			CFrame.new(padCX, 0, (padWid / 2) * sgn))
		part("FrameEnd", Enum.PartType.Block, Vector3.new(0.13, 0.10, padWid + 0.13), SW_FRAME, Enum.Material.SmoothPlastic,
			CFrame.new(padCX + (padLen / 2) * sgn, 0, 0))
	end

	-- the mesh itself: a lattice of thin bars, slightly see-through
	for i = -2, 2 do -- bars running ACROSS the paddle (along Z)
		part("MeshBarZ", Enum.PartType.Block, Vector3.new(0.08, padThk, padWid - 0.06), SW_MESH, Enum.Material.SmoothPlastic,
			CFrame.new(padCX + i * (padLen / 6), 0, 0), 0.25)
	end
	for i = -2, 2 do -- bars running ALONG the paddle (along X)
		part("MeshBarX", Enum.PartType.Block, Vector3.new(padLen - 0.06, padThk, 0.08), SW_MESH, Enum.Material.SmoothPlastic,
			CFrame.new(padCX, 0, i * (padWid / 6)), 0.25)
	end

	-- Stand it upright in the hand. The extra 180-degree yaw FLIPS the paddle round so it
	-- faces forward (away from the player) instead of back at them.
	tool.Grip = SW_BASE_GRIP
	return tool
end

--======================================================================
-- SMACK! -- the actual swatting swing.
--======================================================================
-- The ARM does the swinging, not just the tool.
--
-- Tweening Tool.Grip alone (which is what this used to do) only slides the swatter
-- around relative to the hand -- the arm stays frozen at its side, so there is barely
-- anything to see. To make a real swat we drive the character's RIGHT SHOULDER Motor6D
-- and rotate the whole arm through an overhead swing, with the Grip snapping the wrist
-- on top of it.
--
-- Works on R15 (RightUpperArm.RightShoulder) and R6 (Torso["Right Shoulder"]).
--
-- The C0 is re-applied every RenderStepped for the duration of the swing. That matters:
-- Roblox's default animations write to these same Motor6Ds every frame, so a one-shot
-- assignment gets stomped instantly. Writing in RenderStepped lands AFTER the animator,
-- so the swing wins. The original C0 is restored when the swing ends.
local function rightArmMotor(char: Instance): Motor6D?
	local rua = char:FindFirstChild("RightUpperArm") -- R15
	if rua then
		local m = rua:FindFirstChild("RightShoulder")
		if m and m:IsA("Motor6D") then return m end
	end
	local torso = char:FindFirstChild("Torso") -- R6
	if torso then
		local m = torso:FindFirstChild("Right Shoulder")
		if m and m:IsA("Motor6D") then return m end
	end
	return nil
end

local SWING_TIME = 0.42 -- whole swing: wind-up + strike + recover

-- pitch of the arm through the swing, in radians. Negative = cocked back over the head,
-- positive = swung down and through. Deliberately asymmetric: a slow-ish wind-up and a
-- very fast strike is what reads as a "smack" rather than a wave.
local function swingPitch(a: number): number
	if a < 0.30 then                       -- wind up (back over the shoulder)
		return -1.45 * (a / 0.30)
	elseif a < 0.45 then                   -- STRIKE (fast, whips past the rest pose)
		local k = (a - 0.30) / 0.15
		return -1.45 + (1.45 + 1.25) * k   -- -1.45 -> +1.25
	else                                   -- recover back to rest
		local k = (a - 0.45) / 0.55
		return 1.25 * (1 - k * k)          -- ease out
	end
end

local smacking = false
local function smackSwatter()
	if smacking then return end
	local char = player.Character
	local tool = char and char:FindFirstChild("FlySwatter")
	if not tool then return end

	local motor = rightArmMotor(char)
	local baseC0 = motor and motor.C0
	smacking = true

	task.spawn(function()
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local a = (os.clock() - t0) / SWING_TIME
			if a >= 1 or not (tool.Parent and char.Parent) then
				if conn then conn:Disconnect() end
				-- hand the arm back to the normal animations
				if motor and baseC0 and motor.Parent then
					pcall(function() motor.C0 = baseC0 end)
				end
				pcall(function() tool.Grip = SW_BASE_GRIP end)
				smacking = false
				return
			end

			local pitch = swingPitch(a)

			-- swing the ARM
			if motor and baseC0 and motor.Parent then
				pcall(function()
					motor.C0 = baseC0 * CFrame.Angles(pitch, 0, 0)
				end)
			end

			-- ...and snap the WRIST on top of it, so the paddle leads the hit
			pcall(function()
				tool.Grip = SW_BASE_GRIP * CFrame.Angles(pitch * 0.55, 0, 0)
			end)
		end)
	end)
end

-- Is the player actually holding the swatter right now?
local function holdingSwatter()
	local char = player.Character
	return char ~= nil and char:FindFirstChild("FlySwatter") ~= nil
end

--======================================================================
-- CLICKING A MOSQUITO **WHILE HOLDING THE SWATTER**
--======================================================================
-- THE BUG THIS SOLVES: in Roblox, once a Tool is EQUIPPED, a left-click is routed to
-- the Tool (it fires Tool.Activated) and ClickDetectors DO NOT FIRE AT ALL.
--
-- So the behaviour was exactly backwards:
--   * no swatter  -> ClickDetector fires -> "Talk to the MireWatcher..." hint. Works.
--   * swatter out -> Roblox gives the click to the Tool, the ClickDetector goes silent,
--                    and nothing happens. The one item you need to swat with was the
--                    one thing that disabled swatting.
--
-- So while the swatter is held we do our OWN hit-testing: listen for the raw click/tap
-- via UserInputService, raycast from the camera through the click point, and see if it
-- lands on a mosquito's hitbox. UIS fires regardless of what Tool is equipped, and it
-- covers mouse AND touch, so mobile works the same way.
--
-- st.targets maps a mosquito's HitBox part -> the function that starts its swat.
-- It is filled in as each mosquito is spawned (see BOOT).
local UIS = game:GetService("UserInputService")
local CLICK_RANGE = 60 -- studs; must match the ClickDetector's MaxActivationDistance

-- E-PROMPT RANGE. The mosquitos had NO prompt at all -- only the two click paths above --
-- so there was never an "E" to see. Each mosquito now carries a ProximityPrompt at this
-- range as a third path (see PATH 3 at the spawn site).
--
-- MEASURED TO THE BUG'S HOME POINT, NOT TO THE BUG. The drift loop swings a mosquito
-- +/-6 studs on X and Z, which is most of this budget on its own -- so range taken from
-- the moving body would open and close the prompt while the player stood still. PATH 3
-- hangs it on a stationary anchor instead, so only walking moves you in or out of range.
--
-- Height still counts against it: bugs hover HOVER_MIN..HOVER_MAX studs up and Roblox
-- measures from the CHARACTER, so standing under the highest ones already spends ~8 of it.
-- 12 leaves room for that. If any stay stubborn, lower HOVER_MAX rather than raising this.
local SWAT_PROMPT_RANGE = 12 -- studs

st.targets = {}

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end -- click landed on UI (e.g. the swat mini-game panel)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	-- No swatter? Do nothing here -- the ClickDetector still fires in that case and
	-- shows the "you need a swatter" hint. Handling it here too would double-fire.
	if not holdingSwatter() then return end
	if st.busy or st.done then return end

	local cam = Workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and hrp) then return end

	local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char } -- never hit the player or the swatter in their hand
	local res = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	if not res then return end

	local start = st.targets[res.Instance]
	if not start then return end -- clicked something that isn't a mosquito

	-- same range gate the ClickDetector would have applied
	if (res.Instance.Position - hrp.Position).Magnitude > CLICK_RANGE then
		return
	end
	start()
end)

-- Give the swatter (once). Called when the MireWatcher's quest is accepted.
local function giveSwatter()
	if st.swatter then return end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	if not backpack then warn("[Mosquito] no Backpack -> cannot hand over the Fly Swatter"); return end
	st.swatter = buildSwatterTool()
	st.swatter.Parent = backpack
	print("[Mosquito] MireWatcher handed over the Fly Swatter")
end

-- ===== generic helpers =====
local function floatText(pos, text, color)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,220,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.MaxDistance=120; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=color or Color3.fromRGB(180,230,140); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.6, function() a:Destroy() end)
end

-- ===== top HUD counter =====
local hudLbl
local function buildHUD()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "MosquitoHUD"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 60; g.Parent = pgui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0); f.Position = UDim2.new(0.5,0,0,92); f.Size = UDim2.fromOffset(240,40)
	f.BackgroundColor3 = Color3.fromRGB(122,142,82); f.BackgroundTransparency = 0.1; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,12); local s = Instance.new("UIStroke", f); s.Color = Color3.fromRGB(40,52,38); s.Thickness = 2
	hudLbl = Instance.new("TextLabel"); hudLbl.Size = UDim2.new(1,0,1,0); hudLbl.BackgroundTransparency = 1
	hudLbl.Font = Enum.Font.FredokaOne; hudLbl.TextScaled = true; hudLbl.TextColor3 = Color3.fromRGB(250,242,214); hudLbl.Parent = f
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = hudLbl end
	-- only show the HUD while the player is ON island5 (so it doesn't clutter other islands)
	task.spawn(function()
		while g.Parent do
			local isl = Workspace:FindFirstChild(CONFIG.islandName)
			local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local on = false
			if isl and hrp then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok then local d = hrp.Position - cf.Position; on = math.abs(d.X) <= size.X/2 + 35 and math.abs(d.Z) <= size.Z/2 + 35 and math.abs(d.Y) <= size.Y/2 + 80 end -- Y too (islands stack vertically)
			end
			g.Enabled = on and not st.owns
			task.wait(0.5)
		end
	end)
	return g
end
local function updateHUD()
	if hudLbl then hudLbl.Text = ("\xF0\x9F\xA6\x9F  Mosquitos: %d / %d"):format(st.caught, CONFIG.count) end
end

-- ===== a big, clearly-visible mosquito model =====
local function buildMosquito(homePos)
	local m = Instance.new("Model"); m.Name = "SwampMosquito"
	local function p(name, shape, sz, color, rel, trans)
		local pt = Instance.new("Part"); pt.Name=name; pt.Shape=shape; pt.Size=sz; pt.Color=color; pt.Material=Enum.Material.SmoothPlastic
		pt.Transparency = trans or 0; pt.Anchored=true; pt.CanCollide=false; pt.CanQuery=true; pt.CastShadow=false
		pt.CFrame = CFrame.new(homePos) * rel; pt.Parent = m; return pt
	end
	local DARK = Color3.fromRGB(58,64,52); local WING = Color3.fromRGB(205,224,212)
	local body = p("Body", Enum.PartType.Ball, Vector3.new(1.4,1.2,3.0), DARK, CFrame.new()) -- thorax + abdomen, big enough to see
	m.PrimaryPart = body
	p("Head", Enum.PartType.Ball, Vector3.new(1.1,1.1,1.1), DARK, CFrame.new(0,0.15,1.7))
	p("Proboscis", Enum.PartType.Cylinder, Vector3.new(1.8,0.14,0.14), Color3.fromRGB(35,35,35), CFrame.new(0,0,2.8)*CFrame.Angles(0,math.rad(90),0))
	for _, sgn in ipairs({1,-1}) do
		p("Eye", Enum.PartType.Ball, Vector3.new(0.38,0.38,0.38), Color3.fromRGB(190,40,40), CFrame.new(0.34*sgn,0.3,2.0))
		p("Wing", Enum.PartType.Block, Vector3.new(2.8,0.07,1.2), WING, CFrame.new(1.9*sgn,0.6,0.1)*CFrame.Angles(0,0,math.rad(22*sgn)), 0.5)
		for _, lz in ipairs({0.7,0,-0.7}) do
			p("Leg", Enum.PartType.Cylinder, Vector3.new(1.8,0.09,0.09), DARK, CFrame.new(0.5*sgn,-0.5,lz)*CFrame.Angles(0,0,math.rad(58*sgn))*CFrame.Angles(0,math.rad(18),0))
		end
	end
	-- BIG INVISIBLE HITBOX. The mosquito itself is a fiddly little thing made of thin
	-- wings and legs -- clicking/tapping the actual model is frustrating, especially on
	-- a phone. This is a fat invisible ball around it that swallows the click instead.
	-- The ClickDetector goes on THIS, not on the body, so the whole area around the bug
	-- is tappable.
	--
	-- Transparency = 1 but CanQuery = true: invisible, still hit by the click raycast.
	-- CanCollide = false so the player never walks into an invisible wall in mid-air.
	--
	-- The mosquito's own parts are made NON-queryable just below, so a click ray can only
	-- ever land on this hitbox -- never on a wing or a leg. That keeps the hit-test to a
	-- single unambiguous part.
	local hit = Instance.new("Part")
	hit.Name = "HitBox"
	hit.Shape = Enum.PartType.Ball
	hit.Size = Vector3.new(9, 9, 9) -- generous: ~3x the mosquito's own body
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanQuery = true
	hit.CanTouch = false
	hit.CastShadow = false
	hit.CFrame = CFrame.new(homePos)
	hit.Parent = m

	-- only the hitbox is click-testable; the visual parts are not
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hit then d.CanQuery = false end
	end

	m.Parent = Workspace
	return m, body, hit
end

-- ===== the SWAT mini-game: a MOVING TARGET over the mire, not a mash button =====
--
-- FORCED CADENCE (PickupFloor pattern 2), and a mechanic of its own.
--
-- This used to be six taps on a fixed button against a five-second clock -- the exact
-- same panel island11's geyser uses, and beaten in about a second and a half. Two
-- things were wrong with that: the swamp's collectible cost nothing, and two islands
-- shipped the same minigame with different colours.
--
-- Now the mosquito FLIES. It flits across the mire for RELOCATE seconds, lands
-- somewhere new, and only then can be hit; connect, and it takes off again. So the gap
-- between hits is a hard floor no tap rate can shorten -- HITS x RELOCATE IS the 15s,
-- and mashing the panel hits empty air. The skill is aim, not speed: 12 swings across
-- 15 seconds is 0.8/sec, nowhere near the ~2.7/sec mobile ceiling.
--
-- cadence() solves for (N-1) gaps because it assumes the first action is free. Here
-- every hit is preceded by a flight, including the first, so this divides by HITS.
local function openSwatMinigame(onDone)
	local pgui = player:WaitForChild("PlayerGui")
	local HITS         = CONFIG.hitsToSwat
	local RELOCATE     = PickupFloor.SECONDS / HITS   -- 1.25s in the air between landings
	-- WAS 0.10 -- halved to 0.05 by request. A whiff (tapping the mire instead of the bug)
	-- now costs ~5% of the bar, a little over half a hit's worth of 1/12. The LOCKOUT below
	-- is untouched, so a miss still interrupts your rhythm; it just no longer erases much.
	--
	-- This does NOT make the minigame faster. HITS x RELOCATE is the floor and misses are
	-- pure loss on top of it, so a clean run took 15s before and takes 15s now -- what got
	-- cheaper is being sloppy. Raising this is the difficulty dial; it is not a time dial.
	local MISS_PENALTY = 0.05                          -- a whiff costs ~5% of the bar...
	local MISS_LOCKOUT = 0.45                          -- ...plus a short lockout. No hard fail.

	local g = Instance.new("ScreenGui"); g.Name = "SwatGui"; g.ResetOnSpawn = false; g.DisplayOrder = 210; g.Parent = pgui
	local dim = Instance.new("TextButton"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false; dim.Text = ""; dim.Modal = true; dim.Active = true; dim.Parent = g -- sinks input; tapping it never closes the panel
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromOffset(330,300); panel.Position = UDim2.fromScale(0.5,0.5); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local g2 = Instance.new("UIGradient"); g2.Rotation = 90; g2.Color = ColorSequence.new(Color3.fromRGB(126,146,86), Color3.fromRGB(118,138,80)); g2.Parent = panel
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-56,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "SWAT THE MOSQUITO!"; title.Parent = panel

	-- the mire the bug flies over. Tapping the FIELD is a miss; tapping the BUG is a hit.
	local field = Instance.new("TextButton"); field.Size = UDim2.new(1,-24,0,186); field.Position = UDim2.new(0,12,0,50)
	field.BackgroundColor3 = Color3.fromRGB(74,92,56); field.AutoButtonColor = false; field.Text = ""; field.ClipsDescendants = true; field.Parent = panel
	Instance.new("UICorner", field).CornerRadius = UDim.new(0,12)
	local fs = Instance.new("UIStroke", field); fs.Color = Color3.fromRGB(40,52,38); fs.Thickness = 2
	local bug = Instance.new("TextButton"); bug.Size = UDim2.fromOffset(58,58); bug.AnchorPoint = Vector2.new(0.5,0.5)
	bug.BackgroundTransparency = 1; bug.AutoButtonColor = false; bug.Font = Enum.Font.FredokaOne; bug.TextScaled = true
	bug.Text = "\xF0\x9F\xA6\x9F"; bug.ZIndex = 3; bug.Parent = field
	-- hit/miss feedback flashes THIS overlay, not the field's own colour: a reversing
	-- tween on the field itself can be caught mid-flight by the next hit and leave the
	-- mire stuck green. A plain Frame doesn't sink input, so the field still gets misses.
	local flash = Instance.new("Frame"); flash.Size = UDim2.fromScale(1,1); flash.BackgroundColor3 = Color3.fromRGB(150,200,110)
	flash.BackgroundTransparency = 1; flash.BorderSizePixel = 0; flash.ZIndex = 2; flash.Parent = field
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0,12)
	local function flashField(color)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.45
		TS:Create(flash, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
	end

	local barBg = Instance.new("Frame"); barBg.Size = UDim2.new(1,-40,0,18); barBg.Position = UDim2.new(0,20,1,-26); barBg.AnchorPoint = Vector2.new(0,1)
	barBg.BackgroundColor3 = Color3.fromRGB(40,52,38); barBg.Parent = panel; Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,9)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(0,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(126,217,87); bar.BorderSizePixel = 0; bar.Parent = barBg; Instance.new("UICorner", bar).CornerRadius = UDim.new(0,9)
	local hint = Instance.new("TextLabel"); hint.Size = UDim2.new(1,-24,0,20); hint.Position = UDim2.new(0,12,1,-50); hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham; hint.TextSize = 13; hint.TextColor3 = Color3.fromRGB(240,246,220); hint.Text = "Wait for it to land \xE2\x80\x94 then hit it"; hint.Parent = panel

	-- "He Landed" -- THE LANDED CUE, called out in red across the top of the mire.
	--
	-- The hint line above already switches wording when the bug settles, but at 13px in
	-- off-white it reads as static furniture -- players were missing the one moment in the
	-- whole mini-game that matters, since a swing while it is still FLYING is a guaranteed
	-- miss. Same information, at callout size, in a colour that cannot be mistaken for
	-- background. Shown ONLY while the bug is actually hittable.
	--
	-- TextLabel, NOT a Frame or TextButton: labels do not sink input (same reason the flash
	-- overlay is a plain Frame), so a tap that happens to land on these letters still counts
	-- as a MISS on the mire underneath instead of silently doing nothing.
	local landedCue = Instance.new("TextLabel")
	landedCue.Name = "LandedCue"
	landedCue.Size = UDim2.new(1, -16, 0, 30)
	landedCue.Position = UDim2.new(0, 8, 0, 6)
	landedCue.BackgroundTransparency = 1
	landedCue.Font = Enum.Font.FredokaOne
	landedCue.TextScaled = true
	landedCue.TextColor3 = Color3.fromRGB(236, 64, 54)
	landedCue.TextStrokeColor3 = Color3.fromRGB(28, 12, 10)
	landedCue.TextStrokeTransparency = 0.3
	landedCue.Text = "He Landed"
	landedCue.ZIndex = 4 -- above the bug (3) and the hit/miss flash (2)
	landedCue.Visible = false
	landedCue.Parent = field

	local done, fill = false, 0
	local function finish(win) if done then return end; done = true; pcall(function() g:Destroy() end); if onDone then onDone(win) end end
	-- X closes it (the mosquito stays alive); the Modal backdrop never does
	PickupFloor.addCloseButton(panel, function() finish(false) end)

	-- flight state: "flying" -> untouchable, crossing the mire; "landed" -> hittable
	local state, tState = "flying", os.clock()
	local fromX, fromY = 0.5, 0.5
	local toX, toY = 0.5, 0.5
	local vx, vy = 0, 0
	local lastAction, lockedUntil = os.clock(), 0
	local function takeOff()
		fromX, fromY = toX, toY
		toX = 0.12 + math.random() * 0.76
		toY = 0.16 + math.random() * 0.68
		vx  = (math.random() - 0.5) * 0.16 -- gentle drift once it settles, so it's never a static button
		vy  = (math.random() - 0.5) * 0.12
		state = "flying"; tState = os.clock()
	end
	takeOff(); fromX, fromY = 0.5, 0.10 -- the first one flies in from the top of the mire

	bug.Activated:Connect(function()
		local now = os.clock()
		if done or state ~= "landed" or now < lockedUntil then return end
		lastAction = now
		smackSwatter() -- swing the swatter in-hand
		fill = math.min(1, fill + 1 / HITS)
		bar.Size = UDim2.new(fill, 0, 1, 0)
		flashField(Color3.fromRGB(150,200,110))
		-- >= 0.995, not >= 1: 1/HITS is inexact in binary and MISS_PENALTY is a decimal, so
		-- the two can cancel a hair short of 1.0 and leave a full-looking bar wanting one
		-- more hit. Eleven hits is 0.917, so this can never let a hit count for two.
		if fill >= PickupFloor.DONE then finish(true); return end
		takeOff() -- it gets away and resettles -- THIS is the floor
	end)
	field.Activated:Connect(function()
		local now = os.clock()
		if done or now < lockedUntil then return end
		lastAction = now
		smackSwatter()
		fill = math.max(0, fill - MISS_PENALTY)
		bar.Size = UDim2.new(fill, 0, 1, 0)
		lockedUntil = now + MISS_LOCKOUT
		flashField(Color3.fromRGB(190,80,66))
	end)

	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.1); last = now
			local px, py
			if state == "flying" then
				local a = math.clamp((now - tState) / RELOCATE, 0, 1)
				px = fromX + (toX - fromX) * a
				py = fromY + (toY - fromY) * a - math.sin(a * math.pi) * 0.14 -- little hop through the air
				bug.TextTransparency = 0.45
				if a >= 1 then state = "landed"; tState = now; bug.TextTransparency = 0 end
			else
				toX += vx * dt; toY += vy * dt
				if toX < 0.10 or toX > 0.90 then vx = -vx end
				if toY < 0.14 or toY > 0.86 then vy = -vy end
				toX = math.clamp(toX, 0.10, 0.90); toY = math.clamp(toY, 0.14, 0.86)
				px, py = toX, toY
			end
			bug.Position = UDim2.fromScale(px, py)
			bug.Rotation = math.sin(now * 7) * 14
			hint.Text = (state == "landed") and "It's landed \xE2\x80\x94 HIT IT!" or "Wait for it to land \xE2\x80\x94 then hit it"
			landedCue.Visible = (state == "landed") -- red callout tracks the hittable window exactly
			if now - lastAction > CONFIG.escapeIdle then finish(false); break end -- stopped swinging -> it escapes
			task.wait()
		end
	end)
end

-- ===== squash splat =====
local function squashMosquito(m)
	local pos = m:GetPivot().Position
	local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(1,1,1); fx.CFrame=CFrame.new(pos); fx.Parent=Workspace
	local em = Instance.new("ParticleEmitter"); em.Texture="rbxasset://textures/particles/smoke_main.dds"
	em.Color=ColorSequence.new(Color3.fromRGB(130,170,90)); em.Lifetime=NumberRange.new(0.4,0.8); em.Speed=NumberRange.new(7,14)
	em.SpreadAngle=Vector2.new(180,180); em.Size=NumberSequence.new(1.4,0); em.Rate=0; em.Parent=fx; em:Emit(22)
	Debris:AddItem(fx, 1.1)
	floatText(pos + Vector3.new(0,1,0), "Squashed!")
	pcall(function() m:Destroy() end)
end

-- ===== the reward: dino egg + nest -> feed & hatch =====
local function hatchEgg(eggModel, visual, baseCF, eggPos)
	if st.hatching or st.owns then return end
	st.hatching = true
	if visual then local t0 = os.clock()
		while os.clock()-t0 < 0.9 and visual.Parent do local p=(os.clock()-t0)/0.9; local amp=0.1+p*p*0.95
			pcall(function() visual:PivotTo(baseCF * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*70),0)) end); task.wait() end
		pcall(function() visual:Destroy() end)
	end
	HatchBurst.play(eggPos + Vector3.new(0,1,0), Color3.fromRGB(180,200,150)) -- cool hatch
	floatText(eggPos + Vector3.new(0,3,0), CONFIG.petName .. " hatched! \xF0\x9F\xA5\x9A")
	local grantCF = CFrame.new(eggPos)
	if _G[CONFIG.spawnFollower] then pcall(function() _G[CONFIG.spawnFollower](grantCF) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet(CONFIG.petId, { petId=CONFIG.petId, displayName=CONFIG.petName, level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	do local he = RS:FindFirstChild(CONFIG.hatchEvent); if he then pcall(function() he:FireServer() end) end end
	st.owns = true; st.hatching = false
	task.delay(1.4, function() if eggModel then pcall(function() eggModel:Destroy() end) end end)
	print("[Mosquito] island5 quest complete -> " .. CONFIG.petName .. " hatched")
end

-- ===== FEED mini-game: tap to feed each caught mosquito to the egg (gives the "feeding" feel before it hatches) =====
local function openFeedMinigame(onDone)
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "FeedGui"; g.ResetOnSpawn = false; g.DisplayOrder = 210; g.Parent = pgui
	local dim = Instance.new("TextButton"); dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.5
	dim.AutoButtonColor = false; dim.Text = ""; dim.Modal = true; dim.Active = true; dim.Parent = g
	local panel = Instance.new("Frame"); panel.Size = UDim2.fromOffset(320,300); panel.Position = UDim2.fromScale(0.5,0.5); panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = g
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16); local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local gr = Instance.new("UIGradient"); gr.Rotation = 90; gr.Color = ColorSequence.new(Color3.fromRGB(126,146,86), Color3.fromRGB(118,138,80)); gr.Parent = panel
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1,-20,0,34); title.Position = UDim2.new(0,10,0,10); title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "FEED THE EGG!"; title.Parent = panel
	local eggIco = Instance.new("TextLabel"); eggIco.Size = UDim2.fromOffset(120,120); eggIco.Position = UDim2.new(0.5,0,0,50); eggIco.AnchorPoint = Vector2.new(0.5,0)
	eggIco.BackgroundTransparency = 1; eggIco.Font = Enum.Font.FredokaOne; eggIco.TextScaled = true; eggIco.Text = "\xF0\x9F\xA5\x9A"; eggIco.Parent = panel
	local counter = Instance.new("TextLabel"); counter.Size = UDim2.new(1,-20,0,24); counter.Position = UDim2.new(0,10,0,174); counter.BackgroundTransparency = 1
	counter.Font = Enum.Font.GothamBold; counter.TextScaled = true; counter.TextColor3 = Color3.fromRGB(250,242,214); counter.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = counter end
	local feed = Instance.new("TextButton"); feed.Size = UDim2.fromOffset(190,66); feed.Position = UDim2.new(0.5,0,1,-72); feed.AnchorPoint = Vector2.new(0.5,0)
	feed.BackgroundColor3 = Color3.fromRGB(90,170,90); feed.Font = Enum.Font.FredokaOne; feed.TextScaled = true; feed.TextColor3 = Color3.new(1,1,1); feed.Text = "\xF0\x9F\xA6\x9F  FEED"; feed.Parent = panel
	Instance.new("UICorner", feed).CornerRadius = UDim.new(0,14); Instance.new("UIStroke", feed).Color = Color3.fromRGB(40,80,40)
	local left, done = CONFIG.count, false
	local function refresh() counter.Text = ("Mosquitos to feed: %d"):format(left) end
	refresh()
	feed.Activated:Connect(function()
		if done then return end
		left -= 1; refresh()
		-- a mosquito flies up into the egg, and the egg "chomps" (scale punch + yum face)
		local fly = Instance.new("TextLabel"); fly.Size = UDim2.fromOffset(40,40); fly.AnchorPoint = Vector2.new(0.5,0.5); fly.Position = UDim2.new(0.5,0,1,-104)
		fly.BackgroundTransparency = 1; fly.Font = Enum.Font.FredokaOne; fly.TextScaled = true; fly.Text = "\xF0\x9F\xA6\x9F"; fly.ZIndex = 3; fly.Parent = panel
		TS:Create(fly, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5,0,0,110), Size = UDim2.fromOffset(8,8), TextTransparency = 1 }):Play()
		task.delay(0.32, function() fly:Destroy() end)
		eggIco.Text = "\xF0\x9F\x98\x8B"
		TS:Create(eggIco, TweenInfo.new(0.12), { Size = UDim2.fromOffset(142,142) }):Play()
		task.delay(0.16, function() TS:Create(eggIco, TweenInfo.new(0.12), { Size = UDim2.fromOffset(120,120) }):Play(); task.delay(0.14, function() if not done then eggIco.Text = "\xF0\x9F\xA5\x9A" end end) end)
		if left <= 0 then
			done = true; counter.Text = "Yum! It's hatching..."
			task.delay(0.55, function() pcall(function() g:Destroy() end); if onDone then onDone() end end)
		end
	end)
end

local function spawnEggNest(center)
	-- Guide the player to the reward egg with the SAME green chevron runway island1 and
	-- island11 use. This matters most here: the egg appears at EggSpot5, which can be
	-- right across the island from wherever you swatted the last mosquito.
	ChevronTrail.guideToEgg(
		function() return center end,
		function() return st.owns end, -- hatched -> trail + hint tear themselves down
		"All mosquitos swatted! Follow the arrows to the egg!"
	)

	local egg = Instance.new("Model"); egg.Name = "MosquitoRewardEgg"
	local function part(name, sh, sz, col, cf, mat)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	-- twig nest
	local nestCenter = CFrame.new(center + Vector3.new(0, 0.5, 0))
	for k = 1, 12 do
		local a = (k-1) * (2*math.pi/12)
		local twig = part("Twig", Enum.PartType.Cylinder, Vector3.new(2.2,0.5,0.5), Color3.fromRGB(96,70,42), nestCenter * CFrame.Angles(0,a,0) * CFrame.new(0,0,2.4) * CFrame.Angles(0,math.rad(90),math.rad(16)), Enum.Material.Wood)
	end
	-- egg
	local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
	local shell = Instance.new("Part"); shell.Name="Shell"; shell.Shape=Enum.PartType.Ball; shell.Size=Vector3.new(1,1,1); shell.Color=Color3.fromRGB(196,212,160); shell.Material=Enum.Material.SmoothPlastic; shell.Reflectance=0.05
	shell.Anchored=true; shell.CanCollide=false; shell.CanQuery=false; shell.Parent=visual
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType=Enum.MeshType.Sphere; mesh.Scale=Vector3.new(3.0,4.0,3.0); mesh.Parent=shell
	visual.PrimaryPart = shell
	for j = 1, 8 do local a=(j-1)*(2*math.pi/8); local y=math.sin(a*1.7)*1.0; local r=1.3*math.sqrt(math.max(0,1-(y/2)^2))+0.05
		part("Spot", Enum.PartType.Ball, Vector3.new(0.45,0.45,0.45), Color3.fromRGB(120,150,90), shell.CFrame * CFrame.new(math.sin(a)*r, y, math.cos(a)*r)) end
	local baseCF = CFrame.new(center + Vector3.new(0, 1.9, 0)) -- egg rests in the nest ON the spot (not floating)
	visual:PivotTo(baseCF)
	egg.Parent = Workspace
	local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(180,230,140); hl.FillTransparency=0.5; hl.OutlineColor=Color3.fromRGB(120,200,90); hl.DepthMode=Enum.HighlightDepthMode.Occluded; hl.Adornee=visual; hl.Parent=egg
	-- gentle bob
	task.spawn(function() local t=0 while egg.Parent and not st.hatching do t+=0.05; pcall(function() visual:PivotTo(baseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end); task.wait(0.05) end end)
	-- prompt
	local pp = Instance.new("ProximityPrompt"); pp.ActionText="Feed & Hatch"; pp.ObjectText="Hungry Egg"; pp.KeyboardKeyCode=Enum.KeyCode.E; pp.HoldDuration=0.4; pp.MaxActivationDistance=14; pp.RequiresLineOfSight=false; pp.Parent=shell
	pp.Triggered:Connect(function()
		if st.hatching or st.owns then return end
		pp.Enabled = false
		openFeedMinigame(function() hatchEgg(egg, visual, baseCF, center + Vector3.new(0,1.9,0)) end) -- feed first, THEN hatch
	end)
	floatText(center + Vector3.new(0,4.2,0), "Feed the mosquitos to the egg!", Color3.fromRGB(230,236,150))
	print("[Mosquito] all mosquitos squashed -> reward egg + nest spawned")
end

-- ===== BOOT: find island5, spawn the swarm, run the quest =====
task.spawn(function()
	local isl = Workspace:FindFirstChild(CONFIG.islandName) or Workspace:WaitForChild(CONFIG.islandName, 60)
	if not isl then warn("[Mosquito] " .. CONFIG.islandName .. " not found -> swamp quest skipped"); return end

	--------------------------------------------------------------------
	-- WAIT FOR ISLAND 5 TO STREAM IN. This is why the swarm bunched up.
	--------------------------------------------------------------------
	-- StreamingEnabled: island5's Model replicates at join, its PARTS do not -- they
	-- arrive when the player nears it. Until then GetBoundingBox() returns size (0,0,0),
	-- so the ring radius below collapsed to its 22-stud floor and the surface raycast
	-- missed, dumping all 5 mosquitos in one tight clump at the island's pivot height.
	local function islandHasStreamedIn()
		local ok, _, size = pcall(function() return isl:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end
	if not islandHasStreamedIn() then
		print("[Mosquito] island5 has not streamed in yet (0 parts on this client) -- waiting until the player reaches it...")
		while not islandHasStreamedIn() do task.wait(1) end
		print("[Mosquito] island5 streamed in -> spawning the swarm across the real island")
	end

	local bcf, bsize = isl:GetBoundingBox()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { player.Character }
	local topY = bcf.Position.Y + bsize.Y/2

	--------------------------------------------------------------------
	-- FIND THE REAL WALKABLE GROUND HEIGHT.
	--------------------------------------------------------------------
	-- This USED to be a single downward raycast at the island's centre. On island5 --
	-- a swamp full of tall trees -- that ray hits a TREE CANOPY, not the ground:
	--     centre ray  -> Y 9816     (a treetop)
	--     NPCSpot5    -> Y 9728     (actual ground: the MireWatcher stands on it)
	-- ...so every mosquito was being hovered 5-11 studs above the CANOPY, ~95 studs up
	-- in the sky, which is exactly the "bugs are very high in the air" bug.
	--
	-- Ground truth, best source first:
	--   1. The MireWatcher NPC. The server stood him on the island's own NPCSpot5
	--      marker, so the bottom of his bounding box IS the ground the player walks on.
	--   2. The NPCSpot5 / any *NPCSpot* marker directly.
	--   3. Median of many sample rays. Trees cover a minority of the island's area, so
	--      the MEDIAN hit is ground while canopy hits are outliers. (The MEAN would be
	--      dragged upward by them; the MIN would fall for the island's underside.)
	local function groundFromNPC()
		local npc = Workspace:FindFirstChild("MireWatcher", true)
		if npc then
			local ok, cf, size = pcall(function() return npc:GetBoundingBox() end)
			if ok and cf and size and size.Y > 0 then
				-- NpcLife breathes and hops him on the spot (up to ~1.6 studs), so his bounding box is only
				-- "the ground" while his feet are actually on it. "NpcHome" is the resting pose it captured
				-- before taking him over; the difference from the live pivot is exactly how far he is
				-- currently lifted. Nil until adoption, when the box is untouched and the lift is zero.
				local lift = 0
				local home = npc:GetAttribute("NpcHome")
				if typeof(home) == "CFrame" then
					lift = npc:GetPivot().Position.Y - home.Position.Y
				end
				return cf.Position.Y - size.Y / 2 - lift, "the MireWatcher's feet"
			end
		end
		for _, d in ipairs(isl:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:lower():find("npcspot", 1, true) then
				return d.Position.Y, ("the '%s' marker"):format(d.Name)
			end
		end
		return nil, nil
	end

	local function groundFromSamples()
		local hits = {}
		for i = 1, 32 do
			local a = (i / 32) * math.pi * 2 * 3 -- spiral outward, covering the footprint
			local r = (i / 32) * math.min(bsize.X, bsize.Z) * 0.4
			local sx = bcf.Position.X + math.cos(a) * r
			local sz = bcf.Position.Z + math.sin(a) * r
			local h = Workspace:Raycast(Vector3.new(sx, topY + 60, sz), Vector3.new(0, -(bsize.Y + 200), 0), rp)
			if h then hits[#hits + 1] = h.Position.Y end
		end
		if #hits == 0 then return nil end
		table.sort(hits)
		return hits[math.ceil(#hits / 2)] -- median
	end

	local surfaceY, groundSrc = groundFromNPC()
	if not surfaceY then
		surfaceY = groundFromSamples()
		groundSrc = "the median of 32 sample rays"
	end
	if not surfaceY then
		surfaceY = topY
		groundSrc = "the island bbox TOP (no ground found!)"
	end

	local center = Vector3.new(bcf.Position.X, surfaceY, bcf.Position.Z)
	print(("[Mosquito] island5 bbox: centre=(%.0f, %.0f, %.0f) size=(%.0f, %.0f, %.0f)")
		:format(bcf.Position.X, bcf.Position.Y, bcf.Position.Z, bsize.X, bsize.Y, bsize.Z))
	print(("[Mosquito] ground height = %.0f (from %s)"):format(surfaceY, groundSrc))

	buildHUD(); updateHUD()

	--------------------------------------------------------------------
	-- THE MIREWATCHER HANDS OVER THE FLY SWATTER
	--------------------------------------------------------------------
	-- Talking to the MireWatcher sets Island5QuestAccepted (NestingNook_NPCs does this
	-- for every island Researcher). This script USED to just set that attribute itself,
	-- which skipped the NPC entirely. Now the NPC is the one who arms you.
	if player:GetAttribute("Island5QuestAccepted") then
		giveSwatter() -- already accepted (rejoin / re-spawn)
	end
	player:GetAttributeChangedSignal("Island5QuestAccepted"):Connect(function()
		if player:GetAttribute("Island5QuestAccepted") then giveSwatter() end
	end)
	-- re-issue the swatter on respawn (the Backpack is wiped on death)
	player.CharacterAdded:Connect(function()
		if player:GetAttribute("Island5QuestAccepted") and not st.done then
			st.swatter = nil
			task.wait(0.5)
			giveSwatter()
		end
	end)

	-- the egg appears at the user's EggSpot5 marker. ROBUST find: exact name anywhere -> then any part/model
	-- whose name (case/space-insensitive) is "eggspot5" or contains "eggspot". Fallback = island centre.
	local function findSpot()
		local exact = Workspace:FindFirstChild("EggSpot5", true)
		if exact then return exact end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Model") then
				local n = d.Name:lower():gsub("%s", "")
				if n == "eggspot5" or n:find("eggspot", 1, true) then return d end
			end
		end
		return nil
	end
	local function onAllCaught()
		if st.done then return end
		st.done = true
		-- find EggSpot5 NOW (it has surely streamed in by the time all mosquitos are swatted); fallback = island centre
		local eggSpot = findSpot()
		local eggPos = center
		if eggSpot then
			eggPos = (eggSpot:IsA("BasePart") and eggSpot.Position) or eggSpot:GetPivot().Position
			print("[Mosquito] using EggSpot5 -> " .. eggSpot:GetFullName() .. " at " .. tostring(eggPos))
			if eggSpot:IsA("BasePart") then pcall(function() eggSpot.Transparency = 1; eggSpot.CanCollide = false; eggSpot.CanQuery = false end) end
		else
			warn("[Mosquito] EggSpot5 NOT found -> using island centre. Name a part 'EggSpot5'.")
		end
		spawnEggNest(eggPos)
	end

	--------------------------------------------------------------------
	-- SCATTER THE SWARM ACROSS THE WHOLE ISLAND, AT SWATTABLE HEIGHT
	--------------------------------------------------------------------
	-- Spread over the island's real footprint (not one tight ring), and hover each one
	-- a few studs above the ground DIRECTLY UNDER IT -- island5 is uneven, so a single
	-- shared height would bury some mosquitos in a hill and strand others in the sky.
	-- HOVER_MIN/MAX are kept low so a player on foot can always reach them with the
	-- swatter instead of staring at a bug 28 studs overhead.
	local HOVER_MIN, HOVER_MAX = 5, 11
	local spreadR = math.max(28, math.min(bsize.X, bsize.Z) * 0.42) -- most of the island, but inside its edges

	-- Ground height under an XZ, so each mosquito sits above the terrain it's actually
	-- over -- CLAMPED to a sane band around the island's walkable surface.
	--
	-- Two ways the raw raycast lies on island5, both of which make a mosquito
	-- IMPOSSIBLE TO CLICK (you can't click through terrain):
	--   * FALLS THROUGH: island5's mesh isn't fully raycast-queryable, so the ray passes
	--     straight through the ground and hits the island's UNDERSIDE ~85 studs down ->
	--     the mosquito spawns buried inside the island.
	--   * CANOPY HIT: it's a swamp full of tall trees. The ray hits a treetop on the way
	--     down -> the mosquito spawns ~65 studs up in the branches, out of reach.
	-- Anything more than SURFACE_BAND from the known surface is one of those, so ignore
	-- it and fall back to the surface height the player actually walks on.
	local SURFACE_BAND = 25
	local function groundUnder(x, z)
		local h = Workspace:Raycast(Vector3.new(x, surfaceY + 120, z), Vector3.new(0, -400, 0), rp)
		local y = h and h.Position.Y or surfaceY
		if math.abs(y - surfaceY) > SURFACE_BAND then
			return surfaceY -- ray fell through the island, or snagged a tree
		end
		return y
	end

	for i = 1, CONFIG.count do
		-- evenly spaced angles + jitter, and a varied radius, so they never clump
		local ang = (i - 1) * (2 * math.pi / CONFIG.count) + (math.random() - 0.5) * 0.9
		local r   = spreadR * (0.35 + math.random() * 0.65)
		local hx  = center.X + math.cos(ang) * r
		local hz  = center.Z + math.sin(ang) * r
		local hy  = groundUnder(hx, hz) + HOVER_MIN + math.random() * (HOVER_MAX - HOVER_MIN)
		local home = Vector3.new(hx, hy, hz)

		local m, _body, hitbox = buildMosquito(home)
		st.mossies[#st.mossies+1] = m
		print(("[Mosquito]   mosquito %d at (%.0f, %.0f, %.0f)"):format(i, hx, hy, hz))

		-- bob + slow drift around the home point
		task.spawn(function()
			local t = math.random() * 12
			while m.Parent and not st.done do
				t += 0.05
				local off = Vector3.new(math.sin(t*0.6 + i)*6, math.sin(t*1.4 + i)*1.6, math.cos(t*0.5 + i)*6)
				pcall(function() m:PivotTo(CFrame.new(home + off) * CFrame.Angles(0, t*0.5, 0)) end)
				task.wait(0.05)
			end
		end)

		-- THE SWAT. Point and click (or tap) -- you never physically hit the mosquito with
		-- the swatter model. Reached via TWO paths, because Roblox splits them:
		--
		--   * SWATTER EQUIPPED -> the UserInputService handler at the top of this file.
		--     A Tool in hand swallows the click (Tool.Activated) and ClickDetectors go
		--     silent, so we raycast the click ourselves. st.targets is how it finds us.
		--   * NO SWATTER       -> the ClickDetector below still fires normally, and just
		--     tells the player where to get one.
		local function startSwat()
			if st.busy or st.done or not m.Parent then return end
			st.busy = true
			openSwatMinigame(function(win)
				st.busy = false
				if win and m.Parent then
					squashMosquito(m)
					st.caught += 1; updateHUD()
					if st.caught >= CONFIG.count then onAllCaught() end
				elseif m.Parent then
					floatText(m:GetPivot().Position + Vector3.new(0,1,0), "It got away!", Color3.fromRGB(235,120,120))
				end
			end)
		end

		-- PATH 1: swatter equipped. Register the hitbox so the UserInputService raycast
		-- handler can find this mosquito -- ClickDetectors are dead while a Tool is held.
		st.targets[hitbox] = startSwat

		-- PATH 2: no swatter. The ClickDetector still fires, so use it purely to tell the
		-- player how to get one. (If they DO have it equipped this never runs -- Roblox
		-- has already given the click to the Tool.)
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance = CLICK_RANGE; cd.Parent = hitbox
		cd.MouseClick:Connect(function()
			if st.busy or st.done or not m.Parent then return end
			if holdingSwatter() then startSwat(); return end -- belt-and-braces
			local why = player:GetAttribute("Island5QuestAccepted")
				and "Equip the Fly Swatter!"
				or "Talk to the MireWatcher for a Fly Swatter!"
			floatText(m:GetPivot().Position + Vector3.new(0, 1, 0), why, Color3.fromRGB(240, 220, 120))
		end)

		-- PATH 3: the E PROMPT. Works in BOTH states -- an equipped Tool swallows
		-- ClickDetector clicks but does NOT affect ProximityPrompts -- so this is the one
		-- path that never goes silent.
		--
		-- THE PROMPT HANGS ON A STATIONARY ANCHOR, NOT ON THE BUG. Roblox measures prompt
		-- range to the part the prompt sits on, and the mosquito never stops moving: the
		-- drift loop above swings it +/-6 studs on X and Z. Parented to the hitbox, the
		-- prompt would pop in and out on its own as the bug crossed the range edge while
		-- the player stood perfectly still. Anchored to `home` -- the fixed centre the
		-- drift orbits -- ONLY THE PLAYER'S OWN MOVEMENT opens or closes it. Once it shows
		-- it stays up until the player walks out of range.
		--
		-- RequiresLineOfSight is OFF for the same anti-flicker reason: this is a swamp full
		-- of reeds and branches, and the anchor is an invisible point hanging in mid-air.
		local anchor = Instance.new("Part")
		anchor.Name = "MosquitoPromptAnchor"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(home)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false -- must never eat PATH 1's click raycast
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Parent = Workspace
		-- NOT a child of the mosquito -- m:PivotTo would drag it along and reintroduce the
		-- drift. That means it outlives the bug unless cleaned up by hand, both when one is
		-- squashed and when /done clears the whole swarm.
		m.Destroying:Connect(function() pcall(function() anchor:Destroy() end) end)

		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Swat"
		pp.ObjectText = "Mosquito"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.HoldDuration = 0
		pp.MaxActivationDistance = SWAT_PROMPT_RANGE
		pp.RequiresLineOfSight = false
		pp.Parent = anchor
		pp.Triggered:Connect(function()
			if st.busy or st.done or not m.Parent then return end
			if holdingSwatter() then startSwat(); return end
			local why = player:GetAttribute("Island5QuestAccepted")
				and "Equip the Fly Swatter!"
				or "Talk to the MireWatcher for a Fly Swatter!"
			floatText(m:GetPivot().Position + Vector3.new(0, 1, 0), why, Color3.fromRGB(240, 220, 120))
		end)
	end
	-- /done -> skip the swatting, spawn the Spinosaurus egg + nest at EggSpot5
	DoneCommand.bind(isl, "Mosquito", function()
		-- squash any survivors so the island isn't left with bugs buzzing around the egg
		for _, m in ipairs(st.mossies) do
			if m and m.Parent then pcall(function() m:Destroy() end) end
		end
		st.caught = CONFIG.count
		updateHUD()
		onAllCaught()
	end)

	print(("[Mosquito] island5 swamp quest ready: %d mosquitos scattered over a %.0f-stud spread "
		.. "(%.0f-%.0f studs off the ground) -- get the Fly Swatter from the MireWatcher  (/done to skip to the egg)")
		:format(CONFIG.count, spreadR * 2, HOVER_MIN, HOVER_MAX))
end)
