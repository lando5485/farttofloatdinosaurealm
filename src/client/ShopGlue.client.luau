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

-- THE SHARED TABLES, not a mirror. These were hand-copied "client-side mirrors of the
-- server foods/tiers", and both had gone stale: the food stand quoted Eggs at 16 while the
-- server charged 21 and Steak at 150 against 185, and the gut list still held the six OLD
-- tiers at the OLD server prices (112/140/202/270/336) -- the very numbers whose mismatch
-- made every gut silently unbuyable in the first place.
--
-- A copy could not have stayed in sync either, because Shop.server's `_G.foods` is on the
-- SERVER's globals and never reaches the client; whatever is written here is simply what
-- the client believes. So it reads the modules the server reads.
local RSD = RS:WaitForChild("DinosaurRealm")
_G.foods        = _G.foods        or require(RSD:WaitForChild("FoodMenu")).LIST
_G.stomachTiers = _G.stomachTiers or require(RSD:WaitForChild("StomachTiers")).LIST
-- ===== WHICH FOODS ARE UNLOCKED =====
-- A food unlocks when you have REACHED its island, so island 1's stand shows Eggs
-- buyable and the other twelve greyed with a lock; once you land on the second
-- island in the climb, its food joins them, and so on.
--
-- Gated on HighestSlot (the CLIMB position), NOT HighestIsland (the model number).
-- The tower scrambles model numbers against climb order -- SLOT_TO_ISLAND is
-- {1,9,5,12,3,13,4,2,10,7,6,8,11} -- so the second island you reach is island9,
-- and gating on the raw model number would unlock islands 2..9 all at once.
-- (This used to be `for i = 1, 13 do unlockedIslands[i] = true end`, i.e. nothing
-- was ever locked and every stand sold the whole menu from the start.)
local IslandOrder = require(RSD:WaitForChild("IslandOrder"))
_G.unlockedIslands = _G.unlockedIslands or {}
local function refreshUnlocks()
	local reached = math.clamp(math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1), 1, IslandOrder.COUNT)
	table.clear(_G.unlockedIslands)          -- rebuild, so a rebirth re-locks them
	for slot = 1, reached do
		_G.unlockedIslands[IslandOrder.SLOT_TO_ISLAND[slot]] = true
	end
end
refreshUnlocks()
player:GetAttributeChangedSignal("HighestSlot"):Connect(refreshUnlocks)
_G.playerGamepasses = _G.playerGamepasses or { twoXForever = false, glitterTrail = false }

-- remotes + stats from the server (Shop.server.luau)
_G.BuyFoodEvent = RS:WaitForChild("BuyFoodEvent", 30)
_G.leaderstats  = player:WaitForChild("leaderstats", 30)

-- ===== WHY A BUY WAS REFUSED =====
-- The server fires StomachFullEvent with a reason on every rejected purchase, and
-- NOTHING was listening -- a refused buy just silently did nothing, which reads as
-- a broken button. Show a short toast instead.
task.spawn(function()
	local ev = RS:FindFirstChild("StomachFullEvent") or RS:WaitForChild("StomachFullEvent", 30)
	if not ev then return end
	-- not_enough_coins is DELIBERATELY ABSENT -- see the early-out in the handler.
	local REASONS = {
		stomach_full     = "Your gut is full!",
		not_enough_room  = "Not enough room for that",
		food_locked      = "Locked - reach that island first",
		gut_locked       = "Locked - reach that island first",
	}
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuyToast"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200; gui.Enabled = false; gui.Parent = player:WaitForChild("PlayerGui")
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(330, 46); box.Position = UDim2.new(0.5, 0, 0.22, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5); box.BackgroundColor3 = Color3.fromRGB(48, 30, 16)
	box.BackgroundTransparency = 0.08; box.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = box
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(224, 168, 74); st.Thickness = 2; st.Parent = box
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -20, 1, -10); lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.AnchorPoint = Vector2.new(0.5, 0.5); lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 240, 214); lbl.Parent = box
	do local sc = Instance.new("UITextSizeConstraint"); sc.MaxTextSize = 20; sc.Parent = lbl end

	local token = 0
	ev.OnClientEvent:Connect(function(reason)
		-- BEING BROKE IS NOT AN ERROR, it is the normal state between flights, and the
		-- shop already says so: the BUY button greys out and reads "Not Enough Coins"
		-- right where you are looking. A centre-screen toast on top of that fires on
		-- every click of an unaffordable item and just covers the game up.
		-- The other three reasons are genuine surprises, so they still toast.
		if reason == "not_enough_coins" then return end
		lbl.Text = REASONS[reason] or "Cannot buy that right now"
		gui.Enabled = true
		token += 1
		local mine = token
		task.delay(2, function() if token == mine then gui.Enabled = false end end)
	end)
