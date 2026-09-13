--======================================================================
-- SpacePetFollower.client.luau   — PUT THIS IN THE *SPACE REALM* PLACE
-- (StarterPlayer > StarterPlayerScripts, as a LocalScript).
--
-- ONE self-contained client file for the whole Space Realm pet system:
--   1. Hooks your Pets button (auto-detect, or CONFIG override) -> picker UI.
--   2. Lists the pets that teleported in (GetSpaceRealmPets from PetReceiver).
--   3. Equipping one spawns a follower that trails you, looking EXACTLY like its
--      level on the islands -- size, accessories, aura/trail/sparkles, orbs/ring/
--      pulse, tier badge, and the full RARE look (body recolor + light + cosmic
--      rainbow). Ported verbatim from the main game's PetFollow.client.lua.
--   4. Keeps leveling up as you FLY (fires progress to SpacePetLeveling.server),
--      re-rendering the new look on each level-up.
--   5. Auto-equips whatever pet was following you when you teleported in.
--
-- Needs: PetReceiver.server + PetTemplates.server + SpacePetLeveling.server.
-- ** DELETE SpacePetUpgrades.client.luau -- this file now contains it. **
--======================================================================

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local Debris           = game:GetService("Debris")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function clamp(x, a, b) return math.clamp(x, a, b) end

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	BUTTON_PATH       = nil,            -- e.g. { "MainGui", "PetsButton" } to force a button; nil = auto-detect
	BUTTON_MATCH      = { "pet" },      -- auto-detect: GuiButton whose Name/Text contains one of these
	CREATE_BUTTON_IF_MISSING = true,    -- make our own button if none matches

	MAX_LEVEL         = 25,
	FOLLOW_BEHIND     = 5.0,
	FOLLOW_SIDE       = 3.0,
	FOLLOW_HEIGHT     = -1.0,
	RESPONSIVENESS    = 6.0,
	TURN_SPEED        = 8.0,
	BOB_AMP           = 0.35,
	BOB_SPEED         = 2.2,
	TELEPORT_DIST     = 80,
}

local TEMPLATE_NAME = {
	BroccoliPet      = "BroccoliBunnyTemplate",
	CoconutCrab      = "CoconutCrabTemplate",
	PopcornSheep     = "PopcornSheepTemplate",
	ButterDuck       = "ButterDuckTemplate",
	BurritoArmadillo = "BurritoArmadilloTemplate",
	SunflowerBee     = "SunflowerBeeTemplate",
	MapleFox         = "MapleFoxTemplate",
	FrostPenguin     = "FrostPenguinTemplate",
	BlossomBunny     = "BlossomBunnyTemplate",
}
local function speciesOf(key) return (tostring(key):gsub("#R$", "")) end

