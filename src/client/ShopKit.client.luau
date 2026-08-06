--======================================================================
-- ShopKit.client.luau   (LocalScript -> StarterPlayerScripts.DinosaurRealmClient)
--======================================================================
-- THE 🛒 SHOP PANEL. Fart to Float's main-game shop UI (PremiumShopGui), brought over whole:
-- the 770x572 blue card, the gold section headers, six per-card gradients, the price capsules
-- and pill BUY buttons, the shine sweeps, the ✓ OWNED state and the footer mascot.
--
-- WHAT IT REPLACED. This realm had TWO ScreenGuis called "PremiumShopGui" -- one built in
-- Shop.client.luau, another in Bootstrap.client.luau -- so PlayerGui held two shop panels and the
-- SHOP button opened whichever FindFirstChild returned first. Both builders are gone; this is the
-- only one now. The rail button itself was NOT replaced: Bootstrap still owns the green SHOP
-- button and still calls toggleMainMenu("Premium", "PremiumShopGui"), which resolves the panel by
-- name at click time -- hence CONFIG.buildShopButton = false below.
--
-- ┌─ WHAT IS REALM-SPECIFIC HERE ─────────────────────────────────────────────────┐
-- │ * The ids below are THIS PLACE's ids, carried over from the shop this          │
-- │   replaced -- they are NOT the kit's defaults. Card 6 is the Meteorite         │
-- │   Explosion (a dino-realm product with real server code in                     │
-- │   MeteoriteExplosion.server.luau), where the kit shipped Fart to Float's       │
-- │   Bird Nuke.                                                                   │
-- │ * showCoinBanner = false: this realm sells no coin packs, and the kit's coin   │
-- │   shop ships with productId = 0 on every pack, so the banner would open a      │
-- │   window whose six buttons all report "needs ids". Flip it back on the day     │
-- │   coin products exist (and add a ProcessReceipt branch per id).                │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- Grants are the SERVER's job and are unchanged: PurchaseReceipts.server.luau handles
-- ProcessReceipt for the four products and PromptGamePassPurchaseFinished for the passes.
-- This panel only PROMPTS.
--======================================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local MarketplaceService= game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local MPS       = MarketplaceService
local TS        = TweenService

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	realmName = "Dinosaur Realm",          -- footer: "⭐ Thanks for supporting <realmName>!"

	-- ===== IDS: copied from the shop this replaced. They MUST keep matching the server. =====
	-- PurchaseReceipts.server.luau grants off exactly these numbers; change one here without
	-- changing it there and the prompt succeeds, the Robux is taken, and nothing is granted.
	gamepassIds = {
		TwoXForever  = 1862015450,          -- 249 R$  permanent 2x power
		GlitterTrail = 1859714979,          --  49 R$  permanent sparkle trail
		PrimalGut    = 1860686821,          -- (sold from the STOMACH menu, not this panel -- reference only)
	},
	productIds = {
		TwoXOneHour        = 3600302990,    -- 59 R$  2x power for 1 hour
		MidAirRecharge     = 3600303163,    -- 39 R$  refill gas to 100% mid-flight
		SkipIsland         = 3600303265,    -- 69 R$  jump to the next island
		MeteoriteExplosion = 3606893853,    -- 79 R$  rain meteorites server-wide (this realm's card 6)
	},

	uiClickSound = "rbxassetid://101638558691673", -- volume 0.5
	beanImage    = "rbxassetid://133231198126712", -- footer / banner mascot (always renders; 🫘 does not)

	buildShopButton = false,                -- Bootstrap's SidebarGui already owns the green SHOP button
	shopButtonY     = 96,                   -- (unused while buildShopButton = false)
	showCoinBanner  = false,                -- no coin packs in this realm -- see the header note

	-- The 6 cards, in order. Row 1 = gamepasses, row 2 = one-time items.
	items = {
		twoXForever = { icon="\xe2\x9a\xa1",                 title="2x Power",    sub="FOREVER",    subCol=Color3.fromRGB(100,220,100), price="249 R$", btnCol=Color3.fromRGB(255,180,0)  },
		glitterTrail= { icon="\xe2\x9c\xa8",                 title="Glitter Trail",sub="PERMANENT", subCol=Color3.fromRGB(100,220,100), price="49 R$",  btnCol=Color3.fromRGB(220,80,180) },
		twoXHour    = { icon="\xe2\x8f\xb0",                 title="2x Power",    sub="1 HOUR",     subCol=Color3.fromRGB(255,200,100), price="59 R$",  btnCol=Color3.fromRGB(120, 196, 96) },
		midAir      = { icon="\xF0\x9F\x94\x8B",             title="Mid-Air",     sub="RECHARGE",   subCol=Color3.fromRGB(100,220,100), price="39 R$",  btnCol=Color3.fromRGB(50,200,50),  desc="Refills gas to 100%!" },
		skipIsland  = { icon="\xF0\x9F\x8F\x9D\xEF\xB8\x8F", title="Skip Island", sub="ONE USE",    subCol=Color3.fromRGB(255,200,100), price="69 R$",  btnCol=Color3.fromRGB(255,140,0),  desc="Jump to next island!" },
		-- card 6 is this realm's own product, not the kit's Bird Nuke: the same icon, title, colour
		-- and blurb the old panel used, so nothing about the offer changed except the frame it sits in
		meteorite   = { icon="\xE2\x98\x84\xEF\xB8\x8F",     title="Meteorite Explosion", sub="CHAOS MODE", subCol=Color3.fromRGB(255,140,80), price="79 R$", btnCol=Color3.fromRGB(232,108,40), desc="Rain meteorites down on everyone!" },
	},

	-- COIN SHOP packs. productId = 0 -> the button shows a "needs ids" banner instead of prompting.
	-- Add a server ProcessReceipt branch per id to actually grant the coins.
	coinPacks = {
		{ name="Small Coin Pack",    beans="1,000",   bonus=nil,    price="49 R$",   productId=0, col=Color3.fromRGB(86, 170, 78) },
		{ name="Medium Coin Pack",   beans="5,500",   bonus="+10%", price="99 R$",   productId=0, col=Color3.fromRGB(72,200,120), tag="\xF0\x9F\x94\xA5 MOST POPULAR" },
		{ name="Large Coin Pack",    beans="12,000",  bonus="+20%", price="199 R$",  productId=0, col=Color3.fromRGB(150,96,240) },
		{ name="Giant Coin Pack",    beans="30,000",  bonus="+30%", price="399 R$",  productId=0, col=Color3.fromRGB(64,200,224) },
		{ name="Mega Coin Pack",     beans="70,000",  bonus="+40%", price="799 R$",  productId=0, col=Color3.fromRGB(240,96,180) },
		{ name="Ultimate Coin Pack", beans="180,000", bonus="+50%", price="1499 R$", productId=0, col=Color3.fromRGB(248,150,56), tag="\xE2\xAD\x90 BEST VALUE" },
	},
}
local GAMEPASS_IDS = CONFIG.gamepassIds
local PRODUCT_IDS  = CONFIG.productIds
local BEAN_IMG     = CONFIG.beanImage

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--======================================================================
-- GUI HELPERS (verbatim from CoreClient / ShopClient)
--======================================================================
local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

-- ===== UI CLICK SOUND (self-contained, shared via _G) =====
local uiClickSound = Instance.new("Sound")
uiClickSound.Name="UIClickSound_ShopKit"; uiClickSound.SoundId=CONFIG.uiClickSound; uiClickSound.Volume=0.5; uiClickSound.Parent=PlayerGui
local function playUIClick()
	local s=uiClickSound:Clone(); s.Parent=PlayerGui; s:Play(); Debris:AddItem(s,3)
end
_G.playUIClick = _G.playUIClick or playUIClick

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared manager; reuse the game's if present) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible) -- hide/show the bottom HUD cluster while a main menu is open
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h=mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
_G.MainMenuManager.register("Premium", function() local g=PlayerGui:FindFirstChild("PremiumShopGui"); if g then g.Enabled=false end end)

--======================================================================
-- 1) THE SHOP BUTTON  (left rail, FINAL in-game look)
--    95x95 frame, x=12, y=96 (desktop grid 96/203/310/417, 107px pitch).
--    Bright green 50,220,50 / corner 16 / stroke 30,120,30 w3.
--    🛒 icon label (TextSize 30, 56px tall, black stroke 1) over a "SHOP"
--    label (GothamBold 12, y57, black stroke 1) + a full-size invisible
--    TextButton on top that does the clicking.
--======================================================================
local shopSideFrame, shopSideClick
if CONFIG.buildShopButton then
	local sidebarGui = PlayerGui:FindFirstChild("ShopKitSidebarGui")
	if not sidebarGui then
		sidebarGui = Instance.new("ScreenGui")
		sidebarGui.Name = "ShopKitSidebarGui"; sidebarGui.ResetOnSpawn = false
		sidebarGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- notch only (matches SidebarGui)
		sidebarGui.Parent = PlayerGui
	end
	shopSideFrame = mkFrame(sidebarGui,{
		Name="ShopButton", Size=UDim2.new(0,95,0,95), AnchorPoint=Vector2.new(0,0),
		Position=UDim2.new(0,12,0,CONFIG.shopButtonY), BackgroundColor3=Color3.fromRGB(50,220,50),
	})
	mkCorner(shopSideFrame,16); mkStroke(shopSideFrame,Color3.fromRGB(30,120,30),3)
	local iconL = mkLabel(shopSideFrame,{Text="\xF0\x9F\x9b\x92",Font=Enum.Font.Gotham,TextSize=30,Size=UDim2.new(1,0,0,56),Position=UDim2.new(0,0,0,0),RichText=true,TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(iconL,Color3.new(0,0,0),1)
	local textL = mkLabel(shopSideFrame,{Name="Label",Text="SHOP",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,28),Position=UDim2.new(0,0,0,57),TextXAlignment=Enum.TextXAlignment.Center})
	mkStroke(textL,Color3.new(0,0,0),1)
	shopSideClick = mkButton(shopSideFrame,{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""})
end

--======================================================================
-- 2) THE SHOP PANEL  (PremiumShopGui) -- build pass
--======================================================================
local PremiumShopGui = Instance.new("ScreenGui")
PremiumShopGui.Name="PremiumShopGui"; PremiumShopGui.ResetOnSpawn=false; PremiumShopGui.Enabled=false
PremiumShopGui.DisplayOrder=100 -- definitively above the HUD (<=5) so the shop covers it
PremiumShopGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets -- topbar + notch (matches the game)
PremiumShopGui.Parent=PlayerGui
local sg = PremiumShopGui

-- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS
-- (that's what enables direct click-to-switch between menus)
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false})

local premPanel=mkFrame(sg,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(40, 86, 44),ClipsDescendants=true,Active=true})
mkCorner(premPanel,28); mkStroke(premPanel,Color3.new(1,1,1),3)
-- INNER floating blue card: ALL content lives in here. ClipsDescendants rounds the header + everything
-- else to the card's corners.
local premCard=mkFrame(premPanel,{Size=UDim2.new(1,0,1,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(40, 86, 44),ClipsDescendants=true})
mkCorner(premCard,26)

local premHeader=mkFrame(premCard,{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(15,60,140)})
local premTitleLbl=mkLabel(premHeader,{Text="\xF0\x9F\x9B\x92 SHOP",Font=Enum.Font.GothamBold,TextSize=35,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-60,0,44),Position=UDim2.new(0,16,0,4),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(premTitleLbl,Color3.new(0,0,0),2)
mkLabel(premHeader,{Text="Power up your adventure!",Font=Enum.Font.Gotham,TextSize=13,TextColor3=Color3.fromRGB(215,228,255),Size=UDim2.new(1,-60,0,16),Position=UDim2.new(0,16,0,46),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="\xe2\x9c\x95",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)})
mkCorner(premClose,8)

-- ===== SHOP CONTENTS -- proper LAYOUTS (no absolute positions): a vertical scroll holds two sections;
-- each section CENTERS its 3 cards with a horizontal UIListLayout; each card STACKS its content with a
-- vertical UIListLayout and pins the BUY button to the bottom. So every card is uniform, evenly spaced,
-- centered + aligned, and the list scrolls so nothing is ever cut off. =====
local premScroll=Instance.new("ScrollingFrame")
premScroll.Name="PremiumScroll"; premScroll.BackgroundTransparency=1; premScroll.BorderSizePixel=0
if CONFIG.showCoinBanner then
	premScroll.Position=UDim2.new(0,3,0,162); premScroll.Size=UDim2.new(1,-8,1,-238) -- under header + BUY COINS banner, above footer
else
	premScroll.Position=UDim2.new(0,3,0,70);  premScroll.Size=UDim2.new(1,-8,1,-146) -- no banner: straight under the header
end
premScroll.ScrollBarThickness=5; premScroll.ScrollBarImageColor3=Color3.fromRGB(255,224,90) -- thin, bright-gold rounded thumb
premScroll.TopImage="rbxasset://textures/ui/Scroll/scroll-top.png"; premScroll.MidImage="rbxasset://textures/ui/Scroll/scroll-middle.png"; premScroll.BottomImage="rbxasset://textures/ui/Scroll/scroll-bottom.png"
premScroll.CanvasSize=UDim2.new(0,0,0,0); premScroll.ScrollingDirection=Enum.ScrollingDirection.Y
premScroll.AutomaticCanvasSize=Enum.AutomaticSize.None; premScroll.Parent=premCard -- canvas driven explicitly by syncCanvas below
do
	local sll=Instance.new("UIListLayout"); sll.FillDirection=Enum.FillDirection.Vertical
	sll.HorizontalAlignment=Enum.HorizontalAlignment.Center; sll.Padding=UDim.new(0,18); sll.SortOrder=Enum.SortOrder.LayoutOrder; sll.Parent=premScroll
	local slp=Instance.new("UIPadding"); slp.PaddingTop=UDim.new(0,8); slp.PaddingBottom=UDim.new(0,10); slp.Parent=premScroll
	-- CANVAS = total content height so scrolling reaches every card. Driven EXPLICITLY from the layout's
	-- measured content size -- the reliable equivalent of AutomaticCanvasSize=Y.
	local function syncCanvas() premScroll.CanvasSize=UDim2.new(0,0,0, sll.AbsoluteContentSize.Y + 18) end
	sll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas); task.defer(syncCanvas)
end
local CARD_W, CARD_H = 208, 190
-- a gold section title + underline, sized to sit in the vertical scroll list
local function sectionHeader(text,order)
	local h=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,52),BackgroundTransparency=1,LayoutOrder=order})
	mkLabel(h,{Text=text,Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-8,0,26),Position=UDim2.new(0,8,0,4),TextXAlignment=Enum.TextXAlignment.Left})
	mkFrame(h,{Size=UDim2.new(1,-8,0,2),Position=UDim2.new(0,8,0,38),BackgroundColor3=Color3.fromRGB(255,215,0)})
	return h
end
-- a full-width row that evenly spaces + centers its cards
local function mkSectionRow(order)
	local row=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,CARD_H),BackgroundTransparency=1,LayoutOrder=order})
	local ll=Instance.new("UIListLayout"); ll.FillDirection=Enum.FillDirection.Horizontal
	ll.HorizontalAlignment=Enum.HorizontalAlignment.Center; ll.VerticalAlignment=Enum.VerticalAlignment.Top
	ll.Padding=UDim.new(0,24); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=row
	return row
end
-- a uniform card whose ENTIRE content is one vertical UIListLayout: icon -> name -> price -> [desc] -> BUY.
-- The BUY button is the LAST list item, so it can never overlap the text above it.
local function mkShopCard(parent,order)
	local c=mkFrame(parent,{Size=UDim2.new(0,CARD_W,0,CARD_H),LayoutOrder=order,BackgroundColor3=Color3.fromRGB(28, 64, 34)})
	mkCorner(c,16); mkStroke(c,Color3.new(1,1,1),2)
	local holder=mkFrame(c,{Name="Content",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1})
	local hl=Instance.new("UIListLayout"); hl.FillDirection=Enum.FillDirection.Vertical
	hl.HorizontalAlignment=Enum.HorizontalAlignment.Center; hl.VerticalAlignment=Enum.VerticalAlignment.Top
	hl.Padding=UDim.new(0,3); hl.SortOrder=Enum.SortOrder.LayoutOrder; hl.Parent=holder
	local hp=Instance.new("UIPadding"); hp.PaddingTop=UDim.new(0,18); hp.PaddingBottom=UDim.new(0,6); hp.PaddingLeft=UDim.new(0,8); hp.PaddingRight=UDim.new(0,8); hp.Parent=holder
	return c
end
local function cH(card) return card:FindFirstChild("Content") or card end
local function cardIcon(card,txt)
	mkLabel(cH(card),{Text=txt,Font=Enum.Font.Gotham,TextSize=40,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,42),LayoutOrder=1,RichText=false,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
end
local function cardTitles(card,main,sub,subCol)
	mkLabel(cH(card),{Text=main,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,0,0,19),LayoutOrder=2,TextXAlignment=Enum.TextXAlignment.Center})
	mkLabel(cH(card),{Text=sub,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=subCol,Size=UDim2.new(1,0,0,15),LayoutOrder=3,TextXAlignment=Enum.TextXAlignment.Center})
end
local function cardPrice(card,price)
	mkLabel(cH(card),{Text=price,Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,0,0,17),LayoutOrder=4,TextXAlignment=Enum.TextXAlignment.Center})
end
local function cardDesc(card,desc)
	mkLabel(cH(card),{Text=desc,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(232, 209, 158),Size=UDim2.new(1,0,0,20),LayoutOrder=5,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top})
end
-- BUY button: last list item (LayoutOrder 10) -> always rendered BELOW the icon/name/price
local function cardBuyBtn(card,col,txt,onClick)
	local btn=mkButton(cH(card),{Size=UDim2.new(1,0,0,32),LayoutOrder=10,BackgroundColor3=col,Text=txt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)})
	mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick); return btn
end

sectionHeader("\xe2\xad\x90 GAMEPASSES",1)
local gamepassRow=mkSectionRow(2)

-- Card 1: 2x Power Forever  (+ the "BEST VALUE ⭐" badge overlay -- built hidden, same as the live game)
local I = CONFIG.items
local card1=mkShopCard(gamepassRow,1)
local gpBadge=mkLabel(card1,{Text="BEST VALUE \xe2\xad\x90",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0.5,0,0,3),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,180,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3,Visible=false})
mkCorner(gpBadge,6)
cardIcon(card1,I.twoXForever.icon); cardTitles(card1,I.twoXForever.title,I.twoXForever.sub,I.twoXForever.subCol); cardPrice(card1,I.twoXForever.price)
local btn1=cardBuyBtn(card1,I.twoXForever.btnCol,"BUY GAMEPASS",function()
	-- already owned: do nothing. The attribute is the one that is actually set in this realm
	-- (PurchaseReceipts.server.luau); the _G table is the main game's channel and stays false here.
	if player:GetAttribute("HasTwoXForever") == true then return end
	if _G.playerGamepasses and _G.playerGamepasses.twoXForever then return end
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.TwoXForever) end)
end)
mkStroke(btn1,Color3.fromRGB(200,130,0),2)

-- Card 2: Glitter Trail
local card2=mkShopCard(gamepassRow,2)
cardIcon(card2,I.glitterTrail.icon); cardTitles(card2,I.glitterTrail.title,I.glitterTrail.sub,I.glitterTrail.subCol); cardPrice(card2,I.glitterTrail.price)
local btn2=cardBuyBtn(card2,I.glitterTrail.btnCol,"BUY GAMEPASS",function()
	if player:GetAttribute("HasGlitterTrail") == true then return end            -- already owned: do nothing
	if _G.playerGamepasses and _G.playerGamepasses.glitterTrail then return end
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.GlitterTrail) end)
end)

