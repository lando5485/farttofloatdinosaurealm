--======================================================================
-- JungleChrome.luau  (ModuleScript, ReplicatedStorage.DinosaurRealm.JungleChrome)
--======================================================================
-- Shared jungle-panel chrome so the Shop matches the Pet Hub EXACTLY:
-- olive-green panel, bamboo border frame, corner+edge leaf vines, wooden
-- plaque header, glossy buttons. Same exact values as the Pet Hub.
--======================================================================
local JungleChrome = {}

local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

local STONE_A, STONE_B, STONE_D = Color3.fromRGB(224,204,150), Color3.fromRGB(202,178,118), Color3.fromRGB(148,116,66) -- bamboo
local VGREENS = { Color3.fromRGB(112,192,98), Color3.fromRGB(70,142,64), Color3.fromRGB(48,108,50) }
local VINE = Color3.fromRGB(96,86,48)

-- olive panel recolour (exact Pet Hub values)
function JungleChrome.stylePanel(panel)
	panel.BackgroundColor3 = Color3.fromRGB(122,142,82)
	local cor = panel:FindFirstChildOfClass("UICorner"); if cor then cor.CornerRadius = UDim.new(0,16) else uicorner(panel, 16) end
	local s = panel:FindFirstChildOfClass("UIStroke") or uistroke(panel, Color3.fromRGB(40,52,38), 2); s.Color = Color3.fromRGB(40,52,38); s.Thickness = 2
	if not panel:FindFirstChild("OliveGrad") then
		local g = Instance.new("UIGradient"); g.Name = "OliveGrad"; g.Rotation = 90
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(126,146,86)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(128,148,88)), ColorSequenceKeypoint.new(1, Color3.fromRGB(124,144,84)) })
		g.Parent = panel
	end
end

