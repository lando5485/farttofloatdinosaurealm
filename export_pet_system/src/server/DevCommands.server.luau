--!nonstrict
-- DevCommands (ServerScriptService/DevCommands)
-- ============================================================================
-- [REMOVE BEFORE LAUNCH]  Developer-only chat commands. This whole script is a
-- dev convenience and MUST be deleted before shipping.
-- ============================================================================
--
-- /crate       -> fires ServerScriptService/DevForceCrate (payload = the chatting Player), which
--                 CrateService handles by running performClaim(player, nil, true): bypasses the 6h
--                 gate, grants pet levels exactly like a real claim, and pushes the result via
--                 CrateResult so the reveal animates without tapping the (hidden) crate button.
-- /resetcrate  -> [TEST USERS ONLY] resets the player's crate timer to ready immediately
--                 (lastCrateClaim = 0) so they can claim again right away. Pushes a fresh snapshot
--                 so the More-menu row / "!" dot flip to READY at once.
-- /rocket      -> [TEST USERS ONLY] starts the Big Rocket event NOW instead of waiting for the
--                 BigEventScheduler to pick it. Runs the real sequence for EVERY player in the
--                 server -- build, boarding hatch, countdown, launch, explosion -- so what you are
--                 testing is the shipped event and not a special path. Refuses while one is already
--                 running rather than stacking a second rocket on the first.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevForceCrate = ServerScriptService:WaitForChild("DevForceCrate", 30)
-- PlayerState is the authority for lastCrateClaim; require returns the cached module instance
-- (same in-memory state CrateService uses), so setLastCrateClaim(player, 0) takes effect live.
local PlayerState = require(ServerScriptService:WaitForChild("PlayerState"))

-- [REMOVE BEFORE LAUNCH] Allowlist for test-only commands (/resetcrate). Add UserIds and/or names.
local TEST_USER_IDS = {
	[1418148401] = true,  -- Broskie310111
}
local TEST_USER_NAMES = {
	["lando5485"] = true,
	["itsmaddmax1"] = true,
	["itsmaddmax2"] = true,
	["broskie310111"] = true,
}
local function isTestUser(player)
	-- names compared lower-cased so capitalisation of the account can't cause a miss
	return TEST_USER_IDS[player.UserId] == true or TEST_USER_NAMES[string.lower(player.Name)] == true
end

-- [REMOVE BEFORE LAUNCH] /testpet's EQUIP PET button: grants the full pet roster (the same _G.petsGrantAll
-- the /allpets chat command uses) so the tester can then equip any species through the ORDINARY
-- PetEquipEvent path and playtest it. Sits BELOW isTestUser on purpose -- declared above it, the closure
-- would compile that name as a nil global. Test users only; everyone else's fire is silently ignored.
do
	local ev = ReplicatedStorage:FindFirstChild("DevTestPetAccess")
	if not ev then
		ev = Instance.new("RemoteEvent"); ev.Name = "DevTestPetAccess"; ev.Parent = ReplicatedStorage
	end
	ev.OnServerEvent:Connect(function(player)
		if not isTestUser(player) then
			warn("[DevCommands] DevTestPetAccess refused: " .. player.Name .. " is not on the test allowlist")
			return
		end
		if _G.petsGrantAll then
			local ok, err = pcall(_G.petsGrantAll, player)
			if ok then print("[DevCommands] DevTestPetAccess -> granted all pets to " .. player.Name .. " (for /testpet)")
			else warn("[DevCommands] DevTestPetAccess grant failed: " .. tostring(err)) end
		else
			warn("[DevCommands] DevTestPetAccess: _G.petsGrantAll not published yet (PetSystem still loading?)")
		end
		-- HANDSHAKE: tell the client the grant has landed, so its equip fires AFTER ownership exists
		-- rather than racing it on a fixed wait.
		ev:FireClient(player)
	end)
end

