--[[
	UniverseBoosts.server.luau  (ServerScriptService.DinosaurRealmServer.UniverseBoosts)

	TIMED BOOSTS THAT FOLLOW THE PLAYER EVERYWHERE. The "2x Power (1 Hour)" product used to live only in
	the TwoXHourExpiry attribute: it vanished on rejoin, on a realm hop and on a server shutdown, so a player
	who used 30 minutes here and then travelled lost the other 30. Now every timed boost is an ABSOLUTE
	expiry timestamp (os.time()) held in one universe-wide DataStore, loaded on join and merged with whatever
	the teleport payload carried in. Absolute timestamps mean "30 minutes used in one realm" arrives as "30
	minutes left" in the next with no clock arithmetic anywhere.

	  Store   UniverseBoosts_v1, key tostring(userId), { twoXHourExpiry = <os.time()>, v = 1 }
	  Rule    every merge is max(local, incoming); nothing ever shortens a boost. Expired fields are pruned.
	  Attr    TwoXHourExpiry -- what Shop.server (the multiplier) and ShopKit.client (the countdown) read.
	  Client  GamepassEvent { twoXHourExpiry = n } repaints the countdown the moment anything changes.

	Permanent gamepasses (2x Forever, Glitter, Primal Gut) are NOT here: their ids are identical in every
	realm and PurchaseReceipts re-checks UserOwnsGamePassAsync on join, which is already universe-wide.

	Public hooks (all guarded, all safe before load):
	  _G.boostsGet(player)                  -> { twoXHourExpiry = n | nil } (session cache)
	  _G.boostsExtend(player, field, secs)  -> new expiry. Stacks on the CURRENT expiry (a repeat buy adds an
	                                           hour, it never truncates), persists, sets the attribute, fires the event.
	  _G.boostsApply(player, incoming)      -> max-merge a payload table, persist, set attributes, fire the event.
	  _G.boostsForPayload(player)           -> the table WormholeService puts on the hop (live fields only).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "UniverseBoosts_v1"
local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)

-- field -> the player attribute the rest of the realm reads
local FIELDS = {
	twoXHourExpiry = "TwoXHourExpiry",
}
local MAX_AHEAD = 24 * 3600 -- a boost can never run more than a day into the future (clock skew / corrupt payload guard)

local cache  = {} -- [player] = { field = absExpiry }
local loaded = {} -- [player] = true once the store answered (a write before that could erase a real boost)

local function keyFor(player) return tostring(player.UserId) end
local function now() return os.time() end

local function clean(t)
	local out = {}
	for field in pairs(FIELDS) do
		local v = math.floor(tonumber(type(t) == "table" and t[field]) or 0)
		if v > now() then out[field] = math.min(v, now() + MAX_AHEAD) end
	end
	return out
end

local function fireClient(player)
	local ge = ReplicatedStorage:FindFirstChild("GamepassEvent")
	if not ge then return end
	local payload = {}
	for field in pairs(FIELDS) do payload[field] = cache[player] and cache[player][field] or nil end
	pcall(function() ge:FireClient(player, payload) end)
end

local function applyAttributes(player)
	local c = cache[player] or {}
	for field, attr in pairs(FIELDS) do
		local v = c[field]
		if v and v > now() then
			-- never shorten: an attribute set by something else (a purchase landing first) is kept if longer
			local cur = tonumber(player:GetAttribute(attr)) or 0
			if v > cur then player:SetAttribute(attr, v) end
		end
	end
end

-- max-merge `incoming` (a payload table or the store record) into the cache; returns true if anything grew
local function mergeInto(player, incoming)
	local c = cache[player] or {}
	local grew = false
	for field, v in pairs(clean(incoming)) do
		if v > (c[field] or 0) then c[field] = v; grew = true end
	end
	cache[player] = c
	return grew
end

local function persist(player, why)
	if not (store and loaded[player]) then return end
	local snapshot = clean(cache[player])
	task.spawn(function()
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(old)
				local rec = (type(old) == "table") and old or {}
				for field in pairs(FIELDS) do
					local mine, theirs = snapshot[field] or 0, math.floor(tonumber(rec[field]) or 0)
					local best = math.max(mine, theirs)
					rec[field] = (best > now()) and best or nil -- prune the expired
				end
				rec.v = 1
				return rec
			end)
		end)
		if not ok then warn(("[UniverseBoosts] save failed for %s (%s): %s"):format(player.Name, tostring(why), tostring(err))) end
	end)
