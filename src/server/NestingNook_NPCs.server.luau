--!strict
-- NestingNook_NPCs.server.luau
-- Wires the "Nesting Nook" quest onto the user's existing models:
--   * dino1  - the baby dino, moved onto the DinoPlacement marker
--   * miner  - the quest giver, left where it sits
-- Each LostEgg (spawned by NestingNook_Setup) gets a "Rock Egg Free" ProximityPrompt.
-- That prompt does NOT hand the egg over -- it starts a 15s minigame on the client
-- (NestingNookEggs.client.luau) over the EggCarry remote, and only a claim that comes
-- back no sooner than the floor returns the egg to the nest ring. Shared state lives in
-- ReplicatedStorage.NestingNook so both scripts stay in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PickupFloor = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("PickupFloor")) -- the 15s-per-collectible floor
-- wait for IslandLayout to space the islands first, so NPCs/spawns land at the NEW island positions
do local t0 = os.clock(); while not _G.islandsPositioned and os.clock() - t0 < 5 do task.wait() end end

local SPEECH_LIFETIME = 9 -- seconds before a speech bubble auto-hides
local RING_RADIUS = 3.5 -- how far returned eggs sit from the nest center
local DIALOGUE_CLOSE_DISTANCE = 8 -- studs; conversation closes when the player walks this far away
local LOOK_RADIUS = 20 -- a player within this many studs gets looked at

----------------------------------------------------------------------
-- Wait for the shared quest state published by the setup script
----------------------------------------------------------------------

local folder = ReplicatedStorage:WaitForChild("NestingNook")
if not folder:GetAttribute("Ready") then
	folder:GetAttributeChangedSignal("Ready"):Wait()
end

local totalEggsValue = folder:WaitForChild("TotalEggs") :: IntValue
local eggsReturnedValue = folder:WaitForChild("EggsReturned") :: IntValue

local nestCenter = Vector3.new(
	folder:GetAttribute("NestX") :: number,
	folder:GetAttribute("NestY") :: number,
	folder:GetAttribute("NestZ") :: number
)

-- Quest gate: players must talk to the miner ("the Researcher") before they can
-- collect eggs. `questClaimed` tracks who has; the RemoteEvent tells a client to
-- show the "talk to the Researcher first" banner + guide arrow.
local questClaimed: { [Player]: boolean } = {}

local questGate: RemoteEvent
local existingGate = folder:FindFirstChild("QuestGate")
if existingGate and existingGate:IsA("RemoteEvent") then
	questGate = existingGate
else
	local re = Instance.new("RemoteEvent")
	re.Name = "QuestGate"
	re.Parent = folder
	questGate = re
end

-- EggCarry: the pickup floor for the LostEggs (see DinosaurRealm/PickupFloor). Island 1
-- runs ISLAND1_EGG_SECONDS = 10.5s, 30% short of the game-wide 15s standard.
--
-- Taking an egg used to be ONE prompt trigger -- five free grabs, and island1's whole
-- quest was a walk. It now opens a client minigame (NestingNookEggs.client.luau): the
-- server fires this remote to START one, and the client fires it back when the rocking
-- is finished.
--
-- The client declares success, so the SERVER keeps the clock. carryStartedAt records
-- when each egg's minigame was handed out, and a claim that comes back faster than the
-- floor is refused. That means the floor holds even against a client that skips the UI --
-- the panel is the presentation, this table is the rule.
local eggCarry: RemoteEvent
local existingCarry = folder:FindFirstChild("EggCarry")
if existingCarry and existingCarry:IsA("RemoteEvent") then
	eggCarry = existingCarry
else
	local re = Instance.new("RemoteEvent")
	re.Name = "EggCarry"
	re.Parent = folder
	eggCarry = re
end

-- [player][egg] = os.clock() when that egg's minigame was handed out
local carryStartedAt: { [Player]: { [Instance]: number } } = {}
local CARRY_TOLERANCE = 0.5 -- seconds of slack for latency + frame jitter

Players.PlayerRemoving:Connect(function(plr)
	questClaimed[plr] = nil
	carryStartedAt[plr] = nil
end)

----------------------------------------------------------------------
-- Generic helpers (work for BasePart or Model eggs)
----------------------------------------------------------------------

local function getSize(obj: Instance): Vector3
	if obj:IsA("BasePart") then
		return obj.Size
	elseif obj:IsA("Model") then
		local _, size = obj:GetBoundingBox()
		return size
	end
	return Vector3.new(2, 2, 2)
end

-- The read half of setPivot below. This file had setPivot and getSize but NEVER
-- getPivot, and the EggCarry claim handler calls it for the distance check -- so
-- every completed egg died on "attempt to call a nil value". It went unnoticed
-- because the rocking minigame could not finish either (it tested `fill >= 1`
-- against a value clamped to a ceiling it could only ever REACH), so the claim
-- never got that far. Fixing the minigame is what exposed this.
local function getPivot(obj: Instance): CFrame
	if obj:IsA("BasePart") then
		return obj.CFrame
	elseif obj:IsA("Model") then
		return obj:GetPivot()
	end
	return CFrame.new()
end

local function setPivot(obj: Instance, cf: CFrame)
	if obj:IsA("BasePart") then
		obj.CFrame = cf
	elseif obj:IsA("Model") then
		obj:PivotTo(cf)
	end
end

-- Bottom-align an object to a reference block the SAME way LostEggs align to
-- their EggPlacement markers in NestingNook_Setup:
--   refBottom   = refCenterY - refSizeY/2
--   targetBottom (object's bounding-box bottom) = refBottom
-- so the object rests at the same ground contact as the reference's bottom.
-- Returns the reference's bottom Y (the surface the object should sit on).
local function referenceBottomY(refCenterY: number, refSizeY: number): number
	return refCenterY - refSizeY / 2
end

-- Move a Model (keeping its current rotation) so the bottom of its bounding box
-- sits exactly at `bottomY`, keeping the given X/Z. Robust to the model's pivot
-- not being at its bounding-box center. Returns the achieved bounding-box bottom.
local function placeModelBottomAt(model: Model, x: number, z: number, bottomY: number, rotation: CFrame): number
	-- Position at the target X/Z with the desired rotation first.
	local p = model:GetPivot().Position
	model:PivotTo(CFrame.new(x, p.Y, z) * rotation)
	-- Then correct Y so the bbox bottom lands on bottomY.
	local bcf, bsize = model:GetBoundingBox()
	local currentBottom = bcf.Position.Y - bsize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, bottomY - currentBottom, 0))
	local bcf2, bsize2 = model:GetBoundingBox()
	return bcf2.Position.Y - bsize2.Y / 2
end

-- World-space bottom Y of a single part (orientation-aware).
local function partBottomY(p: BasePart): number
	local cf = p.CFrame
	local s = p.Size
	local halfY = 0.5 * (math.abs(cf.RightVector.Y) * s.X
		+ math.abs(cf.UpVector.Y) * s.Y
		+ math.abs(cf.LookVector.Y) * s.Z)
	return p.Position.Y - halfY
end

-- The model's real "feet" level: the lowest part bottom, but skipping isolated
-- stray parts that sit far below the main cluster, so a stray low part doesn't
-- make the model hover when grounded. Returns (feetY, lowestY, lowestPart).
local function feetLevel(model: Model, clusterGap: number): (number, number, BasePart?)
	local entries: { { y: number, part: BasePart } } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(entries, { y = partBottomY(d), part = d })
		end
	end
	if #entries == 0 then
		return 0, 0, nil
	end
	table.sort(entries, function(a, b)
		return a.y < b.y
	end)
	-- Walk up from the lowest part until two consecutive bottoms are within
	-- clusterGap (the start of the real foot cluster).
	local feet = entries[1].y
	for i = 1, #entries - 1 do
		if entries[i + 1].y - entries[i].y <= clusterGap then
			feet = entries[i].y
			break
		end
	end
	return feet, entries[1].y, entries[1].part
end

