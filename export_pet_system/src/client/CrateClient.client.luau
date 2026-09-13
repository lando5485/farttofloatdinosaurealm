--!nonstrict
-- CrateClient (StarterPlayerScripts/CrateClient)
-- Client presentation for the Mystery Meteor Crate. The server (CrateService) is the sole
-- authority — this script only:
--   * Mirrors lastCrateClaim from the state snapshot to compute LOCAL readiness, exposed as
--     _G.crateIsClaimable so the existing More menu (CoreClient) drives the ready "!" dot.
--   * The live entry point is the "Daily Rewards" row in the existing in-game More menu, which
--     fires the OpenMeteorCrate BindableEvent (this script has NO HUD button of its own).
--   * Shows a pet picker (which OWNED pet receives the levels), then ClaimCrate:InvokeServer(petId)
--     and plays the crack-open reveal of the result (rarity + "+N Levels" + "Lv X -> Y").
--   * Also reveals the dev /crate result pushed via CrateResult (no tap needed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CRATE = Constants.CRATE

-- ===== OPEN TRIGGER (connected FIRST, before any blocking WaitForChild) =====
-- The More menu's "Daily Rewards" row fires ReplicatedStorage/OpenMeteorCrate. We create + connect
-- that listener immediately so a row tap is ALWAYS received on the correct shared instance, even if
-- the crate remotes below are still replicating. `attemptOpen` is forward-declared and assigned far
-- below once everything is built; until then a tap is a harmless no-op (logged).
local attemptOpen -- forward declaration (assigned near the bottom)
local OpenMeteorCrate = ReplicatedStorage:FindFirstChild("OpenMeteorCrate")
if not OpenMeteorCrate then
	OpenMeteorCrate = Instance.new("BindableEvent")
	OpenMeteorCrate.Name = "OpenMeteorCrate"
	OpenMeteorCrate.Parent = ReplicatedStorage
end
OpenMeteorCrate.Event:Connect(function()
	if attemptOpen then
		attemptOpen()
	else
		warn("[CrateClient] Daily Rewards tapped before the crate finished loading — try again in a moment")
	end
end)
print("[CrateClient] OpenMeteorCrate listener connected")

-- ===== remotes ===== (timeout + warn so a missing remote is diagnosable instead of an infinite hang)
local crateRemotes = ReplicatedStorage:WaitForChild("CrateRemotes", 30)
if not crateRemotes then
	warn("[CrateClient] CrateRemotes folder never appeared — is CrateService running on the server?")
	crateRemotes = ReplicatedStorage:WaitForChild("CrateRemotes")
end
local ClaimCrate = crateRemotes:WaitForChild("ClaimCrate")
local CrateResult = crateRemotes:WaitForChild("CrateResult")
local GetOwnedPets = crateRemotes:WaitForChild("GetOwnedPets")
local PreviewRoll = crateRemotes:WaitForChild("PreviewRoll")

-- petId -> displayName cache, refreshed whenever we fetch the owned-pet list (picker / reveal).
local petNameById = {}
local function fetchOwnedPets()
	local ok, list = pcall(function() return GetOwnedPets:InvokeServer() end)
	if ok and type(list) == "table" then
		for _, p in ipairs(list) do
			if p.petId then petNameById[p.petId] = p.displayName or p.petId end
		end
		return list
	end
	return {}
end

-- ===== local readiness mirror =====
local lastCrateClaim = 0

local function isClaimable()
	if lastCrateClaim == 0 then return true end
	return os.time() >= lastCrateClaim + CRATE.COOLDOWN_SECONDS
end
-- Exposed so the existing More menu (CoreClient) can drive the ready "!" dot on the Daily Rewards
-- row + the MORE button without owning the crate snapshot.
_G.crateIsClaimable = isClaimable

-- Snapshot wiring runs in its own thread so a slow StateRemotes replication can NEVER stall the
-- rest of this script (which must reach the OpenMeteorCrate connection so row taps open the crate).
task.spawn(function()
	Remotes.getStateChanged().OnClientEvent:Connect(function(snap)
		if type(snap) == "table" and snap.lastCrateClaim ~= nil then
			lastCrateClaim = tonumber(snap.lastCrateClaim) or 0
		end
	end)
	-- On-ready handshake: ask the server for a fresh snapshot.
	pcall(function() Remotes.getRequestState():FireServer() end)
end)

-- ===== sounds (pcall-guarded, 5s Debris cleanup) =====
local function playSound(id, volume)
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.Volume = volume or 0.6
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 5)
	end)
end

local SND_TAP        = 101638558691673 -- tap/open attempt; button presses -- STANDARD UI click (NOT the food-eat sound)
-- SND_SHAKE/SND_CRACK are the retired opening animation's cues. They are kept ONLY because the preload
-- list below still warms them and both ids currently fail to resolve in Studio -- leaving them named makes
-- that failure legible in the log instead of anonymous. Nothing plays them any more.
local SND_SHAKE      = 9116367700       -- (unused) meteor shake begins
local SND_CRACK      = 199578212        -- (unused) cracks form
local SND_BURST      = 4612378364       -- burst, non-Legendary (vol 0.85)
local SND_BURST_LEG  = 4612378364       -- burst, Legendary, larger (vol 0.85)

-- Reward-card REVEAL payoff sound (the moment the reward pops in). Persistent + reused each open; routed to the
-- SFXGroup so the Settings "Sound Effects" toggle mutes it like the other SFX.
local revealSound = Instance.new("Sound")
revealSound.Name = "CrateRevealSound"
revealSound.SoundId = "rbxassetid://4612378364"
revealSound.Volume = 0.5
revealSound.Parent = SoundService
task.spawn(function()
	local sfx = SoundService:FindFirstChild("SFXGroup") or SoundService:WaitForChild("SFXGroup", 30)
	if sfx and sfx:IsA("SoundGroup") then revealSound.SoundGroup = sfx end
end)
local REVEAL_SOUND_ID = "rbxassetid://4612378364"
local function playReveal()
	print("[CrateClient] playReveal fired (" .. REVEAL_SOUND_ID .. ")")
	-- Persistent instance restart (fast path).
	pcall(function() revealSound.TimePosition = 0; revealSound:Play() end)
	-- ROBUST fallback: a FRESH Sound each reveal, so a failed INITIAL preload of the persistent one (Studio's asset
	-- streaming is flaky and sometimes reports Failure on first fetch) can't silence the payoff. Cleans itself up.
	task.spawn(function()
		local s = Instance.new("Sound")
		s.Name = "CrateRevealSoundOneShot"
		s.SoundId = REVEAL_SOUND_ID
		s.Volume = 0.6
		local sfx = SoundService:FindFirstChild("SFXGroup")
		if sfx and sfx:IsA("SoundGroup") then s.SoundGroup = sfx end
		s.Parent = SoundService
		pcall(function() s:Play() end)
		game:GetService("Debris"):AddItem(s, 5)
	end)
end

-- [DIAG] Report whether each crate sound actually LOADS for this experience. "Success" = usable; "Failure" =
-- the asset isn't approved for this game (uploaded on another account, or an old privated "public" sound) OR the
-- id isn't audio. Read these lines in Output to see exactly which ids to replace.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local tmp = {}
	for _, id in ipairs({ SND_SHAKE, SND_CRACK, SND_BURST, SND_BURST_LEG, 4612378364 }) do
		local s = Instance.new("Sound"); s.SoundId = "rbxassetid://" .. tostring(id); s.Parent = SoundService; tmp[#tmp + 1] = s
	end
	pcall(function()
		ContentProvider:PreloadAsync(tmp, function(contentId, status)
			print(("[CrateSound DIAG] %s -> %s"):format(contentId, tostring(status)))
		end)
	end)
	for _, s in ipairs(tmp) do s:Destroy() end
end)


----------------------------------------------------------------------------------------
-- Reveal flow
----------------------------------------------------------------------------------------
local revealGui = Instance.new("ScreenGui")
revealGui.Name = "MeteorCrateReveal"
revealGui.ResetOnSpawn = false
revealGui.IgnoreGuiInset = true
revealGui.DisplayOrder = 100 -- match the shop ScreenGuis (DisplayOrder 100) so it layers above the HUD the same way
revealGui.Enabled = false
revealGui.Parent = playerGui

-- Click-catcher only -- its fill stays at transparency 1 forever, the world is never darkened. Visible is
-- what now toggles with the reveal, both to swallow stray taps only while it is open and because
-- RewardsClient reads Dim.Visible as its "a crate reveal is on screen" signal.
local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundTransparency = 1
dim.Visible = false
dim.Parent = revealGui

local revealing = false
local opening = false -- declared here (above freshReveal) so the reveal teardown can clear it

-- showMessage(text): brief notice (used for the no-pets case "Unlock A Pet To Receive Levels").
-- Routed through NotifyCenter's HERO lane instead of building its own ScreenGui at
-- UDim2.new(0.5,0,0,12) -- which is inside the same top-centre slot the arrival, purchase, event and
-- reward banners all used, with nothing arbitrating between them. Never consumes the crate timer.
local function showMessage(text)
	if revealing then return end
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		text     = text,
		color    = Color3.fromRGB(26, 28, 42),
		priority = NC.PRIORITY.REWARD,
		duration = 2.2,
	})
end

