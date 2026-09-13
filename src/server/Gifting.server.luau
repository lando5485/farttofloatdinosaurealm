--======================================================================
-- Gifting.server.luau  (Script, ServerScriptService)  -- DINO PORT of Space Realm's copy (itself from the Food Realm)
--======================================================================
-- Give another player some of your Crate Tokens. Two routes:
--   * they are in this server  -> the tokens move immediately, both sides see it happen
--   * they are offline         -> the gift waits in a DataStore mailbox and lands when they next join
--
-- ===== WHAT STOPS IT BEING ABUSED =====
-- The structural property first: gifting CANNOT CREATE TOKENS.
--   * online  -> _G.giftCrateTokens debits and credits in one call with no yield between them
--   * offline -> DEBIT FIRST, then write the mailbox, and refund immediately if that write fails
-- The offline ordering is the important one and it is not interchangeable. Writing the mailbox first and
-- debiting second means a failed debit leaves the recipient owed tokens nobody paid for -- that mints
-- currency. Debiting first means the worst case is a refund.
--
-- The rest of the rules exist only to stop a bot turning this into spam: a cooldown, a per-session send cap,
-- a floor and ceiling on the amount, and a cap on how many gifts one mailbox may hold.
--
-- ===== REALM-LOCAL, BY NECESSITY =====
-- Every realm keeps its OWN Crate Token balance (Dino saves its tokens in DinoSkinState_v1), so a gift has to
-- land in the realm it was sent from. The mailbox store name carries a Dino prefix so this realm's mailboxes
-- can never be claimed by another realm that shares the universe's DataStores.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")

