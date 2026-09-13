--======================================================================
-- PetHubTabs_DinoRealm.client.luau
-- LocalScript -> StarterPlayer > StarterPlayerScripts
--======================================================================
-- THE PET HUB TOP TAB BAR -- the first realm's current HubNav (Fart to Float push 8a5041b, the same bar
-- Space Realm's hub uses), in this realm's jungle colours:
--
--   PETS · FOOD · SPACE · QUESTS · CRATES · TRADE      six tabs, 106px each, 8px apart, bar at y=66, 38 tall
--
-- TAB MAPPING (first realm -> Dino):
--   PETS    -> this realm's own dino pets (the hub's pets grid)
--   SPACE / DINO (the first realm's "other realm collection" tabs) -> FOOD, the one other-realm collection
--            this realm carries (the Food Realm pets that ride the rift teleport, read-only)
--   QUESTS  -> kept in the realm slot the second collection tab would use: the Dino hub has a real pet-quest
--            page and the first realm simply has no equivalent, so dropping it would lose a working feature
--   CRATES  -> the crate panel (SkinCrateClient). TOKENS is no longer a tab: like the first realm's tickets,
--            it is a sub-page of CRATES reached from the GET TOKENS banner (select("tokens") still works)
--   TRADE   -> the hub's trade page
--
--   ACTIVE    gold fill, dark ink, thicker gold-brown edge
--   INACTIVE  deep jungle fill, gold word, the header's own edge colour
--
-- THE WORD IS A CHILD LABEL, NOT THE BUTTON'S OWN TEXT (the first realm's trick): a UIStroke on a FILLED text
-- object outlines the object's border, so the only way to outline the letters is a transparent label on top.
--
-- ===== IT IS A ROUTER, NOT A SET OF TOGGLES =====
-- select() SETS state instead of flipping it, so the highlighted tab and the visible page cannot drift apart.
--
-- API (unchanged -- PetHub and SkinCrateClient call it):
--   _G.HubTabs.build(panel, onSelect) -> tabs      tabs.select(id), tabs.setActive(id), tabs.buttons, tabs.active
--   _G.PetHubTabs                                  the hub's instance
--   _G.PetHub.showPage(id) / .navButtons / .panel  the first realm's contract names, for parity with the other realms
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

