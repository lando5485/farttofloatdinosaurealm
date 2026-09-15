--[[
	GroupBannerClient.client.luau  (StarterPlayerScripts.DinosaurRealmClient.GroupBannerClient)

	The "JOIN THE GROUP" popup the first realm shows, ported to the Dino Realm and re-skinned to the jungle
	chrome (olive body, dark-green header, gold headline, the same chunky INK outlines the Rewards hub uses).
	Shown ONCE per session, after 1 MINUTE OF PLAYTIME, and never to someone who is already in the group.

	===== CAN THE BUTTON AUTO-JOIN THE GROUP? NO -- and this is a Roblox rule, not a code gap. =====
	There is no API that joins a player to a group from inside an experience: nothing in Players, GroupService,
	SocialService or MarketplaceService can do it, and Roblox does not expose a "prompt group join" dialog the
	way it does for purchases and friend invites. Joining has to happen on the group page itself. The closest
	thing available is exactly what the first realm does: GuiService:OpenBrowserWindow opens the MLR Studios
	group page INSIDE the game (an in-experience browser panel on PC and phone), where one tap on the group's
	own Join button does it. On console / VR that panel is not available and the call just does nothing, so
	the body text also names the group for anyone who has to search for it.

	THE REWARD is still real: the Rewards hub's COMMUNITY tab (DailyStreak.client -> SocialRewards.server)
	checks membership on the SERVER and pays +5 pet levels once. This popup only points people at the group.
	NOTE: the server caches IsInGroup per session, so someone who joins mid-session claims after a rejoin --
	the body text says so.

	Self-contained by design: it builds its own ScreenGui and requires nothing (the realms nest their shared
	modules differently, so a single require path would break in at least one of them).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local GROUP_ID = 758781978
local GROUP_URL = "https://www.roblox.com/groups/758781978" -- MLR Studios

-- One minute of playtime before the ask. The first realm carries the same value.
local PLAYTIME_SECONDS = 60

-- Any ScreenGui in PlayerGui with one of these names means a cinematic is on screen: the playtime counter
-- pauses and the banner will not open over it.
local CINEMATIC_GUIS = {
	"IntroCinema",            -- Intro.client: the tower intro's full-screen cover
	"IntroTitle",             -- Intro.client: the title card that rides on top of it
	"DinoArrivalCinematic",   -- ArrivalCinematic.client: the rift-arrival reveal
}

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== jungle palette (JungleChrome / the Rewards hub) =====
local OLIVE       = Color3.fromRGB(122, 142, 82)
local OLIVE_DEEP  = Color3.fromRGB(96, 116, 62)
local HEADER      = Color3.fromRGB(26, 48, 30)
local HEADER_EDGE = Color3.fromRGB(74, 94, 68)
local EDGE        = Color3.fromRGB(40, 52, 38)
local CREAM       = Color3.fromRGB(250, 242, 214)
local MUTED       = Color3.fromRGB(226, 232, 206)
local GOLD        = Color3.fromRGB(255, 214, 56)
local LIME        = Color3.fromRGB(126, 217, 87)
local LIME_DEEP   = Color3.fromRGB(58, 150, 56)
local RED         = Color3.fromRGB(214, 64, 60)
local INK         = Color3.fromRGB(8, 20, 12)
local SCRIM       = Color3.fromRGB(6, 16, 10)

-- Phones get the whole popup shrunk so it fits with margin. Same test ResponsiveUI uses: touch and no keyboard.
local isPhone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local REST_SCALE = isPhone and 0.7 or 1
local POP_SCALE = 0.6 * REST_SCALE

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = o; return s end
local function textStroke(l, t) local s = stroke(l, INK, t); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; return s end

local shown = false

local function cinematicUp()
	for _, name in ipairs(CINEMATIC_GUIS) do
		local g = PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			return true
		end
	end
	return false
end

-- Already a member? Then there is nothing to ask. Display-only check (the reward is verified on the server).
local function alreadyMember()
	local ok, inGroup = pcall(function() return player:IsInGroup(GROUP_ID) end)
	return ok and inGroup == true
end

local function showBanner()
	if shown then
		return
	end
	shown = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "GroupBanner"
	gui.ResetOnSpawn = false -- survive respawns; shown once per session
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200 -- above the HUD; it's a modal popup
	gui.Parent = PlayerGui

	-- Scrim. Active so it swallows clicks aimed at the HUD, but NOT a dismiss target: a menu closes on its X.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = SCRIM
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Active = true
	backdrop.ZIndex = 1
	backdrop.Parent = gui
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()

	-- drop shadow, then the panel (panel first is not needed here: MenuBackButton does not target this gui)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 6, 0.5, 8)
	shadow.Size = UDim2.new(0.9, 0, 0, 300)
	shadow.BackgroundColor3 = INK
	shadow.BackgroundTransparency = 0.5
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 2
	shadow.Parent = gui
	corner(shadow, 22)
	do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, 300); sc.Parent = shadow end
	local shadowScale = Instance.new("UIScale"); shadowScale.Scale = POP_SCALE; shadowScale.Parent = shadow

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0.9, 0, 0, 300)
	panel.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient below carries the olive (a gradient MULTIPLIES the base)
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.ZIndex = 3
	panel.Parent = gui
	corner(panel, 22)
	do local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(OLIVE, OLIVE_DEEP); g.Rotation = 90; g.Parent = panel end
	stroke(panel, EDGE, 4)
	do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, 300); sc.Parent = panel end
	local panelScale = Instance.new("UIScale"); panelScale.Scale = POP_SCALE; panelScale.Parent = panel

	-- header band: dark green, the Rewards hub's header colour, squared off at the bottom by a mask
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 62)
	titleBar.BackgroundColor3 = HEADER
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 4
	titleBar.Parent = panel
	corner(titleBar, 22)
	local titleMask = Instance.new("Frame")
	titleMask.AnchorPoint = Vector2.new(0, 1); titleMask.Position = UDim2.new(0, 0, 1, 0); titleMask.Size = UDim2.new(1, 0, 0, 22)
	titleMask.BackgroundColor3 = HEADER; titleMask.BorderSizePixel = 0; titleMask.ZIndex = 4; titleMask.Parent = titleBar
	local titleLine = Instance.new("Frame")
	titleLine.AnchorPoint = Vector2.new(0, 1); titleLine.Position = UDim2.new(0, 0, 1, 0); titleLine.Size = UDim2.new(1, 0, 0, 3)
	titleLine.BackgroundColor3 = HEADER_EDGE; titleLine.BorderSizePixel = 0; titleLine.ZIndex = 5; titleLine.Parent = titleBar

	-- group icon tile + headline
	local tile = Instance.new("Frame")
	tile.AnchorPoint = Vector2.new(0, 0.5); tile.Position = UDim2.new(0, 14, 0.5, 0); tile.Size = UDim2.fromOffset(44, 44)
	tile.BackgroundColor3 = Color3.fromRGB(16, 36, 24); tile.BorderSizePixel = 0; tile.ZIndex = 5; tile.Parent = titleBar
	corner(tile, 12); stroke(tile, HEADER_EDGE, 2)
	local tileIcon = Instance.new("TextLabel")
	tileIcon.BackgroundTransparency = 1; tileIcon.Size = UDim2.new(1, -10, 1, -10); tileIcon.Position = UDim2.fromOffset(5, 5)
	tileIcon.Font = Enum.Font.FredokaOne; tileIcon.Text = "\u{1F465}"; tileIcon.TextScaled = true; tileIcon.ZIndex = 6; tileIcon.Parent = tile

	local headline = Instance.new("TextLabel")
	headline.Name = "Headline"
	headline.BackgroundTransparency = 1
	headline.AnchorPoint = Vector2.new(0, 0.5)
	headline.Position = UDim2.new(0, 70, 0.5, 0)
	headline.Size = UDim2.new(1, -130, 1, -18)
	headline.Font = Enum.Font.FredokaOne
	headline.Text = "JOIN THE GROUP!"
	headline.TextColor3 = GOLD
	headline.TextScaled = true
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.ZIndex = 5
	headline.Parent = titleBar
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 28; cns.Parent = headline end
	textStroke(headline, 2.5)

	-- X: the Rewards hub's close, to the pixel style (red, INK outline, black X)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(46, 42)
	closeBtn.BackgroundColor3 = RED
	closeBtn.AutoButtonColor = true
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.Text = "X"
	closeBtn.TextColor3 = INK
	closeBtn.TextScaled = true
	closeBtn.ZIndex = 6
	closeBtn.Parent = titleBar
	corner(closeBtn, 12); stroke(closeBtn, INK, 3)
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 22; cns.Parent = closeBtn end

	-- body text
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.new(0.5, 0, 0, 76)
	body.Size = UDim2.new(1, -44, 0, 60)
	body.Font = Enum.Font.GothamBold
	body.Text = "Join MLR Studios and claim +5 pet levels in the Rewards hub's Community tab!"
	body.TextColor3 = CREAM
	body.TextWrapped = true
	body.TextSize = 18
	body.ZIndex = 4
	body.Parent = panel
	textStroke(body, 1.5)

	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.BackgroundTransparency = 1
	note.AnchorPoint = Vector2.new(0.5, 0)
	note.Position = UDim2.new(0.5, 0, 0, 142)
	note.Size = UDim2.new(1, -44, 0, 56)
	note.Font = Enum.Font.Gotham
	note.Text = "JOIN GROUP opens the group page right here in the game. Tap Join on it, then rejoin the game to claim your reward."
	note.TextColor3 = MUTED
	note.TextWrapped = true
	note.TextSize = 13
	note.ZIndex = 4
	note.Parent = panel

	-- JOIN GROUP: big lime slab, INK outline, a darker lip underneath so it reads raised (the hub's buttons)
	local joinLip = Instance.new("Frame")
	joinLip.AnchorPoint = Vector2.new(0.5, 1); joinLip.Position = UDim2.new(0.5, 0, 1, -18); joinLip.Size = UDim2.new(1, -44, 0, 54)
	joinLip.BackgroundColor3 = LIME_DEEP; joinLip.BorderSizePixel = 0; joinLip.ZIndex = 4; joinLip.Parent = panel
	corner(joinLip, 14); stroke(joinLip, INK, 3)
	local joinBtn = Instance.new("TextButton")
	joinBtn.Name = "JoinGroup"
	joinBtn.AnchorPoint = Vector2.new(0.5, 1)
	joinBtn.Position = UDim2.new(0.5, 0, 1, -22)
	joinBtn.Size = UDim2.new(1, -44, 0, 54)
	joinBtn.BackgroundColor3 = LIME
	joinBtn.AutoButtonColor = true
	joinBtn.Font = Enum.Font.FredokaOne
	joinBtn.Text = "\u{1F465}  JOIN GROUP"
	joinBtn.TextColor3 = INK
	joinBtn.TextScaled = true
	joinBtn.ZIndex = 5
	joinBtn.Parent = panel
	corner(joinBtn, 14); stroke(joinBtn, INK, 3)
	do local cns = Instance.new("UITextSizeConstraint"); cns.MaxTextSize = 26; cns.Parent = joinBtn end
	do -- gloss strip
		local g = Instance.new("Frame"); g.AnchorPoint = Vector2.new(0.5, 0); g.Position = UDim2.new(0.5, 0, 0, 4); g.Size = UDim2.new(1, -18, 0, 5)
		g.BackgroundColor3 = Color3.new(1, 1, 1); g.BackgroundTransparency = 0.7; g.BorderSizePixel = 0; g.ZIndex = 6; g.Parent = joinBtn; corner(g, 3)
	end

	-- scale-in pop (panel + shadow together)
	pcall(function()
		local ti = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(panelScale, ti, { Scale = REST_SCALE }):Play()
		TweenService:Create(shadowScale, ti, { Scale = REST_SCALE }):Play()
	end)
	if _G.hapticPulse then pcall(_G.hapticPulse, "milestone") end

	print(("[GroupBanner] shown (group %d) after %ds of playtime"):format(GROUP_ID, PLAYTIME_SECONDS))

	-- ===== dismiss (once) =====
	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		print("[GroupBanner] closed/join tapped")
		pcall(function()
			local ti = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(panelScale, ti, { Scale = POP_SCALE }):Play()
			TweenService:Create(shadowScale, ti, { Scale = POP_SCALE }):Play()
			TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		end)
		task.delay(0.3, function()
			if gui then
				gui:Destroy()
			end
		end)
	end

	closeBtn.Activated:Connect(dismiss)

	joinBtn.Activated:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		-- The closest thing to "auto-join" Roblox allows: open the group page in the in-experience browser so
		-- the player taps Join right there. Nothing can join them from inside the game (see the header).
		local opened = pcall(function()
			GuiService:OpenBrowserWindow(GROUP_URL)
		end)
		if not opened then
			warn("[GroupBanner] the in-experience browser is not available on this platform -- search 'MLR Studios' on Roblox to join")
		end
		dismiss()
	end)
end

-- Run once: bank a minute of actual playtime, then open (never over a cinematic, never for a member).
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	local elapsed = 0
	while elapsed < PLAYTIME_SECONDS do
		local dt = task.wait(0.5)
		if not cinematicUp() then
			elapsed += dt
		end
	end

	if alreadyMember() then
		print("[GroupBanner] skipped -- already in the group")
		return
	end

	-- A cinematic could have started on the very tick the minute completed (an event, a realm arrival);
	-- hold until the screen is the player's again.
	while cinematicUp() do
		task.wait(0.25)
	end
	task.wait(0.6) -- a beat of air so it doesn't pop on the same frame as whatever just closed

	showBanner()
end)

-- /group in chat re-shows it on demand (testing, or a player who closed it and wants the link back)
player.Chatted:Connect(function(msg)
	if msg:lower() == "/group" then
		shown = false
		showBanner()
	end
end)