-- Card 3: 2x Power 1 Hour  (+ live "Active: Xm Ys" timer)
local card3=mkShopCard(gamepassRow,3)
cardIcon(card3,I.twoXHour.icon); cardTitles(card3,I.twoXHour.title,I.twoXHour.sub,I.twoXHour.subCol); cardPrice(card3,I.twoXHour.price)
local twoXShopTimer=mkLabel(cH(card3),{Text="",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(100,220,100),Size=UDim2.new(1,-8,0,14),LayoutOrder=6,TextXAlignment=Enum.TextXAlignment.Center,Visible=false})
cardBuyBtn(card3,I.twoXHour.btnCol,"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.TwoXOneHour) end) end)

sectionHeader("\xF0\x9F\x8E\xAF ONE-TIME ITEMS",3)
local productRow=mkSectionRow(4)

-- Card 4: Mid-Air Recharge
local card4=mkShopCard(productRow,1)
cardIcon(card4,I.midAir.icon); cardTitles(card4,I.midAir.title,I.midAir.sub,I.midAir.subCol); cardPrice(card4,I.midAir.price); cardDesc(card4,I.midAir.desc)
cardBuyBtn(card4,I.midAir.btnCol,"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MidAirRecharge) end) end)

-- Card 5: Skip Island
local card5=mkShopCard(productRow,2)
cardIcon(card5,I.skipIsland.icon); cardTitles(card5,I.skipIsland.title,I.skipIsland.sub,I.skipIsland.subCol); cardPrice(card5,I.skipIsland.price); cardDesc(card5,I.skipIsland.desc)
cardBuyBtn(card5,I.skipIsland.btnCol,"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.SkipIsland) end) end)

-- Card 6: Meteorite Explosion (this realm's product, in the kit's Bird Nuke slot)
local card6=mkShopCard(productRow,3)
cardIcon(card6,I.meteorite.icon); cardTitles(card6,I.meteorite.title,I.meteorite.sub,I.meteorite.subCol); cardPrice(card6,I.meteorite.price); cardDesc(card6,I.meteorite.desc)
cardBuyBtn(card6,I.meteorite.btnCol,"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MeteoriteExplosion) end) end)

-- 2x-1-hour countdown on card 3.
--
-- The kit reads _G.playerGamepasses.twoXHourExpiry, which is how the main game publishes it. In THIS
-- realm nothing ever writes that table -- ShopGlue initialises it to {twoXForever=false,
-- glitterTrail=false} and nobody touches it again -- so the countdown would sit invisible forever
-- even with an hour on the clock. PurchaseReceipts.server.luau sets the PLAYER ATTRIBUTE
-- "TwoXHourExpiry" instead (and mirrors it through GamepassEvent), so read whichever is further out.
local function twoXExpiry()
	local a = player:GetAttribute("TwoXHourExpiry")
	local gp = _G.playerGamepasses
	local g = gp and gp.twoXHourExpiry
	return math.max(typeof(a) == "number" and a or 0, typeof(g) == "number" and g or 0)
end
task.spawn(function()
	while true do
		task.wait(1)
		local expiry = twoXExpiry()
		if expiry > os.time() then
			local rem=expiry-os.time()
			twoXShopTimer.Text="\xe2\x9a\xa1 Active: "..math.floor(rem/60).."m "..rem%60 .."s"
			twoXShopTimer.Visible=true
		else
			twoXShopTimer.Visible=false
		end
	end
end)

for _,v in ipairs(premPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end

--======================================================================
-- 3) PREMIUM SHOP STYLE  (pass 1 of 4)
--======================================================================
;(function()
	-- 6-COLOUR VIRAL PET-SIM THEME. Fresh indigo/blurple base; gold/green/red reused from the Rebirth HUD.
	-- Style = thick outlines + drop shadow + "juicy" beveled buttons + chunky FredokaOne.
	local PANEL  = Color3.fromRGB(40, 86, 44)  -- 1 pets-HUD blue (main background)
	local PANEL2 = Color3.fromRGB(78, 158, 72) -- 2 lighter blue (gradient top)
	local GOLD   = Color3.fromRGB(255, 206, 92) -- 4 gold (title / prices)
	local GREEN  = Color3.fromRGB(86, 205, 120) -- 5 green (buy)
	local RED    = Color3.fromRGB(232, 96, 90)  -- 6 red (close)
	local function dark(c, f) return c:Lerp(Color3.new(0, 0, 0), f or 0.5) end
	local function setStroke(i, col, th) local s = i:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = i; return s end
	local function juice(i) -- top-bright -> bottom-dark bevel, the pet-sim button look
		if i:FindFirstChildOfClass("UIGradient") then return end
		local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(170,170,170)); g.Rotation = 90; g.Parent = i
	end
	local function vgrad(i, top, bot) local g = i:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); g.Color = ColorSequence.new(top, bot); g.Rotation = 90; g.Parent = i; return g end

	-- chunky white FredokaOne text + black outline on everything
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Font = Enum.Font.FredokaOne; v.TextScaled = true; v.TextColor3 = Color3.fromRGB(255,255,255)
			setStroke(v, Color3.fromRGB(0,0,0), 2)
		end
	end

	-- subtle soft drop shadow -- just enough to lift the window off the game world
	local sh = Instance.new("ImageLabel")
	sh.AnchorPoint = Vector2.new(0.5,0.5); sh.Position = UDim2.new(0.5,0,0.5,-11); sh.Size = UDim2.fromOffset(786,586) -- tracks the premium panel's hub-parity -16 (keeps its 5px sag)
	sh.BackgroundTransparency = 1; sh.Image = "rbxassetid://1316045217"; sh.ImageColor3 = Color3.new(0,0,0); sh.ImageTransparency = 0.9
	sh.ScaleType = Enum.ScaleType.Slice; sh.SliceCenter = Rect.new(10,10,118,118); sh.ZIndex = 0; sh.Parent = premPanel.Parent

	-- ONE clean floating blue card -- no dark outer box, no inner shadow
	premPanel.BackgroundTransparency = 1 -- transparent container so nothing dark surrounds the card
	premPanel.ClipsDescendants = false   -- let the card's own rounded corners + outline show fully
	local _ps = premPanel:FindFirstChildOfClass("UIStroke"); if _ps then _ps:Destroy() end
	premCard.BackgroundColor3 = PANEL; vgrad(premCard, PANEL2, Color3.fromRGB(96,60,178)); setStroke(premCard, Color3.new(0,0,0), 4) -- thick BLACK outline around the whole window
	premHeader.BackgroundTransparency = 1 -- transparent header -> the card's rounded TOP corners show
	do -- gentle shine sweep across the SHOP header every few seconds
		premHeader.ClipsDescendants = true
		local shine = Instance.new("Frame"); shine.BackgroundColor3 = Color3.new(1,1,1); shine.BackgroundTransparency = 0.55
		shine.Size = UDim2.new(0,60,1,0); shine.Rotation = 8; shine.ZIndex = (premHeader.ZIndex or 1)+2; shine.Parent = premHeader
		local sgr = Instance.new("UIGradient", shine); sgr.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,0),NumberSequenceKeypoint.new(1,1)})
		task.spawn(function()
			while shine.Parent do
				shine.Position = UDim2.new(-0.2,0,0,0)
				TS:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), {Position = UDim2.new(1.2,0,0,0)}):Play()
				task.wait(4)
			end
		end)
	end
	-- close + title
	premClose.BackgroundColor3 = RED; setStroke(premClose, dark(RED, 0.45), 3); juice(premClose)
	premTitleLbl.TextColor3 = GOLD

	-- cards: lighter indigo + thick outline + bevel
	for _, card in ipairs({card1, card2, card3, card4, card5, card6}) do
		card.BackgroundColor3 = PANEL2; setStroke(card, dark(PANEL, 0.35), 2.5); juice(card)
	end

	-- buy buttons (gamepass = gold, one-time = green) + gold prices/section titles
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextButton") then
			if v.Text:find("BUY GAMEPASS") then v.BackgroundColor3 = GOLD; setStroke(v, dark(GOLD, 0.5), 2.5); juice(v)
			elseif v.Text:find("BUY NOW") then v.BackgroundColor3 = GREEN; setStroke(v, dark(GREEN, 0.5), 2.5); juice(v) end
		end
		if v:IsA("TextLabel") then
			if v.Text:find("R%$") then v.TextColor3 = GOLD end
			if v.Text:find("GAMEPASSES") or v.Text:find("ONE%-TIME") then v.TextColor3 = GOLD end
		end
	end

	-- gpBadge: dark text on gold, no outline
	gpBadge.TextColor3 = dark(GOLD, 0.72); gpBadge.BackgroundColor3 = GOLD
	local gbS = gpBadge:FindFirstChildOfClass("UIStroke"); if gbS then gbS:Destroy() end
end)()

