# Storm Catcher Simulator - prop kit, category "landmarks" (tools/world/sketchup/landmarks.py)
#
# The themed landmarks of every zone (tools/world/PROPS.md, "landmarks"): windmill, hay bale, tesla
# tower, storm cloud, lightning rod, cactus, pyramid, sand arch, oasis pool, igloo, snowman, ice castle
# tower, volcano, lava spire, steam vent, floating island, star lamp, cloud bank, citadel tower and
# aurora arch. Send lib.py first (all its chunks), then each "# ===== chunk" block below as one
# build_model call, in order: chunk 1 stores the shared helpers in session_state["LM"]. Units: studs
# (piece() converts to inches), Z up, front -Y, origin at the centre of the prop's base - except
# WindmillBlades, whose origin is its hub centre (it goes on the Windmill at WINDMILL_HUB). The props
# sit side by side on the rows y = 64 and y = 120.

# ===== chunk 1/9: helpers shared by the landmark props =====
L = session_state["L"]
LM = session_state.setdefault("LM", {})
v_add, v_sub, v_mul, v_dot, v_cross, v_norm, v_len = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_cross", "v_norm", "v_len")]


def revolve(rows, n, fn, center=(0.0, 0.0, 0.0), phase=0.0):
    """Solid of revolution whose rings change with the angle: fn(i, a) -> (r, z) for ring i at angle a
    (radians). An end ring with r = 0 closes in a pole, other ends get a flat cap."""
    verts, rings = [], []
    for i in range(rows):
        r0, z0 = fn(i, phase)[:2]
        if r0 <= 1e-9 and (i == 0 or i == rows - 1):
            rings.append([len(verts)])
            verts.append([center[0], center[1], center[2] + z0])
            continue
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n + phase
            r, z = fn(i, a)[:2]
            ring.append(len(verts))
            verts.append([center[0] + r * math.cos(a), center[1] + r * math.sin(a), center[2] + z])
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


def loft(rings):
    """Closed mesh through rings of points (one point = a pole); open ends fan to their centre."""
    rings = [list(r) for r in rings]
    for end in (0, -1):
        if len(rings[end]) > 1:
            c = [sum([q[k] for q in rings[end]]) / len(rings[end]) for k in range(3)]
            if end == 0:
                rings.insert(0, [c])
            else:
                rings.append([c])
    verts, ids = [], []
    for ring in rings:
        ids.append(list(range(len(verts), len(verts) + len(ring))))
        verts += [list(q) for q in ring]
    return L["orient"]({"v": verts, "f": L["loft_faces"](ids)})


def sweep(path, fn, n=12, up=None, closed=False, rings_only=False):
    """Rings along a path: ring i at angle a reaches fn(i, a) = r or [r_side, r_up] out from the path
    (r_up along `up`, one vector or one per point; else a frame carried along the path). A radius-0 end
    ring closes in a point; closed = the path is a loop; rings_only = the rings' points (for loft())."""
    m = len(path)
    pts = [list(p) for p in path]
    if closed:
        tans = [v_norm(v_sub(pts[(i + 1) % m], pts[i - 1])) for i in range(m)]
    else:
        tans = [v_norm(v_sub(pts[min(i + 1, m - 1)], pts[max(i - 1, 0)])) for i in range(m)]
    ref = [0.0, 0.0, 1.0] if abs(tans[0][2]) < 0.9 else [1.0, 0.0, 0.0]
    side = v_norm(v_cross(tans[0], ref))
    frames = []
    for i in range(m):
        t = tans[i]
        if up is not None:
            w = up[i] if isinstance(up[0], (list, tuple)) else up
            u = v_norm(v_sub(w, v_mul(t, v_dot(w, t))))
            side = v_cross(t, u)
        else:
            side = v_norm(v_sub(side, v_mul(t, v_dot(side, t))))
            u = v_cross(side, t)
        frames.append([side, u])
    verts, rings = [], []
    for i in range(m):
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            r = fn(i, a)
            r = r if isinstance(r, (list, tuple)) else [r, r]
            if k == 0 and max(r) <= 1e-9 and not closed and (i == 0 or i == m - 1):
                break
            ring.append(len(verts))
            verts.append(v_add(pts[i], v_add(v_mul(frames[i][0], r[0] * math.cos(a)),
                                             v_mul(frames[i][1], r[1] * math.sin(a)))))
        if not ring:
            ring = [len(verts)]
            verts.append(pts[i])
        rings.append(ring)
    if rings_only:
        return [[verts[k] for k in ring] for ring in rings]
    if not closed:
        return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})
    faces = []
    for i in range(m):
        a, b = rings[i], rings[(i + 1) % m]
        faces += [[a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]] for k in range(n)]
    return L["orient"]({"v": verts, "f": faces})


def band(r_in, r_out, z0, z1, n=24, center=(0.0, 0.0, 0.0), steps=4, fat=0.6, phase=0.0):
    """A fat rounded ring round a column of radius >= r_in, from height z0 to z1, bulging out to
    r_out (its flat ends at r_in are hidden inside the column)."""
    prof = []
    for k in range(steps + 1):
        a = -math.pi / 2 + math.pi * k / steps
        c, s = math.cos(a), math.sin(a)
        zz = (abs(s) ** fat) * (1.0 if s >= 0 else -1.0)
        prof.append((r_in + (r_out - r_in) * abs(c) ** fat, (z0 + z1) / 2.0 + (z1 - z0) / 2.0 * zz))
    return L["lathe"](prof, n, center, phase)


def align(m, normal, spin=0.0):
    """Turn a mesh modelled around +Z so +Z points along `normal`, after spinning it `spin` degrees."""
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
    """Chunky faceted stone between heights z_bot and z_top (nature.py's stone): a tilted top,
    near-upright sides, shoulder bevels and a flat bottom (bevelled underneath unless floor is set)."""
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


def puff(center, balls, blend=0.8, seg=7):
    """One soft cloud of balls [[x, y, z, rx, ry, rz], ...] melted together (smooth union `blend` wide): a
    cube sphere round `center` (which must see the whole surface) pushed out to the surface."""
    def dist(p):
        d = None
        for b in balls:
            q = [(p[0] - b[0]) / b[3], (p[1] - b[1]) / b[4], (p[2] - b[2]) / b[5]]
            s = (math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2]) - 1.0) * min(b[3], b[4], b[5])
            if d is None:
                d = s
            else:
                h = max(blend - abs(d - s), 0.0) / blend
                d = min(d, s) - h * h * blend / 4.0
        return d

    far = max([v_len(v_sub(b[:3], center)) + max(b[3:]) for b in balls]) + blend
    dirs, faces = L["sphere_grid"](seg)
    verts = []
    for d in dirs:
        lo, hi = 0.0, far
        for k in range(26):
            mid = (lo + hi) / 2.0
            if dist(v_add(center, v_mul(d, mid))) < 0:
                lo = mid
            else:
                hi = mid
        verts.append(v_add(center, v_mul(d, (lo + hi) / 2.0)))
    return L["orient"]({"v": verts, "f": [list(f) for f in faces]})


def arch_poly(w, h, seg=8):
    """Arched door / window outline w wide and h tall, base centred on the origin (for extrude)."""
    r = w / 2.0
    pts = [[-r, 0.0], [r, 0.0]]
    for k in range(seg + 1):
        a = math.pi * k / seg
        pts.append([r * math.cos(a), h - r + r * math.sin(a)])
    return pts


def on_wall(m, radius, az, z, out=0.0):
    """Put a slab built facing -Y (centred on x = y = 0) on a round wall of `radius`, `az` degrees from
    the front (-Y) toward +X, its base at height z, pushed out by `out`."""
    return L["rotate"](L["move"](m, [0.0, -(radius + out), z]), "z", az)


def turn_y(m):
    """Turn a mesh modelled along +Z so it points along -Y (front)."""
    return L["rotate"](m, "x", 90)


