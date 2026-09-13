--!nonstrict
--======================================================================
-- TradeRequests.server.luau  (Script, ServerScriptService)
--======================================================================
-- ASK A FRIEND TO TRADE WHEN THEY ARE NOT HERE.
--
-- The live trade window in PetSystem is good and it is staying exactly as it is: two players, both online,
-- both looking at the same offer, both confirming. That is the only safe way to move a pet or a skin, and
-- nothing here changes it.
--
-- What it could not do is START. Trading needed both kids in the same server at the same moment, which for
-- two friends in different time zones -- or two kids whose parents allot different screen time -- is a
-- coordination problem they have no tool to solve. They could want to trade for a week and never once be
-- online together.
--
-- ===== THIS MOVES MESSAGES, NEVER ITEMS =====
-- A request is an invitation and nothing else. No pet leaves an inventory, no skin is escrowed, no save is
-- written on behalf of somebody who is not here. That is the single design decision this whole file rests
-- on, and it is worth being blunt about why:
--
--   To trade with an OFFLINE player you must edit an inventory nobody is watching. Do that and you have to
--   answer what happens when their save is loaded on another server mid-write, when they join during the
--   write, when the write half-succeeds. Every wrong answer mints duplicate pets, and a duplicated rare is
--   not a bug you can quietly patch -- it is permanently in the economy, and every kid who traded honestly
--   for one has been robbed of the thing that made it worth having.
--
-- So: the request waits. When the recipient joins they are told who asked. If that person is online, one tap
-- opens the REAL trade window. If not, they can send an invitation straight back. Two kids who keep missing
-- each other now leave notes until they overlap, and the moment they do the existing, safe trade runs.
--
-- ===== ANYONE, BUT ONLY EVER A NAME =====
-- Requests can go to any player, found by username, not just to friends -- two kids who met in a server and
-- did not add each other still need a way to finish the trade they were talking about.
--
-- What keeps that safe is that a request CARRIES NO WRITABLE TEXT. The recipient sees a Roblox username, a
-- timestamp, and optionally the name of a pet or skin chosen from a list the server built. There is no field
-- a sender can type into, so this cannot be used to say anything to anyone -- which is the actual risk with
-- an open channel in a game played by children, and it is closed by construction rather than by a filter.
--
-- The rest is volume control: one pending request per sender, a cap on the mailbox, a send cooldown, and a
-- fortnight expiry. Nobody can be buried, and nobody can be nagged.
--======================================================================

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if _G.__TradeRequestsServer then
	warn("[TradeReq] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__TradeRequestsServer = true

--======================================================================
-- TUNING
--======================================================================
local MAX_MAILBOX   = 20      -- pending requests one player may hold; past this, senders are politely refused
local SEND_COOLDOWN = 20      -- seconds between sends, per sender
local EXPIRY_DAYS   = 14      -- a request older than this is dropped on read rather than shown
local FRIEND_CAP    = 60      -- friends listed at most; the list is a paged web call, not a free lookup

local STORE_NAME = "TradeRequests_v1"   -- bump the suffix if the record shape ever changes
local store = DataStoreService:GetDataStore(STORE_NAME)

local function key(userId) return "u_" .. tostring(userId) end

--======================================================================
-- REMOTES
--======================================================================
local function remote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local ReqSend    = remote("TradeReqSendEvent")                        -- c->s: (targetUserId)
local ReqInbox   = remote("TradeReqInboxEvent")                       -- s->c: (list) what is waiting for you
local ReqResult  = remote("TradeReqResultEvent")                      -- s->c: (ok, message)
local ReqFriends = remote("TradeReqFriendsFunc", "RemoteFunction")    -- c->s: () -> friend list
local ReqMine    = remote("TradeReqMineFunc", "RemoteFunction")       -- c->s: () -> your pets + skins
local ReqLookup  = remote("TradeReqLookupFunc", "RemoteFunction")     -- c->s: (name) -> that player

--======================================================================
-- MAILBOX
--======================================================================
-- Every DataStore call throws on network trouble, on throttling, and routinely in Studio where API access is
-- off. Each one becomes a polite refusal rather than an error that leaves a sender staring at a dead button.

-- UpdateAsync, not Set: two senders in different servers must not clobber each other's entry.
local function mailboxAppend(targetUserId, record)
	local full, dupe = false, false
	local ok, err = pcall(function()
		store:UpdateAsync(key(targetUserId), function(old)
			local list = (type(old) == "table") and old or {}
			-- ONE PENDING REQUEST PER SENDER. Without this, tapping Invite four times puts four identical
			-- notes in the same inbox, which is indistinguishable from spam and fills the cap with one
			-- person. Re-sending refreshes the timestamp instead, so a fresh ask still moves to the top.
			for _, rec in ipairs(list) do
				if rec.fromId == record.fromId then
					rec.at = record.at
					-- The OFFER is overwritten too, not just the timestamp. Somebody who asks again with a
					-- different pet has changed their mind, and leaving the old pet's name in the note means
					-- the recipient logs in for something that is no longer on the table.
					rec.offers  = record.offers
					rec.summary = record.summary
					rec.offer   = nil     -- clears the single-item field written by the previous build
					dupe = true
					return list
				end
			end
			if #list >= MAX_MAILBOX then
				full = true
				return nil        -- returning nil aborts the write and leaves the stored value untouched
			end
			list[#list + 1] = record
			return list
		end)
	end)
	if full then return false, "Their trade inbox is full right now!" end
	if not ok then
		warn("[TradeReq] mailbox write failed for " .. tostring(targetUserId) .. ": " .. tostring(err))
		return false, "Couldn't reach them, try again in a moment."
	end
	return true, dupe and "They already have your request -- bumped it to the top!" or nil
end

-- READ WITHOUT CLEARING.
--
-- The opposite of Gifting, and deliberately so. A gift is consumed by being read -- clearing first is what
-- stops it being claimed twice and minting tokens. A request grants NOTHING, so there is nothing to mint,
-- and leaving it in place is strictly better: a player who joins for thirty seconds and leaves still has
-- their requests waiting next time, instead of having silently burned them by logging in.
local function mailboxRead(userId)
	local list
	local ok, err = pcall(function() list = store:GetAsync(key(userId)) end)
	if not ok then
		warn("[TradeReq] mailbox read failed for " .. tostring(userId) .. ": " .. tostring(err))
		return {}
	end
	if type(list) ~= "table" then return {} end

	local cutoff, fresh = os.time() - EXPIRY_DAYS * 86400, {}
	for _, rec in ipairs(list) do
		if type(rec) == "table" and (tonumber(rec.at) or 0) >= cutoff then fresh[#fresh + 1] = rec end
	end
	return fresh
end

local function mailboxRemove(userId, fromId)
	pcall(function()
		store:UpdateAsync(key(userId), function(old)
			local list = (type(old) == "table") and old or {}
			for i = #list, 1, -1 do
				if list[i].fromId == fromId then table.remove(list, i) end
			end
			return list
		end)
	end)
end
_G.tradeReqClear = mailboxRemove

--======================================================================
-- WHAT YOU CAN OFFER
--======================================================================
-- An offer NAMES a thing. It does not reserve it, remove it, or promise it -- see the header. What it buys
-- is the difference between "Sam wants to trade" and "Sam will give you their Gold Void Dragon", and only
-- one of those is worth logging back in for.
--
-- Read from the same server-side tables the live trade reads, so the list can never show something the
-- trade window would then refuse.
local function prettyPet(key)
	local k = tostring(key)
	local rare = k:sub(-2) == "#R"
	if rare then k = k:sub(1, -3) end
	-- "BeanBuddy" -> "Bean Buddy". The ids are camel case and nothing else stores a display name that is
	-- reachable from here, so the name is derived rather than looked up.
	local spaced = k:gsub("(%l)(%u)", "%1 %2")
	return rare and (spaced .. " \xE2\x98\x85Rare") or spaced
end

local function prettySkin(key)
	-- Stored as "Pet|Skin|Trait".
	local pet, skin, trait = tostring(key):match("^([^|]*)|([^|]*)|?(.*)$")
	if not pet then return tostring(key) end
	local name = (skin ~= "" and skin or "Skin") .. " " .. (pet:gsub("(%l)(%u)", "%1 %2"))
	if trait and trait ~= "" then name = trait .. " " .. name end
	return name
end

local function offerables(player)
	local pets, skins = {}, {}

	local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
	if type(owned) == "table" then
		for key, v in pairs(owned) do
			if v then pets[#pets + 1] = { key = tostring(key), label = prettyPet(key) } end
		end
	end

	local mySkins = _G.playerPetSkins and _G.playerPetSkins[player]
	if type(mySkins) == "table" then
		for key, count in pairs(mySkins) do
			if (tonumber(count) or 0) > 0 then
				skins[#skins + 1] = { key = tostring(key), label = prettySkin(key) }
			end
		end
	end

	table.sort(pets,  function(a, b) return a.label < b.label end)
	table.sort(skins, function(a, b) return a.label < b.label end)
	return { pets = pets, skins = skins }
end

ReqMine.OnServerInvoke = function(player) return offerables(player) end

-- Ownership is re-checked HERE, on the way out, and never trusted from the client -- a client can put any
-- string in an offer, and a request advertising a pet the sender does not have is a lie the recipient logs
-- in for. It is checked again by the live trade when the items actually move, which is the check that
-- matters; this one just stops the lie being sent in the first place.
local MAX_OFFER_ITEMS = 6   -- an offer is a pitch, not an inventory dump; past this the note stops being readable

local function validOne(player, offer)
	if type(offer) ~= "table" then return nil end
	local kind, key = tostring(offer.kind or ""), tostring(offer.key or "")
	if key == "" then return nil end

	if kind == "pet" then
		local owned = _G.playerOwnedPets and _G.playerOwnedPets[player]
		if not (type(owned) == "table" and owned[key]) then return nil end
		return { kind = "pet", key = key, label = prettyPet(key) }
	elseif kind == "skin" then
		local ok = false
		if _G.skinOwnsEntry then pcall(function() ok = _G.skinOwnsEntry(player, key) == true end) end
		if not ok then return nil end
		return { kind = "skin", key = key, label = prettySkin(key) }
	end
	return nil
end

-- A player can put several pets AND skins in one offer, because that is how kids actually trade -- "my two
-- commons for your rare" is the normal shape of a deal, and an offer that can only name one thing forces the
-- pitch to be made somewhere this system cannot carry it.
--
-- Every entry is validated on its own and the bad ones are DROPPED rather than failing the whole send: an
-- offer can go stale mid-pick (a pet traded away in another window, a skin fused), and refusing the entire
-- request over one dead entry punishes the sender for something they cannot see.
local function validOffers(player, offers)
	if type(offers) ~= "table" then return nil end

	local out, seen = {}, {}
	for _, entry in ipairs(offers) do
		if #out >= MAX_OFFER_ITEMS then break end
		local checked = validOne(player, entry)
		-- Deduped by kind+key so the same pet listed twice cannot pad a two-item offer into a six-item one.
		if checked then
			local id = checked.kind .. "\0" .. checked.key
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = checked
			end
		end
	end

	if #out == 0 then return nil end
	return out
end

-- One line, whatever the count -- it has to fit on a row in the recipient's list.
local function offerSummary(offers)
	if not offers or #offers == 0 then return nil end
	if #offers == 1 then return offers[1].label end
	if #offers == 2 then return offers[1].label .. " + " .. offers[2].label end
	return offers[1].label .. " + " .. (#offers - 1) .. " more"
end

--======================================================================
-- SEND
--======================================================================
local lastSend = {}   -- [player] = os.clock()

ReqSend.OnServerEvent:Connect(function(player, targetUserId, offer)
	targetUserId = tonumber(targetUserId)
	if not targetUserId or targetUserId <= 0 or targetUserId == player.UserId then return end

	local now = os.clock()
	if lastSend[player] and now - lastSend[player] < SEND_COOLDOWN then
		ReqResult:FireClient(player, false, "Hold on a moment before sending another.")
		return
	end
	lastSend[player] = now

	-- Already here? Then there is nothing to leave a note about -- open the real trade window instead. This
	-- is the case that keeps the feature honest: offline requests are a fallback for when the good path is
	-- unavailable, never a second way of doing something the game already does properly.
	local online = Players:GetPlayerByUserId(targetUserId)
	if online then
		ReqResult:FireClient(player, false, online.Name .. " is here right now -- trade with them directly!")
		return
	end

	local checked = validOffers(player, offer)
	local summary = offerSummary(checked)

	local posted, note = mailboxAppend(targetUserId, {
		fromId   = player.UserId,
		fromName = player.Name,
		at       = os.time(),
		offers   = checked,       -- nil = "just asking", which stays a perfectly good request
		-- The one-line version is stored ALONGSIDE the list, not derived when the note is read. The reader is
		-- a different server that may be running a different build, and a summary computed there could word
		-- the same offer differently from the confirmation the sender was shown.
		summary  = summary,
	})
	if posted then
		ReqResult:FireClient(player, true, note or (summary
			and ("Offer sent! They'll see your " .. summary .. " next time they play.")
			or "Request sent! They'll see it next time they play."))
		print(("[TradeReq] %s -> %d (offline request%s)")
			:format(player.Name, targetUserId, summary and (", offering " .. summary) or ""))
	else
		ReqResult:FireClient(player, false, note or "Couldn't send that right now.")
	end
end)

--======================================================================
-- FRIEND LIST
--======================================================================
-- Paged web call, capped. `here` means "in this server", which is the only online state we can know for
-- certain -- and it is the only one that matters, because it is the one where the live trade window works.
ReqFriends.OnServerInvoke = function(player)
	local out = {}
	pcall(function()
		local page = Players:GetFriendsAsync(player.UserId)
		while #out < FRIEND_CAP do
			for _, f in ipairs(page:GetCurrentPage()) do
				if #out >= FRIEND_CAP then break end
				out[#out + 1] = {
					id   = f.Id,
					name = f.DisplayName or f.Username,
					here = Players:GetPlayerByUserId(f.Id) ~= nil,
				}
			end
			if page.IsFinished then break end
			page:AdvanceToNextPageAsync()
		end
	end)
	table.sort(out, function(a, b)
		if a.here ~= b.here then return a.here end   -- people you can trade with RIGHT NOW go first
		return tostring(a.name):lower() < tostring(b.name):lower()
	end)
	return out
end

--======================================================================
-- FIND A PLAYER BY NAME
--======================================================================
-- GetUserIdFromNameAsync THROWS for a name that does not exist, which is the common case here -- kids
-- mistype usernames constantly. So the failure is caught and turned into a plain "no such player" rather
-- than an error, and the client shows that instead of a dead button.
ReqLookup.OnServerInvoke = function(player, name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #name < 3 or #name > 20 then return nil end

	local id
	local ok = pcall(function() id = Players:GetUserIdFromNameAsync(name) end)
	if not ok or not id or id == player.UserId then return nil end

	-- Resolve the CANONICAL name back from the id. What they typed may differ in case, and showing a player
	-- their own typo back as if it were the account is how you send a request to the wrong person and never
	-- find out.
	local realName = name
	pcall(function() realName = Players:GetNameFromUserIdAsync(id) end)

	return { id = id, name = realName, here = Players:GetPlayerByUserId(id) ~= nil }
end

--======================================================================
-- ON JOIN: tell them who asked
--======================================================================
local function deliver(player)
	local pending = mailboxRead(player.UserId)
	if #pending == 0 then return end

	-- Mark which senders are reachable this second, so the client can offer "Trade now" instead of making
	-- the player guess and tap into a dead end.
	for _, rec in ipairs(pending) do
		rec.here = Players:GetPlayerByUserId(rec.fromId) ~= nil
	end

	pcall(function() ReqInbox:FireClient(player, pending) end)
	print(("[TradeReq] %s has %d pending trade request(s)"):format(player.Name, #pending))
end

Players.PlayerAdded:Connect(function(player)
	-- Deferred: joining is already the busiest moment in the session, and a banner that lands before the HUD
	-- exists is a banner nobody sees.
	task.delay(6, function()
		if player.Parent then deliver(player) end
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.delay(6, function() if p.Parent then deliver(p) end end)
end

Players.PlayerRemoving:Connect(function(player) lastSend[player] = nil end)

print("[TradeReq] ready -- offline trade requests by name or friends list (messages only; no item ever moves)")
