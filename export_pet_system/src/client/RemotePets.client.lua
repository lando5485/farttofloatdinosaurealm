--======================================================================
-- RemotePets.client.lua  (LocalScript)
--======================================================================
-- CROSS-PLAYER PET VISIBILITY (Option B): builds + follows a pet for every OTHER player in the server, so
-- their equipped pet is visible to everyone (not just its owner). The server (PetSystem) BROADCASTS each
-- player's equipped-pet info via the "PetEquipBroadcast" RemoteEvent; this script listens and renders a
-- local copy of each remote pet on THIS client.
--
-- IMPORTANT: this NEVER touches the LOCAL player's own pet -- that is still 100% handled by
-- PetFollow.client.lua (we explicitly skip our own userId). PetFollow was NOT modified. The visual +
-- animation pipeline below is REPLICATED from PetFollow (the originals are locked inside that script and
-- it sits at the 200-local cap, so it can't be edited) -- this is a separate script with its own budget.
--
-- Reuses the SAME server-fused Union body templates already in ReplicatedStorage (the "[Pet][UNION]"
-- templates PetFollow clones) -- no server-side pet models, no CSG here.
--======================================================================

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local RS              = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local PetEquipBroadcast = RS:WaitForChild("PetEquipBroadcast", 30)
if not PetEquipBroadcast then return end -- server publisher not present -> nothing to render

-- PetFollow puts the EQUIPPED SKIN'S RARITY on the nameplate ("Baby Epic"), reading it through
-- _G.petSkinRarityOf. That helper answers for the LOCAL player only -- it looks up PetSkinLook's own equipped
-- table -- so it is useless here: a remote pet's skin arrives in the broadcast payload instead. Require the
-- PetSkins table directly and read the tier off info.skin, so other players' plates carry the same rarity word
-- and colour yours does. Guarded: a missing module must not take the whole renderer down.
local PetSkins do
	local ok, mod = pcall(function()
		return require(RS:WaitForChild("Shared", 20):WaitForChild("PetSkins", 20))
	end)
	PetSkins = ok and mod or nil
	if not PetSkins then warn("[RemotePets] PetSkins module unavailable -- remote nameplates will show age without skin rarity") end
end

--======================================================================
-- ===== VISUAL PIPELINE (ported from PetFollow.client.lua -- kept identical so remote pets look exactly
-- like the owner's pet: size ramp, aura/trail/sparkles, animated FX, accessories, rare look, tier badge,
-- and the body/head/tail/leg animation). =====
--======================================================================
local petAnims = setmetatable({}, { __mode = "k" }) -- [model] = animation state (parts/roles)
local petFX = {}                                    -- [model] = animated FX state (orbs/ring/pulse/burst/shimmer)

local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
-- MUST LIST EVERY SPECIES PetFollow'S PET_THEME LISTS. applyLevelVisual below does `if not theme then return end`,
-- and EVERYTHING that makes a pet read correctly sits after that line: the age SIZE ramp (A.sizeMul, 60% at Baby
-- -> 100% at Elder), the overhead NAME + AGE nameplate, the accessory ladder, the level FX and the rare look.
-- This table had only the 5 quest pets, so the other six species rendered on everyone else's screen at FULL SIZE
-- with NO nameplate -- a Baby Bean Buddy looked like an Elder one and had no name or age over it, while its owner
-- saw it correctly scaled and labelled. Six missing entries, copied verbatim from PetFollow: change one, change both.
local PET_THEME = {
	-- SECRET: Pizza Dragon (10/10 collection reward). Wings are role "wing"; horns sit where other pets' ears do.
	PizzaDragon = { color=Color3.fromRGB(226,150,68),
		head=CFrame.new(-0.1,1.7,0), face=CFrame.new(1.5,0.7,0), glassW=0.5, neck=CFrame.new(1.25,-0.1,0), back=CFrame.new(-1.5,0.5,0), ear=CFrame.new(-0.15,1.9,0.62), side=CFrame.new(0.2,0.0,1.4),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	-- STARTER: Bean Buddy. Its sprout leaves are role "ear", so it reuses the bunny-style ear anchor.
	BeanBuddy = { color=Color3.fromRGB(126,200,86),
		head=CFrame.new(-0.1,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(-0.1,1.75,0.7), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	BroccoliPet = { color=Color3.fromRGB(120,210,70),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	CoconutCrab = { color=Color3.fromRGB(170,100,60),
		head=CFrame.new(-0.1,1.0,0), face=CFrame.new(0.92,0.78,0), glassW=0.4, neck=CFrame.new(0.7,0.05,0), back=CFrame.new(-0.85,0.45,0), side=CFrame.new(0,0.2,1.15), side2=CFrame.new(0,0.2,-1.15),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"anchor"} } },
	PopcornSheep = { color=Color3.fromRGB(248,244,230),
		head=CFrame.new(1.1,1.55,0), face=CFrame.new(1.65,0.4,0), glassW=0.45, neck=CFrame.new(1.1,-0.35,0), back=CFrame.new(-1.4,0.4,0), ear=CFrame.new(0.5,1.6,0.85), side=CFrame.new(0.3,-0.2,1.4),
		accs={ {3,"bell"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"cloudcluster"},{23,"crook"} } },
	ButterDuck = { color=Color3.fromRGB(250,205,75),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BurritoArmadillo = { color=Color3.fromRGB(200,160,110),
		head=CFrame.new(1.15,1.4,0), face=CFrame.new(1.5,0.8,0), glassW=0.45, neck=CFrame.new(1.2,0.15,0), back=CFrame.new(-1.5,0.35,0), side=CFrame.new(0.2,-0.1,1.5), side2=CFrame.new(0.2,-0.1,-1.5),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"safari"},{13,"backpack"},{17,"gemstuds"},{20,"lantern"},{23,"pickaxe"} } },
	-- SEASONAL PETS: reuse the standard body/head anchors so they get the same level scaling + accessory schedule.
	SunflowerBee = { color=Color3.fromRGB(250,205,60),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	MapleFox = { color=Color3.fromRGB(222,120,52),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.2,2.35,1.0), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	FrostPenguin = { color=Color3.fromRGB(120,150,200),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BlossomBunny = { color=Color3.fromRGB(186,224,150),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
}
-- The three REBIRTH pets are recolour-clones of BeanBuddy / PizzaDragon / MapleFox, so they share those bodies
-- exactly -- give them the same anchors rather than leaving them themeless (which is what dropped their nameplate
-- and age scaling). PetFollow resolves them through PET_THEME[pet.Name] on the same table; keep both in step.
PET_THEME.MoltenBean = PET_THEME.BeanBuddy
PET_THEME.VoidDragon = PET_THEME.PizzaDragon
PET_THEME.PrismFox   = PET_THEME.MapleFox
-- ===== RARE PET BRIGHTNESS =====
-- Rare variants read 30% dimmer than they used to. They were the brightest thing on screen -- glass/metal
-- body sheens, an 0.85-LightEmission sparkle aura and a Brightness-3 PointLight on top -- which is a lot of
-- glare to stand next to for the whole game.
--
-- Applied as ONE factor at the point of use rather than by editing the colours in RARE_LOOK, for two
-- reasons: the table stays readable as authored intent, and RemotePets carries an identical copy of both the
-- table and this code, so a single tunable in each is far harder to let drift than ten edited hex values.
-- Raise it back toward 1.0 to undo.
local RARE_DIM = 0.525 -- was 0.7; rare variants read 25% dimmer again. MUST match PetFollow's copy, or your rare pet and everyone else's render at different brightness.
local function rareDim(c)
	return Color3.new(c.R * RARE_DIM, c.G * RARE_DIM, c.B * RARE_DIM)
end

local RARE_LOOK = {
	BroccoliPet      = { name="Emerald Bunny",    body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(70,255,150) },
	CoconutCrab      = { name="Golden Crab",      body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,  refl=0.35, fx=Color3.fromRGB(255,225,90) },
	PopcornSheep     = { name="Cloud Sheep",      body=Color3.fromRGB(212,232,255), mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(225,242,255), puffs=true, light=true },
	BurritoArmadillo = { name="Crystal Armadillo",body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(195,125,255) },
	ButterDuck       = { name="Cosmic Duck",      body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true },
}
-- The overhead nameplate reads from this. A species missing here fell back to its raw id, so a remote pet was
-- labelled "BeanBuddy" where its owner saw "Bean Buddy". Same list as PetFollow's PET_DISPLAY -- keep in step.
local PET_DISPLAY = { BeanBuddy="Bean Buddy", PizzaDragon="Pizza Dragon", BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny",
	MoltenBean="Molten Bean", VoidDragon="Void Dragon", PrismFox="Prism Fox" }
-- MUST LIST EVERY SPECIES PetFollow LISTS. A species missing from here has no template to clone, so
-- buildPetModel returns nil and that player is INVISIBLE to everyone else -- permanently, not briefly.
-- BeanBuddy was missing, and BeanBuddy is the free first-join starter: every new player in the server
-- was carrying a pet nobody else could see. PizzaDragon (10/10 secret) and the three rebirth recolours
-- were missing for the same reason. Keep this table in sync with PET_TEMPLATE_NAME in PetFollow.
local PET_TEMPLATE_NAME = {
	BeanBuddy="BeanBuddyTemplate",                -- starter (free on first join)
	PizzaDragon="PizzaDragonTemplate",            -- SECRET 10/10 collection reward
	BroccoliPet="BroccoliBunnyTemplate", CoconutCrab="CoconutCrabTemplate", PopcornSheep="PopcornSheepTemplate",
	ButterDuck="ButterDuckTemplate", BurritoArmadillo="BurritoArmadilloTemplate",
	SunflowerBee="SunflowerBeeTemplate", MapleFox="MapleFoxTemplate", FrostPenguin="FrostPenguinTemplate", BlossomBunny="BlossomBunnyTemplate",
	MoltenBean="MoltenBeanTemplate",              -- REBIRTH 3  (recoloured Bean Buddy)
	VoidDragon="VoidDragonTemplate",              -- REBIRTH 6  (recoloured Pizza Dragon)
	PrismFox="PrismFoxTemplate",                  -- REBIRTH 10 (recoloured Maple Fox)
}
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230), true, true
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end
	end
	-- AGE stages, mirroring PetFollow's ladder exactly (rarity words belong to the skin crates now;
	-- levels are growth). Change one and you must change the other.
	if level <= 5      then return "Baby",  Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Teen",  Color3.fromRGB(70,140,255),  false, false
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235),  false, false
	else                    return "Elder", Color3.fromRGB(255,170,40),  false, false end
end
local function petDisplayName(petId, isRare) return (isRare and RARE_LOOK[petId] and RARE_LOOK[petId].name) or PET_DISPLAY[petId] or petId end

local function flagAccPart(p)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
local accScale = 1
local function accPart(pet, A, root, shape, sx, sy, sz, color, cf)
	local R = accScale
	local size = Vector3.new(sx*R, sy*R, sz*R)
	local bcf = CFrame.new(cf.Position * R) * (cf - cf.Position)
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=size; p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * bcf; p.Parent = pet
	A.parts[#A.parts+1] = { part=p, base=bcf, baseSize=size, role="body", eye=false }
	return p
end
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local function buildAccessoryByKey(pet, A, root, theme, key, gold)
	if key == "bowtie" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		accPart(pet,A,root, BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "monocle" then
		local f = theme.face; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		accPart(pet,A,root, CYL_, 0.12,0.46,0.46, c, f * CFrame.new(0,0,(theme.glassW or 0.5)))
	elseif key == "bell" then
		local collar = gold and PRESTIGE_GOLD or Color3.fromRGB(170,45,55)
		local bell   = gold and PRESTIGE_GOLD or Color3.fromRGB(212,176,80)
		accPart(pet,A,root, CYL_, 1.5,0.22,0.22, collar, theme.neck * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BAL_, 0.42,0.46,0.42, bell, theme.neck * CFrame.new(0.05,-0.34,0))
	elseif key == "scarf" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		accPart(pet,A,root, CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "backpack" then
		local b = theme.back; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(120,90,58)
		accPart(pet,A,root, BLK_, 0.65,0.8,0.9, c, b)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.55,0.12,0.16, gold and Color3.fromRGB(225,185,70) or Color3.fromRGB(88,64,40), b * CFrame.new(0.5,0.12,0.42*sgn)) end
	elseif key == "flower" then
		local e = theme.ear; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); accPart(pet,A,root, BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		accPart(pet,A,root, BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sword" then
		local s = theme.side; local blade = gold and PRESTIGE_GOLD or Color3.fromRGB(200,205,215)
		accPart(pet,A,root, BLK_, 0.16,0.28,0.16, Color3.fromRGB(90,60,38), s)
		accPart(pet,A,root, BLK_, 0.34,0.12,0.12, gold and PRESTIGE_GOLD or Color3.fromRGB(205,170,70), s * CFrame.new(0,0.16,0))
		accPart(pet,A,root, BLK_, 0.14,1.0,0.14, blade, s * CFrame.new(0,0.7,0))
	elseif key == "crown" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(212,182,66)
		accPart(pet,A,root, CYL_, 0.16,1.05,1.05, c, h * CFrame.Angles(0,0,math.rad(90)))
		for i=0,4 do local ang=math.rad(i*72); accPart(pet,A,root, CYL_, 0.5,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.42, 0.3, math.cos(ang)*0.42) * CFrame.Angles(0,0,math.rad(90))) end
	elseif key == "piratehat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(34,34,40)
		accPart(pet,A,root, BAL_, 1.5,0.45,1.15, c, h)
		accPart(pet,A,root, BAL_, 0.95,0.78,0.85, c, h * CFrame.new(-0.05,0.45,0))
		accPart(pet,A,root, CYL_, 1.0,0.2,0.2, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(225,185,70), h * CFrame.new(0.45,0.05,0) * CFrame.Angles(0,math.rad(90),0))
	elseif key == "tophat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		accPart(pet,A,root, CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "safari" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(156,138,96)
		accPart(pet,A,root, CYL_, 0.12,1.5,1.5, c, h * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BAL_, 0.95,0.66,0.95, c, h * CFrame.new(0,0.34,0))
		accPart(pet,A,root, CYL_, 0.2,0.92,0.92, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(110,92,60), h * CFrame.new(0,0.12,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "haloring" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90)
		for i=0,9 do local ang=math.rad(i*36); local p=accPart(pet,A,root, BAL_, 0.16,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.6, 0.85, math.cos(ang)*0.6)); p.Material=Enum.Material.Neon end
	elseif key == "staff" then
		local s = theme.side
		accPart(pet,A,root, CYL_, 1.7,0.14,0.14, Color3.fromRGB(120,84,46), s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BAL_, 0.42,0.42,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90), s * CFrame.new(0,1.3,0)); p.Material=Enum.Material.Neon
	elseif key == "anchor" then
		local s = theme.side2 or theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.0,0.14,0.14, c, s * CFrame.new(0,0.2,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.6,0.14,0.14, c, s * CFrame.new(0,0.6,0) * CFrame.Angles(math.rad(90),0,0))
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.4,0.14,0.14, c, s * CFrame.new(0.18*sgn,-0.2,0) * CFrame.Angles(0,0,math.rad(40*sgn))) end
	elseif key == "gemcluster" then
		local cols = { Color3.fromRGB(95,215,205), Color3.fromRGB(120,180,255), Color3.fromRGB(235,225,205) }
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.3,0.3,0.3, gold and PRESTIGE_GOLD or cols[(k%3)+1], CFrame.new(-0.35+k*0.28, 0.95, -0.1+(k%2)*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "crook" then
		local s = theme.side; local c = Color3.fromRGB(150,110,64)
		accPart(pet,A,root, CYL_, 1.8,0.14,0.14, c, s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.5,0.13,0.13, c, s * CFrame.new(-0.18,1.35,0) * CFrame.Angles(0,0,math.rad(35)))
		accPart(pet,A,root, CYL_, 0.4,0.13,0.13, c, s * CFrame.new(-0.42,1.18,0) * CFrame.Angles(0,0,math.rad(80)))
	elseif key == "cloudcluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,255,255)
		for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.45,0.4,0.45, c, h * CFrame.new(math.sin(ang)*0.5, 0.8, math.cos(ang)*0.5)) end
	elseif key == "sparklecluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.55, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		accPart(pet,A,root, CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	elseif key == "gemstuds" then
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, gold and PRESTIGE_GOLD or Color3.fromRGB(120,200,210), CFrame.new(-0.7+k*0.5, 1.6, 0)); p.Material=Enum.Material.Neon end
	elseif key == "lantern" then
		local s = theme.side; local frame = gold and PRESTIGE_GOLD or Color3.fromRGB(90,72,46)
		accPart(pet,A,root, CYL_, 0.16,0.1,0.1, frame, s * CFrame.new(0,0.55,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BLK_, 0.5,0.6,0.5, Color3.fromRGB(255,225,110), s); p.Material=Enum.Material.Neon
		accPart(pet,A,root, BLK_, 0.6,0.12,0.6, frame, s * CFrame.new(0,-0.34,0))
	elseif key == "pickaxe" then
		local s = theme.side2 or theme.side; local wood = Color3.fromRGB(120,84,46); local head = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.3,0.13,0.13, wood, s * CFrame.new(0,0.3,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BLK_, 0.9,0.16,0.16, head, s * CFrame.new(0,0.85,0) * CFrame.Angles(0,0,math.rad(18)))
	end
end
local function clearEvo(pet, A)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" or n=="PetRareFX" or n=="PetRareLight" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" then c:Destroy() end
	end
	if A then for i = #A.parts, 1, -1 do if A.parts[i].part and A.parts[i].part.Name == "EvoPart" then A.parts[i].part:Destroy(); table.remove(A.parts, i) end end end
	petFX[pet] = nil
end
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25),
		orbR=2.0, orbH=0.45, ringR=2.2, ringY=0.3, ringTilt=22 }
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0)
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then
		for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end
	end
	if level >= 18 then
		fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2)
	end
	if level >= 24 then
		local b = Instance.new("ParticleEmitter"); b.Name="PetBurst"; b.Color=ColorSequence.new(col)
		b.Rate=0; b.Lifetime=NumberRange.new(0.4,0.8); b.Speed=NumberRange.new(4,9); b.Size=NumberSequence.new(0.5)
		b.LightEmission=0.8; b.Rotation=NumberRange.new(0,360); b.Parent=root; fx.burst=b
	end
	petFX[pet] = fx
