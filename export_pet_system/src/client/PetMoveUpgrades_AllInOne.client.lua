--======================================================================
-- PetMoveUpgrades_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of THREE pet systems from PetFollow.client.lua,
-- lifted VERBATIM so they behave identically:
--
--   1. FOLLOW MOVEMENT -- how the pet moves with you: an eased spring glide
--      to an offset behind/right/above you, a SLOWER facing spring (so it
--      swings round to turn, not snap), a gentle bob, and a max-trail clamp
--      so a fast fart-ascent can never strand it. (+ the per-part animator:
--      bob/sway/blink/leg-gait/wing-flap/claw-scuttle.)
--
--   2. UPGRADES (leveling visuals) -- applyLevelVisual: the EXACT level->look
--      schedule. SIZE 60%@Lv1 -> 100%@Lv25 (every level), AURA@2, TRAIL@5,
--      SPARKLES@8, ORBS@11/14/19, energy RING@15, PULSE@18, BURST@24, GOLD
--      trim + rainbow shimmer @25, and the per-pet ACCESSORY schedule
--      (3/7/10/13/17/20/23). Plus the RARE variant body sheen/aura.
--
--   3. THE TRAIL -- the little themed Trail behind the pet (two Attachments on
--      the root + a Trail that lengthens/brightens as it levels). It's part of
--      the upgrades (Lv5+) and is broken out + commented below.
--
-- DEMO HARNESS: spawns ONE pet that follows you. Use the keys to watch the
-- upgrades roll in live:
--   ]  -> level +1        [  -> level -1
--   R  -> toggle RARE      P -> cycle which pet
-- A small label (top-center) shows the current pet / level / tier.
--
-- Drop into StarterPlayer > StarterPlayerScripts (or sync via Rojo). No server
-- or other scripts needed.
--======================================================================

local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local RunService   = game:GetService("RunService")
local UserInput    = game:GetService("UserInputService")
local Debris       = game:GetService("Debris")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

-- ============================================================================
-- PART HELPERS + animator registry (VERBATIM)
-- ============================================================================
local petAnims = setmetatable({}, { __mode = "k" }) -- model -> { s, parts={{part,base,baseSize,role,eye}}, t, move, blink, sizeMul, popClock, lastVisualLevel }
local petFX = {}                                    -- model -> animated effect state (orbs/ring/pulse/burst/shimmer)
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- ============================================================================
-- PET BUILDERS (role-tagged, so the animator drives legs/wings/etc.) -- copied
-- from PetFollow.client.lua. +X = front.
-- ============================================================================
local function buildCoconutCrab(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "CoconutCrab"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p,base=p.CFrame,baseSize=p.Size,role=role or "body",eye=eye}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0, "body")
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0, "body"); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4, "body"); mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4, "body")
	for _, ez in ipairs({-0.45, 0.45}) do mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez, "body", true); mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez, "body", true) end
	for _, cs in ipairs({-1, 1}) do mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2, "claw"); mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45, "claw") end
	for _, ls in ipairs({-1, 1}) do for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95, "leg") end end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }; return model
end
local function buildPopcornSheep(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "PopcornSheep"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p,base=p.CFrame,baseSize=p.Size,role=role or "body",eye=eye}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0, "body")
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},{0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do local r = 0.72 + math.abs(b[2])*0.04; mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3], "body") end
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0, "head"); mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62, "ear"); mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62, "ear")
	for _, ez in ipairs({0.32, -0.32}) do mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez, "head", true); mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez, "head", true) end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0, "head")
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2], "leg") end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0, "tail")
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }; return model
end
local function buildButterDuck(scale)
	local s = scale or 1; local model = Instance.new("Model"); model.Name = "ButterDuck"; local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye) local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s)); parts[#parts+1]={part=p,base=p.CFrame,baseSize=p.Size,role=role or "body",eye=eye}; return p end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0)); root.Transparency = 1; model.PrimaryPart = root
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0, "body"); mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0, "tail"); mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0, "tail")
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0, "head"); mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0, "head")
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0, "head"); mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0, "head")
	for _, ez in ipairs({0.42, -0.42}) do mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez, "head", true); mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez, "head", true) end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15, "wing") end
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls, "leg") end
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = 0.08 end end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }; return model
end
local PET_BUILDER = { CoconutCrab = buildCoconutCrab, PopcornSheep = buildPopcornSheep, ButterDuck = buildButterDuck }