-- Build + animate the burst (flash + shards + rings; bigger for Legendary).
local function playBurst(isLegendary)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 0.1
	flash.ZIndex = 5
	flash.Parent = revealGui
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(0, 0)
	center.BackgroundTransparency = 1
	center.ZIndex = 6
	center.Parent = revealGui
	Debris:AddItem(center, 1.2)

	local ringCount = isLegendary and 3 or 2
	local maxRing = isLegendary and 520 or 360
	for i = 1, ringCount do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromOffset(40, 40)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 6
		ring.Parent = center
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local rs = Instance.new("UIStroke")
		rs.Color = isLegendary and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(180, 200, 255)
		rs.Thickness = 5
		rs.Parent = ring
		local sz = maxRing + i * 60
		TweenService:Create(ring, TweenInfo.new(0.5 + i * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(sz, sz) }):Play()
		TweenService:Create(rs, TweenInfo.new(0.5 + i * 0.08), { Transparency = 1 }):Play()
	end

	local shardCount = isLegendary and 18 or 10
	for i = 1, shardCount do
		local shard = Instance.new("Frame")
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Position = UDim2.fromScale(0.5, 0.5)
		shard.Size = UDim2.fromOffset(10, 10)
		shard.BackgroundColor3 = isLegendary and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(200, 210, 230)
		shard.ZIndex = 6
		shard.Parent = center
		local ang = (i / shardCount) * math.pi * 2
		local dist = (isLegendary and 320 or 220) + (i % 3) * 30
		TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		}):Play()
	end
end

-- Build the reveal card for a result and wire its button. closeFn tears the whole reveal down.
--   kind == "levels": rarity header, the pet that leveled, "+N Levels", "Lv X -> Y".
--   kind == "coins" : COINS! card (all owned pets maxed) -> AWESOME! only.
-- Forward-declared here (defined further down, in the icon-helper section) so the result card can
-- reuse the SAME pet avatar as the picker rows.
local drawPetIcon, petModelToViewport

local function buildCard(result, closeFn)
	local isCoins = (result.kind == "coins")
	local rarity = (not isCoins) and result.rarity or nil
	local rarityColor = (rarity and CRATE.RARITY_COLORS[rarity]) or Color3.fromRGB(255, 200, 60)
	local petName = (not isCoins) and (petNameById[result.petId] or result.petId) or nil
	local levelsAdded = result.levelsAdded or 0
	local newLevel = result.newLevel or 0
	local oldLevel = math.max(0, newLevel - levelsAdded)

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.42) -- raised above center so the bottom HUD never covers it
	card.Size = UDim2.fromOffset(320, 420)
	card.BackgroundColor3 = Color3.fromRGB(26, 79, 214) -- #1a4fd6
	card.ZIndex = 10
	card.Parent = revealGui
	-- soft drop shadow — parented to revealGui BEHIND the card (NOT as a child of the card: the card has
	-- a UIListLayout, which would lay these big frames out in its content column and shove the reward
	-- content off-screen — that was the "popup never appears" bug).
	for i, sp in ipairs({ 70, 48, 28 }) do
		local sh = Instance.new("Frame"); sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Position = UDim2.new(0.5, 0, 0.42, 6); sh.Size = UDim2.fromOffset(320 + sp, 420 + sp)
		sh.BackgroundColor3 = Color3.fromRGB(0, 12, 44); sh.BackgroundTransparency = ({ 0.86, 0.74, 0.58 })[i]
		sh.BorderSizePixel = 0; sh.ZIndex = 9; sh.Parent = revealGui
		local shc = Instance.new("UICorner"); shc.CornerRadius = UDim.new(0, 30); shc.Parent = sh
	end
	local cardCorner = Instance.new("UICorner"); cardCorner.CornerRadius = UDim.new(0, 24); cardCorner.Parent = card
	local cardGrad = Instance.new("UIGradient"); cardGrad.Rotation = 90 -- #1a4fd6 -> #0e3bb0
	cardGrad.Color = ColorSequence.new(Color3.fromRGB(26, 79, 214), Color3.fromRGB(14, 59, 176)); cardGrad.Parent = card
	local cardStroke = Instance.new("UIStroke"); cardStroke.Color = Color3.fromRGB(255, 255, 255); cardStroke.Thickness = 4; cardStroke.Parent = card -- thick white border

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 10)
	layout.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18); pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18); pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = card

	-- Rarity / reward header.
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 30)
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 24
	header.ZIndex = 11
	header.LayoutOrder = 1
	if isCoins then
		header.Text = "COINS!"
		header.TextColor3 = Color3.fromRGB(255, 210, 70)
	else
		header.Text = string.upper(rarity)
		header.TextColor3 = Color3.fromRGB(126, 217, 87) -- lime rarity (#7ed957)
	end
	header.Parent = card

	-- Icon: coin tile for the coin reward; for a level grant, the SAME avatar as the picker rows —
	-- the real in-game pet model in a ViewportFrame (spinning), vector-icon fallback if it can't clone.
	local iconHolder = Instance.new("Frame")
	iconHolder.BackgroundTransparency = 1
	iconHolder.Size = UDim2.fromOffset(140, 140)
	iconHolder.ZIndex = 11
	iconHolder.LayoutOrder = 2
	iconHolder.Parent = card
	if isCoins then
		local tile = Instance.new("TextLabel")
		tile.Size = UDim2.fromOffset(132, 132)
		tile.Position = UDim2.fromScale(0.5, 0.5)
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Font = Enum.Font.GothamBlack
		tile.TextScaled = true
		tile.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		tile.Text = "💰"
		tile.TextColor3 = Color3.fromRGB(80, 60, 10)
		tile.ZIndex = 11
		tile.Parent = iconHolder
		local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 16); tc.Parent = tile
	else
		-- glossy blue "radial-glow" square holding the spinning real pet model, ringed with sparkles
		local avatar = Instance.new("Frame")
		avatar.Size = UDim2.fromOffset(132, 132)
		avatar.Position = UDim2.fromScale(0.5, 0.5)
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.BackgroundColor3 = Color3.fromRGB(70, 150, 250)
		avatar.ClipsDescendants = true
		avatar.ZIndex = 11
		avatar.Parent = iconHolder
		local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 22); ac.Parent = avatar
		local ast = Instance.new("UIStroke"); ast.Color = Color3.fromRGB(255, 255, 255); ast.Thickness = 2; ast.Parent = avatar
		local ag = Instance.new("UIGradient"); ag.Rotation = 90
		ag.Color = ColorSequence.new(Color3.fromRGB(96, 176, 255), Color3.fromRGB(28, 96, 206)); ag.Parent = avatar
		-- soft radial glow disc behind the model (bright center)
		local glow = Instance.new("Frame"); glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.fromScale(0.86, 0.86); glow.BackgroundColor3 = Color3.fromRGB(192, 226, 255)
		glow.BackgroundTransparency = 0.5; glow.BorderSizePixel = 0; glow.ZIndex = 11; glow.Parent = avatar
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(1, 0); gc.Parent = glow
		local petObj = { petId = result.petId, displayName = petName }
		if not petModelToViewport(avatar, petObj) then
			drawPetIcon(avatar, petName) -- fallback: code-drawn vector icon
		end
		-- lime / cyan sparkle dots over the glow square
		local LIME, CYAN = Color3.fromRGB(126, 217, 87), Color3.fromRGB(94, 198, 255)
		for _, sp in ipairs({ {0.16, 0.18, 5, LIME}, {0.84, 0.24, 4, CYAN}, {0.22, 0.82, 4, CYAN}, {0.82, 0.80, 4.5, LIME} }) do
			local s = Instance.new("Frame"); s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.fromScale(sp[1], sp[2]); s.Size = UDim2.fromOffset(sp[3] * 2, sp[3] * 2)
			s.BackgroundColor3 = sp[4]; s.BackgroundTransparency = 0.05
			s.BorderSizePixel = 0; s.ZIndex = 14; s.Parent = avatar
			local scn = Instance.new("UICorner"); scn.CornerRadius = UDim.new(1, 0); scn.Parent = s
		end
	end

	-- Name: pet name (level grant) or coins amount.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 22
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.ZIndex = 11
	nameLabel.LayoutOrder = 3
	nameLabel.Text = isCoins and (tostring(result.coins) .. " Coins") or tostring(petName)
	nameLabel.Parent = card

	if not isCoins then
		-- "+N Levels" line.
		local gain = Instance.new("TextLabel")
		gain.BackgroundTransparency = 1
		gain.Size = UDim2.new(1, 0, 0, 26)
		gain.Font = Enum.Font.GothamBlack
		gain.TextSize = 24
		gain.TextColor3 = Color3.fromRGB(126, 217, 87) -- large lime (#7ed957)
		gain.ZIndex = 11
		gain.LayoutOrder = 4
		gain.Text = "+" .. tostring(levelsAdded) .. (levelsAdded == 1 and " Level" or " Levels")
		gain.Parent = card
		local gainGlow = Instance.new("UIStroke"); gainGlow.Color = Color3.fromRGB(126, 217, 87)
		gainGlow.Thickness = 2; gainGlow.Transparency = 0.35; gainGlow.Parent = gain -- lime glow

		-- "Lv X -> Y" line.
		local lv = Instance.new("TextLabel")
		lv.BackgroundTransparency = 1
		lv.Size = UDim2.new(1, 0, 0, 22)
		lv.Font = Enum.Font.GothamSemibold
		lv.TextSize = 17
		lv.TextColor3 = Color3.fromRGB(188, 234, 255) -- light blue
		lv.ZIndex = 11
		lv.LayoutOrder = 5
		lv.Text = "Lv " .. tostring(oldLevel) .. " → " .. tostring(newLevel)
		lv.Parent = card
	end

	-- Buttons. Coins -> AWESOME! only. Levels -> EQUIP NOW (equip the pet that leveled) + CLOSE.
	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, 46)
	btnRow.ZIndex = 11
	btnRow.LayoutOrder = 6
	btnRow.Parent = card
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = btnRow

	-- glossy beveled cartoon button: white->grey top-lit gradient + a darker rounded stroke
	local function makeBtn(text, color, strokeCol, order, width)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(width or 130, 44)
		b.BackgroundColor3 = color
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Text = text
		b.ZIndex = 12
		b.LayoutOrder = order
		b.Parent = btnRow
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = b
		local bg = Instance.new("UIGradient"); bg.Rotation = 90
		bg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(204, 204, 204)); bg.Parent = b
		local bs = Instance.new("UIStroke"); bs.Color = strokeCol; bs.Thickness = 2; bs.Parent = b
		return b
	end

	if isCoins then
		local awesome = makeBtn("AWESOME!", Color3.fromRGB(58, 214, 108), Color3.fromRGB(34, 162, 76), 1, 190)
		awesome.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			closeFn()
		end)
	else
		local equip = makeBtn("EQUIP NOW", Color3.fromRGB(46, 156, 255), Color3.fromRGB(22, 104, 210), 1) -- glossy cyan-blue
		equip.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			-- Equip the leveled pet via the same remote the pet inventory uses (best-effort).
			local ev = game:GetService("ReplicatedStorage"):FindFirstChild("PetEquipEvent")
			if ev and result.petId then pcall(function() ev:FireServer(result.petId) end) end
			closeFn()
		end)
		local close = makeBtn("CLOSE", Color3.fromRGB(46, 86, 152), Color3.fromRGB(30, 60, 114), 2) -- slate
		close.Activated:Connect(function()
			playSound(SND_TAP, 0.6)
			closeFn()
		end)
	end

	-- Pop-in (the reward reveal -> play the payoff sound).
	playReveal()
	card.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(320, 420) }):Play()