end
local function applyRareLook(pet, A, root, petId)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="Eye" and n~="Highlight" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				d.Color = rareDim(r.body); d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(rareDim(r.fx)); rfx.LightEmission=0.85*RARE_DIM*0.75
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime = NumberRange.new(0.6,1.2); rfx.Rotation = NumberRange.new(0,360)
	rfx.Speed = NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size = NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent = root
	if r.light then local pl = Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=rareDim(r.fx); pl.Brightness=3*RARE_DIM*0.75; pl.Range=12; pl.Parent=root end
	if r.puffs and A then for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.55,0.5,0.55, Color3.fromRGB(255,255,255), CFrame.new(math.sin(ang)*1.6, 0.7, math.cos(ang)*1.6)) end end
	if r.cosmic and petFX[pet] then petFX[pet].cosmic = true end
end
-- size + aura/trail/sparkles + FX + accessories + rare + overhead tier badge. Mirrors PetFollow's
-- applyLevelVisual (minus its [PetEvo] owner diagnostics + the icon "lite" path, neither needed here).
local function applyLevelVisual(pet, level, petId, isRare, skinId, traitId)
	if not pet then return end
	level = level or 1
	local root = pet.PrimaryPart
	local A = petAnims[pet]
	local theme = PET_THEME[petId] or PET_THEME[pet.Name]
	if not theme then return end
	if isRare then level = 25 end
	local MAXL = 25
	local frac = math.clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = A and A.lastVisualLevel or nil
	accScale = 1
	clearEvo(pet, A)
	if A then A.sizeMul = 0.6 + 0.4 * frac end
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	if level >= 2 and root then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor = theme.color; hl.OutlineColor = theme.color
		hl.FillTransparency = math.clamp(0.8 - 0.45*t, 0, 1); hl.OutlineTransparency = math.clamp(0.4 - 0.4*t, 0, 1)
		hl.Parent = pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=(2.5+4*t)*0.75; pl.Range=8+8*t; pl.Parent=root
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	if level >= 5 and root then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6; tr.Lifetime = 0.5 + 1.1*t
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.3*t, 0, 1)), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = root
	end
	if level >= 8 and root then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"
		pe.Rate = 14 + 90*t; pe.LightEmission = 0.7; pe.Rotation = NumberRange.new(0,360)
		pe.Lifetime = NumberRange.new(0.5, 1.0); pe.Speed = NumberRange.new(0.6, 1.6); pe.Size = NumberSequence.new(0.34)
		pe.Color = ColorSequence.new(theme.color)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) })
		pe.Parent = root
	end
	if root then buildFX(pet, root, theme, level, atMax) end
	if A and root then
		for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, A, root, theme, e[2], atMax) end end
	end
	if isRare and root then applyRareLook(pet, A, root, petId) end
	if root then
		local bb = root:FindFirstChild("LevelTag")
		if not bb then
			-- MUST STAY IDENTICAL to the LevelTag in PetFollow.client.lua (that one labels YOUR pet, this one labels
			-- everyone else's). If the two drift, your own pet gets a different-sized nameplate to every other
			-- pet in the server, which reads as a bug. Shrunk to ~72%: 200x42 -> 144x30, name 16pt -> 12, badge
			-- 11pt -> 9, and the StudsOffset drops 3.7 -> 3.4 so the smaller plate still hugs the pet's head.
			bb = Instance.new("BillboardGui"); bb.Name="LevelTag"; bb.Size=UDim2.new(0,144,0,30)
			bb.StudsOffset=Vector3.new(0,3.4,0); bb.AlwaysOnTop=true; bb.Parent=root
			local lbl = Instance.new("TextLabel"); lbl.Name="L"; lbl.Size=UDim2.new(1,0,0,14); lbl.Position=UDim2.new(0,0,0,0); lbl.BackgroundTransparency=1
			lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=12; lbl.Parent=bb; Instance.new("UIStroke").Parent=lbl
			local tg = Instance.new("TextLabel"); tg.Name="Tag"; tg.AnchorPoint=Vector2.new(0.5,0); tg.Position=UDim2.new(0.5,0,0,16)
			tg.AutomaticSize=Enum.AutomaticSize.X; tg.Size=UDim2.new(0,0,0,12); tg.Font=Enum.Font.GothamBold; tg.TextSize=9; tg.TextColor3=Color3.new(1,1,1); tg.Parent=bb
			local pad=Instance.new("UIPadding", tg); pad.PaddingLeft=UDim.new(0,4); pad.PaddingRight=UDim.new(0,4)
			Instance.new("UICorner", tg).CornerRadius=UDim.new(0,4); Instance.new("UIStroke", tg)
		end
		local tierName, tierColor, isVariant, flashy = petTier(level, isRare, petId)
		-- THE ONE OVERALL TIER joins the badge -- "Baby Legendary  Age 3" -- exactly as PetFollow builds it for
		-- your own pet (age from the level, tier from the equipped skin+trait through PetTier). Never the skin
		-- and trait rarities separately: one label overhead is the rule. Exotic/Mythical variants keep their
		-- own badge: that name outranks any tier, same rule as PetFollow.
		if not isVariant and skinId then
			local ovT, ovC
			if _G.petSkinOverallTier then
				local okOv, a, b = pcall(_G.petSkinOverallTier, skinId, traitId)
				if okOv then ovT, ovC = a, b end
			end
			if not ovT and PetSkins then -- PetSkinLook still booting: the skin's own tier is the honest fallback
				local okS, skTier = pcall(PetSkins.tierOf, skinId)
				if okS and skTier then
					ovT = skTier
					local okC, skCol = pcall(PetSkins.tierColor, skTier)
					if okC then ovC = skCol end
				end
			end
			if ovT then
				tierName = tierName .. " " .. tostring(ovT)
				if ovC then tierColor = ovC end
			end
		end
		bb.L.Text = petDisplayName(petId, isRare)
		bb.L.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
		bb.Tag.Text = isVariant and tierName or (tierName .. "  Age " .. tostring(level))
		bb.Tag.BackgroundColor3 = tierColor
		local stk = bb.Tag:FindFirstChildOfClass("UIStroke")
		if stk then
			if flashy then
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stk.Color = Color3.fromRGB(255,255,255); stk.Thickness = 1; stk.Transparency = 0.2
			else
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; stk.Color = Color3.fromRGB(0,0,0); stk.Thickness = 1; stk.Transparency = 0.35
			end
		end
	end
	local leveledUp = prevLevel and level > prevLevel
	if leveledUp then
		if A then A.popClock = 0.4 end
		if root then
			local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
			burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
			burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root
			burst:Emit(20)
			game:GetService("Debris"):AddItem(burst, 1.1)
		end
	end
	if A then A.lastVisualLevel = level end
end

-- FX loop (orbs/ring/pulse/burst/shimmer/cosmic) -- one Heartbeat for all remote pets.
do
	RunService.Heartbeat:Connect(function(dt)
		for pet, fx in pairs(petFX) do
			local root = pet.Parent and pet.PrimaryPart
			if root then
				fx.t = fx.t + dt
				local t = fx.t
				local rootCF = root.CFrame
				local sm = (petAnims[pet] and petAnims[pet].sizeMul) or 1
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
					fx.pulse.Transparency = math.clamp(ph, 0, 1)
					fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
				end
				if fx.burst then
					fx.burstClock = fx.burstClock - dt
					if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end
				end
				if fx.cosmic then
					local cc = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
					-- Dimmed like the static rare colours are. Without this the Cosmic Duck would rewrite
					-- its light and sparkles to FULL brightness every frame and be the one rare pet the
					-- 30% reduction never touched -- and it is the brightest of the five to begin with.
					local dimCc = rareDim(cc)
					local rl = root:FindFirstChild("PetRareLight"); if rl then rl.Color = dimCc end
					local rfx = root:FindFirstChild("PetRareFX"); if rfx then rfx.Color = ColorSequence.new(dimCc) end
				end
				if fx.shimmer then
					local hue = (t * 0.25) % 1
					local c = Color3.fromHSV(hue, 0.45, 0.9)
					local hl = pet:FindFirstChild("LevelGlow")
					if hl then
						hl.OutlineColor = c; hl.OutlineTransparency = 0.25
						hl.FillColor = c; hl.FillTransparency = 0.88
					end
					local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
					for _, orb in ipairs(fx.orbs) do orb.Color = c end
					for _, seg in ipairs(fx.ring) do seg.part.Color = c end
				end
			else
				petFX[pet] = nil
			end
		end
	end)
end

-- Register a cloned server template: derive each part's animator role from its name + build the anim state.
local function registerClonedTemplate(model)
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then return false end
	model.PrimaryPart = root
	local rootCF = root.CFrame
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local role, eye = "body", false
			local n = p.Name
			if n == "Leg" or n == "Foot" or n == "ToeClaw" then role = "leg"
			elseif n == "Tail" or n == "TailSpike" then role = "tail"
			elseif n == "Ear" then role = "ear"
			elseif n == "Wing" then role = "wing"
			elseif n == "Claw" then role = "claw"
			elseif n == "Eye" or n == "Highlight" then eye = true end
			parts[#parts+1] = { part = p, base = rootCF:ToObjectSpace(p.CFrame), baseSize = p.Size, role = role, eye = eye }
		end
	end
	petAnims[model] = { s = 0.9, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil, unionized = true }
	return true
end
-- Clone the SAME server-fused Union template PetFollow uses (templates are in ReplicatedStorage, available
-- to every client). No client-built fallback here -- if the template hasn't replicated yet, we retry later.
local function buildPetModel(petId)
	local tn = PET_TEMPLATE_NAME[petId]
	local template = tn and (RS:FindFirstChild(tn) or RS:WaitForChild(tn, 4))
	if not template then warn("[RemotePets] template "..tostring(tn).." not replicated yet for "..tostring(petId)); return nil end
	local clone = template:Clone(); clone.Name = petId
	if registerClonedTemplate(clone) then return clone end
	clone:Destroy(); return nil
end

local function pivotRotate(pivot, rot) return CFrame.new(pivot) * rot * CFrame.new(-pivot) end
local function animatePet(model, dt)
	local A = petAnims[model]; if not A then return end
	local root = model.PrimaryPart; if not (root and root.Parent) then return end
	local rootCF = root.CFrame
	local s = A.s
	A.t = A.t + dt
	local t = A.t
	A.popMul = 1
	if A.popClock and A.popClock > 0 then
		A.popClock = math.max(0, A.popClock - dt)
		A.popMul = 1 + 0.25 * math.sin(math.pi * (1 - A.popClock / 0.4))
	end
	local pos = rootCF.Position
	if A.lastPos then
		local d = pos - A.lastPos
		local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
		local target = math.clamp(sp / (26 * s), 0, 1)
		A.move = A.move + (target - A.move) * math.clamp(dt * 5, 0, 1)
	end
	A.lastPos = pos
	local mv = A.move
	local bobY = math.sin(t * 1.5) * 0.06 * s + math.sin(t * (3.0 + 1.5 * mv)) * 0.09 * s * mv
	local swayY = math.rad(3) * math.sin(t * 0.8)
	local swayZ = math.rad(2) * math.sin(t * 1.1)
	local globalT = CFrame.new(0, bobY, 0) * pivotRotate(Vector3.new(0, 0, 0), CFrame.Angles(0, swayY, -math.rad(13) * mv + swayZ))
	local headBob = math.sin(t * 1.7 + 0.5) * 0.05 * s + math.sin(t * (8 + 4 * mv)) * 0.05 * s * mv
	local headRot = CFrame.Angles(0, math.rad(8) * math.sin(t * 0.6), 0) * CFrame.Angles(0, 0, math.rad(5) * math.sin(t * 1.1) - math.rad(7) * mv)
	local headT = CFrame.new(0, headBob, 0) * pivotRotate(Vector3.new(1.2 * s, 0.6 * s, 0), headRot)
	local tailRot = pivotRotate(Vector3.new(-1.5 * s, 0, 0), CFrame.Angles(0, math.sin(t * (2.2 + 3 * mv)) * (math.rad(14) + math.rad(16) * mv), 0))
	A.blink = A.blink - dt
	local eyeY = 1
	if A.blink <= 0 then
		local since = -A.blink
		if since < 0.16 then
			eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1))
		else
			A.blink = 1.8 + math.random() * 3.4
		end
	end
	for _, e in ipairs(A.parts) do
		local bp = e.base
		local localCF
		if e.role == "head" then
			localCF = globalT * headT * bp
		elseif e.role == "tail" then
			localCF = globalT * tailRot * bp
		elseif e.role == "leg" then
			local bx, bz = e.base.Position.X, e.base.Position.Z
			local phase = ((bx >= 0) == (bz >= 0)) and 0 or math.pi
			local swing = math.rad(18) * mv * math.sin(t * (9 + 3 * mv) + phase)
			localCF = globalT * pivotRotate(Vector3.new(bx, -0.7 * s, bz), CFrame.Angles(0, 0, swing)) * bp
		elseif e.role == "ear" then
			local bzs = e.base.Position.Z >= 0 and 1 or -1
			local flop = math.rad(7) * math.sin(t * 1.6) + math.rad(9) * mv * math.sin(t * (7 + 2 * mv))
			local splay = math.rad(5) * math.sin(t * 1.3 + bzs) * bzs
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y - 1.0 * s, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, 0, flop) * CFrame.Angles(splay, 0, 0)) * bp
		elseif e.role == "wing" then
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local flap = (math.rad(10) + math.rad(26) * mv) * math.sin(t * (3 + 9 * mv)) * sgn
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y, e.base.Position.Z - 1.0 * s * sgn)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(flap, 0, 0)) * bp
		elseif e.role == "claw" then
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local sc = (math.rad(6) + math.rad(10) * mv) * math.sin(t * (5 + 6 * mv) + (sgn > 0 and 0 or math.pi))
			local pv = Vector3.new(e.base.Position.X - 0.8 * s, e.base.Position.Y, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, sc * sgn, sc * 0.5)) * bp
		else
			localCF = globalT * bp
		end
		local sm = (A.sizeMul or 1) * (A.popMul or 1)
		if sm ~= 1 then
			local p = localCF.Position
			localCF = CFrame.new(p * sm) * (localCF - p)
		end
		e.part.CFrame = rootCF * localCF
		if e.eye then
			e.part.Size = Vector3.new(e.baseSize.X * sm, e.baseSize.Y * eyeY * sm, e.baseSize.Z * sm)
		elseif sm ~= 1 then
			e.part.Size = e.baseSize * sm
		end
	end
