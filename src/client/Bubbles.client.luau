--!nonstrict
-- ============================================================================
-- BUBBLE KIT  (StarterPlayerScripts)
--
-- BOTH kinds of floating pickup that hang in the air BETWEEN islands in
-- Fart to Float, cut free of that game so any realm can drop them in:
--
--   GAS  -- green 20-stud ball, PULSES, "💨 GAS!"    -> refuels you
--   COIN -- gold/cyan/pink 24-stud ball, "🪙 +BONUS" -> coins, with a STREAK
--
-- They are separate systems in the original (the coin one is still called
-- "ring" in the source -- it used to be a flat ring, and the name stuck after
-- it became a sphere), but they SHARE the drift function, which is why they
-- move identically. That sharing is preserved here rather than duplicated.
--
-- Lifted verbatim from:
--   src/client/WorldClient.client.lua   -- look, pulse, drift, placement
--   src/client/CoreClient.client.lua    -- collection radius, rewards, respawn
-- Every tuning number below is the SHIPPING number. Comments marked (orig)
-- are copied from the source so the reasoning survives the move.
--
-- WHY CLIENT-SIDE: bubbles are anchored, non-collidable, and moved by code
-- only -- they never touch physics or the character. Each player collects
-- their own, so two players don't race for the same bubble and nobody sees a
-- bubble vanish from under them. There is nothing here worth server auth
-- except the reward, which goes through each type's onPop -> your RemoteEvent.
--
-- PORTED INTO DINOSAUR REALM. This REPLACED the gas-only GasBubbleKit that was
-- installed first (src/client/GasBubbles.client.luau, now deleted) -- same gas
-- system, same drift, plus coin bubbles. Do not re-add the old file: both scan
-- the same gaps and you would get two overlapping sets of green balls.
--
-- Three things changed from the kit as shipped, each noted again at the code:
--   1. ANCHORS come from ReplicatedStorage.DinosaurRealm.IslandOrder.SLOT_POS,
--      not from BubbleAnchor attributes. This realm already has the tower ladder
--      in a shared module -- tagging 13 parts by hand would be a second copy of
--      it, and the attribute scan cannot see islands that have not streamed in.
--   2. GAS.onPop fires GasBubbleEvent. The grant HAS to be server-side here;
--      see GasBubble.server.luau (BurnFuelEvent only lets fuel burn DOWN).
--   3. COIN.BASE_BONUS SCALES WITH THE CURRENT ISLAND GAP instead of being a
--      flat 15 -- the same "pay a percentage, never a flat amount" rule the
--      README states for gas, applied to coins. See COIN.baseBonus below.
-- The kit's own anchor scan is kept as a fallback and still works.
-- ============================================================================

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local Debris        = game:GetService("Debris")
local RS            = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ============================================================================
-- SHARED CONFIG -- anchors, drift, and the gap geometry both types use
-- ============================================================================
local SHARED = {
	-- ---- WIRING ---------------------------------------------------------
	-- Number attribute on one part per island, holding that island's index.
	-- An attribute beats a name match: it survives renaming, moving and
	-- reparenting, which the original's "^Island_(%d+)_" pattern does not.
	ANCHOR_ATTRIBUTE = "BubbleAnchor",
	-- Fallback if you'd rather not tag anything: looks for children named
	-- Island1, Island2... inside this folder (nil = attributes only).
	FALLBACK_FOLDER  = nil,
	FALLBACK_PREFIX  = "Island",

	-- ---- GAP GEOMETRY (orig WorldClient:368) ----------------------------
	GAP_BOTTOM_PAD   = 120,  -- studs above the LOWER island -- clears its airspace
	GAP_TOP_PAD      = 200,  -- studs below the UPPER island -- clears its underside

	-- ---- DRIFT / MOVEMENT (orig WorldClient:26 -- shared by BOTH types) --
	DRIFT_SPEED      = 12,   -- (orig) studs/sec: ~2.4x the old 5 -- a real chase, but still catchable by a determined flyer
	DRIFT_HR         = 180,  -- (orig) horizontal half-extent  -- ~4x bigger wander zone (was 45)
	DRIFT_VR         = 280,  -- (orig) vertical half-extent    -- ~4x bigger wander zone (was 70)
	REAIM_MIN        = 0.35, -- (orig) new heading every ~0.35-1.3s (was 2-4.5s)
	REAIM_MAX        = 1.30,
	TURN_INERTIA     = 0.25, -- (orig) new random heading dominates -> abrupt direction changes (not smooth)
	VERTICAL_BIAS    = 0.7,  -- Y component of a random heading is damped -> wanders wide, not up/down

	-- ---- FAR SLEEP -------------------------------------------------------
	-- NOT IN THE KIT. Added because the bubble count here is 6+6 per gap across 12 gaps
	-- = 144, three times the kit's 4-per-gap, and every one of them runs its own
	-- per-frame coroutine writing a CFrame. At 60fps that is ~8,600 writes/second for
	-- parts that are, for all but one gap, thousands of studs away and not on screen.
	--
	-- Beyond FAR_DISTANCE a bubble ticks at FAR_INTERVAL instead of per-frame. It still
	-- drifts -- the maths is dt-based, so it covers the same ground, just in coarser
	-- steps -- and it returns to per-frame the moment the player is near enough to see
	-- or catch it. The kit's own comment about why drift is per-frame ("a chunky update
	-- would let a fast player pass through a bubble between steps") is exactly right and
	-- is why this is distance-gated rather than just made slower everywhere.
	--
	-- FAR_DISTANCE is comfortably past the widest gap's worth of visible airspace. Set
	-- it to math.huge to get the kit's stock behaviour back.
	FAR_DISTANCE     = 1500, -- studs from the player
	FAR_INTERVAL     = 0.25, -- seconds between updates out there

	DEBUG            = true, -- one print per pop, like the original [BUBBLE] log
}

