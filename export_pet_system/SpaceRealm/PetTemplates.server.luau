--======================================================================
-- PetTemplates.server.luau   — PUT THIS IN THE *SPACE REALM* PLACE
-- (ServerScriptService). Builds the SAME fused pet model templates the
-- main "Fart to Float" place builds, and stores each in ReplicatedStorage
-- under the same name (e.g. "ButterDuckTemplate"). The Space Realm follower
-- client (SpacePetFollower.client.luau) CLONES these to spawn followers.
--
-- This is a verbatim copy of the template-builder section of the main game's
-- PetSystem.server.lua, so the Space Realm pets look IDENTICAL to the islands.
-- CSG/UnionAsync is server-only, so the body is fused HERE then replicated.
-- Cosmetic only (Anchored, Massless, CanCollide=false). Local frame: +X = front.
--======================================================================

local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end)
		u.Parent = model
		return u, nil
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name.."Chunk" end
		return nil, tostring(u)
	end
end
local function newRoot(model)
	local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
end
local function weldTo(part, target)
	if part and target then
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
	end
	return part
end
local EYE_DIA = 0.82
local function eyes(P, fx, fy, fz)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = fz * sgn
		P("Eye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)
		P("Highlight", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16)
	end
end
local function mouth(P, fx, fy, w)
	P("Mouth", CYL, w, 0.18, 0.18, Color3.fromRGB(48,32,30), fx, fy, 0, CFrame.Angles(0, math.rad(90), 0))
end
local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
	a(BLK, D, iH, iW, 0,0,0)
	a(BLK, iD, H, iW, 0,0,0)
	a(BLK, iD, iH, W, 0,0,0)
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)
	end
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
		a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
		a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
		a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
	end
end
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- 1) BROCCOLI BUNNY
local function buildBroccoliBunny()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BroccoliBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local GREEN, FLOR, PINK, PINKI, WHITE = Color3.fromRGB(139,195,74), Color3.fromRGB(46,139,58), Color3.fromRGB(240,170,180), Color3.fromRGB(252,205,215), Color3.fromRGB(245,245,245)
	local LGREEN, BLKM = Color3.fromRGB(176,222,116), Color3.fromRGB(20,20,24)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, GREEN)
	local body, err = fuse(m, src, "BodyUnion", GREEN)
	local function roundedEar(cx, cy, cz, len, dia, color, rot)
		local up = (rot * CFrame.new(1, 0, 0)).Position
		local part = {
			P("b", CYL, len, dia, dia, color, cx, cy, cz, rot),
			P("b", BAL, dia, dia, dia, color, cx + up.X*len*0.5, cy + up.Y*len*0.5, cz + up.Z*len*0.5),
		}
		weldTo(fuse(m, part, "Ear", color), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.25 * sgn
		local rotEar = CFrame.Angles(math.rad(13) * sgn, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
		roundedEar(0.1,  2.4, zc, 3.1, 0.92, GREEN, rotEar)
		roundedEar(0.42, 2.4, zc, 2.25, 0.5,  PINKI, rotEar)
	end
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,0.78)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62)
	weldTo(P("Nose", BAL, 0.45,0.52,0.72, PINK, 1.74,-0.05,0), body)
	weldTo(P("Mouth", CYL, 0.32,0.1,0.1, BLKM, 1.74,-0.42,0,    CFrame.Angles(0,0,math.rad(90))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,0.18,  CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-34))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,-0.18, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(34))), body)
	weldTo(P("Mouth", BAL, 0.15,0.15,0.15, BLKM, 1.74,-0.585,0), body)
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.2,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-12))), body)
		weldTo(P("Whisker", CYL, 1.14,0.06,0.06, BLKM, 1.46,-0.32,0.95*sgn, CFrame.Angles(0,math.rad(90),0)), body)
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.44,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(12))), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Cheek", BAL, 0.6,0.52,0.5, LGREEN, 1.6,-0.18,0.72*sgn), body)
	end
	P("Tail", BAL, 1.05,1.05,1.05, WHITE, -1.6,-0.35,0)
	P("Floret", BAL, 0.62,0.54,0.62, FLOR, -0.3,1.9,0)
	P("Floret", BAL, 0.46,0.42,0.46, FLOR, 0.2,2.0,0.45)
	return m, err
