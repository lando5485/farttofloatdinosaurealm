#!/usr/bin/env python3
"""
petscan.py -- extract every pet part from a shipped builder and report geometry defects.

WHY
    petxray.py needs a declarative FEATURES table. Most builders still create their parts with
    loops and expressions, so this reads them AS THEY ARE: it walks the build function, expands
    `for _, sgn in ipairs({1,-1})` / `for _, fp in ipairs({{a,b},...})` loops, evaluates the
    arithmetic in each argument, and produces the same part list petxray works from.

    That makes it possible to audit a pet without first rewriting it.

WHAT IT REPORTS   (these are the defects that have actually shipped)
    FLOATING  -- the part touches nothing. Reads as a piece hovering in mid-air.
    BURIED    -- the part is entirely inside another opaque part. Invisible; the work is wasted.
    GRAZING   -- barely touching. Survives a still pose, looks detached the moment it moves.

USAGE
    python tools/petscan.py src/server/Stegosaurus.server.luau
    python tools/petscan.py src/server/*.server.luau
"""
import re, sys, math, glob, os

# ---------------------------------------------------------------- tiny Lua expression eval
def ev(expr, env):
    e = expr.strip()
    # fp[1] -> element
    def idx(m):
        v = env.get(m.group(1))
        if isinstance(v, (list, tuple)):
            return repr(v[int(m.group(2)) - 1])
        return m.group(0)
    e = re.sub(r"(\w+)\[(\d+)\]", idx, e)
    e = re.sub(r"math\.rad", "math.radians", e)
    for k, v in env.items():
        if isinstance(v, (int, float)):
            e = re.sub(r"\b%s\b" % re.escape(k), repr(v), e)
    try:
        return float(eval(e, {"math": math, "__builtins__": {}}, {}))
    except Exception:
        return None

def parse_list(txt):
    """`{1,-1}` -> [1,-1];  `{ {a,b}, {c,d} }` -> [(a,b),(c,d)]"""
    txt = txt.strip()
    if txt.startswith("{"):
        txt = txt[1:-1]
    out, depth, cur = [], 0, ""
    for ch in txt:
        if ch == "{":
            depth += 1; cur += ch
        elif ch == "}":
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    res = []
    for item in out:
        item = item.strip()
        if item.startswith("{"):
            res.append(tuple(float(x) for x in item[1:-1].split(",")))
        else:
            try:
                res.append(float(item))
            except ValueError:
                pass
    return res

