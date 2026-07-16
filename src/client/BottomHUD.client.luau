--======================================================================
-- BottomHUD.client.luau  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the BOTTOM-CENTER HUD STACK -- the three
-- elements at the bottom of the screen, with their EXACT sizes, colors,
-- fonts, and placement copied verbatim:
--
--   LayoutOrder 1 (TOP):    STOMACH / GUT PILL  -- pink pill, gut emoji + name
--   LayoutOrder 2 (MIDDLE): GAS METER           -- blue box, gold title + green fuel bar + %
--   LayoutOrder 3 (BOTTOM): FART BUTTON         -- green "HOLD TO FART!" button
--
-- HOW THE PLACEMENT WORKS: all three live in ONE container ("BottomStack")
-- anchored bottom-center (AnchorPoint 0.5,1 at Position 0.5,1,-12). A vertical
-- UIListLayout (HorizontalAlignment Center, VerticalAlignment Bottom, Padding 8)
-- stacks them sharing the EXACT same center, so they never drift apart. The
-- container AutomaticSize=Y so it hugs the three. ScreenGui IgnoreGuiInset=true,
-- DisplayOrder 5 (above the world, below menus at 100).
--
-- This is COSMETIC/visual only (no flight wiring).
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- scale: authored at ONE size (1.0) on every device. Phone/tablet fitting is handled globally by
-- ResponsiveUI.client.luau (a single UIScale per ScreenGui), so we do NOT bake a mobile shrink here
-- -- doing so would double-shrink the bottom HUD on phones. (Was: isMobile and 0.7.)
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale    = 1.0

-- ===== GUI HELPERS =====
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== GUT ASSETS -- per-tier emoji on the pill; XL Gut uses an image instead =====
local GUT_EMOJI = {
	["Hatchling Belly"] = "\xF0\x9F\xA5\x9A",            -- egg (baby dino)
	["Raptor Gut"]      = "\xF0\x9F\xA6\x8E",            -- lizard (raptor)
	["Stego Stomach"]   = "\xF0\x9F\xA6\xB4",            -- bone (stego)
	["Bronto Belly"]    = "\xF0\x9F\xA6\x95",            -- sauropod (bronto)
	["Rex Gut"]         = "\xF0\x9F\xA6\x96",            -- t-rex
	["Fossil Gut"]      = "\xF0\x9F\xAA\xA8",            -- rock (fossil)
	["Primal Gut"]      = "\xF0\x9F\x8C\x8B",            -- volcano (primal/infinite)
}
local GUT_IMAGE = "rbxassetid://108585083746103" -- legacy; unused now that all tiers use emoji
local stomachName = "Hatchling Belly" -- the current gut tier (drives the pill icon + name)

-- ============================================================================
-- BOTTOM-CENTER STACK CONTAINER -- the three elements all parent into this.
-- ============================================================================
local bottomStackGui = Instance.new("ScreenGui")
bottomStackGui.Name = "BottomStackGui"; bottomStackGui.ResetOnSpawn = false
bottomStackGui.IgnoreGuiInset = true; bottomStackGui.DisplayOrder = 5; bottomStackGui.Parent = PlayerGui
local bottomStack = Instance.new("Frame")
bottomStack.Name = "BottomStack"; bottomStack.AnchorPoint = Vector2.new(0.5, 1)
bottomStack.Position = UDim2.new(0.5, 0, 1, -12); bottomStack.Size = UDim2.new(0, 480, 0, 0)
bottomStack.AutomaticSize = Enum.AutomaticSize.Y; bottomStack.BackgroundTransparency = 1; bottomStack.Parent = bottomStackGui
do
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Vertical; sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center; sl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	sl.Padding = UDim.new(0, 8); sl.Parent = bottomStack -- matches the first realm's bottom-stack spacing (padding 8)
end

