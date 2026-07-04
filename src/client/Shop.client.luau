print("SHOPCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local PlayerGui = player.PlayerGui
local MPS = MarketplaceService
local GAMEPASS_IDS = {TwoXForever=1862015450, GlitterTrail=1859714979}
local PRODUCT_IDS = {TwoXOneHour=3600302990, MidAirRecharge=3600303163, SkipIsland=3600303265, MeteoriteExplosion=3606893853}
-- Shared coin icon IMAGE: the SAME verified asset used by the coin counter and daily-rewards
-- icons (emoji glyphs like 🪙 don't render in Roblox text). Literal here so it's correct
-- regardless of script load order. Shop prices show this image instead of the missing emoji.
local COIN_IMAGE = "rbxassetid://106760789458573"

local shopOpen = false
local playerClosedShop = false
local nearIslandNumber = 1
local unlockedIslands = {[1]=true}
local stands = {}
local lastAwayTime = 0
local STAND_TRIGGER_RADIUS = 12 -- studs: how close (horizontally) the player must walk to a stand before its shop opens (was 15 original -> 9 reduced -> 12 midpoint)

local function isUnlocked(islandNum)
	if unlockedIslands[islandNum] then
		return true
	end
	if _G.unlockedIslands and _G.unlockedIslands[islandNum] then
		unlockedIslands[islandNum] = true
		return true
	end
	return false
end

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end
local function mkButton(p,props) local b=Instance.new("TextButton"); for k,v in pairs(props) do b[k]=v end; b.Parent=p; return b end

local foodEmojis = {
	Eggs="\xF0\x9F\xA5\x9A", Lettuce="\xF0\x9F\xA5\xAC", Bananas="\xF0\x9F\x8D\x8C",
	Fish="\xF0\x9F\x90\x9F", Ribs="\xF0\x9F\x8D\x96", Mushrooms="\xF0\x9F\x8D\x84",
	Apples="\xF0\x9F\x8D\x8E", Chicken="\xF0\x9F\x8D\x97", ["Chili Peppers"]="\xF0\x9F\x8C\xB6\xEF\xB8\x8F",
	Potatoes="\xF0\x9F\xA5\x94", Steak="\xF0\x9F\xA5\xA9", Grapes="\xF0\x9F\x8D\x87",
	Popcorn="\xF0\x9F\x8D\xBF", ["Turkey Legs"]="\xF0\x9F\x8D\x96"
}

-- REAL uploaded image icons (override the emoji placeholder). For any food NOT in this table the
-- emoji from foodEmojis above is used. The food icons were always emoji TEXT, not images -- Beans
-- showed the 🥜 PEANUT emoji as a stand-in because the bean emoji 🫘 doesn't render in Roblox's font.
-- A food listed here renders its image (ImageLabel.Image) instead of the emoji TextLabel.
local foodImages = {
	Beans = "rbxassetid://133231198126712", -- uploaded bean icon (replaces the 🥜 peanut placeholder)
}

-- Per-food image SCALE (fraction of the normal icon box). Image icons fill the box edge-to-edge, so
-- they read bigger than emoji glyphs (which have built-in whitespace). A value < 1 shrinks ONLY that
-- food's image within its slot (kept centered, so the reduction becomes even padding). Unlisted = 1.0.
local foodImageScale = {
	Beans = 0.8, -- bean icon: 20% smaller, centered in its slot
}

local sg


-- Food Shop
sg=Instance.new("ScreenGui"); sg.Name="FoodShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
local FoodShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false}) -- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (enables direct click-to-switch). The panel itself is Active so panel clicks don't leak to the HUD.
local foodPanel=mkFrame(sg,{Size=UDim2.new(0.92,0,0.78,0),Position=UDim2.new(0.5,0,0.5,-45),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(240,248,255),Active=true}) -- nudged UP ~45px so its bottom clears the stomach/gut indicator below; Active=true blocks pass-through behind the panel
mkCorner(foodPanel,16); mkStroke(foodPanel,Color3.fromRGB(100,180,255),4)
local foodHeader=mkFrame(foodPanel,{Size=UDim2.new(1,0,0,55),BackgroundColor3=Color3.fromRGB(80,160,255)}); mkCorner(foodHeader,16)
local foodTitle=mkLabel(foodHeader,{Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND 1 FOOD STAND",Font=Enum.Font.Gotham,TextSize=24,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,1,0),RichText=true})
mkStroke(foodTitle,Color3.new(0,0,0),2)
local foodCloseBtn=mkButton(foodHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-45,0,7),BackgroundColor3=Color3.fromRGB(255,60,60),Text="X",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)}); mkCorner(foodCloseBtn,8)
local foodLeftPanel=mkFrame(foodPanel,{Size=UDim2.new(0,280,1,-65),Position=UDim2.new(0,10,0,65),BackgroundColor3=Color3.new(1,1,1)}); mkCorner(foodLeftPanel,12)
local foodEmoji=Instance.new("TextLabel")
foodEmoji.Name="FoodEmoji"; foodEmoji.Size=UDim2.new(0,120,0,120)
foodEmoji.Position=UDim2.new(0.5,-60,0,10); foodEmoji.BackgroundTransparency=1
foodEmoji.Text="\xF0\x9F\xA5\x9C"; foodEmoji.TextSize=80; foodEmoji.Font=Enum.Font.Gotham
foodEmoji.RichText=false; foodEmoji.TextScaled=false
foodEmoji.TextXAlignment=Enum.TextXAlignment.Center; foodEmoji.TextYAlignment=Enum.TextYAlignment.Center
foodEmoji.Parent=foodLeftPanel
-- IMAGE-ICON overlay for foods that have a real uploaded image (e.g. Beans). Same box as foodEmoji;
-- updateFoodShop shows exactly ONE of them (this image if foodImages[name], else the emoji text).
local foodEmojiImg=Instance.new("ImageLabel"); foodEmojiImg.Name="FoodEmojiImg"
foodEmojiImg.AnchorPoint=Vector2.new(0.5,0.5); foodEmojiImg.Position=UDim2.new(0.5,0,0,70); foodEmojiImg.Size=UDim2.new(0,120,0,120) -- centered in the 120px icon box; updateFoodShop applies the per-food scale
foodEmojiImg.BackgroundTransparency=1; foodEmojiImg.ScaleType=Enum.ScaleType.Fit; foodEmojiImg.Visible=false; foodEmojiImg.Parent=foodLeftPanel
local foodName=mkLabel(foodLeftPanel,{Text="Beans",Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(1,-10,0,35),Position=UDim2.new(0,5,0,135),TextXAlignment=Enum.TextXAlignment.Center})
-- Price row: a centered [coin IMAGE][price text] pair (replaces the non-rendering 🪙 emoji
-- prefix). foodPrice stays the price TextLabel so the live update below works unchanged.
local foodPriceRow=mkFrame(foodLeftPanel,{Name="PriceRow",Size=UDim2.new(1,-10,0,28),Position=UDim2.new(0,5,0,174),BackgroundTransparency=1})
local fprLayout=Instance.new("UIListLayout"); fprLayout.FillDirection=Enum.FillDirection.Horizontal
fprLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center; fprLayout.VerticalAlignment=Enum.VerticalAlignment.Center
fprLayout.Padding=UDim.new(0,4); fprLayout.SortOrder=Enum.SortOrder.LayoutOrder; fprLayout.Parent=foodPriceRow
local foodPriceIcon=Instance.new("ImageLabel"); foodPriceIcon.Name="CoinIcon"; foodPriceIcon.LayoutOrder=1
foodPriceIcon.Size=UDim2.new(0,22,0,22); foodPriceIcon.BackgroundTransparency=1
foodPriceIcon.Image=COIN_IMAGE; foodPriceIcon.ScaleType=Enum.ScaleType.Fit; foodPriceIcon.Parent=foodPriceRow
local foodPrice=mkLabel(foodPriceRow,{Name="PriceText",Text="10 coins",Font=Enum.Font.Gotham,TextSize=20,TextColor3=Color3.fromRGB(200,140,0),Size=UDim2.new(0,150,1,0),TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=2})
local foodPower=mkLabel(foodLeftPanel,{Text="+3 power",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(0,160,60),Size=UDim2.new(1,-10,0,26),Position=UDim2.new(0,5,0,206),TextXAlignment=Enum.TextXAlignment.Center})
-- (Gas-restored + Owned rows REMOVED from the featured display. Name/price/power remain above; the
-- buy buttons remain pinned to the bottom -- nothing else needs to shift, the rows were the lowest stats.)
local foodBuyBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.04,0,1,-58),BackgroundColor3=Color3.fromRGB(50,200,50),Text="BUY FOOD",Font=Enum.Font.GothamBold,TextSize=17,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyBtn,12)
local foodBuyMaxBtn=mkButton(foodLeftPanel,{Size=UDim2.new(0.44,0,0,50),Position=UDim2.new(0.52,0,1,-58),BackgroundColor3=Color3.fromRGB(255,140,0),Text="BUY MAX",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.new(1,1,1)}); mkCorner(foodBuyMaxBtn,12)
local foodLockedFrame=mkFrame(foodLeftPanel,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.fromRGB(240,240,240),Visible=false}); mkCorner(foodLockedFrame,12)
mkLabel(foodLockedFrame,{Text="\xF0\x9F\x94\x92",Font=Enum.Font.Gotham,TextSize=64,Size=UDim2.new(0,100,0,100),Position=UDim2.new(0.5,-50,0,40),RichText=true})
mkLabel(foodLockedFrame,{Text="Fly here to unlock!",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.fromRGB(200,0,0),Size=UDim2.new(1,-20,0,60),Position=UDim2.new(0,10,0,155),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center})
local foodRight=mkFrame(foodPanel,{Size=UDim2.new(1,-300,1,-65),Position=UDim2.new(0,300,0,65),BackgroundColor3=Color3.fromRGB(248,248,248)}); mkCorner(foodRight,12)
mkLabel(foodRight,{Text="ALL FOODS",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(50,50,50),Size=UDim2.new(1,-10,0,25),Position=UDim2.new(0,5,0,5)})
local foodScroll=Instance.new("ScrollingFrame"); foodScroll.Size=UDim2.new(1,-10,1,-35); foodScroll.Position=UDim2.new(0,5,0,30); foodScroll.BackgroundTransparency=1; foodScroll.ScrollBarThickness=6; foodScroll.CanvasSize=UDim2.new(0,0,0,0); foodScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; foodScroll.Parent=foodRight
local foodGrid=Instance.new("UIGridLayout"); foodGrid.CellSize=UDim2.new(0,155,0,70); foodGrid.CellPadding=UDim2.new(0,6,0,6); foodGrid.Parent=foodScroll
local foodCells={}
for _,f in ipairs(_G.foods) do
	local cell=mkFrame(foodScroll,{Name=f.name,BackgroundColor3=Color3.fromRGB(200,240,200)}); mkCorner(cell,8); mkStroke(cell,Color3.fromRGB(150,200,150),2)
	local emojiFrame=Instance.new("Frame"); emojiFrame.Name="EmojiFrame"
	emojiFrame.Size=UDim2.new(0,55,0,55); emojiFrame.Position=UDim2.new(0,2,0.5,0); emojiFrame.AnchorPoint=Vector2.new(0,0.5)
	emojiFrame.BackgroundTransparency=1; emojiFrame.ClipsDescendants=false; emojiFrame.Parent=cell
	local emojiLabel=Instance.new("TextLabel"); emojiLabel.Name="FoodEmoji"
	emojiLabel.Size=UDim2.new(0,50,0,50); emojiLabel.Position=UDim2.new(0.5,0,0.5,0); emojiLabel.AnchorPoint=Vector2.new(0.5,0.5)
	emojiLabel.BackgroundTransparency=1; emojiLabel.Text=foodEmojis[f.name] or "\xF0\x9F\x8D\xBD\xEF\xB8\x8F"
	emojiLabel.TextSize=34; emojiLabel.Font=Enum.Font.Gotham; emojiLabel.RichText=false
	emojiLabel.TextColor3=Color3.fromRGB(255,255,255)
	emojiLabel.TextXAlignment=Enum.TextXAlignment.Center; emojiLabel.TextYAlignment=Enum.TextYAlignment.Center
	emojiLabel.Parent=emojiFrame
	-- Image-icon overlay in the cell (used instead of the emoji for foods in foodImages, e.g. Beans).
	local iconImg=Instance.new("ImageLabel"); iconImg.Name="FoodIconImg"
	local iScale=foodImageScale[f.name] or 1
	iconImg.Size=UDim2.new(0,50*iScale,0,50*iScale); iconImg.Position=UDim2.new(0.5,0,0.5,0); iconImg.AnchorPoint=Vector2.new(0.5,0.5) -- per-food shrink, centered
	iconImg.BackgroundTransparency=1; iconImg.ScaleType=Enum.ScaleType.Fit
	iconImg.Image=foodImages[f.name] or ""; iconImg.Visible=(foodImages[f.name]~=nil); iconImg.Parent=emojiFrame
	if foodImages[f.name] then emojiLabel.Visible=false end
	mkLabel(cell,{Name="NameLabel",Text=f.name,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.fromRGB(30,30,30),Size=UDim2.new(1,-62,0,30),Position=UDim2.new(0,60,0,5),TextXAlignment=Enum.TextXAlignment.Left})
	-- Coin IMAGE for the cell's price row (replaces the 🪙 emoji prefix). Toggled with the
	-- price text in updateFoodShop (hidden for locked cells, shown for unlocked/priced cells).
	local priceIcon=Instance.new("ImageLabel"); priceIcon.Name="PriceIcon"
	priceIcon.Size=UDim2.new(0,14,0,14); priceIcon.Position=UDim2.new(0,60,0,41); priceIcon.BackgroundTransparency=1
	priceIcon.Image=COIN_IMAGE; priceIcon.ScaleType=Enum.ScaleType.Fit; priceIcon.Parent=cell
	mkLabel(cell,{Name="PriceLabel",Text=tostring(f.price),Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(120,80,0),Size=UDim2.new(1,-80,0,20),Position=UDim2.new(0,78,0,38),TextXAlignment=Enum.TextXAlignment.Left})
	foodCells[f.name]=cell
