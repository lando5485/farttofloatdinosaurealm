# Pet Look Guide — changing how the dinosaur pets look

Everything about the 6 pets' appearance lives in 7 files. This is how to change
them yourself, and how to find floating parts without guessing.

---

## The fast loop (do this first)

Without this you are editing blind and every change costs a round trip.

```
rojo serve
```

Then in Studio: **Plugins → Rojo → Connect**. Now every save to
`src/server/*.server.luau` syncs into Studio live. Press Play, look at the pet,
change a number, press Play again. Seconds, not rounds.

---

## Where the numbers are

| What | File |
|---|---|
| **All 6 faces** (eyes, fangs) | `src/shared/PetFace.luau` |
| Stegosaurus body/plates/tail | `src/server/Stegosaurus.server.luau` |
| Velociraptor | `src/server/Velociraptor.server.luau` |
| Megalodon | `src/server/Shark.server.luau` |
| Triceratops | `src/server/Triceratops.server.luau` |
| Spinosaurus | `src/server/Spinosaurus.server.luau` |
| T‑Rex | `src/server/Tyrannosaurus.server.luau` |

### Changing every face at once

`src/shared/PetFace.luau` → the `TUNING` table. Change one number, **all six
pets change together**:

```lua
EYE_DIA  = 0.98   -- eyeball size.      bigger  = cuter
EYE_GAP  = 0.44   -- +/- sideways.      smaller = closer together = cuter
FANG_W/H = ...    -- fang size.         smaller = friendlier
```

The triceratops was the pet that looked right, so these are its proportions.

---

## Reading a part line

Every visible piece is one line:

```lua
P("Snout", BAL, 1.5,0.75,0.90, BODY, 2.15,-0.25,0)
--  name   shape   size x,y,z   colour   position x,y,z
```

- **+X = forward** (the face). **-X = the tail.** **+Y = up.** **Z = sideways.**
- `BAL` = ball/egg, `BLK` = box, `CYL` = tube.
- The cube body is **3.4 wide (X), 3.6 tall (Y), 3.8 deep (Z)** before scaling,
  so **the front face of the cube is at x = 1.7**. A part at `x = 2.15` sticks
  out in front of the face; a part at `x = 1.5` is buried inside it.

### `S(...)` vs `weldTo(P(...))`

- `S("Foot", ...)` — **fused into the body** as one smooth solid. Use for pieces
  that are the same colour as the body (head, legs, tail).
- `weldTo(P("Eye", ...), body)` — **stuck on top**, keeps its own colour. Use for
  eyes, teeth, belly, claws, stripes.

A fused part must be added **before** the `fuse(m, src, ...)` line.

---

## Finding floating parts

Run `tools/PetFloatCheck.studio.luau` — paste it into Studio's **Command Bar**
after pressing Play. It tests the real models in the real engine and prints:

```
FLOATING  Tooth   -- touches nothing
THIN      Jaw (4% into Snout)
```

### The rule that decides attached vs floating

> A part looks attached when its **centre is inside** its neighbour — not when
> the two surfaces merely touch.

Two balls that just graze each other still read as two balls with a pinch
between them. Move the part's position toward its neighbour until its centre is
inside, then re-run the checker.

**Worked example.** A tooth at `x = 1.9` floats because the mouth ball is
`0.84` deep centred at `1.52`, so the mouth ends at `1.52 + 0.42 = 1.94` — but
only at its very centre; out at the corners it ends much earlier. Move the tooth
to `x = 1.84` and it roots into the mouth.

---

## Things that will bite you

- **Teeth**: long rows of triangles never line up and read as a sawblade. The
  pets that look best have 2 fangs or none at all.
- **Clutter**: the raptor once had 22 overlapping pieces on one flat face. It
  looked like a pile. Fewer, bigger shapes read better than many small ones.
- **Glints** must sit *on* the pupil disc, or they hang in the air in front of
  the eye.
- **Ball parts are ellipsoids** — `Size` stretches them on each axis
  independently.
- If `UnionAsync` fails the parts stay separate and get renamed `BodyUnionChunk`.
  Check Output for `BodyUnion size = ...` to confirm the fuse worked.
