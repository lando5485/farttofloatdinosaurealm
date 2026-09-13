-- ============================================================================================
-- PET SYSTEM (server) -- COSMETIC ONLY. First pet: BroccoliPet on Broccoli Bluff (Island 2).
-- ============================================================================================
-- Flow: player finds 3 hidden broccoli pieces -> egg appears at I2PetBlock -> claim (E) -> a
-- broccoli pet follows them forever (saved). This file owns the AUTHORITATIVE state (piece counts,
-- ownership, persistence handshake) + the world MARKERS. The per-player pieces/egg visuals AND the
-- follow pet are built CLIENT-SIDE (PetFollow.client.lua) so they can be per-player and follow
-- smoothly during fast flight. NOTHING here touches flight/gas/coins/balance -- purely cosmetic.
--
-- MODULAR: to add pet #2, add another entry to PETS below (marker names + island prefix) and reuse
-- the same remotes (the piece/egg/claim protocol is keyed by petId).
-- ============================================================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Rarity is a PERMANENT axis, separate from age/level. See src/shared/PetRarity.luau for why the two must
-- never be conflated, and for the fusion cost ladder.
local PetRarity = require(RS:WaitForChild("Shared"):WaitForChild("PetRarity"))
-- Read-only here: the Pet Crate is the single source of the rarity odds this script publishes, so the number
-- a player is shown and the number the crate rolls are the same value, not two copies that can drift.
local SkinCrates = require(RS:WaitForChild("Shared"):WaitForChild("SkinCrates"))

-- Shared ownership table (PlayerStats persists it under saved.ownedPets; we read/write it on claim).
_G.playerOwnedPets = _G.playerOwnedPets or {}

-- Per-SESSION piece progress (NOT saved -- only ownership persists; an owner skips finding entirely).
local piecesFound = {}  -- [player] = { [petId] = { [pieceIndex]=true, ... } }

-- ===== PET CATALOG (extend this to add more pets later) =====
local PETS = {
	BroccoliPet = {
		displayName  = "Broccoli Bunny",
		islandName   = "Broccoli Bluff",
		questDesc    = "Pull 3 broccoli out of the dirt on the island",
		questType    = "find",                -- pull 3 planted broccoli (hold/release minigame) -> egg -> hatch
		islandPrefix = "Island_2_",          -- the Workspace island model this pet's markers live in
		eggMarker    = "I2PetBlock",          -- where the egg appears
		pieceMarkers = { "BroccoliPiece1", "BroccoliPiece2", "BroccoliPiece3" },
		-- ===== LEVELING (cosmetic-only, ~3 tiers, extensible) =====
		maxLevel     = 3,
		-- ACHIEVEMENT thresholds to REACH each level (placeholder/easy for now -- tune next build). A tier
		-- unlocks once EITHER the equipped-pet's peak flight height OR its total time-with-pet reaches it.
		tiers = {
			[2] = { height = 1200, time = 90 },
			[3] = { height = 6000, time = 300 },
		},
	},
	-- PET #2: COCONUT CRAB on Coconut Cove (Island 5). Harder multi-stage quest: CRACK 7 coconuts (tap
	-- minigame) -> earn the Cave Key -> open the chest in the cave -> egg -> hatch. The server treats the 7
	-- coconuts as "pieces" and the chest as the "egg" marker, so the generic collect/claim/inventory/leveling
	-- logic is reused; the client builds the crack minigame + chest + key gate from these same positions.
	CoconutCrab = {
		displayName  = "Coconut Crab",
		islandName   = "Coconut Cove",
		questDesc    = "Crack 7 coconuts, then find the cave chest",
		questType    = "crack",
		islandPrefix = "Island_5_",          -- Coconut Cove
		eggMarker    = "CoconutChest",        -- the treasure chest (in the cave) = where the egg appears
		pieceMarkers = { "Coconut1","Coconut2","Coconut3","Coconut4","Coconut5","Coconut6","Coconut7" },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 2000, time = 120 },
			[3] = { height = 8000, time = 400 },
		},
	},
	-- PET #3: POPCORN SHEEP on Popcorn Pinnacle (Island 8). Movie-theater themed. questType "film-reels":
	-- find 6 FILM REELS -> load them at the PROJECTOR -> a mini-movie plays on the SCREEN -> the egg
	-- materializes in a spotlight at PopcornEggSpot -> hatch. The server treats the 6 reels as "pieces" and
	-- PopcornEggSpot as the "egg" marker, so the generic collect/claim/inventory/leveling logic is reused;
	-- the client builds the reels + projector + screen mini-movie + spotlight egg from these positions. The
	-- extra (non-collectible) PROJECTOR + SCREEN positions ride alongside in extraMarkers.
	PopcornSheep = {
		displayName  = "Popcorn Sheep",
		islandName   = "Popcorn Pinnacle",
		questDesc    = "Find 6 film reels, then start the show at the projector",
		questType    = "film-reels",
		questUnit    = "reels",               -- inventory progress label ("4/6 reels")
		islandPrefix = "Island_8_",          -- Popcorn Pinnacle
		eggMarker    = "PopcornEggSpot",      -- floor in front of the screen = where the egg appears (in a spotlight)
		pieceMarkers = { "FilmReel1","FilmReel2","FilmReel3","FilmReel4","FilmReel5","FilmReel6" },
		extraMarkers = { projector = "PopcornProjector", screen = "PopcornScreen" }, -- fixed props
		-- "use existing" extras: keep the placed instance VISIBLE + send its reference (the client renders the
		-- mini-movie ON the user's real PopcornScreen). Others (projector) are hidden + rebuilt client-side.
		extraExisting = { screen = true },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 13000, time = 150 },
			[3] = { height = 22000, time = 500 },
		},
	},
	-- PET #4: BUTTER DUCK on Butter Swamp (Island 10). "Hook & Reel" FISHING quest: grab a rod at the barrel
	-- -> fish near/over the ButterLake UNION -> cast -> bite/hook (reaction) -> reel-in tension minigame -> the
	-- SERVER rolls the catch (pity-ramped egg chance + funny junk for misses) -> the egg appears IN FRONT of the
	-- player -> hatch. NO pieces + NO egg marker (the egg spawns where caught). Markers = the fishable lake union
	-- + the rod barrel. The catch ROLL is server-authoritative (PetFishRoll RF below) with a per-player pity ramp.
	ButterDuck = {
		displayName  = "Butter Duck",
		islandName   = "Butter Swamp",
		questDesc    = "Grab a rod from the barrel, then fish in the butter swamp to catch the egg",
		questType    = "fishing",
		questUnit    = "catches",
		islandPrefix = "Island_10_",         -- Butter Swamp
		pieceMarkers = {},                    -- fishing has no collectible pieces
		-- eggMarker = nil: the caught egg appears IN FRONT of the player (not at a fixed marker)
		extraMarkers = { butterlake = "ButterLake", rodbarrel = "RodBarrel" },
		extraExisting = { butterlake = true }, -- ButterLake is the VISIBLE butter UNION -- keep it, don't hide it
		maxLevel     = 3,
		tiers = {
			[2] = { height = 19000, time = 180 },
			[3] = { height = 28000, time = 600 },
		},
	},
	-- PET #5: BURRITO ARMADILLO on Burrito Barrens (Island 13). "Dig for buried treasure" quest: grab a SHOVEL
	-- at ShovelSpot -> a HOT/COLD meter guides you to the buried egg -> DIG (hold/tap minigame) at dig spots ->
	-- DigSpot1-4 are DECOYS (junk), BuriedEggSpot is the REAL one (the armadillo egg) -> hatch. NO pieces + NO
	-- egg marker (the egg appears where dug). Markers = the shovel spot + 4 decoy dig spots + the buried egg spot.
	-- The real-dig completion is server-gated (PetDigEvent below sets digEggReady) so the claim can't be faked.
	BurritoArmadillo = {
		displayName  = "Burrito Armadillo",
		islandName   = "Burrito Barrens",
		questDesc    = "Grab a shovel and dig up the buried armadillo egg - use the hot/cold meter to find it",
		questType    = "dig",
		questUnit    = "digs",
		islandPrefix = "Island_13_",         -- Burrito Barrens
		pieceMarkers = {},                    -- dig has no collectible pieces
		-- eggMarker = nil: the unearthed egg appears at the dug spot (not auto-revealed at a marker)
		extraMarkers = { shovel = "ShovelSpot", dig1 = "DigSpot1", dig2 = "DigSpot2", dig3 = "DigSpot3", dig4 = "DigSpot4", dig5 = "DigSpot5", buriedegg = "BuriedEggSpot" },
		maxLevel     = 3,
		tiers = {
			[2] = { height = 22000, time = 200 },
			[3] = { height = 37000, time = 650 },
		},
	},
	-- ===== STARTER PET (retention): BEAN BUDDY. NO quest -- it is GRANTED FREE the first time a player ever joins
	-- (PlayerStats detects a brand-new save and calls _G.grantStarterPet below), then auto-equipped so a pet is
	-- following them within seconds of spawning. questType="starter" + no islandPrefix -> the island marker scan
	-- skips it and it never shows in the quests panel; pieceMarkers={} keeps the generic state/inventory happy.
	-- Deliberately its OWN species (not one of the 5 quest pets) so giving it away devalues no existing quest.
	BeanBuddy = {
		displayName  = "Bean Buddy", islandName = "Bean Farm", questType = "starter",
		questDesc    = "Your very first pet - a gift for showing up",
		pieceMarkers = {},
		maxLevel     = 3, tiers = { [2] = { height = 800, time = 60 }, [3] = { height = 4000, time = 240 } },
	},
	-- ===== SECRET PET (collection reward): PIZZA DRAGON. The ONLY way to get it is to collect all 10 other pets.
	-- Not questable, not buyable, not obtainable any other way -- that exclusivity IS the reward. Deliberately its
	-- own SPECIES with a silhouette nothing else in the game has (wings, horns, a spiked tail): a recolour of an
	-- existing pet would be worthless as a trophy, since every pet already turns gold and shimmers at level 25.
	-- Themed on Pizza Palms, the final island -- the capstone food for the capstone reward.
	-- questType="collection" -> excluded from the island marker scan, from the quests panel, AND (critically) from
	-- the collection COUNT itself: it is the prize for completing the set, so it can't be part of the set. See
	-- collectableCount() / collectedCount() below -- both skip it.
	PizzaDragon = {
		displayName  = "Pizza Dragon", islandName = "Collection Reward", questType = "collection",
		questDesc    = "Collect all 10 other pets",
		pieceMarkers = {},
		maxLevel     = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	-- ===== SEASONAL PETS (Community Garden rewards) -- NO island quest: they are GRANTED by the garden harvest
	-- (Summer->Sunflower Bee, Autumn->Maple Fox, Winter->Frost Penguin, Spring->Blossom Bunny). questType="seasonal"
	-- + no islandPrefix -> the island marker scan skips them; pieceMarkers={} keeps the generic state/inventory happy.
	SunflowerBee = {
		displayName = "Sunflower Bee", islandName = "Community Garden", questType = "seasonal", season = "Summer",
		questDesc = "Earned from the Summer Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	MapleFox = {
		displayName = "Maple Fox", islandName = "Community Garden", questType = "seasonal", season = "Autumn",
		questDesc = "Earned from the Autumn Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	FrostPenguin = {
		displayName = "Frost Penguin", islandName = "Community Garden", questType = "seasonal", season = "Winter",
		questDesc = "Earned from the Winter Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
	BlossomBunny = {
		displayName = "Blossom Bunny", islandName = "Community Garden", questType = "seasonal", season = "Spring",
		questDesc = "Earned from the Spring Community Garden harvest", pieceMarkers = {},
		maxLevel = 3, tiers = { [2] = { height = 1500, time = 120 }, [3] = { height = 7000, time = 400 } },
	},
}

-- FLAVOUR TEXT for each pet's "VIEW MORE" detail card in the Pet Hub. Kept in one table (rather than inline in
-- PETS) so all ten read as a set and are easy to rewrite in one pass. Purely cosmetic copy -- nothing reads it
-- except the detail card. A pet with no entry just shows no blurb; nothing breaks.
local PET_LORE = {
	BeanBuddy        = "Sprouted in the Bean Farm soil and decided to follow you home. It has never been more than a few feet from you since.",
	BroccoliPet      = "A bunny that grew up in the broccoli patch and started to look like it. Chews constantly. Nobody knows what.",
	CoconutCrab      = "Spent its whole life cracking coconuts on the beach. Its claws are stronger than most rocks, and it knows it.",
	PopcornSheep     = "Its wool pops in the heat. The theatre on Popcorn Pinnacle has never had to buy a snack machine.",
	ButterDuck       = "Floats in the butter swamp like it was made for it. Possibly was. Extremely slippery. Do not attempt to hold.",
	BurritoArmadillo = "Rolls into a perfect burrito when startled. Buries things and forgets where. Digs constantly to find them again.",
	SunflowerBee     = "Arrived the summer the garden first bloomed. Carries a little of that sunshine everywhere it goes.",
	MapleFox         = "Turned the colour of autumn leaves and stayed that way. Naps in the warm patches of the garden.",
	FrostPenguin     = "Waddled out of the winter garden and refused to leave. Its feet have never once been cold.",
	BlossomBunny     = "Woke up with the first spring blossom and wears the flowers to prove it. Hops everywhere. Walking is for others.",
}

local function getOrCreateRemote(name)
	local r = RS:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = RS end
	return r
end
local function getOrCreateRF(name)
	local r = RS:FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = RS end
	return r
end
local PetCollectEvent      = getOrCreateRemote("PetCollectEvent")      -- c->s: (petId, pieceIndex)
local PetClaimEvent        = getOrCreateRemote("PetClaimEvent")        -- c->s: (petId)
local PetRequestStateEvent = getOrCreateRemote("PetRequestStateEvent") -- c->s: () handshake
local PetGetMarkers        = getOrCreateRF("PetGetMarkers")            -- c->s RF: (petId) -> {pieces={Vector3..}, egg=Vector3}

-- SERVER-OWNED marker POSITIONS, captured once on the marker scan below. The client never searches
-- Workspace itself -- it asks for these coordinates via PetGetMarkers. [petId] = {pieces={...}, egg=...}.
local markerPositions = {}
local PetStateEvent        = getOrCreateRemote("PetStateEvent")        -- s->c: (stateTable)

-- ===== PET INVENTORY / EQUIP / LEVELING remotes (cosmetic-only) =====
local PetEquipEvent     = getOrCreateRemote("PetEquipEvent")           -- c->s: (petId|false) equip / unequip
local PetInventoryEvent = getOrCreateRemote("PetInventoryEvent")       -- s->c: (inventory table for the GUI)
local PetUpgradeEvent   = getOrCreateRemote("PetUpgradeEvent")         -- c->s: (petId) free achievement upgrade
local PetProgressEvent  = getOrCreateRemote("PetProgressEvent")        -- c->s: (petId, peakHeight, addTime)
local PetPendingUpgrade = getOrCreateRemote("PetPendingUpgradeEvent")  -- c->s: (petId) declared before a Robux prompt
local PetQuestDiscovered = getOrCreateRemote("PetQuestDiscoveredEvent") -- c->s: (petId) the player landed on this pet's island
local PetFishRoll = getOrCreateRF("PetFishRollEvent")                 -- c->s RF: () player reeled in -> SERVER rolls the catch (pity)
local PetDigEvent = getOrCreateRemote("PetDigEvent")                  -- c->s: (petId) player dug the REAL buried-egg spot -> server unlocks the claim
local PetRareEvent = getOrCreateRemote("PetRareEvent")                -- s->c: (petId, rareName) a RARE hatched -> client plays the fanfare
local PetRareAnnounce = getOrCreateRemote("PetRareAnnounceEvent")     -- s->ALL: (info) a RARE hatched -> the whole server hears about it
local IslandTaskRewardEvent = getOrCreateRemote("IslandTaskRewardEvent") -- s->c: (island, islandName, tokens, petName) island task cleared -> client plays the reward moment
local PetMilestoneEvent = getOrCreateRemote("PetMilestoneEvent")      -- s->c: (milestone) a COLLECTION milestone was reached -> celebration card
local StarterPetEvent = getOrCreateRemote("StarterPetEvent")          -- s->c: (petId, displayName) the free first-join pet was granted -> client plays the welcome card
local PetEquipBroadcast = getOrCreateRemote("PetEquipBroadcast")      -- s->c (ALL): a player's equipped-pet info {userId,petId,level,isRare,variant} -> RemotePets renders OTHER players' followers
-- ===== STAGE 3 TRADE remotes (client sends INTENTS only; the server owns + validates everything) =====
local PetFuseEvent    = getOrCreateRemote("PetFuseEvent")             -- c->s: (storageKey) fuse N duplicates -> 1 of the next rarity
local PetFuseResult   = getOrCreateRemote("PetFuseResultEvent")       -- s->c: (ok, info) fusion outcome -> client plays the reveal / shows the reason

local PetTradeRequest = getOrCreateRemote("PetTradeRequestEvent")     -- c->s: (targetUserId) ask to trade
local PetTradeRespond = getOrCreateRemote("PetTradeRespondEvent")     -- c->s: (accept:bool) answer a request
local PetTradeOffer   = getOrCreateRemote("PetTradeOfferEvent")       -- c->s: (petId, add:bool) add/remove a pet from your offer
local PetTradeConfirm = getOrCreateRemote("PetTradeConfirmEvent")     -- c->s: () lock in your current offer / final-confirm
local PetTradeTokens  = getOrCreateRemote("PetTradeTokensEvent")      -- c->s: (amount) set how many Crate Tokens you're offering
local PetTradeCancel  = getOrCreateRemote("PetTradeCancelEvent")      -- c->s: () cancel the trade
local PetTradeState   = getOrCreateRemote("PetTradeStateEvent")       -- s->c: (perspective state) live trade window
local PetTradePrompt  = getOrCreateRemote("PetTradeRequestPromptEvent") -- s->c: (fromUserId, fromName) incoming request popup
local fishCatches  = {}  -- [player] = number of successful reel-ins (drives the pity ramp; session-only, not saved)
local fishEggReady = {}  -- [player] = true once the SERVER has rolled the EGG (gates the ButterDuck claim, anti-cheat)
local digEggReady  = {}  -- [player] = true once the player DUG the real buried egg (gates the BurritoArmadillo claim, anti-cheat)
-- (The BurritoArmadillo "Armadillo Trail" uses CLIENT-BUILT low-poly part mounds dug one-at-a-time -- no server
-- terrain. The only server piece is the claim gate above + PetDigEvent below.)
_G.playerDiscoveredQuests = _G.playerDiscoveredQuests or {}           -- [player] = { [petId]=true } (persisted by PlayerStats)
_G.playerEverCompletedQuests = _G.playerEverCompletedQuests or {}     -- [player] = { [petId]=true } PERMANENT "ever completed quest X" (persisted) -- gates the first-time-only rare roll, separate from ownership
_G.playerEquippedPet = _G.playerEquippedPet or {}                      -- [player] = petId (persisted by PlayerStats)
-- COLLECTION MILESTONES: which reward tiers this player has already been paid out for. Keys are STRINGS
-- (tostring(need)) because DataStore JSON-encodes tables and a mixed/numeric-keyed table does not round-trip
-- reliably -- string keys always do. Persisted by PlayerStats as saved.petMilestones.
_G.playerPetMilestones = _G.playerPetMilestones or {}                  -- [player] = { ["3"]=true, ["5"]=true, ... }
_G.playerTitle = _G.playerTitle or {}                                  -- [player] = "Beastmaster" (persisted; mirrored to the "Title" attribute)
local pendingRobuxPet = {}                                             -- [userId] = petId awaiting a Robux receipt
local upgradeReady    = {}                                            -- [player][petId] = last canUpgrade (to avoid resend spam)
-- \xE2\x9A\xA0 REPLACE BEFORE LAUNCH: placeholder pet-skip Developer Product ID. The Robux "Skip" fills the current
-- level's remaining XP (one level up), gated behind ProcessReceipt. This is a PLACEHOLDER id -- create the real
-- Developer Product(s) and set the id here (and the matching id in PetFollow.client.lua). Until replaced, real
-- purchases won't grant (the prompt errors harmlessly); test accounts use the instant test-skip path instead.
-- (Price scales with level in the UI label; at launch, map level brackets to per-bracket product IDs here.)
local PET_UPGRADE_PRODUCT_ID = 123456789 -- \xE2\x9A\xA0 (legacy, no longer used -- superseded by the TIER-SKIP products below)

-- \xE2\x9A\xA0 REPLACE BEFORE LAUNCH: placeholder TIER-SKIP Developer Product IDs (4 prices). Each jumps the pet to
-- the FIRST level of the NEXT age stage. Stages: Baby 1-5, Kid 6-10, Teen 11-15, Adult 16-20, Elder 21-25.
-- SERVER-AUTHORITATIVE: a receipt only applies if the pet is actually in that product's SOURCE tier (srcMin..
-- srcMax) -- so a cheap product can NEVER be used to jump a higher tier. The matching ids live in
-- PetFollow.client.lua (PET_SKIP_PRODUCTS). REPLACE ALL FOUR with the real Developer Product IDs before launch.
local PET_SKIP_PRODUCTS = {
	[123456701] = { target = 6,  srcMin = 1,  srcMax = 5,  price = 49,  to = "Kid"   }, -- Baby -> Kid
	[123456702] = { target = 11, srcMin = 6,  srcMax = 10, price = 99,  to = "Teen"  }, -- Kid  -> Teen
	[123456703] = { target = 16, srcMin = 11, srcMax = 15, price = 299, to = "Adult" }, -- Teen -> Adult
	[123456704] = { target = 21, srcMin = 16, srcMax = 20, price = 599, to = "Elder" }, -- Adult-> Elder
}

