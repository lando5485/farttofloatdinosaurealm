--======================================================================
-- PetFollow.client.luau  (LocalScript)
--======================================================================
-- Makes the hatched STEGOSAURUS pet FOLLOW the player and gain level-up
-- visuals + a trail -- behaviour from PET_MOVE_UPGRADES_TRAIL.md
-- (PetMoveUpgrades_AllInOne / PetFollow.client.lua), adapted for our pet:
--
--   * FOLLOW: eased spring glide to an offset behind/right/above you, a SLOWER
--     facing spring (swings round to turn), gentle bob, 45-stud max-trail clamp.
--   * UPGRADES (applyLevelVisual): SIZE 60%@Lv1 -> 100%@Lv25 (via Model:ScaleTo),
--     AURA@2, TRAIL@5, SPARKLES@8, ORBS@11/14/19, RING@15, PULSE@18, BURST@24,
--     GOLD + rainbow shimmer @25, and an accessory schedule (3/7/10/13/17/20/23).
--   * The pet is the ONE source of truth: a clone of ReplicatedStorage.StegosaurusTemplate
--     (same model the Pet Hub + hatch use). Because the body is a CSG union (rigid),
--     there is no per-part organic animator -- the whole model rides the follow PivotTo,
--     and all FX attach to the root.
--
-- It spawns when the egg hatches (QuestGate calls _G.SpawnStegoFollower(cf)).
-- Demo keys to watch the upgrades roll in:  ]  level +1   [  level -1   R  rare toggle
--======================================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Debris     = game:GetService("Debris")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder

-- Stego theme: color + accessory anchor CFrames (in the template's local/scaled space) + schedule.
local THEME = {
	color = Color3.fromRGB(72,190,180),
	head  = CFrame.new(0.10, 1.62, 0),     -- top of the cube (hats)
	face  = CFrame.new(1.52, 0.14, 0), glassW = 0.44,  -- over the eyes (glasses)
	neck  = CFrame.new(1.42, -0.55, 0),    -- front-lower (bowtie / scarf / bell)
	back  = CFrame.new(-1.30, 0.30, 0),    -- back (backpack)
	side  = CFrame.new(0.30, -0.30, 1.35), -- side (sword / cane)
	side2 = CFrame.new(0.30, -0.30,-1.35),
	accs  = { {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"sparklecluster"},{23,"cane"} },
}

-- Per-pet accessory schedules (levels 3/7/10/13/17/20/23) so each dino wears its own set.
local PET_ACCS = {
	StegoPet         = { {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"sparklecluster"},{23,"cane"} },
	RaptorPet        = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"staff"} },
	SharkPet         = { {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"scarf"},{17,"anchor"},{20,"gemcluster"},{23,"sword"} },
	TriceratopsPet   = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"gemstuds"},{23,"staff"} },
	SpinosaurusPet   = { {3,"bell"},{7,"glasses"},{10,"safari"},{13,"scarf"},{17,"sword"},{20,"lantern"},{23,"pickaxe"} },
	TyrannosaurusPet = { {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"gemstuds"},{20,"sparklecluster"},{23,"cane"} },
}
local PET_DISPLAY = { StegoPet="Stegosaurus", RaptorPet="Velociraptor", SharkPet="Megalodon", TriceratopsPet="Triceratops", SpinosaurusPet="Spinosaurus", TyrannosaurusPet="T-Rex", TherizinosaurusPet="Therizinosaurus", BrachiosaurusPet="Brachiosaurus" }
local RARE_NAME   = { StegoPet="Cosmic Stegosaurus", RaptorPet="Alpha Velociraptor", SharkPet="Ancient Megalodon", TriceratopsPet="Elder Triceratops", SpinosaurusPet="Swamp King Spinosaurus", TyrannosaurusPet="Volcano Tyrant Rex", TherizinosaurusPet="Scythe Lord", BrachiosaurusPet="Ancient Bonewalker" }
-- RARE variant body looks (glass/metal/cosmic). T-Rex = Mythical cosmic; the rest = Exotic.
local RARE_LOOK = {
	StegoPet         = { body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(70,255,150) },
	RaptorPet        = { body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(195,125,255) },
	SharkPet         = { body=Color3.fromRGB(200,232,255), mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(225,242,255), light=true },
	TriceratopsPet   = { body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,   refl=0.35, fx=Color3.fromRGB(255,225,90) },
	SpinosaurusPet   = { body=Color3.fromRGB(80,210,200),  mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(150,255,240) },
	TyrannosaurusPet = { body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true },
	TherizinosaurusPet = { body=Color3.fromRGB(40,120,130),  mat=Enum.Material.Glass, refl=0.25, fx=Color3.fromRGB(110,240,255) },
	BrachiosaurusPet   = { body=Color3.fromRGB(205,180,120), mat=Enum.Material.Metal, refl=0.35, fx=Color3.fromRGB(255,235,175) },
}
local function petIdFromName(name)
	name = tostring(name)
	-- Theri/Brachio FIRST: neither contains any of the substrings below, so without these two
	-- branches they hit the `return "StegoPet"` fallback at the bottom and every pet in the game
	-- that is not explicitly listed here silently becomes a Stegosaurus -- wrong nameplate,
	-- wrong rare look, wrong tier pill.
	if name:find("Theri") then return "TherizinosaurusPet"
	elseif name:find("Brachio") then return "BrachiosaurusPet"
	elseif name:find("Stego") then return "StegoPet"
	elseif name:find("Raptor") or name:find("Veloci") then return "RaptorPet"
	elseif name:find("Shark") or name:find("Megalo") then return "SharkPet"
	elseif name:find("Trice") then return "TriceratopsPet"
	elseif name:find("Spino") then return "SpinosaurusPet"
	elseif name:find("Tyranno") or name:find("Rex") then return "TyrannosaurusPet" end
	return "StegoPet"
end
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

-- per-pet state
local petFX    = {}   -- pet -> animated effect state (orbs/ring/pulse/burst/shimmer)
local petScale = {}   -- pet -> current sizeMul (for FX orbit radius)
local petLevel = {}   -- pet -> last applied level

-- ===== part factories =====
local function flagAccPart(p)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
-- accessory part: a model child placed at root.CFrame*cf -> it rides the follow PivotTo (stays attached)
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

-- ===== accessory builders (full set -- each pet's schedule picks 7 of these) =====
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

-- ===== clear / fx =====
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
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0) -- ORBS: 1@11, 2@14, 3@19
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

