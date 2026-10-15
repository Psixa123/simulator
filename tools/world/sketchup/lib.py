# Storm Catcher Simulator - SketchUp prop kit library (tools/world/sketchup/lib.py)
#
# The SketchUp side of the world prop pipeline (see tools/world/README.md). It is sent to the Trimble
# SketchUp MCP sandbox (build_model) one chunk at a time - each "# ===== chunk" block is one call, in
# order - and every chunk stores its functions in session_state["L"]. The prop build scripts in this
# folder then start with `L = session_state["L"]`.
#
# Sandbox rules (checked by `python3 tools/world/build_world_pack.py --check`): no imports (math is
# pre-loaded), no eval/exec/open/type/setattr/globals, no dunders, no classes, no any()/all(), plain
# builtins only. Every chunk runs in a fresh namespace: only session_state survives between calls.
#
# Conventions (docs/STYLE_GUIDE.md, "Prop kit"):
#   * Build scripts work in STUDS. piece() writes inches into SketchUp (12 in = 1 stud), Z up, the
#     prop's front faces -Y, origin at the centre of its base.
#   * A prop is a group "Prop_<PropId>" holding leaf groups named by paint: Primary, Secondary,
#     Tertiary (recoloured per biome), Color_RRGGBB, Neon_RRGGBB (glows) or Glass_RRGGBB. Several
#     leaf groups may share a paint (one per blob, say); the pack merges them.
#   * A mesh is a dict {"v": [[x, y, z], ...], "f": [[i, j, k, ...], ...]}; faces are wound
#     counter-clockwise seen from outside. Primitives return closed meshes that face outward.

# ===== chunk 1/4: vectors, meshes, transforms, noise =====
L = session_state.setdefault("L", {})
AXES = {"x": [1.0, 0.0, 0.0], "y": [0.0, 1.0, 0.0], "z": [0.0, 0.0, 1.0]}


def v_add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]


def v_sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def v_mul(a, s):
    return [a[0] * s, a[1] * s, a[2] * s]


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def v_len(a):
    return math.sqrt(v_dot(a, a))


def v_norm(a):
    n = v_len(a)
    if n < 1e-12:
        return [0.0, 0.0, 1.0]
    return [a[0] / n, a[1] / n, a[2] / n]


def v_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def merge(meshes):
    """One mesh from a list of meshes."""
    out = {"v": [], "f": []}
    for m in meshes:
        base = len(out["v"])
        out["v"].extend([list(p) for p in m["v"]])
        out["f"].extend([[i + base for i in f] for f in m["f"]])
    return out


def warp(m, fn):
    """Send every vertex through fn(point) -> point (bends, tapers, lumps...)."""
    return {"v": [list(fn(p)) for p in m["v"]], "f": [list(f) for f in m["f"]]}


def flip(m):
    return {"v": [list(p) for p in m["v"]], "f": [list(reversed(f)) for f in m["f"]]}


def move(m, d):
    return warp(m, lambda p: [p[0] + d[0], p[1] + d[1], p[2] + d[2]])


def scale(m, s, about=(0.0, 0.0, 0.0)):
    """Scale by a number or [sx, sy, sz] around `about` (mirroring keeps faces outward)."""
    if isinstance(s, (int, float)):
        s = [s, s, s]
    out = warp(m, lambda p: [about[k] + (p[k] - about[k]) * s[k] for k in range(3)])
    return flip(out) if s[0] * s[1] * s[2] < 0 else out


def rot_point(p, axis, deg, about=(0.0, 0.0, 0.0)):
    k = v_norm(AXES[axis] if isinstance(axis, str) else axis)
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    q = v_sub(p, about)
    r = v_add(v_add(v_mul(q, c), v_mul(v_cross(k, q), s)), v_mul(k, v_dot(k, q) * (1.0 - c)))
    return v_add(r, about)


def rotate(m, axis, deg, about=(0.0, 0.0, 0.0)):
    """Rotate around "x", "y", "z" or a vector through `about` (right-hand rule, degrees)."""
    return warp(m, lambda p: rot_point(p, axis, deg, about))


def signed_volume(m):
    vol = 0.0
    for f in m["f"]:
        a = m["v"][f[0]]
        for i in range(1, len(f) - 1):
            vol += v_dot(a, v_cross(m["v"][f[i]], m["v"][f[i + 1]]))
    return vol / 6.0


