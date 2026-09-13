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
-- Forward reference to the Hub panel, built further down. The blink loops below start
-- before it exists, and they use it to idle themselves while the Hub is closed.
local hubPanel = nil
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
		-- One of these runs per dino icon, so idle them while the Hub is shut (it is, most
		-- of the time) -- an off-screen blink is pure cost. `hubPanel` is set once the panel
		-- exists; before that (icons can't be visible yet) we simply skip.
		if not (hubPanel and hubPanel.Visible) then return end
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
-- The Therizinosaurus icon clones ReplicatedStorage.TherizinosaurusTemplate (mirrors the others exactly).
local function buildTherizinosaurusIcon(scale)
	local t = RS:FindFirstChild("TherizinosaurusTemplate") or RS:WaitForChild("TherizinosaurusTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Therizinosaurus"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Therizinosaurus icon -> CLONED TherizinosaurusTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] TherizinosaurusTemplate missing -> empty icon (resync + REPLAY Therizinosaurus.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Therizinosaurus"
	local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
	return ph
end
-- The Brachiosaurus icon clones ReplicatedStorage.BrachiosaurusTemplate (mirrors the others exactly).
local function buildBrachiosaurusIcon(scale)
	local t = RS:FindFirstChild("BrachiosaurusTemplate") or RS:WaitForChild("BrachiosaurusTemplate", 20)
	if t then
		local c = t:Clone(); c.Name = "Brachiosaurus"; petAnims[c] = nil
		local n = 0; for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
		print(("[PetHub] Brachiosaurus icon -> CLONED BrachiosaurusTemplate (%d parts)"):format(n))
		applyBlink(c)
		return c
	end
	warn("[PetHub] BrachiosaurusTemplate missing -> empty icon (resync + REPLAY Brachiosaurus.server.luau)")
	local ph = Instance.new("Model"); ph.Name = "Brachiosaurus"
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
	Therizinosaurus = buildTherizinosaurusIcon, TherizinosaurusPet = buildTherizinosaurusIcon,
	Brachiosaurus = buildBrachiosaurusIcon, BrachiosaurusPet = buildBrachiosaurusIcon,
}

-- ============================================================================
-- FOOD REALM pet icons -- clone the EXACT fused templates the food realm builds
-- (published into ReplicatedStorage by FoodPetTemplates.server.luau, verbatim from
-- Fart to Float's PetSystem.server.lua). Same single-source-of-truth pattern as the
-- Stego/Raptor/... icons above, so the FOOD tab shows the real renders, not the
-- old low-poly stand-ins. Falls back to the legacy handmade builder where one
-- exists, else an empty placeholder (the viewport keeps its emoji).
-- ============================================================================
local function foodTemplateIcon(templateName, fallbackBuilder)
	return function(scale)
		local t = RS:FindFirstChild(templateName) or RS:WaitForChild(templateName, 20)
		if t then
			local c = t:Clone(); petAnims[c] = nil
			return c
		end
		warn("[PetHub] " .. templateName .. " missing -> fallback icon (sync FoodPetTemplates.server.luau + replay)")
		if fallbackBuilder then return fallbackBuilder(scale) end
		local ph = Instance.new("Model"); ph.Name = templateName
		local r = Instance.new("Part"); r.Name = "Root"; r.Size = Vector3.new(0.4,0.4,0.4); r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.Parent = ph; ph.PrimaryPart = r
		return ph
	end
end
PET_ICON_BUILDER.BeanBuddy        = foodTemplateIcon("BeanBuddyTemplate")
PET_ICON_BUILDER.PizzaDragon      = foodTemplateIcon("PizzaDragonTemplate")
PET_ICON_BUILDER.BroccoliPet      = foodTemplateIcon("BroccoliBunnyTemplate",   buildBroccoliBlob) -- note: template is named after the DISPLAY name
PET_ICON_BUILDER.CoconutCrab      = foodTemplateIcon("CoconutCrabTemplate",     buildCoconutCrab)
PET_ICON_BUILDER.PopcornSheep     = foodTemplateIcon("PopcornSheepTemplate",    buildPopcornSheep)
PET_ICON_BUILDER.ButterDuck       = foodTemplateIcon("ButterDuckTemplate",      buildButterDuck)
PET_ICON_BUILDER.BurritoArmadillo = foodTemplateIcon("BurritoArmadilloTemplate")
PET_ICON_BUILDER.SunflowerBee     = foodTemplateIcon("SunflowerBeeTemplate")
PET_ICON_BUILDER.MapleFox         = foodTemplateIcon("MapleFoxTemplate")
PET_ICON_BUILDER.FrostPenguin     = foodTemplateIcon("FrostPenguinTemplate")
PET_ICON_BUILDER.BlossomBunny     = foodTemplateIcon("BlossomBunnyTemplate")
-- SPACE REALM pets (the SPACE tab): clones of the exact Space templates SpacePetTemplates.server.luau builds.
PET_ICON_BUILDER.SolarSlug        = foodTemplateIcon("SolarSlugTemplate")
PET_ICON_BUILDER.RoverRaccoon     = foodTemplateIcon("RoverRaccoonTemplate")
PET_ICON_BUILDER.BlackholeBat     = foodTemplateIcon("BlackholeBatTemplate")
PET_ICON_BUILDER.CometCat         = foodTemplateIcon("CometCatTemplate")

-- ============================================================================
-- THE FULL PET CATALOG (realm 1 parity: the Hub always shows EVERY pet).
-- Un-owned pets get the SAME card and the SAME full-colour spinning 3D icon as
-- owned ones -- a padlock badge and a gold LOCKED line are the only difference,
-- because seeing the actual prize is what makes a player want it. Order = the
-- climb order of the island each one hatches on (IslandOrder.NAMES), so the grid
-- mirrors the tower. `how` never names the island (the LOCKED line already does).
-- ============================================================================
-- RARITY, matching the first realm. Each dino pet now carries a tier the same way the food
-- realm's pets do, drawn from the SAME four words the skin crates already use --
-- Common / Rare / Epic / Legendary -- so a rarity word means one thing everywhere in the game
-- rather than one thing on a crate and another on a pet.
--
-- ORDERED BY CLIMB SLOT, NOT BY THIS TABLE'S ORDER. The catalog is written in the realm's
-- original pet order, which stopped matching the tower when Misty Mire and Fern Frontier
-- swapped: Spinosaurus is now the 3rd island's pet and Triceratops the 8th's. Tiers follow
-- where the pet is actually EARNED, so the ladder still climbs with the tower --
--   slot 1 Stego / slot 3 Spino (Common) -> slot 5 Raptor / slot 8 Shark (Rare)
--   -> slot 10 Trike (Epic) -> slot 13 T-Rex (Legendary, the summit finale).
--
-- Slots 7 and 12 (Claw Cliffs, Redwood Ridge) are not in that ladder: both grant
-- RaptorPet, the same pet Fossil Frontier already gave you at slot 5. They sit where
-- they do so the two unavoidable back-to-back quest islands never hand you two
-- DIFFERENT pets in a row -- see the order note in IslandOrder.
--
-- `rareName` is the first realm's RARE VARIANT idea (see FOOD_RARE_NAMES below, keyed
-- petId.."#R"): the same pet, pulled in its rare form, gets its own name rather than a
-- suffix. Named here so the two realms' pets read as one collection.
local PET_CATALOG = {
	-- ISLAND + HOW ARE THE PLAYER-FACING ANSWER TO "where do I get this", so they have to track
	-- the grants. Three of these were stale: the Stego and Triceratops swapped islands when the
	-- Mama Triceratops on Nesting Nook turned out to be handing out a Stego, and the Raptor kept
	-- only Redwood Ridge when Fossil Frontier and Claw Cliffs stopped duplicating it.
	{ key = "TriceratopsPet",   displayName = "Triceratops",  island = "Nesting Nook",    how = "Hatch the egg by the nest",
		rarity = "Common",    rareName = "Obsidian Triceratops" },
	{ key = "SpinosaurusPet",   displayName = "Spinosaurus",  island = "Misty Mire",      how = "Swat the mosquitos in the swamp",
		rarity = "Common",    rareName = "Storm Spinosaurus" },
	{ key = "BrachiosaurusPet", displayName = "Brachiosaurus",island = "Fossil Frontier", how = "Dig up the buried egg",
		rarity = "Rare",      rareName = "Ancient Bonewalker" },
	{ key = "TherizinosaurusPet", displayName = "Therizinosaurus", island = "Claw Cliffs", how = "Carry meat to the nest",
		rarity = "Rare",      rareName = "Scythe Lord" },
	{ key = "SharkPet",         displayName = "Megalodon",    island = "Coastal Crossing",how = "Fish the egg out of the lake",
		rarity = "Rare",      rareName = "Abyssal Megalodon" },
	{ key = "StegoPet",         displayName = "Stegosaurus",  island = "Fern Frontier",   how = "Find and hatch the egg on the island",
		rarity = "Epic",      rareName = "Crystal Stegosaurus" },
	{ key = "RaptorPet",        displayName = "Velociraptor", island = "Redwood Ridge",   how = "Snipe the raptors on the ridge",
		rarity = "Epic",      rareName = "Phantom Velociraptor" },
	{ key = "TyrannosaurusPet", displayName = "T-Rex",        island = "Volcanic Vista",  how = "Plug all six geysers",
		rarity = "Legendary", rareName = "Molten T-Rex" },
}

-- Tier colours come from PetSkins, NOT a second copy. Those exact four colours are already
-- authored there for the crate UI, and this project has been bitten more than once by the
-- same table living in two files and drifting (FoodMenu vs FoodStands, StomachTiers vs the
-- shop panel). pcall-guarded so the Hub still builds if the module is missing -- the cards
-- just fall back to plain grey text.
local dinoTierColor do
	local okPS, PS = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm", 10):WaitForChild("PetSkins", 10))
	end)
	dinoTierColor = function(tier)
		if okPS and PS and PS.tierColor then
			local ok, c = pcall(PS.tierColor, tier)
			if ok and c then return c end
		end
		return Color3.fromRGB(175, 205, 250) -- the line's original colour
	end
end

