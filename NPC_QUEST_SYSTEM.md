# NPC quest system — how it works, and how to port it

How an island gets a quest-giver, how talking to them **unlocks** the quest, and how the
quest scripts hang off that. Written to be dropped into another realm.

Source: `src/server/NestingNook_NPCs.server.luau` (builds every NPC) plus one client script
per quest.

---

## 1. The whole thing in one line

**Talking to an NPC sets a player attribute. Every quest script gates on that attribute.**

```
player walks up ──► ProximityPrompt "Talk"
                        │
                    paged dialogue (E to advance)
                        │
                    last page ──► player:SetAttribute("Island<N>QuestAccepted", true)
                        │
        ┌───────────────┼────────────────┬─────────────────────┐
        ▼               ▼                ▼                     ▼
   quest script    HUD banner      chevron trail          waypoint arrow
   spawns its      switches to     stops pointing         (always on, not
   markers         the task text   at the NPC             gated)
```

Nothing is a RemoteEvent. The attribute is set on the **server**, replicates to the client
for free, and survives respawns. That is the entire coupling between the NPC and its quest —
which is why a quest can be written with no knowledge of the NPC, and vice versa.

---

## 2. The attribute name is derived, not hand-written

```lua
local acceptAttr = (islandName:gsub("^island", "Island")) .. "QuestAccepted"
```

`island7` → `Island7QuestAccepted`. Add an NPC to `island9` and its flag is
`Island9QuestAccepted` automatically — there is no registry to keep in sync.

**Two legacy names do NOT follow the pattern** and will trip you up:

| Island | Attribute | Why |
|---|---|---|
| island1 (miner) | `NestingNookQuestClaimed` | predates the convention |
| island3 (DigMiner) | `DigQuestAccepted` | predates the convention |
| everything else | `Island<N>QuestAccepted` | derived |

---

## 3. Adding an NPC is one table row

```lua
local ISLAND_NPCS = {
    { island = "island7", name = "RaptorScout", title = "The Scout", pages = {
        "This is Raptor Ridge.",
        "A raptor nest is starving -- its eggs won't hatch!",
        "Grab the meat scattered around the island.",
        "Carry it back and feed the nest -- 5 pieces.",
        "Do it, and a baby raptor will hatch for you!",
    } },
}
for _, n in ipairs(ISLAND_NPCS) do
    setupIslandQuestNPC(n.island, n.name, n.title, n.pages, n.onTalk)
end
```

`onTalk(player)` is optional — an extra callback fired alongside the attribute set.

`setupIslandQuestNPC` **clones the `miner` model** for every NPC, so all quest-givers are the
same rig with a different name and script. Porting this means either shipping that model or
pointing `findModel("miner")` at your own.

### Where the NPC ends up

Search order, island-scoped first:

1. a part named `NPCSpot<N>` or `Island<N>NPC` **on that island**
2. any part on that island whose name contains `npc` **and** the island number
3. any part on that island whose name contains `npc` at all
4. the island's `SpawnLocation`, or a part named `Spawn`, offset a few studs
5. the island's bounding-box centre — with a warning

Step 3 exists because markers go stale: `AshWarden` moved from island8 to island11, so its
marker is still called `NPCSpot8`. Step 5 firing is a bug you want to see in the log:

```
[IslandNPC] CoastalFisher: no spawn/marker on island4 -> placing at island centre (...).
            Add a part named 'NPCSpot4' to set an exact spot.
```

---

## 4. The prompt and the dialogue

```lua
local function addPrompt(part, actionText, objectText)
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = actionText              -- "Talk"
    prompt.ObjectText = objectText              -- "Researcher"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false          -- rigs block their own prompt otherwise
    prompt.Parent = part
    return prompt
end
```

`wireDialogue(prompt, adornee, getPages, onTalk)` drives it as a **paged conversation**:
each E shows the next line, and E on the last page closes the bubble and resets to "Talk".

Constants worth knowing:

| | | |
|---|---|---|
| `SPEECH_LIFETIME` | 9s | a non-paged bubble auto-hides after this |
| `DIALOGUE_CLOSE_DISTANCE` | 8 studs | walk this far and the conversation closes mid-page |
| `LOOK_RADIUS` | 20 studs | NPC turns to face you |
| `MaxActivationDistance` | 12 studs | matches the close distance, so there's no band where the prompt shows but the conversation instantly shuts |

`prompt.MaxActivationDistance` is set to `DIALOGUE_CLOSE_DISTANCE` by `wireDialogue`, on
purpose — if the prompt reached further than the conversation stayed open, you could open a
dialogue that closed itself on the same frame.

---