def orient(m):
    """Wind a closed mesh so its faces point outward (positive volume)."""
    return flip(m) if signed_volume(m) < 0 else m


def bounds(m):
    lo = [min([p[k] for p in m["v"]]) for k in range(3)]
    hi = [max([p[k] for p in m["v"]]) for k in range(3)]
    return lo, hi


def rng(seed):
    """Deterministic random numbers in [0, 1) (Park-Miller), so a build is the same every run."""
    state = [int(abs(seed) * 7919 + 17) % 2147483647 or 1]

    def nxt():
        state[0] = (state[0] * 48271) % 2147483647
        return state[0] / 2147483647.0

    return nxt


def lumps(seed, freq=1.0, count=6):
    """Smooth pseudo-noise n(point) in about [-1, 1]: a few sine waves along random directions."""
    r = rng(seed)
    waves = []
    for i in range(count):
        d = v_norm([r() * 2 - 1, r() * 2 - 1, r() * 2 - 1])
        waves.append([d, freq * (0.7 + 0.6 * r()), r() * 6.2832, 1.0 / (1.0 + 0.5 * i)])
    total = sum([w[3] for w in waves])

    def noise(p):
        s = 0.0
        for w in waves:
            s += w[3] * math.sin(w[1] * v_dot(w[0], p) + w[2])
        return s / total

    return noise


L.update({"AXES": AXES, "v_add": v_add, "v_sub": v_sub, "v_mul": v_mul, "v_dot": v_dot,
          "v_cross": v_cross, "v_len": v_len, "v_norm": v_norm, "v_lerp": v_lerp,
          "smoothstep": smoothstep, "merge": merge, "warp": warp, "flip": flip, "move": move,
          "scale": scale, "rot_point": rot_point, "rotate": rotate, "signed_volume": signed_volume,
          "orient": orient, "bounds": bounds, "rng": rng, "lumps": lumps})
result = {"chunk": 1, "functions": len(L)}

# ===== chunk 2/4: round solids (balls, blobs, rocks, lathes, cones, pucks) =====
L = session_state["L"]
v_add, v_sub, v_mul, v_dot, v_norm, orient, lumps = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_norm", "orient", "lumps")]
GRIDS = {}


def sphere_grid(seg):
    """Unit directions of a cube sphere (seg x seg equal-angle cells per cube face) + its quad faces."""
    if seg in GRIDS:
        return GRIDS[seg]
    verts, faces, index = [], [], {}
    frames = [([1, 0, 0], [0, 1, 0], [0, 0, 1]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
              ([0, 1, 0], [0, 0, 1], [1, 0, 0]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
              ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [0, 1, 0], [1, 0, 0])]
    for n, u, w in frames:
        ids = []
        for i in range(seg + 1):
            ta = math.tan((i / seg - 0.5) * math.pi / 2)
            row = []
            for j in range(seg + 1):
                tb = math.tan((j / seg - 0.5) * math.pi / 2)
                d = v_norm([n[k] + ta * u[k] + tb * w[k] for k in range(3)])
                key = (round(d[0], 6), round(d[1], 6), round(d[2], 6))
                if key not in index:
                    index[key] = len(verts)
                    verts.append(d)
                row.append(index[key])
            ids.append(row)
        for i in range(seg):
            for j in range(seg):
                faces.append([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]])
    GRIDS[seg] = (verts, faces)
    return GRIDS[seg]


def ball(center, radii, seg=6, shape=None):
    """Sphere or ellipsoid (radii = r or [rx, ry, rz]); shape(direction) scales the radius."""
    if isinstance(radii, (int, float)):
        radii = [radii, radii, radii]
    dirs, faces = sphere_grid(seg)
    verts = []
    for d in dirs:
        k = shape(d) if shape else 1.0
        verts.append([center[i] + radii[i] * d[i] * k for i in range(3)])
    return orient({"v": verts, "f": [list(f) for f in faces]})


def blob(center, radius, squash=0.88, lump=0.05, seed=1, seg=6, freq=2.4):
    """Soft cartoon puff: a slightly squashed ball with gentle lumps (tree canopies, bushes, clouds)."""
    noise = lumps(seed, freq)
    return ball(center, [radius, radius, radius * squash], seg, lambda d: 1.0 + lump * noise(d))


