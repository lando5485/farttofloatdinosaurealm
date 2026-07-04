--======================================================================
-- GreenChevronTrail.client.luau   (LocalScript -> StarterPlayerScripts)
--======================================================================
-- A SLEEK GREEN CHEVRON TRAIL: a flowing, striped "runway" of chevron
-- arrows laid FLAT on the ground, leading the player from their feet to a
-- target spot (e.g. a barrel / quest object). The chevrons ride the actual
-- ground (downward raycast), gently pulse so the stripe APPEARS to flow
-- toward the target, and switch off once the player arrives.
--
-- This is an EXACT copy of island4's fishing-rod arrow trail, lifted out of
-- FishingQuest.client.luau and made standalone. To reuse it, set the three
-- CONFIG values below.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer

-- ============================================================================
-- CONFIG -- aim the trail at YOUR target.
-- ============================================================================
local CONFIG = {
	-- The Name of the Part/Model the trail should lead TO (found by name in Workspace).
	targetName = "barrel",
	-- Trail only shows while this returns true. Default: always on once the target exists.
	-- (island4 used:  return player:GetAttribute("Island4QuestAccepted") == true )
	shouldShow = function()
		return true
	end,
	-- Trail switches OFF for good once this returns true (island4 used st.hasRod/st.owns:
	-- the trail vanished the moment you grabbed the rod). Default: never finish.
	isFinished = function()
		return false
	end,
}

-- ===== exact look / motion tuning from the original =====
local BRIGHT      = Color3.fromRGB(90, 200, 110)  -- friendly green
local EDGE        = Color3.fromRGB(40, 120, 60)   -- darker green outline
local SPACING     = 6    -- studs between chevrons
local MAX_ARROWS  = 18   -- most chevrons drawn at once
local STOP_DIST   = 7    -- stop the trail this many studs short of the target ("arrived")
local prefix      = "Trail"

-- ============================================================================
-- find the target by name (retry while it streams in)
-- ============================================================================
local function findTarget()
	local exact = Workspace:FindFirstChild(CONFIG.targetName) or Workspace:FindFirstChild(CONFIG.targetName, true)
	if exact then return exact end
	local w = CONFIG.targetName:lower()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():find(w, 1, true) then
			return d
		end
	end
	return nil
end

local targetInst
for _ = 1, 20 do
	targetInst = findTarget()
	if targetInst then break end
	task.wait(0.5)
end
if not targetInst then
	warn("[Trail] could not find target '"..CONFIG.targetName.."' -- no chevron trail.")
	return
end
local function targetPos()
	return (targetInst:IsA("BasePart") and targetInst.Position) or targetInst:GetPivot().Position
end

-- ============================================================================
-- SLEEK GREEN CHEVRON TRAIL -- flat striped runway of chevron arrows on the ground.
-- ============================================================================
local rayParams = RaycastParams.new(); rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function part(model, name, sx,sy,sz, color, refl, cf)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(sx,sy,sz); p.Color = color
	p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf; p.Parent = model; return p
end
-- one chevron ">" pointing -Z (forward), lying flat (thin in Y): darker edge base + glossy bright top
local function buildChevron()
	local m = Instance.new("Model"); m.Name = prefix .. "Chevron"
	local root = part(m, "Root", 0.2,0.2,0.2, BRIGHT, 0, CFrame.new()); root.Transparency = 1; m.PrimaryPart = root
	local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
	local front = CFrame.new(0, 0, -0.9) -- the chevron POINT
	part(m, "EdgeR", W+0.20, T*0.65, L+0.20, EDGE, 0,    front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,-0.03,L/2))
	part(m, "EdgeL", W+0.20, T*0.65, L+0.20, EDGE, 0,    front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,-0.03,L/2))
	part(m, "ArmR",  W, T, L, BRIGHT, 0.14,              front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, 0.04,L/2))
	part(m, "ArmL",  W, T, L, BRIGHT, 0.14,              front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, 0.04,L/2))
	m.Parent = Workspace
	return m
end
local pool = {}
local function getNode(i) if not pool[i] then pool[i] = buildChevron() end; return pool[i] end
local function setShown(nd, on)
	for _, p in ipairs(nd:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end
	end
end
local function hideFrom(n) for i = n, #pool do if pool[i] then setShown(pool[i], false) end end end
local function destroyAll() for _, nd in ipairs(pool) do pcall(function() nd:Destroy() end) end; pool = {} end

local conn
conn = RunService.RenderStepped:Connect(function()
	if CONFIG.isFinished() then destroyAll(); if conn then conn:Disconnect() end; return end
	if not CONFIG.shouldShow() then hideFrom(1); return end -- only while the gate is open
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then hideFrom(1); return end
	local d = targetPos() - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	local dist = flat.Magnitude
	if dist > 400 or dist <= STOP_DIST then hideFrom(1); return end -- far island / arrived
	local dir = flat.Unit
	-- exclude the player + every chevron so the ground ray doesn't hit them
	local excl = { char }; for _, nd in ipairs(pool) do excl[#excl+1] = nd end
	rayParams.FilterDescendantsInstances = excl
	local maxAlong = dist - STOP_DIST
	local placed = 0
	for i = 1, MAX_ARROWS do
		local along = i * SPACING
		if along > maxAlong then break end
		placed += 1
		local px = hrp.Position.X + dir.X * along
		local pz = hrp.Position.Z + dir.Z * along
		local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rayParams)
		local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
		local nd = getNode(placed)
		-- FLAT on the ground (Y up), pointing toward the target (-Z = dir)
		local p0 = Vector3.new(px, gy + 0.12, pz)
		pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
		-- gentle pulse that FLOWS toward the target
		pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end)
		setShown(nd, true)
	end
	hideFrom(placed + 1)
end)
print("[Trail] sleek GREEN chevron arrow-trail active (flat striped runway on the ground -> "..CONFIG.targetName..")")
