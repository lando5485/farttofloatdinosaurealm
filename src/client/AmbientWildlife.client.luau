-- ============================================================================================================
-- AmbientWildlife.client.luau  (LocalScript -> StarterPlayerScripts.DinosaurRealmClient)
--
-- SMALL CRITTERS DRIFTING THROUGH EACH ISLAND. A still scene reads as a diorama; a scene with things moving
-- through it reads as a place. Every island in the tower gets its own flock, themed to what that island IS:
-- butterflies and bees over the green islands, gulls wheeling over Coastal Crossing, midges over Misty Mire,
-- a couple of dark birds circling Claw Cliffs and nothing at all on Inferno Isle or Glacier Gulch -- an
-- island with no life on it says something too, as long as the ones either side of it are busy.
--
-- ===== WHY CLIENT-SIDE =====
-- A hundred critters on the server would replicate a hundred CFrames per frame to every player, forever, and
-- nobody could tell whether your butterfly and mine were in the same place -- because nobody watches a
-- butterfly that closely. Each client grows its own. Zero replication, zero server cost. Nothing here
-- collides, is queryable, casts shadows or can be touched: it is scenery that happens to move.
--
-- ===== WHY IT BUILDS LATE AND PER ISLAND =====
-- Thirteen flocks built at join is ~450 parts for a tower you climb over an hour, twelve of whose islands you
-- cannot see. An island's flock is built the first time you come near it and then frozen (hidden, and skipped
-- before any per-critter work) whenever you are elsewhere, so the cost is one island's worth at a time.
--
-- ===== ANCHORS: MEASURE, DO NOT TRUST THE PIVOT =====
-- The flock centre comes from the island's BOUNDING BOX plus a downward ray for the ground, never from
-- GetPivot -- a model's pivot sits wherever it happens to sit, and for these islands that is nowhere near the
-- island. And with StreamingEnabled an island MODEL replicates at join while its PARTS do not, so a box
-- measured too early is a few studs across: a box smaller than MIN_SPAN means "not streamed in yet, measure
-- again later" rather than a centre to be trusted. Get this wrong and the critters are never given a CFrame
-- and sit visible at world origin all session, erroring nothing and logging nothing.
-- ============================================================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local rng    = Random.new()

-- ===== SHARED TUNING =====
local ACTIVATE_DIST = 900   -- studs (3D): come this close to an island and its flock is built
local DRAW_DIST     = 420   -- studs: past this the whole flock freezes and hides
local MIN_SPAN      = 120   -- studs: a bounding box narrower than this means the island has not streamed in
local REMEASURE     = 5     -- seconds between re-measures of the island you are on (detail streams in late)
local FLY_LOW       = 3     -- height band above the ground that butterflies/bees stay within
local FLY_HIGH      = 12

-- ===== PALETTES =====
local WINGS_BRIGHT = {
	{ Color3.fromRGB(255, 170, 60),  Color3.fromRGB(255, 140, 40)  }, -- monarch
	{ Color3.fromRGB(120, 190, 255), Color3.fromRGB(90, 160, 240)  }, -- blue
	{ Color3.fromRGB(255, 245, 250), Color3.fromRGB(240, 225, 240) }, -- white
	{ Color3.fromRGB(255, 210, 90),  Color3.fromRGB(250, 180, 70)  }, -- yellow
}
local WINGS_JUNGLE = {
	{ Color3.fromRGB(120, 235, 150), Color3.fromRGB(80, 200, 120)  }, -- emerald
	{ Color3.fromRGB(255, 120, 190), Color3.fromRGB(230, 90, 160)  }, -- orchid
	{ Color3.fromRGB(180, 130, 255), Color3.fromRGB(150, 100, 235) }, -- violet
	{ Color3.fromRGB(255, 200, 70),  Color3.fromRGB(250, 165, 50)  }, -- gold
}
local WINGS_PALE = {
	{ Color3.fromRGB(235, 230, 215), Color3.fromRGB(215, 208, 190) }, -- dust
	{ Color3.fromRGB(210, 190, 150), Color3.fromRGB(190, 168, 130) }, -- sand
}

