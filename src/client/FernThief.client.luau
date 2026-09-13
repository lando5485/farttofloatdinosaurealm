--======================================================================
-- FernThief.client.luau  (LocalScript)
--======================================================================
-- Island2 "Fern Frontier" (climb slot 10) quest: THE FERN THIEF.
--
-- A baby Stego raids the FrillRancher's ferns every night. He gives you
-- 3 traps per round but there are ~6 trap spots around the island,
-- so you CHOOSE where to set them -- that gap is the strategy.
--
-- Open spots fire GREEN light beams while placing; in rounds 2-3 the
-- spots the thief actually prowls glow GOLD -- read the colours, place
-- smart. (This replaced a footprint-trail clue mechanic that was cut:
-- one visual language, the beams tell you everything.)
--
--   ROUND 1  Whatever you trap catches the WRONG jungle critters (a
--            grumpy crab, a startled armadillo) while the real thief
--            raids an open spot, yoinks a fern from the Rancher's basket
--            and vanishes into the ferns.
--   ROUND 2  Three spots glow GOLD -- the thief only visits those. Trap
--            one it visits and the cage drops... and it wriggles out.
--   ROUND 3  The Rancher's SHINY FERN: bait, placeable at ONE spot [F].
--            Bait a spot AND trap the SAME spot [E] -> caught. Forgot
--            the trap? It eats the bait and the round retries with a
--            hint. No fail states anywhere.
--
-- ENDING: [E] "Befriend" on the cage -- the baby Stego nuzzles you and
-- BECOMES YOUR PET (fires the same _G.GrantTriceratops the retired egg
-- used: follower + Pet Hub card + server StegoHatched).
--
-- ===== THE QUEST IS NPC-DRIVEN AND ON-SCREEN (v2 rework) =====
-- The first build hung everything off a built "shrine" monument and told
-- the story in floatTexts there. Reworked after playtest:
--   * NO monument. The FrillRancher IS the quest: his dialogue starts it,
--     his speech bubbles narrate the beats, footprints start at HIS feet.
--   * ON-SCREEN OBJECTIVE: a jungle-green banner (GeyserQuest's HUD
--     pattern) always says exactly what to do next, visible while you are
--     on the island. floatTexts alone were too easy to miss.
--   * TRAP SPOTS GLOW: while placing, every open spot fires a tall neon
--     LIGHT BEAM + pulsing ring you can see across the island. They were
--     "a dirt patch you had to already know about".
--   * SPOTS SIT ON THE GROUND: the ground ray now starts just above each
--     marker and punches through canopy/foliage (CanCollide-false or
--     near-invisible hits), instead of starting at the island bbox top --
--     which hit TREE CANOPY over some markers and floated the props.
--   * THE THIEF STAYS ON THE ISLAND: it escapes to a far point ON the
--     island and vanishes in a leaf-puff. It used to sprint off the rim
--     and jog into open sky.
--   * THE CAGE SHOWS THE BABY: bars are thin, sized from the thief's own
--     bounding box, no low hoop. The old cage was a wooden barrel that
--     completely hid what you'd caught -- the whole payoff.
--
-- PLACEMENT: 4+ parts with "trap" in the name (e.g. "trapmarker")
-- scattered around island2 -- ghosted at boot like Dig/putdino markers.
-- 6 is the sweet spot. (A leftover "MonumentSpot" part is ghosted too,
-- so retired markers never show.) Fewer than 4 -> probed fallback ring
-- + a warn.
--
-- The thief is a scaled-down clone of the published StegosaurusTemplate,
-- so what you chase is what you get. All props client-side + anchored,
-- like GeyserQuest's. /done (or complete10) skips to the grant.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local TS        = game:GetService("TweenService")

local DinoRealm    = RS:WaitForChild("DinosaurRealm")
local DoneCommand  = require(DinoRealm:WaitForChild("DoneCommand"))
local HatchBurst   = require(DinoRealm:WaitForChild("HatchBurst"))

local player = Players.LocalPlayer

-- ===== tuning =====
local TRAPS_PER_ROUND = 3
local THIEF_SPEED     = 15      -- studs/sec on raids (slower on the bait approach)
local CHIME_ID = "rbxasset://sounds/electronicpingshort.wav"  -- built-in, no moderation risk

-- Pet templates face +X (see the Stego builder's ASCII side view: "pet faces RIGHT"),
-- but CFrame.lookAt points -Z at the target -- without this the baby runs SIDEWAYS.
local FACE_FIX = CFrame.Angles(0, math.rad(90), 0)

-- SOUND IDS -- hand-picked from the Toolbox by the owner; swap freely here.
-- The thief's squeak stays a pitched built-in ping (no ID given -- it's cute).
local SOUNDS = {
	nightBed  = "rbxassetid://9112792684",     -- looping night jungle bed (raids)
	dawnBirds = "rbxassetid://109610333077900",-- morning birds when night lifts
	rustle    = "rbxassetid://5108956689",     -- leaf rustle: appear / vanish / prowl
	munch     = "rbxassetid://5630037419",     -- fern chomping
	trapPlace = "rbxassetid://118045282328349",-- setting a trap
	boing     = "rbxassetid://131916027000817",-- trap SNAP + the wriggle-out escape
	woodHit   = "rbxassetid://9118617342",     -- cage slamming down
	sadGag    = "rbxassetid://104211465655831",-- wrong-critter comedy sting
	shimmer   = "rbxassetid://136730840543746",-- shiny fern sparkle
	success   = "rbxassetid://115778296381875",-- CAUGHT!
	love      = "rbxassetid://130304040865448",-- the befriend heart moment
	thud      = "rbxassetid://9125402735",     -- low rumble (kept as a spare)
}

local FERN   = Color3.fromRGB(96, 170, 70)
local FERN2  = Color3.fromRGB(70, 140, 60)
local STONE  = Color3.fromRGB(126, 133, 116)
local BROWN  = Color3.fromRGB(140, 108, 74)
local MUD    = Color3.fromRGB(78, 60, 42)
local GOLDEN = Color3.fromRGB(255, 224, 130)
local WARM   = Color3.fromRGB(255, 210, 120)
local BEAM   = Color3.fromRGB(150, 255, 130)

local st = { started = false, done = false, phase = "wait", round = 1,
	trapsLeft = 0, baitLeft = 0, baitSpot = nil, fernTaken = false }

-- ===== tiny helpers (same idioms the other quests use) =====
local function floatText(pos, text, color, offY)
	-- offY: studs above pos (default 3). Pass a SMALL one for lines shown during a
	-- camera close-up -- at cutscene framing the default floats clean off-screen.
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.CanTouch=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	-- MaxDistance is LOAD-BEARING: an AlwaysOnTop billboard sized in OFFSET pixels
	-- renders at constant screen size from ANY distance -- quest chatter was popping
	-- up on players' screens from other islands, thousands of studs away.
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,340,0,52); bb.StudsOffset=Vector3.new(0,offY or 3,0); bb.AlwaysOnTop=true; bb.MaxDistance=250; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=24; lbl.TextColor3=color or Color3.fromRGB(230,236,196); lbl.Text=text; lbl.TextWrapped=true; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(2.4), {TextTransparency=1}):Play()
	task.delay(2.6, function() a:Destroy() end)
end

local function chime(parent, pitch, volume)
	local s = Instance.new("Sound")
	s.SoundId = CHIME_ID; s.PlaybackSpeed = pitch; s.Volume = volume or 0.8
	s.RollOffMinDistance = 14; s.RollOffMaxDistance = 260
	s.Parent = parent; s:Play()
	s.Ended:Once(function() s:Destroy() end); task.delay(4, function() pcall(function() s:Destroy() end) end)
end

