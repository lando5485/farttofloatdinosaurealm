# Quest Giver name tag — copy + how it works

The floating **"Quest Giver"** label above the Nesting Nook researcher.
Source: `src/server/NestingNook_NPCs.server.luau`. Server-built, so every player sees it.

---

## 1. What it is

A `BillboardGui` parented to one part of the NPC model, holding a single `TextLabel`.
BillboardGui is the right primitive here because it always faces the camera and keeps a
constant on-screen size at any distance — a `SurfaceGui` would skew as you walk around the
NPC, and a `ScreenGui` wouldn't track the NPC at all.

| | |
|---|---|
| Instance name | `NameLabel` (this exact name is load-bearing — see §4) |
| Size | 200 × 44 px |
| Offset | `StudsOffset (0, 3, 0)` — 3 studs above the adornee |
| Font | `FredokaOne`, white, `TextScaled` |
| Outline | `TextStrokeTransparency 0.3`, black |
| `AlwaysOnTop` | `true` — renders through the NPC's own geometry |
| `MaxDistance` | **60 studs** |

`MaxDistance = 60` is what stops thirteen name tags floating in the sky. The islands are
1,470–5,720 studs apart, so without it every NPC in the game would be legible from every
other island as a cluster of text over the horizon.

---

## 2. The code, verbatim

```lua
-- Floating name label. `size`/`textSize`/`worldYOffset` are optional overrides;
-- when `worldYOffset` is given the label is offset in WORLD space (always up),
-- so it can sit above the top of a model regardless of orientation.
local function makeNameLabel(adornee: BasePart, text: string, size: UDim2?, worldYOffset: number?, textSize: number?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameLabel"
	bb.Adornee = adornee
	bb.Size = size or UDim2.new(0, 200, 0, 44)
	if worldYOffset then
		bb.StudsOffsetWorldSpace = Vector3.new(0, worldYOffset, 0)
	else
		bb.StudsOffset = Vector3.new(0, 3, 0)
	end
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60 -- only show the NPC name when you're near it (hidden from other islands)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	if textSize then
		label.TextScaled = false
		label.TextSize = textSize
	else
		label.TextScaled = true
	end
	label.Parent = bb

	bb.Parent = adornee
end
```

Called once, for the researcher:

```lua
local adornee = pickAdornee(model)
makeNameLabel(adornee, "Quest Giver")
local prompt = addPrompt(adornee, "Talk", "Quest Giver")
prompt.Name = "NestingNookTalk"
```

### `StudsOffset` vs `StudsOffsetWorldSpace`

The two branches are not interchangeable:

* **`StudsOffset`** is relative to the **adornee's orientation**. If the part is rotated,
  "up" rotates with it — a tag on a tipped-over rig ends up beside the NPC, not above it.
* **`StudsOffsetWorldSpace`** is always world-up regardless of how the part sits.

The default path uses `StudsOffset` because the researcher's head is upright. Pass
`worldYOffset` for any rig whose adornee part is rotated.

### Which part it attaches to

```lua
local function pickAdornee(model: Model): BasePart?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "head", 1, true) then
			return d
		end
	end
	return model.PrimaryPart or largestBasePart(model)
end
```

Head-first, then PrimaryPart, then the biggest part. The fallback chain matters because
these NPC rigs are inconsistent — some have a part literally named `Head`, some are a
`Dummy` with a `Cloth` root, some have no PrimaryPart set at all.

---

## 3. The default Roblox name is suppressed separately

A `Humanoid` draws its **own** overhead name and health bar, which would sit right on top
of this tag. That's killed in `clearAdornments`:

```lua
elseif d:IsA("Humanoid") then
	d.DisplayName = ""                                              -- blank the overhead name (was "Dummy")
	d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- hide the name + health bar ENTIRELY
	d.NameDisplayDistance = 0
	d.HealthDisplayDistance = 0
end
```

Setting `DisplayName = ""` alone is **not enough** — the health bar survives it. All four
lines are needed.

---

## 4. It hides while the NPC is talking

The tag sits at **+3 studs**; the speech bubble sits at **+5.5 studs** and is **150px tall**,
so the bubble's lower edge lands directly on the name. The tag is therefore switched off for
as long as a bubble is up:

```lua
local function setNameVisible(adornee: BasePart, visible: boolean)
	local nl = adornee:FindFirstChild("NameLabel")
	if nl and nl:IsA("BillboardGui") then
		nl.Enabled = visible
	end
end
```

This is why the BillboardGui's name must stay `"NameLabel"` — that string is the only
handle the speech code has on it.

**A bubble can disappear three different ways, and the tag has to come back on all three:**

| # | Path | Restores via |
|---|---|---|
| 1 | Player finishes or closes the dialogue | `closeDialogue()` → `hideSpeech()` |
| 2 | Player walks out of range mid-conversation (`DIALOGUE_CLOSE_DISTANCE = 8`) | the distance watcher → `closeDialogue()` → `hideSpeech()` |
| 3 | A one-off line auto-expires after `SPEECH_LIFETIME = 9`s | the `task.delay` branch, which destroys the bubble directly and never touches `hideSpeech` |

Paths 1 and 2 are covered by putting the restore inside `hideSpeech`. Path 3 needed its own
call, and it must stay **inside** the timer's existing guard:

```lua
task.delay(SPEECH_LIFETIME, function()
	if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then
		bb:Destroy()
		setNameVisible(adornee, true)
	end
end)
```

That guard exists so an expiring timer can't destroy a **newer** bubble that replaced its
own. Keeping the restore inside it matters for the same reason: a fresh line of dialogue
must not have its name-hiding cancelled by the previous line's timer firing late.

`showSpeech` calls `hideSpeech` first and *then* hides the name, so advancing page-to-page
never flickers the tag back on.

---

## 5. Scope — only one NPC actually has this

**`makeNameLabel` is called exactly once**, for the researcher. The other quest NPCs —
FrillRancher, CoastalFisher, MireWatcher, RidgeWarden, RaptorScout, AshWarden, the Digger,
and the mama dino — have a **ProximityPrompt but no name tag**. They rely on the prompt's
own `ObjectText` for identification.

`setNameVisible` is a no-op on any adornee without a `NameLabel`, so the hide-while-talking
logic is already safe for all of them — but it is doing nothing for them today. To give the
rest a tag, add one line per NPC beside its `addPrompt` call.

---

## 6. Re-runs don't stack duplicates

`clearAdornments(model)` destroys anything named `NestingNookTalk`, `NameLabel` or
`SpeechBubble` before rebuilding. Without it, a script re-run (or a second copy baked into
the place file) leaves two tags fighting for the same pixels.

---

## 7. Reusing it elsewhere

`makeNameLabel`, `pickAdornee` and `setNameVisible` have no dependencies beyond stock
Roblox — copy the three functions as-is. Then:

1. Suppress the `Humanoid` overhead name (§3) or you get two labels.
2. Keep the instance name `"NameLabel"` if you also want the hide-while-talking behaviour.
3. Tune `MaxDistance` to your map's scale — 60 suits islands this far apart; a single
   ground-level map wants it much higher or the tag pops in too late.
4. Pass `worldYOffset` for any rig whose adornee is rotated.
