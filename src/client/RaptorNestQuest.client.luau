--======================================================================
-- RaptorNestQuest.client.luau  (LocalScript)  -- ISLAND 7: Feed the Raptor Nest
--======================================================================
-- Meat (markers "Meat1".."Meat5") is scattered around island7. Each piece is SAWED
-- free with a drag-the-bone minigame -- a rising ceiling holds that to a flat 15s
-- (see PickupFloor), so five pieces is 75s of work, not five taps. The player carries
-- ONE piece at a time back to the nest egg ("EggSpot7") and FEEDS it via a
-- drag-the-meat-into-the-mouth minigame (NOT a tap game). Deliver 5 -> the egg
-- shakes, cracks, and hatches a Baby Raptor pet. Gated by Island7QuestAccepted
-- (talk to the RaptorScout first; the chevron guide leads there).
--======================================================================
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TS               = game:GetService("TweenService")
local Debris           = game:GetService("Debris")

-- VERBOSE: per-item boot spam (one line per part/island/pet/serving). OFF by default --
-- it buried the progression telemetry in hundreds of lines. Flip to true to debug THIS
-- system specifically; every file that had a noisy loop uses the same flag name.
local VERBOSE = false

local player           = Players.LocalPlayer
local PlayerGui        = player:WaitForChild("PlayerGui")

local CONFIG = { island = "island7", count = 5, eggSpot = "EggSpot7", accept = "Island7QuestAccepted" }