-- ============================================================================
-- FOOD REALM PET CATALOG -- the FIRST realm's collection, shown read-only on the
-- Hub's FOOD tab. Data source: FoodPetsEvent -> _G.arrivedSpacePets (the pet table
-- the rift teleport carried across, keyed petId / petId.."#R" for rares -- see
-- FoodRealmPets_Data.md). These pets can't be equipped or levelled HERE (their
-- catalog doesn't exist in this game), so every card points back to the Food Realm.
-- The 10 main collection pets + the Pizza Dragon secret; rebirth pets (Molten
-- Bean / Void Dragon / Prism Fox) are recolour clones and left out.
-- Every pet renders as a clone of its EXACT food-realm fused template (see
-- foodTemplateIcon above + FoodPetTemplates.server.luau); the emoji is only the
-- viewport placeholder while the template builds.
-- ============================================================================
local FOOD_CATALOG = {
	{ key = "BeanBuddy",        displayName = "Bean Buddy",        where = "Bean Farm",                          emoji = "\xF0\x9F\x8C\xB1" },
	{ key = "BroccoliPet",      displayName = "Broccoli Bunny",    where = "Broccoli Bluff",                     emoji = "\xF0\x9F\xA5\xA6" },
	{ key = "CoconutCrab",      displayName = "Coconut Crab",      where = "Coconut Cove",                       emoji = "\xF0\x9F\xA6\x80" },
	{ key = "PopcornSheep",     displayName = "Popcorn Sheep",     where = "Popcorn Pinnacle",                   emoji = "\xF0\x9F\x8D\xBF" },
	{ key = "ButterDuck",       displayName = "Butter Duck",       where = "Butter Swamp",                       emoji = "\xF0\x9F\xA6\x86" },
	{ key = "BurritoArmadillo", displayName = "Burrito Armadillo", where = "Burrito Barrens",                    emoji = "\xF0\x9F\x8C\xAF" },
	{ key = "SunflowerBee",     displayName = "Sunflower Bee",     where = "Community Garden \xC2\xB7 Summer",   emoji = "\xF0\x9F\x8C\xBB" },
	{ key = "MapleFox",         displayName = "Maple Fox",         where = "Community Garden \xC2\xB7 Autumn",   emoji = "\xF0\x9F\x8D\x81" },
	{ key = "FrostPenguin",     displayName = "Frost Penguin",     where = "Community Garden \xC2\xB7 Winter",   emoji = "\xF0\x9F\x90\xA7" },
	{ key = "BlossomBunny",     displayName = "Blossom Bunny",     where = "Community Garden \xC2\xB7 Spring",   emoji = "\xF0\x9F\x8C\xB8" },
	{ key = "PizzaDragon",      displayName = "Pizza Dragon",      where = "Secret Pet",                         emoji = "\xF0\x9F\x8D\x95", secret = true },
}
local FOOD_RARE_NAMES = { BroccoliPet = "Emerald Bunny", CoconutCrab = "Golden Crab", PopcornSheep = "Cloud Sheep",
	BurritoArmadillo = "Crystal Armadillo", ButterDuck = "Cosmic Duck" }
-- Food realm levels display as AGE words, never rarity words (rarity belongs to skin
-- crates over there). Rares override the age entirely -- Exotic cyan; ButterDuck's
-- rare is the 1-in-10,000 Mythical magenta. Same breakpoints/colors as the source.
local function foodAge(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230)
		else return "Exotic", Color3.fromRGB(40,235,225) end
	end
	if level <= 5      then return "Baby",  Color3.fromRGB(175,180,190)
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90,210,90)
	elseif level <= 15 then return "Teen",  Color3.fromRGB(70,140,255)
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235)
	else                    return "Elder", Color3.fromRGB(255,170,40) end
end
local function foodXpNeeded(level) -- the food realm's exact curve: floor(80 * L^1.6)
	if level >= 25 then return 0 end
	return math.floor(80 * level ^ 1.6)
end

-- ============================================================================
-- PET HUB PANEL -- VERBATIM from PetFollow.client.lua (Pet Hub region).
-- ============================================================================
-- ============================================================================
-- SPACE REALM PET CATALOG -- the Hub's SPACE tab, read-only exactly like FOOD. The Space Realm's four
-- planet pets (one per planet task there -- its PetGrants.PLANET_PETS). They ride the SAME rift payload as
-- the food pets: Space's DinoRift sends ownedPets = _G.playerOwnedPets[player], which holds BOTH that realm's
-- food collection and these four (keys SolarSlug / RoverRaccoon / BlackholeBat / CometCat, each
-- { level, xp }). ArrivalReceiver keeps it in _G.arrivedSpacePets and FoodPetsEvent already delivers it --
-- the FOOD grid simply ignores the keys it doesn't know. Tier words + XP curve are Space's own (SpacePetsTab).
-- ONE table rather than a row of locals: this file sits close to Luau's 200-local ceiling.
-- ============================================================================
local SPACE = {
	CATALOG = {
		{ key = "SolarSlug",    displayName = "Solar Slug",    where = "Venus",   task = "take the heat readings",   emoji = "\xE2\x98\x80" },
		{ key = "RoverRaccoon", displayName = "Rover Raccoon", where = "Mars",    task = "mine the gem crystals",    emoji = "\xF0\x9F\x9A\x80" },
		{ key = "BlackholeBat", displayName = "Blackhole Bat", where = "Saturn",  task = "clear the ring fragments", emoji = "\xF0\x9F\xA6\x87" },
		{ key = "CometCat",     displayName = "Comet Cat",     where = "Neptune", task = "drill the ice cores",      emoji = "\xE2\x98\x84" },
	},
	subtitle = "Space Realm collection \xE2\x80\x94 return there to equip & level",
	latest = {},
}
function SPACE.xpNeeded(level) return 50 + (level - 1) * 25 end -- the Space Realm's curve (SpacePetsTab)
function SPACE.tier(level)
	if level <= 5 then return "Common", Color3.fromRGB(175,180,190)
	elseif level <= 10 then return "Uncommon", Color3.fromRGB(90,210,90)
	elseif level <= 15 then return "Rare", Color3.fromRGB(70,140,255)
	elseif level <= 20 then return "Epic", Color3.fromRGB(180,90,235)
	else return "Legendary", Color3.fromRGB(255,170,40) end
end

local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100
invGui.Parent = pg
-- FIRST-REALM SWEEP: every word in this hub gets a black outline. Only TRANSPARENT-background, solid text (on a
-- filled text object a UIStroke outlines the border, not the glyphs; faded watermarks stay soft); anything that
-- already carries a UIStroke keeps its own. Deferred a step so labels judged on their final state.
invGui.DescendantAdded:Connect(function(o)
	task.defer(function()
		if o.Parent == nil then return end
		if not (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then return end
		if o.BackgroundTransparency < 1 or o.TextTransparency > 0.3 or o:FindFirstChildOfClass("UIStroke") then return end
		local st = Instance.new("UIStroke"); st.Color = Color3.new(0, 0, 0)
		st.Thickness = (o.TextScaled or o.TextSize >= 16) and 2 or 1.5; st.LineJoinMode = Enum.LineJoinMode.Round; st.Parent = o
	end)
end)
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end
local function gloss(btn) local gl = Instance.new("Frame"); gl.AnchorPoint = Vector2.new(0.5,0); gl.Position = UDim2.new(0.5,0,0,3); gl.Size = UDim2.new(1,-10,0,9); gl.BackgroundColor3 = Color3.new(1,1,1); gl.BorderSizePixel = 0; gl.ZIndex = (btn.ZIndex or 1) + 1; gl.Parent = btn; uicorner(gl, 6); local gg = Instance.new("UIGradient"); gg.Rotation = 90; gg.Transparency = NumberSequence.new(0.45, 1); gg.Parent = gl end -- glossy top highlight

local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
-- Active: the dim's ONLY job is to swallow presses while the hub is up, so nothing behind it
-- (the world, the bottom HUD, the side rail) reacts to a press aimed at the panel. It does NOT
-- close the hub -- see the note by closeBtn below.
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = true; dim.Parent = invGui

-- ===== STONE SHELL: a chunky grey COBBLESTONE border framing the panel (behind it) =====
local STONE_A, STONE_B, STONE_D = Color3.fromRGB(224,204,150), Color3.fromRGB(202,178,118), Color3.fromRGB(148,116,66)
local shell = Instance.new("Frame"); shell.Name = "StoneShell"; shell.AnchorPoint = Vector2.new(0.5,0.5)
shell.Position = UDim2.new(0.5,0,0.5,-16); shell.Size = UDim2.fromOffset(740,560); shell.BackgroundColor3 = STONE_B  -- hub-parity screen spot (-45 equivalent; no phone clipping)
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
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-16); panel.AnchorPoint = Vector2.new(0.5,0.5)  -- hub-parity screen spot (-45 equivalent; no phone clipping)
panel.BackgroundColor3 = Color3.fromRGB(122,142,82); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui
uicorner(panel, 16); uistroke(panel, Color3.fromRGB(40,52,38), 2)
do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(126,146,86)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(128,148,88)), ColorSequenceKeypoint.new(1, Color3.fromRGB(124,144,84)) }); g.Parent = panel end -- mossy: lighter centre
-- faint paw-print watermark (on the panel bg, under the content)
-- soft mossy radial glow (lighter centre, fades to the edges)
local glow = Instance.new("Frame"); glow.AnchorPoint = Vector2.new(0.5,0.5); glow.Position = UDim2.new(0.5,0,0.5,0); glow.Size = UDim2.fromOffset(620,500); glow.BackgroundColor3 = Color3.fromRGB(150,170,108); glow.BackgroundTransparency = 0.82; glow.BorderSizePixel = 0; glow.Parent = panel; uicorner(glow, 250)
do local glg = Instance.new("UIGradient"); glg.Rotation = 90; glg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(0.5,0), NumberSequenceKeypoint.new(1,1) }); glg.Parent = glow end
local pawWM = Instance.new("TextLabel"); pawWM.AnchorPoint = Vector2.new(0.5,0.5); pawWM.Position = UDim2.new(0.5,0,0.56,0); pawWM.Size = UDim2.fromOffset(310,310); pawWM.BackgroundTransparency = 1; pawWM.Font = Enum.Font.FredokaOne; pawWM.Text = "\xF0\x9F\x90\xBE"; pawWM.TextScaled = true; pawWM.TextColor3 = Color3.fromRGB(30,62,34); pawWM.TextTransparency = 0.72; pawWM.Parent = panel
hubPanel = panel -- the blink loops above idle on this
panel:GetPropertyChangedSignal("Visible"):Connect(function() shell.Visible = panel.Visible end) -- shell shows/hides with the panel

-- FOLIAGE REMOVED. This was the heaviest leaf decoration in the game: eight edge sprigs
-- plus a five-leaf fan on each of the four corners, every leaf a blade + drop shadow +
-- gradient + centre vein, drawn on the SHELL at ZIndex 10-13 -- above the panel itself.
-- The bamboo shell, the olive panel and the paw watermark carry the jungle look on their
-- own; the leaves were sitting over the hub's own content.
--
-- The whole helper set (leaf / stemDot / sprig / strand / corner and the VGREENS + VINE
-- palettes) went with the calls -- nothing else referenced them.

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
-- no plaque behind the title -- just the text on the header. The text NAMES THE PAGE
-- you are on (PETS / TRADE / QUESTS -- the tab entry points below retitle it).
local title = Instance.new("TextLabel"); title.Name = "HubTitle"; title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne; title.TextSize = 26; title.ZIndex = 3
title.TextColor3 = Color3.fromRGB(255,215,0); title.Text = "PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(0,212,0,34); title.Position = UDim2.new(0,50,0,7); title.Parent = header
uistroke(title, Color3.fromRGB(18,38,20), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(245,236,208); subtitle.Text = "Your pets & quest progress"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(0,260,0,16); subtitle.Position = UDim2.new(0,50,0,43); subtitle.Parent = header
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2); gloss(closeBtn)

