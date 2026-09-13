--======================================================================
-- PetBarn.client.lua  (LocalScript)   [Bean Island -- the Pet Hut]
--======================================================================
-- THE PET HUT, player side. Two jobs:
--
--   1. THE PANEL. Walk up to the hut, press E (or tap the prompt) and the 700x520 panel opens: a grid
--      of YOUR pets, each on a card with a live 3D preview of that actual pet -- its species, its skin, its
--      age-correct size -- and a DROP OFF button. If you already have one asleep, the panel shows that pet
--      big instead, with how long it has slept and what it has earned, and a WAKE UP button. Closes on its X
--      only -- never on a stray tap on the backdrop, same rule as every other menu in the game.
--
--   2. THE SLEEPING PETS. Renders EVERY napping pet in the server -- yours and everyone else's -- curled up
--      on the beds outside the hut with a name tag over each. That pile is the entire point of the feature: a
--      passer-by should see whose pets are here without opening anything.
--
-- ===== WHY THE PETS ARE BUILT HERE AND NOT ON THE SERVER =====
-- Same call RemotePets makes, for the same reasons. Server-side pet models would replicate two dozen CFrames
-- per frame to every client forever, and StreamingEnabled would then need each one marked Persistent to stay
-- visible. A sleeping pet is scenery: nothing collides, nothing is queryable, and nobody can tell whether
-- your copy and mine breathe on the same frame. So each client grows its own from the SAME server-fused
-- Union templates in ReplicatedStorage that PetFollow and RemotePets clone. Zero replication, zero server cost.
--
-- ===== ASLEEP MEANS CALM =====
-- A napping pet deliberately does NOT get the level aura, orbit orbs, ring, trail, sparkles or the accessory
-- ladder that a following pet gets. It is asleep. It gets its body, its equipped SKIN (painted through
-- PetSkinLook's static path), its age SIZE, a slow breathing bob, shut eyes and floating Z's. That is a design
-- decision, not a missing feature -- a row of pets each throwing off particles would be soup.
--
-- ===== THE BEDS ARE PARTS, NOT MATHS =====
-- PetBarn.server builds the hut AND names every bed NapBed_0 .. NapBed_7. This script looks a bed up by
-- name and stands the pet on it. No shared layout constants between the two files, so there is nothing to
-- drift: move the marker in Studio and the pets move with it, because they stand on the hut's actual beds.
--======================================================================

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- DUPLICATE GUARD. Rojo ADDS, it never overwrites, so a stale copy of this script baked into the place file
-- runs alongside the synced one. Two copies means two full-screen backdrops (the second one orphaned over the
-- world, which is exactly the input-eating bug MenuBackdropGuard exists to clean up) and two sets of sleeping
-- pets standing in the same beds.
if _G.__PetBarnClient then
	warn("[PetBarn] a SECOND copy of PetBarn.client is running -- this one is bailing out. " ..
		"Delete the stale LocalScript in Studio (Explorer > search 'PetBarn') and re-sync Rojo.")
	return
end
_G.__PetBarnClient = true

local PetBarnEvent = RS:WaitForChild("PetBarnEvent", 30)
local PetBarnState = RS:WaitForChild("PetBarnState", 30)
if not (PetBarnEvent and PetBarnState) then
	warn("[PetBarn] server remotes not present -- pet house inactive")
	return
end
-- PetSystem's OWN remotes. Equipping is its business, not ours: firing PetEquipEvent is what makes it run
-- sendState(), and sendState is what makes PetFollow spawn/despawn the follower. See the server header.
local PetEquipEvent        = RS:FindFirstChild("PetEquipEvent")
local PetInventoryEvent    = RS:FindFirstChild("PetInventoryEvent")
local PetRequestStateEvent = RS:FindFirstChild("PetRequestStateEvent")

--======================================================================
-- TUNING
--======================================================================
local MAX_SLOTS   = 8               -- beds the server builds; used for the "N / 8" readout only. MUST match
                                    -- PetBarn.server's MAX_SLOTS (BED_COLS * BED_ROWS).
local NAP_TILT    = math.rad(20)    -- how far a sleeping pet slumps. Enough to read as lying down without
                                    -- folding the union bodies into themselves.
local SIGN_DIST   = 45              -- studs the floating hut sign is visible from, COPIED FROM THE CAMPFIRE
                                    -- (Campfire.server's sign uses MaxDistance = 45). Same feel: the name
                                    -- fades in as you walk up and is gone again once you leave.
local DRAW_DIST   = 260             -- past this, stop animating sleeping pets (see the breathing loop)

-- FORWARD DECLARATIONS. The roster and inventory handlers are connected long before the panel is built, and
-- both re-render it when data changes. Declared local up here so nothing in this file leaks a global.
local panelOpen = false
local renderPanel
local decorateHub -- marks the Pet Hub card SLEEPING; defined far below, called from the roster handler

--======================================================================
-- SPECIES TABLES
--======================================================================
-- COPIED FROM RemotePets.client.lua -- change one, change both. A species missing from PET_TEMPLATE_NAME has
-- no body to clone, so that player's pet is INVISIBLE outside the hut AND its card preview is empty; a species
-- missing from PET_DISPLAY gets labelled with its raw id ("BeanBuddy" instead of "Bean Buddy").
local PET_TEMPLATE_NAME = {
	BeanBuddy="BeanBuddyTemplate", PizzaDragon="PizzaDragonTemplate",
	BroccoliPet="BroccoliBunnyTemplate", CoconutCrab="CoconutCrabTemplate", PopcornSheep="PopcornSheepTemplate",
	ButterDuck="ButterDuckTemplate", BurritoArmadillo="BurritoArmadilloTemplate",
	SunflowerBee="SunflowerBeeTemplate", MapleFox="MapleFoxTemplate", FrostPenguin="FrostPenguinTemplate",
	BlossomBunny="BlossomBunnyTemplate",
	MoltenBean="MoltenBeanTemplate", VoidDragon="VoidDragonTemplate", PrismFox="PrismFoxTemplate",
}
local PET_DISPLAY = { BeanBuddy="Bean Buddy", PizzaDragon="Pizza Dragon", BroccoliPet="Broccoli Bunny",
	CoconutCrab="Coconut Crab", PopcornSheep="Popcorn Sheep", ButterDuck="Butter Duck",
	BurritoArmadillo="Burrito Armadillo", SunflowerBee="Sunflower Bee", MapleFox="Maple Fox",
	FrostPenguin="Frost Penguin", BlossomBunny="Blossom Bunny",
	MoltenBean="Molten Bean", VoidDragon="Void Dragon", PrismFox="Prism Fox" }
local RARE_NAME = { BroccoliPet="Emerald Bunny", CoconutCrab="Golden Crab", PopcornSheep="Cloud Sheep",
	BurritoArmadillo="Crystal Armadillo", ButterDuck="Cosmic Duck" }

-- The AGE ladder, mirroring PetFollow / RemotePets exactly. Change one, change all three.
local function ageName(level)
	if level <= 5 then return "Baby", Color3.fromRGB(175,180,190)
	elseif level <= 10 then return "Kid", Color3.fromRGB(90,210,90)
	elseif level <= 15 then return "Teen", Color3.fromRGB(70,140,255)
	elseif level <= 20 then return "Adult", Color3.fromRGB(180,90,235)
	else return "Elder", Color3.fromRGB(255,170,40) end
end
local function displayNameOf(petId, isRare)
	if isRare and RARE_NAME[petId] then return RARE_NAME[petId] end
	return PET_DISPLAY[petId] or petId
end
local function speciesOf(skey)
	if type(skey) ~= "string" then return skey end
	return (skey:gsub("#R$", ""))
end
local function ageScale(level) return 0.6 + 0.4 * math.clamp(((level or 1) - 1) / 24, 0, 1) end

-- What a pet of this age earns while it sleeps, in coins per minute.
-- MIRRORS PetBarn.server's coinsForLevel() x 6 ticks a minute -- change one, change both. This is the number
-- that decides WHICH pet you drop off, so showing it on the card is the difference between an informed pick
-- and a guess; a wrong number here is worse than none.
local function coinsPerMin(level)
	return math.clamp(1 + math.floor((tonumber(level) or 1) / 6), 1, 5) * 6
end

--======================================================================
-- THE HOUSE + ITS BEDS
--======================================================================
local houseModel, houseAnchor
-- "PetHouse" is what the model was called before the hut rebuild. It stays in this list so a client that is
-- still looking at an old server (or a place file that has not re-synced yet) still finds the building and
-- still gets its prompt, rather than silently rendering nothing.
local HOUSE_MODEL_NAMES = { "PetHut", "PetHouse" }
local function findHouse()
	for _, name in ipairs(HOUSE_MODEL_NAMES) do
		local m = Workspace:FindFirstChild(name)
		if m and m:IsA("Model") then
			return m, (m.PrimaryPart or m:FindFirstChild("HouseAnchor"))
		end
	end
	return nil, nil
end
-- Beds are named parts the SERVER built. Nil here just means the house has not replicated yet -- the caller
-- retries on the next roster tick rather than guessing a position.
local function bedPart(slot)
	if not houseModel then return nil end
	local beds = houseModel:FindFirstChild("Beds")
	if not beds then return nil end
	local b = beds:FindFirstChild("NapBed_" .. tostring(slot))
	return (b and b:IsA("BasePart")) and b or nil
end

local petFolder = Instance.new("Folder")
petFolder.Name = "SleepingPets"
petFolder.Parent = Workspace

--======================================================================
-- BUILDING A SLEEPING PET
--======================================================================
-- Clone the same server-fused Union template PetFollow and RemotePets clone. No client-built fallback body:
-- if the template has not replicated yet we simply retry on the next state broadcast.
local function buildBody(petId)
	local tn = PET_TEMPLATE_NAME[petId]
	local template = tn and RS:FindFirstChild(tn)
	if not template then return nil end
	local clone = template:Clone()
	local root = clone:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then clone:Destroy(); return nil end
	clone.PrimaryPart = root
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true
		end
	end
	return clone, root
end

-- Shut the eyes. The templates name their eye parts "Eye" (and "Highlight" for the glint); squashing them
-- flat is exactly what PetFollow's blink does at its lowest point, so a sleeping pet reads as a blink that
-- never opens rather than as a pet with something wrong with its face.
local function shutEyes(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name == "Eye" then
				p.Size = Vector3.new(p.Size.X, math.max(p.Size.Y * 0.12, 0.05), p.Size.Z)
			elseif p.Name == "Highlight" then
				p.Transparency = 1
			end
		end
	end
end

local function makeZs(root, tint)
	local a = Instance.new("Attachment"); a.Name = "ZzzAt"; a.Position = Vector3.new(0, 1.6, 0); a.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Zzz"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(tint or Color3.fromRGB(210, 232, 255))
	pe.LightEmission = 0.35
	pe.Rate = 2.2
	pe.Lifetime = NumberRange.new(1.6, 2.4)
	pe.Speed = NumberRange.new(0.6, 1.1)
	pe.SpreadAngle = Vector2.new(6, 6)
	pe.Acceleration = Vector3.new(0, 1.2, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.75) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.25), NumberSequenceKeypoint.new(1, 1) })
	pe.Rotation = NumberRange.new(-20, 20)
	pe.Parent = a
	return pe
