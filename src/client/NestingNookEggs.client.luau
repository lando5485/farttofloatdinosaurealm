--======================================================================
-- NestingNookEggs.client.luau  (LocalScript)  -- ISLAND 1: rock the lost eggs free
--======================================================================
-- The client half of island1's LostEgg pickup. NestingNook_NPCs.server.luau owns the
-- eggs; when the player triggers a "Rock Egg Free" prompt the server fires EggCarry to
-- this script, and this script fires it back once the egg is actually loose.
--
-- WHY THIS EXISTS: taking an egg used to be one prompt trigger. Five free grabs meant
-- island1 -- the FIRST island, the one that teaches the game -- was a walk with five
-- E-taps in it. Every collectible in this realm now costs 15 seconds (see
-- ReplicatedStorage/DinosaurRealm/PickupFloor).
--
-- THE VERB: alternating rocks. The egg is wedged into the leaf litter, and you rock it
-- LEFT, then RIGHT, then LEFT -- a rock only counts if it is the opposite side from the
-- last one, so hammering one button does nothing. Every other island has its own verb
-- (tap-with-cooldown digging, hold/release reeling, aiming at a moving bug, drag-sawing,
-- shoving against pressure); this one is alternation, and it is deliberately the
-- simplest of them because it is the first thing a new player ever does.
--
-- THE FLOOR: RISING CEILING (PickupFloor pattern 1). A ceiling climbs 0 -> 1 over
-- PickupFloor.ISLAND1_EGG_SECONDS and the bar is clamped to it on every write, so rocks
-- swung faster than the ceiling are simply lost. The slow SETTLE in the other direction
-- means stopping loses ground.
--
-- TUNED TWICE, and the two changes pull in opposite directions -- keep both in mind
-- before touching either number:
--   * EASIER: the pace needed to hold the bar against the ceiling is
--     (1/10.5 + 0.02) * 8 = ~0.92 rocks/sec, down ~a third from the ~1.4/sec this
--     shipped with. That is a rock a second on alternating buttons, far inside the
--     ~2.7/sec mobile ceiling.
--   * QUICKER: the egg itself takes 10.5s instead of 15s.
-- Shortening the clock RAISES the required rate on its own, so ROCKS came down from 16
-- to 8 to pay for it. Change the seconds without changing ROCKS and the egg quietly gets
-- harder, not just shorter.
--
-- The server enforces the same 10.5s from the same constant (see ISLAND1_EGG_SECONDS),
-- so skipping the UI still wins nothing.
--
-- The server keeps its own clock on top of this (see EggCarry there). This panel is the
-- presentation; the rule is enforced there, so skipping the UI wins nothing.
--======================================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local TS         = game:GetService("TweenService")
local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

local folder      = RS:WaitForChild("NestingNook")
local eggCarry    = folder:WaitForChild("EggCarry")
local PickupFloor = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PickupFloor"))

local ROCKS  = 8    -- alternating rocks; each one works the egg 1/8 looser
local SETTLE = 0.02 -- it settles back into the leaf litter while you're not rocking
-- DONE, not 1.0. The bar is CLAMPED to the rising ceiling, so the most a rock can ever
-- put in it is exactly the ceiling's value -- and the settle drain then takes a sliver
-- back out on the very next frame. Testing for a literal 1.0 is a test that can never
-- pass: the panel sat there visibly full and never handed the egg over. The threshold
-- is one frame of settle (0.02/60 = 0.0003) clear of full, with room to spare.
local DONE   = PickupFloor.DONE

local busy = false

