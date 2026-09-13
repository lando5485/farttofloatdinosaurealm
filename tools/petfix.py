#!/usr/bin/env python3
"""
petfix.py -- for every BURIED pet part, solve the SMALLEST move that makes it visible.

A part that is 100% buried inside the body draws nothing: the work is wasted and the feature it
was meant to provide (a T-Rex's tiny arms, a shark's gills, a raptor's sickle claws) simply is
not there. Fixing it by hand means guessing an offset, re-checking, guessing again.

This searches instead. For each buried part it tries pushing along the candidate directions
(+/-X, +/-Y, +/-Z and the outward radial), in 0.02-stud steps, and reports the first offset that
leaves at least MIN_SHOW of the part's surface exposed while keeping at least MIN_HOLD of it
embedded -- visible, but still attached.

    python tools/petfix.py src/server/Velociraptor.server.luau
"""
import sys, math, glob, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import petscan as ps

MIN_SHOW = 0.25     # at least a quarter of the surface must be visible
MIN_HOLD = 0.15     # at least this much must stay embedded, or it reads as detached
STEP     = 0.02
MAX_PUSH = 2.50

def coverage(part, parts, cube, offset):
    moved = dict(part)
    moved["pos"] = (part["pos"][0] + offset[0], part["pos"][1] + offset[1], part["pos"][2] + offset[2])
    pts = ps.surface_points(moved)
    cov = 0
    for wp in pts:
        if ps.in_cube(cube, wp) or any(ps.inside(q, wp) for q in parts if q is not part):
            cov += 1
    return cov / float(len(pts))

def solve(part, parts, cube):
    px, py, pz = part["pos"]
    rad = math.sqrt(px*px + py*py + pz*pz) or 1.0
    dirs = [("+X", (1,0,0)), ("-X", (-1,0,0)), ("+Y", (0,1,0)), ("-Y", (0,-1,0)),
            ("+Z", (0,0,1)), ("-Z", (0,0,-1)),
            ("out", (px/rad, py/rad, pz/rad))]
    # push along Z away from the centreline for a part that is off-centre in Z (gills, arms)
    if abs(pz) > 0.2:
        dirs.append(("Z-out", (0, 0, 1 if pz > 0 else -1)))
    best = None
    for label, d in dirs:
        n = 1
        while n * STEP <= MAX_PUSH:
            off = (d[0]*n*STEP, d[1]*n*STEP, d[2]*n*STEP)
            c = coverage(part, parts, cube, off)
            if (1.0 - c) >= MIN_SHOW and c >= MIN_HOLD:
                dist = n * STEP
                if best is None or dist < best[0]:
                    best = (dist, label, off, c)
                break
            n += 1
    return best

def main(paths):
    for path in paths:
        spec = ps.extract(path)
        name = os.path.basename(path).split(".")[0]
        if not spec or not spec["parts"]:
            print("== %-16s extraction failed" % name); continue
        rows = ps.analyse(spec)
        bad = [(p, v) for p, pct, v in rows if v in ("BURIED", "FLOATING", "GRAZING")]
        if not bad:
            print("== %-16s clean" % name); continue
        print("=" * 78)
        print("%s -- %d part(s) to fix" % (name, len(bad)))
        print("=" * 78)
        seen = set()
        for p, v in bad:
            key = (p["name"], tuple(round(abs(c), 3) for c in p["pos"]), p["size"])
            if key in seen:      # mirrored pairs share one source line
                continue
            seen.add(key)
            r = solve(p, spec["parts"], spec["cube"])
            if not r:
                print("  %-11s %-9s at (%.2f,%.2f,%.2f)  NO SOLUTION within %.1f studs"
                      % (p["name"], v, *p["pos"], MAX_PUSH)); continue
            dist, label, off, cov = r
            newp = tuple(p["pos"][i] + off[i] for i in range(3))
            print("  %-11s %-9s (%.2f,%.2f,%.2f) -> (%.2f,%.2f,%.2f)   push %s %.2f   %.0f%% still embedded"
                  % (p["name"], v, *p["pos"], *newp, label, dist, cov * 100))
        print()

if __name__ == "__main__":
    files = []
    for a in sys.argv[1:]:
        files.extend(glob.glob(a))
    main(files)