end

-- ===== BOTTOM HUD HIDE/RESTORE =====
-- While ANY Daily Rewards UI is up (picker modal OR reward popup), hide ONLY the bottom HUD — fart
-- meter, stomach bar, and the bottom buttons — so nothing covers the modal, then restore them EXACTLY
-- to their prior Enabled state when it closes. The LEFT-SIDE buttons (Shop / Invite / Stomach / More /
-- Return to Island, in SidebarGui) stay visible and are deliberately NOT in this list.
-- (Does not touch gameplay — purely shows/hides the GUIs.)
local HUD_GUIS = { "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }
local hudPrevEnabled = nil
local function setHudHidden(hidden)
	-- Tell the bottom-HUD authority in CoreClient that this reveal is a REAL reason to keep BottomStackGui off.
	-- Without the hold it re-enables the bottom buttons a quarter-second into the reveal, straight over the top
	-- of the modal. The other three GUIs in HUD_GUIS are not arbitrated there and are still restored below.
	if _G.hudHold then _G.hudHold("MeteorCrate", hidden) end
	if hidden then
		if hudPrevEnabled then return end -- already hidden; don't re-capture
		hudPrevEnabled = {}
		for _, name in ipairs(HUD_GUIS) do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				hudPrevEnabled[name] = g.Enabled
				g.Enabled = false
			end
		end
	else
		if not hudPrevEnabled then return end
		for _, name in ipairs(HUD_GUIS) do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and hudPrevEnabled[name] ~= nil then
				g.Enabled = hudPrevEnabled[name]
			end
		end
		hudPrevEnabled = nil
	end
end

-- freshReveal(): enable + clean the reveal layer, fade the dim in, and return a closeReveal()
-- teardown. Force-cleans any stale/stuck reveal (e.g. one interrupted by a respawn) so an open can
-- NEVER be blocked by leftover state — that was the stuck-flag trap behind the "missing reveal".
local function freshReveal()
	for _, ch in ipairs(revealGui:GetChildren()) do
		if ch ~= dim then ch:Destroy() end
	end
	revealing = true
	revealGui.Enabled = true
	setHudHidden(true) -- hide the bottom HUD for the whole Daily Rewards UI (picker + reward popup)
	dim.Visible = true -- no tint tween: the catcher is invisible, Visible is purely the open/closed signal
	local function closeReveal()
		for _, ch in ipairs(revealGui:GetChildren()) do
			if ch ~= dim then ch:Destroy() end
		end
		dim.Visible = false
		task.delay(0.25, function()
			revealGui.Enabled = false
			revealing = false
			opening = false
			setHudHidden(false) -- Daily Rewards UI fully closed -> restore the bottom HUD
		end)
	end
	return closeReveal
end

-- playMeteor(big, onDone): NO LONGER AN ANIMATION. The crate now opens STRAIGHT into the reveal.
--
-- What used to live here was a ~100-line set piece: a cratered rock that shook harder and harder, split
-- along radial cracks, and burst. It was a good effect and it was in the wrong place -- it ran BEFORE the
-- thing the player actually wants, every single time, and the crate reel that follows is itself a reveal
-- animation. Two reveals stacked back to back makes the first one a loading screen with a rock on it.
--
-- Kept as a function rather than deleted at the call sites on purpose: both openers (the daily tap and the
-- dev /crate result path) hand it an `onDone` and expect it to be called exactly once, so this is the one
-- place that behaviour is defined. `big` is now unused -- the Mythical burst it selected has no animation
-- left to scale, and the rarity still reads loud and clear on the card/reel that follows.
--
-- The old animation is in git history if it is ever wanted somewhere it does not delay a reward.
local function playMeteor(_big, onDone)
	if onDone then
		onDone()
	end
end

-- showResultCard(result, closeReveal): ensure the pet's name is known, then build the result card
-- (pcall'd so a card error can never leave the reveal stuck).
local function showResultCard(result, closeReveal)
	if result.kind == "levels" and result.petId and not petNameById[result.petId] then
		fetchOwnedPets()
	end
	revealGui.Enabled = true -- the reward popup lives here; make sure the layer is on
	local okCard, err = pcall(buildCard, result, closeReveal)
	if okCard then
		playReveal() -- rbxassetid://4612378364: reward-reveal payoff, the moment the "+N Levels" card pops in
		print("[CrateClient] reward popup built (kind=" .. tostring(result.kind) .. ")")
	else
		warn("[CrateClient] reward popup FAILED to build: " .. tostring(err))
		closeReveal()
	end
end

----------------------------------------------------------------------------------------
-- Open flow
----------------------------------------------------------------------------------------

-- claimAndReveal(petId, closeReveal): claim the chosen pet, then morph the already-open reveal into
-- the result card. This is the whole opening now; it resolves what the card shows.
local function claimAndReveal(petId, closeReveal)
	task.spawn(function()
		local ok, result = pcall(function() return ClaimCrate:InvokeServer(petId) end)
		if ok and type(result) == "table" then
			-- THE DAILY IS A FREE SKIN CRATE. The server already opened it; all that is left is to show it,
			-- and the crate shop's reel/result card is a far better payoff than this file's "+N levels" card
			-- would be for a skin. So this reveal closes here and SkinCrateClient takes the screen.
			if result.ok and result.kind == "skincrate" and type(_G.skinCrateShowReveal) == "function" then
				closeReveal()
				local shown = select(2, pcall(_G.skinCrateShowReveal, result.crateId, result.crate))
				-- If the crate shop is not up (script missing/erroring), the crate is STILL granted and sits in
				-- the Collection Book -- so say so rather than leaving the player with nothing on screen.
				-- closeReveal clears `revealing` on a 0.25s delay and showMessage refuses while it is set, so
				-- this has to wait for that teardown or the message is swallowed.
				if shown ~= true then
					task.delay(0.35, function() showMessage("Free Crate Opened! Check the Crates menu") end)
				end
				return
			end
			if result.ok then
				showResultCard(result, closeReveal)
				return
			elseif result.reason == "no_pets" then
				-- Only reachable now if the crate grant failed AND the old level path took over.
				closeReveal()
				showMessage("Unlock A Pet To Receive Levels")
				return
			elseif result.reason == "cooldown" then
				if result.nextClaimAt then lastCrateClaim = result.nextClaimAt - CRATE.COOLDOWN_SECONDS end
			end
		end
		-- Any failure (cooldown / no_profile / unexpected) -> just close the reveal cleanly.
		closeReveal()
	end)
end

-- ===== "Choose a Pet to Level Up" daily-crate modal — BRIGHT GLOSSY BLUE CARTOON theme (exact hexes) =====
local C = {
	bg       = Color3.fromRGB(10, 40, 90),
	panel    = Color3.fromRGB(26, 79, 214),    -- #1a4fd6 panel gradient TOP
	panelDk  = Color3.fromRGB(14, 59, 176),    -- #0e3bb0 panel gradient BOTTOM
	row      = Color3.fromRGB(47, 111, 224),   -- #2f6fe0 row body
	rowHi    = Color3.fromRGB(66, 130, 240),   -- hover lighten
	rowSel   = Color3.fromRGB(52, 120, 232),   -- selected fill (lime outline is the cue)
	rowEdge  = Color3.fromRGB(18, 56, 150),    -- darker bottom edge of rows
	navy     = Color3.fromRGB(12, 34, 86),     -- dark-navy XP track
	line     = Color3.fromRGB(120, 170, 250),  -- light-blue inner line
	text     = Color3.fromRGB(255, 255, 255),
	muted    = Color3.fromRGB(214, 232, 252),
	gold     = Color3.fromRGB(255, 210, 74),   -- #ffd24a
	goldDk   = Color3.fromRGB(208, 150, 24),
	lime     = Color3.fromRGB(126, 217, 87),   -- #7ed957 selection outline + accents
	limeA    = Color3.fromRGB(154, 232, 74),   -- #9ae84a "Level Up" gradient TOP
	limeB    = Color3.fromRGB(108, 198, 46),   -- #6cc62e "Level Up" gradient BOTTOM
	greenDk  = Color3.fromRGB(74, 150, 32),
	slate    = Color3.fromRGB(46, 86, 152),    -- Cancel / CLOSE
	slateDk  = Color3.fromRGB(30, 60, 114),
	cyan     = Color3.fromRGB(46, 156, 255),   -- "EQUIP NOW" cyan-blue
	cyanDk   = Color3.fromRGB(22, 104, 210),
	xp       = Color3.fromRGB(94, 198, 255),   -- #5ec6ff light-blue XP fill
	xpLt     = Color3.fromRGB(172, 226, 255),
	white    = Color3.fromRGB(255, 255, 255),
	avatarA  = Color3.fromRGB(40, 96, 206),    -- darker-blue avatar inset (gradient top)
	avatarB  = Color3.fromRGB(20, 64, 168),    -- avatar inset bottom
	dark     = Color3.fromRGB(74, 52, 0),      -- dark text on the gold badge
	shadow   = Color3.fromRGB(0, 12, 44),      -- soft drop shadow
	-- legacy keys kept (recolored) so existing references restyle automatically:
	violet   = Color3.fromRGB(255, 255, 255),  -- stray accent -> white
	violetLt = Color3.fromRGB(172, 226, 255),
	emerald  = Color3.fromRGB(124, 210, 70),   -- confirm lime-green base
}
local F_DISPLAY = Enum.Font.FredokaOne
local F_BODY    = Enum.Font.Gotham
local F_MED     = Enum.Font.GothamMedium
local F_BOLD    = Enum.Font.GothamBold

-- Emoji per pet, keyed on the food/animal in the name (checked in priority order so e.g. "Blossom
-- Bunny" -> blossom, "Broccoli Bunny" -> broccoli, "Pepper Pup" -> pepper). Falls back to a paw.
local PET_EMOJI = {
	blossom="🌸", broccoli="🥦", burrito="🌯", butter="🧈", coconut="🥥", popcorn="🍿",
	sunflower="🌻", maple="🍁", frost="❄️", penguin="🐧", pepper="🌶️", armadillo="🦔",
	bunny="🐰", rabbit="🐰", duck="🦆", crab="🦀", bee="🐝", fox="🦊", sheep="🐑", cat="🐱",
	pup="🐶", dog="🐶", moose="🫎", pig="🐷", bear="🐻", seal="🦭", gecko="🦎", sun="☀️",
	moon="🌙", star="⭐", milk="🥛", bread="🍞", pasta="🍝", pizza="🍕", burger="🍔",
	turnip="🥔", bean="🫘", cabbage="🥬", cherry="🍒", melon="🍈", pumpkin="🎃", sushi="🍣",
	banana="🍌", grape="🍇",
}
local PET_EMOJI_ORDER = {
	"blossom","broccoli","burrito","butter","coconut","popcorn","sunflower","maple","frost",
	"pepper","armadillo","penguin","bunny","rabbit","duck","crab","bee","fox","sheep","cat",
	"pup","dog","moose","pig","bear","seal","gecko","sun","moon","star","milk","bread","pasta",
	"pizza","burger","turnip","bean","cabbage","cherry","melon","pumpkin","sushi","banana","grape",
}
local function emojiFor(name)
	local l = string.lower(name or "")
	for _, key in ipairs(PET_EMOJI_ORDER) do
		if string.find(l, key, 1, true) then return PET_EMOJI[key] end
	end
	return "🐾"
end

local function mk(class, parent, props)
	local o = Instance.new(class)
	if props then for k, v in pairs(props) do o[k] = v end end
	o.Parent = parent
	return o
end
local function corner(inst, r) mk("UICorner", inst, { CornerRadius = UDim.new(0, r) }) end
local function stroke(inst, color, thick, transp)
	return mk("UIStroke", inst, { Color = color, Thickness = thick, Transparency = transp or 0 })
end
-- gloss(btn, strokeCol): glossy/beveled cartoon button — a vertical white->grey brightness ramp over
-- the button's color (top-lit sheen) plus a darker rounded stroke for the bevel edge.
local function gloss(btn, strokeCol)
	local g = mk("UIGradient", btn, { Rotation = 90 })
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(204, 204, 204))
	if strokeCol then stroke(btn, strokeCol, 2, 0) end
end

-- dropShadow(obj, padPx): soft drop shadow = a few concentric translucent dark rounded frames BEHIND
-- the object (no image asset). padPx compensates for the object's own UIPadding so the layers still
-- extend OUTSIDE its edges. Fine for fixed-size panels/cards (not AutomaticSize).
local function dropShadow(obj, padPx)
	padPx = padPx or 0
	local base = obj.ZIndex or 10
	for i, s in ipairs({ {66, 0.86}, {46, 0.74}, {26, 0.58} }) do
		local extra = padPx * 2 + s[1]
		local sh = mk("Frame", obj, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.new(1, extra, 1, extra), BackgroundColor3 = C.shadow,
			BackgroundTransparency = s[2], BorderSizePixel = 0, ZIndex = base - 4 + i,
		})
		mk("UICorner", sh, { CornerRadius = UDim.new(0, 30) })
	end
end

-- ===== code-drawn vector pet icons (Frames + UICorner; no text emoji, so they render in published
-- games where emoji glyphs are missing). shape() parents one colored block into the avatar, sized +
-- positioned by SCALE (0..1 of the 48px square). opts: circle=true (full round), r=<px> (corner), rot,
-- z. PET_ICONS[keyword](avatar) draws that food/animal from a few shapes. =====
local function shape(av, color, sx, sy, sxp, syp, opts)
	opts = opts or {}
	local f = mk("Frame", av, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sxp, syp),
		Size = UDim2.fromScale(sx, sy), BackgroundColor3 = color, BorderSizePixel = 0,
		BackgroundTransparency = opts.t or 0, Rotation = opts.rot or 0, ZIndex = opts.z or 13,
	})
	if opts.circle then
		mk("UICorner", f, { CornerRadius = UDim.new(1, 0) })
	elseif opts.r then
		mk("UICorner", f, { CornerRadius = UDim.new(0, opts.r) })
	end
	-- opts.grad = true adds a brightness ramp (white -> gradLo grey) that MULTIPLIES the base color,
	-- giving cheap round/3D shading. gradRot picks the light direction (90 = top-lit, the default).
	if opts.grad then
		local lo = opts.gradLo or 0.62
		local g = mk("UIGradient", f, { Rotation = opts.gradRot or 90 })
		g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(lo, lo, lo))
	end
	return f
