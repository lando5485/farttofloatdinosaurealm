--======================================================================
-- SeasonPass.server.lua  (Script -> ServerScriptService)
--======================================================================
-- The Season Pass every big game has. You earn PASS XP by completing DAILY TASKS; XP fills a track of tiers.
-- Each tier has a FREE reward (coins) everyone gets, and a PREMIUM reward (bigger coins + pet levels) unlocked
-- with a one-time Robux purchase. XP and claimed tiers PERSIST (a dedicated DataStore).
--
-- SERVER-AUTHORITATIVE: the client only draws the track and requests a claim by tier + lane. XP is granted
-- here (by wrapping _G.dailyTaskDone), ownership is checked with UserOwnsGamePassAsync, and every claim is
-- validated (enough XP? not already claimed? owns premium for the premium lane?) before anything is granted.
--
-- ⚠ SET PREMIUM_GAMEPASS_ID to your "Season Pass Premium" gamepass. While it's 0, the premium lane shows
-- "Coming soon" and can't be bought -- everything else (free lane, XP, claiming) works.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

--------------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------------
local SEASON_ID    = 1     -- bump this to start a fresh season (changes the save key -> everyone starts over)
local XP_PER_TASK  = 25    -- pass XP granted per daily task completed
local TIER_XP      = 100   -- XP to advance one tier (so ~4 tasks per tier)
local PREMIUM_GAMEPASS_ID = 0 -- ⚠ your "Season Pass Premium" gamepass id (0 = premium locked / not for sale yet)

-- the track. free = coins everyone gets; prem = the premium lane (coins + optional pet levels).
local TIERS = {
	{ free = { coins = 50 },   prem = { coins = 150 } },
	{ free = { coins = 75 },   prem = { coins = 250 } },
	{ free = { coins = 100 },  prem = { coins = 350, pet = 1 } },
	{ free = { coins = 150 },  prem = { coins = 500 } },
	{ free = { coins = 200 },  prem = { coins = 700, pet = 2 } },
	{ free = { coins = 300 },  prem = { coins = 1000 } },
	{ free = { coins = 400 },  prem = { coins = 1500, pet = 2 } },
	{ free = { coins = 600 },  prem = { coins = 2200 } },
	{ free = { coins = 800 },  prem = { coins = 3000, pet = 3 } },
	{ free = { coins = 1200 }, prem = { coins = 5000, pet = 5 } },
}

--------------------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------------------
local store = DataStoreService:GetDataStore("SeasonPass_v" .. SEASON_ID)

local function getOrCreate(className, name)
	local o = ReplicatedStorage:FindFirstChild(name)
	if not o then o = Instance.new(className); o.Name = name; o.Parent = ReplicatedStorage end
	return o
end
-- client -> server: "claim",{tier,lane} | "buy". server -> client: "state",{...} | "result",tier,lane,ok,msg
local remote = getOrCreate("RemoteEvent", "SeasonPassEvent")

local data      = {} -- [player] = { xp =, free = {tier=true}, prem = {tier=true} }
local premium   = {} -- [player] = bool (owns the premium gamepass)

local function keyFor(userId) return "Player_" .. tostring(userId) end

local function creditCoins(player, amount)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins"); local tce = ls:FindFirstChild("TotalCoinsEarned")
	if coins then coins.Value = coins.Value + amount end
	if tce then tce.Value = tce.Value + amount end
end

local function currentTier(d) return math.floor((d.xp or 0) / TIER_XP) end -- tiers fully EARNED (claimable up to this)

--------------------------------------------------------------------------------
-- state <-> client
--------------------------------------------------------------------------------
local function pushState(player)
	local d = data[player] or {}
	local tiers = {}
	for i, t in ipairs(TIERS) do
		tiers[i] = {
			freeCoins = t.free.coins, premCoins = t.prem.coins, premPet = t.prem.pet or 0,
			freeClaimed = d.free and d.free[i] == true, premClaimed = d.prem and d.prem[i] == true,
		}
	end
	pcall(function()
		remote:FireClient(player, "state", {
			xp = d.xp or 0, tierXp = TIER_XP, earnedTier = currentTier(d),
			premium = premium[player] == true, forSale = PREMIUM_GAMEPASS_ID ~= 0, gamepassId = PREMIUM_GAMEPASS_ID,
			tiers = tiers,
		})
	end)
end

--------------------------------------------------------------------------------
-- XP
--------------------------------------------------------------------------------
local function grantXP(player, amount)
	local d = data[player]; if not d then return end
	d.xp = (d.xp or 0) + amount
	pushState(player)
	-- (saved on the throttled autosave below, and on leave)
