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
-- 13 SLOTS -- one per island MODEL in Workspace, and the whole tower.
--
-- There WAS a 14th ("Summit Spire", model island14), added to match the food realm.
-- This realm only ever had 13 models, so slot 14 was empty sky above the finale and
-- its food could not be bought. Removed rather than modelled: Volcanic Vista is the
-- ending island and it belongs at the top. It cost nothing in pacing -- it removed
-- the LAST crossing, the Colossus Gut's coin wall; the gut is still required for the
-- crossing below it, so all six upgrades stay mandatory. 12 crossings now.
--
-- THE NUMBERS LOOK SCRAMBLED BECAUSE THEY ARE BUILD ORDER, NOT CLIMB ORDER. island11
-- is the summit, island9 is the second slot. DO NOT "FIX" THIS BY RENAMING THE MODELS
-- IN STUDIO. It was tried: the code was renumbered to island<N> = slot <N>, the Studio
-- models were not renamed to match, and the tower came out with Glacier Gulch on top
-- running the volcano quest -- because IslandLayout put the model literally named
-- island13 in slot 13, and GeyserQuest binds to a model NAME. Every quest, NPC, food
-- stand and waypoint keys off the model number, so the two must be renamed in the same
-- breath or not at all. This table is the ONE place the mapping lives; that is the
-- point of it, and it is cheaper than 340 call sites.
--
-- ORDER: PET QUEST / NO QUEST / PET QUEST / ... as closely as 8 quests and 5 blanks
-- allow. Five blanks make six gaps and eight quests into six gaps means two gaps hold
-- two, so EXACTLY TWO adjacent quest pairs is the floor -- no reordering beats it.
-- What the order does do is choose WHICH pairs, and it spends both of them on a
-- duplicate:
--   * NO TWO BLANKS ARE EVER ADJACENT (2, 4, 6, 9, 11 -- all isolated). You are never
--     asked to cross two empty islands in a row.
--   * NO TWO ISLANDS GRANTING A *DISTINCT* PET ARE ADJACENT (1, 3, 5, 8, 10, 13).
--   * Three islands all grant RaptorPet -- Fossil Frontier (dig), Claw Cliffs (nest)
--     and Redwood Ridge (hunt). They are spread to 5, 7 and 12, and the two unavoidable
--     quest pairs (7-8 and 12-13) each contain one, so a doubled-up crossing never
--     hands you two different pets back to back.
--   * Rarity climbs with the tower: Common 1, Common 3, Rare 5, Rare 8, Epic 10,
--     Legendary 13. Misty Mire stays at slot 3 and Fern Frontier high up -- that swap
--     was made by request and this order keeps it.
--
--   slot  1  island1   Nesting Nook       QUEST  Stegosaurus   Common
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
-- Volcanic Vista must stay in the top slot: Rebirth gates on reaching the summit.
-- Nesting Nook must stay at the bottom: it is the spawn island. Both are quest
-- islands, which is exactly why the alternation cannot start or end on a blank.
IslandOrder.SLOT_TO_ISLAND = { 1, 9, 5, 12, 3, 13, 7, 4, 10, 2, 8, 6, 11 }

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
-- ===========================================================================
-- SPACING_SCALE -- the one knob for how far apart the tower is.
--
--   1.00  = the original tower (summit 81,616; you cannot see island 2 from island 1)
--   0.50  = half the distance  (summit 40,883; gap 1->2 = 1,688)
--   0.325 = 65% of that again  (summit 26,626; gap 1->2 = 1,097)  <-- current
--
-- WHY HALVING IS SAFE. Climb distance is
--       climb(max) = (FLIGHT_SECONDS / max) * SUM[ speed * power ]
-- which is LINEAR IN SPEED. So halving the gaps AND halving FlightTuning's speeds
-- scales both sides of every gating check by the same factor: the "no gut reaches the
-- next gap" table above still holds exactly, flights are still 45 seconds, and an
-- island still takes 3-5 attempts. You travel half as far at half the speed, so the
-- pacing is identical -- only the world gets tighter.
--
-- WHAT MUST NOT BE SCALED: the maxPower tiers, coin costs, FLIGHT_SECONDS, DRAIN_RATE
-- and MARGIN. Those are ratios, not distances, and scaling them would change the game.
--
-- FlightTuning.SPACING_SCALE MUST MATCH THIS. FlightTuning warns at runtime if it drifts.
-- Slot 1 stays put at Y=150 and everything above compresses toward it.
-- ===========================================================================
-- ===========================================================================
-- RESCALED TO 0.455 — THE FOOD REALM'S PROVEN SPACING.
--
-- The tower's SHAPE is untouched. Every gap was multiplied by the same 0.455, which is
-- the factor that makes islands 1→13 span 19,995 studs against the Food Realm's measured
-- 19,990 — a 0.03% match on total height. Summit moved 44,099 → 20,145.
--
-- WHY ONE UNIFORM FACTOR AND NOT THE FOOD REALM'S GAPS VERBATIM. Adopting that curve
-- exactly is not a tuning preference, it is ARITHMETICALLY IMPOSSIBLE against this
-- realm's seven gut tiers. Each tier must climb far enough to clear both crossings in its
-- range, and must fall short of the NEXT tier's wall gap or that gut becomes unnecessary.
-- The Food curve dips twice (its gap 8 is shorter than its gap 7, and its gap 12 shorter
-- than its gap 11), which produces two flat contradictions:
--       Trike Gut needs climb ≥ 1839 to clear its own range, and < 1650 to not reach Rex's
--       Titan Gut needs climb ≥ 3268 to clear its own range, and < 3020 to not reach Colossus's
-- No value satisfies either pair. Two guts would silently become unbuyable-because-
-- unnecessary — the exact failure this file's history already records. A uniform factor
-- keeps every one of those relationships intact, because climb is LINEAR IN SPEED: scale
-- the gaps and FlightTuning's climbs together and every gating check holds unchanged.
--
-- WHAT THAT COSTS: individual gaps land between 71% and 112% of their Food counterparts
-- (the early ones shorter, the late ones longer) while the total and the feel match. That
-- residual is the price of keeping twelve crossings walled by twelve gut purchases.
--
-- FlightTuning.SPACING_SCALE MUST MATCH THIS — it warns at runtime if they drift.
-- ===========================================================================
-- ===========================================================================
-- 0.455 -> 0.6825. THE TOWER IS 1.5x TALLER AND THE PROGRESSION IS UNCHANGED.
--
-- Brief: "I like the island progression currently but space the islands out 1.5x, especially
-- the first few." Those two things are only compatible if THREE numbers move together, and
-- this file's own note above says which: gaps, climb, and the coin rate.
--
--   * EVERY VERTICAL GAP x1.5   (the SLOT_POS Y column below)
--   * EVERY TIER'S `climb` x1.5 (FlightTuning.BASE_TIERS) -- because every gate in the game
--     compares a climb against a gap. Scaling gaps alone puts the Hatchling's 569 against a
--     630-stud first gap and THE GAME ENDS AT ISLAND 1: crossing 1 would need 135 power out
--     of a 120 tank. Not "harder" -- arithmetically impossible.
--   * COIN_PER_STUD /1.5, which happens automatically: FlightTuning divides
--     COIN_PER_STUD_BASE by this very constant. Coins are billed per STUD, so a 1.5x taller
--     tower would otherwise pay 1.5x more for the same flight, food prices would not move,
--     and the 93-flight ladder would collapse to roughly 60.
--
-- Because all three scale together every RATIO in the tuning is identical -- required tank
-- fraction per crossing, R, food affordability, the gut walls -- so tools/ladder.py returns
-- the same curve it did before. That is the check, not this comment.
--
-- ONLY Y MOVED. X and Z are deliberately untouched: lateral offset is not in the flight
-- maths at all, and holding it fixed while the climb grows means crossings need the same
-- sideways travel over a longer flight -- i.e. steering gets easier, not harder. Scaling
-- X/Z too would have held the sideways-per-stud-of-climb ratio at its current value, and
-- 4->5 (the worst one, 0.54) is already the crossing that reads as "it took my progress".
-- ===========================================================================
IslandOrder.SPACING_SCALE = 0.6825