-- ===== RARE variant body recolor + rare particles/light =====
local function applyRareLook(pet, root, petId)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="whitepartofeye" and n~="blackpartofeye" and n~="Glint" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				-- a UNION ignores .Color while UsePartColor is false, and the pets are fused into
				-- exactly that (see PetFace.fuseAll) -- so the rare recolour has to flip it on or
				-- it would silently do nothing at all.
				if d:IsA("UnionOperation") then d.UsePartColor = true end
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

-- ===== THE UPGRADE FUNCTION =====
local function applyLevelVisual(pet, level, isRare)
	if not pet or not pet.PrimaryPart then return end
	level = level or 1
	if isRare then level = 25 end
	local root  = pet.PrimaryPart
	local theme = THEME
	local petId = petIdFromName(pet.Name)
	local MAXL  = 25
	local frac  = math.clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = petLevel[pet]
	clearEvo(pet)
	-- (1) SIZE 60% -> 100% via Model:ScaleTo -- this scales every part's SIZE *and* POSITION together about
	-- the pivot, so welded fins/tail keep the SAME overlap with the BodyUnion (no per-part separation).
	-- ===== NO SIZE RAMP. EVERY FOLLOWER IS FULL SIZE. =====
	-- This used to be `0.6 + 0.4 * frac`, so a level-1 pet spawned at 60%. Scaling is where the
	-- "looks fine in the Pet Hub, discombobulated when equipped" bug came from -- the hub icon is
	-- an unscaled clone of the template, the follower was a shrunken one, and shrinking BREAKS
	-- these models.
	--
	-- WHY IT BREAKS: Model:ScaleTo multiplies positions exactly, but Roblox CLAMPS a part's size
	-- at 0.05 studs. Every small detail -- a 0.07 claw, a 0.12 nostril dot, a 0.044 claw tip --
	-- hits that floor and stops shrinking while its position keeps moving inward. The part is
	-- then the wrong size for the socket it sits in and drifts out of it. On a pet built from
	-- chains of small welded pieces that is not subtle: the file's own note said the claws "pull
	-- off the hands and the pet ships as a body surrounded by floating splinters".
	--
	-- Six of the eight pets had already been exempted one at a time as each one broke. Stego and
	-- Raptor were the last two still shrinking. Rather than keep growing an exception list that
	-- was always going to end up containing everything, the ramp is gone: the follower is now a
	-- pixel-identical copy of what you see in the Hub, which is the whole ask.
	--
	-- Level progression still reads loud and clear through the aura, trail, sparkles, orbs, ring
	-- and rare sheen below -- none of which move geometry.
	local sizeMul = 1.0
	petScale[pet] = sizeMul
	local function gapReport(tag) -- prints a part's overlap with the BodyUnion (negative = gap)
		local bu = pet:FindFirstChild("BodyUnion")
		local d = pet:FindFirstChild("Dorsal") or pet:FindFirstChild("FrillScallop") or pet:FindFirstChild("BrowHorn") or pet:FindFirstChild("Pectoral")
		if bu and d then
			local ov = (bu.Position.Y + bu.Size.Y/2) - (d.Position.Y - d.Size.Y/2)
			print(("[PetFollow][GAP] %s scale=%.2f: %s/BodyUnion overlap=%.3f studs (negative = GAP)"):format(tag, pet:GetScale(), d.Name, ov))
		end
	end
	gapReport("BEFORE")
	pcall(function() pet:ScaleTo(sizeMul) end)
	gapReport("AFTER ")
	print(("[PetFollow] %s final scale = %.2f"):format(pet.Name, sizeMul))
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	-- (2) AURA @2
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
	-- (3) TRAIL @5 -- two attachments on the root (1 up / 1 down = width) + a Trail that lengthens/brightens
	if level >= 5 then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color=ColorSequence.new(theme.color); tr.LightEmission=0.6; tr.Lifetime=0.5+1.1*t
		tr.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35-0.3*t,0,1)), NumberSequenceKeypoint.new(1,1) })
		tr.Parent=root
	end
	-- (4) SPARKLES @8
	if level >= 8 then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"; pe.Rate=14+90*t; pe.LightEmission=0.7; pe.Rotation=NumberRange.new(0,360)
		pe.Lifetime=NumberRange.new(0.5,1.0); pe.Speed=NumberRange.new(0.6,1.6); pe.Size=NumberSequence.new(0.34); pe.Color=ColorSequence.new(theme.color)
		pe.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); pe.Parent=root
	end
	-- (5) ANIMATED FX: orbs (11/14/19), ring (15), pulse (18), burst (24)
	buildFX(pet, root, theme, level, atMax)
	-- (6) ACCESSORIES: this pet's own schedule, accumulating; gold trim at MAX
	local accs = PET_ACCS[petId] or theme.accs
	for _, e in ipairs(accs) do if level >= e[1] then buildAccessoryByKey(pet, root, theme, e[2], atMax) end end
	-- (7) RARE variant body recolor + (8) overhead nameplate (name + tier/level pill)
	if isRare then applyRareLook(pet, root, petId) end
	updateNameplate(pet, root, petId, level, isRare)
	-- LEVEL-UP POP + one-shot burst
	if prevLevel and level > prevLevel then
		local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
		burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
		burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root; burst:Emit(20); Debris:AddItem(burst,1.1)
	end
	petLevel[pet] = level
	local nAcc=0; for _,e in ipairs(theme.accs) do if level>=e[1] then nAcc=nAcc+1 end end
	print(("[PetFollow] %s Lv %d: size %d%%, aura %s, trail %s, sparkles %s, accessories %d, shimmer %s")
		:format(tostring(petId), level, math.floor(sizeMul*100), level>=2 and "on" or "off", level>=5 and "on" or "off", level>=8 and "on" or "off", nAcc, atMax and "on" or "off"))

	-- ===== HAND THE PET TO THE COSMETICS RENDERER. THIS IS THE WHOLE SKIN/TRAIT SYSTEM. =====
	-- PetSkinLook paints skins and builds trait accessories, but it does NOT search Workspace for
	-- pets -- it only ever touches models handed to it here, which it records in its `painted`
	-- register. That register is what repaintAll() walks on every server equip push and what
	-- /testpet's try-on repaints.
	--
	-- THIS CALL DID NOT EXIST IN THIS REALM. The renderer loaded fine, reported "17 skins, 21
	-- traits", and then sat with an EMPTY register forever: no skin ever applied, no trait ever
	-- appeared, and every /testpet TRY silently repainted nothing. The renderer's own header names
	-- this exact call site ("at the end of applyLevelVisual") -- it was simply never wired on this
	-- side, because the previous generation of the file was reached a different way.
	--
	-- AFTER the level look, never before: applyLevelVisual recolours and rescales the body, so a
	-- skin painted first would be overwritten by the level pass a few lines later. Guarded and
	-- pcall'd because load order between two LocalScripts is never guaranteed -- if the renderer
	-- has not published its hook yet the pet simply renders plain, and the next level-up or equip
	-- push paints it.
	if _G.applyPetSkinLook then
		pcall(_G.applyPetSkinLook, pet, petId, false)
	end
