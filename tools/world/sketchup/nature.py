# Storm Catcher Simulator - prop kit, category "nature" (tools/world/sketchup/nature.py)
#
# Trees, bushes, flowers, mushrooms, rocks, crystals, fences and grass for the island edges
# (tools/world/PROPS.md, "nature"; TreeRound and RockCluster live in common.py). Send lib.py first
# (all its chunks), then each "# ===== chunk" block below as one build_model call, in order: chunk 1
# stores the shared helpers in session_state["N"]. Units: studs (piece() converts to inches), Z up,
# front -Y, origin at the centre of the prop's base. The props sit side by side on the row y = 24.

# ===== chunk 1/4: helpers shared by the nature props =====
L = session_state["L"]
N = session_state.setdefault("N", {})
v_add, v_sub, v_mul, v_dot, v_cross, v_norm, v_len = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_cross", "v_norm", "v_len")]


def revolve(rows, n, fn, center=(0.0, 0.0, 0.0)):
    """Solid of revolution whose rings may change with the angle: fn(i, a) -> (r, z) for ring i of
    `rows` at angle a (radians). An end ring with r = 0 closes in a pole."""
    verts, rings = [], []
    for i in range(rows):
        r0, z0 = fn(i, 0.0)[:2]
        if r0 <= 1e-9 and (i == 0 or i == rows - 1):
            rings.append([len(verts)])
            verts.append([center[0], center[1], center[2] + z0])
            continue
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            r, z = fn(i, a)[:2]
            ring.append(len(verts))
            verts.append([center[0] + r * math.cos(a), center[1] + r * math.sin(a), center[2] + z])
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


def blade(path, widths, thick, n=10, side=None, up=(0.0, 0.0, 1.0), droop=0.0):
    """Fat leaf / blade along a path: an elliptical section widths[i] across (half-width) and
    thick[i] deep (half), its edges bent down by droop * width (arched leaves). The section's
    sideways axis is `side` (or tangent x up). A width of 0 at an end closes the blade in a point."""
    m = len(path)
    thick = list(thick) if isinstance(thick, (list, tuple)) else [thick] * m
    verts, rings = [], []
    for i in range(m):
        t = v_norm(v_sub(path[min(i + 1, m - 1)], path[max(i - 1, 0)]))
        if side is not None:
            s = v_norm(v_sub(side, v_mul(t, v_dot(side, t))))
        else:
            s = v_norm(v_cross(t, up))
        u = v_cross(s, t)
        w = widths[i]
        if w <= 1e-9:
            rings.append([len(verts)])
            verts.append(list(path[i]))
            continue
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            c, sn = math.cos(a), math.sin(a)
            off = v_add(v_mul(s, w * c), v_mul(u, thick[i] * sn - droop * w * c * c))
            ring.append(len(verts))
            verts.append(v_add(path[i], off))
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


def align(m, normal, spin=0.0):
    """Turn a mesh modelled around +Z (about the origin) so +Z points along `normal`, after
    spinning it `spin` degrees about Z."""
    if spin:
        m = L["rotate"](m, "z", spin)
    n = v_norm(normal)
    axis = v_cross([0.0, 0.0, 1.0], n)
    s = v_len(axis)
    if s < 1e-6:
        return m if n[2] > 0 else L["rotate"](m, "x", 180)
    return L["rotate"](m, axis, math.degrees(math.atan2(s, n[2])))


def floor_at(m, z):
    """Flatten everything below height z (bases planted a little under the ground)."""
    return L["warp"](m, lambda p: [p[0], p[1], max(p[2], z)])