-- ============================================================================================
-- PET MODEL TEMPLATES (all 5 pets). CSG/UnionAsync is SERVER-ONLY, so each pet's BODY+HEAD (+ears/neck/
-- shell ridges that share its colour) is FUSED into ONE smooth gap-free solid HERE at startup, stored in
-- ReplicatedStorage, and the client CLONES it for the follow loop. Heavy overlap -> seamless fusion (no
-- "balls with gaps"). Separate parts (eyes + differently-coloured limbs/bills) keep their own colours and
-- are role-named so the client animator drives them: Eye/Highlight blink, Leg gait, Tail wiggle, everything
-- else rides the fused body. Cosmetic only (Anchored, Massless, CanCollide=false). Local frame: +X = front.
-- ============================================================================================
local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth
local function flagPart(p)
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.Plastic -- matte plastic toy look (no gloss)
	-- Force EVERY face Smooth: new Parts default TopSurface=Studs / BottomSurface=Inlet, which render the
	-- Lego-stud/notch texture (very visible on cylinders). Smooth on all 6 faces -> clean matte plastic, no notches.
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	return p
end
-- make a part (sizes/positions are ALREADY scaled by the caller's P closure)
local function mkPart(model, name, shape, sx, sy, sz, color, x, y, z, rot)
	local p = Instance.new("Part"); p.Name = name; p.Shape = shape; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	local cf = CFrame.new(x, y, z); if rot then cf = cf * rot end
	p.CFrame = cf; flagPart(p); p.Parent = model; return p
end
-- FUSE a list of overlapping source parts into ONE union named `name`, coloured `color`. Returns union, err.
-- On CSG failure it keeps the (unfused) parts renamed so the client still treats them as the body (pet still appears).
local function fuse(model, src, name, color)
	local first = table.remove(src, 1)
	local ok, u = pcall(function() return first:UnionAsync(src) end)
	if ok and typeof(u) == "Instance" then
		first:Destroy(); for _, p in ipairs(src) do p:Destroy() end
		flagPart(u); u.Name = name; u.UsePartColor = true; u.Color = color
		pcall(function() u.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() u.SmoothingAngle = 60 end) -- soft satin shading across the fused solid
		u.Parent = model
		return u, nil
	else
		table.insert(src, 1, first)
		for _, p in ipairs(src) do p.Name = name.."Chunk" end -- unfused fallback -> client role = body
		return nil, tostring(u)
	end
end
local function newRoot(model)
	local r = mkPart(model, "Root", BAL, 0.4, 0.4, 0.4, Color3.new(1,1,1), 0, 0, 0); r.Transparency = 1; model.PrimaryPart = r; return r
end
-- WELD a cosmetic part firmly to a target (the fused head/body). Returns the part for chaining. In this system
-- every part is also anchored + code-positioned relative to the root each frame (that is what actually keeps
-- parts glued with no gap), so the weld is a belt-and-suspenders bind that also documents the parent.
local function weldTo(part, target)
	if part and target then
		local w = Instance.new("WeldConstraint"); w.Name = "Attach"; w.Part0 = target; w.Part1 = part; w.Parent = part
	end
	return part
end
-- THE STANDARD EYES (the armadillo's EXACT construction -- reused on EVERY pet so they all have the same good
-- eyes). Each eye is a big FLAT black disc (a thin cylinder -> flat, never a bulging sphere) whose BACK embeds
-- into the face surface and whose FRONT sits just proud (no gap, no float), plus a small FLAT white sparkle disc
-- on the upper-front. A cylinder's circular faces point along its LOCAL X, so an un-rotated thin cylinder IS a
-- disc facing +X (the front). `fx` = eye CENTRE -- set it per pet so the disc backs into THAT pet's face surface
-- (centre ~ surface_x, so back ~0.11 in / front ~0.11 proud). `fy` height, `fz` lateral spread. Named
-- Eye/Highlight so the client blink squashes them together.
local EYE_DIA = 0.82  -- ONE standard eye size for the whole game (the armadillo's eye)
local function eyes(P, fx, fy, fz)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = fz * sgn
		P("Eye", CYL, 0.22, EYE_DIA, EYE_DIA, Color3.fromRGB(16,16,20), fx, fy, zc)                        -- big flat matte-black disc (back embedded, front proud)
		P("Highlight", CYL, 0.12, EYE_DIA*0.34, EYE_DIA*0.34, Color3.fromRGB(255,255,255), fx + 0.16, fy + EYE_DIA*0.22, zc + EYE_DIA*0.16) -- flat white sparkle on the eye
	end
end
-- a CLEAN single-shape mouth: ONE thin rounded bar laid horizontally across the +X face (a cylinder rotated so
-- its length runs along Z). `fx,fy` = where it sits on the face, `w` = mouth width. (Ducks DON'T call this -- the
-- bill IS the mouth.)
local function mouth(P, fx, fy, w)
	P("Mouth", CYL, w, 0.18, 0.18, Color3.fromRGB(48,32,30), fx, fy, 0, CFrame.Angles(0, math.rad(90), 0))
end

-- ROUNDED-CUBE BODY (Pet-Sim-99 chunky style): appends a fillet/Minkowski box -- 3 cross slabs (the flat
-- faces) + 8 corner spheres + 12 edge cylinders -- to `src`, centred at (cx,cy,cz), dims W(width Z) x
-- H(height Y) x D(depth X) with fillet radius R. Server-unioning `src` then yields ONE cube with smooth
-- curved edges (gap-free). P is the builder's scaling closure. +X = front.
local function roundedCubeInto(src, P, cx, cy, cz, W, H, D, R, color)
	local iW, iH, iD = W - 2*R, H - 2*R, D - 2*R
	local hW, hH, hD = iW/2, iH/2, iD/2
	local dd = 2*R
	local function a(sh, sx,sy,sz, x,y,z, rot) src[#src+1] = P("b", sh, sx,sy,sz, color, cx+x, cy+y, cz+z, rot) end
	a(BLK, D, iH, iW, 0,0,0)   -- 3 cross slabs = the flat faces
	a(BLK, iD, H, iW, 0,0,0)
	a(BLK, iD, iH, W, 0,0,0)
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		a(BAL, dd,dd,dd, c[1]*hD, c[2]*hH, c[3]*hW)  -- 8 corner spheres (rounds the corners)
	end
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do  -- 12 edge cylinders (rounds the edges)
		a(CYL, iD, dd, dd, 0, e[1]*hH, e[2]*hW)
		a(CYL, iH, dd, dd, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0,0,math.rad(90)))
		a(CYL, iW, dd, dd, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0,math.rad(90),0))
	end
end
-- shared chunky body dims (one big rounded cube ~1:1:0.9 -- the signature look) + display scale
local PSW, PSH, PSD, PSR, PSS = 3.8, 3.6, 3.4, 0.9, 0.85

-- 1) BROCCOLI BUNNY (island 2): rounded-cube green body (+feet/eyes unchanged). Attach tall green CYLINDER ears
-- with pink inner-ears (wide apart, tilted out, welded + deeply embedded), a flatter pink nose, a black "w"
-- mouth, 3 whiskers per side, lighter-green cheeks, a fluffy white tail, dark-green floret bumps on top.
local function buildBroccoliBunny()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BroccoliBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local GREEN, FLOR, PINK, PINKI, WHITE = Color3.fromRGB(139,195,74), Color3.fromRGB(46,139,58), Color3.fromRGB(240,170,180), Color3.fromRGB(252,205,215), Color3.fromRGB(245,245,245)
	local LGREEN, BLKM = Color3.fromRGB(176,222,116), Color3.fromRGB(20,20,24) -- lighter-green cheeks; near-black mouth/whiskers
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, GREEN)
	local body, err = fuse(m, src, "BodyUnion", GREEN)
	-- EARS: two TALL bunny ears, each = a CYLINDER capped on top with a half-sphere DOME (same colour) so the
	-- tip is ROUNDED, not flat. The cylinder + dome are UNIONED into ONE "Ear" part -- the dome is fused flush to
	-- the cylinder top (can't float) and the whole ear wiggles as one rigid unit. Green outer ear with a thinner
	-- PINK inner-ear (also cylinder + dome) on its front. Wide apart near the head corners (z=+-1.25), tilted OUT
	-- (gentle V ~13deg), bases sunk ~1 stud deep into the head AND welded to it.
	local function roundedEar(cx, cy, cz, len, dia, color, rot) -- cylinder + flush dome cap -> unioned into one "Ear"
		local up = (rot * CFrame.new(1, 0, 0)).Position -- the cylinder's length (up) axis
		local part = {
			P("b", CYL, len, dia, dia, color, cx, cy, cz, rot),                                          -- the ear shaft
			P("b", BAL, dia, dia, dia, color, cx + up.X*len*0.5, cy + up.Y*len*0.5, cz + up.Z*len*0.5),   -- dome cap on the top face (half pokes out -> rounded tip)
		}
		weldTo(fuse(m, part, "Ear", color), body) -- one rounded-top ear part (role "ear" -> wiggles as a unit), welded to the head
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.25 * sgn
		local rotEar = CFrame.Angles(math.rad(13) * sgn, 0, 0) * CFrame.Angles(0, 0, math.rad(90)) -- upright + outward V
		roundedEar(0.1,  2.4, zc, 3.1, 0.92, GREEN, rotEar)  -- green outer ear (rounded dome top) -- barely shorter (3.4 -> 3.1)
		roundedEar(0.42, 2.4, zc, 2.25, 0.5,  PINKI, rotEar) -- pink inner ear (rounded dome top), on the front -- barely shorter (2.5 -> 2.25)
	end
	-- VERIFY ear attachment: ears are welded to the fused head AND code-positioned relative to the root every frame
	-- AND their bases are embedded ~1 stud into the head -> three things ensuring no gap / no float.
	do
		local earLen, earCenterY, splay = 3.1, 2.4, math.rad(13)
		local earBottom = earCenterY - (earLen * 0.5) * math.cos(splay)  -- vertical reach of the tilted ear
		local embed     = ((PSH * 0.5) - earBottom) * s                  -- how deep the base sinks into the head
		print(string.format("[Pet] bunny ears: welded=yes, attached=%s, embedded depth=%.2f studs, cylinder size=%.2f tall x %.2f dia (wide apart, tilted out)",
			(embed > 0.1) and "yes" or "no", embed, earLen * s, 0.92 * s))
	end
	-- FEET: unchanged (kept exactly as before)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,0.78)
	P("Foot", BLK, 0.95,0.8,0.95, GREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62)                                        -- EYES: unchanged (the good standard eyes, kept exactly)
	-- NOSE: kept pink, but FLATTER (shallower in X) and CENTERED below the eyes
	weldTo(P("Nose", BAL, 0.45,0.52,0.72, PINK, 1.74,-0.05,0), body)
	-- MOUTH: a cute bunny "w" SMILE from thin black cylinders directly below the nose -- a short vertical philtrum
	-- + two strokes that flare UP & OUT (corners turned UP -> happy smile, the "w" flipped right-side up).
	weldTo(P("Mouth", CYL, 0.32,0.1,0.1, BLKM, 1.74,-0.42,0,    CFrame.Angles(0,0,math.rad(90))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,0.18,  CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-34))), body)
	weldTo(P("Mouth", CYL, 0.36,0.1,0.1, BLKM, 1.73,-0.5,-0.18, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(34))), body)
	weldTo(P("Mouth", BAL, 0.15,0.15,0.15, BLKM, 1.74,-0.585,0), body) -- tiny connector bead at the junction -> closes the gap where the philtrum + the two smile strokes meet
	-- WHISKERS: three thin black cylinders on each side of the mouth, fanned (up / level / down), poking outward
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.2,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(-12))), body)
		weldTo(P("Whisker", CYL, 1.14,0.06,0.06, BLKM, 1.46,-0.32,0.95*sgn, CFrame.Angles(0,math.rad(90),0)), body)
		weldTo(P("Whisker", CYL, 1.05,0.06,0.06, BLKM, 1.46,-0.44,0.92*sgn, CFrame.Angles(0,math.rad(90),0)*CFrame.Angles(0,0,math.rad(12))), body)
	end
	-- CHEEKS: small lighter-green spheres below the eyes -- SYMMETRIC (mirrored): both at the same height
	-- (y -0.18) and the same distance out from centre (z = +-0.72). No left/right offset -> equal positions.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Cheek", BAL, 0.6,0.52,0.5, LGREEN, 1.6,-0.18,0.72*sgn), body)
	end
	P("Tail", BAL, 1.05,1.05,1.05, WHITE, -1.6,-0.35,0)          -- round fluffy white tail bump (back)
	P("Floret", BAL, 0.62,0.54,0.62, FLOR, -0.3,1.9,0)            -- dark-green floret bump on top
	P("Floret", BAL, 0.46,0.42,0.46, FLOR, 0.2,2.0,0.45)
	return m, err
end

-- 2) COCONUT CRAB (island 5): SMALL cute wide/flat rounded shell. Attach 2 scuttling claws + 6 little legs
-- (separate, animated), 2 coconut spots, big eyes set high on the shell, a small mouth.
local function buildCoconutCrabT()
	local s = PSS * 0.78  -- noticeably SMALLER -> cute little crab
	local m = Instance.new("Model"); m.Name = "CoconutCrabTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BROWN, DARK, CLAW = Color3.fromRGB(150,72,52), Color3.fromRGB(110,52,36), Color3.fromRGB(176,92,68)
	local src = {}
	-- a wider/flatter rounded shell -> crab body (not a tall cube)
	roundedCubeInto(src, P, 0,0,0, PSW*1.05, PSH*0.72, PSD, PSR*0.95, BROWN)
	local _, err = fuse(m, src, "BodyUnion", BROWN)
	-- 2 CLAWS out the front (role claw -> scuttle), raised pincers
	for _, sgn in ipairs({1,-1}) do P("Claw", BAL, 1.2,1.0,1.05, CLAW, 1.7,-0.1,1.15*sgn) end
	-- 6 LEGS (role leg -> gait scuttle): 3 down each side, thin little legs poking out + down
	for _, sgn in ipairs({1,-1}) do
		for _, lx in ipairs({ 0.7, 0.0, -0.7 }) do
			P("Leg", BLK, 0.32,1.0,0.32, CLAW, lx,-1.05,1.55*sgn, CFrame.Angles(math.rad(22)*sgn,0,0))
		end
	end
	for _, d in ipairs({ {1.55,0.55,0.42},{1.55,0.55,-0.42} }) do P("Dot", BAL, 0.34,0.24,0.34, DARK, d[1],d[2],d[3]) end -- 2 small coconut spots
	eyes(P, 1.34, 1.18, 0.6)  -- STANDARD eyes, moved UP a little higher on the shell (more apparent)
	mouth(P, 1.5, -0.05, 0.42)
	return m, err
end

-- 3) POPCORN SHEEP (island 8): fluffy WHITE/cream wool body. Attach 4 black legs + black floppy ears, and a
-- raised BLACK FACE PATCH (face area only) carrying the standard eyes + a small snout/mouth (its own sheep face).
local function buildPopcornSheepT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "PopcornSheepTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	-- BLACK against the cream wool (legs/ears darkest); the FACE patch is a hair lighter charcoal so the
	-- standard pure-black eyes (16,16,20) still contrast and read clearly on it.
	local CREAM, BLACK, FACEBLK, SNOUT = Color3.fromRGB(252,248,228), Color3.fromRGB(26,26,30), Color3.fromRGB(46,46,52), Color3.fromRGB(64,64,72)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, CREAM)
	for _, b in ipairs({ {0.0,1.75,0.55},{0.0,1.75,-0.55},{-0.7,1.8,0.0},{0.7,1.65,0.0},{-1.55,0.6,0.0},{0.0,0.6,1.6},{0.0,0.6,-1.6} }) do
		src[#src+1] = P("b", BAL, 1.15,1.1,1.15, CREAM, b[1],b[2],b[3]) -- chunkier wool bumps that clearly read (still fused -> fluffy white body)
	end
	local _, err = fuse(m, src, "BodyUnion", CREAM)
	-- 4 dark block LEGS (role leg -> waddle), front + back pairs, embedded into the base
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, 1.0,-1.7,-0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,0.78)
	P("Foot", BLK, 0.85,0.9,0.9, BLACK, -1.0,-1.7,-0.78)
	-- black floppy ears (role ear -> wiggle), bases embedded into the head top but tops standing proud above it
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,0.95)
	P("Ear", BAL, 0.55,0.8,0.46, BLACK, 0.55,1.78,-0.95)
	-- BLACK-FACED SHEEP: a raised BLACK FACE PATCH covering JUST the face area (not the whole front) and
	-- PROTRUDING from the white fluffy body. The standard eyes + a small snout/mouth sit ON this black face.
	-- black face patch: ~2x the frontal AREA (taller + wider: 1.75x1.85 -> 2.5x2.65) so it covers much more
	-- black around the eyes. SAME depth out: X-size (1.25) and centre x (1.45) are UNCHANGED -> the front pole
	-- still sits at x2.075, so it does NOT protrude any further than before.
	local facePatch = P("FacePatch", BAL, 1.25,2.5,2.65, FACEBLK, 1.45,0.05,0)
	-- area dims are Y(height) x Z(width): old 1.75x1.85 = 3.24 -> new 2.50x2.65 = 6.63 (~2.05x). X(depth) kept 1.25.
	local _oldArea, _newArea = 1.75*1.85, 2.50*2.65
	print(string.format("[Pet] sheep black face resized from 1.25x1.75x1.85 to 1.25x2.50x2.65 (face area %.2f -> %.2f, ~%.2fx); actual scaled Size now = %s",
		_oldArea, _newArea, _newArea/_oldArea, tostring(facePatch.Size)))
	P("Snout", BAL, 0.9,0.85,1.0, SNOUT, 2.0,-0.5,0)              -- small protruding snout on the black face
	eyes(P, 1.9, 0.45, 0.5)                                        -- SAME good eyes, pushed IN 0.1 (fx 2.0 -> 1.9) so the disc embeds FLUSH into the face patch with no gap, like the duck
	P("Nose", BAL, 0.34,0.26,0.46, Color3.fromRGB(16,16,20), 2.32,-0.45,0) -- small nose on the snout tip
	mouth(P, 2.18, -0.82, 0.34)                                    -- small clean mouth under the snout (not a smiley)
	return m, err
end

-- 4) BUTTER DUCK (island 10): rounded-cube golden body (+upturned tail bump, fused). Attach 2 flapping wings
-- (separate, animated), a flat orange bill (= the mouth, NO smile), 2 webbed feet, big eyes.
local function buildButterDuckT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "ButterDuckTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BUTTER, BILL = Color3.fromRGB(248,214,96), Color3.fromRGB(244,150,40)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BUTTER)
	src[#src+1] = P("b", BAL, 0.9,0.9,1.0, BUTTER, -1.6,0.5,0, CFrame.Angles(0,0,math.rad(28)))  -- upturned tail bump (fused)
	local _, err = fuse(m, src, "BodyUnion", BUTTER)
	-- 2 WINGS: SEPARATE flat-ish parts (role wing -> flap), inner edge embedded into the body sides
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,1.55)
	P("Wing", BLK, 1.3,0.45,1.5, BUTTER, -0.1,0.25,-1.55)
	P("Bill", BLK, 0.55,0.65,1.25, BILL, 1.85,-0.05,0)           -- flat orange bill OUT on the front (this IS the mouth -> no smile)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,0.72)        -- orange webbed block feet (role leg -> paddle)
	P("Foot", BLK, 0.85,0.7,1.05, BILL, 0.85,-1.62,-0.72)
	eyes(P, 1.72, 0.6, 0.6)  -- STANDARD eyes (fx=1.72 -> black disc backs into the body face at x1.7, front proud -> black eyes clearly visible). Bill is the mouth -> no smile.
	return m, err
end

-- 5) BURRITO ARMADILLO (island 13): rounded-cube tan body (+BANDED shell ridges + head bump, fused). Attach 4
-- waddling legs + a wiggling tail (separate, animated), a tiny nose, big eyes, a small mouth.
local function buildBurritoArmadilloT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BurritoArmadilloTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local TAN, SNT, BAND = Color3.fromRGB(196,150,100), Color3.fromRGB(150,96,56), Color3.fromRGB(168,124,80)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, TAN)
	for _, bx in ipairs({ -0.8,-0.2,0.4 }) do src[#src+1] = P("b", BAL, 0.55,0.9,2.7, BAND, bx,1.95,0) end -- RAISED banded shell ridges across the top (fused)
	src[#src+1] = P("b", BAL, 1.4,1.3,1.5, TAN, 1.82,0.0,0)         -- snout / head bump OUT at the front (fused)
	local _, err = fuse(m, src, "BodyUnion", TAN)
	-- 4 LEGS (role leg -> waddle), front + back pairs, embedded into the base
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, 1.0,-1.65,-0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,0.82)
	P("Foot", BLK, 0.8,0.85,0.85, SNT, -1.0,-1.65,-0.82)
	-- tapering TAIL out the back (role tail -> wiggle)
	P("Tail", BAL, 1.5,0.5,0.5, SNT, -2.1,-0.45,0, CFrame.Angles(0,0,math.rad(-12)))
	P("Nose", BAL, 0.34,0.28,0.34, SNT, 2.4,-0.22,0)             -- nose on the head bump front
	eyes(P, 1.72, 0.95, 0.5)                                        -- eyes embedded FLUSH into the FLAT cube body face (fx 1.72, exactly like the duck -> no gap), raised to sit on the body above the snout bump
	mouth(P, 2.18, -0.6, 0.32)                                      -- TUCKED into the snout (pushed in + down -> flusher, sits in the snout area)
	return m, err
end

-- (legacy single-template builder kept below but UNUSED -- the 5-pet loop above replaces it)
local function buildPetTemplate()
	local s = 0.9 -- display scale baked into the template

	-- bright, saturated palette (nudged up a touch so it pops through the game's dark lighting)
	local LIME   = Color3.fromRGB(146, 205, 78)  -- body
	local FOREST = Color3.fromRGB(50, 148, 62)   -- florets / claws / spikes
	local PALE   = Color3.fromRGB(214, 236, 158) -- belly
	local NDARK  = Color3.fromRGB(70, 120, 42)   -- nostril dents
	local BLACK  = Color3.fromRGB(0, 0, 0)       -- eyes
	local WHITE  = Color3.fromRGB(255, 255, 255) -- highlights / fangs
	local MOUTH  = Color3.fromRGB(38, 24, 24)    -- smile
	local BLK, BAL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder

	local model = Instance.new("Model"); model.Name = "BroccoliDinoTemplate"
	-- one place to stamp the cosmetic flags on every part
	local function flag(p)
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.CastShadow = false; p.Massless = true; p.Material = Enum.Material.SmoothPlastic
		return p
	end
	-- make a part: name, shape, (sx,sy,sz) studs (pre-scale), color, (x,y,z) studs, optional local rotation
	local function part(name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = Instance.new("Part"); p.Name = name; p.Shape = shape
		p.Size = Vector3.new(sx, sy, sz) * s; p.Color = color
		local cf = CFrame.new(x*s, y*s, z*s); if rot then cf = cf * rot end
		p.CFrame = cf; flag(p); return p
	end

	-- invisible root = PrimaryPart (the follow loop drives this; animations are offsets around it)
	local root = part("Root", BAL, 0.4, 0.4, 0.4, WHITE, 0, 0, 0); root.Transparency = 1
	root.Parent = model; model.PrimaryPart = root
	model.Parent = Workspace -- CSG needs the parts in the DataModel; we move the Model to RS after fusing

	-- ===== 1) ROUNDED-CUBE BODY/HEAD (one combined piece, ~1:1:0.8, ~4 wide) ============================
	-- Built as a fillet/Minkowski rounded box so EVERY corner+edge is soft: 3 cross slabs (the flat faces) +
	-- 8 corner spheres + 12 edge cylinders, plus a puffy rounded snout -- all lime, fused into ONE solid.
	local W, H, Dp, R = 4.2, 4.2, 3.4, 1.0          -- width(Z), height(Y), depth(X), fillet radius
	local iW, iH, iD = W - 2*R, H - 2*R, Dp - 2*R    -- inner-box dims (the flat extents)
	local hW, hH, hD = iW/2, iH/2, iD/2
	local d = 2*R                                     -- fillet diameter
	local bodySrc = {}
	local function bodyPart(name, shape, sx, sy, sz, x, y, z, rot)
		local p = part(name, shape, sx, sy, sz, LIME, x, y, z, rot); p.Parent = model; bodySrc[#bodySrc+1] = p
	end
	-- 3 cross slabs (axis-full in one dimension, inner in the others) form the flat faces
	bodyPart("BodySlab", BLK, Dp, iH, iW, 0, 0, 0)
	bodyPart("BodySlab", BLK, iD, H, iW, 0, 0, 0)
	bodyPart("BodySlab", BLK, iD, iH, W, 0, 0, 0)
	-- 8 corner spheres
	for _, c in ipairs({ {1,1,1},{1,1,-1},{1,-1,1},{1,-1,-1},{-1,1,1},{-1,1,-1},{-1,-1,1},{-1,-1,-1} }) do
		bodyPart("BodyCorner", BAL, d, d, d, c[1]*hD, c[2]*hH, c[3]*hW)
	end
	-- 12 edge cylinders (4 along each axis)
	for _, e in ipairs({ {1,1},{1,-1},{-1,1},{-1,-1} }) do
		bodyPart("EdgeX", CYL, iD, d, d, 0, e[1]*hH, e[2]*hW)
		bodyPart("EdgeY", CYL, iH, d, d, e[1]*hD, 0, e[2]*hW, CFrame.Angles(0, 0, math.rad(90)))
		bodyPart("EdgeZ", CYL, iW, d, d, e[1]*hD, e[2]*hH, 0, CFrame.Angles(0, math.rad(90), 0))
	end
	-- puffy rounded SNOUT (~38% of width), lower-centre, protruding forward -- fused into the body
	bodyPart("Snout", BAL, 1.45, 1.3, 1.6, 1.95, -0.85, 0)

	-- fuse on the server
	local unionErr
	local first = table.remove(bodySrc, 1)
	local ok, union = pcall(function() return first:UnionAsync(bodySrc) end)
	if ok and typeof(union) == "Instance" then
		first:Destroy(); for _, p in ipairs(bodySrc) do p:Destroy() end
		flag(union); union.Name = "BodyUnion"; union.UsePartColor = true; union.Color = LIME
		pcall(function() union.RenderFidelity = Enum.RenderFidelity.Precise end)
		pcall(function() union.CollisionFidelity = Enum.CollisionFidelity.Box end)
		pcall(function() union.SmoothingAngle = 60 end) -- soft satin shading across the fused body
		union.Parent = model
	else
		-- CSG unavailable: keep the (unfused) lime chunks so the FULL pet still appears (client treats
		-- unknown names as role "body"). The log will report this so we know fusion didn't run.
		unionErr = tostring(union)
		table.insert(bodySrc, 1, first)
		for _, p in ipairs(bodySrc) do p.Name = "BodyChunk" end
	end

	-- ===== separate coloured parts =================================================================
	local function add(name, shape, sx, sy, sz, color, x, y, z, rot)
		local p = part(name, shape, sx, sy, sz, color, x, y, z, rot); p.Parent = model; return p
	end

	-- 2) EYES: huge black ovals (taller than wide), domed out, wide apart on the upper face; each with
	-- EXACTLY two white highlights (big upper-left + small lower-right) seated just in front of the black.
	for _, ez in ipairs({ 1.12, -1.12 }) do
		local eye = add("Eye", BAL, 0.6, 1.9, 1.5, BLACK, 1.74, 0.98, ez)
		eye.Reflectance = 0.06 -- subtle glossy-bead shine (not a marble)
		add("Highlight", BAL, 0.12, 0.48, 0.4, WHITE, 2.06, 1.46, ez + 0.32) -- big, upper-left
		add("Highlight", BAL, 0.1, 0.22, 0.2, WHITE, 2.08, 0.62, ez - 0.3)   -- small, lower-right
	end

	-- 3) SNOUT FACE: subtle nostril dents on top + a thin dark upturned SMILE + two white down-fangs.
	for _, nz in ipairs({ 0.22, -0.22 }) do add("Nostril", BAL, 0.16, 0.1, 0.16, NDARK, 2.42, -0.42, nz) end
	add("Mouth", BAL, 0.18, 0.16, 0.74, MOUTH, 2.5, -1.3, 0)      -- smile centre (low)
	add("Mouth", BAL, 0.16, 0.16, 0.24, MOUTH, 2.46, -1.15, 0.44) -- corner, upturned
	add("Mouth", BAL, 0.16, 0.16, 0.24, MOUTH, 2.46, -1.15, -0.44)
	for _, fz in ipairs({ 0.36, -0.36 }) do add("Fang", BAL, 0.14, 0.32, 0.16, WHITE, 2.46, -1.55, fz) end

	-- 4) BELLY: pale rounded oval on the lower-front centre.
	add("Belly", BAL, 0.45, 2.2, 2.0, PALE, 1.55, -0.95, 0)

	-- 5) BROCCOLI CROWN: 6 large forest-green florets (fuzzy Grass) clustered into a dome ~as wide as the
	-- head, taller at back-centre, each on a VISIBLE lime stalk whose length is computed to seat it flush
	-- from inside the head top up into the floret (no floating).
	local headTop = H/2 -- 2.1
	for _, f in ipairs({
		{ x = -0.55, z =  0.0,  fy = 3.25, d = 1.8 },
		{ x = -0.1,  z =  0.0,  fy = 3.1,  d = 1.65 },
		{ x =  0.1,  z =  0.85, fy = 2.9,  d = 1.55 },
		{ x =  0.1,  z = -0.85, fy = 2.9,  d = 1.55 },
		{ x =  0.75, z =  0.42, fy = 2.75, d = 1.45 },
		{ x =  0.75, z = -0.42, fy = 2.75, d = 1.45 },
	}) do
		local sBot, sTop = headTop - 0.25, f.fy - f.d*0.35 -- stalk spans from just inside the head into the floret
		add("Stalk", CYL, sTop - sBot, 0.5, 0.5, LIME, f.x, (sBot + sTop)/2, f.z, CFrame.Angles(0, 0, math.rad(90)))
		local floret = add("Floret", BAL, f.d, f.d, f.d, FOREST, f.x, f.fy, f.z)
		pcall(function() floret.Material = Enum.Material.Grass end) -- fuzzy broccoli texture (florets only)
	end

	-- 6) ARMS: tiny stubby box-arms on the front-sides, angled DOWN + FORWARD, each with 3 claw nubs.
	for _, az in ipairs({ 1, -1 }) do
		local arm = add("Arm", BLK, 0.55, 0.55, 1.0, LIME, 1.0, -0.55, az*1.7, CFrame.Angles(math.rad(38), 0, math.rad(-32)*az))
		local tip = arm.CFrame * CFrame.new(0, 0, -0.55*s) -- the down-forward end of the angled arm
		for _, cx in ipairs({ -0.18, 0, 0.18 }) do
			local claw = add("ArmClaw", BAL, 0.2, 0.2, 0.22, FOREST, 0, 0, 0)
			claw.CFrame = tip * CFrame.new(cx*s, -0.08*s, 0)
		end
	end

	-- 7) LEGS: two short THICK stubby legs under the body, with 3 toe-claws each on the front edge.
	for _, lz in ipairs({ 0.95, -0.95 }) do
		add("Leg", BLK, 1.2, 1.2, 1.2, LIME, 0.2, -2.6, lz)
		for _, cz in ipairs({ -0.3, 0, 0.3 }) do add("ToeClaw", BAL, 0.32, 0.24, 0.26, FOREST, 0.8, -3.0, lz + cz) end
	end

	-- 8) TAIL: chunky tapering tail off the lower back curving up (3 shrinking segments) + 3 ridge spikes.
	add("Tail", BAL, 1.7, 1.45, 1.45, LIME, -2.0, -0.55, 0)
	add("Tail", BAL, 1.15, 1.0, 1.0, LIME, -2.85, -0.05, 0)
	add("Tail", BAL, 0.7, 0.62, 0.62, LIME, -3.45, 0.3, 0)
	for _, ts in ipairs({ {-2.0, 0.7, 0.5}, {-2.6, 0.85, 0.44}, {-3.1, 0.78, 0.36} }) do
		add("TailSpike", BAL, ts[3], ts[3]*1.6, ts[3], FOREST, ts[1], ts[2], 0)
	end

	-- ===== EFFECTS: subtle twinkle sparkles + a few drifting green leaf motes (emit from the root) ======
	local sp = Instance.new("ParticleEmitter"); sp.Name = "Sparkles"
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(Color3.fromRGB(235,255,180)); sp.Rate = 5
	sp.Lifetime = NumberRange.new(0.8,1.6); sp.Speed = NumberRange.new(0.5,1.5); sp.Size = NumberSequence.new(0.28)
	sp.Transparency = NumberSequence.new(0.2); sp.SpreadAngle = Vector2.new(180,180); sp.LightEmission = 0.8
	sp.Rotation = NumberRange.new(0,360); sp.Parent = root
	local lf = Instance.new("ParticleEmitter"); lf.Name = "Leaves"
	lf.Color = ColorSequence.new(Color3.fromRGB(60,180,50)); lf.Rate = 2
	lf.Lifetime = NumberRange.new(2,3.5); lf.Speed = NumberRange.new(0.4,1.0); lf.Size = NumberSequence.new(0.22)
	lf.Transparency = NumberSequence.new(0.1); lf.SpreadAngle = Vector2.new(180,180); lf.Acceleration = Vector3.new(0,0.6,0)
	lf.Rotation = NumberRange.new(0,360); lf.RotSpeed = NumberRange.new(-40,40); lf.Parent = root

	-- SLIGHT GLOSS: a hint of reflectance on the solid SmoothPlastic parts for a shiny collectible-toy
	-- sheen (skips the fuzzy Grass florets and the invisible root).
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Material == Enum.Material.SmoothPlastic and p.Transparency < 1 then
			p.Reflectance = math.max(p.Reflectance, 0.04)
		end
	end

	model.Parent = RS -- replicate the finished template to clients (they clone it)
	return model, unionErr
