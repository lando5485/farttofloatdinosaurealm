--======================================================================
-- ShopGlue.client.luau  (LocalScript)
--======================================================================
-- Glue for the copied shop UI (Shop.client.luau) + wires the workspace "Shop"
-- part to open it. The shop UI is a verbatim copy that reads CoreClient globals;
-- this provides them, then flips _G.CoreClientReady so the shop unblocks.
-- (Per SHOP_SETUP.md.) The food/stomach economy + remotes live in Shop.server.luau.
--======================================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player    = Players.LocalPlayer

-- client-side mirror of the server foods/tiers (MUST match Shop.server.luau)
_G.foods = _G.foods or {
	{name="Eggs",price=5,power=8,island=1},             {name="Lettuce",price=24,power=25,island=2},
	{name="Bananas",price=85,power=45,island=3},        {name="Fish",price=94,power=70,island=4},
	{name="Ribs",price=142,power=100,island=5},         {name="Mushrooms",price=138,power=140,island=6},
	{name="Apples",price=202,power=185,island=7},       {name="Chicken",price=600,power=240,island=8},
	{name="Chili Peppers",price=500,power=300,island=9},{name="Potatoes",price=400,power=370,island=10},
	{name="Steak",price=560,power=450,island=11},       {name="Grapes",price=405,power=540,island=12},
	{name="Popcorn",price=700,power=640,island=13},     {name="Turkey Legs",price=518,power=750,island=14},
}
_G.stomachTiers = _G.stomachTiers or {
	{name="Hatchling Belly",maxPower=100,cost=0,robux=false},   {name="Raptor Gut",maxPower=182,cost=1600,robux=false},
	{name="Stego Stomach",maxPower=520,cost=3000,robux=false},{name="Bronto Belly",maxPower=1075,cost=5200,robux=false},
	{name="Rex Gut",maxPower=2146,cost=8000,robux=false}, {name="Fossil Gut",maxPower=3218,cost=11000,robux=false},
	{name="Primal Gut",maxPower=9999,cost=499,robux=true},
}
-- unlock all islands so every food is buyable from the one shop (gate later if you add islands)
_G.unlockedIslands = _G.unlockedIslands or {}
for i = 1, 14 do _G.unlockedIslands[i] = true end
_G.playerGamepasses = _G.playerGamepasses or { twoXForever = false, glitterTrail = false }

-- remotes + stats from the server (Shop.server.luau)
_G.BuyFoodEvent = RS:WaitForChild("BuyFoodEvent", 30)
_G.leaderstats  = player:WaitForChild("leaderstats", 30)

-- (do NOT create _G.MainMenuManager here -- Bootstrap / the shop UI create the real one)
_G.CoreClientReady = true   -- LAST: unblocks Shop.client.luau's `repeat wait until _G.CoreClientReady`
print("[ShopGlue] shop globals set; CoreClientReady = true")

-- ===== wire the workspace "Shop" part: a ProximityPrompt that opens the food shop =====
task.spawn(function()
	-- collect EVERY food stand: any part/model named "Shop" (island1) or "Stand" (island5/6)
	local function gather()
		local list = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d.Name == "Shop" or d.Name == "Stand" then
				local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
				if part then list[#list + 1] = part end
			end
		end
		return list
	end
	local stands
	for _ = 1, 60 do stands = gather(); if #stands > 0 then break end; task.wait(1) end
	if not stands or #stands == 0 then warn("[ShopGlue] no 'Shop'/'Stand' food stand found in Workspace"); return end

	-- distance from a point to the NEAREST SURFACE of a stand part (so big parts work, not just centre)
	local function surfaceDist(target, pos)
		local ok, d = pcall(function()
			local lp = target.CFrame:PointToObjectSpace(pos)
			local h = target.Size * 0.5
			local dx = math.max(0, math.abs(lp.X) - h.X)
			local dy = math.max(0, math.abs(lp.Y) - h.Y)
			local dz = math.max(0, math.abs(lp.Z) - h.Z)
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end)
		return ok and d or (pos - target.Position).Magnitude
	end
	local function nearestDist(pos) -- distance to the CLOSEST stand
		local best = math.huge
		for _, t in ipairs(stands) do if t and t.Parent then best = math.min(best, surfaceDist(t, pos)) end end
		return best
	end

	-- AUTO open/close by proximity to ANY stand: open within OPEN_DIST, close past CLOSE_DIST.
	local OPEN_DIST, CLOSE_DIST = 7.5, 8
	local manualClosed, wasOpen, tick = false, false, 0
	print(("[ShopGlue] %d food stand(s) wired (Shop/Stand) -> auto-open within %s studs, close past %s"):format(#stands, OPEN_DIST, CLOSE_DIST))
	while true do
		task.wait(0.15)
		tick += 1
		if tick % 20 == 0 then stands = gather() end -- re-scan periodically (catches stands that stream in late)
		local fg  = player.PlayerGui:FindFirstChild("FoodShopGui")
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if fg and hrp then
			local dist = nearestDist(hrp.Position)
			local open = fg.Enabled
			-- player X-closed it while still near -> don't auto-reopen until they walk away
			if wasOpen and not open and dist <= CLOSE_DIST then manualClosed = true end
			if dist > CLOSE_DIST then
				manualClosed = false
				if open then if _G.CloseFoodShop then _G.CloseFoodShop() else fg.Enabled = false end; open = false end
			elseif dist <= OPEN_DIST and not open and not manualClosed then
				local blocked = _G.MainMenuManager and _G.MainMenuManager.isOtherOpen and _G.MainMenuManager.isOtherOpen("FoodShop")
				if not blocked then if _G.OpenFoodShop then _G.OpenFoodShop(1) else fg.Enabled = true end; open = true end
			end
			wasOpen = open
		end
	end
end)
