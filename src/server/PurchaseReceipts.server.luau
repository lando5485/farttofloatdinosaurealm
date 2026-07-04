--======================================================================
-- PurchaseReceipts.server.luau  (server Script)
--======================================================================
-- Server-authoritative grants for the buyable PERKS:
--   DEV PRODUCTS (via MarketplaceService.ProcessReceipt, with DataStore dedup):
--     * 2x Power (1 Hour)  -> sets TwoXHourExpiry (Shop's BuyFood applies 1.4x power + tank)
--     * Mid-Air Recharge   -> refills CurrentPower to StomachMax (meter -> 100%, even mid-flight)
--     * Skip Island        -> bumps HighestIsland + teleports onto the next island
--     * Meteorite Explosion-> triggers the server-wide meteor storm
--   GAMEPASSES (PromptGamePassPurchaseFinished + UserOwnsGamePassAsync on join):
--     * 2x Fart Power Forever -> HasTwoXForever (permanent 1.4x via Shop's BuyFood)
--     * Glitter Fart Trail    -> HasGlitterTrail
--     * Primal Gut            -> StomachMax = 9999 (max tank)
--
-- NOTE: only ONE script may own ProcessReceipt. If your place already has another
-- ProcessReceipt handler, MERGE this into it instead of running both.
--======================================================================
local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local MPS       = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")
local DSS       = game:GetService("DataStoreService")

local PRODUCT  = { TwoXOneHour = 3600302990, MidAirRecharge = 3600303163, SkipIsland = 3600303265, MeteoriteExplosion = 3606893853 }
local GAMEPASS = { TwoXForever = 1862015450, GlitterTrail = 1859714979, PrimalGut = 1860686821 }
local MAX_ISLAND = 14

-- ===== perk effects =====
local function triggerMidAirRecharge(plr)
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	local cp, sm = ls:FindFirstChild("CurrentPower"), ls:FindFirstChild("StomachMax")
	if cp and sm then cp.Value = sm.Value end -- meter -> 100%; the client adopts the increase (refills mid-flight)
	plr:SetAttribute("MidAirRechargeCount", (plr:GetAttribute("MidAirRechargeCount") or 0) + 1)
end

local function islandTop(n)
	local isl = Workspace:FindFirstChild("island" .. n); if not isl then return nil end
	local ok, cf, size = pcall(function() return isl:GetBoundingBox() end); if not ok or not cf then return nil end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local excl = {}; for _, p in ipairs(Players:GetPlayers()) do if p.Character then excl[#excl+1] = p.Character end end
	rp.FilterDescendantsInstances = excl
	local topY = cf.Position.Y + size.Y/2
	local hit = Workspace:Raycast(Vector3.new(cf.Position.X, topY + 80, cf.Position.Z), Vector3.new(0, -500, 0), rp)
	return Vector3.new(cf.Position.X, (hit and hit.Position.Y or topY) + 5, cf.Position.Z)
end

local function triggerSkipIsland(plr)
	local cur = math.floor(tonumber(plr:GetAttribute("HighestIsland")) or 1)
	if cur >= MAX_ISLAND then return end
	local target = cur + 1
	plr:SetAttribute("HighestIsland", target)
	local ls = plr:FindFirstChild("leaderstats"); local isl = ls and ls:FindFirstChild("Island")
	if isl and isl.Value < target then isl.Value = target end
	local pos = islandTop(target); local ch = plr.Character
	if pos and ch then pcall(function() ch:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0))) end) end
end

-- ===== gamepass grants =====
local function grantGamepass(plr, passId)
	if passId == GAMEPASS.TwoXForever then
		plr:SetAttribute("HasTwoXForever", true)
	elseif passId == GAMEPASS.GlitterTrail then
		plr:SetAttribute("HasGlitterTrail", true)
	elseif passId == GAMEPASS.PrimalGut then
		plr:SetAttribute("HasPrimalGut", true)
		local ls = plr:FindFirstChild("leaderstats"); local sm = ls and ls:FindFirstChild("StomachMax")
		if sm and sm.Value < 9999 then sm.Value = 9999 end -- Primal Gut = max tank
	end
end
local function applyOwnedGamepasses(plr)
	for _, id in pairs(GAMEPASS) do
		local ok, owns = pcall(function() return MPS:UserOwnsGamePassAsync(plr.UserId, id) end)
		if ok and owns then grantGamepass(plr, id) end
	end
end

-- ===== dev products: ProcessReceipt (authoritative + DataStore dedup) =====
local receiptStore = nil
pcall(function() receiptStore = DSS:GetDataStore("PurchaseReceipts_v1") end)

local function handleProduct(plr, productId)
	if productId == PRODUCT.TwoXOneHour then
		local expiry = os.time() + 3600
		plr:SetAttribute("TwoXHourExpiry", expiry)
		local ge = RS:FindFirstChild("GamepassEvent"); if ge then pcall(function() ge:FireClient(plr, { twoXHourExpiry = expiry }) end) end
	elseif productId == PRODUCT.MidAirRecharge then
		triggerMidAirRecharge(plr)
	elseif productId == PRODUCT.SkipIsland then
		triggerSkipIsland(plr)
	elseif productId == PRODUCT.MeteoriteExplosion then
		if _G.triggerMeteorStorm then _G.triggerMeteorStorm(plr) end
	end
	if _G.announceProductPurchase then _G.announceProductPurchase(plr, productId) end -- buy banner
end

MPS.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local key = info.PlayerId .. "_" .. info.PurchaseId
	if receiptStore then
		local ok, already = pcall(function() return receiptStore:GetAsync(key) end)
		if ok and already then return Enum.ProductPurchaseDecision.PurchaseGranted end -- already granted
	end
	local granted = pcall(function() handleProduct(plr, info.ProductId) end)
	if granted then
		if receiptStore then pcall(function() receiptStore:SetAsync(key, true) end) end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- retry later
end

-- ===== gamepasses: grant on purchase + on join =====
MPS.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
	if wasPurchased then grantGamepass(plr, passId) end -- banner is handled by PurchaseBanner.server
end)
Players.PlayerAdded:Connect(function(p) task.spawn(function() task.wait(1); applyOwnedGamepasses(p) end) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(applyOwnedGamepasses, p) end

print("[PurchaseReceipts] perks ready -- 2x (pass+1hr), Mid-Air Recharge, Skip Island, Meteorite, Primal Gut / Glitter passes")
