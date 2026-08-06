# Island Anchoring & Layout — How It Works

A portable guide to how the islands in this realm are **positioned** and **anchored** so
they never fall, drift, or sag — while dinosaurs and NPCs still animate. Hand this to
another realm to reuse the same system.

There are **4 scripts** involved plus **1 shared module**:

| File | Type | Job |
|------|------|-----|
| `src/shared/IslandOrder.luau` | ModuleScript (ReplicatedStorage) | Single source of truth for tower order + names |
| `src/server/IslandLayout.server.luau` | Server, runs **first** | Moves each island model to its slot in the tower |
| `src/server/AnchorIslands.server.luau` | Server | Anchors static geometry on **all** islands (2 passes) |
| `src/server/Island1Anchor.server.luau` | Server | Persistent, precise anchoring for island1's rig-heavy scene |
| `src/server/IslandTeleport.server.luau` | Server | `/island N` debug teleport (reads live positions) |

---

## The core problem

In Roblox, an unanchored `BasePart` falls under gravity. But you **cannot just anchor
everything**, because anchoring the wrong parts breaks things:

- **Anchoring a dinosaur** freezes it — it can't walk or be moved.
- **Anchoring a part with a `Humanoid`** (an NPC) freezes the NPC.
- **Anchoring a `Tool`'s parts** stops the tool welding to the player's hand.
- **Anchoring a weld-driven part breaks the animation.** This is the subtle one — see below.

So the whole system is: **anchor everything static, but skip anything that something
else is driving.**

### The weld rule (the important one)

The dino rigs are built as an **anchored root part** with **unanchored child parts welded
to it** (`WeldConstraint` / `Weld` / `Motor6D`). The animation code moves only the root's
`CFrame`, and the welded children follow because the weld holds them in place relative to
the root.

If you anchor a welded child, it **stops following the root** — the head, tail, and blink
animations freeze solid. So the anchoring rule is:

> A part is "static" (safe to anchor) only if it is **not** the `Part1` (driven side) of
> any `WeldConstraint`, `Weld`, or `Motor6D`.

Both anchor scripts build a `welded` lookup set once per sweep by scanning
`Workspace:GetDescendants()` for weld objects and recording their `Part1`. Building it
once per pass (not per part) keeps startup from stalling on the bigger islands.

---

## 1. Layout — where the islands go

`IslandLayout.server.luau` runs first. It reads `IslandOrder.SLOT_TO_ISLAND` and, for each
slot (1 = bottom, 13 = summit), moves `island<N>` to a hard-coded `SLOT_POS` coordinate
using `PivotTo` (which **keeps the island's current rotation** and brings all children
along):

```lua
local cur = isl:GetPivot()
isl:PivotTo(CFrame.new(pos) * (cur - cur.Position)) -- move to target, keep rotation
```

When done it sets a global flag:

```lua
_G.islandsPositioned = true
```

Everything that spawns props onto islands (NPCs, eggs, geysers) **waits on this flag** so
their props land at the *new* island positions, not the original editor positions.

### The shared order module

`IslandOrder.luau` is the single source of truth so the layout, progress tracking, and the
Wormhole teleporter can never disagree:

- `SLOT_TO_ISLAND = { 1, 9, 2, 12, 3, 13, 4, 5, 10, 7, 6, 8, 11 }` — slot → model number.
- `NAMES` — model number → display name.
- `QUEST` — which model numbers are quest islands.
- `ISLAND_TO_SLOT` — derived inverse (model number → climb position).

The order alternates QUEST / blank islands so no 3 quest islands sit in a row, and keeps
island11 "Volcanic Vista" as the summit finale. **If you change the order, change it here
only** — never hard-code it in a second place.

---

## 2. AnchorIslands — the broad sweep

`AnchorIslands.server.luau` anchors every **static** `BasePart` under `island1`..`island13`.

**Skip rules** (`isStatic`) — a part is NOT anchored if it is:
- inside `dino1`, `RaptorModel`, or `MamaRaptor` (dinosaurs move elsewhere),
- the driven side of a weld (`welded[part]`),
- inside a `Tool`,
- inside any model that has a `Humanoid` anywhere up the chain (an NPC).

**Two passes**, because props spawn at different times:
- **Pass 1** runs immediately — static island geometry, before any rig exists.
- **Pass 2** runs after `_G.islandsPositioned` is set **plus a 5s wait**, to catch
  late-spawned props (eggs, barrels, geysers, nests). Same skip rules, so it can never
  freeze a rig or tool.

There's also a small extra sweep for food-stand models: anything named `Stand`, `stand`,
`Stand8`, etc. (`^stand%d*$`) gets fully anchored so it never falls apart.

---

## 3. Island1Anchor — the precise, persistent sweep

Island1 (Nesting Nook) is special: `NestingNook_NPCs` adds the miner NPC, `dino1`, and the
`LostEggs` **after** startup, and the rigs weld themselves together a second or two later
still. A one-shot sweep misses all of that.

So `Island1Anchor.server.luau`:

- Anchors **everything** on island1 — including `dino1`'s body, the miner, eggs, props —
  **except** weld-driven parts, `Tool` parts, and `Accessory` parts.
- Runs **10 sweeps, 1 second apart**, so it catches props/rigs as they appear.
- Also sweeps `LostEgg` models parented directly to **Workspace** (not island1), which a
  subtree-only sweep would miss.
- Connects `island1.DescendantAdded` to keep anchoring anything added later. It **defers
  0.5s** before anchoring a new part, so a weld that's about to be created gets a chance to
  exist first (otherwise we'd anchor a rig part a frame before its weld shows up).

Net effect: nothing on island1 can fall or drift, and the dinosaur still animates.

---

## 4. IslandTeleport — debug helper

`IslandTeleport.server.luau` is the server half of `/island N`. The client detects the
chat message and fires the `IslandTeleportRequest` RemoteEvent; the server validates
`N` (1..13) and pivots the player just above the island's top surface
(`GetBoundingBox` for models, `Size.Y/2 + 8` studs of headroom). Island position is read
**live from Workspace**, so it's always correct no matter how the layout spaced things.

---

## Reusing this in another realm — checklist

1. **Name your islands** `island1`, `island2`, … in Workspace.
2. **Copy `IslandOrder.luau`** into `ReplicatedStorage.<YourRealm>` and edit
   `SLOT_TO_ISLAND`, `NAMES`, `QUEST`, and `COUNT` for your island count/order.
3. **Copy `IslandLayout.server.luau`**, update `SLOT_POS` (one Vector3 per slot),
   `TOP_SLOT`, and the `require(...)` path to your IslandOrder. It must set
   `_G.islandsPositioned = true` at the end.
4. **Copy `AnchorIslands.server.luau`**, set `TOP_ISLAND` to your island count, and update
   `isDino()` to match **your** moving-model names (whatever you animate/relocate).
5. **Copy `Island1Anchor.server.luau`** only if you have a rig-heavy first island; adapt
   the extra `miner` / `LostEgg` names to your own late-spawned, Workspace-parented props.
6. **Keep the weld rule intact.** If your rigs use anchored-root + welded-children +
   CFrame animation, do **not** remove the `welded[part]` skip — it's what lets things stay
   put *and* animate.
7. `IslandTeleport` is optional (debug only).

### The golden rules

- **Anchor static geometry; skip anything driven** (welds, dinos, NPCs/Humanoids, Tools,
  Accessories).
- **Position before you anchor**, and gate prop spawns on `_G.islandsPositioned`.
- **Sweep more than once** — props and welds appear on a delay after startup.
- **One source of truth** for island order (`IslandOrder.luau`).
