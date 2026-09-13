--======================================================================
-- PetXPHooks.server.luau  (Server Script)
--======================================================================
-- THE MISSING HALF OF THE PET UPGRADE SYSTEM.
--
-- PetUpgrades.server.luau defines four XP hooks and levels the equipped pet 1..25
-- from them. But it only ever DEFINES them -- something else has to CALL them, and in
-- this game nothing did:
--
--     _G.petOnGas        eating food          -> called (Shop.server.luau:175)   OK
--     _G.petOnFlightTick flying               -> NEVER CALLED                    <- dead
--     _G.petOnCoins      coins earned         -> NEVER CALLED                    <- dead
--     _G.petOnIsland     reaching a new island-> NEVER CALLED                    <- dead
--
-- So pets only gained XP from eating, and FLYING -- the main source, and the whole
-- point of the track -- awarded nothing. That is why the pet system "wasn't working".
--
-- In the original game these calls lived in PlayerStats.server.lua, a file that does
-- not exist here; the pet system was ported across without its call sites. This script
-- is that missing layer.
--
-- It is deliberately SERVER-SIDE and inferred from replicated state (FloorMaterial,
-- leaderstats, position) rather than trusting a client remote. Pet levels are purely
-- cosmetic, so this isn't security-critical -- but a client that can spam "I flew!" to
-- max its pet instantly would make the whole track meaningless.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 0.23 = 0.5 x 0.455. FLIGHT XP IS PAID PER TICK, SO IT IS PAID PER SECOND -- and flights
-- are now 2.2x shorter in wall-clock than they were before the tower was compressed and
-- FLIGHT_SECONDS came down with it. Left at 0.5 a pet would earn less than half the XP per
-- crossing it was tuned for, and the whole 1..25 level track would stretch out by the same
-- factor. Ticking faster restores XP PER CROSSING, which is the quantity that was designed;
-- XP per second was only ever a proxy for it.
--
-- The coin-delta branch below is unaffected either way -- it pays on a DELTA, so the tick
-- rate changes only how finely it samples.
local TICK        = 0.23 -- was 0.5; XP per crossing preserved, XP/sec is now ~26
local TOP_ISLAND  = 13

-- Per-player bookkeeping
local lastCoins   = {} -- [player] = last seen leaderstats.Coins value
local topIsland   = {} -- [player] = highest island MODEL number reached this session
local topSlot     = {} -- [player] = highest tower SLOT (climb position) reached this session

-- Shared tower order (island number <-> slot). HighestSlot (below) is the clean climb-progress signal the
-- Wormhole gates on -- HighestIsland alone can't be, since the tower scrambles model numbers vs climb order.
local IslandOrder = require(game:GetService("ReplicatedStorage"):WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))
local ISLAND_TO_SLOT = IslandOrder.ISLAND_TO_SLOT

--------------------------------------------------------------------
-- Which island is the player standing on? (XZ footprint -> else nearest)
-- Same rule the client HUD uses, so the number the player sees on screen and the
-- number that grants island XP can never disagree.
--------------------------------------------------------------------
-- HOW FAR FROM AN ISLAND'S CENTRE STILL COUNTS AS BEING AT IT. Islands are 370-460 wide,
-- so ~300 reaches the rim of the biggest one; the gaps between them are 6000+. Anything
-- inside 700 is unambiguously AT an island, and nothing mid-flight can be.
-- RESCALED x0.455 with the tower (was 700). This is the "close enough to count as
-- ARRIVED" radius, and its correctness is defined against the GAPS, not the islands: it
-- must stay comfortably under the smallest gap, or the island above you sits inside your
-- own arrival radius. That gap is now 552 studs, so 700 would have exceeded it outright.
-- 318 restores the same proportion. The footprint test above still catches anyone standing
-- anywhere inside an island's own bounding box, so this only governs the just-off-the-edge
-- case -- and it is still gated on `grounded`, which is what makes a mid-gap false positive
-- impossible either way.
local NEAR_RADIUS = 318
local NEAR_RADIUS_SQ = NEAR_RADIUS * NEAR_RADIUS

-- `grounded` gates the NEAR-MISS fallback only. Reaching an island means STANDING on it:
-- without this, flying past 250 studs under its rim counted, so a tank that fell short of
-- the gap still banked the crossing -- which is most of what "I got there in one try"
-- turned out to be. The footprint test below does not need it: being inside an island's
-- own volume is unambiguous however you got there.
local function currentIsland(hrp: BasePart, grounded: boolean?): number?
	local pos = hrp.Position
	local best, bestD = nil, math.huge
	for i = 1, TOP_ISLAND do
		local isl = Workspace:FindFirstChild("island" .. i)
		if isl then
			local ok, cf, size = pcall(function() return isl:GetBoundingBox() end)
			if ok and cf and size and size.Magnitude > 1 then
				local dx, dz = pos.X - cf.Position.X, pos.Z - cf.Position.Z
				local dy = pos.Y - cf.Position.Y
				-- Standing inside the island's footprint -> definitely this one.
				--
				-- `grounded` IS REQUIRED HERE, and leaving it out was a progression bug.
				-- This branch returned `i` unconditionally, so it credited the island to
				-- anyone whose X/Z happened to be over its footprint -- INCLUDING someone
				-- flying past it, or falling back down after failing the crossing. The
				-- vertical test is the island's own half-height PLUS 120 studs of slop, and
				-- these bounding boxes are large (island5 is 198 tall), so that is ~220
				-- studs of airspace under and over each island where merely passing through
				-- counted as arriving.
				--
				-- What that broke: HighestSlot jumped early, which unlocks the higher-tier
				-- FOOD, and a slot-9 food fills a low tank in two servings -- so a failed
				-- crossing could hand the player the fuel to trivially win the next one.
				-- It also made every flight-count measurement meaningless, because the log
				-- recorded islands that were never actually landed on.
				--
				-- The nearest-island fallback below has always required `grounded`. This
				-- branch is simply the same rule stated for the footprint case: you have
				-- arrived when you are STANDING on it, not when you are above it.
				if grounded
					and math.abs(dx) <= size.X / 2 and math.abs(dz) <= size.Z / 2
					and math.abs(dy) <= size.Y / 2 + 120 then
					return i
				end
				-- FULL 3D distance. This used to be dx*dx + dz*dz -- Y was not in it at all,
				-- and that is the bug that broke progression. The tower is stacked
				-- VERTICALLY: 90,000 studs of Y across 13 islands, but only +/-360 of X/Z.
				-- Ignoring Y made "nearest island" essentially arbitrary, so every frame
				-- spent between islands reported some random one as reached.
				local d = dx * dx + dy * dy + dz * dz
				if d < bestD then bestD, best = d, i end
			end
		end
	end
	-- AND IT MUST ACTUALLY BE NEAR ONE. The old code returned `best` unconditionally, so a
	-- player mid-flight was always "at" whichever island won an arbitrary comparison --
	-- HighestSlot ran away within a minute of the first launch, which unlocked the wormhole
	-- and, worse, every high-tier FOOD. Buying 100-power Bananas on island 3 fills any tank
	-- in one purchase, which is what collapsed the multi-attempt crossings into one pass.
	-- Between islands the honest answer is nil: you have not reached anywhere yet.
	if best and bestD <= NEAR_RADIUS_SQ and grounded then return best end
	return nil
