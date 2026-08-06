--======================================================================
-- PickupFloor.luau  (ModuleScript -> ReplicatedStorage/DinosaurRealm)
--======================================================================
-- THE RULE: no collectible is ever handed over on a single prompt trigger.
-- Every pickup takes at least PickupFloor.SECONDS, and that floor is ENFORCED
-- rather than tuned. Tuning a mechanic "to feel like 15s" does not work --
-- players mash, and anything bar-based gets beaten in three seconds.
--
-- The quest scripts each keep their own VERB (dig / reel / swat / carve /
-- shove). This module only holds the two primitives that make the floor exact.
-- Pick by input style:
--
--   newCeiling -- ANY bar-fill mechanic, and the best of the two. A ceiling
--                 rises from the bar's start position to 1.0 over exactly N
--                 seconds; the fill is clamped to it every frame AND on every
--                 input. The player can never finish early no matter how fast
--                 they input, and going SLOWER than the ceiling still costs
--                 them extra time. Exact, invisible, un-gameable.
--
--   cadence    -- tap-per-action mechanics. N actions x cooldown IS the floor,
--                 and extra presses inside the cooldown do nothing.
--                 Re-enable the prompt behind the SAME guard the activation
--                 code uses, or a finished (or abandoned) object re-arms itself.
--
-- MOBILE FIRST: whatever input rate a floor implies must stay under ~2.7/sec.
-- Length comes from more reps, never from faster input.
--
-- The payoff is NOT padded. Hatches, egg rises and cutscene beats stay instant
-- -- this lengthens the WORK, never the reward.
--======================================================================

local PickupFloor = {}

-- The floor itself. One number, so an island can't drift off the standard.
PickupFloor.SECONDS = 15

-- ISLAND 1's LOST EGGS run 30% short of the standard, by request. They are the very
-- first collectible a new player touches, and five of them at the full floor is 75
-- seconds of rocking before the tutorial island opens up.
--
-- This lives HERE rather than as a literal in the two scripts that need it because the
-- CLIENT's rising ceiling and the SERVER's claim check must agree exactly. If they ever
-- drift apart, the server silently refuses every egg the panel says is finished -- which
-- is precisely the failure the eggs already shipped with once.
PickupFloor.ISLAND1_EGG_SECONDS = 10.5

-- What "full" means for a completion test. See the warning on newCeiling below --
-- this is not a nicety, a bar-fill verb that tests against 1.0 cannot be finished.
-- 0.995 of a 15s ceiling is 14.93s, so the floor still holds to within a frame or two.
PickupFloor.DONE = 0.995

--======================================================================
-- RISING CEILING -- for bar-fill mechanics.
--======================================================================
-- Usage:
--   local ceil = PickupFloor.newCeiling(startFill)      -- 15s by default
--   -- every frame:  ceil:step(dt);  fill = ceil:clamp(fill + gain*dt)
--   -- on each input: fill = ceil:clamp(fill + tapGain)
--
-- `fill >= 1` is only reachable once the ceiling itself reaches 1, which
-- happens exactly `seconds` after the ceiling was created.
--
-- !! TEST AGAINST PickupFloor.DONE, NEVER AGAINST 1.0 !!
-- A clamped fill can only ever REACH the ceiling, never pass it -- so anything
-- that takes even a sliver back out after the clamp makes a `fill >= 1` test
-- unpassable, and the bar sits visibly full forever. Every drain-style verb has
-- exactly that shape (`fill = ceil:clamp(fill - leak*dt)` then test), and three
-- shipped minigames -- the island1 eggs, the island11 geysers and the raptor
-- ham-bone -- were each uncompletable because of it. 1/N is also inexact in
-- binary: fourteen 1/14ths sum to 0.9999999999999997, which fails on its own.
--
-- Test on the INPUT path too, not just per frame, so the winning action pays out
-- immediately instead of being charged one frame of drain first.
function PickupFloor.newCeiling(startFill, seconds)
	startFill = math.clamp(startFill or 0, 0, 1)
	seconds = seconds or PickupFloor.SECONDS

	local c = {
		value = startFill,
		rate  = (1 - startFill) / math.max(0.001, seconds),
	}

	-- advance the ceiling by dt; returns its new value
	function c:step(dt)
		self.value = math.min(1, self.value + self.rate * dt)
		return self.value
	end

	-- clamp a candidate fill to the ceiling. Call this on EVERY write to the
	-- bar -- a single unclamped input path is all it takes to break the floor.
	function c:clamp(fill)
		return math.min(fill, self.value)
	end

	return c
end

--======================================================================
-- FORCED CADENCE -- for tap-per-action mechanics.
--======================================================================
-- Cooldown to put between actions so that `actions` of them span at least
-- `seconds`. The FIRST action is free (it starts the clock), so the floor is
-- (actions - 1) * cooldown -- which is what this solves for.
--
--   local COOLDOWN = PickupFloor.cadence(16)   -- 16 swings -> 1.0s apart -> 15s
function PickupFloor.cadence(actions, seconds)
	seconds = seconds or PickupFloor.SECONDS
	return seconds / math.max(1, (actions or 1) - 1)
end

--======================================================================
-- The house "X" close button. A backdrop tap NEVER closes a panel in this
-- game -- only this does, and bailing out is worth no reward.
--======================================================================
function PickupFloor.addCloseButton(panel, onClose)
	local x = Instance.new("TextButton")
	x.Name = "Close"
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -8, 0, 8)
	x.Size = UDim2.fromOffset(30, 30)
	x.BackgroundColor3 = Color3.fromRGB(28, 24, 22)
	x.BackgroundTransparency = 0.25
	x.Font = Enum.Font.GothamBold
	x.TextSize = 18
	x.TextColor3 = Color3.fromRGB(255, 235, 220)
	x.Text = "X"
	x.ZIndex = 20
	x.Parent = panel
	Instance.new("UICorner", x).CornerRadius = UDim.new(1, 0)
	local s = Instance.new("UIStroke", x)
	s.Color = Color3.fromRGB(255, 255, 255)
	s.Transparency = 0.55
	s.Thickness = 2
	x.Activated:Connect(function()
		if onClose then onClose() end
	end)
	return x
end

return PickupFloor