--======================================================================
-- 4) PREMIUM SHOP LAYOUT  (pass 2 of 4) -- fixed 770x572, cards re-laid-out
--======================================================================
;(function()
	premPanel.Size = UDim2.new(0,770,0,572)      -- ~10% bigger than the food shop for breathing room
	premPanel.Position = UDim2.new(0.5,0,0.5,-16) -- hub-parity: -16 here = the hub's -45 screen spot (this gui ignores the topbar inset on phones)
	premPanel.AnchorPoint = Vector2.new(0.5,0.5)

	-- Cards stay in their section rows INSIDE premScroll, so headers AND cards scroll TOGETHER.
	gamepassRow.Size = UDim2.new(1,-16,0,190)
	productRow.Size  = UDim2.new(1,-16,0,220)
	for i, c in ipairs({card1, card2, card3}) do
		c.Parent = gamepassRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,190)
	end
	for i, c in ipairs({card4, card5, card6}) do
		c.Parent = productRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,220)
	end

	-- Re-layout card content into a _Content sub-frame with a UIListLayout.
	-- Badge (card1 only) stays as an absolute overlay on the card itself.
	local function layoutCard(card, isProduct)
		local iconLbl, buyBtn, timer = nil, nil, nil
		local textLbls = {}
		for _, child in ipairs(card:GetChildren()) do
			if child == gpBadge then
				-- handled below as absolute overlay
			elseif child == twoXShopTimer then
				timer = child
			elseif child:IsA("TextButton") then
				buyBtn = child
			elseif child:IsA("TextLabel") then
				if child.TextSize >= 40 then iconLbl = child else table.insert(textLbls, child) end
			end
		end
		table.sort(textLbls, function(a, b) return a.Position.Y.Offset < b.Position.Y.Offset end) -- title→sub→price→desc

		local cf = Instance.new("Frame")
		cf.Name = "_Content"; cf.Size = UDim2.new(1,0,1,0); cf.BackgroundTransparency = 1; cf.Parent = card

		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Vertical
		ll.Padding = UDim.new(0,8) -- breathing room between icon/title/desc/price/button
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.VerticalAlignment = Enum.VerticalAlignment.Top
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = cf

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0,10); pad.PaddingBottom = UDim.new(0,10)
		pad.PaddingLeft = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8)
		pad.Parent = cf

		if iconLbl then
			iconLbl.Size = UDim2.new(0, isProduct and 50 or 55, 0, isProduct and 50 or 55)
			iconLbl.LayoutOrder = 1; iconLbl.TextScaled = true; iconLbl.Parent = cf
		end

		local gpSz = {UDim2.new(1,-8,0,26), UDim2.new(1,-8,0,22), UDim2.new(1,-8,0,22)}
		local pdSz = {UDim2.new(1,-8,0,24), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,28)}
		local szList = isProduct and pdSz or gpSz
		for i, lbl in ipairs(textLbls) do
			lbl.Size = szList[i] or UDim2.new(1,-8,0,20)
			lbl.LayoutOrder = i + 1; lbl.TextScaled = true; lbl.Parent = cf
		end

		if timer then -- card3: between price and buy when active
			timer.Size = UDim2.new(1,-8,0,18); timer.LayoutOrder = 5; timer.TextScaled = true; timer.Parent = cf
		end

		if buyBtn then -- last in stack
			buyBtn.Size = UDim2.new(1,-12,0,40); buyBtn.LayoutOrder = 10; buyBtn.TextScaled = true; buyBtn.Parent = cf
		end

		if card == card1 then -- badge: absolute overlay on card (NOT inside _Content)
			gpBadge.Size = UDim2.new(1,-8,0,18); gpBadge.Position = UDim2.new(0,4,0,2); gpBadge.ZIndex = 10
		end
	end

	layoutCard(card1, false); layoutCard(card2, false); layoutCard(card3, false)
	layoutCard(card4, true);  layoutCard(card5, true);  layoutCard(card6, true)
end)()

-- Explicitly style the shop close button
premClose.Text = "X"
premClose.Font = Enum.Font.FredokaOne
premClose.TextScaled = true
premClose.TextColor3 = Color3.fromRGB(255,255,255)
do
	local pcs = premClose:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	pcs.Color = Color3.fromRGB(0,0,0); pcs.Thickness = 2; pcs.Parent = premClose
end