--======================================================================
-- VISUAL ENGINE  (ported from PetFollow.client.lua: theme/tier/rare data,
-- accessory + FX builders, applyLevelVisual, and the FX loop)
--======================================================================
local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
local PET_THEME = {
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
local RARE_LOOK = {
	BroccoliPet      = { name="Emerald Bunny",     body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(70,255,150) },
	CoconutCrab      = { name="Golden Crab",       body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,   refl=0.35, fx=Color3.fromRGB(255,225,90) },
	PopcornSheep     = { name="Cloud Sheep",       body=Color3.fromRGB(212,232,255), mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(225,242,255), puffs=true, light=true },
	BurritoArmadillo = { name="Crystal Armadillo", body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,   refl=0.25, fx=Color3.fromRGB(195,125,255) },
	ButterDuck       = { name="Cosmic Duck",       body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic, refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true },
}
local PET_DISPLAY = { BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny" }
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
local function petDisplayName(petId, isRare) return (isRare and RARE_LOOK[petId] and RARE_LOOK[petId].name) or PET_DISPLAY[petId] or petId end

local petFX = {}
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local accScale = 1
local function flagAccPart(p)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
local function accPart(pet, root, shape, sx, sy, sz, color, cf)
	local R = accScale
	local size = Vector3.new(sx*R, sy*R, sz*R)
	local bcf = CFrame.new(cf.Position * R) * (cf - cf.Position)
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=size; p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * bcf; p.Parent = pet
	return p
end
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end
local function buildAccessoryByKey(pet, root, theme, key, gold)
	if key == "bowtie" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		accPart(pet,root, BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "monocle" then
		local f = theme.face; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		accPart(pet,root, CYL_, 0.12,0.46,0.46, c, f * CFrame.new(0,0,(theme.glassW or 0.5)))
	elseif key == "bell" then
		local collar = gold and PRESTIGE_GOLD or Color3.fromRGB(170,45,55)
		local bell   = gold and PRESTIGE_GOLD or Color3.fromRGB(212,176,80)
		accPart(pet,root, CYL_, 1.5,0.22,0.22, collar, theme.neck * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,root, BAL_, 0.42,0.46,0.42, bell, theme.neck * CFrame.new(0.05,-0.34,0))
	elseif key == "scarf" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		accPart(pet,root, CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,root, BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "backpack" then
		local b = theme.back; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(120,90,58)
		accPart(pet,root, BLK_, 0.65,0.8,0.9, c, b)
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, BLK_, 0.55,0.12,0.16, gold and Color3.fromRGB(225,185,70) or Color3.fromRGB(88,64,40), b * CFrame.new(0.5,0.12,0.42*sgn)) end
	elseif key == "flower" then
		local e = theme.ear or theme.head; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); accPart(pet,root, BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		accPart(pet,root, BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sword" then
		local s = theme.side; local blade = gold and PRESTIGE_GOLD or Color3.fromRGB(200,205,215)
		accPart(pet,root, BLK_, 0.16,0.28,0.16, Color3.fromRGB(90,60,38), s)
		accPart(pet,root, BLK_, 0.34,0.12,0.12, gold and PRESTIGE_GOLD or Color3.fromRGB(205,170,70), s * CFrame.new(0,0.16,0))
		accPart(pet,root, BLK_, 0.14,1.0,0.14, blade, s * CFrame.new(0,0.7,0))
	elseif key == "crown" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(212,182,66)
		accPart(pet,root, CYL_, 0.16,1.05,1.05, c, h * CFrame.Angles(0,0,math.rad(90)))
		for i=0,4 do local ang=math.rad(i*72); accPart(pet,root, CYL_, 0.5,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.42, 0.3, math.cos(ang)*0.42) * CFrame.Angles(0,0,math.rad(90))) end
	elseif key == "piratehat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(34,34,40)
		accPart(pet,root, BAL_, 1.5,0.45,1.15, c, h)
		accPart(pet,root, BAL_, 0.95,0.78,0.85, c, h * CFrame.new(-0.05,0.45,0))
		accPart(pet,root, CYL_, 1.0,0.2,0.2, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(225,185,70), h * CFrame.new(0.45,0.05,0) * CFrame.Angles(0,math.rad(90),0))
	elseif key == "tophat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		accPart(pet,root, CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "safari" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(156,138,96)
		accPart(pet,root, CYL_, 0.12,1.5,1.5, c, h * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, BAL_, 0.95,0.66,0.95, c, h * CFrame.new(0,0.34,0))
		accPart(pet,root, CYL_, 0.2,0.92,0.92, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(110,92,60), h * CFrame.new(0,0.12,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "haloring" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90)
		for i=0,9 do local ang=math.rad(i*36); local p=accPart(pet,root, BAL_, 0.16,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.6, 0.85, math.cos(ang)*0.6)); p.Material=Enum.Material.Neon end
	elseif key == "staff" then
		local s = theme.side
		accPart(pet,root, CYL_, 1.7,0.14,0.14, Color3.fromRGB(120,84,46), s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,root, BAL_, 0.42,0.42,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90), s * CFrame.new(0,1.3,0)); p.Material=Enum.Material.Neon
	elseif key == "anchor" then
		local s = theme.side2 or theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,root, CYL_, 1.0,0.14,0.14, c, s * CFrame.new(0,0.2,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.6,0.14,0.14, c, s * CFrame.new(0,0.6,0) * CFrame.Angles(math.rad(90),0,0))
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, BLK_, 0.4,0.14,0.14, c, s * CFrame.new(0.18*sgn,-0.2,0) * CFrame.Angles(0,0,math.rad(40*sgn))) end
	elseif key == "gemcluster" then
		local cols = { Color3.fromRGB(95,215,205), Color3.fromRGB(120,180,255), Color3.fromRGB(235,225,205) }
		for k=0,3 do local p=accPart(pet,root, BAL_, 0.3,0.3,0.3, gold and PRESTIGE_GOLD or cols[(k%3)+1], CFrame.new(-0.35+k*0.28, 0.95, -0.1+(k%2)*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "crook" then
		local s = theme.side; local c = Color3.fromRGB(150,110,64)
		accPart(pet,root, CYL_, 1.8,0.14,0.14, c, s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.5,0.13,0.13, c, s * CFrame.new(-0.18,1.35,0) * CFrame.Angles(0,0,math.rad(35)))
		accPart(pet,root, CYL_, 0.4,0.13,0.13, c, s * CFrame.new(-0.42,1.18,0) * CFrame.Angles(0,0,math.rad(80)))
	elseif key == "cloudcluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,255,255)
		for k=0,3 do local ang=math.rad(k*90); accPart(pet,root, BAL_, 0.45,0.4,0.45, c, h * CFrame.new(math.sin(ang)*0.5, 0.8, math.cos(ang)*0.5)) end
	elseif key == "sparklecluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,root, BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.55, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		accPart(pet,root, CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	elseif key == "gemstuds" then
		for k=0,3 do local p=accPart(pet,root, BAL_, 0.26,0.26,0.26, gold and PRESTIGE_GOLD or Color3.fromRGB(120,200,210), CFrame.new(-0.7+k*0.5, 1.6, 0)); p.Material=Enum.Material.Neon end
	elseif key == "lantern" then
		local s = theme.side; local frame = gold and PRESTIGE_GOLD or Color3.fromRGB(90,72,46)
		accPart(pet,root, CYL_, 0.16,0.1,0.1, frame, s * CFrame.new(0,0.55,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,root, BLK_, 0.5,0.6,0.5, Color3.fromRGB(255,225,110), s); p.Material=Enum.Material.Neon
		accPart(pet,root, BLK_, 0.6,0.12,0.6, frame, s * CFrame.new(0,-0.34,0))
	elseif key == "pickaxe" then
		local s = theme.side2 or theme.side; local wood = Color3.fromRGB(120,84,46); local head = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,root, CYL_, 1.3,0.13,0.13, wood, s * CFrame.new(0,0.3,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, BLK_, 0.9,0.16,0.16, head, s * CFrame.new(0,0.85,0) * CFrame.Angles(0,0,math.rad(18)))
	end
end
local function clearEvo(pet)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" or n=="PetRareFX" or n=="PetRareLight" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" or c.Name=="PetPuff" then c:Destroy() end
	end
	petFX[pet] = nil
end
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25), sizeMul=1,
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
local function applyRareLook(pet, root, petId, bodyOnly)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="Eye" and n~="Highlight" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				d.Color = r.body; d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	if bodyOnly then return end -- icon clones: just the body recolor (no particles/light in a static viewport)
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(r.fx); rfx.LightEmission=0.85
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime = NumberRange.new(0.6,1.2); rfx.Rotation = NumberRange.new(0,360)
	rfx.Speed = NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size = NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent = root
	if r.light then local pl = Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=r.fx; pl.Brightness=1.5; pl.Range=12; pl.Parent=root end
	if r.puffs then for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,root, BAL_, 0.55,0.5,0.55, Color3.fromRGB(255,255,255), CFrame.new(math.sin(ang)*1.6, 0.7, math.cos(ang)*1.6)); p.Name="PetPuff" end end
	if r.cosmic and petFX[pet] then petFX[pet].cosmic = true end
end
local function applyLevelVisual(pet, level, petId, isRare, lite)
	if not pet or not pet.Parent then return end
	level = tonumber(level) or 1
	local root = pet.PrimaryPart
	local theme = PET_THEME[petId] or PET_THEME[pet.Name]
	if not (theme and root) then return end
	if isRare then level = 25 end
	local MAXL = 25
	local frac = clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = pet:GetAttribute("VisualLevel")
	accScale = 1
	clearEvo(pet)
	pcall(function() pet:ScaleTo(1) end)
	local sizeMul = 0.6 + 0.4 * frac
	local function ramp(startL) return clamp((level - startL) / (MAXL - startL), 0, 1) end
	if lite then
		-- ICON MODE: size + accessories + rare body recolor only (no particles/trail/light/FX/tag/pop).
		for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, root, theme, e[2], atMax) end end
		if isRare then applyRareLook(pet, root, petId, true) end
		pcall(function() pet:ScaleTo(sizeMul) end)
		pet:SetAttribute("VisualLevel", level)
		return
	end
	if level >= 2 then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor = theme.color; hl.OutlineColor = theme.color
		hl.FillTransparency = clamp(0.8 - 0.45*t, 0, 1); hl.OutlineTransparency = clamp(0.4 - 0.4*t, 0, 1)
		hl.Parent = pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=1.25+2*t; pl.Range=8+8*t; pl.Parent=root
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	if level >= 5 then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6; tr.Lifetime = 0.5 + 1.1*t
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, clamp(0.35 - 0.3*t, 0, 1)), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = root
	end
	if level >= 8 then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"
		pe.Rate = 14 + 90*t; pe.LightEmission = 0.7; pe.Rotation = NumberRange.new(0,360)
		pe.Lifetime = NumberRange.new(0.5, 1.0); pe.Speed = NumberRange.new(0.6, 1.6); pe.Size = NumberSequence.new(0.34)
		pe.Color = ColorSequence.new(theme.color)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) })
		pe.Parent = root
	end
	buildFX(pet, root, theme, level, atMax)
	if petFX[pet] then petFX[pet].sizeMul = sizeMul end
	for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, root, theme, e[2], atMax) end end
	if isRare then applyRareLook(pet, root, petId) end
	do
		local bb = root:FindFirstChild("LevelTag")
		if not bb then
			bb = Instance.new("BillboardGui"); bb.Name="LevelTag"; bb.Size=UDim2.new(0,200,0,42)
			bb.StudsOffset=Vector3.new(0,3.7,0); bb.AlwaysOnTop=true; bb.Parent=root
			local lbl = Instance.new("TextLabel"); lbl.Name="L"; lbl.Size=UDim2.new(1,0,0,20); lbl.Position=UDim2.new(0,0,0,0); lbl.BackgroundTransparency=1
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
			if flashy then
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stk.Color = Color3.fromRGB(255,255,255); stk.Thickness = 1; stk.Transparency = 0.2
			else
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; stk.Color = Color3.fromRGB(0,0,0); stk.Thickness = 1; stk.Transparency = 0.35
			end
		end
	end
	pcall(function() pet:ScaleTo(sizeMul) end)
	if prevLevel and level > prevLevel then
		local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
		burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
		burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root
		burst:Emit(20); Debris:AddItem(burst, 1.1)
	end
	pet:SetAttribute("VisualLevel", level)
