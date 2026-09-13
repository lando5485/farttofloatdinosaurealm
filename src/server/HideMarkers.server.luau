--======================================================================
-- HideMarkers.server.luau  (Script -> ServerScriptService/DinosaurRealmServer)
--======================================================================
-- ONE SWEEP THAT HIDES EVERY PLACEMENT MARKER IN THE GAME.
--
-- A placement marker is a part you dropped in Studio to say "build the thing HERE". The
-- code reads its position and then builds a nest, a geyser, an NPC, a locker. The marker
-- itself was never meant to be seen -- but until something ghosts it, it sits there as a
-- grey box floating in the world, and on a quest you have not started yet it is a grey box
-- marking a reward that does not exist.
--
-- WHY THIS IS ONE SERVER SCRIPT AND NOT SEVEN CLIENT ONES
-- It was seven client ones. GeyserQuest ghosted its own, RaptorNest ghosted its own,
-- BurritoDig, Mosquito, VolcanoFireballs, RedwoodRaptor -- each quest cleaned up after
-- itself, which meant:
--   * A marker for a quest whose script had not run yet stayed visible.
--   * STREAMING UNDID IT. Transparency set on the client is a local change to a replicated
--     part; stream the island out and back in and the part comes back from the server
--     exactly as the server still has it -- visible. VolcanoFireballs already hit this and
--     had to add a server-side pass to fix it, with the note "they stay hidden through
--     streaming now, unlike the client-side ghosting". This is that fix, generalised.
-- Doing it once on the server means the parts are hidden in the authoritative copy, so
-- there is nothing for streaming to restore.
--
-- WHY IT CANNOT ACCIDENTALLY HIDE REAL CONTENT
-- Two independent reasons, and both matter:
--   1. THE NAMES ARE ANCHORED. Every pattern below is a whole-name match, not a substring.
--      "EggSpot7" is a marker; "Egg" is the actual egg model the Lost Eggs are cloned from,
--      and a substring match on "egg" would have deleted the game's eggs from view. Same
--      trap with "Stand" (food stands) and "Dig" vs "Digger".
--   2. THE QUEST BUILDERS ARE ON THE CLIENT. GeyserQuest, RaptorNestQuest, BurritoDig and
--      MosquitoQuest all BUILD their props client-side, so the geysers, meat and eggs they
--      create do not exist on the server at all. This script physically cannot see them,
--      which is why it is safe to re-sweep later without ever hiding built content.
--
-- ADDING A NEW MARKER: put its name in MARKERS below. The script prints anything it hid and
-- anything that looked marker-ish but was NOT matched, so a new one shows up in the log
-- rather than silently staying visible.
--======================================================================

local Workspace = game:GetService("Workspace")

-- Whole-name Lua patterns, matched case-insensitively against the part's name.
-- `%d*` so both the bare name and the numbered variants are covered: the map uses "Geyser"
-- and "Geyser1".."Geyser6", "Meat1".."Meat5", "EggSpot5"/"EggSpot7"/"EggSpot8", and so on.
local MARKERS = {
	"^eggspot%d*$",        -- where a quest reward egg appears (volcano, mosquito, raptor nest)
	"^eggplacement%d*$",   -- the five Lost Egg spots on island 1
	"^geyser%d*$",         -- the six volcano vents on the summit
	"^meat%d*$",           -- raptor-nest bait spots
	"^dig%d*$",            -- burrito dig sites
	"^putdino%d*$",        -- where the Redwood raptors stand
	"^npcspot%d*$",        -- island quest-giver positions
	"^island%d+npc$",      -- the older name for the same thing (Island7NPC, Island8NPC)
	"^dinoplacement%d*$",  -- Mama Dino
	"^sniperspot%d*$",     -- the island-12 gun locker
	"^volcanospot%d*$",    -- the crater the fireballs erupt from
}

-- Names that are NOT markers but sit one letter away from one. Listed only so the "near
-- miss" report below does not cry wolf about them every boot.
local KNOWN_SAFE = {
	egg = true, stand = true, shop = true, digger = true, digminer = true, spawn = true,
}

local function isMarker(name)
	local n = name:lower()
	for _, pat in ipairs(MARKERS) do
		if n:match(pat) then return true end
	end
	return false
end

-- Looks like a marker but did not match -- worth printing once so a newly-added marker with
-- an unexpected name is visible in the log instead of quietly showing up in the world.
local function looksMarkerish(name)
	local n = name:lower()
	if KNOWN_SAFE[n] then return false end
	return (n:match("spot") or n:match("placement") or n:match("marker") or n:match("^put"))
		and not isMarker(name)
end

-- Hide, do not destroy. A destroyed marker takes its CFrame with it, and several quests read
-- that position lazily -- GeyserQuest waits for the island to stream in before it looks. The
-- part has to still be there, just invisible and intangible.
local function hide(p)
	if not p:IsA("BasePart") then return false end
	if p.Transparency >= 1 and not p.CanCollide and not p.CanQuery then return false end
	p.Transparency = 1
	p.CanCollide   = false
	p.CanQuery     = false   -- so raycasts (ground probes, the locker's floor ray) pass through
	p.CanTouch     = false
	p.CastShadow   = false   -- an invisible part still throws a shadow without this
	return true
end

local function sweep()
	local hidden, byName, nearMiss = 0, {}, {}
	for _, root in ipairs(Workspace:GetChildren()) do
		if root:IsA("Model") and root.Name:lower():match("^island%d+$") then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then
					if isMarker(d.Name) then
						if hide(d) then
							hidden = hidden + 1
							byName[d.Name] = (byName[d.Name] or 0) + 1
						end
					elseif looksMarkerish(d.Name) then
						nearMiss[d.Name] = (nearMiss[d.Name] or 0) + 1
					end
				end
			end
		end
	end
	return hidden, byName, nearMiss
end

-- IslandLayout moves every island into the tower on boot and sets this when it is done.
-- Sweeping before that is harmless (the parts exist either way) but waiting keeps the log
-- honest about what was actually in the world.
local t0 = os.clock()
while not _G.islandsPositioned and os.clock() - t0 < 15 do task.wait(0.25) end

local total, names, misses = sweep()

local list = {}
for n, c in pairs(names) do list[#list + 1] = (c > 1 and ("%s x%d"):format(n, c) or n) end
table.sort(list)
print(("[Markers] hid %d placement marker part(s): %s")
	:format(total, #list > 0 and table.concat(list, ", ") or "none found"))

local miss = {}
for n, c in pairs(misses) do miss[#miss + 1] = (c > 1 and ("%s x%d"):format(n, c) or n) end
if #miss > 0 then
	table.sort(miss)
	warn(("[Markers] these look like placement markers but are NOT in the list, so they are " ..
		"STILL VISIBLE -- add them to MARKERS in HideMarkers.server.luau if they should be " ..
		"hidden: %s"):format(table.concat(miss, ", ")))
end

-- A few late passes. Nothing on the server should appear after boot, but FoodStands copies
-- island 1's stand onto bare islands and the NPC placer re-parents things, so a marker that
-- arrives with them would otherwise be missed. Cheap, and it stops on the first quiet run.
task.spawn(function()
	for _ = 1, 4 do
		task.wait(3)
		local n = sweep()
		if n > 0 then print(("[Markers] late pass hid %d more"):format(n)) end
	end
end)
