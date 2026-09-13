--======================================================================
-- ReturnIsland.server.luau   (ServerScriptService.DinosaurRealmServer)
--======================================================================
-- "RETURN TO <HIGHEST ISLAND YOU REACHED>" -- the fall-catch safety button.
--
-- From the portable ReturnIslandKit, wired into this realm. What the kit does generically,
-- this does against the tower:
--   * Watches every player's height against the highest island they have reached.
--   * The moment they are below it by more than CATCH_MARGIN studs, it sets
--     ReturnPromptIsland on them (the SLOT to offer, or 0 to hide). The client draws off it.
--   * Tapping asks the server to put them back. THE SERVER DOES THE TELEPORT.
--   * NO auto-teleport. Falling is the game; this is the player choosing to give up on a fall.
--
-- ===== THREE THINGS FROM THE KIT THAT MUST NOT BE "OPTIMISED" =====
-- 1. THE CLIENT SENDS NOTHING. No slot, no position, no target. The server recomputes
--    where the player actually got to. A client that can name its own destination is a
--    client that can teleport to the summit -- passing the slot would be the whole exploit.
-- 2. ANCHORS ARE RE-SCANNED, NOT CACHED ONCE. IslandLayout MOVES every island at startup,
--    so anything resolved on frame one is wrong by the time the player is flying.
-- 3. THE TAP DOES NOT RE-CHECK THE MARGIN. The button only ever shows while the player is
--    below home; re-testing here meant a tap landing just as they crossed back gave a
--    silent no-op. It cannot skip progress either way -- the only destination it can
--    produce is somewhere they already reached.
--
-- ===== WHAT CHANGED FROM THE KIT, AND WHY =====
-- ANCHORS ARE SLOTS, NOT ISLAND NUMBERS. The tower scrambles the two: island9 is slot 2,
-- island12 is slot 4. Indexing anchors by model number would offer a falling player a
-- "return" to somewhere higher than they have ever been. Everything here is keyed on the
-- CLIMB SLOT, via IslandOrder.SLOT_TO_ISLAND, which is what HighestSlot counts too.
--
-- PROGRESS IS AN ATTRIBUTE, NOT A leaderstats VALUE. The kit reads a leaderstats IntValue;
-- this realm keeps climb progress in the HighestSlot attribute (PetXPHooks sets it, and the
-- shop, wormhole, arrow and rebirth all gate on it). Using anything else here would let the
-- button disagree with every other system about how far you have got.
--
-- LANDING MATH IS IslandTeleport'S. Islands are MODELS, not parts, so "the top face" is the
-- bounding box's top -- the same `GetBoundingBox().Y/2 + offset` that /island N already uses.
-- Reusing it means the button lands you exactly where the chat command does.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local IslandOrder = require(ReplicatedStorage:WaitForChild("DinosaurRealm"):WaitForChild("IslandOrder"))

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- studs BELOW the island before the prompt appears WHILE AIRBORNE. Too small and it
	-- flickers every time you hop off a ledge; too large and a falling player waits to be
	-- offered help. 60 is the kit's default and it suits a tower whose gaps are 6000+.
	-- RESCALED x0.455 with the tower (was 60). It is an anti-flicker band measured against
	-- the airspace of a gap, and the gaps shrank by more than half.
	CATCH_MARGIN = 27,

	-- The same test for a player who is STANDING ON SOMETHING. Far smaller on purpose: the
	-- big margin is only there to stop mid-air flicker, and you cannot flicker with your
	-- feet on the ground. Landed anywhere below your island means you are on a LOWER island
	-- and the button should just be there. 12 keeps it from firing on your own island's
	-- bumps, rocks and slopes -- the ray below samples one point, not the whole surface.
	GROUNDED_DROP = 12,

	DROP_HEIGHT  = 8,     -- matches IslandTeleport's LANDING_OFFSET, so both land identically
	CHECK_HZ     = 5,     -- 5/sec is plenty and costs nothing; per-frame is waste
	RESCAN_AFTER = 5,     -- seconds before the anchor table is rebuilt

	-- ---- FLYING vs FALLING ----------------------------------------------------------
	-- Upward speed at or above this means they are climbing UNDER POWER and the button
	-- stays hidden -- they are already fixing the problem themselves and a rescue offer
	-- sitting over the screen for a whole 80-second ascent is just clutter.
	--
	-- 10 is well clear of noise and well under the slowest gut (81 studs/sec at Hatchling,
	-- and every tier above climbs faster), so it catches every real flight. A jump tops out
	-- around 50 and would read as "flying" for its first fraction of a second -- harmless,
	-- since it only suppresses a button that reappears the moment you start coming down.
	-- BACK AT 10. Every powered climb speed is back to its pre-compression value (the
	-- slowest gut climbs at 50 studs/sec again), so the original threshold is once more the
	-- right one -- a fifth of the slowest powered climb, and well clear of physics noise.
	-- An interim pass cut this to 5 to track a slowed-down player who no longer exists.
	RISE_SPEED = 10,

	-- Falling at or beyond this is a DECENT FALL and always shows the button, whatever the
	-- rise test thinks. Belt and braces: velocity replicates from a client-owned character,
	-- so a stale or jittery upward reading could otherwise hide the button from someone
	-- genuinely plummeting -- the exact moment they need it most.
	-- 35 studs/sec is about a fifth of a second of freefall: past stepping off a ledge,
	-- comfortably short of a real drop.
	FALL_SPEED = 35,
}

