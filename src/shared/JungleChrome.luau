--======================================================================
-- JungleChrome.luau  (ModuleScript, ReplicatedStorage.DinosaurRealm.JungleChrome)
--======================================================================
-- Shared jungle-panel chrome so the Shop matches the Pet Hub EXACTLY:
-- olive-green panel, bamboo border frame, wooden plaque header, glossy
-- buttons. Same exact values as the Pet Hub.
--
-- NO FOLIAGE. Every leaf, vine, sprig and corner fan was removed by request. The bamboo
-- rocks stayed -- they ARE the border, not decoration laid over it.
--======================================================================
local JungleChrome = {}

local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

local STONE_A, STONE_B, STONE_D = Color3.fromRGB(224,204,150), Color3.fromRGB(202,178,118), Color3.fromRGB(148,116,66) -- bamboo
-- The VGREENS leaf palette and the VINE strand colour were removed with the foliage --
-- nothing in this module draws a leaf any more.

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
	shell.Position = UDim2.new(0.5,0,0.5,-16); shell.Size = UDim2.fromOffset(740,560); shell.BackgroundColor3 = STONE_B  -- HUB PARITY: -16 lands panels at the hub's exact screen spot (its -45 in an inset-respecting gui) WITHOUT clipping phone tops
	shell.ZIndex = 0; shell.Parent = screenGui; shell.BackgroundTransparency = 1 -- BAMBOO FRAME REMOVED by request: invisible placeholder so callers can still track it
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
	-- rock rows removed (no wood/bamboo border)
	-- FOLIAGE REMOVED: the four corner leaf-fans and the eight edge sprigs. This function
	-- is shared, so those leaves were being drawn on the Shop and on every panel
	-- JungleTheme restyles -- removing them here clears all of them at once.
	-- The BAMBOO ROCKS stay: they are the border itself, not an accent on top of it.
	return shell
end

-- ============================================================================
-- buildShellAround(parent, w, h) -- the same bamboo shell, at ANY size.
-- ============================================================================
-- buildShell() above is hard-coded to 740x560: the rock rows step `for x = 20, 720`,
-- the bottom row sits at y=544, and the corner knots offset by `cxp - 370, cyp - 280`.
-- Resizing that Frame afterwards shrinks the tan backing but leaves every rock and leaf
-- where it was -- a border drawn around empty space. Anything whose panel is not exactly
-- 700x520 has to use this instead.
--
-- Rebuilds from scratch rather than patching, because the decoration is positional.
function JungleChrome.buildShellAround(parent, w, h)
	local old = parent:FindFirstChild("JungleShell")
	if old then old:Destroy() end

	local shell = Instance.new("Frame"); shell.Name = "JungleShell"
	shell.AnchorPoint = Vector2.new(0.5, 0.5); shell.Position = UDim2.new(0.5, 0, 0.5, -16) -- hub-parity lift (callers that track a panel overwrite this)
	shell.Size = UDim2.fromOffset(w, h); shell.BackgroundTransparency = 1 -- BAMBOO FRAME REMOVED by request
	shell.ZIndex = 0; shell.Parent = parent
	local band = math.clamp(math.floor(math.min(w, h) * 0.075), 10, 26)
	uicorner(shell, math.min(26, math.floor(math.min(w, h) * 0.18)))
	-- (stroke + tan gradient removed)

	local function rock(cx, cy, rw, rh)
		local horiz = rw > rh
		local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5)
		r.Position = UDim2.fromOffset(cx, cy); r.Size = UDim2.fromOffset(rw, rh)
		r.BackgroundColor3 = STONE_B; r.BorderSizePixel = 0; r.ZIndex = 0; r.Parent = shell
		uicorner(r, math.floor(math.min(rw,rh) * 0.46)); uistroke(r, STONE_D, 2)
		local g = Instance.new("UIGradient"); g.Rotation = horiz and 90 or 0
		g.Color = ColorSequence.new(STONE_A, Color3.fromRGB(180,154,94)); g.Parent = r
		local hi = Instance.new("Frame"); hi.AnchorPoint = Vector2.new(0.5,0.5)
		hi.BackgroundColor3 = Color3.fromRGB(240,226,178); hi.BackgroundTransparency = 0.45
		hi.BorderSizePixel = 0; hi.ZIndex = 0; hi.Parent = r
		if horiz then hi.Size = UDim2.new(1,-6,0,2); hi.Position = UDim2.new(0.5,0,0,3)
		else hi.Size = UDim2.new(0,2,1,-6); hi.Position = UDim2.new(0,3,0.5,0) end
		uicorner(hi, 2)
	end

	-- Spacing DIVIDES the run evenly so the last stone lands flush in the corner. A fixed
	-- 43px step (what buildShell uses) leaves a ragged gap at any width that isn't 740.
	local long, short = math.floor(band * 2.9), math.floor(band * 2.1)
	local function runX(cy)
		local usable = w - band * 2
		local n = math.max(2, math.floor(usable / (long + 3)))
		for i = 0, n do rock(band + (usable / n) * i, cy, long, short) end
	end
	local function runY(cx)
		local usable = h - band * 2
		local n = math.max(1, math.floor(usable / (long + 3)))
		for i = 0, n do rock(cx, band + (usable / n) * i, short, long) end
	end
	-- runX/runY rock rows removed (no wood/bamboo border)

	-- FOLIAGE REMOVED here too -- the four corner knots and their leaf fans. Same reason as
	-- buildShell above; this is the any-size variant and shares its callers.
	return shell
end

-- wooden plaque header: recolour the header olive, add plaque + dino-skull + leaves, restyle title (cream) + subtitle + close button
function JungleChrome.plaqueHeader(header, titleLbl, subLbl, closeBtn)
	header.BackgroundColor3 = Color3.fromRGB(26,48,30)
	if not header:FindFirstChild("HdrGrad") then local g = Instance.new("UIGradient"); g.Name = "HdrGrad"; g.Rotation = 90; g.Color = ColorSequence.new(Color3.fromRGB(34,60,38), Color3.fromRGB(22,42,26)); g.Parent = header end
	local hs = header:FindFirstChildOfClass("UIStroke") or uistroke(header, Color3.fromRGB(74,94,68), 2); hs.Color = Color3.fromRGB(74,94,68)
	if not header:FindFirstChildOfClass("UICorner") then uicorner(header, 16) end
	local skull = Instance.new("TextLabel"); skull.BackgroundTransparency = 1; skull.Font = Enum.Font.FredokaOne; skull.TextSize = 30; skull.ZIndex = 3; skull.Text = "\xF0\x9F\xA6\x96"; skull.Size = UDim2.new(0,34,0,38); skull.Position = UDim2.new(0,12,0,8); skull.Parent = header
	-- FOLIAGE REMOVED: the three small leaves that fanned out from behind the skull glyph.
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
