# NPC waypoint arrow — copy + how it works

The bouncing green **▼** hovering over each quest NPC's head.
Source: `src/client/NPCWaypointArrow.client.luau`. Client-built, one script, no remotes.

Companion to `QUEST_GIVER_NAMETAG.md` (the "Quest Giver" text label) — the name tag says
*who*, this says *where*.

---

## 1. What it is

A `BillboardGui` per NPC, parented to **PlayerGui** and `Adornee`'d to a part of the NPC,
holding a single `TextLabel` whose text is `▼`. A `Heartbeat` loop drives a sine bounce and
the visibility gates.

| | |
|---|---|
| Instance name | `WaypointArrow_<npcName>` |
| Parent | `PlayerGui` (**not** the NPC — see §5) |
| Adornee | a stable part on the NPC (see §3) |
| Size | 60 × 60 px — constant on screen at any distance |
| Colour | `Color3.fromRGB(50, 220, 80)` — the same green as the chevron trail |
| Glyph | `▼`, `SourceSansBold`, `TextScaled` |
| Outline | `TextStrokeTransparency 0.3`, black — readable against a bright sky |
| `AlwaysOnTop` | `true` — renders through terrain and the NPC itself |
| `LightInfluence` | `0` — full brightness at night / inside the volcano |
| `MaxDistance` | 240 studs |

`BillboardGui` is the right primitive: it always faces the camera and holds a constant
on-screen size, so the arrow is the same readable blob whether you are 5 or 200 studs away.
A `SurfaceGui` would skew as you walked around the NPC; a `ScreenGui` would not track them
at all.

---

## 2. The code, verbatim

The whole file is ~217 lines. The parts that matter:

### The NPC table — the only thing you edit to add one

```lua
local NPCS = {
    { parent = "island1", npcName = "miner", island = 1 },
    { npcName = "DigMiner",      island = 3 },  -- no `parent` = search Workspace
    { npcName = "FrillRancher",  island = 2 },
    { npcName = "CoastalFisher", island = 4 },
    { npcName = "MireWatcher",   island = 5 },
    { npcName = "RidgeWarden",   island = 6 },
    { npcName = "RaptorScout",   island = 7 },
    { npcName = "AshWarden",     island = 11 },
}

for _, spec in ipairs(NPCS) do
    task.spawn(setupArrow, spec)  -- one independent coroutine each
end
```

`parent` is optional. `NestingNook_NPCs.setupIslandQuestNPC` parents every island Researcher
directly under `Workspace`, so only island1's `miner` (which lives inside the island model)
needs it.

### Building the arrow

```lua
gui = Instance.new("BillboardGui")
gui.Name = "WaypointArrow_" .. spec.npcName
gui.Adornee = anchor
gui.Size = ARROW_SIZE
gui.StudsOffsetWorldSpace = baseOffset
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.MaxDistance = 240
gui.Parent = player:WaitForChild("PlayerGui")

local arrow = Instance.new("TextLabel")
arrow.Size = UDim2.new(1, 0, 1, 0)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.SourceSansBold
arrow.TextScaled = true
arrow.TextColor3 = ARROW_COLOR
arrow.Text = "▼"
arrow.TextStrokeColor3 = Color3.new(0, 0, 0)
arrow.TextStrokeTransparency = 0.3
arrow.Parent = gui
```

### The one loop that runs it

```lua
conn = RunService.Heartbeat:Connect(function()
    if gui then
        gui.Enabled = (not bubbleShowing) and (curIsland == spec.island)
        gui.StudsOffsetWorldSpace = baseOffset
            + Vector3.new(0, math.sin(os.clock() * BOUNCE_SPEED) * BOUNCE_AMP, 0)
    end
end)
```

That is the whole animation: a sine on the Y offset, and two booleans.

---

## 3. Where the arrow actually sits

Two separate decisions, and conflating them is the usual bug.

**Horizontal position** comes from the *anchor part*, picked in this order:

