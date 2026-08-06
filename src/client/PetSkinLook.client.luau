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
-- WHAT A SKIN DOES        recolour + material + reflectance on the BODY parts (eyes, accessories and level FX are
--                         skipped -- the same exclusion list PetFollow's own applyRareLook uses).
-- WHAT A TRAIT DOES       particles / sparkles / light / orbiting parts / a floating halo or crown. Never a body
--                         change, so every trait works on every pet, including pets added later.
--
-- ORIGINALS ARE SNAPSHOTTED before the first recolour, so switching skins (or clearing one) restores the pet's
-- real colours rather than stacking tints.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

local Shared    = ReplicatedStorage:WaitForChild("DinosaurRealm")
local PetSkins  = require(Shared:WaitForChild("PetSkins"))
local PetTraits = require(Shared:WaitForChild("PetTraits"))

local SkinRemotes    = ReplicatedStorage:WaitForChild("SkinRemotes", 30)
local GetSkinState   = SkinRemotes and SkinRemotes:WaitForChild("GetSkinState", 10)
local SkinStateEvent = SkinRemotes and SkinRemotes:WaitForChild("SkinStateEvent", 10)

-- ===== LOCAL VIEW OF SERVER STATE =====
-- equipped[petId] = { skin = "Galaxy", trait = "Crowned" }. Authoritative copy lives on the server; this is only
-- what we were last told, and it is never used to decide what the player OWNS -- only what to draw.
local equipped = {}
_G.petSkinEquipped = equipped -- read by the crate/inventory UI so it doesn't need its own copy

-- Every pet model this script has painted, so an equip change can repaint without searching Workspace.
-- Weak keys: when PetFollow destroys a pet the entry disappears on its own.
local painted = setmetatable({}, { __mode = "k" }) -- [model] = petId

-- Original appearance per part, so a skin change restores instead of stacking. Weak keys again.
local originals = setmetatable({}, { __mode = "k" }) -- [part] = { color, material, refl }

-- Models with an animated skin (rainbow / cosmic hue cycling) and models with orbiting trait parts.
local animated = setmetatable({}, { __mode = "k" }) -- [model] = { mode, parts = {...} }
local orbiting = setmetatable({}, { __mode = "k" }) -- [model] = { parts = {...}, radius, speed, root }
local flickering = setmetatable({}, { __mode = "k" }) -- [model] = light

-- Parts a recolour must NEVER touch. Same list PetFollow's applyRareLook uses, so the two agree on what counts
-- as "the body": eyes stay white, accessories keep their own colours, level FX keep theirs.
local SKIP_NAMES = {
	Eye = true, Pupil = true, Highlight = true, EvoPart = true,
	PetOrb = true, PetRing = true, PetPulse = true,
	-- this script's own additions, so a repaint never recolours its own effects
	PetSkinOrb = true, PetSkinHalo = true, PetSkinCrown = true,
}

local FX_NAMES = {
	"PetSkinFX", "PetSkinLight", "PetSkinSparkles", "PetSkinOrb", "PetSkinHalo", "PetSkinCrown", "PetSkinTraitFX",
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
	flickering[model] = nil
	-- restore original body appearance
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local o = originals[d]
			if o then
				d.Color = o.color; d.Material = o.material; d.Reflectance = o.refl
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

local function applySkin(model, skinId)
	local skin = PetSkins.get(skinId)
	if not skin then return end
	local parts = bodyParts(model)
	for _, p in ipairs(parts) do
		if not originals[p] then
			originals[p] = { color = p.Color, material = p.Material, refl = p.Reflectance }
		end
		if skin.color then p.Color = skin.color end
		if skin.material then p.Material = skin.material end
		p.Reflectance = skin.refl or 0
	end
	-- an ambient tint particle for the flashier skins (the same `fx` field PetFollow's RARE_LOOK uses)
	local root = model.PrimaryPart
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
	if skin.light and root then
		local pl = Instance.new("PointLight")
		pl.Name = "PetSkinLight"
		pl.Color = skin.fx or skin.color or Color3.new(1, 1, 1)
		pl.Brightness = 1.5
		pl.Range = 12
		pl.Parent = root
	end
	if skin.animated then
		animated[model] = { mode = skin.animated, parts = parts }
	end
end

-- ============================================================================================================
-- TRAIT
-- ============================================================================================================
local function applyTrait(model, traitId)
	if PetTraits.isNone(traitId) then return end
	local t = PetTraits.get(traitId)
	if not t then return end
	local root = model.PrimaryPart
	if not root then return end

	if t.particle then
		local p = t.particle
		local e = Instance.new("ParticleEmitter")
		e.Name = "PetSkinTraitFX"
		e.Texture = p.texture or "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(p.color or Color3.new(1, 1, 1))
		e.LightEmission = 0.7
		e.Rate = p.rate or 12
		e.Speed = NumberRange.new(p.speed or 1)
		e.Lifetime = NumberRange.new((p.lifetime or 1) * 0.7, p.lifetime or 1)
		e.Size = NumberSequence.new(p.size or 1)
		e.SpreadAngle = Vector2.new(p.spread or 15, p.spread or 15)
		e.Rotation = NumberRange.new(0, 360)
		e.Acceleration = p.accel or Vector3.new()
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, p.transparency or 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Parent = root
	end

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
		pl.Brightness = t.light.brightness or 1.5
		pl.Range = t.light.range or 10
		pl.Parent = root
		if t.flicker then flickering[model] = pl end
	end

	if t.orbit then
		local o = t.orbit
		local parts = {}
		for i = 1, (o.count or 3) do
			local p = Instance.new("Part")
			p.Name = "PetSkinOrb"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(o.size or 0.25, o.size or 0.25, o.size or 0.25)
			p.Color = o.color or Color3.new(1, 1, 1)
			p.Material = o.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.CastShadow = false; p.Massless = true
			p.CFrame = root.CFrame
			p.Parent = model
			parts[i] = p
		end
		orbiting[model] = { parts = parts, radius = o.radius or 2, speed = o.speed or 3, root = root }
	end

	if t.halo then
		local h = t.halo
		if t.crown then
			-- A floating CROWN: a thin band plus five little spikes, hovering above the pet. Deliberately an
			-- accessory in the air rather than something welded to the head -- that's what keeps it working on a
			-- crab, a bean and a dragon alike, with no per-pet placement.
			local band = Instance.new("Part")
			band.Name = "PetSkinCrown"; band.Shape = Enum.PartType.Cylinder
			band.Size = Vector3.new(0.16, (h.size or 1.5) * 0.62, (h.size or 1.5) * 0.62)
			band.Color = h.color or Color3.fromRGB(255, 206, 92)
			band.Material = Enum.Material.Metal; band.Reflectance = 0.3
			band.Anchored = true; band.CanCollide = false; band.CanQuery = false; band.CanTouch = false
			band.CastShadow = false; band.Massless = true
			band.CFrame = root.CFrame * CFrame.new(0, (h.size or 1.5) * 1.5, 0) * CFrame.Angles(0, 0, math.rad(90))
			band.Parent = model
			for k = 0, 4 do
				local ang = math.rad(k * 72)
				local spike = Instance.new("Part")
				spike.Name = "PetSkinCrown"; spike.Shape = Enum.PartType.Block
				spike.Size = Vector3.new(0.12, 0.34, 0.12)
				spike.Color = band.Color; spike.Material = Enum.Material.Metal; spike.Reflectance = 0.3
				spike.Anchored = true; spike.CanCollide = false; spike.CanQuery = false; spike.CanTouch = false
				spike.CastShadow = false; spike.Massless = true
				spike.CFrame = band.CFrame * CFrame.Angles(math.rad(90), 0, 0)
					* CFrame.new(math.cos(ang) * (h.size or 1.5) * 0.31, 0.22, math.sin(ang) * (h.size or 1.5) * 0.31)
				spike.Parent = model
			end
			-- one shared orbit entry keeps the crown pinned above the pet as it moves (radius 0 = stay centred)
			local all = {}
			for _, d in ipairs(model:GetChildren()) do if d.Name == "PetSkinCrown" then all[#all + 1] = d end end
			orbiting[model] = orbiting[model] or { parts = {}, radius = 0, speed = 0, root = root }
			orbiting[model].crown = { parts = all, height = (h.size or 1.5) * 1.5, root = root }
		else
			local ring = Instance.new("Part")
			ring.Name = "PetSkinHalo"; ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.1, h.size or 2, h.size or 2)
			ring.Color = h.color or Color3.new(1, 1, 1)
			ring.Material = h.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
			ring.Transparency = 0.25
			ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
			ring.CastShadow = false; ring.Massless = true
			ring.CFrame = root.CFrame * CFrame.new(0, (h.size or 2) * 0.9, 0) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = model
			orbiting[model] = orbiting[model] or { parts = {}, radius = 0, speed = 0, root = root }
			orbiting[model].halo = { part = ring, height = (h.size or 2) * 0.9, root = root }
		end
	end
end

-- ============================================================================================================
-- THE ENTRY POINT PetFollow CALLS
-- ============================================================================================================
-- Idempotent: it clears its own previous work first, so PetFollow can call it on every rebuild and every level
-- change without effects piling up. `lite` (icon clones) gets the skin recolour but no particles/light/orbits --
-- they don't render usefully in a static ViewportFrame and would just cost frame time.
_G.applyPetSkinLook = function(model, petId, lite)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	clearLook(model)
	painted[model] = petId

	local e = equipped[petId]
	if not e or not e.skin then return end -- no skin equipped: the pet keeps its natural look

	applySkin(model, e.skin)
	if not lite then applyTrait(model, e.trait) end
end

-- Paint a model with an ARBITRARY skin + trait, independent of what the player has EQUIPPED. This is what the
-- crate reel, the reveal card and the inventory rows need: they describe an item, so they must show that item,
-- not whatever the pet happens to be wearing.
--
-- `static` (the reel + inventory case) paints COLOUR/MATERIAL ONLY -- no particle emitter, no point light, no
-- hue-cycling registration, no trait. A reel is 56 cells: giving each one an emitter and a per-frame colour
-- animation would cost more than the whole reveal is worth, and none of it reads at thumbnail size anyway.
-- The reveal card passes static=false, so the ONE payoff model gets the full treatment.
_G.applyPetSkinPreview = function(model, skinId, traitId, static)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	clearLook(model)
	-- Deliberately NOT recorded in `painted`. repaintAll() walks that table on every server push and would
	-- repaint these to the EQUIPPED skin -- turning a Honey Maple Fox in the reel into whatever the player
	-- is wearing, which is precisely the bug this function exists to avoid.
	local skin = skinId and PetSkins.get(skinId)
	if not skin then return end
	if not static then
		applySkin(model, skinId)
		applyTrait(model, traitId)
		return
	end
	for _, part in ipairs(bodyParts(model)) do
		if not originals[part] then
			originals[part] = { color = part.Color, material = part.Material, refl = part.Reflectance }
		end
		if skin.color then part.Color = skin.color end
		if skin.material then part.Material = skin.material end
		part.Reflectance = skin.refl or 0
	end
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

-- ============================================================================================================
-- ANIMATION LOOP (one connection for every pet)
-- ============================================================================================================
-- Rainbow / cosmic hue cycling, orbiting trait parts, the floating halo/crown, and the Charged flicker all ride
-- one RenderStepped. It exits immediately when nothing is animated, so a player with no animated skin and no
-- orbit trait pays essentially nothing.
do
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t = t + dt

		-- animated skins
		for model, info in pairs(animated) do
			if model.Parent then
				local hue, sat, val
				if info.mode == "cosmic" then
					hue = (t * 0.10) % 1; sat = 0.55; val = 0.55 -- slow, deep, space-ish
				else
					hue = (t * 0.35) % 1; sat = 0.85; val = 1.0  -- rainbow: fast and bright
				end
				local c = Color3.fromHSV(hue, sat, val)
				for _, p in ipairs(info.parts) do
					if p.Parent then p.Color = c end
				end
				local root = model.PrimaryPart
				local pl = root and root:FindFirstChild("PetSkinLight")
				if pl and pl:IsA("PointLight") then pl.Color = c end
			else
				animated[model] = nil
			end
		end

		-- orbiting parts + halo / crown
		for model, o in pairs(orbiting) do
			local root = o.root
			if model.Parent and root and root.Parent then
				local rootCF = root.CFrame
				local n = #o.parts
				for i, p in ipairs(o.parts) do
					if p.Parent then
						local a = t * o.speed + (i - 1) * (2 * math.pi / math.max(1, n))
						p.CFrame = rootCF * CFrame.new(math.cos(a) * o.radius, 0.6, math.sin(a) * o.radius)
					end
				end
				if o.halo and o.halo.part.Parent then
					-- bob gently and spin, so it reads as floating rather than glued on
					o.halo.part.CFrame = rootCF
						* CFrame.new(0, o.halo.height + math.sin(t * 2) * 0.12, 0)
						* CFrame.Angles(0, t * 1.2, math.rad(90))
				end
				if o.crown then
					-- Move the crown as ONE rigid assembly: derive a centre CFrame from the pet's root each frame
					-- (bobbing + slowly spinning), then re-place the band and the five spikes at their fixed
					-- offsets from it. Rebuilding the offsets every frame keeps the pieces locked together no
					-- matter how the pet moves, and costs six CFrame writes.
					local centre = rootCF
						* CFrame.new(0, o.crown.height + math.sin(t * 2) * 0.1, 0)
						* CFrame.Angles(0, t * 0.8, 0)
					local idx = 0
					for _, p in ipairs(o.crown.parts) do
						if p.Parent then
							if idx == 0 then
								p.CFrame = centre * CFrame.Angles(0, 0, math.rad(90)) -- the band (cylinder on its side)
							else
								local ang = math.rad((idx - 1) * 72)                  -- five spikes, evenly spaced
								local r = 0.31 * 1.5
								p.CFrame = centre * CFrame.new(math.cos(ang) * r, 0.22, math.sin(ang) * r)
							end
							idx = idx + 1
						end
					end
				end
			else
				orbiting[model] = nil
			end
		end

		-- Charged flicker
		for model, pl in pairs(flickering) do
			if model.Parent and pl.Parent then
				pl.Brightness = 1.4 + math.abs(math.sin(t * 17)) * 1.4
			else
				flickering[model] = nil
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
			equipped[petId] = { skin = e.skin, trait = e.trait }
		end
	end
	_G.petSkinEquipped = equipped
	_G.petSkinState = state
	-- Tell the Pet Hub its open detail card is stale. Fired here rather than from the equip button because
	-- THIS is the moment the server has confirmed the change -- the button only asks, and a request the
	-- server refuses (pet still locked, skin not owned) must not flip the list to "ON".
	if _G.petHubSkinsChanged then pcall(_G.petHubSkinsChanged) end -- the crate/inventory UI reads tokens + owned entries from here
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