end

--======================================================================
-- ===== REMOTE PET REGISTRY + FOLLOW (one pet per OTHER player) =====
--======================================================================
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5) -- right, up, behind -- SAME as PetFollow so remote pets sit like the owner's
local FOLLOW_K      = 6
local FACE_K        = 4
local MAX_TRAIL     = 45

local remotePets = {} -- [userId] = { userId, player, playerName, petId, level, isRare, pet, smoothPos, smoothFwd, bobT, appliedLevel, appliedRare }
local heard = {}      -- [userId] = true once we have PROCESSED a payload for that player (drives the catch-up poll below)

local function destroyEntryPet(entry)
	if entry.pet then
		petFX[entry.pet] = nil
		petAnims[entry.pet] = nil
		pcall(function() entry.pet:Destroy() end)
		entry.pet = nil
	end
end

local function removeRemotePet(userId, reason)
	local entry = remotePets[userId]
	if not entry then return end
	destroyEntryPet(entry)
	remotePets[userId] = nil
	print(string.format("[RemotePets] removed remote pet for %s (%s)", tostring(entry.playerName or userId), tostring(reason)))
end

-- THE SKIN IS PART OF THE LOOK. The payload carries the owner's equipped skin + trait; painting them here is
-- what makes a remote pet match what its owner sees. applyPetSkinPreview is PetSkinLook's "paint an ARBITRARY
-- skin+trait on this model" entry point, the same one the crate reveal uses; static=false gives the full
-- treatment (emitter, light, hue cycling), which is right here because this is a live pet in the world.
--
-- PetSkinLook is a SEPARATE LocalScript with no ordering guarantee against this one. At join it is routinely
-- still booting (it waits on SkinRemotes + a GetSkinState round-trip) when the first catch-up burst arrives.
-- The old code just gave up in that case, so remote pets rendered SKINLESS for the whole session. Retry until
-- the renderer exists, re-reading the entry each time so a skin change mid-retry wins.
local function paintEntrySkin(entry)
	if not entry.pet then return end
	if _G.applyPetSkinPreview then
		pcall(_G.applyPetSkinPreview, entry.pet, entry.appliedSkin, entry.appliedTrait, false)
		return
	end
	if entry.skinPending then return end -- one waiter per player, not one per broadcast
	entry.skinPending = true
	task.spawn(function()
		for _ = 1, 40 do -- ~20s: PetSkinLook's own WaitForChild budget is 30s, this covers the normal case
			task.wait(0.5)
			if remotePets[entry.userId] ~= entry then break end
			if _G.applyPetSkinPreview then
				if entry.pet then pcall(_G.applyPetSkinPreview, entry.pet, entry.appliedSkin, entry.appliedTrait, false) end
				break
			end
		end
		entry.skinPending = false
	end)