-- PETS section (fills the panel width: 2 big cards/row)
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-114); sec.Position = UDim2.new(0,x,0,108)
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
petsSection.Size = UDim2.new(1, -24, 1, -116); petsSection.Position = UDim2.new(0, 12, 0, 110) -- the first realm's band: under the tab bar, section title on show
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,322,0,252); petsGrid.CellPadding = UDim2.new(0,10,0,12)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; petsGrid.Parent = petsScroll
-- TRADE UP chip (the first realm's pets-page action): burn duplicate skins you own for one of the next rarity.
-- The crate panel owns that page; this is only its door. Orange = the first realm's "primary" colour.
do
	local chip = Instance.new("TextButton"); chip.Name = "TradeUpChip"; chip.AnchorPoint = Vector2.new(1, 0)
	chip.Size = UDim2.new(0, 112, 0, 24); chip.Position = UDim2.new(1, -10, 0, 5)
	chip.BackgroundColor3 = Color3.fromRGB(255, 150, 40); chip.Text = "\xE2\x86\x91 TRADE UP"; chip.Font = Enum.Font.FredokaOne
	chip.TextSize = 13; chip.TextColor3 = Color3.fromRGB(60, 30, 0); chip.AutoButtonColor = true; chip.ZIndex = 5; chip.Parent = petsSection
	uicorner(chip, 8); uistroke(chip, Color3.new(0, 0, 0), 2)
	chip.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		if _G.toggleSkinCrates then pcall(_G.toggleSkinCrates, true, "tradeup") end
	end)
end
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = petsScroll
end

-- QUESTS overlay
local questsOverlay = Instance.new("Frame"); questsOverlay.Name = "QuestsOverlay"; questsOverlay.Size = UDim2.new(1,-24,1,-116); questsOverlay.Position = UDim2.new(0,12,0,110)
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

