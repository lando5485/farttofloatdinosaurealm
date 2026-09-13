--======================================================================
-- JungleTheme.client.luau  (LocalScript)
--======================================================================
-- Puts the imported Fart-to-Float panels on this realm's jungle chrome, so every
-- menu in the game reads as one HUD.
--
-- The Shop, Stomach shop, Pet Hub and MORE+ all call JungleChrome directly. The
-- three panels that came from the FtF bundle -- Skin Crates, Season Pass, Free
-- Rewards -- shipped with their own palettes (magenta, cream, dark purple) and
-- looked like three different games bolted on.
--
-- WHY THIS IS A SEPARATE FILE. Those three are vendor code, byte-identical to the
-- bundle apart from one require path. Keeping them untouched means the next bundle
-- drop is a straight copy instead of a merge, so the restyle is applied from
-- outside instead of edited in.
--
-- CHROME ONLY. This recolours the panel shell, the header bar and the backdrop --
-- nothing else. Content colour in these panels carries MEANING: skin-crate tier
-- colours (Common grey through Gold), rarity bars, the Season Pass progress track.
-- Repainting those would destroy information, so they are deliberately left alone.
--======================================================================
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local okJC, JC = pcall(function()
	return require(RS:WaitForChild("DinosaurRealm"):WaitForChild("JungleChrome", 10))
end)
if not okJC or not JC then
	warn("[JungleTheme] JungleChrome module unavailable -- imported panels keep their own colours")
	return
end

local PARCHMENT = Color3.fromRGB(232, 209, 158)
local LEAF      = Color3.fromRGB(160, 200, 120)

-- 20px of bamboo on every side. Matches JungleChrome's own 740x560-around-700x520 so a
-- centred panel looks exactly as its author intended; the difference is that this is
-- measured off the panel rather than hard-coded, so it holds for any size or offset.
local SHELL_MARGIN = 40

-- The panels we restyle, and how to find the main 700x520 frame inside each.
local TARGETS = { "SkinCrateGui", "SeasonPassGui", "SocialRewardsGui", "DailyStreakGui" } -- DailyStreakGui = the MORE+ Rewards hub (DailyStreak.client)

-- The big panel is the widest 700-wide frame that is a direct child of the ScreenGui.
-- Matching on size rather than name keeps this working if the vendor renames a frame.
local function mainPanel(gui)
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("Frame") and c.Size.X.Offset >= 640 and c.Size.Y.Offset >= 440 then
			return c
		end
	end
	return nil
end

-- The header is the full-width bar pinned to the top of the panel.
local function headerOf(panel)
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("Frame") and c.Position.Y.Offset <= 2 and c.Size.Y.Offset > 0
			and c.Size.Y.Offset <= 96 and (c.Size.X.Scale >= 1 or c.Size.X.Offset >= 600) then
			return c
		end
	end
	return nil
end

local done = {}

local function restyle(gui)
	if done[gui] then return end
	local panel = mainPanel(gui)
	if not panel then return end
	done[gui] = true

	pcall(function() JC.buildShell(gui) end)   -- bamboo border behind the panel
	pcall(function() JC.stylePanel(panel) end) -- olive fill, corner 16, dark stroke

	-- buildShell parents the bamboo frame to the SCREENGUI, not to the panel, and pins it to
	-- screen centre at a fixed 740x560. Two things go wrong with that:
	--   * a panel that isn't dead-centre (Skin Crates sits at 0.5,-45) gets a shell 45px low
	--   * a panel that resizes (Season Pass tweens 660x490 -> 700x520 on open) outgrows it
	-- so instead of trusting those constants, the shell tracks the panel it belongs to.
	--
	-- Visibility has to follow too: the Stomach shop disables its whole ScreenGui when
	-- closed so its shell goes with it, but these keep the ScreenGui enabled and only hide
	-- the inner frame -- which left the shell on screen as a tan rectangle over the HUD.
	local shell = gui:FindFirstChild("JungleShell")
	if shell then
		local function fit()
			shell.AnchorPoint = panel.AnchorPoint
			shell.Position    = panel.Position
			shell.Size = UDim2.new(
				panel.Size.X.Scale, panel.Size.X.Offset + SHELL_MARGIN,
				panel.Size.Y.Scale, panel.Size.Y.Offset + SHELL_MARGIN)
			shell.Visible = panel.Visible
		end
		fit()
		for _, prop in ipairs({ "Visible", "Size", "Position", "AnchorPoint" }) do
			panel:GetPropertyChangedSignal(prop):Connect(fit)
		end
	end

	local hdr = headerOf(panel)
	if hdr then
		pcall(function()
			hdr.BackgroundColor3 = Color3.fromRGB(26, 48, 30)
			if not hdr:FindFirstChild("HdrGrad") then
				local g = Instance.new("UIGradient"); g.Name = "HdrGrad"; g.Rotation = 90
				g.Color = ColorSequence.new(Color3.fromRGB(34, 60, 38), Color3.fromRGB(22, 42, 26))
				g.Parent = hdr
			end
			-- header title text to parchment, so it reads on the dark green bar
			for _, d in ipairs(hdr:GetDescendants()) do
				if d:IsA("TextLabel") and d.TextSize >= 20 then d.TextColor3 = PARCHMENT end
			end
		end)
	end

	-- the full-screen dim behind these panels: warm it so it matches the jungle
	-- backdrop instead of the bundle's cold black
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("Frame") and c.Size.X.Scale >= 1 and c.Size.Y.Scale >= 1 and c.BackgroundTransparency < 1 then
			c.BackgroundColor3 = Color3.fromRGB(18, 26, 16)
		end
	end

	print("[JungleTheme] restyled " .. gui.Name)
end

-- These panels build a second or two after join, and Season Pass rebuilds its track
-- on open, so watch rather than sweeping once.
local function watch()
	for _, name in ipairs(TARGETS) do
		local gui = PlayerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then restyle(gui) end
	end
end

watch()
PlayerGui.ChildAdded:Connect(function(c)
	if c:IsA("ScreenGui") and table.find(TARGETS, c.Name) then
		task.defer(function() task.wait(0.25); restyle(c) end)
	end
end)
for _, t in ipairs({ 1, 3, 6, 12 }) do task.delay(t, watch) end

print("[JungleTheme] ready -- imported panels follow the realm's jungle chrome (chrome only, content colours untouched)")
