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
-- blinking eyes for the live 3D hub icon -- the game's EXACT Size.Y squash (animatePet / Eyes_AllInOne).
-- Stores each eye's ORIGINAL Size.Y once and multiplies from that base each frame (no compounding).
local function applyBlink(petModel)
	if not petModel then return end
	local eyes = {}
	for _, d in ipairs(petModel:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "whitepartofeye" or d.Name == "blackpartofeye" or d.Name == "Glint") then
			eyes[#eyes+1] = { part = d, baseX = d.Size.X, baseY = d.Size.Y, baseZ = d.Size.Z }
		end
	end
	if #eyes == 0 then return end
	local blink = 1.5
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not petModel.Parent then conn:Disconnect(); return end
		blink = blink - dt
		local eyeY = 1
		if blink <= 0 then
			local since = -blink
			if since < 0.16 then eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1))
			else blink = 1.8 + math.random() * 3.4 end
		end
		for _, e in ipairs(eyes) do
			if e.part.Parent then e.part.Size = Vector3.new(e.baseX, e.baseY * eyeY, e.baseZ) end
		end
	end)
	print("[PetHub] eye blink (Size.Y squash) started on hub icon (" .. #eyes .. " eye parts)")
end

-- The Stego icon is a CLONE of the single source of truth: ReplicatedStorage.StegosaurusTemplate
-- (published by Stegosaurus.server.luau). There is NO separate blob build, so the Hub icon can never
-- drift from the in-game pet. WaitForChild so it never silently falls back to something else.
local function buildStegoIcon(scale)
	local t = RS:FindFirstChild("StegosaurusTemplate") or RS:WaitForChild("StegosaurusTemplate", 10)
	if t then
		local c = t:Clone(); c.Name = "Stego"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Stego icon -> CLONED StegosaurusTemplate (%d parts)"):format(n))
		applyBlink(c)  -- live 3D viewport model -> blink it too
		return c
	end
	warn("[PetHub] StegosaurusTemplate missing -> generic placeholder (resync + replay Stegosaurus.server.luau)")
	return buildBroccoliBlob(scale)
end
-- The Velociraptor icon clones ReplicatedStorage.VelociraptorTemplate (mirrors the Stego icon exactly).
local function buildRaptorIcon(scale)
	local t = RS:FindFirstChild("VelociraptorTemplate") or RS:WaitForChild("VelociraptorTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Velociraptor"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Raptor icon -> CLONED VelociraptorTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	-- NO separate blob fallback -- the icon must be the template or nothing (an empty placeholder so it
	-- can never drift to a different model). Stop + Play republishes the template.
	warn("[PetHub] VelociraptorTemplate missing -> empty icon (resync + REPLAY Velociraptor.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Velociraptor"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
-- The Shark icon clones ReplicatedStorage.SharkTemplate (mirrors the Stego/Raptor icon exactly).
local function buildSharkIcon(scale)
	local t = RS:FindFirstChild("SharkTemplate") or RS:WaitForChild("SharkTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Shark"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Shark icon -> CLONED SharkTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] SharkTemplate missing -> empty icon (resync + REPLAY Shark.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Shark"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
-- The Triceratops icon clones ReplicatedStorage.TriceratopsTemplate (mirrors the Stego/Raptor/Shark icon exactly).
local function buildTriceratopsIcon(scale)
	local t = RS:FindFirstChild("TriceratopsTemplate") or RS:WaitForChild("TriceratopsTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Triceratops"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Triceratops icon -> CLONED TriceratopsTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] TriceratopsTemplate missing -> empty icon (resync + REPLAY Triceratops.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Triceratops"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
-- The Spinosaurus icon clones ReplicatedStorage.SpinosaurusTemplate (mirrors the others exactly).
local function buildSpinosaurusIcon(scale)
	local t = RS:FindFirstChild("SpinosaurusTemplate") or RS:WaitForChild("SpinosaurusTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Spinosaurus"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Spinosaurus icon -> CLONED SpinosaurusTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] SpinosaurusTemplate missing -> empty icon (resync + REPLAY Spinosaurus.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Spinosaurus"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
-- The T-Rex icon clones ReplicatedStorage.TyrannosaurusTemplate (mirrors the others exactly).
local function buildTyrannosaurusIcon(scale)
	local t = RS:FindFirstChild("TyrannosaurusTemplate") or RS:WaitForChild("TyrannosaurusTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Tyrannosaurus"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] T-Rex icon -> CLONED TyrannosaurusTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] TyrannosaurusTemplate missing -> empty icon (resync + REPLAY Tyrannosaurus.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Tyrannosaurus"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
local PET_ICON_BUILDER = {
	CoconutCrab = buildCoconutCrab, PopcornSheep = buildPopcornSheep, ButterDuck = buildButterDuck,
	BroccoliPet = buildBroccoliBlob, BurritoArmadillo = buildBroccoliBlob, -- (armadillo builder omitted; broccoli stand-in)
	Stego = buildStegoIcon, StegoPet = buildStegoIcon,
	Velociraptor = buildRaptorIcon, RaptorPet = buildRaptorIcon,
	Shark = buildSharkIcon, SharkPet = buildSharkIcon,
	Triceratops = buildTriceratopsIcon, TriceratopsPet = buildTriceratopsIcon,
	Spinosaurus = buildSpinosaurusIcon, SpinosaurusPet = buildSpinosaurusIcon,
	Tyrannosaurus = buildTyrannosaurusIcon, TyrannosaurusPet = buildTyrannosaurusIcon,
}

-- ============================================================================
-- PET HUB PANEL -- VERBATIM from PetFollow.client.lua (Pet Hub region).
-- ============================================================================
local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end
local function gloss(btn) local gl = Instance.new("Frame"); gl.AnchorPoint = Vector2.new(0.5,0); gl.Position = UDim2.new(0.5,0,0,3); gl.Size = UDim2.new(1,-10,0,9); gl.BackgroundColor3 = Color3.new(1,1,1); gl.BorderSizePixel = 0; gl.ZIndex = (btn.ZIndex or 1) + 1; gl.Parent = btn; uicorner(gl, 6); local gg = Instance.new("UIGradient"); gg.Rotation = 90; gg.Transparency = NumberSequence.new(0.45, 1); gg.Parent = gl end -- glossy top highlight

local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

-- ===== STONE SHELL: a chunky grey COBBLESTONE border framing the panel (behind it) =====
local STONE_A, STONE_B, STONE_D = Color3.fromRGB(224,204,150), Color3.fromRGB(202,178,118), Color3.fromRGB(148,116,66)
local shell = Instance.new("Frame"); shell.Name = "StoneShell"; shell.AnchorPoint = Vector2.new(0.5,0.5)
shell.Position = UDim2.new(0.5,0,0.5,-45); shell.Size = UDim2.fromOffset(740,560); shell.BackgroundColor3 = STONE_B
shell.Visible = false; shell.Parent = invGui; uicorner(shell, 26); uistroke(shell, STONE_D, 2)
do local sg = Instance.new("UIGradient"); sg.Rotation = 90; sg.Color = ColorSequence.new(STONE_A, Color3.fromRGB(184,158,100)); sg.Parent = shell end
local function rock(cx, cy, w, h) -- a BAMBOO/wood pole segment with a top sheen + darker binding bands
	local horiz = w > h
	local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Position = UDim2.fromOffset(cx, cy); r.Size = UDim2.fromOffset(w, h)
	r.BackgroundColor3 = STONE_B; r.BorderSizePixel = 0; r.Parent = shell
	uicorner(r, math.floor(math.min(w,h) * 0.46)); uistroke(r, STONE_D, 2)
	local g = Instance.new("UIGradient"); g.Rotation = horiz and 90 or 0; g.Color = ColorSequence.new(STONE_A, Color3.fromRGB(180,154,94)); g.Parent = r
	local hi = Instance.new("Frame"); hi.AnchorPoint = Vector2.new(0.5,0.5); hi.BackgroundColor3 = Color3.fromRGB(240,226,178); hi.BackgroundTransparency = 0.45; hi.BorderSizePixel = 0; hi.Parent = r
	if horiz then hi.Size = UDim2.new(1,-10,0,3); hi.Position = UDim2.new(0.5,0,0,4) else hi.Size = UDim2.new(0,3,1,-10); hi.Position = UDim2.new(0,4,0.5,0) end
	uicorner(hi, 2)
	for _, f in ipairs({ 0.3, 0.7 }) do -- binding marks wrapping the pole
		local bind = Instance.new("Frame"); bind.AnchorPoint = Vector2.new(0.5,0.5); bind.BackgroundColor3 = STONE_D; bind.BackgroundTransparency = 0.12; bind.BorderSizePixel = 0; bind.Parent = r
		if horiz then bind.Size = UDim2.fromOffset(5, h); bind.Position = UDim2.new(f, 0, 0.5, 0) else bind.Size = UDim2.fromOffset(w, 5); bind.Position = UDim2.new(0.5, 0, f, 0) end
		uicorner(bind, 2)
	end
end
for x = 20, 720, 43 do rock(x, 16, 52, 38); rock(x, 544, 52, 38) end          -- top + bottom poles
for y = 54, 506, 41 do rock(16, y, 38, 52); rock(724, y, 38, 52) end          -- left + right poles

-- ===== PANEL (green, on top of the stone shell) =====
local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5)
panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui
uicorner(panel, 16); uistroke(panel, Color3.fromRGB(40,52,38), 2)
do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(126,146,86)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(128,148,88)), ColorSequenceKeypoint.new(1, Color3.fromRGB(124,144,84)) }); g.Parent = panel end -- mossy: lighter centre
-- faint paw-print watermark (on the panel bg, under the content)
-- soft mossy radial glow (lighter centre, fades to the edges)
local glow = Instance.new("Frame"); glow.AnchorPoint = Vector2.new(0.5,0.5); glow.Position = UDim2.new(0.5,0,0.5,0); glow.Size = UDim2.fromOffset(620,500); glow.BackgroundColor3 = Color3.fromRGB(150,170,108); glow.BackgroundTransparency = 0.82; glow.BorderSizePixel = 0; glow.Parent = panel; uicorner(glow, 250)
do local glg = Instance.new("UIGradient"); glg.Rotation = 90; glg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(0.5,0), NumberSequenceKeypoint.new(1,1) }); glg.Parent = glow end
local pawWM = Instance.new("TextLabel"); pawWM.AnchorPoint = Vector2.new(0.5,0.5); pawWM.Position = UDim2.new(0.5,0,0.56,0); pawWM.Size = UDim2.fromOffset(310,310); pawWM.BackgroundTransparency = 1; pawWM.Font = Enum.Font.FredokaOne; pawWM.Text = "\xF0\x9F\x90\xBE"; pawWM.TextScaled = true; pawWM.TextColor3 = Color3.fromRGB(30,62,34); pawWM.TextTransparency = 0.72; pawWM.Parent = panel
panel:GetPropertyChangedSignal("Visible"):Connect(function() shell.Visible = panel.Visible end) -- shell shows/hides with the panel

