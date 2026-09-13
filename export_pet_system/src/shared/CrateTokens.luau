--!nonstrict
-- CrateTokens (ReplicatedStorage/Shared/CrateTokens)
-- ============================================================================================================
-- SINGLE SOURCE OF TRUTH for the COSMETIC currency: Crate Tokens.
--
-- TWO CURRENCIES, kept strictly apart:
--   * Food Coins   (leaderstats.Coins)       -- earned by playing. Buys food, gut upgrades, progression.
--                                               MUST NEVER buy a skin crate.
--   * Crate Tokens (leaderstats.CrateTokens) -- earned from quests/realms/streaks/events/codes, or bought with
--                                               Robux. Spends ONLY on cosmetics.
--
-- The separation is enforced in ONE place -- SkinCrateService, which is the only script that spends tokens and
-- never reads Coins. Nothing in the crate path can touch the coin economy, and nothing in the food/gut path can
-- touch tokens, so a balance change on one side can't leak into the other.
--
-- This module holds the AMOUNTS only. The SERVER is the sole authority on granting them (SkinCrateService's
-- _G.crateTokensAward), so a client that fakes a "daily complete" gets nothing.
-- ============================================================================================================

local CrateTokens = {}

CrateTokens.CURRENCY_NAME = "Crate Tokens"
CrateTokens.LEADERSTAT    = "CrateTokens" -- the IntValue name in leaderstats (PlayerStats creates it)
CrateTokens.ICON          = "\xF0\x9F\x8E\x9F"  -- 🎟

-- Hard ceiling, so a bugged grant loop can never mint an absurd balance into a save.
CrateTokens.MAX_BALANCE = 1000000

-- ---- EARN AMOUNTS -------------------------------------------------------------------------------------------
-- Every source the spec calls for. Tune freely -- these are the only numbers that decide how fast a
-- non-spending player earns crates. At Starter Crate = 100 tokens, the defaults below mean roughly:
--   a full daily sweep (3 tasks + the daily bonus)      ~=  95 tokens/day
--   a weekly clear                                       = 150 tokens
--   so ~6-7 free Starter crates a week without paying.
--
-- ⚠ NOT RESCALED WITH THE CRATE PRICES -- ON PURPOSE, PENDING YOUR CALL.
-- The island ladder below WAS re-struck for the new prices, because it is sized against a specific basket of
-- crates and would otherwise contradict its own stated total. This table is not: it pays flat amounts that
-- were never pinned to a crate price, so nothing here has gone self-inconsistent. What HAS changed is what
-- they buy -- the same ~95/day used to be a Starter crate every two-and-a-half days and is now roughly one a
-- day, and a realmComplete (400) went from under two Starters to four.
-- If you want the daily/weekly economy held where it was, multiply this whole table by 0.4 (dailyTask 25->10,
-- weeklyAllTasks 150->60, realmComplete 400->160, and so on) and the old pacing comes straight back.
CrateTokens.REWARDS = {
	dailyTask      = 25,   -- one daily task completed
	dailyAllTasks  = 20,   -- bonus for clearing the whole daily list
	weeklyTask     = 60,   -- one weekly task completed
	weeklyAllTasks = 150,  -- bonus for clearing the weekly list
	realmComplete  = 400,  -- finishing a realm (Candy / Dino / Space / the main island run)
	questLine      = 200,  -- finishing a whole quest line (e.g. every pet quest on a realm)
	petQuest       = 75,   -- a single pet quest completed
	seasonPassFree = 50,   -- a free-lane Season Pass tier
	seasonPassPaid = 120,  -- a premium-lane Season Pass tier
	eventReward    = 100,  -- a live event objective
	promoCode      = 250,  -- default for a code that grants tokens (a code may override with its own amount)
}

-- ---- ISLAND TASKS -------------------------------------------------------------------------------------------
-- ONE TASK PER QUEST ISLAND, CLAIMABLE ONCE EACH. A finite ladder, not a daily faucet: five payouts total for
-- the life of a save, worth more the higher you climb.
--
-- ONLY FIVE ISLANDS HAVE ONE. The other nine have no quest NPC -- IslandNPCs logs "no 'Quest' NPC found" for
-- every one of them at boot, and PetSystem only defines islandPrefix for these five. So this table is keyed by
-- ISLAND NUMBER rather than being a 1..14 list: keying it by position would quietly pay out on islands that
-- have nothing to do, and adding a sixth quest island later should be one line here, not a re-index.
--
-- THE NUMBER THE LADDER IS BUILT AROUND. Clearing all five buys exactly what was asked for:
--     5 x Starter (100) + 1 x Premium (250) = 750   -- and the five rewards sum to 750 on the nose.
-- Spend it all on Starters instead and it is 7 spins with 50 left.
--
-- Pacing that falls out of it: the first task alone (100) is exactly one Starter crate, so the reward is
-- immediately spendable rather than being savings you cannot use; the first Premium lands at island 8
-- (100 + 125 = 225 at island 5, still short of 250; 375 by island 8, comfortably over).
--
-- ===== RESCALED WITH THE CRATE PRICES, NOT INDEPENDENTLY OF THEM =====
-- The ladder used to read 250/310/370/430/490 = 1,850, sized against Starter 250 / Premium 600. Those crates
-- were repriced to 100 / 250, so the same tokens bought two and a half times as much: the five tasks alone
-- went from "5 Starters and a Premium" to over eighteen Starters, and every island task silently became a
-- far bigger payout than it was ever designed to be.
--
-- So the ladder is re-struck against the NEW prices rather than left at its old face value. The target moved
-- 1,850 -> 750 (x0.405) and the old rungs scale onto exact round numbers -- 100/125/150/175/200, an even +25
-- a rung where it used to be +60 -- so the shape, the ordering and both pacing rules above survive intact.
-- What a player can buy at each island is unchanged; only the numerals are smaller.
--
-- If you move a crate price again, move this ladder with it: the invariant to preserve is
--     sum(ISLAND_TASK) == 5 x StarterPrice + 1 x PremiumPrice
-- and ISLAND_TASK[2] == StarterPrice, so the first reward is always immediately spendable.
CrateTokens.ISLAND_TASK = {
	[2]  = 100,  -- Broccoli Bluff    -- Sprout, The Grower          (exactly one Starter crate)
	[5]  = 125,  -- Coconut Cove      -- Coco, The Beachcomber
	[8]  = 150,  -- Popcorn Pinnacle  -- Reel, The Projectionist     (cumulative 375 -> first Premium)
	[10] = 175,  -- Butter Swamp      -- Butters, The Angler
	[13] = 200,  -- Burrito Barrens   -- Dusty, The Digger
}