def stone(center, radius, z_bot, z_top, seed, sides=5, shoulders=3, soft=0.5, seg=9, lean=(0.0, 0.0),
          floor=None, squat=None, tilt=(0.18, 0.24)):
    """Chunky faceted stone between heights z_bot and z_top (see common.py's boulder): a tilted
    top, near-upright sides leaning in by tilt[0] + tilt[1] * random, shoulder bevels and a flat
    bottom (bevelled underneath too unless floor is set)."""
    r = L["rng"](seed)
    spin = 2 * math.pi * r()
    top, bot = z_top - center[2], center[2] - z_bot
    planes = [[[lean[0] + 0.2 * (r() - 0.5), lean[1] + 0.2 * (r() - 0.5), 1.0], top]]
    for k in range(sides):
        a = spin + 2 * math.pi * (k + 0.35 * (r() - 0.5)) / sides
        planes.append([[math.cos(a), math.sin(a), tilt[0] + tilt[1] * r()], radius * (0.9 + 0.16 * r())])
    for k in range(shoulders):
        b = spin + 2 * math.pi * (k + 0.5 + 0.3 * (r() - 0.5)) / shoulders
        lift = 1.0 + 0.6 * r()
        s, c = 1.0 / math.sqrt(1 + lift * lift), lift / math.sqrt(1 + lift * lift)
        planes.append([[math.cos(b), math.sin(b), lift], (radius * s + top * c) * (0.8 + 0.06 * r())])
    for k in range(3 if floor is None else 0):
        b = spin + 2 * math.pi * (k + 0.25 + 0.3 * r()) / 3
        planes.append([[math.cos(b), math.sin(b), -1.2], (radius * 0.64 + bot * 0.77) * 0.9])
    planes.append([[0.0, 0.0, -1.0], bot])
    if squat is None:
        squat = max(0.5, min(1.6, (top + bot) / (2.0 * radius)))
    return L["rock"](center, planes, soft, seg, stretch=(1.0, 1.0, squat), floor=floor)


def root_flare(trunk, bumps=5, amount=0.34, height=1.6, phase=0.4):
    """Splay the bottom of a trunk into soft root bumps."""
    def fn(q):
        a = math.atan2(q[1], q[0])
        bump = max(0.0, math.cos(bumps * a + phase)) ** 2
        k = 1.0 + amount * bump * (1.0 - L["smoothstep"](-0.3, height, q[2]))
        return [q[0] * k, q[1] * k, q[2]]
    return L["warp"](trunk, fn)


N.update({"revolve": revolve, "blade": blade, "align": align, "floor_at": floor_at, "stone": stone,
          "root_flare": root_flare})
result = {"chunk": 1, "helpers": sorted(N.keys())}

# ===== chunk 2/4: TreeTall (cotton-candy tree), BushRound, TreePine (soft cones with snow caps) =====
L = session_state["L"]
N = session_state["N"]
CAT = "nature"


def tree_tall():
    p = L["new_prop"]("TreeTall", 0, 24, {"Primary": "FF8CC6", "Secondary": "FFC4E1"}, category=CAT)
    # Slim S-curved trunk with a root flare; it runs up into the tiers

    def bend(z):
        return 0.75 * math.sin(math.pi * max(z, 0.0) / 10.0)

    prof = []
    for z, r in ((-0.3, 1.15), (0.1, 1.02), (0.6, 0.8), (1.4, 0.68), (3.0, 0.62), (5.0, 0.6), (7.0, 0.58),
                 (10.0, 0.55), (13.0, 0.5)):
        prof.append((r, z, bend(z), 0.0))
    L["piece"](p, "Color_A8724C", N["root_flare"](L["lathe"](prof, n=16), amount=0.42, height=1.2), crease=50)
    # Three stacked fluffy tiers: a core puff ringed by smaller puffs (a cotton-candy cloud outline)
    tiers = [(7.85, 3.1, 0.8, 4, 2.0, 2.75, -0.5, 45, "Primary", 5),
             (11.75, 2.45, 0.84, 3, 1.6, 2.05, -0.35, 20, "Secondary", 4),
             (15.3, 1.9, 0.95, 3, 1.15, 1.4, -0.35, 75, "Primary", 4)]
    for z, r, sq, ring, rr, dist, dz, ph, paint, seg in tiers:
        c = [bend(z) - 0.15, 0.0, z]
        L["piece"](p, paint, L["blob"](c, r, squash=sq, lump=0.04, seed=int(z * 10), seg=seg), crease=60,
                   collide=False)
        for k in range(ring):
            a = math.radians(ph + 360.0 * k / ring)
            pc = [c[0] + dist * math.cos(a), c[1] + dist * math.sin(a), z + dz + 0.25 * math.sin(3 * a)]
            L["piece"](p, paint, L["blob"](pc, rr, squash=0.9, lump=0.05, seed=k + int(z * 10), seg=4), crease=60,
                       collide=False)
    return p