end

-- ===== public hooks =====
_G.boostsGet = function(player)
	return table.clone(cache[player] or {})
end

_G.boostsExtend = function(player, field, seconds)
	if not FIELDS[field] then return nil end
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local cur = math.max(now(), (cache[player] and cache[player][field]) or 0, tonumber(player:GetAttribute(FIELDS[field])) or 0)
	local new = cur + seconds -- STACKS: a second hour bought with 20 minutes left = 80 minutes
	mergeInto(player, { [field] = new })
	applyAttributes(player)
	persist(player, "extend " .. field)
	fireClient(player)
	print(("[UniverseBoosts] %s: %s -> expires in %ds"):format(player.Name, field, new - now()))
	return new
end

_G.boostsApply = function(player, incoming)
	if type(incoming) ~= "table" then return false end
	local grew = mergeInto(player, incoming)
	applyAttributes(player)
	if grew then persist(player, "arrival merge"); fireClient(player) end
	return grew
end

_G.boostsForPayload = function(player)
	local out = clean(cache[player])
	-- also pick up an attribute set by something that bypassed the cache (never lose time on the way out)
	for field, attr in pairs(FIELDS) do
		local a = math.floor(tonumber(player:GetAttribute(attr)) or 0)
		if a > now() and a > (out[field] or 0) then out[field] = math.min(a, now() + MAX_AHEAD) end
	end
	return next(out) and out or nil
end

-- ===== join: load, then merge with whatever the arrival stashed =====
local function onJoin(player)
	local rec
	if store then
		local ok, res = pcall(function() return store:GetAsync(keyFor(player)) end)
		if ok then loaded[player] = true; rec = res
		else warn(("[UniverseBoosts] load failed for %s -- boosts NOT saved this session: %s"):format(player.Name, tostring(res))) end
	end
	mergeInto(player, rec)
	-- the arrival payload (stashed by ArrivalReceiver) may carry MORE time than the store: legacy field
	-- names from the other realms are honoured too, so they need no edits over there
	local d = _G.incomingFtFData and _G.incomingFtFData[player]
	if type(d) == "table" then
		local inc = {}
		if type(d.boosts) == "table" then for k, v in pairs(d.boosts) do inc[k] = v end end
		if d.twoXHourExpiry then inc.twoXHourExpiry = math.max(inc.twoXHourExpiry or 0, tonumber(d.twoXHourExpiry) or 0) end
		if d.powerBoostExpiry then inc.twoXHourExpiry = math.max(inc.twoXHourExpiry or 0, tonumber(d.powerBoostExpiry) or 0) end -- the Space realm's name
		mergeInto(player, inc)
	end
	applyAttributes(player)
	persist(player, "join merge")
	fireClient(player)
	local c = cache[player] or {}
	if c.twoXHourExpiry then print(("[UniverseBoosts] %s: 2x power has %ds left (carried across realms/rejoins)"):format(player.Name, c.twoXHourExpiry - now())) end
end

Players.PlayerAdded:Connect(function(p)
	task.spawn(function()
		-- let ArrivalReceiver stash the payload first (it runs synchronously in its own PlayerAdded), then load
		task.wait(0.5)
		onJoin(p)
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(function(p)
	if cache[p] and next(cache[p]) then persist(p, "leave") end
	task.delay(5, function() cache[p] = nil; loaded[p] = nil end)
end)

print(("[UniverseBoosts] ready -- timed boosts persist in %s and ride the teleport payload as absolute expiries (2x hour keeps its remaining time across realms)"):format(STORE_NAME))
