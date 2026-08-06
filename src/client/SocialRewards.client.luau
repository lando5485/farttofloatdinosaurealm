--======================================================================
-- SocialRewards.client.luau  (LocalScript)
--======================================================================
-- The "Free Rewards" panel: Like, Favourite, Join Group -- each a one-time claim worth +5 levels on your
-- EQUIPPED pet. All authority is the server's (SocialRewards.server.lua); this only draws the buttons and
-- fires "claim". Opens from More+ > Free Rewards (see the entry added in CoreClient).
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui    = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("SocialRewardEvent", 30)
if not remote then return end

-- SINGLE-INSTANCE GUARD: if a duplicate copy of this script is already running, bail out (the old guard
-- DESTROYED both panels when two copies existed, which is why Free Rewards stopped opening). First copy wins
-- + owns _G.toggleSocialRewards. Deleting the stale LocalScript in Studio is still the real fix.
if _G.__SocialRewardsClientLoaded then return end
_G.__SocialRewardsClientLoaded = true

local screen = Instance.new("ScreenGui")
screen.Name = "SocialRewardsGui"; screen.ResetOnSpawn = false; screen.IgnoreGuiInset = false
screen.DisplayOrder = 56; screen.Parent = gui

-- Kill any STALE duplicate SocialRewardsGui: an old baked-in copy of this script draws an empty black toast
-- that sits over the bottom HUD ("the black bar"). Only THIS guarded copy runs the cleanup (the stale old copy
-- has no such code + a second copy of THIS script bails at the guard above), so there's no mutual-destroy.
-- Targets SocialRewardsGui ONLY -- never sweeps the rest of PlayerGui. (Deleting the stale script in Studio is the real fix.)
do
	local function killStale()
		for _, g in ipairs(gui:GetChildren()) do
			if g ~= screen and g:IsA("ScreenGui") and g.Name == "SocialRewardsGui" then g:Destroy() end
		end
	end
	task.defer(killStale)
	gui.ChildAdded:Connect(function(c)
		if c ~= screen and c:IsA("ScreenGui") and c.Name == "SocialRewardsGui" then c:Destroy() end
	end)
end

local state = { like = false, favorite = false, group = false, isMember = false }

--------------------------------------------------------------------------------
-- panel
--------------------------------------------------------------------------------
local dim = Instance.new("TextButton") -- transparent tap-outside-to-close catcher (matches the other menus)
dim.Size = UDim2.fromScale(1, 1); dim.BackgroundTransparency = 1
dim.Text = ""; dim.AutoButtonColor = false; dim.Visible = false; dim.Parent = screen

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -16) -- hub-parity screen spot (no phone clipping)
panel.Size = UDim2.fromOffset(700, 520); panel.BackgroundColor3 = Color3.fromRGB(28, 24, 46) -- same size as the Shop / Daily Tasks
panel.Visible = false; panel.Parent = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local pStroke = Instance.new("UIStroke", panel); pStroke.Color = Color3.fromRGB(255, 200, 90); pStroke.Thickness = 3

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 46); title.Position = UDim2.fromOffset(10, 10); title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255, 216, 120)
title.Text = "\xF0\x9F\x8E\x81 Rewards"; title.Parent = panel
local tStroke = Instance.new("UIStroke", title); tStroke.Color = Color3.new(0, 0, 0); tStroke.Thickness = 2

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1, -24, 0, 34); sub.Position = UDim2.fromOffset(12, 56); sub.BackgroundTransparency = 1
sub.Font = Enum.Font.GothamBold; sub.TextScaled = true; sub.TextColor3 = Color3.fromRGB(200, 210, 235)
sub.Text = "Daily crate + free rewards -- levels go to your EQUIPPED pet!"; sub.TextWrapped = true; sub.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -12, 0, 33); closeBtn.Size = UDim2.fromOffset(40, 40)
closeBtn.BackgroundColor3 = Color3.fromRGB(212, 68, 84); closeBtn.Font = Enum.Font.FredokaOne
closeBtn.Text = "X"; closeBtn.TextScaled = true; closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

local list = Instance.new("Frame")
list.Size = UDim2.new(1, -40, 1, -130); list.Position = UDim2.fromOffset(20, 108); list.BackgroundTransparency = 1
list.Parent = panel
local layout = Instance.new("UIListLayout", list); layout.Padding = UDim.new(0, 10); layout.SortOrder = Enum.SortOrder.LayoutOrder
-- rows are narrower than the list now, so centre them for an even margin both sides
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
-- Was Center, which suited 3 equal rows. With two section headings and a fourth
-- card the group is taller than the box, so centring pushed the first heading off
-- the top. Top-aligned now.
layout.VerticalAlignment = Enum.VerticalAlignment.Top

