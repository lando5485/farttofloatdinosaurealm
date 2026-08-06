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
FlightTuning.FLIGHT_SECONDS = 45

-- How far a full tank overshoots the gap it is tuned for. Keeps the reference's
-- "each island sits at ~92% of a full tank" tension: gas spent steering can still
-- cost you the landing.
FlightTuning.MARGIN = 1.08

-- SPACE REALM'S DRAIN MODEL, copied exactly (StomachTiers.luau / FlightClient):
--     the 0-100 meter drains at 100 / tankSeconds per second for the EQUIPPED tier,
--     so raw drain = StomachMax / tankSeconds and a full tank lasts tankSeconds.
-- There, tankSeconds RISES with tier (28 -> 58s) so bigger guts burn longer AND
-- climb farther. Here every tier gets the SAME tankSeconds, because the brief is a
-- constant leg length at every tier: distance is bought with speed instead.
FlightTuning.TANK_SECONDS = FlightTuning.FLIGHT_SECONDS

function FlightTuning.tankSecondsFor(_stomachMax: number): number
	return FlightTuning.TANK_SECONDS
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
FlightTuning.TIERS = {
	{ maxPower = 110,  gap = 3375,  speed = 81.0 },  -- Hatchling Belly  slot 1 -> 2
	{ maxPower = 150,  gap = 3780,  speed = 115.0 }, -- Raptor Gut       slot 2 -> 3
	{ maxPower = 200,  gap = 4234,  speed = 132.1 }, -- Dilo Stomach     slot 3 -> 4
	{ maxPower = 270,  gap = 4742,  speed = 146.9 }, -- Stego Stomach    slot 4 -> 5
	{ maxPower = 365,  gap = 5311,  speed = 164.8 }, -- Anky Belly       slot 5 -> 6
	{ maxPower = 495,  gap = 5949,  speed = 184.6 }, -- Trike Gut        slot 6 -> 7
	{ maxPower = 675,  gap = 6663,  speed = 206.1 }, -- Bronto Belly     slot 7 -> 8
	{ maxPower = 920,  gap = 7463,  speed = 231.2 }, -- Spino Stomach    slot 8 -> 9
	{ maxPower = 1260, gap = 8359,  speed = 258.2 }, -- Rex Gut          slot 9 -> 10
	{ maxPower = 1725, gap = 9362,  speed = 289.4 }, -- Ptero Belly      slot 10 -> 11
	{ maxPower = 2360, gap = 10485, speed = 324.4 }, -- Fossil Gut       slot 11 -> 12
	{ maxPower = 3230, gap = 11743, speed = 363.4 }, -- Titan Gut        slot 12 -> 13
	{ maxPower = math.huge, gap = 13000, speed = 420.0 }, -- Primal Gut (Robux)
}

-- getFlightSpeed(power) -- the reference's function, same signature, same meaning:
-- the band for the CURRENT (draining) power, so speed tapers through the flight.
function FlightTuning.getFlightSpeed(power: number): number
	local p = tonumber(power) or 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		if p <= tier.maxPower then return tier.speed end
	end
	return FlightTuning.TIERS[#FlightTuning.TIERS].speed
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
	local sum, prev = 0, 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		local top = math.min(tier.maxPower, max)
		if top > prev then
			sum += tier.speed * (top - prev)
			prev = top
		end
		if top >= max then break end
	end
	return (FlightTuning.FLIGHT_SECONDS / max) * sum
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
	local max = tonumber(stomachMax) or 0
	local dist = tonumber(distance) or 0
	if max <= 0 or dist <= 0 then return 0 end
	local need = dist * max / FlightTuning.FLIGHT_SECONDS   -- the S(p) we must reach
	local sum, prev = 0, 0
	for _, tier in ipairs(FlightTuning.TIERS) do
		local top = math.min(tier.maxPower, max)
		if top > prev then
			local span = (top - prev) * tier.speed
			if sum + span >= need then
				return math.min(max, prev + (need - sum) / tier.speed)
			end
			sum, prev = sum + span, top
		end
		if top >= max then break end
	end
	return max   -- a full tank is not enough; the caller gets everything there is
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
function FlightTuning.courtesyPower(stomachMax: number, gap: number?): number
	local max = tonumber(stomachMax) or 0
	if max <= 0 then return 0 end
	local g = tonumber(gap)
	if not g or g <= 0 then
		return math.floor(math.min(1, (1 / FlightTuning.MARGIN) * 1.10) * max + 0.5)
	end
	local need = FlightTuning.powerForClimb(max, g)
	return math.floor(math.min(max, need * 1.10) + 0.5)
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