end

-- Wrap the daily-tasks completion hook so finishing a task also feeds the pass. Wait for DailyTasks to define
-- it first, THEN wrap -- otherwise DailyTasks would overwrite our wrapper when it loads.
task.spawn(function()
	for _ = 1, 60 do if type(_G.dailyTaskDone) == "function" then break end; task.wait(0.5) end
	local real = _G.dailyTaskDone
	_G.dailyTaskDone = function(player, id)
		if real then real(player, id) end
		if data[player] then grantXP(player, XP_PER_TASK) end
	end
	print("[SeasonPass] hooked daily-task XP (+" .. XP_PER_TASK .. " per task)")
end)

--------------------------------------------------------------------------------
-- claiming
--------------------------------------------------------------------------------
local function claim(player, tierIndex, lane)
	local d = data[player]; if not d then return end
	local t = TIERS[tierIndex]; if not t then return end
	if tierIndex > currentTier(d) then
		pcall(function() remote:FireClient(player, "result", tierIndex, lane, false, "Not enough XP yet") end); return
	end

	if lane == "free" then
		d.free = d.free or {}
		if d.free[tierIndex] then return end
		d.free[tierIndex] = true
		creditCoins(player, t.free.coins)
		pcall(function() remote:FireClient(player, "result", tierIndex, lane, true, "+" .. t.free.coins .. " coins!") end)
	elseif lane == "prem" then
		if not premium[player] then
			pcall(function() remote:FireClient(player, "result", tierIndex, lane, false, "Premium locked") end); return
		end
		d.prem = d.prem or {}
		if d.prem[tierIndex] then return end
		d.prem[tierIndex] = true
		creditCoins(player, t.prem.coins)
		local msg = "+" .. t.prem.coins .. " coins!"
		if t.prem.pet and t.prem.pet > 0 then
			local eq = _G.playerEquippedPet and _G.playerEquippedPet[player]
			local added = (eq and _G.petAddLevels and _G.petAddLevels(player, eq, t.prem.pet)) or 0
			if added > 0 then msg = msg .. "  +" .. added .. " pet levels!" end
		end
		pcall(function() remote:FireClient(player, "result", tierIndex, lane, true, msg) end)
	else
		return
	end
	pushState(player)
end

--------------------------------------------------------------------------------
-- premium purchase
--------------------------------------------------------------------------------
local function checkPremium(player)
	if PREMIUM_GAMEPASS_ID == 0 then premium[player] = false; return end
	local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, PREMIUM_GAMEPASS_ID) end)
	premium[player] = ok and owns or false
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, purchased)
	if gamepassId == PREMIUM_GAMEPASS_ID and purchased then
		premium[player] = true
		pushState(player)
		print("[SeasonPass] " .. player.Name .. " bought Premium")
	end
end)

remote.OnServerEvent:Connect(function(player, action, a, b)
	if action == "claim" then
		claim(player, tonumber(a), b)
	elseif action == "buy" then
		if PREMIUM_GAMEPASS_ID ~= 0 and not premium[player] then
			pcall(function() MarketplaceService:PromptGamePassPurchase(player, PREMIUM_GAMEPASS_ID) end)
		end
	end
end)

--------------------------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------------
local function load(player)
	local saved
	local ok = pcall(function() saved = store:GetAsync(keyFor(player.UserId)) end)
	if ok and type(saved) == "table" then
		data[player] = { xp = tonumber(saved.xp) or 0, free = saved.free or {}, prem = saved.prem or {} }
	else
		data[player] = { xp = 0, free = {}, prem = {} }
	end
end
local function persist(player)
	if not data[player] then return end
	pcall(function() store:SetAsync(keyFor(player.UserId), data[player]) end)
end

local function onAdded(player)
	load(player)
	task.spawn(function()
		checkPremium(player)
		task.wait(3) -- let the client build
		pushState(player)
		while player.Parent do task.wait(60); persist(player) end -- autosave
	end)
end

Players.PlayerAdded:Connect(onAdded)
for _, p in ipairs(Players:GetPlayers()) do onAdded(p) end
Players.PlayerRemoving:Connect(function(p) persist(p); data[p] = nil; premium[p] = nil end)
game:BindToClose(function() for _, p in ipairs(Players:GetPlayers()) do persist(p) end end)

print(("[SeasonPass] ready -- season %d, %d tiers, %d XP/tier, premium gamepass=%d")
	:format(SEASON_ID, #TIERS, TIER_XP, PREMIUM_GAMEPASS_ID))
