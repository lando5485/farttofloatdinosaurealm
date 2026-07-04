--======================================================================
-- Stegosaurus.server.luau  (server Script -- CSG/UnionAsync is server-only)
--======================================================================
-- Builds a STEGOSAURUS pet using the EXACT same construction as
-- buildBroccoliBunny() in PetSystem.server.lua: the same rounded-cube
-- (Minkowski) body union, the same helpers (mkPart, newRoot, fuse, weldTo,
-- eyes, BLK/BAL/CYL), the same scale/proportions (PSW/PSH/PSD/PSR/PSS), the
-- same matte Plastic + Smooth faces, the same feet, and the same cute face
-- (flat-disc eyes via eyes(), nose, cheeks, smiling mouth). ONLY the
-- bunny-specific accessories are swapped for stegosaurus ones:
--   * back plates (a row of rounded leaf plates down the spine), and
--   * a short thick tail nub with a blunt thagomizer (cream-tipped spikes).
-- Builds one in Workspace so you can see it (and publishes a template copy to
-- ReplicatedStorage, like the bunny). Prints the part count.
--======================================================================

local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ===== helpers (copied VERBATIM from PetSystem.server.lua) =====
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
		P("whitepartofeye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)
		P("blackpartofeye", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16)
	end
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
-- shared chunky body dims (IDENTICAL to the bunny) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- ============================================================================
-- STEGOSAURUS -- same rounded-cube body + face + feet as the bunny; bunny
-- accessories (ears/whiskers/florets/white tail) removed; back plates + a
-- thagomizer tail added instead.
-- ============================================================================
local function buildStegosaurus()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "Stegosaurus"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- dino palette: turquoise body, coral plates, cream belly/spikes, darker-teal freckles, dark accents
	local BODY  = Color3.fromRGB(72,190,180)    -- teal / turquoise body
	local BELLY = Color3.fromRGB(214,242,236)   -- pale mint belly + muzzle
	local PLATE = Color3.fromRGB(255,140,90)     -- contrasting coral plates (pop)
	local CREAM = Color3.fromRGB(245,238,214)    -- bone spike tips
	local SPOT  = Color3.fromRGB(48,150,142)     -- darker-teal back freckles
	local DARK  = Color3.fromRGB(34,28,34)       -- eyes / nostrils / mouth

	-- BODY: UNCHANGED rounded-cube union construction (only the colour differs)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BODY)
	local body, err = fuse(m, src, "BodyUnion", BODY)

	-- FEET: 4 stubby feet (front + back pairs)
	P("Foot", BLK, 0.95,0.8,0.95, BODY,  0.95,-1.55, 0.78)
	P("Foot", BLK, 0.95,0.8,0.95, BODY,  0.95,-1.55,-0.78)
	P("Foot", BLK, 0.95,0.8,0.95, BODY, -0.95,-1.55, 0.78)
	P("Foot", BLK, 0.95,0.8,0.95, BODY, -0.95,-1.55,-0.78)

	-- BELLY: a pale patch low on the front (below the face)
	weldTo(P("Belly", BAL, 0.45,1.0,1.9, BELLY, 1.45,-1.15,0), body)

	-- FACE: clustered LOW + CENTERED on the front (+X). Big forward eyes CLOSE together (white eyeball +
	-- dark pupil + glint), a small rounded snout w/ tiny nostrils, and a little happy open mouth w/ teeth.
	local WHITE = Color3.fromRGB(250,250,250)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 0.5 * sgn  -- eyes close together
		weldTo(P("whitepartofeye", CYL, 0.20, 0.86, 0.86, WHITE, 1.70, 0.18, zc), body)        -- white eyeball (flat disc, forward)
		weldTo(P("blackpartofeye", CYL, 0.26, 0.52, 0.52, DARK,  1.78, 0.15, zc), body)        -- dark pupil, proud of the white
		weldTo(P("Glint",          CYL, 0.12, 0.20, 0.20, WHITE, 1.92, 0.33, zc + 0.12), body) -- bright glint dot
	end
	weldTo(P("Snout", BAL, 0.5,0.58,0.95, BELLY, 1.78,-0.34,0), body)                          -- small rounded snout (below/between eyes)
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.99,-0.22, 0.16), body)                    -- tiny nostril dots
	weldTo(P("Nostril", BAL, 0.12,0.12,0.12, DARK, 1.99,-0.22,-0.16), body)
	weldTo(P("MouthOpen", BAL, 0.26,0.34,0.66, Color3.fromRGB(70,40,46), 1.80,-0.64,0), body)  -- little happy open mouth
	weldTo(P("Tooth", BAL, 0.1,0.14,0.1, WHITE, 1.96,-0.54, 0.16), body)                       -- small cute teeth
	weldTo(P("Tooth", BAL, 0.1,0.14,0.1, WHITE, 1.96,-0.54,-0.16), body)

	-- BACK PLATES: 6 SEPARATE thin upright leaf plates down the top-center of the back (NOT fused --
	-- distinct flat fins). Each plate is a BLOCK (NOT a ball): broad along X (w = front-back), TALL
	-- (Y = h), and THIN in Z (0.12) so it stands up like a flat plate, not a round lump. Biggest in the
	-- middle, smaller toward head + tail; evenly spaced just behind the head -> base of tail (z=0).
	for _, pd in ipairs({ {0.95,0.85}, {0.45,1.2}, {-0.05,1.5}, {-0.55,1.5}, {-1.05,1.2}, {-1.55,0.85} }) do
		local px, h = pd[1], pd[2]
		local w = 0.5 + h * 0.28  -- leaf width along X (front-back); taller plates = wider
		weldTo(P("Plate", BLK, w, h, 0.12, PLATE, px, 1.55 + h * 0.5, 0), body)  -- X=w, Y=h, Z=0.12 (thin = stands up flat)
	end

	-- BACK FRECKLES: a few darker-teal spots for reptile texture
	for _, sp in ipairs({ {0.7,1.25,0.95}, {-0.4,1.4,-0.9}, {0.1,1.0,1.05}, {-1.0,1.05,0.75}, {0.95,1.1,-0.95} }) do
		weldTo(P("Spot", BAL, 0.34,0.3,0.18, SPOT, sp[1], sp[2], sp[3]), body)
	end

	-- TAIL: a short thick nub off the BACK (-X) tapering to a blunt thagomizer (cream tips)
	weldTo(P("Tail", BAL, 1.1,1.0,1.1,   BODY, -1.7,-0.05,0), body)
	weldTo(P("Tail", BAL, 0.72,0.66,0.72, BODY, -2.4,0.12,0), body)
	weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.85,0.45, 0.22), body)
	weldTo(P("Spike", BAL, 0.42,0.42,0.42, CREAM, -2.85,0.45,-0.22), body)
	weldTo(P("Spike", BAL, 0.40,0.40,0.40, CREAM, -2.98,0.20,0), body)

	return m, err
