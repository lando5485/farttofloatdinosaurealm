--======================================================================
-- FlightTuning.luau  (ModuleScript -> ReplicatedStorage/DinosaurRealm)
--======================================================================
-- THE FLIGHT MATH, kept in one place because BottomHUD.client (burns the tank) and
-- Shop.server (fills it) must agree, and IslandOrder owns the gaps both are tuned
-- against. Two copies of "how long is a flight" is how a shop starts selling a tank
-- that does not reach.
--
-- THE MODEL IS THE SPACE REALM / FART-TO-FLOAT ONE, UNCHANGED IN SHAPE:
--   gasMeter  = (CurrentPower / StomachMax) * 100      -- normalised 0..100
--   every frame:  gasMeter -= DRAIN_RATE * dt
--                 CurrentPower = (gasMeter/100) * StomachMax
--   riseSpeed = getFlightSpeed(CurrentPower)            -- BANDS, by CURRENT power
--   BodyVelocity.Y = riseSpeed
--
-- The band lookup reads the power that is DRAINING, so a flight starts in the top
-- band its gut can reach and steps DOWN through every band beneath it as the tank
-- empties. That taper is the mechanic and it is preserved here.
--
-- WHAT CHANGED: only DRAIN_RATE and the band speeds. The reference runs 3.5 gas/sec
-- -- a full tank is 28.6 seconds -- which is where the ~30 second legs came from.
-- A 3-3.5 minute leg was tried and played badly: two attempts at an island is six and
-- a half minutes of holding one button, and at 33 studs/sec the island overhead never
-- appears to move. The leg is now ONE MINUTE and the bands are re-solved against the
-- SAME gaps, which is a straight 3.25x on every speed.
--
-- WHY THE GAPS DID NOT CHANGE TOO
-- A leg has to clear its whole gap in one tank. Running dry destroys the BodyVelocity
-- (BottomHUD's flight loop) and there is nothing between islands to land on, so a
-- flight that ends early does not bank its altitude -- you fall back to the island you
-- launched from. "Half the gap per tank" would therefore not be two short hops, it
-- would be an unwinnable island. Shortening the TANK is the only lever that makes a
-- leg quicker without stranding anyone; a genuine multi-hop needs mid-gap platforms.
--
-- WHY THE BANDS ARE SOLVED, NOT GUESSED
-- With a tapering speed the climb is not speed x time; it is the integral of the
-- band speeds over the time spent in each. Gas falls linearly, so for a gut of size
-- M the flight spends
--       t_j = FLIGHT_SECONDS * (M_j - M_(j-1)) / M     seconds in band j
-- and the total climb is
--       climb(M_k) = (FLIGHT_SECONDS / M_k) * SUM_j[ v_j * (M_j - M_(j-1)) ]
-- Requiring climb(M_k) = gap_k * MARGIN for every tier gives a triangular system
-- with exactly one solution, which is the BANDS table below. Hand-editing one row
-- silently breaks every tier above it -- re-run the solve instead.
--======================================================================

local FlightTuning = {}

-- 80 s of thrust on a full tank, for EVERY gut. The meter is normalised, so tank SIZE
-- does not change how long you fly -- it changes how fast, and so how far.
--
-- This is THE pacing dial. Everything below is solved from it: halve it and every
-- band speed doubles, because the same gap still has to be climbed in the time left.
--
-- 195 was a slog, 60 read as slightly too brisk. 80 is the settled value. Note that a
-- LEG is not a CROSSING: you launch on a part-full tank most of the time, and a tank
-- that is 40% full burns for 40% of this, so the early attempts at an island are much
-- shorter than 80 s. See the `foods` note in Shop.server for how many attempts that is.
-- 45 s of thrust on a full tank. Sized from the OTHER end than every previous pass: the
-- brief is ~3 minutes to clear an island in 3-5 attempts, so one attempt is 180/4 = 45,
-- not 180. A single 3-minute flight was the thing that read as a slog.
-- 25 s of thrust on a full tank, HALVED from 50 as part of a straight speed-up.
--
-- SPEED IS DISTANCE OVER TIME, so there are only three ways to make the player move
-- faster: shorten the flight, lengthen the gaps, or both. At 50 s and 20 studs/sec the
-- opening flight was barely above walking speed (16) and read as a crawl. The fix was
-- applied as ONE coherent rescale:
--     FLIGHT_SECONDS  50 -> 25     (halved)
--     every band speed  x2.5
--     every gap         x1.25      (IslandOrder.SLOT_POS)
--     COIN_PER_STUD     /1.25      (both clients)
-- Climb is (FLIGHT_SECONDS / M) * SUM[v * dM], so halving the time and multiplying the
-- speeds by 2.5 multiplies every climb by exactly 1.25 -- which is what the gaps did too.
-- Every wall, every flight count and the whole economy therefore survive UNCHANGED; the
-- player just covers a 25% bigger tower 2.5x faster in half the time.
--
-- Coins are billed per STUD, so the tower growing 25% would have inflated income by 25%
-- if COIN_PER_STUD had not been divided by the same factor. That is why it moves too.
-- ===========================================================================
-- 11.375 = 25 x 0.455. THE FLIGHT GOT SHORTER, NOT SLOWER.
--
-- When the tower was compressed to the Food Realm's spacing, `climb` scaled with it and
-- this was left at 25 -- which held every crossing at the same NUMBER OF SECONDS by
-- dropping the opening flight from 50 studs/sec to 22.8, barely above the 16 stud walking
-- speed. That was the wrong half of the trade to keep.
--
-- Speed is climb / FLIGHT_SECONDS, so scaling BOTH by 0.455 leaves every band speed
-- EXACTLY where it was before the compression -- 50 / 75 / 108 / 150 / 208 / 292 / 417
-- studs/sec across the seven guts -- and simply makes each flight shorter. A full tank now
-- burns in 11.4 s instead of 25 and covers a proportionally shorter, proportionally closer
-- gap at the same velocity.
--
-- NOTHING IN THE GATING MOVES. Every wall check compares a DISTANCE (climb) against a
-- DISTANCE (gap), and neither changed here. Attempts per island, gut costs, food prices and
-- coins per crossing are all untouched: coins are billed per STUD, not per second.
--
-- WHAT THIS DOES CHANGE is that everything happens ~2.2x sooner in wall-clock, so every
-- per-second rate elsewhere -- hazard spawn intervals, bubble respawns, pet XP ticks, the
-- gas-grant rate limiter -- had to be multiplied by 0.455 to keep the same amount of stuff
-- happening per crossing. Those are listed in the rescale report.
-- ===========================================================================
-- ===========================================================================
-- 15.1667 = 11.375 / 0.75. THE FLIGHT GOT SLOWER, AND THE TOWER DID NOT MOVE.
--
-- Speed is climb / FLIGHT_SECONDS. The brief was "25% slower", and the ONLY safe way to do
-- that is to lengthen the flight rather than shorten the climb:
--       scale THIS by 1/0.75  ->  every band speed drops 25%, `climb` is untouched
--       scale `climb` by 0.75 ->  every band speed drops 25%, AND THE TOWER BREAKS
-- The second one is the trap. Every gate in this file compares a climb against a gap, so
-- cutting climb 25% puts the Raptor at 640 against an 828-stud gap and slots 3, 5, 7, 9, 11
-- and 13 become physically unreachable -- the game would end at island 2.
--
-- Because `climb` did not move, NOTHING else here had to: gaps, gut gates, tank sizes, food
-- prices, gut costs, R, the flight-count ladder and every affordability check are all
-- untouched. A flight simply takes 33% longer to cover the same distance.
--
-- IT ALSO HALVES THE FREE COAST. When thrust ends the character keeps its upward velocity
-- and coasts v^2/2g further on no fuel at all -- which a player can farm by tapping the
-- fart button repeatedly instead of buying a real tank. That coast scales with the SQUARE of
-- speed, so a 25% cut takes 44% off it (Colossus 495 -> 279 studs). A playtest showed 12
-- consecutive 9-11% "flights" chain-tapping across the slot 10 gap; this is most of that fix.
--
-- WHAT THIS DOES CHANGE is wall-clock: everything now takes 33% longer, so every per-second
-- rate elsewhere (hazard spawns, bubble respawns, pet XP ticks, weather intervals) now fires
-- 1.33x more often per crossing than it used to. Those were last scaled for 11.375.
-- ===========================================================================
-- ===========================================================================
-- 22.75 = 15.1667 x 1.5, MOVED WITH THE RESPACING TO PROTECT THE FLIGHT SPEED.
--
-- Speed is climb / FLIGHT_SECONDS and the respacing multiplied `climb` by 1.5. Leaving this
-- at 15.1667 would therefore have made every band 50% FASTER -- silently undoing the "25%
-- slower" pass above, which was an explicit request. Scaling this by the same 1.5 keeps every
-- band speed EXACTLY where it is (35-330 studs/sec across the seven guts); the flight simply
-- lasts longer because it has further to go.
--
-- IT ALSO PROTECTS THE GUT WALLS. The free ballistic coast is v^2/2g, so it depends on speed
-- and NOT on distance. Holding speed fixed leaves the coast unchanged in studs while the gaps
-- grew 1.5x -- so the coast shrinks by a third AS A SHARE OF A GAP and every wall gets safer.
-- Had speed gone up 1.5x instead, the coast would have grown 2.25x (1.5x as a share of a gap)
-- and reopened the chain-tap hole that COAST_DAMPING exists to close.
--
-- WHAT IT COSTS: wall-clock. A full-tank flight is now ~22.8s of thrust instead of ~15.2s, and
-- a failed flight's fall home is 1.5x further too. Every per-second rate elsewhere (hazard
-- spawns, bubble respawns, pet XP ticks, weather intervals) therefore fires ~1.5x more often
-- per crossing than it used to -- the same caveat the 0.455 and 0.75 passes carried.
-- ===========================================================================
FlightTuning.FLIGHT_SECONDS = 22.75