end

local function onJoin(player: Player)
	lastCoins[player] = nil
	topIsland[player] = math.floor(tonumber(player:GetAttribute("HighestIsland")) or 1)
	player:SetAttribute("HighestIsland", topIsland[player])
	-- seed HighestSlot from the highest recorded island's slot so wormhole unlocks survive a rejoin; it
	-- re-grows as the player climbs (the heartbeat below bumps it whenever they reach a higher slot).
	topSlot[player] = ISLAND_TO_SLOT[topIsland[player]] or 1
	player:SetAttribute("HighestSlot", topSlot[player])
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
Players.PlayerRemoving:Connect(function(player)
	lastCoins[player] = nil
	topIsland[player] = nil
	topSlot[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(TICK)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildWhichIsA("Humanoid")

			-- THE INTRO FLIES THE CHARACTER UP THE WHOLE TOWER.
			-- StreamingEnabled loads geometry around the BODY, not the camera, so the
			-- opening cinematic has to carry the character with it to make the islands
			-- render. Without this guard that joyride would look exactly like real
			-- progress: HighestIsland would snap to 11 and the player would be handed
			-- island XP for every island in the game before they'd played a second of it.
			if player:GetAttribute("IntroPlaying") then
				continue
			end

			if hrp and hum and hum.Health > 0 then

				------------------------------------------------------------
				-- 1. FLIGHT TICK -- the main XP source (6 XP per 0.5s = 12 XP/sec)
				------------------------------------------------------------
				-- Inferred from FloorMaterial, which replicates to the server. The
				-- client's own `isFlying` flag (BottomHUD) is NOT trusted -- it would
				-- let a client award itself unlimited pet XP.
				--
				-- NOTE this also ticks while FALLING, not just while farting upward.
				-- That's deliberate and matches the original ("XP while airborne"),
				-- and the whole track is cosmetic, so being generous here is harmless.
				if hum.FloorMaterial == Enum.Material.Air then
					if _G.petOnFlightTick then
						pcall(_G.petOnFlightTick, player)
					end
				end

				------------------------------------------------------------
				-- 2. COINS -- award XP on the DELTA, from whatever source
				------------------------------------------------------------
				-- Watching leaderstats.Coins means every coin the player ever banks
				-- feeds the pet, no matter which system paid it out. No need to hunt
				-- down and patch each award site.
				local ls = player:FindFirstChild("leaderstats")
				local coins = ls and ls:FindFirstChild("Coins")
				if coins then
					local now  = coins.Value
					local prev = lastCoins[player]
					if prev and now > prev then
						local gained = now - prev
						if _G.petOnCoins then
							pcall(_G.petOnCoins, player, gained)
						end
					end
					lastCoins[player] = now
				end

				------------------------------------------------------------
				-- 3. NEW ISLAND -- 600 XP, once per island
				------------------------------------------------------------
				-- This ALSO fixes HighestIsland, which until now was only ever set by
				-- the "Skip Island" Robux product -- so simply flying up to an island
				-- never recorded it. That broke the Space Realm progress bar
				-- (Bootstrap) and the meteor-storm respawn (MeteoriteExplosion), both
				-- of which read this attribute.
				local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
				local grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
				local isl = currentIsland(hrp, grounded)
				if isl then
					local top = topIsland[player] or 1
					if isl > top then
						topIsland[player] = isl
						player:SetAttribute("HighestIsland", isl)
						if _G.petOnIsland then
							pcall(_G.petOnIsland, player)
						end
						print(("[PetXP] %s reached island %d (new best) -> +island XP, HighestIsland = %d")
							:format(player.Name, isl, isl))
					end
					-- CLIMB PROGRESS: track the highest tower SLOT reached (the clean signal the Wormhole gates on).
					local slot = ISLAND_TO_SLOT[isl]
					if slot and slot > (topSlot[player] or 1) then
						topSlot[player] = slot
						player:SetAttribute("HighestSlot", slot)
					end
				end
			end
		end
	end
end)

print("[PetXP] pet XP hooks live -- flight tick, coins, and new-island XP now actually fire "
	.. "(they were defined but never called; only eating food gave XP).")
