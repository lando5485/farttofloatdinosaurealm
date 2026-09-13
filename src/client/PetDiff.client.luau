--======================================================================
-- PetDiff.client.luau  --  THE PET DIAGNOSTIC
--======================================================================
-- WHY THIS EXISTS
--   "It looks perfect in the Pet Hub but wrong when I equip it" has survived many rounds of
--   fixes, because every fix was a guess about WHICH part was wrong. Guessing is the problem:
--   the Hub icon and the equipped follower are supposed to be clones of the same template, so
--   either they are NOT the same model -- which is a fact you can measure -- or they are the
--   same model rendered two different ways, which is a different bug entirely.
--
--   This measures it. No opinions, no rendering, no reading the builder source: it walks the
--   two ACTUAL models in memory and prints exactly where they differ.
--
-- COMMANDS  (type in chat)
--   /petdiff   -- THE IMPORTANT ONE. Compares the Hub icon against the equipped follower.
--                 Open the Pet Hub, equip the pet, then run it.
--   /petdump   -- every part of the equipped pet: class, shape, size, offset, colour, welds.
--   /pethub    -- the same dump for the Hub icon.
--   /petxray   -- ASCII side + front view of the equipped pet, drawn from its real parts.
--
-- Also available from the console as _G.petdiff() / _G.petdump() / _G.pethub() / _G.petxray().
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")
local RS              = game:GetService("ReplicatedStorage")
local PetFace         = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("PetFace"))

local player = Players.LocalPlayer

-- FX and helper parts are not geometry -- they are created per-follower and would swamp the diff.
local IGNORE = {
	PetOrb = true, PetRing = true, PetPulse = true, EvoPart = true, LevelGlow = true,
	PetSparkle = true, PetTrail = true, PetAura = true, PetAuraLight = true,
	PetBurst = true, PetRareFX = true, PetRareLight = true, PetSkinFX = true,
	NameTag = true, PetNameGui = true,
}

local function shapeOf(p)
	if p:IsA("UnionOperation") then return "UNION" end
	if p:IsA("WedgePart") then return "WEDGE" end
	if p:IsA("MeshPart") then return "MESH" end
	if p:IsA("Part") then
		local s = p.Shape
		if s == Enum.PartType.Ball then return "Ball" end
		if s == Enum.PartType.Cylinder then return "Cyl" end
		if s == Enum.PartType.Block then return "Block" end
	end
	return p.ClassName
end