-- How far a full tank overshoots the gap it is tuned for. Keeps the reference's
-- "each island sits at ~92% of a full tank" tension: gas spent steering can still
-- cost you the landing.
FlightTuning.MARGIN = 1.08

-- COINS PAID PER STUD CLIMBED, before the spacing divide. THE ONE COPY.
--
-- It lived as a literal in THREE files -- BottomHUD (which pays the climb), Bubbles (which
-- prices a coin bubble as a fraction of what a flight pays) and BalanceDebug (which reports
-- it) -- and they had drifted: the first two ran 1.16160 while the debug printed 1.056, so
-- every balance table this realm has produced understated the coin rate by 10% and a tuning
-- pass was very nearly made against the wrong number. All three now read this.
--
-- Divide by SPACING_SCALE at the point of use, as BottomHUD does: the tower was compressed
-- x0.455 but the prices it was solved against were not, so a flat rate would pay out
-- proportionally less at every spacing. 1.911 / 0.455 = 4.200 coins per stud.
--
-- 0.637 / 0.455 = 1.400 coins per stud. CUT FROM 4.200 WHEN THE DESCENT STARTED PAYING --
-- see DESCENT_PAY_MULT directly below. A failed flight now earns MORE than it used to; only
-- a successful crossing earns less, and that asymmetry is the entire point.
-- 0.6006 / 0.455 = 1.320 coins per stud. TRIMMED FROM 1.400 TO LENGTHEN THE TOWER.
--
-- This is the flight-count dial and it is EXTREMELY sensitive -- do not nudge it casually.
-- Every crossing's try count is 1 + log(1/start) / log(R), and R is directly proportional to
-- this number, so a 5% cut here is not a 5% change in pacing. Measured, holding everything
-- else fixed:
--       1.41 -> 60 flights      1.36 -> 73
--       1.40 -> 73 flights      1.33 -> 90
--       1.39 -> 70 flights      1.32 -> 93   <== shipped
--       1.38 -> 69 flights      1.31 -> 98
-- It is not monotonic in the small, because try counts are integers and the ladder's last
-- rung either clears the gap or does not. Re-run tools/ladder.py after ANY change here; do
-- not reason about it by hand.
-- x8 DENOMINATION RESCALE. The brief was "the top free gut should be 20k or more".
-- A gut price only means anything against the income that buys it, so the rate, every food
-- price, every gut cost and the starting bank were ALL multiplied by 8 together. Every ratio
-- in the game is therefore untouched -- the flight ladder comes out bit-identical at 93 --
-- and the numbers on screen are simply eight times bigger. 0.6006 -> 4.8048.
FlightTuning.COIN_PER_STUD_BASE = 2.4024

