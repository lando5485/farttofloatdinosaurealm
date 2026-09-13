-- ============================================================================================================
-- PET SKIN LOOK (client) -- paints a SKIN and a TRAIT onto a pet model.
-- ============================================================================================================
-- This is the RENDERER. It owns no state that matters: the server decides what a player owns and what's
-- equipped, pushes it over SkinRemotes.SkinStateEvent, and this script draws it.
--
-- HOW IT HOOKS IN
--   PetFollow.client.lua calls _G.applyPetSkinLook(pet, petId, lite) at the end of applyLevelVisual -- after
--   clearEvo and every level effect -- so a skin can never be stripped by the evolution pass, and inventory /
--   trade icon clones (lite=true) get the skin as well. Two guarded one-liners in PetFollow; nothing else there
--   changed.
--
--   When the player EQUIPS something there is no level change, so PetFollow doesn't rebuild. This script keeps a
--   weak set of the models it has painted and repaints those directly.
--
-- WHAT A SKIN DOES        recolour + material + reflectance/transparency on the BODY parts, plus the skin's own
--                         flavour effects (Lava embers, Ocean bubbles) and small deco geometry (Crystal shards,
--                         Robot antenna). Eyes, accessories and level FX are skipped -- the same exclusion list
--                         PetFollow's own applyRareLook uses.
-- WHAT A TRAIT DOES       builds the trait's ACCESSORY SET (hats, glasses, capes, armour -- see PetTraits) on
--                         named attach points derived from the pet's own bounding box, so ONE authored trait
--                         fits every pet, including pets added later. Per-pet nudges come from
--                         PetTraits.PET_OFFSETS, never from per-pet trait art. A trait may also carry small
--                         effects (particles / light / orbiting bits) -- flavour, never a body change, and
--                         never enough to hide what pet or skin is underneath.
--
-- ORIGINALS ARE SNAPSHOTTED before the first recolour, so switching skins (or clearing one) restores the pet's
-- real colours rather than stacking tints.
-- ============================================================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local PetSkins  = require(Shared:WaitForChild("PetSkins"))
local PetTraits = require(Shared:WaitForChild("PetTraits"))
local PetTier   = require(Shared:WaitForChild("PetTier"))

local SkinRemotes    = ReplicatedStorage:WaitForChild("SkinRemotes", 30)
local GetSkinState   = SkinRemotes and SkinRemotes:WaitForChild("GetSkinState", 10)
local SkinStateEvent = SkinRemotes and SkinRemotes:WaitForChild("SkinStateEvent", 10)

-- ===== LOCAL VIEW OF SERVER STATE =====
-- equipped[petId] = { skin = "Cosmic", trait = "King" }. Authoritative copy lives on the server; this is only
-- what we were last told, and it is never used to decide what the player OWNS -- only what to draw.
local equipped = {}
_G.petSkinEquipped = equipped -- read by the crate/inventory UI so it doesn't need its own copy