def rock(center, planes, soft, seg=6, stretch=(1.0, 1.0, 1.0), floor=None):
    """Faceted-but-soft boulder: the convex solid cut by planes [[normal, distance], ...] around
    `center`, its edges rounded by a smooth minimum over `soft` (same units as the distances).
    The planes must enclose the centre on every side. stretch = rough proportions of the rock
    (e.g. [1, 1, 0.6] for a squat one) spreads the vertices evenly over it. floor = flatten
    everything below this height (bury it a little below z = 0 so the base looks planted)."""
    dirs, faces = sphere_grid(seg)
    cut = []
    for n, h in planes:
        n = v_norm(n)
        sn = [n[0] * stretch[0], n[1] * stretch[1], n[2] * stretch[2]]
        k = math.sqrt(v_dot(sn, sn))
        cut.append([[sn[0] / k, sn[1] / k, sn[2] / k], h / k])
    unit = (stretch[0] * stretch[1] * stretch[2]) ** (1.0 / 3.0)
    soft = soft / unit
    verts = []
    for d in dirs:
        ts = [h / v_dot(n, d) for n, h in cut if v_dot(n, d) > 1e-3]
        if not ts:
            raise Exception("rock(): the planes leave direction " + str(d) + " open")
        lo = min(ts)
        t = max(lo - soft * math.log(sum([math.exp(-(x - lo) / soft) for x in ts])), 0.05 * lo)
        z = center[2] + d[2] * t * stretch[2]
        verts.append([center[0] + d[0] * t * stretch[0], center[1] + d[1] * t * stretch[1],
                      z if floor is None else max(z, floor)])
    return orient({"v": verts, "f": [list(f) for f in faces]})


