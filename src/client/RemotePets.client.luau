--======================================================================
-- RemotePets.client.luau  (LocalScript)
--======================================================================
-- CROSS-PLAYER PET VISIBILITY: builds + follows a pet for every OTHER player in the server, so their
-- equipped pet is visible to everyone (not just its owner). The server (PetUpgrades.server.luau)
-- BROADCASTS each player's equipped-pet info via the "PetEquipBroadcast" RemoteEvent; this script
-- listens and renders a local copy of each remote pet on THIS client.
--
-- It NEVER touches the LOCAL player's own pet -- that stays 100% handled by PetFollow.client.luau
-- (we skip our own userId). The visual pipeline (size ramp / aura / trail / sparkles / animated FX /
-- accessories / gold+shimmer at 25) is REPLICATED from PetFollow so remote pets look identical, plus an
-- overhead nameplate (name + tier/level). Dino pets are rigid CSG unions -> the whole model rides the
-- follow PivotTo (no per-part organic animator; just eye blink + root FX), exactly like PetFollow.
--
-- Reuses the SAME server-fused Union templates already in ReplicatedStorage (StegosaurusTemplate, etc.).
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")
local Workspace  = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local PetEquipBroadcast = RS:WaitForChild("PetEquipBroadcast", 30)
if not PetEquipBroadcast then return end -- server publisher not present -> nothing to render

local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder

-- Same single theme PetFollow uses for the dino pets (teal + accessory anchors + schedule).
local THEME = {
	color = Color3.fromRGB(72,190,180),
	head  = CFrame.new(0.10, 1.62, 0),
	face  = CFrame.new(1.52, 0.14, 0), glassW = 0.44,
	neck  = CFrame.new(1.42, -0.55, 0),
	back  = CFrame.new(-1.30, 0.30, 0),
	side  = CFrame.new(0.30, -0.30, 1.35),
	side2 = CFrame.new(0.30, -0.30,-1.35),
	accs  = { {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"sparklecluster"},{23,"cane"} },
}
-- per-pet accessory schedules + rare body looks (must match PetFollow so remote pets look identical)
local PET_ACCS = {
	StegoPet         = { {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"sparklecluster"},{23,"cane"} },
	RaptorPet        = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"staff"} },
	SharkPet         = { {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"scarf"},{17,"anchor"},{20,"gemcluster"},{23,"sword"} },
	TriceratopsPet   = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"gemstuds"},{23,"staff"} },
	SpinosaurusPet   = { {3,"bell"},{7,"glasses"},{10,"safari"},{13,"scarf"},{17,"sword"},{20,"lantern"},{23,"pickaxe"} },
	TyrannosaurusPet = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"gemstuds"},{20,"sparklecluster"},{23,"cane"} },
}
local RARE_LOOK = {
	StegoPet         = { body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(70,255,150) },
	RaptorPet        = { body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(195,125,255) },
	SharkPet         = { body=Color3.fromRGB(200,232,255), mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(225,242,255), light=true },
	TriceratopsPet   = { body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,   refl=0.35, fx=Color3.fromRGB(255,225,90) },
	SpinosaurusPet   = { body=Color3.fromRGB(80,210,200),  mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(150,255,240) },
	TyrannosaurusPet = { body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true },
}

-- dino pet id -> ReplicatedStorage template / display name / rare name
local PET_TEMPLATE = {
	StegoPet="StegosaurusTemplate", RaptorPet="VelociraptorTemplate", SharkPet="SharkTemplate",
	TriceratopsPet="TriceratopsTemplate", SpinosaurusPet="SpinosaurusTemplate", TyrannosaurusPet="TyrannosaurusTemplate",
}
local PET_DISPLAY = {
	StegoPet="Stegosaurus", RaptorPet="Velociraptor", SharkPet="Megalodon",
	TriceratopsPet="Triceratops", SpinosaurusPet="Spinosaurus", TyrannosaurusPet="T-Rex",
}
local RARE_NAME = {
	StegoPet="Cosmic Stegosaurus", RaptorPet="Alpha Velociraptor", SharkPet="Ancient Megalodon",
	TriceratopsPet="Elder Triceratops", SpinosaurusPet="Swamp King Spinosaurus", TyrannosaurusPet="Volcano Tyrant Rex",
}
-- pets whose small welded balls (fins/frill/horns) separate when shrunk -> keep them full size (matches PetFollow)
local FULLSIZE = { SharkPet=true, TriceratopsPet=true, SpinosaurusPet=true, TyrannosaurusPet=true }