-- ===== JUNGLE CHROME (match the Pet Hub / Shop / Stats panel) =====
local okJC, JC = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10)) end)
if not okJC then JC = nil end
local STONE_A, STONE_B, STONE_D = Color3.fromRGB(224,204,150), Color3.fromRGB(202,178,118), Color3.fromRGB(148,116,66)
local VGREENS = { Color3.fromRGB(112,192,98), Color3.fromRGB(70,142,64), Color3.fromRGB(48,108,50) }

local OLIVE, OLIVE_E = Color3.fromRGB(122,142,82), Color3.fromRGB(40,52,38)
local CREAM, GOLD, DARKTXT = Color3.fromRGB(250,242,214), Color3.fromRGB(255,215,0), Color3.fromRGB(34,26,18)

-- stoneFrame: a fresh cobblestone-bordered panel (Pet Hub look) -- grey-tan rounded stones with
-- bevel highlight + speckle, an inset olive/green fill, leaf corner accents, and a soft drop shadow.
-- Returns (wrapper, content). Add your labels/bar/button to `content` (which is inset inside the border).
local function stoneFrame(w, h, fill, cornerR, layoutOrder)
	local B = 9 -- stone border thickness
	local wrap = mkFrame(bottomStack, { Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, LayoutOrder = layoutOrder })
	-- soft drop shadow (renders behind the stone backing)
	local shadow = mkFrame(wrap, { Size = UDim2.new(1,8,1,8), Position = UDim2.new(0.5,0,0.5,4), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.62, ZIndex = 1, BorderSizePixel = 0 }); mkCorner(shadow, cornerR + 4)
	-- stone backing
	local back = mkFrame(wrap, { Size = UDim2.new(1,0,1,0), BackgroundColor3 = STONE_B, ZIndex = 2, BorderSizePixel = 0 }); mkCorner(back, cornerR); mkStroke(back, STONE_D, 2)
	do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(STONE_A, Color3.fromRGB(184,158,100)); g.Parent = back end
	-- inset olive/green inner fill
	local content = mkFrame(back, { Size = UDim2.new(1,-B*2,1,-B*2), Position = UDim2.new(0.5,0,0.5,0), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = fill, ZIndex = 3, BorderSizePixel = 0 })
	mkCorner(content, math.max(4, cornerR - B)); mkStroke(content, OLIVE_E, 2)
	local cg = Instance.new("UIGradient"); cg.Rotation = 90
	cg.Color = ColorSequence.new(Color3.fromRGB(math.min(255, fill.R*255+10), math.min(255, fill.G*255+10), math.min(255, fill.B*255+10)), fill); cg.Parent = content
	-- cobblestone rocks around the border band (bevel highlight + speckle) -- in the B band, so they frame the content
	local function rock(cx, cy, sw, sh2)
		local r = mkFrame(back, { Size = UDim2.fromOffset(sw, sh2), Position = UDim2.fromOffset(cx, cy), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = STONE_B, ZIndex = 20, BorderSizePixel = 0 })
		mkCorner(r, math.floor(math.min(sw, sh2) * 0.42)); mkStroke(r, STONE_D, 1)
		local g = Instance.new("UIGradient"); g.Rotation = (sw > sh2) and 90 or 0; g.Color = ColorSequence.new(STONE_A, Color3.fromRGB(176,148,90)); g.Parent = r
		local hi = mkFrame(r, { BackgroundColor3 = Color3.fromRGB(244,230,184), BackgroundTransparency = 0.42, ZIndex = 21, BorderSizePixel = 0 })
		if sw > sh2 then hi.Size = UDim2.new(1,-6,0,2); hi.Position = UDim2.new(0,3,0,2) else hi.Size = UDim2.new(0,2,1,-6); hi.Position = UDim2.new(0,2,0,3) end
		mkCorner(hi, 1)
		for _, sp in ipairs({ {0.36,0.62}, {0.64,0.4} }) do local d = mkFrame(r, { Size = UDim2.fromOffset(2,2), Position = UDim2.new(sp[1],0,sp[2],0), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = STONE_D, BackgroundTransparency = 0.35, ZIndex = 21, BorderSizePixel = 0 }); mkCorner(d, 1) end
	end
	for x = B, w - B + 1, 24 do rock(x, math.floor(B/2), 22, B); rock(x, h - math.floor(B/2), 22, B) end
	for y = B + 4, h - B - 3, 22 do rock(math.floor(B/2), y, B, 18); rock(w - math.floor(B/2), y, B, 18) end
	-- leaf corner accents
	local function leaf(px, py, rot, ci)
		local L, lw = 15, 7
		local lf = mkFrame(back, { Size = UDim2.fromOffset(lw, L), Position = UDim2.fromOffset(px, py), AnchorPoint = Vector2.new(0.5,0.5), BackgroundColor3 = VGREENS[ci], ZIndex = 22, BorderSizePixel = 0 })
		lf.Rotation = rot; mkCorner(lf, math.floor(lw/2)); mkStroke(lf, Color3.fromRGB(30,72,32), 1)
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(VGREENS[ci], Color3.fromRGB(34,84,38)); g.Parent = lf
	end
	leaf(7, 6, -46, 1); leaf(w - 7, 6, 46, 2); leaf(7, h - 6, -134, 2); leaf(w - 7, h - 6, 134, 1)
	return wrap, content