-- Move a Model (keeping rotation) so its FEET cluster rests on `groundY` at the
-- given X/Z. Robust to stray low parts. Returns (achievedFeetY, lowestY).
local function placeModelFeetAt(model: Model, x: number, z: number, groundY: number, rotation: CFrame, clusterGap: number): (number, number)
	local p = model:GetPivot().Position
	model:PivotTo(CFrame.new(x, p.Y, z) * rotation)
	local feet = feetLevel(model, clusterGap)
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - feet, 0))
	local feet2, lowest2 = feetLevel(model, clusterGap)
	return feet2, lowest2
end

----------------------------------------------------------------------
-- Remove leftover NPCs from older versions of this script: the procedural
-- BabyDino/Archaeologist, and any "Brachiosaurus" models (anywhere in the
-- tree). Never touches dino1, miner, or the nest eggs.
----------------------------------------------------------------------

for _, inst in ipairs(Workspace:GetDescendants()) do
	if inst:IsA("Model") and (inst.Name == "BabyDino" or inst.Name == "Archaeologist" or inst.Name == "Brachiosaurus") then
		inst:Destroy()
	end
end

----------------------------------------------------------------------
-- GUI / model helpers
----------------------------------------------------------------------

-- Find a Model by exact name anywhere under Workspace.
local function findModel(name: string): Model?
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc.Name == name then
			return desc
		end
	end
	return nil
end

-- Largest BasePart in a model (by volume).
local function largestBasePart(model: Model): BasePart?
	local best: BasePart? = nil
	local bestVol = -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVol then
				bestVol = v
				best = d
			end
		end
	end
	return best
end

-- Ensure a model has a PrimaryPart so PivotTo works; falls back to the largest part.
local function ensurePrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local part = largestBasePart(model)
	if part then
		model.PrimaryPart = part
	end
	return part
end

-- Pick a head-like BasePart to host the GUI/prompt, else the primary/largest part.
local function pickAdornee(model: Model): BasePart?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "head", 1, true) then
			return d
		end
	end
	return model.PrimaryPart or largestBasePart(model)
end

