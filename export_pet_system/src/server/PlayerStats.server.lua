-- Enable Studio access to DataStores: go to Game Settings > Security >
-- Enable Studio Access to API Services to fix DataStore errors in Studio
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
-- (Daily Rewards removed: rewardStore / DAILY_REWARDS / claim logic deleted.)

-- HOLD players on join: no character auto-spawns, so nothing falls/moves while the loading screen +
-- island-select menu are up. The player is spawned manually onto their chosen island (SelectIslandEvent).
Players.CharacterAutoLoads = false

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then obj = Instance.new(className); obj.Name = name; obj.Parent = parent end
	return obj
end

local BuyFoodEvent      = getOrCreate(RS, "RemoteEvent", "BuyFoodEvent")
local RegenEvent        = getOrCreate(RS, "RemoteEvent", "RegenEvent")
local CoinEvent         = getOrCreate(RS, "RemoteEvent", "CoinEvent")
local SkipIslandEvent   = getOrCreate(RS, "RemoteEvent", "SkipIslandEvent")
local UnlockIslandEvent = getOrCreate(RS, "RemoteEvent", "IslandUnlockEvent")
local AnnouncementEvent = getOrCreate(RS, "RemoteEvent", "AnnouncementEvent")
local ServerEventNotify = getOrCreate(RS, "RemoteEvent", "ServerEventNotify")
local StomachFullEvent  = getOrCreate(RS, "RemoteEvent", "StomachFullEvent")
local BuyStomachEvent   = getOrCreate(RS, "RemoteEvent", "BuyStomachEvent")
local StomachUpdateEvent= getOrCreate(RS, "RemoteEvent", "StomachUpdateEvent")
-- s->c: (tierName, islandNeeded) -- the gut you tried to buy is locked until you reach that island.
-- Separate from StomachFullEvent so the shop can say WHY rather than failing silently, which is what
-- a rejected purchase looks like from the player's side.
local StomachLockedEvent= getOrCreate(RS, "RemoteEvent", "StomachLockedEvent")
local LandingEvent      = getOrCreate(RS, "RemoteEvent", "LandingEvent")
local ReturnToIslandEvent = getOrCreate(RS, "RemoteEvent", "ReturnToIslandEvent")
local WelcomeEvent      = getOrCreate(RS, "RemoteEvent", "WelcomeEvent") -- personal "You reached [Island]!" to the lander only
-- ON-JOIN STATE RESTORE: the client fires this AFTER its HUD + RemoteEvent handlers are built, asking
-- the server to (re)send its saved state (gut label + forever gamepasses). This handshake makes the
-- restore reliable on slow-loading mobile/console clients (no dependence on join-time push timing).
local RequestPlayerState = getOrCreate(RS, "RemoteEvent", "RequestPlayerState")
local SelectIslandEvent = getOrCreate(RS, "RemoteEvent", "SelectIslandEvent") -- client picks a spawn island from the loading-screen menu
local DinoSelectEvent   = getOrCreate(RS, "RemoteEvent", "DinoSelectEvent")   -- client picks a DINOSAUR island from the "SELECT A DINOSAUR ISLAND" screen; server VALIDATES unlock
local GoToIsland1Event  = getOrCreate(RS, "RemoteEvent", "GoToIsland1Event") -- rocket-event "Go to Island 1" teleport button

-- DINOSAUR-SELECT: 14 dino islands (mirrors the dino grid in LoadingScreen.client.lua). New players have
-- only island 1 unlocked; the per-player count lives in the "UnlockedDinos" player attribute (server-set,
-- so the client can't forge it). DinoSelectEvent re-validates against it before the (placeholder) spawn.
local DINO_COUNT = 14
-- ⚠ TEST-UNLOCK TOGGLE for the dino picker -- default OFF, so test accounts see the REAL new-player screen with
-- dino islands 2-14 locked (🔒). Flip to true only to preview the later cards. Must be false at launch.
-- The island picker has the matching TEST_UNLOCK_ALL_ISLANDS flag in LoadingScreen.client.lua -- keep them in step.
local TEST_UNLOCK_ALL_DINOS = false
-- ONE-TIME GARDEN INTRO CINEMATIC: server tells the client to PLAY the cutscene (fired when a player who
-- hasn't SeenGardenIntro selects island 1); the client fires _Done back when it finishes so we set+save the flag.
local GardenIntroEvent     = getOrCreate(RS, "RemoteEvent", "GardenIntroEvent")     -- server -> client: play the cinematic now
local GardenIntroDoneEvent = getOrCreate(RS, "RemoteEvent", "GardenIntroDoneEvent") -- client -> server: cinematic finished, set the seen flag
-- OFFLINE PET EARNINGS: server -> client, the OFFER ("your pets earned X coins OR Y pet levels while you were away").
local OfflineEarningsEvent = getOrCreate(RS, "RemoteEvent", "OfflineEarningsEvent")
-- client -> server, the player's CHOICE only ("coins" | "levels"). The server owns the amounts -- see the claim
-- handler: a client can never send a number, only pick which of the two rewards the server already computed.
local OfflineClaimEvent    = getOrCreate(RS, "RemoteEvent", "OfflineClaimEvent")

local ISLAND_DISPLAY_NAMES = {
	"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil",
	"Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle",
	"Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff",
	"Burrito Barrens","Pizza Palms"
}

-- FOOD -- prices and powers copied from the F2F UNIVERSAL PROGRESSION GUIDE (the Dinosaur Realm's
-- shipped menu), one food per island. Foods come in identical PAIRS; Pizza extends the top pair
-- because our tower has 14 islands to the guide's 13.
--
-- THE CRITICAL RULE: power/price is monotonically NON-DECREASING up the tower (0.0250 -> 0.0422,
-- a 1.69x spread), and power is non-decreasing too. Later food is never worse value, so buying
-- "ahead" is never a trap and buying "behind" is never optimal. A retune that breaks either
-- ordering re-creates the old "Popcorn costs 600 and Pizza 518" problem.
--
-- Every meal past the tutorial is <= 18% of what its own crossing pays out, and the player can
-- afford the intended food on FLIGHT 1 of every crossing -- the check whose absence sank a build.
-- IDENTICAL table in CoreClient.client.lua -- if you change one, change both.
local foods = {
	{name="Beans",    price=1280, power=32,  island=1},
	{name="Broccoli", price=1480, power=40,  island=2},
	{name="Cabbage",  price=1480, power=40,  island=3},
	{name="Turnips",  price=1520, power=45,  island=4},
	{name="Coconuts", price=1520, power=45,  island=5},
	{name="Bread",    price=1720, power=55,  island=6},
	{name="Pasta",    price=1720, power=55,  island=7},
	{name="Popcorn",  price=1840, power=65,  island=8},
	{name="Milk",     price=1840, power=65,  island=9},
	{name="Butter",   price=2200, power=85,  island=10},
	{name="IceCream", price=2200, power=85,  island=11},
	{name="Burger",   price=3080, power=130, island=12},
	{name="Burrito",  price=3080, power=130, island=13},
	{name="Pizza",    price=3080, power=130, island=14},
}

-- FOOD STANDS ARE ALL UNLOCKED. Every stand sells all 14 foods to everybody, from the first join.
--
-- Two gates used to sit on top of the coin price, and BOTH are gone:
--   1. this one -- a PET QUEST lock on the 5 quest islands (Broccoli Bluff 2, Coconut Cove 5, Popcorn 8,
--      Butter Swamp 10, Burrito Barrens 13): the stand stayed shut until you owned that island's pet;
--   2. an ISLAND-REACHED lock in the shop clients (see isUnlocked in ShopClient / Shop_AllInOne).
--
-- THE PRICE IS THE GATE NOW. Beans 10 -> Pizza 900,000 is a 90,000x spread, and coins come from HEIGHT --
-- so you still cannot skip ahead: reaching a food you can afford is the same climb it always was. What is
-- gone is being told 'no' at a stand you already flew to.
--
-- NOTE FOR BALANCE: this removes two brakes on the 65-70 minute target in CLAUDE.md. Pet quests are now
-- optional content rather than a required step in the climb -- worth re-timing island 1->2 and the 3 min
-- per-island baseline before launch.
--
-- Kept as a function returning true (rather than deleting the call site) so there is ONE obvious place to
-- put a gate back if the pacing needs it.
local function foodStandUnlocked()
	return true
end

-- GUTS -- tanks, costs and unlock islands copied from the F2F UNIVERSAL PROGRESSION GUIDE.
-- maxPower MUST equal FlightTuning.BASE_TIERS row for row: the tank size IS the climb lookup.
--
-- Every gut covers exactly TWO crossings: a WALL (the gap is 2% past the previous gut's full-tank
-- reach, so you get 97%+ of the way and still cannot land) and a STRETCH (97% of the new tank).
-- That is why `island` steps by 2: a gut unlocks on the island where the previous gut runs out.
--   Tiny   120 -> climb  853.5  covers c1            (tutorial, 1.355x headroom)
--   Small  270 -> climb 1279.5  covers c2 + c3       unlocks at island 2
--   Medium 470 -> climb 1848.0  covers c4 + c5       unlocks at island 4
--   Large  620 -> climb 2559.0  covers c6 + c7       unlocks at island 6
--   XL    1080 -> climb 3555.0  covers c8 + c9       unlocks at island 8
--   XXL   1710 -> climb 4977.0  covers c10 + c11     unlocks at island 10
--   Iron  2600 -> climb 7110.0  covers c12 + c13     unlocks at island 12
--
-- Each gut costs LESS than the crossing before its wall pays out, so saving for it is short. Costs
-- are strictly increasing. A purchased gut arrives EMPTY (see BuyStomachEvent).
--
-- Infinite Gut is deliberately island = 1: it is the Robux tier, and refusing a real-money
-- purchase to a new player is worse than letting them skip ahead.
--
-- The COST still gates as it always did; `island` is a second, separate lock, so banked coins
-- alone cannot buy a gut for a stretch of the game the player has not seen.
local stomachTiers = {
	{name="Tiny Gut",     maxPower=120,  cost=0,      robux=false, island=1},
	{name="Small Gut",    maxPower=270,  cost=1000,   robux=false, island=2},
	{name="Medium Gut",   maxPower=470,  cost=2000,   robux=false, island=4},
	{name="Large Gut",    maxPower=620,  cost=4000,   robux=false, island=6},
	{name="XL Gut",       maxPower=1080, cost=5000,   robux=false, island=8},
	{name="XXL Gut",      maxPower=1710, cost=6000,   robux=false, island=10},
	{name="Iron Gut",     maxPower=2600, cost=11500,  robux=false, island=12},
	{name="Infinite Gut", maxPower=9999, cost=499,    robux=true,  island=1},
}

local ISLAND_NAMES = {
	"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs",
	"Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard",
	"Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh",
	"Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff",
	"Island_13_BurritoBarrens","Island_14_PizzaPalms"
}

-- Island positions live in ONE place: ReplicatedStorage.Shared.IslandOrder (the client reads the
-- same table for gaps and coin payouts). Same {x,y,z} shape every use below always had.
local IslandOrder = require(RS:WaitForChild("Shared"):WaitForChild("IslandOrder"))
local FlightTuning = require(RS:WaitForChild("Shared"):WaitForChild("FlightTuning"))
local ISLAND_POSITIONS = IslandOrder.SLOT_POS

-- PURE VISUAL Y-axis rotation per island (degrees), applied about the island's CENTER
-- AFTER it's positioned -- so the WHOLE model (stand, shop, paths, props, decorations,
-- any child NPCs) spins together and stays aligned, with NO change to height or position.
-- A Y rotation never changes any part's Y, so heights are untouched. Negative degrees =
-- CLOCKWISE viewed from above (Roblox +Y rotation is counter-clockwise from the top).
-- Stand detection runs AFTER this, so the stand/shop are found at their rotated spots and
-- still work. [3]=Cabbage Cliffs 180, [5]=Coconut Cove 180, [7]=Pasta Peak 90 clockwise.
local ISLAND_ROTATIONS = {
	[3] = 180,   -- Cabbage Cliffs: 180 around Y
	[5] = 180,   -- Coconut Cove: 180 around Y
	[7] = -90,   -- Pasta Peak: 90 CLOCKWISE around Y (top-down "3 -> 6 on a clock")
}

-- GAMEPASS IDS now come from the SHARED module (ReplicatedStorage.Shared.Gamepasses) instead of a seventh
-- hand-copied table. Same shape as the literal that used to sit here, so every use below reads unchanged --
-- but adding a pass is now a one-line edit in ONE file rather than a six-file sweep that has already drifted
-- (the three client copies of this table are still missing InfiniteGut).
--
-- Passes with id 0 are NOT YET CREATED and are skipped by the `id ~= 0` guard in the ownership loop below, so
-- an unconfigured pass is never sent to Roblox and can never be owned.
local Gamepasses = require(RS:WaitForChild("Shared"):WaitForChild("Gamepasses"))
local GAMEPASS_IDS = Gamepasses.IDS

-- [STOMACH RESET] \xE2\x9A\xA0 TEMPORARY: while TRUE, EVERY player is forced to the BASE starting gut -- ALL gut/stomach
-- upgrades read as UN-OWNED: Infinite Gut never auto-applies on join OR purchase (applyInfiniteGut no-ops), a stored
-- 9999 / any saved tier is forced back to the base StomachMax on load, and HasInfiniteGut stays false so the meter
-- never locks full. The real on-disk StomachMax is PRESERVED through save (the save writes back the loaded disk value,
-- NOT the forced base), so flipping this FALSE cleanly restores everyone's real gut (Infinite Gut owners also re-get
-- it live from UserOwnsGamePassAsync). Players can still buy coin tiers via BuyStomachEvent. Set FALSE to restore.
local FORCE_BASE_STOMACH = true
local loadedStomachMax = {} -- [player] = the StomachMax value read from disk on load (preserved through save while forced)

-- INFINITE / UNLIMITED GUT gamepass (1860686821): applies the Infinite Gut tier (StomachMax = 9999, the
-- top tier — no practical power cap, so the "stomach full" check effectively never fires). Used BOTH on
-- a fresh purchase (PromptGamePassPurchaseFinished) AND, since it's a forever pass, on every join when
-- UserOwnsGamePassAsync is true. Same mechanism a normal gut buy uses (set StomachMax, carry the power
-- already in the tank, notify the client) so the gut label + meter capacity stay correct. Idempotent:
-- if they're already at Infinite Gut it no-ops. Touches ONLY this player's stomach — no coins, no other
-- tiers, no other system.
local INFINITE_GUT_MAX = 9999
-- `force` is the DEV path only (/infinitegut). FORCE_BASE_STOMACH is a balance-test switch that pins every gut
-- to base, which also makes this a no-op on join and on a real purchase -- so without a bypass the dev command
-- would appear to do nothing at all. Every other caller passes no argument and is gated exactly as before.
local function applyInfiniteGut(player, force)
	if not player then return end
	if FORCE_BASE_STOMACH and not force then print("[STOMACH RESET] applyInfiniteGut SKIPPED for "..player.Name.." (FORCE_BASE_STOMACH on -- gut stays base)"); return end -- never grant the Infinite Gut tier while the reset is on (join or purchase)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local sm = ls:FindFirstChild("StomachMax"); if not sm then return end
	-- Flag ownership FIRST. The client reads HasInfiniteGut to lock the fart meter full (never drains), so
	-- every owner must be flagged on join/purchase regardless of their saved gut (a returning owner loads with
	-- StomachMax already at 9999). applyInfiniteGut is only ever called for actual owners (join
	-- UserOwnsGamePassAsync + purchase), so non-owners never get the flag and are entirely unaffected.
	player:SetAttribute("HasInfiniteGut", true)
	-- Promote the gut to the Infinite tier if it isn't already (only the MAX grows). Notify the client of the
	-- new gut label ONLY when it actually changes, so already-Infinite returning owners aren't re-notified.
	if sm.Value < INFINITE_GUT_MAX then
		sm.Value = INFINITE_GUT_MAX
		local nameStr = "Infinite Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == INFINITE_GUT_MAX then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, INFINITE_GUT_MAX, nameStr) end)
	end
	-- INSTANT-FULL METER (on PURCHASE and on JOIN): Infinite Gut's tank is ALWAYS full, so jump CurrentPower
	-- straight to the gut max regardless of what it was — even from 0 power / 0 coins (no clamp to the old
	-- fill, no early-return). Setting the SERVER CurrentPower makes it AGREE with the client's full/never-drain
	-- meter and stick through the decrease-only landing sync (same lesson as the recharge / bird-nuke fixes).
	-- RegenEvent shows the client bar full IMMEDIATELY. Runs for returning owners too, so they top to full on spawn.
	local cp = ls:FindFirstChild("CurrentPower")
	if cp then cp.Value = sm.Value end -- full tank = StomachMax (= INFINITE_GUT_MAX)
	pcall(function() RegenEvent:FireClient(player, 0, sm.Value, sm.Value) end)
	print("INFINITE GUT applied to "..player.Name.." (StomachMax="..sm.Value..", CurrentPower=FULL)")
end

-- [REMOVE BEFORE LAUNCH] Dev grant for /infinitegut. Bypasses FORCE_BASE_STOMACH (see above) and otherwise runs
-- the IDENTICAL path a real gamepass purchase takes -- same attribute, same tier promotion, same full-meter sync.
_G.devGrantInfiniteGut = function(player)
	applyInfiniteGut(player, true)
end

local PRODUCT_IDS  = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, BirdNuke=3600303082}

-- COIN PACKS: productId -> coins granted.
--
-- The AMOUNT LIVES HERE, on the server, and nowhere else that matters. ShopClient has its own copy of this
-- list, but only for what to draw on the card -- if the two ever disagree the client is simply wrong about
-- the label and the player still gets exactly what this table says. A coin amount read from the client is
-- an amount the client can choose.
--
-- Until this file knew about them, these packs had ids on the buy button and NO branch in ProcessReceipt:
-- the prompt would open, Roblox would take the Robux, the receipt would fall through to NotProcessedYet,
-- and the player would get nothing while Roblox retried the same dead receipt on every future join. An
-- unhandled product id is not an inert placeholder -- it is a charge with no delivery.
local COIN_PACKS = {
	[3699050724] = 1000,      -- Small     49 R$
	[3699055852] = 5500,      -- Medium    99 R$
	[3699059563] = 12000,     -- Large     199 R$
	[3699065394] = 30000,     -- Giant     399 R$
	[3699081248] = 70000,     -- Mega      799 R$
	[3699076690] = 180000,    -- Ultimate  1499 R$
}
-- 2x Fart Power pass/product: with it active, each food is worth this multiple of its power as
-- REAL flight fuel, and the effective stomach tank grows by the same multiple. (Client mirrors
-- this constant in CoreClient.client.lua for the gas-meter / flight math.)
-- 2.0, because the thing is called "2x Fart Power" on the button a player pays for. It was 1.4 -- a 40%
-- boost sold as a doubling, which is the kind of gap that gets a game reported rather than refunded.
local POWER_PASS_MULT = 2.0
-- [TESTING] Flip back to false to re-enable the 2x boost in Studio. When true AND running in Studio,
-- the has2x check is forced false so food gives normal 1x power (ignores HasTwoXForever / TwoXHourExpiry).
-- The LIVE game is unaffected (IsStudio() is false there).
-- OFF too, so the boost can actually be verified in Studio. With this true, testing the thing you just
-- paid to fix silently does nothing and looks like the fix failed.
local DISABLE_2X = false
-- ============================================================================================
-- [BALANCE TESTING] MASTER NO-PERKS SWITCH. While TRUE, the game ignores ALL gamepass/product
-- perks even if the player owns them, so the playthrough reflects a brand-new player with no perks:
--   • 2x Fart Power (TwoXForever gamepass AND the 2x 1-hour product) -> food gives NORMAL 1x power
--     (e.g. Beans = 8, not 11). Both the server power math and the client's gas/flight math follow.
--   • Glitter Trail -> off (client gets an all-false gamepass state).
--   • Skip Island -> the effect is ignored (no skipping).
--   • Mid-Air Recharge -> n/a (it has no active flight effect in the current code).
-- Works in Studio AND the live game. Flip to FALSE to restore all perks after the test.
-- (This supersedes DISABLE_2X above, which was Studio-only.)
-- ============================================================================================
local DISABLE_PERKS_FOR_BALANCE = false
-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- REMOVE BEFORE LAUNCH. While TRUE, the "2x Fart Power Forever" gamepass (TwoXForever)
-- reads as NOT owned for EVERY player regardless of saved data / actual ownership: the join ownership check is forced
-- false, HasTwoXForever is cleared, a fresh purchase won't grant it, and the has2x effect is forced off -- so NO player
-- gets the 2x power boost for now. (Targets ONLY the 2x pass; Glitter/Skip/Infinite Gut are untouched.) Set FALSE to restore.
-- OFF. While this was true the 2x pass and the 1-hour product were BOTH inert for every player: ownership
-- read false on join, HasTwoXForever was cleared, a fresh purchase granted nothing, and has2x was forced
-- false at the point of use. Anybody who bought either one got exactly nothing for their Robux.
local FORCE_NO_2X = false
if FORCE_NO_2X then print("[NOSAVE TEST] 2xFart forced un-owned.") end
-- [BALANCE TESTING] While TRUE, NO random server-wide events fire (FART_STORM, COIN_RUSH, LOW_GRAVITY,
-- POWER_SURGE, RING_FEVER, THUNDERSTORM, WINDSTORM). Set to false to re-enable random events later.
-- (Ambient bird swarms are gated by a matching DISABLE_EVENTS flag in EventClient.client.lua — keep
-- the two in sync. The Bird Nuke PRODUCT is unaffected and still works.)
local DISABLE_EVENTS = false
-- (Daily Rewards feature removed entirely -- reward tables, claim logic, and the DailyRewards_v1 store deleted.)
local playerCoinAccum = {}
-- CoinEvent anti-exploit budget. [player] = { t = window start (os.clock), spent = coins, calls = n }.
-- Sized against the real worst cases in the CoinEvent handler -- read the comment there before retuning,
-- because the flat allowance exists to cover ring bonuses and cutting it will silently rob players.
local coinWindow       = {}
local COIN_WINDOW      = 5      -- seconds per budget window
local COIN_MAX_CALLS   = 60     -- calls per window. Legit is ~4.3/s (COIN_TICK 0.23) + ring bursts.
local COIN_MAX_SINGLE  = 8000   -- no single grant may exceed this. Worst legit tick: an Iron Gut falling
                                -- at terminal speed pays ~5.4k per 0.23s tick during COIN_RUSH. Rings ~1,650.
