--======================================================================
-- IslandTeleport.client.luau  (LocalScript)
--======================================================================
-- Client half of the "/island N" teleport command.
-- TextChatService.SendingMessage fires for EVERY chat message the local
-- player sends (no command registration needed), so we parse "/island N"
-- here and ask the server (via RemoteEvent) to do the teleport.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remote = ReplicatedStorage:WaitForChild("IslandTeleportRequest")

-- Pulls the island number out of "/island 4" (also accepts "/island4").
local function parseIsland(text)
	if not text then
		return nil
	end
	local num = string.match(text:lower(), "/island%s*(%d+)")
	return num and tonumber(num) or nil
end

TextChatService.SendingMessage:Connect(function(message)
	local index = parseIsland(message.Text)
	if index then
		print("[IslandTeleport] requesting island " .. index)
		remote:FireServer(index)
	end
end)

print("[IslandTeleport] client ready -- type '/island N' in chat to teleport")