end

local gui = {} -- holds the built elements

-- ============================================================================
-- (1) GUT NAME PILL  (LayoutOrder 1, small compact, centered) -- stone frame + olive fill
-- ============================================================================
local gutWrap, gutContent = stoneFrame(300, 40, OLIVE, 18, 1)  -- 300x40 to match the first realm's stomach pill
gutWrap.Name = "StomachHud"; gutWrap.ZIndex = 10
local stomachHudIcon = mkLabel(gutContent, { Name = "GutIcon", Text = (GUT_EMOJI[stomachName] or ""), Font = Enum.Font.GothamBold, TextScaled = true, Size = UDim2.new(0,22,0,22), Position = UDim2.new(0,6,0.5,0), AnchorPoint = Vector2.new(0,0.5), ZIndex = 6 })
local stomachHudLabel = mkLabel(gutContent, { Name = "StomachHudLabel", Text = stomachName, Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM, Size = UDim2.new(1,-36,1,-6), Position = UDim2.new(0,32,0.5,0), AnchorPoint = Vector2.new(0,0.5), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
mkStroke(stomachHudLabel, DARKTXT, 2)
local function updateStomachDisplay()
	stomachHudLabel.Text = stomachName
	stomachHudIcon.Text = GUT_EMOJI[stomachName] or stomachHudIcon.Text
end
updateStomachDisplay()
-- DYNAMIC name: keep the pill synced to the bought gut tier (reads StomachMax from leaderstats)
do
	local STOMACH_BY_MAX = { [100]="Hatchling Belly",[182]="Raptor Gut",[520]="Stego Stomach",[1075]="Bronto Belly",[2146]="Rex Gut",[3218]="Fossil Gut",[9999]="Primal Gut" }
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30); local sm = ls and ls:WaitForChild("StomachMax", 30)
		if not sm then return end
		local function refresh() stomachName = STOMACH_BY_MAX[sm.Value] or stomachName; updateStomachDisplay() end
		refresh(); sm:GetPropertyChangedSignal("Value"):Connect(refresh)
	end)
end