--======================================================================
-- LOW-POLY COIN / BEAN / MASCOT BUILDERS (shared by the banner + coin shop)
-- Built from Frames, NOT emoji: 🫘 renders as an empty box in Roblox's font.
--======================================================================
local function _rc(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end
local function _rs(i, col, th) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = i end
local _coinPhase = 0
-- Premium low-poly coin: thickness edge, light-yellow->rich-gold gradient, glossy top shine, beveled dark
-- rim, embossed star, upper-left highlight, slow shine sweep. Returns a holder frame.
local function makeCoin(parent, sz, z)
	local holder = Instance.new("Frame"); holder.BackgroundTransparency = 1; holder.Size = UDim2.fromOffset(sz, sz); holder.ZIndex = z; holder.Parent = parent
	local depth = math.max(2, math.floor(sz * 0.09))
	local edge = Instance.new("Frame"); edge.AnchorPoint = Vector2.new(0.5, 0); edge.Position = UDim2.new(0.5, 0, 0, depth); edge.Size = UDim2.fromOffset(sz, sz); edge.BackgroundColor3 = Color3.fromRGB(176, 112, 16); edge.ZIndex = z; edge.Parent = holder; _rc(edge, sz)
	local face = Instance.new("Frame"); face.Size = UDim2.fromOffset(sz, sz); face.BackgroundColor3 = Color3.fromRGB(255, 206, 92); face.ClipsDescendants = true; face.ZIndex = z + 1; face.Parent = holder; _rc(face, sz); _rs(face, Color3.fromRGB(150, 96, 12), math.max(1.5, sz * 0.06))
	local fg = Instance.new("UIGradient", face); fg.Rotation = 90; fg.Color = ColorSequence.new(Color3.fromRGB(255, 242, 158), Color3.fromRGB(232, 166, 38))
	local inner = Instance.new("Frame"); inner.AnchorPoint = Vector2.new(0.5, 0.5); inner.Position = UDim2.fromScale(0.5, 0.52); inner.Size = UDim2.fromScale(0.64, 0.64); inner.BackgroundColor3 = Color3.fromRGB(255, 226, 120); inner.ZIndex = z + 2; inner.Parent = face; _rc(inner, sz); _rs(inner, Color3.fromRGB(210, 146, 26), math.max(1, sz * 0.03))
	local ig = Instance.new("UIGradient", inner); ig.Rotation = 90; ig.Color = ColorSequence.new(Color3.fromRGB(255, 248, 196), Color3.fromRGB(240, 188, 66))
	local star = Instance.new("TextLabel"); star.BackgroundTransparency = 1; star.AnchorPoint = Vector2.new(0.5, 0.5); star.Position = UDim2.fromScale(0.5, 0.5); star.Size = UDim2.fromScale(0.74, 0.74); star.Font = Enum.Font.FredokaOne; star.TextScaled = true; star.Text = "\xE2\x98\x85"; star.TextColor3 = Color3.fromRGB(206, 144, 26); star.ZIndex = z + 3; star.Parent = inner
	local gloss = Instance.new("Frame"); gloss.AnchorPoint = Vector2.new(0.5, 0); gloss.Position = UDim2.new(0.5, 0, 0, math.max(2, sz * 0.08)); gloss.Size = UDim2.fromScale(0.64, 0.30); gloss.BackgroundColor3 = Color3.new(1, 1, 1); gloss.BackgroundTransparency = 0.35; gloss.ZIndex = z + 4; gloss.Parent = face; _rc(gloss, sz)
	local glg = Instance.new("UIGradient", gloss); glg.Rotation = 90; glg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	local hl = Instance.new("Frame"); hl.AnchorPoint = Vector2.new(0.5, 0.5); hl.Position = UDim2.fromScale(0.32, 0.3); hl.Size = UDim2.fromScale(0.13, 0.13); hl.BackgroundColor3 = Color3.new(1, 1, 1); hl.BackgroundTransparency = 0.1; hl.ZIndex = z + 5; hl.Parent = face; _rc(hl, sz)
	if sz >= 30 then -- slow shine sweep across the face (bigger coins only), staggered so they don't sync
		local streak = Instance.new("Frame"); streak.BackgroundColor3 = Color3.new(1, 1, 1); streak.BackgroundTransparency = 0.55; streak.BorderSizePixel = 0; streak.Rotation = 20; streak.Size = UDim2.new(0.3, 0, 1.6, 0); streak.Position = UDim2.new(-0.45, 0, -0.3, 0); streak.ZIndex = z + 6; streak.Parent = face
		local sgr = Instance.new("UIGradient", streak); sgr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		_coinPhase = (_coinPhase + 1) % 5; local ph = _coinPhase * 0.6
		task.spawn(function()
			task.wait(ph)
			while streak.Parent do
				streak.Position = UDim2.new(-0.45, 0, -0.3, 0)
				TS:Create(streak, TweenInfo.new(0.85, Enum.EasingStyle.Sine), { Position = UDim2.new(1.15, 0, -0.3, 0) }):Play()
				task.wait(3.6)
			end
		end)
	end
	return holder
end
-- Unique coin pile per bundle {xScale, yScale, sizePx, rotDeg}. More/bigger coins = more value at a glance.
local COIN_PILES = {
	{{0.5,0.5,52,0}},
	{{0.33,0.6,38,-8},{0.67,0.6,38,8},{0.5,0.42,42,0}},
	{{0.26,0.62,34,-12},{0.74,0.62,34,12},{0.42,0.48,36,-4},{0.6,0.46,36,6}},
	{{0.22,0.64,32,-14},{0.5,0.66,38,0},{0.78,0.64,32,14},{0.36,0.46,34,-6},{0.62,0.46,34,6}},
	{{0.18,0.64,30,-16},{0.4,0.68,34,-4},{0.6,0.68,34,6},{0.82,0.64,30,16},{0.3,0.46,32,-8},{0.58,0.44,34,10},{0.5,0.3,30,0}},
	{{0.16,0.68,28,-18},{0.36,0.7,32,-6},{0.58,0.7,32,6},{0.8,0.68,28,18},{0.28,0.5,32,-10},{0.5,0.48,36,2},{0.7,0.5,32,12},{0.4,0.32,30,-6},{0.6,0.32,30,8}},
}

--======================================================================
-- 5) SIMULATOR-GRADE POLISH  (pass 3 of 4)
-- rainbow card gradients + glowing borders, gold price capsules, hover pop,
-- footer banner + bean mascot, twinkling sparkles, slide-in-from-bottom.
-- Deferred so the card layout above is final first.
--======================================================================
task.defer(function()
	local cards = {card1, card2, card3, card4, card5, card6}
	local CARD_COLS = { -- 6 unique gradients, no repeats: blue, purple, pink, green, cyan, orange
		Color3.fromRGB(86, 170, 78), Color3.fromRGB(150,96,240), Color3.fromRGB(240,96,180),
		Color3.fromRGB(72,200,120), Color3.fromRGB(64,200,224), Color3.fromRGB(248,150,56),
	}
	local function light(c) return c:Lerp(Color3.new(1,1,1), 0.24) end
	local function dark(c, f) return c:Lerp(Color3.new(0,0,0), f or 0.45) end

	for i, card in ipairs(cards) do
		if card then
			local col = CARD_COLS[i]:Lerp(Color3.fromRGB(150,150,158), 0.14) -- slightly desaturated so text reads clearly
			card.BackgroundColor3 = col
			local g = card:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
			g.Color = ColorSequence.new(light(col), dark(col, 0.28)); g.Rotation = 90; g.Parent = card
			local s = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			s.Color = light(col); s.Thickness = 2.5; s.Transparency = 0.06; s.Parent = card -- glowing border
			local cc = card:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); cc.CornerRadius = UDim.new(0,18); cc.Parent = card

			do -- soft shine strip across the top of the card (static)
				local sheen = Instance.new("Frame"); sheen.BackgroundColor3 = Color3.new(1,1,1); sheen.BorderSizePixel = 0; sheen.BackgroundTransparency = 0.74
				sheen.Size = UDim2.new(1,-16,0,10); sheen.Position = UDim2.new(0,8,0,6); sheen.ZIndex = (card.ZIndex or 1)+4; sheen.Parent = card
				Instance.new("UICorner", sheen).CornerRadius = UDim.new(0,6)
				local shG = Instance.new("UIGradient", sheen); shG.Rotation = 90; shG.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(1,1)})
			end
			-- icon stays still (no idle pulse)
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text:find("R%$") then -- price -> compact gold capsule with a coin, BELOW the desc
					d.BackgroundColor3 = Color3.fromRGB(255,206,92); d.BackgroundTransparency = 0; d.TextColor3 = Color3.fromRGB(92,58,8)
					d.Size = UDim2.fromOffset(128,24); d.LayoutOrder = 9 -- gold price capsule, centered above the button
					local pg = d:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); pg.Color = ColorSequence.new(Color3.fromRGB(255,238,176), Color3.fromRGB(240,190,60)); pg.Rotation = 90; pg.Parent = d
					if not d.Text:find("\xF0\x9F\xAA\x99") then d.Text = "\xF0\x9F\xAA\x99 " .. d.Text end
					local pc = d:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); pc.CornerRadius = UDim.new(1,0); pc.Parent = d
					local ps = d:FindFirstChildOfClass("UIStroke"); if ps then ps.Color = Color3.fromRGB(180,122,20); ps.Thickness = 2 end
					break
				end
			end

			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextButton") then -- ONE short, centered green pill purchase button at the bottom
					d.Size = UDim2.new(0.8,0,0,36); d.LayoutOrder = 20
					d.BackgroundColor3 = Color3.fromRGB(96,210,128)
					local bc = d:FindFirstChildOfClass("UICorner") or Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,18); bc.Parent = d
					local bg2 = d:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient"); bg2.Color = ColorSequence.new(Color3.fromRGB(142,226,160), Color3.fromRGB(86,184,112)); bg2.Rotation = 90; bg2.Parent = d
					local bsr = d:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); bsr.Color = Color3.fromRGB(46,120,68); bsr.Thickness = 1.5; bsr.Parent = d
					local bScl = Instance.new("UIScale"); bScl.Parent = d -- hover glow + click bounce
					d.MouseEnter:Connect(function() TS:Create(bScl, TweenInfo.new(0.1), {Scale=1.05}):Play() end)
					d.MouseLeave:Connect(function() TS:Create(bScl, TweenInfo.new(0.1), {Scale=1}):Play() end)
					d.MouseButton1Down:Connect(function() bScl.Scale=0.92; TS:Create(bScl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale=1}):Play() end)
					break
				end
			end

			local baseSize = card.Size -- hover pop (PC)
			card.MouseEnter:Connect(function() TS:Create(card, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = baseSize + UDim2.fromOffset(12,12) }):Play() end)
			card.MouseLeave:Connect(function() TS:Create(card, TweenInfo.new(0.12), { Size = baseSize }):Play() end)
		end
	end

	-- soft glow behind the SHOP title
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1; glow.Image = "rbxassetid://1316045217"; glow.ImageColor3 = Color3.fromRGB(255,220,120); glow.ImageTransparency = 0.55
	glow.ScaleType = Enum.ScaleType.Slice; glow.SliceCenter = Rect.new(10,10,118,118)
	glow.Size = UDim2.fromOffset(250,72); glow.Position = premTitleLbl.Position - UDim2.fromOffset(16,10); glow.ZIndex = math.max(0, premTitleLbl.ZIndex - 1); glow.Parent = premTitleLbl.Parent

	do -- subtle sparkles around the SHOP title (twinkle in place, no movement)
		for k = 1, 3 do
			local tw = Instance.new("TextLabel"); tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold; tw.Text = "\xE2\x9C\xA6"
			tw.TextColor3 = Color3.fromRGB(255,240,180); tw.TextSize = 10 + k*2; tw.Size = UDim2.fromOffset(16,16)
			tw.Position = UDim2.new(0, 130 + k*24, 0, (k % 2 == 0 and 8 or 32)); tw.ZIndex = (premTitleLbl.ZIndex or 1) + 1; tw.Parent = premTitleLbl.Parent
			TS:Create(tw, TweenInfo.new(0.8 + k*0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.85 }):Play()
		end
	end

	-- footer: full-width purple gradient banner + bean mascot
	local footer = Instance.new("Frame")
	footer.AnchorPoint = Vector2.new(0.5,1); footer.Position = UDim2.new(0.5,0,1,-10); footer.Size = UDim2.new(1,-16,0,60)
	footer.BackgroundColor3 = Color3.fromRGB(120,104,240); footer.ZIndex = 4; footer.Parent = premCard
	Instance.new("UICorner", footer).CornerRadius = UDim.new(0,16)
	local fg = Instance.new("UIGradient", footer); fg.Color = ColorSequence.new(Color3.fromRGB(150,108,244), Color3.fromRGB(96,68,202)); fg.Rotation = 90
	local ft = Instance.new("TextLabel")
	ft.BackgroundTransparency = 1; ft.Position = UDim2.fromOffset(22,0); ft.Size = UDim2.new(1,-92,1,0); ft.Font = Enum.Font.FredokaOne
	ft.TextScaled = true; ft.TextColor3 = Color3.new(1,1,1); ft.TextXAlignment = Enum.TextXAlignment.Left; ft.ZIndex = 5
	ft.Text = "\xE2\xAD\x90 Thanks for supporting " .. CONFIG.realmName .. "!"; ft.Parent = footer
	local fts = Instance.new("UIStroke", ft); fts.Color = Color3.fromRGB(40,20,80); fts.Thickness = 2
	local ftc = Instance.new("UITextSizeConstraint", ft); ftc.MaxTextSize = 16
	local bean = Instance.new("ImageLabel") -- mascot, held still
	bean.AnchorPoint = Vector2.new(1,0.5); bean.Position = UDim2.new(1,-18,0.5,0); bean.Size = UDim2.fromOffset(54,54)
	bean.BackgroundTransparency = 1; bean.Image = BEAN_IMG; bean.ZIndex = 5; bean.Parent = footer
	for s = 1, 3 do -- subtle sparkles around the mascot -- twinkle in place, no movement
		local tw = Instance.new("TextLabel"); tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold; tw.Text = "\xE2\x9C\xA6"
		tw.TextColor3 = Color3.fromRGB(255,240,190); tw.TextSize = 10 + s*2; tw.Size = UDim2.fromOffset(16,16); tw.ZIndex = 6
		tw.Position = UDim2.new(1, -54 - (s-1)*6, 0.5, (s==2 and -18 or 12)); tw.Parent = footer
		TS:Create(tw, TweenInfo.new(0.7 + s*0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.85 }):Play()
	end

	-- drifting background sparkles
	for i = 1, 10 do
		local sp = Instance.new("TextLabel")
		sp.BackgroundTransparency = 1; sp.Font = Enum.Font.GothamBold; sp.Text = "\xE2\x9C\xA6"; sp.TextColor3 = Color3.new(1,1,1); sp.TextTransparency = 0.72
		sp.TextSize = 12 + (i % 3) * 6; sp.Size = UDim2.fromOffset(22,22); sp.ZIndex = 0
		sp.Position = UDim2.fromScale(0.06 + (i * 0.09) % 0.88, 0.18 + (i * 0.13) % 0.66); sp.Parent = premCard
		TS:Create(sp, TweenInfo.new(2.6 + i * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.92 }):Play()
	end

	-- slide in from the bottom on open
	local shopGui = premPanel:FindFirstAncestorOfClass("ScreenGui")
	if shopGui then
		local home = premPanel.Position
		shopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if shopGui.Enabled then
				premPanel.Position = home + UDim2.fromScale(0, 0.6)
				TS:Create(premPanel, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
			end
		end)
	end
end)

