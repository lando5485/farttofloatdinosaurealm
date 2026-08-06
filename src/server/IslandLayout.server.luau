--======================================================================
-- IslandLayout.server.luau  (server Script)  -- RUNS FIRST
--======================================================================
-- Spaces the 13 islands into the vertical "tower" layout. Each island MODEL is
-- moved to its target slot (rotation preserved, children come along). Then it
-- sets _G.islandsPositioned, which the island-dependent scripts (NestingNook_*,
-- RedwoodRaptor) wait on so their NPCs / eggs / spawns land at the NEW positions.
--
-- TOWER ORDER = QUEST, NO-QUEST, QUEST, NO-QUEST, ... island1 pinned to the bottom,
-- and island11 "VOLCANIC VISTA" PINNED TO THE TOP as the ending island.
--   slot 1 (bottom): island1  (QUEST)     slot 8 : island2  (QUEST)
--   slot 2         : island9  (blank)     slot 9 : island10 (blank)
--   slot 3         : island5  (QUEST)     slot 10: island7  (QUEST)
--   slot 4         : island12 (blank)     slot 11: island6  (QUEST)  <- see note
--   slot 5         : island3  (QUEST)     slot 12: island8  (blank)
--   slot 6         : island13 (blank)     slot 13 (top): island11 (QUEST) <- FINALE
--   slot 7         : island4  (QUEST)
--
-- (island5 Misty Mire and island2 Fern Frontier were SWAPPED by request -- slots 3 and 8.
-- This table was ALSO stale before that swap: it listed slot 9 as island5 and slot 12 as
-- island7, which matched no version of SLOT_TO_ISLAND. IslandOrder is the only authority.)
--
-- QUEST islands: 1, 2, 3, 4, 5, 6, 7, 11  (8 of them).
-- BLANK islands: 8, 9, 10, 12, 13         (5 of them).
--   NOTE island8 is a BLANK now -- its geyser quest MOVED to island11, so island8
--   is just scenery ("Inferno Isle"). The quest islands are NOT 1-8 any more.
--
-- THE ENDING ISLAND IS island11 "Volcanic Vista" (top slot): the volcano / geyser
-- FINALE quest, and it grants the T-Rex. Whatever else changes about this layout,
-- Volcanic Vista must stay in the TOP slot.
--
-- NOTE -- why slots 11/12/13 are three quests back-to-back:
--   Perfectly alternating 8 quest islands requires 7 blanks (one between each
--   pair). We only have 5, so the alternation runs out after slot 10 and the last
--   three quest islands stack. To alternate the WHOLE tower, add 2 more blank
--   islands (island14, island15) -- see the note at the bottom of this file.
--======================================================================
local Workspace = game:GetService("Workspace")

-- Slot CENTERS (x, y, z) -- zig-zag tower.
-- X and Z keep the original alternating-sign pattern (+20 magnitude per slot).
-- Y is DERIVED, not chosen: each gap is 92% of what a FULL tank climbs on the gut
-- that flies it (FlightTuning.MARGIN = 1.08). A tank is 80s of thrust, so a clean
-- run only just makes it and any gas spent steering costs you the landing -- the
-- retries are the pacing, not one slow drift. Two islands per gut tier, gaps in pairs:
--   Hatchling 6000 | Raptor 6600 | Stego 7200 | Bronto 7800 | Rex 8400 | Fossil 9000
-- CHANGING ANY OF THESE BREAKS THE PACING. The Y values, the food prices and gut
-- costs in Shop.server.luau, and FLIGHT_SECONDS + the band speeds in FlightTuning are
-- one interlocked set -- retune together or not at all.
-- The ladder and the tower order BOTH live in the shared IslandOrder module -- the
-- SINGLE source of truth the Wormhole, progress tracking and the island arrow also
-- read, so they can never disagree. The positions had to move there because the
-- CLIENT needs them and cannot read them off Workspace: a streamed-out island has no
-- parts, so its pivot reads as the origin. Edit them there; this script applies them.
local IslandOrder = require(game:GetService("ReplicatedStorage")
	:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local SLOT_POS       = IslandOrder.SLOT_POS
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND

-- Highest slot that gets an island. Must not exceed #IslandOrder.SLOT_TO_ISLAND.
local TOP_SLOT = 13

-- SLOT_TO_ISLAND (slot bottom=1 .. top=13 -> island MODEL number) is arranged QUEST/blank
-- so no 3 quest islands sit in a row; island11 "Volcanic Vista" stays the summit finale.
for slot = 1, TOP_SLOT do
	local islandNum = SLOT_TO_ISLAND[slot]
	local pos = SLOT_POS[slot]
	local isl = Workspace:FindFirstChild("island" .. islandNum)
	if isl and pos then
		local ok, err = pcall(function()
			local cur = isl:GetPivot()
			isl:PivotTo(CFrame.new(pos) * (cur - cur.Position)) -- move to target, keep current rotation
		end)
		if ok then
			print(("[IslandLayout] slot %d -> island%d @ (%d, %d, %d)")
				:format(slot, islandNum, pos.X, pos.Y, pos.Z))
		else
			warn(("[IslandLayout] island%d move FAILED: %s"):format(islandNum, tostring(err)))
		end
	else
		warn("[IslandLayout] island" .. islandNum .. " not found (slot " .. slot .. ")")
	end
end

_G.islandsPositioned = true
print(("[IslandLayout] %d islands spaced into the tower (quest / no-quest alternating)."):format(TOP_SLOT))

--======================================================================
-- FUTURE: perfect alternation, all the way to the top.
-- 8 quest islands need 7 blanks to fully separate them; we have 5. Add TWO more
-- blank islands (island14, island15) and swap in this 15-slot order + the two
-- extra slot positions. Then no two quest islands are ever adjacent, and
-- Volcanic Vista is still the ending island at the summit.
--
--   [14] = Vector3.new( 380, 21900, -340),
--   [15] = Vector3.new(-400, 24800,  360),
--
--   [1] = 1,   -- QUEST  Nesting Nook       [9]  = 5,   -- QUEST  Misty Mire
--   [2] = 9,   -- blank  Jungle Junction    [10] = 8,   -- blank  Inferno Isle
--   [3] = 2,   -- QUEST  Fern Frontier      [11] = 6,   -- QUEST  Redwood Ridge
--   [4] = 12,  -- blank  Sunscorch Sands    [12] = 14,  -- blank  (NEW)
--   [5] = 3,   -- QUEST  Fossil Frontier    [13] = 7,   -- QUEST  Raptor Ridge
--   [6] = 13,  -- blank  Glacier Gulch      [14] = 15,  -- blank  (NEW)
--   [7] = 4,   -- QUEST  Coastal Crossing   [15] = 11,  -- QUEST  VOLCANIC VISTA (summit)
--   [8] = 10,  -- blank  Petrified Pass
--======================================================================