-- ============================================================================
-- (2) GAS METER  (LayoutOrder 2, compact full-width) -- stone frame + olive fill
-- ============================================================================
local gasWrap, gasContent = stoneFrame(480, 85, OLIVE, 16, 2)  -- 480x85 to match the first realm's gas meter
gasWrap.Name = "GasMeterPanel"; gui.gasMeterPanel = gasWrap
gui.gasTitleLabel = mkLabel(gasContent, { Text = "\xF0\x9F\x90\xBE  GAS METER  \xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextSize = math.floor(17*scale), TextColor3 = GOLD, Size = UDim2.new(1,0,0,28), Position = UDim2.new(0,0,0,6), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
mkStroke(gui.gasTitleLabel, DARKTXT, 2)
-- dark rounded STONE track
gui.gasBg = mkFrame(gasContent, { Name = "Track", Size = UDim2.new(1,-6,0,40), Position = UDim2.new(0.5,0,0,34), AnchorPoint = Vector2.new(0.5,0), BackgroundColor3 = Color3.fromRGB(28,34,26), ZIndex = 6, BorderSizePixel = 0 })  -- track h40 @ y34 to match the first realm
mkCorner(gui.gasBg, 11); mkStroke(gui.gasBg, Color3.fromRGB(16,20,14), 2)
-- bright green GRADIENT fill -- fills left-to-right to the gas %
gui.gasFill = mkFrame(gui.gasBg, { Name = "Fill", Size = UDim2.new(0,0,1,0), BackgroundColor3 = Color3.fromRGB(70,210,95), ZIndex = 7, BorderSizePixel = 0 })
mkCorner(gui.gasFill, 11)
gui.gasGradient = Instance.new("UIGradient"); gui.gasGradient.Rotation = 90; gui.gasGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(140,245,130)),ColorSequenceKeypoint.new(1,Color3.fromRGB(45,185,70))}); gui.gasGradient.Parent = gui.gasFill
gui.gasPowerText = mkLabel(gui.gasBg, { Size = UDim2.new(1,0,1,0), Text = "0%", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.fromRGB(255,255,255), ZIndex = 9, TextXAlignment = Enum.TextXAlignment.Center })
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = gui.gasPowerText end
mkStroke(gui.gasPowerText, DARKTXT, 2)
-- setGas(pct): drive the green fill + % -- SAME fill calc + % logic as before (untouched)
local function setGas(pct)
	pct = math.clamp(pct, 0, 100)
	gui.gasFill.Size = UDim2.new(pct/100, 0, 1, 0)
	gui.gasPowerText.Text = math.floor(pct) .. "%"
end
setGas(0)

-- ============================================================================
-- (3) HOLD TO FART BUTTON  (LayoutOrder 3, full width) -- stone frame + brighter green
-- ============================================================================
local fartWrap, fartContent = stoneFrame(480, 62, Color3.fromRGB(64,202,74), 16, 3)  -- 480x62 to match the first realm's fart button
fartWrap.Name = "FartBtnFrame"
gui.fartBtnFrame = fartContent -- the GREEN fill (setFartLook recolors this)
gui.fartBtnGradient = fartContent:FindFirstChildOfClass("UIGradient")
gui.fartCloudLabel = mkLabel(fartContent, { Text = "\xe2\x98\x81", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(255,255,255), Size = UDim2.new(0,34,0,34), Position = UDim2.new(0,16,0.5,0), AnchorPoint = Vector2.new(0,0.5), ZIndex = 7, RichText = false })
gui.fartBtn = mkButton(fartContent, { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "HOLD TO FART!", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM, ZIndex = 8, TextXAlignment = Enum.TextXAlignment.Center })
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 26; c.Parent = gui.fartBtn end
mkStroke(gui.fartBtn, Color3.fromRGB(20,70,20), 2)

-- ============================================================================
-- FART PROPEL / FLIGHT  (copied verbatim from PropelSystem_AllInOne):
--   tap fart -> BodyVelocity drives you straight UP (hands-free) while the gas
--   meter DRAINS; tap again BEFORE empty -> cancel but KEEP leftover gas (next
--   tap resumes); run dry -> auto-stop + fall; respawn -> reset to 0.
-- Fuel = the real food/gut stats (CurrentPower / StomachMax), so eating fills
-- the tank and a bigger gut flies faster + higher.
-- ============================================================================
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local maxGasMeter = 100   -- 0..100 normalized fuel bar
local DRAIN_RATE  = 3.5   -- gas drained per second of flight (full tank ~= 28s)
local FLIGHT_HORIZONTAL_SPEED = 48
local stomachMax  = 100   -- gut's max raw power (from StomachMax); bigger gut = faster + higher
local gasMeter    = 0     -- 0..100 normalized fuel (THE meter)
local currentPower= 0     -- raw power = (gasMeter/100)*stomachMax
local isFlying    = false
local bodyVel     = nil