--======================================================================
-- 6) CURRENCY BANNER + COIN SHOP OVERLAY  (pass 4 of 4)
-- A featured banner under the header opens a scale-in COIN SHOP that REPLACES
-- the main page (never two windows stacked). Buys nothing on the main page.
--======================================================================
if CONFIG.showCoinBanner then
task.defer(function()
	local function corner(i,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=i; return c end
	local function stroke(i,col,th,tr) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=th or 2; s.Transparency=tr or 0; s.Parent=i; return s end
	local function vgrad(i,a,b,rot) local g=Instance.new("UIGradient"); g.Color=ColorSequence.new(a,b); g.Rotation=rot or 90; g.Parent=i; return g end
	local function pad(i,n) local p=Instance.new("UIPadding",i); for _,s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do p[s]=UDim.new(0,n) end end
	local function maxsize(i,n) local c=Instance.new("UITextSizeConstraint",i); c.MaxTextSize=n end
	local GOLD=Color3.fromRGB(255,206,92); local GREEN=Color3.fromRGB(86,205,120)
	local function juice(i) local g=Instance.new("UIGradient"); g.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,170,170)); g.Rotation=90; g.Parent=i end

	local BEAN_PACKS = CONFIG.coinPacks

	----------------------------------------------------------------
	-- Coin Shop overlay (built hidden; opened by the banner)
	----------------------------------------------------------------
	local overlay=Instance.new("Frame"); overlay.Name="CurrencyOverlay"; overlay.AnchorPoint=Vector2.new(0.5,0.5); overlay.Position=UDim2.fromScale(0.5,0.5); overlay.Size=UDim2.fromScale(1,1)
	overlay.BackgroundColor3=Color3.new(0,0,0); overlay.BackgroundTransparency=1; overlay.Visible=false; overlay.ZIndex=50; overlay.Parent=premPanel; corner(overlay,20)

	-- the coin shop FILLS the whole card so it fully replaces the main shop. premCard's black outline frames it.
	local win=Instance.new("Frame"); win.AnchorPoint=Vector2.new(0.5,0.5); win.Position=UDim2.fromScale(0.5,0.5); win.Size=UDim2.new(1,0,1,0)
	win.BackgroundColor3=Color3.fromRGB(40, 86, 44); win.ZIndex=51; win.Parent=overlay; corner(win,26); vgrad(win,Color3.fromRGB(78, 158, 72),Color3.fromRGB(40, 86, 44),90)
	local winScale=Instance.new("UIScale"); winScale.Parent=win

	local wTitle=Instance.new("TextLabel"); wTitle.BackgroundTransparency=1; wTitle.Position=UDim2.fromOffset(20,6); wTitle.Size=UDim2.new(1,-80,0,32); wTitle.Font=Enum.Font.FredokaOne; wTitle.TextScaled=true; wTitle.TextColor3=GOLD; wTitle.TextXAlignment=Enum.TextXAlignment.Left; wTitle.Text="\xF0\x9F\x92\xB0 COIN SHOP"; wTitle.ZIndex=52; wTitle.Parent=win; stroke(wTitle,Color3.fromRGB(30,16,60),1.5); maxsize(wTitle,30)
	local wSub=Instance.new("TextLabel"); wSub.BackgroundTransparency=1; wSub.Position=UDim2.fromOffset(20,40); wSub.Size=UDim2.new(1,-80,0,16); wSub.Font=Enum.Font.Gotham; wSub.TextScaled=true; wSub.TextColor3=Color3.new(1,1,1); wSub.TextXAlignment=Enum.TextXAlignment.Left; wSub.Text="Get more Coins instantly!"; wSub.ZIndex=52; wSub.Parent=win; maxsize(wSub,15)
	local xBtn=Instance.new("TextButton"); xBtn.AnchorPoint=Vector2.new(1,0); xBtn.Position=UDim2.new(1,-10,0,10); xBtn.Size=UDim2.fromOffset(44,40); xBtn.BackgroundColor3=Color3.fromRGB(232,96,90); xBtn.Font=Enum.Font.FredokaOne; xBtn.TextScaled=true; xBtn.TextColor3=Color3.new(1,1,1); xBtn.Text="X"; xBtn.ZIndex=52; xBtn.Parent=win; corner(xBtn,10); stroke(xBtn,Color3.fromRGB(150,40,32),2.5); juice(xBtn); pad(xBtn,8)

	local grid=Instance.new("ScrollingFrame"); grid.BackgroundTransparency=1; grid.BorderSizePixel=0; grid.Position=UDim2.fromOffset(24,64); grid.Size=UDim2.new(1,-48,1,-142); grid.ScrollBarThickness=5; grid.ScrollBarImageColor3=GOLD; grid.CanvasSize=UDim2.new(); grid.AutomaticCanvasSize=Enum.AutomaticSize.Y; grid.ScrollingDirection=Enum.ScrollingDirection.Y; grid.ZIndex=52; grid.Parent=win
	local gl=Instance.new("UIGridLayout"); gl.CellSize=UDim2.fromOffset(202,214); gl.CellPadding=UDim2.fromOffset(34,30); gl.HorizontalAlignment=Enum.HorizontalAlignment.Center; gl.SortOrder=Enum.SortOrder.LayoutOrder; gl.Parent=grid
	do local p=Instance.new("UIPadding",grid); p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,10) end

	local wFooter=Instance.new("Frame"); wFooter.AnchorPoint=Vector2.new(0.5,1); wFooter.Position=UDim2.new(0.5,0,1,-8); wFooter.Size=UDim2.new(1,-28,0,54); wFooter.BackgroundColor3=Color3.fromRGB(120,104,240); wFooter.ZIndex=52; wFooter.Parent=win; corner(wFooter,12); vgrad(wFooter,Color3.fromRGB(150,120,248),Color3.fromRGB(108,88,224),90); stroke(wFooter,GOLD,1.5)
	local wfT=Instance.new("TextLabel"); wfT.BackgroundTransparency=1; wfT.Position=UDim2.fromOffset(18,7); wfT.Size=UDim2.new(1,-86,1,-14); wfT.Font=Enum.Font.GothamBold; wfT.TextScaled=true; wfT.TextColor3=Color3.new(1,1,1); wfT.TextXAlignment=Enum.TextXAlignment.Left; wfT.TextWrapped=true; wfT.Text="\xE2\xAD\x90 Need even more Coins? Grab a Coin Pack for instant progress!"; wfT.ZIndex=53; wfT.Parent=wFooter; maxsize(wfT,14)
	local wfBean=makeCoin(wFooter,48,53); wfBean.AnchorPoint=Vector2.new(1,0.5); wfBean.Position=UDim2.new(1,-14,0.5,0) -- coin mascot, held still

	for i,pk in ipairs(BEAN_PACKS) do
		local card=Instance.new("Frame"); card.LayoutOrder=i; card.ZIndex=52; card.BackgroundColor3=pk.col:Lerp(Color3.fromRGB(150,150,158),0.16); card.Parent=grid; corner(card,18); vgrad(card,pk.col:Lerp(Color3.new(1,1,1),0.22),pk.col:Lerp(Color3.new(0,0,0),0.26),90); stroke(card,pk.col:Lerp(Color3.new(1,1,1),0.30),2.5,0.05)
		local cs=Instance.new("UIScale"); cs.Parent=card
		-- unique coin pile per bundle -- more/bigger coins = more value at a glance, with a gentle bob + sparkles
		local art=Instance.new("Frame"); art.BackgroundTransparency=1; art.AnchorPoint=Vector2.new(0.5,0); art.Position=UDim2.new(0.5,0,0,6); art.Size=UDim2.new(1,-24,0,58); art.ZIndex=53; art.Parent=card
		local bob=Instance.new("Frame"); bob.BackgroundTransparency=1; bob.Size=UDim2.fromScale(1,1); bob.ZIndex=53; bob.Parent=art
		local pile=COIN_PILES[i] or COIN_PILES[1]
		for n,cd in ipairs(pile) do
			local co=makeCoin(bob, cd[3], 53+n); co.AnchorPoint=Vector2.new(0.5,0.5); co.Position=UDim2.fromScale(cd[1],cd[2]); co.Rotation=cd[4] or 0
		end
		TS:Create(bob,TweenInfo.new(1.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Position=UDim2.new(0,0,0,-3)}):Play() -- gentle 3px bob
		if i>=4 then -- tiny twinkling sparkles around the larger piles
			local nS=(i>=6 and 5) or (i>=5 and 4) or 3
			local spots={{0.12,0.24},{0.88,0.28},{0.16,0.74},{0.84,0.7},{0.5,0.1}}
			for s=1,nS do
				local sp=Instance.new("TextLabel"); sp.BackgroundTransparency=1; sp.Font=Enum.Font.GothamBold; sp.Text="\xE2\x9C\xA6"; sp.TextColor3=Color3.fromRGB(255,244,190); sp.TextSize=(s%2==0 and 13 or 9); sp.Size=UDim2.fromOffset(16,16); sp.AnchorPoint=Vector2.new(0.5,0.5); sp.Position=UDim2.fromScale(spots[s][1],spots[s][2]); sp.ZIndex=90; sp.Parent=art
				TS:Create(sp,TweenInfo.new(0.7+s*0.2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{TextTransparency=0.85}):Play()
			end
		end
		local nm=Instance.new("TextLabel"); nm.BackgroundTransparency=1; nm.Position=UDim2.fromOffset(4,66); nm.Size=UDim2.new(1,-8,0,22); nm.Font=Enum.Font.FredokaOne; nm.TextScaled=true; nm.TextColor3=Color3.new(1,1,1); nm.Text=pk.name; nm.ZIndex=53; nm.Parent=card; stroke(nm,Color3.new(0,0,0),1.5); maxsize(nm,16)
		local amt=Instance.new("TextLabel"); amt.BackgroundTransparency=1; amt.Position=UDim2.fromOffset(4,88); amt.Size=UDim2.new(1,-8,0,20); amt.Font=Enum.Font.GothamBold; amt.TextScaled=true; amt.TextColor3=GOLD; amt.Text="\xF0\x9F\xAA\x99 "..pk.beans.." Coins"; amt.ZIndex=53; amt.Parent=card; stroke(amt,Color3.new(0,0,0),1.5); maxsize(amt,15)
		if pk.bonus then
			local bb=Instance.new("TextLabel"); bb.AnchorPoint=Vector2.new(0.5,0); bb.Position=UDim2.new(0.5,0,0,112); bb.Size=UDim2.fromOffset(106,17); bb.BackgroundColor3=GREEN; bb.Font=Enum.Font.FredokaOne; bb.TextScaled=true; bb.TextColor3=Color3.new(1,1,1); bb.Text="\xF0\x9F\x8E\x81 BONUS "..pk.bonus; bb.ZIndex=53; bb.Parent=card; corner(bb,9); stroke(bb,Color3.fromRGB(28,84,44),1.5); maxsize(bb,11)
		end
		local price=Instance.new("TextLabel"); price.AnchorPoint=Vector2.new(0.5,0); price.Position=UDim2.new(0.5,0,0,135); price.Size=UDim2.fromOffset(128,24); price.BackgroundColor3=GOLD; price.Font=Enum.Font.FredokaOne; price.TextScaled=true; price.TextColor3=Color3.fromRGB(92,58,8); price.Text="\xF0\x9F\xAA\x99 "..pk.price; price.ZIndex=53; price.Parent=card; corner(price,13); stroke(price,Color3.fromRGB(180,122,20),2); vgrad(price,Color3.fromRGB(255,238,176),Color3.fromRGB(240,190,60),90); maxsize(price,16)
		local buy=Instance.new("TextButton"); buy.AnchorPoint=Vector2.new(0.5,1); buy.Position=UDim2.new(0.5,0,1,-8); buy.Size=UDim2.new(1,-24,0,36); buy.BackgroundColor3=GREEN; buy.Font=Enum.Font.FredokaOne; buy.TextScaled=true; buy.TextColor3=Color3.new(1,1,1); buy.Text="\xF0\x9F\x9B\x92 Purchase"; buy.ZIndex=53; buy.Parent=card; corner(buy,18); stroke(buy,Color3.fromRGB(46,120,68),1.5); vgrad(buy,Color3.fromRGB(142,226,160),Color3.fromRGB(86,184,112),90); pad(buy,6); maxsize(buy,16)
		local buyS=Instance.new("UIScale"); buyS.Parent=buy
		buy.MouseEnter:Connect(function() TS:Create(buyS,TweenInfo.new(0.1),{Scale=1.05}):Play() end)
		buy.MouseLeave:Connect(function() TS:Create(buyS,TweenInfo.new(0.1),{Scale=1}):Play() end)
		buy.MouseButton1Click:Connect(function()
			buyS.Scale=0.9; TS:Create(buyS,TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() -- click bounce
			if pk.productId and pk.productId ~= 0 then pcall(function() MPS:PromptProductPurchase(player, pk.productId) end)
			elseif _G.showHudBanner then _G.showHudBanner("Coin packs need Robux product ids set up first!", Color3.fromRGB(255,150,90), 3) end
		end)
		if pk.tag then -- gold ribbon for BEST VALUE, orange for MOST POPULAR, with a shimmer sweep
			local isBest=pk.tag:find("BEST")~=nil
			local ribCol=isBest and GOLD or Color3.fromRGB(248,150,56)
			local rib=Instance.new("TextLabel"); rib.AnchorPoint=Vector2.new(0.5,0); rib.Position=UDim2.new(0.5,0,0,-2); rib.Size=UDim2.fromOffset(144,17); rib.BackgroundColor3=ribCol; rib.Font=Enum.Font.FredokaOne; rib.TextScaled=true; rib.TextXAlignment=Enum.TextXAlignment.Center; rib.TextColor3=isBest and Color3.fromRGB(92,58,8) or Color3.new(1,1,1); rib.Text=pk.tag; rib.ZIndex=55; rib.Parent=card; rib.ClipsDescendants=true; corner(rib,10); stroke(rib,GOLD,1.5); maxsize(rib,12)
			local rsh=Instance.new("Frame"); rsh.BackgroundColor3=Color3.new(1,1,1); rsh.BackgroundTransparency=0.7; rsh.BorderSizePixel=0; rsh.Size=UDim2.new(0.25,0,1,0); rsh.Position=UDim2.new(-0.3,0,0,0); rsh.ZIndex=56; rsh.Parent=rib
			local rshg=Instance.new("UIGradient",rsh); rshg.Rotation=16; rshg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,0.3),NumberSequenceKeypoint.new(1,1)})
			task.spawn(function() while rsh.Parent do rsh.Position=UDim2.new(-0.3,0,0,0); TS:Create(rsh,TweenInfo.new(1.1,Enum.EasingStyle.Sine),{Position=UDim2.new(1.05,0,0,0)}):Play(); task.wait(3.2) end end)
		end
		card.MouseEnter:Connect(function() TS:Create(cs,TweenInfo.new(0.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.06}):Play() end)
		card.MouseLeave:Connect(function() TS:Create(cs,TweenInfo.new(0.12),{Scale=1}):Play() end)
	end

	-- Coin shop REPLACES the main shop: hide all main-shop content, scale the coin shop in. Reverse on close.
	local hiddenEls = {}
	local function openCurrency()
		table.clear(hiddenEls)
		for _, ch in ipairs(premCard:GetChildren()) do
			if ch:IsA("GuiObject") and ch.Visible then ch.Visible = false; table.insert(hiddenEls, ch) end
		end
		overlay.Visible = true; winScale.Scale = 0.9
		TS:Create(winScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end
	local function closeCurrency()
		local t = TS:Create(winScale, TweenInfo.new(0.16), {Scale = 0.9}); t:Play()
		t.Completed:Connect(function()
			overlay.Visible = false
			for _, ch in ipairs(hiddenEls) do if ch and ch.Parent then ch.Visible = true end end
			table.clear(hiddenEls)
		end)
	end
	-- safety: if the whole shop is closed while the coin shop is open, reset so it reopens on the main page
	PremiumShopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not PremiumShopGui.Enabled and overlay.Visible then
			overlay.Visible = false
			for _, ch in ipairs(hiddenEls) do if ch and ch.Parent then ch.Visible = true end end
			table.clear(hiddenEls)
		end
	end)
	xBtn.MouseButton1Click:Connect(closeCurrency)

	----------------------------------------------------------------
	-- the featured BANNER (below the header, above the gamepasses)
	----------------------------------------------------------------
	local banner=Instance.new("TextButton"); banner.Name="CurrencyBanner"; banner.AutoButtonColor=false; banner.Text=""; banner.ClipsDescendants=true
	banner.AnchorPoint=Vector2.new(0.5,0); banner.Position=UDim2.new(0.5,0,0,74); banner.Size=UDim2.new(1,-16,0,60); banner.BackgroundColor3=Color3.fromRGB(88,104,224); banner.ZIndex=6; banner.Parent=premCard; corner(banner,16); vgrad(banner,Color3.fromRGB(104,132,248),Color3.fromRGB(128,80,224),25); stroke(banner,GOLD,2.5)
	local bScale=Instance.new("UIScale"); bScale.Parent=banner
	-- coin pile art
	local beanBack=makeCoin(banner,28,6); beanBack.Position=UDim2.fromOffset(12,28)
	local beanBack2=makeCoin(banner,24,6); beanBack2.Position=UDim2.fromOffset(46,32)
	local coin=makeCoin(banner,22,7); coin.Position=UDim2.fromOffset(4,6)
	local coin2=makeCoin(banner,16,7); coin2.Position=UDim2.fromOffset(58,10)
	local beanMain=makeCoin(banner,58,8); beanMain.Position=UDim2.fromOffset(24,3)
	local bTitle=Instance.new("TextLabel"); bTitle.BackgroundTransparency=1; bTitle.Position=UDim2.fromOffset(94,4); bTitle.Size=UDim2.new(1,-266,0,24); bTitle.Font=Enum.Font.FredokaOne; bTitle.TextScaled=true; bTitle.TextColor3=GOLD; bTitle.TextXAlignment=Enum.TextXAlignment.Left; bTitle.Text="\xF0\x9F\x92\xB0 BUY COINS"; bTitle.ZIndex=7; bTitle.Parent=banner; stroke(bTitle,Color3.fromRGB(30,16,60),1.5); maxsize(bTitle,24)
	local bSub=Instance.new("TextLabel"); bSub.BackgroundTransparency=1; bSub.Position=UDim2.fromOffset(94,31); bSub.Size=UDim2.new(1,-266,0,13); bSub.Font=Enum.Font.Gotham; bSub.TextScaled=true; bSub.TextColor3=Color3.new(1,1,1); bSub.TextXAlignment=Enum.TextXAlignment.Left; bSub.Text="Get more Coins instantly!"; bSub.ZIndex=7; bSub.Parent=banner; maxsize(bSub,13)
	local bBadge=Instance.new("TextLabel"); bBadge.BackgroundColor3=GOLD; bBadge.Position=UDim2.fromOffset(94,45); bBadge.Size=UDim2.fromOffset(186,13); bBadge.Font=Enum.Font.FredokaOne; bBadge.TextScaled=true; bBadge.TextColor3=Color3.fromRGB(92,58,8); bBadge.Text="\xE2\xAD\x90 Best Way to Progress!"; bBadge.ZIndex=7; bBadge.Parent=banner; corner(bBadge,8); stroke(bBadge,Color3.fromRGB(180,122,20),1.5); maxsize(bBadge,12)
	local openBtn=Instance.new("TextButton"); openBtn.AnchorPoint=Vector2.new(1,0.5); openBtn.Position=UDim2.new(1,-12,0.5,0); openBtn.Size=UDim2.fromOffset(172,48); openBtn.BackgroundColor3=GREEN; openBtn.Font=Enum.Font.FredokaOne; openBtn.TextScaled=true; openBtn.TextColor3=Color3.new(1,1,1); openBtn.Text="OPEN SHOP \xE2\x9E\x9C"; openBtn.ZIndex=7; openBtn.Parent=banner; corner(openBtn,12); stroke(openBtn,Color3.fromRGB(28,84,44),2.5); juice(openBtn); pad(openBtn,6); maxsize(openBtn,18)
	do -- shimmer sweep
		local shine=Instance.new("Frame"); shine.BackgroundColor3=Color3.new(1,1,1); shine.BackgroundTransparency=0.86; shine.BorderSizePixel=0; shine.Size=UDim2.new(0.18,0,1,0); shine.Position=UDim2.new(-0.25,0,0,0); shine.ZIndex=6; shine.Parent=banner
		local sgr=Instance.new("UIGradient",shine); sgr.Rotation=18; sgr.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.5,0.25),NumberSequenceKeypoint.new(1,1)})
		task.spawn(function() while shine.Parent do shine.Position=UDim2.new(-0.25,0,0,0); TS:Create(shine,TweenInfo.new(1.3,Enum.EasingStyle.Sine),{Position=UDim2.new(1.1,0,0,0)}):Play(); task.wait(3.4) end end)
	end
	local function hoverIn() TS:Create(bScale,TweenInfo.new(0.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.03}):Play() end
	local function hoverOut() TS:Create(bScale,TweenInfo.new(0.12),{Scale=1}):Play() end
	banner.MouseEnter:Connect(hoverIn); banner.MouseLeave:Connect(hoverOut); openBtn.MouseEnter:Connect(hoverIn); openBtn.MouseLeave:Connect(hoverOut)
	local function popOpen()
		bScale.Scale=0.94; TS:Create(bScale,TweenInfo.new(0.16,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
		openCurrency()
	end
	banner.MouseButton1Click:Connect(popOpen); openBtn.MouseButton1Click:Connect(popOpen)
end)
end

--======================================================================
-- 7) WIRING: the SHOP button toggles the panel; X closes it
--======================================================================
local function toggleShop()
	if PremiumShopGui.Enabled then
		PremiumShopGui.Enabled = false; _G.MainMenuManager.notifyClosed("Premium")
	else
		_G.MainMenuManager.notifyOpened("Premium"); PremiumShopGui.Enabled = true
	end