-- glossy top highlight on a button (same as the Pet Hub's gloss)
function JungleChrome.styleButton(btn)
	if btn:FindFirstChild("Gloss") then return end
	if not btn:FindFirstChildOfClass("UICorner") then uicorner(btn, 8) end
	local gl = Instance.new("Frame"); gl.Name = "Gloss"; gl.AnchorPoint = Vector2.new(0.5,0); gl.Position = UDim2.new(0.5,0,0,3); gl.Size = UDim2.new(1,-10,0,9)
	gl.BackgroundColor3 = Color3.new(1,1,1); gl.BorderSizePixel = 0; gl.ZIndex = (btn.ZIndex or 1) + 1; gl.Parent = btn; uicorner(gl, 6)
	local gg = Instance.new("UIGradient"); gg.Rotation = 90; gg.Transparency = NumberSequence.new(0.45, 1); gg.Parent = gl
end

-- bamboo shell + corner/edge leaf vines BEHIND a 700x520 panel; parent to the panel's ScreenGui.
function JungleChrome.buildShell(screenGui)
	if screenGui:FindFirstChild("JungleShell") then return screenGui.JungleShell end
	local shell = Instance.new("Frame"); shell.Name = "JungleShell"; shell.AnchorPoint = Vector2.new(0.5,0.5)
	shell.Position = UDim2.new(0.5,0,0.5,-45); shell.Size = UDim2.fromOffset(740,560); shell.BackgroundColor3 = STONE_B
	shell.ZIndex = 0; shell.Parent = screenGui; uicorner(shell, 26); uistroke(shell, STONE_D, 2)
	do local sg = Instance.new("UIGradient"); sg.Rotation = 90; sg.Color = ColorSequence.new(STONE_A, Color3.fromRGB(184,158,100)); sg.Parent = shell end
	local function rock(cx, cy, w, h)
		local horiz = w > h
		local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Position = UDim2.fromOffset(cx, cy); r.Size = UDim2.fromOffset(w, h)
		r.BackgroundColor3 = STONE_B; r.BorderSizePixel = 0; r.ZIndex = 0; r.Parent = shell
		uicorner(r, math.floor(math.min(w,h) * 0.46)); uistroke(r, STONE_D, 2)
		local g = Instance.new("UIGradient"); g.Rotation = horiz and 90 or 0; g.Color = ColorSequence.new(STONE_A, Color3.fromRGB(180,154,94)); g.Parent = r
		local hi = Instance.new("Frame"); hi.AnchorPoint = Vector2.new(0.5,0.5); hi.BackgroundColor3 = Color3.fromRGB(240,226,178); hi.BackgroundTransparency = 0.45; hi.BorderSizePixel = 0; hi.ZIndex = 0; hi.Parent = r
		if horiz then hi.Size = UDim2.new(1,-10,0,3); hi.Position = UDim2.new(0.5,0,0,4) else hi.Size = UDim2.new(0,3,1,-10); hi.Position = UDim2.new(0,4,0.5,0) end
		uicorner(hi, 2)
		for _, f in ipairs({ 0.3, 0.7 }) do
			local bind = Instance.new("Frame"); bind.AnchorPoint = Vector2.new(0.5,0.5); bind.BackgroundColor3 = STONE_D; bind.BackgroundTransparency = 0.12; bind.BorderSizePixel = 0; bind.ZIndex = 0; bind.Parent = r
			if horiz then bind.Size = UDim2.fromOffset(5, h); bind.Position = UDim2.new(f, 0, 0.5, 0) else bind.Size = UDim2.fromOffset(w, 5); bind.Position = UDim2.new(0.5, 0, f, 0) end
			uicorner(bind, 2)
		end
	end
	for x = 20, 720, 43 do rock(x, 16, 52, 38); rock(x, 544, 52, 38) end
	for y = 54, 506, 41 do rock(16, y, 38, 52); rock(724, y, 38, 52) end
	local function leaf(px, py, len, rot, ci)
		local w = math.max(8, math.floor(len * 0.42))
		local sh = Instance.new("Frame"); sh.AnchorPoint = Vector2.new(0.5,0.5); sh.Position = UDim2.new(0.5, px+2, 0.5, py+3); sh.Size = UDim2.fromOffset(w, len); sh.Rotation = rot; sh.BackgroundColor3 = Color3.new(0,0,0); sh.BackgroundTransparency = 0.62; sh.BorderSizePixel = 0; sh.ZIndex = 11; sh.Parent = shell; uicorner(sh, math.floor(w/2))
		local lf = Instance.new("Frame"); lf.AnchorPoint = Vector2.new(0.5,0.5); lf.Position = UDim2.new(0.5, px, 0.5, py); lf.Size = UDim2.fromOffset(w, len); lf.Rotation = rot; lf.BackgroundColor3 = VGREENS[ci]; lf.BorderSizePixel = 0; lf.ZIndex = 12; lf.Parent = shell; uicorner(lf, math.floor(w/2)); uistroke(lf, Color3.fromRGB(30,72,32), 1)
		local lg = Instance.new("UIGradient"); lg.Rotation = 90; lg.Color = ColorSequence.new(VGREENS[ci], Color3.fromRGB(34,84,38)); lg.Parent = lf
		local vein = Instance.new("Frame"); vein.AnchorPoint = Vector2.new(0.5,0.5); vein.Position = UDim2.new(0.5,0,0.5,0); vein.Size = UDim2.fromOffset(2, len-8); vein.BackgroundColor3 = Color3.fromRGB(38,88,40); vein.BackgroundTransparency = 0.25; vein.BorderSizePixel = 0; vein.ZIndex = 13; vein.Parent = lf; uicorner(vein, 1)
	end
	local function sprig(bx, by, ang, len, ci)
		local r = math.rad(ang); local dx, dy = math.sin(r), -math.cos(r)
		local plen = math.max(6, math.floor(len * 0.34))
		local pe = Instance.new("Frame"); pe.AnchorPoint = Vector2.new(0.5,0.5); pe.Position = UDim2.new(0.5, bx + dx*plen*0.5, 0.5, by + dy*plen*0.5); pe.Size = UDim2.fromOffset(3, plen); pe.Rotation = ang; pe.BackgroundColor3 = VINE; pe.BorderSizePixel = 0; pe.ZIndex = 11; pe.Parent = shell; uicorner(pe, 1)
		leaf(bx + dx*(plen + len*0.45), by + dy*(plen + len*0.45), len, ang, ci)
	end
	local function corner(cxp, cyp, a0, a1)
		local bx, by = cxp - 370, cyp - 280
		local knot = Instance.new("Frame"); knot.AnchorPoint = Vector2.new(0.5,0.5); knot.Position = UDim2.new(0.5, bx, 0.5, by); knot.Size = UDim2.fromOffset(14,14); knot.BackgroundColor3 = VINE; knot.BorderSizePixel = 0; knot.ZIndex = 11; knot.Parent = shell; uicorner(knot, 7)
		for i = 0, 4 do sprig(bx, by, a0 + (a1-a0)*(i/4), 26 + (i % 2)*6, (i % 3) + 1) end
	end
	corner(16, 16, 95, 175); corner(724, 16, 185, 265); corner(16, 544, 5, 85); corner(724, 544, 275, 355)
	sprig(-80, -266, 176, 24, 1); sprig(80, -266, 186, 22, 2)
	sprig(-80, 266, 4, 24, 2); sprig(80, 266, -6, 22, 1)
	sprig(-356, -50, 92, 22, 1); sprig(-356, 60, 88, 24, 3)
	sprig(356, -50, 268, 22, 2); sprig(356, 60, 272, 24, 1)
	return shell
end

-- wooden plaque header: recolour the header olive, add plaque + dino-skull + leaves, restyle title (cream) + subtitle + close button
function JungleChrome.plaqueHeader(header, titleLbl, subLbl, closeBtn)
	header.BackgroundColor3 = Color3.fromRGB(26,48,30)
	if not header:FindFirstChild("HdrGrad") then local g = Instance.new("UIGradient"); g.Name = "HdrGrad"; g.Rotation = 90; g.Color = ColorSequence.new(Color3.fromRGB(34,60,38), Color3.fromRGB(22,42,26)); g.Parent = header end
	local hs = header:FindFirstChildOfClass("UIStroke") or uistroke(header, Color3.fromRGB(74,94,68), 2); hs.Color = Color3.fromRGB(74,94,68)
	if not header:FindFirstChildOfClass("UICorner") then uicorner(header, 16) end
	local skull = Instance.new("TextLabel"); skull.BackgroundTransparency = 1; skull.Font = Enum.Font.FredokaOne; skull.TextSize = 30; skull.ZIndex = 3; skull.Text = "\xF0\x9F\xA6\x96"; skull.Size = UDim2.new(0,34,0,38); skull.Position = UDim2.new(0,12,0,8); skull.Parent = header
	for _, sl in ipairs({ {3,-3,11,-28}, {-3,7,9,28}, {21,5,8,58} }) do local le = Instance.new("Frame"); le.AnchorPoint = Vector2.new(0.5,0.5); le.Position = UDim2.new(0,12+sl[1],0,20+sl[2]); le.Size = UDim2.fromOffset(sl[3], math.floor(sl[3]*1.7)); le.BackgroundColor3 = Color3.fromRGB(72,144,66); le.BorderSizePixel = 0; le.Rotation = sl[4]; le.ZIndex = 1; le.Parent = header; uicorner(le, math.floor(sl[3]/2)); uistroke(le, Color3.fromRGB(34,84,38), 1) end
	local plaque = Instance.new("Frame"); plaque.Size = UDim2.new(0,212,0,34); plaque.Position = UDim2.new(0,50,0,7); plaque.BackgroundColor3 = Color3.fromRGB(126,84,48); plaque.BorderSizePixel = 0; plaque.ZIndex = 2; plaque.Parent = header
	uicorner(plaque, 8); uistroke(plaque, Color3.fromRGB(74,46,24), 2)
	do local pgr = Instance.new("UIGradient"); pgr.Rotation = 90; pgr.Color = ColorSequence.new(Color3.fromRGB(152,106,62), Color3.fromRGB(108,70,38)); pgr.Parent = plaque end
	for _, np in ipairs({ {0,0,7,7}, {1,0,-7,7}, {0,1,7,-7}, {1,1,-7,-7} }) do local nail = Instance.new("Frame"); nail.AnchorPoint = Vector2.new(0.5,0.5); nail.Position = UDim2.new(np[1],np[3],np[2],np[4]); nail.Size = UDim2.fromOffset(5,5); nail.BackgroundColor3 = Color3.fromRGB(70,44,22); nail.BorderSizePixel = 0; nail.ZIndex = 3; nail.Parent = plaque; uicorner(nail, 99) end
	if titleLbl then
		titleLbl.ZIndex = 3; titleLbl.TextColor3 = Color3.fromRGB(250,242,214); titleLbl.Font = Enum.Font.FredokaOne
		titleLbl.TextXAlignment = Enum.TextXAlignment.Center; titleLbl.Size = UDim2.new(0,212,0,34); titleLbl.Position = UDim2.new(0,50,0,7)
		local ts = titleLbl:FindFirstChildOfClass("UIStroke") or uistroke(titleLbl, Color3.fromRGB(60,38,18), 2); ts.Color = Color3.fromRGB(60,38,18)
	end
	if subLbl then subLbl.TextColor3 = Color3.fromRGB(245,236,208); subLbl.Font = Enum.Font.FredokaOne; subLbl.Position = UDim2.new(0,50,0,43); subLbl.Size = UDim2.new(0,260,0,16); subLbl.ZIndex = 3 end
	if closeBtn then closeBtn.BackgroundColor3 = Color3.fromRGB(214,64,60); local cs = closeBtn:FindFirstChildOfClass("UIStroke") or uistroke(closeBtn, Color3.new(0,0,0), 2); JungleChrome.styleButton(closeBtn) end
end

return JungleChrome