-- ===========================================================================
-- THE SOLVED TOWER (14 slots).
--
-- Gaps RAMP INSIDE each gut range rather than being flat. That is the whole reason
-- the second island of a range is not free: the crossing cost has to grow from one
-- island to the next, or the player's savings outrun it and every crossing collapses
-- to a single flight. Capacity is fixed inside a range and food value may never get
-- worse, so the gap is the only thing left that can grow.
--
--   gaps:  552  580 |  828  870 | 1195 1257 | 1655 1740 | 2299 2417 | 3218 3384
--         \-gut1-/  \--gut2--/  \--gut3--/  \--gut4--/  \--gut5--/  \--gut6--/  \gut7/
--   (pre-rescale these read 1213 1275 | 1819 1913 | 2627 2763 | 3638 3825 | 5052 5313 |
--    7073 7438 -- every number below that is quoted in studs and not marked otherwise is
--    from that older, 2.2x taller tower. The RATIOS in the notes are all still exact,
--    because a uniform scale cannot change a ratio; only the absolute figures moved.)
--   (gut7 buys the last crossing and has no second gap -- the 14th slot is gone.)
--
-- THE SPACING CURVE WAS FITTED TO THE FOOD REALM, which plays well. Its 14 islands
-- grow 1.16x per crossing, a 6.0x spread bottom to top; this tower now grows the same
-- way and lands at 6.3x. It USED to be 17.1x -- the top gaps were 20,306 studs against
-- an opening of 1,188, which read as far too much empty sky once you were high up.
-- Only the SHAPE was copied. Absolute size is ~1.9x the food realm's because a flight
-- here is 25 s at 51 studs/sec; matching its absolute gaps as well would mean either
-- halving the speed or halving the flight time.
--
-- TWO CROSSINGS PER GUT, WALLED TWO DIFFERENT WAYS. Six upgrades cannot wall thirteen
-- crossings by purchase alone, so:
--   * The FIRST gap of each pair sits 3% past the previous gut's best flight -- a
--     PURCHASE wall. You must buy the gut. 4-5 flights of saving.
--   * The SECOND is 97% of the CURRENT gut's own full-tank climb -- a COIN wall. It
--     works only because a crossing banks LESS than the next gap's fuel costs. 3 flights.
--
-- GENTLER SPACING MAKES THE COIN WALL HARDER, WHICH IS WHY THE COIN RATE FELL WITH IT.
-- A flatter curve puts a gut's two gaps closer together, so crossing the first earns
-- nearly enough for the second. The governing inequality is
--       (wall gap) x COIN_PER_STUD x (fuel per coin)   <   (fuel the long gap needs)
-- which sits at 0.85 here. At the old 1.6 growth it had far more slack; do not flatten
-- the curve further without re-solving the coin rate with it.
--
-- SIMULATED FLIGHTS PER CROSSING: 5, 6, 5, 6, 4, 5, 4, 6, 3, 7, 4, 6.
-- Minimum 3, max 7, average 5.1 -- and they ALTERNATE by design, because the two wall
-- types feel different:
--   * GUT CROSSINGS (2, 4, 6, 8, 10, 12) run 5-7 flights on a rising ladder. You buy the
--     gut, which leaves you broke holding a tank you cannot fill, so the attempts climb
--     roughly 72% -> 78% -> 83% -> 89% -> 97% -> 100% of the gap.
--   * COIN CROSSINGS (1, 3, 5, 7, 9, 11) run 3-4 flights and start high, around 80%,
--     because you land on them holding a full crossing's pay and nothing to spend it on
--     but food. Short sprints between the long climbs.
-- Measured with scratchpad ladder.py, which models Shop.client's BUY MAX (biggest
-- unlocked food first, walking down from the featured one). vship.py buys only the
-- featured food and so reports 1-3 flights MORE per crossing; trust ladder.py.
--
-- ===========================================================================
-- ONLY SLOT 13 MOVED (44,099 -> 45,972). SLOTS 1-12 ARE THE ORIGINAL TOWER.
--
-- A pass that widened the five upgrade-gated gaps (4->5, 6->7, 8->9, 10->11, 12->13) to
-- spread out their attempt ladders WAS REVERTED, and the reason is worth keeping:
--
--   A crossing pays gap x COIN_PER_STUD. Widening a gap therefore raises what it PAYS, and
--   what it pays is the fuel you arrive at the NEXT island with. Every one of these gaps is
--   immediately followed by a "sprint" crossing that needs ~97% of a full tank (rho 1.031).
--   So the moment a crossing pays a full tank, the sprint after it is a ONE-FLIGHT crossing:
--
--       4->5 gap 1913 pays 0.78 of a Dilo tank -> 5->6 takes 3 flights
--       4->5 gap 2412 pays 0.98 of a Dilo tank -> 5->6 takes 1 flight   <- the regression
--       break-even is gap = 2600/1.056 = 2462 studs
--
--   Every wall gap was swept for a value that keeps BOTH its own crossing and the sprint it
--   feeds above one flight, at 0/25/50/75% coin+gas bubble pickup. NO VALUE EXISTS for any of
--   them: the wall gaps are pinned at their original values by the sprint that follows.
--
-- SLOT 12->13 IS THE ONE EXCEPTION and that is why it is the only gap that moved: it is the
-- LAST crossing, so nothing follows it to be bankrolled. Widened 7438 -> 9311, which spreads
-- the finale's ladder from  71 -> 68 -> 68 -> 82 -> 82 -> 96 -> 96 -> clear  (8 flights,
-- two attempts parked at 96%) to  56 -> 54 -> 54 -> 65 -> 65 -> 77 -> 77 -> 88 -> 88 -> clear
-- (10 flights, nothing past 88%). Headroom 10417/9311 = 1.119, well clear of MARGIN.
--
-- THE DOORSTEP BUNCHING ON THE OTHER CROSSINGS IS NOT FIXED, and cannot be by spacing. The
-- bank grows exactly 10% a flight (R = climb/max * COIN_PER_STUD * fuelPerCoin = 1.100) while
-- one serving is 10% of the tank, so the fill ladder walks 4,5,5,6,6,6,7,7,8 servings and the
-- last failed attempt is always one serving short. Moving gaps only re-labels which serving
-- count clears; it cannot change 1/R. Fixing it needs the coin rate, the serving size, or the
-- speed curve -- all deliberately out of scope.
-- CHANGE THESE AND YOU MUST RE-SOLVE FlightTuning.TIERS.
-- ===========================================================================
-- POST-RESCALE (now x0.6825). X and Z are UNTOUCHED -- the zig-zag spiral is identical to the
-- Food Realm's and was already correct, so only Y moved.
--
--   slot     Y        gap up     was (0.455)   (its gap)
--     1        150        630         150          420
--     2        780       1068         570          712
--     3       1848       1242        1282          828
--     4       3090       1305        2110          870
--     5       4395     1792.5        2980         1195
--     6     6187.5     1885.5        4175         1257
--     7       8073     2482.5        5432         1655
--     8    10555.5       2610        7087         1740
--     9    13165.5     3448.5        8827         2299
--    10      16614     3625.5       11126         2417
--    11    20239.5       4827       13543         3218
--    12    25066.5       5076       16761         3384
--    13    30142.5          -       20145            -
--
-- NOTHING IS ROUNDED ANY MORE. The 0.455 pass rounded to whole studs and got away with it;
-- the 1.5x pass did not -- see the note on the Y column below. Half studs stay half studs.
-- ===========================================================================
IslandOrder.SLOT_POS = {
	Vector3.new(    0,    150,     0),
	-- 702 -> 570. ISLAND 2 MOVED DOWN TO SAVE THE FIRST CROSSING.
	--
	-- Gap 1 was 552 and gap 2 was 580 -- only 5% apart -- which pinned the Hatchling's climb
	-- into a 27-stud window (it must clear 552 but must NOT reach 580, or the Raptor Gut is
	-- free). At climb 569 that made crossing 1 cost 97.2% of the starting tank: the single
	-- hardest crossing in the game, and the first thing a new player ever does.
	--
	-- A requirement that high has only one possible shape: you creep 75% -> 85% -> 100% and
	-- every failure lands 85-95% of the way there. That is arithmetic, not tuning -- no coin
	-- rate, serving size or speed curve can move it while the requirement is 97%.
	--
	-- Dropping island 2 by 132 studs makes gap 1 = 420 (needs 75% of tank) and gap 2 = 712
	-- (needs 84% of the Raptor). The first crossing now reads 65% -> clear on the second try.
	--
	-- NOTHING ELSE MOVES. Islands 3-13 are untouched, so the tower's total span is still
	-- 19,995 and every other gap is unchanged. The gate actually gets SAFER: the Hatchling's
	-- 569 climb now sits 143 studs under gap 2 instead of 11.
	-- ===== Y COLUMN x1.5 EXACTLY -- INCLUDING THE HALF STUDS. DO NOT ROUND THESE. =====
	-- Five of the twelve gaps are odd, so x1.5 lands on .5. Rounding them to whole studs was
	-- tried first and it MOVED THE LADDER: a half-stud shift on gap 10 turned that crossing
	-- from 13 flights into 15 and knocked c11/c12 around with it, because the wallet carries
	-- between crossings and the whole ladder is integer-sensitive (whole servings, whole coins).
	-- At the exact values every flight lands on the SAME percentage of its gap it always did.
	-- gaps: 630 1068 1242 1305 1792.5 1885.5 2482.5 2610 3448.5 3625.5 4827 5076
	-- summit 30,142.5 -- exactly 1.5x the old 19,995 span.
	-- X and Z are the SAME numbers they were -- see the note by SPACING_SCALE.
	Vector3.new(  120,    780,    60),
	Vector3.new( -160,   1848,   100),
	Vector3.new(  180,   3090,  -120),
	Vector3.new( -200,   4395,   160),
	Vector3.new(  220, 6187.5,  -180),
	Vector3.new( -240,   8073,   200),
	Vector3.new(  260, 10555.5, -220),
	Vector3.new( -280, 13165.5,  240),
	Vector3.new(  300,  16614,  -260),
	Vector3.new( -320, 20239.5,  280),
	Vector3.new(  340, 25066.5, -300),
	-- 30142.5 -> 31266.5. THE SUMMIT MOVED UP 1124 STUDS, AND ONLY THE SUMMIT.
	--
	-- The final crossing was designed for 14 flights and playtested at SIX. It is the shortest
	-- leg in the game by a mile, because you arrive at Redwood Ridge rich: a failed flight up
	-- here pays 45-90k against a 6,160 Chicken, so three failures fund a whole tank.
	--
	-- WHY THE SPACING AND NOT THE ECONOMY. Every money lever was measured and every one of them
	-- is a cliff on this crossing, not a slope: cutting slot-12 income by just 15% makes the
	-- crossing UNWINNABLE (30 flights, 29 of them with no visible progress), because one failed
	-- flight there barely funds the next as it is. Raising the Chicken breaks the food ladder
	-- the same way. The gut cost is the only other survivor and it is worth one flight.
	--
	-- WHY THIS IS SAFE WHERE IT WOULD NOT BE ANYWHERE ELSE. Moving an island re-picks which
	-- rung of the climb ladder crosses the line for EVERY crossing above it -- that is what
	-- killed the crossing-3 respacing. Slot 13 is the top of the tower. There is nothing above
	-- it, so this is the one gap in the game that can be widened in isolation.
	--
	-- 6200 needs 94% of a full Colossus, up from 77%. Paired with the 23,000 gut cost this
	-- takes the final crossing from 14 flights to 16 with every check still passing; the gap
	-- alone is worth +1 and the cost alone is worth +1.
	Vector3.new( -360, 31266.5,  320),
}

-- island MODEL number -> display name (island1 = Nesting Nook ... island13 = Glacier Gulch).
IslandOrder.NAMES = {
	"Nesting Nook", "Fern Frontier", "Fossil Frontier", "Coastal Crossing", "Misty Mire", "Redwood Ridge",
	"Claw Cliffs", "Inferno Isle", "Frostbite Flats", "Petrified Pass", "Volcanic Vista", "Sunscorch Sands", "Glacier Gulch",
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