end
-- FX LOOP
RunService.Heartbeat:Connect(function(dt)
	for pet, fx in pairs(petFX) do
		local root = pet.Parent and pet.PrimaryPart
		if not root then petFX[pet] = nil
		else
			fx.t = fx.t + dt
			local t = fx.t
			local rootCF = root.CFrame
			local sm = fx.sizeMul or 1
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
				fx.pulse.Transparency = clamp(ph, 0, 1)
				fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
			end
			if fx.burst then
				fx.burstClock = fx.burstClock - dt
				if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end
			end
			if fx.cosmic then
				local cc = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
				local rl = root:FindFirstChild("PetRareLight"); if rl then rl.Color = cc end
				local rfx = root:FindFirstChild("PetRareFX"); if rfx then rfx.Color = ColorSequence.new(cc) end
			end
			if fx.shimmer then
				local hue = (t * 0.25) % 1
				local c = Color3.fromHSV(hue, 0.45, 0.9)
				local hl = pet:FindFirstChild("LevelGlow")
				if hl then
					hl.OutlineColor = c; hl.OutlineTransparency = 0.25
					hl.FillColor = c; hl.FillTransparency = 0.88
				end
			end
		end
	end
end)

--======================================================================
-- LEVELING REMOTES (created by SpacePetLeveling.server.luau)
--======================================================================
local SpacePetEquipEvent = ReplicatedStorage:WaitForChild("SpacePetEquipEvent", 20)
local SpacePetProgress   = ReplicatedStorage:WaitForChild("SpacePetProgress", 20)
local SpacePetLevelEvent = ReplicatedStorage:WaitForChild("SpacePetLevelEvent", 20)