-- rise speed by current (gas-scaled) power -- scales per gut tier (verbatim thresholds)
local function getFlightSpeed(power)
	if power <= 100 then return 40
	elseif power <= 182 then return 62
	elseif power <= 611 then return 84
	elseif power <= 1075 then return 126
	elseif power <= 2146 then return 144
	elseif power <= 3218 then return 226
	else return 280 end
end

-- meter fill from currentPower/stomachMax (== gasMeter%)
local function updateGasMeter()
	local pct = stomachMax > 0 and math.clamp(currentPower / stomachMax, 0, 1) * 100 or 0
	setGas(pct)
end

-- fart button look: idle vs farting
local function setFartLook(on)
	if on then
		gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(80,210,80)
		gui.fartBtnGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(120,240,120)),ColorSequenceKeypoint.new(1,Color3.fromRGB(60,180,60))})
		gui.fartBtn.Text = "FARTING! (TAP TO STOP)"
	else
		gui.fartBtnFrame.BackgroundColor3 = Color3.fromRGB(64,202,74)
		gui.fartBtnGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(120,236,96)),ColorSequenceKeypoint.new(1,Color3.fromRGB(52,184,52))})
		gui.fartBtn.Text = "HOLD TO FART!"
	end
end

-- fuel from the real food/gut system: seed from leaderstats + refuel on RegenEvent (BuyFood)
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local sm = ls and ls:WaitForChild("StomachMax", 30)
	local cp = ls and ls:WaitForChild("CurrentPower", 30)
	if sm then
		stomachMax = sm.Value
		sm:GetPropertyChangedSignal("Value"):Connect(function() stomachMax = sm.Value; updateGasMeter() end)
	end
	if cp then
		currentPower = cp.Value
		gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
		-- adopt the server's CurrentPower only when it INCREASES (a refuel); flying drains locally
		cp:GetPropertyChangedSignal("Value"):Connect(function()
			if cp.Value > currentPower then
				currentPower = cp.Value
				gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
				updateGasMeter()
			end
		end)
	end
	local regen = ReplicatedStorage:FindFirstChild("RegenEvent") or ReplicatedStorage:WaitForChild("RegenEvent", 20)
	if regen then
		regen.OnClientEvent:Connect(function(_added, newCurrent, newMax)
			if newMax then stomachMax = newMax end
			if newCurrent and newCurrent > currentPower then currentPower = newCurrent end
			gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0
			updateGasMeter()
		end)
	end
	updateGasMeter()
end)

-- start/stop (stopFlying KEEPS the meter -- only respawn zeroes it)
local function stopFlying()
	if not isFlying then return end
	isFlying = false; _G.isFlying = false; setFartLook(false)
	if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then local old = hrp:FindFirstChild("FartVelocity"); if old then old:Destroy() end; hrp.Anchored = false end
