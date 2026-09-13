--======================================================================
-- PetHub_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of the WHOLE pets feature from the main game, lifted
-- VERBATIM from PetFollow.client.lua + CoreClient.client.lua:
--
--   1. PETS BUTTON   -- a green paw HUD button (bottom-left) that toggles the
--                       Pet Hub (the game routes this through a PetInvToggle
--                       BindableEvent; that wiring is reproduced here).
--   2. PET HUB       -- the 700x520 blue panel: a grid of OWNED pet cards with
--                       3D auto-rotating viewport icons, name, rarity tier,
--                       level, XP bar, next-milestone hint, EQUIP + tier-SKIP.
--   3. QUESTS TAB    -- the discovered-quests overlay (island / status / how-to).
--   4. TRADE         -- full trade UI: pick a player -> request -> trade window
--                       (your offer / their offer / add list / confirm+cancel)
--                       + the incoming-request ACCEPT/DECLINE popup.
--
-- It talks to the SAME server remotes (PetEquipEvent, PetInventoryEvent,
-- PetTrade*Event, ...) but every remote lookup is GUARDED -- if the server
-- isn't present the UI still builds and a built-in DEMO inventory is shown so
-- you can see exactly how it looks. The moment the real remotes exist + the
-- server fires PetInventoryEvent / PetTradeStateEvent, live data takes over.
--
-- The 3D card icons reuse the real low-poly pet builders (Coconut Crab /
-- Popcorn Sheep / Butter Duck / Broccoli) instead of the heavy server Union +
-- accessory pipeline, so it renders standalone. Drop into StarterPlayer >
-- StarterPlayerScripts (or sync via Rojo) and it runs.
--======================================================================

local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")

-- The PERMANENT rarity axis (Common..Gold) and the fusion cost ladder. Separate from the pet's AGE tier, which
-- petTier() below derives from level -- a pet's rarity never moves, its age always does.
local PetRarity = require(RS:WaitForChild("Shared"):WaitForChild("PetRarity"))
local RunService        = game:GetService("RunService")
local MarketplaceService= game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

-- ============================================================================
-- REMOTES -- looked up if they exist (no WaitForChild block); nil-safe so the
-- whole file runs standalone. Live data flows in automatically once present.
-- ============================================================================
local function remote(name) return RS:FindFirstChild(name) end
local PetEquipEvent      = remote("PetEquipEvent")
local PetInventoryEvent  = remote("PetInventoryEvent")
local PetPendingUpgrade  = remote("PetPendingUpgradeEvent")
local PetFuseEvent       = remote("PetFuseEvent")       -- c->s: (storageKey) burn N duplicates -> next rarity
local PetFuseResult      = remote("PetFuseResultEvent") -- s->c: (ok, info) fusion outcome
local PetProgressEvent   = remote("PetProgressEvent")
-- STAGE 3 TRADE remotes (client sends intents only)
local PetTradeRequest = remote("PetTradeRequestEvent")
local PetTradeRespond = remote("PetTradeRespondEvent")
local PetTradeOffer   = remote("PetTradeOfferEvent")
local PetTradeConfirm = remote("PetTradeConfirmEvent")
local PetTradeCancel  = remote("PetTradeCancelEvent")
local PetTradeState   = remote("PetTradeStateEvent")
local PetTradePrompt  = remote("PetTradeRequestPromptEvent")

-- ⚠ REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (must match PET_SKIP_PRODUCTS in
-- PetSystem.server.lua). Each jumps the pet to the FIRST level of the next tier. (Ordered 1=Common->Uncommon ... 4=Epic->Legendary.)
local PET_SKIP_PRODUCTS = {
	{ to = "Uncommon",  price = 49,  id = 123456701 },
	{ to = "Rare",      price = 99,  id = 123456702 },
	{ to = "Epic",      price = 299, id = 123456703 },
	{ to = "Legendary", price = 599, id = 123456704 },
}

-- ============================================================================
-- RARITY TIER LABELS (VERBATIM from PetFollow.client.lua)
-- ============================================================================
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230), true, true
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end
	end
	if level <= 5      then return "Common",    Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Uncommon",  Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Rare",      Color3.fromRGB(70,140,255),  false, false
	elseif level <= 20 then return "Epic",      Color3.fromRGB(180,90,235),  false, false
	else                    return "Legendary", Color3.fromRGB(255,170,40),  false, false end
end
local PET_DISPLAY = { BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny" }

-- ============================================================================
-- PET MODEL BUILDERS (for the 3D viewport icons) -- copied from PetFollow.
-- Replaces the heavy server-Union + accessory pipeline with the real low-poly
-- bodies so the cards render standalone. +X = front.
-- ============================================================================
local petAnims = setmetatable({}, { __mode = "k" }) -- builders write a temp entry here; icons are static so it's unused
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

local function buildCoconutCrab(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "CoconutCrab"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0)
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4)
	for _, ez in ipairs({-0.45, 0.45}) do mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez); mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez) end
	for _, cs in ipairs({-1, 1}) do mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2); mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45) end
	for _, ls in ipairs({-1, 1}) do for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95) end end
	petAnims[model] = { s = s, parts = parts }; return model
end
local function buildPopcornSheep(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "PopcornSheep"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0)
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},{0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do local r = 0.72 + math.abs(b[2])*0.04; mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3]) end
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0); mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0)
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62); mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62)
	for _, ez in ipairs({0.32, -0.32}) do mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez); mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez) end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0)
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2]) end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0)
	petAnims[model] = { s = s, parts = parts }; return model
end
local function buildButterDuck(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "ButterDuck"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0); mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0); mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0)
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0); mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0)
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0); mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0)
	for _, ez in ipairs({0.42, -0.42}) do mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez); mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez) end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15) end
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls) end
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = 0.08 end end
	petAnims[model] = { s = s, parts = parts }; return model
end
-- a simple broccoli "bunny" stand-in for BroccoliPet + the generic fallback icon
local function buildBroccoliBlob(scale)
	local model = Instance.new("Model"); model.Name = "BroccoliBlob"; local s = scale or 1
	local stalk = newPart(model, "Root", Enum.PartType.Block, Vector3.new(0.85*s, 1.3*s, 0.85*s), Color3.fromRGB(175, 200, 140), CFrame.new(0,0,0)); model.PrimaryPart = stalk
	local crownC = Color3.fromRGB(60, 160, 60)
	newPart(model, "Floret0", Enum.PartType.Ball, Vector3.new(1.5*s,1.5*s,1.5*s), crownC, CFrame.new(0, 1.1*s, 0))
	for i = 1, 5 do local a = (i-1) * (2*math.pi/5); newPart(model, "Floret"..i, Enum.PartType.Ball, Vector3.new(1.05*s,1.05*s,1.05*s), crownC, CFrame.new(math.cos(a)*0.85*s, 0.95*s, math.sin(a)*0.85*s)) end
	for _, sx in ipairs({-0.35, 0.35}) do
		newPart(model, "Eye", Enum.PartType.Ball, Vector3.new(0.42*s,0.42*s,0.42*s), Color3.fromRGB(255,255,255), CFrame.new(sx*s, 1.15*s, 0.62*s))
		newPart(model, "Pupil", Enum.PartType.Ball, Vector3.new(0.22*s,0.22*s,0.22*s), Color3.fromRGB(20,20,20), CFrame.new(sx*s, 1.15*s, 0.78*s))
	end
	petAnims[model] = { s = s, parts = {} }; return model