--======================================================================
-- FOLLOWER spawn / despawn / drive
--======================================================================
local currentModel = nil
local currentKey   = nil
local currentRare  = false
local faceDir      = Vector3.new(0, 0, -1)
local bobClock     = 0

local function despawnFollower()
	if currentModel then pcall(function() currentModel:Destroy() end) end
	currentModel = nil; currentKey = nil; currentRare = false
	if SpacePetEquipEvent then pcall(function() SpacePetEquipEvent:FireServer("") end) end
end

local function spawnFollower(key, level, rare)
	despawnFollower()
	local species = speciesOf(key)
	local tname = TEMPLATE_NAME[species]
	if not tname then warn("[SpacePet] no template mapping for '"..tostring(key).."'"); return end
	local template = ReplicatedStorage:FindFirstChild(tname) or ReplicatedStorage:WaitForChild(tname, 8)
	if not template then warn("[SpacePet] template '"..tname.."' missing — is PetTemplates.server.luau in this place?"); return end

	local model = template:Clone()
	model.Name = "SpaceFollower_" .. tostring(key)
	local lvl  = clamp(tonumber(level) or 1, 1, CONFIG.MAX_LEVEL)
	model:SetAttribute("PetKey", key)
	model:SetAttribute("Level", lvl)

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then model:PivotTo(hrp.CFrame * CFrame.new(0, CONFIG.FOLLOW_HEIGHT, CONFIG.FOLLOW_BEHIND)) end
	model.Parent = Workspace

	currentModel = model; currentKey = key; currentRare = (rare == true)
	-- FULL island look (size + accessories + aura/trail/sparkles + orbs/ring + rare body/light/cosmic + tier)
	applyLevelVisual(model, lvl, species, currentRare)
	if SpacePetEquipEvent then pcall(function() SpacePetEquipEvent:FireServer(key) end) end