-- ===== real trailing leafy VINES: thin curving stems with pointed leaf blades sprouting off =====
local VGREENS = { Color3.fromRGB(112,192,98), Color3.fromRGB(70,142,64), Color3.fromRGB(48,108,50) }
local function leaf(px, py, len, rot, ci) -- a pointed leaf BLADE (elongated) with shadow + center vein
	local w = math.max(8, math.floor(len * 0.42))
	local sh = Instance.new("Frame"); sh.AnchorPoint = Vector2.new(0.5,0.5); sh.Position = UDim2.new(0.5, px+2, 0.5, py+3); sh.Size = UDim2.fromOffset(w, len); sh.Rotation = rot; sh.BackgroundColor3 = Color3.new(0,0,0); sh.BackgroundTransparency = 0.62; sh.BorderSizePixel = 0; sh.ZIndex = 11; sh.Parent = shell; uicorner(sh, math.floor(w/2))
	local lf = Instance.new("Frame"); lf.AnchorPoint = Vector2.new(0.5,0.5); lf.Position = UDim2.new(0.5, px, 0.5, py); lf.Size = UDim2.fromOffset(w, len); lf.Rotation = rot; lf.BackgroundColor3 = VGREENS[ci]; lf.BorderSizePixel = 0; lf.ZIndex = 12; lf.Parent = shell; uicorner(lf, math.floor(w/2)); uistroke(lf, Color3.fromRGB(30,72,32), 1)
	local lg = Instance.new("UIGradient"); lg.Rotation = 90; lg.Color = ColorSequence.new(VGREENS[ci], Color3.fromRGB(34,84,38)); lg.Parent = lf
	local vein = Instance.new("Frame"); vein.AnchorPoint = Vector2.new(0.5,0.5); vein.Position = UDim2.new(0.5,0,0.5,0); vein.Size = UDim2.fromOffset(2, len-8); vein.BackgroundColor3 = Color3.fromRGB(38,88,40); vein.BackgroundTransparency = 0.25; vein.BorderSizePixel = 0; vein.ZIndex = 13; vein.Parent = lf; uicorner(vein, 1)
