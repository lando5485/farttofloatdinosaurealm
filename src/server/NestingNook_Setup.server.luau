--!strict
-- NestingNook_Setup.server.luau
-- Builds the "Nesting Nook" quest data on server start:
--   * locates island1 and its 3 decorative nest "Egg" objects (left untouched)
--   * publishes shared quest state into ReplicatedStorage.NestingNook
--   * spawns 5 small, distinctly-colored "LostEgg" clones at the 5 "EggPlacement"
--     markers found in Workspace (no random scatter)
-- This is a persistent Script (syncs via Rojo) and runs every server start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
-- wait for IslandLayout to space the islands first, so the LostEggs land at the NEW island1 position
do local t0 = os.clock(); while not _G.islandsPositioned and os.clock() - t0 < 5 do task.wait() end end

local TOTAL_EGGS = 5
-- Egg width in studs. Was 1.2 (~a player's head), which made the five LostEggs very hard to
-- spot on island1 -- the FIRST island, the one that teaches the game. Now 5x that.
-- The eggs are BOTTOM-aligned to their EggPlacement markers further down, so growing this
-- makes them taller upward rather than sinking them into the ground. One number, both egg
-- paths (the hand-made clone and the low-poly fallback) read it.
local EGG_FOOTPRINT = 6.0 -- target size in studs
local COLOR_MIN_DISTANCE = 0.28 -- min RGB distance (0..~1.73) from any excluded color

----------------------------------------------------------------------
-- Helpers that work for both BasePart and Model "Egg" objects
----------------------------------------------------------------------

local function isEggObject(inst: Instance): boolean
	return inst.Name == "Egg" and (inst:IsA("BasePart") or inst:IsA("Model"))
end

local function getPivot(obj: Instance): CFrame
	if obj:IsA("BasePart") then
		return obj.CFrame
	elseif obj:IsA("Model") then
		return obj:GetPivot()
	end
	return CFrame.new()
end

local function getSize(obj: Instance): Vector3
	if obj:IsA("BasePart") then
		return obj.Size
	elseif obj:IsA("Model") then
		local _, size = obj:GetBoundingBox()
		return size
	end
	return Vector3.new(2, 2, 2)
end

local function setPivot(obj: Instance, cf: CFrame)
	if obj:IsA("BasePart") then
		obj.CFrame = cf
	elseif obj:IsA("Model") then
		obj:PivotTo(cf)
	end
end

-- Most representative color of an egg: the color of its largest BasePart.
local function getEggColor(obj: Instance): Color3
	if obj:IsA("BasePart") then
		return obj.Color
	elseif obj:IsA("Model") then
		local best: BasePart? = nil
		local bestVol = -1
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bestVol then
					bestVol = v
					best = d
				end
			end
		end
		if best then
			return best.Color
		end
	end
	return Color3.new(1, 1, 1)
end

local function colorDistance(a: Color3, b: Color3): number
	local dr = a.R - b.R
	local dg = a.G - b.G
	local db = a.B - b.B
	return math.sqrt(dr * dr + dg * dg + db * db)
end

local function anchorAll(obj: Instance)
	if obj:IsA("BasePart") then
		obj.Anchored = true
	else
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end
end

local function paintAll(obj: Instance, color: Color3)
	if obj:IsA("BasePart") then
		obj.Color = color
	else
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = color
			end
		end
	end
end

----------------------------------------------------------------------
-- THE EGG SHAPE
----------------------------------------------------------------------
-- The LostEggs used to be clones of a nest egg run through resizeEgg(), which sets a
-- BasePart to EGG_FOOTPRINT on ALL THREE AXES -- a perfect cube, or a perfect sphere if
-- the source happened to be a Ball. Neither is an egg, and five of them are the first
-- thing a new player is asked to go and find.
--
-- Built here instead as a stack of slabs whose radius follows a real egg profile. TWO
-- things make it read as an egg rather than a pill:
--   * the profile is a circle SKEWED along its axis, so the widest point sits below the
--     middle and the top narrows more sharply than the base rounds off. An unskewed
--     profile is an ellipsoid, which reads as a capsule or a rugby ball.
--   * the aspect is ~1.35 tall to wide, which is where real bird eggs sit.
--
-- LOW POLY is kept deliberately: only EGG_LAYERS slabs, so the steps between them stay
-- visible as facets down the silhouette. Raising the count smooths it toward a plain
-- ellipsoid and loses the look; this is a tuning knob, not a quality setting.
--
-- Cylinders rather than blocks: a block stack has a square cross-section and reads as a
-- ziggurat from above, and rotating alternate layers 45 degrees to hide that just makes
-- the corners jut past the silhouette on every other layer.
-- 12, up from 8. Still unmistakably faceted -- the stepped silhouette is the look and is
-- kept on purpose -- but 8 slabs over an aspect of 1.35 made steps thick enough to read as
-- a stack of coins from the side rather than a curve.
local EGG_LAYERS  = 12
local EGG_ASPECT  = 1.35 -- height / width
local EGG_SKEW    = 0.28 -- 0 = ellipsoid; higher = fatter base, pointier top
local EGG_SPECKLES = 10  -- darker spots half-sunk into the shell; see the loop below

local function buildLowPolyEgg(footprint: number, color: Color3): Model
	local model = Instance.new("Model")
	local height    = footprint * EGG_ASPECT
	local maxRadius = footprint * 0.5
	local layerH    = height / EGG_LAYERS

	-- An invisible, UNROTATED core at the egg's centre, and the model's PrimaryPart. It
	-- does two jobs, and the first is not optional: a model's pivot comes from its
	-- PrimaryPart, every shell slab below is turned on its end, and PivotTo-ing a plain
	-- upright CFrame onto one of those would rotate the whole egg onto its side. It is
	-- also what the "Rock Egg Free" prompt hangs off, which puts the prompt at the middle
	-- of the egg instead of down at its base.
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.1, 0.1, 0.1)
	core.CFrame = CFrame.new(0, 0, 0)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Parent = model
	model.PrimaryPart = core

	-- FORM SHADING. Every slab used to take the flat `color`, so the egg was one solid
	-- silhouette with no read of roundness -- the layer steps were the only thing telling
	-- you it was 3D at all, and from any distance it flattened into a coloured blob.
	-- Darkening the base and lifting the crown fakes the light every real egg has on it,
	-- and costs nothing: same part count, same material.
	local function shade(c: Color3, u: number): Color3
		local k = 0.86 + 0.20 * ((u + 1) * 0.5) -- 0.86 at the base -> 1.06 at the tip
		return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
	end

	local radii = {} -- kept so the speckles below can sit exactly on the shell
	for i = 1, EGG_LAYERS do
		local t = (i - 0.5) / EGG_LAYERS -- centre of this slab, 0 at the base
		local u = t * 2 - 1              -- -1 at the base .. +1 at the tip
		local r = maxRadius * math.sqrt(math.max(0, 1 - u * u)) * (1 - EGG_SKEW * u)
		r = math.max(r, maxRadius * 0.12) -- the tip stays a facet rather than a zero-size part
		radii[i] = r

		local slab = Instance.new("Part")
		slab.Name = "Shell" .. i
		slab.Shape = Enum.PartType.Cylinder
		-- a Cylinder's length runs along X, so the part is turned onto its end and sized
		-- length-first: X is the slab's thickness, Y/Z its diameter
		slab.Size = Vector3.new(layerH, r * 2, r * 2)
		slab.CFrame = CFrame.new(0, (i - 0.5) * layerH - height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		slab.Anchored = true
		slab.CanCollide = false
		slab.CanQuery = true
		slab.Material = Enum.Material.SmoothPlastic
		slab.Color = shade(color, u)
		slab.TopSurface = Enum.SurfaceType.Smooth
		slab.BottomSurface = Enum.SurfaceType.Smooth
		slab.Parent = model
	end

	-- SPECKLES -- the thing that actually makes it read as an EGG rather than a smooth
	-- capsule, and the cheapest possible way to get there: small darker balls sunk halfway
	-- into the shell. Half-sunk is the whole trick, since a ball sitting fully proud looks
	-- like a bolt stuck on the side.
	--
	-- Skipped near the very top and bottom (the 0.15..0.85 band) because a speckle on the
	-- pointed tip has almost no radius to sit on and pokes out past the silhouette.
	--
	-- CanQuery = false on every one: the shell slabs are what the "Rock Egg Free" prompt and
	-- any raycast should hit, and a scatter of tiny query-able balls in front of them is a
	-- good way to make a prompt intermittently refuse to register.
	local speckleColor = Color3.new(color.R * 0.62, color.G * 0.62, color.B * 0.62)
	for s = 1, EGG_SPECKLES do
		local band = 0.15 + (s / (EGG_SPECKLES + 1)) * 0.70 -- spread up the egg, poles excluded
		local layer = math.clamp(math.floor(band * EGG_LAYERS) + 1, 1, EGG_LAYERS)
		local r = radii[layer]
		local ang = (s * 2.399) + math.random() * 0.8 -- golden-angle stride, so they never band up
		local y = (layer - 0.5) * layerH - height * 0.5 + (math.random() - 0.5) * layerH * 0.6
		local d = footprint * (0.07 + math.random() * 0.05)

		local spot = Instance.new("Part")
		spot.Name = "Speckle" .. s
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.new(d, d, d)
		-- r (not r + d/2) puts the ball's CENTRE on the shell surface, so half of it is inside
		spot.CFrame = CFrame.new(math.cos(ang) * r, y, math.sin(ang) * r)
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.Material = Enum.Material.SmoothPlastic
		spot.Color = speckleColor
		spot.Parent = model
	end

	return model
end

----------------------------------------------------------------------
-- CLONE THE HAND-MADE "Egg" INSTEAD -- preferred over buildLowPolyEgg above.
----------------------------------------------------------------------
-- island1 carries its own "Egg" object, so the Lost Eggs may as well BE that egg
-- rather than a code-built lookalike sitting next to it.
--
-- WHY THIS WAS NOT DONE BEFORE, AND WHAT CHANGED: cloning was tried and abandoned --
-- see the note on buildLowPolyEgg -- because the old resize set the clone to
-- EGG_FOOTPRINT on ALL THREE AXES, which turns any egg into a cube (or a sphere, if
-- the source was a Ball). The objection was never the cloning, it was the resize.
-- Model:ScaleTo takes ONE factor and scales everything proportionally, so the egg
-- shrinks to nest-egg size while staying egg-shaped. That is the whole difference.
--
-- Scaled off WIDTH, not height: EGG_FOOTPRINT is the target footprint (~a player's
-- head), and an egg is taller than it is wide -- solving for height would leave it
-- noticeably too small next to the marker.
local function buildEggFromTemplate(template: Instance, footprint: number): Instance?
	local ok, clone = pcall(function() return template:Clone() end)
	if not ok or not clone then return nil end

	local size = getSize(template)
	local width = math.max(size.X, size.Z)
	local factor = (width > 0.01) and (footprint / width) or 1

	if clone:IsA("Model") then
		pcall(function() (clone :: Model):ScaleTo(factor) end)
		-- A PrimaryPart is what attachEggPrompt reaches for first, and a hand-made model
		-- usually has none -- without one the prompt falls to FindFirstChildWhichIsA and
		-- can end up on some small detail part off the side of the egg. Largest part is
		-- the body, which is where the prompt belongs.
		if not (clone :: Model).PrimaryPart then
			local best, bestVol = nil, -1
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVol then bestVol = v; best = d end
				end
			end
			if best then (clone :: Model).PrimaryPart = best end
		end
	elseif clone:IsA("BasePart") then
		clone.Size = clone.Size * factor
	else
		clone:Destroy()
		return nil
	end

	-- Never collide: these are picked up by prompt, and a solid egg on the path is
	-- something to trip over. CanQuery stays ON so the prompt's own ray can find it.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false end
	end
	if clone:IsA("BasePart") then clone.CanCollide = false end

	return clone
end

----------------------------------------------------------------------
-- Locate island1 and the 3 nest eggs
----------------------------------------------------------------------

local island = Workspace:FindFirstChild("island1")
if not island or not island:IsA("Model") then
	warn("[NestingNook] Could not find a Model named 'island1' in Workspace. Aborting setup.")
	return
end

local nestEggs: { Instance } = {}
for _, desc in ipairs(island:GetDescendants()) do
	if isEggObject(desc) then
		table.insert(nestEggs, desc)
	end
end

if #nestEggs == 0 then
	warn("[NestingNook] No 'Egg' objects found inside island1. Cannot build the nest. Aborting.")
	return
end
if #nestEggs < 3 then
	warn(("[NestingNook] Expected 3 nest 'Egg' objects but found %d. Continuing with what exists."):format(#nestEggs))
end

-- Nest center = average of the existing eggs' positions. These eggs are NEVER moved.
local sum = Vector3.zero
for _, egg in ipairs(nestEggs) do
	sum += getPivot(egg).Position
end
local nestCenter = sum / #nestEggs

-- Build the color exclusion list from the 3 decorative nest eggs.
local excludedColors: { Color3 } = {}
for _, egg in ipairs(nestEggs) do
	table.insert(excludedColors, getEggColor(egg))
end

----------------------------------------------------------------------
-- Clean up LostEggs from a previous run (NEVER touch the 3 nest eggs)
----------------------------------------------------------------------

local nestEggSet: { [Instance]: boolean } = {}
for _, egg in ipairs(nestEggs) do
	nestEggSet[egg] = true
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	if inst.Name == "LostEgg" and not nestEggSet[inst] then
		inst:Destroy()
	end
end

----------------------------------------------------------------------
-- Shared quest state in ReplicatedStorage
----------------------------------------------------------------------

local existing = ReplicatedStorage:FindFirstChild("NestingNook")
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "NestingNook"

local totalEggs = Instance.new("IntValue")
totalEggs.Name = "TotalEggs"
totalEggs.Value = TOTAL_EGGS
totalEggs.Parent = folder

local eggsReturned = Instance.new("IntValue")
eggsReturned.Name = "EggsReturned"
eggsReturned.Value = 0
eggsReturned.Parent = folder

folder:SetAttribute("NestX", nestCenter.X)
folder:SetAttribute("NestY", nestCenter.Y)
folder:SetAttribute("NestZ", nestCenter.Z)
folder:SetAttribute("Ready", false)
folder.Parent = ReplicatedStorage

----------------------------------------------------------------------
-- Choose 5 distinct bright colors, none close to the nest-egg colors
----------------------------------------------------------------------

-- Candidate palette of clearly-different bright hues.
local palette: { Color3 } = {
	Color3.fromRGB(230, 45, 45),   -- red
	Color3.fromRGB(255, 140, 25),  -- orange
	Color3.fromRGB(160, 70, 220),  -- purple
	Color3.fromRGB(30, 190, 180),  -- teal
	Color3.fromRGB(255, 95, 180),  -- pink
	Color3.fromRGB(255, 220, 40),  -- yellow
	Color3.fromRGB(60, 130, 255),  -- blue
	Color3.fromRGB(120, 230, 70),  -- lime
}

local function pickColors(count: number): { Color3 }
	local chosen: { Color3 } = {}
	-- Progressively relax the distance threshold so we always end up with `count`.
	local thresholds = { COLOR_MIN_DISTANCE, 0.2, 0.12, 0 }
	for _, threshold in ipairs(thresholds) do
		for _, cand in ipairs(palette) do
			if #chosen >= count then
				break
			end
			local ok = true
			for _, ex in ipairs(excludedColors) do
				if colorDistance(cand, ex) < threshold then
					ok = false
					break
				end
			end
			if ok then
				for _, c in ipairs(chosen) do
					if colorDistance(cand, c) < 0.001 then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(chosen, cand)
			end
		end
		if #chosen >= count then
			break
		end
	end
	return chosen
end

local eggColors = pickColors(TOTAL_EGGS)

----------------------------------------------------------------------
-- Spawn one LostEgg at each EggPlacement marker
----------------------------------------------------------------------

-- Markers are BaseParts nested anywhere under ISLAND1, matched by name (contains both
-- "egg" and "plac") so EggPlacement / egg placement / Egg_Placement3 all count.
--
-- SEARCH SCOPE IS island1, NOT THE WHOLE WORKSPACE -- and that is a fix, not a tidy-up.
-- This used to walk Workspace:GetDescendants(), so the loose name match swept up EVERY
-- island's egg marker. An "egg placement" part added to island2 for the TRICERATOPS egg
-- was picked up here and given a sixth Nesting Nook LostEgg -- an island1 collectible,
-- with an island1 pickup prompt, sitting on island2. The count warning even said so
-- ("Expected 5 ... but found 6") and was ignored as noise.
--
-- This script is the NESTING NOOK setup. island1's markers are the only ones it owns;
-- every other island's egg is placed by that island's own quest script.
local placements: { BasePart } = {}
for _, desc in ipairs(island:GetDescendants()) do
	if desc:IsA("BasePart") then
		local n = string.lower(desc.Name)
		if string.find(n, "egg", 1, true) and string.find(n, "plac", 1, true) then
			table.insert(placements, desc)
		end
	end
end

print(("[NestingNook] Found %d EggPlacement marker(s):"):format(#placements))
for _, marker in ipairs(placements) do
	print("    " .. marker:GetFullName())
end

if #placements == 0 then
	warn("[NestingNook] No 'EggPlacement' markers found in Workspace. No LostEggs spawned.")
elseif #placements ~= TOTAL_EGGS then
	warn(("[NestingNook] Expected %d 'EggPlacement' markers but found %d. Spawning one egg per marker.")
		:format(TOTAL_EGGS, #placements))
end

local lostEggs: { Instance } = {}

-- THE TEMPLATE: island1's own hand-made "Egg". Every Lost Egg is a copy of it, and the
-- code-built low-poly egg is only the fallback for when the island has none.
local eggTemplate: Instance? = nil
do
	local src = nestEggs[1]
	if src then
		-- PRISTINE COPY TAKEN FIRST, AND THE ORDER IS LOAD-BEARING. Hiding the original
		-- writes Transparency = 1 onto its parts, and every Lost Egg is cloned FROM it --
		-- so hiding before cloning would produce five perfectly placed invisible eggs with
		-- working prompts and nothing to see. Copy, then hide the source.
		local ok, copy = pcall(function() return src:Clone() end)
		if ok and copy then
			eggTemplate = copy -- left unparented; it exists only to be cloned from
			print(("[NestingNook] egg template = %s (%s) -- Lost Eggs are copies of it")
				:format(src:GetFullName(), src.ClassName))
		end

		-- HIDE THE ORIGINAL. It is a mould now, and leaving it visible puts an extra egg on
		-- the island that no prompt is attached to and no quest counts -- exactly the
		-- "leftover mystery egg" problem island2 already had. Collision and queries go off
		-- with it, so an invisible egg cannot become one of the invisible walls either.
		for _, d in ipairs(src:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false; d.CanQuery = false end
		end
		if src:IsA("BasePart") then
			src.Transparency = 1; src.CanCollide = false; src.CanQuery = false
		end
	end
end
if not eggTemplate then
	warn("[NestingNook] no 'Egg' object on island1 to copy -> Lost Eggs fall back to the built low-poly egg")
end

for i, placement in ipairs(placements) do
	-- Distinct color (cycle through the chosen palette if we have more markers than colors).
	local color = eggColors[((i - 1) % #eggColors) + 1] or Color3.fromRGB(230, 45, 45)

	-- A COPY OF island1's OWN EGG when there is one; the built egg is the fallback.
	-- NOTE the copies are deliberately NOT repainted: the point of using the hand-made
	-- egg is its own look, and paintAll would flatten it to one of the palette colours
	-- and throw that away. The built fallback still gets painted, since a stack of
	-- identical grey slabs needs the colour to tell five eggs apart.
	local egg = eggTemplate and buildEggFromTemplate(eggTemplate, EGG_FOOTPRINT) or nil
	if egg then
		egg.Name = "LostEgg"
		anchorAll(egg)
	else
		egg = buildLowPolyEgg(EGG_FOOTPRINT, color)
		egg.Name = "LostEgg"
		anchorAll(egg)
		paintAll(egg, color)
	end

	-- Sit the egg on the same surface as the marker by aligning their BOTTOMS.
	-- The marker is already at the correct height; the egg is smaller, so match
	-- the bottom contact rather than the center. Keep X/Z exact.
	egg.Parent = Workspace
	local markerCenter = placement.Position
	local eggSizeY = getSize(egg).Y
	local eggY = markerCenter.Y - (placement.Size.Y / 2) + (eggSizeY / 2)
	local target = Vector3.new(markerCenter.X, eggY, markerCenter.Z)
	setPivot(egg, CFrame.new(target))

	egg:SetAttribute("HomeX", target.X)
	egg:SetAttribute("HomeY", target.Y)
	egg:SetAttribute("HomeZ", target.Z)
	egg:SetAttribute("Collected", false)

	-- Hide the placement marker so only the egg shows.
	placement.Transparency = 1
	placement.CanCollide = false

	table.insert(lostEggs, egg)
end

-- Keep the quest count in sync with how many eggs actually spawned.
if #lostEggs > 0 then
	totalEggs.Value = #lostEggs
end

folder:SetAttribute("Ready", true)

print(("[NestingNook] Setup complete: nest center (%.1f, %.1f, %.1f), %d LostEggs placed at EggPlacement markers.")
	:format(nestCenter.X, nestCenter.Y, nestCenter.Z, #lostEggs))
