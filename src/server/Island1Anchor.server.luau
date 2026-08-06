--======================================================================
-- Island1Anchor.server.luau  (Server Script)
--======================================================================
-- ANCHOR EVERYTHING ON ISLAND 1.
--
-- AnchorIslands runs once at startup, but NestingNook adds the miner NPC, dino1 and the
-- LostEggs AFTER that -- so island1 needs its own, more persistent sweep.
--
-- THIS USED TO SKIP ALL OF dino1 ("left free so it can move"). That was too blunt: the
-- Mama Dino is a rig, and only SOME of her parts are driven. Every other part of her was
-- left unanchored with nothing holding it, free to sag, drift or fall off the island.
--
-- The rule now is precise:
--
--   ANCHOR everything on island1 -- including dino1's body, the miner, the eggs, props.
--   EXCEPT parts that are the DRIVEN side of a weld (a WeldConstraint/Weld/Motor6D's
--   Part1). Those are held in place BY the weld, and NestingNook_NPCs' setupDinoIdle
--   animates them by driving the anchored root's CFrame. Anchor them and they stop
--   following the root -- the head, tail and blink animations freeze solid.
--
-- Net effect: nothing on island1 can fall or drift, and the dinosaur still moves.
--
-- The LostEggs are also swept even though NestingNook_Setup parents them to WORKSPACE,
-- not to island1 -- a subtree-only sweep would miss them entirely.
--======================================================================

local Workspace = game:GetService("Workspace")

-- Build the set of parts that a weld is DRIVING. Anchoring any of these breaks the rig.
-- Rebuilt per sweep, since the rigs are welded together a second or two after startup.
local function weldedParts(): { [BasePart]: boolean }
	local welded = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
			if d.Part1 then welded[d.Part1] = true end
		end
	end
	return welded
end

local function anchorPart(p: Instance, welded: { [BasePart]: boolean }): number
	if not p:IsA("BasePart") then return 0 end
	if p.Anchored then return 0 end
	if welded[p] then return 0 end                             -- the weld holds it; anchoring breaks the animation
	if p:FindFirstAncestorWhichIsA("Tool") then return 0 end   -- a tool must stay loose to weld to a hand
	if p:FindFirstAncestorWhichIsA("Accessory") then return 0 end
	p.Anchored = true
	return 1
end

local function anchorTree(root: Instance?, welded): number
	if not root then return 0 end
	local n = 0
	if root:IsA("BasePart") then n += anchorPart(root, welded) end
	for _, d in ipairs(root:GetDescendants()) do
		n += anchorPart(d, welded)
	end
	return n
end

local function sweep(): number
	local welded = weldedParts()
	local n = anchorTree(Workspace:FindFirstChild("island1"), welded)
	n += anchorTree(Workspace:FindFirstChild("miner"), welded) -- if the miner ever lives directly under Workspace

	-- LostEggs are parented to WORKSPACE (see NestingNook_Setup), not to island1, so an
	-- island1-only sweep never touches them.
	for _, d in ipairs(Workspace:GetChildren()) do
		if d.Name == "LostEgg" then
			n += anchorTree(d, welded)
		end
	end
	return n
end

-- Initial sweep + delayed re-sweeps: NestingNook adds the miner / dino1 / eggs a beat
-- after startup, and the dino rigs weld themselves together a second or two later still.
task.spawn(function()
	local total = 0
	for i = 1, 10 do
		local n = sweep()
		total += n
		if n > 0 then
			print(("[Island1Anchor] pass %d -> anchored %d more part(s)"):format(i, n))
		end
		task.wait(1)
	end
	print(("[Island1Anchor] done -- EVERYTHING on island1 anchored (%d total). "
		.. "Only weld-driven rig parts left free, so dino1 still animates.")
		:format(total))
end)

-- Keep anchoring anything parented into island1 later.
local island1 = Workspace:WaitForChild("island1", 30)
if island1 then
	island1.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") then return end
		-- defer: give any weld that's about to be created a chance to exist first, so we
		-- don't anchor a rig part a frame before its weld shows up.
		task.delay(0.5, function()
			if d.Parent then
				anchorPart(d, weldedParts())
			end
		end)
	end)
end
