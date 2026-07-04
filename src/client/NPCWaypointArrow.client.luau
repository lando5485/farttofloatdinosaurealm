--[[
	NPCWaypointArrow.client.luau  (StarterPlayerScripts -> DinosaurRealmClient)

	Always-on green waypoint arrow hovering above each NPC's head, so players can
	see where the quest NPC is. A BillboardGui (faces the camera, constant
	on-screen size at any distance, renders through walls via AlwaysOnTop) holds a
	downward "▼" that bounces up and down on a sine wave.

	Streaming-resilient: the arrow is built when the NPC's head part streams in and
	removed (Heartbeat disconnected) when it streams out, so it survives the player
	walking / teleporting around the map.

	Add another NPC = add one entry to NPCS below.
]]

print("[NPCWaypointArrow] script loaded")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- which island the player is standing on (XZ footprint -> nearest), refreshed every 0.4s and shared by
-- all arrows so each NPC's marker only shows while the player is ON that NPC's island.
local curIsland = nil
do
	local function detect()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local pos = hrp.Position
		local best, bestD = nil, math.huge
		for i = 1, 14 do
			local isl = workspace:FindFirstChild("island" .. i)
			if isl then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and cf and size then
					local dx, dy, dz = pos.X - cf.Position.X, pos.Y - cf.Position.Y, pos.Z - cf.Position.Z
					if math.abs(dx) <= size.X/2 and math.abs(dz) <= size.Z/2 and math.abs(dy) <= size.Y/2 + 80 then return i end
					local d = dx*dx + dy*dy + dz*dz -- 3D nearest (islands stack vertically)
					if d < bestD then bestD = d; best = i end
				end
			end
		end
		return best
	end
	task.spawn(function() while true do curIsland = detect(); task.wait(0.4) end end)
end

-- One entry per NPC. `parent` is the Workspace descendant the NPC lives under,
-- `npcName` is the NPC Model's name.
local NPCS = {
	{ parent = "island1", npcName = "miner", island = 1 },
	{ parent = "island1", npcName = "dino1", island = 1 },
	{ npcName = "DigMiner", island = 3 }, -- island3 Digger (parented directly under Workspace; no parent field = workspace)
	-- other-island Researchers (parented under Workspace by NestingNook_NPCs.setupIslandQuestNPC)
	{ npcName = "FrillRancher",  island = 2 },
	{ npcName = "CoastalFisher", island = 4 },
	{ npcName = "MireWatcher",   island = 5 },
	{ npcName = "RidgeWarden",   island = 6 },
	{ npcName = "RaptorScout",   island = 7 },
	{ npcName = "AshWarden",     island = 8 },
}

-- Arrow look / motion (tunable) ------------------------------------------------
local ARROW_COLOR = Color3.fromRGB(50, 220, 80)
local ARROW_SIZE = UDim2.new(0, 60, 0, 60) -- screen pixels (constant size at any distance)
local ARROW_MARGIN = 3   -- studs above the NPC's bounding-box TOP (so tall NPCs work)
local BOUNCE_BASE = 6    -- fallback studs above the anchor if no bounding box
local BOUNCE_AMP = 1     -- studs of travel each way
local BOUNCE_SPEED = 2.5 -- rad/sec -> ~2.5s cycle
-------------------------------------------------------------------------------

-- A stable part to anchor the arrow to: the model's PrimaryPart (anchored body),
-- else a head-like part, else any BasePart. The vertical offset is computed from
-- the model's bounding box, so which part this is only affects the X/Z anchor.
local function findAnchorPart(npc: Instance): BasePart?
	local hrp = npc:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then return hrp end
	if npc:IsA("Model") and npc.PrimaryPart then
		return npc.PrimaryPart
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "head", 1, true) then
			return d
		end
	end
	return npc:FindFirstChildWhichIsA("BasePart", true)
end

