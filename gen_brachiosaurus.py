"""
gen_brachiosaurus.py

Procedurally generate a cute low-poly (chibi) brachiosaurus as an OBJ mesh
(brachiosaurus.obj + brachiosaurus.mtl) for import into Roblox Studio via
Avatar > Import 3D.

Built by LOFTING tapered tubes along curved spines (not boxes) so the surface
is smooth and organic. Geometry is written with shared (smooth) vertex normals
so Roblox smooth-shades it. Parts are tagged with `o <name>` / `usemtl <mat>`
so eyes / toenails / etc. import as separately colored pieces.

Only dependency for geometry: numpy. (matplotlib is used only for the PNG
preview and can be skipped if not installed.)

Axes:  -X = head / front,  +X = tail,  Y = up,  Z = width (sides).
"""

import os
import numpy as np

# ----------------------------------------------------------------------------
# Mesh accumulator
# ----------------------------------------------------------------------------


class Mesh:
    def __init__(self):
        self.V = []          # list of [x, y, z]
        self.parts = []      # list of dict(name, material, faces=[(a,b,c), ...])

    def _new_part(self, name, material):
        part = {"name": name, "material": material, "faces": []}
        self.parts.append(part)
        return part

    def _add_vertex(self, p):
        self.V.append([float(p[0]), float(p[1]), float(p[2])])
        return len(self.V) - 1

    # -- tube ----------------------------------------------------------------
    def add_tube(self, points, radii, N, cap_start, cap_end, ovality,
                 name, material):
        """Loft a tapered tube along a 3D polyline `points` with per-point
        `radii`. At each spine point a ring of N verts is built in the plane
        perpendicular to the spine tangent, using world-Z as the side reference
        (so vertical necks work). `ovality` squashes the ring in the side
        direction. Consecutive rings are connected with triangles; ends are
        optionally capped."""
        points = np.asarray(points, dtype=float)
        radii = np.asarray(radii, dtype=float)
        M = len(points)
        part = self._new_part(name, material)

        # Smooth tangents along the spine.
        tangents = np.gradient(points, axis=0)
        ref = np.array([0.0, 0.0, 1.0])  # world-Z side reference

        rings = []  # rings[i] = list of N global vertex indices
        for i in range(M):
            T = tangents[i]
            n = np.linalg.norm(T)
            T = T / n if n > 1e-9 else np.array([1.0, 0.0, 0.0])

            # u = side/width direction = world-Z projected onto plane perp to T.
            u = ref - np.dot(ref, T) * T
            if np.linalg.norm(u) < 1e-6:
                u = np.array([1.0, 0.0, 0.0]) - np.dot([1.0, 0.0, 0.0], T) * T
            u = u / np.linalg.norm(u)
            v = np.cross(T, u)            # the other in-plane axis (up/down)
            v = v / np.linalg.norm(v)

            r = radii[i]
            ring = []
            for k in range(N):
                ang = 2.0 * np.pi * k / N
                offset = (np.cos(ang) * ovality * r) * u + (np.sin(ang) * r) * v
                ring.append(self._add_vertex(points[i] + offset))
            rings.append(ring)

        # Side walls (outward winding).
        for i in range(M - 1):
            for k in range(N):
                k1 = (k + 1) % N
                a, b = rings[i][k], rings[i][k1]
                c, d = rings[i + 1][k], rings[i + 1][k1]
                part["faces"].append((a, b, c))
                part["faces"].append((b, d, c))

        # Caps (fan to ring centroid).
        if cap_start:
            c0 = self._add_vertex(points[0])
            for k in range(N):
                k1 = (k + 1) % N
                part["faces"].append((c0, rings[0][k1], rings[0][k]))
        if cap_end:
            cE = self._add_vertex(points[-1])
            for k in range(N):
                k1 = (k + 1) % N
                part["faces"].append((cE, rings[-1][k], rings[-1][k1]))

        return part

    # -- sphere --------------------------------------------------------------
    def add_sphere(self, center, r, lat, lon, squashY, squashX,
                   name, material):
        """UV sphere of triangles centered at `center`. `lat` stacks, `lon`
        slices. `squashY`/`squashX` scale the Y / X axes (Z stays = r)."""
        center = np.asarray(center, dtype=float)
        part = self._new_part(name, material)

        north = self._add_vertex(center + np.array([0.0, r * squashY, 0.0]))
        south = self._add_vertex(center + np.array([0.0, -r * squashY, 0.0]))

        ringsR = []  # interior rings, stacks i = 1 .. lat-1
        for i in range(1, lat):
            theta = np.pi * i / lat
            st, ct = np.sin(theta), np.cos(theta)
            ring = []
            for j in range(lon):
                phi = 2.0 * np.pi * j / lon
                p = center + np.array([
                    r * squashX * st * np.cos(phi),
                    r * squashY * ct,
                    r * st * np.sin(phi),
                ])
                ring.append(self._add_vertex(p))
            ringsR.append(ring)

        # North fan.
        top = ringsR[0]
        for j in range(lon):
            j1 = (j + 1) % lon
            part["faces"].append((north, top[j1], top[j]))

        # Middle strips.
        for i in range(len(ringsR) - 1):
            A, B = ringsR[i], ringsR[i + 1]
            for j in range(lon):
                j1 = (j + 1) % lon
                part["faces"].append((A[j], A[j1], B[j]))
                part["faces"].append((A[j1], B[j1], B[j]))

        # South fan.
        bot = ringsR[-1]
        for j in range(lon):
            j1 = (j + 1) % lon
            part["faces"].append((bot[j], bot[j1], south))

        return part

    # -- output --------------------------------------------------------------
    def vertex_normals(self):
        V = np.asarray(self.V)
        Nrm = np.zeros_like(V)
        for part in self.parts:
            for (a, b, c) in part["faces"]:
                n = np.cross(V[b] - V[a], V[c] - V[a])  # area-weighted
                Nrm[a] += n
                Nrm[b] += n
                Nrm[c] += n
        lengths = np.linalg.norm(Nrm, axis=1)
        lengths[lengths < 1e-12] = 1.0
        Nrm /= lengths[:, None]
        # any leftover zero normals -> point up
        bad = np.linalg.norm(Nrm, axis=1) < 0.5
        Nrm[bad] = np.array([0.0, 1.0, 0.0])
        return Nrm

    def write_obj(self, obj_path, mtl_path):
        V = np.asarray(self.V)
        Nrm = self.vertex_normals()
        nfaces = sum(len(p["faces"]) for p in self.parts)

        with open(obj_path, "w") as f:
            f.write("# cute chibi brachiosaurus - procedurally lofted\n")
            f.write(f"mtllib {os.path.basename(mtl_path)}\n")
            for p in V:
                f.write(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}\n")
            for n in Nrm:
                f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
            for part in self.parts:
                f.write(f"o {part['name']}\n")
                f.write(f"usemtl {part['material']}\n")
                f.write("s 1\n")  # smooth shading group
                for (a, b, c) in part["faces"]:
                    a1, b1, c1 = a + 1, b + 1, c + 1
                    f.write(f"f {a1}//{a1} {b1}//{b1} {c1}//{c1}\n")
        return len(V), nfaces


