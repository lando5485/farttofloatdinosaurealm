# PET SYSTEM EXPORT — Fart to Float FOOD REALM → Dino Realm

**To the Claude doing the import:** this bundle is the complete pet system of the main Food Realm
place (`Fart to Float`, repo `Fart2floatstuff`, place = home hub of the whole experience, Universe
10236070926). Files were copied from the **working tree on 2026-08-29** — that matters because two
files (`src/shared/PetTier.luau`, `src/client/TestPetPreview.client.lua`) are **not committed to git
at all** yet and many others carry uncommitted edits. The disk state, not the last commit, is what
runs and is what you have here.

The destination place's ReplicatedStorage shared folder is named **`DinosaurRealm`**; this realm's is
named **`Shared`** (`ReplicatedStorage/Shared`, from `default.project.json`). Section 3 lists every
file that hard-codes `"Shared"` — that string is the #1 thing you must remap.

The source code is unusually well commented — most files open with a long header explaining exactly
what they own and why. When this doc and a file header disagree, trust the file.

---

## 1. FILE LIST (what each file is, and what's NEW)

### Recency legend
- **NEW** = untracked in git (created since the last commit — the very latest work).
- **RECENT** = last commit 2026-08-18 ("Pet hub restructure...") **plus uncommitted working-tree
  edits** on top. The traits/skins/Overall-Tier fusion work ("levels become AGE, skins/traits split
  apart", "Re-fuse skin+trait", "traits get their own crate") all landed in this window.
- **KIT** = a deliberately self-contained portable copy, **not synced by Rojo** (absent from
  `default.project.json` on purpose — `EggSystem_AllInOne` even documents why syncing it broke two
  quests). These exist precisely for transfers like this one.

### `src/shared/` — config modules (ReplicatedStorage/Shared)
| File | Role |
|---|---|
| `PetSkins.luau` — RECENT | The 17 skin themes (render recipes: color/material/animated/particle/deco/orbit), the 6-band tier ladder (`TIER_ORDER`/`TierColor`/`TierRank`) that PetRarity and the crates borrow, hidden `TIER_VALUE`s, **the inventory key format `pet|skin|trait`**, `SKIN:` trade prefix, legacy-id migration, `prettyPet()` names. |
| `PetTraits.luau` — RECENT | The 21 traits (full accessory geometry specs on Head/Face/Neck/Back/Body attach points), trait `TIER_ODDS` (sum 100, asserted), hidden values, `PET_OFFSETS` per-pet nudges, legacy map, the server `roll(rng)`. |
| `PetTier.luau` — **NEW, uncommitted** | Overall Tier: skin hidden value + trait hidden value = score → one tier label (thresholds 18/11/6/3/0). Never Gold. This is the newest piece of the traits/skins system. |
| `PetRarity.luau` — RECENT | The permanent rarity axis (borrowed from PetSkins' ladder), `FUSE_COST` {5,6,7,8,10}, `normalise`/`canFuse`. Rarity ≠ age; conflating them is the bug this module exists to prevent. |
| `PetCollection.luau` | Collection Book (trait-agnostic skin completion incl. the always-owned "Default"), AURAS table, per-pet REWARDS (title/aura/badgeId=0 placeholders/cosmetic), FULL_COLLECTION ("Living Legend" + Cosmic on every pet). |
| `SkinCrates.luau` — RECENT | All 6 crates (PetLevels 75 / Pets 160 / Traits 200 / Starter 100 / Premium 250 / Elite 600 / Mythic 1200 limited), per-crate odds (asserted sum 100), `kind` = levels/pets/trait/skins, TRADE_UP (10→1 next tier), **live Robux token-pack Developer Product ids**, `TEST_MODE=false`, luck multiplier, the server `roll()` returning the reel index. |
| `CrateTokens.luau` — RECENT | The cosmetic currency: earn amounts, island-task ladder (islands 2/5/8/10/13 → 100/125/150/175/200), login streak, per-source daily anti-farm caps, `MAX_BALANCE` 1,000,000. |
| `RealmTransfer.luau` | **THE cross-realm payload builder** (server-only module). One definition of what a player carries between realms. See §5. |
| `Gamepasses.luau` — RECENT | Single source of gamepass ids (TwoXForever/GlitterTrail/InfiniteGut/LuckyPass/CoinMagnet/VIP, all live) + Space-realm legacy ids that must keep granting. LuckyPass affects crate odds (luck). |
| `GutSkins.luau` — *doubt: not pets* | Gut (belly) cosmetic skins, playtime-unlocked. Included because `ownedGutSkins`/`equippedGutSkin` **travel in the cross-realm payload** and merge on return. |
| `Constants.luau` — **NEW, uncommitted** | `Constants.CRATE` for the Mystery Meteor Crate: 8h cooldown, rarity→levels (1/2/4/6), PET_MAX_LEVEL 25 mirror, fallback 500 coins. |
| `Remotes.luau` | Accessor for the `StateRemotes` folder (StateChanged/RequestState) — the PlayerState snapshot stream the meteor-crate UI reads (`lastCrateClaim`). |
| `CosmeticConfig.luau` / `CosmeticIcon.luau` — *doubt* | Space-Realm-style cosmetic list (47 items incl. a "Pets" cosmetic type) + icon builder. Required by `PlayerState.luau` (and SecurityWatchdog's manifest), which CrateService requires — so they ride along. They are NOT the main pet system. |

### `src/server/` — services (ServerScriptService)
| File | Role |
|---|---|
| `PetSystem.server.lua` (3,180 ln) — RECENT | **The heart.** Pet catalog (14 species: 5 island-quest pets, BeanBuddy starter, PizzaDragon 10/10 secret, 4 seasonal, 3 rebirth recolours), **server-built CSG Union model templates** (parented to ReplicatedStorage as `<PetId>Template` at boot), quest state + marker scan, hatch/claim (incl. legacy 1-in-750 rare roll, ButterDuck 1-in-10,000 Cosmic Duck), XP/leveling (cap 25, `80*L^1.6`), storage keys + stacking, **fusion**, equip/unequip, **the whole P2P trade session** (offer/countdown/final anti-scam machine; skins ride via `SKIN:` keys), collection milestones + titles, island-task token grants, Robux tier-skip receipts, `PetEquipBroadcast`, ~30 `_G` hooks (see §3). |
| `SkinCrateService.server.lua` (1,423 ln) — RECENT | Authority for **tokens, skin inventory, equipped skins, crate opens** (roll server-side, client only animates), trade-up contracts, collection checking, token-pack receipts, gifting debit/credit, `pendingLevels` from the Pet Level Crate, the Pet-Wheel runtime removal sweep, all `_G.crateTokens*`/`_G.skinTrade*`/`_G.skinGrant` hooks. |
| `PlayerStats.server.lua` (2,757 ln) — RECENT | ⚠ **Much more than pets** — the whole save/load/economy service. Included because it is the **sole DataStore writer for all pet state** (`PlayerData_v1`, see §4), creates leaderstats incl. `CrateTokens`, calls `_G.petsApplyOnJoin`/`_G.skinCrateApplyOnJoin` after load, grants the starter pet to brand-new saves (with a 15s wait-for-hook loop), routes **ProcessReceipt** to `_G.petsHandleReceipt` → `_G.skinCrateHandleReceipt`, feeds pet XP (`_G.petOnGas`/`petOnCoins`/`petOnFlightTick`/`petOnIsland`), exposes `_G.savePlayerData`. **Do NOT import it wholesale** — mine the pet-relevant sections. ⚠ It currently has `DISABLE_SAVE_FOR_TESTING = true` in this realm. |
| `PetBarn.server.lua` — RECENT | The pet hut on Bean Farm: builds the hut/beds at a Part named `pethouse`, nap roster broadcast to all clients, coin trickle (≤30/min, owner-online only), away-keep window. Clients render sleepers from the same templates. |
| `CrateService.server.luau` | Mystery Meteor Crate authority: `CrateRemotes` folder, 8h claim, rarity roll → pet levels via `_G.petGrantLevels`, daily free crate via `_G.skinCrateFreeOpen("Premium")`, `DevForceCrate` BindableEvent. |
| `PlayerState.luau` (ModuleScript) | Separate persistence for the meteor crate (`CrateState_v1` DataStore): `lastCrateClaim`, space-style cosmetics, the StateRemotes snapshot stream. |
| `TradeRequests.server.luau` — RECENT | Offline trade *invitations* (messages only, never items): mailbox DataStore, username lookup, opens the real PetSystem trade when both online. |
| `RealmReturnReceiver.server.lua` | **The arrival receiver for players coming HOME.** Merge-never-assign rules — see §5. |
| `DinoRealmTeleport.server.lua` | **The door to the Dino Realm** (place id 110777788409412, ⚠ tester-locked). Client fires `DinoRealmEnterEvent` (no args) → server validates → `RealmTransfer.build(player,"dino")` → `TeleportAsync`. |
| `RealmPortals.server.lua` — RECENT | The 3-portal row on Bean Island (Space→Dino→Candy chain, gated on cross-place DataStore completion flags `SpaceRealm_PlayerState_v1.highestPlanetReached>=8` / `DinoRealm_PlayerState_v1.dinoComplete==true`). Uses RealmTransfer too. Remote: `RealmPortalEvent`. Synced under the name `RealmPortalsHub` to dodge a baked-in stale copy. |
| `BlackHoleTeleport.server.lua` | The black-hole door to the Space Realm (125063266868039, tester-locked). Also RealmTransfer. Remote: `BlackHoleEnterEvent`. |
| `GutSkinService.server.lua` — *doubt* | Gut-skin unlock/equip authority (playtime grants). Travels with the payload's gut-skin fields. |
| `DevCommands.server.luau` — RECENT | Dev chat commands (allowlist-gated) incl. `/newlevel` → `_G.petTierSkip`. Reference for test tooling; REMOVE-BEFORE-LAUNCH class. |
| `PetUpgrades_AllInOne.server.lua` — KIT | Verbatim standalone copy of the XP/level/evolve/Robux-skip backbone with its own in-memory store + demo. **Not the live code** (that's inside PetSystem) — it's the drop-in seed for a new place. |

### `src/client/` — LocalScripts (StarterPlayerScripts)
| File | Role |
|---|---|
| `PetFollow.client.lua` (7,391 ln) — RECENT | **The follower + quests client.** Clones the server-built `<PetId>Template` from ReplicatedStorage (15s wait + client-built fallback), spring-glide follow (works during fast flight), per-part idle animator, the FULL level→look ladder (size 60→100%, aura@2, trail@5, sparkles@8, orbs, ring, pulse, burst, gold+shimmer@25, accessory schedule 3/7/10/13/17/20/23), rare looks, nameplates ("Baby Epic"), **all five island quest minigames** (broccoli pull, coconut crack, film reels, **the real fishing quest**, hot/cold dig), egg + hatch flow, the Pet Hub UI, locked-pet cards, client PET_SKIP_PRODUCTS mirror (placeholder ids!). ⚠ Sits at Luau's **200-local file-scope ceiling** — that is WHY RemotePets/PetRenderGuard/PetSkinLook are separate files. Don't merge things into it. |
| `PetSkinLook.client.lua` — RECENT | **The cosmetics renderer.** `_G.applyPetSkinLook(model, petId, lite)` paints skin (recolour/material/animated cycles/particles/deco/orbiters) + builds trait accessories on attach points derived from the pet's body mass (protrusion-filtered), snapshots originals for clean un-equip, collection auras, `/testpet` try-on override, `_G.petSkinEquipped`, `_G.petSkinRarityOf`. PetFollow calls it via two guarded one-liners. |
| `PetRenderGuard.client.luau` — RECENT | Watchdog for the two "pet didn't load" failures (stuck-invisible after PreloadAsync; wrong-body fallback when the template raced CSG). Fixes from outside because PetFollow can't take another local. |
| `RemotePets.client.lua` — RECENT | Renders **other players'** equipped pets from `PetEquipBroadcast` (userId/petId/level/isRare/variant/skin/trait). Duplicated visual pipeline from PetFollow (`PET_THEME` must list every species — **change one, change both**). |
| `PetBarn.client.lua` — RECENT | Barn panel UI + renders everyone's sleeping pets on the beds from the roster broadcast. |
| `SkinCrateClient.client.lua` (3,009 ln) — RECENT | The crate shop / CS:GO reel / skin inventory / token packs, 700×520 panel. Reel lands on the server's index — client never decides. |
| `CrateClient.client.luau` | Meteor-crate presentation: pet picker, `ClaimCrate:InvokeServer(petId)`, reveal; `_G.crateIsClaimable`; opened by the `OpenMeteorCrate` BindableEvent from the More menu. |
| `TokenHud.client.luau` — RECENT | The tokens+coins currency capsule HUD (reads leaderstats `CrateTokens`). |
| `TestPetPreview.client.lua` — **NEW, uncommitted** | `/testpet` dev panel: every skin × selected pet, every trait on Classic. The tuning surface for `PetTraits.PET_OFFSETS`. [REMOVE BEFORE LAUNCH] |
| `TradeRequests.client.luau` — RECENT | Offline-trade-request UI (send by username, inbox, one-tap open real trade). |
| `SeasonalPetsChest.client.luau` | Mostly retired: `_G.openSeasonalPets()` + a sweep deleting the old world box. The actual Seasonal Pets panel lives in CoreClient (`LockerGui`) — an integration point, see §7. |
| `RealmPortals.client.luau` — RECENT | Client half of the 3 portals (visuals, prompts, status banners, outro). |
| `DinoPortal.client.luau` | Client half of the standalone Dino door: finds a Part/Model named `DinoPortal`, fires intent, renders status via NotifyCenter banners. |
| `GutSkinClient.client.lua` — *doubt* | Gut-skin menu/renderer. |
| `PetHub_AllInOne.client.lua` — KIT, RECENT | Self-contained Pet Hub (button + hub + quests tab + full trade UI) with guarded remotes + demo inventory. Runs standalone in an empty place. |
| `PetLooks_AllInOne.client.lua` — KIT | 3 pet builders + idle animator, verbatim, zero deps. |
| `PetMoveUpgrades_AllInOne.client.lua` — KIT | Follow movement + the exact level→look schedule + trail, with a demo harness (`]`/`[`/R/P keys). |
| `EggSystem_AllInOne.client.lua` — KIT | Quest→egg→hatch flow, standalone. **Header explicitly says do not add to project.json** (double-run bug documented inside). |

### `docs/`
- `FoodRealmPets_Data.md` — **written specifically for the Dino Realm**: complete data reference
  (catalog, ages, skins, traits, rares, crates, storage). Read it right after this file.
- `LockedPetCard_Look.md` — the exact locked-pet-card design (full-colour pet + 🔒 badge, never greyed).

### `SpaceRealm/` — reference: the RECEIVER side from the previous port
- `PetReceiver.server.luau` — the Space place's arrival receiver (reads TeleportData, stages
  `_G.playerOwnedPets`/`_G.playerEquippedPet`, calls `_G.petsApplyOnJoin`). The Dino side's
  `ArrivalReceiver.server.luau` follows this pattern (note: it predates the v2 payload — your
  receiver should handle the full §5 field list).
- `PetTemplates.server.luau`, `SpacePetFollower.client.luau`, `SpacePetLeveling.server.luau` — the
  minimal template/follower/leveling trio a foreign place needs to render + level visiting pets.

### `default.project.json`
Reference copy of the Rojo tree — shows the exact instance names/paths for every file above (§8).

---

## 2. ARCHITECTURE — who owns what, and the full flow

**State ownership (all server, all in `_G` per-player tables, all persisted by PlayerStats):**
- `PetSystem.server.lua` owns pets: ownership/stacks, equip, XP/levels, quests, fusion, trades,
  milestones, titles. It also **builds every pet model template at boot** (CSG UnionAsync is
  server-only) and parents them to ReplicatedStorage as `BeanBuddyTemplate`, `BroccoliPetTemplate`…
- `SkinCrateService.server.lua` owns cosmetics: crate tokens, skin inventory, equipped skin+trait
  per pet, crate rolls, trade-ups, collection rewards.
- `PlayerStats.server.lua` owns persistence (one save doc) and is the only DataStore writer.
- Clients render only. `PetFollow` renders YOUR pet; `RemotePets` renders everyone else's;
  `PetSkinLook` paints skin+trait on any pet model either of them builds.

**Flow: "player gets a pet" → "pet follows with skin + traits applied"**
1. A grant path writes `_G.playerOwnedPets[player][storageKey] = {level=1,xp=0,height=0,time=0,count=1}`.
   Grant paths: island quest claim (`PetClaimEvent`→`completeQuest`), starter (`_G.grantStarterPet`,
   called by PlayerStats for brand-new saves), seasonal (`_G.grantSeasonalPet` from CommunityGarden),
   rebirth (`_G.grantRebirthPet` from RebirthSystem), collection milestones (PizzaDragon), and the
   **Pet Crate** (`_G.grantPetAtRarity` — the ONLY path that can grant above Common).
2. First pet auto-equips (`_G.playerEquippedPet[player] = storageKey`).
3. `sendState(player)` fires `PetStateEvent` → PetFollow clones `<species>Template` from
   ReplicatedStorage, scales it by age (level), applies the level→look ladder, then calls
   `_G.applyPetSkinLook(pet, petId)`.
4. PetSkinLook asks `SkinRemotes.GetSkinState` / listens to `SkinStateEvent` for
   `equipped[petId] = {skin, trait}` and paints skin + builds trait accessories.
5. `broadcastEquip` fires `PetEquipBroadcast` to ALL clients with
   `{userId, petId, level, isRare, variant, skin, trait}` → RemotePets renders it for everyone else.
6. Flight/coins/food feed XP through `_G.petOnCoins/petOnFlightTick/petOnGas/petOnIsland`
   (called from PlayerStats' coin/food/island handlers) → `awardXP` → level-ups → re-broadcast.
7. PlayerStats autosave/leave-save serialises all the `_G` tables into `PlayerData_v1`.

**The two-axis rule (load-bearing, repeated all over the code):**
- **AGE** = level 1–25, grown by playing, shown as Baby(1-5)/Kid(6-10)/Teen(11-15)/Adult(16-20)/Elder(21-25). Everyone can max it.
- **RARITY** = Common→Gold, frozen at grant. Only the Pet Crate and fusion move it. Quest pets are always Common.
- **Overall Tier** (new) = skin value + trait value → one label above the pet (never Gold, never stacked labels).

---

## 3. DEPENDENCY MAP

### ReplicatedStorage paths — ⚠ every `"Shared"` below must become `"DinosaurRealm"` on the dino side
Files containing the literal `"Shared"` (each 1×, unless noted): `PetCollection.luau`,
`PetRarity.luau`, `PetTier.luau`, `SkinCrates.luau`, `PetSystem.server.lua` (2×),
`SkinCrateService.server.lua`, `CrateService.server.luau`, `PlayerState.luau`,
`PlayerStats.server.lua` (3×), `DinoRealmTeleport.server.lua`, `RealmPortals.server.lua`,
`BlackHoleTeleport.server.lua`, `GutSkinService.server.lua`, `PetSkinLook.client.lua`,
`RemotePets.client.lua`, `SkinCrateClient.client.lua`, `CrateClient.client.luau`,
`TestPetPreview.client.lua`, `GutSkinClient.client.lua`, `PetHub_AllInOne.client.lua`.
(`PetFollow.client.lua` has **zero** — it only touches RS-root remotes + templates.)
Also `Remotes.luau` creates the folder `ReplicatedStorage/StateRemotes`, SkinCrateService creates
`ReplicatedStorage/SkinRemotes`, CrateService creates `ReplicatedStorage/CrateRemotes`; pet
templates land at RS **root** as `<PetId>Template`.

### RemoteEvents/Functions (creator in parens; all created server-side with a getOrCreate pattern, so a missing project entry can't break them)
**RS root, PetSystem:** `PetCollectEvent`, `PetClaimEvent`, `PetRequestStateEvent`,
`PetGetMarkers` (RF), `PetStateEvent`, `PetEquipEvent`, `PetInventoryEvent`, `PetUpgradeEvent`,
`PetProgressEvent`, `PetPendingUpgradeEvent`, `PetQuestDiscoveredEvent`, `PetFishRollEvent` (RF),
`PetDigEvent`, `PetRareEvent`, `PetRareAnnounceEvent`, `IslandTaskRewardEvent`,
`PetMilestoneEvent`, `StarterPetEvent`, `PetEquipBroadcast`, `PetFuseEvent`, `PetFuseResultEvent`,
`PetTradeRequestEvent`, `PetTradeRespondEvent`, `PetTradeOfferEvent`, `PetTradeConfirmEvent`,
`PetTradeTokensEvent`, `PetTradeCancelEvent`, `PetTradeStateEvent`, `PetTradeRequestPromptEvent`.
**RS/SkinRemotes, SkinCrateService:** `GetSkinState` (RF), `OpenCrate` (RF), `TradeUp` (RF),
`EquipSkin`, `BuyTokens`, `SetTitle`, `AssignPetLevels` (RF), `SkinStateEvent`, `GoldAnnounce`,
`CollectAnnounce`.
**RS/CrateRemotes, CrateService:** `ClaimCrate` (RF), `CrateResult`, `GetOwnedPets` (RF),
`PreviewRoll` (RF).
**RS/StateRemotes, PlayerState:** `StateChanged`, `RequestState` (via `Remotes.luau`).
**RS root, cross-realm:** `DinoRealmEnterEvent` (DinoRealmTeleport), `BlackHoleEnterEvent`
(BlackHoleTeleport), `RealmPortalEvent` (RealmPortals). PetBarn creates its own RS-root remotes
(getOrCreate at its line ~172). TradeRequests creates its own. GutSkinService creates gut-skin remotes.
`CosmeticRemotes/EquipCosmetic` (PlayerState).

### BindableEvents
- `PetInvToggle` — HUD PETS button ↔ Pet Hub toggle (created client-side).
- `OpenMeteorCrate` (ReplicatedStorage) — More-menu "Daily Rewards" row → CrateClient.
- `DevForceCrate` (ServerScriptService) — dev `/crate` path. [REMOVE BEFORE LAUNCH]

### `_G` hooks — the real internal API (server unless noted)
**PetSystem publishes:** `playerOwnedPets`, `playerEquippedPet`, `playerDiscoveredQuests`,
`playerEverCompletedQuests`, `playerPetMilestones`, `playerTitle`, `REBIRTH_PET_MILESTONES`,
`petsApplyOnJoin(p)`, `grantStarterPet(p)`, `grantSeasonalPet(p,season)`, `grantRebirthPet(p,id)`,
`grantPetAtRarity(p,id,band)`, `petsGrantCollection(p)`, `petsGrantRare(p)`,
`petGrantMythicalVariant(p,id)`, `petForceCompleteQuest(p,id)`, `petAwardXP`, `petOnCoins`,
`petOnFlightTick`, `petOnGas`, `petOnIsland`, `petAddLevels(p,key,n)`, `petGrantLevels(p,id,n)`,
`petTierSkip(p,id)`, `petsHandleReceipt(p,productId)`, `petListOwned`, `petAllSpecies`,
`petSpeciesInfo`, `petHasUnmaxed`, `petsCollectedCount`, `petsCollectableCount`, `petsTotalLevels`,
`petRebroadcastEquip`, `petQuestIslandUnder`, `grantTitle(p,title)`.
**SkinCrateService publishes:** `playerCrateTokens`, `playerPetSkins`, `playerEquippedSkins`,
`playerCollection`, `addSkinTokens`, `spendSkinTokens`, `getSkinTokens`, `crateTokensAward(p,source,arg,override)`,
`crateTokensBalance`, `crateTokensCanAfford`, `crateTokensTrade(from,to,n)`, `giftSkinTokens`,
`debitSkinTokensForGift`, `skinCrateFreeOpen(p,crateId)`, `skinGrant(p,pet,skin,trait,n)`,
`skinCrateHandleReceipt`, `skinCrateApplyOnJoin(p)`, `skinOwnsEntry`, `skinEquippedFor(p,petId)`,
`skinPushState`, `skinOwnedSetsByPet`, `skinCheckCollection`, and the 5 trade hooks
`skinTradeBrief/Owns/Unit/RemoveOne/AddOne/After`.
**PlayerStats publishes (pet-relevant):** `savePlayerData(p,reason)`, `isAllowedTestUser(p)`,
`wormholeWarp`. **Clients publish:** `applyPetSkinLook(model,petId,lite)`, `petSkinEquipped`,
`petSkinRarityOf`, `petSkinTryOn` (PetSkinLook); `crateIsClaimable` (CrateClient);
`openSeasonalPets` (SeasonalPetsChest); `housePanel` conventions elsewhere.
**Cross-realm:** `incomingRealmReturn` (RealmReturnReceiver), `petBarnNapKeyOf` (PetBarn).
⚠ Load order is never assumed: every consumer guards with `if _G.x then pcall(...)` and every
owner declares tables `_G.t = _G.t or {}`. Keep that discipline on the dino side.

### Player attributes
`Title` (PetSystem mirrors `_G.playerTitle`), `SeenGardenIntro` (PlayerStats — **the "save has
landed" signal RealmReturnReceiver waits on**, alongside `_G.playerOwnedPets[p] ~= nil`),
`HasTwoXForever`/`HasGlitterTrail`/`HasInfiniteGut` (PlayerStats; read by RealmTransfer).

### leaderstats
`CrateTokens` (IntValue, created by PlayerStats from `saved.crateTokens`; SkinCrateService mirrors
the `_G` balance onto it), `Coins`, `TotalCoinsEarned` (coin merge target on realm return).

### DataStores
| Store | Key | Owner | Holds |
|---|---|---|---|
| `PlayerData_v1` | per-user | PlayerStats | THE save. Pet fields: `ownedPets`, `equippedPet`, `discoveredQuests`, `everCompletedQuests`, `petMilestones`, `title`, `crateTokens`, `petSkins`, `equippedSkins`, `collection`, `ownedGutSkins`, `equippedGutSkin` (+ all non-pet game state). |
| `CrateState_v1` | UserId | PlayerState | `lastCrateClaim`, `lastStayReward`, meteor-crate cosmetics owned/equipped. |
| `SpaceRealm_PlayerState_v1` | UserId | Space place (read here by RealmPortals/PlanetSelect) | `highestPlanetReached` — gates the Dino portal. |
| `DinoRealm_PlayerState_v1` | UserId | **the Dino place (yours to write!)** | `dinoComplete == true` unlocks the Candy portal here. Fail-closed reads. |
| `TradeRequests` mailbox (`STORE_NAME` in TradeRequests.server) | per-user | TradeRequests | pending trade invitations. |
| `RarestPulls_v1` | — | BlimpService (NOT exported) | rarest-crate-pull leaderboard display. Integration only. |

---

## 4. DATA MODEL (byte-exact — saves and TeleportData both use these shapes)

**Pet storage key** (the unit of ownership/equip/trade/fusion):
`"BroccoliPet"` = Common stack (bare species id — pre-rarity saves load unchanged);
`"BroccoliPet#Uncommon"` / `#Rare` / `#Epic` / `#Legendary` / `#Gold` = one stack per band;
`"BroccoliPet#R"` = LEGACY old rare flag, read as Gold, never written again.

**Owned pet entry:** `ownedPets[storageKey] = { level=1..25, xp=number, height=studs (peak),
time=seconds, count=stack size (≥1, legacy nil→1), rare=true|nil (legacy) }`. Rarity is **derived
from the key**, never trusted from a stored field. Legacy value `true` instead of a table is
normalised on read.

**Equipped pet:** `equippedPet = storageKey | nil` (ONE pet follows).

**Skin inventory:** `petSkins["<petId>|<skinId>|<traitId>"] = count` (traitId `""` only on legacy
entries; every crate pull rolls a trait). Parse with `PetSkins.parseKey` — reject malformed keys.

**Equipped skins:** `equippedSkins[petId] = { skin="Cosmic", trait="King" }` — keyed by SPECIES id.

**Collection:** `collection[...]` flag map (per-pet completion, `titles`, `auras`, `activeTitle`,
`activeAura`, `full`); may nest one level. **Milestones:** `petMilestones["3"]=true` — **string
keys on purpose** (DataStore JSON round-trip; numeric keys don't survive).

**Tokens:** integer, clamped 0..1,000,000. **Title:** string or nil.
**Gut skins:** `ownedGutSkins = {Default=true, Gold=true,...}`, `equippedGutSkin = "Default"`.

**Rarity/id conventions:** bands = `Common, Uncommon, Rare, Epic, Legendary, Gold` (PetSkins.TIER_ORDER
is the single authority; skins never Gold; traits never Gold; Overall Tier never Gold). Pet ids are
CamelCase keys — display names come from the catalog (`BroccoliPet` → "Broccoli Bunny";
`PetSkins.prettyPet` + `PRETTY_OVERRIDES` for client-side prettying). Trait never joins the display
name ("Cosmic Duck" + "Trait: King", NEVER "Cosmic King Duck"). Legacy skin ids (Galaxy→Cosmic,
Stone→Classic…) and trait ids (Crowned→King…) are normalised on every entry point — never wiped.

---

## 5. CROSS-REALM TRAVEL (byte-compatible or hops break — this is the contract)

**Sender (this side):** `RealmTransfer.build(player, realmKey, extra)` — used by ALL THREE doors
(RealmPortals, DinoRealmTeleport, BlackHoleTeleport). Payload v2 fields:

```lua
{
  fromFartToFloat = true,          -- THE marker every receiver checks. Do not rename.
  payloadVersion  = 2,             -- v2 added gamepasses + gamepassIds
  fromPlaceId     = <this place>,  homePlaceId = <this place>,  -- receiver stashes homePlaceId; ReturnSender teleports to it
  toRealm         = "dino",        userId = <int>,   sentAt = os.time(),
  ownedPets       = { [storageKey] = {level,xp,height,time,count,rare?} },
  equippedPet     = storageKey | nil,
  petSkins        = { ["Pet|Skin|Trait"] = count },
  equippedSkins   = { [petId] = { skin, trait } },
  collection      = {...}, petMilestones = {...},
  title           = string|nil,
  crateTokens     = int,           -- ABSOLUTE balance (carried so the far realm can show/spend UI); return trip sends only the DELTA
  ownedGutSkins   = {...}, equippedGutSkin = "Default",
  gamepasses      = { TwoXForever=bool, GlitterTrail=bool, InfiniteGut=bool },
  gamepassIds     = { TwoXForever=1862015450, GlitterTrail=1859714979, InfiniteGut=1860686821 },
  realm           = <RealmPortals passes this via `extra`>,
}
```

**Byte budget:** `BUDGET_BYTES = 28000` JSON-encoded (TeleportAsync THROWS over the cap — it does
not truncate). Shed order when over: (1) collapse skin duplicate counts to 1, (2) drop
`collection`+`petMilestones` (re-derivable at home), (3) drop `petSkins`+`equippedSkins` (pets
travel undressed). **Pets are NEVER dropped.** Each shed warns. Keep this exact behaviour on your
ReturnSender or a completionist's portal stops working.

**What deliberately does NOT travel:** coins, island, stomach, fartMeter — absolutes owned by each
place's own DataStore. A returning snapshot assigning them would wipe home progress.

**Receiver at home (`RealmReturnReceiver.server.lua`) — what YOUR ReturnSender must satisfy:**
- Return payload must have `returningHome == true` AND `fromFartToFloat == true`, plus `userId`
  (checked against the arriving player — mismatch refuses the whole merge), `fromRealm`, `fromPlaceId`.
- **Merge rules (never assign):** pets = union; per-pet numbers = max; `rare` sticky-true;
  new pets copied field-by-field (never the raw table — no smuggled keys). petSkins counts = **max,
  never sum** (summing doubles duplicates per hop). equippedSkins = far-side preference wins but
  only if the skin is owned post-merge. collection/milestones = flag-map union (true wins, numbers
  max). gut skins = union, Default always owned. equippedPet honoured only if owned here. Title
  fills an empty slot only.
- **Currency = DELTA only:** the return payload carries `earned = { coins = <earned abroad>,
  crateTokens = <earned abroad> }` — clamped here to 250,000 coins / 500 tokens per trip. Never
  send absolutes for currency.
- **Ordering:** the receiver waits (≤60s) for the home save to land (signals: `SeenGardenIntro`
  attribute + `_G.playerOwnedPets[p]` non-nil) before merging, then calls `_G.petsApplyOnJoin` +
  `_G.skinCrateApplyOnJoin` to re-render, and lets the normal autosave persist. If the save never
  loads it merges NOTHING (correct: an unpersistable merge is a lie).
- The dino-side receiving pair is named `ArrivalReceiver.server.luau` + `ReturnSender.server.luau`
  (per RealmTransfer's header). A place boundary is a hard wall — the dino side keeps its **own
  copy** of the field list; if you add a field there, add it in RealmTransfer here too.
- `SpaceRealm/PetReceiver.server.luau` in this bundle shows the arrival-staging pattern (it predates
  v2 — extend it with the full field list above).

---

## 6. INTEGRATION POINTS (code OUTSIDE this bundle that calls in — wire equivalents on the dino side)

- **CoreClient.client.lua** (the giant main client, NOT exported): owns the HUD (PETS button →
  `PetInvToggle`), the More menu (fires `OpenMeteorCrate`), the Seasonal Pets `LockerGui` panel that
  `_G.openSeasonalPets` opens, and general UI conventions (700×520 panels, `_G.housePanel`).
- **PlayerStats.server.lua** (exported, but mostly non-pet): XP feeds (`petOnGas` at food purchase,
  `petOnCoins`/`petOnFlightTick` at coin grant, `petOnIsland` ×2 at island reach), starter-pet
  grant for brand-new saves, ProcessReceipt routing, `savePlayerData`, join/leave lifecycle.
- **CommunityGarden.server.lua** (58 pet refs): calls `_G.grantSeasonalPet` in 3 places (harvest,
  global goal, admin). **RebirthSystem.server.lua**: `_G.grantRebirthPet` from `_G.REBIRTH_PET_MILESTONES`.
- **DailyTasks.server.lua**: `_G.crateTokensAward("dailyTask"/"dailyAllTasks"/"loginStreak")`.
- **SeasonPass.server.lua**: `_G.petAddLevels` premium-tier pet-level rewards.
  **SocialRewards.server.lua**: `_G.petAddLevels`. **Gifting.server.luau**: `_G.giftSkinTokens` /
  `_G.debitSkinTokensForGift` (token gifting incl. offline mailbox `MAILBOX_STORE`).
- **DevArrival.server.luau**: dev-join free crate via `_G.skinCrateFreeOpen`.
- **IslandNPCs.server.lua**: the 5 quest-island NPCs (island task ↔ `CrateTokens.ISLAND_TASK` — the
  token grant itself fires from PetSystem's `completeQuest` via `_G.crateTokensAward("islandTask", island)`).
- **Shop_AllInOne.server.lua**: second food-purchase path that feeds `_G.petOnGas`.
- **Wormhole (WormholeService/WormholeClient)**: NOT pet code (island fast-travel via
  `_G.wormholeWarp`); listed because its UI copies the Pet Hub panel geometry.
- **SecurityWatchdog.server.luau**: has a script MANIFEST listing every pet script by instance path
  — if the dino place runs one, add the pet scripts to it or they'll be flagged NOT-IN-MANIFEST.
- **NotifyCenter.client.luau**: all pet banners go through `push`/`pin` — never build a new ScreenGui.

---

## 7. STUDIO-SIDE REQUIREMENTS (things code does NOT create)

**Workspace marker Parts (hand-placed; server hides them and serves positions via `PetGetMarkers`):**
- Island models named `Island_2_*`, `Island_5_*`, `Island_8_*`, `Island_10_*`, `Island_13_*`
  (matched by prefix; this realm has a known `Island_2_BrocolliBluff` misspelling it works around).
- BroccoliPet: `BroccoliPiece1..3`, `I2PetBlock`. CoconutCrab: `Coconut1..7`, `CoconutChest`.
  PopcornSheep: `FilmReel1..6`, `PopcornEggSpot`, `PopcornProjector`, `PopcornScreen` (screen kept
  visible — the mini-movie renders on it). ButterDuck: `ButterLake` (visible union), `RodBarrel`.
  BurritoArmadillo: `ShovelSpot`, `DigSpot1..5` (decoys), `BuriedEggSpot`.
- `pethouse` Part (PetBarn hut position + facing). `Portal` BaseParts ×3 (or Attribute `Realm` =
  `"space"|"dino"|"candy"`) for RealmPortals. A Part/Model named `DinoPortal` for the standalone door.
- **Pet model templates are NOT Studio assets** — PetSystem builds them by CSG at boot. Nothing to import.

**project.json entries:** see the bundled `default.project.json`. Note the deliberate oddities:
server portal script is named `RealmPortalsHub` (stale-copy dodge); the KIT files and
`DinoPortal.client.luau` have **no entries on purpose**; `TestPetPreview` IS synced.
⚠ Rojo only ADDS — stale baked-in copies in the destination place file will run alongside synced
code. PetBarn/RealmPortals/SkinCrateService all carry duplicate-guards/sweeps for exactly this.

**Monetisation ids:**
- Gamepasses (LIVE, universe-wide so they already work in the dino place): TwoXForever 1862015450,
  GlitterTrail 1859714979, InfiniteGut 1860686821, LuckyPass 1875286225 (crate luck!), CoinMagnet
  1874638222, VIP 1874992233; legacy Space passes LuckyPass 1884292287, VIP 1883020301.
- Token packs (LIVE Developer Products, `SkinCrates.TOKEN_PACKS`, TEST_MODE=false): 3699250369
  (100/25R$), 3699255106 (300/59), 3699261145 (700/129), 3699268487 (1500/239), 3699282826 (4400/549).
- ⚠ **PLACEHOLDER** pet tier-skip products 123456701–123456704 (+ legacy 123456789) in
  PetSystem.server:276 AND PetFollow.client (~line 177) — fake-looking ids that open a broken
  prompt on live players. Replace or neuter (Gamepasses.luau's header rants about this).
- Badge ids: all `badgeId = 0` placeholders in PetCollection (0 = skipped silently).

**Asset ids (sounds/textures referenced, not created):** hatch crack 126450028713974, hatch unlock
92880640988467, coconut hit 9125869504, shatter 9116458024, reel/UI 9114065998, misc pet sounds
119135010875996 / 124279162156159 / 115878657073501 / 79404754846319 / 93360393539898 /
117166473587029; SkinCrateClient: 101638558691673, 4612378364, 1316045217. Particle textures are
all built-in `rbxasset://textures/particles/*` (no upload needed). GutSkins may reference decal ids.

---

## 8. REALM-SPECIFIC BITS the dino side must swap

- **`ReplicatedStorage/Shared` → `DinosaurRealm`** — the full file list is in §3.
- **Species catalog**: the 14 species, `PET_LORE`, `RARE_NAMES`, PetCollection.REWARDS/PRETTY_OVERRIDES,
  SkinCrates' STARTER_PETS/PREMIUM_PETS/ALL_SKIN_PETS/PET_CRATE_SPECIES, RemotePets' PET_THEME, and
  PetFollow's builders/themes are all Food-Realm species. Dino species need their own catalog +
  templates + PET_THEME rows (remember: PetFollow and RemotePets must list identical species sets).
- **Island references**: `islandPrefix = "Island_2_"` etc.; quest tier thresholds (heights up to
  37,000 studs are tuned to THIS tower's altitudes); `CrateTokens.ISLAND_TASK` keyed by island
  numbers 2/5/8/10/13; island names ("Broccoli Bluff"…).
- **Place ids**: Dino 110777788409412, Space 125063266868039 (this place's own id is stamped as
  `homePlaceId` at runtime — never hardcode it on the dino side; use the payload).
- **Tester locks** [OPEN BEFORE LAUNCH]: `DINO_REALM_TESTERS_ONLY = true` /
  `SPACE_REALM_TESTERS_ONLY = true` with allowlists (lando5485 / Broskie310111 / Itsmaddmax1,
  UserIds 1086836724 / 1418148401 / 3911540303 — same list various dev gates use).
- **Portal chain gating**: Space→Dino→Dino-complete→Candy, driven by the cross-place DataStores in §3.
  The dino place must WRITE `DinoRealm_PlayerState_v1 → dinoComplete = true` when beaten, or the
  Candy portal here never unlocks.
- Skins/traits/crates/tokens config is realm-AGNOSTIC by design (a skin is a theme that works on any
  body) — carry those tables unchanged so trades/saves/teleports stay compatible.

---

## 9. OTHER REALMS' PETS — the reverse-trip answer

**This Food Realm does NOT carry any other realm's pet template builders.** Verified by search:
there is no `DinoPetTemplates`, `SpacePetTemplates`, or Candy equivalent anywhere in `src/` — the
only templates that exist here are the 14 Food species PetSystem builds, and `RemotePets.PET_THEME`
lists only those. **So a Dino-realm pet species does NOT currently render in the Food Realm** — if
dino-native species can follow players home, this realm would show nothing for them (unknown
petId → no template → no follower).

The pattern to fix that already exists in this repo's **CandyRealm subfolder** (a separate place,
not part of this export): `CandyRealm/src/server/FoodPetTemplates.server.luau` +
`DinoPetTemplates.server.luau` are template-builder copies the Candy place runs so visiting
players' Food and Dino pets render there, with `CandyRealm/src/client/CrossRealmPets.*` +
`RemotePets.client.lua` consuming them. If you want dino pets visible in the Food Realm, the dino
side should hand back a `DinoPetTemplates.server.luau` for this realm to adopt (that would be a
change to THIS realm — out of scope for this read-only export, but the landing spot is: build
templates → RS root as `<PetId>Template`, add PET_THEME rows to RemotePets, add catalog entries).

Note the distinction: Food-realm pets DO travel to other realms and render there today (Space has
the receiver kit in `SpaceRealm/`; Candy has FoodPetTemplates). The missing direction is foreign
species rendering HERE.

---

## 10. GOTCHAS / WARNINGS (learned the hard way, per in-code comments & project memory)

1. **`PetFollow.client.lua` sits at Luau's 200-local file-scope register ceiling** (a Roblox-only
   limit the CLI compiler won't catch). Do not add file-scope locals; that's why PetRenderGuard,
   RemotePets and PetSkinLook are separate files. This repo measures it with `tools/registers.py`.
2. **Rojo only adds, never overwrites.** Multiple exported files exist purely to fight stale
   baked-in duplicates (RealmPortalsHub rename, PetBarn `_G.__PetBarnServer` guard, the Pet Wheel
   runtime sweep, SeasonalPetsChest's box sweep). Expect the same problem in the dino place file.
3. **DataStore string keys**: `petMilestones` uses string keys deliberately; keep it.
4. **`_G` + load order**: never assume a hook exists (PlayerStats waits up to 15s for
   `_G.grantStarterPet`); never write features that hang off `_G.savePlayerData` side-effects — it
   early-returns for test accounts and when saving is disabled.
5. **Fusion and trades call `_G.savePlayerData` immediately** (anti-dupe). Wire that or a crash
   after a fuse eats duplicates without writing the upgrade.
6. **Honest odds are a policy requirement**: the reel must land on the server's roll; both sides
   read ONE shared table; no pity timers/re-rolls on paid crates.
7. `DISABLE_SAVE_FOR_TESTING = true` is currently set in this realm's PlayerStats — if you copy any
   of it, remember nothing persists until that's false.
8. Test/dev scaffolding marked [REMOVE BEFORE LAUNCH] is sprinkled throughout (instant tester
   tier-skip, /testpet, /goldtest, DevForceCrate, tester locks, /10pets).

---

## 11. UNCERTAINTIES (included-with-doubt, and what I did NOT include)

**Included but arguably not "pet system":**
- `PlayerStats.server.lua` — the whole save service (pets are ~15% of it). Included because the user
  asked for "every DataStore read/write for pets" and it is that writer.
- `GutSkins.luau` / `GutSkinService.server.lua` / `GutSkinClient.client.lua` — gut (belly)
  cosmetics, not pet cosmetics; included because they ride the cross-realm payload and its merge.
- `CosmeticConfig.luau` / `CosmeticIcon.luau` — Space-realm-style meteor-crate cosmetics (contains a
  "Pets" cosmetic TYPE but not the pet system); included because PlayerState requires them.
- `Constants.luau` / `Remotes.luau` / `PlayerState.luau` / `CrateService.server.luau` /
  `CrateClient.client.luau` — the Mystery Meteor Crate stack. It's a *pet-level* reward system, so in.
- `DevCommands.server.luau` — dev commands, only some pet-related.
- `RealmPortals.*` / `BlackHoleTeleport` — full portal scripts (visuals + gating included, not just
  the pet payload part), since the payload calls are inseparable.
- The four `*_AllInOne` KITs — snapshots (Jun 29–Aug 18), slightly behind the live code they copy;
  treat the live files as truth and the kits as convenient seeds.
- `SpaceRealm/*` — receiver-side reference from the Space port, predates payload v2.

**Deliberately NOT copied (integration points only, documented in §6):** CoreClient,
CommunityGarden, RebirthSystem, DailyTasks, SeasonPass, SocialRewards, Gifting, DevArrival,
IslandNPCs, Shop_AllInOne, SecurityWatchdog, NotifyCenter, Wormhole*, BlimpService
(RarestPulls_v1 display), GardenChestClient/GardenDonationClient (host the Seasonal Pets tab UI),
LoadingScreen. If the import finds a missing reference, look there first.

**Unknowns I could not verify from here:**
- The dino place's actual `ArrivalReceiver.server.luau`/`ReturnSender.server.luau` contents (they
  live in `../farttofloatdinosaurealm/`, a separate checkout on the other machine).
- Whether the destination place file contains stale baked-in pet scripts (see gotcha #2).
- `docs/FoodRealmPets_Data.md` says "14 species" for the catalog and "10-pet collection" — both are
  right (10 collection + BeanBuddy + PizzaDragon + … actually 11 non-rebirth + 3 rebirth = 14);
  trust PetSystem's `PETS` table for the definitive roster.