def loft_faces(rings):
    """Faces joining rings of vertex ids (one id = a pole); open ends get a flat cap."""
    faces = []
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) > 1:
            faces += [[a[0], b[(k + 1) % len(b)], b[k]] for k in range(len(b))]
        elif len(b) == 1 and len(a) > 1:
            faces += [[a[k], a[(k + 1) % len(a)], b[0]] for k in range(len(a))]
        elif len(a) > 1:
            faces += [[a[k], a[(k + 1) % len(a)], b[(k + 1) % len(b)], b[k]] for k in range(len(a))]
    if len(rings[0]) > 1:
        faces.append(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        faces.append(list(rings[-1]))
    return faces


def lathe(profile, n=16, center=(0.0, 0.0, 0.0), phase=0.0):
    """Lofted solid of revolution around a vertical axis. profile = [(radius, z), ...] bottom to
    top, or (radius, z, dx, dy) to shift a ring sideways (bent trunks). Radius 0 at an end closes it
    in a point (pole), otherwise that end gets a flat cap."""
    verts, rings = [], []
    for i, p in enumerate(profile):
        dx = p[2] if len(p) > 2 else 0.0
        dy = p[3] if len(p) > 3 else 0.0
        c = [center[0] + dx, center[1] + dy, center[2] + p[1]]
        if p[0] <= 1e-9 and (i == 0 or i == len(profile) - 1):
            rings.append([len(verts)])
            verts.append(c)
            continue
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n + phase
            ring.append(len(verts))
            verts.append([c[0] + p[0] * math.cos(a), c[1] + p[0] * math.sin(a), c[2]])
        rings.append(ring)
    return orient({"v": verts, "f": loft_faces(rings)})


def arc_profile(r0, z0, r1, z1, bulge=0.0, steps=4):
    """Profile points from (r0, z0) to (r1, z1) bowed outward by `bulge` (for lathe())."""
    out = []
    for k in range(steps + 1):
        t = k / steps
        out.append((r0 + (r1 - r0) * t + bulge * math.sin(math.pi * t), z0 + (z1 - z0) * t))
    return out


def puck(center, radius, height, bevel, n=16, seg=2):
    """Chunky disc / cylinder with all-round rounded rims (bevel = rim radius)."""
    b = min(bevel, radius * 0.95, height / 2.0)
    prof = []
    for k in range(seg + 1):
        a = math.pi / 2 * k / seg
        prof.append((radius - b + b * math.sin(a), b - b * math.cos(a)))
    for k in range(seg + 1):
        a = math.pi / 2 * k / seg
        prof.append((radius - b + b * math.cos(a), height - b + b * math.sin(a)))
    prof = [(0.0, 0.0)] + prof + [(0.0, height)]
    return lathe(prof, n, center)


def cone(center, r_bottom, r_top, height, n=16, round_top=0.0):
    """Tapered cylinder (r_top 0 = cone). round_top > 0 swaps the top for a dome of that height."""
    prof = [(0.0, 0.0), (r_bottom, 0.0), (r_top, height)]
    if round_top > 0:
        for k in range(1, 5):
            a = math.pi / 2 * k / 4
            prof.append((r_top * math.cos(a), height + round_top * math.sin(a)))
    elif r_top > 0:
        prof.append((0.0, height))
    return lathe(prof, n, center)


L.update({"sphere_grid": sphere_grid, "ball": ball, "blob": blob, "rock": rock, "loft_faces": loft_faces,
          "lathe": lathe, "arc_profile": arc_profile, "puck": puck, "cone": cone})
result = {"chunk": 2, "functions": len(L)}

# ===== chunk 3/4: rounded boxes, tubes, 2D shapes + extrusions (bolts, stars) =====
L = session_state["L"]
v_add, v_sub, v_mul, v_dot, v_cross, v_norm, orient, loft_faces = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_cross", "v_norm", "orient", "loft_faces")]


def rounded_box(center, size, radius, seg=3):
    """Box of size [w, d, h] centred on `center` whose edges and corners are rounded by `radius`."""
    half = [size[0] / 2.0, size[1] / 2.0, size[2] / 2.0]
    r = min(radius, half[0], half[1], half[2])
    inner = [h - r for h in half]
    offs = [r * math.tan(math.pi / 4 * k / seg) for k in range(seg + 1)]
    coords = []
    for a in range(3):
        c = [-(inner[a] + o) for o in reversed(offs)] + [inner[a] + o for o in offs]
        coords.append([x for i, x in enumerate(c) if i == 0 or abs(x - c[i - 1]) > 1e-9])
    verts, faces, index = [], [], {}
    for n, s, u, w in [(0, 1, 1, 2), (0, -1, 2, 1), (1, 1, 2, 0), (1, -1, 0, 2), (2, 1, 0, 1), (2, -1, 1, 0)]:
        ids = []
        for cu in coords[u]:
            row = []
            for cw in coords[w]:
                p = [0.0, 0.0, 0.0]
                p[n], p[u], p[w] = s * half[n], cu, cw
                core = [max(-inner[k], min(inner[k], p[k])) for k in range(3)]
                d = v_sub(p, core)
                if v_dot(d, d) > 1e-18:
                    p = v_add(core, v_mul(v_norm(d), r))
                p = v_add(p, center)
                key = (round(p[0], 6), round(p[1], 6), round(p[2], 6))
                if key not in index:
                    index[key] = len(verts)
                    verts.append(p)
                row.append(index[key])
            ids.append(row)
        for i in range(len(ids) - 1):
            for j in range(len(ids[0]) - 1):
                f = [ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]]
                f = [x for k, x in enumerate(f) if x != f[k - 1]]
                if len(f) >= 3:
                    faces.append(f)
    return orient({"v": verts, "f": faces})