def bush_round():
    p = L["new_prop"]("BushRound", 42, 24, {"Primary": "45C25A", "Secondary": "8FE36F"}, category=CAT)
    puffs = [((0.0, 0.35, 1.55), 2.1, 0.86, "Primary", 31, 6), ((-1.6, 0.1, 1.05), 1.45, 0.88, "Primary", 32, 5),
             ((1.65, -0.15, 1.0), 1.4, 0.88, "Primary", 33, 5), ((0.35, -1.25, 0.8), 1.2, 0.86, "Primary", 34, 5),
             ((-0.45, -0.8, 2.75), 1.2, 0.86, "Secondary", 35, 5)]
    for c, r, sq, paint, seed, seg in puffs:
        m = N["floor_at"](L["blob"](c, r, squash=sq, lump=0.05, seed=seed, seg=seg), -0.25)
        L["piece"](p, paint, m)
    return p


# Normalised soft-cone profile (radius, height) from the rim top to the tip; the underside and the
# rolled rim are added below it
SIDE = [(0.97, 0.12), (0.9, 0.2), (0.8, 0.31), (0.68, 0.43), (0.55, 0.55), (0.42, 0.67), (0.29, 0.78),
        (0.17, 0.87), (0.08, 0.935), (0.0, 0.965)]


def side_at(s):
    """Point on the side profile at s in [0, 1] (rim .. tip) and its outward normal."""
    x = max(0.0, min(0.9999, s)) * (len(SIDE) - 1)
    i = int(x)
    f = x - i
    a, b = SIDE[i], SIDE[i + 1]
    dr, dz = b[0] - a[0], b[1] - a[1]
    k = math.sqrt(dr * dr + dz * dz)
    return a[0] + dr * f, a[1] + dz * f, dz / k, -dr / k


def pine_tier(z0, R, H, lobes, ph, cap_from, n):
    """One soft cone tier (rim radius R at height z0, H tall) with `lobes` drooping scallops round
    its rim, plus its snow cap from side position cap_from up to the tip."""
    def wave(a):
        return math.cos(lobes * (a - ph))

    def shape(s, a, off):
        r, z, nr, nz = side_at(s)
        w = (1.0 - s) ** 2
        r = (r + off * nr / R) * R * (1.0 + 0.075 * wave(a) * w)
        z = z0 + (z + off * nz / H) * H - 0.32 * wave(a) * (1.0 - s) ** 3
        return r, z

    under = [(0.0, 0.16), (0.5, 0.09), (0.84, 0.035), (0.95, 0.045)]
    rows = len(under) + 10

    def cone_fn(i, a):
        if i < len(under):
            r, z = under[i]
            r = r * R * (1.0 + 0.075 * wave(a))
            return r, z0 + z * H - 0.32 * wave(a) * (1.0 if i == len(under) - 1 else 0.6)
        return shape((i - len(under)) / 9.0, a, 0.0)

    cone = N["revolve"](rows, n, cone_fn)

    def drip(a):
        return cap_from - 0.13 * (0.5 + 0.5 * wave(a)) ** 1.5

    def cap_fn(i, a):
        s0 = drip(a)
        if i == 0:
            return shape(s0 + 0.02, a, -0.32)
        if i == 1:
            return shape(s0, a, 0.06)
        if i == 2:
            return shape(s0 + 0.015, a, 0.17)
        return shape(s0 + 0.03 + (1.0 - s0 - 0.03) * (i - 3) / 4.0, a, 0.17 * (1.0 - (i - 3) / 4.0) + 0.02)

    cap = N["revolve"](8, n, cap_fn)
    return cone, cap


