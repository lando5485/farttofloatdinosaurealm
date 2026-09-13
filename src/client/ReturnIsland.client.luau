--======================================================================
-- ReturnIsland.client.luau   (StarterPlayerScripts.DinosaurRealmClient)
--======================================================================
-- The "Return to <island>" button. Pairs with ReturnIsland.server.luau -- that script
-- decides WHEN it shows and does the actual teleport; this one only draws it and reports
-- the tap.
--
-- ===== IT SENDS NOTHING BUT "I TAPPED IT" =====
-- No slot, no position, no target. The server recomputes where the player actually got to
-- and moves them itself, so a hacked client spamming this remote achieves nothing except
-- being put back somewhere it had already earned. Do NOT "optimise" this by passing the
-- slot number -- that is the whole exploit.
--
-- ===== PLACEMENT: LEFT EDGE, VERTICALLY CENTRED =====
-- Position (0, 130, 0.5, 0), AnchorPoint (0, 0.5). Not arbitrary -- it is the one part of
-- this screen that is empty:
--   * the LEFT RAIL (shop / stomach / wormhole / more) is 95px wide at x=12, so it spans
--     12..107 and an inset of 130 clears it with room to spare;
--   * the RIGHT PANEL (stats + impulse buttons) owns the right edge;
--   * the BOTTOM CENTRE is the gut card and the fart button;
--   * the TOP CENTRE is the island banner and the quest cards.
-- Mid-height on the left never covers the middle of the screen. If the rails ever move,
-- X_INSET is the ONE number to change. Keep the anchor at (0, 0.5).
--
-- ===== WHAT CHANGED FROM THE KIT =====
-- IT NAMES THE ISLAND. The kit says "Return to Island 7", because a portable copy only has
-- an index. This realm has IslandOrder on the client too, so the button reads "Return to
-- Claw Cliffs" -- and the attribute is a CLIMB SLOT, which is not the island's number:
-- slot 2 is island9, "Frostbite Flats". Printing the raw index would name the wrong place.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer
local PlayerGui         = player:WaitForChild("PlayerGui")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

--======================================================================
-- LOOK / PLACEMENT
--======================================================================
local X_INSET   = 130                            -- px from the left edge; clears the left rail
local W, H      = 200, 56                        -- authored size (ResponsiveUI scales from here)
local FILL      = Color3.fromRGB(255, 150, 0)    -- warm orange: a safety action, not a purchase
local EDGE      = Color3.fromRGB(180,  90,   0)
local TEXT_SIZE = 17
local CORNER    = 14
local STROKE    = 3

local ReturnToIslandEvent = ReplicatedStorage:FindFirstChild("ReturnToIslandEvent")
	or ReplicatedStorage:WaitForChild("ReturnToIslandEvent", 30)

local gui = Instance.new("ScreenGui")
gui.Name = "ReturnIslandGui"
gui.ResetOnSpawn = false      -- it must survive the respawn that a long fall usually ends in
gui.IgnoreGuiInset = true     -- so the y=0.5 centring is against the real screen, not the inset one
gui.DisplayOrder = 8
gui.Parent = PlayerGui

local btn = Instance.new("TextButton")
btn.Name = "ReturnBtn"
btn.AnchorPoint = Vector2.new(0, 0.5)
btn.Position = UDim2.new(0, X_INSET, 0.5, 0)
btn.Size = UDim2.new(0, W, 0, H)
btn.BackgroundColor3 = FILL
btn.BorderSizePixel = 0
btn.Font = Enum.Font.GothamBold
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.TextScaled = true
btn.Text = "Return"
btn.Visible = false           -- the server's attribute reveals it; never show it unprompted
btn.ZIndex = 8
btn.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, CORNER); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Color = EDGE; s.Thickness = STROKE; s.Parent = btn
	-- TextScaled with a CEILING, not a fixed TextSize. ResponsiveUI blanket-forces
	-- TextScaled on labels it owns, which ignores TextSize and inflates the caption to fill
	-- the button; a UITextSizeConstraint is the only thing that holds the authored size.
	local t = Instance.new("UITextSizeConstraint"); t.MaxTextSize = TEXT_SIZE; t.Parent = btn
end

--======================================================================
-- VISIBILITY -- driven entirely by the server's attribute
--======================================================================
-- ReturnPromptIsland = the CLIMB SLOT to offer, or 0 for "hide". The client never decides
-- this: only the server knows how far the player actually got.
local function refresh()
	local slot = tonumber(player:GetAttribute("ReturnPromptIsland")) or 0
	if slot > 0 then
		-- slot -> island model number -> display name. Going straight from the slot to a
		-- name would print the wrong island: the tower deliberately scrambles the two.
		local islandNum = IslandOrder.SLOT_TO_ISLAND[slot]
		local name = islandNum and IslandOrder.NAMES[islandNum]
		btn.Text = "\xE2\xAC\x86 Return to " .. (name or ("Island " .. slot))  -- U+2B06 up arrow
		btn.Visible = true
	else
		btn.Visible = false
	end
end

player:GetAttributeChangedSignal("ReturnPromptIsland"):Connect(refresh)
refresh()

if ReturnToIslandEvent then
	btn.MouseButton1Click:Connect(function()
		if _G.playUIClick then pcall(_G.playUIClick) end
		-- Hide on tap: the teleport takes a moment to land, and a button still sitting there
		-- invites a second tap that does nothing. The server clears the attribute too, which
		-- is what makes it stick.
		btn.Visible = false
		pcall(function() ReturnToIslandEvent:FireServer() end)
	end)
else
	warn("[Return] ReturnToIslandEvent missing -- is ReturnIsland.server.luau in ServerScriptService?")
end

print("[Return] button ready -- left edge at x=" .. X_INSET
	.. ", shown only while below your highest island (named from IslandOrder)")