local COIN_FLAT_BUDGET = 5000   -- coins per window allowed for ANY gut (this is the ring allowance)
-- Plus, per window, the MOST one whole flight on this player's gut can legitimately pay: a failed
-- flight is climb * COIN_PER_STUD * (1 + DESCENT_PAY_MULT), doubled for COIN_RUSH. A flight is never
-- shorter than a window, so no honest window can exceed one flight's total. Computed from the
-- server's own StomachMax in the handler -- the client cannot inflate it.
local COIN_EVENT_PEAK  = 2
local GamepassEvent = nil
task.spawn(function() GamepassEvent = RS:WaitForChild("GamepassEvent", 10) end)
local BirdNukeEvent = nil
task.spawn(function() BirdNukeEvent = RS:WaitForChild("BirdNukeEvent", 10) end)

-- DataStore init is after island task.spawns are queued so islands set up even if DataStore fails
local playerDataStore = nil
pcall(function()
	local DataStoreService = game:GetService("DataStoreService")
	playerDataStore = DataStoreService:GetDataStore("PlayerData_v1")
end)
print("NOTE: Enable Studio API Access in")
print("Game Settings > Security for")
print("DataStore to work in Studio")

-- ===== PLAYER DATA PERSISTENCE (DataStore "PlayerData_v1", keyed by UserId) =====
-- Persists coins, gut tier (StomachMax), island/unlock progression (Island) and home base
-- (highestIslandReached). Gamepass ownership is NOT saved — it's read live each join via
-- UserOwnsGamePassAsync. All DataStore calls are pcall'd, and a player is NEVER saved unless their
-- load succeeded (dataLoaded), so a failed load can't overwrite real progress with defaults.
local highestIslandReached = {}   -- [player] = highest island reached (home base). Declared here so save/load can use it.
-- Per-player forever-gamepass ownership, computed once on join (NEVER saved) so the on-ready handshake
-- can re-send it reliably. gamepassReady flips true once the (async) ownership check has finished.
local gamepassState = {}          -- [player] = { twoXForever=bool, glitterTrail=bool }
local gamepassReady = {}          -- [player] = true once the on-join ownership check completed
-- PERMANENT TEST ACCOUNT: this UserId never loads/saves (always a brand-new player every join).
local TEST_ACCOUNT_USERID = 1086836724  -- lando5485
-- \xE2\x9A\xA0 TEST: shared allow-list for ALL test/debug features (test chat commands AND the island-select
-- all-islands-unlock below). Matched by USERNAME (case-insensitive). Defined early so every handler can use
-- it. REMOVE BEFORE LAUNCH.
local ALLOWED_TEST_USERS = { ["lando5485"] = true, ["broskie310111"] = true,
	["itsmaddmax1"] = true, ["itsmaddmax2"] = true } -- \xE2\x9A\xA0 REMOVE BEFORE LAUNCH
local function isAllowedTestUser(player) -- \xE2\x9A\xA0 TEST: shared gate for all test/debug features. REMOVE BEFORE LAUNCH.
	local key = string.lower(player.Name)
	if ALLOWED_TEST_USERS[key] == true then return true end
	-- Say WHY, and print the exact key that was compared. A bare `return` makes 'your username isn't what
	-- you think it is', 'the entry is missing' and 'the command never reached the server' all look
	-- identical in the log. Matched on Name (the @username), NOT DisplayName -- the usual culprit.
	print(string.format("[TEST] DENIED '%s' (UserId %d) -- not in ALLOWED_TEST_USERS. Add exactly this "
		.. "lower-cased key to the list in PlayerStats.", key, player.UserId))
	return false
end
_G.isAllowedTestUser = isAllowedTestUser -- \xE2\x9A\xA0 TEST: shared with PetSystem (pet-skip test path). REMOVE BEFORE LAUNCH.
-- =====================================================================================================
-- \xE2\x9A\xA0 FRESH PLAYER TEST OVERRIDE (Broskie310111) -- TEMPORARY. SET false / DELETE THIS BLOCK BEFORE LAUNCH.
-- When FRESH_PLAYER_TEST is true, the player whose UserId == FRESH_PLAYER_USERID loads as a BRAND-NEW
-- player (new-player DEFAULTS below), ALL their gamepasses are VOIDED for the session, and NOTHING is
-- saved for them -- so their REAL data on disk is left untouched and is restored simply by flipping this
-- flag back to false. (Hooks live in fetchPlayerData, savePlayerData, and the join gamepass loop.)
--
-- New-player DEFAULTS a fresh account gets (from DEFAULT_COINS/STOMACH/ISLAND + the load path below):
--   coins = 25, StomachMax = 100 (Tiny Gut), Island = 1, CurrentPower/fartMeter = 0,
--   TotalFartPower = 0, TotalCoinsEarned = 0, HighestIsland = 1, no gamepasses.
--
-- ===== BROSKIE RESTORE DATA (current saved state on disk, recorded BEFORE the override) =====
--   UserId / DataStore key (PlayerData_v1): 1418148401
--   From F9 save logs:  coins = 2,  highestIsland = 13,  stomachMax = 9999 (Infinite Gut tier),  saveVersion = 4
--   Owned gamepasses (inferred from stomachMax 9999): Infinite Gut; plus whatever else UserOwnsGamePassAsync reports live.
--   NOT captured in the logs (island, totalFartPower, totalCoinsEarned, fartMeter): these are UNCHANGED on
--   disk -- because saving is DISABLED for this user in fresh mode, the real save is never overwritten, so
--   the full record (including these fields) survives intact. RESTORE = just set FRESH_PLAYER_TEST = false.
-- =====================================================================================================
-- \xE2\x9A\xA0\xE2\x9A\xA0 THE THREE FLAGS BELOW ARE DEAD CODE. READ THIS BEFORE TRUSTING THE COMMENTS ABOVE THEM.
--
-- FRESH_PLAYER_TEST, SPAWN_AT_PIZZA_PALMS_TEST and FRESH_PLAYER_USERID are DECLARED HERE AND NEVER READ
-- ANYWHERE IN THIS FILE. Every "fresh start" this game has been doing came from DISABLE_SAVE_FOR_TESTING
-- further down, which applied to EVERY player, not to one account.
--
-- That matters because the block above promises "Saving stays DISABLED for this user (real data
-- preserved)". It does not, and it never did -- there is no per-user save gate. With save/load now back ON,
-- anyone reading that promise would believe Broskie310111's record is protected while it is being written
-- to normally like everybody else's.
--
-- Left in place rather than deleted so the restore notes above stay findable, but they change NOTHING at
-- runtime. If you want a single account to load fresh, it has to be written -- flipping these does nothing.
local FRESH_PLAYER_TEST = true          -- DEAD: never read. See the warning above.
local FRESH_PLAYER_USERID = 1418148401  -- Broskie310111 (DataStore PlayerData_v1 key)
-- \xE2\x9A\xA0 SPAWN-AT-PIZZA-PALMS TEST (Broskie310111) -- TEMPORARY. SET false / REMOVE BEFORE LAUNCH.
-- When true, this SUPERSEDES FRESH_PLAYER_TEST for Broskie's account: instead of loading island-1 fresh
-- defaults, they load with Island 14 (Pizza Palms) unlocked + huge test gas/stomach so they can fly up
-- to the black hole. Saving stays DISABLED for this user (real data preserved), exactly like fresh mode.
-- To revert: set this false (back to fresh mode) or set BOTH test flags false (back to real state).
local SPAWN_AT_PIZZA_PALMS_TEST = true  -- DEAD: never read. See the warning above FRESH_PLAYER_TEST.
-- FART-METER PERSISTENCE: lastMeter = the player's last-known live meter (snapshotted on meter changes,
-- so a respawn/cleanup that zeros CurrentPower can't make us SAVE a stale 0). joinRestoreMeter = the
-- saved meter to re-apply AFTER the player's first spawn settles (the spawn's onLand zeros CurrentPower,
-- which is decrease-only, so the load must be re-applied server-side post-spawn).
local lastMeter = {}              -- [player] = last-known meter to SAVE
local joinRestoreMeter = {}       -- [player] = saved meter to RESTORE after first spawn
-- PET OWNERSHIP (cosmetic). Persisted in PlayerData_v1 under saved.ownedPets and shared with
-- PetSystem.server.lua (which reads/writes this table on claim); PlayerStats just persists it.
-- e.g. _G.playerOwnedPets[player] = { BroccoliPet = true }. Loaded into here on join, saved on save.
_G.playerOwnedPets = _G.playerOwnedPets or {}
-- Equipped-pet choice (cosmetic, additive). Persisted under saved.equippedPet; shared with PetSystem.
_G.playerEquippedPet = _G.playerEquippedPet or {}
-- GUT SKINS (cosmetic, additive). owned = { Default=true, ... }; equipped = skin id. Shared with GutSkinService;
-- PlayerStats just persists them (saved.ownedGutSkins / saved.equippedGutSkin).
_G.playerOwnedGutSkins = _G.playerOwnedGutSkins or {}
_G.playerEquippedGutSkin = _G.playerEquippedGutSkin or {}
-- TOTAL cumulative playtime in SECONDS (all sessions). GutSkinService increments + auto-grants playtime skins;
-- PlayerStats just persists it (saved.playtimeSeconds). Single source of truth lives on the server.
_G.playerPlaytimeSec = _G.playerPlaytimeSec or {}
-- PET SKIN CRATES (cosmetic, additive). Owned by SkinCrateService, which is the ONLY script that writes them;
-- PlayerStats just persists them (saved.crateTokens / saved.petSkins / saved.equippedSkins).
--   playerCrateTokens[player]   = number                    -- the COSMETIC currency. Never Food Coins.
--   playerPetSkins[player]      = { ["Pet|Skin|Trait"]=n }  -- one entry per pet+skin+trait, n = duplicates stacked
--   playerEquippedSkins[player] = { Pet = {skin=,trait=} }  -- which skin each pet is wearing
-- Declared here as well as in SkinCrateService because server script load ORDER is not guaranteed: if this join
-- handler ran before that service had created the tables, indexing them would error out the whole load path.
_G.playerCrateTokens   = _G.playerCrateTokens   or {}
_G.playerPetSkins      = _G.playerPetSkins      or {}
_G.playerEquippedSkins = _G.playerEquippedSkins or {}
--   playerCollection[player]    = { completedPets, titles, auras, activeTitle, activeAura, full }
--       Collection Book progress + the badge/title/aura rewards it pays out. Derived from petSkins, but stored
--       rather than recomputed so a reward already announced is never announced twice, and so a title the player
--       chose survives a rejoin.
_G.playerCollection    = _G.playerCollection    or {}
-- Discovered pet QUESTS (cosmetic, additive). Persisted under saved.discoveredQuests; shared with PetSystem.
_G.playerDiscoveredQuests = _G.playerDiscoveredQuests or {}
-- PERMANENT "ever completed pet quest X" flags (additive). Persisted under saved.everCompletedQuests; shared
-- with PetSystem. Used ONLY to gate the first-time-only rare roll (separate from current ownership). Missing = never completed.
_G.playerEverCompletedQuests = _G.playerEverCompletedQuests or {}
-- COLLECTION MILESTONES already paid out + the earned TITLE (Pet Hub collection rewards; owned by PetSystem, which
-- awards them). Declared here too because server script load ORDER is not guaranteed -- if PlayerStats' join handler
-- ran before PetSystem had created these tables, indexing them would error out the whole load path.
_G.playerPetMilestones = _G.playerPetMilestones or {}  -- [player] = { ["3"]=true, ... } (string keys: JSON-safe)
_G.playerTitle = _G.playerTitle or {}                  -- [player] = "Beastmaster" (mirrored to the "Title" attribute)
local DEFAULT_COINS, DEFAULT_STOMACH, DEFAULT_ISLAND = 2000, 120, 1 -- new player: 2,000 coins (a 3-rung tutorial ladder off the bank against a 1,280 first meal), Tiny Gut (120), island 1
print("[RESET] new-player defaults: coins=25, stomach=base, gamepasses=owned-only, islands=locked-to-1, test grants removed.")
-- SAVE RECORD VERSION. ONE-TIME WIPE: bumped to 4. On load, any record whose saveVersion ~= SAVE_VERSION
-- (old records have no saveVersion field at all -> nil; version-2 AND version-3 records from the prior
-- wipes also no longer match) is treated as a brand-new player (defaults: 25 coins, Tiny gut, island 1,
-- no saved meter), then re-saved at this version. After this, normal saving resumes — post-wipe records
-- load normally. This is a ONE-TIME action: the version stays at 4; we do NOT reset on every join.
local SAVE_VERSION = 4
local AUTOSAVE_INTERVAL = 90      -- seconds between autosaves
local dataLoaded = {}             -- [player] = true once load succeeded & applied; gates ALL saves
-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- REMOVE BEFORE LAUNCH. While TRUE, save/load is DISABLED for EVERY player: every
-- join starts as a brand-NEW player (forced 25 coins, island 1, Tiny Gut 100, fart power 0/100, highestIslandReached 1)
-- and NOTHING is ever written to the DataStore -- the join load is skipped, and the autosave / PlayerRemoving /
-- BindToClose saves are all skipped (they route through savePlayerData). Flip to false to restore normal save/load.
--======================================================================
-- \xE2\x9A\xA0\xE2\x9A\xA0  THE ONE SWITCH THAT MUST BE FLIPPED BEFORE LAUNCH  \xE2\x9A\xA0\xE2\x9A\xA0
--======================================================================
-- KEPT ON DELIBERATELY. Every join starts as a brand-new player (25 coins, island 1, Tiny Gut) and NOTHING
-- is written to the DataStore, which is what you want while testing the opening minutes over and over.
--
-- It is also the single most destructive thing that can ship. Live, this means every player's progress is
-- silently thrown away the moment they leave -- they come back to 25 coins, having lost everything, forever.
-- There is no recovery from a session of that, because nothing was ever written to recover.
--
-- SET THIS TO false BEFORE PUBLISHING. It is one word, and it is the difference between a game that keeps
-- progress and a game that does not.
local DISABLE_SAVE_FOR_TESTING = true
if DISABLE_SAVE_FOR_TESTING then
	warn("==================================================================")
	warn("[NOSAVE] SAVING IS DISABLED FOR EVERY PLAYER -- progress is thrown")
	warn("[NOSAVE] away on leave. This is a TESTING mode. Set")
	warn("[NOSAVE] DISABLE_SAVE_FOR_TESTING = false before you publish.")
	warn("==================================================================")
end
-- [TEST — ONE-TIME FULL DATA CAPTURE] While TRUE: the player joins with ~unlimited coins (9,999,999)
-- and can buy/switch to ANY stomach tier (Tiny..Iron) from the shop for FREE (cost/coins ignored), so
-- every tier's full-tank reach can be sampled in a single run with no grinding. This ONLY removes the
-- coin constraint — flight physics, island positions, food costs, and earn rate are unchanged. Use
-- alongside DISABLE_SAVE (so the 9,999,999 never persists). Flip to false to restore normal economy.
local TEST_FULL_DATA = false
local TEST_FULL_DATA_COINS = 9999999
-- [BALANCE LOGGING] per-session attempt tracking (logging only, no gameplay effect).
local sessionFlights = {}         -- [player] = total flights this session (one per landing)
local strandGrantFlight = {}      -- [player] = sessionFlights value at the last anti-strand top-up (one per landing)
local flightsSinceNewIsland = {}  -- [player] = flights since the last NEW island was reached
local attemptsPerIsland = {}      -- [player] = { [islandNum] = attempts it took to reach that island }
-- [BALANCE LOGGING] additional per-session tracking (logging only, no gameplay effect).
local sessionStartTime = {}       -- [player] = os.clock() at join (for real playtime)
local islandReachTime = {}        -- [player] = { [islandNum] = playtime(s) when that island was reached }
local playtimeAtLoad = {}         -- [player] = their SAVED cumulative playtime at the moment they joined

-- LIVE cumulative playtime, in seconds, across every session the player has ever had.
--
-- NOT the same as _G.playerPlaytimeSec, which GutSkinService bumps by 60 once a minute -- that is fine for
-- unlocking skins, but it is only accurate to the nearest minute, and the FASTEST CLIMB leaderboard ranks people
-- against each other by this number. So it is computed live instead: saved total + real seconds this session.
-- Exposed on _G because LeaderboardService needs the same number and must not re-derive it differently.
local function totalPlaytimeSec(p)
	local base    = playtimeAtLoad[p] or _G.playerPlaytimeSec[p] or 0
	local session = sessionStartTime[p] and (os.clock() - sessionStartTime[p]) or 0
	return math.floor(base + session)
end
_G.playerTotalPlaytime = totalPlaytimeSec
_G.playerIslandTimeSec = _G.playerIslandTimeSec or {} -- [player] = playtime(s) at which they reached their HIGHEST island
local lastIslandReachClock = {}   -- [player] = os.clock() when the previous island was reached (for per-island time)
local coinsAtLastIsland = {}      -- [player] = TotalCoinsEarned snapshot at the previous island (for per-island earned)
local islandCoinsEarned = {}      -- [player] = { [islandNum] = coins earned on the way to that island }
local coinsSpentOnFood = {}       -- [player] = total coins spent on food
local coinsSpentOnGuts = {}       -- [player] = total coins spent on guts
local gutPurchases = {}           -- [player] = { {name, island, time, flight}, ... }
local gutBoughtSinceIsland = {}   -- [player] = true if a gut was bought since the previous island (per-island flag)
local saveGateFlights = {}        -- [player] = { [islandNum] = count of save-gate flights toward that island }
local reachFlights = {}           -- [player] = { [islandNum] = count of trying-to-reach flights toward that island }
local saveGateAccum = {}          -- [player] = save-gate flights accumulated since the last new island
local reachAccum = {}             -- [player] = trying-to-reach flights accumulated since the last new island
local gutAtIsland = {}            -- [player] = { [islandNum] = StomachMax when that island was reached }
local birdEncounters = {}         -- [player] = total bird hits this session (from LandingEvent 2nd arg)
local flightsOfSaving = {}        -- [player] = flights since the last gut purchase (for BOUGHT GUT log)
-- server-wide event tracking (the event loop fires events for everyone)
local eventsFiredCount = 0        -- total server events fired this server's lifetime
local eventsFiredTally = {}       -- { [eventName] = count }

-- Returns: "ok",<table|nil> (loaded data, or nil = brand-new player) | "nostore",nil (DataStore
-- unavailable, e.g. Studio API off — run on defaults, don't persist) | "fail",nil (GetAsync errored
-- every retry — caller must NOT hand out a fresh save that could overwrite real data).
local function fetchPlayerData(player)
	-- [RESET] All per-user TEST overrides removed (permanent-reset account, Spawn-at-Pizza-Palms island-14/99999
	-- stomach, Fresh-Player / Fresh-Player-2 forced new-player + gamepass void). Every player now loads their REAL
	-- save below, or new-player DEFAULTS (25 coins / Tiny Gut 100 / island 1, no gamepasses) if they have none.
	if DISABLE_SAVE_FOR_TESTING then
		print("LOAD: "..player.Name.." SKIPPED (DISABLE_SAVE_FOR_TESTING) — starting as a brand-new player (defaults)")
		return "ok", nil -- "ok" + nil = brand-new player -> defaults applied (25 coins, island 1, Tiny Gut)
	end
	-- ⚠ TEST: broskie310111 and lando5485 ALWAYS load as brand-new players, even on a live server (so they
	-- see the new-player experience -- locked realms, fresh coins, island 1). REMOVE BEFORE LAUNCH.
	if isAllowedTestUser(player) then
		print("LOAD: "..player.Name.." forced BRAND-NEW (test account -- always a fresh player)")
		return "ok", nil
	end
	local key = tostring(player.UserId)
	print("LOAD: "..player.Name.." attempting load (key="..key..", store=PlayerData_v1)")
	if not playerDataStore then
		print("LOAD: FAILED - playerDataStore is nil (DataStore service unavailable / API access off)")
		return "nostore", nil
	end
	local lastErr
	for attempt = 1, 4 do
		local ok, result = pcall(function() return playerDataStore:GetAsync(key) end)
		if ok then return "ok", result end
		lastErr = result
		print("LOAD: attempt "..attempt.."/4 errored - "..tostring(result))
		task.wait(2)
	end
	print("LOAD: FAILED - "..tostring(lastErr))
	return "fail", nil
end

