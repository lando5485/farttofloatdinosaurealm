--======================================================================
-- SpacePetTemplates.server.luau  -- DINO REALM copy of the SPACE REALM's four planet-pet template builders
-- (Solar Slug, Rover Raccoon, Blackhole Bat, Comet Cat), lifted verbatim from Space's PetTemplates.server.luau
-- (helpers + the "THE FOUR SPACE PETS" section). Builds the SAME fused models the Space Realm builds and stores
-- each in ReplicatedStorage under the same name ("SolarSlugTemplate"...), so the Pet Hub's SPACE tab clones the
-- EXACT renders -- the same arrangement FoodPetTemplates.server.luau uses for the FOOD tab.
-- CSG/UnionAsync is server-only, so the body is fused HERE then replicated. Cosmetic only (Anchored, Massless,
-- CanCollide=false). Local frame: +X = front. Names don't collide with this game's dino or food templates.
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

-- A glow the WORLD can see. Neon paints the part itself; a PointLight on it paints the ground and the player
-- beside it. Small ranges, so four of these following one player never wash a planet out.
local function glowLight(part, color, range, bright)
	local l = Instance.new("PointLight"); l.Color = color; l.Range = range or 8; l.Brightness = bright or 1.2
	l.Shadows = false; l.Parent = part
	return l
end

-- A rod between two points. Tails and crests used to be rows of separate balls with air between them,
-- which is the single biggest reason a built pet looks like parts on a box instead of a creature. Linking
-- each segment to the next with a rod that overlaps both ends turns the row into one continuous limb.
-- Coordinates are UNSCALED (the same numbers the P() calls use); P applies the scale.
local function link(P, name, x1, y1, z1, x2, y2, z2, dia, color)
	local a, b = Vector3.new(x1, y1, z1), Vector3.new(x2, y2, z2)
	local mid, d = (a + b) / 2, (b - a)
	local rot = (CFrame.lookAt(a, b) - a) * CFrame.Angles(0, math.rad(90), 0) -- cylinder X onto the a->b line
	return P(name, CYL, d.Magnitude * 1.15, dia, dia, color, mid.X, mid.Y, mid.Z, rot)
end

