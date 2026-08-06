--======================================================================
-- NpcLife.client.luau  (LocalScript -> StarterPlayerScripts.DinosaurRealmClient)
--======================================================================
-- THE QUEST GIVERS STOP BEING STATUES.
--
-- Every quest island has a Researcher standing on it, and each one is a clone of the island1
-- `miner` model with every part anchored by NestingNook_NPCs -- so they stand perfectly still,
-- facing whichever way the placement code pointed them, forever. A person who does not move is
-- the most uncanny thing in a world full of things that do: the raptors move, the geysers move,
-- the rain moves, and the one human on the island is furniture.
--
-- Four cues, in order of how much they buy you:
--
--   TURN    they face you when you come near. This is nearly all of it -- being LOOKED AT is what
--           makes something read as aware; the rest is decoration on top.
--   BREATHE a slow rise and fall on the spot, small enough that you would not catch it if you
--           stared, big enough that they are never perfectly static.
--   GREET   one bob when you first walk up, then not again until you have been away. A wave every
--           time you pass is a machine, not a person.
--   IDLE    with nobody near they hop on the spot every few seconds. Somebody perfectly still the
--           moment you look away is a mannequin that got switched on for you.
--
-- CLIENT ONLY, and it only ever touches YAW plus a vertical lift. Tipping a character to look at
-- you is how you get a Researcher leaning over backwards while you stand on a rock above them.
--
-- ===== WHY A NAME LIST AND NOT A SUBSTRING =====
-- The portable kit this came from matches any model with "npc" in its name. Not one NPC in this
-- realm is named that way -- they are `miner`, `FrillRancher`, `DigMiner`, `CoastalFisher`,
-- `MireWatcher`, `RidgeWarden`, `RaptorScout`, `AshWarden` -- so a substring match would adopt
-- exactly nothing and print a cheerful "ready" while doing it. Names are listed explicitly, and
-- matched NORMALISED (lowercased, spaces/underscores/hyphens stripped) so a rename to
-- "Coastal_Fisher" still matches.
--
-- ===== WHAT MUST NEVER BE ADOPTED =====
-- Anything the server animates or moves. This anchors the root and drives the whole pose with
-- PivotTo every frame; point it at a rig with a looping Animation (RedwoodRaptor) or one the
-- server walks around and the two fight -- judder, or a frozen animation. The dinos are not in
-- the list, and NoNpcLife on a model exempts it outright.
--======================================================================

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")
local RunService      = game:GetService("RunService")
local player          = Players.LocalPlayer

-- ===== CONFIG -- the only realm-specific lines in the file =====
-- The island quest givers. island1's `miner` is the source model the rest are cloned from by
-- NestingNook_NPCs.setupIslandQuestNPC, so it is a real NPC in its own right and is listed too.
-- NOT listed, deliberately: dino1 (the baby dino -- a large static prop the QuestGate feeds),
-- MamaDino, and every dinosaur rig the server drives.
local NPC_NAMES = {
	"miner",           -- island1  Nesting Nook
	"FrillRancher",    -- island2  Fern Frontier
	"DigMiner",        -- island3  Fossil Frontier
	"CoastalFisher",   -- island4  Coastal Crossing
	"MireWatcher",     -- island5  Misty Mire
	"RidgeWarden",     -- island6  Redwood Ridge
	"RaptorScout",     -- island7  Raptor Ridge
	"AshWarden",       -- island11 Volcanic Vista
}
local OPT_IN_ATTR = "QuestNpc"    -- ...or set this attribute on a model to adopt it without editing this list
local SKIP_ATTR   = "NoNpcLife"   -- set this to exempt a model (animated or server-driven rigs)

local NOTICE      = 34      -- studs at which they turn toward you
local GREET_AT    = 16      -- studs at which they bob hello
local FORGET_AT   = 60      -- walk this far and they will greet you again next time
local RESCAN      = 4       -- seconds between sweeps while any listed NPC is still missing
local IDLE_RESCAN = 30      -- ...and once they have all been found
local ADOPT_GRACE = 12      -- seconds a model must have been visible before adoption (see below)
local DEBUG_CMD   = "/npc"  -- chat command that prints what it has found

