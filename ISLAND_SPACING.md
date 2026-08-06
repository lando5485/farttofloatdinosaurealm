# Island Spacing (Islands 1–14)

The LIVE placement table. Source of truth: `_G.ISLAND_POS` in
`src/client/CoreClient.client.lua` (line 162), identical to `ISLAND_POSITIONS`
in `src/server/PlayerStats.server.lua`. (The table in `CLAUDE.md` — y=50,600,1400… —
is STALE; ignore it.)

## Exact positions

| # | Island            | X    | Y      | Z    | ΔY from prev (vertical gap) |
|---|-------------------|------|--------|------|------------------------------|
| 1 | Bean Farm         | 0    | 150    | 0    | —                            |
| 2 | Broccoli Bluff    | 120  | 790    | 60   | 640                          |
| 3 | Cabbage Cliffs    | -160 | 1680   | 100  | 890                          |
| 4 | Turnip Tranquil   | 180  | 2480   | -120 | 800                          |
| 5 | Coconut Cove      | -200 | 3580   | 160  | 1100                         |
| 6 | Bread Board       | 220  | 4820   | -180 | 1240                         |
| 7 | Pasta Peak        | -240 | 6460   | 200  | 1640                         |
| 8 | Popcorn Pinnacle  | 260  | 8202   | -220 | 1742                         |
| 9 | Milk Marsh        | -280 | 9732   | 240  | 1530                         |
| 10| Butter Swamp      | 300  | 11978  | -260 | 2246                         |
| 11| Ice Cream Isle    | -320 | 14194  | 280  | 2216                         |
| 12| Burger Bluff      | 340  | 17138  | -300 | 2944                         |
| 13| Burrito Barrens   | -360 | 20206  | 320  | 3068                         |
| 14| Pizza Palms       | 380  | 24017  | -340 | 3811                         |

## How the spacing works

- **Vertical (Y):** the gap between consecutive islands GROWS as you climb —
  starts ~640 studs (1→2) and ramps to ~3811 studs (13→14). Total climb from
  island 1 to 14 = **23,867 studs** (150 → 24,017).
- **X (sideways):** ALTERNATES sign each island (+ then −) and grows in magnitude:
  0, 120, -160, 180, -200, 220, -240, 260, -280, 300, -320, 340, -360, 380.
  So each island is offset to the opposite side of the one below it (a zig-zag),
  widening by 20 studs per step.
- **Z (depth):** also ALTERNATES sign and grows: 0, 60, 100, -120, 160, -180,
  200, -220, 240, -260, 280, -300, 320, -340 — the same zig-zag on the depth axis.

So the tower spirals/zig-zags side to side and front to back while the vertical
gaps stretch out the higher you go.

## Copy-paste (Lua)

```lua
local ISLAND_POS = {
	{x=0,y=150,z=0},{x=120,y=790,z=60},{x=-160,y=1680,z=100},
	{x=180,y=2480,z=-120},{x=-200,y=3580,z=160},{x=220,y=4820,z=-180},
	{x=-240,y=6460,z=200},{x=260,y=8202,z=-220},{x=-280,y=9732,z=240},
	{x=300,y=11978,z=-260},{x=-320,y=14194,z=280},{x=340,y=17138,z=-300},
	{x=-360,y=20206,z=320},{x=380,y=24017,z=-340},
}
```
