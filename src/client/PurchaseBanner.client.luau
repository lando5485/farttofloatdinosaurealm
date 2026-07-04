--======================================================================
-- PurchaseBanner.client.luau  (LocalScript)
--======================================================================
-- Shows a gold slide-in banner for EVERY player when anyone buys a gamepass or
-- developer product. The server broadcasts PurchaseAnnouncementEvent; this plays
-- the banner. Also: when THIS player finishes a dev-product purchase, it tells the
-- server so it can broadcast (dev products go through ProcessReceipt elsewhere).
--======================================================================
local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")
local MPS           = game:GetService("MarketplaceService")
local TweenService  = game:GetService("TweenService")
local Debris        = game:GetService("Debris")
local player        = Players.LocalPlayer
local PlayerGui     = player:WaitForChild("PlayerGui")

local PAE          = RS:WaitForChild("PurchaseAnnouncementEvent", 30)
local clientBought = RS:WaitForChild("ClientBoughtProduct", 30)

-- dev products this client should report on purchase-finished (server-wide banner)
local PRODUCT_IDS = { [3600302990]=true, [3600303163]=true, [3600303265]=true, [3606893853]=true }

-- ===== the banner (look + behavior verbatim from the spec) -- calls onDone after it dismisses =====
local function showPurchaseBanner(playerName, itemName, isGamepass, onDone)
	local g = Instance.new("ScreenGui"); g.Name = "PurchaseBanner"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 80; g.Parent = PlayerGui
	local b = Instance.new("Frame"); b.Size = UDim2.new(0,500,0,60); b.Position = UDim2.new(0.5,0,0,-70); b.AnchorPoint = Vector2.new(0.5,0)
	b.BackgroundColor3 = Color3.fromRGB(255,200,0); b.ZIndex = 20; b.Parent = g
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,12)
	local s = Instance.new("UIStroke", b); s.Color = Color3.fromRGB(200,150,0); s.Thickness = 3
	local icon = Instance.new("TextLabel"); icon.Size = UDim2.new(0,50,1,0); icon.Position = UDim2.new(0,8,0,0); icon.BackgroundTransparency = 1
	icon.Text = isGamepass and "\xe2\xad\x90" or "\xf0\x9f\x8e\x89"; icon.TextSize = 28; icon.Font = Enum.Font.Gotham; icon.ZIndex = 21; icon.Parent = b
	local l = Instance.new("TextLabel"); l.Size = UDim2.new(1,-60,1,0); l.Position = UDim2.new(0,55,0,0); l.BackgroundTransparency = 1
	l.Text = playerName .. " bought " .. itemName .. "!"; l.Font = Enum.Font.GothamBold; l.TextSize = 16; l.TextColor3 = Color3.fromRGB(80,40,0); l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 21; l.Parent = b
	TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5,0,0,10) }):Play()
	local snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://112825313814792"; snd.Volume = 0.8; snd.Parent = workspace; snd:Play(); Debris:AddItem(snd, 5)
	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.05)
			local c = Instance.new("Frame"); c.Size = UDim2.new(0, math.random(8,14), 0, math.random(8,14)); c.Position = UDim2.new(math.random(20,80)/100, 0, 0, math.random(-10,0))
			c.BackgroundColor3 = Color3.fromHSV(math.random(0,100)/100, 1, 1); c.BorderSizePixel = 0; c.ZIndex = 22; c.Rotation = math.random(0,360); c.Parent = g
			Instance.new("UICorner", c).CornerRadius = UDim.new(0,2)
			TweenService:Create(c, TweenInfo.new(2), { Position = UDim2.new(c.Position.X.Scale, 0, 1, 50), Rotation = math.random(360), BackgroundTransparency = 1 }):Play()
			Debris:AddItem(c, 2.1)
		end
	end)
	task.delay(4, function()
		TweenService:Create(b, TweenInfo.new(0.3), { Position = UDim2.new(0.5,0,0,-70) }):Play()
		task.wait(0.4); g:Destroy(); if onDone then onDone() end
	end)
end

-- queue so multiple purchases don't overlap (one banner at a time)
local queue, showing = {}, false
local function processQueue()
	if showing or #queue == 0 then return end
	showing = true
	local a = table.remove(queue, 1)
	showPurchaseBanner(a[1], a[2], a[3], function() showing = false; processQueue() end)
end
if PAE then
	PAE.OnClientEvent:Connect(function(playerName, itemName, isGamepass)
		queue[#queue + 1] = { playerName or "Someone", itemName or "an item", isGamepass }
		processQueue()
	end)
end

-- report THIS player's dev-product purchases so the server can broadcast the banner
MPS.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if isPurchased and userId == player.UserId and PRODUCT_IDS[productId] and clientBought then
		clientBought:FireServer(productId)
	end
end)

print("[PurchaseBanner] client ready -- server-wide purchase banners live")