end

local PET_ICONS = {
	coconut = function(a)
		shape(a, Color3.fromRGB(120, 80, 50), 0.86, 0.86, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.55 })
		shape(a, Color3.fromRGB(238, 222, 204), 0.46, 0.46, 0.50, 0.52, { circle = true, grad = true, gradLo = 0.8, z = 14 })
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.43, 0.47, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.57, 0.47, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(96, 62, 38), 0.09, 0.09, 0.50, 0.60, { circle = true, z = 15 }) -- hole
		shape(a, Color3.fromRGB(255, 255, 255), 0.16, 0.16, 0.33, 0.31, { circle = true, t = 0.55, z = 16 }) -- sheen
	end,
	broccoli = function(a)
		shape(a, Color3.fromRGB(150, 196, 120), 0.14, 0.36, 0.50, 0.76, { r = 4, grad = true, gradRot = 0 }) -- stalk
		shape(a, Color3.fromRGB(52, 132, 66), 0.66, 0.52, 0.50, 0.40, { circle = true, grad = true, gradLo = 0.58 }) -- crown
		shape(a, Color3.fromRGB(74, 158, 86), 0.34, 0.34, 0.32, 0.30, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(74, 158, 86), 0.34, 0.34, 0.68, 0.30, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(90, 178, 100), 0.32, 0.32, 0.50, 0.24, { circle = true, z = 14 }) -- floret
		shape(a, Color3.fromRGB(255, 255, 255), 0.12, 0.12, 0.36, 0.26, { circle = true, t = 0.6, z = 15 }) -- sheen
	end,
	burrito = function(a)
		shape(a, Color3.fromRGB(220, 184, 126), 0.82, 0.42, 0.50, 0.50, { r = 12, rot = -22, grad = true, gradLo = 0.66 })
		shape(a, Color3.fromRGB(180, 142, 92), 0.82, 0.08, 0.50, 0.41, { r = 4, rot = -22, z = 14 }) -- seam
		shape(a, Color3.fromRGB(120, 196, 110), 0.16, 0.18, 0.76, 0.40, { r = 4, rot = -22, z = 15 }) -- lettuce
		shape(a, Color3.fromRGB(224, 92, 72), 0.12, 0.14, 0.72, 0.50, { r = 3, rot = -22, z = 16 }) -- salsa
		shape(a, Color3.fromRGB(255, 255, 255), 0.5, 0.06, 0.46, 0.40, { r = 3, rot = -22, t = 0.62, z = 15 }) -- sheen
	end,
	butter = function(a)
		shape(a, Color3.fromRGB(150, 116, 40), 0.66, 0.22, 0.52, 0.66, { r = 5 }) -- shaded base
		shape(a, Color3.fromRGB(245, 205, 80), 0.66, 0.44, 0.50, 0.56, { r = 6, grad = true, gradLo = 0.74 })
		shape(a, Color3.fromRGB(252, 228, 140), 0.66, 0.16, 0.50, 0.40, { r = 5, z = 14 }) -- top slab
		shape(a, Color3.fromRGB(255, 255, 255), 0.16, 0.1, 0.36, 0.40, { r = 3, t = 0.5, z = 15 }) -- sheen
	end,
	pepper = function(a)
		shape(a, Color3.fromRGB(200, 48, 40), 0.50, 0.62, 0.50, 0.60, { r = 16, rot = 6, grad = true, gradLo = 0.62 })
		shape(a, Color3.fromRGB(248, 120, 100), 0.10, 0.40, 0.40, 0.58, { r = 6, rot = 6, t = 0.35, z = 15 }) -- highlight
		shape(a, Color3.fromRGB(70, 150, 70), 0.16, 0.22, 0.52, 0.22, { r = 4, z = 14 }) -- stem
		shape(a, Color3.fromRGB(86, 176, 90), 0.24, 0.10, 0.44, 0.18, { r = 3, rot = -25, z = 14 }) -- leaf
	end,
	bunny = function(a)
		shape(a, Color3.fromRGB(236, 236, 244), 0.20, 0.42, 0.40, 0.28, { circle = true, grad = true, gradLo = 0.82 }) -- ear
		shape(a, Color3.fromRGB(236, 236, 244), 0.20, 0.42, 0.60, 0.28, { circle = true, grad = true, gradLo = 0.82 }) -- ear
		shape(a, Color3.fromRGB(245, 200, 212), 0.09, 0.26, 0.40, 0.29, { circle = true, z = 14 }) -- inner ear
		shape(a, Color3.fromRGB(245, 200, 212), 0.09, 0.26, 0.60, 0.29, { circle = true, z = 14 }) -- inner ear
		shape(a, Color3.fromRGB(246, 246, 250), 0.58, 0.54, 0.50, 0.62, { circle = true, grad = true, gradLo = 0.84, z = 14 }) -- head
		shape(a, Color3.fromRGB(40, 36, 44), 0.07, 0.08, 0.40, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(40, 36, 44), 0.07, 0.08, 0.60, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(248, 170, 188), 0.10, 0.07, 0.50, 0.69, { circle = true, z = 15 }) -- nose
	end,
	blossom = function(a)
		local petal = Color3.fromRGB(248, 168, 200)
		shape(a, petal, 0.34, 0.34, 0.50, 0.26, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.50, 0.74, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.26, 0.50, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, petal, 0.34, 0.34, 0.74, 0.50, { circle = true, grad = true, gradLo = 0.82 })
		shape(a, Color3.fromRGB(250, 206, 84), 0.30, 0.30, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.72, z = 15 }) -- center
		shape(a, Color3.fromRGB(190, 140, 40), 0.07, 0.07, 0.50, 0.50, { circle = true, z = 16 }) -- pollen dot
	end,
	popcorn = function(a)
		local cream = Color3.fromRGB(250, 240, 202)
		shape(a, cream, 0.38, 0.38, 0.38, 0.30, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, cream, 0.38, 0.38, 0.64, 0.28, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, cream, 0.40, 0.40, 0.50, 0.44, { circle = true, grad = true, gradLo = 0.78 })
		shape(a, Color3.fromRGB(228, 90, 80), 0.56, 0.34, 0.50, 0.80, { r = 4, z = 14 }) -- box
		shape(a, Color3.fromRGB(245, 245, 245), 0.10, 0.34, 0.42, 0.80, { z = 15 }) -- stripe
		shape(a, Color3.fromRGB(245, 245, 245), 0.10, 0.34, 0.58, 0.80, { z = 15 }) -- stripe
	end,
	sunflower = function(a)
		local petal = Color3.fromRGB(250, 198, 66)
		shape(a, petal, 0.30, 0.30, 0.50, 0.22, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.50, 0.78, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.26, 0.36, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.74, 0.36, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.26, 0.64, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, petal, 0.30, 0.30, 0.74, 0.64, { circle = true, grad = true, gradLo = 0.8 })
		shape(a, Color3.fromRGB(104, 68, 36), 0.42, 0.42, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.7, z = 15 }) -- seed center
	end,
	maple = function(a)
		local o = Color3.fromRGB(222, 98, 42)
		shape(a, o, 0.48, 0.48, 0.50, 0.44, { r = 6, rot = 45, grad = true, gradLo = 0.7 }) -- center lobe
		shape(a, o, 0.30, 0.30, 0.28, 0.36, { r = 4, rot = 45 }) -- lobe
		shape(a, o, 0.30, 0.30, 0.72, 0.36, { r = 4, rot = 45 }) -- lobe
		shape(a, o, 0.26, 0.26, 0.50, 0.22, { r = 4, rot = 45 }) -- top lobe
		shape(a, Color3.fromRGB(150, 92, 52), 0.05, 0.28, 0.50, 0.80, { r = 3 }) -- stem
		shape(a, Color3.fromRGB(255, 206, 160), 0.06, 0.22, 0.46, 0.46, { r = 2, rot = 45, t = 0.4, z = 15 }) -- vein
	end,
	frost = function(a)
		local w = Color3.fromRGB(206, 232, 252)
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 0, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 60, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.84, 0.11, 0.50, 0.50, { r = 4, rot = 120, grad = true, gradRot = 0, gradLo = 0.85 })
		shape(a, w, 0.13, 0.13, 0.50, 0.15, { circle = true, z = 15 }) -- tip
		shape(a, w, 0.13, 0.13, 0.50, 0.85, { circle = true, z = 15 }) -- tip
		shape(a, Color3.fromRGB(240, 250, 255), 0.22, 0.22, 0.50, 0.50, { circle = true, z = 16 }) -- core
	end,
	penguin = function(a)
		shape(a, Color3.fromRGB(40, 44, 54), 0.64, 0.82, 0.50, 0.52, { circle = true, grad = true, gradLo = 0.62 }) -- body
		shape(a, Color3.fromRGB(240, 242, 248), 0.36, 0.56, 0.50, 0.60, { circle = true, grad = true, gradLo = 0.86, z = 14 }) -- belly
		shape(a, Color3.fromRGB(20, 22, 28), 0.08, 0.08, 0.42, 0.36, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(20, 22, 28), 0.08, 0.08, 0.58, 0.36, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.03, 0.03, 0.43, 0.35, { circle = true, z = 17 }) -- glint
		shape(a, Color3.fromRGB(246, 160, 50), 0.15, 0.12, 0.50, 0.45, { r = 3, rot = 45, z = 16 }) -- beak
		shape(a, Color3.fromRGB(244, 150, 44), 0.16, 0.08, 0.40, 0.93, { r = 3, z = 15 }) -- foot
		shape(a, Color3.fromRGB(244, 150, 44), 0.16, 0.08, 0.60, 0.93, { r = 3, z = 15 }) -- foot
	end,
	armadillo = function(a)
		shape(a, Color3.fromRGB(152, 122, 94), 0.74, 0.52, 0.46, 0.56, { r = 18, grad = true, gradLo = 0.6 }) -- shell
		shape(a, Color3.fromRGB(120, 94, 70), 0.08, 0.50, 0.38, 0.56, { z = 14 }) -- band
		shape(a, Color3.fromRGB(120, 94, 70), 0.08, 0.50, 0.50, 0.56, { z = 14 }) -- band
		shape(a, Color3.fromRGB(170, 140, 108), 0.28, 0.30, 0.80, 0.50, { circle = true, grad = true, gradLo = 0.72 }) -- head
		shape(a, Color3.fromRGB(28, 24, 22), 0.06, 0.06, 0.85, 0.46, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.4, 0.06, 0.44, 0.42, { r = 3, t = 0.6, z = 15 }) -- sheen
	end,
	duck = function(a)
		shape(a, Color3.fromRGB(248, 206, 70), 0.60, 0.48, 0.44, 0.60, { circle = true, grad = true, gradLo = 0.7 }) -- body
		shape(a, Color3.fromRGB(250, 216, 90), 0.36, 0.36, 0.64, 0.38, { circle = true, grad = true, gradLo = 0.8, z = 14 }) -- head
		shape(a, Color3.fromRGB(238, 222, 138), 0.30, 0.22, 0.40, 0.62, { r = 8, t = 0.2, z = 14 }) -- wing
		shape(a, Color3.fromRGB(242, 150, 44), 0.18, 0.10, 0.82, 0.42, { r = 3, z = 15 }) -- bill
		shape(a, Color3.fromRGB(26, 26, 30), 0.06, 0.06, 0.66, 0.32, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.025, 0.025, 0.67, 0.31, { circle = true, z = 17 }) -- glint
	end,
	crab = function(a)
		shape(a, Color3.fromRGB(220, 62, 50), 0.66, 0.42, 0.50, 0.58, { r = 14, grad = true, gradLo = 0.66 }) -- shell
		shape(a, Color3.fromRGB(232, 86, 74), 0.22, 0.22, 0.24, 0.36, { circle = true, grad = true, gradLo = 0.75 }) -- claw
		shape(a, Color3.fromRGB(232, 86, 74), 0.22, 0.22, 0.76, 0.36, { circle = true, grad = true, gradLo = 0.75 }) -- claw
		shape(a, Color3.fromRGB(20, 20, 24), 0.07, 0.07, 0.42, 0.50, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(20, 20, 24), 0.07, 0.07, 0.58, 0.50, { circle = true, z = 16 }) -- eye
		shape(a, Color3.fromRGB(255, 255, 255), 0.4, 0.06, 0.46, 0.46, { r = 3, t = 0.6, z = 15 }) -- sheen
	end,
	bee = function(a)
		shape(a, Color3.fromRGB(248, 204, 70), 0.62, 0.46, 0.52, 0.56, { r = 13, grad = true, gradLo = 0.7 }) -- body
		shape(a, Color3.fromRGB(40, 36, 32), 0.11, 0.46, 0.46, 0.56, { z = 14 }) -- stripe
		shape(a, Color3.fromRGB(40, 36, 32), 0.11, 0.46, 0.62, 0.56, { z = 14 }) -- stripe
		shape(a, Color3.fromRGB(236, 244, 252), 0.26, 0.32, 0.30, 0.34, { circle = true, t = 0.15, z = 15 }) -- wing
		shape(a, Color3.fromRGB(40, 36, 32), 0.18, 0.18, 0.74, 0.50, { circle = true, z = 15 }) -- head
		shape(a, Color3.fromRGB(255, 255, 255), 0.05, 0.05, 0.78, 0.46, { circle = true, z = 16 }) -- eye glint
	end,
	fox = function(a)
		local o = Color3.fromRGB(228, 124, 46)
		shape(a, o, 0.26, 0.26, 0.30, 0.28, { r = 3, rot = 45, grad = true, gradLo = 0.7 }) -- ear
		shape(a, o, 0.26, 0.26, 0.70, 0.28, { r = 3, rot = 45, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(40, 30, 26), 0.10, 0.10, 0.30, 0.23, { r = 2, rot = 45, z = 14 }) -- ear tip
		shape(a, Color3.fromRGB(40, 30, 26), 0.10, 0.10, 0.70, 0.23, { r = 2, rot = 45, z = 14 }) -- ear tip
		shape(a, o, 0.62, 0.56, 0.50, 0.56, { r = 16, grad = true, gradLo = 0.74 }) -- head
		shape(a, Color3.fromRGB(246, 246, 250), 0.34, 0.32, 0.50, 0.66, { r = 9, z = 14 }) -- snout
		shape(a, Color3.fromRGB(30, 24, 22), 0.07, 0.07, 0.40, 0.52, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(30, 24, 22), 0.07, 0.07, 0.60, 0.52, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(26, 22, 20), 0.10, 0.08, 0.50, 0.71, { circle = true, z = 16 }) -- nose
	end,
	sheep = function(a)
		local wfl = Color3.fromRGB(244, 244, 248)
		shape(a, wfl, 0.36, 0.36, 0.32, 0.38, { circle = true, grad = true, gradLo = 0.82 }) -- fluff
		shape(a, wfl, 0.36, 0.36, 0.68, 0.38, { circle = true, grad = true, gradLo = 0.82 }) -- fluff
		shape(a, wfl, 0.40, 0.40, 0.50, 0.32, { circle = true, grad = true, gradLo = 0.82 }) -- fluff top
		shape(a, wfl, 0.62, 0.50, 0.50, 0.58, { circle = true, grad = true, gradLo = 0.86, z = 13 }) -- fluff body
		shape(a, Color3.fromRGB(72, 68, 80), 0.32, 0.36, 0.50, 0.60, { circle = true, grad = true, gradLo = 0.72, z = 14 }) -- face
		shape(a, Color3.fromRGB(245, 245, 250), 0.06, 0.07, 0.44, 0.58, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(245, 245, 250), 0.06, 0.07, 0.56, 0.58, { circle = true, z = 15 }) -- eye
	end,
	pup = function(a)
		shape(a, Color3.fromRGB(138, 94, 58), 0.24, 0.42, 0.28, 0.36, { r = 8, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(138, 94, 58), 0.24, 0.42, 0.72, 0.36, { r = 8, grad = true, gradLo = 0.7 }) -- ear
		shape(a, Color3.fromRGB(172, 122, 80), 0.60, 0.56, 0.50, 0.52, { r = 16, grad = true, gradLo = 0.76 }) -- head
		shape(a, Color3.fromRGB(216, 184, 144), 0.32, 0.30, 0.50, 0.66, { r = 9, z = 14 }) -- snout
		shape(a, Color3.fromRGB(34, 28, 26), 0.10, 0.09, 0.50, 0.62, { circle = true, z = 15 }) -- nose
		shape(a, Color3.fromRGB(34, 28, 26), 0.07, 0.08, 0.38, 0.46, { circle = true, z = 15 }) -- eye
		shape(a, Color3.fromRGB(34, 28, 26), 0.07, 0.08, 0.62, 0.46, { circle = true, z = 15 }) -- eye
	end,
}
PET_ICONS.rabbit = PET_ICONS.bunny -- name aliases (same icon)
PET_ICONS.dog = PET_ICONS.pup

-- drawPetIcon(avatar, name): same keyword priority as emojiFor; draws the matching vector icon, or a
-- generic rounded dot if nothing matches. (Assigns the forward-declared upvalue above.)
function drawPetIcon(av, name)
	local l = string.lower(name or "")
	for _, key in ipairs(PET_EMOJI_ORDER) do
		local fn = PET_ICONS[key]
		if fn and string.find(l, key, 1, true) then
			fn(av)
			return
		end
	end
	-- generic fallback: a soft shaded dot with a small sheen
	shape(av, Color3.fromRGB(150, 160, 200), 0.50, 0.50, 0.50, 0.50, { circle = true, grad = true, gradLo = 0.62 })
	shape(av, Color3.fromRGB(255, 255, 255), 0.16, 0.16, 0.40, 0.38, { circle = true, t = 0.55, z = 14 })
end

-- ===== REAL pet model in a ViewportFrame (primary avatar display) =====
-- PetSystem builds the fused pet templates and parents them to ReplicatedStorage, named
-- "<DisplayNameNoSpaces>Template" (e.g. "Broccoli Bunny" -> BroccoliBunnyTemplate, "Coconut Crab" ->
-- CoconutCrabTemplate). We clone that exact model so the avatar matches the in-game pet.
local function findPetTemplate(p)
	local dn = (p.displayName or ""):gsub("%s+", "")
	local id = p.petId or ""
	for _, nm in ipairs({ dn .. "Template", dn, id .. "Template", id }) do
		if nm ~= "" and nm ~= "Template" then
			local m = ReplicatedStorage:FindFirstChild(nm) or workspace:FindFirstChild(nm)
			if m and m:IsA("Model") then return m end
		end
	end
	return nil
end

-- petModelToViewport(avatar, p): clone the real pet model into a ViewportFrame filling the avatar,
-- frame a camera on it and light it so it reads at 48px. Returns true on success, false if there's no
-- model to clone (caller then draws the vector icon). The avatar's gradient shows behind (viewport bg
-- is transparent); ClipsDescendants on the avatar rounds the viewport to the square's corners.
local VIEWPORT_SPIN_SPEED = 0.9 -- radians/sec — slow continuous Y-axis turn, like the pets HUD