end
print("ICON FIX DONE")

-- Premium Shop
sg=Instance.new("ScreenGui"); sg.Name="PremiumShopGui"; sg.ResetOnSpawn=false; sg.Enabled=false; sg.DisplayOrder=100; sg.Parent=PlayerGui -- DisplayOrder 100 = definitively above the HUD (<=5) so the shop covers it
local PremiumShopGui=sg
mkFrame(sg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Active=false}) -- invisible + Active=FALSE so clicks OUTSIDE the panel fall through to the HUD MENU BUTTONS (direct click-to-switch)
local premPanel=mkFrame(sg,{Size=UDim2.new(0.9,0,0.85,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(25,90,185),ClipsDescendants=true,Active=true})
mkCorner(premPanel,20); mkStroke(premPanel,Color3.new(1,1,1),3)

local premHeader=mkFrame(premPanel,{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(15,60,140)})
local premTitleLbl=mkLabel(premHeader,{Text="\xF0\x9F\x9B\x92 SHOP",Font=Enum.Font.GothamBold,TextSize=30,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-60,0,40),Position=UDim2.new(0,14,0,5),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
mkStroke(premTitleLbl,Color3.new(0,0,0),2)
mkLabel(premHeader,{Text="Power up your farts!",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-60,0,18),Position=UDim2.new(0,14,0,45),TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1})
local premClose=mkButton(premHeader,{Size=UDim2.new(0,40,0,40),Position=UDim2.new(1,-48,0,12),BackgroundColor3=Color3.fromRGB(220,50,50),Text="\xe2\x9c\x95",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1)})
mkCorner(premClose,8)

-- ===== GAMEPASS SHOP CONTENTS -- proper LAYOUTS (no absolute positions): a vertical scroll holds two
-- sections; each section CENTERS its 3 cards with a horizontal UIListLayout; each card STACKS its content
-- with a vertical UIListLayout and pins the BUY button to the bottom. So every card is uniform, evenly
-- spaced, centered + aligned, comfortably sized, and the list scrolls so nothing is ever cut off. =====
local premScroll=Instance.new("ScrollingFrame")
premScroll.Name="PremiumScroll"; premScroll.BackgroundTransparency=1; premScroll.BorderSizePixel=0
premScroll.Position=UDim2.new(0,0,0,65); premScroll.Size=UDim2.new(1,0,1,-92) -- below the 65px header, above the footer
premScroll.ScrollBarThickness=6; premScroll.ScrollBarImageColor3=Color3.fromRGB(255,215,0)
premScroll.CanvasSize=UDim2.new(0,0,0,0); premScroll.ScrollingDirection=Enum.ScrollingDirection.Y
premScroll.AutomaticCanvasSize=Enum.AutomaticSize.None; premScroll.Parent=premPanel -- canvas is driven explicitly by syncCanvas below
do
	local sll=Instance.new("UIListLayout"); sll.FillDirection=Enum.FillDirection.Vertical
	sll.HorizontalAlignment=Enum.HorizontalAlignment.Center; sll.Padding=UDim.new(0,10); sll.SortOrder=Enum.SortOrder.LayoutOrder; sll.Parent=premScroll
	local slp=Instance.new("UIPadding"); slp.PaddingTop=UDim.new(0,8); slp.PaddingBottom=UDim.new(0,10); slp.Parent=premScroll
	-- CANVAS = total content height so scrolling reaches every card. We drive CanvasSize EXPLICITLY from the
	-- layout's measured content size (self-updating) -- the reliable equivalent of AutomaticCanvasSize=Y, so the
	-- canvas always grows past the viewport and the scroll actually moves through ALL the items.
	local function syncCanvas() premScroll.CanvasSize=UDim2.new(0,0,0, sll.AbsoluteContentSize.Y + 18) end
	sll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas); task.defer(syncCanvas)