end

-- ============================================================================
-- BUILD: make one in Workspace (visible), publish a template copy to RS (like
-- the bunny), and print the part count.
-- ============================================================================
task.spawn(function()
	local ok, model, err = pcall(buildStegosaurus)
	if not (ok and model) then
		warn("[Stego] build error: " .. tostring(model or err))
		return
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end

	-- confirm the body union is a chunky FLAT-FACED rounded cube (not a sphere)
	local bu = model:FindFirstChild("BodyUnion")
	if bu then
		print(("[Stego] BodyUnion size = %.2f (Z) x %.2f (Y) x %.2f (X) -- expect ~3.23 x 3.06 x 2.89 like the bunny")
			:format(bu.Size.Z, bu.Size.Y, bu.Size.X))
	else
		warn("[Stego] BodyUnion not found -- CSG union failed; body is the unfused BodyUnionChunk fallback")
	end

	-- CLEAR any stale/duplicate StegosaurusTemplate first so the Hub + world always clone the FRESH build
	local removed = 0
	for _, c in ipairs(RS:GetChildren()) do if c.Name == "StegosaurusTemplate" then c:Destroy(); removed += 1 end end
	-- publish the fresh template (single source of truth for the Hub icon AND the in-game pet)
	local tmpl = model:Clone(); tmpl.Name = "StegosaurusTemplate"; tmpl.Parent = RS
	local plateCount = 0; for _, d in ipairs(tmpl:GetDescendants()) do if d.Name == "Plate" then plateCount += 1 end end
	print(("[Stego] published ReplicatedStorage.StegosaurusTemplate (%d parts), cleared %d stale copy(ies)"):format(n, removed))
	print(("[Stego] back plates rebuilt: %d flat upright plates (template now %d parts)"):format(plateCount, n))

	-- lift the visible Workspace copy to a spot in front of spawn so you can see it
	local target = CFrame.new(0, 12, 0)
	local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if sp then target = sp.CFrame * CFrame.new(0, 6, -10) end
	pcall(function() model:PivotTo(target) end)

	print(("[Stego] Stegosaurus built: %d parts (body union %s). Visible copy in Workspace, template -> ReplicatedStorage.StegosaurusTemplate")
		:format(n, err and ("FAILED-fallback: " .. tostring(err)) or "ok"))
end)