# ----------------------------------------------------------------------------
# Catmull-Rom resampling of a 2D (x, y) spine + radii
# ----------------------------------------------------------------------------


def resample(points2d, radii, mult):
    """Densify a 2D spine (list of [x, y]) and matching radii with a
    Catmull-Rom spline, `mult` new samples per original segment."""
    P = np.asarray(points2d, dtype=float)
    R = np.asarray(radii, dtype=float)
    M = len(P)

    def cr(p0, p1, p2, p3, t):
        t2, t3 = t * t, t * t * t
        return 0.5 * ((2 * p1)
                      + (-p0 + p2) * t
                      + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)

    out_p, out_r = [], []
    for i in range(M - 1):
        p0 = P[i - 1] if i > 0 else P[i]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < M else P[i + 1]
        r0 = R[i - 1] if i > 0 else R[i]
        r1, r2 = R[i], R[i + 1]
        r3 = R[i + 2] if i + 2 < M else R[i + 1]
        for j in range(mult):
            t = j / mult
            out_p.append(cr(p0, p1, p2, p3, t))
            out_r.append(cr(r0, r1, r2, r3, t))
    out_p.append(P[-1])
    out_r.append(R[-1])
    return np.asarray(out_p), np.asarray(out_r)


# ----------------------------------------------------------------------------
# Materials
# ----------------------------------------------------------------------------