end
local CARD_W, CARD_H = 208, 190
-- a gold section title + underline, sized to sit in the vertical scroll list
local function sectionHeader(text,order)
	local h=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,28),BackgroundTransparency=1,LayoutOrder=order})
	mkLabel(h,{Text=text,Font=Enum.Font.GothamBold,TextSize=16,TextColor3=Color3.fromRGB(255,215,0),Size=UDim2.new(1,-8,0,22),Position=UDim2.new(0,4,0,0),TextXAlignment=Enum.TextXAlignment.Left})
	mkFrame(h,{Size=UDim2.new(1,-8,0,2),Position=UDim2.new(0,4,0,25),BackgroundColor3=Color3.fromRGB(255,215,0)})
	return h
end
-- a full-width row that evenly spaces + centers its cards
local function mkSectionRow(order)
	local row=mkFrame(premScroll,{Size=UDim2.new(1,-16,0,CARD_H),BackgroundTransparency=1,LayoutOrder=order})
	local ll=Instance.new("UIListLayout"); ll.FillDirection=Enum.FillDirection.Horizontal
	ll.HorizontalAlignment=Enum.HorizontalAlignment.Center; ll.VerticalAlignment=Enum.VerticalAlignment.Top
	ll.Padding=UDim.new(0,18); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=row
	return row
end
-- a uniform card whose ENTIRE content is one vertical UIListLayout: icon -> name -> price -> [desc] -> BUY,
-- top to bottom in that order. The BUY button is the LAST list item, so it ALWAYS sits below the icon/text --
-- it can never overlap them. UIPadding leaves room at the top for card 1's "BEST VALUE" badge overlay.
local function mkShopCard(parent,order)
	local c=mkFrame(parent,{Size=UDim2.new(0,CARD_W,0,CARD_H),LayoutOrder=order,BackgroundColor3=Color3.fromRGB(20,70,160)})
	mkCorner(c,16); mkStroke(c,Color3.new(1,1,1),2)
	local holder=mkFrame(c,{Name="Content",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1})
	local hl=Instance.new("UIListLayout"); hl.FillDirection=Enum.FillDirection.Vertical
	hl.HorizontalAlignment=Enum.HorizontalAlignment.Center; hl.VerticalAlignment=Enum.VerticalAlignment.Top
	hl.Padding=UDim.new(0,3); hl.SortOrder=Enum.SortOrder.LayoutOrder; hl.Parent=holder
	local hp=Instance.new("UIPadding"); hp.PaddingTop=UDim.new(0,18); hp.PaddingBottom=UDim.new(0,6); hp.PaddingLeft=UDim.new(0,8); hp.PaddingRight=UDim.new(0,8); hp.Parent=holder
	return c
end
local function cH(card) return card:FindFirstChild("Content") or card end -- the content list holder
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
	mkLabel(cH(card),{Text=desc,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(180,210,255),Size=UDim2.new(1,0,0,20),LayoutOrder=5,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top})
end
-- BUY button: last list item (LayoutOrder 10) -> always rendered BELOW the icon/name/price, never overlapping
local function cardBuyBtn(card,col,txt,onClick)
	local btn=mkButton(cH(card),{Size=UDim2.new(1,0,0,32),LayoutOrder=10,BackgroundColor3=col,Text=txt,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1)})
	mkCorner(btn,8); btn.MouseButton1Click:Connect(onClick); return btn
end
sectionHeader("\xe2\xad\x90 GAMEPASSES",1)
local gamepassRow=mkSectionRow(2)

-- Card 1: 2x Power Forever
local card1=mkShopCard(gamepassRow,1)
local gpBadge=mkLabel(card1,{Text="BEST VALUE \xe2\xad\x90",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(80,40,0),Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0.5,0,0,3),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(255,180,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3})
mkCorner(gpBadge,6)
cardIcon(card1,"\xe2\x9a\xa1"); cardTitles(card1,"2x Power","FOREVER",Color3.fromRGB(100,220,100)); cardPrice(card1,"249 R$")
local btn1=cardBuyBtn(card1,Color3.fromRGB(255,180,0),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.twoXForever then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.TwoXForever) end)
end)
mkStroke(btn1,Color3.fromRGB(200,130,0),2)

-- Card 2: Glitter Trail
local card2=mkShopCard(gamepassRow,2)
cardIcon(card2,"\xe2\x9c\xa8"); cardTitles(card2,"Glitter Trail","PERMANENT",Color3.fromRGB(100,220,100)); cardPrice(card2,"49 R$")
local btn2=cardBuyBtn(card2,Color3.fromRGB(220,80,180),"BUY GAMEPASS",function()
	if _G.playerGamepasses and _G.playerGamepasses.glitterTrail then return end -- already owned: do nothing
	pcall(function() MPS:PromptGamePassPurchase(player,GAMEPASS_IDS.GlitterTrail) end)
end)

-- Card 3: 2x Power 1 Hour
local card3=mkShopCard(gamepassRow,3)
cardIcon(card3,"\xe2\x8f\xb0"); cardTitles(card3,"2x Power","1 HOUR",Color3.fromRGB(255,200,100)); cardPrice(card3,"59 R$")
local twoXShopTimer=mkLabel(cH(card3),{Text="",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(100,220,100),Size=UDim2.new(1,-8,0,14),LayoutOrder=6,TextXAlignment=Enum.TextXAlignment.Center,Visible=false})
cardBuyBtn(card3,Color3.fromRGB(50,150,255),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.TwoXOneHour) end) end)

sectionHeader("\xF0\x9F\x8E\xAF ONE-TIME ITEMS",3)
local productRow=mkSectionRow(4)

-- Card 4: Mid-Air Recharge
local card4=mkShopCard(productRow,1)
cardIcon(card4,"\xF0\x9F\x94\x8B"); cardTitles(card4,"Mid-Air","RECHARGE",Color3.fromRGB(100,220,100)); cardPrice(card4,"39 R$"); cardDesc(card4,"Refills gas to 100%!")
cardBuyBtn(card4,Color3.fromRGB(50,200,50),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MidAirRecharge) end) end)

-- Card 5: Skip Island
local card5=mkShopCard(productRow,2)
cardIcon(card5,"\xF0\x9F\x8F\x9D\xEF\xB8\x8F"); cardTitles(card5,"Skip Island","ONE USE",Color3.fromRGB(255,200,100)); cardPrice(card5,"69 R$"); cardDesc(card5,"Jump to next island!")
cardBuyBtn(card5,Color3.fromRGB(255,140,0),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.SkipIsland) end) end)

-- Card 6: Meteorite Explosion
local card6=mkShopCard(productRow,3)
cardIcon(card6,"\xE2\x98\x84\xEF\xB8\x8F"); cardTitles(card6,"Meteorite Explosion","CHAOS MODE",Color3.fromRGB(255,140,80)); cardPrice(card6,"79 R$"); cardDesc(card6,"Rain meteorites down on everyone!")
cardBuyBtn(card6,Color3.fromRGB(232,108,40),"BUY NOW",function() pcall(function() MPS:PromptProductPurchase(player,PRODUCT_IDS.MeteoriteExplosion) end) end)

mkLabel(premPanel,{Text="Purchases support the game! Thank you! \xF0\x9F\x99\x8F",Font=Enum.Font.Gotham,TextSize=12,TextColor3=Color3.fromRGB(150,180,255),Size=UDim2.new(1,-20,0,18),Position=UDim2.new(0,10,1,-22),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=1})