if _G.__GiftingServer then
	warn("[Gifting] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__GiftingServer = true

--======================================================================
-- RULES
--======================================================================
local MIN_GIFT        = 10     -- below this it is spam, not a gift
local MAX_GIFT        = 500    -- two Starter crates; a big present, not a whole account
local COOLDOWN        = 8      -- seconds between gifts from one player
local MAX_PER_SESSION = 20     -- generous for a real kid, useless to a bot
local MAX_MAILBOX     = 25     -- pending gifts one player may be holding; beyond this, senders are refused

local MAILBOX_STORE = "DinoGiftMailbox_v1"   -- bump the suffix if the record shape ever changes
local mailbox = DataStoreService:GetDataStore(MAILBOX_STORE)

--======================================================================
-- REMOTES
--======================================================================
local function remote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local GiftSend     = remote("GiftTokensEvent")     -- c->s: (targetUserId, amount) -- online OR offline
local GiftResult   = remote("GiftResultEvent")     -- s->c: (ok:bool, message) -> the SENDER
local GiftReceived = remote("GiftReceivedEvent")   -- s->c: (fromName, amount, wasOffline) -> the RECIPIENT

--======================================================================
-- STATE
--======================================================================
local lastGift  = {}   -- [player] = os.clock()
local sentCount = {}   -- [player] = gifts sent this session
Players.PlayerRemoving:Connect(function(p) lastGift[p] = nil; sentCount[p] = nil end)

local function key(userId) return "u_" .. tostring(userId) end

--======================================================================
-- MAILBOX
--======================================================================
-- Every DataStore call is wrapped: they throw on network trouble, on throttling, and -- routinely -- in
-- Studio, where API access is off by default. A thrown error here must become a polite refusal, never an
-- unhandled error that leaves the sender's tokens in limbo.

-- APPEND, via UpdateAsync so two senders in different servers cannot clobber each other's entry.
local function mailboxAppend(targetUserId, record)
	local full = false
	local ok, err = pcall(function()
		mailbox:UpdateAsync(key(targetUserId), function(old)
			local list = (type(old) == "table") and old or {}
			if #list >= MAX_MAILBOX then
				full = true
				return nil          -- returning nil aborts the write, leaving the stored value untouched
			end
			list[#list + 1] = record
			return list
		end)
	end)
	if full then return false, "Their gift box is full right now!" end
	if not ok then
		warn("[Gifting] mailbox write failed for " .. tostring(targetUserId) .. ": " .. tostring(err))
		return false, "Couldn't reach the gift box, try again in a moment."
	end
	return true
end

-- CLAIM: read and clear in ONE UpdateAsync, then credit.
--
-- Clearing BEFORE crediting is deliberate. The two orders fail differently and only one of them is safe:
--   clear -> credit fails  =  that gift is lost. Bad, and logged loudly, but it happens once.
--   credit -> clear fails  =  the same gift is claimable again on the next join, forever. That mints tokens.
-- _G.addCrateTokensRaw is an in-memory write that cannot realistically fail, so the safe order costs nothing.
local function claimMailbox(player)
	local claimed
	local ok, err = pcall(function()
		mailbox:UpdateAsync(key(player.UserId), function(old)
			claimed = (type(old) == "table") and old or nil
			if not claimed or #claimed == 0 then return nil end   -- nothing waiting: do not write at all
			return {}
		end)
	end)
	if not ok then
		-- Not fatal and NOT lost: the mailbox was never cleared, so the gifts are still there for next join.
		warn("[Gifting] mailbox read failed for " .. player.Name .. " (gifts remain pending): " .. tostring(err))
		return
	end
	if not (claimed and #claimed > 0) then return end

	local total = 0
	for _, rec in ipairs(claimed) do
		local amt = math.floor(tonumber(rec and rec.amount) or 0)
		if amt > 0 and _G.addCrateTokensRaw then
			local granted = pcall(_G.addCrateTokensRaw, player, amt, "offline gift from " .. tostring(rec.from or "?"))
			if granted then
				total = total + amt
				pcall(function() GiftReceived:FireClient(player, tostring(rec.from or "A friend"), amt, true) end)
			else
				warn(("[Gifting] LOST GIFT: could not credit %d tokens to %s from %s")
					:format(amt, player.Name, tostring(rec.from or "?")))
			end
		end
	end
	if total > 0 then
		print(("[Gifting] %s claimed %d pending gift(s) worth %d tokens"):format(player.Name, #claimed, total))
	end
end

--======================================================================
-- SEND
--======================================================================
GiftSend.OnServerEvent:Connect(function(sender, targetUserId, amount)
	-- EVERY value below arrives from the client and is a lie until proven otherwise. The amount especially is
	-- never trusted as a number: a crafted call can send a table, a string, inf or nan.
	targetUserId = tonumber(targetUserId)
	amount = math.floor(tonumber(amount) or 0)

	local function fail(msg) pcall(function() GiftResult:FireClient(sender, false, msg) end) end

	if not targetUserId or targetUserId <= 0 then return fail("Pick someone to gift to.") end
	if amount < MIN_GIFT then return fail(("Gifts start at %d tokens."):format(MIN_GIFT)) end
	if amount > MAX_GIFT then return fail(("You can gift up to %d tokens at once."):format(MAX_GIFT)) end
	if targetUserId == sender.UserId then return fail("You can't gift yourself!") end

	local now = os.clock()
	local last = lastGift[sender]
	if last and (now - last) < COOLDOWN then
		return fail(("Wait %d more seconds."):format(math.ceil(COOLDOWN - (now - last))))
	end
	if (sentCount[sender] or 0) >= MAX_PER_SESSION then
		return fail("That's all the gifts for this session!")
	end

	----------------------------------------------------------------
	-- ONLINE: hand it over directly
	----------------------------------------------------------------
	local target = Players:GetPlayerByUserId(targetUserId)
	if target then
		if not _G.giftCrateTokens then
			warn("[Gifting] SkinCrateService has not published _G.giftCrateTokens -- gifting is inert")
			return fail("Gifting isn't ready yet, try again in a moment.")
		end
		local ok, why = _G.giftCrateTokens(sender, target, amount)
		if not ok then
			return fail(why == "not enough tokens" and "You don't have that many tokens."
				or ("Couldn't send: " .. tostring(why)))
		end
		lastGift[sender] = now
		sentCount[sender] = (sentCount[sender] or 0) + 1
		if _G.badgeGiftSent then pcall(_G.badgeGiftSent, sender) end
		pcall(function()
			GiftResult:FireClient(sender, true, ("Sent %d tokens to %s!"):format(amount, target.DisplayName or target.Name))
		end)
		pcall(function() GiftReceived:FireClient(target, sender.DisplayName or sender.Name, amount, false) end)
		print(("[Gifting] %s gifted %d tokens to %s (online)"):format(sender.Name, amount, target.Name))
		return
	end

	----------------------------------------------------------------
	-- OFFLINE: debit, then post
	----------------------------------------------------------------
	if not (_G.debitCrateTokensForGift and _G.addCrateTokensRaw) then
		warn("[Gifting] SkinCrateService has not published the debit/credit hooks -- offline gifting is inert")
		return fail("Gifting isn't ready yet, try again in a moment.")
	end

	-- The NAME is resolved server-side rather than taken from the client. A client-supplied name would let
	-- anyone post a gift that appears to come from someone else, which is a ready-made social-engineering
	-- hook ("look, a mod sent you tokens"). It is also just cheap to look up.
	local targetName
	local okName = pcall(function() targetName = Players:GetNameFromUserIdAsync(targetUserId) end)
	if not (okName and targetName) then
		return fail("Couldn't find that player.")
	end

	-- DEBIT FIRST. See the header: the reverse order is a minting bug, not a stylistic choice.
	local debited, whyNot = _G.debitCrateTokensForGift(sender, amount)
	if not debited then
		return fail(whyNot == "not enough tokens" and "You don't have that many tokens."
			or ("Couldn't send: " .. tostring(whyNot)))
	end

	local posted, reason = mailboxAppend(targetUserId, {
		from   = sender.DisplayName or sender.Name,
		fromId = sender.UserId,
		amount = amount,
		at     = os.time(),
	})
	if not posted then
		-- REFUND, immediately and in full. This is the only failure this design allows and it must never
		-- silently cost the sender anything.
		pcall(_G.addCrateTokensRaw, sender, amount, "refund: offline gift could not be posted")
		print(("[Gifting] refunded %d tokens to %s -- mailbox write failed"):format(amount, sender.Name))
		return fail(reason or "Couldn't send that right now -- your tokens are safe.")
	end

	lastGift[sender] = now
	sentCount[sender] = (sentCount[sender] or 0) + 1
	if _G.badgeGiftSent then pcall(_G.badgeGiftSent, sender) end
	pcall(function()
		GiftResult:FireClient(sender, true,
			("Sent %d tokens to %s -- they'll get it next time they play!"):format(amount, targetName))
	end)
	print(("[Gifting] %s gifted %d tokens to %s (OFFLINE, queued)"):format(sender.Name, amount, targetName))
end)

--======================================================================
-- CLAIM ON JOIN
--======================================================================
local function onJoin(player)
	-- Wait for the skin service to have loaded this player's token balance before crediting into it --
	-- otherwise a claim can land first and be overwritten by the load a moment later.
	task.delay(8, function()
		if player.Parent then claimMailbox(player) end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
Players.PlayerAdded:Connect(onJoin)

--======================================================================
if RunService:IsStudio() then
	print("[Gifting] NOTE: offline gifts use a DataStore. In Studio that needs Game Settings > Security > "
		.. "Enable Studio Access to API Services, or every offline send will refuse and refund.")
end
print(("[Gifting] ready -- %d..%d per gift, %ds cooldown, %d/session, mailbox holds %d. Online gifts are "
	.. "instant; offline gifts debit first, then queue. Realm-local (see the header)."):format(
	MIN_GIFT, MAX_GIFT, COOLDOWN, MAX_PER_SESSION, MAX_MAILBOX))
