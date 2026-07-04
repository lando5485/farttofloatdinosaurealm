--======================================================================
-- IslandLayout.server.luau  (server Script)  -- RUNS FIRST
--======================================================================
-- Spaces islands 1-8 into the vertical "tower" layout (the same coordinates the
-- other game uses via _G.ISLAND_POS). Each island MODEL is moved to its target
-- (rotation preserved, children come along). Then it sets _G.islandsPositioned,
-- which the island-dependent scripts (NestingNook_*, RedwoodRaptor) wait on so
-- their NPCs / eggs / spawns land at the NEW positions.
--======================================================================
local Workspace = game:GetService("Workspace")

-- target island CENTERS (x, y, z) -- islands 1-8 (zig-zag tower, gaps grow with height)
local POS = {
	[1] = Vector3.new(   0,  150,    0),
	[2] = Vector3.new( 120,  790,   60),
	[3] = Vector3.new(-160, 1680,  100),
	[4] = Vector3.new( 180, 2480, -120),
	[5] = Vector3.new(-200, 3580,  160),
	[6] = Vector3.new( 220, 4820, -180),
	[7] = Vector3.new(-240, 6460,  200),
	[8] = Vector3.new( 260, 8202, -220),
}

for i = 1, 8 do
	local isl = Workspace:FindFirstChild("island" .. i)
	if isl and POS[i] then
		local ok, err = pcall(function()
			local cur = isl:GetPivot()
			isl:PivotTo(CFrame.new(POS[i]) * (cur - cur.Position)) -- move to target, keep current rotation
		end)
		if ok then
			print(("[IslandLayout] island%d -> (%d, %d, %d)"):format(i, POS[i].X, POS[i].Y, POS[i].Z))
		else
			warn(("[IslandLayout] island%d move FAILED: %s"):format(i, tostring(err)))
		end
	else
		warn("[IslandLayout] island" .. i .. " not found")
	end
end

_G.islandsPositioned = true
print("[IslandLayout] islands 1-8 spaced into the tower layout.")
