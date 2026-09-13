--======================================================================
-- GasBubble.server.luau  (Script -> ServerScriptService/DinosaurRealmServer)
--======================================================================
-- THE REWARD HALF of the Gas Bubble Kit. The bubbles themselves are entirely
-- client-side and deliberately so (see GasBubbles.client.luau) -- this exists only
-- because the THING THEY PAY IN cannot be.
--
-- WHY THE CLIENT CANNOT JUST ADD THE GAS ITSELF
-- BottomHUD's gas meter is client-authoritative while draining, and it reports what
-- is left through BurnFuelEvent -- which the server clamps so fuel ONLY EVER BURNS
-- DOWN (`r = math.clamp(r, 0, cp.Value)`). That clamp is right and should stay: it is
-- what stops a client from simply announcing a full tank. But it also means a bubble
-- that only bumps the local meter leaves the server's CurrentPower BEHIND, and the
-- food stand reads that stale value -- so it would sell the player food they have no
-- room for, take the coins, and the client would clamp the power away. The player
-- pays for nothing. Routing the grant through here keeps both sides on one number.
--
-- WHAT CANNOT BE VERIFIED, STATED PLAINLY
-- Bubbles are created on the client and do not exist on the server, so the server
-- CANNOT check that a player was really next to one. Any client can fire this remote.
-- The defence is therefore a BUDGET, not a proof: the grant is small, capped per
-- minute, and spaced -- so the worst an exploiter gets is roughly what an honest
-- player gets for flying well, which is the point at which cheating stops paying.
-- If bubbles ever become worth much more than 2%, this needs a real anchor check
-- (server-spawned bubbles, or a signed position), not a bigger cooldown.
--======================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local function ev(name)
	local e = RS:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end
	return e
end
local GasBubbleEvent = ev("GasBubbleEvent") -- c->s: () "I popped a bubble"
local RegenEvent     = ev("RegenEvent")     -- s->c: (powerAdded, currentPower, stomachMax)