end

local function buildEntryPet(entry)
	local pet = buildPetModel(entry.petId)
	if not pet then return false end
	pet.Name = "RemotePet_" .. tostring(entry.userId)
	-- The rename hides the species from PetSkinLook, which reads it to apply PetTraits.PET_OFFSETS (per-pet
	-- accessory nudges). Stamp it as an attribute so a remote crab's hat sits where the owner's does.
	pet:SetAttribute("PetSpecies", entry.petId)
	pet.Parent = Workspace
	entry.pet = pet
	entry.appliedLevel = entry.level
	entry.appliedRare = entry.isRare
	print(string.format("[RemotePets] building remote pet for %s (%s lvl %s rare %s)",
		tostring(entry.playerName), tostring(entry.petId), tostring(entry.level or 1), entry.isRare and "y" or "n"))
	applyLevelVisual(pet, entry.level or 1, entry.petId, entry.isRare, entry.appliedSkin, entry.appliedTrait) -- size/accessories/FX/rare look/nameplate
	print(string.format("[RemotePets] remote pet for %s following", tostring(entry.playerName)))
	return true
end

local function onBroadcast(info)
	if type(info) ~= "table" then return end
	local userId = info.userId
	if not userId or userId == localPlayer.UserId then return end -- own pet is PetFollow's job
	if not info.petId then heard[userId] = true; removeRemotePet(userId, "unequipped"); return end -- nothing equipped
	local plr = Players:GetPlayerByUserId(userId)
	if not plr then return end -- not in the server yet -> stay UNHEARD so the catch-up poll asks again
	heard[userId] = true
	local entry = remotePets[userId]
	if entry and entry.pet and entry.petId == info.petId then
		-- SAME pet -> refresh the look if level / rare / SKIN changed (no rebuild)
		entry.level = info.level; entry.isRare = info.isRare
		-- Skin changes arrive as their own broadcast (SkinCrateService re-announces on equip), and they do NOT
		-- change the pet id -- so without this the payload would be treated as "nothing to do" and the new
		-- skin would never appear on anyone else's screen.
		local skinChanged = (entry.appliedSkin ~= info.skin or entry.appliedTrait ~= info.trait)
		if entry.appliedLevel ~= info.level or entry.appliedRare ~= info.isRare or skinChanged then
			entry.appliedLevel = info.level; entry.appliedRare = info.isRare
			entry.appliedSkin = info.skin; entry.appliedTrait = info.trait
			-- a SKIN change re-runs this too: the badge carries the skin's rarity word + colour, so swapping
			-- skins has to relabel the plate, not just repaint the body. (PetFollow does the same -- a skin
			-- equip goes through _G.petEvoRefresh, a full evo re-run, before the repaint.)
			applyLevelVisual(entry.pet, info.level or 1, info.petId, info.isRare, entry.appliedSkin, entry.appliedTrait)
		end
		if skinChanged then paintEntrySkin(entry) end
		return
	end
	-- DIFFERENT pet (or first time / respawn) -> (re)build cleanly
	if entry then destroyEntryPet(entry) end
	entry = entry or {}
	entry.userId = userId; entry.player = plr; entry.playerName = plr.Name
	entry.petId = info.petId; entry.level = info.level; entry.isRare = info.isRare
	entry.smoothPos = nil; entry.smoothFwd = nil; entry.bobT = 0
	remotePets[userId] = entry
	entry.appliedSkin = info.skin; entry.appliedTrait = info.trait
	if buildEntryPet(entry) then
		paintEntrySkin(entry)
		return
	end
	-- TEMPLATE NOT REPLICATED YET. The server builds all 14 pet templates in one task.spawn at boot (each one a
	-- union operation), so on a fresh server they can land well after the first players do. The old code retried
	-- exactly ONCE at 2s and then gave up forever -- and nothing re-broadcasts on its own, so that player stayed
	-- invisible for the rest of the session. Keep retrying instead.
	if entry.buildPending then return end
	entry.buildPending = true
	task.spawn(function()
		for _ = 1, 15 do -- buildPetModel already waits up to 4s per try -> ~90s of cover, then give up quietly
			task.wait(2)
			if remotePets[userId] ~= entry or entry.pet then break end
			if buildEntryPet(entry) then paintEntrySkin(entry); break end
		end
		entry.buildPending = false
	end)
