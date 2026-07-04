--======================================================================
-- MeteoriteExplosion.client.luau  (LocalScript)
--======================================================================
-- Fires the server when THIS player finishes buying the Meteorite Explosion
-- product (id 3606893853) -> server rains meteors on everyone. Also plays a
-- camera shake + red vignette on every client while the storm is happening.
--======================================================================
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local MPS        = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer

local METEOR_PRODUCT = 3606893853
local triggerEvent = RS:WaitForChild("MeteoriteExplosionEvent", 30)
local shakeEvent   = RS:WaitForChild("MeteoriteShakeEvent", 30)

-- when this player completes the purchase -> tell the server to unleash the storm
MPS.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if isPurchased and productId == METEOR_PRODUCT and userId == player.UserId and triggerEvent then
		triggerEvent:FireServer()
	end
end)

-- camera shake + red vignette for the duration of the storm (all clients)
local shaking = false
if shakeEvent then
	shakeEvent.OnClientEvent:Connect(function(duration)
		if shaking then return end
		shaking = true
		duration = tonumber(duration) or 6
		local pgui = player:WaitForChild("PlayerGui")
		local gui = Instance.new("ScreenGui"); gui.Name = "MeteorVignette"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 60; gui.Parent = pgui
		local red = Instance.new("Frame"); red.Size = UDim2.fromScale(1,1); red.BackgroundColor3 = Color3.fromRGB(180,40,20); red.BackgroundTransparency = 0.8; red.BorderSizePixel = 0; red.Active = false; red.Parent = gui
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(Color3.fromRGB(120,20,10), Color3.fromRGB(40,10,5)); g.Parent = red
		local t0 = os.clock()
		RunService:BindToRenderStep("MeteorShake", Enum.RenderPriority.Camera.Value + 10, function()
			local el = os.clock() - t0
			local cam = workspace.CurrentCamera
			if el > duration or not cam then
				RunService:UnbindFromRenderStep("MeteorShake")
				pcall(function() gui:Destroy() end)
				shaking = false
				return
			end
			local mag = 0.8 * (1 - el / duration) -- shake eases out
			cam.CFrame = cam.CFrame * CFrame.Angles(
				math.rad((math.random() - 0.5) * mag * 3),
				math.rad((math.random() - 0.5) * mag * 3),
				math.rad((math.random() - 0.5) * mag))
			red.BackgroundTransparency = 0.78 + 0.14 * math.sin(el * 14)
		end)
	end)
end

print("[Meteorite] client ready -- buying Meteorite Explosion unleashes a server-wide meteor storm")
