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
-- non-spending player earns crates. At Starter Crate = 250 tokens, the defaults below mean roughly:
--   a full daily sweep (3 tasks + the daily bonus)      ~=  95 tokens/day
--   a weekly clear                                       = 150 tokens
--   so ~2-3 free Starter crates a week without paying.
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
CrateTokens.DAILY_CAPS = {
	dailyTask   = 100,  -- 4 tasks' worth, even if the task system somehow re-fires
	weeklyTask  = 300,
	eventReward = 400,
	petQuest    = 300,
}

function CrateTokens.amountFor(source, ...)
	if source == "loginStreak" then return CrateTokens.loginStreakReward(...) end
	return CrateTokens.REWARDS[source] or 0
end

function CrateTokens.dailyCap(source)
	return CrateTokens.DAILY_CAPS[source] -- nil = uncapped
end

-- "1,800" -- thousands separators for the HUD balance
function CrateTokens.format(n)
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return CrateTokens
