--======================================================================
-- PurchaseBanner.server.luau  (server Script)
--======================================================================
-- Broadcasts a gold "[player] bought [item]!" banner to the WHOLE SERVER
-- whenever anyone buys a gamepass or a developer product.
--
--   * GAMEPASSES are server-authoritative: MarketplaceService.PromptGamePassPurchaseFinished
--     fires server-side -> we announce it.
--   * DEV PRODUCTS go through ProcessReceipt (owned elsewhere in the place), so the
--     BUYER's client reports the finished purchase to us (ClientBoughtProduct) and we
--     broadcast. If you DO own ProcessReceipt, call _G.announceProductPurchase(player, id)
--     inside it instead for a fully server-authoritative announce.
--======================================================================
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local MPS     = game:GetService("MarketplaceService")

local function ev(name)
	local e = RS:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = RS end
	return e
end
local PAE          = ev("PurchaseAnnouncementEvent") -- server -> all clients: (playerName, itemName, isGamepass)
local clientBought = ev("ClientBoughtProduct")       -- client -> server: (productId) buyer finished a dev product

-- name maps (your real IDs)
local PRODUCT_NAMES = {
	[3600302990] = "2x Power (1 Hour)",
	[3600303163] = "Mid-Air Recharge",
	[3600303265] = "Skip Island",
	[3606893853] = "Meteorite Explosion",
}
local GAMEPASS_NAMES = {
	[1862015450] = "2x Fart Power Forever",
	[1859714979] = "Glitter Fart Trail",
	[1860686821] = "Primal Gut",
}

local recentAnnounce = {} -- collapse duplicate announces (ProcessReceipt + client-report) within 3s
local function announce(name, item, isGamepass)
	local key = (name or "?") .. "|" .. (item or "?")
	local now = os.clock()
	if recentAnnounce[key] and now - recentAnnounce[key] < 3 then return end
	recentAnnounce[key] = now
	pcall(function() PAE:FireAllClients(name, item, isGamepass and true or false) end)
end
-- escape hatches usable from any other server script (e.g. your ProcessReceipt)
_G.announcePurchase = announce
_G.announceProductPurchase = function(plr, productId)
	if not plr then return end
	announce(plr.Name, PRODUCT_NAMES[productId] or ("a product"), false)
end
_G.announceGamepassPurchase = function(plr, passId)
	if not plr then return end
	announce(plr.Name, GAMEPASS_NAMES[passId] or ("a gamepass"), true)
end

-- GAMEPASSES: announce when a prompt finishes as purchased (server-side, authoritative)
MPS.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
	if wasPurchased then _G.announceGamepassPurchase(plr, passId) end
end)

-- DEV PRODUCTS: the buyer's client reports it (ProcessReceipt owned elsewhere). Cosmetic; light anti-spam.
local lastProd = {}
clientBought.OnServerEvent:Connect(function(plr, productId)
	productId = tonumber(productId)
	if not productId or not PRODUCT_NAMES[productId] then return end -- only known products
	local now = os.clock()
	if lastProd[plr] and now - lastProd[plr] < 2 then return end
	lastProd[plr] = now
	_G.announceProductPurchase(plr, productId)
end)
Players.PlayerRemoving:Connect(function(p) lastProd[p] = nil end)

print("[PurchaseBanner] server ready -- gamepass + dev-product purchases announce to the whole server")
