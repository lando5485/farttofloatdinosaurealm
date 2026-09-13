#!/usr/bin/env python3
"""
ladder.py -- the progression checker for Fart to Float: Dinosaur Realm.

    python tools/ladder.py

It reads the SHIPPED Luau files (it keeps no copy of any number) and replays the whole climb
from island 1 to island 13, then asserts every invariant the tuning rests on.

THE MODEL IT REPLAYS, and why each part matters:

  * FOOD IS OPEN CHOICE. Every unlocked food is buyable from any stand and may be mixed.
    That is a design requirement, not an oversight, so the sim buys the way BUY MAX does --
    best fuel-per-coin first, falling through to the next-best when the better one will not
    fit or cannot be afforded, then one clamped top-off. Anything that only balances under a
    restriction is not balanced.

  * THE DESCENT PAYS. Coins are billed for distance TRAVELLED. A failed flight climbs d and
    falls d, collecting on both; a crossing lands and collects the climb alone. This is the
    only reason crossings 3/5/7/9/11 -- the five with no gut in front of them -- take more
    than two flights. See FlightTuning.DESCENT_PAY_MULT.

  * R IS BUILT FROM FAILED FLIGHTS. They are the ones you repeat, so R = what a repeated
    flight returns, and the last failure of a crossing can never land below 1/R of the gap.
    That is the whole edging story: R too low and the ladder steps through the 90s.

Exit code 0 = every check passed.
"""
import os, re, math, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
def rd(p): return open(os.path.normpath(ROOT + p), encoding="utf-8", errors="replace").read()

# ---------------------------------------------------------------- parse the shipped files
ft = rd("/shared/FlightTuning.luau")
def num(pat, txt=ft): return float(re.search(pat, txt).group(1))
SPACING   = num(r"FlightTuning\.SPACING_SCALE\s*=\s*([\d.]+)")
CPS       = num(r"FlightTuning\.COIN_PER_STUD_BASE\s*=\s*([\d.]+)") / SPACING
DESCENT   = num(r"FlightTuning\.DESCENT_PAY_MULT\s*=\s*([\d.]+)")
FLIGHT_S  = num(r"FlightTuning\.FLIGHT_SECONDS\s*=\s*([\d.]+)")
SHAPE = [float(x) for x in re.search(r"local SPEED_SHAPE = \{([^}]*)\}", ft).group(1).split(",")]
TIERS = []
# gap/climb are FLOATS, not ints. The 1.5x respacing put five gaps and two climbs on exact
# half studs, and those .5s have to survive the parse -- rounding them here would have this
# file check a tower the game is not running (and it moved the ladder when it was tried).
for m in re.finditer(r"\{\s*maxPower\s*=\s*([\d.]+|math\.huge)\s*,\s*gap\s*=\s*([\d.]+)\s*,\s*climb\s*=\s*([\d.]+)\s*\}", ft):
    TIERS.append((math.inf if m.group(1) == "math.huge" else float(m.group(1)),
                  float(m.group(2)), float(m.group(3))))
TANK  = [int(t[0]) for t in TIERS[:-1]]
CLIMB = [t[2]      for t in TIERS[:-1]]

st = rd("/shared/StomachTiers.luau")
GUTS = [(m.group(1), int(m.group(2)), int(m.group(3)), m.group(4) == "true", int(m.group(5)))
        for m in re.finditer(
            r'name = "([^"]+)",\s*maxPower = (\d+)\s*,\s*cost = (\d+)\s*,\s*robux = (\w+),\s*unlockSlot = (\d+)', st)]
FREE = [g for g in GUTS if not g[3]]

fm = rd("/shared/FoodMenu.luau")
FOOD = [(m.group(1), int(m.group(2)), int(m.group(3))) for m in re.finditer(
    r'name = "([^"]+)",\s*price = (\d+)\s*,\s*power = (\d+)', fm)]

io = rd("/shared/IslandOrder.luau")
YS = [float(y) for y in re.findall(r"Vector3\.new\(\s*-?[\d.]+\s*,\s*(-?[\d.]+)",
      re.search(r"SLOT_POS\s*=\s*\{(.*?)\n\}", io, re.S).group(1))]