task.spawn(function()
	while true do
		task.wait(1)
		local gp=_G.playerGamepasses
		if gp and gp.twoXHourExpiry and gp.twoXHourExpiry>os.time() then
			local rem=gp.twoXHourExpiry-os.time()
			twoXShopTimer.Text="\xe2\x9a\xa1 Active: "..math.floor(rem/60).."m "..rem%60 .."s"
			twoXShopTimer.Visible=true
		else
			twoXShopTimer.Visible=false
		end
	end
end)
print("CHUNK 2 DONE")

-- Hotbar REMOVED: the bottom-right consumable boxes (Mid-Air Recharge "RCHRG" + Skip Island "SKIP"
-- slots/badges, the HotbarGui ScreenGui, and updateHotbar) are gone. Those items are used IMMEDIATELY
-- on purchase by the server (ProcessReceipt -> triggerMidAirRecharge / triggerSkipIsland), so their
-- held-count was always 0 and the boxes were pointless clutter. The item EFFECTS are untouched.
-- (_G.updateHotbar is no longer defined; its one caller in CoreClient is `if _G.updateHotbar then ...`,
-- which now safely no-ops.)

-- The CURRENTLY FEATURED food shown in the big left display. Defaults to the island's MAIN food
-- (_G.foods[islandNum]) on shop open; clicking a grid cell swaps it. The BUY / BUY MAX buttons act on
-- THIS food. Persists across live refreshes (only reset on shop open / explicit grid selection).
local featuredFood