def tree_pine():
    p = L["new_prop"]("TreePine", 14, 24, {"Primary": "2FA866", "Tertiary": "F2F8FF"}, category=CAT)
    trunk = L["lathe"]([(1.05, -0.3), (0.95, 0.1), (0.75, 0.6), (0.66, 1.4), (0.62, 3.2)], n=18)
    L["piece"](p, "Color_8A5A3C", N["root_flare"](trunk, amount=0.38, height=1.0), crease=50)
    tiers = [(2.0, 4.45, 6.2, 6, 0.0, 0.52, 24), (6.3, 3.55, 5.6, 6, math.pi / 6, 0.46, 24),
             (10.2, 2.6, 6.85, 5, math.pi / 10, 0.42, 20)]
    for z0, R, H, lobes, ph, cap_from, n in tiers:
        cone, cap = pine_tier(z0, R, H, lobes, ph, cap_from, n)
        L["piece"](p, "Primary", cone, crease=50, collide=False)
        L["piece"](p, "Tertiary", cap, crease=50, collide=False)
    return p


result = {"built": [L["report"](tree_tall()), L["report"](bush_round()), L["report"](tree_pine())]}

# ===== chunk 3/4: TreePalm, FlowerPatch, GrassTuft, Mushroom =====
L = session_state["L"]
N = session_state["N"]
CAT = "nature"


def tree_palm():
    p = L["new_prop"]("TreePalm", 28, 24, {"Primary": "3EC45E"}, category=CAT)
    top = 13.6

    def spine(z):
        t = max(z, 0.0) / top
        return [2.0 * t ** 1.8 - 0.3, 0.35 * t ** 2, z]

    # Trunk: stacked rings, each a little wider at its top with a crisp step to the next one
    path, radii = [spine(-0.3)], [1.1]
    segs = 9
    for k in range(segs):
        z0 = 0.35 + (top - 0.35) * k / segs
        z1 = 0.35 + (top - 0.35) * (k + 1) / segs
        taper = 1.0 - 0.3 * k / segs
        for f, r in ((0.0, 0.7), (0.55, 0.78), (0.92, 0.88)):
            path.append(spine(z0 + (z1 - z0) * f))
            radii.append(r * taper * (1.25 if k == 0 and f == 0.0 else 1.0))
    path.append(spine(top + 0.15))
    radii.append(0.6)
    trunk = L["tube"](path, radii, n=14, caps="flat")
    L["piece"](p, "Color_C8925A", N["root_flare"](trunk, bumps=4, amount=0.3, height=0.9), crease=35)
    crown = spine(top)
    L["piece"](p, "Primary", L["blob"]([crown[0], crown[1], top + 0.45], 0.9, squash=0.85, lump=0.03, seed=41, seg=4),
               collide=False)
    # Six fat arched leaves rising a little then drooping, edges curled down, and two young upright ones
    leaves = [(15, 4.8, 0.55, 0.95), (75, 4.4, 0.5, 1.0), (138, 4.7, 0.55, 0.95), (200, 4.5, 0.5, 1.0),
              (262, 4.7, 0.6, 0.95), (322, 4.3, 0.6, 1.0), (105, 3.0, 1.0, 0.85), (290, 2.8, 1.0, 0.85)]
    for az, length, rise, fall in leaves:
        a = math.radians(az)
        d = [math.cos(a), math.sin(a)]
        pts, ws = [], []
        steps = 9
        for k in range(steps + 1):
            t = k / steps
            z = top + 0.5 + length * (rise * t - fall * t * t)
            pts.append([crown[0] + d[0] * (0.3 + length * t), crown[1] + d[1] * (0.3 + length * t), z])
            ws.append((0.25 * length) * math.sin(math.pi * t ** 0.85) ** 0.6)
        ws[0], ws[-1] = 0.0, 0.0
        L["piece"](p, "Primary", N["blade"](pts, ws, 0.24, n=10, droop=0.32), crease=55, collide=False)
    # Coconuts tucked under the crown
    for dx, dy, dz in ((0.35, -0.68, -0.55), (-0.62, -0.38, -0.65), (0.4, 0.5, -0.7)):
        L["piece"](p, "Color_7A4E2E", L["ball"]([crown[0] + dx, crown[1] + dy, top + dz], 0.6, seg=3), crease=60,
                   collide=False)
    return p