end
local PET_ICON_BUILDER = {
	CoconutCrab = buildCoconutCrab, PopcornSheep = buildPopcornSheep, ButterDuck = buildButterDuck,
	BroccoliPet = buildBroccoliBlob, BurritoArmadillo = buildBroccoliBlob, -- (armadillo builder omitted; broccoli stand-in)
}

-- ============================================================================
-- PET HUB PANEL -- VERBATIM from PetFollow.client.lua (Pet Hub region).
-- ============================================================================
local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5)
panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui
uicorner(panel, 18); uistroke(panel, Color3.new(1,1,1), 3)

-- HEADER
local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,60); header.BackgroundColor3 = Color3.fromRGB(15,60,140); header.Parent = panel
uicorner(header, 18)
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 26
title.TextColor3 = Color3.fromRGB(255,215,0); title.Text = "\xF0\x9F\x90\xBE PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1,-60,0,34); title.Position = UDim2.new(0,14,0,5); title.Parent = header
uistroke(title, Color3.new(0,0,0), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
subtitle.TextColor3 = Color3.new(1,1,1); subtitle.Text = "Your pets & quest progress"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(1,-60,0,16); subtitle.Position = UDim2.new(0,14,0,40); subtitle.Parent = header
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2)

-- PETS section (fills the panel width: 2 big cards/row)
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-74); sec.Position = UDim2.new(0,x,0,68)
	sec.BackgroundColor3 = Color3.fromRGB(18,66,150); sec.BackgroundTransparency = 0.25; sec.Parent = panel
	uicorner(sec, 12); uistroke(sec, Color3.fromRGB(10,40,100), 2)
	local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,-12,0,22); t.Position = UDim2.new(0,8,0,6)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 16; t.TextColor3 = Color3.fromRGB(255,215,0)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = titleText; t.Parent = sec
	local sc = Instance.new("ScrollingFrame"); sc.Size = UDim2.new(1,-12,1,-34); sc.Position = UDim2.new(0,6,0,30)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 6; sc.ScrollBarImageColor3 = Color3.fromRGB(255,215,0)
	sc.CanvasSize = UDim2.new(0,0,0,0); sc.Parent = sec
	return sec, sc
end
local petsSection, petsScroll = makeSection(12, 676, "\xF0\x9F\x90\xBe PETS")
petsSection.Size = UDim2.new(1, -24, 1, -74); petsSection.Position = UDim2.new(0, 12, 0, 68)
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,322,0,252); petsGrid.CellPadding = UDim2.new(0,10,0,12)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; petsGrid.Parent = petsScroll
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = petsScroll
end

-- QUESTS overlay
local questsOverlay = Instance.new("Frame"); questsOverlay.Name = "QuestsOverlay"; questsOverlay.Size = UDim2.new(1,-24,1,-74); questsOverlay.Position = UDim2.new(0,12,0,68)
questsOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); questsOverlay.Visible = false; questsOverlay.Parent = panel; uicorner(questsOverlay, 12); uistroke(questsOverlay, Color3.fromRGB(10,40,100), 2)
local qoTitle = Instance.new("TextLabel"); qoTitle.Size = UDim2.new(1,-120,0,28); qoTitle.Position = UDim2.new(0,12,0,8); qoTitle.BackgroundTransparency = 1
qoTitle.Font = Enum.Font.GothamBold; qoTitle.TextSize = 18; qoTitle.TextColor3 = Color3.fromRGB(255,215,0); qoTitle.TextXAlignment = Enum.TextXAlignment.Left; qoTitle.Text = "\xF0\x9F\x97\xBA Pet Quests"; qoTitle.Parent = questsOverlay
local qoBack = Instance.new("TextButton"); qoBack.Size = UDim2.new(0,100,0,28); qoBack.Position = UDim2.new(1,-108,0,8); qoBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
qoBack.Font = Enum.Font.GothamBold; qoBack.TextSize = 13; qoBack.TextColor3 = Color3.new(1,1,1); qoBack.Text = "\xE2\x97\x80 Pets"; qoBack.Parent = questsOverlay; uicorner(qoBack, 8)
local questsScroll = Instance.new("ScrollingFrame"); questsScroll.Size = UDim2.new(1,-16,1,-46); questsScroll.Position = UDim2.new(0,8,0,42); questsScroll.BackgroundTransparency = 1; questsScroll.BorderSizePixel = 0
questsScroll.ScrollBarThickness = 6; questsScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); questsScroll.CanvasSize = UDim2.new(0,0,0,0); questsScroll.Parent = questsOverlay
local questsList = Instance.new("UIListLayout"); questsList.Padding = UDim.new(0,8); questsList.SortOrder = Enum.SortOrder.LayoutOrder; questsList.Parent = questsScroll
local questsEmpty = Instance.new("TextLabel"); questsEmpty.Size = UDim2.new(1,-24,0,70); questsEmpty.Position = UDim2.new(0,12,0,46)
questsEmpty.BackgroundTransparency = 1; questsEmpty.Font = Enum.Font.Gotham; questsEmpty.TextSize = 14; questsEmpty.TextWrapped = true
questsEmpty.TextColor3 = Color3.fromRGB(200,220,255); questsEmpty.Text = "Land on islands to discover pet quests!"; questsEmpty.Visible = false; questsEmpty.Parent = questsOverlay

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared manager via _G) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local lp = Players.LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end)

local latestInv = { owned = {}, quests = {}, totalPets = 0 }

local function openPanel(open)
	open = open and true or false
	local okShow = pcall(function() panel.Visible = open; dim.Visible = open end)
	if not okShow then warn("[PetInv] ERROR opening: panel reference invalid"); return end
	local ok, err = pcall(function()
		if open then
			pcall(function() questsOverlay.Visible = false end)
			_G.MainMenuManager.notifyOpened("PetInv")
			local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
			print("[PetInv] inventory opened - owned: " .. nOwned)
			if _G.applyHudScaling then _G.applyHudScaling() end
		else
			_G.MainMenuManager.notifyClosed("PetInv")
			pcall(function() questsOverlay.Visible = false end)
		end
	end)
	if not ok then
		warn("[PetInv] ERROR opening/building: " .. tostring(err))
		pcall(function() if open then _G.MainMenuManager.current = "PetInv" else _G.MainMenuManager.notifyClosed("PetInv") end end)
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
dim.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then openPanel(false) end
end)
-- the ONE pet button toggles this panel via here (the HUD button below fires PetInvToggle)
local toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
toggleEvent.Event:Connect(function()
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
	openPanel(not isOpen)
end)

