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
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local MPS        = game:GetService("MarketplaceService")
local Workspace  = game:GetService("Workspace")
local DSS        = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local PRODUCT  = { TwoXOneHour = 3600302990, MidAirRecharge = 3600303163, SkipIsland = 3600303265, MeteoriteExplosion = 3606893853 }
local GAMEPASS = { TwoXForever = 1862015450, GlitterTrail = 1859714979, PrimalGut = 1860686821 }
local MAX_ISLAND = 13   -- the tower is 13 slots; a 14th was tried and removed

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
		-- STUDIO-GATED for the same reason as PrimalGut below: the place owner counts as
		-- owning their own gamepasses, so this fired on every test join. With it set,
		-- Shop's BuyFood raises the effective tank to stomachMax * 1.4 -- which is why a
		-- "max 100" gut happily filled to 130. Live purchasers are unaffected.
		-- Toggle it deliberately while testing with /2x.
		if not RunService:IsStudio() then
			plr:SetAttribute("HasTwoXForever", true)
		end
	elseif passId == GAMEPASS.GlitterTrail then
		plr:SetAttribute("HasGlitterTrail", true)
	elseif passId == GAMEPASS.PrimalGut then
		-- WHY THIS IS STUDIO-GATED: in Studio the place owner counts as owning their own
		-- gamepasses, so UserOwnsGamePassAsync returns true and this fired on EVERY test
		-- join. That is not a hardcoded debug flag, it is the real Primal Gut grant.
		--
		-- HasPrimalGut IS THE ONE THAT STOPS THE METER. BottomHUD's flight loop reads it:
		--     if not player:GetAttribute("HasPrimalGut") then  gasMeter -= DRAIN_RATE*dt  end
		-- so the perk does not merely give a huge tank, it disables draining entirely --
		-- which is the "I fly forever" part. Both the attribute and the 9999 tank have to
		-- be withheld in Studio or the meter still never moves.
		--
		-- Live servers are untouched: a genuine purchaser gets both, as before.
		-- While testing, turn it on deliberately with the /infinitegut chat command.
		if not RunService:IsStudio() then
			plr:SetAttribute("HasPrimalGut", true)
			local ls = plr:FindFirstChild("leaderstats"); local sm = ls and ls:FindFirstChild("StomachMax")
			if sm and sm.Value < 9999 then sm.Value = 9999 end -- Primal Gut = max tank
		end
	end
end

-- ===== /infinitegut : DEV toggle for the max tank =====
-- StomachMax IS the record of which gut you own -- there is no separate tier field -- so
-- switching this on has to remember the real value first, or turning it off would leave
-- you permanently back on the starter belly.
local INFINITE_MAX = 9999
local function setInfiniteGut(plr, on)
	local ls = plr:FindFirstChild("leaderstats"); if not ls then return end
	local sm = ls:FindFirstChild("StomachMax"); if not sm then return end
	local cp = ls:FindFirstChild("CurrentPower")

	if on then
		if sm.Value < INFINITE_MAX then plr:SetAttribute("GutMaxBeforeInfinite", sm.Value) end
		sm.Value = INFINITE_MAX
		if cp then cp.Value = INFINITE_MAX end
	else
		local restored = tonumber(plr:GetAttribute("GutMaxBeforeInfinite")) or 120 -- 120 = Hatchling Belly (StomachTiers.LIST[1])
		sm.Value = restored
		if cp then cp.Value = math.min(cp.Value, restored) end
	end
	plr:SetAttribute("InfiniteGut", on or nil)
	-- THE ONE THAT ACTUALLY STOPS THE METER: BottomHUD skips the drain entirely while
	-- this is set, so the toggle has to move it too or /infinitegut off would still fly forever.
	plr:SetAttribute("HasPrimalGut", on or nil)

	-- Push it to the HUD the same way a real gut purchase does, or the meter keeps
	-- showing the old tank until something else happens to refresh it.
	local su = RS:FindFirstChild("StomachUpdateEvent")
	if su then pcall(function() su:FireClient(plr, sm.Value, on and "Infinite Gut (dev)" or "Gut") end) end
	local re = RS:FindFirstChild("RegenEvent")
	if re and cp then pcall(function() re:FireClient(plr, 0, cp.Value, sm.Value) end) end

	print(("[/infinitegut] %s -> %s  (StomachMax = %d)"):format(plr.Name, on and "ON" or "OFF", sm.Value))