-- SPACE 1) SOLAR SLUG (Venus). A molten slug: eye stalks, a crest of sun-flare spikes, a cooling crust
-- underneath and a glowing core showing through the shell.
local function buildSolarSlugT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "SolarSlugTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local MOLTEN, CRUST, FLARE, CORE, LAVA = Color3.fromRGB(255,140,40), Color3.fromRGB(96,52,30), Color3.fromRGB(255,214,80), Color3.fromRGB(255,244,190), Color3.fromRGB(255,96,30)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, MOLTEN)
	-- FUSED INTO THE BODY, not stuck on: the eye-stalk roots swell out of the head, the first tail segment
	-- grows out of the back, and a soft belly bulge rounds the whole underside. Same colour as the body, so
	-- the union carries them and the silhouette reads as one soft creature.
	for _, sgn in ipairs({ 1, -1 }) do src[#src+1] = P("b", BAL, 0.9, 0.9, 0.9, MOLTEN, 1.0, 1.75, 0.62*sgn) end
	src[#src+1] = P("b", BAL, 2.2, 1.7, 2.6, MOLTEN, -1.4, -0.7, 0)   -- tail root, sunk into the back
	src[#src+1] = P("b", BAL, 3.2, 1.2, 3.0, MOLTEN, 0.2, -1.5, 0)    -- underside bulge
	local body, err = fuse(m, src, "BodyUnion", MOLTEN)
	-- Cooling crust: a dark cracked patch on the lower front, proud of the face so it never z-fights it.
	weldTo(P("Belly", BAL, 0.72, 1.3, 2.0, CRUST, 1.5, -1.05, 0), body)
	-- Eye STALKS: a slug's eyes sit up on stalks, so the eyes are drawn on their tips instead of the face.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Stalk", CYL, 1.3, 0.34, 0.34, MOLTEN, 1.1, 2.2, 0.62*sgn, CFrame.Angles(0,0,math.rad(90))), body)
		weldTo(P("Eye", BAL, 0.62, 0.62, 0.62, Color3.fromRGB(16,16,20), 1.2, 2.85, 0.62*sgn), body)
		weldTo(P("Highlight", BAL, 0.22, 0.22, 0.22, Color3.fromRGB(255,255,255), 1.42, 3.0, 0.62*sgn + 0.14*sgn), body)
	end
	-- SUN-FLARE CREST: five neon spikes fanned over the back, the middle one tallest (role "Ear" -> wiggles).
	for i, a in ipairs({ -40, -20, 0, 20, 40 }) do
		local len = 0.9 + (2 - math.abs(i - 3)) * 0.2
		local sp = weldTo(P("Ear", BLK, 0.26, len, 0.26, FLARE, -0.6, 1.95, 0, CFrame.Angles(math.rad(a), 0, math.rad(-12))), body)
		sp.Material = Enum.Material.Neon
	end
	-- A glowing core showing through the top of the shell.
	local core = weldTo(P("Core", BAL, 1.1, 0.5, 1.1, CORE, -0.2, 1.75, 0), body); core.Material = Enum.Material.Neon
	-- Slug tail: ONE tapered limb -- overlapping segments joined by rods, so there is no daylight anywhere
	-- along it, glowing hotter toward the tip.
	P("Tail", BAL, 1.6, 1.0, 1.4, MOLTEN, -2.1, -0.85, 0)
	link(P, "Tail", -2.1, -0.85, 0, -2.85, -1.02, 0, 0.75, MOLTEN)
	P("Tail", BAL, 1.1, 0.7, 1.0, MOLTEN, -2.85, -1.02, 0)
	link(P, "Tail", -2.85, -1.02, 0, -3.45, -1.18, 0, 0.5, LAVA).Material = Enum.Material.Neon
	local seg3 = P("Tail", BAL, 0.75, 0.5, 0.7, LAVA, -3.45, -1.18, 0); seg3.Material = Enum.Material.Neon
	link(P, "Tail", -3.45, -1.18, 0, -3.9, -1.28, 0, 0.3, FLARE).Material = Enum.Material.Neon
	local tip = P("Tail", BAL, 0.42, 0.3, 0.4, FLARE, -3.9, -1.28, 0); tip.Material = Enum.Material.Neon
	-- A slug has no feet: one flat foot-pad the whole length of the body, so it still stands on the ground line,
	-- with a thin neon slime-trail glow underneath it.
	P("Foot", BLK, 3.2, 0.5, 2.6, CRUST, 0.1, -1.75, 0)
	mouth(P, 1.74, -0.30, 0.42)
	glowLight(core, LAVA, 9, 1.4)
	return m, err
end

-- SPACE 2) BLACKHOLE BAT (Saturn). A near-black bat: ragged wings that flap, a neon violet event horizon on
-- its chest with a white singularity at the centre, and a fanged grin.
local function buildBlackholeBatT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BlackholeBatTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local INK, SLATE, VIOLET, MAGENTA, WHITE, DUST = Color3.fromRGB(22,18,34), Color3.fromRGB(58,50,80), Color3.fromRGB(150,70,255), Color3.fromRGB(255,90,220), Color3.fromRGB(255,248,255), Color3.fromRGB(120,110,150)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, INK)
	-- FUSED INTO THE BODY: the ear roots swell out of the top of the head and a shoulder hump on each side
	-- carries the wings, so wings and ears grow from the body instead of touching it.
	for _, sgn in ipairs({ 1, -1 }) do
		src[#src+1] = P("b", BAL, 1.0, 1.0, 1.0, INK, -0.1, 1.85, 1.0*sgn)
		src[#src+1] = P("b", BAL, 1.5, 1.3, 1.2, INK, -0.5, 0.9, 1.45*sgn)
	end
	src[#src+1] = P("b", BAL, 1.2, 1.0, 1.4, INK, -1.5, -0.7, 0) -- tail root
	local body, err = fuse(m, src, "BodyUnion", INK)
	-- Tall pointed ears (role "Ear") turned 45 degrees so the corner reads as the tip, with violet inners and
	-- a little fur tuft at each tip.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Ear", BLK, 0.55, 1.4, 0.55, INK, -0.1, 2.35, 1.0*sgn, CFrame.Angles(math.rad(14*sgn), math.rad(45), 0)), body)
		weldTo(P("EarIn", BLK, 0.32, 0.9, 0.32, VIOLET, -0.1, 2.3, 1.0*sgn, CFrame.Angles(math.rad(14*sgn), math.rad(45), 0)), body)
	end
	-- THE EVENT HORIZON on the chest: an accretion ring (neon violet), a fainter magenta outer ring, a dark
	-- hole and a white singularity dot dead centre.
	local r1 = weldTo(P("Ring", CYL, 0.14, 1.7, 1.7, VIOLET, 1.78, -0.55, 0), body); r1.Material = Enum.Material.Neon
	local r2 = weldTo(P("Ring", CYL, 0.1, 2.3, 2.3, MAGENTA, 1.72, -0.55, 0), body); r2.Material = Enum.Material.Neon; r2.Transparency = 0.55
	weldTo(P("Belly", CYL, 0.18, 1.1, 1.1, INK, 1.84, -0.55, 0), body)
	local sing = weldTo(P("Core", BAL, 0.34, 0.34, 0.34, WHITE, 1.92, -0.55, 0), body); sing.Material = Enum.Material.Neon
	-- RAGGED WINGS (role "Wing" -> the animator flaps them): a slab plus two smaller slabs stepped along its
	-- trailing edge, so the outline is scalloped rather than a clean rectangle, with two neon veins each.
	for _, sgn in ipairs({ 1, -1 }) do
		local tilt = CFrame.Angles(math.rad(22*sgn), 0, math.rad(14))
		-- the wing ARM: a bone from the shoulder out along the leading edge, with a knuckle where the slabs step
		link(P, "Wing", -0.4, 1.0, 1.4*sgn, -2.3, 0.05, 3.3*sgn, 0.26, INK)
		P("Wing", BAL, 0.4, 0.4, 0.4, INK, -1.3, 0.55, 2.35*sgn)
		P("Wing", BLK, 2.1, 1.7, 0.2, SLATE, -0.7, 0.9, 1.7*sgn, tilt)
		P("Wing", BLK, 1.4, 1.0, 0.2, SLATE, -1.55, 0.35, 2.55*sgn, tilt)
		P("Wing", BLK, 0.9, 0.6, 0.2, SLATE, -2.15, -0.05, 3.15*sgn, tilt)
		local v = P("Wing", CYL, 2.4, 0.1, 0.1, VIOLET, -1.0, 0.95, 1.75*sgn, tilt * CFrame.Angles(0, 0, math.rad(90))); v.Material = Enum.Material.Neon
	end
	-- Fangs + a small tail nub.
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Fang", BLK, 0.14, 0.32, 0.14, WHITE, 1.78, -0.05, 0.22*sgn), body) end
	link(P, "Tail", -1.7, -0.75, 0, -2.5, -1.0, 0, 0.26, INK)
	P("Tail", BAL, 0.5, 0.32, 0.32, INK, -2.5, -1.0, 0)
	-- Legs: short thighs from the body down to the feet, so the feet are not floating blocks.
	for _, sgn in ipairs({ 1, -1 }) do link(P, "Leg", 0.7, -1.1, 0.7*sgn, 0.85, -1.55, 0.7*sgn, 0.42, INK) end
	P("Foot", BLK, 0.7,0.55,0.7, SLATE, 0.85,-1.55,0.7); P("Foot", BLK, 0.7,0.55,0.7, SLATE, 0.85,-1.55,-0.7)
	eyes(P, 1.72, 0.6, 0.6); mouth(P, 1.74, 0.02, 0.5)
	glowLight(sing, VIOLET, 10, 1.6)
	return m, err
end

-- SPACE 3) ROVER RACCOON (Mars). A grey raccoon with the mask and the striped tail, wearing a jetpack with
-- twin neon exhaust cones.
local function buildRoverRaccoonT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "RoverRaccoonTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local GREY, DARK, CREAM, STEEL, FLAME, NOSE, RUST, LENS = Color3.fromRGB(128,128,138), Color3.fromRGB(44,42,52), Color3.fromRGB(232,226,214), Color3.fromRGB(180,186,196), Color3.fromRGB(255,150,40), Color3.fromRGB(30,26,28), Color3.fromRGB(196,84,48), Color3.fromRGB(120,200,255)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, GREY)
	-- FUSED INTO THE BODY: ear roots, a muzzle base the snout sits in, shoulders the arms hang from, and a
	-- tail root -- so nothing grey is a separate lump on a grey box.
	for _, sgn in ipairs({ 1, -1 }) do
		src[#src+1] = P("b", BAL, 0.9, 0.9, 0.9, GREY, -0.1, 1.8, 1.15*sgn)
		src[#src+1] = P("b", BAL, 1.1, 1.0, 1.0, GREY, 1.1, -0.4, 1.0*sgn)
	end
	src[#src+1] = P("b", BAL, 1.3, 1.1, 1.6, GREY, 1.5, -0.15, 0)   -- muzzle base
	src[#src+1] = P("b", BAL, 1.3, 1.1, 1.3, GREY, -1.6, -0.75, 0)  -- tail root
	local body, err = fuse(m, src, "BodyUnion", GREY)
	weldTo(P("Belly", BAL, 0.72, 1.5, 2.1, CREAM, 1.5, -0.9, 0), body)
	-- THE MASK: a dark band across the eyes, proud of the face so it never z-fights it.
	weldTo(P("Mask", BLK, 0.16, 0.9, 2.5, DARK, 1.76, 0.55, 0), body)
	-- Snout + nose + whisker dots.
	weldTo(P("Snout", BAL, 0.9, 0.7, 1.1, CREAM, 1.85, -0.2, 0), body)
	weldTo(P("Nose", BAL, 0.36, 0.3, 0.42, NOSE, 2.25, -0.05, 0), body)
	-- Round ears (role "Ear") with a cream inner.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Ear", BAL, 0.5, 0.85, 0.75, GREY, -0.1, 2.15, 1.15*sgn), body)
		weldTo(P("EarIn", BAL, 0.3, 0.5, 0.45, CREAM, 0.05, 2.15, 1.15*sgn), body)
	end
	-- THE JETPACK: a steel pack on the back with two cylinder tanks and two neon exhaust cones.
	local exhaustL -- one cone carries the light for both
	weldTo(P("Pack", BLK, 0.9, 1.9, 2.1, STEEL, -1.85, 0.2, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Tank", CYL, 2.0, 0.6, 0.6, DARK, -1.95, 0.3, 0.7*sgn, CFrame.Angles(0, 0, math.rad(90))), body)
		local cone = weldTo(P("Exhaust", BLK, 0.5, 0.7, 0.5, FLAME, -1.95, -0.95, 0.7*sgn, CFrame.Angles(0, math.rad(45), 0)), body)
		cone.Material = Enum.Material.Neon
		if sgn == 1 then exhaustL = cone end
	end
	-- STRIPED TAIL (role "Tail"): alternating grey / dark rings curving up, each joined to the next by a rod
	-- of the same colour, so it is one furry limb rather than a string of beads.
	local segs = { {-2.2,-0.9,0.8}, {-2.85,-0.55,0.7}, {-3.4,-0.05,0.6}, {-3.8,0.5,0.5}, {-4.05,1.0,0.4} }
	for i, seg in ipairs(segs) do
		local col = (i % 2 == 0) and DARK or GREY
		P("Tail", BAL, seg[3]*1.3, seg[3], seg[3], col, seg[1], seg[2], 0, CFrame.Angles(0, 0, math.rad(35)))
		local nxt = segs[i + 1]
		if nxt then link(P, "Tail", seg[1], seg[2], 0, nxt[1], nxt[2], 0, seg[3] * 0.85, col) end
	end
	-- Arms: an upper arm from the shoulder to the paw, not a paw alone.
	for _, sgn in ipairs({ 1, -1 }) do
		link(P, "Arm", 1.1, -0.4, 1.0*sgn, 1.45, -0.55, 0.85*sgn, 0.42, GREY)
		weldTo(P("Arm", BAL, 0.6, 0.5, 0.5, GREY, 1.4, -0.5, 0.8*sgn), body)
	end
	-- Boots: dark feet on short legs down from the body.
	for _, sgn in ipairs({ 1, -1 }) do
		link(P, "Leg", 0.8, -1.1, 0.72*sgn, 0.9, -1.55, 0.72*sgn, 0.5, GREY)
		P("Foot", BLK, 0.9,0.6,0.85, DARK, 0.9,-1.6,0.72*sgn)
	end
	eyes(P, 1.86, 0.55, 0.62); mouth(P, 1.74, -0.4, 0.34)
	glowLight(exhaustL, FLAME, 7, 1.3)
	return m, err
end

-- SPACE 4) COMET CAT (Neptune). A deep-blue cat whose tail is a comet: an icy neon streak with a glowing head,
-- a frost collar with a star tag, ice-crystal cheek tufts and a dusting of star freckles.
local function buildCometCatT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "CometCatTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local DEEP, ICE, GLOW, PINK, NAVY, STAR = Color3.fromRGB(44,70,150), Color3.fromRGB(190,232,255), Color3.fromRGB(120,220,255), Color3.fromRGB(240,150,170), Color3.fromRGB(26,40,96), Color3.fromRGB(255,240,160)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, DEEP)
	-- FUSED INTO THE BODY: ear roots, a rounded chest the ruff sits on, haunches at the back and a tail
	-- root, so the cat is one shape the comet grows out of.
	for _, sgn in ipairs({ 1, -1 }) do
		src[#src+1] = P("b", BAL, 0.9, 0.9, 0.9, DEEP, -0.1, 1.85, 1.05*sgn)
		src[#src+1] = P("b", BAL, 1.4, 1.5, 1.3, DEEP, -1.0, -0.6, 1.2*sgn) -- haunch
	end
	src[#src+1] = P("b", BAL, 1.2, 1.6, 2.4, DEEP, 1.3, -0.3, 0)     -- chest
	src[#src+1] = P("b", BAL, 1.3, 1.0, 1.2, DEEP, -1.6, -0.45, 0)   -- tail root
	local body, err = fuse(m, src, "BodyUnion", DEEP)
	weldTo(P("Belly", BAL, 0.72, 1.4, 2.0, ICE, 1.5, -1.0, 0), body)
	-- Pointed ears (role "Ear"): tall thin blocks turned 45 degrees so their corner reads as the tip, with an
	-- icy tuft at each tip.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Ear", BLK, 0.5, 1.1, 0.5, DEEP, -0.1, 2.25, 1.05*sgn, CFrame.Angles(math.rad(12*sgn), math.rad(45), 0)), body)
		weldTo(P("EarIn", BLK, 0.3, 0.7, 0.3, PINK, -0.1, 2.25, 1.05*sgn, CFrame.Angles(math.rad(12*sgn), math.rad(45), 0)), body)
		local tuft = weldTo(P("Tuft", BLK, 0.14, 0.4, 0.14, ICE, -0.1, 2.95, 1.2*sgn, CFrame.Angles(math.rad(18*sgn), 0, 0)), body); tuft.Material = Enum.Material.Neon
	end
	weldTo(P("Nose", BAL, 0.3, 0.24, 0.36, PINK, 1.78, -0.05, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do -- whiskers: three thin rods a side
		for i, a in ipairs({ -12, 0, 12 }) do
			weldTo(P("Whisker", CYL, 1.1, 0.06, 0.06, ICE, 1.7, -0.2 + (i-2)*0.12, 0.75*sgn, CFrame.Angles(math.rad(a), math.rad(90*sgn), 0)), body)
		end
	end
	-- Star freckles on the forehead and shoulders.
	for _, d in ipairs({ {1.72,1.1,0.3,0.2}, {1.72,1.3,-0.2,0.16}, {1.72,0.95,-0.5,0.14}, {0.4,1.2,1.78,0.16}, {-0.6,0.6,-1.78,0.14} }) do
		local st = weldTo(P("Dot", BAL, d[4], d[4], d[4], GLOW, d[1], d[2], d[3]), body); st.Material = Enum.Material.Neon
	end
	-- FROST COLLAR: a ring round the neck with a neon star tag hanging off the front.
	local collar = weldTo(P("Collar", CYL, 0.34, 3.1, 3.1, ICE, 0.9, 0.55, 0, CFrame.Angles(0, 0, math.rad(0))), body)
	collar.Transparency = 0.25
	local tag = weldTo(P("Tag", BLK, 0.14, 0.42, 0.42, STAR, 1.85, 0.05, 0, CFrame.Angles(math.rad(45), 0, 0)), body); tag.Material = Enum.Material.Neon
	-- THE COMET TAIL: an arc of shrinking neon segments sweeping up and back, brightest at the tip, with a
	-- scatter of tiny sparks trailing behind it.
	local cometHead
	local csegs = { {-1.7,-0.45,1.0}, {-2.3,-0.2,0.9}, {-2.9,0.2,0.75}, {-3.4,0.75,0.6}, {-3.85,1.4,0.5}, {-4.2,2.05,0.42} }
	for i, seg in ipairs(csegs) do
		local col = (i >= 5) and GLOW or ICE
		local t = P("Tail", BAL, seg[3]*1.5, seg[3], seg[3], col, seg[1], seg[2], 0, CFrame.Angles(0, 0, math.rad(30)))
		t.Material = Enum.Material.Neon
		if i == #csegs then cometHead = t end
		local nxt = csegs[i + 1]
		if nxt then link(P, "Tail", seg[1], seg[2], 0, nxt[1], nxt[2], 0, seg[3] * 0.8, col).Material = Enum.Material.Neon end
	end
	for _, d in ipairs({ {-3.0,-0.3,0.6}, {-3.7,0.4,-0.55}, {-4.4,1.3,0.5}, {-4.7,2.3,-0.3} }) do
		local sp = P("Tail", BAL, 0.14, 0.14, 0.14, STAR, d[1], d[2], d[3]); sp.Material = Enum.Material.Neon
	end
	-- Paws: dark blue feet with pale toe beans on the front, on short legs down from the body.
	for _, sgn in ipairs({ 1, -1 }) do
		link(P, "Leg", 0.8, -1.1, 0.72*sgn, 0.9, -1.55, 0.72*sgn, 0.5, DEEP)
		P("Foot", BLK, 0.85,0.7,0.85, NAVY, 0.9,-1.6,0.72*sgn)
		P("Bean", BAL, 0.12,0.2,0.4, PINK, 1.34,-1.55,0.72*sgn)
	end
	eyes(P, 1.72, 0.55, 0.62); mouth(P, 1.74, -0.36, 0.3)
	-- Two tiny ice moons orbiting the cat, a frosted glass ice-shell over the back of the head, a fluffy chest
	-- ruff, and a cold blue light off the comet's head.
	for i = 0, 1 do
		local a = i * math.pi + 0.6
		local moon = weldTo(P("Moon", BAL, 0.34, 0.34, 0.34, ICE, math.cos(a) * 2.3 - 0.2, 0.9 + math.sin(a) * 0.5, math.sin(a) * 2.3), body)
		moon.Material = Enum.Material.Neon
		weldTo(P("Moon", BAL, 0.14, 0.14, 0.14, STAR, math.cos(a + 0.5) * 2.5 - 0.2, 0.7 + math.sin(a + 0.5) * 0.5, math.sin(a + 0.5) * 2.5), body).Material = Enum.Material.Neon
	end
	local shell = weldTo(P("IceShell", BAL, 1.6, 1.1, 2.2, ICE, -0.9, 1.75, 0), body)
	shell.Material = Enum.Material.Glass; shell.Transparency = 0.45
	weldTo(P("Ruff", BAL, 0.7, 0.9, 2.3, ICE, 1.45, -0.2, 0), body).Transparency = 0.15
	glowLight(cometHead, GLOW, 9, 1.4)
	return m, err
end

local BUILDERS = {
	{ id = "SolarSlug",    fn = buildSolarSlugT },
	{ id = "RoverRaccoon", fn = buildRoverRaccoonT },
	{ id = "BlackholeBat", fn = buildBlackholeBatT },
	{ id = "CometCat",     fn = buildCometCatT },
}
task.spawn(function()
	for _, b in ipairs(BUILDERS) do
		local stale = RS:FindFirstChild(b.id .. "Template")
		if stale then stale:Destroy() end
		local ok, model, err = pcall(b.fn)
		if ok and model then
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
			model.Parent = RS
			if err then
				warn("[DinoRealm SpacePetTemplates] " .. b.id .. " union FAILED (" .. tostring(err) .. ") -- template ready with UNFUSED body")
			else
				print("[DinoRealm SpacePetTemplates] " .. b.id .. " built (" .. n .. " parts) -> " .. model.Name)
			end
		else
			warn("[DinoRealm SpacePetTemplates] " .. b.id .. " template build error: " .. tostring(model or err))
		end
	end
	print("[DinoRealm SpacePetTemplates] all 4 Space pet templates ready in ReplicatedStorage.")
end)