end)

-- (do NOT create _G.MainMenuManager here -- Bootstrap / the shop UI create the real one)
_G.CoreClientReady = true   -- LAST: unblocks Shop.client.luau's `repeat wait until _G.CoreClientReady`
print("[ShopGlue] shop globals set; CoreClientReady = true")

-- ===== wire the workspace "Shop"/"Stand" parts: walk up to one and the food shop opens =====
task.spawn(function()
	--------------------------------------------------------------------
	-- WHICH ISLAND DOES THIS STAND BELONG TO?
	--------------------------------------------------------------------
	-- This is the whole point: every stand must sell ITS OWN island's food.
	-- _G.foods is keyed by island number (island1 = Eggs, island5 = Ribs, ...) and
	-- _G.OpenFoodShop(n) already features _G.foods[n] and titles the panel
	-- "ISLAND n FOOD STAND" -- it just has to be told the right n.
	--
	-- (It used to be hardcoded: every stand on every island called OpenFoodShop(1),
	--  so they all sold island1's Eggs and all said "ISLAND 1 FOOD STAND".)
	--
	-- Resolution order, most explicit first:
	--   1. a number in the stand's own name  -> "Stand5", "Shop9"
	--   2. the island model it lives under   -> Workspace.island6.…Stand
	--   3. nearest island by distance        -> last resort for a stand parented loose
	local function islandFromName(name)
		local n = tonumber(name:match("(%d+)$"))
		if n and n >= 1 and n <= 13 then return n, ("its name '%s'"):format(name) end
		return nil
	end
	local function islandFromAncestor(inst)
		local a = inst.Parent
		while a and a ~= Workspace do
			local n = tonumber(tostring(a.Name):match("^island(%d+)$"))
			if n then return n, ("its parent island model '%s'"):format(a.Name) end
			a = a.Parent
		end
		return nil
	end
	local function islandFromPosition(part)
		local best, bestD = nil, math.huge
		for i = 1, 13 do
			local isl = Workspace:FindFirstChild("island" .. i)
			if isl then
				local ok, cf = pcall(function() return isl:GetBoundingBox() end)
				if ok and cf then
					local d = (part.Position - cf.Position).Magnitude
					if d < bestD then bestD, best = d, i end
				end
			end
		end
		if best then return best, "the nearest island by distance" end
		return nil
	end

	-- collect EVERY food stand, each tagged with the island whose food it sells
	local function gather()
		local list = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			-- match "Shop"/"Stand" case-insensitively, with an optional number suffix
			-- ("Stand", "stand", "Stand8", "Shop9", ...) so every island's stand registers.
			local nm = d.Name:lower()
			if nm:match("^shop%d*$") or nm:match("^stand%d*$") then
				local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local island, why = islandFromName(d.Name)
					if not island then island, why = islandFromAncestor(d) end
					if not island then island, why = islandFromPosition(part) end
					list[#list + 1] = { part = part, island = island or 1, why = why or "fallback (island 1)" , name = d.Name }
				end
			end
		end
		return list
	end
	local stands
	for _ = 1, 60 do stands = gather(); if #stands > 0 then break end; task.wait(1) end
	if not stands or #stands == 0 then warn("[ShopGlue] no 'Shop'/'Stand' food stand found in Workspace"); return end

	--------------------------------------------------------------------
	-- COVERAGE REPORT: which islands have a food stand, and which don't.
	--------------------------------------------------------------------
	-- NOTE this only counts stands that have STREAMED IN to this client. Far islands
	-- report as missing until the player gets near them, so the "MISSING" list at spawn
	-- is a worst case. The re-scan below (every ~3s) picks stands up as they arrive, and
	-- this report re-prints whenever the set changes.
	local ISLAND_NAMES = {
		[1]="Nesting Nook", [2]="Fern Frontier", [3]="Fossil Frontier", [4]="Coastal Crossing",
		[5]="Misty Mire", [6]="Redwood Ridge", [7]="Raptor Ridge", [8]="Inferno Isle",
		[9]="Jungle Junction", [10]="Petrified Pass", [11]="Volcanic Vista",
		[12]="Sunscorch Sands", [13]="Glacier Gulch",
	}
	local lastReport
	local function report(list)
		local have = {}
		for _, s in ipairs(list) do have[s.island] = s end
		local key = ""
		for i = 1, 13 do key = key .. (have[i] and "1" or "0") end
		if key == lastReport then return end -- only re-print when the picture changes
		lastReport = key

		print("[ShopGlue] ---- FOOD STAND COVERAGE ----")
		local missing = {}
		for i = 1, 13 do
			local food; for _, ff in ipairs(_G.foods) do if ff.island == i then food = ff; break end end
			local s = have[i]
			if s then
				print(("[ShopGlue]   island %-2d  %-17s  HAS stand '%s' (%s)  -> sells %s")
					:format(i, ISLAND_NAMES[i] or "?", s.name, s.why, food and food.name or "??"))
			else
				missing[#missing + 1] = i
				print(("[ShopGlue]   island %-2d  %-17s  ** NO STAND **                      -> should sell %s")
					:format(i, ISLAND_NAMES[i] or "?", food and food.name or "??"))
			end
		end
		if #missing > 0 then
			warn(("[ShopGlue] islands with NO food stand yet: %s  -- add a part/model named "
				.. "'Stand' (or 'Stand<N>') to each. Any island model it sits under sets its number automatically.")
				:format(table.concat(missing, ", ")))
		else
			print("[ShopGlue] every island 1-13 has a food stand.")
		end
	end
	report(stands)

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
	-- distance to the CLOSEST stand, AND which island that stand belongs to
	local function nearest(pos)
		local bestD, bestIsland = math.huge, 1
		for _, s in ipairs(stands) do
			if s.part and s.part.Parent then
				local d = surfaceDist(s.part, pos)
				if d < bestD then bestD, bestIsland = d, s.island end
			end
		end
		return bestD, bestIsland
	end

	-- AUTO open/close by proximity to ANY stand: open within OPEN_DIST, close past CLOSE_DIST.
	local OPEN_DIST, CLOSE_DIST = 7.5, 8
	local manualClosed, wasOpen, tick = false, false, 0
	print(("[ShopGlue] %d food stand(s) wired (Shop/Stand) -> auto-open within %s studs, close past %s"):format(#stands, OPEN_DIST, CLOSE_DIST))
	while true do
		task.wait(0.15)
		tick += 1
		if tick % 20 == 0 then
			stands = gather() -- re-scan periodically (catches stands that stream in late)
			report(stands)    -- re-print coverage only if the set actually changed
		end
		local fg  = player.PlayerGui:FindFirstChild("FoodShopGui")
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if fg and hrp then
			local dist, island = nearest(hrp.Position)
			local open = fg.Enabled
			-- player X-closed it while still near -> don't auto-reopen until they walk away
			if wasOpen and not open and dist <= CLOSE_DIST then manualClosed = true end
			if dist > CLOSE_DIST then
				manualClosed = false
				if open then if _G.CloseFoodShop then _G.CloseFoodShop() else fg.Enabled = false end; open = false end
			elseif dist <= OPEN_DIST and not open and not manualClosed then
				local blocked = _G.MainMenuManager and _G.MainMenuManager.isOtherOpen and _G.MainMenuManager.isOtherOpen("FoodShop")
				if not blocked then
					-- open with the island of the stand you are ACTUALLY standing at, so it
					-- features that island's food and titles itself correctly. Passing a
					-- hardcoded 1 here is what made every stand sell island1's Eggs.
					if _G.OpenFoodShop then _G.OpenFoodShop(island) else fg.Enabled = true end
					open = true
				end
			end
			wasOpen = open
		end
	end
end)
