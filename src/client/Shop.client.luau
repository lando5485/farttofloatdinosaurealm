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

-- Look a food up by the island it BELONGS to, never by its position in the array.
-- _G.foods is ordered by CLIMB SLOT (Eggs, Chili Peppers, Lettuce, ...), so
-- _G.foods[5] is the 5th food of the climb, NOT island5's food -- island5 sits at
-- slot 3. Indexing by island number only worked back when the array happened to be
-- in island order; it silently features the wrong food now.
local function foodForIsland(islandNum)
	for _, f in ipairs(_G.foods or {}) do
		if f.island == islandNum then return f end
	end
	return nil
end

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
local foodPanel=mkFrame(sg,{Size=UDim2.new(0.92,0,0.78,0),Position=UDim2.new(0.5,0,0.5,-16),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(240,248,255),Active=true}) -- hub-parity spot: -16 lifts it like the hub's -45 without clipping phone tops; Active=true blocks pass-through behind the panel
mkCorner(foodPanel,16); mkStroke(foodPanel,Color3.fromRGB(120, 196, 96),4)
local foodHeader=mkFrame(foodPanel,{Size=UDim2.new(1,0,0,55),BackgroundColor3=Color3.fromRGB(86, 170, 78)}); mkCorner(foodHeader,16)
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
	if not featuredFood then featuredFood = foodForIsland(islandNum) end  -- safety net; shop OPEN resets to the main food
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

for _,v in ipairs(foodPanel:GetDescendants()) do
	if v:IsA("TextLabel") or v:IsA("TextButton") then v.TextScaled=true end
end

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
	foodPanel.Position = UDim2.new(0.5,0,0.5,-16) -- hub-parity spot (-45 equivalent; no phone clipping)
	foodPanel.AnchorPoint = Vector2.new(0.5,0.5)
	foodPanel.BackgroundColor3 = Color3.fromRGB(78, 158, 72)
	local fpC = foodPanel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	fpC.CornerRadius = UDim.new(0,20); fpC.Parent = foodPanel
	local fpS = foodPanel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	fpS.Color = Color3.fromRGB(28, 64, 34); fpS.Thickness = 3; fpS.Parent = foodPanel

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
		cell.BackgroundColor3 = Color3.fromRGB(40, 86, 44)
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
	foodLeftPanel.BackgroundColor3 = Color3.fromRGB(40, 86, 44)
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
	-- by BOTH remaining stomach space AND money on hand. _G.foods is ordered by CLIMB SLOT with
	-- power ascending, so walking the array downward is largest -> smallest. We never spend more
	-- coins than we have and never exceed stomachMax (qty floored by remaining space).
	local remaining = stomMax - curPower
	local coinsLeft = coins
	local totalPower = 0
	-- Start from the featured food's ARRAY INDEX. feat.island is a MODEL number, not an index --
	-- island9 is the 2nd food of the climb, so `for i = feat.island, 1, -1` walked the wrong range.
	local featIdx = 1
	for i, ff in ipairs(_G.foods) do if ff.island == feat.island then featIdx = i; break end end
	for i = featIdx, 1, -1 do  -- fill from the FEATURED food downward (its max), biggest power first
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
					featuredFood = foodForIsland(foundIsland)  -- big display defaults to the island's MAIN food on open
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

-- ===== EXTERNAL OPEN/CLOSE: a workspace "Shop" part (wired in ShopGlue.client.luau) opens this UI =====
_G.OpenFoodShop = function(island)
	island = island or nearIslandNumber or 1
	nearIslandNumber = island
	featuredFood = foodForIsland(island) or _G.foods[1]
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
print("[Shop] external hooks ready: _G.OpenFoodShop / _G.CloseFoodShop")

-- ===== THE PREMIUM (\xF0\x9F\x9B\x92 SHOP) PANEL NO LONGER LIVES HERE =====
-- This file used to build a second ScreenGui called "PremiumShopGui" -- the gamepass/product
-- panel -- alongside the food shop. Bootstrap built a third one of its own under the same name,
-- so PlayerGui held two, and the SHOP button toggled whichever FindFirstChild happened to return.
-- Both are gone: ShopKit.client.luau builds the one PremiumShopGui now, and provides
-- _G.OpenPremiumShop / _G.toggleShopKit. This file owns the FOOD shop and nothing else.