-- ============================================================================
-- RARITY LABELS + DISPLAY NAMES (VERBATIM)
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
local PET_DISPLAY = { CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck" }

-- ============================================================================
-- UPGRADE THEME + RARE LOOKS (VERBATIM)
-- ============================================================================
local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
local PET_THEME = {
	CoconutCrab = { color=Color3.fromRGB(170,100,60),
		head=CFrame.new(-0.1,1.0,0), face=CFrame.new(0.92,0.78,0), glassW=0.4, neck=CFrame.new(0.7,0.05,0), back=CFrame.new(-0.85,0.45,0), side=CFrame.new(0,0.2,1.15), side2=CFrame.new(0,0.2,-1.15),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"anchor"} } },
	PopcornSheep = { color=Color3.fromRGB(248,244,230),
		head=CFrame.new(1.1,1.55,0), face=CFrame.new(1.65,0.4,0), glassW=0.45, neck=CFrame.new(1.1,-0.35,0), back=CFrame.new(-1.4,0.4,0), ear=CFrame.new(0.5,1.6,0.85), side=CFrame.new(0.3,-0.2,1.4),
		accs={ {3,"bell"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"cloudcluster"},{23,"crook"} } },
	ButterDuck = { color=Color3.fromRGB(250,205,75),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
}
local RARE_LOOK = {
	CoconutCrab  = { name="Golden Crab", body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,  refl=0.35, fx=Color3.fromRGB(255,225,90) },
	PopcornSheep = { name="Cloud Sheep", body=Color3.fromRGB(212,232,255), mat=Enum.Material.Plastic, refl=0.1, fx=Color3.fromRGB(225,242,255), puffs=true, light=true },
	ButterDuck   = { name="Cosmic Duck", body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic, refl=0.1, fx=Color3.fromRGB(180,140,255), cosmic=true, light=true },
}
local function petDisplayName(petId, isRare) return (isRare and RARE_LOOK[petId] and RARE_LOOK[petId].name) or PET_DISPLAY[petId] or petId end

-- ===== accessory / fx part factories (VERBATIM) =====
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

-- ===== ALL accessory builders (VERBATIM) =====
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
		local e = theme.ear or theme.head; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
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
	end
end

-- ===== clear / fx / rare (VERBATIM) =====
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
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0) -- ORBS: 1@11, 2@14, 3@19
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end end -- RING@15
	if level >= 18 then fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2) end -- PULSE@18
	if level >= 24 then -- BURST@24
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
				d.Color = r.body; d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(r.fx); rfx.LightEmission=0.85
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime = NumberRange.new(0.6,1.2); rfx.Rotation = NumberRange.new(0,360)
	rfx.Speed = NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size = NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent = root
	if r.light then local pl = Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=r.fx; pl.Brightness=3*0.75; pl.Range=12; pl.Parent=root end
	if r.puffs and A then for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.55,0.5,0.55, Color3.fromRGB(255,255,255), CFrame.new(math.sin(ang)*1.6, 0.7, math.cos(ang)*1.6)) end end
	if r.cosmic and petFX[pet] then petFX[pet].cosmic = true end
end