end
-- fart launch sounds: pick one at RANDOM each fart (toggle-on), 2D via SoundService
local FART_VOLUME = 0.6
local FART_SOUND_IDS = {
	"rbxassetid://137105349517966",
	"rbxassetid://136812322649032",
	"rbxassetid://119702591396866",
	"rbxassetid://123499328258921",
	"rbxassetid://92449881602559",
	"rbxassetid://109574021376037",
	"rbxassetid://129402830763074",
}
local fartSound = Instance.new("Sound"); fartSound.Name = "FartSound"; fartSound.Volume = FART_VOLUME
fartSound.Parent = game:GetService("SoundService")
local function playFartSound()
	fartSound:Stop() -- cut any in-progress fart so rapid re-toggles don't stack
	fartSound.SoundId = FART_SOUND_IDS[math.random(1, #FART_SOUND_IDS)]
	fartSound:Play()
end

local function startFlying()
	if isFlying then return end
	if currentPower <= 0 or gasMeter <= 0 then return end -- no fuel -> can't launch
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	isFlying = true; _G.isFlying = true; setFartLook(true)
	playFartSound() -- random fart sound on every launch
	-- tell the server the coins + fart power we launched with (Meteorite Explosion restores this on death)
	pcall(function() local e = ReplicatedStorage:FindFirstChild("MeteorLaunchSnapshot"); if e then e:FireServer() end end)
end
local function toggleFart()
	if isFlying then stopFlying()                 -- cancel ascent; leftover gas preserved
	elseif gasMeter > 0 then startFlying() end    -- begin/resume ascent
end
gui.fartBtn.Activated:Connect(toggleFart)
UserInputService.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.Space then toggleFart() end
end)

-- flight loop: thrust up while flying + gas left; drain; scale power by gas; stop at 0
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then if isFlying then stopFlying() end return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")
	if not hrp or not hum then if isFlying then stopFlying() end return end
	if hrp.Anchored then hrp.Anchored = false end
	if isFlying and gasMeter > 0 then
		gasMeter = math.max(0, gasMeter - DRAIN_RATE * dt)          -- DRAIN
		currentPower = (gasMeter / maxGasMeter) * stomachMax        -- power scaled by REMAINING gas
		-- Base ascent speed, scaled by any active flight modifier (e.g. Monsoon Rain's
		-- "wet conditions" sets _G.flightDistanceMultiplier = 0.9 for -10% flight distance).
		local speed = getFlightSpeed(currentPower) * (_G.flightDistanceMultiplier or 1)
		local move = hum.MoveDirection                             -- camera-relative steer
		if not bodyVel or not bodyVel.Parent then
			bodyVel = Instance.new("BodyVelocity"); bodyVel.Name = "FartVelocity"; bodyVel.Parent = hrp
		end
		bodyVel.MaxForce = Vector3.new(50000, 1e6, 50000)
		bodyVel.Velocity = Vector3.new(move.X * FLIGHT_HORIZONTAL_SPEED, speed, move.Z * FLIGHT_HORIZONTAL_SPEED)
		updateGasMeter()
		if gasMeter <= 0 then currentPower = 0; updateGasMeter(); stopFlying() end -- ran dry
	else
		if isFlying then stopFlying() end
		if bodyVel then bodyVel:Destroy(); bodyVel = nil end
	end
end)

-- respawn reset: the ONLY place the meter zeroes (eat again to refuel)
player.CharacterAdded:Connect(function()
	isFlying = false; _G.isFlying = false; if bodyVel then pcall(function() bodyVel:Destroy() end); bodyVel = nil end
	currentPower = 0; gasMeter = 0; setFartLook(false); updateGasMeter()
	-- re-seed fuel from the server shortly after spawn, so a Meteorite-Explosion respawn shows the
	-- fart power you launched with (the server restores CurrentPower for the dead players)
	task.spawn(function()
		task.wait(0.4)
		local ls = player:FindFirstChild("leaderstats"); local cp = ls and ls:FindFirstChild("CurrentPower")
		if cp then currentPower = cp.Value; gasMeter = stomachMax > 0 and (currentPower / stomachMax) * maxGasMeter or 0; updateGasMeter() end
	end)
end)

updateGasMeter()

setFartLook(false) -- green idle look on the rebuilt fart button
updateGasMeter()
print("[BottomHUD] REBUILT stone HUD -- gut pill + gas meter + HOLD TO FART; wired to real fuel + fart action")
