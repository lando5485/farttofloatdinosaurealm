#!/usr/bin/env python3
"""
petxray.py -- render a Fart to Float pet as ASCII, from its shipped builder file.

WHY THIS EXISTS
    Pet geometry was being authored blind: write coordinates, ship, wait for a human to
    describe the result in words, guess which number caused it. Five rounds of that produced
    a Brachiosaurus with no neck and a T-Rex with floating teeth, because "it looks like
    stacked cylinders" does not identify a line of code.

    This renders the pet from the SAME table the game builds it from, so the geometry can be
    checked BEFORE it ships. The pet builders print the identical view at runtime, so the two
    can be compared: if they differ, the running build is not this source.

USAGE
    python tools/petxray.py src/server/Brachiosaurus.server.luau
    python tools/petxray.py src/server/*.server.luau

REQUIREMENTS OF THE BUILDER FILE
    It must declare, in this exact shape (the parser is deliberately dumb):

        local PSS = 0.72
        local CUBE = { 3.15, 3.00, 2.85, 0.78 }        -- W, H, D, corner radius
        local FEATURES = {
            { "Head", BAL, 1.15,0.92,0.86, BODY, 1.82,4.30,0.00 },
            { "Neck", BAL, 1.02,3.60,1.02, BODY, 1.25,2.33,0.00, "Z", -15.5 },
        }

    Sizes and positions are in UNSCALED studs (the builder multiplies by PSS). Optional
    trailing "AXIS", degrees applies a rotation about X, Y or Z.
"""
import re, sys, math, glob, os

BAL, BLK, CYL = "BAL", "BLK", "CYL"

# ---------------------------------------------------------------- parsing
def parse(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"local PSS\s*=\s*([\d.]+)", src)
    if not m:
        return None
    pss = float(m.group(1))
    m = re.search(r"local CUBE\s*=\s*\{\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\}", src)
    cube = tuple(float(x) for x in m.groups()) if m else None
    # STRUCT = parts that join the body union; FEATURES = parts welded on top.
    # Both are drawn: what matters for "does this look right" is the geometry, not how it fuses.
    chunks = []
    for tbl in ("STRUCT", "FEATURES"):
        m2 = re.search(r"local %s\s*=\s*\{(.*?)\n\}" % tbl, src, re.S)
        if m2:
            chunks.append(m2.group(1))
    if not chunks:
        return None
    rows_text = "\n".join(chunks)
    feats = []
    row = re.compile(
        r'\{\s*"([^"]+)"\s*,\s*(BAL|BLK|CYL)\s*,'
        r'\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,'
        r'\s*"?(\w+)"?\s*,'
        r'\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*'
        r'(?:,\s*"([XYZ])"\s*,\s*(-?[\d.]+)\s*)?\}')
    for m in row.finditer(rows_text):
        n, sh, sx, sy, sz, col, x, y, z, ax, deg = m.groups()
        feats.append(dict(name=n, shape=sh, size=(float(sx), float(sy), float(sz)),
                          color=col, pos=(float(x), float(y), float(z)),
                          axis=ax, deg=float(deg) if deg else 0.0))
    return dict(pss=pss, cube=cube, feats=feats, path=path)

# ---------------------------------------------------------------- point tests
def rot_into_local(p, axis, deg):
    """Rotate a world-relative offset INTO the part's local frame (inverse rotation)."""
    if not axis or deg == 0.0:
        return p
    t = math.radians(-deg)          # inverse
    c, s = math.cos(t), math.sin(t)
    x, y, z = p
    if axis == "Z":  return (x * c - y * s, x * s + y * c, z)
    if axis == "Y":  return (x * c + z * s, y, -x * s + z * c)
    return (x, y * c - z * s, y * s + z * c)          # X