end

-- 2) COCONUT CRAB
local function buildCoconutCrabT()
	local s = PSS * 0.78
	local m = Instance.new("Model"); m.Name = "CoconutCrabTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BROWN, DARK, CLAW = Color3.fromRGB(150,72,52), Color3.fromRGB(110,52,36), Color3.fromRGB(176,92,68)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW*1.05, PSH*0.72, PSD, PSR*0.95, BROWN)
	local _, err = fuse(m, src, "BodyUnion", BROWN)
	for _, sgn in ipairs({1,-1}) do P("Claw", BAL, 1.2,1.0,1.05, CLAW, 1.7,-0.1,1.15*sgn) end
	for _, sgn in ipairs({1,-1}) do
		for _, lx in ipairs({ 0.7, 0.0, -0.7 }) do
			P("Leg", BLK, 0.32,1.0,0.32, CLAW, lx,-1.05,1.55*sgn, CFrame.Angles(math.rad(22)*sgn,0,0))
		end
	end
	for _, d in ipairs({ {1.55,0.55,0.42},{1.55,0.55,-0.42} }) do P("Dot", BAL, 0.34,0.24,0.34, DARK, d[1],d[2],d[3]) end
	eyes(P, 1.34, 1.18, 0.6)
	mouth(P, 1.5, -0.05, 0.42)
	return m, err
end

-- 3) POPCORN SHEEP
local function buildPopcornSheepT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "PopcornSheepTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local CREAM, BLACK, FACEBLK, SNOUT = Color3.fromRGB(252,248,228), Color3.fromRGB(26,26,30), Color3.fromRGB(46,46,52), Color3.fromRGB(64,64,72)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, CREAM)
	for _, b in ipairs({ {0.0,1.75,0.55},{0.0,1.75,-0.55},{-0.7,1.8,0.0},{0.7,1.65,0.0},{-1.55,0.6,0.0},{0.0,0.6,1.6},{0.0,0.6,-1.6} }) do
		src[#src+1] = P("b", BAL, 1.15,1.1,1.15, CREAM, b[1],b[2],b[3])
	end
	local _, err = fuse(m, src, "BodyUnion", CREAM)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,-0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,-0.78)
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,0.95)
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,-0.95)
	P("FacePatch", BAL, 1.25,2.5,2.65, FACEBLK, 1.45,0.05,0)
	P("Snout", BAL, 0.9,0.85,1.0, SNOUT, 2.0,-0.5,0)
	eyes(P, 1.9, 0.45, 0.5)
	P("Nose", BAL, 0.34,0.26,0.46, Color3.fromRGB(16,16,20), 2.32,-0.45,0)
	mouth(P, 2.18, -0.82, 0.34)
	return m, err
end

-- 4) BUTTER DUCK
local function buildButterDuckT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "ButterDuckTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BUTTER, BILL = Color3.fromRGB(248,214,96), Color3.fromRGB(244,150,40)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BUTTER)
	src[#src+1] = P("b", BAL, 0.9,0.9,1.0, BUTTER, -1.6,0.5,0, CFrame.Angles(0,0,math.rad(28)))
	local _, err = fuse(m, src, "BodyUnion", BUTTER)
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,1.55)
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,-1.55)
	P("Bill", BLK, 0.55,0.65,1.25, BILL, 1.85,-0.05,0)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,0.72)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,-0.72)
	eyes(P, 1.72, 0.6, 0.6)
	return m, err
end