LM.update({"revolve": revolve, "loft": loft, "sweep": sweep, "band": band, "align": align, "floor_at": floor_at,
           "stone": stone, "puff": puff, "arch_poly": arch_poly, "on_wall": on_wall, "turn_y": turn_y})
result = {"chunk": 1, "helpers": sorted(LM.keys())}

# ===== chunk 2/9: Windmill (tower), WindmillBlades, HayBale =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"
WINDMILL_HUB = (0.0, -6.4, 20.0)  # WindmillBlades' origin on the Windmill (studs; Roblox (0, 20, -6.4))


def mill_radius(z):
    t = z / 22.0
    return 6.45 - 2.1 * t + 0.32 * math.sin(math.pi * t)


def facet(z):
    """Distance from the axis to the middle of the octagonal tower's flat sides at height z."""
    return mill_radius(z) * math.cos(math.pi / 8)


def windmill():
    p = L["new_prop"]("Windmill", 0, 64, {"Primary": "F0605D", "Secondary": "5CA8FF"}, solid=True, category=CAT)
    body = "Color_FFF4E0"
    # Tower: a chubby octagonal smock mill, slightly bowed, tapering up to the cap (crisp corners)
    prof = [(0.0, -0.3), (mill_radius(0.0) + 0.05, -0.3)]
    for k in range(10):
        z = 0.1 + 21.7 * k / 9.0
        prof.append((mill_radius(z), z))
    prof.append((0.0, 21.8))
    L["piece"](p, body, L["lathe"](prof, n=8, phase=math.pi / 8), crease=30)
    # Trim rings: a plinth, a fat gallery ring at the waist and the rim under the cap
    for z0, z1, out in ((-0.3, 1.3, 0.75), (10.6, 11.9, 1.05), (20.6, 22.2, 0.85)):
        r = mill_radius((z0 + z1) / 2.0)
        L["piece"](p, "Secondary", LM["band"](r - 0.35, r + out, z0, z1, n=8, phase=math.pi / 8), crease=30)
    # Cap: a big round hat with a rolled eave and a ball on top
    cap = [(0.0, 21.8), (5.3, 21.8), (5.95, 22.0), (6.15, 22.45), (5.95, 23.05), (5.3, 23.9), (4.4, 25.0),
           (3.3, 26.2), (2.2, 27.3), (1.15, 28.2), (0.45, 28.7), (0.0, 28.8)]
    L["piece"](p, "Primary", L["lathe"](cap, n=24), crease=50)
    L["piece"](p, "Secondary", L["ball"]((0.0, 0.0, 29.35), 0.9, seg=4), crease=60)
    # Hub housing at the front, 20 studs up: the blades' hub sits on its face
    housing = L["lathe"]([(0.0, 0.0), (1.55, 0.0), (1.6, 1.6), (1.45, 2.1), (1.05, 2.35), (0.0, 2.4)], n=16)
    L["piece"](p, "Secondary", L["move"](LM["turn_y"](housing), [0.0, -3.6, WINDMILL_HUB[2]]), crease=50)
    # Arched door with a round knob on the front side, arched windows on the others
    door = L["round_poly"](LM["arch_poly"](3.4, 5.0, seg=6), 0.3, seg=1)
    L["piece"](p, "Primary", LM["on_wall"](L["extrude"](door, 0.8, bevel=0.24, seg=1), facet(3.0), 0, 1.25,
                                            out=-0.12), crease=40)
    L["piece"](p, "Secondary", L["ball"]((0.95, -facet(3.4) - 0.42, 3.4), 0.3, seg=2), crease=60)
    win = L["extrude"](L["round_poly"](LM["arch_poly"](1.9, 2.8, seg=6), 0.25, seg=1), 0.6, bevel=0.2, seg=1)
    for az, z in ((0, 6.9), (0, 14.3), (-90, 13.3), (90, 13.3), (-90, 4.4), (90, 4.4), (180, 8.4)):
        L["piece"](p, "Secondary", LM["on_wall"](win, facet(z + 1.2), az, z, out=-0.12), crease=40)
    return p


def windmill_blades():
    p = L["new_prop"]("WindmillBlades", 16, 64, {"Primary": "FFD45C", "Secondary": "5CA8FF"}, category=CAT)
    # Hub: a fat rounded drum along Y with a domed nose, centred on the origin
    hub = L["lathe"]([(0.0, -0.95), (1.5, -0.95), (1.85, -0.68), (1.92, -0.2), (1.85, 0.55), (1.55, 0.95),
                      (0.0, 0.95)], n=20)
    L["piece"](p, "Secondary", LM["turn_y"](hub), crease=50)
    nose = L["lathe"]([(0.0, 0.0), (1.2, 0.0), (1.1, 0.24), (0.75, 0.44), (0.0, 0.52)], n=16)
    L["piece"](p, "Primary", L["move"](LM["turn_y"](nose), [0.0, -0.85, 0.0]), crease=60)
    # Four blades: a spar out to the tip and a sail panel on its trailing side with two battens
    sail = L["round_poly"]([[0.3, 2.3], [3.05, 2.9], [3.25, 10.5], [0.3, 10.7]], 0.55, seg=2)
    for k in range(4):
        parts = [("Secondary", L["rounded_box"]([0.0, 0.25, 6.0], [0.98, 0.7, 9.8], 0.34, seg=1)),
                 ("Primary", L["extrude"](sail, 0.42, bevel=0.15, seg=1, y=0.25))]
        for z in (5.2, 8.4):
            parts.append(("Secondary", L["rounded_box"]([1.75, 0.25, z], [3.5, 0.66, 0.66], 0.26, seg=1)))
        for paint, m in parts:
            L["piece"](p, paint, L["rotate"](m, "y", 90 * k + 12), crease=45, collide=False)
    return p


def hay_bale():
    p = L["new_prop"]("HayBale", 32, 64, category=CAT)
    # A round bale lying on its side (axis along X), sunk a little, with two twine bands
    bale = L["puck"]((0.0, 0.0, 0.0), 2.05, 4.7, 0.75, n=24, seg=3)
    bale = L["move"](L["rotate"](bale, "y", 90), [-2.35, 0.0, 1.9])
    L["piece"](p, "Color_F2C94C", bale, crease=50)
    for x in (-1.35, 1.35):
        ring = LM["band"](1.92, 2.18, -0.24, 0.24, n=24, steps=4)
        L["piece"](p, "Color_C8963E", L["move"](L["rotate"](ring, "y", 90), [x, 0.0, 1.9]), crease=50)
    # A rolled-up swirl on each round end
    for sx in (-1.0, 1.0):
        path = []
        for k in range(34):
            t = k / 33.0
            a = 2 * math.pi * 2.1 * t
            r = 0.18 + 1.02 * t
            path.append([sx * 2.33, r * math.cos(a), 1.9 + r * math.sin(a)])
        L["piece"](p, "Color_C8963E", L["tube"](path, 0.14, n=6, caps="round", cap_seg=2), crease=60)
    return p


result = {"built": [L["report"](windmill()), L["report"](windmill_blades()), L["report"](hay_bale())]}