end
local VINE = Color3.fromRGB(96,86,48) -- olive-brown vine strand
local function stemDot(x, y, w, h) -- a short segment; many overlap into a continuous visible vine
	local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Position = UDim2.new(0.5, x, 0.5, y); s.Size = UDim2.fromOffset(w, h); s.BackgroundColor3 = VINE; s.BorderSizePixel = 0; s.ZIndex = 10; s.Parent = shell; uicorner(s, math.floor(math.min(w,h)/2))
end
-- a leaf GROWING from the vine: a short petiole off the strand point + the leaf blade at its tip
local function sprig(bx, by, ang, len, ci)
	local r = math.rad(ang); local dx, dy = math.sin(r), -math.cos(r) -- ang 0 = up
	local plen = math.max(6, math.floor(len * 0.34))
	local pe = Instance.new("Frame"); pe.AnchorPoint = Vector2.new(0.5,0.5); pe.Position = UDim2.new(0.5, bx + dx*plen*0.5, 0.5, by + dy*plen*0.5); pe.Size = UDim2.fromOffset(3, plen); pe.Rotation = ang; pe.BackgroundColor3 = VINE; pe.BorderSizePixel = 0; pe.ZIndex = 11; pe.Parent = shell; uicorner(pe, 1)
	leaf(bx + dx*(plen + len*0.45), by + dy*(plen + len*0.45), len, ang, ci)