local function norm(s) return (tostring(s):lower():gsub("[%s_%-]", "")) end

local WANTED = {}
local WANTED_COUNT = 0
for _, n in ipairs(NPC_NAMES) do
	if not WANTED[norm(n)] then WANTED[norm(n)] = true; WANTED_COUNT += 1 end
end

local npcs = {}
local adoptedNames = {}                               -- normalised name -> true, to know when to stop sweeping
local adoptedCount = 0
local firstSeen = setmetatable({}, { __mode = "k" })  -- model -> os.clock() when we first saw it
local nextScan = 0

local function rootOf(m)
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return m.PrimaryPart or m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
		or m:FindFirstChildWhichIsA("BasePart")
end

-- IS THE SERVER FINISHED WITH IT?
--
-- We capture the NPC's home pose ONCE and then own its pivot for the rest of the session. Capture
-- it too early and we have latched onto wherever the clone happened to spawn -- and
-- setupIslandQuestNPC parents the model first and THEN raycasts the ground and calls
-- placeModelBottomAt, so a model that exists is not yet a model that has been PLACED. Adopt at the
-- wrong moment and this script cheerfully drags the Researcher back to the spot it was cloned at.
--
-- The prompt is the tell: addPrompt runs after placement, so a ProximityPrompt inside the model
-- means the server is done with it. ADOPT_GRACE is the backstop for anything placed by hand in
-- Studio, which never gets a prompt at all.
local function isSettled(m)
	if m:FindFirstChildWhichIsA("ProximityPrompt", true) then return true end
	local t = firstSeen[m]
	if not t then firstSeen[m] = os.clock(); return false end
	return (os.clock() - t) >= ADOPT_GRACE
end

local function adopt(m)
	if m:GetAttribute("NpcLife") then return end
	if m:GetAttribute(SKIP_ATTR) then return end
	if not isSettled(m) then return end
	local root = rootOf(m)
	if not root then return end
	m:SetAttribute("NpcLife", true)

	-- ANCHOR THE ROOT FIRST. These are Humanoid rigs, and setting the CFrame of an unanchored root
	-- every frame is a fight you lose: the Humanoid and the physics solver both write to it after
	-- you do, so the pose is overwritten before it is ever drawn. (Every part of these particular
	-- NPCs is already anchored server-side, so this is usually a no-op -- but it is what makes the
	-- script work on a rig that is not.) Client-side only: the server still owns the model, so no
	-- other player sees a thing.
	if not root.Anchored then
		root.Anchored = true
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = false end   -- or it turns itself back the moment we turn it
	end

	-- home is measured the same way it is applied: by the model PIVOT, because PivotTo moves the
	-- whole rig and a model's pivot is not its root part
	local base = m:GetPivot()
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, 1) end
	local home = CFrame.lookAt(base.Position, base.Position + flat.Unit)

	npcs[#npcs + 1] = {
		model = m, root = root, home = home,
		yaw = 0, greeted = false, bob = 0, jump = 0, nextJump = math.random() * 1.5,
		phase = math.random() * 6.28,
	}
	-- PUBLISH THE HOME POSE. From here on this NPC's pivot is ours -- it is lifted by up to 1.5 studs
	-- mid-hop and turned up to 180 degrees toward the player -- so any other script that reads the NPC's
	-- transform as a fixed piece of world geometry is now reading a moving target. Two do:
	-- BurritoDig places the shovel barrel 4 studs along the DigMiner's LookVector, and MosquitoQuest
	-- takes the bottom of the MireWatcher's bounding box as island5's true ground height. Both read this
	-- attribute in preference to the live pivot; it is nil until adoption, which is exactly when the live
	-- pivot is still trustworthy.
	m:SetAttribute("NpcHome", home)   -- client-local (attributes set on the client do not replicate)
	local key = norm(m.Name)
	if WANTED[key] and not adoptedNames[key] then adoptedNames[key] = true; adoptedCount += 1 end
	print(("[NpcLife] adopted '%s'  root=%s"):format(m:GetFullName(), root.Name))
end

