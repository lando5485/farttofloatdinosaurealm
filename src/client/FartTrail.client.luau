--======================================================================
-- FartTrail.client.luau  (LocalScript)
--======================================================================
-- The green fart-cloud trail that streams out behind a player while they
-- fart-fly. Purely cosmetic -- no flight wiring, no replication.
--
-- WHO GETS ONE: every character on this client, yours and other players'.
--   * LOCAL player  -> driven by the real flight flag (_G.isFlying, set by
--     BottomHUD's fart loop), so the trail starts/stops exactly with thrust.
--   * OTHER players -> flight is client-driven and nothing about it
--     replicates, so a SUSTAINED fast climb reads as flying: velocity.Y
--     above RISE_VY for SUSTAIN seconds. A normal jump (JumpPower 50 decays
--     through 24 in ~0.13s under gravity) can never hold the threshold that
--     long; the slowest flight tier climbs at a constant 40 and trips it in
--     one window.
--
-- GLITTER: owners of the Glitter Fart Trail gamepass (HasGlitterTrail
-- attribute, set server-side by PurchaseReceipts) get a gold sparkle
-- emitter layered on top of the puff. The attribute replicates, so other
-- players' glitter shows too.
--======================================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local RISE_VY  = 24    -- studs/s upward before a non-local character counts as flying
local SUSTAIN  = 0.3   -- seconds the climb must hold (filters out ordinary jumps)
local GRACE    = 0.25  -- seconds the trail lingers after the climb stops (no flicker)

-- classic fart green: bright pea-soup edge cooling into a murky olive
local PUFF_COLOR = ColorSequence.new(Color3.fromRGB(178, 210, 120), Color3.fromRGB(110, 130, 80))

-- ===== build (or fetch) the two emitters on a character's root =====
local function ensureTrail(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local att = hrp:FindFirstChild("FartTrailAtt")
	if att then return att end
	att = Instance.new("Attachment")
	att.Name = "FartTrailAtt"
	att.Position = Vector3.new(0, -1, 1) -- just behind and below the torso (the source)
	att.Parent = hrp

	local puff = Instance.new("ParticleEmitter")
	puff.Name = "FartPuff"
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = PUFF_COLOR
	puff.Lifetime = NumberRange.new(0.5, 1.1)
	puff.Rate = 26
	puff.Speed = NumberRange.new(2, 5)
	puff.SpreadAngle = Vector2.new(25, 25)
	puff.Rotation = NumberRange.new(0, 360)
	puff.RotSpeed = NumberRange.new(-40, 40)
	puff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.4),
	})
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Acceleration = Vector3.new(0, -2, 0) -- clouds sag as the flier climbs away
	puff.LightEmission = 0.1
	puff.Enabled = false
	puff.Parent = att

	local glitter = Instance.new("ParticleEmitter")
	glitter.Name = "FartGlitter"
	glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glitter.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 180, 60))
	glitter.Lifetime = NumberRange.new(0.4, 0.9)
	glitter.Rate = 18
	glitter.Speed = NumberRange.new(3, 7)
	glitter.SpreadAngle = Vector2.new(35, 35)
	glitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	glitter.LightEmission = 0.85
	glitter.Enabled = false
	glitter.Parent = att

	return att
end

-- per-player trail state: [player] = { riseFor = s above threshold, offFor = s since last flying }
local state = {}
Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		if hrp and hum then
			local st = state[plr]
			if not st then st = { riseFor = 0, offFor = GRACE }; state[plr] = st end

			local flying
			if hum.Health <= 0 then
				flying = false -- a dead body falling is not farting
				st.riseFor = 0
			elseif plr == localPlayer then
				flying = _G.isFlying == true -- the real flag; exact start/stop
			else
				if hrp.AssemblyLinearVelocity.Y > RISE_VY then
					st.riseFor = st.riseFor + dt
				else
					st.riseFor = 0
				end
				flying = st.riseFor >= SUSTAIN
			end
			st.offFor = flying and 0 or (st.offFor + dt)

			local on = st.offFor < GRACE
			local att = ensureTrail(char)
			if att then
				local puff = att:FindFirstChild("FartPuff")
				local glitter = att:FindFirstChild("FartGlitter")
				if puff and puff.Enabled ~= on then puff.Enabled = on end
				if glitter then
					local wantGlitter = on and plr:GetAttribute("HasGlitterTrail") == true
					if glitter.Enabled ~= wantGlitter then glitter.Enabled = wantGlitter end
				end
			end
		end
	end
end)

print("[FartTrail] ready -- green puff trail while fart-flying (glitter for pass owners)")
