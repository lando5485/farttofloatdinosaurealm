-- ============================================================================================================
-- T-REX ROAMER -- finds the "T rex" model in the place and walks it around its island.
-- ============================================================================================================
-- SPLIT THE SAME WAY THE REDWOOD RAPTORS ARE, AND FOR THE SAME REASON:
--   * THIS script (server) moves the BODY, so every player sees the dinosaur in the same place.
--   * TRexRoam.client.luau animates the BONES, because Bone.Transform does not replicate -- a server that
--     poses bones poses them for nobody. See RedwoodRaptor.client.luau, which learned this the hard way.
--
-- NOTHING HERE IS HARDCODED TO A LOCATION. The model was placed by hand in Studio, so this finds it by name
-- (any of the spellings below), works out which way it is facing, drops it onto the ground, and roams it
-- around wherever it happens to be standing. Move it to another island in Studio and it keeps working.
--
-- HOW IT DECIDES WHICH WAY IS FORWARD -- in order, first that works wins:
--   1. a part or bone named "Head"  -> forward is the direction from the body's centre toward it. This is
--      right for essentially every rigged dinosaur, and it is the same trick PetSkinLook uses with eyes.
--   2. the model's pivot            -> its -Z, the Roblox convention.
-- If it ends up walking sideways or backwards, set a FaceOffset attribute on the model (degrees) and it is
-- corrected without touching this file. The boot log prints which method was used and what to do about it.
-- ============================================================================================================

local RunService = game:GetService("RunService")

-- ===== TUNING =====
local NAMES = { "t rex", "t-rex", "trex", "t_rex", "tyrannosaurus rex" } -- lower-cased, matched exactly
local ROAM_RADIUS  = 70     -- studs from where it was placed -- its territory, so it never wanders the map
local SPEED        = 9      -- studs/second: a heavy, unhurried walk, not a sprint
local TURN_RATE    = 1.6    -- radians/second -- it swings round like something with mass
local PAUSE_MIN    = 2.0    -- it stops to look around between walks; a dinosaur that never
local PAUSE_MAX    = 5.5    -- pauses reads like a wind-up toy
local ARRIVE_DIST  = 4      -- close enough to call it arrived
local STEP_HZ      = 20     -- movement updates/second. Plenty for a slow walker, and far cheaper than
                            -- every frame -- the client smooths the visual side anyway.

-- WALKING THROUGH IT, ON PURPOSE. An ANCHORED model driven by PivotTo does not push players -- it sweeps
-- through them and can pin one against a rock with no way out, because nothing about that motion is a
-- physics interaction the player can push back on. Non-colliding is the honest choice for scenery that
-- moves on rails. Set this false if you would rather it were solid and accept the pinning.
local NO_COLLIDE = true

-- ===== FIND IT =====
-- Searched by name anywhere under Workspace, so it does not matter which island model it was dropped into.
-- Templates and pets are excluded: ReplicatedStorage holds TyrannosaurusTemplate, and an equipped pet
-- follower is also a T-Rex -- roaming somebody's pet across the island would be quite the bug.
local function findTRex()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and not d:FindFirstChildWhichIsA("Humanoid") then
			local n = string.lower(d.Name)
			for _, want in ipairs(NAMES) do
				if n == want then
					-- not a pet follower, not a hub icon, not a build artefact
					if not (string.find(n, "template", 1, true)
						or d:GetAttribute("PetFollower")
						or d:FindFirstAncestorWhichIsA("ViewportFrame")) then
						return d
					end
				end
			end
		end
	end
	return nil
end

