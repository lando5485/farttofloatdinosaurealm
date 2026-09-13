--======================================================================
-- MenuBackButton.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- A BACK button on every panel you reach through MORE+ -- ported from the first realm (Fart to Float, push
-- 8a5041b), where the same script does the same job. The Rewards hub already draws its own BACK; this adds the
-- matching button to the other MORE+ cards so none of them is a one-way trip:
--
--   Rebirth / Wormhole / Send a Gift   ->  back to MORE+
--
-- ===== ONE SCRIPT, NOT THREE EDITS =====
-- Each panel is owned by a different script. Editing all of them to add the same button means three chances
-- to break a panel that works, and three places to keep in sync. This injects the button from outside
-- instead: it watches for a panel becoming visible, adds a button if one is not already there, and touches
-- nothing else. Everything it adds is named "RG_Back", so a re-run finds its own work and never doubles up.
--
-- The same file runs in Space Realm and the Dino Realm: the panel names match across the realms, and every
-- realm-specific hook below is guarded, so a realm that lacks one simply takes the safe fallback path.
--======================================================================

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player       = Players.LocalPlayer
local PlayerGui    = player:WaitForChild("PlayerGui")

--======================================================================
-- WHICH PANELS GET ONE (all go back to MORE+)
--======================================================================
local PANELS = {
	RebirthGui   = true,
	WormholeMenu = true,
	GiftGui      = true,
	-- DailyStreakGui (the Rewards hub) is NOT here: it draws its own BACK already.
	-- PetInventoryUI / SkinCrateGui are NOT here: the pet hub opens from the rail, and the crate panel's
	-- own tab bar is the way back to the hub.
}

-- The name each panel registers with the MainMenuManager, where it differs from the ScreenGui's name. The
-- fallback close path reports the close under this name, so the manager brings the HUD back.
local MENU_ALIAS = {
	WormholeMenu = "Wormhole",
	RebirthGui   = "Rebirth",
	GiftGui      = "GiftPanel",
}

