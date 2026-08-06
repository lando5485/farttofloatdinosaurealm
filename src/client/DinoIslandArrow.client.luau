--======================================================================
-- DinoIslandArrow.client.luau  (LocalScript)
--======================================================================
-- THE LITTLE ARROW THAT GUIDES YOU TO THE NEXT ISLAND.
--
-- A bold white up-arrow with a thick black outline. It rotates to point at the
-- island you are climbing toward, and when that island is off-screen or behind
-- you it clamps to the edge of the screen and keeps pointing. A small name label
-- sits under it once you have actually been there.
--
-- The projection + edge-clamp maths is copied VERBATIM from the main game's
-- next-island pointer, so it looks and moves identically. What is rewritten is
-- how it finds and names its target: the original was written for "a realm it
-- knows nothing about" and guessed by scanning Workspace for models called
-- island*, reading the number out of the model name. That guess is wrong here --
-- see the two notes below.
--
-- Gaps are now 1,470 -> 5,720 studs, so the next island is usually a speck or
-- entirely off-screen. This is the thing that tells you where to aim.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- The tower order is authoritative: slot (climb position) -> island MODEL number,
-- plus the display names. No name-parsing, no tags, no guessing.
local IslandOrder = require(RS:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

local CONFIG = {
	HIDE_WITHIN = 60,   -- hide once this close (studs) -- you can see the island by now
	SHOW_NAME   = true, -- show the island's name under the arrow
	NAME_GATE   = true, -- only reveal the name once you have REACHED that island
	EDGE_MARGIN = 60,   -- px in from the screen edge the clamped arrow stops at
	UPDATE_HZ   = 10,   -- refreshes per second
}

--======================================================================
-- HUD -- identical build to the main game's pointer, do not restyle
--======================================================================
local function mkStroke(p, col, t)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s
end
local function mkLabel(p, props)
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
	for k, v in pairs(props) do l[k] = v end
	l.Parent = p; return l
end
local function mkFrame(p, props)
	local f = Instance.new("Frame")
	for k, v in pairs(props) do f[k] = v end
	f.Parent = p; return f
end

local navSg = Instance.new("ScreenGui")
navSg.Name = "DinoNavGui"; navSg.ResetOnSpawn = false
-- IgnoreGuiInset is deliberately LEFT OFF. Camera:WorldToScreenPoint returns
-- coordinates that already EXCLUDE the topbar inset, so it only lines up with an
-- inset-respecting ScreenGui. Turning it on shifts the arrow ~36px off target.
navSg.Parent = player:WaitForChild("PlayerGui")

local navFrame = mkFrame(navSg, {
	Size = UDim2.new(0, 54, 0, 54), Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false,
})
local navArrow = mkLabel(navFrame, {
	Text = "\xe2\x86\x91", Font = Enum.Font.GothamBold, TextSize = 48,
	TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local navArrowStroke = mkStroke(navArrow, Color3.new(0, 0, 0), 5)
navArrowStroke.LineJoinMode = Enum.LineJoinMode.Round

local navName = mkLabel(navSg, {
	Text = "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
	Size = UDim2.new(0, 140, 0, 16), AnchorPoint = Vector2.new(0.5, 0),
	TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
})
mkStroke(navName, Color3.new(0, 0, 0), 1)

--======================================================================
-- TARGETS -- built from IslandOrder, so every entry carries its CLIMB SLOT
--======================================================================
-- Positions come from IslandOrder.SLOT_POS, NOT from the island models in Workspace.
--
-- With StreamingEnabled a distant island's MODEL replicates at join but its PARTS do
-- not, and GetPivot() on a partless model returns the ORIGIN. Reading the world made
-- every island the player had not visited report Y 0, which failed the "above me"
-- test, so pickTarget found nothing and the arrow never appeared.
--
-- Built once. The ladder is static, so there is nothing to rescan for.
local ISLANDS = {}
for slot = 1, IslandOrder.COUNT do
	local modelNum = IslandOrder.SLOT_TO_ISLAND[slot]
	local pos = IslandOrder.SLOT_POS[slot]
	if pos then
		ISLANDS[#ISLANDS + 1] = {
			pos  = pos,
			name = IslandOrder.NAMES[modelNum] or ("Island " .. modelNum),
			slot = slot,   -- CLIMB position, which is what the name gate compares
		}
	end
end

-- WHICH ISLAND ARE WE POINTING AT?
--
-- The lowest one still above you. Never the nearest (that is the one under your
-- feet) and never a fixed next-index (a player who skipped ahead would be sent
-- backwards). Height decides it, so this needs no progression data and cannot
-- desync from it -- and since the tower ascends strictly by slot, "lowest above
-- me" is always the next slot in the climb.
local function pickTarget(fromPos)
	local best, bestScore
	for _, isl in ipairs(ISLANDS) do
		local above = isl.pos.Y - fromPos.Y
		if above > CONFIG.HIDE_WITHIN and (not bestScore or above < bestScore) then
			best, bestScore = isl, above
		end
	end
	return best
end

-- NAME REVEAL: don't spoil an island you have not been to.
--
-- Gated on HighestSlot (climb position), NOT HighestIsland (the model number).
-- The original compared the number scraped out of the model name against
-- HighestIsland, which is wrong here: the tower scrambles model numbers against
-- climb order (SLOT_TO_ISLAND = {1,9,5,12,3,13,4,2,10,7,6,8,11}), so reaching the
-- second island sets HighestIsland = 9 and every island numbered 2..8 would have
-- leaked its name at once.
local function nameFor(isl)
	if not (CONFIG.SHOW_NAME and isl and isl.name ~= "") then return nil end
	if not CONFIG.NAME_GATE then return isl.name end
	local reached = tonumber(player:GetAttribute("HighestSlot"))
	if reached == nil then return isl.name end          -- not tracked yet -> no gate
	if isl.slot > reached then return nil end           -- not been there: arrow only
	return isl.name
end

--======================================================================
-- LOOP -- projection + edge-clamp + rotation, copied verbatim
--======================================================================
local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc = acc + dt
	if acc < (1 / CONFIG.UPDATE_HZ) then return end
	acc = 0

	pcall(function()
		local Camera = Workspace.CurrentCamera
		local char   = player.Character
		local hrp    = char and char:FindFirstChild("HumanoidRootPart")
		if not (Camera and hrp) then navFrame.Visible = false; navName.Visible = false; return end

		local isl = pickTarget(hrp.Position)
		if not isl then navFrame.Visible = false; navName.Visible = false; return end

		local target3D = isl.pos
		if (target3D - hrp.Position).Magnitude <= CONFIG.HIDE_WITHIN then
			navFrame.Visible = false; navName.Visible = false; return
		end

		local vp = Camera.ViewportSize
		local cx, cy = vp.X / 2, vp.Y / 2
		local screenPos = Camera:WorldToScreenPoint(target3D)
		local dx, dy = screenPos.X - cx, screenPos.Y - cy
		local margin = CONFIG.EDGE_MARGIN
		local maxX, maxY = cx - margin, cy - margin
		local ex, ey

		if screenPos.Z > 0 and math.abs(dx) < maxX and math.abs(dy) < maxY then
			-- on screen and in front: sit right on the target
			ex, ey = screenPos.X, screenPos.Y
		else
			-- Behind the camera flips the projection, so mirror it before the edge maths --
			-- without this the arrow points the opposite way whenever you turn your back.
			if screenPos.Z < 0 then dx, dy = -dx, -dy end
			if math.abs(dx) * maxY >= math.abs(dy) * maxX then
				local sign = dx >= 0 and 1 or -1
				ex = cx + sign * maxX
				ey = cy + dy * (maxX / math.max(math.abs(dx), 0.001))
			else
				local sign = dy >= 0 and 1 or -1
				ey = cy + sign * maxY
				ex = cx + dx * (maxY / math.max(math.abs(dy), 0.001))
			end
		end

		navFrame.Position = UDim2.new(0, ex, 0, ey)
		navArrow.Rotation = math.deg(math.atan2(dy, dx)) + 90
		navFrame.Visible  = true

		local label = nameFor(isl)
		if label then
			navName.Position = UDim2.new(0, ex, 0, ey + 26)
			navName.Text     = label
			navName.Visible  = true
		else
			navName.Visible = false
		end
	end)
end)

print("[DinoArrow] next-island pointer ready (" .. IslandOrder.COUNT .. " islands, gated on HighestSlot).")
