--======================================================================
-- PetHubTabs_DinoRealm.client.luau
-- LocalScript -> StarterPlayer > StarterPlayerScripts
--======================================================================
-- THE PET HUB TOP TAB BAR: a horizontal row of tabs sitting directly under the hub
-- header -- PETS / CRATES / TOKENS / TRADE / QUESTS -- each with its own icon.
--
--   ACTIVE    gold fill, dark text, thicker gold stroke
--   INACTIVE  dark blue fill, gold text, thin white stroke
--
-- Same geometry, colours and behaviour as the main game's HubNav (PetFollow.client.lua
-- :3948 for the bar, :5387 for the router), rewritten to be self-contained: no remotes,
-- no pet system, no dependencies beyond stock services. Point it at your panel, hand it
-- a callback, done.
--
-- ===== IT IS A ROUTER, NOT A SET OF TOGGLES =====
-- The original tabs were independent toggles, which let you end up with the pet grid
-- showing while the nav claimed you were on Quests. This SETS state instead of flipping
-- it, so the highlighted tab and the visible page cannot drift apart. Keep that.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ---- WHERE THE BAR GOES ----
	-- Leave AUTO_ATTACH true and set these two names to have the bar find your hub and
	-- attach itself. Set it false to drive everything manually through _G.HubTabs.build.
	AUTO_ATTACH = true,
	GUI_NAME    = "PetInventoryUI", -- the ScreenGui holding the hub
	PANEL_NAME  = "Panel",          -- the panel frame inside it that the bar parents to

	-- ---- THE TABS ----
	-- id is what your callback receives. Order here is the order on screen.
	TABS = {
		{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS"   }, -- 🐾
		{ id = "food",   label = "\xF0\x9F\x8D\x94 PETS"   }, -- 🍔 first-realm (Food Realm) pet collection -- the burger tells the two PETS tabs apart
		{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" }, -- 📦
		{ id = "tokens", label = "\xF0\x9F\x8E\x9F TOKENS" }, -- 🎟
		{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE"  }, -- 🔄
		{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS" }, -- 📜
	},

	-- ---- GEOMETRY ----
	-- 6 x 106 + 5 x 8 padding = 676, which fills a 676-wide panel body exactly. Change
	-- BTN_W if you add or remove a tab: (panelWidth - 20 - PADDING*(n-1)) / n
	BAR_HEIGHT = 38,
	BAR_Y      = 64,   -- directly under this hub's 60px header
	                   -- NOTE: PetHub's content band was moved from y=68 to y=108 to
	                   -- make room. If you change BAR_Y/BAR_HEIGHT, move it to match.
	BAR_INSET  = 10,   -- left/right margin inside the panel
	BTN_W      = 106,
	PADDING    = 8,
	CORNER     = 10,
	TEXT_SIZE  = 15,

	-- ---- COLOURS ----
	ACTIVE_BG      = Color3.fromRGB(255, 215,   0), -- gold
	ACTIVE_TEXT    = Color3.fromRGB( 92,  58,   8), -- dark brown-on-gold
	ACTIVE_STROKE  = Color3.fromRGB(180, 122,  20),
	ACTIVE_THICK   = 2.5,
	IDLE_BG        = Color3.fromRGB( 26,  48,  30), -- deep jungle, same as the hub header
	IDLE_TEXT      = Color3.fromRGB(255, 215,   0), -- gold
	IDLE_STROKE    = Color3.fromRGB( 74,  94,  68), -- the header's own stroke colour
	IDLE_THICK     = 1.5,

	-- ---- BEHAVIOUR ----
	DEFAULT_TAB = "pets",
	HOVER_LIFT  = true,  -- a subtle 1.03 scale on hover
}

--======================================================================
local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

--======================================================================
-- THE API
--
-- local tabs = _G.HubTabs.build(panel, onSelect)
--     onSelect(id) fires on every click AND once on build for the default tab, so your
--     page-showing code lives in ONE place instead of being duplicated at startup.
--
-- tabs.setActive(id)  -- highlight a tab without firing the callback
-- tabs.select(id)     -- highlight AND fire the callback (same as a click)
-- tabs.buttons        -- { [id] = TextButton }
-- tabs.active         -- the current id
--======================================================================
_G.HubTabs = _G.HubTabs or {}

function _G.HubTabs.build(parent, onSelect)
	if not (parent and parent:IsA("GuiObject")) then
		warn("[HubTabs] build() needs a GuiObject to parent to")
		return nil
	end

	local api = { buttons = {}, active = nil }

	local bar = Instance.new("Frame")
	bar.Name = "HubNav"
	bar.Size = UDim2.new(1, -(CONFIG.BAR_INSET * 2), 0, CONFIG.BAR_HEIGHT)
	bar.Position = UDim2.new(0, CONFIG.BAR_INSET, 0, CONFIG.BAR_Y)
	bar.BackgroundTransparency = 1
	bar.Parent = parent

	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, CONFIG.PADDING)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = bar

	-- HIGHLIGHT. Sets every button from one source of truth (api.active) rather than
	-- toggling the one that was clicked -- so two tabs can never both look selected.
	function api.setActive(id)
		api.active = id
		for tabId, b in pairs(api.buttons) do
			local on = (tabId == id)
			b.BackgroundColor3 = on and CONFIG.ACTIVE_BG or CONFIG.IDLE_BG
			b.TextColor3       = on and CONFIG.ACTIVE_TEXT or CONFIG.IDLE_TEXT
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color     = on and CONFIG.ACTIVE_STROKE or CONFIG.IDLE_STROKE
				st.Thickness = on and CONFIG.ACTIVE_THICK or CONFIG.IDLE_THICK
			end
		end
	end

	function api.select(id)
		api.setActive(id)
		if onSelect then pcall(onSelect, id) end
	end

	for i, t in ipairs(CONFIG.TABS) do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. t.id
		b.Size = UDim2.new(0, CONFIG.BTN_W, 1, 0)
		b.LayoutOrder = i
		b.BackgroundColor3 = CONFIG.IDLE_BG
		b.Text = t.label
		b.Font = Enum.Font.FredokaOne
		b.TextSize = CONFIG.TEXT_SIZE
		-- TextScaled + a MaxTextSize constraint: the label shrinks to fit a narrow button
		-- on a phone, but never grows past the authored size on a wide one.
		b.TextScaled = true
		b.TextColor3 = CONFIG.IDLE_TEXT
		b.AutoButtonColor = false
		b.Parent = bar
		corner(b, CONFIG.CORNER)
		stroke(b, CONFIG.IDLE_STROKE, CONFIG.IDLE_THICK)
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = CONFIG.TEXT_SIZE; c.Parent = b

		if CONFIG.HOVER_LIFT then
			local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = b
			local qi = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			b.MouseEnter:Connect(function() TweenService:Create(sc, qi, { Scale = 1.03 }):Play() end)
			b.MouseLeave:Connect(function() TweenService:Create(sc, qi, { Scale = 1 }):Play() end)
		end

		api.buttons[t.id] = b
		b.MouseButton1Click:Connect(function()
			if _G.playUIClick then pcall(_G.playUIClick) end
			api.select(t.id)
		end)
	end

	api.select(CONFIG.DEFAULT_TAB)
	return api
end

--======================================================================
-- AUTO-ATTACH
--
-- Waits for the hub to exist, builds the bar, and routes to pages by NAME: a tab with
-- id "quests" shows a child called "QuestsOverlay" or "QuestsPage" and hides the others.
-- Replace the body of showPage with your own routing when your pages are ready.
--======================================================================
if CONFIG.AUTO_ATTACH then
	task.spawn(function()
		local gui = PlayerGui:WaitForChild(CONFIG.GUI_NAME, 60)
		if not gui then
			warn(("[HubTabs] no ScreenGui named %q -- set CONFIG.GUI_NAME or call _G.HubTabs.build yourself")
				:format(CONFIG.GUI_NAME))
			return
		end
		local panel = gui:WaitForChild(CONFIG.PANEL_NAME, 30) or gui:FindFirstChildWhichIsA("Frame")
		if not panel then
			warn(("[HubTabs] no panel named %q inside %s"):format(CONFIG.PANEL_NAME, CONFIG.GUI_NAME))
			return
		end

		-- Don't stack a second bar if this script re-runs (respawn, hot reload).
		local existing = panel:FindFirstChild("HubNav")
		if existing then existing:Destroy() end

		local function showPage(id)
			-- PREFER the hub's own set-state entry points.
			--
			-- The generic fallback below only flips a frame's Visible, which is not enough for
			-- this hub: its trade overlay holds two sub-views and the player list is filled by
			-- refreshPicker(), reached only via showPicker(). Revealing the frame alone gave an
			-- empty panel that read as "the tab did nothing".
			local hubShow = ({ pets = _G.PetHubShowPets, food = _G.PetHubShowFood, quests = _G.PetHubShowQuests, trade = _G.PetHubShowTrade })[id]
			if hubShow then
				pcall(hubShow)
			else
				-- Fallback for a hub that hasn't got the entry points: show/hide by frame name.
				-- Both spellings are accepted because the main game names them
				-- "QuestsOverlay" / "TradeOverlay" while a fresh build tends to use "QuestsPage".
				for _, t in ipairs(CONFIG.TABS) do
					local cap = t.id:sub(1, 1):upper() .. t.id:sub(2)
					for _, suffix in ipairs({ "Overlay", "Page", "Section" }) do
						local pg = panel:FindFirstChild(cap .. suffix)
						if pg and pg:IsA("GuiObject") then pg.Visible = (t.id == id) end
					end
				end
			end
			-- Hand-offs: in the main game CRATES and TOKENS are pages of the crate panel,
			-- not of the hub -- it already owns the roll, the reveal and the token purchase,
			-- and a second copy of any of those is a second thing that can disagree with the
			-- server. Route them out rather than rebuilding them here.
			if (id == "crates" or id == "tokens") and _G.toggleSkinCrates then
				pcall(_G.toggleSkinCrates, true, id)
			end
		end

		local tabs = _G.HubTabs.build(panel, showPage)
		_G.PetHubTabs = tabs -- so other scripts can call tabs.select("quests")

		print(("[HubTabs] attached to %s.%s -- %d tabs"):format(CONFIG.GUI_NAME, CONFIG.PANEL_NAME, #CONFIG.TABS))
	end)
end

print("[HubTabs] loaded -- _G.HubTabs.build(panel, onSelect)")