-- ===== COINS ARE PAID FOR DISTANCE TRAVELLED, NOT HEIGHT GAINED =====
-- A failed flight climbs d and falls back down d: it travelled 2d, and the fall pays this
-- multiple of the climb rate. A successful crossing climbs the gap and never falls, so it
-- collects the climb alone.
--
-- WHY THIS EXISTS, because it is not decoration. How many flights a crossing takes is
--       start = (what the last crossing paid you) / (what this crossing costs)
-- and substituting R collapses that to
--       start = 0.726 x R x (rate a LANDING pays / rate a FAILED flight pays)
-- R is built out of failed flights -- they are the ones you repeat -- while the bank you
-- arrive with is built out of the ONE successful flight. Those are two different rates, and
-- before this they were equal purely by accident: coins were paid per stud climbed either
-- way, so the ratio was 1 and the whole term vanished.
--
-- That vanished term is why crossings 3, 5, 7, 9 and 11 were stuck. No gut is bought at
-- those slots, so nothing drains the bank and `start` was pinned at 0.726 x R -- about 86%
-- of the crossing, i.e. TWO flights, and no amount of food pricing, tank sizing or coin rate
-- could move it (they all cancel). Paying the descent is the one lever that does, and it
-- costs no new guts, no spacing change and no speed change.
--
-- 2.0 is the tuned value: it lands those five crossings at 4-7 flights instead of 2 while
-- keeping every last miss at or under 84%. 1.0 flattens them to 4-5; 2.5 gives a smoother
-- rise but spikes crossing 2 to seven. Re-run tools/ladder.py if you move it.
--
-- IT ALSO FIXES A FEEL PROBLEM. A failed attempt used to pay for the climb and nothing for
-- the long fall home. In a progression that is deliberately 3-9 flights per island, the
-- failures ARE the gameplay, and they should pay.
--
-- CAPPED AT THE LAUNCH ALTITUDE, or this is a coin printer: without the cap a player could
-- dive from the summit to island 1 and be paid for 20,000 studs. You are only ever paid for
-- coming back down what you just went up.
FlightTuning.DESCENT_PAY_MULT = 2.0

-- SPACE REALM'S DRAIN MODEL, copied exactly (StomachTiers.luau / FlightClient):
--     the 0-100 meter drains at 100 / tankSeconds per second for the EQUIPPED tier,
--     so raw drain = StomachMax / tankSeconds and a full tank lasts tankSeconds.
-- There, tankSeconds RISES with tier (28 -> 58s) so bigger guts burn longer AND
-- climb farther. Here every tier gets the SAME tankSeconds, because the brief is a
-- constant leg length at every tier: distance is bought with speed instead.
FlightTuning.TANK_SECONDS = FlightTuning.FLIGHT_SECONDS

-- ===== HOW LONG A TANK BURNS, PER GUT. THE WALL-CLOCK DIAL. =====
-- The note above says every tier gets the SAME tankSeconds. That is no longer true above
-- the Raptor, and this is the seam that changed it -- the hook always took a stomachMax,
-- it just ignored it.
--
-- WHY. A measured full run came in at 35 minutes against a 45-50 minute brief. The flight
-- LADDER was already right (94 flights flown against a designed 93), so the shortfall was
-- never the amount of work -- it was that one flight cycles in ~22 s. The only honest fix
-- is to make a flight take longer, and the only two other levers were tested and are dead:
-- raising gut costs stalls 26-38 flights, raising food prices breaks the value ladder and
-- stalls 85. Both were measured, not guessed.
--
-- WHY IT IS SAFE. Speed is climb / tankSeconds, so scaling the time and dividing the band
-- speeds by the same factor leaves `climb` EXACTLY where it was. Nothing that gates the
-- tower reads a duration: climbFor() and powerForClimb() are written as tier.climb x a
-- shape fraction with no FLIGHT_SECONDS in them at all, so every gap, gut gate, shop check
-- and flight count survives untouched. A flight simply covers the same distance slower.
--
-- WHY THE FIRST TWO GUTS ARE 1.00. Crossings 1-3 fly on the Hatchling and the Raptor at
-- 37.5 and 56.2 studs/sec. Walking is 16. Slowing the opening of the game is exactly the
-- trade this file has already regretted twice (see the 0.455 and 0.75 notes above), so the
-- bottom of the tower keeps its pace and the slowdown is spent where flights are long
-- enough to absorb it.
-- NOTHING IS CUT MORE THAN 1.60, AND THE TOP GUT IS NOT THE DUMP. A first pass ramped the
-- factor UP with tier and ended at 1.90 on the Colossus, taking it from 312 to 164 studs/s
-- -- a 47% cut on the gut the player worked the whole tower for, which read as a punishment
-- for buying it. The load is now shared: the Titan pair carries the most because crossings
-- 10-11 are simply the longest legs in the game (6.5 minutes of flight between them), not
-- because bigger guts deserve a bigger tax.
--
-- 1.60 IS THE CEILING AND 45 MINUTES IS THE FLOOR, AND THEY MEET ALMOST EXACTLY. Speed is
-- climb / time, so these are one number, not two: a gut cannot fly longer AND as fast. With
-- crossings 1-3 held at 1.00 the rest of the tower has to stretch ~1.5x on average to clear
-- 45 minutes, which is why nothing here can be much gentler without dropping under the floor.
-- Raising any factor buys wall-clock and costs speed at exactly the same rate.
--
-- THE ONE HARD CONSTRAINT IS THAT SPEED MUST STILL RISE WITH EVERY GUT. The Raptor is fixed
-- at 56.2, so the Dilo can never go past 1.44 or a paid upgrade would fly SLOWER than the
-- gut before it. That is what caps the bottom of this ramp, not taste.
local TIER_TIME = {
	{ 120 , 1.00 },   -- Hatchling  crossing 1        37.5 studs/s  (unchanged)
	{ 270 , 1.00 },   -- Raptor     crossings 2-3     56.2          (unchanged)
	{ 470 , 1.35 },   -- Dilo       crossings 4-5     81.2 ->  60.1
	{ 620 , 1.50 },   -- Trike      crossings 6-7    112.5 ->  75.0
	{ 1080, 1.55 },   -- Rex        crossings 8-9    156.3 -> 100.8
	{ 1710, 1.60 },   -- Titan      crossings 10-11  218.8 -> 136.8
	{ 2600, 1.60 },   -- Colossus   crossing 12      312.5 -> 195.3
}

