--!nonstrict
--======================================================================
-- RealmTransfer  (ReplicatedStorage/Shared/RealmTransfer)  -- SERVER-USE MODULE
--======================================================================
-- ONE definition of "what a player carries between realms", shared by every sender in THIS place
-- (RealmPortals.server.lua and DinoRealmTeleport.server.lua). Before this module they each had their own
-- copy of the payload literal, which is exactly how the two doors into the Dino Realm end up sending
-- different shapes and the receiver starts guessing.
--
-- The matching receivers:
--   * this place:  RealmReturnReceiver.server.lua   (catches players coming HOME)
--   * Dino Realm:  ArrivalReceiver.server.luau + ReturnSender.server.luau
--   * Space Realm: PetReceiver.server.luau
-- Those live in OTHER places and cannot require this module -- a place boundary is a hard wall. They carry
-- their own copy of the field list; if you add a field here, add it there too.
--
-- ⚠ SERVER ONLY. It reads the _G player tables PlayerStats owns, which do not exist on a client.
--======================================================================
local HttpService = game:GetService("HttpService")

local RealmTransfer = {}

RealmTransfer.VERSION = 2   -- v2 added `gamepasses` + `gamepassIds`

-- ONE list of the passes, mirroring PlayerStats.server.lua's GAMEPASS_IDS. It is duplicated here rather
-- than required from PlayerStats because that is a Script, not a ModuleScript -- but the ids are shipped
-- IN the payload, so a far realm reads them from the wire instead of keeping its own third copy.
RealmTransfer.GAMEPASS_IDS = { TwoXForever = 1862015450, GlitterTrail = 1859714979, InfiniteGut = 1860686821 }

-- The attribute PlayerStats stamps on the player when it resolves each pass on join.
local PASS_ATTR = { TwoXForever = "HasTwoXForever", GlitterTrail = "HasGlitterTrail", InfiniteGut = "HasInfiniteGut" }

--======================================================================
-- SIZE. Roblox caps TeleportData, and going over does not truncate -- TeleportAsync THROWS, which means the
-- portal stops working entirely for exactly the players who have played the most. A completionist's skin
-- inventory is combinatorial (every pet x 20 skins x 9 traits is its own key), so this is a real ceiling,
-- not a theoretical one.
--
-- So we measure the encoded payload and, if it is too big, shed the least valuable things first. Pets are
-- NEVER dropped -- they are the whole point of the trip.
--======================================================================
local BUDGET_BYTES = 28000 -- comfortably under the cap, with room for Roblox's own envelope

local function encodedSize(t)
	local ok, json = pcall(function() return HttpService:JSONEncode(t) end)
	if not ok then return math.huge end -- unencodable -> treat as oversized so the shedding below runs
	return #json
end

-- Shed in priority order, cheapest loss first. Each step is announced, because a player silently losing
-- their collection book on every portal trip is the kind of bug that takes weeks to notice.
local function fit(payload, playerName)
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	-- 1) Duplicate COUNTS in the skin inventory. Owning 12 copies vs 1 copy only matters for the crate's
	--    duplicate display; which skins you OWN is what actually renders a pet. Collapse counts to 1.
	if type(payload.petSkins) == "table" then
		local flat = {}
		for k, v in pairs(payload.petSkins) do
			if (tonumber(v) or 0) > 0 then flat[k] = 1 end
		end
		payload.petSkins = flat
		warn(("[RealmTransfer] %s payload oversized -- collapsed skin duplicate counts"):format(playerName))
		if encodedSize(payload) <= BUDGET_BYTES then return payload end
	end

	-- 2) The collection book + milestone flags. Both are re-derivable at home from the inventory the player
	--    already has saved there, so dropping them costs nothing permanent.
	payload.collection    = nil
	payload.petMilestones = nil
	warn(("[RealmTransfer] %s payload still oversized -- dropped collection + milestones"):format(playerName))
	if encodedSize(payload) <= BUDGET_BYTES then return payload end

	-- 3) The skin inventory itself. Their pets now travel undressed (base look in the other realm), but they
	--    travel. The home save still has every skin -- nothing is lost permanently, only for this visit.
	payload.petSkins      = nil
	payload.equippedSkins = nil
	warn(("[RealmTransfer] %s payload STILL oversized -- dropped the skin inventory; pets will render " ..
		"with their base look in the other realm"):format(playerName))
	return payload