local rows = {}
local function mkRow(which, emoji, labelText, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 64); row.BackgroundColor3 = Color3.fromRGB(40, 36, 62); row.LayoutOrder = order; row.Parent = list
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

	local ico = Instance.new("TextLabel")
	ico.Size = UDim2.fromOffset(40, 48); ico.Position = UDim2.fromOffset(10, 8); ico.BackgroundTransparency = 1
	ico.Font = Enum.Font.FredokaOne; ico.TextScaled = true; ico.Text = emoji; ico.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -178, 1, 0); lbl.Position = UDim2.fromOffset(56, 0); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true; lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = labelText; lbl.Parent = row
	local sizeC = Instance.new("UITextSizeConstraint", lbl); sizeC.MaxTextSize = 17

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5); btn.Position = UDim2.new(1, -10, 0.5, 0); btn.Size = UDim2.fromOffset(104, 38)
	btn.Font = Enum.Font.FredokaOne; btn.TextScaled = true; btn.TextColor3 = Color3.new(1, 1, 1); btn.Parent = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	local bpad = Instance.new("UIPadding", btn); bpad.PaddingLeft = UDim.new(0, 8); bpad.PaddingRight = UDim.new(0, 8)
	bpad.PaddingTop = UDim.new(0, 8); bpad.PaddingBottom = UDim.new(0, 8)
	btn.Activated:Connect(function() remote:FireServer("claim", which) end)

	rows[which] = { row = row, btn = btn }
end
--------------------------------------------------------------------------------
-- DAILY LOGIN section
--------------------------------------------------------------------------------
-- Daily Rewards used to be its own MORE+ row, but it has no panel of its own: tapping
-- it fires OpenMeteorCrate, which claims immediately and plays a full-screen reveal.
-- There was nothing to browse, so it lives here as one card rather than a second tab --
-- sub-sections rather than tabs, because a tab holding a single button is worse than a
-- heading holding a single button.
--
-- The claim itself is NOT reimplemented. This fires the same BindableEvent the old row
-- did, so the crate service, the ownership check and the reveal are all untouched.
local function sectionHeader(text, order)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, -24, 0, 18); h.BackgroundTransparency = 1; h.LayoutOrder = order
	h.Font = Enum.Font.GothamBold; h.TextSize = 13
	h.TextColor3 = Color3.fromRGB(255, 216, 120)
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = text; h.Parent = list
	return h
end

sectionHeader("DAILY LOGIN", 0)

local dailyRow = Instance.new("Frame")
dailyRow.Size = UDim2.new(1, -24, 0, 64); dailyRow.BackgroundColor3 = Color3.fromRGB(40, 36, 62)
dailyRow.LayoutOrder = 1; dailyRow.Parent = list
Instance.new("UICorner", dailyRow).CornerRadius = UDim.new(0, 12)
do
	local ico = Instance.new("TextLabel")
	ico.Size = UDim2.fromOffset(40, 48); ico.Position = UDim2.fromOffset(10, 8); ico.BackgroundTransparency = 1
	ico.Font = Enum.Font.FredokaOne; ico.TextScaled = true; ico.Text = "\xF0\x9F\x8E\x81"; ico.Parent = dailyRow

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -178, 1, 0); lbl.Position = UDim2.fromOffset(56, 0); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true; lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = "Daily crate \xE2\x80\x94 free pet levels"
	lbl.Parent = dailyRow
	Instance.new("UITextSizeConstraint", lbl).MaxTextSize = 17
end
local dailyBtn = Instance.new("TextButton")
dailyBtn.AnchorPoint = Vector2.new(1, 0.5); dailyBtn.Position = UDim2.new(1, -10, 0.5, 0)
dailyBtn.Size = UDim2.fromOffset(104, 38)
dailyBtn.Font = Enum.Font.FredokaOne; dailyBtn.TextScaled = true; dailyBtn.TextColor3 = Color3.new(1, 1, 1)
dailyBtn.Parent = dailyRow
Instance.new("UICorner", dailyBtn).CornerRadius = UDim.new(0, 10)
do
	local p = Instance.new("UIPadding", dailyBtn)
	p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8)
	p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8)
end
dailyBtn.Activated:Connect(function()
	local RSx = game:GetService("ReplicatedStorage")
	local ev = RSx:FindFirstChild("OpenMeteorCrate")
	if not ev then ev = Instance.new("BindableEvent"); ev.Name = "OpenMeteorCrate"; ev.Parent = RSx end
	ev:Fire()
end)

sectionHeader("FREE REWARDS", 2)
mkRow("like",     "\xF0\x9F\x91\x8D", "Like the game",  3) -- 👍
mkRow("favorite", "\xE2\xAD\x90",     "Favourite it",   4) -- ⭐
mkRow("group",    "\xF0\x9F\x91\xA5", "Join the group", 5) -- 👥