--- Every geometry part of a model, keyed so the same part can be found in the other model.
--- Positions are RELATIVE TO THE MODEL'S PIVOT, so the two can be compared no matter where
--- each one happens to be standing.
local function collect(model)
	if not model then return nil end
	local pivot = model:GetPivot()
	local list, byKey = {}, {}
	local seen = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not IGNORE[d.Name] then
			seen[d.Name] = (seen[d.Name] or 0) + 1
			local key = d.Name .. "#" .. seen[d.Name]
			local rel = pivot:ToObjectSpace(d.CFrame)
			local welded = false
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("WeldConstraint") then welded = true break end
			end
			local e = {
				key = key, name = d.Name, part = d, shape = shapeOf(d),
				size = d.Size, pos = rel.Position, cf = rel,
				color = d.Color, transparency = d.Transparency,
				anchored = d.Anchored, welded = welded,
			}
			list[#list + 1] = e
			byKey[key] = e
		end
	end
	return { model = model, pivot = pivot, list = list, byKey = byKey, scale = model:GetScale() }
end

local function findFollower()
	local best
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:find("Follower") then best = m end
	end
	return best
end

--- The Hub icon lives inside a ViewportFrame named Icon3D somewhere in PlayerGui.
--- Returns the icon whose name best matches the follower, or the first one found.
local function findHubIcons()
	local out = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return out end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("ViewportFrame") then
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("Model") then out[#out + 1] = c end
			end
		end
	end
	return out
end

local function matchHubIcon(followerName)
	local icons = findHubIcons()
	if #icons == 0 then return nil, 0 end
	-- the follower is named e.g. "BrachiosaurusPetFollower"; the icon "Brachiosaurus"
	local best
	for _, m in ipairs(icons) do
		local n = m.Name:gsub("Pet$", "")
		if #n >= 4 and followerName:find(n, 1, true) then best = m end
	end
	return best or icons[1], #icons
end

local function fmtV(v) return ("(%.3f, %.3f, %.3f)"):format(v.X, v.Y, v.Z) end

local function dump(cap, tag)
	if not cap then warn("[PetDiff] nothing to dump for " .. tag); return end
	print(("[PetDiff] ===== %s : %s ====="):format(tag, cap.model.Name))
	print(("[PetDiff]   %d geometry part(s), model scale %.3f, pivot %s")
		:format(#cap.list, cap.scale, fmtV(cap.pivot.Position)))
	print("[PetDiff]   name                shape   size                     offset-from-pivot        weld  transp")
	for _, e in ipairs(cap.list) do
		print(("[PetDiff]   %-19s %-7s %-24s %-24s %-5s %.2f"):format(
			e.name:sub(1, 19), e.shape, fmtV(e.size), fmtV(e.pos),
			e.welded and "yes" or "-", e.transparency))
	end
end

--- THE DIFF. Everything else in this file exists to make this one function possible.
local function petdiff()
	local fol = findFollower()
	if not fol then
		warn("[PetDiff] no follower in Workspace -- equip a pet first."); return
	end
	local hub, iconCount = matchHubIcon(fol.Name)
	if not hub then
		warn(("[PetDiff] no Pet Hub icon found (%d viewport model(s)) -- OPEN THE PET HUB first, " ..
		      "leave it open, then run /petdiff again."):format(iconCount))
		return
	end
	local A, B = collect(hub), collect(fol)
	print("[PetDiff] ==================================================================")
	print(("[PetDiff] HUB   '%s'  ->  %d part(s), scale %.3f"):format(hub.Name, #A.list, A.scale))
	print(("[PetDiff] WORLD '%s'  ->  %d part(s), scale %.3f"):format(fol.Name, #B.list, B.scale))
	print("[PetDiff] ==================================================================")

	if #A.list ~= #B.list then
		warn(("[PetDiff] !! PART COUNT DIFFERS (%d vs %d) -- these are NOT the same model."):format(#A.list, #B.list))
	end
	if math.abs(A.scale - B.scale) > 1e-4 then
		warn(("[PetDiff] !! MODEL SCALE DIFFERS (hub %.3f vs world %.3f) -- scaling is what pulls "
			.. "small welded parts out of their sockets."):format(A.scale, B.scale))
	end

	local onlyHub, onlyWorld, differ = {}, {}, 0
	for _, e in ipairs(A.list) do
		if not B.byKey[e.key] then onlyHub[#onlyHub + 1] = e.key end
	end
	for _, e in ipairs(B.list) do
		if not A.byKey[e.key] then onlyWorld[#onlyWorld + 1] = e.key end
	end
	if #onlyHub > 0 then
		warn("[PetDiff] !! ONLY IN THE HUB (missing from the equipped pet): " .. table.concat(onlyHub, ", "))
	end
	if #onlyWorld > 0 then
		warn("[PetDiff] !! ONLY IN THE WORLD (the hub never shows these): " .. table.concat(onlyWorld, ", "))
	end

	for _, a in ipairs(A.list) do
		local b = B.byKey[a.key]
		if b then
			local dSize = (a.size - b.size).Magnitude
			local dPos  = (a.pos - b.pos).Magnitude
			local dShape = (a.shape ~= b.shape)
			if dShape or dSize > 0.002 or dPos > 0.002 then
				differ = differ + 1
				warn(("[PetDiff] !! %s DIFFERS"):format(a.key))
				if dShape then
					warn(("[PetDiff]      shape : hub=%s   world=%s"):format(a.shape, b.shape))
				end
				if dSize > 0.002 then
					warn(("[PetDiff]      size  : hub=%s  world=%s   (off by %.3f)")
						:format(fmtV(a.size), fmtV(b.size), dSize))
				end
				if dPos > 0.002 then
					warn(("[PetDiff]      offset: hub=%s  world=%s   (off by %.3f studs)")
						:format(fmtV(a.pos), fmtV(b.pos), dPos))
				end
			end
		end
	end

	print("[PetDiff] ------------------------------------------------------------------")
	if #onlyHub == 0 and #onlyWorld == 0 and differ == 0 and #A.list == #B.list then
		print("[PetDiff] VERDICT: the two models are GEOMETRICALLY IDENTICAL.")
		print("[PetDiff]   So the difference you can see is NOT geometry -- it is how they are drawn.")
		print("[PetDiff]   A ViewportFrame lights a model flatly (no shadows, no ambient occlusion),")
		print("[PetDiff]   so seams between overlapping parts vanish; the world lights it properly and")
		print("[PetDiff]   every seam shows. The fix for that is fusing, not moving parts.")
	else
		print(("[PetDiff] VERDICT: the models DIFFER -- %d part(s) changed, %d only in hub, %d only in world.")
			:format(differ, #onlyHub, #onlyWorld))
		print("[PetDiff]   Something transforms the follower after it is cloned. The lines above name it.")
	end
	print("[PetDiff] ==================================================================")
end

-- ===== ASCII view of the equipped pet, from its REAL parts =====
local function glyphFor(n)
	if n:find("Tooth") then return "T" end
	if n:find("Nostril") then return "*" end
	if n:find("Neck") then return "N" end
	if n:find("Head") then return "H" end
	if n:find("Snout") or n:find("Beak") then return "h" end
	if n:find("Dome") or n:find("Crest") then return "D" end
	if n:find("Jaw") then return "J" end
	if n:find("Mouth") or n:find("Smile") then return "m" end
	if n:find("Brow") then return "^" end
	if n:find("Claw") then return "c" end
	if n:find("Arm") or n:find("Hand") then return "a" end
	if n:find("Tail") then return "~" end
	if n:find("Belly") then return ":" end
	if n:find("Foot") or n:find("Leg") then return "L" end
	if n:find("Gill") then return "g" end
	if n:find("Plate") or n:find("Sail") then return "S" end
	if n:find("Fin") or n:find("Dorsal") then return "f" end
	if n:find("Spot") or n:find("Dapple") then return "." end
	if n:find("eye") or n:find("Eye") or n:find("Glint") then return "o" end
	if n:find("BodyUnion") then return "#" end
	return "+"
end

local function xray(cap, tag)
	if not cap or #cap.list == 0 then warn("[PetDiff] nothing to draw for " .. tag); return end
	local function insideE(e, wp)
		local lp = e.cf:PointToObjectSpace(wp)
		local hx, hy, hz = e.size.X / 2, e.size.Y / 2, e.size.Z / 2
		if hx <= 0 or hy <= 0 or hz <= 0 then return false end
		if e.shape == "Ball" then return (lp.X/hx)^2 + (lp.Y/hy)^2 + (lp.Z/hz)^2 <= 1 end
		if e.shape == "Cyl"  then return math.abs(lp.X) <= hx and (lp.Y/hy)^2 + (lp.Z/hz)^2 <= 1 end
		return math.abs(lp.X) <= hx and math.abs(lp.Y) <= hy and math.abs(lp.Z) <= hz
	end
	local COLS, ROWS = 58, 24
	print(("[PetXray] %s -- %s, %d part(s)"):format(tag, cap.model.Name, #cap.list))
	for _, view in ipairs({ "SIDE", "FRONT" }) do
		local minA, maxA, minY, maxY = 1e9, -1e9, 1e9, -1e9
		for _, e in ipairs(cap.list) do
			local r = e.size.Magnitude * 0.5
			local a = (view == "SIDE") and e.pos.X or e.pos.Z
			minA = math.min(minA, a - r); maxA = math.max(maxA, a + r)
			minY = math.min(minY, e.pos.Y - r); maxY = math.max(maxY, e.pos.Y + r)
		end
		local sa, sy = (maxA - minA) / COLS, (maxY - minY) / ROWS
		print(("[PetXray] %s VIEW (%s)"):format(view,
			view == "SIDE" and "+X right = the pet's front" or "+Z right, head on"))
		for r = 0, ROWS - 1 do
			local wy = maxY - (r + 0.5) * sy
			local line = {}
			for c = 0, COLS - 1 do
				local wa = minA + (c + 0.5) * sa
				local ch, best = " ", -1e9
				for _, e in ipairs(cap.list) do
					local wp, depth
					if view == "SIDE" then wp = Vector3.new(wa, wy, e.pos.Z); depth = e.pos.Z
					else wp = Vector3.new(e.pos.X, wy, wa); depth = e.pos.X end
					if insideE(e, wp) and depth > best then best = depth; ch = glyphFor(e.name) end
				end
				line[#line + 1] = ch
			end
			print("[PetXray] |" .. (table.concat(line):gsub("%s+$", "")))
		end
	end
end

-- ===== /petall -- EVERY PET, EVERY PART, IN ONE PASS =====
-- The point of this one is throughput. Diagnosing pets one at a time meant one restart per pet
-- and a fresh guess each round. This walks EVERY published template and reports, for each part,
-- how much of its own SURFACE is buried inside the rest of the model -- which is the number that
-- decides whether it reads as part of the animal or as an object stuck to it:
--
--   ~0%      floating: touches nothing at all
--   under 12% looks stuck on -- a bead perched on the surface
--   over 96%  invisible: fully swallowed, the work is wasted
--   12-96%   seated
--
-- Surface sampling, not volume: the question is what you can SEE, and for a rounded part the
-- volume test misses the extremities entirely (it once reported the signed-off Triceratops as
-- broken). One paste of this covers all eight pets.
local function surfaceExposure(part, others)
	local N = 64
	local hx, hy, hz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
	if hx <= 0 or hy <= 0 or hz <= 0 then return 1 end
	local shape = part:IsA("Part") and part.Shape or nil
	local ga, inside, nearBody = math.pi * (3 - math.sqrt(5)), 0, 0
	for i = 0, N - 1 do
		local y = 1 - 2 * i / (N - 1)
		local r = math.sqrt(math.max(0, 1 - y * y))
		local th = ga * i
		local dx, dy, dz = math.cos(th) * r, y, math.sin(th) * r
		local lx, ly, lz
		if shape == Enum.PartType.Ball or part:IsA("UnionOperation") then
			lx, ly, lz = hx * dx, hy * dy, hz * dz
		elseif shape == Enum.PartType.Cylinder then
			local k = math.max(math.abs(dx), math.sqrt(dy*dy + dz*dz)); if k == 0 then k = 1 end
			lx, ly, lz = hx*dx/k, hy*dy/k, hz*dz/k
		else
			local k = math.max(math.abs(dx), math.abs(dy), math.abs(dz)); if k == 0 then k = 1 end
			lx, ly, lz = hx*dx/k, hy*dy/k, hz*dz/k
		end
		local wp = part.CFrame:PointToWorldSpace(Vector3.new(lx, ly, lz) * 0.999)
		local hitPrim, hitUnion = false, false
		for _, q in ipairs(others) do
			local lp = q.CFrame:PointToObjectSpace(wp)
			local qx, qy, qz = q.Size.X/2, q.Size.Y/2, q.Size.Z/2
			local qs = q:IsA("Part") and q.Shape or nil
			local hit
			if qs == Enum.PartType.Ball then
				hit = (lp.X/qx)^2 + (lp.Y/qy)^2 + (lp.Z/qz)^2 <= 1
			elseif qs == Enum.PartType.Cylinder then
				hit = math.abs(lp.X) <= qx and (lp.Y/qy)^2 + (lp.Z/qz)^2 <= 1
			else
				hit = math.abs(lp.X) <= qx and math.abs(lp.Y) <= qy and math.abs(lp.Z) <= qz
			end
			-- A UNION'S TRUE SHAPE CANNOT BE MEASURED AT RUNTIME. It is not a Part, so it has no
			-- .Shape, and its CollisionFidelity is Box -- so physics queries would lie too. The
			-- first version of this fell through to the box branch and therefore treated the
			-- fused BodyUnion as a SOLID BLOCK of its entire bounding box. That box encloses the
			-- whole animal, so every eye, belly and mouth inside it was reported "100% buried" --
			-- which is how one run produced 136 "problems" that were almost all imaginary.
			--
			-- Union hits are now counted SEPARATELY and never called burial. What is kept is the
			-- part of the check that stays exact: a part swallowed by a PRIMITIVE really is
			-- invisible, and a part touching nothing at all -- not even a bounding box -- really
			-- is floating.
			if hit then
				if q:IsA("UnionOperation") then hitUnion = true else hitPrim = true; break end
			end
		end
		if hitPrim then inside = inside + 1
		elseif hitUnion then nearBody = nearBody + 1 end
	end
	return inside / N, nearBody / N
end

local function petall()
	local names = {}
	for _, t in ipairs(RS:GetChildren()) do
		if t:IsA("Model") and t.Name:match("Template$") then names[#names + 1] = t end
	end
	table.sort(names, function(a, b) return a.Name < b.Name end)
	if #names == 0 then warn("[PetAll] no *Template models in ReplicatedStorage"); return end
	print("[PetAll] ================ ALL PETS, ALL PARTS ================")
	print("[PetAll] Reports only what can be measured EXACTLY: parts touching nothing, and parts")
	print("[PetAll] swallowed by another solid part. A fused union's true surface is not knowable")
	print("[PetAll] at runtime, so \"is this buried in the body\" is deliberately NOT guessed at.")
	local totalBad = 0
	for _, tmpl in ipairs(names) do
		local parts = {}
		for _, d in ipairs(tmpl:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" and not IGNORE[d.Name] then
				parts[#parts + 1] = d
			end
		end
		local unions = 0
		for _, d in ipairs(parts) do if d:IsA("UnionOperation") then unions = unions + 1 end end
		local bad = 0
		local lines = {}
		for _, d in ipairs(parts) do
			local others = {}
			for _, q in ipairs(parts) do if q ~= d then others[#others + 1] = q end end
			local emb, nearBody = surfaceExposure(d, others)
			local verdict
			-- ONLY THE TWO CHECKS THAT ARE EXACT. Anything needing a union's real surface is
			-- skipped rather than guessed at -- see the note inside surfaceExposure.
			if d:IsA("UnionOperation") then
				-- this IS the body; "how buried is the body" is not a meaningful question
			elseif emb + nearBody <= 0.001 then
				verdict = "FLOATING -- touches nothing at all"
			elseif emb > 0.99 then
				verdict = "INVISIBLE -- fully inside another solid part"
			end
			if verdict then
				bad = bad + 1
				lines[#lines + 1] = ("[PetAll]    %-14s %s"):format(d.Name, verdict)
			end
		end
		totalBad = totalBad + bad
		print(("[PetAll] %-18s %2d part(s), %d union(s)  ->  %s"):format(
			tmpl.Name:gsub("Template$", ""), #parts, unions,
			bad == 0 and "all seated" or (bad .. " PROBLEM(S)")))
		for _, l in ipairs(lines) do print(l) end
	end
	print(("[PetAll] ================ %d problem(s) across %d pet(s) ================")
		:format(totalBad, #names))
end

-- ===== /petprobe -- THE ONE THAT ACTUALLY MEASURES A UNION =====
--
-- Every previous check in this file guessed at a UnionOperation's shape, because a union has no
-- .Shape to test against. Guessing gave a false "everything is buried" in one direction and a
-- false "everything is fine" in the other, and neither could see a part that had gone MISSING.
--
-- Roblox will answer the question exactly if asked properly. Workspace:GetPartsInPart() tests
-- real COLLISION geometry, and a union's collision geometry becomes its true shape once
-- CollisionFidelity is PreciseConvexDecomposition. So: clone the template somewhere harmless,
-- switch the unions to precise collision, and walk a tiny probe part over every other part's
-- surface. Whatever the engine says overlaps the probe is what is genuinely there.
--
-- It also prints the FULL ROSTER of every pet, because "the shark has no dorsal fin" is not a
-- geometry question at all -- it is a question of whether the part exists, and nothing here was
-- reporting that.
local function petprobe()
	local names = {}
	for _, t in ipairs(RS:GetChildren()) do
		if t:IsA("Model") and t.Name:match("Template$") then
			-- dinosaurs only; the food pets are a separate set and would triple the log
			local n = t.Name
			if n:match("^Stego") or n:match("^Veloci") or n:match("^Shark") or n:match("^Spino")
				or n:match("^Trice") or n:match("^Tyranno") or n:match("^Theri") or n:match("^Brachio") then
				names[#names + 1] = t
			end
		end
	end
	table.sort(names, function(a, b) return a.Name < b.Name end)
	if #names == 0 then warn("[PetProbe] no dinosaur templates found"); return end

	local holder = Instance.new("Folder"); holder.Name = "PetProbeScratch"; holder.Parent = Workspace
	local probe = Instance.new("Part")
	probe.Name = "Probe"; probe.Shape = Enum.PartType.Ball; probe.Size = Vector3.new(0.06, 0.06, 0.06)
	probe.Anchored = true; probe.CanCollide = false; probe.CanTouch = false; probe.CanQuery = true
	probe.Transparency = 1; probe.Parent = holder

	print("[PetProbe] ============ EXACT SCAN (union-aware, via collision geometry) ============")
	for _, tmpl in ipairs(names) do
		local m = tmpl:Clone()
		m.Parent = holder
		pcall(function() m:PivotTo(CFrame.new(0, 20000, 0)) end)   -- far from anything else

		local parts, roster = {}, {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" and not IGNORE[d.Name] then
				parts[#parts + 1] = d
				d.CanQuery = true
				if d:IsA("UnionOperation") then
					pcall(function() d.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition end)
				end
				roster[#roster + 1] = ("%s[%s %.2fx%.2fx%.2f]"):format(
					d.Name, d:IsA("UnionOperation") and "UNION" or "part", d.Size.X, d.Size.Y, d.Size.Z)
			end
		end
		task.wait()   -- let the precise collision meshes generate

		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = parts
		params.MaxParts = 8

		print(("[PetProbe] ---- %s : %d part(s) ----"):format(tmpl.Name:gsub("Template$", ""), #parts))
		print("[PetProbe]   roster: " .. table.concat(roster, ", "))

		local N, ga = 40, math.pi * (3 - math.sqrt(5))
		for _, d in ipairs(parts) do
			if not d:IsA("UnionOperation") then
				local hx, hy, hz = d.Size.X/2, d.Size.Y/2, d.Size.Z/2
				local covered, total = 0, 0
				for i = 0, N - 1 do
					local y = 1 - 2 * i / (N - 1)
					local r = math.sqrt(math.max(0, 1 - y*y))
					local th = ga * i
					local dx, dy, dz = math.cos(th) * r, y, math.sin(th) * r
					local k = 1
					if d:IsA("Part") and d.Shape == Enum.PartType.Block then
						k = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
					elseif d:IsA("Part") and d.Shape == Enum.PartType.Cylinder then
						k = math.max(math.abs(dx), math.sqrt(dy*dy + dz*dz))
					end
					if k == 0 then k = 1 end
					local lp = Vector3.new(hx*dx/k, hy*dy/k, hz*dz/k) * 1.02  -- just OUTSIDE the surface
					probe.CFrame = CFrame.new(d.CFrame:PointToWorldSpace(lp))
					total = total + 1
					for _, hit in ipairs(Workspace:GetPartsInPart(probe, params)) do
						if hit ~= d then covered = covered + 1; break end
					end
				end
				local exposed = 1 - covered / math.max(1, total)
				if covered == 0 then
					warn(("[PetProbe]   %-15s FLOATING -- nothing touches it anywhere"):format(d.Name))
				-- CAVEAT: PreciseConvexDecomposition fills concavities, so a union's collision hull
				-- is FATTER than the real model -- it spans the gap between legs, under a chin, in
				-- front of a face. A part reported INVISIBLE may simply be sitting in one of those
				-- filled-in hollows. Treat this verdict as "worth a look", not as proof; the ROSTER
				-- above and the union's measured SIZE are the parts of this report that cannot lie.
				elseif exposed <= 0.02 then
					warn(("[PetProbe]   %-15s INVISIBLE -- %.0f%% of its surface is inside something else"):format(d.Name, 100 - exposed*100))
				elseif covered / total < 0.10 then
					warn(("[PetProbe]   %-15s BARELY ON -- only %.0f%% of it is in contact"):format(d.Name, covered/total*100))
				end
			end
		end
		m:Destroy()
	end
	holder:Destroy()
	print("[PetProbe] ============ done ============")
end

-- ===== /petfull -- EVERY PROPERTY OF EVERY PART OF EVERY PET, IN ONE COMMAND =====
--
-- This exists so the "what is wrong with this pet" question never has to be asked twice. Each of
-- the earlier commands answered one narrow question and needed another restart to ask the next.
-- This one dumps EVERYTHING that could possibly explain a visual difference, for all three copies
-- of every pet -- the published TEMPLATE, the Pet Hub ICON, and the equipped FOLLOWER -- so the
-- template/hub/world comparison can be made from a single paste.
--
-- One pipe-delimited line per part. Fields, in order:
--   source | pet | part | class | shape | sizeXYZ | posXYZ (relative to the model pivot)
--          | rotXYZ in degrees | colour RGB | transparency | material | reflectance
--          | anchored | canCollide | weldedTo | unionExtras
--
-- Position is measured from the model's own pivot, so the three copies are directly comparable no
-- matter where each is standing. Rotation is included because a Ball that is BOTH stretched and
-- rotated is destroyed by CSG -- that one fact caused most of this project's pet bugs, and it is
-- invisible unless you print the rotation.
local function fullDump()
	local function pctf(v) return ("%.3f"):format(v) end
	local function line(src, pet, d, pivot)
		local rel = pivot:ToObjectSpace(d.CFrame)
		local rx, ry, rz = rel:ToEulerAnglesXYZ()
		local shape = "-"
		if d:IsA("Part") then
			local sm = { [Enum.PartType.Ball] = "Ball", [Enum.PartType.Block] = "Block",
			             [Enum.PartType.Cylinder] = "Cyl", [Enum.PartType.Wedge] = "Wedge",
			             [Enum.PartType.CornerWedge] = "CWedge" }
			shape = sm[d.Shape] or tostring(d.Shape)
		end
		local weld = "-"
		for _, c in ipairs(d:GetChildren()) do
			if c:IsA("WeldConstraint") then
				weld = (c.Part0 and c.Part0.Name or "?") .. ">" .. (c.Part1 and c.Part1.Name or "?")
				break
			end
		end
		local extra = ""
		if d:IsA("UnionOperation") then
			extra = ("|UPC=%s,RF=%s,CF=%s"):format(tostring(d.UsePartColor),
				tostring(d.RenderFidelity):gsub("Enum.RenderFidelity.", ""),
				tostring(d.CollisionFidelity):gsub("Enum.CollisionFidelity.", ""))
		end
		return ("[Full] %s|%s|%s|%s|%s|%s,%s,%s|%s,%s,%s|%.1f,%.1f,%.1f|%d,%d,%d|%.2f|%s|%.2f|%s|%s|%s%s")
			:format(src, pet, d.Name, d.ClassName, shape,
				pctf(d.Size.X), pctf(d.Size.Y), pctf(d.Size.Z),
				pctf(rel.Position.X), pctf(rel.Position.Y), pctf(rel.Position.Z),
				math.deg(rx), math.deg(ry), math.deg(rz),
				math.floor(d.Color.R*255+0.5), math.floor(d.Color.G*255+0.5), math.floor(d.Color.B*255+0.5),
				d.Transparency, tostring(d.Material):gsub("Enum.Material.", ""), d.Reflectance,
				tostring(d.Anchored), tostring(d.CanCollide), weld, extra)
	end

	-- Every part that gets printed is ALSO kept here, so the TEMPLATE-vs-WORLD comparison at the end
	-- is made by code rather than by reading three hundred lines side by side. That eyeballing step
	-- is where this has gone wrong before: TEMPLATE and HUB came out byte-identical and I still had
	-- to scan for it. CAP[source][pet] = { record, ... }
	local CAP = { TEMPLATE = {}, HUB = {}, WORLD = {} }
	local SEATREP = {}   -- pet -> raycast surface-contact rows, taken off the live WORLD copy
	local function record(src, pet, d, pivot)
		local bucket = CAP[src]; if not bucket then return end
		local rel = pivot:ToObjectSpace(d.CFrame)
		local rx, ry, rz = rel:ToEulerAnglesXYZ()
		bucket[pet] = bucket[pet] or {}
		local t = bucket[pet]
		t[#t + 1] = {
			name = d.Name, class = d.ClassName, size = d.Size, pos = rel.Position, cf = rel,
			rot = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz)),
			rgb = ("%d,%d,%d"):format(math.floor(d.Color.R * 255 + 0.5),
				math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5)),
			transp = d.Transparency, mat = tostring(d.Material),
			union = d:IsA("UnionOperation") and ("UPC=" .. tostring(d.UsePartColor)) or "",
		}
	end

	local function dumpModel(src, pet, m)
		if not m then return 0 end
		local pivot = m:GetPivot()
		local n = 0
		local _, bb = m:GetBoundingBox()
		print(("[Full] == %s | %s | pivot %s,%s,%s | scale %.3f | bbox %s,%s,%s")
			:format(src, pet, pctf(pivot.Position.X), pctf(pivot.Position.Y), pctf(pivot.Position.Z),
				m:GetScale(), pctf(bb.X), pctf(bb.Y), pctf(bb.Z)))
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and not IGNORE[d.Name] then
				n = n + 1
				record(src, pet, d, pivot)
				print(line(src, pet, d, pivot))
			end
		end
		print(("[Full] == %s | %s | %d part(s)"):format(src, pet, n))
		return n
	end

	print("[Full] ################ COMPLETE PET DUMP ################")
	print("[Full] fields: source|pet|part|class|shape|size|pos-from-pivot|rot-deg|rgb|transp|material|refl|anchored|collide|weld|unionExtras")

	-- 1. every published template
	local tmpls = {}
	for _, t in ipairs(RS:GetChildren()) do
		local n = t.Name
		if t:IsA("Model") and n:match("Template$") and (n:match("^Stego") or n:match("^Veloci")
			or n:match("^Shark") or n:match("^Spino") or n:match("^Trice") or n:match("^Tyranno")
			or n:match("^Theri") or n:match("^Brachio")) then tmpls[#tmpls + 1] = t end
	end
	table.sort(tmpls, function(a, b) return a.Name < b.Name end)
	for _, t in ipairs(tmpls) do dumpModel("TEMPLATE", t.Name:gsub("Template$", ""), t) end

	-- 2. every Pet Hub icon currently built
	for _, m in ipairs(findHubIcons()) do dumpModel("HUB", m.Name, m) end

	-- 3. THE WORLD COPY OF EVERY PET -- captured automatically.
	--
	-- This step used to say "equip one and re-run" and then print nothing, which is how the world
	-- copy -- the ONLY copy anyone has ever complained about -- went un-measured through every round
	-- of this. Nothing needs to be owned or equipped by hand now: each follower is spawned through
	-- the same _G.Spawn*Follower hook the Pet Hub's equip path uses, dumped, then replaced by the
	-- next one. Whatever was equipped beforehand is put back at the end.
	local SPAWNERS = {
		{ "Brachiosaurus",   "SpawnBrachiosaurusFollower",   "BrachiosaurusFollower" },
		{ "Shark",           "SpawnSharkFollower",           "SharkFollower" },
		{ "Spinosaurus",     "SpawnSpinosaurusFollower",     "SpinosaurusFollower" },
		{ "Stegosaurus",     "SpawnStegoFollower",           "StegoFollower" },
		{ "Therizinosaurus", "SpawnTherizinosaurusFollower", "TherizinosaurusFollower" },
		{ "Triceratops",     "SpawnTriceratopsFollower",     "TriceratopsFollower" },
		{ "Tyrannosaurus",   "SpawnTyrannosaurusFollower",   "TyrannosaurusFollower" },
		{ "Velociraptor",    "SpawnRaptorFollower",          "RaptorFollower" },
	}
	local restore
	do
		local had = findFollower()
		if had then
			for _, s in ipairs(SPAWNERS) do
				if had.Name == s[3] or had.Name:sub(1, #s[1]) == s[1] then restore = s[2] end
			end
		end
	end
	for _, s in ipairs(SPAWNERS) do
		local fn = rawget(_G, s[2])
		if type(fn) ~= "function" then
			print(("[Full] WORLD %s -- SKIPPED, _G.%s is missing (did PetFollow load?)"):format(s[1], s[2]))
		else
			local ok, err = pcall(fn)
			if not ok then
				print(("[Full] WORLD %s -- SPAWN FAILED: %s"):format(s[1], tostring(err)))
			else
				task.wait(0.4)   -- applyLevelVisual (ScaleTo), captureFeet and applyBlink all run first
				local fol = findFollower()
				if fol then
					dumpModel("WORLD", s[1], fol)
					SEATREP[s[1]] = PetFace.seatReport(fol)
				else
					print(("[Full] WORLD %s -- spawned, but no follower turned up in Workspace"):format(s[1]))
				end
			end
		end
	end
	if restore and type(rawget(_G, restore)) == "function" then
		pcall(rawget(_G, restore))
	else
		local leftover = findFollower()
		if leftover then pcall(function() leftover:Destroy() end) end
		print("[Full] (nothing was equipped when this started -- the last test follower has been removed)")
	end

	-- 4. THE ACTUAL ANSWER: what the spawn path changes.
	--
	-- Parts are matched by name, and repeated names (two eyes, four feet) are paired by sorted
	-- position -- the clone keeps the template's layout, so position is a stable identity. Anything
	-- that moved, resized, rotated, recoloured, appeared or vanished between the published template
	-- and the model the player actually sees is listed here and nowhere else.
	print("[Full] ---------------- TEMPLATE vs WORLD ----------------")
	local NEAR, totalDiffs = 0.005, 0
	local function group(list)
		local g = {}
		for _, r in ipairs(list) do g[r.name] = g[r.name] or {}; table.insert(g[r.name], r) end
		for _, arr in pairs(g) do
			table.sort(arr, function(a, b)
				if math.abs(a.pos.X - b.pos.X) > 1e-4 then return a.pos.X < b.pos.X end
				if math.abs(a.pos.Y - b.pos.Y) > 1e-4 then return a.pos.Y < b.pos.Y end
				return a.pos.Z < b.pos.Z
			end)
		end
		return g
	end
	for _, s in ipairs(SPAWNERS) do
		local pet = s[1]
		local T, W = CAP.TEMPLATE[pet], CAP.WORLD[pet]
		if not (T and W) then
			print(("[Full] %-16s cannot compare -- %s"):format(pet, (not T) and "no TEMPLATE dump" or "no WORLD dump"))
		else
			local gt, gw, msgs = group(T), group(W), {}
			for name, arr in pairs(gt) do
				local other = gw[name]
				if not other then
					msgs[#msgs + 1] = ("GONE IN WORLD  %s x%d"):format(name, #arr)
				elseif #other ~= #arr then
					msgs[#msgs + 1] = ("COUNT          %s: template %d -> world %d"):format(name, #arr, #other)
				end
			end
			for name, arr in pairs(gw) do
				if not gt[name] then msgs[#msgs + 1] = ("EXTRA IN WORLD %s x%d"):format(name, #arr) end
			end
			for name, arr in pairs(gt) do
				local other = gw[name]
				for i = 1, (other and math.min(#arr, #other) or 0) do
					local a, b = arr[i], other[i]
					if (a.size - b.size).Magnitude > NEAR then
						msgs[#msgs + 1] = ("SIZE           %s[%d] %.3f,%.3f,%.3f -> %.3f,%.3f,%.3f")
							:format(name, i, a.size.X, a.size.Y, a.size.Z, b.size.X, b.size.Y, b.size.Z)
					end
					if (a.pos - b.pos).Magnitude > NEAR then
						msgs[#msgs + 1] = ("POS            %s[%d] %.3f,%.3f,%.3f -> %.3f,%.3f,%.3f  (moved %.3f)")
							:format(name, i, a.pos.X, a.pos.Y, a.pos.Z, b.pos.X, b.pos.Y, b.pos.Z, (a.pos - b.pos).Magnitude)
					end
					if (a.rot - b.rot).Magnitude > 0.5 then
						msgs[#msgs + 1] = ("ROT            %s[%d] %.1f,%.1f,%.1f -> %.1f,%.1f,%.1f")
							:format(name, i, a.rot.X, a.rot.Y, a.rot.Z, b.rot.X, b.rot.Y, b.rot.Z)
					end
					if a.rgb ~= b.rgb then
						msgs[#msgs + 1] = ("COLOUR         %s[%d] %s -> %s"):format(name, i, a.rgb, b.rgb)
					end
					if math.abs(a.transp - b.transp) > 0.01 then
						msgs[#msgs + 1] = ("TRANSPARENCY   %s[%d] %.2f -> %.2f"):format(name, i, a.transp, b.transp)
					end
					if a.mat ~= b.mat then
						msgs[#msgs + 1] = ("MATERIAL       %s[%d] %s -> %s"):format(name, i,
							a.mat:gsub("Enum.Material.", ""), b.mat:gsub("Enum.Material.", ""))
					end
					if a.union ~= b.union then
						msgs[#msgs + 1] = ("UNION FLAGS    %s[%d] %s -> %s"):format(name, i, a.union, b.union)
					end
				end
			end
			if #msgs == 0 then
				print(("[Full] %-16s IDENTICAL -- the world copy matches the template exactly"):format(pet))
			else
				table.sort(msgs)
				print(("[Full] %-16s %d DIFFERENCE(S):"):format(pet, #msgs))
				for _, m in ipairs(msgs) do print("[Full]     " .. m); totalDiffs = totalDiffs + 1 end
			end
		end
	end
	print(("[Full] ---------------- %d difference(s) in total ----------------"):format(totalDiffs))

	-- 5. SURFACE CONTACT, MEASURED WITH RAYCASTS AGAINST THE REAL BODY.
	--
	-- The previous version of this section compared bounding boxes, and it cried wolf on its very
	-- first run: it flagged the signed-off Triceratops frill and every eye on every pet as
	-- "buried", because the union's box includes the snout and horns, so anything sitting on a
	-- face measures as inside it. This version asks the engine instead: a ray from outside the
	-- pet, straight through each welded feature, at the actual finished union (the same
	-- measurement PetFace.seatWelded uses at build time to place these parts). gap > 0 is provably
	-- floating; buried > 0 is provably invisible; everything fused is part of the body solid and
	-- cannot do either.
	print("[Full] ---------------- SURFACE CONTACT (raycast vs the real body) ----------------")
	for _, s in ipairs(SPAWNERS) do
		local rows = SEATREP[s[1]]
		if not rows then
			print(("[Full] %-16s not measured (world copy never spawned)"):format(s[1]))
		else
			local bad = {}
			for _, r in ipairs(rows) do
				if r.nohit then
					bad[#bad + 1] = r.name .. "  (ray missed the body entirely -- feature is far off it)"
				elseif r.gap > 0.06 then
					bad[#bad + 1] = ("%s  FLOATING %.2f studs clear of the surface"):format(r.name, r.gap)
				elseif r.buried > 0.02 then
					bad[#bad + 1] = ("%s  BURIED %.2f studs under the surface"):format(r.name, r.buried)
				end
			end
			if #bad == 0 then
				print(("[Full] %-16s all %d welded feature(s) sit on the surface; the rest is one fused solid")
					:format(s[1], #rows))
			else
				table.sort(bad)
				print(("[Full] %-16s %d problem(s):"):format(s[1], #bad))
				for _, m in ipairs(bad) do print("[Full]     " .. m) end
			end
		end
	end
	print("[Full] ################ END ################")
end

-- fullDump now YIELDS (it spawns each follower in turn and waits for it to settle), so it always
-- runs on its own thread -- never inline in a signal handler.
_G.petfull = function() task.spawn(fullDump) end
_G.petprobe = petprobe
_G.petall = petall
_G.petdiff = petdiff
_G.petdump = function() dump(collect(findFollower()), "EQUIPPED (world)") end
_G.pethub  = function()
	local fol = findFollower()
	local hub = matchHubIcon(fol and fol.Name or "")
	dump(collect(hub), "PET HUB icon")
end
_G.petxray = function() xray(collect(findFollower()), "EQUIPPED (world)") end

TextChatService.SendingMessage:Connect(function(message)
	local t = tostring(message.Text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if     t == "/petdiff" then petdiff()
	elseif t == "/petdump" then _G.petdump()
	elseif t == "/pethub"  then _G.pethub()
	elseif t == "/petxray" then _G.petxray()
	elseif t == "/petall"  then petall()
	elseif t == "/petprobe" then petprobe()
	elseif t == "/petfull" then task.spawn(fullDump) end
end)

print("[PetDiff] ready -- just type /petfull in chat. Nothing needs to be owned or equipped.")
print("[PetDiff]   /petfull  = EVERY property of EVERY part of EVERY pet, in all THREE copies")
print("[PetDiff]               (template + hub icon + the equipped world model, all 8 spawned for you),")
print("[PetDiff]               then a TEMPLATE vs WORLD difference list at the end. PASTE THIS.")
print("[PetDiff]   /petprobe = exact union-aware contact scan + roster")
print("[PetDiff]   /petall /petdiff /petdump /pethub /petxray = older, union-blind checks")