-- ===== DEV TRY-ON (client-side preview) =====
-- When set, EVERY pet this client paints wears this combo instead of its real equip -- which is what lets
-- /testpet put a skin/trait on the live follower so it can be seen walking around in the world. Purely
-- local: nothing is granted or saved, other players still see the real equip, and it sits INSIDE the
-- renderer (checked at paint time) so the constant repaints (level-ups, state pushes, evo refreshes) keep
-- the try-on instead of wiping it. Cleared with _G.petSkinTryOn(nil).
--
-- BUT IT YIELDS TO ANY REAL ACTION. An override that survives everything turns the Pet Hub's buttons into
-- liars: press EQUIP/UNEQUIP or switch pets and nothing visibly happens, because the preview silently
-- outranks the result. So the try-on drops itself the moment the player equips/unequips a skin (a changed
-- equip signature from the server) or a DIFFERENT pet starts following them. dropTryOn is a forward local:
-- assigned below repaintAll, called only at runtime.
local tryOn = nil -- { skin = skinId, trait = traitId } or nil
-- LIVE PER-PET TUNING (/testpet's ADJUST mode): runtime nudges layered on top of PetTraits.PET_OFFSETS
-- while the tester LOOKS at the real pet, then dumped as a paste-ready PET_OFFSETS entry. Session-local.
local liveAdjust = {} -- [petId] = { [attach] = { x, y, z, scale } }
local dropTryOn -- (why) -> clears tryOn + repaints; assigned after repaintAll exists
local lastLivePetId = nil -- which pet the follower paints were for, to catch a pet switch
local lastEquipSig = nil  -- last server-confirmed equip signature, to catch a real equip/unequip

-- Every pet model this script has painted, so an equip change can repaint without searching Workspace.
-- Weak keys: when PetFollow destroys a pet the entry disappears on its own.
local painted = setmetatable({}, { __mode = "k" }) -- [model] = petId
-- Published because this is the only complete register of live pet models anywhere on the client: PetFollow
-- builds them but keeps them in a local it cannot export (that file sits on Luau's 200-locals ceiling), and
-- every pet passes through here on build. PetRenderGuard watches it. Weak keys, so publishing it keeps
-- nothing alive.
_G.petPaintedModels = painted

-- Original appearance per part, so a skin change restores instead of stacking. Weak keys again.
local originals = setmetatable({}, { __mode = "k" }) -- [part] = { color, material, refl, trans }

-- Models with an animated skin (rainbow / cosmic hue cycling), orbiting trait parts, and accessory sets that
-- follow the pet. All weak-keyed so a destroyed pet cleans itself up.
local animated  = setmetatable({}, { __mode = "k" }) -- [model] = { mode, parts = {...} }
local orbiting  = setmetatable({}, { __mode = "k" }) -- [model] = { parts = {...}, radius, speed, root }
local accessorised = setmetatable({}, { __mode = "k" }) -- [model] = { root, groups = { {cf, parts={{part,off}}} } }

-- Parts a recolour must NEVER touch. Same list PetFollow's applyRareLook uses, so the two agree on what counts
-- as "the body": eyes stay white, accessories keep their own colours, level FX keep theirs.
local SKIP_NAMES = {
	Eye = true, Pupil = true, Highlight = true, EvoPart = true,
	PetOrb = true, PetRing = true, PetPulse = true,
	-- this script's own additions, so a repaint never recolours its own effects
	PetSkinOrb = true, PetSkinAcc = true, PetSkinDeco = true,
}

local FX_NAMES = {
	"PetSkinFX", "PetSkinLight", "PetSkinSparkles", "PetSkinOrb", "PetSkinAcc", "PetSkinDeco", "PetSkinTraitFX",
	"PetSkinTrail", "PetSkinTrailA0", "PetSkinTrailA1",
}

-- ============================================================================================================
-- CLEAR
-- ============================================================================================================
local function clearLook(model)
	if not model then return end
	-- remove our effects (and only ours -- everything we create is named from FX_NAMES)
	for _, d in ipairs(model:GetDescendants()) do
		for _, n in ipairs(FX_NAMES) do
			if d.Name == n then pcall(function() d:Destroy() end); break end
		end
	end
	animated[model] = nil
	orbiting[model] = nil
	accessorised[model] = nil
	-- restore original body appearance
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local o = originals[d]
			if o then
				d.Color = o.color; d.Material = o.material; d.Reflectance = o.refl
				if o.trans ~= nil then d.Transparency = o.trans end
			end
		end
	end
end

-- ============================================================================================================
-- SKIN
-- ============================================================================================================
local function bodyParts(model)
	local root = model.PrimaryPart
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and not SKIP_NAMES[d.Name] then
			out[#out + 1] = d
		end
	end
	return out
end

local function snapshot(p)
	if not originals[p] then
		originals[p] = { color = p.Color, material = p.Material, refl = p.Reflectance, trans = p.Transparency }
	end
end

-- ONE particle builder for skins and traits alike -- both declare the same { texture, color, size, rate, ... }
-- spec, so Lava's embers and Titan's sparks come out of the same code path.
local function buildParticle(root, spec, name)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = spec.texture or "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(spec.color or Color3.new(1, 1, 1))
	e.LightEmission = 0.7
	e.Rate = spec.rate or 12
	e.Speed = NumberRange.new(spec.speed or 1)
	e.Lifetime = NumberRange.new((spec.lifetime or 1) * 0.7, spec.lifetime or 1)
	e.Size = NumberSequence.new(spec.size or 1)
	e.SpreadAngle = Vector2.new(spec.spread or 15, spec.spread or 15)
	e.Rotation = NumberRange.new(0, 360)
	e.Acceleration = spec.accel or Vector3.new()
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.transparency or 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = root
	return e
end

-- ============================================================================================================
-- GLOBAL PET DIM -- every pet renders 25% darker than it is built.
-- ============================================================================================================
-- The pets were reading as too bright next to the islands. This is the single place to fix that, because it is
-- the one function EVERY pet passes through. Multiplying the channels keeps every hue where it was and only
-- takes the value down. It cannot compound: the TRUE colour is snapshotted before the first dim and clearLook
-- restores from that snapshot at the top of every call.
local PET_DIM = 0.75 -- 25% down

local function dimBody(model)
	for _, p in ipairs(bodyParts(model)) do
		snapshot(p)
		local c = p.Color
		p.Color = Color3.new(c.R * PET_DIM, c.G * PET_DIM, c.B * PET_DIM)
	end
end

-- ============================================================================================================
-- ATTACH POINTS + THE ACCESSORY BUILDER
-- ============================================================================================================
-- Head / Face / Neck / Back / Body are derived from the pet's OWN geometry, in the root's local space, so one
-- authored trait lands sensibly on a duck, a crab and a dragon without per-pet art. Accessory specs are
-- authored for a ~2-stud pet; `scale` stretches them to the real one. PetTraits.PET_OFFSETS supplies the
-- per-pet nudges (position / rotation / scale per attach point) for anatomy the maths can't describe.
--
-- THE PLACEMENT RULE: accessories seat on the pet's MAIN BODY MASS, never on a protrusion. Bean Buddy has a
-- little vine sprouting from his head; a plain bounding box makes the vine tip the "top" and every hat
-- hovers on it. So thin protruding parts are filtered out two ways before any attach point is computed:
--   * by NAME -- vines, sprouts, stems, leaves, antennae, horns, ears, tails, beaks and the like;
--   * by FOOTPRINT -- any part whose horizontal cross-section is a sliver of the largest part's can't be
--     the thing a hat rests on, whatever it is called.
-- The hat then sits on the TOP SURFACE of the biggest remaining mass, centred on THAT part (a duck's hat on
-- its head, a bean's on its body, a crab's on its shell), sunk a hair so the brim hugs instead of floating.
-- Glasses use that same crown part's front and eye-line; neck/back/body come from the filtered mass too.

-- Substring matches on lower-cased part names that mark a part as a PROTRUSION -- paintable, but never the
-- surface an accessory anchors to.
local PROTRUSION_NAMES = {
	"vine", "sprout", "stem", "leaf", "leaves", "stalk", "antenna", "horn", "ear", "tail",
	"whisker", "feather", "hair", "beak", "wing", "fin", "spike", "tongue", "crest",
}
local function isProtrusionName(name)
	local n = string.lower(name)
	for _, key in ipairs(PROTRUSION_NAMES) do
		if string.find(n, key, 1, true) then return true end
	end
	return false
end

local function computeAttach(model, petId)
	local root = model.PrimaryPart
	if not root then return nil end
	local rootCF = root.CFrame

	-- WHICH WAY IS THE PET ACTUALLY FACING? Never assume the root's -Z is the face: some templates are
	-- rooted sideways, which is exactly how a backpack ends up on a pet's flank. The EYES say where the
	-- face is -- their centroid, flattened to the horizontal plane, points from the root toward the front.
	-- Every measurement below happens in this face-aligned frame, so Back really is behind and Face really
	-- is in front whatever the rig's axes do. No eyes readable -> identity, i.e. trust the root as before.
	local eyeSum, eyeN = Vector3.new(), 0
	local eyePts = {} -- individual eye positions (root-local): the separation sizes per-eye Face gear
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "Pupil") then
			local rp = rootCF:PointToObjectSpace(d.Position)
			eyeSum = eyeSum + rp
			eyeN = eyeN + 1
			if #eyePts < 8 then eyePts[#eyePts + 1] = rp end
		end
	end
	local faceCF = CFrame.new()
	if eyeN > 0 then
		local dir = (eyeSum / eyeN) * Vector3.new(1, 0, 1)
		if dir.Magnitude > 0.15 then
			faceCF = CFrame.lookAt(Vector3.new(), dir.Unit)
		end
	end

	-- Per-part boxes in the FACE-ALIGNED frame, from each part's 8 corners so a rotated wedge still counts
	-- fully. bodyParts() already excludes eyes, level FX and this script's own effects; GetBoundingBox() is
	-- avoided because it would also swallow the level-FX orbs PetFollow floats around the pet.
	local infos = {}
	for _, p in ipairs(bodyParts(model)) do
		local rel = rootCF:ToObjectSpace(p.CFrame)
		local sx, sy, sz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
		local iMinX, iMinY, iMinZ = math.huge, math.huge, math.huge
		local iMaxX, iMaxY, iMaxZ = -math.huge, -math.huge, -math.huge
		for ix = -1, 1, 2 do for iy = -1, 1, 2 do for iz = -1, 1, 2 do
			local c = faceCF:PointToObjectSpace((rel * CFrame.new(ix * sx, iy * sy, iz * sz)).Position)
			if c.X < iMinX then iMinX = c.X end; if c.X > iMaxX then iMaxX = c.X end
			if c.Y < iMinY then iMinY = c.Y end; if c.Y > iMaxY then iMaxY = c.Y end
			if c.Z < iMinZ then iMinZ = c.Z end; if c.Z > iMaxZ then iMaxZ = c.Z end
		end end end
		infos[#infos + 1] = {
			part = p,
			minX = iMinX, minY = iMinY, minZ = iMinZ, maxX = iMaxX, maxY = iMaxY, maxZ = iMaxZ,
			cx = (iMinX + iMaxX) / 2, cy = (iMinY + iMaxY) / 2, cz = (iMinZ + iMaxZ) / 2,
			foot = (iMaxX - iMinX) * (iMaxZ - iMinZ), -- horizontal cross-section: a vine's is a sliver
			protrusion = isProtrusionName(p.Name),
		}
	end
	if #infos == 0 then return nil end

	-- THE MASS FILTER. Largest footprint among the non-protrusion parts sets the bar; anything under 22% of
	-- it is a twig, whatever its name. Falls back to the full set if the filters somehow ate everything, so
	-- an oddly-built pet still gets accessories rather than none.
	local maxFoot = 0
	for _, i in ipairs(infos) do
		if not i.protrusion and i.foot > maxFoot then maxFoot = i.foot end
	end
	local major = {}
	for _, i in ipairs(infos) do
		if not i.protrusion and i.foot >= maxFoot * 0.22 then major[#major + 1] = i end
	end
	if #major == 0 then major = infos end

	-- extents of the MAIN MASS only -- this is the body every attach point is measured against
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, i in ipairs(major) do
		if i.minX < minX then minX = i.minX end; if i.maxX > maxX then maxX = i.maxX end
		if i.minY < minY then minY = i.minY end; if i.maxY > maxY then maxY = i.maxY end
		if i.minZ < minZ then minZ = i.minZ end; if i.maxZ > maxZ then maxZ = i.maxZ end
	end
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2

	-- THE CROWN: the major part whose top surface is highest -- the actual skull/shell/body a hat rests on.
	-- The hat centres on THIS part (not the whole-body centre), and sinks a hair into it so the brim hugs.
	local crown = major[1]
	for _, i in ipairs(major) do
		if i.maxY > crown.maxY then crown = i end
	end
	local crownHalf = math.max(crown.maxX - crown.minX, crown.maxZ - crown.minZ) / 2

	-- ===== PER-PET SIZING, THE FIX FOR "EVERY TRAIT SITS WRONG ON EVERY PET" =====
	-- One uniform body-derived scale can't fit a wide crab, a tall dragon and a round bean at once. So:
	--   * HEAD/FACE gear takes its SIZE from the CROWN -- a hat is sized to the head it rests on, so the
	--     brim hugs a duck's small head instead of being cut for its whole body. (Authoring basis: a head
	--     half-width of ~0.95, i.e. hats are drawn ~1.9 wide and shrink/grow from there.)
	--   * BODY/BACK gear keeps a uniform SIZE but its POSITIONS scale PER-AXIS against the body's own
	--     half-extents: a spec position is a FRACTION of the body (x = 1 is the flank, z = -1 the chest,
	--     y = 1 the top), so pauldrons land on the shoulders and straps on the flanks of EVERY body shape.
	local headU = math.clamp(crownHalf / 0.95, 0.45, 2.6)
	local massU = math.clamp(math.max(hx, hz), 0.55, 2.5)

	-- HEAD POKERS: only the twigs rising out of the CENTRE of the head top -- Bean Buddy's vine -- hide under
	-- a hat, because that is where the hat physically sits. Features growing from the SIDES (the bunny's
	-- ears, horns near the rim) are part of the pet's identity and are NEVER removed -- a hat just sits
	-- between them, cartoon-style. (Hidden locally, Transparency snapshotted; back the instant the hat comes
	-- off. A tail, wing or beak sits below the crown top and is never touched either way.)
	local pokers = {}
	do
		local ccx = (crown.minX + crown.maxX) / 2
		local ccz = (crown.minZ + crown.maxZ) / 2
		local reach = math.max(crown.maxX - crown.minX, crown.maxZ - crown.minZ) * 0.5 * 0.45
		for _, i in ipairs(infos) do
			local twig = i.protrusion or (maxFoot > 0 and i.foot < maxFoot * 0.22)
			if twig and i.maxY > crown.maxY - 0.05 then
				local dx, dz = i.cx - ccx, i.cz - ccz
				if (dx * dx + dz * dz) <= reach * reach then pokers[#pokers + 1] = i.part end
			end
		end
	end

	-- THE EYE LINE, in face space: where glasses/eyepatches/monocles must actually sit. Falls back to a
	-- crown-based guess only when the pet's eyes couldn't be read. eyeSepX is HALF the eye separation, so
	-- per-eye Face gear authored at x = 1 lands dead on an eye whatever the pet's eye spacing is.
	local eyeFace, eyeSepX = nil, 0.30 * headU
	if eyeN > 0 then
		eyeFace = faceCF:PointToObjectSpace(eyeSum / eyeN)
		local spread, n = 0, 0
		for _, rp in ipairs(eyePts) do
			local fp = faceCF:PointToObjectSpace(rp)
			spread = spread + math.abs(fp.X - eyeFace.X)
			n = n + 1
		end
		if n > 0 and spread / n > 0.08 then eyeSepX = math.max(spread / n, 0.18 * headU) end
	end

	-- THE CHEST LINE: the front surface just below the MOUTH. Head-based drops see-sawed (big-headed pets
	-- dropped to the belly, small-headed ones stayed on the mouth), so the drop is in STUDS below the eye
	-- line -- pets share a similar absolute scale, and a mouth sits ~0.5-0.8 studs under the eyes on all of
	-- them -- with a proportional floor so the big pets scale up.
	local chestY
	if eyeFace then chestY = eyeFace.Y - math.max(0.9, 0.55 * hy) else chestY = cy - hy * 0.15 end
	chestY = math.clamp(chestY, minY + 0.15 * hy, cy + 0.25 * hy)

	-- Attach frames are the face frame times an offset measured IN it: in that frame -Z points at the eyes,
	-- so Face sits on the eye side and Back sits on the exact opposite side -- the backpack and cape land
	-- behind the pet no matter how its template happens to be rooted.
	local points = {
		Head = faceCF * CFrame.new(crown.cx, crown.maxY - 0.05 * headU, crown.cz),
		-- ON THE EYES: the Face origin is the eye centroid itself, pushed to the crown's front surface --
		-- glasses land across the eyes and a monocle lands on one, exactly, on every pet
		-- pushed a solid 0.08 clear of the surface: eye parts are EMBEDDED in the face, so anchoring at
		-- their depth recessed the glasses into the body (the x-ray showed 0.1-0.4 of sink)
		Face = faceCF * (eyeFace
			and CFrame.new(eyeFace.X, eyeFace.Y, math.min(eyeFace.Z, crown.minZ) - 0.08)
			or CFrame.new(crown.cx, crown.cy + (crown.maxY - crown.cy) * 0.40, crown.minZ - 0.08)),
		-- the chest line (see above): visible, and guaranteed below the face
		Neck = faceCF * CFrame.new(cx, chestY, minZ - 0.02),
		-- flush against the REAR FACE of the main mass, upper back -- a backpack spec tucks itself a hair
		-- into this plane so the pack presses against the body instead of hovering behind a round pet
		Back = faceCF * CFrame.new(cx, cy + hy * 0.20, maxZ),
		Body = faceCF * CFrame.new(cx, cy, cz),
	}

	-- Per-attach sizing record: `size` scales the part dimensions uniformly (assemblies stay rigid);
	-- `pos` scales each position axis, which is what conforms body gear to the body's actual shape.
	-- Face's X position axis is the EYE SEPARATION, so lenses/patches/monocles land per-eye.
	local scales = {
		Head = { size = headU, pos = Vector3.new(headU, headU, headU) },
		Face = { size = headU, pos = Vector3.new(eyeSepX, headU, headU) },
		-- neck/chest gear runs at 75% -- full-size bowties and ties reached up into mouths and dangled
		-- below small bodies; smaller fits the strip between the face and the belly on every pet
		Neck = { size = (headU + massU) * 0.375, pos = Vector3.new((headU + massU) * 0.375, (headU + massU) * 0.375, (headU + massU) * 0.375) },
		Back = { size = massU, pos = Vector3.new(hx, hy, hz) },
		Body = { size = massU, pos = Vector3.new(hx, hy, hz) },
	}

	-- ANCHORS: which real body part each attach point rides. Head/Face gear follows the CROWN part and
	-- chest/back/body gear follows the biggest mass part -- so when the pet waddles, squashes or wobbles a
	-- part relative to its root, the gear on that part moves WITH it instead of hovering rigidly.
	local biggest = major[1]
	for _, i in ipairs(major) do
		if i.foot > biggest.foot then biggest = i end
	end
	local anchors = {
		Head = crown.part, Face = crown.part,
		Neck = biggest.part, Back = biggest.part, Body = biggest.part,
	}

	-- fold in the per-pet tuning (position in fractions of that attach's own units, rotation in degrees,
	-- scale multiplier)
	local overrides = petId and PetTraits.PET_OFFSETS[petId]
	if overrides then
		for name, o in pairs(overrides) do
			local cf, rec = points[name], scales[name]
			if cf and rec then
				local p = o.pos or { 0, 0, 0 }
				local r = o.rot or { 0, 0, 0 }
				points[name] = cf * CFrame.new(p[1] * rec.pos.X, p[2] * rec.pos.Y, p[3] * rec.pos.Z)
					* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
				local m = o.scale or 1
				scales[name] = { size = rec.size * m, pos = rec.pos * m }
			end
		end
	end

	-- live ADJUST nudges go on last, so they tune what is actually on screen (offsets included)
	local live = petId and liveAdjust[petId]
	if live then
		for name, o in pairs(live) do
			local cf, rec = points[name], scales[name]
			if cf and rec then
				points[name] = cf * CFrame.new(o.x * rec.pos.X, o.y * rec.pos.Y, o.z * rec.pos.Z)
				scales[name] = { size = rec.size * o.scale, pos = rec.pos * o.scale }
			end
		end
	end
	return points, scales, pokers, anchors
end

local function buildSpecPart(spec, rec)
	local p
	if spec.shape == "Wedge" then
		-- a real one-piece wedge (horns, blades): sharp top edge, solid taper -- no stacked segments
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if spec.shape == "Ball" then p.Shape = Enum.PartType.Ball
		elseif spec.shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder
		else p.Shape = Enum.PartType.Block end
	end
	p.Name = "PetSkinAcc"
	p.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]) * rec.size
	-- "Dome" = an ellipsoid mesh on a block, so a HALF-SPHERE profile is one part: size it wide and short
	-- and only the rounded cap shows above whatever it sits on (beanies, helmets, caps).
	if spec.shape == "Dome" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Color = spec.color or Color3.new(1, 1, 1)
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Reflectance = spec.refl or 0
	p.Transparency = spec.trans or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	return p
end

local function specOffset(spec, rec)
	local pos = spec.pos or { 0, 0, 0 }
	local rot = spec.rot or { 0, 0, 0 }
	-- `uniform` locks a part's POSITION to the same scale as its SIZE. Face gear normally spreads its X by
	-- the eye separation, but a multi-piece rigid frame (the sunglasses) shatters when its pieces position
	-- on one scale and size on another -- uniform parts stay one solid assembly.
	if spec.uniform then
		return CFrame.new(pos[1] * rec.size, pos[2] * rec.size, pos[3] * rec.size)
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	end
	return CFrame.new(pos[1] * rec.pos.X, pos[2] * rec.pos.Y, pos[3] * rec.pos.Z)
		* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

-- Build a list of part specs onto the model. `static` places them once at the current root CFrame (viewport
-- icons, previews); otherwise they join the follow loop and track the pet every frame -- the same rigid-
-- assembly approach the old floating crown used, which survives however PetFollow moves the model.
local function buildAccessoryParts(model, petId, specs, defaultAttach, static, partName)
	if not specs or #specs == 0 then return end
	local root = model.PrimaryPart
	if not root then return end
	local points, scales, pokers, anchors = computeAttach(model, petId)
	if not points then return end

	local reg = accessorised[model]
	if not reg and not static then
		reg = { root = root, groups = {} }
		accessorised[model] = reg
	end

	-- group the specs by attach point so the follow loop does one attach-CFrame multiply per group
	local groups = {}
	for _, spec in ipairs(specs) do
		local attach = spec.attach or defaultAttach or "Head"
		if not points[attach] then attach = "Head" end
		local g = groups[attach]
		if not g then g = {}; groups[attach] = g end
		g[#g + 1] = spec
	end

	-- SOMETHING IS GOING ON THE HEAD -> hide the head pokers (Bean Buddy's vine, bunny ears, horns) so
	-- nothing sticks through the hat. Local + snapshotted: clearLook restores the original transparency at
	-- the top of every repaint, so the vine is back the moment the hat is taken off. Face/neck/back/body
	-- accessories leave the pet's features exactly as they are.
	if groups.Head and pokers then
		for _, p in ipairs(pokers) do
			snapshot(p)
			p.Transparency = 1
		end
	end

	for attach, list in pairs(groups) do
		local rec = scales[attach] or { size = 1, pos = Vector3.new(1, 1, 1) }
		local attachCF = points[attach]
		local built = {}
		for _, spec in ipairs(list) do
			local p = buildSpecPart(spec, rec)
			if partName then p.Name = partName end
			p:SetAttribute("PetSkinAttach", attach) -- read by /scanpet's geometry X-ray
			local off = specOffset(spec, rec)
			p.CFrame = root.CFrame * attachCF * off
			p.Parent = model
			-- `sway` marks cloth (capes, tails, the bandana): the follow loop flutters it about a HINGE at
			-- the part's top edge, so it flaps like fabric pinned at the shoulders, not a slab spinning on
			-- its centre. phase staggers siblings so a three-segment cape ripples instead of flapping as one.
			-- swayPhase pins multi-part cloth to ONE rhythm (a cape + its hem move as one sheet); without it
			-- each part gets its own stagger, which is right for independent strips/tails
			built[#built + 1] = { part = p, off = off, sway = spec.sway, hinge = p.Size.Y / 2,
				phase = (spec.sway and spec.sway.phase) or (#built * 1.7) }
		end
		if reg then
			-- follow the ANCHOR body part where one exists: rel re-derives the attach frame from that part's
			-- live CFrame each frame, so the gear inherits the pet's waddle/wobble, not just its position
			local anchor = anchors and anchors[attach]
			local rel = nil
			if anchor and anchor.Parent then
				rel = anchor.CFrame:ToObjectSpace(root.CFrame * attachCF)
			else
				anchor = nil
			end
			reg.groups[#reg.groups + 1] = { cf = attachCF, parts = built, anchor = anchor, rel = rel }
		end
	end
end

-- ---- SKIN DECO ----------------------------------------------------------------------------------------------
-- Small extra geometry a skin can declare (PetSkins `deco` field) so its identity is structural, not just a
-- recolour: Crystal grows shards, Robot gets an antenna and rivets. Authored here as ordinary accessory specs
-- and built through the exact same pipeline as trait accessories.
-- Body deco positions are FRACTIONS of the body's half-extents (same convention as trait Body specs), so
-- every point below has magnitude ~1: ON the surface of whatever shape the pet is, never buried inside it.
local SKIN_DECO = {
	-- shards grow off the BACK and FLANKS, kept low -- never crowning the head (that read as a weird
	-- hat on the pets whose body IS their head)
	crystals = { attach = "Body", parts = {
		{ shape="Block", size={0.22,0.75,0.22}, pos={0,0.40,0.62}, rot={-15,10,  5},
			color=Color3.fromRGB(205,165,250), material=Enum.Material.Glass, trans=0.2, refl=0.3 },        -- big back spike
		{ shape="Block", size={0.18,0.60,0.18}, pos={-0.62,0.30,0.25}, rot={ 10,20,-25},
			color=Color3.fromRGB(190,150,240), material=Enum.Material.Glass, trans=0.2, refl=0.3 },        -- flank shards
		{ shape="Block", size={0.16,0.48,0.16}, pos={ 0.62,0.25,0.30}, rot={ -8,-30,22},
			color=Color3.fromRGB(220,185,255), material=Enum.Material.Glass, trans=0.2, refl=0.3 },
		{ shape="Block", size={0.14,0.40,0.14}, pos={ 0.30,0.42,0.58}, rot={-22,45, 12},
			color=Color3.fromRGB(175,135,235), material=Enum.Material.Glass, trans=0.2, refl=0.3 },        -- small back shard
	} },
	bolts = { attach = "Head", parts = {
		{ shape="Cylinder", size={0.34,0.07,0.07}, pos={0,0.42,0}, rot={0,0,90},
			color=Color3.fromRGB(120,126,138), material=Enum.Material.Metal, refl=0.3 },        -- antenna mast
		{ shape="Ball", size={0.16,0.16,0.16}, pos={0,0.62,0},
			color=Color3.fromRGB(90,220,255), material=Enum.Material.Neon },                    -- antenna bulb
		{ shape="Ball", size={0.14,0.14,0.14}, pos={-1.00,-0.12,0}, attach="Body",
			color=Color3.fromRGB(110,116,128), material=Enum.Material.Metal, refl=0.4 },        -- side rivets
		{ shape="Ball", size={0.14,0.14,0.14}, pos={ 1.00,-0.12,0}, attach="Body",
			color=Color3.fromRGB(110,116,128), material=Enum.Material.Metal, refl=0.4 },
		-- the personality half: a control panel with blinky buttons on the CHEST LINE (Neck attach --
		-- guaranteed below the face on every pet) and a little back vent
		{ shape="Block", size={0.60,0.45,0.18}, pos={0,-0.05,0.03}, attach="Neck",
			color=Color3.fromRGB(88,94,106), material=Enum.Material.Metal, refl=0.2 },          -- chest panel, tucked into the chest plane
		{ shape="Ball", size={0.12,0.12,0.12}, pos={-0.18,-0.02,-0.04}, attach="Neck",
			color=Color3.fromRGB(255,80,80),  material=Enum.Material.Neon },                    -- panel lights
		{ shape="Ball", size={0.12,0.12,0.12}, pos={0,-0.02,-0.04}, attach="Neck",
			color=Color3.fromRGB(255,220,90), material=Enum.Material.Neon },
		{ shape="Ball", size={0.12,0.12,0.12}, pos={ 0.18,-0.02,-0.04}, attach="Neck",
			color=Color3.fromRGB(90,220,255), material=Enum.Material.Neon },
		{ shape="Block", size={0.40,0.26,0.10}, pos={0,0.05,1.00}, attach="Body",
			color=Color3.fromRGB(70,76,88), material=Enum.Material.Metal, refl=0.15 },          -- back vent
	} },
	-- CANDY: bright gumdrops stuck ON the body surface -- the skin should read as candy from across the island
	candy = { attach = "Body", parts = {
		{ shape="Ball", size={0.24,0.24,0.24}, pos={-0.66,0.66,-0.36}, color=Color3.fromRGB(255, 80, 90),  material=Enum.Material.SmoothPlastic, refl=0.15 },
		{ shape="Ball", size={0.20,0.20,0.20}, pos={ 0.66,0.59, 0.46}, color=Color3.fromRGB(255,220, 70),  material=Enum.Material.SmoothPlastic, refl=0.15 },
		{ shape="Ball", size={0.22,0.22,0.22}, pos={ 0.18,0.85,-0.49}, color=Color3.fromRGB( 90,220,255),  material=Enum.Material.SmoothPlastic, refl=0.15 },
		{ shape="Ball", size={0.18,0.18,0.18}, pos={-0.61,0.41, 0.68}, color=Color3.fromRGB(120,235,110),  material=Enum.Material.SmoothPlastic, refl=0.15 },
		{ shape="Ball", size={0.20,0.20,0.20}, pos={ 0.77,0.26,-0.58}, color=Color3.fromRGB(200,110,255),  material=Enum.Material.SmoothPlastic, refl=0.15 },
		{ shape="Ball", size={0.18,0.18,0.18}, pos={-0.31,0.23,-0.92}, color=Color3.fromRGB(255,150, 60),  material=Enum.Material.SmoothPlastic, refl=0.15 },
	} },
	-- TOXIC: bubbling neon boils ON the surface -- the sludge is visibly ALIVE
	boils = { attach = "Body", parts = {
		{ shape="Ball", size={0.30,0.30,0.30}, pos={-0.65,0.65,-0.39}, color=Color3.fromRGB(150,255, 60), material=Enum.Material.Neon },
		{ shape="Ball", size={0.20,0.20,0.20}, pos={ 0.75,0.48, 0.41}, color=Color3.fromRGB(120,235, 40), material=Enum.Material.Neon },
		{ shape="Ball", size={0.24,0.24,0.24}, pos={ 0.13,0.87,-0.45}, color=Color3.fromRGB(170,255, 90), material=Enum.Material.Neon },
		{ shape="Ball", size={0.16,0.16,0.16}, pos={-0.59,0.29, 0.74}, color=Color3.fromRGB(140,245, 50), material=Enum.Material.Neon },
		{ shape="Ball", size={0.18,0.18,0.18}, pos={ 0.64,0.14,-0.71}, color=Color3.fromRGB(120,235, 40), material=Enum.Material.Neon },
	} },
	-- COSMIC: the galaxy on the body -- glowing NEBULA cloud patches in purple/pink/teal and tiny white
	-- star studs. (The circling planets + stars are the skin's ORBIT, not deco -- orbiters leave gaps as
	-- they move, so the pet's own features stay visible; the old solid rings covered them.)
	cosmos = { attach = "Body", parts = {
		{ shape="Ball", size={0.42,0.42,0.42}, pos={-0.60,0.60,-0.35}, trans=0.55,
			color=Color3.fromRGB(190,110,255), material=Enum.Material.Neon },                   -- nebula clouds
		{ shape="Ball", size={0.34,0.34,0.34}, pos={ 0.68,0.42, 0.42}, trans=0.55,
			color=Color3.fromRGB(255,120,200), material=Enum.Material.Neon },
		{ shape="Ball", size={0.38,0.38,0.38}, pos={ 0.15,0.80,-0.45}, trans=0.60,
			color=Color3.fromRGB( 90,200,255), material=Enum.Material.Neon },
		{ shape="Ball", size={0.28,0.28,0.28}, pos={-0.55,0.25, 0.60}, trans=0.55,
			color=Color3.fromRGB(150, 90,240), material=Enum.Material.Neon },
		{ shape="Ball", size={0.10,0.10,0.10}, pos={ 0.72,0.15,-0.55}, color=Color3.fromRGB(255,255,255), material=Enum.Material.Neon }, -- star studs
		{ shape="Ball", size={0.09,0.09,0.09}, pos={-0.30,0.75, 0.40}, color=Color3.fromRGB(255,255,255), material=Enum.Material.Neon },
		{ shape="Ball", size={0.08,0.08,0.08}, pos={ 0.35,0.30, 0.72}, color=Color3.fromRGB(255,255,255), material=Enum.Material.Neon },
		{ shape="Ball", size={0.09,0.09,0.09}, pos={-0.70,0.45,-0.20}, color=Color3.fromRGB(255,255,255), material=Enum.Material.Neon },
	} },
	-- ANCIENT: glowing gold rune marks carved into the stone surface
	runes = { attach = "Body", parts = {
		{ shape="Block", size={0.10,0.42,0.06}, pos={-0.78,0.52,-0.45}, rot={  0, 20, 15}, color=Color3.fromRGB(255,206, 92), material=Enum.Material.Neon },
		{ shape="Block", size={0.34,0.10,0.06}, pos={-0.76,0.24,-0.50}, rot={  0, 20,  0}, color=Color3.fromRGB(255,206, 92), material=Enum.Material.Neon },
		{ shape="Block", size={0.10,0.38,0.06}, pos={ 0.80,0.47, 0.40}, rot={  0,-25,-12}, color=Color3.fromRGB(255,190, 70), material=Enum.Material.Neon },
		{ shape="Block", size={0.28,0.10,0.06}, pos={ 0.19,0.68,-0.70}, rot={  0, 60,  0}, color=Color3.fromRGB(255,206, 92), material=Enum.Material.Neon },
	} },
}

-- SURFACE PUSH: the studs-on-the-body decos (gumdrops, boils, shards, runes) were authored for an
-- ellipsoid surface, but the union pet bodies are rounded CUBES -- their diagonal surface sits ~30%
-- further out, and the /scanpet x-ray showed every one of these partly sunk on every pet. Pushing the
-- authored points out here (once, at load) keeps the tables readable. Only default-Body parts move;
-- anything with an explicit attach override (Robot's rivets/vent, Jungle's old flower) is positioned
-- deliberately and stays put.
for name, deco in pairs(SKIN_DECO) do
	if deco.attach == "Body" then
		local push = (name == "candy") and 1.4 or 1.3 -- the small gumdrops need a touch more to break the surface
		for _, spec in ipairs(deco.parts) do
			if not spec.attach and spec.pos then
				spec.pos = { spec.pos[1] * push, spec.pos[2] * push, spec.pos[3] * push }
			end
		end
	end
end

-- ORBITERS, shared by traits (Celestial's stars, Titan's rocks) and skins (Cosmic's planets). `items`
-- lets each orbiter carry its own size/colour/material -- a ring of planets AND stars from one spec --
-- while the plain count/size/color form still works for uniform rings.
local function buildOrbit(model, root, o)
	local parts = {}
	local items = o.items
	local count = if items then #items else (o.count or 3)
	for i = 1, count do
		local it = items and items[i]
		local sz = (it and it.size) or o.size or 0.25
		local p = Instance.new("Part")
		p.Name = "PetSkinOrb"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(sz, sz, sz)
		p.Color = (it and it.color) or o.color or Color3.new(1, 1, 1)
		local neon = if it ~= nil then it.neon else o.neon
		p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true
		p.CFrame = root.CFrame
		p.Parent = model
		parts[i] = p
	end
	orbiting[model] = { parts = parts, radius = o.radius or 2, speed = o.speed or 3, root = root }
	print("[PetSkinLook] orbit built: " .. count .. " orbiter(s), radius " .. tostring(o.radius or 2))
end

-- `static` = colour/material only paint for reels + icons; effects (emitters/lights/animation registration)
-- are skipped there but the deco GEOMETRY still builds -- it is part of the skin's identity, and a Crystal
-- pet without its shards is just purple.
local function applySkin(model, petId, skinId, static)
	local skin = PetSkins.get(skinId)
	if not skin then return end
	local parts = bodyParts(model)
	for _, p in ipairs(parts) do
		snapshot(p)
		if skin.color then p.Color = skin.color end
		if skin.material then p.Material = skin.material end
		p.Reflectance = skin.refl or 0
		if skin.trans then p.Transparency = skin.trans end
	end
	if skin.deco and SKIN_DECO[skin.deco] then
		local d = SKIN_DECO[skin.deco]
		buildAccessoryParts(model, petId, d.parts, d.attach, static, "PetSkinDeco")
	end
	if static then return end

	local root = model.PrimaryPart
	-- an ambient tint particle for the flashier skins (the same `fx` field PetFollow's RARE_LOOK uses)
	if skin.fx and root then
		local e = Instance.new("ParticleEmitter")
		e.Name = "PetSkinFX"
		e.Color = ColorSequence.new(skin.fx)
		e.LightEmission = 0.8
		e.Rate = 18
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(0.4, 1.2)
		e.Size = NumberSequence.new(0.35)
		e.Rotation = NumberRange.new(0, 360)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = root
	end
	-- the skin's OWN flavour emitter (Lava embers, Ocean bubbles, Toxic drips...)
	if skin.particle and root then
		buildParticle(root, skin.particle, "PetSkinFX")
	end
	if skin.light and root then
		local pl = Instance.new("PointLight")
		pl.Name = "PetSkinLight"
		pl.Color = skin.fx or skin.color or Color3.new(1, 1, 1)
		pl.Brightness = 1.5 * 0.75 -- pet glow runs 25% down across the board (see PetFollow's note by RARE_DIM)
		pl.Range = 12
		pl.Parent = root
	end
	-- RIBBON TRAIL (Rainbow's signature): a fixed multi-stop rainbow gradient, so no per-frame cost -- the
	-- ribbon itself carries every colour at once while the body cycles.
	if skin.trail and root then
		local a0 = Instance.new("Attachment"); a0.Name = "PetSkinTrailA0"; a0.Position = Vector3.new(0, 0.8, 0); a0.Parent = root
		local a1 = Instance.new("Attachment"); a1.Name = "PetSkinTrailA1"; a1.Position = Vector3.new(0, -0.8, 0); a1.Parent = root
		local tr = Instance.new("Trail")
		tr.Name = "PetSkinTrail"; tr.Attachment0 = a0; tr.Attachment1 = a1
		tr.Lifetime = 0.9; tr.LightEmission = 0.7; tr.FaceCamera = true
		tr.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  70,  70)),
			ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 170,  60)),
			ColorSequenceKeypoint.new(0.40, Color3.fromRGB(255, 240,  80)),
			ColorSequenceKeypoint.new(0.60, Color3.fromRGB( 90, 230, 110)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB( 80, 160, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(190, 110, 255)),
		})
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1),
		})
		tr.Parent = root
	end
	-- ORBITERS on skins (Cosmic's planets + stars). If the equipped TRAIT also orbits (Celestial, Titan),
	-- the trait applies after the skin and takes the ring -- one orbit per pet keeps it readable.
	if skin.orbit and root then
		buildOrbit(model, root, skin.orbit)
	end
	-- TIER TRAILS: flying with a Rare or better skin should be VISIBLE from across the island.
	--   Rare      -> a glitter trail (world-space sparkles that linger where the pet flew) + a thin line
	--   Legendary -> a bold line trail in the skin's colour
	-- Rainbow keeps its authored multi-colour ribbon instead of the generic line.
	local tint = skin.fx or skin.color or Color3.new(1, 1, 1)
	if root and skin.tier == "Rare" then
		local em = Instance.new("ParticleEmitter")
		em.Name = "PetSkinFX"
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.Color = ColorSequence.new(tint)
		em.Size = NumberSequence.new(0.28)
		em.Rate = 12
		em.Speed = NumberRange.new(0.2, 0.6)
		em.Lifetime = NumberRange.new(0.6, 1.0)
		em.SpreadAngle = Vector2.new(180, 180)
		em.LightEmission = 0.6
		em.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1),
		})
		em.Parent = root
	end
	if root and not skin.trail and (skin.tier == "Rare" or skin.tier == "Legendary") then
		local bold = skin.tier == "Legendary"
		local off = bold and 0.8 or 0.5
		local a0 = Instance.new("Attachment"); a0.Name = "PetSkinTrailA0"; a0.Position = Vector3.new(0, off, 0); a0.Parent = root
		local a1 = Instance.new("Attachment"); a1.Name = "PetSkinTrailA1"; a1.Position = Vector3.new(0, -off, 0); a1.Parent = root
		local tr = Instance.new("Trail")
		tr.Name = "PetSkinTrail"; tr.Attachment0 = a0; tr.Attachment1 = a1
		tr.Lifetime = bold and 0.8 or 0.45
		tr.LightEmission = 0.7; tr.FaceCamera = true
		tr.Color = ColorSequence.new(tint)
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, bold and 0.4 or 0.6), NumberSequenceKeypoint.new(1, 1),
		})
		tr.Parent = root
	end
	if skin.animated then
		animated[model] = { mode = skin.animated, parts = parts }
	end
