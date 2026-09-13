--======================================================================
-- IslandSurfaceReport.server.luau  (server Script)
--======================================================================
-- Prints the ISLAND SURFACE REPORT to the Output window at every boot --
-- no Command Bar needed, just press Play and search Output for
-- "SURFACE REPORT".
--
-- WHAT IT MEASURES. Each island carries a hand-placed part named
-- "islandmarker" (any of islandmarker / IslandMarker / SurfaceMarker --
-- spaces, underscores and case ignored) whose TOP face rests on the spot
-- players actually stand. The report reads that part's top, LIVE, after
-- IslandLayout has moved the islands into the tower, so surfaceY is the
-- real in-world height of each island's walkable surface.
--
-- WHY. IslandLayout places islands by PIVOT (bounding-box centre), but
-- the spacing/economy is tuned surface-to-surface. This realm's islands
-- are big, so each surface sits a different distance above its registered
-- SLOT_POS.Y. To port this realm's spacing to another realm you need the
-- SURFACE numbers, not the pivot numbers -- this prints both, plus the
-- surface-to-surface gap next to the registered gap.
--
-- Read-only: measures and prints, never moves anything. Delete this file
-- (and regenerate the security manifest) once the porting work is done.
--======================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local SLOT_POS = IslandOrder.SLOT_POS
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND
local COUNT = IslandOrder.COUNT

-- Marker names accepted, compared with spaces/underscores stripped, case ignored.
local function isMarkerName(name)
	local n = string.lower(string.gsub(name, "[%s_]", ""))
	return n == "islandmarker" or n == "surfacemarker"
end

local function findMarker(isl)
	for _, d in ipairs(isl:GetDescendants()) do
		if d:IsA("BasePart") and isMarkerName(d.Name) then return d end
	end
	return nil
end

-- Wait for IslandLayout to move the islands into the tower first, or the
-- marker Ys would be the authored editor positions, not the live tower.
task.spawn(function()
	while not _G.islandsPositioned do task.wait(0.1) end
	task.wait(1)   -- let anchoring settle so nothing is mid-move

	print("==================== ISLAND SURFACE REPORT ====================")
	print(("islands: %d   surface = top of each island's 'islandmarker' part (live, in-tower)"):format(COUNT))
	print("slot | model     | regY      | surfaceY  | offset   | sGap->next | regGap")

	local rows = {}
	for slot = 1, COUNT do
		local islandNum = SLOT_TO_ISLAND[slot]
		local isl = Workspace:FindFirstChild("island" .. islandNum)
		local marker = isl and findMarker(isl)
		rows[slot] = { islandNum = islandNum }
		if marker then
			rows[slot].surfaceY = marker.Position.Y + marker.Size.Y / 2
		end
	end

	local missing = {}
	for slot = 1, COUNT do
		local r = rows[slot]
		local regY = SLOT_POS[slot].Y
		local regGap = SLOT_POS[slot + 1] and (SLOT_POS[slot + 1].Y - regY) or nil
		if r.surfaceY then
			local nxt = rows[slot + 1]
			local sGap = (nxt and nxt.surfaceY) and (nxt.surfaceY - r.surfaceY) or nil
			print(("%4d | island%-3d | %9.1f | %9.2f | %8.2f | %10s | %s"):format(
				slot, r.islandNum, regY, r.surfaceY, r.surfaceY - regY,
				sGap and string.format("%.2f", sGap) or "--",
				regGap and string.format("%.1f", regGap) or "--"))
		else
			print(("%4d | island%-3d | %9.1f |  NO MARKER -- add a part named 'islandmarker' INSIDE this island's model")
				:format(slot, r.islandNum, regY))
			table.insert(missing, string.format("slot %d (island%d)", slot, r.islandNum))
		end
	end

	print("")
	print("-- copy-paste block: slot -> surfaceY (studs, live tower) --")
	local parts = {}
	for slot = 1, COUNT do
		parts[#parts + 1] = rows[slot].surfaceY
			and string.format("[%d]=%.2f", slot, rows[slot].surfaceY)
			or string.format("[%d]=nil", slot)
	end
	print("SURFACE_Y = { " .. table.concat(parts, ", ") .. " }")

	if #missing > 0 then
		warn("[SurfaceReport] markers missing on: " .. table.concat(missing, ", "))
	end
	print("PASTE THIS WHOLE REPORT BACK. To port spacing to another realm you also")
	print("need that realm's own marker report -- run its version of this there.")
	print("===============================================================")
end)