end

-- The name tag. Owner on top -- that is what makes the pile social; you should be able to point at a pet and
-- say whose it is -- then the pet's name, then its age badge. Greyed when the owner has left the server.
-- MaxDistance matches the hut sign (and the campfire's): readable up close, gone from the air.
local function makeTag(root, entry)
	local bb = Instance.new("BillboardGui")
	bb.Name = "NapTag"; bb.Size = UDim2.new(0, 152, 0, 46); bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = SIGN_DIST; bb.Parent = root

	local owner = Instance.new("TextLabel")
	owner.Size = UDim2.new(1, 0, 0, 13); owner.BackgroundTransparency = 1
	owner.Font = Enum.Font.GothamBold; owner.TextSize = 11
	owner.TextColor3 = entry.away and Color3.fromRGB(150, 158, 170) or Color3.fromRGB(190, 224, 255)
	owner.Text = tostring(entry.name or "?")
	owner.Parent = bb
	Instance.new("UIStroke").Parent = owner

	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(1, 0, 0, 15); nm.Position = UDim2.new(0, 0, 0, 14); nm.BackgroundTransparency = 1
	nm.Font = Enum.Font.FredokaOne; nm.TextSize = 13
	nm.TextColor3 = entry.away and Color3.fromRGB(190, 196, 206) or Color3.new(1, 1, 1)
	nm.Text = "\xF0\x9F\x92\xA4 " .. displayNameOf(entry.petId, entry.isRare)
	nm.Parent = bb
	Instance.new("UIStroke").Parent = nm

	local age, ageCol = ageName(entry.level or 1)
	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(0.5, 0); badge.Position = UDim2.new(0.5, 0, 0, 31)
	badge.AutomaticSize = Enum.AutomaticSize.X; badge.Size = UDim2.new(0, 0, 0, 13)
	badge.Font = Enum.Font.GothamBold; badge.TextSize = 10; badge.TextColor3 = Color3.new(1, 1, 1)
	badge.BackgroundColor3 = entry.away and Color3.fromRGB(120, 126, 138) or ageCol
	badge.Text = entry.away and (age .. "  \xE2\x80\xA2  away") or (age .. "  Age " .. tostring(entry.level or 1))
	badge.Parent = bb
	local pad = Instance.new("UIPadding", badge); pad.PaddingLeft = UDim.new(0, 5); pad.PaddingRight = UDim.new(0, 5)
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
	Instance.new("UIStroke", badge)
	return bb
end

--======================================================================
-- LIVE ROSTER -> MODELS
--======================================================================
local live = {}          -- [userId] = { entry, model, root, base = CFrame, phase }
local latestRoster = {}
local pendingRetry = false -- true when something failed to build (no template / no bed yet)

local function destroyLive(userId)
	local L = live[userId]
	if not L then return end
	if L.model then pcall(function() L.model:Destroy() end) end
	live[userId] = nil
end

-- Two entries are "the same pet in the same place" if all of these match. Anything else (a different pet, a
-- new skin, an age change, the owner leaving) rebuilds, which is cheap and keeps the render honest.
local function sameLook(a, b)
	return a and b
		and a.petId == b.petId and a.level == b.level and a.isRare == b.isRare
		and a.skin == b.skin and a.trait == b.trait and a.slot == b.slot and a.away == b.away
end

local function spawnPet(entry)
	local bed = bedPart(entry.slot)
	if not bed then pendingRetry = true; return end
	local model, root = buildBody(entry.petId)
	if not model then pendingRetry = true; return end
	model.Name = "SleepingPet_" .. tostring(entry.userId)

	-- The SKIN travels with the pet, exactly as it does for a following pet -- a cosmetic only its owner can
	-- see is a cosmetic nobody has a reason to buy. static=true is the calm variant: colours and materials, no
	-- emitters or hue cycling, because this pet is asleep.
	if _G.applyPetSkinPreview then
		pcall(_G.applyPetSkinPreview, model, entry.skin, entry.trait, true)
	end
	shutEyes(model)

	-- AGE SIZE: the same 60%-at-Baby -> 100%-at-Elder ramp PetFollow and RemotePets use, so a pet is the same
	-- size asleep as it is awake.
	pcall(function() model:ScaleTo(ageScale(entry.level)) end)

	-- Stand it on the cushion. The bed is a cylinder lying flat, so its thickness is along its OWN X axis --
	-- half of Size.X above the bed's centre is the top of the cushion. The pivot (Root) sits mid-body, so the
	-- model is raised by roughly a third of its height on top of that to rest ON the bed rather than in it.
	local ext = model:GetExtentsSize()
	local topY = bed.Position.Y + bed.Size.X / 2
	-- ===== THEY ALL FACE THE WAY THE HUT FACES =====
	-- They used to be aimed AT the hut, which is backwards: players walk in from the front, so every pet had
	-- its back turned to whoever came to look at it. And because the beds sit on an ARC, each pet turned by a
	-- different amount -- so the row fanned inward instead of reading as a row.
	--
	-- The hut's front is the direction from its centre out to the door anchor. Every pet takes that same one
	-- vector, so the whole arc faces the approach square-on and in parallel.
	local fwd
	if houseAnchor and houseModel then
		local d = houseAnchor.Position - houseModel:GetPivot().Position
		fwd = Vector3.new(d.X, 0, d.Z)
	end
	if not fwd or fwd.Magnitude < 0.05 then
		-- fallback: point away from the hut, which at worst still keeps them looking outward
		local ref = houseAnchor and houseAnchor.Position or (bed.Position + Vector3.new(0, 0, 1))
		local d = bed.Position - ref
		fwd = Vector3.new(d.X, 0, d.Z)
		if fwd.Magnitude < 0.05 then fwd = Vector3.new(0, 0, -1) end
	end
	local eye = Vector3.new(bed.Position.X, topY + ext.Y * 0.30, bed.Position.Z)
	local base = CFrame.lookAt(eye, eye + fwd.Unit) * CFrame.Angles(0, 0, NAP_TILT)
	model:PivotTo(base)
	model.Parent = petFolder

	makeZs(root, entry.away and Color3.fromRGB(170, 176, 188) or nil)
	makeTag(root, entry)
	if entry.away then
		-- An away pet is dimmed rather than removed: the beds should still look taken, but you should be able
		-- to tell at a glance which pets have nobody coming back for them right now.
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.5 then p.Transparency = 0.35 end
		end
	end

	live[entry.userId] = { entry = entry, model = model, root = root, base = base,
		phase = (entry.userId % 100) / 100 * math.pi * 2 } -- staggered so the row doesn't breathe in unison
end

local function applyRoster(roster)
	latestRoster = roster or {}
	pendingRetry = false
	if not houseModel then houseModel, houseAnchor = findHouse() end
	local seen = {}
	for _, entry in ipairs(latestRoster) do
		seen[entry.userId] = true
		local L = live[entry.userId]
		if L and sameLook(L.entry, entry) then
			L.entry = entry -- earnings/timer changed only; the model is still correct
		else
			destroyLive(entry.userId)
			spawnPet(entry)
		end
	end
	for userId in pairs(live) do
		if not seen[userId] then destroyLive(userId) end
	end
end

PetBarnState.OnClientEvent:Connect(function(roster)
	if type(roster) ~= "table" then return end
	applyRoster(roster)
	if panelOpen and renderPanel then renderPanel() end
	if decorateHub then task.defer(decorateHub) end -- the Hub's SLEEPING state follows the roster
end)

-- RETRY. On join the house model and the pet templates stream in over several seconds, so the first roster
-- broadcast routinely arrives before there is anywhere to put a pet. Without this the beds stay empty until
-- somebody happens to drop off or collect one.
task.spawn(function()
	while true do
		task.wait(3)
		if pendingRetry then
			if not houseModel then houseModel, houseAnchor = findHouse() end
			applyRoster(latestRoster)
		end
	end
end)

-- BREATHING + FIDGETS. One Heartbeat for every sleeping pet in the server.
--
-- Breathing alone is periodic, and the eye reads perfect periodicity as machinery -- eight pets rising and
-- falling forever is a diorama with a motor in it. So each pet also SHIFTS every 12-26 seconds: a slow turn
-- of the shoulders and a small lift, eased in and out, like something repositioning in its sleep. They are
-- staggered by construction (each next time is rolled independently), so you never get a chorus line.
--
-- Frozen past DRAW_DIST for the same reason AmbientWildlife freezes its butterflies -- a pet you cannot see
-- does not need animating, and that is what keeps two dozen of them free. A pet that was mid-fidget when it
-- froze picks the movement back up on the same clock, so nothing snaps when you turn round.
local FIDGET_MIN, FIDGET_MAX = 12, 26   -- seconds between one pet's shifts
local FIDGET_DUR  = 1.8                 -- how long one takes
local FIDGET_YAW  = math.rad(13)        -- how far the shoulders turn
local FIDGET_LIFT = 0.13
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local here = hrp and hrp.Position
	local t = os.clock()
	for _, L in pairs(live) do
		if L.model and L.model.Parent and L.base then
			if (not here) or (here - L.base.Position).Magnitude <= DRAW_DIST then
				local b = t * 1.1 + L.phase
				local breathe = math.sin(b) * 0.09
				local sway    = math.sin(b * 0.5) * math.rad(1.6)

				-- FIDGET. nextFidget is seeded on the first frame this pet is drawn rather than when it
				-- spawns, so a hutful of pets that all appeared on the same broadcast still drift apart.
				if not L.nextFidget then
					L.nextFidget = t + FIDGET_MIN + math.random() * (FIDGET_MAX - FIDGET_MIN)
				end
				local fy, flift = 0, 0
				if L.fidgetStart then
					local k = (t - L.fidgetStart) / FIDGET_DUR
					if k >= 1 then
						L.fidgetStart = nil
						L.nextFidget = t + FIDGET_MIN + math.random() * (FIDGET_MAX - FIDGET_MIN)
					else
						-- one smooth there-and-back: sin over half a turn peaks in the middle and returns to
						-- exactly zero, so the pet always lands back where it started
						local e = math.sin(k * math.pi)
						fy, flift = e * FIDGET_YAW * (L.fidgetDir or 1), e * FIDGET_LIFT
					end
				elseif t >= L.nextFidget then
					L.fidgetStart = t
					L.fidgetDir = (math.random() < 0.5) and -1 or 1
				end

				pcall(function()
					L.model:PivotTo(L.base * CFrame.new(0, breathe + flift, 0) * CFrame.Angles(0, sway + fy, 0))
				end)
			end
		end
	end
end)

