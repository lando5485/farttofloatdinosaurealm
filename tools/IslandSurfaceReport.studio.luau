--======================================================================
-- IslandSurfaceReport.studio.luau
--======================================================================
-- Measures the WALKABLE SURFACE of every island model and reports, per slot:
--   * the registered slot Y (IslandOrder.SLOT_POS -- where the PIVOT goes)
--   * the surface OFFSET (how far the walkable deck sits above the pivot)
--   * the tower SURFACE Y (registered Y + offset -- where players actually stand)
--   * the SURFACE-TO-SURFACE gap to the next island vs the registered gap
--   * a CONFIDENCE % -- how much of the island's footprint sits at that height
--
-- WHY THIS EXISTS. IslandLayout places islands by PIVOT (bounding-box centre),
-- but the spacing/economy is tuned surface-to-surface. Two realms with
-- different-sized island models therefore get DIFFERENT surface spacing from
-- the SAME SLOT_POS numbers. To port this realm's spacing to another realm you
-- need the surface numbers, not the pivot numbers -- this prints both.
--
-- HOW TO RUN
--   1. Open the place in Studio (edit mode is fine -- no need to press Play;
--      measurements are relative to each island's own pivot, so it does not
--      matter whether IslandLayout has moved them into the tower yet).
--   2. View > Command Bar, paste this WHOLE file, press Enter.
--   3. Read the Output window. Copy the whole report.
--
-- WORKS IN ANY REALM: it finds the first ModuleScript named "IslandOrder"
-- anywhere under ReplicatedStorage, so the same file runs unchanged in the
-- first realm. Run it in BOTH places -- you need both realms' offsets to
-- port spacing (see the recipe it prints at the end).
--
-- HOW THE SURFACE IS FOUND (cliffs and built-up landforms handled):
--   A 9x9 grid of rays (81 points across the central 80% of the footprint)
--   is cast straight down onto the island's own geometry. The hits are
--   sorted into 4-stud height bands, and the surface is the band holding
--   the MOST hits -- i.e. the height where most of the island's walkable
--   area actually is. A cliff or hill only covers part of the footprint,
--   so it gets OUTVOTED by the main deck instead of dragging an average.
--   Rays punch through parts you cannot stand on (CanCollide false,
--   near-invisible). The "conf" column shows what fraction of all hits sit
--   in the chosen band: high (60%+) means one obvious flat deck; low means
--   the island is terraced/hilly and you should EYEBALL that one.
--
-- MANUAL OVERRIDE (PREFERRED) -- you decide what "the surface" is:
--   Put a Part named "IslandMarker" (or "island marker" / "SurfaceMarker" --
--   spaces and case do not matter) anywhere INSIDE each island's model, its
--   TOP face resting on the spot players actually stand. The tool then uses
--   that part's TOP as the surface -- no guessing -- and marks the row
--   "marker". With one on every island the grid never runs at all.
--   Marker checklist: parented UNDER the island model (not loose in
--   Workspace), Anchored, and make it invisible + CanCollide off so players
--   never see or trip on it. A thin 4x1x4 plate sitting on the ground works.
--
--   If NO ray connects at all (mesh with CanQuery off) the row falls back to
--   the bounding-box TOP and is marked "bbox!" -- treat that as approximate
--   and give that island a SurfaceMarker.
--======================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GRID = 9          -- rays per axis (9x9 = 81 sample points)
local SPAN = 0.40       -- sample out to +/-40% of the footprint (central 80%)
local BAND = 4          -- height-band size in studs for the area vote

-- Find IslandOrder wherever this realm keeps it (DinosaurRealm.IslandOrder here;
-- other realms use their own folder name).
local orderModule
for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
	if d:IsA("ModuleScript") and d.Name == "IslandOrder" then
		orderModule = d
		break
	end
end
assert(orderModule, "[SurfaceReport] no ModuleScript named 'IslandOrder' under ReplicatedStorage -- is Rojo synced?")
local IslandOrder = require(orderModule)
local SLOT_POS = IslandOrder.SLOT_POS
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND
local COUNT = IslandOrder.COUNT or #SLOT_TO_ISLAND

-- Marker names accepted, compared with spaces/underscores stripped and case ignored:
-- "SurfaceMarker", "IslandMarker", "island marker", "surface_marker", ...
local function isMarkerName(name)
	local n = string.lower(string.gsub(name, "[%s_]", ""))
	return n == "surfacemarker" or n == "islandmarker"
end

local function findMarker(isl)
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") and isMarkerName(d.Name) then return d end
	end
	return nil
end

