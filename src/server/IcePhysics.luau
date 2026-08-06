--======================================================================
-- IcePhysics.lua  (ModuleScript)
--======================================================================
-- The SERVER side of the IceAge event's ★ GUARDED PLAYER PHYSICS ★.
--
-- Player characters are CLIENT-OWNED, so the server can NOT reliably set a
-- player's velocity/friction/WalkSpeed. Instead this module is the
-- SERVER-AUTHORITATIVE DECISION MAKER: it decides WHEN gusts blow and WHICH
-- players are near an ice-meteor freeze, then MESSAGES those clients via
-- IceAgeSync. The CLIENT (IceAgeUI) actually applies the effect, gated by
-- the strict rules below. This module holds NO permanent state and NEVER
-- moves a character itself.
--
-- ★ THE CONTRACT (enforced together with IceAgeUI) ★
--   * SLIDE (slight slipperiness) + WIND (gentle gust nudge): apply ONLY on
--     the client when the player is GROUNDED and `_G.isFlying ~= true`. The
--     INSTANT the player flies or leaves the ground, the client removes
--     them. They can NEVER shove a player off a fart-flight or out of a
--     climb. Both are SMALL + CONFIG-tunable/zeroable.
--   * METEOR FREEZE: MOVEMENT-ONLY. The client changes ONLY the Humanoid's
--     WalkSpeed (briefly) and restores the captured original. It NEVER
--     touches the fart meter / fart power / flight / gas / coins and NEVER
--     cancels a climb. A frozen player keeps FULL fart power + can still fly.
--   * Nothing is permanent: on effect end AND on event reset every player's
--     friction / WalkSpeed / forces return to normal (the client guarantees
--     this; this module also just stops issuing new effects on cleanup()).
--
-- This module never reads/writes any _G flight/power/coin global. (The only
-- _G access in the whole event is the client READING `_G.isFlying`.)
--======================================================================

local IcePhysics = {}

local Players = game:GetService("Players")

-- Wired by init().
local CONFIG = nil
local IceAgeSync = nil

-- Monotonic id so the client can ignore stale gust messages after a reset.
local epoch = 0

--------------------------------------------------------------------
-- init(config, syncEvent): wire shared dependencies. No state is created.
--------------------------------------------------------------------
function IcePhysics.init(config, syncEvent)
	CONFIG = config
	IceAgeSync = syncEvent
end

--------------------------------------------------------------------
-- broadcastGust(dir): tell EVERY client a gust is sweeping in horizontal
-- direction `dir` (a unit Vector3 on the XZ plane). The client applies a
-- GENTLE, SHORT horizontal nudge -- but ONLY if that client is grounded +
-- not flying (the client enforces the gate; the server just announces).
--
-- We pass the configured force/duration so the client never has to know
-- CONFIG; if WIND_PUSH_FORCE is 0 the client treats it as "no push".
--------------------------------------------------------------------
function IcePhysics.broadcastGust(dir)
	if not IceAgeSync then return end
	-- Normalize to a flat XZ unit direction (defensive).
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	end
	flat = flat.Unit
	IceAgeSync:FireAllClients("gust", {
		epoch = epoch,
		dir = flat,
		force = CONFIG.WIND_PUSH_FORCE,           -- gentle; client clamps/ignores if 0
		duration = CONFIG.GUST_PUSH_DURATION,     -- short
	})
end

--------------------------------------------------------------------
-- applyFreeze(impactPos): SERVER-AUTHORITATIVE proximity check for an ice
-- meteor impact. The SERVER decides who is within FREEZE_RADIUS, then tells
-- ONLY those clients to briefly reduce their OWN Humanoid WalkSpeed (and
-- restore it). MOVEMENT-ONLY -- the client never touches gas/power/flight/
-- coins, and a frozen player keeps full fart power + can still fly.
--
-- If FREEZE_RADIUS or FREEZE_DURATION is 0, freezing is disabled.
--------------------------------------------------------------------
function IcePhysics.applyFreeze(impactPos)
	if not IceAgeSync then return end
	if CONFIG.FREEZE_RADIUS <= 0 or CONFIG.FREEZE_DURATION <= 0 then
		return -- freeze disabled via CONFIG
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - impactPos).Magnitude
			if dist <= CONFIG.FREEZE_RADIUS then
				-- Tell THIS client to slow ONLY its WalkSpeed briefly. The client
				-- captures + restores the original, and skips/clears it instantly
				-- if the player is flying (WalkSpeed is irrelevant to flight, and
				-- we must never appear to interfere with a climb).
				IceAgeSync:FireClient(plr, "freeze", {
					epoch = epoch,
					walkSpeed = CONFIG.FREEZE_WALKSPEED, -- the reduced speed
					duration = CONFIG.FREEZE_DURATION,   -- brief
				})
			end
		end
	end
end

--------------------------------------------------------------------
-- cleanup(): the server has no permanent physics state to tear down (the
-- client owns + restores every effect). We bump the epoch so any in-flight
-- gust/freeze messages the client receives AFTER a reset are recognized as
-- stale and ignored -- a belt-and-suspenders guard against leftover effects.
-- The manager also fires "reset" to the clients, which force-restores
-- everyone's friction/WalkSpeed/forces regardless.
--------------------------------------------------------------------
function IcePhysics.cleanup()
	epoch = epoch + 1
end

-- Expose the current epoch so the manager could include it in "reset" if
-- desired (the client treats reset as authoritative either way).
function IcePhysics.getEpoch()
	return epoch
end

return IcePhysics
