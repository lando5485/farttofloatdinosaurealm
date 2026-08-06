--======================================================================
-- IceAgeCommand.client.luau  (LocalScript)
--======================================================================
-- Client half of the "/iceage" command. TextChatService.SendingMessage fires
-- for every chat message the local player sends, so we parse "/iceage" here and
-- ask the server (via RemoteEvent) to start the Ice Age event.
-- (Mirrors IslandTeleport.client.luau's chat-command pattern.)
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local trigger = ReplicatedStorage:WaitForChild("IceAgeTrigger")

TextChatService.SendingMessage:Connect(function(message)
	local text = message.Text
	if text and string.match(text:lower(), "^%s*/iceage%s*$") then
		print("[IceAge] requesting Ice Age event")
		trigger:FireServer()
	end
end)

print("[IceAge] client ready -- type '/iceage' in chat to start the Ice Age event")