end

PetEquipBroadcast.OnClientEvent:Connect(onBroadcast)
Players.PlayerRemoving:Connect(function(plr) removeRemotePet(plr.UserId, "left"); heard[plr.UserId] = nil end)

-- ===== "I'M READY" HANDSHAKE: ask the server for everyone's current equips, UNTIL WE'VE HEARD FROM EVERYONE =====
-- The server's late-join catch-up fires when OUR SAVE loads -- routinely before this script has connected
-- onBroadcast above, and remote fires that land before a handler exists are simply dropped. That made pet
-- visibility one-way: players already here saw our join broadcast, we never saw their catch-up.
--
-- The old fix was two blind asks (t=0 and t=6). Both can still be lost, because the SERVER side has the mirror
-- race: PetSystem creates the PetEquipBroadcast remote near the top of the file but does not connect its
-- OnServerEvent until ~1200 lines later, so a request that arrives while the server is still booting goes
-- nowhere -- and a client-to-server fire has no delivery receipt to tell us that happened.
--
-- So don't ask blindly: ask, then CHECK. `heard` records every player we've actually processed a payload for;
-- while any player in the server is still unaccounted for, ask again. Interval is 4s because the server
-- debounces this remote at 3s (a faster poll would be silently dropped as spam).
task.spawn(function()
	for attempt = 1, 15 do -- ~60s of cover; a normal join resolves on the first or second ask
		local missing = nil
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer and not heard[p.UserId] then missing = p.Name; break end
		end
		if attempt > 1 and not missing then
			print("[RemotePets] catch-up complete -- heard from every player in the server")
			return
		end
		if missing then print("[RemotePets] catch-up ask #"..attempt.." (still nothing for "..missing..")") end
		pcall(function() PetEquipBroadcast:FireServer() end)
		task.wait(4)
	end
	warn("[RemotePets] gave up asking for catch-up -- some players' pets may not be rendered")
end)