end
_G.toggleShopKit = toggleShop -- so a realm's own sidebar button can call it

-- The hook the old panel published, kept alive under the same name so anything that opened the
-- shop from outside still can. Bootstrap's SHOP button and coin "+" do NOT come through here --
-- they call toggleMainMenu("Premium", "PremiumShopGui") and find this GUI by name.
_G.OpenPremiumShop = function()
	if _G.MainMenuManager then _G.MainMenuManager.notifyOpened("Premium") end
	PremiumShopGui.Enabled = true
end

if shopSideClick then
	shopSideClick.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		toggleShop()
	end)
end
premClose.MouseButton1Click:Connect(function()
	if _G.playUIClick then pcall(_G.playUIClick) end
	PremiumShopGui.Enabled=false
	_G.MainMenuManager.notifyClosed("Premium")
end)
-- NOTE: deliberately NO backdrop-click close. The X button is the only way to shut the panel --
-- a stray screen tap must never close it. (The full-screen frame is Active=false on purpose, so a
-- click outside falls through to the HUD menu buttons and switches menus directly.)

--======================================================================
-- 8) GAMEPASS "OWNED" STATE
-- For the two PERMANENT gamepasses only (cards 1 & 2): once owned, the buy
-- button becomes a non-clickable "✓ OWNED". Ownership comes from
-- _G.playerGamepasses (server-set) when present; otherwise this asks
-- MarketplaceService directly so it works with no server wiring at all.
-- The dev products (2x 1-hour, Mid-Air, Skip Island, Meteorite Explosion) are
-- repeatable and intentionally NOT affected.
--======================================================================
do
	local ownedLocal = { twoXForever=false, glitterTrail=false }
	local function setOwned(btn, owned, buyColor)
		if not btn then return end
		if owned then
			btn.Text = "\xe2\x9c\x93 OWNED"            -- ✓ OWNED
			btn.BackgroundColor3 = Color3.fromRGB(70,70,70)
			btn.AutoButtonColor = false
			btn.Active = false                          -- not clickable (purchase is also guarded in onClick)
		else
			btn.Text = "BUY GAMEPASS"
			btn.BackgroundColor3 = buyColor
			btn.AutoButtonColor = true
			btn.Active = true
		end
	end
	-- THE REAL SOURCE OF TRUTH IN THIS REALM IS THE PLAYER ATTRIBUTE.
	-- PurchaseReceipts.server.luau sets HasTwoXForever / HasGlitterTrail on join (applyOwnedGamepasses)
	-- and the moment a pass is bought. _G.playerGamepasses -- the table the kit was written against --
	-- is initialised to all-false by ShopGlue and then never written, so on its own every card here
	-- would read NOT OWNED forever, which is exactly what the panel this replaced did: a player who
	-- already owned 2x Power Forever was still shown a BUY GAMEPASS button.
	local function refreshOwned()
		local gp = _G.playerGamepasses
		local own2x = player:GetAttribute("HasTwoXForever") == true
			or (gp and gp.twoXForever == true) or ownedLocal.twoXForever
		local ownGl = player:GetAttribute("HasGlitterTrail") == true
			or (gp and gp.glitterTrail == true) or ownedLocal.glitterTrail
		-- Both BUY GAMEPASS buttons are the same orange after the restyle, so restore to that when not owned.
		setOwned(btn1, own2x, Color3.fromRGB(255,160,20))
		setOwned(btn2, ownGl, Color3.fromRGB(255,160,20))
	end
	player:GetAttributeChangedSignal("HasTwoXForever"):Connect(refreshOwned)
	player:GetAttributeChangedSignal("HasGlitterTrail"):Connect(refreshOwned)
	refreshOwned() -- initial (covers ownership already received on join)

	-- Live: the server's GamepassEvent handler updates _G.playerGamepasses first; defer so we read the
	-- updated value, then flip the card to OWNED immediately.
	local GamepassEvent = ReplicatedStorage:FindFirstChild("GamepassEvent")
	if GamepassEvent and GamepassEvent:IsA("RemoteEvent") then
		GamepassEvent.OnClientEvent:Connect(function() task.defer(refreshOwned) end)
	end

	-- Standalone fallback: ask Roblox directly (works with zero server code), then keep it live off
	-- PromptGamePassPurchaseFinished so a fresh purchase flips the card without a rejoin.
	task.spawn(function()
		local ok1, has1 = pcall(function() return MPS:UserOwnsGamePassAsync(player.UserId, GAMEPASS_IDS.TwoXForever) end)
		if ok1 then ownedLocal.twoXForever = has1 == true end
		local ok2, has2 = pcall(function() return MPS:UserOwnsGamePassAsync(player.UserId, GAMEPASS_IDS.GlitterTrail) end)
		if ok2 then ownedLocal.glitterTrail = has2 == true end
		refreshOwned()
	end)
	MPS.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
		if plr ~= player or not wasPurchased then return end
		if passId == GAMEPASS_IDS.TwoXForever  then ownedLocal.twoXForever  = true end
		if passId == GAMEPASS_IDS.GlitterTrail then ownedLocal.glitterTrail = true end
		refreshOwned()
	end)

	-- Safety net: re-check every second so the card stays correct regardless of event timing.
	task.spawn(function() while true do task.wait(1); refreshOwned() end end)