-- 5) BURRITO ARMADILLO
local function buildBurritoArmadilloT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BurritoArmadilloTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local TAN, SNT, BAND = Color3.fromRGB(196,150,100), Color3.fromRGB(150,96,56), Color3.fromRGB(168,124,80)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, TAN)
	for _, bx in ipairs({ -0.8,-0.2,0.4 }) do src[#src+1] = P("b", BAL, 0.55,0.9,2.7, BAND, bx,1.95,0) end
	src[#src+1] = P("b", BAL, 1.4,1.3,1.5, TAN, 1.82,0.0,0)
	local _, err = fuse(m, src, "BodyUnion", TAN)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,-0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,-0.82)
	P("Tail", BAL, 1.5,0.5,0.5, SNT, -2.1,-0.45,0, CFrame.Angles(0,0,math.rad(-12)))
	P("Nose", BAL, 0.34,0.28,0.34, SNT, 2.4,-0.22,0)
	eyes(P, 1.72, 0.95, 0.5)
	mouth(P, 2.18, -0.6, 0.32)
	return m, err
end

-- SEASONAL: SUNFLOWER BEE (Summer)
local function buildSunflowerBeeT()
	local s = PSS * 0.92
	local m = Instance.new("Model"); m.Name = "SunflowerBeeTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local YEL, BLKC, WHITE, PET = Color3.fromRGB(250,205,60), Color3.fromRGB(28,28,32), Color3.fromRGB(248,248,245), Color3.fromRGB(245,180,40)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, YEL); local body, err = fuse(m, src, "BodyUnion", YEL)
	for _, xo in ipairs({ -0.9, 0.0, 0.9 }) do weldTo(P("Stripe", BLK, 0.42, PSH*0.98, PSD*0.98, BLKC, xo, 0, 0), body) end
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.18, 1.7, 1.3, WHITE, -0.3, 1.5, 1.2*sgn, CFrame.Angles(math.rad(22*sgn),0,0)), body) end
	for i = 0, 9 do local a = i*(2*math.pi/10); weldTo(P("Petal", BAL, 0.32, 0.5, 1.15, PET, 1.5, math.cos(a)*1.5, math.sin(a)*1.5, CFrame.Angles(a,0,0)), body) end
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Antenna", CYL, 1.0, 0.1, 0.1, BLKC, 1.0, 2.4, 0.35*sgn, CFrame.Angles(0,0,math.rad(22))), body)
		weldTo(P("AntTip", BAL, 0.3,0.3,0.3, BLKC, 1.4, 2.85, 0.35*sgn), body)
	end
	eyes(P, 1.72, 0.45, 0.6); mouth(P, 1.78, -0.35, 0.62)
	return m, err
end
-- SEASONAL: MAPLE FOX (Autumn)
local function buildMapleFoxT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "MapleFoxTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local ORG, DORG, WHITE, BLKC = Color3.fromRGB(222,120,52), Color3.fromRGB(190,92,40), Color3.fromRGB(245,242,235), Color3.fromRGB(28,24,26)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, ORG); local body, err = fuse(m, src, "BodyUnion", ORG)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.0*sgn
		weldTo(P("Ear", BLK, 0.5, 1.5, 1.0, ORG, 0.2, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body)
		weldTo(P("Ear", BAL, 0.42, 0.8, 0.55, DORG, 0.3, 3.05, zc), body)
		weldTo(P("Ear", BLK, 0.3, 0.95, 0.5, WHITE, 0.42, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body)
	end
	weldTo(P("Snout", BAL, 0.6, 0.7, 0.95, WHITE, 1.5, -0.4, 0), body)
	weldTo(P("Nose", BAL, 0.34,0.3,0.44, BLKC, 1.98, -0.3, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.55,0.5, WHITE, 1.55, -0.12, 0.72*sgn), body) end
	P("Tail", BAL, 1.3,1.0,1.0, ORG, -1.7,-0.1,0); P("Tail", BAL, 0.85,0.85,0.85, WHITE, -2.45,0.1,0)
	P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,0.8); P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,-0.8)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.7, -0.7, 0.5)
	return m, err
end
-- SEASONAL: FROST PENGUIN (Winter)
local function buildFrostPenguinT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "FrostPenguinTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local NAVY, BELLY, ORG, ICE = Color3.fromRGB(38,46,74), Color3.fromRGB(244,246,250), Color3.fromRGB(240,150,40), Color3.fromRGB(180,225,245)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, NAVY); local body, err = fuse(m, src, "BodyUnion", NAVY)
	weldTo(P("Belly", BLK, 0.3, 2.5, 2.3, BELLY, 1.55, -0.3, 0), body)
	weldTo(P("Beak", BAL, 0.75, 0.5, 0.7, ORG, 1.95, 0.05, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.9, 1.9, 0.26, NAVY, -0.1, 0.1, 1.85*sgn, CFrame.Angles(math.rad(12*sgn),0,0)), body) end
	P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,0.7); P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,-0.7)
	for _, d in ipairs({ {0,2.25,0,0.6}, {0.5,2.1,0.6,0.42}, {-0.5,2.1,-0.55,0.42} }) do
		weldTo(P("Crystal", BLK, d[4],d[4],d[4], ICE, d[1], d[2], d[3], CFrame.Angles(0,math.rad(45),math.rad(45))), body)
	end
	eyes(P, 1.72, 0.6, 0.5)
	return m, err
