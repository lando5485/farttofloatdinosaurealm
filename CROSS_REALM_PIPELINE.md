# Fart to Float — Cross-Realm Pipeline (Dino Realm side)

This is the contract for how player data moves between the Food realm (realm 1), the Space realm (realm 2)
and the Dino realm (realm 3), and how the shared "one universe" stores work. The Dino realm side is fully
implemented as described here. The last section lists exactly what the Food and Space realms must change to
match.

All three places are in ONE Roblox experience (universe 10236070926). That matters because DataStores and
MessagingService are scoped to the experience, not the place: any two places that use the same store name
read the same data, and any place that subscribes to the same topic hears the same messages. Every "shared"
system below relies on that.

Place IDs:

| Realm | Place ID |
|---|---|
| Food (home) | 120919484545190 |
| Space | 125063266868039 |
| Dino | 110777788409412 |
| Candy | 133591422694132 (a live hop destination from Dino; not covered by this document's realm to-do list yet, but it must honour `sharedTokens` like the others) |

---

## 1. Two ways data travels

1. **Teleport payload** — a table sent with `TeleportAsync` when a player hops realms. Carries per-player
   state the destination has to know on arrival (pets, cosmetics, home place, what they earned abroad).
2. **Shared DataStores** — universe-wide stores keyed on the userId. Used for the things that must be ONE
   value no matter which realm you stand in: the token wallet, the gift mailbox, rebirths, daily/session
   rewards.

Rule of thumb: **currency and claims live in shared stores; cosmetics and pets ride the payload.**

---

## 2. The teleport payload (field contract)

Sent by `src/server/WormholeService.server.luau` (`buildTravelPayload`). Read by
`src/server/ArrivalReceiver.server.luau` (`intake`). Every receiver in the universe must tolerate missing
fields (treat `nil` as "no change").

### 2.1 Markers and routing

| Field | Type | Meaning | Dino sends | Dino reads |
|---|---|---|---|---|
| `fromFartToFloat` | bool | Universal gate. A payload without it is treated as a direct join. | `true` | required |
| `returningHome` | bool | Set when the hop's destination is the player's home place. **The Food receiver refuses any payload without it.** | when `placeId == homePlaceId` | no |
| `payloadVersion` | number | Schema version. Food's `RealmTransfer` is 2. | `2` | logged |
| `fromPlaceId` | number | Origin place (`game.PlaceId`; the constant only in Studio) | yes | logged; becomes `homePlaceId` if none given |
| `fromRealm` | string | `"dino"` / `"food"` / `"space"` | `"dino"` | logged |
| `fromDinoRealm` | bool | Legacy marker older receivers key on | `true` | no |
| `homePlaceId` | number | Where "back" is. Defaults to Food. Forwarded unchanged if the player arrived with one (Food → Space → Dino still goes home to Food). | yes | stashed |
| `userId` | number | Anti-crosswire stamp. A mismatch is refused and treated as a direct join. | yes | **checked** |
| `sentAt` | number | `os.time()` at send | yes | no |
| `arrivedViaRift` | bool | Space-only: play the rift arrival cinematic and hold the player 7s | never | yes |
| `islandIndex` | number | Food-only landing island | no | no |

### 2.2 Pets and cosmetics (merged, never assigned)

| Field | Shape | Merge rule on arrival |
|---|---|---|
| `ownedPets` | `{ [petId] = { level, xp, height, time, rare } }` | union; per-pet MAX of numbers; `rare` is sticky |
| `equippedPet` | `petId` | applied only if owned after the merge |
| `petSkins` | `{ ["Pet\|Skin\|Trait"] = count }` | per-entry MAX, **never sum** (summing doubles duplicates every round trip) |
| `equippedSkins` | `{ [petId] = { skin = id, trait = id } }` | copied; rendering re-validates ownership |
| `collection` | `{ [flag] = true \| number }` | union: `true` wins, numbers MAX, else fill-if-nil |
| `title` | string | fills an EMPTY title only; never overwrites one earned locally. Also set as the `Title` attribute (TitleTags renders it). |
| `petMilestones` | flag map | Dino has no milestone system: **stashed and forwarded unchanged** |
| `ownedGutSkins`, `equippedGutSkin` | map / id | Dino has no gut skins: **stashed and forwarded unchanged** |
| `gamepasses`, `gamepassIds` | maps | **stashed and forwarded unchanged** |

Pass-through fields only survive the session: if a player leaves Dino, rejoins directly (no payload) and
hops out, the forwarded values are gone. Their home save still has them, so nothing is lost for good.

### 2.3 Currency (both channels, on purpose)

| Field | Type | Who reads it |
|---|---|---|
| `earned.coins` | DELTA earned this visit | Food's return receiver pays it out (capped 250000). Dino never applies coins in either direction: coins are realm-local. |
| `earned.crateTokens` | DELTA earned this visit | Food's return receiver (capped 500). Dino credits it only from a sender on a private wallet. |
| `crateTokens` | ABSOLUTE balance | Space's receiver and Dino's receiver max-merge it. |
| `sharedTokens` | bool | `true` = the sender keeps tokens in the universe wallet (section 3.1). **A receiver on the same wallet must skip ALL token merging** — it already has the balance; merging would pay it twice. Dino also skips merging when `fromPlaceId` is Dino itself (its own tokens coming home from a private-wallet realm). |

Why both: Food's receiver never reads an absolute, Space's never reads the delta. Sending only one channel
(what Dino did before) meant a Dino → Space hop arrived with zero tokens.

Delta measurement (`WormholeService.earnedFor`): a baseline of coins and tokens is taken on join, but only
AFTER (a) leaderstats and the wallet have loaded and (b) `ArrivalReceiver` has raised
`_G.dinoArrivalSettled[player]`, meaning any tokens that arrived WITH the player have already been merged.
Baselining before that merge would count arriving tokens as "earned here" and send them home again. The
delta is `max(0, now - baseline)` plus any bonus registered through `_G.dinoAddEarnedCoins` /
`_G.dinoAddEarnedTokens`. If the wallet never loads there is NO baseline and the visit pays out 0.

### 2.4 Size budget

Roblox caps teleport data. `WormholeService.fit` measures the payload with `HttpService:JSONEncode` against
`BUDGET_BYTES = 28000` and sheds in this order: collapse `petSkins` counts to 1 → drop `collection` → drop
`petMilestones` → drop `petSkins` + `equippedSkins`. `ownedPets`, `earned` and the markers are never shed.
The home save still holds everything shed.

### 2.5 Arrival sequence (Dino)

1. Read `Player:GetJoinData().TeleportData`; require `fromFartToFloat == true` (otherwise: fresh start, and
   `_G.dinoArrivalSettled` is raised at once so the earned baseline can be taken).
2. Refuse if `userId` is present and is not this player.
3. If no `homePlaceId`, set it to `fromPlaceId` (unless that is this place).
4. Stash the whole payload in `_G.incomingFtFData[player]` (WormholeService reads it for pass-through and home).
5. Three INDEPENDENT tasks start: `restorePets`, `restoreCosmetics` (skins / equipped / collection / title
   fill-empty) and `carryUniversals` (tokens, title fill-empty). The two cosmetic tasks wait until
   SkinCrateBridge has loaded THIS player (the wallet entry exists) before merging, so the load can never
   overwrite the merge. Token merging is skipped when `sharedTokens == true` or when the payload came from
   Dino itself; otherwise the earned delta (capped 500) and then the absolute (max-merge) are credited through
   `_G.addCrateTokensRaw`, which clamps, pushes to the client and saves. `carryUniversals` ends by raising
   `_G.dinoArrivalSettled[player]`.
6. If `arrivedViaRift`, hold the player at the entrance for the cinematic.

---

## 3. Shared universe stores

| System | Store name | Key | Record | Owner file (Dino) |
|---|---|---|---|---|
| Token wallet | `UniverseCrateTokens_v1` | `"u_" .. userId` | `{ tokens, updatedAt, lastRealm }` | `SkinCrateBridge.server.luau` |
| Gift mailbox | `GiftMailbox_v1` | `"u_" .. userId` | list of `{ from, fromId, amount, at }` | `Gifting.server.luau` |
| Rebirths | `Rebirth_v1` | `"Player_" .. userId` | `{ rebirths, mult, updatedAt }` | `Rebirth.server.luau` |
| Login streak | `DailyStreak_v1` | `tostring(userId)` | `{ streak, lastDay }` | `DailyStreak.server.luau` |
| Session ladder | `SessionRewardsDay_v1` | `tostring(userId)` | `{ day, played, pass, mask }` | `SessionRewards.server.luau` |
| Daily ticket cap | `RewardsHubDaily_v1` | `tostring(userId)` | `{ day, paid }` (300 tickets / UTC day) | `RewardsHubCap.luau` |
| Dino skins (realm-local) | `DinoSkinState_v1` | `"skin_" .. userId` | `{ tokens (mirror only), skins, equipped }` | `SkinCrateBridge.server.luau` |

"Day" everywhere is the UTC day number `floor(os.time() / 86400)`.

### 3.1 Token wallet

- Loaded on join from `UniverseCrateTokens_v1`. If no record exists, the old realm-local `tokens` field (or 500
  for a new player) seeds it once.
- **Saved on every change** (`setTokens` calls `_G.savePlayerData`), not just on leave. The bridge coalesces a
  burst of changes into consecutive writes and never drops one.
- A failed read at join marks the wallet "not loaded": the balance is shown but **never written** that session,
  so a blank read can't erase a real wallet. No save of any kind runs before `load()` has finished, and the
  join-time balance mirror (`skinCrateApplyOnJoin`) is a no-op until then.
- A save that runs after the player has left re-uses the last captured payload rather than reading the wiped
  tables, so a slow write can never save a 0 wallet.
- Every grant path goes through `setTokens` (crate opens, purchases, `_G.crateTokensAward`, gifts, refunds,
  arrival merges). `setTokens` rejects NaN and infinity (either would corrupt the record and stop all saves).
- Robux token packs: `PurchaseReceipts` hands the receipt to `SkinCrateService` (`_G.skinCrateHandleReceipt`);
  an unrecognised product is left NotProcessedYet so Roblox retries it instead of charging for nothing.
- `TEST_MODE` (free token packs without Robux) only works in Studio. In a live server the flag is ignored and
  the real purchase prompt runs, so no client can mint tokens into the shared wallet.

### 3.2 Gifting (live, cross-realm)

Send path (`GiftTokensEvent`): validate amount (10..500, NaN/inf rejected), cooldown 8s, 20 per session,
mailbox cap 25.

- Recipient on THIS server → direct transfer.
- Otherwise → **debit the sender first**, append to the recipient's mailbox with `UpdateAsync`, refund on
  failure, then `MessagingService:PublishAsync("GiftDelivery_v1", { to = userId, from, amount, at })`.

Receive path: every server subscribes to `GiftDelivery_v1` on boot. On a message, if the recipient is on this
server, it drains their mailbox with the existing atomic read-and-clear (`claimMailbox`). **The message is only
a wake-up**; the store is the single source of truth, so a duplicated, replayed or forged message can never pay
twice or pay anything the store does not hold. Join-time drain (8s after join) remains the offline fallback.

Result: a gift sent from Dino to a friend online in any realm (once that realm subscribes) lands within
seconds; offline friends get it on next join.

### 3.3 Rebirths

- Loaded on join; sets the `Rebirths` and `RebirthMult` (`1 + 0.25 × n`) attributes and a `Rebirths`
  leaderstat.
- On rebirth: **persist first** with `UpdateAsync` (count never moves down), then reset island progress and
  gut, grant `125 × n` coins, and land on island 1. If the save fails, nothing happens.
- Rebirth is refused until the store has answered (`not_loaded`), so nothing can be done on an unsaved count.

### 3.4 Login streak, session ladder, daily cap

Dino's copies are the reference implementations: atomic `UpdateAsync` claims, UTC rollover, and every payout
routed through `RewardsHubCap` (300 tickets per UTC day across everything the hub pays).

---

## 4. What the Food and Space realms must change to be one game

Nothing below has been done yet; it is the to-do list for those places.

| Change | Food | Space | Why |
|---|---|---|---|
| Token wallet → read/write `UniverseCrateTokens_v1` (`"u_"..userId`, `{tokens}`) instead of the realm's own field; save on every change | required | required | Otherwise tokens are three separate wallets and only meet through hops. |
| On arrival, if `sharedTokens == true`, skip token merging | required | required | Prevents paying the same tokens twice. |
| Gift mailbox store name `GiftMailbox_v1` | already | rename from `SpaceGiftMailbox_v1` | One box for the universe. |
| Subscribe to `GiftDelivery_v1` and drain the local recipient's mailbox on message | required | required | Live delivery across realms. |
| Return receiver: `mergeEquippedSkins` expects a string but every realm sends `{skin, trait}` | fix | n/a | Worn looks are silently dropped on the way home today. |
| Rebirth: also set the `Rebirths` / `RebirthMult` attributes on load | already | add attributes | Dino reads attributes. |
| Rebirth reset rule | decide one | decide one | Dino keeps coins + bonus; Food/Space wipe coins. Mixed rules are exploitable. |
| Session ladder → copy Dino's `SessionRewards.server.luau` (change only the require path) | replace in-memory version | install | Food's is uncapped and resets on rejoin; Space has none. |
| Login streak → copy Dino's `DailyStreak.server.luau`; agree one day-7 crate | replace `SetAsync` version | install | Food's non-atomic claim can double-pay and overwrite Dino's record. |
| Require `RewardsHubCap.luau` on every ticket payout | install | install | 300/day only counts in Dino today. |

Store names and the `_G` hook names must match exactly; a different name is a different store.

---

## 5. Known gaps in the Dino realm

- **Daily crate spin**: the Rewards hub draws the row (`DailyStreak.client.luau`), but no server creates
  `DailyCrateRemotes`. It needs a free-spin hook (`_G.skinCrateFreeSpin`) in `SkinCrateService` and a port of
  Space's `DailyCrateService.server.luau` (store `RealmDailyCrate_v1`, key `"daily_"..userId`). The client
  falls back to the 8-hour pet crate until then.
- **Gift send cap** (20 per session) is in-memory: it resets on rejoin and is per realm.
- **Migration window**: while Food or Space still keep a private wallet, a round trip can carry the same
  tokens both ways. Dino guards its side (it never re-merges its own tokens coming home, and skips shared
  senders); the other direction closes when those realms move to the universe wallet.
- **CrateTokens leaderstat**: the shared config expects a `CrateTokens` leaderstat that this realm never
  creates. The HUD reads `_G.crateTokenBalance` instead, so nothing is broken, but the mirror is inert.
- **Studio**: DataStores are blocked unless "Enable Studio Access to API Services" is on, so wallets show
  fallbacks and are not saved; rebirth is allowed in Studio for testing.

---

## 6. Test plan

1. **Wallet persistence**: spend tokens, leave, rejoin → balance holds. Output shows the universe wallet line
   from `[SkinBridge]`.
2. **Live gift**: two accounts on different servers of Dino; send a gift → recipient sees "Gift received"
   within seconds without rejoining. Output shows `mailbox + live wake-up`.
3. **Round trip**: Food → Dino → Food. Dino output shows the arrival line with `home <FoodPlaceId>`; the
   outgoing line shows `[HOME]`; Food's return receiver logs the earned coins landing.
4. **Rebirth**: reach the summit, rebirth, leave, rejoin → `Rebirths` attribute and leaderstat survive.
5. **Crosswire**: a payload stamped for another userId is refused with a warning and a fresh start.

---

## 7. File index (Dino)

| File | Role |
|---|---|
| `src/server/WormholeService.server.luau` | Builds the outgoing payload; island warps; realm hops; size budget; delta measurement |
| `src/server/ArrivalReceiver.server.luau` | Reads the incoming payload; pets, cosmetics, tokens, title, home stash |
| `src/server/SkinCrateBridge.server.luau` | Persistence: universe wallet + realm-local skins |
| `src/server/SkinCrateService.server.luau` | Token grants/debits (`setTokens`), gift hooks, crates |
| `src/server/Gifting.server.luau` | Mailbox, live delivery topic, join-time drain |
| `src/server/Rebirth.server.luau` | Rebirth store, attributes, leaderstat, reset |
| `src/server/DailyStreak.server.luau` | Login streak (reference implementation) |
| `src/server/SessionRewards.server.luau` | Playtime ladder (reference implementation) |
| `src/server/RewardsHubCap.luau` | 300 tickets / UTC day cap |
| `src/server/RealmCompletion.server.luau` | Writes `dinoComplete` for Food's rebirth gate |