-- Anything bigger than the last row (the Primal Gut at 9999) takes the last row's factor.
function FlightTuning.timeScaleFor(stomachMax: number): number
	local max = tonumber(stomachMax) or 0
	for _, row in ipairs(TIER_TIME) do
		if max <= row[1] then return row[2] end
	end
	return TIER_TIME[#TIER_TIME][2]
end

function FlightTuning.tankSecondsFor(stomachMax: number): number
	return FlightTuning.TANK_SECONDS * FlightTuning.timeScaleFor(stomachMax)
end

-- gas/sec on the normalised meter. Space Realm's is 100/28 = 3.57 at tier 1.
FlightTuning.DRAIN_RATE = 100 / FlightTuning.TANK_SECONDS  -- 1.25 (was 0.513 at 195s)

-- GUT TIER -> THE GAP IT OPENS. ONE TIER PER CROSSING: twelve gut sizes, twelve gaps,
-- and row k here is the crossing from slot k to slot k+1 in IslandOrder.SLOT_POS.
--
-- IT USED TO BE SIX ROWS FOR TWELVE CROSSINGS (gaps in pairs, two per gut). That pairing
-- is what made half the tower free -- a gut is the wall that forces saving, so six guts
-- could only ever wall six of the twelve crossings, and the playtest read 3, 1, 3, 1, 6, 1
-- attempts straight up the ladder. Doubling the tiers is the fix; the gaps alone could
-- never have been.
--
-- THE maxPower COLUMN MUST EQUAL StomachTiers.LIST's, ROW FOR ROW. It is not a copy for
-- convenience -- the band widths ARE those numbers, so a tank size that exists in the shop
-- and not here lands mid-band and climbs the wrong distance, silently.
--
-- EVERY TANK CARRIES +10, AND THE SPEEDS DELIBERATELY DID NOT MOVE WITH IT. The brief was
-- "hold ten more, change nothing else" -- so this is capacity only. The speeds are still
-- the solve for the ORIGINAL 100/140/190/260/355/485/665/910/1250/1715/2350/3220 sizes,
-- and the food prices and gut costs are still the ones derived against them.
--
-- What that costs, exactly: the last 10 power of every tank now burns in the tier's TOP
-- band instead of being spread across the solve, so a full tank climbs a hair less than
-- gap x MARGIN. Effective margin lands at ~1.072 instead of 1.080. Full-tank climb against
-- the gap it must clear:
--     Hatchling  110 -> 3645  needs 3375      Bronto     675 ->  7143  needs  6663
--     Raptor     150 -> 4053  needs 3780      Spino      920 ->  8012  needs  7463
--     Dilo       200 -> 4526  needs 4234      Rex       1260 ->  8985  needs  8359
--     Stego      270 -> 5066  needs 4742      Ptero     1725 -> 10074  needs  9362
--     Anky       365 -> 5678  needs 5311      Fossil    2360 -> 11291  needs 10485
--     Trike      495 -> 6368  needs 5949      Titan     3230 -> 12654  needs 11743
--
-- Every tier still clears its own gap with room to spare, so nothing became uncrossable.
--
-- AND EACH ONE STILL FALLS SHORT OF THE NEXT GAP, which is what makes the shop mandatory
-- rather than optional -- 3645 < 3780, 4053 < 4234, 4526 < 4742, 5066 < 5311, 5678 < 5949,
-- 6368 < 6663, 7143 < 7463, 8012 < 8359, 8985 < 9362, 10074 < 10485, 11291 < 11743.
-- That is the check to re-run if the +10 ever becomes +50: it is the slack between MARGIN
-- (8%) and gap growth (12%) that is absorbing this, and it is not unlimited.
--
-- An earlier attempt kept ~8% gap growth and TWO of those comparisons came out the wrong
-- way, which silently made two guts unbuyable-because-unnecessary. Gap growth has to beat
-- MARGIN, everywhere, or the wall it was supposed to build is not there.
-- ===========================================================================
-- SPACING_SCALE -- MUST MATCH IslandOrder.SPACING_SCALE. Checked at runtime below.
--
-- Climb is LINEAR IN SPEED (see the integral at the top of this file), so scaling the
-- gaps and the speeds by the SAME factor leaves every relationship in this file intact:
-- the "no gut reaches the next gap" table still holds, flights are still FLIGHT_SECONDS
-- long, and islands still take 3-5 attempts. Only the world gets tighter.
--
-- maxPower, costs, FLIGHT_SECONDS, DRAIN_RATE and MARGIN are deliberately NOT scaled --
-- they are ratios and time, not distance. Scaling them would change the game.
-- ===========================================================================
-- 0.455 -- the tower was rescaled to the Food Realm's proven spacing. See the long note in
-- IslandOrder.luau for why one uniform factor rather than the Food curve verbatim (short
-- version: that curve dips twice, which makes two gut tiers arithmetically impossible).
--
-- BOTH SIDES OF EVERY CHECK IN THIS FILE MOVED TOGETHER. Climb is linear in speed, so the
-- gaps AND the `climb` column below were multiplied by the same 0.455. The consequence is
-- that nothing else here had to change: MARGIN, FLIGHT_SECONDS, DRAIN_RATE, SPEED_SHAPE,
-- COURTESY_FRACTION and every maxPower are ratios or time, not distance.
-- 0.455 -> 0.6825 (x1.5). MUST MATCH IslandOrder.SPACING_SCALE -- the full reasoning for the
-- respacing lives there. What it does HERE is one thing: COIN_PER_STUD_BASE is divided by this
-- at the point of use, so the coin rate drops 1.32 -> 0.88, exactly cancelling the 1.5x longer
-- distances. Every flight therefore pays the same coins it paid before, food prices never move,
-- and the flight ladder is untouched.
FlightTuning.SPACING_SCALE = 0.6825

-- SEVEN COIN TIERS, ONE PER GUT RANGE. Each gut covers TWO crossings (a wall crossing
-- and a longer one), not one -- so `gap` below names the SECOND (larger) gap of its
-- range. It is documentation only; nothing reads it. gapFromSlot() measures the real
-- distance off IslandOrder.SLOT_POS.
--
-- SPEEDS ARE SOLVED, NOT CHOSEN. They are the unique values making
--     fullTankClimb(M_j) == D_j     with D = 1150 * 1.60^j  and  M below,
-- i.e. climb growth 1.60x per tier against capacity growth 1.70x. Climb growth must
-- EXCEED the crossing profit ratio (1.16) or savings outrun the next crossing and every
-- island collapses to one flight.
--
-- CAPACITIES ARE ALL MULTIPLES OF 10 ON PURPOSE. Food is sold in 10 servings per tank;
-- if M/servingPower is not exactly 10 the integer serving count truncates (289/28.9 =
-- 9.9999 -> 9 servings) and the tank can NEVER be filled. Keep them divisible.
-- SEVEN TIERS, TWO CROSSINGS EACH (the first covers only slot 1->2). `gap` names the WALL
-- gap of the range -- the first of the two, the one the previous gut cannot reach.
--
-- SPEEDS ARE SOLVED, NOT CHOSEN. They are the unique solution of the triangular system
--     fullTankClimb(M_k) == D_k      with  D_k = 1000 * 1.45^k
-- against the capacities below (growing 1.28x). Climb growth 1.45x EXCEEDS capacity growth
-- 1.28x on purpose: that difference is what makes the upper speed bands so much faster than
-- the lower ones, and that contrast is load-bearing -- see below.
--
-- THE BAND CONTRAST IS WHAT WALLS THE SECOND CROSSING OF EACH RANGE. Climb is convex in
-- fuel (higher bands are faster), so the two gaps in a range need very different fills:
-- the wall gap needs ~72% of the tank and the long gap ~96%. The coins banked crossing the
-- first therefore cannot buy the fuel for the second, and that is the ONLY thing stopping
-- the second crossing from being a free single flight. Flatten these speeds toward each
-- other and that wall silently disappears.
--
-- CAPACITY GROWTH MUST STAY UNDER THE FULL-TANK RETURN. Buying a gut divides your
-- coins-per-fuel by the capacity ratio until you can afford to fill past your old cap, so
-- 1.28x growth against a 1.85 return leaves ~1.42 right after a purchase. Push growth past
-- the return and that number goes under 1: every flight after an upgrade loses coins, you
-- can only afford part-tanks, and you bleed out. A previous pass ran 1.70x growth against
-- a 1.16 return -- 0.68 -- and stalled the tower dead at island 3.
--
-- EVERY TANK IS EXACTLY 12 SERVINGS of its range's food (maxPower = 12 x food power), so a
-- tank always fills exactly. Derive the capacity FROM the serving, never the other way: an
-- earlier pass rounded the serving off the capacity and left three guts holding 11 servings,
-- so those tanks could never be filled and their gaps could never be crossed.
--
-- Hand-editing one row silently breaks every tier above it -- re-run the solve instead.
-- `climb` IS WHAT A FULL TANK OF THIS GUT TRAVELS. It replaced a per-tier `speed`, and
-- that swap is the whole fix for "the player slows down halfway through the flight".
--
-- THE OLD MODEL: bands were ABSOLUTE slices of raw fuel, and the speed lookup took the
-- draining power alone. Fuel below 120 flew at 50 studs/sec on EVERY gut, because band 1
-- was 0-120 whatever tank you owned. So the tail of every flight crawled at the STARTING
-- gut's speed: a Colossus flight opened at 669 studs/sec and finished at 50 -- a 13x
-- deceleration, and the last ~6 seconds of every single flight were at walking pace.
-- Worse, it got worse the more you upgraded, so the reward for a 7,720-coin gut was a
-- longer crawl.
--
-- THE NEW MODEL: bands are FRACTIONS OF YOUR OWN TANK (see SPEED_SHAPE), scaled by this
-- number. The profile is identical in shape at every tier, so the floor rises with the
-- gut instead of staying pinned at 50. Colossus now runs 432 -> 270 rather than 669 -> 50.
--
-- WHY THE TAPER CANNOT SIMPLY BE REMOVED: it is load-bearing. A tapering speed makes climb
-- CONVEX in fuel, and that convexity is exactly what makes the second crossing of each gut
-- range cost far more fuel than the first -- the "band wall" that keeps those crossings off
-- 1 flight (see StomachTiers.luau). Flatten the curve completely and every un-purchased
-- crossing collapses to a single flight. SPEED_SHAPE's contrast is the dial, and 1.6 is the
-- gentlest setting that still holds the wall; it was solved, not chosen.
--
-- These climb values are UNCHANGED from the previous solve, so every gap, price, gut cost
-- and wall margin carried over untouched -- only the shape of the speed within a flight moved.
-- `gap` names the WALL gap of each gut's range -- the crossing the PREVIOUS gut cannot make.
-- Re-synced with IslandOrder.SLOT_POS after the overshoot fix (see the long note there).
-- `climb` and `maxPower` are UNCHANGED: the speed ladder, FLIGHT_SECONDS, DRAIN_RATE, the
-- food table, the gut prices and COIN_PER_STUD all stayed exactly where they were.
-- RESCALED x0.455 WITH THE TOWER. `gap` and `climb` are both distances and both moved;
-- `maxPower` did not, because it is fuel. Every check below was re-verified after the
-- rounding to whole studs:
--
--   no gut reaches its successor's wall gap -- the check that keeps all six mandatory:
--       569 < 580    853 < 870    1232 < 1257    1706 < 1740    2370 < 2417    3318 < 3384
--   (slack 11, 17, 25, 34, 47, 66 -- all positive, all in the same proportion as before)
--
--   every gut still clears the LONGER of the two crossings in its own range, at margin
--   1.031 for tiers 1-6 and 1.401 for the Colossus (which has only one crossing left):
--       569/552  853/828  1232/1195  1706/1655  2370/2299  3318/3218  4740/3384
--
--   climb/gap per tier, before -> after: 1.0305 -> 1.0308, 1.4706 -> 1.4707,
--   1.4156 -> 1.4161, 1.3572 -> 1.3572, 1.3616 -> 1.3621, 1.3725 -> 1.3728,
--   1.4005 -> 1.4007. Worst drift +0.0005, entirely from rounding to whole studs.
--
-- Pre-rescale these rows read gap 1213/1275/1913/2763/3825/5313/7438/12000 and climb
-- 1250/1875/2708/3750/5208/7292/10417/18000.
-- ===== CAPACITY NO LONGER TRACKS CLIMB, AND THAT IS THE ATTEMPTS RAMP =====
--
-- `climb` and `gap` below are UNTOUCHED -- they are the speed ladder and the tower, and
-- neither may move. `maxPower` is the free column, and it now grows FASTER than climb:
--
--        tank    climb   climb/tank   food eff   R = eff x 4.20 x climb/tank
--         120      569       4.74       1.00x       1.99
--         290      853       2.94       1.15x       1.42
--         500     1232       2.46       1.30x       1.35
--         820     1706       2.08       1.45x       1.27
--        1300     2370       1.82       1.60x       1.23
--        2050     3318       1.62       1.80x       1.22
--        3070     4740       1.54       2.00x       1.30
--
-- (the 4.20 is 1.400 x (1 + DESCENT_PAY_MULT): a repeated flight earns the climb AND the
--  fall, and R is what repeated flights do)
--
-- WHY. R is how many coins a flight returns per coin of fuel, and it alone decides how many
-- attempts a crossing takes: the bank grows (R-1) of whatever you spend, so a low R means
-- several flights to afford the next serving and a high R means one. It used to be 4.742 --
-- IDENTICAL at every tier, because capacities had been solved to scale with climb -- so R
-- was a constant and every crossing in the tower took the same number of tries no matter how
-- high you were. Flat, not a ramp, and no amount of re-pricing food or guts could bend it,
-- because price cancels out of R against the coins the same flight earns.
--
-- Letting the tank outgrow the climb is the only lever that changes R per tier without
-- touching a gap or a speed. A bigger tank costs proportionally more to fill and still
-- climbs exactly as far, so the return falls, and the crossings near the summit take 8
-- flights against the opening's 3.
--
-- THE STARTER TIER IS THE ODD ONE OUT AT 1.99, ON PURPOSE. Crossing 1 is the only place a
-- player has no income history, so it is the only crossing whose flight count comes from the
-- starting bank rather than from R. It is also the only three-rung ladder in the tower --
-- 34% -> 70% -> clear -- which is what a first crossing should teach. Everything above it
-- runs at R ~1.1, where the flights come from saving up, not from a wider ladder.
--
-- 1.09 IS ESSENTIALLY THE FLOOR AND THAT IS WHY THE TOP STOPS AT EIGHT TRIES. A flight
-- returns R x SPEED_SHAPE[1] at worst, and under 1.0 there a player who can only afford a
-- splash of food loses coins every launch and can never climb out. 1.09 x 0.944 = 1.03 is as
-- close to that wall as this tower can safely sit. If more attempts are ever wanted, they
-- cannot come from here.
--
-- MAXPOWER DOES NOT AFFECT SPEED. getFlightSpeed is climb/FLIGHT_SECONDS x SPEED_SHAPE[band]
-- and the band is a FRACTION of the tank, so every one of these tiers flies at exactly the
-- speed it did before and a full tank still burns in FLIGHT_SECONDS. What changes is the
-- price of that full tank, nothing else. The gates are untouched too, since they compare
-- climb against gap and neither moved.
--
-- THE INVARIANT TO PROTECT IS R x SPEED_SHAPE[1] > 1, not "capacity growth < R". A tank
-- holding a dribble flies in the slowest band, and if that flight cannot pay for its own
-- fuel a broke player can never climb out. Worst row here is 1.33 x 0.944 = 1.25, with the
-- whole ladder above it. Push the top tanks much past 1500 and that is the number that
-- breaks first.
--
-- Rows 1 and 2's `gap` values were re-synced when island 2 dropped 702 -> 570 (see
-- IslandOrder). The gate is far safer than before: 569 < 712 with 143 studs of slack, not 11.
-- ===== TANK SIZES ARE THE R COLUMN, AND THEY WERE RE-SOLVED FOR THE DESCENT-PAY ECONOMY =====
--
-- `gap` and `climb` are UNTOUCHED and must stay that way -- they are the tower and the speed
-- ladder. `maxPower` is the free column and it is what sets R:
--
--        tank    climb   climb/tank   food eff   R = eff x 1.400 x 3 x climb/tank
--         120      569       4.74       0.1000       1.99
--         270      853       3.16       0.1081       1.45
--         470     1232       2.62       0.1184       1.31
--         620     1706       2.75       0.1279       1.51
--        1080     2370       2.19       0.1413       1.31
--        1710     3318       1.94       0.1545       1.27
--        2600     4740       1.82       0.1688       1.30
--
-- (the x3 is 1 + DESCENT_PAY_MULT: a REPEATED flight climbs d and falls d, and R is built
--  out of the flights you repeat, not the one that lands)
--
-- THESE ARE NOT ROUND NUMBERS BECAUSE THEY ARE NOT CHOSEN. Each one is
--       tank = food_efficiency x COIN_PER_STUD x (1 + DESCENT_PAY_MULT) x climb / R_target
-- rounded to a multiple of 10, and R_target is what the crossing's flight count needs. Move
-- a tank and you move that crossing's flight count and nothing else -- speed, climb, gates
-- and gaps are all independent of capacity (see the note under getFlightSpeed).
--
-- THE GATES ARE UNAFFECTED and were re-verified after the change: they compare `climb`
-- against `gap`, and neither column moved.
--       569 < 712    853 < 870    1232 < 1257    1706 < 1740    2370 < 2417    3318 < 3384
-- Every gut still clears the longer crossing of its own range:
--       569/420  853/828  1232/1195  1706/1655  2370/2299  3318/3218  4740/3384
--
-- THE DRIBBLE FLOOR still holds. A tank holding one anti-strand meal flies in band 1, and
-- that flight must still pay for its own fuel: worst row is R x SPEED_SHAPE[1] = 1.27 x
-- 0.944 = 1.20. Under 1.0 there, a broke player bleeds out and can never climb back.
-- ===== EVERY `climb` AND `gap` HERE IS x1.5 EXACTLY, MATCHING THE 0.6825 RESPACING =====
-- maxPower did NOT move and must not: tanks are a fuel quantity, not a distance. Scaling the
-- tanks as well would double-count and hand every gut 1.5x the reach it is solved for.
--
-- THE .5s ARE LOAD-BEARING -- DO NOT TIDY THEM INTO WHOLE STUDS. Rounding was tried and it
-- moved the flight ladder (c10 13 -> 15 flights, and the knock-on shoved c11 and c12 around
-- too). Climb is compared against gap everywhere, so half a stud on either side is enough to
-- flip whether a marginal fill clears -- and the wallet carries between crossings, so one
-- flipped flight propagates. At the exact values tools/ladder.py reproduces the old curve
-- flight for flight, with every flight on the same percentage of its gap.
local BASE_TIERS = {
	{ maxPower = 120, gap = 630, climb = 853.5 },  -- Hatchling Belly  slots 1-2
	{ maxPower = 270, gap = 1068, climb = 1279.5 },  -- Raptor Gut  slots 2-4
	{ maxPower = 470, gap = 1305, climb = 1848 },  -- Dilo Stomach  slots 4-6
	{ maxPower = 620, gap = 1885.5, climb = 2559 },  -- Trike Gut  slots 6-8
	{ maxPower = 1080, gap = 2610, climb = 3555 },  -- Rex Gut  slots 8-10
	{ maxPower = 1710, gap = 3625.5, climb = 4977 },  -- Titan Gut  slots 10-12
	{ maxPower = 2600, gap = 5076, climb = 7110 },  -- Colossus Gut  slot 12-13 (ONE gap: the tower ends at 13)
	{ maxPower = math.huge, gap = 8190, climb = 12285 }, -- Primal Gut (Robux, 9999 tank)
}