def tube(path, radius, n=12, caps="round", cap_seg=3):
    """Round tube along a path of points; radius is a number or one per point. caps: "round" (domed
    ends), "flat" or "open"."""
    pts = [list(p) for p in path]
    m = len(pts)
    radii = list(radius) if isinstance(radius, (list, tuple)) else [radius] * m
    tans = [v_norm(v_sub(pts[min(i + 1, m - 1)], pts[max(i - 1, 0)])) for i in range(m)]
    ref = [0.0, 0.0, 1.0] if abs(tans[0][2]) < 0.9 else [1.0, 0.0, 0.0]
    nrm = v_norm(v_cross(v_cross(tans[0], ref), tans[0]))
    frames = []
    for i in range(m):
        t = tans[i]
        nrm = v_norm(v_sub(nrm, v_mul(t, v_dot(nrm, t))))
        frames.append([nrm, v_cross(t, nrm)])
    centers, rads = list(pts), list(radii)
    if caps == "round":
        for end in (0, 1):
            i = 0 if end == 0 else m - 1
            sign = -1.0 if end == 0 else 1.0
            extra_c, extra_r = [], []
            for j in range(1, cap_seg + 1):
                phi = math.pi / 2 * j / cap_seg
                extra_c.append(v_add(pts[i], v_mul(tans[i], sign * radii[i] * math.sin(phi))))
                extra_r.append(radii[i] * math.cos(phi) if j < cap_seg else 0.0)
            if end == 0:
                centers = list(reversed(extra_c)) + centers
                rads = list(reversed(extra_r)) + rads
                frames = [frames[0]] * cap_seg + frames
            else:
                centers, rads, frames = centers + extra_c, rads + extra_r, frames + [frames[-1]] * cap_seg
    verts, rings = [], []
    for c, fr, r in zip(centers, frames, rads):
        if r <= 1e-9:
            rings.append([len(verts)])
            verts.append(list(c))
            continue
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            ring.append(len(verts))
            verts.append(v_add(c, v_add(v_mul(fr[0], r * math.cos(a)), v_mul(fr[1], r * math.sin(a)))))
        rings.append(ring)
    faces = loft_faces(rings)
    if caps == "open":
        faces = faces[:-2] if len(rings[0]) > 1 and len(rings[-1]) > 1 else faces
    return orient({"v": verts, "f": faces})


def round_poly(poly, radius, seg=3):
    """Soften every corner of a 2D polygon with a curve of about `radius`."""
    out, m = [], len(poly)
    for i in range(m):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % m]
        d0 = [p0[0] - p1[0], p0[1] - p1[1]]
        d2 = [p2[0] - p1[0], p2[1] - p1[1]]
        l0, l2 = math.hypot(d0[0], d0[1]), math.hypot(d2[0], d2[1])
        t = min(radius, 0.45 * l0, 0.45 * l2)
        a = [p1[0] + d0[0] / l0 * t, p1[1] + d0[1] / l0 * t]
        b = [p1[0] + d2[0] / l2 * t, p1[1] + d2[1] / l2 * t]
        for k in range(seg + 1):
            s = k / seg
            out.append([(1 - s) ** 2 * a[0] + 2 * s * (1 - s) * p1[0] + s * s * b[0],
                        (1 - s) ** 2 * a[1] + 2 * s * (1 - s) * p1[1] + s * s * b[1]])
    return out


def star_poly(points=5, r_out=1.0, r_in=0.5):
    return [[(r_out if k % 2 == 0 else r_in) * math.cos(math.pi / 2 + math.pi * k / points),
             (r_out if k % 2 == 0 else r_in) * math.sin(math.pi / 2 + math.pi * k / points)]
            for k in range(2 * points)]


def bolt_poly(h=1.0):
    """Chunky lightning bolt, about h tall, centred on the origin (counter-clockwise)."""
    pts = [[0.10, 0.50], [-0.26, -0.02], [-0.02, -0.02], [-0.12, -0.50], [0.28, 0.08], [0.04, 0.08], [0.22, 0.50]]
    return [[x * h, y * h] for x, y in pts]


def offset_poly(poly, d):
    """Move a counter-clockwise polygon's edges inward by d."""
    out, m = [], len(poly)
    for i in range(m):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % m]
        e1 = [p1[0] - p0[0], p1[1] - p0[1]]
        e2 = [p2[0] - p1[0], p2[1] - p1[1]]
        l1, l2 = math.hypot(e1[0], e1[1]) or 1.0, math.hypot(e2[0], e2[1]) or 1.0
        n = [-e1[1] / l1 - e2[1] / l2, e1[0] / l1 + e2[0] / l2]
        ln = math.hypot(n[0], n[1]) or 1.0
        n = [n[0] / ln, n[1] / ln]
        c = max(0.35, n[0] * -e1[1] / l1 + n[1] * e1[0] / l1)
        out.append([p1[0] + n[0] * d / c, p1[1] + n[1] * d / c])
    return out


