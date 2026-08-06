--[[
	Rebirth.client.luau  (StarterPlayerScripts.DinosaurRealmClient.Rebirth)

	The REBIRTH menu. Opened from the MORE+ menu's "Rebirth" row, which :Fire()s the shared "OpenRebirth"
	BindableEvent. Shows your rebirth count + permanent bonus multiplier, and a REBIRTH button that's enabled
	once you've climbed to the SUMMIT. The server (Rebirth.server.luau) is authoritative — this just presents
	the replicated attributes (Rebirths / RebirthMult / HighestSlot) and calls DoRebirth.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local TOP_SLOT = IslandOrder.COUNT

-- open signal (get-or-create; the MORE+ Rebirth row fires it)
local openSignal = ReplicatedStorage:FindFirstChild("OpenRebirth")
if not openSignal then
	openSignal = Instance.new("BindableEvent"); openSignal.Name = "OpenRebirth"; openSignal.Parent = ReplicatedStorage
end

-- remote (server creates it; timeout so slow replication can't hard-block this script)
local rebirthRemotes = ReplicatedStorage:WaitForChild("RebirthRemotes", 30)
local DoRebirth = rebirthRemotes and rebirthRemotes:WaitForChild("DoRebirth", 30)

-- ===== palette =====
local PANEL = Color3.fromRGB(28, 20, 52)
local ACCENT = Color3.fromRGB(170, 90, 240)
local WHITE = Color3.fromRGB(238, 232, 255)
local MUTED = Color3.fromRGB(170, 160, 200)

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "RebirthGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 155; gui.Enabled = false
gui.Parent = PlayerGui

local backdrop = Instance.new("TextButton")
backdrop.Size = UDim2.new(1, 0, 1, 0); backdrop.BackgroundColor3 = Color3.new(0, 0, 0); backdrop.BackgroundTransparency = 0.45
backdrop.AutoButtonColor = false; backdrop.Text = ""; backdrop.Active = true; backdrop.Parent = gui

local panel = Instance.new("Frame")
-- HUB PARITY: 700x520 at (0.5,-16) — the same footprint + screen spot as every other menu (was a small 420x300
-- centred dialog that also rendered UNSCALED on phones, filling a third of the screen).
panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, -16); panel.Size = UDim2.new(0, 700, 0, 520)
panel.BackgroundColor3 = PANEL; panel.BorderSizePixel = 0; panel.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 20); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = ACCENT; s.Thickness = 2; s.Transparency = 0.2; s.Parent = panel
end

-- device scale: ride the SAME getScale() the HUD + other menus use (ResponsiveScale attribute; 1 on desktop).
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel
local function restScale() return player:GetAttribute("ResponsiveScale") or 1 end
panelScale.Scale = restScale()
player:GetAttributeChangedSignal("ResponsiveScale"):Connect(function()
	if gui.Enabled then panelScale.Scale = restScale() end
end)
-- ALSO re-read on every open: the attribute is published once at boot (usually before this script read it),
-- and the changed-signal above only fires while the gui is enabled — so the panel opened UNSCALED on phones.
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then panelScale.Scale = restScale() end
end)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 16, 0, 12); title.Size = UDim2.new(1, -60, 0, 40)
title.Font = Enum.Font.FredokaOne; title.Text = "\u{1F504} REBIRTH"; title.TextColor3 = WHITE; title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = title end

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 12); closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70); closeBtn.Font = Enum.Font.FredokaOne; closeBtn.Text = "X"
closeBtn.TextColor3 = WHITE; closeBtn.TextScaled = true; closeBtn.Parent = panel
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = closeBtn end

local countLbl = Instance.new("TextLabel")
countLbl.BackgroundTransparency = 1; countLbl.Position = UDim2.new(0, 16, 0, 66); countLbl.Size = UDim2.new(1, -32, 0, 34)
countLbl.Font = Enum.Font.GothamBold; countLbl.TextColor3 = WHITE; countLbl.TextScaled = true
countLbl.TextXAlignment = Enum.TextXAlignment.Left; countLbl.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 20; cns.Parent = countLbl end