local okHB, HatchBurst = pcall(function() return require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst", 10)) end)
if not okHB then HatchBurst = nil end
local PickupFloor = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PickupFloor")) -- the 15s-per-collectible floor

print("[RaptorNest] script loaded")

-- robust find (recursive, case/space-insensitive)
local function findNamed(name)
	local exact = Workspace:FindFirstChild(name, true); if exact then return exact end
	local key = name:lower():gsub("[^%w]", "")
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():gsub("[^%w]", "") == key then return d end
	end
	return nil
end
local function posOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	local ok, cf = pcall(function() return inst:GetPivot() end); return ok and cf.Position or Vector3.new()
end
local function ghost(inst)
	for _, d in ipairs(inst:IsA("BasePart") and { inst } or inst:GetDescendants()) do
		if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false; d.CanQuery = false end
	end
end

-- ===== state =====
local st = { delivered = 0, carrying = false, done = false, owns = false, active = false, carving = false }
local meat = {}          -- [i] = { model, chunk, prompt, pos, basePos, delivered=false, hidden=false, carving=false }
local eggPart, eggBob
local carriedModel
local eggPrompt

-- ===== collectible MEAT: a chunky cartoon ham/roast with a white bone out BOTH ends =====
local function buildMeat(anchored)
	local m = Instance.new("Model"); m.Name = "Meat"
	local function P(shape, sx,sy,sz, color, cf, refl)
		local p = Instance.new("Part"); if shape then p.Shape = shape end; p.Size = Vector3.new(sx,sy,sz); p.Color = color
		p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
		p.Anchored = anchored; p.CanCollide = false; p.CanQuery = false; p.Massless = true; p.CFrame = cf; p.Parent = m
		return p
	end
	local RED, ROAST, BONE = Color3.fromRGB(120,55,45), Color3.fromRGB(150,95,60), Color3.fromRGB(235,230,215)
	-- BODY: a SIDEWAYS cylinder ham (lies along X), two-tone (red base + lighter roasted top) -- same colors
	local root = P(Enum.PartType.Cylinder, 3.4,2.6,2.6, RED, CFrame.new())             -- red barrel (shorter so bones show more)
	P(Enum.PartType.Cylinder, 3.2,2.0,2.0, ROAST, root.CFrame*CFrame.new(0,0.55,0))    -- roasted top
	-- BONES out both ends, pulled in CLOSE so they barely protrude
	local function bone(sign)
		P(Enum.PartType.Cylinder, 1.0,0.6,0.6, BONE, root.CFrame*CFrame.new(sign*2.05,-0.1,0))   -- short shaft, tucked into the end
		P(Enum.PartType.Ball, 0.82,0.82,0.82, BONE, root.CFrame*CFrame.new(sign*2.5,-0.1,-0.34)) -- knob
		P(Enum.PartType.Ball, 0.82,0.82,0.82, BONE, root.CFrame*CFrame.new(sign*2.5,-0.1, 0.34)) -- knob
	end
	bone(1); bone(-1)
	root.CanQuery = true; m.PrimaryPart = root
	for _, p in ipairs(m:GetChildren()) do
		if p ~= root and p:IsA("BasePart") then local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = p; w.Parent = root end
	end
	return m, root
end

-- ===== HUD (only while on island7) =====
local hudGui = Instance.new("ScreenGui"); hudGui.Name = "RaptorNestHUD"; hudGui.ResetOnSpawn = false; hudGui.Enabled = false; hudGui.Parent = PlayerGui
local hud = Instance.new("TextLabel"); hud.AnchorPoint = Vector2.new(0.5,0); hud.Position = UDim2.new(0.5,0,0,96); hud.Size = UDim2.fromOffset(360,46)
hud.BackgroundColor3 = Color3.fromRGB(70,46,40); hud.BackgroundTransparency = 0.1; hud.Font = Enum.Font.FredokaOne; hud.TextScaled = true
hud.TextColor3 = Color3.fromRGB(255,225,180); hud.Text = "\xF0\x9F\xA5\xA9 Meat Delivered: 0/5"; hud.Parent = hudGui
Instance.new("UICorner", hud).CornerRadius = UDim.new(0,12); local hs = Instance.new("UIStroke", hud); hs.Color = Color3.fromRGB(150,60,55); hs.Thickness = 2
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = hud end
local function updateHUD()
	if st.carrying then hud.Text = ("\xF0\x9F\xA5\xA9 Carrying meat -- feed the nest!  (%d/%d)"):format(st.delivered, CONFIG.count)
	else hud.Text = ("\xF0\x9F\xA5\xA9 Meat Delivered: %d/%d"):format(st.delivered, CONFIG.count) end
end

-- island gate: only show the HUD while standing on island7
task.spawn(function()
	while true do
		local on7 = false
		local ch = player.Character; local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local isl = Workspace:FindFirstChild(CONFIG.island)
		if hrp and isl then
			local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
			if ok and cf then
				local d = hrp.Position - cf.Position
				on7 = math.abs(d.X) <= size.X/2 + 30 and math.abs(d.Z) <= size.Z/2 + 30 and math.abs(d.Y) <= size.Y/2 + 80 -- Y too (islands stack vertically)
			end
		end
		hudGui.Enabled = st.active and on7 and not st.done
		task.wait(0.4)
	end
end)

local function updatePrompts()
	local accepted = player:GetAttribute(CONFIG.accept) and not st.done
	for i = 1, CONFIG.count do
		local m = meat[i]
		if m and m.prompt then m.prompt.Enabled = accepted and not st.carrying and not st.carving and not m.delivered and not m.hidden end
	end
	if eggPrompt then eggPrompt.Enabled = accepted and st.carrying and not st.carving end
end
player:GetAttributeChangedSignal(CONFIG.accept):Connect(updatePrompts)

-- ===== drag-the-meat-into-the-mouth feeding minigame (NOT a tap game) =====
local function openFeedMinigame(onDone)
	local gui = Instance.new("ScreenGui"); gui.Name = "FeedMinigame"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 90; gui.Parent = PlayerGui
	-- 0.5 film (matching the carve panel), so the nest is still readable behind it
	local back = Instance.new("TextButton"); back.Size = UDim2.fromScale(1,1); back.BackgroundColor3 = Color3.fromRGB(20,16,12); back.BackgroundTransparency = 0.5; back.Text = ""; back.AutoButtonColor = false; back.Parent = gui
	local panel = Instance.new("Frame"); panel.AnchorPoint = Vector2.new(0.5,0.5); panel.Position = UDim2.new(0.5,0,0.5,0); panel.Size = UDim2.fromOffset(420,360)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = gui; Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16)
	local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Size = UDim2.new(1,-56,0,40); title.Position = UDim2.new(0,10,0,8)
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "Drag the meat into the mouth!"; title.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = title end
	-- the hungry baby raptor's open MOUTH (the drop target)
	local mouth = Instance.new("TextLabel"); mouth.AnchorPoint = Vector2.new(0.5,0); mouth.Position = UDim2.new(0.5,0,0,56); mouth.Size = UDim2.fromOffset(150,150)
	mouth.BackgroundColor3 = Color3.fromRGB(60,30,28); mouth.Font = Enum.Font.GothamBold; mouth.TextScaled = true; mouth.Text = "\xF0\x9F\xA6\x96"; mouth.TextColor3 = Color3.fromRGB(255,255,255); mouth.Parent = panel
	Instance.new("UICorner", mouth).CornerRadius = UDim.new(1,0); local mstk = Instance.new("UIStroke", mouth); mstk.Color = Color3.fromRGB(255,210,120); mstk.Thickness = 3
	local hint = Instance.new("TextLabel"); hint.BackgroundTransparency = 1; hint.AnchorPoint = Vector2.new(0.5,0); hint.Position = UDim2.new(0.5,0,0,212); hint.Size = UDim2.new(1,-20,0,24)
	hint.Font = Enum.Font.GothamBold; hint.TextScaled = true; hint.TextColor3 = Color3.fromRGB(245,236,208); hint.Text = "Drop it in the raptor's mouth"; hint.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = hint end
	-- the draggable meat -- parented to the ScreenGui (top-left = screen 0,0 since IgnoreGuiInset),
	-- with a high ZIndex so it renders ABOVE the panel and tracks the cursor exactly.
	local meatHome = UDim2.new(0.5,0,0.82,0)
	local drag = Instance.new("TextButton"); drag.AnchorPoint = Vector2.new(0.5,0.5); drag.Position = meatHome; drag.Size = UDim2.fromOffset(100,100)
	drag.BackgroundColor3 = Color3.fromRGB(150,62,56); drag.Font = Enum.Font.GothamBold; drag.TextScaled = true; drag.Text = "\xF0\x9F\xA5\xA9"; drag.AutoButtonColor = false; drag.ZIndex = 10; drag.Parent = gui
	Instance.new("UICorner", drag).CornerRadius = UDim.new(1,0); local ds = Instance.new("UIStroke", drag); ds.Color = Color3.fromRGB(90,30,28); ds.Thickness = 2

	local conns = {}
	local finished = false
	local function finish(success)
		if finished then return end
		finished = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		gui:Destroy()
		if onDone then onDone(success) end
	end
	-- There was no way out of this panel at all: miss the mouth repeatedly and the only
	-- exit was closing the game. X bails (you keep the meat, nothing is fed); the
	-- backdrop still never closes it.
	PickupFloor.addCloseButton(panel, function() finish(false) end)
	local dragging = false
	-- screen-space drag (the gui ignores inset, so input.Position maps 1:1)
	drag.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = true end
	end)
	conns[#conns+1] = UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			drag.Position = UDim2.fromOffset(io.Position.X, io.Position.Y) -- AnchorPoint 0.5 -> centered on cursor
		end
	end)
	local function overMouth()
		local dp, dsz = drag.AbsolutePosition, drag.AbsoluteSize
		local cx, cy = dp.X + dsz.X/2, dp.Y + dsz.Y/2
		local mp, msz = mouth.AbsolutePosition, mouth.AbsoluteSize
		return cx >= mp.X and cx <= mp.X + msz.X and cy >= mp.Y and cy <= mp.Y + msz.Y
	end
	conns[#conns+1] = UserInputService.InputEnded:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if overMouth() then
				-- CHOMP: meat flies into the mouth (screen-space center of the mouth), raptor gulps
				local mc = UDim2.fromOffset(mouth.AbsolutePosition.X + mouth.AbsoluteSize.X/2, mouth.AbsolutePosition.Y + mouth.AbsoluteSize.Y/2)
				TS:Create(drag, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = mc, Size = UDim2.fromOffset(8,8) }):Play()
				TS:Create(mouth, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { Size = UDim2.fromOffset(170,170) }):Play()
				task.delay(0.22, function() finish(true) end)
			else
				TS:Create(drag, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Position = meatHome }):Play() -- snap back, try again
			end
		end
	end)
