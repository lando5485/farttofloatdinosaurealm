--!nonstrict
-- ============================================================================================================
-- PET RENDER GUARD (client) -- makes sure the pet you can see matches the pet you own.
-- ============================================================================================================
-- Two different failures both come out looking like "my pet didn't load", and PetFollow's own self-heal
-- watchdog catches NEITHER of them, because both leave a model sitting in the Workspace and all that
-- watchdog asks is whether a model exists.
--
--  1. INVISIBLE. spawnFollowerPet deliberately builds the pet with LocalTransparencyModifier = 1 on every
--     body part and only clears it after ContentProvider:PreloadAsync returns -- so the pet fades up whole
--     instead of assembling itself in mid-air. That is the right behaviour and it usually takes well under a
--     second. But PreloadAsync has no timeout, and on a slow join it can sit there: the pet is built, it is
--     parented, it is following you, and it is drawn at zero opacity forever. If the pet is low enough level
--     to have no accessories yet, that is a completely invisible pet. If it has accessories or an aura --
--     those were added AFTER the hide pass, so they were never hidden -- you get a hat and some sparkles
--     floating along with nothing underneath. That is the "not rendering fully" case.
--
--  2. WRONG BODY. buildPetModel clones a fused template the SERVER builds and replicates. It waits 15s for
--     it, and if it is not there it falls back to a client-built stand-in -- and there is no Bean Buddy
--     stand-in, so a brand-new player whose join raced the server's CSG pass gets a broccoli dino named
--     BeanBuddy as their first pet. It never corrects itself: the template lands in ReplicatedStorage a
--     moment later and nothing goes back to look. The inventory/HUD viewport icons are built later off that
--     same template, which is exactly why the pet following you can look nothing like its own picture.
--
-- Both are fixed from OUT HERE rather than in PetFollow, which is a 7000-line file sitting on Luau's
-- 200-locals-per-scope ceiling -- it cannot take another file-scope local.
-- ============================================================================================================

if _G.__PetRenderGuard then return end
_G.__PetRenderGuard = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

-- How long a pet may stay held-back before we call the reveal stuck. The real reveal is one PreloadAsync plus
-- one frame; six seconds is far past any honest case and far short of being annoying.
local STUCK_SECONDS = 6

-- The template a given pet is supposed to be cloned from. Same map PetFollow keys on, and it has to be
-- repeated here rather than shared because PetFollow cannot export it.
local TEMPLATE_NAME = {
	BeanBuddy        = "BeanBuddyTemplate",
	PizzaDragon      = "PizzaDragonTemplate",
	BroccoliPet      = "BroccoliBunnyTemplate",
	CoconutCrab      = "CoconutCrabTemplate",
	PopcornSheep     = "PopcornSheepTemplate",
	ButterDuck       = "ButterDuckTemplate",
	BurritoArmadillo = "BurritoArmadilloTemplate",
	SunflowerBee     = "SunflowerBeeTemplate",
	MapleFox         = "MapleFoxTemplate",
	FrostPenguin     = "FrostPenguinTemplate",
	BlossomBunny     = "BlossomBunnyTemplate",
	MoltenBean       = "MoltenBeanTemplate",
	VoidDragon       = "VoidDragonTemplate",
	PrismFox         = "PrismFoxTemplate",
}

-- Rare variants are stored as "ButterDuck#R"; the model keeps that key as its name but clones the same
-- template. Strip the suffix before looking the template up.
local function baseId(petId)
	local id = tostring(petId)
	local cut = string.find(id, "#", 1, true)
	return cut and string.sub(id, 1, cut - 1) or id
end

local hiddenSince = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() when it was first seen hidden
local rebuilt     = {}                                  -- [petId] = true, so a pet is only ever rebuilt once

