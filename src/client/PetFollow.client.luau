--======================================================================
-- PetFollow.client.luau  (LocalScript)
--======================================================================
-- Makes the hatched STEGOSAURUS pet FOLLOW the player and gain level-up
-- visuals + a trail -- behaviour from PET_MOVE_UPGRADES_TRAIL.md
-- (PetMoveUpgrades_AllInOne / PetFollow.client.lua), adapted for our pet:
--
--   * FOLLOW: eased spring glide to an offset behind/right/above you, a SLOWER
--     facing spring (swings round to turn), gentle bob, 45-stud max-trail clamp.
--   * UPGRADES (applyLevelVisual): SIZE 60%@Lv1 -> 100%@Lv25 (via Model:ScaleTo),
--     AURA@2, TRAIL@5, SPARKLES@8, ORBS@11/14/19, RING@15, PULSE@18, BURST@24,
--     GOLD + rainbow shimmer @25, and an accessory schedule (3/7/10/13/17/20/23).
--   * The pet is the ONE source of truth: a clone of ReplicatedStorage.StegosaurusTemplate
--     (same model the Pet Hub + hatch use). Because the body is a CSG union (rigid),
--     there is no per-part organic animator -- the whole model rides the follow PivotTo,
--     and all FX attach to the root.
--
-- It spawns when the egg hatches (QuestGate calls _G.SpawnStegoFollower(cf)).
-- Demo keys to watch the upgrades roll in:  ]  level +1   [  level -1   R  rare toggle
--======================================================================

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Debris     = game:GetService("Debris")

local player = Players.LocalPlayer
local pg     = player:WaitForChild("PlayerGui")

local PRESTIGE_GOLD = Color3.fromRGB(255,200,40)
local BAL_, BLK_, CYL_ = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder

-- Stego theme: color + accessory anchor CFrames (in the template's local/scaled space) + schedule.
local THEME = {
	color = Color3.fromRGB(72,190,180),
	head  = CFrame.new(0.10, 1.62, 0),     -- top of the cube (hats)
	face  = CFrame.new(1.52, 0.14, 0), glassW = 0.44,  -- over the eyes (glasses)
	neck  = CFrame.new(1.42, -0.55, 0),    -- front-lower (bowtie / scarf / bell)
	back  = CFrame.new(-1.30, 0.30, 0),    -- back (backpack)
	side  = CFrame.new(0.30, -0.30, 1.35), -- side (sword / cane)
	side2 = CFrame.new(0.30, -0.30,-1.35),
	accs  = { {3,"bowtie"},{7,"glasses"},{10,"tophat"},{13,"scarf"},{17,"flower"},{20,"sparklecluster"},{23,"cane"} },
}

-- per-pet state
local petFX    = {}   -- pet -> animated effect state (orbs/ring/pulse/burst/shimmer)
local petScale = {}   -- pet -> current sizeMul (for FX orbit radius)
local petLevel = {}   -- pet -> last applied level

-- ===== part factories =====
local function flagAccPart(p)
	p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true
	p.Material=Enum.Material.Plastic
	local SM=Enum.SurfaceType.Smooth
	p.TopSurface=SM; p.BottomSurface=SM; p.LeftSurface=SM; p.RightSurface=SM; p.FrontSurface=SM; p.BackSurface=SM
end
-- accessory part: a model child placed at root.CFrame*cf -> it rides the follow PivotTo (stays attached)
local function accPart(pet, root, shape, sx, sy, sz, color, cf)
	local p = Instance.new("Part"); p.Name="EvoPart"; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); p.CFrame = root.CFrame * cf; p.Parent = pet
	return p
end
local function fxPart(pet, name, shape, sx, sy, sz, color, neon)
	local p = Instance.new("Part"); p.Name=name; p.Shape=shape; p.Size=Vector3.new(sx,sy,sz); p.Color=color
	flagAccPart(p); if neon then p.Material = Enum.Material.Neon end
	p.Parent = pet; return p
end

-- ===== accessory builders (subset used by the stego schedule) =====
local function buildAccessoryByKey(pet, root, theme, key, gold)
	if key == "bowtie" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(175,45,55)
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, BLK_, 0.16,0.36,0.4, c, n * CFrame.new(0,0,0.3*sgn) * CFrame.Angles(math.rad(22*sgn),0,0)) end
		accPart(pet,root, BLK_, 0.2,0.22,0.22, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(120,30,40), n)
	elseif key == "glasses" then
		local f = theme.face; local w = theme.glassW or 0.48; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(30,30,36)
		for _,sgn in ipairs({1,-1}) do accPart(pet,root, CYL_, 0.1,0.42,0.42, c, f * CFrame.new(0,0,w*sgn)) end
	elseif key == "tophat" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(35,35,40)
		accPart(pet,root, CYL_, 0.12,1.2,1.2, c, h * CFrame.new(0,-0.05,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.78,0.74,0.74, c, h * CFrame.new(0,0.42,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.2,0.78,0.78, gold and Color3.fromRGB(225,180,60) or Color3.fromRGB(170,40,50), h * CFrame.new(0,0.16,0) * CFrame.Angles(0,0,math.rad(90)))
	elseif key == "scarf" then
		local n = theme.neck; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(70,120,180)
		accPart(pet,root, CYL_, 1.4,0.26,0.26, c, n * CFrame.Angles(0,math.rad(90),0))
		accPart(pet,root, BLK_, 0.5,0.16,0.3, c, n * CFrame.new(-0.18,-0.42,0.32))
	elseif key == "flower" then
		local e = theme.head; local petal = gold and PRESTIGE_GOLD or Color3.fromRGB(240,120,160); local center = gold and PRESTIGE_GOLD or Color3.fromRGB(250,210,90)
		for k=0,4 do local ang=math.rad(k*72); accPart(pet,root, BAL_, 0.22,0.22,0.22, petal, e * CFrame.new(math.sin(ang)*0.24, math.cos(ang)*0.24, 0)) end
		accPart(pet,root, BAL_, 0.18,0.18,0.18, center, e)
	elseif key == "sparklecluster" then
		local h = theme.head; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(255,225,110)
		for k=0,3 do local ang=math.rad(k*90); local p=accPart(pet,root, BAL_, 0.26,0.26,0.26, c, h * CFrame.new(math.sin(ang)*0.7, 0.45, math.cos(ang)*0.7)); p.Material=Enum.Material.Neon end
	elseif key == "cane" then
		local s = theme.side; local c = gold and PRESTIGE_GOLD or Color3.fromRGB(40,30,26)
		accPart(pet,root, CYL_, 1.7,0.13,0.13, c, s * CFrame.new(0,0.35,0) * CFrame.Angles(0,0,math.rad(90)))
		accPart(pet,root, CYL_, 0.45,0.13,0.13, c, s * CFrame.new(-0.16,1.25,0) * CFrame.Angles(0,0,math.rad(55)))
	end
end

-- ===== clear / fx =====
local function clearEvo(pet)
	local g = pet:FindFirstChild("LevelGlow"); if g then g:Destroy() end
	local root = pet.PrimaryPart
	if root then for _, c in ipairs(root:GetChildren()) do
		local n = c.Name
		if n=="PetSparkle" or n=="PetTrail" or n=="PTrailA0" or n=="PTrailA1" or n=="PetAura" or n=="PetAuraLight" or n=="PetBurst" then c:Destroy() end
	end end
	for _, c in ipairs(pet:GetChildren()) do
		if c.Name=="EvoPart" or c.Name=="PetOrb" or c.Name=="PetRing" or c.Name=="PetPulse" then c:Destroy() end
	end
	petFX[pet] = nil
end
local function buildFX(pet, root, theme, level, gold)
	local col = gold and PRESTIGE_GOLD or theme.color
	local fx = { t=0, burstClock=0, orbs={}, ring={}, pulse=nil, burst=nil, shimmer=(level>=25),
		orbR=2.0, orbH=0.45, ringR=2.2, ringY=0.3, ringTilt=22 }
	local orbCount = (level>=11 and 1 or 0) + (level>=14 and 1 or 0) + (level>=19 and 1 or 0) -- ORBS: 1@11, 2@14, 3@19
	for _=1,orbCount do fx.orbs[#fx.orbs+1] = fxPart(pet, "PetOrb", BAL_, 0.42,0.42,0.42, col, true) end
	if level >= 15 then for i=0,7 do fx.ring[#fx.ring+1] = { part = fxPart(pet,"PetRing", BAL_, 0.28,0.28,0.28, col, true), base = math.rad(i*45) } end end
	if level >= 18 then fx.pulse = fxPart(pet, "PetPulse", CYL_, 0.3,1.2,1.2, col, true); fx.pulseBase = Vector3.new(0.3,1.2,1.2) end
	if level >= 24 then
		local b = Instance.new("ParticleEmitter"); b.Name="PetBurst"; b.Color=ColorSequence.new(col)
		b.Rate=0; b.Lifetime=NumberRange.new(0.4,0.8); b.Speed=NumberRange.new(4,9); b.Size=NumberSequence.new(0.5)
		b.LightEmission=0.8; b.Rotation=NumberRange.new(0,360); b.Parent=root; fx.burst=b
	end
	petFX[pet] = fx
end

-- ===== THE UPGRADE FUNCTION =====
local function applyLevelVisual(pet, level, isRare)
	if not pet or not pet.PrimaryPart then return end
	level = level or 1
	if isRare then level = 25 end
	local root  = pet.PrimaryPart
	local theme = THEME
	local MAXL  = 25
	local frac  = math.clamp((level - 1) / (MAXL - 1), 0, 1)
	local atMax = (level >= MAXL)
	local prevLevel = petLevel[pet]
	clearEvo(pet)
	-- (1) SIZE 60% -> 100% via Model:ScaleTo -- this scales every part's SIZE *and* POSITION together about
	-- the pivot, so welded fins/tail keep the SAME overlap with the BodyUnion (no per-part separation).
	local sizeMul = 0.6 + 0.4 * frac
	-- small ball parts (shark fins / trike frill + horn segments) separate when shrunk -> keep these FULL SIZE
	-- (identical to the hub clone, guaranteed solid -- uniform scale alone still pulls the little balls apart).
	if pet.Name:find("Shark") or pet.Name:find("Trice") or pet.Name:find("Spino") or pet.Name:find("Tyranno") then sizeMul = 1.0 end
	petScale[pet] = sizeMul
	local function gapReport(tag) -- prints a part's overlap with the BodyUnion (negative = gap)
		local bu = pet:FindFirstChild("BodyUnion")
		local d = pet:FindFirstChild("Dorsal") or pet:FindFirstChild("FrillScallop") or pet:FindFirstChild("BrowHorn") or pet:FindFirstChild("Pectoral")
		if bu and d then
			local ov = (bu.Position.Y + bu.Size.Y/2) - (d.Position.Y - d.Size.Y/2)
			print(("[PetFollow][GAP] %s scale=%.2f: %s/BodyUnion overlap=%.3f studs (negative = GAP)"):format(tag, pet:GetScale(), d.Name, ov))
		end
	end
	gapReport("BEFORE")
	pcall(function() pet:ScaleTo(sizeMul) end)
	gapReport("AFTER ")
	print(("[PetFollow] %s final scale = %.2f"):format(pet.Name, sizeMul))
	local function ramp(startL) return math.clamp((level - startL) / (MAXL - startL), 0, 1) end
	-- (2) AURA @2
	if level >= 2 then
		local t = ramp(2)
		local hl = Instance.new("Highlight"); hl.Name="LevelGlow"; hl.Adornee=pet
		pcall(function() hl.DepthMode = Enum.HighlightDepthMode.Occluded end)
		hl.FillColor=theme.color; hl.OutlineColor=theme.color
		hl.FillTransparency=math.clamp(0.8-0.45*t,0,1); hl.OutlineTransparency=math.clamp(0.4-0.4*t,0,1); hl.Parent=pet
		local pl = Instance.new("PointLight"); pl.Name="PetAuraLight"; pl.Color=theme.color; pl.Brightness=2.5+4*t; pl.Range=8+8*t; pl.Parent=root
		local ae = Instance.new("ParticleEmitter"); ae.Name="PetAura"; ae.Color=ColorSequence.new(theme.color); ae.LightEmission=0.7
		ae.Rate=8+34*t; ae.Lifetime=NumberRange.new(0.6,1.1); ae.Speed=NumberRange.new(0.2,0.8); ae.Size=NumberSequence.new(0.5+0.5*t)
		ae.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.3), NumberSequenceKeypoint.new(1,1) }); ae.Parent=root
	end
	-- (3) TRAIL @5 -- two attachments on the root (1 up / 1 down = width) + a Trail that lengthens/brightens
	if level >= 5 then
		local t = ramp(5)
		local a0 = Instance.new("Attachment"); a0.Name="PTrailA0"; a0.Position=Vector3.new(0, 1.0, 0); a0.Parent=root
		local a1 = Instance.new("Attachment"); a1.Name="PTrailA1"; a1.Position=Vector3.new(0,-1.0, 0); a1.Parent=root
		local tr = Instance.new("Trail"); tr.Name="PetTrail"; tr.Attachment0=a0; tr.Attachment1=a1
		tr.Color=ColorSequence.new(theme.color); tr.LightEmission=0.6; tr.Lifetime=0.5+1.1*t
		tr.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(0.35-0.3*t,0,1)), NumberSequenceKeypoint.new(1,1) })
		tr.Parent=root
	end
	-- (4) SPARKLES @8
	if level >= 8 then
		local t = ramp(8)
		local pe = Instance.new("ParticleEmitter"); pe.Name="PetSparkle"; pe.Rate=14+90*t; pe.LightEmission=0.7; pe.Rotation=NumberRange.new(0,360)
		pe.Lifetime=NumberRange.new(0.5,1.0); pe.Speed=NumberRange.new(0.6,1.6); pe.Size=NumberSequence.new(0.34); pe.Color=ColorSequence.new(theme.color)
		pe.Transparency=NumberSequence.new({ NumberSequenceKeypoint.new(0,0.15), NumberSequenceKeypoint.new(1,1) }); pe.Parent=root
	end
	-- (5) ANIMATED FX: orbs (11/14/19), ring (15), pulse (18), burst (24)
	buildFX(pet, root, theme, level, atMax)
	-- (6) ACCESSORIES: per-level, accumulating; gold trim at MAX
	for _, e in ipairs(theme.accs) do if level >= e[1] then buildAccessoryByKey(pet, root, theme, e[2], atMax) end end
	-- LEVEL-UP POP + one-shot burst
	if prevLevel and level > prevLevel then
		local burst = Instance.new("ParticleEmitter"); burst.Color=ColorSequence.new(theme.color); burst.LightEmission=0.85
		burst.Lifetime=NumberRange.new(0.35,0.7); burst.Speed=NumberRange.new(3,7); burst.Rotation=NumberRange.new(0,360)
		burst.Size=NumberSequence.new(0.45); burst.Rate=0; burst.Parent=root; burst:Emit(20); Debris:AddItem(burst,1.1)
	end
	petLevel[pet] = level
	local nAcc=0; for _,e in ipairs(theme.accs) do if level>=e[1] then nAcc=nAcc+1 end end
	print(("[PetFollow] Stego Lv %d: size %d%%, aura %s, trail %s, sparkles %s, accessories %d, shimmer %s")
		:format(level, math.floor(sizeMul*100), level>=2 and "on" or "off", level>=5 and "on" or "off", level>=8 and "on" or "off", nAcc, atMax and "on" or "off"))