end
-- a continuous curving vine with occasional leaves sprouting off, alternating sides
local function strand(horizontal, fixed, a, b, n)
	for s = 0, n*5 do
		local t = s/(n*5); local pos = a + (b-a)*t; local wob = math.sin(t*math.pi*3)*5
		local X = (horizontal and pos or (fixed+wob)) - 370
		local Y = (horizontal and (fixed+wob) or pos) - 280
		stemDot(X, Y, horizontal and 13 or 6, horizontal and 6 or 13)
	end
	for k = 1, n do
		local t = (k-0.5)/n; local pos = a + (b-a)*t; local wob = math.sin(t*math.pi*3)*5
		local side = (k % 2 == 0) and 1 or -1
		local len = 22 + (k % 3)*6
		local jit = (k % 3 - 1)*9
		local X = (horizontal and pos or (fixed+wob)) - 370
		local Y = (horizontal and (fixed+wob) or pos) - 280
		local ang = horizontal and ((side < 0) and (-12+jit) or (168+jit)) or ((side < 0) and (-90+jit) or (90+jit))
		sprig(X, Y, ang, len, (k % 3) + 1)
	end
end
-- only a couple of small leaf sprigs along each edge (the corners carry the leafy clusters)
sprig(-80, -266, 176, 24, 1); sprig(80, -266, 186, 22, 2)   -- top
sprig(-80, 266, 4, 24, 2); sprig(80, 266, -6, 22, 1)        -- bottom
sprig(-356, -50, 92, 22, 1); sprig(-356, 60, 88, 24, 3)     -- left
sprig(356, -50, 268, 22, 2); sprig(356, 60, 272, 24, 1)     -- right
-- a leafy bunch at each corner: a vine knot with leaves fanning between the two edge directions
local function corner(cxp, cyp, a0, a1)
	local bx, by = cxp - 370, cyp - 280
	stemDot(bx, by, 14, 14)
	for i = 0, 4 do
		sprig(bx, by, a0 + (a1-a0)*(i/4), 26 + (i % 2)*6, (i % 3) + 1)
	end
end
corner(16, 16, 95, 175); corner(724, 16, 185, 265); corner(16, 544, 5, 85); corner(724, 544, 275, 355)

