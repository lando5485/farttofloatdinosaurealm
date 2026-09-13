--======================================================================
-- FoodStands.server.luau  (server Script)
--======================================================================
-- Guarantees EVERY island has a food stand.
--
-- The shop UI opens by proximity to any part named Shop/Stand (see
-- ShopGlue.client.luau), and it sells the food belonging to the island that
-- stand sits on. Islands without one simply had no way to buy food -- the
-- coverage report listed 2,3,4,6,7,10,11,12,13 as missing, so nine of the
-- thirteen islands were unshoppable.
--
-- This script waits for the tower to be positioned, then builds a stand on any
-- island that hasn't got one. Islands that already have a hand-placed stand
-- MODEL are left completely alone.
--
-- CHOOSING THE SPOT BY HAND: drop a single PLAIN part named "Stand" (or "StandSpot" /
-- "ShopSpot") on the island where the stand should go -- the full stand is built on that
-- part's top surface and the marker is ghosted.
--
-- WHAT COUNTS AS "ALREADY HAS ONE": a Model, a MeshPart, a Union, or any part carrying a
-- mesh/decal/texture. Only a bare, undressed Part is read as a marker. If something of
-- yours still gets built over, set the attribute HandBuilt = true on it and this script
-- will never touch it. See isMarkerPart below.
--
-- NAMING: the stand is named "Stand<MODEL NUMBER>" and parented to island<N>, so
-- ShopGlue resolves its island from either the name suffix or the parent model.
-- That model number is NOT the climb position -- island9 is the second island you
-- reach -- but the stand belongs to the MODEL it sits on, and the food table is
-- keyed by model number too, so they line up.
--======================================================================
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")

-- VERBOSE: per-item boot spam (one line per part/island/pet/serving). OFF by default --
-- it buried the progression telemetry in hundreds of lines. Flip to true to debug THIS
-- system specifically; every file that had a noisy loop uses the same flag name.
local VERBOSE = false


local IslandOrder = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local FoodMenu    = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("FoodMenu"))
local TOP_ISLAND  = IslandOrder.COUNT

-- island MODEL number -> the food that island sells.
--
-- DERIVED FROM FoodMenu, NOT TYPED OUT AGAIN. This was a hand-written copy of the same
-- pairing, and it did exactly what every other duplicated table in this project did: it
-- drifted. When island5 (Misty Mire) and island2 (Fern Frontier) swapped tower slots,
-- FoodMenu's `island` fields swapped with them and this copy did not -- so the stand on
-- Misty Mire was captioned "Lettuce" while the shop next to it sold Ribs, and vice versa.
-- Only the SIGN was wrong (the purchase itself is validated server-side against FoodMenu),
-- which is the worst kind of wrong: nothing errors, the label just lies.
--
-- Reading the pairing off FoodMenu means an island move can never desync the sign again.
local FOOD_BY_ISLAND = {}
for _, food in ipairs(FoodMenu.LIST) do
	FOOD_BY_ISLAND[food.island] = food.name
end
local WOOD_DARK  = Color3.fromRGB(92, 62, 34)
local WOOD_LIGHT = Color3.fromRGB(148, 104, 58)
local AWNING     = Color3.fromRGB(206, 92, 66)

-- same matcher ShopGlue uses, so we only count stands it will actually wire up
local function isStandName(name)
	local n = string.lower(name)
	return n:match("^shop%d*$") ~= nil or n:match("^stand%d*$") ~= nil
end

local function findStand(island)
	for _, d in ipairs(island:GetDescendants()) do
		if isStandName(d.Name) then
			-- must contain a BasePart, or ShopGlue can't measure distance to it
			if d:IsA("BasePart") or d:FindFirstChildWhichIsA("BasePart", true) then return d end
		end
	end
	return nil
end

