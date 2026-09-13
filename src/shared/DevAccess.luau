--======================================================================
-- DevAccess.luau  (ModuleScript -> ReplicatedStorage.DinosaurRealm.DevAccess)
--======================================================================
-- THE ONE LIST OF WHO MAY USE DEV COMMANDS. Shared by every gated command so the lists
-- can never drift apart -- add an account here and it works everywhere at once.
--
-- Currently gating:
--     goisland<N>    GoIsland.server.luau      (server-side gate -- a real one)
--     complete<N>    DoneCommand.luau          (client-side gate -- see the warning below)
--
-- ===== SERVER-SIDE VS CLIENT-SIDE IS NOT THE SAME STRENGTH OF LOCK =====
-- Called from a Script, this is a genuine gate: the client cannot reach it.
-- Called from a LocalScript it is only a CONVENIENCE -- an exploiter runs their own code
-- and can skip any check in it. That is acceptable for the quest-skip command purely
-- because the quests in this game already run client-side, so it opens nothing that was
-- not already open. Do NOT put anything that grants currency, pets or progression behind
-- this from the client and consider it secured; that belongs on the server, the way
-- BurritoDig's /done already fires PetDigEvent so the server can gate the actual claim.
--======================================================================

local DevAccess = {}

-- Usernames are unique on Roblox, so a name match is a real identity check -- but a name
-- can be CHANGED and a UserId never can. Both are honoured; filling in the ids makes the
-- gate survive a username change. To find one:
--     https://www.roblox.com/users/profile?username=lando5485   -> the id is in the URL
DevAccess.NAMES = {
	["lando5485"]     = true,
	["broskie310111"] = true,   -- keys are LOWERCASE; the lookup lowercases the name
}

DevAccess.USER_IDS = {
	-- [123456789] = true,   -- lando5485
	-- [987654321] = true,   -- Broskie310111
}

function DevAccess.isAllowed(player: Player?): boolean
	if not player then return false end
	if DevAccess.USER_IDS[player.UserId] then return true end
	return DevAccess.NAMES[string.lower(player.Name)] == true
end

return DevAccess