local function updateFoodShop(islandNum)
	nearIslandNumber=islandNum
	if not featuredFood then featuredFood = _G.foods[islandNum] end  -- safety net; shop OPEN resets to the main food
	foodTitle.Text="\xF0\x9F\x8F\x9D\xEF\xB8\x8F ISLAND "..islandNum.." FOOD STAND"

	-- ===== BIG FEATURED DISPLAY =====
	-- Shows the CURRENTLY FEATURED food (default = this island's main food; clicking a grid cell swaps
	-- it). Stats are ALWAYS shown, even when the featured food is LOCKED -- in that case it's greyed and
	-- the BUY buttons read "LOCKED" so the player sees what they'd get without being able to buy it.
	local f=featuredFood; if not f then return end
	local fLocked = not isUnlocked(f.island)
	foodLockedFrame.Visible=false  -- locked is now shown inline (greyed stats + LOCKED buttons), not the full cover
	foodEmoji.Visible=true; foodName.Visible=true; foodPriceRow.Visible=true; foodPower.Visible=true
	foodBuyBtn.Visible=true; foodBuyMaxBtn.Visible=true
	-- Icon: a real uploaded IMAGE if this food has one (e.g. Beans), otherwise the emoji TextLabel.
	local fImg = foodImages[f.name]
	local fScale = foodImageScale[f.name] or 1
	foodEmojiImg.Size = UDim2.new(0, 120*fScale, 0, 120*fScale) -- per-food shrink, stays centered (anchor 0.5,0.5)
	foodEmojiImg.Image = fImg or ""; foodEmojiImg.Visible = (fImg ~= nil); foodEmojiImg.ImageTransparency = fLocked and 0.5 or 0
	foodEmoji.Visible = (fImg == nil)
	foodEmoji.Text=foodEmojis[f.name] or "?"; foodEmoji.TextTransparency = fLocked and 0.5 or 0
	foodName.Text = fLocked and (f.name.."  \xF0\x9F\x94\x92 LOCKED") or f.name
	foodName.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(255,255,255) -- WHITE name (was black)
	foodPrice.Text=f.price.." coins"  -- coin shown by the CoinIcon ImageLabel in the row, not text
	foodPrice.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(200,140,0)
	foodPower.Text="+"..f.power.." power"
	foodPower.TextColor3 = fLocked and Color3.fromRGB(150,150,150) or Color3.fromRGB(0,160,60)
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- (Gas + Owned stat rows removed from the featured display. coins/curPower/stomMax above are still
	-- read because the BUY/BUY MAX state below uses them.)
	-- How many of this food actually fit in the remaining stomach space, and can be afforded.
	local fittable    = math.floor((stomMax - curPower) / f.power)
	local affordable  = math.floor(coins / f.price)
	local fitAndAfford = math.min(fittable, affordable)
	if fLocked then
		-- LOCKED featured food: stats shown (greyed) above, but buying is disabled.
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="LOCKED"; foodBuyBtn.TextSize=16
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="LOCKED"; foodBuyMaxBtn.TextSize=16
	else
		-- Single BUY: COINS checked FIRST (the common blocker) -> "Not Enough Coins"; then stomach
		-- capacity -> "Stomach Full"; only when both pass is it buyable.
		if coins < f.price then
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="Not Enough Coins"; foodBuyBtn.TextSize=14
		elseif fittable < 1 then
			-- can't fit one: TRULY full (no room at all) vs HAS room but this food is too big
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text=((stomMax-curPower)<=0) and "Stomach Full" or "Not Enough Room"; foodBuyBtn.TextSize=14
		else
			foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17
		end
		-- BUY MAX label shows the fit-and-afford quantity, never the wallet-only amount.
		if fitAndAfford >= 1 then
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="MAX x"..fitAndAfford; foodBuyMaxBtn.TextSize=14
		elseif fittable < 1 then
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text=((stomMax-curPower)<=0) and "FULL" or "NO ROOM"; foodBuyMaxBtn.TextSize=15
		else
			foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15
		end
	end
	local coins2=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins2=c.Value end end end)
	for _,fd in ipairs(_G.foods) do
		local cell=foodCells[fd.name]; if cell then
			local st=cell:FindFirstChildWhichIsA("UIStroke")
			local pl=cell:FindFirstChild("PriceLabel")
			local nm=cell:FindFirstChild("NameLabel")
			local ef=cell:FindFirstChild("EmojiFrame")
			local icon=ef and ef:FindFirstChild("FoodEmoji")
			local iconImg=ef and ef:FindFirstChild("FoodIconImg")
			if not isUnlocked(fd.island) then
				-- LOCKED: keep it a mystery until the player reaches this food's island. 🔒 icon, "???"
				-- name, no price. Cell stays the same size/position, just greyed and not buyable.
				cell.BackgroundColor3=Color3.fromRGB(208,213,221); if st then st.Color=Color3.fromRGB(140,140,140) end -- LOCKED cell: a lighter cool-grey so it doesn't blend with the grey lock icon
				if iconImg then iconImg.Visible=false end -- locked -> show the 🔒 emoji, hide any image icon
				if icon then icon.Visible=true; icon.Text="\xF0\x9F\x94\x92" end
				if ef then ef.Position=UDim2.new(0.5,0,0.5,0); ef.AnchorPoint=Vector2.new(0.5,0.5) end -- center the 🔒 in the box
				if nm then nm.Text="" end -- no "???" label
				if pl then pl.Text="" end
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=false end  -- no price -> hide coin
					if st then if featuredFood and fd.name==featuredFood.name then st.Color=Color3.fromRGB(255,215,0); st.Thickness=4 else st.Thickness=2 end end -- gold border = the FEATURED cell (locked food still highlightable)
			else
				-- UNLOCKED: reveal the real icon + name + price (restores from the locked state, so it
				-- switches live the moment the player reaches the island).
				local cImg=foodImages[fd.name] -- real image icon for this food (e.g. Beans), else nil -> emoji
				if ef then ef.Position=UDim2.new(0,2,0.5,0); ef.AnchorPoint=Vector2.new(0,0.5) end -- restore the icon to the LEFT
				if iconImg then iconImg.Image=cImg or ""; iconImg.Visible=(cImg~=nil) end
				if icon then icon.Visible=(cImg==nil); icon.Text=foodEmojis[fd.name] or "\xF0\x9F\x8D\xBD\xEF\xB8\x8F" end
				if nm then nm.Text=fd.name end
				if (stomMax - curPower) >= fd.power and coins2>=fd.price then  -- buyable: fits at least one of this food AND affordable
					cell.BackgroundColor3=Color3.fromRGB(50,200,50); if st then st.Color=Color3.fromRGB(30,150,30) end
				else
					cell.BackgroundColor3=Color3.fromRGB(180,50,50); if st then st.Color=Color3.fromRGB(120,30,30) end  -- RED: owned/maxed (stomach can't fit one) OR can't afford
				end
				if pl then pl.Text=tostring(fd.price) end  -- coin shown by the PriceIcon ImageLabel, not text
				local pic=cell:FindFirstChild("PriceIcon"); if pic then pic.Visible=true end  -- priced -> show coin
					if st then if featuredFood and fd.name==featuredFood.name then st.Color=Color3.fromRGB(255,215,0); st.Thickness=4 else st.Thickness=2 end end -- gold border = the FEATURED cell
			end
		end
	end
end

for _,v in ipairs(premPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end
for _,v in ipairs(foodPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end

-- ===== PREMIUM SHOP STYLE =====
;(function()
	-- FredokaOne + white text + black stroke on everything in premPanel
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextLabel") or v:IsA("TextButton") then
			v.Font = Enum.Font.FredokaOne
			v.TextScaled = true
			v.TextColor3 = Color3.fromRGB(255,255,255)
			local s = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			s.Color = Color3.fromRGB(0,0,0); s.Thickness = 2; s.Parent = v
		end
	end

	-- Main panel
	premPanel.BackgroundColor3 = Color3.fromRGB(30,120,220)
	local panelS = premPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	panelS.Color = Color3.fromRGB(20,60,160); panelS.Thickness = 3; panelS.Parent = premPanel

	-- Close button + shop title gold
	premClose.BackgroundColor3 = Color3.fromRGB(255,60,60)
	premTitleLbl.TextColor3 = Color3.fromRGB(255,220,0)

	-- Cards: dark blue bg, white stroke
	for _, card in ipairs({card1, card2, card3, card4, card5, card6}) do
		card.BackgroundColor3 = Color3.fromRGB(20,90,200)
		local cs = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		cs.Color = Color3.fromRGB(255,255,255); cs.Thickness = 2; cs.Parent = card
	end

	-- Buy buttons + price labels + section headers by content
	for _, v in ipairs(premPanel:GetDescendants()) do
		if v:IsA("TextButton") then
			if v.Text:find("BUY GAMEPASS") then
				v.BackgroundColor3 = Color3.fromRGB(255,160,20)
				local bs = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				bs.Color = Color3.fromRGB(180,80,0); bs.Thickness = 2; bs.Parent = v
			elseif v.Text:find("BUY NOW") then
				v.BackgroundColor3 = Color3.fromRGB(50,220,50)
				local bs = v:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				bs.Color = Color3.fromRGB(30,130,30); bs.Thickness = 2; bs.Parent = v
			end
		end
		if v:IsA("TextLabel") then
			if v.Text:find("R%$") then
				v.TextColor3 = Color3.fromRGB(100,255,100)
			end
			if v.Text:find("GAMEPASSES") or v.Text:find("ONE%-TIME") then
				v.TextColor3 = Color3.fromRGB(255,220,0)
			end
		end
	end

	-- gpBadge: dark text on gold, no outline
	gpBadge.TextColor3 = Color3.fromRGB(80,40,0)
	gpBadge.BackgroundColor3 = Color3.fromRGB(255,200,0)
	local gbS = gpBadge:FindFirstChildOfClass("UIStroke")
	if gbS then gbS:Destroy() end
end)()

-- ===== PREMIUM SHOP LAYOUT =====
;(function()
	-- Panel taller to fit bigger cards
	premPanel.Size = UDim2.new(0,700,0,520) -- matches the FOOD SHOP panel exactly (700x520); cards below were re-laid-out to fit
	premPanel.Position = UDim2.new(0.5,0,0.5,-45) -- POSITION matched to the food shop (centered, nudged up 45px)
	premPanel.AnchorPoint = Vector2.new(0.5,0.5)

	-- Keep the cards in their ORIGINAL section rows (gamepassRow / productRow). Those rows live INSIDE premScroll,
	-- right under their section headers, so the headers AND the cards scroll TOGETHER. (The bug: these cards used to be
	-- re-parented onto the FIXED premPanel, so only the headers -- still in the scroll -- moved, sliding over the pinned
	-- cards.) Just resize the rows to the card heights, then size + order the cards inside them.
	gamepassRow.Size = UDim2.new(1,-16,0,190)
	productRow.Size  = UDim2.new(1,-16,0,220)
	for i, c in ipairs({card1, card2, card3}) do
		c.Parent = gamepassRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,190)
	end
	for i, c in ipairs({card4, card5, card6}) do
		c.Parent = productRow; c.LayoutOrder = i; c.Size = UDim2.new(0.31,0,0,220)
	end

	-- Layout card content using UIListLayout inside a _Content sub-frame.
	-- Badge (card1 only) stays as an absolute overlay on the card itself.
	local function layoutCard(card, isProduct)
		-- Collect direct children BEFORE creating _Content frame
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
				if child.TextSize >= 40 then
					iconLbl = child
				else
					table.insert(textLbls, child)
				end
			end
		end
		-- Preserve title→subtitle→price→desc order
		table.sort(textLbls, function(a, b)
			return a.Position.Y.Offset < b.Position.Y.Offset
		end)

		-- Content frame fills the card; UIListLayout stacks children vertically
		local cf = Instance.new("Frame")
		cf.Name = "_Content"
		cf.Size = UDim2.new(1,0,1,0)
		cf.BackgroundTransparency = 1
		cf.Parent = card

		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Vertical
		ll.Padding = UDim.new(0,4)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.VerticalAlignment = Enum.VerticalAlignment.Top
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = cf

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0,4)
		pad.PaddingBottom = UDim.new(0,4)
		pad.PaddingLeft = UDim.new(0,4)
		pad.PaddingRight = UDim.new(0,4)
		pad.Parent = cf

		-- Icon
		if iconLbl then
			iconLbl.Size = UDim2.new(0, isProduct and 50 or 55, 0, isProduct and 50 or 55)
			iconLbl.LayoutOrder = 1
			iconLbl.TextScaled = true
			iconLbl.Parent = cf
		end

		-- Name / Type / Price / Desc labels
		local gpSz = {UDim2.new(1,-8,0,26), UDim2.new(1,-8,0,22), UDim2.new(1,-8,0,22)}
		local pdSz = {UDim2.new(1,-8,0,24), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,20), UDim2.new(1,-8,0,28)}
		local szList = isProduct and pdSz or gpSz
		for i, lbl in ipairs(textLbls) do
			lbl.Size = szList[i] or UDim2.new(1,-8,0,20)
			lbl.LayoutOrder = i + 1
			lbl.TextScaled = true
			lbl.Parent = cf
		end

		-- twoXShopTimer (card3): shows between price and buy when active
		if timer then
			timer.Size = UDim2.new(1,-8,0,18)
			timer.LayoutOrder = 5
			timer.TextScaled = true
			timer.Parent = cf
		end

		-- Buy button: last in stack
		if buyBtn then
			buyBtn.Size = UDim2.new(1,-12,0,40)
			buyBtn.LayoutOrder = 10
			buyBtn.TextScaled = true
			buyBtn.Parent = cf
		end

		-- Badge: absolute overlay on card (NOT inside _Content)
		if card == card1 then
			gpBadge.Size = UDim2.new(1,-8,0,18)
			gpBadge.Position = UDim2.new(0,4,0,2)
			gpBadge.ZIndex = 10
		end
	end

	layoutCard(card1, false)
	layoutCard(card2, false)
	layoutCard(card3, false)
	layoutCard(card4, true)
	layoutCard(card5, true)
	layoutCard(card6, true)
end)()

-- Explicitly style the shop close button
premClose.Text = "X"
premClose.Font = Enum.Font.FredokaOne
premClose.TextScaled = true
premClose.TextColor3 = Color3.fromRGB(255,255,255)
local pcs = premClose:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
pcs.Color = Color3.fromRGB(0,0,0); pcs.Thickness = 2; pcs.Parent = premClose