local function setupArrow(spec)
	local container = spec.parent and workspace:WaitForChild(spec.parent, 90) or workspace
	local npc = container and container:WaitForChild(spec.npcName, 90)
	if not npc then
		warn(("[NPCWaypointArrow] %s not found - no arrow."):format(spec.npcName))
		return
	end

	local gui: BillboardGui? = nil
	local conn: RBXScriptConnection? = nil

	-- Track whether this NPC currently has a speech bubble up, so we can hide the
	-- waypoint arrow while it's talking (server parents a "SpeechBubble"
	-- BillboardGui to the NPC, which replicates here).
	local bubbleShowing = npc:FindFirstChild("SpeechBubble", true) ~= nil
	npc.DescendantAdded:Connect(function(d)
		if d:IsA("BillboardGui") and d.Name == "SpeechBubble" then
			bubbleShowing = true
		end
	end)
	npc.DescendantRemoving:Connect(function(d)
		if d:IsA("BillboardGui") and d.Name == "SpeechBubble" then
			bubbleShowing = false
		end
	end)

	local function buildArrow(anchor: BasePart)
		-- Offset (world space, from the anchor part) that places the arrow over the
		-- HORIZONTAL CENTER of the NPC's bounding box and above its TOP, so it's
		-- centered on the body and clears the head even for tall NPCs like the dino.
		local baseOffset = Vector3.new(0, BOUNCE_BASE, 0)
		if npc:IsA("Model") then
			local cf, size = npc:GetBoundingBox()
			local topY = cf.Position.Y + size.Y / 2
			-- center HORIZONTALLY on the body root (anchor), NOT the bounding-box center,
			-- which skews toward a long tail/neck. Only the height comes from the box top.
			baseOffset = Vector3.new(0, (topY - anchor.Position.Y) + ARROW_MARGIN, 0)
		end

		gui = Instance.new("BillboardGui")
		gui.Name = "WaypointArrow_" .. spec.npcName
		gui.Adornee = anchor
		gui.Size = ARROW_SIZE
		gui.StudsOffsetWorldSpace = baseOffset -- world space, regardless of part orientation
		gui.AlwaysOnTop = true   -- render through walls
		gui.LightInfluence = 0   -- always full brightness
		gui.MaxDistance = 240    -- backstop: never visible from other islands even if island detection lags
		gui.Parent = player:WaitForChild("PlayerGui")

		local arrow = Instance.new("TextLabel")
		arrow.Size = UDim2.new(1, 0, 1, 0)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.SourceSansBold
		arrow.TextScaled = true
		arrow.TextColor3 = ARROW_COLOR
		arrow.Text = "▼" -- downward triangle, points at the NPC
		arrow.TextStrokeColor3 = Color3.new(0, 0, 0)
		arrow.TextStrokeTransparency = 0.3 -- outline for contrast against bright skies
		arrow.Parent = gui

		-- Gentle up/down bounce on a sine wave (added on top of the centered base
		-- offset). Hide the arrow while the NPC's speech bubble is showing.
		conn = RunService.Heartbeat:Connect(function()
			if gui then
				-- show this NPC's arrow ONLY while the player is on that NPC's island, and not while talking
				gui.Enabled = (not bubbleShowing) and (curIsland == spec.island)
				gui.StudsOffsetWorldSpace = baseOffset + Vector3.new(0, math.sin(os.clock() * BOUNCE_SPEED) * BOUNCE_AMP, 0)
			end
		end)
	end

	local function teardownArrow()
		if conn then
			conn:Disconnect()
		end
		if gui then
			gui:Destroy()
		end
		conn, gui = nil, nil
	end

	local function syncLifecycle()
		local anchor = findAnchorPart(npc)
		if anchor then
			if not gui then
				buildArrow(anchor)
			end
		elseif gui then
			teardownArrow()
		end
	end

	-- React instantly when a part replicates in, and poll for stream-in/out.
	npc.DescendantAdded:Connect(function(child)
		if child:IsA("BasePart") then
			syncLifecycle()
		end
	end)
	while true do
		syncLifecycle()
		task.wait(0.5)
	end
end

for _, spec in ipairs(NPCS) do
	task.spawn(setupArrow, spec)
end
