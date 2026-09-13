--======================================================================
-- AnchorIslands.server.luau  (Server Script)
--======================================================================
-- Anchors EVERY static BasePart inside island1 .. island13, so the islands stay
-- put / never fall or drift.
--
-- WHAT IS DELIBERATELY *NOT* ANCHORED (anchoring these BREAKS them):
--   * Dinosaurs (dino1, RaptorModel, MamaRaptor) -- moved/animated elsewhere.
--   * Any model with a Humanoid (the quest NPCs) -- anchoring freezes them.
--   * Tools + their handles (shovel, fishing rod) -- must stay loose to weld to
--     the player's hand.
--   * WELDED rig parts -- NestingNook_NPCs builds rigs as an ANCHORED root with
--     UNANCHORED children welded to it, then animates the root's CFrame (see
--     setupDinoIdle). The welded children are held in place BY the weld. Anchor
--     them and they stop following the root -> the idle animation freezes.
--
-- TWO PASSES:
--   Pass 1 runs immediately (static island geometry, before any rig is built).
--   Pass 2 runs after the islands are positioned + the quest scripts have spawned
--     their props, and catches anything created after pass 1 (eggs, barrels,
--     geysers, quest props). It uses the same skip rules, so it can never freeze
--     a rig or a tool.
--======================================================================

local Workspace = game:GetService("Workspace")

-- VERBOSE: per-item boot spam. OFF by default -- it buried the progression telemetry.
-- Same flag name in every file that had a noisy loop, so it greps as one switch.
local VERBOSE = false

local TOP_ISLAND = 13

-- skip the DINOSAURS (managed elsewhere so they can move): dino1, RaptorModel, MamaRaptor
local function isDino(inst)
	return inst:FindFirstAncestor("dino1") or inst:FindFirstAncestor("RaptorModel") or inst:FindFirstAncestor("MamaRaptor")
end

-- Every part that is the DRIVEN side of a weld (Part1) is held by that weld --
-- anchoring it would break the rig. Build this set ONCE per pass; checking it
-- per-part by rescanning Workspace would be O(parts x descendants) and stall
-- startup on the bigger islands.
local function buildWeldedSet(): { [BasePart]: boolean }
	local welded = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("WeldConstraint") then
			if d.Part1 then welded[d.Part1] = true end
		elseif d:IsA("Weld") or d:IsA("Motor6D") then
			if d.Part1 then welded[d.Part1] = true end
		end
	end
	return welded
end

-- A part is "static" only if nothing else is driving it: not a dino, not inside a
-- Tool, not inside a Humanoid model (NPC), and not welded to some other part.
local function isStatic(part: BasePart, welded: { [BasePart]: boolean }): boolean
	if isDino(part) then return false end
	if welded[part] then return false end
	if part:FindFirstAncestorWhichIsA("Tool") then return false end

	-- inside an NPC / character model? (a Humanoid anywhere up the chain)
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then return false end
		model = model:FindFirstAncestorWhichIsA("Model")
	end

	return true
end

-- Anchor every static BasePart under island1..island13. Returns how many it changed.
local function anchorPass(label: string): number
	local welded = buildWeldedSet()
	local total = 0
	for i = 1, TOP_ISLAND do
		local isl = Workspace:FindFirstChild("island" .. i)
		if isl then
			local n = 0
			if isl:IsA("BasePart") and not isl.Anchored and isStatic(isl, welded) then
				isl.Anchored = true; n += 1
			end
			for _, d in ipairs(isl:GetDescendants()) do
				if d:IsA("BasePart") and not d.Anchored and isStatic(d, welded) then
					d.Anchored = true; n += 1
				end
			end
			total += n
			if VERBOSE and n > 0 then
				print(("[Anchor][%s] island%d -> anchored %d part(s)"):format(label, i, n))
			end
		else
			warn(("[Anchor][%s] island%d NOT FOUND"):format(label, i))
		end
	end
	return total
end

-- PASS 1: static island geometry, right now (before any rig/NPC is built).
local total = anchorPass("pass1")
print(("[Anchor] pass1 done -- %d part(s) anchored across islands 1-%d (dinos/NPCs/tools skipped)")
	:format(total, TOP_ISLAND))

-- PASS 2: catch props spawned AFTER pass 1 (the quest scripts wait on
-- _G.islandsPositioned, then build eggs / barrels / geysers / nests).
task.spawn(function()
	local t0 = os.clock()
	while not _G.islandsPositioned and os.clock() - t0 < 10 do task.wait() end
	task.wait(5) -- let NestingNook_* / RedwoodRaptor finish spawning their props
	local n = anchorPass("pass2")
	print(("[Anchor] pass2 done -- %d late-spawned part(s) anchored"):format(n))
end)

-- anchor any food "Stand" models (island5/6) so they never fall apart
do
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		-- match "Stand" case-insensitively, with an optional number suffix ("Stand", "stand", "Stand8", ...)
		if d.Name:lower():match("^stand%d*$") then
			if d:IsA("BasePart") then d.Anchored = true; n += 1 end
			for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true; n += 1 end end
		end
	end
	print(("[Anchor] anchored %d 'Stand' part(s)"):format(n))
end