-- HEADER
local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,60); header.BackgroundColor3 = Color3.fromRGB(26,48,30); header.Parent = panel
uicorner(header, 18); uistroke(header, Color3.fromRGB(74,94,68), 2)
do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(42,70,46)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30,54,34)), ColorSequenceKeypoint.new(1, Color3.fromRGB(22,40,26)) }); g.Parent = header end
-- thin carved highlight line just inside the top edge (so it reads as carved, not flat)
local hHi = Instance.new("Frame"); hHi.Size = UDim2.new(1,-20,0,2); hHi.Position = UDim2.new(0,10,0,4); hHi.BackgroundColor3 = Color3.fromRGB(120,170,110); hHi.BackgroundTransparency = 0.45; hHi.BorderSizePixel = 0; hHi.ZIndex = 2; hHi.Parent = header; uicorner(hHi, 2)
-- faint highlight just inside the banner border (carved / raised look)
do local hInset = Instance.new("Frame"); hInset.Size = UDim2.new(1,-8,1,-8); hInset.Position = UDim2.new(0,4,0,4); hInset.BackgroundTransparency = 1; hInset.ZIndex = 2; hInset.Parent = header; uicorner(hInset, 14); local his = uistroke(hInset, Color3.fromRGB(130,180,120), 1); his.Transparency = 0.55 end
-- dino-skull icon + wooden PLAQUE banner for the title
local skull = Instance.new("TextLabel"); skull.BackgroundTransparency = 1; skull.Font = Enum.Font.FredokaOne; skull.TextSize = 30; skull.ZIndex = 3; skull.Text = "\xF0\x9F\xA6\x96"; skull.Size = UDim2.new(0,34,0,38); skull.Position = UDim2.new(0,12,0,8); skull.Parent = header
for _, sl in ipairs({ {3,-3,11,-28}, {-3,7,9,28}, {21,5,8,58} }) do local le = Instance.new("Frame"); le.AnchorPoint = Vector2.new(0.5,0.5); le.Position = UDim2.new(0,12+sl[1],0,20+sl[2]); le.Size = UDim2.fromOffset(sl[3], math.floor(sl[3]*1.7)); le.BackgroundColor3 = Color3.fromRGB(72,144,66); le.BorderSizePixel = 0; le.Rotation = sl[4]; le.ZIndex = 1; le.Parent = header; uicorner(le, math.floor(sl[3]/2)); uistroke(le, Color3.fromRGB(34,84,38), 1) end
local plaque = Instance.new("Frame"); plaque.Size = UDim2.new(0,212,0,34); plaque.Position = UDim2.new(0,50,0,7); plaque.BackgroundColor3 = Color3.fromRGB(126,84,48); plaque.BorderSizePixel = 0; plaque.ZIndex = 2; plaque.Parent = header
uicorner(plaque, 8); uistroke(plaque, Color3.fromRGB(74,46,24), 2)
do local pgr = Instance.new("UIGradient"); pgr.Rotation = 90; pgr.Color = ColorSequence.new(Color3.fromRGB(152,106,62), Color3.fromRGB(108,70,38)); pgr.Parent = plaque end
do local seam = Instance.new("Frame"); seam.Size = UDim2.new(1,-14,0,2); seam.Position = UDim2.new(0,7,0.5,-1); seam.BackgroundColor3 = Color3.fromRGB(92,58,30); seam.BackgroundTransparency = 0.45; seam.BorderSizePixel = 0; seam.ZIndex = 2; seam.Parent = plaque end
for _, np in ipairs({ {0,0,7,7}, {1,0,-7,7}, {0,1,7,-7}, {1,1,-7,-7} }) do local nail = Instance.new("Frame"); nail.AnchorPoint = Vector2.new(0.5,0.5); nail.Position = UDim2.new(np[1],np[3],np[2],np[4]); nail.Size = UDim2.fromOffset(5,5); nail.BackgroundColor3 = Color3.fromRGB(70,44,22); nail.BorderSizePixel = 0; nail.ZIndex = 3; nail.Parent = plaque; uicorner(nail, 99) end
do local sheen = Instance.new("Frame"); sheen.AnchorPoint = Vector2.new(0.5,0); sheen.Position = UDim2.new(0.5,0,0,3); sheen.Size = UDim2.new(1,-16,0,5); sheen.BackgroundColor3 = Color3.fromRGB(198,152,100); sheen.BackgroundTransparency = 0.4; sheen.BorderSizePixel = 0; sheen.ZIndex = 2; sheen.Parent = plaque; uicorner(sheen, 3) end
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextSize = 26; title.ZIndex = 3
title.TextColor3 = Color3.fromRGB(250,242,214); title.Text = "PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Center
title.Size = UDim2.new(0,212,0,34); title.Position = UDim2.new(0,50,0,7); title.Parent = header
uistroke(title, Color3.fromRGB(60,38,18), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(245,236,208); subtitle.Text = "Your pets & quest progress"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(0,260,0,16); subtitle.Position = UDim2.new(0,50,0,43); subtitle.Parent = header
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2); gloss(closeBtn)