local BEE_GOLD  = { body = Color3.fromRGB(240, 200, 40),  stripe = Color3.fromRGB(30, 26, 20)  }
local BEE_MIDGE = { body = Color3.fromRGB(60, 62, 58),    stripe = Color3.fromRGB(30, 34, 30)  } -- swamp midges
local BEE_FLY   = { body = Color3.fromRGB(70, 70, 78),    stripe = Color3.fromRGB(40, 40, 46)  } -- dig-site flies

local BIRD_DARK  = { body = Color3.fromRGB(52, 48, 58),   wing = Color3.fromRGB(64, 60, 72)    }
local BIRD_GULL  = { body = Color3.fromRGB(240, 242, 245), wing = Color3.fromRGB(205, 212, 220) }
local BIRD_ASH   = { body = Color3.fromRGB(78, 70, 68),   wing = Color3.fromRGB(96, 88, 84)    }
local BIRD_BROWN = { body = Color3.fromRGB(96, 74, 52),   wing = Color3.fromRGB(120, 96, 68)   }

-- ============================================================================================================
-- PER-ISLAND THEMES -- keyed by island MODEL number ("island<N>" in Workspace; see IslandOrder.NAMES).
-- An island missing from this table simply gets no wildlife.
--
-- birdHeight is measured from the GROUND under the island centre, birdSpread scales the circling radius
-- against the island's own footprint -- so the same numbers work on a small island and a huge one.
-- ============================================================================================================
local ISLANDS = {
	-- island1  Nesting Nook -- home island, the one every player sees longest: lush and busy
	[1]  = { butterflies = 8,  bees = 5, birds = 3, wings = WINGS_BRIGHT, bee = BEE_GOLD,  bird = BIRD_DARK,  birdHeight = 70, birdSpread = 0.9 },
	-- island2  Fern Frontier -- ferns and green
	[2]  = { butterflies = 8,  bees = 4, birds = 2, wings = WINGS_BRIGHT, bee = BEE_GOLD,  bird = BIRD_DARK,  birdHeight = 65, birdSpread = 0.9 },
	-- island3  Fossil Frontier -- a dig site: dust and flies, barely a butterfly
	[3]  = { butterflies = 2,  bees = 4, birds = 2, wings = WINGS_PALE,   bee = BEE_FLY,   bird = BIRD_BROWN, birdHeight = 55, birdSpread = 0.8 },
	-- island4  Coastal Crossing -- gulls over the water, wide and low
	[4]  = { butterflies = 2,  bees = 0, birds = 6, wings = WINGS_BRIGHT, bee = BEE_GOLD,  bird = BIRD_GULL,  birdHeight = 42, birdSpread = 1.2 },
	-- island5  Misty Mire -- midges over the swamp, tight to the ground; nothing with pretty wings
	[5]  = { butterflies = 0,  bees = 9, birds = 2, wings = WINGS_PALE,   bee = BEE_MIDGE, bird = BIRD_DARK,  birdHeight = 50, birdSpread = 0.8 },
	-- island6  Redwood Ridge -- forest canopy: birds high above the trees
	[6]  = { butterflies = 6,  bees = 4, birds = 4, wings = WINGS_JUNGLE, bee = BEE_GOLD,  bird = BIRD_DARK,  birdHeight = 95, birdSpread = 1.0 },
	-- island7  Claw Cliffs -- predators live here. Almost nothing small, and what circles is dark
	[7]  = { butterflies = 0,  bees = 2, birds = 5, wings = WINGS_PALE,   bee = BEE_FLY,   bird = BIRD_DARK,  birdHeight = 90, birdSpread = 1.2 },
	-- island8  Inferno Isle -- nothing lives here. Deliberate: the empty islands make the busy ones read
	-- island9  Frostbite Flats (snow) -- the richest island in the tower
	[9]  = { butterflies = 12, bees = 7, birds = 4, wings = WINGS_JUNGLE, bee = BEE_GOLD,  bird = BIRD_DARK,  birdHeight = 80, birdSpread = 1.0 },
	-- island10 Petrified Pass -- stone forest: sparse, quiet
	[10] = { butterflies = 1,  bees = 1, birds = 3, wings = WINGS_PALE,   bee = BEE_FLY,   bird = BIRD_BROWN, birdHeight = 75, birdSpread = 1.0 },
	-- island11 Volcanic Vista -- the geyser finale: two ash-grey birds riding the thermals, nothing else
	[11] = { butterflies = 0,  bees = 0, birds = 2, wings = WINGS_PALE,   bee = BEE_FLY,   bird = BIRD_ASH,   birdHeight = 110, birdSpread = 1.1 },
	-- island12 Sunscorch Sands -- desert: high, slow, and not much of it
	[12] = { butterflies = 2,  bees = 2, birds = 3, wings = WINGS_PALE,   bee = BEE_FLY,   bird = BIRD_BROWN, birdHeight = 100, birdSpread = 1.2 },
	-- island13 Glacier Gulch -- the summit. Frozen and empty
}