end

--======================================================================
-- THE PAYLOAD
--======================================================================
-- What travels, and just as importantly what does NOT:
--
--   * Pets + the cosmetics that dress them. A pet without its skin/trait renders as the plain base pet in
--     the other realm, so the bundle moves together.
--   * homePlaceId -- how the far side knows where "back" is. The Dino place does not know this place's id,
--     and hardcoding the same magic number in two projects is how return trips break the first time one is
--     republished. We stamp it; ArrivalReceiver stashes it; ReturnSender teleports to it.
--   * NOT coins/island/stomach/fartMeter. Those are ABSOLUTES and this place's DataStore is their authority.
--     A returning snapshot assigning them would wipe whatever the player earned in the meantime -- see the
--     header of RealmReturnReceiver.server.lua for the full reasoning.
--
--   * GAMEPASSES -- and note carefully that these are a DIFFERENT KIND of thing from everything above, so
--     they are carried for a different reason. Pet data has to travel because it exists only in this
--     place's DataStore and the far realm has no way to look it up. Gamepass ownership is not like that:
--     it is a Roblox-side fact keyed on (user, passId), and UserOwnsGamePassAsync answers it correctly
--     from ANY place in ANY universe. So a realm that knows the pass ids never actually needed a payload.
--
--     They travel anyway, for two practical reasons:
--       1. SPEED. The flags here were already resolved on join in this place, so the far realm can honour
--          a 2x pass on the arrival frame instead of after a web call that can take a second and can fail.
--       2. The far realm may not have the id list. `gamepassIds` ships alongside the flags precisely so a
--          receiver can re-verify with UserOwnsGamePassAsync WITHOUT hardcoding ids that then drift apart
--          between projects -- which is the failure this whole module exists to prevent.
--
--     Treat the flags as a trustworthy hint (TeleportData is server-set, so a client cannot forge them)
--     and the ids as the way to confirm. They are three booleans and three numbers, so `fit` never needs
--     to shed them.
--
-- `extra` is merged in last, so a caller can add its own keys (RealmPortals passes `realm`).
function RealmTransfer.build(player, realmKey, extra)
	local function g(tbl, default)
		local t = _G[tbl]
		local v = t and t[player]
		if v == nil then return default end
		return v
	end

	local payload = {
		fromFartToFloat = true,          -- the marker EVERY receiver in the project checks -- do not rename
		payloadVersion  = RealmTransfer.VERSION,
		fromPlaceId     = game.PlaceId,  -- which realm they came FROM
		homePlaceId     = game.PlaceId,  -- where the return trip goes (this IS home)
		toRealm         = realmKey,      -- where they were headed, for the far side's logs
		userId          = player.UserId, -- the far side refuses a payload stamped for somebody else
		sentAt          = os.time(),

		ownedPets       = g("playerOwnedPets", {}),
		equippedPet     = g("playerEquippedPet", nil),
		petSkins        = g("playerPetSkins", {}),
		equippedSkins   = g("playerEquippedSkins", {}),
		collection      = g("playerCollection", {}),
		petMilestones   = g("playerPetMilestones", {}),
		title           = g("playerTitle", nil),
		crateTokens     = math.floor(tonumber(g("playerCrateTokens", 0)) or 0),
		ownedGutSkins   = g("playerOwnedGutSkins", { Default = true }),
		equippedGutSkin = g("playerEquippedGutSkin", "Default"),

		-- Read off the ATTRIBUTES rather than re-querying Roblox: PlayerStats already resolved every pass
		-- when the player joined this place and stamped the answer there, so this costs nothing and cannot
		-- block the teleport on a slow web call. A pass bought DURING this session is included too --
		-- PlayerStats sets the same attribute in its PromptGamePassPurchaseFinished handler.
		gamepasses      = {},
		gamepassIds     = {},   -- a COPY, not the module's own table: `fit` and every caller are free to
		                        -- mutate the payload, and aliasing would edit the shared list underneath them
	}
	for name, attr in pairs(PASS_ATTR) do
		payload.gamepasses[name] = (player:GetAttribute(attr) == true)
	end
	for name, id in pairs(RealmTransfer.GAMEPASS_IDS) do
		payload.gamepassIds[name] = id
	end

	if type(extra) == "table" then
		for k, v in pairs(extra) do payload[k] = v end
	end

	return fit(payload, player.Name)
end

return RealmTransfer
