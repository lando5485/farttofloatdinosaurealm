--======================================================================
-- SeasonalPetsChest.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE SEASONAL PETS BOX IS RETIRED. Seasonal Pets is now a TAB inside the garden's
-- "Support the Garden" treasure chest panel (GardenDonationClient), so the garden has
-- ONE chest again instead of two near-identical boxes sitting side by side asking the
-- player to remember which was which.
--
-- What is left of this script:
--   1. `_G.openSeasonalPets()` -- the one correct way to open the Seasonal Pets panel.
--      The donation panel's tab calls this. It does NOT rebuild the panel: CoreClient
--      owns it as `LockerGui` and `openLocker()` re-asks the server who owns what
--      first, so a second copy of that grid could never disagree with the server.
--   2. A sweep that DELETES the old world box and its prompt. A box built by an earlier
--      run (or by a stale duplicate of this script baked into the place) would otherwise
--      still be standing in the garden with a working door on it.
--
-- Only things this script itself built are removed -- Models named "SeasonalPetsChest"
-- and prompts named "SeasonalPetsPrompt". A part YOU tagged or named is left alone
-- except for having that prompt stripped off it, so nothing you placed by hand is ever
-- deleted out from under you.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local player            = Players.LocalPlayer
local PlayerGui         = player:WaitForChild("PlayerGui")

--======================================================================
-- OPEN THE PANEL
--
-- Three ways in, most correct first. openLocker() is the real one -- it re-requests
-- ownership from the server and expands the current season before showing the panel, so
-- a player who just earned a pet sees it. Enabling the GUI directly skips that refresh,
-- which is why it is the fallback and not the first choice.
--======================================================================
local function openSeasonalPets()
	if _G.playUIClick then pcall(_G.playUIClick) end

	if type(_G.openLocker) == "function" then
		local ok = pcall(_G.openLocker)
		if ok then return true end
	end
	if _G.MainMenuManager and _G.MainMenuManager.notifyOpened then
		local g = PlayerGui:FindFirstChild("LockerGui")
		if g then
			pcall(_G.MainMenuManager.notifyOpened, "Locker")
			g.Enabled = true
			return true
		end
	end
	local g = PlayerGui:FindFirstChild("LockerGui")
	if g then g.Enabled = true; return true end

	warn("[SeasonalChest] no LockerGui and no _G.openLocker -- the Seasonal Pets panel is not built yet")
	return false
end

-- THE DOOR THE DONATION PANEL'S TAB USES. Published before the sweep below so the tab
-- works on the very first frame the panel can be opened.
_G.openSeasonalPets = openSeasonalPets

--======================================================================
-- REMOVE THE OLD BOX
--
-- Runs on a slow repeat rather than once. The garden itself is built by the server a few
-- seconds after join, and a stale duplicate of the OLD version of this script keeps
-- retrying its build for ~30s -- so a single sweep at startup would delete a box that
-- gets rebuilt two seconds later. Sweeping for 60s outlives that retry loop, then stops.
--======================================================================
task.spawn(function()
	local announced = false

	local function sweep(deep)
		local removed = 0

		-- the box this script used to build: always a direct child of Workspace, so this
		-- half of the sweep is one shallow pass and costs nothing to repeat.
		for _, inst in ipairs(Workspace:GetChildren()) do
			if inst:IsA("Model") and inst.Name == "SeasonalPetsChest" then
				inst:Destroy()
				removed = removed + 1
			end
		end

		-- The door itself, wherever it ended up (a hand-placed box keeps the box, loses the
		-- prompt). This one is a FULL descendant walk of a garden with ~1800 parts in it, so
		-- it only runs on the first few sweeps -- long enough to catch a prompt attached to a
		-- box that streamed in late, short of scanning the whole world every 2s forever.
		if deep then
			for _, inst in ipairs(Workspace:GetDescendants()) do
				if inst:IsA("ProximityPrompt") and inst.Name == "SeasonalPetsPrompt" then
					inst:Destroy()
					removed = removed + 1
				end
			end
		end

		if removed > 0 and not announced then
			announced = true
			print("[SeasonalChest] retired -- removed the old Seasonal Pets box/prompt from the garden. "
				.. "Seasonal Pets is now a TAB inside the Support the Garden chest.")
		end
	end

	for i = 1, 30 do -- 60s at 2s apart: outlasts the old build-retry loop
		sweep(i <= 6)  -- deep prompt walk only for the first ~12s
		task.wait(2)
	end
end)

print("[SeasonalChest] box retired -- Seasonal Pets now opens from the Support the Garden chest (tab)")