-- tier name + badge color for the nameplate. Rare -> Exotic (cyan), except the T-Rex rare = Mythical (magenta).
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "TyrannosaurusPet" then return "Mythical", Color3.fromRGB(255,70,230), true, true
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end
	end
	if level <= 5      then return "Common",    Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Uncommon",  Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Rare",      Color3.fromRGB(70,140,255),  false, false
	elseif level <= 20 then return "Epic",      Color3.fromRGB(180,90,235),  false, false
	else                    return "Legendary", Color3.fromRGB(255,170,40),  false, false end
end
local function petDisplayName(petId, isRare) return (isRare and RARE_NAME[petId]) or PET_DISPLAY[petId] or petId end

-- per-pet visual state
local petFX    = {} -- pet -> animated FX (orbs/ring/pulse/burst/shimmer)
local petScale = {} -- pet -> current sizeMul (FX orbit radius)
local petLevel = {} -- pet -> last applied level

-- ===== part factories (identical to PetFollow) =====
local function flagAccPart(p)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
local function accPart(pet, root, shape, sx, sy, sz, color, cf)
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * cf; p.Parent = pet
	return p
end
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end

-- ===== accessory builders (full set -- matches PetFollow) =====
local function buildAccessoryByKey(pet, root, theme, key, gold)
	local function A(shape, sx,sy,sz, color, cf) return accPart(pet, root, shape, sx,sy,sz, color, cf) end
	if key == "bowtie" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do A(BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		A(BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do A(CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "tophat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		A(CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		A(CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		A(CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "scarf" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		A(CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		A(BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "flower" then
		local e = theme.head; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); A(BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		A(BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sparklecluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=A(BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.45, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		A(CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		A(CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	elseif key == "bell" then
		A(CYL_, 1.5,0.22,0.22, gold and PRESTIGE_GOLD or Color3.fromRGB(170,45,55), theme.neck * CFrame.Angles(0,math.rad(90),0))
		A(BAL_, 0.42,0.46,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(212,176,80), theme.neck * CFrame.new(0.05,-0.34,0))
	elseif key == "backpack" then
		local b = theme.back; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(120,90,58)
		A(BLK_, 0.65,0.8,0.9, c, b)
		for _,sgn in ipairs({1,-1}) do A(BLK_, 0.55,0.12,0.16, gold and Color3.fromRGB(225,185,70) or Color3.fromRGB(88,64,40), b * CFrame.new(0.5,0.12,0.42*sgn)) end
	elseif key == "crown" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(212,182,66)
		A(CYL_, 0.16,1.05,1.05, c, h * CFrame.Angles(0,0,math.rad(90)))
		for i=0,4 do local ang=math.rad(i*72); A(CYL_, 0.5,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.42, 0.3, math.cos(ang)*0.42) * CFrame.Angles(0,0,math.rad(90))) end
	elseif key == "piratehat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(34,34,40)
		A(BAL_, 1.5,0.45,1.15, c, h)
		A(BAL_, 0.95,0.78,0.85, c, h * CFrame.new(-0.05,0.45,0))
		A(CYL_, 1.0,0.2,0.2, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(225,185,70), h * CFrame.new(0.45,0.05,0) * CFrame.Angles(0,math.rad(90),0))
	elseif key == "safari" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(156,138,96)
		A(CYL_, 0.12,1.5,1.5, c, h * CFrame.Angles(0,0,math.rad(90)))
		A(BAL_, 0.95,0.66,0.95, c, h * CFrame.new(0,0.34,0))
		A(CYL_, 0.2,0.92,0.92, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(110,92,60), h * CFrame.new(0,0.12,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "staff" then
		local s = theme.side
		A(CYL_, 1.7,0.14,0.14, Color3.fromRGB(120,84,46), s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=A(BAL_, 0.42,0.42,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90), s * CFrame.new(0,1.3,0)); p.Material=Enum.Material.Neon
	elseif key == "sword" then
		local s = theme.side; local blade = gold and PRESTIGE_GOLD or Color3.fromRGB(200,205,215)
		A(BLK_, 0.16,0.28,0.16, Color3.fromRGB(90,60,38), s)
		A(BLK_, 0.34,0.12,0.12, gold and PRESTIGE_GOLD or Color3.fromRGB(205,170,70), s * CFrame.new(0,0.16,0))
		A(BLK_, 0.14,1.0,0.14, blade, s * CFrame.new(0,0.7,0))
	elseif key == "anchor" then
		local s = theme.side2 or theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		A(CYL_, 1.0,0.14,0.14, c, s * CFrame.new(0,0.2,0) * CFrame.Angles(0,0,math.rad(90)))
		A(CYL_, 0.6,0.14,0.14, c, s * CFrame.new(0,0.6,0) * CFrame.Angles(math.rad(90),0,0))
		for _,sgn in ipairs({1,-1}) do A(BLK_, 0.4,0.14,0.14, c, s * CFrame.new(0.18*sgn,-0.2,0) * CFrame.Angles(0,0,math.rad(40*sgn))) end
	elseif key == "gemcluster" then
		local cols = { Color3.fromRGB(95,215,205), Color3.fromRGB(120,180,255), Color3.fromRGB(235,225,205) }
		for k=0,3 do local p=A(BAL_, 0.3,0.3,0.3, gold and PRESTIGE_GOLD or cols[(k%3)+1], theme.head * CFrame.new(-0.35+k*0.28, 0.3, -0.1+(k%2)*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "gemstuds" then
		for k=0,3 do local p=A(BAL_, 0.26,0.26,0.26, gold and PRESTIGE_GOLD or Color3.fromRGB(120,200,210), theme.back * CFrame.new(0, 0.25, -0.45+k*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "lantern" then
		local s = theme.side; local frame = gold and PRESTIGE_GOLD or Color3.fromRGB(90,72,46)
		A(CYL_, 0.16,0.1,0.1, frame, s * CFrame.new(0,0.55,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=A(BLK_, 0.5,0.6,0.5, Color3.fromRGB(255,225,110), s); p.Material=Enum.Material.Neon
		A(BLK_, 0.6,0.12,0.6, frame, s * CFrame.new(0,-0.34,0))
	elseif key == "pickaxe" then
		local s = theme.side2 or theme.side; local wood = Color3.fromRGB(120,84,46); local head = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		A(CYL_, 1.3,0.13,0.13, wood, s * CFrame.new(0,0.3,0) * CFrame.Angles(0,0,math.rad(90)))
		A(BLK_, 0.9,0.16,0.16, head, s * CFrame.new(0,0.85,0) * CFrame.Angles(0,0,math.rad(18)))
	end
end
-- ===== RARE variant body recolor (matches PetFollow) =====
local function applyRareLook(pet, root, petId)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="whitepartofeye" and n~="blackpartofeye" and n~="Glint" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				d.Color = r.body; d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(r.fx); rfx.LightEmission=0.85
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime=NumberRange.new(0.6,1.2); rfx.Rotation=NumberRange.new(0,360)
	rfx.Speed=NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size=NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent=root
	if r.light then local pl=Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=r.fx; pl.Brightness=3; pl.Range=12; pl.Parent=root end
	if petFX[pet] and r.cosmic then petFX[pet].cosmic = true end
end

-- ===== clear / fx (identical to PetFollow) =====
local function clearEvo(pet)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" or n=="PetRareFX" or n=="PetRareLight" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" then c:Destroy() end
	end
	petFX[pet] = nil
end
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25),
		orbR=2.0, orbH=0.45, ringR=2.2, ringY=0.3, ringTilt=22 }
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0)
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end end
	if level >= 18 then fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2) end
	if level >= 24 then
		local b = Instance.new("ParticleEmitter"); b.Name="PetBurst"; b.Color=ColorSequence.new(col)
		b.Rate=0; b.Lifetime=NumberRange.new(0.4,0.8); b.Speed=NumberRange.new(4,9); b.Size=NumberSequence.new(0.5)
		b.LightEmission=0.8; b.Rotation=NumberRange.new(0,360); b.Parent=root; fx.burst=b
	end
	petFX[pet] = fx
end

-- ===== overhead nameplate: pet name (rare tinted) + tier/level pill =====
local function updateNameplate(pet, root, petId, level, isRare)
	local bb = root:FindFirstChild("LevelTag")
	if not bb then
		bb = Instance.new("BillboardGui"); bb.Name="LevelTag"; bb.Size=UDim2.new(0,200,0,42)
		bb.StudsOffset=Vector3.new(0,3.7,0); bb.AlwaysOnTop=true; bb.MaxDistance=160; bb.Parent=root
		local lbl = Instance.new("TextLabel"); lbl.Name="L"; lbl.Size=UDim2.new(1,0,0,20); lbl.BackgroundTransparency=1
		lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=16; lbl.Parent=bb; Instance.new("UIStroke").Parent=lbl
		local tg = Instance.new("TextLabel"); tg.Name="Tag"; tg.AnchorPoint=Vector2.new(0.5,0); tg.Position=UDim2.new(0.5,0,0,22)
		tg.AutomaticSize=Enum.AutomaticSize.X; tg.Size=UDim2.new(0,0,0,16); tg.Font=Enum.Font.GothamBold; tg.TextSize=11; tg.TextColor3=Color3.new(1,1,1); tg.Parent=bb
		local pad=Instance.new("UIPadding", tg); pad.PaddingLeft=UDim.new(0,6); pad.PaddingRight=UDim.new(0,6)
		Instance.new("UICorner", tg).CornerRadius=UDim.new(0,5); Instance.new("UIStroke", tg)
	end
	local tierName, tierColor, isVariant, flashy = petTier(level, isRare, petId)
	bb.L.Text = petDisplayName(petId, isRare)
	bb.L.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	bb.Tag.Text = isVariant and tierName or (tierName .. "  Lv " .. tostring(level))
	bb.Tag.BackgroundColor3 = tierColor
	local stk = bb.Tag:FindFirstChildOfClass("UIStroke")
	if stk then
		if flashy then stk.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stk.Color=Color3.fromRGB(255,255,255); stk.Thickness=1; stk.Transparency=0.2
		else stk.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual; stk.Color=Color3.fromRGB(0,0,0); stk.Thickness=1; stk.Transparency=0.35 end
	end
end

-- ===== THE UPGRADE FUNCTION (dino version, cleaned of owner-only diagnostics) =====
local function applyLevelVisual(pet, petId, level, isRare)
	if not pet or not pet.PrimaryPart then return end
	level = level or 1
	if isRare then level = 25 end
	local root  = pet.PrimaryPart
	local theme = THEME
	local MAXL  = 25
	local frac  = math.clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = petLevel[pet]
	clearEvo(pet)
	local sizeMul = 0.6 + 0.4 * frac
	if FULLSIZE[petId] then sizeMul = 1.0 end
	petScale[pet] = sizeMul
	pcall(function() pet:ScaleTo(sizeMul) end)
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	if level >= 2 then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor=theme.color; hl.OutlineColor=theme.color
		hl.FillTransparency=math.clamp(0.8-0.45*t,0,1); hl.OutlineTransparency=math.clamp(0.4-0.4*t,0,1); hl.Parent=pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=2.5+4*t; pl.Range=8+8*t; pl.Parent=root
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	if level >= 5 then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color=ColorSequence.new(theme.color); tr.LightEmission=0.6; tr.Lifetime=0.5+1.1*t
		tr.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35-0.3*t,0,1)), NumberSequenceKeypoint.new(1,1) })
		tr.Parent=root
	end
	if level >= 8 then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"; pe.Rate=14+90*t; pe.LightEmission=0.7; pe.Rotation=NumberRange.new(0,360)
		pe.Lifetime=NumberRange.new(0.5,1.0); pe.Speed=NumberRange.new(0.6,1.6); pe.Size=NumberSequence.new(0.34); pe.Color=ColorSequence.new(theme.color)
		pe.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); pe.Parent=root
	end
	buildFX(pet, root, theme, level, atMax)
	local accs = PET_ACCS[petId] or theme.accs
	for _, e in ipairs(accs) do if level >= e[1] then buildAccessoryByKey(pet, root, theme, e[2], atMax) end end
	if isRare then applyRareLook(pet, root, petId) end
	updateNameplate(pet, root, petId, level, isRare)
	if prevLevel and level > prevLevel then
		local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
		burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
		burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root; burst:Emit(20); game:GetService("Debris"):AddItem(burst,1.1)
	end
	petLevel[pet] = level
end

-- ===== FX LOOP: orbit orbs, spin ring, pulse, periodic burst, MAX shimmer (all remote pets) =====
RunService.Heartbeat:Connect(function(dt)
	for pet, fx in pairs(petFX) do
		local root = pet.Parent and pet.PrimaryPart
		if root then
			fx.t = fx.t + dt; local t = fx.t; local rootCF = root.CFrame
			local sm = petScale[pet] or 1
			local n = #fx.orbs
			for i, orb in ipairs(fx.orbs) do
				local a = t*1.7 + (i-1)*(2*math.pi/math.max(1,n))
				orb.CFrame = rootCF * CFrame.new(math.cos(a)*fx.orbR*sm, fx.orbH*sm, math.sin(a)*fx.orbR*sm)
			end
			for _, seg in ipairs(fx.ring) do
				local a = t*1.9 + seg.base
				seg.part.CFrame = rootCF * CFrame.new(0, fx.ringY*sm, 0) * CFrame.Angles(math.rad(fx.ringTilt),0,0) * CFrame.new(math.cos(a)*fx.ringR*sm, 0, math.sin(a)*fx.ringR*sm)
			end
			if fx.pulse then
				local ph = (t % 1.3) / 1.3
				fx.pulse.Size = fx.pulseBase * (1 + ph*2.2) * sm
				fx.pulse.Transparency = math.clamp(ph,0,1)
				fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
			end
			if fx.burst then fx.burstClock = fx.burstClock - dt; if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end end
			if fx.cosmic then
				local cc = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
				local rl = root:FindFirstChild("PetRareLight"); if rl then rl.Color = cc end
				local rfx = root:FindFirstChild("PetRareFX"); if rfx then rfx.Color = ColorSequence.new(cc) end
			end
			if fx.shimmer then
				local hue = (t * 0.25) % 1; local c = Color3.fromHSV(hue, 0.45, 0.9)
				local hl = pet:FindFirstChild("LevelGlow"); if hl then hl.OutlineColor=c; hl.OutlineTransparency=0.25; hl.FillColor=c; hl.FillTransparency=0.88 end
				local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
				for _, orb in ipairs(fx.orbs) do orb.Color = c end
				for _, seg in ipairs(fx.ring) do seg.part.Color = c end
			end
		else
			petFX[pet] = nil
		end
	end
end)

-- ===== eye blink (Size.Y squash on whitepartofeye/blackpartofeye/Glint) per remote pet =====
local function applyBlink(pet)
	local eyes = {}
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name=="whitepartofeye" or d.Name=="blackpartofeye" or d.Name=="Glint") then
			eyes[#eyes+1] = { part=d, baseX=d.Size.X, baseY=d.Size.Y, baseZ=d.Size.Z }
		end
	end
	if #eyes == 0 then return end
	local blink = 1.5
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not pet.Parent then conn:Disconnect(); return end
		blink = blink - dt
		local eyeY = 1
		if blink <= 0 then
			local since = -blink
			if since < 0.16 then eyeY = 1 - 0.85 * (1 - math.abs((since/0.16)*2 - 1))
			else blink = 1.8 + math.random()*3.4 end
		end
		for _, e in ipairs(eyes) do if e.part.Parent then e.part.Size = Vector3.new(e.baseX, e.baseY*eyeY, e.baseZ) end end
	end)
end

-- ===== build a remote pet from a published template =====
local function buildPetModel(petId)
	local tn = PET_TEMPLATE[petId]
	local template = tn and (RS:FindFirstChild(tn) or RS:WaitForChild(tn, 4))
	if not template then warn("[RemotePets] template "..tostring(tn).." not replicated yet for "..tostring(petId)); return nil end
	local clone = template:Clone(); clone.Name = petId
	if clone.PrimaryPart ~= clone:FindFirstChild("Root") then clone.PrimaryPart = clone:FindFirstChild("Root") end
	if not clone.PrimaryPart then clone:Destroy(); return nil end
	return clone
end

--======================================================================
-- ===== REMOTE PET REGISTRY + FOLLOW (one pet per OTHER player) =====
--======================================================================
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)
local FOLLOW_K, FACE_K, MAX_TRAIL = 6, 4, 45

local remotePets = {} -- [userId] = { userId, player, petId, level, isRare, pet, smoothPos, smoothFwd, bobT, appliedLevel, appliedRare, facePlayer }

local function destroyEntryPet(entry)
	if entry.pet then
		petFX[entry.pet]=nil; petScale[entry.pet]=nil; petLevel[entry.pet]=nil
		pcall(function() entry.pet:Destroy() end)
		entry.pet = nil
	end
end
local function removeRemotePet(userId, reason)
	local entry = remotePets[userId]; if not entry then return end
	destroyEntryPet(entry); remotePets[userId] = nil
	print(("[RemotePets] removed remote pet for %s (%s)"):format(tostring(entry.playerName or userId), tostring(reason)))
end

local function buildEntryPet(entry)
	local pet = buildPetModel(entry.petId); if not pet then return false end
	pet.Name = "RemotePet_" .. tostring(entry.userId)
	pet.Parent = Workspace
	entry.pet = pet
	entry.appliedLevel = entry.level; entry.appliedRare = entry.isRare
	entry.facePlayer = (entry.petId == "SharkPet") or (entry.petId == "TriceratopsPet") -- turn its +X face toward its owner (like PetFollow)
	applyLevelVisual(pet, entry.petId, entry.level or 1, entry.isRare)
	applyBlink(pet)
	print(("[RemotePets] built %s's %s (lvl %s%s) -> following"):format(tostring(entry.playerName), tostring(entry.petId), tostring(entry.level or 1), entry.isRare and ", rare" or ""))
	return true
end

local function onBroadcast(info)
	if type(info) ~= "table" then return end
	local userId = info.userId
	if not userId or userId == localPlayer.UserId then return end -- own pet is PetFollow's job
	if not info.petId or info.petId == false then removeRemotePet(userId, "unequipped"); return end
	local plr = Players:GetPlayerByUserId(userId); if not plr then return end
	local entry = remotePets[userId]
	if entry and entry.pet and entry.petId == info.petId then
		entry.level = info.level; entry.isRare = info.isRare
		if entry.appliedLevel ~= info.level or entry.appliedRare ~= info.isRare then
			entry.appliedLevel = info.level; entry.appliedRare = info.isRare
			applyLevelVisual(entry.pet, info.petId, info.level or 1, info.isRare)
		end
		return
	end
	if entry then destroyEntryPet(entry) end
	entry = entry or {}
	entry.userId=userId; entry.player=plr; entry.playerName=plr.Name
	entry.petId=info.petId; entry.level=info.level; entry.isRare=info.isRare
	entry.smoothPos=nil; entry.smoothFwd=nil; entry.bobT=0
	remotePets[userId] = entry
	if not buildEntryPet(entry) then
		task.delay(2, function() if remotePets[userId] == entry and not entry.pet then buildEntryPet(entry) end end)
	end
end

PetEquipBroadcast.OnClientEvent:Connect(onBroadcast)
Players.PlayerRemoving:Connect(function(plr) removeRemotePet(plr.UserId, "left") end)

-- FOLLOW loop: each remote pet glides behind ITS player's character (re-read live each frame -> auto re-targets on respawn)
RunService.RenderStepped:Connect(function(dt)
	for _, entry in pairs(remotePets) do
		local pet = entry.pet
		if pet and pet.Parent and pet.PrimaryPart then
			local char = entry.player and entry.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)).Position
				if not entry.smoothPos then entry.smoothPos = targetPos end
				entry.smoothPos = entry.smoothPos:Lerp(targetPos, 1 - math.exp(-FOLLOW_K * dt))
				local back = entry.smoothPos - targetPos
				if back.Magnitude > MAX_TRAIL then entry.smoothPos = targetPos + back.Unit * MAX_TRAIL end
				entry.bobT = (entry.bobT or 0) + dt
				local renderPos = entry.smoothPos + Vector3.new(0, math.sin(entry.bobT * 1.4) * 0.10, 0)
				local vel = hrp.AssemblyLinearVelocity
				local moveDir = Vector3.new(vel.X, 0, vel.Z)
				local fwd
				if entry.facePlayer then fwd = hrp.Position - renderPos; fwd = Vector3.new(fwd.X, 0, fwd.Z)
				elseif moveDir.Magnitude > 2 then fwd = moveDir
				else fwd = hrp.Position - renderPos; fwd = Vector3.new(fwd.X, 0, fwd.Z) end
				if fwd.Magnitude < 0.05 then fwd = (entry.smoothFwd or Vector3.new(0,0,-1)) end
				fwd = fwd.Unit
				if not entry.smoothFwd then entry.smoothFwd = fwd end
				entry.smoothFwd = entry.smoothFwd:Lerp(fwd, 1 - math.exp(-FACE_K * dt))
				if entry.smoothFwd.Magnitude < 0.05 then entry.smoothFwd = fwd end
				local face = entry.smoothFwd.Unit
				pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0))
			end
		end
	end
end)

print("[RemotePets] online -- rendering other players' equipped pets (listening on PetEquipBroadcast)")