-- PETS section (fills the panel width: 2 big cards/row)
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-74); sec.Position = UDim2.new(0,x,0,68)
	sec.BackgroundColor3 = Color3.fromRGB(124,144,86); sec.BackgroundTransparency = 0.45; sec.Parent = panel
	uicorner(sec, 12); uistroke(sec, Color3.fromRGB(98,118,70), 2)
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
questsOverlay.BackgroundColor3 = Color3.fromRGB(28,50,30); questsOverlay.Visible = false; questsOverlay.Parent = panel; uicorner(questsOverlay, 12); uistroke(questsOverlay, Color3.fromRGB(40,46,36), 2)
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
						if req.petId == "SharkPet" or req.petId == "Shark" then
							local pv = model:GetPivot()
							print(("[PetHub][ORIENT] hub shark: model at IDENTITY pivotUp=(%.2f,%.2f,%.2f) -> +Y dorsal UP, +X face toward the front-upper-right camera dir=(0.80,0.50,0.55)"):format(pv.UpVector.X, pv.UpVector.Y, pv.UpVector.Z))
						end
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
	vp.BackgroundColor3 = Color3.fromRGB(16,38,20); vp.BackgroundTransparency = 0.15; vp.Parent = card
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
	card.BackgroundColor3 = p.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(34,74,40); card.Parent = petsScroll
	uicorner(card, 12)
	local tierName, tierColor, isVariant = petTier(p.level, p.rare, petId)
	uistroke(card, isVariant and tierColor or (p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(40,46,36)), (isVariant or p.equipped) and 3 or 1)
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = p.rare and (p.rareName or p.displayName) or p.displayName; nm.Parent = card
	if isVariant then
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		local ts = Instance.new("UIStroke"); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
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
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-16,0,16); lv.Position = UDim2.new(0,8,0,170)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13
	lv.Text = (isVariant and tierName or (tierName .. "  Lv " .. p.level)) .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = card
	lv.TextColor3 = tierColor
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-16,0,14); barBG.Position = UDim2.new(0,8,0,188)
	barBG.BackgroundColor3 = Color3.fromRGB(16,38,20); barBG.BorderSizePixel = 0; barBG.Parent = card; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(10,28,14), 1)
	local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextSize = 10; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP")
	local ms = Instance.new("TextLabel"); ms.Size = UDim2.new(1,-16,0,14); ms.Position = UDim2.new(0,8,0,236)
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextSize = 11; ms.TextColor3 = Color3.fromRGB(185,212,255)
	ms.Text = "\xE2\x9C\xA8 " .. (p.milestone or ""); ms.Parent = card
	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(0,149,0,26); eq.Position = UDim2.new(0,8,0,208)
	eq.Font = Enum.Font.GothamBold; eq.TextSize = 13; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = card
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1)
	eq.MouseButton1Click:Connect(function()
		if PetEquipEvent then
			if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
			else pcall(function() PetEquipEvent:FireServer(key) end) end
		end
	end)
	local sk = Instance.new("TextButton"); sk.Size = UDim2.new(0,149,0,26); sk.Position = UDim2.new(0,165,0,208)
	sk.Font = Enum.Font.GothamBold; sk.TextSize = 12; sk.TextColor3 = Color3.new(1,1,1); sk.Parent = card; uicorner(sk, 8)
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
	local slot = Instance.new("Frame"); slot.Name = "Locked"; slot.LayoutOrder = order; slot.BackgroundColor3 = Color3.fromRGB(24,46,28); slot.Parent = petsScroll
	uicorner(slot, 10); uistroke(slot, Color3.fromRGB(18,38,22), 1)
	local q = Instance.new("TextLabel"); q.Size = UDim2.new(1,0,1,-22); q.BackgroundTransparency = 1; q.Font = Enum.Font.GothamBold; q.TextSize = 46; q.TextColor3 = Color3.fromRGB(70,100,170); q.Text = "?"; q.Parent = slot
	local lk = Instance.new("TextLabel"); lk.Size = UDim2.new(1,-8,0,18); lk.Position = UDim2.new(0,4,1,-22); lk.BackgroundTransparency = 1; lk.Font = Enum.Font.Gotham; lk.TextSize = 12; lk.TextColor3 = Color3.fromRGB(130,160,220); lk.Text = "\xF0\x9F\x94\x92 Locked"; lk.Parent = slot