# ===== chunk 3/9: TeslaTower, StormCloud, LightningRod =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def tesla_tower():
    p = L["new_prop"]("TeslaTower", 44, 64, {"Primary": "C9CFEF", "Secondary": "FF9442"}, solid=True, category=CAT)
    # Two-step round plinth and four chunky buttress fins
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, -0.3), 3.95, 1.5, 0.55, n=20), crease=45)
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, 0.9), 3.0, 1.3, 0.5, n=20), crease=45)
    fin = L["round_poly"]([[1.2, 1.6], [3.6, 1.6], [3.45, 2.75], [1.5, 5.4]], 0.6, seg=2)
    for k in range(4):
        L["piece"](p, "Primary", L["rotate"](L["extrude"](fin, 1.3, bevel=0.4, seg=1), "z", 45 + 90 * k), crease=45)
    # Tapered column with a flared foot, wound with four fat copper coils, smaller toward the top
    L["piece"](p, "Primary", L["lathe"]([(0.0, 1.8), (2.6, 1.8), (2.25, 2.6), (1.98, 3.6), (1.85, 4.8), (1.7, 10.0),
                                         (1.4, 18.0), (1.3, 19.2), (0.0, 19.2)], n=16), crease=40)
    for zc, out, h in ((6.0, 1.45, 2.3), (9.6, 1.3, 2.1), (13.0, 1.15, 1.9), (16.2, 1.0, 1.7)):
        r = 1.95 - 0.55 * (zc - 1.8) / 16.2
        L["piece"](p, "Secondary", LM["band"](r - 0.15, r + out, zc - h / 2, zc + h / 2, n=20, steps=6, fat=0.85),
                   crease=50)
    # A cup on top holding the glowing orb
    cup = [(0.0, 18.4), (1.2, 18.4), (1.95, 19.1), (2.25, 19.75), (2.15, 20.2), (1.65, 20.4), (0.0, 20.4)]
    L["piece"](p, "Primary", L["lathe"](cup, n=20), crease=45)
    L["piece"](p, "Neon_9EE8FF", L["ball"]((0.0, 0.0, 21.75), 2.25, seg=6), crease=60)
    return p


def storm_cloud():
    p = L["new_prop"]("StormCloud", 56, 64, {"Primary": "6C70BE", "Secondary": "A2A8EC"}, category=CAT)
    # The cloud: big round puffs melted together over a flat base
    balls = [[0.5, 0.5, 5.75, 3.0, 2.8, 2.7], [-3.2, 0.3, 5.1, 2.5, 2.45, 2.2], [3.7, 0.2, 5.15, 2.45, 2.4, 2.1],
             [-5.65, 0.4, 4.55, 1.5, 1.75, 1.4], [5.8, 0.4, 4.6, 1.45, 1.7, 1.3], [-1.4, -1.6, 4.8, 1.9, 1.6, 1.6],
             [2.1, -1.5, 4.9, 1.8, 1.6, 1.6], [0.3, 2.5, 5.3, 2.5, 1.9, 1.9]]
    cloud = LM["puff"]([0.0, 0.4, 5.0], balls, blend=0.4, seg=12)
    L["piece"](p, "Primary", LM["floor_at"](cloud, 3.6), crease=55)
    # Two lighter puffs on top catching the sun, part of the silhouette
    tops = [[-1.45, -0.35, 7.55, 1.95, 1.8, 1.65], [2.25, -0.2, 7.15, 1.6, 1.5, 1.4]]
    L["piece"](p, "Secondary", LM["puff"]([0.3, -0.3, 7.3], tops, blend=0.45, seg=8), crease=55)
    # A fat lightning bolt hanging under it; the origin is its tip
    bolt = L["round_poly"](L["bolt_poly"](5.8), 0.34, seg=2)
    lo = min([q[1] for q in bolt])
    tip = [q for q in bolt if q[1] < lo + 1e-6][0]
    bolt = [[q[0] - tip[0], q[1] - lo] for q in bolt]
    L["piece"](p, "Neon_FFE15A", L["extrude"](bolt, 1.1, bevel=0.34, seg=2), crease=40)
    return p


def lightning_rod():
    p = L["new_prop"]("LightningRod", 70, 64, {"Primary": "8E96D6"}, category=CAT)
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, -0.3), 1.5, 0.95, 0.4, n=18), crease=45)
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, 0.45), 1.0, 0.8, 0.32, n=16), crease=45)
    L["piece"](p, "Primary", L["lathe"]([(0.0, 1.0), (0.52, 1.0), (0.46, 4.5), (0.4, 8.0), (0.0, 8.0)], n=14), crease=40)
    for zc, out in ((3.4, 0.6), (5.9, 0.5)):
        L["piece"](p, "Primary", LM["band"](0.34, 0.44 + out, zc - 0.36, zc + 0.36, n=16, steps=4, fat=0.8), crease=50)
    L["piece"](p, "Primary", L["lathe"]([(0.0, 7.5), (0.42, 7.5), (0.78, 7.95), (0.82, 8.25), (0.0, 8.25)], n=16),
               crease=45)
    # The glowing tip: a fat ball with a rounded spike, like a classic rod finial
    tip = [(0.0, 8.15), (0.48, 8.18), (0.74, 8.38), (0.82, 8.68), (0.74, 8.98), (0.5, 9.2), (0.36, 9.42),
           (0.27, 9.75), (0.13, 9.96), (0.0, 10.02)]
    L["piece"](p, "Neon_FFE15A", L["lathe"](tip, n=16), crease=50)
    return p


result = {"built": [L["report"](tesla_tower()), L["report"](storm_cloud()), L["report"](lightning_rod())]}

# ===== chunk 4/9: Cactus, Pyramid =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def ribs(a, amount=0.12, count=8):
    """Rounded cactus ribs: 1 on a rib's crest, 1 - amount in the narrow grooves between them."""
    g = 0.5 + 0.5 * math.cos(count * a)
    return 1.0 - amount * (1.0 - g) ** 2


def cactus_arm(base, elbow, top, r, n=24):
    """A ribbed arm from `base` (inside the trunk) out to an elbow of radius elbow[1] and up to
    height `top`, ending in a dome; base = (x, z), the arm bends in the XZ plane toward +x."""
    path, rad = [], []
    x0, z0 = base
    ex, er = elbow
    for k in range(3):
        path.append([x0 + (ex - x0) * k / 3.0, 0.0, z0])
    for k in range(7):
        t = -math.pi / 2 + math.pi / 2 * k / 6.0
        path.append([ex + er * math.cos(t), 0.0, z0 + er + er * math.sin(t)])
    path.append([ex + er, 0.0, (z0 + er + top) / 2.0])
    path.append([ex + er, 0.0, top])
    rad = [r] * len(path)
    for k in range(1, 5):
        phi = math.pi / 2 * k / 4.0
        path.append([ex + er, 0.0, top + r * 0.95 * math.sin(phi)])
        rad.append(r * math.cos(phi) if k < 4 else 0.0)
    return LM["sweep"](path, lambda i, a: rad[i] * ribs(a, 0.14 * min(1.0, rad[i] / r + 0.3)), n=n)


def flower_head(R, lobes=5):
    """A cupped cartoon flower around +Z: fat round petals with notches, and its domed centre."""
    rows = [(0.0, 0.22), (0.5, 0.2), (0.84, 0.27), (1.0, 0.14), (0.84, -0.04), (0.0, -0.1)]

    def fn(i, a):
        k = 0.4 + 0.6 * abs(math.cos(lobes * a / 2.0)) ** 0.55
        return rows[i][0] * R * k, rows[i][1] * R

    eye = L["lathe"]([(0.0, 0.1 * R), (0.36 * R, 0.13 * R), (0.34 * R, 0.33 * R), (0.2 * R, 0.44 * R),
                      (0.0, 0.47 * R)], n=12)
    return LM["revolve"](len(rows), 6 * lobes, fn), eye


