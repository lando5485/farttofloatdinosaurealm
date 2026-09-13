--======================================================================
-- RealmPortals.client.luau  (LocalScript)   [SENDING PLACE -- Bean Island]
--======================================================================
-- The three realm portals on Bean Island, built as a polished hub plaza. Dino, Space, Candy.
--
-- PLACEMENT IS YOURS, NOT MINE. Each portal is anchored to ITS OWN marker brick -- the one you placed.
-- Nothing here moves, re-spaces or re-orders them. The bricks say where each portal goes, which way it
-- faces, and how high off the ground it stands; this script only builds detail around that.
-- Your markers sit ~12-14 studs apart, so the whole build is deliberately sized to fit inside that:
-- FOOTPRINT_R caps how far any piece may stray from its own marker, and every platform, arch and
-- decoration is kept inside it. That is what stops the three from bleeding into each other.
--
-- The bricks themselves are invisible and inert -- pure placement markers, never scenery.
--
-- HEADERS ARE ALIGNED. All three name plates are pinned to the SAME world height (the tallest portal's
-- top), so the row reads level even if the bricks are at slightly different heights. One header per
-- portal, each adorned to its own anchor: they can't drift onto a neighbour.
--
-- THE FORCE FIELD IS THE DOOR: it fills the opening, and its Touched starts the transfer. Touch -> fire
-- INTENT (a realm key) -> the SERVER validates the chain gate and teleports. The client never teleports.
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

-- ===== WHY THIS SCRIPT IS NAMED 'RealmPortalsHub' AND NOT 'RealmPortals' =====
-- An OLD copy of this file is baked into the place, and it is named 'RealmPortals'. Both copies used to run
-- the SAME first-come-wins guard: whoever started first set a _G flag and destroyed every LocalScript with
-- a matching name. Roblox does not guarantee sibling start order, so it was a coin flip each join -- and
-- when the stale copy won, it deleted the Rojo one and the game ran on months-old code. That is exactly
-- what "sometimes the outro and the sound do not happen" was: not a bug in the outro, a bug in who is alive.
--
-- The fix is a name the old copy cannot see. Its sweep matches `inst.Name == script.Name` == 'RealmPortals',
-- so renaming the Rojo instance to 'RealmPortalsHub' (in default.project.json) makes this copy invisible to
-- it. It can no longer delete us -- while we can still delete it, because we match on the legacy name below.
-- The race is not won more often now; it is gone. The new copy wins by construction, every join.
--
-- ⚠ This is a WORKAROUND for a place-file problem, not a licence to keep the duplicate. Delete the old
-- 'RealmPortals' LocalScript in Studio's StarterPlayerScripts and republish; the log line below tells you
-- every time it is still there.
local LEGACY_NAMES = { RealmPortals = true, RealmPortalsHub = true }

-- Deliberately NOT a bail-out. If the legacy copy started first it will have set this flag, and bailing is
-- precisely how the good copy used to lose. We take over instead: note it, then go on and neutralise it.
local legacyWonTheRace = _G.__RealmPortalsClient == true
_G.__RealmPortalsClient = true

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- NEUTRALIZE STALE DUPLICATES: destroy any LocalScript carrying the legacy name, anywhere the client keeps
-- scripts. Repeated a few times because a stale copy can be re-parented in late (and because Disabled=true
-- is what actually stops an already-running thread -- Destroy alone does not).
local function nukeStaleClientCopies()
	local removed = 0
	for _, container in ipairs({ script.Parent, player:FindFirstChild("PlayerScripts"), playerGui, game:GetService("ReplicatedFirst") }) do
		if container then
			for _, inst in ipairs(container:GetDescendants()) do
				if inst ~= script and inst:IsA("LocalScript") and LEGACY_NAMES[inst.Name] then
					pcall(function() inst.Disabled = true; inst:Destroy() end)
					removed = removed + 1
				end
			end
		end
	end
	if removed > 0 then
		warn("[RealmPortals] removed " .. removed .. " STALE duplicate client script(s) -- delete them in Studio for good")
	end
end
nukeStaleClientCopies()
task.delay(1, nukeStaleClientCopies); task.delay(4, nukeStaleClientCopies)

if legacyWonTheRace then
	warn("[RealmPortals] the STALE baked-in copy started BEFORE this one and has now been shut down. " ..
		"It may have already drawn part of a portal; this copy owns them from here. " ..
		"Delete the old 'RealmPortals' LocalScript in Studio to stop this happening at all.")
end

-- THE PROOF LINE. If the outro or the travel sound ever look like they "did not run" again, check this
-- first: if it is missing from the output, the copy that booted is not this file, and nothing below ran.
print("[RealmPortals] CLIENT BUILD 10 ACTIVE -- this is the Rojo copy (outro + travel sound + send receipts)")
print("[Transition] FULL-BLEED PASS APPLIED. Every realm transition screen now fills the whole viewport -- " ..
	"no black bars, no band, no hard edge. Updated: RealmPortalOutro (this file -- Space/Dino/Candy outro " ..
	"card; the 420px capsule glow is GONE, ground + glow are both fromScale(1,1) with vertical gradients), " ..
	"CandyArrivalCinematic, DinoArrivalCinematic, DinoRiftCinematic (Space->Dino outro card). Verified " ..
	"already full-bleed, unchanged: BlackHoleCinematic (portal suck-in), DinoRiftCinematic backdrop, " ..
	"CandyRealm/Dino tower-descent IntroTitle cards. IntroCinematic (Space Realm join intro) LEFT AS IT " ..
	"WAS -- it is an intro, not a transition card.")

--------------------------------------------------------------------------------
-- dimensions (studs) -- everything is sized to fit the spacing you already have
--------------------------------------------------------------------------------
local PORTAL_W   = 8.4    -- opening width
local PORTAL_H   = 11     -- opening height
local FOOTPRINT_R = 5.4   -- HARD CAP: no piece of a portal may sit further than this from its marker.
local PLATFORM_R = 5.2    -- circular platform (10.4 wide -> fits inside your ~12-stud gaps, never touches)
local PLATFORM_H = 1.3
local RING_SEGS  = 24     -- stones around the arch
local RUNE_EVERY = 4      -- every Nth stone carries a glowing rune
local PORTAL_YAW = -90    -- degrees CLOCKWISE off the marker's facing. Wrong way round? 0 / 90 / 180.
local BOB_AMP    = 0.3    -- idle float
local BOB_SPEED  = 1.1
local LABEL_RANGE = 50    -- studs: headers/lock/requirement only appear this close, like an NPC name tag

-- MASTER BRIGHTNESS. Every light in every portal comes from these four numbers -- turn them down here and
-- the whole row dims together. Two PointLights per portal is the ENTIRE lighting budget (props glow by
-- being Neon, not by casting light), because Roblox blows out fast and the bloom was eating the stonework.
-- LOOKS[realm].dim trims an individual realm further -- Candy runs low, its pink throws more light.
-- A locked portal isn't a separate level -- it just runs these at 65% (see `k` in render()).
local LIGHT_A     = 0.31  -- the realm's main colour
local LIGHT_B     = 0.20  -- its second colour, blended in
local LIGHT_PULSE = 0.47  -- what LIGHT_A breathes up to on an OPEN portal

--------------------------------------------------------------------------------
-- the three themes -- each gets TWO lights, so the glow is a blend, not a flat wash
--------------------------------------------------------------------------------
-- STYLE: flat, chunky, cartoony -- the look the purple Space portal had. Everything is SmoothPlastic or
-- Neon; there is deliberately NO Rock, Slate, Cobblestone, DiamondPlate, Sand or Glass anywhere in this
-- file. Depth comes from a darker bevel behind a lighter face, not from a gritty texture.
local FLAT = Enum.Material.SmoothPlastic
local GLOW = Enum.Material.Neon
-- STONE is matte Plastic, not SmoothPlastic: it keeps the surface SMOOTH (no pebbles, no grit, no
-- normal-mapped gravel) while giving it the faint matte tooth of poured concrete instead of the wet
-- shine of plastic. Roblox's actual Concrete material is a gritty photo texture -- that's the thing we
-- are avoiding. Candy and glowing pieces stay on SmoothPlastic/Neon, which is where you want the gloss.
local STONE = Enum.Material.Plastic

local LOOKS = {
	space = {
		emoji = "\xF0\x9F\x9A\x80", title = "SPACE REALM", name = "Space Realm",
		stone   = Color3.fromRGB(96, 66, 168),   stoneMat = STONE, -- dark purple stone
		bevel   = Color3.fromRGB(62, 40, 116),                    -- the shadow side of it
		rune    = Color3.fromRGB(150, 120, 255),
		vortex  = Color3.fromRGB(120, 80, 235),
		lightA  = Color3.fromRGB(90, 150, 255),  -- blue...
		lightB  = Color3.fromRGB(185, 120, 255), -- ...and purple
		spark   = Color3.fromRGB(235, 228, 255),
		plate   = Color3.fromRGB(70, 50, 122),
		sparkSize = 0.5, sparkRate = 36, spin = 1.5,
		dim = 1, -- per-realm brightness trim; Candy runs lower because white light blows out
	},
	dino = {
		emoji = "\xF0\x9F\xA6\x96", title = "DINO REALM", name = "Dino Realm",
		-- warm sandstone: distinctly its OWN brick, not the same pale stone as Candy
		stone   = Color3.fromRGB(186, 166, 128), stoneMat = STONE,
		bevel   = Color3.fromRGB(140, 122, 90),
		rune    = Color3.fromRGB(120, 235, 130), -- small green crystal accents
		vortex  = Color3.fromRGB(70, 205, 100),
		lightA  = Color3.fromRGB(105, 235, 130), -- green energy
		lightB  = Color3.fromRGB(190, 245, 140),
		spark   = Color3.fromRGB(210, 255, 170),
		plate   = Color3.fromRGB(120, 150, 96),
		sparkSize = 1.1, sparkRate = 20, spin = 0.8,
		dim = 1,
	},
	candy = {
		emoji = "\xF0\x9F\x8D\xAD", title = "CANDY REALM", name = "Candy Realm",
		-- DEEPER bubblegum pink. The old near-white pink glared next to Dino's sandstone and Space's
		-- purple; this one is saturated rather than pale, so the frosting and gumdrops on the frame still
		-- pop against it instead of washing into it.
		stone   = Color3.fromRGB(214, 96, 156), stoneMat = STONE,
		bevel   = Color3.fromRGB(166, 62, 116),
		rune    = Color3.fromRGB(255, 214, 236),
		vortex  = Color3.fromRGB(222, 96, 170),
		lightA  = Color3.fromRGB(232, 104, 172), -- deeper pink...
		lightB  = Color3.fromRGB(250, 196, 222), -- ...and a soft rose. Pure white blew the portal out.
		spark   = Color3.fromRGB(255, 226, 196),
		plate   = Color3.fromRGB(190, 96, 142),
		sparkSize = 1.6, sparkRate = 18, spin = 0.55,
		dim = 0.45, -- ~45% of Space/Dino: pink throws far more light than the green or the purple
	},
}

