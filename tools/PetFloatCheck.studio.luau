--======================================================================
-- PetFloatCheck.studio.luau
--======================================================================
-- Finds FLOATING parts on the dinosaur pets -- in Studio, on the real
-- models, in the real engine. No guessing from screenshots.
--
-- HOW TO RUN
--   1. Press Play (the pet builders publish their templates on start).
--   2. Open  View > Command Bar  and paste:
--        require(game.ServerScriptService.DinosaurRealmServer.Parent
--          :FindFirstChild("PetFloatCheck"))
--      ...or simply paste this whole file into the Command Bar.
--   3. Read the Output window.
--
-- WHAT IT TELLS YOU
--   FLOATING  = that part touches nothing. It hangs in mid-air. Fix it.
--   THIN      = it only just grazes its neighbour, so you will see a seam
--               or a pinched waist where they meet.
--   OK        = properly buried in its neighbour.
--
-- HOW TO FIX WHAT IT REPORTS
--   Every part is one line in src/server/<Pet>.server.luau shaped like
--       P("Name", SHAPE, sizeX,sizeY,sizeZ, COLOUR, posX,posY,posZ)
--   +X is FORWARD (the face), +Y is UP, -X is the tail.
--   To attach a floating part, move its posX/posY/posZ TOWARDS the part it
--   should be sitting in until this script stops reporting it.
--
--   THE RULE: a part looks properly attached when its CENTRE is inside its
--   neighbour -- not merely when the two surfaces touch. Two balls that just
--   kiss still look like two balls.
--======================================================================

local SAMPLES = 220   -- points tested per part. raise for accuracy, lower for speed
local THIN_PCT = 6    -- below this % buried = visible seam

local RS = game:GetService("ReplicatedStorage")

local TEMPLATES = {
	"StegosaurusTemplate", "VelociraptorTemplate", "SharkTemplate",
	"TriceratopsTemplate", "SpinosaurusTemplate", "TyrannosaurusTemplate",
}

-- ===== is a world point inside this part? exact for the shapes the pets use =====
local function inside(part, worldPt)
	local lp = part.CFrame:PointToObjectSpace(worldPt)
	local s = part.Size

	if part:IsA("UnionOperation") or part:IsA("MeshPart") then
		-- we cannot see inside a CSG solid, so treat it as its box.
		-- that is PERMISSIVE: anything this reports as floating really is floating.
		return math.abs(lp.X) <= s.X/2 and math.abs(lp.Y) <= s.Y/2 and math.abs(lp.Z) <= s.Z/2
	end

	if part:IsA("WedgePart") then
		if math.abs(lp.X) > s.X/2 or math.abs(lp.Z) > s.Z/2 or lp.Y < -s.Y/2 then return false end
		return lp.Y <= -(s.Y / s.Z) * lp.Z
	end

	if part:IsA("Part") then
		local sh = part.Shape
		if sh == Enum.PartType.Ball then
			local x, y, z = lp.X/(s.X/2), lp.Y/(s.Y/2), lp.Z/(s.Z/2)
			return x*x + y*y + z*z <= 1
		elseif sh == Enum.PartType.Cylinder then
			-- Roblox cylinders run along their LOCAL X axis
			if math.abs(lp.X) > s.X/2 then return false end
			local y, z = lp.Y/(s.Y/2), lp.Z/(s.Z/2)
			return y*y + z*z <= 1
		end
	end
	-- Block (and anything else): box
	return math.abs(lp.X) <= s.X/2 and math.abs(lp.Y) <= s.Y/2 and math.abs(lp.Z) <= s.Z/2
end

-- ===== random point inside a part =====
local function samplePoint(part)
	local s = part.Size
	local lp
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		local v = Vector3.new(math.random()*2-1, math.random()*2-1, math.random()*2-1)
		while v.Magnitude > 1 or v.Magnitude < 1e-6 do
			v = Vector3.new(math.random()*2-1, math.random()*2-1, math.random()*2-1)
		end
		lp = Vector3.new(v.X*s.X/2, v.Y*s.Y/2, v.Z*s.Z/2)
	elseif part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		local a, r = math.random()*math.pi*2, math.sqrt(math.random())
		lp = Vector3.new((math.random()-0.5)*s.X, math.cos(a)*r*s.Y/2, math.sin(a)*r*s.Z/2)
	else
		lp = Vector3.new((math.random()-0.5)*s.X, (math.random()-0.5)*s.Y, (math.random()-0.5)*s.Z)
	end
	return part.CFrame:PointToWorldSpace(lp)
end

local function checkModel(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Root" then
			table.insert(parts, d)
		end
	end

	local floating, thin, ok = {}, {}, 0
	for _, p in ipairs(parts) do
		-- cheap reject: only test neighbours whose bounds could possibly reach us
		local near = {}
		for _, q in ipairs(parts) do
			if q ~= p and (q.Position - p.Position).Magnitude
				<= (q.Size.Magnitude + p.Size.Magnitude) / 2 + 0.05 then
				table.insert(near, q)
			end
		end

		local best, who = 0, nil
		for _, q in ipairs(near) do
			local hits = 0
			for _ = 1, SAMPLES do
				if inside(q, samplePoint(p)) then hits += 1 end
			end
			local frac = hits / SAMPLES * 100
			if frac > best then best, who = frac, q.Name end
		end

		if best <= 0 then
			table.insert(floating, p.Name)
		elseif best < THIN_PCT then
			table.insert(thin, ("%s (%.0f%% into %s)"):format(p.Name, best, who or "?"))
		else
			ok += 1
		end
	end

	print(("\n=== %s -- %d parts ==="):format(model.Name, #parts))
	if #floating == 0 and #thin == 0 then
		print(("   all %d parts properly attached"):format(ok))
	end
	for _, n in ipairs(floating) do warn(("   FLOATING  %s  -- touches nothing"):format(n)) end
	for _, n in ipairs(thin) do print(("   THIN      %s"):format(n)) end
	return #floating, #thin
end

local totalF, totalT = 0, 0
for _, name in ipairs(TEMPLATES) do
	local m = RS:FindFirstChild(name)
	if m then
		local f, t = checkModel(m)
		totalF += f; totalT += t
	else
		warn(("[PetFloatCheck] %s not found -- press Play first so it gets published"):format(name))
	end
end
print(("\n[PetFloatCheck] TOTAL: %d floating, %d thin joins"):format(totalF, totalT))
print("[PetFloatCheck] Note: BodyUnion is measured as its bounding box (CSG interiors are")
print("[PetFloatCheck] not readable), so anything reported FLOATING is genuinely floating.")