def cactus():
    p = L["new_prop"]("Cactus", 78, 64, {"Primary": "4CB85C", "Secondary": "FF7AB0"}, category=CAT)
    # Ribbed trunk with a domed top; the ribs fade out toward the top
    prof = [(1.3, -0.3), (1.32, 0.4), (1.3, 2.5), (1.27, 4.5), (1.24, 6.3), (1.18, 7.05), (1.02, 7.6),
            (0.76, 8.0), (0.42, 8.24), (0.0, 8.32)]

    def trunk(i, a):
        r, z = prof[i]
        return r * ribs(a, 0.16 * (1.0 - L["smoothstep"](7.3, 8.3, z))), z

    L["piece"](p, "Primary", LM["revolve"](len(prof), 32, trunk), crease=60)
    # Two arms: the right one high, the left one lower and turned back a little
    L["piece"](p, "Primary", cactus_arm((0.6, 3.5), (1.4, 0.75), 6.15, 0.72), crease=60)
    left = cactus_arm((0.6, 2.5), (1.35, 0.7), 4.75, 0.66)
    L["piece"](p, "Primary", L["rotate"](left, "z", 160), crease=60)
    # A pink flower on top and a bud on the right arm
    head, eye = flower_head(1.2)
    tilt = [0.0, -0.45, 1.0]
    L["piece"](p, "Secondary", L["move"](LM["align"](head, tilt, 18), [0.0, -0.15, 8.0]), crease=60)
    L["piece"](p, "Color_FFE15A", L["move"](LM["align"](eye, tilt), [0.0, -0.15, 8.0]), crease=60)
    L["piece"](p, "Secondary", L["blob"]((2.15, -0.05, 6.95), 0.38, squash=1.15, lump=0.0, seed=3, seg=3), crease=60)
    return p


def pyramid():
    p = L["new_prop"]("Pyramid", 100, 64, {"Primary": "F5C77E", "Secondary": "E09A50"}, solid=True, category=CAT)
    # Five rounded tiers, each topped with a trim ledge
    for k in range(5):
        w = 29.4 - 5.6 * k
        z0, z1 = 3.6 * k - (0.5 if k == 0 else 0.2), 3.6 * (k + 1)
        L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.0, (z0 + z1) / 2.0], [w, w, z1 - z0], 0.9, seg=2), crease=50)
        L["piece"](p, "Secondary", L["rounded_box"]([0.0, 0.0, z1 - 0.3], [w + 0.6, w + 0.6, 0.75], 0.35, seg=1),
                   crease=50)
    # A grand staircase up the front to the top tier, framed by two sloping side walls
    steps, y0, y1, top = 12, -17.0, -4.4, 18.0
    rise, run = top / steps, (y1 - y0) / steps
    prof = [[-3.0, -0.5], [y0, -0.5]]
    for i in range(steps):
        prof += [[y0 + run * i, rise * (i + 1)], [y0 + run * (i + 1), rise * (i + 1)]]
    prof.append([-3.0, top])
    prof = L["round_poly"]([[q[0], q[1]] for q in reversed(prof)], 0.14, seg=1)
    L["piece"](p, "Secondary", L["rotate"](L["extrude"](prof, 6.0, bevel=0.3, seg=1), "z", 90), crease=40)
    wall = L["round_poly"]([[y0 - 0.7, -0.5], [-3.0, -0.5], [-3.0, top + 0.95], [y1 - 0.3, top + 0.95],
                            [y0 - 0.7, 1.7]], 0.45, seg=2)
    for x in (-3.7, 3.7):
        side = L["rotate"](L["extrude"](wall, 1.4, bevel=0.4, seg=1), "z", 90)
        L["piece"](p, "Primary", L["move"](side, [x, 0.0, 0.0]), crease=40)
    # The golden capstone: a soft square point
    cap = [(0.0, 17.9), (3.0, 17.9), (3.15, 18.25), (2.6, 19.3), (1.6, 20.6), (0.65, 21.6), (0.2, 21.95), (0.0, 22.0)]
    L["piece"](p, "Color_FFE15A", L["lathe"](cap, n=4, phase=math.pi / 4), crease=35)
    return p


result = {"built": [L["report"](cactus()), L["report"](pyramid())]}

# ===== chunk 5/9: SandArch, OasisPool =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def sand_arch():
    p = L["new_prop"]("SandArch", 134, 64, {"Primary": "EE9F5C", "Secondary": "F7C98A"}, solid=True, category=CAT)
    # Centre line: two chunky leaning legs and a squashed half-ellipse span between them (XZ plane)
    legs = (-0.9, 0.7, 2.3, 3.6, 4.9, 6.2, 7.4)
    path = [[-7.4 + 0.1 * z, 0.0, z] for z in legs]
    for k in range(1, 15):
        t = math.pi - math.pi * k / 15.0
        path.append([6.66 * math.cos(t), 0.0, 7.4 + 6.1 * math.sin(t) ** 0.8])
    path += [[7.4 - 0.1 * z, 0.0, z] for z in reversed(legs)]
    m = len(path)
    noise = L["lumps"](17, 0.62)
    twist = L["rng"](5)
    turns = [0.35 * (twist() - 0.5) for i in range(m)]

    def section(i, a):
        s = i / (m - 1.0)
        mid = math.sin(math.pi * s)
        foot = 1.0 - L["smoothstep"](-0.5, 2.8, path[i][2])
        w = (2.3 + 0.85 * (1.0 - mid) ** 1.3 + 0.5 * foot) * (1.0 + 0.1 * (s - 0.5))
        d = 2.9 + 0.75 * (1.0 - mid) + 0.4 * foot
        b = a + turns[i]
        c, sn = math.cos(b), math.sin(b)
        box = 1.0 / (abs(c) ** 2.6 + abs(sn) ** 2.6) ** (1.0 / 2.6)
        k = box * (1.0 + 0.16 * noise([path[i][0] + w * c, d * sn, path[i][2]]))
        return [w * k, d * k]

    rings = LM["sweep"](path, section, n=9, up=[0.0, 1.0, 0.0], rings_only=True)
    # Wind-worn layers: a lighter band round the middle of each leg
    last = m - 1
    for i0, i1, paint in ((0, 2, "Primary"), (2, 4, "Secondary"), (4, last - 4, "Primary"),
                          (last - 4, last - 2, "Secondary"), (last - 2, last, "Primary")):
        L["piece"](p, paint, LM["loft"](rings[i0:i1 + 1]), crease=38)
    # Fallen rocks at the feet
    for c, r, z1, seed, paint in (((-10.6, -2.3, 0.3), 1.3, 1.55, 31, "Secondary"),
                                  ((10.4, 2.1, 0.3), 1.15, 1.35, 32, "Primary"),
                                  ((-4.0, -3.2, 0.2), 0.75, 0.9, 33, "Primary")):
        L["piece"](p, paint, LM["stone"](c, r, -0.5, z1, seed=seed, seg=5, soft=0.35, floor=-0.5), crease=35,
                   collide=False)
    return p


def kidney(t):
    """Point t (radians) round the pool's kidney-shaped outline (studs, XY)."""
    x, y = 6.5 * math.cos(t), 4.6 * math.sin(t)
    return [x, y - 2.3 * math.exp(-(x / 2.7) ** 2) * L["smoothstep"](0.0, 1.0, math.sin(t))]


def flat_slab(poly, z0, z1, bevel=0.1):
    """A horizontal slab from z0 to z1 with the outline poly [(x, y), ...] (counter-clockwise)."""
    m = L["extrude"]([[q[0], -q[1]] for q in reversed(poly)], z1 - z0, bevel=bevel, seg=1)
    return L["move"](L["rotate"](m, "x", 90), [0.0, 0.0, (z0 + z1) / 2.0])


