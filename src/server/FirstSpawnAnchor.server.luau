-- ============================================================================================================
-- FIRST SPAWN ANCHOR -- puts your FIRST character of the session on island1's pad, whatever Roblox did.
-- ============================================================================================================
-- THE BUG THIS FIXES, measured rather than guessed (see the SpawnProbe output that found it):
--
--     island1 pad: (-4.6, 200.1, -68.2)  Enabled=true
--     enabled SpawnLocations: 1  -> Workspace.island1.island1Spawn
--     you spawned at: (113.2, 176.6, 315.5)      <-- 402 studs away
--     ground below you: NOTHING within 2000 studs -- open sky
--
-- One enabled spawn, in the right place, and the character still came out 402 studs from it over open air.
-- That is only possible if THE CHARACTER WAS CREATED BEFORE THE PADS WERE CONFIGURED. Roblox chooses a
-- SpawnLocation at the moment it builds the character; NestingNook_NPCs disables the twelve original pads
-- and places island1's a fraction of a second into boot, and in Studio the local player joins at almost
-- exactly server-start. Lose that race and you spawn on whichever original pad was still enabled -- which
-- is why dying and respawning always landed correctly: by then setup had finished.
--
-- ORDERING CANNOT BE FIXED BY MOVING CODE AROUND. The spawn pads depend on the islands being laid out,
-- the miner being placed (island1's pad position is recovered from the pad he replaced), and the island
-- models having streamed -- and a player can join before any of that. So rather than race, this corrects
-- the result: wait for the pad to exist, then put the character on it.
--
-- ONLY THE FIRST CHARACTER PER SESSION. ReturnIsland deliberately respawns you at your FURTHEST island
-- when you die, and its header says the first spawn is left to Intro / ArrivalReceiver. Snapping every
-- respawn to island1 would silently undo that and drag you back to the bottom of the tower every death.
-- ============================================================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SNAP_IF_FARTHER_THAN = 25   -- studs. Below this you are already on the pad; leave it alone.
local STAND_HEIGHT         = 3.5  -- lift so the character stands ON the pad rather than inside it

local function island1Pad(timeout)
	local t0 = os.clock()
	repeat
		local island1 = Workspace:FindFirstChild("island1")
		local pad = island1 and island1:FindFirstChild("island1Spawn")
		if pad and pad:IsA("BasePart") then return pad end
		task.wait(0.1)
	until os.clock() - t0 > timeout
	return nil
end

Players.PlayerAdded:Connect(function(plr)
	local first = true
	plr.CharacterAdded:Connect(function(char)
		if not first then return end     -- deaths belong to ReturnIsland, not to this
		first = false

		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end

		-- The pad is placed a beat into boot, and this character may well exist before it does --
		-- that IS the bug -- so wait for it rather than reading a nil and giving up.
		local pad = island1Pad(20)
		if not pad then
			warn("[FirstSpawn] island1Spawn never appeared -- cannot place " .. plr.Name ..
				". They are wherever Roblox put them.")
			return
		end

		local dist = (hrp.Position - pad.Position).Magnitude
		if dist <= SNAP_IF_FARTHER_THAN then
			print(("[FirstSpawn] %s already on island1's pad (%.1f studs) -- left alone"):format(plr.Name, dist))
			return
		end

		-- Keep the pad's facing so the player looks the way the pad was rotated to point (that rotation
		-- is deliberate -- see the "rotated 90 CW" note where island1's pad is rebuilt).
		local target = CFrame.new(pad.Position + Vector3.new(0, STAND_HEIGHT, 0)) * (pad.CFrame - pad.Position)
		char:PivotTo(target)
		-- Kill any inherited velocity, or the character keeps the fall it had already started and drops
		-- straight back off the island the instant it is unfrozen.
		hrp.AssemblyLinearVelocity  = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		print(("[FirstSpawn] %s spawned %.0f studs off (the pads had not finished setting up yet) " ..
			"-> moved onto island1's pad"):format(plr.Name, dist))
	end)
end)

print("[FirstSpawn] ready -- the first character of each session is placed on island1's pad " ..
	"(deaths still go to your furthest island via ReturnIsland)")
