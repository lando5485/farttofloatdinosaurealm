--======================================================================
-- GiftingClient.client.luau  (LocalScript)  -- DINO PORT of Space Realm's copy (itself from the Food Realm)
--======================================================================
-- The GIFT panel: pick someone, pick an amount, send them Crate Tokens. And -- the half that actually
-- matters -- the moment where you RECEIVE one: a hero banner with the sender's name, a reward cue, and the
-- token count going up while they watch.
--
-- ===== IT OPENS FROM MORE+ =====
-- The Send a Gift card lives in HudSidebarStats' MORE+ dashboard beside Rebirth / Rewards / Wormhole. The
-- card calls _G.openGiftPanel, which OPENS rather than toggles: a card always means "show me this".
--
-- ===== SPACE ADAPTATIONS (vs the Food Realm original) =====
--   * MainMenuManager owns exclusivity + HUD hiding here (register / notifyOpened / notifyClosed), replacing
--     the Food Realm's hand-rolled setHudHidden + _G.hudHold plumbing entirely.
--   * Results and the receive moment go through _G.showHudBanner -- Space's one banner channel -- instead of
--     the Food Realm's NotifyCenter.
--   * The balance check reads _G.crateTokenBalance, which Space's SkinCrateClient publishes from every
--     SkinStateEvent, exactly like the original did at home.
-- Everything else -- rules, tabs, custom amount, the input-scrubbing -- is the original, verbatim.
--
-- ===== NO BACKDROP, X ONLY =====
-- No full-screen tint behind the panel (the design rule both realms now share: only the panel renders), and
-- the X button is the only way to close it -- a stray tap must never slam a panel shut mid-decision.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__GiftingClient then
	warn("[Gifting] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__GiftingClient = true

local MENU_NAME = "GiftPanel"

--======================================================================
-- LOOK  (DINO: the jungle panel greens in place of Space's blues; gold / green / red keep their meaning)
--======================================================================
local BLUE   = Color3.fromRGB(122, 142, 82)   -- jungle olive (panel body)
local BLUE_D = Color3.fromRGB(26, 48, 30)     -- dark jungle green (header / wells)
local GOLD   = Color3.fromRGB(255, 206, 92)
local GOLD_D = Color3.fromRGB(226, 158, 30)
local GREEN  = Color3.fromRGB(72, 190, 96)
local RED    = Color3.fromRGB(210, 70, 70)
local CREAM  = Color3.fromRGB(255, 250, 236)
local LIME   = Color3.fromRGB(126, 224, 110)
local INK    = Color3.fromRGB(20, 24, 14)

-- These MUST match Gifting.server's MIN_GIFT / MAX_GIFT. They are duplicated here rather than fetched
-- because the client only uses them to be POLITE -- to grey out an impossible amount before the player
-- presses send. The server re-checks every one of them and is the only authority.
local MIN_GIFT = 10
local MAX_GIFT = 500
local AMOUNTS  = { 10, 25, 50, 100, 250, 500 }   -- quick picks, all inside MIN_GIFT..MAX_GIFT

local function corner(g, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = g end
local function stroke(g, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = g; return s
end
local function text(parent, str, size, colour)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = colour or CREAM
	t.Text = str
	t.Parent = parent
	local st = Instance.new("UIStroke"); st.Color = INK; st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; st.Parent = t
	return t
end
local function sfx(cue) if _G.Sfx then pcall(_G.Sfx.play, cue) end end
local function banner(msg, colour)
	if _G.showHudBanner then pcall(_G.showHudBanner, msg, colour or GOLD, 3.5) end
end

--======================================================================
-- REMOTES
--======================================================================
local GiftSend     = ReplicatedStorage:WaitForChild("GiftTokensEvent", 30)
local GiftResult   = ReplicatedStorage:WaitForChild("GiftResultEvent", 30)
local GiftReceived = ReplicatedStorage:WaitForChild("GiftReceivedEvent", 30)
if not (GiftSend and GiftResult and GiftReceived) then
	warn("[Gifting] gift remotes never arrived -- panel inactive")
	return
end

--======================================================================
-- PANEL
--======================================================================
local gui, panel, listFrame, statusLbl, customBox
-- Forward-declared: build()'s close button closes through it, and build is written above its definition.
-- Without this the reference inside build compiles as a global read -- the exact load-order bug that once
-- took the whole Food Realm panel down before it ever built.
local setOpen
local tabBtns = {}
local mode = "server"        -- "server" = people here now, "friends" = your friends list
local friendCache = nil      -- filled once per session by loadFriends()
local friendsLoading = false
local chosenUser, chosenName, chosenAmount = nil, nil, AMOUNTS[2]
local amountBtns = {}

local function setStatus(msg, colour)
	if statusLbl then statusLbl.Text = msg or ""; statusLbl.TextColor3 = colour or CREAM end
end

local function refreshAmountButtons()
	local matchedPreset = false
	for amt, btn in pairs(amountBtns) do
		local on = (amt == chosenAmount)
		if on then matchedPreset = true end
		btn.BackgroundColor3 = on and GOLD or BLUE_D
		local lbl = btn:FindFirstChildWhichIsA("TextLabel")
		if lbl then lbl.TextColor3 = on and INK or CREAM end
	end
	-- The custom box lights up only when the chosen amount is NOT one of the presets, so exactly one control
	-- ever looks selected and the player can always tell where the number they are about to send came from.
	if customBox then
		local custom = (not matchedPreset) and customBox.Text ~= ""
		customBox.BackgroundColor3 = custom and GOLD or BLUE_D
		customBox.TextColor3 = custom and INK or CREAM
	end
end

--======================================================================
-- FRIENDS
--======================================================================
-- GetFriendsAsync works for OFFLINE friends, which is the entire point -- the server-only list can never
-- show the person a kid actually wants to send something to, because that person is usually not here.
--
-- It is a paged web call, so it is fetched ONCE per session and cached: re-requesting it every time the
-- panel opens would be both slow and a good way to get rate-limited.
local function loadFriends(onDone)
	if friendCache then onDone(friendCache); return end
	if friendsLoading then return end
	friendsLoading = true
	task.spawn(function()
		local out = {}
		local ok, err = pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			for _ = 1, 10 do   -- 10 pages is far more friends than any panel needs to list
				for _, f in ipairs(pages:GetCurrentPage()) do
					out[#out + 1] = {
						id   = f.Id,
						name = f.DisplayName or f.Username,
						user = f.Username,
					}
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
		end)
		friendsLoading = false
		if not ok then
			warn("[Gifting] could not load friends: " .. tostring(err))
			friendCache = {}
		else
			table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
			friendCache = out
		end
		onDone(friendCache)
	end)
end

local function refreshTabs()
	for id, btn in pairs(tabBtns) do
		local on = (id == mode)
		btn.BackgroundColor3 = on and GOLD or BLUE_D
		local lbl = btn:FindFirstChildWhichIsA("TextLabel")
		if lbl then lbl.TextColor3 = on and INK or CREAM end
	end
end

local function rebuildPlayerList()
	if not listFrame then return end
	-- CLEAR EVERYTHING WE DREW, NOT JUST THE ROWS. GuiObject is the right net: it catches the rows AND the
	-- "nobody here" note (a TextLabel), while UICorner/UIListLayout are UIComponents and survive. Destroying
	-- only TextButtons is the bug that once stacked two copies of the empty-list note at home.
	for _, c in ipairs(listFrame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	-- Both tabs render the same row shape, so the list is built from a plain {id, name, here} array and the
	-- only difference between the two modes is where that array came from.
	local others = {}
	if mode == "server" then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				others[#others + 1] = { id = p.UserId, name = p.DisplayName or p.Name, here = true }
			end
		end
	else
		for _, f in ipairs(friendCache or {}) do
			-- A friend who IS in this server is shown as online, so the row reads honestly either way and a
			-- kid is never told a gift will "arrive later" when it is about to arrive instantly.
			others[#others + 1] = {
				id = f.id, name = f.name,
				here = Players:GetPlayerByUserId(f.id) ~= nil,
			}
		end
	end

	if #others == 0 then
		-- An empty list with no explanation reads as a broken panel. Say why it is empty.
		if not listFrame:FindFirstChild("EmptyNote") then
			local msg
			if mode == "friends" then
				msg = friendCache and "No friends found -- add some on Roblox first!" or "Loading your friends..."
			else
				msg = "Nobody else is in this server right now!"
			end
			local none = text(listFrame, msg, 18, CREAM)
			none.Name = "EmptyNote"
			none.Size = UDim2.new(1, -12, 0, 40)
			none.Position = UDim2.new(0, 6, 0, 8)
		end
		listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	for i, p in ipairs(others) do
		local picked = (chosenUser == p.id)
		local row = Instance.new("TextButton")
		row.Name = "P_" .. p.id
		row.Size = UDim2.new(1, -12, 0, 46)
		row.Position = UDim2.new(0, 6, 0, (i - 1) * 52)
		row.BackgroundColor3 = picked and GOLD or BLUE_D
		row.AutoButtonColor = false
		row.Text = ""
		row.Parent = listFrame
		corner(row, 12); stroke(row, picked and GOLD_D or BLUE, 2)

		local nameLbl = text(row, p.name, 20, picked and INK or CREAM)
		nameLbl.Size = UDim2.new(1, -120, 1, 0)
		nameLbl.Position = UDim2.new(0, 14, 0, 0)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left

		-- Say plainly whether this lands now or later. "Offline" on its own reads like a refusal; the point
		-- is that sending still works, so the row says WHEN it arrives instead of whether it can.
		local badge = text(row, p.here and "HERE NOW" or "GETS IT LATER", 13,
			picked and INK or (p.here and LIME or Color3.fromRGB(180, 210, 245)))
		badge.Size = UDim2.new(0, 110, 1, 0)
		badge.Position = UDim2.new(1, -118, 0, 0)
		badge.TextXAlignment = Enum.TextXAlignment.Right

		row.MouseButton1Click:Connect(function()
			chosenUser, chosenName = p.id, p.name
			sfx("click")
			setStatus(p.here and ("Gifting to " .. p.name)
				or ("Gifting to " .. p.name .. " -- they'll get it next time they play"), CREAM)
			rebuildPlayerList()
		end)
	end
	listFrame.CanvasSize = UDim2.new(0, 0, 0, #others * 52 + 8)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GiftGui"; gui:SetAttribute("NoTextSweep", true) -- DINO: opt out of repositionGUIs' TextScaled sweep
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Enabled = false
	gui.Parent = PlayerGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Hub-parity screen spot: this gui RESPECTS the topbar inset, so that is -45 (the IgnoreGuiInset menus use
	-- -16 for the same place on screen). Dead-centre left it sitting low against its siblings.
	panel.Position = UDim2.new(0.5, 0, 0.5, -45)
	panel.Size = UDim2.fromOffset(700, 520)   -- the house panel size, same as the other Space menus
	panel.BackgroundColor3 = BLUE
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 22); stroke(panel, CREAM, 4)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 66)
	header.BackgroundColor3 = BLUE_D
	header.BorderSizePixel = 0
	header.Parent = panel
	corner(header, 22)

	local title = text(header, "\xF0\x9F\x8E\x81  SEND A GIFT", 30, GOLD)
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- X ONLY, and the "X" is the button's OWN Text (not a child label) so anything that finds close buttons
	-- by reading TextButton.Text still finds this one.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(44, 44)
	close.Position = UDim2.new(1, -54, 0, 11)
	close.BackgroundColor3 = RED
	close.AutoButtonColor = false
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 24
	close.TextColor3 = CREAM
	close.Text = "X"
	close.Parent = header
	corner(close, 12); stroke(close, Color3.fromRGB(150, 40, 40), 2)
	local xStroke = Instance.new("UIStroke")
	xStroke.Color = INK; xStroke.Thickness = 2
	xStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	xStroke.Parent = close
	-- BACK, left of the X -- realm 1's header pattern via the shared kit (BackButtonKit.client.luau).
	-- Deferred: the kit is a sibling LocalScript and load order between them is not guaranteed.
	task.defer(function()
		for _ = 1, 40 do
			if _G.addBackButton then _G.addBackButton(close); return end
			task.wait(0.1)
		end
	end)


	local hint = text(panel, "Pick someone, pick an amount, send them Crate Tokens.", 16, CREAM)
	hint.Size = UDim2.new(1, -40, 0, 22)
	hint.Position = UDim2.new(0, 20, 0, 72)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	-- TWO TABS. The server list can only ever show who happens to be here; the friends list is how a kid
	-- reaches the person they actually meant, whether or not that person is online.
	local TABS = { { id = "server", label = "IN THIS SERVER" }, { id = "friends", label = "MY FRIENDS" } }
	for i, t in ipairs(TABS) do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. t.id
		b.Size = UDim2.fromOffset(180, 34)
		b.Position = UDim2.new(0, 20 + (i - 1) * 190, 0, 98)
		b.BackgroundColor3 = BLUE_D
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = panel
		corner(b, 10); stroke(b, BLUE, 2)
		local l = text(b, t.label, 15, CREAM); l.Size = UDim2.fromScale(1, 1)
		tabBtns[t.id] = b
		b.MouseButton1Click:Connect(function()
			if mode == t.id then return end
			mode = t.id
			chosenUser, chosenName = nil, nil
			sfx("click"); refreshTabs()
			if mode == "friends" then
				rebuildPlayerList()                      -- shows "Loading your friends..." straight away
				loadFriends(function() if gui.Enabled then rebuildPlayerList() end end)
			else
				rebuildPlayerList()
			end
		end)
	end
	refreshTabs()

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "PlayerList"
	listFrame.Size = UDim2.new(1, -40, 0, 188)
	listFrame.Position = UDim2.new(0, 20, 0, 138)
	listFrame.BackgroundColor3 = Color3.fromRGB(22, 108, 205)
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.Parent = panel
	corner(listFrame, 14)

	local amtTitle = text(panel, "HOW MANY?", 20, GOLD)
	amtTitle.Size = UDim2.new(1, -40, 0, 24)
	amtTitle.Position = UDim2.new(0, 20, 0, 330)
	amtTitle.TextXAlignment = Enum.TextXAlignment.Left

	-- QUICK PICKS. Six buttons at 100 wide with an 8px gap span exactly 20..680 inside a 700 panel.
	for i, amt in ipairs(AMOUNTS) do
		local b = Instance.new("TextButton")
		b.Name = "Amt_" .. amt
		b.Size = UDim2.fromOffset(100, 44)
		b.Position = UDim2.new(0, 20 + (i - 1) * 108, 0, 356)
		b.BackgroundColor3 = BLUE_D
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = panel
		corner(b, 12); stroke(b, BLUE, 2)
		local l = text(b, tostring(amt), 22, CREAM); l.Size = UDim2.fromScale(1, 1)
		amountBtns[amt] = b
		b.MouseButton1Click:Connect(function()
			chosenAmount = amt
			if customBox then customBox.Text = "" end   -- a preset wins: clear the typed one
			sfx("click"); refreshAmountButtons()
		end)
	end

	-- CUSTOM AMOUNT. The quick picks cover the common cases; this is for the kid who wants to send exactly
	-- 137 because that is how many they have.
	local orLbl = text(panel, "OR TYPE ONE:", 15, CREAM)
	orLbl.Size = UDim2.fromOffset(112, 36)
	orLbl.Position = UDim2.new(0, 20, 0, 406)
	orLbl.TextXAlignment = Enum.TextXAlignment.Left

	customBox = Instance.new("TextBox")
	customBox.Name = "CustomAmount"
	customBox.Size = UDim2.fromOffset(150, 36)
	customBox.Position = UDim2.new(0, 136, 0, 406)
	customBox.BackgroundColor3 = BLUE_D
	customBox.Font = Enum.Font.FredokaOne
	customBox.TextSize = 20
	customBox.TextColor3 = CREAM
	customBox.PlaceholderText = MIN_GIFT .. "-" .. MAX_GIFT
	customBox.PlaceholderColor3 = Color3.fromRGB(150, 185, 230)
	customBox.Text = ""
	customBox.ClearTextOnFocus = false   -- kids edit a number, they do not retype it from scratch
	customBox.Parent = panel
	corner(customBox, 10); stroke(customBox, BLUE, 2)

	local rangeLbl = text(panel, ("%d-%d tokens"):format(MIN_GIFT, MAX_GIFT), 14, Color3.fromRGB(170, 205, 245))
	rangeLbl.Size = UDim2.fromOffset(180, 36)
	rangeLbl.Position = UDim2.new(0, 296, 0, 406)
	rangeLbl.TextXAlignment = Enum.TextXAlignment.Left

	-- DIGITS ONLY, AS THEY TYPE. A TextBox will happily accept "-50" or "1e9" or a paragraph; stripping
	-- non-digits at the keystroke means the box can only ever hold a number, and the 4-character cap keeps it
	-- near the range without an alarming red error for typing a fifth digit.
	local guard = false
	customBox:GetPropertyChangedSignal("Text"):Connect(function()
		if guard then return end
		local clean = customBox.Text:gsub("%D", ""):sub(1, 4)
		if clean ~= customBox.Text then
			guard = true; customBox.Text = clean; guard = false
		end
	end)

	-- COMMIT ON FOCUS LOST. Clamping live would fight the typist: type "5" on the way to "50" and it would
	-- snap to 10 under their finger. So the box holds whatever they type and is clamped once they are done.
	customBox.FocusLost:Connect(function()
		local n = tonumber(customBox.Text)
		if not n or n <= 0 then
			customBox.Text = ""                       -- empty / rubbish: fall back to the selected preset
			refreshAmountButtons()
			return
		end
		local clamped = math.clamp(math.floor(n), MIN_GIFT, MAX_GIFT)
		chosenAmount = clamped
		-- Write the clamped value back so what they SEE is what will send. Silently sending a different
		-- number than the one on screen is the single most confusing thing a form can do.
		guard = true; customBox.Text = tostring(clamped); guard = false
		if clamped ~= math.floor(n) then
			setStatus(("Gifts are %d-%d tokens, so that became %d."):format(MIN_GIFT, MAX_GIFT, clamped), GOLD)
			sfx("deny")
		else
			sfx("click")
		end
		refreshAmountButtons()
	end)

	refreshAmountButtons()

	local send = Instance.new("TextButton")
	send.Name = "Send"
	send.Size = UDim2.new(1, -40, 0, 50)
	send.Position = UDim2.new(0, 20, 0, 450)
	send.BackgroundColor3 = GREEN
	send.AutoButtonColor = false
	send.Text = ""
	send.Parent = panel
	corner(send, 14); stroke(send, Color3.fromRGB(40, 130, 60), 3)
	local sendLbl = text(send, "SEND GIFT", 26, CREAM); sendLbl.Size = UDim2.fromScale(1, 1)

	statusLbl = text(panel, "", 16, CREAM)
	statusLbl.Size = UDim2.new(1, -40, 0, 20)
	statusLbl.Position = UDim2.new(0, 20, 0, 500)

	send.MouseButton1Click:Connect(function()
		if not chosenUser then sfx("deny"); setStatus("Pick someone first!", GOLD); return end
		-- ===== ONLY REFUSE WHEN WE POSITIVELY KNOW IT IS TOO LOW =====
		-- _G.crateTokenBalance is only populated once SkinCrateClient receives its first SkinStateEvent, so a
		-- nil balance falls through and lets the server decide -- the safe direction to be wrong in. Treating
		-- "unknown" as "zero" is the bug that once refused every early send at home.
		local bal = tonumber(_G.crateTokenBalance)
		if bal and bal < chosenAmount then
			sfx("deny")
			setStatus(("You only have %d tokens."):format(bal), GOLD)
			return
		end
		sfx("confirm")
		setStatus("Sending...", CREAM)
		GiftSend:FireServer(chosenUser, chosenAmount)
	end)

	close.MouseButton1Click:Connect(function()
		sfx("click")
		setOpen(false)
	end)

	Players.PlayerAdded:Connect(function() if gui.Enabled then rebuildPlayerList() end end)
	Players.PlayerRemoving:Connect(function(p)
		if chosenUser == p.UserId then chosenUser, chosenName = nil, nil end
		if gui.Enabled then task.defer(rebuildPlayerList) end
	end)
end

--======================================================================
-- OPEN / CLOSE  (MainMenuManager owns exclusivity + HUD hiding)
--======================================================================
-- setOpen is a declared-before-build local because build()'s close button closes through it.
function setOpen(open)
	if not gui then return end
	if open == gui.Enabled then return end
	if open then
		chosenUser, chosenName = nil, nil
		mode = "server"
		refreshTabs()
		chosenAmount = AMOUNTS[2]
		if customBox then customBox.Text = "" end
		setStatus("", CREAM)
		refreshAmountButtons()
		rebuildPlayerList()
		sfx("whoosh")
		gui.Enabled = true
		if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, MENU_NAME) end
	else
		gui.Enabled = false
		sfx("click")
		if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyClosed, MENU_NAME) end
	end
end

_G.toggleGiftPanel = function() setOpen(not (gui and gui.Enabled)) end
-- OPEN, never close. This is what the MORE+ card calls -- a card in that menu always means "show me this",
-- and a toggle would read as a dead button whenever the panel happened to be enabled already.
_G.openGiftPanel = function() setOpen(true) end

--======================================================================
-- RESULTS
--======================================================================
GiftResult.OnClientEvent:Connect(function(ok, msg)
	if ok then
		sfx("purchase")
		-- NO BANNER FOR THE SENDER. The gift panel is open and they are looking straight at it, so the green
		-- status line under the SEND button already says it worked -- a banner at the top of the screen
		-- repeated it somewhere they were not looking, over the panel they were still using. The RECEIVER
		-- still gets one (below): that half arrives unannounced and has no panel to read.
		setStatus(msg or "Sent!", Color3.fromRGB(150, 255, 170))
	else
		sfx("deny")
		setStatus(msg or "Couldn't send that.", GOLD)
	end
end)

-- THE MOMENT THAT MATTERS. Getting a present is the reason this feature exists, so it lands as a hero banner
-- with the sender's name on it -- not as a status line in a panel the recipient does not have open.
GiftReceived.OnClientEvent:Connect(function(fromName, amount, wasOffline)
	sfx("reward")
	banner(wasOffline
		and ("\xF0\x9F\x8E\x81  %s LEFT YOU %s TOKENS WHILE YOU WERE AWAY!"):format(
			string.upper(tostring(fromName)), tostring(amount))
		or  ("\xF0\x9F\x8E\x81  %s GAVE YOU %s TOKENS!"):format(
			string.upper(tostring(fromName)), tostring(amount)), GOLD)
	print(("[Gifting] received %s tokens from %s"):format(tostring(amount), tostring(fromName)))
end)

--======================================================================
build()

-- Register with the manager AFTER build so the hider always has a real gui to hide. The hider must NOT call
-- notifyClosed -- the manager is mid-switch to another menu when it runs, and notifyClosed would clear that
-- menu's claim to the HUD.
task.spawn(function()
	for _ = 1, 50 do
		if _G.MainMenuManager and _G.MainMenuManager.register then
			pcall(_G.MainMenuManager.register, MENU_NAME, function() if gui then gui.Enabled = false end end)
			return
		end
		task.wait(0.2)
	end
	warn("[Gifting] MainMenuManager never appeared -- the panel still works, but won't auto-close other menus")
end)

print("[Gifting] ready -- opens from the MORE+ menu (Send a Gift)")
