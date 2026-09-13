--======================================================================
-- IslandLayout.server.luau  (server Script)  -- RUNS FIRST
--======================================================================
-- Spaces the 13 islands into the vertical "tower" layout. Each island MODEL is
-- moved to its target slot (rotation preserved, children come along). Then it
-- sets _G.islandsPositioned, which the island-dependent scripts (NestingNook_*,
-- RedwoodRaptor) wait on so their NPCs / eggs / spawns land at the NEW positions.
--
-- TOWER ORDER LIVES IN IslandOrder.SLOT_TO_ISLAND, NOT HERE. This script only applies
-- it. The order and the reasoning behind it are documented there -- read that, not this.
--
--   slot  1  island1   Nesting Nook       QUEST  Stegosaurus   Common     <- spawn
--   slot  2  island9   Frostbite Flats    --  (snow island)
--   slot  3  island5   Misty Mire         QUEST  Spinosaurus   Common
--   slot  4  island12  Sunscorch Sands    --
--   slot  5  island3   Fossil Frontier    QUEST  Velociraptor  Rare
--   slot  6  island13  Glacier Gulch      --
--   slot  7  island7   Claw Cliffs       QUEST  Baby Raptor   (RaptorPet again)
--   slot  8  island4   Coastal Crossing   QUEST  Megalodon     Rare
--   slot  9  island10  Petrified Pass     --
--   slot 10  island2   Fern Frontier      QUEST  Triceratops   Epic
--   slot 11  island8   Inferno Isle       --
--   slot 12  island6   Redwood Ridge      QUEST  Velociraptor  (RaptorPet again)
--   slot 13  island11  Volcanic Vista     QUEST  T-Rex         Legendary  <- FINALE
--
-- THE MODEL NUMBER IS NOT THE SLOT. island11 is the summit, island9 is slot 2 -- the
-- numbers are the order the islands were BUILT. Renaming the models in Studio to match
-- the slots was tried and reverted: the code was renumbered, the models were not, and
-- the tower came out with Glacier Gulch on top running the volcano quest, because this
-- loop puts the model literally named island13 into slot 13 while GeyserQuest binds to
-- a model NAME. If you ever do renumber, the Studio rename and the code change must
-- land together, and roughly 340 call sites move with them.
--
-- This header USED to carry its own copy of the order and had drifted out of date
-- twice. It is now a comment ONLY -- IslandOrder is the authority.
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

-- VERBOSE: the per-slot "slot N -> islandN @ (x,y,z)" placement lines. OFF by default --
-- fourteen of them at every boot, and the tower positions are already in IslandOrder if
-- you need to read them. Flip to true when you are actually debugging the layout.
-- (Kept BELOW the require above on purpose: that statement wraps onto a second line, and
-- an earlier pass inserted this flag between the two halves, which silently broke the
-- whole script -- no island got positioned and the tower collapsed to its authored spots.)
local VERBOSE = false
local SLOT_POS       = IslandOrder.SLOT_POS
local SLOT_TO_ISLAND = IslandOrder.SLOT_TO_ISLAND

-- Highest slot that gets an island. DERIVED, never typed: it was hardcoded to 14 while
-- IslandOrder had 14 slots and Workspace had 13 models, so every boot warned
-- "island14 not found (slot 14)" and the top of the tower was empty sky. Reading the
-- ladder's own length makes that impossible -- add or remove a slot in IslandOrder and
-- this follows it.
local TOP_SLOT = IslandOrder.COUNT

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
			if VERBOSE then print(("[IslandLayout] slot %d -> island%d @ (%d, %d, %d)")
				:format(slot, islandNum, pos.X, pos.Y, pos.Z)) end
		else
			warn(("[IslandLayout] island%d move FAILED: %s"):format(islandNum, tostring(err)))
		end
	else
		warn("[IslandLayout] island" .. islandNum .. " not found (slot " .. slot .. ")")
	end
end

_G.islandsPositioned = true
print(("[IslandLayout] %d islands spaced into the tower, bottom to top."):format(TOP_SLOT))

--======================================================================
-- FUTURE: TRUE perfect alternation needs 15 slots, not a reorder.
-- 8 quest islands need 7 blanks to fully separate them; we have 5. Five blanks make
-- six gaps and eight quests into six gaps means two gaps hold two, so two adjacent
-- quest pairs is the FLOOR -- the current order already hits it and no reshuffle can
-- beat it. Build island14 and island15 as BLANKS, insert them at slots 9 and 13, and
-- re-solve FlightTuning for the two extra gaps. Do not add slots without the models:
-- a 14th slot was added once to match the food realm, had no island14 to put in it,
-- and left empty sky above the finale with an unbuyable food.
--======================================================================