-- (There is deliberately no "locked" palette any more. A locked portal keeps its realm's colours and its
-- swirling middle -- it's just dimmer, with the lock sign up. See render().)

local enterEvent = ReplicatedStorage:WaitForChild("RealmPortalEvent", 30)
if not enterEvent then
	warn("[RealmPortals] RealmPortalEvent missing -- is RealmPortals.server.lua running?")
	return
end

-- HOW MANY OF THEM ARE THERE?
-- The server does a getOrCreate on this name AND default.project.json declares one, and this place is known
-- to carry baked-in duplicates of almost everything else. If ReplicatedStorage ends up holding TWO
-- RemoteEvents called 'RealmPortalEvent', :FireServer on one is simply not heard by a listener connected to
-- the other -- the call succeeds, nothing errors, and the request evaporates. That failure is completely
-- silent from both ends, which is what a client "portal entered" with no matching server line looks like.
do
	local n = 0
	for _, inst in ipairs(ReplicatedStorage:GetChildren()) do
		if inst.Name == "RealmPortalEvent" then n = n + 1 end
	end
	if n > 1 then
		warn(("[RealmPortals] ⚠ %d RemoteEvents named 'RealmPortalEvent' in ReplicatedStorage -- the client may "
			.. "be firing into a different one than the server listens on. Delete the extras in Studio."):format(n))
	else
		print("[RealmPortals] remote OK -- exactly 1 'RealmPortalEvent' in ReplicatedStorage")
	end
end

--------------------------------------------------------------------------------
-- LOCKED-DOOR BUMP SOUND
--------------------------------------------------------------------------------
-- A locked portal is SOLID now (see render()), so walking into one is a bump rather than a walk-through.
-- This is the thud you get for it -- the audio half of "that door is shut", played on the frame you hit it.
-- It REPLACES the old re-pitched 'deny' cue from _G.Sfx: that was the same sample everything else in the
-- game uses, pitched down, and a real refusal deserves its own sound.
--
-- 2D (SoundService) for the same reason the entry cue is: this is YOUR body hitting YOUR locked door, not
-- an event happening out in the world for everyone.
local PORTAL_LOCKED_SOUND_ID = "rbxassetid://90321528664115"
local PORTAL_LOCKED_VOLUME   = 0.85
local portalLockedSound = Instance.new("Sound")
portalLockedSound.Name = "RealmPortalLocked"
portalLockedSound.SoundId = PORTAL_LOCKED_SOUND_ID
portalLockedSound.Volume = PORTAL_LOCKED_VOLUME
portalLockedSound.Parent = game:GetService("SoundService")
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ portalLockedSound }, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				print(string.format("[RealmPortals] locked-bump sound %s loaded OK (length %.2fs)",
					PORTAL_LOCKED_SOUND_ID, portalLockedSound.TimeLength))
			else
				warn(string.format("[RealmPortals] locked-bump sound %s FAILED to load (%s) -- not an audio "
					.. "asset, or not approved for this experience's creator.", PORTAL_LOCKED_SOUND_ID, tostring(status)))
			end
		end)
	end)
end)

--------------------------------------------------------------------------------
-- PORTAL ENTRY SOUND
--------------------------------------------------------------------------------
-- Fired the moment your body touches a portal's vortex, before the server has said yes or no. That is
-- deliberate: the sound is the feedback for WALKING IN, not for being approved -- a locked portal that
-- makes the same noise still tells you that you hit the thing, and the refusal message arrives right
-- after. 2D (SoundService), because this is your own crossing rather than an event out in the world.
--
-- One Sound reused for all three portals. p.enter() already debounces on p.sending for 2.5s, so walking
-- through the vortex repeatedly cannot machine-gun this.
local PORTAL_ENTER_SOUND_ID = "rbxassetid://111559442515692"
local PORTAL_ENTER_VOLUME   = 0.8
local portalEnterSound = Instance.new("Sound")
portalEnterSound.Name = "RealmPortalEnter"
portalEnterSound.SoundId = PORTAL_ENTER_SOUND_ID
portalEnterSound.Volume = PORTAL_ENTER_VOLUME
portalEnterSound.Parent = game:GetService("SoundService")
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ portalEnterSound }, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				print(string.format("[RealmPortals] entry sound %s loaded OK (length %.2fs)",
					PORTAL_ENTER_SOUND_ID, portalEnterSound.TimeLength))
			else
				warn(string.format("[RealmPortals] entry sound %s FAILED to load (%s) -- not an audio asset, "
					.. "or not approved for this experience's creator.", PORTAL_ENTER_SOUND_ID, tostring(status)))
			end
		end)
	end)
end)

--------------------------------------------------------------------------------
-- centre-screen status message
--------------------------------------------------------------------------------
local msgGui = Instance.new("ScreenGui")
msgGui.Name = "RealmPortalMsg"; msgGui.ResetOnSpawn = false; msgGui.IgnoreGuiInset = true
msgGui.DisplayOrder = 60; msgGui.Parent = playerGui

local msgLbl = Instance.new("TextLabel")
msgLbl.AnchorPoint = Vector2.new(0.5, 0.5)
msgLbl.Position = UDim2.new(0.5, 0, 0.42, 0)
msgLbl.Size = UDim2.new(0, 580, 0, 78)
msgLbl.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
msgLbl.BackgroundTransparency = 1
msgLbl.Font = Enum.Font.FredokaOne
msgLbl.TextScaled = true
msgLbl.TextColor3 = Color3.new(1, 1, 1)
msgLbl.Text = ""
msgLbl.Visible = false
msgLbl.Parent = msgGui
Instance.new("UICorner", msgLbl).CornerRadius = UDim.new(0, 16)
local msgStroke = Instance.new("UIStroke", msgLbl); msgStroke.Thickness = 3
local msgPad = Instance.new("UIPadding", msgLbl)
msgPad.PaddingLeft = UDim.new(0, 16); msgPad.PaddingRight = UDim.new(0, 16)
msgPad.PaddingTop  = UDim.new(0, 12); msgPad.PaddingBottom = UDim.new(0, 12)