end

-- ============================================================================================================
-- TRAIT
-- ============================================================================================================
-- Builds the trait's accessory set (always -- it IS the trait) plus its flavour effects (live pets only).
local function applyTrait(model, petId, traitId, static)
	if PetTraits.isNone(traitId) then return end
	local t = PetTraits.get(traitId)
	if not t then return end
	local root = model.PrimaryPart
	if not root then return end

	buildAccessoryParts(model, petId, t.parts, t.attach, static, "PetSkinAcc")
	if static then return end

	if t.particle then buildParticle(root, t.particle, "PetSkinTraitFX") end

	if t.sparkles then
		local s = Instance.new("Sparkles")
		s.Name = "PetSkinSparkles"
		s.SparkleColor = t.sparkles
		s.Parent = root
	end

	if t.light then
		local pl = Instance.new("PointLight")
		pl.Name = "PetSkinLight" -- shares the skin light's name on purpose: clearLook removes both in one pass
		pl.Color = t.light.color or Color3.new(1, 1, 1)
		pl.Brightness = (t.light.brightness or 1.5) * 0.75
		pl.Range = t.light.range or 10
		pl.Parent = root
	end

	if t.orbit then
		buildOrbit(model, root, t.orbit)
	end
end

-- ============================================================================================================
-- THE ENTRY POINT PetFollow CALLS
-- ============================================================================================================
-- Idempotent: it clears its own previous work first, so PetFollow can call it on every rebuild and every level
-- change without effects piling up. `lite` (icon clones) gets the skin recolour + the accessory GEOMETRY --
-- the trait has to be readable on an inventory icon -- but no particles/lights/orbits, which don't render
-- usefully in a static ViewportFrame and would just cost frame time.
_G.applyPetSkinLook = function(model, petId, lite)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	clearLook(model)
	painted[model] = petId

	-- non-lite paints are LIVE FOLLOWERS (icons pass lite=true; remote pets go through the preview path):
	-- a different species arriving here means the player switched pets -- a real action the try-on yields to
	if not lite then
		if lastLivePetId ~= nil and petId ~= lastLivePetId and dropTryOn then dropTryOn("pet switched") end
		lastLivePetId = petId
	end

	local e = tryOn or equipped[petId] -- the dev try-on outranks the real equip (local preview only)
	if e and e.skin then
		applySkin(model, petId, e.skin, lite)
		applyTrait(model, petId, e.trait, lite)
	end

	-- LAST, and unconditionally. A pet with no skin needs the dim just as much as one with a skin, and doing
	-- it after applySkin means a skin's own colour comes down by the same 25% -- otherwise equipping a skin
	-- would make a pet suddenly brighter than every unskinned one.
	dimBody(model)
