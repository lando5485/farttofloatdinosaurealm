-- ============================================================================================================
-- SKIN CRATE CLIENT -- the crate shop, the CS:GO-style reveal, and the skin inventory.
-- ============================================================================================================
-- THE CLIENT NEVER DECIDES A REWARD. It asks the server to open a crate, receives the already-granted result
-- (including the reel index it must stop on), and animates to exactly that item. Tampering with this file can
-- change what the animation looks like and nothing else -- the item is decided and saved before the reel moves.
--
-- THREE TABS in one 700x520 panel, matching the Shop panel's geometry, palette and fonts so the cosmetics menu
-- reads as part of the same game:
--   CRATES     -- one card per crate: icon, blurb, token price, OPEN. Plus the real odds, printed from the
--                 SAME shared table the server rolls on.
--   INVENTORY  -- every skin owned, with its trait and duplicate count. A skin for a pet you haven't unlocked
--                 still shows, reading "Unlock <Pet> to equip" -- never hidden.
--   TOKENS     -- the Robux token packs.
--
-- THE REEL (openReveal below) is the CS:GO case feel: a long horizontal strip of items scrolls left, fast at
-- first, easing to a crawl, and stops with the winning cell under the centre marker. A tick plays every time a
-- cell crosses the marker, so the slowdown is audible as well as visible. A Gold pull gets its own sound, a
-- gold flash, and a server-wide announcement.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local PetSkins    = require(Shared:WaitForChild("PetSkins"))
local PetTraits   = require(Shared:WaitForChild("PetTraits"))
local PetTier     = require(Shared:WaitForChild("PetTier"))
local SkinCrates  = require(Shared:WaitForChild("SkinCrates"))
local CrateTokens = require(Shared:WaitForChild("CrateTokens"))
local PetCollection = require(Shared:WaitForChild("PetCollection"))
local Gamepasses  = require(Shared:WaitForChild("Gamepasses"))

local SkinRemotes    = ReplicatedStorage:WaitForChild("SkinRemotes", 30)
local GetSkinState   = SkinRemotes:WaitForChild("GetSkinState")
local OpenCrate      = SkinRemotes:WaitForChild("OpenCrate")
local EquipSkin      = SkinRemotes:WaitForChild("EquipSkin")
local BuyTokens      = SkinRemotes:WaitForChild("BuyTokens")
local SkinStateEvent = SkinRemotes:WaitForChild("SkinStateEvent")
local GoldAnnounce   = SkinRemotes:WaitForChild("GoldAnnounce")
local AssignPetLevels = SkinRemotes:WaitForChild("AssignPetLevels")  -- c->s RF: pour pending levels into a pet
-- Set when the post-open level picker is built; called again whenever fresh state lands so the pet rows
-- follow hatches, trades and levels landing elsewhere.
local levelPickerRefresh = nil
local TradeUpRF      = SkinRemotes:WaitForChild("TradeUp")
local CollectAnnounce = SkinRemotes:WaitForChild("CollectAnnounce")

-- ===== SOUNDS =====
-- REVEAL is the game's existing crate/wheel payoff sound, reused deliberately so the three random-reward systems
-- feel like one game. TICK is the UI click, which is short enough to read as a reel tick.
-- GOLD: upload a dedicated fanfare and paste its id here. Until then it plays the reveal sound pitched DOWN and
-- layered, which is distinctly different from a normal pull without risking a broken asset id.
local TICK_SOUND   = "rbxassetid://101638558691673"
local REVEAL_SOUND = "rbxassetid://4612378364"
local GOLD_SOUND   = nil -- e.g. "rbxassetid://<your gold fanfare>"

local function playSound(id, volume, pitch)
	if not id then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.5
	if pitch then s.PlaybackSpeed = pitch end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
	return s
end

-- ===== HOUSE UI HELPERS (same shape as the Shop / HUD scripts) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end

-- House palette: bright blue / white / lime / gold. No dark panels.
local PANEL      = Color3.fromRGB( 30, 120, 220)
local PANEL_DARK = Color3.fromRGB( 20,  60, 160)
local HEADER     = Color3.fromRGB( 15,  60, 140)
local CARD       = Color3.fromRGB( 20,  90, 200)
local GOLD       = Color3.fromRGB(255, 220,   0)
local LIME       = Color3.fromRGB( 50, 220,  50)
local LIME_DARK  = Color3.fromRGB( 30, 130,  30)
local RED        = Color3.fromRGB(255,  60,  60)
local WHITE      = Color3.new(1, 1, 1)

local function playUIClick() if _G.playUIClick then pcall(_G.playUIClick) end end

-- ============================================================================================================
-- RARITY FLAIR -- what makes a rare pull actually LOOK rare
-- ============================================================================================================
-- Escalating, deliberately: Common and Uncommon get NOTHING. That's the whole point -- if every row shimmers,
-- none of them do. The plain majority is what makes a Rare border-pulse read as special and a Gold stop you.
--
--   Rare       edge pulse
--   Epic       + shimmer sweep
--   Legendary  + twinkling sparkles
--   Gold       + a breathing glow behind the card, faster/wider pulse
--
-- `lite` (the 56 reel cells) keeps only the cheap layers -- pulse + sweep. Sparkles and the glow image are
-- skipped there: at ~18 Rare+ cells flying past in 5 seconds nobody reads them, and they'd cost real frame time.
local FLAIR = {
	Common    = nil,
	Uncommon  = nil,
	Rare      = { pulse = 1.0 },
	Epic      = { pulse = 0.9, sweep = 2.6 },
	Legendary = { pulse = 0.8, sweep = 2.2, sparkles = 2 },
	-- `prize` is deliberately GOLD-ONLY. In CS:GO exactly one band -- the knife -- gets the special
	-- treatment, and that scarcity is the whole reason it reads as a prize. Give Legendary one too and
	-- neither means anything.
	Gold      = { pulse = 0.55, sweep = 1.6, sparkles = 3, glow = true, prize = true },
}

-- Looping tweens per frame, so a REUSED frame (the result card) can be reset between reveals instead of
-- stacking a second pulse on the same stroke. Weak keys: rows/cells that get destroyed drop out on their own.
local flairTweens = setmetatable({}, { __mode = "k" })

local function clearRarityFlair(frame)
	for _, t in ipairs(flairTweens[frame] or {}) do pcall(function() t:Cancel() end) end
	flairTweens[frame] = nil
	for _, d in ipairs(frame:GetChildren()) do
		if d.Name == "RarityShine" or d.Name == "RaritySparkle" or d.Name == "RarityGlow"
			or d.Name == "RarityPrize" then d:Destroy() end
	end
end

local function applyRarityFlair(frame, tier, lite)
	local f = FLAIR[tier]
	if not f then return end -- Common / Uncommon stay flat on purpose
	local col = PetSkins.tierColor(tier)
	local mine = {}; flairTweens[frame] = mine

	-- (1) EDGE PULSE -- breathe the existing rarity stroke instead of adding a second one, so the border
	-- thickens and brightens in place rather than doubling up.
	if f.pulse then
		local st = frame:FindFirstChildOfClass("UIStroke")
		if not st then st = Instance.new("UIStroke"); st.Color = col; st.Parent = frame end
		local base = st.Thickness
		st.Transparency = 0
		local t = TweenService:Create(st, TweenInfo.new(f.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = base + (tier == SkinCrates.GOLD_TIER and 2.5 or 1.5), Transparency = 0.25 })
		t:Play(); mine[#mine + 1] = t
	end

	-- (2) SHIMMER SWEEP -- a soft diagonal highlight crossing the card.
	--
	-- THE BAND ITSELF IS NO LONGER ROTATED, AND THAT IS THE WHOLE FIX. It used to be a Frame with
	-- Rotation = 14, and a ROTATED GuiObject IGNORES ClipsDescendants -- its own and every ancestor's. So
	-- this 1.8x-tall band spilled out of the reel cell, out of the reel window, out of the crate panel and
	-- swept across the entire screen during an opening, with a dozen Epic+ cells doing it at once. The
	-- clipping was set correctly the whole time; the rotation was quietly cancelling it.
	--
	-- The tilt now lives on the UIGradient instead. Gradient rotation is a paint-time property -- it tilts
	-- the highlight without rotating the frame, so clipping applies again. Same white, same 0.72
	-- transparency, same soft-edged band, same 0.85s Sine sweep and the same `f.sweep` gap between passes:
	-- the only thing that changed is that it can no longer leave the frame it belongs to.
	if f.sweep then
		frame.ClipsDescendants = true
		local shine = Instance.new("Frame")
		shine.Name = "RarityShine"; shine.BackgroundColor3 = Color3.new(1, 1, 1); shine.BackgroundTransparency = 0.72
		shine.BorderSizePixel = 0
		-- 0.22 wide, 1.8 tall starting at -0.4: the overhang top and bottom guarantees the band covers the
		-- full height at every point of its travel, and the frame's own clipping trims it to the card.
		shine.Size = UDim2.new(0.22, 0, 1.8, 0); shine.Position = UDim2.new(-0.35, 0, -0.4, 0)
		shine.ZIndex = (frame.ZIndex or 1) + 6; shine.Parent = frame
		local g = Instance.new("UIGradient", shine)
		g.Rotation = 14 -- the diagonal, moved off the Frame and onto the paint
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1),
		})
		task.spawn(function()
			while shine.Parent do
				shine.Position = UDim2.new(-0.35, 0, -0.4, 0)
				TweenService:Create(shine, TweenInfo.new(0.85, Enum.EasingStyle.Sine), { Position = UDim2.new(1.15, 0, -0.4, 0) }):Play()
				task.wait(f.sweep)
			end
		end)
	end

	if lite then return end -- reel cells stop here

	-- (2b) PRIZE ROSETTE -- the top tier gets a struck-medal badge on the item, the way CS:GO stars its
	-- Placed AFTER the `lite` gate on purpose. In the REEL a Gold item is masked -- the whole cell is
	-- one big rosette and nothing else (see buildCell) -- so a corner badge there would just be a
	-- rosette stamped on a rosette. This badge is for the places that DO show the item: the reveal
	-- card, the inventory rows and a completed collection.
	--
	-- Sits at (16, 3): clear of the inventory row's rarity stripe (x 6-14) and of the EQUIP button on the
	-- right, so it never lands on top of something clickable in any of the four places flair is applied.
	if f.prize then
		local medal = Instance.new("Frame")
		medal.Name = "RarityPrize"
		medal.Size = UDim2.fromOffset(24, 24)
		-- Centre-anchored so the breathing tween below grows it evenly in every direction; anchored at the
		-- corner it would swell down-and-right and drift off the item it is marking.
		medal.AnchorPoint = Vector2.new(0.5, 0.5)
		medal.Position = UDim2.new(0, 28, 0, 15)
		medal.BackgroundColor3 = col
		medal.ZIndex = (frame.ZIndex or 1) + 8 -- above the pet thumbnail (ZIndex +3) and the shimmer sweep
		medal.Parent = frame
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = medal -- a disc
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(92, 58, 8); rs.Thickness = 2; rs.Parent = medal
		-- struck-metal look: bright at the top, darker at the bottom
		local rg = Instance.new("UIGradient"); rg.Rotation = 90; rg.Parent = medal
		rg.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), col)
		local star = mkLabel(medal, {
			Text = "\xE2\x98\x85", Font = Enum.Font.FredokaOne, TextScaled = true,
			TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -4, 1, -4),
			Position = UDim2.new(0, 2, 0, 2),
		})
		star.ZIndex = medal.ZIndex + 1
		-- A slow breath, not a spin. It has to catch the eye at reel speed without becoming a second moving
		-- thing competing with the reel itself.
		local pt = TweenService:Create(medal,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.fromOffset(29, 29) })
		pt:Play(); mine[#mine + 1] = pt
	end

	-- (3) SPARKLES -- twinkle in place, no movement. Fixed spots so they read as part of the card.
	if f.sparkles then
		local spots = { {0.06, 0.22}, {0.94, 0.30}, {0.10, 0.78} }
		for i = 1, math.min(f.sparkles, #spots) do
			local tw = Instance.new("TextLabel")
			tw.Name = "RaritySparkle"; tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold
			tw.Text = "\xE2\x9C\xA6"; tw.TextColor3 = col
			tw.TextSize = 10 + i * 3; tw.Size = UDim2.fromOffset(18, 18)
			tw.AnchorPoint = Vector2.new(0.5, 0.5); tw.Position = UDim2.fromScale(spots[i][1], spots[i][2])
			tw.ZIndex = (frame.ZIndex or 1) + 7; tw.Parent = frame
			local t = TweenService:Create(tw, TweenInfo.new(0.6 + i * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ TextTransparency = 0.85 })
			t:Play(); mine[#mine + 1] = t
		end
	end

	-- (4) GOLD GLOW -- a breathing halo BEHIND the card (ZIndex 0), so the top tier is visible from across the
	-- panel before you've read a single word.
	if f.glow then
		local glow = Instance.new("ImageLabel")
		glow.Name = "RarityGlow"; glow.BackgroundTransparency = 1
		glow.Image = "rbxassetid://1316045217"; glow.ImageColor3 = col; glow.ImageTransparency = 0.55
		glow.ScaleType = Enum.ScaleType.Slice; glow.SliceCenter = Rect.new(10, 10, 118, 118)
		glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 26, 1, 26); glow.ZIndex = 0; glow.Parent = frame
		local t = TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ ImageTransparency = 0.2, Size = UDim2.new(1, 40, 1, 40) })
		t:Play(); mine[#mine + 1] = t
	end
end

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared; reuse the game's if present) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end

-- ============================================================================================================
-- PET THUMBNAILS (static, CS:GO-style)
-- ============================================================================================================
-- A crate item is a PET plus a SKIN, so the picture has to be that pet wearing that skin -- a Honey Maple Fox
-- cell shows a Maple Fox painted Honey. A flat colour swatch could never do that.
--
-- STATIC on purpose. These sit still like a CS:GO case cell; there is no rotate loop, which also means no
-- per-frame cost for the ~56 cells a reel builds.
--
-- Two things keep this affordable:
--   * ONE base model is built per pet and cached, then CLONED per cell. Building is the expensive half.
--   * Builds are queued one-per-frame behind a paw placeholder, so a 56-cell reel never blocks a frame. The
--     reel spins for SPIN_TIME seconds, which is far longer than the queue needs to drain.
local previewBase = {}     -- [petId] = one unparented model, built once and cloned from
local previewQueue = {}
local previewWorking = false

-- The Trait Crate reel's stand-in: every cell shows the trait worn by this pet in the Classic skin, because
-- the real ride-along is rolled at open time. One species for every cell on purpose -- the MODEL reads as
-- "demo mannequin" and the TRAIT reads as the thing that changes cell to cell.
local TRAIT_DEMO_PET = "ButterDuck"

local function basePetModel(petId)
	local cached = previewBase[petId]
	if cached then return cached end
	-- PetFollow owns model construction (server union templates, with client fallbacks). Guarded because this
	-- script must still work if PetFollow failed to load -- the cells just keep their placeholder.
	if not _G.petBuildModel then return nil end
	local ok, built = pcall(_G.petBuildModel, petId)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then return nil end
	built.Parent = nil
	previewBase[petId] = built
	return built
end

local function startPreviewWorker()
	if previewWorking then return end
	previewWorking = true
	task.spawn(function()
		while #previewQueue > 0 do
			local req = table.remove(previewQueue, 1)
			-- The cell may have been destroyed while queued (reel rebuilt, tab switched). Skip it.
			if req.vp and req.vp.Parent then
				local base = basePetModel(req.petId)
				if base then
					local ok, err = pcall(function()
						-- CLEAR EVERYTHING BUT THE CAMERA. A viewport populated twice keeps both models stacked at the
						-- origin and renders as one pet with two sets of eyes. Filtering on Model/BasePart was not enough:
						-- the pet template is built server-side, so its top-level shape is not this file's to assume -- a
						-- Folder or an Accessory wrapping the geometry would have slipped straight through.
						-- The placeholder goes too; req.ph is re-checked for a live Parent before it is touched below.
						for _, old in ipairs(req.vp:GetChildren()) do
							if not old:IsA("Camera") then old:Destroy() end
						end
						local clone = base:Clone()
						if _G.applyPetSkinPreview then
							_G.applyPetSkinPreview(clone, req.skin, req.trait, req.static)
						end
						clone.Parent = req.vp
						-- Fixed three-quarter view, framed from the model's own bounds so every pet fills the
						-- cell about equally regardless of how big it was built.
						local cf, size = clone:GetBoundingBox()
						local reach = math.max(size.X, size.Y, size.Z)
						local dist = reach * 1.85 + 1
						local centre = cf.Position
						req.cam.CFrame = CFrame.lookAt(
							centre + Vector3.new(dist * 0.60, dist * 0.40, dist * 0.72), centre)
						if req.ph then
							if req.ph.Parent then req.ph:Destroy() end -- already gone if the clear above took it
							req.ph = nil
						end
					end)
					if not ok then warn("[SkinCrate] thumbnail failed for " .. tostring(req.petId) .. ": " .. tostring(err)) end
				end
			end
			task.wait() -- one per frame: no single heavy synchronous burst
		end
		previewWorking = false
		if #previewQueue > 0 then startPreviewWorker() end -- close the enqueue-as-we-exit race
	end)
end

-- Returns the ViewportFrame immediately; the model lands a frame or two later.
-- `static` false gives the full look (particles, light, trait) -- used only for the one reveal card.
local function makePetPreview(parent, petId, skinId, traitId, size, pos, static)
	local vp = Instance.new("ViewportFrame")
	vp.Size = size; vp.Position = pos
	vp.BackgroundTransparency = 1
	-- Explicit ZIndex: the reel cell draws this OVER its skin-coloured backdrop. Same-ZIndex siblings fall
	-- back to creation order, which works but silently breaks the moment anyone reorders the cell build.
	vp.ZIndex = 3
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5)
	vp.Parent = parent
	-- ONE camera per viewport, created here and reused for its whole life -- the worker only ever writes
	-- its CFrame, never re-creates it. FindFirstChildOfClass first so a re-entrant build reuses the
	-- existing camera instead of leaving an orphan that CurrentCamera no longer points at.
	local cam = vp:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.FieldOfView = 50
		cam.Parent = vp
	end
	vp.CurrentCamera = cam
	local ph = mkLabel(vp, {
		Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = Color3.fromRGB(150, 180, 235), Size = UDim2.new(1, 0, 1, 0),
	})
	previewQueue[#previewQueue + 1] = {
		vp = vp, cam = cam, ph = ph, petId = petId, skin = skinId, trait = traitId,
		static = (static ~= false),
	}
	startPreviewWorker()
	return vp
end