-- A full Workspace:GetDescendants() is not free on a map this size, and the Researchers are cloned in
-- during the first few seconds and then never again. Sweep briskly until every listed name has been
-- adopted, then drop to a slow heartbeat that only exists to catch an NPC rebuilt mid-session or a
-- model opted in by attribute.
local function sweep()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and (WANTED[norm(d.Name)] or d:GetAttribute(OPT_IN_ATTR)) then
			adopt(d)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt or 0.016, 0.05)
	local now = os.clock()
	if now >= nextScan then
		nextScan = now + ((adoptedCount >= WANTED_COUNT) and IDLE_RESCAN or RESCAN)
		sweep()          -- islands stream in and the Researchers are cloned in at run time, so keep
	end                  -- looking rather than look once

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for i = #npcs, 1, -1 do
		local n = npcs[i]
		if not (n.model.Parent and n.root.Parent) then
			table.remove(npcs, i)
		else
			local here = n.home.Position
			local d = (hrp.Position - here).Magnitude

			-- 1. TURN. Only when you are close enough to be worth noticing, and eased rather than
			-- snapped -- a head that whips round reads as a turret.
			local want = 0
			if d <= NOTICE then
				local to = hrp.Position - here
				local flat = Vector3.new(to.X, 0, to.Z)
				if flat.Magnitude > 0.5 then
					local target = CFrame.lookAt(here, here + flat.Unit)
					-- the yaw difference between home and facing you, as a signed angle
					local rel = n.home:ToObjectSpace(target)
					want = math.atan2(-rel.LookVector.X, -rel.LookVector.Z)
				end
			end
			n.yaw += (want - n.yaw) * math.min(1, dt * 6.5)

			-- 2. BREATHE. A slow rise and fall so they are never perfectly still.
			local lift = math.sin(now * 1.7 + n.phase) * 0.11

			-- 3. GREET. One bob, then never again until you have left and come back.
			if not n.greeted and d <= GREET_AT then
				n.greeted = true
				n.bob = 1
			elseif n.greeted and d > FORGET_AT then
				n.greeted = false
			end
			if n.bob > 0 then
				n.bob = math.max(0, n.bob - dt * 2.4)
				lift += math.sin((1 - n.bob) * math.pi) * 0.55
			end

			-- 4. MESSING ABOUT. With nobody watching they hop on the spot every few seconds. It only
			-- ever happens out of NOTICE range, so you never catch them at it -- which is the point:
			-- you catch the tail end of it as you walk up.
			if d > NOTICE then
				n.nextJump -= dt
				if n.nextJump <= 0 and n.jump <= 0 then
					n.jump = 1
					n.nextJump = 0.7 + math.random() * 1.2
				end
			end
			if n.jump > 0 then
				n.jump = math.max(0, n.jump - dt * 2.2)
				-- a real hop: up fast, down faster, not a sine wobble
				local u = 1 - n.jump
				lift += math.sin(u * math.pi) ^ 0.7 * 1.5
			end

			n.model:PivotTo(n.home * CFrame.new(0, lift, 0) * CFrame.Angles(0, n.yaw, 0))
		end
	end
end)

-- /npc -- what it has found and what it thinks it is doing. A silent script that loaded fine and
-- moves nothing is impossible to diagnose from the outside.
local function npcDiag(msg)
	if tostring(msg or ""):lower():sub(1, #DEBUG_CMD) ~= DEBUG_CMD then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	print(("[NpcLife] ---- %d adopted ----"):format(#npcs))
	for _, n in ipairs(npcs) do
		print(("  %-46s root=%-18s dist=%s yaw=%.2f")
			:format(n.model:GetFullName(), n.root.Name,
				hrp and ("%.0f"):format((hrp.Position - n.home.Position).Magnitude) or "?", n.yaw))
	end
	-- name the ones still missing: "0 adopted" on its own does not say whether the models are absent,
	-- still streaming, or simply named something other than what is listed above
	local missing = {}
	for _, n in ipairs(NPC_NAMES) do
		if not adoptedNames[norm(n)] then missing[#missing + 1] = n end
	end
	if #missing > 0 then
		print("  not yet adopted: " .. table.concat(missing, ", ")
			.. "  (not streamed in, not placed yet, or renamed)")
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then npcDiag(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(npcDiag) end)

print(("[NpcLife] ready -- Researchers turn, breathe and say hello once (%s to check)"):format(DEBUG_CMD))