## 5. How a quest consumes the flag

Every quest script follows the same shape. From `RaptorNestQuest.client.luau`:

```lua
local CONFIG = { island = "island7", count = 5, eggSpot = "EggSpot7",
                 accept = "Island7QuestAccepted" }

local function updatePrompts()
    local accepted = player:GetAttribute(CONFIG.accept) and not st.done
    for _, m in ipairs(meat) do
        if m.prompt then m.prompt.Enabled = accepted and not st.carrying and ... end
    end
    if eggPrompt then eggPrompt.Enabled = accepted and st.carrying end
end
player:GetAttributeChangedSignal(CONFIG.accept):Connect(updatePrompts)
```

Two rules that make this work:

* **The markers are built either way, but their prompts start disabled.** The quest props
  are ghosted (invisible, non-colliding) until accepted, rather than spawned on accept —
  so there's no build cost at the moment of acceptance and nothing to fail late.
* **It reacts, it doesn't poll.** `GetAttributeChangedSignal` fires the instant the server
  sets it, with no per-frame cost while the player is nowhere near.

---

## 6. Everything else that reads the flag

| Reader | Behaviour |
|---|---|
| **HUD island banner** (`Bootstrap.client.luau`) | shows "Go Talk To The Researcher" until the flag is set, then that island's task text |
| **Chevron trail** (`NPCGuide.client.luau`) | a ground trail to the NPC, which stops once `accept` is set |
| **Waypoint arrow** (`NPCWaypointArrow.client.luau`) | a `▼` over the NPC's head — **not** gated, always on |

The chevron trail's table is the one place the attribute name is written by hand, so it has
the same two legacy exceptions:

```lua
[1]  = { npcName = "miner",       parent = "island1", accept = "NestingNookQuestClaimed" },
[3]  = { npcName = "DigMiner",                        accept = "DigQuestAccepted" },
[7]  = { npcName = "RaptorScout",                     accept = "Island7QuestAccepted" },
```

---

## 7. Load order — this bites

```lua
-- wait for IslandLayout to space the islands first, so NPCs/spawns land at the NEW positions
do local t0 = os.clock(); while not _G.islandsPositioned and os.clock() - t0 < 5 do task.wait() end end
```

`IslandLayout` moves every island model at startup. An NPC placed before that lands at the
island's **authoring** position and is left floating in space when the island moves out from
under it. Any script that positions props on islands needs this gate, and a 5s cap so a
missing layout script doesn't hang the whole file.

Client-side quest scripts have the mirror problem — **StreamingEnabled**. A far island's
model replicates but its *parts* do not, so markers aren't findable until the player is
near. Each quest waits and logs:

```
[RaptorNest] island7 has not streamed in yet (0 parts on this client) -- waiting...
[RaptorNest] island7 streamed in after 6s -> looking for the Meat + EggSpot markers
```

---

## 8. The reward path

Every quest ends the same way: an egg spawns, the player presses E, it shakes/cracks, and a
pet is granted. Ownership lives in `PetUpgrades.server.luau` (`_G.playerOwnedPets`), keyed by
`StegoPet` / `RaptorPet` / `SharkPet` / `TriceratopsPet` / `SpinosaurusPet` /
`TyrannosaurusPet`. The hatch is client-side spectacle; the grant is server-side.

---

## 9. One inconsistency in this realm, so you don't copy it

`GeyserQuest.client.luau:769` **auto-accepts** its own quest:

```lua
pcall(function() player:SetAttribute("Island11QuestAccepted", true) end) -- no NPC yet -> auto-accept
```

That comment is now out of date — `AshWarden` exists on island11. The result is the volcano
quest unlocking itself the moment the island streams in, so talking to the Ash Warden does
nothing the player can see. **Delete that line** when porting (or in this realm) unless you
genuinely want a no-NPC quest.

---

## 10. Port checklist

1. Ship or replace the `miner` model — `setupIslandQuestNPC` clones it for every NPC.
2. Name your islands so `islandName:gsub("^island", "Island")` produces the attribute you
   want, or replace that line with your own naming.
3. Add an `NPCSpot<N>` part on each island. Without one you fall through to the bounding-box
   centre, which on a big island puts the NPC somewhere unreachable.
4. Gate NPC placement on your layout script's "islands are positioned" flag (§7).
5. In each quest script: build props ghosted, enable prompts from
   `GetAttributeChangedSignal(accept)`, and wait for the island to stream in.
6. Give the HUD banner an entry per island, or the player is told to talk to a Researcher
   that doesn't exist.
7. Decide the two legacy attribute names (§2) — either keep them or normalise; just don't
   leave half the readers on one spelling.