def extrude(poly, depth, bevel=0.0, seg=2, y=0.0):
    """Slab from a 2D polygon [(x, z), ...] (counter-clockwise seen from the front, -Y) drawn in the
    XZ plane, `depth` thick along Y around y, with rounded front and back edges of size `bevel`."""
    steps = []
    for k in range(seg + 1):
        a = math.pi / 2 * k / seg
        steps.append([bevel * (1 - math.sin(a)), -depth / 2 + bevel * (1 - math.cos(a))])
    steps += [[s[0], -s[1]] for s in reversed(steps)]
    if bevel <= 1e-9:
        steps = [[0.0, -depth / 2], [0.0, depth / 2]]
    verts, rings = [], []
    for inset, yy in steps:
        ring = []
        for q in (offset_poly(poly, inset) if inset > 1e-9 else poly):
            ring.append(len(verts))
            verts.append([q[0], y + yy, q[1]])
        rings.append(ring)
    return orient({"v": verts, "f": loft_faces(rings)})


L.update({"rounded_box": rounded_box, "tube": tube, "round_poly": round_poly, "star_poly": star_poly,
          "bolt_poly": bolt_poly, "offset_poly": offset_poly, "extrude": extrude})
result = {"chunk": 3, "functions": len(L)}

# ===== chunk 4/4: the SketchUp side - paints, materials, props, pieces =====
L = session_state["L"]
v_sub, v_cross, v_dot, v_norm, v_len, bounds = [L[k] for k in ("v_sub", "v_cross", "v_dot", "v_norm", "v_len", "bounds")]
TINTS = ("Primary", "Secondary", "Tertiary")
FIXED = ("Color_", "Neon_", "Glass_")
HEX = "0123456789ABCDEF"


def check_paint(paint):
    if paint in TINTS:
        return paint
    for pre in FIXED:
        code = paint[len(pre):]
        if paint.startswith(pre) and len(code) == 6 and len([c for c in code if c in HEX]) == 6:
            return paint
    raise Exception("bad paint name '" + paint + "' (Primary/Secondary/Tertiary or Color_/Neon_/Glass_ + RRGGBB)")


def hex_rgb(code):
    return [int(code[i:i + 2], 16) for i in (0, 2, 4)]


def get_material(name, rgb, alpha=255):
    """Solid-colour material by name (reused and recoloured if it already exists)."""
    for m in model.get_materials():
        if m.get_name() == name:
            m.set_color(SUColor(rgb[0], rgb[1], rgb[2], alpha))
            return m
    mat = Material()
    mat.set_name(name)
    mat.set_color(SUColor(rgb[0], rgb[1], rgb[2], alpha))
    model.add_materials([mat])
    return mat


def paint_material(prop, paint):
    """Tint paints get a per-prop material "<PropId>_<Paint>" in the prop's default colour (edit its
    colour in SketchUp to change the default); fixed paints share one material per colour."""
    if paint in TINTS:
        return get_material(prop["id"] + "_" + paint, hex_rgb(prop["paints"].get(paint, "C8C8C8")))
    code = paint.split("_")[1]
    return get_material(paint, hex_rgb(code), 110 if paint.startswith("Glass_") else 255)


def find_prop(prop_id):
    for g in model.get_entities().get_groups():
        if g.get_name() == "Prop_" + prop_id:
            return g
    return None


def new_prop(prop_id, x=0.0, y=0.0, paints=None, solid=False, category="common", unit=12.0):
    """Start (or rebuild) the group Prop_<prop_id> at layout slot (x, y) in studs. paints = default
    colours of the tint paints, e.g. {"Primary": "5CC94F"}; solid = players bump into it."""
    old = find_prop(prop_id)
    if old is not None:
        model.get_entities().erase_entities([old])
    g = Group()
    model.get_entities().add_group(g)
    g.set_name("Prop_" + prop_id)
    g.set_transform(SUTransformation([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x * unit, y * unit, 0, 1]))
    paints = paints or {}
    info = g.get_attribute_dictionary("storm_prop")
    info["id"] = TypedValue(string_value=prop_id)
    info["category"] = TypedValue(string_value=category)
    info["solid"] = TypedValue(bool_value=bool(solid))
    for name in paints:
        info["paint_" + check_paint(name)] = TypedValue(string_value=paints[name].upper())
    return {"id": prop_id, "group": g, "paints": paints, "unit": unit, "tris": 0, "pieces": 0,
            "warnings": [], "lo": [1e9, 1e9, 1e9], "hi": [-1e9, -1e9, -1e9]}