end

-- ===== FX LOOP: orbit orbs, spin ring, pulse, periodic burst, MAX shimmer =====
RunService.Heartbeat:Connect(function(dt)
	for pet, fx in pairs(petFX) do
		local root = pet.Parent and pet.PrimaryPart
		if root then
			fx.t = fx.t + dt; local t = fx.t; local rootCF = root.CFrame
			local sm = petScale[pet] or 1
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
				fx.pulse.Transparency = math.clamp(ph,0,1)
				fx.pulse.CFrame = rootCF * CFrame.new(0, 0.2*sm, 0) * CFrame.Angles(0,0,math.rad(90))
			end
			if fx.burst then fx.burstClock = fx.burstClock - dt; if fx.burstClock <= 0 then fx.burstClock = 1.3; fx.burst:Emit(18) end end
			if fx.shimmer then
				local hue = (t * 0.25) % 1; local c = Color3.fromHSV(hue, 0.45, 0.9)
				local hl = pet:FindFirstChild("LevelGlow"); if hl then hl.OutlineColor=c; hl.OutlineTransparency=0.25; hl.FillColor=c; hl.FillTransparency=0.88 end
				local tr = root:FindFirstChild("PetTrail"); if tr then tr.Color = ColorSequence.new(Color3.fromHSV((hue+0.5)%1, 0.6, 1)) end
				for _, orb in ipairs(fx.orbs) do orb.Color = c end
				for _, seg in ipairs(fx.ring) do seg.part.Color = c end
			end
		else
			petFX[pet] = nil
		end
	end
end)