-- A player who joins AFTER us is announced by the server when their save loads, and we are already listening --
-- so this is only a backstop for a dropped announce. Costs one remote fire per join, at most.
Players.PlayerAdded:Connect(function(plr)
	task.delay(10, function()
		if plr.Parent and not heard[plr.UserId] then
			print("[RemotePets] never heard about "..plr.Name.." -- asking the server again")
			pcall(function() PetEquipBroadcast:FireServer() end)
		end
	end)
end)

-- FOLLOW + ANIMATE loop: each remote pet glides behind ITS player's character (reads the live character
-- each frame, so it auto-re-targets on respawn). Same smooth glide/face feel as PetFollow's own-pet loop.
RunService.RenderStepped:Connect(function(dt)
	for _, entry in pairs(remotePets) do
		local pet = entry.pet
		if pet and pet.Parent and pet.PrimaryPart then
			local char = entry.player and entry.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)).Position
				if not entry.smoothPos then entry.smoothPos = targetPos end
				local alpha = 1 - math.exp(-FOLLOW_K * dt)
				entry.smoothPos = entry.smoothPos:Lerp(targetPos, alpha)
				local back = entry.smoothPos - targetPos
				if back.Magnitude > MAX_TRAIL then entry.smoothPos = targetPos + back.Unit * MAX_TRAIL end
				entry.bobT = (entry.bobT or 0) + dt
				local renderPos = entry.smoothPos + Vector3.new(0, math.sin(entry.bobT * 1.4) * 0.10, 0)
				local fwd = hrp.CFrame.LookVector; fwd = Vector3.new(fwd.X, 0, fwd.Z)
				if fwd.Magnitude < 0.05 then fwd = (entry.smoothFwd or Vector3.new(0, 0, -1)) end
				fwd = fwd.Unit
				if not entry.smoothFwd then entry.smoothFwd = fwd end
				local fAlpha = 1 - math.exp(-FACE_K * dt)
				entry.smoothFwd = entry.smoothFwd:Lerp(fwd, fAlpha)
				if entry.smoothFwd.Magnitude < 0.05 then entry.smoothFwd = fwd end
				local face = entry.smoothFwd.Unit
				pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0))
			end
			-- no character (respawning) -> leave the pet where it is; still animate the sub-parts
			animatePet(pet, dt)
		end
	end
end)

print("[RemotePets] online -- rendering other players' equipped pets (listening on PetEquipBroadcast)")
