--======================================================================
-- AnchorIslands.server.luau  (Server Script)
--======================================================================
-- Anchors EVERY BasePart inside island2 .. island7 at server start, so those
-- islands stay put / never fall or drift.
--======================================================================

local Workspace = game:GetService("Workspace")

-- skip the DINOSAURS (managed elsewhere so they can move): dino1, RaptorModel, MamaRaptor
local function isDino(inst)
	return inst:FindFirstAncestor("dino1") or inst:FindFirstAncestor("RaptorModel") or inst:FindFirstAncestor("MamaRaptor")
end

local total = 0
for i = 1, 14 do
	local isl = Workspace:FindFirstChild("island" .. i)
	if isl then
		local n = 0
		if isl:IsA("BasePart") and not isDino(isl) then isl.Anchored = true; n += 1 end
		for _, d in ipairs(isl:GetDescendants()) do
			if d:IsA("BasePart") and not isDino(d) then d.Anchored = true; n += 1 end
		end
		total += n
		print(("[Anchor] island%d -> anchored %d part(s)"):format(i, n))
	end
end
print(("[Anchor] done -- %d part(s) anchored across islands 1-14 (dinosaurs skipped)"):format(total))

-- anchor any food "Stand" models (island5/6) so they never fall apart
do
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == "Stand" then
			if d:IsA("BasePart") then d.Anchored = true; n += 1 end
			for _, p in ipairs(d:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true; n += 1 end end
		end
	end
	print(("[Anchor] anchored %d 'Stand' part(s)"):format(n))
end