-- Is this a placement MARKER (build over it) or somebody's actual STAND (leave it)?
--
-- This used to answer "any BasePart with no BaseParts under it is a marker", which is
-- wrong in the one case that matters most: a stand MODELLED IN STUDIO AND IMPORTED
-- arrives as a single MeshPart or a single Union. It has no child parts, so the old test
-- called it a marker -- and island1's hand-built "Shop" was ghosted, renamed
-- "Shop_Marker" and had a coded stand stacked on its own spot, while the run reported
-- "0 already had one".
--
-- A marker is now specifically a PLAIN, UNDRESSED Part:
--   * ClassName exactly "Part" -- a MeshPart or a UnionOperation IS the model. Nobody
--     builds a marker by importing a mesh.
--   * nothing rendered hanging off it -- a SpecialMesh, Decal, Texture or SurfaceGui
--     means the part is scenery, not a spot.
--   * no BaseParts under it -- a multi-part stand was always safe, and still is.
-- Anything failing those is treated as a finished stand and left completely alone.
local function isMarkerPart(inst)
	if not inst:IsA("BasePart") then return false end
	-- explicit override, for anything this heuristic still guesses wrong about
	if inst:GetAttribute("HandBuilt") then return false end

	-- INVISIBLE IS A MARKER, WHATEVER ITS CLASS -- and this is why stands were "missing".
	--
	-- The class test below only ever allowed a plain Part to be read as a marker, so a
	-- MeshPart or Union named "Stand" was ALWAYS treated as a finished hand-built stand and
	-- left alone -- even when it was fully transparent and therefore showing the player
	-- nothing whatsoever. The island then had no visible stand while this script cheerfully
	-- logged "kept the hand-built stand", which is exactly the symptom: a placement blank
	-- being mistaken for the thing it was only ever meant to mark the spot for.
	--
	-- A stand you cannot see is not a stand. Treat it as the marker it plainly is, and let
	-- the builder below put a real one on top of it.
	if inst.Transparency >= 0.95 then return true end

	if inst.ClassName ~= "Part" then return false end                      -- MeshPart / Union
	if inst:FindFirstChildWhichIsA("BasePart", true) then return false end -- multi-part stand
	for _, ch in ipairs(inst:GetChildren()) do
		-- DataModelMesh is the base of SpecialMesh / BlockMesh / CylinderMesh / FileMesh,
		-- so one test covers every way a plain Part can be given a shape
		if ch:IsA("DataModelMesh") or ch:IsA("Decal") or ch:IsA("Texture")
			or ch:IsA("SurfaceGui") or ch:IsA("BillboardGui") then
			return false
		end
	end
	return true
end

-- explicit marker spelling too ("StandSpot" / "ShopSpot"), for a marker that
-- should never be mistaken for a finished stand
local function findSpotMarker(island)
	for _, d in ipairs(island:GetDescendants()) do
		local n = string.lower(d.Name)
		if d:IsA("BasePart") and (n:match("^standspot%d*$") or n:match("^shopspot%d*$")) then return d end
	end
	return nil
end

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.WoodPlanks
	p.Anchored = true          -- static scenery: anchor now, never let it fall
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Find a walkable spot on this island: drop a ray onto the island's own geometry.
-- Prefers a few studs beside the spawn pad so the stand is somewhere the player
-- actually arrives, and falls back to the island's centre.
local function findSpot(island)
	local ok, cf, size = pcall(function() return island:GetBoundingBox() end)
	if not ok or not cf then return nil end

	local originX, originZ = cf.Position.X, cf.Position.Z
	local spawn = island:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		originX, originZ = spawn.Position.X + 14, spawn.Position.Z + 6
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { island }

	local top = cf.Position.Y + size.Y * 0.5 + 10
	-- try the preferred spot, then walk outward in a ring if it misses (the centre
	-- of an island can be a hole, an arch, or open air)
	local tries = {
		Vector3.new(originX, top, originZ),
		Vector3.new(originX + 18, top, originZ),
		Vector3.new(originX - 18, top, originZ),
		Vector3.new(originX, top, originZ + 18),
		Vector3.new(originX, top, originZ - 18),
		Vector3.new(cf.Position.X, top, cf.Position.Z),
	}
	for _, from in ipairs(tries) do
		local hit = Workspace:Raycast(from, Vector3.new(0, -(size.Y + 60), 0), params)
		if hit then return hit.Position end
	end
	return nil
end