function petModelToViewport(avatar, p)
	local template = findPetTemplate(p)
	if not template then return false end
	local vp = mk("ViewportFrame", avatar, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 13,
		Ambient = Color3.fromRGB(150, 154, 170),       -- fill so the model isn't muddy at small size
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.55).Unit, -- key light from upper-front
	})
	local ok = pcall(function()
		local clone = template:Clone()
		clone.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 50
		cam.Parent = vp
		vp.CurrentCamera = cam
		-- frame the model: aim at its bounding-box center from a 3/4 angle, far enough to fit it.
		local cf, size = clone:GetBoundingBox()
		local center = cf.Position
		local extent = math.max(size.X, size.Y, size.Z, 0.1)
		local dist = (extent * 0.5) / math.tan(math.rad(cam.FieldOfView * 0.5)) * 1.45 + extent * 0.2
		local baseDir = Vector3.new(0.5, 0.42, 1).Unit
		-- CONTINUOUS SPIN: orbit the camera around the model's vertical axis every frame (keeps the
		-- model + welds untouched). The connection self-disconnects once the viewport is destroyed.
		local angle = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not vp.Parent then conn:Disconnect(); return end
			angle = angle + dt * VIEWPORT_SPIN_SPEED
			cam.CFrame = CFrame.lookAt(center + (CFrame.Angles(0, angle, 0) * baseDir) * dist, center)
		end)
		vp.Destroying:Connect(function() conn:Disconnect() end)
	end)
	if not ok then
		vp:Destroy()
		return false
	end
	return true