-- ===== 3D VIEWPORT ICONS (auto-rotating clone of the pet) =====
local iconSpins = {}
-- LITE icon: build the real body from the builder table; rare = subtle tint. (No accessory/level pipeline.)
local function buildIconModel(petId, level, isRare)
	local builder = PET_ICON_BUILDER[petId] or buildBroccoliBlob
	local model = builder(0.9)
	model.Name = petId .. "Icon"
	if not model.PrimaryPart then model.PrimaryPart = model:FindFirstChild("Root") end
	if isRare then -- rare variant: a light tint pass so it reads as special in the icon
		local _, tcol = petTier(level, true, petId)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Root" then
				d.Color = d.Color:Lerp(tcol, 0.35); d.Material = Enum.Material.Neon
			end
		end
	end
	petAnims[model] = nil
	return model
end
local iconQueue = {}
local iconWorkerActive = false
local function startIconWorker()
	if iconWorkerActive then return end
	iconWorkerActive = true
	task.spawn(function()
		while true do
			local req = table.remove(iconQueue, 1)
			if not req then break end
			if req.vp.Parent then
				local ok, model = pcall(buildIconModel, req.petId, req.level, req.isRare)
				if ok and model and req.vp.Parent then
					local okFrame = pcall(function()
						model:PivotTo(CFrame.new())
						model.Parent = req.vp
						local cf, size = model:GetBoundingBox()
						local maxe = math.max(size.X, size.Y, size.Z, 1)
						local center = cf.Position
						local dir = Vector3.new(0.8, 0.5, 0.55).Unit
						req.cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center)
						iconSpins[#iconSpins+1] = { model = model, center = center }
					end)
					if okFrame then if req.ph then req.ph.Visible = false end
					else warn("[PetInv] icon frame failed for " .. tostring(req.petId)) end
				else
					if model then pcall(function() model:Destroy() end) end
					if not ok then warn("[PetInv] ERROR building icon for " .. tostring(req.petId) .. ": " .. tostring(model)) end
				end
			end
			task.wait()
		end
		iconWorkerActive = false
		if #iconQueue > 0 then startIconWorker() end
	end)
end
local function makeViewportIcon(card, petId, level, isRare, sizeU, posU, anchorV)
	local vp = Instance.new("ViewportFrame"); vp.Name = "Icon3D"
	vp.AnchorPoint = anchorV or Vector2.new(0.5,0); vp.Size = sizeU or UDim2.new(0,54,0,34); vp.Position = posU or UDim2.new(0.5,0,0,2)
	vp.BackgroundColor3 = Color3.fromRGB(12,34,78); vp.BackgroundTransparency = 0.15; vp.Parent = card
	uicorner(vp, 8)
	vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
	local ph = Instance.new("TextLabel"); ph.Name = "IconPlaceholder"; ph.Size = UDim2.new(1,0,1,0); ph.BackgroundTransparency = 1
	ph.Font = Enum.Font.FredokaOne; ph.TextScaled = true; ph.TextColor3 = Color3.fromRGB(150,180,235); ph.Text = "\xF0\x9F\x90\xBE"; ph.Parent = vp
	iconQueue[#iconQueue + 1] = { vp = vp, cam = cam, ph = ph, petId = petId, level = level, isRare = isRare }
	startIconWorker()
	return vp
end
do
	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		if not panel.Visible or #iconSpins == 0 then return end
		angle = (angle + dt * 0.6) % (2 * math.pi)
		for i = #iconSpins, 1, -1 do
			local ic = iconSpins[i]
			if ic.model and ic.model.Parent then
				ic.model:PivotTo(CFrame.new(ic.center) * CFrame.Angles(0, angle, 0) * CFrame.new(-ic.center))
			else table.remove(iconSpins, i) end
		end
	end)
end

