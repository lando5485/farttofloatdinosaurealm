--======================================================================
-- MeteoriteExplosion.server.luau  (server Script)
--======================================================================
-- The "Meteorite Explosion" Robux product (id 3606893853): when someone buys it,
-- the WHOLE SERVER gets bombarded -- tons of flaming meteorites rain from the sky
-- and EXPLODE. EVERYONE DIES except the buyer. The dead respawn at their highest
-- reached island (player attribute "HighestIsland") and get back the coins + fart
-- power they launched with (a snapshot taken at spawn / fart-launch).
--
-- Trigger: the buyer's client fires MeteoriteExplosionEvent on purchase-finished
-- (see MeteoriteExplosion.client.luau). Also: type /meteor to test.
--======================================================================
local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris    = game:GetService("Debris")
local TS        = game:GetService("TweenService")

local function ev(name)
	local e = RS:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end
	return e
end
local triggerEvent  = ev("MeteoriteExplosionEvent") -- client -> server: a player bought it
local shakeEvent    = ev("MeteoriteShakeEvent")     -- server -> all clients: screen shake + red vignette
local launchEvent   = ev("MeteorLaunchSnapshot")    -- client -> server: "I launched" (snapshot coins+power)

local DURATION    = 6      -- seconds of meteor storm
local WAVE_GAP    = 0.16   -- seconds between waves
local PER_PLAYER  = 2      -- meteors dropped near EVERY player per wave (the buyer sees the show too)
local PER_ISLAND  = 3      -- extra meteors scattered across each island that has a player on it
local KILL_AT     = 1.9    -- seconds into the storm before the killing blow lands
local busy        = false
local lastBy      = {}      -- [player] = os.clock() of last trigger (anti-spam)
local snapshot    = {}      -- [player] = { coins=, power= } -- the "launched with" baseline
local pendingResp = {}      -- [player] = true -> respawn at highest island + restore on next CharacterAdded

-- ===== snapshot / restore the coins + fart power a player "launched with" =====
local function takeSnapshot(plr)
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins"); local power = ls:FindFirstChild("CurrentPower")
	snapshot[plr] = { coins = coins and coins.Value or 25, power = power and power.Value or 0 }
end
local function restoreSnapshot(plr)
	local snap = snapshot[plr]; if not snap then return end
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	local coins = ls:FindFirstChild("Coins"); local power = ls:FindFirstChild("CurrentPower")
	if coins then coins.Value = snap.coins end
	if power then power.Value = snap.power end
end