def oasis_pool():
    p = L["new_prop"]("OasisPool", 160, 64, {"Primary": "E2B272"}, category=CAT)
    N = 48
    edge = [kidney(2 * math.pi * k / N) for k in range(N)]
    # A deep blue basin and the see-through water over it
    L["piece"](p, "Color_45B4F2", flat_slab(edge, -0.35, 0.05), crease=40)
    L["piece"](p, "Glass_5CC8FF", flat_slab(edge, 0.05, 0.62, bevel=0.12), crease=40)
    # Rocky rim: a ring of fat stones melted into one loop
    stones = 13
    noise = L["lumps"](5, 0.9)
    sizes = [0.8 + 0.45 * L["rng"](40 + k)() for k in range(stones)]

    def rim(i, a):
        s = i / float(N) * stones
        bump = abs(math.sin(math.pi * s)) ** 0.7
        h = sizes[int(s) % stones]
        k = (0.5 + 0.55 * bump) * (1.0 + 0.07 * noise([edge[i][0], edge[i][1], a]))
        return [1.05 * k * (0.75 + 0.25 * h), 1.0 * k * h]

    loop = [[q[0], q[1], 0.45] for q in edge]
    L["piece"](p, "Primary", LM["floor_at"](LM["sweep"](loop, rim, n=10, up=[0.0, 0.0, 1.0], closed=True), -0.3),
               crease=50)
    # Two lily pads, one with a pink bud
    pad = [[0.78 * math.cos(math.radians(a)), 0.78 * math.sin(math.radians(a))] for a in range(25, 345, 20)]
    pad = [[0.0, 0.0]] + pad
    for (x, y), turn in (((-2.3, -1.0), 30), ((2.6, -0.4), 200)):
        L["piece"](p, "Color_5BCB4C", L["move"](L["rotate"](flat_slab(pad, 0.58, 0.76, bevel=0.06), "z", turn),
                                                [x, y, 0.0]), crease=40)
    L["piece"](p, "Color_FF86B6", L["blob"]((-2.45, -1.05, 0.98), 0.32, squash=1.1, lump=0.0, seed=4, seg=3), crease=60)
    return p


result = {"built": [L["report"](sand_arch()), L["report"](oasis_pool())]}

# ===== chunk 6/9: Igloo, Snowman, IceCastleTower =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def igloo():
    p = L["new_prop"]("Igloo", 182, 64, {"Secondary": "A9D6F5"}, solid=True, category=CAT)
    R, H, cy = 6.3, 7.1, 1.0
    snow = "Color_EAF6FF"

    def at(e, a, r):
        e = math.radians(e)
        return [r * math.cos(e) * math.cos(a), cy + r * math.cos(e) * math.sin(a), H * math.sin(e) * r / R]

    # The mortar: an inner dome that shows between the snow blocks
    inner = [(0.0, -0.3), (R, -0.3)] + [(R * math.cos(math.radians(e)), H * math.sin(math.radians(e)))
                                        for e in range(0, 91, 10)]
    L["piece"](p, "Secondary", L["lathe"](inner[:-1] + [(0.0, H)], n=28, center=(0.0, cy, 0.0)), crease=50)
    # Rows of pillowy snow blocks (staggered), tucked in at every joint so the mortar shows
    rows = [(-3.0, 17.0, 11), (17.0, 34.0, 9), (34.0, 51.0, 7), (51.0, 67.0, 5)]
    for n, (e0, e1, blocks) in enumerate(rows):
        angles = []
        for b in range(blocks):
            base = 2 * math.pi * (b + 0.5 * (n % 2)) / blocks
            angles += [(base, True)] + [(base + 2 * math.pi * f / blocks, False) for f in (0.13, 0.5, 0.87)]
        rings = []
        for f, out in ((0.0, -0.2), (0.14, 0.2), (0.5, 0.3), (0.86, 0.2), (1.0, -0.2)):
            e = e0 + (e1 - e0) * f
            rings.append([at(e, a, R + (-0.2 if joint else out)) for a, joint in angles])
        L["piece"](p, snow, LM["loft"](rings), crease=55)
    cap = [(0.0, H * math.sin(math.radians(66.0)) - 0.4)]
    for e in (66.0, 68.0, 72.0, 78.0, 84.0):
        cap.append((R * math.cos(math.radians(e)) + 0.25, H * math.sin(math.radians(e)) + 0.25 * math.sin(math.radians(e))))
    cap.append((0.0, H + 0.3))
    L["piece"](p, snow, L["lathe"](cap, n=20, center=(0.0, cy, 0.0)), crease=55)
    # The tunnel: a thick snow arch out front, with a dark doorway inside
    outer, inner_r, hgt, ihgt = 2.75, 1.5, 4.7, 3.45
    arch = [[-outer, -0.3], [-inner_r, -0.3]]
    for k in range(9):
        a = math.pi - math.pi * k / 8.0
        arch.append([inner_r * math.cos(a), ihgt - inner_r + inner_r * math.sin(a)])
    arch += [[inner_r, -0.3], [outer, -0.3]]
    for k in range(11):
        a = math.pi * k / 10.0
        arch.append([outer * math.cos(a), hgt - outer + outer * math.sin(a)])
    tunnel = L["extrude"](L["round_poly"](arch, 0.3, seg=1), 4.2, bevel=0.45, seg=2, y=-5.7)
    L["piece"](p, snow, tunnel, crease=45)
    door = L["extrude"](LM["arch_poly"](3.3, 3.6, seg=8), 1.2, y=-5.25)
    L["piece"](p, "Color_2E3B73", L["move"](door, [0.0, 0.0, -0.3]), crease=40)
    return p


def snowman():
    p = L["new_prop"]("Snowman", 200, 64, {"Primary": "FF5E6C"}, category=CAT)
    white = "Color_FFFFFF"
    ink = "Color_233066"
    L["piece"](p, white, LM["floor_at"](L["ball"]((0.0, 0.0, 1.95), [2.3, 2.3, 2.12], seg=6), -0.25), crease=60)
    L["piece"](p, white, L["ball"]((0.0, 0.0, 4.6), [1.68, 1.68, 1.55], seg=6), crease=60)
    L["piece"](p, white, L["ball"]((0.0, 0.0, 6.45), 1.25, seg=6), crease=60)
    # Woolly hat with a rolled brim and a pompom
    hat = [(1.3, 6.8), (1.4, 6.95), (1.38, 7.2), (1.2, 7.3), (1.12, 7.55), (0.9, 7.85), (0.55, 8.02), (0.0, 8.08)]
    L["piece"](p, "Primary", L["lathe"]([(0.0, 6.8)] + hat, n=20), crease=55)
    L["piece"](p, white, L["ball"]((0.0, 0.0, 8.15), 0.42, seg=3), crease=60)
    # Scarf round the neck, its tail hanging down the front
    L["piece"](p, "Primary", LM["band"](1.05, 1.55, 5.3, 6.0, n=20, steps=4, fat=0.7), crease=50)
    tail = [[0.55, -1.25, 5.55], [0.68, -1.55, 5.0], [0.78, -1.78, 4.35], [0.84, -1.86, 3.75]]
    L["piece"](p, "Primary", LM["sweep"](tail, lambda i, a: [0.38 if i < 3 else 0.3, 0.14], n=8,
                                          up=[0.0, -1.0, 0.0]), crease=55)
    # Carrot nose, coal eyes, a smile and three buttons
    nose = L["lathe"]([(0.0, 0.0), (0.3, 0.0), (0.27, 0.3), (0.16, 0.8), (0.07, 1.05), (0.0, 1.1)], n=10)
    L["piece"](p, "Color_FF9F1C", L["move"](L["rotate"](LM["turn_y"](nose), "x", -10), [0.0, -1.05, 6.4]), crease=50)

    def dot(c, r, normal):
        m = L["ball"]([0.0, 0.0, 0.0], [r, r, r * 0.6], seg=2)
        return L["move"](LM["align"](m, normal), c)

    for x in (-0.42, 0.42):
        n = L["v_norm"]([x, -1.0, 0.25])
        L["piece"](p, ink, dot(L["v_add"]([0.0, 0.0, 6.45], L["v_mul"](n, 1.2)), 0.21, n), crease=60)
    for k in range(5):
        a = math.radians(-60 + 30 * k)
        n = L["v_norm"]([0.62 * math.sin(a), -1.0, -0.4 - 0.12 * math.cos(a)])
        L["piece"](p, ink, dot(L["v_add"]([0.0, 0.0, 6.45], L["v_mul"](n, 1.2)), 0.12, n), crease=60)
    for z in (5.1, 4.45, 3.2):
        c = [0.0, 0.0, 4.6 if z > 4 else 1.95]
        n = L["v_norm"]([0.0, -1.0, (z - c[2]) / 1.5])
        rr = [1.68, 1.68, 1.55] if z > 4 else [2.3, 2.3, 2.12]
        L["piece"](p, ink, dot([0.0, -rr[1] * math.sqrt(max(0.0, 1.0 - ((z - c[2]) / rr[2]) ** 2)), z], 0.2, n),
                   crease=60)
    return p


