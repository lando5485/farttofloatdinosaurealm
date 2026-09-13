--!nonstrict
--======================================================================
-- TradeRequests.client.luau  (LocalScript, StarterPlayerScripts)
--======================================================================
-- OFFLINE TRADE REQUESTS, as a tab inside the trade window that already exists.
--
-- The pet hub's Trade overlay lists players IN THIS SERVER. That is the right list and it stays the default
-- -- somebody standing next to you is always the better trade. This adds the other half: the people who are
-- not here, who you can leave a note for, and who you can name a pet or a skin at so the note is worth
-- coming back for.
--
-- ===== WHY IT ATTACHES FROM OUTSIDE =====
-- The overlay is built in PetFollow.client.lua, which is seven thousand lines sitting ON Luau's limit of 200
-- locals per scope -- one more file-scope local there and the whole script fails to compile, taking pets,
-- quests and the hub down with it. So nothing is added to that file. This one waits for the overlay to
-- exist, hangs a tab off it, and puts its own view underneath.
--
-- It is also why the two view frames are found BY CLASS rather than by name: PetFollow never names them
-- (both are plain "Frame"), and inventing names would mean editing the file this is avoiding.
--======================================================================

if _G.__TradeRequestsClient then return end
_G.__TradeRequestsClient = true

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ReqSend    = ReplicatedStorage:WaitForChild("TradeReqSendEvent", 30)
local ReqInbox   = ReplicatedStorage:WaitForChild("TradeReqInboxEvent", 30)
local ReqResult  = ReplicatedStorage:WaitForChild("TradeReqResultEvent", 30)
local ReqFriends = ReplicatedStorage:WaitForChild("TradeReqFriendsFunc", 30)
if not (ReqSend and ReqInbox and ReqResult and ReqFriends) then
	warn("[TradeReq] remotes never appeared -- offline trade requests are inactive")
	return
end
-- Waited for separately and allowed to be missing: if an older server build is running, the tab still sends
-- plain requests instead of failing to load. A degraded feature beats a dead one.
local ReqMine   = ReplicatedStorage:WaitForChild("TradeReqMineFunc", 10)
local ReqLookup = ReplicatedStorage:WaitForChild("TradeReqLookupFunc", 10)

local GOLD  = Color3.fromRGB(255, 215,   0)
local LIME  = Color3.fromRGB( 50, 200,  60)
local BLUE  = Color3.fromRGB( 40, 110, 210)
local CARD  = Color3.fromRGB( 12,  44, 104)
local DEEP  = Color3.fromRGB(  8,  30,  74)
local GREY  = Color3.fromRGB(110, 120, 140)
local RED   = Color3.fromRGB(225,  55,  55)
local INK   = Color3.fromRGB( 16,  32,  62)
local WHITE = Color3.fromRGB(255, 255, 255)

local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end

local function stroke(i, colour, thick)
	local s = Instance.new("UIStroke")
	s.Color = colour; s.Thickness = thick or 2; s.Parent = i
	return s
end

local function toast(msg, colour)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(_G.NotifyCenter.push, { text = msg, color = colour or GOLD, duration = 4 })
	elseif _G.showHudBanner then
		pcall(_G.showHudBanner, msg, colour or GOLD, 4)
	end
end

local inbox = {}   -- pending requests, newest first

--======================================================================
-- ATTACH TO THE OVERLAY
--======================================================================
local overlay = nil
local content, tabBtn, tabStroke, tabBadge, tabBadgeText
local open = false
local hiddenViews = {}
local rebuild                     -- forward declarations; both defined below, both used by setOpen
local closePicker
local picker

-- ===== MAKE IT LOOK PRESSED-ABLE =====
-- The first version of this was a flat blue rectangle in a header full of flat blue rectangles, and it read
-- as a label rather than a control -- players did not know there was a second half of the window. It is now
-- gold on navy (nothing else in this header is gold), carries a chevron pointing at where it goes, and wears
-- a count badge when somebody is waiting. The badge is the part that actually gets it tapped.
local function refreshTab()
	local n = #inbox
	if not tabBtn then return end
	if open then
		tabBtn.Text = "\xE2\x97\x80  IN SERVER"
		tabBtn.BackgroundColor3 = GREY
		tabBtn.TextColor3 = WHITE
		tabStroke.Color = Color3.fromRGB(200, 210, 230)
	else
		tabBtn.Text = "\xF0\x9F\x91\xA5 FRIENDS  \xE2\x96\xB6"
		tabBtn.BackgroundColor3 = GOLD
		tabBtn.TextColor3 = INK          -- dark on gold; the contrast is what stops it reading as decoration
		tabStroke.Color = WHITE
	end
	tabBadge.Visible = (n > 0) and not open
	tabBadgeText.Text = (n > 9) and "9+" or tostring(n)
end