-- one OWNED pet card (VERBATIM)
local function buildPetCard(key, p, order)
	local petId = p.petId or key
	local card = Instance.new("Frame"); card.Name = key; card.LayoutOrder = order
	card.BackgroundColor3 = p.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160); card.Parent = petsScroll
	uicorner(card, 12)
	local tierName, tierColor, isVariant = petTier(p.level, p.rare, petId)
	uistroke(card, isVariant and tierColor or (p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(10,40,100)), (isVariant or p.equipped) and 3 or 1)
	-- SCALE-sized picture (0.55 of the card = the same 140px on a 252px cell), so it keeps its share of the
	-- card instead of holding 140px and squeezing the text block off the bottom.
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(1,-12,0.55,0), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))

	-- ---- THE CARD BODY: ONE VERTICAL LIST, NO FIXED OFFSETS ----------------------------------------
	-- Same change as PetFollow.client.lua's copy of this card, for the same reason. These lines were hand
	-- placed at y = 150/170/188/208/236 against a card assumed to be exactly 252px tall, so the name, the
	-- level line, the XP bar, the buttons and the milestone stacked on top of each other the moment the
	-- card was any shorter. A UIListLayout cannot overlap: each row is placed after the one before it.
	--
	-- Sizes are SCALE and every label is TextScaled with a UITextSizeConstraint pinning its AUTHORED size
	-- as the MAXIMUM -- identical at full size, shrinking instead of spilling when the card is small.
	local body = Instance.new("Frame"); body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 8, 0.57, 2)
	body.Size = UDim2.new(1, -16, 0.43, -8)
	body.Parent = card
	do
		local bl = Instance.new("UIListLayout"); bl.FillDirection = Enum.FillDirection.Vertical
		bl.SortOrder = Enum.SortOrder.LayoutOrder; bl.Padding = UDim.new(0, 2); bl.Parent = body
	end
	local function fitText(o, maxSize)
		o.TextScaled = true
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
		return o
	end
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,0,0.17,0); nm.LayoutOrder = 1
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = p.rare and (p.rareName or p.displayName) or p.displayName; nm.Parent = body
	fitText(nm, 18)
	if isVariant then
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		local ts = Instance.new("UIStroke"); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end
	-- ---- RARITY PILL: the axis that never moves --------------------------------------------------------
	-- Sits BOTTOM-left of the picture, deliberately far from the age tag (top-right) and the xN count
	-- (top-left). Three badges that all look alike in one corner is how a player learns to read none of them.
	-- Common gets no pill at all: it is the default, and a badge on every single card stops being a signal.
	local rarityBand = p.rarity or PetRarity.DEFAULT
	if rarityBand ~= PetRarity.DEFAULT then
		local rc = PetRarity.Color[rarityBand] or Color3.fromRGB(200,200,200)
		local rp = Instance.new("TextLabel"); rp.Name = "RarityPill"
		rp.AutomaticSize = Enum.AutomaticSize.X; rp.Size = UDim2.new(0,0,0,17)
		rp.AnchorPoint = Vector2.new(0,1); rp.Position = UDim2.new(0,6,0.55,-4)
		rp.BackgroundColor3 = rc; rp.Font = Enum.Font.GothamBold; rp.TextSize = 11
		rp.TextColor3 = Color3.new(1,1,1); rp.Text = rarityBand:upper(); rp.Parent = card
		local rpad = Instance.new("UIPadding", rp); rpad.PaddingLeft = UDim.new(0,6); rpad.PaddingRight = UDim.new(0,6)
		uicorner(rp, 5)
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(0,0,0); rs.Thickness = 1; rs.Transparency = 0.35; rs.Parent = rp
	end

	if (p.count or 1) > 1 then
		local cnt = Instance.new("TextLabel"); cnt.AutomaticSize = Enum.AutomaticSize.X; cnt.Size = UDim2.new(0,0,0,18); cnt.Position = UDim2.new(0,6,0,8)
		cnt.BackgroundColor3 = Color3.fromRGB(255,170,40); cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 12; cnt.TextColor3 = Color3.new(1,1,1); cnt.Text = "x" .. (p.count or 1); cnt.Parent = card
		local cpad = Instance.new("UIPadding", cnt); cpad.PaddingLeft = UDim.new(0,5); cpad.PaddingRight = UDim.new(0,5)
		uicorner(cnt, 5)
		local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(0,0,0); cs.Thickness = 1; cs.Transparency = 0.2; cs.Parent = cnt
	end
	local cap = p.maxLevel or 25
	local maxed = (p.level >= cap)
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,0,0.15,0); lv.LayoutOrder = 2
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold
	lv.Text = (isVariant and tierName or (tierName .. "  Lv " .. p.level)) .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = body
	lv.TextColor3 = tierColor
	fitText(lv, 13)
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,0,0.14,0); barBG.LayoutOrder = 3
	barBG.BackgroundColor3 = Color3.fromRGB(12,40,90); barBG.BorderSizePixel = 0; barBG.Parent = body; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(8,26,64), 1)
	local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP")
	fitText(xpTxt, 10)
	-- EQUIP + SKIP share one row; the milestone line sits under them, in list order rather than at y=236
	local btnRow = Instance.new("Frame"); btnRow.Name = "Buttons"; btnRow.LayoutOrder = 4
	btnRow.BackgroundTransparency = 1; btnRow.Size = UDim2.new(1,0,0.26,0); btnRow.Parent = body
	do
		local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal
		rl.SortOrder = Enum.SortOrder.LayoutOrder; rl.Padding = UDim.new(0, 6)
		rl.VerticalAlignment = Enum.VerticalAlignment.Center; rl.Parent = btnRow
	end
	local ms = Instance.new("TextLabel"); ms.Size = UDim2.new(1,0,0.15,0); ms.LayoutOrder = 5
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextColor3 = Color3.fromRGB(185,212,255)
	ms.Text = "\xE2\x9C\xA8 " .. (p.milestone or ""); ms.Parent = body
	fitText(ms, 11)
	-- ---- FUSION SLOT ------------------------------------------------------------------------------------
	-- The button appears as soon as you hold a SECOND copy, not only once you can afford the fuse -- seeing
	-- "FUSE 2/5" is how a player finds out duplicates are worth keeping. Before that the row stays two
	-- buttons wide, so a card with nothing to fuse looks exactly as it always did.
	-- p.fuseCost is nil at Gold (top of the ladder): nothing to fuse into, so no slot at all.
	local dupes    = p.count or 1
	local showFuse = (p.fuseCost ~= nil) and dupes > 1
	local btnW     = showFuse and 0.32 or 0.49 -- three across, or the original two

	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(btnW,0,1,0); eq.LayoutOrder = 1
	eq.Font = Enum.Font.GothamBold; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = btnRow
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1); fitText(eq, 13)
	eq.MouseButton1Click:Connect(function()
		if PetEquipEvent then
			if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
			else pcall(function() PetEquipEvent:FireServer(key) end) end
		end
	end)
	-- 'Skip to Legendary R$599' is the longest string on the card, hence the tighter cap here
	if showFuse then
		local canFuse = p.canFuse == true
		local into    = p.fuseInto or "?"
		local fz = Instance.new("TextButton"); fz.Name = "Fuse"; fz.Size = UDim2.new(btnW,0,1,0); fz.LayoutOrder = 3
		fz.Font = Enum.Font.GothamBold; fz.TextColor3 = Color3.new(1,1,1); fz.Parent = btnRow
		uicorner(fz, 8); fitText(fz, 12)
		if canFuse then
			-- tinted with the band you are fusing INTO, so the button previews its own reward
			fz.BackgroundColor3 = PetRarity.Color[into] or Color3.fromRGB(180,90,235)
			fz.Text = "FUSE \xE2\x86\x92 " .. into
			uistroke(fz, Color3.new(1,1,1), 2)
			fz.MouseButton1Click:Connect(function()
				if PetFuseEvent then pcall(function() PetFuseEvent:FireServer(key) end) end
			end)
		else
			-- Not enough yet: show the goal, not a dead button. AutoButtonColor off so it does not
			-- flash like something that should work.
			fz.BackgroundColor3 = Color3.fromRGB(90,90,90); fz.AutoButtonColor = false
			fz.Text = string.format("FUSE %d/%d", dupes, p.fuseCost)
			uistroke(fz, Color3.new(0,0,0), 1)
		end
	end

	local sk = Instance.new("TextButton"); sk.Size = UDim2.new(btnW,0,1,0); sk.LayoutOrder = 2
	sk.Font = Enum.Font.GothamBold; sk.TextColor3 = Color3.new(1,1,1); sk.Parent = btnRow; uicorner(sk, 8); fitText(sk, 12)
	local skipStep = (p.level <= 5 and PET_SKIP_PRODUCTS[1]) or (p.level <= 10 and PET_SKIP_PRODUCTS[2])
		or (p.level <= 15 and PET_SKIP_PRODUCTS[3]) or (p.level <= 20 and PET_SKIP_PRODUCTS[4]) or nil
	if maxed or not skipStep then
		sk.Text = maxed and "MAX LEVEL" or "MAX TIER"; sk.BackgroundColor3 = Color3.fromRGB(90,90,90); sk.AutoButtonColor = false
	else
		sk.Text = "Skip to " .. skipStep.to .. "  R$" .. skipStep.price; sk.BackgroundColor3 = Color3.fromRGB(50,170,90)
		sk.MouseButton1Click:Connect(function()
			if PetPendingUpgrade then pcall(function() PetPendingUpgrade:FireServer(key) end) end
			task.wait(0.15)
			pcall(function() MarketplaceService:PromptProductPurchase(player, skipStep.id) end)
		end)
	end
