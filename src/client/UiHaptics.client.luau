--======================================================================
-- UiHaptics.client.luau   (StarterPlayerScripts)
--======================================================================
-- EVERY BUTTON IN THE GAME TICKS. One 8ms tap the moment a button is pressed -- the thing that makes an
-- interface feel like it is made of real switches instead of pictures of switches. It is the cheapest
-- interactivity win available and it applies to menus nobody has written yet.
--
-- ===== WHY A SWEEP AND NOT A LINE IN EVERY MENU =====
-- There are ~40 GUI scripts in this realm and more arrive every week. Wiring each by hand would miss most
-- of them immediately and all of the new ones forever. This adopts every GuiButton under PlayerGui and
-- keeps adopting them via DescendantAdded, so a menu written next month ticks without anybody remembering.
--
-- ===== PRESS, NOT RELEASE =====
-- MouseButton1Down, not Activated. A real button gives way under the finger on the way DOWN; a tick on
-- release feels like a delayed echo. This is the same reason Haptics fires its curves synchronously.
--
-- ===== WHAT IS DELIBERATELY SKIPPED =====
--   * Full-screen backdrops. Several menus put an invisible screen-sized TextButton behind the panel to
--     catch stray taps (see MenuBackdropGuard). Buzzing when the player taps empty space is noise, and in
--     this game those taps are explicitly meant to do NOTHING -- menus only close on their X.
--   * Anything with the NoHaptic attribute, for opting a specific control out by hand.
--   * Buttons that already fire their own richer pulse still tick first, and that is fine: `tick` is rank 1,
--     so the moment the real pulse (purchase/unlock/fail) starts it takes the motor and the tick is gone.
--     The alternative -- maintaining a list of every button that has its own haptic -- rots instantly.
--======================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")

-- A screen-sized button is a backdrop, not a control. Measured against the actual viewport rather than a
-- fixed number so it behaves on a phone and a 4K monitor alike.
local BACKDROP_FRAC = 0.8

local function isBackdrop(b: GuiButton): boolean
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then return false end
	local s = b.AbsoluteSize
	return (s.X >= vp.X * BACKDROP_FRAC) and (s.Y >= vp.Y * BACKDROP_FRAC)
end

local seen = setmetatable({}, { __mode = "k" })   -- weak: a destroyed button must not be pinned in memory

local function adopt(b)
	if not b:IsA("GuiButton") or seen[b] then return end
	seen[b] = true
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("NoHaptic") then return end
		if isBackdrop(b) then return end          -- checked at press time: AbsoluteSize is 0 before layout
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
	end)
end

for _, d in ipairs(gui:GetDescendants()) do adopt(d) end
gui.DescendantAdded:Connect(adopt)

--======================================================================
-- The one non-button case worth having: closing a menu with Escape/B feels like a button press too.
--======================================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
	end
end)

print("[UiHaptics] ready -- every GuiButton under PlayerGui ticks on press (backdrops and NoHaptic skipped)")