local function openRockMinigame(egg, onDone)
	-- The egg's resting pose, captured ONCE. Held in a local rather than written onto
	-- the instance: it belongs to the server, and a client-set attribute there is a
	-- local-only scribble on someone else's object.
	local baseCF = nil
	pcall(function() baseCF = egg:GetPivot() end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RockEggMinigame"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 90; gui.Parent = PlayerGui
	-- 0.5 film so the nest is still readable behind it. Modal with no click handler:
	-- the X closes this, a backdrop tap NEVER does (house rule).
	local back = Instance.new("TextButton"); back.Size = UDim2.fromScale(1,1); back.BackgroundColor3 = Color3.new(0,0,0)
	back.BackgroundTransparency = 0.5; back.Text = ""; back.AutoButtonColor = false; back.Modal = true; back.Active = true; back.Parent = gui

	local panel = Instance.new("Frame"); panel.AnchorPoint = Vector2.new(0.5,0.5); panel.Position = UDim2.new(0.5,0,0.5,0); panel.Size = UDim2.fromOffset(400,300)
	panel.BackgroundColor3 = Color3.fromRGB(62,96,58); panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,16)
	local ps = Instance.new("UIStroke", panel); ps.Color = Color3.fromRGB(50,200,80); ps.Thickness = 3 -- island1's guide green
	local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Size = UDim2.new(1,-56,0,38); title.Position = UDim2.new(0,10,0,8)
	title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "Rock the egg free!"; title.Parent = panel
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 24; c.Parent = title end

	-- the egg itself, tilting to whichever side you last rocked
	local eggIco = Instance.new("TextLabel"); eggIco.BackgroundTransparency = 1; eggIco.AnchorPoint = Vector2.new(0.5,0)
	eggIco.Position = UDim2.new(0.5,0,0,52); eggIco.Size = UDim2.fromOffset(104,104)
	eggIco.Font = Enum.Font.FredokaOne; eggIco.TextScaled = true; eggIco.Text = "\xF0\x9F\xA5\x9A"; eggIco.Parent = panel

	local function rockButton(side, xScale, label)
		local b = Instance.new("TextButton"); b.AnchorPoint = Vector2.new(0.5,0); b.Position = UDim2.new(xScale,0,0,166); b.Size = UDim2.fromOffset(150,66)
		b.BackgroundColor3 = Color3.fromRGB(96,150,84); b.Font = Enum.Font.FredokaOne; b.TextScaled = true
		b.TextColor3 = Color3.new(1,1,1); b.Text = label; b.AutoButtonColor = false; b.Parent = panel
		Instance.new("UICorner", b).CornerRadius = UDim.new(0,14)
		local s = Instance.new("UIStroke", b); s.Color = Color3.fromRGB(36,66,34); s.Thickness = 2
		return b
	end
	local leftBtn  = rockButton(-1, 0.27, "\xE2\x97\x80  ROCK")
	local rightBtn = rockButton( 1, 0.73, "ROCK  \xE2\x96\xB6")

	local barBg = Instance.new("Frame"); barBg.AnchorPoint = Vector2.new(0.5,1); barBg.Position = UDim2.new(0.5,0,1,-46); barBg.Size = UDim2.new(1,-48,0,20)
	barBg.BackgroundColor3 = Color3.fromRGB(34,52,32); barBg.Parent = panel; Instance.new("UICorner", barBg).CornerRadius = UDim.new(0,10)
	local bar = Instance.new("Frame"); bar.Size = UDim2.new(0,0,1,0); bar.BackgroundColor3 = Color3.fromRGB(126,217,87); bar.BorderSizePixel = 0; bar.Parent = barBg
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0,10)
	local hint = Instance.new("TextLabel"); hint.BackgroundTransparency = 1; hint.AnchorPoint = Vector2.new(0.5,1); hint.Position = UDim2.new(0.5,0,1,-14); hint.Size = UDim2.new(1,-40,0,22)
	hint.Font = Enum.Font.Gotham; hint.TextSize = 13; hint.TextColor3 = Color3.fromRGB(240,246,220)
	hint.Text = "Side to side \xE2\x80\x94 the same side twice does nothing"; hint.Parent = panel

	local finished, fill, lastSide = false, 0, 0
	local ceiling = PickupFloor.newCeiling(0, PickupFloor.ISLAND1_EGG_SECONDS)
	local function finish(success)
		if finished then return end
		finished = true
		gui:Destroy()
		-- Put the egg back exactly as it was, whether we finished or bailed out. On
		-- success the server is about to fly it to the nest ring from its ORIGINAL
		-- pivot, so a half-rocked pose left behind here would make it jump.
		if baseCF then pcall(function() egg:PivotTo(baseCF) end) end
		if onDone then onDone(success) end
	end
	PickupFloor.addCloseButton(panel, function() finish(false) end)

	local function rock(side, btn)
		if finished then return end
		if side == lastSide then
			-- the whole point of the verb: mashing one side is not progress
			TS:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { BackgroundColor3 = Color3.fromRGB(120,96,64) }):Play()
			return
		end
		lastSide = side
		fill = ceiling:clamp(math.min(1, fill + 1 / ROCKS)) -- clamp on the INPUT path too
		eggIco.Rotation = side * 16
		TS:Create(eggIco, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Rotation = side * 6 }):Play()
		-- The winning rock pays out HERE, not a frame later in the loop. Waiting cost the
		-- player a frame of settle drain off a bar that was already at the ceiling.
		if fill >= DONE then
			bar.Size = UDim2.new(1, 0, 1, 0)
			finish(true)
		end
	end
	leftBtn.Activated:Connect(function() rock(-1, leftBtn) end)
	rightBtn.Activated:Connect(function() rock(1, rightBtn) end)

	task.spawn(function()
		local last = os.clock()
		while not finished do
			local now = os.clock(); local dt = math.min(now - last, 0.1); last = now
			ceiling:step(dt)
			fill = ceiling:clamp(math.max(0, fill - SETTLE * dt))
			bar.Size = UDim2.new(fill, 0, 1, 0)
			-- THE REAL EGG REACTS behind the 0.5 film: it works loose and lifts a
			-- believable amount -- just clear of the litter, not launched into the sky.
			if baseCF and egg.Parent then
				pcall(function()
					egg:PivotTo(baseCF
						* CFrame.new(0, fill * 0.7, 0)
						* CFrame.Angles(0, 0, math.rad(math.sin(now * 9) * 9 * (1 - fill * 0.7))))
				end)
			end
			if fill >= DONE then bar.Size = UDim2.new(1,0,1,0); finish(true); break end
			task.wait()
		end
	end)
end

-- the server hands us an egg -> run the minigame -> tell it we're done
eggCarry.OnClientEvent:Connect(function(egg)
	if busy or typeof(egg) ~= "Instance" then return end
	busy = true
	openRockMinigame(egg, function(success)
		busy = false
		if success then eggCarry:FireServer(egg) end
	end)
end)

print("[NestingNookEggs] ready -- LostEggs open the 15s rocking minigame")