-- Remove any NestingNook-added adornments so re-runs don't stack duplicates.
local function clearAdornments(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "NestingNookTalk" or d.Name == "NameLabel" or d.Name == "SpeechBubble" then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayName = ""                                              -- blank the overhead name (was "Dummy")
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- hide the name + health bar ENTIRELY
			d.NameDisplayDistance = 0
			d.HealthDisplayDistance = 0
		end
	end
end

-- Floating name label above an NPC.
-- Floating name label. `size`/`textSize`/`worldYOffset` are optional overrides;
-- when `worldYOffset` is given the label is offset in WORLD space (always up),
-- so it can sit above the top of a model regardless of orientation.
local function makeNameLabel(adornee: BasePart, text: string, size: UDim2?, worldYOffset: number?, textSize: number?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameLabel"
	bb.Adornee = adornee
	bb.Size = size or UDim2.new(0, 200, 0, 44)
	if worldYOffset then
		bb.StudsOffsetWorldSpace = Vector3.new(0, worldYOffset, 0)
	else
		bb.StudsOffset = Vector3.new(0, 3, 0)
	end
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60 -- only show the NPC name when you're near it (hidden from other islands)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	if textSize then
		label.TextScaled = false
		label.TextSize = textSize
	else
		label.TextScaled = true
	end
	label.Parent = bb

	bb.Parent = adornee
end

-- The name tag and the speech bubble fight for the same patch of screen: the name
-- sits at +3 studs and the bubble at +5.5, and the bubble is 150px tall, so its
-- lower edge lands right on top of the name. Hide the name for as long as the NPC
-- is actually talking, and put it back the moment the bubble goes.
local function setNameVisible(adornee: BasePart, visible: boolean)
	local nl = adornee:FindFirstChild("NameLabel")
	if nl and nl:IsA("BillboardGui") then
		nl.Enabled = visible
	end
end

-- Rounded white speech bubble that auto-hides after SPEECH_LIFETIME seconds.
local function hideSpeech(adornee: BasePart)
	local prev = adornee:FindFirstChild("SpeechBubble")
	if prev then
		prev:Destroy()
	end
	setNameVisible(adornee, true)
end

-- Show a speech bubble. If `persist` is true it stays until replaced/hidden
-- (used for paged dialogue advanced with E); otherwise it auto-hides. `footer`
-- adds a small hint line (e.g. "[E] next").
local function showSpeech(adornee: BasePart, text: string, persist: boolean?, footer: string?)
	hideSpeech(adornee)

	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.fromRGB(35, 35, 35)
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = frame

	local sizer = Instance.new("UITextSizeConstraint")
	sizer.MaxTextSize = 22
	sizer.Parent = label

	if footer then
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.fromScale(1, 0.2)
		hint.Position = UDim2.fromScale(0, 0.8)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.FredokaOne
		hint.Text = footer
		hint.TextColor3 = Color3.fromRGB(130, 130, 130)
		hint.TextScaled = true
		hint.Parent = frame
		local hsizer = Instance.new("UITextSizeConstraint")
		hsizer.MaxTextSize = 14
		hsizer.Parent = hint
	end

	bb.Parent = adornee
	setNameVisible(adornee, false)   -- talking now: get the name out from under the bubble

	-- Auto-hide unless this is a persistent (paged) bubble.
	if not persist then
		task.delay(SPEECH_LIFETIME, function()
			-- the Parent/Name guard keeps this from destroying a NEWER bubble that
			-- replaced ours, so the name is only restored when OUR bubble is the one
			-- still up -- otherwise a fresh line would lose its name-hiding
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then
				bb:Destroy()
				setNameVisible(adornee, true)
			end
		end)
	end
end

local function addPrompt(part: BasePart, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

----------------------------------------------------------------------
-- Locate the DinoPlacement marker (BasePart, name contains "dino" + "plac")
----------------------------------------------------------------------

-- SEARCH ISLAND1 FIRST. This is the NESTING NOOK dino -- it belongs on island1.
--
-- This used to scan all of Workspace and take the first "dino*plac*" it hit. The moment
-- a 'dinoplacement' part appeared on island6 (for the Redwood raptors), that one won the
-- race and the Mama Dino was built 14,000 studs up on Redwood Ridge:
--     Placed dino1 on DinoPlacement marker Workspace.island6.island6.dinoplacement
--     ground = 14182.256          <- island6's altitude, not island1's
-- ...which quietly removes the Mama Dino from the island1 quest entirely.
--
-- Scoping to island1 first makes that impossible; the Workspace-wide scan is only a
-- last resort now, and it says so out loud when it fires.
local function findDinoMarker(): BasePart?
	local function scan(root: Instance?): BasePart?
		if not root then return nil end
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("BasePart") then
				local n = string.lower(desc.Name)
				if string.find(n, "dino", 1, true) and string.find(n, "plac", 1, true) then
					return desc
				end
			end
		end
		return nil
	end

	local island1 = Workspace:FindFirstChild("island1")
	local onIsland1 = scan(island1)
	if onIsland1 then return onIsland1 end

	local anywhere = scan(Workspace)
	if anywhere then
		warn(("[NestingNook] no DinoPlacement marker on island1 -- falling back to '%s'. "
			.. "The Mama Dino belongs on island1; add a 'DinoPlacement' part there.")
			:format(anywhere:GetFullName()))
	end
	return anywhere
end

----------------------------------------------------------------------
-- Baby Dino: use the user's existing "dino1" model. Anchor it, place it on
-- the DinoPlacement marker (static, no animation), and host the quest GUI.
----------------------------------------------------------------------

local function setupBabyDino(): (Model?, BasePart?)
	local model = findModel("dino1")
	if not model then
		warn("[NestingNook] Model 'dino1' not found in Workspace. Baby Dino quest logic skipped.")
		return nil, nil
	end
	print("[NestingNook] Found dino1: " .. model:GetFullName())

	-- Remove any leftover neck/body filler balls from earlier versions.
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "NeckFiller" then
			d:Destroy()
		end
	end

	ensurePrimaryPart(model)
	clearAdornments(model)

	-- Anchor every part so the dino stays put (static, no movement).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	-- Place dino1 at the DinoPlacement marker's X/Z, then drop it so its FEET
	-- (the lowest cluster of parts, ignoring stray low parts) rest on the actual
	-- ground there. This stops it hovering when the bounding box is taller than
	-- the visible body. Ground is found by a downward ray; falls back to marker
	-- bottom if nothing is hit.
	local CLUSTER_GAP = 2.0 -- studs; parts further below the cluster are treated as strays
	local rotation = model:GetPivot().Rotation
	local marker = findDinoMarker()
	if marker then
		local mc = marker.Position
		local markerBottom = referenceBottomY(mc.Y, marker.Size.Y)

		-- Raycast straight down to find the ground under the marker (ignore the
		-- dino and the marker so neither blocks the ray).
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { model, marker }
		local hit = Workspace:Raycast(Vector3.new(mc.X, mc.Y + 200, mc.Z), Vector3.new(0, -1000, 0), rp)
		local groundY = hit and hit.Position.Y or markerBottom

		local feetY, lowestY = placeModelFeetAt(model, mc.X, mc.Z, groundY, rotation, CLUSTER_GAP)
		marker.Transparency = 1
		marker.CanCollide = false

		local _, _, lowestPart = feetLevel(model, CLUSTER_GAP)
		print(("[NestingNook] Placed dino1 on DinoPlacement marker %s"):format(marker:GetFullName()))
		print(("[NestingNook] ground = %s, feet rest at %.3f, lowest part bottom = %.3f%s")
			:format(
				hit and string.format("%.3f", groundY) or ("none (marker bottom " .. string.format("%.3f", markerBottom) .. ")"),
				feetY,
				lowestY,
				(lowestPart and (feetY - lowestY) > 0.05) and (" [stray below feet: " .. lowestPart.Name .. "]") or ""
			))
	else
		-- Fallback: rest it on the nest-center height.
		local feetY = placeModelFeetAt(model, nestCenter.X, nestCenter.Z, nestCenter.Y, rotation, CLUSTER_GAP)
		warn(("[NestingNook] No 'DinoPlacement' marker found; placed dino1 at the nest center (feet at %.3f)")
			:format(feetY))
	end

	local adornee = pickAdornee(model)
	if not adornee then
		warn("[NestingNook] dino1 has no BasePart to host GUI/prompt. Baby Dino quest logic skipped.")
		return model, nil
	end

	-- (No overhead name label on the dino.)
	local prompt = addPrompt(adornee, "Talk", "Baby Dino")
	prompt.Name = "NestingNookTalk"

	return model, adornee
end

----------------------------------------------------------------------
-- Quest giver: use the user's "miner" model, placed ~6 studs from spawn
----------------------------------------------------------------------

local function setupMiner(): (Model?, BasePart?)
	local model = findModel("miner")
	if not model then
		warn("[NestingNook] Model 'miner' not found in Workspace. Quest-giver logic skipped.")
		return nil, nil
	end

	ensurePrimaryPart(model)
	clearAdornments(model)

	-- Move the miner next to the SpawnLocation. It stands ON the spawn pad, so
	-- bottom-align its bounding box to the spawn's TOP surface (the ground there),
	-- using the same robust bottom-align helper so it never floats or sinks.
	local island1 = Workspace:FindFirstChild("island1")
	local oldSpawn = island1 and island1:FindFirstChildWhichIsA("SpawnLocation", true)
	if oldSpawn then
		-- the miner stands where the island1 spawn pad was; REMOVE that old (black) spawn entirely.
		-- (players spawn on the spawn point you placed on island3 -- left untouched.)
		local sPos = oldSpawn.Position
		local spawnTopY = oldSpawn.Position.Y + oldSpawn.Size.Y / 2
		_G.island1SpawnCF = oldSpawn.CFrame; _G.island1SpawnSize = oldSpawn.Size -- save the real pad so the player spawn reuses it
		oldSpawn:Destroy()
		-- 6 studs farther ("back") + 1 down, facing back toward where the pad was
		local awayDir = Vector3.new(6, 0, 4).Unit
		local spot = sPos + Vector3.new(6, 0, 4) + awayDir * 6
		local rotation = CFrame.lookAt(spot, Vector3.new(sPos.X, spot.Y, sPos.Z)).Rotation
		local achievedBottom = placeModelBottomAt(model, spot.X, spot.Z, spawnTopY - 1, rotation)  -- 1 stud down
		print(("[NestingNook] miner placed; old spawn removed (old top = %.3f, miner bottom = %.3f)")
			:format(spawnTopY, achievedBottom))
	else
		warn("[NestingNook] No SpawnLocation found; leaving miner at its current position.")
	end

	local adornee = pickAdornee(model)
	if not adornee then
		warn("[NestingNook] miner has no BasePart to host GUI/prompt. Quest-giver logic skipped.")
		return model, nil
	end

	makeNameLabel(adornee, "Quest Giver")
	local prompt = addPrompt(adornee, "Talk", "Quest Giver")
	prompt.Name = "NestingNookTalk"

	return model, adornee
end

----------------------------------------------------------------------
-- Dino idle animation: only the Head and Tail groups move (the body and
-- legs stay anchored/static), plus blinking. Each moving group is welded
-- internally and pivoted by driving its anchored root part's CFrame.
----------------------------------------------------------------------

local TWO_PI = math.pi * 2

local function shortestAngle(a: number): number
	return ((a + math.pi) % TWO_PI) - math.pi
end

local function findChildModel(parent: Instance, name: string): Model?
	for _, d in ipairs(parent:GetDescendants()) do
		if d:IsA("Model") and d.Name == name then
			return d :: Model
		end
	end
	return nil
end

-- Split a group into a FIXED base (parts within `baseDepth` studs of the body
-- join, measured along `axisDir`) and a MOVING upper section. The fixed base is
-- left anchored as part of the static body so the body->group join never moves;
-- the moving section is welded rigid around an anchored root that the script
-- pivots from the TOP of the fixed base. Returns the moving root, that pivot,
-- its rest CFrame, and a sampled group color (for fillers) - or nil.
type BendInfo = { root: BasePart, pivot: Vector3, rest: CFrame, color: Color3 }

local function makeBendingGroup(group: Model, basePivot: Vector3, axisDir: Vector3, baseDepth: number, label: string): BendInfo?
	local fixed: { BasePart } = {}
	local moving: { BasePart } = {}
	for _, d in ipairs(group:GetDescendants()) do
		if d:IsA("BasePart") then
			local proj = (d.Position - basePivot):Dot(axisDir)
			if proj <= baseDepth then
				table.insert(fixed, d)
			else
				table.insert(moving, d)
			end
		end
	end

	-- Report the fixed-base parts.
	local fixedNames = {}
	for _, p in ipairs(fixed) do
		table.insert(fixedNames, p.Name)
	end
	print(("[NestingNook] dino1 %s fixed-base parts (%d): %s"):format(label, #fixed, table.concat(fixedNames, ", ")))

	if #moving == 0 then
		return nil
	end

	-- Largest moving part is the driven root.
	local root: BasePart = moving[1]
	local bestVol = -1
	for _, p in ipairs(moving) do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if v > bestVol then
			bestVol = v
			root = p
		end
	end

	for _, p in ipairs(moving) do
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = root
			p.Anchored = false
		end
	end
	root.Anchored = true

	-- Fixed base stays anchored (part of the body).
	for _, p in ipairs(fixed) do
		p.Anchored = true
	end

	local color = (#fixed > 0 and fixed[1].Color) or root.Color
	return {
		root = root,
		pivot = basePivot + axisDir * baseDepth, -- bend from the top of the fixed base
		rest = root.CFrame,
		color = color,
	}
end

local function setupDinoIdle(dino: Model)
	local rng = Random.new()

	-- The dino's world front (it faces -Z) for look-at math.
	local frontRaw = dino:GetPivot().LookVector
	local headFront = Vector3.new(frontRaw.X, 0, frontRaw.Z)
	headFront = headFront.Magnitude > 1e-3 and headFront.Unit or Vector3.new(0, 0, -1)

	local BASE_DEPTH = 1.5 -- how much of the tail near the body join stays fixed

	-- HEAD: the "Neck" part bridges body and head. Weld the Head group rigid to
	-- the Neck part and rotate the combined Neck+Head as one unit around the
	-- bottom of the Neck (where it meets the body), which stays planted.
	local neckPart: BasePart? = nil
	for _, d in ipairs(dino:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Neck" then
			neckPart = d
			break
		end
	end
	local headGroup = findChildModel(dino, "Head")
	print(("[NestingNook] dino1 Neck part %s; Head group %s.")
		:format(neckPart and "found" or "NOT found", headGroup and "found" or "NOT found"))

	local headRoot: BasePart? = nil
	local headPivot: Vector3 = Vector3.zero
	local headRest: CFrame = CFrame.new()
	if neckPart then
		-- Weld the Head group rigid to the Neck (Neck is the driven root).
		if headGroup then
			for _, d in ipairs(headGroup:GetDescendants()) do
				if d:IsA("BasePart") then
					local w = Instance.new("WeldConstraint")
					w.Part0 = neckPart
					w.Part1 = d
					w.Parent = neckPart
					d.Anchored = false
				end
			end
		end
		neckPart.Anchored = true

		-- Pivot = bottom of the Neck part (lowest point, centered X/Z), robust to
		-- the part's orientation.
		local cf = neckPart.CFrame
		local s = neckPart.Size
		local halfY = 0.5 * (math.abs(cf.RightVector.Y) * s.X
			+ math.abs(cf.UpVector.Y) * s.Y
			+ math.abs(cf.LookVector.Y) * s.Z)
		headPivot = Vector3.new(neckPart.Position.X, neckPart.Position.Y - halfY, neckPart.Position.Z)
		headRoot = neckPart
		headRest = neckPart.CFrame
		print(("[NestingNook] dino1 head motion enabled - neck-base pivot at (%.2f, %.2f, %.2f).")
			:format(headPivot.X, headPivot.Y, headPivot.Z))
	else
		print("[NestingNook] dino1 has no 'Neck' part - head motion skipped.")
	end

	-- TAIL group: keeps its own fixed-base sway from its body-join pivot.
	local tailGroup = findChildModel(dino, "Tail")
	local tailRoot: BasePart? = nil
	local tailPivot: Vector3 = Vector3.zero
	local tailRest: CFrame = CFrame.new()
	if tailGroup then
		local bcf, bsize = tailGroup:GetBoundingBox()
		local tailJoin = (bcf * CFrame.new(0, 0, -bsize.Z / 2)).Position -- front-center = body join
		local backAxis = bcf:VectorToWorldSpace(Vector3.new(0, 0, 1)).Unit -- toward the tip
		local tb = makeBendingGroup(tailGroup, tailJoin, backAxis, BASE_DEPTH, "Tail")
		if tb then
			tailRoot = tb.root
			tailPivot = tb.pivot
			tailRest = tb.rest
			print("[NestingNook] dino1 Tail: fixed-base set, tail motion enabled.")
		else
			print("[NestingNook] dino1 Tail group has no moving parts above the base - tail motion skipped.")
		end
	else
		print("[NestingNook] dino1 has no 'Tail' group - tail motion skipped.")
	end

	-- Nearest player within LOOK_RADIUS -> yaw (about Y) to face them.
	local function nearestPlayerYaw(): number?
		local bestDist = LOOK_RADIUS
		local bestYaw: number? = nil
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local d = hrp.Position - headPivot
				local flat = Vector3.new(d.X, 0, d.Z)
				local dist = flat.Magnitude
				if dist > 1e-3 and dist <= bestDist then
					bestDist = dist
					local b = flat.Unit
					local crossY = headFront.Z * b.X - headFront.X * b.Z
					local dot = headFront.X * b.X + headFront.Z * b.Z
					bestYaw = math.atan2(crossY, dot)
				end
			end
		end
		return bestYaw
	end

	-- BLINKING (works regardless of head/tail) -----------------------------
	local eyeParts: { BasePart } = {}
	local eyeOriginal: { [BasePart]: number } = {}
	for _, d in ipairs(dino:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = string.lower(d.Name)
			if string.find(n, "blackpartofeye", 1, true) or string.find(n, "whitepartofeye", 1, true) then
				table.insert(eyeParts, d)
				eyeOriginal[d] = d.Transparency
			end
		end
	end
	print(("[NestingNook] dino1 eye parts found: %d %s")
		:format(#eyeParts, #eyeParts > 0 and "- blinking enabled." or "- blinking skipped."))

	if #eyeParts > 0 then
		local function doBlink()
			for _, eye in ipairs(eyeParts) do
				eyeOriginal[eye] = eye.Transparency
				eye.Transparency = 1
			end
			task.wait(0.12)
			for _, eye in ipairs(eyeParts) do
				eye.Transparency = eyeOriginal[eye]
			end
		end
		task.spawn(function()
			while dino.Parent do
				task.wait(rng:NextNumber(3, 6))
				doBlink()
				if rng:NextNumber(0, 1) < 0.3 then
					task.wait(0.12)
					doBlink()
				end
			end
		end)
	end

	-- Random head glances (paused while looking at a player) ----------------
	local currentYaw = 0
	local targetYaw = 0
	local wasLooking = false

	if headRoot then
		task.spawn(function()
			while dino.Parent do
				task.wait(rng:NextNumber(4, 8))
				if not wasLooking then
					local sign = rng:NextInteger(0, 1) == 0 and -1 or 1
					targetYaw = sign * math.rad(rng:NextNumber(10, 18)) -- gentle glance, ±18° max
					task.wait(rng:NextNumber(0.8, 1.4))
					if not wasLooking then
						targetYaw = 0
					end
				end
			end
		end)
	end

	-- One Heartbeat drives the head (bob + glance/look-at) and tail (sway).
	if headRoot or tailRoot then
		local animTime = 0
		RunService.Heartbeat:Connect(function(dt)
			animTime += dt

			if headRoot then
				local lookYaw = nearestPlayerYaw()
				if lookYaw then
					-- Clamp so the neck never swings far from the body.
					targetYaw = math.clamp(lookYaw, -math.rad(30), math.rad(30))
					wasLooking = true
				elseif wasLooking then
					targetYaw = 0
					wasLooking = false
				end

				-- Smooth, frame-rate-independent ease (no snapping).
				local alpha = 1 - math.exp(-dt * 5)
				currentYaw += shortestAngle(targetYaw - currentYaw) * alpha

				local nod = math.sin(animTime * 1.6) * math.rad(3) -- gentle ±3° nod
				local R = CFrame.Angles(nod, currentYaw, 0)
				-- Rotate the whole Head group around the fixed neck-base pivot, so
				-- the base stays attached to the body and only the head/upper neck swings.
				headRoot.CFrame = CFrame.new(headPivot) * R * CFrame.new(-headPivot) * headRest
			end

			if tailRoot then
				-- Slow side-to-side sway lagging the head's turn (follow-through).
				local sway = math.sin(animTime * 0.8 - 0.7) * math.rad(10) - 0.2 * currentYaw
				local R = CFrame.Angles(0, sway, 0)
				tailRoot.CFrame = CFrame.new(tailPivot) * R * CFrame.new(-tailPivot) * tailRest
			end
		end)
	end
end

----------------------------------------------------------------------
-- Assemble NPCs
----------------------------------------------------------------------

local babyDino, babyAdornee = setupBabyDino()
local _miner, archAdornee = setupMiner()

if babyDino then
	setupDinoIdle(babyDino)

	-- Confirm the neck/body filler parts are gone and report dino1's part count.
	local partCount = 0
	for _, d in ipairs(babyDino:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	print(("[NestingNook] Neck/body filler parts removed. dino1 now has %d parts."):format(partCount))
end

----------------------------------------------------------------------
-- Dialogue
----------------------------------------------------------------------

local function progressText(): string
	return ("(%d/%d found)"):format(eggsReturnedValue.Value, totalEggsValue.Value)
end

-- Dialogue split into short pages, advanced by pressing E. The Mama Dino is the
-- heartbroken mother; the Miner is a gruff old prospector with his own voice.
local function dinoPages(): { string }
	if eggsReturnedValue.Value >= totalEggsValue.Value then
		return {
			"You found all my eggs!",
			"Thank you so much! 💚",
		}
	end
	return {
		"My 5 eggs are missing!",
		"Please bring them back to the nest.",
		("Found: %d of %d."):format(eggsReturnedValue.Value, totalEggsValue.Value),
	}
end

local function minerPages(): { string }
	if eggsReturnedValue.Value >= totalEggsValue.Value then
		return {
			"All the eggs are back home. Nice work!",
		}
	end
	return {
		"Some critters took the dino's 5 eggs.",
		"Find them and bring them to the nest.",
		("You have %d of %d."):format(eggsReturnedValue.Value, totalEggsValue.Value),
	}
end

-- Drive a prompt as a paged conversation: each E press shows the next page;
-- after the last page, E closes the bubble and resets to "Talk".
local function wireDialogue(prompt: ProximityPrompt, adornee: BasePart, getPages: () -> { string }, onTalk: ((Player) -> ())?)
	-- The "E" prompt shows/fires within the same range the conversation stays
	-- open, so there's no zone where it opens then instantly closes.
	prompt.MaxActivationDistance = DIALOGUE_CLOSE_DISTANCE

	local pages: { string }? = nil
	local index = 0
	local watching = false

	local function closeDialogue()
		hideSpeech(adornee)
		prompt.ActionText = "Talk"
		index = 0
		pages = nil
	end

	-- Is any player within DIALOGUE_CLOSE_DISTANCE studs of this NPC?
	local function playerInRange(): boolean
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and (hrp.Position - adornee.Position).Magnitude <= DIALOGUE_CLOSE_DISTANCE then
				return true
			end
		end
		return false
	end

	-- While a conversation is open, watch distance and close it the moment the
	-- player walks out of range (no matter which page they're on).
	local function startWatcher()
		if watching then
			return
		end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				if not playerInRange() then
					closeDialogue()
					break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function(player)
		if index == 0 then
			pages = getPages()
		end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			return
		end
		-- Give the quest once the player has read at least 2 pages.
		if index == 2 and onTalk and player then
			onTalk(player)
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showSpeech(adornee, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)

	-- Immediate close when the prompt hides (player left the 12-stud range).
	prompt.PromptHidden:Connect(function()
		if index ~= 0 then
			closeDialogue()
		end
	end)
end

----------------------------------------------------------------------
-- Wire the Talk prompts (attached to the real models)
----------------------------------------------------------------------

-- These prompts are now CREATED if the model doesn't already have one.
--
-- They used to only be FOUND (`FindFirstChildWhichIsA`), and if the model had no
-- ProximityPrompt sitting in it in Studio, the wiring was SILENTLY SKIPPED -- no error,
-- no warning. For the miner that is fatal: talking to him is the only thing that sets
-- questClaimed[player], and onEggTaken() refuses EVERY egg pickup without it. So a
-- missing prompt on the miner = the island1 eggs can never be collected, with nothing
-- in the log to say why.
if babyAdornee then
	local babyPrompt = babyAdornee:FindFirstChildWhichIsA("ProximityPrompt")
	if not babyPrompt then
		babyPrompt = addPrompt(babyAdornee, "Talk", "Mama Dinosaur")
		print("[NestingNook] dino1 had no ProximityPrompt -> created one")
	end
	wireDialogue(babyPrompt, babyAdornee, dinoPages)
	print("[NestingNook] Mama Dino talk prompt wired.")
end

if archAdornee then
	local archPrompt = archAdornee:FindFirstChildWhichIsA("ProximityPrompt")
	if not archPrompt then
		archPrompt = addPrompt(archAdornee, "Talk", "Researcher")
		print("[NestingNook] miner had no ProximityPrompt -> created one")
	end
	-- Talking to the miner ("the Researcher") claims the quest for that player.
	-- WITHOUT THIS, NO EGG ON ISLAND1 CAN BE PICKED UP (see onEggTaken's gate).
	wireDialogue(archPrompt, archAdornee, minerPages, function(player)
		questClaimed[player] = true
		player:SetAttribute("NestingNookQuestClaimed", true) -- replicates to the client HUD
		print(("[NestingNook] %s talked to the Researcher -> quest CLAIMED, eggs are now collectable")
			:format(player.Name))
	end)
	print("[NestingNook] Researcher (miner) talk prompt wired -> talking to him unlocks egg pickup.")
else
	warn("[NestingNook] NO MINER FOUND -> the quest can never be claimed and the LostEggs "
		.. "can NEVER be picked up. Island1 needs a model named 'miner'.")
end

----------------------------------------------------------------------
-- Island 3 "Digger" NPC: a CLONE of the miner placed by the island3 spawn.
-- Talking to it grants the DIG QUEST (sets the "DigQuestAccepted" attribute);
-- BurritoDig.client.luau watches that to build + reveal the dig trail.
----------------------------------------------------------------------
local function digMinerPages(): { string }
	return {
		"There are fossils buried here.",
		"Take this shovel.",
		"Dig the dirt spots to find an egg!",
	}
end

local function setupDigMiner()
	local src = findModel("miner")
	if not src then warn("[DigQuest] 'miner' model not found; Digger NPC skipped."); return end
	local island3 = Workspace:FindFirstChild("island3")
	if not island3 then warn("[DigQuest] island3 not found; Digger NPC skipped."); return end
	local spawn = island3:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then warn("[DigQuest] no SpawnLocation inside island3; Digger NPC skipped."); return end

	local model = src:Clone()
	model.Name = "DigMiner"
	model.Parent = Workspace
	ensurePrimaryPart(model)
	clearAdornments(model)

	-- stand ~6 studs from the island3 spawn, grounded to the island3 floor, facing the spawn
	local sPos = spawn.Position
	local spot = sPos + Vector3.new(6, 0, 6)
	local rotation = CFrame.lookAt(spot, Vector3.new(sPos.X, spot.Y, sPos.Z)).Rotation
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { model, spawn }
	local hit = Workspace:Raycast(Vector3.new(spot.X, sPos.Y + 40, spot.Z), Vector3.new(0, -400, 0), rp)
	local groundY = hit and hit.Position.Y or (spawn.Position.Y + spawn.Size.Y / 2)
	placeModelBottomAt(model, spot.X, spot.Z, groundY, rotation)

	local adornee = pickAdornee(model)
	if not adornee then warn("[DigQuest] Digger NPC has no BasePart for GUI/prompt."); return end
	local prompt = addPrompt(adornee, "Talk", "The Digger")
	prompt.Name = "DigQuestTalk"
	wireDialogue(prompt, adornee, digMinerPages, function(player)
		player:SetAttribute("DigQuestAccepted", true) -- BurritoDig.client.luau starts the dig on this
	end)
	-- Replace the island3 spawn BRICK with our own invisible, non-colliding spawn at the SAME spot/height
	-- (like island1) -- the player still spawns here but never sees or runs into the brick.
	do
		local mine = Instance.new("SpawnLocation")
		mine.Name = "Island3Spawn"
		mine.Size = spawn.Size
		mine.CFrame = spawn.CFrame
		mine.Duration = spawn.Duration
		mine.Neutral = spawn.Neutral
		mine.AllowTeamChangeOnTouch = spawn.AllowTeamChangeOnTouch
		mine.TeamColor = spawn.TeamColor
		mine.Anchored = true
		mine.CanCollide = false
		mine.CanQuery = false
		mine.CanTouch = false
		mine.Transparency = 1
		mine.Enabled = true
		mine.Parent = island3
		spawn:Destroy()
		print("[DigQuest] island3 spawn brick replaced with an invisible, non-colliding spawn.")
	end
	print("[DigQuest] Digger NPC placed by the island3 spawn.")
end
setupDigMiner()

----------------------------------------------------------------------
-- Other islands: a CLONE of the miner placed the SAME way as island3's Digger
-- (~6 studs from that island's spawn point, grounded, facing the spawn), with
-- dialogue relative to that island's quest. Islands 1 + 3 already have their own
-- NPCs above; an island with NO spawn point is skipped automatically.
----------------------------------------------------------------------
local function setupIslandQuestNPC(islandName, npcName, title, pages, onTalk)
	local src = findModel("miner")
	if not src then warn("[IslandNPC] 'miner' model not found; " .. npcName .. " skipped."); return end
	local island = Workspace:FindFirstChild(islandName)
	if not island then warn("[IslandNPC] " .. islandName .. " not found; " .. npcName .. " skipped."); return end
	-- find this island's spawn point (OPTIONAL): a SpawnLocation, else a part named "Spawn"
	local spawn = island:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Spawn" then spawn = d; break end
		end
	end
	-- Find the NPC marker. Search order (ISLAND-SCOPED FIRST -- a marker sitting on THIS
	-- island always beats a same-named one somewhere else):
	--   1. exact "NPCSpot<N>" / "Island<N>NPC" on this island
	--   2. any part on this island named "...npc..." AND containing the island number
	--   3. any part on this island named "...npc..." at all  <-- catches a marker whose
	--      number is stale (e.g. AshWarden moved island8 -> island11, so its marker may
	--      still be called "NPCSpot8"), or one just named "NPCSpot" / "npc".
	--   4. exact name anywhere in Workspace (last resort)
	local num = islandName:gsub("island", "")
	local npcSpot = island:FindFirstChild("NPCSpot" .. num, true) or island:FindFirstChild("Island" .. num .. "NPC", true)
	if not (npcSpot and npcSpot:IsA("BasePart")) then
		npcSpot = nil
		local anyNpcPart -- step 3 candidate: has "npc" in the name but the wrong/no number
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("BasePart") then
				local n = d.Name:lower()
				if n:find("npc", 1, true) then
					if n:find(num, 1, true) then npcSpot = d; break end -- step 2: exact number match wins
					if not anyNpcPart then anyNpcPart = d end            -- step 3: remember the first
				end
			end
		end
		if not npcSpot and anyNpcPart then
			npcSpot = anyNpcPart
			warn(("[IslandNPC] %s: no 'NPCSpot%s' on %s -- using the marker '%s' found on that island instead. "
				.. "Rename it to 'NPCSpot%s' to silence this.")
				:format(npcName, num, islandName, anyNpcPart.Name, num))
		end
	end
	if not (npcSpot and npcSpot:IsA("BasePart")) then -- step 4: anywhere in Workspace
		npcSpot = Workspace:FindFirstChild("NPCSpot" .. num, true) or Workspace:FindFirstChild("Island" .. num .. "NPC", true)
		if npcSpot and not npcSpot:IsA("BasePart") then npcSpot = nil end
	end
	local model = src:Clone()
	model.Name = npcName
	model.Parent = Workspace
	ensurePrimaryPart(model)
	clearAdornments(model)

	-- placement: prefer the NPCSpot<N> marker; else stand ~6 studs from the spawn;
	-- else (no marker AND no spawn pad) fall back to the island centre so the NPC
	-- always appears (e.g. island4 has a lake but no spawn pad / NPCSpot4 marker).
	local spotX, spotZ, refY
	local placedBy
	if npcSpot then
		spotX, spotZ, refY = npcSpot.Position.X, npcSpot.Position.Z, npcSpot.Position.Y
		placedBy = ("marker '%s'"):format(npcSpot.Name)
		print(("[IslandNPC] %s using marker '%s' at (%.0f,%.0f,%.0f)"):format(npcName, npcSpot.Name, npcSpot.Position.X, npcSpot.Position.Y, npcSpot.Position.Z))
		-- GHOST THE MARKER so the placement block is never visible in-game.
		-- Handles a Model marker too (ghost every BasePart inside it), not just a Part.
		pcall(function()
			if npcSpot:IsA("BasePart") then
				npcSpot.Transparency = 1; npcSpot.CanCollide = false; npcSpot.CanQuery = false; npcSpot.CanTouch = false
			end
			for _, d in ipairs(npcSpot:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = 1; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
				end
			end
		end)
	elseif spawn then
		spotX, spotZ, refY = spawn.Position.X + 6, spawn.Position.Z + 6, spawn.Position.Y
		placedBy = "the island spawn pad (~6 studs away)"
	else
		local bcf, bsize = island:GetBoundingBox()
		spotX, spotZ, refY = bcf.Position.X, bcf.Position.Z, bcf.Position.Y + bsize.Y / 2
		placedBy = "the island CENTRE (no marker!)"
		warn(("[IslandNPC] %s: no spawn/marker on %s -> placing at island centre (%.0f,%.0f,%.0f). "
			.. "Add a part named 'NPCSpot%s' on the island to set an exact spot.")
			:format(npcName, islandName, spotX, refY, spotZ, num))
	end
	-- face the spawn if there is one, else face the island centre
	local faceTarget
	if spawn then faceTarget = Vector3.new(spawn.Position.X, refY, spawn.Position.Z)
	else local bcf = island:GetBoundingBox(); faceTarget = Vector3.new(bcf.Position.X, refY, bcf.Position.Z) end
	local here = Vector3.new(spotX, refY, spotZ)
	local rotation = ((faceTarget - here).Magnitude > 0.1) and CFrame.lookAt(here, faceTarget).Rotation or CFrame.new()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local excl = { model }; if spawn then excl[#excl+1] = spawn end
	if npcSpot then excl[#excl+1] = npcSpot end -- never land ON the marker we're standing at
	rp.FilterDescendantsInstances = excl
	local hit = Workspace:Raycast(Vector3.new(spotX, refY + 40, spotZ), Vector3.new(0, -400, 0), rp)
	local groundY = hit and hit.Position.Y or refY
	-- WHEN WE HAVE A MARKER, THE MARKER WINS. Only let the ray settle the NPC onto the
	-- surface if it broadly agrees with the marker. If the island's mesh isn't
	-- raycast-queryable, the ray punches THROUGH the island and hits whatever is below,
	-- which would bury the NPC ~200 studs underground (this is exactly what happened to
	-- the island11 geysers). Clamping to the marker makes that impossible: worst case
	-- the NPC stands precisely where the marker is.
	if npcSpot and math.abs(groundY - refY) > 15 then
		warn(("[IslandNPC] %s: ground ray landed %.0f studs from the marker (fell through the island?) -> standing AT the marker instead")
			:format(npcName, groundY - refY))
		groundY = refY
	end
	placeModelBottomAt(model, spotX, spotZ, groundY, rotation)

	local adornee = pickAdornee(model)
	if not adornee then warn("[IslandNPC] " .. npcName .. " has no BasePart for GUI/prompt."); return end
	local prompt = addPrompt(adornee, "Talk", "Researcher") -- shown name = "Researcher" (matches the banner directions)
	prompt.Name = npcName .. "Talk"
	-- talking ACCEPTS that island's quest -> sets Island<N>QuestAccepted (mirrors island3's DigQuestAccepted),
	-- which the top-of-screen banner watches to switch from "go talk to the Researcher" to the quest task.
	local acceptAttr = (islandName:gsub("^island", "Island")) .. "QuestAccepted"
	wireDialogue(prompt, adornee, function() return pages end, function(plr)
		plr:SetAttribute(acceptAttr, true)
		if onTalk then onTalk(plr) end
	end)
	print(("[IslandNPC] %s (Researcher) on %s placed by %s; talk sets %s."):format(npcName, islandName, placedBy, acceptAttr))
end

-- One quest-giver per island that has a spawn point (dialogue matches that island's quest).
local ISLAND_NPCS = {
	{ island = "island2", name = "FrillRancher", title = "The Rancher", pages = {
		"There's a Triceratops egg in the ferns.",
		"Find it and press E to hatch it!",
	} },
	{ island = "island4", name = "CoastalFisher", title = "The Fisher", pages = {
		"Grab the fishing rod from the barrel.",
		"Fish the lake until you catch an egg.",
		"Hatch it to get a Megalodon!",
	} },
	{ island = "island5", name = "MireWatcher", title = "The Mire Watcher", pages = {
		"Welcome to the Misty Mire.",
		"Big mosquitos are buzzing above us.",
		"Click them and swat them in the mini-game!",
		"Feed 5 to the nest and a baby Spinosaurus will hatch!",
	} },
	{ island = "island6", name = "RidgeWarden", title = "The Warden", pages = {
		"Welcome to Redwood Ridge.",
		"Five raptors prowl these woods.",
		"Only ONE is hiding a secret egg.",
		"Grab a sniper and hunt them down to find it!",
	} },
	{ island = "island7", name = "RaptorScout", title = "The Scout", pages = {
		"This is Raptor Ridge.",
		"A raptor nest is starving -- its eggs won't hatch!",
		"Grab the meat scattered around the island.",
		"Carry it back and feed the nest -- 5 pieces.",
		"Do it, and a baby raptor will hatch for you!",
	} },
	{ island = "island11", name = "AshWarden", title = "The Ash Warden", pages = {
		"The volcano is about to blow!",
		"Six geysers are building up pressure.",
		"Plug every geyser to stop the eruption!",
		"Save us, and a mighty T-Rex egg will hatch.",
	} },
}
for _, n in ipairs(ISLAND_NPCS) do
	setupIslandQuestNPC(n.island, n.name, n.title, n.pages, n.onTalk)
end

-- Put the player spawn on a chosen island AT THE SPAWN BLOCK THE USER PLACED there: find that block
-- (a SpawnLocation, else a part named "Spawn"), put an invisible non-colliding spawn at its EXACT spot,
-- and disable every other spawn so the player always spawns there.
-- `enabled` = may Roblox actually spawn players here on join.
--
-- ONLY ISLAND 1 MAY BE TRUE, and that is not a style choice: Roblox picks a RANDOM
-- enabled Neutral SpawnLocation, so two enabled pads means a coin-flip start. Every
-- other island gets its pad built and left DISABLED -- it exists as a POSITION ANCHOR
-- that the Wormhole and the death-return read, not as a Roblox spawn point.
local function putSpawnOnIsland(islandName, label, enabled)
	local island = Workspace:FindFirstChild(islandName)
	if not island then warn(("[Spawn] %s not found -- cannot place the %s spawn"):format(islandName, label)); return end
	local cf, size, src
	-- placedHow records which branch below actually decided the position, because `src` alone
	-- cannot tell you: island7 and island1 both set `cf` WITHOUT setting `src`, so the old
	-- `src and ... or ...` chain fell through to "no spawn block -> island centre" for them.
	-- island7's own line said "placed ~16 studs from the RaptorScout" one line above the
	-- summary claiming it went to the island centre -- two contradictory logs for one spawn.
	local placedHow
	-- island7: spawn a short way from the RaptorScout (the island7 "miner"), FACING him (body + camera)
	if islandName == "island7" then
		local npc = Workspace:FindFirstChild("RaptorScout", true) or Workspace:FindFirstChild("Island7NPC", true)
		if npc then
			local npcPos = (npc:IsA("BasePart") and npc.Position) or npc:GetPivot().Position
			local bcf = island:GetBoundingBox()
			local toCenter = Vector3.new(bcf.Position.X - npcPos.X, 0, bcf.Position.Z - npcPos.Z)
			toCenter = (toCenter.Magnitude > 1 and toCenter.Unit) or Vector3.new(0, 0, 1)
			local sx, sz = npcPos.X + toCenter.X * 16, npcPos.Z + toCenter.Z * 16 -- ~16 studs back from the NPC (not too close)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { npc }
			local hit = Workspace:Raycast(Vector3.new(sx, npcPos.Y + 60, sz), Vector3.new(0, -400, 0), rp)
			local y = (hit and hit.Position.Y or npcPos.Y) + 3
			cf = CFrame.lookAt(Vector3.new(sx, y, sz), Vector3.new(npcPos.X, y, npcPos.Z)) -- face the NPC
			size = Vector3.new(6, 1, 6)
			placedHow = "(16 studs from the RaptorScout, facing him)"
			print("[Spawn] island7 spawn placed ~16 studs from the RaptorScout, facing him")
		end
	end
	if not cf then
		-- locate the user's spawn block
		src = island:FindFirstChildWhichIsA("SpawnLocation", true)
		if not src then
			for _, d in ipairs(island:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Spawn" then src = d; break end
			end
		end
		if src then
			cf, size = src.CFrame, src.Size
		elseif islandName == "island1" and _G.island1SpawnCF then
			-- the island1 spawn pad was removed when the miner was placed on it -> reuse its saved spot,
			-- rotated 90 degrees clockwise so the player faces the requested direction
			cf, size = _G.island1SpawnCF * CFrame.Angles(0, math.rad(-90), 0), (_G.island1SpawnSize or Vector3.new(6, 1, 6))
			print("[Spawn] island1 reusing the original spawn pad position (rotated 90 CW; miner stands nearby)")
		else
			local bcf, bsize = island:GetBoundingBox()
			local topY = bcf.Position.Y + bsize.Y / 2
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
			local hit = Workspace:Raycast(Vector3.new(bcf.Position.X, topY + 60, bcf.Position.Z), Vector3.new(0, -300, 0), rp)
			cf = CFrame.new(bcf.Position.X, (hit and hit.Position.Y or topY) + 0.5, bcf.Position.Z); size = Vector3.new(6, 1, 6)
			warn(("[Spawn] no spawn block found on %s -- using surface centre instead"):format(islandName))
		end
	end
	local sp = Instance.new("SpawnLocation")
	sp.Name = islandName .. "Spawn"; sp.Size = size; sp.CFrame = cf
	sp.Anchored = true; sp.CanCollide = false; sp.CanQuery = false; sp.CanTouch = false
	sp.Transparency = 1; sp.Neutral = true; sp.Duration = 0; sp.Enabled = (enabled == true)
	sp.Parent = island
	if src then pcall(function() src:Destroy() end) end -- remove the user's visible spawn block
	-- NOTE: island1's pad is destroyed earlier (the miner is placed on it) and reused
	-- from _G.island1SpawnCF, so `src` is nil there even though we did NOT fall back to
	-- the centre. Report what actually happened instead of guessing from `src`.
	local how = placedHow
		or (src and "(user's spawn block)")
		or (islandName == "island1" and _G.island1SpawnCF and "(reused the original island1 pad)")
		or "(no spawn block -> island centre)"
	print(("[Spawn] %s '%s' spawn placed %s; all other spawns disabled")
		:format(islandName, label, how))
end
-- ALWAYS START ON ISLAND 1.
-- Roblox picks a RANDOM enabled (Neutral) SpawnLocation, so the only way to
-- guarantee island1 is to leave exactly ONE enabled spawn in the whole Workspace.
-- We disable every existing spawn, then place a single enabled one on island1.
--
-- (This used to enable spawns on island6 / island8 / island9 and NONE on island1,
--  so players spawned at random on 6, 8 or 9 and never on island1.)
--------------------------------------------------------------------
-- GHOST EVERY SPAWN PAD: invisible + non-colliding.
--------------------------------------------------------------------
-- This used to ONLY do `d.Enabled = false`. That stops a pad SPAWNING you, but it stays
-- VISIBLE AND SOLID -- so every island's original spawn block was still sitting there as
-- a big block you could see and walk into. Kill the visuals and the collision too.
--
-- Decals/Textures are destroyed as well: setting a part's Transparency to 1 does NOT
-- hide a Decal on its face, so the classic Roblox spawn-pad graphic would otherwise
-- still be painted in mid-air.
local function ghostSpawn(sp: BasePart)
	sp.Transparency = 1
	sp.CanCollide = false
	sp.CanQuery = false
	sp.CanTouch = false
	for _, d in ipairs(sp:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy() -- a decal ignores the part's Transparency; it must go
		end
	end
end

local ghosted = 0
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") then
		d.Enabled = false
		ghostSpawn(d)
		ghosted += 1
	end
end
print(("[Spawn] %d existing spawn pad(s) disabled + made invisible/non-colliding"):format(ghosted))

-- EVERY ISLAND GETS ONE, island1's is the only one ENABLED.
--
-- island1 used to be the only island given a pad at all, so the other twelve kept their
-- raw builder spawn block -- visible, solid, and walk-into-able -- until the ghosting
-- sweep above merely hid it. Now each island gets the same treatment island1 got: the
-- hand-placed block is replaced by a clean invisible SpawnLocation named
-- "island<N>Spawn", parented to that island so it travels with it.
--
-- These are ANCHORS, not spawn points. WormholeService lands you on your destination's
-- pad, and ReturnIsland puts you back on it when you die -- both read the pad's position
-- rather than guessing at a bounding-box top, so a hand-placed pad is now the one place
-- that decides where you arrive on an island, however you arrive.
--
-- Only island1 is Enabled, because Roblox picks a RANDOM enabled spawn on join and any
-- second enabled pad reintroduces the exact "spawned on 6, 8 or 9 at random" bug noted
-- below.
for n = 1, 13 do
	if Workspace:FindFirstChild("island" .. n) then
		putSpawnOnIsland("island" .. n, "Island " .. n, n == 1)
	end
end

-- FINAL SWEEP: catch any SpawnLocation created after the loop above (including the one
-- putSpawnOnIsland just made, and island3's DigQuest replacement). The island1 spawn
-- MUST stay Enabled -- we only strip its visuals, never its function.
task.delay(3, function()
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			if d.Transparency < 1 or d.CanCollide then
				ghostSpawn(d)
				n += 1
			end
		end
	end
	if n > 0 then
		print(("[Spawn] final sweep: ghosted %d more spawn pad(s)"):format(n))
	end
end)

-- Ghost the island3 "Dig" marker blocks SERVER-SIDE (authoritative): invisible + non-colliding so
-- players never run into the old marker blocks. (The dirt mounds are built on these positions client-side.)
do
	local island3 = Workspace:FindFirstChild("island3")
	if island3 then
		local hidden = 0
		for _, d in ipairs(island3:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Dig" then
				d.Transparency = 1; d.CanCollide = false; d.CanQuery = false; hidden += 1
			end
		end
		print(("[DigQuest] ghosted %d 'Dig' marker block(s) (invisible + non-colliding)"):format(hidden))
	end
end

----------------------------------------------------------------------
-- LostEgg collection: return each egg to the nest in a ring
----------------------------------------------------------------------

-- Declared up here, not next to their first use: the EggCarry handler below closes over
-- both, and a `local function` declared AFTER a closure is a different (global, nil)
-- name inside it -- the claim would silently reject every egg.
local function isLostEgg(inst: Instance): boolean
	return inst.Name == "LostEgg" and (inst:IsA("BasePart") or inst:IsA("Model"))
end
local eggPromptOf: { [Instance]: ProximityPrompt } = {} -- egg -> its prompt, for onEggTaken

local function placeEggInRing(egg: Instance, index: number)
	local count = math.max(totalEggsValue.Value, 1)
	local angle = (index - 1) * (math.pi * 2 / count)
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local eggHeight = getSize(egg).Y
	local target = nestCenter + offset + Vector3.new(0, eggHeight * 0.5, 0)
	setPivot(egg, CFrame.new(target) * CFrame.Angles(0, angle, 0))
end

local function onEggTaken(egg: Instance, prompt: ProximityPrompt, player: Player?)
	-- Must claim the quest from the miner first. This is BY DESIGN -- the client shows a
	-- "Talk To The Researcher First" banner + an arrow to him (QuestGate.client.luau).
	-- Logged so that "the eggs won't pick up" is never a silent mystery again.
	if player and not questClaimed[player] then
		print(("[NestingNook] %s tried to take an egg but has NOT talked to the Researcher yet -> refused (talk to the miner first)")
			:format(player.Name))
		questGate:FireClient(player)
		return
	end

	if egg:GetAttribute("Collected") then
		return
	end
	egg:SetAttribute("Collected", true)
	prompt.Enabled = false

	eggsReturnedValue.Value += 1
	placeEggInRing(egg, eggsReturnedValue.Value)

	if babyAdornee then
		showSpeech(
			babyAdornee,
			("You found one! Welcome home, little egg. %s"):format(progressText())
		)
	end

	if eggsReturnedValue.Value >= totalEggsValue.Value and babyAdornee then
		local dinoAdornee = babyAdornee
		task.delay(1.5, function()
			showSpeech(
				dinoAdornee,
				"That's all of them! My family is reunited at last. Thank you so much! 💚"
			)
		end)
	end
end

local function attachEggPrompt(egg: Instance)
	-- Find a BasePart on the egg to host the prompt.
	local host: BasePart? = nil
	if egg:IsA("BasePart") then
		host = egg
	else
		-- PrimaryPart FIRST. The egg is a stack of slabs, so FindFirstChildWhichIsA picks
		-- up the bottom one and floats the prompt off the base of the egg; the primary is
		-- the middle slab, which puts it on the egg itself.
		host = (egg :: Model).PrimaryPart or egg:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host then
		warn("[NestingNook] LostEgg has no BasePart to host a prompt: " .. egg:GetFullName())
		return
	end

	-- "Rock Egg Free", not "Take Egg" -- the prompt opens the minigame, it does not
	-- hand the egg over. HoldDuration 0.4 matches every other quest's opener.
	local prompt = addPrompt(host, "Rock Egg Free", "Lost Egg")
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.4
	if egg:GetAttribute("Collected") then
		prompt.Enabled = false
	end
	prompt.Triggered:Connect(function(player)
		if not player then return end
		-- the Researcher gate still applies, and still applies FIRST -- an ungated
		-- player should see the banner, not a minigame they can't cash in
		if not questClaimed[player] then
			print(("[NestingNook] %s tried to take an egg but has NOT talked to the Researcher yet -> refused (talk to the miner first)")
				:format(player.Name))
			questGate:FireClient(player)
			return
		end
		if egg:GetAttribute("Collected") then return end
		-- start this player's clock for this egg, then hand them the minigame
		local mine = carryStartedAt[player]
		if not mine then mine = {}; carryStartedAt[player] = mine end
		mine[egg] = os.clock()
		eggCarry:FireClient(player, egg)
	end)
	eggPromptOf[egg] = prompt
end

----------------------------------------------------------------------
-- The client finished rocking an egg loose -> validate and collect it.
----------------------------------------------------------------------
-- Everything here is checked server-side, because the client is the one claiming:
--   * it is a real, uncollected LostEgg still in the world
--   * this player was actually handed THIS egg's minigame
--   * at least PickupFloor.SECONDS has passed since they were handed it
--   * they are still standing next to it (no claiming from across the tower)
eggCarry.OnServerEvent:Connect(function(player, egg)
	if typeof(egg) ~= "Instance" or not isLostEgg(egg) or not egg:IsDescendantOf(Workspace) then return end
	if not questClaimed[player] then return end
	if egg:GetAttribute("Collected") then return end

	local mine = carryStartedAt[player]
	local startedAt = mine and mine[egg]
	if not startedAt then
		print(("[NestingNook] %s claimed '%s' without ever starting it -> refused")
			:format(player.Name, egg.Name))
		return
	end

	-- ISLAND1_EGG_SECONDS, not SECONDS: island 1's eggs run 30% short of the standard
	-- floor. This MUST be the same constant the client builds its ceiling from -- a
	-- server still holding out for the full 15s refuses every egg the panel completes.
	local floor = PickupFloor.ISLAND1_EGG_SECONDS
	local elapsed = os.clock() - startedAt
	if elapsed < floor - CARRY_TOLERANCE then
		print(("[NestingNook] %s claimed '%s' after %.1fs (floor is %.1fs) -> refused")
			:format(player.Name, egg.Name, elapsed, floor))
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	if (getPivot(egg).Position - hrp.Position).Magnitude > 40 then
		print(("[NestingNook] %s claimed '%s' from too far away -> refused"):format(player.Name, egg.Name))
		return
	end

	mine[egg] = nil
	local prompt = eggPromptOf[egg]
	if prompt then onEggTaken(egg, prompt, player) end
end)

-- Attach to all LostEggs already present (the setup script ran first).
local found = 0
for _, inst in ipairs(Workspace:GetDescendants()) do
	if isLostEgg(inst) then
		-- Only top-level LostEggs (a Model named LostEgg won't have LostEgg parts inside).
		attachEggPrompt(inst)
		found += 1
	end
end

print(("[NestingNook] NPCs built. Attached collection prompts to %d LostEggs."):format(found))