local BACK_H = 36

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c end
local function stroke(o, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = o; return s end

--======================================================================
-- CLOSE THROUGH THE PANEL'S OWN CODE PATH
--
-- Closing by hand (Enabled = false AND Visible = false) breaks a panel permanently, because each panel's
-- toggle only ever flips ONE of those flags -- the other is left off with nothing to turn it back on. So close
-- the way its own X does: through its own toggle where it publishes one, otherwise by clearing only the flag
-- that is actually showing it.
--======================================================================
-- Each returns TRUE only if the owner was actually there to do the closing; otherwise the manual path runs.
local CLOSERS = {
	RebirthGui   = function() if _G.toggleRebirth   then _G.toggleRebirth();   return true end end,
	WormholeMenu = function() if _G.toggleWormhole  then _G.toggleWormhole();  return true end end,
	GiftGui      = function() if _G.toggleGiftPanel then _G.toggleGiftPanel(); return true end end,
}

-- The panel frame, by shape -- STRICTLY a Frame (a decorative shadow ImageLabel of panel size once caught the
-- button in the first realm).
local function bigFrame(gui)
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Offset >= 400 and ch.Size.Y.Offset >= 200 then return ch end
	end
	for _, ch in ipairs(gui:GetChildren()) do
		if ch.ClassName == "Frame" and ch.Size.X.Scale >= 0.5 and ch.Size.X.Scale < 1 then return ch end
	end
	return nil
end

local function closeGui(gui)
	-- Every closer is a TOGGLE, so only call it while the panel is actually up, or BACK would re-open it.
	local panel = bigFrame(gui)
	local showing = (not gui:IsA("ScreenGui") or gui.Enabled) and (panel == nil or panel.Visible)
	local fn = CLOSERS[gui.Name]
	if fn and showing then
		local ok, closed = pcall(fn)
		if ok and closed then return end
	end

	-- No owner hook: hide ONE flag, never both.
	if gui:IsA("ScreenGui") and gui.Enabled and (panel == nil or panel.Visible) then
		gui.Enabled = false
	elseif panel then
		panel.Visible = false
	end
	if _G.MainMenuManager and _G.MainMenuManager.notifyClosed then
		pcall(_G.MainMenuManager.notifyClosed, MENU_ALIAS[gui.Name] or gui.Name)
	end
end

local function openMore()
	-- The MORE+ owner publishes _G.setMoreOpen (Space: HudSidebarStats, Dino: Bootstrap). Going through it keeps
	-- ONE owner of that state.
	if _G.railGuardOpenMore then pcall(_G.railGuardOpenMore); return true end
	if _G.setMoreOpen then pcall(_G.setMoreOpen, true); return true end
	return false
end

--======================================================================
-- WHERE TO PUT IT: mirrored off the close X -- same size, anchor, corner and baseline, one gap to its left --
-- so the two read as a matched pair and nothing else on the panel has to move.
--======================================================================
local function findCloseX(panel)
	local best
	for _, ch in ipairs(panel:GetDescendants()) do
		if ch:IsA("TextButton") and ch.Name ~= "RG_Back" then
			local t = ch.Text
			if (t == "X" or t == "x" or t == "\xE2\x9C\x95" or t == "\xE2\x9C\x96")
				and ch.AbsoluteSize.X > 0 and ch.AbsoluteSize.X <= 60
				and (not best or ch.AbsolutePosition.Y < best.AbsolutePosition.Y)
			then
				best = ch
			end
		end
	end
	return best
end

local function inject(gui)
	local panel = bigFrame(gui)
	if not panel then return false end
	if panel:FindFirstChild("RG_Back", true) then return true end -- already done

	-- The first realm's back button: warm brown with a cream glyph. Matched to the X in SHAPE, distinct in
	-- COLOUR -- two red buttons side by side would both say "leave" and you could not tell which goes back.
	local b = Instance.new("TextButton")
	b.Name = "RG_Back"
	b.BackgroundColor3 = Color3.fromRGB(120, 78, 40)
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.fromRGB(255, 244, 214)
	b.AutoButtonColor = false
	b.Text = "\xE2\x97\x80" -- the left arrow
	b.TextSize = 20
	b.ZIndex = 50

	local x = findCloseX(panel)
	if x then
		-- The gap is measured off the X's RENDERED width: a close button with its own stroke draws wider than
		-- its Size says.
		local w = (x.AbsoluteSize.X > 0) and x.AbsoluteSize.X or BACK_H
		local radius = 10
		local xc = x:FindFirstChildOfClass("UICorner")
		if xc then radius = xc.CornerRadius.Offset end
		b.Size = x.Size
		b.AnchorPoint = x.AnchorPoint
		b.Position = UDim2.new(x.Position.X.Scale, x.Position.X.Offset - w - 14, x.Position.Y.Scale, x.Position.Y.Offset)
		b.ZIndex = math.max(b.ZIndex, x.ZIndex)
		b.Parent = x.Parent
		corner(b, radius)
	else
		-- No close button found: top-left of the panel, still where a player looks for Back.
		b.Size = UDim2.new(0, BACK_H, 0, BACK_H)
		b.Position = UDim2.new(0, 14, 0, 14)
		b.Parent = panel
		corner(b, 10); stroke(b, Color3.fromRGB(255, 255, 255), 1.5)
	end

	local sc = Instance.new("UIScale"); sc.Scale = 1; sc.Parent = b
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	b.MouseEnter:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1.05 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(152, 102, 56) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, ti, { Scale = 1 }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = Color3.fromRGB(120, 78, 40) }):Play()
	end)

	-- DEBOUNCED: closeGui may go through the panel's own TOGGLE, so a double-tap would close and re-open it.
	local lastBack = 0
	b.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastBack < 0.35 then return end
		lastBack = now
		if _G.playUIClick then pcall(_G.playUIClick) end
		closeGui(gui)
		-- Deferred: the panel we just closed may notify the menu manager, which can close other menus in the
		-- same frame -- including the one we are about to open.
		task.defer(openMore)
	end)
	return true
end

--======================================================================
-- WATCH: panels are often built after this script runs and some rebuild on respawn, so watch rather than
-- look once, and retry whenever a panel is shown.
--======================================================================
local hooked = {}

local function watch(gui)
	if not PANELS[gui.Name] or hooked[gui] then return end
	hooked[gui] = true

	local function tryInject()
		task.defer(function() pcall(inject, gui) end)
	end

	if gui:IsA("ScreenGui") then
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then tryInject() end
		end)
	end
	task.delay(0.5, function()
		local panel = bigFrame(gui)
		if panel then
			panel:GetPropertyChangedSignal("Visible"):Connect(function()
				if panel.Visible then tryInject() end
			end)
		end
	end)
	tryInject()
end

for _, gui in ipairs(PlayerGui:GetChildren()) do watch(gui) end
PlayerGui.ChildAdded:Connect(function(gui) task.defer(watch, gui) end)

-- Catch-all sweep: some panels finish building several seconds in.
for _, t in ipairs({ 2, 5, 10, 20 }) do
	task.delay(t, function()
		for _, gui in ipairs(PlayerGui:GetChildren()) do
			if PANELS[gui.Name] and gui:IsA("ScreenGui") and gui.Enabled then pcall(inject, gui) end
		end
	end)
end

print("[MenuBack] ready -- BACK on Rebirth / Wormhole / Send a Gift -> MORE+ (the Rewards hub has its own)")
