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
		for i = 1, 13 do
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

-- ONE SHOWING PER ISLAND: the arrow is for finding the NPC the FIRST time you land
-- somewhere. Take off again and that island is done -- the arrow goes immediately, and
-- it does NOT come back when you return, because by then you have been there and the
-- arrow is just clutter pointing at someone you have already met.
--
-- Keyed on TAKEOFF, and only the island being LEFT is marked. The naive version --
-- "while flying, dismiss curIsland" -- is wrong in a way that only shows up mid-climb:
-- curIsland tracks the NEAREST island, so on the way up it flips to the island you are
-- approaching while you are still airborne, and that island would be dismissed before
-- you ever set foot on it. Only the rising edge of _G.isFlying counts, which is the
-- moment you leave, and curIsland still reads the island under your feet then.
--
-- _G.isFlying is BottomHUD's flight flag (set in startFlying / stopFlying). Polled
-- rather than signalled because it is a plain global; 0.1s is far finer than the 0.4s
-- island detection it is read against, so the pairing can never land a frame late.
local dismissed = {}
do
	local wasFlying = false
	task.spawn(function()
		while true do
			local flying = (_G.isFlying == true)
			if flying and not wasFlying and curIsland then
				dismissed[curIsland] = true
			end
			wasFlying = flying
			task.wait(0.1)
		end
	end)
end

-- One entry per NPC. `parent` is the Workspace descendant the NPC lives under,
-- `npcName` is the NPC Model's name.
local NPCS = {
	{ parent = "island1", npcName = "miner", island = 1 },
	-- dino1 (the Mama Dino) deliberately has NO waypoint arrow. She is a large static
	-- prop right beside the spawn, not something the player has to be led to, and the
	-- arrow sat on top of her. The quest still guides you to her when it matters:
	-- QuestGate puts an arrow above the PLAYER'S head pointing her way once all 5 eggs
	-- are returned.
	{ npcName = "DigMiner", island = 3 }, -- island3 Digger (parented directly under Workspace; no parent field = workspace)
	-- other-island Researchers (parented under Workspace by NestingNook_NPCs.setupIslandQuestNPC)
	{ npcName = "FrillRancher",  island = 2 },
	{ npcName = "CoastalFisher", island = 4 },
	{ npcName = "MireWatcher",   island = 5 },
	{ npcName = "RidgeWarden",   island = 6 },
	{ npcName = "RaptorScout",   island = 7 },
	{ npcName = "AshWarden",     island = 11 },  -- Volcanic Vista (geyser finale)
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

-- Wait for a DESCENDANT (not just a direct child) named `name` under `container`.
-- WaitForChild only looks one level deep. The island1 models are nested inside
-- themselves (Workspace.island1.island1.dino1), so `island1:WaitForChild("dino1")`
-- never resolved -- it timed out after 90s and the miner/dino1 arrows never appeared.
local function waitForDescendant(container: Instance, name: string, timeout: number): Instance?
	local found = container:FindFirstChild(name, true)
	if found then return found end
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		task.wait(0.25)
		found = container:FindFirstChild(name, true)
		if found then return found end
	end
	return nil
end

local function setupArrow(spec)
	local container = spec.parent and workspace:WaitForChild(spec.parent, 90) or workspace
	local npc = container and waitForDescendant(container, spec.npcName, 90)
	if not npc then
		warn(("[NPCWaypointArrow] %s not found under %s - no arrow."):format(spec.npcName, container and container:GetFullName() or "?"))
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
				-- show this NPC's arrow ONLY while the player is on that NPC's island, not while
				-- talking, and only until they have flown off it once (see `dismissed` above)
				gui.Enabled = (not bubbleShowing) and (curIsland == spec.island) and not dismissed[spec.island]
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