-- ============================================================================
-- GAS BUBBLE  (orig WorldClient:113/126/139 + CoreClient:3085)
-- ============================================================================
local GAS = {
	ID             = "GAS",
	ENABLED        = true,

	-- look -- FATTER THAN THE KIT (was 20 / 13 / 17). The pulse range is scaled by the
	-- same 1.5x rather than re-picked, so it still breathes across the same proportion of
	-- its own size -- a bigger ball with the kit's 13-17 pulse would look like it was
	-- deflating, not breathing.
	SIZE           = 30,
	COLOR          = Color3.fromRGB(0, 255, 100),
	TRANSPARENCY   = 0.4,
	PULSE          = true,   -- GAS pulses; COIN does not. This is the fastest way to tell them apart mid-flight
	PULSE_MIN      = 20,
	PULSE_MAX      = 26,
	PULSE_TIME     = 1,
	LABEL_TEXT     = "\240\159\146\168 GAS!", -- 💨 GAS!
	LABEL_COLOR    = Color3.fromRGB(0, 255, 100), -- label matches the ball
	LABEL_SIZE     = 16,
	LABEL_OFFSET_Y = 12,
	LABEL_WIDTH    = 80,

	-- placement -- SIX PER GAP, not the kit's two (was {0.35, 0.65}).
	-- The t-values are INTERLEAVED with COIN's rather than shared: at the same heights the
	-- two types would sit in matched pairs up the gap and read as one row of alternating
	-- colours. Offset, they read as a scattered field, which is the point of having more.
	-- The placer spaces them evenly around the circle (2*pi / #T_POSITIONS), so six here
	-- means 60 degrees apart -- no two adjacent heights on the same side.
	T_POSITIONS    = {0.10, 0.26, 0.42, 0.58, 0.74, 0.90},
	SPREAD_MIN     = 60,  -- (orig) min studs off the centerline (was a ~+/-30 jitter)
	SPREAD_MAX     = 160, -- widened from 110: more bubbles need more room, or six of them
	                      -- in one gap form a tight tube you fly straight through

	-- collection (orig CoreClient:3089)
	COLLECT_RADIUS = 26,  -- studs. Was 20 for a 20-wide ball -- i.e. 10 studs past the
	                      -- surface. Held at ~11 past the surface of the 30-wide ball, so
	                      -- the pickup is no easier than shipped; it just is not now
	                      -- possible to overlap the ball visually without collecting it.
	RESPAWN        = 45,  -- (orig) re-spawns after 45s so the pickup stays available
	FLOAT_TEXT     = "+\240\159\146\168 GAS BOOST!",
	FLOAT_COLOR    = Color3.fromRGB(0, 255, 100),

	-- pop (orig WorldClient:139 -- the full expand + sparkle burst)
	POP_STYLE      = "burst",
	POP_SIZE       = 45,  -- 1.5x with SIZE: the burst is "expand to 1.5x then fade", and
	                      -- leaving it at 30 against a 30-wide ball would be no expansion
	POP_TIME       = 0.22,
	POP_PARTICLES  = 26,
	SOUND_ID       = "rbxassetid://9114402399", -- (orig) PLACEHOLDER id -- swap to your preferred bubble-pop sfx
	SOUND_VOLUME   = 0.5,
}

-- ---------------------------------------------------------------------------
-- GAS.onPop -- THE INTEGRATION POINT for gas bubbles.
--
-- The original grants +2 on a 0-100 gas meter. That is not a flat +2, it is
-- 2% OF THE TANK, and deliberately so (orig comment):
--
--   "at the base Tiny Gut (100 max power) 1 meter point IS 1 fart power -- this
--    grants exactly +2 fart power there, and stays 2% of the tank on bigger guts
--    so a bubble does not become worthless the moment you upgrade. For a flat +2
--    power at EVERY tier instead, this would have to be (2 / stomachMax) * 100 --
--    which pays 0.06 of a meter point on an Iron Gut, i.e. nothing."
--
-- Keep that shape when you port it: pay a PERCENTAGE of the resource, never a
-- flat amount, or the pickup dies the moment your realm's numbers grow.
--
-- Return a string to override the floating text, or nil for FLOAT_TEXT.
-- ---------------------------------------------------------------------------
-- THIS IS THE KIT'S OPTION (A), THE FART-METER ONE, ROUTED THROUGH THE SERVER.
--
-- The kit's (A) calls a local `_G.addGas(2)`. That does not work here and would be a
-- quiet bug rather than an obvious one. BottomHUD's meter is client-side while it
-- drains, and it reports what is left through BurnFuelEvent, which the server CLAMPS
-- so fuel only ever burns DOWN -- correctly, or a client could just declare a full
-- tank. So a purely local +2% would climb the on-screen meter while the server's
-- CurrentPower stayed put, and the food stand reads the server's: it would sell the
-- player food they have no room for, take the coins, and the client would clamp the
-- power straight back off. The player pays for nothing.
--
-- So the grant goes to the server, which owns the number, and comes back as RegenEvent
-- -- which BottomHUD already adopts whenever CurrentPower RISES. The floating text
-- fires immediately, so the pickup still reads as instant while that round-trips.
--
-- The AMOUNT lives on the server too (2% of the tank, never a flat +2 -- see the note
-- there). Nothing here should decide it: a client that picks its own reward is just a
-- client that picks 100%.
local GasBubbleEvent = RS:FindFirstChild("GasBubbleEvent")
function GAS.onPop(_position)
	GasBubbleEvent = GasBubbleEvent or RS:FindFirstChild("GasBubbleEvent")
	if GasBubbleEvent then
		GasBubbleEvent:FireServer()
	elseif SHARED.DEBUG then
		warn("[Bubble] GasBubbleEvent missing -- popped, but no gas granted. Is GasBubble.server.luau running?")
	end
	return nil
end

-- ============================================================================
-- COIN BUBBLE  (orig WorldClient:74 "spawnRing" + CoreClient:3116)
--
-- Called a "ring" throughout the original source -- it was a flat ring/cylinder
-- once, became a sphere, and the name never got changed. It is a BALL.
-- ============================================================================
local COIN = {
	ID             = "COIN",
	ENABLED        = true,

	-- look
	SIZE           = 36,     -- FATTER (was 24). Still bigger than a gas bubble -- the two
	                         -- sizes were 20/24 and are now 30/36, same ratio
	TRANSPARENCY   = 0.2,    -- and more solid-looking
	PULSE          = false,  -- (orig) only gas pockets pulse
	-- Colours cycle per bubble within a gap: gold, cyan, pink.
	COLORS         = {
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(255, 100, 200),
	},
	LABEL_TEXT     = "\240\159\170\153 +BONUS", -- 🪙 +BONUS
	LABEL_COLOR    = Color3.new(1, 1, 1), -- white, NOT the ball colour -- it has three
	LABEL_SIZE     = 14,
	LABEL_OFFSET_Y = 3,
	LABEL_WIDTH    = 120,

	-- placement (orig WorldClient:366) -- pushed FURTHER out than gas bubbles
	-- SIX PER GAP (was {1/3, 2/3}), interleaved with GAS's heights -- see the note there.
	T_POSITIONS    = {0.18, 0.34, 0.50, 0.66, 0.82, 0.94},
	SPREAD_MIN     = 85,  -- (orig) min studs off the centerline (was 55) -- wider sideways spread
	SPREAD_MAX     = 200, -- widened from 145, in step with GAS -- coins stay the further
	                      -- detour of the two, so the gap between the two spreads is kept

	-- collection (orig CoreClient:3116)
	COLLECT_RADIUS = 22,  -- still TIGHTER than gas relative to the ball (4 studs past the
	                      -- surface, vs gas's 11) -- coins are meant to cost more precision.
	                      -- Was 16 against a 24-wide ball, i.e. 4 past the surface: same.
	RESPAWN        = 30,  -- (orig) re-spawns after 30s -- faster than gas, they're worth less each
	FLOAT_COLOR    = Color3.fromRGB(255, 215, 0),

	-- pop: NO visual burst in the original -- the part is destroyed instantly and
	-- only the sound plays. Set POP_STYLE = "burst" if you want it to match gas.
	POP_STYLE      = "instant",
	SOUND_ID       = "rbxassetid://115390827163601",
	SOUND_VOLUME   = 0.6,

	-- ---- STREAK (orig CoreClient:3123) ----------------------------------
	-- Each bubble collected without landing raises the multiplier. Landing
	-- resets it. This is the whole reason coin bubbles are interesting: a
	-- chain of them in one flight pays far more than the same count spread
	-- over several flights, so players plan a route instead of grabbing
	-- whatever is nearest.
	BASE_BONUS       = 15,   -- (orig) bonus = floor(BASE * multiplier * eventMult). FALLBACK only -- see baseBonus()
	STREAK_STEP      = 0.2,  -- (orig) multiplier = 1 + streak * 0.2
	RESET_ON_LANDING = true,

	-- Fraction of ONE FLIGHT'S EARNINGS that a SINGLE bubble at the first streak step
	-- should pay. 0.032 is not a taste call -- it is the number that reproduces the kit's
	-- flat BASE_BONUS = 15 exactly at slot 1 (3375 * 0.14 * 0.032 = 15.1), so the bottom
	-- of the tower feels precisely as shipped and only the top changes.
	--
	-- PER BUBBLE, NOT PER CHAIN, and that matters now there are six in a gap instead of
	-- two. Dividing a fixed chain total by the bubble count would mean adding bubbles made
	-- each one worth a third as much and a whole gap worth exactly what it was before --
	-- more things to fly at, no more reward, which is not what "more bubbles" should mean.
	-- This way each bubble holds its value and the extra ones raise what is AVAILABLE; the
	-- limit is how many you can actually reach, which is the interesting constraint.
	BUBBLE_SHARE     = 0.032,
	COIN_PER_STUD    = 0.14, -- must match BottomHUD's COIN_PER_STUD (the climb payout rate)
}

-- BASE_BONUS, SCALED TO WHERE THE PLAYER ACTUALLY IS.
--
-- The README makes this exact point about GAS -- "pay a percentage of whatever the
-- resource is, never a flat amount, or the pickup dies the moment your realm's numbers
-- grow" -- and then hands COIN a flat 15. In the source realm that was fine. Here the
-- tower spans a 3.5x range of gaps, and a flight is paid PER STUD CLIMBED, so a flight
-- earns 473 coins at the bottom and 1644 at the top. A flat 15 means the two coin
-- bubbles in a gap are worth 7.6% of a flight on island 1 and 2.2% on island 12 -- the
-- pickup quietly stops being worth the detour exactly where the detour costs most.
--
-- So the base scales with the gap the player is currently crossing, holding a full
-- 2-bubble chain at ~7.6% of a flight all the way up. Same formula, same streak, same
-- numbers at the bottom of the tower -- it just does not decay.
--
-- Falls back to the flat BASE_BONUS if FlightTuning/HighestSlot are unavailable, so this
-- still behaves like the stock kit in a realm without them.
function COIN.baseBonus()
	local ok, FlightTuning = pcall(function()
		return require(RS:WaitForChild("DinosaurRealm", 10):WaitForChild("FlightTuning", 10))
	end)
	if not ok or not FlightTuning then return COIN.BASE_BONUS end
	local slot = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)
	local gap  = FlightTuning.gapFromSlot(slot)
	if not gap or gap <= 0 then return COIN.BASE_BONUS end
	return gap * COIN.COIN_PER_STUD * COIN.BUBBLE_SHARE
end

-- runtime streak state (module-level so onPop and the landing watcher share it)
local coinStreak, coinMultiplier = 0, 1

-- ---------------------------------------------------------------------------
-- COIN.onPop -- THE INTEGRATION POINT for coin bubbles.
-- The streak has already been advanced when this runs; `bonus` is the final
-- amount. Return a string to override the floating text.
-- ---------------------------------------------------------------------------
-- THIS IS THE KIT'S OPTION (A) -- the client computes the bonus and fires CoinEvent.
--
-- The kit flags that as trusting the client, and it is. It is used here anyway because
-- it changes NOTHING about this realm's exposure: BottomHUD already pays the entire
-- climb the same way (`CoinEvent:FireServer(gained * COIN_PER_STUD)`), and the server
-- handler takes any positive number it is given. A bubble worth ~30 coins is not the
-- soft spot in that design -- the flight payout is.
--
-- If CoinEvent is ever made authoritative, do this one at the same time and in the same
-- way: send the STREAK, let the server hold BASE_BONUS and STREAK_STEP, and delete the
-- amount from this call. Doing it here alone would buy nothing.
local CoinEvent = RS:FindFirstChild("CoinEvent")
function COIN.onPop(_position, bonus, multiplier)
	CoinEvent = CoinEvent or RS:FindFirstChild("CoinEvent")
	if CoinEvent then
		pcall(function() CoinEvent:FireServer(bonus) end)
	elseif SHARED.DEBUG then
		warn("[Bubble] CoinEvent missing -- coin bubble popped but paid nothing.")
	end
	return "+" .. bonus .. " \240\159\170\153 x" .. string.format("%.1f", multiplier)
end

local TYPES = {GAS, COIN}

-- ============================================================================
-- FLOATING TEXT -- reuses the host realm's if it has one, else a faithful
-- 3-slot copy of CoreClient's showFloatingText so the kit stands alone.
-- ============================================================================
local showFloatingText
do
	local FLOAT_SLOTS, slots = 3, {}
	local gui
	local function ensureGui()
		if gui and gui.Parent then return gui end
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then return nil end
		gui = Instance.new("ScreenGui")
		gui.Name = "BubbleFloatGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.Parent = pg
		return gui
	end
	showFloatingText = function(text, col)
		if _G.showFloatingText then return _G.showFloatingText(text, col) end -- host realm's version wins
		local parent = ensureGui(); if not parent then return end
		local slot
		for i = 1, FLOAT_SLOTS do if not slots[i] then slot = i; break end end
		if not slot then return end -- all slots busy: drop it rather than stack text on text
		slots[slot] = true
		local startY = 0.60 - (slot - 1) * 0.05 -- 0.60 / 0.55 / 0.50, drifting up 0.10 -> band 0.40..0.60
		local lbl = Instance.new("TextLabel")
		lbl.Text = text; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 22
		lbl.TextColor3 = col or Color3.fromRGB(255, 220, 0); lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0, 300, 0, 50); lbl.Position = UDim2.new(0.5, -150, startY, 0)
		lbl.ZIndex = 10; lbl.Parent = parent
		Instance.new("UIStroke").Parent = lbl
		TweenService:Create(lbl, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, -150, startY - 0.10, 0), TextTransparency = 1 }):Play()
		task.delay(1.5, function() lbl:Destroy(); slots[slot] = nil end)
	end