```lua
local function findAnchorPart(npc)
    local hrp = npc:FindFirstChild("HumanoidRootPart", true)   -- 1. rig root
    if hrp and hrp:IsA("BasePart") then return hrp end
    if npc:IsA("Model") and npc.PrimaryPart then                -- 2. PrimaryPart
        return npc.PrimaryPart
    end
    for _, d in ipairs(npc:GetDescendants()) do                 -- 3. anything "head"
        if d:IsA("BasePart") and string.find(string.lower(d.Name), "head", 1, true) then
            return d
        end
    end
    return npc:FindFirstChildWhichIsA("BasePart", true)         -- 4. any part at all
end
```

**Vertical position** comes from the *bounding box*, not the anchor:

```lua
local cf, size = npc:GetBoundingBox()
local topY = cf.Position.Y + size.Y / 2
baseOffset = Vector3.new(0, (topY - anchor.Position.Y) + ARROW_MARGIN, 0)
```

> **Why not just use the bounding-box centre for X/Z too?** Because a dinosaur is mostly
> tail. A long neck or tail drags the box centre away from the body, and the arrow ends up
> hovering over empty ground beside the NPC. Only the **height** comes from the box; the
> X/Z stays pinned to the body root. Taking height from the box is what makes tall rigs
> work without a per-NPC offset.

### `StudsOffsetWorldSpace`, not `StudsOffset`

`StudsOffset` is relative to the **adornee part's orientation**. NPCs turn to face the
player (`NpcLife` does this), so with `StudsOffset` the arrow would swing around the NPC's
head like a compass needle as they turned. `StudsOffsetWorldSpace` is always world +Y, so
"up" stays up.

---

## 4. Three separate reasons it hides

| Gate | Where | Why |
|---|---|---|
| Player is on a different island | `curIsland == spec.island` | otherwise every NPC's arrow is visible from every island |
| NPC is talking | `not bubbleShowing` | the arrow sits exactly where the speech bubble goes |
| Beyond 240 studs | `MaxDistance` | backstop, in case island detection lags |

### Island detection

One shared poller, not one per arrow:

```lua
local curIsland = nil
do
    local function detect()
        -- ...for i = 1, 13: if inside island i's XZ footprint (+80 studs of Y slack) -> i
        -- ...else remember the nearest by 3D distance and return that
    end
    task.spawn(function() while true do curIsland = detect(); task.wait(0.4) end end)
end
```

The **+80 studs of Y slack** and the **3D** nearest-fallback both exist because this realm's
islands stack *vertically* — 1,470 to 5,720 studs apart on Y with overlapping X/Z footprints.
A flat 2D "which island am I over" test matches three islands at once here.

### Speech-bubble tracking

The server parents a `BillboardGui` named `SpeechBubble` to the NPC when it talks, and that
replicates. The client just watches for it:

```lua
local bubbleShowing = npc:FindFirstChild("SpeechBubble", true) ~= nil
npc.DescendantAdded:Connect(function(d)
    if d:IsA("BillboardGui") and d.Name == "SpeechBubble" then bubbleShowing = true end
end)
npc.DescendantRemoving:Connect(function(d)
    if d:IsA("BillboardGui") and d.Name == "SpeechBubble" then bubbleShowing = false end
end)
```

Note the initial `FindFirstChild` — without it, an NPC already mid-conversation when the
arrow builds would show both.

**The name `SpeechBubble` is load-bearing.** Rename it on the server and the arrow stops
hiding, with no error anywhere.

---

## 5. Streaming lifecycle — why the arrow is parented to PlayerGui

The place has `StreamingEnabled`. An NPC's **Model** replicates at join but its **parts** do
not until the player is near. So there is a long window where `npc` exists and
`findAnchorPart(npc)` returns `nil`.

```lua
local function syncLifecycle()
    local anchor = findAnchorPart(npc)
    if anchor then
        if not gui then buildArrow(anchor) end
    elseif gui then
        teardownArrow()   -- disconnect the Heartbeat, destroy the gui
    end
end

npc.DescendantAdded:Connect(function(child)      -- react instantly on stream-in
    if child:IsA("BasePart") then syncLifecycle() end
end)
while true do                                     -- and poll for stream-OUT
    syncLifecycle()
    task.wait(0.5)
end
```

`DescendantAdded` alone is not enough — there is no matching signal you can rely on for
stream-*out*, hence the 0.5s poll.