-- SPEED SHAPE -- how fast you fly at each FRACTION of your own tank, lowest slice first.
--
-- Normalised so the mean is exactly 1.0, which is what makes a full tank travel its tier's
-- `climb` precisely: climb = (mean of the shape) x climb, and the mean is 1.
--
-- 1.15x from the empty end to the full end -- much gentler than the 1.6x it replaced.
-- The taper is NOT what walls a crossing (the coin rate is -- see IslandOrder), so this only
-- has to stay steep enough that a nearly-empty tank still pays for its own fuel:
--     return on a dribble of fuel = R x SPEED_SHAPE[1] = 1.20 x 0.932 = 1.12  (must be > 1)
-- Flatten it further and that goes under 1, which means a player who can only afford a
-- splash of food loses coins on every launch and can never climb out.
local SPEED_SHAPE = { 0.944, 0.960, 0.975, 0.991, 1.007, 1.024, 1.041, 1.058 }
FlightTuning.SPEED_SHAPE = SPEED_SHAPE
local NBANDS = #SPEED_SHAPE

-- Running integral of the shape at each band edge, so climb/inverse-climb are exact
-- table walks rather than searches. CUM[i+1] is the fraction of a full tank's distance
-- covered by the time fuel has drained to i/NBANDS of the tank.
local CUM = { 0 }
for i, v in ipairs(SPEED_SHAPE) do CUM[i + 1] = CUM[i] + v / NBANDS end

