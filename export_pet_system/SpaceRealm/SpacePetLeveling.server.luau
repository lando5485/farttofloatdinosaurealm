--======================================================================
-- SpacePetLeveling.server.luau   — PUT THIS IN THE *SPACE REALM* PLACE
-- (ServerScriptService).
--
-- Pets keep LEVELING UP in the Space Realm the same way they do on the islands:
-- as you FLY, the equipped pet earns XP and levels (max 25). Uses the EXACT same
-- XP curve + flight-tick rate as the main game (PetSystem.server.lua), so a Lv6
-- pet that came over continues from Lv6 and climbs identically.
--
-- Data lives in _G.playerOwnedPets[player][key] = { level, xp, ... } — the same
-- table PetReceiver staged from the teleport, so a level earned here is written
-- straight back into that record. If your "return to Fart to Float" teleport
-- sends _G.playerOwnedPets back (mirroring the way they came in), the new level
-- rides home with them.
--
-- Flow:
--   SpacePetUpgrades.client fires SpacePetEquipEvent(key) when a pet is equipped,
--   SpacePetProgress() on each flight tick. This script awards XP, levels up, and
--   fires SpacePetLevelEvent(player, {key,level,xp,xpNeed,leveledUp}) back so the
--   follower re-renders the new look.
--======================================================================

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

_G.playerOwnedPets = _G.playerOwnedPets or {}

--======================================================================
-- XP MODEL (identical to the islands)
--======================================================================
local PET_MAX_LEVEL = 25
local PET_XP_BASE, PET_XP_EXP = 80, 1.6
local function xpNeeded(level)
	if level >= PET_MAX_LEVEL then return math.huge end
	return math.floor(PET_XP_BASE * (level ^ PET_XP_EXP))
end
local XP_PER_FLIGHT_TICK = 6     -- each 0.5s flight tick (matches the main game's "distance flown" XP)
local XP_PER_COIN        = 0.15
local XP_PER_GAS         = 0.5
local XP_PER_ISLAND      = 600

--======================================================================
-- REMOTES
--======================================================================
local function remote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not (r and r:IsA("RemoteEvent")) then
		r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage
	end
	return r
end
local SpacePetEquipEvent = remote("SpacePetEquipEvent") -- c->s: equipped storage key ("" = none)
local SpacePetProgress   = remote("SpacePetProgress")   -- c->s: one flight tick
local SpacePetLevelEvent = remote("SpacePetLevelEvent") -- s->c: { key, level, xp, xpNeed, leveledUp }

local equippedKey = {} -- [player] = storage key currently following them
local lastTick    = {} -- [player] = os.clock() of last accepted flight tick (anti-spam)

local function getData(player, key)
	local op = _G.playerOwnedPets[player]; if not op then return nil end
	local d = op[key]; if type(d) ~= "table" then return nil end
	d.level = d.level or 1; d.xp = d.xp or 0
	if d.level > PET_MAX_LEVEL then d.level = PET_MAX_LEVEL; d.xp = 0 end
	return d
end

local function pushLevel(player, key, d, leveledUp)
	SpacePetLevelEvent:FireClient(player, {
		key       = key,
		level     = d.level,
		xp        = math.floor(d.xp),
		xpNeed    = (d.level >= PET_MAX_LEVEL) and 0 or xpNeeded(d.level),
		leveledUp = leveledUp == true,
	})
end

local function awardXP(player, amount, source)
	local key = equippedKey[player]; if not key then return end
	local d = getData(player, key); if not d then return end
	if d.level >= PET_MAX_LEVEL then return end
	d.xp = d.xp + (tonumber(amount) or 0)
	local leveled = false
	while d.level < PET_MAX_LEVEL do
		local need = xpNeeded(d.level)
		if d.xp < need then break end
		d.xp = d.xp - need
		d.level = d.level + 1
		leveled = true
	end
	if d.level >= PET_MAX_LEVEL then d.xp = 0 end
	pushLevel(player, key, d, leveled)
	if leveled then
		print(("[SpaceRealm PetLeveling] %s -> %s now Lv %d (xp source: %s)"):format(player.Name, key, d.level, tostring(source)))
	end
end

--======================================================================
-- WIRING
--======================================================================
SpacePetEquipEvent.OnServerEvent:Connect(function(player, key)
	if type(key) ~= "string" or key == "" then
		equippedKey[player] = nil
		return
	end
	local d = getData(player, key)
	if d then
		equippedKey[player] = key
		pushLevel(player, key, d, false) -- sync the current level to the client on equip
	end
end)

SpacePetProgress.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastTick[player] and (now - lastTick[player]) < 0.4 then return end -- anti-spam: ~max 1 tick/0.4s
	lastTick[player] = now
	awardXP(player, XP_PER_FLIGHT_TICK, "flight")
end)

-- Hooks so YOUR Space Realm flight/coin code can feed XP directly if you prefer (optional):
_G.spaceAwardPetXP   = function(player, amount, source) awardXP(player, amount, source) end
_G.spaceOnFlightTick = function(player)        awardXP(player, XP_PER_FLIGHT_TICK, "flight") end
_G.spaceOnCoins      = function(player, coins) awardXP(player, (tonumber(coins) or 0) * XP_PER_COIN, "coins") end
_G.spaceOnGas        = function(player, gas)   awardXP(player, (tonumber(gas) or 0) * XP_PER_GAS, "gas") end
_G.spaceOnIsland     = function(player)        awardXP(player, XP_PER_ISLAND, "island") end

Players.PlayerRemoving:Connect(function(p)
	equippedKey[p] = nil
	lastTick[p] = nil
end)

print("[SpaceRealm PetLeveling] ready — pets gain XP while flying and level up (max 25, same curve as the islands).")