end

-- ============================================================================
-- ANCHORS -- one position per island, sorted low to high. Everything else
-- derives from these, so a realm with 4 islands or 40 needs no other change.
-- ============================================================================
local anchorY = {}

-- THE TOWER, FROM THE SHARED MODULE. IslandOrder.SLOT_POS is where IslandLayout puts
-- each island at startup, in climb order, and it is the ONLY reliable source on the
-- client: with StreamingEnabled a distant island's MODEL replicates but its PARTS do
-- not, so a Workspace scan (the kit's default, below) sees far islands either missing
-- or sitting at the origin. That is also why the module exists at all -- see its header.
--
-- These are model PIVOTS, not top faces, so bubbles sit a few dozen studs lower than the
-- kit intends. Against gaps of 3375-11743 with 120/200-stud pads that is noise.
local function anchorsFromIslandOrder()
	local ok, IslandOrder = pcall(function()
		return require(RS:WaitForChild("DinosaurRealm", 20):WaitForChild("IslandOrder", 20))
	end)
	if not ok or not IslandOrder or not IslandOrder.SLOT_POS then return {} end
	local out = {}
	for slot, pos in ipairs(IslandOrder.SLOT_POS) do out[slot] = pos end
	return out
end

local function collectAnchors()
	-- Shared ladder first; the attribute scan below is the kit's original path and stays
	-- as a fallback so this file still drops into a realm that has no IslandOrder.
	local fromModule = anchorsFromIslandOrder()
	if #fromModule >= 2 then return fromModule end

	local found = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			local idx = d:GetAttribute(SHARED.ANCHOR_ATTRIBUTE)
			if type(idx) == "number" then
				found[idx] = d.Position + Vector3.new(0, d.Size.Y / 2, 0) -- TOP face, not centre
			end
		end
	end
	if not next(found) and SHARED.FALLBACK_FOLDER then
		local folder = workspace:FindFirstChild(SHARED.FALLBACK_FOLDER)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				local n = tonumber(child.Name:match("^" .. SHARED.FALLBACK_PREFIX .. "(%d+)$"))
				local part = child:IsA("BasePart") and child
					or (child:IsA("Model") and (child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")))
				if n and part then found[n] = part.Position + Vector3.new(0, part.Size.Y / 2, 0) end
			end
		end
	end
	local keys = {}
	for k in pairs(found) do table.insert(keys, k) end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do table.insert(out, found[k]) end
	return out
end

-- ============================================================================
-- DRIFT  (orig WorldClient:26 -- startBubbleDrift, unchanged, SHARED by both)
--
-- Gently wander an anchored bubble within a BOX zone around its spawn point so
-- the player has to go off-course to catch it. Anchored + moved by code only ->
-- never touches flight physics. The collection loop reads the part's CURRENT
-- .Position, so it still collects at the moving spot (rising or falling).
--   homePos = spawn point (zone centre); HR = horizontal half-extent; VR = vertical
-- ============================================================================
local function startBubbleDrift(part, homePos, HR, VR)
	task.spawn(function()
		local rng = Random.new()
		local SPEED = SHARED.DRIFT_SPEED
		local function randDir()
			local d = Vector3.new(rng:NextNumber() - 0.5, (rng:NextNumber() - 0.5) * SHARED.VERTICAL_BIAS, rng:NextNumber() - 0.5)
			return (d.Magnitude > 0) and d.Unit or Vector3.new(1, 0, 0)
		end
		local vel = randDir()
		local retime = 0
		local last = os.clock()
		-- THIS bubble's island GAP, from its home Y, so the enlarged vertical band can't spill into the
		-- next island. If the gap is shorter than the requested +/-VR, the gap wins (vertical is clamped;
		-- horizontal still gets full HR).
		local yMin, yMax = homePos.Y - VR, homePos.Y + VR
		pcall(function()
			local belowY, aboveY = -math.huge, math.huge
			for _, a in ipairs(anchorY) do
				if a.Y <= homePos.Y and a.Y > belowY then belowY = a.Y end
				if a.Y >= homePos.Y and a.Y < aboveY then aboveY = a.Y end
			end
			if belowY > -math.huge then yMin = math.max(yMin, belowY + SHARED.GAP_BOTTOM_PAD) end
			if aboveY <  math.huge then yMax = math.min(yMax, aboveY - SHARED.GAP_TOP_PAD) end
		end)
		if yMin > yMax then yMin, yMax = homePos.Y, homePos.Y end -- degenerate-gap guard
		while part.Parent do
			local now = os.clock(); local dt = math.min(now - last, 0.2); last = now
			retime = retime - dt
			if retime <= 0 then -- re-aim OFTEN with a SHARP turn -> erratic, darting, hard to predict
				vel = (vel * SHARED.TURN_INERTIA + randDir())
				vel = (vel.Magnitude > 0) and vel.Unit or randDir()
				retime = SHARED.REAIM_MIN + rng:NextNumber() * (SHARED.REAIM_MAX - SHARED.REAIM_MIN)
			end
			local np = part.Position + vel * SPEED * dt
			-- clamp X/Z to the +/-HR box around home, Y to this gap; bounce velocity inward at the edges
			local cx = math.clamp(np.X, homePos.X - HR, homePos.X + HR)
			local cy = math.clamp(np.Y, yMin, yMax)
			local cz = math.clamp(np.Z, homePos.Z - HR, homePos.Z + HR)
			if cx ~= np.X then vel = Vector3.new(-vel.X, vel.Y, vel.Z) end
			if cy ~= np.Y then vel = Vector3.new(vel.X, -vel.Y, vel.Z) end -- gap floor/ceiling bounce
			if cz ~= np.Z then vel = Vector3.new(vel.X, vel.Y, -vel.Z) end
			pcall(function() part.CFrame = CFrame.new(cx, cy, cz) end)
			-- per-FRAME while the player is anywhere near: smooth at this speed, and the
			-- collection loop always matches the current position. Far away, coarser --
			-- see the FAR SLEEP note in SHARED. dt is measured, not assumed, so a coarse
			-- step still moves the bubble the correct distance.
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - part.Position).Magnitude > SHARED.FAR_DISTANCE then
				task.wait(SHARED.FAR_INTERVAL)
			else
				task.wait()
			end
		end
	end)
end

-- ============================================================================
-- LOOK  (orig WorldClient:113 pulse + :74/:126 spawn)
-- ============================================================================
local active = {}   -- [typeId] = { {part=..., home=..., color=...}, ... }
for _, t in ipairs(TYPES) do active[t.ID] = {} end

local function startPulse(part, spec)
	local function doPulse()
		if not part.Parent then return end
		local t1 = TweenService:Create(part, TweenInfo.new(spec.PULSE_TIME, Enum.EasingStyle.Sine),
			{ Size = Vector3.new(spec.PULSE_MAX, spec.PULSE_MAX, spec.PULSE_MAX) }); t1:Play()
		t1.Completed:Connect(function()
			if not part.Parent then return end
			local t2 = TweenService:Create(part, TweenInfo.new(spec.PULSE_TIME, Enum.EasingStyle.Sine),
				{ Size = Vector3.new(spec.PULSE_MIN, spec.PULSE_MIN, spec.PULSE_MIN) }); t2:Play()
			t2.Completed:Connect(function() doPulse() end)
		end)
	end
	doPulse()
end

local function spawnBubble(spec, pos, color)
	color = color or spec.COLOR or (spec.COLORS and spec.COLORS[1]) or Color3.new(1, 1, 1)

	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(spec.SIZE, spec.SIZE, spec.SIZE)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = spec.TRANSPARENCY
	p.CanCollide = false      -- never blocks or bumps a flying player
	p.Anchored = true         -- moved by code only; gravity/physics never touch it
	p.CastShadow = false
	p.Position = pos
	p.Name = spec.ID .. "Bubble"
	p.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, spec.LABEL_WIDTH, 0, 30)
	bb.StudsOffset = Vector3.new(0, spec.LABEL_OFFSET_Y, 0)
	bb.AlwaysOnTop = false    -- false on purpose: it should be hidden by terrain, not float through it
	bb.Parent = p

	local bl = Instance.new("TextLabel")
	bl.Size = UDim2.new(1, 0, 1, 0); bl.BackgroundTransparency = 1
	bl.Font = Enum.Font.GothamBold; bl.TextSize = spec.LABEL_SIZE
	bl.TextColor3 = spec.LABEL_COLOR; bl.Text = spec.LABEL_TEXT
	bl.Parent = bb
	Instance.new("UIStroke").Parent = bl

	-- home + colour live in the entry, so a respawn restores BOTH: back at the
	-- spawn point (not where it drifted to) and in its original colour.
	table.insert(active[spec.ID], {part = p, home = pos, color = color})
	if spec.PULSE then startPulse(p, spec) end
	startBubbleDrift(p, pos, SHARED.DRIFT_HR, SHARED.DRIFT_VR)
	return p
end

-- ============================================================================
-- POP  (orig WorldClient:139 for gas; coin is destroyed outright)
-- PURELY VISUAL. Grants nothing -- onPop owns the reward.
-- ============================================================================
local function playSound(spec, at)
	local s = Instance.new("Sound")
	s.SoundId = spec.SOUND_ID; s.Volume = spec.SOUND_VOLUME
	s.Parent = at or workspace
	s:Play()
	Debris:AddItem(s, 3)
end

local function popBubble(part, spec)
	if not part or not part.Parent then return end

	if spec.POP_STYLE ~= "burst" then
		-- COIN: (orig) destroyed immediately, sound only. Sound is parented to
		-- workspace, not the part, or destroying the part would cut it off.
		playSound(spec, workspace)
		part:Destroy()
		return
	end

	-- GAS: full expand + fade + sparkle burst
	local bb = part:FindFirstChildOfClass("BillboardGui")
	if bb then bb.Enabled = false end -- hide the label immediately so only the pop shows

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(part.Color)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(12, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(1.3)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(spec.POP_PARTICLES)

	playSound(spec, part)

	local t = TweenService:Create(part, TweenInfo.new(spec.POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(spec.POP_SIZE, spec.POP_SIZE, spec.POP_SIZE), Transparency = 1 })
	t:Play()
	t.Completed:Connect(function() if part.Parent then part:Destroy() end end)
	Debris:AddItem(part, 1.2) -- backup cleanup, in case the tween never completes
end

-- ============================================================================
-- PLACEMENT  (orig WorldClient:366 rings + :383 gas -- same shape, own numbers)
--
-- Bubbles sit FAR off the central climb line so grabbing one is a deliberate
-- sideways move, not something you fly through on a normal ascent. The two in
-- a gap sit on ~OPPOSITE sides so they're far from each other too.
-- ============================================================================
local function placeType(spec)
	if not spec.ENABLED then return 0 end
	local rng = Random.new()
	local placed, colorIdx = 0, 0
	for i = 1, #anchorY - 1 do
		local startPos, endPos = anchorY[i], anchorY[i + 1]
		local safeStart = startPos + Vector3.new(0, SHARED.GAP_BOTTOM_PAD, 0)
		local safeEnd   = endPos   - Vector3.new(0, SHARED.GAP_TOP_PAD, 0)
		if safeEnd.Y > safeStart.Y then -- skip gaps too short to hold a bubble
			local baseAng = rng:NextNumber() * 2 * math.pi -- per-gap base angle
			for j, t in ipairs(spec.T_POSITIONS) do
				local ang = baseAng + (j - 1) * (2 * math.pi / #spec.T_POSITIONS) -- opposite sides
				local rad = spec.SPREAD_MIN + rng:NextNumber() * (spec.SPREAD_MAX - spec.SPREAD_MIN)
				local pos = safeStart:Lerp(safeEnd, t) + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
				local color = spec.COLOR
				if spec.COLORS then
					color = spec.COLORS[(colorIdx % #spec.COLORS) + 1] -- cycle gold/cyan/pink
					colorIdx = colorIdx + 1
				end
				spawnBubble(spec, pos, color)
				placed = placed + 1
			end
		end
	end
	return placed
end

-- ============================================================================
-- STREAK  (orig CoreClient:2749 -- reset on landing)
-- Reuses the host realm's _G.hasLanded if it sets one; otherwise watches the
-- Humanoid's floor material, which is the same signal by another name.
--
-- This realm sets neither _G.hasLanded nor an equivalent -- BottomHUD tracks
-- _G.isFlying, which is THRUST, not contact: it goes false the moment you stop
-- farting, while you are still hundreds of studs up and falling. Resetting the
-- streak on that would end a chain mid-air every time the player let go of the
-- button, which is the opposite of what the streak rewards. FloorMaterial is the
-- right signal and it is the one the kit already falls back to.
-- ============================================================================
local function watchLanding()
	if not (COIN.ENABLED and COIN.RESET_ON_LANDING) then return end
	local wasAir = true
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if not hum then return end
		local grounded = (hum.FloorMaterial ~= Enum.Material.Air)
		if grounded and wasAir and coinStreak > 0 then
			if SHARED.DEBUG then print(string.format("[Bubble] landed - coin streak %d -> 0", coinStreak)) end
			coinStreak, coinMultiplier = 0, 1
		end
		wasAir = not grounded
	end)
end

-- ============================================================================
-- COLLECTION  (orig CoreClient:3089 gas / :3116 coin)
--
-- Runs EVERY frame, deliberately OUTSIDE any is-flying check, so a bubble pops
-- whether the player is RISING or FALLING through it. Re-spawns at its ORIGINAL
-- home after the type's RESPAWN delay -- note the home, not where it drifted to.
-- ============================================================================
local function collectType(spec, hrp)
	local list = active[spec.ID]
	for i = #list, 1, -1 do
		local e = list[i]
		if e and e.part and e.part.Parent then
			if (hrp.Position - e.part.Position).Magnitude < spec.COLLECT_RADIUS then
				table.remove(list, i)
				local home, color, part = e.home, e.color, e.part

				local override
				if spec.ID == "COIN" then
					-- streak FIRST, so onPop sees the multiplier this bubble earned
					coinStreak = coinStreak + 1
					coinMultiplier = 1 + coinStreak * spec.STREAK_STEP
					-- baseBonus() is gap-scaled here rather than the flat BASE_BONUS -- see
					-- its note. The event multiplier is this realm's _G.serverEventCoinMult
					-- (BottomHUD's name for it); the kit's _G.serverEventRingMult is read too
					-- so a realm that sets either still gets its double-coins event.
					local eventMult = _G.serverEventCoinMult or _G.serverEventRingMult or 1
					local base = spec.BASE_BONUS
					local okBase, scaled = pcall(spec.baseBonus)
					if okBase and type(scaled) == "number" and scaled > 0 then base = scaled end
					local bonus = math.max(1, math.floor(base * coinMultiplier * eventMult))
					local ok, err = pcall(function() override = spec.onPop(part.Position, bonus, coinMultiplier) end)
					if not ok then warn("[Bubble] COIN onPop error: " .. tostring(err)) end
					if SHARED.DEBUG then print(string.format("[Bubble] COIN popped - streak=%d x%.1f bonus=%d", coinStreak, coinMultiplier, bonus)) end
				else
					local ok, err = pcall(function() override = spec.onPop(part.Position) end)
					if not ok then warn("[Bubble] GAS onPop error: " .. tostring(err)) end
					if SHARED.DEBUG then print("[Bubble] GAS popped at " .. tostring(home)) end
				end

				popBubble(part, spec) -- visual, after the reward, so a bad onPop still pops the bubble
				local text = override or spec.FLOAT_TEXT
				if text then showFloatingText(text, spec.FLOAT_COLOR) end
				task.delay(spec.RESPAWN, function() spawnBubble(spec, home, color) end)
			end
		else
			table.remove(list, i)
		end
	end
end

local function startCollection()
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		for _, spec in ipairs(TYPES) do
			if spec.ENABLED then collectType(spec, hrp) end
		end
	end)
end

-- ============================================================================
-- BOOT
-- ============================================================================
task.spawn(function()
	-- Wait for anchors to exist. With StreamingEnabled the far ones arrive late,
	-- so poll rather than reading once and giving up on an empty workspace.
	local deadline = os.clock() + 30
	repeat
		anchorY = collectAnchors()
		if #anchorY >= 2 then break end
		task.wait(0.5)
	until os.clock() > deadline

	if #anchorY < 2 then
		warn(string.format("[Bubble] found %d anchor(s) -- need 2+. Expected IslandOrder.SLOT_POS; failing that, tag one part per island with a NUMBER attribute named '%s'. Nothing spawned.",
			#anchorY, SHARED.ANCHOR_ATTRIBUTE))
		return
	end

	local nGas  = placeType(GAS)
	local nCoin = placeType(COIN)
	watchLanding()
	startCollection()
	print(string.format("[Bubble] %d gas + %d coin across %d gaps (%d islands)",
		nGas, nCoin, #anchorY - 1, #anchorY))
end)
