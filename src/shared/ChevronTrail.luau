--======================================================================
-- ChevronTrail.luau  (ModuleScript -> ReplicatedStorage.DinosaurRealm.ChevronTrail)
--======================================================================
-- The flat green CHEVRON RUNWAY that guides the player to a quest target -- the
-- one island1 uses to point at the Mama Dino. A pool of low-poly arrow models is
-- laid FLAT on the ground between the player and the target, ray-cast onto the
-- terrain so the trail hugs slopes, pulsing as it goes.
--
-- This is the ONE source of truth for that trail. It used to be written inline in
-- QuestGate (island1); GeyserQuest (island11) had a different floating "^" arrow
-- over the player's head instead. Both now call this, so every quest's "go here"
-- guide looks identical.
--
-- CLIENT ONLY (uses Players.LocalPlayer + RenderStepped).
--
-- USAGE:
--   local ChevronTrail = require(ReplicatedStorage.DinosaurRealm.ChevronTrail)
--   local trail = ChevronTrail.start(function()
--       return someTarget and someTarget:GetPivot().Position or nil  -- nil = hide
--   end, function()
--       return questDone                                             -- true = tear down for good
--   end)
--   ...
--   trail:Destroy()   -- optional; isDone() tears it down on its own
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer

local ChevronTrail = {}

-- Defaults = the exact island1 look.
local DEFAULTS = {
	bright    = Color3.fromRGB(90, 200, 110), -- friendly green
	edge      = Color3.fromRGB(40, 120, 60),  -- darker green outline
	spacing   = 6,                            -- studs between chevrons
	maxArrows = 18,                           -- pool cap
	stopDist  = 12,                           -- hide the trail once this close to the target

	-- A QUEST'S GUIDE MUST NEVER SHOW FROM ANOTHER ISLAND.
	-- Without these, a trail started on one island keeps drawing from wherever the
	-- player is -- so standing on island1 you'd see green chevrons laid across the
	-- ground pointing at island2's Triceratops egg 1,500 studs overhead. (Trike starts
	-- its trail at BOOT, since its egg is placed immediately, so this fired constantly.)
	--
	-- The islands are a vertical tower spaced 600-2,900 studs apart, so a Y difference
	-- is the cleanest "are we even on the same island" test there is. maxDist catches
	-- the horizontal case.
	maxYDiff  = 250,                          -- studs of altitude between you and the target
	maxDist   = 500,                          -- studs of horizontal distance
}

local function cpart(model, name, sx, sy, sz, color, refl, cf)
	local p = Instance.new("Part")
	p.Name = name; p.Size = Vector3.new(sx, sy, sz); p.Color = color
	p.Material = Enum.Material.SmoothPlastic; p.Reflectance = refl or 0
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.LeftSurface = Enum.SurfaceType.Smooth; p.RightSurface = Enum.SurfaceType.Smooth
	p.FrontSurface = Enum.SurfaceType.Smooth; p.BackSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf; p.Parent = model
	return p
end

-- One low-poly chevron: two angled arms with a darker outline behind them.
local function buildChevron(cfg)
	local m = Instance.new("Model")
	m.Name = "QuestChevron"
	local root = cpart(m, "Root", 0.2, 0.2, 0.2, cfg.bright, 0, CFrame.new())
	root.Transparency = 1
	m.PrimaryPart = root

	local L, W, T, ANG = 2.6, 0.72, 0.22, math.rad(42)
	local front = CFrame.new(0, 0, -0.9)
	cpart(m, "EdgeR", W + 0.20, T * 0.65, L + 0.20, cfg.edge, 0, front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0, -0.03, L / 2))
	cpart(m, "EdgeL", W + 0.20, T * 0.65, L + 0.20, cfg.edge, 0, front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0, -0.03, L / 2))
	cpart(m, "ArmR",  W, T, L, cfg.bright, 0.14,               front * CFrame.Angles(0,  ANG, 0) * CFrame.new(0,  0.04, L / 2))
	cpart(m, "ArmL",  W, T, L, cfg.bright, 0.14,               front * CFrame.Angles(0, -ANG, 0) * CFrame.new(0,  0.04, L / 2))
	m.Parent = Workspace
	return m
end