The GUI lives in **PlayerGui**, not under the NPC. If it were parented to the NPC, streaming
the NPC out would take the GUI with it and `conn` would keep firing against a destroyed
instance. Parenting to PlayerGui with an `Adornee` means the arrow is ours to destroy on our
own schedule.

---

## 6. The nested-model trap

```lua
-- WaitForChild only looks ONE level deep. The island1 models are nested inside
-- themselves (Workspace.island1.island1.dino1), so island1:WaitForChild("dino1")
-- never resolved -- it timed out after 90s and the arrows never appeared.
local function waitForDescendant(container, name, timeout)
    local found = container:FindFirstChild(name, true)   -- `true` = recursive
    if found then return found end
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        task.wait(0.25)
        found = container:FindFirstChild(name, true)
        if found then return found end
    end
    return nil
end
```

This is the single most likely thing to bite you on a port. `WaitForChild` is not recursive;
`FindFirstChild(name, true)` is. If your NPCs are anywhere but a direct child, you need this.

Failure is loud, which is the point:

```
[NPCWaypointArrow] RaptorScout not found under Workspace - no arrow.
```

---

## 7. Tuning

```lua
local ARROW_COLOR  = Color3.fromRGB(50, 220, 80)
local ARROW_SIZE   = UDim2.new(0, 60, 0, 60) -- screen pixels
local ARROW_MARGIN = 3    -- studs above the NPC's bounding-box TOP
local BOUNCE_BASE  = 6    -- fallback studs if the NPC has no bounding box
local BOUNCE_AMP   = 1    -- studs of travel each way
local BOUNCE_SPEED = 2.5  -- rad/sec -> ~2.5s cycle
```

`ARROW_MARGIN` is the one you will actually touch. `BOUNCE_BASE` only applies to a
non-Model NPC.

---

## 8. Deliberate exception

`dino1` (the Mama Dino on island1) has **no** arrow, on purpose:

> She is a large static prop right beside the spawn, not something the player has to be led
> to, and the arrow sat on top of her. The quest still guides you to her when it matters:
> QuestGate puts an arrow above the **player's** head pointing her way once all 5 eggs are
> returned.

Worth keeping in mind — an arrow over something the player literally cannot miss reads as
clutter, not guidance.

---

## 9. The two sibling guides

Three separate systems point at NPCs. Do not confuse them:

| | File | Points at | Gated? |
|---|---|---|---|
| **Waypoint arrow** (this doc) | `NPCWaypointArrow.client.luau` | the NPC's head | **never** — always on |
| **Chevron trail** | `NPCGuide.client.luau` → `ChevronTrail.luau` | a ground runway to the NPC | stops once the quest is accepted |
| **Player-head arrow** | `QuestGate.client.luau` | shown over the *player*, pointing at the miner | only when you try to grab an egg ungated |

The waypoint arrow being ungated is the design: the chevron trail tells you *go here now*,
the arrow tells you *that's the guy* forever after.

`NPCGuide.client.luau` is the one place quest-accept attribute names are written by hand,
and it carries the two legacy spellings:

```lua
[1] = { npcName = "miner",    parent = "island1", accept = "NestingNookQuestClaimed" },
[3] = { npcName = "DigMiner",                     accept = "DigQuestAccepted" },
[7] = { npcName = "RaptorScout",                  accept = "Island7QuestAccepted" },
```

---

## 10. Port checklist

1. Drop `NPCWaypointArrow.client.luau` into `StarterPlayerScripts`. No remotes, no server
   half, no dependencies — it is genuinely standalone.
2. Rewrite the `NPCS` table for your NPCs. Add `parent` only for NPCs that are not
   direct children of `Workspace`.
3. **Fix the island loop.** `for i = 1, 13 do workspace:FindFirstChild("island" .. i)` is
   hard-coded to this realm's naming and count. If your islands are named differently, this
   is the one block you must change or every arrow will be hidden forever
   (`curIsland` never matches `spec.island`).
4. Decide the Y slack in `detect()`. The `+80` exists because these islands stack
   vertically; a flat realm wants a much smaller number, or the test matches everything.
5. Match `SpeechBubble` to whatever your server names its speech GUI, or delete the
   bubble-hiding block.
6. Check `MaxDistance = 240` against your island spacing — it should be comfortably less
   than the gap between islands.