end
-- SEASONAL: BLOSSOM BUNNY (Spring)
local function buildBlossomBunnyT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BlossomBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local PGREEN, PINK, WHITE, FLPINK, FLWHT, YEL = Color3.fromRGB(186,224,150), Color3.fromRGB(240,150,180), Color3.fromRGB(248,248,245), Color3.fromRGB(245,160,195), Color3.fromRGB(250,248,250), Color3.fromRGB(250,215,90)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, PGREEN); local body, err = fuse(m, src, "BodyUnion", PGREEN)
	local function ear(cx,cy,cz,len,dia,color,rot)
		local up = (rot * CFrame.new(1,0,0)).Position
		local part = { P("b",CYL,len,dia,dia,color,cx,cy,cz,rot), P("b",BAL,dia,dia,dia,color,cx+up.X*len*0.5,cy+up.Y*len*0.5,cz+up.Z*len*0.5) }
		weldTo(fuse(m, part, "Ear", color), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.1*sgn; local rot = CFrame.Angles(math.rad(10*sgn),0,0) * CFrame.Angles(0,0,math.rad(90))
		ear(0.1, 2.9, zc, 3.9, 0.85, PGREEN, rot)
		ear(0.42, 2.9, zc, 3.0, 0.46, FLPINK, rot)
	end
	for i = -2, 2 do
		local zz = i * 0.66; local col = (i % 2 == 0) and FLPINK or FLWHT
		weldTo(P("Flower", BAL, 0.42,0.42,0.42, col, 0.35, 2.05, zz), body)
		weldTo(P("FlowerCtr", BAL, 0.2,0.2,0.2, YEL, 0.52, 2.1, zz), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.45,0.45, PINK, 1.6,-0.15,0.7*sgn), body) end
	weldTo(P("Nose", BAL, 0.34,0.32,0.46, PINK, 1.78,-0.05,0), body)
	P("Tail", BAL, 1.0,1.0,1.0, WHITE, -1.65,-0.3,0)
	P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,0.78); P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.74, -0.42, 0.4)
	return m, err
end

local PET_TEMPLATE_BUILDERS = {
	{ id = "BroccoliPet",      fn = buildBroccoliBunny },
	{ id = "CoconutCrab",      fn = buildCoconutCrabT },
	{ id = "PopcornSheep",     fn = buildPopcornSheepT },
	{ id = "ButterDuck",       fn = buildButterDuckT },
	{ id = "BurritoArmadillo", fn = buildBurritoArmadilloT },
	{ id = "SunflowerBee",     fn = buildSunflowerBeeT,     seasonal = true, name = "Sunflower Bee" },
	{ id = "MapleFox",         fn = buildMapleFoxT,         seasonal = true, name = "Maple Fox" },
	{ id = "FrostPenguin",     fn = buildFrostPenguinT,     seasonal = true, name = "Frost Penguin" },
	{ id = "BlossomBunny",     fn = buildBlossomBunnyT,     seasonal = true, name = "Blossom Bunny" },
}
task.spawn(function()
	for _, b in ipairs(PET_TEMPLATE_BUILDERS) do
		local ok, model, err = pcall(b.fn)
		if ok and model then
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
			model.Parent = RS
			if err then
				warn("[SpaceRealm PetTemplates] "..b.id.." union FAILED ("..tostring(err)..") -- template ready with UNFUSED body (still appears)")
			else
				print("[SpaceRealm PetTemplates] "..b.id.." built ("..n.." parts) -> "..model.Name)
			end
		else
			warn("[SpaceRealm PetTemplates] "..b.id.." template build error: "..tostring(model or err))
		end
	end
	print("[SpaceRealm PetTemplates] all pet templates ready in ReplicatedStorage.")
end)