end

-- ===== FX LOOP: orbit orbs, spin ring, pulse, periodic burst, MAX shimmer =====
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

-- ===== FOLLOW MOVEMENT =====
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)  -- right, up, BEHIND (+Z)
local FOLLOW_K = 6     -- position responsiveness (lower = softer glide)
local FACE_K   = 4     -- facing responsiveness (slower -> swings round to turn)
local MAX_TRAIL = 45   -- never strand the pet on a fast ascent
local petSmoothPos, petSmoothFwd, bobT = nil, nil, 0

local st = { pet = nil, level = 1, rare = false, emerging = false }

-- ===== LIVE X-RAY -- draws the pet THAT IS ACTUALLY ON YOUR SCREEN =====
-- The hub icon and the follower clone the SAME template, so when one looks right and the other
-- looks wrong, the difference is something done to the follower AFTER it spawns -- and no amount
-- of reading the builder will show that. This reads the spawned model's real parts, in their real
-- positions, and draws them. If this drawing disagrees with the builder's own x-ray, whatever is
-- between them is the bug.
--
-- It runs ~1.5s after spawn (past the emerge animation and a few walk-cycle frames) so it shows
-- the settled state, not the entry pose. Re-run it any time with  _G.dinoPetXray()  in the console.
local FX_NAMES = { PetOrb=true, PetRing=true, PetPulse=true, EvoPart=true, LevelGlow=true,
                   PetSparkle=true, PetTrail=true, PetAura=true, Root=true }
local function liveGlyph(n)
	if n:find("Tooth") then return "T" end
	if n:find("Nostril") then return "*" end
	if n:find("Neck") then return "N" end
	if n:find("Head") then return "H" end
	if n:find("Snout") or n:find("Beak") then return "h" end
	if n:find("Dome") or n:find("Crest") then return "D" end
	if n:find("Jaw") then return "J" end
	if n:find("Mouth") or n:find("Smile") then return "m" end
	if n:find("Brow") then return "^" end
	if n:find("Claw") then return "c" end
	if n:find("Arm") or n:find("Hand") then return "a" end
	if n:find("Tail") then return "~" end
	if n:find("Belly") then return ":" end
	if n:find("Foot") then return "L" end
	if n:find("Gill") then return "g" end
	if n:find("Plate") or n:find("Sail") then return "S" end
	if n:find("Fin") or n:find("Dorsal") then return "f" end
	if n:find("Spot") or n:find("Dapple") then return "." end
	if n:find("eye") or n:find("Eye") or n:find("Glint") then return "o" end
	if n:find("BodyUnion") then return "#" end
	return "+"