-- ===== where island N's surface centre is (for respawn) =====
local function islandSpawnPos(n)
	local isl = Workspace:FindFirstChild("island" .. n); if not isl then return nil end
	local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
	if not ok or not cf then return nil end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local excl = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then excl[#excl+1] = p.Character end end
	rp.FilterDescendantsInstances = excl
	local topY = cf.Position.Y + size.Y/2
	local hit = Workspace:Raycast(Vector3.new(cf.Position.X, topY + 80, cf.Position.Z), Vector3.new(0, -500, 0), rp)
	local y = (hit and hit.Position.Y or topY) + 5
	return Vector3.new(cf.Position.X, y, cf.Position.Z)
end

-- ===== find the island surface under an XZ point =====
-- The rocks used to stop at the PLAYER's height: targetPos was hrp.Position + a flat XZ offset, so
-- for anyone floating (this is a float game) the meteor exploded in mid-air and never touched the
-- island, and on a slope the ones off to the side burst above or below the ground. Now every
-- meteor drops a ray from high above its XZ spot and lands ON the surface it finds.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
local function groundUnder(pos)
	local excl = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then excl[#excl+1] = p.Character end end
	groundParams.FilterDescendantsInstances = excl
	local origin = Vector3.new(pos.X, pos.Y + 300, pos.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -4000, 0), groundParams) -- long enough to reach the island from a high float
	if hit then
		-- which island model did we land on? (walk up to the Workspace child named islandN)
		local isl = hit.Instance
		while isl and isl.Parent ~= Workspace do isl = isl.Parent end
		if isl and not tostring(isl.Name):match("^island%d+$") then isl = nil end
		return hit.Position + Vector3.new(0, 1, 0), isl
	end
	-- nothing under this spot (over the void / off the island edge): try straight under the player
	-- instead so the rock still lands on the island they are floating over
	return nil
end

-- ===== one flaming meteorite that falls from the sky to targetPos and explodes ON THE GROUND =====
local function spawnMeteor(targetPos)
	targetPos = groundUnder(targetPos) or targetPos
	local s = 5 + math.random() * 4
	local rock = Instance.new("Part")
	rock.Shape = Enum.PartType.Ball; rock.Size = Vector3.new(s, s, s)
	rock.Color = Color3.fromRGB(52,38,30); rock.Material = Enum.Material.Slate
	rock.Anchored = true; rock.CanCollide = false; rock.CanQuery = false; rock.CastShadow = false
	local start = targetPos + Vector3.new(math.random(-45,45), 200 + math.random(0,140), math.random(-45,45))
	rock.CFrame = CFrame.new(start) * CFrame.Angles(math.random()*6, math.random()*6, math.random()*6)
	rock.Parent = Workspace
	-- A CRAGGY ROCK, NOT A BOWLING BALL. The core sphere is wrapped in a ring of smaller lumps: rotated
	-- blocks and wedges half-buried in it, so the silhouette is jagged and reads as a chunk of rock. The lumps
	-- are unanchored and WELDED to the anchored core, so tweening the core's CFrame carries all of them.
	for i = 1, 7 do
		local lump = Instance.new(i % 3 == 0 and "WedgePart" or "Part")
		lump.Name = "Lump"
		lump.Size = Vector3.new(s * (0.35 + math.random() * 0.4), s * (0.3 + math.random() * 0.35), s * (0.35 + math.random() * 0.4))
		lump.Color = (i % 2 == 0) and Color3.fromRGB(64, 46, 36) or Color3.fromRGB(44, 32, 26)
		lump.Material = (i % 2 == 0) and Enum.Material.Rock or Enum.Material.Slate
		lump.Anchored = false; lump.CanCollide = false; lump.CanQuery = false; lump.CanTouch = false
		lump.Massless = true; lump.CastShadow = false
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
		lump.CFrame = rock.CFrame * CFrame.new(dir * s * 0.38) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		lump.Parent = rock
		local w = Instance.new("WeldConstraint"); w.Part0 = rock; w.Part1 = lump; w.Parent = lump
	end
	-- glowing cracks: a hot inner core showing through the gaps between the lumps
	local ember = Instance.new("Part"); ember.Shape = Enum.PartType.Ball; ember.Size = Vector3.new(s * 0.92, s * 0.92, s * 0.92)
	ember.Color = Color3.fromRGB(255, 120, 30); ember.Material = Enum.Material.Neon; ember.Transparency = 0.35
	ember.Anchored = false; ember.CanCollide = false; ember.CanQuery = false; ember.CanTouch = false; ember.Massless = true; ember.CastShadow = false
	ember.CFrame = rock.CFrame; ember.Parent = rock
	do local w = Instance.new("WeldConstraint"); w.Part0 = rock; w.Part1 = ember; w.Parent = ember end
	local fire = Instance.new("Fire"); fire.Size = 16; fire.Heat = 20; fire.Color = Color3.fromRGB(255,150,50); fire.SecondaryColor = Color3.fromRGB(180,40,20); fire.Parent = rock
	local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255,140,40); light.Brightness = 5; light.Range = 30; light.Parent = rock
	local trail = Instance.new("ParticleEmitter"); trail.Texture = "rbxasset://textures/particles/fire_main.dds"; trail.Rate = 90
	trail.Lifetime = NumberRange.new(0.4,0.9); trail.Speed = NumberRange.new(2); trail.Size = NumberSequence.new(6,0)
	trail.Color = ColorSequence.new(Color3.fromRGB(255,170,60), Color3.fromRGB(170,40,20)); trail.LightEmission = 0.7; trail.Parent = rock
	local smoke = Instance.new("ParticleEmitter"); smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"; smoke.Rate = 24
	smoke.Lifetime = NumberRange.new(0.8,1.4); smoke.Speed = NumberRange.new(1); smoke.Size = NumberSequence.new(8,14); smoke.Transparency = NumberSequence.new(0.4,1); smoke.Color = ColorSequence.new(Color3.fromRGB(60,50,45)); smoke.Parent = rock
	local fall = 0.55 + math.random() * 0.4
	TS:Create(rock, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(targetPos) * CFrame.Angles(math.random() * 4, math.random() * 4, math.random() * 4) }):Play() -- tumbles as it falls
	task.delay(fall, function()
		local exx = Instance.new("Explosion")
		exx.Position = targetPos; exx.BlastRadius = 22 + math.random() * 10; exx.BlastPressure = 420000
		exx.DestroyJointRadiusPercent = 0; exx.ExplosionType = Enum.ExplosionType.NoCraters; exx.Parent = Workspace
		local flash = Instance.new("Part"); flash.Shape = Enum.PartType.Ball; flash.Size = Vector3.new(8,8,8)
		flash.Color = Color3.fromRGB(255,200,90); flash.Material = Enum.Material.Neon
		flash.Anchored = true; flash.CanCollide = false; flash.CanQuery = false; flash.CFrame = CFrame.new(targetPos); flash.Parent = Workspace
		TS:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(48,48,48), Transparency = 1 }):Play()
		-- (the impact SOUND is played CLIENT-SIDE in MeteoriteExplosion.client.luau -- 2D so it's always
		-- audible; server-created positional sounds don't reliably reach/play on clients.)
		Debris:AddItem(flash, 0.5); Debris:AddItem(rock, 0.12)
	end)