end

-- ===== CARVE THE MEAT FREE (the island7 pickup) =====
--
-- RISING CEILING (PickupFloor pattern 1), with a verb of its own: sawing.
--
-- Picking meat up used to be one E on a ProximityPrompt, which made the whole of
-- Claw Cliffs a five-stop walk. Each piece is now sawed off the ridge with the
-- bone: DRAG the saw across the cut and back, and each full traverse bites deeper.
--
-- The floor is exact rather than tuned. A ceiling climbs 0 -> 1 over 15s and the
-- cut is clamped to it on every write, so strokes swung faster than the ceiling are
-- simply lost -- there is no stroke rate that finishes a piece early. The slow
-- SAG in the other direction means standing still loses ground, so keeping pace
-- costs (1/15 + 0.02) / (1/14) = ~1.2 traverses/sec: a steady sawing rhythm, and a
-- DRAG rather than taps, which is the comfortable input on a phone.
--
-- Bail out (X, never the backdrop) and the meat is left exactly as it was.
local function openCarveMinigame(entry, onDone)
	local STROKES = 8       -- full traverses of the cut; each one bites 1/8 deeper
	local SAG     = 0.012   -- the meat settles back into the ridge while you're not sawing
	-- DONE, not 1.0, for TWO reasons -- either one alone made the cut impossible to finish:
	--   1. the fill is CLAMPED to the rising ceiling, so a stroke can add at most exactly
	--      the ceiling's value, and the sag then takes a sliver back out on the very next
	--      frame -- before the completion test ever runs.
	--   2. 1/14 is not exact in binary. Fourteen of them sum to 0.9999999999999997, which
	--      is not >= 1 even with the sag switched off entirely.
	local DONE    = PickupFloor.DONE

	local gui = Instance.new("ScreenGui"); gui.Name = "CarveMinigame"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 90; gui.Parent = PlayerGui
	-- 0.5 film, so the real ham-bone is still visible reacting behind the panel.
	-- Modal + no click handler: a backdrop tap NEVER closes this.
	local back = Instance.new("TextButton"); back.Size = UDim2.fromScale(1,1); back.BackgroundColor3 = Color3.new(0,0,0); back.BackgroundTransparency = 0.5
	back.Text = ""; back.AutoButtonColor = false; back.Modal = true; back.Active = true; back.Parent = gui
	local panel = Instance.new("Frame"); panel.AnchorPoint = Vector2.new(0.5,0.5); panel.Position = UDim2.new(0.5,0,0.5,0); panel.Size = UDim2.fromOffset(420,300)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.Parent = gui; Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16)
	local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(40,52,38); ps.Thickness = 3
	local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Size = UDim2.new(1,-56,0,40); title.Position = UDim2.new(0,10,0,8)
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "Saw the meat free!"; title.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 24; c.Parent = title end

	-- THE CUT: a horizontal track the saw is dragged along, end to end
	local track = Instance.new("Frame"); track.AnchorPoint = Vector2.new(0.5,0); track.Position = UDim2.new(0.5,0,0,74); track.Size = UDim2.new(1,-48,0,86)
	track.BackgroundColor3 = Color3.fromRGB(70,40,36); track.Parent = panel; Instance.new("UICorner", track).CornerRadius = UDim.new(0,12)
	local ts = Instance.new("UIStroke", track); ts.Color = Color3.fromRGB(150,95,60); ts.Thickness = 2
	for _, x in ipairs({ 0.08, 0.92 }) do -- the two ends you have to reach for a stroke to count
		local mark = Instance.new("Frame"); mark.AnchorPoint = Vector2.new(0.5,0.5); mark.Position = UDim2.new(x,0,0.5,0); mark.Size = UDim2.new(0,4,1,-16)
		mark.BackgroundColor3 = Color3.fromRGB(255,210,120); mark.BackgroundTransparency = 0.45; mark.BorderSizePixel = 0; mark.Parent = track
	end
	local saw = Instance.new("TextButton"); saw.AnchorPoint = Vector2.new(0.5,0.5); saw.Position = UDim2.new(0.5,0,0.5,0); saw.Size = UDim2.fromOffset(70,70)
	saw.BackgroundColor3 = Color3.fromRGB(235,230,215); saw.AutoButtonColor = false; saw.Font = Enum.Font.FredokaOne; saw.TextScaled = true
	saw.Text = "\xF0\x9F\xA6\xB4"; saw.ZIndex = 3; saw.Parent = track
	Instance.new("UICorner", saw).CornerRadius = UDim.new(1,0); local ss = Instance.new("UIStroke", saw); ss.Color = Color3.fromRGB(120,90,60); ss.Thickness = 2

	local cutBg = Instance.new("Frame"); cutBg.AnchorPoint = Vector2.new(0.5,0); cutBg.Position = UDim2.new(0.5,0,0,182); cutBg.Size = UDim2.new(1,-48,0,20)
	cutBg.BackgroundColor3 = Color3.fromRGB(40,52,38); cutBg.Parent = panel; Instance.new("UICorner", cutBg).CornerRadius = UDim.new(0,10)
	local cut = Instance.new("Frame"); cut.Size = UDim2.new(0,0,1,0); cut.BackgroundColor3 = Color3.fromRGB(200,80,70); cut.BorderSizePixel = 0; cut.Parent = cutBg
	Instance.new("UICorner", cut).CornerRadius = UDim.new(0,10)
	local hint = Instance.new("TextLabel"); hint.BackgroundTransparency = 1; hint.AnchorPoint = Vector2.new(0.5,0); hint.Position = UDim2.new(0.5,0,0,214); hint.Size = UDim2.new(1,-40,0,26)
	hint.Font = Enum.Font.GothamBold; hint.TextScaled = true; hint.TextColor3 = Color3.fromRGB(245,236,208); hint.Text = "Drag the bone end to end \xE2\x80\x94 keep sawing"; hint.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = hint end

	local conns = {}
	local finished, fill = false, 0
	local ceiling = PickupFloor.newCeiling(0)
	local function finish(success)
		if finished then return end
		finished = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		gui:Destroy()
		if onDone then onDone(success) end
	end
	PickupFloor.addCloseButton(panel, function() finish(false) end)

	-- drag: the saw follows the pointer's X along the track (mouse and touch alike)
	local dragging, sawX, edge = false, 0.5, 0
	saw.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = true end
	end)
	conns[#conns+1] = UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	conns[#conns+1] = UserInputService.InputChanged:Connect(function(io)
		if not dragging or finished then return end
		if io.UserInputType ~= Enum.UserInputType.MouseMovement and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local tp, tsz = track.AbsolutePosition, track.AbsoluteSize
		if tsz.X <= 0 then return end
		sawX = math.clamp((io.Position.X - tp.X) / tsz.X, 0.04, 0.96)
		-- a STROKE is a traverse: reach one end having last touched the other
		if sawX >= 0.92 and edge ~= 1 then
			edge = 1
			fill = ceiling:clamp(fill + 1 / STROKES) -- clamp on the INPUT path, not just per-frame
		elseif sawX <= 0.08 and edge ~= -1 then
			edge = -1
			fill = ceiling:clamp(fill + 1 / STROKES)
		else
			return
		end
		-- the stroke that severs it pays out HERE, not a frame later in the loop, which
		-- would charge it a frame of sag off a bar already sitting at the ceiling
		if fill >= DONE then cut.Size = UDim2.new(1, 0, 1, 0); finish(true) end
	end)

	task.spawn(function()
		local last = os.clock()
		while not finished do
			local now = os.clock(); local dt = math.min(now - last, 0.1); last = now
			ceiling:step(dt)
			fill = ceiling:clamp(math.max(0, fill - SAG * dt))
			saw.Position = UDim2.new(sawX, 0, 0.5, 0)
			saw.Rotation = (sawX - 0.5) * 40
			cut.Size = UDim2.new(fill, 0, 1, 0)
			-- THE REAL HAM-BONE REACTS behind the 0.5 film: it works loose and lifts a
			-- believable amount -- just clear of the ground, not launched into the sky.
			if entry and entry.model and entry.model.Parent and entry.basePos then
				pcall(function()
					entry.model:PivotTo(CFrame.new(entry.basePos + Vector3.new(0, fill * 0.8, 0))
						* CFrame.Angles(0, fill * 2.4, math.rad(math.sin(now * 14) * 4 * (1 - fill))))
				end)
			end
			if fill >= DONE then cut.Size = UDim2.new(1,0,1,0); finish(true); break end
			task.wait()
		end
	end)
