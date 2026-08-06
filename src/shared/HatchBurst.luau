--======================================================================
-- HatchBurst.luau  (ModuleScript, ReplicatedStorage.DinosaurRealm.HatchBurst)
--======================================================================
-- ONE shared "cool hatch" explosion so every island's pet hatch looks the same:
-- a bright flash + an expanding neon shockwave ring + a sparkle blast + egg-shell
-- shards flying outward + a pop sound. Call HatchBurst.play(worldPos, shellColor).
--======================================================================
local Workspace = game:GetService("Workspace")
local TS        = game:GetService("TweenService")
local Debris    = game:GetService("Debris")

local M = {}

-- pos: Vector3 world position to burst at.  shellColor (optional): the egg-shell color for the shards.
function M.play(pos, shellColor)
	if typeof(pos) ~= "Vector3" then return end
	shellColor = shellColor or Color3.fromRGB(245, 235, 180)

	-- 1) bright flash sphere
	local flash = Instance.new("Part"); flash.Shape = Enum.PartType.Ball; flash.Size = Vector3.new(2,2,2)
	flash.Color = Color3.fromRGB(255,250,210); flash.Material = Enum.Material.Neon
	flash.Anchored = true; flash.CanCollide = false; flash.CanQuery = false; flash.CastShadow = false; flash.CFrame = CFrame.new(pos); flash.Parent = Workspace
	TS:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(18,18,18), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)

	-- 2) expanding shockwave ring (flat neon disc)
	local ring = Instance.new("Part"); ring.Shape = Enum.PartType.Cylinder; ring.Size = Vector3.new(0.4,3,3)
	ring.Color = Color3.fromRGB(120,220,255); ring.Material = Enum.Material.Neon; ring.Transparency = 0.15
	ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0,0,math.rad(90)); ring.Parent = Workspace
	TS:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4,30,30), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.7)

	-- 3) sparkle particle blast
	local fx = Instance.new("Part"); fx.Anchored = true; fx.CanCollide = false; fx.CanQuery = false; fx.Transparency = 1; fx.Size = Vector3.new(1,1,1); fx.CFrame = CFrame.new(pos); fx.Parent = Workspace
	local em = Instance.new("ParticleEmitter"); em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(255,240,160), Color3.fromRGB(120,220,255))
	em.Lifetime = NumberRange.new(0.5,1.1); em.Speed = NumberRange.new(12,26); em.SpreadAngle = Vector2.new(180,180)
	em.Size = NumberSequence.new(1.6, 0); em.Rate = 0; em.LightEmission = 0.9; em.Rotation = NumberRange.new(0,360); em.Parent = fx
	em:Emit(70)
	Debris:AddItem(fx, 1.3)

	-- 4) egg-shell shards flying outward
	for s = 1, 12 do
		local ang = (s-1) * (2*math.pi/12)
		local shard = Instance.new("Part"); shard.Shape = Enum.PartType.Ball; shard.Size = Vector3.new(1.0,0.7,1.0)
		shard.Color = shellColor; shard.Material = Enum.Material.SmoothPlastic
		shard.Anchored = true; shard.CanCollide = false; shard.CanQuery = false; shard.CastShadow = false
		shard.CFrame = CFrame.new(pos) * CFrame.new(0,0.4,0); shard.Parent = Workspace
		local out = Vector3.new(math.cos(ang)*7, math.random()*5-0.5, math.sin(ang)*7)
		TS:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(pos + out) * CFrame.Angles(math.random()*6, math.random()*6, math.random()*6), Transparency = 1, Size = Vector3.new(0.2,0.2,0.2) }):Play()
		Debris:AddItem(shard, 0.8)
	end

	-- 5) egg-opening / pop sound. Lives on its OWN holder part (not `fx`, which is
	-- cleaned up at 1.3s) so it always plays to the very END -- it is no longer cut
	-- off the instant the egg has fully hatched. Cleaned up when the sound finishes.
	pcall(function()
		local holder = Instance.new("Part"); holder.Name = "HatchSound"
		holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false
		holder.CastShadow = false; holder.Transparency = 1; holder.Size = Vector3.new(1,1,1)
		holder.CFrame = CFrame.new(pos); holder.Parent = Workspace
		local snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://92880640988467"; snd.Volume = 2.5; snd.Parent = holder
		snd.Ended:Connect(function() holder:Destroy() end)
		Debris:AddItem(holder, 15) -- safety cap in case .Ended never fires
		snd:Play()
	end)
end

return M