end

local function buildLockedSlot(order)
	local slot = Instance.new("Frame"); slot.Name = "Locked"; slot.LayoutOrder = order; slot.BackgroundColor3 = Color3.fromRGB(14,46,104); slot.Parent = petsScroll
	uicorner(slot, 10); uistroke(slot, Color3.fromRGB(10,30,80), 1)
	local q = Instance.new("TextLabel"); q.Size = UDim2.new(1,0,1,-22); q.BackgroundTransparency = 1; q.Font = Enum.Font.GothamBold; q.TextSize = 46; q.TextColor3 = Color3.fromRGB(70,100,170); q.Text = "?"; q.Parent = slot
	local lk = Instance.new("TextLabel"); lk.Size = UDim2.new(1,-8,0,18); lk.Position = UDim2.new(0,4,1,-22); lk.BackgroundTransparency = 1; lk.Font = Enum.Font.Gotham; lk.TextSize = 12; lk.TextColor3 = Color3.fromRGB(130,160,220); lk.Text = "\xF0\x9F\x94\x92 Locked"; lk.Parent = slot
end

local function buildQuestEntry(q, order)
	local qf = Instance.new("Frame"); qf.Name = "Quest"; qf.LayoutOrder = order; qf.Size = UDim2.new(1,-4,0,92); qf.BackgroundColor3 = Color3.fromRGB(20,70,160); qf.Parent = questsScroll
	uicorner(qf, 8); uistroke(qf, Color3.fromRGB(10,40,100), 1)
	local qn = Instance.new("TextLabel"); qn.Size = UDim2.new(1,-10,0,18); qn.Position = UDim2.new(0,6,0,4)
	qn.BackgroundTransparency = 1; qn.Font = Enum.Font.GothamBold; qn.TextSize = 14; qn.TextColor3 = Color3.new(1,1,1); qn.TextXAlignment = Enum.TextXAlignment.Left; qn.Text = q.islandName or "?"; qn.Parent = qf
	local statusCol = (q.status == "done") and Color3.fromRGB(120,255,120) or (q.status == "inprogress") and Color3.fromRGB(255,205,90) or Color3.fromRGB(180,220,255)
	local statusTxt = (q.status == "done") and "Done \xE2\x9C\x94"
		or (q.status == "inprogress") and ("In Progress  "..(q.found or 0).."/"..(q.total or 0).." "..(q.unit or ""))
		or "Available"
	local qs = Instance.new("TextLabel"); qs.Size = UDim2.new(1,-10,0,14); qs.Position = UDim2.new(0,6,0,22)
	qs.BackgroundTransparency = 1; qs.Font = Enum.Font.GothamBold; qs.TextSize = 11; qs.TextColor3 = statusCol; qs.TextXAlignment = Enum.TextXAlignment.Left; qs.Text = statusTxt; qs.Parent = qf
	local qd = Instance.new("TextLabel"); qd.Size = UDim2.new(1,-12,0,46); qd.Position = UDim2.new(0,6,0,38)
	qd.BackgroundTransparency = 1; qd.Font = Enum.Font.Gotham; qd.TextSize = 11; qd.TextColor3 = Color3.fromRGB(205,222,255); qd.TextWrapped = true
	qd.TextXAlignment = Enum.TextXAlignment.Left; qd.TextYAlignment = Enum.TextYAlignment.Top; qd.Text = q.desc or ""; qd.Parent = qf
end

local function rebuildInventory(payload)
	local ok, err = pcall(function()
		latestInv = payload or { owned = {}, quests = {}, totalPets = 0 }
		local owned, quests = latestInv.owned or {}, latestInv.quests or {}
		table.clear(iconSpins)
		for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local ownedCount, order = 0, 0
		local rank = { Mythical = 7, Exotic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1 }
		local ids = {}
		for skey in pairs(owned) do ids[#ids + 1] = skey end
		table.sort(ids, function(a, b)
			local pa, pb = owned[a], owned[b]
			local ra = rank[petTier(pa.level or 1, pa.rare, pa.petId)] or 0
			local rb = rank[petTier(pb.level or 1, pb.rare, pb.petId)] or 0
			if ra ~= rb then return ra > rb end
			return (pa.level or 0) > (pb.level or 0)
		end)
		for _, skey in ipairs(ids) do
			ownedCount = ownedCount + 1; order = order + 1
			local okc, ec = pcall(buildPetCard, skey, owned[skey], order)
			if not okc then warn("[PetInv] card build failed for " .. tostring(skey) .. ": " .. tostring(ec)) end
		end
		if ownedCount == 0 then
			local em = Instance.new("Frame"); em.Name = "PetsEmpty"; em.Size = UDim2.new(1,-20,0,90); em.Position = UDim2.new(0,10,0,8); em.BackgroundTransparency = 1; em.Parent = petsScroll
			local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 20; lbl.TextWrapped = true; lbl.TextColor3 = Color3.fromRGB(190,210,255); lbl.Text = "No Pets Unlocked\nComplete pet quests on the islands to hatch your first pet!"; lbl.Parent = em
		end
		petsScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(ownedCount / 2) * 264 + 20)
		for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local qCount = 0
		for _, q in pairs(quests) do qCount = qCount + 1; pcall(buildQuestEntry, q, qCount) end
		questsEmpty.Visible = (qCount == 0)
		questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
	end)
	if not ok then warn("[PetInv] ERROR building inventory: " .. tostring(err)) end
end
if PetInventoryEvent then PetInventoryEvent.OnClientEvent:Connect(rebuildInventory) end

-- =====================================================================================================
-- TRADE UI (housed in the Pet Hub). The client sends INTENTS only; the server owns the trade. (VERBATIM)
-- =====================================================================================================
local tradeState = nil

local function makeOfferRow(parent, brief, order, onClick)
	local row = Instance.new(onClick and "TextButton" or "TextLabel"); row.Size = UDim2.new(1,-6,0,26); row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Text = ""; row.Parent = parent; uicorner(row, 6)
	if onClick then row.AutoButtonColor = true end
	local tname, tcol = petTier(brief.level, brief.rare, brief.petId)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-10,1,0); nm.Position = UDim2.new(0,6,0,0); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 12; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = tcol
	nm.Text = brief.name .. "  (" .. tname .. (brief.rare and "" or ("  Lv" .. tostring(brief.level))) .. ")"; nm.Parent = row
	if onClick then row.MouseButton1Click:Connect(onClick) end
	return row