-- ============================================================================================================
-- CRITTER MODELS
-- ============================================================================================================
local folder = Instance.new("Folder")
folder.Name = "AmbientWildlife"
folder.Parent = Workspace

local function part(parent, name, size, color)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	-- BORN HIDDEN. A critter that is never given a CFrame sits at world origin -- visible, in the middle of
	-- the map, forever. Starting transparent means a flock whose island never measures shows nothing at all
	-- instead of a pile of parts. The fly loop turns them on once it has somewhere to put them.
	p.Transparency = 1
	p.Parent = parent
	return p
end

-- A butterfly: two wings hinged either side of a body. The WINGS are what sell it -- one that glides with
-- fixed wings reads as a leaf, so the flap is the whole illusion and it has to be big and irregular.
local function buildButterfly(col1, col2)
	local m = Instance.new("Model"); m.Name = "Butterfly"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.12, 0.12, 0.42), Color3.fromRGB(40, 32, 28))
	m.PrimaryPart = body
	return { model = m, body = body,
		wingL = part(m, "WingL", Vector3.new(0.06, 0.5, 0.62), col1),
		wingR = part(m, "WingR", Vector3.new(0.06, 0.5, 0.62), col2) }
end

local function buildBee(pal)
	local m = Instance.new("Model"); m.Name = "Bee"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.22, 0.22, 0.34), pal.body)
	m.PrimaryPart = body
	return { model = m, body = body,
		stripe = part(m, "Stripe", Vector3.new(0.24, 0.24, 0.10), pal.stripe),
		wingL  = part(m, "WingL", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255)),
		wingR  = part(m, "WingR", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255)) }
end

local function buildBird(pal)
	local m = Instance.new("Model"); m.Name = "SkyBird"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.5, 0.4, 1.3), pal.body)
	m.PrimaryPart = body
	return { model = m, body = body,
		wingL = part(m, "WingL", Vector3.new(0.08, 0.18, 2.2), pal.wing),
		wingR = part(m, "WingR", Vector3.new(0.08, 0.18, 2.2), pal.wing) }
end

-- the resting transparency of each part, so the freeze can restore it exactly
local function baseAlpha(kind, which)
	if which == "wing" then
		if kind == "bee" then return 0.55 elseif kind == "butterfly" then return 0.1 else return 0 end
	end
	return 0
end

-- ============================================================================================================
-- MEASURING AN ISLAND
-- ============================================================================================================
local measureParams = RaycastParams.new()
measureParams.FilterType = Enum.RaycastFilterType.Exclude

