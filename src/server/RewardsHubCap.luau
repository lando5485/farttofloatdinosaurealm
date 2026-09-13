--[[
	RewardsHubCap.luau  (ServerScriptService.RewardsHubCap)

	THE REWARDS HUB'S DAILY TICKET CEILING: 300 tickets per player per UTC day, across the DAILY login streak
	and the TIMED playtime ladder TOGETHER -- and across EVERY REALM. (COMMUNITY pays pet levels and the day-7 /
	daily crate is a spin, so neither counts.) Rewards pay tickets, never coins: coins drive planet progression.

	CROSS-REALM. The realms are places in ONE Roblox experience (universe 10236070926), and DataStores are scoped
	to the universe -- so every realm that requires this module reads and writes the SAME per-player total.
	Collect 300 in the Food Realm and Space Realm has nothing left to pay you today, and the reverse.

	ATOMIC, NOT CACHED. Every payout reserves its tickets with ONE UpdateAsync on the shared store BEFORE the
	faucet runs, so two realms (or a teleport landing before the old server's cached read catches up) can never
	both see room for the same tickets. If the faucet then pays less than was reserved, the difference is handed
	back. If the store can't be reached, NOTHING pays ("try again") -- an outage must not become an uncapped day.

	API (DailyStreak.server and SessionRewards.server require this):
	  Cap.LIMIT                          300
	  Cap.remaining(player) -> n         what's left today, from the last value seen in the store (for display)
	  Cap.pay(player, amount, source)    -> got, reason   got = tickets that actually landed (0..amount);
	                                     reason when got == 0: "cap" (limit reached), "store" (DataStore failed),
	                                     "faucet" (SkinCrateService not up yet / paid nothing), "none" (amount 0)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Cap = {}
Cap.LIMIT = 300

-- Shared by EVERY PLACE IN THIS UNIVERSE. Do not rename it per realm, or each realm gets its own 300.
local store = DataStoreService:GetDataStore("RewardsHubDaily_v1")
local known = {} -- [player] = { day, paid } -- last total seen in the store; display only, never authoritative

local function today() return math.floor(os.time() / 86400) end
local function keyFor(player) return tostring(player.UserId) end

local function paidToday(v)
	if type(v) == "table" and tonumber(v.day) == today() then
		return math.max(0, math.floor(tonumber(v.paid) or 0))
	end
	return 0
end

local function refresh(player)
	local ok, v = pcall(function() return store:GetAsync(keyFor(player)) end)
	if ok then known[player] = { day = today(), paid = paidToday(v) } end
end
Cap.refresh = refresh

function Cap.remaining(player)
	local k = known[player]
	local paid = (k and k.day == today()) and k.paid or 0
	return math.max(0, Cap.LIMIT - paid)
end

-- Take up to `amount` of today's room in ONE transaction. Returns how much fit, or nil if the store failed.
local function reserve(player, amount)
	local give, newPaid = 0, nil
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			local paid = paidToday(old)
			give = math.min(amount, math.max(0, Cap.LIMIT - paid))
			newPaid = paid + give
			if give <= 0 then return nil end -- full: cancel, nothing to write
			return { day = today(), paid = newPaid }
		end)
	end)
	if not ok then return nil end
	known[player] = { day = today(), paid = newPaid or 0 }
	return give
end

-- Hand back tickets that were reserved but never paid.
local function refund(player, amount)
	if amount <= 0 then return end
	local newPaid = nil
	local ok = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if type(old) ~= "table" or tonumber(old.day) ~= today() then return nil end
			newPaid = math.max(0, paidToday(old) - amount)
			return { day = today(), paid = newPaid }
		end)
	end)
	if ok and newPaid then known[player] = { day = today(), paid = newPaid } end
end

function Cap.pay(player, amount, source)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return 0, "none" end
	if type(_G.crateTokensAward) ~= "function" then return 0, "faucet" end

	local give = reserve(player, amount)
	if give == nil then return 0, "store" end
	if give <= 0 then return 0, "cap" end

	local ok, got = pcall(_G.crateTokensAward, player, source, nil, give)
	got = ok and math.floor(tonumber(got) or 0) or 0
	if got < give then refund(player, give - got) end
	if got <= 0 then return 0, "faucet" end
	return got, nil
end

Players.PlayerAdded:Connect(function(p) task.spawn(refresh, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(refresh, p) end
Players.PlayerRemoving:Connect(function(p) known[p] = nil end)

return Cap