local CONFIG = {
	AUTO_ATTACH = true,
	GUI_NAME    = "PetInventoryUI", -- the ScreenGui holding the hub
	PANEL_NAME  = "Panel",          -- the panel frame inside it that the bar parents to

	TABS = {
		{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS"   }, -- 🐾 this realm's dinos
		{ id = "food",   label = "\xF0\x9F\x8D\x94 FOOD"   }, -- 🍔 the Food Realm collection
		{ id = "space",  label = "\xF0\x9F\x9A\x80 SPACE"  }, -- 🚀 the Space Realm collection (read-only, like FOOD)
		{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS" }, -- 📜
		{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" }, -- 📦 (tokens live inside)
		{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE"  }, -- 🔄
	},
	-- ids that are pages of another tab: selecting one lights its parent
	PARENT = { tokens = "crates" },

	-- SIX tabs now (SPACE added): 6 x 106 + 5 x 8 = 676, inside the same 680px bar the first realm's five use
	BAR_HEIGHT = 38,
	BAR_Y      = 66,
	BAR_INSET  = 10,
	BTN_W      = 106,
	PADDING    = 8,
	CORNER     = 10,
	TEXT_SIZE  = 15,

	ACTIVE_BG      = Color3.fromRGB(255, 215,   0), -- gold
	ACTIVE_TEXT    = Color3.fromRGB( 92,  58,   8), -- dark brown-on-gold
	ACTIVE_STROKE  = Color3.fromRGB(180, 122,  20),
	ACTIVE_THICK   = 2.5,
	IDLE_BG        = Color3.fromRGB( 26,  48,  30), -- deep jungle, same as the hub header
	IDLE_TEXT      = Color3.fromRGB(255, 215,   0), -- gold
	IDLE_STROKE    = Color3.fromRGB( 74,  94,  68), -- the header's own stroke colour
	IDLE_THICK     = 1.5,

	DEFAULT_TAB = "pets",
	HOVER_LIFT  = true,
}

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

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
	bar.ZIndex = 3
	bar.Parent = parent

	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, CONFIG.PADDING)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = bar

	-- HIGHLIGHT from one source of truth (api.active), so two tabs can never both look selected.
	function api.setActive(id)
		api.active = id
		local lit = CONFIG.PARENT[id] or id
		for tabId, b in pairs(api.buttons) do
			local on = (tabId == lit)
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
		b.Text = "" -- the word is the child label below
		b.Font = Enum.Font.FredokaOne
		b.TextColor3 = CONFIG.IDLE_TEXT
		b.AutoButtonColor = false
		b.ZIndex = 4
		b.Parent = bar
		corner(b, CONFIG.CORNER)
		do local st = stroke(b, CONFIG.IDLE_STROKE, CONFIG.IDLE_THICK); st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.new(1, -8, 1, -6)
		lbl.Position = UDim2.new(0, 4, 0, 3)
		lbl.BackgroundTransparency = 1
		lbl.Text = t.label
		lbl.Font = Enum.Font.FredokaOne
		-- TextScaled + a ceiling: shrinks to fit a phone, never grows past the authored size (this realm's
		-- repositionGUIs sweep force-sets TextScaled anyway, so the constraint is what actually holds it).
		lbl.TextSize = CONFIG.TEXT_SIZE
		lbl.TextScaled = true
		lbl.TextWrapped = false
		lbl.TextColor3 = CONFIG.IDLE_TEXT
		lbl.ZIndex = 5
		lbl.Parent = b
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = CONFIG.TEXT_SIZE; c.Parent = lbl end
		stroke(lbl, Color3.new(0, 0, 0), 2)
		-- anything that recolours the BUTTON carries over to the word
		b:GetPropertyChangedSignal("TextColor3"):Connect(function() lbl.TextColor3 = b.TextColor3 end)

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
-- AUTO-ATTACH: find the hub, build the bar, route pages
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
			-- CRATES / TOKENS are pages of the crate panel, not of the hub: it owns the roll, the reveal and the
			-- token purchase, and a second copy would be a second thing that can disagree with the server.
			if id == "crates" or id == "tokens" then
				if _G.toggleSkinCrates then pcall(_G.toggleSkinCrates, true, id) end
				return
			end
			-- The hub's own SET-state entry points (the trade page must be populated, not just revealed).
			local hubShow = ({ pets = _G.PetHubShowPets, food = _G.PetHubShowFood, space = _G.PetHubShowSpace, quests = _G.PetHubShowQuests, trade = _G.PetHubShowTrade })[id]
			if hubShow then pcall(hubShow) end
		end

		local tabs = _G.HubTabs.build(panel, showPage)
		_G.PetHubTabs = tabs -- other scripts call tabs.select("quests")

		-- The first realm's contract names, so code written against its hub (or Space's) works here too.
		_G.PetHub = _G.PetHub or {}
		_G.PetHub.panel = panel
		_G.PetHub.navButtons = tabs and tabs.buttons or {}
		_G.PetHub.showPage = function(id) if tabs then tabs.select(id) end end
		_G.PetHub.syncNav = function() if tabs then tabs.setActive(tabs.active or "pets") end end

		print(("[HubTabs] attached to %s.%s -- %d tabs (PETS / FOOD / SPACE / QUESTS / CRATES / TRADE, first-realm bar)")
			:format(CONFIG.GUI_NAME, CONFIG.PANEL_NAME, #CONFIG.TABS))
	end)
end

print("[HubTabs] loaded -- _G.HubTabs.build(panel, onSelect)")