-- ===== FOOD SHOP STYLE & LAYOUT =====
;(function()
	-- FIX 1: Sort food grid cells by island order
	foodGrid.SortOrder = Enum.SortOrder.LayoutOrder
	if _G.foods then
		for _, f in ipairs(_G.foods) do
			local cell = foodCells[f.name]
			if cell then cell.LayoutOrder = f.island or 99 end
		end
	end

	-- FIX 2: Main panel
	foodPanel.Size = UDim2.new(0,700,0,520)
	foodPanel.Position = UDim2.new(0.5,0,0.5,-45) -- nudged UP ~45px so the panel's bottom clears the bottom-center stomach/gut indicator below it
	foodPanel.AnchorPoint = Vector2.new(0.5,0.5)
	foodPanel.BackgroundColor3 = Color3.fromRGB(30,120,220)
	local fpC = foodPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fpC.CornerRadius = UDim.new(0,20); fpC.Parent = foodPanel
	local fpS = foodPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fpS.Color = Color3.fromRGB(20,60,160); fpS.Thickness = 3; fpS.Parent = foodPanel

	-- FIX 3: Header + title
	foodHeader.BackgroundColor3 = Color3.fromRGB(15,60,140)
	local fhC = foodHeader:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fhC.CornerRadius = UDim.new(0,20); fhC.Parent = foodHeader
	foodTitle.Size = UDim2.new(1,-55,0,55)
	foodTitle.Position = UDim2.new(0,0,0,0)
	foodTitle.Font = Enum.Font.FredokaOne
	foodTitle.TextColor3 = Color3.fromRGB(255,220,0)
	foodTitle.TextScaled = true
	foodTitle.TextXAlignment = Enum.TextXAlignment.Center
	local ftS = foodTitle:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	ftS.Color = Color3.fromRGB(0,0,0); ftS.Thickness = 2; ftS.Parent = foodTitle

	-- FIX 4: Food grid settings
	foodGrid.CellSize = UDim2.new(0,95,0,75)
	foodGrid.CellPadding = UDim2.new(0,6,0,6)

	-- Right panel adjusted for new left panel width
	foodRight.Size = UDim2.new(1,-190,1,-70)
	foodRight.Position = UDim2.new(0,180,0,60)
	foodRight.BackgroundColor3 = Color3.fromRGB(15,60,140)
	local frC = foodRight:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	frC.CornerRadius = UDim.new(0,12); frC.Parent = foodRight
	for _, v in ipairs(foodRight:GetChildren()) do
		if v:IsA("TextLabel") then
			v.Font = Enum.Font.FredokaOne
			v.TextColor3 = Color3.fromRGB(255,220,0)
			v.TextScaled = true
		end
	end

	-- Restyle each food cell
	for _, cell in pairs(foodCells) do
		cell.BackgroundColor3 = Color3.fromRGB(20,90,200)
		local cs = cell:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		cs.CornerRadius = UDim.new(0,10); cs.Parent = cell
		local css = cell:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		css.Color = Color3.fromRGB(255,255,255); css.Thickness = 1.5; css.Parent = cell
		local ef = cell:FindFirstChild("EmojiFrame")
		if ef then
			ef.Size = UDim2.new(0,36,0,36)
			ef.Position = UDim2.new(0,6,0.5,0)
			ef.AnchorPoint = Vector2.new(0,0.5)
			local el = ef:FindFirstChild("FoodEmoji")
			if el then
				el.Size = UDim2.new(1,0,1,0)
				el.Position = UDim2.new(0,0,0,0)
				el.AnchorPoint = Vector2.new(0,0)
				el.TextScaled = true
			end
		end
		for _, child in ipairs(cell:GetChildren()) do
			if child:IsA("TextLabel") and child.Name == "PriceLabel" then
				-- Narrow the price text to leave room for the coin icon, and align the icon to this row.
				child.Size = UDim2.new(1,-66,0,22)
				child.Position = UDim2.new(0,64,0,36)
				child.Font = Enum.Font.FredokaOne
				child.TextScaled = true
				child.TextColor3 = Color3.fromRGB(255,220,0)
				child.TextXAlignment = Enum.TextXAlignment.Left
				local pIcon = cell:FindFirstChild("PriceIcon")
				if pIcon then pIcon.Size = UDim2.new(0,18,0,18); pIcon.Position = UDim2.new(0,44,0,38) end
			elseif child:IsA("TextLabel") then
				child.Size = UDim2.new(1,-48,0,28)
				child.Position = UDim2.new(0,46,0,8)
				child.Font = Enum.Font.FredokaOne
				child.TextScaled = true
				child.TextColor3 = Color3.fromRGB(255,255,255)
				child.TextXAlignment = Enum.TextXAlignment.Left
				local ns = child:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				ns.Color = Color3.fromRGB(0,0,0); ns.Thickness = 2; ns.Parent = child
			end
		end
	end

	-- FIX 5: Left preview panel
	foodLeftPanel.Size = UDim2.new(0,160,1,-80)
	foodLeftPanel.Position = UDim2.new(0,10,0,60)
	foodLeftPanel.BackgroundColor3 = Color3.fromRGB(20,90,200)
	local flpC = foodLeftPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	flpC.CornerRadius = UDim.new(0,14); flpC.Parent = foodLeftPanel
	local flpS = foodLeftPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	flpS.Color = Color3.fromRGB(255,255,255); flpS.Thickness = 2; flpS.Parent = foodLeftPanel
	foodEmoji.Size = UDim2.new(0,80,0,80)
	foodEmoji.Position = UDim2.new(0.5,0,0,10)
	foodEmoji.AnchorPoint = Vector2.new(0.5,0)
	foodName.Size = UDim2.new(1,-8,0,32)
	foodName.Position = UDim2.new(0,4,0,98)
	foodName.Font = Enum.Font.FredokaOne
	foodName.TextScaled = true
	foodName.TextColor3 = Color3.fromRGB(255,255,255)
	local fnS = foodName:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fnS.Color = Color3.fromRGB(0,0,0); fnS.Thickness = 2; fnS.Parent = foodName
	foodPriceRow.Size = UDim2.new(1,-8,0,26); foodPrice.Size = UDim2.new(0,110,1,0)  -- size the ROW (coin+text); text fixed width inside the centered list
	foodPriceRow.Position = UDim2.new(0,4,0,134)  -- position the ROW; UIListLayout handles the text inside
	foodPrice.Font = Enum.Font.FredokaOne
	foodPrice.TextScaled = true
	foodPrice.TextColor3 = Color3.fromRGB(255,220,0)
	foodPower.Size = UDim2.new(1,-8,0,26)
	foodPower.Position = UDim2.new(0,4,0,164)
	foodPower.Font = Enum.Font.FredokaOne
	foodPower.TextScaled = true
	foodPower.TextColor3 = Color3.fromRGB(100,255,100)

	-- FIX 6: Buy buttons — move to main panel, position at bottom-left
	foodBuyBtn.Parent = foodPanel
	foodBuyBtn.Size = UDim2.new(0,130,0,48)
	foodBuyBtn.Position = UDim2.new(0,10,1,-58)
	foodBuyBtn.BackgroundColor3 = Color3.fromRGB(50,220,50)
	foodBuyBtn.Font = Enum.Font.FredokaOne
	foodBuyBtn.TextScaled = true
	foodBuyBtn.TextColor3 = Color3.fromRGB(255,255,255)
	local fbC = foodBuyBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fbC.CornerRadius = UDim.new(0,12); fbC.Parent = foodBuyBtn
	local fbS = foodBuyBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fbS.Color = Color3.fromRGB(30,130,30); fbS.Thickness = 2; fbS.Parent = foodBuyBtn
	foodBuyMaxBtn.Parent = foodPanel
	foodBuyMaxBtn.Size = UDim2.new(0,130,0,48)
	foodBuyMaxBtn.Position = UDim2.new(0,148,1,-58)
	foodBuyMaxBtn.BackgroundColor3 = Color3.fromRGB(255,160,20)
	foodBuyMaxBtn.Font = Enum.Font.FredokaOne
	foodBuyMaxBtn.TextScaled = true
	foodBuyMaxBtn.TextColor3 = Color3.fromRGB(255,255,255)
	local fmC = foodBuyMaxBtn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fmC.CornerRadius = UDim.new(0,12); fmC.Parent = foodBuyMaxBtn
	local fmS = foodBuyMaxBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fmS.Color = Color3.fromRGB(180,80,0); fmS.Thickness = 2; fmS.Parent = foodBuyMaxBtn

	-- Close button
	foodCloseBtn.Text = "X"
	foodCloseBtn.Font = Enum.Font.FredokaOne
	foodCloseBtn.TextScaled = true
	local fclS = foodCloseBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fclS.Color = Color3.fromRGB(0,0,0); fclS.Thickness = 2; fclS.Parent = foodCloseBtn
end)()