end

-- ===== egg at EggSpot7 (no nest -- just the egg) =====
local function buildEgg(pos)
	local egg = Instance.new("Part"); egg.Name = "RaptorEgg"; egg.Shape = Enum.PartType.Ball; egg.Size = Vector3.new(3.0,3.8,3.0)
	egg.Color = Color3.fromRGB(226,206,150); egg.Material = Enum.Material.SmoothPlastic; egg.Anchored = true; egg.CanCollide = false; egg.CanQuery = true
	egg.CFrame = CFrame.new(pos + Vector3.new(0,1.9,0)); egg.Parent = Workspace
	for _ = 1, 7 do -- brown speckles
		local sp = Instance.new("Part"); sp.Shape = Enum.PartType.Ball; sp.Size = Vector3.new(0.5,0.5,0.5); sp.Color = Color3.fromRGB(120,86,52)
		sp.Material = Enum.Material.SmoothPlastic; sp.Anchored = true; sp.CanCollide = false; sp.CanQuery = false
		local u = (math.random()-0.5); local a = math.random()*math.pi*2
		sp.CFrame = egg.CFrame * CFrame.Angles(0, a, u*2) * CFrame.new(0, 0, 1.45); sp.Parent = Workspace
		local w = Instance.new("WeldConstraint"); w.Part0 = egg; w.Part1 = sp; w.Parent = egg
	end
	-- gentle idle bob (no spin)
	eggBob = RunService.Heartbeat:Connect(function()
		if egg.Parent then egg.CFrame = CFrame.new(pos + Vector3.new(0, 1.9 + math.sin(os.clock()*2)*0.12, 0)) end
	end)
	return egg
