--======================================================================
-- DoneCommand.luau  (ModuleScript -> ReplicatedStorage.DinosaurRealm.DoneCommand)
--======================================================================
-- The quest SKIP commands: jump a quest straight to its reward egg. Two of them, and the
-- difference between them is the whole design of this file:
--
--   "/done"          -- open to anyone, but ONLY completes the island you are STANDING ON.
--   "complete<slot>" -- names its island, so it works from anywhere in the tower.
--                       WHITELISTED (DevAccess), because a command that can be fired from
--                       the other end of the map with no positional cost is a command that
--                       finishes the whole game in eight messages.
--
-- ===== WHY /done NEEDS THE POSITION GATE =====
-- Every quest script registers its own listener and those listeners stay alive for the
-- whole session. Without an island check, typing /done on the volcano would ALSO complete
-- the swamp, the dig site and the fishing quest at once, spawning eggs across the tower.
-- The position gate keeps it to the island under your feet. complete<slot> does not need
-- the gate because the slot number already names exactly one island.
--
-- ===== THE NUMBER IS A CLIMB SLOT, NOT A MODEL NAME =====
-- "complete13" is the THIRTEENTH ISLAND OF THE CLIMB -- Volcanic Vista, the volcano
-- finale, whose model is named island11. Model numbers are build order and are
-- deliberately scrambled (see the long note in IslandOrder.luau), so they are the wrong
-- thing to type. Slot also matches goisland<N>, so both dev commands count the same way.
--
-- AND SLOT IS THE ONLY OPTION, NOT A PREFERENCE. Accepting model numbers too would be
-- ambiguous: "complete3" is slot 3 (Misty Mire, mosquitoes) AND model island3 (Fossil
-- Frontier, the dig) -- both real quests, and both would fire.
--
-- Listens on BOTH Player.Chatted and TextChatService.SendingMessage -- different parts of
-- this game use different chat APIs and only one fires depending on the chat version, so
-- we take either.
--
-- USAGE (from a quest's BOOT, once its island has streamed in):
--     local DoneCommand = require(ReplicatedStorage.DinosaurRealm.DoneCommand)
--     DoneCommand.bind(isl, "Geyser", function()
--         onAllPlugged()   -- whatever completes THIS quest and spawns its egg
--     end)
--======================================================================

local Players           = game:GetService("Players")
local TextChatService   = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DinoRealm   = ReplicatedStorage:WaitForChild("DinosaurRealm")
local IslandOrder = require(DinoRealm:WaitForChild("IslandOrder"))
local DevAccess   = require(DinoRealm:WaitForChild("DevAccess"))

local player = Players.LocalPlayer

local DoneCommand = {}

local MARGIN = 80 -- studs of slack around the island's footprint (you may be mid-air over it)

--- Bind the skip commands to a quest's completion function.
-- @param island Instance  : the island model this quest lives on
-- @param tag    string    : log prefix, e.g. "Geyser"
-- @param complete function: runs the quest's completion (spawn the reward egg)
function DoneCommand.bind(island: Instance, tag: string, complete: () -> ())
	local fired = false

	-- Which slot is this quest's island? Read from the MODEL NAME rather than passed in, so
	-- no quest script has to know its own slot and none of them can get it wrong.
	local islandNum = tonumber(string.match(island.Name or "", "^island(%d+)$"))
	local slot = islandNum and IslandOrder.ISLAND_TO_SLOT[islandNum] or nil
	local islandName = islandNum and IslandOrder.NAMES[islandNum] or (island.Name or "?")

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

	local function run(how: string)
		if fired then return end
		fired = true
		print(("[%s] %s -> skipping to the reward egg (slot %s, %s)")
			:format(tag, how, tostring(slot), islandName))
		local ok, err = pcall(complete)
		if not ok then
			warn(("[%s] %s failed: %s"):format(tag, how, tostring(err)))
			fired = false -- let them try again
		end
	end

	local function onMessage(text: string?)
		if not text or fired then return end
		local cmd = string.gsub(string.lower(text), "%s", "")

		-- "/done" -- anyone, but only for the island under their feet.
		if cmd == "/done" then
			if onThisIsland() then run("/done") end
			return
		end

		-- "complete<slot>" (a leading slash is optional) -- whitelisted, works from anywhere.
		local n = tonumber(string.match(cmd, "^/?complete(%d+)$"))
		if n and slot and n == slot then
			if not DevAccess.isAllowed(player) then return end
			run("complete" .. n)
		end
	end

	player.Chatted:Connect(onMessage)
	pcall(function()
		TextChatService.SendingMessage:Connect(function(m) onMessage(m.Text) end)
	end)
end

return DoneCommand