--======================================================================
-- REMOTE
--======================================================================
local ReturnToIslandEvent = ReplicatedStorage:FindFirstChild("ReturnToIslandEvent")
if not ReturnToIslandEvent then
	ReturnToIslandEvent = Instance.new("RemoteEvent")
	ReturnToIslandEvent.Name = "ReturnToIslandEvent"
	ReturnToIslandEvent.Parent = ReplicatedStorage
end

--======================================================================
-- THE ANCHORS -- one per CLIMB SLOT
--======================================================================
-- Rebuilt on demand rather than cached once: IslandLayout repositions all 13 models at
-- startup, and a table resolved before that ran would teleport people to where the islands
-- USED to be. Streaming is client-side, so on the server the models themselves always exist.
local anchorCache, anchorCacheAt = {}, 0

-- THE ANCHOR HEIGHT IS THE WALKABLE SURFACE, NOT THE BOUNDING BOX TOP.
--
-- IslandTeleport uses bbox-top for /island N and gets away with it: you drop in from above
-- the treetops and fall to the ground, which is fine for a debug command. It is NOT fine
-- here, because this height is also the line that decides whether you are "below" your
-- island. A bounding box wraps the tallest tree, the volcano and every NPC on the island --
-- island5's is ~47781 while its ground is ~47546. Using it would mean standing on your own
-- island counts as 235 studs below it: the button would offer to rescue you from the place
-- you are standing, and tapping it would drop you from the canopy.
--
-- So: one downward ray per island, from just above its bbox, hitting only that island's own
-- parts. Whatever it lands on IS the surface. 13 rays every RESCAN_AFTER seconds is nothing.
local function surfaceY(isl, x, z, ceiling)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { isl }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, ceiling + 10, z), Vector3.new(0, -(ceiling * 2 + 100), 0), params)
	return hit and hit.Position.Y or nil
end

local function rebuildAnchors()
	local found = {}
	for slot, islandNum in ipairs(IslandOrder.SLOT_TO_ISLAND) do
		local isl = Workspace:FindFirstChild("island" .. islandNum)
		if isl then
			local pos, boxTop
			if isl:IsA("Model") then
				local cf, size = isl:GetBoundingBox()
				pos, boxTop = cf.Position, cf.Position.Y + size.Y / 2
			elseif isl:IsA("BasePart") then
				pos, boxTop = isl.Position, isl.Position.Y + isl.Size.Y / 2
			end
			-- THE ISLAND'S SPAWN PAD WINS, when it has one. NestingNook_NPCs puts an
			-- invisible "island<N>Spawn" on every island at the hand-placed spawn spot, so
			-- dying returns you to the same place a wormhole warp would -- one arrival point
			-- per island however you get there, instead of three systems each with their
			-- own idea of where "on the island" means.
			--
			-- The centre-line ray below stays as the fallback, and it is a real fallback,
			-- not dead code: it is what answers for an island whose pad has not been built
			-- yet when the first anchor scan runs.
			local pad = isl:FindFirstChild("island" .. islandNum .. "Spawn", true)
			if pad and pad:IsA("BasePart") then
				found[slot] = {
					x = pad.Position.X,
					z = pad.Position.Z,
					top = pad.Position.Y + pad.Size.Y / 2,
					island = islandNum,
				}
			elseif boxTop then
				-- Ray straight down the island's centre line. Falls back to the bbox top only
				-- if the centre happens to be a hole -- better a high anchor than none.
				local top = surfaceY(isl, pos.X, pos.Z, boxTop) or boxTop
				found[slot] = { x = pos.X, z = pos.Z, top = top, island = islandNum }
			end
		end
	end
	anchorCache, anchorCacheAt = found, os.clock()
	return found