FlightTuning.TIERS = {}
for i, t in ipairs(BASE_TIERS) do
	FlightTuning.TIERS[i] = { maxPower = t.maxPower, gap = t.gap, climb = t.climb }
end

-- getFlightSpeed(power, stomachMax) -- the speed to fly at RIGHT NOW.
--
-- STOMACHMAX IS THE SECOND ARGUMENT AND IT IS NOT OPTIONAL IN SPIRIT. The band you are in
-- is a fraction of YOUR OWN TANK, not an absolute fuel amount, so the same 100 fuel is
-- "nearly empty" on a Colossus and "most of a tank" on a Hatchling and must not fly at the
-- same speed. Callers that omit it get the starting tier, which is only correct on tier 1.
--
-- Speed still tapers as the tank drains -- that is the mechanic, and the band wall depends
-- on it -- but the taper is now the same 1.6x slide on every gut instead of bottoming out
-- at the starter gut's 50 studs/sec no matter what you paid.
function FlightTuning.getFlightSpeed(power: number, stomachMax: number?): number
	local max = tonumber(stomachMax) or FlightTuning.TIERS[1].maxPower
	if max <= 0 then return 0 end
	local tier = FlightTuning.tierFor(max)
	-- PER-GUT duration, not the global. This is the ONLY place the slowdown is applied:
	-- a tier that burns 1.9x longer flies 1.9x slower, so climb (speed x time) is identical
	-- and nothing that gates the tower moves. See TIER_TIME.
	local avg  = tier.climb / FlightTuning.tankSecondsFor(max) -- the tier's mean speed
	local x    = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local band = math.min(NBANDS, math.floor(x * NBANDS) + 1)  -- 1-based, empty end first
	return avg * SPEED_SHAPE[band]