end

-- ===== SEASONAL PETS (Community Garden rewards) -- SAME rounded-cube union style/scale as the pets above
-- (roundedCubeInto -> fuse body, then welded features), reusing the shared eyes()/mouth() so they're equally cute.
-- SUMMER: SUNFLOWER BEE -- yellow striped body, white wings, a ring of sunflower petals round the face, antennae.
local function buildSunflowerBeeT()
	local s = PSS * 0.92
	local m = Instance.new("Model"); m.Name = "SunflowerBeeTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local YEL, BLKC, WHITE, PET = Color3.fromRGB(250,205,60), Color3.fromRGB(28,28,32), Color3.fromRGB(248,248,245), Color3.fromRGB(245,180,40)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, YEL); local body, err = fuse(m, src, "BodyUnion", YEL)
	for _, xo in ipairs({ -0.9, 0.0, 0.9 }) do weldTo(P("Stripe", BLK, 0.42, PSH*0.98, PSD*0.98, BLKC, xo, 0, 0), body) end -- black stripes
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.18, 1.7, 1.3, WHITE, -0.3, 1.5, 1.2*sgn, CFrame.Angles(math.rad(22*sgn),0,0)), body) end -- white wings (flap)
	for i = 0, 9 do local a = i*(2*math.pi/10); weldTo(P("Petal", BAL, 0.32, 0.5, 1.15, PET, 1.5, math.cos(a)*1.5, math.sin(a)*1.5, CFrame.Angles(a,0,0)), body) end -- sunflower-petal collar
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Antenna", CYL, 1.0, 0.1, 0.1, BLKC, 1.0, 2.4, 0.35*sgn, CFrame.Angles(0,0,math.rad(22))), body)
		weldTo(P("AntTip", BAL, 0.3,0.3,0.3, BLKC, 1.4, 2.85, 0.35*sgn), body)
	end
	eyes(P, 1.72, 0.45, 0.6); mouth(P, 1.78, -0.35, 0.62)
	return m, err
end
-- AUTUMN: MAPLE FOX -- orange body, pointy ears (white inner), white snout/cheeks, bushy white-tipped tail.
local function buildMapleFoxT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "MapleFoxTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local ORG, DORG, WHITE, BLKC = Color3.fromRGB(222,120,52), Color3.fromRGB(190,92,40), Color3.fromRGB(245,242,235), Color3.fromRGB(28,24,26)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, ORG); local body, err = fuse(m, src, "BodyUnion", ORG)
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.0*sgn
		weldTo(P("Ear", BLK, 0.5, 1.5, 1.0, ORG, 0.2, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body)   -- pointy outer ear
		weldTo(P("Ear", BAL, 0.42, 0.8, 0.55, DORG, 0.3, 3.05, zc), body)                                       -- darker pointed tip
		weldTo(P("Ear", BLK, 0.3, 0.95, 0.5, WHITE, 0.42, 2.35, zc, CFrame.Angles(math.rad(16*sgn),0,0)), body) -- white inner
	end
	weldTo(P("Snout", BAL, 0.6, 0.7, 0.95, WHITE, 1.5, -0.4, 0), body)
	weldTo(P("Nose", BAL, 0.34,0.3,0.44, BLKC, 1.98, -0.3, 0), body)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.55,0.5, WHITE, 1.55, -0.12, 0.72*sgn), body) end
	P("Tail", BAL, 1.3,1.0,1.0, ORG, -1.7,-0.1,0); P("Tail", BAL, 0.85,0.85,0.85, WHITE, -2.45,0.1,0) -- bushy white-tipped tail
	P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,0.8); P("Foot", BLK, 0.9,0.7,0.9, DORG, 0.95,-1.6,-0.8)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.7, -0.7, 0.5)
	return m, err
end
-- WINTER: FROST PENGUIN -- navy body, white belly, orange beak/feet, side flippers, ice crystals on top.
local function buildFrostPenguinT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "FrostPenguinTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local NAVY, BELLY, ORG, ICE = Color3.fromRGB(38,46,74), Color3.fromRGB(244,246,250), Color3.fromRGB(240,150,40), Color3.fromRGB(180,225,245)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, NAVY); local body, err = fuse(m, src, "BodyUnion", NAVY)
	weldTo(P("Belly", BLK, 0.3, 2.5, 2.3, BELLY, 1.55, -0.3, 0), body)            -- white belly (flat front)
	weldTo(P("Beak", BAL, 0.75, 0.5, 0.7, ORG, 1.95, 0.05, 0), body)             -- orange beak (the mouth)
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Wing", BLK, 0.9, 1.9, 0.26, NAVY, -0.1, 0.1, 1.85*sgn, CFrame.Angles(math.rad(12*sgn),0,0)), body) end -- flippers (flap)
	P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,0.7); P("Foot", BLK, 1.1,0.45,0.8, ORG, 0.9,-1.7,-0.7)
	for _, d in ipairs({ {0,2.25,0,0.6}, {0.5,2.1,0.6,0.42}, {-0.5,2.1,-0.55,0.42} }) do
		weldTo(P("Crystal", BLK, d[4],d[4],d[4], ICE, d[1], d[2], d[3], CFrame.Angles(0,math.rad(45),math.rad(45))), body) -- ice crystals on top
	end
	eyes(P, 1.72, 0.6, 0.5)
	return m, err
end
-- SPRING: BLOSSOM BUNNY -- pale-green body, long ears (pink inner), a flower crown, pink cheeks/nose, fluffy tail.
local function buildBlossomBunnyT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "BlossomBunnyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local PGREEN, PINK, WHITE, FLPINK, FLWHT, YEL = Color3.fromRGB(186,224,150), Color3.fromRGB(240,150,180), Color3.fromRGB(248,248,245), Color3.fromRGB(245,160,195), Color3.fromRGB(250,248,250), Color3.fromRGB(250,215,90)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, PGREEN); local body, err = fuse(m, src, "BodyUnion", PGREEN)
	local function ear(cx,cy,cz,len,dia,color,rot) -- cylinder + flush dome cap -> one rounded "Ear" (wiggles)
		local up = (rot * CFrame.new(1,0,0)).Position
		local part = { P("b",CYL,len,dia,dia,color,cx,cy,cz,rot), P("b",BAL,dia,dia,dia,color,cx+up.X*len*0.5,cy+up.Y*len*0.5,cz+up.Z*len*0.5) }
		weldTo(fuse(m, part, "Ear", color), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		local zc = 1.1*sgn; local rot = CFrame.Angles(math.rad(10*sgn),0,0) * CFrame.Angles(0,0,math.rad(90))
		ear(0.1, 2.9, zc, 3.9, 0.85, PGREEN, rot)  -- long ear
		ear(0.42, 2.9, zc, 3.0, 0.46, FLPINK, rot) -- pink inner
	end
	for i = -2, 2 do -- flower crown: a row of small flowers across the top-front of the head
		local zz = i * 0.66; local col = (i % 2 == 0) and FLPINK or FLWHT
		weldTo(P("Flower", BAL, 0.42,0.42,0.42, col, 0.35, 2.05, zz), body)
		weldTo(P("FlowerCtr", BAL, 0.2,0.2,0.2, YEL, 0.52, 2.1, zz), body)
	end
	for _, sgn in ipairs({ 1, -1 }) do weldTo(P("Cheek", BAL, 0.5,0.45,0.45, PINK, 1.6,-0.15,0.7*sgn), body) end
	weldTo(P("Nose", BAL, 0.34,0.32,0.46, PINK, 1.78,-0.05,0), body)
	P("Tail", BAL, 1.0,1.0,1.0, WHITE, -1.65,-0.3,0)
	P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,0.78); P("Foot", BLK, 0.9,0.75,0.9, PGREEN, 0.95,-1.55,-0.78)
	eyes(P, 1.72, 0.5, 0.62); mouth(P, 1.74, -0.42, 0.4)
	return m, err
end

-- STARTER: BEAN BUDDY -- the free first-join pet. A chubby sprouting bean: bright bean-green rounded-cube body,
-- a stem with two leaves sprouting from its head, a paler bean-belly, little feet + stubby arms, big standard eyes
-- and a smile. Same rounded-cube union style/scale as every other pet so it reads as part of the same set.
local function buildBeanBuddyT()
	local s = PSS * 0.9  -- a touch smaller -> reads as the cute little "first" pet
	local m = Instance.new("Model"); m.Name = "BeanBuddyTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local BEAN, LEAF, BELLY, STEM = Color3.fromRGB(126,200,86), Color3.fromRGB(88,168,64), Color3.fromRGB(196,232,158), Color3.fromRGB(96,150,60)
	local src = {}; roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, BEAN); local body, err = fuse(m, src, "BodyUnion", BEAN)
	-- BELLY: a pale patch on the LOWER front. Two rules keep the face readable, and both matter:
	--   (1) It must be decisively PROUD of the body's flat front face (which sits at x = PSD/2 = 1.70). A shallow
	--       ellipsoid whose front pole lands ON that plane is near-COPLANAR with it -> z-fighting, and the pale
	--       belly then flickers over / overdraws the face. Front pole here = 1.50 + 0.36 = 1.86 (0.16 proud).
	--   (2) Its top must stay BELOW the mouth (-0.39) and nowhere near the eyes (0.14..0.96), so it can never
	--       paint over either. Top here = -1.10 + 0.60 = -0.50, and the bottom (-1.70) stays inside the body (-1.80).
	weldTo(P("Belly", BAL, 0.72, 1.2, 1.9, BELLY, 1.5, -1.10, 0), body)
	-- SPROUT: a short stem out the top of the head carrying two leaves that splay out to either side.
	weldTo(P("Stem", CYL, 1.15, 0.28, 0.28, STEM, -0.1, 2.3, 0, CFrame.Angles(0,0,math.rad(90))), body)
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Ear", BAL, 0.34, 0.72, 1.5, LEAF, -0.1, 2.95, 0.72*sgn, CFrame.Angles(math.rad(20*sgn),0,0)), body) -- leaf (role "ear" -> the animator wiggles it)
	end
	for _, sgn in ipairs({ 1, -1 }) do
		P("Arm", BAL, 0.5, 0.5, 0.95, BEAN, 0.55, -0.5, 1.65*sgn, CFrame.Angles(math.rad(18*sgn),0,0)) -- stubby side arms
	end
	P("Foot", BLK, 0.85,0.75,0.85, STEM, 0.9,-1.6,0.72); P("Foot", BLK, 0.85,0.75,0.85, STEM, 0.9,-1.6,-0.72)
	-- FACE: standard eyes (disc backs into the body face at x1.7, front proud -> always visible) + a mouth raised
	-- to y-0.30 so its lower edge (-0.39) sits just ABOVE the belly top (-0.40) instead of inside it.
	eyes(P, 1.72, 0.55, 0.62); mouth(P, 1.74, -0.30, 0.42)
	-- VERIFY the face can't be overdrawn: the belly must clear the body's front plane (no z-fight) AND stay below
	-- the mouth. Both numbers must be POSITIVE or the face will flicker/disappear at some camera angles.
	do
		local bodyFaceX  = PSD * 0.5                       -- 1.70: the flat front plane of the fused body
		local bellyProud = (1.5 + 0.72 * 0.5) - bodyFaceX  -- how far the belly's front pole clears that plane
		local mouthGap   = (-0.30 - 0.09) - (-1.10 + 1.2 * 0.5) -- mouth bottom minus belly top
		print(string.format("[Pet] bean buddy face: belly proud of body face by %.2f studs (>0 = no z-fight), mouth clears belly by %.2f studs (>0 = not overdrawn), eyes proud by %.2f",
			bellyProud * s, mouthGap * s, ((1.72 + 0.22 * 0.5) - bodyFaceX) * s))
	end
	return m, err
end

