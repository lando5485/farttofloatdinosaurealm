--======================================================================
-- NPCGuide.client.luau  (LocalScript)
--======================================================================
-- A flat green CHEVRON TRAIL (the same "runway" style as the island4 fishing
-- guide) that points the player toward the current island's quest NPC -- the
-- miner / Researcher / Digger -- the moment they're on that island, and HIDES
-- once they accept that island's quest. One shared chevron pool, retargeted per
-- island, so it guides new players to the quest giver on every island.
--======================================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local player     = Players.LocalPlayer

-- island -> quest NPC + the attribute that means "accepted" (hide the trail).
-- island4: trail points to the CoastalFisher until you accept his quest; after
-- that, FishingQuest's own chevron takes over and points to the rod barrel.
local GUIDE = {
	[1] = { npcName = "miner",        parent = "island1", accept = "NestingNookQuestClaimed" },
	[2] = { npcName = "FrillRancher",                     accept = "Island2QuestAccepted" },
	[3] = { npcName = "DigMiner",                         accept = "DigQuestAccepted" },
	[4] = { npcName = "CoastalFisher",                    accept = "Island4QuestAccepted" },
	[5] = { npcName = "MireWatcher",                      accept = "Island5QuestAccepted" },
	[6] = { npcName = "RidgeWarden",                      accept = "Island6QuestAccepted" },
	[7] = { npcName = "RaptorScout",                      accept = "Island7QuestAccepted" },
	-- island11 "Volcanic Vista" = the geyser FINALE (island8 is now a blank island)
	[11] = { npcName = "AshWarden",                       accept = "Island11QuestAccepted" },
}

-- which island the player is on (XZ footprint), refreshed every 0.4s
local curIsland = nil
task.spawn(function()
	while true do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = hrp.Position; local best, bestD = nil, math.huge
			for i = 1, 13 do
				local isl = Workspace:FindFirstChild("island" .. i)
				if isl then
					local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
					if ok and cf and size then
						local dx, dy, dz = pos.X - cf.Position.X, pos.Y - cf.Position.Y, pos.Z - cf.Position.Z
						if math.abs(dx) <= size.X/2 and math.abs(dz) <= size.Z/2 and math.abs(dy) <= size.Y/2 + 80 then best = i; break end
						local d = dx*dx + dy*dy + dz*dz; if d < bestD then bestD = d; best = i end -- 3D nearest (islands stack vertically)
					end
				end
			end
			curIsland = best
		end
		task.wait(0.4)
	end
end)

-- ONE SHOWING PER ISLAND -- the same rule NPCWaypointArrow uses, and they have to agree
-- or the island keeps one guide and loses the other, which reads as a bug either way.
--
-- The trail is for finding the NPC the FIRST time you land. Once you fly off, that island
-- is done: the chevrons go at once and stay gone when you come back, because by then you
-- have been there and they are only pointing at someone you have already walked past.
--
-- Marked on the RISING EDGE of _G.isFlying (BottomHUD's flight flag), never continuously.
-- curIsland tracks the NEAREST island, so mid-climb it flips to the one you are rising
-- toward -- dismissing on "flying" alone would kill that island's trail before you ever
-- landed on it. At takeoff, curIsland is still the ground you just left.
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

-- find the quest NPC's ground position
-- NOTE the RECURSIVE FindFirstChild (the `true`). These used to be non-recursive, so
-- the island1 "miner" -- which lives at Workspace.island1.island1.miner (island1 is
-- nested inside itself) -- was never found, and island1's chevron trail to the miner
-- silently never appeared. Search the island's whole subtree, then all of Workspace.
local function findNPC(spec)
	local cont = spec.parent and Workspace:FindFirstChild(spec.parent) or Workspace
	local npc = cont and cont:FindFirstChild(spec.npcName, true)
	if not npc then npc = Workspace:FindFirstChild(spec.npcName, true) end
	if not npc then return nil end
	-- NOTE: a recursive FindFirstChild("HumanoidRootPart", true) can match a Pose
	-- of that name inside the rig's AnimSaves (which has no .Position and errors),
	-- so only accept a candidate that is actually a BasePart.
	local hrp = npc:FindFirstChild("HumanoidRootPart", true)
	local anchor = (hrp and hrp:IsA("BasePart")) and hrp
		or (npc:IsA("Model") and npc.PrimaryPart)
		or npc:FindFirstChildWhichIsA("BasePart", true)
	return (anchor and anchor:IsA("BasePart")) and anchor.Position or nil
end

-- ===== chevron trail (same flat striped runway as the fishing guide) =====
local BRIGHT = Color3.fromRGB(90, 200, 110)
local EDGE   = Color3.fromRGB(40, 120, 60)
local SPACING, MAX_ARROWS, STOP_DIST = 6, 18, 8
local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function part(model, name, sx,sy,sz, color, refl, cf)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(sx,sy,sz); p.Color = color
	p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.CFrame = cf; p.Parent = model; return p
end
local function buildChevron()
	local m = Instance.new("Model"); m.Name = "NPCGuideChevron"
	local root = part(m, "Root", 0.2,0.2,0.2, BRIGHT, 0, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
	local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
	local front = CFrame.new(0, 0, -0.9)
	part(m, "EdgeR", W+0.20, T*0.65, L+0.20, EDGE, 0, front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,-0.03,L/2))
	part(m, "EdgeL", W+0.20, T*0.65, L+0.20, EDGE, 0, front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,-0.03,L/2))
	part(m, "ArmR",  W, T, L, BRIGHT, 0.14,          front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, 0.04,L/2))
	part(m, "ArmL",  W, T, L, BRIGHT, 0.14,          front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, 0.04,L/2))
	m.Parent = Workspace
	return m
end
local pool = {}
local function getNode(i) if not pool[i] then pool[i] = buildChevron() end; return pool[i] end
local function setShown(nd, on) for _, p in ipairs(nd:GetDescendants()) do if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end end end
local function hideFrom(n) for i = n, #pool do if pool[i] then setShown(pool[i], false) end end end

RunService.RenderStepped:Connect(function()
	local spec = curIsland and GUIDE[curIsland]
	if not spec then hideFrom(1); return end
	if dismissed[curIsland] then hideFrom(1); return end -- already flown off here once -> guided already
	if player:GetAttribute(spec.accept) then hideFrom(1); return end -- quest accepted -> stop guiding
	local target = findNPC(spec)
	if not target then hideFrom(1); return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then hideFrom(1); return end
	local d = target - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z); local dist = flat.Magnitude
	if dist > 400 or dist <= STOP_DIST then hideFrom(1); return end -- far / arrived
	local dir = flat.Unit
	local excl = { char }; for _, nd in ipairs(pool) do excl[#excl+1] = nd end
	rayParams.FilterDescendantsInstances = excl
	local maxAlong = dist - STOP_DIST; local placed = 0
	for i = 1, MAX_ARROWS do
		local along = i * SPACING
		if along > maxAlong then break end
		placed += 1
		local px = hrp.Position.X + dir.X * along
		local pz = hrp.Position.Z + dir.Z * along
		local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rayParams)
		local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
		local nd = getNode(placed)
		local p0 = Vector3.new(px, gy + 0.12, pz)
		pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
		pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end) -- flow pulse
		setShown(nd, true)
	end
	hideFrom(placed + 1)
end)

print("[NPCGuide] chevron trail to each island's quest NPC active (until accepted)")
