--======================================================================
-- SeasonPass.client.luau  (LocalScript)
--======================================================================
-- The Season Pass track UI -- LIGHT / bright theme. All authority is the server's (SeasonPass.server.lua):
-- this draws the tiers and fires "claim"/"buy". Opens from More+ > Season Pass. Two lanes per tier:
-- FREE (top) and PLUS/premium (bottom). Same 700x520 shell + MainMenuManager wiring as the other menus
-- (hides the bottom HUD, closes on switch).
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("SeasonPassEvent", 30)
if not remote then return end

-- SINGLE-INSTANCE GUARD: if a duplicate copy of this script is already running, bail out (the old guard
-- DESTROYED both panels when two copies existed, which is why it stopped opening). First copy wins + owns
-- _G.toggleSeasonPass. Deleting the stale LocalScript in Studio is still the real fix.
if _G.__SeasonPassClientLoaded then return end
_G.__SeasonPassClientLoaded = true

local screen = Instance.new("ScreenGui")
screen.Name = "SeasonPassGui"; screen.ResetOnSpawn = false; screen.DisplayOrder = 57; screen.Parent = gui

local S = { xp = 0, tierXp = 100, earnedTier = 0, premium = false, forSale = false, tiers = {} }

--------------------------------------------------------------------------------
-- style helpers + LIGHT palette
--------------------------------------------------------------------------------
local function corner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst; return c end
local function stroke(inst, col, thick, trans)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = thick or 2; s.Transparency = trans or 0; s.Parent = inst; return s
end
local function gradient(inst, a, b, rot)
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(a, b); g.Rotation = rot or 90; g.Parent = inst; return g
end
local function padAll(inst, n) local p = Instance.new("UIPadding"); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do p[s] = UDim.new(0, n) end; p.Parent = inst; return p end

local COL_BG      = Color3.fromRGB(226, 219, 248) -- soft lavender panel (was near-white/washed) -> a visible premium gradient
local COL_BG2     = Color3.fromRGB(247, 244, 255)
local COL_INK     = Color3.fromRGB(46, 40, 78)    -- dark readable text on the light panel
local COL_PURPLE  = Color3.fromRGB(140, 100, 246)
local COL_PURP_D  = Color3.fromRGB(104, 68, 210)
local COL_GOLD    = Color3.fromRGB(255, 190, 55)
local COL_GOLD_D  = Color3.fromRGB(226, 152, 24)
local COL_GOLDINK = Color3.fromRGB(150, 96, 8)
local COL_GREEN   = Color3.fromRGB(66, 200, 108)
local COL_GREENINK= Color3.fromRGB(30, 130, 74)
local COL_FREE_A  = Color3.fromRGB(230, 250, 236) -- light mint card
local COL_FREE_B  = Color3.fromRGB(206, 240, 218)
local COL_PREM_A  = Color3.fromRGB(255, 247, 224) -- light gold card
local COL_PREM_B  = Color3.fromRGB(253, 236, 196)

--------------------------------------------------------------------------------
-- shell
--------------------------------------------------------------------------------
local dim = Instance.new("TextButton") -- transparent tap-outside-to-close catcher (matches the other menus)
dim.Size = UDim2.fromScale(1, 1); dim.BackgroundTransparency = 1
dim.Text = ""; dim.AutoButtonColor = false; dim.Visible = false; dim.Parent = screen

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -16) -- hub-parity screen spot (no phone clipping)
panel.Size = UDim2.fromOffset(700, 520); panel.BackgroundColor3 = COL_BG -- same size as the Shop / Daily Tasks
panel.Visible = false; panel.Parent = screen
corner(panel, 20); gradient(panel, COL_BG2, COL_BG, 90)
stroke(panel, COL_PURPLE, 3)

-- ---- header band (bright purple->blue, white text) ----
local header = Instance.new("Frame")
header.Position = UDim2.fromOffset(16, 14); header.Size = UDim2.new(1, -64, 0, 58)
header.BackgroundColor3 = COL_PURP_D; header.Parent = panel
corner(header, 14); gradient(header, Color3.fromRGB(160, 120, 255), Color3.fromRGB(120, 160, 255), 20)
stroke(header, Color3.fromRGB(255, 255, 255), 1.5, 0.35)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(16, 0); title.Size = UDim2.new(1, -140, 1, 0)
title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "\xE2\xAD\x90 SEASON PASS"; title.Parent = header
do local tc = Instance.new("UITextSizeConstraint", title); tc.MaxTextSize = 30 end
stroke(title, Color3.fromRGB(70, 40, 140), 2)

