--[[
	Rebirth.server.luau  (ServerScriptService.DinosaurRealmServer.Rebirth)

	Minimal, self-contained Dino Realm REBIRTH. Server-authoritative.

	  * ELIGIBILITY: you must have climbed to the SUMMIT (HighestSlot == the top slot = Volcanic Vista).
	  * ON REBIRTH: +1 to the "Rebirths" attribute, raise the permanent "RebirthMult" attribute
	    (1 + 0.25 per rebirth), grant a lump-sum coin bonus, and RESET island progress (HighestIsland /
	    HighestSlot / leaderstats.Island -> 1) + place the player back on island1.

	Attributes (Rebirths, RebirthMult) auto-replicate, so the client menu + any economy code can read them.
	Remote: ReplicatedStorage/RebirthRemotes/DoRebirth (RemoteFunction) -> { ok, rebirths?, mult?, reason? }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- ONE REBIRTH RECORD FOR THE WHOLE UNIVERSE. The count lived only in the Rebirths attribute, which does not
-- persist: a Dino rebirth vanished on leave (the multiplier with it) while its coin bonus stayed -- free coins
-- for anyone who rebirthed and rejoined. It now loads from and saves to the SAME store the Food and Space
-- realms use (Rebirth_v1, key "Player_<userId>", { rebirths = n }), so a rebirth counts everywhere and the
-- multiplier follows the player between realms. `mult`/`updatedAt` are extra fields the other realms ignore.
local REBIRTH_STORE = "Rebirth_v1"
local rebirthStore = DataStoreService:GetDataStore(REBIRTH_STORE)
local function rebirthKey(player) return "Player_" .. player.UserId end

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local StomachTiers = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("StomachTiers"))
local TOP_SLOT = IslandOrder.COUNT       -- summit slot (13)
-- The gut a fresh climb starts on. Read from the table rather than hardcoded, because
-- StomachMax IS the record of which gut you own -- there is no separate tier field.
local START_MAX = StomachTiers.LIST[1].maxPower   -- Hatchling Belly (120)
local LANDING_OFFSET = 8                  -- studs above island1's top (matches IslandTeleport / Wormhole)
local BONUS_PER_REBIRTH = 0.25            -- +25% RebirthMult per rebirth
local COIN_BONUS_PER_REBIRTH = 125        -- lump-sum coins granted, scaled by rebirth count

-- ===== remote =====
local folder = ReplicatedStorage:FindFirstChild("RebirthRemotes")
if not folder then
	folder = Instance.new("Folder"); folder.Name = "RebirthRemotes"; folder.Parent = ReplicatedStorage
end
local DoRebirth = folder:FindFirstChild("DoRebirth")
if not DoRebirth then
	DoRebirth = Instance.new("RemoteFunction"); DoRebirth.Name = "DoRebirth"; DoRebirth.Parent = folder
end

local function refreshMult(player)
	local n = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0)
	player:SetAttribute("RebirthMult", 1 + BONUS_PER_REBIRTH * n)
end

local loaded = {} -- [player] = true once the store has answered (a save before that could wipe a real count)

local function applyCount(player, n)
	player:SetAttribute("Rebirths", n)
	refreshMult(player)
	-- the Food / Space realms show it on the leaderboard; mirror that here so all three read the same
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local v = ls:FindFirstChild("Rebirths")
		if not v then v = Instance.new("IntValue"); v.Name = "Rebirths"; v.Parent = ls end
		v.Value = n
	end
end

local function loadRebirths(player)
	local n = 0
	local ok, rec = pcall(function() return rebirthStore:GetAsync(rebirthKey(player)) end)
	if ok then
		n = math.floor(tonumber(type(rec) == "table" and rec.rebirths) or 0)
		loaded[player] = true
	else
		warn("[Rebirth] load failed for " .. player.Name .. " (rebirths shown as 0, NOT saved this session): " .. tostring(rec))
		if RunService:IsStudio() then loaded[player] = true end -- Studio without API access: let the flow be tested
	end
	applyCount(player, n)
end

local function saveRebirths(player, n)
	if not loaded[player] then
		warn("[Rebirth] refusing to save for " .. player.Name .. " -- the store never loaded, a write could erase a real count")
		return false
	end
	local ok, err = pcall(function()
		rebirthStore:UpdateAsync(rebirthKey(player), function(old)
			local rec = (type(old) == "table") and old or {}
			rec.rebirths = math.max(n, math.floor(tonumber(rec.rebirths) or 0)) -- never move a count DOWN
			rec.mult = 1 + BONUS_PER_REBIRTH * rec.rebirths
			rec.updatedAt = os.time()
			return rec
		end)
	end)
	if not ok then warn("[Rebirth] save failed for " .. player.Name .. ": " .. tostring(err)) end
	return ok