end

local function makeOfferCard(parent, brief, order, onClick)
	local card = Instance.new(onClick and "TextButton" or "TextLabel")
	card.Size = UDim2.new(1,-6,0,76); card.LayoutOrder = order
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160)
	card.Text = ""; if onClick then card.AutoButtonColor = true end; card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare, brief.petId)
	uistroke(card, isVariant and tcol or Color3.fromRGB(10,40,100), isVariant and 2 or 1)
	makeViewportIcon(card, brief.petId, brief.level, brief.rare, UDim2.new(0,96,0,68), UDim2.new(0,4,0,4), Vector2.new(0,0))
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 14
	nm.TextColor3 = isVariant and tcol or Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Position = UDim2.new(0,108,0,8); nm.Size = UDim2.new(1,-114,0,20); nm.Text = brief.name; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12
	lv.TextColor3 = tcol; lv.TextXAlignment = Enum.TextXAlignment.Left
	lv.Position = UDim2.new(0,108,0,32); lv.Size = UDim2.new(1,-114,0,18)
	lv.Text = isVariant and tname or (tname .. "  Lv " .. tostring(brief.level)); lv.Parent = card
	if onClick then
		local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Font = Enum.Font.Gotham; h.TextSize = 11; h.TextColor3 = Color3.fromRGB(255,190,190)
		h.TextXAlignment = Enum.TextXAlignment.Left; h.Position = UDim2.new(0,108,0,52); h.Size = UDim2.new(1,-114,0,16); h.Text = "Click to remove \xE2\x9C\x95"; h.Parent = card
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

local tradeBtn = Instance.new("TextButton"); tradeBtn.Size = UDim2.new(0,96,0,34); tradeBtn.Position = UDim2.new(1,-150,0,13)
tradeBtn.BackgroundColor3 = Color3.fromRGB(80,160,255); tradeBtn.Font = Enum.Font.GothamBold; tradeBtn.TextSize = 14; tradeBtn.TextColor3 = Color3.new(1,1,1)
tradeBtn.Text = "\xF0\x9F\x94\x81 TRADE"; tradeBtn.Parent = header; uicorner(tradeBtn, 8); uistroke(tradeBtn, Color3.new(0,0,0), 2)

local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1,-24,1,-74); tradeOverlay.Position = UDim2.new(0,12,0,68)
tradeOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); tradeOverlay.Visible = false; tradeOverlay.Parent = panel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(10,40,100), 2)
local ovTitle = Instance.new("TextLabel"); ovTitle.Size = UDim2.new(1,-120,0,28); ovTitle.Position = UDim2.new(0,12,0,8); ovTitle.BackgroundTransparency = 1
ovTitle.Font = Enum.Font.GothamBold; ovTitle.TextSize = 18; ovTitle.TextColor3 = Color3.fromRGB(255,215,0); ovTitle.TextXAlignment = Enum.TextXAlignment.Left; ovTitle.Text = "Trade"; ovTitle.Parent = tradeOverlay
local ovBack = Instance.new("TextButton"); ovBack.Size = UDim2.new(0,100,0,28); ovBack.Position = UDim2.new(1,-108,0,8); ovBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
ovBack.Font = Enum.Font.GothamBold; ovBack.TextSize = 13; ovBack.TextColor3 = Color3.new(1,1,1); ovBack.Text = "\xE2\x97\x80 Pets"; ovBack.Parent = tradeOverlay; uicorner(ovBack, 8)

local pickerView = Instance.new("Frame"); pickerView.Size = UDim2.new(1,-16,1,-46); pickerView.Position = UDim2.new(0,8,0,42); pickerView.BackgroundTransparency = 1; pickerView.Parent = tradeOverlay
local pickerScroll = Instance.new("ScrollingFrame"); pickerScroll.Size = UDim2.new(1,0,1,0); pickerScroll.BackgroundTransparency = 1; pickerScroll.BorderSizePixel = 0
pickerScroll.ScrollBarThickness = 6; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); pickerScroll.CanvasSize = UDim2.new(0,0,0,0); pickerScroll.Parent = pickerView
local pickerLayout = Instance.new("UIListLayout"); pickerLayout.Padding = UDim.new(0,6); pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickerLayout.Parent = pickerScroll

local windowView = Instance.new("Frame"); windowView.Size = UDim2.new(1,-16,1,-46); windowView.Position = UDim2.new(0,8,0,42); windowView.BackgroundTransparency = 1; windowView.Visible = false; windowView.Parent = tradeOverlay
local function colTitle(text, x) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,310,0,18); l.Position = UDim2.new(0,x,0,0); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.TextColor3 = Color3.fromRGB(255,215,0); l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.Parent = windowView; return l end
local function colScroll(x, y, h) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0,310,0,h); s.Position = UDim2.new(0,x,0,y); s.BackgroundColor3 = Color3.fromRGB(12,44,104); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0,0,0,0); s.Parent = windowView; uicorner(s,8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end
colTitle("YOUR OFFER (click to remove)", 0)
local yourOfferScroll = colScroll(0, 20, 150)
local addTitleLbl = colTitle("YOUR PETS (click to add)", 0); addTitleLbl.Position = UDim2.new(0,0,0,176)
local addScroll = colScroll(0, 196, 200)
colTitle("THEIR OFFER", 330)
local theirOfferScroll = colScroll(330, 20, 150)
local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0,310,0,108); statusLbl.Position = UDim2.new(0,330,0,178); statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 14; statusLbl.TextColor3 = Color3.new(1,1,1); statusLbl.TextWrapped = true; statusLbl.TextYAlignment = Enum.TextYAlignment.Top; statusLbl.Text = ""; statusLbl.Parent = windowView
local cancelBtn = Instance.new("TextButton"); cancelBtn.Size = UDim2.new(0,150,0,34); cancelBtn.Position = UDim2.new(0,330,0,300); cancelBtn.BackgroundColor3 = Color3.fromRGB(220,60,60)
cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 15; cancelBtn.TextColor3 = Color3.new(1,1,1); cancelBtn.Text = "CANCEL"; cancelBtn.Parent = windowView; uicorner(cancelBtn,8); uistroke(cancelBtn, Color3.new(0,0,0),2)
local confirmBtn = Instance.new("TextButton"); confirmBtn.Size = UDim2.new(0,150,0,34); confirmBtn.Position = UDim2.new(0,490,0,300); confirmBtn.BackgroundColor3 = Color3.fromRGB(50,200,50)
confirmBtn.Font = Enum.Font.GothamBold; confirmBtn.TextSize = 15; confirmBtn.TextColor3 = Color3.new(1,1,1); confirmBtn.Text = "CONFIRM"; confirmBtn.Parent = windowView; uicorner(confirmBtn,8); uistroke(confirmBtn, Color3.new(0,0,0),2)

