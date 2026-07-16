--[[
	ResponsiveUI.client.luau  (StarterPlayer > StarterPlayerScripts > ResponsiveUI)

	DROP-IN RESPONSIVE HUD SCALER for the Dino Realm (or any place). Realm-AGNOSTIC core lifted from the
	Fart-to-Float / Space-Realm HUD scaler, with the Space-specific element repositioning removed — this
	version scales ANY HUD generically, so it works with whatever GUIs the Dino Realm already has.

	WHAT IT DOES
	  * PHONE-ONLY: on desktop/laptop/Studio-non-emulated it does NOTHING (your authored layout is untouched).
	  * On a real phone / tablet / iPad (and the Studio Device emulator), it fits the HUD to the screen with a
	    single GLOBAL UIScale applied to every managed GUI element, so the whole HUD grows/shrinks as ONE unit
	    (squares stay square, text scales to fit) — no per-device re-tuning.
	  * Flips each HUD ScreenGui to ScreenInsets = DeviceSafeInsets so top elements clear the notch / Dynamic
	    Island and bottom elements clear the home-bar.
	  * Re-runs on rotation / window resize / camera change.

	DETECTION is capability-based (NOT pixel size):
	    PHONE  == TouchEnabled AND not KeyboardEnabled
	    DESKTOP == anything else (a touchscreen laptop has a keyboard, so it's DESKTOP).
	  We do NOT test MouseEnabled (real iPhones/iPads report a virtual mouse) and do NOT test viewport width
	  (high-res phones report big pixel viewports). Touch + no-keyboard is the robust phone check.

	INSTALL
	  Put this file at StarterPlayer > StarterPlayerScripts > ResponsiveUI (a LocalScript). With Rojo, register
	  it in default.project.json under StarterPlayerScripts exactly like your other client scripts.

	OPT OUT per element or ScreenGui: set the attribute  NoResponsiveScale = true.
	EXTRA per-element shrink (optional): set attribute  ResponsiveExtraShrink = <number>  (e.g. 0.85).

	TUNE the feel in the TUNABLES block below (reference resolution + clamp). Reference is iPhone SE/8 landscape;
	bigger screens (iPad) scale UP from there, smaller scale DOWN, all keeping the identical layout.
]]

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== TUNABLES =====
-- The whole HUD scales as ONE unit from a phone REFERENCE resolution:
--     ratio = clamp( min(viewport.X/REF_W, viewport.Y/REF_H), RATIO_MIN, deviceMax )   -- deviceMax is per-class
local REF_W, REF_H       = 1100, 590   -- reference viewport (iPhone SE/8 landscape-ish); phones bind ~1.0, bigger scale up
local RATIO_MIN          = 0.55        -- floor
local PHONE_MAX          = 0.60        -- phone-class cap (keeps HUD clear of the joystick / jump button)
local TABLET_MAX         = 2.5         -- tablet / iPad cap (effectively uncapped so big screens keep their computed scale)
local TABLET_SHORT_AXIS  = 800         -- viewport short-axis (min(X,Y)) >= this  ⇒  tablet-class
local FULLSCREEN_EPS     = 0.95        -- Size.Scale >= this on BOTH axes ⇒ a full-screen cover (don't scale; recurse into it)

local SCALE_TAG    = "ResponsiveScaleApplied" -- idempotency marker
local OPT_OUT      = "NoResponsiveScale"       -- set true on any element/ScreenGui to skip it
local EXTRA_SHRINK = "ResponsiveExtraShrink"   -- optional per-element multiplier on top of the global scale

-- ===== PHONE DETECTION (capability-based; NO pixel-size test) =====
local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ===== SCALE MATH =====
local managed: { UIScale } = {}

local function deviceMax(vp: Vector2): number
	return (math.min(vp.X, vp.Y) >= TABLET_SHORT_AXIS) and TABLET_MAX or PHONE_MAX
end

local function globalRatio(vp: Vector2): number
	return math.clamp(math.min(vp.X / REF_W, vp.Y / REF_H), RATIO_MIN, deviceMax(vp))
end

local function viewport(): Vector2
	return (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(REF_W, REF_H)
end

local function currentScale(): number
	local vp = viewport()
	if vp.X <= 1 or vp.Y <= 1 then
		return PHONE_MAX -- viewport not valid yet (boot reports 1x1) → safe default; a recompute fixes it
	end
	return globalRatio(vp)
end

local function logScale()
	local vp = viewport()
	local raw = (vp.X > 1 and vp.Y > 1) and math.min(vp.X / REF_W, vp.Y / REF_H) or 1.0
	local maxUsed = deviceMax(vp)
	print(("[UIScale] calib → ref=%dx%d, viewport=%dx%d, computed=%.3f, clampMax=%.2f, final=%.3f"):format(
		REF_W, REF_H, math.floor(vp.X), math.floor(vp.Y), raw, maxUsed, math.clamp(raw, RATIO_MIN, maxUsed)))
end

local function isFullScreen(obj: Instance): boolean
	if not obj:IsA("GuiObject") then return false end
	local sz = obj.Size
	return sz.X.Scale >= FULLSCREEN_EPS and sz.Y.Scale >= FULLSCREEN_EPS
end

local function attachScale(obj: GuiObject, scale: number)
	if obj:GetAttribute(SCALE_TAG) or obj:GetAttribute(OPT_OUT) then return end
	if obj:FindFirstChildWhichIsA("UIScale") then return end -- respect a hand-authored UIScale (pop-ins etc.)
	local us = Instance.new("UIScale")
	us.Scale = scale * (obj:GetAttribute(EXTRA_SHRINK) or 1)
	us.Parent = obj
	obj:SetAttribute(SCALE_TAG, true)
	table.insert(managed, us)
end

-- Non-full-screen element → scale it directly (descendants ride the UIScale). Full-screen cover → keep it
-- covering, recurse into its children so nested backdrops/stages get scaled at their real content size.
local function applyResponsive(obj: Instance, scale: number)
	if not obj:IsA("GuiObject") or obj:GetAttribute(OPT_OUT) then return end
	if isFullScreen(obj) then
		for _, child in ipairs(obj:GetChildren()) do applyResponsive(child, scale) end
	else
		attachScale(obj, scale)
	end
end

local function refreshAll()
	local s = currentScale()
	for i = #managed, 1, -1 do
		local us = managed[i]
		if us.Parent then
			us.Scale = s * (us.Parent:GetAttribute(EXTRA_SHRINK) or 1)
		else
			table.remove(managed, i) -- prune UIScales whose element (closed popup) was destroyed
		end
	end
end

-- ===== SAFE AREA (phones) =====
local function applySafeInsets(sg: ScreenGui)
	pcall(function() sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
end

-- ===== EXECUTION GATE — desktop touches NOTHING =====
local touch    = UserInputService.TouchEnabled
local mouse    = UserInputService.MouseEnabled
local keyboard = UserInputService.KeyboardEnabled

if not isPhone() then
	local vp = viewport()
	print(("[UIScale] layout decision — branch=DESKTOP, Touch=%s, Mouse=%s, Keyboard=%s, viewport=%dx%d")
		:format(tostring(touch), tostring(mouse), tostring(keyboard), math.floor(vp.X), math.floor(vp.Y)))
	return -- DESKTOP / laptop / Studio non-emulated → leave the HUD exactly as authored
end

-- PHONE: wait for a VALID viewport (boot reports 1x1 for a frame or two; scaling then would collapse the HUD).
do
	local waited = 0
	while (viewport().X <= 1 or viewport().Y <= 1) and waited < 3 do
		waited += RunService.RenderStepped:Wait()
	end
end

local vpUsed = viewport()
print(("[UIScale] layout decision — branch=PHONE, Touch=%s, Mouse=%s, Keyboard=%s, viewport=%dx%d")
	:format(tostring(touch), tostring(mouse), tostring(keyboard), math.floor(vpUsed.X), math.floor(vpUsed.Y)))

local function publishScale()
	local vp = viewport()
	player:SetAttribute("ResponsiveRefW", REF_W)
	player:SetAttribute("ResponsiveRefH", REF_H)
	player:SetAttribute("ResponsiveScale", currentScale())
	player:SetAttribute("ResponsiveViewportW", math.floor(vp.X))
	player:SetAttribute("ResponsiveViewportH", math.floor(vp.Y))
	player:SetAttribute("ResponsiveClampMax", deviceMax(vp))
	player:SetAttribute("ResponsiveBranchRan", true)
end
publishScale()
logScale()

-- ===== SCREENGUI DISCOVERY (current + future) =====
local processed = setmetatable({}, { __mode = "k" })
-- NEVER touch Roblox-provided GUIs (mobile movement joystick + jump button live in TouchGui).
local ROBLOX_GUIS = { TouchGui = true, ControlGui = true, RobloxGui = true }

local function hookScreenGui(sg: Instance)
	if not sg:IsA("ScreenGui") or processed[sg] or sg:GetAttribute(OPT_OUT) then return end
	if ROBLOX_GUIS[sg.Name] then
		processed[sg] = true
		print(("[Mobile] left Roblox control GUI '%s' untouched (joystick + jump stay default)"):format(sg.Name))
		return
	end
	processed[sg] = true
	applySafeInsets(sg)
	for _, child in ipairs(sg:GetChildren()) do
		applyResponsive(child, currentScale())
	end
	-- Popups/banners add their root later; defer one step so a synchronously-built panel exists before we scan.
	sg.ChildAdded:Connect(function(child)
		task.defer(function() applyResponsive(child, currentScale()) end)
	end)
end

local lastLoggedW, lastLoggedH = -1, -1
local function recompute()
	refreshAll()
	publishScale()
	local vp = viewport()
	local w, h = math.floor(vp.X), math.floor(vp.Y)
	if w ~= lastLoggedW or h ~= lastLoggedH then
		lastLoggedW, lastLoggedH = w, h
		logScale()
	end
end

local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(recompute) end
end
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(); recompute()
end)
pcall(function() GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(recompute) end)

PlayerGui.ChildAdded:Connect(function(sg)
	task.defer(function() hookScreenGui(sg) end)
end)
for _, sg in ipairs(PlayerGui:GetChildren()) do
	hookScreenGui(sg)
end

-- Belt-and-suspenders settle passes in case a ViewportSize change never fires after the wait.
task.defer(refreshAll)
task.delay(0.3, refreshAll)

print("[UIScale] PHONE branch — global responsive scale + device safe-area insets applied to all HUD ScreenGuis.")
