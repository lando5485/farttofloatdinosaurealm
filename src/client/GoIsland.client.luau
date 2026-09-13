--======================================================================
-- GoIsland.client.luau  (LocalScript)
--======================================================================
-- Client half of the owner-only "goisland1" / "goisland2" warp.
--
-- Player.Chatted on the SERVER misses messages under some TextChatService setups, so
-- this listens to TextChatService.SendingMessage -- which fires for every message the
-- local player sends -- and asks the server to do the move. GoIsland.server listens on
-- Chatted as well and de-dupes, so whichever one fires first wins and the other is
-- swallowed. (Same belt-and-braces split DoneCommand.luau uses.)
--
-- THIS FILE GRANTS NOTHING. The whitelist lives on the server; all this can do is fire
-- a request that the server is free to ignore. It runs for every player on purpose --
-- gating it here would only hide the command, not protect it.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService   = game:GetService("TextChatService")

local remote = ReplicatedStorage:WaitForChild("GoIslandRequest")

-- "goisland7" -> 7. Also accepts "go island 7", "/goisland 7". Anchored at both ends so
-- ordinary chat that merely mentions an island is not treated as a command.
local function parseSlot(text)
	if type(text) ~= "string" then return nil end
	local n = string.match(string.lower(text), "^%s*/?go%s*island%s*(%d+)%s*$")
	return n and tonumber(n) or nil
end

TextChatService.SendingMessage:Connect(function(message)
	local slot = parseSlot(message.Text)
	if slot then
		remote:FireServer(slot)
	end
end)
