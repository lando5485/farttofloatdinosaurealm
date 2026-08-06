--======================================================================
-- MonsoonCommand.client.luau  (LocalScript)
--======================================================================
-- Client half of the "/monsoon" command (alias: "/rain").
-- TextChatService.SendingMessage fires for every chat message the local player
-- sends, so we parse the command here and ask the server (via RemoteEvent) to
-- start the Monsoon Rain event.
-- (Mirrors IceAgeCommand.client.luau / IslandTeleport.client.luau.)
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local trigger = ReplicatedStorage:WaitForChild("MonsoonTrigger")

TextChatService.SendingMessage:Connect(function(message)
	local text = message.Text
	if text and (string.match(text:lower(), "^%s*/monsoon%s*$")
		or string.match(text:lower(), "^%s*/rain%s*$")) then
		print("[Monsoon] requesting Monsoon Rain event")
		trigger:FireServer()
	end
end)

print("[Monsoon] client ready -- type '/monsoon' or '/rain' in chat to start the Monsoon Rain event")