-- ===== FOLLOW MOVEMENT =====
local FOLLOW_OFFSET = Vector3.new(3.5, 1.5, 5)  -- right, up, BEHIND (+Z)
local FOLLOW_K = 6     -- position responsiveness (lower = softer glide)
local FACE_K   = 4     -- facing responsiveness (slower -> swings round to turn)
local MAX_TRAIL = 45   -- never strand the pet on a fast ascent
local petSmoothPos, petSmoothFwd, bobT = nil, nil, 0

local st = { pet = nil, level = 1, rare = false, emerging = false }

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pet = st.pet
	if pet and pet.Parent and pet.PrimaryPart and not st.emerging and hrp then
		local targetPos = (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)).Position
		if not petSmoothPos then petSmoothPos = targetPos end
		petSmoothPos = petSmoothPos:Lerp(targetPos, 1 - math.exp(-FOLLOW_K * dt))
		local back = petSmoothPos - targetPos
		if back.Magnitude > MAX_TRAIL then petSmoothPos = targetPos + back.Unit * MAX_TRAIL end
		bobT = bobT + dt
		local renderPos = petSmoothPos + Vector3.new(0, math.sin(bobT * 1.4) * 0.10, 0)
		-- HYBRID facing: face the TRAVEL direction while moving, turn to face the PLAYER when idle.
		-- (+X front reads forward when running, and looks at you when stopped -- the hub's front view.)
		local vel = hrp.AssemblyLinearVelocity
		local moveDir = Vector3.new(vel.X, 0, vel.Z)
		local fwd
		if st.facePlayer then -- shark: ALWAYS face the player so its +X face shows (hub-like)
			fwd = hrp.Position - renderPos; fwd = Vector3.new(fwd.X, 0, fwd.Z)
		elseif moveDir.Magnitude > 2 then
			fwd = moveDir                               -- moving -> face where it's going
		else
			fwd = hrp.Position - renderPos               -- idle -> look at the player (front toward you)
			fwd = Vector3.new(fwd.X, 0, fwd.Z)
		end
		if fwd.Magnitude < 0.05 then fwd = (petSmoothFwd or Vector3.new(0,0,-1)) end
		fwd = fwd.Unit
		if not petSmoothFwd then petSmoothFwd = fwd end
		petSmoothFwd = petSmoothFwd:Lerp(fwd, 1 - math.exp(-FACE_K * dt))
		if petSmoothFwd.Magnitude < 0.05 then petSmoothFwd = fwd end
		local face = petSmoothFwd.Unit
		pet:PivotTo(CFrame.lookAt(renderPos, renderPos + face) * CFrame.Angles(0, math.rad(90), 0)) -- +X = front -> yaw +90
		if not st.orientPrinted then st.orientPrinted = true
			local pv = pet:GetPivot()
			print(("[PetFollow][ORIENT] %s AFTER -> up=(%.2f,%.2f,%.2f) frontX=(%.2f,%.2f,%.2f)  (up should be ~0,1,0 = dorsal upright; frontX = the travel/look dir the face points)"):format(pet.Name, pv.UpVector.X,pv.UpVector.Y,pv.UpVector.Z, pv.RightVector.X,pv.RightVector.Y,pv.RightVector.Z))
		end
	end
end)