-- FOOD REALM PETS page -- the FOOD tab. Built through the SAME makeSection as the
-- PETS page and pinned to the SAME band, so it's identical furniture: mossy section
-- chrome, same scroll metrics, same 2-wide grid starting at the same height. Only
-- the cards inside differ (food-realm blue). No back button, no extra header row --
-- the PETS page has neither; the tab bar does the navigating.
local foodOverlay, foodScroll = makeSection(12, 676, "\xF0\x9F\x8D\x94 PETS")
foodOverlay.Name = "FoodOverlay" -- the tab router's fallback shows/hides by this name
foodOverlay.Size = UDim2.new(1, -24, 1, -116); foodOverlay.Position = UDim2.new(0, 12, 0, 110) -- same band as petsSection
foodOverlay.Visible = false
local foTitle = foodOverlay:FindFirstChildOfClass("TextLabel") -- the section title (sits behind the tab bar, same as PETS')
local foodGrid = Instance.new("UIGridLayout"); foodGrid.CellSize = UDim2.new(0,322,0,252); foodGrid.CellPadding = UDim2.new(0,10,0,12)
foodGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; foodGrid.Parent = foodScroll
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = foodScroll
end

-- SPACE REALM PETS page -- the SPACE tab. Same furniture as the FOOD page above (makeSection, same band,
-- same 2-wide grid); only the cards differ (the Space Realm's navy).
do
	local ov, sc = makeSection(12, 676, "\xF0\x9F\x9A\x80 PETS")
	ov.Name = "SpaceOverlay"
	ov.Size = UDim2.new(1, -24, 1, -116); ov.Position = UDim2.new(0, 12, 0, 110) -- same band as petsSection
	ov.Visible = false
	local g = Instance.new("UIGridLayout"); g.CellSize = UDim2.new(0,322,0,252); g.CellPadding = UDim2.new(0,10,0,12)
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center; g.Parent = sc
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4); pad.Parent = sc
	SPACE.overlay, SPACE.scroll = ov, sc
	SPACE.title = ov:FindFirstChildOfClass("TextLabel")
end

-- Forward-declared: the PET DETAIL PAGE (built after the card builders it serves --
-- search "PET DETAIL PAGE"). Declared this early so openPanel and the tab entry
-- points can hide it, and so the card builders' click handlers can capture showDetail.
local detailPage = nil     -- the page Frame
local detailSpecies = nil  -- petId currently on the page (nil = closed)
local detailIsFood = false -- true = the open page is a FOOD REALM pet (read-only)
local showDetail           -- showDetail(petId) -- opens the page
local rebuildDetail        -- repaints the open page from live state

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
			-- always land on the pets grid, never on a stale detail page or another tab's overlay
			pcall(function()
				questsOverlay.Visible = false; foodOverlay.Visible = false; SPACE.overlay.Visible = false; petsSection.Visible = true
				if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false
			end)
			-- the tab bar keeps its own highlight; snap it back to PETS so it agrees with the page
			pcall(function() if _G.PetHubTabs and _G.PetHubTabs.active ~= "pets" then _G.PetHubTabs.setActive("pets") end end)
			_G.MainMenuManager.notifyOpened("PetInv")
			local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
			print("[PetInv] inventory opened - owned: " .. nOwned)
			if _G.applyHudScaling then _G.applyHudScaling() end
		else
			_G.MainMenuManager.notifyClosed("PetInv")
			pcall(function()
				questsOverlay.Visible = false; foodOverlay.Visible = false; SPACE.overlay.Visible = false; petsSection.Visible = true
				if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false
			end)
		end
	end)
	if not ok then
		warn("[PetInv] ERROR opening/building: " .. tostring(err))
		pcall(function() if open then _G.MainMenuManager.current = "PetInv" else _G.MainMenuManager.notifyClosed("PetInv") end end)
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
-- NO click-outside-to-close. The dim spans the whole screen and sits UNDER the panel, so
-- its InputBegan fired for presses that were never "outside" at all -- the decorative stone
-- shell around the panel is a sibling that doesn't sink input, and any press that slipped
-- between the panel's interactive children reached the dim too. The hub read as closing at
-- random. It now closes only on an explicit action: the X, its own toggle, or
-- MainMenuManager closing it because another menu opened. (Same call the MORE+ menu and the
-- Season Pass panel already made -- see Bootstrap's "deliberately NO catcher click-to-close".)
--
-- The dim still SWALLOWS the press (it's Active -- set where it's built) so it can't fall
-- through to the world or the HUD underneath while the hub is up. That's its whole job now.
-- the ONE pet button toggles this panel via here (MORE+ -> Pets fires PetInvToggle)
local function toggleHub(open)
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
	if open == nil then openPanel(not isOpen) else openPanel(open and true or false) end
end
-- GLOBAL entry point, tried FIRST by every caller (Bootstrap's MORE+ Pets card, the
-- crate panel's BACK / GO TO QUESTS buttons). The BindableEvent below is kept as a
-- fallback, but an instance parented to PlayerGui can be swept away by GUI cleanup
-- passes -- which left the Pets button dead ("PetInvToggle not found") while this
-- script was running fine. A _G function can't be destroyed.
_G.togglePetHub = toggleHub
local toggleEvent
local function buildToggleEvent()
	toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
	toggleEvent.Event:Connect(function() toggleHub() end)
	-- self-heal: if something deletes the event, put a fresh one back
	toggleEvent.AncestryChanged:Connect(function(_, parent)
		if parent == nil then task.defer(buildToggleEvent) end
	end)
end
buildToggleEvent()

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
						local offset = dir * (maxe * 1.45 + 1)
						req.cam.CFrame = CFrame.lookAt(center + offset, center)
						if req.petId == "SharkPet" or req.petId == "Shark" then
							local pv = model:GetPivot()
							print(("[PetHub][ORIENT] hub shark: model at IDENTITY pivotUp=(%.2f,%.2f,%.2f) -> +Y dorsal UP, +X face toward the front-upper-right camera dir=(0.80,0.50,0.55)"):format(pv.UpVector.X, pv.UpVector.Y, pv.UpVector.Z))
						end
						-- detail-page requests carry the pet's EQUIPPED skin: recolour the clone so the
						-- stage matches the follower/card (static -- colour+material only; particles
						-- don't render inside ViewportFrames anyway)
						if req.skin and _G.applyPetSkinPreview then
							pcall(_G.applyPetSkinPreview, model, req.skin, req.trait, true)
						end
						-- the spinner ORBITS THE CAMERA, so it stores the rest frame rather than the
						-- model: one CFrame write per icon per frame instead of a whole-model PivotTo.
						iconSpins[#iconSpins+1] = {
							model = model, center = center, cam = req.cam, offset = offset,
							vp = req.vp, card = req.card, scroll = req.scroll, chain = req.chain,
						}
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
	-- The spinner culls by page + scroll position, so record where this icon lives.
	-- Every caller parents the card BEFORE calling here, so this resolves now:
	--   card -> petsScroll   -> petsSection                (dino grid)
	--   card -> foodScroll   -> foodOverlay                (food grid)
	--   card -> *OfferScroll -> windowView -> tradeOverlay (trade)
	-- The FULL chain matters, not just the immediate page: trade's windowView stays
	-- Visible when you tab away, and only tradeOverlay above it goes false.
	local scroll = card.Parent
	local chain = {}
	local a = scroll
	while a and a ~= panel and a:IsA("GuiObject") do chain[#chain+1] = a; a = a.Parent end
	iconQueue[#iconQueue + 1] = { vp = vp, cam = cam, ph = ph, petId = petId, level = level, isRare = isRare,
		card = card, scroll = scroll, chain = chain }
	startIconWorker()
	return vp
end
-- ===== THE SPINNER =====
-- Three things keep this cheap with ~17 icons live (6 dino + 11 food):
--
--  1. ORBIT THE CAMERA, NOT THE MODEL. PivotTo() rewrites the CFrame of every part in
--     the model -- 40 for the T-Rex, 53 for the raptor -- so the old version was doing
--     hundreds of part writes per frame. Rotating the camera around the model is ONE
--     CFrame write per icon and looks identical (the pet still turns on the spot).
--  2. SKIP PAGES THAT AREN'T ON SCREEN. The food grid's 11 icons must not cost anything
--     while you're looking at the dino grid, and vice versa.
--  3. CULL BY SCROLL POSITION, and actually hide the off-screen ones. A ViewportFrame is
--     its own render pass, so a scrolled-away card is real GPU work even though you can't
--     see it -- Visible=false is the only thing that truly stops it.
--
-- Everything visible still updates every frame, so the motion stays smooth; the work just
-- scales with what's on screen (typically 2-4 icons) instead of with what exists.
do
	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		if not panel.Visible or #iconSpins == 0 then return end
		-- NEGATIVE: orbiting the camera one way turns the pet the other, so this keeps the
		-- original spin direction. Same 0.6 rad/s as before.
		angle = (angle - dt * 0.6) % (2 * math.pi)
		local rot = CFrame.Angles(0, angle, 0)
		for i = #iconSpins, 1, -1 do
			local ic = iconSpins[i]
			if not (ic.model and ic.model.Parent and ic.vp and ic.vp.Parent) then
				table.remove(iconSpins, i)
			else
				local onScreen = true
				for _, f in ipairs(ic.chain) do -- is this icon's page actually up? (2-3 reads)
					if not f.Visible then onScreen = false; break end
				end
				local sc, card = ic.scroll, ic.card
				if onScreen and sc and card then -- vertical overlap test against the scroll window (the grids are rows)
					local sy, sh = sc.AbsolutePosition.Y, sc.AbsoluteSize.Y
					local cy, ch = card.AbsolutePosition.Y, card.AbsoluteSize.Y
					onScreen = (cy + ch >= sy - 24) and (cy <= sy + sh + 24) -- 24px of slack so nothing pops in late
				end
				if ic.vp.Visible ~= onScreen then ic.vp.Visible = onScreen end
				if onScreen then
					local c = ic.center
					ic.cam.CFrame = CFrame.lookAt(c + rot * ic.offset, c)
				end
			end
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
	-- the WHOLE card opens the detail page. Parented FIRST so it sits under every real
	-- control -- EQUIP/SKIP and the VIEW chip are later siblings, so they still swallow
	-- their own clicks; anything else on the card falls through to this.
	local hit = Instance.new("TextButton"); hit.Name = "OpenDetail"; hit.Size = UDim2.new(1,0,1,0)
	hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = card
	hit.MouseButton1Click:Connect(function() if showDetail then showDetail(key) end end)
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	-- visible affordance for the card-wide hit: a small chip on the picture's bottom-right
	local view = Instance.new("TextButton"); view.Size = UDim2.new(0,74,0,22); view.Position = UDim2.new(1,-10,0,120); view.AnchorPoint = Vector2.new(1,0)
	view.BackgroundColor3 = Color3.fromRGB(16,38,20); view.BackgroundTransparency = 0.2; view.Font = Enum.Font.GothamBold
	view.TextSize = 11; view.TextColor3 = Color3.fromRGB(255,215,0); view.Text = "\xF0\x9F\x94\x8D VIEW"; view.ZIndex = 3; view.Parent = card
	uicorner(view, 6); uistroke(view, Color3.fromRGB(18,38,20), 1)
	view.MouseButton1Click:Connect(function() if showDetail then showDetail(key) end end)
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

-- A LOCKED pet card -- one for every pet in the catalog the player does NOT own yet. The pet is shown in FULL
-- COLOUR, exactly as it really looks (same card, same spinning 3D model as an owned pet) -- seeing the actual
-- prize is what makes a player want it. "Locked" is communicated by the padlock badge, the gold LOCKED line and
-- the how-to-get-it text, NOT by hiding, dimming or greying the pet. The only thing missing vs an owned card is
-- the EQUIP/SKIP buttons (there's nothing to equip yet). The hint says where to go, never where things hide.
-- (Ported from the first realm's PetFollow.client.lua buildLockedPetCard -- see LockedPetCard_Look.md. The one
-- deliberate change: the food realm's "X / Y Skins" line is repurposed, since this realm has no pet skins.)
local function buildLockedPetCard(entry, order, catalogIndex)
	local card = Instance.new("Frame"); card.Name = "Locked_" .. tostring(entry.key); card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(34,74,40); card.Parent = petsScroll -- SAME green as an owned card
	uicorner(card, 12); uistroke(card, Color3.fromRGB(255,190,60), 2) -- gold "locked" border
	makeViewportIcon(card, entry.key, 1, false, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0)) -- full colour, Lv1 look
	-- padlock badge over the top-right of the picture -- this (not a grey-out) is what marks the card as locked
	local lock = Instance.new("TextLabel"); lock.Size = UDim2.new(0,28,0,28); lock.Position = UDim2.new(1,-12,0,12); lock.AnchorPoint = Vector2.new(1,0)
	lock.BackgroundTransparency = 1; lock.Font = Enum.Font.FredokaOne; lock.TextScaled = true; lock.Text = "\xF0\x9F\x94\x92"; lock.Parent = card
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = Color3.new(1,1,1); nm.Text = entry.displayName or entry.key; nm.Parent = card
	local st = Instance.new("TextLabel"); st.Size = UDim2.new(1,-16,0,16); st.Position = UDim2.new(0,8,0,170)
	st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold; st.TextSize = 13
	st.TextColor3 = Color3.fromRGB(255,205,90); st.Text = "\xF0\x9F\x94\x92 LOCKED" .. (entry.island and ("  \xE2\x80\xA2  " .. entry.island) or ""); st.Parent = card
	-- RARITY + island + collection position. This was the food realm's skins line repurposed,
	-- with a note saying "Dino Realm pets have no skins" -- no longer true in either half:
	-- the crates hand out skins for these pets (Shadow SharkPet, Stone StegoPet), and each pet
	-- now carries a rarity of its own. The tier leads the line and is the only coloured part,
	-- so the grid can be read for rarity at a glance the way the crate UI is.
	do
		local rs = Instance.new("TextLabel"); rs.Size = UDim2.new(1,-20,0,14); rs.Position = UDim2.new(0,10,0,188)
		rs.BackgroundTransparency = 1; rs.Font = Enum.Font.GothamBold; rs.TextSize = 12
		rs.TextColor3 = dinoTierColor(entry.rarity)
		rs.TextXAlignment = Enum.TextXAlignment.Left
		rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.Parent = card
		rs.Text = string.upper(entry.rarity or "Common")
			.. "   \xC2\xB7   " .. (entry.island or "???")
			.. "   \xC2\xB7   " .. tostring(catalogIndex or "?") .. "/" .. #PET_CATALOG
	end
	local how = Instance.new("TextLabel"); how.Size = UDim2.new(1,-20,0,26); how.Position = UDim2.new(0,10,0,204)
	how.BackgroundTransparency = 1; how.Font = Enum.Font.Gotham; how.TextSize = 12; how.TextWrapped = true
	how.TextColor3 = Color3.fromRGB(205,222,255); how.TextYAlignment = Enum.TextYAlignment.Top
	how.Text = entry.how or "Keep exploring to find this pet"; how.Parent = card
	-- VIEW QUEST, not VIEW MORE: a locked pet has nothing to customise, so the only useful thing this page can
	-- tell you is how to earn it. The card is deliberately NOT click-through either.
	local more = Instance.new("TextButton"); more.Size = UDim2.new(1,-16,0,20); more.Position = UDim2.new(0,8,0,230)
	more.BackgroundColor3 = Color3.fromRGB(150,110,30); more.Font = Enum.Font.GothamBold; more.TextSize = 12
	more.TextColor3 = Color3.new(1,1,1); more.Text = "\xF0\x9F\x94\x92 VIEW QUEST"; more.Parent = card
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90,66,16), 1)
	-- opens the pet's DETAIL PAGE (locked variant: gold LOCKED line + how-to-unlock).
	-- The locked card is deliberately NOT click-through -- this button is the only way in.
	more.MouseButton1Click:Connect(function() if showDetail then showDetail(entry.key) end end)
end

-- ============================================================================
-- FOOD REALM PET CARDS (the FOOD tab). Same 322x252 grid cell and same layout
-- rhythm as the dino cards, but in the food realm's own card colours (blue owned /
-- purple rare -- FoodRealmPets_Data.md section 9), so the page reads as "their"
-- collection. No EQUIP/SKIP here: these pets can only be equipped and levelled in
-- the Food Realm, so that button row is replaced by a pointer back there.
-- ============================================================================
-- every food pet renders as its EXACT food-realm template clone (spinning, full
-- colour) via the shared viewport path; the pet's emoji stands in as the viewport
-- placeholder while the template streams/builds.
local function makeFoodIcon(card, entry, level, isRare)
	local vp = makeViewportIcon(card, entry.key, level, isRare, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	vp.BackgroundColor3 = Color3.fromRGB(10,32,80) -- match the blue food cards (the default is the dino dark-green)
	local ph = vp:FindFirstChild("IconPlaceholder")
	if ph and entry.emoji then ph.Text = entry.emoji end
	return vp
end

-- one OWNED food pet card -- age word + level, XP bar on the food realm's curve.
-- isRare = the "#R" inventory entry (pre-maxed, its own card, own name + badge).
local function buildFoodOwnedCard(entry, p, isRare, order)
	local level = math.clamp(tonumber(p.level) or 1, 1, 25)
	local card = Instance.new("Frame"); card.Name = "Food_" .. entry.key .. (isRare and "_R" or ""); card.LayoutOrder = order
	card.BackgroundColor3 = isRare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160); card.Parent = foodScroll
	uicorner(card, 12)
	local ageName, ageColor = foodAge(level, isRare, entry.key)
	uistroke(card, isRare and ageColor or Color3.fromRGB(12,44,110), isRare and 3 or 1)
	-- whole card opens the detail page; parented FIRST so later controls (the pointer-home
	-- button, the VIEW chip) still swallow their own clicks
	local hit = Instance.new("TextButton"); hit.Name = "OpenDetail"; hit.Size = UDim2.new(1,0,1,0)
	hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = card
	hit.MouseButton1Click:Connect(function() if showDetail then showDetail(entry.key, true) end end)
	makeFoodIcon(card, entry, level, isRare)
	local view = Instance.new("TextButton"); view.Size = UDim2.new(0,74,0,22); view.Position = UDim2.new(1,-10,0,120); view.AnchorPoint = Vector2.new(1,0)
	view.BackgroundColor3 = Color3.fromRGB(10,32,80); view.BackgroundTransparency = 0.2; view.Font = Enum.Font.GothamBold
	view.TextSize = 11; view.TextColor3 = Color3.fromRGB(255,215,0); view.Text = "\xF0\x9F\x94\x8D VIEW"; view.ZIndex = 3; view.Parent = card
	uicorner(view, 6); uistroke(view, Color3.fromRGB(8,24,60), 1)
	view.MouseButton1Click:Connect(function() if showDetail then showDetail(entry.key, true) end end)
	if isRare then -- Exotic / Mythical corner tag, same treatment as the dino cards
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = ageColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = ageName; tag.ZIndex = 3; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end
	if (tonumber(p.count) or 1) > 1 then
		local cnt = Instance.new("TextLabel"); cnt.AutomaticSize = Enum.AutomaticSize.X; cnt.Size = UDim2.new(0,0,0,18); cnt.Position = UDim2.new(0,6,0,8)
		cnt.BackgroundColor3 = Color3.fromRGB(255,170,40); cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 12; cnt.TextColor3 = Color3.new(1,1,1); cnt.Text = "x" .. p.count; cnt.ZIndex = 3; cnt.Parent = card
		local cpad = Instance.new("UIPadding", cnt); cpad.PaddingLeft = UDim.new(0,5); cpad.PaddingRight = UDim.new(0,5)
		uicorner(cnt, 5); uistroke(cnt, Color3.new(0,0,0), 1)
	end
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = isRare and ageColor or Color3.new(1,1,1)
	nm.Text = isRare and (FOOD_RARE_NAMES[entry.key] or entry.displayName) or entry.displayName; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-16,0,16); lv.Position = UDim2.new(0,8,0,170)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13
	lv.TextColor3 = ageColor; lv.Text = isRare and ageName or (ageName .. "  Lv " .. level); lv.Parent = card
	local maxed = (level >= 25)
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-16,0,14); barBG.Position = UDim2.new(0,8,0,188)
	barBG.BackgroundColor3 = Color3.fromRGB(10,32,80); barBG.BorderSizePixel = 0; barBG.Parent = card; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(8,24,60), 1)
	local need = foodXpNeeded(level)
	local frac = maxed and 1 or math.clamp((tonumber(p.xp) or 0) / math.max(1, need), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextSize = 10; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or (math.floor(tonumber(p.xp) or 0) .. " / " .. need .. " XP")
	-- in the EQUIP/SKIP row: the pointer home (informational, not a teleport)
	local home = Instance.new("TextButton"); home.Size = UDim2.new(1,-16,0,26); home.Position = UDim2.new(0,8,0,208)
	home.BackgroundColor3 = Color3.fromRGB(38,110,210); home.AutoButtonColor = false
	home.Font = Enum.Font.GothamBold; home.TextSize = 12; home.TextColor3 = Color3.new(1,1,1)
	home.Text = "\xF0\x9F\x8D\x94 EQUIP & LEVEL IN THE FOOD REALM"; home.Parent = card
	uicorner(home, 8); uistroke(home, Color3.fromRGB(10,40,96), 1)
	local ms = Instance.new("TextLabel"); ms.Size = UDim2.new(1,-16,0,14); ms.Position = UDim2.new(0,8,0,236)
	ms.BackgroundTransparency = 1; ms.Font = Enum.Font.Gotham; ms.TextSize = 11; ms.TextColor3 = Color3.fromRGB(185,212,255)
	ms.Text = "\xE2\x9C\xA8 " .. (entry.where or "Food Realm"); ms.Parent = card
end

-- one LOCKED food pet card -- the exact LockedPetCard_Look spec (full-colour picture,
-- padlock badge, gold border, gold LOCKED line), except every task line points back:
-- "Return to the Food Realm to complete".
local function buildFoodLockedCard(entry, order, catalogIndex)
	local card = Instance.new("Frame"); card.Name = "FoodLocked_" .. entry.key; card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(20,70,160); card.Parent = foodScroll -- SAME blue as an owned food card
	uicorner(card, 12); uistroke(card, Color3.fromRGB(255,190,60), 2) -- gold "locked" border
	makeFoodIcon(card, entry, 1, false) -- full colour, Lv1 look -- never greyed
	local lock = Instance.new("TextLabel"); lock.Size = UDim2.new(0,28,0,28); lock.Position = UDim2.new(1,-12,0,12); lock.AnchorPoint = Vector2.new(1,0)
	lock.BackgroundTransparency = 1; lock.Font = Enum.Font.FredokaOne; lock.TextScaled = true; lock.Text = "\xF0\x9F\x94\x92"; lock.ZIndex = 3; lock.Parent = card
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = Color3.new(1,1,1); nm.Text = entry.displayName; nm.Parent = card
	local st = Instance.new("TextLabel"); st.Size = UDim2.new(1,-16,0,16); st.Position = UDim2.new(0,8,0,170)
	st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold; st.TextSize = 13
	st.TextColor3 = Color3.fromRGB(255,205,90)
	st.Text = "\xF0\x9F\x94\x92 LOCKED  \xE2\x80\xA2  " .. (entry.where or "Food Realm"); st.Parent = card
	local rs = Instance.new("TextLabel"); rs.Size = UDim2.new(1,-20,0,14); rs.Position = UDim2.new(0,10,0,188)
	rs.BackgroundTransparency = 1; rs.Font = Enum.Font.Gotham; rs.TextSize = 12
	rs.TextColor3 = Color3.fromRGB(175,205,250); rs.TextXAlignment = Enum.TextXAlignment.Left
	rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.Parent = card
	rs.Text = "Food Realm   \xC2\xB7   Pet " .. tostring(catalogIndex) .. " of " .. #FOOD_CATALOG
	local how = Instance.new("TextLabel"); how.Size = UDim2.new(1,-20,0,26); how.Position = UDim2.new(0,10,0,204)
	how.BackgroundTransparency = 1; how.Font = Enum.Font.Gotham; how.TextSize = 12; how.TextWrapped = true
	how.TextColor3 = Color3.fromRGB(205,222,255); how.TextYAlignment = Enum.TextYAlignment.Top
	how.Text = entry.secret and "Return to the Food Realm and collect all 10 pets to unlock this secret pet"
		or "Return to the Food Realm to complete this pet's quest"; how.Parent = card
	local more = Instance.new("TextButton"); more.Size = UDim2.new(1,-16,0,20); more.Position = UDim2.new(0,8,0,230)
	more.BackgroundColor3 = Color3.fromRGB(150,110,30); more.AutoButtonColor = false
	more.Font = Enum.Font.GothamBold; more.TextSize = 12; more.TextColor3 = Color3.new(1,1,1)
	more.Text = "\xF0\x9F\x94\x92 RETURN TO FOOD REALM TO COMPLETE"; more.Parent = card
	more.AutoButtonColor = true
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90,66,16), 1)
	-- opens the detail page's LOCKED variant (gold LOCKED line + the return-home sentence)
	more.MouseButton1Click:Connect(function() if showDetail then showDetail(entry.key, true) end end)
