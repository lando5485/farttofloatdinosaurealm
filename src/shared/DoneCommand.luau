--======================================================================
-- DoneCommand.luau  (ModuleScript -> ReplicatedStorage.DinosaurRealm.DoneCommand)
--======================================================================
-- The "/done" dev/test command: SKIP A QUEST STRAIGHT TO ITS REWARD EGG.
--
-- island1 (QuestGate) already had its own inline /done. This is the same idea, made
-- reusable so every island quest gets it with one call.
--
-- IMPORTANT -- it only fires for the island you are STANDING ON.
-- Every quest script registers its own /done listener, and those listeners stay alive
-- for the whole session. Without an island check, typing /done on the volcano would
-- ALSO complete the swamp, the dig site and the fishing quest at once, spawning eggs
-- across the whole tower. The position gate keeps it to the island under your feet.
--
-- Listens on BOTH Player.Chatted and TextChatService.SendingMessage -- different parts
-- of this game use different chat APIs, and only one of them fires depending on the
-- chat version, so we take either.
--
-- USAGE (from a quest's BOOT, once its island has streamed in):
--     local DoneCommand = require(ReplicatedStorage.DinosaurRealm.DoneCommand)
--     DoneCommand.bind(isl, "Geyser", function()
--         onAllPlugged()   -- whatever completes THIS quest and spawns its egg
--     end)
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

local DoneCommand = {}

local MARGIN = 80 -- studs of slack around the island's footprint (you may be mid-air over it)

--- Bind /done to a quest's completion function.
-- @param island Instance  : the island model this quest lives on
-- @param tag    string    : log prefix, e.g. "Geyser"
-- @param complete function: runs the quest's completion (spawn the reward egg)
function DoneCommand.bind(island: Instance, tag: string, complete: () -> ())
	local fired = false

	local function onThisIsland(): boolean
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (hrp and island and island.Parent) then return false end
		local ok, cf, size = pcall(function() return island:GetBoundingBox() end)
		if not (ok and cf and size and size.Magnitude > 1) then return false end
		local d = hrp.Position - cf.Position
		return math.abs(d.X) <= size.X / 2 + MARGIN
			and math.abs(d.Z) <= size.Z / 2 + MARGIN
			and math.abs(d.Y) <= size.Y / 2 + 200 -- islands stack vertically; be generous in Y
	end

	local function onMessage(text: string?)
		if not text or fired then return end
		if string.gsub(string.lower(text), "%s", "") ~= "/done" then return end
		if not onThisIsland() then return end -- a different island's /done -- not ours
		fired = true
		print(("[%s] /done -> skipping to the reward egg"):format(tag))
		local ok, err = pcall(complete)
		if not ok then
			warn(("[%s] /done failed: %s"):format(tag, tostring(err)))
			fired = false -- let them try again
		end
	end

	player.Chatted:Connect(onMessage)
	pcall(function()
		TextChatService.SendingMessage:Connect(function(m) onMessage(m.Text) end)
	end)
end

return DoneCommand
