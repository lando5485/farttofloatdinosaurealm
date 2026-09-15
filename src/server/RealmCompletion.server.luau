--======================================================================================================
-- RealmCompletion.server.luau   (ServerScriptService.DinosaurRealmServer)
--======================================================================================================
-- THE ONE THING THIS PLACE OWED THE HUB, AND NEVER PAID.
--
-- The Food Realm's portal room gates the CANDY REALM on "have you beaten the Dino Realm", and it answers
-- that question by reading a DataStore this place is supposed to write:
--
--     store  DinoRealm_PlayerState_v1
--     key    "Player_<userId>"
--     value  a table with  dinoComplete = true
--
-- (See RealmPortals.server.lua in the Food repo -- dinoCompleted(), which reads exactly that and nothing
-- else.) Nothing in this place has ever written it. Worse, that read FAILS CLOSED by design: a missing
-- record is indistinguishable from "not finished", so the Candy portal was not merely un-lit for players
-- who had beaten the Dino Realm -- it was permanently unreachable BY EVERYONE. The realm chain
-- Food -> Space -> Dino -> Candy terminated here.
--
-- WHAT COUNTS AS BEATEN: reaching the SUMMIT, i.e. climb slot IslandOrder.COUNT (13 -- which is island
-- MODEL 11, Volcanic Vista, not the model numbered 13).
-- HighestSlot -- not HighestIsland -- is the signal, for the reason PetXPHooks spells out: the tower
-- scrambles model numbers against climb order, so island 13 is not the top and comparing model numbers
-- would hand out the realm early. PetXPHooks owns both attributes; this file only reads them.
--
-- WRITE POLICY
--   * UpdateAsync, not SetAsync. This store is empty today, but the moment anything else in this place
--     starts using it, a blind SetAsync here would erase that record. Merging costs nothing now and
--     cannot bite later.
--   * ONCE per player per server. Completion is permanent and the flag never goes false, so re-writing
--     it every time they touch the summit would just burn DataStore budget.
--   * The record is written the moment they land on the summit -- not on leave. A player who closes the
--     game the instant they arrive has still beaten the realm, and a save that only happens on a clean
--     exit is a save that loses exactly the players who rage-quit at the top.
--
-- Everything is pcall'd. No DataStore (Studio with API access off) means the write no-ops and the rest
-- of the realm is untouched -- this must never be able to break a session.
--======================================================================================================

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

local STORE_NAME = "DinoRealm_PlayerState_v1" -- ⚠ MUST match RealmPortals.DINO_STORE in the Food repo
local KEY_PREFIX = "Player_"                  -- ⚠ MUST match RealmPortals.KEY_PREFIX
local SUMMIT     = IslandOrder.COUNT          -- 13 -- the last climb SLOT (model 11, Volcanic Vista)

local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)
if not store then
	warn("[RealmCompletion] no DataStore (API access off?) -- completion will NOT be recorded this session")
end

local written = {} -- [player] = true, so the summit is written once per server, not once per landing

local function summitSlotOf(player)
	-- HighestSlot is the climb position and the honest measure. HighestIsland is kept as a fallback only
	-- for a session where the slot attribute has not been set yet -- and it is compared against COUNT the
	-- same way, so it can never be MORE generous than the slot check.
	local slot = tonumber(player:GetAttribute("HighestSlot"))
	if slot then return math.floor(slot) end
	local isl = tonumber(player:GetAttribute("HighestIsland"))
	return isl and math.floor(isl) or 1
end

local function recordCompletion(player)
	if written[player] or not store then return end
	if summitSlotOf(player) < SUMMIT then return end
	written[player] = true -- claimed BEFORE the yield, so two landings in the same frame cannot both write

	local key = KEY_PREFIX .. tostring(player.UserId)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			local rec = (type(old) == "table") and old or {}
			rec.dinoComplete = true          -- the flag the Food Realm's Candy portal reads
			rec.dinoCompleteAt = os.time()   -- not read by anything: it is here so "when did they finish"
			rec.highestSlot = SUMMIT         -- is answerable later without a second store
			return rec
		end)
	end)
	if ok then
		print(("[RealmCompletion] %s BEAT THE DINO REALM (slot %d/%d) -> %s written, Candy Realm unlocked")
			:format(player.Name, summitSlotOf(player), SUMMIT, STORE_NAME))
	else
		written[player] = nil -- the write failed: let a later landing (or their next join) try again
		warn(("[RealmCompletion] write FAILED for %s: %s -- will retry on their next summit landing")
			:format(player.Name, tostring(err)))
	end
end

local function watch(player)
	-- On JOIN as well as on change: a player arriving with the attribute already restored (realm transfer,
	-- or a future save/load in this place) has finished and must not have to re-climb to be recorded.
	task.spawn(function()
		task.wait(5) -- let whatever restores the attributes finish first
		recordCompletion(player)
	end)
	player:GetAttributeChangedSignal("HighestSlot"):Connect(function() recordCompletion(player) end)
	player:GetAttributeChangedSignal("HighestIsland"):Connect(function() recordCompletion(player) end)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player)
	recordCompletion(player) -- last chance, in case the attribute landed in the same tick they left
	written[player] = nil
end)

print(("[RealmCompletion] ready -- summit is slot %d (%s); beating it writes dinoComplete to %s")
	:format(SUMMIT, IslandOrder.NAMES[IslandOrder.SLOT_TO_ISLAND[SUMMIT]] or "?", STORE_NAME))
