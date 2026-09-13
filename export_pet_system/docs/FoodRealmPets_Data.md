# Food Realm Pets — COMPLETE data reference (for the Dino Realm "Food Realm Pets" tab)

Everything the food realm (Fart to Float) knows about pets: every species, the level/age system
from Baby to max, every skin each pet can wear, traits, rares, crates, and how the data is stored —
so Dino Realm can build a tab that shows (and upgrades) these same pets.

Sources of truth in the food realm:
- `src/server/PetSystem.server.lua` — catalog, leveling, rares, milestones
- `src/shared/PetSkins.luau` — skin themes + inventory key format
- `src/shared/PetTraits.luau` — traits + odds
- `src/shared/SkinCrates.luau` — crates, odds, token packs, trade-ups

---

## 1. THE PET CATALOG (14 species)

### Main pets (count toward the 10-pet collection)

| petId | Display Name | Where / How | Quest type |
|---|---|---|---|
| `BeanBuddy` | Bean Buddy | Bean Farm — FREE starter, granted + auto-equipped on first ever join | starter |
| `BroccoliPet` | **Broccoli Bunny** (note: id ≠ name) | Broccoli Bluff (Island 2) — find 3 broccoli pieces → egg | find |
| `CoconutCrab` | Coconut Crab | Coconut Cove (Island 5) — crack 7 coconuts → cave chest → egg | crack |
| `PopcornSheep` | Popcorn Sheep | Popcorn Pinnacle (Island 8) — find 6 film reels → projector show → egg | film-reels |
| `ButterDuck` | Butter Duck | Butter Swamp (Island 10) — fishing minigame, pity-ramped egg catch | fishing |
| `BurritoArmadillo` | Burrito Armadillo | Burrito Barrens (Island 13) — shovel + hot/cold dig for the buried egg | dig |
| `SunflowerBee` | Sunflower Bee | Community Garden — Summer harvest reward | seasonal |
| `MapleFox` | Maple Fox | Community Garden — Autumn harvest reward | seasonal |
| `FrostPenguin` | Frost Penguin | Community Garden — Winter harvest reward | seasonal |
| `BlossomBunny` | Blossom Bunny | Community Garden — Spring harvest reward | seasonal |

### Secret pet (NOT in the collection count)

| petId | Display Name | How |
|---|---|---|
| `PizzaDragon` | Pizza Dragon | ONLY by collecting all 10 pets above. Not questable, not buyable. |

### Rebirth pets (NOT in the collection count)

| petId | Display Name | Requirement |
|---|---|---|
| `MoltenBean` | Molten Bean | Rebirth 3 |
| `VoidDragon` | Void Dragon | Rebirth 6 |
| `PrismFox` | Prism Fox | Rebirth 10 |

They're recolour clones of base pets, granted by RebirthSystem
(`_G.REBIRTH_PET_MILESTONES = { {req=3, MoltenBean}, {req=6, VoidDragon}, {req=10, PrismFox} }`).

### Lore blurbs (detail-card copy)

- **BeanBuddy** — "Sprouted in the Bean Farm soil and decided to follow you home. It has never been more than a few feet from you since."
- **BroccoliPet** — "A bunny that grew up in the broccoli patch and started to look like it. Chews constantly. Nobody knows what."
- **CoconutCrab** — "Spent its whole life cracking coconuts on the beach. Its claws are stronger than most rocks, and it knows it."
- **PopcornSheep** — "Its wool pops in the heat. The theatre on Popcorn Pinnacle has never had to buy a snack machine."
- **ButterDuck** — "Floats in the butter swamp like it was made for it. Possibly was. Extremely slippery. Do not attempt to hold."
- **BurritoArmadillo** — "Rolls into a perfect burrito when startled. Buries things and forgets where. Digs constantly to find them again."
- **SunflowerBee** — "Arrived the summer the garden first bloomed. Carries a little of that sunshine everywhere it goes."
- **MapleFox** — "Turned the colour of autumn leaves and stayed that way. Naps in the warm patches of the garden."
- **FrostPenguin** — "Waddled out of the winter garden and refused to leave. Its feet have never once been cold."
- **BlossomBunny** — "Woke up with the first spring blossom and wears the flowers to prove it. Hops everywhere. Walking is for others."