--======================================================================
-- YOUR PET INVENTORY (for the drop-off grid)
--======================================================================
local inventory = {} -- [storageKey] = card, straight off PetSystem's PetInventoryEvent payload
if PetInventoryEvent then
	PetInventoryEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.owned) == "table" then
			inventory = payload.owned
			if panelOpen and renderPanel then renderPanel() end
		end
	end)
end

--======================================================================
-- UI HELPERS
--======================================================================
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end
local function grad(p, a, b, rot)
	local g = Instance.new("UIGradient", p); g.Rotation = rot or 90; g.Color = ColorSequence.new(a, b); return g
end
-- Press feedback. Every button in the panel gets it: without it a tap on a touchscreen gives no sign it
-- registered, so players tap three more times and drop three pets off.
local function pressable(btn)
	local base = btn.BackgroundColor3
	local function tint(f) btn.BackgroundColor3 = Color3.new(base.R * f, base.G * f, base.B * f) end
	btn.MouseButton1Down:Connect(function() tint(0.82) end)
	btn.MouseButton1Up:Connect(function() tint(1) end)
	btn.MouseLeave:Connect(function() tint(1) end)
	return btn
end

--======================================================================
-- 3D PET PREVIEWS
--======================================================================
-- The single biggest upgrade over an emoji: the card shows the ACTUAL pet -- right species, right skin, right
-- age size -- slowly turning. Same trick the Pet Hub's card icons use.
local spinners = {} -- [ViewportFrame] = { model, speed }
RunService.RenderStepped:Connect(function(dt)
	for vf, s in pairs(spinners) do
		if vf.Parent and s.model.Parent then
			s.t = s.t + dt * s.speed
			pcall(function() s.model:PivotTo(s.home * CFrame.Angles(0, s.t, 0)) end)
		else
			spinners[vf] = nil -- the card was destroyed on a re-render; stop paying for it
		end
	end
end)

-- `parent` must be a frame that already carries the tile's fill -- the ViewportFrame itself is left fully
-- transparent on purpose. A UIGradient on a ViewportFrame tints the RENDERED MODEL as well as the backing,
-- which would wash every pet blue and make skins unreadable.
-- `zoom` is the camera pull-back multiplier: LOWER means the pet fills more of the frame. 2.1 is the safe
-- default for a small tile (a long pet like the Armadillo needs the headroom); the big featured preview passes
-- something tighter because it has the pixels to spare and the pet is the point of that pane.
local function petViewport(parent, props, petId, level, skin, trait, zoom)
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.BorderSizePixel = 0
	vf.Ambient = Color3.fromRGB(190, 205, 230)
	vf.LightColor = Color3.fromRGB(255, 250, 240)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.6)
	for k, v in pairs(props) do vf[k] = v end
	vf.Parent = parent

	local model = buildBody(petId)
	if not model then return vf end -- template not replicated yet; the card just shows its blue tile
	if _G.applyPetSkinPreview then pcall(_G.applyPetSkinPreview, model, skin, trait, true) end
	pcall(function() model:ScaleTo(ageScale(level)) end)
	model.Parent = vf

	local cam = Instance.new("Camera")
	vf.CurrentCamera = cam
	cam.Parent = vf

	-- Frame the pet: sit the model at the origin and back the camera off by its own size, so a Baby and an
	-- Elder both fill the tile instead of one being a speck and the other clipping out of frame.
	local ext = model:GetExtentsSize()
	local home = CFrame.new(0, -ext.Y * 0.15, 0)
	model:PivotTo(home)
	local dist = math.max(ext.X, ext.Y, ext.Z) * (zoom or 2.1) + 2
	cam.CFrame = CFrame.lookAt(Vector3.new(0, ext.Y * 0.28, dist), Vector3.new(0, 0, 0))

	spinners[vf] = { model = model, home = home, t = 0, speed = 0.7 }
	return vf
end

--======================================================================
-- THE PANEL
--======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "PetHouseGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100; gui.Enabled = false; gui.Parent = PlayerGui

-- Full-screen catcher: it SWALLOWS taps that land off the panel so they don't reach the world, but it does
-- NOT close the panel. Menus in this game close on their X and nothing else -- a stray tap slamming a panel
-- shut is the single most annoying thing a menu can do.
--
-- FULLY TRANSPARENT. No tint, no dim: the design call is that ONLY the panel renders and the world behind
-- it stays exactly as bright as it was. The button itself must stay -- it is what stops a stray tap from
-- reaching the world -- it just draws nothing.
mkButton(gui, { Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Active = true })

local panel = mkFrame(gui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(26, 79, 214), ClipsDescendants = true, Active = true, ZIndex = 2,
})
mkCorner(panel, 22); mkStroke(panel, Color3.new(1, 1, 1), 4)
-- FLAT, NOT GRADED. The panel used to fade 46,122,226 -> 14,59,176 top to bottom, which meant nothing laid on
-- it could ever match its own background -- the scroll fade at the bottom of the grid had to guess a blend
-- colour, and the cards sat on a lighter blue at the top of the list than at the bottom. One flat blue makes
-- the three-tone depth system below (panel > inset > well) actually legible, and it is the reason the fade
-- can now simply be the panel colour.

-- Navy drop shadow, same as the garden panels -- but it has to FOLLOW the panel, which no longer has a fixed
-- height: sizePanelTo shrinks it whenever a state needs less room, and a shadow frozen at 520 would sit out
-- past the bottom edge as a floating navy band.
-- ===== NO SHADOW, NO BACKDROP, NO TINT =====
-- This used to build two navy frames behind the panel as a drop shadow. At their original 54/30px spreads
-- they covered virtually the whole screen at up to 38% opacity -- the "blue overlay" -- and even shrunk they
-- were still a coloured layer under the panel. The design call now is absolute: ONLY the panel renders.
-- The table survives (empty) because fitPanel() below resizes whatever is in it; with nothing in it, that
-- loop is simply a no-op, and any future shadow experiment can drop frames back in without re-plumbing.
local SHADOWS = {}

-- the shared adaptive UIScale every 700x520 panel in the game uses. (If shadow frames ever return to the
-- SHADOWS table above, remember a UIScale only reaches its own descendants -- siblings of the panel need
-- their own, driven from this same apply(), or they render unscaled. That bug produced a screen-wide navy
-- rectangle on small viewports once already.)
local applyPanelScale
do
	local s = Instance.new("UIScale"); s.Parent = panel
	applyPanelScale = function()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		s.Scale = math.min(vp.X / 1280, vp.Y / 720, 1)
	end
	applyPanelScale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyPanelScale)
	end