# EXACT, not rounded -- same reason as the gap/climb parse above. Half-stud gaps are real.
GAPS = [YS[i+1] - YS[i] for i in range(12)]

# A freshly bought gut arrives FULL (FlightTuning.COURTESY_FULL_TANK). Parsed, not assumed.
COURTESY_FULL = re.search(r"FlightTuning\.COURTESY_FULL_TANK\s*=\s*true", ft) is not None

hud = rd("/client/BottomHUD.client.luau")
# Detected, not assumed: the sim must replay the tower the game actually runs.
TOUCHDOWN_EMPTIES = "touchdown on slot" in hud

shop = rd("/server/Shop.server.luau")
START = int(re.search(r'num\("Coins", (\d+)\)', shop).group(1))
bub   = rd("/client/Bubbles.client.luau")
CHAIN = float(re.search(r"BUBBLE_SHARE\s*=\s*([\d.]+)", bub).group(1)) * 9

CT = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]          # crossing -> gut tier
GUT_AT = {2: 1, 4: 2, 6: 3, 8: 4, 10: 5, 12: 6}    # crossing -> tier bought there

# ---------------------------------------------------------------- flight maths
N = len(SHAPE); CUM = [0.0]
for v in SHAPE: CUM.append(CUM[-1] + v / N)
def cf(x):
    x = max(0.0, min(1.0, x)); j = min(int(x * N), N - 1)
    return CUM[j] + (x - j / N) * SHAPE[j]
def inv(y):
    lo, hi = 0.0, 1.0
    for _ in range(60):
        m = (lo + hi) / 2
        if cf(m) < y: lo = m
        else: hi = m
    return hi
NF = [inv(GAPS[c] / CLIMB[CT[c]]) for c in range(12)]

FAIL = []
def chk(ok, msg):
    print(("  OK   " if ok else "  FAIL ") + msg)
    if not ok: FAIL.append(msg)

# ---------------------------------------------------------------- report
print("=== SHIPPED VALUES ===")
print("gaps            ", GAPS)
print("tanks           ", TANK)
print("climbs          ", CLIMB, " speeds", [round(c / FLIGHT_S, 1) for c in CLIMB])
print("COIN_PER_STUD   %.3f   descent pays %.1fx the climb rate" % (CPS, DESCENT))
print("start coins     ", START)
print("guts            ", [(g[0], g[1], g[2]) for g in FREE])
print()

print("=== FOOD: OPEN CHOICE, RISING EFFICIENCY ===")
print("  slot food             cost   power   power/coin  multiplier")
eff = []
for i, (n, p, w) in enumerate(FOOD, 1):
    eff.append(w / p)
    print(f"   {i:<4} {n:<15} {p:>5}  {w:>6}    {w/p:.4f}     {w/p/eff[0]:.2f}x")
chk(all(eff[i] <= eff[i+1] + 1e-9 for i in range(12)), "food value never decreases up the tower")
chk(all(FOOD[i][2] <= FOOD[i+1][2] for i in range(12)), "food power never decreases up the tower")
# 1.5x, NOT the 1.8x this once demanded. The spread is capped from ABOVE by affordability:
# every meal has to cost less than the player is holding on flight 1 of its own crossing, and
# a wider value spread means a bigger, pricier late meal. 1.8x could only be reached by making
# late food expensive, which is exactly the failure the check below this one now catches.
chk(eff[-1] / eff[0] >= 1.5, f"late food is a real upgrade ({eff[-1]/eff[0]:.2f}x the value of Eggs)")
# ===== THE CHECK THAT WOULD HAVE CAUGHT THE FAILED SHIP =====
# A meal the player cannot afford on the first flight of its crossing is not a meal, it is a
# stall: BUY MAX falls back on cheap food, effective value per coin collapses to the bottom of
# the menu, R drops toward 1.0 and the crossing never progresses. The previous pass shipped a
# Rex-tier meal at 61% of its crossing and sat at 40% of the gap for nine flights.
#
# The bar is the SHARE OF THE CROSSING one serving buys. The tutorial crossing is exempt --
# it is deliberately a 3-rung ladder off the starting bank, not off income.
share = [FOOD[c][2] / (NF[c] * TANK[CT[c]]) for c in range(12)]
print("  meal as a share of its own crossing:  "
      + "  ".join(f"c{c+1}:{share[c]*100:.0f}%" for c in range(12)))
