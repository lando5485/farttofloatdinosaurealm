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
local EGG_FOOTPRINT = 1.2 -- target size in studs (~a player's head)
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

-- Resize to roughly a EGG_FOOTPRINT cube. Parts get their Size set directly;
-- Models are uniformly scaled down so their largest dimension fits the footprint.
local function resizeEgg(obj: Instance)
	if obj:IsA("BasePart") then
		obj.Size = Vector3.new(EGG_FOOTPRINT, EGG_FOOTPRINT, EGG_FOOTPRINT)
	elseif obj:IsA("Model") then
		local size = getSize(obj)
		local maxDim = math.max(size.X, size.Y, size.Z)
		if maxDim > 0 then
			local factor = EGG_FOOTPRINT / maxDim
			obj:ScaleTo(obj:GetScale() * factor)
		end
	end
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

-- Markers are BaseParts nested anywhere under Workspace (e.g. inside island1),
-- so search ALL descendants and match by name (contains both "egg" and "plac").
local placements: { BasePart } = {}
for _, desc in ipairs(Workspace:GetDescendants()) do
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

local sourceEgg = nestEggs[1]
local lostEggs: { Instance } = {}

for i, placement in ipairs(placements) do
	local egg = sourceEgg:Clone()
	egg.Name = "LostEgg"

	anchorAll(egg)
	resizeEgg(egg)

	-- Distinct color (cycle through the chosen palette if we have more markers than colors).
	local color = eggColors[((i - 1) % #eggColors) + 1] or Color3.fromRGB(230, 45, 45)
	paintAll(egg, color)

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