end

--======================================================================
-- ONE PALETTE, USED BY EVERY PIECE
--======================================================================
-- The panel used to pick its colours inline, so the header, the cards, the stat tiles and the footer each
-- invented their own blue and their own border. That is the single biggest reason it read as "several boxes
-- stacked together" rather than one screen. Everything below now draws from here.
--
-- DEPTH IS DONE WITH VALUE, NOT WITH BORDERS. Three blues -- panel, inset, well -- and a thing looks recessed
-- because it is darker than what it sits on, not because it has an outline. The thick white stroke is then
-- reserved for the two jobs it actually does well: the outside edge of the panel, and the primary buttons.
local C = {
	panel   = Color3.fromRGB( 30,  92, 214),   -- the panel itself
	inset   = Color3.fromRGB( 20,  68, 172),   -- cards, chips, the asleep panel
	well    = Color3.fromRGB( 15,  52, 136),   -- stat tiles, footer: the deepest layer
	sky     = Color3.fromRGB( 96, 176, 252),   -- behind a pet model, so it reads against the blue

	orange  = Color3.fromRGB(255, 168,  46),   -- header
	ink     = Color3.fromRGB( 74,  40,   4),   -- text ON orange (6.8:1)
	green   = Color3.fromRGB( 72, 194,  74),   -- primary action
	greenHi = Color3.fromRGB(108, 222,  96),
	greenLo = Color3.fromRGB( 48, 152,  52),
	grey    = Color3.fromRGB(118, 130, 148),   -- primary action, disabled
	red     = Color3.fromRGB(232,  72,  84),   -- close
	gold    = Color3.fromRGB(255, 208,  72),   -- rare / earnings

	white   = Color3.new(1, 1, 1),
	txt     = Color3.new(1, 1, 1),
	txtDim  = Color3.fromRGB(186, 214, 250),   -- secondary copy
	txtMute = Color3.fromRGB(146, 184, 236),   -- captions and the tips (5.3:1 on `well`)
}
-- The panel is built above this block (it has to exist before anything can be parented to it), so its fill is
-- assigned here rather than duplicating the literal in two places. gridFade paints itself C.panel to blend
-- into this exact colour, so the two must never drift apart.
panel.BackgroundColor3 = C.panel

-- ===== VERTICAL RHYTHM =====
-- Every y in this file comes from these. Previously the header ended at 80, the subtitle sat at 84, the rail
-- at 116 and the body at 154 -- gaps of 4, 32 and 38 with no reason behind any of them.
local PAD       = 12                       -- panel edge, used on all four sides
local HEAD_H    = 54
local STRIP_Y   = PAD + HEAD_H + 8         -- 74
local STRIP_H   = 32
local BODY_TOP  = STRIP_Y + STRIP_H + 10   -- 116

-- ===== HEADER =====
-- Icon, title, close -- and nothing else, so PET HUT has nothing to compete with. 54 tall instead of 66, and
-- the 12 saved goes straight to the pet previews, which is what a player is actually looking at.
--
-- The title dropped 30 -> 26. It was the largest text in the panel by a clear margin and pulled the eye to a
-- word you only need to read once; at 26 it is still unmistakably the heading and the pet names beneath it
-- (17, and 28 on the asleep card) can now hold their own.
--
-- Flat orange, not a gradient. The old header faded 255,226,140 -> 232,172,36, which is nearly the full
-- yellow-to-orange range in one 66px bar and made the dark title text sit on a moving background.
local header = mkFrame(panel, { Size = UDim2.new(1, -PAD * 2, 0, HEAD_H), Position = UDim2.new(0, PAD, 0, PAD),
	BackgroundColor3 = C.orange, ZIndex = 3 })