-- Save current progress. No-ops unless the load succeeded (dataLoaded) and the store exists, so a
-- failed/never-loaded player can't wipe their save. pcall'd.
local function savePlayerData(player, trigger)
	trigger = trigger or "?"
	-- [RESET] per-user save-disable special-casing removed (lando5485 permanent reset, Broskie fresh-test
	-- skips) -- saving now works normally for EVERY player.
	if DISABLE_SAVE_FOR_TESTING then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED (DISABLE_SAVE_FOR_TESTING) — test runs are not persisted")
		return
	end
	-- ⚠ TEST: broskie310111 and lando5485 never persist, so their fresh-start session can't overwrite a real
	-- save and they stay "always new" next join too. REMOVE BEFORE LAUNCH.
	if isAllowedTestUser(player) then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED (test account -- always a fresh player, never saved)")
		return
	end
	if not playerDataStore then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - no DataStore"); return
	end
	if not dataLoaded[player] then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - data never loaded (won't overwrite real save)"); return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		print("SAVE ("..trigger.."): "..player.Name.." SKIPPED - no leaderstats"); return
	end
	local function val(n, d) local s = ls:FindFirstChild(n); return (s and s.Value) or d end
	-- FART METER to save: use the snapshotted last-known meter (updated on meter changes) so a respawn/
	-- cleanup that just zeroed the live CurrentPower can't make us persist a stale 0. Fall back to the
	-- live leaderstat if no snapshot yet. Clamp defensively to the gut max.
	local gutMaxNow = val("StomachMax", DEFAULT_STOMACH)
	local meterToSave = math.clamp(math.floor(lastMeter[player] or val("CurrentPower", 0)), 0, gutMaxNow)
	-- Read LIVE current values straight off leaderstats / the runtime home-base table.
	local data = {
		saveVersion      = SAVE_VERSION,  -- stamp the current version so future joins load normally (post-wipe)
		coins            = val("Coins", DEFAULT_COINS),
		-- [STOMACH RESET] while the gut is forced to base, persist the HIGHER of the real on-disk gut (loadedStomachMax)
		-- and the live leaderstat -- so the reset is non-destructive (the saved tier survives) AND any coin-tier the player
		-- buys this session still persists, while the forced base (<= both) never overwrites real progress. Reversible.
		stomachMax       = FORCE_BASE_STOMACH and math.max(loadedStomachMax[player] or DEFAULT_STOMACH, val("StomachMax", DEFAULT_STOMACH)) or val("StomachMax", DEFAULT_STOMACH),
		island           = val("Island", DEFAULT_ISLAND),
		highestIsland    = highestIslandReached[player] or DEFAULT_ISLAND,
		totalFartPower   = val("TotalFartPower", 0),
		totalCoinsEarned = val("TotalCoinsEarned", 0),
		fartMeter        = meterToSave,  -- persist the player's CURRENT fart-meter (raw power), from the snapshot
		ownedPets        = _G.playerOwnedPets[player] or {},  -- cosmetic pet ownership + per-pet {level,height,time}
		equippedPet      = _G.playerEquippedPet[player],      -- cosmetic: which pet is currently equipped (additive)
		discoveredQuests = _G.playerDiscoveredQuests[player] or {}, -- cosmetic: which pet quests are discovered (additive)
		everCompletedQuests = _G.playerEverCompletedQuests[player] or {}, -- PERMANENT first-completion flags (gates the one-time rare roll; additive)
		seenGardenIntro  = player:GetAttribute("SeenGardenIntro") == true, -- one-time Community Garden cinematic: true once the player has watched it
		ownedGutSkins    = _G.playerOwnedGutSkins[player] or { Default = true },  -- cosmetic gut skins owned (always includes Default)
		equippedGutSkin  = _G.playerEquippedGutSkin[player] or "Default",         -- currently equipped gut skin id
		crateTokens      = math.floor(tonumber(_G.playerCrateTokens[player]) or 0), -- COSMETIC currency (skin crates only; never buys food)
		petSkins         = _G.playerPetSkins[player] or {},                       -- pet skin inventory: ["Pet|Skin|Trait"] = duplicate count
		equippedSkins    = _G.playerEquippedSkins[player] or {},                  -- which skin+trait each pet is wearing
		collection       = _G.playerCollection[player] or {},                     -- collection-book completion + earned titles/auras
		playtimeSeconds  = _G.playerPlaytimeSec[player] or 0,                     -- total cumulative playtime (drives skin unlocks)
		islandTimeSec    = _G.playerIslandTimeSec[player] or 0,                   -- playtime(s) at which they reached their highest island (FASTEST CLIMB board)
		petMilestones    = _G.playerPetMilestones[player] or {},                  -- collection milestones already paid out ({"3"=true,...}; string keys = JSON-safe)
		title            = _G.playerTitle[player],                                -- earned title ("Beastmaster"); nil = none
		-- OFFLINE EARNINGS: when this save was written. The next join subtracts it from os.time() to work out
		-- how long the player's pets were left minding the farm. Written on EVERY save (autosave + leave), so a
		-- crash costs at most one autosave interval of accrual rather than the whole session.
		lastSeen         = os.time(),
	}
	print(string.format("[SAVE METER] player=%s meter=%d", player.Name, meterToSave))
	local key = tostring(player.UserId)
	print("SAVE ("..trigger.."): "..player.Name.." attempting (key="..key..") - coins="..data.coins.." island="..data.highestIsland.." stomach="..data.stomachMax)
	local ok, err = pcall(function() playerDataStore:SetAsync(key, data) end)
	if ok then
		print("SAVE ("..trigger.."): success")
	else
		print("SAVE ("..trigger.."): FAILED - "..tostring(err))
	end
	-- GLOBAL LEADERBOARDS: push this player's (just-persisted, server-owned) totals to the OrderedDataStores.
	-- Deliberately AFTER the save and pcall'd -- a leaderboard hiccup must never break the save path.
	if _G.leaderboardSubmit then pcall(_G.leaderboardSubmit, player) end
end
_G.savePlayerData = savePlayerData -- exposed so PetSystem can persist BOTH players immediately after a trade (anti-dupe)

-- ============================================================================================================
-- OFFLINE PET EARNINGS -- "your pets kept working while you were away", and the player PICKS the reward.
--
-- THE PLAYER CHOOSES: COINS, or PET LEVELS on their equipped pet. One or the other, never both. That makes the
-- return moment a small decision instead of a passive handout, and lets a player who does not need coins put the
-- time into their collection instead.
--
-- DESIGN CONSTRAINT: this must stay a NUDGE, never an income stream. It exists to give a player a reason to come
-- back tomorrow, not to replace playing. BOTH options are therefore capped hard:
--
--   COINS  -- tuned to be worth well under a MINUTE of real play at every stage of the game.
--             Sanity-checked against the real coin formula (coins = h*0.008 + (h/500)^2 per 0.5s tick):
--               * Island 2, 3 pets, equipped Lv5:    (3*8 + 5*2) * 1.15 = ~39/hour  -> ~235 for a full 6 hours.
--               * Island 14, 10 pets, equipped Lv25: (10*8 + 25*2) * 2.95 = ~383/hour -> ~2,300 for 6 hours,
--                 which is LESS than a SINGLE 0.5s tick of real flight up there (~8,400 coins).
--             It can never become the optimal way to earn, at any point in the game.
--
--   LEVELS -- HARD-capped at OFFLINE_MAX_LEVELS (2). A pet needs ~125,000 XP to reach Lv25, so two free levels is
--             a nudge, not a shortcut. Because the cap is a flat COUNT, no amount of idling (a week, a month) can
--             ever yield more than 2. Applies to the EQUIPPED pet only, and is not offered at all if that pet is
--             already maxed -- offering a reward that would do nothing is a lie.
--
-- The island multiplier on coins only exists so the number does not read as insulting late-game; as the figures
-- above show, it does NOT let offline overtake active play.
-- ============================================================================================================
local OFFLINE_PER_PET_HOUR   = 8     -- coins/hour for each pet SPECIES owned
local OFFLINE_PER_LEVEL_HOUR = 2     -- coins/hour per level of the EQUIPPED pet (rewards levelling one properly)
local OFFLINE_ISLAND_MULT    = 0.15  -- +15% per island beyond the first (island 14 => 2.95x)
local OFFLINE_MAX_HOURS      = 6     -- accrual stops here. Idling for a week earns the same as sleeping one night.
local OFFLINE_MIN_SECONDS    = 300   -- under 5 minutes away => no offer at all (stops rejoin-spam farming)
local OFFLINE_HARD_CAP       = 5000  -- absolute coin ceiling, whatever the maths says. Backstop against bad tuning.
local OFFLINE_MAX_LEVELS     = 2     -- HARD cap on the pet-level option. Never more, however long you idle.
local OFFLINE_LEVEL_1_HOURS  = 1     -- away >= 1h -> 1 level offered
local OFFLINE_LEVEL_2_HOURS  = 4     -- away >= 4h -> 2 levels offered (the cap)

-- A player's UNCLAIMED offer. Held SERVER-side and cleared the moment it is claimed, so the claim remote cannot be
-- replayed to grant twice -- the client only ever sends "I pick coins" / "I pick levels", never an amount.
local pendingOffline = {}  -- [player] = { coins, levels, pets, eqLevel, hours, capped, perHour, test }

-- Work out what a player is owed. `awaySeconds` is a PARAMETER (not read from the save in here) so the /offline
-- test command can simulate any window. Returns the offer table, or nil if there is nothing to offer.
local function computeOfflineEarnings(player, awaySeconds)
	awaySeconds = math.max(0, math.floor(tonumber(awaySeconds) or 0))
	if awaySeconds < OFFLINE_MIN_SECONDS then return nil end

	local pets = 0
	if type(_G.petsCollectedCount) == "function" then
		local ok, n = pcall(_G.petsCollectedCount, player)
		if ok and type(n) == "number" then pets = n end
	end
	if pets <= 0 then return nil end -- no pets => nothing was minding the farm

	-- the EQUIPPED pet: its level drives the coin rate, AND it is the pet the level option would be spent on
	local eqKey = _G.playerEquippedPet and _G.playerEquippedPet[player]
	local eqLevel = 0
	local owned = _G.playerOwnedPets[player]
	if eqKey and type(owned) == "table" and type(owned[eqKey]) == "table" then
		eqLevel = tonumber(owned[eqKey].level) or 0
	end

	local island  = math.max(1, math.floor(player:GetAttribute("HighestIsland") or 1))
	local mult    = 1 + OFFLINE_ISLAND_MULT * (island - 1)
	local perHour = (pets * OFFLINE_PER_PET_HOUR + eqLevel * OFFLINE_PER_LEVEL_HOUR) * mult
	local hours   = math.min(awaySeconds / 3600, OFFLINE_MAX_HOURS)
	local coins   = math.floor(math.min(perHour * hours, OFFLINE_HARD_CAP))

	-- LEVELS: a flat count by time away, hard-capped, and only if there is an un-maxed equipped pet to spend it on.
	local awayHours = awaySeconds / 3600
	local levels = 0
	if awayHours >= OFFLINE_LEVEL_2_HOURS then levels = 2
	elseif awayHours >= OFFLINE_LEVEL_1_HOURS then levels = 1 end
	levels = math.min(levels, OFFLINE_MAX_LEVELS)
	if (not eqKey) or eqLevel >= 25 then levels = 0 end

	if coins <= 0 and levels <= 0 then return nil end
	return {
		coins = coins, levels = levels, pets = pets, eqLevel = eqLevel,
		hours = hours, capped = (awaySeconds / 3600) > OFFLINE_MAX_HOURS, perHour = math.floor(perHour),
	}
end

-- Exposed so ComebackNudge can ask "what would this player be owed if they came back in N hours?" and put that
-- REAL number in the push notification. It must be the same function that actually pays out -- a notification
-- promising 240 coins that then hands over 90 is worse than sending nothing at all.
_G.offlinePreview = computeOfflineEarnings

-- Make the OFFER (grants NOTHING yet) and show the welcome-back card.
local function offerOfflineEarnings(player, awaySeconds, viaTestCommand)
	local r = computeOfflineEarnings(player, awaySeconds)
	if not r then return nil end
	r.test = viaTestCommand and true or false
	pendingOffline[player] = r
	pcall(function() OfflineEarningsEvent:FireClient(player, r) end)
	print(string.format("[OFFLINE] %s away %ds -> OFFER: %d coins OR %d level(s) (%d pets, eqLv %d, %.2fh%s)%s",
		player.Name, awaySeconds, r.coins, r.levels, r.pets, r.eqLevel, r.hours,
		r.capped and ", CAPPED" or "", viaTestCommand and " [TEST /offline]" or ""))
	return r
end

-- CLAIM: the client sends only its CHOICE ("coins" | "levels"). The SERVER owns the amounts, and the pending offer
-- is cleared FIRST -- so a replayed or spammed claim finds nothing and does nothing. A client can never ask for an
-- amount, only pick which of the two rewards the server already computed.
OfflineClaimEvent.OnServerEvent:Connect(function(player, choice)
	local r = pendingOffline[player]
	if not r then return end        -- nothing pending (already claimed, or never offered)
	pendingOffline[player] = nil    -- cleared BEFORE granting: a second click can never double-pay
	if choice ~= "coins" and choice ~= "levels" then choice = "coins" end
	if choice == "levels" and r.levels <= 0 then choice = "coins" end -- levels were not on the table -> fall back

	if choice == "levels" then
		local eqKey = _G.playerEquippedPet and _G.playerEquippedPet[player]
		local before, after
		if eqKey and type(_G.petGrantLevels) == "function" then
			local ok, b, a = pcall(_G.petGrantLevels, player, eqKey, r.levels)
			if ok then before, after = b, a end
		end
		print(string.format("[OFFLINE] %s CLAIMED %d pet level(s) on %s (Lv %s -> %s)",
			player.Name, r.levels, tostring(eqKey), tostring(before), tostring(after)))
	else
		local ls = player:FindFirstChild("leaderstats")
		local coinsStat = ls and ls:FindFirstChild("Coins")
		local totalStat = ls and ls:FindFirstChild("TotalCoinsEarned")
		if coinsStat then
			coinsStat.Value = coinsStat.Value + r.coins
			if totalStat then totalStat.Value = totalStat.Value + r.coins end -- counts toward the MOST COINS board
		end
		print(string.format("[OFFLINE] %s CLAIMED %d coins", player.Name, r.coins))
	end
	if _G.savePlayerData then pcall(_G.savePlayerData, player, "offlineclaim") end
end)

Players.PlayerRemoving:Connect(function(p) pendingOffline[p] = nil end)

-- Autosave loop (~every AUTOSAVE_INTERVAL s).
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, p in ipairs(Players:GetPlayers()) do savePlayerData(p, "autosave") end
	end
end)

