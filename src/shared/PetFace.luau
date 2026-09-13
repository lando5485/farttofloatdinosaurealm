--======================================================================
-- PetFace.luau -- ONE face shared by every dinosaur pet.
--======================================================================
-- WHY THIS EXISTS
--   Every pet used to hand-code its own eyes and teeth. Six copies of the
--   same idea with slightly different numbers, so the faces drifted apart
--   and every tweak meant six separate edits (and six chances to get one
--   wrong). That is why fixing the look kept taking round after round.
--
--   Now there is exactly one face. To change how ALL SIX pets look, edit
--   the TUNING table below -- nothing else. Bigger eyes, closer together,
--   smaller fangs: one number, one place, every pet updates together.
--
-- THE CUTE RULE
--   Big eyes set CLOSE together is what reads as cute. The triceratops was
--   the pet that looked right, so its proportions are the defaults here.
--======================================================================

local PetFace = {}

PetFace.TUNING = {
	EYE_DIA   = 0.98,  -- white eyeball diameter        -- bigger = cuter
	EYE_GAP   = 0.44,  -- +/- Z from centre             -- smaller = closer together = cuter
	IRIS_DIA  = 0.66,  -- coloured iris ring (only drawn if the pet passes one)
	PUPIL_DIA = 0.54,  -- dark pupil
	GLINT_DIA = 0.21,  -- white highlight dot
	EYE_STEP  = 0.06,  -- how far each layer sits proud of the one behind it
	GLINT_UP  = 0.13,  -- glint offset up/across, kept inside the pupil disc
	GLINT_OVER= 0.09,
	FANG_W    = 0.15,  -- fangs are deliberately SMALL and few. Long rows of
	FANG_H    = 0.22,  -- triangles read as menacing, not cute -- and the pets
	FANG_GAP  = 0.17,  -- that already looked right had no tooth rows at all.
}

local BLK = Enum.PartType.Block

local CYL = Enum.PartType.Cylinder
local BAL = Enum.PartType.Ball

--- Standard flat-disc eye pair: white -> optional iris -> pupil -> glint,
--- each layer sitting slightly proud of the last so it never sinks into the face.
--- o = { P, weld, body, x, y, white, dark, iris? }
---   x = the face surface the eyes sit on, y = eye height.
function PetFace.eyes(o)
	local T = PetFace.TUNING
	local k    = o.scale or 1        -- whole-eye size (the megalodon wears them smaller)
	local step = o.step  or T.EYE_STEP -- layer stack-out; smaller = flatter, painted-on eyes
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = T.EYE_GAP * sgn
		o.weld(o.P("whitepartofeye", CYL, 0.20, T.EYE_DIA * k, T.EYE_DIA * k, o.white,
			o.x, o.y, zc), o.body)
		if o.iris then
			o.weld(o.P("EyeAmber", CYL, 0.22, T.IRIS_DIA * k, T.IRIS_DIA * k, o.iris,
				o.x + step, o.y - 0.01, zc), o.body)
		end
		o.weld(o.P("blackpartofeye", CYL, 0.26, T.PUPIL_DIA * k, T.PUPIL_DIA * k, o.dark,
			o.x + step * 2, o.y - 0.02, zc), o.body)
		o.weld(o.P("Glint", CYL, 0.12, T.GLINT_DIA * k, T.GLINT_DIA * k, o.white,
			o.x + step * 3.7, o.y + T.GLINT_UP * k, zc + T.GLINT_OVER * k), o.body)
	end
end