end

--======================================================================
-- 9) MOBILE SCALING  (the SHOP's exact pass, scoped to this kit's GUIs)
-- Phone caps at 0.60, tablet/iPad scales up to 2.5, desktop is exactly 1.
-- Each non-full-screen cluster gets its OWN UIScale so it shrinks about its
-- own AnchorPoint and stays pinned to its screen edge.
--======================================================================
local function getScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X <= 1 or vp.Y <= 1 then return isMobile and 0.60 or 1 end -- boot: viewport not valid yet
	if isMobile then
		-- iPhone SE/8 landscape reference (1100x590), clamped by device CLASS (viewport short axis).
		local deviceMax = (math.min(vp.X, vp.Y) >= 800) and 2.5 or 0.60
		return math.clamp(math.min(vp.X / 1100, vp.Y / 590), 0.55, deviceMax)
	end
	return 1
end

local function applyShopScaling()
	local s = getScale()
	local guis = { PremiumShopGui }
	if shopSideFrame then table.insert(guis, shopSideFrame.Parent) end
	for _, gui in ipairs(guis) do
		if gui and gui:IsA("ScreenGui") then
			local function scaleNode(child)
				if not child:IsA("GuiObject") then return end
				if child.Size.X.Scale >= 1 and child.Size.Y.Scale >= 1 then
					for _, gc in ipairs(child:GetChildren()) do scaleNode(gc) end -- recurse into a full-screen cover
				else
					local us = child:FindFirstChildWhichIsA("UIScale")
					if not us then us = Instance.new("UIScale"); us.Parent = child end
					us.Scale = s
				end
			end
			for _, child in ipairs(gui:GetChildren()) do scaleNode(child) end
		end
	end
	-- rail button: phone raises the stack 30px to clear the joystick (y66); tablet/desktop keep y96
	if shopSideFrame then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
		local phoneClass = isMobile and math.min(vp.X, vp.Y) < 800
		local topY = (phoneClass and CONFIG.shopButtonY == 96) and 66 or CONFIG.shopButtonY
		shopSideFrame.Size = UDim2.new(0,95,0,95); shopSideFrame.AnchorPoint = Vector2.new(0,0)
		shopSideFrame.Position = UDim2.new(0, 12, 0, topY)
	end
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyShopScaling)
end
applyShopScaling()
task.delay(3, applyShopScaling)

print(("[ShopKit] PremiumShopGui built -- 770x572 panel, 6 cards, coin banner=%s, own rail button=%s")
	:format(tostring(CONFIG.showCoinBanner), tostring(CONFIG.buildShopButton)))