-- ====================== TEST SKIN COMMANDS - REMOVE BEFORE LAUNCH ======================
-- /default /gold /lava /diamond /galaxy /rainbow : instantly GRANT + EQUIP that gut skin for testing,
-- bypassing the playtime requirement (uses the same _G.grantGutSkin the unlock system uses). Test users only.
local SKIN_CMDS = {
	["/default"] = "Default", ["/gold"] = "Gold", ["/lava"] = "Lava",
	["/diamond"] = "Diamond", ["/galaxy"] = "Galaxy", ["/rainbow"] = "Rainbow",
}
-- ==================== END TEST SKIN COMMANDS ====================

local function onChatted(player, message)
	local cmd = string.lower((string.gsub(message, "^%s*(.-)%s*$", "%1")))
	if cmd == "/crate" then
		if DevForceCrate then
			DevForceCrate:Fire(player)
		end
	elseif cmd == "/resetcrate" then
		-- TEST USERS ONLY: silently ignore for everyone else.
		if not isTestUser(player) then return end
		PlayerState.setLastCrateClaim(player, 0) -- 0 = never claimed -> ready now; pushes snapshot
		print("[DevCommands] /resetcrate: crate timer reset to READY for " .. player.Name)
	-- TEST SKIN COMMANDS - REMOVE BEFORE LAUNCH: /default /gold /lava /diamond /galaxy /rainbow
	elseif SKIN_CMDS[cmd] then
		if not isTestUser(player) then return end
		local skinId = SKIN_CMDS[cmd]
		if _G.grantGutSkin and _G.grantGutSkin(player, skinId, true) then -- grant + equip + apply to the current gut
			print("[DevCommands] " .. cmd .. " -> granted + equipped '" .. skinId .. "' for " .. player.Name)
		end
	-- (/givespins and /forcemythical went with the Pet Wheel. Pet levels come from the Pet Level Crate now,
	--  so /givetokens + /opencrate PetLevels tests that path end to end.)
	-- SKIN CRATE TEST COMMANDS - REMOVE BEFORE LAUNCH -----------------------------------------------------
	-- /givetokens <n>  : credit n Crate Tokens (default 1000) with no Robux purchase.
	-- /opencrate <id>  : force-open a crate (default the first), comping its token price, so the roll + reveal
	--                    can be tested repeatedly. Goes through the SAME openCrate the real button uses -- there
	--                    is no test-only roll path that could behave differently from production.
	-- /goldtest        : keep opening until a GOLD pull lands, to check the jackpot sound / flash / announcement.
	--                    Capped at 5000 opens so a bad streak can't spin forever (0.08% -> expect ~1250).
	elseif string.match(cmd, "^/givetokens") then
		if not isTestUser(player) then return end
		local n = tonumber(string.match(cmd, "^/givetokens%s+(%-?%d+)")) or 1000
		local ev = ServerScriptService:FindFirstChild("DevGiveTokens")
		if ev then ev:Fire(player, n); print("[DevCommands] /givetokens " .. tostring(n) .. " for " .. player.Name) end
	elseif string.match(cmd, "^/opencrate") then
		if not isTestUser(player) then return end
		local id = string.match(message, "^/opencrate%s+(%S+)") -- raw message, not lower-cased: crate ids are case-sensitive
		local ev = ServerScriptService:FindFirstChild("DevOpenCrate")
		if ev then ev:Fire(player, id); print("[DevCommands] /opencrate " .. tostring(id or "(default)") .. " for " .. player.Name) end
	-- /infinitegut : grant the Infinite Gut tier (StomachMax 9999 + a meter that never drains), the same thing the
	--                1860686821 gamepass gives. Forces past FORCE_BASE_STOMACH, the balance-test switch that
	--                otherwise pins every gut to base and makes even a real purchase a no-op.
	elseif cmd == "/infinitegut" or cmd == "/infgut" then
		if not isTestUser(player) then return end
		if _G.devGrantInfiniteGut then
			_G.devGrantInfiniteGut(player)
			print("[DevCommands] /infinitegut for " .. player.Name)
		end
	-- /newlevel : push the EQUIPPED pet into the NEXT TIER (Baby->Kid->Teen->Adult->Elder), i.e. straight to
	--             levels 6 / 11 / 16 / 21. This is the ONE step that fires the tier-up sound, so it tests that
	--             sound (and the new look) in a second instead of grinding five levels of XP. It runs the same
	--             server-side tierSkip the Robux product uses, and can never jump more than one tier per call.
	--             Optional argument: /newlevel <petId> to bump a pet other than the equipped one.
	elseif string.match(cmd, "^/newlevel") or string.match(cmd, "^/nextlevel") then
		if not isTestUser(player) then return end
		if not _G.petTierSkip then
			warn("[DevCommands] /newlevel: PetSystem hasn't published _G.petTierSkip yet")
			return
		end
		-- raw message, not the lower-cased copy: pet ids are case-sensitive ("BroccoliPet")
		local petId = string.match(message, "^/%a+level%s+(%S+)") -- covers /newlevel and the /nextlevel alias
		local lvl, tier = _G.petTierSkip(player, petId)
		if lvl then
			print(string.format("[DevCommands] /newlevel: %s -> Lv %d (%s tier) for %s",
				tostring(petId or "equipped pet"), lvl, tostring(tier), player.Name))
		else
			print("[DevCommands] /newlevel: nothing to skip for " .. player.Name
				.. " (no equipped pet, not owned, or already at the top tier)")
		end
	-- /complete : finish the pet quest on the island you are STANDING ON, exactly as if you had collected every
	--             piece and hatched the egg -- the pet, the rare roll, the hatch tier, the island-task crate
	--             tokens and the on-screen reward moment all fire through the real path.
	--
	--             It calls PetSystem's completeQuest with the anti-cheat gates lifted rather than reimplementing
	--             the hatch here; a second copy of that logic would drift the first time the rewards change.
	--
	--             The tokens are still gated on firstTime, so spamming /complete cannot farm them: the second
	--             run on the same island pays nothing, which is also exactly what it does for a real player.
	--             Optional argument: /complete <petId> to force a specific quest from anywhere.
	elseif string.match(cmd, "^/complete") then
		if not isTestUser(player) then return end
		if not (_G.petForceCompleteQuest and _G.petQuestIslandUnder) then
			warn("[DevCommands] /complete: PetSystem hasn't published its quest hooks yet -- try again in a second")
			return
		end
		-- raw message, not the lower-cased copy: pet ids are case-sensitive ("BroccoliPet")
		local petId = string.match(message, "^/complete%s+(%S+)")
		local island
		if not petId then
			local why
			petId, island, why = _G.petQuestIslandUnder(player)
			if not petId then
				print(("[DevCommands] /complete: %s -- %s. Stand on island 2, 5, 8, 10 or 13, or type /complete <petId>.")
					:format(player.Name, tostring(why)))
				return
			end
		end
		if _G.petForceCompleteQuest(player, petId) then
			print(("[DevCommands] /complete: %s finished %s%s"):format(
				player.Name, petId, island and (" on island " .. island) or ""))
		else
			-- Almost always "you already own this species" -- completeQuest refuses that for dev and player
			-- alike, because granting a duplicate would put a second copy in the inventory.
			print(("[DevCommands] /complete: nothing done for %s on %s (already own it, or unknown pet id)")
				:format(player.Name, petId))
		end
	-- /unlockall : grant every skin on every pet + one of each trait. ~230 inventory entries, so the panel takes
	--              a beat to build the first time you open INVENTORY after running it.
	elseif cmd == "/unlockall" or cmd == "/unlockallskins" then
		if not isTestUser(player) then return end
		local ev = ServerScriptService:FindFirstChild("DevUnlockAllSkins")
		if ev then ev:Fire(player); print("[DevCommands] /unlockall for " .. player.Name) end
	elseif cmd == "/goldtest" then
		if not isTestUser(player) then return end
		local ev = ServerScriptService:FindFirstChild("DevOpenCrate")
		if not ev then return end
		print("[DevCommands] /goldtest: opening until a Gold pull (max 5000) for " .. player.Name)
		task.spawn(function()
			for i = 1, 5000 do
				ev:Fire(player, nil, true) -- quiet: don't print 5000 lines
				if _G.skinLastPullWasGold and _G.skinLastPullWasGold(player) then
					print("[DevCommands] /goldtest: GOLD after " .. i .. " opens"); return
				end
				if i % 100 == 0 then task.wait() end -- yield periodically so the server stays responsive
			end
			print("[DevCommands] /goldtest: no Gold in 5000 opens")
		end)
	-- END SKIN CRATE TEST COMMANDS ------------------------------------------------------------------------
	-- /rocket : fire the Big Rocket event on demand.
	elseif cmd == "/rocket" then
		if not isTestUser(player) then return end
		-- RocketEventManager publishes { start, isRunning } here; it does not exist until that script has
		-- run, and it is the SAME entry point the scheduler uses -- so this cannot drift into being a
		-- second, subtly-different launch path.
		local r = _G.BigEvents and _G.BigEvents.rocket
		if not (r and type(r.start) == "function") then
			warn("[DevCommands] /rocket: the rocket event is not registered yet (RocketEventManager still loading?)")
			return
		end
		if type(r.isRunning) == "function" and r.isRunning() then
			-- The event builds ONE rocket model at ONE site; a second start would have the two sequences
			-- fighting over it. startEvent() guards this too -- this is just so the tester gets told.
			warn("[DevCommands] /rocket ignored: a rocket event is already running")
			return
		end
		print("[DevCommands] /rocket: starting the Big Rocket event for " .. player.Name)
		r.start()
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		onChatted(player, msg)
	end)
