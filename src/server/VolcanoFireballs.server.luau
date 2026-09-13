--======================================================================
-- VolcanoFireballs.server.luau  (Server Script)
--======================================================================
-- THE CRATER half of the volcano hazard. Two jobs, both small:
--
--   1. PUBLISH WHERE THE CRATER IS. The client cannot find "Volcanospot" on its own.
--      With StreamingEnabled a part 15,000 studs above you is NOT replicated -- and the
--      hazard has to be running while the player is still down at slot 11, long before
--      the summit streams in. The server always has the whole Workspace, so it finds the
--      part once and writes the position into ReplicatedStorage.VolcanoSpotPos for the
--      client to read. (This is the same reason Bubbles.client reads the tower ladder out
--      of IslandOrder instead of measuring the islands in Workspace.)
--
--   2. MAKE THE VOLCANO LOOK LIKE IT IS WAKING UP -- NOT ERUPTING. Deliberately
--      restrained: a thin smoke column, a soft glow in the throat, and the odd puff of
--      embers. No lava fountain, no roar, no shake. The brief was "early stages", so the
--      crater should read as ominous rather than as a set piece going off.
--
-- The falling fireballs themselves are NOT here -- they are per-player and client-side,
-- in VolcanoFireballs.client.luau. See that file's header for why.
--
-- RE-READ ON A LOOP because IslandLayout MOVES the island models at startup. Reading the
-- crater position once at boot would cache wherever the part sat in Studio, which is not
-- where it ends up in game.
--======================================================================

local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

local SPOT_NAME  = "volcanospot"   -- compared lowercased, so VolcanoSpot / VOLCANOSPOT all match
local REPUBLISH  = 5               -- seconds between position refreshes

-- Values the client reads. All three are published together on the loop at the bottom.
--   VolcanoSpotPos      -- the crater, where launched fireballs come out of
--   VolcanoIslandCenter -- bounding-box centre of the island the volcano sits on
--   VolcanoIslandSize   -- bounding-box size of that island
-- The last two exist so the client can keep fireballs from passing THROUGH the island:
-- it needs the footprint radius and the top/bottom to test against, and it cannot measure
-- the model itself because with StreamingEnabled the summit's parts are not replicated
-- while the player is still down at slot 11.
local function ensureVec(name)
	local v = ReplicatedStorage:FindFirstChild(name)
	if not v then
		v = Instance.new("Vector3Value")
		v.Name = name
		v.Value = Vector3.zero   -- zero means "not measured yet"; the client uses its own fallback
		v.Parent = ReplicatedStorage
	end
	return v
end

local posValue    = ensureVec("VolcanoSpotPos")
local centerValue = ensureVec("VolcanoIslandCenter")
local sizeValue   = ensureVec("VolcanoIslandSize")

-- Bounds for the ISLANDS UNDER THE VOLCANO as well, so a falling fireball can find the
-- ground and actually land on it instead of sinking through. Attributes rather than a
-- tree of Vector3Values: one container, two attributes per slot, and Vector3 attributes
-- replicate to clients like any other.
--     Center_<slot>, Size_<slot>   for the top TRACK_SLOTS slots of the tower
local TRACK_SLOTS = 4
local bounds = ReplicatedStorage:FindFirstChild("VolcanoIslandBounds")
if not bounds then
	bounds = Instance.new("Folder")
	bounds.Name = "VolcanoIslandBounds"
	bounds.Parent = ReplicatedStorage
end

local function publishIslandBounds()
	for slot = math.max(1, IslandOrder.COUNT - TRACK_SLOTS + 1), IslandOrder.COUNT do
		local num = IslandOrder.SLOT_TO_ISLAND[slot]
		local m = num and Workspace:FindFirstChild("island" .. num)
		if m and m:IsA("Model") then
			local ok, cf, size = pcall(function()
				local c, s = m:GetBoundingBox()
				return c, s
			end)
			if ok and cf and size and size.Magnitude > 1 then
				bounds:SetAttribute("Center_" .. slot, cf.Position)
				bounds:SetAttribute("Size_" .. slot, size)
			end
		end
	end
end