def split_args(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1; cur += ch
        elif ch in ")]}":
            if depth == 0 and ch == ")":
                break                      # this closes the call itself -- stop here
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [a.strip() for a in out]

def rot_of(expr, env):
    """CFrame.Angles(a,b,c) -> (axis, degrees). Anything else -> (None, 0)."""
    m = re.search(r"CFrame\.Angles\((.*)\)\s*$", expr.strip())
    if not m:
        return (None, 0.0)
    a = split_args(m.group(1))
    if len(a) != 3:
        return (None, 0.0)
    vals = [ev(x, env) for x in a]
    for axis, v in zip("XYZ", vals):
        if v not in (None, 0.0) and abs(v) > 1e-9:
            return (axis, math.degrees(v))
    return (None, 0.0)

# ---------------------------------------------------------------- extract parts
CALL = re.compile(r"(S|weldTo)\(\s*(?:P\()?\s*(.*)$")

def extract(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"local PSW, PSH, PSD, PSR, PSS = ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)", src)
    if not m:
        return None
    W, H, D, R, PSS = (float(x) for x in m.groups())
    fn = re.search(r"local function build\w+\(\).*?\n^end\s*$", src, re.S | re.M)
    if not fn:
        return None
    lines = fn.group(0).split("\n")

    parts, stack = [], []          # stack of (var, values, indent)
    locals_env = {}
    for raw in lines:
        line = raw.rstrip()
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        while stack and indent <= stack[-1][2]:
            stack.pop()
        if stripped.startswith("--") or not stripped:
            continue
        mf = re.match(r"for\s+_\s*,\s*(\w+)\s+in\s+ipairs\(\s*(\{.*\})\s*\)\s+do", stripped)
        if mf:
            stack.append((mf.group(1), parse_list(mf.group(2)), indent))
            continue
        ml = re.match(r"local\s+(\w+)\s*=\s*(.+)$", stripped)
        if ml and "P(" not in ml.group(2) and "Vector3" not in ml.group(2):
            locals_env[ml.group(1)] = ml.group(2)
            continue
        mc = re.match(r"(?:local\s+\w+\s*=\s*)?(S|weldTo)\(", stripped)
        if not mc:
            continue
        inner = stripped[stripped.index("(") + 1:]
        if mc.group(1) == "weldTo":
            mp = re.search(r"P\((.*)", inner)
            if not mp:
                continue
            inner = mp.group(1)
        args = split_args(inner)
        if len(args) < 9:
            continue
        # every combination of the active loop variables
        combos = [{}]
        for var, vals, _ in stack:
            combos = [dict(c, **{var: v}) for c in combos for v in vals]
        for env in combos:
            e = dict(env)
            for k, expr in locals_env.items():
                v = ev(expr, e)
                if v is not None:
                    e[k] = v
            name = args[0].strip().strip('"')
            shape = args[1].strip()
            nums = [ev(a, e) for a in args[2:5]] + [ev(a, e) for a in args[6:9]]
            if any(v is None for v in nums):
                continue
            axis, deg = rot_of(args[9], e) if len(args) > 9 else (None, 0.0)
            parts.append(dict(name=name, shape=shape, fused=(mc.group(1) == "S"),
                              size=tuple(nums[0:3]), pos=tuple(nums[3:6]),
                              axis=axis, deg=deg))
    return dict(cube=(W, H, D, R), pss=PSS, parts=parts, path=path)

# ---------------------------------------------------------------- geometry
def rot_local(p, axis, deg):
    if not axis or deg == 0.0:
        return p
    t = math.radians(-deg); c, s = math.cos(t), math.sin(t); x, y, z = p
    if axis == "Z": return (x*c - y*s, x*s + y*c, z)
    if axis == "Y": return (x*c + z*s, y, -x*s + z*c)
    return (x, y*c - z*s, y*s + z*c)

def inside(pt, wp):
    d = (wp[0]-pt["pos"][0], wp[1]-pt["pos"][1], wp[2]-pt["pos"][2])
    x, y, z = rot_local(d, pt["axis"], pt["deg"])
    hx, hy, hz = (v/2.0 for v in pt["size"])
    if hx <= 0 or hy <= 0 or hz <= 0:
        return False
    if pt["shape"] == "BLK": return abs(x) <= hx and abs(y) <= hy and abs(z) <= hz
    if pt["shape"] == "BAL": return (x/hx)**2 + (y/hy)**2 + (z/hz)**2 <= 1.0
    return abs(x) <= hx and (y/hy)**2 + (z/hz)**2 <= 1.0

def in_cube(cube, wp):
    W, H, D, R = cube
    # AXIS ORDER: roundedCubeInto builds `a(BLK, D, iH, iW, ...)` -- the body's X extent is D
    # (front-to-back) and its Z extent is W (side-to-side), NOT the other way round. Getting
    # this backwards makes every containment test wrong: parts pushed out along X overshoot
    # (visible gaps) and parts along Z stay buried. Confirmed against the live log -- a
    # 3.15/3.00/2.85 cube at scale 0.72 reports BodyUnion 2.05 x 2.16 x 2.27, i.e. X=D, Z=W.
    hx, hy, hz = D/2.0, H/2.0, W/2.0
    x, y, z = abs(wp[0]), abs(wp[1]), abs(wp[2])
    if x > hx or y > hy or z > hz: return False
    ox, oy, oz = max(0.0, x-(hx-R)), max(0.0, y-(hy-R)), max(0.0, z-(hz-R))
    return ox*ox + oy*oy + oz*oz <= R*R

def surface_points(p, n=96):
    """Points ON the part's surface. Visibility is a question about the SURFACE, not the volume.

    The first version of this sampled the part's VOLUME on a 5x5x5 grid and asked how much of it
    sat inside something else. That produced a false BURIED on every rounded part, including the
    Triceratops -- which is signed off as correct. The reason: for an ellipsoid the only samples
    that reach the extremities land exactly ON the surface, where floating-point rounding pushed
    them just outside the `<= 1.0` test and dropped them. Every surviving sample was interior,
    and interior samples are of course inside the body. Sampling the surface directly has no
    such blind spot and answers the question that actually matters: can any of this be seen?
    """
    hx, hy, hz = (v / 2.0 for v in p["size"])
    pts = []
    ga = math.pi * (3.0 - math.sqrt(5.0))          # Fibonacci sphere -- even coverage, no poles
    for i in range(n):
        y = 1.0 - 2.0 * i / float(n - 1)
        r = math.sqrt(max(0.0, 1.0 - y * y))
        th = ga * i
        dx, dy, dz = math.cos(th) * r, y, math.sin(th) * r
        if p["shape"] == "BAL":
            lx, ly, lz = hx * dx, hy * dy, hz * dz
        elif p["shape"] == "BLK":
            k = max(abs(dx), abs(dy), abs(dz)) or 1.0
            lx, ly, lz = hx * dx / k, hy * dy / k, hz * dz / k
        else:                                       # CYL -- circular in Y/Z, flat ends in X
            k = max(abs(dx), math.hypot(dy, dz)) or 1.0
            lx, ly, lz = hx * dx / k, hy * dy / k, hz * dz / k
        lx, ly, lz = lx * 0.999, ly * 0.999, lz * 0.999
        t = math.radians(p["deg"]); c, sn = math.cos(t), math.sin(t)
        if   p["axis"] == "Z": ox, oy, oz = lx*c - ly*sn, lx*sn + ly*c, lz
        elif p["axis"] == "Y": ox, oy, oz = lx*c + lz*sn, ly, -lx*sn + lz*c
        elif p["axis"] == "X": ox, oy, oz = lx, ly*c - lz*sn, ly*sn + lz*c
        else:                  ox, oy, oz = lx, ly, lz
        pts.append((p["pos"][0]+ox, p["pos"][1]+oy, p["pos"][2]+oz))
    return pts

def analyse(spec):
    cube, parts = spec["cube"], spec["parts"]
    rows = []
    for p in parts:
        pts = surface_points(p)
        covered = 0
        for wp in pts:
            if in_cube(cube, wp) or any(inside(q, wp) for q in parts if q is not p):
                covered += 1
        contact = covered / float(len(pts))          # how much of it is buried in something
        exposed = 1.0 - contact                      # how much of it can actually be seen
        if   contact == 0.0:  v = "FLOATING"         # touches nothing at all
        elif exposed <= 0.005: v = "BURIED"          # nothing shows -- invisible
        elif contact < 0.06:  v = "GRAZING"          # touching, but barely
        else:                 v = "ok"
        rows.append((p, contact * 100.0, v))
    return rows

def main(paths):
    for path in paths:
        spec = extract(path)
        name = os.path.basename(path).split(".")[0]
        if not spec:
            print("== %-16s (no PSW/PSH block -- already converted or not a pet)" % name)
            continue
        rows = analyse(spec)
        if not rows:
            print("== %-16s EXTRACTION FAILED -- 0 parts read. NOT a clean result." % name)
            print()
            continue
        bad = [r for r in rows if r[2] != "ok"]
        print("=" * 76)
        print("%-16s %d parts   %d DEFECT(S)" % (name, len(rows), len(bad)))
        print("=" * 76)
        for p, pct, v in rows:
            if v == "ok":
                continue
            print("  %-9s %-12s %4.0f%% buried  size %.2fx%.2fx%.2f  at (%.2f, %.2f, %.2f)%s" % (
                v, p["name"], pct, p["size"][0], p["size"][1], p["size"][2],
                p["pos"][0], p["pos"][1], p["pos"][2], "  [in union]" if p["fused"] else ""))
        if not bad:
            print("  clean -- every part is attached and visible")
        print()

if __name__ == "__main__":
    files = []
    for a in sys.argv[1:]:
        files.extend(glob.glob(a))
    main(files)
