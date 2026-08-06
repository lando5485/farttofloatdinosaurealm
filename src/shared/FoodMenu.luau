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
FoodMenu.LIST = {
	{ name = "Eggs",          price = 21,  power = 8,   island = 1 },  --  1  Nesting Nook      Hatchling
	{ name = "Chili Peppers", price = 53,  power = 25,  island = 9 },  --  2  Jungle Junction   Raptor
	{ name = "Lettuce",       price = 79,  power = 45,  island = 5 },  --  3  Misty Mire        Dilo
	{ name = "Grapes",        price = 101, power = 70,  island = 12 }, --  4  Sunscorch Sands   Stego
	{ name = "Bananas",       price = 118, power = 100, island = 3 },  --  5  Fossil Frontier   Anky
	{ name = "Popcorn",       price = 136, power = 140, island = 13 }, --  6  Glacier Gulch     Trike
	{ name = "Fish",          price = 147, power = 185, island = 4 },  --  7  Coastal Crossing  Bronto
	{ name = "Ribs",          price = 156, power = 240, island = 2 },  --  8  Fern Frontier     Spino
	{ name = "Potatoes",      price = 159, power = 300, island = 10 }, --  9  Petrified Pass    Rex
	{ name = "Apples",        price = 160, power = 370, island = 7 },  -- 10  Raptor Ridge      Ptero
	{ name = "Mushrooms",     price = 159, power = 450, island = 6 },  -- 11  Redwood Ridge     Fossil
	{ name = "Chicken",       price = 156, power = 540, island = 8 },  -- 12  Inferno Isle      Titan
	{ name = "Steak",         price = 185, power = 640, island = 11 }, -- 13  Volcanic Vista    Titan (summit)
}

-- name -> row, for the purchase handler (which is handed a name, not an index).
FoodMenu.BY_NAME = {}
for _, food in ipairs(FoodMenu.LIST) do
	FoodMenu.BY_NAME[food.name] = food
end

return FoodMenu