end

RunService.RenderStepped:Connect(function(dt)
	local model = currentModel
	if not model or not model.Parent then return end
	local root = model.PrimaryPart
	if not root then return end
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	bobClock += dt
	local behind = hrp.CFrame.LookVector
	local side   = hrp.CFrame.RightVector
	local bob    = math.sin(bobClock * CONFIG.BOB_SPEED) * CONFIG.BOB_AMP
	local target = hrp.Position - behind * CONFIG.FOLLOW_BEHIND + side * CONFIG.FOLLOW_SIDE + Vector3.new(0, CONFIG.FOLLOW_HEIGHT + bob, 0)

	local curPos = model:GetPivot().Position
	if (curPos - hrp.Position).Magnitude > CONFIG.TELEPORT_DIST then
		model:PivotTo(CFrame.new(target)); return
	end
	local alpha  = 1 - math.exp(-dt * CONFIG.RESPONSIVENESS)
	local newPos = curPos:Lerp(target, alpha)

	local moveH = Vector3.new(newPos.X - curPos.X, 0, newPos.Z - curPos.Z)
	local wantDir
	if moveH.Magnitude > 0.02 then
		wantDir = moveH.Unit
	else
		wantDir = Vector3.new(behind.X, 0, behind.Z)
		if wantDir.Magnitude > 1e-3 then wantDir = wantDir.Unit else wantDir = faceDir end
	end
	local turn = math.clamp(dt * CONFIG.TURN_SPEED, 0, 1)
	local blended = faceDir + (wantDir - faceDir) * turn
	if blended.Magnitude > 1e-3 then faceDir = blended.Unit end
	model:PivotTo(CFrame.fromMatrix(newPos, faceDir, Vector3.yAxis))
end)

player.CharacterAdded:Connect(function() faceDir = Vector3.new(0, 0, -1) end)

-- server confirms the level on equip + every level-up -> re-render the new look
if SpacePetLevelEvent then
	SpacePetLevelEvent.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then return end
		local model = currentModel
		if not (model and model.Parent) then return end
		if model:GetAttribute("PetKey") ~= info.key then return end
		model:SetAttribute("Level", info.level)
		applyLevelVisual(model, info.level, speciesOf(info.key), currentRare)
	end)
end

-- FLIGHT DETECTION: while flying (airborne + moving, or rising fast), tick progress every 0.5s.
-- Your own flight code can also set _G.spaceForceFlying = true to force ticks.
local function isFlying()
	if _G.spaceForceFlying then return true end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then return false end
	local v = hrp.AssemblyLinearVelocity
	return (hum.FloorMaterial == Enum.Material.Air and v.Magnitude > 6) or (v.Y > 12)
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if currentModel and currentModel.Parent and isFlying() and SpacePetProgress then
			pcall(function() SpacePetProgress:FireServer() end)
		end
	end
end)