def inside(feat, wp):
    dx = wp[0] - feat["pos"][0]
    dy = wp[1] - feat["pos"][1]
    dz = wp[2] - feat["pos"][2]
    x, y, z = rot_into_local((dx, dy, dz), feat["axis"], feat["deg"])
    hx, hy, hz = (v / 2.0 for v in feat["size"])
    if feat["shape"] == BLK:
        return abs(x) <= hx and abs(y) <= hy and abs(z) <= hz
    if feat["shape"] == BAL:
        return (x / hx) ** 2 + (y / hy) ** 2 + (z / hz) ** 2 <= 1.0
    # CYL: circular axis is X in Roblox
    return abs(x) <= hx and (y / hy) ** 2 + (z / hz) ** 2 <= 1.0

def in_cube(cube, wp):
    """Rounded box, treated as a box with the corners chamfered by the radius."""
    W, H, D, R = cube
    # AXIS ORDER: roundedCubeInto builds `a(BLK, D, iH, iW, ...)` -- the body's X extent is D
    # (front-to-back) and its Z extent is W (side-to-side), NOT the other way round. Getting
    # this backwards makes every containment test wrong: parts pushed out along X overshoot
    # (visible gaps) and parts along Z stay buried. Confirmed against the live log -- a
    # 3.15/3.00/2.85 cube at scale 0.72 reports BodyUnion 2.05 x 2.16 x 2.27, i.e. X=D, Z=W.
    hx, hy, hz = D / 2.0, H / 2.0, W / 2.0
    x, y, z = abs(wp[0]), abs(wp[1]), abs(wp[2])
    if x > hx or y > hy or z > hz:
        return False
    ox, oy, oz = max(0.0, x - (hx - R)), max(0.0, y - (hy - R)), max(0.0, z - (hz - R))
    return ox * ox + oy * oy + oz * oz <= R * R

# ---------------------------------------------------------------- rendering
def glyph(name):
    n = name.lower()
    for key, ch in (("dapple", "."), ("spot", "."), ("neck", "N"), ("head", "H"), ("snout", "h"), ("dome", "D"), ("crest", "D"),
                    ("tooth", "T"), ("jaw", "J"), ("mouth", "m"), ("smile", "m"),
                    ("nostril", "*"), ("eye", "o"), ("glint", "'"), ("brow", "^"),
                    ("foot", "L"), ("leg", "L"), ("toe", "t"), ("arm", "a"), ("hand", "a"),
                    ("claw", "c"), ("tail", "~"), ("belly", ":"), ("dapple", "."),
                    ("sail", "S"), ("plate", "S"), ("frill", "F"), ("horn", "V"),
                    ("fin", "f"), ("feather", "w"), ("beak", "b")):
        if key in n:
            return ch
    return "#"

def render(spec, view, cols=64, rows=34):
    """view 'side' = XY plane (camera on +Z). view 'front' = ZY plane (camera on +X)."""
    feats, cube = spec["feats"], spec["cube"]
    xs, ys = [], []
    def acc(p, s):
        for i, (lo, hi) in enumerate(((p[0] - s[0] / 2, p[0] + s[0] / 2),
                                      (p[1] - s[1] / 2, p[1] + s[1] / 2),
                                      (p[2] - s[2] / 2, p[2] + s[2] / 2))):
            (xs if i == (0 if view == "side" else 2) else ys if i == 1 else []).extend([lo, hi])
    for f in feats:
        acc(f["pos"], f["size"])
    if cube:
        acc((0, 0, 0), cube[:3])
    if not xs:
        return ["(no geometry)"]
    x0, x1, y0, y1 = min(xs) - 0.4, max(xs) + 0.4, min(ys) - 0.4, max(ys) + 0.4
    # keep the aspect roughly square: character cells are ~2x taller than wide
    sx = (x1 - x0) / cols
    sy = (y1 - y0) / rows
    out = []
    for r in range(rows):
        wy = y1 - (r + 0.5) * sy
        line = []
        for c in range(cols):
            wx = x0 + (c + 0.5) * sx
            ch = " "
            best = None
            for f in feats:
                # sample along the camera axis, take the part nearest the camera
                probe = (wx, wy, f["pos"][2]) if view == "side" else (f["pos"][0], wy, wx)
                if inside(f, probe):
                    depth = f["pos"][2] if view == "side" else f["pos"][0]
                    if best is None or depth > best[0]:
                        best = (depth, glyph(f["name"]))
            if best:
                ch = best[1]
            elif cube and in_cube(cube, (wx, wy, 0.0) if view == "side" else (0.0, wy, wx)):
                ch = "#"
            line.append(ch)
        out.append("%6.2f |%s" % (wy, "".join(line).rstrip()))
    out.append("       +" + "-"*cols)
    out.append("        %-*s%s" % (cols-6, "%.1f"%x0, "%.1f"%x1))
    return out

