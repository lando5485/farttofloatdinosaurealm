--======================================================================
-- Island1Anchor.server.luau  (Server Script)
--======================================================================
-- AnchorIslands runs ONCE at startup, but NestingNook adds the nest "miner"
-- NPC, dino1 and the eggs AFTER that. The miner has a Humanoid, so while it
-- is unanchored the player can SHOVE it off the spawn block by walking into
-- it (or by teleporting onto the island). This anchors EVERY part of island1
-- -- including the miner -- so nothing drifts, and keeps doing so for any
-- parts added later.
--
-- EXCEPTION: dino1 / RaptorModel / MamaRaptor are left FREE so they can move.
--======================================================================

local Workspace = game:GetService("Workspace")

local function isDino(inst)
	return inst:FindFirstAncestor("dino1")
		or inst:FindFirstAncestor("RaptorModel")
		or inst:FindFirstAncestor("MamaRaptor")
end

local function anchorPart(p)
	if p:IsA("BasePart") and not p.Anchored and not isDino(p) then
		p.Anchored = true
		return 1
	end
	return 0
end

local function anchorTree(root)
	if not root then
		return 0
	end
	local n = 0
	if root:IsA("BasePart") then
		n += anchorPart(root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		n += anchorPart(d)
	end
	return n
end

local function sweep()
	local n = anchorTree(Workspace:FindFirstChild("island1"))
	n += anchorTree(Workspace:FindFirstChild("miner")) -- in case the miner ever lives directly under Workspace
	return n
end

-- Initial sweep + a few delayed re-sweeps to catch the miner / eggs NestingNook
-- adds shortly after startup.
task.spawn(function()
	local total = 0
	for i = 1, 6 do
		local n = sweep()
		total += n
		if n > 0 then
			print(("[Island1Anchor] pass %d -> anchored %d more part(s)"):format(i, n))
		end
		task.wait(1)
	end
	print(("[Island1Anchor] done -- island1 + miner anchored (%d total; dino1 left free).")
		:format(total))
end)

-- Keep anchoring anything parented into island1 later (still skipping dino1).
local island1 = Workspace:WaitForChild("island1", 30)
if island1 then
	island1.DescendantAdded:Connect(function(d)
		task.defer(anchorPart, d)
	end)
end