end

-- Paint a model with an ARBITRARY skin + trait, independent of what the player has EQUIPPED. This is what the
-- crate reel, the reveal card, the inventory rows, remote players' pets and /testpet need: they describe an
-- item, so they must show that item, not whatever the pet happens to be wearing.
--
-- `static` (the reel + inventory + /testpet case) paints colour/material and builds the accessory GEOMETRY,
-- placed once -- no emitters, no lights, no hue-cycling registration, no follow loop. The reveal card and
-- remote pets pass static=false, so live models get the full treatment.
--
-- The pet species for PET_OFFSETS is read off the model itself: buildPetModel names its clones after the
-- species, and anything that renames one (RemotePets) stamps a "PetSpecies" attribute instead.
_G.applyPetSkinPreview = function(model, skinId, traitId, static)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	clearLook(model)
	-- Deliberately NOT recorded in `painted`. repaintAll() walks that table on every server push and would
	-- repaint these to the EQUIPPED skin -- turning a Candy Maple Fox in the reel into whatever the player
	-- is wearing, which is precisely the bug this function exists to avoid.
	local petId = model:GetAttribute("PetSpecies") or model.Name
	if skinId and PetSkins.exists(skinId) then
		applySkin(model, petId, skinId, static and true or false)
	end
	applyTrait(model, petId, traitId, static and true or false)
