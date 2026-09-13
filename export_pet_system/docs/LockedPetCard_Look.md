# Locked Pet Card — the EXACT food-realm look (hand this to Dino Realm)

This is how the Fart to Float (food realm) Pet Hub draws a pet the player does NOT own yet:
same blue card as an owned pet, pet shown in FULL COLOUR (spinning 3D model, not greyed out),
and a little 🔒 padlock badge in the TOP-RIGHT corner of the picture.

Source of truth: `src/client/PetFollow.client.lua` — `buildLockedPetCard` (line ~4922).

---

## 1. Design rules (why it looks this way)

- The pet is shown in **full colour**, exactly as it really looks — seeing the actual prize is
  what makes a player want it. **Never grey out or silhouette the pet.**
- "Locked" is communicated by THREE things only:
  1. the **🔒 padlock badge** floating over the top-right of the picture,
  2. the **gold "🔒 LOCKED" line** under the name,
  3. the how-to-get-it hint text.
- The **only** things missing vs an owned card are the EQUIP / SKIP buttons (nothing to equip yet).
- The card border is **gold** (255,190,60) thickness 2 — locked cards pop in the grid.
- The card is **not click-through**; only the gold-brown "🔒 VIEW QUEST" button opens the detail view.

## 2. Grid it sits in

Cards live in a ScrollingFrame with a `UIGridLayout`:

```lua
petsGrid.CellSize    = UDim2.new(0, 322, 0, 252)
petsGrid.CellPadding = UDim2.new(0, 10, 0, 12)
```

## 3. Exact element-by-element spec

