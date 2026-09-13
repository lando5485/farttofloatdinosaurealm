-- ============================================================================================================
-- T-REX ROAMER (client) -- the animation half. TRexRoam.server.luau moves the body; this makes it alive.
-- ============================================================================================================
-- WHY THIS IS ON THE CLIENT AT ALL: Bone.Transform DOES NOT REPLICATE. A server that poses bones poses them
-- for nobody -- the same lesson RedwoodRaptor.client.luau documents, and the reason the raptors are animated
-- this way too. Motor6D joints do replicate, so those are driven here as well purely to keep one code path.
--
-- IT DOES NOT KNOW WHAT RIG IT IS DRIVING. The model was made by someone else, so rather than assume a
-- skeleton it looks for what is there and animates whatever it finds, best option first:
--
--   1. A PACKAGED ANIMATION (Humanoid/AnimationController + an Animation asset). If the model came with a
--      walk cycle, that is better than anything procedural and it simply plays it.
--   2. BONES -- tail, neck, head, legs, matched loosely by name so Tail1/tail_01/TailBone all count.
--   3. MOTOR6D joints, same names, for older R6-style rigs.
--   4. NOTHING USABLE -> the whole model still breathes and bobs as it walks. A static mesh sliding around
--      looks broken; a static mesh with weight to its step reads as deliberate.
--
-- The motion is keyed off how fast the body is ACTUALLY moving, which the server drives -- so he strides
-- when walking and settles when paused, without the two halves having to talk to each other.
-- ============================================================================================================

local RunService = game:GetService("RunService")