-- ============================================================================================================
-- STATE (a local mirror of the server's push; never used to decide what the player owns)
-- ============================================================================================================
local state = { tokens = 0, skins = {}, equipped = {}, unlocked = {}, collection = {} }
local refreshTabs -- forward
-- FORWARD DECL. The tab-click handler (which hands PETS/TRADE/QUESTS back to the Pet Hub) has to close
-- this panel, but setOpen is defined ~1000 lines below with the rest of the open/close plumbing. Without
-- this line that handler compiles `setOpen` as a GLOBAL, finds nil at click time, and errors -- which is
-- exactly why those three tabs did nothing. Declared here, assigned there.
local setOpen -- forward

local function applyState(s)
	if type(s) ~= "table" then return end
	state.tokens   = tonumber(s.tokens) or 0
	state.skins    = s.skins    or {}
	state.equipped = s.equipped or {}
	state.unlocked = s.unlocked or {}
	state.collection = s.collection or {}
	-- The pet roster the post-open level picker draws, plus how many levels are waiting to be placed.
	-- pendingLevels of 0 is the normal resting state: it only goes above zero between opening a Pet Level
	-- Crate and choosing where those levels land.
	state.levelPets     = s.levelPets or {}
	state.pendingLevels = tonumber(s.pendingLevels) or 0
	-- Repaint the picker if the crate list has already built one. This is what makes the button follow a
	-- hatch, a trade, a pet maxing out, or the server refusing a stale target -- every one of those ends in a
	-- pushState, and every pushState lands here.
	if levelPickerRefresh then pcall(levelPickerRefresh) end
	-- Publish the balance so the Pet Hub header can show the same number this panel does. Pushed on the
	-- SERVER's state, not on a local guess, so the two headers cannot drift apart.
	_G.crateTokenBalance = state.tokens
	if _G.petHubTokensChanged then pcall(_G.petHubTokensChanged, state.tokens) end
	if refreshTabs then refreshTabs() end
end

-- ============================================================================================================
-- THE PANEL
-- ============================================================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SkinCrateGui"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.DisplayOrder = 100 -- above the HUD, same as the Shop
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- KEEP CoreClient'S TEXT SWEEP OFF THIS PANEL.
-- applyScaling/repositionGUIs blanket-force TextScaled = true on every TextLabel/TextButton in every ScreenGui.
-- TextScaled IGNORES TextSize and inflates each label to fill its frame, so this panel's authored sizes (tab
-- labels, crate blurbs, odds lines) get overwritten -- the same "text goes huge and overlaps" bug the Pet Hub
-- hit. NoTextSweep is that sweep's documented opt-out and PetFollow already sets it on the Pet Hub (invGui).
--
-- IT WAS SET ON ONLY ONE OF THE TWO PANELS, which is why text looked different depending on the tab: PETS kept
-- its authored sizes, CRATES got swept. Worse, THIS panel calls _G.applyHudScaling() when it opens, so pressing
-- CRATES was itself the thing that triggered the sweep. Both panels opt out, or neither does.
gui:SetAttribute("NoTextSweep", true)
gui.Parent = PlayerGui

-- Full-screen catcher. Active=false so a click OUTSIDE falls through to the HUD menu buttons (click-to-switch).
-- It is NOT a close button: this menu closes on the X only -- a stray screen tap must never shut a panel.
mkFrame(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Active = false })

local panel = mkFrame(gui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, Active = true, ClipsDescendants = true,
})
mkCorner(panel, 20); mkStroke(panel, PANEL_DARK, 3)

local header = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = HEADER })
mkCorner(header, 20)
local titleLbl = mkLabel(header, {
	Text = "\xF0\x9F\x8E\x81 PET SKIN CRATES", Font = Enum.Font.FredokaOne, TextSize = 26, TextScaled = true,
	TextColor3 = GOLD, Size = UDim2.new(0, 330, 0, 34), Position = UDim2.new(0, 14, 0, 6),
	TextXAlignment = Enum.TextXAlignment.Left,
})
mkStroke(titleLbl, Color3.new(0, 0, 0), 2)
mkLabel(header, {
	Text = "Every pull is a Skin + a Trait. Together they set the pet's Tier.", Font = Enum.Font.Gotham, TextSize = 13,
	TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255), Size = UDim2.new(0, 330, 0, 15),
	Position = UDim2.new(0, 14, 0, 40), TextXAlignment = Enum.TextXAlignment.Left,
})