-- ===== GROUND =====
-- Raycast down onto the island, ignoring the dinosaur itself and anything alive, so it stands ON the
-- terrain rather than inside it or hovering over it.
local function groundY(model, pos)
	local ignore = { model }
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p.Character then ignore[#ignore + 1] = p.Character end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(pos.X, pos.Y + 250, pos.Z), Vector3.new(0, -600, 0), rp)
	return hit and hit.Position.Y or nil
end

task.spawn(function()
	-- The islands stream and build over the first few seconds; give the place time to exist before
	-- deciding the model is not there. Same patience the quest scripts use.
	local rex
	for _ = 1, 40 do
		rex = findTRex()
		if rex then break end
		task.wait(0.5)
	end
	if not rex then
		warn("[TRex] no model named 'T rex' found in Workspace after 20s. Accepted spellings: " ..
			table.concat(NAMES, ", ") .. " (case does not matter). Rename the model to one of those.")
		return
	end

	-- A PrimaryPart is what PivotTo steers by. Most hand-placed models have none, so adopt the biggest
	-- part rather than failing -- picking the largest keeps the pivot near the body's mass instead of on
	-- some stray prop.
	if not rex.PrimaryPart then
		local best, bestVol = nil, -1
		for _, d in ipairs(rex:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > bestVol then best, bestVol = d, v end
			end
		end
		if not best then warn("[TRex] '" .. rex.Name .. "' has no BaseParts -- nothing to move."); return end
		rex.PrimaryPart = best
		print(("[TRex] no PrimaryPart set -> adopted '%s' (the largest part) as the pivot"):format(best.Name))
	end

	-- ANCHOR EVERYTHING. The model is moved with PivotTo, which fights physics if the parts are loose:
	-- unanchored limbs sag, drift, or fall through the island the moment the body teleports forward.
	local partCount = 0
	for _, d in ipairs(rex:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if NO_COLLIDE then d.CanCollide = false end
			partCount += 1
		end
	end

	local cf, size = rex:GetBoundingBox()
	local home = cf.Position

	-- ---- WHICH WAY IS IT FACING? (see the header) ----
	local forward, how
	local head = rex:FindFirstChild("Head", true)
	if head and (head:IsA("BasePart") or head:IsA("Bone")) then
		local v = (head.Position - home) * Vector3.new(1, 0, 1)
		if v.Magnitude > 0.5 then forward, how = v.Unit, "the 'Head' part" end
	end
	if not forward then
		forward, how = (rex:GetPivot().LookVector * Vector3.new(1, 0, 1)).Unit, "the model's pivot (-Z)"
	end
	-- manual correction hatch: FaceOffset on the model, in degrees
	local faceOff = tonumber(rex:GetAttribute("FaceOffset")) or 0
	if faceOff ~= 0 then
		forward = (CFrame.Angles(0, math.rad(faceOff), 0) * forward).Unit
		how = how .. (", plus your FaceOffset of %d deg"):format(faceOff)
	end
	-- The yaw correction that turns "the direction it should travel" into "the CFrame to hold it at".
	-- Baked once here so the walk loop is a plain lookAt with a fixed twist, not per-frame trigonometry.
	local baseYaw = math.atan2(forward.X, forward.Z) - math.atan2(0, 1)

	local gy = groundY(rex, home)
	if gy then
		rex:PivotTo(rex:GetPivot() + Vector3.new(0, (gy + size.Y / 2) - home.Y, 0))
		home = rex:GetPivot().Position
	end

	rex:SetAttribute("TRexRoamer", true)   -- the client watches for this to start the bone animation
	print(("[TRex] roaming '%s' (%d parts) at (%.0f, %.0f, %.0f) -- home radius %d, speed %d")
		:format(rex:GetFullName(), partCount, home.X, home.Y, home.Z, ROAM_RADIUS, SPEED))
	print(("[TRex] facing worked out from %s. If he walks sideways or backwards, add a NumberValue-style " ..
		"attribute 'FaceOffset' to the model (90 / 180 / 270) and rerun -- no code change needed."):format(how))
	if NO_COLLIDE then
		print("[TRex] collision off so he cannot pin a player against scenery (he is moved on rails, " ..
			"not by physics). Set NO_COLLIDE=false in TRexRoam.server.luau if you want him solid.")
	end

	-- ===== PICK SOMEWHERE TO GO =====
	-- Only accepts a destination with real ground under it at a sane height, which is what keeps him on
	-- the island instead of striding off the edge: past the rim the ray finds nothing (or something far
	-- below) and the point is thrown away.
	local function pickTarget(from)
		for _ = 1, 12 do
			local ang  = math.random() * math.pi * 2
			local dist = 18 + math.random() * (ROAM_RADIUS - 18)
			local p    = home + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
			local y    = groundY(rex, p)
			if y and math.abs(y - from.Y) < 25 then         -- no cliffs, no voids
				return Vector3.new(p.X, y, p.Z)
			end
		end
		return nil
	end

	-- ===== THE WALK =====
	local target      = nil
	local pauseLeft   = 1.0
	local curYaw      = math.atan2(forward.X, forward.Z)
	local footY       = size.Y / 2      -- pivot height above the ground
	local acc         = 0

	RunService.Heartbeat:Connect(function(dt)
		if not rex.Parent then return end
		acc += dt
		if acc < 1 / STEP_HZ then return end
		dt, acc = acc, 0

		local pivot = rex:GetPivot()
		local pos   = pivot.Position

		if pauseLeft > 0 then
			pauseLeft -= dt
			return
		end
		if not target then
			target = pickTarget(pos)
			if not target then pauseLeft = 1.5; return end   -- boxed in; wait and try again
		end

		local flat = (target - pos) * Vector3.new(1, 0, 1)
		if flat.Magnitude < ARRIVE_DIST then
			target    = nil
			pauseLeft = PAUSE_MIN + math.random() * (PAUSE_MAX - PAUSE_MIN)
			return
		end

		-- TURN FIRST, THEN WALK. Rotating toward the target over time (instead of snapping to face it)
		-- is most of what makes something this size read as heavy; and moving along where he is ACTUALLY
		-- pointing, not straight at the target, makes him lean into the turn instead of crabbing.
		local want = math.atan2(flat.Unit.X, flat.Unit.Z)
		local diff = (want - curYaw + math.pi) % (math.pi * 2) - math.pi
		curYaw += math.clamp(diff, -TURN_RATE * dt, TURN_RATE * dt)

		local heading = Vector3.new(math.sin(curYaw), 0, math.cos(curYaw))
		-- slow down while turning hard, so he pivots on the spot rather than skating through the corner
		local throttle = math.clamp(1 - math.abs(diff) / 1.4, 0.15, 1)
		local step     = heading * (SPEED * throttle * dt)
		local nxt      = pos + step

		-- stay on the ground the whole way, so slopes are walked rather than floated over
		local y = groundY(rex, nxt)
		if y then
			nxt = Vector3.new(nxt.X, y + footY, nxt.Z)
		else
			target = nil; pauseLeft = 1.0; return    -- walked onto nothing: stop and choose again
		end

		rex:PivotTo(CFrame.new(nxt) * CFrame.Angles(0, curYaw - baseYaw, 0))
	end)
end)