local function sfx(parent, id, volume, pitch)   -- one-shot positional sound
	if not parent or not id then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.7; s.PlaybackSpeed = pitch or 1
	s.RollOffMinDistance = 14; s.RollOffMaxDistance = 300
	s.Parent = parent; s:Play()
	s.Ended:Once(function() s:Destroy() end); task.delay(10, function() pcall(function() s:Destroy() end) end)
end

-- ===== on-screen objective banner (GeyserQuest's HUD pattern, jungle chrome) =====
local hudLbl, hudGui
local function buildHUD(isl)
	local pgui = player:WaitForChild("PlayerGui")
	hudGui = Instance.new("ScreenGui"); hudGui.Name = "FernThiefHUD"; hudGui.ResetOnSpawn = false
	hudGui.IgnoreGuiInset = true; hudGui.DisplayOrder = 60; hudGui.Enabled = false; hudGui.Parent = pgui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0); f.Position = UDim2.new(0.5, 0, 0, 92)
	f.Size = UDim2.fromOffset(400, 44); f.BackgroundColor3 = Color3.fromRGB(38, 58, 34); f.BackgroundTransparency = 0.08; f.Parent = hudGui
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
	local s = Instance.new("UIStroke", f); s.Color = FERN; s.Thickness = 2
	hudLbl = Instance.new("TextLabel"); hudLbl.Size = UDim2.new(1, -16, 1, 0); hudLbl.Position = UDim2.new(0, 8, 0, 0)
	hudLbl.BackgroundTransparency = 1; hudLbl.Font = Enum.Font.FredokaOne; hudLbl.TextScaled = true
	hudLbl.TextColor3 = Color3.fromRGB(225, 245, 200); hudLbl.Parent = f
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 21; c.Parent = hudLbl end
	-- visible only while ON island2, mid-quest, with something to say
	task.spawn(function()
		while hudGui.Parent do
			local on = false
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and isl and isl.Parent then
				local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
				if ok and size.Magnitude > 1 then
					local d = hrp.Position - cf.Position
					on = math.abs(d.X) <= size.X/2 + 40 and math.abs(d.Z) <= size.Z/2 + 40 and math.abs(d.Y) <= size.Y/2 + 120
				end
			end
			hudGui.Enabled = on and st.started and not st.done and hudLbl.Text ~= ""
			task.wait(0.5)
		end
	end)
end
local function objective(text)
	if hudLbl then hudLbl.Text = text and ("\u{1F33F} " .. text) or "" end
	if text == nil or text == "" then if hudLbl then hudLbl.Text = "" end end
end