end)
-- Players already present when this script starts.
for _, p in ipairs(Players:GetPlayers()) do
	p.Chatted:Connect(function(msg)
		onChatted(p, msg)
	end)
end

-- The modern chat (TextChatService) does NOT fire Player.Chatted, so EVERY command above is dead on a place
-- using it -- which is why /givetokens silently did nothing. Register real slash commands as well, exactly the
-- way RealmPortals.server.lua already does for /unlock. Harmless on the legacy chat (these simply never trigger
-- there, and the Player.Chatted path above covers that case).
--
-- One TextChatCommand per alias pair; Triggered hands us the full typed text, so it routes straight into the
-- SAME onChatted used by the legacy path -- no second implementation to drift.
do
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local function register(name, primary, secondary)
			local cmd = Instance.new("TextChatCommand")
			cmd.Name = name
			cmd.PrimaryAlias = primary
			if secondary then cmd.SecondaryAlias = secondary end
			cmd.Parent = TextChatService
			cmd.Triggered:Connect(function(source, unfilteredText)
				local plr = source and Players:GetPlayerByUserId(source.UserId)
				if plr then onChatted(plr, unfilteredText) end
			end)
		end
		register("DevCrateCommand",      "/crate",      "/resetcrate")
		register("DevGiveTokensCommand", "/givetokens", "/opencrate")
		register("DevGoldTestCommand",   "/goldtest",   "/unlockall")
		register("DevInfiniteGutCommand", "/infinitegut", "/infgut")
		register("DevNewLevelCommand",   "/newlevel",    "/nextlevel") -- pet TIER skip (fires the tier-up sound)
		register("DevCompleteCommand",   "/complete",    "/finishquest") -- finish the quest on the island you are on
	end)
	if ok then print("[DevCommands] slash commands registered with TextChatService (/crate /resetcrate /givetokens /opencrate /goldtest /unlockall /infinitegut /newlevel /complete)")
	else warn("[DevCommands] TextChatService command registration failed: " .. tostring(err)) end
end