def ice_castle_tower():
    p = L["new_prop"]("IceCastleTower", 214, 64, {"Primary": "9AD8FF", "Secondary": "4C8FE6"}, solid=True,
                      category=CAT)
    sides = 12
    phase = -math.pi / 2 - math.pi / sides
    L["piece"](p, "Secondary", L["puck"]((0.0, 0.0, -0.4), 5.7, 1.9, 0.65, n=24), crease=45)
    # Faceted ice body (crisp vertical edges), a corbelled battlement drum and its merlons
    body = [(0.0, 1.0), (4.75, 1.0), (4.6, 6.0), (4.42, 12.0), (4.25, 18.0), (0.0, 18.0)]
    L["piece"](p, "Primary", L["lathe"](body, n=sides, phase=phase), crease=25)
    drum = [(0.0, 16.6), (4.1, 16.6), (4.45, 17.1), (5.15, 18.0), (5.55, 18.9), (5.6, 20.9), (5.35, 21.2), (0.0, 21.2)]
    L["piece"](p, "Primary", L["lathe"](drum, n=24), crease=45)
    for k in range(8):
        merlon = L["rounded_box"]([0.0, -5.0, 21.9], [1.75, 1.2, 1.8], 0.45, seg=1)
        L["piece"](p, "Primary", L["rotate"](merlon, "z", 22.5 + 45 * k), crease=45)
    # Cone roof with a glowing ice crystal on top
    roof = [(0.0, 20.9), (4.35, 20.9), (4.5, 21.35), (3.95, 22.6), (3.15, 24.4), (2.3, 26.3), (1.5, 28.1), (0.8, 29.6),
            (0.35, 30.5), (0.0, 30.75)]
    L["piece"](p, "Secondary", L["lathe"](roof, n=24), crease=50)
    gem = [(0.0, 30.3), (0.48, 30.4), (0.55, 31.1), (0.0, 31.95)]
    L["piece"](p, "Neon_BDF4FF", L["lathe"](gem, n=6), crease=30)
    # Glowing arched windows on frames, and a door
    flat = 4.6 * math.cos(math.pi / sides)

    def window(w, h, az, z):
        frame = L["extrude"](L["round_poly"](LM["arch_poly"](w + 0.6, h + 0.45, seg=4), 0.2, seg=1), 0.5, bevel=0.15,
                             seg=1)
        pane = L["extrude"](L["round_poly"](LM["arch_poly"](w, h, seg=4), 0.2, seg=1), 0.5, bevel=0.15, seg=1)
        L["piece"](p, "Secondary", LM["on_wall"](frame, flat - 0.12, az, z - 0.25), crease=40)
        L["piece"](p, "Neon_BDF4FF", LM["on_wall"](pane, flat - 0.02, az, z), crease=40)

    window(1.8, 3.0, 0, 7.6)
    window(1.5, 2.5, 0, 13.0)
    window(1.5, 2.5, -120, 10.2)
    window(1.5, 2.5, 120, 10.2)
    door = L["extrude"](L["round_poly"](LM["arch_poly"](2.5, 3.6, seg=4), 0.25, seg=1), 0.7, bevel=0.2, seg=1)
    L["piece"](p, "Secondary", LM["on_wall"](door, 4.7 * math.cos(math.pi / sides) - 0.15, 0, 1.0), crease=40)
    return p


result = {"built": [L["report"](igloo()), L["report"](snowman()), L["report"](ice_castle_tower())]}

# ===== chunk 7/9: Volcano, LavaSpire, SteamVent =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"
VOLCANO = [(29.8, -1.5), (29.6, 0.0), (27.0, 2.2), (22.6, 5.4), (18.6, 9.2), (15.3, 13.6), (12.9, 18.5), (11.2, 23.5),
           (10.0, 28.5), (9.25, 33.0), (9.0, 36.4), (9.1, 38.1), (8.7, 39.3), (7.9, 39.85), (7.0, 39.75), (6.4, 39.0),
           (6.0, 37.6), (4.5, 36.0), (0.0, 35.6)]


def cone_radius(z):
    """The volcano's outer radius at height z (outer slope only)."""
    for k in range(10):
        (r0, z0), (r1, z1) = VOLCANO[k], VOLCANO[k + 1]
        if z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return VOLCANO[10][0]


def volcano():
    p = L["new_prop"]("Volcano", 0, 120, {"Primary": "6E5464", "Secondary": "4A3A4E"}, solid=True, category=CAT)
    noise = L["lumps"](61, 0.16)

    def ridge(a, z):
        fade = 1.0 - L["smoothstep"](34.0, 38.5, z)
        return 1.0 + fade * (0.055 * math.cos(7 * a + 0.4 * math.sin(3 * a)) + 0.05 * noise([math.cos(a) * 20, math.sin(a) * 20, z]))

    def cone(i, a):
        r, z = VOLCANO[i]
        return r * ridge(a, z), z

    # The rock cone up to the ash line, then the scorched top with a rounded crater lip; the wavy
    # seam between them is closed by a point inside on both sides
    def seam(a):
        z = 18.5 + 1.8 * math.sin(5 * a + 1.0) + 0.9 * math.sin(9 * a)
        return cone_radius(z) * ridge(a, z), z

    def upper(i, a):
        return (0.0, 18.0) if i == 0 else (seam(a) if i == 1 else cone(i + 5, a))

    def lower(i, a):
        return (0.0, 18.0) if i == 7 else (seam(a) if i == 6 else cone(i, a))

    L["piece"](p, "Primary", LM["revolve"](8, 40, lower), crease=45)
    L["piece"](p, "Secondary", LM["revolve"](len(VOLCANO) - 5, 40, upper), crease=45)
    # Glowing lava in the crater
    L["piece"](p, "Neon_FF7A2E", L["lathe"]([(0.0, 36.0), (6.3, 36.0), (6.25, 37.3), (4.0, 37.7), (0.0, 37.85)], n=24),
               crease=40)
    # Three lava streaks running down from the lip
    for a0, length, wob in ((-1.4, 24.0, 0.06), (-0.55, 17.0, -0.05), (2.35, 21.0, 0.05)):
        path, ups, wid = [], [], []
        for k in range(14):
            t = k / 13.0
            z = 39.2 - length * t
            a = a0 + wob * math.sin(3.0 * t * math.pi) + 0.04 * t
            r = cone_radius(z) * ridge(a, z) + 0.15
            if z > 38.0:
                r = 9.0 - 0.4 * (z - 38.0)
            path.append([r * math.cos(a), r * math.sin(a), z])
            ups.append([math.cos(a), math.sin(a), 0.45])
            wid.append((2.1 + 1.0 * t) * min(1.0, 4.0 * (1.0 - t)) ** 0.7 + 0.05)
        wid[-1] = 0.0
        L["piece"](p, "Neon_FF7A2E", LM["sweep"](path, lambda i, a: [wid[i], 0.6 * min(1.0, wid[i])], n=8, up=ups),
                   crease=50)
    # Boulders round the foot
    for c, r, z1, seed in (((-22.0, -18.5, 1.0), 4.6, 5.8, 71), ((25.0, -11.0, 0.8), 3.6, 4.4, 72)):
        L["piece"](p, "Secondary", LM["stone"](c, r, -0.8, z1, seed=seed, seg=5, soft=0.7, floor=-0.8), crease=35)
    return p


def surface_r(m, az, z, around=0.3, band=0.9):
    """Roughly how far a convex mesh reaches from the Z axis toward angle az (radians) at height z."""
    best = 0.0
    for q in m["v"]:
        if abs(q[2] - z) < band:
            d = (math.atan2(q[1], q[0]) - az + math.pi) % (2 * math.pi) - math.pi
            if abs(d) < around:
                best = max(best, math.hypot(q[0], q[1]) * math.cos(d))
    return best