end

-- showPicker(pets, closeReveal, onPick): the "Choose a Pet to Level Up" modal, rendered INSIDE the
-- already-open reveal (after the burst). All OWNED pets are listed; maxed pets are greyed + "MAX" and
-- not selectable. Select -> Level Up confirm -> onPick(petId); Cancel -> closeReveal() tears it down.
-- header colors for the rolled rarity (driven by the server's PreviewRoll result)
local RARITY_HEX = { Uncommon = "#9fe1cb", Rare = "#85b7eb", Epic = "#afa9ec", Mythical = "#ffc83d" }
local MAX_LV = CRATE.PET_MAX_LEVEL or 25

local function showPicker(pets, roll, closeReveal, onPick)
	local done = false
	local selected = nil          -- the chosen pet entry (non-maxed); only WHICH pet is chosen
	local tokens = 1              -- the available daily-crate claim, shown as a spendable token
	local rowApis = {}
	-- The rolled rarity + level amount are decided by the SERVER (PreviewRoll), not the player.
	local rarity = roll and roll.rarity or nil
	local levelsAdded = (roll and roll.levelsAdded) or 1
	local rarityHex = (rarity and RARITY_HEX[rarity]) or "#8b93b5"

	-- ----- modal panel: EXACT same Size/Position/AnchorPoint as the Pets Hub / shop panel (copied
	-- verbatim: 700 x 520 fixed, centered, nudged up 45px) + the SAME adaptive UIScale factor the shops
	-- get via _G.applyHudScaling — so it opens at identical dimensions and scale. (DisplayOrder 100.) ---
	local panel = mk("Frame", revealGui, {
		Name = "PetPicker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -45),
		Size = UDim2.new(0, 700, 0, 520), BackgroundColor3 = C.panel, ZIndex = 10,
	})
	corner(panel, 24)
	stroke(panel, C.white, 4, 0) -- thick white rounded cartoon border
	dropShadow(panel, 24) -- soft drop shadow behind the panel
	local panelGrad = mk("UIGradient", panel, { Rotation = 90 }) -- #1a4fd6 -> #0e3bb0 vertical gradient
	panelGrad.Color = ColorSequence.new(C.panel, C.panelDk)
	mk("UIPadding", panel, {
		PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 22),
		PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22),
	})
	-- adaptive UIScale: the SAME factor ShopClient/_G.applyHudScaling applies, min(vp.X/1280, vp.Y/720, 1),
	-- kept in sync with the viewport so the panel tracks the shops across screen sizes.
	local uiScale = mk("UIScale", panel, { Scale = 1 })
	local function applyShopScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		uiScale.Scale = math.min(vp.X / 1280, vp.Y / 720, 1)
	end
	applyShopScale()
	do
		local cam = workspace.CurrentCamera
		if cam then
			local cc = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyShopScale)
			panel.Destroying:Connect(function() cc:Disconnect() end)
		end
	end

	-- inner content FILLS the panel (header pinned top, list fills the middle, footer pinned bottom —
	-- the shop layout). The token pill floats top-right as a separate child of `panel`.
	local HEADER_H, FOOTER_H, GAP = 112, 64, 10
	local content = mk("Frame", panel, {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 11,
	})

	-- ----- token pill (top-right, gold coin "↑" + count) -----
	local pill = mk("Frame", panel, { -- gold rounded pill, white outline
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(74, 34), BackgroundColor3 = C.gold, ZIndex = 14,
	})
	corner(pill, 999)
	stroke(pill, C.white, 2, 0)
	local pillGrad = mk("UIGradient", pill, { Rotation = 90 }) -- gold gloss
	pillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 214, 214))
	mk("UIListLayout", pill, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 7),
	})
	mk("UIPadding", pill, { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10) })
	local coin = mk("TextLabel", pill, { -- gold star coin (white disc so the star reads)
		Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.white, Font = F_DISPLAY, Text = "★",
		TextSize = 14, TextColor3 = C.goldDk, ZIndex = 15, LayoutOrder = 1,
	})
	corner(coin, 999)
	stroke(coin, C.goldDk, 1, 0)
	local tokenCount = mk("TextLabel", pill, {
		Size = UDim2.fromOffset(20, 22), BackgroundTransparency = 1, Font = F_BOLD,
		Text = tostring(tokens), TextSize = 15, TextColor3 = C.dark, -- dark count on the gold pill
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15, LayoutOrder = 2,
	})

	-- ----- header (pinned top, centered) -----
	local header = mk("Frame", content, {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 11,
	})
	mk("UIListLayout", header, {
		FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})
	-- gold "DAILY CRATE" with a small gold star
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, -80, 0, 14), AutomaticSize = Enum.AutomaticSize.None,
		Font = F_BOLD, Text = "★ DAILY CRATE", TextSize = 12, TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12, LayoutOrder = 1,
	})
	-- white bold title (~26px) with a gold star before it
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = F_DISPLAY, RichText = true, Text = '<font color="#ffd24a">★</font> Choose a Pet to Level Up',
		TextSize = 26, TextColor3 = C.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12, LayoutOrder = 2,
	})
	-- Subtitle shows the SERVER-ROLLED rarity (colored) + the matching "+N levels" amount, e.g.
	-- "EPIC roll — pick a pet to grant +4 levels." Falls back to the plain line if no roll came back.
	local subText
	if rarity then
		subText = string.format(
			'<font color="#7ed957"><b>%s</b></font> roll — pick a pet to grant <font color="#7ed957"><b>+%d level%s</b></font>.',
			string.upper(rarity), levelsAdded, (levelsAdded == 1) and "" or "s")
	else
		subText = "Spend a token to grant the next level instantly."
	end
	mk("TextLabel", header, {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = F_BODY, RichText = true, Text = subText, TextSize = 13,
		TextColor3 = C.muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12, LayoutOrder = 3,
	})

	-- ----- scrollable list: fills the middle (between the pinned header and footer) -----
	local list = mk("ScrollingFrame", content, {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, HEADER_H + GAP),
		Size = UDim2.new(1, 0, 1, -(HEADER_H + FOOTER_H + GAP * 2)),
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.violet, ScrollBarImageTransparency = 0.35,
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 11,
	})
	mk("UIListLayout", list, {
		FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	})
	mk("UIPadding", list, { PaddingRight = UDim.new(0, 6) })

	-- footer/confirm refs are declared before the rows so selection can update the button
	local confirmEnabled = false
	local confirmBtn, confirmLabel, costChip, confirmGrad

	local function setConfirm(on)
		confirmEnabled = on
		confirmBtn.BackgroundColor3 = C.white -- the UIGradient supplies the fill color
		if on then
			confirmGrad.Color = ColorSequence.new(C.limeA, C.limeB) -- #9ae84a -> #6cc62e glossy lime
			confirmBtn.AutoButtonColor = true
			confirmLabel.TextColor3 = C.white -- white bold text
			confirmLabel.Text = "Level Up +" .. tostring(levelsAdded) -- amount is the server roll, not the pet
			costChip.Visible = true
		else
			confirmGrad.Color = ColorSequence.new(Color3.fromRGB(150, 170, 210), Color3.fromRGB(96, 124, 182)) -- dim
			confirmBtn.AutoButtonColor = false
			confirmLabel.TextColor3 = C.muted
			confirmLabel.Text = (selected and tokens <= 0) and "Out of Tokens" or "Level Up"
			costChip.Visible = false
		end
	end
	local function refreshConfirm()
		setConfirm(selected ~= nil and tokens > 0)
	end

	-- ----- one pet row -----
	for i, p in ipairs(pets) do
		local maxed = p.maxed == true
		local row = mk("TextButton", list, {
			Text = "", AutoButtonColor = false, Selectable = not maxed,
			Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.row, ZIndex = 11, LayoutOrder = i,
		})
		corner(row, 16)
		local rowStroke = stroke(row, C.line, 1.5, 0) -- light-blue inner outline
		local rowGrad = mk("UIGradient", row, { Rotation = 90 }) -- inner top highlight -> darker bottom edge
		rowGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 192, 226))

		-- check mark (top-right, shown when selected) — lime to match the selected outline
		local check = mk("TextLabel", row, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = C.lime, Font = F_BOLD, Text = "✓", TextSize = 13,
			TextColor3 = Color3.fromRGB(18, 70, 20), Visible = false, ZIndex = 14,
		})
		corner(check, 999)
		stroke(check, C.white, 2, 0)

		-- avatar (rounded 48px square, gradient bg) showing the REAL in-game pet MODEL in a ViewportFrame;
		-- only falls back to the code-drawn vector icon if that pet's model can't be found/cloned.
		local avatar = mk("Frame", row, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = C.avatarA, ClipsDescendants = true, ZIndex = 12,
		})
		corner(avatar, 14)
		stroke(avatar, C.white, 1.5, 0) -- white border (darker-blue inset behind the viewport)
		local ag = mk("UIGradient", avatar, { Rotation = 90 })
		ag.Color = ColorSequence.new(C.avatarA, C.avatarB)
		if not petModelToViewport(avatar, p) then
			drawPetIcon(avatar, p.displayName) -- fallback: code-drawn vector icon
		end

		-- info column (name + xp bar + %)
		local info = mk("Frame", row, {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 76, 0.5, 0), Size = UDim2.new(1, -76 - 96, 0, 44), ZIndex = 12,
		})
		mk("UIListLayout", info, {
			FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7),
		})
		mk("TextLabel", info, {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Font = F_DISPLAY,
			Text = p.displayName or p.petId, TextSize = 16, TextColor3 = maxed and C.muted or C.text,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 12, LayoutOrder = 1,
		})
		local xpRow = mk("Frame", info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 8), ZIndex = 12, LayoutOrder = 2 })
		local track = mk("Frame", xpRow, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -40, 0, 7),
			BackgroundColor3 = C.navy, BackgroundTransparency = 0, ZIndex = 12, -- dark-navy track
		})
		corner(track, 999)
		local fill = mk("Frame", track, {
			Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = maxed and C.muted or C.xp, ZIndex = 13,
		})
		corner(fill, 999)
		if not maxed then
			local fg = mk("UIGradient", fill, { Rotation = 0 }) -- light-blue XP gradient
			fg.Color = ColorSequence.new(C.xp, C.xpLt)
		end
		mk("TextLabel", xpRow, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(34, 14),
			BackgroundTransparency = 1, Font = F_MED, Text = maxed and "MAX" or (tostring(math.floor(p.xpPct or 0)) .. "%"),
			TextSize = 11, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12,
		})
		TweenService:Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new((p.xpPct or 0) / 100, 0, 1, 0) }):Play()

		-- level column (gold "Lv N" badge + "-> N+1", or "MAX")
		local level = mk("Frame", row, {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(80, 44), ZIndex = 12,
		})
		mk("UIListLayout", level, {
			FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
		})
		local badge = mk("TextLabel", level, { -- gold gradient pill: WHITE star + DARK "Lv N"
			BackgroundColor3 = C.gold, BackgroundTransparency = maxed and 0.55 or 0,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22),
			Font = F_DISPLAY, RichText = true,
			Text = maxed and "MAX" or ('<font color="#ffffff">★</font> Lv ' .. tostring(p.level)),
			TextSize = 13, TextColor3 = maxed and C.muted or C.dark, ZIndex = 13, LayoutOrder = 1,
		})
		corner(badge, 999)
		stroke(badge, C.white, 1.5, maxed and 0.4 or 0)
		if not maxed then local bgr = mk("UIGradient", badge, { Rotation = 90 }); bgr.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(220,196,120)) end -- gold gloss
		mk("UIPadding", badge, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
		if not maxed then
			-- preview = current level + the ROLLED amount, clamped at the cap (same for every pet)
			mk("TextLabel", level, {
				BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 13),
				Font = F_MED, Text = "→ Lv " .. tostring(math.min(MAX_LV, p.level + levelsAdded)),
				TextSize = 11, TextColor3 = C.xp, ZIndex = 12, LayoutOrder = 2, -- light blue
			})
		end

		-- selection / hover behaviour
		local function setSelected(on)
			rowStroke.Color = on and C.lime or C.line -- bright lime outline when selected
			rowStroke.Thickness = on and 3 or 1.5
			row.BackgroundColor3 = on and C.rowSel or C.row
			check.Visible = on
		end
		rowApis[i] = { entry = p, setSelected = setSelected }

		if maxed then
			row.BackgroundTransparency = 0.35 -- greyed / dimmed; not selectable
		else
			local rowScale = mk("UIScale", row, { Scale = 1 }) -- hover "lift" (visual only; layout unaffected)
			row.MouseEnter:Connect(function()
				if selected ~= p then row.BackgroundColor3 = C.rowHi end
				TweenService:Create(rowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1.02 }):Play()
			end)
			row.MouseLeave:Connect(function()
				if selected ~= p then row.BackgroundColor3 = C.row end
				TweenService:Create(rowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			end)
			row.Activated:Connect(function()
				if done then return end
				playSound(SND_TAP, 0.6)
				selected = p
				for _, a in ipairs(rowApis) do a.setSelected(a.entry == p) end
				refreshConfirm()
			end)
		end
	end

	-- ----- footer (Cancel + Level Up) -----
	local footer = mk("Frame", content, {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, FOOTER_H), ZIndex = 11,
	})
	mk("Frame", footer, { -- top border line
		BackgroundColor3 = C.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 0), ZIndex = 11,
	})
	local cancelBtn = mk("TextButton", footer, { -- slate-blue, glossy
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 6), Size = UDim2.fromOffset(116, 46),
		BackgroundColor3 = C.slate, AutoButtonColor = true,
		Font = F_BOLD, Text = "Cancel", TextSize = 15, TextColor3 = C.white, ZIndex = 12,
	})
	corner(cancelBtn, 14)
	gloss(cancelBtn, C.slateDk)

	confirmBtn = mk("TextButton", footer, { -- glossy lime-green gradient (colors set in setConfirm)
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 6), Size = UDim2.new(1, -128, 0, 46),
		BackgroundColor3 = C.white, AutoButtonColor = false, Text = "", ZIndex = 12,
	})
	corner(confirmBtn, 14)
	stroke(confirmBtn, C.greenDk, 2, 0)
	confirmGrad = mk("UIGradient", confirmBtn, { Rotation = 90 })
	-- faint white sparkles scattered on the Level Up button
	for _, sp in ipairs({ {0.16, 0.32, 3}, {0.46, 0.70, 2.5}, {0.78, 0.30, 3}, {0.62, 0.4, 2} }) do
		local s = mk("Frame", confirmBtn, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sp[1], sp[2]),
			Size = UDim2.fromOffset(sp[3] * 2, sp[3] * 2), BackgroundColor3 = C.white,
			BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 12,
		})
		mk("UICorner", s, { CornerRadius = UDim.new(1, 0) })
	end
	mk("UIListLayout", confirmBtn, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10),
	})
	confirmLabel = mk("TextLabel", confirmBtn, {
		BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20),
		Font = F_BOLD, Text = "Level Up", TextSize = 15, TextColor3 = C.muted, ZIndex = 13, LayoutOrder = 1,
	})
	costChip = mk("Frame", confirmBtn, {
		BackgroundColor3 = C.dark, BackgroundTransparency = 0.78, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22), Visible = false, ZIndex = 13, LayoutOrder = 2,
	})
	corner(costChip, 999)
	mk("UIListLayout", costChip, {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	})
	mk("UIPadding", costChip, { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 9) })
	local chipCoin = mk("TextLabel", costChip, {
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.gold, Font = F_DISPLAY, Text = "★",
		TextSize = 11, TextColor3 = Color3.fromRGB(120, 78, 0), ZIndex = 14, LayoutOrder = 1,
	})
	corner(chipCoin, 999)
	mk("TextLabel", costChip, {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 16), Font = F_BOLD, Text = "1",
		TextSize = 12, TextColor3 = C.dark, ZIndex = 14, LayoutOrder = 2,
	})

	local function teardown() panel:Destroy() end

	cancelBtn.Activated:Connect(function()
		if done then return end
		done = true
		playSound(SND_TAP, 0.6)
		-- Cancel backs out: clears selection and closes the modal + reveal (the daily claim is NOT
		-- consumed — only Confirm/ClaimCrate spends it — so the crate stays available).
		selected = nil
		teardown()
		closeReveal()
	end)

	confirmBtn.Activated:Connect(function()
		if done or not confirmEnabled or not selected then return end
		done = true
		playSound(SND_TAP, 0.6)
		tokens = tokens - 1
		tokenCount.Text = tostring(tokens)
		local petId = selected.petId
		teardown()
		onPick(petId) -- claim -> result card (bumps level / resets XP in the reveal)
	end)

	refreshConfirm()