-- surface Y of one island model, in the island's CURRENT position.
-- returns surfaceY, method ("marker" | "grid" | "bbox"), confidence (0..1 or nil)
local function surfaceYOf(isl)
	-- 1) explicit override wins outright
	local marker = findMarker(isl)
	if marker then
		return marker.Position.Y + marker.Size.Y / 2, "marker", 1
	end

	local okBox, cf, size = pcall(function() return isl:GetBoundingBox() end)
	if not okBox or size.Magnitude < 1 then return nil end
	local topY = cf.Position.Y + size.Y / 2

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { isl }

	-- 2) dense grid: where does most of the island's area actually sit?
	local hits = {}
	for ix = 0, GRID - 1 do
		for iz = 0, GRID - 1 do
			local fx = (ix / (GRID - 1) - 0.5) * 2 * SPAN   -- -SPAN .. +SPAN
			local fz = (iz / (GRID - 1) - 0.5) * 2 * SPAN
			local origin = Vector3.new(
				cf.Position.X + fx * size.X,
				topY + 50,
				cf.Position.Z + fz * size.Z)
			-- punch through non-walkable hits until something standable answers
			for _ = 1, 8 do
				local hit = Workspace:Raycast(origin, Vector3.new(0, -(size.Y + 100), 0), rp)
				if not hit then break end
				if hit.Instance.CanCollide and hit.Instance.Transparency < 0.95 then
					table.insert(hits, hit.Position.Y)
					break
				end
				origin = hit.Position - Vector3.new(0, 0.1, 0)
			end
		end
	end

	if #hits == 0 then return topY, "bbox", nil end

	-- 3) area vote: bin hits into BAND-stud bands, pick the fullest band.
	local bins = {}
	for _, y in ipairs(hits) do
		local b = math.floor(y / BAND)
		bins[b] = (bins[b] or 0) + 1
	end
	local bestBin, bestCount = nil, -1
	for b, n in pairs(bins) do
		-- ties go to the LOWER band: ground beats an equally-sized plateau on top of it
		if n > bestCount or (n == bestCount and b < bestBin) then
			bestBin, bestCount = b, n
		end
	end

	-- surface = median of the hits inside the winning band (+/- one band for slope)
	local deck = {}
	for _, y in ipairs(hits) do
		local b = math.floor(y / BAND)
		if b >= bestBin - 1 and b <= bestBin + 1 then table.insert(deck, y) end
	end
	table.sort(deck)
	local surface = deck[math.ceil(#deck / 2)]
	return surface, "grid", bestCount / #hits
end

print("==================== ISLAND SURFACE REPORT ====================")
print(("place: %s   islands: %d   (%dx%d rays per island, %d-stud bands)"):format(game.Name, COUNT, GRID, GRID, BAND))
print("slot | model     | regY      | offset   | surfaceY  | sGap->next | regGap  | method  | conf")

local rows = {}
for slot = 1, COUNT do
	local islandNum = SLOT_TO_ISLAND[slot]
	local isl = Workspace:FindFirstChild("island" .. islandNum)
	local row = { slot = slot, islandNum = islandNum }
	if isl then
		local sy, method, conf = surfaceYOf(isl)
		if sy then
			local pivotY = isl:GetPivot().Position.Y
			row.offset = sy - pivotY                      -- pivot -> surface, position-independent
			row.surfaceY = SLOT_POS[slot].Y + row.offset  -- where the surface sits IN THE TOWER
			row.method = method
			row.conf = conf
		end
	end
	rows[slot] = row
end

local lowConf = {}
for slot = 1, COUNT do
	local r = rows[slot]
	local nxt = rows[slot + 1]
	local regY = SLOT_POS[slot].Y
	local regGap = SLOT_POS[slot + 1] and (SLOT_POS[slot + 1].Y - regY) or nil
	if r.offset then
		local sGap = (nxt and nxt.surfaceY) and (nxt.surfaceY - r.surfaceY) or nil
		local confStr = r.conf and string.format("%d%%", math.floor(r.conf * 100 + 0.5)) or "--"
		print(("%4d | island%-3d | %9.1f | %8.2f | %9.2f | %10s | %7s | %-7s | %s"):format(
			slot, r.islandNum, regY, r.offset, r.surfaceY,
			sGap and string.format("%.2f", sGap) or "--",
			regGap and string.format("%.1f", regGap) or "--",
			r.method .. (r.method == "bbox" and "!" or ""), confStr))
		if r.method == "bbox" or (r.conf and r.conf < 0.45) then
			table.insert(lowConf, string.format("slot %d (island%d)", slot, r.islandNum))
		end
	else
		print(("%4d | island%-3d | %9.1f |   MISSING or no parts -- open the place fully / check the model name")
			:format(slot, r.islandNum, regY))
	end
end

if #lowConf > 0 then
	print("")
	print("CHECK BY EYE (terraced/hilly or unmeasurable -- consider adding a SurfaceMarker part):")
	print("  " .. table.concat(lowConf, ", "))
end

print("")
print("-- copy-paste block: slot -> surface offset (pivot -> walkable deck, studs) --")
local parts = {}
for slot = 1, COUNT do
	parts[#parts + 1] = rows[slot].offset and string.format("[%d]=%.2f", slot, rows[slot].offset) or string.format("[%d]=nil", slot)
end
print("OFFSETS = { " .. table.concat(parts, ", ") .. " }")

print("")
print("PORTING RECIPE (surface-accurate spacing across realms):")
print("  1. Run this in the SOURCE realm -> note each slot's surfaceY (or the sGap column).")
print("  2. Run this in the TARGET realm -> note the target's OFFSETS.")
print("  3. Target SLOT_POS[n].Y = desired surfaceY[n] - targetOffset[n].")
print("     (Layout places by PIVOT, so subtracting the offset puts the SURFACE on target.)")
print("===============================================================")