local tag = Instance.new("TextLabel") -- season / premium badge on the right of the header
tag.AnchorPoint = Vector2.new(1, 0.5); tag.Position = UDim2.new(1, -12, 0.5, 0); tag.Size = UDim2.fromOffset(118, 30)
tag.BackgroundColor3 = Color3.fromRGB(255, 252, 244); tag.Font = Enum.Font.GothamBold
tag.TextScaled = true; tag.TextColor3 = COL_GOLDINK; tag.Text = "SEASON 1"; tag.Parent = header
corner(tag, 9); stroke(tag, COL_GOLD, 1.5); padAll(tag, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 13); closeBtn.Size = UDim2.fromOffset(40, 40)
closeBtn.BackgroundColor3 = Color3.fromRGB(240, 84, 100); closeBtn.Font = Enum.Font.FredokaOne
closeBtn.Text = "X"; closeBtn.TextScaled = true; closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.ZIndex = 5; closeBtn.Parent = panel
corner(closeBtn, 11); stroke(closeBtn, Color3.fromRGB(190, 50, 64), 2); padAll(closeBtn, 9)

-- ---- info "?" button + "how it works" overlay (like the Shop / Pets have) ----
-- Wrapped in pcall so a UI glitch here can NEVER stop the rest of the script (which defines _G.toggleSeasonPass).
local okInfo, errInfo = pcall(function()
	local infoBtn = Instance.new("TextButton")
	infoBtn.AnchorPoint = Vector2.new(1, 0.5); infoBtn.Position = UDim2.new(1, -138, 0.5, 0); infoBtn.Size = UDim2.fromOffset(30, 30)
	infoBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255); infoBtn.Font = Enum.Font.FredokaOne; infoBtn.Text = "?"
	infoBtn.TextScaled = true; infoBtn.TextColor3 = COL_PURP_D; infoBtn.ZIndex = 4; infoBtn.Parent = header
	corner(infoBtn, 15); stroke(infoBtn, COL_PURP_D, 1.5); padAll(infoBtn, 5)

	local infoOverlay = Instance.new("TextButton") -- also acts as a tap-outside-to-close catcher
	infoOverlay.Size = UDim2.fromScale(1, 1); infoOverlay.AutoButtonColor = false; infoOverlay.Text = ""
	infoOverlay.BackgroundColor3 = Color3.fromRGB(40, 32, 70); infoOverlay.BackgroundTransparency = 0.2
	infoOverlay.Visible = false; infoOverlay.ZIndex = 30; infoOverlay.Parent = panel; corner(infoOverlay, 20)
	local infoCard = Instance.new("Frame")
	infoCard.AnchorPoint = Vector2.new(0.5, 0.5); infoCard.Position = UDim2.fromScale(0.5, 0.5); infoCard.Size = UDim2.fromOffset(520, 366)
	infoCard.BackgroundColor3 = COL_BG2; infoCard.ZIndex = 31; infoCard.Active = true; infoCard.Parent = infoOverlay
	corner(infoCard, 18); stroke(infoCard, COL_PURPLE, 3); gradient(infoCard, Color3.fromRGB(250, 248, 255), COL_BG, 90)
	local infoHdr = Instance.new("TextLabel")
	infoHdr.BackgroundTransparency = 1; infoHdr.Position = UDim2.fromOffset(22, 16); infoHdr.Size = UDim2.new(1, -44, 0, 40)
	infoHdr.Font = Enum.Font.FredokaOne; infoHdr.TextScaled = true; infoHdr.TextColor3 = COL_PURP_D
	infoHdr.TextXAlignment = Enum.TextXAlignment.Left; infoHdr.Text = "\xE2\xAD\x90 How the Season Pass works"; infoHdr.ZIndex = 32; infoHdr.Parent = infoCard
	do local c = Instance.new("UITextSizeConstraint", infoHdr); c.MaxTextSize = 25 end
	local infoBody = Instance.new("TextLabel")
	infoBody.BackgroundTransparency = 1; infoBody.Position = UDim2.fromOffset(24, 62); infoBody.Size = UDim2.new(1, -48, 1, -134)
	infoBody.Font = Enum.Font.GothamBold; infoBody.TextScaled = false; infoBody.TextSize = 17; infoBody.TextWrapped = true
	infoBody.TextColor3 = COL_INK; infoBody.TextXAlignment = Enum.TextXAlignment.Left; infoBody.TextYAlignment = Enum.TextYAlignment.Top
	infoBody.ZIndex = 32; infoBody.Parent = infoCard
	infoBody.Text = "Complete Daily Tasks to earn Season Pass XP \xE2\x80\x94 +25 XP each.\n\nEvery 100 XP fills the bar and unlocks the next tier (about 4 tasks per tier).\n\nEach tier has two lanes:\n\xF0\x9F\x9F\xA2 FREE \xE2\x80\x94 coins everyone gets\n\xF0\x9F\x91\x91 PLUS \xE2\x80\x94 bigger coins + pet levels (needs the Premium pass)\n\nOnce a tier is unlocked, press CLAIM on it to collect. Unclaimed rewards keep waiting for you!"
	local infoOk = Instance.new("TextButton")
	infoOk.AnchorPoint = Vector2.new(0.5, 1); infoOk.Position = UDim2.new(0.5, 0, 1, -16); infoOk.Size = UDim2.fromOffset(200, 46)
	infoOk.Font = Enum.Font.FredokaOne; infoOk.TextScaled = true; infoOk.TextColor3 = Color3.new(1, 1, 1); infoOk.Text = "GOT IT"
	infoOk.BackgroundColor3 = COL_PURPLE; infoOk.ZIndex = 32; infoOk.Parent = infoCard
	corner(infoOk, 12); stroke(infoOk, COL_PURP_D, 2); gradient(infoOk, Color3.fromRGB(170, 130, 255), COL_PURP_D, 90); padAll(infoOk, 8)
	infoBtn.Activated:Connect(function() infoOverlay.Visible = true end)
	infoOk.Activated:Connect(function() infoOverlay.Visible = false end)
	infoOverlay.MouseButton1Click:Connect(function() infoOverlay.Visible = false end)
	print("[SeasonPass] info button built OK")