--======================================================================
-- CLONE ISLAND 1's STAND -- "island1 is working, copy how that works".
--======================================================================
-- island1's stand is a hand-made prop that already looks right and already opens the shop,
-- so the surest way to make a bare island match it is to put THE SAME OBJECT there rather
-- than a second, code-built approximation that only resembles it. Every island then shares
-- one look, and improving island1's prop in Studio improves all of them.
--
-- The code-built stand below is kept as the FALLBACK for the case where island1's stand
-- cannot be found (renamed, deleted, or not streamed yet) -- an island with a plain wooden
-- stand still sells food, an island with nothing does not.
--
-- WHAT THE CLONE STILL NEEDS DOING TO IT:
--   * ANCHORED. The source prop may be anchored only because it was never moved; a clone
--     dropped onto a new island unanchored falls straight through the world.
--   * SEATED ON THE SURFACE. Positioned by its own BOTTOM, not its centre, or half of it
--     sinks into the island.
--   * CAPTIONED. island1's prop carries no food label of its own, and every island sells
--     something different. A BillboardGui is used rather than the SurfaceGui the built
--     stand uses, because the face of an arbitrary imported mesh is not knowable -- a
--     billboard reads from every angle.
local function cloneStandFrom(template, island, islandNum, spot)
	if not (template and island and spot) then return false end

	local ok, clone = pcall(function() return template:Clone() end)
	if not ok or not clone then return false end
	clone.Name = "Stand" .. islandNum -- ShopGlue resolves the island from the suffix or the parent

	-- anchor every part before it is parented in, so it can never fall
	if clone:IsA("BasePart") then clone.Anchored = true end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	clone.Parent = island

	-- seat it on the spot by its bottom face
	local pivotCF, size
	if clone:IsA("Model") then
		local bcf, bsz = clone:GetBoundingBox()
		pivotCF, size = bcf, bsz
	elseif clone:IsA("BasePart") then
		pivotCF, size = clone.CFrame, clone.Size
	else
		clone:Destroy(); return false
	end
	local target = CFrame.new(spot + Vector3.new(0, size.Y * 0.5, 0)) * pivotCF.Rotation
	pcall(function()
		if clone:IsA("Model") then clone:PivotTo(target) else clone.CFrame = target end
	end)

	-- NO FLOATING FOOD CAPTION. A BillboardGui naming the island's food used to hang over
	-- the clone -- so Volcanic Vista carried the word "Steak" in mid-air, reading as a stray
	-- object rather than as signage. Removed by request.
	--
	-- Nothing is lost that the player needs: the shop panel opens on approach (ShopGlue,
	-- within 7.5 studs) and names the food itself, so the caption was duplicating a label
	-- the player is about to read anyway. The code-built stand keeps ITS sign, because that
	-- one is a SurfaceGui painted on the stand's own board rather than text floating in air.
	return true
end

local function buildStand(island, islandNum, markerPos)
	local spot = markerPos or findSpot(island)
	if not spot then
		warn(("[FoodStands] island%d: no surface found, stand not placed"):format(islandNum))
		return false
	end

	local model = Instance.new("Model")
	model.Name = "Stand" .. islandNum

	local base = spot + Vector3.new(0, 0.5, 0)
	-- counter the player walks up to
	local counter = part(model, "Counter", Vector3.new(9, 1, 3.5),
		CFrame.new(base + Vector3.new(0, 2.6, 0)), WOOD_LIGHT)
	part(model, "Front", Vector3.new(9, 3, 0.6),
		CFrame.new(base + Vector3.new(0, 1.1, 1.6)), WOOD_DARK)
	-- posts
	part(model, "PostL", Vector3.new(0.6, 6, 0.6), CFrame.new(base + Vector3.new(-4.2, 3, -1.4)), WOOD_DARK)
	part(model, "PostR", Vector3.new(0.6, 6, 0.6), CFrame.new(base + Vector3.new( 4.2, 3, -1.4)), WOOD_DARK)
	-- awning
	local awn = part(model, "Awning", Vector3.new(10, 0.5, 5),
		CFrame.new(base + Vector3.new(0, 6.2, 0)) * CFrame.Angles(math.rad(-12), 0, 0), AWNING)
	awn.Material = Enum.Material.Fabric

	-- sign naming the food this stand sells
	local sign = part(model, "Sign", Vector3.new(7.5, 1.8, 0.3),
		CFrame.new(base + Vector3.new(0, 5.1, 1.7)), WOOD_DARK)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 100)
	gui.AlwaysOnTop = false
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 244, 214)
	label.Text = FOOD_BY_ISLAND[islandNum] or "FOOD"
	label.Parent = gui

	model.PrimaryPart = counter
	model.Parent = island
	return true