-- The island model the crater sits on. Walks UP from the marker rather than assuming the
-- summit, so moving the volcano to a different island needs no code change here. Falls
-- back to whatever model the shared ladder puts in the top slot.
local function findIslandModel(spot)
	local node = spot
	while node and node ~= Workspace do
		if node:IsA("Model") and string.match(string.lower(node.Name), "^island%d+$") then
			return node
		end
		node = node.Parent
	end
	local summitNum = IslandOrder.SLOT_TO_ISLAND[IslandOrder.COUNT]
	local m = Workspace:FindFirstChild("island" .. summitNum)
	if m and m:IsA("Model") then return m end
	return nil
end

-- Recursive, case-insensitive hunt. FindFirstChild(name, true) would work but is
-- case-SENSITIVE, and the part was named by hand in Studio.
local function findSpot()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and string.lower(d.Name) == SPOT_NAME then
			return d
		end
	end
	return nil
end

--======================================================================
-- CRATER DRESSING -- parented to the marker part, never modifying the part itself.
-- Everything here is a CHILD of Volcanospot, so deleting the children removes the
-- effect completely and the builder's own part is left exactly as they made it.
--======================================================================
local function dressCrater(spot)
	if spot:FindFirstChild("VolcanoStirring") then return end   -- already dressed

	local root = Instance.new("Folder")
	root.Name = "VolcanoStirring"
	root.Parent = spot

	local att = Instance.new("Attachment")
	att.Name = "CraterAttachment"
	att.Parent = spot
	att.Position = Vector3.new(0, spot.Size.Y / 2, 0)   -- lip of the marker, not its middle

	-- SMOKE: the tell you can see from three islands down. Slow, thin, and wide rather
	-- than dense -- a dense plume reads as a full eruption, which is the one thing asked
	-- against. Long lifetime is what makes the column tall without needing a fast rate.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "CraterSmoke"
	smoke.Parent = att
	smoke.Texture = "rbxassetid://241650934"
	smoke.Rate = 14
	smoke.Lifetime = NumberRange.new(6, 10)
	smoke.Speed = NumberRange.new(28, 46)
	smoke.SpreadAngle = Vector2.new(14, 14)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-18, 18)
	smoke.LightEmission = 0.12
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 14),
		NumberSequenceKeypoint.new(1, 92),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 78, 72)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(52, 48, 48)),
	})

	-- EMBERS: sparse orange flecks lifting out of the throat. Rate is low on purpose --
	-- these are meant to be noticed, not to form a sheet.
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "CraterEmbers"
	embers.Parent = att
	embers.Rate = 9
	embers.Lifetime = NumberRange.new(2.5, 4.5)
	embers.Speed = NumberRange.new(55, 95)
	embers.SpreadAngle = Vector2.new(22, 22)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 55, 20)),
	})

	-- GLOW in the throat. Range is generous but brightness is not -- it should look like
	-- something hot is a long way down, not like a light bulb sitting in the rock.
	local light = Instance.new("PointLight")
	light.Name = "CraterGlow"
	light.Parent = att
	light.Color = Color3.fromRGB(255, 130, 45)
	light.Brightness = 1.6
	light.Range = 46
	light.Shadows = false

	-- Slow uneven pulse, so the glow breathes instead of sitting flat. Cheap: one
	-- property, four times a second.
	task.spawn(function()
		local t = 0
		while light.Parent do
			t += 0.25
			light.Brightness = 1.35 + math.sin(t * 0.9) * 0.35 + math.sin(t * 2.3) * 0.15
			task.wait(0.25)
		end
	end)

	print(("[Volcano] crater dressed at %s (%s)"):format(spot:GetFullName(), tostring(spot.Position)))
end