-- loose name matching: "Tail1", "tail_01" and "Bone_Tail" should all be found
local function findAll(model, pattern)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Bone") or d:IsA("Motor6D")) and string.find(string.lower(d.Name), pattern) then
			out[#out + 1] = d
		end
	end
	table.sort(out, function(a, b) return a.Name < b.Name end)   -- Tail1 before Tail2, so the wave travels
	return out
end

-- Bone and Motor6D both animate through a .Transform, so one setter covers rigs of either kind.
local function pose(j, cf) if j then j.Transform = cf end end

local function animate(rex)
	-- ---- 1. did it ship with its own animation? ----
	local animator = rex:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		local ctrl = rex:FindFirstChildWhichIsA("AnimationController", true)
			or rex:FindFirstChildWhichIsA("Humanoid", true)
		if ctrl then animator = ctrl:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", ctrl) end
	end
	local anim = rex:FindFirstChildWhichIsA("Animation", true)
	if animator and anim then
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			track.Looped = true
			track:Play()
			print(("[TRex] playing the model's own animation '%s' -- no procedural motion needed"):format(anim.Name))
			return
		end
	end

	-- ---- 2/3. whatever skeleton it has ----
	local tail  = findAll(rex, "tail")
	local legs  = findAll(rex, "leg")
	local feet  = findAll(rex, "foot")
	local neck  = findAll(rex, "neck")[1]
	local head  = findAll(rex, "head")[1]
	local torso = findAll(rex, "torso")[1] or findAll(rex, "spine")[1] or findAll(rex, "body")[1]
	local jaw   = findAll(rex, "jaw")[1]
	local rigged = (#tail + #legs + #feet) > 0 or neck or head or torso

	-- ---- 4. no rig: still give the whole model weight ----
	-- Nothing to bend, so the BODY is bobbed and rolled instead. Its original pose is captured relative to
	-- the pivot so the sway is applied on top of wherever the server has put him, never replacing it.
	local base = rex:GetPivot()
	local partsRel = {}
	if not rigged then
		for _, d in ipairs(rex:GetDescendants()) do
			if d:IsA("BasePart") then partsRel[#partsRel + 1] = { d, base:ToObjectSpace(d.CFrame) } end
		end
	end

	local t, walkT, moveTimer, gait = math.random() * 10, 0, 0, 0
	local prev = rex:GetPivot().Position
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not rex.Parent then conn:Disconnect(); return end
		dt = math.min(dt, 1 / 30)          -- a frame hitch must not jolt the pose
		t += dt

		-- IS HE WALKING? Read it from the body the server is moving. moveTimer holds the answer between
		-- the server's throttled updates, so the legs keep striding instead of stuttering to a halt
		-- between position packets.
		local now = rex:GetPivot().Position
		if ((now - prev) * Vector3.new(1, 0, 1)).Magnitude > 0.01 then moveTimer = 0.35 end
		prev = now
		moveTimer = math.max(0, moveTimer - dt)
		gait += ((moveTimer > 0 and 1 or 0) - gait) * math.min(dt * 6, 1)   -- eased, so it starts and stops smoothly
		walkT += dt * (2.6 + 1.4 * gait)   -- a T-Rex strides slower than a raptor: long, heavy steps
		local breath = math.sin(t * 1.2)

		if rigged then
			-- TAIL: a travelling wave, held out behind for balance and swinging wider as he walks.
			-- Counter-phased against the stride so it reads as balance, not decoration.
			for i, b in ipairs(tail) do
				pose(b, CFrame.Angles(
					math.sin(t * 1.4 - i * 0.5) * math.rad(2.5),
					math.sin(walkT - i * 0.55) * math.rad(7 + 7 * gait), 0))
			end
			-- NECK + HEAD: slow predatory scanning while idle, levelling out and pushing forward at speed
			pose(neck, CFrame.Angles(
				math.sin(t * 1.1) * math.rad(3) + gait * math.rad(6),
				math.sin(t * 0.6) * math.rad(9), 0))
			pose(head, CFrame.Angles(
				math.sin(t * 1.7) * math.rad(3) - gait * math.rad(5),
				math.sin(t * 0.5) * math.rad(6), math.sin(t * 0.9) * math.rad(2)))
			-- JAW: an occasional slow open, not a chatter -- max() keeps it shut most of the time
			pose(jaw, CFrame.Angles(math.max(0, math.sin(t * 0.35) - 0.85) * math.rad(70), 0, 0))
			-- TORSO: stride bob + roll, easing into idle breathing when he stops
			pose(torso, CFrame.new(0, math.sin(walkT * 2) * 0.09 * gait + breath * 0.02 * (1 - gait), 0)
				* CFrame.Angles(0, 0, math.sin(walkT) * math.rad(2 + 3 * gait)))
			-- LEGS: two legs, so alternate them a half-cycle apart; feet trail by a quarter so the
			-- ankle folds after the thigh swings rather than with it
			for i, b in ipairs(legs) do
				pose(b, CFrame.Angles(math.sin(walkT + (i % 2 == 0 and math.pi or 0)) * math.rad(26) * gait, 0, 0))
			end
			for i, b in ipairs(feet) do
				pose(b, CFrame.Angles(math.sin(walkT + (i % 2 == 0 and math.pi or 0) + 1.5) * math.rad(16) * gait, 0, 0))
			end
		else
			-- unrigged: sway the whole body around the server's current pivot
			local p = rex:GetPivot()
			local sway = CFrame.new(0, math.sin(walkT * 2) * 0.12 * gait + breath * 0.03 * (1 - gait), 0)
				* CFrame.Angles(0, 0, math.sin(walkT) * math.rad(2.5 + 2.5 * gait))
			for _, e in ipairs(partsRel) do
				if e[1].Parent then e[1].CFrame = p * sway * e[2] end
			end
		end
	end)

	if rigged then
		print(("[TRex] bone animation running -- %d tail, %d leg, %d foot joint(s)%s%s")
			:format(#tail, #legs, #feet, neck and ", neck" or "", head and ", head" or ""))
	else
		print("[TRex] this model has no bones or Motor6Ds and shipped no animation, so the whole body " ..
			"bobs and rolls as it walks instead. Rig it (or add an Animation) and this script picks that " ..
			"up automatically with no changes.")
	end
end

-- The server tags him once he is grounded and roaming; wait for that rather than racing it.
local seen = {}
local function try(inst)
	if inst:IsA("Model") and inst:GetAttribute("TRexRoamer") and not seen[inst] then
		seen[inst] = true
		task.spawn(function() task.wait(0.25); animate(inst) end)   -- let the bones replicate first
	end
end
for _, d in ipairs(workspace:GetDescendants()) do try(d) end
workspace.DescendantAdded:Connect(try)
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		d:GetAttributeChangedSignal("TRexRoamer"):Connect(function() try(d) end)
	end
end)
-- the model usually exists before the server tags it, so watch for the tag arriving on models already here
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") then
		d:GetAttributeChangedSignal("TRexRoamer"):Connect(function() try(d) end)
	end
end

print("[TRex] client ready -- waiting for the roaming T-Rex to be tagged by the server")