end

local function anchors()
	if os.clock() - anchorCacheAt > CONFIG.RESCAN_AFTER then return rebuildAnchors() end
	return anchorCache
end

--======================================================================
-- HOW FAR HAVE THEY GOT
--======================================================================
-- HighestSlot IS THE ONLY SOURCE. The kit also kept a `sessionBest` -- the highest slot the
-- player had been "at or above" -- as a floor under the progress stat, for realms that have
-- no progress stat at all. This realm has one, and keeping both was a bug:
--
--     if y >= anchor.top - 2 then reachedNow = slot end
--
-- tested ALTITUDE ONLY, with no X/Z check. Anything that lifts you -- the intro cinematic, a
-- long flight -- counted as reaching every island whose surface you were above, and because
-- it was a running maximum it latched permanently. A fresh join was offered the summit
-- eleven seconds in. It is the same mistake as PetXPHooks' XZ-only nearest-island test,
-- from the opposite direction: in a tower 90,000 studs tall and 700 wide, ONE AXIS IS NEVER
-- ENOUGH. PetXPHooks now decides "reached" properly, in 3D and distance-capped, so this
-- reads its answer instead of second-guessing it with a worse test.
local function highestReached(player)
	local best = math.floor(tonumber(player:GetAttribute("HighestSlot")) or 1)

	-- Clamp DOWN to a slot that actually resolves. Progress can legitimately run ahead of
	-- the world (a wormhole unlock, a model not yet rebuilt), and teleporting to an anchor
	-- that is not there is a fall through the void.
	local a = anchors()
	while best > 1 and not a[best] do best = best - 1 end
	return best
end

--======================================================================
-- THE TELEPORT
--======================================================================
local function putOnAnchor(char, anchor)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and anchor) then return false end
	char:PivotTo(CFrame.new(anchor.x, anchor.top + CONFIG.DROP_HEIGHT, anchor.z))
	-- Kill the fall. Without this they arrive carrying whatever downward velocity they had
	-- and drop straight back off, which reads as the button not working.
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

ReturnToIslandEvent.OnServerEvent:Connect(function(player)
	-- The client sends NOTHING. Everything below is recomputed here; see the header.
	local slot = highestReached(player)
	if slot < 1 then return end
	local anchor = anchors()[slot]
	if not anchor then
		warn(("[Return] %s tapped but slot %d has no island resolved yet"):format(player.Name, slot))
		return
	end
	local char = player.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then return end

	if putOnAnchor(char, anchor) then
		player:SetAttribute("ReturnPromptIsland", 0)
		print(("[Return] %s returned to slot %d (island%d, %s)")
			:format(player.Name, slot, anchor.island, IslandOrder.NAMES[anchor.island] or "?"))
	end
end)

