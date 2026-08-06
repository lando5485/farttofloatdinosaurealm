--[[
	PhoneHUD.luau  (ReplicatedStorage.PhoneHUD)

	Shared CLIENT phone-layout helpers. Single source of truth for:
	  * isPhone()    — capability-based phone detection (matches ResponsiveUI; MouseEnabled is NOT tested because
	                   real iPhones report it true).
	  * the "banner spot" — the ONE top-centre location every transient banner + event countdown/info pill (server
	    events, cosmic race climb pill, planet arrival, friend-promo, etc.) is snapped into, so they're consistent
	    AND never overlap the persistent "Planet: <name> / objective" pill above them. On phones/tablets the pill
	    grows to hold the objective (top y16 + 66 height = bottom y82 at reference scale), so the banner spot sits at
	    y110 — BELOW that pill with a clear gap. ResponsiveUI scales each element's SIZE about its top anchor (offsets
	    don't move), so the pill's rendered bottom shrinks on phones (bigger gap) and grows on large tablets; y110
	    keeps clear air across the realistic range (phones ~0.6x → ~54px gap; iPad-Pro-class ~1.24x → ~12px gap).
	    The generic ResponsiveUI UIScale + safe-area then scales/positions these banners exactly like the rest of the
	    HUD — no banner has its own sizing/positioning.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer -- client-only module; used to read ResponsiveUI's published live scale

local PhoneHUD = {}

PhoneHUD.BANNER_ANCHOR = Vector2.new(0.5, 0)
PhoneHUD.BANNER_OFFSCREEN = UDim2.new(0.5, 0, 0, -90) -- off the top edge, for slide-in banners
PhoneHUD.BANNER_SIZE = UDim2.new(0, 300, 0, 80)

-- The persistent "Planet: <name> / objective" pill (HUD.client) sits at the top centre: its TOP is a fixed y16 and
-- on phones/tablets it grows to hold the objective (authored height 66). ResponsiveUI scales each element's SIZE
-- about its top anchor but NOT its position offset, so the pill's RENDERED bottom = 16 + 66*scale (scale-dependent).
-- The shared banner spot therefore sits a TIGHT, SCALED gap below that: bannerY = 16 + (66 + GAP)*scale. The gap is
-- defined in SCALED terms (BANNER_GAP reference px × the live global UIScale), so it stays a few px / proportional
-- on every device — never overlapping the pill, never drifting. (Desktop isn't scaled and keeps its own spot below.)
local PILL_TOP = 16
local PILL_H_PHONE = 66
local BANNER_GAP = 8 -- reference px between the pill's bottom and the banner; multiplied by the live UIScale

-- DESKTOP banner spot: the same top-centre location, sitting BELOW the desktop HUD strip (slim Planet title + the
-- RaceBoard leaderboard). Desktop is NOT scaled by ResponsiveUI, so it keeps a fixed authored offset.
PhoneHUD.BANNER_POS_DESKTOP = UDim2.new(0.5, 0, 0, 180)
PhoneHUD.BANNER_OFFSCREEN_DESKTOP = UDim2.new(0.5, 0, 0, 140) -- just above the rest spot, for slide-in banners

function PhoneHUD.isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The LIVE global UIScale ResponsiveUI publishes (recomputed on every viewport/rotation change). Defaults to 1 if
-- not set yet (pre-settle) — which only ever makes the gap LARGER, never overlapping.
function PhoneHUD.uiScale(): number
	local s = localPlayer and localPlayer:GetAttribute("ResponsiveScale")
	return (typeof(s) == "number" and s > 0) and s or 1
end

-- The shared banner spot's RESTING (on-screen) position for THIS device — every banner + every event pill use this
-- so they ALL sit at the ONE designated spot: a tight SCALED gap just below the Planet/objective pill. Re-read it at
-- SHOW time so it always uses the current device's live scale (the gap stays proportional + clear on any screen).
function PhoneHUD.bannerOn(): UDim2
	if PhoneHUD.isPhone() then
		return UDim2.new(0.5, 0, 0, PILL_TOP + (PILL_H_PHONE + BANNER_GAP) * PhoneHUD.uiScale())
	end
	return PhoneHUD.BANNER_POS_DESKTOP
end

-- The shared banner spot's OFF-SCREEN (slide-start) position for THIS device.
function PhoneHUD.bannerOff(): UDim2
	return PhoneHUD.isPhone() and PhoneHUD.BANNER_OFFSCREEN or PhoneHUD.BANNER_OFFSCREEN_DESKTOP
end

local logged = false

-- On phones, snap a banner frame into the shared top-centre banner spot (tight scaled gap below the Planet pill) +
-- size. Widens any UISizeConstraint that would clamp the new 80px height. Returns true if applied (i.e. on a phone).
-- Callers should re-run this (or set frame.Position = PhoneHUD.bannerOn()) when SHOWING the banner so it uses the
-- live scale. One-shot log.
function PhoneHUD.placeBanner(frame: GuiObject): boolean
	if not PhoneHUD.isPhone() then
		return false
	end
	frame.AnchorPoint = PhoneHUD.BANNER_ANCHOR
	frame.Position = PhoneHUD.bannerOn()
	frame.Size = PhoneHUD.BANNER_SIZE
	local sc = frame:FindFirstChildOfClass("UISizeConstraint")
	if sc then
		sc.MaxSize = Vector2.new(math.max(sc.MaxSize.X, 300), math.max(sc.MaxSize.Y, 80))
	end
	if not logged then
		logged = true
		print("[UIScale] PHONE event/welcome/arrival banners moved to race board spot + matched size")
	end
	return true
end

return PhoneHUD