-- ===== boot =====
task.spawn(function()
	local isl = Workspace:FindFirstChild("island2") or Workspace:WaitForChild("island2", 120)
	if not isl then warn("[FernThief] island2 not found -- quest not built"); return end
	local function streamedIn()
		local ok, _, size = pcall(function() return isl:GetBoundingBox() end)
		return ok and size ~= nil and size.Magnitude > 1
	end
	if not streamedIn() then
		print("[FernThief] island2 has not streamed in yet -- waiting until the player reaches it...")
		while not streamedIn() do task.wait(1) end
	end
	local bcf, bsize = isl:GetBoundingBox()
	buildHUD(isl)

	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { isl }
	-- WALKABLE ground: start the ray just above `fromY` when given (a marker), else the
	-- island top, and punch through canopy/foliage -- anything you couldn't stand on.
	local function groundAt(x, z, fallbackY, fromY)
		local origin = Vector3.new(x, fromY or (bcf.Position.Y + bsize.Y/2 + 60), z)
		for _ = 1, 6 do
			local hit = Workspace:Raycast(origin, Vector3.new(0, -(bsize.Y + 150), 0), rp)
			if not hit then return fallbackY end
			if hit.Instance.CanCollide and hit.Instance.Transparency < 0.95 then return hit.Position.Y end
			origin = hit.Position - Vector3.new(0, 0.1, 0)
		end
		return fallbackY
	end
	local function playerOnIsland()
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
		local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
		if not (ok and size.Magnitude > 1) then return false end
		local d = hrp.Position - cf.Position
		return math.abs(d.X) <= size.X/2 + 40 and math.abs(d.Z) <= size.Z/2 + 40 and math.abs(d.Y) <= size.Y/2 + 120
	end
	local function randomGroundPoint()
		for _ = 1, 12 do
			local ang = math.random() * 2 * math.pi
			local r = (0.25 + math.random() * 0.15) * math.min(bsize.X, bsize.Z)
			local x, z = bcf.Position.X + math.cos(ang) * r, bcf.Position.Z + math.sin(ang) * r
			local y = groundAt(x, z, nil)
			if y then return Vector3.new(x, y, z) end
		end
		return nil
	end

	-- ===== the quest-giver: the FrillRancher himself =====
	local npc = Workspace:FindFirstChild("FrillRancher") or Workspace:WaitForChild("FrillRancher", 30)
	local function npcPos()
		if npc and npc.Parent then
			local ok, cf = pcall(function() return npc:GetPivot() end)
			if ok then return cf.Position end
		end
		return Vector3.new(bcf.Position.X, groundAt(bcf.Position.X, bcf.Position.Z, bcf.Position.Y), bcf.Position.Z)
	end
	local function speak(text)   -- the Rancher's speech bubble -- the quest's narrator
		floatText(npcPos() + Vector3.new(0, 6.5, 0), text, WARM)
	end
	if not npc then warn("[FernThief] FrillRancher not found on island2 -- narrating from the island centre") end
	local homePos = npcPos()   -- footprints start at his feet

	-- ===== trap spots ("trap" in the name) =====
	-- MARKERS ARE FOUND ANYWHERE, not just inside the island model. Half the
	-- hand-placed markers sat loose in Workspace (not parented under island2), so
	-- the old descendants-only scan missed them -- the quest then invented probed
	-- fallback spots (glow where nothing was marked) while the REAL marker parts
	-- stood there visible and un-ghosted. Now any trap-named part whose position
	-- is over island2's footprint counts, wherever it is parented; trap-named
	-- parts NOT over the island are warned about and ignored.
	local spots = {}
	local seenMarkers = {}
	local function overIsland(p)
		local d = p - bcf.Position
		return math.abs(d.X) <= bsize.X/2 + 60 and math.abs(d.Z) <= bsize.Z/2 + 60
			and math.abs(d.Y) <= bsize.Y/2 + 200
	end
	local function scanForMarkers(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") and not seenMarkers[d] then
				local n = d.Name:lower()
				if n:find("trap", 1, true) then
					seenMarkers[d] = true
					if overIsland(d.Position) then
						local top = d.Position + Vector3.new(0, d.Size.Y/2, 0)
						-- ray from JUST ABOVE THE MARKER, not the island top -- see header
						local y = groundAt(top.X, top.Z, top.Y, top.Y + 12)
						table.insert(spots, { pos = Vector3.new(top.X, y, top.Z) })
						d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
						print(("[FernThief] trap spot %d: '%s' at (%.0f, %.0f, %.0f)%s"):format(
							#spots, d.Name, top.X, top.Y, top.Z,
							d:IsDescendantOf(isl) and "" or "  (loose in Workspace -- works, but consider parenting it under island2)"))
					else
						warn(("[FernThief] '%s' is trap-named but NOT over island2 (at %.0f, %.0f, %.0f) -- ignored"):format(
							d.Name, d.Position.X, d.Position.Y, d.Position.Z))
					end
				elseif n:find("monument", 1, true) and overIsland(d.Position) then
					seenMarkers[d] = true
					d.Transparency = 1; d.CanCollide = false; d.CanQuery = false   -- retired marker: never show it
				end
			end
		end
	end
	scanForMarkers(isl)
	scanForMarkers(Workspace)
	-- StreamingEnabled can deliver loose markers a beat after the island itself:
	-- keep rescanning briefly before concluding they do not exist.
	do
		local t0 = os.clock()
		while #spots < 4 and os.clock() - t0 < 20 do
			task.wait(2)
			scanForMarkers(isl); scanForMarkers(Workspace)
		end
	end
	if #spots < 4 then
		warn(("[FernThief] only %d 'trap' marker(s) found over island2 -> adding probed fallback spots. Place ~6 parts named 'trapmarker' around the island."):format(#spots))
		for i = 1, 8 do
			if #spots >= 6 then break end
			local p = randomGroundPoint()
			if p then table.insert(spots, { pos = p }) end
		end
	end
	if #spots < 4 then
		warn(("[FernThief] still only %d usable trap spot(s) -- quest needs 4+ (3 traps must never cover every spot). Quest disabled; /done still grants."):format(#spots))
	end
	print(("[FernThief] %d trap spots on island2"):format(#spots))

	-- ===== props =====
	local props = Instance.new("Model"); props.Name = "FernThiefQuest"; props.Parent = Workspace
	local function part(name, sz, col, cf, mat, shape, parent)
		local p = Instance.new("Part"); p.Name = name
		if shape then p.Shape = shape end
		p.Size=sz; p.Color=col; p.Material=mat or Enum.Material.Slate
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
		p.CFrame=cf; p.Parent=parent or props; return p
	end
	local function fernTuft(pos, scale, parent)
		scale = scale or 1
		for k = 1, 4 do
			local w = Instance.new("WedgePart")
			w.Size = Vector3.new(0.3, 2.4 * scale, 0.9 * scale)
			w.Color = (k % 2 == 0) and FERN or FERN2; w.Material = Enum.Material.Grass
			w.Anchored=true; w.CanCollide=false; w.CanQuery=false; w.CanTouch=false
			w.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(k * 90 + 20), math.rad(18))
				* CFrame.new(0, 1.0 * scale, 0)
			w.Parent = parent or props
		end
	end
	local function leafPuff(pos)   -- the thief's vanish/appear FX
		local snd = part("PuffSnd", Vector3.new(0.4, 0.4, 0.4), FERN, CFrame.new(pos))
		snd.Transparency = 1
		sfx(snd, SOUNDS.rustle, 0.8)
		task.delay(5, function() snd:Destroy() end)
		for k = 1, 8 do
			local ang = k * math.pi / 4
			local leaf = part("Puff", Vector3.new(0.7, 0.12, 0.5), (k % 2 == 0) and FERN or FERN2,
				CFrame.new(pos + Vector3.new(0, 1, 0)), Enum.Material.Grass)
			TS:Create(leaf, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(pos + Vector3.new(math.cos(ang)*3.2, 2.2 + math.random(), math.sin(ang)*3.2)) * CFrame.Angles(math.random(), math.random(), 0),
				Transparency = 1,
			}):Play()
			task.delay(0.8, function() leaf:Destroy() end)
		end
	end

	-- the Rancher's fern basket -- the thing being raided (round 1's yoink target)
	local basketPos
	do
		local bp2 = homePos + Vector3.new(3.2, 0, 2.4)
		basketPos = Vector3.new(bp2.X, groundAt(bp2.X, bp2.Z, homePos.Y, homePos.Y + 8), bp2.Z)
		part("Basket", Vector3.new(2.4, 1.2, 2.4), BROWN, CFrame.new(basketPos + Vector3.new(0, 0.6, 0)), Enum.Material.WoodPlanks, Enum.PartType.Cylinder).CFrame = CFrame.new(basketPos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		for k = 1, 3 do
			part("BasketFern" .. k, Vector3.new(1.2, 0.6, 0.7), FERN, CFrame.new(basketPos + Vector3.new((k-2)*0.6, 1.35, 0)) * CFrame.Angles(0, k, 0), Enum.Material.Grass)
		end
	end

	-- per-spot dressing: grounded dirt patch + pebbles, and a LIGHT BEAM + pulsing
	-- ring that fire while the spot is open for placing -- visible across the island.
	for i, spot in ipairs(spots) do
		local p = spot.pos
		spot.anchor = part("Spot" .. i, Vector3.new(0.6, 3.2, 4.2), MUD, CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Ground, Enum.PartType.Cylinder)
		for k = 1, 3 do
			part("Pebble", Vector3.new(0.8, 0.6, 0.7), STONE, CFrame.new(p + Vector3.new(math.cos(k*2.1)*2.2, 0.3, math.sin(k*2.1)*2.2)), nil, Enum.PartType.Ball)
		end
		spot.ring = part("Ring" .. i, Vector3.new(0.35, 8, 8), BEAM, CFrame.new(p + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Neon, Enum.PartType.Cylinder)
		spot.ring.Transparency = 1
		-- upright light pillar: a cylinder's axis is X, so roll it 90 degrees to stand it up
		spot.beam = part("Beam" .. i, Vector3.new(30, 2.2, 2.2), BEAM, CFrame.new(p + Vector3.new(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Neon, Enum.PartType.Cylinder)
		spot.beam.Transparency = 1
		-- spinning gem at head height inside the beam -- the "come here" the beam alone lacked
		spot.gem = part("Gem" .. i, Vector3.new(1.7, 1.7, 1.7), BEAM, CFrame.new(p + Vector3.new(0, 9, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Enum.Material.Neon)
		spot.gem.Transparency = 1
		spot.light = Instance.new("PointLight"); spot.light.Color = BEAM; spot.light.Range = 0; spot.light.Brightness = 5; spot.light.Parent = spot.ring
	end
	-- The glow means exactly one thing: "this spot still needs a trap". It is on only
	-- while PLACING and only on untrapped spots -- trap one and its beam dies, so the
	-- remaining light pillars double as a you-can-see-it-from-anywhere trap counter.
	-- CLUE SPOTS GLOW GOLD (replaces the cut footprint mechanic): in rounds 2-3 the
	-- spots the thief actually prowls turn golden -- read the colours, place smart.
	local function setSpotGlow(spot, on)
		spot.glowOn = on
		local col = spot.clue and GOLDEN or BEAM
		spot.ring.Color = col; spot.beam.Color = col; spot.gem.Color = col; spot.light.Color = col
		spot.ring.Transparency = on and 0.05 or 1
		spot.beam.Transparency = on and 0.2 or 1
		spot.gem.Transparency = on and 0 or 1
		spot.light.Range = on and 32 or 0
	end
	-- strong pulse + gem spin on whatever is glowing -- and a PROXIMITY FADE: the
	-- glow is a beacon for finding the spot, not a floodlight for standing in. It
	-- dims as you approach (fully calm within ~7 studs) so it never blinds you
	-- while you line up the trap, and swells back as you leave.
	task.spawn(function()
		local t = 0
		while props.Parent do
			t += 0.06
			local puls = 0.15 * math.sin(t * 3)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			for _, spot in ipairs(spots) do
				if spot.glowOn then
					local fade = 0
					if hrp then
						local d = (hrp.Position - spot.pos).Magnitude
						fade = math.clamp(1 - (d - 7) / 12, 0, 1)   -- 0 beyond 19 studs -> 1 within 7
					end
					spot.beam.Transparency = math.min(1, 0.2 + puls + fade * 0.75)
					spot.ring.Transparency = math.min(1, 0.05 + math.max(0, puls) + fade * 0.6)
					spot.gem.Transparency = math.min(1, fade * 0.85)
					spot.light.Range = 32 * (1 - fade)
					spot.gem.CFrame = CFrame.new(spot.pos + Vector3.new(0, 9 + math.sin(t * 2) * 0.6, 0))
						* CFrame.Angles(math.rad(45), t * 1.5, math.rad(45))
				end
			end
			task.wait(0.06)
		end
	end)

	-- ===== NIGHT MODE -- THIS PLAYER ONLY =====
	-- The raids happen at night. Lighting property changes made from a LocalScript
	-- NEVER replicate, so only the quest player's sky darkens -- every other player's
	-- world (and their own screenshots of it) stays exactly as it was. Fireflies wake
	-- up around the trap spots while it lasts; everything restores when the raid ends.
	local Lighting = game:GetService("Lighting")
	local SoundService = game:GetService("SoundService")
	local nightOn = false
	local baseLight = nil      -- the island's TRUE daytime look, captured exactly once
	local lightTween = nil     -- in-flight transition; cancelled before starting a new one
	local duckedMusic = {}     -- [Sound] = original volume; music is silenced at night
	local nightBed = Instance.new("Sound")
	nightBed.SoundId = SOUNDS.nightBed; nightBed.Looped = true; nightBed.Volume = 0
	nightBed.Parent = game:GetService("SoundService")
	local fireflies = {}
	local function setNight(on)
		if on == nightOn then return end
		nightOn = on
		if lightTween then lightTween:Cancel(); lightTween = nil end
		if on then
			-- Capture the daytime baseline ONCE, ever. Re-capturing each raid sampled
			-- the half-restored values of the PREVIOUS dawn tween, so the "day" the
			-- next dawn returned to drifted darker every round -- the broken cycle.
			if not baseLight then
				baseLight = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness,
					OutdoorAmbient = Lighting.OutdoorAmbient, Ambient = Lighting.Ambient }
			end
			lightTween = TS:Create(Lighting, TweenInfo.new(1.8), { ClockTime = 0.4, Brightness = 1,
				OutdoorAmbient = Color3.fromRGB(70, 85, 130), Ambient = Color3.fromRGB(45, 55, 90) })
			lightTween:Play()
			-- night is QUIET: duck whatever music is playing (the game's playlist lives
			-- in SoundService) so the crickets own the soundscape until dawn.
			for _, s in ipairs(SoundService:GetChildren()) do
				if s:IsA("Sound") and s ~= nightBed and s.Volume > 0 then
					duckedMusic[s] = s.Volume
					TS:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
				end
			end
			nightBed:Play(); TS:Create(nightBed, TweenInfo.new(1.5), { Volume = 0.765 }):Play()
			for k = 1, 14 do
				local anchorSpot = spots[(k - 1) % math.max(1, #spots) + 1]
				local anchor = (anchorSpot and anchorSpot.pos or homePos)
					+ Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
				local fly = part("Firefly", Vector3.new(0.25, 0.25, 0.25), GOLDEN, CFrame.new(anchor + Vector3.new(0, 3, 0)), Enum.Material.Neon, Enum.PartType.Ball)
				local fl = Instance.new("PointLight"); fl.Color = GOLDEN; fl.Range = 6; fl.Brightness = 1.2; fl.Parent = fly
				table.insert(fireflies, { p = fly, a = anchor, seed = math.random() * 20 })
			end
			task.spawn(function()
				while nightOn do
					local t = os.clock()
					for _, f in ipairs(fireflies) do
						if f.p.Parent then
							f.p.CFrame = CFrame.new(f.a + Vector3.new(
								math.sin(t * 0.7 + f.seed) * 5,
								3.2 + math.sin(t * 1.3 + f.seed * 2) * 1.6,
								math.cos(t * 0.9 + f.seed) * 5))
							f.p.Transparency = 0.1 + 0.5 * math.abs(math.sin(t * 2 + f.seed * 3))
						end
					end
					task.wait(0.05)
				end
			end)
		else
			if baseLight then
				lightTween = TS:Create(Lighting, TweenInfo.new(2), baseLight)
				lightTween:Play()
			end
			for s, vol in pairs(duckedMusic) do
				pcall(function() TS:Create(s, TweenInfo.new(2), { Volume = vol }):Play() end)
			end
			duckedMusic = {}
			sfx(SoundService, SOUNDS.dawnBirds, 0.55)   -- morning birdsong as the light returns
			TS:Create(nightBed, TweenInfo.new(1.5), { Volume = 0 }):Play()
			task.delay(1.6, function() if not nightOn then nightBed:Stop() end end)
			for _, f in ipairs(fireflies) do pcall(function() f.p:Destroy() end) end
			fireflies = {}
		end
	end

	-- ===== snares, bait, footprints =====
	local function buildSnare(spot)
		local m = Instance.new("Model"); m.Name = "Snare"; m.Parent = props
		local p = spot.pos
		part("Sapling", Vector3.new(0.35, 4.4, 0.35), BROWN, CFrame.new(p + Vector3.new(1.6, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(-38)), Enum.Material.Wood, nil, m)
		part("RopeCoil", Vector3.new(0.4, 2.6, 2.6), BROWN, CFrame.new(p + Vector3.new(0, 0.26, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Fabric, Enum.PartType.Cylinder, m)
		for k = 1, 3 do
			part("Leaf", Vector3.new(1.5, 0.12, 1.0), FERN2, CFrame.new(p + Vector3.new(math.cos(k*2)*0.8, 0.4, math.sin(k*2)*0.8)) * CFrame.Angles(0, k, 0), Enum.Material.Grass, nil, m)
		end
		spot.snare = m
		sfx(spot.anchor, SOUNDS.trapPlace, 0.8)
	end
	local function clearSnaresAndBait()
		for _, spot in ipairs(spots) do
			if spot.snare then spot.snare:Destroy(); spot.snare = nil end
			if spot.bait then spot.bait:Destroy(); spot.bait = nil end
		end
		st.baitSpot = nil
	end
	local function buildBait(spot)
		local m = Instance.new("Model"); m.Name = "ShinyFern"; m.Parent = props
		fernTuft(spot.pos, 0.8, m)
		for _, w in ipairs(m:GetChildren()) do w.Material = Enum.Material.Neon; w.Color = GOLDEN end
		local gl = Instance.new("PointLight"); gl.Color = GOLDEN; gl.Range = 10; gl.Brightness = 1.4
		gl.Parent = part("BaitCore", Vector3.new(0.4,0.4,0.4), GOLDEN, CFrame.new(spot.pos + Vector3.new(0,0.8,0)), Enum.Material.Neon, Enum.PartType.Ball, m)
		spot.bait = m
		sfx(spot.anchor, SOUNDS.shimmer, 0.8)
	end

	-- (the footprint-trail clue mechanic was cut -- clue spots glow GOLD instead,
	--  see setSpotGlow. One visual language: beams tell you everything.)

	-- ===== the thief (a shrunken clone of the real Stego pet) =====
	local thief, thiefLift, thiefPos, thiefSize
	local thiefFacing = Vector3.new(0, 0, -1)   -- flat unit vector; every pivot goes through FACE_FIX
	local function buildThief()
		if thief then return end
		local tpl = RS:FindFirstChild("StegosaurusTemplate") or RS:WaitForChild("StegosaurusTemplate", 8)
		if tpl then
			thief = tpl:Clone(); thief.Name = "FernThiefStego"
			for _, d in ipairs(thief:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanQuery=false; d.CanTouch=false end
			end
			pcall(function() thief:ScaleTo(0.85) end)   -- the BABY (big enough to spot at range)
		else
			thief = Instance.new("Model"); thief.Name = "FernThiefStego"
			local body = part("Body", Vector3.new(2.2,1.6,1.4), FERN, CFrame.new(0,1,0), Enum.Material.SmoothPlastic, Enum.PartType.Ball, thief)
			part("Head", Vector3.new(1.1,1.0,1.0), FERN, CFrame.new(1.4,1.3,0), Enum.Material.SmoothPlastic, Enum.PartType.Ball, thief)
			part("Eye1", Vector3.new(0.22,0.22,0.22), Color3.new(0,0,0), CFrame.new(1.8,1.5,0.3), Enum.Material.SmoothPlastic, Enum.PartType.Ball, thief)
			part("Eye2", Vector3.new(0.22,0.22,0.22), Color3.new(0,0,0), CFrame.new(1.8,1.5,-0.3), Enum.Material.SmoothPlastic, Enum.PartType.Ball, thief)
			thief.PrimaryPart = body
		end
		-- golden outline THROUGH foliage + its own little glow, so you never lose it
		local hl = Instance.new("Highlight")
		hl.FillColor = GOLDEN; hl.FillTransparency = 0.88
		hl.OutlineColor = GOLDEN; hl.OutlineTransparency = 0.1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = thief
		local glowPart = thief:FindFirstChildWhichIsA("BasePart", true)
		if glowPart then
			local gl = Instance.new("PointLight"); gl.Color = GOLDEN; gl.Range = 12; gl.Brightness = 1.6; gl.Parent = glowPart
		end
		local okB, _, tsz = pcall(function() return thief:GetBoundingBox() end)
		thiefSize = (okB and tsz) or Vector3.new(2.5, 2, 2.5)
		thiefLift = thiefSize.Y/2 + 0.1
	end
	local function showThiefAt(pos)
		buildThief()
		thiefPos = Vector3.new(pos.X, groundAt(pos.X, pos.Z, pos.Y), pos.Z)
		local toHome = Vector3.new(homePos.X - thiefPos.X, 0, homePos.Z - thiefPos.Z)
		thiefFacing = toHome.Magnitude > 0.05 and toHome.Unit or Vector3.new(0, 0, -1)
		local eye = thiefPos + Vector3.new(0, thiefLift, 0)
		pcall(function() thief:PivotTo(CFrame.lookAt(eye, eye + thiefFacing) * FACE_FIX) end)
		thief.Parent = Workspace
		leafPuff(thiefPos)
	end
	local function squeak() if thief then local pp2 = thief:FindFirstChildWhichIsA("BasePart", true); if pp2 then chime(pp2, 1.7 + math.random() * 0.5, 0.7) end end end
	local function vanishThief()   -- always ON the island: puff + gone, never a sprint off the rim
		if thief and thief.Parent then leafPuff(thiefPos); thief.Parent = nil end
	end
	local function runCore(dest, speed, ignoreDone)
		if not thief then return end
		local from = thiefPos
		local flat = Vector3.new(dest.X - from.X, 0, dest.Z - from.Z)
		local dist = flat.Magnitude
		if dist < 0.5 then return end
		local dur = dist / (speed or THIEF_SPEED)
		thiefFacing = flat.Unit
		local t0 = os.clock()
		-- STAY ON THE GROUND: the ground ray hits whatever is in the way -- a food
		-- stand roof, a crate -- and the baby used to pop up ONTO obstacles crossing
		-- its path, then snap back down. A critter can't step up more than a couple
		-- of studs in one stride, so ground rises steeper than that are ignored and
		-- it just brushes past the obstacle instead of climbing it.
		local lastGy = thiefPos.Y
		while ignoreDone or not st.done do
			local a = math.min(1, (os.clock() - t0) / dur)
			local p = from:Lerp(dest, a)
			local gy = groundAt(p.X, p.Z, p.Y)
			if gy > lastGy + 2.5 then gy = lastGy end
			lastGy = gy
			local hop = math.abs(math.sin(a * dist / 2.6 * math.pi)) * 0.7
			-- a touch of waddle: the run reads as scampering, not gliding
			local waddle = math.sin(os.clock() * 14) * 0.09
			local eye = Vector3.new(p.X, gy + thiefLift + hop, p.Z)
			pcall(function() thief:PivotTo(CFrame.lookAt(eye, eye + thiefFacing) * FACE_FIX * CFrame.Angles(0, 0, waddle)) end)
			if a >= 1 then break end
			task.wait(0.03)
		end
		thiefPos = Vector3.new(dest.X, groundAt(dest.X, dest.Z, dest.Y), dest.Z)
	end
	local function thiefRunTo(dest, speed) runCore(dest, speed, false) end
	-- alive-idle: bob + wiggle in place (munching, sniffing, sulking)
	local function thiefIdle(dur)
		local t0 = os.clock()
		while os.clock() - t0 < dur and not st.done and thief and thief.Parent do
			local t = os.clock() * 3
			local eye = thiefPos + Vector3.new(0, thiefLift + math.abs(math.sin(t * 1.7)) * 0.14, 0)
			pcall(function() thief:PivotTo(CFrame.lookAt(eye, eye + thiefFacing) * FACE_FIX * CFrame.Angles(0, math.sin(t) * 0.22, 0)) end)
			task.wait(0.04)
		end
	end
	local function escapeAndVanish(fast)
		-- a SHORT dash away from the Rancher, then gone in a leaf-puff -- it does
		-- not tour the island past spots that have nothing to do with the player
		local dir = Vector3.new(thiefPos.X - homePos.X, 0, thiefPos.Z - homePos.Z)
		if dir.Magnitude < 0.05 then dir = Vector3.new(1, 0, 0) end
		local p = thiefPos + dir.Unit * 22
		if not groundAt(p.X, p.Z, nil) then p = randomGroundPoint() or thiefPos end
		thiefRunTo(p, THIEF_SPEED * (fast and 1.5 or 1.1))
		vanishThief()
	end

	-- ===== cage (sized from the thief so the baby stays VISIBLE) + gag critters =====
	local function buildCage(pos)
		local r = math.max(thiefSize and thiefSize.X or 2.5, thiefSize and thiefSize.Z or 2.5) / 2 + 1.3
		local h = (thiefSize and thiefSize.Y or 2) + 1.6
		local cage = Instance.new("Model"); cage.Name = "VineCage"; cage.Parent = props
		for k = 1, 6 do
			local ang = k * math.pi / 3
			part("Bar", Vector3.new(0.25, h, 0.25), BROWN, CFrame.new(pos + Vector3.new(math.cos(ang)*r, h/2, math.sin(ang)*r)), Enum.Material.Wood, nil, cage)
		end
		part("Hoop", Vector3.new(0.3, r*2 + 0.4, r*2 + 0.4), FERN2, CFrame.new(pos + Vector3.new(0, h, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Grass, Enum.PartType.Cylinder, cage)
		local target = cage:GetPivot()
		cage:PivotTo(target * CFrame.new(0, 9, 0))
		for step = 1, 8 do cage:PivotTo(target * CFrame.new(0, 9 - step * 9/8, 0)); task.wait(0.02) end
		cage:PivotTo(target)
		sfx(cage:FindFirstChildWhichIsA("BasePart"), SOUNDS.woodHit, 0.9)
		return cage
	end

	local GAGS = {
		{ tpl = "CoconutCrabTemplate",      text = "A grumpy Coconut Crab?! That's not the thief..." },
		{ tpl = "BurritoArmadilloTemplate", text = "A startled Armadillo?! Wrong again..." },
		{ tpl = "FrostPenguinTemplate",     text = "A... penguin? In the JUNGLE?!" },
	}
	local function wrongCatch(spot, gagIndex)
		local gag = GAGS[(gagIndex - 1) % #GAGS + 1]
		if spot.snare then spot.snare:Destroy(); spot.snare = nil end
		sfx(spot.anchor, SOUNDS.boing, 0.9)
		task.delay(0.4, function() sfx(spot.anchor, SOUNDS.sadGag, 0.8) end)
		local critter
		local tpl = RS:FindFirstChild(gag.tpl)
		if tpl then
			critter = tpl:Clone()
			for _, d in ipairs(critter:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanQuery=false; d.CanTouch=false end
			end
			pcall(function() critter:PivotTo(CFrame.new(spot.pos + Vector3.new(0, 1.4, 0))) end)
			-- same can't-miss treatment as the thief: warm outline through everything
			local hl = Instance.new("Highlight")
			hl.FillColor = WARM; hl.FillTransparency = 0.88
			hl.OutlineColor = WARM; hl.OutlineTransparency = 0.1
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = critter
			critter.Parent = Workspace
		end
		floatText(spot.pos + Vector3.new(0, 4, 0), "SNAP! " .. gag.text, WARM)
		task.delay(2.6, function()
			if critter then
				local base = critter:GetPivot()
				for step = 1, 20 do pcall(function() critter:PivotTo(base * CFrame.new(0.6 * step, math.abs(math.sin(step))*0.3, 0)) end); task.wait(0.03) end
				critter:Destroy()
			end
		end)
	end

	-- ===== prompts / placing =====
	local armCheck   -- set below; prompt handlers call it
	local refreshPrompts
	for _, spot in ipairs(spots) do
		local tp = Instance.new("ProximityPrompt")
		tp.ObjectText = "Trap Spot"; tp.ActionText = "Set Trap"
		tp.KeyboardKeyCode = Enum.KeyCode.E; tp.HoldDuration = 0.3
		tp.MaxActivationDistance = 10; tp.RequiresLineOfSight = false
		tp.Enabled = false; tp.Parent = spot.anchor
		spot.trapPrompt = tp
		tp.Triggered:Connect(function()
			if st.done or st.phase ~= "placing" or st.trapsLeft <= 0 or spot.snare then return end
			buildSnare(spot)
			setSpotGlow(spot, false)   -- snared spots stop glowing: the glow means "still open"
			st.trapsLeft -= 1
			objective(st.trapsLeft > 0 and ("Set your traps at the glowing spots! %d left"):format(st.trapsLeft)
				or (st.round == 3 and st.baitSpot == nil and "Traps set! Now place the SHINY FERN [F] at one spot!" or "Traps set... watch the ferns!"))
			if armCheck then armCheck() end
		end)

		local bp = Instance.new("ProximityPrompt")
		bp.ObjectText = "Trap Spot"; bp.ActionText = "Place Shiny Fern"
		bp.KeyboardKeyCode = Enum.KeyCode.F; bp.HoldDuration = 0.3
		bp.MaxActivationDistance = 10; bp.RequiresLineOfSight = false
		bp.UIOffset = Vector2.new(0, 56)
		bp.Enabled = false; bp.Parent = spot.anchor
		spot.baitPrompt = bp
		bp.Triggered:Connect(function()
			if st.done or st.phase ~= "placing" or st.baitLeft <= 0 or spot.bait then return end
			buildBait(spot)
			st.baitLeft -= 1; st.baitSpot = spot
			objective(st.trapsLeft > 0 and ("Shiny fern down! Now set %d more trap(s) -- one on THIS spot!"):format(st.trapsLeft) or "Bait AND traps set... here it comes!")
			if armCheck then armCheck() end
		end)
	end
	refreshPrompts = function()
		local placing = (st.phase == "placing") and not st.done
		for _, spot in ipairs(spots) do
			-- In rounds 2-3 ONLY the golden clue spots light up and take traps -- green
			-- spots going dark IS the round-2 reveal. Round 1 lights everything.
			-- Round 3: NOTHING lights or takes traps until the Rancher hands over the
			-- Shiny Fern -- the handoff sends you out into a freshly golden island.
			local active = placing and not spot.snare and (st.round == 1 or spot.clue == true)
				and (st.round < 3 or st.fernTaken)
			spot.trapPrompt.Enabled = active and st.trapsLeft > 0
			spot.baitPrompt.Enabled = placing and st.baitLeft > 0 and not spot.bait and spot.clue == true
			setSpotGlow(spot, active)
		end
	end
	armCheck = function()
		refreshPrompts()
		if st.phase == "placing" and st.trapsLeft == 0 and (st.round < 3 or st.baitSpot ~= nil) then
			st.phase = "armed"
			refreshPrompts()
		end
	end

	-- ===== round 3's SHINY FERN: handed over by the Rancher IN PERSON =====
	-- The bait no longer just appears in your pocket. A glowing fern hovers at the
	-- Rancher's hands; [E] "Take Shiny Fern" plays a short zoom-in on it while he
	-- delivers the pitch, then it floats away into your keeping and the bait
	-- prompts unlock. Re-offered automatically if the thief eats one (round-3 retry).
	local fernOffer = nil
	local function offerShinyFern()
		if fernOffer then fernOffer:Destroy(); fernOffer = nil end
		local look = Vector3.new(0, 0, -1)
		pcall(function()
			local lv = npc:GetPivot().LookVector
			local f = Vector3.new(lv.X, 0, lv.Z)
			if f.Magnitude > 0.05 then look = f.Unit end
		end)
		local fernPos = npcPos() + look * 2.2 + Vector3.new(0, 1.6, 0)
		local m = Instance.new("Model"); m.Name = "ShinyFernOffer"; m.Parent = props
		fernTuft(fernPos - Vector3.new(0, 1.0, 0), 0.55, m)
		for _, w in ipairs(m:GetChildren()) do w.Material = Enum.Material.Neon; w.Color = GOLDEN end
		local core = part("OfferCore", Vector3.new(0.35, 0.35, 0.35), GOLDEN, CFrame.new(fernPos), Enum.Material.Neon, Enum.PartType.Ball, m)
		local gl = Instance.new("PointLight"); gl.Color = GOLDEN; gl.Range = 8; gl.Brightness = 1.2; gl.Parent = core
		sfx(core, SOUNDS.shimmer, 0.6)
		local op = Instance.new("ProximityPrompt")
		op.ObjectText = "FrillRancher"; op.ActionText = "Take Shiny Fern"
		op.KeyboardKeyCode = Enum.KeyCode.E; op.HoldDuration = 0.3
		op.MaxActivationDistance = 12; op.RequiresLineOfSight = false; op.Parent = core
		fernOffer = m
		op.Triggered:Once(function()
			if st.done then return end
			op.Enabled = false
			local cam = Workspace.CurrentCamera
			local hrp2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			-- TURN HIM TO FACE YOU, and move the fern to his new front -- the shot used
			-- to catch his side profile because the fern hovered wherever he happened
			-- to be facing when the round began.
			if hrp2 then
				pcall(function()
					local np = npc:GetPivot().Position
					npc:PivotTo(CFrame.lookAt(np, Vector3.new(hrp2.Position.X, np.Y, hrp2.Position.Z)))
					local f = Vector3.new(hrp2.Position.X - np.X, 0, hrp2.Position.Z - np.Z)
					if f.Magnitude > 0.05 then look = f.Unit end
				end)
				local newFernPos = npcPos() + look * 2.2 + Vector3.new(0, 1.6, 0)
				pcall(function() m:PivotTo(m:GetPivot() + (newFernPos - fernPos)) end)
				fernPos = newFernPos
			end
			-- over-your-shoulder zoom at the fern, with his FRONT behind it
			if cam and hrp2 then
				cam.CameraType = Enum.CameraType.Scriptable
				task.delay(7, function() pcall(function() cam.CameraType = Enum.CameraType.Custom end) end)
				local dir = Vector3.new(fernPos.X - hrp2.Position.X, 0, fernPos.Z - hrp2.Position.Z)
				if dir.Magnitude < 0.05 then dir = look else dir = dir.Unit end
				local right = Vector3.new(-dir.Z, 0, dir.X)
				local camPos = hrp2.Position - dir * 1.5 + right * 2.0 + Vector3.new(0, 2.2, 0)
				TS:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.lookAt(camPos, fernPos) }):Play()
			end
			sfx(core, SOUNDS.shimmer, 0.9)
			speak("This is the LEGENDARY SHINY FERN. No thief can resist it...")
			task.wait(2.2)
			if not st.done then speak("Take it! This'll catch him once and for all!") end
			-- the fern floats up and fades into your keeping
			for _, p2 in ipairs(m:GetDescendants()) do
				if p2:IsA("BasePart") then
					TS:Create(p2, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ CFrame = p2.CFrame * CFrame.new(0, 2.5, 0), Transparency = 1 }):Play()
				end
			end
			task.wait(0.9)
			if cam then pcall(function() cam.CameraType = Enum.CameraType.Custom end) end
			if fernOffer then fernOffer:Destroy(); fernOffer = nil end
			if st.done then return end
			st.fernTaken = true
			st.baitLeft = 1
			refreshPrompts()   -- NOW the golden spots blaze -- go get him
			objective("The GOLDEN spots are lit! Bait [F] and trap [E] the SAME spot!")
		end)
	end

	-- ===== round setup + raids (run sequentially from the main flow) =====
	local function pickSpots(n)
		local pool = {}
		for _, s in ipairs(spots) do table.insert(pool, s) end
		for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
		local out = {}
		for i = 1, math.min(n, #pool) do out[i] = pool[i] end
		return out
	end
	local clueSpots = {}

	local function runPlacing(round)
		-- quest beats only play with the player actually ON the island -- speech and
		-- announcements from a quest you flew away from are just noise
		while not st.done and not playerOnIsland() do task.wait(1) end
		if st.done then return end
		st.round = round; st.phase = "placing"
		st.trapsLeft = TRAPS_PER_ROUND
		st.baitLeft = 0   -- round 3's bait must be TAKEN from the Rancher first (see offerShinyFern)
		clearSnaresAndBait()
		for _, s in ipairs(spots) do s.clue = false end
		if round == 1 then
			speak("Something's been stealing my ferns every night!")
			objective(("Set %d traps at the GLOWING spots around the island!"):format(TRAPS_PER_ROUND))
		elseif round == 2 then
			clueSpots = pickSpots(3)
			for _, s in ipairs(clueSpots) do s.clue = true end
			speak("I found fern crumbs! The GOLDEN spots are where it prowls -- trap those!")
			objective("Trap the GOLDEN spots -- that's where the thief prowls!")
		else
			-- 3 golden spots (not 2): only golden spots take traps now, and all 3 traps
			-- must be placeable or the round could never arm
			clueSpots = pickSpots(3)
			for _, s in ipairs(clueSpots) do s.clue = true end
			st.fernTaken = false   -- fern FIRST, traps after -- nothing glows until he hands it over
			offerShinyFern()
			speak("Come here! I've got JUST the thing for that rascal...")
			objective("See the FrillRancher -- he has the secret weapon!")
		end
		refreshPrompts()
		while not st.done and st.phase ~= "armed" do task.wait(0.2) end
		if st.done then return end
		task.wait(2)
	end

	local function trappedSpots()
		local out = {}
		for _, s in ipairs(spots) do if s.snare then table.insert(out, s) end end
		return out
	end

	-- returns "advance" or "caught" or "retry"
	local function runRaid(round)
		st.phase = "raid"; refreshPrompts()
		setNight(true)   -- the raid IS the night (this player's Lighting only)
		objective("Night falls... something's rustling in the ferns!")
		task.wait(2.0)
		if st.done then return "advance" end

		if round == 1 then
			-- comedy round, played entirely ON THE PLAYER'S OWN TRAPS: the thief creeps
			-- up to a trap YOU set, the trap SNAPS a beat early on the wrong critter,
			-- the startled thief bolts to the Rancher's basket, yoinks a fern and
			-- vanishes. (It used to raid a random open spot -- watching it wander
			-- somewhere you never trapped read as the quest ignoring your choices.)
			local snared = trappedSpots()
			local target = snared[1] or spots[1]
			showThiefAt(randomGroundPoint() or target.pos)
			local approach = Vector3.new(target.pos.X - homePos.X, 0, target.pos.Z - homePos.Z)
			if approach.Magnitude < 0.05 then approach = Vector3.new(1, 0, 0) end
			thiefRunTo(target.pos + approach.Unit * 7, THIEF_SPEED * 0.8)
			if st.done then return "advance" end
			squeak(); sfx(target.anchor, SOUNDS.rustle, 0.7)
			floatText(target.pos + Vector3.new(0, 3.5, 0), "*rustle rustle*", FERN)
			thiefIdle(1.0)
			-- the trap fires JUST as it sniffs -- and catches something else entirely
			wrongCatch(target, 1)
			squeak(); thiefIdle(0.8)
			-- a second of your traps snaps in the distance for the double-gag
			task.delay(1.2, function() if snared[2] and not st.done then wrongCatch(snared[2], 2) end end)
			thiefRunTo(basketPos); if st.done then return "advance" end
			squeak(); sfx(thief and thief:FindFirstChildWhichIsA("BasePart", true), SOUNDS.munch, 0.85)
			floatText(basketPos + Vector3.new(0, 4, 0), "*YOINK* -- it grabbed a fern! It's a BABY STEGO?!", WARM)
			thiefIdle(0.7)
			escapeAndVanish(false)
			speak("A baby Stego! I'll mark its favourite spots in GOLD tonight...")
			objective("It vanished into the ferns! Get ready for round 2...")
			task.wait(2.2)
			return "advance"
		end

		if round == 2 then
			-- it only prowls traps YOU set (all on golden spots this round)
			local snared = trappedSpots()
			local visits
			if #snared >= 2 then
				visits = { snared[math.random(#snared)] }
				repeat visits[2] = snared[math.random(#snared)] until visits[2] ~= visits[1]
			elseif #snared == 1 then
				visits = { snared[1] }
			else
				visits = pickSpots(2)
			end
			showThiefAt(randomGroundPoint() or visits[1].pos)
			for _, spot in ipairs(visits) do
				thiefRunTo(spot.pos); if st.done then return "advance" end
				if spot.snare then
					-- NEAR MISS: cage drops, it wriggles out
					spot.snare:Destroy(); spot.snare = nil
					squeak()
					local cage = buildCage(spot.pos)
					floatText(spot.pos + Vector3.new(0, 5, 0), "GOTCHA! ...wait--", GOLDEN)
					task.wait(1.4)
					sfx(spot.anchor, SOUNDS.boing, 0.9, 1.1)
					floatText(spot.pos + Vector3.new(0, 5, 0), "It WRIGGLED OUT through the bars!! SO close!", WARM)
					cage:Destroy()
					escapeAndVanish(true)
					speak("SO close! It's rattled now... I have one last trick.")
					objective("So close!! The Rancher has one last trick...")
					task.wait(2.2)
					return "advance"
				else
					squeak(); sfx(spot.anchor, SOUNDS.munch, 0.85)
					floatText(spot.pos + Vector3.new(0, 3.5, 0), "*munch munch*", FERN)
					thiefIdle(1.1)
				end
			end
			escapeAndVanish(false)
			speak("It dodged us! Trap the GOLDEN spots next time. Still -- I have a trick.")
			objective("It got away clean... but the Rancher has a trick!")
			task.wait(2.2)
			return "advance"
		end

		-- round 3: the bait decides where it goes
		local spot = st.baitSpot
		showThiefAt(randomGroundPoint() or spot.pos)
		thiefRunTo(spot.pos + (spot.pos - homePos).Unit * 6, THIEF_SPEED * 0.6)
		if st.done then return "advance" end
		squeak(); sfx(spot.anchor, SOUNDS.shimmer, 0.7)
		floatText(spot.pos + Vector3.new(0, 4, 0), "Ooooh... shiny...", GOLDEN)
		thiefIdle(1.2)
		thiefRunTo(spot.pos, THIEF_SPEED * 0.5)
		if st.done then return "advance" end
		if spot.snare then
			return "caught"
		else
			if spot.bait then spot.bait:Destroy(); spot.bait = nil end
			squeak(); sfx(spot.anchor, SOUNDS.munch, 0.9)
			floatText(spot.pos + Vector3.new(0, 4, 0), "It ATE the shiny fern and bolted!", WARM)
			escapeAndVanish(true)
			speak("It ate the bait! Trap the SAME spot as the fern this time!")
			task.wait(1.5)
			return "retry"
		end
	end

	-- ===== the happy ending =====
	local function befriendAt(spot)
		st.phase = "caught"
		if spot.snare then spot.snare:Destroy(); spot.snare = nil end
		if spot.bait then spot.bait:Destroy(); spot.bait = nil end
		squeak()
		local cage = buildCage(spot.pos)
		sfx(spot.anchor, SOUNDS.success, 0.9)
		floatText(spot.pos + Vector3.new(0, 5.5, 0), "CAUGHT! The little fern thief!", GOLDEN)
		speak("HA! You got the rascal! Go on -- say hello!")
		objective("You caught it! Walk up and BEFRIEND the baby Stego!")
		-- sad-baby idle bob inside the cage
		task.spawn(function()
			local t = 0
			while cage.Parent and thief and thief.Parent and not st.done do
				t += 0.05
				local eye = thiefPos + Vector3.new(0, thiefLift + math.abs(math.sin(t*2))*0.15, 0)
				pcall(function() thief:PivotTo(CFrame.lookAt(eye, eye + thiefFacing) * FACE_FIX) end)
				task.wait(0.05)
			end
		end)
		local bar = cage:FindFirstChildWhichIsA("BasePart")
		local pp = Instance.new("ProximityPrompt")
		pp.ObjectText = "Baby Stego"; pp.ActionText = "Befriend"
		pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.5
		pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false; pp.Parent = bar
		pp.Triggered:Once(function()
			st.done = true
			cage:Destroy()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local at = hrp and (hrp.CFrame * CFrame.new(0, 0, -5)) or CFrame.new(thiefPos + Vector3.new(0, 1, 0))
			if hrp then runCore(at.Position, THIEF_SPEED * 0.8, true) end   -- ignoreDone: this walk is the ending

			-- ===== THE BEFRIEND CUTSCENE (this client's camera only) =====
			-- Side close-up on the baby -> "Dang it... you caught me!" -> happy
			-- spin-hop -> hatch-burst into the real pet -> pan to you and your new
			-- best friend -> camera handed back. A delayed failsafe restores the
			-- camera no matter what.
			local cam = Workspace.CurrentCamera
			local usedCam = cam and hrp and thief and true or false
			if usedCam then
				cam.CameraType = Enum.CameraType.Scriptable
				task.delay(11, function() pcall(function() cam.CameraType = Enum.CameraType.Custom end) end)
				local eye = thiefPos + Vector3.new(0, thiefLift, 0)
				-- three-quarter shot from the SIDE. Shooting from straight toward the
				-- player put the player's own head between the lens and the dino.
				local toPlayer = Vector3.new(hrp.Position.X - eye.X, 0, hrp.Position.Z - eye.Z)
				if toPlayer.Magnitude < 0.05 then toPlayer = Vector3.new(0, 0, -1) end
				local side = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(55)) * toPlayer.Unit
				local camPos = eye + side * 7 + Vector3.new(0, 2, 0)
				TS:Create(cam, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.lookAt(camPos, eye) }):Play()
			end
			sfx(thief and thief:FindFirstChildWhichIsA("BasePart", true), SOUNDS.love, 0.9)
			squeak()
			-- low offset: the camera is in a close-up; the default height sits off-frame
			floatText(thiefPos + Vector3.new(0, thiefLift + 0.4, 0), "\"Dang it... you caught me!\"", WARM, 0.6)
			task.wait(1.4)
			if thief then
				-- fine, fine... actually this is great -- happy spin-hop on the spot
				local t0 = os.clock()
				while os.clock() - t0 < 1.6 and thief do
					local a = (os.clock() - t0) / 1.6
					local eye2 = thiefPos + Vector3.new(0, thiefLift + math.abs(math.sin(a * 4 * math.pi)) * 0.5, 0)
					pcall(function() thief:PivotTo(CFrame.new(eye2) * CFrame.Angles(0, a * 2 * math.pi, 0) * FACE_FIX) end)
					task.wait(0.03)
				end
			end
			floatText((thief and thiefPos or spot.pos) + Vector3.new(0, thiefLift + 0.6, 0), "It hands over the stolen fern... and wants to come along!", GOLDEN, 1)
			task.wait(0.8)
			HatchBurst.play((thief and thiefPos or spot.pos) + Vector3.new(0, 1, 0), FERN)
			if thief then thief:Destroy(); thief = nil end
			if _G.GrantTriceratops then pcall(function() _G.GrantTriceratops(at) end) end
			objective("")
			setNight(false)   -- dawn breaks on the new friendship
			-- the pan: you and your brand-new best friend, then the camera is yours again
			if usedCam and hrp then
				local camPos2 = (hrp.CFrame * CFrame.new(2.5, 3, -9)).Position
				TS:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ CFrame = CFrame.lookAt(camPos2, hrp.Position + Vector3.new(0, 1, 0)) }):Play()
				task.wait(2.2)
				pcall(function() cam.CameraType = Enum.CameraType.Custom end)
			end
			floatText(at.Position + Vector3.new(0, 4, 0), "The little thief is YOUR Stegosaurus now! \u{1F995}", GOLDEN)
			print("[FernThief] befriended -> Stegosaurus granted (same path the old egg used)")
		end)
	end

	-- ===== /done skip: straight to the grant =====
	DoneCommand.bind(isl, "FernThief", function()
		if st.done then return end
		st.done = true
		clearSnaresAndBait(); refreshPrompts(); vanishThief(); setNight(false)
		if fernOffer then fernOffer:Destroy(); fernOffer = nil end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(0, 0, -5)) or CFrame.new(homePos + Vector3.new(0, 2, 0))
		HatchBurst.play(at.Position + Vector3.new(0, 1, 0), FERN)
		if _G.GrantTriceratops then pcall(function() _G.GrantTriceratops(at) end) end
		objective("")
		floatText(at.Position + Vector3.new(0, 4, 0), "The little thief is YOUR Stegosaurus now! \u{1F995}", GOLDEN)
	end)

	-- ===== main flow =====
	print("[FernThief] island2 'Fern Frontier' quest ready: trap the fern thief (3 rounds). /done to skip.")
	if player:GetAttribute("Island2QuestAccepted") ~= true then
		-- NPCGuide's chevron trail already leads to the Rancher pre-accept; nothing to add
		while not st.done and player:GetAttribute("Island2QuestAccepted") ~= true do task.wait(0.5) end
	end
	if st.done or #spots < 4 then return end
	st.started = true

	local round = 1
	while not st.done and round <= 3 do
		runPlacing(round)
		if st.done then break end
		local outcome = runRaid(round)
		if outcome == "caught" then
			befriendAt(st.baitSpot)   -- night (and the fireflies) hold until the befriend
			break
		end
		setNight(false)               -- dawn between rounds
		if outcome == "retry" then
			-- stay on round 3
		else
			round += 1
		end
	end
	if st.phase ~= "caught" then setNight(false) end   -- /done mid-raid etc: never leave it dark
end)
