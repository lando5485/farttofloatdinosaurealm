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

-- PERCENT, NEVER A FLAT AMOUNT. Straight from the source realm's comment: at the base
-- gut 1 meter point IS 1 fart power, so this is +2 power there -- and stays 2% of the
-- tank on a Titan Gut instead of decaying into nothing. A flat +2 would be 0.06% of a
-- 3230 tank, i.e. not worth flying sideways for.
local GRANT_PERCENT = 0.02

-- The budget described above. Two bubbles sit in each gap and a crossing is ~45 s, so an
-- honest player meets far fewer than this; the cap only ever bites on a spammer.
local MIN_INTERVAL   = 0.75  -- seconds between accepted grants
local WINDOW_SECONDS = 60
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

	-- Round UP so the smallest tank still gets a whole point rather than a silent zero.
	local grant = math.max(1, math.ceil(sm.Value * GRANT_PERCENT))
	local before = cp.Value
	cp.Value = math.min(sm.Value, before + grant)
	local added = cp.Value - before
	if added <= 0 then return end -- already full: not an error, just nothing to give

	lastGrant[player] = now
	windowCount[player] = windowCount[player] + 1
	-- BottomHUD adopts CurrentPower only when it RISES, which is exactly this case.
	pcall(function() RegenEvent:FireClient(player, added, cp.Value, sm.Value) end)
end)