-- ============================================================================
-- THE UPGRADE FUNCTION (applyLevelVisual) -- VERBATIM. The level->look schedule.
-- ============================================================================
local function applyLevelVisual(pet, level, petId, isRare, lite)
	if not pet then return end
	level = level or 1
	local root = pet.PrimaryPart
	local A = petAnims[pet]
	local theme = PET_THEME[petId] or PET_THEME[pet.Name]
	if not theme then return end
	if isRare then level = 25 end -- RARE pets display PRE-MAXED (full lvl-25 look)
	local MAXL = 25
	local frac = math.clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = A and A.lastVisualLevel or nil
	accScale = 1
	clearEvo(pet, A)
	-- (1) SIZE: 60% @Lv1 -> 100% @Lv25 (+1.667%/level) -- the guaranteed visible change every level.
	if A then A.sizeMul = 0.6 + 0.4 * frac end
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	-- (2) AURA @Lv2: a themed Highlight glow + PointLight + soft particles, brightening each level.
	if level >= 2 and root and not lite then
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
	-- ============================ (3) THE TRAIL @Lv5 ============================
	-- Two Attachments on the ROOT (one 1 stud up, one 1 down -> the trail's width)
	-- + a Trail between them. As the pet moves, Roblox streaks a ribbon between the
	-- attachments. It LENGTHENS (Lifetime 0.5 -> 1.6) + BRIGHTENS (less transparent)
	-- as the level climbs from 5 -> 25. Themed to the pet's color.
	if level >= 5 and root and not lite then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6; tr.Lifetime = 0.5 + 1.1*t
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.3*t, 0, 1)), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = root
	end
	-- ===========================================================================
	-- (4) SPARKLES @Lv8: themed sparkle particles, denser each level.
	if level >= 8 and root and not lite then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"
		pe.Rate = 14 + 90*t; pe.LightEmission = 0.7; pe.Rotation = NumberRange.new(0,360)
		pe.Lifetime = NumberRange.new(0.5, 1.0); pe.Speed = NumberRange.new(0.6, 1.6); pe.Size = NumberSequence.new(0.34)
		pe.Color = ColorSequence.new(theme.color)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) })
		pe.Parent = root
	end
	-- (5) ANIMATED EFFECTS: orbs (11/14/19), energy ring (15), pulse (18), burst (24) -> petFX, animated by the FX loop.
	if root and not lite then buildFX(pet, root, theme, level, atMax) end
	-- (6) ACCESSORIES: the per-pet list, each at its exact level (3/7/10/13/17/20/23), accumulating. GOLD trim at MAX.
	if A and root then
		for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, A, root, theme, e[2], atMax) end end
	end
	-- (7) RARE: pre-maxed + the unique rare body sheen/aura on top.
	if isRare and root then applyRareLook(pet, A, root, petId) end
	-- LEVEL-UP POP: every live level-up -> a tiny scale-pop + a one-shot sparkle burst.
	local leveledUp = prevLevel and level > prevLevel
	if leveledUp then
		if A then A.popClock = 0.4 end
		if root then
			local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
			burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
			burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root
			burst:Emit(20)
			Debris:AddItem(burst, 1.1)
		end
	end
	if A then A.lastVisualLevel = level end
	if lite then return end
	local nAcc = 0; for _, e in ipairs(theme.accs) do if level >= e[1] then nAcc = nAcc + 1 end end
	local nOrb = (level>=11 and 1 or 0)+(level>=14 and 1 or 0)+(level>=19 and 1 or 0)
	print(string.format("[PetEvo] %s Lvl %d: size %d%%, aura %s, trail %s, sparkles %s, orbs %d, ring %s, pulse %s, burst %s, accessories %d, shimmer %s",
		pet.Name, level, math.floor((0.6 + 0.4*frac)*100),
		(level>=2) and "on" or "off", (level>=5) and "on" or "off", (level>=8) and "on" or "off",
		nOrb, (level>=15) and "on" or "off", (level>=18) and "on" or "off", (level>=24) and "on" or "off", nAcc, atMax and "on" or "off"))
end

-- ============================================================================
-- FX LOOP (VERBATIM): orbit orbs, spin ring, expand+fade pulse, periodic burst,
-- cosmic rainbow, MAX shimmer. One Heartbeat for all pets.
-- ============================================================================
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
				local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
				for _, orb in ipairs(fx.orbs) do orb.Color = c end
				for _, seg in ipairs(fx.ring) do seg.part.Color = c end
			end
		else
			petFX[pet] = nil
		end
	end
end)

-- ============================================================================
-- PER-PART ANIMATOR (VERBATIM): bob/sway/blink + leg gait, ear flop, wing flap,
-- claw scuttle. Reads the live root CFrame each frame.
-- ============================================================================
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
		if since < 0.16 then eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1))
		else A.blink = 1.8 + math.random() * 3.4 end
	end
	for _, e in ipairs(A.parts) do
		local bp = e.base
		local localCF
		if e.role == "head" then localCF = globalT * headT * bp
		elseif e.role == "tail" then localCF = globalT * tailRot * bp
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
		else localCF = globalT * bp end
		local sm = (A.sizeMul or 1) * (A.popMul or 1)
		if sm ~= 1 then local p = localCF.Position; localCF = CFrame.new(p * sm) * (localCF - p) end
		e.part.CFrame = rootCF * localCF
		if e.eye then e.part.Size = Vector3.new(e.baseSize.X * sm, e.baseSize.Y * eyeY * sm, e.baseSize.Z * sm)
		elseif sm ~= 1 then e.part.Size = e.baseSize * sm end
	end
end