--======================================================================
-- BOOT: find the marker, then keep its published position current.
--======================================================================
task.spawn(function()
	local spot = nil

	-- Hunt until it turns up. IslandLayout runs at startup and the island models may not
	-- be parented yet on the first pass, so this keeps looking rather than giving up.
	for _ = 1, 60 do
		spot = findSpot()
		if spot then break end
		task.wait(1)
	end

	if not spot then
		warn("[Volcano] no part named 'Volcanospot' found in Workspace. The fireballs will "
			.. "fall from the summit's ladder position instead (IslandOrder.SLOT_POS[13]). "
			.. "Name the crater part 'Volcanospot' to place them exactly.")
		return
	end

	dressCrater(spot)

	local island = findIslandModel(spot)
	if island then
		print(("[Volcano] crater sits on %s"):format(island:GetFullName()))
	else
		warn("[Volcano] could not identify the island the crater sits on -- fireballs will "
			.. "use the client's fallback footprint and may clip the island edges.")
	end

	while spot.Parent do
		posValue.Value = spot.Position
		publishIslandBounds()
		-- Re-measured every pass, not cached: IslandLayout moves the models at startup, and
		-- a bounding box read before that ran would describe the island's Studio position.
		if island and island.Parent then
			local ok, cf, size = pcall(function()
				local c, s = island:GetBoundingBox()
				return c, s
			end)
			if ok and cf and size and size.Magnitude > 1 then
				centerValue.Value = cf.Position
				sizeValue.Value = size
			end
		end
		task.wait(REPUBLISH)
	end
end)

--======================================================================
-- HIDE THE QUEST PLACEMENT BLOCKS -- ON THE SERVER, SO THEY STAY HIDDEN.
--======================================================================
-- GeyserQuest.client already ghosts EggSpot8 and Geyser1..6, and it works -- the boot log
-- says "ghosted 7 placement-block part(s)". The problem is WHERE it happens.
--
-- That sweep is a LocalScript changing properties on its own client, and the place has
-- StreamingEnabled. Island 11 is the summit of a 30,000-stud tower, so it streams out the
-- moment you drop away from it. When you come back, Roblox re-sends those parts from the
-- SERVER -- with the server's properties, which still say Transparency 0. The marker is
-- visible again and the client sweep has long since finished; it never re-runs.
--
-- Doing it here instead makes it stick: a server-side property change is the replicated
-- truth, so every stream-in and every player that joins later gets the hidden version.
--
-- HIDDEN, NOT DELETED. GeyserQuest reads the marker's POSITION to stand the nest on it and
-- to know where the reward egg goes -- destroying the block would take the nest with it.
--
-- The geyser markers get the same treatment for the same reason: the client builds visible
-- vent art over them, and a marker that streams back in pokes a grey box out through it.
do
	local WANT = { "eggspot", "geyser" }   -- matched as a SUBSTRING of the de-punctuated name

	local function looksLikeMarker(name: string): boolean
		local key = name:lower():gsub("[^%w]", "")
		for _, w in ipairs(WANT) do
			if key:find(w, 1, true) then return true end
		end
		return false
	end

	local function hide(part: BasePart)
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false     -- also keeps the nest's ground raycast from hitting the marker
		part.CanTouch = false
		part.CastShadow = false   -- an invisible part still throws a shadow otherwise
	end

	local function sweep(): number
		local n = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if looksLikeMarker(d.Name) then
				if d:IsA("BasePart") then
					if d.Transparency < 1 then hide(d); n += 1 end
				elseif d:IsA("Model") then
					for _, p in ipairs(d:GetDescendants()) do
						if p:IsA("BasePart") and p.Transparency < 1 then hide(p); n += 1 end
					end
				end
			end
		end
		return n
	end

	task.spawn(function()
		-- The islands are moved into the tower by IslandLayout at startup; wait for that so
		-- the sweep is not racing an empty Workspace. Then re-sweep a few times to catch
		-- anything that arrives late, and stop -- this is boot cleanup, not a live watcher.
		local t0 = os.clock()
		while not _G.islandsPositioned and os.clock() - t0 < 10 do task.wait(0.25) end
		local total = sweep()
		for _ = 1, 5 do
			task.wait(3)
			total += sweep()
		end
		print(("[Volcano] hid %d quest placement block(s) server-side (EggSpot / Geyser) -- "
			.. "they stay hidden through streaming now, unlike the client-side ghosting"):format(total))
	end)
end

print("[Volcano] server ready -- publishing crater position on ReplicatedStorage.VolcanoSpotPos")