end

-- ===== /2x : DEV toggle for the 2x Fart Power pass =====
-- Worth knowing what this actually does: with it on, Shop's BuyFood raises the effective
-- tank to stomachMax * 1.4, so a 100 gut legitimately fills to 140. The HUD still prints
-- the RAW StomachMax as the denominator, which is why it reads "130/100" and looks broken.
local function setTwoX(plr, on)
	plr:SetAttribute("HasTwoXForever", on or nil)
	print(("[/2x] %s -> %s"):format(plr.Name, on and "ON (tank x1.4)" or "OFF"))
end

local function hookDevChat(plr)
	plr.Chatted:Connect(function(msg)
		local cmd = string.gsub(string.lower(msg), "%s", "")
		if cmd == "/infinitegut" then
			setInfiniteGut(plr, not plr:GetAttribute("InfiniteGut"))
		elseif cmd == "/2x" then
			setTwoX(plr, not plr:GetAttribute("HasTwoXForever"))
		end
	end)
end
local hookInfiniteGutChat = hookDevChat
Players.PlayerAdded:Connect(hookInfiniteGutChat)
for _, p in ipairs(Players:GetPlayers()) do hookInfiniteGutChat(p) end
local function applyOwnedGamepasses(plr)
	for _, id in pairs(GAMEPASS) do
		local ok, owns = pcall(function() return MPS:UserOwnsGamePassAsync(plr.UserId, id) end)
		if ok and owns then grantGamepass(plr, id) end
	end
end

-- ===== dev products: ProcessReceipt (authoritative + DataStore dedup) =====
local receiptStore = nil
pcall(function() receiptStore = DSS:GetDataStore("PurchaseReceipts_v1") end)

-- Returns TRUE only when something actually granted the product. An unrecognised product used to fall
-- through here, get marked PurchaseGranted and written to the dedup store -- the Robux were taken, nothing
-- was given, and the receipt could never be retried. Now it is left NotProcessedYet so Roblox retries it.
local function handleProduct(plr, productId)
	local handled = true
	if productId == PRODUCT.TwoXOneHour then
		-- Through UniverseBoosts: stacks on any time already running, persists to the universe store, and
		-- rides the teleport payload, so the hour keeps its remaining minutes across rejoins and realms.
		if _G.boostsExtend then
			_G.boostsExtend(plr, "twoXHourExpiry", 3600)
		else -- boost service not up (should not happen): fall back to the old attribute-only grant
			local expiry = os.time() + 3600
			plr:SetAttribute("TwoXHourExpiry", expiry)
			local ge = RS:FindFirstChild("GamepassEvent"); if ge then pcall(function() ge:FireClient(plr, { twoXHourExpiry = expiry }) end) end
		end
	elseif productId == PRODUCT.MidAirRecharge then
		triggerMidAirRecharge(plr)
	elseif productId == PRODUCT.SkipIsland then
		triggerSkipIsland(plr)
	elseif productId == PRODUCT.MeteoriteExplosion then
		if _G.triggerMeteorStorm then _G.triggerMeteorStorm(plr) end
	elseif _G.skinCrateHandleReceipt and _G.skinCrateHandleReceipt(plr, productId) then
		-- a crate-token pack: SkinCrateService credited the universe wallet and saved
	else
		handled = false
	end
	if handled and _G.announceProductPurchase then pcall(_G.announceProductPurchase, plr, productId) end -- buy banner
	return handled
end

MPS.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local key = info.PlayerId .. "_" .. info.PurchaseId
	if receiptStore then
		local ok, already = pcall(function() return receiptStore:GetAsync(key) end)
		if ok and already then return Enum.ProductPurchaseDecision.PurchaseGranted end -- already granted
	end
	local okCall, granted = pcall(function() return handleProduct(plr, info.ProductId) end)
	if not okCall then warn("[PurchaseReceipts] handler errored for product " .. tostring(info.ProductId) .. ": " .. tostring(granted)) end
	if okCall and granted then
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