def flower_head(R, lobes=5):
    """A cupped cartoon flower around +Z: round petals joined in the middle, with a domed centre."""
    rows = [(0.0, 0.26), (0.5, 0.22), (0.86, 0.3), (1.0, 0.17), (0.82, -0.05), (0.0, -0.13)]

    def fn(i, a):
        k = 0.56 + 0.44 * math.cos(lobes * a / 2.0) ** 2
        return rows[i][0] * R * k, rows[i][1] * R

    eye = L["lathe"]([(0.0, 0.1 * R), (0.36 * R, 0.13 * R), (0.34 * R, 0.33 * R), (0.2 * R, 0.44 * R),
                      (0.0, 0.47 * R)], n=12)
    return N["revolve"](len(rows), 25, fn), eye


def flower_patch():
    p = L["new_prop"]("FlowerPatch", 52, 24, {"Primary": "4CC254", "Secondary": "FF86B6", "Tertiary": "FFFFFF"},
                      category=CAT)
    noise = L["lumps"](51, 1.6)

    def mound_shape(d):
        a = math.atan2(d[1], d[0])
        return 1.0 + 0.06 * noise(d) + 0.06 * math.cos(3 * a + 0.5) * (1.0 - d[2] * d[2])

    mound = L["ball"]([0.0, 0.0, -0.55], [2.95, 2.75, 1.25], seg=7, shape=mound_shape)
    L["piece"](p, "Primary", N["floor_at"](mound, -0.3), crease=60)
    flowers = [(-1.2, -0.95, 1.45, 0.78, "Secondary", 10), (0.6, -1.35, 1.25, 0.7, "Tertiary", 40),
               (1.45, 0.25, 1.65, 0.8, "Secondary", 70), (-0.15, 0.7, 1.95, 0.85, "Tertiary", 15),
               (-1.8, 0.6, 1.3, 0.66, "Tertiary", 55), (1.0, 1.55, 1.4, 0.66, "Secondary", 30),
               (0.15, -0.2, 1.15, 0.6, "Secondary", 5)]
    for x, y, h, R, paint, spin in flowers:
        lean = [x * 0.14, y * 0.1 - 0.32, 1.0]
        top = L["v_add"]([x, y, 0.0], L["v_mul"](L["v_norm"](lean), h))
        L["piece"](p, "Primary", L["tube"]([[x, y, 0.2], L["v_lerp"]([x, y, 0.2], top, 0.5), top], 0.19, n=8,
                                           caps="flat"), crease=60)
        head, eye = flower_head(R)
        L["piece"](p, paint, L["move"](N["align"](head, lean, spin), top), crease=60)
        L["piece"](p, "Color_FFE15A", L["move"](N["align"](eye, lean), top), crease=60)
    return p


def grass_tuft():
    p = L["new_prop"]("GrassTuft", 106, 24, {"Primary": "5BCB4C"}, category=CAT)
    # (direction, length, lean) per blade; each blade arcs outward and ends in a rounded tip
    blades = [(330, 1.75, 3), (150, 1.5, 8), (10, 1.35, 20), (62, 1.2, 26), (115, 1.4, 18), (195, 1.15, 26),
              (245, 1.35, 20), (290, 1.1, 28)]
    ts = [0.0, 0.16, 0.32, 0.48, 0.62, 0.74, 0.84, 0.92, 0.97, 1.0]
    for az, length, tilt in blades:
        a = math.radians(az)
        d = [math.cos(a), math.sin(a), 0.0]
        pos = [d[0] * 0.15, d[1] * 0.15, -0.25]
        pts, ws = [], []
        for k, t in enumerate(ts):
            pts.append(list(pos))
            ws.append(0.2 * (1.0 + 0.45 * t) * max(0.0, 1.0 - t ** 3) ** 0.55)
            if k + 1 < len(ts):
                bend = math.radians(tilt) + 0.5 * t * t
                step = length * (ts[k + 1] - t)
                pos = [pos[0] + d[0] * math.sin(bend) * step, pos[1] + d[1] * math.sin(bend) * step,
                       pos[2] + math.cos(bend) * step]
        m = N["blade"](pts, ws, [0.11 * (1.0 - 0.5 * t) for t in ts], n=8, side=[-d[1], d[0], 0.0])
        L["piece"](p, "Primary", L["scale"](m, [1.25, 1.25, 0.88]), crease=65)
    return p