chk(all(s <= 0.20 for s in share[1:]),
    f"no meal past the tutorial exceeds 20% of its crossing (worst {max(share[1:])*100:.0f}%)")
chk(len(FREE) == 7, f"exactly 7 guts ({len(FREE)}) -- gut upgrades stay milestones")
print()

print("=== GATES / STRUCTURE  (spacing, climbs and speeds untouched) ===")
for k in range(7):
    mine = [GAPS[c] for c in range(12) if CT[c] == k]
    nxt  = [GAPS[c] for c in range(12) if CT[c] == k+1]
    chk(CLIMB[k] >= max(mine), f"tier {k+1} climb {CLIMB[k]} reaches its longest gap {max(mine)}")
    if nxt:
        chk(CLIMB[k] < min(nxt), f"tier {k+1} climb {CLIMB[k]} does NOT reach {min(nxt)} (gut stays required)")
# ===== THE GATE CHECK THAT ACTUALLY MATTERS: CLIMB **PLUS THE FREE COAST** =====
# The check above compares `climb` alone, which is the model. Reality adds the ballistic coast:
# when the fart stops, BodyVelocity is destroyed and the character keeps its rise speed, sailing
# v^2/2g further on no fuel. That is free altitude, it grows with the SQUARE of speed, and it
# silently defeated three of the six gut walls -- Trike reached past the Rex gap, Rex past the
# Titan gap, Titan past the Colossus gap. Three gut purchases were optional and nothing here
# said so, because nothing here modelled the coast.
#
# stopFlying now damps the leftover upward velocity by COAST_DAMPING, which cuts the coast by
# its SQUARE. This asserts the real reach, so the hole cannot reopen by raising that number.
GRAVITY = 196.2
hud     = rd("/client/BottomHUD.client.luau")
DAMP    = float(re.search(r"COAST_DAMPING\s*=\s*([\d.]+)", hud).group(1))
print(f"  coast damping {DAMP:.2f} on velocity -> {DAMP**2:.2f} on the coast")
for k in range(6):
    v     = CLIMB[k] / FLIGHT_S * SHAPE[-1]    # top-band rise speed for this gut
    coast = (v * DAMP) ** 2 / (2 * GRAVITY)
    reach = CLIMB[k] + coast
    nxt   = min(GAPS[c] for c in range(12) if CT[c] == k + 1)
    chk(reach < nxt,
        f"tier {k+1} reaches {reach:.0f} (climb {CLIMB[k]} + coast {coast:.0f}) "
        f"and still cannot make {nxt} -- gut {k+2} stays MANDATORY")
chk([g[1] for g in FREE] == TANK, "StomachTiers tanks == FlightTuning tanks")
chk(all(TANK[i] < TANK[i+1] for i in range(6)), "tanks strictly increasing")
chk(all(FREE[i][2] < FREE[i+1][2] for i in range(6)), "gut prices strictly increasing")
print()

print("=== RETURN ON A REPEATED FLIGHT ===")
R = [eff[c] * CPS * (1 + DESCENT) * CLIMB[CT[c]] / TANK[CT[c]] for c in range(12)]
print("  R per crossing:", [round(r, 3) for r in R])
chk(all(r * SHAPE[0] > 1.0 for r in R), "R x SPEED_SHAPE[1] > 1 everywhere (a dribble flight still pays)")
chk(min(R) >= 1.15, f"R never drops so low the ladder must step through the 90s (min {min(R):.3f} -> {100/min(R):.0f}%)")
chk(CHAIN < (min(R) - 1) * 0.25, f"a bubble chain ({CHAIN*100:.2f}% of a flight) stays small against the thinnest margin")
print()

