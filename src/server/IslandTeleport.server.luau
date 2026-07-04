--======================================================================
-- IslandTeleport.server.luau  (Server Script)
--======================================================================
-- Server half of the "/island N" teleport command.
-- The CLIENT (IslandTeleport.client.luau) detects the chat message and
-- fires the RemoteEvent below; here we validate it and teleport the
-- player onto island N, landing just above the island's top surface.
-- Island position is read LIVE from the Workspace, so it stays correct
-- no matter how IslandLayout spaces the islands.
--======================================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_ISLAND = 14        -- islands island1 .. island14
local LANDING_OFFSET = 8     -- studs above the island top to drop the player

-- RemoteEvent the client fires to request a teleport.
local remote = ReplicatedStorage:FindFirstChild("IslandTeleportRequest")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "IslandTeleportRequest"
	remote.Parent = ReplicatedStorage
end

-- Returns a world position to teleport onto, or nil if the island isn't found.
local function getLandingPosition(index)
	local isl = Workspace:FindFirstChild("island" .. index)
	if not isl then
		return nil
	end

	if isl:IsA("Model") then
		local cf, size = isl:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y / 2 + LANDING_OFFSET, 0)
	elseif isl:IsA("BasePart") then
		return isl.Position + Vector3.new(0, isl.Size.Y / 2 + LANDING_OFFSET, 0)
	end

	return nil
end

local function teleport(player, index)
	local char = player.Character
	if not char or not char.PrimaryPart then
		warn(("[IslandTeleport] %s has no character to move"):format(player.Name))
		return
	end

	local pos = getLandingPosition(index)
	if not pos then
		warn(("[IslandTeleport] %s asked for island%d but it was not found")
			:format(player.Name, index))
		return
	end

	char:PivotTo(CFrame.new(pos))
	print(("[IslandTeleport] %s -> island%d (%d, %d, %d)")
		:format(player.Name, index, pos.X, pos.Y, pos.Z))
end

remote.OnServerEvent:Connect(function(player, index)
	index = tonumber(index)
	if not index then
		return
	end
	index = math.floor(index)
	if index < 1 or index > MAX_ISLAND then
		warn(("[IslandTeleport] %s asked for island%d (out of range 1-%d)")
			:format(player.Name, index, MAX_ISLAND))
		return
	end
	teleport(player, index)
end)

print("[IslandTeleport] server ready -- type '/island N' in chat (N = 1.." .. MAX_ISLAND .. ")")
