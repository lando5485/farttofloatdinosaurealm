--[[
	IslandOrder.luau  (ReplicatedStorage.DinosaurRealm.IslandOrder)

	SINGLE SOURCE OF TRUTH for the Dino island TOWER ORDER + display names, shared by the physical layout
	(IslandLayout), progress tracking (PetXPHooks), and the Wormhole (client + service) so they can never
	disagree about which model is where or which is "first"/"last".

	TOWER ORDER: slot 1 = the FIRST island (bottom) ... slot 13 = the SUMMIT / FINAL island. The player climbs
	slots in order, so a slot number IS the climb/progression position.

	QUEST (pet/NPC) islands: 1,2,3,4,5,6,7,11.  Blank scenery islands: 8,9,10,12,13.
	The pattern below alternates QUEST / blank and is arranged so NO 3 quest islands sit in a row:
	  slot: 1  2  3  4  5  6  7  8  9  10 11 12 13
	  isl : 1  9  5  12 3  13 4  2  10 7  6  8  11
	  type: Q  b  Q  b  Q  b  Q  Q  b  Q  Q  b  Q     (max 2 quests adjacent; island6 kept at slot 11 so its
	  server-side raptor rig still grounds correctly; island11 stays the summit finale)

	MISTY MIRE AND FERN FRONTIER ARE SWAPPED, by request: island5 (Misty Mire) took slot 3 and
	island2 (Fern Frontier) took slot 8. Both are QUEST islands, so the Q/b pattern above is
	untouched and the no-3-in-a-row rule still holds -- a swap between two islands of DIFFERENT
	type would not be this cheap and would need the type row re-checked.

	THE SWAP IS NOT DONE HERE ALONE. FoodMenu.LIST is ordered by SLOT and its prices/power are
	solved for the gap and tank size AT THAT SLOT, but each row names the island MODEL that hosts
	the stand -- so rows 3 and 8 had their `island` fields swapped to match. Move an island here
	without doing that and the food stand travels with the model, putting a slot-8 food (power
	240) on slot 3 and a slot-3 food (power 45) on slot 8. That is the exact "power runs
	8 -> 300 -> 25" breakage FoodMenu's own header warns about.
]]

local IslandOrder = {}

-- slot (1..13, bottom -> summit) -> island MODEL number ("island<N>" in Workspace). MUST match IslandLayout.
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 5, 12, 3, 13, 4, 2, 10, 7, 6, 8, 11 }