-- (The embedded "GAS METER" fart-power bar that used to sit in the food shop's bottom strip has been
-- REMOVED from the stand menu. The underlying CurrentPower / StomachMax values are untouched -- they
-- still drive flight and the HUD gas meter; only this duplicate bar display in the shop is gone.)

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY: shared manager (one instance across client scripts, via _G). Guarded
-- factory so whichever client script loads first creates it. Lets opening one main menu close the others. =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)                                                -- hide/show the WHOLE bottom HUD (gut pill + gas meter + fart button all live in BottomStackGui)
		local lp = game:GetService("Players").LocalPlayer
		local pgx = lp and lp:FindFirstChildOfClass("PlayerGui")
		local g = pgx and pgx:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name
		mgr.setHud(false)                                                       -- a main menu is now open -> hide the bottom HUD (Shop/Pet Hub/Seasonal Pets all route through here)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end                         -- last menu closed -> restore the bottom HUD
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end
-- the food-STAND menu fully hides here (also clears shopOpen so the proximity loop knows it's closed)
_G.MainMenuManager.register("FoodShop", function() FoodShopGui.Enabled = false; shopOpen = false end)

-- [UIFix] print the SHOP panel's REAL final layout + any size-controlling constraints (so the menus can copy them exactly),
-- then its RESOLVED on-screen size each time it opens (compare against the Pet Hub / Seasonal Pets prints).
print("[UIFix] SHOP size=" .. tostring(premPanel.Size) .. " pos=" .. tostring(premPanel.Position) .. " anchor=" .. tostring(premPanel.AnchorPoint))
for _, c in ipairs(premPanel:GetChildren()) do
	if c:IsA("UIScale") then print("[UIFix] SHOP UIScale=" .. tostring(c.Scale))
	elseif c:IsA("UISizeConstraint") then print("[UIFix] SHOP UISizeConstraint min=" .. tostring(c.MinSize) .. " max=" .. tostring(c.MaxSize))
	elseif c:IsA("UIAspectRatioConstraint") then print("[UIFix] SHOP UIAspectRatioConstraint ratio=" .. tostring(c.AspectRatio) .. " type=" .. tostring(c.AspectType)) end
end
PremiumShopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if PremiumShopGui.Enabled then task.defer(function() print("[UIFix] SHOP AbsoluteSize=" .. tostring(premPanel.AbsoluteSize) .. " AbsolutePosition=" .. tostring(premPanel.AbsolutePosition)) end) end
end)
premClose.MouseButton1Click:Connect(function() if _G.playUIClick then _G.playUIClick() end; PremiumShopGui.Enabled=false; _G.MainMenuManager.notifyClosed("Premium") end)
foodCloseBtn.MouseButton1Click:Connect(function()
	FoodShopGui.Enabled = false
	shopOpen = false
	playerClosedShop = true
	_G.MainMenuManager.notifyClosed("FoodShop")
	task.delay(3, function() playerClosedShop = false end)
end)

local function playEatSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://103794849233173"
	sound.Volume=0.8; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,3)
end

foodBuyBtn.MouseButton1Click:Connect(function()
	local f=featuredFood; if not f then return end          -- buy the CURRENTLY FEATURED food
	if not isUnlocked(f.island) then return end              -- locked featured food: not buyable
	playEatSound()
	local coins=0
	pcall(function() if _G.leaderstats then local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end end end)
	if coins<f.price then
		foodBuyBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyBtn.Text="Not Enough Coins"; foodBuyBtn.TextSize=14
		task.delay(1,function() foodBuyBtn.BackgroundColor3=Color3.fromRGB(50,200,50); foodBuyBtn.Text="BUY FOOD"; foodBuyBtn.TextSize=17 end)
		return
	end
	pcall(function() _G.BuyFoodEvent:FireServer(f.name) end)
	print("FIRED BUYFOOD:", f.name)
	local fl=Instance.new("TextLabel"); fl.Text="+"..f.power.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=20; fl.TextColor3=Color3.fromRGB(0,200,50); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,200,0,40); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

foodBuyMaxBtn.MouseButton1Click:Connect(function()
	playEatSound()
	local feat=featuredFood; if not feat then return end     -- BUY MAX targets the FEATURED food
	if not isUnlocked(feat.island) then return end           -- locked featured food: BUY MAX disabled
	local coins, curPower, stomMax = 0, 0, 46
	pcall(function() if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins"); if c then coins=c.Value end
		local cp=_G.leaderstats:FindFirstChild("CurrentPower"); if cp then curPower=cp.Value end
		local sm=_G.leaderstats:FindFirstChild("StomachMax"); if sm then stomMax=sm.Value end
	end end)
	-- Fill as full as possible using current + lower UNLOCKED foods, biggest power first, capped
	-- by BOTH remaining stomach space AND money on hand. _G.foods is ordered by power ascending
	-- (island N == index N), so iterating nearIslandNumber -> 1 is largest -> smallest. We never
	-- spend more coins than we have and never exceed stomachMax (qty floored by remaining space).
	local remaining = stomMax - curPower
	local coinsLeft = coins
	local totalPower = 0
	for i = feat.island, 1, -1 do  -- fill from the FEATURED food downward (its max), biggest power first
		local f = _G.foods[i]
		if f and isUnlocked(f.island) then
			local qty = math.min(math.floor(remaining / f.power), math.floor(coinsLeft / f.price))
			if qty > 0 then
				for _=1,qty do pcall(function() _G.BuyFoodEvent:FireServer(f.name) end) end
				remaining = remaining - qty * f.power
				coinsLeft = coinsLeft - qty * f.price
				totalPower = totalPower + qty * f.power
			end
		end
		if remaining < _G.foods[1].power or coinsLeft < _G.foods[1].price then break end
	end
	if totalPower <= 0 then
		-- coins checked FIRST; then TRULY full (no room) vs HAS room but the cheapest food still won't fit
		local reason
		if coinsLeft < _G.foods[1].price then reason = "Not Enough Coins"
		elseif remaining <= 0 then reason = "Stomach Full"
		else reason = "Not Enough Room" end
		foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(150,150,150); foodBuyMaxBtn.Text=reason; foodBuyMaxBtn.TextSize=13
		task.delay(1,function() foodBuyMaxBtn.BackgroundColor3=Color3.fromRGB(255,140,0); foodBuyMaxBtn.Text="BUY MAX"; foodBuyMaxBtn.TextSize=15 end)
		return
	end
	print("BUY MAX: +"..totalPower.." power (coins left "..coinsLeft..", space left "..remaining..")")
	local fl=Instance.new("TextLabel"); fl.Text="MAX! +"..totalPower.." power!"; fl.Font=Enum.Font.GothamBold; fl.TextSize=18; fl.TextColor3=Color3.fromRGB(255,140,0); fl.BackgroundTransparency=1; fl.Size=UDim2.new(0,260,0,50); fl.Position=UDim2.new(0.3,0,0.6,0); fl.ZIndex=10; fl.Parent=FoodShopGui
	TweenService:Create(fl,TweenInfo.new(1.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new(0.3,0,0.4,0),TextTransparency=1}):Play()
	task.delay(1.5,function() fl:Destroy() end)
end)

