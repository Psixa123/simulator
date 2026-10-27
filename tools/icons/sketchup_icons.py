# Storm Catcher Simulator - 3D UI icons (tools/icons/sketchup_icons.py)
#
# The game's UI icons (docs/STYLE_GUIDE.md "Icons") as small chunky 3D objects modelled in Trimble
# SketchUp, then rendered to glossy cartoon PNGs by tools/icons/render_icons.py (see tools/icons/README.md).
# Same pipeline and library as the world props: send tools/world/sketchup/lib.py first (all 4 chunks),
# then each "# ===== chunk" block below as one build_model call, in order (chunk 1 stores the icon
# helpers in session_state["IC"]), then tools/world/sketchup/extract.py.
#
# Contract (like the prop kit): every icon is a top-level group "Prop_<IconKey>" (category "icons")
# made of leaf groups named by paint - fixed colours Color_RRGGBB (and Glass_RRGGBB for see-through
# glass). Units: studs (piece() writes inches, 12 in = 1 stud), Z up, the icon's FRONT faces -Y, its
# origin at the centre of its base. An icon is about 4-5 studs across. The renderer picks a 3/4 hero
# angle per icon (tools/icons/render_icons.py, ICONS), so model the readable face towards -Y.
#
# Sandbox rules (checked by `python3 tools/icons/import_icons.py check`): no imports (math is
# pre-loaded), no eval/exec/open/type/setattr, no dunders, no classes, no any()/all().

# ===== chunk 1/12: icon helpers (session_state["IC"]) - palette, discs, rings, tubes, cushions =====
L = session_state["L"]
IC = session_state.setdefault("IC", {})
v_add, v_sub, v_mul, v_dot, v_cross, v_norm, v_len = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_cross", "v_norm", "v_len")]

# Sky Lab palette (docs/STYLE_GUIDE.md) as paints; the light/dark steps follow its gradients
P = {"ink": "Color_233066", "inksoft": "Color_5B6A9E", "white": "Color_FFFFFF", "cloud": "Color_F4F8FF",
     "haze": "Color_D5E5FB", "sky": "Color_4FB6FF", "sky_l": "Color_8FDBFF", "sky_d": "Color_2F86F2",
     "bolt": "Color_FFCF3A", "bolt_l": "Color_FFE98A", "bolt_d": "Color_FFAA1F",
     "rain": "Color_3EC6FF", "rain_d": "Color_1E9BEF",
     "storm": "Color_8E6EF7", "storm_l": "Color_C3B0FF", "storm_d": "Color_6B4BE6",
     "leaf": "Color_55CF4C", "leaf_l": "Color_8BE86E", "leaf_d": "Color_33B24A",
     "coral": "Color_FF5C72", "coral_l": "Color_FF8F9B", "coral_d": "Color_E43A58",
     "sunset": "Color_FF9440", "sunset_l": "Color_FFBE6E", "sunset_d": "Color_F2702A",
     "pink": "Color_FF74AE", "cream": "Color_FFF6E2", "steel": "Color_A3B1E3", "gold": "Color_FFB52E",
     "shine": "Neon_FFFFFF"}


def new_icon(key, slot):
    """Start (or rebuild) the group Prop_<key>; icons sit side by side on a row, 8 studs apart."""
    return L["new_prop"](key, 8.0 * slot, 0.0, {}, solid=False, category="icons")


def front(m):
    """Turn a mesh built around +Z (lathe, puck, cone) so that its +Z axis points to the front (-Y)."""
    return L["rotate"](m, "x", 90)


def disc(center, r, thick, bevel, n=40):
    """Coin-like disc facing the front: axis along Y, centred on `center`, rims rounded by `bevel`."""
    return L["move"](front(L["puck"]((0.0, 0.0, -thick / 2.0), r, thick, bevel, n=n, seg=3)), center)


def torus(center, big, small, n=40, m=10, axis="y", squash=1.0):
    """Ring of radius `big`, tube radius `small`; axis "y" = standing up facing the front (in the XZ plane),
    "z" = lying flat, "x" = standing sideways (in the YZ plane). squash scales the tube along the axis."""
    verts, faces = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            rr = big + small * math.cos(b)
            verts.append([rr * math.cos(a), rr * math.sin(a), small * squash * math.sin(b)])
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            faces.append([i * m + j, i2 * m + j, i2 * m + j2, i * m + j2])
    mesh = L["orient"]({"v": verts, "f": faces})
    if axis == "y":
        mesh = L["rotate"](mesh, "x", 90)
    elif axis == "x":
        mesh = L["rotate"](mesh, "y", 90)
    return L["move"](mesh, center)


def sweep(path, radius, n=12, closed=True, flat=1.0):
    """Tube along a path; closed = a loop (no caps), else round caps. flat < 1 squashes the tube's
    cross-section along Y (front to back), for puffy flat strokes facing the front."""
    if not closed:
        m = L["tube"](path, radius, n=n, caps="round", cap_seg=3)
    else:
        k = len(path)
        verts, rings = [], []
        for i in range(k):
            t = v_norm(v_sub(path[(i + 1) % k], path[i - 1]))
            u = [0.0, 1.0, 0.0] if abs(t[1]) < 0.9 else [0.0, 0.0, 1.0]
            u = v_norm(v_sub(u, v_mul(t, v_dot(u, t))))
            side = v_cross(t, u)
            ring = []
            for j in range(n):
                a = 2 * math.pi * j / n
                ring.append(len(verts))
                verts.append(v_add(path[i], v_add(v_mul(side, radius * math.cos(a)), v_mul(u, radius * math.sin(a)))))
            rings.append(ring)
        faces = []
        for i in range(k):
            a, b = rings[i], rings[(i + 1) % k]
            faces += [[a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]] for j in range(n)]
        m = L["orient"]({"v": verts, "f": faces})
    if flat != 1.0:
        lo, hi = L["bounds"]({"v": [list(p) for p in path], "f": []})
        cy = (lo[1] + hi[1]) / 2.0
        m = L["warp"](m, lambda p: [p[0], cy + (p[1] - cy) * flat, p[2]])
    return m