end

-- attemptOpen(): triggered by the More menu's "Daily Rewards" row (assigns the forward-declared
-- upvalue connected at the top). Otherwise fetch owned pets, pick (or auto-select), then claim. The
-- server applies the levels to the chosen pet and rolls the rarity.
attemptOpen = function()
	print("[CrateClient] Daily Rewards open requested (claimable=" .. tostring(isClaimable()) .. ")")
	playSound(SND_TAP, 0.6)
	if not isClaimable() then return end
	-- Recover from any leftover/stuck crate UI (a prior reveal interrupted by a respawn, etc.) so a
	-- tap is NEVER silently swallowed. A live reveal covers the screen + closes the menu, so this only
	-- ever fires on a genuinely stuck state, not on a real in-progress open.
	if revealing or opening then
		for _, ch in ipairs(revealGui:GetChildren()) do
			if ch ~= dim then ch:Destroy() end
		end
		revealGui.Enabled = false
		revealing = false
		opening = false
	end
	opening = true
	task.spawn(function()
		-- NO PET GATE ANY MORE. The daily hands out a free Premium skin crate, which is worth exactly the
		-- same to a player who owns no pets as to one who owns every pet -- so the old "Unlock A Pet To
		-- Receive Levels" refusal (and the pet picker behind it) would now be turning people away from a
		-- reward they can use. Both only survive as the fallback path, if the crate grant itself fails.
		--
		-- SEQUENCE: claim, then the crate shop's own reveal reel. No opening animation in front of it -- the
		-- reel IS the reveal, and anything played before it is just a delay between the tap and the reward.
		local closeReveal = freshReveal()
		playMeteor(false, function()
			claimAndReveal(nil, closeReveal)
		end)
	end)
end

print("[CrateClient] fully loaded — Daily Rewards is now live")

-- Dev /crate path: the server already decided the result. Same flow as a real open -- straight to the
-- result card, no picker (the server already chose the pet).
CrateResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	if result.ok then
		if revealing or opening then
			for _, ch in ipairs(revealGui:GetChildren()) do
				if ch ~= dim then ch:Destroy() end
			end
			revealGui.Enabled = false; revealing = false; opening = false
		end
		local closeReveal = freshReveal()
		local big = (result.kind == "levels") and (result.rarity == "Mythical")
		playMeteor(big, function() showResultCard(result, closeReveal) end)
	elseif result.reason == "no_pets" then
		showMessage("Unlock A Pet To Receive Levels")
	end
end)