--- Two small SQUARE fangs. Replaces the old per-pet rows of triangular
--- WedgeParts, which never lined up and read as a sawblade.
---
--- SQUARE (Block), NOT ROUND (Ball). A Ball tooth is an ellipsoid, and an ellipsoid seated
--- into a mouth meets it along a curve -- so its widest point sits proud of the mouth surface
--- while its base has already vanished inside, and the eye reads the visible sliver as a
--- separate object hovering in front of the face. A Block has flat sides that pass straight
--- through the mouth surface, so the part you can see is plainly the top of a tooth that
--- continues into the gum. Square teeth also just read as teeth at pet scale.
---
--- SEATING IS THE CALLER'S JOB AND IT IS EASY TO GET WRONG: x must straddle the mouth part's
--- surface. Too far in and the tooth is swallowed by the (opaque) mouth; too far out and it
--- floats in front of the face with a visible gap. PetFace.audit() below checks this.
--- o = { P, weld, body, x, y, color, scale? }
--- Pass `mouth` (the mouth Part) and `unscale` (the builder's model scale `s`) and the teeth
--- SEAT THEMSELVES on the mouth's surface -- no hand-computed x/y. This is the whole reason
--- teeth kept ending up wrong: seating a tooth on an ELLIPSOID means solving the ellipsoid for
--- the surface at that tooth's own y and z, and a hand-picked x that looks right for the middle
--- tooth is already inside or outside the mouth for the one beside it. Doing it in code makes
--- every tooth land exactly half-in/half-out: guaranteed visible, guaranteed touching.
function PetFace.fangs(o)
	local T = PetFace.TUNING
	local s = o.scale or 1
	local w, h = T.FANG_W * s, T.FANG_H * s
	for _, sgn in ipairs({ 1, -1 }) do
		local dz = T.FANG_GAP * s * sgn
		local x, y, z
		if o.mouth then
			-- the mouth Part was created through the builder's scaled P(), so its Position/Size
			-- are already multiplied by the model scale. Undo that here, because the P() we are
			-- about to call will apply it again.
			local sc  = o.unscale or 1
			local pos = o.mouth.Position / sc
			local sz  = o.mouth.Size / sc
			local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
			local dy = o.dy or 0
			local isBall = (o.mouth.Shape == BAL)
			if isBall then
				-- ellipsoid mouth: solve for the front (+X) surface at this tooth's own y and z
				local ky = (hy > 0) and (dy / hy) ^ 2 or 0
				local kz = (hz > 0) and (dz / hz) ^ 2 or 0
				local k  = math.max(1 - ky - kz, 0.04)
				x = pos.X + hx * math.sqrt(k)
				y = pos.Y + dy
			else
				-- flat "mouth line" block: straddle the TOP face for an upper row (dy >= 0) and
				-- the BOTTOM face for a lower row, keeping the caller's x along the jaw.
				x = o.x or pos.X
				y = pos.Y + ((dy >= 0) and hy or -hy)
			end
			z = pos.Z + dz
		else
			x, y, z = o.x, o.y, dz
		end
		-- WELD THE TOOTH TO THE MOUTH, not to the body union. A tooth is part of the mouth, and
		-- welding it to the thing it visually belongs to means it cannot be left behind if the
		-- body is rebuilt, and makes "is this tooth attached?" a question about two small parts
		-- whose exact shapes are known -- instead of about a union nobody can measure.
		o.weld(o.P("Tooth", BLK, w, h, w, o.color, x, y, z), o.mouth or o.body)
	end
end

--- GUARANTEE THE MODEL HAS A "Root" PrimaryPart. Call at the END of every builder.
---
--- The live log caught the Brachiosaurus shipping without one: "clone has NO 'Root' part". Every
--- builder creates its Root FIRST, before the body union -- an invisible 0.4 ball sitting at
--- (0,0,0), dead centre inside the very cube that UnionAsync then consumes. Making it again at
--- the end puts it out of CSG's reach.
---
--- It is not a cosmetic loss. With no PrimaryPart, Model:GetPivot() falls back to the BOUNDING-BOX
--- CENTRE, so a pet with a tall neck or a long tail pivots around a point that is not its body --
--- and PetFollow then turns it about that point, which reads as the model swinging wrongly.
function PetFace.ensureRoot(model)
	if not model then return end
	local root = model:FindFirstChild("Root")
	if not root then
		root = Instance.new("Part")
		root.Name = "Root"; root.Shape = BAL; root.Size = Vector3.new(0.4, 0.4, 0.4)
		root.Transparency = 1; root.Anchored = true; root.CanCollide = false
		root.CanQuery = false; root.CanTouch = false; root.CastShadow = false; root.Massless = true
		root.CFrame = CFrame.new(0, 0, 0)   -- the origin every builder lays its geometry out around
		root.Parent = model
		warn(("[%s] Root was missing at publish -- rebuilt it. (It is created before the union in " ..
		      "this builder, and CSG consumed it.)"):format(model.Name))
	end
	model.PrimaryPart = root
end

--- FUSE THE WHOLE PET INTO ONE SOLID.
---
--- THIS IS THE FIX FOR "looks perfect in the Pet Hub, disconnected when equipped".
---
--- The two are the SAME model -- the hub icon and the follower clone the identical template and
--- nothing moves or resizes it in between (verified: at level 1 the follower gets clone -> blink
--- -> move, exactly what the hub gets). So the geometry was never the problem. The difference is
--- WHERE they are drawn:
---
---   * The hub renders inside a ViewportFrame: one flat light, no shadows, no ambient occlusion.
---     Boundaries between overlapping parts are invisible, so the pet reads as one creature.
---   * The world lights the pet properly. Every separately-rendered part has its own normals and
---     its own shading, so the seam where two overlapping parts meet draws as a hard line -- and
---     a hard line across a limb reads exactly like the limb is not attached.
---
--- A UnionOperation does not have that problem: it is ONE surface with ONE set of normals, and
--- SmoothingAngle blends across the whole thing. So the answer is to stop welding parts on and
--- fuse them instead -- if the pet is a single part, there is nothing left to look disconnected.
---
--- COLOUR SURVIVES. UsePartColor = false makes a union render with the colours of the ORIGINAL
--- parts rather than one flat colour, so teeth stay white, eyes stay dark and bellies stay pale.
--- That property is the only reason the coloured details had to be welded on separately before.
---
--- WHAT STAYS SEPARATE: anything that has to ANIMATE. The eye discs are squashed every blink, and
--- you cannot animate part of a union. Leaving them out costs nothing -- they are a different
--- colour from the face, so their edge reads as an eye rather than as a crack.
---
--- @param model  the pet model
--- @param body   the existing BodyUnion (or a plain part) everything gets fused into
--- @param keep   set of part NAMES to leave welded (animated parts)
--- @return the new single part
--- ONE SWITCH TO REVERT. If the fused pets come out the wrong COLOUR (everything one flat shade),
--- it means UsePartColor = false did not preserve the source parts' colours on this Roblox build.
--- Set this to false and every pet goes straight back to the old welded look -- seams and all --
--- with no other change. Nothing else in the codebase needs touching.
-- BACK ON, NOW THAT /petdiff HAS ANSWERED THE QUESTION.
--
-- The measurement: the Pet Hub icon and the equipped follower were compared part by part and came
-- back IDENTICAL -- same count, same sizes, same offsets, nothing added, nothing moved. So the
-- difference a player can see is definitively NOT geometry, and no amount of nudging coordinates
-- was ever going to fix it. It is that a ViewportFrame lights a model flatly while the world does
-- not, and every boundary between two overlapping parts becomes a visible hard line out there.
-- One fused solid has no boundaries to draw, which is why this is the fix.
--
-- The first attempt at it was reverted because it ate the Brachiosaurus neck. That was a real
-- effect with a specific cause -- see CSG_RISKY below -- not a reason to abandon fusing.
PetFace.FUSE_ALL = true

-- ===================== RAYCAST SEATING: measure the surface, stop guessing =====================
--
-- Every "floating"/"buried" bug so far has been fixed by hand-editing one coordinate, restarting,
-- and asking whether it looks right. That loop has failed repeatedly because the body is a ROUNDED
-- cube fused with snouts and tails: nobody can hand-solve where its curved surface actually is at
-- a given height, and every audit that approximated it with a bounding box cried wolf (the
-- signed-off Triceratops frill measured "1% exposed" by box while being the best-looking feature
-- in the game).
--
-- So the build now MEASURES. For each feature welded to the body, a ray is cast from outside the
-- pet straight through the feature toward the body's centre; where it strikes the body union is
-- the real, curved, post-CSG surface under that feature. If the feature's inner face hangs beyond
-- that surface it is provably FLOATING; if its outer face is under it, it is provably INVISIBLE.
-- Either way it is slid along the ray until SEAT_EMBED of its thickness sits inside the body and
-- the rest stands proud. Anything already straddling the surface is NOT touched, which is the
-- difference between this and every previous "fix": correct features (the whole Triceratops, most
-- eyes) cannot be made worse.
--
-- Runs BEFORE fuseAll's CSG pass, so parts that later fuse are fused at their SEATED positions.
-- Parts welded to another feature (teeth in a mouth) are never seated against the body -- they
-- follow their carrier by exactly its delta instead.
PetFace.SEAT_EMBED = 0.35   -- keep this fraction of a feature's thickness inside the body
PetFace.SEAT_TOL   = 0.06   -- a gap/burial smaller than this is left alone
PetFace.SEAT_SKIP  = { Triceratops = true }   -- signed off by the user: never re-seat it

local function thicknessAlong(p, dir)
	-- the part's world-space extent measured along `dir` (columns of R = world dirs of local axes)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	return math.abs(dir.X * r00 + dir.Y * r10 + dir.Z * r20) * p.Size.X
	     + math.abs(dir.X * r01 + dir.Y * r11 + dir.Z * r21) * p.Size.Y
	     + math.abs(dir.X * r02 + dir.Y * r12 + dir.Z * r22) * p.Size.Z
end

local function seatMeasure(part, body, rp)
	local dir = part.Position - body.Position
	if dir.Magnitude < 0.05 then return nil end
	dir = dir.Unit
	local th = thicknessAlong(part, dir)
	-- SHORT RAY, ANCHORED AT THE PART. The first version fired from 30 studs out and hit whatever
	-- stuck out first: the Spinosaurus snout caught the ray meant for its own eye, the eye
	-- measured "buried 0.37" while sitting perfectly, and the correction dragged the whole face
	-- around. Starting a hair outside the part means the first surface this ray can meet is the
	-- one directly beneath the part.
	--
	-- This also makes the check FLOATING-ONLY by construction: if the part is buried, the ray
	-- origin is already inside the body and hits nothing, so the part is left alone. Deliberate.
	-- Pushing "buried" parts out is what shoved the Spino mouth 1.17 studs out of its face -- a
	-- shallow marking that is mostly embedded is CORRECT, not broken. Floating is the only defect
	-- a player has ever reported, so floating is the only thing this corrects.
	local hit = workspace:Raycast(part.Position + dir * (th / 2 + 0.3), -dir * (th + 3.0), rp)
	if not hit then return nil end
	local surf = (hit.Position - body.Position):Dot(dir)
	local d    = (part.Position - body.Position):Dot(dir)
	return { dir = dir, surf = surf, centre = d, th = th, gap = (d - th / 2) - surf, buried = 0 }
end

-- Teeth, fangs and claws are placed against the MOUTH or a FOOT by their builders, hanging
-- deliberately proud -- the body-centre ray reads that as "floating" and pulls them in, which is
-- exactly how the T-Rex lost its teeth for one build. They are never body-seated.
local function seatIgnored(name)
	return name:find("Tooth") ~= nil or name:find("Fang") ~= nil or name:find("Claw") ~= nil
end

local function weldTarget(p)
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("WeldConstraint") and c.Part0 then return c.Part0 end
	end
	return nil
end

--- Read-only version of the measurement, for diagnostics (/petfull). Returns rows for every
--- part still welded to the BodyUnion of a FINISHED pet: name, gap, buried, thickness.
function PetFace.seatReport(model)
	local body = model and model:FindFirstChild("BodyUnion")
	if not body then return {} end
	local oldQ = body.CanQuery
	body.CanQuery = true
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { body }
	local rows = {}
	for _, p in ipairs(model:GetDescendants()) do
		-- eye stacks are measured through their base disc only: the pupil, glint and iris ring sit
		-- on the WHITE disc, not on the body, so measuring them against the body reports designed
		-- layering as "floating" (the Glint false alarms that filled the first report).
		local stackLayer = PetFace.ANIMATED[p.Name] and p.Name ~= "whitepartofeye"
		if p:IsA("BasePart") and p ~= body and p.Name ~= "Root" and p.Transparency < 0.9
			and weldTarget(p) == body and not stackLayer and not seatIgnored(p.Name) then
			local m = seatMeasure(p, body, rp)
			if m then rows[#rows + 1] = { name = p.Name, gap = m.gap, buried = 0, th = m.th } end
		end
	end
	body.CanQuery = oldQ
	return rows
end

function PetFace.seatWelded(model, body, tag)
	if not (model and body) then return end
	if PetFace.SEAT_SKIP[model.Name] or PetFace.SEAT_SKIP[tag] then
		print(("[SEAT] %s: skipped by request -- this pet is signed off as-is"):format(tostring(tag)))
		return
	end
	-- raycasts only work inside Workspace; builders normally are, but NEVER crash a build over
	-- it. Re-parenting a model whose Parent is locked (destroyed mid-publish) is what killed the
	-- whole Brachiosaurus build: no template, no hub icon -- and the Pet Hub then stalled 20
	-- seconds per missing template, which blanked every render after it in the grid.
	local oldParent = nil
	if not model:IsDescendantOf(workspace) then
		oldParent = model.Parent
		local ok = pcall(function() model.Parent = workspace end)
		if not ok or not model:IsDescendantOf(workspace) then return end
	end
	local oldQ = body.CanQuery
	body.CanQuery = true
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { body }

	-- who is welded to what: only direct children of the BODY get seated; anything welded to
	-- another feature (fangs in a mouth, claw tips on hands) follows its carrier instead
	local carried = {}   -- carrier part -> { parts riding on it }
	local seatable = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= body and p.Name ~= "Root" and p.Transparency < 0.9 then
			local t = weldTarget(p)
			if t == body and not seatIgnored(p.Name) then seatable[#seatable + 1] = p
			elseif t and t ~= body then carried[t] = carried[t] or {}; table.insert(carried[t], p) end
		end
	end

	-- THE EYE STACK MOVES AS ONE UNIT. white disc + black disc + glint (+ amber ring) are layered
	-- along one axis; seating each layer against the body independently would flatten them into
	-- the same plane and z-fight. The white disc is measured, and its delta carries the others.
	local eyeGroup, eyeLeader = {}, {}
	for i = #seatable, 1, -1 do
		local p = seatable[i]
		if PetFace.ANIMATED[p.Name] then
			local key = (body.CFrame:PointToObjectSpace(p.Position).Z >= 0) and "R" or "L"
			eyeGroup[key] = eyeGroup[key] or {}
			table.insert(eyeGroup[key], p)
			if p.Name == "whitepartofeye" then eyeLeader[key] = p end
			table.remove(seatable, i)
		end
	end

	local moved, tight = 0, 0
	local function applyDelta(p, dv)
		p.CFrame = p.CFrame + dv
		for _, rider in ipairs(carried[p] or {}) do rider.CFrame = rider.CFrame + dv end
	end
	local function solve(p)
		local m = seatMeasure(p, body, rp)
		if not m then return nil, nil end
		if m.gap <= PetFace.SEAT_TOL then return nil, m end   -- touching or embedded: leave it alone
		local delta = -(m.gap + PetFace.SEAT_EMBED * m.th)    -- pull in until SEAT_EMBED sits inside
		-- a correction bigger than the gap plus the whole part is a measurement artifact, not a fix
		if -delta > math.min(1.2, m.gap + m.th) then return nil, m end
		return m.dir * delta, m
	end
	for _, p in ipairs(seatable) do
		local dv, m = solve(p)
		if dv then
			applyDelta(p, dv)
			moved += 1
			print(("[SEAT] %s: %s pulled IN %.2f studs (was floating %.2f clear, thickness %.2f)"):format(
				tostring(tag), p.Name, dv.Magnitude, m.gap, m.th))
		elseif m then tight += 1 end
	end
	for key, members in pairs(eyeGroup) do
		local lead = eyeLeader[key] or members[1]
		local dv, m = solve(lead)
		if dv then
			for _, p in ipairs(members) do applyDelta(p, dv) end
			moved += 1
			print(("[SEAT] %s: eye stack %s pulled IN %.2f studs as one unit (was floating %.2f clear)"):format(
				tostring(tag), key, dv.Magnitude, m.gap))
		elseif m then tight += 1 end
	end
	body.CanQuery = oldQ
	if oldParent then model.Parent = oldParent end
	print(("[SEAT] %s: %d feature(s) re-seated on the measured surface, %d already correct")
		:format(tostring(tag), moved, tight))
end

function PetFace.fuseAll(model, body, keep)
	if not (model and body) then return body end
	-- seat FIRST, fuse SECOND: parts that fuse must be fused at their measured positions
	PetFace.seatWelded(model, body, model.Name)
	if not PetFace.FUSE_ALL then return body end
	keep = keep or {}
	-- ===== WHAT CSG CANNOT BE TRUSTED WITH =====
	-- Solid modelling treats a Ball part as a SPHERE. Hand it a Ball that has been scaled
	-- non-uniformly and it can come back as a sphere of the SMALLEST radius -- which is precisely
	-- what happened to the Brachiosaurus neck (0.95 x 3.85 x 0.95): it was reported in-world as
	-- "no neck, just a small floating ball between the head and body".
	--
	-- Rather than ban fusing over it, the lopsided balls simply stay welded. There are few of
	-- them, they are nearly always a different colour from the body (a belly patch, a dorsal fin),
	-- and a seam between two DIFFERENT colours reads as a marking rather than as a crack -- so
	-- keeping them out costs almost nothing while removing the failure entirely.
	-- ===== THE ACTUAL RULE, MEASURED AT LAST =====
	--
	-- /petprobe finally gave hard numbers, and they identify the bug that has been behind every
	-- one of these reports:
	--
	--   Spino Sail    3.4 x 2.8 x 1.1     NO rotation      -> survived as a full ellipsoid
	--   Shark Dorsal  1.7 x 2.7 x 0.9     rotated 16 deg   -> union grew by ~0. IT VANISHED.
	--   Brachio neck  0.95 x 3.85 x 0.95  rotated 17 deg   -> reported as "a small floating ball"
	--   Head / Snout  1.65 x 1.40 x 1.50  NO rotation      -> fine on every pet, always
	--
	-- A Ball that is NON-UNIFORM *and* ROTATED is destroyed by CSG -- it comes back as a small
	-- sphere of roughly its minor radius, or as nothing at all. Non-uniform alone is fine.
	-- Rotated alone is fine. The two together is what kills it.
	--
	-- That single rule explains the whole saga: the missing dorsal fin, the neck that turned into
	-- a ball, and the "floating" face parts -- because when a rotated snout or jaw shrinks inside
	-- the union, the eyes and teeth welded around it are left hanging in the space it used to
	-- occupy. Nothing was ever floating; the geometry underneath them was collapsing.
	--
	-- Both earlier size thresholds (1.6, then 3.2) were guesses at the wrong variable. Size was
	-- never the trigger. ROTATION is.
	local function isRotated(p)
		local rx, ry, rz = p.CFrame:ToEulerAnglesXYZ()
		return math.abs(rx) > 0.02 or math.abs(ry) > 0.02 or math.abs(rz) > 0.02
	end
	local function csgRisky(p)
		if not p:IsA("Part") or p.Shape ~= Enum.PartType.Ball then return false end
		local sz = p.Size
		local mx, mn = math.max(sz.X, sz.Y, sz.Z), math.min(sz.X, sz.Y, sz.Z)
		if mn <= 0 then return false end
		local ratio = mx / mn
		-- rotated AND stretched at all: the fatal combination
		if ratio > 1.15 and isRotated(p) then return true end
		-- and still keep the wildly lopsided ones out even unrotated, as a belt-and-braces guard
		return ratio > 3.2
	end

	-- MOVING PARTS STAY WELDED. The walk cycle and fin flap can only move a part that is its own
	-- part -- anything fused is rigid with the body forever. Feet (Foot*) and side fins
	-- (Pectoral/Wing) are therefore always kept out of the union. The cost is a faint seam at
	-- each ankle; the payoff is legs that actually step and fins that actually swim.
	local function isMovingPart(name)
		return name:sub(1, 4) == "Foot" or name == "Pectoral" or name == "Wing"
	end
	local victims, keepers, risky = {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= body and d.Name ~= "Root" and not d:IsA("UnionOperation") then
			if keep[d.Name] or isMovingPart(d.Name) then keepers[#keepers + 1] = d
			elseif csgRisky(d) then
				keepers[#keepers + 1] = d
				risky[#risky + 1] = ("%s(%.2fx%.2fx%.2f)"):format(d.Name, d.Size.X, d.Size.Y, d.Size.Z)
			else victims[#victims + 1] = d end
		elseif d:IsA("UnionOperation") and d ~= body then
			victims[#victims + 1] = d
		end
	end
	if #victims == 0 then return body end

	local function finish(u)
		u.Name = "BodyUnion"
		u.UsePartColor = false          -- keep every source part's own colour
		u.Anchored = true; u.CanCollide = false; u.CanQuery = false; u.CanTouch = false
		u.CastShadow = false; u.Massless = true
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end)
		u.Parent = model
		PetFace.forcePrecise(u, model.Name)   -- AFTER parenting: it does not stick before
		print(("[%s] fuseAll: %d part(s) fused into ONE solid (+%d kept separate)")
			:format(model.Name, #victims + 1, #keepers))
		-- NB: this line is on the SUCCESS path only. The batch fallback below reports its own
		-- totals; a previous version printed this unconditionally, so a run in which every single
		-- part refused still announced "20 fused" and the failure looked like a win.
		if #risky > 0 then
			print(("[%s] fuseAll: left welded -- CSG destroys a Ball that is both stretched AND rotated: %s")
				:format(model.Name, table.concat(risky, ", ")))
		end
		-- the old body is gone, so anything deliberately left out has lost its weld
		for _, k in ipairs(keepers) do
			for _, c in ipairs(k:GetChildren()) do
				if c:IsA("WeldConstraint") then c:Destroy() end
			end
			local w = Instance.new("WeldConstraint")
			w.Name = "Attach"; w.Part0 = u; w.Part1 = k; w.Parent = k
		end
		return u
	end

	-- STRIP THE WELDS FIRST. Every victim is currently welded to the body, and handing CSG an
	-- operand that still carries a joint is a known way to make UnionAsync refuse. It cost the
	-- Brachiosaurus every single one of its 18 features -- snout, mouth and nostrils included --
	-- which is precisely why that pet still read as loose balls hanging off a head while the
	-- Therizinosaurus (46 parts, same code) fused cleanly.
	for _, v in ipairs(victims) do
		for _, c in ipairs(v:GetChildren()) do
			if c:IsA("WeldConstraint") or c:IsA("Weld") or c:IsA("Motor6D") then c:Destroy() end
		end
	end

	-- ONE FLAT CALL FIRST -- the live log proved batching fails MORE often than a single union.
	local ok, u = pcall(function() return body:UnionAsync(victims) end)
	if ok and typeof(u) == "Instance" then
		body:Destroy()
		for _, v in ipairs(victims) do v:Destroy() end
		return finish(u)
	end

	-- fallback: fold them in a few at a time; whatever refuses stays welded as it is today
	-- FALL ALL THE WAY DOWN TO ONE AT A TIME. The old version gave up on a whole batch of five the
	-- moment CSG refused it, so a single awkward part could drag four perfectly fusable ones out
	-- with it -- which is how 18 of 18 ended up welded. Now a failed batch is retried piece by
	-- piece, and only the parts that genuinely cannot fuse stay welded.
	local base, pending, refused = body, {}, 0
	for i, v in ipairs(victims) do pending[i] = v end
	local function tryFuse(batch)
		local ok2, u2 = pcall(function() return base:UnionAsync(batch) end)
		if ok2 and typeof(u2) == "Instance" then
			base:Destroy()
			for _, b in ipairs(batch) do b:Destroy() end
			base = u2; base.Parent = model
			return true
		end
		return false
	end
	while #pending > 0 do
		local batch = {}
		for _ = 1, math.min(5, #pending) do batch[#batch + 1] = table.remove(pending, 1) end
		if not tryFuse(batch) then
			for _, b in ipairs(batch) do
				if not tryFuse({ b }) then
					refused = refused + 1
					local w = Instance.new("WeldConstraint")
					w.Name = "Attach"; w.Part0 = base; w.Part1 = b; w.Parent = b
				end
			end
		end
	end
	if refused > 0 then
		warn(("[%s] fuseAll: %d part(s) refused to fuse and stayed welded (they may show a seam)")
			:format(model.Name, refused))
	end
	return finish(base)
end

--- The parts every pet must keep OUT of the union, because they are animated.
--- FORCE A UNION TO RENDER AT FULL DETAIL, AND SAY SO IF IT WILL NOT.
---
--- THIS IS THE BUG THAT CAUSED "perfect in the Pet Hub, disconnected when equipped".
--- /petfull dumped `RF=Automatic` on every single dinosaur union -- even though the builders had
--- been setting Precise all along, inside a pcall that was quietly failing.
---
--- I read that as the cause of "right in the menu, wrong in the world" and it is NOT. Two things
--- disprove it, and they are recorded here so nobody spends another session on this dead end:
---
---   1. THE WRITE IS REFUSED, not merely failing quietly. A UnionOperation built at runtime by
---      :UnionAsync() keeps RenderFidelity = Automatic no matter when you assign it -- before
---      parenting, after parenting, from the client, from the server. The read-back below stays
---      Automatic on all 8 dinosaurs. It is not an ordering bug, so there is no ordering fix.
---
---   2. IT WOULD NOT MATTER IF IT WORKED. Automatic picks the level of detail from the CAMERA
---      DISTANCE, not the on-screen size, and it uses the HIGHEST detail inside ~250 studs. An
---      equipped pet trails the player a few studs away, so Automatic already renders it whole.
---      The Hub icon and the follower are getting the same mesh.
---
--- So the difference between the hub copy and the world copy is created somewhere in the spawn
--- path, not by this property. The call is kept because Precise is still what we want if Roblox
--- ever allows it, but it is now a one-line note instead of eight scary warnings a boot.
local precisePrinted = false
function PetFace.forcePrecise(inst, tag)
	if not (inst and inst:IsA("UnionOperation")) then return end
	pcall(function() inst.RenderFidelity = Enum.RenderFidelity.Precise end)
	pcall(function() inst.CollisionFidelity = Enum.CollisionFidelity.Box end)
	if inst.RenderFidelity ~= Enum.RenderFidelity.Precise and not precisePrinted then
		precisePrinted = true
		print(("[PetFace] RenderFidelity stays %s on runtime unions (Roblox refuses the write, e.g. %s/%s). "
		      .. "Harmless: Automatic already renders at full detail within ~250 studs of the camera.")
			:format(tostring(inst.RenderFidelity):gsub("Enum.RenderFidelity.", ""), tostring(tag), inst.Name))
	end
end

PetFace.ANIMATED = {
	whitepartofeye = true, blackpartofeye = true, Glint = true, EyeAmber = true,
}

--- BUILD-TIME ATTACHMENT AUDIT -- call once at the end of every pet builder.
---
--- WHY: a pet part can be "wrong" in two ways that look identical in the finished model and
--- are both invisible in the source. (1) It was never welded -- weldTo(part, body) silently
--- does nothing when body is nil, which is exactly what happens when UnionAsync FAILS, so one
--- failed union detaches every decoration on the pet at once. (2) It was welded correctly but
--- placed where it does not touch the body, so it rides along at the right offset while
--- visibly floating in mid-air. Both have shipped here more than once, and neither is findable
--- by reading the file -- you have to compare numbers against the body's actual extents.
---
--- This does that comparison and prints it. It never changes the model.
function PetFace.audit(model, tag)
	tag = tag or model.Name
	local union, parts = nil, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "BodyUnion" then union = d
			elseif d.Name ~= "Root" then parts[#parts + 1] = d end
		end
	end
	if not union then
		warn(("[%s][AUDIT] NO BodyUnion -- the CSG union failed, so all %d part(s) are loose and " ..
		      "unattached. Everything on this pet will look like it is floating."):format(tag, #parts))
		return
	end
	-- (An earlier version ran a SECOND seat pass here, against the post-CSG surface. Two passes
	-- against two different surfaces moved the same parts twice along two different rays -- the
	-- Spinosaurus eyes drifted 0.16 studs diagonally across the face from the churn, and the
	-- pass could even touch a model mid-publish. Seating happens exactly once, in fuseAll,
	-- before the fuse bakes anything in.)
	-- conservative axis-aligned overlap: the union is built unrotated at the origin, and every
	-- decoration is a small blob, so treating both as boxes is accurate enough to catch a gap.
	local uMin = union.Position - union.Size * 0.5
	local uMax = union.Position + union.Size * 0.5
	local loose, floating = {}, {}
	for _, p in ipairs(parts) do
		local welded = false
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("WeldConstraint") then welded = true; break end
		end
		if not welded then loose[#loose + 1] = p.Name end
		-- ROTATED PARTS NEED A SPHERE, NOT AN AXIS-ALIGNED BOX. Position +/- Size/2 describes the
		-- part's LOCAL box; for anything rotated (claw segments, angled fins, brow ridges) that box
		-- is in the wrong orientation and the test reports a perfectly attached part as FLOATING.
		-- That is what produced six phantom "floating claw tips" on the Therizinosaurus. A bounding
		-- sphere is orientation-free: it can never give a false alarm, only miss a marginal case --
		-- and tools/petscan.py does the exact geometry offline, so this only has to be a safety net.
		local pr = p.Size.Magnitude * 0.5
		local pMin = p.Position - Vector3.new(pr, pr, pr)
		local pMax = p.Position + Vector3.new(pr, pr, pr)
		local hit = (pMin.X <= uMax.X and pMax.X >= uMin.X)
			and (pMin.Y <= uMax.Y and pMax.Y >= uMin.Y)
			and (pMin.Z <= uMax.Z and pMax.Z >= uMin.Z)
		if not hit then
			-- it may still be legitimately anchored to another decoration (a tooth in a mouth,
			-- a claw in a hand), so only flag it if it touches nothing at all.
			local touchesSibling = false
			for _, q in ipairs(parts) do
				if q ~= p then
					local qr = q.Size.Magnitude * 0.5
					local qMin = q.Position - Vector3.new(qr, qr, qr)
					local qMax = q.Position + Vector3.new(qr, qr, qr)
					if (pMin.X <= qMax.X and pMax.X >= qMin.X)
						and (pMin.Y <= qMax.Y and pMax.Y >= qMin.Y)
						and (pMin.Z <= qMax.Z and pMax.Z >= qMin.Z) then touchesSibling = true; break end
				end
			end
			if not touchesSibling then floating[#floating + 1] = ("%s@(%.2f,%.2f,%.2f)"):format(
				p.Name, p.Position.X, p.Position.Y, p.Position.Z) end
		end
	end
	if #loose > 0 then
		warn(("[%s][AUDIT] %d part(s) NOT WELDED to anything: %s"):format(tag, #loose, table.concat(loose, ", ")))
	end
	if #floating > 0 then
		warn(("[%s][AUDIT] %d part(s) FLOATING (touching neither the body nor any other part): %s")
			:format(tag, #floating, table.concat(floating, ", ")))
	end
	if #loose == 0 and #floating == 0 then
		print(("[%s][AUDIT] ok -- %d part(s), all welded and all touching the body"):format(tag, #parts))
	end
end

-- One line in the log says which mode the pets were built in, so a report of "still wrong"
-- can always be tied to a known configuration instead of a guess about what was running.
print(("[PetFace] config: FUSE_ALL=%s  (true = each pet is one fused solid; " ..
	"false = the original welded build)"):format(tostring(PetFace.FUSE_ALL)))

return PetFace
