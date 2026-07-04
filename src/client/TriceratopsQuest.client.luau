--======================================================================
-- TriceratopsQuest.client.luau  (LocalScript)
--======================================================================
-- Island 2 "Fern Frontier" grant for the Triceratops pet. Mirrors EXACTLY how
-- island3's BurritoDig grants the Raptor: a hatchable EGG with an [E] prompt ->
-- on hatch it spawns the follower, adds the Pet Hub card, and fires the server
-- grant (TriceratopsHatched) so it's equippable like the others.
-- Also exposes _G.GrantTriceratops(cf) + a /trike chat command.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local TS        = game:GetService("TweenService")
local HatchBurst = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("HatchBurst")) -- shared cool hatch FX
local player    = Players.LocalPlayer

local st = { owns = false, hatching = false }

local function floatText(pos, text)
	local a = Instance.new("Part"); a.Anchored=true; a.CanCollide=false; a.CanQuery=false; a.Transparency=1; a.Size=Vector3.new(1,1,1); a.CFrame=CFrame.new(pos); a.Parent=Workspace
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,240,0,40); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Parent=a
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.FredokaOne; lbl.TextSize=22; lbl.TextColor3=Color3.fromRGB(230,236,196); lbl.Text=text; lbl.Parent=bb
	Instance.new("UIStroke").Parent = lbl
	TS:Create(lbl, TweenInfo.new(1.4), {TextTransparency=1}):Play()
	task.delay(1.6, function() a:Destroy() end)
end

-- the GRANT (identical path to BurritoDig -> Raptor)
local function grant(cf)
	if st.owns then return end
	st.owns = true
	if _G.SpawnTriceratopsFollower then pcall(function() _G.SpawnTriceratopsFollower(cf) end) end
	if _G.PetHubAddPet then pcall(function() _G.PetHubAddPet("TriceratopsPet", { petId="TriceratopsPet", displayName="Triceratops", level=1, xp=0, xpNeed=100, maxLevel=25, milestone="Newly hatched!" }) end) end
	do local th = RS:FindFirstChild("TriceratopsHatched"); if th then pcall(function() th:FireServer() end) end end
	print("[Trike] Triceratops granted (follower + Pet Hub card + server grant)")
end
_G.GrantTriceratops = grant

-- /trike chat command -> grant it in front of you (dev shortcut)
player.Chatted:Connect(function(msg)
	local m = string.gsub(string.lower(msg), "%s", "")
	if m == "/trike" or m == "/triceratops" then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = hrp and (hrp.CFrame * CFrame.new(0,0,-6)) or CFrame.new(0,8,0)
		grant(at); floatText((hrp and hrp.Position or Vector3.zero)+Vector3.new(0,4,0), "Triceratops unlocked! \xF0\x9F\xA6\x95")
	end
end)

-- ===== island2 "Fern Frontier" EGG + Hatch prompt (the assigned grant) =====
task.spawn(function()
	local isl = Workspace:FindFirstChild("island2") or Workspace:WaitForChild("island2", 60)
	if not isl then warn("[Trike] island2 not found -> no egg placed (use /trike or _G.GrantTriceratops)"); return end
	local bcf, bsize = isl:GetBoundingBox()
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character }
	local topY = bcf.Position.Y + bsize.Y/2
	local hit = Workspace:Raycast(Vector3.new(bcf.Position.X, topY + 60, bcf.Position.Z), Vector3.new(0,-400,0), rp)
	local y = (hit and hit.Position.Y or topY) + 2.0
	local center = Vector3.new(bcf.Position.X, y, bcf.Position.Z)

	-- cute egg (cream shell + a few earthy spots)
	local egg = Instance.new("Model"); egg.Name = "TriceratopsEgg"
	local function part(name, sh, sz, col, cf)
		local p = Instance.new("Part"); p.Name=name; p.Shape=sh; p.Size=sz; p.Color=col; p.Material=Enum.Material.SmoothPlastic
		p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CastShadow=false; p.CFrame=cf; p.Parent=egg; return p
	end
	local shell = part("Shell", Enum.PartType.Ball, Vector3.new(3.0,4.0,3.0), Color3.fromRGB(232,224,190), CFrame.new(center))
	egg.PrimaryPart = shell
	for _, sp in ipairs({ {0.9,0.6,0.7}, {-0.7,-0.4,0.8}, {0.4,-0.9,-0.6}, {-0.5,0.9,-0.4} }) do
		part("Spot", Enum.PartType.Ball, Vector3.new(0.7,0.7,0.7), Color3.fromRGB(150,160,110), CFrame.new(center + Vector3.new(sp[1],sp[2],sp[3])))
	end
	egg.Parent = Workspace
	local hl = Instance.new("Highlight"); hl.FillColor = Color3.fromRGB(190,200,150); hl.FillTransparency = 0.55; hl.OutlineColor = Color3.fromRGB(120,128,86); hl.Adornee = egg; hl.Parent = egg
	-- gentle bob
	task.spawn(function() local t = 0 while egg.Parent and not st.owns do t += 0.05; pcall(function() egg:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t*2)*0.25, 0)) * CFrame.Angles(0, math.sin(t)*0.12, 0)) end); task.wait(0.05) end end)

	local pp = Instance.new("ProximityPrompt"); pp.ActionText = "Hatch"; pp.ObjectText = "Triceratops Egg"
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.4; pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false; pp.Parent = shell
	pp.Triggered:Connect(function()
		if st.owns or st.hatching then return end
		st.hatching = true
		local base = egg:GetPivot()
		-- quick shake then grant
		local t0 = os.clock()
		while os.clock()-t0 < 1.0 and egg.Parent do local p=(os.clock()-t0)/1.0; local amp=0.1+p*0.9
			pcall(function() egg:PivotTo(base * CFrame.new((math.random()-0.5)*amp,0,(math.random()-0.5)*amp) * CFrame.Angles(0, math.rad((math.random()-0.5)*60),0)) end); task.wait() end
		HatchBurst.play(center + Vector3.new(0,1,0), Color3.fromRGB(232,224,190)) -- COOL hatch explosion
		grant(base)
		floatText(center + Vector3.new(0,3,0), "Triceratops hatched! \xF0\x9F\xA6\x95")
		pcall(function() egg:Destroy() end)
	end)
	print(("[Trike] island2 'Fern Frontier' Triceratops egg placed at (%.0f,%.0f,%.0f)"):format(center.X, center.Y, center.Z))
end)
