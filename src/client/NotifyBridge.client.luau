--======================================================================
-- NotifyBridge.client.luau  (LocalScript)
--======================================================================
-- Publishes the realm's banner system the way the first realm does it:
--   _G.NotifyCenter   = the ONE owner of every top-centre banner (NotifyCenter.luau, a module beside this)
--   _G.showHudBanner  = one line that hands a message to it (the first realm's CoreClient ~927, verbatim in spirit)
--
-- Before this the Dino Realm had no banner system at all. The only _G.showHudBanner was TestPetPreview's
-- fallback -- a 460x44 test-tool strip at y150 -- so the Rewards hub, gifts, skin crates, the season pass and
-- pet skins all spoke through a debugging panel's banner. Assigned unconditionally so the real one wins even if
-- that fallback loaded first (the fallback is guarded `if not _G.showHudBanner`, so if we load first it never
-- builds at all).
--======================================================================

local ok, Notify = pcall(function()
	return require(script.Parent:WaitForChild("NotifyCenter", 15))
end)
if not (ok and Notify) then
	warn("[NotifyBridge] NotifyCenter module unavailable -- banners stay silent: " .. tostring(Notify))
	return
end

_G.NotifyCenter = Notify

-- The first realm's showHudBanner: a REWARD-priority card (below arrivals, events and purchases), default
-- green, 4s hold.
local function showHudBanner(text, color, holdSeconds)
	Notify.push({
		text     = tostring(text),
		color    = (typeof(color) == "Color3") and color or Color3.fromRGB(40, 160, 90),
		priority = Notify.PRIORITY.REWARD,
		duration = tonumber(holdSeconds) or 4,
	})
end
_G.showHudBanner = showHudBanner

-- HOLD THE CLAIM for a few seconds: a script that published its own fallback just after us would otherwise
-- win the race and route every banner back to itself.
task.spawn(function()
	for _ = 1, 10 do
		task.wait(1)
		if _G.showHudBanner ~= showHudBanner then _G.showHudBanner = showHudBanner end
		if _G.NotifyCenter ~= Notify then _G.NotifyCenter = Notify end
	end
end)

print("[NotifyBridge] banners ready -- _G.NotifyCenter + _G.showHudBanner (first-realm 500x65 hero card, one at a time)")
