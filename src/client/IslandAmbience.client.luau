--======================================================================
-- IslandAmbience.client.luau  (LocalScript)
--======================================================================
-- The nature bed around each island -- birds, water, wind, whatever each one calls for.
-- One looping positional Sound per island, so it swells as you land and falls away as you
-- climb out. No zones, no triggers, no polling: distance rolloff does all of it.
--
-- ===== THE NUMBERS ARE CLIMB SLOTS =====
-- Slot 13 is the SUMMIT (Volcanic Vista, whose model is named island11), the same way
-- goisland13 and complete13 mean the summit. Model numbers are build order and deliberately
-- scrambled -- see the long note in IslandOrder.luau.
--
-- IF THE MAPPING COMES OUT WRONG -- desert noise on the glacier, waves on a volcano -- the
-- likely cause is that these were meant as MODEL numbers instead. Flip KEY_BY_SLOT to false
-- and the same table is read that way. The boot print lists every island by name so a
-- mismatch is obvious on the first run rather than something you notice weeks later.
--
-- ===== POSITIONS COME FROM THE SHARED LADDER =====
-- IslandOrder.SLOT_POS, not the models in Workspace. With StreamingEnabled a distant
-- island's parts are not replicated and its model reports a zero-size box at the origin --
-- so anything that measures the world for island positions puts far islands at Y 0. Bubbles
-- and DinoIslandArrow read the ladder for exactly this reason.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

--======================================================================
-- TUNING
--======================================================================
-- Ambience should be clearly THERE when you are standing on an island and gone by the time
-- you are crossing. It sits above the music (0.22, 2D) because it is positional and only
-- one or two are ever audible at once -- but under the quest SFX, which have to cut through
-- it.
-- Fallback only -- every group below sets its own. Kept so a group added later without a
-- `volume` still plays at something sane.
local VOLUME = 0.40

-- Full volume anywhere on the island; silent well before the next one. The tightest gap in
-- the tower is 1,213 studs (slot 1 -> 2), so 700 leaves a genuinely quiet stretch mid-
-- crossing rather than letting two islands' beds overlap into mud.
local ROLLOFF_MIN = 120
local ROLLOFF_MAX = 700

-- Set false if these numbers turn out to be MODEL numbers rather than climb slots.
local KEY_BY_SLOT = true

-- ===== VOLUME IS PER SOUND, NOT PER ISLAND =====
-- The four clips are mastered at different levels, so one shared number could only ever be
-- right for one of them -- which is exactly how it played: the open-air bed on slots 1, 7,
-- 10, 11, 12 and 13 was inaudible while the other three sat on top of everything.
--
-- Each group therefore carries its own `volume`, tuned against the clip rather than against
-- the island. Adjusting one group cannot disturb the others.
--
-- These are ROUGH FIRST VALUES SET BY EAR-REPORT, not measurements -- the open-air bed is
-- up ~1.75x and the other three down ~0.7x from the old shared 0.40. Nudge the single number
-- on a group's row if it is still off; nothing else needs touching.
local GROUPS = {
	{ id = "rbxassetid://9114891426",     volume = 0.70, keys = { 1, 7, 10, 11, 12, 13 } },
	{ id = "rbxassetid://73399320704222", volume = 0.28, keys = { 8 } },
	{ id = "rbxassetid://9114057128",     volume = 0.28, keys = { 4, 5, 9 } },
	{ id = "rbxassetid://6670092634",     volume = 0.28, keys = { 2, 6 } },
}

--======================================================================
-- Resolve the table into slot -> { id, volume }.
--======================================================================
local bySlot = {}
for _, group in ipairs(GROUPS) do
	for _, key in ipairs(group.keys) do
		local slot = key
		if not KEY_BY_SLOT then
			-- The key is a MODEL number; convert it to the slot that model sits in.
			slot = IslandOrder.ISLAND_TO_SLOT[key]
		end
		if slot and IslandOrder.SLOT_POS[slot] then
			if bySlot[slot] then
				warn(("[Ambience] slot %d is listed in two groups -- keeping the first"):format(slot))
			else
				bySlot[slot] = { id = group.id, volume = group.volume or VOLUME }
			end
		else
			warn(("[Ambience] key %d does not resolve to a real island -- skipped"):format(key))
		end
	end
end

--======================================================================
-- Build one emitter per island.
--======================================================================
local bin = Instance.new("Folder")
bin.Name = "IslandAmbience"
bin.Parent = Workspace

local made, missing = {}, {}

for slot = 1, IslandOrder.COUNT do
	local entry = bySlot[slot]
	local islandNum = IslandOrder.SLOT_TO_ISLAND[slot]
	local name = islandNum and IslandOrder.NAMES[islandNum] or "?"

	if not entry then
		-- Not an error: an island with no ambience listed simply stays quiet.
		table.insert(missing, ("slot %d %s"):format(slot, name))
	else
		local pos = IslandOrder.SLOT_POS[slot]

		-- An invisible anchor to hang the Sound on. A Sound needs a BasePart or Attachment
		-- parent to be positional at all -- parented to the Workspace it plays flat 2D
		-- everywhere, which would stack all thirteen beds on top of each other.
		local a = Instance.new("Part")
		a.Name = ("Ambience_%d_%s"):format(slot, name:gsub("%s", ""))
		a.Size = Vector3.new(1, 1, 1)
		-- Lifted toward the island's deck rather than its pivot, so the bed is centred on
		-- where the player actually walks.
		a.Position = pos + Vector3.new(0, 40, 0)
		a.Transparency = 1
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CanTouch = false
		a.CastShadow = false
		a.Parent = bin

		local s = Instance.new("Sound")
		s.Name = "Ambience"
		s.SoundId = entry.id
		s.Looped = true
		s.Volume = entry.volume
		s.RollOffMode = Enum.RollOffMode.Linear
		s.RollOffMinDistance = ROLLOFF_MIN
		s.RollOffMaxDistance = ROLLOFF_MAX
		s.Parent = a
		pcall(function() s:Play() end)

		table.insert(made, ("%d=%s@%.2f"):format(slot, name, entry.volume))
	end
end

print(("[Ambience] %d island beds up (per-sound volume, rolloff %d-%d), keyed by %s")
	:format(#made, ROLLOFF_MIN, ROLLOFF_MAX, KEY_BY_SLOT and "CLIMB SLOT" or "MODEL NUMBER"))
for _, g in ipairs(GROUPS) do
	print(("[Ambience]   %s  vol %.2f  -> slots %s")
		:format(g.id, g.volume or VOLUME, table.concat(g.keys, ",")))
end
print("[Ambience] " .. table.concat(made, ", "))
if #missing > 0 then
	print("[Ambience] no ambience listed for: " .. table.concat(missing, ", "))
end
