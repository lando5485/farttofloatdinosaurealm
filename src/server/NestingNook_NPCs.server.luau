--!strict
-- NestingNook_NPCs.server.luau
-- Wires the "Nesting Nook" quest onto the user's existing models:
--   * dino1  - the baby dino, moved onto the DinoPlacement marker
--   * miner  - the quest giver, left where it sits
-- Each LostEgg (spawned by NestingNook_Setup) gets a "Take Egg" ProximityPrompt
-- that returns it to the nest in a ring. Shared state lives in
-- ReplicatedStorage.NestingNook so both scripts stay in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
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

Players.PlayerRemoving:Connect(function(plr)
	questClaimed[plr] = nil
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

-- Rounded white speech bubble that auto-hides after SPEECH_LIFETIME seconds.
local function hideSpeech(adornee: BasePart)
	local prev = adornee:FindFirstChild("SpeechBubble")
	if prev then
		prev:Destroy()
	end
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

	-- Auto-hide unless this is a persistent (paged) bubble.
	if not persist then
		task.delay(SPEECH_LIFETIME, function()
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then
				bb:Destroy()
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

local function findDinoMarker(): BasePart?
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local n = string.lower(desc.Name)
			if string.find(n, "dino", 1, true) and string.find(n, "plac", 1, true) then
				return desc
			end
		end
	end
	return nil
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

if babyAdornee then
	local babyPrompt = babyAdornee:FindFirstChildWhichIsA("ProximityPrompt")
	if babyPrompt then
		wireDialogue(babyPrompt, babyAdornee, dinoPages)
	end
end

if archAdornee then
	local archPrompt = archAdornee:FindFirstChildWhichIsA("ProximityPrompt")
	if archPrompt then
		-- Talking to the miner ("the Researcher") claims the quest for that player.
		wireDialogue(archPrompt, archAdornee, minerPages, function(player)
			questClaimed[player] = true
			player:SetAttribute("NestingNookQuestClaimed", true) -- replicates to the client HUD
		end)
	end
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
	-- find the NPC marker. Accepts "NPCSpot<N>" OR "Island<N>NPC" (exact), then any island part whose
	-- name contains "npc" and the island number (e.g. "Island8NPC", "NPCSpot5", "npc8").
	local num = islandName:gsub("island", "")
	local npcSpot = island:FindFirstChild("NPCSpot" .. num, true) or island:FindFirstChild("Island" .. num .. "NPC", true)
		or Workspace:FindFirstChild("NPCSpot" .. num, true) or Workspace:FindFirstChild("Island" .. num .. "NPC", true)
	if not (npcSpot and npcSpot:IsA("BasePart")) then
		npcSpot = nil
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("BasePart") then
				local n = d.Name:lower()
				if n:find("npc", 1, true) and n:find(num, 1, true) then npcSpot = d; break end
			end
		end
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
	if npcSpot then
		spotX, spotZ, refY = npcSpot.Position.X, npcSpot.Position.Z, npcSpot.Position.Y
		print(("[IslandNPC] %s using marker '%s' at (%.0f,%.0f,%.0f)"):format(npcName, npcSpot.Name, npcSpot.Position.X, npcSpot.Position.Y, npcSpot.Position.Z))
		pcall(function() npcSpot.Transparency = 1; npcSpot.CanCollide = false; npcSpot.CanQuery = false end) -- ghost the marker
	elseif spawn then
		spotX, spotZ, refY = spawn.Position.X + 6, spawn.Position.Z + 6, spawn.Position.Y
	else
		local bcf, bsize = island:GetBoundingBox()
		spotX, spotZ, refY = bcf.Position.X, bcf.Position.Z, bcf.Position.Y + bsize.Y / 2
		print(("[IslandNPC] %s: no spawn/marker on %s -> placing at island centre (%.0f,%.0f,%.0f). "
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
	local excl = { model }; if spawn then excl[#excl+1] = spawn end; rp.FilterDescendantsInstances = excl
	local hit = Workspace:Raycast(Vector3.new(spotX, refY + 40, spotZ), Vector3.new(0, -400, 0), rp)
	local groundY = hit and hit.Position.Y or refY
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
	print(("[IslandNPC] %s (Researcher) placed ~6 studs from the %s spawn point; talk sets %s."):format(npcName, islandName, acceptAttr))
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
		"Watch out for raptors in the woods.",
	} },
	{ island = "island7", name = "RaptorScout", title = "The Scout", pages = {
		"This is Raptor Ridge.",
		"A raptor nest is starving -- its eggs won't hatch!",
		"Grab the meat scattered around the island.",
		"Carry it back and feed the nest -- 5 pieces.",
		"Do it, and a baby raptor will hatch for you!",
	} },
	{ island = "island8", name = "AshWarden", title = "The Ash Warden", pages = {
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
local function putSpawnOnIsland(islandName, label)
	local island = Workspace:FindFirstChild(islandName)
	if not island then warn(("[Spawn] %s not found -- cannot place the %s spawn"):format(islandName, label)); return end
	local cf, size, src
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
	sp.Transparency = 1; sp.Neutral = true; sp.Duration = 0; sp.Enabled = true
	sp.Parent = island
	if src then pcall(function() src:Destroy() end) end -- remove the user's visible spawn block
	print(("[Spawn] %s '%s' spawn placed at the user's spawn block %s; other spawns disabled")
		:format(islandName, label, src and "(found)" or "(NOT found -> centre)"))
end
-- disable every existing spawn ONCE, then place an invisible spawn on each chosen island
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") then d.Enabled = false end
end
putSpawnOnIsland("island6", "Island 6")

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

local function placeEggInRing(egg: Instance, index: number)
	local count = math.max(totalEggsValue.Value, 1)
	local angle = (index - 1) * (math.pi * 2 / count)
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local eggHeight = getSize(egg).Y
	local target = nestCenter + offset + Vector3.new(0, eggHeight * 0.5, 0)
	setPivot(egg, CFrame.new(target) * CFrame.Angles(0, angle, 0))
end

local function onEggTaken(egg: Instance, prompt: ProximityPrompt, player: Player?)
	-- Must claim the quest from the miner first.
	if player and not questClaimed[player] then
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
		host = egg:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host then
		warn("[NestingNook] LostEgg has no BasePart to host a prompt: " .. egg:GetFullName())
		return
	end

	local prompt = addPrompt(host, "Take Egg", "Lost Egg")
	prompt.MaxActivationDistance = 10
	if egg:GetAttribute("Collected") then
		prompt.Enabled = false
	end
	prompt.Triggered:Connect(function(player)
		onEggTaken(egg, prompt, player)
	end)
end

local function isLostEgg(inst: Instance): boolean
	return inst.Name == "LostEgg" and (inst:IsA("BasePart") or inst:IsA("Model"))
end

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