local function redraw()
	-- daily crate: same _G.crateIsClaimable the MORE+ badge reads, so the button and the
	-- red "!" can never disagree about whether there is something to claim
	local dailyReady = (_G.crateIsClaimable and _G.crateIsClaimable()) == true
	dailyBtn.Text = dailyReady and "CLAIM" or "Claimed â"
	dailyBtn.BackgroundColor3 = dailyReady and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(70, 78, 96)
	dailyBtn.Active = dailyReady
	for which, r in pairs(rows) do
		if state[which] then
			r.btn.Text = "Claimed \xE2\x9C\x94"; r.btn.BackgroundColor3 = Color3.fromRGB(70, 78, 96); r.btn.Active = false
		elseif which == "group" and not state.isMember then
			r.btn.Text = "Join first"; r.btn.BackgroundColor3 = Color3.fromRGB(90, 130, 235); r.btn.Active = true
		else
			r.btn.Text = "CLAIM +5"; r.btn.BackgroundColor3 = Color3.fromRGB(70, 200, 90); r.btn.Active = true
		end
	end
end

--------------------------------------------------------------------------------
-- a tiny centre toast for the claim result
--------------------------------------------------------------------------------
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0.5); toast.Position = UDim2.fromScale(0.5, 0.82); toast.Size = UDim2.fromOffset(420, 52)
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 30); toast.BackgroundTransparency = 0.1
toast.Font = Enum.Font.FredokaOne; toast.TextScaled = true; toast.TextColor3 = Color3.new(1, 1, 1)
toast.Text = ""; toast.Visible = false; toast.Parent = screen
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)
local toastStroke = Instance.new("UIStroke", toast); toastStroke.Thickness = 2
local toastPad = Instance.new("UIPadding", toast); toastPad.PaddingLeft = UDim.new(0, 12); toastPad.PaddingRight = UDim.new(0, 12)
local toastToken = 0
local function showToast(text, ok)
	if not text or text == "" then toast.Visible = false; return end -- never show an empty black box
	toastToken += 1; local mine = toastToken
	toast.Text = text; toastStroke.Color = ok and Color3.fromRGB(90, 220, 110) or Color3.fromRGB(255, 150, 90)
	toast.Visible = true
	task.delay(3, function() if toastToken == mine then toast.Visible = false end end)
end

--------------------------------------------------------------------------------
-- open/close + server messages
--------------------------------------------------------------------------------
local MENU_NAME = "SocialRewards"
local function setOpen(o)
	panel.Visible = o; dim.Visible = o
	if o then
		if _G.MainMenuManager then _G.MainMenuManager.notifyOpened(MENU_NAME) end -- closes other menus + hides the bottom HUD
		redraw()
	else
		if _G.MainMenuManager then _G.MainMenuManager.notifyClosed(MENU_NAME) end -- restores the bottom HUD
	end
end
_G.toggleSocialRewards = function() setOpen(not panel.Visible) end
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
-- MainMenuManager closing it because another menu opened.

-- STALE-DUPLICATE DEFENSE: an old baked-in copy prints "[Social] client ready" at a DIFFERENT line, builds
-- its own SocialRewardsGui (the empty black toast = "the black bar") AND steals _G.toggleSocialRewards.
-- Destroy any OTHER SocialRewardsGui + RE-CLAIM the toggle for THIS panel whenever a dup appears.
local function claimSocial()
	for _, g in ipairs(gui:GetChildren()) do
		if g ~= screen and g:IsA("ScreenGui") and g.Name == "SocialRewardsGui" then g:Destroy() end
	end
	_G.toggleSocialRewards = function() setOpen(not panel.Visible) end
end
task.defer(claimSocial)
gui.ChildAdded:Connect(function(c)
	if c ~= screen and c:IsA("ScreenGui") and c.Name == "SocialRewardsGui" then task.defer(claimSocial) end
end)

-- let the manager slam us shut when another menu opens over us (wait for it -- load order isn't guaranteed)
task.spawn(function()
	for _ = 1, 100 do
		if _G.MainMenuManager then _G.MainMenuManager.register(MENU_NAME, function() panel.Visible = false; dim.Visible = false end); return end
		task.wait(0.1)
	end
end)

remote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "state" and type(a) == "table" then
		state = a; redraw()
	elseif kind == "result" then
		local which, ok, msg = a, b, c
		showToast(msg or (ok and "Claimed!" or "Couldn't claim"), ok)
		if ok and rows[which] then state[which] = true; redraw() end
	end
end)

print("[Social] client ready -- Free Rewards panel (opens from More+)")
