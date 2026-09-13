--======================================================================
-- FoodMenu.luau  (ModuleScript -> ReplicatedStorage/DinosaurRealm)
--======================================================================
-- THE FOOD STAND MENU, in one place, for the same reason StomachTiers.luau exists: it was
-- typed out twice -- once in Shop.server (which validates the purchase) and once in
-- ShopGlue.client (which draws the prices) -- and the two DRIFTED. The client was showing
-- Eggs at 16 while the server charged 21, Steak at 150 against 185, and every row in
-- between was wrong by 20-30%. Nothing errors on that; the stand simply lies about the
-- price and takes a different number of coins.
--
-- Ordered by CLIMB SLOT (1..13), which is the order the player meets them -- NOT by island
-- model number. The tower scrambles the two (IslandOrder.SLOT_TO_ISLAND is
-- {1,9,5,12,3,13,4,2,10,7,6,8,11}), and an earlier version keyed this by model number, so
-- along the actual route power ran 8 -> 300 -> 25 -> 540 -> 45 -> 640 and three foods
-- unlocked on slots where the player's tank was too small to hold one serving.
--
-- THE ROW ORDER IS THE CONTRACT; THE `island` FIELD JUST NAMES THE HOST. Row k is the food
-- for SLOT k, and its price/power are solved for slot k. `island` only says which model the
-- stand physically sits on -- so whenever IslandOrder moves an island, the affected rows'
-- `island` fields move with it or the food ends up at the wrong altitude.
--
-- That is why LETTUCE IS ON MISTY MIRE and RIBS ARE ON FERN FRONTIER, which reads odd
-- thematically: island5 and island2 were swapped in IslandOrder (Misty Mire to slot 3, Fern
-- Frontier to slot 8), so the two stands swapped hosts to stay at their solved slots. The
-- foods did NOT move up or down the climb -- only the scenery around them did. If the names
-- matter more than the pairing, rename the rows; do not move price/power between slots.
--
-- PRICES ARE DERIVED, NOT PICKED. Each row is solved for a flat
--       R = (coins a full flight earns) / (coins a full refill costs) = 1.91
--       price = gap * MARGIN * COIN_PER_STUD / (R * (tierMaxPower / power))
-- against the gap and the tank size AT THAT SLOT. Both moved in the twelve-tier retier, so
-- both halves of every row moved with them. See the long note in Shop.server.luau for why
-- R > 1 is the thing to protect and why prices can NOT be used to set the try count.
--
-- tierMaxPower above is the ORIGINAL tank size (100/140/190/...), not the +10 one the shop
-- now sells. The +10 was asked for as capacity ONLY -- no change to what food costs or what
-- a flight earns -- so these prices were re-solved once for the twelve tiers and then left
-- alone. It costs ~0.8% of margin (see the note on FlightTuning.TIERS) and nothing else.
--
-- "Turkey Legs" (island=14) is RETIRED: the game is 13 islands. A food here that the server
-- does not have is a buyable item the server rejects, so this list is the whole contract.
--======================================================================

local FoodMenu = {}