CAP = [(0.0, 2.75), (0.9, 2.78), (1.7, 2.95), (2.25, 3.05), (2.45, 3.25), (2.42, 3.6), (2.2, 4.15), (1.75, 4.75),
       (1.1, 5.2), (0.5, 5.42), (0.0, 5.47)]


def cap_spot(az, u, r):
    """A raised round spot on the cap's outer side at angle az and height u (0 rim .. 1 top)."""
    x = 4.0 + u * 5.999
    i = int(x)
    f = x - i
    (r0, z0), (r1, z1) = CAP[i], CAP[i + 1]
    k = math.sqrt((r1 - r0) ** 2 + (z1 - z0) ** 2)
    nr, nz = (z1 - z0) / k, -(r1 - r0) / k
    a = math.radians(az)
    nrm = [nr * math.cos(a), nr * math.sin(a), nz]
    pr = r0 + (r1 - r0) * f
    spot = L["lathe"]([(0.0, -0.12), (r, -0.12), (r, 0.0), (0.72 * r, 0.1), (0.0, 0.14)], n=12)
    return L["move"](N["align"](spot, nrm), [pr * math.cos(a), pr * math.sin(a), z0 + (z1 - z0) * f])


def mushroom_one(p, c, s, tilt, spin, spots, n):
    """A cartoon toadstool of scale s at c: bulgy stem, domed cap with a rolled rim, white spots."""
    stem = L["lathe"]([(0.0, -0.3), (1.0, -0.3), (1.02, 0.1), (0.86, 0.6), (0.72, 1.4), (0.68, 2.2), (0.74, 2.9),
                       (0.0, 3.0)], n=n - 6)

    def place(m):
        m = L["rotate"](L["scale"](m, s), "z", spin)
        return L["move"](L["rotate"](m, "x", tilt), c)

    L["piece"](p, "Color_FFF4E0", place(stem), crease=50)
    L["piece"](p, "Primary", place(L["lathe"](CAP, n=n)), crease=50)
    for az, u, r in spots:
        L["piece"](p, "Color_FFFFFF", place(cap_spot(az, u, r)), crease=60)


def mushroom():
    p = L["new_prop"]("Mushroom", 62, 24, {"Primary": "FF5E6C"}, category=CAT)
    mushroom_one(p, [-0.35, 0.3, 0.0], 1.0, 0.0, 0.0,
                 [(255, 0.3, 0.5), (300, 0.62, 0.42), (205, 0.6, 0.4), (335, 0.22, 0.38), (165, 0.25, 0.42),
                  (90, 0.45, 0.44), (30, 0.5, 0.38), (240, 0.92, 0.4)], 24)
    mushroom_one(p, [1.6, -1.15, 0.0], 0.48, -8.0, 30.0, [(240, 0.35, 0.6), (330, 0.55, 0.5), (160, 0.5, 0.55)], 20)
    return p


result = {"built": [L["report"](tree_palm()), L["report"](flower_patch()), L["report"](grass_tuft()),
                    L["report"](mushroom())]}

# ===== chunk 4/4: RockTall, CrystalCluster, Fence =====
L = session_state["L"]
N = session_state["N"]
CAT = "nature"


def rock_tall():
    p = L["new_prop"]("RockTall", 72, 24, {"Primary": "959ECB", "Secondary": "B9C0E8"}, solid=True, category=CAT)
    # A balanced cairn: four flat faceted stones, each smaller, nudged and tipped against the one
    # below (tip = axis + degrees about the stone's bottom centre), and a pebble at the foot
    stones = [("Primary", (0.0, 0.2, 1.3), 3.1, -0.5, 3.4, 61, 5, 0.4, 9, (0.15, -0.1), None),
              ("Secondary", (0.55, -0.05, 4.6), 2.45, 3.05, 6.5, 62, 5, 0.4, 8, (-0.2, 0.1), ([0.3, 1.0, 0.0], 8)),
              ("Primary", (-0.2, 0.2, 7.5), 1.8, 6.1, 8.7, 63, 5, 0.35, 7, (0.25, -0.15), ([1.0, -0.4, 0.0], -10)),
              ("Secondary", (0.15, 0.1, 9.3), 1.05, 8.45, 10.1, 64, 4, 0.28, 5, (-0.2, 0.2), None),
              ("Secondary", (-2.55, -1.75, 0.4), 1.1, -0.5, 1.5, 66, 4, 0.25, 4, (0.0, 0.0), None)]
    for paint, c, r, z0, z1, seed, sides, soft, seg, lean, tip in stones:
        m = N["stone"](c, r, z0, z1, seed=seed, sides=sides, soft=soft, seg=seg, lean=lean,
                       floor=-0.5 if z0 < 0 else None, shoulders=3 if r > 1.0 else 2)
        if tip:
            m = L["rotate"](m, tip[0], tip[1], (c[0], c[1], z0))
        L["piece"](p, paint, m, crease=30)
    return p