--======================================================================
-- THE PROMPT DRIVER
--======================================================================
-- Sets ReturnPromptIsland on every player: the SLOT to offer, or 0 for "hide the button".
--
-- SHOWN whenever they are below home AND NOT CLIMBING UNDER POWER -- so standing on a lower
-- island, drifting, or falling all offer the button, and a decent fall always does.
-- HIDDEN on or above home, and while fart-flying upward.
--
-- The flying test is VELOCITY, not a flag from the client. BottomHUD knows perfectly well
-- whether it is flying, but that lives in a LocalScript's own _G and its BodyVelocity is
-- client-created, so neither replicates -- reading either would mean a new remote and
-- trusting the client about when it may hide a safety button. Vertical speed comes back on
-- its own with the character's physics state and cannot be quietly lied about for free.
task.spawn(function()
	local period = 1 / math.max(1, CONFIG.CHECK_HZ)
	while true do
		task.wait(period)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp then
				local a = anchors()
				local y = hrp.Position.Y

				-- (The session-progress scan that used to sit here is gone -- see the note on
				-- highestReached. It recorded progress from altitude alone, which handed a
				-- brand-new player the summit.)

				-- Climbing under power, or coming down hard? A decent fall WINS over the rise
				-- test rather than merely failing it, so a jittery upward sample cannot blank
				-- the button on somebody who is actually dropping.
				local vy = hrp.AssemblyLinearVelocity.Y
				local fallingHard = vy <= -CONFIG.FALL_SPEED
				local flying      = (not fallingHard) and vy >= CONFIG.RISE_SPEED

				-- STANDING ON SOMETHING SKIPS THE MARGIN ENTIRELY.
				-- CATCH_MARGIN exists to stop the button flickering while you hop around in
				-- the air near your own island -- it is an ANTI-FLICKER rule, and a player
				-- with both feet on the ground cannot flicker. If you are landed and your
				-- island is above you, you are on a lower island and you want the button,
				-- even if the drop was only a few studs. GROUNDED_DROP is just enough to not
				-- fire from standing on your own island's own bumps.
				local grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
				local margin = grounded and CONFIG.GROUNDED_DROP or CONFIG.CATCH_MARGIN

				local home = highestReached(plr)
				local want = 0
				if home >= 1 and not flying then
					local anchor = a[home]
					if anchor and y < anchor.top - margin then want = home end
				end
				if (plr:GetAttribute("ReturnPromptIsland") or 0) ~= want then
					plr:SetAttribute("ReturnPromptIsland", want)
				end
			end
		end
	end
end)

--======================================================================
-- RESPAWN ON YOUR HIGHEST ISLAND
--======================================================================
-- Dying dropped you back at island 1's SpawnLocation, however far you had climbed -- so a
-- single mistimed landing undid the whole session. You now come back where you got to.
--
-- IT LIVES HERE because this file already knows where every island's WALKABLE SURFACE is
-- (the raycast anchors above) and which slot a player has actually reached. Writing it
-- anywhere else would mean a second copy of both, and a second copy of the bounding-box
-- mistake that put the anchor in the treetops.
--
-- ONLY ON RESPAWN, NEVER ON THE FIRST CHARACTER. The join spawn belongs to Intro (the
-- first-join cinematic) and ArrivalReceiver (rift arrivals); moving the player out from
-- under either would fight them for the same character. The first CharacterAdded is
-- therefore skipped and only deaths are caught.
local seenCharacter = {}

local function placeOnHighest(plr, char)
	local slot = highestReached(plr)
	if slot < 2 then return end            -- island 1 IS the default spawn; nothing to do
	local anchor = anchors()[slot]
	if not anchor then return end
	if not (char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)) then return end
	-- Let Roblox's own SpawnLocation placement land first, then override it. Moving the
	-- character in the same frame it appears is a race the default spawn usually wins.
	task.wait(0.2)
	if plr.Character ~= char or not char.Parent then return end
	if putOnAnchor(char, anchor) then
		plr:SetAttribute("ReturnPromptIsland", 0)   -- they are home; nothing to return to
		print(("[Return] %s respawned on slot %d (island%d, %s)")
			:format(plr.Name, slot, anchor.island, IslandOrder.NAMES[anchor.island] or "?"))
	end
end

local function hookRespawn(plr)
	plr.CharacterAdded:Connect(function(char)
		if not seenCharacter[plr] then
			seenCharacter[plr] = true       -- first character: Intro / ArrivalReceiver own it
			return
		end
		task.spawn(placeOnHighest, plr, char)
	end)
end
for _, plr in ipairs(Players:GetPlayers()) do hookRespawn(plr) end
Players.PlayerAdded:Connect(hookRespawn)

Players.PlayerRemoving:Connect(function(p)
	seenCharacter[p] = nil
end)

print(("[Return] respawn-at-highest active -- deaths return you to your furthest island "
	.. "(first spawn left to Intro / ArrivalReceiver)"))
print(("[Return] ready -- shows while LANDED %d+ studs below your island, or airborne %d+ below; "
	.. "hidden while climbing (>%d studs/s up), always shown in a fall (<-%d). Anchors are the "
	.. "RAYCAST SURFACE of each island, keyed on CLIMB SLOT (progress from HighestSlot). "
	.. "Server-authoritative teleport."):format(
	CONFIG.GROUNDED_DROP, CONFIG.CATCH_MARGIN, CONFIG.RISE_SPEED, CONFIG.FALL_SPEED))