# ---------------------------------------------------------------- attachment report
def report(spec):
    feats, cube = spec["feats"], spec["cube"]
    lines = []
    for f in feats:
        # sample the feature's own volume; how much of it is inside the cube or another part?
        hx, hy, hz = (v / 2.0 for v in f["size"])
        hits_body = hits_other = total = 0
        S = 5
        for i in range(S):
            for j in range(S):
                for k in range(S):
                    lx = -hx + 2 * hx * i / (S - 1)
                    ly = -hy + 2 * hy * j / (S - 1)
                    lz = -hz + 2 * hz * k / (S - 1)
                    t = math.radians(f["deg"])
                    c, s = math.cos(t), math.sin(t)
                    if f["axis"] == "Z":   ox, oy, oz = lx * c - ly * s, lx * s + ly * c, lz
                    elif f["axis"] == "Y": ox, oy, oz = lx * c + lz * s, ly, -lx * s + lz * c
                    elif f["axis"] == "X": ox, oy, oz = lx, ly * c - lz * s, ly * s + lz * c
                    else:                  ox, oy, oz = lx, ly, lz
                    wp = (f["pos"][0] + ox, f["pos"][1] + oy, f["pos"][2] + oz)
                    # only count points actually inside THIS part -- sampling its bounding box
                    # counts corners that are outside an ellipsoid and deflates every figure.
                    if not inside(f, wp):
                        continue
                    total += 1
                    if cube and in_cube(cube, wp):
                        hits_body += 1
                    elif any(inside(g, wp) for g in feats if g is not f):
                        hits_other += 1
        pct = 100.0 * (hits_body + hits_other) / max(1, total)
        if pct == 0:
            verdict = "FLOATING -- touches nothing"
        elif pct >= 99:
            verdict = "BURIED -- fully inside, invisible"
        elif pct < 8:
            verdict = "GRAZING -- barely touching (%.0f%%)" % pct
        else:
            verdict = "ok (%.0f%% embedded)" % pct
        lines.append("    %-12s %-26s %s" % (f["name"], verdict,
                     "body" if hits_body >= hits_other else "sibling"))
    return lines

def main(paths):
    for path in paths:
        spec = parse(path)
        if not spec:
            print("== %s : no declarative FEATURES table (not converted yet)" % os.path.basename(path))
            continue
        name = os.path.basename(path).split(".")[0]
        print("=" * 70)
        print("%s   scale %.2f   %d features" % (name, spec["pss"], len(spec["feats"])))
        print("=" * 70)
        for view in ("side", "front"):
            print("  %s VIEW  (%s)" % (view.upper(),
                  "+X right, +Y up -- the pet faces RIGHT" if view == "side" else "+Z right, +Y up -- head on"))
            for line in render(spec, view):
                print("   " + line)
            print()
        print("  ATTACHMENT")
        for line in report(spec):
            print(line)
        print()

if __name__ == "__main__":
    args = sys.argv[1:]
    files = []
    for a in args:
        files.extend(glob.glob(a))
    main(files or ["src/server/Brachiosaurus.server.luau"])