def crystal(h, w, tip):
    """Hexagonal crystal around +Z: a slightly flaring prism, a bevel ring and a pointed top; the
    top `tip` fraction of the point is a separate piece (it glows)."""
    z0, z1 = 0.62 * h, 0.7 * h
    zt = h - tip * (h - z1)
    rt = 0.9 * w * tip
    body = L["lathe"]([(0.0, -1.0), (w * 0.9, -1.0), (w, z0), (w * 0.9, z1), (rt, zt), (0.0, zt)], n=6,
                      phase=math.pi / 6)
    point = L["lathe"]([(0.0, zt - 0.04), (rt, zt - 0.04), (0.0, h)], n=6, phase=math.pi / 6)
    return body, point


def crystal_cluster():
    p = L["new_prop"]("CrystalCluster", 82, 24, {"Primary": "7650EE", "Secondary": "6E75B0"}, category=CAT)
    L["piece"](p, "Secondary", N["stone"]((0.0, 0.0, 0.35), 2.7, -0.5, 1.25, seed=71, seg=8, soft=0.45,
                                          floor=-0.5), crease=30)
    gems = [((0.0, 0.3, 0.5), 6.3, 1.3, (0.05, 0.1), 0), ((-1.5, -0.4, 0.5), 4.3, 0.95, (-0.55, -0.2), 15),
            ((1.55, -0.2, 0.45), 4.8, 1.0, (0.6, -0.15), 40), ((0.6, 1.5, 0.45), 3.6, 0.85, (0.3, 0.6), 25),
            ((-1.05, 1.25, 0.45), 3.0, 0.75, (-0.5, 0.45), 5), ((0.35, -1.65, 0.3), 2.2, 0.65, (0.15, -0.75), 20)]
    for c, h, w, lean, spin in gems:
        body, point = crystal(h, w, 0.3)
        n = [lean[0], lean[1], 1.0]
        L["piece"](p, "Primary", L["move"](N["align"](body, n, spin), c), crease=25)
        L["piece"](p, "Neon_FFFFFF", L["move"](N["align"](point, n, spin), c), crease=25)
    return p


def fence():
    p = L["new_prop"]("Fence", 94, 24, {"Primary": "FFF6E8", "Secondary": "7DB4F5"}, category=CAT)
    for x in (-4.45, 4.45):
        L["piece"](p, "Primary", L["lathe"]([(0.0, -0.3), (0.62, -0.3), (0.64, 0.15), (0.52, 0.42), (0.5, 3.2),
                                              (0.58, 3.32), (0.6, 3.5), (0.0, 3.5)], n=16, center=(x, 0.0, 0.0)))
        L["piece"](p, "Primary", L["ball"]([x, 0.0, 3.85], 0.5, seg=4))
    pick = L["round_poly"]([[-0.475, -0.25], [0.475, -0.25], [0.475, 2.5], [0.0, 3.15], [-0.475, 2.5]], 0.32, seg=2)
    for k in range(6):
        L["piece"](p, "Primary", L["move"](L["extrude"](pick, 0.36, bevel=0.11, seg=1), [-3.125 + 1.25 * k, -0.12, 0.0]))
    for z in (1.0, 2.3):
        L["piece"](p, "Secondary", L["rounded_box"]([0.0, 0.26, z], [8.6, 0.42, 0.6], 0.18, seg=1))
    return p


result = {"built": [L["report"](rock_tall()), L["report"](crystal_cluster()), L["report"](fence())]}
