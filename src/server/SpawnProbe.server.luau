-- ============================================================================================================
-- SPAWN PROBE  [TEMPORARY -- DELETE ONCE THE SPAWN BUG IS FIXED]
-- ============================================================================================================
-- "I join and fall into the void." The boot log cannot show this: it proves the spawn pad was PLACED, not
-- that anything solid is under it. Those are different claims, and only the second one keeps you standing.
--
-- So this reports, at the moment you actually spawn:
--   * where island1's pad is, and where you came out
--   * WHAT IS UNDER YOU -- the part's name, how far down, and whether it is collidable
--   * whether you are still falling a second later, which is the difference between "spawned wrong" and
--     "spawned right and the floor is missing"
--
-- The third line is the one that matters. A pad in the right place with nothing solid beneath it looks
-- identical in the boot log to a pad that works.
-- ============================================================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function describeGround(hrp, char)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	rp.IgnoreWater = true
	-- 2000 studs is deliberately far: if the nearest floor is hundreds of studs down, that IS the finding
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -2000, 0), rp)
	if not hit then
		return "NOTHING AT ALL within 2000 studs below you -- you are over open sky"
	end
	local p = hit.Instance
	return ("'%s' (%s) %.1f studs below | CanCollide=%s Anchored=%s Transparency=%.2f")
		:format(p.Name, p:GetFullName(), (hrp.Position - hit.Position).Magnitude,
			tostring(p.CanCollide), tostring(p.Anchored), p.Transparency)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end
		task.wait(0.15)   -- let the spawn placement settle before reading it

		print("========== SPAWN PROBE ==========")

		-- where the game MEANT to put you
		local island1 = Workspace:FindFirstChild("island1")
		local pad = island1 and island1:FindFirstChild("island1Spawn")
		if pad then
			print(("[SpawnProbe] island1 pad: (%.1f, %.1f, %.1f)  Enabled=%s")
				:format(pad.Position.X, pad.Position.Y, pad.Position.Z, tostring(pad.Enabled)))
		else
			warn("[SpawnProbe] island1Spawn PAD DOES NOT EXIST -- the spawn was never placed, so Roblox " ..
				"dropped you at the world origin. That is the bug.")
		end

		-- every enabled spawn in the place: more than one and Roblox picks at random
		local enabled = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("SpawnLocation") and d.Enabled then enabled[#enabled + 1] = d:GetFullName() end
		end
		print(("[SpawnProbe] enabled SpawnLocations: %d%s"):format(#enabled,
			(#enabled > 0) and ("  -> " .. table.concat(enabled, ", ")) or "  (NONE -- Roblox spawns you at 0,100,0)"))

		-- where you ACTUALLY came out, and what is holding you up
		local p0 = hrp.Position
		print(("[SpawnProbe] you spawned at: (%.1f, %.1f, %.1f)"):format(p0.X, p0.Y, p0.Z))
		if pad then
			print(("[SpawnProbe] that is %.1f studs from the pad"):format((p0 - pad.Position).Magnitude))
		end
		print("[SpawnProbe] ground below you: " .. describeGround(hrp, char))

		-- THE DECIDING LINE: still moving down a second later means nothing caught you
		task.delay(1.0, function()
			if not hrp.Parent then return end
			local p1 = hrp.Position
			local drop = p0.Y - p1.Y
			if drop > 8 then
				warn(("[SpawnProbe] FALLING -- dropped %.0f studs in 1s (now Y=%.0f). The pad is in the " ..
					"right place but nothing solid is under it: island1's floor is missing, non-collidable, " ..
					"or was deleted."):format(drop, p1.Y))
			else
				print(("[SpawnProbe] landed OK -- moved %.1f studs in 1s (now Y=%.0f)"):format(drop, p1.Y))
			end
			print("========== END SPAWN PROBE ==========")
		end)
	end)
end)

print("[SpawnProbe] armed -- rejoin and read the ========== SPAWN PROBE ========== block  [DELETE ME LATER]")