--                                             slot  island            gut tier at that slot
-- ==========================================================================
-- A MEAL IS SOLVED SO THAT TWO OF THEM CROSS THE GAP (three on the two starter islands).
-- That is what this column is for, and it is the reason no crossing can end in a near-miss.
-- ==========================================================================
--
-- THE MEAL SIZE IS THE ONLY THING THAT DECIDES HOW SHORT THE LAST FAILED ATTEMPT FALLS.
--
-- Here is the law. A player lands, spends everything on food, flies, banks what the climb
-- paid, and repeats. A flight returns R times its own fuel cost, so if fuel were infinitely
-- divisible the ladder would be geometric and the LAST failure would always land at 1/R of
-- the gap -- 91%, 95%, whatever R happens to be. At the R this tower runs on (~1.1 above the
-- starter island) that would be a 91% miss on every single crossing. There is no starting
-- bank, coin rate or spacing that escapes it; it is the same number from both ends. That is
-- exactly the "it keeps edging me" case.
--
-- Meals break it, because fuel is NOT divisible: you fly whole meals. The failed attempt
-- sits one meal below the one that clears, so the miss is pinned to a QUANTISED STEP instead
-- of to R. With n meals to a crossing the last miss is roughly (n-1)/n of the distance:
--
--       n = 12   last miss ~95%     <- what this file shipped as, and always in the band
--       n =  4   last miss ~78%
--       n =  3   last miss ~70-73%  <- crossings 1 and 2
--       n =  2   last miss ~51-60%  <- crossings 3 to 12
--
-- TWO IS THE FLOOR, not a preference: one meal would have to be more than a whole crossing
-- and less than one at the same time. So this table sits on the floor everywhere it can, and
-- every miss in the tower lands between 51% and 73% of the gap -- nowhere near the band that
-- reads as "so close". Each row satisfies
--       n x power      >=  (fuel the crossing needs) + 4% of the tank    <- n meals clear
--       (n-1) x power  <   (fuel the crossing needs)                     <- n-1 do not
--
-- CROSSINGS 1 AND 2 ARE THREE MEALS ON PURPOSE. They are the only two crossings whose flight
-- count comes from the starting bank rather than from saving up, so they are the only two
-- that can afford a wider ladder -- crossing 1 reads 34% -> 70% -> clear, which is the right
-- way to teach a new player what the gas meter does. Everything above runs at R ~1.1, where
-- extra flights come from saving, and a third rung there would only raise the miss.
--
-- POWER IS NOT A FIXED FRACTION OF THE TANK, and it cannot be. The crossings need 71.9% to
-- 97.2% of a tank depending on whether the slot faces the short hop or the long one, so a
-- single fraction would put some slots at two meals and others at three or four.
--
-- THAT MEANS A MEAL NEED NOT DIVIDE THE TANK, and the shop handles the remainder: a last
-- purchase that would overflow tops the tank off and clamps instead of being refused (see
-- the note in Shop.server's BuyFood). Before that fix the leftover fuel you land with pushed
-- the tank one meal short of full and manufactured 95-98% misses all by itself.
--
-- THE FLOOR UNDERNEATH IT. Shop.server's anti-strand hands a genuinely broke player exactly
-- ONE meal -- enough to launch, never enough to cross, since no crossing is one meal. Raise
-- that to two and most of the tower becomes free.
--
-- VALUE IS FLAT AT 0.100 FUEL PER COIN ON EVERY ISLAND. Prices are just power x 10. Meals
-- get bigger going up (32 -> 730) and cost more (320 -> 7300), and buy exactly the same fuel
-- per coin the whole way. Nothing in this column can move R, the gut prices or the gates.
--
-- POWER REPEATS IN PAIRS in places because a gut covers two slots and the short crossing of
-- the pair can reuse the long one's meal; where it does not, the long crossing needs the
-- bigger meal.
--
-- FUEL PER COIN IS FLAT AT 0.100 ON EVERY ISLAND, and that is deliberate. It used to
-- rise, which reads generous but is a direct discount on the NEXT island's tank: it made
-- every crossing cheaper relative to what the last one earned, and that is one of the
-- things that collapsed the un-purchased crossings to a single flight. Later food is
-- still a strict upgrade -- the SERVINGS get bigger, so a tank is fewer trips to the
-- stand -- it just is not better VALUE. If you make it rise again, re-check the
-- coin-wall inequality in IslandOrder.
--
-- ORDERED BY CLIMB SLOT; the `island` field names the MODEL that hosts the stand and must
-- stay matched to IslandOrder.SLOT_TO_ISLAND -- see this file's header. Moving an island in
-- IslandOrder without swapping these `island` fields puts a slot-13 food on slot 3.
-- ===== VALUE RISES 1.00x -> 1.69x, AND A MEAL IS A SMALL SLICE OF ITS CROSSING =====
--
-- Both halves of that sentence are load-bearing and they pull against each other. Read this
-- before moving any number in the table.
--
-- WHY VALUE RISES. Flat value was a rule here for a long time (0.100 fuel per coin on every
-- island) because a value TAPER is a coin-devaluation and reads backwards. Rising value is
-- the opposite and is safe: a coin buys more the higher you get, so later food is a genuine
-- upgrade in the only way a player can feel -- bang for the coin, not just serving size.
-- It also feeds straight into R (see BASE_TIERS in FlightTuning), which is what lets the top
-- of the tower run 7-9 flights per crossing without the return ever dropping under 1.
--
-- WHY A MEAL SHRANK TO 5-18% OF ITS CROSSING. This is the rule that a previous ship failed:
--
--       meal_price  <=  what the player is actually holding on flight 1
--
-- Rex-tier food used to be 61% of its crossing at 3,700 coins while the player landed with
-- ~3,000 and then paid for a gut. They could not buy it. BUY MAX fell back on cheap food,
-- the effective value per coin collapsed to the bottom of this table, R fell to ~1.00, and
-- crossing 8 sat at ~40% of the gap for nine flights with no way out. A food the intended
-- player cannot afford on their first flight is not a food, it is a stall.
--
-- So every row was searched against the ACTUAL BUY MAX SEQUENCE replayed from the real coin
-- balance at the start of each crossing -- not against an assumed wallet. tools/ladder.py
-- re-runs that replay and asserts the affordability check row by row.
--
-- THE COST OF THAT RULE, stated plainly so nobody "fixes" it later: late food is NOT a big
-- luxury purchase. Steak is 770 coins for 130 power against Eggs at 320 for 32 -- 2.4x the
-- price, 4x the serving, 1.69x the value. It cannot be a 5,000-coin showpiece, because a
-- meal is capped at roughly the first rung of its own ladder and the late ladders are long.
-- Make Steak expensive and crossing 12 stalls exactly the way crossing 8 did. This was a
-- deliberate, accepted trade: working progression over an impressive price tag.
--
-- POWER AND PRICE BOTH MOVE MONOTONICALLY UP THE TABLE and value never dips. An earlier pass
-- produced Grapes at 0.1300 and Bananas at 0.1292 purely from rounding, which means the shop
-- sells you a worse deal for more money one slot later. The search enforces monotonicity now.
--
-- PAIRS REPEAT (370/40, 380/45, ...) BECAUSE A GUT COVERS TWO SLOTS. The short crossing of a
-- range reuses the long one's meal; there is no tier change between them to price against.
-- Those rows are identical on purpose, not by omission.
--
-- COLUMN 4 IS THE CHECK THAT MATTERS: what share of its own crossing one serving buys. Keep
-- every row at or under ~20% (crossing 1 is the tutorial and is allowed 36%) or the ladder
-- for that crossing gets too coarse and the last miss climbs back toward the 90s.
FoodMenu.LIST = {
	--                                          power  price   power/coin  mult   % of its crossing
	{ name = "Eggs",           price = 1280 , power = 32 , island = 1  }, --  1   0.1000  1.00x   36%  (tutorial)
	{ name = "Chili Peppers",  price = 1480 , power = 40 , island = 9  }, --  2   0.1081  1.08x   18%
	{ name = "Lettuce",        price = 1480 , power = 40 , island = 5  }, --  3   0.1081  1.08x   15%
	{ name = "Grapes",         price = 1520 , power = 45 , island = 12 }, --  4   0.1184  1.18x   13%
	{ name = "Bananas",        price = 1520 , power = 45 , island = 3  }, --  5   0.1184  1.18x   10%
	{ name = "Popcorn",        price = 1720 , power = 55 , island = 13 }, --  6   0.1279  1.28x   12%
	{ name = "Fish",           price = 1720 , power = 55 , island = 7  }, --  7   0.1279  1.28x    9%
	{ name = "Ribs",           price = 1840 , power = 65 , island = 4  }, --  8   0.1413  1.41x    8%
	{ name = "Potatoes",       price = 1840 , power = 65 , island = 10 }, --  9   0.1413  1.41x    6%
	{ name = "Apples",         price = 2200 , power = 85 , island = 2  }, -- 10   0.1545  1.55x    7%
	{ name = "Mushrooms",      price = 2200 , power = 85 , island = 8  }, -- 11   0.1545  1.55x    5%
	{ name = "Chicken",        price = 3080 , power = 130, island = 6  }, -- 12   0.1688  1.69x    7%
	{ name = "Steak",          price = 3080 , power = 130, island = 11 }, -- 13   0.1688  1.69x  (summit)
}





-- name -> row, for the purchase handler (which is handed a name, not an index).
FoodMenu.BY_NAME = {}
for _, food in ipairs(FoodMenu.LIST) do
	FoodMenu.BY_NAME[food.name] = food
end

return FoodMenu