-- ============================================================================================================
-- 1. STUCK REVEAL
-- ============================================================================================================
-- Clearing LocalTransparencyModifier is always safe: it is a purely local "don't draw this yet" flag with no
-- meaning of its own, and nothing in the game sets it except that reveal. The pet's real Transparency values
-- (the deliberately invisible root part, the semi-transparent aura pieces) live in Transparency and are not
-- touched, so a pet fixed by this guard looks exactly like one that revealed on its own.
local function unstick(model, petId)
	local held = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.LocalTransparencyModifier > 0.01 then
			d.LocalTransparencyModifier = 0
			held = held + 1
		end
	end
	if held > 0 then
		warn(("[PetGuard] %s never finished revealing (%d part(s) held for %ds) -- showing it now")
			:format(tostring(petId), held, STUCK_SECONDS))
	end
end

-- ============================================================================================================
-- 2. WRONG BODY
-- ============================================================================================================
-- A pet built from its template contains every part name the template has. applyLevelVisual only ever ADDS to
-- that (accessories, aura, evolution bits), so a model missing most of the template's parts was not built
-- from the template -- it is the stand-in. A 60% threshold rather than an exact match, because a level effect
-- is free to strip the odd part and that must not count as a wrong body.
local function looksLikeTemplate(model, template)
	local have = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then have[d.Name] = true end
	end
	local want, got = 0, 0
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then
			want = want + 1
			if have[d.Name] then got = got + 1 end
		end
	end
	if want == 0 then return true end -- nothing to compare against; never call that a mismatch
	return (got / want) >= 0.6
end

-- Destroying the model is the whole repair. PetFollow's watchdog runs every 3 seconds, sees an owned+equipped
-- pet with no model in the Workspace, and rebuilds it -- and by now the template it needs has arrived, so the
-- rebuild gets the real body. Going through that path rather than building anything here means the rebuilt pet
-- gets its level visuals, its skin and its trait applied by the code that owns them.
local function rebuild(model, petId)
	rebuilt[petId] = true
	warn(("[PetGuard] %s was built from the fallback body (its template arrived late) -- rebuilding it from %s")
		:format(tostring(petId), tostring(TEMPLATE_NAME[baseId(petId)])))
	model:Destroy()
end

-- ============================================================================================================
-- THE SWEEP
-- ============================================================================================================
task.spawn(function()
	-- The wrong-body check only runs for the first few minutes. That is when the join race it exists for
	-- happens, and bounding it means a false positive can cost at most one rebuild per pet, once, early --
	-- never a pet that flickers all session. The invisibility check has no such bound: it is a pure repair
	-- with nothing to get wrong, and a reveal can stall at any point (a pet re-spawns on respawn too).
	local startedAt = os.clock()
	while true do
		task.wait(1)
		local reg = _G.petPaintedModels
		if type(reg) == "table" then
			for model, petId in pairs(reg) do
				-- Icon clones live inside ViewportFrames and are registered here too. They are drawn by a
				-- camera, not the world, and are never subject to either failure -- skip anything not in
				-- the Workspace.
				if typeof(model) == "Instance" and model.Parent and model:IsDescendantOf(Workspace) then
					-- --- stuck reveal ---
					local anyHidden = false
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.LocalTransparencyModifier > 0.01 then anyHidden = true; break end
					end
					if anyHidden then
						local t0 = hiddenSince[model]
						if not t0 then
							hiddenSince[model] = os.clock()
						elseif (os.clock() - t0) >= STUCK_SECONDS then
							unstick(model, petId)
							hiddenSince[model] = nil
						end
					else
						hiddenSince[model] = nil
					end

					-- --- wrong body ---
					if not rebuilt[petId] and (os.clock() - startedAt) < 180 then
						local tn = TEMPLATE_NAME[baseId(petId)]
						local template = tn and ReplicatedStorage:FindFirstChild(tn)
						-- Only judge once the template is actually present. Before that there is nothing to
						-- compare against and the stand-in is the correct thing to be looking at.
						if template and not looksLikeTemplate(model, template) then
							rebuild(model, petId)
						end
					end
				end
			end
		end
	end
end)

print("[PetGuard] watching pet models for stuck reveals and fallback bodies")