end

-- BADGE HELPER: the ONE Overall Tier for a pet's equipped skin + trait, for the overhead nameplate
-- ("Baby \xC2\xB7 Legendary"). Computed from the hidden skin/trait values through PetTier -- never two labels
-- stacked above a pet. nil when nothing is equipped, and the badge shows age alone. On _G so PetFollow can
-- read it without requiring the modules itself -- that file sits at the edge of Luau's 200-locals ceiling.
_G.petSkinRarityOf = function(petId)
	local e = tryOn or equipped[petId] -- the try-on shows its real Overall Tier on the badge too
	if not e then return nil, nil end
	return PetTier.overall(e.skin, e.trait)
end

-- The same computation for an ARBITRARY pair -- RemotePets uses this for other players' nameplates, and the
-- crate/inventory UI for its tier chips. Also published as data so UIs can print "Overall Tier: X" rows.
_G.petSkinOverallTier = function(skinId, traitId)
	return PetTier.overall(skinId, traitId)
end

-- Repaint every model we've already painted. Called when the server pushes a new equip state -- there's no level
-- change in that case, so PetFollow won't rebuild and wouldn't otherwise call us.
local function repaintAll()
	for model, petId in pairs(painted) do
		if model.Parent then
			_G.applyPetSkinLook(model, petId, false)
		end
	end
