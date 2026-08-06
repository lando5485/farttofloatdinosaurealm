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

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local TOP_SLOT = IslandOrder.COUNT       -- summit slot (13)
local LANDING_OFFSET = 8                  -- studs above island1's top (matches IslandTeleport / Wormhole)
local BONUS_PER_REBIRTH = 0.25            -- +25% RebirthMult per rebirth
local COIN_BONUS_PER_REBIRTH = 250        -- lump-sum coins granted, scaled by rebirth count

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

local function onJoin(player)
	if player:GetAttribute("Rebirths") == nil then player:SetAttribute("Rebirths", 0) end
	refreshMult(player)
end
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

	local n = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0) + 1
	player:SetAttribute("Rebirths", n)
	refreshMult(player)

	-- reset island progress
	player:SetAttribute("HighestIsland", 1)
	player:SetAttribute("HighestSlot", 1)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local islv = ls:FindFirstChild("Island"); if islv then islv.Value = 1 end
		local coins = ls:FindFirstChild("Coins")
		if coins then coins.Value = coins.Value + COIN_BONUS_PER_REBIRTH * n end -- tangible reward each rebirth
	end
	landIsland1(player)

	print(("[Rebirth] %s rebirthed -> Rebirths=%d, RebirthMult=%.2f (+%d coins)")
		:format(player.Name, n, 1 + BONUS_PER_REBIRTH * n, COIN_BONUS_PER_REBIRTH * n))
	return { ok = true, rebirths = n, mult = 1 + BONUS_PER_REBIRTH * n }
end

print("[Rebirth] service online — reach the summit to rebirth (+RebirthMult, resets island progress, coin bonus).")