local msgToken = 0
local function showMsg(text, tint, seconds)
	msgToken += 1
	local mine = msgToken
	msgLbl.Text = text
	msgStroke.Color = tint or Color3.fromRGB(200, 200, 200)
	msgLbl.BackgroundTransparency = 0.15
	msgLbl.Visible = true
	if seconds then
		task.delay(seconds, function()
			if msgToken == mine then
				msgLbl.Visible = false; msgLbl.BackgroundTransparency = 1; msgLbl.Text = ""
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- THE OUTRO -- walking through a portal
--------------------------------------------------------------------------------
-- The counterpart to the black hole's "sucked in" shot, and deliberately its MIRROR IMAGE. That one is a
-- gravity well: your HUD spirals inward, the frame squeezes, the FOV narrows, you are dragged down a drain.
-- A portal is a DOORWAY -- you walk through it under your own steam -- so everything here says forward
-- instead of down:
--
--   * the HUD PEELS OUTWARD past the edges of the screen, not inward. The interface stays behind while you
--     step through it; that single reversal is what makes this read as "crossing" rather than "falling".
--   * an IRIS of portal-light opens from the centre and swallows the frame -- the doorway getting bigger
--     because you are walking into it.
--   * FOV pushes WIDE (stepping forward) where the black hole narrowed.
--   * IT WEARS THE REALM'S OWN COLOURS. `look` is the same table the portal itself is built from, so Space
--     crosses over in blue/purple, Dino in green, Candy in pink. One effect, three transitions.
--
-- SHORTER THAN THE BLACK HOLE ON PURPOSE (3.6s vs 6.2s). The black hole is a one-time discovery and can
-- afford to be a set piece; portals are the everyday route between realms and get used over and over, so
-- this has to stay something you enjoy the fifth time. Must match the task.wait in RealmPortals.server.lua.
local PORTAL_CINEMATIC_SECONDS = 4.2
-- FOUR beats, not three. The shot used to detonate on frame one -- you touched the vortex and the entire
-- interface was already flying off screen, which reads as a glitch before it reads as a transition. INTAKE
-- is the anticipation beat that fixes it: for half a second nothing leaves, the world just dims and the
-- portal light swells and the frame tightens, as though the doorway has noticed you. THEN the HUD goes.
-- Every good transition has a breath before the move; without one the move looks like a mistake.
local P_INTAKE, P_THRESHOLD, P_CROSS, P_CARD = 0.6, 1.0, 1.6, 1.0

-- Set to the running shot's teardown while an outro is on screen, nil otherwise. It lets the server's
-- "error" reply cancel the cinematic immediately rather than waiting out the backstop timer.
local abortOutro = nil
local outroRunning = false
local function playPortalOutro(look)
	if outroRunning then return end
	outroRunning = true
	-- Proof the shot actually started, and which realm's look it got. If the travel sound plays and this
	-- line does NOT appear, the outro was never entered; if it appears and you still see no transition,
	-- the problem is inside the shot rather than in reaching it.
	print("[RealmPortals] OUTRO START -> " .. tostring(look and look.title or "?"))

	local cam = Workspace.CurrentCamera
	local origFov = cam and cam.FieldOfView or 70
	local heldCF = cam and cam.CFrame or CFrame.new()
	local restored, renderConn, guiAddedConn, blur, gui = false, nil, nil, nil, nil
	local hidden = {}
	local shakeMag = 0

	-- ONE teardown. The SUCCESS path never calls it -- we hold on black and the teleport is the cut. This
	-- exists for the failure paths and the backstop (Studio, where TeleportAsync does nothing at all).
	local function restore()
		if restored then return end
		restored = true
		if renderConn then renderConn:Disconnect() end
		if guiAddedConn then guiAddedConn:Disconnect() end
		pcall(function()
			local c = Workspace.CurrentCamera
			if c then
				c.CameraType = Enum.CameraType.Custom
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then c.CameraSubject = hum end
				c.FieldOfView = origFov
			end
		end)
		if blur then pcall(function() blur:Destroy() end) end
		for sg, wasOn in pairs(hidden) do pcall(function() sg.Enabled = wasOn end) end
		pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		if gui then pcall(function() gui:Destroy() end) end
		outroRunning = false
		abortOutro = nil
	end

	-- Published so the "error" reply from the server can end the shot the instant the teleport is known to
	-- have failed, instead of leaving the player staring at a card while a timer runs down.
	abortOutro = restore

	-- THE BACKSTOP -- 2.5s past the end of the shot, not 10.
	-- On a real crossing this never fires: the server teleports at 4.2s and the place swap takes the whole
	-- client with it. It only matters when the teleport DOESN'T happen -- in Studio, where TeleportAsync
	-- always fails, or on a live server that refuses. In that case the old +10 left you sitting on a black
	-- screen with no HUD for FOURTEEN SECONDS, which does not read as a cinematic, it reads as the HUD being
	-- broken. If we are still in this place 2.5s after the card has landed, the crossing did not happen and
	-- the interface should come back promptly.
	task.delay(PORTAL_CINEMATIC_SECONDS + 2.5, restore)

	-- Dying or respawning mid-shot also ends it. The HUD is hidden by .Enabled, which survives respawn, so
	-- without this a death during the crossing would strand the player with no interface at all.
	do
		local conn
		conn = player.CharacterAdded:Connect(function()
			if conn then conn:Disconnect() end
			restore()
		end)
		task.delay(PORTAL_CINEMATIC_SECONDS + 3, function() if conn then conn:Disconnect() end end)
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "RealmPortalOutro"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global; gui.DisplayOrder = 10000
	gui.Parent = playerGui

	local shell = Instance.new("Frame")
	shell.Size = UDim2.new(1, 0, 1, 0); shell.BackgroundTransparency = 1; shell.ZIndex = 2
	shell.Parent = gui

	-- ---- measure the HUD where it actually sits, then let it fall behind ----
	local ghosts = {}
	pcall(function()
		for _, sg in ipairs(playerGui:GetChildren()) do
			if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui and sg ~= msgGui then
				for _, obj in ipairs(sg:GetChildren()) do
					if #ghosts >= 24 then break end
					if obj:IsA("GuiObject") and obj.Visible and obj.AbsoluteSize.X > 24 and obj.AbsoluteSize.Y > 12 then
						local g = Instance.new("Frame")
						g.Position = UDim2.fromOffset(obj.AbsolutePosition.X, obj.AbsolutePosition.Y)
						g.Size = UDim2.fromOffset(obj.AbsoluteSize.X, obj.AbsoluteSize.Y)
						g.BackgroundColor3 = obj.BackgroundColor3
						-- Faint and edgeless -- see the same note in the black hole shot. An outlined, rounded
						-- rectangle sliding off screen is furniture being thrown; a feathered smear of the
						-- colour that used to be there is an interface being left behind.
						g.BackgroundTransparency = math.clamp(obj.BackgroundTransparency, 0.55, 0.82)
						g.BorderSizePixel = 0; g.ZIndex = 8; g.Parent = shell
						local gg = Instance.new("UIGradient")
						gg.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 1),
						})
						gg.Rotation = 90
						gg.Parent = g
						ghosts[#ghosts + 1] = g
					end
				end
			end
		end
	end)

	local function hideOne(child)
		if child == gui or not child:IsA("ScreenGui") then return end
		if hidden[child] == nil then hidden[child] = child.Enabled; child.Enabled = false end
	end
	for _, c in ipairs(playerGui:GetChildren()) do hideOne(c) end
	guiAddedConn = playerGui.ChildAdded:Connect(hideOne)
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)

	-- ---- the iris: portal light opening up to take the whole frame ----
	local iris = Instance.new("Frame")
	iris.AnchorPoint = Vector2.new(0.5, 0.5); iris.Position = UDim2.new(0.5, 0, 0.5, 0)
	iris.Size = UDim2.new(0, 0, 0, 0)
	iris.BackgroundColor3 = look.lightA
	iris.BackgroundTransparency = 0.15; iris.BorderSizePixel = 0; iris.ZIndex = 12; iris.Parent = shell
	Instance.new("UICorner", iris).CornerRadius = UDim.new(1, 0)
	-- NO RIM. A 10px bright ring around a growing circle is the single most "drawn shape" thing this file
	-- could put on screen. The iris now feathers out through its own gradient instead: solid colour in the
	-- middle, gone by the edge, so what expands is a wash of portal light with no boundary rather than a
	-- disc with an outline. The colour still runs lightB -> lightA across it, so it keeps the realm's look.
	local irisGrad = Instance.new("UIGradient")
	irisGrad.Color = ColorSequence.new(look.lightB or look.lightA, look.lightA)
	irisGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.28, 0.15),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.72, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	irisGrad.Rotation = 90; irisGrad.Parent = iris

	-- ---- streaks blowing PAST you (outward = you are moving forward through them) ----
	local function spawnPass()
		local s = Instance.new("Frame")
		local ang = math.rad(math.random(0, 359))
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.new(0.5 + math.cos(ang) * 0.06, 0, 0.5 + math.sin(ang) * 0.06, 0)
		s.Size = UDim2.new(0, 3, 0, 18)
		s.BackgroundColor3 = (math.random() < 0.5) and (look.spark or Color3.new(1, 1, 1)) or look.lightB or look.lightA
		s.BackgroundTransparency = 0.3; s.BorderSizePixel = 0
		s.Rotation = math.deg(ang) + 90
		s.ZIndex = 10; s.Parent = shell
		-- fade to nothing at both ends: a streak of light, not a rounded pill flying past
		local sg = Instance.new("UIGradient")
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sg.Rotation = 90
		sg.Parent = s
		local dur = 0.3 + math.random() * 0.25
		pcall(function()
			TweenService:Create(s, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5 + math.cos(ang) * 1.2, 0, 0.5 + math.sin(ang) * 1.2, 0),
				Size = UDim2.new(0, 2, 0, 150 + math.random() * 90), -- stretches as it flies past
				BackgroundTransparency = 1,
			}):Play()
		end)
		game:GetService("Debris"):AddItem(s, dur + 0.1)
	end

	renderConn = RunService.RenderStepped:Connect(function()
		if restored then return end
		local c = Workspace.CurrentCamera
		if c then c.CameraType = Enum.CameraType.Scriptable; c.CFrame = heldCF end
		if shakeMag > 0 then
			shell.Position = UDim2.new(0, math.random(-8, 8) * shakeMag, 0, math.random(-8, 8) * shakeMag)
		else
			shell.Position = UDim2.new(0, 0, 0, 0)
		end
	end)

	blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Parent = game:GetService("Lighting")

	local ok, err = pcall(function()
		-- ===== BEAT 0: INTAKE (0.6s) -- the doorway notices you =====
		-- Nothing leaves yet. The world dims a touch, the portal's light rises out of the middle of the
		-- screen, and the FOV pulls IN slightly -- a held breath before the step forward. The FOV tightening
		-- here is what makes the widening in the next beats land: without something to push against, a
		-- widening lens just looks like a lens.
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_INTAKE, Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out), { Size = UDim2.new(0, 90, 0, 90) }):Play()
			TweenService:Create(blur, TweenInfo.new(P_INTAKE), { Size = 4 }):Play()
		end)
		local t0 = os.clock()
		while not restored and (os.clock() - t0) < P_INTAKE do
			local a = (os.clock() - t0) / P_INTAKE
			if cam then cam.FieldOfView = origFov - a * 6 end -- the inhale
			task.wait()
		end
		if restored then return end

		-- ===== BEAT 1: THRESHOLD (1.0s) -- the interface falls behind =====
		for i, g in ipairs(ghosts) do
			task.delay((i - 1) * 0.03, function()
				pcall(function()
					-- each panel flies out through the nearest edge, away from centre
					local gx = g.AbsolutePosition.X + g.AbsoluteSize.X * 0.5
					local gy = g.AbsolutePosition.Y + g.AbsoluteSize.Y * 0.5
					local vx = (gx < shell.AbsoluteSize.X * 0.5) and -1 or 1
					local vy = (gy < shell.AbsoluteSize.Y * 0.5) and -1 or 1
					TweenService:Create(g, TweenInfo.new(0.7 + math.random() * 0.3,
						Enum.EasingStyle.Back, Enum.EasingDirection.In), {
						Position = UDim2.fromOffset(gx + vx * 900, gy + vy * 520),
						Rotation = vx * (18 + math.random(0, 26)),
						BackgroundTransparency = 1,
					}):Play()
				end)
			end)
			game:GetService("Debris"):AddItem(g, 2)
		end
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_THRESHOLD, Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out), { Size = UDim2.new(0, 240, 0, 240) }):Play()
			TweenService:Create(blur, TweenInfo.new(P_THRESHOLD), { Size = 10 }):Play()
		end)
		t0 = os.clock()
		while not restored and (os.clock() - t0) < P_THRESHOLD do
			local a = (os.clock() - t0) / P_THRESHOLD
			shakeMag = a * 0.5
			-- picks up exactly where the inhale left off (-6) and swings through to +10, so the release out
			-- of the anticipation beat is one continuous move rather than a snap back to neutral first
			if cam then cam.FieldOfView = origFov - 6 + a * 16 end
			task.wait()
		end
		if restored then return end

		-- ===== BEAT 2: CROSS (1.6s) -- the doorway takes the screen =====
		pcall(function()
			TweenService:Create(iris, TweenInfo.new(P_CROSS * 0.8, Enum.EasingStyle.Quint,
				Enum.EasingDirection.In), { Size = UDim2.new(2.6, 0, 2.6, 0), BackgroundTransparency = 0 }):Play()
			TweenService:Create(blur, TweenInfo.new(P_CROSS), { Size = 22 }):Play()
		end)
		local passClock = 0
		t0 = os.clock()
		while not restored and (os.clock() - t0) < P_CROSS do
			local dt = task.wait()
			local a = (os.clock() - t0) / P_CROSS
			shakeMag = 0.5 + a * 0.7
			if cam then cam.FieldOfView = origFov + 10 + a * 16 end
			passClock += dt
			-- one at a time, half as often: two per 0.02s filled the screen with individually readable
			-- objects instead of a sense of speed
			if passClock > 0.04 then passClock = 0; spawnPass() end
		end
		if restored then return end

		-- ===== BEAT 3: CARD (1.0s) -- the destination, and hold =====
		-- This is the last thing the player sees before the place swaps, and it was the cheapest-looking
		-- moment in the whole shot: flat black with a word on it. Four changes, all of them light rather
		-- than shapes, so it stays in the same visual language as the rest:
		--
		--   GROUND  not pure black. A near-black tinted toward the realm's own colour, so the screen still
		--           belongs to where you are going instead of being an absence of picture.
		--   GLOW    a wide, fully feathered disc of realm light behind the text. It is what stops the card
		--           reading as a loading screen -- there is depth behind the words.
		--   SETTLE  the title arrives slightly oversized and eases down to true size as it fades up. A word
		--           that simply appears is a label; a word that settles was placed there.
		--   LINE    a thin horizontal light, feathered to nothing at both ends, that widens out from under
		--           the title. It gives the eye something completing rather than something waiting.
		shakeMag = 0
		--======================================================================
		-- FULL-BLEED. NO BAND, NO BARS, NO SEAM.
		--======================================================================
		-- This card used to be a black screen with a 420px-tall CAPSULE of realm light lying across the
		-- middle of it: `glow` was Size (1.4, 0, 0, 420) with UICorner(1,0) and its transparency tweened to
		-- 0, so what actually rendered was a solid coloured strip with a hard rounded edge, floating on
		-- plain black above and below. On a phone that strip was most of the screen; on an ultrawide it was
		-- a letterbox. Either way it read as a panel that had failed to load rather than as a shot.
		--
		-- The fix is two layers, BOTH edge-to-edge, and no shape anywhere:
		--   GROUND  the whole viewport, carrying a vertical realm gradient. Every pixel is coloured, so
		--           there is no "rest of the screen" left plain black to have an edge against.
		--   GLOW    also the whole viewport, feathered to FULLY transparent at the top and bottom edges. It
		--           still puts light behind the words -- that was the point of it -- but it now arrives at
		--           the screen edge already at zero, so there is nothing for a seam to form on.
		-- The ScreenGui is IgnoreGuiInset = true (above) and neither layer has a parent frame with an
		-- offset height, so this covers the true viewport on every aspect ratio.
		local black = Instance.new("Frame")
		black.Size = UDim2.fromScale(1, 1)
		black.Position = UDim2.fromScale(0, 0)
		black.AnchorPoint = Vector2.new(0, 0)
		-- 6% of the realm hue over black: enough to feel coloured, nowhere near enough to look lit
		black.BackgroundColor3 = look.lightA:Lerp(Color3.new(0, 0, 0), 0.94)
		black.BackgroundTransparency = 1; black.BorderSizePixel = 0; black.ZIndex = 25; black.Parent = gui
		do
			-- Top and bottom sit a touch darker than the middle, so the screen has a direction to it and the
			-- eye is walked to the title. It is a gradient across the WHOLE height -- not a shape with ends.
			local bg = Instance.new("UIGradient")
			local deep = look.lightA:Lerp(Color3.new(0, 0, 0), 0.975)
			local mid  = look.lightA:Lerp(Color3.new(0, 0, 0), 0.90)
			bg.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, deep),
				ColorSequenceKeypoint.new(0.5, mid),
				ColorSequenceKeypoint.new(1, deep),
			})
			bg.Rotation = 90
			bg.Parent = black
		end

		local glow = Instance.new("Frame")
		glow.AnchorPoint = Vector2.new(0, 0)
		glow.Position = UDim2.fromScale(0, 0)
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = look.lightA
		glow.BackgroundTransparency = 1; glow.BorderSizePixel = 0; glow.ZIndex = 26; glow.Parent = gui
		-- NO UICorner here. The rounded corner is what turned this layer into a visible capsule with an
		-- outline; a full-screen layer that fades to nothing needs no shape at all.
		do
			local gg = Instance.new("UIGradient")
			-- Rotation 90 = top-to-bottom. Fully transparent at both screen edges, brightest across the
			-- middle where the title sits, and every step between is interpolated -- so the light falls off
			-- smoothly all the way to the edge instead of stopping at one.
			gg.Rotation = 90
			gg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.28, 0.94),
				NumberSequenceKeypoint.new(0.5, 0.82),
				NumberSequenceKeypoint.new(0.72, 0.94),
				NumberSequenceKeypoint.new(1, 1),
			})
			gg.Parent = glow
		end

		local card = Instance.new("TextLabel")
		card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.Size = UDim2.new(1.02, 0, 0, 102) -- oversized; settles to 0.9/90 below
		card.BackgroundTransparency = 1
		card.Font = Enum.Font.FredokaOne; card.TextScaled = true
		card.TextColor3 = look.spark or Color3.new(1, 1, 1); card.TextTransparency = 1
		card.Text = look.title or "TRAVELLING"; card.ZIndex = 28; card.Parent = gui
		do local c = Instance.new("UITextSizeConstraint", card); c.MaxTextSize = 58 end
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = look.lightA; cardStroke.Thickness = 3; cardStroke.Transparency = 1

		local sub = Instance.new("TextLabel")
		sub.AnchorPoint = Vector2.new(0.5, 0.5); sub.Position = UDim2.new(0.5, 0, 0.5, 62)
		sub.Size = UDim2.new(0.8, 0, 0, 30); sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamMedium; sub.TextScaled = true
		sub.TextColor3 = look.lightA; sub.TextTransparency = 1
		sub.Text = (look.emoji or "") .. "  entering the " .. (look.name or "realm")
		sub.ZIndex = 28; sub.Parent = gui
		do local c = Instance.new("UITextSizeConstraint", sub); c.MaxTextSize = 20 end

		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5); line.Position = UDim2.new(0.5, 0, 0.5, 38)
		line.Size = UDim2.new(0, 0, 0, 2)
		line.BackgroundColor3 = look.lightA
		line.BackgroundTransparency = 0.25; line.BorderSizePixel = 0; line.ZIndex = 28; line.Parent = gui
		do
			local lg = Instance.new("UIGradient")
			lg.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			lg.Parent = line
		end

		pcall(function()
			TweenService:Create(black, TweenInfo.new(0.4, Enum.EasingStyle.Quad,
				Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
		end)
		task.wait(0.4)
		pcall(function()
			TweenService:Create(glow, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
			TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out), { TextTransparency = 0, Size = UDim2.new(0.9, 0, 0, 90) }):Play()
			TweenService:Create(cardStroke, TweenInfo.new(0.45), { Transparency = 0 }):Play()
			TweenService:Create(line, TweenInfo.new(0.55, Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out), { Size = UDim2.new(0.42, 0, 0, 2) }):Play()
		end)
		task.delay(0.2, function()
			pcall(function()
				TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 0.25 }):Play()
			end)
		end)
		-- HOLD. The teleport lands here.
	end)

	if not ok then
		warn("[RealmPortals] outro cinematic error: " .. tostring(err))
		restore()
	end