end
local function livePetXray(pet, tag)
	if not (pet and pet.Parent and pet.PrimaryPart) then
		warn("[PetXray] no pet to draw"); return
	end
	local pivot = pet:GetPivot()
	local list = {}
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and not FX_NAMES[d.Name] then
			local rel = pivot:ToObjectSpace(d.CFrame)
			list[#list + 1] = { part = d, cf = rel, size = d.Size, glyph = liveGlyph(d.Name) }
		end
	end
	if #list == 0 then warn("[PetXray] pet has no parts"); return end
	local sc = pet:GetScale(); if sc <= 0 then sc = 1 end
	local function insideLive(e, wp)
		local lp = e.cf:PointToObjectSpace(wp)
		local hx, hy, hz = e.size.X/2, e.size.Y/2, e.size.Z/2
		if hx <= 0 or hy <= 0 or hz <= 0 then return false end
		local sh = (e.part:IsA("Part")) and e.part.Shape or nil
		if sh == Enum.PartType.Ball then
			return (lp.X/hx)^2 + (lp.Y/hy)^2 + (lp.Z/hz)^2 <= 1
		elseif sh == Enum.PartType.Cylinder then
			return math.abs(lp.X) <= hx and (lp.Y/hy)^2 + (lp.Z/hz)^2 <= 1
		end
		return math.abs(lp.X) <= hx and math.abs(lp.Y) <= hy and math.abs(lp.Z) <= hz
	end
	local COLS, ROWS = 58, 26
	print(("[PetXray] %s -- %s, %d part(s), scale %.2f"):format(tag, pet.Name, #list, sc))
	for _, view in ipairs({ "SIDE", "FRONT" }) do
		local minA, maxA, minY, maxY = 1e9, -1e9, 1e9, -1e9
		for _, e in ipairs(list) do
			local c, r = e.cf.Position, e.size.Magnitude * 0.5
			local a = (view == "SIDE") and c.X or c.Z
			minA = math.min(minA, a - r); maxA = math.max(maxA, a + r)
			minY = math.min(minY, c.Y - r); maxY = math.max(maxY, c.Y + r)
		end
		local sa, sy = (maxA - minA) / COLS, (maxY - minY) / ROWS
		print(("[PetXray] %s VIEW  (%s)"):format(view,
			view == "SIDE" and "+X right = the pet's front" or "+Z right, head on"))
		for r = 0, ROWS - 1 do
			local wy = maxY - (r + 0.5) * sy
			local line = {}
			for c = 0, COLS - 1 do
				local wa = minA + (c + 0.5) * sa
				local ch, best = " ", -1e9
				for _, e in ipairs(list) do
					local wp, depth
					if view == "SIDE" then wp = Vector3.new(wa, wy, e.cf.Position.Z); depth = e.cf.Position.Z
					else wp = Vector3.new(e.cf.Position.X, wy, wa); depth = e.cf.Position.X end
					if insideLive(e, wp) and depth > best then best = depth; ch = e.glyph end
				end
				line[#line + 1] = ch
			end
			print("[PetXray] |" .. (table.concat(line):gsub("%s+$", "")))
		end
	end
	-- anything touching nothing at all
	local loose = {}
	for _, e in ipairs(list) do
		local touch = false
		for _, q in ipairs(list) do
			if q ~= e and (e.cf.Position - q.cf.Position).Magnitude
				<= (e.size.Magnitude + q.size.Magnitude) * 0.5 then touch = true; break end
		end
		if not touch then loose[#loose + 1] = e.part.Name end
	end
	if #loose > 0 then
		warn(("[PetXray] %d part(s) touching NOTHING: %s"):format(#loose, table.concat(loose, ", ")))
	else
		print("[PetXray] every part is in contact with at least one other")
	end
end
_G.dinoPetXray = function() livePetXray(st.pet, "ON DEMAND") end

-- ===== WALK CYCLE: THE FEET SWING ON THEIR OWN =====
-- Every part named "Foot" is animated here. The builders deliberately keep the feet OUT of the
-- body union for this: a fused foot is one rigid solid with the body and physically cannot move
-- independently, no matter what this code does.
--
-- The gait is diagonal-pair (front-left with back-right), which is how four-legged animals
-- actually walk and reads far better than all four moving together. Stride length and cadence
-- both scale with how fast you are actually travelling, so the feet settle back to rest when you
-- stop -- no marching in place.
-- OFF BY DEFAULT. The walk cycle is the only thing that MOVES a part after the follower spawns,
-- so while "the shapes don't connect when equipped" is being chased it must not be in the way.
-- It also has a real cost even when working: feet have to live OUTSIDE the body union to move at
-- all, and a body-coloured part welded on rather than fused shades independently, so Roblox draws
-- a crease where each leg meets the body. Invisible in the Hub's flat ViewportFrame lighting,
-- visible in the world. Set this true to get stepping legs back and accept the seams.
local WALK_CYCLE = true   -- feet are welded (not fused) again on every pet, so they can step

-- ===== THE GAIT IS THE FOOD REALM'S PENDULUM SWING (ported 2026-08-29) =====
-- It used to SLIDE the feet: CFrame.new(swing, lift, 0) translated each block fore/aft and
-- lifted it. Blocks skating back and forth under a body -- the legs never actually pivoted, so
-- nothing about it read as walking. The first realm swings each leg like a PENDULUM from a hip
-- socket instead (PetFollow.client.lua:4253 over there), which is what sells the step, and this
-- is that algorithm on this realm's models:
--
--   swing = 18deg * mv * sin(phase)                       -- rotation, not translation
--   leg   = rotate(rest pose) about the HIP, around the LATERAL Z axis
--
-- WHAT CHANGED WITH IT, and why each one matters:
--   * HIP PIVOT IS DERIVED, NOT HARDCODED. The food realm pivots every pet at a flat
--     y = -0.7 * 0.9 studs, which only works because all its pets are one size. These are not:
--     a Stego foot is a 0.95 cube and a Brachiosaurus "foot" is a 2.05-tall LEG. Each leg group
--     now pivots at its own TOP FACE, so stride length scales with leg length for free -- little
--     dinos take little steps, the Brachiosaurus takes long ones.
--   * ONE PIVOT PER LEG GROUP, not per part. The raptor's FootClaw sickles sit on the toes; give
--     each part its own pivot and the claw rotates on a shorter arm than the foot it belongs to
--     and visibly shears off it. Grouping by quadrant and rotating the whole group about the
--     main foot's hip keeps foot+claw rigid.
--   * SPEED IS THE PET'S OWN DISPLACEMENT, not the player's velocity. Measured horizontally and
--     smoothed, exactly like the food realm: vertical is dropped, so a fart-ascent leaves the
--     legs hanging still instead of sprinting in mid-air. No airborne branch needed.
--   * PHASE IS PER-PET, not one file-level global shared by every follower.
--   * NO LIFT TERM. The rotation arcs the foot up on its own; the old explicit lift was there
--     to fake what a pendulum does for free.
local SWING_MAX     = math.rad(18)  -- peak leg swing at a full run (the food realm's number)
local STRIDE_SPEED  = 23.4          -- studs/sec that counts as a full-speed run (theirs: 26 * 0.9)

local feetOf = setmetatable({}, { __mode = "k" })  -- pet -> foot rest offsets (weak: dead pets drop out)

local function captureFeet(pet)
	if not WALK_CYCLE then return end
	local sc = pet:GetScale(); if sc <= 0 then sc = 1 end
	local pivot = pet:GetPivot()
	local list = { phase = 0, move = 0, lastPos = nil }
	for _, p in ipairs(pet:GetDescendants()) do
		-- NAME PREFIX, not an exact match. The live log read
		--     [PetFollow] TyrannosaurusPetFollower walk cycle -> 0 foot part(s)
		-- because that pet names its feet FootFL / FootFR / FootBL / FootBR. An exact "Foot"
		-- test silently gave those pets no walk cycle at all.
		if p:IsA("BasePart") and p.Name:sub(1, 4) == "Foot" then
			-- store the rest pose in the pivot's own space, DIVIDED BY the model scale, so the
			-- same numbers stay correct after applyLevelVisual() scales the pet on level-up.
			local rel = pivot:ToObjectSpace(p.CFrame)
			list[#list + 1] = {
				part = p, pos = rel.Position / sc, rot = rel - rel.Position,
				halfY = (p.Size.Y * 0.5) / sc,          -- for the hip: half the leg's own height
				vol   = p.Size.X * p.Size.Y * p.Size.Z, -- biggest part in a group = the real foot
			}
		end
	end

	-- GROUP BY QUADRANT and give each group ONE hip, taken from its bulkiest part (the foot
	-- itself, never a claw hanging off it). Everything in the group then rotates rigidly.
	local groups = {}
	for _, f in ipairs(list) do
		local key = ((f.pos.X >= 0) and "F" or "B") .. ((f.pos.Z >= 0) and "L" or "R")
		local g = groups[key]
		if not g or f.vol > g.vol then groups[key] = { vol = f.vol, f = f } end
		f.groupKey = key
	end
	for _, f in ipairs(list) do
		local lead = groups[f.groupKey].f
		f.hip = Vector3.new(lead.pos.X, lead.pos.Y + lead.halfY, lead.pos.Z)
	end

	-- order them so alternating indices are diagonal partners (front-left, back-right, ...)
	table.sort(list, function(a, b)
		if a.pos.X ~= b.pos.X then return a.pos.X > b.pos.X end
		return a.pos.Z > b.pos.Z
	end)
	feetOf[pet] = list
	print(("[PetFollow] %s walk cycle -> %d foot part(s)"):format(pet.Name, #list))
	return list
end

local function animateFeet(pet, pivot, speed, dt)
	if not WALK_CYCLE then return end
	local list = feetOf[pet]
	if not list or #list == 0 then return end
	local sc = pet:GetScale(); if sc <= 0 then sc = 1 end

	-- the pet's OWN horizontal speed, smoothed -- see the header note
	local here = pivot.Position
	if list.lastPos then
		local d = here - list.lastPos
		local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
		local target = math.clamp(sp / STRIDE_SPEED, 0, 1)
		list.move = list.move + (target - list.move) * math.clamp(dt * 5, 0, 1)
	end
	list.lastPos = here
	local mv = list.move
	list.phase = list.phase + dt * (9 + 3 * mv)   -- cadence rises with speed

	for _, f in ipairs(list) do
		if f.part.Parent then
			-- DIAGONAL GAIT KEYED ON POSITION, not list index: front-left steps with back-right.
			-- Position-keyed so extra Foot* parts (the raptor's FootClaw sickles ride on the toes)
			-- inherit the exact phase of the foot they sit on instead of a random index parity.
			local ph    = list.phase + (((f.pos.X >= 0) == (f.pos.Z >= 0)) and 0 or math.pi)
			local swing = SWING_MAX * mv * math.sin(ph)
			-- pendulum: rotate the rest pose about the hip, around the lateral Z axis. +X is the
			-- pet's front, so +Z rotation carries the foot forward.
			local hip  = f.hip * sc
			local rest = CFrame.new(f.pos * sc) * f.rot
			f.part.CFrame = pivot
				* (CFrame.new(hip) * CFrame.Angles(0, 0, swing) * CFrame.new(-hip))
				* rest
		end
	end
end

-- ===== FIN FLAP =====
-- Same idea as the walk cycle, for side fins: any part named "Pectoral" (or "Wing", for future
-- pets) is kept welded by fuseAll and rocked around its own mounting point. Fins scull gently
-- even at rest -- a shark treads water -- and beat faster with speed.
local finsOf = setmetatable({}, { __mode = "k" })
local finPhase = 0
local function captureFins(pet)
	local sc = pet:GetScale(); if sc <= 0 then sc = 1 end
	local pivot = pet:GetPivot()
	local list = {}
	for _, p in ipairs(pet:GetDescendants()) do
		if p:IsA("BasePart") and (p.Name == "Pectoral" or p.Name == "Wing") then
			local rel = pivot:ToObjectSpace(p.CFrame)
			list[#list + 1] = { part = p, pos = rel.Position / sc, rot = rel - rel.Position,
				sgn = (rel.Position.Z >= 0) and 1 or -1 }
		end
	end
	finsOf[pet] = list
	if #list > 0 then print(("[PetFollow] %s fin flap -> %d fin(s)"):format(pet.Name, #list)) end
end
local function animateFins(pet, pivot, speed, dt)
	local list = finsOf[pet]
	if not list or #list == 0 then return end
	local sc = pet:GetScale(); if sc <= 0 then sc = 1 end
	local drive = 0.35 + 0.65 * math.clamp(speed / 18, 0, 1)
	finPhase = finPhase + dt * (2.2 + 6 * drive)
	local ang = math.sin(finPhase) * 0.22 * drive
	for _, f in ipairs(list) do
		if f.part.Parent then
			f.part.CFrame = pivot * (CFrame.new(f.pos * sc) * f.rot) * CFrame.Angles(ang * f.sgn, 0, 0)
		end
	end
end

-- ===== FOLLOW WATCHDOG =====
-- "they do not follow me" is reported often and is nearly impossible to diagnose from source,
-- because the follow branch below is fully generic -- no pet is named in it, so a pet that
-- spawns either follows or fails one of exactly four preconditions. This prints WHICH ONE,
-- once a second, so the answer is in the log instead of in a guess.
--
-- IT ALSO CATCHES THE COMMON FALSE ALARM: the two STATIC copies of every pet that legitimately
-- stand still are the build's display model near the SpawnLocation and the "Hatched<Name>_<you>"
-- celebration pet the server floats over the egg. Neither is st.pet and neither ever follows.
-- If this watchdog is silent while a pet stands there, that pet is one of those two, not a bug.
local wdT = 0
local function followWatchdog(dt, pet, hrp)
	wdT = wdT + dt
	if wdT < 1 then return end
	wdT = 0
	if not pet then return end                      -- nothing equipped: not a fault
	local why =
		(not pet.Parent) and "pet was destroyed (pet.Parent == nil)"
		or (not pet.PrimaryPart) and "pet has NO PrimaryPart -- its 'Root' part is missing from the template"
		or st.emerging and "still in the 0.5s emerge animation (stuck emerging = a PivotTo error)"
		or (not hrp) and "your character has no HumanoidRootPart yet"
		or nil
	if why then warn(("[PetFollow][WATCHDOG] %s is NOT following: %s"):format(pet.Name, why)) end
	-- A DESTROYED pet is gone for good -- something external removed it (e.g. /petfull replacing
	-- test followers). Repeating the same warning every second forever is noise, not diagnosis:
	-- one report, then let go of the reference so the state reads "nothing equipped".
	if not pet.Parent then st.pet = nil end
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pet = st.pet
	followWatchdog(dt, pet, hrp)
	if pet and pet.Parent and pet.PrimaryPart and not st.emerging and hrp then
		local targetPos = (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)).Position
		if not petSmoothPos then petSmoothPos = targetPos end
		petSmoothPos = petSmoothPos:Lerp(targetPos, 1 - math.exp(-FOLLOW_K * dt))
		local back = petSmoothPos - targetPos
		if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
		bobT = bobT + dt
		local vel = hrp.AssemblyLinearVelocity
		local moveDir = Vector3.new(vel.X, 0, vel.Z)
		-- ===== ALIVE, NOT A STATUE =====
		-- WHOLE-BODY MOTION, layered UNDER the leg swing (animateFeet, below). This comment used
		-- to say legs could not move at all because the pet was one fused solid -- that has not
		-- been true since feet came back out of the union on every pet, and the body motion is
		-- now the accompaniment rather than the whole performance:
		--   * a HOP synced to a GALLOP pitch while you move (bounds along over the stepping legs)
		--   * a WADDLE roll layered on top
		--   * a FORWARD LEAN that grows with speed -- the food realm's running tell
		--   * a slow BREATHING sway + idle yaw/roll when standing still
		local speedF = math.clamp(moveDir.Magnitude / 14, 0, 1)
		local hop = math.abs(math.sin(bobT * 4.5)) * 0.09 * speedF   -- toned down: the LEGS walk now, the body only bounces lightly over them
		local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 1.4) * 0.10 + hop, 0)
		-- HYBRID facing: face the TRAVEL direction while moving, turn to face the PLAYER when idle.
		-- (+X front reads forward when running, and looks at you when stopped -- the hub's front view.)
		local fwd
		if st.facePlayer then -- shark/trike: ALWAYS face the player so its +X face shows (hub-like)
			fwd = hrp.Position - renderPos; fwd = Vector3.new(fwd.X, 0, fwd.Z)
		elseif moveDir.Magnitude > 2 then
			fwd = moveDir                               -- moving -> face where it's going
		else
			fwd = hrp.Position - renderPos               -- idle -> look at the player (front toward you)
			fwd = Vector3.new(fwd.X, 0, fwd.Z)
		end
		if fwd.Magnitude < 0.05 then fwd = (petSmoothFwd or Vector3.new(0,0,-1)) end
		fwd = fwd.Unit
		if not petSmoothFwd then petSmoothFwd = fwd end
		petSmoothFwd = petSmoothFwd:Lerp(fwd, 1 - math.exp(-FACE_K * dt))
		if petSmoothFwd.Magnitude < 0.05 then petSmoothFwd = fwd end
		local face = petSmoothFwd.Unit
		-- ===== THREE-QUARTER VIEW (st.faceYaw) =====
		-- The Pet Hub does NOT look at a pet head-on. Its camera sits front-upper-RIGHT, at
		-- dir=(0.80,0.50,0.55) -- about 35 degrees off the pet's nose -- so every flat feature shows
		-- its BROAD side. facePlayer, by contrast, aimed the nose exactly at the camera, and a flat
		-- feature seen exactly edge-on is only as wide as it is THICK.
		--
		-- That is the whole "the megalodon has no fin when I equip it" bug. Its dorsal is 1.44 wide
		-- but only 0.77 THICK, so nose-on it collapsed to a ~0.77-stud dark nub above the head --
		-- "just a little dot". Nothing was missing, deleted or shrunk: /petfull proved the world copy
		-- is identical to the template and the hub icon, part for part. It was pointed the one way
		-- that hides it. Yawing to match the hub's own camera angle is what makes it read as a fin.
		local pivot = CFrame.lookAt(renderPos, renderPos + face)
			* CFrame.Angles(0, math.rad(90 + (st.faceYaw or 0)), 0) -- +X = front -> yaw +90 (+ per-pet offset)
		-- gallop = nose bobs with the hop; waddle = side-to-side lean; breath = idle sway
		local gallop = math.sin(bobT * 9.0) * 0.035 * speedF
		local waddle = math.sin(bobT * 4.5) * 0.02 * speedF
		local breath = (1 - speedF) * math.sin(bobT * 1.6) * 0.02
		-- FORWARD LEAN -- the other half of the food realm's gait, and the half that actually
		-- reads as "running". Their pets pitch nose-down up to 13 degrees in proportion to speed
		-- (PetFollow.client.lua:4225 over there); ours only ever oscillated, so the body stayed
		-- bolt upright while the legs worked. -Z pitch drops the nose, since +X is the front.
		local lean = -math.rad(13) * speedF
		-- IDLE SWAY: a slow yaw/roll that never stops, so a standing pet still breathes rather
		-- than freezing solid the moment you stop -- the legs go completely still at rest now.
		local swayY = math.rad(3) * math.sin(bobT * 0.8)
		local swayZ = math.rad(2) * math.sin(bobT * 1.1)
		pivot = pivot * CFrame.Angles(waddle, swayY, gallop + breath + lean + swayZ)
		pet:PivotTo(pivot)
		-- feet AFTER the pivot: PivotTo moves every part, so the walk offsets have to be applied
		-- on top of the pose it just set, not before it.
		animateFeet(pet, pivot, moveDir.Magnitude, dt)
		animateFins(pet, pivot, moveDir.Magnitude, dt)
		if not st.orientPrinted then st.orientPrinted = true
			local pv = pet:GetPivot()
			print(("[PetFollow][ORIENT] %s AFTER -> up=(%.2f,%.2f,%.2f) frontX=(%.2f,%.2f,%.2f)  (up should be ~0,1,0 = dorsal upright; frontX = the travel/look dir the face points)"):format(pet.Name, pv.UpVector.X,pv.UpVector.Y,pv.UpVector.Z, pv.RightVector.X,pv.RightVector.Y,pv.RightVector.Z))
		end
	end
end)

-- ===== EYE BLINK (the game's EXACT Size.Y squash from animatePet / Eyes_AllInOne) =====
-- Eye parts (whitepartofeye / blackpartofeye / Glint) are treated as eye=true. Per frame:
-- blink -= dt; on crossing 0, squash Size.Y for 0.16s, then schedule next at 1.8 + rand*3.4 s.
-- Each eye's ORIGINAL Size.Y is stored once and multiplied from that base every frame (no compounding).
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
		if not petModel.Parent then conn:Disconnect(); return end   -- clean up on despawn
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
	print("[PetFollow] eye blink (Size.Y squash) started (" .. #eyes .. " eye parts)")
end

-- SHARK FOLLOWER-ONLY FINS: DELETED. This built the equipped shark a SECOND set of WedgePart
-- fins and destroyed the template Dorsal/TailTop/TailBot first, so the pet you equipped was a
-- different model from its Hub icon. Its call site was removed long ago but the function was
-- left behind, and it cost a whole debugging round: it looks exactly like a fin-deleter, so it
-- became the prime suspect for the missing megalodon fin before grep proved nothing called it.
-- The real cause was the viewing angle (see st.faceYaw above). Dead code that impersonates a bug
-- is worse than no code.

-- ===== SPAWN a follower from a published template (called by QuestGate / dig quest on hatch) =====
local function spawnFollowerFromTemplate(templateName, label, baseCF)
	local tmpl = RS:FindFirstChild(templateName) or RS:WaitForChild(templateName, 10)
	if not tmpl then warn("[PetFollow] " .. templateName .. " missing -> cannot spawn follower"); return end
	if st.pet then pcall(function() st.pet:Destroy() end); petFX[st.pet]=nil; petScale[st.pet]=nil; petLevel[st.pet]=nil end
	local pet = tmpl:Clone(); pet.Name = label; pet.Parent = workspace
	local n = 0; for _, d in ipairs(pet:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	print(("[PetFollow] %s -> CLONED %s (%d parts)"):format(label, templateName, n))
	-- match the hub EXACTLY: pivot on Root (origin/identity, +X front, +Y up). If the clone lost its PrimaryPart,
	-- PivotTo would fall back to a tilted bounding-box pivot -> fin/face read wrong. Force it back to Root.
	-- Ask for full detail on the clone. Roblox refuses this on runtime-CSG unions (see
	-- PetFace.forcePrecise for the two reasons it is a dead end, and why it does not matter:
	-- Automatic already renders at highest detail within ~250 studs). Left in, silent, in case
	-- the engine ever starts honouring it.
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("UnionOperation") then
			pcall(function() d.RenderFidelity = Enum.RenderFidelity.Precise end)
		end
	end
	if pet.PrimaryPart ~= pet:FindFirstChild("Root") then pet.PrimaryPart = pet:FindFirstChild("Root") end
	-- ===== NO PrimaryPart == NO FOLLOWING, SILENTLY =====
	-- The follow loop requires pet.PrimaryPart, so a clone whose "Root" is missing spawns fine,
	-- looks fine, and then stands exactly where it appeared forever with nothing logged. That is
	-- indistinguishable to a player from "the pet is broken", and it is the single failure that
	-- has cost the most time on this file. Root can go missing for boring reasons -- a build that
	-- errored before newRoot(), a stale template published by an older version of the builder,
	-- a resync that landed mid-build -- so rather than trust every builder to be perfect, rebuild
	-- it here. An invisible 0.4 ball at the model's own pivot is exactly what newRoot() makes.
	if not pet.PrimaryPart then
		warn(("[PetFollow] %s clone has NO 'Root' part -- rebuilding one so it can follow " ..
		      "(fix the builder: %s must call newRoot())"):format(label, templateName))
		local pivot = pet:GetPivot()
		local r = Instance.new("Part")
		r.Name = "Root"; r.Shape = Enum.PartType.Ball; r.Size = Vector3.new(0.4, 0.4, 0.4)
		r.Transparency = 1; r.Anchored = true; r.CanCollide = false; r.CanQuery = false
		r.CanTouch = false; r.CastShadow = false; r.Massless = true
		r.CFrame = pivot; r.Parent = pet
		pet.PrimaryPart = r
	end
	do local pv = pet:GetPivot(); print(("[PetFollow][ORIENT] %s BEFORE -> PrimaryPart=%s pivotUp=(%.2f,%.2f,%.2f) pivotLook=(%.2f,%.2f,%.2f)"):format(label, pet.PrimaryPart and pet.PrimaryPart.Name or "nil", pv.UpVector.X,pv.UpVector.Y,pv.UpVector.Z, pv.LookVector.X,pv.LookVector.Y,pv.LookVector.Z)) end
	st.pet = pet; petSmoothPos = nil; petSmoothFwd = nil; st.orientPrinted = false
	-- The SHARK no longer force-faces the player. That rule dates from when its fin was
	-- invisible and only the face view looked right -- but a glider that always rotates toward
	-- you SWIMS BACKWARD whenever you move, which is exactly the "looks bad only when equipped"
	-- effect: the hub cannot show motion. It now faces its travel direction like a real shark
	-- (and still turns to face you when you stand still, via the idle branch below).
	st.facePlayer = (label:find("Trice") ~= nil) -- trike only: its frill face is its identity
	-- The TRICERATOPS reads best dead-on -- its frill faces forward, which is why it has always
	-- looked right. The MEGALODON is the opposite animal: everything that identifies it (dorsal,
	-- pectorals, tail fork) is a FLAT BLADE, invisible edge-on. It gets the hub camera's own
	-- ~35-degree offset so you see the broad side of those blades, not their thickness.
	-- No yaw offset either: it existed to show the old invisible fin's broad side. The new
	-- design carries its identity in the silhouette (dorsal, side fins, tail), which is exactly
	-- what you see while it swims alongside you; the face shows when it turns to you at rest.
	st.faceYaw = 0
	applyLevelVisual(pet, st.level, st.rare)
	captureFeet(pet)   -- AFTER applyLevelVisual: it calls ScaleTo, which moves the feet
	captureFins(pet)   -- side fins (Pectoral/Wing) scull on their own cycle
	applyBlink(pet)  -- Size.Y squash blink on whitepartofeye/blackpartofeye/Glint
	-- SHARK FOLLOWER-ONLY FINS: REMOVED. This used to delete the template's Dorsal/TailTop/TailBot
	-- and rebuild them as WedgeParts, so the equipped shark was literally a DIFFERENT model from the
	-- one in the Pet Hub -- the single clearest case of "looks right in the menu, wrong in the world".
	-- It only existed because the follower used to be scaled to 0.6, which pulled the template's small
	-- welded fins off the body; the size ramp is gone, so the template's own fins work. And it would
	-- now actively break things: after PetFace.fuseAll the template fins are INSIDE the union, so the
	-- destroy pass would find nothing and it would weld a SECOND set of fins on top of them.
	-- emerge: a short rise at the spot, then hand off to the follow loop
	if typeof(baseCF) == "CFrame" then
		st.emerging = true
		pcall(function() pet:PivotTo(baseCF) end)
		task.spawn(function()
			local T, t0 = 0.5, os.clock()
			while os.clock() - t0 < T and pet.Parent do
				local p = (os.clock() - t0) / T
				pcall(function() pet:PivotTo(baseCF * CFrame.new(0, math.sin(p * math.pi) * 2.0 + p * 1.0, 0)) end)
				task.wait()
			end
			st.emerging = false
		end)
	end
	print("[PetFollow] " .. label .. " spawned -> following you")
	task.delay(1.5, function()
		if st.pet == pet and pet.Parent then livePetXray(pet, "EQUIPPED (live, 1.5s after spawn)") end
	end)
end
_G.SpawnStegoFollower  = function(baseCF) spawnFollowerFromTemplate("StegosaurusTemplate", "StegoFollower", baseCF) end
_G.SpawnRaptorFollower = function(baseCF) spawnFollowerFromTemplate("VelociraptorTemplate", "RaptorFollower", baseCF) end
_G.SpawnSharkFollower  = function(baseCF) spawnFollowerFromTemplate("SharkTemplate", "SharkFollower", baseCF) end
_G.SpawnTriceratopsFollower = function(baseCF) spawnFollowerFromTemplate("TriceratopsTemplate", "TriceratopsFollower", baseCF) end
_G.SpawnSpinosaurusFollower = function(baseCF) spawnFollowerFromTemplate("SpinosaurusTemplate", "SpinosaurusFollower", baseCF) end
_G.SpawnTyrannosaurusFollower = function(baseCF) spawnFollowerFromTemplate("TyrannosaurusTemplate", "TyrannosaurusFollower", baseCF) end
_G.SpawnTherizinosaurusFollower = function(baseCF) spawnFollowerFromTemplate("TherizinosaurusTemplate", "TherizinosaurusFollower", baseCF) end
_G.SpawnBrachiosaurusFollower   = function(baseCF) spawnFollowerFromTemplate("BrachiosaurusTemplate",   "BrachiosaurusFollower",   baseCF) end

-- ===== EQUIP from the Pet Hub -> spawn THAT pet as the follower (or despawn on unequip). Lets you equip any owned pet. =====
task.spawn(function()
	local pee = RS:WaitForChild("PetEquipEvent", 30)
	if not pee then return end
	-- EVERY pet must be in here or equipping it silently does nothing.
	-- Spinosaurus and Tyrannosaurus were MISSING -- their templates existed and the
	-- _G.Spawn*Follower functions above used them, but the Pet Hub's equip path looks
	-- pets up in THIS table, so equipping the Spino or T-Rex just warned
	-- "has no template mapping" and no follower ever appeared.
	local EQUIP_TMPL = {
		StegoPet         = "StegosaurusTemplate",
		RaptorPet        = "VelociraptorTemplate",
		SharkPet         = "SharkTemplate",
		TriceratopsPet   = "TriceratopsTemplate",
		SpinosaurusPet   = "SpinosaurusTemplate",   -- was missing
		TyrannosaurusPet = "TyrannosaurusTemplate", -- was missing
		-- AND THEN IT HAPPENED AGAIN. The Therizinosaurus and Brachiosaurus were added with
		-- templates, grants, hub icons and _G.Spawn*Follower hooks -- everything except this
		-- table -- so they hatched, appeared in the Hub, and equipped to nothing. If you add a
		-- pet anywhere, add it HERE too; this is the table the equip button actually reads.
		TherizinosaurusPet = "TherizinosaurusTemplate",
		BrachiosaurusPet   = "BrachiosaurusTemplate",
	}
	pee.OnClientEvent:Connect(function(petId)
		if not petId or petId == false then -- unequipped -> remove the follower
			if st.pet then pcall(function() st.pet:Destroy() end); petFX[st.pet]=nil; petScale[st.pet]=nil; petLevel[st.pet]=nil; st.pet = nil end
			return
		end
		-- RARE variants are stored under a "#R" storage key (e.g. "StegoPet#R"), which
		-- would miss this table entirely. Strip the suffix so a rare equips the same
		-- model as its normal counterpart (applyLevelVisual paints the rare sheen on top).
		local baseId = tostring(petId):gsub("#R$", "")
		local tmpl = EQUIP_TMPL[baseId]
		if not tmpl then
			warn(("[PetFollow] equipped '%s' has no template mapping -- add it to EQUIP_TMPL"):format(tostring(petId)))
			return
		end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)) or CFrame.new(0,8,0)
		spawnFollowerFromTemplate(tmpl, petId .. "Follower", at)  -- swaps st.pet to the equipped pet
	end)
	print("[PetFollow] equip listener ready -> equipping a pet in the hub spawns its follower")
end)

-- ===== server-driven level (PetUpgrades.server.luau): re-apply the follower's evolve look on PetStateEvent =====
task.spawn(function()
	local pse = RS:WaitForChild("PetStateEvent", 20)
	if not pse then return end
	pse.OnClientEvent:Connect(function(payload)
		-- IGNORE STATE FOR A PET THAT IS NOT THE ONE EQUIPPED. The live log caught this firing on
		-- the OUTGOING follower mid-swap: equipping the Triceratops re-ran the whole level-visual
		-- pass on the SharkPetFollower a few milliseconds before it was destroyed. Harmless today,
		-- but it re-applies scaling and FX to a doomed model and muddies every log it appears in.
		if not (payload and st.pet and st.pet.Parent) then return end
		local d = payload.StegoPet or payload.RaptorPet or payload.SharkPet or payload.TriceratopsPet or payload.SpinosaurusPet or payload.TyrannosaurusPet
			or payload.TherizinosaurusPet or payload.BrachiosaurusPet
		if not d then for _, v in pairs(payload) do if type(v) == "table" then d = v; break end end end
		if d then
			st.level = d.level or st.level
			st.rare  = d.rare or false
			applyLevelVisual(st.pet, st.level, st.rare)
		end
	end)
end)

-- ===== RARE HATCH FANFARE: server rolled a rare -> full-screen "RARE!" banner + a burst on the pet =====
task.spawn(function()
	local pre = RS:WaitForChild("PetRareEvent", 30)
	if not pre then return end
	local TS = game:GetService("TweenService")
	pre.OnClientEvent:Connect(function(petId, rareName)
		st.rare = true
		if st.pet then applyLevelVisual(st.pet, 25, true) end
		if st.pet and st.pet.PrimaryPart then
			local b = Instance.new("ParticleEmitter"); b.Color=ColorSequence.new(Color3.fromRGB(255,120,235)); b.LightEmission=0.9
			b.Lifetime=NumberRange.new(0.5,1.0); b.Speed=NumberRange.new(5,12); b.Rotation=NumberRange.new(0,360)
			b.Size=NumberSequence.new(0.5); b.Rate=0; b.Parent=st.pet.PrimaryPart; b:Emit(60); Debris:AddItem(b,1.4)
		end
		local gui = Instance.new("ScreenGui"); gui.Name="RareFanfare"; gui.IgnoreGuiInset=true; gui.DisplayOrder=200; gui.Parent=pg
		local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.fromScale(1,0.2); lbl.Position=UDim2.fromScale(0,0.32); lbl.BackgroundTransparency=1
		lbl.Font=Enum.Font.FredokaOne; lbl.TextScaled=true; lbl.TextColor3=Color3.fromRGB(255,120,235); lbl.TextTransparency=1
		lbl.Text=("\xE2\x9C\xA8 RARE!  %s  \xE2\x9C\xA8"):format(tostring(rareName or petDisplayName(petId, true)))
		local stk=Instance.new("UIStroke", lbl); stk.Color=Color3.fromRGB(255,255,255); stk.Thickness=2; stk.Transparency=1
		lbl.Parent=gui
		TS:Create(lbl, TweenInfo.new(0.4), { TextTransparency=0 }):Play()
		TS:Create(stk, TweenInfo.new(0.4), { Transparency=0 }):Play()
		task.delay(2.4, function()
			TS:Create(lbl, TweenInfo.new(0.6), { TextTransparency=1 }):Play()
			TS:Create(stk, TweenInfo.new(0.6), { Transparency=1 }):Play()
			Debris:AddItem(gui, 1.0)
		end)
		print("[PetFollow] RARE fanfare -> "..tostring(rareName))
	end)
end)

-- ===== keys: ] = real server level-up (updates hub + follower), [ = local preview down, R = rare preview =====
local function setLevel(lv)
	st.level = math.clamp(lv, 1, 25)
	if st.pet then applyLevelVisual(st.pet, st.level, st.rare) end
end
UserInput.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.RightBracket then
		local up = RS:FindFirstChild("PetUpgradeEvent")
		if up then pcall(function() up:FireServer("StegoPet") end) else setLevel(st.level + 1) end
	elseif io.KeyCode == Enum.KeyCode.LeftBracket then setLevel(st.level - 1)
	elseif io.KeyCode == Enum.KeyCode.R then st.rare = not st.rare; if st.pet then applyLevelVisual(st.pet, st.level, st.rare) end end
end)

print("[PetFollow] ready -- hatch a Stego to get a follower. Keys: ] level+  [ level-  R rare")