def pillow(poly, depth, center=(0.0, 0.0, 0.0), pivot=None, rings=6, power=0.55):
    """Inflated cushion from a 2D outline [(x, z), ...] (counter-clockwise seen from the front), full
    thickness `depth` along Y at the pivot. Each ring is the outline scaled towards the pivot (default:
    the outline's centroid), so any outline that is star-shaped around the pivot works (stars, hearts,
    blobs, paw pads). power < 1 makes the cushion boxier, 1 = lens-like."""
    if pivot is None:
        pivot = [sum([q[0] for q in poly]) / len(poly), sum([q[1] for q in poly]) / len(poly)]
    verts, ids = [], []
    for k in range(-rings, rings + 1):
        a = math.pi / 2 * k / rings
        s = abs(math.cos(a)) ** power
        y = math.sin(a) * depth / 2.0
        if s < 1e-6:
            ids.append([len(verts)])
            verts.append([center[0] + pivot[0], center[1] + y, center[2] + pivot[1]])
            continue
        ring = []
        for q in poly:
            ring.append(len(verts))
            verts.append([center[0] + pivot[0] + (q[0] - pivot[0]) * s, center[1] + y,
                          center[2] + pivot[1] + (q[1] - pivot[1]) * s])
        ids.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](ids)})


def ellipse_poly(rx, rz, n=40, cx=0.0, cz=0.0, fn=None):
    """2D ellipse outline (counter-clockwise); fn(t) -> radius factor shapes it (blobs, pads)."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        f = fn(t) if fn else 1.0
        pts.append([cx + rx * f * math.cos(t), cz + rz * f * math.sin(t)])
    return pts


def align(m, normal, at):
    """Rotate a mesh built around +Z so that +Z points along `normal`, then move its origin to `at`."""
    n = v_norm(normal)
    axis = v_cross([0.0, 0.0, 1.0], n)
    if v_len(axis) < 1e-9:
        m = m if n[2] > 0 else L["rotate"](m, "x", 180)
    else:
        m = L["rotate"](m, axis, math.degrees(math.acos(max(-1.0, min(1.0, n[2])))))
    return L["move"](m, at)


def decal(at, normal, rx, ry, thick, sink=0.05, spin=0.0, seg=5):
    """A flattened puff stuck on a surface (spots, patches): an ellipsoid rx x ry x thick whose middle
    sits `sink` below the surface point `at` with outward `normal`; spin turns it about the normal."""
    m = L["ball"]((0.0, 0.0, 0.0), [rx, ry, thick], seg=seg)
    if spin:
        m = L["rotate"](m, "z", spin)
    return align(m, normal, v_sub(at, v_mul(v_norm(normal), sink)))


IC.update({"P": P, "new_icon": new_icon, "front": front, "disc": disc, "torus": torus, "sweep": sweep,
           "pillow": pillow, "ellipse_poly": ellipse_poly, "align": align, "decal": decal})
result = {"chunk": 1, "helpers": len(IC)}

# ===== chunk 2/12: icon helpers - bevelled slabs, smooth profiles, 2D outline tools =====
L = session_state["L"]
IC = session_state["IC"]


def bolt_shape(h):
    """A chunky lightning bolt about h tall (fatter than lib bolt_poly: its waist is 0.24 h, so slab()
    bevels fit), counter-clockwise, sharp: pass corner= to slab()."""
    pts = [[0.06, 0.5], [-0.34, -0.08], [-0.06, -0.08], [-0.2, -0.5], [0.36, 0.12], [0.08, 0.12], [0.36, 0.5]]
    return [[q[0] * h - 0.01 * h, q[1] * h] for q in pts]


def slab(poly, depth, bevel, y=0.0, z=0.0, x=0.0, seg=3, corner=0.0, support=None):
    """A bevelled slab from a 2D outline [(x, z), ...] (counter-clockwise seen from the front): `depth`
    thick along Y around y, edges rounded by `bevel`, moved by (x, z). Give a SHARP outline and its corner
    radius `corner`: every bevel ring is the sharp outline inset, then rounded by corner - inset, so the
    rings never fold over (insetting an already rounded outline past its corner radius would). A flat
    support ring `support` inside the bevel (default for bevels >= 0.1) keeps the big flat faces shading
    flat. Keep the outline's narrowest part wider than 2 * (bevel + support)."""
    if support is None:
        support = 0.4 * bevel if bevel >= 0.1 else 0.0
    steps = [[bevel + support, -depth / 2.0]] if support > 0 else []
    for k in range(seg + 1):
        a = math.pi / 2 * k / seg
        steps.append([bevel * (1 - math.sin(a)), -depth / 2.0 + bevel * (1 - math.cos(a))])
    steps += [[q[0], -q[1]] for q in reversed(steps)]
    verts, rings = [], []
    for inset, yy in steps:
        ring2 = L["offset_poly"](poly, inset) if inset > 1e-9 else poly
        if corner > 0:
            ring2 = L["round_poly"](ring2, max(0.03, corner - inset), seg=3)
        ring = []
        for q in ring2:
            ring.append(len(verts))
            verts.append([q[0] + x, y + yy, q[1] + z])
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


def smooth_profile(pts, steps=4):
    """Catmull-Rom curve through profile points [(r, z), ...] (ends kept), `steps` samples per span."""
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n - 1)]
        for k in range(steps):
            t = k / float(steps)
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(tuple(pts[-1]))
    return [(max(0.0, q[0]) if 0 < i < len(out) - 1 else q[0], q[1]) for i, q in enumerate(out)]


