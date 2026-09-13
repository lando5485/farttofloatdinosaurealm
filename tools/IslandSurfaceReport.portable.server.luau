--======================================================================
-- IslandSurfaceReport.portable.server.luau
--======================================================================
-- PORTABLE island-surface report -- for measuring ANOTHER realm (e.g. the
-- first / Food realm) the same way the Dino realm was measured.
--
-- HOW TO USE (in the OTHER realm's place):
--   1. Put a part named "islandmarker" INSIDE each island's model, its TOP
--      face resting where players actually stand (same as the dino realm).
--   2. In Explorer: right-click ServerScriptService > Insert Object > Script.
--   3. Paste this WHOLE file into it (replace the default line).
--   4. Press Play. In the Output window, search for "SURFACE REPORT".
--   5. Copy the whole report block. Delete the Script afterwards.
--
-- Unlike the dino realm's copy, this one AUTO-FINDS the IslandOrder module
-- anywhere under ReplicatedStorage (any folder name), and if the realm has
-- no IslandOrder at all it still reports each island's LIVE surface Y and
-- the surface-to-surface gaps by island number order (island1, island2...).
--======================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

task.spawn(function()
	-- Give the realm's own layout script (if any) time to move islands first.
	local t0 = os.clock()
	while not _G.islandsPositioned and os.clock() - t0 < 15 do task.wait(0.1) end
	task.wait(1)

	-- Find IslandOrder wherever this realm keeps it (any folder name).
	local IslandOrder
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("ModuleScript") and d.Name == "IslandOrder" then
			local ok, mod = pcall(require, d)
			if ok and type(mod) == "table" and mod.SLOT_TO_ISLAND then IslandOrder = mod break end
		end
	end

	-- Build the slot list: from IslandOrder if present, else island1..N found in Workspace.
	local slots = {}   -- array of { islandNum = n }
	if IslandOrder then
		for slot, islandNum in ipairs(IslandOrder.SLOT_TO_ISLAND) do
			slots[slot] = { islandNum = islandNum }
		end
	else
		local n = 1
		while Workspace:FindFirstChild("island" .. n) do
			slots[n] = { islandNum = n }
			n += 1
		end
	end

	print("==================== ISLAND SURFACE REPORT (portable) ====================")
	print(("place: %s   islands: %d   order: %s"):format(
		game.Name, #slots, IslandOrder and "IslandOrder.SLOT_TO_ISLAND" or "island number (no IslandOrder found)"))
	print("slot | model     | regY      | surfaceY  | offset   | sGap->next")

	local rows = {}
	for slot, s in ipairs(slots) do
		local isl = Workspace:FindFirstChild("island" .. s.islandNum)
		local marker = isl and findMarker(isl)
		rows[slot] = { islandNum = s.islandNum }
		if isl and marker then
			rows[slot].surfaceY = marker.Position.Y + marker.Size.Y / 2
			rows[slot].pivotY = isl:GetPivot().Position.Y
		end
	end

	local missing = {}
	for slot = 1, #slots do
		local r = rows[slot]
		local regY = IslandOrder and IslandOrder.SLOT_POS and IslandOrder.SLOT_POS[slot]
			and IslandOrder.SLOT_POS[slot].Y or r.pivotY
		if r.surfaceY then
			local nxt = rows[slot + 1]
			local sGap = (nxt and nxt.surfaceY) and (nxt.surfaceY - r.surfaceY) or nil
			print(("%4d | island%-3d | %9s | %9.2f | %8s | %s"):format(
				slot, r.islandNum,
				regY and string.format("%.1f", regY) or "--",
				r.surfaceY,
				regY and string.format("%.2f", r.surfaceY - regY) or "--",
				sGap and string.format("%.2f", sGap) or "--"))
		else
			print(("%4d | island%-3d |   NO MARKER -- add a part named 'islandmarker' INSIDE this island's model")
				:format(slot, r.islandNum))
			table.insert(missing, string.format("slot %d (island%d)", slot, r.islandNum))
		end
	end

	print("")
	print("-- copy-paste blocks --")
	local sy, off = {}, {}
	for slot = 1, #slots do
		local r = rows[slot]
		sy[#sy + 1] = r.surfaceY and string.format("[%d]=%.2f", slot, r.surfaceY) or string.format("[%d]=nil", slot)
		off[#off + 1] = (r.surfaceY and r.pivotY)
			and string.format("[%d]=%.2f", slot, r.surfaceY - r.pivotY)
			or string.format("[%d]=nil", slot)
	end
	print("SURFACE_Y = { " .. table.concat(sy, ", ") .. " }")
	print("PIVOT_OFFSET = { " .. table.concat(off, ", ") .. " }   -- surface minus model pivot, per slot")

	if #missing > 0 then
		warn("[SurfaceReport] markers missing on: " .. table.concat(missing, ", "))
	end
	print("==========================================================================")
end)