local function clearScroll(s) for _, c in ipairs(s:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end
local function refreshPicker()
	clearScroll(pickerScroll)
	local order, n = 0, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player then
			n = n + 1; order = order + 1
			local row = Instance.new("Frame"); row.Size = UDim2.new(1,-6,0,30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Parent = pickerScroll; uicorner(row,6)
			local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-94,1,0); nm.Position = UDim2.new(0,8,0,0); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextColor3 = Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"; nm.Parent = row
			local req = Instance.new("TextButton"); req.Size = UDim2.new(0,82,0,24); req.Position = UDim2.new(1,-86,0,3); req.BackgroundColor3 = Color3.fromRGB(50,200,50); req.Font = Enum.Font.GothamBold; req.TextSize = 12; req.TextColor3 = Color3.new(1,1,1); req.Text = "REQUEST"; req.Parent = row; uicorner(req,6)
			local uid = pl.UserId
			req.MouseButton1Click:Connect(function() if PetTradeRequest then pcall(function() PetTradeRequest:FireServer(uid) end) end; ovTitle.Text = "Request sent to " .. pl.DisplayName .. "..." end)
		end
	end
	if n == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1,-6,0,40); e.BackgroundTransparency = 1; e.Font = Enum.Font.Gotham; e.TextSize = 13; e.TextColor3 = Color3.fromRGB(200,220,255); e.TextWrapped = true; e.Text = "No other players in the server to trade with."; e.Parent = pickerScroll
	end
	pickerScroll.CanvasSize = UDim2.new(0,0,0, n*36 + 8)
end
local function showPicker() pickerView.Visible = true; windowView.Visible = false; ovTitle.Text = "Trade \xE2\x80\x94 pick a player"; refreshPicker() end
local function renderTradeWindow(state)
	pickerView.Visible = false; windowView.Visible = true; ovTitle.Text = "Trading with " .. tostring(state.withName)
	clearScroll(yourOfferScroll); for i, b in ipairs(state.mine or {}) do makeOfferCard(yourOfferScroll, b, i, function() if PetTradeOffer then pcall(function() PetTradeOffer:FireServer(b.key or b.petId, false) end) end end) end
	yourOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.mine or {}) * 80 + 4)
	clearScroll(theirOfferScroll); for i, b in ipairs(state.theirs or {}) do makeOfferCard(theirOfferScroll, b, i, nil) end
	theirOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.theirs or {}) * 80 + 4)
	local offered = {}; for _, b in ipairs(state.mine or {}) do offered[b.key or b.petId] = true end
	clearScroll(addScroll); local idx = 0
	for skey, p in pairs(latestInv.owned or {}) do
		if not offered[skey] then idx = idx + 1
			local rowName = ((p.rare and p.rareName) or p.displayName) .. (((p.count or 1) > 1) and ("  x" .. p.count) or "")
			makeOfferRow(addScroll, { petId = p.petId, name = rowName, level = p.level, rare = p.rare }, idx, function() if PetTradeOffer then pcall(function() PetTradeOffer:FireServer(skey, true) end) end end)
		end
	end
	addScroll.CanvasSize = UDim2.new(0,0,0, idx * 30 + 4)
	local st = state.status
	statusLbl.Text = (st=="trading" and "\xE2\x9C\xA8 Both confirmed - trading!") or (st=="waiting_them" and ("You confirmed.\nWaiting for " .. state.withName .. "...")) or (st=="waiting_you" and (state.withName .. " confirmed.\nYour move!")) or "Add pets, then both CONFIRM.\n(changing an offer resets both confirms)"
	confirmBtn.Text = state.myConfirm and "\xE2\x9C\x94 CONFIRMED" or "CONFIRM"
	confirmBtn.BackgroundColor3 = state.myConfirm and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
end
ovBack.MouseButton1Click:Connect(function() tradeOverlay.Visible = false end)
cancelBtn.MouseButton1Click:Connect(function() if PetTradeCancel then pcall(function() PetTradeCancel:FireServer() end) end end)
confirmBtn.MouseButton1Click:Connect(function() if PetTradeConfirm then pcall(function() PetTradeConfirm:FireServer() end) end end)
tradeBtn.MouseButton1Click:Connect(function()
	questsOverlay.Visible = false
	if tradeState and tradeState.active then tradeOverlay.Visible = true; renderTradeWindow(tradeState)
	else tradeOverlay.Visible = not tradeOverlay.Visible; if tradeOverlay.Visible then showPicker() end end
end)

local questsBtn = Instance.new("TextButton"); questsBtn.Size = UDim2.new(0,96,0,34); questsBtn.Position = UDim2.new(1,-252,0,13)
questsBtn.BackgroundColor3 = Color3.fromRGB(120,170,60); questsBtn.Font = Enum.Font.GothamBold; questsBtn.TextSize = 14; questsBtn.TextColor3 = Color3.new(1,1,1)
questsBtn.Text = "\xF0\x9F\x97\xBA QUESTS"; questsBtn.Parent = header; uicorner(questsBtn, 8); uistroke(questsBtn, Color3.new(0,0,0), 2)
questsBtn.MouseButton1Click:Connect(function() tradeOverlay.Visible = false; questsOverlay.Visible = not questsOverlay.Visible end)
qoBack.MouseButton1Click:Connect(function() questsOverlay.Visible = false end)

if PetTradeState then PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		openPanel(true); tradeOverlay.Visible = true; renderTradeWindow(state)
	else
		local reason = state and state.reason
		print("[Trade] window closed (" .. tostring(reason) .. ")")
		tradeState = nil
		if tradeOverlay.Visible then ovTitle.Text = "Trade " .. (reason and ("\xE2\x80\x94 " .. reason) or "closed"); showPicker() end
	end
end) end