-- token balance pill, top-right of the header
local tokenPill = mkFrame(header, {
	Size = UDim2.new(0, 158, 0, 34), Position = UDim2.new(1, -212, 0, 13), BackgroundColor3 = GOLD,
})
mkCorner(tokenPill, 17); mkStroke(tokenPill, Color3.fromRGB(180, 122, 20), 2)
local tokenLbl = mkLabel(tokenPill, {
	Text = CrateTokens.ICON .. " 0", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true,
	TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local closeBtn = mkButton(header, {
	Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -48, 0, 10), BackgroundColor3 = RED,
	Text = "X", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true, TextColor3 = WHITE,
})
mkCorner(closeBtn, 8); mkStroke(closeBtn, Color3.fromRGB(150, 40, 32), 2)

-- BACK -> the Pet Hub. Only shown when this panel was opened FROM the Pet Hub (its CRATES chip closes the hub
-- so the two 700x520 panels don't stack, which otherwise leaves no way back except reopening Pets from MORE+).
-- Opened any other way -- the MORE+ row, /crates -- there is nothing to go "back" to, so it stays hidden.
local backBtn = mkButton(header, {
	Size = UDim2.new(0, 70, 0, 30), Position = UDim2.new(1, -290, 0, 15), BackgroundColor3 = CARD,
	Text = "\xE2\x9D\xAE BACK", Font = Enum.Font.FredokaOne, TextSize = 14, TextScaled = true,
	TextColor3 = WHITE, Visible = false,
})
mkCorner(backBtn, 8); mkStroke(backBtn, WHITE, 1.5)
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 14; c.Parent = backBtn end

-- ===== TABS =====
-- Five tabs across a 680px bar. Widths are authored (not scale-based) because the bar sits inside the panel's
-- fixed 700px layout, and 8px of padding between five buttons leaves exactly 129 each: 5*129 + 4*8 = 677.
-- THE SAME FIVE PAGES THE PET HUB SHOWS, in the same order and the same geometry. Two of them (CRATES,
-- TOKENS) are built here; the other three live in the Pet Hub and this bar hands off to it. Matching the
-- bar pixel-for-pixel is the whole point -- tabbing between the panels should feel like one interface
-- changing pages, not two menus swapping places.
--
-- INVENTORY / TRADE UP / COLLECTION are no longer top-level tabs. They are sub-pages now, reached from the
-- page they belong to (View Collection on a crate, Trade Up from the crate list, skins from a pet), which
-- is what gives each top-level page one job instead of five competing ones.
-- ===== TWO TABS, NOT FIVE =====
-- This bar used to mirror the Pet Hub's five pages (PETS/CRATES/TOKENS/TRADE/QUESTS) and hand
-- three of them off to the hub, so the two panels read as one interface. That was reversed on
-- purpose: five tabs of which several have their OWN sub-page rows underneath read as
-- overwhelming, and pressing Pets vs Crates from the menu landed players in "the same GUI,
-- different tab", which felt broken. Crates is its own menu again -- it hosts exactly the two
-- pages it owns, and the Pet Hub keeps its three. The `hub` field / TAB_TO_HUB machinery below
-- still works if a cross-tab is ever wanted back: add the entry, done.
-- ===== ONE HUB, FOUR PAGES =====
-- Pets and crates are ONE interface again, entered through the PETS rail button: this bar mirrors the
-- Pet Hub's bar exactly (same four tabs, same geometry) and the two panels hand off to each other, so
-- tabbing feels like one menu changing pages. The de-overwhelm vs the old five-tab bar is TOKENS: it is
-- no longer a top-level destination -- it is a page INSIDE Crates (the GET TOKENS button and the token
-- chip lead there), because it is a shop for the crates page, not a collection of its own.
local TABS = {
	{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS",   hub = "pets"   },
	{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" },
	{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE",  hub = "trade"  },
	{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS", hub = "quests" },
}
-- id -> the Pet Hub page to jump to, for the tabs this panel does not host
local TAB_TO_HUB = {}
for _, t in ipairs(TABS) do if t.hub then TAB_TO_HUB[t.id] = t.hub end end
-- Fill the same 677px the five 129px tabs used to occupy: n tabs + 8px gaps between them.
local TAB_W = math.floor((677 - 8 * (#TABS - 1)) / #TABS)
local activeTab = "crates"
local tabBar = mkFrame(panel, { Size = UDim2.new(1, -20, 0, 38), Position = UDim2.new(0, 10, 0, 66), BackgroundTransparency = 1 })
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 8); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = tabBar
end
local tabButtons = {}
for i, t in ipairs(TABS) do
	local b = mkButton(tabBar, {
		Size = UDim2.new(0, TAB_W, 1, 0), LayoutOrder = i, BackgroundColor3 = CARD, Text = t.label,
		-- GOLD, not WHITE: pure white on the blue card is the brightest thing on the panel and was pulling
		-- the eye away from the content. This is the same tone as the 'PET SKIN CRATES' title.
		Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true, TextColor3 = GOLD,
	})
	mkCorner(b, 10); mkStroke(b, WHITE, 1.5)
	-- HANDS OFF -- SAME REASON AS THE PET HUB'S COPY OF THIS BAR (PetFollow's HubNav).
	-- The refresh below paints selected as dark-on-gold with a 2.5px gold-brown outline and unselected as
	-- gold-on-blue with a 1.5px white one: the colour IS which tab you're on. ButtonTextStyle's legibility
	-- sweep repaints every button cream with a 2px dark stroke and darkens the fill from whichever state it
	-- first saw, which erases that distinction.
	--
	-- THIS BAR AND THE PET HUB'S ARE TWO SEPARATE BUILDS OF THE SAME FOUR TABS, in two different scripts, and
	-- pressing PETS/CRATES swaps which panel you are looking at. Protecting only one of them is what made the
	-- tabs appear to change font and outline as you clicked between them -- so both carry the flag or neither.
	b:SetAttribute("BTS_Skip", true)
	-- CoreClient force-sets TextScaled on every label in PlayerGui, so a plain TextSize won't hold -- the
	-- ceiling has to come from a constraint or "COLLECTION" would scale up and crowd its neighbours.
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = b end
	tabButtons[t.id] = b
end

-- one scrolling body shared by the tabs; each tab rebuilds its contents into it
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 10, 0, 110); body.Size = UDim2.new(1, -20, 1, -122)
body.BackgroundTransparency = 1; body.BorderSizePixel = 0
body.ScrollBarThickness = 6; body.ScrollBarImageColor3 = GOLD
body.CanvasSize = UDim2.new(0, 0, 0, 0); body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollingDirection = Enum.ScrollingDirection.Y; body.Parent = panel
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Vertical
	ll.Padding = UDim.new(0, 10); ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center; ll.Parent = body
	local pd = Instance.new("UIPadding"); pd.PaddingBottom = UDim.new(0, 10); pd.Parent = body
end

local function clearBody()
	for _, ch in ipairs(body:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
end

-- ============================================================================================================
-- TAB: CRATES
-- ============================================================================================================
local openRequestInFlight = false
local doOpenCrate -- forward (defined with the reveal, below)

local function buildCratesTab()
	-- SUB-PAGE ROW. Inventory, Trade Up and Collection stopped being top-level tabs when the bar became the
	-- hub's five pages -- but they are still whole features, so they get their entry point here, on the page
	-- they belong to. Losing a working system to a layout change would be a bad trade.
	do
		local row = mkFrame(body, { Size = UDim2.new(1, -8, 0, 34), BackgroundTransparency = 1, LayoutOrder = 0 })
		local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal
		rl.Padding = UDim.new(0, 8); rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center; rl.Parent = row
		for j, sub in ipairs({
			{ id = "inventory",  label = "\xF0\x9F\x91\x95 MY SKINS" },
			{ id = "tradeup",    label = "\xE2\x86\x91 TRADE UP"    },
			{ id = "collection", label = "\xF0\x9F\x93\x96 COLLECTION" },
			-- TOKENS lives here now, not on the top bar: it is the crates page's shop, not a
			-- collection of its own -- one fewer top-level tab is the whole de-overwhelm.
			{ id = "tokens",     label = "\xF0\x9F\x8E\x9F TOKENS" },
		}) do
			local b = mkButton(row, {
				Size = UDim2.new(0, 128, 1, 0), LayoutOrder = j, BackgroundColor3 = CARD, Text = sub.label,
				Font = Enum.Font.FredokaOne, TextSize = 14, TextScaled = true, TextColor3 = GOLD,
			})
			mkCorner(b, 8); mkStroke(b, WHITE, 1.5)
			do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 14; c.Parent = b end
			b.MouseButton1Click:Connect(function() playUIClick(); activeTab = sub.id; refreshTabs() end)
		end
	end
	for i, crate in ipairs(SkinCrates.CRATES) do
		-- The Pet Level Crate card is now the same height as every other crate card. It used to be 44px
		-- taller to carry a "LEVELS GO TO:" picker, which asked you to choose a pet BEFORE opening -- i.e.
		-- before you knew whether you had won +1 or +7, which is the fact that decides which pet you want to
		-- feed. That picker is gone; you choose after the reveal instead. See levelPickerRefresh below.
		local card = mkFrame(body, { Size = UDim2.new(1, -8, 0, 132), BackgroundColor3 = CARD, LayoutOrder = i })
		mkCorner(card, 14); mkStroke(card, crate.color or WHITE, 2.5)

		mkLabel(card, {
			Text = crate.icon or "\xF0\x9F\x93\xA6", Font = Enum.Font.FredokaOne, TextSize = 46, TextScaled = true,
			Size = UDim2.new(0, 70, 0, 70), Position = UDim2.new(0, 12, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local nameLbl = mkLabel(card, {
			Text = crate.displayName, Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true,
			TextColor3 = GOLD, Size = UDim2.new(1, -260, 0, 26), Position = UDim2.new(0, 92, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)
		-- LIMITED crates (events / Season Pass / Robux bundles) are called out so nobody assumes the pool is
		-- permanent. They're still openable with tokens here -- the tag is about the COLLECTION rotating, not
		-- about the button being disabled.
		if crate.limited then
			local tag = mkFrame(card, {
				Size = UDim2.new(0, 74, 0, 18), Position = UDim2.new(1, -244, 0, 16),
				BackgroundColor3 = Color3.fromRGB(240, 96, 180),
			})
			mkCorner(tag, 9)
			mkLabel(tag, {
				Text = "LIMITED", Font = Enum.Font.GothamBold, TextSize = 11, TextScaled = true, TextColor3 = WHITE,
				Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 3, 0, 0),
			})
		end
		mkLabel(card, {
			Text = crate.blurb or "", Font = Enum.Font.Gotham, TextSize = 13, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -260, 0, 32),
			Position = UDim2.new(0, 92, 0, 40), TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
		})

		-- contents summary: how many items in each rarity band
		local counts = {}
		for _, e in ipairs(SkinCrates.flatContents(crate.id)) do counts[e.rarity] = (counts[e.rarity] or 0) + 1 end
		-- At half size all six pills fit ONE row again (6*58 + 5*4 = 368) inside the 418px this row has before
		-- the OPEN button's column starts -- so nothing wraps and nothing runs underneath the button, which is
		-- what used to hide the Legendary and Gold chances.
		local bandRow = mkFrame(card, { Size = UDim2.new(1, -266, 0, 16), Position = UDim2.new(0, 92, 0, 84), BackgroundTransparency = 1 })
		do
			local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
			ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = bandRow
		end
		-- THE PILLS SHOW *YOUR* ODDS, not the base table. luckFor() folds in rebirth luck (from the replicated
		-- Rebirths leaderstat) and the Lucky Pass, so a player who has paid for better odds is shown the better
		-- odds -- and a player who has not sees exactly the numbers this panel always showed, because luckFor
		-- returns 1.0 for them and 1.0 leaves the weights bit-for-bit untouched.
		--
		-- The server re-derives luck itself at roll time, so this is display only and cannot influence a roll.
		local odds = SkinCrates.effectiveOdds(crate.id, Gamepasses.luckFor(player))
		for oi, rarity in ipairs(SkinCrates.RARITY_ORDER) do
			if (counts[rarity] or 0) > 0 then
				local pill = mkFrame(bandRow, {
					Size = UDim2.new(0, 58, 1, 0), LayoutOrder = oi,
					BackgroundColor3 = PetSkins.tierColor(rarity),
				})
				mkCorner(pill, 8)
				mkLabel(pill, {
					-- one decimal, not two: at half width "79.92%" was eating the tier name off the front of the pill
				Text = string.format("%s %.1f%%", rarity, odds[rarity] or 0), Font = Enum.Font.GothamBold,
					TextSize = 11, TextScaled = true, TextColor3 = Color3.fromRGB(30, 30, 40),
					Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 3, 0, 0),
					TextXAlignment = Enum.TextXAlignment.Center,
				})
			end
		end

		-- price + OPEN
		local canAfford = state.tokens >= crate.price
		local priceLbl = mkLabel(card, {
			Text = CrateTokens.ICON .. " " .. CrateTokens.format(crate.price), Font = Enum.Font.FredokaOne,
			TextSize = 18, TextScaled = true, TextColor3 = canAfford and GOLD or Color3.fromRGB(255, 150, 150),
			Size = UDim2.new(0, 150, 0, 24), Position = UDim2.new(1, -162, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		mkStroke(priceLbl, Color3.new(0, 0, 0), 2)

		local openBtn = mkButton(card, {
			Size = UDim2.new(0, 150, 0, 44), Position = UDim2.new(1, -162, 0, 72),
			BackgroundColor3 = canAfford and LIME or Color3.fromRGB(120, 130, 145),
			Text = canAfford and "OPEN" or "NEED TOKENS", Font = Enum.Font.FredokaOne,
			TextSize = canAfford and 20 or 14, TextScaled = true, TextColor3 = WHITE,
			AutoButtonColor = canAfford,
		})
		mkCorner(openBtn, 12); mkStroke(openBtn, canAfford and LIME_DARK or Color3.fromRGB(80, 88, 100), 2)
		openBtn.MouseButton1Click:Connect(function()
			playUIClick()
			if not canAfford then
				-- Not enough tokens: send them to the tab that fixes it rather than a dead-end error.
				activeTab = "tokens"; refreshTabs()
				return
			end
			doOpenCrate(crate)
		end)
	end

	-- Honest-odds footer. Same promise as before, but as a heading + one plain sentence instead of two disclosure
	-- lines run together and stretched by TextScaled.
	--
	-- Every label here needs TextScaled + a UITextSizeConstraint rather than a plain TextSize: CoreClient's
	-- repositionGUIs sweep force-sets TextScaled = true on every TextLabel under PlayerGui, so an authored
	-- TextSize gets blown up to fill its frame. The constraint is the only thing that actually holds a size.
	local note = mkFrame(body, { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = HEADER, LayoutOrder = 999 })
	mkCorner(note, 12); mkStroke(note, GOLD, 1.5)
	local noteTitle = mkLabel(note, {
		Text = "\xE2\xAD\x90 THESE ARE THE REAL DROP CHANCES",
		Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true, TextColor3 = GOLD,
		Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 9),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = noteTitle end
	local noteBody = mkLabel(note, {
		Text = "Rarity rolls first, then a random item from it, then the trait.",
		Font = Enum.Font.Gotham, TextSize = 12, TextScaled = true, TextColor3 = Color3.fromRGB(196, 214, 250),
		Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 33),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = noteBody end
end

-- ============================================================================================================
-- TAB: INVENTORY
-- ============================================================================================================
local function buildInventoryTab()
	-- flatten the owned map into a sortable list
	local items = {}
	for key, count in pairs(state.skins) do
		local petId, skinId, traitId = PetSkins.parseKey(key)
		if petId then
			-- `tier` is the ONE Overall Tier (hidden skin+trait values through PetTier) -- the label the pet
			-- itself would wear. The per-part rarities ride along for the detail line.
			local overall = PetTier.overall(skinId, traitId) or PetSkins.tierOf(skinId)
			items[#items + 1] = {
				key = key, pet = petId, skin = skinId, trait = traitId,
				count = tonumber(count) or 1, tier = overall,
				skinTier = PetSkins.tierOf(skinId), traitTier = PetTraits.tierOf(traitId),
			}
		end
	end
	-- best first, then by pet, then by skin -- the order a collector wants to see
	table.sort(items, function(a, b)
		local ra, rb = PetSkins.TierRank[a.tier] or 0, PetSkins.TierRank[b.tier] or 0
		if ra ~= rb then return ra > rb end
		if a.pet ~= b.pet then return a.pet < b.pet end
		if a.skin ~= b.skin then return a.skin < b.skin end
		return (a.trait or "") < (b.trait or "")
	end)

	if #items == 0 then
		local empty = mkFrame(body, { Size = UDim2.new(1, -8, 0, 120), BackgroundColor3 = CARD, LayoutOrder = 1 })
		mkCorner(empty, 14); mkStroke(empty, WHITE, 2)
		mkLabel(empty, {
			Text = "No skins yet!\nOpen a crate to start your collection.", Font = Enum.Font.FredokaOne,
			TextSize = 20, TextScaled = true, TextColor3 = WHITE, Size = UDim2.new(1, -20, 1, -20),
			Position = UDim2.new(0, 10, 0, 10), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
		return
	end

	for i, it in ipairs(items) do
		local tierCol = PetSkins.tierColor(it.tier)
		local unlockedPet = state.unlocked[it.pet] == true
		local eq = state.equipped[it.pet]
		local isEquipped = eq and eq.skin == it.skin and (eq.trait or nil) == (it.trait or nil)

		local row = mkFrame(body, { Size = UDim2.new(1, -8, 0, 72), BackgroundColor3 = CARD, LayoutOrder = i })
		mkCorner(row, 12)
		mkStroke(row, isEquipped and LIME or tierCol, isEquipped and 3 or 2)
		applyRarityFlair(row, it.tier) -- Rare+ pulses, Epic+ shimmers, Legendary+ sparkles, Gold glows

		-- rarity stripe down the left edge: the colour tells you the tier before you read anything
		local stripe = mkFrame(row, { Size = UDim2.new(0, 8, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = tierCol })
		mkCorner(stripe, 4)
		-- The same thumbnail the reel uses, so an item looks identical everywhere you meet it.
		makePetPreview(row, it.pet, it.skin, it.trait, UDim2.new(0, 58, 0, 58), UDim2.new(0, 20, 0, 7), true)

		local nameLbl = mkLabel(row, {
			-- Pet-crate rows carry no skin. displayName would not crash there (it falls back to "?") but it
			-- would list sixty rows reading "? Bean Buddy", so a skinless entry is labelled by species alone.
			Text = it.skin and PetSkins.displayName(it.skin, PetSkins.prettyPet(it.pet)) or PetSkins.prettyPet(it.pet),
			Font = Enum.Font.FredokaOne, TextSize = 19,
			TextScaled = true, TextColor3 = WHITE, Size = UDim2.new(1, -360, 0, 24),
			Position = UDim2.new(0, 84, 0, 8), TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)

		-- ONE overall tier up front, then the breakdown the detail view owes the player: skin rarity, trait +
		-- trait rarity, duplicate count. The row's stripe/border/flair all carry the overall tier's colour.
		local metaBits = { "Tier: " .. it.tier }
		if it.skinTier ~= it.tier then metaBits[#metaBits + 1] = "Skin: " .. it.skinTier end
		if not PetTraits.isNone(it.trait) then
			metaBits[#metaBits + 1] = "Trait: " .. PetTraits.displayName(it.trait)
				.. (it.traitTier and (" (" .. it.traitTier .. ")") or "")
		end
		if it.count > 1 then metaBits[#metaBits + 1] = "x" .. it.count end
		mkLabel(row, {
			Text = table.concat(metaBits, "   \xE2\x80\xA2   "), Font = Enum.Font.GothamBold, TextSize = 13,
			TextScaled = true, TextColor3 = PetTraits.isNone(it.trait) and Color3.fromRGB(205, 224, 255) or PetTraits.color(it.trait),
			Size = UDim2.new(1, -360, 0, 18), Position = UDim2.new(0, 84, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		if not unlockedPet then
			-- LOCKED PET: the skin is owned and safe, it just can't be worn yet. Say exactly what to do about it.
			local lock = mkFrame(row, {
				Size = UDim2.new(0, 250, 0, 34), Position = UDim2.new(1, -262, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(120, 130, 145),
			})
			mkCorner(lock, 10)
			mkLabel(lock, {
				Text = "\xF0\x9F\x94\x92 Unlock " .. it.pet .. " to equip", Font = Enum.Font.GothamBold,
				TextSize = 13, TextScaled = true, TextColor3 = WHITE, Size = UDim2.new(1, -10, 1, 0),
				Position = UDim2.new(0, 5, 0, 0), TextXAlignment = Enum.TextXAlignment.Center,
			})
		else
			local btn = mkButton(row, {
				Size = UDim2.new(0, 130, 0, 38), Position = UDim2.new(1, -142, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = isEquipped and Color3.fromRGB(120, 160, 110) or LIME,
				Text = isEquipped and "EQUIPPED \xE2\x9C\x93" or "EQUIP", Font = Enum.Font.FredokaOne,
				TextSize = 16, TextScaled = true, TextColor3 = WHITE,
			})
			mkCorner(btn, 10); mkStroke(btn, LIME_DARK, 2)
			btn.MouseButton1Click:Connect(function()
				playUIClick()
				if isEquipped then
					EquipSkin:FireServer(it.pet, false)          -- toggle off -> back to the pet's natural look
				else
					EquipSkin:FireServer(it.pet, it.skin, it.trait or false)
				end
			end)
		end
	end
end

-- ============================================================================================================
-- TAB: TOKENS
-- ============================================================================================================
-- ============================================================================================================
-- TAB: TOKENS  --  earn them, or buy them. Nothing else.
-- ============================================================================================================
-- TWO EQUAL COLUMNS, 320 wide each with a 12px gutter (320 + 12 + 320 = 652, the body's usable width).
-- Earning is on the LEFT because it is the side a player should see first: tokens are a thing you can play for,
-- and putting the Robux packs first would frame them as the only way. Both panels are the same height and the
-- same card style, so neither reads as the 'real' option.
--
-- Every earn amount is read from CrateTokens.REWARDS -- the same table the SERVER pays out of -- so this list
-- physically cannot advertise a number the game does not honour.
--
-- ---- WHY THIS PAGE IS SHORT ---------------------------------------------------------------------------------
-- It shows FOUR ways to earn and THREE packs, and that is deliberately the whole list. A tall scrolling column of
-- near-identical rows reads as a wall and gets skimmed; four big rows get read. The entries that went were the
-- ones carrying the least: Daily and Weekly were the same sentence written twice (now one row quoting both
-- numbers), and "Events & Updates" only pays while an event happens to be running, so most of the time it
-- advertised nothing. Nothing became harder to earn -- every one of those payouts still fires exactly as before,
-- this page just stopped listing the ones a player cannot act on right now.
--
-- ---- WHY EVERY HEIGHT IS COMPUTED ---------------------------------------------------------------------------
-- body is 398 tall inside the 520 panel and reserves 10 for its own bottom padding: 388 pixels of run, not one
-- more. The TEST MODE strip, when it exists, eats into that. Rather than hand-typing card heights that fit one of
-- those two states and overflow the other -- which is what the old numbers did, 384 + 10 + 40 = 434 against a 388
-- budget, so this page has been quietly scrolling -- the columns take whatever is left and the cards divide it.
-- The page fits by construction in both states, and stays fitting if a pack or an earn row is ever added.
local function buildTokensTab()
	local BODY_RUN = 388
	local warnH    = SkinCrates.TEST_MODE and 34 or 0
	local rowH     = BODY_RUN - (warnH > 0 and (warnH + 10) or 0)
	local row = mkFrame(body, { Size = UDim2.new(1, -8, 0, rowH), BackgroundTransparency = 1, LayoutOrder = 1 })

	-- one shared panel shell, so the two columns are identical by construction rather than by copy-paste
	local function column(x, titleText)
		local col = mkFrame(row, { Size = UDim2.new(0, 320, 1, 0), Position = UDim2.new(0, x, 0, 0),
			BackgroundColor3 = CARD })
		mkCorner(col, 12); mkStroke(col, GOLD, 1.5)
		local h = mkLabel(col, {
			Text = titleText, Font = Enum.Font.FredokaOne, TextSize = 17, TextScaled = true, TextColor3 = GOLD,
			Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(h, Color3.new(0, 0, 0), 2)
		-- CoreClient force-sets TextScaled on every PlayerGui label, so the ceiling must come from a constraint
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 17; c.Parent = h end
		return col
	end

	-- ---------------------------------------------------------------- LEFT: earn free tokens
	local left = column(0, "EARN FREE TOKENS")
	-- Biggest payout first, so the largest number is the first thing read. `amountText` is an override for the one
	-- merged row that has two rates to quote; every other row still formats straight out of REWARDS.
	local EARN = {
		{ icon = "\xF0\x9F\x8F\x9D", name = "Complete Realms",     amount = CrateTokens.REWARDS.realmComplete,
			note = "Finish a realm's island run" },
		{ icon = "\xF0\x9F\x94\xA5", name = "7 Day Login Streak",  amount = CrateTokens.LOGIN_STREAK[#CrateTokens.LOGIN_STREAK],
			note = "Day 7 payout. Days 1-6 build up to it" },
		{ icon = "\xF0\x9F\x90\xBE", name = "Finish Pet Quests",   amount = CrateTokens.REWARDS.petQuest,
			note = "Each pet you unlock" },
		-- Daily and Weekly were two rows saying the same thing. One row now, both rates, both full-list bonuses.
		{ icon = "\xF0\x9F\x93\x85", name = "Daily & Weekly Tasks", amount = CrateTokens.REWARDS.dailyTask,
			amountText = "+" .. CrateTokens.REWARDS.dailyTask .. " / " .. CrateTokens.REWARDS.weeklyTask,
			note = "Per task. Clear a list for +" .. CrateTokens.REWARDS.dailyAllTasks
				.. " / +" .. CrateTokens.REWARDS.weeklyAllTasks },
	}
	-- Fill the column exactly: whatever height the scroll ends up with gets split between the rows. Fewer rows are
	-- therefore not merely fewer -- they are BIGGER, which is the whole point of dropping the other two.
	local EARN_GAP = 12
	local earnRowH = math.floor(((rowH - 100) - EARN_GAP * (#EARN - 1)) / #EARN)
	-- name (17) + 4 + note (14) = a 35px text block, centred in whatever height the row came out as
	local earnTextY = math.floor((earnRowH - 35) / 2)
	-- The list scrolls; the GO TO QUESTS button is pinned OUTSIDE it at the bottom so it can never be scrolled
	-- out of reach -- it is the one action on this side of the page.
	local earnList = Instance.new("ScrollingFrame"); earnList.Name = "EarnList"
	earnList.Size = UDim2.new(1, -16, 1, -100); earnList.Position = UDim2.new(0, 8, 0, 38)
	earnList.BackgroundTransparency = 1; earnList.BorderSizePixel = 0; earnList.ScrollBarThickness = 4
	earnList.ScrollBarImageColor3 = GOLD; earnList.CanvasSize = UDim2.new(0, 0, 0, 0)
	earnList.AutomaticCanvasSize = Enum.AutomaticSize.Y; earnList.Parent = left
	do
		local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, EARN_GAP)
		ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = earnList
	end
	for ei, e in ipairs(EARN) do
		-- The FRAME grows; every label inside keeps its exact height, so the type stays the size it always was and
		-- the entire gain lands as whitespace. That is "less crowded" without being "redesigned".
		local r = mkFrame(earnList, { Size = UDim2.new(1, -6, 0, earnRowH), BackgroundColor3 = HEADER, LayoutOrder = ei })
		mkCorner(r, 10); mkStroke(r, Color3.fromRGB(90, 130, 200), 1.5)
		mkLabel(r, {
			Text = e.icon, Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true, TextColor3 = WHITE,
			Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		})
		mkLabel(r, {
			Text = e.name, Font = Enum.Font.FredokaOne, TextSize = 14, TextScaled = true, TextColor3 = WHITE,
			Size = UDim2.new(1, -110, 0, 17), Position = UDim2.new(0, 42, 0, earnTextY),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkLabel(r, {
			Text = e.note, Font = Enum.Font.Gotham, TextSize = 11, TextScaled = true,
			TextColor3 = Color3.fromRGB(190, 210, 240), Size = UDim2.new(1, -110, 0, 14),
			Position = UDim2.new(0, 42, 0, earnTextY + 21), TextXAlignment = Enum.TextXAlignment.Left,
		})
		local amt = mkLabel(r, {
			Text = e.amountText or ("+" .. CrateTokens.format(e.amount or 0)), Font = Enum.Font.FredokaOne, TextSize = 15,
			TextScaled = true, TextColor3 = GOLD, Size = UDim2.new(0, 60, 0, 22),
			Position = UDim2.new(1, -66, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		mkStroke(amt, Color3.new(0, 0, 0), 2)
	end

	local toQuests = mkButton(left, {
		Size = UDim2.new(1, -16, 0, 46), Position = UDim2.new(0, 8, 1, -54),
		BackgroundColor3 = LIME, Text = "\xE2\x96\xB6 GO TO QUESTS", Font = Enum.Font.FredokaOne,
		TextSize = 17, TextScaled = true, TextColor3 = WHITE,
	})
	mkCorner(toQuests, 12); mkStroke(toQuests, LIME_DARK, 2)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 17; c.Parent = toQuests end
	toQuests.MouseButton1Click:Connect(function()
		playUIClick()
		-- Quests is a PET HUB page, so this is the same hand-off the QUESTS tab performs: close this panel, wake
		-- the hub, then route it. Firing PetInvToggle alone would reopen the hub on whatever page it was left on.
		setOpen(false)
		local ev = PlayerGui:FindFirstChild("PetInvToggle")
		if ev and ev:IsA("BindableEvent") then ev:Fire() end
		task.defer(function() if _G.PetHub and _G.PetHub.showPage then _G.PetHub.showPage("quests") end end)
	end)

	-- ---------------------------------------------------------------- RIGHT: buy tokens
	local right = column(332, "BUY TOKENS")
	local packList = Instance.new("ScrollingFrame"); packList.Name = "PackList"
	packList.Size = UDim2.new(1, -16, 1, -46); packList.Position = UDim2.new(0, 8, 0, 38)
	packList.BackgroundTransparency = 1; packList.BorderSizePixel = 0; packList.ScrollBarThickness = 4
	packList.ScrollBarImageColor3 = GOLD; packList.CanvasSize = UDim2.new(0, 0, 0, 0)
	packList.AutomaticCanvasSize = Enum.AutomaticSize.Y; packList.Parent = right
	-- CHEAPEST FIRST. Sorted here rather than trusting the order they happen to be authored in, so adding a pack
	-- to SkinCrates.TOKEN_PACKS can never drop it in the middle of the ladder.
	--
	-- ALL OF THEM. This used to keep only the cheapest three, because back when the column had to fit its
	-- contents without scrolling a fourth rung squeezed every card down to 77px and cost the other three
	-- their air.
	--
	-- That trade is gone: the cards now have a minimum height and the list is a ScrollingFrame, so a pack
	-- that does not fit scrolls into view instead of shrinking everything. Truncating is also the worse
	-- failure by far -- the two most expensive packs were silently dropped, which looks exactly like a
	-- broken scroll from the player's side and quietly hid the best-value rung the whole ladder builds up
	-- to. A list that scrolls is a list; a list that deletes its own last rows is a bug.
	local PACK_GAP = 16
	local packs = {}
	for _, pk in ipairs(SkinCrates.TOKEN_PACKS) do packs[#packs + 1] = pk end
	table.sort(packs, function(a, b) return (a.robux or 0) < (b.robux or 0) end)
	do
		local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, PACK_GAP)
		ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = packList
	end
	-- same rule as the earn rows: divide the column, never guess it
	-- Divide the row between the packs, but never below what a card actually needs.
	--
	-- This used to be a pure division, which quietly assumed the pack count would never change. It just
	-- did -- four packs became five -- and an unclamped divide answers that by shrinking every card ~20%
	-- until the buy button is hanging out of the bottom of its own frame. The list is a ScrollingFrame with
	-- AutomaticCanvasSize on, so the honest answer to "they do not all fit" is to let it scroll rather than
	-- to crush them until they do.
	local packCardH = math.max(96, math.floor(((rowH - 46) - PACK_GAP * (#packs - 1)) / #packs))
	-- amount (26) + 6 + rate (14) + 10 + button (28) = an 84px stack, centred in the card
	local packTextY = math.max(6, math.floor((packCardH - 84) / 2))
	for i, pack in ipairs(packs) do
		local card = mkFrame(packList, { Size = UDim2.new(1, -6, 0, packCardH), BackgroundColor3 = HEADER, LayoutOrder = i })
		mkCorner(card, 12); mkStroke(card, GOLD, 2)
		local nameLbl = mkLabel(card, {
			Text = CrateTokens.ICON .. "  " .. CrateTokens.format(pack.tokens),
			Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = GOLD,
			Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, packTextY),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)
		mkLabel(card, {
			Text = (pack.tag and (pack.tag .. "   \xE2\x80\xA2   ") or "")
				.. math.floor(pack.tokens / math.max(1, pack.robux) * 10) / 10 .. " tokens per R$",
			Font = Enum.Font.Gotham, TextSize = 11, TextScaled = true, TextColor3 = Color3.fromRGB(205, 224, 255),
			Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, packTextY + 32),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		-- EXTRA VALUE BADGE. How much further a Robux goes on THIS pack than on the smallest one.
		--
		-- Measured against the cheapest pack because that is a price a player can actually pay. The usual way
		-- to get a percentage onto every card is to invent a "single token" price nobody sells and discount
		-- everything off that -- but a saving against a price that does not exist is a made-up saving, and
		-- made-up savings are what consumer rules and storefront policy are both written about. This number is
		-- real: at +100% a Robux genuinely buys twice what it buys on the 25 R$ pack, and the card shows the
		-- tokens-per-R$ right next to it so anyone can check.
		--
		-- The entry pack therefore carries no badge. It is the thing everything else is better THAN, and
		-- stamping it with a discount against itself would be the one dishonest label on the shelf.
		local basePack = SkinCrates.TOKEN_PACKS[1]
		local baseRate = basePack and (basePack.tokens / math.max(1, basePack.robux)) or 0
		local thisRate = pack.tokens / math.max(1, pack.robux)
		local bonus    = (baseRate > 0) and math.floor((thisRate / baseRate - 1) * 100 + 0.5) or 0
		-- The badge is the extra value a bigger pack buys, so only the packs that HAVE extra value carry one.
		-- The entry pack is the baseline every percentage is measured from -- a badge there would either be
		-- a number measured against itself or a slogan pretending to be one, and a bare card next to four
		-- badged ones makes the ladder read at a glance anyway.
		if bonus >= 1 then
			local badge = mkFrame(card, {
				Size = UDim2.new(0, 96, 0, 26), Position = UDim2.new(1, -104, 0, packTextY - 2),
				BackgroundColor3 = Color3.fromRGB(46, 168, 84),
			})
			mkCorner(badge, 8); mkStroke(badge, Color3.fromRGB(24, 96, 48), 2)
			local bl = mkLabel(badge, {
				Text = "+" .. bonus .. "% VALUE",
				Font = Enum.Font.FredokaOne, TextSize = 14, TextScaled = true, TextColor3 = WHITE,
				Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3),
			})
			mkStroke(bl, Color3.new(0, 0, 0), 2)
		end
		local buy = mkButton(card, {
			Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, packTextY + 56),
			BackgroundColor3 = LIME, Text = pack.robux .. " R$", Font = Enum.Font.FredokaOne, TextSize = 17,
			TextScaled = true, TextColor3 = WHITE,
		})
		mkCorner(buy, 10); mkStroke(buy, LIME_DARK, 2)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 17; c.Parent = buy end
		buy.MouseButton1Click:Connect(function()
			playUIClick()
			BuyTokens:FireServer(pack.id)
		end)
	end

	if SkinCrates.TEST_MODE then
		-- One line at warnH, not two at 40. It is a note to the developer rather than part of the page, and every
		-- pixel it takes comes off the cards above it -- rowH is computed from this exact number.
		local warn = mkFrame(body, { Size = UDim2.new(1, -8, 0, warnH),
			BackgroundColor3 = Color3.fromRGB(255, 160, 20), LayoutOrder = 2 })
		mkCorner(warn, 10)
		mkLabel(warn, {
			Text = "TEST MODE: packs credit tokens with no Robux charge. Set SkinCrates.TEST_MODE = false at launch.",
			Font = Enum.Font.GothamBold, TextSize = 12, TextScaled = true, TextColor3 = Color3.fromRGB(70, 40, 0),
			Size = UDim2.new(1, -12, 1, -6), Position = UDim2.new(0, 6, 0, 3),
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
	end
end

-- ============================================================================================================
-- TAB: TRADE UP
-- ============================================================================================================
-- Hand in 10 skins of one rarity for 1 random skin of the next rarity up.
--
-- WHICH 10 GET BURNED is the part that needs care. Auto-picking the first ten the loop happens to see could
-- destroy the only copy of something the player likes, and "I lost my Cosmic to a trade-up I didn't read" is the
-- kind of thing that makes people stop trading up entirely. So:
--   * spares first -- a key with 4 copies contributes 3 before anything unique is touched;
--   * then, only if still short, unique items, rarest-looking last;
--   * and nothing is sent until the player has seen the exact list on a confirm screen.
local tradeUpInFlight = false
local showTradeUpResult -- forward (defined with the reveal helpers below)

-- Build the list of keys a contract at `tier` would consume, spares first. Returns the key list (may be short)
-- and the total number of that tier the player holds.
local function planTradeUp(tier)
	local need = SkinCrates.TRADE_UP.COST
	local entries, total = {}, 0
	for key, count in pairs(state.skins) do
		local petId, skinId = PetSkins.parseKey(key)
		if petId and skinId and PetSkins.tierOf(skinId) == tier then
			local n = math.max(0, math.floor(tonumber(count) or 0))
			if n > 0 then
				entries[#entries + 1] = { key = key, pet = petId, skin = skinId, count = n }
				total = total + n
			end
		end
	end
	-- most-duplicated first, so the deepest stacks are spent before the thin ones
	table.sort(entries, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.pet ~= b.pet then return a.pet < b.pet end
		return a.skin < b.skin
	end)

	local picked = {}
	-- PASS 1: spares only (leave one of each behind)
	for _, e in ipairs(entries) do
		local spare = e.count - 1
		while spare > 0 and #picked < need do picked[#picked + 1] = e.key; spare = spare - 1 end
		if #picked >= need then break end
	end
	-- PASS 2: still short -> start taking last copies
	if #picked < need then
		for _, e in ipairs(entries) do
			local used = 0
			for _, k in ipairs(picked) do if k == e.key then used = used + 1 end end
			if used < e.count and #picked < need then picked[#picked + 1] = e.key end
			if #picked >= need then break end
		end
	end
	return picked, total
end

-- Confirmation overlay: shows exactly what is about to be destroyed and what tier comes back.
local function confirmTradeUp(tier, target, keys, onYes)
	local shade = mkFrame(panel, {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35, ZIndex = 60, Active = true,
	})
	local box = mkFrame(shade, {
		Size = UDim2.new(0, 460, 0, 370), Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, ZIndex = 61,
	})
	mkCorner(box, 16); mkStroke(box, PetSkins.tierColor(target), 3)

	local h = mkLabel(box, {
		Text = "TRADE UP: " .. tier .. " \xE2\x86\x92 " .. target, Font = Enum.Font.FredokaOne, TextSize = 24,
		TextScaled = true, TextColor3 = PetSkins.tierColor(target), Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0, 10, 0, 10), ZIndex = 62,
	})
	mkStroke(h, Color3.new(0, 0, 0), 2)
	mkLabel(box, {
		Text = "These " .. #keys .. " will be DESTROYED for 1 random " .. target .. ". The pet, the skin and the "
			.. "trait are all rolled fresh.",
		Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255),
		Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 46), TextWrapped = true, ZIndex = 62,
	})

	-- the exact list, collapsed to "Skin Pet xN"
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 84); list.Size = UDim2.new(1, -24, 0, 210)
	list.BackgroundColor3 = CARD; list.BackgroundTransparency = 0.25; list.BorderSizePixel = 0
	list.ScrollBarThickness = 5; list.ScrollBarImageColor3 = GOLD; list.ZIndex = 62
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = box
	mkCorner(list, 10)
	do
		local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 3)
		ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
		local pd = Instance.new("UIPadding"); pd.PaddingTop = UDim.new(0, 5); pd.PaddingLeft = UDim.new(0, 8)
		pd.Parent = list
	end
	local tally, order = {}, {}
	for _, k in ipairs(keys) do
		if not tally[k] then tally[k] = 0; order[#order + 1] = k end
		tally[k] = tally[k] + 1
	end
	for i, k in ipairs(order) do
		local petId, skinId, traitId = PetSkins.parseKey(k)
		local txt = PetSkins.displayName(skinId, PetSkins.prettyPet(petId))
		if not PetTraits.isNone(traitId) then txt = txt .. " (" .. PetTraits.displayName(traitId) .. ")" end
		mkLabel(list, {
			Text = "\xE2\x80\xA2  " .. txt .. "   x" .. tally[k], Font = Enum.Font.GothamBold, TextSize = 14,
			TextScaled = true, TextColor3 = WHITE, Size = UDim2.new(1, -16, 0, 20), LayoutOrder = i,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63,
		})
	end

	local function close() shade:Destroy() end
	local no = mkButton(box, {
		Size = UDim2.new(0, 200, 0, 46), Position = UDim2.new(0, 14, 1, -56), BackgroundColor3 = CARD,
		Text = "CANCEL", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = WHITE, ZIndex = 62,
	})
	mkCorner(no, 12); mkStroke(no, WHITE, 2)
	no.MouseButton1Click:Connect(function() playUIClick(); close() end)

	local yes = mkButton(box, {
		Size = UDim2.new(0, 200, 0, 46), Position = UDim2.new(1, -214, 1, -56), BackgroundColor3 = LIME,
		Text = "TRADE UP", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = WHITE, ZIndex = 62,
	})
	mkCorner(yes, 12); mkStroke(yes, LIME_DARK, 2)
	yes.MouseButton1Click:Connect(function() playUIClick(); close(); onYes() end)
end

local function buildTradeUpTab()
	local intro = mkFrame(body, { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = HEADER, LayoutOrder = 1 })
	mkCorner(intro, 12); mkStroke(intro, GOLD, 1.5)
	mkLabel(intro, {
		Text = "TRADE UP MACHINE\nGive " .. SkinCrates.TRADE_UP.COST .. " skins of one rarity, get 1 random skin "
			.. "of the next rarity up. Duplicates are perfect for this.",
		Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255),
		Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
	})

	local need = SkinCrates.TRADE_UP.COST
	for i, tier in ipairs(SkinCrates.RARITY_ORDER) do
		-- Gold is a pet/crate band, not a skin tier -- no skin can ever sit in it, so a Gold contract row
		-- would be a permanent dead line. Skip it entirely; Legendary is the ladder's visible top.
		if tier == SkinCrates.GOLD_TIER then continue end
		local target = SkinCrates.tradeUpTarget(tier)
		local keys, total = planTradeUp(tier)
		local canDo = target ~= nil and #keys >= need
		local tierCol = PetSkins.tierColor(tier)

		local row = mkFrame(body, { Size = UDim2.new(1, -8, 0, 72), BackgroundColor3 = CARD, LayoutOrder = i + 1 })
		mkCorner(row, 12); mkStroke(row, tierCol, canDo and 3 or 2)
		if canDo then applyRarityFlair(row, tier) end -- only draw the eye to a contract that's actually ready

		local stripe = mkFrame(row, { Size = UDim2.new(0, 8, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = tierCol })
		mkCorner(stripe, 4)

		local title = target
			and (tier .. "  \xE2\x86\x92  " .. target)
			or (tier .. "  \xE2\x80\xA2  top rarity")
		local nameLbl = mkLabel(row, {
			Text = title, Font = Enum.Font.FredokaOne, TextSize = 19, TextScaled = true,
			TextColor3 = target and WHITE or Color3.fromRGB(170, 182, 200),
			Size = UDim2.new(1, -290, 0, 24), Position = UDim2.new(0, 22, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)

		local sub
		if not target then
			sub = "Nothing to trade up into -- " .. tier .. " is the top of the ladder."
		else
			sub = "You have " .. total .. " " .. tier .. "   \xE2\x80\xA2   need " .. need
		end
		mkLabel(row, {
			Text = sub, Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true,
			TextColor3 = canDo and Color3.fromRGB(180, 255, 190) or Color3.fromRGB(205, 224, 255),
			Size = UDim2.new(1, -290, 0, 18), Position = UDim2.new(0, 22, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		if target then
			local btn = mkButton(row, {
				Size = UDim2.new(0, 150, 0, 42), Position = UDim2.new(1, -162, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = canDo and LIME or Color3.fromRGB(120, 130, 145),
				Text = canDo and "TRADE UP" or (math.min(total, need) .. " / " .. need),
				Font = Enum.Font.FredokaOne, TextSize = 16, TextScaled = true, TextColor3 = WHITE,
			})
			mkCorner(btn, 10); mkStroke(btn, canDo and LIME_DARK or Color3.fromRGB(90, 98, 112), 2)
			if canDo then
				btn.MouseButton1Click:Connect(function()
					playUIClick()
					if tradeUpInFlight then return end
					-- Re-plan at click time rather than trusting the list built when the tab was drawn: a crate
					-- opened, or a trade completed, in between would otherwise submit stale keys the server rejects.
					local liveKeys, liveTotal = planTradeUp(tier)
					if #liveKeys < need then
						refreshTabs() -- the tab is stale; redraw it so the count tells the truth
						return
					end
					local _ = liveTotal
					confirmTradeUp(tier, target, liveKeys, function()
						if tradeUpInFlight then return end
						tradeUpInFlight = true
						task.spawn(function()
							local ok, result = pcall(function() return TradeUpRF:InvokeServer(tier, liveKeys) end)
							tradeUpInFlight = false
							if ok and type(result) == "table" and result.ok then
								if showTradeUpResult then showTradeUpResult(result) end
							else
								local why = (type(result) == "table" and result.reason) or "error"
								warn("[SkinCrate] trade-up refused: " .. tostring(why))
								refreshTabs()
							end
						end)
					end)
				end)
			end
		end
	end
end

-- ============================================================================================================
-- TAB: COLLECTION BOOK
-- ============================================================================================================
-- Every skin for every pet, owned or not, so a player always knows what they're missing. Completion is
-- trait-agnostic (see PetCollection) -- a Galaxy Pizza Dragon ticks Galaxy off whether or not it came Crowned.
local function buildCollectionTab()
	-- collapse the inventory to [pet] = { [skin] = true }, dropping traits
	local sets = {}
	for key, count in pairs(state.skins) do
		if (tonumber(count) or 0) > 0 then
			local petId, skinId = PetSkins.parseKey(key)
			if petId and skinId then
				local t = sets[petId]; if not t then t = {}; sets[petId] = t end
				t[skinId] = true
			end
		end
	end

	-- Which pets to show. Prefer the server's unlocked list plus anything we hold a skin for; fall back to the
	-- crate contents so the book is never blank on a fresh account with nothing unlocked yet.
	local petSet = {}
	for petId in pairs(state.unlocked) do petSet[petId] = true end
	for petId in pairs(sets) do petSet[petId] = true end
	for _, crate in ipairs(SkinCrates.CRATES) do
		for _, pool in pairs(crate.contents) do
			-- level/trait entries carry no pet; petSet[nil] would be a hard error
			for _, e in ipairs(pool) do if e.pet then petSet[e.pet] = true end end
		end
	end
	local pets = {}
	for petId in pairs(petSet) do pets[#pets + 1] = petId end
	table.sort(pets)

	local completed = (state.collection and state.collection.completedPets) or {}

	-- summary header
	local doneCount = 0
	for _, petId in ipairs(pets) do if completed[petId] then doneCount = doneCount + 1 end end
	local intro = mkFrame(body, { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = HEADER, LayoutOrder = 1 })
	mkCorner(intro, 12); mkStroke(intro, GOLD, 1.5)
	mkLabel(intro, {
		Text = "COLLECTION BOOK   \xE2\x80\xA2   " .. doneCount .. " / " .. #pets .. " pets completed\n"
			.. "Complete a pet's set for a title, an aura, a badge and an exclusive skin.",
		Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255),
		Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
	})

	for pi, petId in ipairs(pets) do
		local rows, owned, total = PetCollection.page(sets[petId])
		local isDone = completed[petId] == true

		-- One card per pet: a header line, then a wrapped grid of every skin as a tick or a cross.
		local perRow = 5
		local cellH, cellPad = 26, 4
		local gridRows = math.ceil(#rows / perRow)
		local cardH = 40 + gridRows * (cellH + cellPad) + 8

		local card = mkFrame(body, { Size = UDim2.new(1, -8, 0, cardH), BackgroundColor3 = CARD, LayoutOrder = pi + 1 })
		mkCorner(card, 12); mkStroke(card, isDone and GOLD or Color3.fromRGB(90, 130, 200), isDone and 3 or 2)
		if isDone then applyRarityFlair(card, "Gold") end -- a finished set gets the jackpot treatment

		local hdr = mkLabel(card, {
			Text = (isDone and "\xE2\x9C\x94 " or "") .. PetSkins.prettyPet(petId) .. "   " .. owned .. " / " .. total,
			Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true,
			TextColor3 = isDone and GOLD or WHITE, Size = UDim2.new(1, -20, 0, 26),
			Position = UDim2.new(0, 12, 0, 6), TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(hdr, Color3.new(0, 0, 0), 2)

		local grid = mkFrame(card, {
			Size = UDim2.new(1, -20, 0, gridRows * (cellH + cellPad)), Position = UDim2.new(0, 10, 0, 36),
			BackgroundTransparency = 1,
		})
		do
			local gl = Instance.new("UIGridLayout")
			gl.CellSize = UDim2.new(0, 128, 0, cellH)
			gl.CellPadding = UDim2.new(0, cellPad, 0, cellPad)
			gl.SortOrder = Enum.SortOrder.LayoutOrder
			gl.Parent = grid
		end
		for ri, r in ipairs(rows) do
			local cell = mkFrame(grid, {
				Size = UDim2.new(0, 128, 0, cellH), LayoutOrder = ri,
				BackgroundColor3 = r.owned and r.color or Color3.fromRGB(58, 66, 80),
				BackgroundTransparency = r.owned and 0.25 or 0.4,
			})
			mkCorner(cell, 6)
			mkLabel(cell, {
				Text = (r.owned and "\xE2\x9C\x85 " or "\xE2\x9D\x8C ") .. r.name,
				Font = Enum.Font.GothamBold, TextSize = 12, TextScaled = true,
				TextColor3 = r.owned and WHITE or Color3.fromRGB(150, 160, 175),
				Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end
end

-- ============================================================================================================
-- TAB SWITCHING
-- ============================================================================================================
refreshTabs = function()
	tokenLbl.Text = CrateTokens.ICON .. " " .. CrateTokens.format(state.tokens)
	-- A sub-page keeps its PARENT tab lit: sitting on Collection with no tab highlighted reads as being lost.
	local litTab = activeTab
	if litTab == "inventory" or litTab == "tradeup" or litTab == "collection" or litTab == "tokens" then litTab = "crates" end
	for id, b in pairs(tabButtons) do
		local on = (id == litTab)
		-- Selected = yellow, unselected = blue, matching the Pet Hub's tab styling.
		b.BackgroundColor3 = on and GOLD or CARD
		-- Selected = dark-on-gold (max contrast, unmistakably the active tab); unselected = gold-on-blue,
		-- matching the panel title rather than shouting in pure white.
		b.TextColor3 = on and Color3.fromRGB(92, 58, 8) or GOLD
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then st.Color = on and Color3.fromRGB(180, 122, 20) or WHITE; st.Thickness = on and 2.5 or 1.5 end
	end
	if not gui.Enabled then return end -- don't rebuild a hidden panel
	clearBody()
	-- crates/tokens are top-level pages; inventory/tradeup/collection are sub-pages reached from them. A hub
	-- page id can never reach here (the click handler hands those off before touching activeTab).
	if activeTab == "inventory" then buildInventoryTab()
	elseif activeTab == "tradeup" then buildTradeUpTab()
	elseif activeTab == "collection" then buildCollectionTab()
	elseif activeTab == "tokens" then buildTokensTab()
	else buildCratesTab() end
end

for id, b in pairs(tabButtons) do
	b.MouseButton1Click:Connect(function()
		playUIClick()
		-- PETS / TRADE / QUESTS belong to the Pet Hub: close this panel and open it on that page. Firing
		-- PetInvToggle alone would only re-open the hub on whatever page it was last left on.
		local hubPage = TAB_TO_HUB[id]
		if hubPage then
			setOpen(false)
			local ev = PlayerGui:FindFirstChild("PetInvToggle")
			if ev and ev:IsA("BindableEvent") then ev:Fire() end
			-- one frame for the hub to build/open before routing it
			task.defer(function() if _G.PetHub and _G.PetHub.showPage then _G.PetHub.showPage(hubPage) end end)
		return
		end
		activeTab = id; refreshTabs()
	end)
end

-- ============================================================================================================
-- THE CS:GO REEL
-- ============================================================================================================
-- Geometry: cells of CELL_W scroll right-to-left behind a fixed centre marker. We build a strip long enough that
-- the eye never sees the ends, place the WINNING item at WIN_INDEX, and tween the strip so that cell lands dead
-- centre. Because the stop position is computed FROM the server's result, the reel physically cannot end on
-- anything else.
-- THE CAROUSEL IS THE INTERFACE. It takes 408 of the panel's 520px (78% of the whole panel, 82% of what
-- is left after margins), and the cards scale WITH it -- 224x344 instead of 108x156. At that width ~3
-- cells span the 676px window, which is exactly the Pet-Simulator read: one big centred pet with its
-- neighbours half-visible either side.
local CELL_W, CELL_H = 228, 348
local WINDOW_Y   = 34
local WINDOW_H   = 474           -- 91% of the 520-tall panel: the carousel IS the interface now
local MARKER_Y   = 26
local MARKER_H   = WINDOW_H + 16 -- overhangs top and bottom so the selector reads as a fixed rail
local EDGE_FADE  = 110           -- soft cut-off at each end, scaled up with the window
-- THERE IS NO INFO PANEL. The reward reads off the winning CARD -- already centred under the marker, already
-- showing the pet, its skin and its name -- so a second blue box restating it was pure duplication. What is
-- left of the reveal (rarity, trait, note, CLAIM) floats over the lower strip of the carousel with no
-- container of its own, so the cards keep the full height.
--
-- CARD_TOP: cards are TOP-anchored in the window rather than centred, which reserves REVEAL_BAND at the
-- bottom for that floating text without shrinking the window.
local CARD_TOP    = 8
local REVEAL_Y    = WINDOW_Y + CARD_TOP + CELL_H + 10  -- first line of floating reveal text
local REVEAL_BAND = (WINDOW_Y + WINDOW_H) - REVEAL_Y   -- what is left under the cards
local WIN_CELL_NAME = "WinningCell" -- lets the payoff find the landed card without repeating index maths
local STRIP_LEN  = 56 -- cells built
local WIN_INDEX  = 48 -- which cell holds the winner (leaves 8 cells of runout so the stop isn't at the very end)

-- ONE CONTINUOUS DECELERATION -- position = start + distance * (1 - (1-t)^SPIN_EASE), stepped every frame.
--
-- This replaced a three-stage version (fast tween -> linear crawl -> settle tween) that had a visible hitch:
-- an ease-out finishes at near-zero speed, so when the linear crawl took over at a CONSTANT speed the reel
-- appeared to stop and then set off again. Chaining tweens can't avoid that -- the velocity at a stage boundary
-- is whatever each curve happens to end and begin at, and those don't match. Driving one curve by hand means
-- speed falls monotonically from full to zero with nothing to bump against.
--
-- SPIN_EASE is the whole feel, and it's a real trade-off:
--   5+ (Quint/Expo)  the reel is within ~20px of the answer with 2s still to run -- the last third is motionless
--                    and it reads as "it already landed, now it's just waiting".
--   3.2             ~1.5 cells still to travel at that same point, so those seconds are spent visibly creeping
--                    past a near-miss and easing down to nothing. This is the number to tune.
--   2 or lower      still moving quickly at the end, so it snaps to a halt instead of settling.
local SPIN_TIME = 6.0
local SPIN_EASE = 3.2
-- Authored reel geometry. The landing maths uses these LOCAL units rather than AbsoluteSize so the stop stays
-- centred under any UIScale -- see the comment in openReveal.
-- The reveal uses the SAME footprint as the crate panel it opened from (700x520 at 0.5,-45), so the two
-- never jump size or position when one replaces the other. REEL_WINDOW_INSET is unchanged -- the landing
-- maths in openReveal derives the window width from these two constants.
local REEL_PANEL_W      = 700
local REEL_PANEL_H      = 520
local REEL_WINDOW_INSET = 24

local revealGui = Instance.new("ScreenGui")
revealGui.Name = "SkinCrateRevealGui"; revealGui.ResetOnSpawn = false; revealGui.Enabled = false
revealGui.DisplayOrder = 200 -- above EVERY menu panel: shop/hub (100), codes/group (130), banner (140), wormhole (160)
revealGui.IgnoreGuiInset = true
revealGui.Parent = PlayerGui

-- click-catcher only, no dim: the reveal panel draws with no darkening of the world behind it
local dim = mkFrame(revealGui, {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Active = true,
})

local reelPanel = mkFrame(revealGui, {
	Size = UDim2.new(0, REEL_PANEL_W, 0, REEL_PANEL_H), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, ClipsDescendants = true,
})
mkCorner(reelPanel, 18); mkStroke(reelPanel, PANEL_DARK, 4)

local reelTitle = mkLabel(reelPanel, {
	Text = "OPENING...", Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Center,
})
mkStroke(reelTitle, Color3.new(0, 0, 0), 2)

-- the window the strip scrolls through
local reelWindow = mkFrame(reelPanel, {
	Size = UDim2.new(1, -REEL_WINDOW_INSET, 0, WINDOW_H), Position = UDim2.new(0, REEL_WINDOW_INSET / 2, 0, WINDOW_Y),
	BackgroundColor3 = HEADER, ClipsDescendants = true,
})
mkCorner(reelWindow, 12); mkStroke(reelWindow, PANEL_DARK, 2)

local strip = mkFrame(reelWindow, { Size = UDim2.new(0, STRIP_LEN * CELL_W, 1, 0), BackgroundTransparency = 1 })

-- EDGE FADE -- cards dissolve into the panel at each end instead of being sliced off mid-cell. Two gradient
-- overlays in the window's own colour rather than a CanvasGroup: a CanvasGroup would fade the real thing,
-- but ViewportFrames (every pet thumbnail) are unreliable inside one, so this stays overlay-based.
for _, side in ipairs({ -1, 1 }) do
	local fade = mkFrame(reelWindow, {
		Size = UDim2.new(0, EDGE_FADE, 1, 0),
		Position = (side < 0) and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -EDGE_FADE, 0, 0),
		BackgroundColor3 = HEADER, ZIndex = 20,
	})
	local fg = Instance.new("UIGradient"); fg.Parent = fade
	-- opaque at the outer edge, clear by the inner edge
	fg.Transparency = (side < 0)
		and NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		or NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
end

-- centre marker: a gold line with arrows above and below, so the landing point is unmistakable
local marker = mkFrame(reelPanel, {
	Size = UDim2.new(0, 5, 0, MARKER_H), Position = UDim2.new(0.5, 0, 0, MARKER_Y), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = GOLD, ZIndex = 6,
})
mkCorner(marker, 2)
local markerArrow = mkLabel(reelPanel, {
	Text = "\xE2\x96\xBC", Font = Enum.Font.GothamBold, TextSize = 20, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(0, 30, 0, 24), Position = UDim2.new(0.5, 0, 0, WINDOW_Y + 6), AnchorPoint = Vector2.new(0.5, 0),
	-- inside the window and above the edge fades (ZIndex 20), pointing down at the centre cell
	ZIndex = 22, TextXAlignment = Enum.TextXAlignment.Center,
})

-- ============================================================================================================
-- REVEAL CELEBRATION (contained)
-- ============================================================================================================
-- Everything here is parented to reelPanel, which has ClipsDescendants = true -- so the effect physically
-- CANNOT leave the crate-opening UI. The previous version flashed a full-screen sheet parented to revealGui,
-- which washed the whole game out for the better part of a second and had nothing to do with the panel you
-- were actually looking at.
--
-- Scaled by tier, so the effect tells you how good the pull was before you've read anything:
--   Rare 6 sparks -> Uncommon/Common nothing -> Gold 30 sparks + a gold wash across the panel.
local BURST = {
	Rare      = { sparks =  6 },
	Epic      = { sparks = 12 },
	Legendary = { sparks = 20, wash = 0.55 },
	Gold      = { sparks = 30, wash = 0.25, ring = true },
}

-- The reel half of the panel. A trade-up has no strip to scroll, so it hides these and keeps the SAME
-- 700x520 frame -- the old code shrank the panel to 90px, which would now clip the result card away.
local function setReelVisible(on)
	reelWindow.Visible = on
	marker.Visible = on
	markerArrow.Visible = on
end

local function celebrate(tier)
	local cfg = BURST[tier]
	if not cfg or not reelPanel.Visible then return end
	local col = PetSkins.tierColor(tier)

	-- (1) WASH -- a tint over the PANEL only, gone in well under a second.
	if cfg.wash then
		local wash = mkFrame(reelPanel, {
			Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = col,
			BackgroundTransparency = cfg.wash, ZIndex = 40,
		})
		TweenService:Create(wash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
		Debris:AddItem(wash, 0.8)
	end

	-- (2) SHOCK RING -- one expanding circle from the marker. Top tier only; it's the loudest thing here.
	if cfg.ring then
		local ring = mkFrame(reelPanel, {
			Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 41,
		})
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local rs = Instance.new("UIStroke"); rs.Color = col; rs.Thickness = 5; rs.Parent = ring
		TweenService:Create(ring, TweenInfo.new(0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(640, 640) }):Play()
		TweenService:Create(rs, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1, Thickness = 0.5 }):Play()
		Debris:AddItem(ring, 0.9)
	end

	-- (3) SPARKS -- thrown out from the marker, arcing and fading. Spawned from the CENTRE (where the winning
	-- cell just landed) so the eye is already there.
	for i = 1, cfg.sparks do
		local spark = mkLabel(reelPanel, {
			Text = "\xE2\x9C\xA6", Font = Enum.Font.GothamBold, TextColor3 = col,
			TextSize = math.random(11, 22), TextScaled = true,
			Size = UDim2.fromOffset(math.random(11, 22), math.random(11, 22)),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 42,
			Rotation = math.random(0, 359),
		})
		local ox, oy = math.random(-34, 34), math.random(-14, 14)
		spark.Position = UDim2.new(0.5, ox, 0.5, oy)
		-- Elliptical spread: wider than tall, because the panel is wider than it is tall. A circular spread
		-- would bunch everything against the top and bottom edges and get clipped away immediately.
		local ang = math.rad(math.random(0, 359))
		local reach = math.random(70, 300)
		local dx = math.cos(ang) * reach
		local dy = math.sin(ang) * reach * 0.42
		local dur = 0.55 + math.random() * 0.55
		TweenService:Create(spark, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, ox + dx, 0.5, oy + dy),
			TextTransparency = 1,
			Rotation = spark.Rotation + math.random(-200, 200),
		}):Play()
		Debris:AddItem(spark, dur + 0.15)
	end
end

-- result card, shown after the reel stops
-- The reveal layer: NOT a panel. An invisible group holding the floating text and the CLAIM button over the
-- bottom strip of the carousel. Grouping them keeps ONE Visible flag driving the whole reveal, exactly as the
-- old card did, without putting a box back on screen.
-- ZIndex 50 keeps it above the celebration layers (wash 40, ring 41, sparks 42) -- those are brief, but that
-- brief moment is precisely when CLAIM gets pressed.
local resultCard = mkFrame(reelPanel, {
	Size = UDim2.new(0, 676, 0, REVEAL_BAND), Position = UDim2.new(0.5, 0, 0, REVEAL_Y),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 50,
})
-- THE PAYOFF PICTURE: the pet you actually won, wearing the skin you actually won. Sits on the left with the
-- text to its right, so the card keeps its 460x190 footprint and nothing else in the reveal has to move.
-- A TRADE-UP has no reel to scroll, so nothing else would show the item. This holder sits in the middle of
-- the (hidden) carousel for that case only; on a crate open the winning CARD is the picture, so it stays off.
local resultPetHolder = mkFrame(reelPanel, {
	Size = UDim2.new(0, 260, 0, 260), Position = UDim2.new(0.5, 0, 0, WINDOW_Y + 40),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 30,
})
-- Rebuilt per reveal -- the pet and skin change every open. static=false: this is the ONE model that earns
-- the full look (particles, light, and its trait).
local function showResultPet(petId, skinId, traitId)
	for _, ch in ipairs(resultPetHolder:GetChildren()) do ch:Destroy() end
	resultPetHolder.Visible = true
	makePetPreview(resultPetHolder, petId, skinId, traitId, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), false)
end
local resultName = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 30, TextScaled = true, TextColor3 = WHITE,
	-- The text block is centred in the 462px LEFT of the button, not across the whole band -- centring it
	-- across the full width would read as off-centre, because the button occupies only the right side.
	Size = UDim2.new(0, 462, 0, 38), Position = UDim2.new(0, 8, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
mkStroke(resultName, Color3.new(0, 0, 0), 2)
-- TextScaled shrinks a long name to fit instead of clipping it; the constraint stops a SHORT name from
-- ballooning to fill 40px of height and swamping the lines beneath it.
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = resultName end
local resultTier = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(0, 462, 0, 20), Position = UDim2.new(0, 8, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
local resultTrait = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.GothamBold, TextSize = 15, TextScaled = true, TextColor3 = WHITE,
	Size = UDim2.new(0, 462, 0, 18), Position = UDim2.new(0, 8, 0, 62),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
local resultNote = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.Gotham, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(205, 224, 255),
	Size = UDim2.new(0, 462, 0, 20), Position = UDim2.new(0, 8, 0, 82),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = resultTier end
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = resultTrait end
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = resultNote end
local resultBtn = mkButton(resultCard, {
	Size = UDim2.new(0, 190, 0, 60), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = LIME, Text = "NICE!", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true, TextColor3 = WHITE,
})
mkCorner(resultBtn, 12); mkStroke(resultBtn, LIME_DARK, 2)

-- SKIP -- jump straight to the reward. The reel is ~6s and you will open a lot of these; forcing the full
-- animation every time turns a good moment into a chore. It only ever snaps the strip to the position the
-- server already chose, so skipping cannot change (or reveal early) anything the roll didn't already decide.
local skipBtn = mkButton(reelPanel, {
	Size = UDim2.new(0, 160, 0, 40), Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 20), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = CARD, Text = "SKIP \xE2\x9D\xAF\xE2\x9D\xAF", Font = Enum.Font.FredokaOne,
	TextSize = 16, TextScaled = true, TextColor3 = WHITE, Visible = false, ZIndex = 8,
})
mkCorner(skipBtn, 10); mkStroke(skipBtn, WHITE, 1.5)
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = skipBtn end

-- Build one reel cell. Cells are plain coloured tiles with the skin name, the pet name and a rarity stripe --
-- readable at speed, which matters more here than detail nobody can see while it's moving.
local function buildCell(parent, x, item)
	local tierCol = PetSkins.tierColor(item.rarity)
	local cell = mkFrame(parent, {
		-- TOP-anchored vertically so the band underneath stays free for the floating reveal text; CENTRE-
		-- anchored horizontally so the focus scaling below grows and shrinks the card about its own middle
		-- instead of dragging it sideways off the marker.
		Size = UDim2.new(0, CELL_W - 8, 0, CELL_H),
		Position = UDim2.new(0, x + math.floor(CELL_W / 2), 0, CARD_TOP),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = CARD,
	})
	mkCorner(cell, 14); mkStroke(cell, tierCol, 3)
	-- Driven per frame by the focus pass in openReveal. A UIScale rather than a Size tween because it
	-- scales the card's CONTENTS too -- the pet, the band, the captions all shrink together.
	do local sc = Instance.new("UIScale"); sc.Name = "Focus"; sc.Scale = 1; sc.Parent = cell end
	-- rarity band across the top
	local band = mkFrame(cell, { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = tierCol })
	mkCorner(band, 7)
	local skin = PetSkins.get(item.skin)
	-- a big colour swatch standing in for the skin, tinted with the skin's own colour
	-- THE TOP TIER IS MASKED IN THE REEL. A Gold cell shows a prize rosette and nothing else -- no pet, no
	-- skin name -- so scrolling past one tells you a jackpot is IN this crate without spoiling which one you
	-- are about to win. That reveal belongs to the result card, and giving it away here would throw away the
	-- best moment the system has. It is the same reason CS:GO never shows the knife in the reel.
	--
	-- This is presentation only. The server has ALREADY chosen the reward, the reel still lands on that exact
	-- cell, and the odds panel still publishes every item in the crate -- so nothing here hides information
	-- the player is owed.
	local isTop = (item.rarity == SkinCrates.GOLD_TIER)

	-- A PET LEVEL CRATE cell. There is no pet and no skin to draw -- the reward IS the number -- so the cell
	-- shows it at the size the pet preview would have taken. The top tier keeps its struck-medal treatment but
	-- does NOT hide the number: masking exists to protect WHICH pet/skin you are about to win, and a level crate
	-- has no such secret. Hiding '+10' would only make the best pull in the crate unreadable.
	if item.levels then
		local plate = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = isTop and Color3.fromRGB(46, 34, 8) or Color3.fromRGB(18, 34, 66),
		})
		mkCorner(plate, 12); mkStroke(plate, tierCol, 3)
		local disc = mkFrame(plate, {
			Size = UDim2.fromOffset(132, 132), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = tierCol,
		})
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc end
		mkStroke(disc, Color3.fromRGB(12, 24, 48), 2)
		do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Parent = disc
			g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), tierCol) end
		mkLabel(disc, {
			Text = "+" .. item.levels, Font = Enum.Font.FredokaOne, TextSize = 56, TextScaled = true,
			TextColor3 = Color3.fromRGB(18, 34, 66), Size = UDim2.new(1, -22, 1, -22),
			Position = UDim2.new(0, 11, 0, 11),
		})
		mkLabel(cell, {
			Text = item.levels == 1 and "1 Pet Level" or (item.levels .. " Pet Levels"),
			Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true, TextColor3 = isTop and GOLD or WHITE,
			Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		mkLabel(cell, {
			Text = "PET LEVELS", Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
		applyRarityFlair(cell, item.rarity, true)
		return cell
	end

	-- A TRAIT CRATE cell shows THE GOODS the same way a skin cell does: a real 3D pet actually WEARING the
	-- trait (accessories and all), against a backdrop tinted the trait's own colour. Every cell uses the
	-- same DEMO MODEL -- a Classic Butter Duck -- because the actual ride-along pet+skin is rolled at open
	-- time and cannot be known while the reel spins; the payoff flips the winning card to the real grant.
	-- Not masked at Gold: the crate holds exactly one trait per band, so there is no which-item secret.
	if item.trait then
		local swatch = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = PetTraits.color(item.trait) or tierCol, BackgroundTransparency = 0.35,
		})
		mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
		makePetPreview(cell, TRAIT_DEMO_PET, "Classic", item.trait,
			UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
		local traitLbl = mkLabel(cell, {
			Text = PetTraits.displayName(item.trait), Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true,
			TextColor3 = PetTraits.color(item.trait) or (isTop and GOLD or WHITE),
			Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		traitLbl.Name = "SkinName" -- same caption names as a skin cell, so the payoff can rewrite them in place
		local subLbl2 = mkLabel(cell, {
			Text = "TRAIT", Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
		subLbl2.Name = "PetName"
		applyRarityFlair(cell, item.rarity, true)
		return cell
	end

	if isTop then
		local plate = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = Color3.fromRGB(46, 34, 8),
		})
		plate.Name = "MysteryPlate" -- the payoff finds it by name to tear the mask off (see unmaskWinner)
		mkCorner(plate, 12); mkStroke(plate, tierCol, 3)
		-- one big struck medal, centred, filling the space the pet would have used
		local medal = mkFrame(plate, {
			Size = UDim2.fromOffset(112, 112), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = tierCol,
		})
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = medal end
		mkStroke(medal, Color3.fromRGB(92, 58, 8), 2)
		do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Parent = medal
			g.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), tierCol) end
		mkLabel(medal, {
			Text = "\xE2\x98\x85", Font = Enum.Font.FredokaOne, TextSize = 52, TextScaled = true,
			TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -16, 1, -16),
			Position = UDim2.new(0, 8, 0, 8),
		})
	else
		-- Every other tier shows the goods. The skin-coloured panel stays as a BACKDROP: it reads the tier
		-- colour even while the reel is a blur, and gives the 3D pet something to sit against.
		local swatch = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = (skin and skin.color) or Color3.fromRGB(120, 130, 145),
		})
		mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
		-- THE ACTUAL ITEM: this pet, wearing this skin.
		makePetPreview(cell, item.pet, item.skin, nil, UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
	end
	-- Both captions are NAMED so the payoff can rewrite them in place when a masked Gold card lands.
	local skinLbl = mkLabel(cell, {
		-- masked for the top tier: printing 'Cosmic' here would undo everything the rosette just did
		-- A PET CRATE cell has no skin, so the old `(skin and skin.displayName) or item.skin` resolved to nil --
		-- and assigning nil to .Text is a hard error in Roblox, which would have killed the reel build mid-strip.
		-- The species name is the right label there anyway: on that crate the PET is the prize and the cell's
		-- tier colour already carries the rarity.
		Text = isTop and "???" or ((skin and skin.displayName) or item.skin or PetSkins.prettyPet(item.pet)),
		Font = Enum.Font.FredokaOne, TextSize = 15,
		TextScaled = true, TextColor3 = isTop and GOLD or WHITE, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	skinLbl.Name = "SkinName"
	local petLbl = mkLabel(cell, {
		Text = isTop and "MYSTERY PRIZE" or PetSkins.prettyPet(item.pet), Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
		TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
	})
	petLbl.Name = "PetName"
	-- lite=true: pulse + shimmer only. A Rare+ cell flashing past the marker is what builds the "wait, was that
	-- a good one?" tension during the slowdown -- sparkles/glow would just be noise at reel speed.
	applyRarityFlair(cell, item.rarity, true)
	return cell
end

-- UNMASK THE JACKPOT. A Gold cell rides the reel as a rosette so scrolling past one never gives away which
-- item is in the crate -- that reveal is the best moment the system has, and spending it on a blurred cell
-- mid-spin wastes it. But once the reel has STOPPED on it the secret has done its job, and leaving the card
-- as a rosette means the one thing the player actually wants to look at is the only card not showing its
-- prize. So the mask comes off and the card becomes what every other winning card already is: this pet, in
-- this skin, wearing this trait.
--
-- Self-guarding: no MysteryPlate means the cell was never masked (every tier below Gold, and every cell in a
-- level crate, which has no pet to hide), so this is a no-op and safe to call on any winner.
local function unmaskWinner(cell, petId, skinId, traitId)
	local plate = cell:FindFirstChild("MysteryPlate")
	if not (plate and petId and skinId) then return false end
	plate:Destroy()
	local skin = PetSkins.get(skinId)
	-- same backdrop + preview pair the unmasked tiers build, so the flipped card is indistinguishable from
	-- one that was never masked -- no second code path to keep in step.
	local swatch = mkFrame(cell, {
		Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
		BackgroundColor3 = (skin and skin.color) or Color3.fromRGB(120, 130, 145),
	})
	mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
	-- the real trait too, not nil: the reel passes nil while scrolling, but the winner should show what was
	-- actually granted, which is what the result card underneath is about to name.
	makePetPreview(cell, petId, skinId, traitId, UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
	local sn = cell:FindFirstChild("SkinName")
	if sn then sn.Text = (skin and skin.displayName) or skinId end
	-- the trait is half the prize, so the card says it out loud in the trait's own colour instead of leaving
	-- it to the small print on the result band below
	local pn = cell:FindFirstChild("PetName")
	if pn then
		if traitId and not PetTraits.isNone(traitId) then
			pn.Text = PetSkins.prettyPet(petId) .. "  \xE2\x80\xA2  " .. PetTraits.displayName(traitId) .. " Trait"
			pn.TextColor3 = PetTraits.color(traitId) or pn.TextColor3
		else
			pn.Text = PetSkins.prettyPet(petId)
		end
	end
	return true
end

local spinning = false
-- Separate flag from `spinning`: `spinning` is cleared at the PAYOFF, `building` the moment the strip has
-- finished being built. Two flags because the dangerous window is the BUILD -- a second entrant partway
-- through would leave the first pass's cells, and their queued previews, alive alongside the new ones.
local building = false
-- Guards the SETTLE step specifically. The spin can end two ways -- the drive loop reaching t >= 1, or SKIP
-- snapping it early -- and both fall through to the same payoff. One flag, set the instant the strip stops,
-- means the win visuals apply exactly once per spin no matter which path got there.
local settled = false

-- THE REVEAL. `result` is the server's already-granted payload; `crate` is the crate it came from.
local function openReveal(crate, result)
	-- BUILD DEBOUNCE. openReveal destroys and rebuilds all STRIP_LEN cells; a second entrant partway
	-- through would leave the first pass's cells (and their queued previews) alive alongside the new
	-- ones. `spinning` already gated this, but it was cleared on the payoff rather than at the end of
	-- the build, leaving a window where a fast second click could re-enter.
	if spinning or building then return end
	spinning = true
	building = true
	settled = false -- new spin: the settle step has not run yet

	-- rebuild the strip
	for _, ch in ipairs(strip:GetChildren()) do ch:Destroy() end
	resultCard.Visible = false
	resultPetHolder.Visible = false -- the winning CARD is the picture on a crate open
	-- Undo the title-only layout a trade-up reveal leaves behind (it shares this GUI).
	setReelVisible(true)
	reelTitle.Text = "OPENING " .. string.upper(crate.displayName)
	reelTitle.TextColor3 = GOLD

	local pool = SkinCrates.flatContents(crate.id)
	if #pool == 0 then spinning = false; return end
	local winner = pool[result.reelIndex] or { pet = result.pet, skin = result.skin, rarity = result.rarity }

	-- Fill every cell with a random item from the crate EXCEPT the winning slot, which gets the server's item.
	-- The filler is cosmetic only -- it exists to give the eye something to read while the reel decelerates.
	-- NO TWO IDENTICAL CARDS ON SCREEN AT ONCE. Only ~3 cells are visible at this card size, so a plain
	-- random fill showed the same skin twice side by side often enough to look broken -- and it makes the
	-- reel read as a short loop rather than a deep crate.
	--
	-- Deduped on the PET, not on pet+skin. A card is dominated by its 3D pet model, so a Stone Bean Buddy
	-- beside an Emerald Bean Buddy reads as the same card printed twice even though they are different
	-- rewards -- which is exactly what looked broken. Two cards may share a SKIN; they may not share a PET.
	--
	-- `recent` holds the last visible-window's worth of picks plus a margin, so a pet can't reappear the
	-- moment its twin slides out of frame. A colliding pick is re-rolled up to 24 times, then accepted: if a
	-- crate has fewer distinct pets than fit on screen, repeats are unavoidable and a bounded loop is the
	-- only honest answer -- an unbounded one would hang forever on a two-pet crate.
	local windowCells = math.ceil((REEL_PANEL_W - REEL_WINDOW_INSET) / CELL_W) + 2
	local recent = {}
	local cells = {} -- by strip index, for the per-frame focus pass
	-- Identity for the no-two-alike pass. A level crate has no pet, so keying on e.pet alone would make every
	-- cell look identical, empty the eligible set, and drop the reel back to a blind random pick.
	local function keyOf(e)
		if e.levels then return "lvl" .. tostring(e.levels) end
		if e.trait  then return "trt" .. tostring(e.trait)  end
		return tostring(e.pet)
	end
	local function remember(e)
		recent[#recent + 1] = keyOf(e)
		if #recent > windowCells then table.remove(recent, 1) end
	end
	for i = 1, STRIP_LEN do
		local item
		if i == WIN_INDEX then
			item = winner -- never re-rolled: this is the cell the server's roll has to land on
		else
			-- The winner is FORCED, so the cells landing just BEFORE it cannot discover it through `recent` the
			-- way later cells do -- and those are exactly the cells sharing the screen with it when the reel
			-- stops. That hole is what kept the winning pet appearing twice at the payoff moment. Look ahead
			-- instead: inside the run-up, treat the winner's pet as already taken.
			local nearWinner = (i < WIN_INDEX) and (WIN_INDEX - i <= windowCells)
			-- Gather what IS allowed and pick from that, rather than re-rolling and hoping. Blind retries have a
			-- failure tail that scales with how few pets a crate has -- the Mythic pool (8 pets) still doubled on
			-- ~5% of reels at 24 attempts. Building the set costs #pool * windowCells checks per cell (about six
			-- thousand for a whole strip -- nothing) and CANNOT fail while any legal choice exists.
			local eligible = {}
			for _, e in ipairs(pool) do
				local k = keyOf(e)
				local ok = not (nearWinner and k == keyOf(winner))
				if ok then
					for _, r in ipairs(recent) do if r == k then ok = false; break end end
				end
				if ok then eligible[#eligible + 1] = e end
			end
			-- Empty only when the crate has fewer distinct pets than fit on screen, where a repeat is unavoidable.
			item = (#eligible > 0) and eligible[math.random(1, #eligible)] or pool[math.random(1, #pool)]
		end
		remember(item)
		local built = buildCell(strip, (i - 1) * CELL_W, item)
		cells[i] = built
		if i == WIN_INDEX then built.Name = WIN_CELL_NAME end
	end

	building = false -- every cell exists now; re-entry is safe again
	-- Hide the crate panel underneath. Its ScreenGui uses CoreUISafeInsets while this one ignores the inset,
	-- so the two 700x520 panels don't share a footprint on screen -- the crate list's bottom row was poking
	-- out below the reveal. The CLAIM button brings it back.
	gui.Enabled = false
	revealGui.Enabled = true

	-- Where the strip must end up: the winning cell's centre sits under the window's centre.
	--
	-- windowW is the window's LOCAL width, derived from the authored geometry (reelPanel 700 wide, reelWindow
	-- inset 24) -- deliberately NOT reelWindow.AbsoluteSize.X. AbsoluteSize is in post-UIScale screen pixels,
	-- while strip.Position offsets are pre-scale local units, so mixing them would land the reel off-centre on
	-- any device where the HUD scaling pass has applied a UIScale (i.e. every phone and iPad).
	local windowW = REEL_PANEL_W - REEL_WINDOW_INSET
	local targetX = -((WIN_INDEX - 1) * CELL_W + CELL_W / 2) + windowW / 2
	-- a few pixels of jitter so repeat pulls don't stop pixel-identically
	targetX = targetX + math.random(-14, 14)

	strip.Position = UDim2.new(0, windowW, 0, 0) -- start off to the right, so the first cells fly in
	local startX = windowW
	local dist   = targetX - startX -- negative: the strip travels leftward

	-- TICKS: watch which cell is under the marker and click whenever it changes. Because the strip decelerates,
	-- the ticks naturally slow with it -- that audible ramp is most of what makes a case opening feel tense.
	-- PITCH TRACKS SPEED. A flat tick made every part of the spin sound the same; sliding the pitch down as
	-- the reel slows means you HEAR the deceleration, which is most of the tension. Measured from the
	-- strip's actual per-frame travel rather than from the curve, so it stays honest if SPIN_EASE changes.
	local lastCell, lastX = nil, strip.Position.X.Offset
	local tickConn = RunService.RenderStepped:Connect(function()
		local x = strip.Position.X.Offset
		local travel = math.abs(x - lastX)
		lastX = x
		local centreIdx = math.floor((-x + windowW / 2) / CELL_W) + 1
		if centreIdx ~= lastCell then
			lastCell = centreIdx
			-- a whole cell of travel in ONE frame is flat out; the last few ticks crawl in near zero
			local v = math.clamp(travel / CELL_W, 0, 1)
			playSound(TICK_SOUND, 0.20 + v * 0.12, 1.02 + v * 0.68)
			-- ONE TAP PER CELL. The reel already slows into the stop, so the taps space out with it -- the
			-- payoff is felt building, not just watched. Haptics throttles `tick`, so the fast opening blur
			-- cannot turn into a solid hum.
			if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
		end
	end)

	-- CENTRE FOCUS. Cards shrink with distance from the marker, so the one under it is always visibly the
	-- subject and its neighbours read as context. Without this, three identically sized cards give the eye
	-- nothing to lock onto until the reel has already stopped.
	--
	-- Neighbours SHRINK rather than the centre growing: at scale 1 a card is exactly its authored size, so
	-- nothing can ever overflow the window or collide with the reveal band below.
	--
	-- Only the ~5 cells that can be on screen are touched, found by arithmetic rather than by walking all
	-- STRIP_LEN of them -- this runs every frame of the spin.
	local FOCUS_MIN = 0.80

	-- ---- OFFSCREEN VIEWPORTS ARE PARKED --------------------------------------------------------------
	-- A ViewportFrame renders its 3D contents every frame whenever it is Visible. Being scrolled outside a
	-- ClipsDescendants parent does NOT stop that -- the cost is paid for all STRIP_LEN cells even though only
	-- about five can be seen. With 56 cells of 11-53 parts each that is the whole reel re-rendered every
	-- frame, and it is what makes the spin stutter.
	--
	-- So each frame only the cells in the focus window stay live; the rest have their ViewportFrame hidden.
	-- Visible=false is the cheap switch here: it stops the render but keeps the model, so a cell coming back
	-- into view costs nothing to restore -- no rebuild, no re-queue, no flicker.
	--
	-- Toggling is done on the DELTA (cells entering/leaving the window), not by sweeping all 56 -- this runs
	-- every frame of a 6-second spin.
	local vpCache = {}   -- [index] = the cell's ViewportFrame, resolved once
	local liveFirst, liveLast = nil, nil
	local function viewportOf(i)
		local hit = vpCache[i]
		if hit ~= nil then return hit or nil end
		local c = cells[i]
		local vp = c and c:FindFirstChildWhichIsA("ViewportFrame", true)
		vpCache[i] = vp or false -- cache the miss too: a level cell has no viewport at all
		return vp
	end
	local function setLive(i, live)
		local vp = viewportOf(i)
		if vp then vp.Visible = live end
	end

	local function applyFocus()
		local x = strip.Position.X.Offset
		local centre = -x + windowW / 2 -- strip-space X currently under the marker
		local first = math.max(1, math.floor((centre - windowW / 2) / CELL_W))
		local last  = math.min(STRIP_LEN, math.ceil((centre + windowW / 2) / CELL_W) + 1)

		if first ~= liveFirst or last ~= liveLast then
			if liveFirst then -- retire the cells that just left the window
				for i = liveFirst, liveLast do
					if i < first or i > last then setLive(i, false) end
				end
			else              -- first pass: nothing has been shown yet, so park everything off-window
				for i = 1, STRIP_LEN do
					if i < first or i > last then setLive(i, false) end
				end
			end
			for i = first, last do setLive(i, true) end
			liveFirst, liveLast = first, last
		end

		for i = first, last do
			local c = cells[i]
			if c then
				local sc = c:FindFirstChild("Focus")
				if sc then
					-- distance from the marker, measured in CARDS: 0 dead centre, 1 a full card away
					local d = math.abs(((i - 1) * CELL_W + CELL_W / 2) - centre) / CELL_W
					local near = math.clamp(1 - d, 0, 1)
					-- eased, so the centre card holds its size through the middle of the slot instead of
					-- pulsing sharply as the boundary crosses
					sc.Scale = FOCUS_MIN + (1 - FOCUS_MIN) * (near * near * (3 - 2 * near))
				end
			end
		end
	end
	applyFocus() -- correct on the very first frame, before the reel has moved

	-- SKIP wiring: a flag the drive loop polls, so a click drops straight through to the payoff. The strip is
	-- snapped to targetX afterwards either way, so a skipped reveal and a watched one end on the exact same cell.
	local skipped = false
	skipBtn.Visible = true
	local skipConn = skipBtn.MouseButton1Click:Connect(function()
		if skipped then return end
		skipped = true
		playUIClick()
	end)

	-- THE DRIVE LOOP: one curve, stepped per frame, no tween hand-offs. Speed only ever decreases, so the reel
	-- cannot stall and re-accelerate the way the old staged version did at its boundaries.
	local markerPulse
	local t0 = os.clock()
	while not skipped do
		local t = math.clamp((os.clock() - t0) / SPIN_TIME, 0, 1)
		local travelled = 1 - (1 - t) ^ SPIN_EASE
		strip.Position = UDim2.new(0, startX + dist * travelled, 0, 0)
		applyFocus()

		-- Once the winner is within ~2 cells the marker starts breathing -- the UI signalling "this is the
		-- moment", not just the reel. Triggered off the distance remaining rather than a timestamp, so it stays
		-- in sync with the curve if SPIN_EASE is retuned.
		if not markerPulse and math.abs(dist) * (1 - travelled) <= CELL_W * 2 then
			markerPulse = TweenService:Create(marker,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundColor3 = Color3.fromRGB(255, 255, 220), Size = UDim2.new(0, 8, 0, MARKER_H + 8) })
			markerPulse:Play()
		end

		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end

	if markerPulse then
		markerPulse:Cancel()
		marker.BackgroundColor3 = GOLD; marker.Size = UDim2.new(0, 5, 0, MARKER_H) -- back to its authored look
	end

	strip.Position = UDim2.new(0, targetX, 0, 0) -- exact landing, skipped or not
	applyFocus() -- settle the scales on the final position (a SKIP jumps straight here)
	skipConn:Disconnect()
	skipBtn.Visible = false
	tickConn:Disconnect()
	-- The selector has done its job once the reel lands; left up, it painted a gold stripe straight down the
	-- winning card. setReelVisible(true) at the top of the next spin brings both back.
	marker.Visible = false
	markerArrow.Visible = false

	-- ===== the payoff =====
	if settled then return end -- a second entrant would re-apply the win visuals on top of the first
	settled = true
	local isGold = result.isGold == true
	-- THE PAYOFF. Gold gets the five-tap `rare` rhythm; every other pull gets `unlock`. Both outrank
	-- the reel's ticks, so the strip of taps stops dead and the result lands as its own thing.
	if _G.hapticPulse then pcall(_G.hapticPulse, isGold and "rare" or "unlock") end
	local tierCol = PetSkins.tierColor(result.rarity)

	if isGold then
		-- GOLD is the knife pull: its own layered sound and a gold-framed card. The celebration itself is
		-- fired below for EVERY tier, scaled to how good the pull was.
		playSound(GOLD_SOUND or REVEAL_SOUND, 0.9, GOLD_SOUND and 1 or 0.72)
		playSound(REVEAL_SOUND, 0.6, 1.25) -- layered, so it's clearly not a normal reveal
		reelTitle.Text = "\xE2\xAD\x90 GOLD \xE2\xAD\x90"
		-- (no marker pulse here any more: the selector is hidden at the payoff, and that infinite tween
		-- also used to bleed a pale-gold marker colour into the NEXT spin because nothing cancelled it)
	else
		playSound(REVEAL_SOUND, 0.7, 1)
		reelTitle.Text = string.upper(result.rarity) .. "!"
	end
	-- Highlight the card ALREADY holding the winner: a short pop and a heavier tier-coloured border. Purely
	-- visual, and it never touches the ViewportFrame's contents, so it cannot duplicate geometry.
	do
		local won = strip:FindFirstChild(WIN_CELL_NAME)
		if won then
			local st = won:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = tierCol
				TweenService:Create(st, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
					{ Thickness = isGold and 8 or 6 }):Play()
			end
			-- MAKE THE WINNER DOMINANT BY PULLING ITS NEIGHBOURS BACK, not by growing it. Cards are already at
			-- their authored size at scale 1, so any pop would push the winner's bottom edge into the reveal text
			-- (1.08 overshoots it by 17px). Receding the crowd reads stronger anyway -- the winner is left alone
			-- on the strip -- and it cannot overflow anything, because every scale involved only ever goes DOWN.
			-- Hold the rosette for a beat so "...is that the GOLD?" lands, THEN flip the card to the real prize.
			-- Delayed rather than immediate because unmasking on the same frame the reel stops reads as the card
			-- having been the pet all along, and throws away the pause the whole mask exists to create.
			-- checked BEFORE the delays fire: unmaskWinner destroys the plate, so asking again inside the
			-- skin-flip's own delay would see "not masked" and paint a second preview over the unmasked one
			local wasMasked = won:FindFirstChild("MysteryPlate") ~= nil
			task.delay(0.42, function()
				if won.Parent and unmaskWinner(won, result.pet, result.skin, result.trait) then
					playSound(REVEAL_SOUND, 0.55, 1.25)
				end
			end)
			-- SKIN pull: the reel scrolled with bare pet+skin cells (the trait belongs to the PULL, not the
			-- cell -- painting it on every cell would spoil the roll mid-spin). Once the winner is parked,
			-- flip its preview to the full prize -- skin AND trait rendered together -- and name the trait on
			-- the card, same 0.42s beat as the Gold unmask so both flips read as the same reveal.
			if not result.kind and not wasMasked and result.pet and result.skin
				and result.trait and not PetTraits.isNone(result.trait) then
				task.delay(0.42, function()
					if not won.Parent then return end
					local vp = won:FindFirstChildWhichIsA("ViewportFrame", true)
					if vp then vp:Destroy() end
					makePetPreview(won, result.pet, result.skin, result.trait,
						UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
					local pn = won:FindFirstChild("PetName")
					if pn then
						pn.Text = PetSkins.prettyPet(result.pet) .. "  \xE2\x80\xA2  "
							.. PetTraits.displayName(result.trait) .. " Trait"
						pn.TextColor3 = PetTraits.color(result.trait) or pn.TextColor3
					end
					playSound(REVEAL_SOUND, 0.45, 1.35)
				end)
			end
			-- TRAIT pull: the reel's cells all wore the trait on the demo duck; once the reel has landed,
			-- the winning card flips to the ACTUAL ride-along the server granted -- same beat, same 0.42s
			-- pause as the Gold unmask, so the flip reads as a reveal rather than a glitch.
			if result.kind == "trait" and result.pet and result.skin then
				task.delay(0.42, function()
					if not won.Parent then return end
					local vp = won:FindFirstChildWhichIsA("ViewportFrame", true)
					if vp then vp:Destroy() end
					makePetPreview(won, result.pet, result.skin, result.trait,
						UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
					local sn = won:FindFirstChild("SkinName")
					if sn then sn.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet)) end
					local pn = won:FindFirstChild("PetName")
					if pn then pn.Text = PetTraits.displayName(result.trait) .. " TRAIT" end
					playSound(REVEAL_SOUND, 0.55, 1.25)
				end)
			end
			local wonScale = won:FindFirstChild("Focus")
			if wonScale then
				TweenService:Create(wonScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }):Play() -- snap out any residual focus easing so it lands exactly full size
			end
			for _, other in ipairs(strip:GetChildren()) do
				if other ~= won then
					local osc = other:FindFirstChild("Focus")
					-- only the ones actually on screen are worth tweening
					if osc and osc.Scale > 0.01 and math.abs(other.AbsolutePosition.X - won.AbsolutePosition.X) < windowW then
						TweenService:Create(osc, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ Scale = 0.66 }):Play()
					end
				end
			end
		end
	end
	celebrate(result.rarity) -- contained inside reelPanel; see the BURST table
	reelTitle.TextColor3 = tierCol

	-- NO showResultPet HERE. The winning CARD is already parked under the marker showing this exact pet in
	-- this exact skin; rendering it again into the 260x260 holder painted a duplicate directly on top of it.
	-- That holder exists ONLY for trade-ups, which have no reel to show the item. Win visuals go on the card
	-- that is already there -- see the highlight block above.
	-- A LEVEL pull says what it gave and WHERE it went. `grants` is the server's list of which pets actually
	-- took the levels (it spills across pets so none are wasted at the cap), so the player never has to guess.
	if result.kind == "levels" then
		resultName.Text = "+" .. tostring(result.levels) .. (result.levels == 1 and " Pet Level" or " Pet Levels")
	elseif result.kind == "pets" then
		-- The PET is the prize and the band above it is its permanent rarity, so the name is just the species.
		-- Routed before the skin branch because a pet pull carries no skin at all, and displayName(nil, ...)
		-- would have rendered the reveal as a blank.
		resultName.Text = PetSkins.prettyPet(result.pet)
	elseif result.kind == "trait" then
		resultName.Text = PetTraits.displayName(result.trait) .. " Trait"
	else
		resultName.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
	end
	if result.skin and not result.kind then
		-- A skin pull's tier line is the OVERALL TIER -- the one label the pet will wear overhead, computed
		-- from the hidden skin+trait values. The skin's own band already spoke through the reel colour.
		local overall = result.overallTier or PetTier.overall(result.skin, result.trait) or result.rarity
		resultTier.Text = "Tier: " .. tostring(overall)
		resultTier.TextColor3 = PetSkins.tierColor(overall)
	else
		resultTier.Text = result.rarity
		resultTier.TextColor3 = tierCol
	end

	-- One clean line, always the same shape ("Trait: Smoky"), so the eye knows where to look whether or not
	-- the pull had a trait. The old SHOUTED, sparkle-wrapped version changed width on every reveal.
	if result.kind == "levels" then
		-- Nothing has been levelled YET -- these are pending until the picker places them, so this line can no
		-- longer name a pet (the server used to send `grants`; it does not decide any more).
		resultTrait.Text = "Choose which pet gets them"
		resultTrait.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "pets" then
		-- Say the quiet part out loud on the very first pull: the band you just rolled is the ONLY thing about
		-- this pet that will never change. Its size is a separate axis you grow by flying.
		resultTrait.Text = "Rarity is permanent \xE2\x80\x94 it grows from Baby as you play"
		resultTrait.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "trait" then
		-- the trait is the prize; this line names the ride-along it arrived on
		resultTrait.Text = "Comes on: " .. PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
		resultTrait.TextColor3 = PetTraits.color(result.trait) or Color3.fromRGB(150, 255, 170)
	elseif PetTraits.isNone(result.trait) then
		resultTrait.Text = "Trait: None"
		resultTrait.TextColor3 = Color3.fromRGB(180, 190, 205)
	else
		-- The trait NEVER joins the pet's name -- this line is where it lives, styled as the second prize it
		-- is ("Wizard Trait  \xE2\x80\xA2  Epic"), not as metadata small print.
		local tTier = PetTraits.tierOf(result.trait)
		resultTrait.Text = PetTraits.displayName(result.trait) .. " Trait"
			.. (tTier and ("  \xE2\x80\xA2  " .. tTier) or "")
		resultTrait.TextColor3 = PetTraits.color(result.trait)
	end

	if result.kind == "levels" then
		resultNote.Text = "Tap CONTINUE to pick a pet"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "pets" then
		-- A duplicate is progress, not a miss. Naming the stack size is what teaches that, so the second
		-- Broccoli Bunny reads as "2 of 5 toward an Uncommon" instead of "I already had this".
		local n = tonumber(result.count) or 1
		resultNote.Text = (n > 1)
			and string.format("You now have x%d \xE2\x80\x94 fuse duplicates in the Pet Hub", n)
			or "Added to your pets"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "trait" then
		if result.locked then
			resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to wear it"
			resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
		else
			local ov = result.overallTier or PetTier.overall(result.skin, result.trait)
			resultNote.Text = "Ready to Equip!" .. (ov and ("   Tier: " .. tostring(ov)) or "")
			resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
		end
	elseif result.locked then
		-- prettyPet, not the raw id: "Unlock Burrito Armadillo", never "Unlock BurritoArmadillo".
		resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to equip this skin"
		resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
	else
		-- They own the pet, so the useful thing to say is that they can wear it RIGHT NOW. The duplicate
		-- count rides along on the same line instead of taking one of its own.
		resultNote.Text = "Ready to Equip!"
		if (result.newCount or 1) > 1 then
			resultNote.Text = "Ready to Equip!   (you own x" .. result.newCount .. ")"
		end
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	end

	resultCard.Visible = true
	resultCard.Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 14)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, REVEAL_Y) }):Play()

	spinning = false
end


--======================================================================
-- WHERE DO THE LEVELS GO?  (shown AFTER a Pet Level Crate opens)
--======================================================================
-- The crate reveals "+7 Pet Levels", you close it, and THIS comes up: every pet you own, with its current
-- level, and you tap the one you want fed. You are choosing with the number already on screen -- which is the
-- whole reason it moved here from the crate card, where you had to guess before opening.
--
-- IT REOPENS UNTIL THE POOL IS EMPTY. Pick a pet that caps after 3 of your 7 and the other 4 stay pending,
-- so the panel stays up for the next choice -- that is the "select the ones you want it to go to" case.
--
-- NOTHING CAN BE STRANDED. The pool is the server's and it is session-scoped: walk away, close the game, or
-- ignore this panel entirely and the server spills whatever is left across your pets on the way out (equipped
-- first, then lowest level). Skipping is a real choice, not a way to lose levels. That is what makes it safe
-- to hold levels back at all -- the old pet wheel's pending bucket had no such guarantee.
local levelPickGui = Instance.new("ScreenGui")
levelPickGui.Name = "PetLevelPickerGui"; levelPickGui.ResetOnSpawn = false
levelPickGui.DisplayOrder = 210; levelPickGui.Enabled = false; levelPickGui.Parent = PlayerGui

local lpPanel = mkFrame(levelPickGui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL,
})
mkCorner(lpPanel, 22); mkStroke(lpPanel, WHITE, 4)

local lpHead = mkFrame(lpPanel, { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD })
mkCorner(lpHead, 22)
local lpTitle = mkLabel(lpHead, {
	Text = "WHERE DO THE LEVELS GO?", Font = Enum.Font.FredokaOne, TextSize = 28, TextScaled = true,
	TextColor3 = GOLD, Size = UDim2.new(1, -40, 1, -16), Position = UDim2.new(0, 20, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 28; c.MinTextSize = 14; c.Parent = lpTitle end

local lpCount = mkLabel(lpPanel, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = WHITE,
	Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 0, 74),
	TextXAlignment = Enum.TextXAlignment.Left,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.MinTextSize = 12; c.Parent = lpCount end

local lpList = Instance.new("ScrollingFrame")
lpList.Size = UDim2.new(1, -40, 0, 340); lpList.Position = UDim2.new(0, 20, 0, 110)
lpList.BackgroundTransparency = 1; lpList.BorderSizePixel = 0; lpList.ScrollBarThickness = 6
lpList.ScrollBarImageColor3 = GOLD; lpList.CanvasSize = UDim2.new(0, 0, 0, 0); lpList.Parent = lpPanel
do
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = lpList
end

-- SKIP is deliberately present and deliberately safe. A player who does not want to decide should not be
-- trapped in a modal -- the server spills the remainder for them, exactly as it did before this panel existed.
local lpSkip = mkButton(lpPanel, {
	Size = UDim2.new(1, -40, 0, 46), Position = UDim2.new(0, 20, 1, -58),
	BackgroundColor3 = CARD, Text = "", AutoButtonColor = false,
})
mkCorner(lpSkip, 12); mkStroke(lpSkip, WHITE, 2)
mkLabel(lpSkip, {
	Text = "Decide for me", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
	TextColor3 = WHITE, Size = UDim2.fromScale(1, 1),
})

local function lpClose()
	levelPickGui.Enabled = false
	if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyClosed, "PetLevelPicker") end
end

local function lpBuild()
	for _, ch in ipairs(lpList:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	local pending = tonumber(state.pendingLevels) or 0
	lpCount.Text = ("%d level%s to place"):format(pending, pending == 1 and "" or "s")

	local pets = state.levelPets or {}
	local n = 0
	for _, pt in ipairs(pets) do
		n += 1
		local maxed = pt.maxed and true or false
		local row = mkButton(lpList, {
			Size = UDim2.new(1, -10, 0, 56), BackgroundColor3 = maxed and Color3.fromRGB(48, 52, 64) or CARD,
			Text = "", AutoButtonColor = not maxed, LayoutOrder = n,
		})
		mkCorner(row, 12); mkStroke(row, maxed and Color3.fromRGB(80, 86, 102) or GOLD, 2)

		mkLabel(row, {
			Text = tostring(pt.name or pt.petId), Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
			TextColor3 = maxed and Color3.fromRGB(150, 156, 172) or WHITE,
			Size = UDim2.new(0.6, -20, 1, -14), Position = UDim2.new(0, 16, 0, 7),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkLabel(row, {
			-- A maxed pet still LISTS -- greyed and unpickable. Hiding it would read as "that pet is gone";
			-- showing it greyed reads as "that one is finished", which is the true and more useful statement.
			Text = maxed and "MAX" or ("Lv " .. tostring(pt.level or 1)),
			Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true,
			TextColor3 = maxed and Color3.fromRGB(150, 156, 172) or GOLD,
			Size = UDim2.new(0.4, -20, 1, -14), Position = UDim2.new(0.6, 4, 0, 7),
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		if not maxed then
			row.MouseButton1Click:Connect(function()
				playUIClick()
				row.AutoButtonColor = false      -- one tap per row; the state push re-enables it
				task.spawn(function()
					local ok, res = pcall(function() return AssignPetLevels:InvokeServer(pt.petId) end)
					if not (ok and type(res) == "table" and res.ok) then
						lpBuild()                 -- refused (raced to max, etc): redraw off the truth
						return
					end
					if _G.showHudBanner then
						pcall(_G.showHudBanner,
							("%s  Lv %d -> %d"):format(tostring(pt.name or pt.petId), res.from, res.to),
							Color3.fromRGB(150, 255, 170), 3)
					end
					-- Levels left over (the pet capped mid-pour) -> stay open for the next pick.
					if (tonumber(res.remaining) or 0) > 0 then lpBuild() else lpClose() end
				end)
			end)
		end
	end

	if n == 0 then
		mkLabel(lpList, {
			Text = "You don't own any pets yet!", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
			TextColor3 = WHITE, Size = UDim2.new(1, -10, 0, 56), LayoutOrder = 1,
		})
	end
	lpList.CanvasSize = UDim2.new(0, 0, 0, math.max(1, n) * 64 + 8)
end

-- Republished so applyState refreshes the open panel when levels land, a pet hatches, or a trade completes.
levelPickerRefresh = function()
	if levelPickGui.Enabled then lpBuild() end
end

local function lpOpen()
	if (tonumber(state.pendingLevels) or 0) <= 0 then return end
	if _G.MainMenuManager and _G.MainMenuManager.closeAll then pcall(_G.MainMenuManager.closeAll) end
	lpBuild()
	levelPickGui.Enabled = true
	if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, "PetLevelPicker") end
end
_G.openPetLevelPicker = lpOpen

lpSkip.MouseButton1Click:Connect(function() playUIClick(); lpClose() end)
if _G.MainMenuManager then
	pcall(_G.MainMenuManager.register, "PetLevelPicker", function() levelPickGui.Enabled = false end)
end

resultBtn.MouseButton1Click:Connect(function()
	playUIClick()
	revealGui.Enabled = false
	resultCard.Visible = false
	resultPetHolder.Visible = false

	-- A LEVEL PULL HANDS OFF TO THE PICKER instead of dropping you back on the crate list. The levels are
	-- sitting in the server's pending pool at this point and the only thing left to do is say where they go,
	-- so putting the crate panel back up first would be a step the player has to click past.
	if (tonumber(state.pendingLevels) or 0) > 0 then
		lpOpen()
		return
	end

	gui.Enabled = true -- the crate panel was hidden while the reveal covered it; this reveal always starts there
	refreshTabs()
end)

-- ===== PLAY THE REVEAL FOR A CRATE SOMEONE ELSE HANDED OUT =====
-- The Daily Rewards crate is opened SERVER-side (it is free, so there is no client invoke to carry the
-- result back) and then pushed here. Publishing openReveal is what lets that crate use this exact reel,
-- result card and Gold flair instead of growing a second reveal that would have to be kept in step.
-- Takes the crate ID rather than the crate table so the caller needs nothing from SkinCrates.
_G.skinCrateShowReveal = function(crateId, result)
	local crate = SkinCrates.getCrate(crateId)
	if not (crate and type(result) == "table" and result.ok) then return false end
	-- openReveal refuses while a reel is already running, and it does so silently. Report that refusal
	-- rather than returning true for a reveal that never happened -- the caller shows its own fallback
	-- message on false, so the player is told the crate is waiting in the Collection Book.
	if spinning or building then return false end
	-- The reel expects the crate panel to be the thing it is covering; opening from outside means that panel
	-- was never up, so `gui` is closed here and openReveal's own teardown puts it back exactly as a normal
	-- open would -- which is also why the player lands on the crate list afterwards.
	openReveal(crate, result)
	return true
end

-- ===== TRADE-UP RESULT =====
-- A trade-up is a pull too, so it lands on the SAME result card a crate does -- same rarity colour, same trait
-- line, same flair escalation. No second reveal UI to keep in sync, and no risk of the two drifting apart.
-- It skips the reel: there was no crate to scroll through, and the ten items were already reviewed on the
-- confirm screen, so the payoff is the only thing left to show.
showTradeUpResult = function(result)
	if not result or not result.skin then return end
	local tierCol = PetSkins.tierColor(result.rarity)
	local isGold = result.isGold == true
	-- THE PAYOFF. Gold gets the five-tap `rare` rhythm; every other pull gets `unlock`. Both outrank
	-- the reel's ticks, so the strip of taps stops dead and the result lands as its own thing.
	if _G.hapticPulse then pcall(_G.hapticPulse, isGold and "rare" or "unlock") end

	-- reelTitle lives INSIDE reelPanel, so the panel stays up; only the scrolling window is hidden and the
	-- panel collapses to a title-only banner above the card.
	reelPanel.Visible = true
	setReelVisible(false)
	gui.Enabled = false -- same footprint mismatch as the crate reveal: nothing may show around the edges
	revealGui.Enabled = true

	reelTitle.Text = "TRADE UP: " .. string.upper(tostring(result.rarity)) .. "!"
	reelTitle.TextColor3 = tierCol

	showResultPet(result.pet, result.skin, result.trait)
	resultName.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
	do
		local overall = result.overallTier or PetTier.overall(result.skin, result.trait) or result.rarity
		resultTier.Text = "Tier: " .. tostring(overall)
		resultTier.TextColor3 = PetSkins.tierColor(overall)
	end

	-- One clean line, always the same shape ("Trait: King  \xE2\x80\xA2  Epic"), so the eye knows where to
	-- look whether or not the pull had a trait.
	if PetTraits.isNone(result.trait) then
		resultTrait.Text = "Trait: None"
		resultTrait.TextColor3 = Color3.fromRGB(180, 190, 205)
	else
		local tTier = PetTraits.tierOf(result.trait)
		resultTrait.Text = "Trait: " .. PetTraits.displayName(result.trait)
			.. (tTier and ("  \xE2\x80\xA2  " .. tTier) or "")
		resultTrait.TextColor3 = PetTraits.color(result.trait)
	end

	if result.locked then
		resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to equip this skin"
		resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
	else
		resultNote.Text = "Ready to Equip!   (" .. (result.consumed or SkinCrates.TRADE_UP.COST)
			.. " " .. tostring(result.from) .. " traded in)"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	end

	if isGold then
		playSound(GOLD_SOUND or REVEAL_SOUND, 0.9, GOLD_SOUND and 1 or 0.72)
		playSound(REVEAL_SOUND, 0.6, 1.25)
	else
		playSound(REVEAL_SOUND, 0.7, 1)
	end
	-- A contract is a pull too, so it gets the same contained celebration. The panel is collapsed to a
	-- title-only banner here, and reelPanel clips -- so the burst simply plays in the smaller space.
	celebrate(result.rarity)

	resultCard.Visible = true
	resultCard.Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 14)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, REVEAL_Y) }):Play()
end

-- ===== the open request =====
doOpenCrate = function(crate)
	if openRequestInFlight or spinning then return end
	openRequestInFlight = true
	task.spawn(function()
		local ok, result = pcall(function() return OpenCrate:InvokeServer(crate.id) end)
		openRequestInFlight = false
		if not ok or type(result) ~= "table" then
			warn("[SkinCrateClient] open failed: " .. tostring(result))
			return
		end
		if not result.ok then
			-- Every refusal is a real server-side reason; surface it rather than failing silently.
			local msg = ({
				not_enough_tokens = "Not enough Crate Tokens!",
				unknown_crate     = "That crate doesn't exist.",
				empty_crate       = "That crate has no items yet.",
				cooldown          = "Slow down a second!",
				-- The Pet Level Crate refuses BEFORE charging when there is nothing left to level, so say why --
				-- otherwise a maxed-out player just sees the button do nothing and assumes it's broken.
				all_pets_maxed    = "All your pets are max level! Nothing to level up.",
			})[result.reason] or "Couldn't open that crate."
			if _G.showHudBanner then _G.showHudBanner(msg, Color3.fromRGB(255, 150, 90), 3) end
			refreshTabs()
			return
		end
		openReveal(crate, result)
	end)
end

-- ============================================================================================================
-- TRADE BRIDGE
-- ============================================================================================================
-- The trade window lives in PetFollow (it owns the Pet Hub panel), but the SKIN inventory lives here. Rather
-- than give PetFollow a second copy of the skin state to keep in sync, it asks for a snapshot at the moment it
-- draws its "things you can offer" list.
--
-- Keys come back already prefixed with "SKIN:" -- the exact string PetSystem's PetTradeOfferEvent expects -- so
-- the trade window can pass one straight through without knowing anything about how skins are stored.
-- Equip a skin from OUTSIDE this script. The Pet Hub's VIEW MORE card lists a pet's skins and needs to be able
-- to put one on without owning a copy of the remote or re-implementing the rules -- the server still validates
-- ownership and whether the pet is unlocked, exactly as it does for the button in this panel.
-- Pass skinId = false to clear back to the pet's natural look.
_G.skinEquip = function(petId, skinId, traitId)
	if type(petId) ~= "string" then return end
	pcall(function() EquipSkin:FireServer(petId, skinId or false, traitId or false) end)
end

_G.skinTradeList = function()
	local out = {}
	for key, count in pairs(state.skins) do
		local petId, skinId, traitId = PetSkins.parseKey(key)
		local n = math.max(0, math.floor(tonumber(count) or 0))
		if petId and skinId and n > 0 then
			local label = PetSkins.displayName(skinId, PetSkins.prettyPet(petId))
			if not PetTraits.isNone(traitId) then label = label .. " (" .. PetTraits.displayName(traitId) .. ")" end
			out[#out + 1] = {
				key   = PetSkins.TRADE_PREFIX .. key, -- "SKIN:Pet|Skin|Trait"
				name  = label,
				count = n,
				tier  = PetSkins.tierOf(skinId),
				color = PetSkins.tierColor(skinId),
				pet   = petId,
				skin  = skinId,
			}
		end
	end
	-- rarest first, so the valuable things are at the top of the offer list where they're easy to find
	table.sort(out, function(a, b)
		local ra, rb = PetSkins.TierRank[a.tier] or 0, PetSkins.TierRank[b.tier] or 0
		if ra ~= rb then return ra > rb end
		return a.name < b.name
	end)
	return out
end

-- ============================================================================================================
-- COLLECTION REWARDS
-- ============================================================================================================
-- Two kinds of message arrive here:
--   kind = "earned" -> just for you: one or more collections you completed, with what they paid out.
--   kind = "full"   -> server-wide: somebody finished EVERY skin on EVERY pet.
-- Banners are staggered so completing two pets at once (which a trade can do) doesn't overwrite itself.
-- ============================================================================================================
-- COLLECTION REWARD BANNERS
-- ============================================================================================================
-- Completing a collection is how you earn a TITLE ("Bee Keeper" and friends), an aura and an exclusive skin.
-- These used to go out through _G.showHudBanner at REWARD priority, which is the tier meant for NUDGES --
-- "Daily Reward Ready", "Stomach Upgrade Available". At 40 a finished collection queued behind literally
-- every other kind of news and never triggered the milestone haptic, which starts at TUTORIAL.
--
-- Three things this fixes:
--   1. PRIORITY. Your own completion is a TUTORIAL-tier milestone -- exclusive, nothing plays beside it, and
--      it buzzes. Somebody ELSE's completion stays low: it is news about a stranger, not about you.
--   2. THE SILENT FALLBACK. The old code was `if _G.showHudBanner then ... else print(text) end`. CoreClient
--      publishes that global, and if a collection ever completed before CoreClient finished loading the
--      reward went to the OUTPUT WINDOW instead of the screen. This waits for NotifyCenter instead.
--   3. PILE-UP. Multiple notices were fired 3.2s apart while each asked to be shown for 6s, so the queue
--      grew faster than it drained and the last title in a batch arrived long after the crate was closed.
--      Spacing is now taken from the duration, so they play back to back with a clean gap.
local function collectionBanner(text, seconds, mine)
	local NC = _G.NotifyCenter
	if not NC or not NC.push then
		-- NotifyCenter genuinely absent (stale-duplicate eviction mid-boot): retry briefly rather than
		-- dropping a reward the player has earned. Never print-and-forget.
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.25)
				if _G.NotifyCenter and _G.NotifyCenter.push then
					pcall(_G.NotifyCenter.push, {
						text = text, color = Color3.fromRGB(255, 214, 90),
						priority = mine and _G.NotifyCenter.PRIORITY.TUTORIAL or _G.NotifyCenter.PRIORITY.REWARD,
						duration = seconds,
					})
					return
				end
			end
			warn("[SkinCrate] NotifyCenter never arrived -- collection banner lost: " .. tostring(text))
		end)
		return
	end
	pcall(NC.push, {
		text     = text,
		color    = Color3.fromRGB(255, 214, 90),
		priority = mine and NC.PRIORITY.TUTORIAL or NC.PRIORITY.REWARD,
		duration = seconds,
	})
end

CollectAnnounce.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end

	if info.kind == "full" then
		local mine = (info.playerName == player.Name)
		local text = mine
			and "\xF0\x9F\x8F\x86 YOU COMPLETED THE ENTIRE COLLECTION! Title unlocked: " .. tostring(info.title)
			or string.format("\xF0\x9F\x8F\x86 %s completed the ENTIRE collection!", tostring(info.playerName))
		collectionBanner(text, 10, mine)
		return
	end

	if info.kind == "earned" and type(info.notices) == "table" then
		for i, n in ipairs(info.notices) do
			-- 7s apart for a 6s banner: one clean gap between titles instead of a queue that outgrows itself.
			task.delay((i - 1) * 7, function()
				local text
				if n.kind == "full" then
					text = "\xF0\x9F\x8F\x86 FULL COLLECTION COMPLETE! Title: " .. tostring(n.title)
				else
					local bits = {}
					if n.title then bits[#bits + 1] = "Title: " .. n.title end
					if n.aura and PetCollection.AURAS[n.aura] then
						bits[#bits + 1] = PetCollection.AURAS[n.aura].name
					end
					if n.cosmetic then bits[#bits + 1] = PetSkins.displayName(n.cosmetic) .. " skin" end
					text = "\xE2\x9C\x94 " .. tostring(n.petName or n.pet) .. " collection complete! "
						.. table.concat(bits, "  \xE2\x80\xA2  ")
				end
				collectionBanner(text, 6, true)   -- always the player's own reward -> milestone tier
				playSound(REVEAL_SOUND, 0.6, 1.1)
			end)
		end
		refreshTabs()
	end
end)

-- ============================================================================================================
-- GOLD ANNOUNCEMENT (server-wide)
-- ============================================================================================================
-- Server-wide pull news: GOLD (the knife pull) and any LEGENDARY unlock -- a Legendary skin, trait or pet.
-- `tier` on the payload picks the fanfare; the banner names the legendary THING the way a player would say
-- it out loud, because this line is read off the screen mid-flight, not parsed.
GoldAnnounce.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	local mine = (info.playerName == player.Name)
	local isLeg = (info.tier == "Legendary")

	local what
	if info.petRarity then
		-- a Pet Crate pull: the band IS the pet's permanent rarity
		what = "a " .. string.upper(tostring(info.petRarity)) .. " " .. PetSkins.prettyPet(info.pet)
	elseif info.skin then
		-- name only the legendary half (or both) of a skin+trait pull, so the banner says what earned it
		local bits = {}
		if not isLeg or PetSkins.tierOf(info.skin) == "Legendary" then
			bits[#bits + 1] = PetSkins.displayName(info.skin, PetSkins.prettyPet(info.pet))
		end
		if info.trait and (not isLeg or PetTraits.tierOf(info.trait) == "Legendary") and not PetTraits.isNone(info.trait) then
			bits[#bits + 1] = "the " .. PetTraits.displayName(info.trait) .. " Trait"
		end
		if #bits == 0 then bits[1] = PetSkins.displayName(info.skin, PetSkins.prettyPet(info.pet)) end
		what = table.concat(bits, " + ")
	elseif info.trait then
		what = "the " .. PetTraits.displayName(info.trait) .. " Trait"
	else
		what = isLeg and "a LEGENDARY pull" or "a Gold pull"
	end

	local text
	if isLeg then
		text = string.format("\xF0\x9F\x94\xA5 %s unlocked %s from the %s!",
			tostring(info.playerName), what, tostring(info.crateName or "crate"))
	else
		text = string.format("\xE2\xAD\x90 %s pulled %s from the %s!",
			tostring(info.playerName), what, tostring(info.crateName or "crate"))
	end
	if _G.showHudBanner then
		-- Legendary rides its own tier colour so the two kinds of news read apart at a glance
		_G.showHudBanner(text, isLeg and PetSkins.tierColor("Legendary") or Color3.fromRGB(255, 214, 90), 6)
	else
		print("[SkinCrate] " .. text)
	end
	-- The puller already hears their own jackpot sound in the reveal; don't double it up for them.
	if not mine then playSound(REVEAL_SOUND, isLeg and 0.3 or 0.35, 0.8) end
end)

-- ============================================================================================================
-- OPEN / CLOSE
-- ============================================================================================================
_G.MainMenuManager.register("SkinCrates", function() gui.Enabled = false end)

-- fromHub: opened by the Pet Hub's CRATES chip, so the BACK button has somewhere to return to.
local openedFromHub = false

setOpen = function(open, fromHub, wantTab)
	if open then
		openedFromHub = fromHub == true
		-- The hub's nav sends which page it wants (CRATES or TOKENS). Without this the panel always
		-- opened on whatever tab was last used, so pressing TOKENS could land you on Crates.
		if wantTab and tabButtons[wantTab] then activeTab = wantTab end
		backBtn.Visible = openedFromHub
		_G.MainMenuManager.notifyOpened("SkinCrates")
		gui.Enabled = true
		refreshTabs()
		if _G.applyHudScaling then _G.applyHudScaling() end -- match the Shop's on-screen size exactly
		-- Log the RESOLVED on-screen box, the same [UIFix] diagnostic the Shop and Pet Hub print. If the panel
		-- ever appears not to open, this line says whether it was enabled and where it actually landed.
		task.defer(function()
			print(string.format("[SkinCrate] panel OPEN -- tab=%s tokens=%d AbsoluteSize=%s AbsolutePosition=%s",
				activeTab, state.tokens, tostring(panel.AbsoluteSize), tostring(panel.AbsolutePosition)))
		end)
	else
		gui.Enabled = false
		_G.MainMenuManager.notifyClosed("SkinCrates")
		print("[SkinCrate] panel CLOSED")
	end
end

-- The X is the ONLY way to close this panel. The full-screen frame is Active=false on purpose so a click
-- outside falls through to the HUD menu buttons instead of dismissing the menu.
closeBtn.MouseButton1Click:Connect(function() playUIClick(); setOpen(false) end)

-- BACK: close this panel, then reopen the Pet Hub on its main pets view. PetFollow owns a "PetInvToggle"
-- BindableEvent in PlayerGui (the same one the MORE+ Pets row fires) -- and since the CRATES chip closed the hub
-- on the way in, firing the toggle now re-OPENS it. Guarded: with PetFollow absent this just closes the panel.
backBtn.MouseButton1Click:Connect(function()
	playUIClick()
	setOpen(false)
	local ev = PlayerGui:FindFirstChild("PetInvToggle")
	if ev and ev:IsA("BindableEvent") then ev:Fire() end
end)

-- `wantTab` lets the Pet Hub nav open this panel straight onto CRATES or TOKENS. Omitted elsewhere, which
-- keeps the plain toggle behaviour every other caller already relies on.
_G.toggleSkinCrates = function(fromHub, wantTab) setOpen(not gui.Enabled, fromHub, wantTab) end

-- ===== SKIN METADATA, for the Pet Hub's Pet Skins page =====
-- PetFollow draws that page but cannot require PetSkins: it sits at Luau's 200-locals-per-scope ceiling and
-- one more top-level local stops the whole script compiling. Rather than copy the rarity table over there
-- (two copies that can disagree the first time a skin is retuned), this panel -- which already requires the
-- module -- publishes a reader. One source of truth, no extra local on the other side.
_G.petSkinMeta = function(skinId)
	if not skinId or skinId == "" then
		return { name = "Default", tier = "Common", tierColor = Color3.fromRGB(190,198,214), color = Color3.fromRGB(190,198,214) }
	end
	local ok, sk = pcall(function() return PetSkins.get(skinId) end)
	return {
		name      = (ok and sk and sk.displayName) or tostring(skinId),
		tier      = PetSkins.tierOf(skinId) or "Common",
		tierColor = PetSkins.tierColor(skinId) or WHITE,
		color     = (ok and sk and sk.color) or Color3.fromRGB(120,130,145),
	}
end
-- How many skins exist in total, for the page's 'Skins Owned: X / N' readout. +1 for the Default look, which
-- every pet owns from the start and which the page lists as a real card.
_G.petSkinTotal = function() return #PetSkins.Order + 1 end

-- Trait metadata for the same page (name, rarity, a ready-made "King  \xC2\xB7  Epic" label, and the accent
-- colour). Published for the same 200-locals reason as petSkinMeta: PetFollow draws the row but cannot
-- require PetTraits.
_G.petTraitMeta = function(traitId)
	if PetTraits.isNone(traitId) then
		return { name = "None", label = "None", tier = nil, color = Color3.fromRGB(180, 200, 230) }
	end
	local tier = PetTraits.tierOf(traitId)
	local name = PetTraits.displayName(traitId)
	return {
		name  = name,
		tier  = tier,
		label = name .. (tier and ("  \xC2\xB7  " .. tier) or ""),
		color = PetTraits.color(traitId),
	}
end

-- Chat shortcut so the panel can be opened without going through the Pet Hub or the MORE+ list. Type /crates.
-- [REMOVE BEFORE LAUNCH] along with the other dev conveniences.
--
-- TWO paths on purpose: this place uses TextChatService, which does NOT fire Player.Chatted -- that's why the
-- first version of this shortcut did nothing at all. TextChatCommand is the one that actually works here;
-- Player.Chatted is kept for places still on the legacy chat.
local function toggleFromChat()
	print("[SkinCrate] /crates -> toggling panel")
	setOpen(not gui.Enabled)
end

player.Chatted:Connect(function(msg) -- legacy chat path
	local cmd = string.lower((string.gsub(msg, "^%s*(.-)%s*$", "%1")))
	if cmd == "/crates" or cmd == "/skins" then toggleFromChat() end
end)

do -- modern chat path (TextChatService) -- registered client-side so it needs no remote
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "SkinCratesCommand"
		cmd.PrimaryAlias = "/crates"
		cmd.SecondaryAlias = "/skins"
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(toggleFromChat)
	end)
	if not ok then warn("[SkinCrate] TextChatService command registration failed: " .. tostring(err)) end
end

-- ============================================================================================================
-- STATE WIRING
-- ============================================================================================================
SkinStateEvent.OnClientEvent:Connect(applyState)
task.spawn(function()
	local ok, s = pcall(function() return GetSkinState:InvokeServer() end)
	if ok then applyState(s) end
end)

print("[SkinCrateClient] ready -- " .. #SkinCrates.CRATES .. " crates, " ..
	#SkinCrates.TOKEN_PACKS .. " token packs. Open with _G.toggleSkinCrates()")