---

## 2. LEVELS & AGES (Baby → max) — the LIVE leveling system

**Max level is 25 for every pet** (`PET_MAX_LEVEL = 25`). Levels are cosmetic GROWTH only
(size + accessories) — no stat effects. (Ignore the `maxLevel = 3` / `tiers` height+time fields
inside the PETS catalog — that's the legacy achievement system; the XP system below is what runs.)

### Age ladder (the badge over the pet + on the card)

Levels display as AGE words, never rarity words (rarity vocabulary belongs to skin crates):

| Age | Levels | Badge color |
|---|---|---|
| Baby | 1–5 | `Color3.fromRGB(175,180,190)` grey |
| Kid | 6–10 | `Color3.fromRGB(90,210,90)` green |
| Teen | 11–15 | `Color3.fromRGB(70,140,255)` blue |
| Adult | 16–20 | `Color3.fromRGB(180,90,235)` purple |
| Elder | 21–25 | `Color3.fromRGB(255,170,40)` orange |

Rare hatch variants override the age word entirely (they're genuinely rarity, and come pre-maxed):

| Variant | Badge | Color |
|---|---|---|
| Any rare (Exotic) | **Exotic** | `Color3.fromRGB(40,235,225)` bright cyan, glow |
| ButterDuck rare only | **Mythical** | `Color3.fromRGB(255,70,230)` magenta, flashiest glow |

### XP curve

`xpNeeded(L) = math.floor(80 * L^1.6)` — XP to go from level L to L+1. Exact table:

| L→L+1 | XP | L→L+1 | XP | L→L+1 | XP |
|---|---|---|---|---|---|
| 1→2 | 80 | 9→10 | 2,690 | 17→18 | 7,444 |
| 2→3 | 242 | 10→11 | 3,184 | 18→19 | 8,156 |
| 3→4 | 463 | 11→12 | 3,709 | 19→20 | 8,893 |
| 4→5 | 735 | 12→13 | 4,263 | 20→21 | 9,654 |
| 5→6 | 1,050 | 13→14 | 4,846 | 21→22 | 10,438 |
| 6→7 | 1,406 | 14→15 | 5,456 | 22→23 | 11,245 |
| 7→8 | 1,799 | 15→16 | 6,093 | 23→24 | 12,074 |
| 8→9 | 2,228 | 16→17 | 6,755 | 24→25 | 12,924 |

### XP sources (only the EQUIPPED pet earns XP)

| Source | XP |
|---|---|
| Coins earned | `0.15` XP per coin |
| Each 0.5s flight tick | `6` XP |
| Gas/power gained from eating | `0.5` XP per gas |
| Reaching a NEW island | `600` XP |

Other ways levels move:
- **Pet Level Crate** (see §5) — pays 1/2/3/5/7/10 whole levels per open.
- **Robux tier skips** (buttons on the owned card): Skip to Kid / Teen / Adult / Elder by bracket
  (level ≤5 → skip 1, ≤10 → 2, ≤15 → 3, ≤20 → 4). Server-validated via `PetPendingUpgradeEvent` + receipt.

### Visual milestones (what a level LOOKS like)

Milestone levels: **3, 8, 13, 18, 23, 25**. Accessories unlock at levels `{3, 7, 10, 13, 17, 20, 23}` (7 max).

| Level | Look |
|---|---|
| 1–2 | starter (growing) |
| 3+ | 1 accessory, growing |
| 5+ | 1 accessory + trail |
| 8+ | 2 accessories + trail (accessory #2 = glasses) |
| 10+ | 2 accessories + aura |
| 13+ | 3 accessories + aura (accessory #3 = hat) |
| 15+ | 3 accessories + sparkles |
| 18+ | 4 accessories + sparkles |
| 23+ | 5 accessories + full trail/aura/sparkles |
| 25 | **MAX — all accessories + gold + shimmer** |

---

## 3. RARE HATCH VARIANTS

Rolled ONCE per species, on the first-ever quest completion. A rare is a separate inventory entry
(storage key `petId .. "#R"`, e.g. `"ButterDuck#R"`) that arrives **pre-maxed at level 25**.
Cosmetic only. Normal + rare of the same species can both be owned.

| petId | Rare name | Odds |
|---|---|---|
| `BroccoliPet` | Emerald Bunny | 1 in 750 |
| `CoconutCrab` | Golden Crab | 1 in 750 |
| `PopcornSheep` | Cloud Sheep | 1 in 750 |
| `BurritoArmadillo` | Crystal Armadillo | 1 in 750 |
| `ButterDuck` | **Cosmic Duck** | **1 in 10,000** (the rarest thing in the game) |

---

## 4. SKINS — every pet can wear EVERY skin

Skins are **universal themes**: any skin works on any pet ("Galaxy" fits Pizza Dragon, Bean Buddy,
anything). So "the skins each pet can have" = the full 18-theme list below, for all 14 species.
What varies per pet is only which CRATES drop that (pet, skin) pair — §5.

Skin rarity tiers (never confuse with pet AGE): **Common → Uncommon → Rare → Epic → Legendary → Gold**.
Tier colors: Common grey (176,182,194) · Uncommon green (92,200,122) · Rare blue (70,140,255) ·
Epic purple (180,90,235) · Legendary orange (255,140,40) · Gold (255,206,92).
"Gold" is ONLY ever a rarity — the gold-coloured skin is called "Gilded".

| Skin id | Tier | Look (color / material / extras) |
|---|---|---|
| `Stone` | Common | grey (142,146,152), Slate |
| `Sand` | Common | tan (226,202,144), Sand |
| `Moss` | Common | green (96,138,74), Grass |
| `Mud` | Common | brown (96,72,50), Mud |
| `Chocolate` | Common | dark brown (84,52,34), SmoothPlastic, refl 0.08 |
| `Honey` | Common | amber (232,168,48), Glass, refl 0.15 |
| `Ice` | Uncommon | pale blue (168,222,246), Glass, refl 0.30, fx sparkle |
| `Emerald` | Uncommon | green (20,150,80), Glass, refl 0.25, fx |
| `Coral` | Uncommon | pink-red (248,116,104), SmoothPlastic |
| `Gilded` | Uncommon | gold (232,186,62), Metal, refl 0.40, fx |
| `Crystal` | Uncommon | lilac (190,150,240), Glass, refl 0.35, fx |
| `Neon` | Rare | mint (60,255,170), Neon, glows (PointLight) |
| `Toxic` | Rare | acid green (150,235,40), Neon, glows |
| `Magma` | Rare | orange-red (255,88,24), Neon, glows |
| `Galaxy` | Epic | deep purple (40,30,92), Neon, purple fx, glows |
| `Rainbow` | Epic | ANIMATED — hue cycles every frame |
| `Cyber` | Epic | cyan (24,232,232), Neon, glows |
| `Shadow` | Legendary | near-black (18,16,26), purple fx, glows |
| `Celestial` | Legendary | warm white (252,246,208), Neon, glows |
| `Cosmic` | **Gold** | dark violet (30,24,66), Neon, ANIMATED "cosmic", glows — the knife pull |

**Inventory key format** (one entry per pet+skin+trait combo, entries stack with `count`):
`petId .. "|" .. skinId .. "|" .. traitId` — e.g. `"PizzaDragon|Galaxy|"` (no trait),
`"PizzaDragon|Galaxy|Crowned"` (separate entry). Trade keys are the same string prefixed `"SKIN:"`.

**Important:** a player can own a skin for a pet they have NOT unlocked yet — it reads
"Unlock <Pet> to equip" until they earn the pet. Deliberate (stops odds-farming while locked).

---

## 5. SKIN CRATES (token-priced; honest CS:GO-style odds)

Baseline rarity odds (Starter): Common 79.92 · Uncommon 16.00 · Rare 3.20 · Epic 0.64 ·
Legendary 0.16 · Gold 0.08 (%). Roll = pick rarity band, then uniform within the band; the trait
rolls separately (§6). Never rig the reel — published odds ARE the rolled odds.

| Crate | Price (tokens) | Odds override | Notes |
|---|---|---|---|
| **Pet Level Crate** (`PetLevels`) | 150 | C52/U30/R13/E4/L0.9/G0.1 | Pays LEVELS not skins: 1/2/3/5/7/10 (avg 1.78/open) |
| **Starter** | 250 | baseline | The odds players learn from |
| **Premium** | 600 | C58/U30/R9/E2.2/L0.6/G0.2 | Half the Commons |
| **Elite** | 1500 | C20/U25/R34/E15/L5/G1 | Rare+ is 55% |
| **Mythic** | 3000 | C0/U18/R40/E28/L11/G3 | `limited = true` — events / Season Pass / bundles only |

Which (pet, skin) pairs each crate drops — copy exactly if the Dino tab shows crate contents:

- **Starter**: Common — BeanBuddy/Stone, BlossomBunny/Sand, BroccoliPet/Moss, ButterDuck/Mud, SunflowerBee/Chocolate, MapleFox/Honey · Uncommon — FrostPenguin/Ice, BeanBuddy/Emerald, ButterDuck/Coral, BroccoliPet/Gilded, BlossomBunny/Crystal · Rare — MapleFox/Neon, SunflowerBee/Toxic, BurritoArmadillo/Magma, PizzaDragon/Gilded · Epic — PizzaDragon/Galaxy, ButterDuck/Rainbow, MapleFox/Cyber · Legendary — PizzaDragon/Shadow, PopcornSheep/Celestial · Gold — PizzaDragon/Cosmic
- **Premium**: Common — CoconutCrab/Stone, PopcornSheep/Sand, BurritoArmadillo/Mud, FrostPenguin/Chocolate · Uncommon — CoconutCrab/Coral, PopcornSheep/Ice, MapleFox/Crystal, SunflowerBee/Gilded, BurritoArmadillo/Emerald · Rare — FrostPenguin/Neon, ButterDuck/Toxic, BroccoliPet/Magma, BeanBuddy/Neon · Epic — BurritoArmadillo/Galaxy, BeanBuddy/Cyber, PopcornSheep/Rainbow · Legendary — CoconutCrab/Shadow, BlossomBunny/Celestial · Gold — CoconutCrab/Cosmic
- **Elite**: Common — PizzaDragon/Stone, CoconutCrab/Moss · Uncommon — PizzaDragon/Crystal, FrostPenguin/Emerald, BurritoArmadillo/Gilded · Rare — PizzaDragon/Neon, CoconutCrab/Toxic, PopcornSheep/Magma, BlossomBunny/Neon · Epic — CoconutCrab/Galaxy, FrostPenguin/Cyber, SunflowerBee/Rainbow, MapleFox/Galaxy · Legendary — ButterDuck/Shadow, MapleFox/Celestial, BeanBuddy/Shadow · Gold — ButterDuck/Cosmic, MapleFox/Cosmic
- **Mythic**: Uncommon — PizzaDragon/Ice, BeanBuddy/Crystal · Rare — PizzaDragon/Toxic, BlossomBunny/Magma, SunflowerBee/Neon · Epic — PizzaDragon/Cyber, BlossomBunny/Galaxy, FrostPenguin/Rainbow, CoconutCrab/Cyber · Legendary — SunflowerBee/Shadow, BurritoArmadillo/Celestial, FrostPenguin/Shadow · Gold — BlossomBunny/Cosmic, SunflowerBee/Cosmic, BroccoliPet/Cosmic

**Tokens** (Robux dev products, PLACEHOLDER ids 900000001–4, `TEST_MODE = true` right now):
250 tok = R$99 · 700 = R$249 ("Popular") · 1,800 = R$599 ("Best Value") · 5,000 = R$1,499.
Reference rate 0.4 R$/token.

**Trade-up**: 10 same-rarity skins → 1 random skin of the next rarity up
(Common→Uncommon→Rare→Epic→Legendary→Gold; Gold has no trade-up). Pool = all crates' contents at that tier.

---

## 6. TRAITS (independent second roll on every skin pull)

Pure effect layers (particles/light/orbit/halo) — never body changes, so every trait fits every pet.
Chances sum to 100:

| Trait | Chance | Effect |
|---|---|---|
| None | 85.00% | renders exactly as the skin |
| Sparkly | 6.00% | gold Sparkles |
| Smoky | 3.50% | grey smoke particles |
| Flaming | 2.00% | fire particles + orange light |
| Frozen | 1.50% | falling frost sparkle + icy light |
| Charged | 1.00% | 3 neon orbs orbiting + flickering electric light |
| Glowing | 0.70% | neon halo ring + strong warm light |
| Cosmic Aura | 0.20% | 5 purple orbs orbiting + sparkle + light |
| Crowned | 0.10% | a little floating 5-point CROWN + sparkles + light |

---

## 7. COLLECTION MILESTONES (the "REWARDS" tab)

Counted species: the 10 main pets (PizzaDragon and rebirth pets are excluded from BOTH counts).
Owning either variant (normal or rare) counts a species once. Rewards are TITLES (floating nametags
all players see) — no coins:

| Need | Reward |
|---|---|
| 3 | Title: **Pet Keeper** |
| 5 | Title: **Pet Collector** |
| 7 | Title: **Beastmaster** |
| 10 | **SECRET PET: Pizza Dragon** |

---

## 8. HOW THE DATA IS STORED (what a Dino Realm tab must read/write)

Server-side globals in the food realm (all persisted by `PlayerStats.server.lua`):

- `_G.playerOwnedPets[player]` — the pet inventory. Keyed by **storage key**: `petId` for normal,
  `petId .. "#R"` for the rare variant. Each value: `{ level, xp, height, time, rare, count }`.
- `_G.playerEquippedPet[player]` — equipped storage key (or nil).
- `_G.playerPetMilestones[player]` — claimed collection milestones, STRING keys: `{ ["3"]=true, ... }`.
- `_G.playerDiscoveredQuests[player]` / `_G.playerEverCompletedQuests[player]` — quest state
  (`everCompleted` gates the once-only rare roll; separate from ownership).
- Skins/traits/tokens live in the SkinCrateService inventory keyed `petId|skinId|traitId` with counts.

Client-facing payload per pet (what `PetInventoryEvent` sends — mirror this shape for the Dino tab):
`{ petId, displayName, level, maxLevel=25, xp, xpNeed, milestone (hint text), tierVisual, equipped,
height, time, rare, rareName, count, lore, islandName, totalXp, accessories, accessoriesMax=7,
rareOdds, questLabel }`.

Key remotes (all in ReplicatedStorage, created via getOrCreate on server start):
`PetInventoryEvent` (s→c inventory), `PetEquipEvent` (c→s equip/unequip by storage key),
`PetProgressEvent` (c→s peakHeight+time), `PetPendingUpgradeEvent` + Robux receipt (tier skips),
`PetRequestStateEvent` (c→s handshake).

**Cross-realm note:** Dino Realm is a separate place, so it can't touch these `_G` tables directly —
it needs the same DataStore save (PlayerStats' keys) or a copy of the pet fields carried across in
the teleport payload (see `src/shared/RealmTransfer.luau` for the existing transfer envelope). If the
Dino tab allows UPGRADES, write back through the same save shape above or the two realms will
overwrite each other's pet data.

---

## 9. WHAT AN OWNED CARD SHOWS (so the tab reads identically)

Card 322x252, blue `RGB(20,70,160)` (rares: dark purple `RGB(46,28,86)`), gold stroke if equipped:
spinning 3D model (310x140) → name (rare name if rare) → "`<Age>  Lv N`" line in age color
(+ "• EQUIPPED") → XP bar "`X / Y XP`" (gold "MAX" at 25) → EQUIP/UNEQUIP + Skip-tier buttons →
"✨ next milestone" hint. Variant pets show an Exotic/Mythical corner tag; stacked duplicates show
an orange "xN" count chip. Locked pets: see `docs/LockedPetCard_Look.md`.