-- ===== EYE BLINK (the game's EXACT Size.Y squash from animatePet / Eyes_AllInOne) =====
-- Eye parts (whitepartofeye / blackpartofeye / Glint) are treated as eye=true. Per frame:
-- blink -= dt; on crossing 0, squash Size.Y for 0.16s, then schedule next at 1.8 + rand*3.4 s.
-- Each eye's ORIGINAL Size.Y is stored once and multiplied from that base every frame (no compounding).
local function applyBlink(petModel)
	if not petModel then return end
	local eyes = {}
	for _, d in ipairs(petModel:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "whitepartofeye" or d.Name == "blackpartofeye" or d.Name == "Glint") then
			eyes[#eyes+1] = { part = d, baseX = d.Size.X, baseY = d.Size.Y, baseZ = d.Size.Z }
		end
	end
	if #eyes == 0 then return end
	local blink = 1.5
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not petModel.Parent then conn:Disconnect(); return end   -- clean up on despawn
		blink = blink - dt
		local eyeY = 1
		if blink <= 0 then
			local since = -blink
			if since < 0.16 then eyeY = 1 - 0.85 * (1 - math.abs((since / 0.16) * 2 - 1))
			else blink = 1.8 + math.random() * 3.4 end
		end
		for _, e in ipairs(eyes) do
			if e.part.Parent then e.part.Size = Vector3.new(e.baseX, e.baseY * eyeY, e.baseZ) end
		end
	end)
	print("[PetFollow] eye blink (Size.Y squash) started (" .. #eyes .. " eye parts)")
end

-- ===== FOLLOWER-ONLY shark fins: add a big dorsal fin + a forked tail, welded to the follower's BodyUnion.
-- Does NOT touch the SharkTemplate or the hub icon -- only the spawned follower clone. Sizes/offsets are in
-- world studs matching the full-size body (+X front, +Y up, -X back), and parts are embedded so nothing floats. =====
local function addSharkFollowerFins(pet)
	local body = pet:FindFirstChild("BodyUnion") or pet.PrimaryPart
	if not body then warn("[PetFollow] shark follower has no BodyUnion -> cannot add fins"); return end
	-- clear any template/old follower dorsal+tail on THIS clone only (so the new ones don't double up)
	for _, d in ipairs(pet:GetChildren()) do
		if d:IsA("BasePart") and (d.Name=="Dorsal" or d.Name=="TailBase" or d.Name=="TailTop" or d.Name=="TailBot"
			or d.Name:find("FollowerDorsal") or d.Name:find("FollowerTail")) then d:Destroy() end
	end
	local FIN = Color3.fromRGB(84,100,120)   -- shark blue-grey fin
	local SMOOTH = Enum.SurfaceType.Smooth
	local hx, hy = body.Size.X/2, body.Size.Y/2 -- ACTUAL body half-extents: hx = front/back (X), hy = top (Y)
	-- SWEPT: rotate the wedge so it's a FLAT TRIANGLE in the X-Y plane, THIN (0.4) side-to-side along Z, with the
	-- full-height edge toward +X tapering to a point toward -X (swept back). A WedgePart -- NOT a ball.
	local SWEPT = CFrame.Angles(0, math.rad(-90), 0)
	local function wedgeFin(name, sx,sy,sz, lx,ly,lz)
		local p = Instance.new("WedgePart"); p.Name = name; p.Size = Vector3.new(sx,sy,sz); p.Color = FIN
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.CastShadow=false; p.Massless=true; p.Material=Enum.Material.Plastic
		p.TopSurface=SMOOTH;p.BottomSurface=SMOOTH;p.LeftSurface=SMOOTH;p.RightSurface=SMOOTH;p.FrontSurface=SMOOTH;p.BackSurface=SMOOTH
		p.CFrame = body.CFrame * CFrame.new(lx,ly,lz) * SWEPT
		p.Parent = pet
		local w = Instance.new("WeldConstraint"); w.Name="FinWeld"; w.Part0=body; w.Part1=p; w.Parent=p -- moves + stays attached at follower scale
		print(("[PetFollow][FIN] %s shape=%s size=(%.2f,%.2f,%.2f) relPos=(%.2f,%.2f,%.2f)"):format(name, p.ClassName, sx,sy,sz, lx,ly,lz))
		return p
	end
	-- size order = (sx = thin Z, sy = tall Y, sz = depth X)
	-- DORSAL FIN: flat triangle standing on the TOP surface; flat bottom embeds ~0.4, the rest (~2 studs) stands above.
	local dY = 2.4
	wedgeFin("FollowerDorsal", 0.4, dY, 1.8, -0.1, hy + dY/2 - 0.4, 0)
	-- FORKED TAIL: two flat triangular lobes at the BACK (-X). Tall edge embeds ~0.3 into the rear; points splay out behind.
	wedgeFin("FollowerTailTop", 0.4, 2.3, 1.8, -hx - 1.8/2 + 0.3,  0.5, 0)  -- taller TOP lobe
	wedgeFin("FollowerTailBot", 0.4, 1.5, 1.5, -hx - 1.5/2 + 0.3, -0.7, 0)  -- shorter bottom lobe
	-- ===== confirm: WedgeParts sitting ON the body surface (not balls floating off it) =====
	local dBase = (hy + dY/2 - 0.4) - dY/2
	print(("[PetFollow][FIN] body half: X(front/back)=%.2f  Y(top)=%.2f"):format(hx, hy))
	print(("[PetFollow][FIN] DORSAL base_y=%.2f bodyTop=%.2f embed=%.2f -> tip ~%.2f studs ABOVE the body"):format(dBase, hy, hy - dBase, (hy + dY/2 - 0.4) + dY/2 - hy))
	print(("[PetFollow][FIN] TAIL lobes: tall edge embeds ~0.30 into the rear (bodyBack=%.2f), points stick out behind"):format(-hx))
	print("[PetFollow] SharkPetFollower: dorsal + forked tail are WedgeParts ON the body surface (welded to BodyUnion)")
end

-- ===== SPAWN a follower from a published template (called by QuestGate / dig quest on hatch) =====
local function spawnFollowerFromTemplate(templateName, label, baseCF)
	local tmpl = RS:FindFirstChild(templateName) or RS:WaitForChild(templateName, 10)
	if not tmpl then warn("[PetFollow] " .. templateName .. " missing -> cannot spawn follower"); return end
	if st.pet then pcall(function() st.pet:Destroy() end); petFX[st.pet]=nil; petScale[st.pet]=nil; petLevel[st.pet]=nil end
	local pet = tmpl:Clone(); pet.Name = label; pet.Parent = workspace
	local n = 0; for _, d in ipairs(pet:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	print(("[PetFollow] %s -> CLONED %s (%d parts)"):format(label, templateName, n))
	-- match the hub EXACTLY: pivot on Root (origin/identity, +X front, +Y up). If the clone lost its PrimaryPart,
	-- PivotTo would fall back to a tilted bounding-box pivot -> fin/face read wrong. Force it back to Root.
	if pet.PrimaryPart ~= pet:FindFirstChild("Root") then pet.PrimaryPart = pet:FindFirstChild("Root") end
	do local pv = pet:GetPivot(); print(("[PetFollow][ORIENT] %s BEFORE -> PrimaryPart=%s pivotUp=(%.2f,%.2f,%.2f) pivotLook=(%.2f,%.2f,%.2f)"):format(label, pet.PrimaryPart and pet.PrimaryPart.Name or "nil", pv.UpVector.X,pv.UpVector.Y,pv.UpVector.Z, pv.LookVector.X,pv.LookVector.Y,pv.LookVector.Z)) end
	st.pet = pet; petSmoothPos = nil; petSmoothFwd = nil; st.orientPrinted = false
	st.facePlayer = (label:find("Shark") ~= nil) or (label:find("Trice") ~= nil) -- shark/trike: always turn its +X FACE toward you (see its face like the hub)
	applyLevelVisual(pet, st.level, st.rare)
	applyBlink(pet)  -- Size.Y squash blink on whitepartofeye/blackpartofeye/Glint
	if label:find("Shark") then addSharkFollowerFins(pet) end -- follower-only dorsal fin + forked tail (template/hub untouched)
	-- emerge: a short rise at the spot, then hand off to the follow loop
	if typeof(baseCF) == "CFrame" then
		st.emerging = true
		pcall(function() pet:PivotTo(baseCF) end)
		task.spawn(function()
			local T, t0 = 0.5, os.clock()
			while os.clock() - t0 < T and pet.Parent do
				local p = (os.clock() - t0) / T
				pcall(function() pet:PivotTo(baseCF * CFrame.new(0, math.sin(p * math.pi) * 2.0 + p * 1.0, 0)) end)
				task.wait()
			end
			st.emerging = false
		end)
	end
	print("[PetFollow] " .. label .. " spawned -> following you")
end
_G.SpawnStegoFollower  = function(baseCF) spawnFollowerFromTemplate("StegosaurusTemplate", "StegoFollower", baseCF) end
_G.SpawnRaptorFollower = function(baseCF) spawnFollowerFromTemplate("VelociraptorTemplate", "RaptorFollower", baseCF) end
_G.SpawnSharkFollower  = function(baseCF) spawnFollowerFromTemplate("SharkTemplate", "SharkFollower", baseCF) end
_G.SpawnTriceratopsFollower = function(baseCF) spawnFollowerFromTemplate("TriceratopsTemplate", "TriceratopsFollower", baseCF) end
_G.SpawnSpinosaurusFollower = function(baseCF) spawnFollowerFromTemplate("SpinosaurusTemplate", "SpinosaurusFollower", baseCF) end
_G.SpawnTyrannosaurusFollower = function(baseCF) spawnFollowerFromTemplate("TyrannosaurusTemplate", "TyrannosaurusFollower", baseCF) end

-- ===== EQUIP from the Pet Hub -> spawn THAT pet as the follower (or despawn on unequip). Lets you equip any owned pet. =====
task.spawn(function()
	local pee = RS:WaitForChild("PetEquipEvent", 30)
	if not pee then return end
	local EQUIP_TMPL = { StegoPet = "StegosaurusTemplate", RaptorPet = "VelociraptorTemplate", SharkPet = "SharkTemplate", TriceratopsPet = "TriceratopsTemplate" }
	pee.OnClientEvent:Connect(function(petId)
		if not petId or petId == false then -- unequipped -> remove the follower
			if st.pet then pcall(function() st.pet:Destroy() end); petFX[st.pet]=nil; petScale[st.pet]=nil; petLevel[st.pet]=nil; st.pet = nil end
			return
		end
		local tmpl = EQUIP_TMPL[petId]
		if not tmpl then warn("[PetFollow] equipped '"..tostring(petId).."' has no template mapping"); return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(FOLLOW_OFFSET.X, FOLLOW_OFFSET.Y, FOLLOW_OFFSET.Z)) or CFrame.new(0,8,0)
		spawnFollowerFromTemplate(tmpl, petId .. "Follower", at)  -- swaps st.pet to the equipped pet
	end)
	print("[PetFollow] equip listener ready -> equipping a pet in the hub spawns its follower")
end)

-- ===== server-driven level (PetUpgrades.server.luau): re-apply the follower's evolve look on PetStateEvent =====
task.spawn(function()
	local pse = RS:WaitForChild("PetStateEvent", 20)
	if not pse then return end
	pse.OnClientEvent:Connect(function(payload)
		if not (payload and st.pet) then return end
		local d = payload.StegoPet or payload.RaptorPet or payload.SharkPet or payload.TriceratopsPet or payload.SpinosaurusPet or payload.TyrannosaurusPet
		if not d then for _, v in pairs(payload) do if type(v) == "table" then d = v; break end end end
		if d then
			st.level = d.level or st.level
			st.rare  = d.rare or false
			applyLevelVisual(st.pet, st.level, st.rare)
		end
	end)
end)

-- ===== keys: ] = real server level-up (updates hub + follower), [ = local preview down, R = rare preview =====
local function setLevel(lv)
	st.level = math.clamp(lv, 1, 25)
	if st.pet then applyLevelVisual(st.pet, st.level, st.rare) end
end
UserInput.InputBegan:Connect(function(io, gp)
	if gp then return end
	if io.KeyCode == Enum.KeyCode.RightBracket then
		local up = RS:FindFirstChild("PetUpgradeEvent")
		if up then pcall(function() up:FireServer("StegoPet") end) else setLevel(st.level + 1) end
	elseif io.KeyCode == Enum.KeyCode.LeftBracket then setLevel(st.level - 1)
	elseif io.KeyCode == Enum.KeyCode.R then st.rare = not st.rare; if st.pet then applyLevelVisual(st.pet, st.level, st.rare) end end
end)

print("[PetFollow] ready -- hatch a Stego to get a follower. Keys: ] level+  [ level-  R rare")