-- Every stand sells ALL unlocked foods: make each food cell in the grid a buy button (one
-- purchase per click). The native food stays the enlarged left preview with its own BUY/BUY MAX.
-- Server validates coins + stomach space, so foods too big for the current gut just won't buy.
-- Purely additive: no price/power changed (flat 0.5 coins/power), so no exploit.
for _, f in ipairs(_G.foods) do
	local cell = foodCells[f.name]
	if cell then
		local buyOverlay = mkButton(cell, {Name="BuyOverlay", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", ZIndex=5})
		buyOverlay.MouseButton1Click:Connect(function()
			-- Clicking a grid food now FEATURES it in the big left display (instead of buying directly).
			-- Locked foods feature too (shown greyed + LOCKED). Buying happens via the big BUY / BUY MAX
			-- buttons, which target the featured food -- the purchase remote/server flow is unchanged.
			if _G.playUIClick then pcall(_G.playUIClick) end
			featuredFood = f
			updateFoodShop(nearIslandNumber)  -- re-render big display + re-highlight the grid (keeps featured)
		end)
	end
end

-- (Hotbar slot click handlers REMOVED with the hotbar. They were the OLD manual-use path that only
-- fired when the held count was > 0; since Mid-Air Recharge / Skip Island are now applied IMMEDIATELY
-- on purchase server-side, those counts stay 0 and these handlers never ran. The item effects are
-- driven by the server's ProcessReceipt -> triggerMidAirRecharge (client rechargeNow) / triggerSkipIsland.)

pcall(function()
	if _G.leaderstats then
		local c=_G.leaderstats:FindFirstChild("Coins")
		if c then c.Changed:Connect(function() if _G.updateCoins then _G.updateCoins() end; if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		-- Stomach fill changes (buying food, landing) must refresh the BUY MAX fit count live.
		local cpv=_G.leaderstats:FindFirstChild("CurrentPower")
		if cpv then cpv.Changed:Connect(function() if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		local smv=_G.leaderstats:FindFirstChild("StomachMax")
		if smv then smv.Changed:Connect(function() if shopOpen then updateFoodShop(nearIslandNumber) end end) end
		local isl=_G.leaderstats:FindFirstChild("Island")
		if isl then isl.Changed:Connect(function(newVal)
			for n=1,newVal do unlockedIslands[n]=true end
			if shopOpen then updateFoodShop(nearIslandNumber) end
		end) end
	end
end)

-- Keep local unlockedIslands in sync with _G.unlockedIslands every second
task.spawn(function()
	while true do
		task.wait(1)
		if _G.unlockedIslands then
			for k, v in pairs(_G.unlockedIslands) do
				if v then unlockedIslands[k] = true end
			end
		end
		pcall(function()
			if _G.leaderstats then
				local isl = _G.leaderstats:FindFirstChild("Island")
				if isl then for n = 1, isl.Value do unlockedIslands[n] = true end end
			end
		end)
		-- LIVE: refresh the grid so a newly-reached island reveals its food cell (🔒 -> real icon/name/price)
		-- without needing another stat change.
		if shopOpen then pcall(function() updateFoodShop(nearIslandNumber) end) end
	end
end)

-- ===== STAND DETECTION =====
local RS = game:GetService("ReplicatedStorage")

-- Receive stand positions from server
local sre = RS:WaitForChild("StandsReadyEvent", 30)
if sre then
	sre.OnClientEvent:Connect(function(data)
		stands = {}
		for islandNum, pos in pairs(data) do
			table.insert(stands, {
				position = Vector3.new(pos.x, pos.y, pos.z),
				islandNum = tonumber(islandNum)
			})
		end
		table.sort(stands, function(a, b) return a.islandNum < b.islandNum end)
		print("STANDS RECEIVED:", #stands)
	end)
end

-- Proximity check every 0.1 seconds
task.spawn(function()
	while true do
		task.wait(0.1)
		pcall(function()
			if #stands == 0 then return end  -- no food stands in this game -> don't auto-open/close; the "Shop" part opens it
			local character = player.Character
			if not character then return end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			if _G.unlockedIslands then
				for i, v in pairs(_G.unlockedIslands) do unlockedIslands[i] = v end
			end
			-- Stand only triggers while GROUNDED — never mid-flight / in the air (flying lifts the humanoid off
				-- the floor, so FloorMaterial becomes Air and _G.isFlying is set).
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local grounded = (not _G.isFlying) and humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
				local nearStand = false
			local foundIsland = 1
			for _, stand in ipairs(stands) do
				local diff = hrp.Position - stand.position
				local horizontalDist = math.sqrt(diff.X * diff.X + diff.Z * diff.Z)
				local verticalDist = math.abs(diff.Y)
				if grounded and horizontalDist < STAND_TRIGGER_RADIUS and verticalDist < 120 then
					nearStand = true
					foundIsland = stand.islandNum
					break
				end
			end
			if nearStand then
				lastAwayTime = 0
				-- only auto-open if no OTHER main menu is open (proximity yields to a deliberately-opened menu)
				if not shopOpen and not playerClosedShop and not _G.MainMenuManager.isOtherOpen("FoodShop") then
					nearIslandNumber = foundIsland
					featuredFood = _G.foods[foundIsland]  -- big display defaults to the island's MAIN food on open
					updateFoodShop(foundIsland)
					_G.MainMenuManager.notifyOpened("FoodShop") -- becomes the one open main menu
					FoodShopGui.Enabled = true
					shopOpen = true
					print("SHOP OPEN ISLAND", foundIsland)
				end
			else
				if lastAwayTime == 0 then lastAwayTime = tick() end
				if tick() - lastAwayTime > 2 then playerClosedShop = false end
				if shopOpen then
					FoodShopGui.Enabled = false
					shopOpen = false
					_G.MainMenuManager.notifyClosed("FoodShop")
					print("SHOP CLOSED")
				end
			end
		end)
	end
end)

print("PERMANENTLY FIXED")
print("FIXES DONE")
print("REMOVED 2 OLD BUTTONS (orange Shop + purple Invite from ShopClient SidebarGui)")
print("OLD BUTTONS REMOVED")

-- ===== GAMEPASS "OWNED" STATE =====
-- For the two REAL permanent gamepasses only (2x Power Forever, Glitter Trail), show a non-clickable
-- "✓ OWNED" button instead of "BUY GAMEPASS" once the player owns it. Ownership comes from
-- _G.playerGamepasses (twoXForever / glitterTrail), which the server sets on join and on a live
-- purchase (PromptGamePassPurchaseFinished -> GamepassEvent). The developer products (Meteorite Explosion,
-- Skip Island, Mid-Air Recharge, 2x 1-Hour) are repeatable and intentionally NOT affected here.
do
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
	local function refreshOwned()
		local gp = _G.playerGamepasses
		-- Both "BUY GAMEPASS" buttons are orange after the shop restyle, so restore to that when not owned.
		setOwned(btn1, gp and gp.twoXForever == true, Color3.fromRGB(255,160,20))
		setOwned(btn2, gp and gp.glitterTrail == true, Color3.fromRGB(255,160,20))
	end
	refreshOwned() -- initial (covers ownership already received on join)
	-- Live: CoreClient's GamepassEvent handler updates _G.playerGamepasses first; defer so we read the
	-- updated value, then flip the card to OWNED immediately (e.g. right after a purchase grant).
	local GamepassEvent = game:GetService("ReplicatedStorage"):FindFirstChild("GamepassEvent")
		or game:GetService("ReplicatedStorage"):WaitForChild("GamepassEvent", 10)
	if GamepassEvent then
		GamepassEvent.OnClientEvent:Connect(function() task.defer(refreshOwned) end)
	end
	-- Safety net: also re-check every second so the card stays correct regardless of event timing.
	task.spawn(function() while true do task.wait(1); refreshOwned() end end)
end

-- ===== EXTERNAL OPEN/CLOSE: a workspace "Shop" part (wired in ShopGlue.client.luau) opens this UI =====
_G.OpenFoodShop = function(island)
	island = island or nearIslandNumber or 1
	nearIslandNumber = island
	featuredFood = _G.foods[island] or _G.foods[1]
	pcall(function() updateFoodShop(island) end)
	if _G.MainMenuManager then _G.MainMenuManager.notifyOpened("FoodShop") end
	FoodShopGui.Enabled = true
	shopOpen = true
	playerClosedShop = false
	print("[Shop] opened via _G.OpenFoodShop (island " .. tostring(island) .. ")")
end
_G.CloseFoodShop = function()
	FoodShopGui.Enabled = false
	shopOpen = false
	if _G.MainMenuManager then _G.MainMenuManager.notifyClosed("FoodShop") end
end
_G.OpenPremiumShop = function()
	if _G.MainMenuManager then _G.MainMenuManager.notifyOpened("Premium") end
	PremiumShopGui.Enabled = true
end
print("[Shop] external hooks ready: _G.OpenFoodShop / _G.CloseFoodShop / _G.OpenPremiumShop")

-- ===== JUNGLE CHROME -- make the SHOP match the Pet Hub EXACTLY (olive panel, bamboo border, =====
-- corner leaf vines, wooden plaque header, glossy buttons). Same shared module the look comes from.
task.spawn(function()
	local okMod, JC = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10))
	end)
	if not okMod or not JC then warn("[Shop] JungleChrome module missing -- SHOP keeps its default style"); return end
	JC.buildShell(PremiumShopGui)        -- bamboo border + corner/edge vines behind the panel
	JC.stylePanel(premPanel)             -- olive-green panel + gradient + stroke (exact Pet Hub values)
	local subLbl; for _, c in ipairs(premHeader:GetChildren()) do if c:IsA("TextLabel") and c ~= premTitleLbl then subLbl = c; break end end
	JC.plaqueHeader(premHeader, premTitleLbl, subLbl, premClose) -- wooden plaque header (keeps the "SHOP" title)
	for _, v in ipairs(premPanel:GetDescendants()) do if v:IsA("TextButton") and v ~= premClose then JC.styleButton(v) end end -- glossy buy buttons
	for _, card in ipairs({ card1, card2, card3, card4, card5, card6 }) do -- cards -> Pet Hub card green (matching set)
		if card then card.BackgroundColor3 = Color3.fromRGB(34,74,40); local cs = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke"); cs.Color = Color3.fromRGB(22,44,26); cs.Thickness = 2; cs.Parent = card end
	end
	print("[Shop] jungle chrome applied -- SHOP now matches the Pet Hub")
end)