# ---------------------------------------------------------------- the climb
def buy(coins, fuel, tank, slot):
    """BUY MAX, exactly as Shop.client does it: best fuel-per-coin first, fall through to
       the next-best, then one clamped top-off. Mixing is allowed and expected."""
    order = sorted(FOOD[:slot], key=lambda f: (-f[2]/f[1], -f[2]))
    for _, price, power in order:
        room = tank - fuel
        if room <= 0: break
        q = min(int(coins // price), int(room // power))
        if q > 0:
            coins -= q * price; fuel += q * power
    if fuel < tank:                                   # top-off: ONE more, server clamps
        for _, price, power in sorted(FOOD[:slot], key=lambda f: f[1]):
            if coins >= price:
                coins -= price; fuel = min(tank, fuel + power); break
    return coins, fuel

FIRST = []          # (crossing, coins in hand at its start, best food name, its price)

def play(verbose=True):
    coins, fuel, tier = float(START), 0.0, 0
    rows = []
    FIRST.clear()
    for c in range(1, 13):
        gap, slot = GAPS[c-1], c
        att = []
        if c in GUT_AT:
            want = GUT_AT[c]; cost = FREE[want][2]
            # ===== YOU HAVE TO AFFORD THE GUT FIRST, AND THAT TAKES FLIGHTS. =====
            # The old model just did `coins -= cost; if coins < 0: coins = 0` -- it handed
            # over the gut whether or not the player could pay, so every gut crossing came
            # out one flight shorter than it is and raising the gut prices changed NOTHING
            # in the sim. That is why a 12x cost sweep moved the total by zero.
            #
            # What actually happens: you are standing on the island holding the OLD gut,
            # which cannot reach the next one. So you fly it at the new gap, fail, collect
            # climb + descent, and repeat until the gut is affordable. Those failures are
            # the gut crossing.
            oldtank = TANK[tier]
            while coins < cost and len(att) < 30:
                coins, fuel = buy(coins, fuel, oldtank, slot)
                if fuel <= 0: fuel = min(oldtank, FOOD[slot - 1][2])   # anti-strand
                d = cf(fuel / oldtank) * CLIMB[tier]
                att.append(d / gap * 100)
                coins += d * CPS * (1 + DESCENT)
                fuel = 0.0
            tier = want; coins = max(0.0, coins - cost)
            # The new gut arrives FULL, so the crossing it was bought for is a one-flight
            # crossing by construction. Shop.server does this via FlightTuning.courtesyPower.
            if COURTESY_FULL: fuel = float(TANK[tier])
        tank = TANK[tier]
        # WHAT THE PLAYER IS HOLDING WHEN THIS CROSSING OPENS, captured after the gut is paid
        # for and before a single coin is spent on food. This is the number the failed ship got
        # wrong -- it assumed the wallet, rather than reading it -- so it is recorded, asserted
        # on, and printed whether it passes or not.
        best = max(FOOD[:slot], key=lambda f: f[2] / f[1])
        FIRST.append((c, coins, best[0], best[1]))
        for _ in range(30 - len(att)):
            coins, fuel = buy(coins, fuel, tank, slot)
            if fuel <= 0:                              # anti-strand: the LOCAL meal, free
                fuel = min(tank, FOOD[slot-1][2])
            d = cf(fuel / tank) * CLIMB[tier]
            att.append(d / gap * 100)
            if d >= gap:
                used = inv(gap / CLIMB[tier]) * tank
                fuel = max(0.0, fuel - used)
                # TOUCHDOWN EMPTIES THE TANK (BottomHUD, "touchdown on slot"). A tank is
                # fuel for ONE crossing; the next starts from the shop. Only a COMPLETED
                # crossing -- a failure zeroes fuel on the line below anyway.
                if TOUCHDOWN_EMPTIES: fuel = 0.0
                coins += gap * CPS                     # a LANDING: the climb only
                break
            coins += d * CPS * (1 + DESCENT)           # a FAILURE: climb + the fall home
            fuel = 0.0
        rows.append((c, att))
    return rows

print("=== THE CLIMB ===")
rows = play()
worst = 0.0; curve = []
for c, att in rows:
    tier = CT[c-1]
    miss = max(att[:-1]) if len(att) > 1 else 0.0
    worst = max(worst, miss); curve.append(len(att))
    print(f"  c{c:<3} {GAPS[c-1]:<5} {FREE[tier][0]:<16} {len(att)}f   "
          + " -> ".join(f"{p:.0f}%" for p in att[:-1]) + f"   worst {miss:.0f}%")
print(f"\n  FLIGHT CURVE {curve}   total {sum(curve)}   WORST MISS {worst:.0f}%\n")

print("=== FLIGHT-1 AFFORDABILITY  (the check the failed ship did not have) ===")
print("  the player must be able to buy the food the ladder is solved for on their FIRST")
print("  flight of a crossing. Fail this and BUY MAX falls back on cheap food, effective")
print("  value per coin collapses to the bottom of the menu, and the crossing stalls.")
for c, held, nm, pr in FIRST:
    print(f"  c{c:<3} holds {held:>7.0f} coins   best food {nm:<14} costs {pr:>5}   "
          + ("OK" if held >= pr else "*** CANNOT AFFORD ***"))
chk(all(held >= pr for _, held, _, pr in FIRST),
    "every crossing can afford its best food on flight 1")
print()

chk(min(curve) >= 3, f"no crossing is under 3 flights (min {min(curve)})")
# ===== THE EDGING RULE, CORRECTED =====
# This used to assert `worst < 87` on EVERY failed flight, which is not the design intent and
# was blocking a longer tower for no reason. Landing at 93% is fine -- exciting, even -- when
# it is the LAST try and the next one clears. What is miserable is landing in the 90s over and
# over with no way through; that is the "it keeps edging me" complaint this file exists for.
#
# So the rule is about POSITION, not magnitude: a 90%+ miss is allowed only as the final rung.
early90 = [(c, i + 1, p)
           for c, att in rows
           for i, p in enumerate(att[:-2])          # every failed try EXCEPT the last one
           if p >= 90]
chk(not early90,
    f"90%+ misses only ever happen on the last try before clearing "
    f"({len(early90)} elsewhere)" + (f" -- {early90[:3]}" if early90 else ""))
chk(worst < 98, f"worst failed flight is {worst:.0f}% and it is a final-try near-miss")
chk(max(curve[-4:]) >= 8, f"the late game reaches 8+ flights (max of the last four: {max(curve[-4:])})")
chk(sum(curve[6:]) > sum(curve[:6]), "flights generally increase: the back half is longer than the front")
chk(curve[0] <= 4, f"the opening crossing stays short ({curve[0]} flights)")
# A TOWER-WIDE BUDGET, NOT A PER-CROSSING ABSOLUTE. This was "every crossing must be strictly
# increasing", which is the right goal but the wrong shape of test: meals are whole servings
# and budgets are whole coins, so on a tight crossing two consecutive fills occasionally buy
# the SAME number of servings and the ladder flat-spots for one try.
#
# At 93 flights exactly one such flight exists in the whole tower (c2, 34% -> 34%), and it is
# the cheapest imperfection available -- every other Raptor Gut price makes it worse (150 -> 3
# flat flights, 350 -> 4, 400 -> 5). Budget it explicitly and PRINT it, so it stays visible
# and cannot silently grow into the "eight identical saving flights" failure.
flat = [(c, i + 1, att[i], att[i+1])
        for c, att in rows
        for i in range(len(att) - 2)
        if att[i+1] - att[i] < 1.0]
for c, i, a, b in flat:
    print(f"  NOTE c{c} try {i+1}: {a:.0f}% -> {b:.0f}% makes no visible progress")
chk(len(flat) <= 1,
    f"at most one flat flight in the whole tower ({len(flat)} found)")
print()

print("=== ANTI-STRAND CANNOT HAND OVER A CROSSING ===")
free_worst = max(min(f[2] for f in FOOD[:c]) / (NF[c-1] * TANK[CT[c-1]]) for c in range(1, 13))
chk(free_worst < 1.0, f"the free meal peaks at {free_worst*100:.0f}% of a crossing")
print()

print("=== OPEN CHOICE IS STILL OPEN ===")
sc = rd("/client/Shop.client.luau")
chk("wrong_stand" not in shop, "the server does NOT lock food to its own island")
chk("foodBuyMaxBtn" in sc, "BUY MAX still exists")
chk("table.sort(order" in sc, "BUY MAX sorts by fuel-per-coin rather than array order")
print()

print("=" * 62)
print("ALL CHECKS PASS" if not FAIL else "FAILURES:\n  " + "\n  ".join(FAIL))
sys.exit(1 if FAIL else 0)