-- What island N's task pays, or 0 if that island has no task. Zero is the honest answer for the nine islands
-- without a quest NPC -- amountFor's caller already drops a 0 grant, so a stray call costs nothing.
function CrateTokens.islandTaskReward(island)
	return CrateTokens.ISLAND_TASK[math.floor(tonumber(island) or 0)] or 0
end

-- Everything the ladder pays if you clear all five. Derived, never typed in, so the total quoted above cannot
-- quietly stop being true when a reward is retuned.
function CrateTokens.islandTaskTotal()
	local t = 0
	for _, v in pairs(CrateTokens.ISLAND_TASK) do t = t + v end
	return t
end

-- ---- LOGIN STREAK -------------------------------------------------------------------------------------------
-- Day N of a consecutive-login streak. Beyond the table the last value repeats, so a long streak keeps paying
-- without needing an entry per day.
CrateTokens.LOGIN_STREAK = { 20, 30, 40, 60, 80, 110, 200 }

function CrateTokens.loginStreakReward(day)
	local d = math.max(1, math.floor(tonumber(day) or 1))
	return CrateTokens.LOGIN_STREAK[math.min(d, #CrateTokens.LOGIN_STREAK)]
end

-- ---- ANTI-FARM CAPS -----------------------------------------------------------------------------------------
-- Optional per-source daily ceilings. A source NOT listed here is uncapped (one-off grants like realmComplete
-- and questLine don't need a cap -- they can only fire once). Sources that a player could conceivably repeat are
-- capped so a bug in a caller can't become an infinite token faucet.
-- Expressed as HOW MANY OF THIS SOURCE PER DAY, not as an absolute token number.
--
-- WHY UNITS AND NOT TOKENS. These used to be absolute (dailyTask = 100, i.e. "4 tasks' worth at 25 each"),
-- which is exact only while the reward is a fixed 25. Once a source scales with island the cap and the payout
-- round independently and drift apart: at island 7 four tasks pay 4 x round(25 x 1.46) = 148, while scaling
-- the flat cap gives round(100 x 1.46) = 146 -- so the fourth task quietly paid 2 short and logged it as
-- anti-farm. Counting UNITS makes the ceiling mean exactly what it says at every island, by construction,
-- with no second rounding to disagree with the first.
CrateTokens.DAILY_CAP_UNITS = {
	dailyTask   = 4,   -- the four tasks on the daily list, even if the task system somehow re-fires
	weeklyTask  = 5,
	eventReward = 4,
	petQuest    = 4,
}

-- ISLAND TASKS get a FLAT ceiling instead of a unit count, because their payouts are not uniform -- island 14
-- is worth nearly four times island 1, so "N units' worth" has no single value. The ceiling is the whole
-- ladder: a player can legitimately clear several islands in one session, but never more than all fourteen,
-- so a caller bug cannot mint past one complete run per day.
CrateTokens.DAILY_CAP_FLAT = {
	islandTask = nil, -- filled in below from the ladder itself, so it can never drift from it
}
CrateTokens.DAILY_CAP_FLAT.islandTask = CrateTokens.islandTaskTotal()

-- N units x what one unit pays, or a flat ceiling for the sources that have one. Built from the same
-- amountFor() the grant itself uses, so the cap and the payout cannot disagree.
function CrateTokens.dailyCapFor(source)
	local flat = CrateTokens.DAILY_CAP_FLAT[source]
	if flat then return flat end
	local units = CrateTokens.DAILY_CAP_UNITS[source]
	if not units then return nil end
	return units * CrateTokens.amountFor(source)
end

-- The two sources whose value depends on an argument rather than being a flat rate: which streak day, and
-- which island. Everything else is a fixed number from REWARDS.
function CrateTokens.amountFor(source, ...)
	if source == "loginStreak" then return CrateTokens.loginStreakReward(...) end
	if source == "islandTask"  then return CrateTokens.islandTaskReward(...) end
	return CrateTokens.REWARDS[source] or 0
end

function CrateTokens.dailyCap(source)
	return CrateTokens.dailyCapFor(source) -- nil = uncapped
end

-- "1,800" -- thousands separators for the HUD balance
function CrateTokens.format(n)
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return CrateTokens