end

local function onJoin(player)
	if player:GetAttribute("Rebirths") == nil then player:SetAttribute("Rebirths", 0) end
	refreshMult(player)
	task.spawn(function()
		-- leaderstats may still be building; the count is applied to it as soon as both exist
		player:WaitForChild("leaderstats", 10)
		loadRebirths(player)
	end)
end
Players.PlayerRemoving:Connect(function(p) loaded[p] = nil end)
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

-- place the character back on top of island1 (same live bounding-box landing the Wormhole / IslandTeleport use)
local function landIsland1(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local isl = Workspace:FindFirstChild("island1")
	if not (hrp and isl) then return end
	local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
	if ok and cf and size then
		char:PivotTo(CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + LANDING_OFFSET, 0)))
		pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
	end
end

DoRebirth.OnServerInvoke = function(player)
	local highestSlot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	if highestSlot < TOP_SLOT then
		return { ok = false, reason = "not_summit", need = TOP_SLOT, have = highestSlot }
	end

	if not loaded[player] then
		return { ok = false, reason = "not_loaded" } -- the store has not answered; a rebirth now could not be kept
	end
	local n = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0) + 1
	-- PERSIST FIRST. If the write fails the rebirth does not happen: no reset, no bonus, nothing to exploit.
	if not saveRebirths(player, n) then
		return { ok = false, reason = "save_failed" }
	end
	applyCount(player, n)

	-- reset island progress
	player:SetAttribute("HighestIsland", 1)
	player:SetAttribute("HighestSlot", 1)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local islv = ls:FindFirstChild("Island"); if islv then islv.Value = 1 end
		local coins = ls:FindFirstChild("Coins")
		if coins then coins.Value = coins.Value + COIN_BONUS_PER_REBIRTH * n end -- tangible reward each rebirth

		-- RESET THE GUT TOO. THIS WAS MISSING AND IT MADE THE WHOLE NEXT CLIMB FREE.
		--
		-- Island progress reset but StomachMax did not, so a rebirthed player stood on
		-- Nesting Nook holding the Colossus Gut. One full tank of that climbs 10,417 studs
		-- and Nesting Nook -> Glacier Gulch is 9,346, so the first launch after every
		-- rebirth skipped FIVE islands in a single flight. Every tank does some version of
		-- this: Titan reaches slot 5, Rex slot 4, Dilo slot 3.
		--
		-- The unlockSlot gate cannot catch it -- that gate only stops you BUYING a gut too
		-- early, and this player already owns it. StomachMax is the only record of which
		-- gut you have, so resetting the climb has to reset it or the climb is not reset.
		--
		-- Coins are deliberately NOT reset (they are the rebirth reward, and unlockSlot
		-- still forces you to re-earn each tier's island before you can re-buy it).
		local sm = ls:FindFirstChild("StomachMax")
		local cp = ls:FindFirstChild("CurrentPower")
		if sm then sm.Value = START_MAX end
		if cp then cp.Value = 0 end
		-- Push it to the HUD the same way a gut purchase does, or the meter keeps showing
		-- the old tank until something else happens to refresh it.
		local su = ReplicatedStorage:FindFirstChild("StomachUpdateEvent")
		if su and sm then pcall(function() su:FireClient(player, sm.Value, StomachTiers.LIST[1].name) end) end
		local re = ReplicatedStorage:FindFirstChild("RegenEvent")
		if re and sm then pcall(function() re:FireClient(player, 0, 0, sm.Value) end) end
	end
	landIsland1(player)

	print(("[Rebirth] %s rebirthed -> Rebirths=%d, RebirthMult=%.2f (+%d coins)")
		:format(player.Name, n, 1 + BONUS_PER_REBIRTH * n, COIN_BONUS_PER_REBIRTH * n))
	return { ok = true, rebirths = n, mult = 1 + BONUS_PER_REBIRTH * n }
end

print("[Rebirth] service online — reach the summit to rebirth (+RebirthMult, resets island progress, coin bonus). Persisted to the universe store " .. REBIRTH_STORE .. " (shared with Food / Space).")
