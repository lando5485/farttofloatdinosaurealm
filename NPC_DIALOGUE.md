# NPC Overhead Dialogue — spec + copy (for porting to Candy Realm)

Everything lives in `src/server/NestingNook_NPCs.server.luau`:
`showSpeech()` (line 281) draws the bubble, `wireDialogue()` (line 892) pages it.

---

## 1. How it LOOKS

A rounded white BillboardGui floating above the NPC's head part.

| Property | Value |
|---|---|
| Instance | `BillboardGui` named `SpeechBubble`, parented to + adorned to the head part |
| Size | `UDim2.new(0, 320, 0, 150)` — 320×150 px |
| Offset | `StudsOffset = Vector3.new(0, 5.5, 0)` (5.5 studs above head) |
| AlwaysOnTop | `true` |
| MaxDistance | `120` studs (fades out past that) |
| Background | white `Color3.new(1,1,1)`, `BackgroundTransparency = 0.05` |
| Corner | `UICorner` radius `18` px |
| Outline | `UIStroke` color `RGB(60,60,60)`, thickness `2`, transparency `0.4` |
| Padding | top/bottom `12`, left/right `14` |
| Body text | Font `FredokaOne`, color `RGB(35,35,35)`, `TextScaled`, `TextWrapped`, max text size **22** |
| Body height | `1.0` scale if no footer, `0.78` if there is one |
| Footer hint | bottom `0.2` scale at y `0.8`, Font `FredokaOne`, color `RGB(130,130,130)`, max text size **14** |

For Candy Realm the only things I'd change are the palette — swap the white/grey
fill+stroke for candy pastels (e.g. fill `RGB(255, 240, 248)`, stroke `RGB(214, 92, 158)`,
text `RGB(74, 30, 58)`) and keep FredokaOne, it already reads as candy.

## 2. How it ACTS

- **Trigger:** a `ProximityPrompt` on the NPC. Default `ActionText = "Talk"`, `HoldDuration = 0`, `RequiresLineOfSight = false`.
- **Prompt range** is set to `DIALOGUE_CLOSE_DISTANCE` (**8 studs**) so the prompt appears in exactly the range the conversation stays open — no zone where it opens then instantly shuts.
- **Paging:** each `E` press advances one page. `ActionText` becomes `"Continue"`, and `"Close"` on the last page. One more `E` closes and resets to `"Talk"`.
- **Footer text:** `"[E] more  (%d/%d)"` on every page but the last; `"[E] close"` on the last.
- **Pages are fetched fresh on page 1** (`getPages()`), so quest-progress counters in the text are always current.
- **Quest handoff fires on page 2** — `onTalk(player)` is called when `index == 2`, i.e. the player has actually read a bit before getting the quest.
- **Walk-away close:** a `task.spawn` watcher polls every `0.25s` while a conversation is open and closes it the moment no player is within 8 studs. `PromptHidden` also closes it immediately.
- **Non-paged bubbles** (reactive one-liners like "You found one!") pass `persist = false` and auto-destroy after `SPEECH_LIFETIME = 9` seconds.

---

## 3. The dialogue, verbatim

### Mama Dino — `dino1`, island1 (prompt reads "Baby Dino" / "Mama Dinosaur")
Completed:
```
You found all my eggs!
Thank you so much! 💚
```
In progress:
```
My 5 eggs are missing!
Please bring them back to the nest.
Found: %d of %d.
```
Reactive one-liners (9s auto-hide):
```
You found one! Welcome home, little egg. (%d/%d found)
That's all of them! My family is reunited at last. Thank you so much! 💚
```

### Quest Giver / The Researcher — `miner`, island1
Completed:
```
All the eggs are back home. Nice work!
```
In progress:
```
Some critters took the dino's 5 eggs.
Find them and bring them to the nest.
You have %d of %d.
```

### The Digger — `DigMiner`, island3
```
There are fossils buried here.
Take this shovel.
Dig the dirt spots to find an egg!
```

### The Rancher — `FrillRancher`, island2
```
There's a Triceratops egg in the ferns.
Find it and press E to hatch it!
```

### The Fisher — `CoastalFisher`, island4
```
Grab the fishing rod from the barrel.
Fish the lake until you catch an egg.
Hatch it to get a Megalodon!
```

### The Mire Watcher — `MireWatcher`, island5
```
Welcome to the Misty Mire.
Big mosquitos are buzzing above us.
Click them and swat them in the mini-game!
Feed 5 to the nest and a baby Spinosaurus will hatch!
```