end

-- DEV TRY-ON entry point ( /testpet's TRY buttons ). petSkinTryOn(skinId, traitId) paints the combo onto
-- every live pet this client renders; petSkinTryOn(nil) restores the real equip. The evo refresh + repaint
-- run immediately, exactly as they do when the server pushes a real equip change.
-- Sits BELOW repaintAll on purpose: declared above it, `repaintAll()` here would compile as a GLOBAL read,
-- come back nil, and error on the first TRY press -- the classic local-ordering trap this file's siblings
-- keep warning about.
_G.petSkinTryOn = function(skinId, traitId)
	if skinId == nil or skinId == false then
		tryOn = nil
	else
		local skin = PetSkins.normalise(skinId)
		if not skin then return false end
		local trait = PetTraits.normalise(traitId)
		tryOn = { skin = skin, trait = trait ~= "" and trait or nil }
	end
	if _G.petEvoRefresh then pcall(_G.petEvoRefresh) end
	repaintAll()
	return true
end

-- THE YIELD (see the try-on header): clears the preview because the player took a REAL action -- equipped
-- or unequipped a skin, or switched which pet follows them. Clearing is synchronous so the paint that
-- detected it already renders the truth; the deferred refresh sweeps every other painted model, deferred
-- because this can fire from INSIDE applyPetSkinLook and a re-entrant repaintAll would repaint mid-paint.
dropTryOn = function(why)
	if not tryOn then return end
	tryOn = nil
	task.defer(function()
		if _G.petEvoRefresh then pcall(_G.petEvoRefresh) end
		repaintAll()
	end)
	if _G.showHudBanner then
		pcall(_G.showHudBanner, "Try-on cleared -- showing your real equip", Color3.fromRGB(205, 224, 255), 3)
	end
	print("[PetSkinLook] try-on cleared (" .. tostring(why) .. ")")
end

-- ===== LIVE ADJUST (the /testpet ADJUST mode) =====
-- Nudge one attach point of one pet while looking at it: dx/dy/dz in that attach's own units, dscale
-- multiplies size AND reach. Accumulates for the session and repaints instantly.
_G.petSkinAdjust = function(petId, attach, dx, dy, dz, dscale)
	if type(petId) ~= "string" or type(attach) ~= "string" then return nil end
	local perPet = liveAdjust[petId]
	if not perPet then perPet = {}; liveAdjust[petId] = perPet end
	local o = perPet[attach]
	if not o then o = { x = 0, y = 0, z = 0, scale = 1 }; perPet[attach] = o end
	o.x = o.x + (tonumber(dx) or 0)
	o.y = o.y + (tonumber(dy) or 0)
	o.z = o.z + (tonumber(dz) or 0)
	o.scale = math.clamp(o.scale + (tonumber(dscale) or 0), 0.3, 3)
	if _G.petEvoRefresh then pcall(_G.petEvoRefresh) end
	repaintAll()
	return o
end

-- Prints the pet's accumulated nudges as a paste-ready PetTraits.PET_OFFSETS entry, so a tuning session
-- ends in config, not in memory.
_G.petSkinAdjustDump = function(petId)
	local perPet = petId and liveAdjust[petId]
	if not perPet then print("[PetSkinLook] no live adjustments for " .. tostring(petId)); return end
	local lines = { "\t" .. petId .. " = {" }
	for attach, o in pairs(perPet) do
		lines[#lines + 1] = string.format("\t\t%s = { pos = {%.2f, %.2f, %.2f}, scale = %.2f },",
			attach, o.x, o.y, o.z, o.scale)
	end
	lines[#lines + 1] = "\t},"
	print("[PetSkinLook] PASTE INTO PetTraits.PET_OFFSETS:\n" .. table.concat(lines, "\n"))
end

-- ============================================================================================================
-- ANIMATION LOOP (one connection for every pet)
-- ============================================================================================================
-- Rainbow / cosmic hue cycling, orbiting trait parts, and the accessory follow all ride one RenderStepped.
-- It exits immediately when nothing is registered, so a player with no animated skin and no accessories pays
-- essentially nothing.
do
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t = t + dt

		-- animated skins. Each mode decides a BODY colour (nil = leave the body alone) and an FX colour for
		-- the light/emitters. Cosmic is the special one: the deep-space body NEVER cycles -- only its stars
		-- and aura swirl through the vivid rainbow, the exact treatment the old Cosmic Duck rare wore.
		-- Cycling the body too is what made Cosmic read as "basically Rainbow".
		for model, info in pairs(animated) do
			if model.Parent then
				local mode = info.mode
				local bodyC, fxC
				if mode == "cosmic" then
					fxC = Color3.fromHSV((t * 0.40) % 1, 0.70, 1)                                   -- the aura swirl
				elseif mode == "pastel" then
					bodyC = Color3.fromHSV((t * 0.06) % 1, 0.30, 1); fxC = bodyC                    -- dreamy soft drift
				elseif mode == "ocean" then
					bodyC = Color3.fromHSV(0.56 + math.sin(t * 1.3) * 0.035, 0.75, 0.85); fxC = bodyC -- rolling swell
				elseif mode == "jungle" then
					-- canopy light: the green slowly BREATHES between deep jungle shade and sunlit leaf,
					-- and the firefly glow FLICKERS warm yellow like the real thing
					bodyC = Color3.fromHSV(0.31 + math.sin(t * 0.8) * 0.025, 0.72, 0.55 + math.sin(t * 0.8) * 0.10)
					fxC = Color3.fromHSV(0.135, 0.50, 0.72 + math.sin(t * 2.6) * 0.26)
				elseif mode == "lava" then
					bodyC = Color3.fromHSV(0.035 + math.sin(t * 2.2) * 0.015, 1, 0.66 + math.sin(t * 2.2) * 0.16) -- molten pulse
					fxC = bodyC
				else -- rainbow: fast and bright
					bodyC = Color3.fromHSV((t * 0.35) % 1, 0.85, 1); fxC = bodyC
				end
				if bodyC then
					for _, p in ipairs(info.parts) do
						if p.Parent then p.Color = bodyC end
					end
				end
				local root = model.PrimaryPart
				if root and fxC then
					local pl = root:FindFirstChild("PetSkinLight")
					if pl and pl:IsA("PointLight") then pl.Color = fxC end
					if mode == "cosmic" then -- the stars ride the cycle too; other modes keep authored FX colours
						for _, ch in ipairs(root:GetChildren()) do
							if ch.Name == "PetSkinFX" and ch:IsA("ParticleEmitter") then
								ch.Color = ColorSequence.new(fxC)
							end
						end
					end
				end
			else
				animated[model] = nil
			end
		end

		-- orbiting trait parts (Celestial's stars)
		for model, o in pairs(orbiting) do
			local root = o.root
			if model.Parent and root and root.Parent then
				local rootCF = root.CFrame
				local n = #o.parts
				for i, p in ipairs(o.parts) do
					if p.Parent then
						local a = t * o.speed + (i - 1) * (2 * math.pi / math.max(1, n))
						-- gentle wave in the orbit so the ring visibly LOOPS instead of sliding flat
						p.CFrame = rootCF * CFrame.new(math.cos(a) * o.radius, 0.6 + math.sin(a * 2) * 0.3, math.sin(a) * o.radius)
					end
				end
			else
				orbiting[model] = nil
			end
		end

		-- accessory sets (trait gear + skin deco) ride the pet as rigid assemblies: one attach-frame multiply
		-- per group, one CFrame write per part. All offsets were precomputed at build time. Parts marked
		-- `sway` get the wind treatment: a gentle hinged flutter about their top edge.
		for model, reg in pairs(accessorised) do
			local root = reg.root
			if model.Parent and root and root.Parent then
				local rootCF = root.CFrame
				for _, g in ipairs(reg.groups) do
					-- anchored groups ride their real body part (waddle and all); the root is the fallback
					local base
					if g.anchor and g.anchor.Parent then base = g.anchor.CFrame * g.rel
					else base = rootCF * g.cf end
					for _, e in ipairs(g.parts) do
						if e.part.Parent then
							if e.sway then
								local sp = e.sway.speed or 2.2
								local amp = e.sway.amp or 6
								local a = math.rad(math.sin(t * sp + e.phase) * amp)
								local b = math.rad(math.sin(t * sp * 0.6 + e.phase) * amp * 0.35)
								e.part.CFrame = base * e.off
									* CFrame.new(0, e.hinge, 0) * CFrame.Angles(a, 0, b) * CFrame.new(0, -e.hinge, 0)
							else
								e.part.CFrame = base * e.off
							end
						end
					end
				end
			else
				accessorised[model] = nil
			end
		end
	end)
end

-- ============================================================================================================
-- STATE
-- ============================================================================================================
local function applyState(state)
	if type(state) ~= "table" then return end
	equipped = {}
	for petId, e in pairs(state.equipped or {}) do
		if type(e) == "table" and type(e.skin) == "string" then
			-- Normalised on arrival: an old save's "Galaxy"/"Crowned" paints as its modern identity even if a
			-- stale server payload slips one through (the server migrates on join too -- defence in depth).
			local skin = PetSkins.normalise(e.skin)
			local trait = PetTraits.normalise(e.trait or (type(e.traits) == "table" and e.traits[1]) or "")
			if skin then
				equipped[petId] = { skin = skin, trait = trait ~= "" and trait or nil }
			end
		end
	end
	-- A REAL equip change while a try-on is active means the player is acting on their actual pet, so the
	-- preview yields. Signature-compared because this event also fires for token/collection/level pushes
	-- that change no equip -- those must NOT eat the try-on mid-walk.
	local sigParts = {}
	for petId, e in pairs(equipped) do
		sigParts[#sigParts + 1] = petId .. "=" .. e.skin .. "|" .. (e.trait or "")
	end
	table.sort(sigParts)
	local sig = table.concat(sigParts, ",")
	if lastEquipSig ~= nil and sig ~= lastEquipSig and dropTryOn then dropTryOn("equip changed") end
	lastEquipSig = sig

	_G.petSkinEquipped = equipped
	_G.petSkinState = state
	-- Tell the Pet Hub its open detail card is stale. Fired here rather than from the equip button because
	-- THIS is the moment the server has confirmed the change -- the button only asks, and a request the
	-- server refuses (pet still locked, skin not owned) must not flip the list to "ON".
	if _G.petHubSkinsChanged then pcall(_G.petHubSkinsChanged) end -- the crate/inventory UI reads tokens + owned entries from here
	-- FULL evo re-run BEFORE the repaint: trait accessories sit ON TOP of the level particle stack, so an
	-- equip/unequip must rebuild the level effects now, not on the next level-up. petEvoRefresh ends by
	-- re-applying the skin itself, and repaintAll still covers painted models that aren't live followers
	-- (viewport icons and the like).
	if _G.petEvoRefresh then pcall(_G.petEvoRefresh) end
	repaintAll()
end

if SkinStateEvent then
	SkinStateEvent.OnClientEvent:Connect(applyState)
end

-- Initial fetch, so a pet already following at join gets its skin without waiting for a push.
task.spawn(function()
	if not GetSkinState then return end
	local ok, state = pcall(function() return GetSkinState:InvokeServer() end)
	if ok then applyState(state) end
end)

print("[PetSkinLook] renderer ready (" .. #PetSkins.Order .. " skins, " .. #PetTraits.TRAITS .. " traits)")