-- Pulses only while somebody is actually waiting, and only while the tab is closed. A control that animates
-- forever is wallpaper -- players stop seeing it within a minute. This one moves when there is news and is
-- completely still the rest of the time, so the movement keeps meaning something.
local function pulseTab()
	task.spawn(function()
		while tabBtn and tabBtn.Parent do
			if #inbox > 0 and not open then
				TweenService:Create(tabStroke, TweenInfo.new(0.55), { Thickness = 4 }):Play()
				task.wait(0.6)
				TweenService:Create(tabStroke, TweenInfo.new(0.55), { Thickness = 2 }):Play()
				task.wait(0.9)
			else
				tabStroke.Thickness = 2
				task.wait(0.5)
			end
		end
	end)
end

local function setOpen(on)
	if not overlay then return end
	open = on
	content.Visible = on
	if on then
		-- Full geometry dump, not a marker. "OPEN" alone proved the state flips while the screen showed
		-- nothing, which is exactly the case where the next question is WHERE the page actually is.
		task.defer(function()
			local kids = 0
			if list then for _, c in ipairs(list:GetChildren()) do if not c:IsA("UIListLayout") then kids = kids + 1 end end end
			print(("[TradeReq] FRIENDS open: overlay.Visible=%s size=%s | content.Visible=%s size=%s pos=%s | rows=%d | searchBox=%s")
				:format(tostring(overlay.Visible), tostring(overlay.AbsoluteSize),
					tostring(content.Visible), tostring(content.AbsoluteSize), tostring(content.AbsolutePosition),
					kids, tostring(searchBox and searchBox.Visible)))
		end)
		-- Hide the overlay's own views and remember exactly which ones WERE showing, so closing puts the
		-- window back into the state it was in rather than into a guess about the state it should be in.
		hiddenViews = {}
		for _, c in ipairs(overlay:GetChildren()) do
			-- Frames only: the TextLabel title and the TextButton back/tab are the header and must stay.
			-- The picker is skipped as well -- it is a sibling now rather than a child of the view, and
			-- sweeping it into hiddenViews would have it pop back open the next time the tab is closed.
			if c:IsA("Frame") and c ~= content and c ~= picker and c.Visible then
				hiddenViews[#hiddenViews + 1] = c
				c.Visible = false
			end
		end
	else
		if closePicker then closePicker() end
		for _, c in ipairs(hiddenViews) do
			if c.Parent then c.Visible = true end
		end
		hiddenViews = {}
	end
	refreshTab()
end

-- For the overlay's OWNER. Space's trade page re-shows its picker/window views when its TRADE tab is pressed,
-- and it cannot know this tab hid them -- two scripts each restoring "their" views is how both end up visible
-- at once and the top ZIndex wins. The owner calls this first, so there is only ever one set of views showing.
_G.tradeReqCloseTab = function()
	if open then setOpen(false) end
end

--======================================================================
-- CONTENT
--======================================================================
local list, searchBox
local searchResult = nil     -- { id, name, here } from the last successful lookup
local searchNote   = nil     -- a message to show instead, e.g. "no player called that"

-- ===== NOT EVERY REALM CAN TRADE =====
-- The live trade window belongs to the pet hub, and the pet hub does not exist in every place. Where it is
-- missing this whole feature still has a job -- requests are stored per UNIVERSE, so one sent from a realm
-- that cannot trade is waiting in a realm that can -- but "TRADE NOW" must not be offered, because a button
-- that hands off to a window nobody built is a dead end dressed up as the main path.
local function canTradeLive()
	return ReplicatedStorage:FindFirstChild("PetTradeRequestEvent") ~= nil
end

local function startLiveTrade(userId)
	-- Hand straight to the EXISTING trade window. Nothing here ever moves an item; it only gets two people
	-- to the door of the flow that already does it safely.
	local ev = ReplicatedStorage:FindFirstChild("PetTradeRequestEvent")
	if not ev then
		toast("Trading happens in the Food and Candy realms \xE2\x80\x94 send them an offer instead!", GOLD)
		return
	end
	pcall(function() ev:FireServer(userId) end)
	setOpen(false)
end

--======================================================================
-- OFFER PICKER
--======================================================================
-- ===== AN OFFER IS A SENTENCE, NOT A TRANSACTION =====
-- Picking a pet here does NOT reserve it, remove it, or promise it. It writes its NAME into the note, and
-- that is the whole feature: "Sam wants to trade" is ignorable, "Sam will give you their Gold Void Dragon"
-- is a reason to log in. Everything about actually swapping the items still happens later, in the live trade
-- window, with both players present -- see the server file's header for why that line is not negotiable.
--
-- The list is fetched from the server rather than read from any client-side inventory copy, so it cannot
-- offer something the trade window would then refuse.
local offerCache = nil

-- Cleared every time the tab is opened rather than cached for the session: a player who hatches a pet, comes
-- back and does not see it in their own offer list concludes the feature is broken, and one extra remote call
-- per tab open is a trivial price for the list always being true.
local function clearOfferCache() offerCache = nil end

local function fetchOfferables()
	if offerCache then return offerCache end
	if not ReqMine then return { pets = {}, skins = {} } end
	local ok, data = pcall(function() return ReqMine:InvokeServer() end)
	if ok and type(data) == "table" then
		offerCache = { pets = data.pets or {}, skins = data.skins or {} }
	else
		offerCache = { pets = {}, skins = {} }
	end
	return offerCache
end

-- ===== SEVERAL THINGS, NOT ONE =====
-- Pets and skins go in the same basket and any mix of them can be picked, because that is the shape real
-- trades take -- "my two commons and a skin for your rare" is the normal opening move, and an offer that can
-- only name one item pushes the actual pitch somewhere this system cannot carry it.
--
-- Capped at the same number the server enforces. The cap is not about payload size; it is that a note reading
-- "offering 23 things" says nothing at all, and the recipient has to log in to find out what the deal even is.
local MAX_OFFER_ITEMS = 6

local function send(targetId, offers, btn)
	ReqSend:FireServer(targetId, offers)
	if btn then
		btn.Text = "SENT \xE2\x9C\x93"
		btn.BackgroundColor3 = GREY
	end
end

-- The footer button outlives any one visit to the picker, so its handler must not. Left connected, a picker
-- that was opened and closed without sending would still have a live handler pointed at the OLD player, and
-- the next send would go to both of them.
local sendConn = nil
local function dropSendHandler()
	if sendConn then sendConn:Disconnect(); sendConn = nil end
end

closePicker = function()
	dropSendHandler()
	if picker then picker.Visible = false end
end

local function openPicker(targetId, targetName, btn)
	if not picker then send(targetId, nil, btn); return end
	dropSendHandler()

	for _, c in ipairs(picker.Body:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	picker.Title.Text = tostring(targetName)
	picker.Visible = true

	-- Insertion-ordered, so the footer count and the offer itself follow the order they were tapped in rather
	-- than a hash order that reshuffles every time something is ticked.
	local chosen = {}
	local function indexOf(kind, key)
		for i, c in ipairs(chosen) do
			if c.kind == kind and c.key == key then return i end
		end
		return nil
	end

	local n = 0
	local function ord() n = n + 1; return n end

	local rows = {}          -- every toggle, so all of them can be re-styled when the cap is hit
	local refreshRows

	local function option(label, kind, key)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -8, 0, 34); b.BackgroundColor3 = CARD; b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.TextColor3 = WHITE
		b.TextXAlignment = Enum.TextXAlignment.Left; b.AutoButtonColor = false
		-- Explicit, not inherited: this ScreenGui's ZIndexBehavior belongs to PetFollow, and under Global a
		-- child does not ride on its parent's layer -- these rows would draw under the panel they sit in.
		b.ZIndex = 52
		b.LayoutOrder = ord(); b.Parent = picker.Body
		corner(b, 7)
		local st = stroke(b, CARD, 2)

		rows[#rows + 1] = {
			btn = b, stroke = st, kind = kind, key = key, label = label,
		}

		b.MouseButton1Click:Connect(function()
			local at = indexOf(kind, key)
			if at then
				table.remove(chosen, at)
			elseif #chosen < MAX_OFFER_ITEMS then
				chosen[#chosen + 1] = { kind = kind, key = key }
			else
				-- Refused rather than silently swapping something out. Dropping the player's earliest pick to
				-- make room for a new one loses a choice they made on purpose and never told them about.
				return
			end
			refreshRows()
		end)
	end

	refreshRows = function()
		local atCap = #chosen >= MAX_OFFER_ITEMS
		for _, r in ipairs(rows) do
			local picked = indexOf(r.kind, r.key) ~= nil
			-- The tick is part of the TEXT, not a separate frame: these rows are built by the dozen and a
			-- checkbox instance each is a lot of GUI for a mark that a character renders perfectly.
			r.btn.Text = (picked and "  \xE2\x9C\x94  " or "  \xE2\x98\x90  ") .. r.label
			r.btn.BackgroundColor3 = picked and Color3.fromRGB(20, 74, 150) or CARD
			r.stroke.Color = picked and GOLD or CARD
			-- Rows you cannot currently pick go dim, so the cap explains itself before it has to be explained.
			r.btn.TextTransparency = (atCap and not picked) and 0.45 or 0
		end
		picker.Footer.Send.Text = (#chosen == 0)
			and "\xF0\x9F\x91\x8B JUST ASK THEM TO TRADE"
			or ("SEND OFFER (" .. #chosen .. ")")
		picker.Footer.Send.BackgroundColor3 = (#chosen == 0) and BLUE or LIME
		picker.Footer.Hint.Text = (#chosen == 0)
			and "Tick any pets or skins you'd swap \xE2\x80\x94 or just ask."
			or ("Picked " .. #chosen .. "/" .. MAX_OFFER_ITEMS ..
				". Nothing is given away until you both trade for real.")
	end

	local function head(text)
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(1, -8, 0, 22); h.BackgroundTransparency = 1; h.LayoutOrder = ord()
		h.Font = Enum.Font.GothamBold; h.TextSize = 12; h.TextColor3 = GOLD
		h.TextXAlignment = Enum.TextXAlignment.Left; h.ZIndex = 52
		h.Text = text; h.Parent = picker.Body
	end

	local mine = fetchOfferables()
	if #mine.pets == 0 and #mine.skins == 0 then
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -8, 0, 30); l.BackgroundTransparency = 1; l.LayoutOrder = ord()
		l.Font = Enum.Font.Gotham; l.TextSize = 12; l.TextColor3 = Color3.fromRGB(195, 215, 245)
		l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true; l.ZIndex = 52
		l.Text = "   Nothing to offer yet \xE2\x80\x94 hatch a pet or open a crate first. You can still ask!"
		l.Parent = picker.Body
	end

	if #mine.pets > 0 then
		head("   YOUR PETS")
		for _, p in ipairs(mine.pets) do
			option("\xF0\x9F\x90\xBE " .. p.label, "pet", p.key)
		end
	end
	if #mine.skins > 0 then
		head("   YOUR SKINS")
		for _, s in ipairs(mine.skins) do
			option("\xE2\x9C\xA8 " .. s.label, "skin", s.key)
		end
	end

	-- Rewired on every open: the footer button is permanent but the basket it sends is not.
	sendConn = picker.Footer.Send.Activated:Connect(function()
		local payload = (#chosen > 0) and chosen or nil
		closePicker()
		send(targetId, payload, btn)
	end)

	refreshRows()
	picker.Body.CanvasPosition = Vector2.new(0, 0)
end

--======================================================================
-- LIST
--======================================================================
local function note(text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 34); l.BackgroundTransparency = 1; l.LayoutOrder = order; l.ZIndex = 8
	l.Font = Enum.Font.Gotham; l.TextSize = 13; l.TextColor3 = Color3.fromRGB(195, 215, 245)
	l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true; l.Text = text; l.Parent = list
end

local function heading(text, order)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, -8, 0, 24); h.BackgroundTransparency = 1; h.LayoutOrder = order; h.ZIndex = 8
	h.Font = Enum.Font.GothamBold; h.TextSize = 14; h.TextColor3 = GOLD
	h.TextXAlignment = Enum.TextXAlignment.Left; h.Text = text; h.Parent = list
end

local function row(order, name, sub, btnText, btnColour, onClick)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, -8, 0, 46); r.BackgroundColor3 = CARD; r.BorderSizePixel = 0
	r.ZIndex = 8
	r.LayoutOrder = order; r.Parent = list
	corner(r, 8)

	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1; n.Size = UDim2.new(1, -150, 0, 22); n.Position = UDim2.new(0, 10, 0, 3)
	n.Font = Enum.Font.GothamBold; n.TextSize = 15; n.TextColor3 = WHITE
	n.TextXAlignment = Enum.TextXAlignment.Left; n.TextTruncate = Enum.TextTruncate.AtEnd
	n.ZIndex = 9; n.Text = name; n.Parent = r

	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1; s.Size = UDim2.new(1, -150, 0, 16); s.Position = UDim2.new(0, 10, 0, 25)
	s.Font = Enum.Font.Gotham; s.TextSize = 12; s.TextColor3 = Color3.fromRGB(190, 210, 245)
	s.TextXAlignment = Enum.TextXAlignment.Left; s.TextTruncate = Enum.TextTruncate.AtEnd
	s.ZIndex = 9; s.Text = sub; s.Parent = r

	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(126, 32); b.Position = UDim2.new(1, -136, 0, 7)
	b.BackgroundColor3 = btnColour; b.Font = Enum.Font.GothamBold; b.TextSize = 13
	b.TextScaled = true; b.TextColor3 = WHITE; b.Text = btnText; b.ZIndex = 9; b.Parent = r
	corner(b, 7)
	b.MouseButton1Click:Connect(function() onClick(b) end)
end

-- One row per person, wired the same way everywhere: here means trade now, away means offer them something.
local function personRow(ord, id, name, here, sub)
	-- `here` only means "trade with them right now" where a trade window exists to do it in. Everywhere else
	-- being in the same server changes nothing about what this panel can offer.
	local live = here and canTradeLive()
	row(ord, name,
		sub or (live and "In this server" or "Away \xE2\x80\x94 they'll see your offer"),
		live and "TRADE NOW" or "OFFER TRADE",
		live and LIME or BLUE,
		function(b)
			if live then startLiveTrade(id) else openPicker(id, name, b) end
		end)
end

rebuild = function()
	if not list then return end
	for _, c in ipairs(list:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	local n = 0
	local function ord() n = n + 1; return n end

	-- SEARCH RESULT AT THE TOP. Somebody who just typed a name is looking for exactly one thing, and making
	-- them hunt for it below their own friends list is the surest way to make search feel broken.
	if searchNote then
		note("   " .. searchNote, ord())
	end
	if searchResult then
		heading("SEARCH RESULT", ord())
		personRow(ord(), searchResult.id, searchResult.name, searchResult.here)
	end

	-- INCOMING FIRST. It is the half somebody else acted on; buried under your own friends it gets missed.
	heading("WAITING FOR YOU (" .. #inbox .. ")", ord())
	if #inbox == 0 then
		note("   Nobody has asked yet. Search a name or invite a friend below!", ord())
	else
		for _, rec in ipairs(inbox) do
			local here = rec.here == true
			-- What they offered is the whole reason to open this, so it takes the subtitle line and the
			-- online/away status gets folded in after it.
			-- `summary` is written by the sending server; `offer` is the single-item field an earlier build
			-- wrote, and notes from it can still be sitting in a mailbox for another fortnight.
			local blurb = rec.summary
			if not blurb and rec.offers and rec.offers[1] then blurb = rec.offers[1].label end
			if not blurb and rec.offer and rec.offer.label then blurb = rec.offer.label end

			local sub
			if blurb then
				sub = "\xF0\x9F\x8E\x81 Offering: " .. tostring(blurb)
			else
				sub = here and "Online now!" or "Not online right now"
			end
			local live = here and canTradeLive()
			row(ord(), rec.fromName or "A player", sub,
				live and "TRADE NOW" or "OFFER BACK",
				live and LIME or BLUE,
				function(b)
					if live then
						startLiveTrade(rec.fromId)
					else
						openPicker(rec.fromId, rec.fromName or "them", b)
					end
				end)
		end
	end

	-- No in-server list here: this panel is a tab OF the trade overlay, whose own picker already lists the
	-- people present. Showing them again would be the same list twice.
	heading("YOUR FRIENDS", ord())
	local loading = Instance.new("TextLabel")
	loading.Size = UDim2.new(1, -8, 0, 34); loading.BackgroundTransparency = 1; loading.LayoutOrder = ord()
	loading.Font = Enum.Font.Gotham; loading.TextSize = 13; loading.TextColor3 = Color3.fromRGB(195, 215, 245)
	loading.TextXAlignment = Enum.TextXAlignment.Left; loading.Text = "   Loading friends..."; loading.Parent = list

	task.spawn(function()
		local ok, friends = pcall(function() return ReqFriends:InvokeServer() end)
		if loading.Parent then loading:Destroy() end
		if not ok or type(friends) ~= "table" or #friends == 0 then
			note("   No friends found \xE2\x80\x94 search any username above instead!", ord())
			return
		end
		for _, f in ipairs(friends) do
			personRow(ord(), f.id, f.name or "Friend", f.here)
		end
	end)
end

--======================================================================
-- SEARCH
--======================================================================
-- Names are resolved SERVER-SIDE and the canonical spelling comes back with the id, because what a player
-- types is frequently not quite the account -- wrong case, a missing underscore, a guess. Echoing their typo
-- back at them is how a request goes to a stranger with a similar name and nobody ever finds out.
local searching = false

local function doSearch()
	if searching or not searchBox then return end
	local name = searchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if #name < 3 then
		searchNote = "Type at least 3 letters of a username."
		searchResult = nil
		if open then rebuild() end
		return
	end
	if not ReqLookup then
		searchNote = "Search isn't available right now."
		if open then rebuild() end
		return
	end

	searching = true
	searchNote = "Looking for " .. name .. "..."
	searchResult = nil
	if open then rebuild() end

	task.spawn(function()
		local ok, found = pcall(function() return ReqLookup:InvokeServer(name) end)
		searching = false
		if ok and type(found) == "table" and found.id then
			searchResult = found
			searchNote = nil
		else
			searchResult = nil
			searchNote = "No player called \"" .. name .. "\" \xE2\x80\x94 check the spelling."
		end
		if open then rebuild() end
	end)
end

--======================================================================
-- FIND THE TRADE OVERLAY
--======================================================================
-- Every realm now has the SAME structure: a pet hub whose Panel holds a "TradeOverlay" page -- built by
-- PetFollow in Food and Candy, and by PetTradeClient (the Food layout, ported) in Space. This panel is a
-- second TAB inside that overlay, everywhere, because somebody standing next to you is always the better
-- trade and the in-server picker has to stay the thing you land on.
--
-- POLLED, NOT TWO WAITS IN A ROW. A WaitForChild on Food's gui name would burn its full timeout in Space
-- before ever looking for Space's -- which is exactly the bug that once made this tab take 60 seconds to
-- appear there. Polling finds whichever hub exists within a frame or two of its own script finishing.
local function findHost()
	local deadline = os.clock() + 60   -- generous: the hubs build after their own data loads

	repeat
		for _, guiName in ipairs({ "PetInventoryUI", "PetHubGui" }) do
			local gui = playerGui:FindFirstChild(guiName)
			local panel = gui and gui:FindFirstChild("Panel")
			local ov = panel and panel:FindFirstChild("TradeOverlay")
			if ov then
				overlay = ov
				return true
			end
		end
		task.wait(0.25)
	until os.clock() > deadline

	return false
end

task.spawn(function()
	if not findHost() then
		warn("[TradeReq] no pet hub found -- offline trade requests have nowhere to attach")
		return
	end

	-- The tab sits left of the overlay's own "Pets" back button, in its header strip.
	tabBtn = Instance.new("TextButton")
	tabBtn.Name = "OfflineReqTab"
	tabBtn.Size = UDim2.fromOffset(150, 34); tabBtn.Position = UDim2.new(1, -274, 0, 4)
	tabBtn.BackgroundColor3 = GOLD; tabBtn.Font = Enum.Font.GothamBlack; tabBtn.TextSize = 14
	tabBtn.TextScaled = true; tabBtn.TextColor3 = INK; tabBtn.AutoButtonColor = true
	tabBtn.Text = "\xF0\x9F\x91\xA5 FRIENDS  \xE2\x96\xB6"
	tabBtn.ZIndex = 5
	tabBtn.Parent = overlay
	corner(tabBtn, 9)
	tabStroke = stroke(tabBtn, WHITE, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 5); pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = tabBtn

	-- The count badge. It hangs off the corner rather than sitting inside the label, so it survives the
	-- button's TextScaled shrinking on small screens.
	tabBadge = Instance.new("Frame")
	tabBadge.Size = UDim2.fromOffset(22, 22); tabBadge.Position = UDim2.new(1, -11, 0, -9)
	tabBadge.BackgroundColor3 = RED; tabBadge.BorderSizePixel = 0; tabBadge.ZIndex = 6
	tabBadge.Visible = false; tabBadge.Parent = tabBtn
	corner(tabBadge, 11)
	stroke(tabBadge, WHITE, 2)
	tabBadgeText = Instance.new("TextLabel")
	tabBadgeText.Size = UDim2.fromScale(1, 1); tabBadgeText.BackgroundTransparency = 1
	tabBadgeText.Font = Enum.Font.GothamBlack; tabBadgeText.TextSize = 12; tabBadgeText.TextColor3 = WHITE
	tabBadgeText.ZIndex = 7; tabBadgeText.Text = "0"; tabBadgeText.Parent = tabBadge

	-- Same geometry as the overlay's own views, so switching tabs does not move the page around.
	content = Instance.new("Frame")
	content.Name = "OfflineReqView"
	content.Size = UDim2.new(1, -16, 1, -46); content.Position = UDim2.new(0, 8, 0, 42)
	content.BackgroundTransparency = 1; content.Visible = false
	-- ABOVE the overlay's own views, explicitly. Food builds its picker/window at default ZIndex so this never
	-- mattered there; Space builds them at 4, and a sibling at the default 1 renders UNDERNEATH them -- so if
	-- either view is ever visible at the same time as this page, this page is the one that disappears.
	content.ZIndex = 6
	content.Parent = overlay

	-- ---- search bar, fixed above the scrolling list so it cannot scroll away ----
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 34); bar.BackgroundTransparency = 1; bar.ZIndex = 7; bar.Parent = content

	searchBox = Instance.new("TextBox")
	searchBox.Size = UDim2.new(1, -96, 1, 0); searchBox.BackgroundColor3 = DEEP
	searchBox.BorderSizePixel = 0; searchBox.Font = Enum.Font.Gotham; searchBox.TextSize = 14
	searchBox.TextColor3 = WHITE; searchBox.PlaceholderColor3 = Color3.fromRGB(140, 160, 195)
	searchBox.PlaceholderText = "  Search any username..."
	searchBox.Text = ""; searchBox.ClearTextOnFocus = false
	searchBox.TextXAlignment = Enum.TextXAlignment.Left; searchBox.ZIndex = 8; searchBox.Parent = bar
	corner(searchBox, 8)
	stroke(searchBox, Color3.fromRGB(60, 100, 170), 1)
	local sp = Instance.new("UIPadding"); sp.PaddingLeft = UDim.new(0, 10); sp.Parent = searchBox

	local goBtn = Instance.new("TextButton")
	goBtn.Size = UDim2.fromOffset(88, 34); goBtn.Position = UDim2.new(1, -88, 0, 0)
	goBtn.BackgroundColor3 = LIME; goBtn.Font = Enum.Font.GothamBold; goBtn.TextSize = 14
	goBtn.TextScaled = true; goBtn.TextColor3 = WHITE; goBtn.Text = "SEARCH"; goBtn.ZIndex = 8; goBtn.Parent = bar
	corner(goBtn, 8)
	local gp = Instance.new("UIPadding")
	gp.PaddingTop = UDim.new(0, 7); gp.PaddingBottom = UDim.new(0, 7); gp.Parent = goBtn

	goBtn.MouseButton1Click:Connect(doSearch)
	-- Enter counts too. On mobile the on-screen keyboard's Go key is the natural way to finish typing, and a
	-- search box that ignores it feels broken before the player ever finds the button.
	searchBox.FocusLost:Connect(function(enter) if enter then doSearch() end end)

	list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -40); list.Position = UDim2.new(0, 0, 0, 40)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0
	list.ScrollBarThickness = 6; list.ScrollBarImageColor3 = GOLD
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 7
	list.Parent = content
	local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = list

	-- ---- offer picker ----
	-- ===== IT IS ITS OWN PAGE, NOT A SHEET OVER THE OLD ONE =====
	-- It sits on the OVERLAY rather than inside the friends view, and covers all of it. As a translucent panel
	-- over the person list it read as two screens at once: the blue rows showed through behind the pets, and
	-- the name you were offering to looked like it belonged to the list underneath rather than to the offer.
	-- Fully opaque and full-bleed, there is exactly one thing on screen and it says who it is for.
	picker = Instance.new("Frame")
	picker.Name = "OfferPicker"
	picker.Size = UDim2.new(1, 0, 1, 0); picker.Position = UDim2.new(0, 0, 0, 0)
	picker.BackgroundColor3 = Color3.fromRGB(6, 22, 56)
	picker.BackgroundTransparency = 0; picker.BorderSizePixel = 0
	picker.Visible = false; picker.ZIndex = 50; picker.Parent = overlay
	corner(picker, 10)
	stroke(picker, GOLD, 2)

	-- Header band. Solid, because the recipient's name is the one thing on this page that must not be
	-- mistakable for part of anything else.
	local pBand = Instance.new("Frame")
	pBand.Size = UDim2.new(1, 0, 0, 54); pBand.BackgroundColor3 = CARD; pBand.BorderSizePixel = 0
	pBand.ZIndex = 51; pBand.Parent = picker
	corner(pBand, 10)
	-- Square off the bottom of the band so it meets the body flush instead of showing two rounded corners
	-- floating in the middle of the panel.
	local pBandFill = Instance.new("Frame")
	pBandFill.Size = UDim2.new(1, 0, 0, 12); pBandFill.Position = UDim2.new(0, 0, 1, -12)
	pBandFill.BackgroundColor3 = CARD; pBandFill.BorderSizePixel = 0; pBandFill.ZIndex = 51
	pBandFill.Parent = pBand

	local pCap = Instance.new("TextLabel")
	pCap.Size = UDim2.new(1, -60, 0, 14); pCap.Position = UDim2.new(0, 14, 0, 7)
	pCap.BackgroundTransparency = 1; pCap.Font = Enum.Font.GothamBold; pCap.TextSize = 11
	pCap.TextColor3 = GOLD; pCap.TextXAlignment = Enum.TextXAlignment.Left
	pCap.ZIndex = 52; pCap.Text = "OFFERING TO"; pCap.Parent = pBand

	-- Kept as a direct child of the picker so `picker.Title` still resolves, even though it draws over the band.
	local pTitle = Instance.new("TextLabel")
	pTitle.Name = "Title"
	pTitle.Size = UDim2.new(1, -60, 0, 26); pTitle.Position = UDim2.new(0, 14, 0, 22)
	pTitle.BackgroundTransparency = 1; pTitle.Font = Enum.Font.GothamBlack; pTitle.TextSize = 19
	pTitle.TextColor3 = WHITE; pTitle.TextXAlignment = Enum.TextXAlignment.Left
	pTitle.TextTruncate = Enum.TextTruncate.AtEnd; pTitle.ZIndex = 52
	pTitle.Text = "\xE2\x80\x94"; pTitle.Parent = picker

	local pClose = Instance.new("TextButton")
	pClose.Size = UDim2.fromOffset(34, 34); pClose.Position = UDim2.new(1, -44, 0, 10)
	pClose.BackgroundColor3 = Color3.fromRGB(190, 60, 60); pClose.Font = Enum.Font.GothamBold
	pClose.TextSize = 18; pClose.TextColor3 = WHITE; pClose.Text = "X"; pClose.ZIndex = 52
	pClose.Parent = picker
	corner(pClose, 8)
	stroke(pClose, WHITE, 2)
	-- X only. Tapping the backdrop must never dismiss this -- a stray thumb on a phone would close it mid-
	-- scroll, which is the single most annoying way for a menu to behave.
	pClose.MouseButton1Click:Connect(closePicker)

	local pBody = Instance.new("ScrollingFrame")
	pBody.Name = "Body"
	pBody.Size = UDim2.new(1, -16, 1, -128); pBody.Position = UDim2.new(0, 8, 0, 60)
	pBody.BackgroundTransparency = 1; pBody.BorderSizePixel = 0
	pBody.ScrollBarThickness = 6; pBody.ScrollBarImageColor3 = GOLD
	pBody.CanvasSize = UDim2.new(0, 0, 0, 0); pBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pBody.ZIndex = 51; pBody.Parent = picker
	local pLayout = Instance.new("UIListLayout"); pLayout.Padding = UDim.new(0, 5)
	pLayout.SortOrder = Enum.SortOrder.LayoutOrder; pLayout.Parent = pBody

	-- ---- footer: pinned, never scrolls ----
	-- The send button lives OUTSIDE the scrolling list on purpose. Put it at the bottom of the items and a
	-- player with thirty pets has to scroll past all of them to find out how to finish, which is exactly the
	-- moment they give up. Pinned, the way out is visible from the first frame.
	local pFoot = Instance.new("Frame")
	pFoot.Name = "Footer"
	pFoot.Size = UDim2.new(1, -16, 0, 60); pFoot.Position = UDim2.new(0, 8, 1, -66)
	pFoot.BackgroundTransparency = 1; pFoot.ZIndex = 52; pFoot.Parent = picker

	local pHint = Instance.new("TextLabel")
	pHint.Name = "Hint"
	pHint.Size = UDim2.new(1, 0, 0, 16); pHint.BackgroundTransparency = 1
	pHint.Font = Enum.Font.Gotham; pHint.TextSize = 11; pHint.TextColor3 = Color3.fromRGB(180, 200, 235)
	pHint.TextXAlignment = Enum.TextXAlignment.Left; pHint.TextTruncate = Enum.TextTruncate.AtEnd
	pHint.ZIndex = 53; pHint.Text = ""; pHint.Parent = pFoot

	local pSend = Instance.new("TextButton")
	pSend.Name = "Send"
	pSend.Size = UDim2.new(1, 0, 0, 38); pSend.Position = UDim2.new(0, 0, 0, 20)
	pSend.BackgroundColor3 = BLUE; pSend.Font = Enum.Font.GothamBlack; pSend.TextSize = 16
	pSend.TextScaled = true; pSend.TextColor3 = WHITE; pSend.ZIndex = 53
	pSend.Text = "SEND"; pSend.Parent = pFoot
	corner(pSend, 8)
	stroke(pSend, WHITE, 2)
	local fp = Instance.new("UIPadding")
	fp.PaddingTop = UDim.new(0, 8); fp.PaddingBottom = UDim.new(0, 8)
	fp.PaddingLeft = UDim.new(0, 10); fp.PaddingRight = UDim.new(0, 10)
	fp.Parent = pSend

	if tabBtn then
		tabBtn.MouseButton1Click:Connect(function()
			if open then setOpen(false) else clearOfferCache(); setOpen(true); rebuild() end
		end)
	end

	refreshTab()
	pulseTab()

	-- A live trade beginning must take the screen back, or the request list would be sitting on top of the
	-- actual trade the player just agreed to. (No such event in a realm without live trading; the guard is
	-- what lets the same file load there.)
	local state = ReplicatedStorage:FindFirstChild("PetTradeStateEvent")
	if state and state:IsA("RemoteEvent") then
		state.OnClientEvent:Connect(function() if open then closePicker(); setOpen(false) end end)
	end

	-- Leaving the overlay entirely resets the tab, so reopening Trade always lands on the in-server list.
	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		if not overlay.Visible and open then closePicker(); setOpen(false) end
	end)

	print("[TradeReq] client ready -- FRIENDS tab added to the trade overlay")
end)

-- Kept for anything that wants to jump straight here (a HUD button, a notification tap).
_G.toggleTradeRequests = function()
	if not overlay then return end
	if not overlay.Visible then
		local ev = playerGui:FindFirstChild("PetInvToggle")
		if ev and ev:IsA("BindableEvent") then ev:Fire() end
		return
	end
	if open then setOpen(false) else clearOfferCache(); setOpen(true); rebuild() end
end

--======================================================================
-- SERVER MESSAGES
--======================================================================
ReqInbox.OnClientEvent:Connect(function(l)
-- Someone wants to trade. Light: this arrives unprompted and may arrive repeatedly.
if _G.hapticPulse then pcall(_G.hapticPulse, "tock") end
	if type(l) ~= "table" then return end
	inbox = l
	table.sort(inbox, function(a, b) return (tonumber(a.at) or 0) > (tonumber(b.at) or 0) end)
	if #inbox > 0 then
		local who = (#inbox == 1) and (inbox[1].fromName or "A player") or (#inbox .. " players")
		toast("\xF0\x9F\x94\x81 " .. who .. " want" .. ((#inbox == 1) and "s" or "") ..
			" to trade! Check PETS \xE2\x86\x92 Trade \xE2\x86\x92 Friends.", GOLD)
	end
	refreshTab()
	if open then rebuild() end
end)

ReqResult.OnClientEvent:Connect(function(ok, message)
	toast((ok and "\xE2\x9C\x85 " or "\xE2\x9A\xA0 ") .. tostring(message or ""),
		ok and LIME or Color3.fromRGB(255, 120, 90))
	-- A refusal usually means the world moved: the friend came online, the inbox filled. Redraw so the
	-- buttons match reality instead of leaving a stale "SENDING..." on screen.
	if not ok and open then rebuild() end
end)
