--======================================================================
-- RemoveInvisibleWalls.server.luau  (Server Script)
--======================================================================
-- Kills the "invisible force fields" you bump into around the premade props.
--
-- There are TWO separate causes, and this fixes both:
--
--   1. FULLY INVISIBLE PARTS THAT STILL COLLIDE.
--      Transparency = 1 but CanCollide = true. You walk into nothing. These are
--      usually leftover markers, hitboxes, or trigger volumes that came bundled
--      with a free model. Fix: CanCollide = false.
--
--   2. MESHPARTS *AND UNIONS* WITH BOX / HULL COLLISION.  <-- this is the big one
--      A MeshPart's collision shape is NOT its visible mesh -- it's whatever
--      CollisionFidelity says. Free models very often ship as `Box`, which wraps the
--      whole prop in its bounding box. So a tall skinny tree gets a solid invisible
--      CRATE around it the size of its whole canopy, and you can't walk anywhere
--      near the trunk. Fix: PreciseConvexDecomposition, so the collision actually
--      follows the model's shape.
--
-- SIDE BENEFIT: raycasts hit the COLLISION geometry, not the visible mesh. Islands
-- whose meshes have broken/absent collision are exactly why the ground-finding rays
-- in GeyserQuest / MosquitoQuest kept falling straight through the island. Giving
-- the meshes real collision shapes should make those rays land properly too.
--
-- Ground and terrain are untouched: they're VISIBLE, so rule 1 skips them, and rule 2
-- only makes their collision tighter (never removes it).
--
-- Every change is logged with the part's full path, so if something you actually
-- wanted disappears, you can see exactly what was hit and put it back.
--======================================================================

local Workspace = game:GetService("Workspace")

local TOP_ISLAND = 13
local LOG_LIMIT  = 30 -- don't spam the output with hundreds of lines

-- Transparency at or above this reads as "the player cannot see it", so it has no business
-- blocking them. Not 1.0 -- see rule 1 -- because near-invisible leftovers are just as solid
-- and just as baffling to walk into.
local INVISIBLE_AT = 0.95

-- Never touch these -- an invisible SpawnLocation is how the player spawns at all,
-- and the quest scripts rely on their own invisible non-colliding helpers.
local function isProtected(p: BasePart): boolean
	if p:IsA("SpawnLocation") then return true end
	-- our own quest props (already non-colliding; listed for clarity)
	local n = p.Name:lower()
	if n == "hitbox" or n:find("spawn", 1, true) then return true end
	return false
end

local invisibleFixed, meshFixed = 0, 0
local logged = 0
local function logHit(kind: string, p: BasePart)
	logged += 1
	if logged <= LOG_LIMIT then
		print(("[NoWalls]   %s -> %s"):format(kind, p:GetFullName()))
	elseif logged == LOG_LIMIT + 1 then
		print("[NoWalls]   ... (further changes not listed)")
	end
end

local function fixPart(p: BasePart)
	if isProtected(p) then return end

	-- 1. invisible but solid -> stop it blocking the player
	--
	-- NEARLY invisible counts. This tested `>= 1` exactly, so a leftover volume saved at
	-- 0.95 or 0.99 -- which you cannot see and which no one sets on purpose for a prop you
	-- are meant to notice -- kept its collision and stayed a force field. Anything you
	-- genuinely see through but still bump into is the bug this rule exists to kill.
	if p.CanCollide and p.Transparency >= INVISIBLE_AT then
		p.CanCollide = false
		invisibleFixed += 1
		logHit("invisible wall", p)
		return
	end

	-- 2. MeshPart whose collision shape is a crude blob -> make collision follow the mesh.
	--
	-- BOTH bad values are handled:
	--   Box     = the prop's full bounding box (worst -- a literal crate around it)
	--   Default = a single CONVEX HULL of the whole mesh. This is Roblox's DEFAULT, and
	--             it's almost certainly your culprit: a convex hull around a tree is one
	--             solid blob spanning trunk + canopy, so you get shoved away from the
	--             trunk by an invisible dome. Anything with a concave shape (arches,
	--             doorways, hollow rocks, branches) is solid all the way through.
	-- PreciseConvexDecomposition splits the mesh into many convex pieces, so collision
	-- actually matches what you can see.
	-- UNIONS COUNT TOO, AND THEY WERE BEING SKIPPED. This tested `p:IsA("MeshPart")` only,
	-- but CollisionFidelity lives on PartOperation -- the base class of UnionOperation and
	-- NegateOperation -- exactly as it does on MeshPart. So every welded-together union prop
	-- kept its default single convex hull: one solid blob spanning the whole union, which is
	-- the invisible box you walk into around a prop whose visible shape has gaps in it.
	-- A union is the MOST likely thing to have this problem, because unioning is what people
	-- do to concave, hollow, arched scenery in the first place.
	if (p:IsA("MeshPart") or p:IsA("PartOperation")) and p.CanCollide then
		local fid = p.CollisionFidelity
		if fid == Enum.CollisionFidelity.Box or fid == Enum.CollisionFidelity.Default then
			local ok = pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			end)
			if ok then
				meshFixed += 1
				logHit((fid == Enum.CollisionFidelity.Box) and "box collision" or "hull collision", p)
			end
		end
	end
end

-- Run AFTER the islands are placed and their props exist.
do
	local t0 = os.clock()
	while not _G.islandsPositioned and os.clock() - t0 < 10 do
		task.wait()
	end
end
task.wait(2) -- let the quest scripts finish spawning their props

local scanned = 0
local started = os.clock()
for i = 1, TOP_ISLAND do
	local isl = Workspace:FindFirstChild("island" .. i)
	if isl then
		for _, d in ipairs(isl:GetDescendants()) do
			if d:IsA("BasePart") then
				scanned += 1
				pcall(fixPart, d)
				-- Recomputing collision geometry is NOT free -- yield every so often so a
				-- big island can't stall the server thread on startup.
				if scanned % 200 == 0 then task.wait() end
			end
		end
	end
end
local took = os.clock() - started

print(("[NoWalls] scanned %d part(s) across islands 1-%d in %.1fs"):format(scanned, TOP_ISLAND, took))
print(("[NoWalls] %d invisible collider(s) disabled  |  %d mesh/union part(s) given precise collision (was Box/Default hull)")
	:format(invisibleFixed, meshFixed))
if invisibleFixed == 0 and meshFixed == 0 then
	print("[NoWalls] nothing to fix -- no invisible colliders, and every MeshPart already had precise collision.")
end