-- incoming-request popup (shows even if the Hub is closed)
local reqPopup = Instance.new("Frame"); reqPopup.Name = "TradeRequestPopup"; reqPopup.AnchorPoint = Vector2.new(0.5,0.5); reqPopup.Position = UDim2.new(0.5,0,0.4,0); reqPopup.Size = UDim2.new(0,320,0,130)
reqPopup.BackgroundColor3 = Color3.fromRGB(25,90,185); reqPopup.Visible = false; reqPopup.ZIndex = 50; reqPopup.Parent = invGui; uicorner(reqPopup, 12); uistroke(reqPopup, Color3.fromRGB(255,215,0), 3)
local reqLbl = Instance.new("TextLabel"); reqLbl.Size = UDim2.new(1,-20,0,60); reqLbl.Position = UDim2.new(0,10,0,10); reqLbl.BackgroundTransparency = 1; reqLbl.ZIndex = 51; reqLbl.Font = Enum.Font.GothamBold; reqLbl.TextSize = 16; reqLbl.TextColor3 = Color3.new(1,1,1); reqLbl.TextWrapped = true; reqLbl.Text = ""; reqLbl.Parent = reqPopup
local reqAccept = Instance.new("TextButton"); reqAccept.Size = UDim2.new(0,140,0,38); reqAccept.Position = UDim2.new(0,12,1,-46); reqAccept.BackgroundColor3 = Color3.fromRGB(50,200,50); reqAccept.ZIndex = 51; reqAccept.Font = Enum.Font.GothamBold; reqAccept.TextSize = 15; reqAccept.TextColor3 = Color3.new(1,1,1); reqAccept.Text = "ACCEPT"; reqAccept.Parent = reqPopup; uicorner(reqAccept,8)
local reqDecline = Instance.new("TextButton"); reqDecline.Size = UDim2.new(0,140,0,38); reqDecline.Position = UDim2.new(1,-152,1,-46); reqDecline.BackgroundColor3 = Color3.fromRGB(220,60,60); reqDecline.ZIndex = 51; reqDecline.Font = Enum.Font.GothamBold; reqDecline.TextSize = 15; reqDecline.TextColor3 = Color3.new(1,1,1); reqDecline.Text = "DECLINE"; reqDecline.Parent = reqPopup; uicorner(reqDecline,8)
reqAccept.MouseButton1Click:Connect(function() reqPopup.Visible = false; if PetTradeRespond then pcall(function() PetTradeRespond:FireServer(true) end) end end)
reqDecline.MouseButton1Click:Connect(function() reqPopup.Visible = false; if PetTradeRespond then pcall(function() PetTradeRespond:FireServer(false) end) end end)
if PetTradePrompt then PetTradePrompt.OnClientEvent:Connect(function(fromUserId, fromName)
	reqLbl.Text = "\xF0\x9F\x94\x81 " .. tostring(fromName) .. " wants to trade pets with you!"
	reqPopup.Visible = true
	task.delay(15, function() if reqPopup.Visible then reqPopup.Visible = false end end)
end) end

-- FLIGHT-ACHIEVEMENT progress (only if the server remote exists)
if PetProgressEvent then
	task.spawn(function()
		local TICK = 3
		while true do
			task.wait(TICK)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if _G.equippedPetId and hrp then
				local peak = math.max(hrp.Position.Y, _G.peakHeight or 0)
				pcall(function() PetProgressEvent:FireServer(_G.equippedPetId, peak, TICK) end)
			end
		end
	end)
end

-- ============================================================================
-- PETS HUD BUTTON -- the green paw button (matches CoreClient's repurposed
-- daily-rewards button: 80,170,70 fill / 40,110,40 stroke / rounded 16). It
-- fires the PetInvToggle BindableEvent, exactly like the in-game More+ menu.
--
-- ONLY WHEN THIS KIT IS RUNNING ALONE. In the real game the left rail is exactly
-- four buttons (SHOP / WORMHOLE / Stomach / MORE) and Pets is a row INSIDE the
-- MORE+ popup -- so this paw would be a fifth rail button landing between Stomach
-- and MORE. If CoreClient's SidebarGui exists, the real rail is already up and the
-- game already has a way into the Pet Hub, so the button is skipped and only the
-- Hub itself is built. Standalone (no SidebarGui) it appears as before, because
-- without it the kit has no way to open anything.
-- ============================================================================
local railExists = pg:FindFirstChild("SidebarGui") ~= nil
if railExists then
	print("[PetHub] SidebarGui present -> skipping the paw button (Pets lives in the MORE+ menu)")
end
local btnGui = Instance.new("ScreenGui"); btnGui.Name = "PetHubButton"; btnGui.ResetOnSpawn = false
btnGui.Enabled = not railExists
btnGui.Parent = pg
local petBtn = Instance.new("TextButton"); petBtn.Name = "PetsButton"; petBtn.Size = UDim2.new(0,70,0,70)
petBtn.Position = UDim2.new(0,20,0.5,40); petBtn.AnchorPoint = Vector2.new(0,0.5)
petBtn.BackgroundColor3 = Color3.fromRGB(80,170,70); petBtn.Font = Enum.Font.FredokaOne; petBtn.TextSize = 36
petBtn.TextColor3 = Color3.new(1,1,1); petBtn.Text = "\xF0\x9F\x90\xBE"; petBtn.Parent = btnGui
uicorner(petBtn, 16); uistroke(petBtn, Color3.fromRGB(40,110,40), 3)
local petLbl = Instance.new("TextLabel"); petLbl.Size = UDim2.new(1,0,0,16); petLbl.Position = UDim2.new(0,0,1,-16); petLbl.BackgroundTransparency = 1
petLbl.Font = Enum.Font.GothamBold; petLbl.TextSize = 12; petLbl.TextColor3 = Color3.new(1,1,1); petLbl.Text = "Pets"; petLbl.Parent = petBtn
uistroke(petLbl, Color3.new(0,0,0), 1)
petBtn.MouseButton1Click:Connect(function() toggleEvent:Fire() end)

-- ============================================================================
-- DEMO INVENTORY -- shown standalone so you can SEE the Hub populated. As soon
-- as the real server fires PetInventoryEvent, this is overwritten with live data.
-- ============================================================================
if not PetInventoryEvent then
	rebuildInventory({
		totalPets = 5,
		owned = {
			BroccoliPet  = { petId="BroccoliPet",  displayName="Broccoli Bunny", level=4,  xp=120, xpNeed=200, maxLevel=25, equipped=true,  milestone="Lv 5 -> Uncommon tier" },
			CoconutCrab  = { petId="CoconutCrab",  displayName="Coconut Crab",   level=12, xp=80,  xpNeed=300, maxLevel=25, milestone="Lv 15 -> Epic" },
			PopcornSheep = { petId="PopcornSheep", displayName="Popcorn Sheep",  level=22, xp=40,  xpNeed=400, maxLevel=25, count=2, milestone="Lv 25 -> MAX" },
			["ButterDuck#R"] = { petId="ButterDuck", displayName="Butter Duck", rareName="Cosmic Duck", rare=true, level=25, xp=0, xpNeed=0, maxLevel=25, milestone="Maxed Mythical" },
		},
		quests = {
			b = { islandName="Broccoli Bluff",  status="done",       desc="Find 3 hidden broccoli pieces, then hatch the egg." },
			c = { islandName="Coconut Cove",    status="inprogress", found=4, total=7, unit="coconuts", desc="Crack 7 coconuts to earn the Cave Key, open the chest." },
			p = { islandName="Popcorn Pinnacle",status="available",  desc="Find 6 film reels, load the projector, watch the show." },
		},
	})
	print("[PetHub] no server remotes found -> showing DEMO inventory. Click the paw button to open.")
end

print("[PetHub] ready -- paw button (bottom-left) toggles the Pet Hub")