def rot2(poly, deg, cx=0.0, cz=0.0):
    """2D outline turned counter-clockwise (seen from the front) by deg around (cx, cz)."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[cx + (q[0] - cx) * c - (q[1] - cz) * s, cz + (q[0] - cx) * s + (q[1] - cz) * c] for q in poly]


def move2(poly, dx, dz):
    return [[q[0] + dx, q[1] + dz] for q in poly]


IC.update({"bolt_shape": bolt_shape, "slab": slab, "smooth_profile": smooth_profile, "rot2": rot2,
           "move2": move2})
result = {"chunk": 2, "helpers": len(IC)}

# ===== chunk 3/12: Volts (bolt coin), Energy (raindrop), Star, Check, Close =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def volts():
    p = IC["new_icon"]("Volts", 0)
    # A thick gold coin standing up, a raised rim and a big embossed bolt
    L["piece"](p, P["gold"], IC["disc"]((0, 0, 2.1), 2.0, 0.7, 0.3, n=44), crease=50)
    L["piece"](p, P["bolt"], IC["torus"]((0, -0.33, 2.1), 1.7, 0.19, n=44, m=10), crease=60)
    L["piece"](p, P["cream"], IC["slab"](IC["bolt_shape"](2.45), 0.5, 0.1, y=-0.32, z=2.1, corner=0.24), crease=50)
    return p


def energy():
    p = IC["new_icon"]("Energy", 1)
    # A plump raindrop: a ball at the bottom pulling up into a soft rounded tip
    r0, phi0 = 1.55, math.radians(32)
    prof = [(0.0, 0.0)]
    for k in range(1, 10):
        a = -math.pi / 2 + (phi0 + math.pi / 2) * k / 9
        prof.append((r0 * math.cos(a), r0 + r0 * math.sin(a)))
    p0 = (r0 * math.cos(phi0), r0 + r0 * math.sin(phi0))
    c1 = (p0[0] - 0.95 * math.sin(phi0), p0[1] + 0.95 * math.cos(phi0))
    tip = (0.16, 4.35)
    for k in range(1, 9):
        t = k / 8.0
        prof.append(((1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * c1[0] + t * t * tip[0],
                     (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * c1[1] + t * t * tip[1]))
    prof += [(0.1, 4.43), (0.0, 4.47)]
    L["piece"](p, P["rain"], L["lathe"](prof, n=36), crease=60)
    # a white shine streak on the upper left
    L["piece"](p, P["shine"], IC["decal"]((-0.8, -1.1, 2.45), [-0.55, -0.8, 0.25], 0.16, 0.42, 0.07, sink=0.02,
                                          spin=-25), crease=60)
    return p


def star():
    p = IC["new_icon"]("Star", 2)
    outline = L["round_poly"](L["star_poly"](5, 2.3, 1.12), 0.32, seg=3)
    L["piece"](p, P["bolt"], IC["pillow"](outline, 1.5, center=(0, 0, 2.25), rings=6, power=0.5), crease=60)
    return p


def check():
    p = IC["new_icon"]("Check", 3)
    # A fat check mark: one puffy stroke, short leg down-left, long leg up-right, softly bent corner
    path = [(-1.75, 0.0, 2.15), (-1.15, 0.0, 1.55), (-0.62, 0.0, 1.02)]
    for k in range(1, 6):
        a = math.radians(-135 + 90 * k / 6)
        path.append((-0.42 + 0.28 * math.cos(a), 0.0, 1.02 + 0.28 * math.sin(a) + 0.08))
    path += [(0.3, 0.0, 1.75), (1.05, 0.0, 2.65), (1.8, 0.0, 3.55)]
    L["piece"](p, P["leaf"], IC["sweep"](path, 0.62, n=18, closed=False, flat=0.62), crease=60)
    return p


def close():
    p = IC["new_icon"]("Close", 4)
    # A round Coral candy button with a puffy white X
    L["piece"](p, P["coral"], IC["disc"]((0, 0, 2.1), 2.05, 1.0, 0.45, n=44), crease=50)
    for sx in (1, -1):
        stroke = [(-0.82 * sx, -0.55, 2.1 - 0.82), (0.0, -0.62, 2.1), (0.82 * sx, -0.55, 2.1 + 0.82)]
        L["piece"](p, P["white"], IC["sweep"](stroke, 0.36, n=14, closed=False, flat=0.6), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (volts, energy, star, check, close)]}

# ===== chunk 4/12: Pets (paw), Eggs (spotted egg), Luck (four-leaf clover) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def pets():
    p = IC["new_icon"]("Pets", 5)
    # main pad: a soft rounded trapezoid, wider at the bottom; four toe beans fanned above it
    pad = IC["ellipse_poly"](1.5, 1.12, n=48)
    pad = [[q[0] * (1.0 - 0.13 * q[1] / 1.12), q[1] * (1.0 + 0.06 * (q[0] / 1.5) ** 2)] for q in pad]
    L["piece"](p, P["pink"], IC["pillow"](IC["move2"](pad, 0.0, 1.3), 1.05, rings=6, power=0.5), crease=60)
    for x, z, rx, rz, tilt in ((-1.8, 2.72, 0.5, 0.64, 28), (-0.62, 3.5, 0.53, 0.68, 9),
                               (0.62, 3.5, 0.53, 0.68, -9), (1.8, 2.72, 0.5, 0.64, -28)):
        toe = IC["rot2"](IC["ellipse_poly"](rx, rz, n=32), tilt)
        L["piece"](p, P["pink"], IC["pillow"](IC["move2"](toe, x, z), 0.9, rings=5, power=0.5), crease=60)
    return p


def eggs():
    p = IC["new_icon"]("Eggs", 6)
    h, r, k = 4.4, 1.62, 0.13

    def at(t):
        return (r * math.sin(t) * (1 + k * math.cos(t)), h / 2 * (1 - math.cos(t)))

    L["piece"](p, P["leaf_l"], L["lathe"]([at(math.pi * i / 24) for i in range(25)], n=40), crease=60)
    # yellow spots stuck on the shell (t along the profile, azimuth: -90 = facing the front)
    for t, az, s in ((2.25, -96, 0.46), (1.5, -52, 0.4), (1.38, -134, 0.34), (0.82, -88, 0.33),
                     (1.95, -14, 0.3), (2.62, -150, 0.26), (0.95, -30, 0.26), (1.9, -172, 0.28)):
        rr, z = at(t)
        a = math.radians(az)
        dr = r * (math.cos(t) * (1 + k * math.cos(t)) - k * math.sin(t) ** 2)
        dz = h / 2 * math.sin(t)
        nn = math.hypot(dr, dz)
        normal = [dz / nn * math.cos(a), dz / nn * math.sin(a), -dr / nn]
        L["piece"](p, P["bolt"], IC["decal"]((rr * math.cos(a), rr * math.sin(a), z), normal, s, s * 0.9, 0.16,
                                             sink=0.07), crease=60)
    return p


def heart(w):
    """Heart outline about w wide, its point at the origin, the lobes up (+z)."""
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append([x * w / 32.0, (z + 17) * w / 32.0])
    return pts


def luck():
    p = IC["new_icon"]("Luck", 7)
    cx, cz = 0.0, 2.45
    # four heart leaves (two greens, so their ink lines show), points meeting in the middle
    for i in range(4):
        ang = 45 + 90 * i
        leaf = IC["rot2"](heart(2.25), ang - 90)
        leaf = IC["move2"](leaf, cx + 0.1 * math.cos(math.radians(ang)), cz + 0.1 * math.sin(math.radians(ang)))
        piv = [cx + 1.05 * math.cos(math.radians(ang)), cz + 1.05 * math.sin(math.radians(ang))]
        L["piece"](p, P["leaf"] if i % 2 == 0 else "Color_6BDA5A",
                   IC["pillow"](leaf, 0.75, center=(0.0, -0.04 * i, 0.0), pivot=piv, rings=5, power=0.55),
                   crease=60)
    stem = [(0.05, 0.3, cz - 0.6), (0.22, 0.28, cz - 1.2), (0.55, 0.2, cz - 1.8), (1.05, 0.12, cz - 2.3)]
    L["piece"](p, P["leaf_d"], L["tube"](stem, [0.26, 0.24, 0.22, 0.2], n=12, caps="round"), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (pets, eggs, luck)]}

# ===== chunk 5/12: Shop (shopping bag), Sell (coin bag), Codes (ticket) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def shop():
    p = IC["new_icon"]("Shop", 8)
    body = L["rounded_box"]((0, 0, 1.55), [3.5, 1.7, 3.1], 0.42, seg=3)
    body = L["warp"](body, lambda q: [q[0] * (0.88 + 0.12 * q[2] / 3.1), q[1], q[2]])
    L["piece"](p, P["sunset"], body, crease=40)
    L["piece"](p, P["sunset_l"], L["rounded_box"]((0, 0, 3.0), [3.62, 1.84, 0.56], 0.26, seg=3), crease=40)
    for y in (-0.5, 0.5):
        arc = [(0.85 * math.cos(math.pi * k / 14), y, 3.12 + 1.05 * math.sin(math.pi * k / 14)) for k in range(15)]
        L["piece"](p, P["sunset_d"], L["tube"](arc, 0.17, n=10, caps="round"), crease=60)
    # emblem: a gold coin with a bolt
    L["piece"](p, P["bolt"], IC["disc"]((0, -0.9, 1.45), 0.88, 0.34, 0.14, n=32), crease=50)
    L["piece"](p, P["sunset_d"], IC["slab"](IC["bolt_shape"](1.12), 0.24, 0.06, y=-1.06, z=1.45, corner=0.1), crease=50)
    return p


def sell():
    p = IC["new_icon"]("Sell", 9)
    # a fat green money sack: round belly, cinched neck, ruffled top
    prof = IC["smooth_profile"]([(0.0, 0.0), (1.0, 0.04), (1.65, 0.38), (1.95, 1.0), (1.92, 1.7), (1.6, 2.35),
                                 (1.05, 2.85), (0.66, 3.15), (0.55, 3.32), (0.72, 3.5), (1.05, 3.72), (1.18, 3.95),
                                 (0.95, 4.15), (0.45, 4.26), (0.0, 4.3)], steps=3)
    sack = L["lathe"](prof, n=60)

    def ruffle(q):
        a = math.atan2(q[1], q[0])
        w = math.cos(5 * a + 0.6)
        f = 1.0 + 0.14 * w * L["smoothstep"](3.35, 3.85, q[2])
        lift = 0.16 * w * L["smoothstep"](3.7, 4.05, q[2]) * min(1.0, math.hypot(q[0], q[1]) / 0.9)
        return [q[0] * f, q[1] * f, q[2] + lift]

    L["piece"](p, P["leaf"], L["warp"](sack, ruffle), crease=60)
    L["piece"](p, P["bolt"], IC["torus"]((0, 0, 3.28), 0.66, 0.2, n=28, m=10, axis="z"), crease=60)
    L["piece"](p, P["bolt"], IC["slab"](IC["bolt_shape"](2.05), 0.8, 0.14, y=-1.62, z=1.42, x=-0.15, corner=0.22), crease=50)
    # a gold coin leaning on the sack
    coin = L["rotate"](IC["disc"]((0, 0, 0), 0.72, 0.28, 0.12, n=32), "z", -28)
    L["piece"](p, P["gold"], L["move"](coin, [1.55, -1.3, 0.7]), crease=50)
    L["piece"](p, P["bolt"], L["move"](L["rotate"](IC["torus"]((0, -0.15, 0), 0.56, 0.07, n=28, m=6), "z", -28),
                                       [1.55, -1.3, 0.7]), crease=60)
    return p


def ticket_outline(w, h, r, rn):
    """Rounded rectangle w x h with a round notch of radius rn in the middle of each short side."""
    pts = []
    corners = [(-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270), None, (w / 2 - r, h / 2 - r, 0),
               (-w / 2 + r, h / 2 - r, 90), None]
    for i, c in enumerate(corners):
        if c is not None:
            for k in range(5):
                a = math.radians(c[2] + 90 * k / 4)
                pts.append([c[0] + r * math.cos(a), c[1] + r * math.sin(a)])
        elif i == 2:
            for k in range(1, 10):
                a = math.radians(-90 - 180 * k / 10)
                pts.append([w / 2 + rn * math.cos(a), rn * math.sin(a)])
        else:
            for k in range(1, 10):
                a = math.radians(90 - 180 * k / 10)
                pts.append([-w / 2 + rn * math.cos(a), rn * math.sin(a)])
    return pts


def codes():
    p = IC["new_icon"]("Codes", 10)
    outline = ticket_outline(4.5, 2.7, 0.38, 0.48)
    L["piece"](p, P["bolt"], IC["slab"](outline, 0.62, 0.2, z=1.35), crease=45)
    # perforation dashes and a coral star
    for z in (0.62, 1.35, 2.08):
        L["piece"](p, P["bolt_d"], L["rounded_box"]((0.95, -0.31, z), [0.16, 0.12, 0.42], 0.06, seg=2), crease=60)
    star = L["round_poly"](L["star_poly"](5, 0.78, 0.38), 0.1, seg=2)
    L["piece"](p, P["coral"], IC["pillow"](IC["move2"](star, -0.55, 1.33), 0.5, center=(0, -0.31, 0), rings=4),
               crease=60)
    return p


result = {"built": [L["report"](f()) for f in (shop, sell, codes)]}

# ===== chunk 6/12: Upgrades (fat up arrow), Boost (x2 lightning badge), Power (vacuum nozzle) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def upgrades():
    p = IC["new_icon"]("Upgrades", 11)
    arrow = [(-0.85, 0.0), (0.85, 0.0), (0.85, 2.1), (1.95, 2.1), (0.0, 4.3), (-1.95, 2.1), (-0.85, 2.1)]
    L["piece"](p, P["leaf"], IC["slab"](arrow, 1.25, 0.36, seg=3, corner=0.55), crease=50)
    return p


def glyph(path, r=0.17, y=-0.5):
    return IC["sweep"]([(q[0], y, q[1]) for q in path], r, n=12, closed=False, flat=0.7)


def boost():
    p = IC["new_icon"]("Boost", 12)
    seal = L["round_poly"](L["star_poly"](12, 2.15, 1.82), 0.16, seg=2)
    L["piece"](p, P["sunset"], IC["pillow"](IC["move2"](seal, 0.0, 2.15), 0.95, rings=5, power=0.45), crease=60)
    bolt = IC["rot2"](IC["bolt_shape"](3.0), -8)
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.6, 0.14, y=-0.42, x=-0.5, z=2.3, corner=0.3), crease=50)
    # "x2" in white strokes, lower right
    for path in ([(0.42, 0.78), (1.0, 1.36)], [(0.42, 1.36), (1.0, 0.78)]):
        L["piece"](p, P["white"], glyph(path), crease=60)
    two = [(1.22, 1.62), (1.4, 1.83), (1.66, 1.88), (1.88, 1.74), (1.9, 1.5), (1.7, 1.24), (1.3, 0.86),
           (1.25, 0.78), (1.95, 0.78)]
    L["piece"](p, P["white"], glyph(two), crease=60)
    return p


def power():
    p = IC["new_icon"]("Power", 13)
    # the vacuum nozzle: a horn built along +Z (hose end at z = 0), turned to blow out to the left and a
    # little towards the viewer; a purple hose bends down behind it
    shell = [(0.0, 0.0), (0.66, 0.0), (0.74, 0.12), (0.76, 0.9), (0.84, 1.5), (1.06, 2.05), (1.4, 2.55), (1.66, 2.88),
             (1.8, 3.06), (1.78, 3.24), (1.64, 3.32), (1.48, 3.24), (1.22, 2.9), (0.92, 2.5), (0.58, 2.18),
             (0.0, 2.04)]
    d = [-0.74, -0.6, 0.3]
    at = (0.9, 0.2, 1.75)
    parts = [(P["sky"], L["lathe"](shell, n=40), 55),
             (P["ink"], L["puck"]((0, 0, 2.14), 0.86, 0.16, 0.05, n=32), 60),
             (P["bolt"], IC["torus"]((0, 0, 3.16), 1.66, 0.17, n=40, m=8, axis="z"), 60),
             (P["bolt"], IC["torus"]((0, 0, 0.6), 0.8, 0.17, n=32, m=8, axis="z"), 60)]
    for paint, m, crease in parts:
        L["piece"](p, paint, IC["align"](m, d, at), crease=crease)
    hose = [(at[0] + 0.25, at[1] + 0.12, at[2] - 0.08), (at[0] + 0.85, at[1] + 0.3, at[2] - 0.35),
            (at[0] + 1.15, at[1] + 0.35, at[2] - 0.95), (at[0] + 1.05, at[1] + 0.3, at[2] - 1.55)]
    L["piece"](p, P["storm"], L["tube"](hose, 0.5, n=16, caps="round"), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (upgrades, boost, power)]}

# ===== chunk 7/12: Rewards (gift box with a bow), Gift (small present) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def bow(p, paint, c, size=1.0, knot=0.38):
    """Two ribbon loops tilted up and out from a knot at c, plus the knot."""
    for side in (-1, 1):
        loop = []
        for k in range(22):
            t = 2 * math.pi * k / 22
            x, z = 0.82 * size * (1 - math.cos(t)), 0.5 * size * math.sin(t)
            a = math.radians(28)
            loop.append((c[0] + side * (x * math.cos(a) - z * math.sin(a) * 0.4), c[1] + 0.1 * math.sin(t),
                         c[2] + x * math.sin(a) + z * math.cos(a)))
        L["piece"](p, paint, IC["sweep"](loop, 0.26 * size, n=12, closed=True), crease=60)
    L["piece"](p, paint, L["ball"](c, [knot * 1.1, knot, knot], seg=5), crease=60)


def present(p, box, lid, ribbon, w, h, lid_h):
    """Box (w x w x h) + optional lid (lid_h tall) with a ribbon cross over every side."""
    L["piece"](p, box, L["rounded_box"]((0, 0, h / 2), [w, w, h], 0.3, seg=3), crease=40)
    top = h
    if lid_h > 0:
        L["piece"](p, lid, L["rounded_box"]((0, 0, h - 0.05 + lid_h / 2), [w + 0.34, w + 0.34, lid_h], 0.28, seg=3),
                   crease=40)
        top = h - 0.05 + lid_h
        for size in ([0.78, w + 0.47, lid_h + 0.06], [w + 0.47, 0.78, lid_h + 0.06]):
            L["piece"](p, ribbon, L["rounded_box"]((0, 0, h - 0.05 + lid_h / 2), size, 0.14, seg=2), crease=50)
    for size in ([0.78, w + 0.13, top - 0.02], [w + 0.13, 0.78, top - 0.02]):
        L["piece"](p, ribbon, L["rounded_box"]((0, 0, (top - 0.02) / 2 + 0.01), [size[0], size[1], top + 0.04], 0.14,
                                               seg=2), crease=50)
    return top


def rewards():
    p = IC["new_icon"]("Rewards", 14)
    top = present(p, P["coral"], "Color_FF7A8E", P["bolt"], 3.3, 2.4, 0.86)
    bow(p, P["bolt"], (0, 0, top + 0.28), 1.0)
    return p


def gift():
    p = IC["new_icon"]("Gift", 15)
    top = present(p, P["storm"], None, P["pink"], 3.0, 2.7, 0.0)
    bow(p, P["pink"], (0, 0, top + 0.26), 0.95)
    return p


result = {"built": [L["report"](f()) for f in (rewards, gift)]}

# ===== chunk 8/12: Teleport (map pin on a mini globe), ClimateShift (purple swirl), Settings (gear) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def teleport():
    p = IC["new_icon"]("Teleport", 16)
    g, r = (0.0, 0.0, 1.85), 1.85
    L["piece"](p, P["sky"], L["ball"](g, r, seg=12), crease=60)
    # continents: a second sphere that only rises above the sea where the noise is high
    noise = L["lumps"](5, 3.8)
    lands = [((-0.45, -0.8, 0.3), 0.62), ((0.7, -0.62, -0.25), 0.48), ((-0.05, -0.75, -0.7), 0.36),
             ((-0.95, 0.2, -0.3), 0.5), ((0.5, 0.75, 0.3), 0.55)]

    def land(d):
        m = 0.0
        for c, size in lands:
            q = L["v_sub"](d, L["v_norm"](c))
            m = max(m, math.exp(-L["v_dot"](q, q) / (size * size)))
        return 0.9 + 0.14 * L["smoothstep"](0.5, 0.58, m + 0.42 * noise(d))

    L["piece"](p, P["leaf"], L["ball"](g, r, seg=18, shape=land), crease=60)
    # the map pin, its point stuck in the top of the globe
    pin = [(0.0, 0.0), (0.12, 0.08), (0.3, 0.38), (0.5, 0.74), (0.68, 1.1), (0.8, 1.45), (0.83, 1.75),
           (0.76, 2.04), (0.6, 2.3), (0.34, 2.47), (0.0, 2.53)]
    base = (0.12, -0.72, g[2] + r * 0.5)
    L["piece"](p, P["coral"], L["lathe"](pin, n=36, center=base), crease=60)
    head = (base[0], base[1], base[2] + 1.72)
    L["piece"](p, P["white"], IC["decal"]((head[0], head[1] - 0.8, head[2]), [0, -1, 0.1], 0.34, 0.34, 0.16, sink=0.08),
               crease=60)
    return p


def climate_shift():
    p = IC["new_icon"]("ClimateShift", 17)
    c, rx, ry = (0.0, 0.0, 2.0), 1.95, 1.05
    L["piece"](p, P["storm"], L["ball"](c, [rx, ry, rx], seg=12), crease=60)
    # a fat spiral riding on the orb's face, thin in the middle, thick at the end
    path, radii = [], []
    steps = 46
    for k in range(steps + 1):
        t = 3.3 * math.pi * k / steps
        rho = 0.12 + 0.42 * t / math.pi
        x, z = rho * math.cos(t + 1.2), rho * math.sin(t + 1.2)
        q = min(0.98, (x * x + z * z) / (rx * rx))
        path.append((x, c[1] - ry * math.sqrt(1 - q) + 0.02, c[2] + z))
        radii.append(0.1 + 0.15 * k / steps)
    L["piece"](p, P["storm_l"], L["tube"](path, radii, n=12, caps="round"), crease=60)
    return p


def gear_outline(teeth, ro, ri, top=0.17, base=0.28):
    pts = []
    for k in range(teeth):
        a = 2 * math.pi * k / teeth
        step = 2 * math.pi / teeth
        for da, rr in ((-base, ri), (-top, ro), (top, ro), (base, ri)):
            pts.append([rr * math.cos(a + da), rr * math.sin(a + da)])
        for j in range(1, 3):
            b = a + base + (step - 2 * base) * j / 3
            pts.append([ri * math.cos(b), ri * math.sin(b)])
    return pts


def settings():
    p = IC["new_icon"]("Settings", 18)
    L["piece"](p, P["steel"], IC["slab"](gear_outline(8, 2.15, 1.62, top=0.19), 0.9, 0.2, z=2.15, corner=0.16),
               crease=50)
    L["piece"](p, P["sky"], IC["disc"]((0, -0.45, 2.15), 0.9, 0.5, 0.2, n=36), crease=50)
    L["piece"](p, P["ink"], IC["disc"]((0, -0.62, 2.15), 0.36, 0.3, 0.1, n=28), crease=50)
    return p


result = {"built": [L["report"](f()) for f in (teleport, climate_shift, settings)]}

# ===== chunk 9/12: Index (book), Daily (calendar), Lock (padlock) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def index():
    p = IC["new_icon"]("Index", 19)
    z = 1.85
    L["piece"](p, P["cream"], L["rounded_box"]((0.12, 0, z), [2.75, 0.9, 3.35], 0.16, seg=2), crease=40)
    for y in (-0.52, 0.52):
        L["piece"](p, P["storm"], L["rounded_box"]((0, y, z), [3.1, 0.24, 3.7], 0.11, seg=2), crease=40)
    L["piece"](p, P["storm"], L["rounded_box"]((-1.42, 0, z), [0.42, 1.28, 3.7], 0.2, seg=3), crease=40)
    star = L["round_poly"](L["star_poly"](5, 0.95, 0.46), 0.12, seg=2)
    L["piece"](p, P["bolt"], IC["pillow"](IC["move2"](star, 0.2, z + 0.12), 0.42, center=(0, -0.66, 0), rings=4),
               crease=60)
    return p


def daily():
    p = IC["new_icon"]("Daily", 20)
    L["piece"](p, P["cloud"], L["rounded_box"]((0, 0, 1.7), [3.6, 0.72, 3.4], 0.38, seg=3), crease=40)
    L["piece"](p, P["coral"], L["rounded_box"]((0, 0, 2.95), [3.7, 0.82, 0.98], 0.36, seg=3), crease=40)
    for x in (-0.95, 0.95):
        L["piece"](p, P["inksoft"], IC["torus"]((x, 0, 3.45), 0.34, 0.12, n=24, m=8, axis="x"), crease=60)
    seven = [(-0.72, -0.42, 2.0), (0.72, -0.42, 2.0), (-0.08, -0.42, 0.42)]
    L["piece"](p, P["sky_d"], IC["sweep"](seven, 0.28, n=14, closed=False, flat=0.55), crease=60)
    return p


def lock():
    p = IC["new_icon"]("Lock", 21)
    arc = [(1.0, 0, 2.2)] + [(1.0 * math.cos(math.pi * k / 16), 0, 2.6 + 1.15 * math.sin(math.pi * k / 16))
                             for k in range(17)] + [(-1.0, 0, 2.2)]
    L["piece"](p, P["steel"], L["tube"](arc, 0.3, n=14, caps="round"), crease=60)
    L["piece"](p, P["bolt"], L["rounded_box"]((0, 0, 1.3), [3.2, 1.35, 2.6], 0.46, seg=3), crease=40)
    hole = []
    for k in range(25):
        a = math.radians(-58 + 296 * k / 24)
        hole.append([0.4 * math.cos(a), 1.55 + 0.4 * math.sin(a)])
    hole += [[-0.27, 0.72], [0.27, 0.72]]
    L["piece"](p, P["ink"], IC["slab"](hole, 0.24, 0.06, y=-0.68, corner=0.07), crease=50)
    return p


result = {"built": [L["report"](f()) for f in (index, daily, lock)]}

# ===== chunk 10/12: Radar (radar dish), Range (target), Speed (winged boot) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def radar():
    p = IC["new_icon"]("Radar", 22)
    L["piece"](p, P["sky_d"], L["puck"]((0, 0, 0), 1.5, 0.55, 0.24, n=36), crease=50)
    L["piece"](p, P["sky_d"], L["lathe"]([(0.0, 0.4), (0.42, 0.4), (0.36, 1.0), (0.32, 1.55), (0.0, 1.55)], n=20),
               crease=50)
    L["piece"](p, P["sky_d"], L["ball"]((0, 0, 1.72), 0.46, seg=5), crease=60)
    # the dish: a thick bowl (outside, rolled rim, inside) aimed up and out to the left
    bowl = [(0.0, 0.0), (0.6, 0.04), (1.2, 0.22), (1.7, 0.56), (2.0, 0.9), (2.08, 1.06), (2.0, 1.16), (1.84, 1.12),
            (1.5, 0.84), (1.0, 0.52), (0.5, 0.36), (0.0, 0.32)]
    parts = [(P["cloud"], L["lathe"](bowl, n=44), 50),
             (P["sky"], IC["torus"]((0, 0, 1.03), 1.98, 0.16, n=44, m=8, axis="z"), 60),
             (P["inksoft"], L["tube"]([(0, 0, 0.3), (0, 0, 1.6)], 0.14, n=10, caps="flat"), 60),
             (P["coral"], L["ball"]((0, 0, 1.75), 0.34, seg=5), 60)]
    for paint, m, crease in parts:
        L["piece"](p, paint, IC["align"](m, [-0.72, -0.36, 0.6], (0, 0, 1.9)), crease=crease)
    # two radio waves leaving the dish, centred on its axis
    c = (-1.35, -0.7, 3.0)
    for rr in (0.75, 1.3):
        arc = []
        for j in range(11):
            a = math.radians(140 - 42 + 84 * j / 10)
            arc.append((c[0] + rr * math.cos(a), c[1] - 0.15, c[2] + rr * math.sin(a)))
        L["piece"](p, P["sky"], L["tube"](arc, 0.14, n=10, caps="round"), crease=60)
    return p


def range_target():
    p = IC["new_icon"]("Range", 23)
    c = (0.0, 0.0, 2.1)
    for i, (r, paint) in enumerate(((2.05, P["coral"]), (1.62, P["white"]), (1.2, P["coral"]), (0.78, P["white"]),
                                    (0.38, P["coral"]))):
        thick = 0.62 + 0.14 * i
        L["piece"](p, paint, IC["disc"]((c[0], c[1] + 0.02 * i, c[2]), r, thick, min(0.2, r * 0.3), n=44), crease=50)
    # a chunky dart in the bullseye
    tip = (0.05, -1.05, 2.15)
    tail = (1.55, -2.35, 3.5)
    L["piece"](p, P["sky_d"], L["tube"]([tip, tail], 0.15, n=12, caps="round"), crease=60)
    for spin in (0, 90):
        fin = L["ball"]((0, 0, 0), [0.42, 0.06, 0.24], seg=4)
        fin = L["rotate"](fin, "x", spin)
        d = L["v_norm"](L["v_sub"](tail, tip))
        fin = IC["align"](L["rotate"](fin, "y", -90), d, L["v_add"](tail, L["v_mul"](d, -0.2)))
        L["piece"](p, P["bolt"], fin, crease=60)
    return p


def speed():
    p = IC["new_icon"]("Speed", 24)
    # a chunky sky-blue boot, toe to the right, on a white sole that curls up at the toe
    sole = L["rounded_box"]((0.35, 0, 0.24), [3.7, 1.5, 0.48], 0.24, seg=3)
    sole = L["warp"](sole, lambda q: [q[0], q[1], q[2] + 0.45 * L["smoothstep"](1.2, 2.2, q[0]) ** 2])
    L["piece"](p, P["white"], sole, crease=40)
    L["piece"](p, P["sky"], L["ball"]((0.7, 0, 0.98), [1.55, 0.74, 0.72], seg=7), crease=60)
    L["piece"](p, P["sky"], L["lathe"]([(0.0, 0.5), (0.82, 0.5), (0.86, 1.2), (0.8, 2.2), (0.84, 3.0), (0.0, 3.0)],
                                        n=28, center=(-0.6, 0, 0)), crease=50)
    L["piece"](p, P["white"], IC["torus"]((-0.6, 0, 3.0), 0.84, 0.26, n=28, m=10, axis="z"), crease=60)
    L["piece"](p, P["bolt"], IC["slab"](IC["rot2"](IC["bolt_shape"](1.25), -20), 0.3, 0.07, y=-0.77, x=-0.55, z=1.7, corner=0.12),
               crease=50)
    # a white wing on the heel, three feathers fanned up and back
    root = (-1.2, -0.25, 2.25)
    for i, (ln, ang, paint) in enumerate(((2.0, 128, P["white"]), (1.75, 152, P["cloud"]), (1.4, 176, P["white"]))):
        fea = IC["ellipse_poly"](ln / 2, 0.36 - 0.03 * i, n=28)
        fea = IC["rot2"](fea, ang)
        fea = IC["move2"](fea, root[0] + ln / 2 * math.cos(math.radians(ang)),
                          root[2] + ln / 2 * math.sin(math.radians(ang)))
        L["piece"](p, paint, IC["pillow"](fea, 0.4, center=(0, root[1] - 0.12 * i, 0), rings=4), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (radar, range_target, speed)]}

# ===== chunk 11/12: Rainbow, MegaStorm (thundercloud with a bolt), Tank (storm jar) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def rainbow():
    p = IC["new_icon"]("Rainbow", 25)
    for rr, paint in ((2.55, P["coral"]), (2.08, P["bolt"]), (1.61, P["leaf"]), (1.14, P["sky"])):
        arc = [(rr * math.cos(math.pi * k / 24), 0.0, 0.6 + rr * math.sin(math.pi * k / 24)) for k in range(25)]
        L["piece"](p, paint, IC["sweep"](arc, 0.27, n=14, closed=False, flat=0.75), crease=60)
    for sx in (-1, 1):
        x = 1.85 * sx
        for dx, dz, r in ((-0.6, 0.42, 0.52), (0.05, 0.72, 0.68), (0.66, 0.4, 0.5)):
            L["piece"](p, P["white"], L["blob"]((x + dx * sx, -0.22, dz), r, squash=0.9, lump=0.03, seed=3, seg=6),
                       crease=60)
    return p


def mega_storm():
    p = IC["new_icon"]("MegaStorm", 26)
    cloud = "Color_8A72EC"
    for c, r in (((-1.35, 0.0, 2.55), 1.0), ((0.05, 0.1, 3.0), 1.38), ((1.4, 0.0, 2.6), 0.98),
                 ((-0.55, -0.25, 2.2), 0.95), ((0.75, -0.25, 2.2), 0.95)):
        L["piece"](p, cloud, L["blob"](c, r, squash=0.92, lump=0.03, seed=5, seg=7), crease=60)
    L["piece"](p, cloud, L["rounded_box"]((0.0, 0.0, 2.1), [3.9, 1.7, 1.0], 0.48, seg=3), crease=40)
    bolt = IC["rot2"](IC["bolt_shape"](3.1), -10)
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.62, 0.15, y=-0.6, x=0.2, z=0.95, corner=0.3), crease=50)
    return p


def tank():
    p = IC["new_icon"]("Tank", 27)
    L["piece"](p, P["storm"], L["puck"]((0, 0, 0), 1.5, 0.6, 0.24, n=40), crease=50)
    glass = [(0.0, 0.45), (1.12, 0.45), (1.3, 0.62), (1.34, 1.5), (1.32, 2.8), (1.16, 3.12), (0.0, 3.16)]
    L["piece"](p, "Glass_BFEAFF", L["lathe"](glass, n=40), crease=60)
    water = [(0.0, 0.55), (1.0, 0.55), (1.19, 0.72), (1.22, 1.5), (1.21, 2.15), (0.0, 2.15)]
    L["piece"](p, P["rain"], L["lathe"](water, n=40), crease=60)
    for x, z, r in ((-0.45, 1.35, 0.16), (0.3, 1.7, 0.12), (0.55, 1.05, 0.1)):
        L["piece"](p, P["shine"], L["ball"]((x, -1.0, z), r, seg=4), crease=60)
    L["piece"](p, "Neon_FFC21F", IC["slab"](IC["bolt_shape"](1.15), 0.24, 0.04, z=2.62, corner=0.1), crease=50)
    L["piece"](p, P["storm"], L["puck"]((0, 0, 3.0), 1.48, 0.62, 0.26, n=40), crease=50)
    L["piece"](p, P["bolt"], IC["torus"]((0, 0, 3.3), 1.47, 0.12, n=40, m=8, axis="z"), crease=60)
    L["piece"](p, P["storm_d"], L["puck"]((0, 0, 3.55), 0.55, 0.36, 0.14, n=24), crease=50)
    return p


result = {"built": [L["report"](f()) for f in (rainbow, mega_storm, tank)]}

# ===== chunk 12/12: Trade (two curved swap arrows) =====
L = session_state["L"]
IC = session_state["IC"]
P = IC["P"]


def swap_arrow(start, end, cz, rm=1.55, width=0.95, flare=0.55, head=1.2, lead=0.18):
    """Flat outline of a fat arrow curving clockwise round (0, cz) from angle `start` to `end` (degrees,
    start > end), with a pointed head at `end`; counter-clockwise as slab() wants it."""
    ro, ri = rm + width / 2.0, rm - width / 2.0
    steps = 10
    outer, inner = [], []
    for k in range(steps + 1):
        a = math.radians(start + (end - start) * k / steps)
        outer.append((ro * math.cos(a), cz + ro * math.sin(a)))
        inner.append((ri * math.cos(a), cz + ri * math.sin(a)))
    a = math.radians(end)
    radial, tangent = (math.cos(a), math.sin(a)), (math.sin(a), -math.cos(a))
    tip = (rm * radial[0] + head * tangent[0], cz + rm * radial[1] + head * tangent[1])
    # the barbs lean a little towards the tip so they stay thick enough for the bevel
    wing_out = ((ro + flare) * radial[0] + lead * tangent[0], cz + (ro + flare) * radial[1] + lead * tangent[1])
    wing_in = ((ri - flare) * radial[0] + lead * tangent[0], cz + (ri - flare) * radial[1] + lead * tangent[1])
    poly = outer + [wing_out, tip, wing_in] + list(reversed(inner))
    return [list(q) for q in reversed(poly)]


def shine_arc(start, end, cz, r, y):
    """A thin white gloss streak along an arrow's front face."""
    path = []
    for k in range(9):
        a = math.radians(start + (end - start) * k / 8.0)
        path.append((r * math.cos(a), y, cz + r * math.sin(a)))
    return IC["sweep"](path, 0.085, n=8, closed=False, flat=0.5)


def trade():
    p = IC["new_icon"]("Trade", 28)
    cz, depth = 2.3, 0.78
    L["piece"](p, P["sky"], IC["slab"](swap_arrow(164.0, 24.0, cz), depth, 0.22, seg=3, corner=0.18), crease=50)
    L["piece"](p, P["leaf"], IC["slab"](swap_arrow(344.0, 204.0, cz), depth, 0.22, y=0.04, seg=3, corner=0.18),
               crease=50)
    L["piece"](p, P["shine"], shine_arc(140.0, 70.0, cz, 1.86, -depth / 2.0 - 0.01), crease=60)
    L["piece"](p, P["shine"], shine_arc(320.0, 262.0, cz, 1.86, -depth / 2.0 + 0.03), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (trade,)]}