end

-- The tier a TANK SIZE belongs to (not a draining power) -- used by the shop.
function FlightTuning.tierFor(stomachMax: number)
	local max = tonumber(stomachMax) or 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		if max <= tier.maxPower then return tier end
	end
	return FlightTuning.TIERS[#FlightTuning.TIERS]
end

-- What a FULL tank of this size actually climbs, by the integral described above.
-- This is the check the BANDS were solved against; keep it, because it is the only
-- thing that will tell you a hand-edited speed has broken a tier.
function FlightTuning.fullTankClimb(stomachMax: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	return FlightTuning.tierFor(max).climb          -- the shape averages 1, so this is exact
end

-- How far a tank of `stomachMax` filled to `power` will climb before running dry.
-- Walks the shape's running integral, so it is exact rather than sampled.
function FlightTuning.climbFor(stomachMax: number, power: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local x = math.clamp((tonumber(power) or 0) / max, 0, 1)
	local j = math.min(NBANDS - 1, math.floor(x * NBANDS))
	return FlightTuning.tierFor(max).climb * (CUM[j + 1] + (x - j / NBANDS) * SPEED_SHAPE[j + 1])
end

-- COURTESY FILL: what CurrentPower a gut should hold the moment it is bought.
--
-- A full tank climbs gap * MARGIN, so the CROSSING ITSELF costs 1/MARGIN = ~93% of
-- the tank. The brief is "enough for the next island, +10%" -- 93% * 1.10 is over
-- 100%, so an earned gut arrives FULL. That is the honest result of the arithmetic
-- rather than a number picked to look generous.
-- POWER NEEDED TO CLIMB `distance` IN A TANK OF `stomachMax`. The inverse of
-- fullTankClimb: that one asks "how far does a full tank go", this asks "how full must it
-- be to go this far".
--
-- Both run on the same integral. A tank filled to p burns for FLIGHT_SECONDS * (p/max) and
-- steps DOWN through the bands from p to 0, so its climb is (FLIGHT_SECONDS/max) * S(p),
-- where S is the running sum of speed x band-width. Solving for S and walking the bands
-- until it is reached gives p exactly -- no search, no approximation.
function FlightTuning.powerForClimb(stomachMax: number, distance: number): number
	local max  = tonumber(stomachMax) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or dist <= 0 then return 0 end
	local y = dist / FlightTuning.tierFor(max).climb   -- fraction of a full tank's distance
	if y >= 1 then return max end                      -- a full tank is not enough
	for j = 1, NBANDS do
		if CUM[j + 1] >= y then
			return max * ((j - 1) / NBANDS + (y - CUM[j]) / SPEED_SHAPE[j])
		end
	end
	return max
end

-- COURTESY FILL: what CurrentPower a gut should hold the moment it is bought.
--
-- IT USED TO HAND OVER A FULL TANK, and that was arithmetic, not generosity: it assumed
-- the buyer was about to fly their OWN tier's gap, for which a full tank is 1/MARGIN, and
-- 92.6% + 10% is over 100%. But you BUY a gut at the END of the previous tier -- the very
-- next crossing is the SHORTER one you are already standing at the bottom of. Sizing the
-- fill against the new tank's own gap over-filled it every time.
--
-- `gap` is now the crossing actually in front of the player. For a Raptor Gut (182) bought
-- on slot 2, that is 6000, not 6600: 156 power climbs it, +10% is 172, and the player gets
-- 172/182 -- enough, with a real margin, and visibly not full.
--
-- Called with no gap it falls back to the old whole-tank behaviour, so any caller that has
-- not been taught where the player is standing still works.
-- COURTESY_FRACTION: 0. It was 1.10, then 0.30, then 0.15.
-- At 1.10 a freshly bought gut arrived with MORE fuel than the next crossing needs, so the
-- wall crossing was always cleared on the very next launch -- every gut purchase handed out
-- a free island. 0 is the solved value for the current tables: a new gut arrives EMPTY and
-- you buy food for it like any other flight, which is what puts the wall crossings at 5.
-- Raise it if buying a gut ever feels punishing -- but it is one of the inputs the
-- flight-count solve was run against, so moving it moves those counts and the gut costs
-- have to be re-solved with it.
FlightTuning.COURTESY_FRACTION = 0

-- ===== A NEW GUT ARRIVES FULL -- TRIED AND REVERTED. Leave this false. =====
-- Shipped true for one build. It makes the gut purchase clear its own crossing on the
-- very next launch, which reads as the game playing itself: 33 flights instead of 93, and
-- forty of those made no visible progress because the player was pinned at the bottom of
-- every ladder. The switch stays so the experiment is one word away, not a rewrite.
--
-- (original note follows)
-- ===== A NEW GUT ARRIVES FULL. DELIBERATE, AND IT OVERRIDES COURTESY_FRACTION. =====
-- This is the design the note above describes at 1.10 and calls a bug: a freshly bought
-- gut carries more fuel than the next crossing needs, so the crossing you bought it for
-- is cleared on the very next launch. It is intentional now. The gut purchase IS the
-- crossing -- you save up, you buy, the tank hands you the island, and TOUCHDOWN EMPTIES
-- IT (see BottomHUD) so the crossing after that starts from zero like any other.
--
-- WHAT IT COSTS, measured, so nobody has to rediscover it:
--     off  [3, 7, 4, 13, 9, 8, 5, 9, 8, 14, 11, 11]  = 102 flights
--     on   [3, 1, 3,  1, 6, 1, 4, 1, 6,  1,  5,  1]  =  33 flights
-- All six gut crossings drop to ONE flight, and the crossings after them shorten too,
-- because a one-flight crossing spends nothing on food and banks the difference. If the
-- run needs to be longer again, the lever is the GUT COSTS in StomachTiers -- they are
-- what the player now saves toward, and they are no longer sized for that job.
FlightTuning.COURTESY_FULL_TANK = false

function FlightTuning.courtesyPower(stomachMax: number, gap: number?): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	-- Full tank wins over the fraction entirely -- no interaction, no rounding, no gap term.
	if FlightTuning.COURTESY_FULL_TANK then return max end
	local cf = FlightTuning.COURTESY_FRACTION
	local g = tonumber(gap)
	if not g or g <= 0 then
		return math.floor(math.min(1, (1 / FlightTuning.MARGIN) * cf) * max + 0.5)
	end
	local need = FlightTuning.powerForClimb(max, g)
	return math.floor(math.min(max, need * cf) + 0.5)
end

-- The gap the player must cross FROM a given climb slot -- i.e. the one their next flight
-- has to clear. Pairs with courtesyPower above; keep in step with IslandOrder.SLOT_POS.
function FlightTuning.gapFromSlot(slot: number): number?
	local s = math.floor(tonumber(slot) or 0)
	if s < 1 then return nil end
	local ok, IslandOrder = pcall(function()
		return require(game:GetService("ReplicatedStorage").DinosaurRealm.IslandOrder)
	end)
	if not ok or not IslandOrder then return nil end

	-- DRIFT GUARD. gapFromSlot measures the REAL distance between two islands, while
	-- TIERS.gap is what the tuning assumes that distance is. If the two SPACING_SCALEs
	-- fall out of step those numbers diverge and nothing else would ever say so -- the
	-- shop would price crossings for a tower that no longer exists.
	if not FlightTuning._scaleWarned and IslandOrder.SPACING_SCALE
		and math.abs(IslandOrder.SPACING_SCALE - FlightTuning.SPACING_SCALE) > 1e-6 then
		FlightTuning._scaleWarned = true
		warn(("[FlightTuning] SPACING_SCALE MISMATCH: IslandOrder=%.3f but FlightTuning=%.3f. "
			.. "The tower and the flight physics disagree -- set both to the same value.")
			:format(IslandOrder.SPACING_SCALE, FlightTuning.SPACING_SCALE))
	end

	local here, next_ = IslandOrder.SLOT_POS[s], IslandOrder.SLOT_POS[s + 1]
	if not (here and next_) then return nil end
	return next_.Y - here.Y
end

-- RAW POWER still needed to make the next crossing, given what is in the tank now.
--
-- NOT WIRED TO ANYTHING RIGHT NOW. The shop's anti-strand used to price its top-up
-- against this, which handed the player a whole crossing on their first dry landing
-- and pinned every island at two attempts; it funds a quarter tank instead. Kept
-- because "how much more do I need to clear this gap" is the honest question to ask
-- if you ever want a HUD readout or a "you cannot make it yet" warning -- just do not
-- hand its answer to the player as coins.
function FlightTuning.powerShortfall(stomachMax: number, currentPower: number): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local need = (1 / FlightTuning.MARGIN) * max        -- the crossing's share of the tank
	return math.max(0, need - (tonumber(currentPower) or 0))
end

return FlightTuning