mkCorner(header, 14); mkStroke(header, C.white, 3)
local badge = mkFrame(header, { Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(0, 8, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(255, 246, 226), ZIndex = 4 })
mkCorner(badge, 11); mkStroke(badge, C.white, 2)
mkLabel(badge, { Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextSize = 21, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
mkLabel(header, { Text = "PET HUT", Font = Enum.Font.FredokaOne, TextSize = 26, TextColor3 = C.ink,
	Size = UDim2.new(1, -108, 1, 0), Position = UDim2.new(0, 54, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
-- Fixed TextSize, not TextScaled-with-padding. The old X was a 44px button scaling its glyph inside 9px of
-- padding on every side, which rounds to a different size at every UIScale and never quite sat centred.
local closeBtn = pressable(mkButton(header, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(0, 36, 0, 36),
	Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = C.red, Text = "X",
	Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = C.white, ZIndex = 5 }))
mkCorner(closeBtn, 10); mkStroke(closeBtn, C.white, 2)

-- ===== STATUS STRIP: ONE ROW, TWO THINGS =====
-- The bed markers and the free-bed count are the SAME FACT drawn two ways, so they now share one chip
-- instead of floating 32px apart as separate elements. The sentence telling you what to do sits on the same
-- baseline to its left. That is the whole strip: what to do, and how much room is left.
local bedChip = mkFrame(panel, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 244, 0, STRIP_H),
	Position = UDim2.new(1, -PAD, 0, STRIP_Y), BackgroundColor3 = C.inset, ZIndex = 3 })
mkCorner(bedChip, 10)

local countLbl = mkLabel(bedChip, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = C.txt, AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(0, 100, 1, 0),
	Position = UDim2.new(1, -10, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })

-- THE BED RAIL. One marker per actual bed, in the order the server hands them out -- so marker N is bed N in
-- the world, and walking outside shows the pets in the same left-to-right order.
--
-- DOTS, NOT CAPSULES. At 14px square with a 1.5px outline these read as a row of eight empty boxes -- eight
-- more rectangles in a panel that already had too many. 10px fully-rounded dots say the same thing (filled =
-- taken, hollow = free, gold ring = yours) while reading as punctuation rather than as another list.
local RAIL_SLOTS = {}
do
	local MARK, GAPX = 10, 4
	local rail = mkFrame(bedChip, { Size = UDim2.new(0, MAX_SLOTS * MARK + (MAX_SLOTS - 1) * GAPX, 0, MARK),
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundTransparency = 1, ZIndex = 4 })
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal; lay.Padding = UDim.new(0, GAPX)
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = rail
	for i = 1, MAX_SLOTS do
		local slot = mkFrame(rail, { Size = UDim2.new(0, MARK, 0, MARK), LayoutOrder = i,
			BackgroundColor3 = C.well, ZIndex = 5 })
		mkCorner(slot, MARK // 2)
		local st = mkStroke(slot, Color3.fromRGB(74, 128, 214), 1.5)
		-- Kept so the render loop can stay as it is, never shown: 14px cannot hold a name, and pretending
		-- otherwise is what produced the clipped text this replaced.
		local lbl = mkLabel(slot, { Text = "", Visible = false, ZIndex = 6 })
		RAIL_SLOTS[i] = { frame = slot, stroke = st, label = lbl }
	end
end

local subLbl = mkLabel(panel, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14,
	TextColor3 = C.txtDim, Size = UDim2.new(1, -320, 0, STRIP_H), Position = UDim2.new(0, PAD + 4, 0, STRIP_Y),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })

--======================================================================
-- PILLS THAT CANNOT CLIP
--======================================================================
-- Every badge on this panel used to be "  TEXT  " with AutomaticSize.X -- padding faked with spaces. That
-- fails in two ways at once: AutomaticSize measures the text at its FIXED TextSize, so a long label (a
-- 2-word age name, a 4-digit rate) simply runs past the rounded end; and the UIStroke draws outside the
-- measured box, so even a correctly-sized pill loses its last glyph under the outline.
--
-- This does it properly: real UIPadding for the horizontal breathing room, TextScaled so a long string steps
-- DOWN instead of overflowing, and a UITextSizeConstraint so a short one does not balloon. `size` becomes a
-- ceiling rather than a fixed value.
local PILL_H = 20
local function pill(parent, opts)
	local l = mkLabel(parent, {
		Text = opts.text, Font = opts.font or Enum.Font.GothamBold,
		TextSize = opts.size or 11, TextColor3 = opts.fg or Color3.new(1, 1, 1),
		BackgroundTransparency = 0, BackgroundColor3 = opts.bg,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, opts.h or PILL_H),
		Position = opts.pos, AnchorPoint = opts.anchor,
		TextScaled = true, ZIndex = opts.z or 5,
	})
	local pad = Instance.new("UIPadding", l)
	pad.PaddingLeft  = UDim.new(0, opts.padX or 9)
	pad.PaddingRight = UDim.new(0, opts.padX or 9)
	local c = Instance.new("UITextSizeConstraint", l)
	c.MaxTextSize = opts.size or 11
	c.MinTextSize = 8
	mkCorner(l, (opts.h or PILL_H) // 2)
	mkStroke(l, Color3.new(1, 1, 1), 1)
	return l
end

-- ===== BODY A: ONE LARGE HORIZONTAL PET PANEL =====
--
-- WHY THIS IS NOT A GRID OF CARDS.
-- The previous pass turned this into fixed 216px cards, which made a player with one pet stare at a small
-- portrait tile marooned in a wide window. A grid is the right shape when you are COMPARING many things; the
-- job here is "look at my pet, then drop it off", which is one subject and one action. So the pet gets the
-- whole width: a big preview on the left, its facts stacked beside it, and the action running the full width
-- underneath. Owning more pets adds a compact picker strip below -- it does not shrink the pet.
local FOOT_H   = 32
local FEAT_H   = 268                   -- the big pet panel
local CHOOSE_H = 74                    -- the picker strip, only present when you own more than one pet
local PANEL_W  = 700
local INNER    = PANEL_W - PAD * 2     -- 676
local CHOOSE_Y = BODY_TOP + FEAT_H + 8 -- 392

-- Panel height is derived from whatever the visible state actually ends at, so no state ever pads itself out
-- with empty blue and none of them can drift apart when one is edited.
local function fitPanel(bodyBottom)
	local h = bodyBottom + 10 + FOOT_H + PAD
	panel.Size = UDim2.new(0, PANEL_W, 0, h)
	for _, sh in ipairs(SHADOWS) do
		sh.frame.Size = UDim2.new(0, PANEL_W + sh.spread, 0, h + sh.spread)
	end
	return h
end

local featured = mkFrame(panel, { Size = UDim2.new(1, -PAD * 2, 0, FEAT_H), Position = UDim2.new(0, PAD, 0, BODY_TOP),
	BackgroundColor3 = C.inset, Visible = false, ZIndex = 3 })
mkCorner(featured, 18); mkStroke(featured, C.white, 3)

-- ----- the pet, big -----
-- 280 x 172 against the old 200 x 142 tile: 70% more area, and the camera pulls in tighter on top of that.
local FEAT_PAD  = 16
local PREV_W    = 280
local featPrev  = mkFrame(featured, { Size = UDim2.new(0, PREV_W, 0, FEAT_H - 96),
	Position = UDim2.new(0, FEAT_PAD, 0, FEAT_PAD), BackgroundColor3 = C.sky,
	ClipsDescendants = true, ZIndex = 4 })
mkCorner(featPrev, 14)

-- ----- its facts, beside it -----
local INFO_X = FEAT_PAD + PREV_W + 16                 -- 312
local INFO_W = INNER - INFO_X - FEAT_PAD              -- 348

local featName = mkLabel(featured, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = C.txt,
	Size = UDim2.new(0, INFO_W, 0, 40), Position = UDim2.new(0, INFO_X, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })

local featAge = pill(featured, { text = "", bg = Color3.fromRGB(175, 180, 190), size = 13, h = 26,
	pos = UDim2.new(0, INFO_X, 0, 68), z = 5 })
local featEquip = pill(featured, { text = "EQUIPPED", bg = Color3.fromRGB(46, 150, 96), size = 12, h = 26,
	pos = UDim2.new(0, INFO_X, 0, 68), z = 5 })   -- x is re-set in paintFeatured, after featAge has measured

-- THE EARN RATE GETS A TILE, NOT A PILL. It is the number the whole feature exists for -- it is why you pick
-- the old pet over the cute one -- so it is the only thing in this column allowed to be big and gold.
local rateTile = mkFrame(featured, { Size = UDim2.new(0, INFO_W, 0, 68), Position = UDim2.new(0, INFO_X, 0, 106),
	BackgroundColor3 = C.well, ZIndex = 4 })
mkCorner(rateTile, 14)
mkLabel(rateTile, { Text = "EARNS WHILE NAPPING", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.txtMute,
	Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 14, 0, 11),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
local rateVal = mkLabel(rateTile, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = C.gold,
	Size = UDim2.new(1, -28, 0, 34), Position = UDim2.new(0, 14, 0, 28),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })

-- ----- the action, full width -----
-- DEPTH WITHOUT DECORATION: a darker slab sits 4px lower than the button so it reads as a physical key with a
-- lip, which is the whole Roblox-simulator button language. It is a plain frame BEHIND the button rather than
-- a highlight layered on top, because a child drawn over a TextButton competes with the button's own label.
local dropBase = mkFrame(featured, { Size = UDim2.new(1, -FEAT_PAD * 2, 0, 52),
	Position = UDim2.new(0, FEAT_PAD, 1, -64), BackgroundColor3 = C.greenLo, ZIndex = 3 })
mkCorner(dropBase, 14)
local dropBtn = pressable(mkButton(featured, { Size = UDim2.new(1, -FEAT_PAD * 2, 0, 52),
	Position = UDim2.new(0, FEAT_PAD, 1, -68), BackgroundColor3 = C.green, Text = "DROP OFF",
	Font = Enum.Font.FredokaOne, TextSize = 26, TextColor3 = C.txt, ZIndex = 4 }))
mkCorner(dropBtn, 14); mkStroke(dropBtn, C.white, 3)
grad(dropBtn, C.greenHi, C.greenLo)

-- ===== THE PICKER STRIP =====
-- Only built when you own more than one pet. One pet means there is nothing to pick, and a row of one tile in
-- 676px of width is exactly the empty space this revamp is meant to remove.
local chooser = Instance.new("ScrollingFrame")
chooser.Size = UDim2.new(1, -PAD * 2, 0, CHOOSE_H); chooser.Position = UDim2.new(0, PAD, 0, CHOOSE_Y)
chooser.BackgroundColor3 = C.inset; chooser.BorderSizePixel = 0
chooser.ScrollingDirection = Enum.ScrollingDirection.X
chooser.ScrollBarThickness = 4; chooser.ScrollBarImageColor3 = C.gold
chooser.CanvasSize = UDim2.new(0, 0, 0, 0); chooser.Visible = false; chooser.ZIndex = 3
chooser.Parent = panel
mkCorner(chooser, 14)
do
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal; lay.Padding = UDim.new(0, 8)
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = chooser
	local pad = Instance.new("UIPadding", chooser)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
end

local emptyLbl = mkLabel(panel, { Text = "", Font = Enum.Font.GothamBold, TextSize = 17,
	TextColor3 = C.txtDim, Size = UDim2.new(1, -140, 0, 130), Position = UDim2.new(0, 70, 0, BODY_TOP + 30),
	TextWrapped = true, Visible = false, ZIndex = 4 })

-- ===== BODY B: the pet you already have asleep =====
--
-- A FEATURED CARD, NOT A MODEL FLOATING IN A BOX. The preview was a 208px square dropped 22px inside a
-- 306px panel, which left an L-shaped margin of empty blue around two of its sides and made the pet look
-- like a placeholder. It is now a proper left-hand pane: square, edge-aligned to the same 14px inset the
-- text column uses, and lit a lighter blue so the model reads against it.
--
-- The right-hand column is a straight top-to-bottom read: WHO (name + age) -> HOW IT'S DOING (three stats)
-- -> WHAT TO DO (one green button). Nothing crosses the gutter between the two panes.
local AS_H     = 300
local AS_PAD   = 14
local AS_PREV  = 236                                   -- the square preview pane
local AS_COL_X = AS_PAD + AS_PREV + 14                 -- 264: where the text column starts
local AS_COL_W = 676 - AS_COL_X - AS_PAD               -- 398

local asleepCard = mkFrame(panel, { Size = UDim2.new(1, -PAD * 2, 0, AS_H), Position = UDim2.new(0, PAD, 0, BODY_TOP),
	BackgroundColor3 = C.inset, Visible = false, ZIndex = 3 })
mkCorner(asleepCard, 18); mkStroke(asleepCard, C.white, 3)

local asleepVpHolder = mkFrame(asleepCard, { Size = UDim2.new(0, AS_PREV, 0, AS_PREV),
	Position = UDim2.new(0, AS_PAD, 0, AS_PAD), BackgroundColor3 = C.sky, ClipsDescendants = true, ZIndex = 4 })
mkCorner(asleepVpHolder, 14)

local asleepName = mkLabel(asleepCard, { Text = "", Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = C.txt,
	Size = UDim2.new(0, AS_COL_W, 0, 36), Position = UDim2.new(0, AS_COL_X, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })

local asleepAge = pill(asleepCard, { text = "", bg = Color3.fromRGB(175, 180, 190), size = 13, h = 24,
	pos = UDim2.new(0, AS_COL_X, 0, 60), z = 4 })

-- THREE STATS, EQUAL WEIGHT: how long, how much, how fast. The rate used to be crammed into the earnings
-- tile as "12  (6/min)", so the one number that tells you whether to leave the pet longer was a parenthetical.
local statTiles = {}
do
	local TW = (AS_COL_W - 2 * 10) / 3    -- 126
	for i, caption in ipairs({ "ASLEEP FOR", "EARNED", "PER MIN" }) do
		local tile = mkFrame(asleepCard, { Size = UDim2.new(0, TW, 0, 68),
			Position = UDim2.new(0, AS_COL_X + (i - 1) * (TW + 10), 0, 94), BackgroundColor3 = C.well, ZIndex = 4 })
		mkCorner(tile, 12)
		mkLabel(tile, { Text = caption, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.txtMute,
			Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 10, 0, 10),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
		-- TextScaled with a ceiling: "just now" and "1440 min" have to live in the same 110px as "3".
		local v = mkLabel(tile, { Text = "-", Font = Enum.Font.FredokaOne, TextSize = 22,
			TextColor3 = (i == 2) and C.gold or C.txt, Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.new(0, 10, 0, 28), TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true, ZIndex = 5 })
		local cst = Instance.new("UITextSizeConstraint", v); cst.MaxTextSize = 22; cst.MinTextSize = 12
		statTiles[i] = v
	end
end

-- Same slab-and-lip as DROP OFF, so the primary action is the same object in both states.
local wakeBase = mkFrame(asleepCard, { Size = UDim2.new(0, AS_COL_W, 0, 58),
	Position = UDim2.new(0, AS_COL_X, 0, 176), BackgroundColor3 = C.greenLo, ZIndex = 3 })
mkCorner(wakeBase, 14)
local wakeBtn = pressable(mkButton(asleepCard, { Size = UDim2.new(0, AS_COL_W, 0, 58),
	Position = UDim2.new(0, AS_COL_X, 0, 172), BackgroundColor3 = C.green, Text = "WAKE UP",
	Font = Enum.Font.FredokaOne, TextSize = 26, TextColor3 = C.txt, ZIndex = 4 }))
mkCorner(wakeBtn, 14); mkStroke(wakeBtn, C.white, 3)
grad(wakeBtn, C.greenHi, C.greenLo)

-- The tip runs the FULL width under both panes rather than only under the text column: it is about the panel,
-- not about the right-hand side, and stretching it across also fills the gap left below the square preview.
-- 12px and muted -- present when wanted, invisible when not.
local asleepHint = mkLabel(asleepCard, { Text = "", Font = Enum.Font.Gotham, TextSize = 12,
	TextColor3 = C.txtMute, Size = UDim2.new(1, -AS_PAD * 2, 0, 36), Position = UDim2.new(0, AS_PAD, 0, 256),
	TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4 })
asleepHint.LineHeight = 1.2

-- ===== FOOTER: ONE BAR, IDENTICAL IN BOTH STATES =====
-- Same bar in both states, so switching never nudges it. Deliberately the quietest thing on the panel: no
-- outline, a barely-there well, 12px muted text. It is a tip, and a tip that competes with the primary
-- button for attention is a design mistake -- the previous version had a 1.5px stroke and 13px text, which
-- gave a footnote the same visual weight as the stat tiles.
local footBar = mkFrame(panel, { Size = UDim2.new(1, -PAD * 2, 0, FOOT_H),
	Position = UDim2.new(0, PAD, 1, -(FOOT_H + PAD)), BackgroundColor3 = C.well, ZIndex = 3 })
mkCorner(footBar, 10)
-- The bulb gets its own small round chip so the tip reads as a labelled bar rather than a sentence that
-- happens to start with an emoji -- and it lets the text start on a clean left margin.
local footIcon = mkFrame(footBar, { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 9, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.gold, ZIndex = 4 })
mkCorner(footIcon, 11)
mkLabel(footIcon, { Text = "\xF0\x9F\x92\xA1", Font = Enum.Font.GothamBold, TextSize = 12,
	Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
-- 13px, not 12: this is the one line of prose in the panel and it was the smallest text on screen.
local footLbl = mkLabel(footBar, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = C.txtDim, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 39, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })

--======================================================================
-- RENDER
--======================================================================
-- Signature of the grid as it is currently DRAWN. renderPanel rebuilds cards only when this changes; see the
-- note where it is computed.
local listSig = nil
local asleepVp = nil
-- The DROP OFF handler is re-bound whenever the selected pet changes, so the old one has to go with it --
-- otherwise every selection change stacks another connection and one tap drops several pets.
local dropConn = nil

local function myNapEntry()
	for _, e in ipairs(latestRoster) do
		if e.userId == player.UserId then return e end
	end
	return nil
end

-- Which pet the big panel is showing. Defaults to the best napper you own -- the same pet the footer tip
-- recommends -- so the panel opens on the right answer and most players never touch the picker at all.
local selectedKey = nil
local featVp      = nil
local featSig     = nil
local chooseSig   = nil

local function dropOff(skey, card, btn)
	-- Every bed taken: say so and do nothing. The server would refuse anyway, but firing at it and watching
	-- nothing change looks exactly like a broken button.
	if #latestRoster >= MAX_SLOTS then
		btn.Text = "NO BEDS FREE"
		task.delay(1.2, function() if btn.Parent then btn.Text = "ALL BEDS FULL" end end)
		return
	end
	btn.Text = "..."
	btn.BackgroundColor3 = C.grey
	-- Unequip FIRST, through PetSystem's own remote, so the follower despawns; then ask the hut to take it.
	-- The server re-checks ownership either way -- this call is about the follower, not about trust.
	if card.equipped and PetEquipEvent then pcall(function() PetEquipEvent:FireServer(false) end) end
	PetBarnEvent:FireServer("drop", skey)
end

-- One tile in the picker strip: just the pet and a ring. No name, no stats -- everything about the pet is
-- already spelled out in the big panel, and repeating it here would turn a picker back into a grid of cards.
local function mkThumb(skey, card, order, selected)
	local petId = speciesOf(skey)
	local t = mkButton(chooser, { Size = UDim2.new(0, 58, 0, 58), LayoutOrder = order, Text = "",
		BackgroundColor3 = C.sky, AutoButtonColor = false, ClipsDescendants = true, ZIndex = 4 })
	mkCorner(t, 12)
	mkStroke(t, selected and C.gold or (card.rare and Color3.fromRGB(255, 226, 150) or C.white), selected and 3 or 2)
	petViewport(t, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 }, petId, card.level, card.skin, card.trait)
	t.MouseButton1Click:Connect(function()
		if selectedKey == skey then return end
		selectedKey = skey
		renderPanel()
	end)
	return t
end

-- Paints the big panel for whichever pet is selected. Split out from the render so the pet MODEL is only
-- rebuilt when the selection actually changes -- renderPanel also runs on a 3-second tick and on every roster
-- broadcast from other players, and re-cloning a Union that often would be brutal.
local function paintFeatured(skey, card)
	local petId = speciesOf(skey)
	local level = card.level or 1
	local age, ageCol = ageName(level)
	local full = (#latestRoster >= MAX_SLOTS)

	local sig = string.format("%s:%d:%s:%s:%s", skey, level, tostring(card.rare), tostring(card.skin), tostring(card.trait))
	if sig ~= featSig then
		featSig = sig
		if featVp then spinners[featVp] = nil; featVp:Destroy() end
		-- 1.75 instead of the default 2.1: this pane is 280 wide and the pet is the reason the panel exists.
		featVp = petViewport(featPrev, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 }, petId, level, card.skin, card.trait, 1.75)
	end

	featName.Text = displayNameOf(petId, card.rare)
	featName.TextColor3 = card.rare and C.gold or C.txt

	featAge.Text = age .. "  \xE2\x80\xA2  Age " .. tostring(level)
	featAge.BackgroundColor3 = ageCol
	featEquip.Visible = card.equipped and true or false
	-- AutomaticSize means featAge's width is only known after it has laid out, so EQUIPPED is positioned off
	-- its measured size rather than off a guess. One frame of settling is invisible; a hardcoded x would
	-- overlap the moment a pet is called "Teenager" instead of "Baby".
	task.defer(function()
		if featEquip.Parent then
			featEquip.Position = UDim2.new(0, INFO_X + featAge.AbsoluteSize.X + 8, 0, 68)
		end
	end)

	rateVal.Text = "\xF0\x9F\xAA\x99 " .. coinsPerMin(level) .. " / min"

	dropBtn.Text = full and "ALL BEDS FULL" or "DROP OFF"
	dropBtn.TextSize = full and 20 or 26
	dropBtn.BackgroundColor3 = full and C.grey or C.green
	dropBase.BackgroundColor3 = full and Color3.fromRGB(84, 94, 110) or C.greenLo
	if dropConn then dropConn:Disconnect() end
	dropConn = dropBtn.MouseButton1Click:Connect(function() dropOff(skey, card, dropBtn) end)
end

renderPanel = function()
	local mine = myNapEntry()
	local taken = #latestRoster

	-- ===== BED RAIL =====
	-- The server hands out beds by INDEX, so slot N on this rail is bed N in the world -- walk outside and
	-- the pets are in the same order, left to right. That correspondence is the reason this is worth drawing
	-- as slots rather than as a bar.
	local bySlot = {}
	for _, e in ipairs(latestRoster) do
		if e.slot then bySlot[e.slot] = e end
	end
	for i = 1, MAX_SLOTS do
		local ui = RAIL_SLOTS[i]
		local e  = bySlot[i - 1] -- server slots are 0-based
		if not e then
			ui.frame.BackgroundColor3 = C.well
			ui.stroke.Color = Color3.fromRGB(74, 128, 214); ui.stroke.Thickness = 1.5
			ui.label.Text = "free"
			ui.label.TextColor3 = Color3.fromRGB(104, 148, 210)
		else
			local mine = (e.userId == player.UserId)
			local _, ageCol = ageName(e.level or 1)
			ui.frame.BackgroundColor3 = e.away and Color3.fromRGB(88, 96, 112) or ageCol
			-- yours gets a gold outline: in a rail of eight near-identical chips, finding your own by reading
			-- names is exactly the small friction this is meant to remove
			ui.stroke.Color = mine and C.gold or C.white
			ui.stroke.Thickness = mine and 2.5 or 1.5
			-- no text: the marker is a 10px dot. Yours is identified by the gold ring set just above.
			ui.label.Text = ""
		end
	end
	-- Full white, not a dim blue. This is the number that decides whether the DROP OFF button will even work,
	-- so it is the one label in the strip that gets full contrast.
	countLbl.Text = (taken >= MAX_SLOTS) and "ALL BEDS TAKEN"
		or string.format("%d of %d free", MAX_SLOTS - taken, MAX_SLOTS)
	countLbl.TextColor3 = (taken >= MAX_SLOTS) and Color3.fromRGB(255, 176, 158) or C.txt

	if mine then
		featured.Visible = false
		chooser.Visible = false
		emptyLbl.Visible = false
		asleepCard.Visible = true
		fitPanel(BODY_TOP + AS_H)
		subLbl.Text = "Your pet is asleep outside the hut."

		-- Rebuild the big preview only when the pet itself changed -- this function also runs on the 3-second
		-- tick that keeps the timer live, and re-cloning a Union model every 3 seconds would be absurd.
		local sig = string.format("%s:%d:%s:%s:%s", tostring(mine.petId), mine.level or 1,
			tostring(mine.isRare), tostring(mine.skin), tostring(mine.trait))
		if sig ~= listSig then
			listSig = sig
			if asleepVp then spinners[asleepVp] = nil; asleepVp:Destroy() end
			asleepVp = petViewport(asleepVpHolder, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 },
				mine.petId, mine.level, mine.skin, mine.trait, 1.8)
		end

		asleepName.Text = displayNameOf(mine.petId, mine.isRare)
		local age, ageCol = ageName(mine.level or 1)
		asleepAge.Text = age .. "  \xE2\x80\xA2  Age " .. tostring(mine.level or 1)
		asleepAge.BackgroundColor3 = ageCol
		local mins = math.max(0, math.floor((os.time() - (mine.since or os.time())) / 60))
		statTiles[1].Text = (mins < 1) and "just now" or (mins .. " min")
		statTiles[2].Text = tostring(mine.earned or 0)
		statTiles[3].Text = tostring(coinsPerMin(mine.level or 1))
		asleepHint.Text = "\xF0\x9F\x92\xA4  Sleeping pets can't be equipped from the Pet Hub. Wake it up here and it goes straight back with you \xE2\x80\xA2 leave the game and it keeps its bed for 15 more minutes."
	else
		asleepCard.Visible = false

		-- SORTED, not pairs(). inventory is a hash keyed by storage key, so iterating it raw would deal the
		-- cards into a different order on every rebuild.
		-- BEST EARNER FIRST: age decides the payout, so sorting by age puts the pet you should actually drop
		-- off top-left. Rares tie-break above equal-age normals because that is the one you want to show off
		-- in the row of sleeping pets outside.
		local keys = {}
		for skey in pairs(inventory) do keys[#keys + 1] = skey end
		table.sort(keys, function(a, b)
			local A, B = inventory[a], inventory[b]
			if (A.level or 1) ~= (B.level or 1) then return (A.level or 1) > (B.level or 1) end
			if (A.rare and true or false) ~= (B.rare and true or false) then return A.rare and true or false end
			return a < b
		end)

		-- KEEP THE SELECTION IF IT IS STILL VALID. It falls back to keys[1] -- the best napper -- which is what
		-- a fresh open, a traded-away pet and a just-dropped-off pet should all land on.
		if not (selectedKey and inventory[selectedKey]) then selectedKey = keys[1] end

		featured.Visible = (#keys > 0)
		emptyLbl.Visible = (#keys == 0)
		emptyLbl.Text = "You don't have any pets yet!\n\nHatch or find one first, then bring it back here and it can nap while you fly."

		if #keys > 0 then
			paintFeatured(selectedKey, inventory[selectedKey])
		end

		-- THE PICKER, ONLY WHEN THERE IS SOMETHING TO PICK. Rebuilt on the same
		-- signature rule as everything else: this function runs on every roster broadcast from every other
		-- player in the server, and re-cloning one pet model per tile on each of those is not affordable.
		local showChooser = (#keys > 1)
		chooser.Visible = showChooser
		if showChooser then
			local sig = { selectedKey }
			for i, skey in ipairs(keys) do
				local c = inventory[skey]
				sig[i + 1] = string.format("%s:%d:%s:%s:%s", skey, c.level or 1, tostring(c.rare),
					tostring(c.skin), tostring(c.trait))
			end
			sig = table.concat(sig, "|")
			if sig ~= chooseSig then
				chooseSig = sig
				for _, ch in ipairs(chooser:GetChildren()) do
					if ch:IsA("GuiButton") then ch:Destroy() end
				end
				for i, skey in ipairs(keys) do mkThumb(skey, inventory[skey], i, skey == selectedKey) end
				chooser.CanvasSize = UDim2.new(0, #keys * 58 + (#keys - 1) * 8 + 20, 0, 0)
			end
		else
			chooseSig = nil
		end

		-- Height follows whichever piece actually ends lowest, so nothing pads itself out with empty blue.
		if #keys == 0 then
			fitPanel(BODY_TOP + 150)
		elseif showChooser then
			fitPanel(CHOOSE_Y + CHOOSE_H)
		else
			fitPanel(BODY_TOP + FEAT_H)
		end

		subLbl.Text = (taken >= MAX_SLOTS) and "Every bed is taken right now \xE2\x80\x94 check back soon."
			or "Pick a pet to leave here for a nap."
	end

	-- The footer used to restate rules the cards already show. It now answers the question someone actually
	-- opens this panel with -- "which one do I leave?" -- by naming the best earner they own. With a pet
	-- already asleep there is nothing left to choose, so it goes back to stating the rule.
	if mine then
		footLbl.Text = "Coins only tick while you're in the server \xE2\x80\xA2 one bed each, so everyone gets one"
	else
		local bestK, bestL = nil, -1
		for skey, c in pairs(inventory) do
			if (c.level or 1) > bestL then bestK, bestL = skey, c.level or 1 end
		end
		footLbl.Text = bestK
			and string.format("Best napper: %s \xE2\x80\x94 %d coins/min \xE2\x80\xA2 older pets always earn more!",
				displayNameOf(speciesOf(bestK), inventory[bestK].rare), coinsPerMin(bestL))
			or "Older pets earn more \xE2\x80\xA2 coins only tick while you're in the server"
	end
end

--======================================================================
-- OPEN / CLOSE
--======================================================================
-- Shared main-menu manager: opening the house hides the bottom HUD and closes whatever menu was open, so two
-- panels can never sit on top of each other.
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local pgx = player:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end

local function setOpen(open)
	panelOpen = open and true or false
	gui.Enabled = panelOpen
	if panelOpen then
		_G.MainMenuManager.notifyOpened("PetHouse")
		-- Ask for fresh data on the way in: the inventory may be stale (a pet levelled up since the last push)
		-- and the roster may have changed while we were away from the house.
		if PetRequestStateEvent then pcall(function() PetRequestStateEvent:FireServer() end) end
		PetBarnEvent:FireServer("sync")
		renderPanel()
		panel.Size = UDim2.new(0, 640, 0, 476)
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 700, 0, 520) }):Play()
		if _G.applyHudScaling then pcall(_G.applyHudScaling) end
	else
		_G.MainMenuManager.notifyClosed("PetHouse")
	end
end
_G.MainMenuManager.register("PetHouse", function() panelOpen = false; gui.Enabled = false end)

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
wakeBtn.MouseButton1Click:Connect(function()
	local mine = myNapEntry()
	if not mine then return end
	wakeBtn.Text = "..."
	PetBarnEvent:FireServer("take")
	-- Re-equip through PetSystem's own remote so the follower spawns and runs to you. The server has already
	-- freed the bed by the time this lands; if the order flips the worst case is one extra equip broadcast.
	if PetEquipEvent then
		task.delay(0.15, function()
			pcall(function() PetEquipEvent:FireServer(mine.skey or mine.petId) end)
		end)
	end
	task.delay(0.4, function() wakeBtn.Text = "WAKE UP" end)
end)

--======================================================================
-- THE PET HUB, WHILE YOUR PET IS ASLEEP
--======================================================================
-- A pet in a bed is not available to equip. The SERVER already enforces that (PetSystem's equip handler
-- refuses a key that PetBarn reports as napping), but a button that looks live and silently does nothing is
-- worse than no button -- so the Hub card has to SAY it.
--
-- ===== WHY THIS DECORATES THE HUB INSTEAD OF LIVING IN IT =====
-- The Pet Hub is built by PetFollow.client.lua, which is ~7000 lines and sits at Luau's 200-local-per-scope
-- ceiling -- RemotePets documents the same wall and made the same call. So this never edits that script or
-- its instances. It ADDS marks on top of the finished cards, every one of them named "PetHutSleepMark" so
-- the cleanup pass can find and remove them all with no bookkeeping.
--
-- Nothing here destroys or reparents anything PetFollow made. The card's own spinning 3D icon keeps running
-- underneath; the sleeping preview is a SECOND viewport laid over it. That is deliberate: PetFollow drives
-- its icons from its own render loop, and pulling a model out from under that loop is how you turn a
-- cosmetic overlay into somebody else's error spam.
local MARK = "PetHutSleepMark"

-- Build a still, tilted, eyes-shut preview -- the same pose the pet is actually holding out at the hut, so
-- the card and the world agree about what "asleep" looks like.
local function sleepViewport(parent, props, entry)
	local vf = Instance.new("ViewportFrame")
	vf.Name = MARK
	vf.BackgroundColor3 = Color3.fromRGB(12, 40, 96)
	vf.BackgroundTransparency = 0.15
	vf.BorderSizePixel = 0
	vf.Ambient = Color3.fromRGB(120, 140, 180)   -- dimmer than the awake cards: it is night for this pet
	vf.LightColor = Color3.fromRGB(210, 220, 255)
	vf.LightDirection = Vector3.new(-0.3, -1, -0.5)
	for k, v in pairs(props) do vf[k] = v end
	vf.Parent = parent

	local model = buildBody(entry.petId)
	if model then
		if _G.applyPetSkinPreview then pcall(_G.applyPetSkinPreview, model, entry.skin, entry.trait, true) end
		shutEyes(model)
		pcall(function() model:ScaleTo(ageScale(entry.level)) end)
		model.Parent = vf
		local cam = Instance.new("Camera"); vf.CurrentCamera = cam; cam.Parent = vf
		local ext = model:GetExtentsSize()
		model:PivotTo(CFrame.new(0, -ext.Y * 0.12, 0) * CFrame.Angles(0, math.rad(-28), NAP_TILT))
		local dist = math.max(ext.X, ext.Y, ext.Z) * 2.1 + 2
		cam.CFrame = CFrame.lookAt(Vector3.new(0, ext.Y * 0.22, dist), Vector3.new(0, 0, 0))
	end
	return vf
end

local function clearHubMarks(gui)
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == MARK then
			d:Destroy()
		elseif d:IsA("TextButton") then
			-- restore any equip button we relabelled. The card is usually rebuilt from scratch on the next
			-- inventory push, but "usually" is not a guarantee and a button stuck reading SLEEPING forever
			-- would be a genuinely confusing bug to chase.
			local orig = d:GetAttribute("PetHutOrigText")
			if orig then
				d.Text = orig
				d.BackgroundColor3 = d:GetAttribute("PetHutOrigColor") or d.BackgroundColor3
				d:SetAttribute("PetHutOrigText", nil)
				d:SetAttribute("PetHutOrigColor", nil)
			end
		end
	end
end

decorateHub = function()
	local gui = PlayerGui:FindFirstChild("PetInventoryUI")
	if not gui then return end
	clearHubMarks(gui)

	local mine = myNapEntry()
	local skey = mine and (mine.skey or mine.petId)
	if not skey then return end

	-- The owned cards are named by STORAGE KEY and parented straight to the pets ScrollingFrame, so that
	-- pairing identifies a card without needing to know the rest of the Hub's layout.
	local card
	for _, d in ipairs(gui:GetDescendants()) do
		if d.Name == skey and d:IsA("GuiObject") and d.Parent and d.Parent:IsA("ScrollingFrame") then
			card = d; break
		end
	end
	if not card then return end

	-- 1) the sleeping preview, laid over the card's own spinning icon
	local icon = card:FindFirstChild("Icon3D")
	if icon and icon:IsA("GuiObject") then
		local vp = sleepViewport(card, {
			Size = icon.Size, Position = icon.Position, AnchorPoint = icon.AnchorPoint,
			ZIndex = (icon.ZIndex or 1) + 3,
		}, mine)
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = vp
		local z = Instance.new("TextLabel")
		z.Name = MARK; z.BackgroundTransparency = 1; z.Text = "\xF0\x9F\x92\xA4"
		z.Font = Enum.Font.FredokaOne; z.TextSize = 30; z.TextColor3 = Color3.fromRGB(214, 234, 255)
		z.AnchorPoint = Vector2.new(1, 0); z.Position = UDim2.new(1, -8, 0, 4)
		z.Size = UDim2.new(0, 36, 0, 36); z.ZIndex = vp.ZIndex + 1; z.Parent = vp
		local zs = Instance.new("UIStroke"); zs.Color = Color3.fromRGB(8, 28, 70); zs.Thickness = 2; zs.Parent = z
	end

	-- 2) a ribbon across the card so it reads at a glance in the grid
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = MARK
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, 6)
	ribbon.Size = UDim2.new(0.92, 0, 0, 26)
	ribbon.BackgroundColor3 = Color3.fromRGB(58, 96, 168)
	ribbon.Font = Enum.Font.GothamBold; ribbon.TextSize = 13
	ribbon.TextColor3 = Color3.fromRGB(226, 240, 255)
	ribbon.Text = "\xF0\x9F\x92\xA4  ASLEEP IN THE PET HUT"
	ribbon.ZIndex = 20
	ribbon.Parent = card
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = ribbon
	local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(150, 196, 255); rs.Thickness = 1.5; rs.Parent = ribbon

	-- 3) the EQUIP button: relabel it, grey it, and swallow its clicks. PetFollow owns that button's own
	-- click handler and we do not touch it -- a transparent button on top means the handler never fires,
	-- rather than firing into a server that will only reject it.
	local body = card:FindFirstChild("Body")
	local btnRow = body and body:FindFirstChild("Buttons")
	if btnRow then
		for _, b in ipairs(btnRow:GetChildren()) do
			if b:IsA("TextButton") then
				local t = tostring(b.Text):upper()
				if t:find("EQUIP") then
					b:SetAttribute("PetHutOrigText", b.Text)
					b:SetAttribute("PetHutOrigColor", b.BackgroundColor3)
					b.Text = "SLEEPING"
					b.BackgroundColor3 = Color3.fromRGB(104, 116, 134)
					local swallow = Instance.new("TextButton")
					swallow.Name = MARK
					swallow.Size = UDim2.new(1, 0, 1, 0)
					swallow.BackgroundTransparency = 1
					swallow.Text = ""
					swallow.AutoButtonColor = false
					swallow.ZIndex = (b.ZIndex or 1) + 5
					swallow.Parent = b
					swallow.MouseButton1Click:Connect(function()
						if _G.NotifyCenter and _G.NotifyCenter.social then
							pcall(_G.NotifyCenter.social, "This pet is asleep in the Pet Hut \xE2\x80\x94 wake it up there first.")
						end
					end)
					break
				end
			end
		end
	end
end

-- Re-decorate whenever the Hub could have been rebuilt. PetFollow tears down and recreates every card on
-- each inventory push, so a one-shot pass would be wiped by the very next server message.
if PetInventoryEvent then
	PetInventoryEvent.OnClientEvent:Connect(function() task.defer(decorateHub) end)
end
task.spawn(function()
	while true do
		task.wait(2)
		pcall(decorateHub) -- catches rebuilds triggered by anything we don't have a signal for
	end
end)

--======================================================================
-- THE PROMPT + THE FLOATING SIGN
--======================================================================
-- Both are pure UI, so there is nothing for the server to own here, and building them on the client keeps
-- them off the replication budget entirely.
task.spawn(function()
	for _ = 1, 120 do
		houseModel, houseAnchor = findHouse()
		if houseAnchor then break end
		task.wait(1)
	end
	if not houseAnchor then
		warn("[PetBarn] the PetHouse model never appeared -- check that PetBarn.server found the 'pethouse' Part")
		return
	end
	print("[PetBarn] house found at " .. tostring(houseAnchor.Position))
	applyRoster(latestRoster) -- anything that arrived before the house existed can be placed now

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetHousePrompt"
	prompt.ActionText = "Pet Hut"
	prompt.ObjectText = "Leave a pet to nap"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = houseAnchor
	prompt.Triggered:Connect(function() setOpen(true) end)

	-- THE FLOATING NAME. Copied from the campfire's sign (Campfire.server line ~340): a rounded card with a
	-- stroke, AlwaysOnTop, and MaxDistance = 45 so the name appears as you walk up and disappears again once
	-- you are past it. Nothing here polls a distance -- MaxDistance is what does the fading, same as the fire.
	local sign = Instance.new("BillboardGui")
	sign.Name = "PetHouseSign"
	sign.Size = UDim2.fromOffset(220, 60)
	-- Clears the whole roof: the anchor sits at door height (~2.3 above the porch) and the cone plus its peak
	-- lantern top out around 15, so the sign has to start above that or it hangs inside the thatch.
	sign.StudsOffset = Vector3.new(0, 15.5, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = SIGN_DIST
	sign.Adornee = houseAnchor
	sign.Parent = houseAnchor

	local card = mkFrame(sign, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 40, 96),
		BackgroundTransparency = 0.25, BorderSizePixel = 0 })
	mkCorner(card, 10); mkStroke(card, Color3.fromRGB(126, 190, 255), 1.5)
	local lbl = mkLabel(card, { Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3),
		Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.fromRGB(226, 240, 255),
		Text = "\xF0\x9F\x90\xBE Pet Hut\nno pets asleep" })
	mkStroke(lbl, Color3.new(0, 0, 0), 2)

	while true do
		local n = #latestRoster
		local line = (n == 0) and "no pets asleep" or (n == 1 and "1 pet asleep" or (n .. " pets asleep"))
		lbl.Text = "\xF0\x9F\x90\xBE Pet Hut\n" .. line
		if panelOpen and renderPanel then renderPanel() end -- keeps "asleep for N min / earned N" live
		task.wait(3)
	end
end)

-- Ask for the roster once our handler is live. A broadcast that fired before this script connected is simply
-- lost -- the same join-order trap PetSystem's own catch-up documents -- so the beds would render empty until
-- the next change. This closes that window.
task.delay(2, function() pcall(function() PetBarnEvent:FireServer("sync") end) end)
if PetRequestStateEvent then
	task.delay(3, function() pcall(function() PetRequestStateEvent:FireServer() end) end)
end

print("[PetBarn] client ready")
