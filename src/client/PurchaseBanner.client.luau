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

-- ONE BANNER SYSTEM. Every announcement in this realm goes through NotifyCenter's hero card (the
-- module beside this script) -- no private ScreenGui, no private slot table, no private Y.
local Notify = require(script.Parent:WaitForChild("NotifyCenter"))

-- The gold card, the jingle and the confetti are all still here; the CARD is NotifyCenter's hero card at
-- PURCHASE priority (real money is never swallowed: it plays over any event countdown and queues behind
-- nothing but an arrival). The confetti and the jingle fire from the spec's `sound` hook, which the centre
-- calls the moment the card actually slides in -- so they land with the banner, not before it.
local GOLD = Color3.fromRGB(255, 200, 0)
local function celebrate()
	local snd = Instance.new("Sound"); snd.SoundId = "rbxassetid://112825313814792"; snd.Volume = 0.8; snd.Parent = workspace; snd:Play(); Debris:AddItem(snd, 5)
	local g = Instance.new("ScreenGui"); g.Name = "PurchaseConfetti"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 80; g.Parent = PlayerGui
	Debris:AddItem(g, 4)
	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.05)
			if not g.Parent then return end
			local c = Instance.new("Frame"); c.Size = UDim2.new(0, math.random(8,14), 0, math.random(8,14)); c.Position = UDim2.new(math.random(20,80)/100, 0, 0, math.random(-10,0))
			c.BackgroundColor3 = Color3.fromHSV(math.random(0,100)/100, 1, 1); c.BorderSizePixel = 0; c.ZIndex = 22; c.Rotation = math.random(0,360); c.Parent = g
			Instance.new("UICorner", c).CornerRadius = UDim.new(0,2)
			TweenService:Create(c, TweenInfo.new(2), { Position = UDim2.new(c.Position.X.Scale, 0, 1, 50), Rotation = math.random(360), BackgroundTransparency = 1 }):Play()
			Debris:AddItem(c, 2.1)
		end
	end)
end
local function showPurchaseBanner(playerName, itemName, isGamepass)
	Notify.push({
		top      = isGamepass and "\xE2\xAD\x90 GAMEPASS" or "\xF0\x9F\x8E\x89 PURCHASE",
		text     = playerName .. " bought " .. itemName .. "!",
		color    = GOLD,
		priority = Notify.PRIORITY.PURCHASE,
		duration = 4,
		sound    = celebrate,
	})
end
if PAE then
	PAE.OnClientEvent:Connect(function(playerName, itemName, isGamepass)
		showPurchaseBanner(playerName or "Someone", itemName or "an item", isGamepass)
	end)
end

-- report THIS player's dev-product purchases so the server can broadcast the banner
MPS.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if isPurchased and userId == player.UserId and PRODUCT_IDS[productId] and clientBought then
		clientBought:FireServer(productId)
	end
end)

print("[PurchaseBanner] client ready -- server-wide purchase banners live")