### The Warden — `RidgeWarden`, island6 (Redwood Ridge)
```
Welcome to Redwood Ridge.
Five raptors prowl these woods.
Only ONE is hiding a secret egg.
Grab a sniper and hunt them down to find it!
```

### The Scout — `RaptorScout`, island7 (Raptor Ridge)
```
This is Raptor Ridge.
A raptor nest is starving -- its eggs won't hatch!
Grab the meat scattered around the island.
Carry it back and feed the nest -- 5 pieces.
Do it, and a baby raptor will hatch for you!
```

### The Ash Warden — `AshWarden`, island11 (Volcanic Vista)
```
The volcano is about to blow!
Six geysers are building up pressure.
Plug every geyser to stop the eruption!
Save us, and a mighty T-Rex egg will hatch.
```

**Known bug worth NOT porting:** `setupIslandQuestNPC` hardcodes every island NPC's
prompt `ObjectText` to `"Researcher"` (line 1194) regardless of the `title` field, so
"The Rancher", "The Fisher" etc. are passed in but never rendered anywhere.

---

## 4. Drop-in module for Candy Realm

Save as `src/server/NPCDialogue.luau` (ModuleScript) and require it.

```lua
local Players = game:GetService("Players")

local SPEECH_LIFETIME = 9        -- seconds before a non-paged bubble auto-hides
local CLOSE_DISTANCE  = 8        -- studs; conversation closes past this

-- Candy Realm palette
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(214, 92, 158)
local TEXT   = Color3.fromRGB(74, 30, 58)
local HINT   = Color3.fromRGB(170, 130, 150)

local M = {}

function M.hide(adornee: BasePart)
	local prev = adornee:FindFirstChild("SpeechBubble")
	if prev then prev:Destroy() end
end

function M.show(adornee: BasePart, text: string, persist: boolean?, footer: string?)
	M.hide(adornee)

	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = FILL
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = TEXT
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = frame

	local sizer = Instance.new("UITextSizeConstraint")
	sizer.MaxTextSize = 22
	sizer.Parent = label

	if footer then
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.fromScale(1, 0.2)
		hint.Position = UDim2.fromScale(0, 0.8)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.FredokaOne
		hint.Text = footer
		hint.TextColor3 = HINT
		hint.TextScaled = true
		hint.Parent = frame
		local hsizer = Instance.new("UITextSizeConstraint")
		hsizer.MaxTextSize = 14
		hsizer.Parent = hint
	end

	bb.Parent = adornee

	if not persist then
		task.delay(SPEECH_LIFETIME, function()
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then
				bb:Destroy()
			end
		end)
	end
end

function M.addPrompt(part: BasePart, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- getPages() is called fresh on page 1 so counters stay current.
-- onTalk(player) fires once the player reaches page 2.
function M.wire(prompt: ProximityPrompt, adornee: BasePart, getPages: () -> { string }, onTalk: ((Player) -> ())?)
	prompt.MaxActivationDistance = CLOSE_DISTANCE

	local pages: { string }? = nil
	local index = 0
	local watching = false

	local function closeDialogue()
		M.hide(adornee)
		prompt.ActionText = "Talk"
		index = 0
		pages = nil
	end

	local function playerInRange(): boolean
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and (hrp.Position - adornee.Position).Magnitude <= CLOSE_DISTANCE then
				return true
			end
		end
		return false
	end

	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				if not playerInRange() then
					closeDialogue()
					break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function(player)
		if index == 0 then
			pages = getPages()
		end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			return
		end
		if index == 2 and onTalk and player then
			onTalk(player)
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		M.show(adornee, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)

	prompt.PromptHidden:Connect(function()
		if index ~= 0 then
			closeDialogue()
		end
	end)
end

return M
```

Usage:

```lua
local Dialogue = require(script.Parent.NPCDialogue)

local head = candyNPC:FindFirstChild("Head")
local prompt = Dialogue.addPrompt(head, "Talk", "The Candy Maker")

Dialogue.wire(prompt, head, function()
	if collected.Value >= total.Value then
		return { "You gathered every gumdrop!", "The factory is saved! 🍬" }
	end
	return {
		"My gumdrops rolled all over the realm!",
		"Bring them back to the candy vat.",
		("Found: %d of %d."):format(collected.Value, total.Value),
	}
end, function(player)
	giveCandyQuest(player)
end)
```