-- Exclude the critters and every CHARACTER: the ray drops through the island's horizontal centre, which
-- is frequently where a player is standing, and a ray that lands on somebody's head would put the whole
-- flock a body's height above the ground until the next re-measure.
local function refreshFilter()
	local excl = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then excl[#excl + 1] = p.Character end
	end
	measureParams.FilterDescendantsInstances = excl
end

-- -> centre (Vector3, at GROUND level under the island's horizontal centre), halfX, halfZ. nil while the
-- island has not streamed in far enough to measure.
local function measure(model)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if not (ok and cf and size) then return nil end
	if size.X < MIN_SPAN or size.Z < MIN_SPAN then return nil end

	local cx, cz = cf.Position.X, cf.Position.Z
	local top = cf.Position.Y + size.Y * 0.5
	refreshFilter()
	local hit = Workspace:Raycast(Vector3.new(cx, top + 20, cz), Vector3.new(0, -(size.Y + 60), 0), measureParams)
	-- No hit means the centre of the island is a hole (island4's lake, island11's crater) -- the box centre is
	-- a better guess there than the box TOP, which would put the butterflies up in the sky.
	local groundY = hit and hit.Position.Y or cf.Position.Y
	return Vector3.new(cx, groundY, cz), size.X * 0.5, size.Z * 0.5
end

-- ============================================================================================================
-- BUILDING A FLOCK
-- ============================================================================================================
local flocks = {}   -- islandNum -> { centre, span, critters, shown, nextMeasure, model }

local function spawnFlock(num, theme, centre, halfX, halfZ)
	local groundR = math.clamp(math.min(halfX, halfZ) * 0.55, 18, 95)
	local birdR   = math.clamp(math.max(halfX, halfZ) * theme.birdSpread, 55, 240)
	local critters = {}

	-- Each critter gets its OWN speed, radius, height and phase. Shared values move them as a flock of clones,
	-- which is instantly readable as fake -- the irregularity IS the realism.
	for i = 1, theme.butterflies do
		local c = theme.wings[((i - 1) % #theme.wings) + 1]
		local b = buildButterfly(c[1], c[2])
		b.kind = "butterfly"
		b.radius  = rng:NextNumber(groundR * 0.2, groundR)
		b.speed   = rng:NextNumber(0.16, 0.34)          -- lazy
		b.height  = rng:NextNumber(FLY_LOW, FLY_HIGH)
		b.bobAmp  = rng:NextNumber(0.8, 2.2)            -- butterflies do not fly straight; they bob a lot
		b.bobFreq = rng:NextNumber(1.4, 2.6)
		b.flap    = rng:NextNumber(7, 11)
		b.phase   = rng:NextNumber(0, math.pi * 2)
		critters[#critters + 1] = b
	end
	for _ = 1, theme.bees do
		local b = buildBee(theme.bee)
		b.kind = "bee"
		b.radius  = rng:NextNumber(groundR * 0.15, groundR * 0.6)  -- bees stay tighter to the flowers
		b.speed   = rng:NextNumber(0.5, 0.9)                       -- and are much busier
		b.height  = rng:NextNumber(2, 6)
		b.bobAmp  = rng:NextNumber(0.3, 0.8)
		b.bobFreq = rng:NextNumber(3, 5)
		b.flap    = rng:NextNumber(28, 40)                         -- a blur, as it should be
		b.phase   = rng:NextNumber(0, math.pi * 2)
		critters[#critters + 1] = b
	end
	for _ = 1, theme.birds do
		local b = buildBird(theme.bird)
		b.kind = "bird"
		b.radius  = rng:NextNumber(birdR * 0.6, birdR)
		b.speed   = rng:NextNumber(0.10, 0.18)                     -- slow, wide, unhurried circles
		b.height  = theme.birdHeight * rng:NextNumber(0.75, 1.3)
		b.bobAmp  = rng:NextNumber(1.5, 4)
		b.bobFreq = rng:NextNumber(0.3, 0.7)
		b.flap    = rng:NextNumber(2, 3.5)                         -- birds glide; the flap is occasional
		b.phase   = rng:NextNumber(0, math.pi * 2)
		critters[#critters + 1] = b
	end

	print(("[Wildlife] island%d: %d butterflies, %d bees, %d birds (ground r=%.0f, bird r=%.0f)")
		:format(num, theme.butterflies, theme.bees, theme.birds, groundR, birdR))
	return { centre = centre, span = math.max(halfX, halfZ), critters = critters, shown = false, nextMeasure = 0 }
end

-- ============================================================================================================
-- DISCOVERY -- build an island's flock the first time you come near it
-- ============================================================================================================
task.spawn(function()
	while true do
		task.wait(1)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for num, theme in pairs(ISLANDS) do
				if not flocks[num] then
					local model = Workspace:FindFirstChild("island" .. num)
					if model then
						-- coarse gate on the pivot (cheap, and wrong by at most an island's width -- fine for
						-- deciding "are we in the neighbourhood"), then the real measurement
						local ok, pivot = pcall(function() return model:GetPivot() end)
						if ok and (pivot.Position - hrp.Position).Magnitude <= ACTIVATE_DIST then
							local centre, hx, hz = measure(model)
							if centre then
								flocks[num] = spawnFlock(num, theme, centre, hx, hz)
								flocks[num].model = model
							end
						end
					end
				end
			end
		end
	end
end)

-- ============================================================================================================
-- FLY
-- ============================================================================================================
local function setFlockShown(f, on)
	for _, c in ipairs(f.critters) do
		if on then
			c.body.Transparency  = baseAlpha(c.kind, "body")
			c.wingL.Transparency = baseAlpha(c.kind, "wing")
			c.wingR.Transparency = c.wingL.Transparency
			if c.stripe then c.stripe.Transparency = 0 end
		else
			for _, p in ipairs(c.model:GetChildren()) do
				if p:IsA("BasePart") then p.Transparency = 1 end
			end
		end
	end
	f.shown = on
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local me = hrp.Position

	for _, f in pairs(flocks) do
		-- ONE distance test per ISLAND, before any per-critter work. Twelve frozen flocks cost twelve
		-- subtractions a frame; testing every critter individually would cost a hundred.
		local near = (f.centre - me).Magnitude <= DRAW_DIST + f.span
		if not near then
			if f.shown then setFlockShown(f, false) end
		else
			if not f.shown then setFlockShown(f, true) end

			-- islands are positioned at run time by IslandLayout and their detail streams in late, so the
			-- island you are actually standing on is re-measured every few seconds
			if t >= f.nextMeasure then
				f.nextMeasure = t + REMEASURE
				if f.model and f.model.Parent then
					local centre = measure(f.model)
					if centre then f.centre = centre end
				end
			end

			for _, c in ipairs(f.critters) do
				if c.model.Parent then
					local a = t * c.speed + c.phase
					-- a wobbling circle, not a clean one -- a perfect orbit is the tell that something is on rails
					local r = c.radius * (1 + 0.18 * math.sin(a * 1.7 + c.phase))
					local pos = f.centre + Vector3.new(
						math.cos(a) * r,
						c.height + math.sin(t * c.bobFreq + c.phase) * c.bobAmp,
						math.sin(a) * r
					)

					-- face the way we are going (the tangent of the circle)
					local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
					local cf = CFrame.lookAt(pos, pos + tangent)
					c.body.CFrame = cf
					if c.stripe then c.stripe.CFrame = cf * CFrame.new(0, 0, 0.02) end

					-- WINGS. Butterflies and bees beat up and down at the sides of the body; a bird's wings
					-- sweep from a shoulder further out. Same maths, different hinge.
					local beat = math.sin(t * c.flap + c.phase)
					if c.kind == "bird" then
						local sweep = math.rad(38) * beat
						c.wingL.CFrame = cf * CFrame.new(-0.9, 0.1, 0) * CFrame.Angles(0, 0, sweep)
						c.wingR.CFrame = cf * CFrame.new(0.9, 0.1, 0) * CFrame.Angles(0, 0, -sweep)
					else
						local open = math.rad((c.kind == "bee") and 55 or 78) * (0.35 + 0.65 * ((beat + 1) / 2))
						c.wingL.CFrame = cf * CFrame.new(-0.06, 0.16, 0) * CFrame.Angles(0, 0, open)
						c.wingR.CFrame = cf * CFrame.new(0.06, 0.16, 0) * CFrame.Angles(0, 0, -open)
					end
				end
			end
		end
	end
end)

-- /wildlife -- which islands have a flock, where it thinks the island is, and how far you are from it.
-- An empty sky is otherwise impossible to tell apart from a script that never measured anything.
do
	local TextChatService = game:GetService("TextChatService")
	local function diag(msg)
		if tostring(msg or ""):lower():sub(1, 9) ~= "/wildlife" then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		print("[Wildlife] ---- flocks ----")
		local n = 0
		for num, f in pairs(flocks) do
			n += 1
			print(("  island%-3d critters=%-3d shown=%-5s centre=(%.0f,%.0f,%.0f) dist=%s")
				:format(num, #f.critters, tostring(f.shown), f.centre.X, f.centre.Y, f.centre.Z,
					hrp and ("%.0f"):format((f.centre - hrp.Position).Magnitude) or "?"))
		end
		if n == 0 then
			print("  none built yet -- no configured island has been within " .. ACTIVATE_DIST .. " studs AND measured > " .. MIN_SPAN .. " studs across")
		end
	end
	pcall(function()
		TextChatService.MessageReceived:Connect(function(m)
			if m.TextSource and m.TextSource.UserId == player.UserId then diag(m.Text) end
		end)
	end)
	pcall(function() player.Chatted:Connect(diag) end)
end

print("[Wildlife] ready -- per-island themed flocks, built on approach (client-side, no replication)")