def lava_spire():
    p = L["new_prop"]("LavaSpire", 70, 120, {"Primary": "5E4651"}, category=CAT)
    # A tall tapering rock and a tipped top chunk; a glowing core shows in the seam between them
    L["piece"](p, "Neon_FF7A2E", L["lathe"]([(0.0, 6.0), (1.55, 6.0), (1.35, 9.0), (0.0, 9.6)], n=10), crease=40)
    base = LM["stone"]((0.0, 0.0, 3.0), 2.9, -0.5, 8.4, seed=81, sides=6, shoulders=3, soft=0.3, seg=8,
                       lean=(0.12, -0.08), floor=-0.5, tilt=(0.3, 0.12))
    L["piece"](p, "Primary", base, crease=30)
    top = LM["stone"]((0.1, 0.1, 10.4), 1.6, 8.6, 13.9, seed=83, sides=5, shoulders=3, soft=0.26, seg=7,
                      lean=(-0.4, 0.22), tilt=(0.36, 0.14))
    L["piece"](p, "Primary", L["rotate"](top, [1.0, 0.4, 0.0], 9, (0.1, 0.1, 8.6)), crease=30)
    # Glowing zigzag cracks running down the faces of the tall rock
    for az, z0, z1 in ((-95, 7.2, 0.6), (30, 6.0, 0.8), (150, 6.8, 1.6)):
        crack, rad = [], []
        for k in range(7):
            t = k / 6.0
            z = z0 + (z1 - z0) * t
            a = math.radians(az + 10 * (1 if k % 2 else -1) * (0.4 + 0.6 * t))
            r = surface_r(base, a, z) - 0.06
            crack.append([r * math.cos(a), r * math.sin(a), z])
            rad.append(0.26 * math.sin(math.pi * (0.15 + 0.7 * t)) + 0.08)
        L["piece"](p, "Neon_FF7A2E", L["tube"](crack, rad, n=6, caps="round", cap_seg=2), crease=50)
    # Two small rocks at its foot
    for c, r, h, seed in (((2.9, -1.6, 0.3), 1.0, 1.4, 85), ((-2.6, 2.0, 0.2), 0.8, 1.05, 86)):
        L["piece"](p, "Primary", LM["stone"](c, r, -0.5, h, seed=seed, seg=4, soft=0.25, floor=-0.5), crease=30)
    return p


def steam_vent():
    p = L["new_prop"]("SteamVent", 82, 120, {"Primary": "6E5A57"}, category=CAT)
    noise = L["lumps"](91, 1.1)
    ring = [(2.95, -0.3), (3.05, 0.2), (2.85, 0.75), (2.35, 1.25), (1.75, 1.45), (1.3, 1.3), (1.1, 0.9), (0.95, 0.4),
            (0.0, 0.3)]

    def mound(i, a):
        r, z = ring[i]
        k = 1.0 + 0.09 * noise([math.cos(a) * 2, math.sin(a) * 2, z]) * (1.0 if i < len(ring) - 1 else 0.0)
        return r * k, z * (1.0 + 0.12 * noise([math.cos(a), math.sin(a), 2.0])) if 0 < i < 7 else z

    L["piece"](p, "Primary", LM["revolve"](len(ring), 24, mound), crease=40)
    # Rocks round the rim
    for k, (r, h) in enumerate(((0.95, 1.95), (0.75, 1.65), (0.85, 1.85), (0.65, 1.5), (0.8, 1.75))):
        a = 2 * math.pi * (k + 0.2) / 5.0
        c = (2.3 * math.cos(a), 2.3 * math.sin(a), 0.6)
        L["piece"](p, "Primary", LM["stone"](c, r, 0.0, h, seed=92 + k, sides=5, soft=0.25, seg=4), crease=32)
    # The glowing vent
    L["piece"](p, "Neon_FFB15C", L["lathe"]([(0.0, 0.2), (1.2, 0.2), (1.15, 0.7), (0.7, 0.95), (0.0, 1.02)], n=16),
               crease=45)
    return p


result = {"built": [L["report"](volcano()), L["report"](lava_spire()), L["report"](steam_vent())]}

# ===== chunk 8/9: FloatingIsland, StarLamp, CloudBank =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def floating_island():
    p = L["new_prop"]("FloatingIsland", 96, 120, {"Primary": "7FDB6A", "Secondary": "B48C76", "Tertiary": "8A6A63"},
                      category=CAT)
    noise = L["lumps"](101, 0.35)

    def outline(a):
        k = 1.0 + 0.07 * math.cos(3 * a + 0.5) + 0.05 * math.cos(5 * a + 1.3)
        return 7.7 * k * math.sqrt(1.0 / (math.cos(a) ** 2 + (math.sin(a) / 0.88) ** 2))

    # Grass top: a thick soft slab whose rim droops into a few round drips
    grass = [(0.0, 10.05), (0.45, 10.0), (0.78, 9.86), (0.93, 9.62), (0.995, 9.28), (1.0, 8.92), (0.965, 8.6),
             (0.86, 8.45), (0.6, 8.5), (0.0, 8.6)]

    def top(i, a):
        f, z = grass[i]
        drip = 0.75 * max(0.0, math.cos(7 * a + 0.3)) ** 3
        if i >= 6:
            z -= drip * (1.0 if i == 6 else 0.7)
        return f * outline(a), z

    L["piece"](p, "Primary", LM["revolve"](len(grass), 42, top), crease=50)
    # Rocky cone underneath, faceted, in two layers split along a wavy seam
    rows = [8.95, 8.1, 7.0, 5.8, 4.6, 3.4, 2.2, 1.1, 0.35, 0.0]

    def rock(i, a, zz=None):
        z = rows[i] if zz is None else zz
        if z <= 0.0:
            return 0.0, 0.0
        ridge = 1.0 + 0.1 * math.cos(6 * a + 0.8) + 0.08 * noise([math.cos(a) * 6, math.sin(a) * 6, z])
        return 0.93 * outline(a) * (z / 8.95) ** 0.72 * ridge, z

    def seam(a):
        return 4.6 + 0.6 * math.sin(4 * a + 0.7) + 0.35 * math.sin(7 * a)

    def upper(i, a):
        return (0.0, 4.4) if i == 5 else rock(i, a, seam(a) if i == 4 else None)

    def lower(i, a):
        return (0.0, 4.9) if i == 0 else rock(i + 3, a, seam(a) if i == 1 else None)

    L["piece"](p, "Secondary", LM["revolve"](6, 30, upper), crease=35)
    L["piece"](p, "Tertiary", LM["revolve"](len(rows) - 3, 30, lower), crease=35)
    return p


def star_lamp():
    p = L["new_prop"]("StarLamp", 116, 120, {"Primary": "7C6CF0"}, category=CAT)
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, -0.3), 1.4, 0.95, 0.4, n=18), crease=45)
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, 0.5), 0.9, 0.7, 0.3, n=16), crease=45)
    L["piece"](p, "Primary", L["lathe"]([(0.0, 1.0), (0.46, 1.0), (0.4, 4.5), (0.36, 7.2), (0.0, 7.2)], n=14), crease=40)
    L["piece"](p, "Primary", LM["band"](0.32, 0.82, 3.4, 4.1, n=16, steps=4, fat=0.8), crease=50)
    cup = [(0.0, 6.75), (0.5, 6.75), (0.85, 7.05), (0.95, 7.35), (0.82, 7.5), (0.0, 7.5)]
    L["piece"](p, "Primary", L["lathe"](cup, n=16), crease=45)
    # A puffy glowing star facing the front
    star = L["round_poly"](L["star_poly"](5, 1.5, 0.74), 0.24, seg=2)
    L["piece"](p, "Neon_FFE15A", L["move"](L["extrude"](star, 0.95, bevel=0.32, seg=2), [0.0, 0.0, 8.5]), crease=45)
    return p


