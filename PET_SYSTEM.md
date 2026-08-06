# Fart to Float: Dinosaur Realm — Pet Upgrade & Rarity System

> Everything below is **cosmetic only**. It never touches flight, gas, coins, or balance.

The 6 pets: **Stegosaurus, Velociraptor, Megalodon (Shark), Triceratops, Spinosaurus, T-Rex**.
Each is hatched from its island quest (or granted with the `/pet` command).

---

## The 25-level ladder → 5 tiers

Every pet levels **1 → 25** on an XP curve. The level maps to a tier name + color — that's the badge above the pet.

| Tier          | Levels | Badge color (RGB)          |
|---------------|--------|----------------------------|
| **Common**    | 1–5    | grey `(175,180,190)`       |
| **Uncommon**  | 6–10   | green `(90,210,90)`        |
| **Rare**      | 11–15  | blue `(70,140,255)`        |
| **Epic**      | 16–20  | purple `(180,90,235)`      |
| **Legendary** | 21–25  | gold/orange `(255,170,40)` |

XP to go L → L+1 is `floor(80 × L^1.6)` — cap is level 25.

**XP is earned by the *equipped* pet:** coins → `0.15 XP` each · every 0.5s flight tick → `+6 XP` · gas from food → `0.5 XP` each · reaching a new island → `+600 XP`. (Hooks: `_G.petOnCoins/petOnFlightTick/petOnGas/petOnIsland`.)

---

## What the pet looks like at each level

- **Size:** 60% at Lv1 → 100% at Lv25 (Shark/Trike/Spino/T-Rex stay full-size so their fins/frills/horns don't separate).
- **Lv2:** glowing **aura** (Highlight + point light + particles) · **Lv5:** **trail** · **Lv8:** **sparkles**
- **Lv11/14/19:** orbiting **energy orbs** (1→2→3) · **Lv15:** spinning **ring** (8 neon beads) · **Lv18:** **pulse ring** · **Lv24:** ambient **burst**
- **Accessories** accumulate at **Lv 3/7/10/13/17/20/23** — each pet has its own set (below)
- **Lv25 (MAX):** accessories turn **gold** + a **rainbow shimmer** cycles across the glow/trail/orbs

### Per-pet accessory schedule (Lv 3/7/10/13/17/20/23)

| Pet          | Accessories in order                                                    |
|--------------|-------------------------------------------------------------------------|
| Stegosaurus  | bowtie → glasses → top hat → scarf → flower → sparkle cluster → cane     |
| Velociraptor | bowtie → glasses → crown → backpack → sword → gem cluster → staff        |
| Megalodon    | bowtie → glasses → pirate hat → scarf → anchor → gem cluster → sword     |
| Triceratops  | bowtie → glasses → crown → backpack → flower → gem studs → staff         |
| Spinosaurus  | bell → glasses → safari hat → scarf → sword → lantern → pickaxe          |
| T-Rex        | bowtie → glasses → crown → backpack → gem studs → sparkle cluster → cane |

Theme color (glow/trail): teal `(72,190,180)`.

---

## The rarest form: RARE hatch variants

Rolled **only the first time** you ever hatch that pet — re-hatching is always a normal (rares can't be farmed). A rare hatches **pre-maxed to level 25** with a recolored body + its own tier badge, and plays a full-screen **"✨ RARE! ✨"** fanfare.

| Base pet     | Rare name             | Odds  | Tier         | Badge color            | Body look                                   |
|--------------|-----------------------|-------|--------------|------------------------|---------------------------------------------|
| Stegosaurus  | Cosmic Stegosaurus    | 1/99  | Exotic       | cyan `(40,235,225)`    | emerald glass `(20,150,80)`                 |
| Velociraptor | Alpha Velociraptor    | 1/99  | Exotic       | cyan                   | amethyst glass `(150,80,210)`               |
| Megalodon    | Ancient Megalodon     | 1/99  | Exotic       | cyan                   | pale ice `(200,232,255)` + soft light       |
| Triceratops  | Elder Triceratops     | 1/99  | Exotic       | cyan                   | shiny gold metal `(255,200,40)`             |
| Spinosaurus  | Swamp King Spinosaurus| 1/99  | Exotic       | cyan                   | crystal glass `(80,210,200)`                |
| **T-Rex**    | **Volcano Tyrant Rex**| **1/500** | **Mythical** | magenta `(255,70,230)` | deep-space `(30,24,66)` + **rainbow-cycling** light |

Full ranking, high → low: **Mythical → Exotic → Legendary → Epic → Rare → Uncommon → Common.**

---

## What shows ABOVE the pet as you walk around

Every equipped pet (yours *and* other players', via **RemotePets**) carries a floating **nameplate** 3.7 studs up, always-on-top:

- **Line 1 — name** (FredokaOne 16): normal = white pet name; rare = the rare name tinted in the tier color.
- **Line 2 — tier pill** (GothamBold 11, rounded, tier-colored): normal = `"<Tier>  Lv <N>"` (e.g. `Rare  Lv 13`); rare = just `Exotic` / `Mythical` (white edge glow).

On **level-up**: a themed 20-particle burst. On a **rare hatch**: the full-screen fanfare + a 60-particle burst on the pet.

---

## Upgrading via Robux (tier-skip)

Each Hub card has a **"Skip to <Tier>"** button (server-validated so a cheap skip can't jump a higher tier):

| Skip                 | Price  | → level |
|----------------------|--------|---------|
| Common → Uncommon    | R$49   | 6       |
| Uncommon → Rare      | R$99   | 11      |
| Rare → Epic          | R$299  | 16      |
| Epic → Legendary     | R$599  | 21      |

⚠ The product IDs (`123456701`–`123456704`) are **placeholders** — swap in real Developer Product IDs before launch.

---

## Source files

- `src/server/PetUpgrades.server.luau` — ownership, XP/leveling, **rare rolls**, tier-skip, hatch grants, `/allpets`, and the `PetEquipBroadcast` that powers cross-player pets.
- `src/client/PetFollow.client.luau` — your own follow pet: size ramp, per-level FX, per-pet accessories, rare body, **overhead nameplate**, rare fanfare.
- `src/client/RemotePets.client.luau` — renders every *other* player's equipped pet with the identical visuals + nameplate.
- `src/client/PetHub.client.luau` — the Pet Hub inventory cards (icon, XP bar, tier-skip, equip).
- `src/client/PetCommand.client.luau` — `/pet <name>` (and `/pet all`) test-grant command.