end

local function floatText(pos, txt, color)
	local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 1; p.Size = Vector3.new(1,1,1); p.CFrame = CFrame.new(pos); p.Parent = Workspace
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(240,50); bb.StudsOffset = Vector3.new(0,2,0); bb.AlwaysOnTop = true; bb.Parent = p
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1,1); l.Font = Enum.Font.FredokaOne; l.TextScaled = true; l.TextColor3 = color or Color3.fromRGB(255,230,150); l.TextStrokeTransparency = 0.3; l.Text = txt; l.Parent = bb
	TS:Create(p, TweenInfo.new(1.1), { CFrame = CFrame.new(pos + Vector3.new(0,4,0)) }):Play()
	Debris:AddItem(p, 1.2)
end

-- ===== hatch -> Baby Raptor =====
local function hatchEgg(egg)
	if st.done then return end
	st.done = true
	updatePrompts(); hudGui.Enabled = false
	local pos = egg.Position
	if eggBob then eggBob:Disconnect() end
	-- shake + cracks
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.4 and egg.Parent do
			egg.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(math.random(-12,12)), 0, math.rad(math.random(-12,12)))
			task.wait(0.04)
		end
	end)
	floatText(pos + Vector3.new(0,3,0), "The egg is hatching!", Color3.fromRGB(255,210,120))
	task.wait(1.5)
	if HatchBurst then pcall(function() HatchBurst.play(pos, Color3.fromRGB(226,206,150)) end) end
	pcall(function() egg:Destroy() end)
	-- grant the Baby Raptor (Velociraptor pet)
	local cf = CFrame.new(pos + Vector3.new(3,0,0))
	-- ===== CLAW CLIFFS GIVES A THERIZINOSAURUS, NOT A THIRD VELOCIRAPTOR =====
	-- This island, Fossil Frontier and Redwood Ridge all used to hand out RaptorPet, so two of
	-- the three were giving you a pet you already owned. The Raptor stayed on Redwood Ridge
	-- (its raptors are the quest there); this island took the dinosaur with the longest claws
	-- of any animal that has ever lived, which is what its landmark is.
	-- Only the species granted changed -- the meat, the nest and the markers are untouched.
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("TherizinosaurusPet", { petId="TherizinosaurusPet", displayName="Therizinosaurus", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	if _G.SpawnTherizinosaurusFollower then pcall(function() _G.SpawnTherizinosaurusFollower(cf) end) end
	do local rh = RS:FindFirstChild("TherizinosaurusHatched"); if rh then pcall(function() rh:FireServer() end) end end
	floatText(pos + Vector3.new(0,3,0), "\xF0\x9F\xA6\x96 Baby Raptor hatched!", Color3.fromRGB(140,255,150))
end

-- ===== carry / deliver =====
local function dropCarried()
	if carriedModel then pcall(function() carriedModel:Destroy() end); carriedModel = nil end
end
local function pickUp(i)
	if st.carrying or st.done then return end
	local m = meat[i]; if not m or m.delivered or m.hidden then return end
	st.carrying = true; m.hidden = true
	pcall(function() m.model.Parent = nil end) -- stash (restored if you die before delivering)
	-- weld a meat to the player
	local ch = player.Character; local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then
		local cm, chunk = buildMeat(false) -- carried ham-bone
		cm:PivotTo(hrp.CFrame * CFrame.new(2.0, 0.6, -1.8))
		cm.Parent = Workspace
		local w = Instance.new("WeldConstraint"); w.Part0 = hrp; w.Part1 = chunk; w.Parent = chunk
		carriedModel = cm
	end
	st.carriedIndex = i
	updateHUD(); updatePrompts()
	floatText(m.pos + Vector3.new(0,2,0), "Picked up meat!", Color3.fromRGB(255,180,120))
end
-- The prompt no longer hands the meat over -- it opens the carve. Only a FINISHED
-- carve calls pickUp; bailing out puts the ham-bone back exactly where it was.
local function startCarve(i)
	if st.carrying or st.done or st.carving then return end
	local m = meat[i]; if not m or m.delivered or m.hidden then return end
	st.carving = true; m.carving = true -- m.carving parks the idle bob so the carve owns the pivot
	updatePrompts()
	openCarveMinigame(m, function(success)
		st.carving = false; m.carving = false
		if success and not st.done then
			pickUp(i)
		elseif m.model and m.model.Parent and m.basePos then
			pcall(function() m.model:PivotTo(CFrame.new(m.basePos)) end) -- reset the prop on abort
		end
		updatePrompts()
	end)
end
local function deliver()
	if not st.carrying or st.done then return end
	openFeedMinigame(function(success)
		if not success or st.done then return end
		local i = st.carriedIndex
		st.carrying = false; dropCarried()
		if i and meat[i] then meat[i].delivered = true; if meat[i].model then pcall(function() meat[i].model:Destroy() end) end end
		st.delivered += 1
		updateHUD(); updatePrompts()

		-- THE CHOMP. Fires on a SUCCESSFUL feed only -- bailing out of the panel with the X
		-- returns success=false and leaves you still carrying the meat, so it must sit here
		-- rather than in the minigame's finish(), or you would hear the nest eat something
		-- it never got. Positional on the egg so it comes from the nest, not your head.
		if eggPart then
			local s = Instance.new("Sound")
			s.Name = "NestChomp"
			s.SoundId = "rbxassetid://95877881142415"
			s.Volume = 2.0
			s.RollOffMode = Enum.RollOffMode.Linear
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 120
			s.Parent = eggPart
			pcall(function() s:Play() end)
			pcall(function() s.Ended:Once(function() pcall(function() s:Destroy() end) end) end)
			Debris:AddItem(s, 12) -- backstop: eggPart survives the quest, so never leak onto it
		end

		if eggPart then floatText(eggPart.Position + Vector3.new(0,2.5,0), ("Fed!  %d/%d"):format(st.delivered, CONFIG.count), Color3.fromRGB(255,230,150)) end
		if st.delivered >= CONFIG.count and eggPart then hatchEgg(eggPart) end
	end)
end

-- if you die while carrying, restore that meat so the quest can't soft-lock
player.CharacterAdded:Connect(function()
	if st.carrying and not st.done then
		st.carrying = false; dropCarried()
		local i = st.carriedIndex
		if i and meat[i] and meat[i].hidden and not meat[i].delivered then meat[i].hidden = false; pcall(function() meat[i].model.Parent = Workspace end) end
		updateHUD(); updatePrompts()
	end
end)

-- ===== GREEN CHEVRON TRAIL: while CARRYING meat, a flat runway points you to the nest; hidden after you feed =====
do
	local BRIGHT, EDGE = Color3.fromRGB(90,200,110), Color3.fromRGB(40,120,60)
	local SPACING, MAX_ARROWS, STOP_DIST = 6, 20, 8
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local function cpart(model, name, sx,sy,sz, color, refl, cf)
		local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(sx,sy,sz); p.Color = color
		p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false; p.CFrame = cf; p.Parent = model; return p
	end
	local function buildChevron()
		local m = Instance.new("Model"); m.Name = "RaptorNestChevron"
		local root = cpart(m, "Root", 0.2,0.2,0.2, BRIGHT, 0, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
		local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
		local front = CFrame.new(0, 0, -0.9)
		cpart(m, "EdgeR", W+0.20, T*0.65, L+0.20, EDGE, 0, front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,-0.03,L/2))
		cpart(m, "EdgeL", W+0.20, T*0.65, L+0.20, EDGE, 0, front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,-0.03,L/2))
		cpart(m, "ArmR",  W, T, L, BRIGHT, 0.14,          front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, 0.04,L/2))
		cpart(m, "ArmL",  W, T, L, BRIGHT, 0.14,          front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, 0.04,L/2))
		m.Parent = Workspace
		return m
	end
	local pool = {}
	local function getNode(i) if not pool[i] then pool[i] = buildChevron() end; return pool[i] end
	local function setShown(nd, on) for _, p in ipairs(nd:GetDescendants()) do if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end end end
	local function hideFrom(n) for i = n, #pool do if pool[i] then setShown(pool[i], false) end end end
	RunService.RenderStepped:Connect(function()
		-- only while actively carrying a piece of meat toward the nest
		if not (st.active and st.carrying and not st.done and eggPart and eggPart.Parent) then hideFrom(1); return end
		local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then hideFrom(1); return end
		local d = eggPart.Position - hrp.Position; local flat = Vector3.new(d.X, 0, d.Z); local dist = flat.Magnitude
		if dist > 600 or dist <= STOP_DIST then hideFrom(1); return end -- arrived / too far
		local dir = flat.Unit
		local excl = { char }; for _, nd in ipairs(pool) do excl[#excl+1] = nd end
		rp.FilterDescendantsInstances = excl
		local maxAlong = dist - STOP_DIST; local placed = 0
		for i = 1, MAX_ARROWS do
			local along = i * SPACING
			if along > maxAlong then break end
			placed += 1
			local px = hrp.Position.X + dir.X * along
			local pz = hrp.Position.Z + dir.Z * along
			local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rp)
			local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
			local nd = getNode(placed); local p0 = Vector3.new(px, gy + 0.12, pz)
			pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
			pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end)
			setShown(nd, true)
		end
		hideFrom(placed + 1)
	end)