--======================================================================
-- PICKER UI  (styled like the main game's Pet inventory: a grid of BIG cards,
-- each with a slowly auto-rotating 3D preview of the actual pet at its level.)
--======================================================================
local getPets = ReplicatedStorage:WaitForChild("GetSpaceRealmPets", 30)
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

local gui = Instance.new("ScreenGui")
gui.Name = "SpacePetPickerGui"; gui.ResetOnSpawn = false; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 50; gui.Enabled = true; gui.Parent = playerGui

-- dim backdrop (click to close)
local dim = Instance.new("TextButton")
dim.Name = "Dim"; dim.Size = UDim2.fromScale(1,1); dim.BackgroundColor3 = Color3.new(0,0,0); dim.BackgroundTransparency = 0.45
dim.AutoButtonColor = false; dim.Text = ""; dim.Visible = false; dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"; panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(700, 540); panel.BackgroundColor3 = Color3.fromRGB(16, 60, 140)
panel.BorderSizePixel = 0; panel.Visible = false; panel.Parent = gui
uicorner(panel, 18); uistroke(panel, Color3.new(1,1,1), 3)

-- RESPONSIVE: scale this centered popup with the HUD on phone/tablet, same as the game's other popups.
-- Reads ResponsiveUI's published "ResponsiveScale" (phone/tablet only; desktop leaves it unset -> 1 = authored).
-- Owning our own UIScale makes ResponsiveUI's generic pass skip us, so there's never a double scale.
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel
local function syncPanelScale()
	local s = player:GetAttribute("ResponsiveScale")
	panelScale.Scale = (type(s) == "number" and s > 0) and s or 1
end
syncPanelScale()
player:GetAttributeChangedSignal("ResponsiveScale"):Connect(syncPanelScale)

local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,52); header.BackgroundColor3 = Color3.fromRGB(12, 44, 104); header.BorderSizePixel = 0; header.Parent = panel
uicorner(header, 18)
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Position = UDim2.fromOffset(18, 0); title.Size = UDim2.new(1, -70, 1, 0)
title.Font = Enum.Font.FredokaOne; title.TextSize = 24; title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 240, 255); title.Text = "\xF0\x9F\x90\xBE  Space Realm Pets"; title.Parent = header
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5); closeBtn.Position = UDim2.new(1, -12, 0.5, 0); closeBtn.Size = UDim2.fromOffset(34, 34)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 20; closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2)

local petsScroll = Instance.new("ScrollingFrame")
petsScroll.Position = UDim2.fromOffset(12, 62); petsScroll.Size = UDim2.new(1, -24, 1, -74); petsScroll.BackgroundTransparency = 1
petsScroll.BorderSizePixel = 0; petsScroll.ScrollBarThickness = 7; petsScroll.ScrollBarImageColor3 = Color3.fromRGB(120,160,255)
petsScroll.CanvasSize = UDim2.new(); petsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; petsScroll.Parent = panel
do
	local g = Instance.new("UIGridLayout"); g.CellSize = UDim2.new(0,322,0,252); g.CellPadding = UDim2.new(0,10,0,12)
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center; g.SortOrder = Enum.SortOrder.LayoutOrder; g.Parent = petsScroll
	local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0,8); pad.Parent = petsScroll
end
local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "PetsEmpty"; emptyLabel.BackgroundTransparency = 1; emptyLabel.Size = UDim2.new(1, -20, 0, 110)
emptyLabel.Font = Enum.Font.GothamBold; emptyLabel.TextSize = 18; emptyLabel.TextWrapped = true; emptyLabel.TextColor3 = Color3.fromRGB(190, 210, 255)
emptyLabel.Text = "No pets came through.\nCollect & equip a pet in Fart to Float, then ride the black hole here."
emptyLabel.Visible = false; emptyLabel.Parent = panel
emptyLabel.Position = UDim2.fromOffset(10, 90)