-- ============================================================================
-- FOLLOW MOVEMENT (VERBATIM): the constants + the RenderStepped follow loop.
-- ============================================================================
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)  -- right, up, BEHIND (+Z) in the player's local frame
local FOLLOW_K      = 6    -- POSITION responsiveness (lower = softer, flowier glide)
local FACE_K        = 4    -- FACING responsiveness (slower than FOLLOW_K so the pet SWINGS round to turn)
local MAX_TRAIL     = 45   -- never let the pet fall further than this behind -> can't be lost in a fast ascent
local petSmoothPos  = nil
local petSmoothFwd  = nil
local bobT          = 0

-- single demo pet (the real game keeps a petState table; here one st is enough)
local st = { pet = nil, level = 1, rare = false, petId = "CoconutCrab", emerging = false }

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pet = st.pet
	if pet and pet.Parent and pet.PrimaryPart and not st.emerging then
		if hrp then
			local targetCF = hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)
			local targetPos = targetCF.Position
			if not petSmoothPos then petSmoothPos = targetPos end
			local alpha = 1 - math.exp(-FOLLOW_K * dt) -- frame-rate-independent ease
			petSmoothPos = petSmoothPos:Lerp(targetPos, alpha)
			local back = petSmoothPos - targetPos
			if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
			bobT = bobT + dt
			local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 1.4) * 0.10, 0)
			local fwd = hrp.CFrame.LookVector
			fwd = Vector3.new(fwd.X, 0, fwd.Z)
			if fwd.Magnitude < 0.05 then fwd = (petSmoothFwd or Vector3.new(0, 0, -1)) end
			fwd = fwd.Unit
			if not petSmoothFwd then petSmoothFwd = fwd end
			local fAlpha = 1 - math.exp(-FACE_K * dt) -- slower facing spring -> graceful swing turns
			petSmoothFwd = petSmoothFwd:Lerp(fwd, fAlpha)
			if petSmoothFwd.Magnitude < 0.05 then petSmoothFwd = fwd end
			local face = petSmoothFwd.Unit
			pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0)) -- +X = front -> yaw +90
		end
		animatePet(pet, dt)
	end
end)

-- ============================================================================
-- DEMO HARNESS: spawn the pet + a label + level/rare/pet controls.
-- ============================================================================
local function spawnFollower()
	if st.pet then st.pet:Destroy(); st.pet = nil; petAnims[st.pet] = nil end
	local builder = PET_BUILDER[st.petId] or buildCoconutCrab
	st.pet = builder(0.9)
	st.pet.Name = st.petId
	st.pet.Parent = Workspace
	petSmoothPos = nil; petSmoothFwd = nil
	st.lastApplied = nil
	applyLevelVisual(st.pet, st.level, st.petId, st.rare)
end

local gui = Instance.new("ScreenGui"); gui.Name = "PetMoveUpgradesDemo"; gui.ResetOnSpawn = false; gui.Parent = pg
local lbl = Instance.new("TextLabel"); lbl.AnchorPoint = Vector2.new(0.5,0); lbl.Position = UDim2.new(0.5,0,0,12); lbl.Size = UDim2.new(0,520,0,52)
lbl.BackgroundColor3 = Color3.fromRGB(15,60,140); lbl.BackgroundTransparency = 0.15; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16
lbl.TextColor3 = Color3.new(1,1,1); lbl.TextWrapped = true; lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0,10)
local function refreshLabel()
	local tierName = select(1, petTier(st.level, st.rare, st.petId))
	lbl.Text = string.format("%s  |  Lv %d  |  %s\n]/[ level +/-     R rare: %s     P pet",
		petDisplayName(st.petId, st.rare), st.level, tierName, st.rare and "ON" or "off")
end
local function setLevel(lv)
	st.level = math.clamp(lv, 1, 25)
	applyLevelVisual(st.pet, st.level, st.petId, st.rare) -- live re-apply = exactly what a level-up does
	refreshLabel()
end
UserInput.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.RightBracket then setLevel(st.level + 1)
	elseif io.KeyCode == Enum.KeyCode.LeftBracket then setLevel(st.level - 1)
	elseif io.KeyCode == Enum.KeyCode.R then st.rare = not st.rare; applyLevelVisual(st.pet, st.level, st.petId, st.rare); refreshLabel()
	elseif io.KeyCode == Enum.KeyCode.P then
		local order = { "CoconutCrab", "PopcornSheep", "ButterDuck" }
		local i = (table.find(order, st.petId) or 0) % #order + 1
		st.petId = order[i]; spawnFollower(); refreshLabel()
	end
end)

spawnFollower()
refreshLabel()
print("[PetMoveUpgrades] pet following. ]/[ to change level, R rare, P swap pet")