-- ===== FLAT 2 FART POWER. THIS IS A DELIBERATE REVERSAL -- READ BEFORE RESTORING. =====
-- The percentage argument (kept below, because it is still correct on its own terms) says
-- a flat grant "decays into nothing" on a big gut. That is now the POINT, not the flaw.
--
-- WHY IT CHANGED. Gas bubbles refuel you MID-FLIGHT: the grant raises the server's
-- CurrentPower and BottomHUD adopts any rise, so a bubble met on the way up quietly
-- extends the flight you are already on. A measured run shows it plainly -- crossing 11,
-- fuel goes 278 -> 280 between two ticks of a single flight. That is the flight economy's
-- one unmetered fuel source, and the whole progression is solved assuming it is zero.
--
-- At 0.2% of tank the grant had already grown back into the late game by rounding:
--     Hatchling 1   Raptor 1   Dilo 1   Trike 2   Rex 3   Titan 4   Colossus 6   Primal 20
-- so the biggest guts -- the ones on the longest, most carefully solved crossings -- were
-- collecting the most free fuel per bubble. Exactly backwards for pacing.
--
-- A FLAT 2 INVERTS THAT. It is a real, felt top-up on the small early tanks (1 -> 2, and
-- 2 on a 120-stud Hatchling tank is a visible 1.7%) and it is deliberately negligible on
-- a Colossus (2 of 2600 = 0.08%), where the ladder is tightest and free fuel does the most
-- damage. Bubbles stay worth flying through while you are learning and stop being able to
-- move a late crossing at all.
--
-- The original percentage reasoning, preserved:
--
-- PERCENT, NEVER A FLAT AMOUNT. Straight from the source realm's comment: at the base
-- gut 1 meter point IS 1 fart power, so this stays a fixed share of the tank on a Titan
-- Gut instead of decaying into nothing. A flat +2 would be 0.06% of a 3230 tank, i.e.
-- not worth flying sideways for.
--
-- CUT FROM 0.02 TO 0.002, AND IT IS THE SINGLE MOST LOAD-BEARING NUMBER FOR PACING.
-- Bubbles.client places SIX gas bubbles per gap, so at 2% each a player who flew through
-- them arrived with +12% OF A WHOLE TANK of free fuel, granted MID-FLIGHT. That rescues
-- any attempt that would otherwise have fallen short by less than 12% -- and because
-- every island sits at ~97% of a full tank (IslandOrder's rho = 1.031), the attempt right
-- before success always lands in exactly that band. So the last failed flight of nearly
-- every crossing got carried over the line, and crossings collapsed to ONE FLIGHT:
--     gas 2.0%  ->  3 / 4 / 8 / 11 one-flight crossings at 25 / 50 / 75 / 100% pickup
--     gas 0.2%  ->  0 / 0 / 0 /  1
-- Total flights over the tower went the same way: 13 at full pickup, now 29.
--
-- It is still 6 x 0.2% = 1.2% of a tank per gap, which is a genuine top-up on a long
-- crossing; it just cannot hand you the island. Raise it and the one-flight crossings
-- come straight back -- see the arithmetic in IslandOrder's SLOT_POS note.
-- (the superseded value was GRANT_PERCENT = 0.002 -- 0.2% of tank, rounded up)
local GRANT_POWER = 2         -- flat fart power per gas bubble, every gut, every tank

-- The budget described above. Two bubbles sit in each gap and a crossing is ~45 s, so an
-- honest player meets far fewer than this; the cap only ever bites on a spammer.
-- THE RATE LIMITER HAD TO SPEED UP WITH THE PLAYER. Flights are 2.2x shorter in wall-clock
-- since the tower was compressed, so a crossing's worth of gas bubbles now arrives in less
-- than half the time. Left alone, these caps would have started throttling ordinary play
-- rather than only abuse -- the limiter is meant to bound grants per CROSSING, and it only
-- ever expressed that in seconds because seconds used to be a fair proxy for a crossing.
-- Both scaled x0.455 (were 0.75 and 60); WINDOW_MAX is a COUNT and stays.
local MIN_INTERVAL   = 0.34  -- seconds between accepted grants
local WINDOW_SECONDS = 27
local WINDOW_MAX     = 12    -- accepted grants per window

local lastGrant, windowStart, windowCount = {}, {}, {}

Players.PlayerRemoving:Connect(function(plr)
	lastGrant[plr], windowStart[plr], windowCount[plr] = nil, nil, nil
end)

GasBubbleEvent.OnServerEvent:Connect(function(player)
	local ls = player:FindFirstChild("leaderstats"); if not ls then return end
	local cp = ls:FindFirstChild("CurrentPower")
	local sm = ls:FindFirstChild("StomachMax")
	if not (cp and sm) or sm.Value <= 0 then return end

	local now = os.clock()
	if lastGrant[player] and (now - lastGrant[player]) < MIN_INTERVAL then return end
	if not windowStart[player] or (now - windowStart[player]) > WINDOW_SECONDS then
		windowStart[player], windowCount[player] = now, 0
	end
	if windowCount[player] >= WINDOW_MAX then return end

	-- FLAT, not a share of the tank (see the long note by GRANT_POWER). Still clamped to
	-- the room actually left in the tank on the next line, so a full player gets nothing.
	local grant = GRANT_POWER
	local before = cp.Value
	cp.Value = math.min(sm.Value, before + grant)
	local added = cp.Value - before
	if added <= 0 then return end -- already full: not an error, just nothing to give

	lastGrant[player] = now
	windowCount[player] = windowCount[player] + 1
	-- BottomHUD adopts CurrentPower only when it RISES, which is exactly this case.
	pcall(function() RegenEvent:FireClient(player, added, cp.Value, sm.Value) end)
end)

-- Say the live number at boot. This one is load-bearing for pacing and it used to vary by
-- gut, so a log that states it flatly is the quickest way to confirm which build is running.
print(("[GasBubble] ready -- flat +%d fart power per bubble on every gut "
	.. "(was 0.2%% of tank: 1 on a Hatchling, 6 on a Colossus, 20 on a Primal)")
	:format(GRANT_POWER))