-- ===== 3D VIEWPORT ICONS (clone of the pet at its level, slowly auto-rotating) =====
local iconSpins = {}
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
				local tname = TEMPLATE_NAME[req.species]
				local template = tname and ReplicatedStorage:FindFirstChild(tname)
				local model = template and template:Clone()
				if model then
					if not model.PrimaryPart then model.PrimaryPart = model:FindFirstChild("Root") end
					local okFrame = pcall(function()
						model.Name = req.species .. "Icon"
						model:PivotTo(CFrame.new())
						model.Parent = req.vp
						applyLevelVisual(model, req.level, req.species, req.isRare, true) -- LITE: body + accessories + rare recolor
						local cf, size = model:GetBoundingBox()
						local maxe = math.max(size.X, size.Y, size.Z, 1)
						local center = cf.Position
						local dir = Vector3.new(0.8, 0.5, 0.55).Unit -- 3/4 front view (pets face +X), slightly above
						req.cam.CFrame = CFrame.lookAt(center + dir * (maxe * 1.45 + 1), center)
						iconSpins[#iconSpins+1] = { model = model, center = center }
					end)
					if okFrame then if req.ph then req.ph.Visible = false end
					else pcall(function() model:Destroy() end) end
				end
			end
			task.wait() -- one icon per frame -> no heavy burst
		end
		iconWorkerActive = false
		if #iconQueue > 0 then startIconWorker() end
	end)
end
local function makeViewportIcon(card, species, level, isRare)
	local vp = Instance.new("ViewportFrame"); vp.Name = "Icon3D"
	vp.AnchorPoint = Vector2.new(0.5,0); vp.Size = UDim2.new(0,310,0,140); vp.Position = UDim2.new(0.5,0,0,6)
	vp.BackgroundColor3 = Color3.fromRGB(12,34,78); vp.BackgroundTransparency = 0.15; vp.Parent = card
	uicorner(vp, 8)
	vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
	local ph = Instance.new("TextLabel"); ph.Name = "IconPlaceholder"; ph.Size = UDim2.new(1,0,1,0); ph.BackgroundTransparency = 1
	ph.Font = Enum.Font.FredokaOne; ph.TextScaled = true; ph.TextColor3 = Color3.fromRGB(150,180,235); ph.Text = "\xF0\x9F\x90\xBE"; ph.Parent = vp
	iconQueue[#iconQueue+1] = { vp = vp, cam = cam, ph = ph, species = species, level = level, isRare = isRare }
	startIconWorker()
	return vp
end
-- ONE slow auto-rotate loop for all icon clones; only runs while the panel is open
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

-- ===== CARDS =====
local cardData = {} -- [key] = { stroke=, btn=, isVariant=, tierColor= }
local function refreshButtonStates()
	for key, d in pairs(cardData) do
		local equipped = (key == currentKey)
		d.btn.Text = equipped and "UNEQUIP" or "EQUIP"
		d.btn.BackgroundColor3 = equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,80)
		d.stroke.Color = d.isVariant and d.tierColor or (equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(10,40,100))
		d.stroke.Thickness = (d.isVariant or equipped) and 3 or 1
	end
end
local function makeCard(entry, order)
	local species = speciesOf(entry.key)
	local rare = entry.rare == true
	local level = entry.level or 1
	local tierName, tierColor, isVariant = petTier(level, rare, species)

	local card = Instance.new("Frame"); card.Name = entry.key; card.LayoutOrder = order
	card.BackgroundColor3 = rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160); card.Parent = petsScroll
	uicorner(card, 12)
	local stroke = uistroke(card, isVariant and tierColor or Color3.fromRGB(10,40,100), isVariant and 3 or 1)

	makeViewportIcon(card, species, level, rare)

	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,20); nm.Position = UDim2.new(0,8,0,152)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 17
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = petDisplayName(species, rare); nm.Parent = card

	if isVariant then -- flashy Exotic/Mythical badge, top-right
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		local ts = uistroke(tag, Color3.fromRGB(255,255,255), 1); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Transparency = 0.2
	end

	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,-16,0,16); lv.Position = UDim2.new(0,8,0,176)
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 13; lv.TextColor3 = tierColor
	lv.Text = (isVariant and tierName or (tierName .. "  Lv " .. tostring(level))); lv.Parent = card

	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(1,-16,0,36); eq.Position = UDim2.new(0,8,0,206)
	eq.Font = Enum.Font.GothamBold; eq.TextSize = 15; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = Color3.fromRGB(50,200,80); eq.Text = "EQUIP"; eq.Parent = card
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1)
	eq.MouseButton1Click:Connect(function()
		if currentKey == entry.key then despawnFollower() else spawnFollower(entry.key, level, rare) end
		refreshButtonStates()
	end)

	cardData[entry.key] = { stroke = stroke, btn = eq, isVariant = isVariant, tierColor = tierColor }