local multLbl = Instance.new("TextLabel")
multLbl.BackgroundTransparency = 1; multLbl.Position = UDim2.new(0, 16, 0, 104); multLbl.Size = UDim2.new(1, -32, 0, 30)
multLbl.Font = Enum.Font.GothamMedium; multLbl.TextColor3 = Color3.fromRGB(180, 255, 180); multLbl.TextScaled = true
multLbl.TextXAlignment = Enum.TextXAlignment.Left; multLbl.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 16; cns.Parent = multLbl end

local infoLbl = Instance.new("TextLabel")
infoLbl.BackgroundTransparency = 1; infoLbl.Position = UDim2.new(0, 16, 0, 140); infoLbl.Size = UDim2.new(1, -32, 0, 60)
infoLbl.Font = Enum.Font.Gotham; infoLbl.TextColor3 = MUTED; infoLbl.TextWrapped = true; infoLbl.TextScaled = true
infoLbl.TextXAlignment = Enum.TextXAlignment.Left; infoLbl.TextYAlignment = Enum.TextYAlignment.Top; infoLbl.Parent = panel
do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 14; cns.Parent = infoLbl end

local rebirthBtn = Instance.new("TextButton")
rebirthBtn.AnchorPoint = Vector2.new(0.5, 1); rebirthBtn.Position = UDim2.new(0.5, 0, 1, -16); rebirthBtn.Size = UDim2.new(1, -32, 0, 54)
rebirthBtn.BackgroundColor3 = ACCENT; rebirthBtn.Font = Enum.Font.FredokaOne; rebirthBtn.Text = "REBIRTH"; rebirthBtn.TextColor3 = WHITE
rebirthBtn.TextScaled = true; rebirthBtn.Parent = panel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = rebirthBtn
	local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 24; cns.Parent = rebirthBtn
end

local function eligible()
	return math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1) >= TOP_SLOT
end

local function refresh()
	local n = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0)
	local mult = tonumber(player:GetAttribute("RebirthMult")) or 1
	countLbl.Text = "Rebirths: " .. n
	multLbl.Text = ("Bonus multiplier: x%.2f"):format(mult)
	if eligible() then
		infoLbl.Text = "You've reached the summit! Rebirth to reset your island progress for a bigger permanent bonus (+250 coins each)."
		rebirthBtn.BackgroundColor3 = ACCENT
		rebirthBtn.Active = true; rebirthBtn.AutoButtonColor = true
		rebirthBtn.Text = "REBIRTH"
	else
		infoLbl.Text = "Reach the SUMMIT (Volcanic Vista — the top of the climb) to unlock Rebirth."
		rebirthBtn.BackgroundColor3 = Color3.fromRGB(70, 64, 90)
		rebirthBtn.Active = false; rebirthBtn.AutoButtonColor = false
		rebirthBtn.Text = "REACH THE SUMMIT FIRST"
	end
end

local function openMenu()
	refresh()
	gui.Enabled = true
	panelScale.Scale = 0.7 * restScale()
	pcall(function()
		TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = restScale() }):Play()
	end)
end
local function closeMenu() gui.Enabled = false end

closeBtn.Activated:Connect(closeMenu)
-- NO click-outside-to-close: the backdrop covers the whole screen, so a stray tap anywhere
-- shut the menu and it read as closing at random. It still SWALLOWS the click (Active, so
-- nothing behind it reacts) -- it just no longer closes. Explicit actions only: the X button,
-- its own toggle, or MainMenuManager. Matches the MORE+ menu, Season Pass and the Pet Hub.
openSignal.Event:Connect(openMenu)
player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
player:GetAttributeChangedSignal("RebirthMult"):Connect(refresh)
player:GetAttributeChangedSignal("HighestSlot"):Connect(refresh)

local busy = false
rebirthBtn.Activated:Connect(function()
	if busy or not eligible() or not DoRebirth then return end
	busy = true
	local ok, result = pcall(function() return DoRebirth:InvokeServer() end)
	busy = false
	if ok and type(result) == "table" and result.ok then
		refresh()
		closeMenu() -- reset happens server-side (teleported to island1); close so they see it
	end
end)

print("[Rebirth][client] menu ready — opens from the MORE+ Rebirth row via the OpenRebirth signal.")
