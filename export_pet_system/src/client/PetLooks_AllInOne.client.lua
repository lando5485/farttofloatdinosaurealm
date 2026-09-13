--======================================================================
-- PetLooks_AllInOne.client.lua  (LocalScript)
--======================================================================
-- A SELF-CONTAINED copy of how 3 of the game's pets LOOK + how they idle-
-- animate, lifted VERBATIM from PetFollow.client.lua. Drop this one script
-- into StarterPlayer > StarterPlayerScripts (or sync via Rojo) and it spawns
-- the three pets in a row in front of spawn so you can see them. No remotes,
-- no server code, no other scripts needed.
--
-- Pets included (the builders are copied EXACTLY -- same parts/sizes/colors):
--   1. CoconutCrab   -- brown crab: body, 3 coconut "eye" spots, cute eyes,
--                       2 claws, 6 little legs.
--   2. PopcornSheep  -- cream popcorn-wool body, dark face, ears, tuft, snout,
--                       4 legs, tail tuft.
--   3. ButterDuck    -- glossy golden duck: body, rump/tail, neck, head, flat
--                       bill, wings, webbed legs, cute eyes.
--
-- The idle animator (bob / sway / blink / leg gait / wing flap / claw scuttle)
-- is also copied so they look ALIVE exactly like in game. They just stand and
-- idle here (no follow logic) -- swap in your own follow code if you want.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ===== low-poly build helper (VERBATIM from PetFollow.client.lua) =====
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- Animator registry: model -> { parts = {...}, s, t, move, blink, lastPos }. (VERBATIM)
local petAnims = setmetatable({}, { __mode = "k" })

-- ============================================================================
-- PET BUILDERS -- copied EXACTLY from PetFollow.client.lua. +X = front.
-- ============================================================================

-- COCONUT CRAB
local function buildCoconutCrab(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "CoconutCrab"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0, "body")
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0, "body")      -- the 3 coconut "eyes"
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4, "body")
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4, "body")
	for _, ez in ipairs({-0.45, 0.45}) do                                          -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez, "body", true)
		mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez, "body", true)
	end
	for _, cs in ipairs({-1, 1}) do                                                -- two claws
		mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2, "body")
		mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45, "body")
	end
	for _, ls in ipairs({-1, 1}) do                                                -- 6 little legs
		for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95, "leg") end
	end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- POPCORN SHEEP