-- SECRET: PIZZA DRAGON -- the 10/10 collection trophy, and a BRAND-NEW species (not a recolour of anything: every
-- pet already goes gold + shimmers at level 25, so a gold re-skin would be a worthless trophy). Themed on Pizza
-- Palms, the final island. Its silhouette is unlike any other pet in the game -- WINGS out the back, HORNS, and a
-- SPIKED TAIL -- so a player can tell one is following you from across the map.
--   crust-orange body + a melted-cheese belly + pepperoni spots (fused into the body so they read as toppings),
--   membrane wings (role "wing" -> the animator FLAPS them, like the duck's),
--   two horns, a row of back spikes, and a tail that tapers to a spike (role "tail" -> wiggles).
local function buildPizzaDragonT()
	local s = PSS
	local m = Instance.new("Model"); m.Name = "PizzaDragonTemplate"; m.Parent = Workspace
	local function P(n,sh,sx,sy,sz,c,x,y,z,r) return mkPart(m,n,sh,sx*s,sy*s,sz*s,c,x*s,y*s,z*s,r) end
	newRoot(m)
	local CRUST, CHEESE, PEP, HORN, WING = Color3.fromRGB(226,150,68), Color3.fromRGB(252,206,84),
		Color3.fromRGB(198,48,44), Color3.fromRGB(248,236,206), Color3.fromRGB(232,120,60)
	local src = {}
	roundedCubeInto(src, P, 0,0,0, PSW,PSH,PSD, PSR, CRUST)
	-- pepperoni + cheese are FUSED into the body so they're toppings ON the crust, not stuck-on lumps. (They
	-- inherit the union's single colour, so the visible topping colour comes from the separate discs below.)
	local body, err = fuse(m, src, "BodyUnion", CRUST)
	if body then body.Material = Enum.Material.Sand end -- slightly rough, like a baked crust (not shiny plastic)
	-- MELTED CHEESE belly: a wide flat patch on the lower front, decisively PROUD of the body's front plane
	-- (front pole 1.5+0.36 = 1.86 vs the plane at 1.70) so it can never z-fight -- same rule as the Bean Buddy.
	weldTo(P("Belly", BAL, 0.72, 1.5, 2.1, CHEESE, 1.5, -0.95, 0), body)
	-- PEPPERONI: flat discs pressed onto the cheese + the shoulders. Cylinders face +X, so they read as circles.
	for _, d in ipairs({ {1.80,-0.55,0.55}, {1.80,-1.35,-0.5}, {1.80,-1.25,0.62}, {1.62,0.25,-1.15} }) do
		weldTo(P("Dot", CYL, 0.16, 0.5, 0.5, PEP, d[1], d[2], d[3]), body)
	end
	-- WINGS: big membrane slabs off the upper back, swept out and back. Role "wing" -> the animator flaps them.
	for _, sgn in ipairs({ 1, -1 }) do
		P("Wing", BLK, 1.9, 1.5, 0.22, WING, -0.85, 1.0, 1.5*sgn, CFrame.Angles(math.rad(24*sgn), 0, math.rad(18)))
	end
	-- HORNS: two tapering cones swept back off the top of the head.
	for _, sgn in ipairs({ 1, -1 }) do
		weldTo(P("Horn", BLK, 0.36, 1.15, 0.36, HORN, -0.15, 2.25, 0.62*sgn, CFrame.Angles(math.rad(16*sgn), 0, math.rad(-22))), body)
	end
	-- BACK SPIKES: a shrinking row down the spine.
	for i, sz in ipairs({ 0.62, 0.52, 0.4 }) do
		weldTo(P("Spike", BLK, sz*0.55, sz, sz*0.55, HORN, -0.35 - (i-1)*0.55, 1.95, 0, CFrame.Angles(0,0,math.rad(-16))), body)
	end
	-- TAIL: three shrinking segments out the back, ending in a spike. Role "tail" -> wiggles as one.
	P("Tail", BAL, 1.4,0.75,0.75, CRUST, -2.0,-0.5,0, CFrame.Angles(0,0,math.rad(-10)))
	P("Tail", BAL, 0.9,0.5,0.5, CRUST, -2.75,-0.25,0)
	P("Tail", BLK, 0.5,0.55,0.35, HORN, -3.25,0.0,0, CFrame.Angles(0,0,math.rad(-30)))
	P("Foot", BLK, 0.9,0.8,0.9, CRUST, 0.95,-1.6,0.78); P("Foot", BLK, 0.9,0.8,0.9, CRUST, 0.95,-1.6,-0.78)
	-- FACE: the standard eyes (same geometry as every other pet -- disc backs into the body face at x1.7, front
	-- proud, so it can never be overdrawn) sitting well ABOVE the cheese belly (which tops out at -0.20).
	eyes(P, 1.72, 0.75, 0.62); mouth(P, 1.74, 0.05, 0.46)
	return m, err
end

-- Build ALL fused pet templates at startup, apply a slight toy gloss, and store each in ReplicatedStorage
-- (the client clones them). Each logs its own union result. (buildPetTemplate above is legacy/unused.)
-- ===== REBIRTH MILESTONE PETS: exclusive pets earned at rebirth counts. Recolour-CLONES of existing templates
-- (no new geometry). questType="rebirth" keeps them out of island quests AND the collection count. =====
PETS.MoltenBean = { displayName = "Molten Bean",  questType = "rebirth", rebirthReq = 3,  maxLevel = 3, tiers = { [2] = { height = 3000, time = 150 }, [3] = { height = 12000, time = 500 } } }
PETS.VoidDragon = { displayName = "Void Dragon",  questType = "rebirth", rebirthReq = 6,  maxLevel = 3, tiers = { [2] = { height = 3000, time = 150 }, [3] = { height = 12000, time = 500 } } }
PETS.PrismFox   = { displayName = "Prism Fox",    questType = "rebirth", rebirthReq = 10, maxLevel = 3, tiers = { [2] = { height = 3000, time = 150 }, [3] = { height = 12000, time = 500 } } }
-- exposed so the RebirthSystem (grant) + the Rebirth menu (display) share ONE source of truth
_G.REBIRTH_PET_MILESTONES = { { req = 3, id = "MoltenBean", name = "Molten Bean" }, { req = 6, id = "VoidDragon", name = "Void Dragon" }, { req = 10, id = "PrismFox", name = "Prism Fox" } }

-- clone a finished template, tint every part toward `tint`, rename to <newId>Template (the client keys the clone
-- on that name via its PET_TEMPLATE map). Returns the model (the builder loop below parents it to RS).
local function buildRecolorClone(newId, baseTemplateName, tint)
	local base = RS:FindFirstChild(baseTemplateName)
	if not base then return nil, "base template '" .. baseTemplateName .. "' not ready" end
	local m = base:Clone(); m.Name = newId .. "Template"
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then d.Color = d.Color:Lerp(tint, 0.6) end end
	return m
end
local function buildMoltenBeanT() return buildRecolorClone("MoltenBean", "BeanBuddyTemplate",   Color3.fromRGB(255, 90, 30)) end   -- fiery
local function buildVoidDragonT() return buildRecolorClone("VoidDragon", "PizzaDragonTemplate", Color3.fromRGB(120, 60, 200)) end   -- void purple
local function buildPrismFoxT()   return buildRecolorClone("PrismFox",   "MapleFoxTemplate",    Color3.fromRGB(255, 215, 90)) end   -- gold

local PET_TEMPLATE_BUILDERS = {
	{ id = "BeanBuddy",        fn = buildBeanBuddyT,        name = "Bean Buddy" }, -- free first-join starter pet
	{ id = "PizzaDragon",      fn = buildPizzaDragonT,      name = "Pizza Dragon" }, -- SECRET 10/10 collection reward
	{ id = "BroccoliPet",      fn = buildBroccoliBunny },
	{ id = "CoconutCrab",      fn = buildCoconutCrabT },
	{ id = "PopcornSheep",     fn = buildPopcornSheepT },
	{ id = "ButterDuck",       fn = buildButterDuckT },
	{ id = "BurritoArmadillo", fn = buildBurritoArmadilloT },
	{ id = "SunflowerBee",     fn = buildSunflowerBeeT,     seasonal = true, name = "Sunflower Bee" },
	{ id = "MapleFox",         fn = buildMapleFoxT,         seasonal = true, name = "Maple Fox" },
	{ id = "FrostPenguin",     fn = buildFrostPenguinT,     seasonal = true, name = "Frost Penguin" },
	{ id = "BlossomBunny",     fn = buildBlossomBunnyT,     seasonal = true, name = "Blossom Bunny" },
	-- rebirth clones LAST so their base templates are already built + in RS when they clone
	{ id = "MoltenBean",       fn = buildMoltenBeanT,       name = "Molten Bean" },
	{ id = "VoidDragon",       fn = buildVoidDragonT,       name = "Void Dragon" },
	{ id = "PrismFox",         fn = buildPrismFoxT,         name = "Prism Fox" },
}
task.spawn(function()
	local totalSmoothed = 0
	for _, b in ipairs(PET_TEMPLATE_BUILDERS) do
		local ok, model, err = pcall(b.fn)
		if ok and model then
			-- (no gloss pass: all pet parts are matte Enum.Material.Plastic + all surfaces Smooth via flagPart ->
			-- clean matte plastic, no Lego-stud/notch texture)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
			totalSmoothed = totalSmoothed + n
			model.Parent = RS -- replicate the finished template to clients
			if err then
				warn("[Pet][UNION] "..b.id.." union FAILED ("..tostring(err)..") -- template ready with UNFUSED body (still appears)")
			else
				print("[Pet][UNION] "..b.id.." rounded-cube body SUCCESS ("..n.." parts -> matte Plastic + Smooth surfaces)")
			end
			if b.seasonal then print("[Pet] seasonal "..b.name.." built ("..(err and "union FAILED" or "union ok")..")") end
		else
			warn("[Pet][UNION] "..b.id.." template build error: "..tostring(model or err))
		end
	end
	print("[Pet] surface sweep: "..totalSmoothed.." pet parts set to clean matte Plastic + all faces Smooth (no stud/notch texture)")
end)

-- ===== STATE HELPERS =====
-- ownsPet checks a STORAGE KEY exactly (the unit of equip/level/trade). A key is either a species id ("ButterDuck",
-- the NORMAL variant) or a species id + the rare suffix ("ButterDuck#R", the RARE variant). Normal pets keep key==petId
-- so all existing single-pet code is unchanged; rares get the suffix so a normal AND a rare of one species can coexist.
local function ownsPet(player, key)
	local op = _G.playerOwnedPets[player]
	return op ~= nil and op[key] ~= nil -- value may be `true` (legacy) or a {level,height,time,count,rare} table
end
local RARE_SUFFIX = "#R"

-- ===== STORAGE KEYS: ONE STACK PER (SPECIES, RARITY) ==========================================================
-- A player holds a separate stack for each rarity of each species, because fusion needs to count copies at a
-- SPECIFIC band ("5 Common Broccoli Bunnies", not "5 Broccoli Bunnies of any kind"). The key encodes both:
--
--     BroccoliPet            -- Common (the bare species id: this is also exactly what every pre-rarity save
--                               already wrote, so old saves load as Common with no migration step)
--     BroccoliPet#Uncommon   -- one stack per band above Common
--     BroccoliPet#R          -- LEGACY. The old 1-in-750 "rare" flag, from before rarity was a ladder.
--                               Read as Gold (it was the rarest thing a pet could be), never written again.
--
-- variantKey() takes EITHER a rarity string OR the old boolean, on purpose: there are 30+ existing call sites
-- passing `true`/`false`/nil, and quietly reinterpreting a boolean as a band name would have silently rekeyed
-- every one of them. A boolean still means what it always meant; strings are the new path.
local function variantKey(petId, rarity)
	if rarity == true  then return petId .. RARE_SUFFIX end -- legacy caller: the old rare slot
	if rarity == nil or rarity == false or rarity == PetRarity.DEFAULT then return petId end
	if not PetRarity.isValid(rarity) then return petId end  -- unknown band -> Common, never a junk key
	return petId .. "#" .. rarity
end

-- storage key -> species id. Strips the legacy #R and any #Band suffix. Anchored to the END and matched
-- against the KNOWN band list, so a species whose own id contained a '#' could never be truncated by accident.
local function speciesOf(key)
	if type(key) ~= "string" then return key end
	if key:sub(-#RARE_SUFFIX) == RARE_SUFFIX then return key:sub(1, -#RARE_SUFFIX - 1) end
	for _, band in ipairs(PetRarity.ORDER) do
		local suf = "#" .. band
		if key:sub(-#suf) == suf then return key:sub(1, -#suf - 1) end
	end
	return key
end

-- storage key -> the rarity band it represents (bare key = Common, legacy #R = Gold).
local function rarityOfKey(key)
	if type(key) ~= "string" then return PetRarity.DEFAULT end
	if key:sub(-#RARE_SUFFIX) == RARE_SUFFIX then return PetRarity.TOP end -- legacy rare == top of the ladder
	for _, band in ipairs(PetRarity.ORDER) do
		local suf = "#" .. band
		if key:sub(-#suf) == suf then return band end
	end
	return PetRarity.DEFAULT
end

-- every storage key that exists for a species, Common first then up the ladder, plus the legacy rare slot.
local function allKeysOf(petId)
	local t = { petId }
	for _, band in ipairs(PetRarity.ORDER) do
		if band ~= PetRarity.DEFAULT then t[#t + 1] = petId .. "#" .. band end
	end
	t[#t + 1] = petId .. RARE_SUFFIX -- legacy stacks still on disk from before the ladder
	return t
end

-- owns ANY variant (any rarity) of a species -- used by quest gates / "do you have this pet at all" checks.
local function ownsSpecies(player, petId)
	for _, k in ipairs(allKeysOf(petId)) do
		if ownsPet(player, k) then return true end
	end
	return false
end

-- the storage keys a player actually owns for a species, in ladder order (Common -> Gold, legacy last).
local function ownedKeysOf(player, petId)
	local t = {}
	for _, k in ipairs(allKeysOf(petId)) do
		if ownsPet(player, k) then t[#t + 1] = k end
	end
	return t
end

local function foundCount(player, petId)
	local s = piecesFound[player] and piecesFound[player][petId]
	if not s then return 0 end
	local n = 0; for _ in pairs(s) do n = n + 1 end; return n
end

-- RE-DOABLE QUESTS: a pet quest is DOABLE AGAIN whenever the player currently owns ZERO of that species
-- (e.g. they traded their only one away). Owning >=1 keeps it completed/locked -> no farming duplicates.
-- everCompleted is a PERMANENT flag used ONLY to gate the rare roll (see PetClaimEvent); it does NOT lock the quest.
local function questAvailable(player, petId)
	local owns = ownsSpecies(player, petId) -- owning ANY variant (normal or rare) locks the quest
	local ever = (_G.playerEverCompletedQuests[player] or {})[petId] == true
	local available = not owns
	print(string.format("[PetQuest] %s quest %s availability: ownsCount=%d, everCompleted=%s -> available=%s",
		player.Name, petId, owns and 1 or 0, ever and "y" or "n", available and "y" or "n"))
	return available
end
-- Wipe a pet's quest PROGRESS so it must be genuinely re-done from scratch (used when ownership drops to zero
-- via a trade). Session-only progress: collected pieces + the fishing/dig anti-cheat gates.
local function resetQuestProgress(player, petId)
	if piecesFound[player] then piecesFound[player][petId] = nil end
	if petId == "ButterDuck" then fishEggReady[player] = nil; fishCatches[player] = nil end -- duck must re-catch the egg
	if petId == "BurritoArmadillo" then digEggReady[player] = nil end                       -- armadillo must re-dig the egg
end

-- ===== LEVELING (cosmetic prestige -- 1..50, XP-driven, NO gameplay/flight effect whatsoever) =====
local PET_MAX_LEVEL = 25
-- Rising XP curve: each level needs progressively more (base * level^1.6) so 1->8 is quick and 20->25 is a
-- real grind. xpNeeded(L) = XP to go from level L to L+1. (Rescaled for a 25-level cap.)
local PET_XP_BASE, PET_XP_EXP = 80, 1.6
local function xpNeeded(level)
	if level >= PET_MAX_LEVEL then return math.huge end
	return math.floor(PET_XP_BASE * (level ^ PET_XP_EXP))
end
-- XP award RATES (all tuning lives here). Cosmetic-only -- these NEVER touch flight/gas/coins balance.
local XP_PER_COIN        = 0.15  -- coins earned -> XP (proportional)
local XP_PER_FLIGHT_TICK = 6     -- each 0.5s coin tick fires DURING FLIGHT -> "distance flown" XP
local XP_PER_GAS         = 0.5   -- gas/power gained from eating food -> XP
local XP_PER_ISLAND      = 600   -- reaching a NEW island -> a chunk of XP
-- The cosmetic VISUAL tier name for a level (milestones at 10/20/30/40/50) -- diagnostics + card hint only.
local function tierVisual(level)
	if level >= 25 then return "MAX (all accessories + gold + shimmer)"
	elseif level >= 23 then return "5 accessories + full trail/aura/sparkles"
	elseif level >= 18 then return "4 accessories + sparkles + growing"
	elseif level >= 15 then return "3 accessories + sparkles + growing"
	elseif level >= 13 then return "3 accessories + aura + growing"
	elseif level >= 10 then return "2 accessories + aura + growing"
	elseif level >= 8 then return "2 accessories + trail + growing"
	elseif level >= 5 then return "1 accessory + trail + growing"
	elseif level >= 3 then return "1 accessory, growing"
	else return "starter (growing)" end
end
local function nextMilestoneHint(level)
	if level >= 25 then return "MAX reached"
	elseif level >= 23 then return "Lvl 25: MAX (gold + shimmer)"
	elseif level >= 18 then return "Lvl 23: accessory #5"
	elseif level >= 13 then return "Lvl 18: accessory #4"
	elseif level >= 8 then return "Lvl 13: accessory #3 (hat)"
	elseif level >= 3 then return "Lvl 8: accessory #2 (glasses)"
	else return "Lvl 3: accessory #1" end
end
local function isMilestone(level) return level==3 or level==8 or level==13 or level==18 or level==23 or level==25 end
-- ===== RARE HATCH VARIANTS (Stage 2): a rare is a FLAG on the owned pet (additive: data.rare=true), comes
-- PRE-MAXED + a unique rare look. Cosmetic. Exotic = 1 in 750; the Cosmic Duck (Mythical) = 1 in 10,000.
local RARE_NAMES = {
	BroccoliPet = "Emerald Bunny", CoconutCrab = "Golden Crab", PopcornSheep = "Cloud Sheep",
	BurritoArmadillo = "Crystal Armadillo", ButterDuck = "Cosmic Duck",
}
-- The Cosmic Duck is the single rarest thing in the game: 1 in 10,000. Every other pet's rare (Exotic) is 1 in 750.
local function rareOdds(petId) return (petId == "ButterDuck") and 10000 or 750 end

-- ===== PET RARITY ODDS (was: the hatch-tier roll) =======================================================
-- THE OLD TABLE IS GONE. It rolled a pet's starting AGE (Baby..Elder, weights out of 10000) at hatch time,
-- and nothing rolls that any more: age is grown from flight and playtime, so every pet starts at Baby. The
-- weights, the roll and the "1 in N" strings derived from them all described a mechanic that no longer
-- exists -- leaving them would have kept advertising odds for a dice roll the game stopped making.
--
-- What players actually want odds for now is RARITY, and the only place rarity is rolled is the Pet Crate.
-- So the odds published here are read straight out of SkinCrates, via effectiveOdds() -- the SAME accessor
-- the crate's own odds panel prints and the same numbers the roll uses. There is no second copy to drift:
-- retune the crate and this follows automatically.
--
-- effectiveOdds (not the raw odds table) on purpose: it accounts for empty-band redistribution, so if a band
-- ever ends up with no stock the number here stays truthful instead of quietly over-promising.
local PET_CRATE_ODDS_TEXT = {}
do
	local ok, odds = pcall(SkinCrates.effectiveOdds, "Pets")
	if ok and type(odds) == "table" then
		for band, pct in pairs(odds) do
			if type(pct) == "number" and pct > 0 then
				local n = 100 / pct
				-- whole numbers print clean ("1 in 25", not "1 in 25.0"); only a genuinely fractional ratio
				-- keeps its decimal, which in practice is just Common ("1 in 1.7").
				local whole = math.floor(n + 0.5)
				PET_CRATE_ODDS_TEXT[band] = (math.abs(n - whole) < 0.05)
					and ("1 in " .. whole) or string.format("1 in %.1f", n)
			end
		end
	else
		warn("[Pet] could not read Pet Crate odds from SkinCrates -- the rarity ladder will show no odds")
	end
end
-- Normalize an owned entry to a {level,xp,height,time} table (legacy saves stored `true`; xp is ADDITIVE --
-- missing pets/fields default to level 1, 0 XP so existing saves are never broken).
local function getPetData(player, petId)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local v = op[petId]; if v == nil then return nil end
	if type(v) ~= "table" then v = {}; op[petId] = v end
	v.level = v.level or 1; v.xp = v.xp or 0; v.height = v.height or 0; v.time = v.time or 0
	v.count = math.max(1, math.floor(tonumber(v.count) or 1)) -- how many of THIS variant the player has stacked (legacy saves -> 1)
	-- RARITY IS DERIVED FROM THE KEY, NOT TRUSTED FROM THE SAVE. The key is what decides which stack a pet
	-- lives in, so if a stored `rarity` field ever disagreed with the key the two would fight -- and fusion,
	-- which counts copies per band, would count the wrong pile. The key wins, always.
	v.rarity = rarityOfKey(petId)
	if v.rare then v.rarity = PetRarity.TOP end -- legacy rare flag outranks a bare key (old saves)
	if v.level > PET_MAX_LEVEL then v.level = PET_MAX_LEVEL; v.xp = 0 end -- clamp legacy saves to the new 25 cap
	return v
end
-- The next level + its achievement threshold (nil if already maxed).
local function nextTier(player, petId)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return nil end
	local nl = d.level + 1
	if nl > (def.maxLevel or 1) then return nil end
	return nl, def.tiers and def.tiers[nl]
end
-- Has the achievement threshold for the next level been met?
local function canUpgrade(player, petId)
	local nl, th = nextTier(player, petId)
	if not nl then return false end
	if not th then return true end -- no threshold defined -> always available
	local d = getPetData(player, petId)
	return (d.height >= (th.height or math.huge)) or (d.time >= (th.time or math.huge))
end

-- Build the full state for one player across all pets and send it to that client.
local function sendState(player)
	local state = {}
	local eq = _G.playerEquippedPet[player]                       -- a STORAGE KEY (petId or petId#R)
	local eqSpecies = eq and speciesOf(eq) or nil
	for petId, def in pairs(PETS) do
		local owns = ownsSpecies(player, petId)
		local isEquipped = owns and (eqSpecies == petId) or false  -- the client only spawns the EQUIPPED follower
		-- follower look comes from the EQUIPPED stack if this species is equipped, else any owned stack (normal first)
		local d = isEquipped and getPetData(player, eq)
			or (owns and (getPetData(player, petId) or getPetData(player, variantKey(petId, true))))
		state[petId] = {
			found = foundCount(player, petId), total = def.pieceMarkers and #def.pieceMarkers or 0, owns = owns,
			equipped = isEquipped,
			level = (d and d.level) or 1,
			rare = (d and d.rare) or false, -- rare variant flag (client applies pre-maxed + rare look)
		}
	end
	pcall(function() PetStateEvent:FireClient(player, state) end)
end

-- True if this player has DISCOVERED a pet's quest (landed on its island, or owns the pet).
local function questDiscovered(player, petId)
	if ownsSpecies(player, petId) then return true end
	local dq = _G.playerDiscoveredQuests[player]
	return dq ~= nil and dq[petId] == true
end

-- ===== EXTRA FACTS for the VIEW MORE detail card (cosmetic read-outs; nothing here affects balance) =====
-- The levels at which a pet gains an accessory (bowtie/glasses/hat/backpack/...). Mirrors the client's real
-- accessory schedule in PET_THEME.accs, so "3 / 7 unlocked" is the truth, not the older 3/8/13/18/23 hint.
local ACC_LEVELS = { 3, 7, 10, 13, 17, 20, 23 }
local function accessoryCount(level)
	local n = 0
	for _, L in ipairs(ACC_LEVELS) do if (level or 1) >= L then n = n + 1 end end
	return n
end
-- LIFETIME XP: everything banked into every level so far, plus progress into the current one. This is the number
-- that shows how much a pet has actually been flown -- the per-level `xp` alone resets every level-up and hides it.
local function totalXpEarned(level, xp)
	local t = xp or 0
	for L = 1, (level or 1) - 1 do t = t + xpNeeded(L) end
	return math.floor(t)
end
-- A human label for how a pet is earned, used on the detail card ("Quest type" fact).
local QUEST_LABEL = {
	find = "Hidden pieces", crack = "Coconut cracking", ["film-reels"] = "Film reel hunt",
	fishing = "Fishing", dig = "Buried treasure", seasonal = "Garden harvest", starter = "Free gift",
}

-- One line telling a player HOW to get a pet they don't own yet -- shown on the LOCKED card in the pet index.
-- Kept generic (island + what to do), never a step-by-step spoiler: it says where to go, not where things hide.
local function unlockHint(def)
	if def.questType == "starter" then return "A free gift for new players" end
	if def.questType == "collection" then return "SECRET \xE2\x80\x94 collect every other pet to earn it" end
	if def.questType == "seasonal" then
		return "Grow the Community Garden to full bloom in " .. (def.season or "season")
	end
	if def.questType == "rebirth" then return "\xF0\x9F\x94\x84 Reach Rebirth " .. (def.rebirthReq or "?") end
	return def.questDesc or ("Complete the quest on " .. (def.islandName or "its island"))
end

-- ============================================================================================================
-- COLLECTION MILESTONES (definitions + counting). Declared HERE, above sendInventory, because the payload needs
-- them; the AWARDING logic (checkCollectionMilestones) lives further down, where sendState/sendInventory exist.
--
-- No coins anywhere. The rewards are TITLES (a floating nametag every other player can see -- see
-- TitleTags.client.luau) and, at 10/10, the SECRET PIZZA DRAGON, which exists nowhere else in the game.
--
-- THE COUNTING RULE, and it matters: the Pizza Dragon is questType="collection", and BOTH counts below skip it.
-- It is the prize for completing the set, so it cannot be part of the set -- if it counted, "collect them all"
-- would require owning the very thing you get FOR collecting them all, which is unwinnable. So the target is 10,
-- not 11, and a finished player shows 10/10 while actually owning 11 pets.
-- ============================================================================================================
local COLLECTION_MILESTONES = {
	{ need = 3,  kind = "title", id = "Pet Keeper",    name = "Title: Pet Keeper",    desc = "A nametag above your head" },
	{ need = 5,  kind = "title", id = "Pet Collector", name = "Title: Pet Collector", desc = "A rarer nametag above your head" },
	{ need = 7,  kind = "title", id = "Beastmaster",   name = "Title: Beastmaster",   desc = "The top nametag in the game" },
	{ need = 10, kind = "pet",   id = "PizzaDragon",   name = "SECRET PET: Pizza Dragon",
		desc = "A brand-new pet that cannot be earned any other way" },
}
-- how many pets COUNT toward the collection (everything except the collection reward itself)
local function collectableCount()
	local n = 0
	for _, def in pairs(PETS) do if def.questType ~= "collection" and def.questType ~= "rebirth" then n = n + 1 end end
	return n
end
-- how many of those this player owns (any variant -- a rare still counts as its species, exactly once)
local function collectedCount(player)
	local n = 0
	for petId, def in pairs(PETS) do
		if def.questType ~= "collection" and def.questType ~= "rebirth" and ownsSpecies(player, petId) then n = n + 1 end
	end
	return n
end
-- Exposed for OTHER systems (the global PETS COLLECTED leaderboard; offline earnings). Both counts already
-- exclude the secret Pizza Dragon, so anything reading these sees the same 10-pet target the Pet Hub shows.
_G.petsCollectedCount = collectedCount
_G.petsCollectableCount = collectableCount
-- Total LEVELS across every pet a player owns -- the offline-earnings rate scales off this, so a big, well-
-- levelled collection earns a little more than a single Lv1 pet. Read-only; never mutates pet data.
_G.petsTotalLevels = function(player)
	local op = _G.playerOwnedPets[player]
	if type(op) ~= "table" then return 0 end
	local total = 0
	for skey in pairs(op) do
		local d = getPetData(player, skey)
		if d and type(d.level) == "number" then total = total + d.level end
	end
	return total
end

-- Build + send the inventory payload to the GUI:
--   owned     = full cards (level/equip/upgrade) per OWNED pet
--   quests    = discovered quests (island/status/desc/progress) -- only once landed/owned
--   catalog   = EVERY pet in the game + whether this player owns it + how to unlock it. This is what lets the
--               Pet Hub render a LOCKED silhouette card for pets the player hasn't got yet (the pet index), so
--               they can see the whole collection and what they're missing instead of only what they own.
--   totalPets = how many pets exist in the catalog (the "N / total collected" counter)
local function sendInventory(player)
	local equipped = _G.playerEquippedPet[player]
	local payload = { owned = {}, quests = {}, catalog = {} }
	-- The REAL rarity odds, read out of the Pet Crate (see PET_CRATE_ODDS_TEXT). Keyed by rarity band
	-- (Common..Gold) -- these used to be the Baby..Elder age-roll odds, which described a roll the game no
	-- longer makes. `petCrateOdds` is the honest name and what new UI should read; `hatchOdds` is kept as an
	-- alias to the same table so any older client that still reads it shows correct numbers rather than
	-- stale ones for a deleted mechanic.
	payload.petCrateOdds = PET_CRATE_ODDS_TEXT
	payload.hatchOdds    = PET_CRATE_ODDS_TEXT
	-- COLLECTION PROGRESS. totalPets is the COLLECTABLE count (10), NOT #PETS (11) -- the Pizza Dragon is the prize
	-- for finishing, not part of what you finish. See the counting rule above.
	payload.totalPets = collectableCount()
	payload.collected = collectedCount(player)
	payload.title     = _G.playerTitle[player] -- the title they're currently wearing (nil if none yet)
	payload.milestones = {}
	do
		local claimed = _G.playerPetMilestones[player] or {}
		for i, ms in ipairs(COLLECTION_MILESTONES) do
			payload.milestones[i] = {
				need = ms.need, kind = ms.kind, name = ms.name, desc = ms.desc,
				claimed = claimed[tostring(ms.need)] == true,
			}
		end
	end
	for petId, def in pairs(PETS) do
		payload.catalog[#payload.catalog + 1] = {
			petId       = petId,
			displayName = def.displayName or petId,
			owned       = ownsSpecies(player, petId), -- ANY variant (normal or rare) counts as collected
			islandName  = def.islandName,
			questType   = def.questType,
			unlock      = unlockHint(def),
			lore        = PET_LORE[petId], -- the detail card works for locked pets too (see it before you earn it)
			questLabel  = QUEST_LABEL[def.questType] or def.questType,
			rareOdds    = rareOdds(petId), -- "Rare chance: 1 in 750" -- a reason to care which pet you go for
		}
		-- ONE card per OWNED STACK: a species can have up to two (a normal stack and/or a separate rare stack). Each
		-- entry is keyed by its STORAGE KEY (petId or petId#R) and carries petId=the SPECIES (the client keys icons/
		-- templates/equip on that) so normal + rare show as separate cards and each can be equipped/traded on its own.
		for _, skey in ipairs(ownedKeysOf(player, petId)) do
			local d = getPetData(player, skey)
			payload.owned[skey] = {
				petId = petId,
				displayName = def.displayName or petId,
				level = d.level, maxLevel = PET_MAX_LEVEL,
				xp = math.floor(d.xp), xpNeed = (d.level >= PET_MAX_LEVEL) and 0 or xpNeeded(d.level),
				milestone = nextMilestoneHint(d.level), tierVisual = tierVisual(d.level),
				equipped = (equipped == skey),
				height = math.floor(d.height), time = math.floor(d.time),
				rare = d.rare and true or false, rareName = d.rare and RARE_NAMES[petId] or nil, -- RARE badge + variant name
				count = d.count or 1, -- how many of this exact variant are stacked (shows as "xN")
				-- ===== RARITY (permanent) + FUSION PROGRESS =====
				-- Sent alongside the legacy `rare` boolean rather than replacing it: `rare` still drives the
				-- existing rare look/pre-maxed rendering in PetFollow, and swapping it out would have meant
				-- touching ~150 call sites across six client scripts to ship one feature.
				rarity     = d.rarity,                          -- "Common".."Gold" -- NEVER changes with age
				fuseCost   = PetRarity.costToFuse(d.rarity),    -- nil at Gold: nothing to fuse into
				fuseInto   = PetRarity.nextOf(d.rarity),        -- the band this stack fuses up to
				canFuse    = (select(1, PetRarity.canFuse(d.rarity, d.count))),
				-- ===== VIEW MORE detail-card facts (display only) =====
				lore = PET_LORE[petId], islandName = def.islandName,
				totalXp = totalXpEarned(d.level, d.xp),                  -- lifetime XP, not just this level's
				accessories = accessoryCount(d.level), accessoriesMax = #ACC_LEVELS,
				rareOdds = rareOdds(petId),                              -- 750, or 10000 for the duck -> "1 in 750"
				questLabel = QUEST_LABEL[def.questType] or def.questType,
			}
		end
		-- seasonal (garden), starter (free gift) and collection (the secret 10/10 pet) pets are all GRANTED, not
		-- quested -- none belongs in the quests panel (they still get an OWNED inventory card from the loop above).
		if questDiscovered(player, petId) and def.questType ~= "seasonal" and def.questType ~= "starter"
			and def.questType ~= "collection" and def.questType ~= "rebirth" then
			local found = foundCount(player, petId)
			local total = #def.pieceMarkers
			local status = ownsSpecies(player, petId) and "done" or (found > 0 and "inprogress" or "available")
			payload.quests[petId] = {
				islandName = def.islandName or petId,
				desc = def.questDesc or "",
				status = status, found = found, total = total,
				unit = def.questUnit or ((def.questType == "crack") and "coconuts" or "pieces"),
			}
		end
	end
	pcall(function() PetInventoryEvent:FireClient(player, payload) end)
end

-- ============================================================================================
-- CROSS-PLAYER PET VISIBILITY (Option B) -- ADDITIVE. Besides the owner-only sendState/sendInventory
-- above, BROADCAST each player's equipped-pet info to ALL clients so RemotePets.client.lua can build +
-- follow OTHER players' pets. This NEVER changes sendState/sendInventory or how the owner's own pet
-- (PetFollow) works -- it's an extra fire-and-forget message. No server-side pet models / CSG here.
-- ============================================================================================
local function buildEquipPayload(player)
	local skey = _G.playerEquippedPet[player]
	local petId, level, isRare, variant = nil, 1, false, nil
	local skin, trait = nil, nil
	if skey and ownsPet(player, skey) then
		local d = getPetData(player, skey)
		petId = speciesOf(skey) -- remote clients render by SPECIES (+ the rare flag/variant below)
		if d then level = d.level or 1; isRare = d.rare and true or false end
		if isRare then variant = RARE_NAMES[petId] end
		-- THE SKIN TRAVELS WITH THE PET.
		-- Without these two fields the payload described a SPECIES and nothing else, so every remote viewer
		-- rendered the plain base pet: you saw your Cosmic-skinned duck with its trait effects, and everyone
		-- else saw an ordinary duck. The whole point of a cosmetic is that other people can see it -- a skin
		-- only the owner can see is a skin nobody has a reason to buy.
		-- Read through skinEquippedFor rather than poking _G.playerEquippedSkins directly, so the entry's
		-- shape stays SkinCrateService's business and this cannot drift from it.
		if _G.skinEquippedFor then
			local ok, s, t = pcall(_G.skinEquippedFor, player, petId)
			if ok then skin, trait = s, t end
		end
	end
	return { userId = player.UserId, petId = petId, level = level, isRare = isRare, variant = variant,
		skin = skin, trait = trait }
end
local function broadcastEquip(player, reason)
	if not player then return end
	local payload = buildEquipPayload(player)
	pcall(function() PetEquipBroadcast:FireAllClients(payload) end)
	print(string.format("[RemotePets] broadcast %s pet=%s lvl=%d rare=%s (reason=%s)",
		player.Name, tostring(payload.petId), payload.level, payload.isRare and "y" or "n", tostring(reason)))
end
-- Published so OTHER systems can re-announce a player's look when they change something this file does not
-- own. SkinCrateService calls it after equipping or clearing a skin: that push only reaches the owner, so
-- without a re-broadcast every other player keeps rendering the previous look.
_G.petRebroadcastEquip = function(player, reason)
	if player and player.Parent then broadcastEquip(player, reason or "external") end
end

-- Send the CURRENT equipped pet of everyone ALREADY in the server to ONE (newly-joined) client, so late
-- joiners immediately see existing players' pets (existing players don't re-broadcast just because one joins).
local function sendAllEquipsTo(target)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= target then
			pcall(function() PetEquipBroadcast:FireClient(target, buildEquipPayload(p)) end)
		end
	end
end

-- ===== CLIENT-READY RE-SYNC: fixes "my friend saw my pet, I couldn't see theirs" =====
-- The join-time catch-up above fires the moment the SAVE loads -- often seconds before the joining
-- client's RemotePets script has connected its OnClientEvent. Remote fires that land before a client
-- connects a handler are simply lost, so the late joiner missed the whole catch-up burst (while their
-- own "join" broadcast reached everyone else's already-running clients -- hence the one-way visibility).
-- RemotePets now fires this remote UPWARD when its listener is live; the server answers with a fresh
-- catch-up and re-announces the requester to everyone (covers the mirror case: their join broadcast
-- fired while some OTHER client was still loading). Debounced so a spammy client costs nothing.
local lastEquipSync = {}
PetEquipBroadcast.OnServerEvent:Connect(function(player)
	local t = os.clock()
	if lastEquipSync[player] and t - lastEquipSync[player] < 3 then return end
	lastEquipSync[player] = t
	sendAllEquipsTo(player)
	broadcastEquip(player, "client-ready")
end)
Players.PlayerRemoving:Connect(function(p) lastEquipSync[p] = nil end)

-- Level a pet up by one (the XP auto-level loop and the Robux/test skip all funnel here). Re-syncs follower + GUI.
local function levelUp(player, petId, via)
	local def = PETS[petId]; local d = getPetData(player, petId)
	if not (def and d) then return false end
	if d.level >= PET_MAX_LEVEL then return false end
	d.level = d.level + 1
	print("[PetLvl] "..petId.." LEVELED UP to "..d.level.." (via "..tostring(via)..")")
	if isMilestone(d.level) then print("[PetLvl] "..petId.." hit milestone "..d.level.." -> "..tierVisual(d.level)) end
	sendState(player)     -- the follower re-applies its per-level cosmetic tier visual
	sendInventory(player) -- the card shows the new level + reset XP bar
	if _G.playerEquippedPet[player] == petId then broadcastEquip(player, "levelup") end -- remote viewers see the new level look
	return true
end

-- EXTERNAL: add N levels to a pet (used by reward systems -- e.g. SocialRewards). Goes through levelUp so the
-- follower + inventory refresh and remote viewers see it. `key` may be a storage key OR a species id; returns
-- the levels actually added (0 if the pet isn't owned or is already maxed).
_G.petAddLevels = function(player, key, n)
	if not (player and key) then return 0 end
	local resolved = (getPetData(player, key) and key)
		or (getPetData(player, variantKey(key, true)) and variantKey(key, true))
	if not resolved then return 0 end
	local added = 0
	for _ = 1, (tonumber(n) or 0) do
		if not levelUp(player, resolved, "reward") then break end
		added = added + 1
	end
	return added
end

-- Throttle the XP-bar inventory resend (coins/flight feed XP fast). Always force on level-up.
local lastInvSync = {}
local lastXpPrint = {} -- throttle the per-tick "+XP" diagnostic for the high-frequency coins/distance sources
local function syncXP(player, force)
	local now = os.clock()
	if force or not lastInvSync[player] or (now - lastInvSync[player]) >= 2.5 then
		lastInvSync[player] = now; sendInventory(player)
	end
end
-- Award XP to the player's EQUIPPED pet ONLY. Cosmetic prestige -- NEVER affects flight/gas/coins. Auto-levels
-- (carrying the remainder) while XP fills, up to MAX (50). Diagnostics per the spec.
local function awardXP(player, amount, source)
	amount = tonumber(amount) or 0; if amount <= 0 then return end
	local petId = _G.playerEquippedPet[player]; if not petId or not ownsPet(player, petId) then return end
	local d = getPetData(player, petId); if not d then return end
	if d.level >= PET_MAX_LEVEL then return end -- maxed -> no XP needed
	d.xp = d.xp + amount
	local leveled = false
	while d.level < PET_MAX_LEVEL do
		local need = xpNeeded(d.level)
		if d.xp < need then break end
		d.xp = d.xp - need
		levelUp(player, petId, "xp:"..tostring(source)) -- force-syncs follower + GUI
		leveled = true
	end
	if d.level >= PET_MAX_LEVEL then d.xp = 0 end
	-- Diagnostic: always for level-ups + low-frequency sources (island/gas); throttle the per-0.5s coins/distance.
	local hi = (source == "coins" or source == "distance")
	local now = os.clock()
	if leveled or not hi or not lastXpPrint[player] or (now - lastXpPrint[player]) >= 2.5 then
		if hi then lastXpPrint[player] = now end
		print(string.format("[PetLvl] %s +%d XP to %s from %s -> %d/%s",
			player.Name, math.floor(amount), petId, tostring(source), math.floor(d.xp),
			(d.level >= PET_MAX_LEVEL) and "MAX" or tostring(xpNeeded(d.level))))
	end
	if not leveled then syncXP(player, false) end -- level-up already force-synced
end
-- XP SOURCE HOOKS (called from PlayerStats' coin/food/island handlers; all rate tuning lives above). --
_G.petAwardXP      = function(player, amount, source) awardXP(player, amount, source) end
_G.petOnCoins      = function(player, coins) awardXP(player, (tonumber(coins) or 0) * XP_PER_COIN, "coins") end
_G.petOnFlightTick = function(player)        awardXP(player, XP_PER_FLIGHT_TICK, "distance") end
_G.petOnGas        = function(player, gas)   awardXP(player, (tonumber(gas) or 0) * XP_PER_GAS, "gas") end
_G.petOnIsland     = function(player)        awardXP(player, XP_PER_ISLAND, "island") end

-- ===== METEOR CRATE HOOKS (pet-level reward) =====
-- The Mystery Meteor Crate grants LEVELS to a player-chosen owned pet. These funnel through the
-- same levelUp() path (re-syncs follower + GUI + remote broadcast each step), and the owned-pets
-- table they mutate is exactly what PlayerStats persists on autosave/leave -- so grants survive.

-- List the player's OWNED pets for the crate picker: { {petId, displayName, level, maxed}, ... },
-- sorted by petId for a deterministic order (server picker fallback + stable client list).
-- Every pet SPECIES id in the catalogue, sorted. The skin system needs the full list (not just owned ones) --
-- skins exist for pets you haven't unlocked yet, so /unlockall has to walk the whole roster. Sorted so the
-- output is stable rather than pairs()-order.
_G.petAllSpecies = function()
	local list = {}
	for petId in pairs(PETS) do list[#list + 1] = petId end
	table.sort(list)
	return list
end

-- The catalogue's DISPLAY data for every species, keyed by petId:
--   { displayName, islandName, questDesc, maxLevel }
-- The Pets page, the Quest page and the Collection Book all need a pet's name and realm, and none of them should
-- be re-deriving it from a hard-coded copy of this table -- PETS stays the one place a pet is described.
-- Returns a fresh table each call so a caller can't mutate the catalogue by accident.
_G.petSpeciesInfo = function()
	local out = {}
	for petId, def in pairs(PETS) do
		out[petId] = {
			displayName = def.displayName or petId,
			islandName  = def.islandName or "",
			questDesc   = def.questDesc or "",
			maxLevel    = def.maxLevel or 1,
		}
	end
	return out
end

_G.petListOwned = function(player)
	local list = {}
	local op = _G.playerOwnedPets[player]; if not op then return list end
	for petId in pairs(op) do
		if ownsPet(player, petId) then
			local def = PETS[petId]; local d = getPetData(player, petId)
			if def and d then
				local maxed = d.level >= PET_MAX_LEVEL
				local need = maxed and 0 or xpNeeded(d.level)
				local pct = maxed and 100 or (need > 0 and math.clamp((d.xp / need) * 100, 0, 100) or 0)
				table.insert(list, {
					petId = petId,
					displayName = def.displayName or petId,
					level = d.level,
					maxed = maxed,
					xp = math.floor(d.xp),
					xpNeed = need,        -- XP required for the next level (0 when maxed)
					xpPct = pct,          -- 0..100 progress to the next level (100 when maxed)
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.petId < b.petId end)
	return list
end

-- True if the player owns at least one pet that is NOT yet at the level cap.
_G.petHasUnmaxed = function(player)
	for _, p in ipairs(_G.petListOwned(player)) do
		if not p.maxed then return true end
	end
	return false
end

-- Grant N levels to a specific owned pet (crate reward). Validates ownership, clamps at
-- PET_MAX_LEVEL, and re-syncs via levelUp() per step. Returns oldLevel, newLevel, levelsAdded
-- (levelsAdded == 0 if the pet was already maxed; nil on invalid pet / not owned).
_G.petGrantLevels = function(player, petId, n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return nil end
	if not ownsPet(player, petId) then return nil end
	local d = getPetData(player, petId); if not d then return nil end
	local oldLevel = d.level
	if oldLevel >= PET_MAX_LEVEL then return oldLevel, oldLevel, 0 end
	local target = math.min(PET_MAX_LEVEL, oldLevel + n)
	while d.level < target do
		if not levelUp(player, petId, "crate") then break end
	end
	return oldLevel, d.level, (d.level - oldLevel)
end

-- SKIP: instantly FILL the current level's remaining XP -> the pet levels up once (Robux product OR test path).
local function petSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= PET_MAX_LEVEL then return false end
	d.xp = 0
	local ok = levelUp(player, petId, "skip:"..tostring(via))
	if ok then print("[PetLvl] skip "..tostring(via).." for "..petId.." -> filled to Lvl "..d.level) end
	return ok
end

-- TIER SKIP: jump the pet to the FIRST level of the NEXT tier (Common1-5 -> 6, Uncommon6-10 -> 11,
-- Rare11-15 -> 16, Epic16-20 -> 21). Returns nil at the top tier (Legendary 21-25 -> nothing to skip).
local function nextTierTarget(level)
	if level <= 5 then return 6
	elseif level <= 10 then return 11
	elseif level <= 15 then return 16
	elseif level <= 20 then return 21
	else return nil end -- Legendary (top tier) -> no skip
end
-- Apply a one-tier jump from the pet's CURRENT level (used by the test path; computed server-side so it can
-- never skip more than one tier). Re-syncs the follower + GUI like levelUp does.
local function tierSkip(player, petId, via)
	if not ownsPet(player, petId) then return false end
	local d = getPetData(player, petId); if not d then return false end
	local target = nextTierTarget(d.level)
	if not target then return false end -- already at the top tier
	d.level = target; d.xp = 0
	sendState(player); sendInventory(player)
	if _G.playerEquippedPet[player] == petId then broadcastEquip(player, "levelup") end -- remote viewers see the tier-skip look
	print("[PetLvl] tier-skip "..tostring(via).." for "..petId.." -> Lvl "..d.level)
	return true
end

-- \xE2\x9A\xA0 TEST COMMAND /newlevel - EXTERNAL entry point for the same one-tier jump. REMOVE BEFORE LAUNCH.
-- DevCommands calls this to push the player's EQUIPPED pet (or a named one) into the next tier, so the tier-up
-- sound + the new look can be checked in seconds instead of grinding five levels of XP. It goes through the
-- SAME tierSkip the Robux/test path uses -- there is no separate dev path that could behave differently -- so
-- the client sees an ordinary inventory push and reacts exactly as it would to a real tier-up.
-- Returns newLevel, tierName (nil if there is no pet, it isn't owned, or it's already at the top tier).
_G.petTierSkip = function(player, petId)
	if not player then return nil end
	petId = petId or _G.playerEquippedPet[player]
	if not petId then return nil end
	if not tierSkip(player, petId, "dev:/newlevel") then return nil end
	local d = getPetData(player, petId)
	if not d then return nil end
	-- The client's ladder (PetFollow petTier): Baby 1-5, Kid 6-10, Teen 11-15, Adult 16-20, Elder 21+.
	local tier = (d.level <= 5 and "Baby") or (d.level <= 10 and "Kid") or (d.level <= 15 and "Teen")
		or (d.level <= 20 and "Adult") or "Elder"
	return d.level, tier
end

-- \xE2\x9A\xA0 TEST COMMAND /allpets - grants all pets to test accounts. REMOVE BEFORE LAUNCH.
-- Grants EVERY pet in the catalog to the player using the SAME ownership structure a normal claim writes
-- ({level=1,height=0,time=0}), marks each quest discovered, auto-equips one if none is equipped, then
-- re-sends state + inventory so all pets show OWNED + equippable immediately (no rejoin). Gated by the
-- CALLER (PlayerStats /allpets handler, test accounts only). Returns how many NEW pets were granted.
_G.petsGrantAll = function(player)
	if not player then return 0 end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	local granted = 0
	for petId in pairs(PETS) do
		if not ownsPet(player, petId) then
			_G.playerOwnedPets[player][petId] = { level = 1, height = 0, time = 0 } -- same table PetClaimEvent writes
			granted = granted + 1
		end
		_G.playerDiscoveredQuests[player][petId] = true -- so the quests panel shows it as done too
	end
	if not _G.playerEquippedPet[player] then for petId in pairs(PETS) do _G.playerEquippedPet[player] = petId; break end end
	sendState(player)     -- spawns the equipped follower + flags everything owned
	sendInventory(player) -- all pets now appear in the inventory, equippable
	broadcastEquip(player, "equip") -- let other clients render the (test-)equipped pet
	return granted
end
-- \xE2\x9A\xA0 TEST COMMAND /rarepets - grants every pet as its RARE variant (pre-maxed + rare flag) so all 5 rare
-- looks can be seen without gambling the odds. REMOVE BEFORE LAUNCH.
_G.petsGrantRare = function(player)
	if not player then return 0 end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	local granted = 0
	for petId in pairs(PETS) do
		_G.playerOwnedPets[player][variantKey(petId, true)] = { level = PET_MAX_LEVEL, xp = 0, height = 0, time = 0, rare = true } -- RARE + pre-maxed (own rare slot)
		_G.playerDiscoveredQuests[player][petId] = true
		granted = granted + 1
		print(string.format("[PetRare] rare %s displayed pre-maxed + rare effect %s", petId, RARE_NAMES[petId] or petId))
	end
	if not _G.playerEquippedPet[player] then for petId in pairs(PETS) do _G.playerEquippedPet[player] = variantKey(petId, true); break end end
	sendState(player); sendInventory(player)
	broadcastEquip(player, "rare") -- let other clients render the (test-)equipped rare pet
	return granted
end

-- ============================================================================================================
-- COLLECTION MILESTONES -- rewards for FILLING the Pet Hub's index. No coins anywhere: the rewards are TITLES
-- (a floating nametag every other player can see -- see TitleTags.client.luau) and, at 10/10, the SECRET PIZZA
-- DRAGON, which exists nowhere else in the game.
--
-- THE COUNTING RULE, and it matters: the Pizza Dragon is questType="collection", and BOTH counts below skip it.
-- It is the prize for completing the set, so it cannot be part of the set -- if it counted, "collect all" would
-- require owning the thing you get FOR collecting all, which is unwinnable. So the target is 10, not 11, and a
-- player who finishes shows 10/10 while owning 11 pets.
-- ============================================================================================================
-- TITLES: a pure brag reward. Stored on the player and mirrored to the "Title" ATTRIBUTE, which Roblox replicates
-- to every client automatically -- TitleTags.client.luau just watches that attribute, so no remotes are needed and
-- late joiners see it for free. Titles never affect flight, gas, coins or any stat. Higher milestones overwrite
-- lower ones (you wear your BEST title), which is why COLLECTION_MILESTONES is walked in ascending order.
_G.grantTitle = function(player, title)
	if not (player and type(title) == "string" and title ~= "") then return false end
	_G.playerTitle[player] = title
	player:SetAttribute("Title", title) -- replicates -> every client's TitleTags renders it above this player
	print("[PetTitle] " .. player.Name .. " earned the title '" .. title .. "'")
	return true
end

-- Award any milestone the player has reached but not yet been paid for. Safe to call on EVERY ownership change
-- (claim / seasonal / starter / trade / join): already-claimed tiers are skipped, so it can never double-pay.
local function checkCollectionMilestones(player)
	if not player or not player.Parent then return end
	_G.playerPetMilestones[player] = _G.playerPetMilestones[player] or {}
	local claimed = _G.playerPetMilestones[player]
	local have, target = collectedCount(player), collectableCount()
	local awarded = false
	for _, ms in ipairs(COLLECTION_MILESTONES) do -- ascending, so the BEST title lands last and wins
		local mkey = tostring(ms.need) -- STRING key: DataStore JSON round-trips string keys reliably, numbers don't
		if have >= ms.need and not claimed[mkey] then
			claimed[mkey] = true
			if ms.kind == "title" then
				_G.grantTitle(player, ms.id)
			elseif ms.kind == "pet" then
				-- grant the secret pet exactly like any normal claim, so it persists, levels, and is equippable
				-- through the ordinary pet path. It starts at Baby like EVERY granted pet -- age is grown from
				-- flight and playtime, never handed over at grant time. (See the quest claim for the full why.)
				_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
				if not ownsSpecies(player, ms.id) then
					_G.playerOwnedPets[player][ms.id] = { level = 1, xp = 0, height = 0, time = 0 }
					_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
					_G.playerDiscoveredQuests[player][ms.id] = true
					print(string.format("[PetMilestone] %s COMPLETED THE COLLECTION (%d/%d) -> secret %s at Baby (Lv 1)",
						player.Name, have, target, ms.id))
				end
			end
			awarded = true
			print(string.format("[PetMilestone] %s reached %d/%d pets -> %s", player.Name, have, target, ms.name))
			pcall(function()
				PetMilestoneEvent:FireClient(player, {
					need = ms.need, have = have, target = target,
					kind = ms.kind, id = ms.id, name = ms.name, desc = ms.desc,
				})
			end)
		end
	end
	if awarded then
		sendState(player); sendInventory(player) -- the new pet/title shows up immediately, no rejoin
		if _G.savePlayerData then pcall(_G.savePlayerData, player, "petmilestone") end
	end
end

-- \xE2\x9A\xA0 TEST COMMAND /10pets - instantly collect all 10 COLLECTABLE pets so the collection rewards can be tested
-- end to end. REMOVE BEFORE LAUNCH.
-- It deliberately does NOT hand over the Pizza Dragon: it grants the 10 pets that COUNT and then runs the normal
-- milestone check, so every title fires in order and the secret pet is awarded by the real 10/10 code path -- which
-- is the thing worth testing. (Contrast /allpets, which force-grants every entry in the catalog, dragon included,
-- and therefore proves nothing about the milestone logic.) Gated by the CALLER to test accounts.
_G.petsGrantCollection = function(player)
	if not player then return 0 end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	local granted = 0
	for petId, def in pairs(PETS) do
		if def.questType ~= "collection" and not ownsSpecies(player, petId) then
			_G.playerOwnedPets[player][petId] = { level = 1, xp = 0, height = 0, time = 0 }
			_G.playerDiscoveredQuests[player][petId] = true
			granted = granted + 1
		end
	end
	if not _G.playerEquippedPet[player] then
		for petId in pairs(PETS) do _G.playerEquippedPet[player] = petId; break end
	end
	sendState(player); sendInventory(player)
	broadcastEquip(player, "equip")
	checkCollectionMilestones(player) -- <- the real path: fires every title, then grants the secret Pizza Dragon
	print(string.format("[TEST] /10pets granted %d pet(s) to %s -> %d/%d collected",
		granted, player.Name, collectedCount(player), collectableCount()))
	return granted
end

-- ===== STARTER PET ENTITLEMENT (retention): grant the free Bean Buddy. PlayerStats calls this ONCE, only for a
-- player whose save is brand-new, right after petsApplyOnJoin -- so a first-time player has a pet following them
-- within seconds of spawning instead of having to earn one. Uses the SAME ownership structure as a normal claim,
-- so it persists (PlayerStats saved.ownedPets), shows OWNED in the inventory, levels, and is equippable/tradeable
-- through the normal pet path. Idempotent: a player who already owns it gets nothing. Fires StarterPetEvent so the
-- client can play the welcome card. Returns true if a pet was actually granted. =====
_G.grantStarterPet = function(player)
	if not player then return false end
	local petId = "BeanBuddy"
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	if ownsSpecies(player, petId) then return false end -- already has it -> never re-grant
	_G.playerOwnedPets[player][petId] = { level = 1, xp = 0, height = 0, time = 0 } -- same table a normal claim writes
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][petId] = true
	-- AUTO-EQUIP: a brand-new player has nothing equipped, so this is what actually puts a pet on screen for them.
	-- If they somehow already have something equipped (shouldn't happen on a fresh save), leave their choice alone.
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = petId end
	sendState(player); sendInventory(player) -- owned + equipped + following, immediately (no rejoin)
	if _G.playerEquippedPet[player] == petId then broadcastEquip(player, "equip") end -- other players see it too
	pcall(function() StarterPetEvent:FireClient(player, petId, PETS[petId].displayName) end) -- welcome card
	print("[Pet] STARTER "..petId.." granted to "..player.Name.." (free first-join gift, auto-equipped)")
	-- RE-PUSH. The grant lands ~0.5s BEFORE PetFollow connects its OnClientEvent handlers, so the sendState
	-- above is fired into a client with no listener. Roblox queues an unheard remote only briefly and then
	-- DISCARDS it -- which is why the starter pet renders on a fast join and silently doesn't on a slow one.
	-- Repeat the push over the next ~9s; whichever copy lands after the listeners exist is the one that works.
	-- sendState is idempotent (it just describes current ownership), so extra copies cost nothing.
	task.spawn(function()
		for _ = 1, 4 do
			task.wait(3)
			if not player.Parent then return end -- left
			sendState(player); sendInventory(player)
		end
	end)
	checkCollectionMilestones(player) -- the starter counts as 1/10 toward the collection
	return true
end

-- ===== SEASONAL PET ENTITLEMENT: grant ONE seasonal pet for a season (called by the Community Garden harvest and by
-- the /grantpet test command). Adds it with the SAME ownership structure as a normal claim, so it persists (via
-- PlayerStats saved.ownedPets), shows OWNED in the inventory, and is equippable through the normal pet path. =====
local SEASON_TO_PET = { Summer = "SunflowerBee", Autumn = "MapleFox", Winter = "FrostPenguin", Spring = "BlossomBunny" }
_G.grantSeasonalPet = function(player, season)
	if not (player and season) then return false end
	season = tostring(season)
	local key = season:sub(1, 1):upper() .. season:sub(2):lower() -- accept "summer"/"Summer"/"SUMMER"
	local petId = SEASON_TO_PET[key]
	if not petId then warn("[Pet] grantSeasonalPet: unknown season '"..season.."'"); return false end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	if ownsSpecies(player, petId) then return true end -- already owned -> nothing to do
	-- A seasonal harvest pet starts at Baby like every granted pet: age comes from flight time and playtime,
	-- not from the moment of the grant. The garden gives you the SPECIES; you grow it yourself.
	_G.playerOwnedPets[player][petId] = { level = 1, xp = 0, height = 0, time = 0 } -- same table a normal claim writes (persists)
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][petId] = true
	sendState(player); sendInventory(player) -- now shows OWNED + equippable immediately (no rejoin)
	print(string.format("[Pet] seasonal %s granted to %s (%s reward) at Baby (Lv 1)",
		petId, player.Name, key))
	checkCollectionMilestones(player) -- a garden pet counts toward the collection like any other
	return true
end

-- ===== REBIRTH PET ENTITLEMENT: granted by RebirthSystem when a rebirth milestone is reached. Same ownership
-- path as any hatch, so it persists (ownedPets), shows OWNED in the pet HUD, and equips/trades normally. =====
-- ===== GRANT A PET AT A SPECIFIC RARITY -- the crate's way in ================================================
-- The ONLY entry point that can hand out a pet above Common, which is what makes "rarer pets come from crate
-- spins" true by construction rather than by convention: every other grant path in this file writes a bare
-- (Common) key and none of them take a band.
--
-- Unlike the quest/seasonal/rebirth grants, this does NOT bail when the player already owns the species. That
-- is the entire point -- a repeat pull is a DUPLICATE, and duplicates are the fuel fusion runs on. It stacks
-- onto the matching (species, rarity) slot and leaves any other band the player owns untouched, so a Rare
-- Broccoli Bunny never overwrites the Uncommon one being saved up for a fuse.
--
-- Age is not negotiable here either: a crate pet arrives at Baby like everything else. The crate sells you
-- RARITY, never a head start on growth.
-- Returns ok, newCount.
_G.grantPetAtRarity = function(player, petId, rarity)
	if not (player and petId and PETS[petId]) then return false, 0 end
	local band = PetRarity.normalise(rarity) -- unknown/forged band -> Common, never a junk key
	local key  = variantKey(petId, band)
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	local op = _G.playerOwnedPets[player]

	local existing = op[key]
	local newCount
	if type(existing) == "table" then
		newCount = (tonumber(existing.count) or 1) + 1
		existing.count = newCount
	else
		newCount = 1
		op[key] = { level = 1, xp = 0, height = 0, time = 0, count = 1 }
	end

	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][petId] = true
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = key end -- auto-equip a first pet

	print(string.format("[PetCrate] %s pulled %s %s (x%d)", player.Name, band, petId, newCount))
	sendState(player); sendInventory(player)
	broadcastEquip(player, _G.playerEquippedPet[player] and "equip" or "unequip")
	checkCollectionMilestones(player) -- a crate pet counts toward the collection like any other
	return true, newCount
end

_G.grantRebirthPet = function(player, petId)
	if not (player and petId and PETS[petId]) then return false end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	if ownsSpecies(player, petId) then return true end -- already owned -> nothing to do
	-- Baby, like every granted pet -- age is grown from flight and playtime, never granted.
	_G.playerOwnedPets[player][petId] = { level = 1, xp = 0, height = 0, time = 0 }
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][petId] = true
	sendState(player); sendInventory(player)
	if _G.savePlayerData then pcall(_G.savePlayerData, player, "rebirthpet") end
	print("[Pet] REBIRTH pet " .. petId .. " granted to " .. player.Name)
	return true
end

-- ===== MARKERS: locate + hide the raw marker parts (kept in place so clients can read positions) =====
-- The islands are NOT always named "Island_2_BroccoliBluff" -- in this place they can be plain "island2".
-- Try the literal prefix first, then a NORMALIZED prefix ("island2", case/underscore-insensitive) with a
-- digit guard so "island1" can never match "island14". A miss here isn't fatal (markers still resolve at
-- Workspace level), it just costs the island-first lookup + the position diagnostic.
local function findIsland(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	local want = (tostring(prefix):lower():gsub("[%s_%-%.]", ""))
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") then
			local n = (m.Name:lower():gsub("[%s_%-%.]", ""))
			if n:sub(1, #want) == want and not tonumber(n:sub(#want + 1, #want + 1)) then
				print("[Pet][DIAG] island prefix '"..prefix.."' matched Workspace model '"..m.Name.."' (normalized)")
				return m
			end
		end
	end
	return nil
end
local function hideMarker(part)
	if part and part:IsA("BasePart") then
		-- ANCHOR FIRST. Clearing CanCollide on an UNANCHORED part is a licence to fall forever -- it loses the
		-- floor in the same breath. The markers in this place ship unanchored, so hiding one used to launch it
		-- into an endless drop; anything that later re-read its position got a number from halfway to the void.
		part.Anchored = true
		part.Transparency = 1; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		return true
	end
	return false
end
-- Resolve a marker by EXACT name (case-sensitive): (a) inside the island model (recursive), then
-- (b) Workspace top level, then (c) anywhere in Workspace -- so markers work whether placed inside the
-- island OR at Workspace root (the user's are at Workspace top level).
local function resolveMarker(island, name)
	local p = island and island:FindFirstChild(name, true)
	if not p then p = Workspace:FindFirstChild(name) end        -- top-level Workspace child
	if not p then p = Workspace:FindFirstChild(name, true) end  -- anywhere in Workspace (recursive)
	return p
end
-- Get a marker's WORLD POSITION whether it's a single BasePart OR a built MODEL (e.g. the user's
-- PopcornProjector is a Model, not one Part -- hideMarker() alone would skip it). Hides it (all of the
-- model's BaseParts) so a client-rebuilt prop doesn't double with the placed one, and returns the position.
local function captureMarkerPos(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		hideMarker(inst)
		return inst.Position
	elseif inst:IsA("Model") then
		local pos
		pcall(function() pos = inst:GetPivot().Position end)                 -- pivot works even with no PrimaryPart
		if not pos and inst.PrimaryPart then pos = inst.PrimaryPart.Position end
		if not pos then pcall(function() local cf = inst:GetBoundingBox(); pos = cf.Position end) end -- bbox centre fallback
		for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then hideMarker(d) end end
		return pos
	end
	return nil -- some other instance type (Folder/Attachment/etc) -- not positionable as a marker
end
-- LOOSE marker resolve. resolveMarker() is EXACT + case-sensitive, so one marker named "Broccoli Piece 3",
-- "broccolipiece3" or "BroccoliPiece_3" (or one that got GROUPED into a Model) silently goes missing and that
-- piece never exists in the world -- an uncompletable quest. This falls back to a normalized-name match
-- (lowercased, spaces/underscores/dashes/dots stripped) over the island, then Workspace, and reports HOW it
-- matched so the log names the real instance to rename.
local function normName(s) return (tostring(s):lower():gsub("[%s_%-%.]", "")) end
local function resolveMarkerLoose(island, name)
	local p = resolveMarker(island, name)
	if p then return p, "exact" end
	local want = normName(name)
	local function scan(list)
		for _, m in ipairs(list) do
			if (m:IsA("BasePart") or m:IsA("Model")) and normName(m.Name) == want then return m end
		end
		return nil
	end
	local hit
	pcall(function()
		if island then hit = scan(island:GetDescendants()) end
		if not hit then hit = scan(Workspace:GetChildren()) end
		if not hit then hit = scan(Workspace:GetDescendants()) end
	end)
	if hit then return hit, "fuzzy" end
	return nil, nil
end
local function posStr(p) return p and string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "nil" end
-- Ground under a point (for the missing-marker fallback below): drop a ray from well above it.
local function groundAt(p)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local hit = Workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
	return hit and (hit.Position + Vector3.new(0, 1.2, 0)) or nil
end
task.spawn(function()
	-- TIMING (critical): PlayerStats REPOSITIONS the islands at runtime (e.g. Island_2 -> Y=790). The
	-- markers are now CHILDREN of the island model, so they MOVE WITH IT. We must capture positions
	-- AFTER that move or we'd record the pre-move coords (the old Y=-18 bug). PlayerStats sets
	-- workspace:SetAttribute("StandsReady", true) once islands are positioned + stands are set up
	-- ("STANDS SETUP COMPLETE"), so we WAIT for that flag before reading any marker.
	-- ===== ANCHOR EVERY MARKER *BEFORE* THE WAIT (this is why a piece could fail to spawn) =====
	-- The quest markers ship from Studio UNANCHORED with CanCollide on. PlayerStats then lifts island 2 from
	-- Y=-18 to Y~790 at runtime; the markers ride the island up and, being unanchored, immediately start
	-- falling. We do not read their positions until StandsReady, up to 60 SECONDS later -- so any marker that
	-- was over a gap, an edge, or a non-collidable mesh has long since dropped away, and the coordinate we
	-- capture is wherever it fell. The client then dutifully builds that piece thousands of studs under the
	-- island, which on screen is simply "that broccoli never spawned" -- and it hits whichever piece happens
	-- to sit over a hole, which is why one specific piece goes missing while its neighbours are fine.
	--
	-- Anchoring costs nothing and cannot move anything: Model:PivotTo carries anchored children with it, so the
	-- island reposition still works exactly as before -- the parts just hold their place on it instead of
	-- sliding off. Done here, before the wait, so there is no window to fall in.
	do
		local wanted = {} -- normalised marker name -> true, across every pet
		for _, d in pairs(PETS) do
			for _, n in ipairs(d.pieceMarkers or {}) do wanted[normName(n)] = true end
			if d.eggMarker then wanted[normName(d.eggMarker)] = true end
			for _, n in pairs(d.extraMarkers or {}) do wanted[normName(n)] = true end
		end
		local anchored = 0
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if wanted[normName(inst.Name)] then
				if inst:IsA("BasePart") then
					if not inst.Anchored then inst.Anchored = true; anchored = anchored + 1 end
				elseif inst:IsA("Model") then
					for _, p in ipairs(inst:GetDescendants()) do
						if p:IsA("BasePart") and not p.Anchored then p.Anchored = true; anchored = anchored + 1 end
					end
				end
			end
		end
		print("[Pet] anchored "..anchored.." unanchored quest marker part(s) before the island move -- they can no longer fall away from their island")
	end

	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 60 do task.wait(0.5); waited = waited + 0.5 end
	if Workspace:GetAttribute("StandsReady") then
		print("[Pet][DIAG] StandsReady=true after "..waited.."s -- islands are positioned; capturing marker positions")
	else
		warn("[Pet][DIAG] StandsReady never set after "..waited.."s -- capturing anyway (positions may be pre-move)")
	end
	-- Give the positioned island a moment, then find + hide each pet's markers and log diagnostics.
	for petId, def in pairs(PETS) do
		if not def.islandPrefix then continue end -- seasonal/grant-only pet: no island markers to scan
		local island
		for _ = 1, 30 do island = findIsland(def.islandPrefix); if island then break end; task.wait(1) end
		if not island then
			print("[Pet] island '"..def.islandPrefix.."' not found -- resolving markers at Workspace top level instead")
		else
			print(string.format("[Pet][DIAG] island 2 positioned at Y=%.0f, capturing marker positions now", island:GetPivot().Position.Y))
		end
		-- Resolve each marker ISLAND-FIRST (they're grouped inside the island now), Workspace as backup,
		-- CAPTURE its post-positioning world position (the client builds from these coords), and hide it.
		local foundN = 0
		local fallbackN = 0 -- how many of foundN are FALLBACK guesses rather than real placed markers
		local piecePos = {}
		local missingPieces = {}
		-- HOW FAR BELOW THE ISLAND A MARKER MAY SIT before we treat it as FALLEN rather than placed. Measured
		-- from the island's bounding-box FLOOR, not its pivot -- a pivot can sit anywhere inside the model, the
		-- floor is always the floor. 60 studs is well under any island's spacing and well over any legitimate
		-- dip in the terrain. This catches markers that already fell in a place saved while they were dropping:
		-- anchoring above stops NEW falls, but a coordinate that is already wrong has to be rejected here.
		local islandFloorY
		if island then
			pcall(function()
				local cf, size = island:GetBoundingBox()
				islandFloorY = cf.Position.Y - size.Y * 0.5
			end)
		end
		local function fallenAway(pos)
			return islandFloorY ~= nil and pos.Y < (islandFloorY - 60)
		end

		for i, name in ipairs(def.pieceMarkers) do
			local inst, how = resolveMarkerLoose(island, name)
			local pos = captureMarkerPos(inst) -- Part OR Model (hideMarker alone silently skipped grouped markers)
			if pos and fallenAway(pos) then
				warn(string.format("[Pet] piece marker '%s' resolved at %s -- that is %.0f studs BELOW the island floor,"
					.." so it fell off before we read it. Ignoring the coordinate and placing this piece on the island instead."
					.." (Anchor '%s' in Studio to fix it permanently.)", name, posStr(pos), islandFloorY - pos.Y, name))
				pos = nil
			end
			if pos then
				foundN = foundN + 1; piecePos[i] = pos
				if how == "fuzzy" then
					warn("[Pet] piece marker '"..name.."' matched LOOSELY to '"..inst.Name.."' ("..inst.ClassName..") at "
						..inst:GetFullName().." -- rename it to '"..name.."' exactly")
				end
			else
				missingPieces[#missingPieces+1] = { i = i, name = name }
				-- only claim it's MISSING when we genuinely couldn't find it; a marker rejected for having fallen
				-- was found, and has already said so above in a way that names the real fix.
				if not inst then warn("[Pet] piece marker '"..name.."' MISSING (not in island OR Workspace)") end
			end
		end
		-- RETRY for late-parented/late-moved markers (something added to the island after StandsReady), then
		-- DUMP every candidate so a typo'd name is visible in the log.
		if #missingPieces > 0 then
			task.wait(5)
			for idx = #missingPieces, 1, -1 do
				local m = missingPieces[idx]
				local inst = resolveMarkerLoose(island, m.name)
				local pos = captureMarkerPos(inst)
				if pos and fallenAway(pos) then pos = nil end -- same rejection as above: a fallen marker is not a retry win
				if pos then
					piecePos[m.i] = pos; foundN = foundN + 1; table.remove(missingPieces, idx)
					print("[Pet] piece marker '"..m.name.."' appeared on RETRY at "..posStr(pos))
				end
			end
			if #missingPieces > 0 then
				local key = normName(def.pieceMarkers[1]):gsub("%d+$", "") -- e.g. "broccolipiece"
				local function dumpLike(list, where)
					for _, m in ipairs(list) do
						if (m:IsA("BasePart") or m:IsA("Model")) and normName(m.Name):find(key, 1, true) then
							print("[Pet][DIAG] piece-like found: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
						end
					end
				end
				pcall(function() if island then dumpLike(island:GetDescendants(), "island") end end)
				pcall(function() dumpLike(Workspace:GetChildren(), "Workspace top") end)
			end
		end
		local eggPos = nil
		if def.eggMarker then -- fishing has NO egg marker (the egg appears where caught) -> skip the egg lookup entirely
		local egg = resolveMarker(island, def.eggMarker)
		if hideMarker(egg) then
			eggPos = egg.Position
		else
			warn("[Pet] "..def.eggMarker.." MISSING (not in island OR Workspace)")
			-- DIAGNOSTIC DUMP: the marker wasn't found by exact name -> scan the island (recursive) + Workspace
			-- top level for anything chest/coconut/crab-like so we can see the real name/location to fix it.
			local function scanList(list, where)
				for _, m in ipairs(list) do
					local n = m.Name:lower()
					if n:find("chest") or n:find("coconut") or n:find("crab") then
						print("[Pet][DIAG] chest-like found: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
					end
				end
			end
			pcall(function() if island then scanList(island:GetDescendants(), "island") end end)
			pcall(function() scanList(Workspace:GetChildren(), "Workspace top") end)
		end
		end -- close: if def.eggMarker
		-- LAST RESORT for a piece marker that still can't be found: place it near the ones that DID resolve
		-- (ring around the anchor, raycast down onto the island surface) so the count can still reach N/N and
		-- the quest is never dead. Loud warn -- this is a band-aid, the marker should still be fixed/renamed.
		for _, m in ipairs(missingPieces) do
			local anchor
			for j = 1, #def.pieceMarkers do if piecePos[j] then anchor = piecePos[j]; break end end
			-- ISLAND PIVOT AS THE FINAL ANCHOR. Preferring a resolved piece, then the egg, is right -- but when
			-- NEITHER exists (every marker on the island renamed or missing) this gave up and the quest had no
			-- collectibles at all. The island itself is always locatable and always the right neighbourhood, so
			-- ring the pieces around its pivot rather than shipping an island with nothing on it.
			anchor = anchor or eggPos
			if not anchor and island then
				pcall(function() anchor = island:GetPivot().Position end)
				if anchor then
					warn("[Pet] "..petId..": no piece or egg marker resolved -- anchoring the fallback ring on the ISLAND PIVOT "
						..posStr(anchor)..". Place Parts named '"..table.concat(def.pieceMarkers, "', '").."' on the island to fix this properly.")
				end
			end
			if anchor then
				local a = (m.i - 1) * (2 * math.pi / math.max(1, #def.pieceMarkers)) + 0.7
				local guess = anchor + Vector3.new(math.cos(a) * 26, 0, math.sin(a) * 26)
				local pos = groundAt(guess) or (guess + Vector3.new(0, 2, 0))
				piecePos[m.i] = pos
				foundN = foundN + 1 -- it EXISTS in the world now, so the "markers found: N/3" line must count it;
				fallbackN = fallbackN + 1 -- ...and this says how many of those N are guesses rather than placed markers
				warn("[Pet] piece marker '"..m.name.."' NOT FOUND -- using a FALLBACK spot at "..posStr(pos)
					.." so the quest stays completable. Add/rename a Part called '"..m.name.."' on the island to fix it.")
			else
				warn("[Pet] piece marker '"..m.name.."' NOT FOUND and no anchor to fall back to -- that piece will not exist")
			end
		end
		-- EXTRA (non-collectible) markers -- fixed props like the projector + screen. Capture positions the same
		-- way (resolve island-first then Workspace; hide the raw marker; the client rebuilds the visuals). These
		-- may be MODELS (the user's PopcornProjector is a built Model), so use captureMarkerPos (Part OR Model).
		local extraPos, extraFound, extraInst, extraSize = {}, {}, {}, {}
		if def.extraMarkers then
			-- DIAGNOSTIC DUMP (film-reels): list every projector/popcorn-like instance (name + class + full path)
			-- so the projector's real name + whether it's a Model is visible even if the exact-name lookup misses.
			if def.questType == "film-reels" then
				local function dumpLike(list, where)
					for _, m in ipairs(list) do
						local n = m.Name:lower()
						if n:find("projector") or n:find("popcorn") then
							print("[Pet][DIAG] projector-like found: '"..m.Name.."' ("..m.ClassName..") at "..m:GetFullName().." ["..where.."]")
						end
					end
				end
				pcall(function() if island then dumpLike(island:GetDescendants(), "island") end end)
				pcall(function() dumpLike(Workspace:GetChildren(), "Workspace top") end)
			end
			for key, name in pairs(def.extraMarkers) do
				local inst = resolveMarker(island, name)
				local useExisting = def.extraExisting and def.extraExisting[key]
				local pos
				if inst and useExisting then
					-- KEEP the placed instance visible + send its reference (client renders directly on it)
					if inst:IsA("BasePart") then pos = inst.Position
					elseif inst:IsA("Model") then pcall(function() pos = inst:GetPivot().Position end) end
					if pos then extraInst[key] = inst end
				elseif inst then
					pos = captureMarkerPos(inst) -- hide it; the client rebuilds a prop at this position
				end
				if pos then
					extraPos[key] = pos; extraFound[key] = true
					-- also capture the marker's bounding-box SIZE (e.g. the ButterLake union) for client proximity checks
					if inst:IsA("BasePart") then extraSize[key] = inst.Size
					else pcall(function() local _, sz = inst:GetBoundingBox(); extraSize[key] = sz end) end
					print(string.format("[Pet][DIAG] extra marker '%s' resolved to '%s' (%s)%s at (%.0f,%.0f,%.0f)",
						key, inst and inst.Name or "?", inst and inst.ClassName or "?",
						useExisting and " [kept visible, sent to client]" or "", pos.X, pos.Y, pos.Z))
				else
					warn("[Pet] extra marker '"..name.."' ("..key..") MISSING (not found as a Part OR Model in island/Workspace)")
				end
			end
		end
		-- generic across pets: e.g. "[Pet] CoconutCrab markers found: 7/7, chest found: yes"
		if def.questType == "fishing" then
			print("[Pet] "..petId.." markers found: butterlake="..(extraFound.butterlake and "yes" or "no")
				.." (union), rodbarrel="..(extraFound.rodbarrel and "yes" or "no"))
		elseif def.questType == "dig" then
			local digN = 0; for _, k in ipairs({ "dig1","dig2","dig3","dig4","dig5" }) do if extraFound[k] then digN = digN + 1 end end
			print("[Pet] "..petId.." markers found: shovel="..(extraFound.shovel and "yes" or "no")
				..", digspots="..digN.."/5, buriedegg="..(extraFound.buriedegg and "yes" or "no"))
		elseif def.questType == "film-reels" then
			print("[Pet] "..petId.." markers found: "..foundN.."/"..#def.pieceMarkers
				..", projector/screen/eggspot found: "..(extraFound.projector and "yes" or "no")
				.."/"..(extraFound.screen and "yes" or "no").."/"..(eggPos and "yes" or "no"))
		else
			print("[Pet] "..petId.." markers found: "..foundN.."/"..#def.pieceMarkers
				..(fallbackN > 0 and (" ("..fallbackN.." on FALLBACK spots -- markers missing/renamed)") or "")..", "
				..(def.questType == "crack" and "chest" or "egg").." found: "..(eggPos and "yes" or "no"))
		end
		markerPositions[petId] = { pieces = piecePos, egg = eggPos, extra = extraPos, extraInst = extraInst, extraSize = extraSize } -- ready for PetGetMarkers to hand to clients
	end
end)

-- ===== POSITIONS RF: the client asks for a pet's marker coordinates (it never searches Workspace) =====
local function vstr(p) return p and string.format("(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or "nil" end
PetGetMarkers.OnServerInvoke = function(player, petId)
	petId = petId or "BroccoliPet"
	local def = PETS[petId]
	if not def then
		warn("[Pet][DIAG] PetGetMarkers: unknown petId '"..tostring(petId).."' requested by "..player.Name)
		return nil
	end
	-- The marker scan runs at startup and may not be done yet when the client asks; wait for it.
	local waited = 0
	while not markerPositions[petId] and waited < 90 do task.wait(0.5); waited = waited + 0.5 end -- 90s: covers the StandsReady wait + island find before positions are captured
	local mp = markerPositions[petId]
	if not mp then
		warn("[Pet][DIAG] PetGetMarkers: positions for "..petId.." NOT READY for "..player.Name.." -- markers were never found server-side")
		return nil
	end
	local pp = mp.pieces or {}
	local n = 0; for _ in pairs(pp) do n = n + 1 end
	local label = (PETS[petId].questType == "crack") and "coconut" or "marker"
	print("[Pet] sending "..label.." positions to "..player.Name.." ("..n.." pieces, "..(PETS[petId].questType == "crack" and "chest" or "egg").."="..vstr(mp.egg)..")")
	return mp
end

-- ===== HANDSHAKE: PlayerStats calls this once the player's saved data (ownedPets) is loaded =====
_G.petsApplyOnJoin = function(player)
	piecesFound[player] = piecesFound[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	-- MIGRATION (one-time per save): legacy saves stored a rare under its PLAIN species key. Re-key it to the rare
	-- slot (petId#R) so a normal of the same species can now coexist as a separate entry. Keeps the equip pointer valid.
	local op = _G.playerOwnedPets[player]
	if op then
		for petId in pairs(PETS) do
			local v = op[petId]
			if type(v) == "table" and v.rare and op[variantKey(petId, true)] == nil then
				op[variantKey(petId, true)] = v; op[petId] = nil
				if _G.playerEquippedPet[player] == petId then _G.playerEquippedPet[player] = variantKey(petId, true) end
			end
		end
		for skey in pairs(op) do getPetData(player, skey) end -- normalize legacy `true`/missing level/xp/count on every stack
	end
	-- owning a pet implies its quest was discovered (so the quests panel shows Done even on a fresh session).
	for petId in pairs(PETS) do
		if ownsSpecies(player, petId) then _G.playerDiscoveredQuests[player][petId] = true end
	end
	-- default-equip an owned stack if none is equipped (or the saved one is no longer valid) so a pet still follows
	if not (_G.playerEquippedPet[player] and ownsPet(player, _G.playerEquippedPet[player])) then
		_G.playerEquippedPet[player] = nil
		for petId in pairs(PETS) do local ks = ownedKeysOf(player, petId); if ks[1] then _G.playerEquippedPet[player] = ks[1]; break end end
	end
	sendState(player)     -- tells the client what they own + which is equipped (spawns that follower)
	sendInventory(player) -- fills the Pet Inventory GUI
	for petId in pairs(PETS) do
		for _, skey in ipairs(ownedKeysOf(player, petId)) do print("[Pet] "..skey.." owned by "..player.Name.." (equipped="..tostring(_G.playerEquippedPet[player] == skey)..")") end
	end
	broadcastEquip(player, "join")  -- tell everyone what this (now-loaded) player has equipped
	sendAllEquipsTo(player)         -- and tell THIS player what everyone already here has equipped (late-join catch-up)
	-- CATCH-UP: re-run the milestone check on join. This pays out anyone who crossed a threshold before the system
	-- existed (their pets are already owned, so they'll be granted their titles + the secret pet on next login),
	-- and re-applies the "Title" attribute, which does NOT survive a rejoin on its own.
	if _G.playerTitle[player] then player:SetAttribute("Title", _G.playerTitle[player]) end
	checkCollectionMilestones(player)
end

-- ADDITIVE lifecycle for cross-player pets: re-broadcast a player's pet when their character (re)spawns so
-- remote clients re-attach the follower to the new body. (RemotePets also reads the live character each frame,
-- so this is belt-and-suspenders.) Never touches the owner's own PetFollow pet.
local function hookRemotePetLifecycle(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the new HumanoidRootPart exist before remote clients re-target
		broadcastEquip(player, "respawn")
	end)
end
Players.PlayerAdded:Connect(hookRemotePetLifecycle)
for _, p in ipairs(Players:GetPlayers()) do hookRemotePetLifecycle(p) end

-- ===== REMOTE HANDLERS =====
PetRequestStateEvent.OnServerEvent:Connect(function(player)
	-- Client handshake (fires when its pet UI is ready). Respond with whatever we know so far; if the
	-- save hasn't loaded yet, ownedPets is nil -> empty, and petsApplyOnJoin will push the real state.
	piecesFound[player] = piecesFound[player] or {}
	sendState(player)
	sendInventory(player)
end)

PetCollectEvent.OnServerEvent:Connect(function(player, petId, pieceIndex)
	local def = PETS[petId]; if not def then return end
	pieceIndex = tonumber(pieceIndex)
	if not pieceIndex or pieceIndex < 1 or pieceIndex > #def.pieceMarkers then return end
	if ownsSpecies(player, petId) then return end -- already have the pet (any variant); ignore
	piecesFound[player] = piecesFound[player] or {}
	piecesFound[player][petId] = piecesFound[player][petId] or {}
	local set = piecesFound[player][petId]
	if set[pieceIndex] then return end -- already counted this exact piece (idempotent; no double-count)
	set[pieceIndex] = true
	local n = foundCount(player, petId)
	if def.questType == "crack" then
		print("[Pet] "..player.Name.." cracked coconut "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] "..player.Name.." earned the Cave Key") end
	elseif def.questType == "film-reels" then
		print("[Pet] "..player.Name.." took film reel "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] "..player.Name.." has all 6 film reels - load them at the projector") end
	else
		print("[Pet] "..player.Name.." collected piece "..n.."/"..#def.pieceMarkers)
		if n == #def.pieceMarkers then print("[Pet] egg appeared for "..player.Name.." at "..def.eggMarker) end
	end
	sendState(player)
	sendInventory(player) -- keep the quests panel's progress (N/total) current as pieces/coconuts are collected
end)

-- THE ONE COMPLETION PATH. Extracted from the PetClaimEvent handler so the dev /complete command can run
-- EXACTLY this -- the rare roll, the hatch-tier roll, the island-task tokens, the reward moment, the save, the
-- broadcast -- instead of a second copy that drifts out of step with it. `bypassGates` is the only difference
-- between a player claiming and a dev forcing, and it is off for anything that arrives over the remote.
local function completeQuest(player, petId, bypassGates)
	local def = PETS[petId]; if not def then return false end
	if ownsSpecies(player, petId) then return false end       -- already own this species (any variant)
	if not bypassGates then
		if def.questType == "fishing" then
			-- fishing has no pieces: the SERVER-rolled egg flag is the anti-cheat gate (client can't fake a catch)
			if not fishEggReady[player] then print("[Pet] "..player.Name.." tried to claim "..petId.." without catching the egg"); return false end
		elseif def.questType == "dig" then
			-- dig has no pieces: the player must have DUG the real buried-egg spot (PetDigEvent set this gate)
			if not digEggReady[player] then print("[Pet] "..player.Name.." tried to claim "..petId.." without digging up the egg"); return false end
		else
			if foundCount(player, petId) < #def.pieceMarkers then return false end -- must have all pieces (anti-cheat gate)
		end
	end
	-- RARE ROLL is FIRST-TIME-ONLY (permanent): the very FIRST ever completion of this quest rolls rare
	-- (1/750, 1/10000 for the duck, server-authoritative). Every RE-completion (quest redone after trading the
	-- species away) grants a GUARANTEED NORMAL pet -- the rare roll never happens again, so rares can never be
	-- re-farmed (they only come from that one first roll, or from trading). everCompleted persists across sessions.
	_G.playerEverCompletedQuests[player] = _G.playerEverCompletedQuests[player] or {}
	local firstTime = not _G.playerEverCompletedQuests[player][petId]
	_G.playerEverCompletedQuests[player][petId] = true -- PERMANENT: this quest has now been completed at least once

	-- ===== A QUEST HATCH IS NOT A GAMBLE =====
	-- What you get is the species the quest is FOR, at Baby, every single time. Both rolls that used to live
	-- here are gone on purpose:
	--
	--   * the RARE roll (1/750, 1/10000 for the duck) -- rarer pets now come from CRATE SPINS only, so the
	--     quest cannot hand one out. Doing an island quest is a guaranteed, known reward; the crate is where
	--     the gambling lives. Mixing the two meant the best pet in the game came from a quest you could only
	--     do once and could never re-roll, which is the worst possible place to put a 1-in-10,000.
	--   * the HATCH TIER roll (Baby..Elder starting level) -- age is no longer something you WIN, it is
	--     something you GROW. Every quest pet starts at Baby level 1 and ages to Elder purely on flight time
	--     and playtime (see awardXP: distance/coins/gas/islands). Rolling a starting tier meant one player's
	--     Elder was luck and another's was an hour of flying, and those two things should not look identical.
	--
	-- RARITY AND AGE ARE NOW SEPARATE AXES. Age (Baby->Elder) moves with play. Rarity never moves at all --
	-- an Uncommon stays an Uncommon forever, it just gets bigger. Nothing below may write `data.rare`.
	local data = { level = 1, xp = 0, height = 0, time = 0 }
	local hatchTier = "Baby"
	local isRare = false -- quests never grant a rare; kept so the shared claim path below reads unchanged
	print(string.format("[PetQuest] %s hatched %s at Baby (Lv 1) -- quest pets are fixed, they grow with play",
		player.Name, petId))
	print(string.format("[PetQuest] %s completed %s quest: firstTime=%s -> rareRoll=%s, granted %s at %s (Lv %d)",
		player.Name, petId, firstTime and "y" or "n", firstTime and "done" or "skipped",
		isRare and ((RARE_NAMES[petId] or petId).." (rare)") or "normal", hatchTier, data.level))
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	local skey = variantKey(petId, isRare)         -- a rare goes in its own slot so a normal can coexist later
	_G.playerOwnedPets[player][skey] = data         -- now a table (PlayerStats saves it, incl. the rare flag)
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = skey end -- auto-equip your first pet
	print("[Pet] "..player.Name.." claimed "..skey)
	print("[Pet] "..skey.." following "..player.Name)
	if isRare then
		pcall(function() PetRareEvent:FireClient(player, petId, RARE_NAMES[petId] or petId) end) -- the hatcher's own fanfare

		-- ===== AND THE WHOLE SERVER HEARS IT =====
		-- Rare SKINS already do this (SkinCrateService fires GoldAnnounce:FireAllClients on a Gold pull), but
		-- rare PETS did not -- PetRareEvent is FireClient, so the rarest event in the game happened in total
		-- silence to everyone except the person it happened to. That is backwards: seeing SOMEBODY ELSE hit a
		-- 1-in-750 is what makes a player believe the number is real and worth chasing. It is the single
		-- cheapest piece of social proof this game has.
		--
		-- The base odds ride along deliberately. "Got a rare" is a shrug; "1 in 10,000" is a number kids
		-- repeat to each other. rareOdds() is the UNMODIFIED headline -- the roll itself is shortened by
		-- rebirth luck, and announcing someone's personal luck-adjusted odds would be both confusing and a
		-- quiet way of broadcasting how many rebirths they have.
		pcall(function()
			PetRareAnnounce:FireAllClients({
				userId   = player.UserId,
				playerName = player.DisplayName or player.Name,
				petId    = petId,
				rareName = RARE_NAMES[petId] or petId,
				odds     = rareOdds(petId),
			})
		end)
	end

	-- ===== ISLAND TASK REWARD: CRATE TOKENS, ONCE PER ISLAND, EVER =====
	-- Gated on `firstTime`, which is the SAME flag the rare roll uses -- and it is backed by
	-- _G.playerEverCompletedQuests, which PlayerStats persists. So "once each" already survives a rejoin, and a
	-- player who trades the species away and redoes the quest gets the pet again but NOT the tokens again.
	-- Re-using the existing flag rather than adding a parallel one means the two can never disagree about
	-- whether this quest has been done.
	--
	-- The island number is PARSED from the quest's own islandPrefix ("Island_8_" -> 8) rather than written out
	-- in a second table. There is exactly one source of truth for which island a pet quest lives on, and adding
	-- a copy of it here is how the two drift apart the next time a quest moves.
	if firstTime then
		local island = tonumber(tostring(def.islandPrefix or ""):match("Island_(%d+)_") or "")
		if island then
			local tokens = 0
			if _G.crateTokensAward then
				local ok, granted = pcall(_G.crateTokensAward, player, "islandTask", island)
				if ok then tokens = tonumber(granted) or 0 end
			end
			if tokens > 0 then
				print(string.format("[IslandTask] %s cleared island %d (%s) -> +%d crate tokens",
					player.Name, island, def.islandName or "?", tokens))
				pcall(function()
					IslandTaskRewardEvent:FireClient(player, island, def.islandName or ("Island " .. island),
						tokens, def.displayName or petId)
				end)
			else
				-- Not fatal, but worth a line: it means SkinCrateService is not up yet, or the island has no
				-- entry in the ladder. Silence here would look exactly like "the reward is broken".
				warn(string.format("[IslandTask] %s cleared island %d but got 0 tokens -- is SkinCrateService up, and does CrateTokens.ISLAND_TASK have an entry for island %d?",
					player.Name, island, island))
			end
		end
	end

	sendState(player)     -- client hides egg/pieces and spawns the equipped follower
	sendInventory(player) -- the new pet shows up in the inventory GUI
	if _G.playerEquippedPet[player] == skey then broadcastEquip(player, isRare and "rare" or "equip") end -- auto-equipped first pet -> show to others
	checkCollectionMilestones(player) -- a new species may have just completed a milestone (title / the secret pet)
	return true
end

-- Players always go through the gates. bypassGates is never reachable from the client.
PetClaimEvent.OnServerEvent:Connect(function(player, petId) completeQuest(player, petId, false) end)

-- WHICH QUEST ISLAND IS THIS PLAYER STANDING ON. Measured against the island MODELS that findIsland() already
-- resolves, rather than against a second table of hard-coded Y values -- PlayerStats moves every island at
-- runtime, so any coordinate written down here would be wrong by the time anyone stood on it.
--
-- Returns petId, islandNumber -- or nil plus a reason string that is worth showing the player, because
-- "nothing happened" and "you are not on a quest island" look identical from the outside.
_G.petQuestIslandUnder = function(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil, "no character" end
	local here = hrp.Position

	local bestId, bestNum, bestDist
	for petId, def in pairs(PETS) do
		if def.islandPrefix then
			local island = findIsland(def.islandPrefix)
			if island then
				local ok, cf, size = pcall(function()
					local c, sz = island:GetBoundingBox(); return c, sz
				end)
				if ok and cf then
					-- Vertical distance decides it. The islands are stacked hundreds of studs apart but only
					-- a few hundred wide, so Y is the axis that actually separates them; comparing full 3D
					-- distance would let a wide island two levels down win on a tall thin one.
					local dy = math.abs(here.Y - cf.Position.Y)
					local halfY = (size and size.Y or 100) * 0.5 + 220 -- generous: you may be hovering over it
					if dy <= halfY and (not bestDist or dy < bestDist) then
						bestDist = dy
						bestId = petId
						bestNum = tonumber(tostring(def.islandPrefix):match("Island_(%d+)_") or "")
					end
				end
			end
		end
	end
	if not bestId then return nil, nil, "not on a quest island" end
	return bestId, bestNum, nil
end

-- FORCE-COMPLETE for the dev /complete command. Runs the real completion path with the anti-cheat gates
-- lifted, so everything a genuine hatch does still happens exactly once -- including the island-task tokens,
-- which stay gated on firstTime and therefore cannot be farmed by spamming the command.
_G.petForceCompleteQuest = function(player, petId)
	if not (player and PETS[petId]) then return false end
	return completeQuest(player, petId, true) and true or false
end

-- ===== MYTHICAL JACKPOT GRANT (server-authoritative). CURRENTLY UNCALLED: its only caller was the Pet
-- Wheel, which has been removed. Kept because it is a complete, working grant path -- wire it to a crate
-- tier or an event when you want a mythical payout again. Was called when the 0.1%
-- MYTHICAL PET wedge is rolled. Grants `petId` as its RARE/"Mythical" variant, pre-maxed to level 25 -- the
-- exact same variant + look the rare hatch produces (see the `if isRare then` branch in PetClaimEvent above).
-- Reuses the file-local variantKey / sendState / sendInventory / broadcastEquip / PetRareEvent so the pet
-- renders, PERSISTS (PlayerStats serialises _G.playerOwnedPets), and broadcasts to other players identically to
-- a genuine rare hatch. Returns the pet's display name on success, or nil if petId is invalid. Idempotent:
-- re-granting a mythical the player already owns is a harmless no-op that still returns the name.
_G.petGrantMythicalVariant = function(player, petId)
	if not player then return nil end
	local def = PETS[petId]; if not def then return nil end
	_G.playerOwnedPets[player] = _G.playerOwnedPets[player] or {}
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerEverCompletedQuests[player] = _G.playerEverCompletedQuests[player] or {}
	local skey = variantKey(petId, true)                              -- the rare gets its OWN slot (a normal can coexist)
	local already = _G.playerOwnedPets[player][skey] ~= nil
	_G.playerOwnedPets[player][skey] = { level = PET_MAX_LEVEL, xp = 0, height = 0, time = 0, rare = true } -- pre-maxed rare
	_G.playerDiscoveredQuests[player][petId] = true                   -- show it as discovered in the Pet Hub index
	_G.playerEverCompletedQuests[player][petId] = true               -- permanent, mirrors the hatch path
	if not _G.playerEquippedPet[player] then _G.playerEquippedPet[player] = skey end -- auto-equip if it's their first pet
	local name = RARE_NAMES[petId] or petId
	print(string.format("[Pet] %s won MYTHICAL %s%s", player.Name, name, already and " (already owned)" or ""))
	pcall(function() PetRareEvent:FireClient(player, petId, name) end) -- same rare-hatch fanfare
	sendState(player); sendInventory(player)
	if _G.playerEquippedPet[player] == skey then broadcastEquip(player, "rare") end -- show the equipped rare to others
	checkCollectionMilestones(player)                                 -- a new species may complete a collection milestone
	pcall(function() if _G.savePlayerData then _G.savePlayerData(player, "petwheel_mythical") end end) -- persist at once
	return name
end

-- ===== FISHING CATCH ROLL (SERVER-AUTHORITATIVE): the client invokes this after a successful reel-in. The
-- server owns the roll + the per-player pity counter so the client can NEVER decide what it catches. Egg chance
-- starts ~25% and ramps each catch, GUARANTEED by catch 8 (no endless bad luck -- it's an easy pet). A miss =
-- a funny junk item (just for variety). Returns { egg=true } or { egg=false, junk="..." } to the client. =====
local FISH_JUNK = { "an old boot", "a butter blob", "a rubber duck", "a soggy sock", "a rusty tin can",
                    "a clump of swamp weed", "a lost flip-flop", "a message in a bottle" }
PetFishRoll.OnServerInvoke = function(player)
	if ownsSpecies(player, "ButterDuck") then return { egg = true, already = true } end -- already have the duck (any variant)
	fishCatches[player] = (fishCatches[player] or 0) + 1
	local n = fishCatches[player]
	local eggChance = math.min(1, 0.25 + (n - 1) * 0.11) -- 0.25 at catch 1 -> ramps to 1.0 by catch ~8
	local gotEgg = (n >= 8) or (math.random() < eggChance) -- pity: guaranteed by catch 8
	if gotEgg then
		fishEggReady[player] = true -- the claim gate (above) now allows ButterDuck
		print("[Pet] "..player.Name.." reeled in -> caught the EGG (catch "..n..")")
		return { egg = true, catch = n }
	else
		local junk = FISH_JUNK[math.random(1, #FISH_JUNK)]
		print(string.format("[Pet] %s reeled in -> caught: %s (catch %d, egg chance now %d%%)", player.Name, junk, n, math.floor(eggChance * 100)))
		return { egg = false, junk = junk, catch = n, chance = math.floor(eggChance * 100) }
	end
end

-- ===== DIG (BurritoArmadillo): the client fires this when it finishes digging the REAL BuriedEggSpot. The
-- server unlocks the claim gate (digEggReady) so PetClaimEvent will accept the armadillo. Decoy digs (junk) are
-- purely client-side cosmetic and never call this -- only the real buried egg does. =====
PetDigEvent.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def or def.questType ~= "dig" then return end
	if ownsSpecies(player, petId) then return end
	digEggReady[player] = true
	print("[Pet] "..player.Name.." dug BuriedEggSpot -> EGG (claim unlocked)")
end)

-- ===== INVENTORY: EQUIP / UNEQUIP (one at a time) =====
PetEquipEvent.OnServerEvent:Connect(function(player, petId)
	if petId == false or petId == nil then
		_G.playerEquippedPet[player] = nil
		print("[PetInv] unequipped (none) for "..player.Name)
	else
		if not ownsPet(player, petId) then return end -- can only equip what you own
		-- ...and not what is currently ASLEEP IN THE PET HUT. PetBarn publishes the napping key here; a pet
		-- cannot be in two places at once, and without this check the Pet Hub could pull a pet back out of
		-- its bed while the hut still shows it sleeping there to every other player in the server.
		-- Guarded: if PetBarn isn't running, this is simply never true and equipping behaves as it always did.
		if _G.petBarnNapKeyOf then
			local ok, napKey = pcall(_G.petBarnNapKeyOf, player)
			if ok and napKey == petId then
				print("[PetInv] " .. player.Name .. " tried to equip " .. tostring(petId) .. " -- it's asleep in the Pet Hut")
				sendInventory(player) -- re-push so the card snaps back to its SLEEPING state
				return
			end
		end
		_G.playerEquippedPet[player] = petId
		local d = getPetData(player, petId)
		print(string.format("[PetLvl] %s equipped %s Lvl %d (%d/%s) tier visual: %s",
			player.Name, petId, d.level, math.floor(d.xp),
			(d.level >= PET_MAX_LEVEL) and "MAX" or tostring(xpNeeded(d.level)), tierVisual(d.level)))
	end
	sendState(player)     -- client spawns/despawns the follower to match
	sendInventory(player)
	broadcastEquip(player, _G.playerEquippedPet[player] and "equip" or "unequip") -- mirror the change to every other client
end)

-- ===== FUSION: N duplicates at one band -> ONE pet of the same species, one band up ==========================
-- The only route UP the rarity ladder that isn't a crate pull. Costs come from PetRarity.FUSE_COST (5 at the
-- bottom, 10 at the top); the duplicates are consumed.
--
-- THE RESULT HATCHES AT BABY, LEVEL 1 -- deliberately, and it is the whole reason age and rarity are separate
-- axes. Age is grown by flying; carrying it across a fuse would turn "stockpile duplicates" into a shortcut
-- past the growth curve, which is exactly the thing removing the hatch-tier roll was meant to stop. You are
-- buying a RARER pet, not an OLDER one. (The pets you burn keep no XP either -- nothing is transferred.)
--
-- FULLY SERVER-AUTHORITATIVE. The client sends a storage key and nothing else: not a count, not a rarity, not
-- a destination band. All three are re-derived here from what the player actually owns, so a forged
-- "fuse my 1 Common into a Gold" is arithmetically impossible rather than merely rejected.
PetFuseEvent.OnServerEvent:Connect(function(player, storageKey)
	if type(storageKey) ~= "string" then return end
	if not ownsPet(player, storageKey) then return end -- you cannot fuse a stack you do not have

	local d = getPetData(player, storageKey)
	if not d then return end

	local species = speciesOf(storageKey)
	local band    = d.rarity                       -- from the KEY, never from the client
	local ok, costOrReason = PetRarity.canFuse(band, d.count)
	if not ok then
		-- costOrReason is either the "highest rarity" string or how many MORE copies are needed.
		local why = (type(costOrReason) == "number")
			and string.format("Need %d more to fuse", costOrReason)
			or tostring(costOrReason)
		pcall(function() PetFuseResult:FireClient(player, false, { reason = why, key = storageKey }) end)
		return
	end

	local cost    = costOrReason
	local nextTierBand = PetRarity.nextOf(band)
	local destKey = variantKey(species, nextTierBand)

	-- ---- consume, then create. In that order: if the destination write failed we would rather have taken
	-- ---- nothing than have taken the duplicates and produced nothing.
	local op = _G.playerOwnedPets[player]
	local left = d.count - cost
	if left <= 0 then
		-- The whole stack went in. Clear the slot, and un-equip if the pet standing next to the player was
		-- the one just consumed -- otherwise the follower keeps rendering a pet its owner no longer has.
		op[storageKey] = nil
		if _G.playerEquippedPet[player] == storageKey then _G.playerEquippedPet[player] = nil end
	else
		d.count = left
	end

	local dest = op[destKey]
	if type(dest) == "table" then
		dest.count = (tonumber(dest.count) or 1) + 1 -- already own this band -> it stacks toward the NEXT fuse
	else
		op[destKey] = { level = 1, xp = 0, height = 0, time = 0, count = 1 } -- Baby: grow it yourself
	end
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	_G.playerDiscoveredQuests[player][species] = true

	print(string.format("[PetFuse] %s fused %dx %s %s -> 1x %s %s (%d left in the old stack)",
		player.Name, cost, band, species, nextTierBand, species, math.max(0, left)))

	pcall(function()
		PetFuseResult:FireClient(player, true, {
			petId = species, key = destKey,
			fromRarity = band, toRarity = nextTierBand,
			consumed = cost,
		})
	end)

	sendState(player); sendInventory(player)
	broadcastEquip(player, _G.playerEquippedPet[player] and "equip" or "unequip")
	-- Fusion destroys pets. That MUST hit the datastore now, not at the next autosave -- a rejoin after a
	-- crash that ate the duplicates but never wrote the upgrade is the one outcome players never forgive.
	if _G.savePlayerData then pcall(_G.savePlayerData, player, "petfuse") end
end)

-- ===== FREE (achievement) upgrade -- gated on the threshold being met =====
PetUpgradeEvent.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	if not canUpgrade(player, petId) then
		print("[PetInv] "..tostring(petId).." upgrade requested but threshold NOT met")
		return
	end
	levelUp(player, petId, "achievement")
end)

-- ===== FLIGHT-ACHIEVEMENT progress accumulation (per EQUIPPED pet). Cosmetic: only feeds the level gate;
-- never touches flight/gas/coins. The client reads the flight stats (peak height + airtime) and reports. =====
PetProgressEvent.OnServerEvent:Connect(function(player, petId, peakHeight, addTime)
	if not ownsPet(player, petId) then return end
	if _G.playerEquippedPet[player] ~= petId then return end -- only the equipped pet accrues progress
	local d = getPetData(player, petId)
	peakHeight = tonumber(peakHeight) or 0; addTime = tonumber(addTime) or 0
	if peakHeight > d.height then d.height = peakHeight end
	if addTime > 0 and addTime <= 30 then d.time = d.time + addTime end -- clamp per tick (sanity)
	local nl = nextTier(player, petId)
	local avail = canUpgrade(player, petId)
	print(string.format("[PetInv] %s flight progress: height=%d time=%d -> tier %s available: %s",
		petId, math.floor(d.height), math.floor(d.time), tostring(nl or "max"), avail and "yes" or "no"))
	-- only re-push the inventory GUI when upgrade-availability actually CHANGES (avoids per-tick resend spam)
	upgradeReady[player] = upgradeReady[player] or {}
	if upgradeReady[player][petId] ~= avail then upgradeReady[player][petId] = avail; sendInventory(player) end
end)

-- ===== ROBUX SKIP path: client declares which pet it's skipping, THEN prompts the Developer Product. The
-- actual XP-fill is gated behind ProcessReceipt (a real purchase). =====
PetPendingUpgrade.OnServerEvent:Connect(function(player, petId)
	if not ownsPet(player, petId) then return end
	-- \xE2\x9A\xA0 TEST skip path: test accounts skip-fill INSTANTLY (no real purchase) so the flow is testable. REMOVE BEFORE LAUNCH.
	if _G.isAllowedTestUser and _G.isAllowedTestUser(player) then
		tierSkip(player, petId, "test") -- testers TIER-skip instantly (no purchase) -- REMOVE BEFORE LAUNCH
		return
	end
	pendingRobuxPet[player.UserId] = petId
end)
-- Called by PlayerStats' single MarketplaceService.ProcessReceipt for the pet-SKIP product. Gated behind the
-- receipt -- a real purchase is required to fill the level (never faked).
_G.petsHandleReceipt = function(player, productId)
	local prod = PET_SKIP_PRODUCTS[productId]
	if not prod then return false end -- not one of our tier-skip products
	local petId = pendingRobuxPet[player.UserId]; pendingRobuxPet[player.UserId] = nil
	if not (petId and ownsPet(player, petId)) then return false end
	local d = getPetData(player, petId); if not d then return false end
	if d.level >= prod.srcMin and d.level <= prod.srcMax then
		d.level = prod.target; d.xp = 0 -- SERVER-AUTHORITATIVE: only applies in this product's source tier
		sendState(player); sendInventory(player)
		print("[PetLvl] tier-skip PURCHASED (to "..prod.to..") for "..petId.." -> Lvl "..d.level)
		return true
	end
	-- not in this product's source tier (pet leveled past it before the receipt) -> consume WITHOUT a wrong jump
	warn("[PetLvl] tier-skip product "..tostring(productId).." not applicable for "..petId.." (Lvl "..d.level.."); consumed, no jump")
	return true
end

-- ===== QUEST DISCOVERY: the client fires this when the player LANDS on a pet's island. Records it
-- (persisted by PlayerStats), so the quest shows in the inventory's quests panel permanently. =====
PetQuestDiscovered.OnServerEvent:Connect(function(player, petId)
	local def = PETS[petId]; if not def then return end
	_G.playerDiscoveredQuests[player] = _G.playerDiscoveredQuests[player] or {}
	if _G.playerDiscoveredQuests[player][petId] then return end -- already discovered (idempotent)
	_G.playerDiscoveredQuests[player][petId] = true
	print("[PetInv] quest discovered: "..petId.." on "..(def.islandName or "?"))
	questAvailable(player, petId) -- log doable/locked state (available iff they own zero of this species)
	sendInventory(player) -- the quest now appears in the player's quests panel
end)

-- =====================================================================================================
-- STAGE 3: PLAYER-TO-PLAYER TRADING (server-authoritative, atomic, anti-dupe). The client only sends INTENTS;
-- the server validates ownership, owns the offer/confirm state, and executes the swap in one synchronous step.
-- =====================================================================================================
local tradeOf    = {} -- [player] = session (a player is in at most ONE trade -> a pet can't be in two trades)
local incomingReq = {} -- [targetPlayer] = requesterPlayer (one pending incoming request)

local function keyList(set) local t = {}; for k in pairs(set) do t[#t+1] = k end; return table.concat(t, ",") end
local function ownedKeyList(player) local t = {}; for k in pairs(_G.playerOwnedPets[player] or {}) do t[#t+1] = k end; return table.concat(t, ",") end
-- ===== SKIN OFFERS ride this same trade session =====
-- A skin offer arrives as a "SKIN:<pet>|<skin>|<trait>" string over the SAME PetTradeOfferEvent. These three
-- one-line helpers route those keys to SkinCrateService's hooks, so skins became tradable without a second trade
-- system, a second window, or any change to the request/confirm handshake. All guarded: with the skin service
-- absent, isSkinKey is never true and every path below behaves exactly as it did before.
local SKIN_PREFIX = "SKIN:"
local function isSkinKey(k) return type(k) == "string" and k:sub(1, #SKIN_PREFIX) == SKIN_PREFIX end
local function skinKeyOf(k) return k:sub(#SKIN_PREFIX + 1) end

-- compact display payload for an offered pet (skey = the storage key being offered; petId = its SPECIES for the icon)
local function petBrief(player, skey)
	if isSkinKey(skey) then -- a SKIN entry, not a pet: let the skin service describe it
		if not _G.skinTradeBrief then return nil end
		local ok, brief = pcall(_G.skinTradeBrief, player, skinKeyOf(skey))
		return ok and brief or nil
	end
	local d = getPetData(player, skey); local sp = speciesOf(skey); local def = PETS[sp]; if not d then return nil end
	return { key = skey, petId = sp, name = (d.rare and RARE_NAMES[sp]) or (def and def.displayName) or sp, level = d.level, rare = d.rare and true or false }
end
local function offerList(owner, offerSet)
	local list = {}; for skey in pairs(offerSet) do local b = petBrief(owner, skey); if b then list[#list+1] = b end end; return list
end
local function tradeStatus(myC, theirC)
	if myC and theirC then return "trading" elseif myC then return "waiting_them" elseif theirC then return "waiting_you" else return "open" end
end

-- ANTI-SCAM STAGES. The classic trade scam is swapping your offer in the instant before the other person's
-- click lands, so they confirm something different from what they read. Three things stop that here:
--   1. ANY change to EITHER offer (items or tokens) clears BOTH readies -- already true for items, now true
--      for tokens too.
--   2. Once both sides are READY the offers are FROZEN and a countdown runs. Nothing can be added or removed
--      during it, so the last thing you saw is the thing that trades.
--   3. After the countdown BOTH sides must press CONFIRM one more time. That second press is on a locked
--      offer, so it can't be raced.
-- Cancel is available at every stage right up until the swap, and cancelling costs nothing -- no items move
-- until the final confirmations are both in.
local TRADE_STAGE_OFFER     = "offer"     -- building offers; readies clear on any change
local TRADE_STAGE_COUNTDOWN = "countdown" -- both ready; offers frozen; timer running
local TRADE_STAGE_FINAL     = "final"     -- timer done; both must confirm once more to execute
local TRADE_COUNTDOWN_SEC   = 5

-- Crate Tokens live in SkinCrateService, so every read goes through its global. Guarded: if that service failed
-- to load, trading simply reports a zero balance and the token half of the deal is unusable, rather than erroring
-- out the whole trade window.
local function tokenBalance(player)
	if not _G.crateTokensBalance then return 0 end
	local ok, n = pcall(_G.crateTokensBalance, player)
	return (ok and tonumber(n)) or 0
end

-- Back to a live, editable offer. Used whenever anything about the deal changes.
local function resetTradeStage(session)
	session.stage = TRADE_STAGE_OFFER
	session.confirmA, session.confirmB = false, false
	session.finalA, session.finalB = false, false
	session.countdownEnds = nil
	session.countdownToken = (session.countdownToken or 0) + 1 -- invalidates any in-flight countdown thread
end
local function sendTradeState(session)
	local A, B = session.a, session.b
	local stage = session.stage or TRADE_STAGE_OFFER
	-- Seconds left, recomputed per push rather than counted down on the client, so a laggy client can't show a
	-- longer window than the server is actually enforcing.
	local left = 0
	if session.countdownEnds then left = math.max(0, math.ceil(session.countdownEnds - tick())) end
	local function payload(me, them, myOffer, theirOffer, myC, theirC, myF, theirF, myTok, theirTok)
		return {
			active = true, withName = them.Name,
			mine = offerList(me, myOffer), theirs = offerList(them, theirOffer),
			myConfirm = myC, theirConfirm = theirC,
			status = tradeStatus(myC, theirC),
			-- token half of the deal
			myTokens = myTok, theirTokens = theirTok,
			myTokenBalance = tokenBalance(me),
			-- anti-scam stage machine
			stage = stage, countdown = left,
			myFinal = myF, theirFinal = theirF,
			locked = (stage ~= TRADE_STAGE_OFFER), -- client greys out add/remove while true
		}
	end
	pcall(function() if A.Parent then PetTradeState:FireClient(A,
		payload(A, B, session.offerA, session.offerB, session.confirmA, session.confirmB,
			session.finalA, session.finalB, session.tokensA or 0, session.tokensB or 0)) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B,
		payload(B, A, session.offerB, session.offerA, session.confirmB, session.confirmA,
			session.finalB, session.finalA, session.tokensB or 0, session.tokensA or 0)) end end)
end
local function closeTrade(session, reason, doneFlag)
	if not tradeOf[session.a] and not tradeOf[session.b] then return end -- already closed
	tradeOf[session.a] = nil; tradeOf[session.b] = nil
	pcall(function() if session.a.Parent then PetTradeState:FireClient(session.a, { active=false, reason=reason }) end end)
	pcall(function() if session.b.Parent then PetTradeState:FireClient(session.b, { active=false, reason=reason }) end end)
	if not doneFlag then print("[Trade] CANCELLED ("..tostring(reason)..")") end
end
-- ATOMIC, server-validated swap. Runs synchronously (no yields) -> no duplication window.
local function executeTrade(session)
	local A, B = session.a, session.b
	if not (A.Parent and B.Parent) then closeTrade(session, "a player left"); return end
	-- SECURITY re-check at execution: both must still OWN everything they're offering (not just when added).
	-- Skin entries are checked through the skin service's own ownership function -- same rule, different inventory.
	local function stillOwns(who, key)
		if isSkinKey(key) then
			if not _G.skinTradeOwns then return false end
			local ok, owns = pcall(_G.skinTradeOwns, who, skinKeyOf(key))
			return ok and owns == true
		end
		return ownsPet(who, key)
	end
	for petId in pairs(session.offerA) do if not stillOwns(A, petId) then closeTrade(session, A.Name.." no longer owns "..petId); return end end
	for petId in pairs(session.offerB) do if not stillOwns(B, petId) then closeTrade(session, B.Name.." no longer owns "..petId); return end end
	-- CRATE TOKENS are re-checked here too, not just when they were offered: a player can open a crate between
	-- offering and confirming, and promising tokens you no longer hold must fail the trade rather than transfer
	-- a smaller amount than the other side agreed to.
	local tokA, tokB = math.max(0, math.floor(session.tokensA or 0)), math.max(0, math.floor(session.tokensB or 0))
	if tokA > 0 and not (_G.crateTokensCanAfford and _G.crateTokensCanAfford(A, tokA)) then
		closeTrade(session, A.Name.." no longer has "..tokA.." tokens"); return
	end
	if tokB > 0 and not (_G.crateTokensCanAfford and _G.crateTokensCanAfford(B, tokB)) then
		closeTrade(session, B.Name.." no longer has "..tokB.." tokens"); return
	end
	-- OPEN TRADING with STACKING + VARIANTS: ANY pet for ANY pet. Offers are STORAGE KEYS (petId or petId#R), so a
	-- normal and a rare of one species are independent units. Receiving a key you already own STACKS it (count++,
	-- shared at the higher level); receiving a DIFFERENT variant key just lands as its own separate entry. Nothing to
	-- reject -- different variants can't overwrite each other because they live under different keys.
	local op = _G.playerOwnedPets
	print(string.format("[Trade] EXECUTING %s[%s] <-> %s[%s] - validated ownership both sides (stacking+variants on)", A.Name, keyList(session.offerA), B.Name, keyList(session.offerB)))
	-- snapshot the UNIT each side gives (level/xp/rare), remove ONE from each giver (count--, or drop the stack at 0),
	-- then add ONE to each receiver: STACK if they already own that exact key (count++, keep the higher level) else new.
	local giveA, giveB = {}, {}
	-- Snapshot the unit each side is giving. For a SKIN key the unit is {pet,skin,trait} from the skin service; for
	-- a pet key it's the level/xp/progress bundle. Both are just opaque payloads to addOne below.
	local function snapshot(owner, skey)
		if isSkinKey(skey) then
			if not _G.skinTradeUnit then return nil end
			local ok, unit = pcall(_G.skinTradeUnit, owner, skinKeyOf(skey))
			return ok and unit or nil
		end
		local d = getPetData(owner, skey)
		return d and { level = d.level, xp = d.xp, height = d.height, time = d.time, rare = d.rare } or nil
	end
	for skey in pairs(session.offerA) do giveA[skey] = snapshot(A, skey) end
	for skey in pairs(session.offerB) do giveB[skey] = snapshot(B, skey) end
	local function removeOne(owner, skey)
		if isSkinKey(skey) then
			if _G.skinTradeRemoveOne then pcall(_G.skinTradeRemoveOne, owner, skinKeyOf(skey)) end
			return
		end
		local d = op[owner][skey]; if not d then return end
		local c = (d.count or 1) - 1
		if c <= 0 then op[owner][skey] = nil else d.count = c end
	end
	local function addOne(owner, skey, unit)
		if not unit then return end
		if isSkinKey(skey) then
			-- Receiving a skin STACKS on the matching key (or lands as a new entry), including a skin for a pet the
			-- receiver has NOT unlocked -- that's allowed on purpose, and it shows as "Unlock <Pet> to equip" until
			-- they do. The skin service owns that logic.
			if _G.skinTradeAddOne then pcall(_G.skinTradeAddOne, owner, unit) end
			return
		end
		local d = op[owner][skey]
		if d then -- same exact key -> stack, keeping the higher level so no progress is lost
			d.count = (d.count or 1) + 1
			if (unit.level or 1) > (d.level or 1) then d.level = unit.level; d.xp = unit.xp or 0 end
		else
			op[owner][skey] = { level = unit.level or 1, xp = unit.xp or 0, height = unit.height or 0, time = unit.time or 0, rare = unit.rare or nil, count = 1 }
		end
	end
	for skey in pairs(session.offerA) do removeOne(A, skey) end
	for skey in pairs(session.offerB) do removeOne(B, skey) end
	-- Tokens move in the same no-yield window as the items. Validated just above, so a false here means the
	-- balance changed between two lines of straight-line code, which can't happen -- it's logged rather than
	-- unwound because there is nothing that could have consumed it.
	if tokA > 0 and _G.crateTokensTrade and not _G.crateTokensTrade(A, B, tokA) then
		warn("[Trade] token transfer A->B failed unexpectedly ("..tokA..")")
	end
	if tokB > 0 and _G.crateTokensTrade and not _G.crateTokensTrade(B, A, tokB) then
		warn("[Trade] token transfer B->A failed unexpectedly ("..tokB..")")
	end
	for skey, unit in pairs(giveA) do addOne(B, skey, unit) end -- A's unit -> B (stacks onto B's matching key)
	for skey, unit in pairs(giveB) do addOne(A, skey, unit) end -- B's unit -> A (stacks onto A's matching key)
	-- RE-DOABLE QUESTS: whoever traded away their LAST of a SPECIES (owns neither variant now) gets that quest reset
	-- so they can earn it again. A re-completion grants a GUARANTEED NORMAL (rare roll is first-time-only).
	-- (Skin keys are skipped here: giving away a SKIN never affects a pet quest -- you still own the pet.)
	for skey in pairs(giveA) do if not isSkinKey(skey) then local sp = speciesOf(skey); if not ownsSpecies(A, sp) then resetQuestProgress(A, sp); questAvailable(A, sp) end end end
	for skey in pairs(giveB) do if not isSkinKey(skey) then local sp = speciesOf(skey); if not ownsSpecies(B, sp) then resetQuestProgress(B, sp); questAvailable(B, sp) end end end
	-- clear equipped if it was traded away (keep equip state sane)
	if _G.playerEquippedPet[A] and not ownsPet(A, _G.playerEquippedPet[A]) then _G.playerEquippedPet[A] = nil end
	if _G.playerEquippedPet[B] and not ownsPet(B, _G.playerEquippedPet[B]) then _G.playerEquippedPet[B] = nil end
	tradeOf[A] = nil; tradeOf[B] = nil
	print(string.format("[Trade] DONE - %s now owns %s, %s now owns %s", A.Name, ownedKeyList(A), B.Name, ownedKeyList(B)))
	-- refresh both clients FIRST (the swap is already done in memory), then persist (SetAsync yields).
	sendState(A); sendInventory(A); sendState(B); sendInventory(B)
	-- push the SKIN inventories too, so a traded skin appears/disappears in the cosmetics UI immediately
	if _G.skinTradeAfter then pcall(_G.skinTradeAfter, A); pcall(_G.skinTradeAfter, B) end
	-- a trade can COMPLETE a collection (you received the species you were missing). It can also drop someone below
	-- a threshold they'd already been paid for -- milestones are deliberately NOT revoked in that case: the reward
	-- was earned, and clawing back a title (or the secret pet) because a player traded a duplicate away would be a
	-- nasty surprise. claimed[] is permanent, so re-crossing the same threshold never re-pays either.
	checkCollectionMilestones(A); checkCollectionMilestones(B)
	broadcastEquip(A, "equip"); broadcastEquip(B, "equip") -- a traded-away equipped pet may have changed -> update remote views
	pcall(function() if A.Parent then PetTradeState:FireClient(A, { active=false, reason="completed" }) end end)
	pcall(function() if B.Parent then PetTradeState:FireClient(B, { active=false, reason="completed" }) end end)
	if _G.savePlayerData then pcall(function() _G.savePlayerData(A, "trade") end); pcall(function() _G.savePlayerData(B, "trade") end) end -- persist BOTH now (anti-dupe)
end

PetTradeRequest.OnServerEvent:Connect(function(player, targetUserId)
	if tradeOf[player] then return end -- already in a trade
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target or target == player or tradeOf[target] then return end
	incomingReq[target] = player
	print(string.format("[Trade] %s requested trade with %s", player.Name, target.Name))
	pcall(function() PetTradePrompt:FireClient(target, player.UserId, player.Name) end)
end)

PetTradeRespond.OnServerEvent:Connect(function(player, accept)
	local requester = incomingReq[player]; incomingReq[player] = nil
	if not (requester and requester.Parent) then return end
	if accept == true and not tradeOf[player] and not tradeOf[requester] then
		local session = {
			a = requester, b = player,
			offerA = {}, offerB = {},
			confirmA = false, confirmB = false,
			tokensA = 0, tokensB = 0,                -- Crate Tokens each side is putting in
			finalA = false, finalB = false,          -- the post-countdown second confirmation
			stage = TRADE_STAGE_OFFER, countdownToken = 0,
		}
		tradeOf[requester] = session; tradeOf[player] = session
		print(string.format("[Trade] %s accepted trade with %s", player.Name, requester.Name))
		sendTradeState(session)
	else
		print(string.format("[Trade] %s declined trade from %s", player.Name, requester.Name))
		pcall(function() if requester.Parent then PetTradeState:FireClient(requester, { active=false, reason="declined" }) end end)
	end
end)

PetTradeOffer.OnServerEvent:Connect(function(player, petId, add)
	local session = tradeOf[player]; if not session or type(petId) ~= "string" then return end
	-- FROZEN once both sides are ready: the whole point of the countdown is that what you read is what you get,
	-- so a late add/remove is refused outright rather than silently resetting everyone back to the offer stage.
	if (session.stage or TRADE_STAGE_OFFER) ~= TRADE_STAGE_OFFER then return end
	local mine = (session.a == player) and session.offerA or session.offerB
	if add == true then
		if isSkinKey(petId) then
			-- SKIN offer: ownership is checked against the skin inventory instead of the pet table. Nothing is
			-- auto-unequipped here -- a skin stays wearable right up until the trade executes, and the skin service
			-- clears the equip at that point if the last copy left.
			local owns = false
			if _G.skinTradeOwns then local ok, r = pcall(_G.skinTradeOwns, player, skinKeyOf(petId)); owns = ok and r == true end
			if not owns then return end
			mine[petId] = true
			print(string.format("[Trade] %s added skin %s to offer", player.Name, skinKeyOf(petId)))
			resetTradeStage(session)
			sendTradeState(session)
			return
		end
		if not ownsPet(player, petId) then return end -- can only offer what you actually own
		if _G.playerEquippedPet[player] == petId then -- auto-unequip the equipped pet when you offer it
			_G.playerEquippedPet[player] = nil; sendState(player); sendInventory(player)
			broadcastEquip(player, "unequip") -- remove the follower from other clients too
		end
		mine[petId] = true
		print(string.format("[Trade] %s added %s to offer", player.Name, petId))
	else
		mine[petId] = nil
		print(string.format("[Trade] %s removed %s from offer", player.Name, petId))
	end
	resetTradeStage(session) -- ANY offer change RESETS both readies (anti-scam)
	sendTradeState(session)
end)

-- TOKEN OFFER. Same anti-scam rules as an item: refused while frozen, and any change clears both readies.
-- The amount is clamped to what the player actually holds at the time, and re-validated again at execution --
-- so spending tokens on a crate mid-trade can't let someone promise more than they have.
PetTradeTokens.OnServerEvent:Connect(function(player, amount)
	local session = tradeOf[player]; if not session then return end
	if (session.stage or TRADE_STAGE_OFFER) ~= TRADE_STAGE_OFFER then return end
	local n = math.floor(tonumber(amount) or 0)
	if n < 0 then n = 0 end
	n = math.min(n, tokenBalance(player))
	if session.a == player then
		if session.tokensA == n then return end
		session.tokensA = n
	else
		if session.tokensB == n then return end
		session.tokensB = n
	end
	print(string.format("[Trade] %s set token offer to %d", player.Name, n))
	resetTradeStage(session)
	sendTradeState(session)
end)

-- ONE button, three meanings depending on the stage -- READY while building, ignored during the countdown, and
-- CONFIRM once the countdown is done. Keeping it on the existing remote means the trade window didn't need a
-- second verb and older clients still work (they just see the button relabel itself).
PetTradeConfirm.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]; if not session then return end
	local isA = (session.a == player)
	local stage = session.stage or TRADE_STAGE_OFFER

	if stage == TRADE_STAGE_COUNTDOWN then
		return -- nothing to press; the timer has to finish first
	end

	if stage == TRADE_STAGE_FINAL then
		-- SECOND confirmation, on an offer that has been frozen since before the countdown started.
		if isA then session.finalA = true else session.finalB = true end
		print(string.format("[Trade] %s gave FINAL confirmation", player.Name))
		if session.finalA and session.finalB then executeTrade(session) else sendTradeState(session) end
		return
	end

	-- READY
	if isA then session.confirmA = true else session.confirmB = true end
	print(string.format("[Trade] %s is READY (offers: %s=[%s]+%dtok %s=[%s]+%dtok)", player.Name,
		session.a.Name, keyList(session.offerA), session.tokensA or 0,
		session.b.Name, keyList(session.offerB), session.tokensB or 0))

	if not (session.confirmA and session.confirmB) then
		sendTradeState(session)
		return
	end

	-- BOTH READY -> freeze and run the countdown. `countdownToken` is captured now and compared when the timer
	-- fires: resetTradeStage bumps it, so a trade that got edited (or cancelled, or re-opened between two
	-- different players) can never have a stale thread push it into the final stage.
	session.stage = TRADE_STAGE_COUNTDOWN
	session.countdownEnds = tick() + TRADE_COUNTDOWN_SEC
	local myToken = session.countdownToken or 0
	print(string.format("[Trade] both ready -> %ds countdown", TRADE_COUNTDOWN_SEC))
	sendTradeState(session)

	task.spawn(function()
		-- Tick once a second so the window can show the number counting down, re-checking validity each time.
		for _ = 1, TRADE_COUNTDOWN_SEC do
			task.wait(1)
			if session.countdownToken ~= myToken then return end        -- edited/cancelled
			if not tradeOf[session.a] or not tradeOf[session.b] then return end -- closed
			sendTradeState(session)
		end
		if session.countdownToken ~= myToken then return end
		if not tradeOf[session.a] or not tradeOf[session.b] then return end
		session.stage = TRADE_STAGE_FINAL
		session.countdownEnds = nil
		print("[Trade] countdown done -> FINAL confirmation required from both sides")
		sendTradeState(session)
	end)
end)

PetTradeCancel.OnServerEvent:Connect(function(player)
	local session = tradeOf[player]; if session then closeTrade(session, "cancelled by "..player.Name) end
end)

Players.PlayerRemoving:Connect(function(player)
	piecesFound[player] = nil -- ownership/equipped/discovered clears are handled by PlayerStats (after it saves)
	pendingRobuxPet[player.UserId] = nil
	upgradeReady[player] = nil
	lastInvSync[player] = nil; lastXpPrint[player] = nil -- XP-sync / diagnostic throttles (session-only)
	fishCatches[player] = nil; fishEggReady[player] = nil -- fishing pity is session-only (not persisted)
	digEggReady[player] = nil -- dig gate is session-only (not persisted)
	-- TRADE: if they were trading, cancel cleanly (no item loss/dupe -- nothing was swapped until both confirmed).
	local session = tradeOf[player]; if session then closeTrade(session, player.Name.." left") end
	incomingReq[player] = nil
	for tgt, req in pairs(incomingReq) do if req == player then incomingReq[tgt] = nil end end
end)

print("[Pet] PetSystem ready (cosmetic-only)")