--- Start a chevron trail.
-- @param getTargetPos function -> Vector3? : where to point (nil hides the trail this frame)
-- @param isDone       function -> boolean  : true tears the trail down permanently
-- @param opts         table?              : overrides for DEFAULTS (colors / spacing / stopDist)
-- @return handle with :Destroy()
function ChevronTrail.start(getTargetPos, isDone, opts)
	local cfg = {}
	for k, v in pairs(DEFAULTS) do cfg[k] = v end
	if opts then for k, v in pairs(opts) do cfg[k] = v end end

	local pool = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local function getNode(i)
		if not pool[i] then pool[i] = buildChevron(cfg) end
		return pool[i]
	end
	local function setShown(nd, on)
		for _, p in ipairs(nd:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = on and 0 or 1 end
		end
	end
	local function hideFrom(n)
		for i = n, #pool do
			if pool[i] then setShown(pool[i], false) end
		end
	end

	local handle = {}
	local conn

	local function teardown()
		for _, nd in ipairs(pool) do pcall(function() nd:Destroy() end) end
		pool = {}
		if conn then conn:Disconnect(); conn = nil end
	end
	handle.Destroy = teardown

	conn = RunService.RenderStepped:Connect(function()
		if isDone and isDone() then teardown(); return end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local target = getTargetPos and getTargetPos()
		if not (hrp and target) then hideFrom(1); return end

		local d = target - hrp.Position
		local flat = Vector3.new(d.X, 0, d.Z)
		local dist = flat.Magnitude

		-- NOT ON THIS ISLAND -> draw nothing. A quest's guide must never be visible from
		-- another island. The Y test does the real work (the islands are a vertical
		-- tower); the horizontal test covers the rest.
		if math.abs(d.Y) > cfg.maxYDiff or dist > cfg.maxDist then hideFrom(1); return end

		-- close enough -> hide the trail (the target speaks for itself now)
		if dist <= cfg.stopDist then hideFrom(1); return end
		local dir = flat.Unit

		-- never let the ray land on the player or on the chevrons themselves
		local excl = { char }
		for _, nd in ipairs(pool) do excl[#excl + 1] = nd end
		rayParams.FilterDescendantsInstances = excl

		local maxAlong = dist - cfg.stopDist
		local placed = 0
		for i = 1, cfg.maxArrows do
			local along = i * cfg.spacing
			if along > maxAlong then break end
			placed += 1
			local px = hrp.Position.X + dir.X * along
			local pz = hrp.Position.Z + dir.Z * along
			local hit = Workspace:Raycast(Vector3.new(px, hrp.Position.Y + 14, pz), Vector3.new(0, -240, 0), rayParams)
			local gy = (hit and hit.Position.Y) or (hrp.Position.Y - 2.5)
			local nd = getNode(placed)
			local p0 = Vector3.new(px, gy + 0.12, pz)
			pcall(function() nd:PivotTo(CFrame.lookAt(p0, p0 + dir)) end)
			pcall(function() nd:ScaleTo(1 + 0.10 * math.sin(os.clock() * 5 - i * 0.8)) end)
			setShown(nd, true)
		end
		hideFrom(placed + 1)
	end)

	return handle
end

--- Guide the player to a quest REWARD EGG: the ground chevron runway plus a bottom-edge
--- hint. This is the one call every island quest makes the moment its egg appears, so
--- the "go get your reward" moment looks identical everywhere -- island1's Mama Dino,
--- island11's volcano egg, and every quest in between.
--
-- @param getTargetPos function -> Vector3? : where the egg is
-- @param isDone       function -> boolean  : true once hatched -> tears everything down
-- @param hintText     string?              : bottom-edge prompt (defaults to a generic one)
-- @return handle with :Destroy()
function ChevronTrail.guideToEgg(getTargetPos, isDone, hintText)
	local playerGui = player:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name = "QuestEggGuide"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 45
	sg.Parent = playerGui

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 1, -26)
	lbl.Size = UDim2.fromOffset(460, 46)
	lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	lbl.BackgroundTransparency = 0.3
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = hintText or "Quest complete! Follow the arrows to your egg!"
	lbl.Parent = sg
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 12)
	local s = Instance.new("UIStroke", lbl)
	s.Color = DEFAULTS.bright
	s.Thickness = 2
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 26; c.Parent = lbl end

	-- THE HINT MUST ALSO VANISH OFF-ISLAND. The trail hides itself when you're not on the
	-- target's island, but this banner is a ScreenGui -- it would otherwise stay stuck to
	-- the screen the whole time you fly up the rest of the tower, telling you to go get an
	-- egg five islands below. Same gate as the trail.
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not sg.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local target = getTargetPos and getTargetPos()
		if not (hrp and target) then sg.Enabled = false; return end
		local d = target - hrp.Position
		local flat = Vector3.new(d.X, 0, d.Z).Magnitude
		sg.Enabled = math.abs(d.Y) <= DEFAULTS.maxYDiff and flat <= DEFAULTS.maxDist
	end)

	local trail
	trail = ChevronTrail.start(getTargetPos, function()
		local done = isDone and isDone() or false
		if done and sg.Parent then
			if conn then conn:Disconnect(); conn = nil end
			sg:Destroy() -- hatched -> drop the hint with the trail
		end
		return done
	end)

	return {
		Destroy = function()
			if conn then conn:Disconnect(); conn = nil end
			pcall(function() sg:Destroy() end)
			pcall(function() trail:Destroy() end)
		end,
	}
end

return ChevronTrail