end

local function buildQuestEntry(q, order)
	local qf = Instance.new("Frame"); qf.Name = "Quest"; qf.LayoutOrder = order; qf.Size = UDim2.new(1,-4,0,92); qf.BackgroundColor3 = Color3.fromRGB(34,74,40); qf.Parent = questsScroll
	uicorner(qf, 8); uistroke(qf, Color3.fromRGB(40,46,36), 1)
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
			local _pe = petsSection:FindFirstChild("PetsEmpty"); if _pe then _pe:Destroy() end -- empty state lives on the section (not the gridded scroll)
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
			-- ===== styled EMPTY STATE: paw watermark + heading + subtitle + egg-in-twig-nest =====
			local em = Instance.new("Frame"); em.Name = "PetsEmpty"; em.Size = UDim2.new(1,-16,1,-40); em.Position = UDim2.new(0,8,0,34); em.BackgroundTransparency = 1; em.ZIndex = 2; em.Parent = petsSection
			local function pawPrint(sx, sy, scale, rot, transp)
				local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Position = UDim2.new(sx,0,sy,0); c.Size = UDim2.fromOffset(scale, scale); c.BackgroundTransparency = 1; c.Rotation = rot; c.ZIndex = 1; c.Parent = em
				local BR = Color3.fromRGB(80,55,35) -- clear dark brown paw-print
				local pad = Instance.new("Frame"); pad.AnchorPoint = Vector2.new(0.5,0.5); pad.Position = UDim2.new(0.5,0,0.64,0); pad.Size = UDim2.new(0.52,0,0.42,0); pad.BackgroundColor3 = BR; pad.BackgroundTransparency = transp; pad.BorderSizePixel = 0; pad.ZIndex = 1; pad.Parent = c; uicorner(pad, 999)
				for _, tt in ipairs({ {0.3,0.26,0.2}, {0.46,0.13,0.22}, {0.64,0.18,0.2}, {0.8,0.36,0.16} }) do
					local toe = Instance.new("Frame"); toe.AnchorPoint = Vector2.new(0.5,0.5); toe.Position = UDim2.new(tt[1],0,tt[2],0); toe.Size = UDim2.new(tt[3],0,tt[3],0); toe.BackgroundColor3 = BR; toe.BackgroundTransparency = transp; toe.BorderSizePixel = 0; toe.ZIndex = 1; toe.Parent = c; uicorner(toe, 999)
				end
			end
			-- a clean dark-brown paw-print trail (tasteful watermark)
			pawPrint(0.42, 0.66, 96, -16, 0.42); pawPrint(0.50, 0.53, 104, 8, 0.4); pawPrint(0.58, 0.40, 90, -10, 0.46)
				-- (rising paw-trail removed; single centred watermark above)
			local h = Instance.new("TextLabel"); h.AnchorPoint = Vector2.new(0.5,0); h.Position = UDim2.new(0.5,0,0,22); h.Size = UDim2.new(1,-24,0,44); h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.TextScaled = true; h.Text = "No Pets Unlocked!"; h.TextColor3 = Color3.new(1,1,1); h.TextStrokeColor3 = Color3.fromRGB(18,38,20); h.TextStrokeTransparency = 0; h.ZIndex = 3; h.Parent = em
			do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 32; c.Parent = h end
			local s = Instance.new("TextLabel"); s.AnchorPoint = Vector2.new(0.5,0); s.Position = UDim2.new(0.5,0,0,70); s.Size = UDim2.new(1,-20,0,28); s.BackgroundTransparency = 1; s.Font = Enum.Font.FredokaOne; s.TextWrapped = false; s.TextSize = 15; s.Text = "Complete pet quests on the islands to hatch your first pet!"; s.TextColor3 = Color3.fromRGB(247,238,212); s.TextStrokeColor3 = Color3.fromRGB(18,38,20); s.TextStrokeTransparency = 0.4; s.ZIndex = 3; s.Parent = em
			-- (egg + twig nest removed from the empty state)
		end
		petsScroll.CanvasSize = UDim2.new(0,0,0, ownedCount == 0 and 0 or (math.ceil(ownedCount / 2) * 264 + 20))
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
	row.BackgroundColor3 = Color3.fromRGB(34,74,40); row.Text = ""; row.Parent = parent; uicorner(row, 6)
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
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(34,74,40)
	card.Text = ""; if onClick then card.AutoButtonColor = true end; card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare, brief.petId)
	uistroke(card, isVariant and tcol or Color3.fromRGB(40,46,36), isVariant and 2 or 1)
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
tradeBtn.BackgroundColor3 = Color3.fromRGB(48,110,210); tradeBtn.Font = Enum.Font.FredokaOne; tradeBtn.TextSize = 15; tradeBtn.TextColor3 = Color3.new(1,1,1)
tradeBtn.Text = "\xF0\x9F\x94\x81 TRADE"; tradeBtn.Parent = header; uicorner(tradeBtn, 8); uistroke(tradeBtn, Color3.new(0,0,0), 2); gloss(tradeBtn)