-- slot -> world position. THE ladder: IslandLayout moves each island here at startup.
--
-- It lives in the shared module rather than in IslandLayout because the CLIENT needs
-- it too and cannot get it from Workspace: with StreamingEnabled a distant island's
-- MODEL replicates but its PARTS do not, and GetPivot() on a partless model returns
-- the origin -- so anything reading island positions off the world sees far islands
-- sitting at Y 0.
--
-- Y is derived from the flight physics (each gap is 92% of a full tank's climb) --
-- see the pacing note in IslandLayout.server.luau before touching any of it.
-- RESPACED once, and now KEPT. The old tower topped out at 39,430 with gaps of
-- 1470..5720, which forced an opening ascent of 8 studs/second -- half walking speed.
-- Speed is distance over time, so widening the gaps is what bought the speed back.
--
-- Gaps run 3375..11743, ONE PER GUT TIER (FlightTuning.TIERS depends on that pairing
-- being 1:1 -- see below). Growth is compressed from 3.9x to 3.5x on purpose: scaling
-- the old gaps uniformly enough to fix the opening speed put the summit at 191,000
-- studs, deep into the float-precision range where parts jitter.
--
-- ONE GAP PER GUT, TWELVE OF EACH. This replaced a PAIRED tower (six gut tiers, two
-- crossings apiece) and the pairing is exactly what the playtest caught: attempts ran
-- 3, 1, 3, 1, 6, 1, 3+ up the tower, alternating. A gut is the WALL that forces saving,
-- so only as many crossings can be walls as there are guts to buy -- with six guts and
-- twelve crossings, six islands were free by construction and no respacing could have
-- fixed it. Twelve tiers in StomachTiers.LIST, twelve gaps here, one wall each.
--
-- EACH GAP IS 12% BIGGER THAN THE LAST, AND THAT NUMBER IS LOAD-BEARING. A full tank
-- climbs its own gap x MARGIN (1.08), so a gut is locked out of the next tier only if the
-- gap grows by MORE than 8%. An earlier pass grew 10.1 / 9.0 / 8.4 / 7.6 / 7.2 -- the last
-- two fell under the line, which quietly made two guts unnecessary rather than unbuyable:
-- Bronto's 4740 already cleared the 4725 Rex gap. 12% clears 8% at every step.
--
--   slot 1-2    3375     slot 5-6    5311     slot  9-10   8359
--   slot 2-3    3780     slot 6-7    5949     slot 10-11   9362
--   slot 3-4    4234     slot 7-8    6663     slot 11-12  10485
--   slot 4-5    4742     slot 8-9    7463     slot 12-13  11743
--
-- NO GUT REACHES THE NEXT GAP -- the check that makes the shop mandatory rather than
-- optional. Full-tank climb (= gap x 1.08) against the gap AFTER it:
--     3645 < 3780   5121 < 5311   7196 < 7463    9028 <  9362
--     4082 < 4234   5736 < 5949   8060 < 8359   10111 < 10485
--     4573 < 4742   6425 < 6663                 11324 < 11743
--
-- The uniform-6000 version two revisions back made every crossing identical, which also
-- made every gut pointless: a Hatchling full tank climbed 6480 and every gap was 6000, so
-- the starting gut cleared the entire tower and nothing in the shop bought you anything.
--
-- Sized for a 45-SECOND flight (FlightTuning.FLIGHT_SECONDS), so 3-5 attempts at an island
-- lands around the 3 minutes asked for rather than one 3-minute drift.
--
-- Summit is 81,616. Taller than the 59,236 it replaces because twelve compounding steps
-- reach further than six, and still well clear of the range where float precision makes
-- parts jitter (~100k+).
--
-- CHANGE THESE AND YOU MUST RE-SOLVE FlightTuning.TIERS. The band speeds are the solution
-- to these exact gaps and nothing will warn you if they drift apart.
IslandOrder.SLOT_POS = {
	Vector3.new(   0,   150,    0),
	Vector3.new( 120,  3525,   60),
	Vector3.new(-160,  7305,  100),
	Vector3.new( 180, 11539, -120),
	Vector3.new(-200, 16281,  160),
	Vector3.new( 220, 21592, -180),
	Vector3.new(-240, 27541,  200),
	Vector3.new( 260, 34204, -220),
	Vector3.new(-280, 41667,  240),
	Vector3.new( 300, 50026, -260),
	Vector3.new(-320, 59388,  280),
	Vector3.new( 340, 69873, -300),
	Vector3.new(-360, 81616,  320),
}

-- island MODEL number -> display name (island1 = Nesting Nook ... island13 = Glacier Gulch).
IslandOrder.NAMES = {
	"Nesting Nook", "Fern Frontier", "Fossil Frontier", "Coastal Crossing", "Misty Mire", "Redwood Ridge",
	"Raptor Ridge", "Inferno Isle", "Jungle Junction", "Petrified Pass", "Volcanic Vista", "Sunscorch Sands", "Glacier Gulch",
}

-- QUEST (pet/NPC) islands, by MODEL number — used only for documentation / potential UI hints.
IslandOrder.QUEST = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [11] = true }

-- derived inverse: island MODEL number -> slot (climb position).
IslandOrder.ISLAND_TO_SLOT = {}
for slot, islandNum in ipairs(IslandOrder.SLOT_TO_ISLAND) do
	IslandOrder.ISLAND_TO_SLOT[islandNum] = slot
end

IslandOrder.COUNT = #IslandOrder.SLOT_TO_ISLAND

return IslandOrder