end

-- Repaint the FOOD grid from a food-realm pet table (keys: petId, or petId.."#R" for
-- the rare variant -- both can be owned at once and each gets its own card, exactly
-- like the food realm's own hub). Empty table (direct join, nothing carried over) ->
-- the full catalog shows locked, which is the correct "go earn them" read.
local latestFoodPets = {}
-- Each page owns a header-subtitle string (the section titles sit behind the tab bar,
-- so the subtitle is where the collection counter actually shows). The tab entry
-- points swap between these; the rebuilds keep them fresh.
local subtitleDino = "Your pets & quest progress"
local subtitleFood = "Food Realm collection \xE2\x80\x94 return there to hatch & level"
local function rebuildFoodPets(spacePets)
	local ok, err = pcall(function()
		if type(spacePets) == "table" then latestFoodPets = spacePets end
		-- drop queued icon builds for the food cards we're about to destroy
		for i = #iconQueue, 1, -1 do
			local q = iconQueue[i]
			if q.vp and (not q.vp.Parent or q.vp:IsDescendantOf(foodScroll)) then table.remove(iconQueue, i) end
		end
		for _, c in ipairs(foodScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local ownedNormal, ownedRare = {}, {}
		for skey, v in pairs(latestFoodPets) do
			if type(skey) == "string" and type(v) == "table" then
				if skey:sub(-2) == "#R" then ownedRare[skey:sub(1, -3)] = v else ownedNormal[skey] = v end
			end
		end
		local order, cards, ownedSpecies = 0, 0, 0
		for i, entry in ipairs(FOOD_CATALOG) do
			local n, r = ownedNormal[entry.key], ownedRare[entry.key]
			if n or r then ownedSpecies = ownedSpecies + 1 end
			if r then order = order + 1; cards = cards + 1; pcall(buildFoodOwnedCard, entry, r, true, order) end
			if n then order = order + 1; cards = cards + 1; pcall(buildFoodOwnedCard, entry, n, false, order) end
			if not n and not r then order = order + 1; cards = cards + 1; pcall(buildFoodLockedCard, entry, order, i) end
		end
		foodScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(cards / 2) * 264 + 20)
		if foTitle then foTitle.Text = ("\xF0\x9F\x8D\x94 PETS   %d / %d"):format(ownedSpecies, #FOOD_CATALOG) end
		subtitleFood = ("Food Realm collection  %d / %d \xE2\x80\x94 return there to hatch & level"):format(ownedSpecies, #FOOD_CATALOG)
		if foodOverlay.Visible then pcall(function() subtitle.Text = subtitleFood end) end
		print(("[PetInv] FOOD tab: %d/%d species owned (%d cards)"):format(ownedSpecies, #FOOD_CATALOG, cards))
		-- keep an open FOOD detail page live when a fresh pet table lands
		if detailIsFood and detailPage and detailPage.Visible and rebuildDetail then pcall(rebuildDetail) end
	end)
	if not ok then warn("[PetInv] ERROR building food pets: " .. tostring(err)) end
end
-- ============================================================================
-- SPACE REALM PET CARDS (the SPACE tab). Same 322x252 cell and layout rhythm as the FOOD cards, in the Space
-- Realm's navy. Read-only: these pets equip and level in the Space Realm, so no EQUIP row and no detail page
-- (the detail page is built around this realm's own pets and the food catalog). No emoji in the text -- this
-- realm's UI fonts render them as tofu; the emoji only stands in as the viewport placeholder while the
-- template builds, the same as FOOD.
-- ============================================================================
function SPACE.icon(card, entry, level)
	local vp = makeViewportIcon(card, entry.key, level, false, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	vp.BackgroundColor3 = Color3.fromRGB(14,22,46)
	local ph = vp:FindFirstChild("IconPlaceholder"); if ph and entry.emoji then ph.Text = entry.emoji end
	return vp
end
function SPACE.text(card, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold
	for k, v in pairs(props) do l[k] = v end
	l.Parent = card; return l
end
-- one OWNED space pet: Space tier word + level, XP bar on Space's curve, pointer home.
function SPACE.ownedCard(entry, p, order)
	local level = math.clamp(tonumber(p.level) or 1, 1, 25)
	local tierName, tierColor = SPACE.tier(level)
	local card = Instance.new("Frame"); card.Name = "Space_" .. entry.key; card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(26,38,74); card.Parent = SPACE.scroll
	uicorner(card, 12); uistroke(card, Color3.fromRGB(62,90,160), 1)
	SPACE.icon(card, entry, level)
	SPACE.text(card, { Size = UDim2.new(1,-16,0,18), Position = UDim2.new(0,8,0,150), TextSize = 16,
		TextColor3 = Color3.new(1,1,1), Text = entry.displayName })
	SPACE.text(card, { Size = UDim2.new(1,-16,0,16), Position = UDim2.new(0,8,0,170), TextSize = 13,
		TextColor3 = tierColor, Text = tierName .. "  Lv " .. level })
	local maxed = level >= 25
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-16,0,14); barBG.Position = UDim2.new(0,8,0,188)
	barBG.BackgroundColor3 = Color3.fromRGB(14,22,46); barBG.BorderSizePixel = 0; barBG.Parent = card
	uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(10,16,34), 1)
	local need = SPACE.xpNeeded(level)
	local frac = maxed and 1 or math.clamp((tonumber(p.xp) or 0) / math.max(1, need), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	SPACE.text(barBG, { Size = UDim2.new(1,0,1,0), TextSize = 10, TextColor3 = Color3.new(1,1,1),
		Text = maxed and "MAX" or (math.floor(tonumber(p.xp) or 0) .. " / " .. need .. " XP") })
	local home = SPACE.text(card, { Size = UDim2.new(1,-16,0,26), Position = UDim2.new(0,8,0,208), TextSize = 12,
		TextColor3 = Color3.new(1,1,1), Text = "EQUIP & LEVEL IN THE SPACE REALM" })
	home.BackgroundTransparency = 0; home.BackgroundColor3 = Color3.fromRGB(62,90,160)
	uicorner(home, 8); uistroke(home, Color3.fromRGB(20,32,70), 1)
	SPACE.text(card, { Size = UDim2.new(1,-16,0,14), Position = UDim2.new(0,8,0,236), Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = Color3.fromRGB(150,190,255), Text = "Earned on " .. entry.where })
end
-- one LOCKED space pet: full-colour picture, gold border + gold LOCKED line, and the task that earns it.
function SPACE.lockedCard(entry, order, idx)
	local card = Instance.new("Frame"); card.Name = "SpaceLocked_" .. entry.key; card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(26,38,74); card.Parent = SPACE.scroll
	uicorner(card, 12); uistroke(card, Color3.fromRGB(255,190,60), 2)
	SPACE.icon(card, entry, 1)
	local badge = SPACE.text(card, { Size = UDim2.new(0,66,0,20), Position = UDim2.new(1,-12,0,12), AnchorPoint = Vector2.new(1,0),
		TextSize = 11, TextColor3 = Color3.fromRGB(60,40,0), Text = "LOCKED", ZIndex = 3 })
	badge.BackgroundTransparency = 0; badge.BackgroundColor3 = Color3.fromRGB(255,190,60); uicorner(badge, 6)
	SPACE.text(card, { Size = UDim2.new(1,-16,0,18), Position = UDim2.new(0,8,0,150), TextSize = 16,
		TextColor3 = Color3.new(1,1,1), Text = entry.displayName })
	SPACE.text(card, { Size = UDim2.new(1,-16,0,16), Position = UDim2.new(0,8,0,170), TextSize = 13,
		TextColor3 = Color3.fromRGB(255,205,90), Text = "LOCKED  \xE2\x80\xA2  " .. entry.where })
	SPACE.text(card, { Size = UDim2.new(1,-20,0,14), Position = UDim2.new(0,10,0,188), Font = Enum.Font.Gotham, TextSize = 12,
		TextColor3 = Color3.fromRGB(150,190,255), TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Space Realm   \xC2\xB7   Pet " .. tostring(idx) .. " of " .. #SPACE.CATALOG })
	SPACE.text(card, { Size = UDim2.new(1,-20,0,26), Position = UDim2.new(0,10,0,204), Font = Enum.Font.Gotham, TextSize = 12,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(205,222,255),
		Text = "In the Space Realm, " .. entry.task .. " on " .. entry.where .. " to earn this pet" })
	local more = SPACE.text(card, { Size = UDim2.new(1,-16,0,20), Position = UDim2.new(0,8,0,230), TextSize = 12,
		TextColor3 = Color3.new(1,1,1), Text = "COLLECT IN THE SPACE REALM" })
	more.BackgroundTransparency = 0; more.BackgroundColor3 = Color3.fromRGB(150,110,30)
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90,66,16), 1)
end
-- Repaint the SPACE grid from the rift pet table (the same table FOOD reads). Empty (direct join) -> all 4 locked.
function SPACE.rebuild(t)
	local ok, err = pcall(function()
		if type(t) == "table" then SPACE.latest = t end
		for i = #iconQueue, 1, -1 do
			local q = iconQueue[i]
			if q.vp and (not q.vp.Parent or q.vp:IsDescendantOf(SPACE.scroll)) then table.remove(iconQueue, i) end
		end
		for _, c in ipairs(SPACE.scroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local owned = 0
		for i, entry in ipairs(SPACE.CATALOG) do
			local p = SPACE.latest[entry.key]
			if type(p) == "table" then owned = owned + 1; pcall(SPACE.ownedCard, entry, p, i)
			else pcall(SPACE.lockedCard, entry, i, i) end
		end
		SPACE.scroll.CanvasSize = UDim2.new(0,0,0, math.ceil(#SPACE.CATALOG / 2) * 264 + 20)
		if SPACE.title then SPACE.title.Text = ("\xF0\x9F\x9A\x80 PETS   %d / %d"):format(owned, #SPACE.CATALOG) end
		SPACE.subtitle = ("Space Realm collection  %d / %d \xE2\x80\x94 return there to equip & level"):format(owned, #SPACE.CATALOG)
		if SPACE.overlay.Visible then pcall(function() subtitle.Text = SPACE.subtitle end) end
		print(("[PetInv] SPACE tab: %d/%d species owned"):format(owned, #SPACE.CATALOG))
	end)
	if not ok then warn("[PetInv] ERROR building space pets: " .. tostring(err)) end
end
SPACE.rebuild({}) -- paint the full locked catalog immediately; live data overwrites it
rebuildFoodPets({}) -- paint the full locked catalog immediately; live data overwrites it
task.spawn(function()
	local ev = RS:FindFirstChild("FoodPetsEvent") or RS:WaitForChild("FoodPetsEvent", 20)
	if not ev then return end -- no server half -> the locked catalog stands
	ev.OnClientEvent:Connect(function(t) rebuildFoodPets(t); SPACE.rebuild(t) end) -- one rift table feeds FOOD and SPACE
	pcall(function() ev:FireServer() end) -- request (covers this script loading after the arrival push)
end)

-- ============================================================================
-- PET DETAIL PAGE -- opens from 🔍 VIEW on an owned card (or the card itself) and
-- from 🔒 VIEW QUEST on a locked one. A PAGE, not a popup: same panel, same header,
-- same tab bar -- only the body swaps (petsSection hides, this shows). Ported from
-- the Space Realm's PetDetailPage_Look.md, recoloured into this hub's jungle
-- palette. One pet on a lit stage wearing its EQUIPPED skin, an info panel beside
-- it (tier / XP / tier-skip), and that pet's SKINS grid underneath -- without this
-- page a skin can be won in the crates and never worn.
-- ============================================================================
do
	local D_GOLD, D_INSET, D_EDGE, D_NAV = Color3.fromRGB(255,215,0), Color3.fromRGB(20,42,24), Color3.fromRGB(74,94,68), Color3.fromRGB(34,74,40)
	local D_SUBTLE, D_GREY, D_GREEN, D_LOCKGOLD = Color3.fromRGB(185,212,255), Color3.fromRGB(120,120,120), Color3.fromRGB(80,220,120), Color3.fromRGB(255,205,90)
	local WHITE = Color3.new(1,1,1)
	local function dlabel(parent, props)
		local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent; return l
	end

	detailPage = Instance.new("Frame")
	detailPage.Name = "DetailPage"; detailPage.BackgroundTransparency = 1
	detailPage.Position = UDim2.new(0, 12, 0, 110); detailPage.Size = UDim2.new(1, -24, 1, -116) -- same band as the quests/trade overlays
	detailPage.Visible = false; detailPage.ZIndex = 3; detailPage.Parent = panel

	local backBtn = Instance.new("TextButton"); backBtn.Size = UDim2.new(0,132,0,30); backBtn.Position = UDim2.new(0,10,0,8)
	backBtn.BackgroundColor3 = D_GREY; backBtn.Text = "\xE2\x97\x80 Back to Pets"; backBtn.Font = Enum.Font.GothamBold
	backBtn.TextSize = 14; backBtn.TextColor3 = WHITE; backBtn.ZIndex = 8; backBtn.Parent = detailPage
	uicorner(backBtn, 8); uistroke(backBtn, Color3.new(0,0,0), 2)

	local detailTitle = dlabel(detailPage, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 26, TextColor3 = D_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1,-160,0,30), Position = UDim2.new(0,152,0,8), ZIndex = 8 })
	uistroke(detailTitle, Color3.fromRGB(18,38,20), 2)

	-- THE STAGE. The soft glow and the pedestal are plain Frames in the panel's own
	-- palette, so the pet reads as standing on something rather than floating in a box.
	local stage = Instance.new("Frame"); stage.Size = UDim2.new(0,268,0,140); stage.Position = UDim2.new(0,10,0,46)
	stage.BackgroundColor3 = D_INSET; stage.BorderSizePixel = 0; stage.ZIndex = 6; stage.Parent = detailPage
	uicorner(stage, 10); uistroke(stage, D_EDGE, 2)
	do
		local glow = Instance.new("Frame"); glow.Size = UDim2.fromOffset(150,150); glow.Position = UDim2.new(0.5,0,0.52,0)
		glow.AnchorPoint = Vector2.new(0.5,0.5); glow.BackgroundColor3 = D_GOLD; glow.BackgroundTransparency = 0.88
		glow.BorderSizePixel = 0; glow.ZIndex = 6; glow.Parent = stage
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1,0); gc.Parent = glow
		local ped = Instance.new("Frame"); ped.Size = UDim2.fromOffset(150,14); ped.Position = UDim2.new(0.5,0,1,-14)
		ped.AnchorPoint = Vector2.new(0.5,0); ped.BackgroundColor3 = Color3.fromRGB(12,28,16); ped.BorderSizePixel = 0; ped.ZIndex = 6; ped.Parent = stage
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1,0); pc.Parent = ped
	end
	local detailPreview = Instance.new("ViewportFrame"); detailPreview.Name = "Icon3D"
	detailPreview.Size = UDim2.new(1,-16,1,-22); detailPreview.Position = UDim2.new(0,8,0,4)
	detailPreview.BackgroundTransparency = 1 -- the stage behind it IS the backdrop
	detailPreview.ZIndex = 7
	detailPreview.Ambient = Color3.fromRGB(185,185,195); detailPreview.LightColor = Color3.fromRGB(255,255,255); detailPreview.LightDirection = Vector3.new(-0.4,-1,-0.5)
	detailPreview.Parent = stage
	local detailChain = { stage, detailPage } -- the spinner's page-visibility cull walks this

	-- INFO PANEL, right of the stage: what this pet is, what it's wearing, the skip offer.
	local info = Instance.new("Frame"); info.Size = UDim2.new(1,-296,0,140); info.Position = UDim2.new(0,288,0,46)
	info.BackgroundColor3 = D_INSET; info.BackgroundTransparency = 0.25; info.BorderSizePixel = 0; info.ZIndex = 6; info.Parent = detailPage
	uicorner(info, 10); uistroke(info, D_EDGE, 2)
	dlabel(info, { Text = "EQUIPPED", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = D_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1,-20,0,14), Position = UDim2.new(0,10,0,6), ZIndex = 7 })
	local detailWearing = dlabel(info, { Text = "Default", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1,-20,0,20), Position = UDim2.new(0,10,0,22), ZIndex = 7 })
	local detailTier = dlabel(info, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = D_SUBTLE,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1,-20,0,16), Position = UDim2.new(0,10,0,48), ZIndex = 7 })
	local detailXP = dlabel(info, { Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = D_SUBTLE,
		TextXAlignment = Enum.TextXAlignment.Left,
		-- Top-aligned because the LOCKED branch grows this to 60px + wraps it for the
		-- unlock sentence; at the owned single-line height Top and Center look the same.
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1,-20,0,14), Position = UDim2.new(0,10,0,66), ZIndex = 7 })
	local skipBtn = Instance.new("TextButton"); skipBtn.Name = "BuyNextLevel"; skipBtn.Size = UDim2.new(1,-20,0,32); skipBtn.Position = UDim2.new(0,10,0,92)
	skipBtn.BackgroundColor3 = Color3.fromRGB(255,170,40); skipBtn.Font = Enum.Font.GothamBold; skipBtn.TextSize = 14
	skipBtn.TextColor3 = WHITE; skipBtn.Text = ""; skipBtn.Visible = false; skipBtn.ZIndex = 7; skipBtn.Parent = info
	uicorner(skipBtn, 8); uistroke(skipBtn, Color3.new(0,0,0), 2)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 14; c.Parent = skipBtn end

	dlabel(detailPage, { Text = "SKINS", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = D_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0,200,0,16), Position = UDim2.new(0,10,0,194), ZIndex = 7 })
	local skinList = Instance.new("ScrollingFrame"); skinList.BackgroundTransparency = 1; skinList.BorderSizePixel = 0
	skinList.Position = UDim2.new(0,10,0,214); skinList.Size = UDim2.new(1,-20,1,-222)
	skinList.ScrollBarThickness = 6; skinList.ScrollBarImageColor3 = D_GOLD
	skinList.CanvasSize = UDim2.new(0,0,0,0); skinList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	skinList.ZIndex = 4; skinList.Parent = detailPage
	do
		local grid = Instance.new("UIGridLayout"); grid.CellSize = UDim2.new(0,150,0,66); grid.CellPadding = UDim2.new(0,8,0,8)
		grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = skinList
	end

	-- owned-skin enumeration (SkinCrate inventory keys are "pet|skin|trait")
	local function ownedSkinEntries(petId)
		local out = {}
		local st = _G.petSkinState
		if not (st and type(st.skins) == "table") then return out end
		for skey, count in pairs(st.skins) do
			if (tonumber(count) or 0) > 0 then
				local kp, ks, kt = string.match(tostring(skey), "^([^|]+)|([^|]*)|?([^|]*)$")
				if kp == petId and ks and ks ~= "" then
					out[#out+1] = { skin = ks, trait = (kt ~= "" and kt or nil), count = tonumber(count) or 1 }
				end
			end
		end
		table.sort(out, function(a, b)
			if a.skin ~= b.skin then return a.skin < b.skin end
			return tostring(a.trait) < tostring(b.trait)
		end)
		return out
	end

	-- Stage preview, routed through the shared icon worker + spinner (build cost stays off
	-- the click; camera-orbit spin and the page-visibility cull come free). Skipped when
	-- nothing changed, so the throttled inventory pushes don't re-clone the model mid-look.
	local lastPrev = {}
	local function fillDetailPreview(petId, isRare, skinId, traitId)
		if lastPrev.pet == petId and lastPrev.skin == skinId and lastPrev.trait == traitId
			and detailPreview:FindFirstChildWhichIsA("Model") then return end
		lastPrev = { pet = petId, skin = skinId, trait = traitId }
		for i = #iconQueue, 1, -1 do if iconQueue[i].vp == detailPreview then table.remove(iconQueue, i) end end
		for i = #iconSpins, 1, -1 do if iconSpins[i].vp == detailPreview then table.remove(iconSpins, i) end end
		detailPreview:ClearAllChildren()
		local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = detailPreview; detailPreview.CurrentCamera = cam
		iconQueue[#iconQueue + 1] = { vp = detailPreview, cam = cam, petId = petId, level = 1,
			isRare = isRare and true or false, chain = detailChain, skin = skinId, trait = traitId }
		startIconWorker()
	end

	rebuildDetail = function()
		if not detailSpecies then return end
		local petId = detailSpecies
		-- FOOD REALM pets read from a different inventory + catalog and use that realm's
		-- AGE vocabulary. Everything else on the page is shared.
		local owned, entry
		if detailIsFood then
			-- the "#R" rare entry wins the page when both variants are owned, same as its card
			owned = latestFoodPets[petId .. "#R"] or latestFoodPets[petId]
			for _, e in ipairs(FOOD_CATALOG) do if e.key == petId then entry = e; break end end
		else
			owned = latestInv.owned and latestInv.owned[petId] or nil
			for _, e in ipairs(PET_CATALOG) do if e.key == petId then entry = e; break end end
		end
		local displayName = (owned and owned.displayName) or (entry and entry.displayName) or petId

		local eqAll = _G.petSkinState and _G.petSkinState.equipped
		local eq = (not detailIsFood) and eqAll and eqAll[petId] or nil -- food pets' skins live in the Food Realm
		if eq and (type(eq) ~= "table" or not eq.skin) then eq = nil end
		local eqTrait = eq and eq.trait ~= "" and eq.trait or nil

		if detailIsFood then
			local isRare = latestFoodPets[petId .. "#R"] ~= nil
			if owned then
				local level = math.clamp(tonumber(owned.level) or 1, 1, 25)
				local ageName, ageColor = foodAge(level, isRare, petId)
				detailTitle.Text = isRare and (FOOD_RARE_NAMES[petId] or displayName) or displayName
				detailTier.TextColor3 = ageColor
				detailTier.Text = isRare and ageName or (ageName .. "  \xE2\x80\xA2  Level " .. level)
				detailXP.TextWrapped = false
				detailXP.Size = UDim2.new(1,-20,0,14)
				local need = foodXpNeeded(level)
				detailXP.Text = (level >= 25) and "MAX LEVEL"
					or ("%d / %d XP to level %d"):format(math.floor(tonumber(owned.xp) or 0), need, level + 1)
			else
				detailTitle.Text = displayName
				detailTier.TextColor3 = D_LOCKGOLD
				detailTier.Text = "\xF0\x9F\x94\x92 LOCKED" .. (entry and entry.where and ("  \xE2\x80\xA2  " .. entry.where) or "")
				detailXP.TextWrapped = true
				detailXP.Size = UDim2.new(1,-20,0,60)
				detailXP.Text = (entry and entry.secret)
					and "Return to the Food Realm and collect all 10 pets to unlock this secret pet."
					or "Return to the Food Realm to complete this pet's quest."
			end
			-- these pets can't be equipped, levelled or skinned HERE -- their catalog isn't
			-- this game's -- so the wearing line and the skip offer both point home instead.
			detailWearing.Text = "\xF0\x9F\x8D\x94 Food Realm pet"
			skipBtn.Visible = false
		elseif owned then
			local cap = tonumber(owned.maxLevel) or 25
			local level = math.clamp(tonumber(owned.level) or 1, 1, cap)
			local tierName, tierColor, isVariant = petTier(level, owned.rare, petId)
			detailTitle.Text = owned.rare and (owned.rareName or displayName) or displayName
			detailTier.TextColor3 = tierColor
			detailTier.Text = isVariant and tierName or (tierName .. "  \xE2\x80\xA2  Level " .. level)
			detailXP.TextWrapped = false
			detailXP.Size = UDim2.new(1,-20,0,14)
			local maxed = level >= cap
			detailXP.Text = maxed and "MAX LEVEL"
				or ("%d / %d XP to level %d"):format(math.floor(tonumber(owned.xp) or 0), tonumber(owned.xpNeed) or 0, level + 1)
			-- same bracket rule as the card's SKIP button; the placeholder ids match the server's
			local skipStep = not maxed and ((level <= 5 and PET_SKIP_PRODUCTS[1]) or (level <= 10 and PET_SKIP_PRODUCTS[2])
				or (level <= 15 and PET_SKIP_PRODUCTS[3]) or (level <= 20 and PET_SKIP_PRODUCTS[4])) or nil
			if skipStep then
				skipBtn.Visible = true
				skipBtn.Text = ("\xE2\xAC\x86 SKIP TO %s \xE2\x80\x94 %d R$"):format(string.upper(skipStep.to), skipStep.price)
			else
				skipBtn.Visible = false -- top tier / rare: nothing left to skip to
			end
		else
			-- LOCKED: this page is what VIEW QUEST opens, so it carries the how-to rather
			-- than an empty stat block.
			detailTitle.Text = displayName
			detailTier.TextColor3 = D_LOCKGOLD
			detailTier.Text = "\xF0\x9F\x94\x92 LOCKED" .. (entry and entry.island and ("  \xE2\x80\xA2  " .. entry.island) or "")
			detailXP.TextWrapped = true
			detailXP.Size = UDim2.new(1,-20,0,60)
			detailXP.Text = entry and (entry.how .. " on " .. entry.island .. " to hatch this pet.")
				or "Keep exploring to find this pet."
			skipBtn.Visible = false
		end

		-- what it's wearing, named the way the crate panel names it so they can't disagree
		if detailIsFood then
			-- already set by the food branch above
		elseif eq then
			local nm = eq.skin
			if _G.petSkinMeta then
				local ok, m = pcall(_G.petSkinMeta, eq.skin)
				if ok and type(m) == "table" and m.name then nm = m.name end
			end
			detailWearing.Text = nm .. (eqTrait and ("  \xC2\xB7  " .. tostring(eqTrait)) or "")
		else
			detailWearing.Text = "Default"
		end

		fillDetailPreview(petId, (not detailIsFood) and owned and owned.rare, eq and eq.skin or nil, eqTrait)

		for _, ch in ipairs(skinList:GetChildren()) do
			if not ch:IsA("UIGridLayout") then ch:Destroy() end
		end
		local function cell(orderN, label, sub, active, tint, onClick)
			local b = Instance.new("TextButton"); b.LayoutOrder = orderN; b.BackgroundColor3 = D_NAV; b.Text = ""
			b.AutoButtonColor = true; b.ZIndex = 5; b.Parent = skinList
			uicorner(b, 10)
			-- equipped reads as a GREEN border at 2.5, unequipped as its tier colour at 1.5
			uistroke(b, active and D_GREEN or (tint or D_EDGE), active and 2.5 or 1.5)
			dlabel(b, { Text = label, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHITE,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1,-16,0,16), Position = UDim2.new(0,8,0,8), ZIndex = 6 })
			dlabel(b, { Text = sub, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = tint or D_SUBTLE,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1,-16,0,14), Position = UDim2.new(0,8,0,26), ZIndex = 6 })
			dlabel(b, { Text = active and "\xE2\x9C\x94 EQUIPPED" or "TAP TO WEAR", Font = Enum.Font.GothamBold, TextSize = 11,
				TextColor3 = active and D_GREEN or D_SUBTLE, TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1,-16,0,14), Position = UDim2.new(0,8,1,-20), ZIndex = 6 })
			b.MouseButton1Click:Connect(onClick)
			return b
		end

		-- FOOD REALM pets: this realm's crates don't stock their skins and its equip remote
		-- doesn't know them, so offering cells here would be a dead end. Say where they live.
		if detailIsFood then
			dlabel(skinList, { Text = "This pet's skins live in the Food Realm \xE2\x80\x94 open crates and wear them there.",
				Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = D_SUBTLE, TextWrapped = true,
				Size = UDim2.new(1,-8,0,40), ZIndex = 5 })
			return
		end

		-- DEFAULT first, always: clearing a skin has to be as reachable as setting one,
		-- or a player who dislikes a look is stuck with it.
		cell(1, "Default", "the pet's natural look", eq == nil, nil, function()
			if _G.skinEquip then pcall(_G.skinEquip, petId, false, false) end
		end)
		local entries = ownedSkinEntries(petId)
		for i, e in ipairs(entries) do
			local meta
			if _G.petSkinMeta then
				local ok, m = pcall(_G.petSkinMeta, e.skin)
				if ok then meta = m end
			end
			local name = (type(meta) == "table" and meta.name) or e.skin
			local tint = (type(meta) == "table" and meta.tierColor) or nil
			local sub = (e.trait and (tostring(e.trait) .. "  \xE2\x80\xA2  ") or "") .. ((type(meta) == "table" and meta.tier) or "skin")
			if e.count > 1 then sub = sub .. ("  x%d"):format(e.count) end
			local active = (eq ~= nil and eq.skin == e.skin and eqTrait == e.trait)
			cell(i + 1, name, sub, active, tint, function()
				if _G.skinEquip then pcall(_G.skinEquip, petId, e.skin, e.trait or false) end
			end)
		end
		if #entries == 0 then
			dlabel(skinList, { Text = "No skins for this pet yet \xE2\x80\x94 open a crate from the CRATES tab.",
				Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = D_SUBTLE, TextWrapped = true,
				Size = UDim2.new(1,-8,0,40), ZIndex = 5 })
		end
	end

	showDetail = function(petId, isFood)
		if type(petId) ~= "string" then return end
		detailSpecies = petId; detailIsFood = isFood and true or false
		-- SWAP pages, never stack -- the translucent sections bleed through each other.
		-- (TradeOverlay is looked up by name: its local is declared BELOW this block, so
		-- referencing it here would silently hit a nil global instead.)
		petsSection.Visible = false; foodOverlay.Visible = false; SPACE.overlay.Visible = false
		questsOverlay.Visible = false
		local tov = panel:FindFirstChild("TradeOverlay"); if tov then tov.Visible = false end
		detailPage.Visible = true
		rebuildDetail()
	end
	local function backToPets()
		detailPage.Visible = false; detailSpecies = nil; detailIsFood = false
		if _G.PetHubTabs then _G.PetHubTabs.select("pets") else petsSection.Visible = true end
	end
	backBtn.MouseButton1Click:Connect(backToPets)

	-- The button only says "skip this pet" -- the bracket is re-read from the pet's REAL
	-- level at click time, and PetPendingUpgradeEvent + the receipt validate server-side,
	-- so a stale label can never mean a wrong charge.
	skipBtn.MouseButton1Click:Connect(function()
		if not (detailSpecies and skipBtn.Visible) then return end
		local owned = latestInv.owned and latestInv.owned[detailSpecies]
		if not owned then return end
		local level = tonumber(owned.level) or 1
		local skipStep = (level <= 5 and PET_SKIP_PRODUCTS[1]) or (level <= 10 and PET_SKIP_PRODUCTS[2])
			or (level <= 15 and PET_SKIP_PRODUCTS[3]) or (level <= 20 and PET_SKIP_PRODUCTS[4]) or nil
		if not skipStep then return end
		if PetPendingUpgrade then pcall(function() PetPendingUpgrade:FireServer(detailSpecies) end) end
		task.wait(0.15)
		pcall(function() MarketplaceService:PromptProductPurchase(player, skipStep.id) end)
	end)

	-- Repaint on every server skin-state push -- the ✔ EQUIPPED tick appears only once the
	-- server has actually accepted the equip (round trip, never the local click). PetSkinLook
	-- already fires this hook on each push; chain any handler that was there first.
	local prevSkinsChanged = _G.petHubSkinsChanged
	_G.petHubSkinsChanged = function()
		if prevSkinsChanged then pcall(prevSkinsChanged) end
		if panel.Visible and detailPage.Visible then pcall(rebuildDetail) end
	end
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
		for i = #iconSpins, 1, -1 do -- only this grid's spinners; the FOOD tab keeps its own
			local m = iconSpins[i].model
			if not (m and m.Parent) or m:IsDescendantOf(petsScroll) then table.remove(iconSpins, i) end
		end
		for i = #iconQueue, 1, -1 do -- drop icon builds still queued for the cards we're about to destroy
			local q = iconQueue[i]
			if q.vp and (not q.vp.Parent or q.vp:IsDescendantOf(petsScroll)) then table.remove(iconQueue, i) end
		end
		for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
			local _pe = petsSection:FindFirstChild("PetsEmpty"); if _pe then _pe:Destroy() end -- legacy empty state (the grid is never empty now -- locked cards fill it)
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
		-- ===== EVERY OTHER PET IN THE REALM, LOCKED (realm 1 parity) =====
		-- The whole catalog is always on screen: owned first (best tier first), then the
		-- ones still to hatch as spinning-but-padlocked cards, in island climb order.
		local lockedCount = 0
		for i, entry in ipairs(PET_CATALOG) do
			if owned[entry.key] == nil then
				lockedCount = lockedCount + 1; order = order + 1
				local okl, el = pcall(buildLockedPetCard, entry, order, i)
				if not okl then warn("[PetInv] locked card build failed for " .. tostring(entry.key) .. ": " .. tostring(el)) end
			end
		end
		local totalCards = ownedCount + lockedCount
		-- the header subtitle doubles as the collection counter (the section's own title
		-- sits behind the PetHubTabs bar, so it can't carry it). Don't stomp the FOOD
		-- page's subtitle if that tab is the one on screen.
		subtitleDino = ("Collection  %d / %d hatched"):format(ownedCount, math.max(totalCards, #PET_CATALOG))
		if not foodOverlay.Visible and not SPACE.overlay.Visible then pcall(function() subtitle.Text = subtitleDino end) end
		print(("[PetInv] hub grid: %d owned + %d locked = %d cards"):format(ownedCount, lockedCount, totalCards))
		if totalCards == 0 then
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
		petsScroll.CanvasSize = UDim2.new(0,0,0, totalCards == 0 and 0 or (math.ceil(totalCards / 2) * 264 + 20))
		for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local qCount = 0
		for _, q in pairs(quests) do qCount = qCount + 1; pcall(buildQuestEntry, q, qCount) end
		questsEmpty.Visible = (qCount == 0)
		questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
		if detailPage and detailPage.Visible and rebuildDetail then pcall(rebuildDetail) end -- keep the open detail page's level/XP live
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
tradeBtn.Text = "\xF0\x9F\x94\x81 TRADE"; tradeBtn.Parent = header; uicorner(tradeBtn, 8); uistroke(tradeBtn, Color3.new(0,0,0), 2); gloss(tradeBtn); tradeBtn.Visible = false -- first-realm header: X only (the tab bar navigates)

local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1,-24,1,-116); tradeOverlay.Position = UDim2.new(0,12,0,110)
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
ovBack.MouseButton1Click:Connect(function()
	if _G.PetHubTabs then _G.PetHubTabs.select("pets"); return end
	tradeOverlay.Visible = false
end)
cancelBtn.MouseButton1Click:Connect(function() if PetTradeCancel then pcall(function() PetTradeCancel:FireServer() end) end end)
confirmBtn.MouseButton1Click:Connect(function() if PetTradeConfirm then pcall(function() PetTradeConfirm:FireServer() end) end end)
tradeBtn.MouseButton1Click:Connect(function()
	-- route through the tab bar when it exists, so the highlight and title move with the page
	if _G.PetHubTabs then _G.PetHubTabs.select("trade"); return end
	questsOverlay.Visible = false
	if tradeState and tradeState.active then tradeOverlay.Visible = true; renderTradeWindow(tradeState)
	else tradeOverlay.Visible = not tradeOverlay.Visible; if tradeOverlay.Visible then showPicker() end end
end)

local questsBtn = Instance.new("TextButton"); questsBtn.Size = UDim2.new(0,96,0,34); questsBtn.Position = UDim2.new(1,-252,0,13)
questsBtn.BackgroundColor3 = Color3.fromRGB(74,150,58); questsBtn.Font = Enum.Font.FredokaOne; questsBtn.TextSize = 15; questsBtn.TextColor3 = Color3.new(1,1,1)
questsBtn.Text = "\xF0\x9F\x97\xBA QUESTS"; questsBtn.Parent = header; uicorner(questsBtn, 8); uistroke(questsBtn, Color3.new(0,0,0), 2); gloss(questsBtn); questsBtn.Visible = false -- first-realm header: X only
questsBtn.MouseButton1Click:Connect(function()
	if _G.PetHubTabs then _G.PetHubTabs.select("quests"); return end
	tradeOverlay.Visible = false; questsOverlay.Visible = not questsOverlay.Visible
end)

----------------------------------------------------------------------
-- SET-state entry points for the tab bar (PetHubTabs.client.luau).
--
-- The header buttons above TOGGLE, which is wrong for a tab router: clicking the
-- already-active tab would close its own page and leave the highlight disagreeing
-- with what is on screen. These SET instead.
--
-- Trade also has to be *populated*, not just revealed. The overlay holds two
-- sub-views -- pickerView and windowView -- and the picker's list is filled by
-- refreshPicker(), which only showPicker() calls. Flipping tradeOverlay.Visible on
-- its own gives you an empty panel, which is what made the tab look like it had
-- failed until you clicked a second time.
----------------------------------------------------------------------
-- NOTE: petsSection and foodOverlay are BOTH translucent section frames on the same
-- band, so only ONE may be visible at a time -- the food page sitting on top of a
-- still-visible dino grid lets the dino cards bleed through its empty grid cells
-- (11 food cards -> the last row's right cell is a window straight onto the dino
-- grid's last card). The quests/trade overlays are opaque, so they just cover it.
_G.PetHubShowPets = function()
	SPACE.overlay.Visible = false
	if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false -- tab switch closes the detail page
	tradeOverlay.Visible = false
	questsOverlay.Visible = false
	foodOverlay.Visible = false
	petsSection.Visible = true
	title.Text = "PET HUB"; subtitle.Text = subtitleDino
end
_G.PetHubShowFood = function()
	SPACE.overlay.Visible = false
	if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false -- tab switch closes the detail page
	tradeOverlay.Visible = false
	questsOverlay.Visible = false
	petsSection.Visible = false -- swap, never stack (see note above)
	foodOverlay.Visible = true
	title.Text = "PET HUB"; subtitle.Text = subtitleFood -- named PETS like the food realm's own menu; the subtitle says which realm
end
_G.PetHubShowSpace = function()
	if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false -- tab switch closes the detail page
	tradeOverlay.Visible = false
	questsOverlay.Visible = false
	petsSection.Visible = false -- swap, never stack (see note above)
	foodOverlay.Visible = false
	SPACE.overlay.Visible = true
	title.Text = "PET HUB"; subtitle.Text = SPACE.subtitle
end
_G.PetHubShowQuests = function()
	SPACE.overlay.Visible = false
	if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false -- tab switch closes the detail page
	tradeOverlay.Visible = false
	foodOverlay.Visible = false
	petsSection.Visible = true
	questsOverlay.Visible = true
	title.Text = "PET HUB"; subtitle.Text = subtitleDino
end
_G.PetHubShowTrade = function()
	SPACE.overlay.Visible = false
	if detailPage then detailPage.Visible = false end; detailSpecies = nil; detailIsFood = false -- tab switch closes the detail page
	questsOverlay.Visible = false
	foodOverlay.Visible = false
	petsSection.Visible = true
	tradeOverlay.Visible = true
	title.Text = "PET HUB"; subtitle.Text = subtitleDino
	-- mid-trade: show the live window. Otherwise the player picker, refreshed.
	if tradeState and tradeState.active then renderTradeWindow(tradeState) else showPicker() end
end
qoBack.MouseButton1Click:Connect(function()
	if _G.PetHubTabs then _G.PetHubTabs.select("pets"); return end
	questsOverlay.Visible = false
end)

if PetTradeState then PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		openPanel(true); tradeOverlay.Visible = true; renderTradeWindow(state)
		title.Text = "PET HUB"
		if _G.PetHubTabs then pcall(function() _G.PetHubTabs.setActive("trade") end) end
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
-- Paint the grid straight away either way: with a server present this shows the full
-- LOCKED catalog immediately instead of a blank panel for the ~2.5s until the first
-- PetInventoryEvent lands (which then overwrites it with the real owned pets).
refreshClientInv()

print("[PetHub] ready -- MORE+ -> Pets toggles the Pet Hub (_G.togglePetHub / PetInvToggle)")
