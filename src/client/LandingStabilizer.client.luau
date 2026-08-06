--======================================================================
-- LandingStabilizer.client.luau  (LocalScript -> StarterPlayer/StarterPlayerScripts)
--======================================================================
-- Two bugs, one cause: YOU WERE FALLING TOO FAST FOR THE PHYSICS STEP.
--
--   1. LANDING FLINGS YOU OFF THE ISLAND. Hit ground at speed and the character
--      tumbles, keeps its sideways momentum, and skids over the edge.
--   2. YOU FALL THROUGH THE ISLAND'S TOP SURFACE into the lower parts of the model,
--      and end up inside/under geometry you should have landed on.
--
-- Both are the SAME arithmetic. IslandOrder's biggest gap is 11,743 studs, and a
-- free fall of that length under Roblox gravity (196.2) arrives at
--     v = sqrt(2 * 196.2 * 11743) ~= 2,100 studs/s
-- At 60 Hz that is ~35 STUDS OF TRAVEL PER PHYSICS STEP. Anything thinner than 35
-- studs -- which is every island's walkable shell -- can be crossed entirely between
-- one step and the next, so the solver never sees a contact and you arrive inside
-- the model. Bug 2 IS bug 1 with a slightly different landing spot.
--
-- So this does not try to patch the two symptoms separately. It caps the speed that
-- causes both, and then cleans up what is left of the skid on touchdown.
--
-- WHY A CAP AND NOT THICKER COLLISION: making every island's shell 35+ studs thick
-- is not a thing you can do to imported meshes, and CollisionFidelity does not help
-- either -- a perfectly accurate collision surface is still a surface the character
-- teleported past. Tunnelling is a function of speed, so speed is where the fix goes.
--
-- WHAT IT DOES NOT TOUCH: upward motion. Only downward velocity is clamped, so
-- fart-flight climbs, the gut tiers and every FlightTuning number behave exactly as
-- before. This is a floor on how fast you may come DOWN, nothing else.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

--======================================================================
-- CONFIG
--======================================================================
-- TERMINAL FALL SPEED, studs/second.
--
-- 350 is picked off LandingImpact's own curve, which maps landing force over
-- 95..260 studs/s -- so 350 sits just past the top of the range the game already
-- considers a maximum-force landing. Falls still look and feel fast; they simply
-- stop outrunning the physics step. At 350 the character covers ~5.8 studs per
-- 60 Hz step, comfortably thinner than any island shell.
--
-- RAISING THIS BRINGS THE BUGS BACK, in this order: somewhere past ~600 you begin
-- clipping thin decorative geometry, and past ~1,200 the main island surfaces start
-- letting you through again.
local MAX_FALL_SPEED = 350

-- How much sideways speed survives touchdown (0 = dead stop, 1 = keep it all).
-- The skid off the edge is horizontal momentum outliving the landing, so this is
-- the dial for it. Not 0: a hard stop reads as hitting glue, and you want a little
-- carry-through so a running landing still feels like one.
local LANDING_SLIDE_KEEP = 0.15

--======================================================================
local function stabilize(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hrp) then return end

	-- NO TUMBLING. A hard landing can throw the Humanoid into FallingDown or Ragdoll,
	-- and a ragdolled character has no footing at all -- it slides on whatever slope it
	-- landed on, which on a domed island means straight off the side. These states are
	-- never wanted here: nothing in this game intentionally knocks the player over.
	for _, state in ipairs({
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.PlatformStanding,
	}) do
		pcall(function() hum:SetStateEnabled(state, false) end)
	end

	-- THE CAP. Heartbeat, so it runs after physics has integrated the frame and before
	-- the next one -- clamping in RenderStepped would fight the solver instead of
	-- correcting it.
	--
	-- Only the Y component is rewritten. X and Z are left exactly as they were so
	-- horizontal control while falling is untouched.
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not hrp.Parent or not hum.Parent or hum.Health <= 0 then return end
		local v = hrp.AssemblyLinearVelocity
		if v.Y < -MAX_FALL_SPEED then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, -MAX_FALL_SPEED, v.Z)
		end
	end)

	-- KILL THE SKID. On touchdown, bleed off most of the sideways momentum and zero
	-- the vertical -- otherwise the speed built up over a several-thousand-stud drop
	-- is still in the assembly when the character starts walking, and it carries them
	-- across and off the island before the controller takes over.
	hum.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Landed then return end
		if not hrp.Parent then return end
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X * LANDING_SLIDE_KEEP, 0, v.Z * LANDING_SLIDE_KEEP)
	end)

	-- one connection per character, released with it (respawns build a fresh one)
	hum.Died:Connect(function() if conn then conn:Disconnect(); conn = nil end end)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent and conn then conn:Disconnect(); conn = nil end
	end)
end

if player.Character then task.spawn(stabilize, player.Character) end
player.CharacterAdded:Connect(function(char) task.spawn(stabilize, char) end)

print(("[LandingStabilizer] ready -- fall speed capped at %d studs/s (no tunnelling through island tops), "
	.. "tumble states off, %d%% of sideways speed kept on touchdown (no skidding off the edge)")
	:format(MAX_FALL_SPEED, math.floor(LANDING_SLIDE_KEEP * 100)))