local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1,-24,1,-74); tradeOverlay.Position = UDim2.new(0,12,0,68)
tradeOverlay.BackgroundColor3 = Color3.fromRGB(28,50,30); tradeOverlay.Visible = false; tradeOverlay.Parent = panel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(40,46,36), 2)
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
local function colScroll(x, y, h) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0,310,0,h); s.Position = UDim2.new(0,x,0,y); s.BackgroundColor3 = Color3.fromRGB(16,38,20); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0,0,0,0); s.Parent = windowView; uicorner(s,8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end
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
			local row = Instance.new("Frame"); row.Size = UDim2.new(1,-6,0,30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(34,74,40); row.Parent = pickerScroll; uicorner(row,6)
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
questsBtn.BackgroundColor3 = Color3.fromRGB(74,150,58); questsBtn.Font = Enum.Font.FredokaOne; questsBtn.TextSize = 15; questsBtn.TextColor3 = Color3.new(1,1,1)
questsBtn.Text = "\xF0\x9F\x97\xBA QUESTS"; questsBtn.Parent = header; uicorner(questsBtn, 8); uistroke(questsBtn, Color3.new(0,0,0), 2); gloss(questsBtn)
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
-- NO HUD BUTTON HERE -- the existing styled "Pets" side button (in
-- Bootstrap.client.luau) fires the PetInvToggle BindableEvent created above to
-- open/close this Hub, so we don't add a second button.
-- ============================================================================

-- ============================================================================
-- DEMO INVENTORY -- shown standalone so you can SEE the Hub populated. As soon
-- as the real server fires PetInventoryEvent, this is overwritten with live data.
-- ============================================================================
-- ============================================================================
-- CLIENT-SIDE INVENTORY -- no pet server here, so the Hub starts EMPTY and
-- hatched pets are added via _G.PetHubAddPet (called from QuestGate on hatch).
-- If a real PetInventoryEvent ever fires, live server data takes over instead.
-- ============================================================================
local clientOwned = {}
local function refreshClientInv() rebuildInventory({ totalPets = 0, owned = clientOwned, quests = {} }) end
_G.PetHubAddPet = function(key, data)
	if not key or not data then return end
	clientOwned[key] = data
	if not PetInventoryEvent then refreshClientInv() end
end
if not PetInventoryEvent then refreshClientInv() end

print("[PetHub] ready -- paw button (bottom-left) toggles the Pet Hub")