MATERIALS = {
    "cute_green":    (0.29, 0.63, 0.31),
    "cute_eyewhite": (0.97, 0.97, 0.97),
    "cute_eyeblack": (0.05, 0.05, 0.06),
    "cute_cream":    (0.95, 0.92, 0.82),
    "cute_mouth":    (0.20, 0.10, 0.07),
}


def write_mtl(path):
    with open(path, "w") as f:
        f.write("# cute brachiosaurus materials\n")
        for name, (r, g, b) in MATERIALS.items():
            f.write(f"newmtl {name}\n")
            f.write(f"Kd {r:.3f} {g:.3f} {b:.3f}\n")
            f.write("Ka 0.000 0.000 0.000\n")
            f.write("Ks 0.050 0.050 0.050\n")
            f.write("Ns 16.0\n")
            f.write("d 1.0\n")
            f.write("illum 2\n\n")


# ----------------------------------------------------------------------------
# Build the brachiosaurus
# ----------------------------------------------------------------------------


def build():
    m = Mesh()

    # --- BODY + NECK + TAIL: one continuous lofted tube --------------------
    # Spine in side view (x, y); x>0 tail, x<0 head/front. Radii give the
    # thin tail -> fat belly -> tapering neck profile. The neck S-curves up.
    spine = [
        (4.7, 1.05),   # tail tip
        (3.7, 0.95),
        (2.7, 1.10),
        (1.8, 1.65),   # rising into the rump (arched back)
        (0.9, 2.05),   # mid body, fullest belly + domed top
        (0.0, 2.10),
        (-0.7, 2.05),  # shoulders
        (-1.25, 2.55),
        (-1.15, 3.45),  # neck S: tucks back...
        (-1.45, 4.35),
        (-1.85, 5.20),  # ...then sweeps forward
        (-2.20, 6.00),
        (-2.45, 6.70),  # neck top (head attaches)
    ]
    radii = [
        0.10, 0.42, 0.88, 1.55, 2.25, 2.30, 1.95,
        1.35, 1.00, 0.92, 0.85, 0.80, 0.75,
    ]
    sp2d, rr = resample(spine, radii, mult=6)
    sp3d = np.column_stack([sp2d[:, 0], sp2d[:, 1], np.zeros(len(sp2d))])
    m.add_tube(sp3d, rr, N=28, cap_start=True, cap_end=False, ovality=0.94,
               name="body", material="cute_green")

    neck_top = sp3d[-1]

    # --- HEAD + SNOUT ------------------------------------------------------
    head_c = neck_top + np.array([-0.35, 0.18, 0.0])
    m.add_sphere(head_c, 0.95, lat=16, lon=22, squashY=1.0, squashX=1.0,
                 name="head", material="cute_green")
    snout_c = head_c + np.array([-0.88, -0.18, 0.0])
    m.add_sphere(snout_c, 0.55, lat=12, lon=16, squashY=0.92, squashX=1.05,
                 name="snout", material="cute_green")

    # --- HAUNCHES (fuse legs into body) -----------------------------------
    haunches = [
        ((-0.5, 1.40, 1.15), 0.95),   # front-left shoulder
        ((-0.5, 1.40, -1.15), 0.95),  # front-right shoulder
        ((1.55, 1.40, 1.30), 1.15),   # back-left hip (bigger)
        ((1.55, 1.40, -1.30), 1.15),  # back-right hip
    ]
    for c, r in haunches:
        m.add_sphere(c, r, lat=12, lon=16, squashY=1.0, squashX=1.0,
                     name="haunch", material="cute_green")

    # --- LEGS (stubby tubes, tops sunk into body, no top cap) -------------
    legs = [
        # (top xyz, bottom xyz, r_top, r_bot)
        ((-0.5, 1.75, 1.05), (-0.5, 0.20, 1.32), 0.52, 0.46),   # front-left
        ((-0.5, 1.75, -1.05), (-0.5, 0.20, -1.32), 0.52, 0.46),  # front-right
        ((1.55, 1.75, 1.20), (1.55, 0.20, 1.48), 0.58, 0.50),   # back-left
        ((1.55, 1.75, -1.20), (1.55, 0.20, -1.48), 0.58, 0.50),  # back-right
    ]
    feet_centers = []
    for top, bot, rt, rb in legs:
        top = np.asarray(top, float)
        bot = np.asarray(bot, float)
        pts = np.array([top, top * 0.5 + bot * 0.5, bot])
        rad = np.array([rt, (rt + rb) * 0.5, rb])
        m.add_tube(pts, rad, N=16, cap_start=False, cap_end=True, ovality=1.0,
                   name="leg", material="cute_green")
        feet_centers.append(bot)

    # --- FEET (flattened green stumps) ------------------------------------
    foot_r = [0.55, 0.55, 0.60, 0.60]
    for bot, fr in zip(feet_centers, foot_r):
        fc = np.array([bot[0], 0.12, bot[2]])
        m.add_sphere(fc, fr, lat=10, lon=14, squashY=0.5, squashX=1.0,
                     name="foot", material="cute_green")

        # --- TOENAILS (3 cream spheres on the front of each foot) ---------
        for dz in (-0.24, 0.0, 0.24):
            nail = np.array([fc[0] - 0.42, 0.10, fc[2] + dz])
            m.add_sphere(nail, 0.13, lat=6, lon=8, squashY=0.9, squashX=0.9,
                         name="toenail", material="cute_cream")

    # --- EYES (big & cute, upper-front sides of the head) -----------------
    for side in (1.0, -1.0):
        white_c = head_c + np.array([-0.36, 0.30, 0.55 * side])
        m.add_sphere(white_c, 0.34, lat=12, lon=14, squashY=1.0, squashX=1.0,
                     name="whitepartofeye", material="cute_eyewhite")
        pupil_c = white_c + np.array([-0.18, 0.02, 0.10 * side])
        m.add_sphere(pupil_c, 0.18, lat=10, lon=12, squashY=1.0, squashX=1.0,
                     name="blackpartofeye", material="cute_eyeblack")
        glint_c = pupil_c + np.array([-0.11, 0.08, 0.04 * side])
        m.add_sphere(glint_c, 0.055, lat=6, lon=8, squashY=1.0, squashX=1.0,
                     name="eyeglint", material="cute_eyewhite")

    # --- NOSTRILS (two tiny dark spheres on the snout) --------------------
    for side in (1.0, -1.0):
        nostril = snout_c + np.array([-0.46, 0.10, 0.17 * side])
        m.add_sphere(nostril, 0.07, lat=6, lon=8, squashY=1.0, squashX=1.0,
                     name="nostril", material="cute_mouth")

    # --- MOUTH (thin dark tube, small upward smile across snout front) ----
    mouth_x = snout_c[0] - 0.30
    mouth_y = snout_c[1] - 0.20
    mouth_pts, mouth_rad = [], []
    zs = np.linspace(-0.32, 0.32, 9)
    for z in zs:
        y = mouth_y + 0.13 * (z / 0.32) ** 2   # corners curl up = smile
        mouth_pts.append((mouth_x, y, z))
        mouth_rad.append(0.05)
    m.add_tube(np.asarray(mouth_pts), np.asarray(mouth_rad), N=8,
               cap_start=True, cap_end=True, ovality=1.0,
               name="mouth", material="cute_mouth")

    return m