def cloud_bank():
    p = L["new_prop"]("CloudBank", 136, 120, {"Secondary": "D3DCFF"}, category=CAT)
    balls = [[0.0, 0.5, 5.4, 4.5, 4.1, 3.9], [-5.8, 0.3, 4.3, 3.6, 3.4, 3.1], [5.9, 0.8, 4.4, 3.7, 3.5, 3.2],
             [-9.5, 0.4, 3.0, 2.4, 2.6, 2.2], [9.7, 0.6, 3.1, 2.3, 2.5, 2.1], [-2.6, -3.0, 3.5, 2.8, 2.4, 2.5],
             [2.9, -2.8, 3.7, 2.7, 2.3, 2.4], [-1.0, 3.6, 4.2, 3.2, 2.6, 2.8], [1.9, 0.0, 7.6, 2.6, 2.4, 2.2],
             [-3.4, 0.6, 6.6, 2.4, 2.2, 2.0]]
    cloud = LM["puff"]([0.0, 0.5, 4.4], balls, blend=0.6, seg=12)
    L["piece"](p, "Color_FFFFFF", LM["floor_at"](cloud, 1.0), crease=55)
    # The shaded underside: a flat layer of puffs bulging out round the bottom
    belly = [[x, y, 1.75, rx * 0.98 + 0.4, ry * 0.98 + 0.4, 1.95] for x, y, z, rx, ry, rz in balls if z < 6.0]
    L["piece"](p, "Secondary", LM["floor_at"](LM["puff"]([0.0, 0.5, 1.8], belly, blend=0.6, seg=9), -0.2),
               crease=55)
    return p


result = {"built": [L["report"](floating_island()), L["report"](star_lamp()), L["report"](cloud_bank())]}

# ===== chunk 9/9: CitadelTower, AuroraArch =====
L = session_state["L"]
LM = session_state["LM"]
CAT = "landmarks"


def citadel_window(p, w, h, radius, az, z, seg=4, sill=True):
    """A glowing arched window on a round wall, with a little sill."""
    pane = L["extrude"](L["round_poly"](LM["arch_poly"](w, h, seg=seg), 0.2, seg=1), 0.55, bevel=0.17, seg=1)
    L["piece"](p, "Neon_FFF3B0", LM["on_wall"](pane, radius - 0.1, az, z), crease=40)
    if not sill:
        return
    sill = L["rounded_box"]([0.0, 0.0, 0.0], [w + 0.7, 0.75, 0.4], 0.17, seg=1)
    L["piece"](p, "Secondary", LM["on_wall"](sill, radius + 0.05, az, z - 0.12), crease=45)


def citadel_tower():
    p = L["new_prop"]("CitadelTower", 156, 120, {"Primary": "F1EEFF", "Secondary": "FFC94D", "Tertiary": "7A5CF0"},
                      solid=True, category=CAT)
    # Plinth, a gently tapering round body, a corbelled gold balcony and a belfry drum
    L["piece"](p, "Secondary", L["puck"]((0.0, 0.0, -0.4), 5.6, 1.7, 0.6, n=20), crease=45)
    body = [(0.0, 1.0), (4.75, 1.0), (4.6, 6.0), (4.4, 12.0), (4.2, 18.0), (4.05, 22.0), (0.0, 22.0)]
    L["piece"](p, "Primary", L["lathe"](body, n=24), crease=40)
    balcony = [(3.9, 20.0), (4.3, 20.4), (5.1, 21.3), (5.55, 22.1), (5.6, 22.9), (5.3, 23.25), (0.0, 23.25)]
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 20.0)] + balcony, n=24), crease=45)
    belfry = [(0.0, 23.0), (4.55, 23.0), (4.6, 26.4), (0.0, 26.4)]
    L["piece"](p, "Primary", L["lathe"](belfry, n=24), crease=40)
    # Tall cone roof with a flared eave and a gold ball on top
    roof = [(0.0, 26.1), (5.6, 26.1), (5.85, 26.45), (5.5, 26.9), (4.4, 27.9), (3.3, 29.0), (2.3, 30.3), (1.4, 31.6),
            (0.7, 32.7), (0.25, 33.4), (0.0, 33.55)]
    L["piece"](p, "Tertiary", L["lathe"](roof, n=24), crease=50)
    L["piece"](p, "Secondary", L["ball"]((0.0, 0.0, 33.85), 0.62, seg=3), crease=60)
    # A little turret on the right side, corbelled out of the wall
    tc = (4.25, -0.4)
    turret = [(0.0, 8.4), (0.5, 8.5), (1.35, 9.5), (1.85, 10.5), (1.9, 16.6), (0.0, 16.6)]
    L["piece"](p, "Primary", L["lathe"](turret, n=16, center=(tc[0], tc[1], 0.0)), crease=40)
    L["piece"](p, "Secondary", LM["band"](1.7, 2.3, 16.2, 17.0, n=16, center=(tc[0], tc[1], 0.0), steps=4, fat=0.8),
               crease=45)
    troof = [(0.0, 16.7), (2.35, 16.7), (2.4, 17.0), (1.9, 17.8), (1.25, 19.0), (0.68, 20.2), (0.2, 21.0), (0.0, 21.15)]
    L["piece"](p, "Tertiary", L["lathe"](troof, n=16, center=(tc[0], tc[1], 0.0)), crease=50)
    L["piece"](p, "Secondary", L["ball"]((tc[0], tc[1], 21.4), 0.4, seg=3), crease=60)
    # Glowing windows: two up the front, the belfry ring, one on the turret; a door at the bottom
    citadel_window(p, 2.0, 3.2, 4.55, 0, 6.6)
    citadel_window(p, 1.7, 2.7, 4.35, 0, 13.4)
    for az in (0, 90, 180, 270):
        citadel_window(p, 1.35, 2.0, 4.6, az + 45, 23.8, seg=3, sill=False)
    turret_win = L["extrude"](L["round_poly"](LM["arch_poly"](1.0, 1.7, seg=3), 0.15, seg=1), 0.5, bevel=0.15, seg=1)
    L["piece"](p, "Neon_FFF3B0", L["move"](LM["on_wall"](turret_win, 1.82, 35, 12.6), [tc[0], tc[1], 0.0]), crease=40)
    door = L["extrude"](L["round_poly"](LM["arch_poly"](2.6, 3.8, seg=4), 0.25, seg=1), 0.7, bevel=0.22, seg=1)
    L["piece"](p, "Secondary", LM["on_wall"](door, 4.62, 0, 1.0, out=-0.1), crease=40)
    return p


def aurora_arch():
    p = L["new_prop"]("AuroraArch", 182, 120, category=CAT)
    # Three translucent ribbons arching over, nested and staggered front to back, rippling gently
    bands = [("Glass_9EF0D8", 11.9, 17.0, -1.15, 1.6, 0.0), ("Glass_B58CFF", 10.0, 14.4, 0.05, 1.4, 1.7),
             ("Glass_9EF0D8", 8.1, 11.8, 1.2, 1.2, 3.1)]
    for paint, half, height, y, width, phase in bands:
        path, wid = [], []
        for k in range(29):
            t = k / 28.0
            a = math.pi * (1.0 - t)
            path.append([half * math.cos(a), y + 0.35 * math.sin(4 * math.pi * t + phase),
                         -0.6 + (height + 0.6) * math.sin(a) ** 0.9])
            wid.append(width * (0.85 + 0.15 * math.sin(6 * math.pi * t + phase)))
        L["piece"](p, paint, LM["sweep"](path, lambda i, a: [wid[i], 0.32], n=8, up=[0.0, 1.0, 0.0]), crease=50)
    return p


result = {"built": [L["report"](citadel_tower()), L["report"](aurora_arch())]}
