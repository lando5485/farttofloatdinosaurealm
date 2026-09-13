-- ============================================================================================
-- PET SYSTEM (client) -- COSMETIC ONLY. Builds the per-player broccoli PIECES + EGG at the island
-- markers, and the follower PET that trails the player (smoothly, INCLUDING during fast fart-flight).
-- ============================================================================================
-- The server (PetSystem.server.lua) owns the authoritative state (piece counts, ownership,
-- persistence). This client builds the visuals per-player and drives the follow. It NEVER touches
-- the player's physics: the pet is anchored + CanCollide/CanQuery false and moved kinematically via
-- Model:PivotTo, so it cannot affect flight, gas, coins, or anything. Purely visual.
--
-- Protocol: PetStateEvent (s->c) tells us {found,total,owns} per pet. We fire PetCollectEvent /
-- PetClaimEvent (c->s) from the prompts, and PetRequestStateEvent (c->s) once as a handshake.
-- ============================================================================================

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")
local SoundService    = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local player      = Players.LocalPlayer

-- ===== HATCH SOUNDS (shared by ALL pets' hatch flow) =====
-- Created + PRELOADED ONCE at startup so they play INSTANTLY. (Previously a fresh Instance.new("Sound") +
-- :Play() loaded the asset on first use, which delayed the crack ~2s -- so it seemed to start ~2s late.
-- Preloading removes that delay, so the crack now fires right at the TRUE hatch start and the unlock lands
-- on the reveal.) Volumes are boosted ABOVE 1.0 (Roblox allows up to 10) for a genuinely LOUD/impactful hatch.
local hatchCrackSound = Instance.new("Sound")
hatchCrackSound.Name = "HatchCrackSound"; hatchCrackSound.SoundId = "rbxassetid://126450028713974"
hatchCrackSound.Volume = 3; hatchCrackSound.Parent = SoundService
local hatchUnlockSound = Instance.new("Sound")
hatchUnlockSound.Name = "HatchUnlockSound"; hatchUnlockSound.SoundId = "rbxassetid://92880640988467"
hatchUnlockSound.Volume = 3; hatchUnlockSound.Parent = SoundService
-- COCONUT CRACK HIT -- one thwack per tap in the island-5 crack minigame.
-- ONE Sound reused, not a fresh Instance per tap: the crack is a mash-as-fast-as-you-can bar and allocating
-- a Sound per press is the same mistake the reel loop documents further down. TimePosition = 0 before each
-- Play() is what makes it RETRIGGER instead of being ignored while already playing -- which is the whole
-- point here, since every tap is meant to be its own hit.
local cocoHitSound = Instance.new("Sound")
cocoHitSound.Name = "CocoHitSound"; cocoHitSound.SoundId = "rbxassetid://9125869504"
cocoHitSound.Volume = 2.2; cocoHitSound.Parent = SoundService   -- SoundService = 2D + obeys the SFX toggle
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ hatchCrackSound, hatchUnlockSound, cocoHitSound }) end) end)

-- Mirror of the server catalog (marker names so we can find them in Workspace).
local PETS = {
	BroccoliPet = {
		questType    = "find",
		islandPrefix = "Island_2_",
		eggMarker    = "I2PetBlock",
		pieceMarkers = { "BroccoliPiece1", "BroccoliPiece2", "BroccoliPiece3" },
		-- UI metadata (DATA-DRIVEN: the quest UI reads these, so future pet islands reuse it with no hardcoding)
		pieceLabel   = "Broccoli",                                  -- tracker/popup label ("Broccoli: 1/3")
		iconEmoji    = "\xF0\x9F\xA5\xA6",                           -- 🥦 tracker icon
		questName    = "Broccoli Bunny Quest",                       -- HUD indicator: the quest's real NAME
		objective    = "Pull 3 broccoli out of the dirt",            -- HUD indicator: short objective line
		trackWord    = "Pieces",                                     -- HUD minimized tracker word ("Pieces X/3")
		nextStep     = "Hatch the egg",                              -- tracker text once the count is complete
	},
	-- PET #2: COCONUT CRAB (Coconut Cove). questType "crack": 7 coconuts (tap-to-crack minigame) -> Cave Key
	-- -> chest in the cave -> egg -> hatch. Same marker->position->visual architecture as broccoli.
	CoconutCrab = {
		questType    = "crack",
		islandPrefix = "Island_5_",
		eggMarker    = "CoconutChest",
		pieceMarkers = { "Coconut1","Coconut2","Coconut3","Coconut4","Coconut5","Coconut6","Coconut7" },
		pieceLabel   = "Coconut",
		iconEmoji    = "\xF0\x9F\xA5\xA5",                           -- 🥥 tracker icon
		questName    = "Coconut Crab Quest",
		objective    = "Crack 7 coconuts",
		trackWord    = "Coconuts",                                   -- "Coconuts X/7"
		nextStep     = "Unlock the chest",
	},
	-- PET #3: POPCORN SHEEP (Popcorn Pinnacle). questType "film-reels": find 6 FILM REELS -> load them at
	-- the PROJECTOR -> a mini-movie plays on the SCREEN -> the egg materializes in a spotlight at the
	-- PopcornEggSpot -> hatch. Same marker->position->visual architecture; projector + screen positions ride
	-- in extraMarkers (the client builds those props). Movie-theater themed, cosmetic-only.
	PopcornSheep = {
		questType    = "film-reels",
		islandPrefix = "Island_8_",
		eggMarker    = "PopcornEggSpot",
		pieceMarkers = { "FilmReel1","FilmReel2","FilmReel3","FilmReel4","FilmReel5","FilmReel6" },
		extraMarkers = { projector = "PopcornProjector", screen = "PopcornScreen" },
		pieceLabel   = "Film Reel",
		iconEmoji    = "\xF0\x9F\x90\x91",                           -- 🐑 tracker icon
		allFoundMsg  = "All 6 found! Load reels at the projector!",  -- tracker text at full count (data-driven)
		questName    = "Popcorn Sheep Quest",
		objective    = "Collect 6 film reels",
		trackWord    = "Reels",                                      -- "Reels X/6"
		nextStep     = "Load the projector",
	},
	-- PET #4: BUTTER DUCK (Butter Swamp). questType "fishing": grab a rod at the barrel -> fish near/over the
	-- ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in tension minigame -> the SERVER rolls the catch
	-- (pity egg chance + funny junk) -> the egg appears IN FRONT of the player -> hatch. No pieces/egg marker.
	ButterDuck = {
		questType    = "fishing",
		islandPrefix = "Island_10_",
		pieceMarkers = {},                                          -- fishing has no collectible pieces
		extraMarkers = { butterlake = "ButterLake", rodbarrel = "RodBarrel" },
		pieceLabel   = "Catch",
		iconEmoji    = "\xF0\x9F\xA6\x86",                           -- 🦆 tracker icon
		allFoundMsg  = "Fish in the butter to catch the egg!",
		questName    = "Butter Duck Quest",
		objective    = "Catch what's in the butter lake",
		trackWord    = "Reeled in",                                  -- fishing has no fixed total -> "Reeled in: X"
		nextStep     = "Hatch the egg",
	},
	-- PET #5: BURRITO ARMADILLO (Burrito Barrens). questType "dig": grab a SHOVEL -> hot/cold hunt -> DIG
	-- minigame at dig spots -> DigSpot1-4 are decoys (junk), BuriedEggSpot is the real one (the egg) -> hatch.
	BurritoArmadillo = {
		questType    = "dig",
		islandPrefix = "Island_13_",
		pieceMarkers = {},                                          -- dig has no collectible pieces
		extraMarkers = { shovel = "ShovelSpot", dig1 = "DigSpot1", dig2 = "DigSpot2", dig3 = "DigSpot3", dig4 = "DigSpot4", dig5 = "DigSpot5", buriedegg = "BuriedEggSpot" },
		pieceLabel   = "Dig",
		iconEmoji    = "\xF0\x9F\xAA\x96",                           -- 🪖 (armadillo-ish) tracker icon
		allFoundMsg  = "Dig up the buried armadillo egg!",
		questName    = "Burrito Armadillo Quest",
		objective    = "Dig up what's buried",
		trackWord    = "Mounds",                                     -- "Mounds X/6"
		nextStep     = "Dig up the egg",
	},
	-- ===== STARTER PET (retention) -- NO island quest: the server GRANTS it free on a player's first ever join and
	-- auto-equips it. questType="starter" so the startup world-builder skips it (nothing to build) and it never shows
	-- in the quests panel; it ONLY appears as the equipped FOLLOWER (cloned from the server template via
	-- PET_TEMPLATE_NAME) + an owned inventory card. Must exist here so applyState() spawns the follower.
	BeanBuddy    = { questType = "starter",  pieceMarkers = {}, displayName = "Bean Buddy",    iconEmoji = "\xF0\x9F\x8C\xB1" },
	-- ===== SECRET PET (10/10 collection reward) -- NO quest, no island, nothing to build in the world: the server
	-- grants it the moment the collection is complete. questType="collection" so the world-builder skips it and it
	-- never shows in the quests panel. Must exist here so applyState() can spawn the follower.
	PizzaDragon  = { questType = "collection", pieceMarkers = {}, displayName = "Pizza Dragon", iconEmoji = "\xF0\x9F\x90\x89" },
	-- ===== SEASONAL PETS (Community Garden rewards) -- NO island quest (granted by the harvest). questType="seasonal"
	-- so the startup world-builder skips them; they ONLY ever appear as the equipped FOLLOWER (cloned from the server
	-- template via PET_TEMPLATE_NAME) + an owned inventory card. Must exist here so applyState() spawns the follower.
	SunflowerBee = { questType = "seasonal", pieceMarkers = {}, displayName = "Sunflower Bee", iconEmoji = "\xF0\x9F\x90\x9D" },
	MapleFox     = { questType = "seasonal", pieceMarkers = {}, displayName = "Maple Fox",     iconEmoji = "\xF0\x9F\xA6\x8A" },
	FrostPenguin = { questType = "seasonal", pieceMarkers = {}, displayName = "Frost Penguin", iconEmoji = "\xF0\x9F\x90\xA7" },
	BlossomBunny = { questType = "seasonal", pieceMarkers = {}, displayName = "Blossom Bunny", iconEmoji = "\xF0\x9F\x90\xB0" },
}

-- ============================================================================================
-- HUD QUEST INDICATOR -- shared progress state. The on-screen tracker shows each quest's real NAME +
-- objective while it's AVAILABLE on the player's island, then MINIMIZES to a small live progress counter
-- once STARTED. Piece quests (broccoli/coconut/sheep) drive it from the server found/total; the count-less
-- quests (fishing/dig) push progress here from their own interaction code. Forward-declared so that the
-- interaction code (which lives ABOVE the HUD GUI in this file) can update it. COSMETIC-ONLY.
local localQuestProg = {}    -- [petId] = { started=bool, found=n, total=n_or_nil, complete=bool } (fishing/dig)
local refreshQuestHUD        -- assigned where the tracker GUI is built (below); closures capture this upvalue
local function pushQuestProg(petId, fields)
	local lp = localQuestProg[petId] or {}
	local wasComplete = lp.complete == true
	for k, v in pairs(fields) do lp[k] = v end
	localQuestProg[petId] = lp
	if refreshQuestHUD then pcall(refreshQuestHUD) end

	-- ===== A QUEST STEP FINISHING IS A MILESTONE, SO IT TAKES THE HERO LANE ALONE =====
	-- The tracker above is a persistent counter -- it says "3/3" and keeps sitting there. The COMPLETION is
	-- news, and this realm's rule is that a tutorial/milestone moment gets the top-centre banner to itself:
	-- while it plays, arrival cards, event titles, promos, reward toasts and purchase confirmations all
	-- queue and follow it, in order, never over or beside it. The one thing that outranks it is the garden
	-- watering quest's live step directions.
	--
	-- Guarded on the TRANSITION (wasComplete -> complete), because pushQuestProg is called again on later
	-- field updates for the same quest and a completion is a once-ever beat, not a repeating state.
	--
	-- Everything here is inline on purpose: this file's main chunk sits at 198 of Luau's 200 local
	-- registers, so a top-level `local NC = ...` would take the script over the ceiling and silently kill
	-- every pet, quest and tracker in the game.
	if lp.complete == true and not wasComplete then
		if _G.NotifyCenter then
			local spec = {
				top   = "\xE2\x9C\x85 QUEST COMPLETE",
				text  = "\xF0\x9F\xA5\x9A  YOUR EGG IS READY!",
				sub   = "Follow the arrows \xE2\x80\x94 they are pointing straight at it",
				color = Color3.fromRGB(126, 217, 87),
				exclusive = true,
				priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.TUTORIAL) or 150,
				duration = 4,
			}
			if _G.NotifyCenter.tutorial then pcall(_G.NotifyCenter.tutorial, spec)
			elseif _G.NotifyCenter.push then pcall(_G.NotifyCenter.push, spec) end
		end
		print("[Pet][HUD] quest step COMPLETE for " .. tostring(petId) .. " -- exclusive hero banner")
	end
end

local PetCollectEvent      = RS:WaitForChild("PetCollectEvent", 30)
local PetClaimEvent        = RS:WaitForChild("PetClaimEvent", 30)
local PetRequestStateEvent = RS:WaitForChild("PetRequestStateEvent", 30)
local PetStateEvent        = RS:WaitForChild("PetStateEvent", 30)
local PetGetMarkers        = RS:WaitForChild("PetGetMarkers", 30) -- RF: ask the server for marker COORDINATES (client never searches Workspace)
-- pet inventory / equip / leveling remotes (cosmetic-only)
local PetEquipEvent     = RS:WaitForChild("PetEquipEvent", 30)
local PetInventoryEvent = RS:WaitForChild("PetInventoryEvent", 30)
local PetUpgradeEvent   = RS:WaitForChild("PetUpgradeEvent", 30)
local PetProgressEvent  = RS:WaitForChild("PetProgressEvent", 30)
local PetPendingUpgrade = RS:WaitForChild("PetPendingUpgradeEvent", 30)
local PetQuestDiscovered = RS:WaitForChild("PetQuestDiscoveredEvent", 30) -- c->s: landed on a pet's island
local PetFishRoll = RS:WaitForChild("PetFishRollEvent", 30) -- c->s RF: reeled in -> SERVER rolls the catch (pity)
local PetDigEvent = RS:WaitForChild("PetDigEvent", 30) -- c->s: dug the REAL buried-egg spot -> server unlocks the BurritoArmadillo claim
local PetRareEvent = RS:WaitForChild("PetRareEvent", 30) -- s->c: (petId, rareName) a RARE hatched -> play the fanfare
-- (StarterPetEvent is fetched inside its own do-block down by the welcome card: this file sits close to Luau's
-- 200-locals-per-scope ceiling, so a block-scoped local frees its register instead of holding a top-level slot.)
-- STAGE 3 TRADE remotes (client sends intents only)
local PetTradeRequest = RS:WaitForChild("PetTradeRequestEvent", 30)
local PetTradeRespond = RS:WaitForChild("PetTradeRespondEvent", 30)
local PetTradeOffer   = RS:WaitForChild("PetTradeOfferEvent", 30)
local PetTradeConfirm = RS:WaitForChild("PetTradeConfirmEvent", 30)
local PetTradeCancel  = RS:WaitForChild("PetTradeCancelEvent", 30)
local PetTradeState   = RS:WaitForChild("PetTradeStateEvent", 30)
local PetTradePrompt  = RS:WaitForChild("PetTradeRequestPromptEvent", 30)
-- ⚠ REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (must match PET_SKIP_PRODUCTS in
-- PetSystem.server.lua). Each jumps the pet to the FIRST level of the next tier; the Skip button prompts the
-- one for the pet's current tier. Until the real products exist the prompt errors harmlessly for real players;
-- test accounts tier-skip instantly via the server test path. (Ordered 1=Baby->Kid ... 4=Adult->Elder.
-- `to` is the DISPLAY label on the skip button -- age names since the level ladder stopped using rarity words.)
local PET_SKIP_PRODUCTS = {
	{ to = "Kid",   price = 49,  id = 123456701 }, -- ⚠ placeholder product id -- REPLACE BEFORE LAUNCH
	{ to = "Teen",  price = 99,  id = 123456702 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Adult", price = 299, id = 123456703 }, -- ⚠ REPLACE BEFORE LAUNCH
	{ to = "Elder", price = 599, id = 123456704 }, -- ⚠ REPLACE BEFORE LAUNCH
}

-- ===== low-poly build helpers =====
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape
	p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- A small broccoli "thing" (stalk + green florets) built around a root CFrame; returns the Model.
local function buildBroccoliBlob(scale, withFace)
	local model = Instance.new("Model"); model.Name = "BroccoliBlob"
	local s = scale or 1
	-- Upright BLOCK stalk as PrimaryPart (identity orientation) so Model:PivotTo orients the whole pet
	-- cleanly (a rotated PrimaryPart would skew the florets/eyes when we PivotTo each frame).
	local stalk = newPart(model, "Stalk", Enum.PartType.Block, Vector3.new(0.85*s, 1.3*s, 0.85*s), Color3.fromRGB(175, 200, 140), CFrame.new(0,0,0))
	model.PrimaryPart = stalk
	local crownC = Color3.fromRGB(60, 160, 60)
	newPart(model, "Floret0", Enum.PartType.Ball, Vector3.new(1.5*s,1.5*s,1.5*s), crownC, CFrame.new(0, 1.1*s, 0))
	for i = 1, 5 do
		local a = (i-1) * (2*math.pi/5)
		newPart(model, "Floret"..i, Enum.PartType.Ball, Vector3.new(1.05*s,1.05*s,1.05*s), crownC,
			CFrame.new(math.cos(a)*0.85*s, 0.95*s, math.sin(a)*0.85*s))
	end
	if withFace then
		-- eyes on the FRONT (-Z) of the crown; pupils slightly in front so they read at distance.
		for _, sx in ipairs({-0.35, 0.35}) do
			newPart(model, "Eye", Enum.PartType.Ball, Vector3.new(0.42*s,0.42*s,0.42*s), Color3.fromRGB(255,255,255), CFrame.new(sx*s, 1.15*s, -0.62*s))
			newPart(model, "Pupil", Enum.PartType.Ball, Vector3.new(0.22*s,0.22*s,0.22*s), Color3.fromRGB(20,20,20), CFrame.new(sx*s, 1.15*s, -0.78*s))
		end
	end
	return model
end

-- A cute cartoony broccoli-themed DINO (the pet). Built low-poly around an INVISIBLE anchored Root as
-- PrimaryPart (identity orientation) so Model:PivotTo follows + ScaleTo pops without skewing; -Z = front
-- (the follow loop faces the pet's -Z toward travel, so the eyes point forward). Modular: future pets can
-- have their own buildXyz() and spawnFollowerPet just swaps which builder it calls.
-- Animator registry: model -> { parts = { {part, base (local CFrame vs root), baseSize, role, eye?, breath?}.. },
-- s, t, move (0..1), blink, lastPos }. Weak keys so a destroyed pet is GC'd. animatePet() (below) reads
-- this each frame and writes LOCAL offsets onto the sub-parts -- the root keeps following the player.
local petAnims = setmetatable({}, { __mode = "k" })

-- FRIENDLY CARTOON DINO: a soft, smooth, rounded long-neck dinosaur. EVERYTHING is a rounded ellipsoid
-- (Ball, SmoothPlastic) -- NO blocks, no sharp edges. Parts overlap generously so they blend into ONE
-- connected smooth animal, while the long-neck-up / snout-forward / long-tail-back / standing-on-legs
-- proportions keep it readable as a dinosaur. Big cute eyes = friendly. Broccoli-green with rounded
-- floret bumps as a head crest + back ridge. Local frame: +X = FORWARD/facing (the follow loop yaws the
-- root so +X leads travel). role groups parts for the animator (body/head/tail/leg); eye=true blinks.
-- The long NECK is tagged "head" so it sways smoothly with the head (a gentle, friendly dino motion).
-- NOTE: this is the FALLBACK builder (separate parts) used only if the server's fused Union template is
-- missing. Normally buildBroccoliDino() clones the pre-fused server Union from ReplicatedStorage instead.
local function buildBroccoliDinoFallback(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "BroccoliDino"
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1
	model.PrimaryPart = root
	local bodyC  = Color3.fromRGB(60,140,55)
	local legC   = Color3.fromRGB(45,110,45)
	local crownC = Color3.fromRGB(40,100,40)
	local whiteC = Color3.fromRGB(245,245,245)
	local darkC  = Color3.fromRGB(30,30,30)
	local parts = {}
	local function record(part, role, eye)
		local e = { part = part, base = part.CFrame, baseSize = part.Size, role = role, eye = eye }
		parts[#parts+1] = e
		return e
	end
	-- a part (Block or Ball) at a position, with optional local rotation (for the angled neck). SmoothPlastic.
	local function add(name, role, ptype, size, color, x, y, z, rot, eye)
		local cf = CFrame.new(x*s, y*s, z*s)
		if rot then cf = cf * rot end
		local part = newPart(model, name, ptype, Vector3.new(size[1], size[2], size[3]) * s, color, cf)
		return record(part, role, eye)
	end
	local BAL = Enum.PartType.Ball -- everything is a smooth rounded Ball ellipsoid (no blocks)

	-- ===== FALLBACK body parts (separate rounded ellipsoids). Used only when the server Union template is
	-- missing -- they animate per-role (neck/tail sway) so the pet still looks alive without the fusion.
	-- 1) BODY: a big soft rounded torso.
	add("Body", "body", BAL, {2.9, 1.85, 2.05}, bodyC, 0, 0, 0).bodyGroup = true
	-- 2) NECK: two rounded ellipsoids sweeping UP-and-FORWARD, overlapping body + head -> one smooth neck.
	add("NeckLow", "head", BAL, {1.15, 1.5, 1.15}, bodyC, 1.35, 1.05, 0, CFrame.Angles(0, 0, math.rad(-30))).bodyGroup = true
	add("Neck",    "head", BAL, {1.0, 1.7, 1.0},  bodyC, 1.85, 1.95, 0, CFrame.Angles(0, 0, math.rad(-26))).bodyGroup = true
	-- 3) HEAD + SNOUT.
	add("Head", "head", BAL, {1.35, 1.2, 1.25}, bodyC, 2.35, 2.55, 0).bodyGroup = true
	add("Snout", "head", BAL, {1.1, 0.85, 0.95}, bodyC, 3.0, 2.35, 0).bodyGroup = true
	-- 4) TAIL: a long tapering tail, each segment overlapping the previous, stepping DOWN-and-BACK.
	add("Tail", "tail", BAL, {1.6, 1.15, 1.15}, bodyC, -1.85, -0.05, 0).bodyGroup = true
	add("Tail", "tail", BAL, {1.15, 0.8, 0.8},  bodyC, -2.7, -0.4, 0).bodyGroup = true
	add("Tail", "tail", BAL, {0.75, 0.5, 0.5},  bodyC, -3.4, -0.7, 0).bodyGroup = true
	add("Tail", "tail", BAL, {0.42, 0.34, 0.34},bodyC, -3.9, -0.95, 0).bodyGroup = true

	-- ===== SEPARATE parts (NOT unioned) -- they keep their own colors/animation. .lockOnUnion = they snap
	-- to riding rigidly with the fused union once it exists (so they don't drift off the now-solid body).
	-- EYES: BIG friendly rounded eyes (white) + big dark pupils, proud of the head front.
	for _, ez in ipairs({0.42, -0.42}) do
		add("Eye",   "head", BAL, {0.52, 0.62, 0.46}, whiteC, 2.62, 2.7, ez, nil, true).lockOnUnion = true
		add("Pupil", "head", BAL, {0.3, 0.42, 0.3},   darkC,  2.82, 2.66, ez, nil, true).lockOnUnion = true
	end
	-- LEGS: four soft rounded leg stubs (kept SEPARATE -- thin parts union poorly, and they keep their gait).
	for _, lp in ipairs({ {1.0,0.62}, {1.0,-0.62}, {-1.0,0.62}, {-1.0,-0.62} }) do
		add("Leg", "leg", BAL, {0.8, 1.35, 0.8}, legC, lp[1], -1.2, lp[2])
	end
	-- BROCCOLI THEME: rounded floret bumps as a HEAD CREST + a NECK/BACK RIDGE (separate green parts).
	for _, f in ipairs({
		{x=2.3, y=3.05,z=0.00, r=0.56, role="head"}, {x=2.05,y=2.95,z=0.26, r=0.44, role="head"},
		{x=2.55,y=2.95,z=-0.24,r=0.46, role="head"}, {x=1.85,y=2.25,z=0.00, r=0.46, role="head"}, -- crest + upper neck
		{x=0.5, y=1.15,z=0.00, r=0.56, role="body"}, {x=-0.55,y=1.05,z=0.00, r=0.5, role="body"}, -- back ridge
	}) do
		add("Floret", f.role, BAL, {f.r, f.r, f.r}, crownC, f.x, f.y, f.z).lockOnUnion = true
	end

	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- Register a CLONED server template (its body is ONE fused UnionOperation -> smooth, not loose spheres).
-- Derive each part's animator role from its name. The body is now one rigid union, so the head/neck/tail
-- can't sway independently -- everything (union + eyes + florets) rides the whole-body bob/sway/lean as a
-- unit; eyes still blink; the separate legs still do their gait.
local function registerClonedTemplate(model)
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then return false end
	model.PrimaryPart = root
	local rootCF = root.CFrame
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local role, eye = "body", false
			local n = p.Name
			if n == "Leg" or n == "Foot" or n == "ToeClaw" then role = "leg"   -- legs/feet do the gait
			elseif n == "Tail" or n == "TailSpike" then role = "tail" -- tail wiggle
			elseif n == "Ear" then role = "ear"                       -- ears wiggle/flop (bunny, sheep)
			elseif n == "Wing" then role = "wing"                     -- wings flap (duck)
			elseif n == "Claw" then role = "claw"                     -- claws scuttle (crab)
			elseif n == "Eye" or n == "Highlight" then eye = true end -- ride the body, but blink
			parts[#parts+1] = { part = p, base = rootCF:ToObjectSpace(p.CFrame), baseSize = p.Size, role = role, eye = eye }
		end
	end
	petAnims[model] = { s = 0.9, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil, unionized = true }
	return true
end

-- The pet builder: CLONE the server's pre-fused Union template (smooth body) if present; otherwise fall
-- back to the client-built separate-parts dino so the pet always appears.
local function buildBroccoliDino(scale)
	-- instant if already replicated; else wait briefly for it (covers join-time replication lag)
	local template = RS:FindFirstChild("BroccoliDinoTemplate") or RS:WaitForChild("BroccoliDinoTemplate", 3)
	if template then
		local clone = template:Clone()
		clone.Name = "BroccoliDino"
		if registerClonedTemplate(clone) then
			print("[Pet][UNION] cloned server Union template (smooth fused body)")
			return clone
		end
		clone:Destroy()
	end
	warn("[Pet][UNION] BroccoliDinoTemplate not found in ReplicatedStorage -- using separate-parts fallback")
	return buildBroccoliDinoFallback(scale)
end

local function setVisible(model, on)
	if not model then return end
	model.Parent = on and Workspace or nil
end

-- ===== marker lookup =====
-- (REMOVED: the client no longer SEARCHES Workspace/island for markers. The server owns the marker
-- POSITIONS and hands them over via the PetGetMarkers RemoteFunction; we build from those coordinates.)

-- ===== per-pet client state =====
local petState = {}  -- [petId] = { pieces={[i]=model}, collected={[i]=bool}, egg=model, pet=model, built=bool }

local function addPrompt(rootPart, actionText, objectText, onTriggered)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText; pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0
	pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
	pp.Parent = rootPart
	pp.Triggered:Connect(onTriggered)
	return pp
end

local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,180,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(120,255,120); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	game:GetService("TweenService"):Create(a, TweenInfo.new(1.2), {Transparency=1}):Play()
	game:GetService("TweenService"):Create(lbl, TweenInfo.new(1.2), {TextTransparency=1}):Play()
	task.delay(1.3, function() a:Destroy() end)
end

-- ============================================================================================
-- THE QUEST ACCEPT GATE
--
-- Landing on an island used to hand you its quest: the tracker told you the objective and every collectible
-- was already live. Now the island keeps its secret until you find the quest giver and hear them out. The NPC
-- sets Island<N>QuestAccepted on the SERVER (page 2 of its dialogue, IslandNPCs.server.lua); it replicates
-- here for free and survives respawns, so no remote and no handshake is needed.
--
-- The props stay VISIBLE and still show their prompts -- an island stripped of its scenery reads as broken,
-- and a prompt that silently does nothing reads as a bug. What they refuse to do is START a quest nobody
-- handed you, and they say exactly where to go instead.
--
-- The island number comes from the pet's own islandPrefix ("Island_2_" -> 2), so there is no second table to
-- keep in sync -- adding a quest island needs no edit here.
-- ============================================================================================
-- ===== THIS FILE IS AT LUAU'S 200-LOCAL CEILING =====
-- The main chunk of PetFollow is one register from the limit -- adding eight plain top-level locals
-- here is what produced "Out of local registers when trying to allocate reqAccept: exceeded limit
-- 200", which kills the WHOLE script, not just the new code.
--
-- So the gate costs ZERO top-level registers: its state and helpers live inside this do-block (they
-- become upvalues of the closure, which are not main-chunk registers), and the one entry point is
-- published on _G -- the same pattern this file already uses for _G.isFlying / _G.guideTrailTo.
--
--   _G.petQuestGate(def)       -> boolean, SILENT. For "may I show this?" checks.
--   _G.petQuestGate(def, pos)  -> boolean, and floats "talk to the NPC" at pos when refused.
do
	local attrCache, msgAt = {}, 0
	local function attrFor(def)
		if not def.islandPrefix then return nil end
		local cached = attrCache[def.islandPrefix]
		if cached ~= nil then return cached end
		local n = tonumber(tostring(def.islandPrefix):match("%d+"))
		cached = n and ("Island%dQuestAccepted"):format(n) or false
		attrCache[def.islandPrefix] = cached
		return cached
	end
	_G.petQuestGate = function(def, pos)
		local attr = attrFor(def)
		if not attr then return true end -- seasonal/starter pets have no island: nothing to gate
		if player:GetAttribute(attr) == true then return true end
		-- ===== THE REFUSAL IS A BANNER NOW, NOT FLOATING WORLD TEXT =====
		-- This used to be a floatText: a 3D label spawned two and a half studs above whichever prop you
		-- touched. Three problems, all of them fixed by using the same lane every other message uses.
		--   1. IT WAS SOMEWHERE ELSE. Every other "you can't do that yet" in this game -- the locked food
		--      stand, the wormhole's "land first" -- arrives as a banner at the top. This one appeared over
		--      a bush, in a different size, in a different font, at whatever distance you happened to be
		--      standing. A player learns where to look for refusals; this taught the opposite.
		--   2. IT WAS UNREADABLE AT RANGE. World text scales with distance. Touch a prop from the far side
		--      of a prompt's radius and the sentence was a few pixels tall.
		--   3. IT COULD OVERLAP ANYTHING. Being world-space it had no idea what was on screen, so it could
		--      land straight across a hero banner or a tutorial instruction.
		-- As a banner it is the same 500-wide card, in the same place, at EVENT priority: it queues behind
		-- the garden watering directions and any exclusive tutorial/achievement moment rather than talking
		-- over them, and it cannot preempt one at all.
		--
		-- The 2s throttle is KEPT and still matters -- it is what stops mashing E from queueing ten
		-- identical banners behind each other. (NotifyCenter also drops an exact repeat within 2s, so this
		-- is belt and braces, but the throttle is the one that keeps the log quiet too.)
		--
		-- `pos` is now only a "was this an actual interaction" flag rather than a place to draw at; it is
		-- kept in the signature because every call site passes it and the silent form still passes nil.
		--
		-- Inline on _G with no new top-level local: this file's main chunk is at Luau's 200-register
		-- ceiling and one more would stop the entire script -- pets, quests and trackers -- from compiling.
		if pos and os.clock() - msgAt > 2 then
			msgAt = os.clock()
			if _G.NotifyCenter and _G.NotifyCenter.push then
				pcall(_G.NotifyCenter.push, {
					top   = "\u{1F512} Quest Not Started",
					text  = "Talk to the Quest NPC to start this quest!",
					color = Color3.fromRGB(255, 190, 60), -- the same amber the locked food stand uses
					priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT) or 80,
					duration = 3,
				})
			end
			print("[Pet][Quest] blocked -- " .. tostring(attr) .. " not accepted yet (hero banner shown)")
		end
		return false
	end
end

local hatchEgg -- forward declaration; assigned below (after the spawnFollowerPet/setEggGlow it relies on)

-- ============================================================================================
-- COCONUT CRAB QUEST (questType "crack"). A harder multi-stage quest: CRACK 7 coconuts (a tap minigame)
-- -> earn the CAVE KEY -> open the key-gated CHEST in the cave -> egg -> hatch -> the Coconut Crab follows.
-- Reuses the same server collect/claim/inventory + the broccoli HATCH flow. All cosmetic-only.
-- ============================================================================================

-- placeholder COCONUT CRAB follower (brown coconut-shell body + 3 spots, claws, legs, cute eyes). Registers
-- parts into petAnims (body/leg roles + eye) so the existing animator gives it idle bob, blink, leg gait.
local function buildCoconutCrab(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "CoconutCrab"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BROWN, DARK, CLAW = Color3.fromRGB(112,72,42), Color3.fromRGB(66,40,22), Color3.fromRGB(150,72,46)
	mk("Body", Enum.PartType.Ball, 2.1,1.8,2.1, BROWN, 0,0,0, "body")
	mk("Spot", Enum.PartType.Ball, 0.34,0.34,0.22, DARK, 0.95,0.15,0, "body")      -- the 3 coconut "eyes"
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,-0.4, "body")
	mk("Spot", Enum.PartType.Ball, 0.3,0.3,0.2, DARK, 0.9,-0.35,0.4, "body")
	for _, ez in ipairs({-0.45, 0.45}) do                                          -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.42,0.42,0.42, Color3.fromRGB(245,245,245), 0.55,1.0,ez, "body", true)
		mk("Pupil", Enum.PartType.Ball, 0.22,0.22,0.22, Color3.fromRGB(18,18,18), 0.78,1.02,ez, "body", true)
	end
	for _, cs in ipairs({-1, 1}) do                                                -- two claws
		mk("Claw", Enum.PartType.Ball, 0.78,0.66,0.6, CLAW, 0.7,-0.15,cs*1.2, "body")
		mk("ClawTip", Enum.PartType.Ball, 0.46,0.34,0.34, CLAW, 1.05,-0.05,cs*1.45, "body")
	end
	for _, ls in ipairs({-1, 1}) do                                                -- 6 little legs
		for i = 1, 3 do mk("Leg", Enum.PartType.Ball, 0.26,0.62,0.26, DARK, -0.5+(i-1)*0.5, -0.9, ls*0.95, "leg") end
	end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- CRACK MINIGAME: a small popup -- tap the coconut NEED times within WINDOW seconds to crack it.
-- ============================================================================================
-- SHARED MINIGAME UI KIT. All four quest minigames are built from these, so they read as ONE
-- system instead of four unrelated popups: house-blue gradient card, thick white border, navy
-- cartoon drop shadow, gold header strip with an X, and the same adaptive scale the rest of the
-- HUD uses. Colours are the house palette -- bright and kid-friendly, navy for shadow, never black.
-- ============================================================================================
local MG = {
	blueTop = Color3.fromRGB(26, 79, 214),   -- panel gradient top
	blueBot = Color3.fromRGB(14, 59, 176),   -- panel gradient bottom
	headTop = Color3.fromRGB(18, 62, 180),   -- header strip
	headBot = Color3.fromRGB(10, 44, 140),
	navy    = Color3.fromRGB(6, 26, 80),     -- shadows + meter troughs (never black)
	trough  = Color3.fromRGB(10, 40, 110),
	white   = Color3.fromRGB(255, 255, 255),
	lime    = Color3.fromRGB(126, 217, 87),
	gold    = Color3.fromRGB(255, 210, 74),
	amber   = Color3.fromRGB(255, 170, 60),
	red     = Color3.fromRGB(226, 76, 72),
	ice     = Color3.fromRGB(206, 226, 255), -- caption text
}
local function mgCorner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 12); c.Parent = inst; return c end
local function mgStroke(inst, col, th, trans)
	local s = Instance.new("UIStroke"); s.Color = col or MG.white; s.Thickness = th or 2; s.Transparency = trans or 0; s.Parent = inst; return s
end
local function mgGrad(inst, a, b, rot)
	local gr = Instance.new("UIGradient"); gr.Color = ColorSequence.new(a, b); gr.Rotation = rot or 90; gr.Parent = inst; return gr
end
-- glossy fill: a UIGradient MULTIPLIES the frame colour, so white->grey reads as a lit top edge on ANY hue
local function mgGloss(inst)
	local gr = Instance.new("UIGradient"); gr.Rotation = 90
	gr.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.new(0.90, 0.90, 0.90)),
		ColorSequenceKeypoint.new(1,   Color3.new(0.70, 0.70, 0.70)),
	})
	gr.Parent = inst; return gr
end
-- The standard modal card. The backdrop blocks clicks but NEVER closes the panel (X only -- house rule).
-- Body content starts at MG_BODY_TOP. Returns the shared pieces; each minigame adds its own body.
local MG_BODY_TOP = 78
local function mgCard(guiName, w, h, titleText, hintText)
	local pgui = player:WaitForChild("PlayerGui")
	-- ===== KILL ANY OLDER CARD OF THE SAME NAME FIRST =====
	-- Roblox happily keeps two ScreenGuis with identical names side by side, and this builder used to
	-- just add a new one. So an older build's card -- left in PlayerGui by a stale duplicate LocalScript,
	-- or baked into the place -- stayed put and rendered UNDERNEATH the new one: you would open the
	-- popcorn quest and see the previous version of the minigame. The name is the identity here, so any
	-- earlier copy is by definition dead and gets destroyed before the new card is parented.
	for _, old in ipairs(pgui:GetChildren()) do
		if old:IsA("ScreenGui") and old.Name == guiName then
			old:Destroy()
			warn("[Pet] destroyed a STALE '" .. guiName .. "' left over from an older build -- "
				.. "if this prints every join, delete the duplicate LocalScript in Studio.")
		end
	end
	local g = Instance.new("ScreenGui"); g.Name = guiName; g.ResetOnSpawn = false; g.DisplayOrder = 97
	-- 97, ABOVE NotifyCenter's hero banner at 95 (and its social lane at 94). A minigame card is a modal:
	-- it dims the world and takes every tap, so a banner drawing straight over it looked like a bug. Still
	-- BELOW the 100 menus, because opening the Pet Hub or the Shop should genuinely cover a quest card.
	-- QuestHud is what NotifyCenter watches to HOLD banners while this is up -- see the note there. Any
	-- future quest HUD only has to set this attribute to get the same treatment.
	g:SetAttribute("QuestHud", true)
	g.IgnoreGuiInset = true; g.Enabled = false; g.Parent = pgui
	local film = Instance.new("Frame"); film.Size = UDim2.new(1,0,1,0); film.BackgroundColor3 = MG.navy
	film.BackgroundTransparency = 0.45; film.BorderSizePixel = 0; film.Active = true; film.Parent = g
	-- ===== EVERY MINIGAME CARD IS THE HOUSE PANEL SIZE (700x520) =====
	-- The card frame is now the same footprint as the Shop / Daily Tasks / trade panels, whatever w/h the
	-- caller asks for -- so the crack, reel, fishing and pull minigames all open the same-sized window as
	-- every other menu instead of four different little cards. The caller's w/h still matters: it becomes
	-- the size of a CONTENT frame centred inside the card (see `body` below), so each minigame's hand-tuned
	-- internal layout keeps its coordinates and simply sits centred in the standard frame.
	-- holder carries the adaptive UIScale so the card is the same on-screen size on phone and desktop
	local holder = Instance.new("Frame"); holder.Size = UDim2.new(0, 700, 0, 520); holder.AnchorPoint = Vector2.new(0.5,0.5)
	holder.Position = UDim2.new(0.5,0,0.5,0); holder.BackgroundTransparency = 1; holder.Parent = g
	local scale = Instance.new("UIScale"); scale.Parent = holder
	local function fit()
		local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
		-- MOBILE: scale so the 700x520 card always fits inside ~92% of the viewport. The old clamp floored
		-- at 0.62, which was tuned for the small per-minigame cards -- at 700x520 that floor is 434x322,
		-- which OVERFLOWS a short phone screen (a 360-tall landscape viewport). This formula fits the card
		-- to the actual screen on every device; the 0.4 floor only guards against a degenerate viewport.
		scale.Scale = math.clamp(math.min(vp.X * 0.92 / 700, vp.Y * 0.92 / 520), 0.4, 1)
	end
	fit()
	pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end)
	local shadow = Instance.new("Frame"); shadow.Size = UDim2.new(1,0,1,0); shadow.Position = UDim2.new(0,7,0,9)
	shadow.BackgroundColor3 = MG.navy; shadow.BackgroundTransparency = 0.4; shadow.BorderSizePixel = 0; shadow.Parent = holder
	mgCorner(shadow, 22)
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(1,0,1,0); panel.BackgroundColor3 = MG.blueTop
	panel.BorderSizePixel = 0; panel.Parent = holder
	mgCorner(panel, 22); mgGrad(panel, MG.blueTop, MG.blueBot); mgStroke(panel, MG.white, 4)
	-- HEADER strip: rounded like the panel, with a filler squaring off its bottom edge + a gold rule
	local head = Instance.new("Frame"); head.Size = UDim2.new(1,0,0,50); head.BackgroundColor3 = MG.headTop
	head.BorderSizePixel = 0; head.Parent = panel
	mgCorner(head, 20); mgGrad(head, MG.headTop, MG.headBot)
	local sq = Instance.new("Frame"); sq.Size = UDim2.new(1,0,0,22); sq.Position = UDim2.new(0,0,1,-22)
	sq.BackgroundColor3 = MG.headBot; sq.BorderSizePixel = 0; sq.Parent = head
	local rule = Instance.new("Frame"); rule.Size = UDim2.new(1,0,0,3); rule.Position = UDim2.new(0,0,1,-3)
	rule.BackgroundColor3 = MG.gold; rule.BackgroundTransparency = 0.4; rule.BorderSizePixel = 0; rule.Parent = head
	local titl = Instance.new("TextLabel"); titl.Size = UDim2.new(1,-100,1,-6); titl.Position = UDim2.new(0,16,0,0)
	titl.BackgroundTransparency = 1; titl.Font = Enum.Font.FredokaOne; titl.TextSize = 23; titl.TextColor3 = MG.gold
	titl.TextXAlignment = Enum.TextXAlignment.Left; titl.TextScaled = false; titl.Text = titleText; titl.Parent = head
	mgStroke(titl, MG.navy, 2)
	local close = Instance.new("TextButton"); close.Size = UDim2.new(0,34,0,34); close.Position = UDim2.new(1,-45,0,8)
	close.BackgroundColor3 = MG.red; close.Text = "X"; close.Font = Enum.Font.GothamBold; close.TextSize = 18
	close.TextColor3 = MG.white; close.AutoButtonColor = false; close.Parent = head
	mgCorner(close, 10); mgStroke(close, MG.white, 2); mgGloss(close)
	local hintL = Instance.new("TextLabel"); hintL.Size = UDim2.new(1,-28,0,22); hintL.Position = UDim2.new(0,14,0,53)
	hintL.BackgroundTransparency = 1; hintL.Font = Enum.Font.GothamMedium; hintL.TextSize = 13; hintL.TextColor3 = MG.white
	hintL.TextWrapped = true; hintL.Text = hintText or ""; hintL.Parent = panel
	-- The minigame's own content area: the caller's original w x h, centred in the space below the header
	-- strip. Every call site parents its pieces to `panel` (or `holder`) using offsets tuned to that w x h,
	-- so BOTH names below point HERE -- the tuned layouts land unchanged, just centred in the big card.
	-- ===== THE CONTENT IS SCALED TO FILL THE CARD =====
	-- The card became the house 700x520 panel while each minigame kept its own small hand-tuned layout
	-- (330x342, 420x300, ...) pinned to the top. Everything landed where it always had and the leftover
	-- room simply appeared underneath -- so every minigame opened as a little cluster of controls floating
	-- in a large empty blue rectangle.
	--
	-- Rather than re-tuning four layouts by hand, the whole body is SCALED. One UIScale, computed from the
	-- card's real content area, applies to every minigame at once: the coconut, its "Crack it!" line and its
	-- progress bar all grow together, and so do the reel, the fishing and the pull.
	--
	-- The scale is UNIFORM, so nothing is stretched out of shape. It is the smaller of the two fits:
	--   * vertical -- content runs from just under the hint line down to BOTTOM_MARGIN off the bottom edge
	--   * horizontal -- capped so a wide layout cannot grow past the panel's side margins
	-- For the four current minigames the vertical fit binds on three and the horizontal on one, which is
	-- what the request describes: fill the height, keep even margins, no distortion.
	--
	-- MG_BODY_TOP is subtracted before scaling and added back after. Every minigame measures its pieces from
	-- the CARD's top edge (MG_BODY_TOP + n, i.e. "n below the header"), so that first 78px is header
	-- clearance, not content -- scaling it would just push everything down and undo the gain.
	local TOP_TARGET, BOTTOM_MARGIN, SIDE_MARGIN = 80, 16, 16
	local body = Instance.new("Frame"); body.Size = UDim2.new(0, w, 0, h)
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.BackgroundTransparency = 1; body.Parent = panel
	local contentH = math.max(1, h - MG_BODY_TOP)
	local bScale = math.min((520 - TOP_TARGET - BOTTOM_MARGIN) / contentH, (700 - SIDE_MARGIN * 2) / w)
	if bScale < 1 then bScale = 1 end   -- never shrink a layout that already fits
	local bs = Instance.new("UIScale"); bs.Scale = bScale; bs.Parent = body
	-- Pull the body up by the scaled header clearance so the FIRST piece of content lands on TOP_TARGET.
	-- The body's own top edge ends up above the panel, which is invisible: it is a transparent frame and
	-- no minigame places anything above MG_BODY_TOP.
	body.Position = UDim2.new(0.5, 0, 0, TOP_TARGET - bScale * MG_BODY_TOP)
	return { gui = g, holder = body, panel = body, card = panel, head = head, title = titl, hint = hintL, close = close }
end
-- A labelled meter: caption + rounded trough + glossy fill. Returns the FILL frame to drive.
local function mgMeter(parent, x, y, w, label, col)
	local cap = Instance.new("TextLabel"); cap.Size = UDim2.new(0,w,0,14); cap.Position = UDim2.new(0,x,0,y)
	cap.BackgroundTransparency = 1; cap.Font = Enum.Font.GothamBold; cap.TextSize = 11
	cap.TextXAlignment = Enum.TextXAlignment.Left; cap.TextColor3 = MG.ice; cap.Text = label; cap.Parent = parent
	local bg = Instance.new("Frame"); bg.Size = UDim2.new(0,w,0,16); bg.Position = UDim2.new(0,x,0,y+15)
	bg.BackgroundColor3 = MG.navy; bg.BorderSizePixel = 0; bg.Parent = parent
	mgCorner(bg, 8); mgStroke(bg, MG.trough, 2, 0.25)
	local f = Instance.new("Frame"); f.Size = UDim2.new(0,0,1,0); f.BackgroundColor3 = col; f.BorderSizePixel = 0; f.Parent = bg
	mgCorner(f, 8); mgGloss(f)
	return f
end

local crackUI, crackBusy = nil, false
local function ensureCrackUI()
	if crackUI then return crackUI end
	local ui = mgCard("CoconutCrackGui", 330, 342, "CRACK THE COCONUT!", "Tap the coconut to fill the bar before it drains!")
	local panel = ui.panel
	-- the coconut sits on a lighter round pad so the tap target reads as a target
	local pad = Instance.new("Frame"); pad.Size = UDim2.new(0,176,0,176); pad.Position = UDim2.new(0.5,0,0,MG_BODY_TOP)
	pad.AnchorPoint = Vector2.new(0.5,0); pad.BackgroundColor3 = MG.navy; pad.BackgroundTransparency = 0.55
	pad.BorderSizePixel = 0; pad.Parent = panel
	mgCorner(pad, 88); mgStroke(pad, MG.white, 2, 0.65)
	local coco = Instance.new("TextButton"); coco.Size = UDim2.new(0,152,0,152); coco.Position = UDim2.new(0.5,0,0.5,0)
	coco.AnchorPoint = Vector2.new(0.5,0.5); coco.BackgroundColor3 = Color3.fromRGB(126, 82, 48)
	coco.Text = "\xF0\x9F\xA5\xA5"; coco.TextSize = 92; coco.Font = Enum.Font.GothamBold; coco.AutoButtonColor = false; coco.Parent = pad
	mgCorner(coco, 76); mgStroke(coco, MG.white, 3); mgGloss(coco)
	local cnt = Instance.new("TextLabel"); cnt.Size = UDim2.new(1,-28,0,24); cnt.Position = UDim2.new(0,14,0,MG_BODY_TOP+184)
	cnt.BackgroundTransparency = 1; cnt.Font = Enum.Font.FredokaOne; cnt.TextSize = 18; cnt.TextColor3 = MG.white
	cnt.Text = "Crack it!"; cnt.Parent = panel
	mgStroke(cnt, MG.navy, 2)
	local bar = mgMeter(panel, 16, MG_BODY_TOP + 212, 298, "CRACK PROGRESS", MG.lime)
	-- `close` IS LOAD-BEARING and was missing. mgCard always builds the X, but this table is all that
	-- openCrackMinigame below can see -- leave the button out of it and there is nothing to connect the click
	-- to, so the X renders, highlights on hover, and does nothing. Worse than nothing, actually: the panel
	-- stays up AND crackBusy stays true, so the coconut prompts refuse to open a new minigame afterwards.
	-- The reel and broccoli minigames both keep theirs (see spinUI / the pull UI); this one didn't.
	crackUI = { gui = ui.gui, coco = coco, cnt = cnt, bar = bar, hint = ui.hint, close = ui.close }
	return crackUI
end
-- Per-coconut difficulty for the TUG-OF-WAR crack: drain = how fast the bar falls/sec; fill = how much each
-- tap pushes it up. Success when the bar reaches the TOP (need taps/sec > drain/fill). `secs` is a HARD
-- FLOOR -- the bar is clamped to a ceiling that rises over exactly that many seconds, so no amount of
-- mashing finishes a coconut early; tapping slower than the ceiling still costs extra time.
--
-- ===== RETUNED SHORT AGAIN: 2.5-4s FLOORS (was 6-11s, before that 15-19s) =====
-- `secs` is the only number that decides how long a coconut ACTUALLY takes, because the ceiling it drives
-- is a hard clamp -- no amount of mashing beats it. 6-11s still read as slow across seven coconuts, so the
-- floors come down to "a few seconds each": 2.5s on the first, 4s on the last.
--
-- `fill` is raised to match. The ceiling now rises ~0.34/sec, so the bar needs ~2.5 taps/sec just to keep
-- pace with it -- at the old fill values a player would tap well UNDER the ceiling and the real time would
-- drift back over the floor, which is exactly how the 15-19s floors played as 45s. A big fill keeps normal
-- tapping pinned to the ceiling, so the floor is what players actually experience.
--
-- Taps to crack = (rise + drain x secs) / fill, where rise = 1 - CRACK_START:
--   coconut 1 ~4 taps ... coconut 7 ~5 taps; whole quest ~31 taps and ~23s of floors (was ~57s, orig ~115s).
-- Still a real tapping minigame -- just a short one. The easy/medium/hard curve keeps its shape.
local CRACK_START = 0.16 -- where the bar starts (also fixes how far it has to climb)
local CRACK_DIFFICULTY = {
	[1] = { drain = 0.05, fill = 0.24, secs = 2.5, name = "Easy" },
	[2] = { drain = 0.05, fill = 0.24, secs = 2.5, name = "Easy" },
	[3] = { drain = 0.06, fill = 0.23, secs = 3,   name = "Easy" },
	[4] = { drain = 0.06, fill = 0.22, secs = 3,   name = "Medium" },
	[5] = { drain = 0.07, fill = 0.21, secs = 3.5, name = "Medium" },
	[6] = { drain = 0.07, fill = 0.20, secs = 3.5, name = "Hard" },
	[7] = { drain = 0.08, fill = 0.20, secs = 4,   name = "Hard" },
}

-- TUG-OF-WAR crack: the fill bar constantly DRAINS down; each tap pushes it UP. Fill it to the TOP to crack.
-- Forgiving -- if it drains all the way to empty the GUI just closes (retry), no hard fail.
local function openCrackMinigame(onCracked, diff)
	if crackBusy then return end
	crackBusy = true
	local ui = ensureCrackUI()
	-- default matches the retuned CRACK_DIFFICULTY above -- an 8th coconut falling back to this default
	-- would otherwise be the one that still cost the old number of taps
	diff = diff or { drain = 0.06, fill = 0.22, secs = 3, name = "" }
	local fill = CRACK_START -- small head start so the long crack still starts near-empty
	-- TIME FLOOR: `ceiling` rises from the start position to full over diff.secs and the bar is clamped to it,
	-- so the crack can NEVER complete faster than that no matter how fast the player taps.
	local ceiling = fill
	local ceilRate = (1 - CRACK_START) / (diff.secs or 16)
	local done = false
	local started = false -- the bar holds steady until the FIRST tap; drain only begins then (a moment to react)
	ui.hint.Text = "Tap to FILL the bar before it drains!"
	ui.cnt.Text = "Crack it!" -- NO difficulty shown to the player (the tier still varies under the hood)
	ui.bar.Size = UDim2.new(fill, 0, 1, 0); ui.bar.BackgroundColor3 = Color3.fromRGB(80,220,80)
	ui.gui.Enabled = true
	local conn, closeConn
	local function finish(success)
		if done then return end
		done = true
		if conn then conn:Disconnect() end
		-- BOTH connections must go. crackUI is CACHED and reused for every coconut, so the X button outlives
		-- this minigame -- leaving its handler attached would stack another one on each open, and by the 7th
		-- coconut a single tap of the X would fire seven finishes.
		if closeConn then closeConn:Disconnect() end
		ui.gui.Enabled = false; crackBusy = false
		if success then onCracked() end
	end
	-- X CLOSES IT, and closing counts as giving up, not as cracking -- finish(false) leaves the coconut
	-- uncracked and the count untouched, so it can simply be tried again. Same contract as the reel and
	-- broccoli minigames: the X is the ONLY way out, a stray tap elsewhere never shuts the panel.
	closeConn = ui.close.MouseButton1Click:Connect(function() finish(false) end)
	conn = ui.coco.MouseButton1Click:Connect(function()
		if done then return end
		started = true -- first tap arms the drain (the tug-of-war is now on)
		-- THE THWACK. Pitch jitters +/-7% so mashing reads as repeated blows rather than a stuck loop.
		pcall(function()
			cocoHitSound.PlaybackSpeed = 0.93 + math.random() * 0.14
			cocoHitSound.TimePosition = 0
			cocoHitSound:Play()
		end)
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end   -- and a tap you can feel
		fill = math.min(1, fill + diff.fill)
		if fill > ceiling then fill = ceiling end -- mashing can't outrun the time floor
		ui.bar.Size = UDim2.new(fill, 0, 1, 0)
		pcall(function() game:GetService("TweenService"):Create(ui.coco, TweenInfo.new(0.05), { Rotation = math.random(-12,12) }):Play() end)
		if fill >= 1 then finish(true) end
	end)
	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = now - last; last = now -- keep `last` current even while paused (no drain accrues before the first tap)
			if started then -- the bar only starts draining AGAINST the player after their first tap
				ceiling = math.min(1, ceiling + ceilRate * dt) -- the time floor advances from the first tap
				fill = math.max(0, math.min(fill, ceiling) - diff.drain * dt)
				ui.bar.Size = UDim2.new(fill, 0, 1, 0)
				ui.bar.BackgroundColor3 = (fill > 0.5) and Color3.fromRGB(80,220,80) or Color3.fromRGB(235,170,55)
				if fill <= 0 then ui.hint.Text = "Drained! Try again."; task.wait(0.35); finish(false); break end
			end
			task.wait()
		end
	end)
end

-- CAVE KEY reveal: a key pops up centre-screen, holds, then floats away + fades.
local function showKeyReveal()
	local pgui = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui"); g.Name = "CaveKeyReveal"; g.ResetOnSpawn = false; g.DisplayOrder = 95; g.Parent = pgui
	local f = Instance.new("Frame"); f.Size = UDim2.new(0,40,0,24); f.Position = UDim2.new(0.5,0,0.4,0); f.AnchorPoint = Vector2.new(0.5,0.5)
	f.BackgroundColor3 = Color3.fromRGB(25,90,185); f.BackgroundTransparency = 0.05; f.Parent = g
	Instance.new("UICorner", f).CornerRadius = UDim.new(0,16); local s = Instance.new("UIStroke", f); s.Color = Color3.fromRGB(255,215,0); s.Thickness = 3
	local key = Instance.new("TextLabel"); key.Size = UDim2.new(1,0,0,80); key.Position = UDim2.new(0,0,0,12); key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamBold; key.TextSize = 56; key.Text = "\xF0\x9F\x97\x9D\xEF\xB8\x8F"; key.Parent = f
	local txt = Instance.new("TextLabel"); txt.Size = UDim2.new(1,-16,0,40); txt.Position = UDim2.new(0,8,1,-52); txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.GothamBold; txt.TextSize = 20; txt.TextColor3 = Color3.fromRGB(255,215,0); txt.Text = "You got the Cave Key!"; txt.Parent = f
	local TW = game:GetService("TweenService")
	TW:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0,260,0,150)}):Play()
	task.delay(2.0, function()
		TW:Create(f, TweenInfo.new(0.5), {Position = UDim2.new(0.5,0,0.25,0), BackgroundTransparency = 1}):Play()
		TW:Create(s, TweenInfo.new(0.5), {Transparency = 1}):Play()
		TW:Create(key, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		TW:Create(txt, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		task.delay(0.6, function() g:Destroy() end)
	end)
	print("[Pet][UI] cave key reveal shown")
end

-- Build the COCONUT quest world: 7 crackable coconuts + the chest (key-gated) that reveals the egg on open.
local function buildCoconutWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isCrack = true
	local pieces = positions.pieces or {}
	-- PER-COCONUT PLACEMENT NUDGE, in studs, applied on top of the marker position.
	--
	-- Coconut4's marker sits low enough that the ball ends up inside the island geometry -- present and
	-- rendering, but not visible or reachable. +2 studs lifts it clear. It is listed HERE, one coconut, by
	-- number, rather than detected at runtime: an earlier attempt tried to spot buried coconuts automatically
	-- and floated several healthy ones instead, because "is this ball touching something" is also true of
	-- every coconut resting on the ground. Everything not in this table is placed exactly on its marker.
	--
	-- This is a patch over a marker that is slightly too low. Moving 'Coconut4' up in Studio and deleting the
	-- entry below is the real fix -- with the entry still here, doing that would raise it twice.
	--
	-- Declared inside this function ON PURPOSE: PetFollow's main chunk is at Luau's 200-local ceiling, and a
	-- new top-level local is what produced "Out of local registers" and killed the whole script last time.
	local COCO_NUDGE = { [4] = Vector3.new(0, 1.75, 0) } -- was +2; dropped 0.25 to sit right
	-- 7 coconuts (hidden until applyState confirms !owns). Hold E -> crack minigame -> count + server collect.
	for i = 1, #def.pieceMarkers do
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			-- applied before anything reads `pos`, so the ball, its prompt, the "cracked!" text and the
			-- on-landing hint anchor all agree on one position
			pos = pos + (COCO_NUDGE[i] or Vector3.zero)
			st.hintAnchor = st.hintAnchor or pos -- the on-landing hint anchors at a COCONUT (on the island), not the cave chest
			local coco = Instance.new("Model"); coco.Name = "Coconut"..i
			local b = newPart(coco, "Coco", Enum.PartType.Ball, Vector3.new(1.6,1.6,1.6), Color3.fromRGB(112,72,42), CFrame.new(pos), Enum.Material.SmoothPlastic)
			coco.PrimaryPart = b
			for _, sp in ipairs({ {0,0.2,0.65}, {-0.3,-0.2,0.6}, {0.3,-0.2,0.6} }) do
				newPart(coco, "Spot", Enum.PartType.Ball, Vector3.new(0.3,0.3,0.2), Color3.fromRGB(66,40,22), CFrame.new(pos) * CFrame.new(sp[1],sp[2],sp[3]))
			end
			local pp = addPrompt(b, "Crack Coconut", "Coconut", function()
				if st.collected[i] or st.owns then return end
				if not _G.petQuestGate(def, pos) then return end -- the Beachcomber has to hand you this first
				openCrackMinigame(function()
					if st.collected[i] or st.owns then return end
					st.collected[i] = true
					local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
					setVisible(coco, false)
					floatText(pos + Vector3.new(0,2,0), "Coconut cracked! "..count.."/"..#def.pieceMarkers)
					pcall(function() PetCollectEvent:FireServer(petId, i) end)
					-- the 7th distinct crack (in ANY order) grants the CAVE KEY -> reveal + unlock the chest
					if count >= #def.pieceMarkers and not st.hasKey then
						st.hasKey = true
						showKeyReveal()
						if st.chestGlow then st.chestGlow(true) end
						print("[Pet] "..player.Name.." cracked 7/7 -> Cave Key granted")
					end
				end, CRACK_DIFFICULTY[i])
			end)
			pp.HoldDuration = 0.5 -- HOLD E to start the minigame
			st.pieces[i] = coco

			setVisible(coco, false)
			print(string.format("[Pet][DIAG] built coconut %d (%s) at (%.0f,%.0f,%.0f)", i, (CRACK_DIFFICULTY[i] and CRACK_DIFFICULTY[i].name or "?"), pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] coconut "..i.." position MISSING for "..petId)
		end
	end
	-- CHEST in the cave (always visible to non-owners). Key-gated prompt -> opens -> reveals the egg.
	local eggPos = positions.egg
	if typeof(eggPos) ~= "Vector3" then warn("[Pet][DIAG] chest position MISSING for "..petId); return end
	st.eggPos = eggPos
	-- rotate the WHOLE chest 130 deg CCW about Y (positive Y = CCW from above) so it faces the player's approach
	local chestRot = CFrame.Angles(0, math.rad(130), 0)
	local function chestCF(ox, oy, oz) return CFrame.new(eggPos) * chestRot * CFrame.new(ox, oy, oz) end
	local chest = Instance.new("Model"); chest.Name = petId.."Chest"
	local base = newPart(chest, "ChestBase", Enum.PartType.Block, Vector3.new(4,2.2,3), Color3.fromRGB(120,78,40), chestCF(0,1.1,0), Enum.Material.SmoothPlastic)
	chest.PrimaryPart = base
	newPart(chest, "Band", Enum.PartType.Block, Vector3.new(4.1,0.4,3.1), Color3.fromRGB(70,70,80), chestCF(0,0.6,0), Enum.Material.Metal)
	newPart(chest, "Band", Enum.PartType.Block, Vector3.new(4.1,0.4,3.1), Color3.fromRGB(70,70,80), chestCF(0,1.7,0), Enum.Material.Metal)
	local lid = Instance.new("Model"); lid.Name = "Lid"; lid.Parent = chest
	local lidHinge = chestCF(0, 2.2, -1.5).Position -- back-top hinge (in the rotated frame)
	local lidPart = newPart(lid, "ChestLid", Enum.PartType.Block, Vector3.new(4,1.2,3), Color3.fromRGB(138,92,50), chestCF(0,2.6,0), Enum.Material.SmoothPlastic)
	lid.PrimaryPart = lidPart
	newPart(lid, "Lock", Enum.PartType.Block, Vector3.new(0.7,0.9,0.4), Color3.fromRGB(220,190,60), chestCF(0,2.1,1.55), Enum.Material.Metal)
	chest.Parent = Workspace
	st.chest = chest
	-- toggle a gold glow on the chest once the player has the Cave Key (used by applyState)
	st.chestGlow = function(on)
		if on and not st.chestHl then
			local hl = Instance.new("Highlight"); hl.Name = "ChestGlow"; hl.FillColor = Color3.fromRGB(255,225,120); hl.FillTransparency = 0.6
			hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = chest; hl.Parent = chest; st.chestHl = hl
		elseif not on and st.chestHl then st.chestHl:Destroy(); st.chestHl = nil end
	end
	-- reveal the EGG (themed coconut egg) above the open chest, with the hatch prompt
	local function revealEgg()
		if st.egg then return end
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,80,46), nil)
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for _, sp in ipairs({ {0,0.4,1.35}, {-0.55,-0.2,1.25}, {0.55,-0.2,1.25} }) do
			newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.35), Color3.fromRGB(66,40,22), CFrame.new(sp[1],sp[2],sp[3]))
		end
		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 3.6, 0))
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,235,150); hl.FillTransparency = 0.55; hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Coconut Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function()
			local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
	end
	-- open the chest: rotate the lid up about its hinge + sparkle, then reveal the egg
	local function openChest()
		pcall(function()
			local TW = game:GetService("TweenService")
			local startCF = lid:GetPivot()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			local hingeFrame = CFrame.new(lidHinge) * chestRot -- pitch about the chest's LOCAL X (the hinge), so it opens UP relative to the rotated chest
			nv:GetPropertyChangedSignal("Value"):Connect(function()
				pcall(function() lid:PivotTo(hingeFrame * CFrame.Angles(math.rad(-100*nv.Value),0,0) * hingeFrame:Inverse() * startCF) end)
			end)
			TW:Create(nv, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = 1}):Play()
		end)
		pcall(function()
			local fx = Instance.new("Part"); fx.Anchored = true; fx.CanCollide = false; fx.CanQuery = false; fx.Transparency = 1; fx.Size = Vector3.new(1,1,1); fx.CFrame = CFrame.new(eggPos + Vector3.new(0,2.5,0)); fx.Parent = Workspace
			local em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/sparkles_main.dds"; em.Color = ColorSequence.new(Color3.fromRGB(255,235,150))
			em.Lifetime = NumberRange.new(0.5,1.0); em.Speed = NumberRange.new(4,10); em.SpreadAngle = Vector2.new(180,180); em.Rate = 0; em.Size = NumberSequence.new(1.2); em.LightEmission = 0.9; em.Parent = fx
			em:Emit(40); game:GetService("Debris"):AddItem(fx, 1.2)
		end)
		task.delay(0.5, revealEgg)
	end
	-- the key-gated chest prompt
	local prompt
	prompt = addPrompt(base, "Use Cave Key", "Treasure Chest", function()
		if st.owns or st.chestOpened then return end
		if not (st.hasKey or (st.uiFound or 0) >= #def.pieceMarkers) then -- locked until the Cave Key is earned (7/7)
			floatText(eggPos + Vector3.new(0,3.2,0), "Locked \xE2\x80\x94 find the Cave Key")
			print("[Pet] "..player.Name.." opened the chest blocked (no key)")
			return
		end
		st.chestOpened = true
		prompt.Enabled = false -- REMOVE the chest prompt the moment it opens, so it never overlaps the egg's hatch prompt
		print("[Pet] "..player.Name.." opened the chest (had key)")
		openChest() -- the egg's Hatch prompt appears ~0.5s later (revealEgg), after this one is already off -> only one prompt active
	end)
	prompt.HoldDuration = 0.4
	print(string.format("[Pet][DIAG] built coconut chest at (%.0f,%.0f,%.0f)", eggPos.X, eggPos.Y, eggPos.Z))
end

-- ============================================================================================
-- POPCORN SHEEP QUEST (questType "film-reels"). Movie-theater themed multi-stage quest: find 6 FILM REELS
-- -> LOAD them at the PROJECTOR -> a mini-movie plays on the SCREEN (flicker -> egg falls/bounces ->
-- "NEW PET!") -> the egg materializes in a SPOTLIGHT at PopcornEggSpot -> hatch -> the Popcorn Sheep
-- follows. Reuses the same server collect/claim/inventory + the shared HATCH flow. Cosmetic-only.
-- ============================================================================================

-- ===== FILM REEL MINIGAME: a SPINNING/SWEEPING METER (deliberately DIFFERENT from the coconut tug-of-war).
-- A marker sweeps back and forth across a track with a green TARGET ZONE; tap STOP to halt it. Stop inside the
-- zone -> the reel is collected; miss -> the sweep keeps going so you can try again (not punishing). Per reel,
-- with the zone shrinking + the sweep speeding up for later reels. Single-tap = mobile-friendly. Cosmetic-only.
local spinUI, spinBusy = nil, false
local function ensureSpinUI()
	if spinUI then return spinUI end
	local ui = mgCard("FilmReelSpinGui", 420, 300, "WIND THE FILM!",
		"Tap WIND until the reel is full.")
	local panel = ui.panel
	local BODY = MG_BODY_TOP + 10

	-- ===== THE BENCH: SUPPLY REEL -> FILM -> TAKE-UP REEL =====
	-- Two reels with the film strip running between them. The supply reel SHRINKS and the take-up reel GROWS
	-- as you wind, so progress is legible from the picture alone before you read a single number.
	local function reel(x, size)
		local r = Instance.new("Frame"); r.Size = UDim2.new(0, size, 0, size)
		r.AnchorPoint = Vector2.new(0.5, 0.5); r.Position = UDim2.new(0, x, 0, BODY + 74)
		r.BackgroundColor3 = Color3.fromRGB(38, 34, 40); r.BorderSizePixel = 0; r.Parent = panel
		Instance.new("UICorner", r).CornerRadius = UDim.new(1, 0)
		mgStroke(r, MG.trough, 3, 0.15)
		-- spokes: the thing that makes rotation READABLE. A plain disc spinning looks static.
		for i = 0, 2 do
			local sp = Instance.new("Frame"); sp.Size = UDim2.new(0.86, 0, 0, 5)
			sp.AnchorPoint = Vector2.new(0.5, 0.5); sp.Position = UDim2.fromScale(0.5, 0.5)
			sp.Rotation = i * 60; sp.BackgroundColor3 = Color3.fromRGB(96, 88, 100)
			sp.BorderSizePixel = 0; sp.Parent = r
		end
		local hub = Instance.new("Frame"); hub.Size = UDim2.fromScale(0.3, 0.3)
		hub.AnchorPoint = Vector2.new(0.5, 0.5); hub.Position = UDim2.fromScale(0.5, 0.5)
		hub.BackgroundColor3 = Color3.fromRGB(140, 130, 145); hub.BorderSizePixel = 0; hub.Parent = r
		Instance.new("UICorner", hub).CornerRadius = UDim.new(1, 0)
		return r
	end
	local supply = reel(96, 118)
	local takeup = reel(324, 60)

	-- the film strip stretched between them, with sprocket holes that SCROLL while winding
	local strip = Instance.new("Frame"); strip.Size = UDim2.new(0, 150, 0, 26)
	strip.AnchorPoint = Vector2.new(0.5, 0.5); strip.Position = UDim2.new(0, 210, 0, BODY + 74)
	strip.BackgroundColor3 = Color3.fromRGB(24, 22, 28); strip.BorderSizePixel = 0; strip.Parent = panel
	strip.ClipsDescendants = true
	mgStroke(strip, Color3.fromRGB(70, 64, 76), 2, 0.3)
	local holes = {}
	for i = 1, 12 do
		local hlow = Instance.new("Frame"); hlow.Size = UDim2.new(0, 7, 0, 6)
		hlow.Position = UDim2.new(0, (i - 1) * 16, 0, 3)
		hlow.BackgroundColor3 = Color3.fromRGB(224, 220, 210); hlow.BorderSizePixel = 0; hlow.Parent = strip
		local hhi = hlow:Clone(); hhi.Position = UDim2.new(0, (i - 1) * 16, 1, -9); hhi.Parent = strip
		holes[#holes + 1] = hlow; holes[#holes + 1] = hhi
	end

	-- the CRANK on the take-up reel: an arm with a knob, rotating a notch per wind
	local crank = Instance.new("Frame"); crank.Size = UDim2.new(0, 54, 0, 8)
	crank.AnchorPoint = Vector2.new(0, 0.5); crank.Position = UDim2.new(0, 324, 0, BODY + 74)
	crank.BackgroundColor3 = Color3.fromRGB(188, 150, 70); crank.BorderSizePixel = 0; crank.Parent = panel
	mgCorner(crank, 4); mgStroke(crank, MG.navy, 2)
	local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 16, 0, 16)
	knob.AnchorPoint = Vector2.new(0.5, 0.5); knob.Position = UDim2.new(1, -2, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(230, 196, 96); knob.BorderSizePixel = 0; knob.Parent = crank
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	mgStroke(knob, MG.navy, 2)

	-- ONE BAR, ONE BUTTON. There was a tension gauge here with a red band and a snap-the-film penalty --
	-- two systems to read and a way to lose, on a quest that is meant to be a pleasant thirty seconds of
	-- winding a reel. It is gone: tap WIND, the bar fills, the reels turn. Nothing to fail.
	local progCap = Instance.new("TextLabel"); progCap.Size = UDim2.new(0, 200, 0, 14)
	progCap.Position = UDim2.new(0, 20, 0, BODY + 146); progCap.BackgroundTransparency = 1
	progCap.Font = Enum.Font.GothamBold; progCap.TextSize = 11; progCap.TextColor3 = MG.ice
	progCap.TextXAlignment = Enum.TextXAlignment.Left; progCap.Text = "FILM WOUND"; progCap.Parent = panel
	local progBg = Instance.new("Frame"); progBg.Size = UDim2.new(1, -40, 0, 24)
	progBg.Position = UDim2.new(0, 20, 0, BODY + 162); progBg.BackgroundColor3 = MG.navy
	progBg.BorderSizePixel = 0; progBg.Parent = panel
	mgCorner(progBg, 10); mgStroke(progBg, MG.trough, 2, 0.25)
	local progFill = Instance.new("Frame"); progFill.Size = UDim2.new(0, 0, 1, 0)
	progFill.BackgroundColor3 = Color3.fromRGB(255, 196, 84); progFill.BorderSizePixel = 0; progFill.Parent = progBg
	mgCorner(progFill, 10); mgGloss(progFill)

	local wind = Instance.new("TextButton"); wind.Size = UDim2.new(0, 220, 0, 60)
	wind.Position = UDim2.new(0.5, 0, 0, BODY + 200); wind.AnchorPoint = Vector2.new(0.5, 0)
	wind.BackgroundColor3 = Color3.fromRGB(46, 132, 62); wind.Text = "WIND"
	wind.Font = Enum.Font.FredokaOne; wind.TextSize = 26; wind.TextColor3 = MG.white
	wind.AutoButtonColor = false; wind.Parent = panel
	mgCorner(wind, 14); mgStroke(wind, MG.white, 3); mgGloss(wind)

	spinUI = {
		gui = ui.gui, panel = ui.holder, close = ui.close, hint = ui.hint,
		supply = supply, takeup = takeup, crank = crank, holes = holes,
		progFill = progFill, wind = wind,
	}
	return spinUI
end
-- WINDING TUNING (this replaced a stop-the-sweeping-marker minigame -- see ensureSpinUI for why).
-- `hits` = taps to wind that reel, and it is now the ONLY field that means anything. The old zone/speed
-- columns were the sweeping marker's target width and sweep rate, and a SPIN_MIN_SECONDS floor held a
-- finished reel back until the clock caught up -- all gone with the mechanic. Later reels are simply
-- longer, which is the entire difficulty curve; there is nothing to fail and nothing to wait out.
-- BACK TO THE ORIGINAL EFFORT. The original quest cost ONE well-timed stop per reel -- six actions
-- for the whole thing -- and the later 10..16-tap ramp made Popcorn Pinnacle far heavier than it
-- ever was. A literal 1 would make the winding pointless (the reels would not visibly turn), so
-- every reel is a flat 4 quick taps: about two seconds each, ~24 for the quest, no ramp. Say the
-- word and it drops to 1-per-reel for exact parity.
local SPIN_DIFFICULTY = {
	[1] = { hits = 4 },
	[2] = { hits = 4 },
	[3] = { hits = 4 },
	[4] = { hits = 4 },
	[5] = { hits = 4 },
	[6] = { hits = 4 },
}
local function openSpinMinigame(onSuccess, diff)
	if spinBusy then return end
	spinBusy = true
	local ui = ensureSpinUI()
	diff = diff or { hits = 14 }
	local needWinds = diff.hits or 14   -- cranks to wind this reel over. That is the ENTIRE rule.
	local winds = 0
	local crankAng, stripOff = 0, 0
	local done = false

	ui.hint.Text = "Tap WIND until the reel is full."
	ui.progFill.Size = UDim2.new(0, 0, 1, 0)
	ui.supply.Size = UDim2.new(0, 118, 0, 118)
	ui.takeup.Size = UDim2.new(0, 60, 0, 60)
	ui.gui.Enabled = true

	local conns = {}
	local function finish(success)
		if done then return end
		done = true
		for _, c in ipairs(conns) do c:Disconnect() end
		ui.gui.Enabled = false; spinBusy = false
		if success then onSuccess() end
	end

	-- One tap = one crank. No tension, no timer, no way to lose -- the reels turning and the bar filling
	-- ARE the game. Winding an old projector reel is meant to be satisfying, not a test.
	conns[#conns+1] = ui.wind.MouseButton1Click:Connect(function()
		if done then return end
		winds = winds + 1
		crankAng = crankAng + 72   -- a fifth of a turn: the arm visibly steps round
		stripOff = stripOff + 16   -- one sprocket hole of film travels
		if winds >= needWinds then
			ui.hint.Text = "Reel wound -- got it!"
			task.wait(0.25); finish(true)
		else
			ui.hint.Text = "Wound " .. winds .. "/" .. needWinds
		end
	end)
	conns[#conns+1] = ui.close.MouseButton1Click:Connect(function() finish(false) end)

	task.spawn(function()
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = now - last; last = now
			local p = math.clamp(winds / math.max(needWinds, 1), 0, 1)
			ui.progFill.Size = UDim2.new(p, 0, 1, 0)
			-- the crank eases toward its stepped angle, and BOTH reels spin with it
			ui.crank.Rotation = ui.crank.Rotation + (crankAng - ui.crank.Rotation) * math.min(1, dt * 12)
			ui.supply.Rotation = -ui.crank.Rotation * 0.55
			ui.takeup.Rotation = ui.crank.Rotation
			-- film physically moves from the big reel to the small one
			ui.supply.Size = UDim2.new(0, 118 - 46 * p, 0, 118 - 46 * p)
			ui.takeup.Size = UDim2.new(0, 60 + 46 * p, 0, 60 + 46 * p)
			-- sprocket holes scroll so the strip itself reads as moving
			for i, h in ipairs(ui.holes) do
				local col = math.floor((i - 1) / 2)
				h.Position = UDim2.new(0, (col * 16 - stripOff) % 192 - 8, h.Position.Y.Scale, h.Position.Y.Offset)
			end
			task.wait()
		end
	end)
end

-- a low-poly FILM REEL collectible: a flat dark disc (round face up) + a raised hub + a few holes. Built in
-- place at `pos` (with an optional yaw) -- like the coconuts -- so the flat orientation isn't lost to PivotTo.
local function buildFilmReel(pos, yaw)
	local model = Instance.new("Model"); model.Name = "FilmReel"
	local DARK, RIM, HUB, HOLE = Color3.fromRGB(28,28,32), Color3.fromRGB(58,58,66), Color3.fromRGB(82,82,92), Color3.fromRGB(12,12,15)
	local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's round faces are on local X; rotate X->Y so the disc lies FLAT (face up)
	local frame = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
	local function at(ox, oy, oz) return frame * CFrame.new(ox, oy, oz) * FLAT end -- oy = up (face normal); ox/oz spread on the disc
	local disc = newPart(model, "Reel", Enum.PartType.Cylinder, Vector3.new(0.5,2.6,2.6), DARK, at(0,0,0))
	model.PrimaryPart = disc
	newPart(model, "Rim", Enum.PartType.Cylinder, Vector3.new(0.42,2.9,2.9), RIM, at(0,-0.04,0))     -- classic reel edge
	newPart(model, "Hub", Enum.PartType.Cylinder, Vector3.new(0.7,0.9,0.9), HUB, at(0,0.16,0))        -- raised centre hub
	newPart(model, "HubHole", Enum.PartType.Cylinder, Vector3.new(0.74,0.34,0.34), HOLE, at(0,0.2,0))
	for k = 1, 5 do -- 5 round holes in a ring (the "couple of smaller circles" look)
		local a = (k-1) * (2*math.pi/5)
		newPart(model, "Hole", Enum.PartType.Cylinder, Vector3.new(0.56,0.66,0.66), HOLE, at(math.sin(a)*0.95, 0.18, math.cos(a)*0.95))
	end
	return model
end

-- placeholder POPCORN SHEEP follower: a fluffy off-white popcorn-wool body (cluster of bumps), a small face,
-- little legs, cute eyes. Registers parts into petAnims (body/head/leg/tail roles + eye) so the existing
-- animator gives it idle bob, blink, leg gait, head/tail sway. Refine the looks later. Cosmetic-only.
local function buildPopcornSheep(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "PopcornSheep"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local WOOL, FACE, LEG, DARK = Color3.fromRGB(252,248,228), Color3.fromRGB(58,46,40), Color3.fromRGB(70,56,46), Color3.fromRGB(24,24,24)
	-- BODY core + a cluster of popcorn-wool bumps all over it
	mk("Body", Enum.PartType.Ball, 2.4,2.0,2.2, WOOL, 0,0,0, "body")
	for _, b in ipairs({ {0.8,0.9,0.6},{0.6,1.0,-0.6},{-0.2,1.15,0.0},{-0.9,0.85,0.5},{-0.9,0.7,-0.5},{0.15,0.55,1.0},
	                     {0.15,0.5,-1.0},{-0.5,0.2,0.98},{-0.5,0.1,-0.98},{0.7,0.0,0.92},{0.7,-0.1,-0.92},{-1.05,0.05,0.0} }) do
		local r = 0.72 + math.abs(b[2])*0.04
		mk("Wool", Enum.PartType.Ball, r,r,r, WOOL, b[1],b[2],b[3], "body")
	end
	-- HEAD (small dark face at the front) + a wool tuft + ears
	mk("Head", Enum.PartType.Ball, 1.0,1.05,0.95, FACE, 1.25,0.35,0, "head")
	mk("Tuft", Enum.PartType.Ball, 0.78,0.7,0.78, WOOL, 1.12,1.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,0.62, "head")
	mk("Ear", Enum.PartType.Ball, 0.3,0.52,0.22, FACE, 1.0,0.7,-0.62, "head")
	for _, ez in ipairs({0.32, -0.32}) do -- cute eyes
		mk("Eye", Enum.PartType.Ball, 0.3,0.38,0.26, Color3.fromRGB(245,245,245), 1.74,0.45,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 1.9,0.42,ez, "head", true)
	end
	mk("Snout", Enum.PartType.Ball, 0.52,0.4,0.56, Color3.fromRGB(80,66,56), 1.78,0.06,0, "head")
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do -- 4 little legs
		mk("Leg", Enum.PartType.Ball, 0.42,1.0,0.42, LEG, lp[1],-1.4,lp[2], "leg")
	end
	mk("Tail", Enum.PartType.Ball, 0.55,0.55,0.55, WOOL, -1.3,0.3,0, "tail") -- tiny tail tuft
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- placeholder BUTTER DUCK follower: a glossy golden duck (rounded body, head + flat bill, little wings, cute
-- eyes). Registers parts (body/head/wing->tail/leg roles + eye) so the existing animator gives it idle bob,
-- blink, wing/tail flap, leg paddle. Refine the looks later. Cosmetic-only.
local function buildButterDuck(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "ButterDuck"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local BUTTER, DEEP, BILL, DARK = Color3.fromRGB(248,214,96), Color3.fromRGB(232,188,70), Color3.fromRGB(244,150,40), Color3.fromRGB(28,24,18)
	mk("Body", Enum.PartType.Ball, 2.5,2.0,2.1, BUTTER, 0,0,0, "body")          -- rounded duck body
	mk("Rump", Enum.PartType.Ball, 1.1,1.0,1.0, BUTTER, -1.25,0.35,0, "tail")    -- upturned tail end
	mk("TailTip", Enum.PartType.Ball, 0.5,0.5,0.7, DEEP, -1.85,0.6,0, "tail")
	mk("Neck", Enum.PartType.Ball, 0.95,1.2,0.95, BUTTER, 1.05,0.85,0, "head")   -- neck sweeping up
	mk("Head", Enum.PartType.Ball, 1.15,1.15,1.1, BUTTER, 1.5,1.6,0, "head")     -- round head, up front
	mk("Bill", Enum.PartType.Ball, 0.95,0.35,0.8, BILL, 2.2,1.45,0, "head")      -- flat duck bill
	mk("BillTip", Enum.PartType.Ball, 0.55,0.28,0.66, BILL, 2.55,1.4,0, "head")
	for _, ez in ipairs({0.42, -0.42}) do -- cute eyes on the head front
		mk("Eye", Enum.PartType.Ball, 0.34,0.4,0.3, Color3.fromRGB(245,245,245), 1.92,1.78,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.18,0.22,0.18, DARK, 2.1,1.76,ez, "head", true)
	end
	for _, ws in ipairs({1, -1}) do mk("Wing", Enum.PartType.Ball, 1.3,0.7,0.5, DEEP, -0.1,0.2,ws*1.15, "tail") end -- little side wings (flap with the tail role)
	for _, ls in ipairs({0.55, -0.55}) do mk("Leg", Enum.PartType.Ball, 0.4,0.7,0.5, BILL, 0.2,-1.35,ls, "leg") end  -- two webbed legs
	-- glossy buttery sheen on the solid body parts
	for _, e in ipairs(parts) do if e.part.Transparency < 1 then e.part.Reflectance = math.max(e.part.Reflectance, 0.08) end end
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- placeholder BURRITO ARMADILLO follower: a rounded tan armadillo with a banded burrito/tortilla shell back
-- (toasted bands arcing over the back), a pale belly, a pointy snout, little legs + tail, cute eyes. Registers
-- parts (body/head/leg/tail roles + eye) so the existing animator gives it idle bob, blink, leg gait, head/tail
-- sway. Placeholder -- refine the looks later. Cosmetic-only.
local function buildBurritoArmadillo(scale)
	local s = scale or 1
	local model = Instance.new("Model"); model.Name = "BurritoArmadillo"
	local parts = {}
	local function mk(name, shape, sx, sy, sz, color, x, y, z, role, eye, mat)
		local p = newPart(model, name, shape, Vector3.new(sx,sy,sz)*s, color, CFrame.new(x*s,y*s,z*s), mat)
		parts[#parts+1] = { part = p, base = p.CFrame, baseSize = p.Size, role = role or "body", eye = eye }
		return p
	end
	local root = newPart(model, "Root", Enum.PartType.Ball, Vector3.new(0.4,0.4,0.4)*s, Color3.new(1,1,1), CFrame.new(0,0,0))
	root.Transparency = 1; model.PrimaryPart = root -- +X = front (the follow loop yaws +X toward travel)
	local TORT, TOAST, BELLY, SNT, DARK = Color3.fromRGB(214,170,110), Color3.fromRGB(176,118,64), Color3.fromRGB(236,212,170), Color3.fromRGB(150,96,56), Color3.fromRGB(26,20,16)
	mk("Body", Enum.PartType.Ball, 2.6,2.0,2.2, TORT, 0,0,0, "body")                 -- rounded tan body
	for i = -2, 2 do mk("Band", Enum.PartType.Ball, 0.42,1.75,2.05, TOAST, i*0.5,0.55,0, "body") end -- toasted tortilla bands over the back
	mk("Belly", Enum.PartType.Ball, 2.2,1.0,1.9, BELLY, 0.1,-0.7,0, "body")          -- pale belly
	mk("Head", Enum.PartType.Ball, 1.1,1.05,1.0, TORT, 1.5,0.2,0, "head")
	mk("Snout", Enum.PartType.Ball, 0.85,0.5,0.5, SNT, 2.25,-0.05,0, "head")         -- pointy snout
	mk("SnoutTip", Enum.PartType.Ball, 0.32,0.3,0.34, DARK, 2.72,-0.05,0, "head")
	mk("Ear", Enum.PartType.Ball, 0.22,0.5,0.16, SNT, 1.15,0.85,0.42, "head")
	mk("Ear", Enum.PartType.Ball, 0.22,0.5,0.16, SNT, 1.15,0.85,-0.42, "head")
	for _, ez in ipairs({0.34,-0.34}) do
		mk("Eye", Enum.PartType.Ball, 0.3,0.36,0.26, Color3.fromRGB(245,245,245), 1.9,0.42,ez, "head", true)
		mk("Pupil", Enum.PartType.Ball, 0.16,0.2,0.16, DARK, 2.05,0.4,ez, "head", true)
	end
	for _, lp in ipairs({ {0.8,0.7},{0.8,-0.7},{-0.7,0.7},{-0.7,-0.7} }) do          -- four little legs
		mk("Leg", Enum.PartType.Ball, 0.42,0.9,0.42, SNT, lp[1],-1.35,lp[2], "leg")
	end
	mk("Tail", Enum.PartType.Ball, 0.7,0.6,0.6, TOAST, -1.5,-0.1,0, "tail")          -- tapering tail
	mk("TailTip", Enum.PartType.Ball, 0.4,0.34,0.34, SNT, -2.0,0.05,0, "tail")
	petAnims[model] = { s = s, parts = parts, t = 0, move = 0, blink = 1.5, lastPos = nil }
	return model
end

-- the 6 face normals (local space), used to pick which face of the EXISTING screen points at the player.
local FACE_NORMALS = {
	[Enum.NormalId.Front]  = Vector3.new(0,0,-1), [Enum.NormalId.Back]   = Vector3.new(0,0,1),
	[Enum.NormalId.Right]  = Vector3.new(1,0,0),  [Enum.NormalId.Left]   = Vector3.new(-1,0,0),
	[Enum.NormalId.Top]    = Vector3.new(0,1,0),  [Enum.NormalId.Bottom] = Vector3.new(0,-1,0),
}
-- the user's PopcornScreen is normally a single Part; if it's a Model, use its PrimaryPart / biggest BasePart.
local function screenSurfacePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart end
		local biggest, bv
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then local v = d.Size.X * d.Size.Y * d.Size.Z; if not bv or v > bv then bv = v; biggest = d end end
		end
		return biggest
	end
	return nil
end
-- CLIENT-side resolve of the real, still-visible PopcornScreen (island-then-Workspace, exact name). Needed
-- because with StreamingEnabled an Instance reference sent over the RemoteFunction arrives nil while island 8 is
-- streamed out -- so the client finds the part itself (the server keeps it in the world, un-hidden). Resolved
-- lazily at show time, when the player is standing right next to it, so it's guaranteed streamed in.
local function findIslandClient(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function resolveScreenPart(def)
	local name = (def.extraMarkers and def.extraMarkers.screen) or "PopcornScreen"
	local island = def.islandPrefix and findIslandClient(def.islandPrefix)
	local inst = (island and island:FindFirstChild(name, true)) or Workspace:FindFirstChild(name) or Workspace:FindFirstChild(name, true)
	return screenSurfacePart(inst)
end
local function dumpScreenLike(def)
	print("[Pet][DIAG] PopcornScreen NOT found by client - dump of screen-like parts:")
	local function scan(list, where)
		for _, m in ipairs(list) do
			local n = m.Name:lower()
			if n:find("screen") or n:find("popcorn") then
				print("[Pet][DIAG] screen-like: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
			end
		end
	end
	local island = def.islandPrefix and findIslandClient(def.islandPrefix)
	pcall(function() if island then scan(island:GetDescendants(), "island") end end)
	pcall(function() scan(Workspace:GetChildren(), "Workspace top") end)
end

-- Build the POPCORN quest world: 6 film reels + a projector (Load Reels) + a screen (mini-movie) + the
-- spotlight egg at PopcornEggSpot. Reuses the shared hatch flow (hatchEgg) once the egg is revealed.
local function buildPopcornWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isFilm = true
	local pieces = positions.pieces or {}
	local extra  = positions.extra or {}

	-- STAGE 1: 6 FILM REELS (hidden until applyState confirms !owns). E -> take -> count + server collect.
	for i = 1, #def.pieceMarkers do
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			st.hintAnchor = st.hintAnchor or pos -- the on-landing hint anchors at a REEL (on the island)
			local reel = buildFilmReel(pos, math.rad(i * 43)) -- built flat, in place, with a varied yaw
			local pp = addPrompt(reel.PrimaryPart, "Take Film Reel", "Film Reel", function()
				if st.collected[i] or st.owns then return end
				if not _G.petQuestGate(def, pos) then return end -- the Projectionist has to hand you this first
				openSpinMinigame(function() -- STOP-the-marker timing minigame per reel (not the coconut tap-fill)
					if st.collected[i] or st.owns then return end
					st.collected[i] = true
					local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
					setVisible(reel, false)
					floatText(pos + Vector3.new(0,2,0), "Film reel "..count.."/"..#def.pieceMarkers.."!")
					pcall(function() PetCollectEvent:FireServer(petId, i) end)
				end, SPIN_DIFFICULTY[i])
			end)
			pp.HoldDuration = 0.4 -- HOLD E to start the spinning-meter minigame
			st.pieces[i] = reel
			setVisible(reel, false)
			print(string.format("[Pet][DIAG] built film reel %d at (%.0f,%.0f,%.0f)", i, pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] film reel "..i.." position MISSING for "..petId)
		end
	end

	local eggPos    = positions.egg
	local projPos   = extra.projector
	local screenPos = extra.screen
	if typeof(eggPos) ~= "Vector3" then warn("[Pet][DIAG] PopcornEggSpot position MISSING for "..petId); return end
	st.eggPos = eggPos
	st.filmProps = {}
	-- at 6/6 the on-screen pointer guides to the PROJECTOR (load reels); after the show it points at the egg
	st.pointTarget = (typeof(projPos) == "Vector3") and projPos or eggPos

	-- ===== THE SCREEN: play the mini-movie on the user's EXISTING, still-visible PopcornScreen (NO duplicate
	-- code screen). The client RESOLVES the real screen BY NAME (island-then-Workspace) and remembers the broad
	-- face that points at the play area. With StreamingEnabled the screen may be streamed OUT at join, so this
	-- can fail now -- that's fine: playMovie retries it when the player is standing right at the screen. =====
	local function setupScreen()
		if st.screenPart and st.screenPart.Parent then return true end
		local part = resolveScreenPart(def)
		if not part then return false end
		local sz = part.Size
		local faces -- broad faces lie on the THINNEST axis; pick whichever points toward the egg/player
		if sz.Z <= sz.X and sz.Z <= sz.Y then faces = { Enum.NormalId.Front, Enum.NormalId.Back }
		elseif sz.X <= sz.Y and sz.X <= sz.Z then faces = { Enum.NormalId.Right, Enum.NormalId.Left }
		else faces = { Enum.NormalId.Top, Enum.NormalId.Bottom } end
		local aim = eggPos - part.Position -- the player stands at the egg spot, in front of the screen
		local best, bestDot
		for _, f in ipairs(faces) do
			local n = part.CFrame:VectorToWorldSpace(FACE_NORMALS[f])
			local d = (aim.Magnitude > 0.001) and n:Dot(aim.Unit) or 1
			if not bestDot or d > bestDot then bestDot = d; best = f end
		end
		local fw, fh -- the chosen face's width/height -> a matching canvas aspect (so the movie isn't stretched)
		if best == Enum.NormalId.Front or best == Enum.NormalId.Back then fw, fh = sz.X, sz.Y
		elseif best == Enum.NormalId.Left or best == Enum.NormalId.Right then fw, fh = sz.Z, sz.Y
		else fw, fh = sz.X, sz.Z end
		st.screenPart = part
		st.movieFace = best
		st.movieCanvas = Vector2.new(600, math.clamp(math.floor(600 * fh / math.max(fw, 1)), 150, 900))
		print("[Pet][DIAG] PopcornScreen resolved at "..part:GetFullName()..", attaching mini-movie SurfaceGui to "..best.Name.." face")
		return true
	end
	st.setupScreen = setupScreen
	setupScreen() -- try now; if the screen is streamed out at join this just no-ops -- playMovie retries (+ dumps) when the player is at it

	-- ===== THE PROJECTOR: a client-built prop at the marker, facing the screen + a translucent light BEAM =====
	local projBody
	if typeof(projPos) == "Vector3" then
		local faceTo = (typeof(screenPos) == "Vector3") and screenPos or eggPos
		local pdir = Vector3.new(faceTo.X - projPos.X, 0, faceTo.Z - projPos.Z)
		if pdir.Magnitude < 0.05 then pdir = Vector3.new(0,0,1) end
		local projCF = CFrame.lookAt(projPos, projPos + pdir.Unit) * CFrame.new(0, -1.0, 0) -- -Z points at the screen; net -1.0 (dropped 2.5 then raised 1.5) so the prop rests at the right height
		local proj = Instance.new("Model"); proj.Name = petId.."Projector"
		projBody = newPart(proj, "ProjBody", Enum.PartType.Block, Vector3.new(2.4,1.8,3.4), Color3.fromRGB(42,42,48), projCF * CFrame.new(0,1.4,0), Enum.Material.Metal)
		proj.PrimaryPart = projBody
		newPart(proj, "Lens", Enum.PartType.Cylinder, Vector3.new(1.2,1.1,1.1), Color3.fromRGB(150,210,255), projCF * CFrame.new(0,1.4,-1.9) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Neon)
		newPart(proj, "ReelTop", Enum.PartType.Cylinder, Vector3.new(0.5,1.6,1.6), Color3.fromRGB(28,28,32), projCF * CFrame.new(-0.6,2.6,0.5) * CFrame.Angles(0,0,math.rad(90)))
		newPart(proj, "ReelTop", Enum.PartType.Cylinder, Vector3.new(0.5,1.6,1.6), Color3.fromRGB(28,28,32), projCF * CFrame.new(0.7,2.6,-0.5) * CFrame.Angles(0,0,math.rad(90)))
		newPart(proj, "Stand", Enum.PartType.Block, Vector3.new(0.7,1.4,0.7), Color3.fromRGB(30,30,34), projCF * CFrame.new(0,0.2,0))
		proj.Parent = Workspace
		-- gold glow on the projector (SAME chest-style Highlight) so the player can find it once the reels are
		-- collected; toggled by applyState. st.* fields only -- no new module-scope locals.
		st.projector = proj
		st.projGlow = function(on)
			if on and not st.projHl then
				local hl = Instance.new("Highlight"); hl.Name = "ProjGlow"; hl.FillColor = Color3.fromRGB(255,225,120); hl.FillTransparency = 0.6
				hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = proj; hl.Parent = proj; st.projHl = hl
			elseif not on and st.projHl then st.projHl:Destroy(); st.projHl = nil end
		end
		-- PERMANENT prop: NOT added to st.filmProps, so applyState never hides it -- the projector always stays
		-- in the world (a fixed prop for any player arriving), even after the quest/movie.
		-- translucent light BEAM from the lens toward the screen -- off until the projector turns ON (movie start),
		-- then it stays lit continuously while the projector is on (the movie / held end frame).
		if typeof(screenPos) == "Vector3" then
			local lensPos = (projCF * CFrame.new(0,1.4,-1.9)).Position
			local mid = (lensPos + screenPos) / 2
			local len = (screenPos - lensPos).Magnitude
			local beam = newPart(Workspace, petId.."Beam", Enum.PartType.Cylinder, Vector3.new(len, 6, 6), Color3.fromRGB(170,210,255), CFrame.lookAt(mid, screenPos) * CFrame.Angles(0,math.rad(90),0), Enum.Material.Neon)
			beam.Transparency = 1 -- off until the projector turns on; then it stays on (never added to filmProps -> never hidden)
			st.beam = beam
		end
		print(string.format("[Pet][DIAG] built projector at (%.0f,%.0f,%.0f)", projPos.X, projPos.Y, projPos.Z))
	else
		warn("[Pet][DIAG] PopcornProjector position MISSING for "..petId)
	end

	-- ===== STAGE 4: reveal the themed popcorn egg in a SPOTLIGHT at PopcornEggSpot (with the Hatch prompt) =====
	local function revealEgg()
		if st.egg then return end
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(245,228,150), nil)
		shell.Reflectance = 0.04
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 10 do -- popcorn-kernel bumps hugging the ovoid surface
			local a = (j-1) * (2*math.pi/10)
			local y = math.sin(a*1.7) * 1.0
			local r = 1.35 * math.sqrt(math.max(0, 1 - (y/2.0)^2)) + 0.05
			newPart(visual, "Kernel", Enum.PartType.Ball, Vector3.new(0.55,0.55,0.55), Color3.fromRGB(255,248,212), CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
		end
		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 3.2, 0))
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		-- SPOTLIGHT: a bright translucent light column down onto the egg + a SpotLight from above + a glow
		local colH = 16
		local col = newPart(egg, "Spotlight", Enum.PartType.Cylinder, Vector3.new(colH, 7, 7), Color3.fromRGB(255,245,205), CFrame.new(eggPos + Vector3.new(0, colH/2 + 1, 0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Neon)
		col.Transparency = 0.72
		local lamp = newPart(egg, "SpotRig", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.new(0,0,0), CFrame.new(eggPos + Vector3.new(0, colH + 2, 0))); lamp.Transparency = 1
		local sl = Instance.new("SpotLight"); sl.Face = Enum.NormalId.Bottom; sl.Angle = 50; sl.Brightness = 6; sl.Range = colH + 10; sl.Color = Color3.fromRGB(255,245,210); sl.Parent = lamp
		local pl = Instance.new("PointLight"); pl.Brightness = 4; pl.Range = 18; pl.Color = Color3.fromRGB(255,240,185); pl.Parent = shell
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,245,180); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(255,215,0); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Popcorn Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function() -- gentle bob (paused during the hatch); the spotlight stays put
			local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] mini-movie played -> egg in spotlight at PopcornEggSpot")
	end

	-- ===== STAGE 3: the SCREEN comes alive -- a ~30s themed CINEMATIC (studio card -> title -> egg falls
	-- through space -> journey -> lands on the popcorn mountain -> "A NEW FRIEND HATCHES"), then the egg
	-- reveals. The SurfaceGui is NEVER destroyed: it HOLDS the final frame permanently (never blank/white). =====
	local function playMovie()
		local TweenService = game:GetService("TweenService") -- the file-level TweenService local is declared later (lexical scope)
		-- the player is now standing at the projector/screen on island 8, so the screen is definitely streamed in
		-- -- retry the by-name resolve in case it was streamed out at build/join time.
		if not (st.screenPart and st.screenPart.Parent) and st.setupScreen then
			if not st.setupScreen() then dumpScreenLike(def) end
		end
		if not (st.screenPart and st.screenPart.Parent) then revealEgg(); return end -- still no screen: complete the quest anyway
		-- build the movie SurfaceGui for the existing PopcornScreen's player-facing face (right-side-up). It lives
		-- in PlayerGui with Adornee = the screen, so its content SURVIVES StreamingEnabled stream-out/in + respawns
		-- (when the player flies up past island 8). A tiny watcher re-points the Adornee when the screen streams
		-- back in. It is NEVER destroyed -- after the feature it HOLDS the final frame on the screen forever.
		local pgui = player:WaitForChild("PlayerGui")
		local sg = Instance.new("SurfaceGui"); sg.Name = petId.."Movie"; sg.Face = st.movieFace
		sg.CanvasSize = st.movieCanvas; sg.LightInfluence = 0; sg.Brightness = 2; sg.ZOffset = 0.05
		sg.ResetOnSpawn = false; sg.Adornee = st.screenPart; sg.Parent = pgui
		st.movieGui = sg
		task.spawn(function() -- keep the end card pinned to the screen across streaming / respawns (re-link Adornee)
			while st.movieGui and st.movieGui.Parent do
				if not (st.screenPart and st.screenPart.Parent) and st.setupScreen then st.setupScreen() end
				if st.screenPart and st.screenPart.Parent and st.movieGui.Adornee ~= st.screenPart then st.movieGui.Adornee = st.screenPart end
				task.wait(2)
			end
		end)
		local bg = Instance.new("Frame"); bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = Color3.fromRGB(6,7,16)
		bg.BackgroundTransparency = 1; bg.BorderSizePixel = 0; bg.ClipsDescendants = true; bg.Parent = sg
		local flash = Instance.new("Frame"); flash.Size = UDim2.new(1,0,1,0); flash.BackgroundColor3 = Color3.fromRGB(245,240,255)
		flash.BackgroundTransparency = 1; flash.BorderSizePixel = 0; flash.ZIndex = 50; flash.Parent = bg
		if st.beam then st.beam.Transparency = 0.86 end -- projector beam stays on (the screen is always "playing")

		-- ===== little 2D builders (all parented to bg; one cohesive dark-cinematic palette) =====
		local function tw(o, t, props, style, dir)
			return TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		end
		local function mkLabel(text, font, size, color)
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Font = font; l.TextSize = size; l.TextColor3 = color
			l.Text = text; l.TextStrokeTransparency = 0.3; l.AnchorPoint = Vector2.new(0.5,0.5); l.Parent = bg; return l
		end
		local function mkEgg() -- a cute 2D egg (rounded oval + popcorn speckles + a highlight)
			local e = Instance.new("Frame"); e.AnchorPoint = Vector2.new(0.5,0.5); e.BackgroundColor3 = Color3.fromRGB(248,236,170); e.BorderSizePixel = 0; e.Parent = bg
			Instance.new("UICorner", e).CornerRadius = UDim.new(0.5, 0)
			local es = Instance.new("UIStroke", e); es.Color = Color3.fromRGB(210,180,90); es.Thickness = 2
			for _, p in ipairs({ {0.34,0.32},{0.62,0.5},{0.42,0.66},{0.6,0.28} }) do
				local sp = Instance.new("Frame"); sp.AnchorPoint = Vector2.new(0.5,0.5); sp.Size = UDim2.new(0.16,0,0.12,0)
				sp.Position = UDim2.new(p[1],0,p[2],0); sp.BackgroundColor3 = Color3.fromRGB(255,250,222); sp.BorderSizePixel = 0; sp.Parent = e
				Instance.new("UICorner", sp).CornerRadius = UDim.new(1,0)
			end
			local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5,0.5); hl.Size = UDim2.new(0.22,0,0.16,0)
			hl.Position = UDim2.new(0.32,0,0.26,0); hl.BackgroundColor3 = Color3.fromRGB(255,255,245); hl.BackgroundTransparency = 0.15; hl.BorderSizePixel = 0; hl.Parent = e
			Instance.new("UICorner", hl).CornerRadius = UDim.new(1,0)
			return e
		end
		local function makeStars(n) -- a twinkling star field (each star reverses forever -- alive, never resets)
			for _ = 1, n do
				local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5)
				local d = 2 + math.random()*4; s.Size = UDim2.new(0,d,0,d)
				s.Position = UDim2.new(math.random(), 0, math.random()*0.82, 0)
				s.BackgroundColor3 = Color3.fromRGB(255,255,238); s.BorderSizePixel = 0; s.BackgroundTransparency = 0.2 + math.random()*0.5
				Instance.new("UICorner", s).CornerRadius = UDim.new(1,0); s.Parent = bg
				TweenService:Create(s, TweenInfo.new(0.6 + math.random()*1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random()*0.8), {BackgroundTransparency = 0.92}):Play()
			end
		end
		local function mkCloud(x, y, scale)
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0, 130*scale, 0, 46*scale)
			c.Position = UDim2.new(x,0,y,0); c.BackgroundTransparency = 1; c.Parent = bg
			for _, p in ipairs({ {0.5,0.6,1.0},{0.28,0.66,0.7},{0.72,0.66,0.7},{0.4,0.46,0.62},{0.62,0.46,0.62} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3]*1.5,0)
				b.Position = UDim2.new(p[1],0,p[2],0); b.BackgroundColor3 = Color3.fromRGB(210,216,238); b.BackgroundTransparency = 0.3; b.BorderSizePixel = 0; b.Parent = c
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			return c
		end
		local function shootingStar()
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,7,0,7)
			s.BackgroundColor3 = Color3.fromRGB(255,255,235); s.BorderSizePixel = 0; s.Position = UDim2.new(-0.1,0, math.random()*0.4, 0); s.Parent = bg
			Instance.new("UICorner", s).CornerRadius = UDim.new(1,0)
			local trail = Instance.new("UIStroke", s); trail.Color = Color3.fromRGB(255,255,225); trail.Thickness = 2; trail.Transparency = 0.2
			tw(s, 0.85, {Position = UDim2.new(1.1,0, math.random()*0.5+0.1, 0), Size = UDim2.new(0,2,0,2)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
			task.delay(0.9, function() s:Destroy() end)
		end
		local function mkMountain() -- a popcorn-mountain silhouette (a dark ridge + pale popcorn humps)
			local m = Instance.new("Frame"); m.Size = UDim2.new(1,0,0.34,0); m.Position = UDim2.new(0,0,0.74,0); m.BackgroundTransparency = 1; m.Parent = bg
			local base = Instance.new("Frame"); base.Size = UDim2.new(1,0,0.55,0); base.Position = UDim2.new(0,0,0.55,0); base.BackgroundColor3 = Color3.fromRGB(34,30,54); base.BorderSizePixel = 0; base.Parent = m
			for _, p in ipairs({ {0.5,0.0,0.52},{0.3,0.16,0.36},{0.7,0.16,0.36},{0.15,0.3,0.26},{0.85,0.3,0.26} }) do
				local h = Instance.new("Frame"); h.AnchorPoint = Vector2.new(0.5,0.5); h.Size = UDim2.new(p[3],0,p[3]*1.25,0)
				h.Position = UDim2.new(p[1],0,0.24+p[2],0); h.BackgroundColor3 = Color3.fromRGB(246,240,206); h.BackgroundTransparency = 0.05; h.BorderSizePixel = 0; h.Parent = m
				Instance.new("UICorner", h).CornerRadius = UDim.new(1,0)
			end
			return m
		end
		local function puff(x, y) -- a quick dust/popcorn puff on landing
			for i = 1, 8 do
				local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5,0.5); d.Size = UDim2.new(0,10,0,10); d.Position = UDim2.new(x,0,y,0)
				d.BackgroundColor3 = Color3.fromRGB(250,245,222); d.BackgroundTransparency = 0.2; d.BorderSizePixel = 0; d.Parent = bg
				Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
				local a = (i-1)*(math.pi*2/8)
				tw(d, 0.6, {Position = UDim2.new(x+math.cos(a)*0.12,0,y+math.sin(a)*0.1,0), Size = UDim2.new(0,2,0,2), BackgroundTransparency = 1}):Play()
				task.delay(0.65, function() d:Destroy() end)
			end
		end
		local function sparkle(x, y)
			local s = mkLabel("\xE2\x9C\xA8", Enum.Font.GothamBold, 22, Color3.fromRGB(255,246,184))
			s.Size = UDim2.new(0,30,0,30); s.Position = UDim2.new(x,0,y,0); s.TextTransparency = 0.05
			tw(s, 0.7, {TextTransparency = 1, Size = UDim2.new(0,46,0,46)}):Play()
			task.delay(0.75, function() s:Destroy() end)
		end
		local function mkSheep() -- a cute fluffy sheep that peeks up at the finale
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,96,0,76); s.BackgroundTransparency = 1; s.Parent = bg
			for _, p in ipairs({ {0.5,0.55,0.62},{0.28,0.5,0.46},{0.72,0.5,0.46},{0.38,0.74,0.42},{0.62,0.74,0.42},{0.5,0.28,0.5} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3],0); b.Position = UDim2.new(p[1],0,p[2],0)
				b.BackgroundColor3 = Color3.fromRGB(250,248,236); b.BorderSizePixel = 0; b.Parent = s
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			local face = Instance.new("Frame"); face.AnchorPoint = Vector2.new(0.5,0.5); face.Size = UDim2.new(0.4,0,0.48,0); face.Position = UDim2.new(0.5,0,0.36,0)
			face.BackgroundColor3 = Color3.fromRGB(54,44,40); face.BorderSizePixel = 0; face.ZIndex = 2; face.Parent = s
			Instance.new("UICorner", face).CornerRadius = UDim.new(0.5,0)
			for _, ex in ipairs({0.4,0.6}) do
				local e = Instance.new("Frame"); e.AnchorPoint = Vector2.new(0.5,0.5); e.Size = UDim2.new(0.1,0,0.13,0); e.Position = UDim2.new(ex,0,0.32,0)
				e.BackgroundColor3 = Color3.fromRGB(245,245,245); e.BorderSizePixel = 0; e.ZIndex = 3; e.Parent = s
				Instance.new("UICorner", e).CornerRadius = UDim.new(1,0)
			end
			return s
		end
		-- ===== cosmic-journey builders (planets, ring/portal, comet, nebula, asteroid, star cluster) =====
		local function mkPlanet(x, y, d, color, ringed)
			local p = Instance.new("Frame"); p.AnchorPoint = Vector2.new(0.5,0.5); p.Size = UDim2.new(0,d,0,d); p.Position = UDim2.new(x,0,y,0)
			p.BackgroundColor3 = color; p.BorderSizePixel = 0; p.Parent = bg
			Instance.new("UICorner", p).CornerRadius = UDim.new(1,0)
			local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5,0.5); hl.Size = UDim2.new(0.42,0,0.42,0); hl.Position = UDim2.new(0.32,0,0.3,0)
			hl.BackgroundColor3 = Color3.fromRGB(255,255,255); hl.BackgroundTransparency = 0.62; hl.BorderSizePixel = 0; hl.Parent = p
			Instance.new("UICorner", hl).CornerRadius = UDim.new(1,0)
			if ringed then
				local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Size = UDim2.new(1.8,0,0.55,0); r.Position = UDim2.new(0.5,0,0.5,0)
				r.BackgroundTransparency = 1; r.Rotation = -22; r.Parent = p
				Instance.new("UICorner", r).CornerRadius = UDim.new(1,0)
				local rs = Instance.new("UIStroke", r); rs.Color = Color3.fromRGB(232,222,180); rs.Thickness = 3; rs.Transparency = 0.15
			end
			return p
		end
		local function mkRing(x, y, d) -- a glowing portal/ring the egg zooms through
			local r = Instance.new("Frame"); r.AnchorPoint = Vector2.new(0.5,0.5); r.Size = UDim2.new(0,d,0,d); r.Position = UDim2.new(x,0,y,0); r.BackgroundTransparency = 1; r.Parent = bg
			Instance.new("UICorner", r).CornerRadius = UDim.new(1,0)
			local s1 = Instance.new("UIStroke", r); s1.Color = Color3.fromRGB(120,220,255); s1.Thickness = 5; s1.Transparency = 0.08
			local inner = Instance.new("Frame"); inner.AnchorPoint = Vector2.new(0.5,0.5); inner.Size = UDim2.new(0.72,0,0.72,0); inner.Position = UDim2.new(0.5,0,0.5,0)
			inner.BackgroundColor3 = Color3.fromRGB(150,230,255); inner.BackgroundTransparency = 0.78; inner.BorderSizePixel = 0; inner.Parent = r
			Instance.new("UICorner", inner).CornerRadius = UDim.new(1,0)
			return r
		end
		local function mkComet() -- a bright head + a fading tail streaking across
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0,13,0,13); c.Position = UDim2.new(-0.12,0,0.14,0)
			c.BackgroundColor3 = Color3.fromRGB(190,238,255); c.BorderSizePixel = 0; c.ZIndex = 2; c.Parent = bg
			Instance.new("UICorner", c).CornerRadius = UDim.new(1,0)
			local t = Instance.new("Frame"); t.AnchorPoint = Vector2.new(1,0.5); t.Size = UDim2.new(0,64,0,7); t.Position = UDim2.new(0.5,0,0.5,0); t.Rotation = 10
			t.BackgroundColor3 = Color3.fromRGB(150,210,255); t.BorderSizePixel = 0; t.Parent = c
			Instance.new("UICorner", t).CornerRadius = UDim.new(1,0)
			local g = Instance.new("UIGradient", t); g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0.15) })
			tw(c, 3.6, {Position = UDim2.new(1.12,0,0.34,0)}, Enum.EasingStyle.Linear):Play()
			task.delay(3.7, function() c:Destroy() end)
			return c
		end
		local function mkNebula(x, y, scale, color) -- a soft translucent colored nebula wisp
			local c = Instance.new("Frame"); c.AnchorPoint = Vector2.new(0.5,0.5); c.Size = UDim2.new(0, 150*scale, 0, 80*scale); c.Position = UDim2.new(x,0,y,0); c.BackgroundTransparency = 1; c.Parent = bg
			for _, p in ipairs({ {0.5,0.5,1.0},{0.3,0.6,0.72},{0.7,0.44,0.72},{0.46,0.34,0.62},{0.64,0.62,0.58} }) do
				local b = Instance.new("Frame"); b.AnchorPoint = Vector2.new(0.5,0.5); b.Size = UDim2.new(p[3],0,p[3],0); b.Position = UDim2.new(p[1],0,p[2],0)
				b.BackgroundColor3 = color; b.BackgroundTransparency = 0.62; b.BorderSizePixel = 0; b.Parent = c
				Instance.new("UICorner", b).CornerRadius = UDim.new(1,0)
			end
			return c
		end
		local function mkAsteroid(x, y, d)
			local a = Instance.new("Frame"); a.AnchorPoint = Vector2.new(0.5,0.5); a.Size = UDim2.new(0,d,0,d); a.Position = UDim2.new(x,0,y,0)
			a.BackgroundColor3 = Color3.fromRGB(122,114,106); a.BorderSizePixel = 0; a.Parent = bg
			Instance.new("UICorner", a).CornerRadius = UDim.new(0.5,0)
			for _, p in ipairs({ {0.36,0.4,0.24},{0.62,0.56,0.18},{0.5,0.3,0.14} }) do
				local cr = Instance.new("Frame"); cr.AnchorPoint = Vector2.new(0.5,0.5); cr.Size = UDim2.new(p[3],0,p[3],0); cr.Position = UDim2.new(p[1],0,p[2],0)
				cr.BackgroundColor3 = Color3.fromRGB(92,86,80); cr.BorderSizePixel = 0; cr.Parent = a
				Instance.new("UICorner", cr).CornerRadius = UDim.new(1,0)
			end
			return a
		end
		local function mkCluster(x, y) -- a twinkling star cluster / constellation
			local g = Instance.new("Frame"); g.AnchorPoint = Vector2.new(0.5,0.5); g.Size = UDim2.new(0,86,0,64); g.Position = UDim2.new(x,0,y,0); g.BackgroundTransparency = 1; g.Parent = bg
			for _, p in ipairs({ {0.2,0.3},{0.45,0.14},{0.6,0.46},{0.82,0.3},{0.4,0.62},{0.72,0.72} }) do
				local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5,0.5); s.Size = UDim2.new(0,5,0,5); s.Position = UDim2.new(p[1],0,p[2],0)
				s.BackgroundColor3 = Color3.fromRGB(220,234,255); s.BorderSizePixel = 0; s.Parent = g
				Instance.new("UICorner", s).CornerRadius = UDim.new(1,0)
				TweenService:Create(s, TweenInfo.new(0.8 + math.random()*1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random()), {BackgroundTransparency = 0.7}):Play()
			end
			return g
		end
		local function fadeAndDestroy(o, t) -- fade a composite element (and its children) then remove it
			for _, d in ipairs(o:GetDescendants()) do
				if d:IsA("GuiObject") then tw(d, t, {BackgroundTransparency = 1}):Play() end
				if d:IsA("UIStroke") then tw(d, t, {Transparency = 1}):Play() end
			end
			if o:IsA("GuiObject") then tw(o, t, {BackgroundTransparency = 1}):Play() end
			game:GetService("Debris"):AddItem(o, t + 0.15)
		end

		task.spawn(function()
			-- ===== OPENING (~3.7s): the screen TURNS ON (flicker) -> studio card =====
			tw(bg, 0.3, {BackgroundTransparency = 0}):Play()
			for _ = 1, 6 do flash.BackgroundTransparency = 0.2; task.wait(0.05); flash.BackgroundTransparency = 0.9; task.wait(0.05) end
			tw(flash, 0.3, {BackgroundTransparency = 1}):Play()
			local corn = mkLabel("\xF0\x9F\x8D\xBF", Enum.Font.GothamBold, 44, Color3.new(1,1,1))
			corn.Size = UDim2.new(0,64,0,64); corn.Position = UDim2.new(0.5,0,0.3,0); corn.TextTransparency = 1
			local studio = mkLabel("POPCORN PICTURES", Enum.Font.GothamBold, 30, Color3.fromRGB(255,226,150))
			studio.Size = UDim2.new(0.85,0,0,40); studio.Position = UDim2.new(0.5,0,0.46,0); studio.TextTransparency = 1
			local pres = mkLabel("presents", Enum.Font.Gotham, 18, Color3.fromRGB(214,218,235))
			pres.Size = UDim2.new(0.6,0,0,24); pres.Position = UDim2.new(0.5,0,0.58,0); pres.TextTransparency = 1
			tw(corn, 0.6, {TextTransparency = 0}):Play(); tw(studio, 0.7, {TextTransparency = 0}):Play()
			tw(corn, 1.2, {Position = UDim2.new(0.5,0,0.26,0)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
			task.wait(0.7); tw(pres, 0.5, {TextTransparency = 0}):Play()
			task.wait(2.4)
			for _, o in ipairs({corn, studio, pres}) do tw(o, 0.5, {TextTransparency = 1}):Play() end
			task.wait(0.6); corn:Destroy(); studio:Destroy(); pres:Destroy()

			-- ===== TITLE CARD (~4.5s): the movie title zooms + glows in, holds, fades =====
			local title = mkLabel("FLUFF FROM ABOVE", Enum.Font.FredokaOne, 10, Color3.fromRGB(255,216,0))
			title.Size = UDim2.new(0.2,0,0,60); title.Position = UDim2.new(0.5,0,0.46,0); title.TextScaled = true; title.TextStrokeTransparency = 0
			local tglow = Instance.new("UIStroke", title); tglow.Color = Color3.fromRGB(255,150,30); tglow.Thickness = 0
			local sub = mkLabel("the legend of the popcorn sheep", Enum.Font.Gotham, 16, Color3.fromRGB(220,224,240))
			sub.Size = UDim2.new(0.75,0,0,22); sub.Position = UDim2.new(0.5,0,0.62,0); sub.TextTransparency = 1
			tw(title, 0.8, {Size = UDim2.new(0.9,0,0,92)}, Enum.EasingStyle.Back):Play(); tw(tglow, 0.8, {Thickness = 3}):Play()
			task.wait(0.9); tw(sub, 0.6, {TextTransparency = 0}):Play()
			tw(title, 1.6, {Size = UDim2.new(0.94,0,0,98)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut):Play()
			task.wait(2.8)
			tw(title, 0.7, {TextTransparency = 1}):Play(); tw(tglow, 0.7, {Transparency = 1}):Play(); tw(sub, 0.6, {TextTransparency = 1}):Play()
			task.wait(0.8); title:Destroy(); sub:Destroy()

			-- ===== STORY ACTS 1-2 (~12s): THE EGG'S JOURNEY -- a busy, lively cosmic adventure. A swooping path:
			-- drift in -> curve around a planet -> ZOOM through a glow ring -> glance off a cloud -> dodge an
			-- asteroid -> settle. The egg tumbles + trails sparkles, past drifting planets, a nebula, a star
			-- cluster, shooting stars + a comet (parallax: far = slow, near = fast). Busy but readable. =====
			makeStars(50) -- far twinkling field (static = slowest depth layer)
			local journeyFx = {}
			local function jfx(o) journeyFx[#journeyFx+1] = o; return o end
			-- drifting cosmic set (parallax)
			local planet = jfx(mkPlanet(0.72, 0.18, 66, Color3.fromRGB(120,150,235), true))
			tw(planet, 12.0, {Position = UDim2.new(0.68,0,0.24,0)}, Enum.EasingStyle.Linear):Play()
			local moon = jfx(mkPlanet(0.18, 0.4, 32, Color3.fromRGB(205,165,120), false))
			tw(moon, 12.0, {Position = UDim2.new(0.22,0,0.48,0)}, Enum.EasingStyle.Linear):Play()
			jfx(mkCluster(0.85, 0.58))
			local neb = jfx(mkNebula(0.3, 0.7, 1.2, Color3.fromRGB(150,90,200)))
			tw(neb, 12.0, {Position = UDim2.new(0.2,0,0.64,0)}, Enum.EasingStyle.Linear):Play()
			local ring = jfx(mkRing(0.42, 0.42, 58))
			TweenService:Create(ring, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Rotation = 14}):Play()
			local cloud = jfx(mkCloud(0.58, 0.52, 1.15))
			local roid = jfx(mkAsteroid(0.5, 0.62, 26))
			TweenService:Create(roid, TweenInfo.new(2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360}):Play()
			-- background flair (timed across the descent)
			task.delay(0.6, shootingStar); task.delay(2.6, shootingStar); task.delay(4.6, shootingStar)
			task.delay(7.4, shootingStar); task.delay(9.6, shootingStar)
			task.delay(3.4, mkComet)

			-- THE EGG: enters small at the top, tumbles continuously, and trails twinkling sparkles
			local egg = mkEgg()
			egg.Size = UDim2.new(0,26,0,34); egg.Position = UDim2.new(0.5,0,0.05,0); egg.ZIndex = 4
			local spinTween = TweenService:Create(egg, TweenInfo.new(1.3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360})
			spinTween:Play()
			local trailing = true
			task.spawn(function() -- SPARKLE TRAIL: little twinkles spawned at the egg's live position as it flies
				while trailing do
					local d = Instance.new("Frame"); d.AnchorPoint = Vector2.new(0.5,0.5); local sz = 4 + math.random()*4
					d.Size = UDim2.new(0,sz,0,sz); d.Position = egg.Position; d.BackgroundColor3 = Color3.fromRGB(255,250,205)
					d.BorderSizePixel = 0; d.ZIndex = 3; d.Parent = bg
					Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
					tw(d, 0.7, {Size = UDim2.new(0,1,0,1), BackgroundTransparency = 1, Rotation = 40}):Play()
					game:GetService("Debris"):AddItem(d, 0.75)
					task.wait(0.06)
				end
			end)
			-- glide the egg to a waypoint over t secs (Sine = smooth curves), growing as it nears
			local function go(t, x, y, w, h, style, dir)
				tw(egg, t, { Position = UDim2.new(x,0,y,0), Size = UDim2.new(0,w,0,h) }, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut):Play()
				task.wait(t)
			end
			go(2.4, 0.34, 0.16, 34, 44)                                            -- drift in toward the planet
			-- curve / loop gracefully around the planet
			go(1.1, 0.54, 0.1, 36, 48)
			go(1.1, 0.84, 0.18, 40, 52)
			go(1.1, 0.7, 0.32, 42, 55)
			go(1.0, 0.5, 0.4, 46, 60)                                              -- glide down toward the ring
			-- ZOOM through the glowing ring (speed up) + a ring pulse as it passes
			TweenService:Create(ring, TweenInfo.new(0.18), {Size = UDim2.new(0,74,0,74)}):Play()
			task.delay(0.22, function() if ring.Parent then TweenService:Create(ring, TweenInfo.new(0.3), {Size = UDim2.new(0,58,0,58)}):Play() end end)
			go(0.5, 0.42, 0.42, 48, 62, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			-- GLANCE off the cloud (it jiggles), deflecting the egg
			go(0.8, 0.6, 0.5, 54, 70, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(cloud, TweenInfo.new(0.15), {Position = UDim2.new(0.62,0,0.53,0)}):Play()
			task.delay(0.18, function() if cloud.Parent then TweenService:Create(cloud, TweenInfo.new(0.5, Enum.EasingStyle.Elastic), {Position = UDim2.new(0.58,0,0.52,0)}):Play() end end)
			go(0.6, 0.46, 0.54, 58, 76, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			-- WEAVE / dodge the asteroid
			go(0.6, 0.64, 0.56, 64, 84)
			go(0.6, 0.5, 0.52, 70, 92)
			go(0.9, 0.5, 0.5, 72, 94)                                              -- settle into the landing approach
			-- end the journey: stop the trail + spin, clear the cosmic set (keep the far star field)
			trailing = false
			spinTween:Cancel(); egg.Rotation = 0
			for _, o in ipairs(journeyFx) do fadeAndDestroy(o, 0.5) end

			-- ===== STORY ACT 3 (~4.5s): the egg lands softly on the popcorn mountain, puffs, settles + glows =====
			mkMountain()
			tw(egg, 1.0, {Position = UDim2.new(0.5,0,0.64,0), Rotation = 360}, Enum.EasingStyle.Bounce):Play()
			task.wait(1.0)
			puff(0.5, 0.7)
			tw(egg, 0.16, {Size = UDim2.new(0,88,0,74)}):Play(); task.wait(0.16)
			tw(egg, 0.24, {Size = UDim2.new(0,72,0,94)}, Enum.EasingStyle.Back):Play(); task.wait(0.3)
			local eglow = Instance.new("UIStroke", egg); eglow.Color = Color3.fromRGB(255,240,170); eglow.Thickness = 0
			tw(eglow, 1.2, {Thickness = 5}):Play()
			task.wait(3.0)

			-- ===== REVEAL (~5s, then PERMANENT): "A NEW FRIEND HATCHES!" + sparkles + a sheep peeking. The real
			-- 3D spotlight egg appears at PopcornEggSpot now, and this final frame HOLDS forever (never blank). =====
			revealEgg()
			st.pointTarget = eggPos -- the on-screen pointer now guides to the real egg
			local sheep = mkSheep(); sheep.Position = UDim2.new(0.5,0,1.2,0)
			tw(sheep, 0.9, {Position = UDim2.new(0.5,0,0.66,0)}, Enum.EasingStyle.Back):Play()
			local cap = mkLabel("A NEW FRIEND HATCHES!", Enum.Font.FredokaOne, 10, Color3.fromRGB(255,236,150))
			cap.Size = UDim2.new(0.2,0,0,50); cap.Position = UDim2.new(0.5,0,0.2,0); cap.TextScaled = true; cap.TextStrokeTransparency = 0
			local cglow = Instance.new("UIStroke", cap); cglow.Color = Color3.fromRGB(255,150,30); cglow.Thickness = 2
			task.wait(0.4)
			tw(cap, 0.7, {Size = UDim2.new(0.94,0,0,86)}, Enum.EasingStyle.Back):Play()
			for i = 1, 12 do task.delay(i*0.12, function() sparkle(0.5 + (math.random()-0.5)*0.5, 0.52 + (math.random()-0.5)*0.45) end) end
			-- keep the held finale ALIVE (gentle infinite pulses) but never resetting / clearing
			TweenService:Create(cap, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {TextStrokeTransparency = 0.45}):Play()
			TweenService:Create(eglow, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Thickness = 2}):Play()
			-- TWO end-frame states: BEFORE hatch the egg sits in FRONT of the sheep (covering it, "about to
			-- hatch"). hatchScreenEgg() (fired by applyState when the player CLAIMS the spotlight egg) cracks +
			-- removes the screen egg so the SHEEP is revealed, and updates the caption to the hatched state.
			st.screenHatched = false
			st.hatchScreenEgg = function()
				if st.screenHatched then return end
				st.screenHatched = true
				pcall(function() puff(0.5, 0.64) end) -- a little crack/poof where the egg was
				for i = 1, 8 do task.delay(i*0.05, function() sparkle(0.5 + (math.random()-0.5)*0.3, 0.62 + (math.random()-0.5)*0.18) end) end
				if egg and egg.Parent then -- crack the egg off the screen
					tw(egg, 0.35, {Size = UDim2.new(0,4,0,4), BackgroundTransparency = 1, Rotation = 60}):Play()
					local de = egg; task.delay(0.4, function() pcall(function() de:Destroy() end) end)
				end
				if sheep and sheep.Parent then -- reveal the sheep (a happy little pop forward)
					tw(sheep, 0.45, {Position = UDim2.new(0.5,0,0.6,0), Size = UDim2.new(0,112,0,90)}, Enum.EasingStyle.Back):Play()
				end
				if cap and cap.Parent then cap.Text = "A NEW FRIEND HATCHED!" end
				print("[Pet] screen end frame -> sheep revealed (player hatched the Popcorn Sheep)")
			end
			if st.owns then st.hatchScreenEgg() end -- already owned by now (hatched fast) -> reveal immediately
			-- (intentionally NO destroy/fade here -- the SurfaceGui holds this end card on the screen permanently)
			print("[Pet] mini-movie played -> egg in spotlight at PopcornEggSpot")
		end)
	end

	-- ===== STAGE 2: PROJECTOR "Load Reels" prompt (needs all 6 reels) =====
	if projBody then
		local prompt
		prompt = addPrompt(projBody, "Load Reels", "Projector", function()
			if st.owns or st.showPlayed then return end
			local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
			local have = math.max(count, st.uiFound or 0) -- server-confirmed count as a backup
			if have < #def.pieceMarkers then
				floatText(projPos + Vector3.new(0,3.5,0), "Find all 6 film reels first")
				print("[Pet] "..player.Name.." tried to load reels ("..have.."/6) -- not enough")
				return
			end
			st.showPlayed = true
			prompt.Enabled = false -- one show; remove the prompt so it never overlaps the egg's hatch prompt
			print("[Pet] "..player.Name.." loaded reels -> show starting")
			playMovie()
		end)
		prompt.HoldDuration = 0.4
	end

	-- (st.filmProps is empty now -- the projector + beam are PERMANENT props that are never hidden, for owners or not)
	if st.owns and st.filmProps then for _, o in ipairs(st.filmProps) do setVisible(o, false) end end
end

-- ============================================================================================
-- BUTTER DUCK QUEST (questType "fishing"). "Hook & Reel": grab a rod at the barrel -> fish near/over the
-- ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in TENSION minigame -> the SERVER rolls the catch
-- (pity egg + funny junk) -> the egg appears IN FRONT of the player -> hatch -> the Butter Duck follows.
-- Reuses the shared hatch flow + claim/inventory. Cosmetic-only.
-- ============================================================================================

-- REEL-IN minigame: the standard FISCH-STYLE reel Roblox players recognize on sight. A tall vertical BAR
-- holds a drifting FISH marker and a player-controlled SLIDER (the catch zone). HOLD (click/tap anywhere)
-- to push the slider UP; RELEASE and it falls DOWN under gravity -- that single hold/release is the whole
-- control, exactly like Fisch. Keep the slider OVERLAPPING the fish to FILL the catch PROGRESS bar; when the
-- fish slips outside the slider, progress slowly drains. Fill to the top = caught; drain to zero = it got
-- away. A brief ~1.2s locked intro ("GET READY") lets the player orient before it goes live. Tuned EASY +
-- mobile-friendly (single hold/release works on touch). onDone(success) when finished.
local reelUI, reelBusy = nil, false
local function ensureReelUI()
	if reelUI then return reelUI end
	local ui = mgCard("ButterReelGui", 340, 396, "REEL IT IN!",
		"HOLD to rise \xE2\x80\xA2 RELEASE to drop \xE2\x80\x94 keep \xF0\x9F\x90\x9F inside the slider")
	local panel = ui.panel
	local TOP, TALL = MG_BODY_TOP + 18, 244
	-- the tall vertical REEL BAR (holds the drifting fish + the player-controlled slider)
	local track = Instance.new("Frame"); track.Size = UDim2.new(0,104,0,TALL); track.Position = UDim2.new(0,34,0,TOP)
	track.BackgroundColor3 = MG.navy; track.BorderSizePixel = 0; track.Parent = panel
	mgCorner(track, 14); mgStroke(track, MG.trough, 2, 0.15)
	for k = 1, 5 do -- faint depth ticks so the bar doesn't read as an empty slab
		local t = Instance.new("Frame"); t.Size = UDim2.new(1,-16,0,2); t.Position = UDim2.new(0,8,k/6,0)
		t.BackgroundColor3 = MG.white; t.BackgroundTransparency = 0.88; t.BorderSizePixel = 0; t.Parent = track
	end
	-- the SLIDER (catch zone) the player moves with hold/release
	local zone = Instance.new("Frame"); zone.Size = UDim2.new(1,-10,0.30,0); zone.Position = UDim2.new(0.5,0,0.5,0)
	zone.AnchorPoint = Vector2.new(0.5,0.5); zone.BackgroundColor3 = MG.lime; zone.BackgroundTransparency = 0.15
	zone.BorderSizePixel = 0; zone.Parent = track
	mgCorner(zone, 10); mgGloss(zone); mgStroke(zone, Color3.fromRGB(226,255,208), 2)
	-- the FISH marker that drifts up/down inside the bar
	local fish = Instance.new("TextLabel"); fish.Size = UDim2.new(0,48,0,48); fish.AnchorPoint = Vector2.new(0.5,0.5)
	fish.Position = UDim2.new(0.5,0,0.5,0); fish.BackgroundTransparency = 1; fish.Font = Enum.Font.GothamBold
	fish.TextSize = 36; fish.Text = "\xF0\x9F\x90\x9F"; fish.ZIndex = 4; fish.Parent = track
	-- the catch PROGRESS bar (vertical, right side), fills bottom-up
	local pbBg = Instance.new("Frame"); pbBg.Size = UDim2.new(0,52,0,TALL); pbBg.Position = UDim2.new(1,-86,0,TOP)
	pbBg.BackgroundColor3 = MG.navy; pbBg.BorderSizePixel = 0; pbBg.Parent = panel
	mgCorner(pbBg, 14); mgStroke(pbBg, MG.trough, 2, 0.15)
	local pb = Instance.new("Frame"); pb.Size = UDim2.new(1,0,0.45,0); pb.Position = UDim2.new(0,0,1,0); pb.AnchorPoint = Vector2.new(0,1)
	pb.BackgroundColor3 = MG.gold; pb.BorderSizePixel = 0; pb.Parent = pbBg
	mgCorner(pb, 14); mgGloss(pb)
	local function cap(text, x, w)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,w,0,16); l.Position = UDim2.new(0,x,0,TOP+TALL+8)
		l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 11; l.TextColor3 = MG.ice; l.Text = text; l.Parent = panel
	end
	cap("SLIDER", 34, 104); cap("CATCH", 340-86, 52)
	-- center "GET READY" overlay for the brief locked intro
	local ready = Instance.new("TextLabel"); ready.AnchorPoint = Vector2.new(0.5,0.5); ready.Position = UDim2.new(0.5,0,0.5,10)
	ready.Size = UDim2.new(1,-20,0,44); ready.BackgroundTransparency = 1; ready.Font = Enum.Font.FredokaOne
	ready.TextSize = 30; ready.TextColor3 = MG.gold; ready.Text = "GET READY..."; ready.ZIndex = 6; ready.Parent = panel
	mgStroke(ready, MG.navy, 3)
	reelUI = { gui = ui.gui, zone = zone, fish = fish, pb = pb, hint = ui.hint, ready = ready }
	return reelUI
end
--======================================================================
-- FISHING SOUNDS
--======================================================================
-- The Butter Swamp fishing quest had NO audio at all -- every beat of it (the cast, the bobber landing, the
-- bite, the fight, the catch) happened in silence, which is why the minigame reads as a bar moving rather
-- than as fishing. Five cues, one per beat.
--
-- ===== 2D vs 3D, AND WHY THE SPLASH IS THE ODD ONE =====
-- Four of these are things happening TO YOU and play flat out of SoundService: you always hear your own cast
-- and your own bite at full strength regardless of where the camera is. The SPLASH is the exception -- it is
-- a thing happening OUT THERE, at the bobber, several studs away across the butter. Parenting it to the
-- bobber makes it positional, so it arrives from the direction you just cast in. That is the whole reason
-- the cast reads as travelling somewhere.
--
-- ===== THE SPLASH IS DELAYED ON PURPOSE =====
-- The cast tween is 0.6s (see the NumberValue arc below), so the bobber is still in the AIR for that whole
-- time. Playing the splash on the cast would land the water sound while the bobber is at the top of its arc.
-- It fires at +0.6s, when the bobber actually touches down.
local FISH_SFX = {
	cast    = { id = "rbxassetid://119135010875996", volume = 1.2 },  -- bobber leaves the rod tip
	splash  = { id = "rbxassetid://124279162156159", volume = 1.4 },  -- +0.6s, ON the bobber (the landing)
	bite    = { id = "rbxassetid://115878657073501", volume = 1.6 },  -- with the "!" billboard
	reel    = { id = "rbxassetid://79404754846319",  volume = 1.0, looped = true }, -- while you HOLD
	pullOut = { id = "rbxassetid://93360393539898",  volume = 1.5 },  -- egg or junk, before the status text
}

-- Play a cue. `parent` makes it positional (3D) from that part; omitted, it plays flat out of SoundService.
-- Returns the Sound so a LOOPED cue can be stopped by its caller; one-shots clean themselves up via Debris.
--
-- pcall-wrapped at every call site rather than here: a bad or unapproved asset id is a silent no-op in
-- Roblox (the Sound simply never loads), so a broken cue can never take the fishing quest down with it.
local function playFishSfx(cue, parent)
	local c = FISH_SFX[cue]
	if not c then return nil end
	local s = Instance.new("Sound")
	s.SoundId = c.id
	s.Volume  = c.volume
	s.Looped  = (c.looped == true)
	-- A 3D cue parented to the bobber dies with the bobber, which is correct: destroying the bobber IS the
	-- end of that sound's subject. Debris only guards the flat ones, which have nothing to outlive.
	s.Parent = parent or SoundService
	s:Play()
	if not s.Looped then game:GetService("Debris"):AddItem(s, 6) end
	return s
end

local function openReelMinigame(onDone)
	if reelBusy then if onDone then onDone(false) end return end
	reelBusy = true
	local UIS = game:GetService("UserInputService")
	local ui = ensureReelUI()
	-- RETUNED FOR LENGTH: the catch used to fill in ~1.5s. It's now a sustained fight with a HARD FLOOR --
	-- `ceiling` rises over MIN_FIGHT seconds and the catch bar is clamped to it, so even perfect tracking
	-- cannot land the fish sooner. The slider stays WIDE and the drain stays gentle: longer, not harder.
	local MIN_FIGHT = 15         -- seconds the fish fights for, minimum, once the bar goes live
	local ZONE_H = 0.30          -- slider height as a fraction of the bar (WIDE = easy; this is an easy pet)
	local zone, zoneVel = 0.45, 0
	local fishF, fishTarget, fishTimer = 0.5, 0.5, 0
	local progress = 0.30        -- start partway so it isn't an instant win/lose (lower = a longer fight)
	local ceiling = progress
	ui.zone.Size = UDim2.new(1,-10,ZONE_H,0)
	ui.pb.Size = UDim2.new(1,0,progress,0)
	local done, holding = false, false
	-- LINE TENSION, fed to the haptic loop below. Updated once per frame from the same values that drive
	-- the bar, so what the hand feels and what the screen shows can never disagree.
	local tension, wasInZone = 0, false
	local c1, c2
	-- THE REEL LOOP. Created once and started/stopped with the hold rather than spawned per press: a new
	-- Sound on every tap would restart the recording from zero and machine-gun its attack, which on a
	-- 15-second fight of rapid taps is a rattle rather than a reel.
	local reelSnd = playFishSfx("reel")
	if reelSnd then pcall(function() reelSnd:Stop() end) end -- created stopped; the first hold starts it
	local function setReeling(on)
		if not reelSnd then return end
		pcall(function() if on then if not reelSnd.IsPlaying then reelSnd:Play() end else reelSnd:Stop() end end)
	end
	local function isHold(t) return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch end
	c1 = UIS.InputBegan:Connect(function(i) if isHold(i.UserInputType) then holding = true; setReeling(true) end end)
	c2 = UIS.InputEnded:Connect(function(i) if isHold(i.UserInputType) then holding = false; setReeling(false) end end)
	ui.gui.Enabled = true
	-- THE LINE GOES TIGHT. A continuous strain that rises as you crank, as the fish sits in the slider, and
	-- as the catch bar climbs -- so the last seconds of a 15-second fight are the hardest to hold. This is
	-- the reeling SOUND made physical; the loop is torn down in finish(), the one exit from the minigame.
	if _G.hapticLoop then pcall(_G.hapticLoop, "strain", function() return tension end) end
	local function finish(success)
		if done then return end
		done = true; if c1 then c1:Disconnect() end; if c2 then c2:Disconnect() end
		-- Destroy, not just Stop: finish() is the only exit from the minigame (win, loss, or the early-out
		-- above), so this is the one place that can guarantee the loop does not outlive the fight and follow
		-- the player around the island forever.
		if reelSnd then pcall(function() reelSnd:Stop(); reelSnd:Destroy() end); reelSnd = nil end
		ui.gui.Enabled = false; reelBusy = false
		if _G.hapticLoopStop then pcall(_G.hapticLoopStop, "strain") end
		if onDone then onDone(success) end
	end
	task.spawn(function()
		-- BRIEF LOCKED INTRO (~1.2s, like Fisch): the fish + slider are shown and the slider already responds
		-- to hold/release so the player can pre-position, but the catch PROGRESS doesn't move until it goes live.
		local introT = 1.2
		ui.ready.Visible = true
		local last = os.clock()
		while not done do
			local now = os.clock(); local dt = math.min(now - last, 0.05); last = now
			-- SLIDER physics: HOLD pushes up, gravity pulls down, light damping -- the whole control
			zoneVel = (zoneVel + (holding and 2.4 or -1.15) * dt) * 0.90
			zone = zone + zoneVel * dt
			if zone < ZONE_H/2 then zone = ZONE_H/2; zoneVel = 0 elseif zone > 1 - ZONE_H/2 then zone = 1 - ZONE_H/2; zoneVel = 0 end
			-- FISH drift toward a slowly-changing target (gentle = easy)
			fishTimer = fishTimer - dt
			if fishTimer <= 0 then fishTarget = 0.14 + math.random() * 0.72; fishTimer = 0.5 + math.random() * 1.1 end
			fishF = fishF + (fishTarget - fishF) * math.min(dt * 1.8, 1) -- runs a little more often so you can't just park the slider
			local inZone = math.abs(fishF - zone) <= (ZONE_H/2)
			-- Slack rod = a faint presence; cranking adds to it; holding the fish in the slider adds more; and the
			-- whole thing scales with progress so the fish feels heavier the closer it gets to the surface.
			tension = 0.10 + (holding and 0.22 or 0) + (inZone and 0.16 or 0) + progress * 0.32
			-- One tick the instant the fish slips OUT of the slider -- the moment you are losing it, which is the
			-- half of the fight the bar communicates worst. Edge-triggered, so a fish sitting outside stays silent.
			if wasInZone and not inZone and _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
			wasInZone = inZone
			if introT > 0 then
				introT = introT - dt
				if introT <= 0 then ui.ready.Visible = false end
			else
				-- LIVE: fill while the fish is inside the slider, drain (slower = forgiving) when it slips out
				ceiling = math.min(1, ceiling + ((1 - 0.30) / MIN_FIGHT) * dt) -- the time floor, live-only
				progress = math.clamp(math.min(progress, ceiling) + (inZone and 0.135 or -0.105) * dt, 0, 1)
				progress = math.min(progress, ceiling)
			end
			-- visuals (f=1 is the TOP of the bar)
			ui.zone.Position = UDim2.new(0.5, 0, 1 - zone, 0)
			ui.zone.BackgroundColor3 = inZone and Color3.fromRGB(70,225,95) or Color3.fromRGB(90,150,110)
			ui.fish.Position = UDim2.new(0.5, 0, 1 - fishF, 0)
			ui.pb.Size = UDim2.new(1, 0, progress, 0)
			ui.pb.BackgroundColor3 = (progress > 0.5) and Color3.fromRGB(120,235,110) or Color3.fromRGB(255,205,60)
			if introT <= 0 then
				if progress >= 1 then finish(true); break elseif progress <= 0 then finish(false); break end
			end
			task.wait()
		end
	end)
end

-- Build the BUTTER fishing world: a rod barrel (grab the rod) + a Fish prompt near/over the ButterLake union,
-- and the full cast -> bite/hook -> reel-in -> server-roll -> egg-in-front flow.
local function buildButterWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isFishing = true
	local extra = positions.extra or {}
	local sizes = positions.extraSize or {}
	local lakePos  = extra.butterlake
	local lakeSize = sizes.butterlake
	local barrelPos = extra.rodbarrel
	st.fishProps = {}
	st.hintAnchor = barrelPos or lakePos
	if typeof(lakePos) ~= "Vector3" then warn("[Pet][DIAG] ButterLake position MISSING for "..petId.." -- fishing disabled"); return end
	local surfaceY = lakePos.Y + ((typeof(lakeSize) == "Vector3") and lakeSize.Y/2 or 0)

	-- ===== REALISTIC FISHING VISUALS: rod-in-hand + line + floating red/white bobber =====
	-- A thin rod model rides on the player's hand (updated each frame to follow it, angled forward+up). On
	-- cast, a Beam "line" runs from the rod TIP to a classic red-top/white-bottom bobber that arcs out and
	-- floats on the butter. Lightweight (a handful of parts) but clearly reads as fishing. Defined before the
	-- rod-barrel block so the "Grab Fishing Rod" handler can start the held rod.
	local heldRod, rodTip, rodTipAtt
	local function startHeldRod()
		if heldRod then return end
		local rod = Instance.new("Model"); rod.Name = petId.."HeldRod"
		local function rp(name, shape, size, color, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false
			p.CanQuery = false; p.CastShadow = false; p.Parent = rod; return p
		end
		local shaft = rp("Shaft", Enum.PartType.Cylinder, Vector3.new(6,0.16,0.16), Color3.fromRGB(110,70,40), Enum.Material.SmoothPlastic)
		local grip  = rp("Grip",  Enum.PartType.Cylinder, Vector3.new(1.1,0.26,0.26), Color3.fromRGB(35,30,28))
		local reel  = rp("Reel",  Enum.PartType.Cylinder, Vector3.new(0.3,0.7,0.7), Color3.fromRGB(40,40,46), Enum.Material.Metal)
		rodTip = rp("Tip", Enum.PartType.Ball, Vector3.new(0.16,0.16,0.16), Color3.fromRGB(235,235,235)); rodTip.Transparency = 1
		rodTipAtt = Instance.new("Attachment"); rodTipAtt.Parent = rodTip
		rod.Parent = Workspace; heldRod = rod; st.fishProps[#st.fishProps+1] = rod
		-- TELL EVERYONE ELSE. This rod is a client-built prop in the local Workspace, so by default it exists
		-- for nobody but the holder -- other players see you miming. HeldItemSync picks this flag up and
		-- publishes it as a replicated Player attribute, and every other client draws its own copy on your hand.
		if _G.setHeldQuestItem then _G.setHeldQuestItem("FishingRod") end
		task.spawn(function()
			-- LEASH: the rod belongs to Butter Swamp's lake, so it goes away when you leave. Measured in 3D from
			-- the lake, NOT in X/Z -- the islands sit in a vertical stack with overlapping footprints, so a
			-- flat distance check would still call you "at the lake" while you flew a thousand studs above it.
			-- Flying off is the common case and it moves you almost entirely in Y.
			local ROD_LEASH = 350
			while heldRod and heldRod.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				-- PUT IT AWAY when you leave the island OR the moment you take off. Flying with a fishing
				-- rod welded to your hand looks broken, and the rod is island equipment -- lifting off is
				-- the clearest possible "I am done here" signal a player can give.
				local flyingAway = (_G.isFlying == true)
				if hrp and ((hrp.Position - lakePos).Magnitude > ROD_LEASH or flyingAway) then
					-- put the rod away, drop the flag so other players stop seeing it, and clear hasRod so
					-- the barrel hands you a fresh one when you come back.
					heldRod:Destroy(); heldRod = nil; st.hasRod = false
					if _G.setHeldQuestItem then _G.setHeldQuestItem(nil) end
					print("[Pet] " .. (flyingAway and "took off" or "left Butter Swamp") .. " -- fishing rod put away")
					break
				end
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					local rodDir = (look.Unit + Vector3.new(0, 0.62, 0)).Unit       -- forward + up
					local center = hand.Position + look.Unit * 0.4 + rodDir * 3.0
					local cf = CFrame.lookAt(center, center + rodDir) * CFrame.Angles(0, math.rad(90), 0) -- align cylinder length (X) to rodDir
					shaft.CFrame = cf
					grip.CFrame  = cf * CFrame.new(-2.6, 0, 0)
					reel.CFrame  = cf * CFrame.new(-2.0, -0.35, 0) * CFrame.Angles(0,0,math.rad(90))
					rodTip.CFrame = cf * CFrame.new(3.0, 0, 0)                       -- far end of the shaft (line origin)
				end
				RunService.Heartbeat:Wait()
			end
			-- QUEST FINISHED -> HAND IT BACK. The loop above also ends when st.owns flips true (the pet is
			-- claimed), and without this the rod just stopped following and hung in the air wherever the
			-- player happened to be standing. You keep the pet, not the equipment.
			if heldRod then
				heldRod:Destroy(); heldRod = nil; st.hasRod = false
				if _G.setHeldQuestItem then _G.setHeldQuestItem(nil) end
				print("[Pet] Butter Duck quest done -- fishing rod handed back")
			end
		end)
	end
	-- classic bobber: white body + red cap + red antenna (reads red-top/white-bottom). Root = white body
	-- (anchored, moved by CFrame); cap + antenna welded so they follow. Returns the root part.
	local function buildBobber(cf)
		local root = Instance.new("Part"); root.Name = petId.."Bobber"; root.Shape = Enum.PartType.Ball
		root.Size = Vector3.new(0.55,0.55,0.55); root.Color = Color3.fromRGB(240,240,245); root.Material = Enum.Material.SmoothPlastic
		root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.CastShadow = false; root.CFrame = cf; root.Parent = Workspace
		local function weldTo(part) local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = part; w.Parent = root end
		local cap = Instance.new("Part"); cap.Name="Cap"; cap.Shape=Enum.PartType.Ball; cap.Size=Vector3.new(0.6,0.6,0.6)
		cap.Color=Color3.fromRGB(225,55,55); cap.Material=Enum.Material.SmoothPlastic
		cap.Anchored=false; cap.CanCollide=false; cap.CanQuery=false; cap.CastShadow=false; cap.Massless=true; cap.CFrame=cf*CFrame.new(0,0.22,0); cap.Parent=root; weldTo(cap)
		local ant = Instance.new("Part"); ant.Name="Antenna"; ant.Shape=Enum.PartType.Cylinder; ant.Size=Vector3.new(0.5,0.07,0.07)
		ant.Color=Color3.fromRGB(225,55,55); ant.Material=Enum.Material.SmoothPlastic
		ant.Anchored=false; ant.CanCollide=false; ant.CanQuery=false; ant.CastShadow=false; ant.Massless=true; ant.CFrame=cf*CFrame.new(0,0.62,0)*CFrame.Angles(0,0,math.rad(90)); ant.Parent=root; weldTo(ant)
		return root
	end
	-- the LINE: a Beam from the rod tip to the bobber. Att1 + Beam live ON the bobber, so destroying the
	-- bobber removes them; Att0 is the persistent rod-tip attachment (so the line tracks the moving rod).
	local function attachLine(bobRoot)
		if not rodTipAtt then return end
		local a1 = Instance.new("Attachment"); a1.Name = "LineEnd"; a1.Parent = bobRoot
		local beam = Instance.new("Beam"); beam.Attachment0 = rodTipAtt; beam.Attachment1 = a1
		beam.Width0 = 0.05; beam.Width1 = 0.05; beam.FaceCamera = true; beam.Segments = 4
		beam.Color = ColorSequence.new(Color3.fromRGB(235,235,235)); beam.Transparency = NumberSequence.new(0.15)
		beam.LightInfluence = 1; beam.Parent = bobRoot
	end

	-- ===== ROD BARREL (client-built prop at the captured position) + "Grab Fishing Rod" prompt =====
	if typeof(barrelPos) == "Vector3" then
		local barrel = Instance.new("Model"); barrel.Name = petId.."RodBarrel"
		-- WOODEN BARREL: a brown wood cylinder standing upright (axis = Y) with darker slat BANDS around it.
		local body = newPart(barrel, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,3.0,3.0), Color3.fromRGB(124,82,44), CFrame.new(barrelPos + Vector3.new(0,1.7,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.SmoothPlastic)
		barrel.PrimaryPart = body
		newPart(barrel, "Lip", Enum.PartType.Cylinder, Vector3.new(0.5,3.2,3.2), Color3.fromRGB(96,62,32), CFrame.new(barrelPos + Vector3.new(0,3.35,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.SmoothPlastic) -- top rim
		newPart(barrel, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.5,2.5), Color3.fromRGB(48,32,18), CFrame.new(barrelPos + Vector3.new(0,3.3,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.SmoothPlastic) -- dark opening (so rods read as sticking OUT of it)
		for _, oy in ipairs({0.7, 1.8, 2.9}) do newPart(barrel, "Band", Enum.PartType.Cylinder, Vector3.new(0.28,3.5,3.5), Color3.fromRGB(58,40,24), CFrame.new(barrelPos + Vector3.new(0,oy,0)) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.SmoothPlastic) end -- dark slat bands
		-- SEVERAL FISHING RODS sticking up and OUTWARD out of the barrel, at slight angles around the rim.
		local rimY = barrelPos + Vector3.new(0, 3.0, 0)
		local NRODS = 4
		for i = 0, NRODS - 1 do
			local ang = i * (2*math.pi / NRODS) + 0.4
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local tiltDeg = 20
			local rodLen = 6.5
			local up = math.cos(math.rad(tiltDeg)); local out = math.sin(math.rad(tiltDeg))
			local axis = (outward * out + Vector3.new(0, up, 0)).Unit          -- the rod's lean direction
			local center = rimY + outward * 0.7 + axis * (rodLen/2)
			local cf = CFrame.lookAt(center, center + axis) * CFrame.Angles(0, math.rad(90), 0) -- align cylinder length (local X) to axis
			newPart(barrel, "Rod", Enum.PartType.Cylinder, Vector3.new(rodLen,0.16,0.16), Color3.fromRGB(110,70,40), cf, Enum.Material.SmoothPlastic)
			-- a small dark reel near the rod's base + a tiny tip bead so it reads as a real rod
			newPart(barrel, "RodReel", Enum.PartType.Cylinder, Vector3.new(0.28,0.6,0.6), Color3.fromRGB(38,38,44), cf * CFrame.new(-rodLen/2 + 0.9, -0.32, 0) * CFrame.Angles(0,0,math.rad(90)), Enum.Material.Metal)
			newPart(barrel, "RodTip", Enum.PartType.Ball, Vector3.new(0.22,0.22,0.22), Color3.fromRGB(235,235,235), cf * CFrame.new(rodLen/2, 0, 0))
		end
		barrel.Parent = Workspace
		st.fishProps[#st.fishProps+1] = barrel
		local grab = addPrompt(body, "Grab Fishing Rod", "Rod Barrel", function()
			if st.owns then return end
			-- THE ROD IS THE START OF THE FISHING QUEST -- same rule as the shovel: refused, with directions.
			if not _G.petQuestGate(def, barrelPos) then return end
			if not st.hasRod then
				st.hasRod = true
				startHeldRod() -- show the rod in the player's hand from now on
				floatText(barrelPos + Vector3.new(0,4,0), "Got a fishing rod! \xF0\x9F\x8E\xA3")
				print("[Pet] "..player.Name.." grabbed rod")
			else
				floatText(barrelPos + Vector3.new(0,4,0), "You already have a rod!")
			end
		end)
		grab.HoldDuration = 0.3
		print(string.format("[Pet][DIAG] built rod barrel at (%.0f,%.0f,%.0f)", barrelPos.X, barrelPos.Y, barrelPos.Z))
	else
		warn("[Pet][DIAG] RodBarrel position MISSING for "..petId)
	end

	-- ===== FISHING HUD (status + tap-to-hook + junk popup) =====
	local pgui = player:WaitForChild("PlayerGui")
	local hud = Instance.new("ScreenGui"); hud.Name = "ButterFishingHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 97; hud.Parent = pgui
	-- 97: above NotifyCenter's hero banner (95), below the 100 menus -- so a banner can never draw
	-- through this HUD. Deliberately NOT marked QuestHud, unlike the minigame cards: this ScreenGui is
	-- created once and stays enabled for the WHOLE quest session (only the status frame inside it is
	-- toggled), so marking it would hold every banner for minutes rather than for a modal's lifetime.
	-- status = a blue BACKDROP FRAME (the pill) with a child text label. Visible=FALSE at rest; setStatus/hideStatus
	-- toggle the FRAME's visibility -- so the empty backdrop never lingers on screen when no message is showing.
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,440,0,40)
	status.BackgroundColor3 = Color3.fromRGB(25,90,185); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,215,0); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	-- ===== THE FISHING COMMENTARY IS A BANNER NOW =====
	-- "Waiting for a bite..." / "Something's biting! TAP!" / "Reel it in!" ran in a private blue pill at
	-- y 0.12, in its own font, with its own colours -- a fourth place the game speaks to you from. It is a
	-- banner now, in the shared hero lane, so fishing looks like everything else in the game.
	--
	-- IT IS PINNED, AT RANK.STATUS (30). A pin is right because this is a STANDING readout that changes
	-- several times per cast: re-pinning the same id repaints in place, so the words follow the cast inside
	-- ONE continuous card rather than a stream of separate banners fighting for the slot.
	--
	-- The rank is what stops that being a problem. RANK.STATUS sits BELOW every push priority, so unlike the
	-- tutorial and watering pins this one holds nothing shut: an island landing, a reward, an event, a
	-- milestone -- anything at all preempts it, plays in full, and the commentary steps back in afterwards,
	-- mid-cast, exactly where it was. Somebody can fish for ten minutes without silencing the game.
	--
	-- The old stranding bug is gone by construction. There is no Visible flag to leave true: the card belongs
	-- to NotifyCenter, and the only way to keep it is to keep re-pinning. The unpin below is still called on
	-- the normal path, and the timeout is the backstop for the paths that never reach it (an error mid-loop,
	-- an early break, dying mid-cast) -- the failure this file had, which had NO backstop at all.
	-- Kept in step with FishingQuest_AllInOne.client.lua, which owns a second copy of this HUD.
	local STATUS_PIN = "Fishing"
	local STATUS_MAX_SHOW = 25
	local statusTok = 0
	local function hideStatus()
		statusTok += 1
		status.Visible = false -- the old pill, in case a stale duplicate of this script still shows one
		local NC = _G.NotifyCenter
		if NC and NC.unpin then pcall(NC.unpin, STATUS_PIN) end
	end
	local function setStatus(txt)
		local NC = _G.NotifyCenter
		if NC and NC.pin then
			pcall(NC.pin, STATUS_PIN, {
				rank  = (NC.RANK and NC.RANK.STATUS) or 30,
				top   = "\xF0\x9F\x8E\xA3 FISHING",
				text  = txt,
				color = Color3.fromRGB(25, 90, 185), -- the pill's own blue, so the feature keeps its colour
			})
		else
			status.Visible = true; statusText.Text = txt -- no banner system: fall back to the old pill
		end
		statusTok += 1
		local mine = statusTok
		task.delay(STATUS_MAX_SHOW, function()
			if statusTok ~= mine then return end -- a newer message owns it; its own timer will handle it
			hideStatus()
			warn("[Pet][Fish] status banner auto-cleared after " .. STATUS_MAX_SHOW .. "s -- the fishing flow " ..
				"ended without releasing it. Last text: " .. tostring(txt))
		end)
	end
	local JUNK_EMOJI = {
		["an old boot"] = "\xF0\x9F\xA5\xBE", ["a butter blob"] = "\xF0\x9F\xA7\x88", ["a rubber duck"] = "\xF0\x9F\xA6\x86",
		["a soggy sock"] = "\xF0\x9F\xA7\xA6", ["a rusty tin can"] = "\xF0\x9F\xA5\xAB", ["a clump of swamp weed"] = "\xF0\x9F\x8C\xBF",
		["a lost flip-flop"] = "\xF0\x9F\xA9\xB4", ["a message in a bottle"] = "\xF0\x9F\x8D\xBE",
	}
	local function showJunk(junk)
		local pop = Instance.new("TextLabel"); pop.AnchorPoint = Vector2.new(0.5,0.5); pop.Position = UDim2.new(0.5,0,0.42,0); pop.Size = UDim2.new(0,60,0,60)
		pop.BackgroundTransparency = 1; pop.Font = Enum.Font.GothamBold; pop.TextSize = 70; pop.Text = JUNK_EMOJI[junk] or "\xF0\x9F\xA5\xBE"; pop.TextTransparency = 1; pop.Parent = hud
		local TS = game:GetService("TweenService")
		TS:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0,120,0,120), TextTransparency = 0}):Play()
		task.delay(1.2, function() TS:Create(pop, TweenInfo.new(0.4), {TextTransparency = 1}):Play(); task.delay(0.45, function() pop:Destroy() end) end)
	end
	-- ===== "TAP TO HOOK!" HOLDS FOR A FULL SECOND =====
	-- The label used to die with the catcher on the same frame the tap landed, so a player with quick
	-- reflexes -- exactly the player who is doing it right -- saw the words for two or three frames and then
	-- the screen was back to fishing. The prompt read as a flicker rather than as a moment, and on a fast
	-- hook you could not tell whether you had caught it or missed it.
	--
	-- So the two jobs are separated. They were only ever fused because both lived on the same instance:
	--   THE CATCHER (the orange wash + the invisible full-screen button) ends the INSTANT the tap lands.
	--     It blocks input and tints the screen, so holding it any longer would put a full second of lag
	--     between the tap and the reel minigame -- the one thing that must stay immediate.
	--   THE LABEL is reparented to the HUD and stays up until it has been on screen a full second. It is
	--     just text at that point: not tinting, not blocking, purely the confirmation that you hooked it.
	-- A miss is unaffected -- the window is 1.3s, so the label has already outlived the minimum.
	local HOOK_MIN_SHOW = 1.0
	local function waitForTap(timeout)
		local tapped = false
		local shownAt = os.clock()
		local catcher = Instance.new("TextButton"); catcher.Size = UDim2.new(1,0,1,0); catcher.BackgroundColor3 = Color3.fromRGB(255,120,40)
		catcher.BackgroundTransparency = 0.8; catcher.AutoButtonColor = false; catcher.Text = ""
		-- MenuBackdropGuard hunts full-screen tinted input sinks and hides them as orphaned menu backdrops.
		-- This one is deliberate -- you tap ANYWHERE to hook -- and the guard was killing it 0.25s into the
		-- 1.3s window, which is why every hook was missed. Stamped here as well as exempted by gui name over
		-- there, because a stale baked-in copy of the guard will not have the name list but WILL read this.
		catcher:SetAttribute("NoBackdropGuard", true)
		catcher.Parent = hud
		local big = Instance.new("TextLabel"); big.AnchorPoint = Vector2.new(0.5,0.5); big.Position = UDim2.new(0.5,0,0.5,0); big.Size = UDim2.new(0,320,0,120)
		big.BackgroundTransparency = 1; big.Font = Enum.Font.FredokaOne; big.TextSize = 60; big.TextColor3 = Color3.fromRGB(255,240,120); big.Text = "TAP TO HOOK!"; big.Parent = catcher
		Instance.new("UIStroke", big).Thickness = 3
		-- TouchTap as well as MouseButton1Click: on a phone the click event is not guaranteed on a button
		-- this large, and a missed tap here reads to the player as the hook window being broken.
		local c = catcher.MouseButton1Click:Connect(function() tapped = true end)
		local c2 = catcher.TouchTap:Connect(function() tapped = true end)
		local t = 0; while t < timeout and not tapped do t = t + task.wait() end
		c:Disconnect(); c2:Disconnect()

		-- Both are full-screen and `big` is centre-anchored, so moving it from the catcher to the HUD does
		-- not shift it by a pixel -- it simply outlives the thing that was tinting the screen.
		big.Parent = hud
		catcher:Destroy()

		local remain = HOOK_MIN_SHOW - (os.clock() - shownAt)
		if remain > 0 then
			-- task.delay, NOT a wait: this function must return the moment the tap is known, or the whole
			-- fishing sequence stalls for a second before the reel minigame opens.
			task.delay(remain, function() if big.Parent then big:Destroy() end end)
		else
			big:Destroy()
		end
		return tapped
	end

	-- ===== the BUTTER EGG (caught) -> appears IN FRONT of the player, with a Hatch prompt (reuses hatchEgg) =====
	local function spawnButterEgg()
		if st.egg then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local fwd = hrp.CFrame.LookVector; fwd = Vector3.new(fwd.X, 0, fwd.Z); if fwd.Magnitude < 0.1 then fwd = Vector3.new(0,0,-1) end
		local center = hrp.Position + fwd.Unit * 6 + Vector3.new(0, -1.0, 0) -- a few studs in front, near the ground
		st.eggPos = center; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(250,224,120), nil)
		shell.Reflectance = 0.08
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 8 do local a = (j-1)*(2*math.pi/8); local y = math.sin(a*1.7)*1.0; local r = 1.3*math.sqrt(math.max(0, 1-(y/2)^2))+0.05
			newPart(visual, "Drip", Enum.PartType.Ball, Vector3.new(0.45,0.45,0.45), Color3.fromRGB(255,236,150), CFrame.new(math.sin(a)*r, y, math.cos(a)*r)) end
		st.eggBaseCF = CFrame.new(center)
		st.eggVisual = visual; visual:PivotTo(st.eggBaseCF)
		st.egg = egg; egg.Parent = Workspace
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(255,235,140); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(255,210,80); hl.Adornee = visual; hl.Parent = egg
		addPrompt(shell, "Hatch", "Butter Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] butter egg caught -> appeared in front of "..player.Name)
	end

	-- ===== near the EXPOSED butter EDGE (so you can fish from the shore, on land) =====
	-- The ButterLake union extends UNDER the whole landmass, so its bounding box covers the island and a
	-- box/center distance check is useless. Instead we PROBE for exposed butter with downward rays in a
	-- small ring AROUND the player: if a ray straight DOWN from the player OR from any nearby ring point
	-- hits the ButterLake union FIRST, the player is standing on/beside EXPOSED butter (i.e. at the shore).
	-- This lets them fish from LAND a few studs from the edge without stepping onto the butter, and it does
	-- NOT trigger in the island middle (every probe there hits land first). butterProbe() returns the
	-- nearest exposed-butter world point within reach (so the line can cast OUT INTO the butter), or nil.
	-- (All our client props are CanQuery=false, so the rays ignore them and only hit real world geometry.)
	local EDGE_REACH = 7   -- TIGHT: only a few studs from the exposed butter counts as "at the edge" (must be right at the shoreline, not partway into the island)
	local function butterProbe()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		params.IgnoreWater = true
		local origin = hrp.Position
		local function probe(px, pz)
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 5, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			local inst = r.Instance
			if inst.Name == "ButterLake" or inst:FindFirstAncestor("ButterLake") ~= nil then return r.Position end
			return nil
		end
		local p = probe(origin.X, origin.Z); if p then return p end          -- standing right on the butter
		for _, rad in ipairs({ EDGE_REACH * 0.55, EDGE_REACH }) do           -- else a SMALL ring out to the edge only
			for i = 0, 11 do                                                 -- 12 dirs (denser, since the radius is tiny)
				local a = i * (math.pi / 6)
				p = probe(origin.X + math.cos(a) * rad, origin.Z + math.sin(a) * rad)
				if p then return p end
			end
		end
		return nil
	end
	local function isNearButterEdge() return butterProbe() ~= nil end

	-- ===== where the cast LANDS: a point OUT on the butter, in front of the player =====
	-- The old target (butterProbe's first hit) often landed at the player's feet or off to a fixed side.
	-- Instead: find the horizontal DIRECTION toward the butter (toward the nearest butter, or the player's
	-- facing if already standing on butter), then march OUT along it and drop the bobber a few studs ONTO
	-- the open butter past the edge. Returns a Vector3 on the butter surface, or nil if no butter found.
	local function castTarget()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		params.IgnoreWater = true
		local origin = hrp.Position
		local function butterY(px, pz) -- butter surface Y at (px,pz) if the FIRST thing below is butter, else nil
			local r = Workspace:Raycast(Vector3.new(px, origin.Y + 8, pz), Vector3.new(0, -400, 0), params)
			if not r or not r.Instance then return nil end
			local inst = r.Instance
			if inst.Name == "ButterLake" or inst:FindFirstAncestor("ButterLake") ~= nil then return r.Position.Y end
			return nil
		end
		-- 1) direction toward the butter
		local look = hrp.CFrame.LookVector; look = Vector3.new(look.X, 0, look.Z)
		look = (look.Magnitude > 0.1) and look.Unit or Vector3.new(0, 0, -1)
		local dir
		if butterY(origin.X, origin.Z) then
			dir = look                                   -- already on butter -> cast where we're facing
		else
			local best, bestDist                         -- nearest butter around us -> head that way
			for i = 0, 11 do
				local a = i * (math.pi / 6)
				local d = Vector3.new(math.cos(a), 0, math.sin(a))
				for _, rad in ipairs({ 3, 6, 9, 12 }) do
					if butterY(origin.X + d.X * rad, origin.Z + d.Z * rad) then
						if not bestDist or rad < bestDist then bestDist = rad; best = d end
						break
					end
				end
			end
			dir = best or look
		end
		-- 2) march OUT along dir; drop the bobber a few studs onto the butter, past where it starts
		local CAST_OUT, CAST_MAX, STEP = 8, 28, 2
		local edgeDist, lastY, lastD
		for d = 1, CAST_MAX, STEP do
			local by = butterY(origin.X + dir.X * d, origin.Z + dir.Z * d)
			if by then
				edgeDist = edgeDist or d
				lastY, lastD = by, d
				if d >= edgeDist + CAST_OUT then
					return Vector3.new(origin.X + dir.X * d, by + 0.45, origin.Z + dir.Z * d) -- out on open butter
				end
			end
		end
		if lastY then return Vector3.new(origin.X + dir.X * lastD, lastY + 0.45, origin.Z + dir.Z * lastD) end -- furthest butter we found
		return nil
	end

	-- ===== the FISH prompt (lives on a part that FOLLOWS the player, NOT a fixed island-center anchor) =====
	-- The follower part is repositioned to the player every frame (loop below), so the "[E] Fish" prompt
	-- appears NEXT TO THE PLAYER at the shore. A ProximityPrompt natively shows "[E] Fish" on desktop + a
	-- tap button on mobile; we enable it only while near the exposed butter edge.
	local fishFollower = newPart(Workspace, petId.."FishSpot", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(lakePos))
	fishFollower.Transparency = 1
	st.fishProps[#st.fishProps+1] = fishFollower
	local fishing = false
	local fishPrompt -- forward-declared so the closure below captures THIS local (not a nil global)
	fishPrompt = addPrompt(fishFollower, "Fish", "Butter Swamp", function()
		if st.owns or st.eggCaught or fishing then return end
		if not _G.petQuestGate(def, lakePos) then return end -- the Angler has to hand you this first
		if not st.hasRod then floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or lakePos) + Vector3.new(0,3,0), "Grab a rod from the barrel first!"); return end
		if not isNearButterEdge() then floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or lakePos) + Vector3.new(0,3,0), "Get closer to the butter's edge to fish!"); return end
		fishing = true; fishPrompt.Enabled = false
		pushQuestProg(petId, { started = true }) -- HUD: minimize to the live fishing tracker
		task.spawn(function()
			local TS = game:GetService("TweenService")
			local keepGoing = true
			-- STOP when the player owns it OR walks away from the butter edge. Without the isNearButterEdge()
			-- gate the loop recast FOREVER and left the blue "status" HUD bar stuck on screen.
			while keepGoing and not st.owns and isNearButterEdge() do
				-- STEP 1: CAST -- a bobber arcs from the rod tip OUT onto the butter in FRONT of the player.
				-- castTarget() aims toward the nearest butter and lands the bobber a few studs out from the edge.
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local target = castTarget()  -- a point OUT on the butter in front of the player (toward nearest butter)
					or (hrp and Vector3.new(hrp.Position.X, surfaceY + 0.4, hrp.Position.Z))
					or Vector3.new(lakePos.X, surfaceY + 0.4, lakePos.Z)
				-- cast the line from the ROD TIP (in hand) out to a red/white BOBBER that arcs in + floats.
				local startP = (rodTip and rodTip.Position) or (hrp and (hrp.Position + Vector3.new(0,1.5,0))) or target
				local bob = buildBobber(CFrame.new(startP)); attachLine(bob) -- bobber + the line beam to the rod tip
				local nv = Instance.new("NumberValue"); nv.Value = 0; nv.Parent = bob
				nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; bob.CFrame = CFrame.new(startP:Lerp(target, t) + Vector3.new(0, math.sin(t*math.pi)*6, 0)) end)
				TS:Create(nv, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Value = 1}):Play()
				-- CAST: flat, on the frame the bobber leaves the rod tip.
				pcall(function() playFishSfx("cast") end)
				-- SPLASH: at +0.6s, matching the arc tween above, and parented to the BOBBER so it arrives
				-- from where the bobber actually landed. Re-checks bob.Parent because the player can walk
				-- away from the butter edge mid-arc, which destroys the bobber before it ever touches down.
				task.delay(0.6, function()
					if bob and bob.Parent then pcall(function() playFishSfx("splash", bob) end) end
				end)
				print("[Pet] "..player.Name.." cast"); setStatus("Waiting for a bite...")
				-- gentle idle BOB on the butter surface once the cast lands (until the bite takes over).
				local floating = true
				task.spawn(function()
					task.wait(0.62)
					local ft = 0
					while floating and bob.Parent do ft = ft + 0.05; pcall(function() bob.CFrame = CFrame.new(target + Vector3.new(0, math.sin(ft*2.2)*0.16, 0)) end); task.wait(0.05) end
				end)
				task.wait(0.65 + 1 + math.random() * 3) -- cast settle + random 1-4s until a bite
				floating = false
				if st.owns or not isNearButterEdge() then pcall(function() bob:Destroy() end) break end -- walked away from the butter edge (or owns) -> stop; loop-end hides the status
				-- STEP 2: THE BITE -- bobber dips/wiggles + "!" ; tap within ~1.3s to HOOK
				print("[Pet] "..player.Name.." bite")
				-- BITE: flat and loud (1.6). This cue is a 1.3-second REACTION WINDOW opening -- if the player
				-- is looking anywhere but at the bobber, this sound is the only thing that tells them to tap,
				-- so it deliberately does not fall off with distance the way the splash does.
				pcall(function() playFishSfx("bite") end)
				-- The 1.3s reaction window is open. `alert` is the rising jab -- it exists for exactly this.
				if _G.hapticPulse then pcall(_G.hapticPulse, "alert") end
				local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,36,0,36); bb.StudsOffset = Vector3.new(0,2.4,0); bb.AlwaysOnTop = true; bb.Parent = bob
				local bl = Instance.new("TextLabel"); bl.Size = UDim2.new(1,0,1,0); bl.BackgroundTransparency = 1; bl.Font = Enum.Font.GothamBold; bl.TextSize = 34; bl.TextColor3 = Color3.fromRGB(255,70,70); bl.Text = "!"; bl.Parent = bb
				local biteBase = bob.Position
				local wiggling = true
				task.spawn(function() local t = 0; while wiggling and bob.Parent do t = t + 0.04; pcall(function() bob.CFrame = CFrame.new(biteBase + Vector3.new(math.sin(t*30)*0.18, -math.abs(math.sin(t*16))*0.5, math.cos(t*30)*0.18)) end); task.wait(0.03) end end)
				setStatus("Something's biting! TAP!")
				local hooked = waitForTap(1.3)
				wiggling = false
				if not hooked then
					setStatus("It got away!"); print("[Pet] "..player.Name.." missed the hook")
					if _G.hapticPulse then pcall(_G.hapticPulse, "fail") end
					pcall(function() bob:Destroy() end); task.wait(1.1)
				else
					print("[Pet] "..player.Name.." hooked"); setStatus("Reel it in!")
					if _G.hapticPulse then pcall(_G.hapticPulse, "bump") end
					pcall(function() bob:Destroy() end)
					-- STEP 3: REEL-IN tension minigame (blocks until done)
					local rDone, rWin = false, false
					openReelMinigame(function(s) rWin = s; rDone = true end)
					while not rDone do task.wait() end
					if not rWin then
						setStatus("It got away!"); print("[Pet] "..player.Name.." reel-in failed"); task.wait(1.1)
						if _G.hapticPulse then pcall(_G.hapticPulse, "fail") end
					else
						print("[Pet] "..player.Name.." reeled in")
						if _G.hapticPulse then pcall(_G.hapticPulse, "milestone") end
						pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1 }) -- HUD: bump the reeled-in counter
						-- STEP 4: SERVER rolls the catch (pity) -- the client NEVER decides
						local ok, res = pcall(function() return PetFishRoll:InvokeServer() end)
						-- PULL-OUT: the moment something breaks the surface, fired BEFORE the status text so the
						-- sound leads the words rather than trailing them.
						--
						-- It plays for an EGG **and** for JUNK, deliberately: the player pulled something out
						-- either way, and staying silent on junk would turn the absence of a sound into a
						-- spoiler -- you would know it was a miss before the text told you. It does NOT play on
						-- the third branch, where the server roll itself failed and nothing was ever pulled out.
						if ok and type(res) == "table" then
							pcall(function() playFishSfx("pullOut") end)
						end
						if ok and type(res) == "table" and res.egg then
							setStatus("You reeled in... an EGG! \xF0\x9F\xA5\x9A"); keepGoing = false; pushQuestProg(petId, { complete = true }) -- HUD: quest complete
							task.wait(0.6); spawnButterEgg(); task.wait(1.4) -- show "EGG!" a moment; the loop-end below hides the backdrop
						elseif ok and type(res) == "table" then
							setStatus("You caught: "..(res.junk or "junk").."!"); showJunk(res.junk or ""); task.wait(1.8)
						else
							setStatus("It got away!"); task.wait(1.1)
							if _G.hapticPulse then pcall(_G.hapticPulse, "fail") end
						end
					end
				end
			end
			fishing = false
			hideStatus() -- ALWAYS hide the status backdrop when the flow ends (got-away / caught / walked away / owned) so it never lingers
			if not st.owns and not st.eggCaught then fishPrompt.Enabled = true end
		end)
	end)
	-- The prompt part rides ON the player, so the activation distance only needs to cover that tiny gap.
	fishPrompt.MaxActivationDistance = 16
	fishPrompt.HoldDuration = 0
	fishPrompt.Enabled = false  -- starts hidden (the follower begins at lakePos); the loop enables it only at the edge
	-- FOLLOW THE PLAYER + GATE: every frame, move the prompt part to the player so "[E] Fish" appears next to
	-- them (never at the island center). Enable it ONLY while near the exposed butter EDGE (probe throttled to
	-- ~0.2s) so it shows at the shore and hides in the island middle. While a fishing attempt is running, that
	-- attempt owns the prompt's Enabled state (it disables it during cast/reel), so we leave it alone then.
	task.spawn(function()
		local probeTimer, nearCached = 0, false
		while st and not st.owns do
			local dt = RunService.Heartbeat:Wait()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then fishFollower.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 1.5, 0)) end
			probeTimer = probeTimer - dt
			if probeTimer <= 0 then probeTimer = 0.2; nearCached = isNearButterEdge() end
			if not fishing and not st.eggCaught then fishPrompt.Enabled = (hrp ~= nil) and nearCached end
		end
	end)
	print(string.format("[Pet][DIAG] butter fishing ready: lake=(%.0f,%.0f,%.0f) size=%s", lakePos.X, lakePos.Y, lakePos.Z, (typeof(lakeSize)=="Vector3") and string.format("(%.0f,%.0f,%.0f)", lakeSize.X, lakeSize.Y, lakeSize.Z) or "?"))

	-- avoid a flash of the props for someone who already OWNS the duck
	if st.owns then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end
end

-- ============================================================================================
-- BURRITO ARMADILLO QUEST (questType "dig"). "ARMADILLO TRAIL": grab a SHOVEL at the stand -> dig the active
-- low-poly dirt MOUND (multi-swing: each E-tap shrinks it away + dirt burst) -> fully dug, a DECOY reveals junk
-- + lays ARMADILLO TRACKS leading to the NEXT mound (which then appears) -> follow the trail DigSpot1 -> 2 -> 3
-- -> 4 -> 5 -> BuriedEggSpot, ONE mound at a time (~3-min hunt across the island) -> the final spot reveals the
-- armadillo EGG (rises out) -> Hatch prompt -> shared hatch flow -> the Burrito Armadillo follows. Mounds are
-- CLIENT-BUILT low-poly PARTS (no terrain). The real-dig completion is server-gated (PetDigEvent). Cosmetic-only.
-- ============================================================================================
local function buildBurritoWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	st.built = true; st.isDigging = true
	local TS = game:GetService("TweenService")
	local extra = positions.extra or {}
	local shovelPos = extra.shovel
	local buriedPos = extra.buriedegg
	-- ARMADILLO TRAIL order: DigSpot1 -> 2 -> 3 -> 4 -> 5 -> BuriedEggSpot (one mound active at a time)
	local digSpots = {
		{ key="dig1", pos=extra.dig1, real=false, label="DigSpot1" },
		{ key="dig2", pos=extra.dig2, real=false, label="DigSpot2" },
		{ key="dig3", pos=extra.dig3, real=false, label="DigSpot3" },
		{ key="dig4", pos=extra.dig4, real=false, label="DigSpot4" },
		{ key="dig5", pos=extra.dig5, real=false, label="DigSpot5" },
		{ key="buriedegg", pos=buriedPos, real=true, label="BuriedEggSpot" },
	}
	st.digProps = {}
	st.hintAnchor = shovelPos or buriedPos -- the on-landing pet-quest hint anchors on the island
	if typeof(buriedPos) ~= "Vector3" then warn("[Pet][DIAG] BuriedEggSpot position MISSING for "..petId.." -- dig quest may not complete") end

	local pgui = player:WaitForChild("PlayerGui")
	-- ===== HUD: just a status pill for dig-result messages (no hot/cold meter -- the dig feedback is in-world) =====
	local hud = Instance.new("ScreenGui"); hud.Name = "BurritoDigHUD"; hud.ResetOnSpawn = false; hud.DisplayOrder = 97; hud.Parent = pgui
	-- 97: above NotifyCenter's hero banner (95), below the 100 menus -- so a banner can never draw
	-- through this HUD. Deliberately NOT marked QuestHud, unlike the minigame cards: this ScreenGui is
	-- created once and stays enabled for the WHOLE quest session (only the status frame inside it is
	-- toggled), so marking it would hold every banner for minutes rather than for a modal's lifetime.
	local status = Instance.new("Frame"); status.AnchorPoint = Vector2.new(0.5,0); status.Position = UDim2.new(0.5,0,0.12,0); status.Size = UDim2.new(0,470,0,40)
	status.BackgroundColor3 = Color3.fromRGB(150,96,40); status.BackgroundTransparency = 0.12; status.BorderSizePixel = 0; status.Visible = false; status.Parent = hud
	Instance.new("UICorner", status).CornerRadius = UDim.new(0,10); local sstk = Instance.new("UIStroke", status); sstk.Color = Color3.fromRGB(255,225,150); sstk.Thickness = 2
	local statusText = Instance.new("TextLabel"); statusText.Size = UDim2.new(1,0,1,0); statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.GothamBold; statusText.TextSize = 20; statusText.TextColor3 = Color3.new(1,1,1); statusText.Text = ""; statusText.Parent = status
	local function setStatus(t) statusText.Text = t; status.Visible = true end
	local function hideStatus() status.Visible = false end
	-- (NO hot/cold meter -- players find the buried egg by EXPLORING + digging the visible mounds themselves.)
	-- desert junk items (the in-world reveal that RISES out of a decoy hole uses these emoji)
	local DIG_JUNK = { "an old boot", "a cattle skull", "a rusty can", "a prickly cactus", "a horseshoe", "a coyote bone", "a tumbleweed" }
	local DIG_JUNK_EMOJI = { ["an old boot"]="\xF0\x9F\xA5\xBE", ["a cattle skull"]="\xF0\x9F\x92\x80", ["a rusty can"]="\xF0\x9F\xA5\xAB", ["a prickly cactus"]="\xF0\x9F\x8C\xB5", ["a horseshoe"]="\xF0\x9F\xA7\xB2", ["a coyote bone"]="\xF0\x9F\xA6\xB4", ["a tumbleweed"]="\xF0\x9F\x8C\xBE" }

	-- ===== SHARED LOW-POLY SHOVEL + BARREL STYLE (so the barrel, the shovels in it, and the held shovel all
	-- match): one wood-brown tone, one blade metal, one faceting level. =====
	local SH_WOOD   = Color3.fromRGB(124,82,44)   -- wood-brown for ALL wood (barrel staves + shovel shafts/grips)
	local SH_WOOD_D = Color3.fromRGB(94,60,30)    -- darker wood (barrel rims)
	local SH_HOOP   = Color3.fromRGB(96,98,108)   -- metal barrel band/hoop
	local SH_BLADE  = Color3.fromRGB(150,154,164) -- shovel blade metal
	local SH_LEN    = 4.4                          -- shovel shaft length
	-- Build a low-poly SHOVEL model in LOCAL space: PrimaryPart (Root) at the GRIP; local +X runs DOWN the shaft
	-- toward the BLADE. Place it by PivotTo(cf) where cf's +X (RightVector) points grip->blade. Used by both the
	-- barrel (static) and the held shovel (follows the hand) so they're identical.
	-- REAL "Shovel" ASSET FIRST. If a Model or Part named "Shovel" exists (ReplicatedStorage first, so a clean
	-- template beats a dressed world prop; then Workspace), it is CLONED for every shovel this quest needs --
	-- the three in the barrel and the one in the player's hand -- and the low-poly build below becomes only the
	-- fallback for when it is missing or streamed out. Both call sites go through here, so there is nothing else
	-- to change.
	--
	-- The clone has to behave like the procedural one or PivotTo puts it through the floor: pivot AT THE GRIP,
	-- local +X running grip -> blade. A hand-modelled shovel can be built along any axis, facing either way, at
	-- any scale, so the clone is normalised rather than trusted:
	--   * SHAFT AXIS = the longest side of the bounding box (a shovel is much longer than it is wide);
	--   * WHICH END IS THE BLADE = the volume-weighted centroid of the parts. The blade is a solid lump and the
	--     shaft is a thin stick, so the centre of mass always sits on the blade side. Set a `FlipShovel`
	--     Boolean attribute on the asset if a particular model fools it -- no code change needed;
	--   * SCALE = matched to the built-in shovel's length, so the hand offsets and barrel positions below keep
	--     working for an asset authored at any size. `ShovelScale` on the asset overrides it.
	-- The template itself is left exactly where it is and never touched -- this only ever clones.
	local function buildShovel()
		if st.shovelTemplate == nil then
			-- false = searched and found nothing (so we never walk the tree again); an Instance = found.
			st.shovelTemplate = false
			for _, where in ipairs({ RS, Workspace }) do
				local found = where:FindFirstChild("Shovel", true)
				if found and (found:IsA("Model") or found:IsA("BasePart")) then st.shovelTemplate = found; break end
			end
			print("[Pet][DIAG] Shovel asset: " .. (st.shovelTemplate and st.shovelTemplate:GetFullName() or "NOT FOUND -> using built-in shovel"))
		end
		if st.shovelTemplate then
			local src = st.shovelTemplate
			local m = src:Clone()
			if m:IsA("BasePart") then
				-- a bare Part named "Shovel": wrap it so PivotTo / WorldPivot work the same as for a Model
				local wrap = Instance.new("Model"); m.Parent = wrap; wrap.PrimaryPart = m; m = wrap
			end
			m.Name = petId .. "Shovel"
			-- static prop: never collide, never block a raycast (the landing + dig detection both raycast), and
			-- drop anything that would run or prompt a second time out of the clone.
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
				elseif d:IsA("ProximityPrompt") or d:IsA("BaseScript") then
					d:Destroy()
				end
			end
			local cf, size = m:GetBoundingBox()
			local ax, len = cf.RightVector, size.X
			if size.Y >= size.X and size.Y >= size.Z then ax, len = cf.UpVector, size.Y
			elseif size.Z >= size.X and size.Z >= size.Y then ax, len = cf.LookVector, size.Z end
			-- volume-weighted centre of mass -> which half the blade is in
			local acc, vol = Vector3.zero, 0
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					local v = math.max(d.Size.X * d.Size.Y * d.Size.Z, 1e-4)
					acc = acc + d.Position * v; vol = vol + v
				end
			end
			local lean = ((vol > 0 and (acc / vol) or cf.Position) - cf.Position):Dot(ax)
			if m:GetAttribute("FlipShovel") == true then lean = -lean end
			local toBlade = (lean >= 0) and ax or -ax
			-- match the built-in shovel's overall length so the hand/barrel offsets below still fit
			local wanted = tonumber(m:GetAttribute("ShovelScale"))
			if not wanted and len > 0.05 then wanted = (SH_LEN + 1.1) / len end
			if wanted and wanted > 0 and math.abs(wanted - 1) > 0.02 then
				pcall(function() m:ScaleTo(wanted) end)
				cf, size = m:GetBoundingBox()
				len = len * wanted
			end
			local grip = cf.Position - toBlade * (len / 2)
			-- lookAt blows up when the direction is parallel to the up hint, and a shovel modelled straight up
			-- or straight down is exactly that case -- so pick a different hint when the shaft is near-vertical.
			local upHint = (math.abs(toBlade.Y) > 0.99) and Vector3.new(0, 0, 1) or Vector3.new(0, 1, 0)
			-- SAME form as shovelCF below (+X = the shaft direction). Written out rather than called, because
			-- shovelCF is declared AFTER this function -- calling it here would compile as a global and be nil.
			m.WorldPivot = CFrame.lookAt(grip, grip + toBlade, upHint) * CFrame.Angles(0, math.rad(90), 0)
			m.Parent = Workspace
			return m
		end
		local m = Instance.new("Model"); m.Name = petId.."Shovel"
		local function rp(name, shape, size, color, cf, mat)
			local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
			p.Material = mat or Enum.Material.SmoothPlastic; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false; p.Parent = m
			p.CFrame = cf; return p
		end
		local root = rp("Root", Enum.PartType.Ball, Vector3.new(0.2,0.2,0.2), SH_WOOD, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
		rp("Handle", Enum.PartType.Cylinder, Vector3.new(SH_LEN,0.26,0.26), SH_WOOD, CFrame.new(SH_LEN/2,0,0), Enum.Material.SmoothPlastic)        -- shaft along +X
		rp("Grip",   Enum.PartType.Cylinder, Vector3.new(1.3,0.24,0.24), SH_WOOD, CFrame.new(-0.1,0,0) * CFrame.Angles(0,math.rad(90),0), Enum.Material.SmoothPlastic) -- T grip cross-bar at the top
		rp("Socket", Enum.PartType.Cylinder, Vector3.new(0.6,0.34,0.34), SH_BLADE, CFrame.new(SH_LEN+0.1,0,0), Enum.Material.Metal)        -- shaft->blade collar
		rp("Blade",  Enum.PartType.Block,    Vector3.new(0.45,1.4,1.2), SH_BLADE, CFrame.new(SH_LEN+0.85,0,0), Enum.Material.Metal)        -- flat metal scoop at the far end
		m.Parent = Workspace
		return m
	end
	-- align a model's local +X (shaft) to a world direction `d`, with the grip (pivot) at `gripPos`
	local function shovelCF(gripPos, d) return CFrame.lookAt(gripPos, gripPos + d) * CFrame.Angles(0, math.rad(90), 0) end

	-- ===== HELD SHOVEL (rides on the player's hand once grabbed) =====
	local heldShovel
	local function startHeldShovel()
		if heldShovel then return end
		heldShovel = buildShovel(); heldShovel.Name = petId.."HeldShovel"; st.digProps[#st.digProps+1] = heldShovel
		task.spawn(function()
			-- the dig site (the shovel barrel's own spot): anything past this is "left the island", same
			-- idea as the rod's ROD_LEASH
			local digHome = shovelPos
			while heldShovel and heldShovel.Parent and not st.owns do
				local char = player.Character
				local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				-- PUT IT AWAY on take-off, or if you wander right off the island. A shovel welded to your
				-- hand mid-flight looks broken, and it is dig-site equipment -- the barrel hands you a
				-- fresh one the moment you come back.
				local flyingAway = (_G.isFlying == true)
				local strayed = hrp and typeof(digHome) == "Vector3"
					and (hrp.Position - digHome).Magnitude > 350
				if hrp and (flyingAway or strayed) then
					heldShovel:Destroy(); heldShovel = nil
					print("[Pet] " .. (flyingAway and "took off" or "left Burrito Barrens") .. " -- shovel put away")
					break
				end
				if hand and hrp then
					local look = hrp.CFrame.LookVector; look = Vector3.new(look.X,0,look.Z)
					if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
					-- ===== HELD BY THE HANDLE, BLADE DOWN AND FORWARD =====
					-- `dirShaft` is the direction from GRIP to BLADE, so it must point away from the hand,
					-- forward and steeply down -- the natural digging carry. It read as upside down because
					-- the shaft was too shallow (-0.5) to sell "blade at the ground": the tool sat out
					-- horizontally like a lance. -1.15 puts the blade clearly below the hand.
					--
					-- The hand end is the T-grip: `gripPos` is pulled BACK along the shaft from the palm, so
					-- the fist closes on the handle rather than the middle of the shaft.
					local dirShaft = (look.Unit + Vector3.new(0,-1.15,0)).Unit
					local gripPos = hand.Position + Vector3.new(0,0.15,0) - dirShaft*0.55
					heldShovel:PivotTo(shovelCF(gripPos, dirShaft))
				end
				RunService.Heartbeat:Wait()
			end
			-- QUEST FINISHED -> HAND IT BACK, same as the fishing rod. The loop also ends when st.owns
			-- flips true, and without this the shovel simply stopped following and hung in mid-air.
			if heldShovel then
				heldShovel:Destroy(); heldShovel = nil
				print("[Pet] Burrito Armadillo quest done -- shovel handed back")
			end
		end)
	end

	-- ===== SHOVEL BARREL (low-poly wooden barrel of shovels) + "Grab Shovel" prompt =====
	if typeof(shovelPos) == "Vector3" then
		local stand = Instance.new("Model"); stand.Name = petId.."ShovelStand"
		local cyc = function(y) return CFrame.new(shovelPos + Vector3.new(0,y,0)) * CFrame.Angles(0,0,math.rad(90)) end -- vertical cylinder CFrame at height y
		local body = newPart(stand, "Barrel", Enum.PartType.Cylinder, Vector3.new(3.4,2.4,2.4), SH_WOOD, cyc(1.7), Enum.Material.SmoothPlastic)
		stand.PrimaryPart = body
		newPart(stand, "Bulge", Enum.PartType.Cylinder, Vector3.new(1.5,2.85,2.85), SH_WOOD, cyc(1.7), Enum.Material.SmoothPlastic)            -- slight middle bulge (classic barrel)
		newPart(stand, "RimBot", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(0.45), Enum.Material.SmoothPlastic)        -- top + bottom rims
		newPart(stand, "RimTop", Enum.PartType.Cylinder, Vector3.new(0.5,2.55,2.55), SH_WOOD_D, cyc(2.95), Enum.Material.SmoothPlastic)
		newPart(stand, "Inside", Enum.PartType.Cylinder, Vector3.new(0.4,2.0,2.0), Color3.fromRGB(46,30,16), cyc(3.05), Enum.Material.SmoothPlastic) -- dark opening (shovels read as sticking OUT of it)
		for _, oy in ipairs({1.0, 2.4}) do newPart(stand, "Hoop", Enum.PartType.Cylinder, Vector3.new(0.32,2.75,2.75), SH_HOOP, cyc(oy), Enum.Material.Metal) end -- metal barrel bands/hoops
		stand.Parent = Workspace; st.digProps[#st.digProps+1] = stand
		-- SHOVELS sticking up out of the barrel (same low-poly shovel as the held one -> matching set): grip + handle
		-- poke UP/out, blade down inside the barrel.
		for i = 1, 3 do
			local ang = (i - 2) * 0.7
			local outward = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local gripPos = shovelPos + Vector3.new(0, 4.8, 0) + outward * 1.1   -- grip high + out (handle sticks out)
			local dirShaft = (Vector3.new(0,-1.6,0) - outward * 0.55).Unit       -- shaft runs DOWN + inward (blade into the barrel)
			local sv = buildShovel(); sv:PivotTo(shovelCF(gripPos, dirShaft)); st.digProps[#st.digProps+1] = sv
		end
		local grab = addPrompt(body, "Grab Shovel", "Shovel Stand", function()
			if st.owns then return end
			-- THE SHOVEL IS THE START OF THE DIG QUEST, so this is where it gets refused: the barrel is right
			-- there and the prompt still works, it just tells you who to see rather than arming the quest.
			if not _G.petQuestGate(def, shovelPos) then return end
			if not st.hasShovel then
				st.hasShovel = true
				startHeldShovel()
				floatText(shovelPos + Vector3.new(0,4,0), "Got a shovel! Now find + dig the mounds. \xE2\x9B\x8F")
				print("[Pet] "..player.Name.." grabbed shovel (can dig the mounds now)")
			else
				floatText(shovelPos + Vector3.new(0,4,0), "You already have a shovel!")
			end
		end)
		grab.HoldDuration = 0.3
		print(string.format("[Pet][DIAG] built shovel stand at (%.0f,%.0f,%.0f)", shovelPos.X, shovelPos.Y, shovelPos.Z))
	else
		warn("[Pet][DIAG] ShovelSpot position MISSING for "..petId)
	end

	-- RETUNED FOR LENGTH: 6 swings emptied a mound in ~2s of mashing. The WIND-UP between swings (the prompt
	-- goes quiet for SWING_COOLDOWN after each one) IS the floor here: 14 swings x ~1.05s of forced cadence
	-- puts a mound at ~15s minimum, and spamming E can't beat it because extra presses do nothing.
	-- 50% FEWER SWINGS (was 14). Six mounds x 14 taps was 84 E-presses for one pet; at 7 it is 42. Only the
	-- tap COUNT changed -- the mound still shrinks one step per swing, so each dig looks the same, it just
	-- takes half as many presses to finish.
	local N_SWINGS = 7           -- E-taps ("swings") to fully dig a mound away (it shrinks one step per swing)
	local SWING_COOLDOWN = 1.0   -- seconds the shovel takes to come back up between swings (13 x 1.0 = 13s floor)
	-- a dug-up JUNK item RISES out of the decoy hole (in-world reveal), holds, then fades away
	local function junkRise(pos, junkName)
		local j = newPart(Workspace, petId.."DugJunk", Enum.PartType.Ball, Vector3.new(1.3,1.3,1.3), Color3.fromRGB(120,92,60), CFrame.new(pos + Vector3.new(0, -3.0, 0)), Enum.Material.SmoothPlastic)
		st.digProps[#st.digProps+1] = j
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,64,0,64); bb.StudsOffset = Vector3.new(0,2.0,0); bb.AlwaysOnTop = true; bb.Adornee = j; bb.Parent = j
		local lb = Instance.new("TextLabel"); lb.Size = UDim2.new(1,0,1,0); lb.BackgroundTransparency = 1; lb.Font = Enum.Font.GothamBold; lb.TextSize = 50; lb.Text = DIG_JUNK_EMOJI[junkName] or "\xF0\x9F\xA6\xB4"; lb.Parent = bb
		TS:Create(j, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) }):Play() -- rises up out of the hole
		task.delay(2.4, function()
			pcall(function() lb.TextTransparency = 1 end)
			TS:Create(j, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.6, function() pcall(function() j:Destroy() end) end)
		end)
	end

	-- ===== the ARMADILLO EGG (desert/sandy) RISES UP out of the real hole -> Hatch prompt -> shared hatch flow =====
	local function spawnArmadilloEgg(atPos)
		if st.egg then return end
		st.eggPos = atPos; st.eggCaught = true
		local egg = Instance.new("Model"); egg.Name = petId.."Egg"
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(224,194,148), nil)
		shell.Reflectance = 0.05
		local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Scale = Vector3.new(3.0,4.0,3.0); m.Parent = shell
		visual.PrimaryPart = shell
		for j = 1, 6 do local a = (j-1)*(2*math.pi/6); newPart(visual, "Speck", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(176,118,64), CFrame.new(math.sin(a)*1.2, (j%2==0 and 0.5 or -0.5), math.cos(a)*1.2)) end
		local eggCenter = atPos + Vector3.new(0, 1.7, 0)
		st.eggBaseCF = CFrame.new(eggCenter); st.eggVisual = visual
		local startCF = CFrame.new(atPos + Vector3.new(0, -3.4, 0)) -- start DOWN inside the dug hole...
		st.eggRising = true; visual:PivotTo(startCF)
		st.egg = egg; egg.Parent = Workspace; st.digProps[#st.digProps+1] = egg
		local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(235,205,150); hl.FillTransparency = 0.5; hl.OutlineColor = Color3.fromRGB(210,168,90); hl.Adornee = visual; hl.Parent = egg
		local hp = addPrompt(shell, "Hatch", "Armadillo Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end
		end)
		hp.Enabled = false -- can't hatch until it has fully risen out of the ground
		-- RISE: tween the egg UP out of the hole (a CFrame lerp via a NumberValue, since Models can't tween directly)
		task.spawn(function()
			local nv = Instance.new("NumberValue"); nv.Value = 0
			nv:GetPropertyChangedSignal("Value"):Connect(function() local t = nv.Value; pcall(function() visual:PivotTo(startCF:Lerp(st.eggBaseCF, t)) end) end)
			TS:Create(nv, TweenInfo.new(1.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
			task.wait(1.2); st.eggRising = false; pcall(function() nv:Destroy() end); hp.Enabled = true
		end)
		-- gentle bob (only AFTER it has risen + while not hatching)
		task.spawn(function() local t = 0
			while st.egg do t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching and not st.eggRising then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.28, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.1, 0)) end)
				end
				task.wait(0.05)
			end
		end)
		print("[Pet] armadillo egg rose out of the ground for "..player.Name)
	end

	-- ===== ARMADILLO TRAIL: low-poly PART dirt mounds dug ONE AT A TIME. Each E-tap = one swing that SHRINKS the
	-- mound away + bursts dirt + sound + camera kick (the prompt is on its own anchor so it RE-ARMS every swing).
	-- Fully digging a DECOY reveals JUNK + lays ARMADILLO TRACKS to the NEXT mound (which then appears); the final
	-- spot (BuriedEggSpot) reveals the egg. Spread across the island + done sequentially -> a ~3-minute hunt. =====
	local DIRT, DIRT2 = Color3.fromRGB(150,110,70), Color3.fromRGB(134,96,58)
	-- a LOW-POLY DIRT PILE: a few stacked, rotated square blocks tapering up into a faceted cone/pile -> reads as
	-- ONE angular pile of dirt (NOT stacked bubble-circles). Built around `pos`; digging shrinks the whole model.
	local function buildMound(pos)
		local m = Instance.new("Model"); m.Name = petId.."DigMound"
		local base
		for i, L in ipairs({
			{ w=5.4, h=1.3, y=0.65, yaw=0,  col=DIRT  },
			{ w=4.0, h=1.3, y=1.75, yaw=45, col=DIRT2 },
			{ w=2.7, h=1.2, y=2.75, yaw=20, col=DIRT  },
			{ w=1.5, h=1.1, y=3.6,  yaw=58, col=DIRT2 },
		}) do
			local p = newPart(m, "MoundLayer", Enum.PartType.Block, Vector3.new(L.w, L.h, L.w), L.col, CFrame.new(pos + Vector3.new(0, L.y, 0)) * CFrame.Angles(0, math.rad(L.yaw), 0), Enum.Material.Sand)
			if i == 1 then base = p end
		end
		m.PrimaryPart = base
		m.Parent = Workspace
		return m
	end
	-- ARMADILLO TRACKS: a line of little footprint marks (flat oval + 3 toe dots) on the ground from one mound
	-- toward the next, leading MOST of the way -- the cue the player follows to reach the next mound.
	local function spawnTracks(fromPos, toPos)
		if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then return end
		local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
		local dist = flat.Magnitude; if dist < 3 then return end
		local dir = flat.Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local n = math.clamp(math.floor(dist / 7), 4, 16) -- a footprint roughly every ~7 studs
		for k = 1, n do
			local frac = (k / (n + 1)) * 0.85 + 0.05 -- lead MOST of the way (stop short of the next mound)
			local p = fromPos + dir * (dist * frac)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character }; rp.IgnoreWater = true
			local hit = Workspace:Raycast(p + Vector3.new(0,14,0), Vector3.new(0,-90,0), rp)
			local y = hit and hit.Position.Y or p.Y
			local side = (k % 2 == 0) and 1 or -1
			local fp = Vector3.new(p.X, y + 0.08, p.Z) + right * (side * 0.7)
			local cf = CFrame.lookAt(fp, fp + dir)
			local foot = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.95,0.12,1.35), Color3.fromRGB(96,62,34), cf) -- flat oval print
			foot.Transparency = 1; st.digProps[#st.digProps+1] = foot
			for _, tx in ipairs({ -0.3, 0, 0.3 }) do -- 3 toe dots ahead -> armadillo-print look
				local toe = newPart(Workspace, petId.."Track", Enum.PartType.Ball, Vector3.new(0.26,0.1,0.26), Color3.fromRGB(80,52,28), cf * CFrame.new(tx, 0, -0.72))
				toe.Transparency = 1; st.digProps[#st.digProps+1] = toe
			end
			TS:Create(foot, TweenInfo.new(0.3), { Transparency = 0.1 }):Play()
		end
	end

	local spots = {}   -- [i] = { spot, mound, prompt } (or false if the marker position is missing)
	local activateStep -- forward-decl (doSwing advances the trail via this)

	for i, spot in ipairs(digSpots) do
		if typeof(spot.pos) ~= "Vector3" then
			warn("[Pet][DIAG] dig spot "..spot.label.." position MISSING for "..petId)
			spots[i] = false
		else
			local mound = buildMound(spot.pos); setVisible(mound, false) -- built hidden; shown when this step is active
			st.digProps[#st.digProps+1] = mound
			-- the "Dig" prompt rides on its OWN persistent anchor, so shrinking/hiding the mound never removes it
			-- (BUGFIX kept) -> it re-arms every E-press (HoldDuration 0 -> one swing per press) until fully dug.
			local promptAnchor = newPart(Workspace, petId.."DigPrompt", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(spot.pos + Vector3.new(0,1.5,0)))
			promptAnchor.Transparency = 1; st.digProps[#st.digProps+1] = promptAnchor
			local swings, fxAnchor, em, snd, done = 0, nil, nil, nil, false
			local prompt -- forward-decl so doSwing can disable it on the final swing
			local function doSwing()
				if not fxAnchor then
					fxAnchor = newPart(Workspace, petId.."DigFX", Enum.PartType.Ball, Vector3.new(1,1,1), Color3.fromRGB(120,84,52), CFrame.new(spot.pos + Vector3.new(0,0.6,0)))
					fxAnchor.Transparency = 1
					em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/smoke_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(150,110,70), Color3.fromRGB(110,78,46)); em.Lifetime = NumberRange.new(0.4,0.85)
					em.Speed = NumberRange.new(10,18); em.SpreadAngle = Vector2.new(40,40); em.EmissionDirection = Enum.NormalId.Top
					em.Acceleration = Vector3.new(0,-44,0); em.Size = NumberSequence.new(0.9); em.Rate = 0; em.Rotation = NumberRange.new(0,360); em.Parent = fxAnchor
					snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://9114065998"; snd.Volume = 0.55; snd.Parent = fxAnchor -- PLACEHOLDER dirt/shovel dig sound -- swap freely
				end
				swings = swings + 1
				pcall(function() mound:ScaleTo(math.max(0.06, 1 - swings / N_SWINGS)) end) -- SHRINK the low-poly mound away one step (the part-based dig)
				pcall(function() em:Emit(20) end)                              -- DIRT burst this swing
				pcall(function() snd.TimePosition = 0; snd:Play() end)         -- dig SOUND this swing
				pcall(function()                                               -- small camera kick for feel
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then hum.CameraOffset = Vector3.new((math.random()-0.5)*0.5, -0.35, 0); TS:Create(hum, TweenInfo.new(0.18), {CameraOffset = Vector3.zero}):Play() end
				end)
				print(string.format("[Pet][DIG] swing %d/%d on %s", swings, N_SWINGS, spot.label))
				if swings < N_SWINGS then -- WIND-UP: the prompt goes quiet while the shovel comes back up
					prompt.Enabled = false
					task.delay(SWING_COOLDOWN, function() -- same gate activateStep uses; a finished/owned mound stays off
						if not done and not st.owns and not st.eggCaught then prompt.Enabled = true end
					end)
				end
				if swings >= N_SWINGS then -- mound fully dug -> reveal + advance the trail
					done = true; prompt.Enabled = false
					pushQuestProg(petId, { started = true, found = ((localQuestProg[petId] and localQuestProg[petId].found) or 0) + 1, total = #digSpots }) -- HUD: "Mounds X/6"
					pcall(function() setVisible(mound, false) end)
					if em then task.delay(0.4, function() em.Enabled = false end) end
					if fxAnchor then game:GetService("Debris"):AddItem(fxAnchor, 1.2) end
					if spot.real then
						print("[Pet][DIG] BuriedEggSpot dug -> EGG rises")
						pcall(function() PetDigEvent:FireServer(petId) end) -- server unlocks the claim (anti-cheat gate)
						pushQuestProg(petId, { complete = true }) -- HUD: armadillo quest complete
						setStatus("You unearthed the armadillo egg! \xF0\x9F\xA5\x9A"); task.delay(2.6, hideStatus)
						spawnArmadilloEgg(spot.pos)
					else
						local junk = DIG_JUNK[math.random(1, #DIG_JUNK)]
						junkRise(spot.pos, junk)
						local nextSpot = digSpots[i+1]
						local nextPos = nextSpot and nextSpot.pos
						local nextLabel = (nextSpot and nextSpot.label) or "?"
						if nextPos then spawnTracks(spot.pos, nextPos) end
						print(string.format("[Pet][DIG] %s dug -> junk (%s), tracks spawned toward %s", spot.label, junk, nextLabel))
						setStatus("You dug up: "..junk.."! Follow the tracks..."); task.delay(2.6, hideStatus)
						task.delay(0.4, function() activateStep(i + 1) end)
					end
				end
			end
			prompt = addPrompt(promptAnchor, "Dig", "Dig Spot", function() -- each E-tap = ONE swing (HoldDuration 0 -> per-press)
				if st.owns or st.eggCaught or done then return end
				if not st.hasShovel then floatText(spot.pos + Vector3.new(0,3,0), "Grab a shovel first!"); return end
				doSwing()
			end)
			prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12; prompt.Enabled = false -- enabled by activateStep when this is the active mound
			spots[i] = { spot = spot, mound = mound, prompt = prompt }
			print(string.format("[Pet][DIAG] built trail mound %s (step %d/%d, real=%s) at (%.0f,%.0f,%.0f)", spot.label, i, #digSpots, tostring(spot.real), spot.pos.X, spot.pos.Y, spot.pos.Z))
		end
	end

	-- show + enable the active step's mound (one at a time); skip any step whose marker position is missing
	activateStep = function(n)
		if n > #digSpots then return end
		local e = spots[n]
		if not e then return activateStep(n + 1) end
		st.digStep = n -- remembered so the accept-gate can restore the trail to exactly this step
		setVisible(e.mound, true)
		if not st.owns and not st.eggCaught then e.prompt.Enabled = true end
		print(string.format("[Pet][DIG] active mound: %s (trail step %d/%d)", e.spot.label, n, #digSpots))
	end
	if not st.owns then activateStep(1) end -- start the Armadillo Trail at the first mound

	print(string.format("[Pet][DIAG] burrito dig ready: shovel=%s buriedegg=%s", shovelPos and "yes" or "no", buriedPos and "yes" or "no"))
	-- avoid a flash of the props for someone who already OWNS the armadillo
	if st.owns then for _, o in ipairs(st.digProps) do setVisible(o, false) end end
end

-- ============================================================================================
-- BROCCOLI PULL MINIGAME (questType "find" -- Broccoli Bluff, the FIRST pet quest). THREE TUGS: the
-- broccoli wiggles in the dirt, the button says PULL, you tap it. Three taps and it is out. That is the
-- whole game -- there is no timer, no meter to read, no way to lose and nothing to let go of.
--
-- ===== WHY IT IS THIS SIMPLE, AND WHAT IT REPLACED =====
-- Broccoli Bluff is island 2, so this is the very first minigame anybody meets, played by a young kid who
-- has had the controls for about two minutes. It used to be a HOLD/RELEASE rhythm against a STALK STRAIN
-- meter: holding filled the uproot bar AND filled the strain bar, and redlining the strain "slipped" the
-- stalk, took 6% of your progress back and locked the button out for half a second.
--
-- Read that from a six-year-old's seat. The only control you have makes one bar good and another bar bad,
-- nothing on screen tells you where the line is, and the punishment for guessing wrong is that the button
-- stops responding. They hold it down -- which is what "HOLD TO PULL" says to do -- slip, lose ground,
-- and decide the game is broken. Three pieces of that, ~10s each, before the quest pays anything.
--
-- So the mechanic is now call-and-response: the game asks, you answer, something big happens, three times.
--   * ONE input. Tap. No hold, no aim, no timing window -- it waits for you forever.
--   * ONE piece of state, and it is a PICTURE, not a bar: three root pips, and the broccoli itself climbing
--     a third of the way out of the soil on every tug.
--   * NO fail state. Progress only ever goes up. The X is still the only way out.
-- What was kept: the dirt scene, the roots tearing free one at a time, the world broccoli reacting behind
-- the panel, and the pop at the end -- all the parts that made pulling it up feel good, none of the parts
-- that made it a test.
--
-- The other two quests are untouched and still play differently (coconut = tap-spam against a drain,
-- film reel = a timing meter). This one being the plain one is the point: it is the tutorial.
local PULL_TUGS = 3          -- taps to uproot a piece. Same 3 as the root pips -- they ARE the counter.

local pullUI, pullBusy = nil, false
local function ensurePullUI()
	if pullUI then return pullUI end
	local ui = mgCard("BroccoliPullGui", 360, 330, "PULL IT UP!", "Tap PULL 3 times!")
	local panel, titl, hintL = ui.panel, ui.title, ui.hint

	-- the little DIRT SCENE: sky, a soil band with a grass lip, and the broccoli rising out from BEHIND the
	-- soil (soil ZIndex > broccoli ZIndex) as each tug lands. Clipped so it truly emerges from the ground.
	-- KEEP THE 116 HEIGHT / 48 SOIL BAND: the tug animation's pixel offsets are tuned against them.
	local scene = Instance.new("Frame"); scene.Size = UDim2.new(1,-28,0,116); scene.Position = UDim2.new(0,14,0,MG_BODY_TOP)
	scene.BackgroundColor3 = Color3.fromRGB(126,190,240); scene.ClipsDescendants = true; scene.BorderSizePixel = 0; scene.Parent = panel
	mgCorner(scene, 12); mgStroke(scene, MG.navy, 2, 0.45)
	mgGrad(scene, Color3.fromRGB(158,212,248), Color3.fromRGB(112,178,236))
	-- Y OFFSETS (from the scene bottom; negative = up). It starts DOWN IN THE SOIL with only the crown
	-- showing and finishes with the whole broccoli sitting just clear of the dirt line -- it is being
	-- uprooted, not launched, so it never travels up into the sky.
	local brocc = Instance.new("TextLabel"); brocc.Size = UDim2.new(0,74,0,74); brocc.AnchorPoint = Vector2.new(0.5,1)
	brocc.Position = UDim2.new(0.5,0,1,4); brocc.BackgroundTransparency = 1; brocc.Font = Enum.Font.GothamBold
	brocc.TextSize = 58; brocc.Text = "\xF0\x9F\xA5\xA6"; brocc.ZIndex = 2; brocc.Parent = scene
	local soil = Instance.new("Frame"); soil.Size = UDim2.new(1,0,0,48); soil.Position = UDim2.new(0,0,1,-48)
	soil.BackgroundColor3 = Color3.fromRGB(96,64,40); soil.BorderSizePixel = 0; soil.ZIndex = 3; soil.Parent = scene
	local grass = Instance.new("Frame"); grass.Size = UDim2.new(1,0,0,7); grass.Position = UDim2.new(0,0,0,0)
	grass.BackgroundColor3 = Color3.fromRGB(96,182,86); grass.BorderSizePixel = 0; grass.ZIndex = 4; grass.Parent = soil
	for k = 1, 6 do -- a few dirt specks so the soil band isn't a flat rectangle
		local d = Instance.new("Frame"); d.Size = UDim2.new(0,6,0,6); d.Position = UDim2.new((k-0.5)/6, math.random(-14,14), 0, 12 + math.random(0,22))
		d.BackgroundColor3 = Color3.fromRGB(74,48,28); d.BorderSizePixel = 0; d.ZIndex = 4; d.Parent = soil
		Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
	end

	-- 3 ROOT pips: one lights gold per tug. This is the ONLY progress readout on the card now -- three
	-- lights and a broccoli climbing out of a hole, which a player who cannot read yet can still follow.
	local rootCap = Instance.new("TextLabel"); rootCap.Size = UDim2.new(1,-28,0,14); rootCap.Position = UDim2.new(0,14,0,MG_BODY_TOP+122)
	rootCap.BackgroundTransparency = 1; rootCap.Font = Enum.Font.GothamBold; rootCap.TextSize = 11; rootCap.TextColor3 = MG.ice
	rootCap.TextXAlignment = Enum.TextXAlignment.Left; rootCap.Text = "ROOTS"; rootCap.Parent = panel
	local roots = {}
	for k = 1, PULL_TUGS do
		local r = Instance.new("Frame"); r.Size = UDim2.new(0,100,0,16); r.Position = UDim2.new(0.5,(k-2)*106,0,MG_BODY_TOP+138)
		r.AnchorPoint = Vector2.new(0.5,0); r.BackgroundColor3 = MG.navy; r.BorderSizePixel = 0; r.Parent = panel
		mgCorner(r, 8); mgStroke(r, MG.trough, 2, 0.35); mgGloss(r)
		roots[k] = r
	end

	local pullBtn = Instance.new("TextButton"); pullBtn.Size = UDim2.new(0,258,0,66); pullBtn.Position = UDim2.new(0.5,0,1,-18)
	pullBtn.AnchorPoint = Vector2.new(0.5,1); pullBtn.BackgroundColor3 = Color3.fromRGB(60,180,80); pullBtn.Text = "PULL!"
	pullBtn.Font = Enum.Font.FredokaOne; pullBtn.TextSize = 30; pullBtn.TextColor3 = MG.white; pullBtn.AutoButtonColor = false; pullBtn.Parent = panel
	mgCorner(pullBtn, 14); mgStroke(pullBtn, MG.white, 3); mgGloss(pullBtn)

	pullUI = { gui = ui.gui, panel = ui.holder, scene = scene, brocc = brocc, soil = soil, roots = roots,
	           btn = pullBtn, close = ui.close, hint = hintL, title = titl }
	return pullUI
end

-- hooks (optional) let the 3D broccoli in the world react: hooks.update(progress) once per tug,
-- hooks.snap() on each tug, hooks.pop() on the last one. onPulled runs only on a full uproot.
-- info (optional) = { num = which broccoli this is (1-based), total = how many in the quest } -- shown as
-- "Broccoli 1 of 3" so the popup answers "how much more of this is there?" without being asked.
local function openPullMinigame(onPulled, info, hooks)
	if pullBusy then return end
	pullBusy = true
	local ui = ensurePullUI()
	hooks = hooks or {}
	info = info or {}
	local UIS = game:GetService("UserInputService")
	local TS  = game:GetService("TweenService")

	local tugs, done = 0, false
	-- The subtitle is the ONE line of text on the card, so it says where you are in the quest, not how to
	-- play -- the button already says PULL and the pips already show three of them.
	ui.hint.Text = (info.num and info.total) and ("Broccoli " .. info.num .. " of " .. info.total)
		or "Tap PULL 3 times!"
	ui.title.Text = "PULL IT UP!"
	ui.brocc.Position = UDim2.new(0.5,0,1,4); ui.brocc.Rotation = 0 -- back down in the soil
	for _, r in ipairs(ui.roots) do r.BackgroundColor3 = Color3.fromRGB(15,40,90) end
	ui.btn.BackgroundColor3 = Color3.fromRGB(60,180,80); ui.btn.Text = "PULL!"; ui.btn.TextSize = 30
	ui.gui.Enabled = true

	local conns = {}
	local function finish(success)
		if done then return end
		done = true
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		ui.gui.Enabled = false; pullBusy = false
		if success then onPulled() else pcall(function() if hooks.reset then hooks.reset() end end) end -- bailed out: drop the world broccoli back in its hole
	end

	-- ONE TUG. Every tap runs this and every tap moves the broccoli -- there is no state where a press
	-- does nothing, which is the failure mode that made the old version read as broken.
	local function tug()
		if done or tugs >= PULL_TUGS then return end
		tugs = tugs + 1
		local progress = tugs / PULL_TUGS
		ui.roots[tugs].BackgroundColor3 = Color3.fromRGB(255,205,60)
		-- 44px of total travel: buried (+4) -> whole broccoli resting on the dirt line (-40). No further.
		local y = 4 - math.floor(progress * 44)
		pcall(function()
			TS:Create(ui.brocc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 1, y), Rotation = 0 }):Play()
		end)
		ui.brocc.Rotation = (tugs % 2 == 0) and 8 or -8 -- a yank to one side, tweened straight again
		-- the broccoli itself pops bigger for a beat -- a hit you can see. NOT a nudge of the card: mgCard
		-- positions the panel by pixel offset, so tweening its Position to a scale value (what the old slip
		-- shake did) throws the whole card down the screen and back.
		pcall(function()
			TS:Create(ui.brocc, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
				{ TextSize = 70 }):Play()
		end)
		pcall(function() if hooks.snap then hooks.snap() end end)             -- dirt burst in the world
		pcall(function() if hooks.update then hooks.update(progress) end end)
		if _G.hapticPulse then pcall(_G.hapticPulse, "coin") end
		if tugs >= PULL_TUGS then
			ui.title.Text = "GOT IT!"; ui.hint.Text = "Broccoli uprooted!"
			ui.btn.Text = "POP!"; ui.btn.BackgroundColor3 = Color3.fromRGB(255,205,60)
			pcall(function() if hooks.pop then hooks.pop() end end)
			task.delay(0.5, function() finish(true) end)
		else
			ui.hint.Text = (tugs == PULL_TUGS - 1) and "One more!" or "Again!"
		end
	end

	conns[#conns+1] = ui.btn.MouseButton1Click:Connect(tug)
	conns[#conns+1] = UIS.InputBegan:Connect(function(input, gpe) -- keyboard: SPACE or E is a tug too
		if done or gpe then return end -- gpe = typing in chat; don't pull
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then tug() end
	end)
	conns[#conns+1] = ui.close.MouseButton1Click:Connect(function() finish(false) end) -- X only (a backdrop tap never closes it)

	-- IDLE WIGGLE: while the card is open and unfinished the broccoli jiggles and the button breathes, so
	-- something on screen is always asking to be tapped. It is the only "attract" the card has now that
	-- there are no meters moving -- and a still screen is what a stuck player stares at.
	task.spawn(function()
		while not done do
			if tugs < PULL_TUGS then
				pcall(function()
					TS:Create(ui.brocc, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true),
						{ Rotation = (math.random() < 0.5) and -5 or 5 }):Play()
					TS:Create(ui.btn, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true),
						{ Size = UDim2.new(0, 272, 0, 70) }):Play()
				end)
			end
			task.wait(1.1)
		end
	end)
end

-- Lock a built model into ONE rigid piece: every BasePart anchored AND WeldConstraint'd to the model's
-- root part. Anchored alone already holds them in place, but the weld means that if anything ever
-- unanchors a part (an event, a stray physics touch) the model still travels as a single object instead
-- of collapsing into loose bits on the floor. PivotTo the model afterwards moves the whole unit.
local function lockModel(model, root)
	root = root or model.PrimaryPart
	if not root then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root; w.Part1 = d; w.Parent = root
			end
		end
	end
end

-- The DIRT PATCH each broccoli piece is planted in: a squat mound, a ring of clods and a couple of leaf
-- tufts poking out of the soil, so a piece reads as "growing here", not "floating here". Kept SMALLER
-- than the broccoli that sits in it -- an oversized mound made the florets read as junk on the ground.
-- Returns the model + its mound part (used as the dirt-FX anchor).
local function buildDirtPatch(pos)
	local patch = Instance.new("Model"); patch.Name = "DirtPatch"
	local mound = newPart(patch, "Mound", Enum.PartType.Ball, Vector3.new(3.4, 1.2, 3.4), Color3.fromRGB(94, 63, 38), CFrame.new(pos + Vector3.new(0, -0.3, 0)), Enum.Material.Ground)
	patch.PrimaryPart = mound
	for k = 1, 7 do -- clods scattered around the rim
		local a = (k-1) * (2*math.pi/7) + math.random() * 0.5
		local r = 1.2 + math.random() * 0.45
		newPart(patch, "Clod", Enum.PartType.Ball, Vector3.new(0.6, 0.42, 0.6), Color3.fromRGB(76, 50, 30),
			CFrame.new(pos + Vector3.new(math.cos(a) * r, -0.12, math.sin(a) * r)), Enum.Material.Ground)
	end
	for k = 1, 4 do -- flat leaf tufts fanning out of the soil (the "there's something planted here" cue)
		local a = (k-1) * (2*math.pi/4) + 0.6
		local leaf = newPart(patch, "Leaf", Enum.PartType.Block, Vector3.new(1.3, 0.14, 0.55), Color3.fromRGB(104, 168, 72),
			nil, Enum.Material.Grass)
		leaf.CFrame = CFrame.new(pos + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0.8, 0, 0) * CFrame.Angles(0, 0, math.rad(16))
	end
	lockModel(patch, mound)
	return patch, mound
end

-- Build the pieces + egg for a pet from SERVER-PROVIDED positions (the client never searches Workspace).
-- positions = { pieces = { [i]=Vector3 }, egg = Vector3 }. Pieces/egg start hidden; PetStateEvent reveals
-- the uncollected pieces (when !owns) and the egg (when found==total).
local function buildPetWorld(petId, def, positions)
	local st = petState[petId]
	if st.built then return end
	positions = positions or {}
	if def.questType == "crack" then return buildCoconutWorld(petId, def, positions) end -- coconut quest has its own world
	if def.questType == "film-reels" then return buildPopcornWorld(petId, def, positions) end -- popcorn quest has its own world
	if def.questType == "fishing" then return buildButterWorld(petId, def, positions) end -- butter duck quest has its own world
	if def.questType == "dig" then return buildBurritoWorld(petId, def, positions) end -- burrito armadillo dig quest has its own world
	st.built = true
	local pieces = positions.pieces or {}
	-- 3 collectible pieces (built at the received coordinates), each PLANTED in a dirt patch: the prompt
	-- opens the PULL minigame (~15s) instead of handing the piece over on a single E-tap.
	for i = 1, #def.pieceMarkers do
		-- ONE PIECE MUST NEVER TAKE THE REST DOWN WITH IT. st.built is set above, before any of this runs, so a
		-- single error mid-loop used to leave a HALF-BUILT world permanently: piece 3 and the EGG never got built
		-- and nothing would ever retry them -- an uncompletable quest that looks like "only some broccoli showed
		-- up". Per-piece pcall: a piece that fails is reported by name and the others still appear.
		local okPiece, errPiece = pcall(function()
		local pos = pieces[i]
		if typeof(pos) == "Vector3" then
			-- container: dirt patch (static) + the broccoli blob (rises out of the soil as you pull).
			-- ONE model so setVisible()/applyState keeps toggling exactly one thing per piece.
			local piece = Instance.new("Model"); piece.Name = "BroccoliPatch"..i
			local patch, mound = buildDirtPatch(pos)
			patch.Parent = piece
			-- ONE whole broccoli standing in the mound (stalk buried, crown clearly above the dirt). It is
			-- welded into a single rigid unit so it reads as a plant, never as loose florets on the floor.
			local blob = buildBroccoliBlob(0.85, false); blob.Name = "Blob"; blob.Parent = piece
			local baseCF = CFrame.new(pos + Vector3.new(0, 0.35, 0)) -- stalk base sits in the mound, crown proud of it
			blob:PivotTo(baseCF)
			lockModel(blob, blob.PrimaryPart)
			piece.PrimaryPart = mound

			-- dirt FX anchor (built lazily on the first burst, cleaned up with the piece)
			local dirtEm
			local function dirtBurst(n)
				if not dirtEm then
					local a = Instance.new("Attachment"); a.Name = "DirtFX"; a.Position = Vector3.new(0, 0.8, 0); a.Parent = mound
					local em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/smoke_main.dds"
					em.Color = ColorSequence.new(Color3.fromRGB(150,110,70), Color3.fromRGB(110,78,46)); em.Lifetime = NumberRange.new(0.4,0.85)
					em.Speed = NumberRange.new(8,15); em.SpreadAngle = Vector2.new(45,45); em.EmissionDirection = Enum.NormalId.Top
					em.Acceleration = Vector3.new(0,-44,0); em.Size = NumberSequence.new(0.8); em.Rate = 0; em.Rotation = NumberRange.new(0,360); em.Parent = a
					dirtEm = em
				end
				pcall(function() dirtEm:Emit(n or 14) end)
			end

			-- LATE GROUND-SNAP: a marker part that sits a little UNDER the island surface (or a little above it)
			-- is exactly how a piece ends up buried in the mesh and looks like it never spawned. The island is
			-- usually not streamed in when we build, so we can't raycast yet -- wait until the player is actually
			-- near the piece, then drop a short ray and sit the whole patch flush on the ground. Runs once.
			task.spawn(function()
				while true do
					task.wait(1)
					if st.collected[i] or st.owns then return end
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - pos).Magnitude < 250 then
						local rp = RaycastParams.new()
						rp.FilterType = Enum.RaycastFilterType.Exclude
						rp.FilterDescendantsInstances = { piece, player.Character }
						local hit = Workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -36, 0), rp)
						if hit then
							local dy = hit.Position.Y - pos.Y
							if math.abs(dy) > 0.35 and not pullBusy then
								piece:PivotTo(piece:GetPivot() + Vector3.new(0, dy, 0))
								baseCF = baseCF + Vector3.new(0, dy, 0) -- keep the pull animation's rest pose in sync
								print(string.format("[Pet][DIAG] piece %d ground-snapped %.1f studs onto the island surface", i, dy))
							end
							return
						end
					end
				end
			end)

			addPrompt(blob.PrimaryPart, "Pull Up", (def.pieceLabel or "Pet"), function() -- no name-number: which piece doesn't matter
				if st.collected[i] or st.owns then return end
				if not _G.petQuestGate(def, pos) then return end -- the Grower has to hand you this first
				-- WHICH broccoli this is out of how many, counted BEFORE the pull so the card can say
				-- "Broccoli 2 of 3" while you are pulling it -- not the piece INDEX i, which is a marker
				-- id and jumps around depending on the order you find them in.
				local doneSoFar = 0; for _, v in pairs(st.collected) do if v then doneSoFar = doneSoFar + 1 end end
				openPullMinigame(function()
					if st.collected[i] or st.owns then return end
					st.collected[i] = true -- track WHICH pieces (index = dedup key); the same piece can't count twice
					-- DISPLAYED number = how many DISTINCT pieces collected so far (running total), NOT the piece index i
					local count = 0; for _, v in pairs(st.collected) do if v then count = count + 1 end end
					setVisible(piece, false) -- (the dirt burst already fired from the `pop` hook, while it was still visible)
					floatText(pos, (def.pieceLabel or "Pet").." piece "..count.."/"..#def.pieceMarkers.."!")
					pcall(function() PetCollectEvent:FireServer(petId, i) end) -- send the index so the server dedups by piece
				end, { num = doneSoFar + 1, total = #def.pieceMarkers }, {
					-- the REAL broccoli reacts behind the (semi-transparent) minigame panel: it jumps a third
					-- of the way out of the soil on every tug, with a little yank to one side.
					-- Called ONCE PER TUG now, not every frame (the old hold/release version drove this from a
					-- render loop). So the yank has to SETTLE itself: pivot with a tilt, then a moment later
					-- pivot to the clean lifted pose. Without the second pivot the broccoli would sit crooked
					-- in the dirt until the next tap.
					update = function(progress)
						local lift = progress * 0.85 -- just enough to clear the stalk from the mound, never airborne
						local yank = CFrame.new((math.random()-0.5)*0.22, 0, (math.random()-0.5)*0.22)
							* CFrame.Angles(0, 0, math.rad((math.random()-0.5)*10))
						blob:PivotTo(baseCF * CFrame.new(0, lift, 0) * yank)
						task.delay(0.16, function()
							if blob and blob.Parent then blob:PivotTo(baseCF * CFrame.new(0, lift, 0)) end
						end)
					end,
					snap  = function() dirtBurst(12) end,
					reset = function() blob:PivotTo(baseCF) end, -- closed the panel early: it settles back into the dirt
					pop   = function()
						dirtBurst(20)
						blob:PivotTo(baseCF * CFrame.new(0, 1.05, 0)) -- pops free and sits on the dirt, not in the sky
					end,
				})
			end).HoldDuration = 0.4 -- HOLD E to start the pull minigame (matches the other quests' openers)

			st.pieces[i] = piece
			setVisible(piece, false) -- hidden until PetStateEvent confirms !owns (avoids a flash for owners)
			print(string.format("[Pet][DIAG] built planted piece %d at (%.0f,%.0f,%.0f) with Pull Up prompt", i, pos.X, pos.Y, pos.Z))
		else
			warn("[Pet][DIAG] piece "..i.." position MISSING from server for "..petId.." -- that piece will NOT exist in the world (check the server's '[Pet] piece marker ... MISSING' warning)")
		end
		end)
		if not okPiece then
			warn("[Pet][DIAG] piece "..i.." for "..petId.." FAILED to build: "..tostring(errPiece)
				.." -- the remaining pieces and the egg were still built")
		end
	end
	-- EGG (ovoid) sitting in a twiggy NEST, built at the received coordinate; shown only when found==total.
	local eggPos = positions.egg
	if typeof(eggPos) == "Vector3" then
		st.eggPos = eggPos -- raw egg coordinate (for the quest pointer + landing-hint island anchor)
		local egg = Instance.new("Model"); egg.Name = petId.."Egg" -- CONTAINER (egg visual + nest -> one visibility toggle)

		-- NEST: low-poly brown twig ring/bowl the egg nestles into (STATIC -- does not bob).
		local nest = Instance.new("Model"); nest.Name = "Nest"; nest.Parent = egg
		local nestCenter = CFrame.new(eggPos + Vector3.new(0, 1.0, 0))
		for k = 1, 14 do
			local a = (k-1) * (2*math.pi/14)
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.2, 0.55, 0.55), Color3.fromRGB(105, 65, 38), nil, Enum.Material.SmoothPlastic)
			twig.CFrame = nestCenter * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.7) * CFrame.Angles(0, math.rad(90), math.rad(18))
		end
		for k = 1, 10 do -- a lower second layer for a bowl look
			local a = (k-1) * (2*math.pi/10) + 0.3
			local twig = newPart(nest, "Twig", Enum.PartType.Cylinder, Vector3.new(2.0, 0.5, 0.5), Color3.fromRGB(90, 55, 32), nil, Enum.Material.SmoothPlastic)
			twig.CFrame = nestCenter * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), math.rad(30))
		end

		-- EGG VISUAL: an ovoid (taller than wide, tapered top) with broccoli-green speckles. This sub-model
		-- BOBS and is what CRACKS on hatch (the nest stays put). PrimaryPart = the main shell.
		local visual = Instance.new("Model"); visual.Name = "Visual"; visual.Parent = egg
		-- ONE smooth egg ovoid (NOT two stacked spheres): a unit Part with a built-in Sphere SpecialMesh
		-- stretched taller-than-wide via a non-uniform Mesh.Scale -> a single continuous egg silhouette.
		local shell = newPart(visual, "Shell", Enum.PartType.Ball, Vector3.new(1, 1, 1), Color3.fromRGB(208, 232, 178), nil)
		shell.Reflectance = 0.06 -- slight gloss
		local eggMesh = Instance.new("SpecialMesh")
		eggMesh.MeshType = Enum.MeshType.Sphere
		eggMesh.Scale = Vector3.new(3.0, 4.2, 3.0) -- W x H x D: taller than wide = egg shape
		eggMesh.Parent = shell
		visual.PrimaryPart = shell
		-- broccoli-green speckles dusted around the single ovoid surface (x/z radius ~1.5, height ~2.1)
		for j = 1, 9 do
			local a = (j-1) * (2*math.pi/9)
			local y = math.sin(a*1.8) * 1.05 -- wander up/down the egg
			local r = 1.42 * math.sqrt(math.max(0, 1 - (y/2.1)^2)) + 0.04 -- hug the ovoid surface at this height
			newPart(visual, "Spot", Enum.PartType.Ball, Vector3.new(0.5,0.5,0.5), Color3.fromRGB(70, 150, 70),
				CFrame.new(math.sin(a)*r, y, math.cos(a)*r))
		end

		st.eggBaseCF = CFrame.new(eggPos + Vector3.new(0, 2.6, 0)) -- the egg sits IN the nest
		st.eggVisual = visual
		visual:PivotTo(st.eggBaseCF)
		st.egg = egg
		setVisible(egg, false)

		addPrompt(shell, "Hatch", (def.pieceLabel or "Pet").." Egg", function()
			if st.owns or st.hatching then return end
			if hatchEgg then hatchEgg(petId, def) end -- E -> hatch animation, THEN the claim registers
		end)

		-- gentle idle bob/wiggle for the EGG VISUAL only (paused during the hatch); the nest stays still
		task.spawn(function()
			local t = 0
			while st.egg do
				t = t + 0.05
				if st.egg.Parent and st.eggBaseCF and st.eggVisual and not st.hatching then
					pcall(function() st.eggVisual:PivotTo(st.eggBaseCF * CFrame.new(0, math.sin(t*3)*0.3, 0) * CFrame.Angles(0, math.sin(t*1.5)*0.12, math.rad(math.sin(t*2)*5))) end)
				end
				task.wait(0.05)
			end
		end)
		print(string.format("[Pet][DIAG] egg + nest built at (%.0f,%.0f,%.0f) (shows at 3/3)", eggPos.X, eggPos.Y, eggPos.Z))
	else
		warn("[Pet][DIAG] egg position MISSING from server for "..petId)
	end
end

-- ===== FOLLOWER PET (the key part: smooth follow, keeps up during fast flight) =====
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)  -- right, up, BEHIND (+Z) in the player's local frame
local FOLLOW_K      = 6    -- POSITION responsiveness (lower = softer, flowier glide -- was 12, now eased)
local FACE_K        = 4    -- FACING responsiveness (slower than FOLLOW_K so the pet SWINGS round to turn, not snap)
local MAX_TRAIL     = 45   -- never let the pet fall further than this behind -> can't be lost in a fast ascent
local petSmoothPos  = nil  -- smoothed follow position (no bob)
local petSmoothFwd  = nil  -- smoothed facing direction (eased -> graceful swing turns)
local bobT          = 0

-- ============================================================================================
-- ACCUMULATING PRESTIGE VISUALS (Stage 1 visual progression). PURELY COSMETIC -- every effect is Massless,
-- CanCollide=false, no physics/flight role. As a pet levels 1->50 it accumulates: a small CONTINUOUS color/
-- intensity creep EVERY level, plus STACKING milestone pieces -- 10 trail, 20 aura, 30 sparkles + slightly
-- bigger, 40 a themed accessory, 50 MAX (rainbow shimmer + biggest trail + max sparkles + GOLD accessory +
-- MAX badge). Themed per pet. Idempotent: clears + re-applies so equip and live level-ups refresh cleanly.
-- ============================================================================================
local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
-- per-pet UPGRADE theme: themed effect color (trail/aura/sparkles), per-location anchors in the pet's own model
-- space (head/face/neck/back/ear/side), glasses lens half-spread, and the EXACT accessory schedule (level ->
-- accessory key). The BASE PET IS NEVER MODIFIED -- only size, the listed effects, and these accessories are added.
local PET_THEME = {
	-- SECRET: Pizza Dragon (10/10 collection reward). Its wings are role "wing" (they flap, like the duck's) and its
	-- horns sit where other pets' ears do, so the accessory anchors line up with the standard schedule.
	PizzaDragon = { color=Color3.fromRGB(226,150,68),
		head=CFrame.new(-0.1,1.7,0), face=CFrame.new(1.5,0.7,0), glassW=0.5, neck=CFrame.new(1.25,-0.1,0), back=CFrame.new(-1.5,0.5,0), ear=CFrame.new(-0.15,1.9,0.62), side=CFrame.new(0.2,0.0,1.4),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	-- STARTER: Bean Buddy. Its sprout leaves are role "ear", so it reuses the bunny-style ear anchor.
	BeanBuddy = { color=Color3.fromRGB(126,200,86),
		head=CFrame.new(-0.1,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(-0.1,1.75,0.7), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	BroccoliPet = { color=Color3.fromRGB(120,210,70),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	CoconutCrab = { color=Color3.fromRGB(170,100,60),
		head=CFrame.new(-0.1,1.0,0), face=CFrame.new(0.92,0.78,0), glassW=0.4, neck=CFrame.new(0.7,0.05,0), back=CFrame.new(-0.85,0.45,0), side=CFrame.new(0,0.2,1.15), side2=CFrame.new(0,0.2,-1.15),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"piratehat"},{13,"backpack"},{17,"sword"},{20,"gemcluster"},{23,"anchor"} } },
	PopcornSheep = { color=Color3.fromRGB(248,244,230),
		head=CFrame.new(1.1,1.55,0), face=CFrame.new(1.65,0.4,0), glassW=0.45, neck=CFrame.new(1.1,-0.35,0), back=CFrame.new(-1.4,0.4,0), ear=CFrame.new(0.5,1.6,0.85), side=CFrame.new(0.3,-0.2,1.4),
		accs={ {3,"bell"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"cloudcluster"},{23,"crook"} } },
	ButterDuck = { color=Color3.fromRGB(250,205,75),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BurritoArmadillo = { color=Color3.fromRGB(200,160,110),
		head=CFrame.new(1.15,1.4,0), face=CFrame.new(1.5,0.8,0), glassW=0.45, neck=CFrame.new(1.2,0.15,0), back=CFrame.new(-1.5,0.35,0), side=CFrame.new(0.2,-0.1,1.5), side2=CFrame.new(0.2,-0.1,-1.5),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"safari"},{13,"backpack"},{17,"gemstuds"},{20,"lantern"},{23,"pickaxe"} } },
	-- SEASONAL PETS: reuse the standard body/head anchors so they get the same level scaling + accessory schedule.
	SunflowerBee = { color=Color3.fromRGB(250,205,60),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	MapleFox = { color=Color3.fromRGB(222,120,52),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.2,2.35,1.0), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
	FrostPenguin = { color=Color3.fromRGB(120,150,200),
		head=CFrame.new(0.15,1.6,0), face=CFrame.new(1.5,0.5,0), glassW=0.5, neck=CFrame.new(1.3,-0.3,0), back=CFrame.new(-1.4,0.4,0), side=CFrame.new(0.3,-0.3,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"monocle"},{20,"sparklecluster"},{23,"cane"} } },
	BlossomBunny = { color=Color3.fromRGB(186,224,150),
		head=CFrame.new(0.05,1.62,0), face=CFrame.new(1.5,0.45,0), glassW=0.5, neck=CFrame.new(1.25,-0.3,0), back=CFrame.new(-1.4,0.35,0), ear=CFrame.new(0.1,1.7,0.95), side=CFrame.new(0.2,-0.1,1.35),
		accs={ {3,"bowtie"},{7,"glasses"},{10,"crown"},{13,"backpack"},{17,"flower"},{20,"haloring"},{23,"staff"} } },
}
-- REBIRTH PETS (rebirth 3/6/10) are recolour-CLONES of Bean Buddy / Pizza Dragon / Maple Fox -- same bodies, same
-- anchor points -- so they reuse those themes. Without an entry they fall through applyLevelVisual's
-- `if not theme then return end` and lose their age SIZE ramp and their overhead name/age plate entirely.
-- Assignments, not new locals: this file is at Luau's 200-local ceiling (see the note above applyLevelVisual).
-- RemotePets.client.lua carries the identical three lines -- change one, change both.
PET_THEME.MoltenBean = PET_THEME.BeanBuddy
PET_THEME.VoidDragon = PET_THEME.PizzaDragon
PET_THEME.PrismFox   = PET_THEME.MapleFox
local petFX = {}         -- [pet] = animated effect state (orbs/ring/pulse/burst/shimmer) driven by the FX loop
-- RARE variant looks (Stage 2): body sheen (color/material/reflectance) + a rare-only sparkle aura. Cosmetic.
-- ===== RARE PET BRIGHTNESS =====
-- Rare variants read 30% dimmer than they used to. They were the brightest thing on screen -- glass/metal
-- body sheens, an 0.85-LightEmission sparkle aura and a Brightness-3 PointLight on top -- which is a lot of
-- glare to stand next to for the whole game.
--
-- Applied as ONE factor at the point of use rather than by editing the colours in RARE_LOOK, for two
-- reasons: the table stays readable as authored intent, and RemotePets carries an identical copy of both the
-- table and this code, so a single tunable in each is far harder to let drift than ten edited hex values.
-- Raise it back toward 1.0 to undo.
local RARE_DIM = 0.525 -- was 0.7; rare variants read 25% dimmer again (body, FX, light and the Cosmic cycle all scale off this one number). MUST match RemotePets' copy.
local function rareDim(c)
	return Color3.new(c.R * RARE_DIM, c.G * RARE_DIM, c.B * RARE_DIM)
end

local RARE_LOOK = {
	BroccoliPet      = { name="Emerald Bunny",    body=Color3.fromRGB(20,150,80),   mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(70,255,150) },                       -- emerald crystal sheen + green crystal sparkles
	CoconutCrab      = { name="Golden Crab",      body=Color3.fromRGB(255,200,40),  mat=Enum.Material.Metal,  refl=0.35, fx=Color3.fromRGB(255,225,90) },                        -- solid shiny gold + gold sparkles
	PopcornSheep     = { name="Cloud Sheep",      body=Color3.fromRGB(212,232,255), mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(225,242,255), puffs=true, light=true }, -- white-blue cloud sheen + cloud puffs + soft light
	BurritoArmadillo = { name="Crystal Armadillo",body=Color3.fromRGB(150,80,210),  mat=Enum.Material.Glass,  refl=0.25, fx=Color3.fromRGB(195,125,255) },                       -- amethyst crystal sheen + crystal-shard sparkles
	ButterDuck       = { name="Cosmic Duck",      body=Color3.fromRGB(30,24,66),    mat=Enum.Material.Plastic,refl=0.1,  fx=Color3.fromRGB(180,140,255), cosmic=true, light=true }, -- deep-space body + swirling stars + rainbow cosmic aura (showstopper)
}
-- ===== RARITY TIER LABELS (shared by the inventory card + the floating overhead label) =====
-- Normal pets: tier by LEVEL (Common->Legendary). Rare variants: special TOP tiers (Exotic, or Mythical for the
-- 1/10000 Cosmic Duck). Ranked by REAL odds: Mythical > Legendary > Exotic > Epic > ... Escalating colors;
-- Exotic/Mythical are the flashiest (glow) since they're variant LOOKS, not just level bands.
-- ===== AGE STAGES, NOT RARITY WORDS =====
-- This ladder used to say Common/Uncommon/Rare/Epic/Legendary -- the EXACT same words the skin
-- crates use for skin rarity, so a young pet wearing a Legendary-rarity skin read "Common Lv 3"
-- over its head. Levels are GROWTH (size + accessories), so the badge now says age: rarity
-- vocabulary belongs to crates alone. Colors kept, so the escalation players know still reads.
-- Rare hatch variants keep Exotic/Mythical -- those genuinely ARE rarity, not age.
-- NOTE: RemotePets.client.lua has an identical copy of this ladder for other players' pets --
-- change one and you must change the other.
local function petTier(level, isRare, petId)
	if isRare then
		if petId == "ButterDuck" then return "Mythical", Color3.fromRGB(255,70,230), true, true  -- top tier, flashiest (magenta glow)
		else return "Exotic", Color3.fromRGB(40,235,225), true, true end                          -- above everything (bright cyan/teal glow)
	end
	if level <= 5      then return "Baby",  Color3.fromRGB(175,180,190), false, false
	elseif level <= 10 then return "Kid",   Color3.fromRGB(90,210,90),   false, false
	elseif level <= 15 then return "Teen",  Color3.fromRGB(70,140,255),  false, false
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235),  false, false
	else                    return "Elder", Color3.fromRGB(255,170,40),  false, false end
end
local PET_DISPLAY = { BeanBuddy="Bean Buddy", PizzaDragon="Pizza Dragon", BroccoliPet="Broccoli Bunny", CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck", BurritoArmadillo="Burrito Armadillo",
	SunflowerBee="Sunflower Bee", MapleFox="Maple Fox", FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny",
	-- rebirth pets: without these three the plate read the raw id ("MoltenBean"). Names match the server catalog.
	MoltenBean="Molten Bean", VoidDragon="Void Dragon", PrismFox="Prism Fox" }
-- the name shown above a pet: the rare variant name if rare, else the normal display name.
local function petDisplayName(petId, isRare) return (isRare and RARE_LOOK[petId] and RARE_LOOK[petId].name) or PET_DISPLAY[petId] or petId end
local function flagAccPart(p) -- clean matte-plastic cosmetic flags (matches the pet style; never collides/affects physics)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
local accScale = 1
-- create one ACCESSORY part, WELD it into the pet's animation list (role "body" -> tracks the pet's bob/sway +
-- the size tier each frame; it can never float off). `cf` is object-space relative to the root. Returns the part.
local function accPart(pet, A, root, shape, sx, sy, sz, color, cf)
	local R = accScale
	local size = Vector3.new(sx*R, sy*R, sz*R)
	local bcf = CFrame.new(cf.Position * R) * (cf - cf.Position) -- scale offset, keep rotation
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=size; p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * bcf; p.Parent = pet
	A.parts[#A.parts+1] = { part=p, base=bcf, baseSize=size, role="body", eye=false }
	return p
end
-- create a free-standing EFFECT part (orbs/ring/pulse): parented to the pet but NOT animated by animatePet -- the
-- FX loop positions/scales it each frame. Glowing (Neon) when `neon`. Massless/CanCollide=false (no flight impact).
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
-- Build ONE accessory by key, welded onto the pet (base pet untouched), at the right per-pet anchor for its
-- location. GOLD-trimmed when `gold` (lvl 25 MAX). Builds EXACTLY the listed parts -- nothing extra.
local function buildAccessoryByKey(pet, A, root, theme, key, gold)
	if key == "bowtie" then                 -- two wings + a center knot, at the neck
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		accPart(pet,A,root, BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then            -- two round lens frames over the eyes (no bridge)
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "monocle" then            -- a single round lens over one eye
		local f = theme.face; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		accPart(pet,A,root, CYL_, 0.12,0.46,0.46, c, f * CFrame.new(0,0,(theme.glassW or 0.5)))
	elseif key == "bell" then               -- a collar band + a round bell, around the neck
		local collar = gold and PRESTIGE_GOLD or Color3.fromRGB(170,45,55)
		local bell   = gold and PRESTIGE_GOLD or Color3.fromRGB(212,176,80)
		accPart(pet,A,root, CYL_, 1.5,0.22,0.22, collar, theme.neck * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BAL_, 0.42,0.46,0.42, bell, theme.neck * CFrame.new(0.05,-0.34,0))
	elseif key == "scarf" then              -- a scarf band around the neck + a hanging end
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		accPart(pet,A,root, CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,A,root, BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "backpack" then           -- a pack box + two straps, on the back
		local b = theme.back; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(120,90,58)
		accPart(pet,A,root, BLK_, 0.65,0.8,0.9, c, b)
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.55,0.12,0.16, gold and Color3.fromRGB(225,185,70) or Color3.fromRGB(88,64,40), b * CFrame.new(0.5,0.12,0.42*sgn)) end
	elseif key == "flower" then             -- 5 petals + a center, tucked by one ear
		local e = theme.ear; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); accPart(pet,A,root, BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		accPart(pet,A,root, BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sword" then              -- a small cutlass (handle + guard + blade), on the shell side
		local s = theme.side; local blade = gold and PRESTIGE_GOLD or Color3.fromRGB(200,205,215)
		accPart(pet,A,root, BLK_, 0.16,0.28,0.16, Color3.fromRGB(90,60,38), s)                       -- handle
		accPart(pet,A,root, BLK_, 0.34,0.12,0.12, gold and PRESTIGE_GOLD or Color3.fromRGB(205,170,70), s * CFrame.new(0,0.16,0)) -- guard
		accPart(pet,A,root, BLK_, 0.14,1.0,0.14, blade, s * CFrame.new(0,0.7,0))                      -- blade (up)
	elseif key == "crown" then              -- band + 5 prongs, on top of the head
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(212,182,66)
		accPart(pet,A,root, CYL_, 0.16,1.05,1.05, c, h * CFrame.Angles(0,0,math.rad(90)))
		for i=0,4 do local ang=math.rad(i*72); accPart(pet,A,root, CYL_, 0.5,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.42, 0.3, math.cos(ang)*0.42) * CFrame.Angles(0,0,math.rad(90))) end
	elseif key == "piratehat" then          -- brim + crown + front trim, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(34,34,40)
		accPart(pet,A,root, BAL_, 1.5,0.45,1.15, c, h)
		accPart(pet,A,root, BAL_, 0.95,0.78,0.85, c, h * CFrame.new(-0.05,0.45,0))
		accPart(pet,A,root, CYL_, 1.0,0.2,0.2, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(225,185,70), h * CFrame.new(0.45,0.05,0) * CFrame.Angles(0,math.rad(90),0))
	elseif key == "tophat" then             -- brim + crown + band, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		accPart(pet,A,root, CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "safari" then             -- wide brim + shallow crown + band, on top
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(156,138,96)
		accPart(pet,A,root, CYL_, 0.12,1.5,1.5, c, h * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BAL_, 0.95,0.66,0.95, c, h * CFrame.new(0,0.34,0))
		accPart(pet,A,root, CYL_, 0.2,0.92,0.92, gold and Color3.fromRGB(255,225,90) or Color3.fromRGB(110,92,60), h * CFrame.new(0,0.12,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "haloring" then           -- BUNNY: a glowing ring of beads above the head
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90)
		for i=0,9 do local ang=math.rad(i*36); local p=accPart(pet,A,root, BAL_, 0.16,0.16,0.16, c, h * CFrame.new(math.sin(ang)*0.6, 0.85, math.cos(ang)*0.6)); p.Material=Enum.Material.Neon end
	elseif key == "staff" then              -- BUNNY: a side scepter (shaft + glowing orb top)
		local s = theme.side
		accPart(pet,A,root, CYL_, 1.7,0.14,0.14, Color3.fromRGB(120,84,46), s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BAL_, 0.42,0.42,0.42, gold and PRESTIGE_GOLD or Color3.fromRGB(150,235,90), s * CFrame.new(0,1.3,0)); p.Material=Enum.Material.Neon
	elseif key == "anchor" then             -- CRAB: a tiny anchor on the other shell side (shaft + crossbar + flukes)
		local s = theme.side2 or theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.0,0.14,0.14, c, s * CFrame.new(0,0.2,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.6,0.14,0.14, c, s * CFrame.new(0,0.6,0) * CFrame.Angles(math.rad(90),0,0))
		for _,sgn in ipairs({1,-1}) do accPart(pet,A,root, BLK_, 0.4,0.14,0.14, c, s * CFrame.new(0.18*sgn,-0.2,0) * CFrame.Angles(0,0,math.rad(40*sgn))) end
	elseif key == "gemcluster" then         -- CRAB: a cluster of glowing gem studs on the shell top
		local cols = { Color3.fromRGB(95,215,205), Color3.fromRGB(120,180,255), Color3.fromRGB(235,225,205) }
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.3,0.3,0.3, gold and PRESTIGE_GOLD or cols[(k%3)+1], CFrame.new(-0.35+k*0.28, 0.95, -0.1+(k%2)*0.3)); p.Material=Enum.Material.Neon end
	elseif key == "crook" then              -- SHEEP: a side shepherd's-crook (shaft + hook)
		local s = theme.side; local c = Color3.fromRGB(150,110,64)
		accPart(pet,A,root, CYL_, 1.8,0.14,0.14, c, s * CFrame.new(0,0.4,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.5,0.13,0.13, c, s * CFrame.new(-0.18,1.35,0) * CFrame.Angles(0,0,math.rad(35)))
		accPart(pet,A,root, CYL_, 0.4,0.13,0.13, c, s * CFrame.new(-0.42,1.18,0) * CFrame.Angles(0,0,math.rad(80)))
	elseif key == "cloudcluster" then       -- SHEEP: a small cluster of cloud puffs above
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,255,255)
		for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.45,0.4,0.45, c, h * CFrame.new(math.sin(ang)*0.5, 0.8, math.cos(ang)*0.5)) end
	elseif key == "sparklecluster" then     -- DUCK: a small cluster of glowing butter sparkles
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.55, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then               -- DUCK: a side cane (shaft + J handle)
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		accPart(pet,A,root, CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	elseif key == "gemstuds" then           -- ARMADILLO: a row of glowing gem studs on the shell
		for k=0,3 do local p=accPart(pet,A,root, BAL_, 0.26,0.26,0.26, gold and PRESTIGE_GOLD or Color3.fromRGB(120,200,210), CFrame.new(-0.7+k*0.5, 1.6, 0)); p.Material=Enum.Material.Neon end
	elseif key == "lantern" then            -- ARMADILLO: a tiny glowing lantern at the side
		local s = theme.side; local frame = gold and PRESTIGE_GOLD or Color3.fromRGB(90,72,46)
		accPart(pet,A,root, CYL_, 0.16,0.1,0.1, frame, s * CFrame.new(0,0.55,0) * CFrame.Angles(0,0,math.rad(90)))
		local p=accPart(pet,A,root, BLK_, 0.5,0.6,0.5, Color3.fromRGB(255,225,110), s); p.Material=Enum.Material.Neon
		accPart(pet,A,root, BLK_, 0.6,0.12,0.6, frame, s * CFrame.new(0,-0.34,0))
	elseif key == "pickaxe" then            -- ARMADILLO: a tiny pickaxe on the other shell side
		local s = theme.side2 or theme.side; local wood = Color3.fromRGB(120,84,46); local head = gold and PRESTIGE_GOLD or Color3.fromRGB(150,154,164)
		accPart(pet,A,root, CYL_, 1.3,0.13,0.13, wood, s * CFrame.new(0,0.3,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,A,root, BLK_, 0.9,0.16,0.16, head, s * CFrame.new(0,0.85,0) * CFrame.Angles(0,0,math.rad(18)))
	end
end
-- clear ALL added parts + effects (accessories, emitters, lights, trail, orbs/ring/pulse/burst) so a re-apply
-- (equip / level-up) is clean (idempotent). The BASE PET parts are never touched.
local function clearEvo(pet, A)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" or n=="PetRareFX" or n=="PetRareLight" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" then c:Destroy() end
	end
	if A then for i = #A.parts, 1, -1 do if A.parts[i].part and A.parts[i].part.Name == "EvoPart" then A.parts[i].part:Destroy(); table.remove(A.parts, i) end end end
	petFX[pet] = nil
end
-- build the animated EFFECT parts (orbs/ring/pulse/burst) for `level` into petFX[pet]; the FX loop animates them.
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25),
		orbR=2.0, orbH=0.45, ringR=2.2, ringY=0.3, ringTilt=22 }
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0) -- ORBS: 1@11, 2@14, 3@19
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then -- RING: a glowing energy ring of 8 beads, spinning on a tilted circle
		for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end
	end
	if level >= 18 then -- PULSE: an expanding-fading ring burst
		fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2)
	end
	if level >= 24 then -- BURST: periodic ambient particle burst
		local b = Instance.new("ParticleEmitter"); b.Name="PetBurst"; b.Color=ColorSequence.new(col)
		b.Rate=0; b.Lifetime=NumberRange.new(0.4,0.8); b.Speed=NumberRange.new(4,9); b.Size=NumberSequence.new(0.5)
		b.LightEmission=0.8; b.Rotation=NumberRange.new(0,360); b.Parent=root; fx.burst=b
	end
	petFX[pet] = fx
end
-- RARE-only look (Stage 2): a body sheen (color/material/reflectance) + a rare sparkle aura (+ cloud puffs / soft
-- light / cosmic rainbow). Applied ON TOP of the pre-maxed visuals. Eyes + accessories + leveling FX are left as-is.
local function applyRareLook(pet, A, root, petId)
	local r = RARE_LOOK[petId]; if not r then return end
	for _, d in ipairs(pet:GetDescendants()) do          -- (1) body sheen (skip eyes / accessories / leveling FX)
		if d:IsA("BasePart") and d ~= root then
			local n = d.Name
			if n~="Eye" and n~="Highlight" and n~="EvoPart" and n~="PetOrb" and n~="PetRing" and n~="PetPulse" then
				d.Color = rareDim(r.body); d.Material = r.mat; d.Reflectance = r.refl
			end
		end
	end
	local rfx = Instance.new("ParticleEmitter"); rfx.Name="PetRareFX"; rfx.Color=ColorSequence.new(rareDim(r.fx)); rfx.LightEmission=0.85*RARE_DIM*0.75
	rfx.Rate = r.cosmic and 65 or 32; rfx.Lifetime = NumberRange.new(0.6,1.2); rfx.Rotation = NumberRange.new(0,360)
	rfx.Speed = NumberRange.new(r.cosmic and 1.4 or 0.5, r.cosmic and 3.2 or 1.4); rfx.Size = NumberSequence.new(r.cosmic and 0.45 or 0.4)
	rfx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); rfx.Parent = root
	if r.light then local pl = Instance.new("PointLight"); pl.Name="PetRareLight"; pl.Color=rareDim(r.fx); pl.Brightness=3*RARE_DIM*0.75; pl.Range=12; pl.Parent=root end -- SAME as RemotePets' rare light, so your rare pet shines like the ones you see on others
	if r.puffs and A then for k=0,3 do local ang=math.rad(k*90); accPart(pet,A,root, BAL_, 0.55,0.5,0.55, Color3.fromRGB(255,255,255), CFrame.new(math.sin(ang)*1.6, 0.7, math.cos(ang)*1.6)) end end
	if r.cosmic and petFX[pet] then petFX[pet].cosmic = true end -- the FX loop rainbow-cycles the rare light + stars
end
-- (Body-evolution REMOVED: the base pet's own parts are never modified. Upgrades = accessories + size + effects.)

-- `lite` (used by the menu/trade ICON clones): build ONLY size + accessories + rare body recolor; SKIP every
-- particle/highlight/trail/light/billboard FX (they don't render usefully in a static ViewportFrame icon and
-- were only being created then stripped). This keeps the per-icon build cheap so many maxed/rare icons can't
-- spike the frame / exhaust execution time.
local function applyLevelVisual(pet, level, petId, isRare, lite)
	if not pet then return end
	level = level or 1
	local root = pet.PrimaryPart
	local A = petAnims[pet]
	local theme = PET_THEME[petId] or PET_THEME[pet.Name]
	if not theme then
		-- No upgrade theme (Bean Buddy / Pizza Dragon / the seasonals) -- but a SKIN + TRAIT still applies to
		-- every pet, so paint it before bailing out. Guarded: PetSkinLook.client defines this.
		if _G.applyPetSkinLook then pcall(_G.applyPetSkinLook, pet, petId, lite) end
		return -- only the 5 known pets have upgrade visuals
	end
	if isRare then level = 25 end -- RARE pets display PRE-MAXED (full lvl-25 look) regardless of stored level
	local MAXL = 25
	local frac = math.clamp((level - 1) / (MAXL - 1), 0, 1) -- 0 at Lv1 -> 1 at Lv25
	local atMax = (level >= MAXL)
	local prevLevel = A and A.lastVisualLevel or nil
	accScale = 1
	clearEvo(pet, A) -- removes ONLY the added effects + EvoPart accessories; the BASE PET is never touched
	-- ===== LEVEL FX: MUST STAY ON, BECAUSE EVERY OTHER PLAYER'S PET HAS THEM =====
	-- RemotePets.client.lua (which draws every OTHER player's pet on this screen) runs this exact ladder
	-- unconditionally. While this was false, your own pet was the ONLY plain pet in the server: you saw
	-- everyone else's aura/trail/sparkles/orbs/ring/pulse and had none of it yourself, which reads as
	-- "my pet is broken". The two renderers must agree -- if you ever retire the level particle stack,
	-- retire it in RemotePets in the SAME commit.
	local LEVEL_FX = true
	-- (1) SIZE: 60% at Lv1 -> 100% at Lv25 (+1.667%/level) -- the guaranteed visible change every level. (popMul = level-up bounce)
	if A then A.sizeMul = 0.6 + 0.4 * frac end
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	-- (2) AURA: appears at Lv2; brightens each level. BOLD = a bright themed Highlight glow + a PointLight + soft particles.
	if LEVEL_FX and level >= 2 and root and not lite then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor = theme.color; hl.OutlineColor = theme.color
		hl.FillTransparency = math.clamp(0.8 - 0.45*t, 0, 1); hl.OutlineTransparency = math.clamp(0.4 - 0.4*t, 0, 1)
		hl.Parent = pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=(2.5+4*t)*0.75; pl.Range=8+8*t; pl.Parent=root -- SAME as RemotePets: your pet must not glow dimmer than everyone else's
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	-- (3) TRAIL: appears at Lv5; lengthens/brightens each level. BOLD = long, wide, bright themed trail.
	if LEVEL_FX and level >= 5 and root and not lite then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color = ColorSequence.new(theme.color); tr.LightEmission = 0.6; tr.Lifetime = 0.5 + 1.1*t
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35 - 0.3*t, 0, 1)), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = root
	end
	-- (4) SPARKLES: appear at Lv8; density up each level. BOLD = dense themed sparkle particles.
	if LEVEL_FX and level >= 8 and root and not lite then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"
		pe.Rate = 14 + 90*t; pe.LightEmission = 0.7; pe.Rotation = NumberRange.new(0,360)
		pe.Lifetime = NumberRange.new(0.5, 1.0); pe.Speed = NumberRange.new(0.6, 1.6); pe.Size = NumberSequence.new(0.34)
		pe.Color = ColorSequence.new(theme.color)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) })
		pe.Parent = root
	end
	-- (5) ANIMATED EFFECTS: orbs (11/14/19), energy ring (15), pulse (18), burst (24) -- built into petFX, animated by the FX loop.
	if LEVEL_FX and root and not lite then buildFX(pet, root, theme, level, atMax) end
	-- (6) ACCESSORIES: the per-pet list, each at its exact level (3/7/10/13/17/20/23), accumulating. GOLD trim at MAX.
	if A and root then
		for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, A, root, theme, e[2], atMax) end end
	end
	-- (7) RARE: pre-maxed (above) + the unique rare body sheen/aura on top.
	if isRare and root then applyRareLook(pet, A, root, petId) end
	-- TIER BADGE (overhead): pet NAME + a colored TIER badge. Normal = Common->Legendary by level (+ "Lv N");
	-- rare variants = Exotic, or Mythical for the Cosmic Duck (no level). Colors escalate; Exotic/Mythical glow.
	if root and not lite then
		local bb = root:FindFirstChild("LevelTag")
		if not bb then
			-- NAMEPLATE SIZE: ~72% of what it was (200x42 -> 144x30, name 16pt -> 12, badge 11pt -> 9). It was
			-- big enough to be the loudest thing on screen and to cover the pet it was labelling. StudsOffset
			-- drops with it (3.7 -> 3.4) so the smaller plate still sits just above the pet's head instead of
			-- floating with a gap under it.
			-- NOTE: RemotePets.client.lua builds an IDENTICAL LevelTag for OTHER players' pets. Change one and you
			-- must change the other, or your pet and everyone else's are labelled at different sizes.
			bb = Instance.new("BillboardGui"); bb.Name="LevelTag"; bb.Size=UDim2.new(0,144,0,30)
			bb.StudsOffset=Vector3.new(0,3.4,0); bb.AlwaysOnTop=true; bb.Parent=root
			local lbl = Instance.new("TextLabel"); lbl.Name="L"; lbl.Size=UDim2.new(1,0,0,14); lbl.Position=UDim2.new(0,0,0,0); lbl.BackgroundTransparency=1
			lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=12; lbl.Parent=bb; Instance.new("UIStroke").Parent=lbl
			local tg = Instance.new("TextLabel"); tg.Name="Tag"; tg.AnchorPoint=Vector2.new(0.5,0); tg.Position=UDim2.new(0.5,0,0,16)
			tg.AutomaticSize=Enum.AutomaticSize.X; tg.Size=UDim2.new(0,0,0,12); tg.Font=Enum.Font.GothamBold; tg.TextSize=9; tg.TextColor3=Color3.new(1,1,1); tg.Parent=bb
			local pad=Instance.new("UIPadding", tg); pad.PaddingLeft=UDim.new(0,4); pad.PaddingRight=UDim.new(0,4)
			Instance.new("UICorner", tg).CornerRadius=UDim.new(0,4); Instance.new("UIStroke", tg)
		end
		local tierName, tierColor, isVariant, flashy = petTier(level, isRare, petId)
		-- SKIN RARITY joins the badge: "Baby Epic  Lv 3" -- age from the level, rarity from the
		-- EQUIPPED SKIN, colored by the skin's tier so rarity reads at a glance. petSkinRarityOf
		-- lives in PetSkinLook (it owns the equipped state and the PetSkins table); nil when no
		-- skin is worn, so an unskinned pet shows age alone exactly as before. Exotic/Mythical
		-- variants keep their own badge -- that name outranks any skin.
		if not isVariant and _G.petSkinRarityOf then
			local okS, skTier, skCol = pcall(_G.petSkinRarityOf, petId)
			if okS and skTier then
				tierName = tierName .. " " .. tostring(skTier)
				if skCol then tierColor = skCol end
			end
		end
		bb.L.Text = petDisplayName(petId, isRare)
		bb.L.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
		bb.Tag.Text = isVariant and tierName or (tierName .. "  Age " .. tostring(level))
		bb.Tag.BackgroundColor3 = tierColor
		local stk = bb.Tag:FindFirstChildOfClass("UIStroke")
		if stk then
			if flashy then -- Exotic/Mythical: thin CLEAN border on the badge EDGE (not a thick text halo) -> readable
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stk.Color = Color3.fromRGB(255,255,255); stk.Thickness = 1; stk.Transparency = 0.2
			else -- normal tiers: unchanged (thin dark text outline)
				stk.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; stk.Color = Color3.fromRGB(0,0,0); stk.Thickness = 1; stk.Transparency = 0.35
			end
		end
	end
	-- (7) LEVEL-UP POP: every live level-up -> a tiny scale-pop + a one-shot sparkle burst (feedback).
	local leveledUp = prevLevel and level > prevLevel
	if leveledUp then
		if A then A.popClock = 0.4 end
		if root then
			local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
			burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
			burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root
			burst:Emit(20)
			game:GetService("Debris"):AddItem(burst, 1.1)
		end
	end
	if A then A.lastVisualLevel = level end
	-- SKIN + TRAIT go on LAST, after clearEvo and every level effect, so a repaint can never be stripped by the
	-- evolution pass. Placed BEFORE the `lite` return so inventory/trade icon clones show the skin too. Guarded:
	-- PetSkinLook.client defines this and owns its own cleanup, so calling it repeatedly is safe.
	if _G.applyPetSkinLook then pcall(_G.applyPetSkinLook, pet, petId, lite) end
	if lite then return end -- icon clones: size + accessories + rare recolor only; skip the level-up pop + diagnostics
	-- DIAGNOSTICS
	local nAcc = 0; for _, e in ipairs(theme.accs) do if level >= e[1] then nAcc = nAcc + 1 end end
	local nOrb = (level>=11 and 1 or 0)+(level>=14 and 1 or 0)+(level>=19 and 1 or 0)
	print(string.format("[PetEvo] %s Lvl %d: size %d%%, aura %s, trail %s, sparkles %s, orbs %d, ring %s, pulse %s, burst %s, accessories %d, shimmer %s",
		pet.Name, level, math.floor((0.6 + 0.4*frac)*100),
		(level>=2) and "on" or "off", (level>=5) and "on" or "off", (level>=8) and "on" or "off",
		nOrb, (level>=15) and "on" or "off", (level>=18) and "on" or "off", (level>=24) and "on" or "off", nAcc, atMax and "on" or "off"))
	if leveledUp then
		local added = "size"
		if level==2 then added="aura" elseif level==5 then added="trail" elseif level==8 then added="sparkles"
		elseif level==11 or level==14 or level==19 then added="floating orb" elseif level==15 then added="energy ring"
		elseif level==18 then added="pulse" elseif level==24 then added="burst" elseif atMax then added="MAX: gold trim + shimmer" end
		for _, e in ipairs(theme.accs) do if e[1] == level then added = "accessory ("..tostring(e[2])..")" end end
		print(string.format("[PetEvo] %s level-up %d -> added %s", pet.Name, level, added))
	end
end
-- FX LOOP: animate each active pet's orbs (orbit), energy ring (spin), pulse (expand+fade), burst (periodic emit),
-- and the MAX shimmer (cycle aura/trail/orb/ring colors). One Heartbeat connection for all pets.
do
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		for pet, fx in pairs(petFX) do
			local root = pet.Parent and pet.PrimaryPart
			if root then
				fx.t = fx.t + dt
				local t = fx.t
				local rootCF = root.CFrame
				local sm = (petAnims[pet] and petAnims[pet].sizeMul) or 1
				local n = #fx.orbs
				for i, orb in ipairs(fx.orbs) do
					local a = t*1.7 + (i-1)*(2*math.pi/math.max(1,n))
					orb.CFrame = rootCF * CFrame.new(math.cos(a)*fx.orbR*sm, fx.orbH*sm, math.sin(a)*fx.orbR*sm)
				end
				for _, seg in ipairs(fx.ring) do
					local a = t*1.9 + seg.base
					seg.part.CFrame = rootCF * CFrame.new(0, fx.ringY*sm, 0) * CFrame.Angles(math.rad(fx.ringTilt),0,0) * CFrame.new(math.cos(a)*fx.ringR*sm, 0, math.sin(a)*fx.ringR*sm)
				end
				if fx.pulse then
					local ph = (t % 1.3) / 1.3
					fx.pulse.Size = fx.pulseBase * (1 + ph*2.2) * sm
					fx.pulse.Transparency = math.clamp(ph, 0, 1)
					fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
				end
				if fx.burst then
					fx.burstClock = fx.burstClock - dt
					if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end
				end
				if fx.cosmic then -- COSMIC DUCK rare: vivid rainbow cycle on the rare light + star sparkles
					local cc = Color3.fromHSV((t * 0.4) % 1, 0.7, 1)
					-- Dimmed like the static rare colours are. Without this the Cosmic Duck would rewrite
					-- its light and sparkles to FULL brightness every frame and be the one rare pet the
					-- 30% reduction never touched -- and it is the brightest of the five to begin with.
					local dimCc = rareDim(cc)
					local rl = root:FindFirstChild("PetRareLight"); if rl then rl.Color = dimCc end
					local rfx = root:FindFirstChild("PetRareFX"); if rfx then rfx.Color = ColorSequence.new(dimCc) end
				end
				if fx.shimmer then
					-- SUBTLE rainbow sheen: cycle a gentle hue (lower saturation/value) and keep the Highlight FILL
					-- nearly transparent so it reads as a soft sheen ON the pet, NOT a bright wash that hides it.
					local hue = (t * 0.25) % 1
					local c = Color3.fromHSV(hue, 0.45, 0.9)
					local hl = pet:FindFirstChild("LevelGlow")
					if hl then
						hl.OutlineColor = c; hl.OutlineTransparency = 0.25 -- a thin rainbow edge sheen (doesn't cover the body)
						hl.FillColor = c; hl.FillTransparency = 0.88       -- very light fill so the pet's features stay clearly visible
					end
					local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
					for _, orb in ipairs(fx.orbs) do orb.Color = c end
					for _, seg in ipairs(fx.ring) do seg.part.Color = c end
				end
			else
				petFX[pet] = nil
			end
		end
	end)
end

-- Every pet now clones its SERVER-FUSED union template (smooth gap-free body). The client part-cluster
-- builders are kept only as FALLBACKS if a template hasn't replicated (so a pet always appears).
local PET_TEMPLATE_NAME = {
	BeanBuddy        = "BeanBuddyTemplate",       -- starter (free on first join)
	PizzaDragon      = "PizzaDragonTemplate",     -- SECRET 10/10 collection reward
	BroccoliPet      = "BroccoliBunnyTemplate",
	CoconutCrab      = "CoconutCrabTemplate",
	PopcornSheep     = "PopcornSheepTemplate",
	ButterDuck       = "ButterDuckTemplate",
	BurritoArmadillo = "BurritoArmadilloTemplate",
	SunflowerBee     = "SunflowerBeeTemplate",   -- seasonal (Summer)
	MapleFox         = "MapleFoxTemplate",        -- seasonal (Autumn)
	FrostPenguin     = "FrostPenguinTemplate",    -- seasonal (Winter)
	BlossomBunny     = "BlossomBunnyTemplate",    -- seasonal (Spring)
	MoltenBean       = "MoltenBeanTemplate",      -- REBIRTH 3 reward  (recoloured Bean Buddy)
	VoidDragon       = "VoidDragonTemplate",      -- REBIRTH 6 reward  (recoloured Pizza Dragon)
	PrismFox         = "PrismFoxTemplate",        -- REBIRTH 10 reward (recoloured Maple Fox)
}
local PET_FALLBACK = {
	CoconutCrab      = buildCoconutCrab,
	PopcornSheep     = buildPopcornSheep,
	ButterDuck       = buildButterDuck,
	BurritoArmadillo = buildBurritoArmadillo,
	BroccoliPet      = buildBroccoliDinoFallback,
}
local function buildPetModel(petId)
	local tn = PET_TEMPLATE_NAME[petId]
	-- WAIT LONGER THAN 4s FOR THE TEMPLATE. This is called during the busiest second of the join -- the server
	-- is unioning 14 pet bodies, positioning 14 islands and building the garden, all while this client is
	-- still streaming in -- and 4s was enough on a fast connection and not on a slow one. Timing out doesn't
	-- fail loudly, it silently drops to PET_FALLBACK... which has NO BeanBuddy entry, so it lands on
	-- buildBroccoliDinoFallback and hands a brand-new player a broccoli dino named BeanBuddy as their first
	-- pet. 15s costs nothing when the template is already there (FindFirstChild returns instantly, and it
	-- normally is) and covers a slow join properly.
	local template = tn and (RS:FindFirstChild(tn) or RS:WaitForChild(tn, 15))
	if template then
		local clone = template:Clone(); clone.Name = petId
		if registerClonedTemplate(clone) then
			print("[Pet][UNION] cloned server template "..tn.." for "..petId.." (smooth fused body)")
			return clone
		end
		clone:Destroy()
	end
	warn("[Pet][UNION] "..petId.." template missing -- using client-built fallback")
	local fb = PET_FALLBACK[petId]
	local fallback = (fb and fb(0.9)) or buildBroccoliDinoFallback(0.9)
	-- match the server pets: force every fallback PET part to clean matte plastic + Smooth faces (no Lego-stud/
	-- notch texture). Pet-only -- this never touches quest props (they use their own newPart elsewhere).
	if fallback then
		local SM = Enum.SurfaceType.Smooth
		for _, d in ipairs(fallback:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Transparency < 1 then d.Material = Enum.Material.Plastic end -- keep invisible roots untouched
				d.TopSurface = SM; d.BottomSurface = SM; d.LeftSurface = SM
				d.RightSurface = SM; d.FrontSurface = SM; d.BackSurface = SM
			end
		end
	end
	return fallback
end
-- Exposed for SkinCrateClient, which needs real pet models for its crate-reel and reveal thumbnails.
-- An assignment, NOT a `local` -- this file is at Luau's 200-registers-per-scope ceiling.
_G.petBuildModel = buildPetModel

local function spawnFollowerPet(petId)
	local st = petState[petId]
	-- `and st.pet.Parent` MATTERS. st.pet holds a reference to a DESTROYED model just as happily as a live
	-- one, and a destroyed Instance is still truthy -- so the old test made this return early for a pet that
	-- no longer exists in the world, and the self-heal watchdog below (which detects exactly that case and
	-- calls this function to fix it) could never actually fix anything. It only ever healed the case where
	-- st.pet was nil. With the Parent check the reference is treated as stale and a fresh model is built.
	if st.pet and st.pet.Parent then -- already following: just refresh the visual if the level OR the rare flag changed
		if st.appliedLevel ~= st.level or st.appliedRare ~= st.rare then
			st.appliedLevel = st.level; st.appliedRare = st.rare; applyLevelVisual(st.pet, st.level or 1, petId, st.rare)
		end
		return
	end
	local qt = PETS[petId] and PETS[petId].questType
	if qt == "seasonal" or qt == "starter" or qt == "collection" then
		print("[PetFollow] building "..qt.." "..(PETS[petId].displayName or petId).." follower")
	end
	st.pet = buildPetModel(petId)
	st.pet.Name = petId
	-- ===== SHOW IT ONLY ONCE IT IS WHOLE =====
	-- A union body renders in stages: the parts appear, then the fused solid resolves, then its colours and
	-- the face on top of it. Parent it straight to Workspace and the first thing a brand-new player sees of
	-- their free pet is it assembling itself in mid-air -- and applyLevelVisual (accessories, aura, size
	-- tier) lands on top of that, so it flickers twice.
	--
	-- LocalTransparencyModifier, not Transparency: this is a purely local "don't draw yet" that the pet's own
	-- transparency values are read back out of untouched. Writing Transparency here would fight applyLevelVisual
	-- and permanently flatten the deliberately-invisible root part and the semi-transparent aura pieces.
	local hidden = {}
	for _, d in ipairs(st.pet:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = 1; hidden[#hidden + 1] = d end
	end
	st.pet.Parent = Workspace
	st.appliedLevel = st.level; st.appliedRare = st.rare
	applyLevelVisual(st.pet, st.level or 1, petId, st.rare)
	task.spawn(function()
		-- PreloadAsync yields until the model's assets (union meshes, any textures) are actually resolved,
		-- which is the real "is it renderable yet" signal. Then one frame so the first draw includes
		-- everything applyLevelVisual just added, and it fades up whole.
		pcall(function() ContentProvider:PreloadAsync({ st.pet }) end)
		RunService.RenderStepped:Wait()
		local shown = 0
		for _, d in ipairs(hidden) do
			if d.Parent then d.LocalTransparencyModifier = 0; shown = shown + 1 end
		end
		-- Anything applyLevelVisual added while we were hidden was never in `hidden`, so it drew normally --
		-- only the body needed holding back. Clear the modifier on the whole model to be certain nothing
		-- stays ghosted if a part was re-parented mid-build.
		for _, d in ipairs(st.pet:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
		print(("[Pet][DIAG] %s revealed fully rendered (%d body part(s) held until the model was ready)")
			:format(petId, shown))
	end)
	print("[Pet][DIAG] pet spawned, following player ("..petId..") at Lv "..tostring(st.level or 1))
end

-- FULL EVO RE-RUN for every live follower. PetSkinLook calls this when the server pushes a new
-- equip state: equipping a trait must strip the level particle stack NOW (and unequipping must
-- bring it back NOW) -- without this, the applyLevelVisual gate only re-evaluates on the next
-- level-up or respawn, and the two effect systems visibly overlap until then. On _G, not a
-- local: this file sits at the edge of Luau's 200-locals ceiling.
_G.petEvoRefresh = function()
	for petId, st in pairs(petState) do
		if st.pet and st.pet.Parent then
			pcall(applyLevelVisual, st.pet, st.level or 1, petId, st.rare)
		end
	end
end

-- Despawn the follower (used when a pet is UNEQUIPPED). Cosmetic-only.
local function despawnFollowerPet(petId)
	local st = petState[petId]
	if st and st.pet then
		petFX[st.pet] = nil -- stop the FX loop tracking this pet before it's destroyed
		petAnims[st.pet] = nil
		pcall(function() st.pet:Destroy() end)
		st.pet = nil; st.appliedLevel = nil
		print("[Pet][DIAG] pet despawned (unequipped) ("..petId..")")
	end
end

-- ===== PET ANIMATION (idle + movement). Drives the sub-parts as LOCAL offsets around the root, so the
-- root keeps following the player (this NEVER moves the root -- it only re-poses children each frame).
-- Role-based: the head bobs/nods, the tail wiggles, the legs do a gait swing, the eyes blink, and the
-- whole pet does a gentle idle float + a Crossy-Road hop when moving. Modular: any pet whose builder
-- registers parts with body/head/tail/leg roles + an eye flag animates for free.
local function pivotRotate(pivot, rot) -- rotate about a local pivot point (not the part's own centre)
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end
local function animatePet(model, dt)
	local A = petAnims[model]; if not A then return end
	local root = model.PrimaryPart; if not (root and root.Parent) then return end
	local rootCF = root.CFrame
	local s = A.s
	A.t = A.t + dt
	local t = A.t
	-- LEVEL-UP POP: a quick cosmetic scale-bounce (1 -> ~1.25 -> 1 over ~0.4s) whenever applyLevelVisual sets
	-- A.popClock on a level-up, so EVERY level-up is instantly, visibly rewarding. Purely visual.
	A.popMul = 1
	if A.popClock and A.popClock > 0 then
		A.popClock = math.max(0, A.popClock - dt)
		A.popMul = 1 + 0.25 * math.sin(math.pi * (1 - A.popClock / 0.4))
	end
	-- MOVING? measure the root's HORIZONTAL speed (ignore the ambient vertical bob) and smooth it to 0..1.
	local pos = rootCF.Position
	if A.lastPos then
		local d = pos - A.lastPos
		local sp = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
		local target = math.clamp(sp / (26 * s), 0, 1)
		A.move = A.move + (target - A.move) * math.clamp(dt * 5, 0, 1)
	end
	A.lastPos = pos
	local mv = A.move
	-- GLOBAL (local frame: +X = front): SOFT slow breathing bob (idle) + a gentle slow bob when moving + a
	-- forward lean. Lean = pitch the front (+X) down -> rotate about the lateral Z axis, pivoted at the centre.
	-- (Soft sine, low frequency/amplitude -- no fast abs-sine jackhammer, so the motion is flowy, not jittery.)
	local bobY = math.sin(t * 1.5) * 0.06 * s + math.sin(t * (3.0 + 1.5 * mv)) * 0.09 * s * mv
	-- a gentle whole-body sway (yaw + roll) keeps the pet alive as ONE unit -- important once the body is a
	-- single fused union (which can no longer sway its neck/tail independently). Applied to every part.
	local swayY = math.rad(3) * math.sin(t * 0.8)
	local swayZ = math.rad(2) * math.sin(t * 1.1)
	local globalT = CFrame.new(0, bobY, 0) * pivotRotate(Vector3.new(0, 0, 0), CFrame.Angles(0, swayY, -math.rad(13) * mv + swayZ))
	-- HEAD: a little Y bob + idle nod (pitch about Z) + side glance (yaw about Y), small dip when moving,
	-- pivoted at the neck (between body centre and the head at +X).
	local headBob = math.sin(t * 1.7 + 0.5) * 0.05 * s + math.sin(t * (8 + 4 * mv)) * 0.05 * s * mv
	local headRot = CFrame.Angles(0, math.rad(8) * math.sin(t * 0.6), 0) * CFrame.Angles(0, 0, math.rad(5) * math.sin(t * 1.1) - math.rad(7) * mv)
	local headT = CFrame.new(0, headBob, 0) * pivotRotate(Vector3.new(1.2 * s, 0.6 * s, 0), headRot) -- pivot at the NECK BASE so the long neck sways
	-- TAIL: side-to-side sway (yaw about Y), pivoted where it meets the body back (-X).
	local tailRot = pivotRotate(Vector3.new(-1.5 * s, 0, 0), CFrame.Angles(0, math.sin(t * (2.2 + 3 * mv)) * (math.rad(14) + math.rad(16) * mv), 0))
	-- BLINK: quick eye squash every ~2-5s (random) so it feels natural.
	A.blink = A.blink - dt
	local eyeY = 1
	if A.blink <= 0 then
		local since = -A.blink
		if since < 0.16 then
			eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1)) -- close then open
		else
			A.blink = 1.8 + math.random() * 3.4 -- schedule the next blink
		end
	end
	-- Apply per part: each block keeps its clean local placement (bp = base) + a role transform
	-- (head bob / tail wiggle / leg gait) + the global hop/lean. Blocks stay snapped (no scale = no gaps).
	for _, e in ipairs(A.parts) do
		local bp = e.base
		local localCF
		if e.role == "head" then
			localCF = globalT * headT * bp
		elseif e.role == "tail" then
			localCF = globalT * tailRot * bp
		elseif e.role == "leg" then
			-- diagonal gait: front-left + back-right swing together, opposite pair anti-phase. Legs swing
			-- fore/aft (in X) -> rotate about the lateral Z axis, pivoted at the hip (body underside).
			local bx, bz = e.base.Position.X, e.base.Position.Z
			local phase = ((bx >= 0) == (bz >= 0)) and 0 or math.pi
			local swing = math.rad(18) * mv * math.sin(t * (9 + 3 * mv) + phase)
			localCF = globalT * pivotRotate(Vector3.new(bx, -0.7 * s, bz), CFrame.Angles(0, 0, swing)) * bp
		elseif e.role == "ear" then
			-- EARS (bunny/sheep): gentle floppy wiggle -- rock fore/aft (about Z) + a touch of side splay
			-- (about X), pivoted at the EAR BASE (down at the head top) so the tip swings, not the whole ear.
			local bzs = e.base.Position.Z >= 0 and 1 or -1
			local flop = math.rad(7) * math.sin(t * 1.6) + math.rad(9) * mv * math.sin(t * (7 + 2 * mv))
			local splay = math.rad(5) * math.sin(t * 1.3 + bzs) * bzs
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y - 1.0 * s, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, 0, flop) * CFrame.Angles(splay, 0, 0)) * bp
		elseif e.role == "wing" then
			-- WINGS (duck): flap up/down -- rotate about the fore/aft X axis, pivoted at the INNER edge
			-- (where the wing meets the body, toward Z=0) so the outer tip lifts. Idle = slow settle.
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local flap = (math.rad(10) + math.rad(26) * mv) * math.sin(t * (3 + 9 * mv)) * sgn
			local pv = Vector3.new(e.base.Position.X, e.base.Position.Y, e.base.Position.Z - 1.0 * s * sgn)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(flap, 0, 0)) * bp
		elseif e.role == "claw" then
			-- CLAWS/legs (crab): scuttle -- a quick small open/close yaw (about Y) + tiny tilt, pivoted at the
			-- shoulder (toward the body, lower X). Left/right anti-phase so it looks like a busy little crab.
			local sgn = e.base.Position.Z >= 0 and 1 or -1
			local sc = (math.rad(6) + math.rad(10) * mv) * math.sin(t * (5 + 6 * mv) + (sgn > 0 and 0 or math.pi))
			local pv = Vector3.new(e.base.Position.X - 0.8 * s, e.base.Position.Y, e.base.Position.Z)
			localCF = globalT * pivotRotate(pv, CFrame.Angles(0, sc * sgn, sc * 0.5)) * bp
		else
			localCF = globalT * bp
		end
		-- COSMETIC SIZE TIER (lvl >=30): scale every part's offset-from-root + its size uniformly, so the whole
		-- pet grows about its root. sm==1 (levels <30) keeps the EXACT original behavior (only eyes set Size).
		local sm = (A.sizeMul or 1) * (A.popMul or 1)
		if sm ~= 1 then
			local pos = localCF.Position
			localCF = CFrame.new(pos * sm) * (localCF - pos) -- scale translation, keep rotation
		end
		e.part.CFrame = rootCF * localCF
		if e.eye then -- blink squash: shrink the eye block vertically (Part.Size.Y)
			e.part.Size = Vector3.new(e.baseSize.X * sm, e.baseSize.Y * eyeY * sm, e.baseSize.Z * sm)
		elseif sm ~= 1 then
			e.part.Size = e.baseSize * sm
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	-- follow for any owned/spawned pet (currently one; the loop supports more)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for _, st in pairs(petState) do
		local pet = st.pet
		if pet and pet.Parent and pet.PrimaryPart and not st.emerging then -- 'emerging' = the hatch pop controls the pet
			if not hrp then
				-- no character (respawning) -> just leave the pet where it is
			else
				local targetCF = hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)
				local targetPos = targetCF.Position
				if not petSmoothPos then petSmoothPos = targetPos end
				-- SOFT eased position smoothing (frame-rate-independent) -> the pet glides, no micro-bounce
				local alpha = 1 - math.exp(-FOLLOW_K * dt)
				petSmoothPos = petSmoothPos:Lerp(targetPos, alpha)
				-- clamp the trail so a very fast fart-ascent never strands the pet
				local back = petSmoothPos - targetPos
				if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
				-- ONE gentle slow bob (the breath/lean lives in animatePet) -- soft + low frequency, no jitter
				bobT = bobT + dt
				local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 1.4) * 0.10, 0)
				-- FACING: ease the look direction toward the player's heading on a SLOWER spring than position,
				-- so the pet smoothly SWINGS around to turn (trailing gracefully) instead of snapping in lock-step.
				local fwd = hrp.CFrame.LookVector
				fwd = Vector3.new(fwd.X, 0, fwd.Z)
				if fwd.Magnitude < 0.05 then fwd = (petSmoothFwd or Vector3.new(0, 0, -1)) end
				fwd = fwd.Unit
				if not petSmoothFwd then petSmoothFwd = fwd end
				local fAlpha = 1 - math.exp(-FACE_K * dt)
				petSmoothFwd = petSmoothFwd:Lerp(fwd, fAlpha)
				if petSmoothFwd.Magnitude < 0.05 then petSmoothFwd = fwd end
				local face = petSmoothFwd.Unit
				-- the model is built with +X = front, so yaw the look-at +90 deg to point its +X along travel
				pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0))
			end
			-- animate the sub-parts AFTER positioning the root (local offsets on top of the follow)
			animatePet(pet, dt)
		end
	end
end)

-- ============================================================================================
-- PET QUEST UI -- mysterious landing hint -> discovery popup -> corner tracker -> 3/3 pointer + glowing
-- egg. Reflects the EXISTING per-player progress (found count + owns from PetStateEvent) and is fully
-- DATA-DRIVEN from each pet's catalog entry (pieceLabel / iconEmoji / questHint) so future pet islands
-- reuse it with zero broccoli-specific hardcoding. COSMETIC ONLY -- no gameplay effects.
-- ============================================================================================
local TweenService = game:GetService("TweenService")
local Camera = Workspace.CurrentCamera
local questGui = Instance.new("ScreenGui")
questGui.Name = "PetQuestUI"; questGui.ResetOnSpawn = false; questGui.DisplayOrder = 30
questGui.Parent = player:WaitForChild("PlayerGui")

local function uiStroke(o, th, col) local s=Instance.new("UIStroke"); s.Color=col or Color3.fromRGB(0,0,0); s.Thickness=th or 2; s.Parent=o; return s end
local function uiCorner(o, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0, r or 12); c.Parent=o; return c end

-- (1) HINT: subtle, top-center, fades in then out
local hint = Instance.new("TextLabel")
hint.Name="Hint"; hint.AnchorPoint=Vector2.new(0.5,0); hint.Position=UDim2.new(0.5,0,0.07,0); hint.Size=UDim2.new(0,500,0,34)
hint.BackgroundTransparency=1; hint.Font=Enum.Font.FredokaOne; hint.TextSize=22; hint.TextColor3=Color3.fromRGB(225,232,255); hint.TextTransparency=1; hint.Text=""; hint.Parent=questGui
local hintStroke = uiStroke(hint, 2); hintStroke.Transparency=1

-- (2a) DISCOVERY POPUP: TOP-CENTRE reveal that animates into the tracker's slot.
-- It used to open at y=0.4 -- the middle of the screen, over the player's own character and nowhere near
-- the tracker it then flies into. It opens IN the lane now (LaneY, the same -20 the tracker uses): the
-- tracker yields for the duration, so the reveal has the slot to itself and shrinks into it as the counter
-- takes over. The build-time 76 here was the old "just under the tracker" spot, which is what put two
-- cards in the column at once; showDiscoveryPopup overwrites this anyway, but a stale authored number is
-- what anyone measuring this GUI reads as the spec.
-- Anchor is (0.5, 0) to match the tracker's: that tween sets Position = tracker.Position, and with two
-- different anchor points the popup was landing offset from the box it was supposedly merging into.
local popup = Instance.new("Frame")
-- SHARED BANNER SIZE (500 x 65), like the tracker above it and every card in this column. It was 300 x 110
-- -- narrower AND taller than everything it sits under, which is the worst of both: it never lined up with
-- the card above and it pushed further down the screen than any banner does.
popup.Name="Popup"; popup.AnchorPoint=Vector2.new(0.5,0); popup.Position=UDim2.new(0.5,0,0,-20); popup.Size=UDim2.new(0,500,0,65)
popup.BackgroundColor3=Color3.fromRGB(38,72,38); popup.BackgroundTransparency=0.05; popup.Visible=false; popup.Parent=questGui
uiCorner(popup, 16); uiStroke(popup, 3, Color3.fromRGB(120,220,120))
-- Laid out like the hero card's top line + main line: a small caption at y6 over the bigger line at y29,
-- inside the shared 65px height. The old 40 + 36 stack needed 110px and no longer fits (nor should it).
local popTitle = Instance.new("TextLabel"); popTitle.BackgroundTransparency=1; popTitle.Font=Enum.Font.FredokaOne; popTitle.TextScaled=true; popTitle.TextColor3=Color3.fromRGB(180,255,180); popTitle.Size=UDim2.new(1,-14,0,22); popTitle.Position=UDim2.new(0,7,0,6); popTitle.Text="Pet Search Active!"; popTitle.Parent=popup; uiStroke(popTitle,2)
do local c=Instance.new("UITextSizeConstraint"); c.MaxTextSize=20; c.Parent=popTitle end
local popSub = Instance.new("TextLabel"); popSub.BackgroundTransparency=1; popSub.Font=Enum.Font.FredokaOne; popSub.TextScaled=true; popSub.TextColor3=Color3.fromRGB(255,255,255); popSub.Size=UDim2.new(1,-14,0,30); popSub.Position=UDim2.new(0,7,0,30); popSub.Text=""; popSub.Parent=popup; uiStroke(popSub,2)
do local c=Instance.new("UITextSizeConstraint"); c.MaxTextSize=26; c.Parent=popSub end

-- (2b) CORNER TRACKER: top-right, persistent. Two modes -- "available" shows quest NAME + objective on two
-- lines; "progress"/"complete" minimize to a single compact counter line. refreshQuestHUD() drives both.
local tracker = Instance.new("Frame")
-- TOP-CENTRE (anchor 0.5,0 keeps it centred as Size changes per mode) -- the quest directions ("Find 3
-- Broccoli") belong in the player's eyeline. It shares that space with NotifyCenter's hero banner
-- (y 10..75), which it cannot fit beside, so instead of colliding it YIELDS: see the visibility gate
-- just below -- the tracker slides away while a banner is on screen and slides back when it clears.
-- LANE Y = -20. The top-centre line every quest pill hangs from, tuned live on the mobile emulator.
-- 12 sat too low there for one specific reason: the HUD's UIScale shrinks an element's SIZE but never its
-- own Position, so on a phone the pill renders 240x52 -> 134x31 while its 12px gap from the top edge does
-- not shrink with it. The gap has to come down to match, and -20 is where it looked right.
--
-- It lives on an ATTRIBUTE, not a top-level local: this file's main chunk is at 198 of Luau's 200 local
-- registers, and BOTH the visibility gate below and showDiscoveryPopup need to read it. Change it here and
-- the other two follow.
-- ONE BANNER SIZE FOR THE WHOLE GAME: 500 x 65, the hero card's dimensions and the big event banner's,
-- which were already identical. The tracker was 240 x 52 and RESIZED ITSELF to fit its text, so the same
-- lane showed a different-shaped box depending on whether you were mid-quest, mid-event or mid-arrival --
-- a card would slide out and something visibly smaller and differently-rounded took its place. It is a
-- fixed banner now, like everything else in this column; the text scales inside it instead.
tracker.Name="Tracker"; tracker.AnchorPoint=Vector2.new(0.5,0); tracker.Position=UDim2.new(0.5,0,0,-20); tracker.Size=UDim2.new(0,500,0,65)
tracker:SetAttribute("LaneY", -20)
tracker.BackgroundColor3=Color3.fromRGB(28,52,28); tracker.BackgroundTransparency=0.12; tracker.Visible=false; tracker.Parent=questGui
uiCorner(tracker, 16); uiStroke(tracker, 2, Color3.fromRGB(120,220,120)) -- 16 = the shared banner radius (was 10)

-- ---- TRACKER VISIBILITY GATE: yield the top-centre slot to whatever banner is showing --------------
-- The tracker is PERSISTENT while a quest is live, and it sits in the same top-centre space as
-- NotifyCenter's hero banner (island unlock / purchase / server event / reward). They cannot both fit,
-- so the tracker gives way: it slides out while a banner is up and slides back the moment the lane is
-- clear. Quest state is untouched -- this only controls whether the box is on screen.
--
-- EVERYTHING here lives in a do-block + on _G ON PURPOSE: this file's MAIN CHUNK is at 198 of Luau's
-- 200 local registers. Two more top-level `local`s and the whole script silently fails to compile
-- ("Out of local registers ... exceeded limit 200") and NO pets, quests or trackers work at all --
-- the same failure that already took out CoreClient. Do-block locals are freed at `end`; the closures
-- keep the values as upvalues. Do NOT lift any of this to a top-level `local`.
do
	local wanted, onScreen = false, false
	-- Both read the LaneY attribute set above; HIDDEN keeps the original 82px of travel, so the slide-out
	-- still clears the top edge completely rather than leaving a sliver of pill parked up there.
	local SHOWN, HIDDEN = UDim2.new(0.5, 0, 0, (tracker:GetAttribute("LaneY") or -20)),
		UDim2.new(0.5, 0, 0, (tracker:GetAttribute("LaneY") or -20) - 82)
	local function apply()
		local NC = _G.NotifyCenter
		-- TWO THINGS OUTRANK THE TRACKER, and for the same reason: both are transient and both now open in
		-- this exact lane, while the tracker is persistent and will still be here once they clear.
		--   NotifyCenter.isBusy()  -- the hero banner (island unlock / purchase / server event / reward)
		--   _G.eventPillActive     -- an event pill: the storm countdown, or a milestone pill
		--   the PopupUp attribute   -- THIS file's own discovery popup (see showDiscoveryPopup)
		-- EventClient publishes that second flag by tag as its pills come and go (see eventPillHold there),
		-- so the tracker slides away for them and slides back the moment the last one retires.
		--
		-- ===== THE THIRD ONE WAS THE ONE THIS FILE KEPT MISSING =====
		-- Collecting a piece fires BOTH at once -- the log reads
		--     [Pet][UI] discovery popup shown (1/3) top-centre
		--     [Pet][UI] tracker updated: 1/3
		-- one millisecond apart -- and the popup opens directly under the tracker's slot, so the player got
		-- two stacked green cards for every 1/3. The popup is the transient one and it ENDS by flying into
		-- the tracker's slot, so the tracker waits for it exactly the way it waits for a hero banner.
		-- An attribute, not a local: this file's main chunk is at the 200-register ceiling.
		local blocked = ((NC ~= nil) and NC.isBusy() or false) or (_G.eventPillActive == true)
			or (tracker:GetAttribute("PopupUp") == true)
		local target = wanted and not blocked
		if target == onScreen then return end -- already in the right state; don't restart the tween
		onScreen = target
		if target then
			tracker.Position = HIDDEN
			tracker.Visible = true
			TweenService:Create(tracker, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = SHOWN }):Play()
		else
			TweenService:Create(tracker, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = HIDDEN }):Play()
			task.delay(0.22, function() if not onScreen then tracker.Visible = false end end)
		end
	end
	-- Quest code calls this instead of touching tracker.Visible, so "should it show" (quest state) and
	-- "may it show" (is a banner up) stay separate concerns.
	_G.__petTrackerSet = function(w) wanted = w and true or false; apply() end
	-- Published so the popup can force an immediate re-check the moment it takes the lane, instead of
	-- waiting up to 0.15s for the poll below -- that gap is long enough to see both cards on screen.
	_G.__petTrackerApply = apply
	task.spawn(function()
		while true do task.wait(0.15); apply() end -- NotifyCenter has no signal to listen to; poll it
	end)
end
-- Icon column widened for the taller card. TextScaled on the label, capped: the box is a fixed 500x65 now,
-- so the TEXT is what adapts (a long nextStep line shrinks to fit) rather than the box growing to suit it.
local trkIcon = Instance.new("TextLabel"); trkIcon.BackgroundTransparency=1; trkIcon.Font=Enum.Font.Gotham; trkIcon.TextSize=30; trkIcon.Size=UDim2.new(0,36,1,0); trkIcon.Position=UDim2.new(0,10,0,0); trkIcon.Text=""; trkIcon.Parent=tracker
local trkLabel = Instance.new("TextLabel"); trkLabel.BackgroundTransparency=1; trkLabel.Font=Enum.Font.FredokaOne; trkLabel.TextScaled=true; trkLabel.TextColor3=Color3.fromRGB(255,255,255); trkLabel.Size=UDim2.new(1,-56,1,0); trkLabel.Position=UDim2.new(0,44,0,0); trkLabel.TextXAlignment=Enum.TextXAlignment.Center; trkLabel.Text=""; trkLabel.Parent=tracker; uiStroke(trkLabel,2) -- centred in the box
-- THE COLLECTIBLE COUNTER GETS A FIXED, BIGGER SIZE: 30, set in refreshQuestHUD below. "Pieces 1/3" /
-- "Coconuts 1/7" is the one line on this card that is always short, so TextScaled had nothing to do and it
-- sat at this 24 cap -- visibly smaller than the 30px icon beside it. It is the number the player is
-- actually tracking, so it is set outright rather than left to scale. Only the COUNTER is fixed: the
-- objective and next-step lines are sentences of unpredictable length and still scale to fit.
-- The constraint is deliberately NOT held in a file-scope local: this chunk runs at 198 of Luau's 200
-- top-level registers, so refreshQuestHUD looks it up instead (see the note there).
do local c=Instance.new("UITextSizeConstraint"); c.MaxTextSize=24; c.Parent=trkLabel end
local trkSub = Instance.new("TextLabel"); trkSub.BackgroundTransparency=1; trkSub.Font=Enum.Font.Gotham; trkSub.TextSize=13; trkSub.TextColor3=Color3.fromRGB(210,235,210); trkSub.Size=UDim2.new(1,-50,0,18); trkSub.Position=UDim2.new(0,42,0,28); trkSub.TextXAlignment=Enum.TextXAlignment.Left; trkSub.Text=""; trkSub.Visible=false; trkSub.Parent=tracker; uiStroke(trkSub,1)

-- (3) POINTER: on-screen arrow guiding to the egg (shown at 3/3)
local pointer = Instance.new("TextLabel")
pointer.Name="Pointer"; pointer.AnchorPoint=Vector2.new(0.5,0.5); pointer.Size=UDim2.new(0,60,0,60)
pointer.BackgroundTransparency=1; pointer.Font=Enum.Font.GothamBold; pointer.TextSize=46; pointer.TextColor3=Color3.fromRGB(150,255,140); pointer.Text="\xE2\x9E\xA4"; pointer.Visible=false; pointer.Parent=questGui; uiStroke(pointer,2)

local activeUiPet = nil -- petId currently driving the tracker/pointer
local onIsland = {}     -- [petId] = bool (for the once-per-visit landing hint)

local function flashHint(def)
	-- SHORT on-landing reveal showing the quest's real NAME + objective (the corner tracker then persists it)
	hint.Text = (def.iconEmoji or "\xF0\x9F\x90\xBe").."  "..(def.objective or "Pet Quest") -- objective only, no "???" (note: flashHint is no longer called)
	hint.TextTransparency = 1; hintStroke.Transparency = 1
	TweenService:Create(hint, TweenInfo.new(0.6), {TextTransparency=0}):Play()
	TweenService:Create(hintStroke, TweenInfo.new(0.6), {Transparency=0}):Play()
	task.delay(3.0, function()
		TweenService:Create(hint, TweenInfo.new(1.0), {TextTransparency=1}):Play()
		TweenService:Create(hintStroke, TweenInfo.new(1.0), {Transparency=1}):Play()
	end)
	print("[Pet][UI] on-landing pet-quest hint shown (points to inventory)")
end

-- progress for ONE quest: found, total (nil = count-less), started, complete. Piece quests read the server
-- found/total; the count-less ones (fishing/dig) read the client-tracked localQuestProg.
local function questProgress(petId, def, st)
	local qt = def.questType
	if qt == "dig" or qt == "fishing" then
		local lp = localQuestProg[petId] or {}
		local total = lp.total
		local complete = (lp.complete == true) or (total ~= nil and total >= 1 and (lp.found or 0) >= total)
		return lp.found or 0, total, lp.started == true, complete
	end
	local found = (st and st.uiFound) or 0
	local total = (st and st.total) or #def.pieceMarkers
	-- piece quests: started once the first piece is found; COMPLETE at full count -> the tracker swaps to the
	-- next-step text (def.nextStep). owns=true (hatched) hides the tracker; the on-screen pointer guides to the egg.
	return found, total, found >= 1, (total >= 1 and found >= total)
end

-- THE on-screen quest indicator. Picks the quest to show (a started/finished one wins over a merely
-- available one), then renders it: AVAILABLE -> name + objective (two lines); STARTED -> compact live
-- counter; full -> "Complete!"; hatched -> hidden. Assigned to the forward-declared upvalue. Cosmetic-only.
refreshQuestHUD = function()
	local showId, mode
	-- 1) a STARTED-but-unfinished quest wins (progress); a finished-but-unhatched one shows "Complete!"
	--    ISLAND-BOUND: `and onIsland[petId]` so the on-screen tracker only shows while the player is ON that
	--    quest's island (hides elsewhere, reappears on return). The pet GUI quest TAB is unaffected.
	--    ACCEPT-BOUND: `and _G.petQuestGate(def)` -- landing on an island no longer tells you what the quest is.
	--    You have to find the quest giver and hear it from them.
	for petId, def in pairs(PETS) do
		local st = petState[petId]
		if st and not st.owns and onIsland[petId] and _G.petQuestGate(def) then
			local _, _, started, complete = questProgress(petId, def, st)
			if complete then showId, mode = petId, "complete"; break
			elseif started then showId, mode = petId, "progress"; break end
		end
	end
	-- 2) else an AVAILABLE quest on whatever island the player is standing on
	if not showId then
		for petId, def in pairs(PETS) do
			local st = petState[petId]
			if st and not st.owns and onIsland[petId] and _G.petQuestGate(def) then showId, mode = petId, "available"; break end
		end
	end
	if not showId then _G.__petTrackerSet(false); activeUiPet = nil; return end
	activeUiPet = showId
	local def = PETS[showId]; local st = petState[showId]
	trkIcon.Text = def.iconEmoji or "\xF0\x9F\x90\xBE"
	-- The label's size cap, looked up rather than kept in a file-scope local: this chunk is already ON
	-- Luau's 200-top-level-register ceiling, and one more local would refuse to compile at all. The lookup
	-- is free at the rate this function runs.
	local trkCap = trkLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if mode == "available" then
		-- AVAILABLE: show the OBJECTIVE cleanly (no "???"). TextWrapped so a longer objective fits two lines.
		-- THE BOX NO LONGER CHANGES SIZE. Both modes are the shared 500 x 65 banner; only the label inside
		-- it moves. A lane whose card silently grows and shrinks between states is the thing that made the
		-- top of the screen look unsettled, and it is the whole reason the size is fixed at build time now.
		trkLabel.TextWrapped = true
		trkLabel.TextScaled = true; if trkCap then trkCap.MaxTextSize = 24 end -- a sentence: let it shrink to fit two lines
		trkLabel.Position = UDim2.new(0,44,0,6); trkLabel.Size = UDim2.new(1,-56,0,53) -- centred; icon column left
		trkLabel.Text = def.objective or ""; trkLabel.TextColor3 = Color3.fromRGB(255,240,150)
		trkSub.Visible = false
	else
		trkLabel.TextWrapped = false
		trkLabel.Position = UDim2.new(0,44,0,0); trkLabel.Size = UDim2.new(1,-56,1,0) -- centred; icon column left
		trkSub.Visible = false
		if mode == "complete" then
			-- count finished -> show the NEXT step for this quest (def.nextStep), not the finished count
			trkLabel.TextScaled = true; if trkCap then trkCap.MaxTextSize = 24 end -- a sentence again: scale it
			trkLabel.Text = def.nextStep or "Complete!"; trkLabel.TextColor3 = Color3.fromRGB(160,255,160)
		else
			-- THE COUNTER. Fixed size, not scaled. The cap is raised with it
			-- because UITextSizeConstraint clamps the effective size either way, so leaving it at 24 would
			-- quietly undo the whole change.
			local found, total = questProgress(showId, def, st)
			local word = def.trackWord or def.pieceLabel or "Progress"
			trkLabel.TextScaled = false
			if trkCap then trkCap.MaxTextSize = 30 end
			trkLabel.TextSize = 30
			trkLabel.Text = (total ~= nil) and (word.." "..found.."/"..total) or (word..": "..found)
			trkLabel.TextColor3 = Color3.fromRGB(255,255,255)
		end
		-- THE PILL NO LONGER SIZES ITSELF TO ITS TEXT.
		-- It used to: a fixed 200-wide box with an unwrapped, unscaled, centred label overflowed its own
		-- rounded edges on any longer counter ("Coconut 1/7", every longer nextStep line), so the box was
		-- measured and grown to fit. That solved the overflow and created a worse problem -- a card in the
		-- shared top-centre column that was a different width every time you looked at it.
		--
		-- The banner is 500 wide now, which is roomier than the widest string this ever produced, and the
		-- label is TextScaled (set at build time) so anything longer shrinks to fit INSIDE the card instead
		-- of pushing it wider. Fixed size, no overflow, and it matches every other banner in the lane.
	end
	_G.__petTrackerSet(true) -- "quest is live" -> the gate decides whether a banner is currently in the way
end

-- IT NEVER SHARES THE LANE WITH AN ANNOUNCEMENT.
-- The top-centre strip belongs to NotifyCenter's hero banner (island unlock / purchase / server event /
-- reward) whenever one is up. The tracker already yields to it; this reveal now does the same, in both
-- directions: if a banner is up when a piece is found the reveal WAITS for the lane to clear rather than
-- opening underneath it, and if a banner starts while the reveal is on screen the reveal gets out of the
-- way immediately. Quest state is untouched either way -- this only decides whether the box is drawn.
--
-- Every local here is inside the function ON PURPOSE. This file's main chunk sits at 198 of Luau's 200
-- local registers; two more top-level `local`s and the whole script silently fails to compile, taking
-- every pet, quest and tracker with it.
local function showDiscoveryPopup(def, found, total)
	-- WHERE IT SITS IS MEASURED, NOT HARD-CODED.
	-- The HUD's UIScale shrinks an element's SIZE but never its own Position, so a fixed "76px from the
	-- top" is not a fixed place: on a 1044px desktop screen it is 7% down, on a 372px phone screen it is
	-- 20% down -- far enough that the reveal reads as mid-screen again, which is the whole bug. Measured
	-- on the emulator: tracker 240x52 renders as 134x31, so the gap under it shrinks by 21px while the 76
	-- does not move.
	-- IT OPENS IN THE LANE ITSELF, not under it. It used to be placed against the tracker's live bottom
	-- edge (LaneY + however tall the tracker renders + 8) because the tracker stayed on screen beside it --
	-- which is exactly the two-cards-at-once bug. The tracker now yields for the duration (see the PopupUp
	-- attribute below), so the reveal gets the prime slot to itself and then shrinks into it as the counter
	-- takes over. One card, one place, whatever the HUD's UIScale does to the sizes on a phone.
	local SHOWN_AT = UDim2.new(0.5, 0, 0, tracker:GetAttribute("LaneY") or -20)
	local function bannerUp()
		local NC = _G.NotifyCenter
		return (NC ~= nil) and NC.isBusy() or false
	end
	task.spawn(function()
		-- ===== IT TAKES THE LANE, IT DOES NOT SHARE IT =====
		-- Claimed FIRST, before the banner wait below, not just before the card is drawn. The tracker polls
		-- on its own 0.15s timer, so if the claim came after the wait there is a window as a hero banner
		-- clears where the tracker slides in and this popup immediately shoves it back out -- a visible
		-- flicker for the exact case the waiting exists to handle. Both exits hand it back (handBack).
		tracker:SetAttribute("PopupUp", true)
		if _G.__petTrackerApply then pcall(_G.__petTrackerApply) end

		-- wait out a banner, but not forever -- 6s, then show anyway rather than swallow the reveal
		local waited = 0
		while bannerUp() and waited < 6 do task.wait(0.15); waited = waited + 0.15 end

		popSub.Text = found.."/"..total.." "..(def.pieceLabel or "Pieces").." Found"
		popTitle.TextTransparency=0; popSub.TextTransparency=0; popup.BackgroundTransparency=0.05
		-- Pops in from 80% of the shared banner size to the full 500 x 65. It used to grow 240x88 -> 300x110,
		-- i.e. it settled at a size no other card in this column uses; the pop is kept, the destination is
		-- now the one banner size.
		popup.Position = SHOWN_AT; popup.Size = UDim2.new(0,400,0,52); popup.Visible = true
		TweenService:Create(popup, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size=UDim2.new(0,500,0,65)}):Play()
		print("[Pet][UI] discovery popup shown ("..found.."/"..total..") top-centre")

		-- HANDING THE LANE BACK is one line in both exits, and it must happen AFTER the popup is off the
		-- screen -- clearing it early puts the tracker back underneath a card that is still there.
		local function handBack()
			tracker:SetAttribute("PopupUp", false)
			if _G.__petTrackerApply then pcall(_G.__petTrackerApply) end
		end

		local retired = false
		task.spawn(function()   -- a banner starting mid-reveal takes the lane back at once
			while not retired do
				if bannerUp() then popup.Visible = false; retired = true; handBack(); break end
				task.wait(0.1)
			end
		end)
		task.delay(2.0, function()
			if retired then return end
			retired = true
			local ti = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			-- Flies into the tracker's SLOT, not into tracker.Position -- the tracker is parked off-screen
			-- right now (it yielded to this popup), so reading its live position would send the card up
			-- past the top edge instead of shrinking into the place the counter is about to appear.
			TweenService:Create(popup, ti, {
				Position = UDim2.new(0.5, 0, 0, tracker:GetAttribute("LaneY") or -20),
				Size = UDim2.new(0, 180, 0, 40),
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(popTitle, ti, {TextTransparency=1}):Play()
			TweenService:Create(popSub, ti, {TextTransparency=1}):Play()
			task.delay(0.6, function() popup.Visible=false; handBack() end)
		end)
	end)
end

local function setEggGlow(petId, on)
	local st = petState[petId]; if not st then return end
	if on and not st.eggGlow and st.egg then
		local hl = Instance.new("Highlight"); hl.FillColor=Color3.fromRGB(120,255,120); hl.FillTransparency=0.45
		hl.OutlineColor=Color3.fromRGB(230,255,180); hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = st.eggVisual or st.egg; hl.Parent = st.egg; st.eggGlow = hl
		local shell = st.egg:FindFirstChild("Shell", true)
		if shell then
			local pl=Instance.new("PointLight"); pl.Name="EggGlowLight"; pl.Color=Color3.fromRGB(150,255,150); pl.Brightness=4; pl.Range=26; pl.Parent=shell
			local em=Instance.new("ParticleEmitter"); em.Name="EggGlowSparkle"; em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Rate=16; em.Lifetime=NumberRange.new(0.6,1.1); em.Speed=NumberRange.new(2,6); em.Size=NumberSequence.new(0.9); em.LightEmission=0.85; em.Parent=shell
		end
	elseif not on and st.eggGlow then
		st.eggGlow:Destroy(); st.eggGlow=nil
		local shell = st.egg and st.egg:FindFirstChild("Shell", true)
		if shell then for _,n in ipairs({"EggGlowLight","EggGlowSparkle"}) do local o=shell:FindFirstChild(n); if o then o:Destroy() end end end
	end
end

local function hideQuestUI(petId)
	_G.__petTrackerSet(false); pointer.Visible = false
	setEggGlow(petId, false)
	if activeUiPet == petId then activeUiPet = nil end
end

-- ===== HATCH: press E -> shake -> crack -> pet pops out -> follows, THEN the claim registers =====
-- Purely visual; the resulting pet is the same broccoli pet and ownership/persistence still saves via
-- the existing PetClaimEvent (fired AFTER the animation). Assigns the forward-declared `hatchEgg`.
hatchEgg = function(petId, def)
	local st = petState[petId]
	if not st or st.hatching or st.owns then return end
	st.hatching = true -- pauses the egg bob + (below) blocks applyState from re-touching the egg/glow
	print("[Pet][HATCH] hatch started for "..player.Name)
	-- HATCH SOUND #1: play the PRELOADED egg-CRACK sound the INSTANT the hatch begins (no load delay now, so it
	-- fires right at the true hatch start + leads in through the shake). The unlock follows at the crack beat below.
	pcall(function() hatchCrackSound.TimePosition = 0; hatchCrackSound:Play() end)
	local prompt = st.egg and st.egg:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then prompt.Enabled = false end -- can't re-trigger mid-hatch
	setEggGlow(petId, false)
	local visual = st.eggVisual
	local base = st.eggBaseCF or CFrame.new((st.eggPos or Vector3.zero) + Vector3.new(0, 2.6, 0))

	-- 1) SHAKE ~2.0s, intensity ramps up
	local SHAKE, t0 = 2.0, os.clock()
	while os.clock() - t0 < SHAKE do
		local p = (os.clock() - t0) / SHAKE
		local amp = 0.1 + p * p * 0.9
		if visual and visual.PrimaryPart then
			pcall(function()
				visual:PivotTo(base
					* CFrame.new((math.random()-0.5)*amp*1.4, math.abs(math.sin((os.clock()-t0)*22))*amp*0.5, (math.random()-0.5)*amp*1.4)
					* CFrame.Angles(math.rad((math.random()-0.5)*amp*55), math.rad((math.random()-0.5)*amp*80), math.rad((math.random()-0.5)*amp*55)))
			end)
		end
		task.wait()
	end

	-- 2) CRACK: particle burst + sound, fling shell shards, remove the intact egg visual
	print("[Pet][HATCH] egg cracked, pet emerging")
	-- HATCH SOUND #2: the PRELOADED PET-UNLOCK sound lands HERE at the crack/shatter beat as the pet reveals
	-- (preloaded, so it fires on time -- no ~2s load delay -- layered over the tail of the crack as the payoff).
	pcall(function() hatchUnlockSound.TimePosition = 0; hatchUnlockSound:Play() end)
	-- THE PET IS OUT. A double-thump on the reveal (see Haptics.client.luau) -- called through _G rather than
	-- required, because this file sits on Luau's 200-local ceiling and a require would need a new upvalue.
	if _G.hapticPulse then pcall(_G.hapticPulse, "hatch") end
	pcall(function()
		local fx = Instance.new("Part"); fx.Anchored=true; fx.CanCollide=false; fx.CanQuery=false; fx.Transparency=1; fx.Size=Vector3.new(1,1,1); fx.CFrame=base; fx.Parent=Workspace
		local em=Instance.new("ParticleEmitter"); em.Texture="rbxasset://textures/particles/sparkles_main.dds"; em.Color=ColorSequence.new(Color3.fromRGB(210,255,180)); em.Lifetime=NumberRange.new(0.4,0.8); em.Speed=NumberRange.new(8,16); em.SpreadAngle=Vector2.new(180,180); em.Size=NumberSequence.new(1.4); em.Rate=0; em.LightEmission=0.9; em.Parent=fx
		em:Emit(40)
		local snd=Instance.new("Sound"); snd.SoundId="rbxassetid://9116458024"; snd.Volume=0.6; snd.Parent=fx; snd:Play()
		game:GetService("Debris"):AddItem(fx, 1.2)
	end)
	if visual then
		pcall(function()
			for s = 1, 6 do
				local ang = (s-1) * (2*math.pi/6)
				local shard = Instance.new("Part"); shard.Shape=Enum.PartType.Ball; shard.Size=Vector3.new(1.1,0.7,1.1); shard.Color=Color3.fromRGB(210,234,182); shard.Material=Enum.Material.SmoothPlastic
				shard.Anchored=true; shard.CanCollide=false; shard.CanQuery=false; shard.CastShadow=false; shard.CFrame=base*CFrame.new(0,1,0); shard.Parent=Workspace
				TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{CFrame=base*CFrame.new(math.cos(ang)*5, math.random()*3-1, math.sin(ang)*5), Transparency=1, Size=Vector3.new(0.2,0.2,0.2)}):Play()
				game:GetService("Debris"):AddItem(shard, 0.8)
			end
		end)
		pcall(function() visual:Destroy() end); st.eggVisual = nil
	end

	-- 3) PET POPS OUT: spawn the follower, scale-pop it at the nest, then hand off to the follow loop
	spawnFollowerPet(petId)
	local pet = st.pet
	st.emerging = true -- follow loop skips it while we control the pop
	if pet then
		pcall(function() pet:ScaleTo(0.2) end)
		local POP, pop0 = 0.45, os.clock()
		while os.clock() - pop0 < POP do
			local p = (os.clock() - pop0) / POP
			pcall(function() pet:ScaleTo(0.2 + p * 0.8); pet:PivotTo(base * CFrame.new(0, math.sin(p * math.pi) * 2.2, 0)) end)
			task.wait()
		end
		pcall(function() pet:ScaleTo(1) end)
	end
	petSmoothPos = base.Position -- the pet flies OUT from the nest toward the player
	st.emerging = false

	-- 4) register the claim (ownership + persistence) -- AFTER the animation, per design
	pcall(function() PetClaimEvent:FireServer(petId) end)
	print("[Pet][HATCH] hatch complete, pet now following")
	st.hatching = false
	task.delay(2.0, function() if st.egg then pcall(function() st.egg:Destroy() end); st.egg = nil end end) -- clean up the nest container
end

-- ===== STATE SYNC =====
local equippedPetId = nil -- the petId currently equipped (drives the follower + flight-progress accrual)
local function applyState(state)
	for petId, def in pairs(PETS) do
		petState[petId] = petState[petId] or { pieces = {}, collected = {}, egg = nil, pet = nil, built = false, owns = false }
		local st = petState[petId]
		local info = state[petId] or { found = 0, total = #def.pieceMarkers, owns = false }
		local prevFound = st.uiFound or 0
		local wasOwned = st.owns -- RE-DOABLE QUEST: detect a pet we JUST lost (traded away) to reset its local quest progress
		st.owns = info.owns == true
		_G.ownedPetSpecies = _G.ownedPetSpecies or {}
		_G.ownedPetSpecies[petId] = st.owns -- exposed so ShopClient can gate food stands until the pet quest is done
		st.equipped = info.equipped == true
		st.level = info.level or 1
		st.rare = info.rare == true -- rare variant flag (drives pre-maxed + rare look)
		if st.equipped then equippedPetId = petId elseif equippedPetId == petId then equippedPetId = nil end
		st.uiFound = info.found
		st.total = info.total
		if st.owns then
			-- owns the pet: hide find-pieces + egg + chest, follow ONLY if equipped, and tear down the quest UI
			for i, piece in pairs(st.pieces) do setVisible(piece, false) end
			setVisible(st.egg, false)
			if st.chest then setVisible(st.chest, false) end
			if st.filmProps then for _, o in ipairs(st.filmProps) do setVisible(o, false) end end -- (empty now: the projector + beam are PERMANENT, never hidden)
			if st.projGlow then st.projGlow(false) end -- owned -> remove the projector glow

			if st.fishProps then for _, o in ipairs(st.fishProps) do setVisible(o, false) end end -- fishing: hide the rod barrel + fish spot (prompt) once owned
			if st.digProps then for _, o in ipairs(st.digProps) do setVisible(o, false) end end -- dig: hide the shovel stand + dig mounds + held shovel once owned
			-- NOTE: st.movieGui is intentionally NOT destroyed here -- the finale end card holds on the screen permanently
			if st.hatchScreenEgg then st.hatchScreenEgg() end -- popcorn: now owned -> crack the egg off the screen end frame, revealing the sheep
			if st.equipped then spawnFollowerPet(petId) else despawnFollowerPet(petId) end
			hideQuestUI(petId)
			if not st.uiDoneLogged then st.uiDoneLogged = true; print("[Pet][UI] quest complete - UI hidden") end
		else
			-- RE-DOABLE QUEST: if we JUST lost this pet (traded it away), the server has reset its quest progress
			-- to zero -- wipe the stale LOCAL progress so the pieces/egg/chest reappear and it can be re-done now.
			if wasOwned then st.collected = {}; st.hasKey = false; st.uiFound = 0; info.found = 0 end
			-- not owned yet: show uncollected pieces/coconuts. For "find" the egg appears at full count; for
			-- "crack" the CHEST stays visible and glows once the player has the Cave Key (the egg is revealed
			-- only when they open the chest). While st.hatching, leave the egg/glow alone.
			for i, piece in pairs(st.pieces) do setVisible(piece, not st.collected[i]) end
			if st.isCrack then
				if st.chest then setVisible(st.chest, true) end
				if st.chestGlow then st.chestGlow(st.hasKey or info.found >= info.total) end -- glow once the Cave Key is earned (local or server-confirmed)
			elseif st.isFilm then
				-- projector + screen are static props (built visible); the egg appears ONLY after the projector
				-- show (revealEgg), so don't auto-reveal it here -- st.egg stays nil until the mini-movie plays.
				-- HIGHLIGHT the projector once all reels are collected (so the player finds where to load them);
				-- turn it off once the egg has appeared (movie played).
				if st.projGlow then st.projGlow(info.found >= info.total and not st.egg) end
			elseif st.isFishing then
				-- fishing: the rod barrel + Fish prompt are static; the egg appears ONLY when CAUGHT (spawnButterEgg),
				-- so don't auto-reveal anything here -- st.egg stays nil until the player reels in the egg.
			elseif st.isDigging then
				-- dig: the shovel stand + dig mounds are static; the egg appears ONLY when the REAL spot is dug
				-- (spawnArmadilloEgg), so don't auto-reveal anything here -- st.egg stays nil until then.
			elseif not st.hatching then
				setVisible(st.egg, info.found >= info.total)
			end
			-- ===== QUEST UI: the on-screen tracker is refreshed ONCE after this loop (refreshQuestHUD picks
			-- which quest to show); here we only fire the first-piece discovery popup + the progress log. =====
			if info.found >= 1 then
				if prevFound < 1 then showDiscoveryPopup(def, info.found, info.total) end -- first piece = the reveal
				if info.found ~= prevFound then print("[Pet][UI] tracker updated: "..info.found.."/"..info.total) end
			end
			if info.found >= info.total and info.found >= 1 then
				if not st.isCrack and not st.isFilm and not st.isFishing and not st.hatching then setEggGlow(petId, true) end -- broccoli: glowing egg at full count (crack/film/fishing reveal their egg via an interaction)
				if not st.ui3of3Logged then st.ui3of3Logged = true; print("[Pet][UI] "..info.total.."/"..info.total.." reached") end
			else
				if not st.isCrack and not st.isFilm and not st.isFishing then setEggGlow(petId, false) end
				st.ui3of3Logged = false
			end
		end
	end
	refreshQuestHUD() -- re-pick + render the on-screen quest indicator from the latest state
end
-- Everything below lives in a do-block for the same reason as the gate above: this chunk is at the
-- 200-register ceiling, and locals inside a block are released at its end.
do
	-- Remember the last state the server sent, so accepting a quest can re-apply it with no round trip.
	local lastPetState = {}
	local stateReceived = false -- true once a REAL server state has landed (guards the re-apply below)
	if PetStateEvent then -- guarded: a missing remote can't crash the script
		PetStateEvent.OnClientEvent:Connect(function(state)
			lastPetState = state or lastPetState
			stateReceived = true
			applyState(lastPetState)
		end)
	end

	-- ===== BUILD-AFTER-STATE FIX: "broccoli / film reels / coconuts sometimes never appear" =====
	-- Every quest world builds its pieces HIDDEN and waits for applyState to reveal them -- but applyState
	-- only runs when a PetStateEvent arrives. The marker fetch can take a long time (the server's scan may
	-- hold the RF for up to 90s), so the world routinely finishes building AFTER the last state push...
	-- and then nothing ever reveals the pieces. The startup builder calls this hook right after each
	-- buildPetWorld to re-apply the latest known state to the freshly built (still hidden) pieces.
	-- Gated on stateReceived so a build finishing before ANY real state cannot reveal pieces to a player
	-- who might own the pet (the original reason they build hidden).
	_G.petWorldBuilt = function()
		if stateReceived then applyState(lastPetState) end
	end

-- ===== ACCEPTING A QUEST OPENS IT, IMMEDIATELY =====
-- The NPC sets Island<N>QuestAccepted on the SERVER (page 2 of its dialogue) and it replicates here. Watching
-- the attribute rather than a RemoteEvent means the quest scripts and the NPC know nothing about each other,
-- and a player who accepted before a respawn still has their quest open afterwards.
--
-- One listener per quest island, wired from the pet catalog so adding a quest island needs no edit here.
	local wired = {}
	for _, def in pairs(PETS) do
		local n = def.islandPrefix and tonumber(tostring(def.islandPrefix):match("%d+"))
		local attr = n and ("Island%dQuestAccepted"):format(n)
		if attr and not wired[attr] then
			wired[attr] = true
			player:GetAttributeChangedSignal(attr):Connect(function()
				if player:GetAttribute(attr) ~= true then return end
				print("[Pet][Quest] " .. attr .. " -> quest accepted")
				applyState(lastPetState)   -- refresh anything gated on it
				refreshQuestHUD()          -- and the tracker can finally show what the quest is
			end)
		end
	end
end

-- RARE HATCH FANFARE: the server fires this when a rare hatches -> a big on-screen "RARE!" callout + an extra
-- sparkle burst on the new pet, so the player clearly knows they got something special. Cosmetic-only.
if PetRareEvent then
	PetRareEvent.OnClientEvent:Connect(function(petId, rareName)
	-- A rare is the rarest thing most players will ever see here, so it gets the only five-tap rhythm in
	-- the palette. Ranked above `hatch`, which fires on the same reveal -- the rare wins, the hatch drops.
	if _G.hapticPulse then pcall(_G.hapticPulse, "rare") end
		print(string.format("[PetRare] RARE hatch fanfare: %s (%s)", tostring(rareName), tostring(petId)))
		local TW = game:GetService("TweenService")
		local sg = Instance.new("ScreenGui"); sg.Name="RareHatchFanfare"; sg.ResetOnSpawn=false; sg.DisplayOrder=60; sg.IgnoreGuiInset=true
		sg.Parent = player:WaitForChild("PlayerGui")
		local lbl = Instance.new("TextLabel"); lbl.AnchorPoint=Vector2.new(0.5,0.5); lbl.Position=UDim2.new(0.5,0,0.32,0); lbl.Size=UDim2.new(0,540,0,90)
		lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextScaled=true; lbl.TextColor3=Color3.fromRGB(255,170,245)
		lbl.Text="\xE2\x9C\xA8 RARE!  "..tostring(rareName).."  \xE2\x9C\xA8"; lbl.Parent=sg
		local stk=Instance.new("UIStroke", lbl); stk.Color=Color3.fromRGB(150,20,140); stk.Thickness=3
		lbl.TextTransparency=1; stk.Transparency=1
		TW:Create(lbl, TweenInfo.new(0.3), {TextTransparency=0}):Play(); TW:Create(stk, TweenInfo.new(0.3), {Transparency=0}):Play()
		task.delay(2.0, function()
			TW:Create(lbl, TweenInfo.new(0.6), {TextTransparency=1, Position=UDim2.new(0.5,0,0.26,0)}):Play()
			TW:Create(stk, TweenInfo.new(0.6), {Transparency=1}):Play()
			task.wait(0.7); sg:Destroy()
		end)
		task.delay(0.4, function() -- let the pet spawn, then a celebratory burst on it
			local st = petState[petId]; local pet = st and st.pet; local root = pet and pet.PrimaryPart
			if root then
				local b = Instance.new("ParticleEmitter"); b.Color=ColorSequence.new(Color3.fromRGB(255,150,240)); b.LightEmission=0.9
				b.Lifetime=NumberRange.new(0.5,1.0); b.Speed=NumberRange.new(6,14); b.Size=NumberSequence.new(0.7); b.Rate=0; b.Rotation=NumberRange.new(0,360); b.Parent=root
				b:Emit(60); game:GetService("Debris"):AddItem(b, 1.4)
			end
		end)
	end)
end

-- ===== COLLECTION MILESTONE CELEBRATION: the server just paid out a collection reward (a TITLE, or -- at 10/10 --
-- the secret Pizza Dragon). A reward the player doesn't NOTICE may as well not exist, so this is loud: a gold card,
-- what they earned, and a burst of confetti. Cosmetic-only; the grant already happened server-side. =====
do
	local PetMilestoneEvent = RS:WaitForChild("PetMilestoneEvent", 30) -- block-scoped: no top-level local burned
	if PetMilestoneEvent then
		PetMilestoneEvent.OnClientEvent:Connect(function(m)
			if type(m) ~= "table" then return end
			local isPet = (m.kind == "pet")
			print(string.format("[PetMilestone] %s earned at %s/%s", tostring(m.name), tostring(m.have), tostring(m.target)))

			-- A TITLE ANNOUNCES ITSELF IN THE BANNER LANE, not in a card of its own. NotifyCenter owns the
			-- top-centre strip and a second card drawn beside it is the one thing that lane forbids -- and a
			-- title IS a nametag, so a banner is also the right size for it: name the title, say where it now
			-- lives, get out of the way. TUTORIAL + exclusive is the milestone tier, so nothing plays over it.
			--
			-- The 10/10 SECRET PIZZA DRAGON keeps the big gold card below. It is the end of the entire
			-- collection and the only reward here that has earned an interruption.
			--
			-- Colours mirror TitleTags.client.luau's TITLE_COLOR, so the banner that announces a title and the
			-- nametag it turns into are the same colour. An unlisted title still renders, in the default gold.
			-- NO NAMED LOCALS IN THIS BRANCH. PetFollow sits ONE register under Luau's hard 200-local
			-- ceiling (tools/registers.py), a limit the compiler cannot see and Roblox enforces at load:
			-- go over it and the whole file silently refuses to run. The colour table and the
			-- NotifyCenter handle are therefore written inline instead of lifted into locals -- uglier,
			-- and cheaper than spending the file's last register on tidiness.
			if not isPet then
				if _G.NotifyCenter and _G.NotifyCenter.push then
					_G.NotifyCenter.push({
						top       = "\xF0\x9F\x8F\x86 TITLE EARNED",
						text      = tostring(m.id or m.name or "Title"),
						sub       = string.format("%s / %s pets  \xC2\xB7  it now sits above your head",
							tostring(m.have), tostring(m.target)),
						color     = ({ ["Pet Collector"] = Color3.fromRGB(80, 220, 140),
						               ["Beastmaster"]   = Color3.fromRGB(255, 190, 50) })[m.id]
						            or Color3.fromRGB(255, 215, 0),
						priority  = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.TUTORIAL or nil,
						exclusive = true,
						duration  = 5,
					})
					return
				end
				-- No NotifyCenter (stale copy mid-load, or it never started): fall through to the card rather
				-- than swallowing the reward. A reward nobody sees may as well not have been given.
				warn("[PetMilestone] NotifyCenter unavailable -- showing the title on the fallback card")
			end

			local TW = game:GetService("TweenService")
			local sg = Instance.new("ScreenGui"); sg.Name = "PetMilestoneCard"; sg.ResetOnSpawn = false
			sg.DisplayOrder = 65; sg.IgnoreGuiInset = true; sg.Parent = player:WaitForChild("PlayerGui")
			local card = Instance.new("Frame"); card.AnchorPoint = Vector2.new(0.5,0.5); card.Position = UDim2.new(0.5,0,0.3,0)
			card.Size = UDim2.new(0,500,0,160); card.BackgroundColor3 = Color3.fromRGB(46,36,12); card.BackgroundTransparency = 1
			card.Parent = sg
			Instance.new("UICorner", card).CornerRadius = UDim.new(0,18)
			local stroke = Instance.new("UIStroke", card); stroke.Color = Color3.fromRGB(255,200,60); stroke.Thickness = 3; stroke.Transparency = 1
			local eyebrow = Instance.new("TextLabel"); eyebrow.BackgroundTransparency = 1; eyebrow.Position = UDim2.new(0,0,0,12)
			eyebrow.Size = UDim2.new(1,0,0,20); eyebrow.Font = Enum.Font.GothamBold; eyebrow.TextSize = 14
			eyebrow.TextColor3 = Color3.fromRGB(220,190,120); eyebrow.TextTransparency = 1
			eyebrow.Text = string.format("COLLECTION REWARD  \xE2\x80\xA2  %s / %s PETS", tostring(m.have), tostring(m.target))
			eyebrow.Parent = card
			local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Position = UDim2.new(0,10,0,38)
			title.Size = UDim2.new(1,-20,0,54); title.Font = Enum.Font.FredokaOne; title.TextScaled = true
			title.TextColor3 = isPet and Color3.fromRGB(255,190,60) or Color3.fromRGB(255,235,170)
			title.TextTransparency = 1; title.Text = tostring(m.name or "Reward"); title.Parent = card
			local sub = Instance.new("TextLabel"); sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0,10,0,100)
			sub.Size = UDim2.new(1,-20,0,44); sub.Font = Enum.Font.Gotham; sub.TextSize = 15; sub.TextWrapped = true
			sub.TextColor3 = Color3.fromRGB(212,224,255); sub.TextTransparency = 1
			sub.Text = tostring(m.desc or ""); sub.Parent = card
			local IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TW:Create(card, IN, {BackgroundTransparency = 0.05}):Play()
			TW:Create(stroke, IN, {Transparency = 0}):Play()
			for _, l in ipairs({ eyebrow, title, sub }) do TW:Create(l, IN, {TextTransparency = 0}):Play() end
			task.delay(isPet and 7.0 or 5.0, function() -- the secret pet is the big one: leave it up longer
				local OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TW:Create(card, OUT, {BackgroundTransparency = 1, Position = UDim2.new(0.5,0,0.26,0)}):Play()
				TW:Create(stroke, OUT, {Transparency = 1}):Play()
				for _, l in ipairs({ eyebrow, title, sub }) do TW:Create(l, OUT, {TextTransparency = 1}):Play() end
				task.wait(0.6); sg:Destroy()
			end)
		end)
	end
end

-- ===== STARTER PET WELCOME CARD: the server granted a brand-new player their free pet. Tell them they own it and
-- that it levels up, so the gift reads as the start of a progression rather than set dressing. Cosmetic-only.
-- TIMING: a brand-new player is usually watching the one-time Garden Intro cinematic right now, so we HOLD the card
-- until the intro is done -- the server flips the SeenGardenIntro attribute (which replicates here) when the client
-- reports the cutscene finished/skipped. Bounded wait so the card still shows if the intro never runs. =====
do
local StarterPetEvent = RS:WaitForChild("StarterPetEvent", 30) -- s->c: (petId, displayName) free first-join pet granted
if StarterPetEvent then
	StarterPetEvent.OnClientEvent:Connect(function(petId, displayName)
		local name = tostring(displayName or (PETS[petId] and PETS[petId].displayName) or petId)
		-- ANNOUNCE THE CARD BEFORE IT EXISTS. ObjectiveHUD's directions card holds off until this clears, so a
		-- brand-new player is told "here is your pet" and only THEN "here is what to do" -- two cards fighting
		-- for the same first ten seconds is how a new player reads neither. Set at the moment the grant lands
		-- rather than when the card appears, because the card waits out the loading screen and the whole Garden
		-- Intro first: with no "pending" claimed up front, the directions would win that race every time.
		_G.starterWelcome = "pending"
		print(string.format("[StarterPet] granted %s (%s) -- waiting for the intro to finish, then welcoming", name, tostring(petId)))
		task.spawn(function()
			-- (1) THEY MUST ACTUALLY BE PLAYING FIRST. The pet is granted at JOIN, while the player is still sitting
			-- on the loading screen's PLAY button -- and they can sit there as long as they like. The old bound
			-- counted from the GRANT, so a player who took their time pressing PLAY had the card open and expire
			-- behind the loading screen, and never saw their first pet announced at all. Nothing starts counting
			-- until the character is in the world and the loading screen is gone.
			local pg = player:WaitForChild("PlayerGui")
			while not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) do task.wait(0.25) end
			-- (CoreClient destroys the loading screen within a second of the spawn; the bound is only so a screen
			-- that somehow never tears down can't suppress the card forever.)
			local lsWait = 0
			while pg:FindFirstChild("LoadingScreen") and lsWait < 20 do task.wait(0.25); lsWait = lsWait + 0.25 end
			-- (2) THEN wait for the Garden Intro to be DONE -- watched to the end or SKIPPED, both count: the client
			-- fires GardenIntroDoneEvent either way and the server flips SeenGardenIntro, which replicates back here.
			-- A player who never gets the cinematic passes straight through. The bound is only a safety net for an
			-- intro that never reports back, and it can no longer expire while nobody is looking at the screen.
			local waited = 0
			while player:GetAttribute("SeenGardenIntro") ~= true and waited < 300 do task.wait(0.25); waited = waited + 0.25 end
			task.wait(1.0) -- let gameplay settle after the cutscene hands control back
			local TW = game:GetService("TweenService")
			local sg = Instance.new("ScreenGui"); sg.Name="StarterPetWelcome"; sg.ResetOnSpawn=false; sg.DisplayOrder=60; sg.IgnoreGuiInset=true
			sg.Parent = player:WaitForChild("PlayerGui")
			local card = Instance.new("Frame"); card.AnchorPoint=Vector2.new(0.5,0.5); card.Position=UDim2.new(0.5,0,0.3,0)
			card.Size=UDim2.new(0,460,0,150); card.BackgroundColor3=Color3.fromRGB(28,40,24); card.BackgroundTransparency=1; card.Parent=sg
			Instance.new("UICorner", card).CornerRadius = UDim.new(0,18)
			local stroke=Instance.new("UIStroke", card); stroke.Color=Color3.fromRGB(126,200,86); stroke.Thickness=3; stroke.Transparency=1
			local title = Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.new(0,0,0,14); title.Size=UDim2.new(1,0,0,40)
			title.Font=Enum.Font.FredokaOne; title.TextScaled=true; title.TextColor3=Color3.fromRGB(190,240,150); title.TextTransparency=1
			title.Text="\xF0\x9F\x8C\xB1  YOUR FIRST PET!"; title.Parent=card
			local who = Instance.new("TextLabel"); who.BackgroundTransparency=1; who.Position=UDim2.new(0,0,0,58); who.Size=UDim2.new(1,0,0,42)
			who.Font=Enum.Font.FredokaOne; who.TextScaled=true; who.TextColor3=Color3.fromRGB(255,255,255); who.TextTransparency=1
			who.Text=name.." is yours"; who.Parent=card
			local sub = Instance.new("TextLabel"); sub.BackgroundTransparency=1; sub.Position=UDim2.new(0,0,0,104); sub.Size=UDim2.new(1,0,0,32)
			sub.Font=Enum.Font.Gotham; sub.TextScaled=true; sub.TextColor3=Color3.fromRGB(190,205,180); sub.TextTransparency=1
			sub.Text="It follows you everywhere -- fly high to level it up"; sub.Parent=card
			-- MOBILE SCALING. CoreClient's pass is what fits every panel to the screen (phones cap at 0.60, iPads
			-- scale up), but it walks PlayerGui at HUD-build time -- and this card is created ~15s later, when the
			-- intro ends, so the sweep had already run and missed it. On a phone that left the card at its authored
			-- 460x150 while the whole HUD around it sat at 0.60, so it covered half the screen. Re-running the pass
			-- fits it with the identical factor; it REUSES an element's existing UIScale rather than adding a second
			-- one, so this cannot double-shrink the card if the sweep runs again later.
			if _G.applyHudScaling then pcall(_G.applyHudScaling) end
			_G.starterWelcome = "showing"
			local IN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TW:Create(card,   IN, {BackgroundTransparency=0.08}):Play()
			TW:Create(stroke, IN, {Transparency=0}):Play()
			for _, l in ipairs({ title, who, sub }) do TW:Create(l, IN, {TextTransparency=0}):Play() end
			-- celebratory burst on the pet itself so the card and the follower read as the same gift
			local st = petState[petId]; local root = st and st.pet and st.pet.PrimaryPart
			if root then
				local b = Instance.new("ParticleEmitter"); b.Color=ColorSequence.new(Color3.fromRGB(170,240,120)); b.LightEmission=0.8
				b.Lifetime=NumberRange.new(0.5,1.0); b.Speed=NumberRange.new(5,12); b.Size=NumberSequence.new(0.6); b.Rate=0; b.Rotation=NumberRange.new(0,360); b.Parent=root
				b:Emit(45); game:GetService("Debris"):AddItem(b, 1.4)
			end
			task.delay(5.0, function()
				local OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TW:Create(card,   OUT, {BackgroundTransparency=1, Position=UDim2.new(0.5,0,0.26,0)}):Play()
				TW:Create(stroke, OUT, {Transparency=1}):Play()
				for _, l in ipairs({ title, who, sub }) do TW:Create(l, OUT, {TextTransparency=1}):Play() end
				task.wait(0.6); sg:Destroy()
				_G.starterWelcome = "done"   -- ObjectiveHUD's directions card is waiting on exactly this
			end)
			-- Says WHY it fired: "intro done" is the normal path (watched or skipped); "TIMED OUT" means the
			-- cinematic never reported back and the safety net fired, which is worth seeing in a test log.
			print(string.format("[StarterPet] welcome card shown for %s -- in-world, %s (waited %.1fs on the intro)",
				name, player:GetAttribute("SeenGardenIntro") == true and "intro done" or "intro TIMED OUT", waited))
		end)
	end)
end
end -- (do-block: keeps StarterPetEvent off the top-level local budget)

-- ===== STARTUP: handshake for state, then ASK THE SERVER for marker positions and build =====
-- Fire the state handshake FIRST so an OWNED pet spawns immediately (the follower needs no markers).
if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end

-- ===== SELF-HEAL: "the bean buddy sometimes doesn't render" =====
-- Neither half of the join handshake is guaranteed on its own:
--
--   * the PUSH can arrive too early. The server grants the starter pet the moment the save loads -- which is
--     roughly half a second BEFORE this script connects its OnClientEvent handlers. An unheard remote is
--     queued only briefly and then discarded, so on a slow join that push is simply gone.
--   * the PULL can come back empty. PetRequestStateEvent above is one-shot, and the server answers with
--     whatever it knows *at that instant* -- if the save hasn't finished loading, that is "you own nothing"
--     (see the comment on PetRequestStateEvent.OnServerEvent in PetSystem).
--
-- Miss both and st.owns stays false, spawnFollowerPet is never called, and there is no pet -- with no error
-- anywhere to explain it. This watchdog closes the loop from the only side that can actually see the result:
-- it compares what the server says we own against what is really standing in the Workspace, and fixes the
-- difference. That makes it agnostic about WHICH delivery failed -- it also covers a model that gets
-- destroyed later on. Re-asking is capped so a genuinely pet-less player doesn't poll forever; the
-- missing-model check stays live for the whole session because a model can go away at any time.
task.spawn(function()
	local asked, healed = 0, 0
	while true do
		task.wait(3)
		local ownAny, gap = false, nil
		for petId, st in pairs(petState) do
			if st.owns then
				ownAny = true
				-- owned AND equipped, but nothing in the world -> the follower never spawned (or was lost)
				if st.equipped and not (st.pet and st.pet.Parent) then gap = petId end
			end
		end
		if gap then
			healed = healed + 1
			warn(("[Pet][HEAL] %s is owned+equipped but has no follower in Workspace -- rebuilding it (heal #%d)"):format(gap, healed))
			pcall(spawnFollowerPet, gap)
		elseif not ownAny and asked < 20 then
			-- Every player owns at least the starter pet, so "zero owned" this long after joining means the
			-- state never reached us. Ask again. 20 tries x 3s = a one-minute window, then we stop.
			asked = asked + 1
			warn(("[Pet][HEAL] server state still reports 0 owned pets -- re-requesting (try %d/20)"):format(asked))
			if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end
		end
	end
end)

-- Per pet: ASK the server for the marker coordinates (no Workspace searching) and build from them.
for petId, def in pairs(PETS) do
	petState[petId] = petState[petId] or { pieces = {}, collected = {}, egg = nil, pet = nil, built = false, owns = false }
	-- seasonal (garden harvest) and starter (free first-join gift) pets are GRANTED, not quested -- they have no
	-- markers, no pieces and no island world to build. They only ever appear as the equipped follower.
	if def.questType == "seasonal" or def.questType == "starter" or def.questType == "collection" then continue end
	task.spawn(function()
		-- RETRY, DON'T GIVE UP: this used to be one attempt, and every failure path was terminal -- a nil
		-- from the server (its marker scan can time out at 90s on a slow start), a failed invoke, or the
		-- remote itself missing all meant that pet's collectibles never existed for the whole session, with
		-- only a warn to show for it. That IS the "broccoli / reels / coconuts randomly don't render" bug's
		-- other half. Retries with growing gaps cover a slow server scan; the cap keeps a genuinely broken
		-- marker set (already loudly warned server-side) from polling forever.
		local positions
		for attempt = 1, 6 do
			if not PetGetMarkers then -- late re-acquire: the 30s WaitForChild at the top may have timed out
				PetGetMarkers = RS:FindFirstChild("PetGetMarkers")
			end
			if PetGetMarkers then
				local ok, result = pcall(function() return PetGetMarkers:InvokeServer(petId) end)
				if ok and type(result) == "table" then
					positions = result
					if attempt > 1 then print("[Pet][DIAG] marker positions for "..petId.." arrived on retry #"..attempt) end
					break
				end
				warn("[Pet][DIAG] PetGetMarkers attempt "..attempt.."/6 for "..petId.." failed ("
					..(ok and "server had no positions yet" or tostring(result))..")"..(attempt < 6 and " -- retrying" or " -- giving up"))
			else
				warn("[Pet][DIAG] PetGetMarkers RemoteFunction still missing (attempt "..attempt.."/6) for "..petId)
			end
			if attempt < 6 then task.wait(8 * attempt) end -- 8,16,24,32,40s between tries (~2 min window on top of the server's own wait)
		end
		if not positions then return end
		local pp = positions.pieces or {}
		local function v(p) return (typeof(p) == "Vector3") and string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "nil" end
		print("[Pet][DIAG] received positions: piece1="..v(pp[1]).." piece2="..v(pp[2]).." piece3="..v(pp[3]).." egg="..v(positions.egg))
		buildPetWorld(petId, def, positions)
		-- the world just built with every piece HIDDEN -- re-apply the latest server state so uncollected
		-- pieces reveal NOW instead of waiting for a state push that may never come (see _G.petWorldBuilt)
		if _G.petWorldBuilt then _G.petWorldBuilt() end
	end)
end

-- re-handshake on respawn (cheap; keeps things in sync if the server pushed state while we were dead)
player.CharacterAdded:Connect(function()
	task.wait(1)
	if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end
end)

-- ===== MYSTERIOUS LANDING HINT: when the player is grounded on a pet-quest island and hasn't
-- started/finished it, flash the subtle hint ONCE per visit. Island anchor = the egg coordinate
-- (server-provided, on the island). Resets when they leave so it can re-show on a later visit.
task.spawn(function()
	while true do
		task.wait(0.5)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		for petId, def in pairs(PETS) do
			local st = petState[petId]
			local anchor = st and (st.hintAnchor or st.eggPos) -- coconut: anchor the on-landing hint at a COCONUT (island), not the cave chest
			if hrp and anchor then
				local dx, dz = hrp.Position.X - anchor.X, hrp.Position.Z - anchor.Z
				local inArea = math.sqrt(dx*dx + dz*dz) < 200 and math.abs(hrp.Position.Y - anchor.Y) < 90
				local grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
				if inArea and grounded and not onIsland[petId] then
					onIsland[petId] = true
					pcall(function() PetQuestDiscovered:FireServer(petId) end) -- record the quest as DISCOVERED (server dedups + persists)
					-- (landing card removed: the big "??? Quest" flashHint card no longer shows on landing.)
					-- Reveal the island-bound tracker only AFTER the island arrival intro finishes, so the
					-- top-center tracker isn't covered by the "You reached ..." banner. Wait for the arrival
					-- frame to hide (re-visits = no intro -> shows quickly), then show if still on the island.
					task.spawn(function()
						task.wait(0.6) -- let the arrival intro (if any) appear first
						for _ = 1, 40 do
							local af = _G.gui and _G.gui.arrivalFrame
							if not (af and af.Visible) then break end
							task.wait(0.15)
						end
						if onIsland[petId] then refreshQuestHUD() end
					end)
				elseif not inArea and onIsland[petId] then
					onIsland[petId] = false
					refreshQuestHUD() -- left the island: drop the AVAILABLE card (a started counter stays up)
				end
			end
		end
	end
end)

-- ===== EGG POINTER + GROUND TRAIL: when the active pet's quest is COMPLETE (all pieces found, egg available,
-- not yet hatched), two things guide the player to it:
--   * the on-screen arrow (clamped to the screen edge when the egg is off-screen or behind you), and
--   * the GREEN CHEVRON TRAIL on the ground -- the same runway that walks a new player to the Gardener on Bean
--     Farm. An arrow tells you WHICH WAY; the trail tells you HOW TO GET THERE, which on the later islands (over
--     a lake, up a cliff, behind a projector screen) is a completely different question.
--
-- This works for EVERY pet, not just the broccoli one, because the condition below is generic: it reads whatever
-- quest is active out of petState. Broccoli's 3/3 pieces, the popcorn sheep's 6/6 film reels, the burrito
-- armadillo's dig trail -- each sets eggPos and its own total, and each lights the trail the moment it completes.
RunService.RenderStepped:Connect(function()
	local petId = activeUiPet
	local st = petId and petState[petId]
	if not st or st.owns or not st.eggPos or (st.uiFound or 0) < (st.total or 3) then
		pointer.Visible = false
		-- Quest not complete (or already hatched) -> put the trail away. Cleared every frame rather than once, so
		-- hatching, switching pets, or a fresh inventory push can never leave a stale trail pointing at nothing.
		if _G.guideTrailClear then _G.guideTrailClear() end
		return
	end
	local target = (st.pointTarget or st.eggPos) + Vector3.new(0, 2.3, 0) -- film-reels: points at the projector until the show, then the egg

	-- Lay the chevron runway to the egg. Fed the RAW ground position, not `target` (which is lifted 2.3 studs to
	-- float the on-screen arrow above the egg) -- the trail rays down onto the floor and a lifted target would
	-- make it aim at a point in the air.
	if _G.guideTrailTo then _G.guideTrailTo(st.pointTarget or st.eggPos) end
	local vp = Camera:WorldToViewportPoint(target)
	local vs = Camera.ViewportSize
	local cx, cy = vs.X * 0.5, vs.Y * 0.5
	if vp.Z > 0 and vp.X >= 0 and vp.X <= vs.X and vp.Y >= 0 and vp.Y <= vs.Y then
		pointer.Position = UDim2.new(0, vp.X, 0, math.max(vp.Y - 64, 36)) -- hover above the egg
		pointer.Rotation = 90 -- "➤" rotated to point DOWN at it
	else
		local dx, dy
		if vp.Z > 0 then dx, dy = vp.X - cx, vp.Y - cy else dx, dy = cx - vp.X, cy - vp.Y end -- behind camera -> invert
		local mag = math.sqrt(dx*dx + dy*dy); if mag < 1 then dx, dy, mag = 0, -1, 1 end
		dx, dy = dx/mag, dy/mag
		pointer.Position = UDim2.new(0, cx + dx * (cx - 70), 0, cy + dy * (cy - 70)) -- clamp to screen edge
		pointer.Rotation = math.deg(math.atan2(dy, dx)) -- "➤" points along +X at rotation 0
	end
	pointer.Visible = true
end)

-- ============================================================================================
-- PET INVENTORY GUI -- storage (grid of OWNED pets) + EQUIP toggle (one at a time) + a wired-but-stubbed
-- LEVELING/UPGRADE framework (achievement progress OR Robux). Server-authoritative (PetInventoryEvent);
-- the buttons just fire remotes. Cosmetic-only. Data-driven from the inventory table so future pets/tiers
-- plug in with no GUI changes.
-- ============================================================================================
-- Styled to MATCH the game's existing GUI (Shop / former Daily popup): a blue panel (25,90,185) with a
-- white stroke + rounded corners, a darker-blue header (15,60,140) with a GOLD GothamBold title + white
-- Gotham subtitle, and a red close button. There is NO separate paw button here anymore -- the ONE pet
-- button is the repurposed HUD button (CoreClient), which toggles this panel via a BindableEvent.
local pg = player:WaitForChild("PlayerGui")
local invGui = Instance.new("ScreenGui")
invGui.Name = "PetInventoryUI"; invGui.ResetOnSpawn = false; invGui.DisplayOrder = 100 -- EXACT same ScreenGui settings as the SHOP (PremiumShopGui): DisplayOrder 100, no IgnoreGuiInset
-- HANDS OFF THE TEXT. CoreClient runs two blanket passes that force TextScaled=true (and Visible=true) on every
-- label in every ScreenGui. Every label in this hub is authored with a deliberate TextSize -- 18pt headings, 12pt
-- captions, 9pt badges -- and TextScaled THROWS THAT AWAY, inflating each one to fill its frame. That is why the
-- REWARDS tab's text turned huge and overlapping after switching tabs: the overlay is rebuilt with correct sizes,
-- then the next sweep (viewport change / respawn / another menu calling _G.applyHudScaling) overwrites them all.
-- This attribute makes both sweeps skip the entire hub, including overlays built long after this line runs.
invGui:SetAttribute("NoTextSweep", true)
invGui.Parent = pg
local function uicorner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function uistroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t or 2; s.Parent = o; return s end

-- INVISIBLE click-block behind the panel (NO dark film): fully transparent + Active so the rest of the
-- HUD stays VISIBLE but non-interactable while the panel is open -- same treatment as the food shop.
local dim = Instance.new("Frame"); dim.Name = "Dim"; dim.Size = UDim2.new(1,0,1,0); dim.BackgroundColor3 = Color3.new(0,0,0)
-- Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch). The
-- panel itself is Active=true so panel clicks don't leak to the HUD behind it.
dim.BackgroundTransparency = 1; dim.Visible = false; dim.Active = false; dim.Parent = invGui

-- PANEL -- EXACT same Size + Position + AnchorPoint as the SHOP menu's FINAL layout (PremiumShopGui's premPanel,
-- after its layout pass): 700 x 520 fixed, centered, nudged up 45px. No UIScale/UISizeConstraint/UIAspectRatioConstraint on the Shop.
local panel = Instance.new("Frame"); panel.Name = "Panel"
panel.Size = UDim2.new(0,700,0,520); panel.Position = UDim2.new(0.5,0,0.5,-45); panel.AnchorPoint = Vector2.new(0.5,0.5) -- copied verbatim from the SHOP panel's final values (do NOT recompute / no responsive fit)
panel.BackgroundColor3 = Color3.fromRGB(25,90,185); panel.ClipsDescendants = true; panel.Visible = false; panel.Active = true; panel.Parent = invGui -- Active=true so panel clicks don't leak to the HUD behind it
uicorner(panel, 18); uistroke(panel, Color3.new(1,1,1), 3)

-- HEADER
local header = Instance.new("Frame"); header.Size = UDim2.new(1,0,0,60); header.BackgroundColor3 = Color3.fromRGB(15,60,140); header.Parent = panel
uicorner(header, 18)
local title = Instance.new("TextLabel"); title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold; title.TextSize = 26
title.TextColor3 = Color3.fromRGB(255,215,0); title.Text = "\xF0\x9F\x90\xBE PET HUB"; title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.new(1,-60,0,34); title.Position = UDim2.new(0,14,0,5); title.Parent = header
uistroke(title, Color3.new(0,0,0), 2)
local subtitle = Instance.new("TextLabel"); subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
-- The subtitle is now the PETS-UNLOCKED progress readout. Every page in the hub shows the same header, so
-- this and the token chip beside it are the two numbers that are always on screen wherever you navigate.
subtitle.TextColor3 = Color3.new(1,1,1); subtitle.Text = "0 / 0 pets unlocked"; subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Size = UDim2.new(0,300,0,16); subtitle.Position = UDim2.new(0,14,0,40); subtitle.Parent = header
subtitle.Name = "HubProgress"

-- TOKEN COUNTER, sat left of the close button. Same chip treatment the crate panel uses for its own token
-- readout, so the two panels read as one interface when you tab between them.
do
	local tokChip = Instance.new("Frame"); tokChip.Name = "HubTokens"
	tokChip.Size = UDim2.new(0,126,0,28); tokChip.Position = UDim2.new(1,-182,0,16)
	tokChip.BackgroundColor3 = Color3.fromRGB(12,44,104); tokChip.Parent = header
	uicorner(tokChip, 8); uistroke(tokChip, Color3.fromRGB(255,215,0), 1.5)
	local tl = Instance.new("TextLabel"); tl.Name = "Value"; tl.BackgroundTransparency = 1
	tl.Size = UDim2.new(1,-10,1,0); tl.Position = UDim2.new(0,5,0,0)
	tl.Font = Enum.Font.GothamBold; tl.TextSize = 14; tl.TextColor3 = Color3.fromRGB(255,215,0)
	tl.Text = "\xF0\x9F\x92\xB0 0"; tl.Parent = tokChip
	-- CoreClient force-sets TextScaled on every PlayerGui TextLabel, so cap it here or a long balance grows
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 14; c.Parent = tl; tl.TextScaled = true end
end
local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-48,0,10)
closeBtn.BackgroundColor3 = Color3.fromRGB(220,50,50); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22 -- plain "X" matches the other GUIs' close buttons
closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Parent = header
uicorner(closeBtn, 8); uistroke(closeBtn, Color3.new(0,0,0), 2)

-- ===== NAVIGATION: the five pages of the hub =====
-- One horizontal bar directly under the header, in the SAME geometry the crate panel already uses for its
-- own tabs (bar at y=66, 38 tall, five 129px buttons 8px apart: 5*129 + 4*8 = 677 of the 680 available).
-- Identical on purpose: CRATES and TOKENS live in the other panel, and matching the bar pixel-for-pixel is
-- what makes tabbing between the two read as one interface instead of two menus swapping places.
--
-- Wrapped in a do-block and hung off _G.PetHub because this file sits at 193 of Luau's 200 locals per
-- scope -- one local over and the WHOLE script silently fails to compile, taking every pet handler with it.
_G.PetHub = _G.PetHub or {}
do
	_G.PetHub.navButtons = {}
	-- SKIN PROGRESS for one pet, shared by the owned and locked card builders. Counts DISTINCT skins (a Neon
	-- Fox and a Neon+Sparkly Fox are one skin owned twice, not two), +1 for the Default look every pet has from
	-- the start -- the same rule the Pet Skins page uses, so the two readouts can never disagree.
	_G.PetHub.skinCount = function(petId)
		local total = (_G.petSkinTotal and _G.petSkinTotal()) or 0
		local seen, n = {}, 0
		if _G.petSkinState then
			for skey, count in pairs(_G.petSkinState.skins or {}) do
				local kp, ks = string.match(tostring(skey), "^([^|]+)|([^|]*)")
				if kp == petId and ks and ks ~= "" and (tonumber(count) or 0) > 0 and not seen[ks] then
					seen[ks] = true; n = n + 1
				end
			end
		end
		return n + 1, total
	end
	-- HEADER READOUTS, defined HERE and not down with the router. The pet grid calls setProgress while the
	-- script is still LOADING -- long before the router block runs -- so defining them late meant the very
	-- first build found nil and the header sat at its placeholder until something happened to rebuild it.
	_G.PetHub.setProgress = function(owned, total)
		local lbl = header:FindFirstChild("HubProgress")
		if lbl then lbl.Text = tostring(owned) .. " / " .. tostring(total) .. " pets unlocked" end
	end
	_G.PetHub.setTokens = function(n)
		local chip = header:FindFirstChild("HubTokens")
		local lbl = chip and chip:FindFirstChild("Value")
		if lbl then lbl.Text = "\xF0\x9F\x92\xB0 " .. tostring(math.floor(tonumber(n) or 0)) end
	end
	-- SkinCrateClient calls this whenever the server pushes a new balance, so the hub header and the crate
	-- panel can never show two different token counts.
	_G.petHubTokensChanged = function(n) pcall(_G.PetHub.setTokens, n) end
	local bar = Instance.new("Frame"); bar.Name = "HubNav"
	bar.Size = UDim2.new(1,-20,0,38); bar.Position = UDim2.new(0,10,0,66)
	bar.BackgroundTransparency = 1; bar.Parent = panel
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0,8); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = bar
	-- FOUR tabs: pets and crates are ONE hub again, entered through the PETS rail button. The
	-- de-overwhelm vs the old five-tab bar is TOKENS -- no longer top-level, it lives inside the
	-- CRATES page (its shop, not a collection). CRATES hands off to the crate panel via showPage,
	-- which draws the SAME four-tab bar, so the swap reads as one menu changing pages.
	-- 163 wide: four tabs + three 8px gaps fill the same 676px the five 129s did.
	for i, t in ipairs({
		{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS"   },
		{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" },
		{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE"  },
		{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS" },
	}) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0,163,1,0); b.LayoutOrder = i
		b.BackgroundColor3 = Color3.fromRGB(18,66,150); b.Text = t.label
		b.Font = Enum.Font.FredokaOne; b.TextSize = 15; b.TextScaled = true
		b.TextColor3 = Color3.fromRGB(255,215,0); b.Parent = bar
		uicorner(b, 10); uistroke(b, Color3.new(1,1,1), 1.5)
		-- HANDS OFF: THESE TABS DRIVE THEIR OWN FILL, TEXT AND OUTLINE.
		-- syncNav below paints selected as dark-on-gold with a 2.5px gold-brown outline and unselected as
		-- gold-on-blue with a 1.5px white one -- the colour IS how you tell which tab you're on.
		-- ButtonTextStyle's legibility sweep would repaint all four cream with a 2px dark-blue outline and
		-- darken the fill from whichever state the tab happened to be in the first time it was seen, so the
		-- selected tab stopped looking selected and the four tabs stopped matching each other. BTS_Skip is
		-- that sweep's documented opt-out for exactly this: a button whose colour carries meaning.
		b:SetAttribute("BTS_Skip", true)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = b end
		_G.PetHub.navButtons[t.id] = b
		-- showPage is defined much further down (it needs the trade + quest overlays to exist first). Looked
		-- up at CLICK time, not now, so the ordering is fine.
		b.MouseButton1Click:Connect(function()
			if _G.playUIClick then pcall(_G.playUIClick) end
			if _G.PetHub.showPage then _G.PetHub.showPage(t.id) end
		end)
	end
end

-- ===== TWO SECTIONS: LEFT = PETS (owned cards + locked "?" slots), RIGHT = QUESTS (discovered quests) =====
local function makeSection(x, w, titleText)
	local sec = Instance.new("Frame"); sec.Size = UDim2.new(0,w,1,-74); sec.Position = UDim2.new(0,x,0,68)
	sec.BackgroundColor3 = Color3.fromRGB(18,66,150); sec.BackgroundTransparency = 0.25; sec.Parent = panel
	uicorner(sec, 12); uistroke(sec, Color3.fromRGB(10,40,100), 2)
	local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,-12,0,22); t.Position = UDim2.new(0,8,0,6)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 16; t.TextColor3 = Color3.fromRGB(255,215,0)
	t.TextXAlignment = Enum.TextXAlignment.Left; t.Text = titleText; t.Parent = sec
	local sc = Instance.new("ScrollingFrame"); sc.Size = UDim2.new(1,-12,1,-34); sc.Position = UDim2.new(0,6,0,30)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 6; sc.ScrollBarImageColor3 = Color3.fromRGB(255,215,0)
	sc.CanvasSize = UDim2.new(0,0,0,0); sc.Parent = sec
	return sec, sc
end
-- PETS now fills the FULL panel width (the pets are the star) -> 2 BIG cards per row with large 3D pictures.
local petsSection, petsScroll = makeSection(12, 676, "\xF0\x9F\x90\xBe PETS")
-- Panel now uses the SHOP's scale-based size (0.9 x 0.85), so make this section fill it responsively (scale width,
-- like the quests overlay) instead of a fixed 676px -- the centered grid then sits properly at any panel width.
-- y=110, not 68: the five-tab nav bar now owns 66..104 directly under the header.
petsSection.Size = UDim2.new(1, -24, 1, -116); petsSection.Position = UDim2.new(0, 12, 0, 110)
local petsGrid = Instance.new("UIGridLayout"); petsGrid.CellSize = UDim2.new(0,322,0,252); petsGrid.CellPadding = UDim2.new(0,10,0,12)
petsGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center; petsGrid.Parent = petsScroll
-- small TOP/side padding so the first row of pet cards isn't clipped at the scroll's top edge. Wrapped in a
-- do-block on purpose: the `pad` local is block-scoped (freed immediately), so it adds NO persistent
-- module-scope local -- avoiding Luau's 200-local main-chunk limit that broke the earlier all-at-once tries.
do
	local pad = Instance.new("UIPadding"); pad.Name = "PetsTopPad"
	pad.PaddingTop = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,4); pad.PaddingRight = UDim.new(0,4)
	pad.Parent = petsScroll
end

-- QUEST INFO is tucked into a small COLLAPSIBLE overlay (hidden until the header "QUESTS" tab is tapped), so
-- it no longer takes prime space away from the pets. Same look as the trade overlay.
local questsOverlay = Instance.new("Frame"); questsOverlay.Name = "QuestsOverlay"; questsOverlay.Size = UDim2.new(1,-24,1,-116); questsOverlay.Position = UDim2.new(0,12,0,110)
questsOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); questsOverlay.Visible = false; questsOverlay.Parent = panel; uicorner(questsOverlay, 12); uistroke(questsOverlay, Color3.fromRGB(10,40,100), 2)
local qoTitle = Instance.new("TextLabel"); qoTitle.Size = UDim2.new(1,-120,0,28); qoTitle.Position = UDim2.new(0,12,0,8); qoTitle.BackgroundTransparency = 1
qoTitle.Font = Enum.Font.GothamBold; qoTitle.TextSize = 18; qoTitle.TextColor3 = Color3.fromRGB(255,215,0); qoTitle.TextXAlignment = Enum.TextXAlignment.Left; qoTitle.Text = "\xF0\x9F\x97\xBA Pet Quests"; qoTitle.Parent = questsOverlay
local qoBack = Instance.new("TextButton"); qoBack.Size = UDim2.new(0,100,0,28); qoBack.Position = UDim2.new(1,-108,0,8); qoBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
qoBack.Font = Enum.Font.GothamBold; qoBack.TextSize = 13; qoBack.TextColor3 = Color3.new(1,1,1); qoBack.Text = "\xE2\x97\x80 Pets"; qoBack.Parent = questsOverlay; uicorner(qoBack, 8)
local questsScroll = Instance.new("ScrollingFrame"); questsScroll.Size = UDim2.new(1,-16,1,-46); questsScroll.Position = UDim2.new(0,8,0,42); questsScroll.BackgroundTransparency = 1; questsScroll.BorderSizePixel = 0
questsScroll.ScrollBarThickness = 6; questsScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); questsScroll.CanvasSize = UDim2.new(0,0,0,0); questsScroll.Parent = questsOverlay
local questsList = Instance.new("UIListLayout"); questsList.Padding = UDim.new(0,8); questsList.SortOrder = Enum.SortOrder.LayoutOrder; questsList.Parent = questsScroll
local questsEmpty = Instance.new("TextLabel"); questsEmpty.Size = UDim2.new(1,-24,0,70); questsEmpty.Position = UDim2.new(0,12,0,46)
questsEmpty.BackgroundTransparency = 1; questsEmpty.Font = Enum.Font.Gotham; questsEmpty.TextSize = 14; questsEmpty.TextWrapped = true
questsEmpty.TextColor3 = Color3.fromRGB(200,220,255); questsEmpty.Text = "Land on islands to discover pet quests!"; questsEmpty.Visible = false; questsEmpty.Parent = questsOverlay

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: shared manager (one instance across client scripts, via _G). Guarded
-- factory so whichever client script loads first creates it. The Pet Hub joins the "only one open" group. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD (gut pill + gas meter + fart button all live in BottomStackGui)
		local lp = game:GetService("Players").LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
		mgr.setHud(false)                                                       -- a main menu is now open -> hide the bottom HUD (Shop/Pet Hub/Seasonal Pets all route through here)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end                         -- last menu closed -> restore the bottom HUD
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) -- full-hide the Pet Hub

local latestInv = { owned = {}, quests = {}, catalog = {}, totalPets = 0 }
-- Defensive de-dup: multiple StyleLinks under CoreGui cause "undefined behavior" GUI warnings/glitches. We
-- never create StyleLinks, but if extras appear we keep ONE and drop the rest. Guarded (CoreGui may be
-- write-protected for non-core scripts -> the pcall just no-ops then). Cosmetic/safety only.
local function dedupeStyleLinks()
	pcall(function()
		local cg = game:GetService("CoreGui")
		local seen = false
		for _, c in ipairs(cg:GetChildren()) do
			if c:IsA("StyleLink") then
				if seen then c:Destroy() else seen = true end
			end
		end
	end)
end
dedupeStyleLinks()

-- Open/close the Pet Hub ROBUSTLY. The panel is shown/hidden FIRST (so the menu state is always correct),
-- then the manager-notify + counting/logging run inside a pcall so a single error (e.g. while building the
-- heavier 3D pet icons) can NEVER leave the Hub stuck unable to open. Errors are printed, not swallowed.
local function openPanel(open)
	open = open and true or false
	local okShow = pcall(function() panel.Visible = open; dim.Visible = open end) -- SHOW/HIDE FIRST, no matter what
	if not okShow then warn("[PetInv] ERROR opening/building: panel reference invalid (could not set Visible)"); return end
	local ok, err = pcall(function()
		if open then
			pcall(function() questsOverlay.Visible = false end) -- a fresh open lands on the pet cards, not a stuck sub-tab
			-- also drop any VIEW MORE detail card. Killed BY NAME rather than through _G.PetHub.hideDetail(), which is
			-- defined further down this file -- openPanel can't see it, and forward-declaring it would burn one of
			-- the few module-scope locals this file has left before Luau's 200-per-scope ceiling.
			pcall(function() local pd = panel:FindFirstChild("PetDetailOverlay"); if pd then pd:Destroy() end end)
			dedupeStyleLinks() -- clean up any extra StyleLinks each open (addresses the CoreGui warning)
			-- A fresh open always lands on PETS, and the nav has to SAY so. Without this the bar keeps whatever
			-- tab was lit when you last closed, while the panel actually shows the pet grid -- the exact drift the
			-- router exists to prevent. Page state is reset just above; this makes the highlight agree.
			pcall(function() _G.PetHub.activePage = "pets"; _G.PetHub.syncNav() end)
			-- header token chip: show the balance the crate panel last had from the server
			pcall(function() _G.PetHub.setTokens(_G.crateTokenBalance or 0) end)
			_G.MainMenuManager.notifyOpened("PetInv") -- direct switch: close any other open main menu first
			local nOwned = 0; for _ in pairs(latestInv.owned or {}) do nOwned = nOwned + 1 end
			local nQuests = 0; for _ in pairs(latestInv.quests or {}) do nQuests = nQuests + 1 end
			print("[PetInv] inventory opened - owned: " .. nOwned .. ", quests discovered: " .. nQuests)
			if _G.applyHudScaling then _G.applyHudScaling() end -- re-apply the SHOP's identical UIScale so this panel matches the Shop size exactly
			task.defer(function() print("[UIFix] PetHub AbsoluteSize=" .. tostring(panel.AbsoluteSize) .. " AbsolutePosition=" .. tostring(panel.AbsolutePosition)) end) -- resolved on-screen size, to compare vs the SHOP
		else
			_G.MainMenuManager.notifyClosed("PetInv")
			pcall(function() questsOverlay.Visible = false end) -- reset sub-overlays on close so it re-opens clean
			pcall(function() local pd = panel:FindFirstChild("PetDetailOverlay"); if pd then pd:Destroy() end end)
		end
	end)
	if not ok then
		warn("[PetInv] ERROR opening/building: " .. tostring(err))
		-- SELF-HEAL the manager so a failed open can never leave it stuck (every later click still works):
		-- if we were opening, the panel IS shown so claim "PetInv"; otherwise clear it.
		pcall(function()
			if open then _G.MainMenuManager.current = "PetInv" else _G.MainMenuManager.notifyClosed("PetInv") end
		end)
	end
end
closeBtn.MouseButton1Click:Connect(function() openPanel(false) end)
-- NOTE: there is deliberately NO click-outside-to-close handler. `dim` spans the whole screen, so a click
-- anywhere off the panel -- including one that falls through to a HUD button behind it -- used to slam the Hub
-- shut, which made the menu feel like it was closing at random. The Hub now closes ONLY on an explicit action:
-- the X button, the pet HUD button toggling it off, or MainMenuManager closing it because another menu opened.
-- the ONE pet button (the repurposed daily-rewards HUD button in CoreClient) toggles this panel via here
local toggleEvent = Instance.new("BindableEvent"); toggleEvent.Name = "PetInvToggle"; toggleEvent.Parent = pg
toggleEvent.Event:Connect(function()
	local current = _G.MainMenuManager and _G.MainMenuManager.current
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end) -- read actual visibility safely
	print("[MenuMgr] PetInv click - current open menu = " .. tostring(current) .. ", panel open = " .. tostring(isOpen) .. " -> " .. (isOpen and "closing" or "opening (proceeding)"))
	openPanel(not isOpen)
end)
-- THE UNAMBIGUOUS DOOR. Buttons that can should call this instead of firing a found event -- see below.
-- On _G, not a local: this file sits at the edge of Luau's 200-locals ceiling.
_G.togglePetHub = function()
	local isOpen = false; pcall(function() isOpen = panel.Visible == true end)
	openPanel(not isOpen)
end
-- ===== KILL THE IMPOSTOR =====
-- A copy of PetHub_AllInOne (the standalone export kit) is baked into the place. It builds its OWN
-- ScreenGui named PetInventoryUI and its OWN PetInvToggle BindableEvent -- a complete second Pet Hub.
-- Every button that opens the hub does FindFirstChild("PetInvToggle"), which returns whichever of the
-- two events sits first in PlayerGui -- a load-order race. When the kit's copy won, the paw button
-- toggled the kit's dead panel and "the pet menu stopped opening". So: any same-named event or hub gui
-- that is not OURS is destroyed/retired, at load AND whenever one appears later (the kit can load after
-- us), and our MainMenuManager registration is re-asserted since the kit overwrites that too.
-- The real fix is deleting PetHub_AllInOne inside Studio -- this keeps the game correct until then.
do
	local ownGui = panel:FindFirstAncestorOfClass("ScreenGui")
	local function killImpostor(ch)
		if ch == toggleEvent or ch == ownGui then return end
		if ch:IsA("BindableEvent") and ch.Name == "PetInvToggle" then
			ch:Destroy()
			warn("[PetInv] destroyed a STALE duplicate PetInvToggle (baked-in PetHub_AllInOne kit -- delete it in Studio)")
			pcall(function() _G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) end)
		elseif ch:IsA("ScreenGui") and ch.Name == "PetInventoryUI" then
			ch.Enabled = false
			ch.Name = "PetInventoryUI_STALE" -- renamed so no finder (BACK, guards, verify nets) can grab it
			warn("[PetInv] retired a STALE duplicate PetInventoryUI gui (baked-in PetHub_AllInOne kit -- delete it in Studio)")
			pcall(function() _G.MainMenuManager.register("PetInv", function() panel.Visible = false; dim.Visible = false end) end)
		end
	end
	for _, ch in ipairs(pg:GetChildren()) do killImpostor(ch) end
	pg.ChildAdded:Connect(function(ch) task.defer(killImpostor, ch) end)
end

-- ===== 3D VIEWPORT ICONS: each owned pet card's icon is a CLONE of the real pet model at its current-level
-- look (accessories/colors/variant), slowly auto-rotating. Clones never touch the real follow pets. =====
local iconSpins = {} -- list of { model } icon clones to slowly spin (only while the menu is open)
local function stripIconEffects(model) -- drop particle/glow/orbit effects (don't render in a viewport / would clutter it); keep body + accessories
	for _, d in ipairs(model:GetDescendants()) do
		local n = d.Name
		if n=="PetOrb" or n=="PetRing" or n=="PetPulse" or n=="PetSparkle" or n=="PetAura" or n=="PetAuraLight"
			or n=="PetBurst" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetRareFX" or n=="PetRareLight"
			or n=="LevelGlow" or n=="LevelTag" then d:Destroy() end
	end
end
-- a CLONE of a pet at its current-level look (same accessories/colors/variant as the real pet) for the icon.
local function buildIconModel(petId, level, isRare)
	local tn = PET_TEMPLATE_NAME[petId]
	local template = tn and RS:FindFirstChild(tn)
	local model = template and template:Clone()
	if not model then local fb = PET_FALLBACK[petId]; model = (fb and fb(0.9)) or buildBroccoliDinoFallback(0.9) end
	model.Name = petId .. "Icon"
	if not model.PrimaryPart then model.PrimaryPart = model:FindFirstChild("Root") end
	petAnims[model] = { s = 0.9, parts = {}, t = 0 } -- temp entry so the accessory builder can attach; removed right after (icon is static)
	pcall(function() applyLevelVisual(model, level or 1, petId, isRare, true) end) -- LITE: size + accessories + rare recolor only (no heavy FX)
	stripIconEffects(model)
	petFX[model] = nil; petAnims[model] = nil -- detach from the global anim/FX loops (icon is a static, separately-spun clone)
	return model
end
-- DEFERRED ICON BUILDER. The heavy 3D clone build (clone template + apply lvl-25/rare visuals + frame the
-- camera) is NOT done synchronously -- doing 5 maxed/rare pets at once (especially right after /rarepets,
-- alongside the rare fanfare + follow-pet spawn) was a single huge burst that could exhaust execution time
-- and HANG the PetFollow script, severing its connections so the menu's toggle handler never ran again.
-- Instead each icon is queued and built ONE-PER-FRAME by a single worker, each in its OWN pcall, with a paw
-- placeholder shown until it's ready (or kept as the fallback if that one icon fails). One bad/maxed/rare
-- icon can NEVER stall the others or the menu.
local iconQueue = {}            -- pending { vp, cam, ph, petId, level, isRare, skin, trait }
local iconWorkerActive = false
local function startIconWorker()
	if iconWorkerActive then return end
	iconWorkerActive = true
	task.spawn(function()
		while true do
			local req = table.remove(iconQueue, 1)
			if not req then break end
			if req.vp.Parent then -- skip viewports a later rebuild already destroyed
				local ok, model = pcall(buildIconModel, req.petId, req.level, req.isRare)
				if ok and model and req.vp.Parent then
					local okFrame = pcall(function()
						-- CLEAR FIRST. Parenting straight in meant a viewport populated twice kept BOTH models, overlapping
						-- at the origin -- the doubled pet with two sets of eyes. Everything that is not the Camera or the
						-- paw placeholder is ours, so this is safe to run on every refresh.
						for _, old in ipairs(req.vp:GetChildren()) do
							if old:IsA("Model") or old:IsA("BasePart") then old:Destroy() end
						end
						-- Retire any orbit driver still pointing at this viewport: two entries would drive one camera from
						-- different start angles and fight each other every frame.
						for si = #iconSpins, 1, -1 do
							if iconSpins[si].vp == req.vp then table.remove(iconSpins, si) end
						end
						-- PAINT THE SKIN before framing the camera. PetSkinLook owns the look (it is the same renderer the
						-- crate reel and the world pet use), and it deliberately does NOT record these into its `painted`
						-- table -- so a server push repainting the EQUIPPED skin can never reach in and recolour these cards.
						if req.skin and _G.applyPetSkinPreview then
							pcall(_G.applyPetSkinPreview, model, req.skin, req.trait, true)
						end
						model:PivotTo(CFrame.new()) -- root at origin, ONCE -- the model never moves again (see below)
						model.Parent = req.vp
						local cf, size = model:GetBoundingBox()
						local maxe = math.max(size.X, size.Y, size.Z, 1)
						local center = cf.Position
						local dir = Vector3.new(0.8, 0.5, 0.55).Unit -- 3/4 front view (pets face +X), slightly above
						local off = dir * (maxe * 1.45 + 1)          -- camera offset from the pet; distance fits any size
						req.cam.CFrame = CFrame.lookAt(center + off, center)
						-- SPIN BY ORBITING THE CAMERA, not by pivoting the model. Pivoting rewrote the CFrame of every
						-- part of every pet (15-30 parts x ~10 icons) every frame, which is what made the little
						-- pictures stutter. Orbiting is ONE CFrame write per icon per frame and is perfectly smooth.
						-- Cache the orbit here so the loop does no per-frame maths beyond a sin/cos:
						--   radius/height = the same 3/4 framing, decomposed; a0 = the angle it started at, so the
						--   rotation begins exactly where the static shot was pointing (no jump on the first frame).
						iconSpins[#iconSpins+1] = {
							vp = req.vp, cam = req.cam, center = center,
							radius = math.sqrt(off.X * off.X + off.Z * off.Z),
							height = off.Y,
							a0     = math.atan2(off.Z, off.X),
						}
					end)
					if okFrame then if req.ph then req.ph.Visible = false end
					else warn("[PetInv] icon frame failed for " .. tostring(req.petId) .. " (keeping placeholder)") end
				else
					if model then pcall(function() model:Destroy() end) end
					if not ok then warn("[PetInv] ERROR building icon for " .. tostring(req.petId) .. ": " .. tostring(model) .. " (keeping placeholder)") end
				end
			end
			task.wait() -- one icon per frame -> no single heavy synchronous burst (never exhausts execution time)
		end
		iconWorkerActive = false
		if #iconQueue > 0 then startIconWorker() end -- close the enqueue-just-as-we-exit race
	end)
end
-- (sizeU/posU/anchorV optional: the menu cards pass a BIG size; the trade window reuses this for both offers)
-- Creates the ViewportFrame + a paw placeholder IMMEDIATELY (cheap) and QUEUES the heavy 3D build (see above).
-- `skinId`/`traitId` are OPTIONAL. Passed, the icon shows this pet WEARING that skin -- which is what makes a
-- skin card show the actual thing you are buying instead of a colour swatch you have to imagine onto a pet.
-- Omitted (every other caller), the pet renders in its natural look exactly as before.
local function makeViewportIcon(card, petId, level, isRare, sizeU, posU, anchorV, skinId, traitId)
	-- ONE icon per card. A rebuild that failed to destroy the previous one left two Icon3D siblings stacked
	-- in the same rect, which looks identical to a doubled model. Clear by name before building.
	for _, old in ipairs(card:GetChildren()) do
		if old.Name == "Icon3D" then
			for si = #iconSpins, 1, -1 do
				if iconSpins[si].vp == old then table.remove(iconSpins, si) end
			end
			old:Destroy()
		end
	end
	local vp = Instance.new("ViewportFrame"); vp.Name = "Icon3D"
	vp.AnchorPoint = anchorV or Vector2.new(0.5,0); vp.Size = sizeU or UDim2.new(0,54,0,34); vp.Position = posU or UDim2.new(0.5,0,0,2)
	vp.BackgroundColor3 = Color3.fromRGB(12,34,78); vp.BackgroundTransparency = 0.15; vp.Parent = card
	uicorner(vp, 8)
	vp.Ambient = Color3.fromRGB(185,185,195); vp.LightColor = Color3.fromRGB(255,255,255); vp.LightDirection = Vector3.new(-0.4,-1,-0.5)
	-- The camera is created ONCE here and reused for the viewport's whole life; the worker only ever writes
	-- its CFrame. Nothing re-creates it on refresh, so CurrentCamera can never end up on an orphan.
	local cam = Instance.new("Camera"); cam.FieldOfView = 50; cam.Parent = vp; vp.CurrentCamera = cam
	local ph = Instance.new("TextLabel"); ph.Name = "IconPlaceholder"; ph.Size = UDim2.new(1,0,1,0); ph.BackgroundTransparency = 1
	ph.Font = Enum.Font.FredokaOne; ph.TextScaled = true; ph.TextColor3 = Color3.fromRGB(150,180,235); ph.Text = "\xF0\x9F\x90\xBE"; ph.Parent = vp
	-- DRAG TO ROTATE. Grab a pet and it turns with your finger/mouse; let go and the gentle auto-orbit
	-- picks up from wherever you left it. State lives in ATTRIBUTES rather than locals because this file
	-- is at Luau's 200-registers-per-scope ceiling and the spin loop is in a different scope entirely.
	--   SpinDrag = radians added by the player;  SpinAuto = radians added by the idle orbit;
	--   SpinHeld = true while a finger is down, which pauses SpinAuto so the two never fight.
	vp.Active = true
	vp:SetAttribute("SpinDrag", 0); vp:SetAttribute("SpinAuto", 0); vp:SetAttribute("SpinHeld", false)
	vp:SetAttribute("SpinTilt", 0)
	do
		-- ===== THE DRAG IS TRACKED GLOBALLY, NOT OVER THE ICON =====
		-- The first version listened on the ViewportFrame's OWN InputChanged and released on
		-- MouseLeave. A grid icon is about 50px wide, so the pointer left it within the first
		-- few pixels of any real drag -- movement stopped arriving and MouseLeave then dropped
		-- the grab entirely. It read as "the pet barely turns, then lets go by itself".
		-- Only the GRAB is hit-tested on the icon now; once you have hold of the pet, the
		-- movement and the release come from UserInputService, so your finger/mouse can travel
		-- anywhere on the screen and the pet keeps turning with it.
		local uis = game:GetService("UserInputService")
		local lastX, lastY, moveConn, endConn
		local function release()
			lastX, lastY = nil, nil
			if moveConn then moveConn:Disconnect(); moveConn = nil end
			if endConn then endConn:Disconnect(); endConn = nil end
			vp:SetAttribute("SpinHeld", false)   -- the idle orbit picks up from here
		end
		vp.InputBegan:Connect(function(io)
			if io.UserInputType ~= Enum.UserInputType.MouseButton1
				and io.UserInputType ~= Enum.UserInputType.Touch then return end
			release()                            -- never stack two grabs on one icon
			lastX, lastY = io.Position.X, io.Position.Y
			vp:SetAttribute("SpinHeld", true)    -- pauses the auto-spin for THIS pet only

			moveConn = uis.InputChanged:Connect(function(m)
				if not lastX then return end
				if m.UserInputType ~= Enum.UserInputType.MouseMovement
					and m.UserInputType ~= Enum.UserInputType.Touch then return end
				local dx, dy = m.Position.X - lastX, m.Position.Y - lastY
				lastX, lastY = m.Position.X, m.Position.Y
				-- 0.011 rad/px sideways: a drag the width of the panel is roughly one full turn.
				vp:SetAttribute("SpinDrag", (vp:GetAttribute("SpinDrag") or 0) + dx * 0.011)
				-- Up/down raises and lowers the camera so you can look at the pet's face or its
				-- feet. Clamped so it can never swing over the top and render the pet upside down.
				vp:SetAttribute("SpinTilt",
					math.clamp((vp:GetAttribute("SpinTilt") or 0) + dy * 0.02, -1.6, 2.2))
			end)
			endConn = uis.InputEnded:Connect(function(e)
				if e.UserInputType == Enum.UserInputType.MouseButton1
					or e.UserInputType == Enum.UserInputType.Touch then release() end
			end)
		end)
		-- A card rebuild (inventory refresh, menu close) destroys the icon mid-drag; without this
		-- its two UserInputService connections would outlive it, one pair per rebuild.
		vp.Destroying:Connect(release)
	end
	iconQueue[#iconQueue + 1] = { vp = vp, cam = cam, ph = ph, petId = petId, level = level,
		isRare = isRare, skin = skinId, trait = traitId }
	startIconWorker()
	return vp
end
-- ONE slow auto-rotate loop for ALL icon clones; only runs while the pet menu is OPEN (so closed = no cost,
-- and ViewportFrames only render while visible anyway).
do
	local angle = 0
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		if not panel.Visible or #iconSpins == 0 then return end
		angle = (angle + dt * 0.6) % (2 * math.pi) -- slow + smooth; dt-based so it's frame-rate independent
		local step = dt * 0.6 -- this frame's share of the idle orbit, applied per-icon below
		-- Two culls, both about not paying for pictures nobody can see. ViewportFrames render whether or not
		-- anything is on top of them, so without these we'd spin ~10 grid pets behind an opaque detail card, and
		-- keep spinning cards scrolled far out of view.
		local detail = panel:FindFirstChild("PetDetailOverlay") -- open => the grid behind it is fully covered
		local pTop = panel.AbsolutePosition.Y
		local pBot = pTop + panel.AbsoluteSize.Y
		for i = #iconSpins, 1, -1 do
			local ic = iconSpins[i]
			local vp = ic.vp
			if not (vp and vp.Parent and ic.cam and ic.cam.Parent) then
				table.remove(iconSpins, i) -- its card/overlay was destroyed -- drop it
			elseif detail and not vp:IsDescendantOf(detail) then
				-- covered by the VIEW MORE card: skip (the detail pet itself still spins -- it IS a descendant)
			elseif vp.AbsolutePosition.Y + vp.AbsoluteSize.Y >= pTop and vp.AbsolutePosition.Y <= pBot then
				-- ORBIT THE CAMERA around the (stationary) pet. One CFrame write, no part-by-part transform.
				-- Each icon carries its OWN auto-orbit total so a pet the player has turned by hand keeps its
				-- new heading instead of snapping back to the shared angle the moment they let go.
				if not vp:GetAttribute("SpinHeld") then
					vp:SetAttribute("SpinAuto", ((vp:GetAttribute("SpinAuto") or 0) + step) % (2 * math.pi))
				end
				local a = ic.a0 + (vp:GetAttribute("SpinAuto") or 0) + (vp:GetAttribute("SpinDrag") or 0)
				-- SpinTilt is the up/down the player dragged in, scaled by this icon's own radius so the
				-- same finger movement reads the same on a tiny grid card and on the big detail pet.
				local h = ic.height + (vp:GetAttribute("SpinTilt") or 0) * ic.radius * 0.5
				ic.cam.CFrame = CFrame.lookAt(
					ic.center + Vector3.new(math.cos(a) * ic.radius, h, math.sin(a) * ic.radius),
					ic.center)
			end
			-- else: scrolled out of the panel's visible band -- leave it, it'll spin again when scrolled back in
		end
	end)
end

-- ===== "VIEW MORE" PET DETAIL CARD =====================================================================
-- A full-panel overlay showing ONE pet big -- a giant 3D picture, its tier, level + XP, lifetime stats and a
-- flavour blurb -- and COVERING the grid entirely so nothing competes with it. Same overlay pattern as the
-- Quests/Trade tabs: a Frame parented to `panel`, mutually exclusive with them, dismissed by its own back button.
--
-- Built FRESH on every open and destroyed on close (rather than kept as a persistent module-scope local + widget
-- set): this file sits near Luau's 200-locals-per-scope ceiling, and a rebuilt overlay also can't go stale
-- against an inventory refresh. Callers find/kill it by NAME, so nothing else needs a local either.
-- ===== PET HUB OVERLAY FUNCTIONS -- ON A SHARED TABLE, NOT AS MODULE-SCOPE LOCALS ==========================
-- This file sits ON Luau's hard ceiling of 200 locals per scope for the main chunk. Declaring these three as
-- `local function` overflowed it and the WHOLE SCRIPT failed to compile ("Out of local registers"), which silently
-- killed every Pet Hub button. A table field costs ZERO main-chunk registers, so they live here instead.
-- DO NOT convert these back to `local function` without first freeing registers elsewhere in this file.
_G.PetHub = _G.PetHub or {}

_G.PetHub.hideDetail = function()
	local d = panel:FindFirstChild("PetDetailOverlay")
	if d then d:Destroy() end
end
-- `p` is an OWNED card's payload entry (level/xp/rare/stats) OR a LOCKED catalog entry ({owned=false, unlock=...}).
-- `key` is the storage key for owned pets (what EQUIP fires with); nil for locked ones.
_G.PetHub.showDetail = function(key, p)
	local petId = p.petId or key
	local locked = (p.owned == false) -- catalog entries carry owned=false; owned-card payloads have no `owned` field
	local tierName, tierColor, isVariant = petTier(p.level or 1, p.rare, petId)
	local cap = p.maxLevel or 25
	local maxed = (p.level or 1) >= cap

	-- thousands separators -- "12,480" reads as an achievement, "12480" reads as noise. Function-scoped on purpose
	-- (this file is near Luau's 200-locals-per-scope ceiling, so no new module-scope local).
	local function comma(n)
		local s = tostring(math.floor(tonumber(n) or 0))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end
	local function hms(sec)
		sec = math.floor(tonumber(sec) or 0)
		local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
		if h > 0 then return string.format("%dh %dm", h, m) end
		return string.format("%dm %ds", m, sec % 60)
	end

	-- STAT ROWS: the "cool stuff" -- what this pet has actually been through with the player. Computed UP FRONT
	-- because both the build path and the live-patch path below need them (and the row COUNT is part of the
	-- patch-vs-rebuild identity check).
	-- ===== HOW RARE IS IT =====
	-- The server has always sent rareOdds (750, or 10,000 for the Cosmic Duck) on BOTH the owned entry and the
	-- locked catalog entry, with a comment saying it was meant for exactly this line -- and the client never read
	-- it. Printed in the house "1 in N" wording, the same phrasing the server derives from the roll weights
	-- (HATCH_ODDS_TEXT), so the card and the actual roll can never word the same number two different ways.
	--
	-- Deliberately NOT the age-tier hatch odds. Those are the odds of hatching AT a stage, and a pet's stage
	-- changes every time it levels -- a grown pet would advertise the odds of a roll it never made. rareOdds is a
	-- property of the SPECIES and stays true for the life of the pet.
	local function oddsText(n)
		if type(n) ~= "number" or n <= 0 then return nil end
		return "1 in " .. comma(math.floor(n + 0.5))
	end
	local rows = {}
	if locked then
		rows[#rows+1] = { "Found on", p.islandName or "???" }
		rows[#rows+1] = { "How to get it", p.questLabel or "???" }
		-- a reason to care WHICH pet you go for, before you own it
		local o = oddsText(p.rareOdds)
		if o then rows[#rows+1] = { "Rare chance", o } end
		-- (no "Status: not collected" row -- the header already says LOCKED in letters twice this size)
	else
		-- FOUR facts, deliberately. This card is read by 10-year-olds, and the old eleven-row dump (Lifetime
		-- XP, Accessories, How you got it, Hatch odds, You own...) buried the two things a kid actually cares
		-- about -- "how strong is it" and "what do I do next" -- in a wall of numbers. Everything cut is either
		-- shown elsewhere (rarity on the chip strip below), or was trivia.
		rows[#rows+1] = { "Level", maxed and ("MAX (" .. cap .. ")") or ((p.level or 1) .. " / " .. cap) }
		-- RARITY. For a rare variant the odds ARE its rarity, so name the tier alongside them ("Exotic - 1 in 750",
		-- "Mythical - 1 in 10,000"). For a normal pet the same number is the chance of pulling this species' rare
		-- version, which is the thing worth knowing before you grind it, so it's labelled for what it is.
		do
			local o = oddsText(p.rareOdds)
			if o then
				if p.rare then rows[#rows+1] = { "Rarity", tierName .. "  \xE2\x80\xA2  " .. o }
				else rows[#rows+1] = { "Rare chance", o } end
			end
		end
		rows[#rows+1] = { "Highest flight", comma(p.height or 0) .. " studs" }
		rows[#rows+1] = { "Time together", hms(p.time or 0) }
		if (p.count or 1) > 1 then rows[#rows+1] = { "You own", "x" .. p.count } end
		-- the ONE forward-looking line: what happens next. Worth more than the rest put together.
		if not maxed and p.milestone and p.milestone ~= "" then rows[#rows+1] = { "Next unlock", p.milestone } end
	end
	-- (No row cap needed: the right column is a ScrollingFrame with an auto-sized canvas, so the fact list, the tier
	-- ladder and the EQUIP button below it can all grow without anything falling off the bottom of the card.)

	local function subText()
		if locked then return "\xF0\x9F\x94\x92 LOCKED" .. (p.islandName and ("  \xE2\x80\xA2  " .. p.islandName) or "") end
		return tierName .. (isVariant and "" or ("  \xE2\x80\xA2  Level " .. (p.level or 1)))
			.. (p.islandName and ("  \xE2\x80\xA2  " .. p.islandName) or "")
	end

	-- ===== LIVE PATCH PATH =====
	-- If this EXACT pet's card is already on screen, update the numbers IN PLACE and return -- do NOT rebuild.
	-- rebuildInventory calls this on every inventory push, and those fire repeatedly during flight as XP ticks in.
	-- Tearing the overlay down each time would destroy and re-clone the big 3D pet, so the picture would flicker
	-- and its rotation would snap back to zero every few seconds. Patching leaves the model (and its spin) alone.
	-- The row COUNT is part of the identity check: if a level-up added/removed a row, the layout genuinely changed,
	-- so we fall through and rebuild properly.
	-- WHAT THIS PET IS WEARING is part of the card's identity too. Without it, equipping a skin hit the
	-- live-patch path (same pet, same row count, same tier) and returned early -- so the PET INVENTORY list
	-- kept showing "ON" against the OLD skin and "WEAR" against the one you had just put on.
	local eqSig = "-"
	if _G.petSkinState and _G.petSkinState.equipped then
		local e = _G.petSkinState.equipped[petId]
		if e then eqSig = tostring(e.skin) .. "|" .. tostring(e.trait or "") end
	end
	local cur = panel:FindFirstChild("PetDetailOverlay")
	if cur and cur:GetAttribute("PetKey") == (key or "") and cur:GetAttribute("PetSpecies") == tostring(petId)
		and cur:GetAttribute("RowCount") == #rows
		and cur:GetAttribute("EquipSig") == eqSig -- skin/trait changed => the ON marker moved => rebuild
		and cur:GetAttribute("Tier") == tierName then -- tier changed => the ladder highlight moved => rebuild properly
		local sub = cur:FindFirstChild("SubLine", true)
		if sub then sub.Text = subText() end
		local bar = cur:FindFirstChild("XpBar", true)
		if bar then
			local fill, xt = bar:FindFirstChild("XpFill"), bar:FindFirstChild("XpText")
			local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
			if fill then
				fill.Size = UDim2.new(frac, 0, 1, 0)
				fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120)
			end
			if xt then xt.Text = maxed and "MAX LEVEL" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP to Level " .. ((p.level or 1) + 1)) end
		end
		for i, r in ipairs(rows) do
			local v = cur:FindFirstChild("RowVal" .. i, true)
			if v then v.Text = tostring(r[2]) end
		end
		local eq = cur:FindFirstChild("EquipBtn", true) -- now lives inside the scrolling fact list -> recursive find
		if eq then
			eq.Text = p.equipped and "UNEQUIP" or "EQUIP"
			eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
			eq:SetAttribute("Equipped", p.equipped and true or false) -- what the button's click handler actually reads
		end
		return
	end

	-- ===== FULL BUILD PATH (a different pet, or the layout changed) =====
	_G.PetHub.hideDetail()
	questsOverlay.Visible = false     -- the detail view owns the panel while it's up
	local d = Instance.new("Frame"); d.Name = "PetDetailOverlay"; d.Size = UDim2.new(1,-24,1,-116); d.Position = UDim2.new(0,12,0,110)
	d.BackgroundColor3 = Color3.fromRGB(16,60,140); d.ZIndex = 5; d.Parent = panel
	-- Stamp WHICH pet this card is showing (+ its row count). rebuildInventory and the patch path above read these.
	-- Stashed on the shared _G.PetHub table (not a local -- this file is at the 200-register ceiling) so the
	-- skin-state hook below can re-render THIS card without knowing anything about the grid.
	_G.PetHub._lastKey, _G.PetHub._lastP = key, p
	d:SetAttribute("PetKey", key or "")
	d:SetAttribute("PetSpecies", tostring(petId))
	d:SetAttribute("RowCount", #rows)
	d:SetAttribute("EquipSig", eqSig)
	d:SetAttribute("Tier", tierName) -- the ladder highlight is keyed on this; a tier change forces a rebuild
	uicorner(d, 12); uistroke(d, locked and Color3.fromRGB(255,190,60) or Color3.fromRGB(10,40,100), 2)

	-- ============================================================================================================
	-- THE PET SKINS PAGE
	-- ============================================================================================================
	-- One pet, one job: customise it. This replaced a spec-sheet layout that mixed a fact list, a rarity ladder and
	-- a narrow skins list into one scrolling column -- three unrelated jobs sharing a container, none of them with
	-- room to breathe.
	--
	-- It is a PAGE, not a popup: same 700x520 panel, same header, same nav bar, sitting at the same y=110 every
	-- other page uses. Back returns to the Pets grid. Nothing floats, nothing dims the screen behind it.
	--
	-- Everything below is function-scoped. This file sits at Luau's 200-locals-per-scope ceiling and one more
	-- top-level local silently stops the whole script compiling -- taking every pet handler down with it.

	-- ===== EVERYTHING BELOW IS SCALE, NOT OFFSET =====
	-- This page was laid out in pixels for a PC viewport: 676 x 404 inside the 700 x 520 panel, with every
	-- child at a hand-measured offset. On a short mobile screen the panel loses height, the offsets do not
	-- move, and the whole page compresses into itself. Each Scale below is the ORIGINAL pixel measure
	-- divided by that 676 x 404, so the page is pixel-identical on PC and simply re-proportions elsewhere.
	--
	-- The aspect ratio holds the shape: rather than squashing vertically when the panel is short, the page
	-- keeps its 676:404 and gives back the width it cannot use.
	do
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 676 / 404
		ar.AspectType = Enum.AspectType.FitWithinMaxSize
		ar.DominantAxis = Enum.DominantAxis.Width
		ar.Parent = d
	end
	-- TextScaled everywhere, each label capped so it can never grow past its authored size -- shrink-to-fit
	-- in one direction only.
	local function dfit(o, maxSize)
		o.TextScaled = true
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize or 20; c.Parent = o
		return o
	end

	-- ---- HEADER ROW: back + page title, laid out, not overlapped ----
	-- These were two absolutely-positioned elements at x=10 and x=152 with the title sized (1,-160). The
	-- back button's own width was not part of that sum, so the moment either changed size they slid over
	-- each other. A horizontal list gives each a share of the row and the gap is the layout's, not a guess.
	local hdr = Instance.new("Frame"); hdr.Name = "HeaderRow"; hdr.BackgroundTransparency = 1
	hdr.Position = UDim2.new(0.015,0,0.02,0); hdr.Size = UDim2.new(0.97,0,0.074,0); hdr.ZIndex = 8; hdr.Parent = d
	do
		local hl = Instance.new("UIListLayout"); hl.FillDirection = Enum.FillDirection.Horizontal
		hl.SortOrder = Enum.SortOrder.LayoutOrder; hl.Padding = UDim.new(0.02,0)
		hl.VerticalAlignment = Enum.VerticalAlignment.Center; hl.Parent = hdr
	end
	local back = Instance.new("TextButton"); back.Size = UDim2.new(0.2,0,1,0); back.LayoutOrder = 1
	back.BackgroundColor3 = Color3.fromRGB(120,120,120); back.Font = Enum.Font.GothamBold
	back.TextColor3 = Color3.new(1,1,1); back.Text = "\xE2\x97\x80 Back to Pets"; back.ZIndex = 8; back.Parent = hdr
	uicorner(back, 8); uistroke(back, Color3.new(0,0,0), 2); dfit(back, 14)
	back.MouseButton1Click:Connect(_G.PetHub.hideDetail)

	local title = Instance.new("TextLabel"); title.Size = UDim2.new(0.76,0,1,0); title.LayoutOrder = 2
	title.BackgroundTransparency = 1; title.Font = Enum.Font.FredokaOne
	title.TextXAlignment = Enum.TextXAlignment.Left; title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = isVariant and tierColor or Color3.fromRGB(255,215,0); title.ZIndex = 8
	title.Text = (p.rare and (p.rareName or p.displayName)) or p.displayName or petId; title.Parent = hdr
	uistroke(title, Color3.new(0,0,0), 2); dfit(title, 20)

	-- ---- LEFT: the pet on a display stage ----
	-- The pedestal and the soft glow are plain Frames in the panel's own palette, so the pet reads as standing on
	-- something rather than floating in a blue box. No new art, no new colours.
	-- 268x140 at (10,46) -> the same rect expressed against 676x404
	local stage = Instance.new("Frame"); stage.Size = UDim2.new(0.396,0,0.347,0); stage.Position = UDim2.new(0.015,0,0.114,0)
	stage.BackgroundColor3 = Color3.fromRGB(12,44,104); stage.BorderSizePixel = 0; stage.ZIndex = 6; stage.Parent = d
	uicorner(stage, 10); uistroke(stage, Color3.fromRGB(8,26,64), 2)
	do
		local glow = Instance.new("Frame"); glow.Size = UDim2.new(0,150,0,150); glow.Position = UDim2.new(0.5,0,0.52,0)
		glow.AnchorPoint = Vector2.new(0.5,0.5); glow.BackgroundColor3 = tierColor; glow.BackgroundTransparency = 0.88
		glow.BorderSizePixel = 0; glow.ZIndex = 6; glow.Parent = stage
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1,0); gc.Parent = glow
		local ped = Instance.new("Frame"); ped.Size = UDim2.new(0,150,0,14); ped.Position = UDim2.new(0.5,0,1,-14)
		ped.AnchorPoint = Vector2.new(0.5,0); ped.BackgroundColor3 = Color3.fromRGB(8,26,64); ped.BorderSizePixel = 0
		ped.ZIndex = 6; ped.Parent = stage
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1,0); pc.Parent = ped
	end
	-- Same makeViewportIcon the grid cards use, so it is the same live model on the same shared auto-rotate loop.
	local bigVp = makeViewportIcon(stage, petId, p.level or 1, p.rare, UDim2.new(1,-16,1,-22), UDim2.new(0,8,0,4), Vector2.new(0,0))
	bigVp.ZIndex = 7

	-- ---- TOP RIGHT: what this pet is wearing ----
	-- (1,-296) x 140 at (288,46) -> the same rect against 676x404
	local info = Instance.new("Frame"); info.Size = UDim2.new(0.562,0,0.347,0); info.Position = UDim2.new(0.426,0,0.114,0)
	info.BackgroundColor3 = Color3.fromRGB(12,44,104); info.BackgroundTransparency = 0.25; info.BorderSizePixel = 0
	info.ZIndex = 6; info.Parent = d
	uicorner(info, 10); uistroke(info, Color3.fromRGB(8,26,64), 2)
	-- ---- THE INFO BLOCK: ONE VERTICAL LIST ---------------------------------------------------------
	-- Same fix as the grid cards. These six rows were hand-placed at y = 6/24/44/66/86/108 inside a frame
	-- 140px tall -- 134px of content in 140px of room, so the moment the panel scaled down they stacked.
	-- The list places each row after the one before it, and the Scale heights re-proportion with the frame.
	--
	-- SubLine / XpBar / XpFill / XpText / EquipBtn KEEP THEIR NAMES -- the live-patch path above finds them
	-- to update the numbers in place, which is what stops the 3D pet being rebuilt (and its spin snapping
	-- back to zero) every few seconds while XP ticks in. It already searches recursively, so it does not
	-- care that they now sit one level deeper.
	local ibody = Instance.new("Frame"); ibody.Name = "Body"; ibody.BackgroundTransparency = 1
	ibody.Position = UDim2.new(0,10,0,6); ibody.Size = UDim2.new(1,-20,1,-12); ibody.ZIndex = 7; ibody.Parent = info
	do
		local il = Instance.new("UIListLayout"); il.FillDirection = Enum.FillDirection.Vertical
		il.SortOrder = Enum.SortOrder.LayoutOrder
		il.Padding = UDim.new(0.02,0)   -- a FRACTION of the block, so the gaps shrink with the rows
		il.Parent = ibody
	end
	local ifit = dfit   -- same TextScaled + max-size treatment as the header
	do
		local h = Instance.new("TextLabel"); h.Size = UDim2.new(1,0,0.11,0); h.LayoutOrder = 1
		h.BackgroundTransparency = 1; h.Font = Enum.Font.GothamBold
		h.TextColor3 = Color3.fromRGB(255,215,0); h.TextXAlignment = Enum.TextXAlignment.Left
		h.ZIndex = 7; h.Text = "EQUIPPED"; h.Parent = ibody
		ifit(h, 12)
		-- THE ONE OVERALL TIER (hidden skin+trait values -> PetTier) rides the header in its own colour, so the
		-- detail card leads with the same single label the pet wears overhead. Rich text because a TextLabel is
		-- one colour otherwise; PetSkinLook publishes the computation (this file cannot afford the requires).
		local eqH = (_G.petSkinState and (_G.petSkinState.equipped or {})[petId]) or nil
		if eqH and _G.petSkinOverallTier then
			local okOv, ovT, ovC = pcall(_G.petSkinOverallTier, eqH.skin, eqH.trait)
			if okOv and ovT then
				local c = ovC or Color3.new(1,1,1)
				h.RichText = true
				h.Text = string.format('EQUIPPED   <font color="rgb(%d,%d,%d)">%s</font>',
					math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5), string.upper(tostring(ovT)))
			end
		end
	end
	-- Read live from the state PetSkinLook mirrors off the server, never from a local guess, so this panel and the
	-- crate panel cannot disagree about what you are wearing.
	local eqNow = (_G.petSkinState and (_G.petSkinState.equipped or {})[petId]) or nil
	local function metaOf(id)
		if _G.petSkinMeta then return _G.petSkinMeta(id) end
		return { name = id and tostring(id) or "Default", tier = "Common",
			tierColor = Color3.new(1,1,1), color = Color3.fromRGB(120,130,145) }
	end
	-- A key/value pair is now a ROW in the list rather than two labels at a shared y. The two halves are
	-- Scale-width inside that row, so the value column follows the frame instead of starting at a fixed 70px.
	local function infoRow(order, key, value, colour)
		local row = Instance.new("Frame"); row.BackgroundTransparency = 1
		row.Size = UDim2.new(1,0,0.15,0); row.LayoutOrder = order; row.ZIndex = 7; row.Parent = ibody
		local k = Instance.new("TextLabel"); k.Size = UDim2.new(0.3,0,1,0)
		k.BackgroundTransparency = 1; k.Font = Enum.Font.Gotham
		k.TextColor3 = Color3.fromRGB(165,195,240); k.TextXAlignment = Enum.TextXAlignment.Left
		k.ZIndex = 7; k.Text = key; k.Parent = row
		ifit(k, 12)
		local v = Instance.new("TextLabel"); v.Size = UDim2.new(0.68,0,1,0); v.Position = UDim2.new(0.32,0,0,0)
		v.BackgroundTransparency = 1; v.Font = Enum.Font.GothamBold
		v.TextColor3 = colour or Color3.new(1,1,1); v.TextXAlignment = Enum.TextXAlignment.Left
		v.TextTruncate = Enum.TextTruncate.AtEnd; v.ZIndex = 7; v.Text = value; v.Parent = row
		ifit(v, 13)
	end
	do
		-- Skin + its rarity, Trait + its rarity -- the detailed breakdown lives HERE, never overhead (the pet
		-- shows only the one Overall Tier in the header above). petTraitMeta comes from SkinCrateClient, which
		-- already requires PetTraits; this file cannot.
		local m = metaOf(eqNow and eqNow.skin or nil)
		infoRow(2, "Skin", m.name .. ((eqNow and eqNow.skin) and ("  \xC2\xB7  " .. tostring(m.tier)) or ""), m.tierColor)
		local tm = (eqNow and eqNow.trait and _G.petTraitMeta) and _G.petTraitMeta(eqNow.trait) or nil
		infoRow(3, "Trait", tm and tm.label or ((eqNow and eqNow.trait) or "None"),
			tm and tm.color or ((eqNow and eqNow.trait) and Color3.fromRGB(255,205,120) or Color3.fromRGB(180,200,230)))
	end

	-- SubLine / XpBar / XpFill / XpText / EquipBtn keep these EXACT names: the live-patch path above finds them by
	-- name and updates their numbers in place on every inventory push, which is what stops the 3D pet from being
	-- rebuilt (and its spin snapping back to zero) every few seconds while XP ticks in during flight.
	local sub = Instance.new("TextLabel"); sub.Name = "SubLine"; sub.Size = UDim2.new(1,0,0.13,0); sub.LayoutOrder = 4
	sub.BackgroundTransparency = 1; sub.Font = Enum.Font.GothamBold
	sub.TextXAlignment = Enum.TextXAlignment.Left; sub.ZIndex = 7; sub.Parent = ibody
	sub.TextColor3 = locked and Color3.fromRGB(255,205,90) or tierColor
	sub.Text = subText()
	ifit(sub, 12)

	if not locked then
		local barBG = Instance.new("Frame"); barBG.Name = "XpBar"; barBG.Size = UDim2.new(1,0,0.13,0); barBG.LayoutOrder = 5
		barBG.BackgroundColor3 = Color3.fromRGB(8,26,64); barBG.BorderSizePixel = 0; barBG.ZIndex = 7; barBG.Parent = ibody
		uicorner(barBG, 8)
		local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
		local fill = Instance.new("Frame"); fill.Name = "XpFill"; fill.Size = UDim2.new(frac,0,1,0); fill.BorderSizePixel = 0; fill.ZIndex = 7
		fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 8)
		local xt = Instance.new("TextLabel"); xt.Name = "XpText"; xt.Size = UDim2.new(1,0,1,0); xt.BackgroundTransparency = 1; xt.ZIndex = 8
		xt.Font = Enum.Font.GothamBold; xt.TextColor3 = Color3.new(1,1,1); xt.Parent = barBG
		xt.Text = maxed and "MAX LEVEL" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP to Level " .. ((p.level or 1) + 1))
		ifit(xt, 11)
	end

	-- THE BIG BUTTON equips the PET. That is deliberately the primary action on this page: a skin only shows up in
	-- the world on the pet you are actually walking around with, so choosing a skin below and then not equipping the
	-- pet would leave you looking at a change nobody else can see. Per-skin Equip lives on each card.
	if not locked and key then
		local eq = Instance.new("TextButton"); eq.Name = "EquipBtn"
		eq.Size = UDim2.new(1,0,0.21,0); eq.LayoutOrder = 6; eq.Parent = ibody
		eq.Font = Enum.Font.GothamBold; eq.TextColor3 = Color3.new(1,1,1); eq.ZIndex = 8
		ifit(eq, 15)
		eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
		eq.Text = p.equipped and ("\xE2\x9C\x94 EQUIPPED") or "EQUIP PET"
		eq:SetAttribute("Equipped", p.equipped and true or false)
		-- HANDS OFF for the same reason as the nav tabs: GREY means "already equipped", GREEN means "press me",
		-- and the live-patch path above recolours THIS SAME INSTANCE when you equip. ButtonTextStyle remembers a
		-- button's fill on first sight and re-asserts a darkened version of it every 3s, so an equipped pet's
		-- grey button would drift back toward green (or the reverse) and advertise an action that isn't there.
		eq:SetAttribute("BTS_Skip", true)
		uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 2)
		eq.MouseButton1Click:Connect(function()
			-- reads the live attribute, NOT a captured p.equipped: the patch path keeps the attribute current, so a
			-- closure over the build-time value would go stale the moment the pet is equipped.
			if eq:GetAttribute("Equipped") then pcall(function() PetEquipEvent:FireServer(false) end)
			else pcall(function() PetEquipEvent:FireServer(key) end) end
		end)
	end

	-- ---- OWNED COUNT + FILTERS ----
	local ownedList, seenSkin, distinct = {}, {}, 0
	if _G.petSkinState then
		for skey, count in pairs(_G.petSkinState.skins or {}) do
			-- key format is 'Pet|Skin|Trait' (PetSkins.makeKey). Split inline rather than requiring the module:
			-- this file cannot afford another top-level local.
			local kp, ks, kt = string.match(tostring(skey), "^([^|]+)|([^|]*)|?(.*)$")
			if kp == petId and ks and ks ~= "" and (tonumber(count) or 0) > 0 then
				ownedList[#ownedList + 1] = { skin = ks, trait = (kt ~= "" and kt or nil), count = tonumber(count) or 1 }
				if not seenSkin[ks] then seenSkin[ks] = true; distinct = distinct + 1 end
			end
		end
	end
	table.sort(ownedList, function(a, b)
		if a.skin ~= b.skin then return a.skin < b.skin end
		return (a.trait or "") < (b.trait or "")
	end)
	-- DEFAULT first, so there is always a way back to the pet's natural look. It counts toward the total because
	-- every pet owns it from the start -- an all-red 0/21 page reads as 'I have nothing' and is a worse hook.
	table.insert(ownedList, 1, { skin = false, trait = nil, count = 1, isDefault = true })

	local totalSkins = (_G.petSkinTotal and _G.petSkinTotal()) or (#ownedList)
	local ownedLbl = Instance.new("TextLabel"); ownedLbl.Size = UDim2.new(0.97,0,0.045,0); ownedLbl.Position = UDim2.new(0.015,0,0.475,0)
	ownedLbl.BackgroundTransparency = 1; ownedLbl.Font = Enum.Font.GothamBold
	ownedLbl.TextColor3 = Color3.fromRGB(255,215,0); ownedLbl.TextXAlignment = Enum.TextXAlignment.Left
	ownedLbl.ZIndex = 7; ownedLbl.Parent = d
	ownedLbl.Text = "Skins Owned:  " .. (distinct + 1) .. " / " .. totalSkins
	dfit(ownedLbl, 14)

	-- the grid takes whatever is left under the filter bar: y 0.609 -> 1.0 of the page
	local grid = Instance.new("ScrollingFrame"); grid.Name = "SkinGrid"
	grid.Size = UDim2.new(0.97,0,0.371,0); grid.Position = UDim2.new(0.015,0,0.609,0)
	grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); grid.CanvasSize = UDim2.new(0,0,0,0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y; grid.ZIndex = 6; grid.Parent = d
	do
		local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.new(0,154,0,140)
		gl.CellPadding = UDim2.new(0,8,0,8); gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.HorizontalAlignment = Enum.HorizontalAlignment.Left; gl.Parent = grid
	end

	-- renderSkins() rebuilds ONLY the grid, so tapping a filter never touches the 3D pet above it -- the model keeps
	-- spinning through every filter change instead of restarting each time.
	local function renderSkins(filter)
		for _, c in ipairs(grid:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		local shown = 0
		for i, it in ipairs(ownedList) do
			local m = metaOf(it.skin or nil)
			local pass = (filter == "All")
			if filter == "Traits" then pass = (it.trait ~= nil)
			elseif filter ~= "All" then pass = (m.tier == filter) end
			if pass then
				shown = shown + 1
				local on = it.isDefault and (eqNow == nil or eqNow.skin == nil)
					or (eqNow ~= nil and eqNow.skin == it.skin and (eqNow.trait or nil) == (it.trait or nil))
				local card = Instance.new("Frame"); card.LayoutOrder = i; card.BorderSizePixel = 0; card.ZIndex = 6
				card.BackgroundColor3 = Color3.fromRGB(18,66,150); card.Parent = grid
				uicorner(card, 10); uistroke(card, on and Color3.fromRGB(80,220,120) or m.tierColor, on and 2.5 or 1.5)
				-- SKIN PREVIEW = THIS PET WEARING THIS SKIN. A flat colour chip made you imagine the skin onto the pet;
				-- showing the real thing is the whole point of a skin card. The chip stays as the BACKDROP so the card
				-- still reads as that skin's colour at a glance and the pet has something to sit against -- the same
				-- swatch-behind-model pairing the crate reel uses.
				-- Scale-sized (0.39 of a 140px cell = the same 54px), so the preview keeps its share of the
				-- card rather than holding 54px while everything under it is squeezed.
				local sw = Instance.new("Frame"); sw.Size = UDim2.new(1,-16,0.39,0); sw.Position = UDim2.new(0,8,0,8)
				sw.BackgroundColor3 = m.color; sw.BorderSizePixel = 0; sw.ZIndex = 7; sw.Parent = card
				uicorner(sw, 8); uistroke(sw, Color3.new(0,0,0), 1)
				-- Same builder + same shared auto-rotate loop the pet grid uses, so these spin exactly like every other
				-- pet picture in the hub. Transparent background so the skin colour behind shows through.
				local svp = makeViewportIcon(card, petId, p.level or 1, p.rare,
					UDim2.new(1,-16,0.39,0), UDim2.new(0,8,0,8), Vector2.new(0,0), it.skin or nil, it.trait)
				svp.ZIndex = 8; svp.BackgroundTransparency = 1
				if (it.count or 1) > 1 then
					-- parented to the CARD at ZIndex 9, not to the swatch: the viewport now sits above the swatch, so a
					-- badge inside it would be buried under the pet.
					local cb = Instance.new("TextLabel"); cb.Size = UDim2.new(0,34,0,16); cb.Position = UDim2.new(1,-46,0,12)
					cb.BackgroundColor3 = Color3.fromRGB(8,26,64); cb.Font = Enum.Font.GothamBold; cb.TextSize = 11
					cb.TextColor3 = Color3.new(1,1,1); cb.ZIndex = 9; cb.Text = "x" .. it.count; cb.Parent = card
					uicorner(cb, 6)
				end
				-- Name / rarity / Equip in a list too. These sat at y = 66/84/110 in a 140px cell -- the same
				-- fixed-offset stack as every other card in this hub, and it collapses the same way.
				local sbody = Instance.new("Frame"); sbody.Name = "Body"; sbody.BackgroundTransparency = 1
				sbody.Position = UDim2.new(0,8,0.46,0); sbody.Size = UDim2.new(1,-16,0.54,-8); sbody.ZIndex = 7; sbody.Parent = card
				do
					local sl = Instance.new("UIListLayout"); sl.FillDirection = Enum.FillDirection.Vertical
					sl.SortOrder = Enum.SortOrder.LayoutOrder; sl.Padding = UDim.new(0,2); sl.Parent = sbody
				end
				local function sfit(o, maxSize)
					o.TextScaled = true
					local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
				end
				local nmL = Instance.new("TextLabel"); nmL.Size = UDim2.new(1,0,0.24,0); nmL.LayoutOrder = 1
				nmL.BackgroundTransparency = 1; nmL.Font = Enum.Font.GothamBold
				nmL.TextColor3 = Color3.new(1,1,1); nmL.TextXAlignment = Enum.TextXAlignment.Left
				nmL.TextTruncate = Enum.TextTruncate.AtEnd; nmL.ZIndex = 7; nmL.Text = m.name; nmL.Parent = sbody
				sfit(nmL, 13)
				local rr = Instance.new("TextLabel"); rr.Size = UDim2.new(1,0,0.21,0); rr.LayoutOrder = 2
				rr.BackgroundTransparency = 1; rr.Font = Enum.Font.Gotham
				rr.TextColor3 = m.tierColor; rr.TextXAlignment = Enum.TextXAlignment.Left
				rr.TextTruncate = Enum.TextTruncate.AtEnd; rr.ZIndex = 7; rr.Parent = sbody
				-- the card's tier line is the OVERALL tier of this exact skin+trait combo, not the skin's own
				-- band -- so a Classic card carrying Titan reads Epic here, same as it would overhead.
				do
					local ovT, ovC = m.tier, m.tierColor
					if not it.isDefault and _G.petSkinOverallTier then
						local okOv, a, b2 = pcall(_G.petSkinOverallTier, it.skin, it.trait)
						if okOv and a then ovT, ovC = a, b2 or ovC end
					end
					rr.TextColor3 = ovC
					rr.Text = tostring(ovT) .. (it.trait and ("  \xC2\xB7  " .. it.trait) or "")
				end
				sfit(rr, 11)
				local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0.33,0); b.LayoutOrder = 3
				b.Font = Enum.Font.GothamBold; b.TextColor3 = Color3.new(1,1,1); b.ZIndex = 7; b.Parent = sbody
				sfit(b, 12)
				b.BackgroundColor3 = on and Color3.fromRGB(60,150,70) or Color3.fromRGB(50,200,50)
				b.AutoButtonColor = not on
				b.Text = on and ("\xE2\x9C\x94 Equipped") or "Equip"
				uicorner(b, 6); uistroke(b, Color3.new(0,0,0), 1)
				b.MouseButton1Click:Connect(function()
					-- Only ASKS. The server re-validates that you own this exact skin+trait and that the pet is unlocked,
					-- then pushes state -- which lands in the patch path above and re-renders this page honestly.
					if not on and _G.skinEquip then _G.skinEquip(petId, it.skin, it.trait) end
				end)
			end
		end
		if shown == 0 then
			-- the grid layout sizes this to a cell whatever we ask for, so it just needs to shrink its text
			local none = Instance.new("TextLabel"); none.Size = UDim2.new(0,470,0,40); none.LayoutOrder = 0
			dfit(none, 13)
			none.BackgroundTransparency = 1; none.Font = Enum.Font.Gotham; none.TextWrapped = true
			none.TextColor3 = Color3.fromRGB(165,195,240); none.TextXAlignment = Enum.TextXAlignment.Left
			none.ZIndex = 7; none.Parent = grid
			none.Text = (filter == "All") and "No skins yet. Open a Skin Crate to find some!"
				or ("No " .. filter .. " skins for this pet yet.")
		end
	end

	-- FILTERS. Same gold-on-blue / dark-on-gold selected states the hub nav bar uses, so the two read as one UI.
	do
		local bar = Instance.new("Frame"); bar.Name = "SkinFilters"
		bar.Size = UDim2.new(0.97,0,0.064,0); bar.Position = UDim2.new(0.015,0,0.53,0)
		bar.BackgroundTransparency = 1; bar.ZIndex = 7; bar.Parent = d
		local bl = Instance.new("UIListLayout"); bl.FillDirection = Enum.FillDirection.Horizontal
		bl.Padding = UDim.new(0.012,0); bl.SortOrder = Enum.SortOrder.LayoutOrder; bl.Parent = bar
		local btns = {}
		local function light(sel)
			for name, b in pairs(btns) do
				local on = (name == sel)
				b.BackgroundColor3 = on and Color3.fromRGB(255,215,0) or Color3.fromRGB(18,66,150)
				b.TextColor3 = on and Color3.fromRGB(92,58,8) or Color3.fromRGB(255,215,0)
				local st = b:FindFirstChildOfClass("UIStroke")
				if st then st.Thickness = on and 2 or 1 end
			end
		end
		for i, name in ipairs({ "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Traits" }) do
			-- seven buttons + six 0.012 gaps: 7 x 0.132 + 0.072 = 0.996, so the row fills the bar at any width
			local b = Instance.new("TextButton"); b.Size = UDim2.new(0.132,0,1,0); b.LayoutOrder = i
			b.Font = Enum.Font.GothamBold; b.Text = name; b.ZIndex = 8; b.Parent = bar
			uicorner(b, 8); uistroke(b, Color3.new(1,1,1), 1)
			-- CoreClient force-sets TextScaled on every PlayerGui label, so the ceiling has to come from a constraint
			dfit(b, 12)
			btns[name] = b
			b.MouseButton1Click:Connect(function() light(name); renderSkins(name) end)
		end
		light("All")
	end
	renderSkins("All")

	if locked then
		local warn2 = Instance.new("TextLabel"); warn2.Size = UDim2.new(0.97,0,0.045,0); warn2.Position = UDim2.new(0.015,0,0.475,0)
		warn2.BackgroundTransparency = 1; warn2.Font = Enum.Font.GothamBold
		warn2.TextColor3 = Color3.fromRGB(255,200,120); warn2.TextXAlignment = Enum.TextXAlignment.Left
		warn2.ZIndex = 8; warn2.Parent = d
		warn2.Text = "\xF0\x9F\x94\x92 Unlock this pet to wear its skins"
		dfit(warn2, 13)
		ownedLbl.Visible = false
		-- The old facts list carried 'Found on' / 'How to get it'. That list is gone, so the ONE line worth
		-- keeping moves here: a locked pet's page exists to sell you on going and earning it, and showing the
		-- prize without saying where to get it is a worse pitch than the grid card you clicked to get here.
		local hint = Instance.new("TextLabel"); hint.Size = UDim2.new(0.97,0,0.109,0); hint.Position = UDim2.new(0.015,0,0.53,0)
		hint.BackgroundTransparency = 1; hint.Font = Enum.Font.Gotham; hint.TextWrapped = true
		hint.TextColor3 = Color3.fromRGB(205,222,255); hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top; hint.ZIndex = 8; hint.Parent = d
		hint.Text = (p.questLabel or p.unlock or "Keep exploring to find this pet")
			.. (p.islandName and ("   " .. p.islandName) or "")
		dfit(hint, 13)
		-- nothing to filter when you own none of its skins
		local fb = d:FindFirstChild("SkinFilters"); if fb then fb.Visible = false end
	end
	print("[PetInv] detail card opened for " .. tostring(petId) .. (locked and " (locked)" or ""))
end

-- one OWNED pet card (icon/name/level/equip/upgrade/robux) into the PETS grid. `key` is the STORAGE KEY (the unit of
-- equip/trade -- petId or petId#R); the SPECIES (for icons/templates/tier) is p.petId. A normal + a rare of one species
-- arrive as two separate keys -> two separate cards.
local function buildPetCard(key, p, order)
	local petId = p.petId or key -- SPECIES id (templates/icons/tier key on this); `key` is the per-variant identity
	local card = Instance.new("Frame"); card.Name = key; card.LayoutOrder = order
	card.BackgroundColor3 = p.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160); card.Parent = petsScroll
	uicorner(card, 12)
	local tierName, tierColor, isVariant, flashy = petTier(p.level, p.rare, petId)
	-- border: variant = its tier color (Exotic/Mythical) glow; else equipped = gold; else default.
	uistroke(card, isVariant and tierColor or (p.equipped and Color3.fromRGB(255,215,0) or Color3.fromRGB(10,40,100)), (isVariant or p.equipped) and 3 or 1)
	-- BIG 3D picture across the top of the card -- the pets are the star of the menu.
	-- SCALE-sized (0.55 of the card = the same 140px it has always been on a 252px cell), so the picture
	-- and the text block below it keep their proportions instead of the picture holding a fixed 140px and
	-- squeezing everything else off the bottom.
	makeViewportIcon(card, petId, p.level, p.rare, UDim2.new(1,-12,0.55,0), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0))
	-- WHOLE CARD OPENS THE SKINS PAGE. A TextButton behind everything (ZIndex 0, fully transparent): the real
	-- controls sit on top and swallow their own clicks, and the pet picture keeps its drag-to-rotate, so this
	-- only catches the empty parts of the card. Routes to the same in-panel page VIEW does -- never a popup.
	local hit = Instance.new("TextButton"); hit.Size = UDim2.new(1,0,1,0); hit.BackgroundTransparency = 1
	hit.Text = ""; hit.AutoButtonColor = false; hit.ZIndex = 0; hit.Parent = card
	hit.MouseButton1Click:Connect(function() _G.PetHub.showDetail(key, p) end)
	-- ---- THE CARD BODY: ONE VERTICAL LIST, NO FIXED OFFSETS ----------------------------------------
	-- Every line below used to be hand-placed at y = 148 / 166 / 182 / 200 / 220 against a card assumed to
	-- be exactly 252px tall. That is what stacked the name, the two info lines, the XP bar and the buttons
	-- on top of each other: the offsets do not move when the card does. A UIListLayout cannot overlap by
	-- construction -- each row is placed after the one before it, whatever height the card ends up.
	--
	-- Sizes are all SCALE, so the block re-proportions with the card instead of overflowing it. Every label
	-- is TextScaled with a UITextSizeConstraint holding its AUTHORED size as the maximum -- so at full size
	-- it renders exactly as it does today, and on a small card the text shrinks rather than spilling into
	-- the row underneath. That cap is also what makes this survive the HUD's blanket TextScaled sweep,
	-- which would otherwise inflate every one of these labels to fill its whole row.
	--
	-- (No AutomaticSize on the card itself: petsScroll is a UIGridLayout, and a grid writes its cells' Size
	-- outright every layout pass -- an AutomaticSize card would just be overwritten.)
	local body = Instance.new("Frame"); body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 8, 0.57, 2)
	body.Size = UDim2.new(1, -16, 0.43, -8)
	body.Parent = card
	do
		local bl = Instance.new("UIListLayout"); bl.FillDirection = Enum.FillDirection.Vertical
		bl.SortOrder = Enum.SortOrder.LayoutOrder; bl.Padding = UDim.new(0, 2); bl.Parent = body
	end
	-- TextScaled + a MAX size. Not TextSize: a fixed size cannot shrink, which is the whole problem.
	local function fitText(o, maxSize)
		o.TextScaled = true
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
		return o
	end

	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,0,0.18,0); nm.LayoutOrder = 1
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold   -- alignment left at its default (centre), as authored
	nm.TextColor3 = isVariant and tierColor or Color3.new(1,1,1)
	nm.Text = p.rare and (p.rareName or p.displayName) or p.displayName; nm.Parent = body -- variant name (e.g. "Cosmic Duck") for rares
	fitText(nm, 18)
	if isVariant then -- a flashy TIER badge (Exotic / Mythical) in the top-right corner
		local tag = Instance.new("TextLabel"); tag.AutomaticSize = Enum.AutomaticSize.X; tag.Size = UDim2.new(0,0,0,18); tag.Position = UDim2.new(1,-6,0,8); tag.AnchorPoint = Vector2.new(1,0)
		tag.BackgroundColor3 = tierColor; tag.Font = Enum.Font.GothamBold; tag.TextSize = 11; tag.TextColor3 = Color3.new(1,1,1); tag.Text = tierName; tag.Parent = card
		local pad = Instance.new("UIPadding", tag); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5)
		uicorner(tag, 5)
		-- thin CLEAN border (not a thick text halo) so the Exotic/Mythical text stays readable
		local ts = Instance.new("UIStroke"); ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Color = Color3.fromRGB(255,255,255); ts.Thickness = 1; ts.Transparency = 0.2; ts.Parent = tag
	end
	if (p.count or 1) > 1 then -- STACK badge: how many of this exact pet (same variant) you have, top-LEFT corner
		local cnt = Instance.new("TextLabel"); cnt.AutomaticSize = Enum.AutomaticSize.X; cnt.Size = UDim2.new(0,0,0,18); cnt.Position = UDim2.new(0,6,0,8)
		cnt.BackgroundColor3 = Color3.fromRGB(255,170,40); cnt.Font = Enum.Font.GothamBold; cnt.TextSize = 12; cnt.TextColor3 = Color3.new(1,1,1); cnt.Text = "x" .. (p.count or 1); cnt.Parent = card
		local cpad = Instance.new("UIPadding", cnt); cpad.PaddingLeft = UDim.new(0,5); cpad.PaddingRight = UDim.new(0,5)
		uicorner(cnt, 5)
		local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(0,0,0); cs.Thickness = 1; cs.Transparency = 0.2; cs.Parent = cnt
	end
	local cap = p.maxLevel or 25
	local maxed = (p.level >= cap)
	-- TIER line: NORMAL = "<Tier>  Lv N" (tier-colored); VARIANT = "<Tier>" (Exotic / Mythical). + EQUIPPED.
	-- REALM + SKIN PROGRESS on one line. Two things a player scanning the grid wants -- where this pet came
	-- from, and how far off completing its wardrobe they are -- without spending a whole row on either.
	do
		local ownedSk, totalSk = _G.PetHub.skinCount(petId)
		local rs = Instance.new("TextLabel"); rs.Size = UDim2.new(1,0,0.14,0); rs.LayoutOrder = 2
		rs.BackgroundTransparency = 1; rs.Font = Enum.Font.Gotham
		rs.TextColor3 = Color3.fromRGB(175,205,250); rs.TextXAlignment = Enum.TextXAlignment.Left
		rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.Parent = body
		rs.Text = (p.islandName or "Bean Farm") .. "   \xC2\xB7   " .. ownedSk .. " / " .. totalSk .. " Skins"
		fitText(rs, 12)
	end
	local lv = Instance.new("TextLabel"); lv.Size = UDim2.new(1,0,0.16,0); lv.LayoutOrder = 3
	lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold
	lv.Text = (isVariant and tierName or (tierName .. "  Age " .. p.level)) .. (p.equipped and "  \xE2\x80\xA2 EQUIPPED" or ""); lv.Parent = body
	lv.TextColor3 = tierColor
	fitText(lv, 13)
	-- XP PROGRESS BAR (current XP / XP needed for the next level)
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,0,0.15,0); barBG.LayoutOrder = 4
	barBG.BackgroundColor3 = Color3.fromRGB(12,40,90); barBG.BorderSizePixel = 0; barBG.Parent = body; uicorner(barBG, 7); uistroke(barBG, Color3.fromRGB(8,26,64), 1)
	local frac = maxed and 1 or math.clamp((p.xp or 0) / math.max(1, p.xpNeed or 1), 0, 1)
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = maxed and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120); fill.Parent = barBG; uicorner(fill, 7)
	local xpTxt = Instance.new("TextLabel"); xpTxt.Size = UDim2.new(1,0,1,0); xpTxt.BackgroundTransparency = 1
	xpTxt.Font = Enum.Font.GothamBold; xpTxt.TextColor3 = Color3.new(1,1,1); xpTxt.Parent = barBG
	xpTxt.Text = maxed and "MAX" or ((p.xp or 0) .. " / " .. (p.xpNeed or 0) .. " XP")
	fitText(xpTxt, 10)
	-- EQUIP / SKIP / VIEW share ONE row -- now a horizontal UIListLayout rather than three hand-placed x
	-- offsets, so the three buttons divide whatever width the card has instead of running off its edge.
	-- VIEW opens the full detail page (big picture, stats, blurb).
	local btnRow = Instance.new("Frame"); btnRow.Name = "Buttons"; btnRow.LayoutOrder = 5
	btnRow.BackgroundTransparency = 1; btnRow.Size = UDim2.new(1,0,0.27,0); btnRow.Parent = body
	do
		local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal
		rl.SortOrder = Enum.SortOrder.LayoutOrder; rl.Padding = UDim.new(0, 4)
		rl.VerticalAlignment = Enum.VerticalAlignment.Center; rl.Parent = btnRow
	end
	-- EQUIP toggle, then SKIP, then VIEW -- the same left-to-right order they were placed in by hand
	local eq = Instance.new("TextButton"); eq.Size = UDim2.new(0.32,0,1,0); eq.LayoutOrder = 1
	eq.Font = Enum.Font.GothamBold; eq.TextColor3 = Color3.new(1,1,1)
	eq.BackgroundColor3 = p.equipped and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	eq.Text = p.equipped and "UNEQUIP" or "EQUIP"; eq.Parent = btnRow
	uicorner(eq, 8); uistroke(eq, Color3.new(0,0,0), 1); fitText(eq, 13)
	eq.MouseButton1Click:Connect(function()
		if p.equipped then pcall(function() PetEquipEvent:FireServer(false) end)
		else pcall(function() PetEquipEvent:FireServer(key) end) end -- equip THIS exact variant (storage key)
	end)
	-- TIER SKIP (Robux): jump the WHOLE next tier at once (lands on its first level). Button shows the next
	-- tier + price; at the top tier (Legendary) there's nothing to skip. The SERVER validates + applies the jump.
	-- 'Skip to Legendary R$599' is the longest string on the card, which is why its cap is the tightest here.
	local sk = Instance.new("TextButton"); sk.Size = UDim2.new(0.32,0,1,0); sk.LayoutOrder = 2
	sk.Font = Enum.Font.GothamBold; sk.TextColor3 = Color3.new(1,1,1)
	sk.Parent = btnRow; uicorner(sk, 8); fitText(sk, 12)
	local more = Instance.new("TextButton"); more.Size = UDim2.new(0.32,0,1,0); more.LayoutOrder = 3
	more.BackgroundColor3 = Color3.fromRGB(38,110,215); more.Font = Enum.Font.GothamBold
	more.TextColor3 = Color3.new(1,1,1); more.Text = "\xF0\x9F\x94\x8D VIEW"; more.Parent = btnRow
	uicorner(more, 6); uistroke(more, Color3.fromRGB(10,40,100), 1); fitText(more, 12)
	more.MouseButton1Click:Connect(function() _G.PetHub.showDetail(key, p) end)
	-- which tier-skip step applies to this pet's CURRENT level (Common 1-5 / Uncommon 6-10 / Rare 11-15 / Epic 16-20)
	local skipStep = (p.level <= 5 and PET_SKIP_PRODUCTS[1]) or (p.level <= 10 and PET_SKIP_PRODUCTS[2])
		or (p.level <= 15 and PET_SKIP_PRODUCTS[3]) or (p.level <= 20 and PET_SKIP_PRODUCTS[4]) or nil
	if maxed or not skipStep then
		sk.Text = maxed and "MAX LEVEL" or "MAX TIER"; sk.BackgroundColor3 = Color3.fromRGB(90,90,90); sk.AutoButtonColor = false
	else
		sk.Text = "Skip to " .. skipStep.to .. "  R$" .. skipStep.price; sk.BackgroundColor3 = Color3.fromRGB(50,170,90)
		sk.MouseButton1Click:Connect(function()
			pcall(function() PetPendingUpgrade:FireServer(key) end) -- declare the pet (testers tier-skip instantly here)
			task.wait(0.15)
			pcall(function() game:GetService("MarketplaceService"):PromptProductPurchase(player, skipStep.id) end)
		end)
	end
end

-- A LOCKED pet card -- one for every pet in the catalog the player does NOT own yet. The pet is shown in FULL
-- COLOUR, exactly as it really looks (same blue card, same spinning 3D model as an owned pet) -- seeing the actual
-- prize is what makes a player want it. "Locked" is communicated by the padlock badge, the gold LOCKED line and
-- the how-to-get-it text, NOT by hiding or greying the pet. The only thing missing vs an owned card is the
-- EQUIP/SKIP buttons (there's nothing to equip yet). The hint says where to go, never where things hide.
local function buildLockedPetCard(info, order)
	local petId = info.petId
	local card = Instance.new("Frame"); card.Name = "Locked_" .. tostring(petId); card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(20, 70, 160); card.Parent = petsScroll -- SAME blue as an owned card
	uicorner(card, 12); uistroke(card, Color3.fromRGB(255, 190, 60), 2) -- gold "locked" border (owned+equipped = solid gold)
	makeViewportIcon(card, petId, 1, false, UDim2.new(1,-12,0.55,0), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0)) -- full colour, Lv1 look
	-- padlock badge over the top-right of the picture -- this (not a grey-out) is what marks the card as locked
	local lock = Instance.new("TextLabel"); lock.Size = UDim2.new(0,28,0,28); lock.Position = UDim2.new(1,-12,0,12); lock.AnchorPoint = Vector2.new(1,0)
	lock.BackgroundTransparency = 1; lock.Font = Enum.Font.FredokaOne; lock.TextScaled = true; lock.Text = "\xF0\x9F\x94\x92"; lock.Parent = card
	-- The same vertical list the owned card uses, for the same reason -- these sat at y = 150/170/188/204/230
	-- and stacked on a shorter card. Locked and owned cards share a grid, so they have to share the treatment
	-- or they stop lining up with each other.
	local body = Instance.new("Frame"); body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 8, 0.57, 2)
	body.Size = UDim2.new(1, -16, 0.43, -8)
	body.Parent = card
	do
		local bl = Instance.new("UIListLayout"); bl.FillDirection = Enum.FillDirection.Vertical
		bl.SortOrder = Enum.SortOrder.LayoutOrder; bl.Padding = UDim.new(0, 2); bl.Parent = body
	end
	local function fitText(o, maxSize)
		o.TextScaled = true
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
		return o
	end
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,0,0.18,0); nm.LayoutOrder = 1
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold
	nm.TextColor3 = Color3.new(1,1,1); nm.Text = info.displayName or petId; nm.Parent = body
	fitText(nm, 18)
	local st = Instance.new("TextLabel"); st.Size = UDim2.new(1,0,0.16,0); st.LayoutOrder = 2
	st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold
	st.TextColor3 = Color3.fromRGB(255,205,90); st.Text = "\xF0\x9F\x94\x92 LOCKED" .. (info.islandName and ("  \xE2\x80\xA2  " .. info.islandName) or ""); st.Parent = body
	fitText(st, 13)
	-- Same realm + skin-progress line the owned cards carry, so the grid reads consistently. Skins CAN be won
	-- for a pet you have not unlocked yet, so this number is not always 1 -- which is precisely the nudge to
	-- go and earn the pet.
	do
		local ownedSk, totalSk = _G.PetHub.skinCount(petId)
		local rs = Instance.new("TextLabel"); rs.Size = UDim2.new(1,0,0.14,0); rs.LayoutOrder = 3
		rs.BackgroundTransparency = 1; rs.Font = Enum.Font.Gotham
		rs.TextColor3 = Color3.fromRGB(175,205,250); rs.TextXAlignment = Enum.TextXAlignment.Left
		rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.Parent = body
		rs.Text = (info.islandName or "???") .. "   \xC2\xB7   " .. ownedSk .. " / " .. totalSk .. " Skins"
		fitText(rs, 12)
	end
	local how = Instance.new("TextLabel"); how.Size = UDim2.new(1,0,0.26,0); how.LayoutOrder = 4
	how.BackgroundTransparency = 1; how.Font = Enum.Font.Gotham; how.TextWrapped = true
	how.TextColor3 = Color3.fromRGB(205,222,255); how.TextYAlignment = Enum.TextYAlignment.Top
	how.Text = info.unlock or "Keep exploring to find this pet"; how.Parent = body
	fitText(how, 12)
	-- locked pets get a VIEW MORE too -- the detail card shows the pet big with its blurb and how to unlock it,
	-- which is exactly the pitch for going and earning it.
	local more = Instance.new("TextButton"); more.Size = UDim2.new(1,0,0.22,0); more.LayoutOrder = 5
	more.BackgroundColor3 = Color3.fromRGB(150,110,30); more.Font = Enum.Font.GothamBold
	-- VIEW QUEST, not VIEW MORE: a locked pet has nothing to customise, so the only useful thing this page can
	-- tell you is how to earn it. The card is deliberately NOT click-through either -- clicking a locked pet
	-- must never land you on a skins page you cannot use.
	more.TextColor3 = Color3.new(1,1,1); more.Text = "\xF0\x9F\x94\x92 VIEW QUEST"; more.Parent = body
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90,66,16), 1); fitText(more, 12)
	more.MouseButton1Click:Connect(function() _G.PetHub.showDetail(nil, info) end)
end

-- one discovered-quest entry (island name + status + short how-to + small progress) into the QUESTS list
local function buildQuestEntry(q, order)
	local qf = Instance.new("Frame"); qf.Name = "Quest"; qf.LayoutOrder = order; qf.Size = UDim2.new(1,-4,0,92); qf.BackgroundColor3 = Color3.fromRGB(20,70,160); qf.Parent = questsScroll
	uicorner(qf, 8); uistroke(qf, Color3.fromRGB(10,40,100), 1)
	-- name / status / description as a list rather than y = 4/22/38 in a 92px box
	local qbody = Instance.new("Frame"); qbody.Name = "Body"; qbody.BackgroundTransparency = 1
	qbody.Position = UDim2.new(0,6,0,4); qbody.Size = UDim2.new(1,-12,1,-8); qbody.Parent = qf
	do
		local ql = Instance.new("UIListLayout"); ql.FillDirection = Enum.FillDirection.Vertical
		ql.SortOrder = Enum.SortOrder.LayoutOrder; ql.Padding = UDim.new(0,2); ql.Parent = qbody
	end
	local function qfit(o, maxSize)
		o.TextScaled = true
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = maxSize; c.Parent = o
	end
	local qn = Instance.new("TextLabel"); qn.Size = UDim2.new(1,0,0.21,0); qn.LayoutOrder = 1
	qn.BackgroundTransparency = 1; qn.Font = Enum.Font.GothamBold; qn.TextColor3 = Color3.new(1,1,1); qn.TextXAlignment = Enum.TextXAlignment.Left; qn.Text = q.islandName or "?"; qn.Parent = qbody
	qfit(qn, 14)
	local statusCol = (q.status == "done") and Color3.fromRGB(120,255,120) or (q.status == "inprogress") and Color3.fromRGB(255,205,90) or Color3.fromRGB(180,220,255)
	local statusTxt = (q.status == "done") and "Done \xE2\x9C\x94"
		or (q.status == "inprogress") and ("In Progress  "..(q.found or 0).."/"..(q.total or 0).." "..(q.unit or ""))
		or "Available"
	local qs = Instance.new("TextLabel"); qs.Size = UDim2.new(1,0,0.16,0); qs.LayoutOrder = 2
	qs.BackgroundTransparency = 1; qs.Font = Enum.Font.GothamBold; qs.TextColor3 = statusCol; qs.TextXAlignment = Enum.TextXAlignment.Left; qs.Text = statusTxt; qs.Parent = qbody
	qfit(qs, 11)
	local qd = Instance.new("TextLabel"); qd.Size = UDim2.new(1,0,0.55,0); qd.LayoutOrder = 3
	qd.BackgroundTransparency = 1; qd.Font = Enum.Font.Gotham; qd.TextColor3 = Color3.fromRGB(205,222,255); qd.TextWrapped = true
	qd.TextXAlignment = Enum.TextXAlignment.Left; qd.TextYAlignment = Enum.TextYAlignment.Top; qd.Text = q.desc or ""; qd.Parent = qbody
	qfit(qd, 11)
end

-- ===== COLLECTION REWARDS OVERLAY ("REWARDS" tab) =========================================================
-- Shows the four collection milestones, what each pays, and a live progress bar to the next one. This is what
-- turns the "7 / 10 collected" counter in the header from a stat into a GOAL -- without it a player can see they
-- are missing three pets but has no idea that finishing pays anything.
-- Built fresh on open and killed by name (like the VIEW MORE card), so it costs no module-scope local beyond this
-- one function -- this file sits close to Luau's 200-locals-per-scope ceiling.
_G.PetHub.showMilestones = function()
	local old = panel:FindFirstChild("MilestonesOverlay"); if old then old:Destroy() end
	_G.PetHub.hideDetail(); questsOverlay.Visible = false
	local ms = latestInv.milestones or {}
	local have, target = latestInv.collected or 0, latestInv.totalPets or 0

	local d = Instance.new("Frame"); d.Name = "MilestonesOverlay"; d.Size = UDim2.new(1,-24,1,-74); d.Position = UDim2.new(0,12,0,68)
	d.BackgroundColor3 = Color3.fromRGB(16,60,140); d.ZIndex = 5; d.Parent = panel
	uicorner(d, 12); uistroke(d, Color3.fromRGB(255,215,0), 2)

	local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,-130,0,28); t.Position = UDim2.new(0,14,0,10)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 18; t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Color3.fromRGB(255,215,0); t.ZIndex = 7; t.Text = "\xF0\x9F\x8F\x86 Collection Rewards"; t.Parent = d
	local back = Instance.new("TextButton"); back.Size = UDim2.new(0,110,0,28); back.Position = UDim2.new(1,-118,0,10)
	back.BackgroundColor3 = Color3.fromRGB(120,120,120); back.Font = Enum.Font.GothamBold; back.TextSize = 13
	back.TextColor3 = Color3.new(1,1,1); back.Text = "\xE2\x97\x80 All Pets"; back.ZIndex = 7; back.Parent = d
	uicorner(back, 8)
	back.MouseButton1Click:Connect(function() d:Destroy() end)

	-- BIG progress bar: how far through the whole collection you are.
	local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(1,-28,0,26); barBG.Position = UDim2.new(0,14,0,46)
	barBG.BackgroundColor3 = Color3.fromRGB(12,40,90); barBG.BorderSizePixel = 0; barBG.ZIndex = 6; barBG.Parent = d
	uicorner(barBG, 13); uistroke(barBG, Color3.fromRGB(8,26,64), 1)
	local frac = (target > 0) and math.clamp(have / target, 0, 1) or 0
	local fill = Instance.new("Frame"); fill.Size = UDim2.new(frac,0,1,0); fill.BorderSizePixel = 0; fill.ZIndex = 6
	fill.BackgroundColor3 = (have >= target) and Color3.fromRGB(255,200,40) or Color3.fromRGB(80,220,120)
	fill.Parent = barBG; uicorner(fill, 13)
	local bt = Instance.new("TextLabel"); bt.Size = UDim2.new(1,0,1,0); bt.BackgroundTransparency = 1; bt.ZIndex = 7
	bt.Font = Enum.Font.GothamBold; bt.TextSize = 13; bt.TextColor3 = Color3.new(1,1,1); bt.Parent = barBG
	bt.Text = have .. " / " .. target .. " pets collected" .. ((have >= target) and "  \xE2\x80\xA2  COMPLETE!" or "")

	local sc = Instance.new("ScrollingFrame"); sc.Size = UDim2.new(1,-28,1,-90); sc.Position = UDim2.new(0,14,0,82)
	sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 5
	sc.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); sc.CanvasSize = UDim2.new(0,0,0,0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.ZIndex = 6; sc.Parent = d
	do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0,6); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = sc end

	for i, m in ipairs(ms) do
		local done = m.claimed == true
		local row = Instance.new("Frame"); row.Size = UDim2.new(1,-8,0,58); row.LayoutOrder = i
		row.BackgroundColor3 = done and Color3.fromRGB(28,96,52) or Color3.fromRGB(12,44,104)
		row.BackgroundTransparency = 0.25; row.BorderSizePixel = 0; row.ZIndex = 6; row.Parent = sc
		uicorner(row, 8)
		uistroke(row, done and Color3.fromRGB(90,220,120) or Color3.fromRGB(10,40,100), done and 2 or 1)
		-- the milestone's requirement, as a chunky badge on the left
		local badge = Instance.new("TextLabel"); badge.Size = UDim2.new(0,54,0,38); badge.Position = UDim2.new(0,10,0,10)
		badge.BackgroundColor3 = done and Color3.fromRGB(60,180,90) or Color3.fromRGB(30,70,150)
		badge.Font = Enum.Font.FredokaOne; badge.TextSize = 18; badge.TextColor3 = Color3.new(1,1,1)
		badge.ZIndex = 7; badge.Text = m.need .. "/" .. target; badge.Parent = row
		uicorner(badge, 6)
		local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-150,0,20); nm.Position = UDim2.new(0,74,0,9)
		nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 15
		nm.TextXAlignment = Enum.TextXAlignment.Left; nm.ZIndex = 7
		nm.TextColor3 = (m.kind == "pet") and Color3.fromRGB(255,190,60) or Color3.new(1,1,1)
		nm.Text = m.name or ""; nm.Parent = row
		local ds = Instance.new("TextLabel"); ds.Size = UDim2.new(1,-150,0,18); ds.Position = UDim2.new(0,74,0,29)
		ds.BackgroundTransparency = 1; ds.Font = Enum.Font.Gotham; ds.TextSize = 12
		ds.TextColor3 = Color3.fromRGB(190,212,255); ds.TextXAlignment = Enum.TextXAlignment.Left
		ds.TextWrapped = true; ds.ZIndex = 7; ds.Text = m.desc or ""; ds.Parent = row
		local st = Instance.new("TextLabel"); st.Size = UDim2.new(0,66,0,20); st.Position = UDim2.new(1,-74,0,19)
		st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold; st.TextSize = 12
		st.TextXAlignment = Enum.TextXAlignment.Right; st.ZIndex = 7
		st.TextColor3 = done and Color3.fromRGB(120,255,140) or Color3.fromRGB(150,175,215)
		st.Text = done and "EARNED \xE2\x9C\x94" or ((math.max(0, m.need - have)) .. " to go")
		st.Parent = row
	end
	print(string.format("[PetInv] rewards tab opened (%d/%d collected)", have, target))
end

-- Rebuild is FAILURE-TOLERANT: each card/icon build is pcall'd so one bad pet (e.g. a rare-variant 3D icon
-- that fails to build) can't abort the whole rebuild and leave the menu empty/broken. The whole thing is
-- pcall-wrapped too, so a rebuild error can never knock the Hub into a state where it won't open.
local function rebuildInventory(payload)
	local ok, err = pcall(function()
		latestInv = payload or { owned = {}, quests = {}, catalog = {}, totalPets = 0 }
		local owned, quests, totalPets = latestInv.owned or {}, latestInv.quests or {}, latestInv.totalPets or 0
		local catalog = latestInv.catalog or {}
		-- PETS section: OWNED cards first (sorted by tier), then a LOCKED card for every pet in the catalog the
		-- player hasn't collected yet -- so the Hub shows the WHOLE collection, not just what they already have.
		-- DON'T table.clear(iconSpins) here. It used to be safe (every spinning model lived in a grid card that this
		-- function destroys and rebuilds), but the VIEW MORE detail card's big 3D pet is parented to the OVERLAY,
		-- which survives a rebuild -- the patch path below updates its numbers in place precisely so the model, and
		-- its rotation, are left alone. Clearing the list would silently drop that entry and the detail pet would
		-- freeze the first time an inventory push landed. The spin loop already prunes entries whose model has lost
		-- its Parent (which is exactly what destroying the old cards below does), so pruning here is redundant too.
		for _, c in ipairs(petsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local ownedCount, order = 0, 0
		-- SORT owned pets by RARITY TIER, then by LEVEL (high->low). The ranking follows the ACTUAL odds, so it
		-- matches the tier ladder on the detail card exactly:
		--   Mythical (1/10,000) > Legendary (1/1000) > Exotic (1/750) > Epic (1/125) > Rare > Uncommon > Common
		-- LEGENDARY OUTRANKS EXOTIC -- a Legendary really is the rarer pull, so it sorts above it. (This was the
		-- other way round while Exotic was 1/99; if you retune the odds again, re-check this table AND the ladder.)
		-- All locals here are function-scoped (no new module-scope locals).
		-- age names since the ladder rename (rarity words belong to skins now); Exotic/Mythical variants still top
		local rank = { Mythical = 7, Exotic = 6, Elder = 5, Adult = 4, Teen = 3, Kid = 2, Baby = 1 }
		-- `owned` is keyed by STORAGE KEY (petId or petId#R) -> a species can have two cards (normal + rare). Sort by
		-- the SPECIES tier (p.petId), never the raw key, so the "#R" suffix never confuses petTier.
		local ids = {}
		for skey in pairs(owned) do ids[#ids + 1] = skey end
		table.sort(ids, function(a, b)
			local pa, pb = owned[a], owned[b]
			local ra = rank[petTier(pa.level or 1, pa.rare, pa.petId)] or 0 -- petTier's 1st return value = tier name
			local rb = rank[petTier(pb.level or 1, pb.rare, pb.petId)] or 0
			if ra ~= rb then return ra > rb end                       -- higher tier first (Mythical leads)
			return (pa.level or 0) > (pb.level or 0)                  -- same tier: higher level first
		end)
		for _, skey in ipairs(ids) do
			ownedCount = ownedCount + 1; order = order + 1
			local okc, ec = pcall(buildPetCard, skey, owned[skey], order) -- per-card: a bad icon can't abort the rest
			if not okc then warn("[PetInv] card build failed for " .. tostring(skey) .. ": " .. tostring(ec)) end
		end
		-- LOCKED cards: one for every catalogued pet this player owns ZERO of, appended after the owned ones in a
		-- STABLE order (species id, alphabetical) so the grid never reshuffles between rebuilds. Each shows the pet
		-- in FULL COLOUR with a padlock + how-to-get-it line. Per-card pcall: one bad card can't abort the grid.
		-- (These replace the old "No Pets Unlocked" message -- an empty collection now shows the full locked set,
		-- which tells the player far more than a blank panel did.)
		local lockedIds = {}
		for _, info in ipairs(catalog) do
			if not info.owned then lockedIds[#lockedIds + 1] = info end
		end
		table.sort(lockedIds, function(a, b) return tostring(a.petId) < tostring(b.petId) end)
		local lockedCount = 0
		for _, info in ipairs(lockedIds) do
			lockedCount = lockedCount + 1; order = order + 1
			local okl, el = pcall(buildLockedPetCard, info, order)
			if not okl then warn("[PetInv] locked card build failed for " .. tostring(info.petId) .. ": " .. tostring(el)) end
		end
		-- COLLECTION COUNTER in the Hub header, so "how many am I missing" is answerable at a glance.
		-- Take `collected` and `totalPets` STRAIGHT FROM THE SERVER -- do NOT derive it as (totalPets - lockedCount)
		-- any more. The catalog now contains 11 pets but the collection target is 10: the secret Pizza Dragon is the
		-- PRIZE for finishing, not part of the set, so the server excludes it from both counts. Deriving the count
		-- from the locked cards would silently fold the Dragon back in and the header could never reach 10/10.
		local collected = latestInv.collected or 0
		subtitle.Text = (totalPets > 0)
			and string.format("%d / %d pets collected%s", collected, totalPets, (lockedCount == 0) and "  \xE2\x80\xA2  COMPLETE!" or "")
			or "Your pets & quest progress"
		local rows = math.ceil((ownedCount + lockedCount) / 2) -- 2 BIG cards per row (252 tall + 12 padding)
		petsScroll.CanvasSize = UDim2.new(0,0,0, rows * 264 + 20)
		-- If a VIEW MORE detail card is open, re-render it against the FRESH payload so a level-up / equip / trade
		-- push can't leave stale numbers on screen. If that pet is no longer owned (traded away while being viewed)
		-- or a locked one just got unlocked, fall back to the grid rather than showing a card for a stale state.
		local pd = panel:FindFirstChild("PetDetailOverlay")
		if pd then
			local k, pid = pd:GetAttribute("PetKey"), pd:GetAttribute("PetSpecies")
			if k and k ~= "" then                                   -- was showing an OWNED pet
				if owned[k] then pcall(_G.PetHub.showDetail, k, owned[k]) else _G.PetHub.hideDetail() end
			elseif pid then                                          -- was showing a LOCKED pet
				local still
				for _, info in ipairs(catalog) do if info.petId == pid and not info.owned then still = info end end
				if still then pcall(_G.PetHub.showDetail, nil, still) else _G.PetHub.hideDetail() end
			end
		end
		print(string.format("[PetInv] pet index: %d owned card(s), %d locked card(s), %d/%d species collected",
			ownedCount, lockedCount, collected, totalPets))
		-- The grid has just counted these for its own log line; reuse them rather than counting a second time
		-- somewhere else and risking two different answers on screen at once.
		pcall(function() _G.PetHub.setProgress(collected, totalPets) end)
		-- QUESTS section: discovered quests
		for _, c in ipairs(questsScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		local qCount = 0
		for _, q in pairs(quests) do qCount = qCount + 1; pcall(buildQuestEntry, q, qCount) end
		questsEmpty.Visible = (qCount == 0)
		questsScroll.CanvasSize = UDim2.new(0,0,0, qCount * 100 + 8)
	end)
	if not ok then warn("[PetInv] ERROR building inventory: " .. tostring(err)) end
end
if PetInventoryEvent then PetInventoryEvent.OnClientEvent:Connect(rebuildInventory) end

-- =====================================================================================================
-- TIER-UP SOUND: the pet crossed into the NEXT tier (Baby -> Kid -> Teen -> Adult -> Elder).
-- =====================================================================================================
-- NOT a per-level sound. Levels tick over constantly (coins and flight both feed XP), so a sound on every
-- level-up would be noise -- this fires only on the FOUR level-ups that change the pet's TIER, i.e. the
-- steps that actually rename the badge over its head and unlock the next look:
--     5 -> 6 (Baby -> Kid) | 10 -> 11 (Kid -> Teen) | 15 -> 16 (Teen -> Adult) | 20 -> 21 (Adult -> Elder)
-- The bands are petTier()'s, read from the same authoritative inventory payload the cards are built from,
-- so this can never disagree with what the badge says. (petTier's labels are ages now -- Baby/Kid/Teen/
-- Adult/Elder -- but they are the same five bands the old Common/Uncommon/Rare/Epic/Legendary ladder used.)
--
-- A SEPARATE connection, not a line inside rebuildInventory: that function is a big pcall'd rebuild, and a
-- sound has no business being skipped because a card failed to draw.
--
-- Rare variants (Exotic / Mythical) are LOOK tiers, not level bands -- they hatch pre-maxed and never climb,
-- so they're excluded; their fanfare is PetRareEvent's, at hatch.
do
	local tierUpSound = Instance.new("Sound")
	tierUpSound.Name = "PetTierUpSound"
	tierUpSound.SoundId = "rbxassetid://117166473587029"
	tierUpSound.Volume = 3            -- matches the hatch sounds: a milestone should land, not whisper
	tierUpSound.Parent = SoundService -- SoundService (not the pet) = 2D, always audible, and SettingsMenu's
	                                  -- SFX toggle routes it like every other ungrouped sound
	task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ tierUpSound }) end) end)

	-- Band index for a level: 1=Baby(1-5) 2=Kid(6-10) 3=Teen(11-15) 4=Adult(16-20) 5=Elder(21+).
	local function bandOf(level)
		level = tonumber(level) or 1
		if level <= 5 then return 1
		elseif level <= 10 then return 2
		elseif level <= 15 then return 3
		elseif level <= 20 then return 4
		else return 5 end
	end

	local lastBand = {}     -- storage key -> the band this pet was in at the previous payload
	local baselined = false -- the FIRST payload only RECORDS: joining with a Teen pet is not a tier-up

	if PetInventoryEvent then
		PetInventoryEvent.OnClientEvent:Connect(function(payload)
			local owned = (type(payload) == "table" and payload.owned) or nil
			if type(owned) ~= "table" then return end
			local rang = false
			for skey, p in pairs(owned) do
				if type(p) == "table" and not p.rare then -- rare variants sit outside the level bands
					local band = bandOf(p.level)
					local prev = lastBand[skey]
					-- Only ever UPWARD, and only on a real transition. Levels never fall, but a trade or a
					-- fresh payload for a pet we've not seen (prev == nil) must not sound.
					if baselined and prev and band > prev and not rang then
						rang = true -- one sound per payload, even if a crate pushed two pets up at once
						pcall(function() tierUpSound:Play() end)
						print(string.format("[PetLvl] %s reached a NEW TIER (Lv %s) -- tier-up sound played",
							tostring(p.petId or skey), tostring(p.level)))
					end
					lastBand[skey] = band
				end
			end
			-- Pets that vanished from the payload (traded away) shouldn't keep a stale band around: if that key
			-- comes back later it must re-baseline rather than sound off the old number.
			for skey in pairs(lastBand) do
				if owned[skey] == nil then lastBand[skey] = nil end
			end
			baselined = true
		end)
	end
end

-- =====================================================================================================
-- STAGE 3: TRADE UI (housed in the Pet Hub). The client sends INTENTS only; the server owns the trade.
-- =====================================================================================================
-- Wrapped in a function ON PURPOSE -- do NOT flatten it back out to top level.
-- Luau allows only 200 locals live at once PER FUNCTION, and the main chunk of this file had hit exactly
-- that: `renderTradeWindow` below was the 201st, so it failed to COMPILE, which kills the whole script --
-- no pet follow, no broccoli pieces, no egg, nothing. A function body gets its own register frame, so
-- these 25 locals no longer count against the main chunk. A do...end block would NOT have worked: it only
-- frees registers after its `end`, and the overflow happens inside. If you add more top-level locals to
-- this file, wrap them in a function like this one.
local function buildTradeUI()
local PlayersSvc = game:GetService("Players")
local tradeState = nil -- latest server trade state (active=true while trading)

-- a compact offered-pet row (reuses the tier colors). `onClick` makes it a button (add/remove).
local function makeOfferRow(parent, brief, order, onClick)
	local row = Instance.new(onClick and "TextButton" or "TextLabel"); row.Size = UDim2.new(1,-6,0,26); row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Text = ""; row.Parent = parent; uicorner(row, 6)
	if onClick then row.AutoButtonColor = true end
	local tname, tcol = petTier(brief.level, brief.rare, brief.petId)
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-10,1,0); nm.Position = UDim2.new(0,6,0,0); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 12; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextColor3 = tcol
	nm.Text = brief.name .. "  (" .. tname .. (brief.rare and "" or ("  Lv" .. tostring(brief.level))) .. ")"; nm.Parent = row
	if onClick then row.MouseButton1Click:Connect(onClick) end
	return row
end

-- an OFFERED-pet CARD with the pet's real 3D PICTURE + name + level + rarity tier (anti-scam: each player
-- can SEE exactly what's being offered). Reuses the same ViewportFrame renderer as the menu icons. `onClick`
-- (your side) makes it a remove button; their side passes nil (read-only).
local function makeOfferCard(parent, brief, order, onClick)
	local card = Instance.new(onClick and "TextButton" or "TextLabel")
	card.Size = UDim2.new(1,-6,0,76); card.LayoutOrder = order
	card.BackgroundColor3 = brief.rare and Color3.fromRGB(46,28,86) or Color3.fromRGB(20,70,160)
	card.Text = ""; if onClick then card.AutoButtonColor = true end; card.Parent = parent; uicorner(card, 8)
	local tname, tcol, isVariant = petTier(brief.level, brief.rare, brief.petId)
	uistroke(card, isVariant and tcol or Color3.fromRGB(10,40,100), isVariant and 2 or 1)
	makeViewportIcon(card, brief.petId, brief.level, brief.rare, UDim2.new(0,96,0,68), UDim2.new(0,4,0,4), Vector2.new(0,0))
	local nm = Instance.new("TextLabel"); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 14
	nm.TextColor3 = isVariant and tcol or Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Position = UDim2.new(0,108,0,8); nm.Size = UDim2.new(1,-114,0,20); nm.Text = brief.name; nm.Parent = card
	local lv = Instance.new("TextLabel"); lv.BackgroundTransparency = 1; lv.Font = Enum.Font.GothamBold; lv.TextSize = 12
	lv.TextColor3 = tcol; lv.TextXAlignment = Enum.TextXAlignment.Left
	lv.Position = UDim2.new(0,108,0,32); lv.Size = UDim2.new(1,-114,0,18)
	lv.Text = isVariant and tname or (tname .. "  Age " .. tostring(brief.level)); lv.Parent = card
	if onClick then
		local h = Instance.new("TextLabel"); h.BackgroundTransparency = 1; h.Font = Enum.Font.Gotham; h.TextSize = 11; h.TextColor3 = Color3.fromRGB(255,190,190)
		h.TextXAlignment = Enum.TextXAlignment.Left; h.Position = UDim2.new(0,108,0,52); h.Size = UDim2.new(1,-114,0,16); h.Text = "Click to remove \xE2\x9C\x95"; h.Parent = card
		card.MouseButton1Click:Connect(onClick)
	end
	return card
end

-- TRADE button in the Pet Hub header
-- HEADER BUTTON ROW -- five compact chips, right to left, ending just left of the X.
-- 82x26 (25% smaller than the old 110x34) on an 88px pitch: X at -138 / -226 / -314 / -402 / -490.
-- At the old sizes the row ran out to x=102 on a 700-wide panel -- straight under "PET HUB" and its subtitle.
-- At 82 the row stops at x=210, so the title has clear space. Every one gets TextScaled + a MaxTextSize 11
-- constraint so a longer label shrinks to fit instead of clipping.
local tradeBtn = Instance.new("TextButton"); tradeBtn.Size = UDim2.new(0,82,0,26); tradeBtn.Position = UDim2.new(1,-138,0,17)
tradeBtn.BackgroundColor3 = Color3.fromRGB(80,160,255); tradeBtn.Font = Enum.Font.GothamBold; tradeBtn.TextSize = 14; tradeBtn.TextColor3 = Color3.new(1,1,1)
tradeBtn.Text = "\xF0\x9F\x94\x81 TRADE"; tradeBtn.Parent = header; uicorner(tradeBtn, 8); uistroke(tradeBtn, Color3.new(0,0,0), 2)
tradeBtn.Visible = false -- replaced by the HubNav bar under the header; handler kept so nothing rewires
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = tradeBtn; tradeBtn.TextScaled = true end -- shrink-to-fit on the 82px chip

-- TRADE OVERLAY (covers the panel body)
local tradeOverlay = Instance.new("Frame"); tradeOverlay.Name = "TradeOverlay"; tradeOverlay.Size = UDim2.new(1,-24,1,-116); tradeOverlay.Position = UDim2.new(0,12,0,110)
tradeOverlay.BackgroundColor3 = Color3.fromRGB(16,60,140); tradeOverlay.Visible = false; tradeOverlay.Parent = panel; uicorner(tradeOverlay, 12); uistroke(tradeOverlay, Color3.fromRGB(10,40,100), 2)
local ovTitle = Instance.new("TextLabel"); ovTitle.Size = UDim2.new(1,-120,0,28); ovTitle.Position = UDim2.new(0,12,0,8); ovTitle.BackgroundTransparency = 1
ovTitle.Font = Enum.Font.GothamBold; ovTitle.TextSize = 18; ovTitle.TextColor3 = Color3.fromRGB(255,215,0); ovTitle.TextXAlignment = Enum.TextXAlignment.Left; ovTitle.Text = "Trade"; ovTitle.Parent = tradeOverlay
local ovBack = Instance.new("TextButton"); ovBack.Size = UDim2.new(0,100,0,28); ovBack.Position = UDim2.new(1,-108,0,8); ovBack.BackgroundColor3 = Color3.fromRGB(120,120,120)
ovBack.Font = Enum.Font.GothamBold; ovBack.TextSize = 13; ovBack.TextColor3 = Color3.new(1,1,1); ovBack.Text = "\xE2\x97\x80 Pets"; ovBack.Parent = tradeOverlay; uicorner(ovBack, 8)

-- VIEW 1: pick a player to request a trade
local pickerView = Instance.new("Frame"); pickerView.Size = UDim2.new(1,-16,1,-46); pickerView.Position = UDim2.new(0,8,0,42); pickerView.BackgroundTransparency = 1; pickerView.Parent = tradeOverlay
local pickerScroll = Instance.new("ScrollingFrame"); pickerScroll.Size = UDim2.new(1,0,1,0); pickerScroll.BackgroundTransparency = 1; pickerScroll.BorderSizePixel = 0
pickerScroll.ScrollBarThickness = 6; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(255,215,0); pickerScroll.CanvasSize = UDim2.new(0,0,0,0); pickerScroll.Parent = pickerView
local pickerLayout = Instance.new("UIListLayout"); pickerLayout.Padding = UDim.new(0,6); pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder; pickerLayout.Parent = pickerScroll

-- VIEW 2: the trade window (your side / their side / add list / confirm + cancel)
local windowView = Instance.new("Frame"); windowView.Size = UDim2.new(1,-16,1,-46); windowView.Position = UDim2.new(0,8,0,42); windowView.BackgroundTransparency = 1; windowView.Visible = false; windowView.Parent = tradeOverlay
local function colTitle(text, x) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,310,0,18); l.Position = UDim2.new(0,x,0,0); l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamBold; l.TextSize = 14; l.TextColor3 = Color3.fromRGB(255,215,0); l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.Parent = windowView; return l end
-- w defaults to 300 (one trade panel). The tap-to-add strip passes the full window width.
local function colScroll(x, y, h, w) local s = Instance.new("ScrollingFrame"); s.Size = UDim2.new(0,w or 300,0,h); s.Position = UDim2.new(0,x,0,y); s.BackgroundColor3 = Color3.fromRGB(12,44,104); s.BorderSizePixel = 0; s.ScrollBarThickness = 5; s.CanvasSize = UDim2.new(0,0,0,0); s.Parent = windowView; uicorner(s,8); local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = s; return s end
-- ============================================================================================================
-- THE TRADE FLOOR: two identical panels, an exchange arrow between them, one READY underneath.
-- ============================================================================================================
-- 300 + 48 + 300 = 648 of the window's 660, so the two offers are the same width to the pixel and the arrow
-- sits dead centre between them. Whatever is being traded is the biggest thing on the page; everything else
-- (tokens, status, buttons) is a thin strip underneath it.
--
-- GEOMETRY ONLY below this line. Every one of these widgets keeps its exact variable name, because
-- renderTradeWindow and the whole live trade session drive them by name -- nothing about how a trade works
-- changed, only where the pieces sit.
colTitle("YOUR OFFER", 0)
do
	local sb = colTitle("(click an item to remove)", 0)
	sb.Position = UDim2.new(0,0,0,17); sb.Size = UDim2.new(0,300,0,14)
	sb.Font = Enum.Font.Gotham; sb.TextSize = 11; sb.TextColor3 = Color3.fromRGB(175,205,250)
end
local yourOfferScroll = colScroll(0, 34, 140)

-- EXCHANGE ARROW, centred in the 48px gutter. Purely a sign that these two piles swap -- no state, no clicks.
do
	local sw = Instance.new("TextLabel"); sw.Size = UDim2.new(0,48,0,48); sw.Position = UDim2.new(0,300,0,80)
	sw.BackgroundTransparency = 1; sw.Font = Enum.Font.FredokaOne; sw.TextScaled = true
	sw.TextColor3 = Color3.fromRGB(255,215,0); sw.Text = "\xE2\x87\x84"; sw.Parent = windowView
	uistroke(sw, Color3.new(0,0,0), 2)
end

colTitle("THEIR OFFER", 348)
do
	local sb = colTitle("(what you will receive)", 348)
	sb.Position = UDim2.new(0,348,0,17); sb.Size = UDim2.new(0,300,0,14)
	sb.Font = Enum.Font.Gotham; sb.TextSize = 11; sb.TextColor3 = Color3.fromRGB(175,205,250)
end
local theirOfferScroll = colScroll(348, 34, 140)

-- TAP TO ADD, full width under both panels. It is a strip rather than a pop-out picker on purpose: this page
-- must never open a floating window, and a permanently visible shelf is also fewer taps than open-pick-close.
local addTitleLbl = colTitle("YOUR PETS & SKINS (click to add)", 0)
addTitleLbl.Position = UDim2.new(0,0,0,178); addTitleLbl.Size = UDim2.new(0,648,0,12)
addTitleLbl.Font = Enum.Font.Gotham; addTitleLbl.TextSize = 11; addTitleLbl.TextColor3 = Color3.fromRGB(175,205,250)
local addScroll = colScroll(0, 192, 40, 648)

local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0,648,0,28); statusLbl.Position = UDim2.new(0,0,0,264); statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 12; statusLbl.TextColor3 = Color3.new(1,1,1); statusLbl.TextWrapped = true
statusLbl.TextXAlignment = Enum.TextXAlignment.Center; statusLbl.TextYAlignment = Enum.TextYAlignment.Top; statusLbl.Text = ""; statusLbl.Parent = windowView
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = statusLbl end
-- The rule, stated once and always on screen. Neither side can finish alone, and saying so up front is what
-- stops "I pressed ready and nothing happened" from reading as a broken button.
do
	local rule = Instance.new("TextLabel"); rule.Size = UDim2.new(0,648,0,14); rule.Position = UDim2.new(0,0,0,332)
	rule.BackgroundTransparency = 1; rule.Font = Enum.Font.Gotham; rule.TextSize = 11
	rule.TextColor3 = Color3.fromRGB(175,205,250); rule.TextXAlignment = Enum.TextXAlignment.Center
	rule.Text = "Both players must be ready to trade."; rule.Parent = windowView
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = rule end
end
-- CRATE TOKENS half of the deal. Food Coins are deliberately absent -- gameplay currency is not tradeable, so
-- there is nothing here to type a coin amount into. Type a number and press OFFER; any change clears both
-- readies exactly like adding a pet does.
-- Built inside do...end on purpose: PetFollow sits at Luau's 200-locals-per-scope ceiling, so these widgets
-- must not hold module-scope registers. renderTradeWindow re-finds them by NAME instead (see tokenWidgets).
do
	local row = Instance.new("Frame"); row.Name = "TokenRow"
	row.Size = UDim2.new(0,648,0,26); row.Position = UDim2.new(0,0,0,236)
	row.BackgroundColor3 = Color3.fromRGB(12,44,104); row.Parent = windowView; uicorner(row,8)
	local lead = Instance.new("TextLabel"); lead.Name = "Lead"
	lead.Size = UDim2.new(0,86,1,0); lead.Position = UDim2.new(0,8,0,0)
	lead.BackgroundTransparency = 1; lead.Font = Enum.Font.GothamBold; lead.TextSize = 12
	lead.TextColor3 = Color3.fromRGB(255,215,0); lead.TextXAlignment = Enum.TextXAlignment.Left
	lead.Text = "Tokens:"; lead.Parent = row
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = lead; lead.TextScaled = true end
	local box = Instance.new("TextBox"); box.Name = "Box"
	box.Size = UDim2.new(0,92,0,22); box.Position = UDim2.new(0,96,0,4)
	box.BackgroundColor3 = Color3.fromRGB(24,80,170); box.Font = Enum.Font.GothamBold; box.TextSize = 13
	box.TextColor3 = Color3.new(1,1,1); box.Text = "0"; box.ClearTextOnFocus = false
	box.PlaceholderText = "0"; box.Parent = row; uicorner(box,6)
	local set = Instance.new("TextButton"); set.Name = "Set"
	set.Size = UDim2.new(0,66,0,22); set.Position = UDim2.new(0,194,0,4)
	set.BackgroundColor3 = Color3.fromRGB(50,200,50); set.Font = Enum.Font.GothamBold; set.TextSize = 12
	set.TextColor3 = Color3.new(1,1,1); set.Text = "OFFER"; set.Parent = row; uicorner(set,6)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = set; set.TextScaled = true end
	-- The remote is resolved per click rather than held in a module local, same reason as above.
	local function send()
		local n = math.floor(tonumber(box.Text) or 0)
		if n < 0 then n = 0 end
		box.Text = tostring(n)
		local ev = RS:FindFirstChild("PetTradeTokensEvent")
		if ev then pcall(function() ev:FireServer(n) end) end
	end
	set.MouseButton1Click:Connect(send)
	box.FocusLost:Connect(function(enter) if enter then send() end end)
end

-- READY is CENTRED (224 + 200 = the middle 200px of 648) and is the biggest control on the page. CANCEL sits
-- beside it, smaller and red -- present, but never competing with the action the player came here to take.
local cancelBtn = Instance.new("TextButton"); cancelBtn.Size = UDim2.new(0,110,0,30); cancelBtn.Position = UDim2.new(0,96,0,298); cancelBtn.BackgroundColor3 = Color3.fromRGB(220,60,60)
cancelBtn.Font = Enum.Font.GothamBold; cancelBtn.TextSize = 15; cancelBtn.TextColor3 = Color3.new(1,1,1); cancelBtn.Text = "CANCEL"; cancelBtn.Parent = windowView; uicorner(cancelBtn,8); uistroke(cancelBtn, Color3.new(0,0,0),2)
local confirmBtn = Instance.new("TextButton"); confirmBtn.Size = UDim2.new(0,200,0,34); confirmBtn.Position = UDim2.new(0,224,0,296); confirmBtn.BackgroundColor3 = Color3.fromRGB(50,200,50)
confirmBtn.Font = Enum.Font.GothamBold; confirmBtn.TextSize = 15; confirmBtn.TextColor3 = Color3.new(1,1,1); confirmBtn.Text = "CONFIRM"; confirmBtn.Parent = windowView; uicorner(confirmBtn,8); uistroke(confirmBtn, Color3.new(0,0,0),2)

local function clearScroll(s) for _, c in ipairs(s:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end
local function refreshPicker()
	clearScroll(pickerScroll)
	local order, n = 0, 0
	for _, pl in ipairs(PlayersSvc:GetPlayers()) do
		if pl ~= player then
			n = n + 1; order = order + 1
			local row = Instance.new("Frame"); row.Size = UDim2.new(1,-6,0,30); row.LayoutOrder = order; row.BackgroundColor3 = Color3.fromRGB(20,70,160); row.Parent = pickerScroll; uicorner(row,6)
			local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-94,1,0); nm.Position = UDim2.new(0,8,0,0); nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextColor3 = Color3.new(1,1,1); nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = pl.DisplayName .. " (@" .. pl.Name .. ")"; nm.Parent = row
			local req = Instance.new("TextButton"); req.Size = UDim2.new(0,82,0,24); req.Position = UDim2.new(1,-86,0,3); req.BackgroundColor3 = Color3.fromRGB(50,200,50); req.Font = Enum.Font.GothamBold; req.TextSize = 12; req.TextColor3 = Color3.new(1,1,1); req.Text = "REQUEST"; req.Parent = row; uicorner(req,6)
			local uid = pl.UserId
			req.MouseButton1Click:Connect(function() pcall(function() PetTradeRequest:FireServer(uid) end); ovTitle.Text = "Request sent to " .. pl.DisplayName .. "..." end)
		end
	end
	if n == 0 then
		local e = Instance.new("TextLabel"); e.Size = UDim2.new(1,-6,0,40); e.BackgroundTransparency = 1; e.Font = Enum.Font.Gotham; e.TextSize = 13; e.TextColor3 = Color3.fromRGB(200,220,255); e.TextWrapped = true; e.Text = "No other players in the server to trade with."; e.Parent = pickerScroll
	end
	pickerScroll.CanvasSize = UDim2.new(0,0,0, n*36 + 8)
end
local function showPicker() pickerView.Visible = true; windowView.Visible = false; ovTitle.Text = "Trade \xE2\x80\x94 pick a player"; refreshPicker() end
local function renderTradeWindow(state)
	pickerView.Visible = false; windowView.Visible = true; ovTitle.Text = "Trading with " .. tostring(state.withName)
	-- FROZEN once both sides are ready: the add/remove callbacks are dropped entirely so the buttons are
	-- inert, matching the server, which refuses offer changes outside the offer stage.
	local frozen = (state.locked == true)
	clearScroll(yourOfferScroll); for i, b in ipairs(state.mine or {}) do makeOfferCard(yourOfferScroll, b, i, (not frozen) and function() pcall(function() PetTradeOffer:FireServer(b.key or b.petId, false) end) end or nil) end -- remove BY storage key
	yourOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.mine or {}) * 80 + 4)
	clearScroll(theirOfferScroll); for i, b in ipairs(state.theirs or {}) do makeOfferCard(theirOfferScroll, b, i, nil) end
	theirOfferScroll.CanvasSize = UDim2.new(0,0,0, #(state.theirs or {}) * 80 + 4)
	local offered = {}; for _, b in ipairs(state.mine or {}) do offered[b.key or b.petId] = true end -- dedup the picker BY storage key
	clearScroll(addScroll); local idx = 0
	for skey, p in pairs(latestInv.owned or {}) do -- `owned` is keyed by storage key; each variant offers independently
		if not offered[skey] then idx = idx + 1
			local rowName = ((p.rare and p.rareName) or p.displayName) .. (((p.count or 1) > 1) and ("  x" .. p.count) or "") -- show the stack size so duplicates are obvious
			makeOfferRow(addScroll, { petId = p.petId, name = rowName, level = p.level, rare = p.rare }, idx, (not frozen) and function() pcall(function() PetTradeOffer:FireServer(skey, true) end) end or nil)
		end
	end
	-- SKINS go in the same list, under the pets. The keys come back already prefixed with "SKIN:", which is
	-- exactly what PetTradeOfferEvent expects, so they need no special handling on the way out.
	if _G.skinTradeList then
		local okSkins, skins = pcall(_G.skinTradeList)
		if okSkins and type(skins) == "table" then
			for _, sk in ipairs(skins) do
				if not offered[sk.key] then
					idx = idx + 1
					local key = sk.key
					-- Built inline rather than via a helper: a module-scope `local function` would cost a register
					-- this file doesn't have (200-per-scope ceiling). A skin has no level or pet tier, so it's
					-- coloured by RARITY and labelled with its duplicate count instead of reusing makeOfferRow.
					local canAdd = not frozen
					local srow = Instance.new(canAdd and "TextButton" or "TextLabel")
					srow.Size = UDim2.new(1,-6,0,26); srow.LayoutOrder = idx
					srow.BackgroundColor3 = Color3.fromRGB(20,70,160); srow.Text = ""; srow.Parent = addScroll; uicorner(srow, 6)
					if canAdd then srow.AutoButtonColor = true end
					local stripe = Instance.new("Frame"); stripe.Size = UDim2.new(0,5,1,-8); stripe.Position = UDim2.new(0,4,0,4)
					stripe.BorderSizePixel = 0; stripe.BackgroundColor3 = sk.color or Color3.fromRGB(200,200,200)
					stripe.Parent = srow; uicorner(stripe, 3)
					local snm = Instance.new("TextLabel"); snm.Size = UDim2.new(1,-18,1,0); snm.Position = UDim2.new(0,14,0,0)
					snm.BackgroundTransparency = 1; snm.Font = Enum.Font.GothamBold; snm.TextSize = 12
					snm.TextXAlignment = Enum.TextXAlignment.Left; snm.TextColor3 = sk.color or Color3.new(1,1,1)
					snm.Text = sk.name .. "  (" .. tostring(sk.tier) .. (((sk.count or 1) > 1) and ("  x" .. sk.count) or "") .. ")"
					snm.Parent = srow
					if canAdd then srow.MouseButton1Click:Connect(function() pcall(function() PetTradeOffer:FireServer(key, true) end) end) end
				end
			end
		end
	end
	addScroll.CanvasSize = UDim2.new(0,0,0, idx * 30 + 4)
	-- TOKEN half of the deal. The box is only rewritten when it does NOT have focus, so a number being
	-- typed is never yanked out from under the player by an incoming state push.
	local myTok, theirTok = state.myTokens or 0, state.theirTokens or 0
	-- Found by name, not held in module locals (200-register ceiling -- see the do...end that builds them).
	local tokRow = windowView:FindFirstChild("TokenRow")
	if tokRow then
		local box, set, lead = tokRow:FindFirstChild("Box"), tokRow:FindFirstChild("Set"), tokRow:FindFirstChild("Lead")
		if box then
			if not box:IsFocused() then box.Text = tostring(myTok) end
			box.TextEditable = not frozen
		end
		if set then set.BackgroundColor3 = frozen and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50) end
		if lead then lead.Text = "Tokens:  (you have " .. tostring(state.myTokenBalance or 0) .. ")" end
	end

	-- STATUS + the one button whose meaning changes with the stage. Three stages, three labels:
	--   offer     -> READY (press when your side is done)
	--   countdown -> locked, showing the seconds left; nothing to press
	--   final     -> CONFIRM TRADE, the second press on an offer that has been frozen the whole time
	local stage = state.stage or "offer"
	local st = state.status
	local tokenLine = ""
	if myTok > 0 or theirTok > 0 then
		tokenLine = "\nYou: " .. myTok .. " tokens   |   Them: " .. theirTok .. " tokens"
	end

	if stage == "countdown" then
		statusLbl.Text = "\xE2\x8F\xB3 Offers LOCKED. Check them carefully!\nFinal confirmation in "
			.. tostring(state.countdown or 0) .. "s" .. tokenLine
		statusLbl.TextColor3 = Color3.fromRGB(255,205,90)
		confirmBtn.Text = "LOCKED  " .. tostring(state.countdown or 0) .. "s"
		confirmBtn.BackgroundColor3 = Color3.fromRGB(120,120,120)
	elseif stage == "final" then
		if state.myFinal then
			statusLbl.Text = "You confirmed.\nWaiting for " .. tostring(state.withName) .. " to confirm..." .. tokenLine
		else
			statusLbl.Text = "\xE2\x9A\xA0 LAST CHANCE - this is exactly what you get.\nPress CONFIRM TRADE to finish." .. tokenLine
		end
		statusLbl.TextColor3 = state.myFinal and Color3.new(1,1,1) or Color3.fromRGB(255,235,120)
		confirmBtn.Text = state.myFinal and "\xE2\x9C\x94 CONFIRMED" or "CONFIRM TRADE"
		confirmBtn.BackgroundColor3 = state.myFinal and Color3.fromRGB(120,120,120) or Color3.fromRGB(255,170,40)
	else
		statusLbl.Text = ((st=="waiting_them" and ("You are ready.\nWaiting for " .. tostring(state.withName) .. "..."))
			or (st=="waiting_you" and (tostring(state.withName) .. " is ready.\nYour move!"))
			or "Add pets, skins or tokens, then both press READY.\n(any change resets both)") .. tokenLine
		statusLbl.TextColor3 = Color3.new(1,1,1)
		confirmBtn.Text = state.myConfirm and "\xE2\x9C\x94 READY" or "READY"
		confirmBtn.BackgroundColor3 = state.myConfirm and Color3.fromRGB(120,120,120) or Color3.fromRGB(50,200,50)
	end
end
ovBack.MouseButton1Click:Connect(function() tradeOverlay.Visible = false end) -- back to pet cards (trade stays live; reopen via TRADE)
cancelBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeCancel:FireServer() end) end)
confirmBtn.MouseButton1Click:Connect(function() pcall(function() PetTradeConfirm:FireServer() end) end)
tradeBtn.MouseButton1Click:Connect(function()
	questsOverlay.Visible = false -- TRADE + QUESTS + DETAIL overlays are mutually exclusive over the pet grid
	_G.PetHub.hideDetail()
	if tradeState and tradeState.active then tradeOverlay.Visible = true; renderTradeWindow(tradeState)
	else tradeOverlay.Visible = not tradeOverlay.Visible; if tradeOverlay.Visible then showPicker() end end
end)
-- ===== PUBLISH THE TRADE HANDLES =====
-- Everything above is LOCAL to buildTradeUI. The trade tab, the QUESTS and REWARDS chips, and the
-- live-trade remote all live BELOW this function and referenced `tradeOverlay` / `showPicker` /
-- `renderTradeWindow` directly -- which, out here, are not those locals at all: they are undeclared
-- globals, i.e. nil. That is the "attempt to index nil with 'Visible'" the trade tab threw on every
-- click, and why nothing happened when you pressed it.
--
-- They go on _G.PetHub rather than becoming module-scope locals ON PURPOSE: this file sits right up
-- against Luau's 200-locals-per-scope ceiling, and three more top-level locals is exactly the kind of
-- change that turns a working file into one that will not compile.
	_G.PetHub.trade = {
		overlay = tradeOverlay,
		title   = ovTitle,
		picker  = showPicker,
		render  = renderTradeWindow,
	}
end -- closes buildTradeUI
buildTradeUI() -- build it right here, exactly where it used to run inline

-- ===== HUB ROUTER: one page at a time =====
-- Defined HERE, not up beside the nav bar, because it drives the real trade + quest overlays and they do not
-- exist yet at that point in the file. The nav buttons look showPage up at CLICK time, so the order is fine.
--
-- Every page is mutually exclusive: the old header chips TOGGLED, which let you end up with the pet grid
-- showing while the nav claimed you were on Quests. A router that SETS state instead of flipping it cannot
-- drift out of step with the highlighted tab.
_G.PetHub.activePage = "pets"

_G.PetHub.syncNav = function()
	local cur = _G.PetHub.activePage or "pets"
	for id, b in pairs(_G.PetHub.navButtons or {}) do
		local on = (id == cur)
		-- selected = dark-on-gold, unselected = gold-on-blue. Same two states the crate panel uses.
		b.BackgroundColor3 = on and Color3.fromRGB(255,215,0) or Color3.fromRGB(18,66,150)
		b.TextColor3 = on and Color3.fromRGB(92,58,8) or Color3.fromRGB(255,215,0)
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = on and Color3.fromRGB(180,122,20) or Color3.new(1,1,1)
			st.Thickness = on and 2.5 or 1.5
		end
	end
end

_G.PetHub.showPage = function(id)
	id = id or "pets"
	-- CRATES and TOKENS are pages of the crate panel. Hand off rather than rebuild: that panel already owns
	-- the roll, the reveal and the token purchase, and a second copy of any of those is a second thing that
	-- can disagree with the server. It carries the same header and the same nav bar, so the swap is seamless.
	if id == "crates" or id == "tokens" then
		openPanel(false)
		if _G.toggleSkinCrates then _G.toggleSkinCrates(true, id) end
		return
	end
	local mo = panel:FindFirstChild("MilestonesOverlay"); if mo then mo:Destroy() end
	_G.PetHub.hideDetail()
	questsOverlay.Visible = (id == "quests")
	local tr = _G.PetHub.trade
	if tr and tr.overlay then tr.overlay.Visible = (id == "trade") end
	if id == "trade" and tr then
		-- a live session shows the trade window; otherwise the picker, exactly as the old TRADE chip did
		if tradeState and tradeState.active then
			if tr.render then tr.render(tradeState) end
		elseif tr.picker then tr.picker() end
	end
	_G.PetHub.activePage = id
	_G.PetHub.syncNav()
end


-- Re-render the open detail card when the SERVER confirms a skin change. Equipping is a round trip -- the
-- client asks, the server validates ownership and unlock, then pushes the new state -- so the list can only
-- honestly say what you are wearing AFTER that push lands. Optimistically flipping the label on click would
-- show 'ON' against a skin the server may have refused.
_G.petHubSkinsChanged = function()
	local d = panel:FindFirstChild("PetDetailOverlay")
	if not d or not _G.PetHub._lastP then return end
	pcall(function() _G.PetHub.showDetail(_G.PetHub._lastKey, _G.PetHub._lastP) end)
end

-- QUESTS tab in the header -> opens the tucked-away discovered-quests overlay (the quest info lives here now,
-- off the main pet grid). Mutually exclusive with the TRADE overlay.
local questsBtn = Instance.new("TextButton"); questsBtn.Size = UDim2.new(0,82,0,26); questsBtn.Position = UDim2.new(1,-226,0,17)
questsBtn.BackgroundColor3 = Color3.fromRGB(120,170,60); questsBtn.Font = Enum.Font.GothamBold; questsBtn.TextSize = 14; questsBtn.TextColor3 = Color3.new(1,1,1)
questsBtn.Text = "\xF0\x9F\x97\xBA QUESTS"; questsBtn.Parent = header; uicorner(questsBtn, 8); uistroke(questsBtn, Color3.new(0,0,0), 2)
questsBtn.Visible = false -- replaced by the HubNav bar under the header; handler kept so nothing rewires
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = questsBtn; questsBtn.TextScaled = true end -- shrink-to-fit on the 82px chip
questsBtn.MouseButton1Click:Connect(function()
	if _G.PetHub.trade and _G.PetHub.trade.overlay then _G.PetHub.trade.overlay.Visible = false end
	_G.PetHub.hideDetail()
	local mo = panel:FindFirstChild("MilestonesOverlay"); if mo then mo:Destroy() end
	questsOverlay.Visible = not questsOverlay.Visible
end)

-- REWARDS tab -> the collection-milestones overlay. Wrapped in a do-block so the button needs no module-scope
-- local (this file is close to Luau's 200-locals-per-scope ceiling).
do
	local rewardsBtn = Instance.new("TextButton"); rewardsBtn.Size = UDim2.new(0,82,0,26); rewardsBtn.Position = UDim2.new(1,-314,0,17)
	rewardsBtn.BackgroundColor3 = Color3.fromRGB(210,160,40); rewardsBtn.Font = Enum.Font.GothamBold
	rewardsBtn.TextSize = 11; rewardsBtn.TextColor3 = Color3.new(1,1,1); rewardsBtn.Text = "\xF0\x9F\x8F\x86 REWARDS"
	rewardsBtn.Parent = header; uicorner(rewardsBtn, 8); uistroke(rewardsBtn, Color3.new(0,0,0), 2)
	rewardsBtn.Visible = false -- replaced by the HubNav bar under the header; handler kept so nothing rewires
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = rewardsBtn; rewardsBtn.TextScaled = true end -- shrink-to-fit on the 82px chip
	rewardsBtn.MouseButton1Click:Connect(function()
		if _G.PetHub.trade and _G.PetHub.trade.overlay then _G.PetHub.trade.overlay.Visible = false end
		questsOverlay.Visible = false; _G.PetHub.hideDetail()
		local open = panel:FindFirstChild("MilestonesOverlay")
		if open then open:Destroy() else _G.PetHub.showMilestones() end -- toggle
	end)
end

-- SKIN CRATES button in the Pet Hub header -> opens the crate shop + skin inventory (SkinCrateClient.client
-- owns the panel via _G.toggleSkinCrates). It now sits in the WHEEL's old slot (-402): the wheel is gone and
-- pet levels come from the Pet Level Crate inside this very panel, so this is where a player who used to
-- reach for WHEEL should land. Leaving it at -490 would have left a visible 88px hole in the header row.
-- Slots run right-to-left, 88px apart: -138 TRADE / -226 QUESTS / -314 REWARDS / -402 CRATES.
-- Skins and levels both belong to pets, so the Pet Hub is where players look -- the MORE+ row stays as a
-- second way in, but it sits below the fold in that popup, which is exactly why this button exists.
-- Same do-block wrapper as its neighbours: this file is close to Luau's 200-locals-per-scope ceiling, and one
-- local over makes the WHOLE script fail to compile silently, taking every handler in it down.
do
	local cratesBtn = Instance.new("TextButton"); cratesBtn.Size = UDim2.new(0,82,0,26); cratesBtn.Position = UDim2.new(1,-402,0,17)
	cratesBtn.BackgroundColor3 = Color3.fromRGB(150,96,240); cratesBtn.Font = Enum.Font.GothamBold
	cratesBtn.TextSize = 11; cratesBtn.TextColor3 = Color3.new(1,1,1); cratesBtn.Text = "\xF0\x9F\x8E\x81 CRATES"
	cratesBtn.Parent = header; uicorner(cratesBtn, 8); uistroke(cratesBtn, Color3.new(0,0,0), 2)
	cratesBtn.Visible = false -- replaced by the HubNav bar under the header; handler kept so nothing rewires
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = cratesBtn; cratesBtn.TextScaled = true end -- shrink-to-fit on the 82px chip
	cratesBtn.MouseButton1Click:Connect(function()
		openPanel(false) -- close the pet hub first: both panels are DisplayOrder 100, so they'd overlap
		-- `true` = opened from the hub, which makes the crate panel show its BACK button (it fires PetInvToggle
		-- to bring the hub back). Opened any other way there'd be nothing to return to, so BACK stays hidden.
		if _G.toggleSkinCrates then _G.toggleSkinCrates(true) end
	end)
end
qoBack.MouseButton1Click:Connect(function() questsOverlay.Visible = false end)

-- live trade state from the server
if PetTradeState then PetTradeState.OnClientEvent:Connect(function(state)
	tradeState = state
	if state and state.active then
		-- ensure the Hub is open so both players see the trade window
		openPanel(true)
		local tr = _G.PetHub.trade
		if tr and tr.overlay then tr.overlay.Visible = true end
		if tr and tr.render then tr.render(state) end
	else
		local reason = state and state.reason
		print("[Trade] window closed (" .. tostring(reason) .. ")")
		tradeState = nil
		local tr = _G.PetHub.trade
		if tr and tr.overlay and tr.overlay.Visible then
			if tr.title then tr.title.Text = "Trade " .. (reason and ("\xE2\x80\x94 " .. reason) or "closed") end
			if tr.picker then tr.picker() end
		end
	end
end) end

-- incoming-request popup (shows even if the Hub is closed)
local reqPopup = Instance.new("Frame"); reqPopup.Name = "TradeRequestPopup"; reqPopup.AnchorPoint = Vector2.new(0.5,0.5); reqPopup.Position = UDim2.new(0.5,0,0.4,0); reqPopup.Size = UDim2.new(0,320,0,130)
reqPopup.BackgroundColor3 = Color3.fromRGB(25,90,185); reqPopup.Visible = false; reqPopup.ZIndex = 50; reqPopup.Parent = invGui; uicorner(reqPopup, 12); uistroke(reqPopup, Color3.fromRGB(255,215,0), 3)
local reqLbl = Instance.new("TextLabel"); reqLbl.Size = UDim2.new(1,-20,0,60); reqLbl.Position = UDim2.new(0,10,0,10); reqLbl.BackgroundTransparency = 1; reqLbl.ZIndex = 51; reqLbl.Font = Enum.Font.GothamBold; reqLbl.TextSize = 16; reqLbl.TextColor3 = Color3.new(1,1,1); reqLbl.TextWrapped = true; reqLbl.Text = ""; reqLbl.Parent = reqPopup
local reqAccept = Instance.new("TextButton"); reqAccept.Size = UDim2.new(0,140,0,38); reqAccept.Position = UDim2.new(0,12,1,-46); reqAccept.BackgroundColor3 = Color3.fromRGB(50,200,50); reqAccept.ZIndex = 51; reqAccept.Font = Enum.Font.GothamBold; reqAccept.TextSize = 15; reqAccept.TextColor3 = Color3.new(1,1,1); reqAccept.Text = "ACCEPT"; reqAccept.Parent = reqPopup; uicorner(reqAccept,8)
local reqDecline = Instance.new("TextButton"); reqDecline.Size = UDim2.new(0,140,0,38); reqDecline.Position = UDim2.new(1,-152,1,-46); reqDecline.BackgroundColor3 = Color3.fromRGB(220,60,60); reqDecline.ZIndex = 51; reqDecline.Font = Enum.Font.GothamBold; reqDecline.TextSize = 15; reqDecline.TextColor3 = Color3.new(1,1,1); reqDecline.Text = "DECLINE"; reqDecline.Parent = reqPopup; uicorner(reqDecline,8)
reqAccept.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(true) end) end)
reqDecline.MouseButton1Click:Connect(function() reqPopup.Visible = false; pcall(function() PetTradeRespond:FireServer(false) end) end)
if PetTradePrompt then PetTradePrompt.OnClientEvent:Connect(function(fromUserId, fromName)
	reqLbl.Text = "\xF0\x9F\x94\x81 " .. tostring(fromName) .. " wants to trade pets with you!"
	reqPopup.Visible = true
	task.delay(15, function() if reqPopup.Visible then reqPopup.Visible = false end end) -- auto-dismiss if ignored
end) end

-- FLIGHT-ACHIEVEMENT progress: while a pet is EQUIPPED, report peak height (the flight system's _G.peakHeight
-- / live Y) + airtime to the server, which accrues it on that pet and gates the next level. READ-ONLY of the
-- flight stats -- never modifies flight/gas/coins. Cosmetic-only.
task.spawn(function()
	local TICK = 3
	while true do
		task.wait(TICK)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if equippedPetId and hrp then
			local peak = math.max(hrp.Position.Y, _G.peakHeight or 0)
			pcall(function() PetProgressEvent:FireServer(equippedPetId, peak, TICK) end)
		end
	end
end)