end)
if not okInfo then warn("[SeasonPass] info button FAILED to build: " .. tostring(errInfo)) end

-- ---- XP progress bar + Get Premium ----
local buyBtn = Instance.new("TextButton")
buyBtn.AnchorPoint = Vector2.new(1, 0); buyBtn.Position = UDim2.new(1, -16, 0, 84); buyBtn.Size = UDim2.fromOffset(150, 40)
buyBtn.BackgroundColor3 = COL_GOLD; buyBtn.Font = Enum.Font.FredokaOne
buyBtn.TextScaled = true; buyBtn.TextColor3 = Color3.fromRGB(70, 40, 0); buyBtn.Text = "\xF0\x9F\x91\x91 GET PREMIUM"; buyBtn.Parent = panel
corner(buyBtn, 11); gradient(buyBtn, Color3.fromRGB(255, 224, 120), COL_GOLD_D, 90); stroke(buyBtn, COL_GOLDINK, 2); padAll(buyBtn, 7)
buyBtn.Activated:Connect(function() remote:FireServer("buy") end)

local barBg = Instance.new("Frame")
barBg.Position = UDim2.fromOffset(16, 86); barBg.Size = UDim2.new(1, -186, 0, 34)
barBg.BackgroundColor3 = Color3.fromRGB(228, 224, 244); barBg.Parent = panel
corner(barBg, 17); stroke(barBg, Color3.fromRGB(190, 182, 224), 1.5)
local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0); barFill.BackgroundColor3 = COL_PURPLE; barFill.Parent = barBg
corner(barFill, 17); gradient(barFill, Color3.fromRGB(180, 140, 255), Color3.fromRGB(120, 90, 240), 0)
local barLbl = Instance.new("TextLabel")
barLbl.Size = UDim2.fromScale(1, 1); barLbl.BackgroundTransparency = 1; barLbl.Font = Enum.Font.FredokaOne
barLbl.TextScaled = true; barLbl.TextColor3 = Color3.new(1, 1, 1); barLbl.ZIndex = 3; barLbl.Text = ""; barLbl.Parent = barBg
do local lc = Instance.new("UITextSizeConstraint", barLbl); lc.MaxTextSize = 17 end
stroke(barLbl, Color3.fromRGB(90, 66, 150), 2) -- dark outline -> white core reads on both the light track and the purple fill