end

-- ===== BOOT: ghost the marker parts now; the quest (meat + egg) only appears AFTER you talk to the NPC =====
task.spawn(function()
	local island = Workspace:WaitForChild(CONFIG.island, 60); if not island then warn("[RaptorNest] island7 not found"); return end

	--------------------------------------------------------------------
	-- WAIT FOR ISLAND 7 TO STREAM IN before hunting for the markers.
	--------------------------------------------------------------------
	-- StreamingEnabled: island7's MODEL replicates at join, but its PARTS (Meat1..5 and
	-- EggSpot7) are only sent once the player is near it -- and island7 sits 11,978 studs
	-- up the tower (slot 10). At spawn it is an EMPTY SHELL on this client.
	--
	-- The old code searched for the markers immediately with a 20s retry, found NOTHING
	-- (the player was still down on island1), and left meatPos/eggPos EMPTY. Much later,
	-- when you finally talked to the RaptorScout, activate() ran off those empty tables:
	--     [RaptorNest] Meat1..5 not found
	--     [RaptorNest] quest ACTIVATED -- placed 0 ham-bone meat models + egg MISSING
	-- The markers were on the island the whole time -- they just hadn't been streamed.
	local function islandHasStreamedIn()
		local ok, _, size = pcall(function() return island:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end
	if not islandHasStreamedIn() then
		print("[RaptorNest] island7 has not streamed in yet (0 parts on this client) -- waiting until the player reaches it...")
		local waited = 0
		while not islandHasStreamedIn() do
			task.wait(1)
			waited += 1
			if waited % 30 == 0 then
				if VERBOSE then print(("[RaptorNest]   still waiting for island7 to stream in (%ds)"):format(waited)) end
			end
		end
		print(("[RaptorNest] island7 streamed in after %ds -> looking for the Meat + EggSpot markers"):format(waited))
	end

	-- now the island's parts really are here, so a miss is a REAL miss
	local meatMarkers, eSpot = {}, nil
	for _ = 1, 40 do
		for i = 1, CONFIG.count do if not meatMarkers[i] then local mk = findNamed("Meat" .. i); if mk then meatMarkers[i] = mk end end end
		if not eSpot then eSpot = findNamed(CONFIG.eggSpot) end
		local n = 0; for i = 1, CONFIG.count do if meatMarkers[i] then n += 1 end end
		if n >= CONFIG.count and eSpot then break end
		task.wait(0.5)
	end

	-- report what we actually found, so a genuinely missing/misnamed marker is obvious
	do
		local n = 0
		for i = 1, CONFIG.count do
			if meatMarkers[i] then
				n += 1
			else
				warn(("[RaptorNest] island7 IS streamed in, but marker 'Meat%d' is genuinely absent -- "
					.. "name a part 'Meat%d' on island7."):format(i, i))
			end
		end
		if not eSpot then
			warn(("[RaptorNest] island7 IS streamed in, but '%s' is genuinely absent -- name a part '%s' on island7.")
				:format(CONFIG.eggSpot, CONFIG.eggSpot))
		end
		print(("[RaptorNest] found %d/%d Meat marker(s) + egg spot %s")
			:format(n, CONFIG.count, eSpot and "ok" or "MISSING"))
	end
	-- the parts you placed are just LOCATIONS -> ghost them immediately + remember where they were
	local meatPos = {}
	for i = 1, CONFIG.count do if meatMarkers[i] then meatPos[i] = posOf(meatMarkers[i]); ghost(meatMarkers[i]) end end
	local eggPos = eSpot and posOf(eSpot); if eSpot then ghost(eSpot) end

	-- activate(): spawn the real meat + egg + prompts. Runs ONLY after Island7QuestAccepted (talk to RaptorScout).
	local function activate()
		if st.active or st.done then return end
		st.active = true
		local found = 0
		for i = 1, CONFIG.count do
			if meatPos[i] then
				found += 1
				local model, chunk = buildMeat(true)                  -- cartoon ham-bone (all 5 the same)
				local basePos = meatPos[i] + Vector3.new(0, 1.4, 0)
				model:PivotTo(CFrame.new(basePos))
				model.Parent = Workspace
				-- "Carve", not "Carry" -- the prompt opens the saw minigame, it does not hand the meat over
				local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Carve Meat"; pp.ObjectText = "Meat"
				pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.15; pp.MaxActivationDistance = 18; pp.RequiresLineOfSight = false; pp.Enabled = true; pp.Parent = chunk
				meat[i] = { model = model, chunk = chunk, prompt = pp, pos = meatPos[i], basePos = basePos, delivered = false, hidden = false, carving = false }
				pp.Triggered:Connect(function() startCarve(i) end)
				-- gentle BOB (up/down, no spin) so uncollected meat is easy to spot.
				-- Parked while this piece is being carved -- otherwise the bob and the
				-- carve fight over the pivot and the ham-bone judders in place.
				task.spawn(function()
					while model.Parent and not meat[i].hidden and not meat[i].delivered and not st.done do
						if not meat[i].carving then
							model:PivotTo(CFrame.new(basePos + Vector3.new(0, math.sin(os.clock()*2 + i)*0.25, 0)))
						end
						task.wait()
					end
				end)
			else
				warn("[RaptorNest] Meat" .. i .. " not found")
			end
		end
		if eggPos then
			eggPart = buildEgg(eggPos)
			eggPrompt = Instance.new("ProximityPrompt"); eggPrompt.ActionText = "Feed the Nest"; eggPrompt.ObjectText = "Raptor Egg"
			eggPrompt.KeyboardKeyCode = Enum.KeyCode.E; eggPrompt.HoldDuration = 0.1; eggPrompt.MaxActivationDistance = 32; eggPrompt.RequiresLineOfSight = false; eggPrompt.Enabled = false; eggPrompt.Parent = eggPart
			eggPrompt.Triggered:Connect(deliver)
		else
			warn("[RaptorNest] EggSpot7 not found -> no egg")
		end
		updatePrompts()
		print(("[RaptorNest] quest ACTIVATED -- placed %d ham-bone meat models + egg %s"):format(found, eggPart and "ok" or "MISSING"))
	end

	-- gate: nothing shows until you accept (talk to the RaptorScout; the chevron arrows lead you there)
	if player:GetAttribute(CONFIG.accept) then
		activate()
	else
		local conn; conn = player:GetAttributeChangedSignal(CONFIG.accept):Connect(function()
			if player:GetAttribute(CONFIG.accept) then if conn then conn:Disconnect() end; activate() end
		end)
	end
	print("[RaptorNest] island7 markers ghosted -- quest hidden until you talk to the RaptorScout")
end)