| Element | Class | Size / Position | Style |
|---|---|---|---|
| Card | Frame | 322x252 grid cell | Bg `Color3.fromRGB(20,70,160)` (same blue as owned), UICorner 12, UIStroke `Color3.fromRGB(255,190,60)` thickness 2 |
| Pet picture | ViewportFrame | `UDim2.new(0,310,0,140)` at `UDim2.new(0.5,0,0,6)`, AnchorPoint `(0.5,0)` | Full-colour spinning 3D model, Lv1 look (level=1, rare=false) |
| **🔒 padlock badge** | TextLabel | `Size UDim2.new(0,28,0,28)`, `Position UDim2.new(1,-12,0,12)`, `AnchorPoint Vector2.new(1,0)` | BackgroundTransparency 1, Font `FredokaOne`, `TextScaled = true`, Text `"\xF0\x9F\x94\x92"` (🔒). Parented to the CARD (so it floats over the picture's top-right corner) |
| Name | TextLabel | `UDim2.new(1,-16,0,18)` at `UDim2.new(0,8,0,150)` | GothamBold 16, white, `info.displayName` |
| LOCKED line | TextLabel | `UDim2.new(1,-16,0,16)` at `UDim2.new(0,8,0,170)` | GothamBold 13, **gold `Color3.fromRGB(255,205,90)`**, text `"🔒 LOCKED  •  <IslandName>"` |
| Progress line | TextLabel | `UDim2.new(1,-20,0,14)` at `UDim2.new(0,10,0,188)` | Gotham 12, `Color3.fromRGB(175,205,250)`, left-aligned, TextTruncate AtEnd, text `"<IslandName>   ·   X / Y Skins"` (drop or repurpose if Dino Realm has no skins) |
| How-to hint | TextLabel | `UDim2.new(1,-20,0,26)` at `UDim2.new(0,10,0,204)` | Gotham 12, `Color3.fromRGB(205,222,255)`, wrapped, top-aligned, `info.unlock` or `"Keep exploring to find this pet"` |
| VIEW QUEST button | TextButton | `UDim2.new(1,-16,0,20)` at `UDim2.new(0,8,0,230)` | Bg **gold-brown `Color3.fromRGB(150,110,30)`** (owned cards use blue here), GothamBold 12, white, text `"🔒 VIEW QUEST"`, UICorner 6, UIStroke `Color3.fromRGB(90,66,16)` 1 |

Emoji are written as UTF-8 byte escapes in source: 🔒 = `"\xF0\x9F\x94\x92"`, • = `"\xE2\x80\xA2"`, · = `"\xC2\xB7"`.

## 4. Verbatim code (from PetFollow.client.lua)

```lua
-- A LOCKED pet card -- one for every pet in the catalog the player does NOT own yet. The pet is shown in FULL
-- COLOUR, exactly as it really looks (same blue card, same spinning 3D model as an owned pet) -- seeing the actual
-- prize is what makes a player want it. "Locked" is communicated by the padlock badge, the gold LOCKED line and
-- the how-to-get-it text, NOT by hiding or greying the pet. The only thing missing vs an owned card is the
-- EQUIP/SKIP buttons (there's nothing to equip yet). The hint says where to go, never where things hide.
local function buildLockedPetCard(info, order)
	local petId = info.petId
	local card = Instance.new("Frame"); card.Name = "Locked_" .. tostring(petId); card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(20, 70, 160); card.Parent = petsScroll -- SAME blue as an owned card
	uicorner(card, 12); uistroke(card, Color3.fromRGB(255, 190, 60), 2) -- gold "locked" border
	makeViewportIcon(card, petId, 1, false, UDim2.new(0,310,0,140), UDim2.new(0.5,0,0,6), Vector2.new(0.5,0)) -- full colour, Lv1 look
	-- padlock badge over the top-right of the picture -- this (not a grey-out) is what marks the card as locked
	local lock = Instance.new("TextLabel"); lock.Size = UDim2.new(0,28,0,28); lock.Position = UDim2.new(1,-12,0,12); lock.AnchorPoint = Vector2.new(1,0)
	lock.BackgroundTransparency = 1; lock.Font = Enum.Font.FredokaOne; lock.TextScaled = true; lock.Text = "\xF0\x9F\x94\x92"; lock.Parent = card
	local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1,-16,0,18); nm.Position = UDim2.new(0,8,0,150)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16
	nm.TextColor3 = Color3.new(1,1,1); nm.Text = info.displayName or petId; nm.Parent = card
	local st = Instance.new("TextLabel"); st.Size = UDim2.new(1,-16,0,16); st.Position = UDim2.new(0,8,0,170)
	st.BackgroundTransparency = 1; st.Font = Enum.Font.GothamBold; st.TextSize = 13
	st.TextColor3 = Color3.fromRGB(255,205,90); st.Text = "\xF0\x9F\x94\x92 LOCKED" .. (info.islandName and ("  \xE2\x80\xA2  " .. info.islandName) or ""); st.Parent = card
	-- realm + skin-progress line so the grid reads consistently (drop if the realm has no skins)
	do
		local ownedSk, totalSk = _G.PetHub.skinCount(petId)
		local rs = Instance.new("TextLabel"); rs.Size = UDim2.new(1,-20,0,14); rs.Position = UDim2.new(0,10,0,188)
		rs.BackgroundTransparency = 1; rs.Font = Enum.Font.Gotham; rs.TextSize = 12
		rs.TextColor3 = Color3.fromRGB(175,205,250); rs.TextXAlignment = Enum.TextXAlignment.Left
		rs.TextTruncate = Enum.TextTruncate.AtEnd; rs.Parent = card
		rs.Text = (info.islandName or "???") .. "   \xC2\xB7   " .. ownedSk .. " / " .. totalSk .. " Skins"
	end
	local how = Instance.new("TextLabel"); how.Size = UDim2.new(1,-20,0,26); how.Position = UDim2.new(0,10,0,204)
	how.BackgroundTransparency = 1; how.Font = Enum.Font.Gotham; how.TextSize = 12; how.TextWrapped = true
	how.TextColor3 = Color3.fromRGB(205,222,255); how.TextYAlignment = Enum.TextYAlignment.Top
	how.Text = info.unlock or "Keep exploring to find this pet"; how.Parent = card
	-- VIEW QUEST, not VIEW MORE: a locked pet has nothing to customise, so the only useful thing this page can
	-- tell you is how to earn it. The card is deliberately NOT click-through either.
	local more = Instance.new("TextButton"); more.Size = UDim2.new(1,-16,0,20); more.Position = UDim2.new(0,8,0,230)
	more.BackgroundColor3 = Color3.fromRGB(150,110,30); more.Font = Enum.Font.GothamBold; more.TextSize = 12
	more.TextColor3 = Color3.new(1,1,1); more.Text = "\xF0\x9F\x94\x92 VIEW QUEST"; more.Parent = card
	uicorner(more, 6); uistroke(more, Color3.fromRGB(90,66,16), 1)
	more.MouseButton1Click:Connect(function() _G.PetHub.showDetail(nil, info) end)
end
```

## 5. Dependencies the code assumes (replace with Dino Realm's own)

- `uicorner(inst, r)` / `uistroke(inst, color, thickness)` — tiny helpers that add a UICorner / UIStroke.
- `makeViewportIcon(card, petId, level, isRare, sizeU, posU, anchorV)` — builds a ViewportFrame with the
  pet's 3D model, queued through an icon worker; a shared RenderStepped loop slowly spins every icon
  (0.6 rad/s, only while the panel is visible). If Dino Realm renders pets differently, keep the
  **310x140 picture at top-centre** and put the padlock over it the same way.
- `_G.PetHub.skinCount(petId)` — only for the skins line; skip that block if there are no skins.
- `_G.PetHub.showDetail(nil, info)` — opens the big detail card; wire to whatever detail view exists.
- `petsScroll` — the grid ScrollingFrame (cells 322x252, padding 10x12).

## 6. How locked cards get into the grid

The rebuild loop first builds all OWNED cards (sorted best-first), then appends one locked card for
**every catalog pet not owned**, in catalog order, continuing the same `order` counter — so locked
pets always trail owned pets in the same grid.