-- ---- lane labels (left gutter) ----
local function laneLabel(text, y, fill, ink)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0, 0.5); l.Position = UDim2.fromOffset(14, y); l.Size = UDim2.fromOffset(66, 46)
	l.BackgroundColor3 = fill; l.Font = Enum.Font.FredokaOne
	l.TextColor3 = ink; l.Text = text; l.TextScaled = true; l.ZIndex = 3; l.Parent = panel
	corner(l, 10); stroke(l, ink, 1.5, 0.3); padAll(l, 6)
	return l
end
laneLabel("FREE", 238, COL_FREE_A, COL_GREENINK)
laneLabel("PLUS", 392, COL_PREM_A, COL_GOLDINK)

-- ---- CODES lives here now ----------------------------------------------------------------------------------
-- Redeeming a code used to be its own MORE+ entry, which is a whole menu row for a window the player opens
-- maybe twice ever. It sits in the left gutter under the lane labels instead -- the same 66px column, the same
-- pill shape -- so the two "free stuff" flows (season rewards, code rewards) are one place.
-- RewardsClient owns the window (_G.openCodesGui); this only opens it. Opening it routes through
-- MainMenuManager, which closes this panel underneath -- deliberate: one menu on screen at a time.
local codesBtn = Instance.new("TextButton")
codesBtn.AnchorPoint = Vector2.new(0, 0.5); codesBtn.Position = UDim2.fromOffset(14, 462); codesBtn.Size = UDim2.fromOffset(66, 52)
codesBtn.BackgroundColor3 = COL_GOLD; codesBtn.Font = Enum.Font.FredokaOne
codesBtn.Text = "\xF0\x9F\x8E\xAB CODES"; codesBtn.TextScaled = true; codesBtn.TextWrapped = true
codesBtn.TextColor3 = Color3.fromRGB(70, 40, 0); codesBtn.ZIndex = 3; codesBtn.Parent = panel
corner(codesBtn, 10); gradient(codesBtn, Color3.fromRGB(255, 224, 120), COL_GOLD_D, 90)
stroke(codesBtn, COL_GOLDINK, 2); padAll(codesBtn, 6)
codesBtn.Activated:Connect(function()
	if _G.openCodesGui then _G.openCodesGui() end
end)

--------------------------------------------------------------------------------
-- horizontal scroll of tier columns
--------------------------------------------------------------------------------
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(88, 132); scroll.Size = UDim2.new(1, -104, 0, 372)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollingDirection = Enum.ScrollingDirection.X
scroll.ScrollBarThickness = 8; scroll.ScrollBarImageColor3 = COL_PURPLE; scroll.CanvasSize = UDim2.new()
scroll.Active = true; scroll.Parent = panel
local hlist = Instance.new("UIListLayout", scroll); hlist.FillDirection = Enum.FillDirection.Horizontal
hlist.Padding = UDim.new(0, 10); hlist.SortOrder = Enum.SortOrder.LayoutOrder; hlist.VerticalAlignment = Enum.VerticalAlignment.Top
hlist:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, hlist.AbsoluteContentSize.X + 10, 0, 0)
end)

--------------------------------------------------------------------------------
-- tier columns
--------------------------------------------------------------------------------
local cols = {}

local function mkCard(parent, y, h, colA, colB, edge)
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(0, y); card.Size = UDim2.new(1, 0, 0, h)
	card.BackgroundColor3 = colA; card.Parent = parent
	corner(card, 12); gradient(card, colA, colB, 90); stroke(card, edge, 1.5)
	return card
end

local function mkReward(card, emoji, text, ink)
	local ico = Instance.new("TextLabel")
	ico.BackgroundTransparency = 1; ico.Position = UDim2.fromOffset(0, 12); ico.Size = UDim2.new(1, 0, 0, 40)
	ico.Font = Enum.Font.GothamBold; ico.TextScaled = true; ico.Text = emoji; ico.Parent = card
	do local ic = Instance.new("UITextSizeConstraint", ico); ic.MaxTextSize = 34 end
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1; lbl.Position = UDim2.fromOffset(2, 52); lbl.Size = UDim2.new(1, -4, 0, 42)
	lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.TextColor3 = ink; lbl.Text = text
	lbl.TextWrapped = true; lbl.Parent = card
end