def face_normal(pts):
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n = [n[0] + (a[1] - b[1]) * (a[2] + b[2]), n[1] + (a[2] - b[2]) * (a[0] + b[0]),
             n[2] + (a[0] - b[0]) * (a[1] + b[1])]
    return n


def planar(pts):
    """True when every point lies within 0.0001 in of the face plane (SketchUp refuses warped faces)."""
    n = v_norm(face_normal(pts))
    return len([p for p in pts if abs(v_dot(n, v_sub(p, pts[0]))) > 1e-4]) == 0


def piece(prop, paint, m, crease=40.0, collide=None):
    """Add mesh m (studs) to the prop as a leaf group named by its paint. Edges between faces that
    meet at less than `crease` degrees are soft + smooth, the rest stay crisp; the pack shades the
    piece the same way (the crease is stored on the group). collide: override the prop's solid
    flag for this piece (e.g. False for a tree canopy)."""
    check_paint(paint)
    u = prop["unit"]
    verts = [[p[0] * u, p[1] * u, p[2] * u] for p in m["v"]]
    faces = []
    for f in m["f"]:
        pts = [verts[i] for i in f]
        if v_len(face_normal(pts)) < 1e-6:
            continue
        if len(f) > 3 and not planar(pts):
            if len(f) == 4:
                d1, d2 = v_len(v_sub(pts[2], pts[0])), v_len(v_sub(pts[3], pts[1]))
                faces += [[f[0], f[1], f[2]], [f[0], f[2], f[3]]] if d1 <= d2 else [[f[0], f[1], f[3]], [f[1], f[2], f[3]]]
            else:
                faces += [[f[0], f[i], f[i + 1]] for i in range(1, len(f) - 1)]
        else:
            faces.append(list(f))
    normals = [v_norm(face_normal([verts[i] for i in f])) for f in faces]
    edges = {}
    for fi, f in enumerate(faces):
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            edges.setdefault((min(a, b), max(a, b)), []).append(fi)
    limit = math.cos(math.radians(crease))
    gi = GeometryInput()
    gi.set_vertices([SUPoint3D(p[0], p[1], p[2]) for p in verts])
    mat = paint_material(prop, paint)
    for fi, f in enumerate(faces):
        loop = LoopInput()
        for i in f:
            loop.add_vertex_index(i)
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            near = edges[(min(a, b), max(a, b))]
            if len(near) == 2 and v_dot(normals[near[0]], normals[near[1]]) > limit:
                loop.edge_set_soft(k, True)
                loop.edge_set_smooth(k, True)
        idx, gi = gi.add_face(loop)
        gi.face_set_front_material(idx, [], mat)
        gi.face_set_back_material(idx, [], mat)
    g = Group()
    prop["group"].get_entities().add_group(g)
    g.set_name(paint)
    g.get_entities().fill(gi, weld_vertices=True)
    meta = g.get_attribute_dictionary("storm_piece")
    meta["crease"] = TypedValue(double_value=float(crease))
    if collide is not None:
        meta["collide"] = TypedValue(bool_value=bool(collide))
    made = len(g.get_entities().get_faces())
    if made != len(faces):
        prop["warnings"].append(paint + ": SketchUp made " + str(made) + " of " + str(len(faces)) + " faces")
    lo, hi = bounds(m)
    prop["lo"] = [min(prop["lo"][k], lo[k]) for k in range(3)]
    prop["hi"] = [max(prop["hi"][k], hi[k]) for k in range(3)]
    prop["tris"] += sum([len(f) - 2 for f in faces])
    prop["pieces"] += 1
    return g


def report(prop):
    """Summary of a built prop (studs) for the build_model result."""
    return {"id": prop["id"], "pieces": prop["pieces"], "tris": prop["tris"], "warnings": prop["warnings"],
            "size": [round(prop["hi"][k] - prop["lo"][k], 2) for k in range(3)],
            "min": [round(x, 2) for x in prop["lo"]], "max": [round(x, 2) for x in prop["hi"]]}


L.update({"TINTS": TINTS, "check_paint": check_paint, "hex_rgb": hex_rgb, "get_material": get_material,
          "paint_material": paint_material, "find_prop": find_prop, "new_prop": new_prop,
          "face_normal": face_normal, "piece": piece, "report": report})
result = {"chunk": 4, "functions": len(L)}