-- ============================================================================
-- HATCH SPAWN: QuestGate (client) fires HatchStegoSpawn with a CFrame when the
-- egg hatches. The SERVER clones the union template into Workspace at that spot
-- and floats it. A server-owned UnionOperation renders for every client in the
-- open world -- so the in-game pet looks identical to the Pet Hub (a client-side
-- clone of a server union only renders reliably inside a ViewportFrame).
-- ============================================================================
local Players  = game:GetService("Players")
local spawnEvt = Instance.new("RemoteEvent"); spawnEvt.Name = "HatchStegoSpawn"; spawnEvt.Parent = RS
local activePets = {}
spawnEvt.OnServerEvent:Connect(function(player, baseCF)
	if typeof(baseCF) ~= "CFrame" then return end
	local tmpl = RS:FindFirstChild("StegosaurusTemplate") or RS:WaitForChild("StegosaurusTemplate", 10)
	if not tmpl then return end
	if activePets[player] then pcall(function() activePets[player]:Destroy() end); activePets[player] = nil end
	-- hover the pet up clear of the (brown) nest + the dino's feet so nothing overlaps it
	local hover = baseCF * CFrame.new(0, 3, 0)
	local pet = tmpl:Clone(); pet.Name = "HatchedStego_" .. player.Name; pet.Parent = Workspace
	pcall(function() pet:PivotTo(hover) end)
	activePets[player] = pet
	do local cnt = 0; for _, d in ipairs(pet:GetDescendants()) do if d:IsA("BasePart") then cnt = cnt + 1 end end
		print(("[Stego] in-game pet for %s -> CLONED StegosaurusTemplate (%d parts) at %s"):format(player.Name, cnt, tostring(hover.Position))) end
	-- rise pop, then a gentle float + slow spin (server-side -> replicates to everyone)
	task.spawn(function()
		local POP, t0 = 0.45, os.clock()
		while os.clock() - t0 < POP and pet.Parent do
			local p = (os.clock() - t0) / POP
			pcall(function() pet:PivotTo(hover * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
			task.wait()
		end
		local t = 0
		while pet.Parent do
			t = t + 0.05
			pcall(function() pet:PivotTo(hover * CFrame.new(0, 1.5 + math.sin(t*2)*0.4, 0) * CFrame.Angles(0, t*0.6, 0)) end)
			task.wait(0.05)
		end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	if activePets[p] then pcall(function() activePets[p]:Destroy() end); activePets[p] = nil end
end)