local function mkClaim(card, lane, tierIndex)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 1); b.Position = UDim2.new(0.5, 0, 1, -8); b.Size = UDim2.new(1, -16, 0, 30)
	b.Font = Enum.Font.FredokaOne; b.TextScaled = true; b.TextColor3 = Color3.new(1, 1, 1); b.ZIndex = 3; b.Parent = card
	corner(b, 8); stroke(b, Color3.fromRGB(255, 255, 255), 1.2, 0.5)
	do local bp = Instance.new("UIPadding", b); bp.PaddingTop = UDim.new(0, 4); bp.PaddingBottom = UDim.new(0, 4) end
	b.Activated:Connect(function() remote:FireServer("claim", tierIndex, lane) end)
	return b
end

local function buildColumns()
	for _, c in ipairs(cols) do c.col:Destroy() end
	cols = {}
	for i, t in ipairs(S.tiers) do
		local col = Instance.new("Frame")
		col.Size = UDim2.new(0, 100, 1, 0); col.BackgroundTransparency = 1; col.LayoutOrder = i; col.Parent = scroll

		local numPill = Instance.new("TextLabel")
		numPill.AnchorPoint = Vector2.new(0.5, 0); numPill.Position = UDim2.new(0.5, 0, 0, 0); numPill.Size = UDim2.fromOffset(80, 26)
		numPill.BackgroundColor3 = Color3.fromRGB(236, 232, 250); numPill.Font = Enum.Font.FredokaOne
		numPill.TextScaled = true; numPill.TextColor3 = COL_PURP_D; numPill.Text = "TIER " .. i; numPill.Parent = col
		corner(numPill, 9); padAll(numPill, 4)
		local numStroke = stroke(numPill, Color3.fromRGB(200, 188, 240), 1.5)

		local free = mkCard(col, 36, 150, COL_FREE_A, COL_FREE_B, COL_GREEN)
		mkReward(free, "\xF0\x9F\xAA\x99", tostring(t.freeCoins), COL_GREENINK)
		local fBtn = mkClaim(free, "free", i)

		local prem = mkCard(col, 194, 150, COL_PREM_A, COL_PREM_B, COL_GOLD)
		local ptxt = tostring(t.premCoins)
		local pemoji = "\xF0\x9F\xAA\x99"
		if t.premPet and t.premPet > 0 then ptxt = ptxt .. "  +" .. t.premPet .. "\xF0\x9F\x90\xBE"; pemoji = "\xF0\x9F\x91\x91" end
		mkReward(prem, pemoji, ptxt, COL_GOLDINK)
		local pBtn = mkClaim(prem, "prem", i)

		cols[i] = { col = col, numStroke = numStroke, numPill = numPill, free = free, prem = prem, fBtn = fBtn, pBtn = pBtn }
	end
end

--------------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------------
local function styleBtn(btn, kind)
	-- kind: "claim" | "claimed" | "locked" | "lockedPrem" -- colours tuned for the light cards
	if kind == "claimed" then
		btn.Text = "CLAIMED \xE2\x9C\x94"; btn.BackgroundColor3 = Color3.fromRGB(206, 212, 226); btn.TextColor3 = Color3.fromRGB(92, 98, 116); btn.Active = false; btn.AutoButtonColor = false
	elseif kind == "claim" then
		btn.Text = "CLAIM"; btn.BackgroundColor3 = COL_GREEN; btn.TextColor3 = Color3.new(1, 1, 1); btn.Active = true; btn.AutoButtonColor = true
	elseif kind == "lockedPrem" then
		btn.Text = "\xF0\x9F\x94\x92 PLUS"; btn.BackgroundColor3 = Color3.fromRGB(240, 222, 176); btn.TextColor3 = COL_GOLDINK; btn.Active = false; btn.AutoButtonColor = false
	else
		btn.Text = "\xF0\x9F\x94\x92"; btn.BackgroundColor3 = Color3.fromRGB(222, 218, 238); btn.TextColor3 = Color3.fromRGB(140, 134, 168); btn.Active = false; btn.AutoButtonColor = false
	end
end