end

-- ===== the killing blow: a non-buyer gets a finishing blast + dies (flagged to respawn at highest island) =====
local function killByMeteor(plr)
	local ch = plr.Character; if not ch then return end
	local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	pendingResp[plr] = true
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if hrp then
		local exx = Instance.new("Explosion"); exx.Position = hrp.Position; exx.BlastRadius = 16; exx.BlastPressure = 520000
		exx.DestroyJointRadiusPercent = 0; exx.ExplosionType = Enum.ExplosionType.NoCraters; exx.Parent = Workspace
	end
	hum.Health = 0
end

local function rainMeteorites(buyer)
	if busy then return end
	busy = true
	pcall(function() shakeEvent:FireAllClients(DURATION) end)
	task.spawn(function()
		local t0 = os.clock()
		local killed = false
		while os.clock() - t0 < DURATION do
			-- ROCKS FALL ON EVERYONE'S ISLAND, THE BUYER'S INCLUDED. The loop used to skip the buyer, so
			-- in a solo server (every Studio test) it spawned NOTHING: the buyer got the shake and the red
			-- vignette and never saw a single rock land. The buyer is immune to the KILL, not the show.
			local islandsHit = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				local ch = plr.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp then
					for _ = 1, PER_PLAYER do
						-- pick a spot around them; if it hangs over nothing, aim straight down under them
						local spot = hrp.Position + Vector3.new(math.random(-32,32), 0, math.random(-32,32))
						local ground, isl = groundUnder(spot)
						if not ground then ground, isl = groundUnder(hrp.Position) end
						spawnMeteor(ground or spot)
						if isl then islandsHit[isl] = true end
					end
				end
			end
			-- and a few more scattered over the whole island, so the bombardment reads as the island
			-- being hit rather than just the patch of ground the player is standing on
			for isl in pairs(islandsHit) do
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and cf then
					for _ = 1, PER_ISLAND do
						local spot = cf.Position + Vector3.new((math.random() - 0.5) * size.X * 0.8, size.Y / 2, (math.random() - 0.5) * size.Z * 0.8)
						local ground = groundUnder(spot)
						if ground then spawnMeteor(ground) end
					end
				end
			end
			-- the killing blow: EVERYONE dies except the buyer (once, mid-storm)
			if not killed and os.clock() - t0 > KILL_AT then
				killed = true
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= buyer then killByMeteor(plr) end
				end
			end
			task.wait(WAVE_GAP)
		end
		busy = false
	end)
end

-- ===== per-player lifecycle: snapshot on spawn; on a meteor death, respawn at highest island + restore =====
local function onChar(plr, char)
	if pendingResp[plr] then
		pendingResp[plr] = nil
		task.spawn(function()
			local hrp = char:WaitForChild("HumanoidRootPart", 10); if not hrp then return end
			task.wait(0.1)
			local hi = math.clamp(math.floor(tonumber(plr:GetAttribute("HighestIsland")) or 1), 1, 13)
			local pos = islandSpawnPos(hi)
			if pos then pcall(function() char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0))) end) end
			restoreSnapshot(plr) -- give back the coins + fart power they launched with
		end)
	else
		task.wait(0.2) -- let leaderstats populate
		takeSnapshot(plr) -- baseline for this life
	end
end

local function hookPlayer(plr)
	plr.CharacterAdded:Connect(function(char) onChar(plr, char) end)
	if plr.Character then task.spawn(onChar, plr, plr.Character) end
	plr.Chatted:Connect(function(msg)
		local m = msg:lower()
		if m == "/meteor" then rainMeteorites(plr)        -- runner is the immune "buyer"
		elseif m == "/meteorme" then rainMeteorites(nil)  -- TEST: nobody immune (you die too -> see the respawn)
		end
	end)
end
Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerRemoving:Connect(function(p) lastBy[p] = nil; snapshot[p] = nil; pendingResp[p] = nil end)

-- expose so the ProcessReceipt handler (PurchaseReceipts) can trigger it server-authoritatively
_G.triggerMeteorStorm = rainMeteorites

-- buyer's client fired -> rain on everyone, buyer survives (kept as a fallback trigger)
triggerEvent.OnServerEvent:Connect(function(plr)
	local now = os.clock()
	if lastBy[plr] and now - lastBy[plr] < 20 then return end -- light anti-spam
	lastBy[plr] = now
	rainMeteorites(plr)
end)

-- client says "I launched" -> update the snapshot to their at-launch coins + fart power
launchEvent.OnServerEvent:Connect(function(plr) takeSnapshot(plr) end)

print("[Meteorite] server ready -- buy Meteorite Explosion (or /meteor) -> meteor storm, everyone but the buyer dies + respawns at their highest island")