local function buildPopcornSheep(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "PopcornSheep"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	-- BODY core + a cluster of popcorn-wool bumps all over it
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0, "body")
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},
	                     {0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do
		local r = 0.72 + math.abs(b[2])*0.04
		mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3], "body")
	end
	-- HEAD (small dark face at the front) + a wool tuft + ears
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0, "head")
	mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62, "head")
	for _, ez in ipairs({0.32, -0.32}) do -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez, "head", true)
	end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0, "head")
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do -- 4 little legs
		mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2], "leg")
	end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0, "tail") -- tiny tail tuft
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- BUTTER DUCK
local function buildButterDuck(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "ButterDuck"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0, "body")          -- rounded duck body
	mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0, "tail")    -- upturned tail end
	mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0, "tail")
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0, "head")   -- neck sweeping up
	mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0, "head")     -- round head, up front
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0, "head")      -- flat duck bill
	mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0, "head")
	for _, ez in ipairs({0.42, -0.42}) do -- cute eyes on the head front
		mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez, "head", true)
	end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15, "tail") end -- little side wings (flap with the tail role)
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls, "leg") end  -- two webbed legs
	-- glossy buttery sheen on the solid body parts
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = math.max(e.part.Reflectance, 0.08) end end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- ============================================================================
-- IDLE ANIMATOR -- copied VERBATIM from PetFollow.client.lua (animatePet).
-- Gives every pet bob/sway/blink + per-role motion (leg gait, ear flop, wing
-- flap, claw scuttle). It reads the model's CURRENT root CFrame each frame and
-- writes local offsets onto the sub-parts, so the root stays put while the pet
-- looks alive.
-- ============================================================================
local function pivotRotate(pivot, rot) -- rotate about a local pivot point (not the part's own centre)
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

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
	-- MOVING? measure the root's HORIZONTAL speed and smooth it to 0..1.
	local pos = rootCF.Position
	if A.lastPos then
		local d = pos - A.lastPos
		local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
		local target = math.clamp(sp / (26 * s), 0, 1)
		A.move = A.move + (target - A.move) * math.clamp(dt * 5, 0, 1)
	end
	A.lastPos = pos
	local mv = A.move
	-- GLOBAL: soft breathing bob + gentle sway + forward lean when moving.
	local bobY = math.sin(t * 1.5) * 0.06 * s + math.sin(t * (3.0 + 1.5 * mv)) * 0.09 * s * mv
	local swayY = math.rad(3) * math.sin(t * 0.8)
	local swayZ = math.rad(2) * math.sin(t * 1.1)
	local globalT = CFrame.new(0, bobY, 0) * pivotRotate(Vector3.new(0, 0, 0), CFrame.Angles(0, swayY, -math.rad(13) * mv + swayZ))
	-- HEAD: little bob + idle nod + side glance, pivoted at the neck base.
	local headBob = math.sin(t * 1.7 + 0.5) * 0.05 * s + math.sin(t * (8 + 4 * mv)) * 0.05 * s * mv
	local headRot = CFrame.Angles(0, math.rad(8) * math.sin(t * 0.6), 0) * CFrame.Angles(0, 0, math.rad(5) * math.sin(t * 1.1) - math.rad(7) * mv)
	local headT = CFrame.new(0, headBob, 0) * pivotRotate(Vector3.new(1.2 * s, 0.6 * s, 0), headRot)
	-- TAIL: side-to-side sway, pivoted at the body back.
	local tailRot = pivotRotate(Vector3.new(-1.5 * s, 0, 0), CFrame.Angles(0, math.sin(t * (2.2 + 3 * mv)) * (math.rad(14) + math.rad(16) * mv), 0))
	-- BLINK: quick eye squash every ~2-5s.
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
			-- diagonal gait: front-left + back-right swing together, opposite pair anti-phase.
			local bx, bz = e.base.Position.X, e.base.Position.Z
			local phase = ((bx >= 0) == (bz >= 0)) and 0 or math.pi
			local swing = math.rad(18) * mv * math.sin(t * (9 + 3 * mv) + phase)
			localCF = globalT * pivotRotate(Vector3.new(bx, -0.7 * s, bz), CFrame.Angles(0, 0, swing)) * bp
		elseif e.role == "ear" then
			-- EARS: gentle floppy wiggle, pivoted at the ear base.
			local bzs = e.base.Position.Z >= 0 and 1 or -1
			local flop = math.rad(7) * math.sin(t * 1.6) + math.rad(9) * mv * math.sin(t * (7 + 2 * mv))
			local splay = math.rad(5) * math.sin(t * 1.3 + bzs) * bzs
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y - 1.0 * s, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, 0, flop) * CFrame.Angles(splay, 0, 0)) * bp
		elseif e.role == "wing" then
			-- WINGS (duck): flap up/down, pivoted at the inner edge.
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local flap = (math.rad(10) + math.rad(26) * mv) * math.sin(t * (3 + 9 * mv)) * sgn
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y, e.base.Position.Z - 1.0 * s * sgn)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(flap, 0, 0)) * bp
		elseif e.role == "claw" then
			-- CLAWS (crab): scuttle -- quick small open/close, pivoted at the shoulder.
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

-- ============================================================================
-- DISPLAY: spawn the three pets in a row a few studs in front of the player's
-- spawn and idle-animate them forever. Purely a viewer harness.
-- ============================================================================
local function anchorCF()
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if hrp then return hrp.CFrame * CFrame.new(0, 0, -12) end -- 12 studs in front
	return CFrame.new(0, 5, 0)
end

local base = anchorCF()
local spawned = {}
local builders = { buildCoconutCrab, buildPopcornSheep, buildButterDuck }
for i, build in ipairs(builders) do
	local m = build(1.4) -- a touch bigger so they read well as a showcase
	m:PivotTo(base * CFrame.new((i - 2) * 8, 0, 0) * CFrame.Angles(0, math.rad(180), 0)) -- face the player (+X front -> turn around)
	m.Parent = Workspace
	spawned[#spawned+1] = m
end

RunService.RenderStepped:Connect(function(dt)
	for _, m in ipairs(spawned) do
		if m.Parent then animatePet(m, dt) end
	end
end)

print("[PetLooks] spawned CoconutCrab + PopcornSheep + ButterDuck in front of you")