end

--======================================================================
-- run after the tower is positioned, and after the NPC/spawn scripts have
-- had a moment to place their pads (we prefer to sit beside one)
--======================================================================
task.spawn(function()
	local waited = 0
	while not _G.islandsPositioned and waited < 60 do task.wait(0.25); waited += 0.25 end
	task.wait(6)   -- let NestingNook_NPCs finish placing spawn pads

	-- THE TEMPLATE: island1's working stand, cloned onto any island that needs one.
	-- Resolved once, and only if it is a REAL stand -- if island1's own stand is missing or
	-- is itself just a marker there is nothing worth copying, and every island falls back to
	-- the code-built stand exactly as before.
	local TEMPLATE_ISLAND = 1
	local templateStand do
		local isl1 = Workspace:FindFirstChild("island" .. TEMPLATE_ISLAND)
		local cand = isl1 and findStand(isl1)
		if cand and not isMarkerPart(cand) then
			templateStand = cand
			print(("[FoodStands] template = island%d's '%s' (%s) -- bare islands get a copy of it")
				:format(TEMPLATE_ISLAND, cand.Name, cand.ClassName))
		else
			warn("[FoodStands] island1 has no usable stand to copy -> falling back to the code-built stand")
		end
	end

	local built, cloned, already, failed = 0, 0, 0, 0
	for n = 1, TOP_ISLAND do
		local island = Workspace:FindFirstChild("island" .. n)
		local existing = island and findStand(island)
		if not island then
			warn(("[FoodStands] island%d not found"):format(n))
		elseif existing and not isMarkerPart(existing) then
			-- a real hand-built stand: leave it completely alone, and SAY SO. This branch
			-- used to be a silent counter, so the only clue that a stand had been replaced
			-- was a total that did not match what was on the island.
			already += 1
			if VERBOSE then print(("[FoodStands] island%d -> kept the hand-built stand '%s' (%s); nothing built")
				:format(n, existing.Name, existing.ClassName)) end
		else
			-- no stand, OR only a placement marker. An explicit StandSpot beats a loose
			-- Stand-named part if both exist.
			local marker = (island and findSpotMarker(island)) or (existing and isMarkerPart(existing) and existing) or nil
			local markerPos = nil
			if marker then
				-- build on the marker's TOP surface, then ghost + rename it so the strict
				-- Shop/Stand matcher (here and in ShopGlue) never counts the bare part again
				markerPos = marker.Position + Vector3.new(0, marker.Size.Y / 2, 0)
				marker.Transparency = 1; marker.CanCollide = false; marker.CanQuery = false
				marker.Name = marker.Name .. "_Marker"
			end
			-- PREFER A COPY OF ISLAND 1's STAND; fall back to the code-built one.
			local spot = markerPos or findSpot(island)
			local placedByClone = false
			if templateStand and n ~= TEMPLATE_ISLAND and spot then
				placedByClone = cloneStandFrom(templateStand, island, n, spot)
			end

			if placedByClone then
				cloned += 1
				print(("[FoodStands] island%d (climb slot %d) -> COPIED island%d's stand as Stand%d selling %s%s")
					:format(n, IslandOrder.ISLAND_TO_SLOT[n] or 0, TEMPLATE_ISLAND, n, FOOD_BY_ISLAND[n] or "?",
						markerPos and " (on the hand-placed marker)" or ""))
			elseif buildStand(island, n, markerPos) then
				built += 1
				print(("[FoodStands] island%d (climb slot %d) -> built Stand%d selling %s%s")
					:format(n, IslandOrder.ISLAND_TO_SLOT[n] or 0, n, FOOD_BY_ISLAND[n] or "?",
						markerPos and " (on the hand-placed marker)" or ""))
			else
				failed += 1
			end
		end
	end
	print(("[FoodStands] done -- %d copied from island%d, %d code-built, %d already had one, %d failed (of %d islands)")
		:format(cloned, TEMPLATE_ISLAND, built, already, failed, TOP_ISLAND))
end)