end

--------------------------------------------------------------------------------
-- part builders. Everything is cosmetic + client-only: anchored, no collision, no query, no touch.
-- (The force field re-enables its own CanTouch -- it's the one piece that starts a transfer.)
--------------------------------------------------------------------------------
-- Everything is SOLID by default -- you bump into the stonework, you stand on the plaza, you can't walk
-- through a lantern. The only things you may pass through are listed in PASS_THROUGH below: the portal's
-- own interior (that's the door), and small trip-hazard clutter like flowers and sprinkles that would
-- otherwise snag you as you walk.
local PASS_THROUGH = {
	ForceField = true, Depth1 = true, Depth2 = true, Depth3 = true, Depth4 = true, -- walk INTO the portal
	Swirl1 = true, Swirl2 = true, Anchor = true,
	Flower = true, Grass = true, Sprinkle = true, Star = true,                     -- would only trip you up
	Rune = true, Engraving = true, Spoke = true, Medallion = true,                 -- flush with the floor
}

local function newPart(parent, name, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = not PASS_THROUGH[name]
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent, name, d, cf, color, material)
	local p = newPart(parent, name, Vector3.new(d, d, d), cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- a Cylinder's axis runs along its own X, so `len` is along X and the circular face is Y/Z
local function cyl(parent, name, len, dia, cf, color, material)
	local p = newPart(parent, name, Vector3.new(len, dia, dia), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--------------------------------------------------------------------------------
-- themed decoration around each platform
-- Every offset below is kept inside FOOTPRINT_R of the marker -- that is the whole trick to keeping
-- three portals this close together without them visually colliding.
--------------------------------------------------------------------------------
local function buildDinoScenery(f, top, floaters, pulsers)
	local BONE  = Color3.fromRGB(242, 238, 224) -- bright cartoon bone, not weathered ivory
	local ROCK  = Color3.fromRGB(178, 178, 182) -- chunky grey stone
	local FERN  = Color3.fromRGB(96, 190, 78)
	local VINE  = Color3.fromRGB(86, 176, 70)
	local AMBER = Color3.fromRGB(120, 235, 130) -- green crystals now, to match the realm's energy

	for i = -1, 1, 2 do -- ribcage curving up out of the stone, tucked behind the arch
		for r = 1, 3 do
			cyl(f, "Rib", 4.2 - r * 0.45, 0.5,
				top * CFrame.new(i * (3.3 + r * 0.3), 1.3 + r * 0.3, -1.5 - r * 0.7)
					* CFrame.Angles(0, 0, math.rad(90 + (12 + r * 9) * i)),
				BONE, FLAT)
		end
	end

	local skull = ball(f, "Skull", 1.9, top * CFrame.new(-3.6, 0.75, 2.6), BONE, FLAT)
	skull.Size = Vector3.new(1.9, 1.6, 2.5) -- squashed into a snout
	newPart(f, "Jaw", Vector3.new(1.6, 0.34, 2.0), top * CFrame.new(-3.6, 0.05, 2.85), BONE, FLAT)

	for _, s in ipairs({ { 3.4, 2.8, 24 }, { -2.0, -3.3, -40 } }) do -- fossil slabs pressed into the floor
		local slab = newPart(f, "FossilSlab", Vector3.new(2.6, 0.26, 1.9),
			top * CFrame.new(s[1], 0.06, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0),
			Color3.fromRGB(152, 152, 158), STONE)
		for b = -1, 1 do
			ball(f, "Vertebra", 0.55, slab.CFrame * CFrame.new(b * 0.75, 0.14, 0), BONE, FLAT)
		end
	end

	for _, fr in ipairs({ { 4.2, -1.6 }, { -4.1, -2.2 }, { 1.7, 4.0 } }) do -- fern clumps
		for leaf = 0, 4 do
			local a = math.rad(leaf * 72)
			newPart(f, "Fern", Vector3.new(0.28, 2.2, 0.95),
				top * CFrame.new(fr[1] + math.cos(a) * 0.4, 0.95, fr[2] + math.sin(a) * 0.4)
					* CFrame.Angles(math.rad(math.cos(a) * 26), a, math.rad(math.sin(a) * 26)),
				FERN, FLAT)
		end
	end

	for _, b in ipairs({ { -4.4, -0.7, 1.5 }, { 4.4, 2.0, 1.25 }, { 0.5, -4.4, 1.05 } }) do -- chunky boulders
		ball(f, "Boulder", b[3], top * CFrame.new(b[1], b[3] * 0.32, b[2]), ROCK, STONE) -- no cracks: clean shapes
	end

	for i = 1, 3 do -- amber crystals: Neon, but NO PointLight -- they glow without bleaching the scene
		local a = math.rad(30 + i * 118)
		local shard = newPart(f, "AmberCrystal", Vector3.new(0.55, 1.5 + i * 0.2, 0.55),
			top * CFrame.new(math.cos(a) * 4.0, 0.85, math.sin(a) * 4.0) * CFrame.Angles(math.rad(11), a, math.rad(-8)),
			AMBER, Enum.Material.Neon)
		pulsers[#pulsers + 1] = { part = shard, phase = i * 1.7 } -- pulses by transparency, not brightness
	end

	-- (the vines live on the ARCH itself now -- see the frame detail in buildPortal -- so they bob with it
	-- instead of hanging in mid-air while the portal floats)
	for i = 1, 2 do -- creeper roots crawling across the deck toward the frame
		local x = (i == 1) and -2.7 or 2.9
		for seg = 0, 3 do
			newPart(f, "Root", Vector3.new(0.9, 0.14, 0.2),
				top * CFrame.new(x + seg * 0.3 * (i == 1 and 1 or -1), 0.08, -1.4 - seg * 0.85)
					* CFrame.Angles(0, math.rad(seg * 14), 0),
				VINE, FLAT)
		end
	end
end

local function buildSpaceScenery(f, top, floaters, pulsers)
	local ROCK  = Color3.fromRGB(58, 54, 74)
	local STEEL = Color3.fromRGB(150, 155, 170)

	local crystals = {
		{ -4.2, -1.9, 2.8, Color3.fromRGB(90, 160, 255) },
		{ 4.3, -1.3, 2.2, Color3.fromRGB(120, 200, 255) },
		{ -2.5, 3.9, 1.9, Color3.fromRGB(160, 120, 255) },
		{ 3.6, 3.4, 2.4, Color3.fromRGB(110, 140, 255) },
	}
	for i, c in ipairs(crystals) do -- blue crystals on rock bases: Neon only, no PointLight (see the note
		-- on the portal's own lights -- per-prop lights are what washed the detail out)
		local shard = newPart(f, "Crystal", Vector3.new(0.75, c[3], 0.75),
			top * CFrame.new(c[1], c[3] * 0.5, c[2]) * CFrame.Angles(math.rad(8 * i), math.rad(45 * i), math.rad(-6 * i)),
			c[4], Enum.Material.Neon)
		pulsers[#pulsers + 1] = { part = shard, phase = i * 1.4 }
		newPart(f, "CrystalBase", Vector3.new(1.3, 0.5, 1.3), top * CFrame.new(c[1], 0.2, c[2]), ROCK, STONE)
	end

	-- asteroids: they drift and tumble. local_ is their offset from the platform, so they follow it.
	for i, r in ipairs({ { 4.6, 0, 1.25 }, { -4.6, 1.7, 0.95 }, { 0.9, -4.6, 1.1 } }) do
		local localCF = CFrame.new(r[1], 5.6 + i * 1.25, r[2])
		local rock = ball(f, "Asteroid", r[3], top * localCF, ROCK, STONE)
		floaters[#floaters + 1] = { part = rock, local_ = localCF, phase = i * 2.1, amp = 0.55 + i * 0.15, spin = 0.5 + i * 0.25 }
	end

	for i, d in ipairs({ { 3.9, -3.4, 22 }, { -3.7, 2.9, -37 } }) do -- metallic debris half-buried in the deck
		newPart(f, "Debris", Vector3.new(1.9, 0.3, 0.8),
			top * CFrame.new(d[1], 0.14, d[2]) * CFrame.Angles(0, math.rad(d[3]), math.rad(6 * i)),
			STEEL, FLAT)
		cyl(f, "Strut", 1.5, 0.28, top * CFrame.new(d[1] + 0.3, 0.3, d[2] + 0.5) * CFrame.Angles(0, math.rad(d[3]), math.rad(90)),
			STEEL, FLAT)
	end

	for i = 1, 10 do -- stars hanging in the air
		local a = math.rad(i * 36)
		ball(f, "Star", 0.25,
			top * CFrame.new(math.cos(a) * 4.8, 6.5 + (i % 4) * 1.4, math.sin(a) * 4.8),
			Color3.fromRGB(255, 255, 235), Enum.Material.Neon)
	end
end

local function buildCandyScenery(f, top, floaters, pulsers)
	local RED, WHITE = Color3.fromRGB(226, 58, 78), Color3.fromRGB(255, 255, 255)
	local CHOC = Color3.fromRGB(88, 54, 36)

	for _, side in ipairs({ -1, 1 }) do -- candy canes: striped pole + a properly hooked top
		local x = side * 4.4
		for s = 0, 7 do
			cyl(f, "CanePole", 0.95, 0.72, top * CFrame.new(x, 0.5 + s * 0.95, -2.2) * CFrame.Angles(0, 0, math.rad(90)),
				(s % 2 == 0) and RED or WHITE, Enum.Material.SmoothPlastic)
		end
		for h = 1, 4 do
			local a = math.rad(h * 34)
			cyl(f, "CaneHook", 0.95, 0.72,
				top * CFrame.new(x - side * (1 - math.cos(a)) * 1.25, 8.1 + math.sin(a) * 1.15, -2.2)
					* CFrame.Angles(0, 0, math.rad(90) - a * side),
				(h % 2 == 0) and RED or WHITE, Enum.Material.SmoothPlastic)
		end
	end

	for _, lp in ipairs({ { -3.7, 3.5, Color3.fromRGB(255, 120, 190) }, { 4.0, 3.2, Color3.fromRGB(140, 220, 255) } }) do
		cyl(f, "PopStick", 3.0, 0.28, top * CFrame.new(lp[1], 1.5, lp[2]) * CFrame.Angles(0, 0, math.rad(90)),
			WHITE, Enum.Material.SmoothPlastic)
		-- roll the disc 90 degrees so its flat face points at the player, not at the sky
		cyl(f, "PopHead", 0.38, 2.1, top * CFrame.new(lp[1], 3.6, lp[2]) * CFrame.Angles(0, math.rad(90), 0),
			lp[3], Enum.Material.SmoothPlastic) -- plastic, not neon: a lollipop shouldn't glow like a lamp
	end

	for _, g in ipairs({
		{ 2.6, -4.2, 1.2, Color3.fromRGB(120, 230, 140) },
		{ -2.3, -4.4, 1.05, Color3.fromRGB(255, 210, 90) },
		{ 4.5, 0.9, 1.3, Color3.fromRGB(180, 130, 255) },
		{ -4.6, 0.4, 1.1, Color3.fromRGB(255, 140, 120) },
	}) do -- gumdrops: taller than wide, like the real thing
		local d = ball(f, "Gumdrop", g[3], top * CFrame.new(g[1], g[3] * 0.42, g[2]), g[4], Enum.Material.SmoothPlastic)
		d.Size = Vector3.new(g[3], g[3] * 1.25, g[3])
	end

	for _, c in ipairs({ { -1.6, -4.6, 1.35 }, { 3.3, -2.6, 1.1 } }) do -- chocolate rocks
		ball(f, "ChocRock", c[3], top * CFrame.new(c[1], c[3] * 0.34, c[2]), CHOC, STONE)
	end

	for i = 1, 20 do -- frosting piped around the rim
		local a = (i / 20) * math.pi * 2
		ball(f, "Frosting", 1.05,
			top * CFrame.new(math.cos(a) * (PLATFORM_R - 0.3), 0.12, math.sin(a) * (PLATFORM_R - 0.3)),
			WHITE, Enum.Material.SmoothPlastic)
	end

	local SPRINKLE = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 230, 90),
		Color3.fromRGB(150, 255, 150), Color3.fromRGB(220, 140, 255) }
	for i = 1, 18 do -- sprinkles scattered over the deck
		local a, r = math.rad(i * 53), 1.6 + (i % 4) * 0.85
		newPart(f, "Sprinkle", Vector3.new(0.42, 0.12, 0.12),
			top * CFrame.new(math.cos(a) * r, 0.06, math.sin(a) * r) * CFrame.Angles(0, math.rad(i * 37), 0),
			SPRINKLE[(i % #SPRINKLE) + 1], Enum.Material.SmoothPlastic)
	end
end

--------------------------------------------------------------------------------
-- one portal
--------------------------------------------------------------------------------
local portals = {} -- [realmKey] = portal
local markers = {} -- array of { part =, key =, lastCF = }
local state   = {} -- [realmKey] = { unlocked =, built =, reqText = } -- server-pushed, per player

-- Floating label plates: dark rounded card, white outlined text -- readable against the trees.
--
-- CONSTANT ON-SCREEN SIZE. A BillboardGui's Size is a UDim2: the SCALE half is measured in studs (so it
-- shrinks with distance), the OFFSET half is measured in screen pixels (so it does not). Sizing the plate
-- purely in Offset is what holds it at the same apparent size at any range.
--   * MaxDistance = math.huge -> never fades out across the hub.
--   * AlwaysOnTop = true      -> draws over the trees and the arch, so it's always readable.
-- Do NOT add distance-based resizing here. An earlier version scaled the pixel size BY the camera
-- distance, and that is exactly what made the labels balloon as you walked away.
local function makePlate(adornee, w, h, textSize, font)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(w, h) -- pixels only: no Scale component, no distance scaling
	bb.AlwaysOnTop = true
	-- Fade in only when you're near, the way an NPC's name tag does. Across the island the three headers
	-- were just floating clutter; you only need them once you're close enough to actually walk in.
	bb.MaxDistance = LABEL_RANGE
	bb.LightInfluence = 0            -- keeps its own colours instead of soaking up the portal glow
	bb.Adornee = adornee
	bb.Parent = adornee

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	card.Parent = bb
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local edge = Instance.new("UIStroke", card)
	edge.Color = Color3.fromRGB(255, 255, 255); edge.Transparency = 0.65; edge.Thickness = 1.5

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -12, 1, -8)
	lbl.Position = UDim2.new(0, 6, 0, 4)
	lbl.BackgroundTransparency = 1
	lbl.Font = font or Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Parent = card
	local stroke = Instance.new("UIStroke", lbl)
	stroke.Color = Color3.new(0, 0, 0); stroke.Thickness = 2.5
	if textSize then lbl.TextScaled = false; lbl.TextSize = textSize end

	return bb, lbl, card
end

local function buildPortal(key)
	local look = LOOKS[key]
	local p = {
		key = key, look = look,
		ring = {}, frame = {}, runes = {}, swirls = {}, depth = {}, floaters = {}, pulsers = {},
		unlocked = false, sending = false, pulse = nil,
		phase = (key == "space" and 0) or (key == "dino" and 2.1) or 4.2, -- so they don't bob in lockstep
	}

	local root = Instance.new("Folder"); root.Name = "RealmPortal_" .. key; root.Parent = Workspace
	p.root = root
	local static = Instance.new("Folder"); static.Name = "Static"; static.Parent = root -- never bobs
	local moving = Instance.new("Folder"); moving.Name = "Moving"; moving.Parent = root -- bobs
	p.static, p.moving = static, moving

	-- ---- circular platform: base slab, a coloured rim, and a glowing inlay disc ----
	p.platform = cyl(static, "Platform", PLATFORM_H, PLATFORM_R * 2, CFrame.new(), Color3.fromRGB(132, 128, 122), STONE)
	p.rim      = cyl(static, "Rim", PLATFORM_H * 0.5, PLATFORM_R * 2 + 1.0, CFrame.new(), look.plate, STONE)
	p.inlay    = cyl(static, "Inlay", PLATFORM_H * 0.62, PLATFORM_R * 1.0, CFrame.new(), look.lightA, Enum.Material.Neon)
	p.inlay.Transparency = 0.72 -- a hint of colour in the floor, not a floodlight

	-- ---- the arch: chunky beveled blocks around an ellipse ----
	-- Each stone is TWO flat parts: a darker bevel sitting slightly proud behind a lighter face. That
	-- clean shadow line along every edge is the whole "low-poly premium" trick -- no cracks, no grit, no
	-- texture. Big simple blocks, few of them, read from a distance.
	local rx, ry = PORTAL_W / 2, PORTAL_H / 2
	local perim  = math.pi * (3 * (rx + ry) - math.sqrt((3 * rx + ry) * (rx + 3 * ry))) -- Ramanujan
	local segLen = (perim / RING_SEGS) * 1.34 -- overlap slightly: no gaps on the curve
	for i = 1, RING_SEGS do
		local a = (i / RING_SEGS) * math.pi * 2
		local tangent = math.atan2(rx * math.sin(a), ry * math.cos(a)) -- lie along the ellipse, not a circle
		local base = CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 0) * CFrame.Angles(0, 0, -tangent)

		local bevel = newPart(moving, "Bevel", Vector3.new(segLen * 1.06, 2.0, 2.4), CFrame.new(), look.bevel, STONE)
		p.ring[#p.ring + 1] = { part = bevel, localCF = base, bevel = true }

		local face = newPart(moving, "Stone", Vector3.new(segLen, 1.6, 2.0), CFrame.new(), look.stone, STONE)
		p.ring[#p.ring + 1] = { part = face, localCF = base * CFrame.new(0, 0, 0.34), bevel = false }

		if i % RUNE_EVERY == 0 then -- glowing accents set into the stone -- these pulse
			local rune = newPart(moving, "Rune", Vector3.new(0.8, 0.8, 0.14), CFrame.new(), look.rune, GLOW)
			p.ring[#p.ring + 1] = { part = rune, localCF = base * CFrame.new(0, 0, 1.36), bevel = false }
			p.runes[#p.runes + 1] = rune
		end
	end

	-- ---- what makes each FRAME its own object, not a recolour of the same ring ----
	-- These hang off the arch itself (localCF is relative to the portal centre), so they float with it.
	-- A frame prop keeps its own colour/material; render() greys them out when the portal is locked.
	local function frameProp(part, localCF)
		p.frame[#p.frame + 1] = { part = part, localCF = localCF, color = part.Color, material = part.Material }
	end

	if key == "space" then
		-- BIG chunky crystals embedded around the frame -- few, large, unmistakable. Plus sci-fi accent
		-- bars. Nothing dark, nothing metallic: the frame is purple stone and glowing candy-bright gems.
		local GEM = { Color3.fromRGB(120, 170, 255), Color3.fromRGB(175, 125, 255), Color3.fromRGB(140, 220, 255) }
		for i = 1, 6 do
			local a = math.rad(28 + i * 58)
			local gem = newPart(moving, "Crystal", Vector3.new(1.05, 2.3 + (i % 3) * 0.5, 1.05), CFrame.new(),
				GEM[(i % #GEM) + 1], GLOW)
			frameProp(gem, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.15) * CFrame.Angles(0, 0, a + math.pi / 2))
			p.pulsers[#p.pulsers + 1] = { part = gem, phase = i * 1.3 }
		end
		for i = 1, 4 do -- glowing accent bars: the sci-fi read, without a single rivet
			local a = math.rad(i * 90 + 45)
			frameProp(newPart(moving, "Accent", Vector3.new(1.9, 0.3, 0.16), CFrame.new(), look.rune, GLOW),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.38) * CFrame.Angles(0, 0, a + math.pi / 2))
		end
		local cap = newPart(moving, "Keystone", Vector3.new(2.6, 1.5, 2.6), CFrame.new(), look.bevel, STONE)
		frameProp(cap, CFrame.new(0, ry + 0.75, 0.4))
		local capGem = newPart(moving, "KeystoneGem", Vector3.new(1.2, 1.2, 1.2), CFrame.new(), look.rune, GLOW)
		frameProp(capGem, CFrame.new(0, ry + 0.9, 1.5))
		p.pulsers[#p.pulsers + 1] = { part = capGem, phase = 0.4 }

	elseif key == "dino" then
		local BONE = Color3.fromRGB(240, 236, 220)
		local LEAF = Color3.fromRGB(86, 176, 70)
		-- simple bones laid across the frame -- a shaft with two round ends, the classic cartoon bone
		for i = 1, 4 do
			local a = math.rad(35 + i * 78)
			local at = CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.2) * CFrame.Angles(0, 0, a + math.pi / 2)
			frameProp(cyl(moving, "Bone", 2.4, 0.5, CFrame.new(), BONE, FLAT), at * CFrame.Angles(0, 0, math.rad(90)))
			for e = -1, 1, 2 do
				frameProp(ball(moving, "BoneEnd", 0.85, CFrame.new(), BONE, FLAT), at * CFrame.new(0, e * 1.2, 0))
			end
		end
		local skull = newPart(moving, "Skull", Vector3.new(2.4, 1.9, 1.9), CFrame.new(), BONE, FLAT) -- chunky, friendly
		frameProp(skull, CFrame.new(0, ry + 0.7, 0.9))
		frameProp(newPart(moving, "Snout", Vector3.new(1.4, 0.9, 1.2), CFrame.new(), BONE, FLAT),
			CFrame.new(0, ry + 0.35, 1.9))
		for i = 1, 3 do -- small green crystals
			local a = math.rad(200 + i * 50)
			local gem = newPart(moving, "GreenCrystal", Vector3.new(0.6, 1.3, 0.6), CFrame.new(), look.rune, GLOW)
			frameProp(gem, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.25) * CFrame.Angles(0, 0, a + math.pi / 2))
			p.pulsers[#p.pulsers + 1] = { part = gem, phase = i * 1.9 }
		end
		for i = 1, 5 do -- vines spilling over the arch, with a leaf on the end of each
			local x = (i - 3) * 1.6
			for seg = 0, 2 do
				frameProp(newPart(moving, "Vine", Vector3.new(0.26, 1.0, 0.26), CFrame.new(), LEAF, FLAT),
					CFrame.new(x, ry - 0.2 - seg * 0.95, 1.2))
			end
			frameProp(newPart(moving, "Leaf", Vector3.new(0.9, 0.22, 0.55), CFrame.new(), LEAF, FLAT),
				CFrame.new(x + 0.35, ry - 3.0, 1.2) * CFrame.Angles(0, 0, math.rad(22)))
		end

	elseif key == "candy" then
		local WHITE = Color3.fromRGB(255, 255, 255)
		local CANDY = { Color3.fromRGB(255, 105, 135), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 225, 100),
			Color3.fromRGB(150, 245, 160), Color3.fromRGB(200, 150, 255) }

		for i = 0, 9 do -- frosting spread over the top of the arch, with fat rounded drips
			local a = math.rad(18 + i * 16)
			local drip = 0.6 + ((i % 3) * 0.6)
			frameProp(newPart(moving, "Frosting", Vector3.new(1.7, 1.1 + drip, 1.1), CFrame.new(), WHITE, FLAT),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry - drip * 0.35, 1.05))
			frameProp(ball(moving, "Drip", 0.9, CFrame.new(), WHITE, FLAT),
				CFrame.new(math.cos(a) * rx, math.sin(a) * ry - drip - 0.35, 1.05))
		end
		for i = 1, 8 do -- gumdrops pressed into the stones
			local a = math.rad(i * 45 + 20)
			local g = ball(moving, "FrameGumdrop", 1.1, CFrame.new(), CANDY[(i % #CANDY) + 1], FLAT)
			g.Size = Vector3.new(1.1, 1.35, 1.1)
			frameProp(g, CFrame.new(math.cos(a) * rx, math.sin(a) * ry, 1.35))
		end
		for _, side in ipairs({ -1, 1 }) do -- a lollipop built into each shoulder of the frame
			local at = CFrame.new(side * (rx - 0.2), ry * 0.55, 1.3)
			frameProp(cyl(moving, "FramePopStick", 1.6, 0.28, CFrame.new(), WHITE, FLAT),
				at * CFrame.new(0, -1.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
			local head = cyl(moving, "FramePopHead", 0.4, 2.0, CFrame.new(), CANDY[(side == 1) and 1 or 3], FLAT)
			frameProp(head, at * CFrame.Angles(0, math.rad(90), 0))
		end
		for i = 1, 14 do -- sprinkles
			local a = math.rad(i * 26)
			frameProp(newPart(moving, "Sprinkle", Vector3.new(0.45, 0.14, 0.14), CFrame.new(),
				CANDY[(i % #CANDY) + 1], FLAT),
				CFrame.new(math.cos(a) * (rx - 0.35), math.sin(a) * (ry - 0.35), 1.42) * CFrame.Angles(0, 0, math.rad(i * 41)))
		end
	end

	-- ---- the interior: layered discs receding into the distance, so the door has DEPTH ----
	-- Each layer sits further back, smaller and dimmer -- a tunnel, not a flat pane. They counter-rotate.
	for i = 1, 4 do
		local scale = 1 - i * 0.16
		local disc = newPart(moving, "Depth" .. i,
			Vector3.new(0.4, PORTAL_H * scale, PORTAL_W * scale), CFrame.new(),
			look.vortex, Enum.Material.Neon, 0.35 + i * 0.1)
		disc.Shape = Enum.PartType.Cylinder
		p.depth[i] = {
			part = disc,
			localCF = CFrame.new(0, 0, -0.9 * i) * CFrame.Angles(0, math.rad(90), 0),
			speed = (i % 2 == 0) and (0.5 + i * 0.2) or -(0.4 + i * 0.25), -- alternate direction: it churns
			angle = 0,
		}
	end

	-- ---- THE FORCE FIELD: fills the opening. Touching it starts the transfer. ----
	-- A Cylinder's axis is its X, so roll it 90 degrees to aim that axis down the facing. That leaves
	-- Size.Y as the opening's height and Size.Z as its width -- an oval door, not a circle.
	p.vortex = newPart(moving, "ForceField", Vector3.new(0.6, PORTAL_H, PORTAL_W), CFrame.new(),
		look.vortex, Enum.Material.ForceField, 0.2)
	p.vortex.Shape = Enum.PartType.Cylinder
	p.vortex.CanTouch = true -- the one piece in the whole build you can touch
	p.vortexLocal = CFrame.Angles(0, math.rad(90), 0)

	-- TWO lights per portal, and that is the WHOLE lighting budget for it. The previous build also hung a
	-- PointLight on every crystal and lollipop -- six per portal, eighteen across the row -- and Roblox
	-- blows out well before that: the bloom swallowed the stonework, the runes and the cracks. Props now
	-- glow by being Neon, not by casting light, and these two are dialled well down.
	local d = look.dim or 1 -- the realm's own trim, on top of the master levels
	local lightA = Instance.new("PointLight")
	lightA.Color = look.lightA; lightA.Brightness = LIGHT_A * d; lightA.Range = 20; lightA.Parent = p.vortex
	local lightB = Instance.new("PointLight")
	lightB.Color = look.lightB; lightB.Brightness = LIGHT_B * d; lightB.Range = 15; lightB.Parent = p.vortex
	p.lightA, p.lightB = lightA, lightB

	local sparks = Instance.new("ParticleEmitter") -- motes pulled INTO the door (negative speed)
	sparks.Color = ColorSequence.new(look.spark)
	sparks.Size = NumberSequence.new(look.sparkSize)
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Rate = look.sparkRate * 0.6
	sparks.Speed = NumberRange.new(-4, -1)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 0.55 -- was 1: full emission is a bloom machine
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.25), NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Parent = p.vortex
	p.sparks = sparks

	for i = 1, 2 do -- swirl bars across the surface
		local arc = newPart(moving, "Swirl" .. i, Vector3.new(PORTAL_W * (i == 1 and 0.78 or 0.52), 0.5, 0.22),
			CFrame.new(), look.rune, Enum.Material.Neon, 0.4)
		p.swirls[i] = { part = arc, speed = (i == 1 and 1 or -1.7), angle = 0 }
	end

	-- ---- ambient glow rising off the platform ----
	p.anchor = newPart(static, "Anchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), look.lightA, Enum.Material.Neon, 1)
	local ambient = Instance.new("ParticleEmitter") -- a slow drift of motes off the platform, kept subtle
	ambient.Color = ColorSequence.new(look.lightB)
	ambient.Size = NumberSequence.new(0.6)
	ambient.Lifetime = NumberRange.new(1.8, 3.2)
	ambient.Rate = 7
	ambient.Speed = NumberRange.new(1.4, 2.6)
	ambient.SpreadAngle = Vector2.new(30, 30)
	ambient.LightEmission = 0.4
	ambient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	ambient.Parent = p.anchor
	p.ambient = ambient

	-- ---- labels: a lock badge over the portal, and a requirement line beneath ----
	-- The realm-NAME header was removed: the portal already tells you which realm it is through its own
	-- colour, emoji-free art and vortex tint, and three floating name plates in a row was the noisiest
	-- thing on the hub skyline. The lock badge stays -- that is the one bit of state the art cannot show.
	-- Everything hangs off this portal's own anchor so it can never drift onto a neighbour; the Y offset is
	-- pinned to a shared world height in alignHeaders(), not here.
	local lockBB, lockLbl, lockCard = makePlate(p.anchor, 66, 66)
	lockLbl.Text = "\xF0\x9F\x94\x92" -- 🔒
	lockCard.BackgroundTransparency = 0.25
	p.lockBB, p.lockLbl = lockBB, lockLbl

	local reqBB, reqLbl = makePlate(p.anchor, 232, 30, nil, Enum.Font.GothamBold)
	reqLbl.TextColor3 = Color3.fromRGB(255, 214, 140)
	reqBB.StudsOffsetWorldSpace = Vector3.new(0, PLATFORM_H - 1.8, 0) -- beneath the portal
	p.reqBB, p.reqLbl = reqBB, reqLbl

	-- ---- touch -> INTENT ONLY. The server owns the gate and the teleport. ----
	function p.enter()
		if p.sending then return end
		p.sending = true
		-- TWO DEBOUNCES, because the two cases are no longer the same shape. An OPEN portal you pass through
		-- in a fraction of a second, so 2.5s is plenty. A LOCKED one is a wall you can stand against, and
		-- Touched keeps firing for as long as you lean on it -- at 2.5s that is the thud and the centre-screen
		-- refusal replayed every two and a half seconds at a kid who has already got the message.
		task.delay(p.unlocked and 2.5 or 6, function() p.sending = false end) -- local; the server has its own

		-- A LOCKED PORTAL DOES NOTHING BUT SAY NO.
		-- The travel cue and the outro ARE the crossing. Running either one at a portal that is about to
		-- refuse you is a promise it cannot keep: you get the whoosh of a 7.5s journey and then you are still
		-- standing on the hub, which reads as a broken portal rather than a locked one. Walking into a gate
		-- you have not earned should cost you nothing and tell you why.
		--
		-- The intent still goes to the server -- that is what produces the 🔒 "not unlocked yet" message, and
		-- it also makes the server re-read the chain, so a realm you finished seconds ago on another place
		-- can correct a stale cache instead of stranding you. p.unlocked is only the client's cached view;
		-- the server remains the authority, and the two disagreeing is handled either way:
		--   * client thinks LOCKED, server says open -> the "traveling" reply starts the shot anyway
		--   * client thinks OPEN, server says locked -> the "locked" reply aborts the shot mid-run
		if not p.unlocked then
			pcall(function() enterEvent:FireServer(key) end)

			-- THE BUMP. You did not walk through anything -- you walked INTO something -- so the cue is a
			-- thud on contact, not a chime. :Play() restarts a sound that is already going, which is right
			-- here: every fresh bump should sound like a fresh bump.
			pcall(function() portalLockedSound:Play() end)

			print("[RealmPortals] " .. tostring(key) .. " portal is LOCKED for this player -- deny cue, no outro")
			return
		end

		-- ONCE, AND THEN LEFT ALONE. The 2.5s debounce is NOT enough on its own: this cue is 7.5s long, so
		-- standing in the vortex re-entered every 2.5s and restarted a clip that had 5 seconds left to run.
		-- The log showed it plainly -- three "travel sound played" lines inside six seconds, and the sound
		-- never got past its own opening.
		--
		-- :Play() on a Sound that is already playing RESTARTS it, so a retrigger does not layer the cue, it
		-- truncates it. If it is already running, leave it running: a cue mid-play is already doing its job.
		pcall(function()
			if portalEnterSound.IsPlaying then return end
			portalEnterSound:Play()
			print(string.format("[RealmPortals] %s portal entered -> travel sound started (loaded=%s vol=%.2f)",
				tostring(key), tostring(portalEnterSound.IsLoaded), portalEnterSound.Volume))
		end)
		-- NOT a bare pcall any more. This used to swallow its own failure: if the remote were nil, detached or
		-- the wrong instance, FireServer would throw (or quietly go nowhere) and we would carry on as if the
		-- server had been told. Say what happened, so a missing server-side receipt means something specific.
		local sent, sendErr = pcall(function() enterEvent:FireServer(key) end)
		print(("[RealmPortals] intent sent for %s -> %s (remote=%s, parent=%s)"):format(
			tostring(key), sent and "ok" or ("FAILED: " .. tostring(sendErr)),
			tostring(enterEvent), tostring(enterEvent and enterEvent.Parent)))

		-- START THE SHOT HERE, NOT WHEN THE SERVER ANSWERS.
		-- The outro used to run only from the "traveling" reply, which made a purely local, purely visual
		-- effect depend on a round trip: fire an intent, wait for the server to validate the chain gate and
		-- reply, and only then dim the screen. Anything that delays or loses that reply -- a slow server, a
		-- gate that answers something else, a remote that never lands -- and the sound plays over ordinary
		-- gameplay with no transition at all. That is exactly the "sound but no HUD" you were seeing.
		--
		-- The client already knows whether this portal is open (p.unlocked, pushed by the server's state
		-- message and used to draw the lock badge), so it can start the shot on the frame you touch the
		-- vortex. The server stays the authority on the actual teleport -- it can still refuse, and the
		-- "locked"/"soon"/"error" replies below abort the shot -- but the picture no longer waits on it.
		--
		-- No lock test here: the locked case returned above, so reaching this line already means open.
		task.spawn(function() playPortalOutro(LOOKS[key]) end)
	end
	p.vortex.Touched:Connect(function(hit)
		local char = player.Character
		if not (char and hit and hit:IsDescendantOf(char)) then return end -- only our own body
		p.enter()
	end)

	portals[key] = p
	return p
end

--------------------------------------------------------------------------------
-- seating a portal on ITS OWN marker (positions are yours; we never move them)
--------------------------------------------------------------------------------
local function seat(p, marker, rot)
	-- the portal stands on the ground the brick sits on: the BOTTOM of the marker
	local platBaseY = marker.Position.Y - marker.Size.Y * 0.5
	local pos       = marker.Position
	local centreY   = platBaseY + PLATFORM_H + PORTAL_H / 2

	p.baseCF    = CFrame.new(Vector3.new(pos.X, centreY, pos.Z)) * rot -- portal centre
	p.platBaseY = platBaseY
	p.topWorldY = platBaseY + PLATFORM_H + PORTAL_H -- top of the arch: used to align the headers

	local platCF = CFrame.new(pos.X, platBaseY + PLATFORM_H * 0.5, pos.Z) * rot
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie on their X; stand them up
	p.platform.CFrame = platCF * upright
	p.rim.CFrame      = platCF * CFrame.new(0, -0.28, 0) * upright
	p.inlay.CFrame    = platCF * CFrame.new(0, PLATFORM_H * 0.45, 0) * upright
	p.anchor.CFrame   = CFrame.new(pos.X, platBaseY, pos.Z)

	local top = platCF * CFrame.new(0, PLATFORM_H * 0.5, 0) -- the walkable surface

	if not p.sceneryBuilt then
		p.sceneryBuilt = true
		if p.key == "dino"  then buildDinoScenery(p.static, top, p.floaters, p.pulsers) end
		if p.key == "space" then buildSpaceScenery(p.static, top, p.floaters, p.pulsers) end
		if p.key == "candy" then buildCandyScenery(p.static, top, p.floaters, p.pulsers) end
	elseif p.topCF then
		-- reseated (the island moved): carry the scenery across by the same delta rather than rebuild it
		local delta = top * p.topCF:Inverse()
		for _, d in ipairs(p.static:GetChildren()) do
			if d:IsA("BasePart") and d ~= p.platform and d ~= p.rim and d ~= p.inlay and d ~= p.anchor then
				d.CFrame = delta * d.CFrame
			end
		end
	end
	p.topCF = top
end

-- The moving half, re-placed each frame with the idle bob folded in.
local function place(p, bob)
	local face = p.baseCF * CFrame.new(0, bob, 0)
	p.face = face
	for _, e in ipairs(p.ring) do
		e.part.CFrame = face * e.localCF
	end
	for _, e in ipairs(p.frame) do -- the realm-specific frame detail rides with the arch
		e.part.CFrame = face * e.localCF
	end
	for _, d in ipairs(p.depth) do
		d.part.CFrame = face * CFrame.Angles(0, 0, d.angle) * d.localCF
	end
	p.vortex.CFrame = face * p.vortexLocal
	for _, s in ipairs(p.swirls) do
		s.part.CFrame = face * CFrame.Angles(0, 0, s.angle) * CFrame.new(0, 0, -0.4)
	end
end

-- ONE header height for the whole row: pin every name plate to the tallest portal's top, so the three
-- read as a level row even if the bricks aren't at identical heights.
local function alignHeaders()
	local top = -math.huge
	for _, p in pairs(portals) do
		if p.topWorldY then top = math.max(top, p.topWorldY) end
	end
	if top == -math.huge then return end

	-- One shared world height for every lock badge -> the row reads dead level, whatever height the
	-- bricks happen to sit at.
	for _, p in pairs(portals) do
		if p.anchor then
			local anchorY = p.anchor.Position.Y
			-- 3.4 was the name header's height; with the header gone the badge takes its place rather than
			-- hanging at 7.2 with empty air beneath it.
			p.lockBB.StudsOffsetWorldSpace = Vector3.new(0, top + 3.4 - anchorY, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- LAYOUT: each portal on its own marker. Positions never change; we only follow them.
--------------------------------------------------------------------------------
local function relayout()
	if #markers == 0 then return end

	-- one shared rotation for the row (from the first marker + the yaw fix), so the three are parallel
	local m1 = markers[1].part
	local rot = (m1.CFrame - m1.CFrame.Position) * CFrame.Angles(0, math.rad(PORTAL_YAW), 0)

	for _, m in ipairs(markers) do
		local p = portals[m.key] or buildPortal(m.key)
		seat(p, m.part, rot)
		place(p, 0)
	end
	alignHeaders()
end

--------------------------------------------------------------------------------
-- lock state (server-pushed, per player)
--------------------------------------------------------------------------------
local function render(p)
	local st, look = state[p.key] or {}, p.look
	local soon = (st.built == false)                  -- Candy: the place isn't built yet
	local open = (st.unlocked == true) and not soon
	p.unlocked = open

	-- EVERY PORTAL IS ALWAYS A PORTAL. It keeps its realm colours, its themed stone and frame, and the
	-- swirling stuff in the middle you walk through -- open, locked or coming-soon alike. Locked used to
	-- strip all that out and leave a dead grey ring, which is what drained the colour out of Dino and left
	-- nothing in its middle. Now "locked" only means: the sign is up, and it's a shade dimmer. The SERVER
	-- is what actually refuses to travel you -- the look never lies about which realm this is.
	for _, e in ipairs(p.ring) do
		e.part.Color    = e.bevel and look.bevel or look.stone
		e.part.Material = look.stoneMat
	end
	for _, e in ipairs(p.frame) do -- bones, crystals, frosting: always their own colours
		e.part.Color    = e.color
		e.part.Material = e.material
	end
	for _, rune in ipairs(p.runes) do
		rune.Color = look.rune
		rune.Material = GLOW
	end
	for _, s in ipairs(p.swirls) do s.part.Transparency = 0.4 end
	for i, d in ipairs(p.depth) do -- the tunnel of depth behind the door
		d.part.Color = look.vortex
		d.part.Transparency = 0.35 + i * 0.1
	end

	p.inlay.Color = look.lightA

	-- k: not yet yours -> still lit, still swirling, just quieter than a door you can walk through.
	-- d: the realm's own brightness trim (Candy 0.7 -- its white light blows out at the shared level).
	-- ===== A LOCKED PORTAL IS SOLID =====
	-- The lock badge said "not yours yet" and then the door let you stroll straight through it into a realm
	-- you had not earned, where the SERVER refused the teleport. Two different answers to the same question,
	-- and the one your body got was "yes".
	--
	-- So the force field carries its own refusal: CanCollide while locked, walk-through once earned. Nothing
	-- is added to the build to do it -- this is the same ForceField part that has always filled the opening,
	-- and the four depth discs behind it, which together give the plug a few studs of thickness so a player
	-- arriving fast cannot tunnel past a 0.6-stud pane. CanTouch stays on either way, so the bump still
	-- fires Touched and you still get the thud and the reason.
	--
	-- Client-side collision is the right scope, not a hole in the gate: these portals are built per player
	-- by this LocalScript, the client owns its own character's physics, and the SERVER still owns the actual
	-- teleport. Someone who defeats their own barrier arrives at a gate that says no, exactly as before.
	p.vortex.CanCollide = not open
	for _, dd in ipairs(p.depth) do dd.part.CanCollide = not open end

	local k = open and 1 or 0.65
	local d = look.dim or 1
	p.vortex.Color = look.vortex
	p.vortex.Transparency = open and 0.28 or 0.4
	p.lightA.Brightness = LIGHT_A * k * d; p.lightA.Color = look.lightA
	p.lightB.Brightness = LIGHT_B * k * d; p.lightB.Color = look.lightB
	p.sparks.Color = ColorSequence.new(look.spark); p.sparks.Rate = look.sparkRate * 0.6 * k
	p.ambient.Rate = 7 * k * d

	if open then
		p.lockBB.Enabled = false -- no lock badge...
		p.reqBB.Enabled  = false -- ...and the requirement line goes once it's earned
		if not p.pulse then -- an open door breathes, gently -- and the breath is trimmed per realm too
			p.pulse = TweenService:Create(p.lightA,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Brightness = LIGHT_PULSE * d })
			p.pulse:Play()
		end
	else
		-- LOCKED (and "coming soon" Candy): the same 🔒 badge overhead on both, no strapline. The server
		-- sends the centre-screen "not unlocked" message if you actually walk in.
		if p.pulse then p.pulse:Cancel(); p.pulse = nil end
		p.lockBB.Enabled = true
		p.reqBB.Enabled  = false
		p.lockLbl.Text = "\xF0\x9F\x94\x92" -- 🔒
	end
end

--------------------------------------------------------------------------------
-- per-frame: follow the markers, bob, spin, pulse
--------------------------------------------------------------------------------
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt

	-- Did a marker move? PlayerStats repositions Island 1 shortly after we build, and the markers ride
	-- with it. Re-derive from the markers rather than trusting a one-time placement.
	local dirty = false
	for _, m in ipairs(markers) do
		if m.part.Parent and m.part.CFrame ~= m.lastCF then
			m.lastCF = m.part.CFrame
			dirty = true
		end
	end
	if dirty then relayout() end

	for _, p in pairs(portals) do
		if p.baseCF then
			-- Every portal churns, locked or not -- a portal you can't use yet is still a portal. An open
			-- one just turns a little faster, so it reads as the livelier of the two.
			local rate = p.unlocked and 1 or 0.6
			for _, s in ipairs(p.swirls) do s.angle += dt * p.look.spin * s.speed * rate end
			for _, d in ipairs(p.depth) do d.angle += dt * d.speed * 0.5 * rate end

			place(p, math.sin(t * BOB_SPEED + p.phase) * BOB_AMP) -- the idle float

			for _, rune in ipairs(p.runes) do -- runes breathe, slightly out of phase with the bob
				rune.Transparency = p.unlocked and (0.15 + 0.25 * (0.5 + 0.5 * math.sin(t * 2.2 + p.phase))) or 0.6
			end

			for _, pl in ipairs(p.pulsers) do -- crystals breathing: transparency, not light brightness
				pl.part.Transparency = 0.05 + 0.28 * (0.5 + 0.5 * math.sin(t * 1.6 + pl.phase))
			end

			for _, fl in ipairs(p.floaters) do -- Space Realm's asteroids
				fl.part.CFrame = p.topCF * fl.local_
					* CFrame.new(0, math.sin(t * 0.7 + fl.phase) * fl.amp, 0)
					* CFrame.Angles(t * fl.spin * 0.35, t * fl.spin * 0.5, 0)
			end
		end
	end

end)

--------------------------------------------------------------------------------
-- find the marker blocks (they can stream in late -- watch forever, never a one-shot sweep)
--------------------------------------------------------------------------------
local function adopt(part, key)
	for _, m in ipairs(markers) do
		if m.part == part then return end -- already ours
	end

	-- THE MARKER: invisible and inert. It only says where this portal goes and which way it faces.
	part.Transparency = 1
	part.CanCollide   = false
	part.CanTouch     = false -- the force field is what starts a transfer
	part.CastShadow   = false

	-- The big realm name floating INSIDE the portal is not ours -- it's the stale duplicate script,
	-- which adorns its sign straight onto the marker brick. Ours all hang off p.anchor instead. Strip
	-- anything else that tries to label this brick, and keep stripping it, so the only text you see is
	-- the one header above the portal. (Deleting that old script is still the real fix.)
	local function scrubForeignLabels()
		for _, c in ipairs(part:GetChildren()) do
			if c:IsA("BillboardGui") or c:IsA("SurfaceGui") then c:Destroy() end
		end
	end
	scrubForeignLabels()
	part.ChildAdded:Connect(function(c)
		if c:IsA("BillboardGui") or c:IsA("SurfaceGui") then c:Destroy() end
	end)

	markers[#markers + 1] = { part = part, key = key, lastCF = part.CFrame }
	relayout()
	if portals[key] then render(portals[key]) end
	print("[RealmPortals] built the " .. LOOKS[key].title .. " portal on its marker")
end

local function consider(inst)
	if not (inst:IsA("BasePart") and inst.Name == "Portal") then return end
	local function try()
		local key = inst:GetAttribute("Realm")
		if type(key) == "string" and LOOKS[key] then adopt(inst, key) end
	end
	try() -- the attribute may already be there...
	inst:GetAttributeChangedSignal("Realm"):Connect(try) -- ...or the server writes it a moment later
end

for _, d in ipairs(Workspace:GetDescendants()) do consider(d) end
Workspace.DescendantAdded:Connect(consider)

--------------------------------------------------------------------------------
-- what the server tells us
--------------------------------------------------------------------------------
enterEvent.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "state" then -- a: { [realmKey] = { unlocked, built, reqText } }
		if type(a) ~= "table" then return end
		for key, st in pairs(a) do state[key] = st end
		for _, p in pairs(portals) do render(p) end -- lights up the moment the server says it's earned
		return
	end

	if kind ~= "status" then return end
	local key, status, reqText = a, b, c
	local look = LOOKS[key]
	if not look then return end

	if status == "traveling" then
		-- The outro REPLACES the old centre-screen text box: it hides the whole HUD anyway, so the message
		-- would be covered a frame later, and the realm's title card at the end says the same thing better.
		task.spawn(function() playPortalOutro(look) end)
	elseif status == "locked" then
		-- The client thought this portal was open and may already have started the shot. The server is the
		-- authority and it says no, so take the shot down before showing the refusal.
		if abortOutro then pcall(abortOutro) end
		showMsg("\xF0\x9F\x94\x92  You haven't unlocked the " .. look.name .. " yet!",
			Color3.fromRGB(255, 190, 90), 3.5)
	elseif status == "soon" then
		if abortOutro then pcall(abortOutro) end
		showMsg("\xF0\x9F\x9A\xA7  " .. look.name .. " \xE2\x80\x94 Coming soon!", look.lightA, 3)
	elseif status == "error" then
		-- The teleport failed, so the shot is now a lie -- tear it down at once and give the HUD back rather
		-- than holding a "entering the Space Realm" card over a crossing that is not going to happen.
		if abortOutro then pcall(abortOutro) end
		showMsg("Couldn't travel right now, try again", Color3.fromRGB(255, 120, 120), 3)
	end
end)

print("[RealmPortals] client ready -- hub build, watching for Portal marker blocks")
