--======================================================================
-- GoIsland.server.luau  (Server Script)
--======================================================================
-- "goisland1" / "goisland2" / ... -- OWNER-ONLY warp up and down the tower.
--
-- WHITELISTED. Unlike the older "/island N" command (IslandTeleport.*), which any
-- player in the server can fire, this one is gated to the accounts in ALLOWED below
-- and the gate is enforced HERE, on the server. The client half only shortcuts the
-- chat parse -- it cannot grant itself the teleport, so a hacked client gets nothing.
--
-- THE NUMBER IS A CLIMB SLOT, NOT A MODEL NAME. "goisland2" takes you to the SECOND
-- island of the climb (Frostbite Flats), not to the model literally named "island2"
-- (Fern Frontier, which is the TENTH island up). The model numbers are build order and
-- are deliberately scrambled -- see the long note in IslandOrder.luau. Slot is what a
-- player means by "island 2", so slot is what this takes.
--
-- TWO LISTENERS ON PURPOSE. Player.Chatted (here) and TextChatService.SendingMessage
-- (GoIsland.client) each miss messages the other catches depending on how the chat is
-- configured -- the same reason DoneCommand.luau listens on both. A COOLDOWN below
-- swallows the duplicate when both fire for one message.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

-- THE WHITELIST lives in DevAccess, so this and the complete<N> quest-skip share ONE list
-- and cannot drift apart -- add accounts there, not here. Enforced on the SERVER, which
-- for this command makes it a real gate rather than a convenience; see DevAccess's header
-- for why that distinction matters.
local DevAccess = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("DevAccess"))
local isAllowed = DevAccess.isAllowed

local LANDING_OFFSET = 8      -- studs above the island's top surface to drop you
local COOLDOWN       = 0.75   -- seconds; also what de-dupes the Chatted/remote double-fire
local MAX_SLOT       = IslandOrder.COUNT   -- 13

local lastWarp = {}   -- [Player] = os.clock() of the last accepted warp

-- Remote the client half fires. Created here so the command works whether or not the
-- event was added to default.project.json (same pattern as WindstormSync).
local remote = ReplicatedStorage:FindFirstChild("GoIslandRequest")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "GoIslandRequest"
	remote.Parent = ReplicatedStorage
end

-- "goisland7" -> 7. Also accepts "go island 7", "/goisland 7", "goisland  7".
-- Returns nil for anything else, INCLUDING plain chat that happens to contain a number.
local function parseSlot(text)
	if type(text) ~= "string" then return nil end
	local n = string.match(string.lower(text), "^%s*/?go%s*island%s*(%d+)%s*$")
	return n and tonumber(n) or nil
end

-- Where slot N actually is. Prefers the LIVE model in Workspace (so it stays right if
-- IslandLayout is ever re-tuned) and falls back to the shared ladder if the model is
-- missing or has no parts yet.
local function landingPosition(slot)
	local islandNum = IslandOrder.SLOT_TO_ISLAND[slot]
	if not islandNum then return nil end

	local isl = Workspace:FindFirstChild("island" .. islandNum)
	if isl then
		if isl:IsA("Model") then
			local cf, size = isl:GetBoundingBox()
			-- A model whose parts have not loaded reports a zero box at the origin.
			-- Trusting that would drop the player into the void, so fall through.
			if size.Magnitude > 1 and cf.Position.Magnitude > 1 then
				return cf.Position + Vector3.new(0, size.Y / 2 + LANDING_OFFSET, 0), islandNum
			end
		elseif isl:IsA("BasePart") then
			return isl.Position + Vector3.new(0, isl.Size.Y / 2 + LANDING_OFFSET, 0), islandNum
		end
	end

	local pos = IslandOrder.SLOT_POS[slot]
	if pos then
		return pos + Vector3.new(0, 40 + LANDING_OFFSET, 0), islandNum
	end
	return nil
end

local function warp(plr, slot)
	if not isAllowed(plr) then
		warn(("[goisland] %s (%d) is not whitelisted -- ignored"):format(plr.Name, plr.UserId))
		return
	end

	slot = math.floor(tonumber(slot) or 0)
	if slot < 1 or slot > MAX_SLOT then
		warn(("[goisland] %s asked for island %d (valid range 1-%d)"):format(plr.Name, slot, MAX_SLOT))
		return
	end

	local now = os.clock()
	if lastWarp[plr] and now - lastWarp[plr] < COOLDOWN then return end   -- the duplicate fire

	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not root then
		warn(("[goisland] %s has no character to move"):format(plr.Name))
		return
	end

	local pos, islandNum = landingPosition(slot)
	if not pos then
		warn(("[goisland] slot %d has no island to land on"):format(slot))
		return
	end

	lastWarp[plr] = now
	char:PivotTo(CFrame.new(pos))

	-- KILL THE INHERITED MOMENTUM. Warping mid-flight otherwise keeps whatever velocity
	-- the fart loop had you at, so you arrive on the island already sliding off it.
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	print(("[goisland] %s -> slot %d = island%d (%s) at (%d, %d, %d)")
		:format(plr.Name, slot, islandNum, IslandOrder.NAMES[islandNum] or "?", pos.X, pos.Y, pos.Z))
end

remote.OnServerEvent:Connect(function(plr, slot)
	warp(plr, slot)
end)

local function hook(plr)
	if not isAllowed(plr) then return end   -- no listener at all for everyone else
	plr.Chatted:Connect(function(msg)
		local slot = parseSlot(msg)
		if slot then warp(plr, slot) end
	end)
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerRemoving:Connect(function(plr) lastWarp[plr] = nil end)

print(("[goisland] server ready -- whitelisted players type 'goisland1' .. 'goisland%d' in chat")
	:format(MAX_SLOT))