# ----------------------------------------------------------------------------
# Preview PNG (smooth-shaded, side + 3/4 views)
# ----------------------------------------------------------------------------


def save_preview(mesh, path):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: F401
    except Exception as exc:  # pragma: no cover
        print(f"[preview] matplotlib unavailable, skipping PNG ({exc})")
        return

    # matplotlib draws the 3rd coordinate as vertical, but our "up" is Y, so
    # remap columns to (X, Z, Y) for the plot — vertical axis becomes Y(up).
    V = np.asarray(mesh.V)[:, [0, 2, 1]]
    tris = []
    cols = []
    for part in mesh.parts:
        kd = MATERIALS[part["material"]]
        for f in part["faces"]:
            tris.append(f)
            cols.append(kd)
    tris = np.asarray(tris)
    cols = np.asarray(cols)

    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    # Simple Lambert shading against a fixed light for nicer-looking preview.
    light = np.array([-0.4, 0.6, 0.7])
    light = light / np.linalg.norm(light)

    def make_collection():
        polys = V[tris]
        n = np.cross(polys[:, 1] - polys[:, 0], polys[:, 2] - polys[:, 0])
        ln = np.linalg.norm(n, axis=1)
        ln[ln < 1e-12] = 1.0
        n = n / ln[:, None]
        shade = 0.35 + 0.65 * np.clip(n @ light, 0, 1)
        face_rgb = np.clip(cols * shade[:, None], 0, 1)
        pc = Poly3DCollection(polys, facecolors=face_rgb, edgecolors="none")
        return pc

    lo = V.min(axis=0)
    hi = V.max(axis=0)
    ctr = (lo + hi) / 2
    span = (hi - lo).max() / 2

    fig = plt.figure(figsize=(13, 6))
    views = [("side view", 0, -90), ("3/4 view", 18, -60)]
    for idx, (title, elev, azim) in enumerate(views, start=1):
        ax = fig.add_subplot(1, 2, idx, projection="3d")
        ax.add_collection3d(make_collection())
        ax.set_xlim(ctr[0] - span, ctr[0] + span)
        ax.set_ylim(ctr[1] - span, ctr[1] + span)
        ax.set_zlim(ctr[2] - span, ctr[2] + span)
        ax.set_box_aspect((1, 1, 1))
        ax.view_init(elev=elev, azim=azim)
        ax.set_title(title)
        ax.set_xlabel("X (head-/tail+)")
        ax.set_ylabel("Z width")
        ax.set_zlabel("Y up")
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)
    print(f"[preview] wrote {path}")


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------


def main():
    obj_path = "brachiosaurus.obj"
    mtl_path = "brachiosaurus.mtl"
    png_path = "brachiosaurus_preview.png"

    mesh = build()
    write_mtl(mtl_path)
    nverts, nfaces = mesh.write_obj(obj_path, mtl_path)

    print(f"Wrote {obj_path} and {mtl_path}")
    print(f"Vertices: {nverts}")
    print(f"Triangles (faces): {nfaces}")

    save_preview(mesh, png_path)

    print("\nImport into Roblox: Avatar > Import 3D > select brachiosaurus.obj")
    print("Model faces -X (front); +X is the tail. Rename it 'dino1' and place")
    print("it in island1 on the DinoPlacement marker (the NestingNook server")
    print("script handles bottom-alignment, facing, and anchoring).")


if __name__ == "__main__":
    main()