-- Save everyone on server shutdown so nothing is lost when the server closes.
game:BindToClose(function()
	print("SAVE (BindToClose): server shutting down, saving "..#Players:GetPlayers().." player(s)")
	for _, p in ipairs(Players:GetPlayers()) do savePlayerData(p, "BindToClose") end
	task.wait(2) -- give SetAsync a moment to flush before the server fully closes
end)

-- Tutorial-NPC guard: the Farmer rig must NEVER be mistaken for an island's stand. Returns true if
-- `obj` lives inside a Humanoid character or a Farmer model, so the stand-finder/prompt-tagger can
-- skip it. (Belt-and-suspenders: even a stray Farmer parented inside an island won't shadow the stand.)
local function isTutorialNpc(obj, stopAt)
	local cur = obj
	while cur and cur ~= stopAt and cur ~= workspace do
		if cur.Name == "FarmerNPC" or cur.Name == "Farmer" then return true end
		if cur:IsA("Model") and cur:FindFirstChildWhichIsA("Humanoid") then return true end
		cur = cur.Parent
	end
	return false
end

-- Find an island's model ROBUSTLY so a dragged/renamed/nested model can't break the lookup.
-- A model "is island N" if its name CONTAINS "Island_<n>_" (plain substring). This survives a
-- trailing/leading space, a stray hidden character, or a rename, and "Island_1_" can never match
-- "Island_10_..." / "Island_11_..." (the char after "Island_1" there is a digit, not "_").
-- Search order: exact top-level child -> any top-level Island_<n>_ Model -> any Island_<n>_ Model
-- nested ANYWHERE in Workspace (e.g. dragged into a folder or that stray unnamed Model).
-- NOTE: cannot recover a genuinely DELETED model — that must be restored in Studio.
local function findIslandModel(islandNum)
	local name = ISLAND_NAMES[islandNum]
	local key = "Island_" .. islandNum .. "_"
	local function looksLikeIsland(inst)
		return inst:IsA("Model") and inst.Name:find(key, 1, true) ~= nil
	end
	-- 1) normal case: exact name, top-level child.
	local exact = workspace:FindFirstChild(name)
	if exact then return exact end
	-- 2) top-level child whose name contains "Island_<n>_" (rename / hidden char / trailing space).
	for _, child in ipairs(workspace:GetChildren()) do
		if looksLikeIsland(child) then
			warn(("ISLAND %d: exact name '%s' not found; using top-level model '%s' (name has a typo/space/hidden char — fix it to '%s')."):format(islandNum, name, child.Name, name))
			return child
		end
	end
	-- 3) nested anywhere in Workspace (dragged into a folder / another model / the stray unnamed Model).
	for _, desc in ipairs(workspace:GetDescendants()) do
		if looksLikeIsland(desc) then
			warn(("ISLAND %d: model '%s' is NESTED under '%s' (not a top-level Workspace child). Using it; move it back to the top of Workspace and name it '%s'."):format(islandNum, desc.Name, tostring(desc.Parent), name))
			return desc
		end
	end
	-- Not found at all: dump top-level Workspace Models so the real problem (typo / deleted / nested) is visible.
	local names = {}
	for _, c in ipairs(workspace:GetChildren()) do if c:IsA("Model") then names[#names + 1] = "'" .. c.Name .. "'" end end
	warn(("ISLAND %d: NOT FOUND. No Model contains '%s'. Top-level Workspace Models: %s"):format(islandNum, key, table.concat(names, ", ")))
	return nil
end

task.spawn(function()
	task.wait(2)
	for i, iname in ipairs(ISLAND_NAMES) do
		local model = findIslandModel(i)
		local pos = ISLAND_POSITIONS[i]
		if model then
			pcall(function()
				if model:IsA("Model") then
					if model.PrimaryPart then
						model:SetPrimaryPartCFrame(CFrame.new(pos.x, pos.y, pos.z))
					else
						model:MoveTo(Vector3.new(pos.x, pos.y, pos.z))
					end
				end
			end)
			print("Positioned "..iname.." at Y="..pos.y)
			-- PURE VISUAL rotation about the island's CENTER (keeps height + position).
			local rotDeg = ISLAND_ROTATIONS[i]
			if rotDeg and rotDeg ~= 0 and model:IsA("Model") then
				pcall(function()
					local cf = model:GetBoundingBox()       -- center CFrame of the whole model
					local c = cf.Position
					-- Rotate the ENTIRE model about world point c (its center) on Y. PivotTo
					-- moves every descendant together, so stand/shop/paths/props stay aligned.
					local rot = CFrame.new(c) * CFrame.Angles(0, math.rad(rotDeg), 0) * CFrame.new(c):Inverse()
					model:PivotTo(rot * model:GetPivot())
					print("ROTATED island "..i.." ("..iname..") by "..rotDeg.." deg about Y (visual only)")
				end)
			end
			for _, obj in ipairs(model:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and not isTutorialNpc(obj, model) and (obj.ObjectText == "Stand" or obj.ObjectText == "Buy Food" or obj.ObjectText == "") then
					obj:SetAttribute("IslandNumber", i)
					obj.Style = Enum.ProximityPromptStyle.Custom
					obj.Enabled = false
					print("TAGGED island "..i.." prompt: '"..obj.ObjectText.."'")
				end
			end
		else
			print("WARNING: "..iname.." not found in workspace")
		end
	end
end)

-- Largest flat BasePart in the island, IGNORING any tutorial-NPC parts (so the Farmer can never be
-- picked). Used as a robust fallback for the stand position when there's no Stand_N model/prompt.
local function getStandPart(model)
	local bestPart = nil
	local bestArea = 0
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and not isTutorialNpc(obj, model) then
			local area = obj.Size.X * obj.Size.Z
			if area > bestArea then
				bestArea = area
				bestPart = obj
			end
		end
	end
	return bestPart
end

-- Real Stand part positions per island, [islandNum] = {x,y,z}. Module scope so the
-- home-base respawn/catch system below can read the authoritative positions.
local standData = {}
-- Optional per-island EXACT player-spawn override from a placed SpawnLocation (separate from standData so the
-- Farmer/rocket/return still use the real stand). placeOnStand prefers this when present.
local spawnData = {}
task.spawn(function()
	task.wait(8)
	standData = {}
	spawnData = {}
	for islandNum = 1, 14 do
		local island = findIslandModel(islandNum)
		local partPos = nil
		local standLook = nil -- the stand part's facing (LookVector), used to spawn the player in FRONT of the booth

		print("SEARCHING ISLAND", islandNum, "MODEL FOUND:", island ~= nil)

		if island then
			-- SPAWN-POINT OVERRIDE: if a SpawnLocation is placed in the island, remember it as the EXACT player
			-- spawn spot (stored SEPARATELY in spawnData so the stand below still drives the Farmer/rocket/return).
			-- placeOnStand prefers this for islands that have one — e.g. the Bean Farm / island-1 spawn.
			for _, obj in ipairs(island:GetDescendants()) do
				if obj:IsA("SpawnLocation") then
					local top = obj.Position + Vector3.new(0, obj.Size.Y / 2, 0) -- pad top surface
					local lk = obj.CFrame.LookVector
					local fx, fz = 0, 1
					local h = Vector3.new(lk.X, 0, lk.Z)
					if h.Magnitude > 0.05 then h = h.Unit; fx, fz = h.X, h.Z end
					spawnData[islandNum] = {x=top.X, y=top.Y, z=top.Z, fx=fx, fz=fz, exact=true}
					print("STAND["..islandNum.."]: SpawnLocation '"..obj.Name.."' -> exact player spawn at", top)
					break
				end
			end

			-- Method 1: search ALL descendants for Stand_N model (handles nested hierarchy)
			local standName = "Stand_"..islandNum
			local standModel = nil
			for _, obj in ipairs(island:GetDescendants()) do
				if obj:IsA("Model") and obj.Name == standName and not isTutorialNpc(obj, island) then
					standModel = obj
					break
				end
			end
			print("  "..standName.." found in descendants:", standModel ~= nil)
			if standModel then
				local part = standModel.PrimaryPart or standModel:FindFirstChildWhichIsA("BasePart")
				if part then
					partPos = part.Position
					standLook = part.CFrame.LookVector
						print("STAND["..islandNum.."]: Method1 on", part.Name, part.Position)
				end
			else
				-- dump all Model names so we can see what's actually inside
				for _, obj in ipairs(island:GetDescendants()) do
					if obj:IsA("Model") then print("  MODEL:", obj.Name) end
				end
			end

			-- Method 2: any ProximityPrompt — walk up ancestors to find a BasePart
			if not partPos then
				for _, obj in ipairs(island:GetDescendants()) do
					if obj:IsA("ProximityPrompt") and not isTutorialNpc(obj, island) then
						local cur = obj.Parent
						while cur and cur ~= island and cur ~= workspace do
							if cur:IsA("BasePart") then
								partPos = cur.Position
								print("STAND["..islandNum.."]: Method2 on", cur.Name)
								break
							end
							cur = cur.Parent
						end
						if partPos then break end
					end
				end
			end

			-- Method 3: island PrimaryPart
			if not partPos and island:IsA("Model") and island.PrimaryPart then
				partPos = island.PrimaryPart.Position
				print("STAND["..islandNum.."]: Method3 PrimaryPart")
			end

			-- Method 3.5: largest NON-NPC BasePart in the island (its stand/platform). Robust catch-all
			-- so a REAL on-island position is always used instead of the off-island ISLAND_POSITIONS
			-- fallback, with the Farmer's parts excluded so he can never become the stand.
			if not partPos then
				local part = getStandPart(island)
				if part then
					partPos = part.Position
					standLook = part.CFrame.LookVector
					print("STAND["..islandNum.."]: Method3.5 largest non-NPC part:", part.Name, part.Position)
				end
			end
		else
			print("STAND["..islandNum.."]: island not in workspace")
		end

		-- Method 4: guaranteed fallback to known island position
		if not partPos then
			local pos = ISLAND_POSITIONS[islandNum]
			partPos = Vector3.new(pos.x, pos.y, pos.z)
			print("STAND["..islandNum.."]: Method4 ISLAND_POSITIONS Y="..pos.y)
		end

		-- Horizontal facing of the booth (flattened LookVector). Used to drop the player a bit in
		-- FRONT of the stand, looking back at it. Defaults to +Z if the stand had no usable orientation.
		local sfx, sfz = 0, 1
		if standLook then
			local h = Vector3.new(standLook.X, 0, standLook.Z)
			if h.Magnitude > 0.05 then h = h.Unit; sfx, sfz = h.X, h.Z end
		end
		standData[islandNum] = {x=partPos.X, y=partPos.Y, z=partPos.Z, fx=sfx, fz=sfz}
		print("STAND["..islandNum.."]: READY Y="..partPos.Y..(spawnData[islandNum] and " (+SpawnLocation override)" or ""))
	end
	local count = 0; for _ in pairs(standData) do count = count + 1 end
	print("STAND DATA COUNT:", count)
	for k, v in pairs(standData) do
		print("STAND DATA ISLAND", k, v.x, v.y, v.z)
	end
	print("STANDS SETUP COMPLETE:", count, "/ 14")

	-- Publish island-1's REAL detected stand + a readiness flag so the tutorial-NPC spawner can place
	-- the Farmer at the actual stand AFTER detection is done. The Farmer lives in ServerStorage (never
	-- in Workspace during stand setup), so it can never interfere with island detection.
	local s1 = standData[1]
	if s1 then
		workspace:SetAttribute("Stand1Pos", Vector3.new(s1.x, s1.y, s1.z))
		workspace:SetAttribute("Stand1Face", Vector3.new(s1.fx, 0, s1.fz))
	end
	workspace:SetAttribute("StandsReady", true)

	local StandsReadyEvent = RS:WaitForChild("StandsReadyEvent", 10)
	if not StandsReadyEvent then
		print("STAND: StandsReadyEvent not found!")
		return
	end

	local function fireToAll()
		for _, p in ipairs(Players:GetPlayers()) do
			StandsReadyEvent:FireClient(p, standData)
		end
	end

	-- Fire now, then re-fire at +7s and +15s for clients that load after the character spawns
	fireToAll()
	task.delay(7,  fireToAll)
	task.delay(15, fireToAll)

	Players.PlayerAdded:Connect(function(p)
		task.wait(5)
		StandsReadyEvent:FireClient(p, standData)
	end)
end)

Players.PlayerAdded:Connect(function(player)
	-- Load saved data FIRST. If it fails, kick instead of letting them play on a fresh save that
	-- would overwrite their real progress.
	local status, saved = fetchPlayerData(player)
	if status == "fail" then
		player:Kick("Couldn't load your saved data. Please rejoin.")
		return
	end
	if not player.Parent then return end -- left during the load
	-- ONE-TIME WIPE: any record from an OLD save version (or with no saveVersion field, i.e. all
	-- pre-wipe records) is discarded and the player is treated as brand-new. The defaults path below
	-- then runs, and they get re-saved at SAVE_VERSION (autosave / leave), so future joins load normally.
	if status == "ok" and saved and saved.saveVersion ~= SAVE_VERSION then
		print("LOAD: "..player.Name.." save WIPED (saveVersion "..tostring(saved.saveVersion).." ~= "..SAVE_VERSION..") -> starting brand-new")
		saved = nil
	end
	if status == "ok" and saved then
		print("LOAD: success - coins="..tostring(saved.coins).." island="..tostring(saved.highestIsland).." stomach="..tostring(saved.stomachMax))
	elseif status == "ok" then
		print("LOAD: no save found, using defaults")
	else -- "nostore"
		print("LOAD: no DataStore available, using defaults (will NOT persist)")
	end
	-- STARTER PET: is this the player's FIRST EVER join? True when there is no usable save record -- no save found
	-- ("ok" + nil), a wiped old-version save, or no DataStore at all ("nostore", e.g. Studio with API access off).
	-- Those are exactly the cases that fall through to the defaults below, so this means "running on a fresh slate".
	-- Captured BEFORE the `saved = saved or {}` line collapses nil into an empty table. Read further down, once the
	-- pet state has loaded, to hand them their free Bean Buddy. An existing player NEVER re-triggers this.
	local isBrandNewPlayer = (saved == nil)
	saved = saved or {} -- new player ("ok" nil) or "nostore" -> defaults below

	local ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
	local coins  = Instance.new("IntValue"); coins.Name  = "Coins";          coins.Value  = saved.coins or DEFAULT_COINS;        coins.Parent  = ls
	if DISABLE_SAVE_FOR_TESTING then coins.Value = DEFAULT_COINS end -- [NOSAVE TEST] \xE2\x9A\xA0 force a fresh 2,000-coin start, IGNORING any saved coin value. REMOVE BEFORE LAUNCH.
	if TEST_FULL_DATA then coins.Value = TEST_FULL_DATA_COINS end -- [TEST] unlimited coins to sample every tier's reach without grinding
	local island = Instance.new("IntValue"); island.Name = "Island";         island.Value = math.max(saved.island or DEFAULT_ISLAND, saved.highestIsland or DEFAULT_ISLAND); island.Parent = ls
	local tfp    = Instance.new("IntValue"); tfp.Name    = "TotalFartPower"; tfp.Value    = saved.totalFartPower or 0;           tfp.Parent    = ls
	local tce    = Instance.new("IntValue"); tce.Name    = "TotalCoinsEarned"; tce.Value  = saved.totalCoinsEarned or 0;         tce.Parent    = ls
	-- CRATE TOKENS: the COSMETIC currency, deliberately a separate stat from Coins so the two economies can never
	-- be confused for one another. Tokens buy skin crates and nothing else; Coins buy food/guts and nothing else.
	local ctok   = Instance.new("IntValue"); ctok.Name   = "CrateTokens";     ctok.Value = math.floor(tonumber(saved.crateTokens) or 0); ctok.Parent = ls
	-- [STOMACH RESET] StomachMax: remember the REAL on-disk value (preserved through save), then force the live gut to
	-- the BASE starting value while FORCE_BASE_STOMACH is on (don't trust a stored 9999 / any saved upgrade). Clear the
	-- Infinite-Gut flag so the meter never locks full. When the reset is off, load the saved tier as normal.
	loadedStomachMax[player] = saved.stomachMax or DEFAULT_STOMACH
	local stomachStart = FORCE_BASE_STOMACH and DEFAULT_STOMACH or (saved.stomachMax or DEFAULT_STOMACH)
	local stomachMaxStat = Instance.new("IntValue"); stomachMaxStat.Name="StomachMax"; stomachMaxStat.Value=stomachStart; stomachMaxStat.Parent=ls
	if FORCE_BASE_STOMACH then player:SetAttribute("HasInfiniteGut", false) end
	-- RESTORE FART METER: clamp the saved meter to the (restored) gut max — never above; NO lower cap.
	-- [FART RESET] while the reset is on, the meter STARTS EMPTY (0) -- a fresh start is 0/StomachMax, never a full tank,
	-- so a high saved meter can't restore as a FULL base tank on spawn/load. (Reset off -> restore the saved meter as
	-- before.) (When DISABLE_SAVE_FOR_TESTING is on, `saved` is empty -> fartMeter nil -> 0, so it follows the save flag.)
	local restoredMeter = FORCE_BASE_STOMACH and 0 or math.max(0, math.min(math.floor(tonumber(saved.fartMeter) or 0), stomachMaxStat.Value))
	local currentPowerStat = Instance.new("IntValue"); currentPowerStat.Name="CurrentPower"; currentPowerStat.Value=restoredMeter; currentPowerStat.Parent=ls
	print(string.format("[FART RESET] start CurrentPower=%d StomachMax=%d (should be 0/100)", currentPowerStat.Value, stomachMaxStat.Value))
	-- [NOSAVE TEST] \xE2\x9A\xA0 TEMPORARY -- confirm the forced fresh start + that saving is off. REMOVE BEFORE LAUNCH.
	if DISABLE_SAVE_FOR_TESTING then
		print(string.format("[NOSAVE TEST] %s coins=%d power=%d/%d saveDisabled=yes", player.Name, coins.Value, currentPowerStat.Value, stomachMaxStat.Value))
	end
	-- [STOMACH RESET] confirm the starting gut + meter are base and ALL gut ownership reads false.
	print(string.format("[STOMACH RESET] ownsInfiniteGut=%s allGutsOwned=%d StomachMax=%d CurrentPower=%d (should be base, ownership all false)",
		FORCE_BASE_STOMACH and "n" or "?", FORCE_BASE_STOMACH and 0 or 0, stomachMaxStat.Value, currentPowerStat.Value))
	-- METER PERSISTENCE: remember the saved meter to RE-APPLY after the first spawn settles. We can't
	-- rely on the leaderstat value above surviving, because the spawn's onLand fires LandingEvent(0)
	-- which (decrease-only) zeros CurrentPower. The SelectIslandEvent spawn hook re-applies this value
	-- post-spawn and replicates it to the client's gas meter. lando5485 has saved=nil -> 0 -> no restore.
	joinRestoreMeter[player] = restoredMeter
	lastMeter[player] = restoredMeter
	print(string.format("[LOAD METER] player=%s saved=%d applied_to_live=%d", player.Name, math.floor(tonumber(saved.fartMeter) or 0), restoredMeter))
	-- Restore home base / highest island. Use the MAX of both saved fields so the home stand (where
	-- onCharacterAdded teleports), the HighestIsland attribute, and the Island leaderstat (food-shop
	-- unlocks) all reflect the furthest the player reached — they had diverged before.
	local restoredIsland = math.max(saved.highestIsland or DEFAULT_ISLAND, saved.island or DEFAULT_ISLAND)
	highestIslandReached[player] = restoredIsland
	player:SetAttribute("HighestIsland", restoredIsland)
	-- DINO UNLOCKS: ZERO for a new player -- the Dino Realm is somewhere you REACH, not somewhere you are given.
	-- The only thing unlocked anywhere in the game at the start is Island 1 of the first realm; every dino card
	-- shows 🔒 until the player actually gets there. (This used to default to 1, quietly gifting a free dino island
	-- to an account that had never seen the realm.)
	--
	-- This attribute is the ONE authority on dino access: the client paints the cards from it, and DinoSelectEvent
	-- re-validates against it. So the default has to be fixed HERE -- the picker can only show what this tells it.
	--
	-- The test-account "grant all 14" is behind TEST_UNLOCK_ALL_DINOS, defaulted OFF, so a tester sees the real
	-- new-player screen. Mirrors TEST_UNLOCK_ALL_ISLANDS in LoadingScreen.client.lua.
	player:SetAttribute("UnlockedDinos", (TEST_UNLOCK_ALL_DINOS and isAllowedTestUser(player)) and DINO_COUNT or 0)
	print("LOAD ISLAND: "..player.Name.." restored highestIsland="..restoredIsland..", teleporting to stand "..restoredIsland)
	dataLoaded[player] = true
	playerCoinAccum[player] = 0
	-- ONE-TIME GARDEN INTRO: restore the "has watched the cinematic" flag as a player attribute (replicates to
	-- the client; the SelectIslandEvent hook reads it to decide whether to play). \xE2\x9A\xA0 TEST: lando5485 is treated as a
	-- brand-new player every join -- force the flag FALSE so the intro replays for testing. REMOVE BEFORE LAUNCH.
	local isIntroTester = (player.UserId == TEST_ACCOUNT_USERID) or (string.lower(player.Name) == "lando5485")
	local seenIntro = (not isIntroTester) and (saved.seenGardenIntro == true)
	player:SetAttribute("SeenGardenIntro", seenIntro)
	print("LOAD GARDEN INTRO: "..player.Name.." SeenGardenIntro="..tostring(seenIntro)..(isIntroTester and " (TEST: forced replay)" or ""))
	-- PETS: restore cosmetic pet ownership from the save (fresh/test/synthetic saves have no ownedPets
	-- field -> {} -> no pet, which respects FRESH_PLAYER_TEST / SPAWN_AT_PIZZA_PALMS_TEST). Then let
	-- PetSystem react (spawn an owned pet + send the client its state). Guarded so load never depends on it.
	_G.playerOwnedPets[player] = saved.ownedPets or {}
	_G.playerEquippedPet[player] = saved.equippedPet -- cosmetic equipped choice (nil if none / legacy save)
	-- GUT SKINS: new players (and legacy saves) start owning ONLY Default, equipped Default. GutSkinService reads these.
	_G.playerOwnedGutSkins[player] = saved.ownedGutSkins or { Default = true }
	_G.playerOwnedGutSkins[player].Default = true -- safety: everyone always owns Default
	_G.playerEquippedGutSkin[player] = saved.equippedGutSkin or "Default"
	_G.playerPlaytimeSec[player] = tonumber(saved.playtimeSeconds) or 0 -- restore total playtime (new players = 0)
	-- PET SKIN CRATES: a new player (and every legacy save) starts with 0 tokens and an empty skin inventory, so
	-- nothing here can retroactively hand out cosmetics. SkinCrateService reads these; its skinCrateApplyOnJoin
	-- (called below, after the pet state loads) mirrors the balance onto the leaderstat and pushes the client state.
	_G.playerCrateTokens[player]   = math.floor(tonumber(saved.crateTokens) or 0)
	_G.playerPetSkins[player]      = saved.petSkins or {}
	_G.playerEquippedSkins[player] = saved.equippedSkins or {}
	-- A save written before the collection existed loads as an empty table; SkinCrateService's collection()
	-- back-fills the missing fields, then its first pushState re-derives completion from the inventory -- so an
	-- existing player who already owns a full set is credited on their next join rather than having to re-earn it.
	_G.playerCollection[player]    = saved.collection or {}
	-- Snapshot the SAVED playtime as this session's baseline. totalPlaytimeSec() adds live session seconds on top,
	-- so it must know where the session started from -- reading _G.playerPlaytimeSec later would double-count the
	-- minutes GutSkinService has already added to it.
	playtimeAtLoad[player]       = _G.playerPlaytimeSec[player]
	_G.playerIslandTimeSec[player] = tonumber(saved.islandTimeSec) or 0 -- when they reached their highest island
	_G.playerDiscoveredQuests[player] = saved.discoveredQuests or {} -- cosmetic discovered-quest set (empty / legacy save)
	_G.playerEverCompletedQuests[player] = saved.everCompletedQuests or {} -- PERMANENT first-completion flags (empty / legacy save -> never completed)
	-- COLLECTION MILESTONES + TITLE (Pet Hub collection rewards). Keys in petMilestones are STRINGS ("3","5",...)
	-- because DataStore JSON-encodes tables and numeric keys don't round-trip reliably. A legacy save has neither
	-- field -> empty/nil -> PetSystem's join-time catch-up re-checks their pets and pays out anything they'd already
	-- earned, so existing players get their titles (and the secret pet) on their next login rather than never.
	_G.playerPetMilestones[player] = saved.petMilestones or {}
	_G.playerTitle[player] = saved.title -- nil = no title yet; PetSystem re-applies the "Title" attribute on join
	if _G.petsApplyOnJoin then pcall(function() _G.petsApplyOnJoin(player) end) end
	-- SKIN CRATES: run AFTER petsApplyOnJoin so the pet-ownership table is populated -- the pushed state includes
	-- which pets are unlocked, which is what decides whether a skin reads as equippable or "Unlock <Pet> to equip".
	if _G.skinCrateApplyOnJoin then pcall(function() _G.skinCrateApplyOnJoin(player) end) end
	-- FREE STARTER PET (retention): a brand-new player is handed a Bean Buddy immediately -- owned, auto-equipped,
	-- following them from their first spawn -- so they OWN something before they have earned anything. Runs AFTER
	-- petsApplyOnJoin so the pet state is loaded and the grant's sendState/sendInventory is the last word. Guarded
	-- (pcall + existence check) so a pet-system failure can never break the join/load path. It also persists on the
	-- normal path: PlayerStats saves _G.playerOwnedPets under saved.ownedPets on autosave/leave.
	-- THE CHECK IS INSIDE THE SPAWN, NOT AROUND IT -- that ordering is the whole fix.
	-- It used to read `if isBrandNewPlayer and _G.grantStarterPet then`, which asks whether PetSystem has
	-- finished loading AT THIS EXACT INSTANT. PlayerStats and PetSystem are two separate server Scripts and
	-- Roblox does not order them: on a join where PlayerStats got there first, _G.grantStarterPet was still
	-- nil, the whole branch was skipped, and the player never received a Bean Buddy. Silently -- the print
	-- lived inside the branch too, so there was not even a log line saying it had not run. That is the
	-- intermittent "my starter pet did not show up": not a render failure at all, a grant that never
	-- happened, on whichever joins lost the race.
	--
	-- Now the spawn always starts and WAITS for the function to exist (up to 15s, 10x/sec). The brand-new
	-- test still gates it, and a timeout warns loudly instead of failing quietly.
	if isBrandNewPlayer then
		task.spawn(function()
			local waited = 0
			while not _G.grantStarterPet and waited < 15 do task.wait(0.1); waited = waited + 0.1 end
			if not _G.grantStarterPet then
				warn(("[STARTER PET] %s brandNew=y but _G.grantStarterPet never appeared after %.0fs -- " ..
					"PetSystem.server did not load. No starter pet granted."):format(player.Name, waited))
				return
			end
			if not player.Parent then return end -- left while we were waiting
			local ok, granted = pcall(function() return _G.grantStarterPet(player) end)
			print(string.format("[STARTER PET] %s brandNew=y grantOk=%s granted=%s (waited %.1fs for PetSystem)",
				player.Name, ok and "y" or "n", (ok and granted) and "y" or "n", waited))
		end)
	end
	-- OFFLINE PET EARNINGS: pay out what their pets earned while they were away. Deferred so it runs AFTER
	-- petsApplyOnJoin above has loaded their pets -- the rate is derived from pets owned + equipped level, so
	-- computing it any earlier would read an empty collection and pay nothing. A brand-new player has no
	-- lastSeen, so they're skipped entirely (nothing to be away FROM).
	if not isBrandNewPlayer and saved.lastSeen then
		local away = os.time() - (tonumber(saved.lastSeen) or os.time())
		task.spawn(function()
			task.wait(1) -- let the pet state settle
			if player.Parent then pcall(offerOfflineEarnings, player, away, false) end
		end)
	end
	-- Gamepass ownership is read LIVE each join (never saved).
	task.spawn(function()
		local gpData = {twoXForever=false, glitterTrail=false, luckyPass=false, vip=false, coinMagnet=false}
		for name, id in pairs(GAMEPASS_IDS) do
			if id ~= 0 then
				-- Check the current id AND any superseded one that grants the same perk (Gamepasses.LEGACY_IDS --
				-- Space Realm's original Lucky Crates / VIP). The realms share one experience, so a pass bought
				-- in Space is owned here too, and dropping those buyers on the floor is not an option.
				local ok, owns = pcall(function()
					for _, passId in ipairs(Gamepasses.allIdsFor(name)) do
						if MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId) then return true end
					end
					return false
				end)
				-- [TESTING] Gamepasses.FORCE_UNOWNED forces ALL SIX passes to read un-owned, including the three
				-- legacy ones that don't go through Gamepasses.owns(). Needed because Roblox reports the CREATOR
				-- of a pass as owning it, so on the dev account every pass is owned and none of the buy flows can
				-- be tested. Set it false in Shared/Gamepasses before publishing.
				if Gamepasses.FORCE_UNOWNED then
					owns = false
					pcall(function() player:SetAttribute(Gamepasses.ATTR[name], false) end)
				end
				-- [RESET] gamepass-voiding test hooks removed: ownership is whatever Roblox reports (owned-only) for EVERY player.
				-- [STOMACH RESET] the GUT gamepass is forced un-owned while FORCE_BASE_STOMACH is on, so Infinite Gut never applies.
				if name == "InfiniteGut" and FORCE_BASE_STOMACH then owns = false end
				-- [NOSAVE TEST] the 2x FOREVER gamepass is forced un-owned while FORCE_NO_2X is on. REMOVE BEFORE LAUNCH.
				if name == "TwoXForever" and FORCE_NO_2X then owns = false; player:SetAttribute("HasTwoXForever", false) end
				if ok and owns then
					if name == "TwoXForever" then gpData.twoXForever = true; player:SetAttribute("HasTwoXForever", true)
					elseif name == "GlitterTrail" then gpData.glitterTrail = true; player:SetAttribute("HasGlitterTrail", true)
					elseif name == "InfiniteGut" then applyInfiniteGut(player) -- forever pass: re-apply the Infinite Gut tier on join (effect is the StomachMax, not a client gpData flag)
					-- The three newer passes are all ATTRIBUTE-DRIVEN and need no work here beyond the flag:
					--   LuckyPass  -> Gamepasses.luckFor() reads it at roll time (SkinCrateService / CrateService)
					--   VIP        -> VipService watches the attribute for the coin perk + stipend; TitleTags draws the tag
					--   CoinMagnet -> CoinMagnet.client reads it to start pulling pickups
					-- gpData mirrors each one to the client purely so shop buttons can show OWNED instead of a price.
					elseif name == "LuckyPass"  then gpData.luckyPass  = true; player:SetAttribute("HasLuckyPass",  true)
					elseif name == "VIP"        then gpData.vip        = true; player:SetAttribute("HasVIP",        true)
					elseif name == "CoinMagnet" then gpData.coinMagnet = true; player:SetAttribute("HasCoinMagnet", true)
					end
				elseif name == "InfiniteGut" and (FORCE_BASE_STOMACH or ok) then
					-- [STOMACH RESET] forced un-owned, OR the ownership check SUCCEEDED as not-owned (never clamp on a failed
					-- check -> don't strip a real owner on a transient error): clamp a stored 9999 back to base + clear the flag.
					player:SetAttribute("HasInfiniteGut", false)
					local lsg = player:FindFirstChild("leaderstats"); local smg = lsg and lsg:FindFirstChild("StomachMax")
					if smg and smg.Value >= INFINITE_GUT_MAX then
						smg.Value = DEFAULT_STOMACH
						pcall(function() StomachUpdateEvent:FireClient(player, DEFAULT_STOMACH, "Tiny Gut") end)
						print("[STOMACH RESET] clamped stored Infinite Gut (9999) back to base for "..player.Name.." (not owned / forced)")
					end
				end
			end
		end
		-- Store the computed ownership so the on-ready handshake can re-send it (and mark it ready).
		gamepassState[player] = gpData
		gamepassReady[player] = true
		if GamepassEvent then
			-- [BALANCE] send an all-false perk state when disabled, so the client mirrors "no perks"
			-- (powerPassActive=false, no Glitter Trail, FLIGHT DEBUG has2x=false) even if the player owns them.
			pcall(function() GamepassEvent:FireClient(player, DISABLE_PERKS_FOR_BALANCE and {twoXForever=false, glitterTrail=false} or gpData) end)
		end
	end)
end)

-- ON-READY HANDSHAKE: the client fires RequestPlayerState once its HUD + handlers are built. We then
-- (re)send the saved state so the LABEL, forever gamepasses, capacity, and menu all agree on every
-- platform — independent of join-time push timing (fixes slow mobile/console clients).
RequestPlayerState.OnServerEvent:Connect(function(player)
	-- (1) GUT LABEL: re-send the saved gut (read from the already-restored StomachMax leaderstat) so the
	-- on-screen gut name matches the meter capacity. The client looks the name up from maxPower itself.
	local ls = player:FindFirstChild("leaderstats")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if sm and StomachUpdateEvent then
		local gutName = "Tiny Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == sm.Value then gutName = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, sm.Value, gutName) end)
	end
	-- (1b) FART METER: restore the saved meter so the gas-meter BAR shows the correct fill on join. We
	-- send it AFTER the gut label so the client's gut max is set first. RegenEvent makes the client set
	-- currentPower + gasMeter and refresh the bar/button. Safety-clamp to the gut max (already clamped on
	-- load; re-clamped here defensively). Same cross-platform handshake as the gut label.
	local cp = ls and ls:FindFirstChild("CurrentPower")
	if cp and sm and RegenEvent then
		local restored = math.max(0, math.min(cp.Value, sm.Value))
		pcall(function() RegenEvent:FireClient(player, 0, restored, sm.Value) end)
	end
	-- (2) FOREVER GAMEPASSES: wait briefly for the on-join ownership check to finish, then re-send the
	-- active state (2X Power Forever / Glitter Trail) so client visuals/effects apply without manual action.
	local deadline = os.clock() + 8
	while not gamepassReady[player] and os.clock() < deadline do task.wait(0.15) end
	if GamepassEvent then
		local gp = gamepassState[player] or { twoXForever = false, glitterTrail = false }
		pcall(function() GamepassEvent:FireClient(player, DISABLE_PERKS_FOR_BALANCE and { twoXForever = false, glitterTrail = false } or gp) end)
	end
	-- (3) 2X Coins (1hr): consumable timer is NOT in the saved data table, so there is nothing to restore
	-- on join. (If/when a remaining-expiry is ever saved, re-send it here as {twoXHourExpiry=...}.)
end)

Players.PlayerRemoving:Connect(function(player)
	print("PlayerRemoving FIRED for "..player.Name)
	savePlayerData(player, "PlayerRemoving") -- gated by dataLoaded + pcall'd inside; saves coins/gut/island/home base (reads lastMeter)
	playerCoinAccum[player] = nil
	coinWindow[player] = nil      -- the anti-exploit budget window; a stale entry would leak per rejoin
	dataLoaded[player] = nil
	gamepassState[player] = nil
	gamepassReady[player] = nil
	lastMeter[player] = nil       -- cleared AFTER save (save reads it for the meter)
	joinRestoreMeter[player] = nil
	loadedStomachMax[player] = nil -- cleared AFTER save (save reads it to preserve the real on-disk gut while forced)
	_G.playerOwnedPets[player] = nil  -- cleared AFTER save (save reads it for ownedPets)
	_G.playerEquippedPet[player] = nil
	_G.playerDiscoveredQuests[player] = nil
	_G.playerEverCompletedQuests[player] = nil -- cleared AFTER save (save reads it for everCompletedQuests)
	_G.playerPetMilestones[player] = nil       -- cleared AFTER save (save reads it for petMilestones)
	_G.playerTitle[player] = nil               -- cleared AFTER save (save reads it for title)
end)

-- (Daily Rewards join-handshake removed.)

-- FORWARD DECLARATION. islandUnderCharacter is defined further down (it needs standData, which is
-- built below this point), but the food purchase above needs it. Declaring the local HERE puts it in
-- scope for the closures between here and there; the definition below assigns into this same local
-- rather than creating a second one. Without this the handler would resolve it as a global and get nil.
local islandUnderCharacter

BuyFoodEvent.OnServerEvent:Connect(function(player, foodName)
	print("SERVER RECEIVED BUY:", player.Name, foodName)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then return end
	local coins        = stats:FindFirstChild("Coins")
	local totalPower   = stats:FindFirstChild("TotalFartPower")
	local totalEarned  = stats:FindFirstChild("TotalCoinsEarned")
	local currentPower = stats:FindFirstChild("CurrentPower")
	local stomachMax   = stats:FindFirstChild("StomachMax")
	if not coins or not totalPower then return end
	local food = nil
	for _, f in ipairs(foods) do
		if f.name == foodName then food = f; break end
	end
	if not food then
		print("FOOD NOT FOUND:", foodName)
		return
	end
	-- FAILURE CHECK 0 (ISLAND LOCK): a food unlocks when the player has REACHED its island. Pizza is island
	-- 14, so it stays unbuyable until they have physically stood on island 14 -- and the same for every
	-- island above the one they have climbed to.
	--
	-- This is NOT the old stand/pet-quest lock, which is still gone (foodStandUnlocked() is a permanent
	-- `true`; every stand opens for everybody and lists the whole menu). That gate asked "may you shop
	-- here"; this one asks "have you earned this rung".
	--
	-- Checked BEFORE the coin check on purpose: a locked food must say "locked", not "not enough coins" --
	-- and it must never fall through to the generic branch on the client, which opens the gut shop.
	--
	-- READ BOTH MARKERS AND TAKE THE HIGHER. There are two, they are raised by different events, and they
	-- legitimately disagree for a while:
	--   * highestIslandReached -- raised only by the Heartbeat's PHYSICAL landing detection (flying past an
	--     island does not count);
	--   * the Island leaderstat -- raised by UnlockIslandEvent when the player's PEAK clears the island.
	-- UnlockIslandEvent does NOT touch highestIslandReached, and the food shop's client reads the Island
	-- stat. So gating on highestIslandReached alone would refuse a food the grid is showing as unlocked,
	-- with no visible reason -- the precise failure the client comment warns about. The max of the two is
	-- what the player has been shown, so that is what gets honoured.
	--
	-- Still server-authoritative: both values are written only by server code, never by client input.
	local lsIslandStat  = stats:FindFirstChild("Island")
	local reachedIsland = math.max(highestIslandReached[player] or 1, (lsIslandStat and lsIslandStat.Value) or 1)
	local foodIsland    = tonumber(food.island) or 1
	if foodIsland > reachedIsland then
		print("FOOD LOCKED:", player.Name, food.name, "needs island", foodIsland, "reached", reachedIsland)
		pcall(function() StomachFullEvent:FireClient(player, "food_locked", food.name, foodIsland) end)
		return
	end
	-- ===== THERE IS NO FLOOR ANY MORE: COINS ARE THE LIMIT =====
	-- There used to be a FAILURE CHECK 0b here refusing any food from an island BELOW the one you were
	-- standing on ("food_below_island"). It was there to stop island 13 being played by buying beans, but it
	-- broke the thing the shop is FOR: on island 1 your coins turn straight into food, and on every island
	-- above it they stop doing that. Stood on island 4 with 150 coins, Turnips (94) are the only legal
	-- purchase -- one of them, and the other 56 coins buy nothing at all, on an island whose gut you cannot
	-- fill with whole turnips anyway. Island 1 spends every coin; island 4 stranded them.
	--
	-- So the only gate left is the CEILING above (have you reached this food's island) and the price. What
	-- you can buy is what you have unlocked, and how much of it is what your coins allow -- the same rule on
	-- island 14 as on island 1.
	--
	-- KNOWN TRADE-OFF, deliberately accepted: the early foods are still the best power-per-coin in the game
	-- (Beans 1.60, Popcorn 0.40), so buying beans stays mathematically optimal at altitude. That is a PRICE
	-- TABLE problem -- see the "food prices are not monotonic" note in CLAUDE.md -- and the fix belongs in
	-- the prices, not in a rule that stops players spending their money.
	-- ===== ANTI-STRAND: a dry landing is never a dead end =====
	-- If the player lands DRY and cannot afford any meal they have unlocked, grant exactly enough for ONE
	-- serving of the food on the island they are standing on. Once per landing (keyed on sessionFlights) so
	-- it cannot be farmed by hopping. The free meal must never hand over a crossing: one serving is at most
	-- 36% of a crossing (the tutorial, c1) and under 20% everywhere else. An earlier design priced the top-up
	-- against FlightTuning.powerShortfall() and that handed over a WHOLE crossing on the first dry landing.
	if coins.Value < food.price and currentPower and currentPower.Value <= 0 then
		local cheapest = math.huge
		for _, f in ipairs(foods) do
			if (tonumber(f.island) or 1) <= reachedIsland and f.price < cheapest then cheapest = f.price end
		end
		local flightNow = sessionFlights[player] or 0
		if coins.Value < cheapest and strandGrantFlight[player] ~= flightNow then
			local hereIsland = math.clamp((lsIslandStat and lsIslandStat.Value) or 1, 1, #foods)
			local localFood = foods[hereIsland]
			for _, f in ipairs(foods) do if f.island == hereIsland then localFood = f; break end end
			local grant = localFood.price - coins.Value
			if grant > 0 then
				strandGrantFlight[player] = flightNow
				coins.Value = coins.Value + grant
				print(("[ANTI-STRAND] %s landed dry with %d coins -> +%d for one %s"):format(player.Name, coins.Value - grant, grant, localFood.name))
			end
		end
	end
	-- FAILURE CHECK 1 (COINS FIRST — the common blocker): not enough coins -> "not_enough_coins".
	if coins.Value < food.price then
		print("NOT ENOUGH COINS:", player.Name, coins.Value, "<", food.price)
		pcall(function() StomachFullEvent:FireClient(player, "not_enough_coins") end) -- specific reason for the client
		return
	end
	if not currentPower or not stomachMax then return end
	-- 2x Fart Power pass (forever) OR an active 1-hour product both grant the real power boost.
	local has2x = player:GetAttribute("HasTwoXForever") or
		(player:GetAttribute("TwoXHourExpiry") and player:GetAttribute("TwoXHourExpiry") > os.time())
	if DISABLE_2X and game:GetService("RunService"):IsStudio() then has2x = false end -- [TESTING] no 2x boost in Studio
	if DISABLE_PERKS_FOR_BALANCE then has2x = false end -- [BALANCE] force normal 1x power (Studio AND live) -> Beans = 8
	if FORCE_NO_2X then has2x = false end -- [NOSAVE TEST] 2x forced un-owned for everyone -> no 2x power boost. REMOVE BEFORE LAUNCH.
	-- With the pass, food adds POWER_PASS_MULT x its power to ACTUAL flight fuel, and the
	-- effective tank grows to stomachMax * POWER_PASS_MULT (so the player flies higher).
	local powerGain   = has2x and math.floor(food.power * POWER_PASS_MULT) or food.power
	local effectiveMax = has2x and math.floor(stomachMax.Value * POWER_PASS_MULT) or stomachMax.Value
	local newPower = currentPower.Value + powerGain
	-- FAILURE CHECK 2 (only reached when coins are sufficient): does it fit the REMAINING stomach space?
	-- Distinguish TRULY FULL (no room at all -> "stomach_full") from HAS-ROOM-but-too-big ("not_enough_room").
	if newPower > effectiveMax then
		local remaining = effectiveMax - currentPower.Value
		if remaining <= 0 then
			print("STOMACH FULL:", player.Name, currentPower.Value, "/", effectiveMax, "(no room at all)")
			pcall(function() StomachFullEvent:FireClient(player, "stomach_full") end)    -- truly full
		else
			print("NOT ENOUGH ROOM:", player.Name, "+"..powerGain, ">", remaining, "remaining")
			pcall(function() StomachFullEvent:FireClient(player, "not_enough_room") end) -- has room, this food won't fit
		end
		return
	end
	coins.Value = coins.Value - food.price
	coinsSpentOnFood[player] = (coinsSpentOnFood[player] or 0) + food.price -- [BALANCE LOGGING] track food spend
	currentPower.Value = newPower
	-- Cosmetic TotalFartPower counter: unchanged — still doubles with the pass as before.
	local bonusPower = has2x and food.power or 0
	totalPower.Value = totalPower.Value + food.power + bonusPower
	if totalEarned then totalEarned.Value = totalEarned.Value + food.price end
	pcall(function() RegenEvent:FireClient(player, food.power, currentPower.Value, stomachMax.Value) end)
	print("BOUGHT:", player.Name, foodName, "+", food.power, "power, total:", currentPower.Value)
	-- PET XP (cosmetic-only): eating food = "collecting gas" -> XP for the equipped pet (proportional to the
	-- power/gas gained). Never affects gas/food/flight balance.
	if _G.petOnGas then _G.petOnGas(player, powerGain) end
end)

CoinEvent.OnServerEvent:Connect(function(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local tce   = ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt = tonumber(amount) or 0
	--======================================================================
	-- COIN VALIDATION -- this remote used to accept ANY number the client sent
	--======================================================================
	-- CoinEvent:FireServer(1e9) banked a billion coins instantly. There was no cap, no rate limit and no
	-- check that the sender was even flying; SecurityGuard does not help here, it only removes injected
	-- SCRIPTS and has nothing to say about a legitimate remote being called with a silly number.
	--
	-- ===== WHY THIS IS A BUDGET AND NOT AN EXACT RECOMPUTE =====
	-- The honest fix is for the server to work out flight coins itself and stop trusting the client for the
	-- figure at all. That is a real refactor: the per-stud payout, the descent prepay and the apex settle
	-- all live in CoreClient's flight loop. This bounds the hole hard without touching balance.
	--
	-- ===== THE NUMBERS ARE SIZED OFF REAL WORST CASES, NOT GUESSED =====
	-- Two very different legitimate sources arrive on this same remote:
	--   * FLIGHT TICKS, every COIN_TICK (0.23s): studs travelled * COIN_PER_STUD (3.52) -- x3 on a failed
	--     flight (the 2x descent bonus) -- * serverEventCoinMult (peaks at 2, COIN_RUSH). The biggest
	--     honest tick is an Iron Gut falling at terminal speed during COIN_RUSH: ~5.4k.
	--   * RING BONUSES, bursty: floor(15 * (1 + ringStreak * 0.2) * serverEventRingMult). ringStreak resets
	--     on landing, but serverEventRingMult reaches 10 during a ring event -- so a long streak in that
	--     event legitimately pays ~1,650 in ONE call, at ANY altitude.
	-- That second case is why the window has a flat allowance on top of the per-gut flight budget: a ring
	-- bonus down at the farm must never be rejected and silently rob the player.
	if amt ~= amt or amt == math.huge or amt == -math.huge then return end -- NaN / inf
	if amt <= 0 then return end
	if amt > COIN_MAX_SINGLE then
		warn(("[SECURITY] %s sent a single coin grant of %.0f (cap %d) -- rejected")
			:format(player.Name, amt, COIN_MAX_SINGLE))
		return
	end

	do
		local now = os.clock()
		local w = coinWindow[player]
		if not w or (now - w.t) >= COIN_WINDOW then
			w = { t = now, spent = 0, calls = 0 }
			coinWindow[player] = w
		end
		w.calls = w.calls + 1
		-- CALL-RATE. Legitimate traffic is 2 flight ticks a second plus the odd ring; this allows an order
		-- of magnitude more before it complains, so it only ever catches a script hammering the remote.
		if w.calls > COIN_MAX_CALLS then
			if w.calls == COIN_MAX_CALLS + 1 then
				warn(("[SECURITY] %s is calling CoinEvent %d times in %ds -- throttling")
					:format(player.Name, w.calls, COIN_WINDOW))
			end
			return
		end
		-- BUDGET. The gut is the one input the server owns outright, so the ceiling is "one full flight on
		-- this gut, failed, during COIN_RUSH" -- the most any honest window can carry.
		local sm = ls:FindFirstChild("StomachMax")
		local gutMax = (sm and sm.Value) or 120
		local oneFlight = FlightTuning.fullTankClimb(gutMax) * FlightTuning.COIN_PER_STUD
			* (1 + FlightTuning.DESCENT_PAY_MULT) * COIN_EVENT_PEAK
		local budget = COIN_FLAT_BUDGET + oneFlight
		if (w.spent + amt) > budget then
			warn(("[SECURITY] %s exceeded the coin budget (%.0f + %.0f > %.0f on a %d gut) -- rejected")
				:format(player.Name, w.spent, amt, budget, gutMax))
			return
		end
		w.spent = w.spent + amt
	end
	-- FRIEND/GROUP COIN BOOST: scale earned FLIGHT coins by this player's bonus multiplier (1 = none). Set by
	-- RewardsService (friend-in-server +25%, MLR group +10%, stackable). Flat rewards (codes) are granted directly, unaffected.
	amt = amt * ((_G.coinBonusMult and _G.coinBonusMult[player]) or 1)
	amt = amt * ((_G.rebirthMult and _G.rebirthMult[player]) or 1) -- REBIRTH coin boost (stacks on top of the friend/group boost)
	-- SHADY SAL'S 2x COINS: bought for coins at the secret cave trader. The attribute is an EXPIRY set with
	-- the server clock by SecretTrader.server.lua, and it is checked HERE, server-side, at the moment coins
	-- are banked -- so a client can neither fake a boost nor stretch one past its five minutes.
	if (player:GetAttribute("SalCoinBoostUntil") or 0) > workspace:GetServerTimeNow() then
		amt = amt * 2
	end
	playerCoinAccum[player] = (playerCoinAccum[player] or 0) + amt
	local toAdd = math.floor(playerCoinAccum[player])
	if toAdd > 0 then
		playerCoinAccum[player] = playerCoinAccum[player] - toAdd
		coins.Value = coins.Value + toAdd
		tce.Value   = tce.Value + toAdd
	end
	-- PET XP (cosmetic-only): this coin tick fires every 0.5s DURING FLIGHT, so it feeds BOTH the "coins
	-- earned" and "distance flown" XP sources for the equipped pet. Never affects coins/flight balance.
	if _G.petOnCoins then _G.petOnCoins(player, amt) end
	if _G.petOnFlightTick then _G.petOnFlightTick(player) end
end)


-- LEGACY / UNTRUSTED. The client used to fire this the moment its PEAK HEIGHT cleared an island,
-- which unlocked islands the player had only flown PAST. Unlocking is now driven solely by the
-- physical-landing detection further down (islandUnderCharacter), which raises the Island
-- leaderstat itself.
--
-- This handler is kept and CLAMPED rather than removed, because it cannot simply be deleted:
-- stale baked-in copies of CoreClient in StarterPlayerScripts still fire the old peak-height
-- event, and a client can fire it with any number it likes. So it now refuses to unlock anything
-- the player has not physically reached -- it can never grant progression, only re-assert what
-- landing already earned (useful if the leaderstat and highestIslandReached ever drift).
UnlockIslandEvent.OnServerEvent:Connect(function(player, islandNum)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local island = ls:FindFirstChild("Island"); if not island then return end
	local n = tonumber(islandNum) or 0
	local reached = highestIslandReached[player] or 1
	if n > reached then
		-- flown past, or a spoofed number: not an unlock
		return
	end
	if n > island.Value and n <= 14 then
		island.Value = n
		print("ISLAND "..n.." UNLOCKED by "..player.Name)
		if _G.petOnIsland then _G.petOnIsland(player) end -- PET XP (cosmetic-only): reaching a NEW island -> XP chunk for the equipped pet

		-- NOTE: no arrival message here. The welcome + "[username] landed" broadcast fire ONLY
		-- from the physical-landing detection (Heartbeat above), never from this peak/unlock event.
		-- NOTE: do NOT zero CurrentPower / gas here. Reaching or landing on a new island must
		-- keep whatever fuel the player stopped flying with (after drain + any bird hits).
		-- Landing power-sync is handled by LandingEvent (decrease-only, preserves remaining).
	end
end)

-- Skip Island handler is connected later in this script (near the test hooks) via the shared
-- triggerSkipIsland(), so it can reuse teleportToHome / highestIslandReached / standData, which
-- are defined below this point. See triggerSkipIsland.

-- ===== HIGHEST ISLAND REACHED (home base): respawn + fall-below catch =====
-- Server-authoritative. highestIslandReached only ever increases this session. Physical
-- landings are detected with the server's own short downward raycast, so flying PAST an
-- island (without standing on it) does NOT count. There are NO mid-air parts/floors/clouds;
-- the only solid ground is the existing island Stand parts, and the only time we move the
-- player is the single teleport-to-home-Stand case when they drop below their home island.
local RunService = game:GetService("RunService")
-- highestIslandReached is declared up top (near the DataStore init) so the save/load code can use it.
local CATCH_MARGIN  = 50          -- studs below the home Stand before the Return prompt shows
local STAND_OFFSET_Y = 10         -- place the player this far above the Stand part center
local SPAWN_FRONT_DIST = 14       -- studs IN FRONT of the stand to drop the player (so the booth is ahead of them)
local EXACT_SPAWN_OFFSET_Y = 4    -- when spawning ON a SpawnLocation, lift the player this far above its top surface

-- Which island (if any) is the character physically standing on right now? Must work for
-- ALL 14 stands regardless of their geometry/parenting.
local LAND_RAY      = 14   -- studs to ray downward (start slightly above HRP) — covers thick/offset stands
local STAND_NEAR_XZ = 45   -- fallback: horizontal radius around a Stand position to count as "on it"
local STAND_NEAR_Y  = 30   -- fallback: vertical tolerance around a Stand position
function islandUnderCharacter(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	-- Method A: ray down from just above the HRP and walk up to an Island_N_ ancestor. Starting
	-- a little above the HRP and using a longer ray catches stands whose surface sits lower.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char}
	local res = workspace:Raycast(hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -LAND_RAY, 0), params)
	if res and res.Instance then
		local obj = res.Instance
		while obj and obj ~= workspace do
			local n = obj.Name:match("^Island_(%d+)_")
			if n then return tonumber(n) end
			obj = obj.Parent
		end
	end
	-- Method B (fallback): proximity to a known Stand position. Robust to stands whose parts
	-- aren't named/parented under Island_N_. Caller only runs this while grounded, so being
	-- near a Stand means actually standing on that island. Pick the nearest within tolerance.
	local pos = hrp.Position
	local best, bestDist
	for islandNum, sd in pairs(standData) do
		local dx, dz = pos.X - sd.x, pos.Z - sd.z
		local d2 = dx*dx + dz*dz
		if d2 <= STAND_NEAR_XZ*STAND_NEAR_XZ and math.abs(pos.Y - sd.y) <= STAND_NEAR_Y then
			if not bestDist or d2 < bestDist then best, bestDist = islandNum, d2 end
		end
	end
	return best
end

-- Place the player a bit IN FRONT of the home island's Stand, FACING it — as if they just landed on
-- the path and are looking up at the shop. Same rule for all 14 stands. (The ONLY position clamp we do.)
local function teleportToHome(char, sd)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- EXACT SPAWN (SpawnLocation): place the player ON the pad at that precise spot, facing its orientation —
	-- NOT stepped out in front of a stand. sd.y is already the pad's top surface; lift by the character offset.
	if sd.exact then
		local front = Vector3.new(sd.fx or 0, 0, sd.fz or 1)
		if front.Magnitude < 0.05 then front = Vector3.new(0, 0, 1) end
		front = front.Unit
		local pos = Vector3.new(sd.x, sd.y + EXACT_SPAWN_OFFSET_Y, sd.z)
		hrp.CFrame = CFrame.lookAt(pos, pos + front)
		hrp.AssemblyLinearVelocity = Vector3.zero
		return
	end
	local standCenter = Vector3.new(sd.x, sd.y + STAND_OFFSET_Y, sd.z)
	-- Step out along the booth's front-facing direction, then look back at the booth. If a stand had
	-- no usable orientation, fx/fz default to +Z. (Flip SPAWN_FRONT_DIST's sign if a stand template
	-- ever faces the other way so the player lands behind it.)
	local front = Vector3.new(sd.fx or 0, 0, sd.fz or 1)
	if front.Magnitude < 0.05 then front = Vector3.new(0, 0, 1) end
	front = front.Unit
	local spawnPos = standCenter + front * SPAWN_FRONT_DIST
	-- Face the stand using ONLY the horizontal direction: the look target sits at the spawn's OWN
	-- height, so there is zero pitch and the character stays perfectly upright (no tipping). We set the
	-- HumanoidRootPart CFrame directly — the unambiguous way to orient a character (no model-pivot
	-- guesswork) — so the stand ends up straight ahead of them, not sideways.
	local lookTarget = Vector3.new(standCenter.X, spawnPos.Y, standCenter.Z)
	hrp.CFrame = CFrame.lookAt(spawnPos, lookTarget)
	hrp.AssemblyLinearVelocity = Vector3.zero
end

-- No character spawns on join (CharacterAutoLoads = false), so the player is simply held with no
-- character until they pick an island. SelectIslandEvent spawns them on the chosen island. After
-- that, respawns go to their home/highest island (we LoadCharacter manually since auto-spawn is off).
local hasChosenIsland = {} -- [player] = picked their spawn island this session
local spawnIsland = {}     -- [player] = island to place the NEXT character spawn on

-- Position of the Community Garden (the gardener if present, else the build's centre) — used to make the
-- island-1 spawn FACE the garden so the player's character + camera look at it.
local function findGardenPos()
	local build = workspace:FindFirstChild("CommunityGardenBuild", true)
	if not build then return nil end
	local props = build:FindFirstChild("GardenProps")
	local g = props and props:FindFirstChild("Gardener")
	if not g then
		for _, d in ipairs(build:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("GardenerNPC") then g = d; break end
		end
	end
	local ok, p = pcall(function() return (g or build):GetPivot().Position end)
	return ok and p or nil
end

local function placeOnStand(char, islandNum)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	local sd = standData[islandNum]
	local tries = 0
	while not sd and tries < 50 do task.wait(0.2); sd = standData[islandNum]; tries = tries + 1 end
	-- prefer a placed SpawnLocation (exact spawn) over the stand-front spot, when one exists for this island
	local spot = spawnData[islandNum] or sd
	-- ISLAND 1: spawn FACING the Community Garden, so the on-spawn camera resets behind the player already
	-- looking at it (and the body faces it too). Override the facing with the direction toward the garden, in a
	-- FRESH copy so the saved spawn data is untouched. Brief poll in case the garden is still building.
	if spot and spot.exact and islandNum == 1 then -- only the exact SpawnLocation spawn (facing-only; never shifts position)
		local gp = findGardenPos()
		local pt = 0
		while not gp and pt < 2 do task.wait(0.25); pt = pt + 0.25; gp = findGardenPos() end
		if gp then
			local dx, dz = gp.X - spot.x, gp.Z - spot.z
			local mag = math.sqrt(dx * dx + dz * dz)
			if mag > 0.1 then
				spot = {x = spot.x, y = spot.y, z = spot.z, fx = dx / mag, fz = dz / mag, exact = true}
			end
		end
	end
	if spot then task.wait(0.05); teleportToHome(char, spot) end
end

-- ===== WORMHOLE FAST-TRAVEL =====
-- Place a player on an island's stand IF they've already REACHED it. Called by WormholeService's WormholeWarp
-- RemoteFunction. Server-authoritative: validates islandNum against the SAVED highestIslandReached (never trusts
-- the client) and refuses while airborne. TRAVEL ONLY -- it never unlocks an island or grants any progression.
_G.wormholeMaxIsland = function(player) return highestIslandReached[player] or 1 end
_G.wormholeWarp = function(player, islandNum)
	if not player then return false, "no player" end
	islandNum = tonumber(islandNum); if not islandNum then return false, "bad island" end
	islandNum = math.floor(islandNum)
	local maxI = highestIslandReached[player] or 1
	if islandNum < 1 or islandNum > maxI then return false, "locked" end -- only islands you've reached
	local char = player.Character; if not char then return false, "no character" end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.FloorMaterial == Enum.Material.Air then return false, "airborne" end -- can't warp mid-flight
	placeOnStand(char, islandNum)
	print("[Wormhole] " .. player.Name .. " warped to island " .. islandNum .. " (max " .. maxI .. ")")
	return true
end

local function onCharacterAdded(player, char)
	local target = spawnIsland[player] or highestIslandReached[player] or 1
	spawnIsland[player] = nil
	task.spawn(function()
		placeOnStand(char, target)
		print("SPAWN: placed "..player.Name.." on island "..target)
	end)
	-- Auto-spawn is off, so manually reload the character on death (respawn at the home island).
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			task.wait(Players.RespawnTime)
			if player.Parent then
				spawnIsland[player] = highestIslandReached[player] or 1
				player:LoadCharacter()
			end
		end)
	end
end

-- The loading-screen island menu picks a spawn island. Server-authoritative RE-VALIDATION: the
-- choice is checked against the SAVED highestIslandReached (never trust the client) and clamped to
-- the unlocked range, then the held player is SPAWNED onto that island's stand. This is what puts
-- the player into the world on join (replacing the old auto-teleport-to-highest).
SelectIslandEvent.OnServerEvent:Connect(function(player, islandNum)
	if hasChosenIsland[player] then return end -- one choice per session (the join menu)
	islandNum = tonumber(islandNum); if not islandNum then return end
	islandNum = math.floor(islandNum)
	-- [RESET] all-islands-unlock TEST bypass removed: EVERY player is validated against their REAL reached island
	-- (highestIslandReached), so new players are locked to island 1 and can only spawn on islands they've reached.
	local maxIsland = highestIslandReached[player] or 1
	if islandNum < 1 or islandNum > maxIsland then
		print("ISLAND SELECT: "..player.Name.." requested LOCKED island "..tostring(islandNum).." (max "..maxIsland.."), clamping")
		islandNum = math.clamp(islandNum, 1, maxIsland)
	end
	hasChosenIsland[player] = true
	spawnIsland[player] = islandNum
	player:LoadCharacter() -- spawn the held player; onCharacterAdded teleports to the chosen stand
	print("ISLAND SELECT: "..player.Name.." spawning on island "..islandNum)
	-- ONE-TIME GARDEN INTRO: a brand-new player (hasn't SeenGardenIntro) who picks island 1 gets the cinematic.
	-- Server-authoritative: gated on the saved/restored flag (attribute), so it never replays for returning players.
	-- The client runs the cutscene and fires GardenIntroDoneEvent back, which sets+saves the flag.
	if islandNum == 1 and player:GetAttribute("SeenGardenIntro") ~= true then
		print("GARDEN INTRO: "..player.Name.." selected island 1 for the first time -> playing cinematic")
		-- Fire immediately as the authoritative fallback. The client also self-starts on click (for the instant
		-- black overlay); GardenIntro's `playing` guard makes this a no-op if the client already began.
		pcall(function() GardenIntroEvent:FireClient(player) end)
	end
	-- FART METER RESTORE (after-spawn): the spawn's own onLand fires LandingEvent(0), which zeros the
	-- decrease-only CurrentPower — so we must re-apply the saved meter SERVER-SIDE once the spawn has
	-- settled, then replicate it to the client's gas meter via RegenEvent. This runs AFTER the
	-- character/gas system is up (handles mobile slow-load), so the value sticks instead of being
	-- overwritten by the default. (joinRestoreMeter is unset/0 for lando5485 and brand-new players.)
	task.spawn(function()
		local want = joinRestoreMeter[player]
		joinRestoreMeter[player] = nil
		-- INFINITE GUT owners: the tank is ALWAYS full, so this post-spawn restore must apply the gut MAX, not
		-- the saved meter (which could be 0/low) — otherwise it would overwrite the instant-full meter that
		-- applyInfiniteGut set on join, and the server value would disagree with the client's full/never-drain
		-- meter. Gated on ownership, so NON-owners restore their saved meter exactly as before.
		-- [STOMACH RESET] while the gut is forced to base, NEVER take the full-tank Infinite-Gut branch (so CurrentPower
		-- is the saved meter clamped to the base StomachMax, never the old 9999 full tank).
		local infiniteGut = (not FORCE_BASE_STOMACH) and (player:GetAttribute("HasInfiniteGut") == true)
		if not infiniteGut and (not want or want <= 0) then return end
		task.wait(2.5) -- let the character spawn, settle, and fire its onLand(0) FIRST
		if not player.Parent then return end
		local ls2 = player:FindFirstChild("leaderstats"); if not ls2 then return end
		local cp2 = ls2:FindFirstChild("CurrentPower"); local sm2 = ls2:FindFirstChild("StomachMax")
		if not cp2 then return end
		local gutMax = sm2 and sm2.Value or want or 0
		local applied = infiniteGut and gutMax or math.clamp(math.floor(want), 0, gutMax) -- Infinite Gut -> FULL; else clamp saved
		cp2.Value = applied
		lastMeter[player] = applied
		pcall(function() RegenEvent:FireClient(player, 0, applied, gutMax) end) -- replicate to the client's gas meter UI
		print(string.format("[LOAD METER] player=%s saved=%s applied_to_live=%d%s", player.Name, tostring(want), applied, infiniteGut and " (INFINITE GUT: full)" or ""))
	end)
end)

-- DINOSAUR-SELECT VALIDATION: the client picks a dino island (1-14) and fires this. Re-check it against the
-- server-set "UnlockedDinos" attribute (test accounts get all 14) — never trust the client. On approval we
-- SPAWN the held player so they enter the game (real dino worlds don't exist yet, so this is a PLACEHOLDER
-- spawn onto their home island in the main world), then reply so the client fades in. Shares the
-- SelectIslandEvent one-choice guard (hasChosenIsland) so a player picks ONE destination.
DinoSelectEvent.OnServerEvent:Connect(function(player, dinoNum)
	dinoNum = tonumber(dinoNum)
	if not dinoNum then pcall(function() DinoSelectEvent:FireClient(player, dinoNum, false) end); return end
	dinoNum = math.floor(dinoNum)
	if hasChosenIsland[player] then pcall(function() DinoSelectEvent:FireClient(player, dinoNum, false) end); return end
	-- Fall back to 0, not 1. If the attribute is somehow missing (data still loading, a race on join), the safe
	-- answer is "you have unlocked nothing" -- a fallback of 1 would approve a dino spawn for a player whose
	-- unlocks we cannot actually read, which is the exact case this validation exists to catch.
	local unlocked = tonumber(player:GetAttribute("UnlockedDinos")) or 0
	if isAllowedTestUser(player) then unlocked = DINO_COUNT end -- \xE2\x9A\xA0 TEST: all dino islands unlocked. REMOVE BEFORE LAUNCH.
	local approved = (dinoNum >= 1 and dinoNum <= DINO_COUNT and dinoNum <= unlocked)
	if approved then
		hasChosenIsland[player] = true
		spawnIsland[player] = highestIslandReached[player] or 1 -- PLACEHOLDER: main-world home island until dino worlds exist
		player:LoadCharacter() -- spawn the held player; onCharacterAdded places + handles respawns
	end
	print(string.format("DINO SELECT: %s requested dino island %d (unlocked=%d) -> %s",
		player.Name, dinoNum, unlocked, approved and "APPROVED (placeholder spawn)" or "REJECTED (locked)"))
	pcall(function() DinoSelectEvent:FireClient(player, dinoNum, approved) end)
end)

-- ONE-TIME GARDEN INTRO: the client fires this the moment the cinematic finishes. We mark the flag on the
-- player (so it persists in the next save) and save immediately so a leave right after watching still counts.
-- (lando5485 is force-reset to FALSE on each load, so the intro still replays for him next join despite this.)
GardenIntroDoneEvent.OnServerEvent:Connect(function(player)
	if player:GetAttribute("SeenGardenIntro") == true then return end
	player:SetAttribute("SeenGardenIntro", true)
	print("GARDEN INTRO: "..player.Name.." finished the cinematic -> SeenGardenIntro=true (saving)")
	task.spawn(function() savePlayerData(player, "garden-intro-seen") end)
end)

Players.PlayerAdded:Connect(function(player)
	-- [BALANCE LOGGING] start the session clock + per-island timing baseline.
	sessionStartTime[player] = os.clock()
	lastIslandReachClock[player] = os.clock()
	-- highestIslandReached + HighestIsland attribute are restored by the data-load handler above;
	-- onCharacterAdded waits for that load before placing the player on their home island.
	if player.Character then onCharacterAdded(player, player.Character) end
	player.CharacterAdded:Connect(function(char) onCharacterAdded(player, char) end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- [BALANCE LOGGING] compact one-line session summary you can read the whole run from.
	pcall(function()
		local ls = player:FindFirstChild("leaderstats")
		local coins   = (ls and ls:FindFirstChild("Coins") and ls.Coins.Value) or 0
		local stomach = (ls and ls:FindFirstChild("StomachMax") and ls.StomachMax.Value) or 0
		local hi = highestIslandReached[player] or 1
		local flights = sessionFlights[player] or 0
		local api = attemptsPerIsland[player] or {}
		local parts = {}
		for i = 2, 14 do if api[i] then parts[#parts+1] = "i"..i..":"..api[i] end end
		-- [BALANCE LOGGING] expanded session summary.
		local playtime = sessionStartTime[player] and math.floor(os.clock() - sessionStartTime[player]) or 0
		local totalEarned = (ls and ls:FindFirstChild("TotalCoinsEarned") and ls.TotalCoinsEarned.Value) or 0
		local foodSpent = coinsSpentOnFood[player] or 0
		local gutSpent = coinsSpentOnGuts[player] or 0
		local encounters = birdEncounters[player] or 0
		-- gut purchases list (name @ islandN, t=Xs, flight#)
		local gp = gutPurchases[player] or {}
		local gpParts = {}
		for _, g in ipairs(gp) do gpParts[#gpParts+1] = string.format("%s@i%d(t=%ds,flight#%d)", g.name, g.island, g.time, g.flight) end
		-- server-wide events fired list
		local evParts = {}
		for name, c in pairs(eventsFiredTally) do evParts[#evParts+1] = name..":"..c end
		print("SESSION SUMMARY: highestIsland="..hi..", total playtime="..playtime.."s, total flights="..flights..", attempts per island=["..table.concat(parts, ", ").."], final coins="..coins..", totalCoinsEarned="..totalEarned..", spentOnFood="..foodSpent..", spentOnGuts="..gutSpent..", stomach="..stomach..", gutsBought=["..table.concat(gpParts, ", ").."], serverEventsFired="..eventsFiredCount.." ["..table.concat(evParts, ", ").."], birdEncounters="..encounters)
		-- [BALANCE LOGGING] clean per-island TABLE: island | attempts | time(s) | gut used | save-gate?
		print("SESSION TABLE | island | attempts | time(s) | gutMax | save-gate(save/reach)")
		local irt = islandReachTime[player] or {}
		local sgf = saveGateFlights[player] or {}
		local rff = reachFlights[player] or {}
		local gai = gutAtIsland[player] or {}
		for i = 2, 14 do
			if api[i] then
				print(string.format("  i%-2d | att=%-3d | t=%-7.1f | gutMax=%-5d | %d/%d",
					i, api[i] or 0, irt[i] or 0, gai[i] or 0, sgf[i] or 0, rff[i] or 0))
			end
		end
	end)
	highestIslandReached[player] = nil
	hasChosenIsland[player] = nil
	spawnIsland[player] = nil
	sessionFlights[player] = nil
	strandGrantFlight[player] = nil
	flightsSinceNewIsland[player] = nil
	attemptsPerIsland[player] = nil
	-- [BALANCE LOGGING] clean up the added tracking tables.
	sessionStartTime[player] = nil
	playtimeAtLoad[player]   = nil
	islandReachTime[player] = nil
	lastIslandReachClock[player] = nil
	coinsAtLastIsland[player] = nil
	islandCoinsEarned[player] = nil
	coinsSpentOnFood[player] = nil
	coinsSpentOnGuts[player] = nil
	gutPurchases[player] = nil
	gutBoughtSinceIsland[player] = nil
	saveGateFlights[player] = nil
	reachFlights[player] = nil
	saveGateAccum[player] = nil
	reachAccum[player] = nil
	gutAtIsland[player] = nil
	birdEncounters[player] = nil
	flightsOfSaving[player] = nil
end)

-- ===== WHICH ISLAND DOES "RETURN" MEAN? =====
-- The furthest island the player has actually got to, by ANY route -- and that is more than
-- highestIslandReached alone. That table is raised ONLY by the physical landing detector below, so it misses
-- everything that puts a player on an island without a detected touchdown: the Island leaderstat rises when
-- they unlock one, Skip Island moves their home base, and a wormhole warp drops them straight onto a stand.
-- Reading only the landing table meant the button could still say "Return to Island 3" for someone who had
-- unlocked and travelled to 8 -- offering to send them backwards, which is the opposite of what it is for.
--
-- The max of the three is what the player has already been SHOWN as their progress (the food shop gates on
-- exactly this max, see BuyFoodEvent), so it is the honest answer. Still server-authoritative: every one of
-- these three is written only by server code and never from client input, and the result is clamped to an
-- island whose stand actually exists, so it can never teleport into nothing.
--
-- DECLARED HERE, ABOVE BOTH USES -- the tap handler immediately below and the below-home prompt in the
-- Heartbeat further down. A `local` is invisible to code written above it.
local function maxIslandVisited(player)
	local stats = player:FindFirstChild("leaderstats")
	local lsIsland = stats and stats:FindFirstChild("Island")
	local best = math.max(
		highestIslandReached[player] or 1,
		player:GetAttribute("HighestIsland") or 1,
		(lsIsland and lsIsland.Value) or 1
	)
	-- clamp down to the highest island we actually have a stand for: standData fills in over the first few
	-- seconds, and offering to return somewhere with no stand is a tap that silently does nothing
	while best > 1 and not standData[best] do best = best - 1 end
	return best
end

-- Player tapped the "Return to Island N" button. Server-authoritative: only teleport if they
-- really are below their home island, and only ever to that island's real Stand part.
ReturnToIslandEvent.OnServerEvent:Connect(function(player)
	local hi = maxIslandVisited(player)
	if hi <= 1 then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local sd = standData[hi]
	if not sd then print("RETURN: "..player.Name.." tapped but island "..hi.." stand not loaded yet") return end
	-- Safety button: ALWAYS honor the tap (the button is only shown while the player is below home,
	-- so this can't skip progress — it just returns them to the highest island they already reached).
	-- Previously this re-checked the below-margin condition and could silently no-op; removed so the
	-- tap reliably teleports. teleportToHome places them on the stand, on the ground, facing it.
	teleportToHome(char, sd)
	player:SetAttribute("ReturnPromptIsland", 0)
	print("RETURN: "..player.Name.." returned to home island "..hi.." stand")
end)

-- Rocket event "Go to Island 1" button: teleport the requester to island 1's
-- stand to watch the rocket. Uses the SAME teleportToHome as Return-to-Island
-- (just always island 1). Does NOT change unlocked islands / saved progress --
-- it only moves the character; the fall-catch "Return" prompt still works.
GoToIsland1Event.OnServerEvent:Connect(function(player)
	-- GUARD: this is the ROCKET EVENT's teleport button -- only honor it WHILE the rocket event is
	-- actually running. (Server-authoritative backstop so firing the remote outside an event -- e.g. an
	-- invisible-but-clickable button -- can never teleport.) Flag is set by RocketEventManager.
	local rk = _G.BigEvents and _G.BigEvents.rocket
	if not (rk and rk.isRunning and rk.isRunning()) then
		print("GOTO1: rejected -- no rocket event running ("..player.Name..")")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local sd = standData[1]
	if not sd then print("GOTO1: island 1 stand not loaded yet") return end
	teleportToHome(char, sd)
	print("GOTO1: "..player.Name.." teleported to island 1 for the rocket event")
end)

local detectAccum = 0
RunService.Heartbeat:Connect(function(dt)
	detectAccum = detectAccum + dt
	local doDetect = detectAccum >= 0.1
	if doDetect then detectAccum = 0 end
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local hi = highestIslandReached[plr] or 1
			-- Physical landing detection (throttled): raise home base when standing on a higher island.
			-- This is the ONE authoritative arrival trigger — the personal welcome and the others-only
			-- broadcast both fire from here, never from peak-height/unlock.
			if doDetect and hum.FloorMaterial ~= Enum.Material.Air then
				local n = islandUnderCharacter(char)
				-- WHERE THEY ARE STANDING RIGHT NOW, every detection -- not just on a new personal best.
				-- The food shop's floor rule ("no buying below your feet") needs the CURRENT island, and
				-- the branch below only fires when n beats the record, which would leave this stale the
				-- moment a player flew back down. Published as an attribute so the client can grey the
				-- cells out; the server still re-checks the real position on purchase.
				if n then pcall(function() plr:SetAttribute("CurrentIsland", n) end) end
				if n and n > hi then
					highestIslandReached[plr] = n
					hi = n
					plr:SetAttribute("HighestIsland", n)
					-- THE UNLOCK ITSELF, and the only place it happens. The Island leaderstat is what
					-- gates the food shop, so raising it HERE -- inside the check that requires the
					-- player to be physically standing on island n -- is what makes "you must land on
					-- it" true. Peak height no longer unlocks anything (see UnlockIslandEvent above).
					local lsU = plr:FindFirstChild("leaderstats")
					local islU = lsU and lsU:FindFirstChild("Island")
					if islU and n > islU.Value then
						islU.Value = n
						print("ISLAND "..n.." UNLOCKED by "..plr.Name.." (landed on it)")
						if _G.petOnIsland then _G.petOnIsland(plr) end -- PET XP: reaching a NEW island
					end
					-- Stamp the cumulative playtime at which this island fell. This is what the FASTEST CLIMB board
					-- ranks on, so it is recorded HERE -- at the one authoritative arrival trigger -- and nowhere
					-- else. It always describes the player's CURRENT highest island, which is what the board wants:
					-- "you reached island N, and it took you this long."
					_G.playerIslandTimeSec[plr] = totalPlaytimeSec(plr)
					-- [BALANCE LOGGING] attempts to reach this island = flights since the previous new island.
					local att = flightsSinceNewIsland[plr] or 0
					attemptsPerIsland[plr] = attemptsPerIsland[plr] or {}
					attemptsPerIsland[plr][n] = att
					flightsSinceNewIsland[plr] = 0
					-- [BALANCE LOGGING] per-island metrics: real time, coins earned, save-gate vs reach breakdown,
					-- the gut used, and whether a gut was purchased on the way to this island.
					local nowClock = os.clock()
					local secsToReach = lastIslandReachClock[plr] and (nowClock - lastIslandReachClock[plr]) or 0
					lastIslandReachClock[plr] = nowClock
					islandReachTime[plr] = islandReachTime[plr] or {}
					islandReachTime[plr][n] = sessionStartTime[plr] and (nowClock - sessionStartTime[plr]) or 0
					local lsR = plr:FindFirstChild("leaderstats")
					local tceVal = (lsR and lsR:FindFirstChild("TotalCoinsEarned") and lsR.TotalCoinsEarned.Value) or 0
					local prevTce = coinsAtLastIsland[plr] or 0
					local earnedThis = tceVal - prevTce
					coinsAtLastIsland[plr] = tceVal
					islandCoinsEarned[plr] = islandCoinsEarned[plr] or {}
					islandCoinsEarned[plr][n] = earnedThis
					local sg = saveGateAccum[plr] or 0
					local rf = reachAccum[plr] or 0
					saveGateFlights[plr] = saveGateFlights[plr] or {}; saveGateFlights[plr][n] = sg
					reachFlights[plr] = reachFlights[plr] or {}; reachFlights[plr][n] = rf
					saveGateAccum[plr] = 0; reachAccum[plr] = 0
					local gutMaxNow = (lsR and lsR:FindFirstChild("StomachMax") and lsR.StomachMax.Value) or 0
					gutAtIsland[plr] = gutAtIsland[plr] or {}; gutAtIsland[plr][n] = gutMaxNow
					local gutNameNow = "Gut"
					for _, t in ipairs(stomachTiers) do if t.maxPower == gutMaxNow then gutNameNow = t.name; break end end
					local gutBought = gutBoughtSinceIsland[plr] and true or false
					gutBoughtSinceIsland[plr] = false
					print(string.format("ISLAND REACHED: island %d reached after %d attempts (%d save-gate, %d trying-to-reach) | time=%.1fs | coinsEarnedToHere=%d | gutUsed=%s (maxPower=%d) | gutBoughtOnWay=%s",
						n, att, sg, rf, secsToReach, earnedThis, gutNameNow, gutMaxNow, tostring(gutBought)))
					print("HOME BASE: "..plr.Name.." landed on island "..n)
					local iname = ISLAND_DISPLAY_NAMES[n] or ("Island "..n)
					-- Personal "You reached [Island]!" welcome to the lander only.
					pcall(function() WelcomeEvent:FireClient(plr, n, iname) end)
					-- "[username] landed on [island]" broadcast to EVERYONE EXCEPT the lander.
					for _, other in ipairs(Players:GetPlayers()) do
						if other ~= plr then
							pcall(function() AnnouncementEvent:FireClient(other, plr.Name, n, iname) end)
						end
					end
				end
			end
			-- Below-home prompt (every frame): show the "Return to Island N" button WHENEVER the
			-- player is below their highest-reached island's Y — flying, falling, or standing.
			-- Hidden only when on/above that island. (Client reads the ReturnPromptIsland
			-- attribute.) No auto-teleport — the player chooses to tap the button.
			-- NOT `hi`. `hi` above is the LANDING-DETECTOR's number and it has to stay that way -- it is the
			-- value the `n > hi` test compares against, and widening it there would make a player who unlocked
			-- island 5 without landing never register the landing at all. The BUTTON wants the broader
			-- question ("furthest you have got to by any route"), so it asks separately.
			local homeI = maxIslandVisited(plr)
			local want = 0
			if homeI > 1 then
				local sd = standData[homeI]
				if sd and hrp.Position.Y < sd.y - CATCH_MARGIN then
					want = homeI
				end
			end
			if (plr:GetAttribute("ReturnPromptIsland") or 0) ~= want then
				plr:SetAttribute("ReturnPromptIsland", want)
			end
		end
	end
end)

local PAE_productNames = {
	[PRODUCT_IDS.TwoXOneHour]    = "2x Power 1 Hour",
	[PRODUCT_IDS.MidAirRecharge] = "Mid-Air Recharge",
	[PRODUCT_IDS.SkipIsland]     = "Skip Island",
	[PRODUCT_IDS.BirdNuke]       = "Bird Nuke",
}
local function fireProductAnnouncement(player, productId)
	local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent")
	if PAE then pcall(function() PAE:FireAllClients(player.Name, PAE_productNames[productId] or "an item", false) end) end
end

-- The offensive Bird Nuke, called by ProcessReceipt / the test hooks on a real purchase. OFFENSIVE:
-- broadcast to EVERYONE; the BUYER is spared (their client returns early on the event). Each VICTIM's
-- client KILLS its own character (Humanoid.Health = 0) and, on the normal Roblox respawn, restores its
-- fart meter to THIS flight's LAUNCH amount (the launch-snapshot rule — _G.beamLaunchSnapshot.power —
-- the same data the planes/junk/beams hazards use). The server intentionally does NOT teleport anyone
-- or zero CurrentPower: the existing death->respawn flow (onCharacterAdded's Died handler) already
-- reloads each victim at their home island, and leaving CurrentPower at its mid-flight launch value
-- lets the client restore stick on BOTH sides via the decrease-only landing sync. Server-authoritative
-- on WHO is nuked: only the server fires this event, and the buyer is excluded client-side.
local function triggerBirdNuke(buyer)
	if not buyer then return end
	-- Fire to all clients NOW: boom sound + swarm + nuke visual play immediately; each VICTIM's client
	-- kills its own character on this same event (the buyer is spared client-side).
	if BirdNukeEvent then
		-- HOW MANY PEOPLE THIS ACTUALLY HIT, sent with the event. The buyer's client slams it on screen
		-- ("9 PLAYERS SENT HOME!") -- without it the one person who paid for this has no idea whether it
		-- landed on nine players or on nobody. Counted here because the server is the only place that
		-- knows, and sent to everyone because it costs nothing and only the buyer's branch reads it.
		local victims = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= buyer then victims = victims + 1 end
		end
		pcall(function() BirdNukeEvent:FireAllClients(buyer.Name, victims) end)
		print(("[BirdNuke] %s nuked %d player(s)"):format(buyer.Name, victims))
	end
	-- Purchase banner ("[name] bought Bird Nuke!") — same as before.
	fireProductAnnouncement(buyer, PRODUCT_IDS.BirdNuke)
	-- The server does NOT teleport anyone or zero CurrentPower here. Each victim's client KILLS its own
	-- character on this event and the existing death->respawn flow (onCharacterAdded's Died handler)
	-- reloads them at their home island, so "everyone sent home" is preserved by the respawn itself.
	-- Leaving CurrentPower untouched (it still holds the launch value mid-flight) is what lets the
	-- client's launch-amount restore stick on BOTH sides via the decrease-only landing sync.
end

-- Skip Island effect, factored so the real product (SkipIslandEvent, fired by the hotbar) and the
-- test hooks share ONE path. Teleports the player to the next island ABOVE their current highest
-- (e.g. 6 -> 7), repeatable up to island 14, and moves their home base (highestIslandReached) +
-- Island stat to the new island so respawn/return and unlocks all follow. Server-authoritative.
local function triggerSkipIsland(player)
	if not player then return end
	if DISABLE_PERKS_FOR_BALANCE then print("SKIP: ignored — DISABLE_PERKS_FOR_BALANCE is on"); return end -- [BALANCE] no Skip Island during the no-perks test
	local current = highestIslandReached[player] or 1
	if current >= 14 then print("SKIP: "..player.Name.." already at top island 14"); return end
	local target = current + 1
	highestIslandReached[player] = target
	player:SetAttribute("HighestIsland", target)
	-- Keep the Island leaderstat (drives food-shop unlocks / UI) at least at the new island.
	local ls = player:FindFirstChild("leaderstats")
	local island = ls and ls:FindFirstChild("Island")
	if island and island.Value < target then island.Value = target end
	-- Teleport onto the new island's home Stand — same system as Return-to-Island / respawn.
	local sd = standData[target]
	local char = player.Character
	if sd and char then
		print("SKIP: "..player.Name.." -> island "..target)
		pcall(function() teleportToHome(char, sd) end)
	else
		print("SKIP: "..player.Name.." set to island "..target.." but no teleport (stand="..tostring(sd~=nil)..", char="..tostring(char~=nil)..")")
	end
end

-- TEST: jump straight to ANY island (chat "goisland<N>", N=1..14). Mirrors triggerSkipIsland's bookkeeping but
-- to an arbitrary island: raises home base (highestIslandReached) + HighestIsland attr + Island stat to at least N
-- so respawn/return/shop follow, then teleports onto that island's home stand. Server-authoritative; test users only.
local function goToIsland(player, n)
	if not player then return end
	n = math.clamp(math.floor(tonumber(n) or 0), 1, 14)
	if (highestIslandReached[player] or 1) < n then
		highestIslandReached[player] = n
		player:SetAttribute("HighestIsland", n)
	end
	local ls = player:FindFirstChild("leaderstats")
	local island = ls and ls:FindFirstChild("Island")
	if island and island.Value < n then island.Value = n end
	local sd = standData[n]
	local char = player.Character
	if sd and char then
		print("[GOISLAND] " .. player.Name .. " -> island " .. n)
		pcall(function() teleportToHome(char, sd) end)
	else
		print("[GOISLAND] " .. player.Name .. " island " .. n .. " not ready (stand=" .. tostring(sd ~= nil) .. ", char=" .. tostring(char ~= nil) .. ")")
	end
end

-- REBIRTH RESET (exposed for RebirthSystem.server). Unlike Skip/goToIsland this LOWERS the run back to the
-- start: home base + Island stat -> 1, coins -> base, gut -> base, meter -> 0, then respawns onto Bean Farm
-- (onCharacterAdded reads highestIslandReached/spawnIsland, both set to 1 here). Pets, gamepasses and lifetime
-- totals are NOT touched -- those live elsewhere. Server-authoritative; RebirthSystem validates before calling.
_G.rebirthResetHome = function(player)
	if not player then return end
	highestIslandReached[player] = 1
	spawnIsland[player] = 1
	player:SetAttribute("HighestIsland", 1)
	loadedStomachMax[player] = DEFAULT_STOMACH
	joinRestoreMeter[player] = 0; lastMeter[player] = 0
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local function setv(name, v) local s = ls:FindFirstChild(name); if s then s.Value = v end end
		setv("Island", 1); setv("Coins", DEFAULT_COINS); setv("StomachMax", DEFAULT_STOMACH); setv("CurrentPower", 0)
	end
	print("[Rebirth] " .. player.Name .. " island run reset -> Bean Farm (island 1, coins=" .. DEFAULT_COINS .. ", gut base)")
	pcall(function() player:LoadCharacter() end) -- respawn -> onCharacterAdded places on island 1's home stand
end

-- Real Skip Island product (hotbar): teleport to the next island + move home base.
SkipIslandEvent.OnServerEvent:Connect(function(player) triggerSkipIsland(player) end)

-- Mid-Air Recharge REFILL effect — factored so the REAL product (ProcessReceipt) and the TEST hook below
-- call ONE path (no duplicated logic). Sets the server CurrentPower to the full gut max (StomachMax) so
-- the 100% refill STICKS through the decrease-only LandingEvent sync, then fires the client `rechargeNow`
-- so the client refills its display (a mid-flight-paused player stays frozen with a full meter). isTest=true
-- also sets `rechargeTest` so the client refills its display even when NOT paused — letting the refill be
-- confirmed in Studio without a real purchase. (Real purchases never pass isTest.)
local function triggerMidAirRecharge(player, isTest)
	if not player then return end
	local cur = player:GetAttribute("MidAirRechargeCount") or 0
	player:SetAttribute("MidAirRechargeCount", cur + 1)
	local ls = player:FindFirstChild("leaderstats")
	local cp = ls and ls:FindFirstChild("CurrentPower")
	local sm = ls and ls:FindFirstChild("StomachMax")
	if cp and sm then cp.Value = sm.Value end -- server meter -> 100% (gut max); a PAID increase, like a food buy
	if GamepassEvent then
		pcall(function() GamepassEvent:FireClient(player, {midAirRecharge = cur + 1, rechargeNow = true, rechargeTest = isTest and true or nil}) end)
	end
	if isTest then
		print(string.format("[TEST RECHARGE] %s -> CurrentPower set to %d (gut max); client rechargeNow fired", player.Name, (cp and cp.Value) or -1))
	end
end

-- (Pre-launch cleanup: the [TESTING ONLY] Bird Nuke "/nuke" + _G.testBirdNuke and Mid-Air Recharge
-- "/recharge" + _G.testMidAirRecharge manual triggers were removed. triggerBirdNuke and
-- triggerMidAirRecharge remain — they are the REAL effects called by ProcessReceipt below.)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- BLIMP feed + top-donator board: observe EVERY product before the branches below, so donations and
	-- future products show up without another hook. Display-only and pcall'd -- it must never fail a purchase.
	if _G.blimpRecordPurchase then
		pcall(function() _G.blimpRecordPurchase(player, info.ProductId) end)
	end
	if info.ProductId == PRODUCT_IDS.TwoXOneHour then
		player:SetAttribute("TwoXHourExpiry", os.time() + 3600)
		if GamepassEvent then
			pcall(function() GamepassEvent:FireClient(player, {twoXHourExpiry=os.time()+3600}) end)
		end
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.MidAirRecharge then
		-- Refill via the shared path: bumps MidAirRechargeCount, sets the server CurrentPower to the gut
		-- max (so the 100% STICKS past the decrease-only landing sync), and fires the client rechargeNow
		-- refill. (No isTest -> real-purchase behavior: client refills only while mid-flight-paused.)
		triggerMidAirRecharge(player)
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.SkipIsland then
		-- AUTO-SKIP ON PURCHASE: perform the skip IMMEDIATELY here via the SAME triggerSkipIsland the SKIP
		-- hotbar button used to call — purchase now = instant skip, no second button press. We intentionally
		-- NO LONGER fire the {skipIsland=...} client flag, so no consumable "charge" is granted: the SKIP
		-- hotbar slot stays at 0 and is inert (its click guard needs skipIsland>0, and the hotbar only shows
		-- when a charge exists), so the second step is bypassed. The skip BEHAVIOR is unchanged.
		local cur = player:GetAttribute("SkipIslandCount") or 0
		player:SetAttribute("SkipIslandCount", cur + 1) -- lifetime purchase counter only; no longer a button charge
		triggerSkipIsland(player)
		fireProductAnnouncement(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == PRODUCT_IDS.BirdNuke then
		-- Real purchase: run the offensive nuke (swarm + every other player dies & respawns home + banner).
		triggerBirdNuke(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- COIN PACKS. Credited to Coins only, deliberately NOT to TotalCoinsEarned: that value is the record of
	-- what a player FLEW for, and it is what the leaderboard and the coin badges read. Letting Robux write
	-- to it would put paying players at the top of a board that is supposed to measure climbing.
	local packCoins = COIN_PACKS[info.ProductId]
	if packCoins then
		local ls = player:FindFirstChild("leaderstats")
		local c  = ls and ls:FindFirstChild("Coins")
		if not c then
			-- No leaderstats yet means the join load has not finished. Returning NotProcessedYet asks Roblox
			-- to hand us the same receipt again shortly -- which is exactly right, and is why the coins
			-- cannot be lost by buying during a slow join.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		c.Value = c.Value + packCoins
		-- Bank it immediately. A pack is real money, and the gap between granting and the next autosave is
		-- the one window where a server crash would take it back.
		pcall(function() savePlayerData(player, "coinpack") end)
		fireProductAnnouncement(player, info.ProductId)
		print(("[Shop] %s bought %d coins (product %d)"):format(player.Name, packCoins, info.ProductId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- GARDEN DONATION Developer Product (tip jar, cosmetic-only): CommunityGarden handles it -- thank-you + banner
	-- ONLY, no stat/coin/pet/garden change. Checked before the pet handler; each owns a disjoint set of product IDs.
	if _G.gardenHandleDonationReceipt then
		local granted = false
		pcall(function() granted = _G.gardenHandleDonationReceipt(player, info.ProductId) end)
		if granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end
	-- PET upgrade Developer Product (cosmetic-only): PetSystem handles it + levels up the player's pending pet.
	if _G.petsHandleReceipt then
		local granted = false
		pcall(function() granted = _G.petsHandleReceipt(player, info.ProductId) end)
		if granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end
	-- (PET WHEEL spin packs are gone with the wheel. Its Developer Product ids were never created -- the wheel
	-- shipped in TEST_MODE -- so no live receipt can arrive for them and nothing needs a compatibility path.)
	-- CRATE TOKEN packs (Developer Products): SkinCrateService handles it + credits the purchased tokens. Owns its
	-- own disjoint set of product IDs (see SkinCrates.TOKEN_PACKS). Credits only on a confirmed receipt.
	if _G.skinCrateHandleReceipt then
		local granted = false
		pcall(function() granted = _G.skinCrateHandleReceipt(player, info.ProductId) end)
		if granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	local gpData = {}
	if passId == GAMEPASS_IDS.TwoXForever and not FORCE_NO_2X then -- [NOSAVE TEST] don't grant 2x while forced un-owned. REMOVE BEFORE LAUNCH.
		player:SetAttribute("HasTwoXForever", true); gpData.twoXForever = true
	elseif passId == GAMEPASS_IDS.GlitterTrail then
		player:SetAttribute("HasGlitterTrail", true); gpData.glitterTrail = true
	elseif passId == GAMEPASS_IDS.InfiniteGut then
		applyInfiniteGut(player) -- gut becomes UNLIMITED immediately; effect is the StomachMax (+StomachUpdateEvent), so no gpData client flag is needed
	-- The `> 0` guard matters: an unconfigured pass has id 0, and without it a 0 id would sit in this chain
	-- ready to match on any falsy/zero passId. Every new pass takes effect the instant the attribute is set --
	-- luck is read at roll time, VipService watches the attribute, and the magnet is a client-side reader.
	elseif GAMEPASS_IDS.LuckyPass > 0 and passId == GAMEPASS_IDS.LuckyPass then
		player:SetAttribute("HasLuckyPass", true); gpData.luckyPass = true
	elseif GAMEPASS_IDS.VIP > 0 and passId == GAMEPASS_IDS.VIP then
		player:SetAttribute("HasVIP", true); gpData.vip = true
	elseif GAMEPASS_IDS.CoinMagnet > 0 and passId == GAMEPASS_IDS.CoinMagnet then
		player:SetAttribute("HasCoinMagnet", true); gpData.coinMagnet = true
	end
	if GamepassEvent and next(gpData) then
		pcall(function() GamepassEvent:FireClient(player, gpData) end)
	end
	-- Built from the shared NAMES table so a renamed pass renames itself in the server-wide purchase banner too.
	-- Unset (0) passes are filtered out so they can't collide on the key 0.
	local passNames = {}
	for key, id in pairs(GAMEPASS_IDS) do
		if id > 0 then passNames[id] = Gamepasses.NAMES[key] or key end
	end
	local passName = passNames[passId] or "a gamepass"
	local PAE = RS:FindFirstChild("PurchaseAnnouncementEvent")
	if PAE then pcall(function() PAE:FireAllClients(player.Name, passName, true) end) end
end)

-- ===== SERVER-WIDE EVENT LOOP =====
local eventPool = {
	{name="FART_STORM",   dispName="\xF0\x9F\x92\xA8 FART STORM",   weight=15, dur=7, msg="\xF0\x9F\x92\xA8 FART STORM! Everyone flies faster for 7 seconds!",       r=100,g=200,b=255},
	{name="COIN_RUSH",    dispName="\xF0\x9F\x92\xB0 COIN RUSH",    weight=15, dur=7, msg="\xF0\x9F\x92\xB0 COIN RUSH! Double coins for 7 seconds!",                  r=255,g=200,b=0},
	-- DISPLAY-NAME-ONLY rename: shown to players as "HIGH GRAVITY". The internal key
	-- stays "LOW_GRAVITY" so the client handler (EventClient ~938) and all mechanics
	-- (speed/gas-drain multipliers, weight, 10s duration) are completely unchanged.
	{name="LOW_GRAVITY",  dispName="\xF0\x9F\x8C\x99 HIGH GRAVITY",  weight=15, dur=10, msg="\xF0\x9F\x8C\x99 HIGH GRAVITY! Float like a cloud for 10 seconds!",        r=150,g=100,b=255},
	{name="POWER_SURGE",  dispName="\xE2\x9A\xA1 POWER SURGE",      weight=15, dur=8,  msg="\xE2\x9A\xA1 POWER SURGE! Fly higher than ever for 8 seconds!",          r=255,g=255,b=0},
	{name="RING_FEVER",   dispName="\xF0\x9F\x8E\xAF RING FEVER",   weight=15, dur=30, msg="\xF0\x9F\x8E\xAF RING FEVER! Massive ring bonuses for 30 seconds!",       r=255,g=100,b=200},
	-- 60s (was 25). This is the ONE authority for the length: the server broadcasts `dur` alongside the event
	-- name and EventClient's startThunderstorm(dur) uses whatever arrives -- its own `or 25` is only a
	-- fallback for a broadcast that somehow carries no duration, so it does NOT need changing to match.
	-- Campfires stay doused for the whole storm plus their 10s dry-out, so they are now out for ~70s.
	{name="THUNDERSTORM", dispName="\xe2\x9b\x88 THUNDERSTORM",     weight=15, dur=40, msg="\xe2\x9b\x88\xef\xb8\x8f THUNDERSTORM! Hard to see!",                    r=50, g=50, b=80},
	{name="WINDSTORM",    dispName="\xF0\x9F\x92\xA8 WIND STORM",   weight=10, dur=20, msg="\xF0\x9F\x92\xA8 WIND STORM! Fighting the wind!",                        r=100,g=150,b=200},
}

local function pickRandomEvent()
	return eventPool[math.random(1, #eventPool)]
end

-- Single unified event loop: random event every 4 minutes
task.spawn(function()
	if DISABLE_EVENTS then print("EVENTS DISABLED (DISABLE_EVENTS) — no random server events will fire") return end
	task.wait(240)
	while true do
		local ev = pickRandomEvent()
		-- [BALANCE LOGGING] count server events fired (overall + per-name) for the session summary.
		eventsFiredCount = eventsFiredCount + 1
		eventsFiredTally[ev.name] = (eventsFiredTally[ev.name] or 0) + 1
		print("NEXT EVENT:", ev.name, "(server events fired so far:", eventsFiredCount..")")
		pcall(function()
			ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
		end)
		workspace:SetAttribute("ActiveServerEvent", ev.name) -- server-readable flag (e.g. the campfire douses in THUNDERSTORM)
		-- TWO MORE ATTRIBUTES, for anything that wants to SHOW the event rather than react to it (the blimp's
		-- WHAT'S ON page). ActiveServerEvent is the internal key (THUNDERSTORM); this is the name a player
		-- should read, plus when it ends so a countdown can be drawn without guessing the duration.
		workspace:SetAttribute("ActiveServerEventName", ev.dispName or ev.name)
		workspace:SetAttribute("ActiveServerEventEndsAt", os.time() + ev.dur)
		task.wait(ev.dur + 2)
		pcall(function()
			ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1,1,1))
		end)
		workspace:SetAttribute("ActiveServerEvent", "")
		workspace:SetAttribute("ActiveServerEventName", "")
		workspace:SetAttribute("ActiveServerEventEndsAt", 0)
		task.wait(240)
	end
end)

-- \xE2\x9A\xA0 TEST COMMAND: /thunderstorm triggers the storm on demand. REMOVE BEFORE LAUNCH.
-- Lets a test account fire the THUNDERSTORM big event instantly instead of waiting for the timer.
-- It uses the EXISTING event path -- the same ServerEventNotify FireAllClients + scheduled "END"
-- the random loop above uses -- so the storm runs EXACTLY like normal, just on command. This does
-- NOT change the storm or the scheduler's normal behavior (the loop above is untouched and keeps
-- running on its own timer). Gated to the test accounts so random players can't trigger it.
-- \xE2\x9A\xA0 TEST COMMANDS allowed for: lando5485, Broskie310111. REMOVE BEFORE LAUNCH.
-- (The shared ALLOWED_TEST_USERS list + isAllowedTestUser() are defined near the top of this file so the
-- island-select all-unlock and these chat commands can both use them. /thunderstorm checks it below.)
local function fireThunderstormNow()
	local ev
	for _, e in ipairs(eventPool) do if e.name == "THUNDERSTORM" then ev = e break end end
	if not ev then return end
	pcall(function()
		ServerEventNotify:FireAllClients(ev.name, ev.dispName, ev.dur, ev.msg, Color3.fromRGB(ev.r, ev.g, ev.b))
	end)
	workspace:SetAttribute("ActiveServerEvent", ev.name)
	workspace:SetAttribute("ActiveServerEventName", ev.dispName or ev.name)   -- same pair the random loop sets
	workspace:SetAttribute("ActiveServerEventEndsAt", os.time() + ev.dur)
	task.delay(ev.dur + 2, function() -- end it after its duration, exactly like the random loop does
		pcall(function() ServerEventNotify:FireAllClients("END", "", 0, "", Color3.new(1,1,1)) end)
		workspace:SetAttribute("ActiveServerEvent", "")
		workspace:SetAttribute("ActiveServerEventName", "")
		workspace:SetAttribute("ActiveServerEventEndsAt", 0)
	end)
end
-- \xE2\x9A\xA0 TEST: quick "get<tier>gut" chat commands to grab any gut tier instantly (for belly/flight testing).
-- REMOVE BEFORE LAUNCH. Example: type  gettinygut  (or /gettinygut) in chat.
local GUT_CMDS = {
	gettinygut = "Tiny Gut", getsmallgut = "Small Gut", getmediumgut = "Medium Gut",
	getlargegut = "Large Gut", getxlgut = "XL Gut", getirongut = "Iron Gut", getinfinitegut = "Infinite Gut",
}
local function giveGut(player, gutName)
	local tier; for _, t in ipairs(stomachTiers) do if t.name == gutName then tier = t; break end end
	if not tier then return end
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local sm = ls:FindFirstChild("StomachMax"); if not sm then return end
	sm.Value = tier.maxPower
	local cp = ls:FindFirstChild("CurrentPower")
	if cp then cp.Value = math.min(cp.Value, tier.maxPower) end -- carry/clamp current gas to the new tank
	if tier.maxPower >= INFINITE_GUT_MAX then player:SetAttribute("HasInfiniteGut", true) end
	pcall(function() StomachUpdateEvent:FireClient(player, tier.maxPower, tier.name) end)
	pcall(function() RegenEvent:FireClient(player, 0, cp and cp.Value or 0, tier.maxPower) end)
	print("[TEST] gave "..player.Name.." "..tier.name.." (maxPower "..tier.maxPower..")")
end

-- â  TEST command body, lifted out of the Chatted closure so the TextChatService registration below can
-- route into the SAME code. REMOVE BEFORE LAUNCH.
local function handleTestChat(player, msg)
		local cmd = string.lower(tostring(msg or "")):match("^%s*(.-)%s*$") -- trim + lowercase
		if cmd == "/birdnuke" then
			-- BIRD NUKE COMMAND -- its OWN allow-list, DELIBERATELY TIGHTER than ALLOWED_TEST_USERS:
			-- exclusively lando5485 and Broskie310111 may fire it. The shared test list also carries the
			-- itsmaddmax accounts, and they must NOT have this -- a nuke hits every player on the server.
			-- Routes through triggerBirdNuke, the same path a real purchase takes, so the effect/announce/
			-- knockdown behave identically to a paid nuke.
			local nm = string.lower(player.Name)
			if nm ~= "lando5485" and nm ~= "broskie310111" then
				print("[BirdNuke] DENIED /birdnuke for '" .. player.Name .. "' -- owner-only command.")
				return
			end
			print("[BirdNuke] /birdnuke fired by " .. player.Name .. " (owner command)")
			triggerBirdNuke(player)
		elseif cmd == "/thunderstorm" then
			if not isAllowedTestUser(player) then return end -- shared test-user allow-list (lando5485 + the two test accounts)
			print("[TEST] /thunderstorm command used by " .. player.Name .. " - firing thunderstorm event. REMOVE BEFORE LAUNCH.")
			fireThunderstormNow()
		elseif cmd == "/allpets" then -- \xE2\x9A\xA0 TEST COMMAND /allpets - grants all pets to test accounts. REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end -- same allow-list as the other test commands (non-test players: ignored)
			-- Report what actually happened: the old form pcall'd the grant then printed success
			-- unconditionally, so a missing global or an error inside PetSystem still read as 'granted'.
			if not _G.petsGrantAll then
				warn("[TEST] /allpets: _G.petsGrantAll is not defined -- PetSystem did not load or failed early.")
			else
				local okGrant, errGrant = pcall(_G.petsGrantAll, player)
				if okGrant then print("[TEST] /allpets used by " .. player.Name .. " - granted all pets. REMOVE BEFORE LAUNCH.")
				else warn("[TEST] /allpets FAILED for " .. player.Name .. ": " .. tostring(errGrant)) end
			end
		elseif cmd == "/rarepets" then -- \xE2\x9A\xA0 TEST COMMAND /rarepets - grants every pet as its RARE variant. REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end
			-- Report what actually happened: the old form pcall'd the grant then printed success
			-- unconditionally, so a missing global or an error inside PetSystem still read as 'granted'.
			if not _G.petsGrantRare then
				warn("[TEST] /rarepets: _G.petsGrantRare is not defined -- PetSystem did not load or failed early.")
			else
				local okGrant, errGrant = pcall(_G.petsGrantRare, player)
				if okGrant then print("[TEST] /rarepets used by " .. player.Name .. " - granted all RARE pets. REMOVE BEFORE LAUNCH.")
				else warn("[TEST] /rarepets FAILED for " .. player.Name .. ": " .. tostring(errGrant)) end
			end
		elseif cmd == "/offline" or cmd:match("^/offline%s+%d+$") then
			-- \xE2\x9A\xA0 TEST COMMAND /offline - simulate a rejoin after being away, and show the welcome-back HUD.
			-- REMOVE BEFORE LAUNCH.
			-- Runs the REAL grant path (same maths, same payout, same card) against a simulated away-time, so what
			-- you see is exactly what a returning player sees -- it isn't a mock-up of the card.
			-- "/offline"      -> simulates the full 6-hour cap.
			-- "/offline 1800" -> simulates being away 1800 seconds (30 min), so you can check partial windows.
			if not isAllowedTestUser(player) then return end
			local secs = tonumber(cmd:match("(%d+)")) or (OFFLINE_MAX_HOURS * 3600)
			local r = offerOfflineEarnings(player, secs, true)
			if not r then
				-- tell the tester WHY nothing happened rather than silently doing nothing
				print(string.format("[TEST] /offline by %s -> NO PAYOUT (need >= %ds away and >= 1 pet owned; away=%ds)",
					player.Name, OFFLINE_MIN_SECONDS, secs))
			end
		elseif cmd == "/10pets" then -- \xE2\x9A\xA0 TEST COMMAND /10pets - complete the COLLECTION. REMOVE BEFORE LAUNCH.
			-- Grants the 10 pets that COUNT toward the collection, then runs the real milestone check -- so all three
			-- titles fire in order (3 -> 5 -> 7, ending on "Beastmaster") and the secret Pizza Dragon is awarded by
			-- the actual 10/10 code path. Deliberately does NOT hand the Dragon over directly: the whole point is to
			-- exercise the reward logic, not to bypass it.
			if not isAllowedTestUser(player) then return end
			if _G.petsGrantCollection then pcall(function() _G.petsGrantCollection(player) end) end
			print("[TEST] /10pets used by " .. player.Name .. " - completed the collection (titles + secret pet). REMOVE BEFORE LAUNCH.")
		elseif cmd:match("^/?goisland%s*%d+$") then -- \xE2\x9A\xA0 TEST: "goisland1".."goisland14" -> teleport to that island (slash optional). REMOVE BEFORE LAUNCH.
			if not isAllowedTestUser(player) then return end
			goToIsland(player, cmd:match("(%d+)"))
		else -- \xE2\x9A\xA0 TEST: instant gut tiers — "gettinygut", "getsmallgut", ... (slash optional). REMOVE BEFORE LAUNCH.
			local gutName = GUT_CMDS[cmd] or GUT_CMDS[(cmd:gsub("^/", ""))]
			if gutName then
				if not isAllowedTestUser(player) then return end
				giveGut(player, gutName)
			end
		end
end

local function hookTestStormChat(player) -- â  TEST: legacy-chat path. REMOVE BEFORE LAUNCH.
	-- â  TEST: on lando5485's join, print their userId so it can be hardcoded by id later. REMOVE BEFORE LAUNCH.
	if string.lower(player.Name) == "lando5485" then
		print("[TEST] lando5485 joined - userId = " .. player.UserId .. " (can hardcode this in the allowed list)")
	end
	player.Chatted:Connect(function(msg) handleTestChat(player, msg) end)
end
for _, p in ipairs(Players:GetPlayers()) do hookTestStormChat(p) end
Players.PlayerAdded:Connect(hookTestStormChat)

-- â  TEST: the modern chat (TextChatService) does NOT fire Player.Chatted, so every command above was
-- dead on this place -- /allpets and /rarepets included. Register them as real slash commands too, the same way
-- RealmPortals and DevCommands do. Both paths call handleTestChat, so there is one implementation.
-- NOTE: the no-slash spellings ("goisland3", "getlargegut") only ever worked on the legacy chat; use the slash
-- forms registered here. REMOVE BEFORE LAUNCH.
do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local function reg(name, primary, secondary)
			local c = Instance.new("TextChatCommand")
			c.Name = name; c.PrimaryAlias = primary
			if secondary then c.SecondaryAlias = secondary end
			c.Parent = TextChatService
			c.Triggered:Connect(function(source, text)
				local plr = source and Players:GetPlayerByUserId(source.UserId)
				-- Printed BEFORE the allow-list check, so the log separates 'never reached the server' from
				-- 'server got it and refused'. Those two need completely different fixes.
				print(string.format("[TEST] slash %q from %s", tostring(text), plr and plr.Name or "<unknown>"))
				if plr then handleTestChat(plr, text) end
			end)
		end
		reg("TestPetsCommand",       "/allpets",      "/rarepets")
		reg("BirdNukeCommand",       "/birdnuke") -- owner-only inside handleTestChat (lando5485 + Broskie310111 ONLY)
		reg("TestCollectionCommand", "/10pets",       "/thunderstorm")
		reg("TestOfflineCommand",    "/offline",      "/goisland")
		reg("TestGutCommand1",       "/gettinygut",   "/getsmallgut")
		reg("TestGutCommand2",       "/getmediumgut", "/getlargegut")
		reg("TestGutCommand3",       "/getxlgut",     "/getirongut")
		reg("TestGutCommand4",       "/getinfinitegut")
	end)
	if ok then print("[TEST] chat commands registered with TextChatService (/allpets /rarepets /10pets /thunderstorm /offline /goisland /get*gut)")
	else warn("[TEST] TextChatService command registration failed: " .. tostring(err)) end
end

-- (Daily Rewards claim handler removed.)

LandingEvent.OnServerEvent:Connect(function(player, remainingPower, birdHit, realAttempt)
	-- [LOGGING ACCURACY] Count this landing as a flight ATTEMPT only when the client reports a REAL flight
	-- (genuine fart-launch + airtime > 3s). This excludes spawn falls, post-teleport settles, walk-offs, and
	-- aborted near-zero launches. ALL attempt counters (session, since-new-island, saving, save-gate/reach,
	-- bird) are gated together so they stay mutually consistent (attempts == saveGate + reach).
	if realAttempt then
		sessionFlights[player] = (sessionFlights[player] or 0) + 1
		flightsSinceNewIsland[player] = (flightsSinceNewIsland[player] or 0) + 1
		flightsOfSaving[player] = (flightsOfSaving[player] or 0) + 1
		-- [BALANCE LOGGING] bird encounter flag passed from the client (remainingPower stays the first arg).
		if birdHit then birdEncounters[player] = (birdEncounters[player] or 0) + 1 end
		-- [BALANCE LOGGING] classify this attempt as a SAVE-GATE flight (current gut physically can't reach the
		-- next island: 50 + gutMax*14 < nextIslandY) or a TRYING-TO-REACH flight. Tallied per next-island.
		pcall(function()
			local lsd = player:FindFirstChild("leaderstats")
			local smv = lsd and lsd:FindFirstChild("StomachMax") and lsd.StomachMax.Value or 0
			local hi = highestIslandReached[player] or 1
			local nextN = math.min(hi + 1, 14)
			local nextY = ISLAND_POSITIONS[nextN] and ISLAND_POSITIONS[nextN].y or math.huge
			local gutCeil = 50 + smv * 14
			if gutCeil < nextY then
				saveGateAccum[player] = (saveGateAccum[player] or 0) + 1
			else
				reachAccum[player] = (reachAccum[player] or 0) + 1
			end
		end)
	end
	-- Landing keeps whatever gas the player did NOT burn in flight. The client reports its
	-- actual remaining power; sync the server to it so the next purchase validates against the
	-- real remaining space. Only ever allow this to DECREASE CurrentPower (power is added solely
	-- by server-validated BuyFood), so it can't be exploited to inflate power. If the player
	-- drained the whole tank the reported value is naturally 0.
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower")
	local sm = ls:FindFirstChild("StomachMax")
	if not cp then return end
	local reported = math.floor(tonumber(remainingPower) or 0)
	local newVal = math.clamp(reported, 0, cp.Value)
	if newVal ~= cp.Value then
		cp.Value = newVal
		pcall(function() RegenEvent:FireClient(player, 0, newVal, sm and sm.Value or 120) end)
	end
	lastMeter[player] = cp.Value -- snapshot the last-known live meter for SAVE (so a later respawn-zero can't persist a stale 0)
end)

BuyStomachEvent.OnServerEvent:Connect(function(player, newMax, cost)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins")
	local stomachMaxStat = ls:FindFirstChild("StomachMax")
	if not coins or not stomachMaxStat then return end
	local newMaxN = tonumber(newMax) or 0
	local costN   = tonumber(cost)   or 0
	-- [TEST] TEST_FULL_DATA: free switch to ANY real tier (ignore cost + coins) so every tier's reach
	-- can be sampled in one run. Still validates the maxPower is a real tier; changes nothing about flight.
	if TEST_FULL_DATA then
		if newMaxN <= 0 then return end
		local ok = false
		for _, tier in ipairs(stomachTiers) do if tier.maxPower == newMaxN then ok = true; break end end
		if not ok then return end
		stomachMaxStat.Value = newMaxN
		local cp = ls:FindFirstChild("CurrentPower"); local carried = 0
		if cp then cp.Value = math.min(cp.Value, newMaxN); carried = cp.Value end -- carry over power (clamp to new max)
		pcall(function() RegenEvent:FireClient(player, 0, carried, newMaxN) end)
		local nameStr = "Gut"
		for _, t in ipairs(stomachTiers) do if t.maxPower == newMaxN then nameStr = t.name; break end end
		pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, nameStr) end)
		print("TEST_FULL_DATA: "..player.Name.." switched to "..nameStr.." (maxPower "..newMaxN..") for FREE")
		return
	end
	if costN <= 0 or newMaxN <= 0 then return end
	local valid = false
	local wantTier = nil
	for _, tier in ipairs(stomachTiers) do
		if tier.maxPower == newMaxN and tier.cost == costN and not tier.robux then
			valid = true; wantTier = tier; break
		end
	end
	if not valid then return end
	-- ISLAND LOCK. A gut cannot be bought before the player has physically REACHED the island it
	-- unlocks on. Checked against highestIslandReached (the landing-detection value), NOT the Island
	-- leaderstat, so it means "you got there", and enforced HERE because the client's shop is only a
	-- display: it can be a stale baked-in copy, or simply lied to, and the coins move on this line.
	local reachedNow = highestIslandReached[player] or 1
	if wantTier.island and reachedNow < wantTier.island then
		print(("STOMACH LOCKED: %s tried to buy %s (needs island %d, reached %d)")
			:format(player.Name, wantTier.name, wantTier.island, reachedNow))
		pcall(function() StomachLockedEvent:FireClient(player, wantTier.name, wantTier.island) end)
		return
	end
	-- MUST BE AN UPGRADE. The loop above only proves the (maxPower, cost) pair is a REAL tier — it never checked
	-- the tier is bigger than the one already owned, so a player could re-buy their current gut, or even a
	-- SMALLER one, and the server would happily take the coins and shrink StomachMax.
	--
	-- That is also the one and only path on which the next-island fill below turns into a FULL STOMACH: the fill
	-- is clamped to the new tank, so asking for a tank that cannot hold the power the next island needs pins the
	-- meter at 100%. On the real ladder every upgrade lands between 53% and 70% (Small 70, Medium 53, Large 60,
	-- XL 63, Iron 59), but re-buying Large at island 11 wants 1343 into a 1075 tank -> clamped -> free full tank
	-- for 5,200 coins, which is cheaper than the food. Requiring a strict increase removes the exploit and the
	-- downgrade in one line, and leaves the fill unable to reach 100% at all.
	if newMaxN <= stomachMaxStat.Value then return end
	if coins.Value < costN then return end
	local coinsBeforeBuy = coins.Value -- [BALANCE LOGGING] snapshot before deducting
	coins.Value = coins.Value - costN
	coinsSpentOnGuts[player] = (coinsSpentOnGuts[player] or 0) + costN -- [BALANCE LOGGING] track gut spend
	stomachMaxStat.Value = newMaxN
	-- ===== A GUT ARRIVES EMPTY (FlightTuning.COURTESY_FRACTION = 0) =====
	-- It used to come FULL. That handed out a free crossing with every purchase: the wall crossing the gut
	-- was bought for was always cleared on the very next launch, and the most meaningful decision in the
	-- game turned into a cutscene. Now you buy the gut, then go and earn a meal for it -- the purchase is a
	-- step, not a teleport. Whatever was already in the tank is KEPT (fuel is never wiped), just re-sent so
	-- the client's meter re-scales against the bigger max.
	do
		local cp = ls:FindFirstChild("CurrentPower")
		if cp then
			cp.Value = math.clamp(cp.Value, 0, newMaxN)
			pcall(function() RegenEvent:FireClient(player, 0, cp.Value, newMaxN) end)
		end
	end
	local tierNameStr = "Gut"
	for _, t in ipairs(stomachTiers) do
		if t.maxPower == newMaxN then tierNameStr = t.name; break end
	end
	pcall(function() StomachUpdateEvent:FireClient(player, newMaxN, tierNameStr) end)
	-- [BALANCE LOGGING] record this gut purchase + print a labeled line.
	local lsIsland = ls:FindFirstChild("Island")
	local atIsland = (lsIsland and lsIsland.Value) or (highestIslandReached[player] or 1)
	local playtime = sessionStartTime[player] and math.floor(os.clock() - sessionStartTime[player]) or 0
	local savingFlights = flightsOfSaving[player] or 0
	local flightNum = sessionFlights[player] or 0
	gutPurchases[player] = gutPurchases[player] or {}
	table.insert(gutPurchases[player], {name=tierNameStr, island=atIsland, time=playtime, flight=flightNum})
	gutBoughtSinceIsland[player] = true -- per-island flag: a gut was bought on the way to the next island
	flightsOfSaving[player] = 0 -- reset flights-of-saving counter for the next gut
	print(string.format("BOUGHT GUT: %s for %d, at island %d, after %d flights of saving, coins before/after=%d/%d, total playtime=%ds",
		tierNameStr, costN, atIsland, savingFlights, coinsBeforeBuy, coins.Value, playtime))
end)

print("STANDS COMPLETE")
print("GAMEPASS FIXES DONE")
print("ERRORS FIXED")
print("REVERTED")
print("DONE")