local function redraw()
	local frac = math.clamp((S.xp % S.tierXp) / S.tierXp, 0, 1)
	if S.earnedTier >= #S.tiers then frac = 1 end
	TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
	barLbl.Text = ("TIER %d  \xE2\x80\xA2  %d / %d XP"):format(S.earnedTier, S.xp % S.tierXp, S.tierXp)

	buyBtn.Visible = S.forSale and not S.premium
	tag.Text = S.premium and "\xF0\x9F\x91\x91 PREMIUM" or "SEASON 1"

	if #cols ~= #S.tiers then buildColumns() end
	for i, t in ipairs(S.tiers) do
		local c = cols[i]; if not c then break end
		local earned = i <= S.earnedTier
		styleBtn(c.fBtn, t.freeClaimed and "claimed" or (earned and "claim" or "locked"))
		if t.premClaimed then styleBtn(c.pBtn, "claimed")
		elseif not S.premium then styleBtn(c.pBtn, "lockedPrem")
		elseif earned then styleBtn(c.pBtn, "claim")
		else styleBtn(c.pBtn, "locked") end

		-- highlight the tier you're actively filling (the next one you'll earn)
		local isCurrent = (i == S.earnedTier + 1) and (S.earnedTier < #S.tiers)
		c.numStroke.Color = isCurrent and COL_GOLD or Color3.fromRGB(200, 188, 240)
		c.numStroke.Thickness = isCurrent and 2.5 or 1.5
		c.numPill.BackgroundColor3 = isCurrent and Color3.fromRGB(255, 244, 214) or Color3.fromRGB(236, 232, 250)
		c.numPill.TextColor3 = isCurrent and COL_GOLDINK or COL_PURP_D
		c.numPill.Text = isCurrent and ("\xE2\x96\xB6 TIER " .. i) or ("TIER " .. i)
		-- not-yet-earned tiers dim back a touch so earned ones pop
		c.free.BackgroundTransparency = earned and 0 or 0.35
		c.prem.BackgroundTransparency = earned and 0 or 0.35
	end
end

--------------------------------------------------------------------------------
-- open/close + server
--------------------------------------------------------------------------------
local MENU_NAME = "SeasonPass"
local function setOpen(o)
	dim.Visible = o
	if o then
		if _G.MainMenuManager then _G.MainMenuManager.notifyOpened(MENU_NAME) end -- closes other menus + hides the bottom HUD
		panel.Visible = true
		panel.Size = UDim2.fromOffset(660, 490)
		TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(700, 520) }):Play()
		redraw()
	else
		panel.Visible = false
		if _G.MainMenuManager then _G.MainMenuManager.notifyClosed(MENU_NAME) end -- restores the bottom HUD
	end
end
_G.toggleSeasonPass = function() setOpen(not panel.Visible) end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
-- MainMenuManager closing it because another menu opened.

-- STALE-DUPLICATE DEFENSE: an old baked-in copy of this script (it prints "[SeasonPass] client ready" at a
-- DIFFERENT line) builds its own SeasonPassGui and steals _G.toggleSeasonPass, so More+ opens a dead panel.
-- Destroy any OTHER SeasonPassGui and RE-CLAIM the toggle for THIS (working) panel, now and whenever a dup
-- appears. Targets SeasonPassGui ONLY. (Deleting the stale LocalScript in Studio is the real fix.)
local function claimSeasonPass()
	for _, g in ipairs(gui:GetChildren()) do
		if g ~= screen and g:IsA("ScreenGui") and g.Name == "SeasonPassGui" then g:Destroy() end
	end
	_G.toggleSeasonPass = function() setOpen(not panel.Visible) end
end
task.defer(claimSeasonPass)
gui.ChildAdded:Connect(function(c)
	if c ~= screen and c:IsA("ScreenGui") and c.Name == "SeasonPassGui" then task.defer(claimSeasonPass) end
end)

-- let the manager slam us shut when another menu opens over us (wait for it -- load order isn't guaranteed)
task.spawn(function()
	for _ = 1, 100 do
		if _G.MainMenuManager then _G.MainMenuManager.register(MENU_NAME, function() panel.Visible = false; dim.Visible = false end); return end
		task.wait(0.1)
	end
end)

remote.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "state" and type(a) == "table" then
		S = a; S.tiers = S.tiers or {}
		if panel.Visible then redraw() end
	elseif kind == "result" then
		-- a=tier, b=lane, c=ok, d=msg  (a tiny center note)
		if _G.showHudBanner and d then _G.showHudBanner(d, c and Color3.fromRGB(90, 220, 110) or Color3.fromRGB(255, 150, 90), 2.5) end
		if panel.Visible then redraw() end
	end
end)

print("[SeasonPass] client ready -- light-theme track UI (opens from More+)")