end
local function rebuildList(pets, autoEquip)
	for key in pairs(cardData) do cardData[key] = nil end
	table.clear(iconSpins)
	for _, child in ipairs(petsScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
	if not pets or #pets == 0 then emptyLabel.Visible = true; return end
	emptyLabel.Visible = false
	-- sort by rarity tier, then level (high first) -- like the main game
	local rank = { Mythical=7, Exotic=6, Legendary=5, Epic=4, Rare=3, Uncommon=2, Common=1 }
	table.sort(pets, function(a, b)
		local ra = rank[petTier(a.level or 1, a.rare, speciesOf(a.key))] or 0
		local rb = rank[petTier(b.level or 1, b.rare, speciesOf(b.key))] or 0
		if ra ~= rb then return ra > rb end
		return (a.level or 0) > (b.level or 0)
	end)
	for i, entry in ipairs(pets) do
		makeCard(entry, i)
		if autoEquip and entry.equipped and not currentModel then spawnFollower(entry.key, entry.level, entry.rare) end
	end
	refreshButtonStates()
end
local function fetchPets()
	if not getPets then return {} end
	local ok, result = pcall(function() return getPets:InvokeServer() end)
	if ok and type(result) == "table" then return result end
	return {}
end
local function openPicker() rebuildList(fetchPets(), false); dim.Visible = true; panel.Visible = true end
local function closePicker() panel.Visible = false; dim.Visible = false end
local function togglePicker() if panel.Visible then closePicker() else openPicker() end end
closeBtn.MouseButton1Click:Connect(closePicker)
dim.MouseButton1Click:Connect(closePicker)

--======================================================================
-- HOOK THE BUTTON
--======================================================================
local function resolveConfiguredButton()
	if not CONFIG.BUTTON_PATH then return nil end
	local node = playerGui
	for _, childName in ipairs(CONFIG.BUTTON_PATH) do node = node and node:FindFirstChild(childName) end
	if node and node:IsA("GuiButton") then return node end
	return nil
end
local function looksLikePetButton(inst)
	if not inst:IsA("GuiButton") then return false end
	if inst:IsDescendantOf(gui) then return false end
	local hay = string.lower(inst.Name) .. " " .. string.lower((inst:IsA("TextButton") and inst.Text) or "")
	for _, m in ipairs(CONFIG.BUTTON_MATCH) do if string.find(hay, string.lower(m), 1, true) then return true end end
	return false
end
local function findExistingButton()
	local forced = resolveConfiguredButton(); if forced then return forced end
	for _, inst in ipairs(playerGui:GetDescendants()) do if looksLikePetButton(inst) then return inst end end
	return nil
end
local function createOwnButton()
	local btnGui = Instance.new("ScreenGui"); btnGui.Name = "SpacePetButtonGui"; btnGui.ResetOnSpawn = false; btnGui.Parent = playerGui
	local b = Instance.new("TextButton")
	b.Name = "PetsButton"; b.Position = UDim2.fromOffset(16, 120); b.Size = UDim2.fromOffset(120, 44)
	b.Font = Enum.Font.GothamBold; b.TextSize = 16; b.Text = "\xF0\x9F\x90\xBE Pets"
	b.TextColor3 = Color3.fromRGB(255, 255, 255); b.BackgroundColor3 = Color3.fromRGB(70, 110, 230); b.Parent = btnGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = b
	return b
end
local hooked = false
local function hookButton(btn)
	if hooked then return end
	hooked = true
	btn.Activated:Connect(togglePicker)
	print("[SpacePet] hooked Pets button: " .. btn:GetFullName())
end
task.spawn(function()
	local waited = 0
	while waited < 8 do
		local btn = findExistingButton()
		if btn then hookButton(btn); break end
		task.wait(0.25); waited += 0.25
	end
	if not hooked and CONFIG.CREATE_BUTTON_IF_MISSING then
		hookButton(createOwnButton())
		print("[SpacePet] no existing Pets button found — created one (top-left).")
	end
end)

-- auto-equip the previously-equipped pet shortly after join
task.spawn(function()
	if not getPets then return end
	for _ = 1, 40 do
		local pets = fetchPets()
		if #pets > 0 then rebuildList(pets, true); return end
		task.wait(0.25)
	end
end)

print("[SpacePet] Space Realm pet system ready (follower + island-accurate level/rare visuals + fly-to-level).")
