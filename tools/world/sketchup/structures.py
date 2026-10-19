# Storm Catcher Simulator - prop kit, category "structures" (tools/world/sketchup/structures.py)
#
# The hub and zone buildings (tools/world/PROPS.md, "structures"): weather tower, station booth, weather
# lab, rebirth shrine, forecast tower, egg incubator, sell machine, zone gate, cliff segment, cloud puff,
# bench, sign post, planter and leaderboard frame. MapService keeps the gameplay parts (prompts, signs,
# SurfaceGuis) and places them on these, so the flat sign / screen areas below sit exactly where its
# SurfaceGuis go. Send lib.py first (all its chunks), then each "# ===== chunk" block below as one
# build_model call, in order: chunk 1 stores the shared helpers in session_state["ST"]. Units: studs
# (piece() converts to inches), Z up, front -Y, origin at the centre of the prop's base - except
# CliffSegment, whose origin is on its flat top (z = 0) and which hangs down to z = -30. The props sit
# side by side on the rows y = 180 and y = 230.

# ===== chunk 1/8: helpers shared by the structures =====
L = session_state["L"]
ST = session_state.setdefault("ST", {})
v_add, v_sub, v_mul, v_dot, v_cross, v_norm, v_len = [L[k] for k in (
    "v_add", "v_sub", "v_mul", "v_dot", "v_cross", "v_norm", "v_len")]


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


def revolve(rows, n, fn, center=(0.0, 0.0, 0.0), phase=0.0):
    """Solid of revolution whose rings change with the angle: fn(i, a) -> (r, z) for ring i at angle a.
    An end ring with r = 0 closes in a pole, other ends get a flat cap."""
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


def torus(center, big, small, n=24, m=8, axis="z", tall=None):
    """Doughnut of radius `big` and tube radius `small` (tube height `tall`) around a Z axis, or
    standing up facing -Y with axis="y"."""
    tall = small if tall is None else tall
    verts, faces = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            rr = big + small * math.cos(b)
            verts.append([rr * math.cos(a), rr * math.sin(a), tall * math.sin(b)])
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            faces.append([i * m + j, i2 * m + j, i2 * m + j2, i * m + j2])
    mesh = L["orient"]({"v": verts, "f": faces})
    if axis == "y":
        mesh = L["rotate"](mesh, "x", 90)
    return L["move"](mesh, center)


def sweep(path, radius, n=8, closed=True, up=None):
    """Tube of radius `radius` (number, or [side, up] for an oval) along a path; closed = a loop.
    up = a fixed 'up' vector for the oval's second axis (default: +Y, for loops drawn in the XZ plane)."""
    m = len(path)
    rs = radius if isinstance(radius, (list, tuple)) else [radius, radius]
    w = up or [0.0, 1.0, 0.0]
    verts, rings = [], []
    for i in range(m):
        if closed:
            t = v_norm(v_sub(path[(i + 1) % m], path[i - 1]))
        else:
            t = v_norm(v_sub(path[min(i + 1, m - 1)], path[max(i - 1, 0)]))
        u = v_norm(v_sub(w, v_mul(t, v_dot(w, t))))
        side = v_cross(t, u)
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            ring.append(len(verts))
            verts.append(v_add(path[i], v_add(v_mul(side, rs[0] * math.cos(a)), v_mul(u, rs[1] * math.sin(a)))))
        rings.append(ring)
    if not closed:
        return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})
    faces = []
    for i in range(m):
        a, b = rings[i], rings[(i + 1) % m]
        faces += [[a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]] for k in range(n)]
    return L["orient"]({"v": verts, "f": faces})


def rrect_path(w, h, r, seg=3, center=(0.0, 0.0, 0.0)):
    """Closed rounded-rectangle loop w x h in the XZ plane (for sweep), counter-clockwise from the front."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            pts.append([center[0] + cx + r * math.cos(a), center[1], center[2] + cz + r * math.sin(a)])
    return pts


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


def arch_poly(w, h, seg=8):
    """Arched door / window outline w wide and h tall, base centred on the origin (for extrude)."""
    r = w / 2.0
    pts = [[-r, 0.0], [r, 0.0]]
    for k in range(seg + 1):
        a = math.pi * k / seg
        pts.append([r * math.cos(a), h - r + r * math.sin(a)])
    return pts


def circle_poly(r, n=12, cx=0.0, cz=0.0):
    return [[cx + r * math.cos(2 * math.pi * k / n), cz + r * math.sin(2 * math.pi * k / n)] for k in range(n)]


def on_wall(m, radius, az, z, out=0.0):
    """Put a slab built facing -Y (centred on x = y = 0) on a round wall of `radius`, `az` degrees from
    the front (-Y) toward +X, its base at height z, pushed out by `out`."""
    return L["rotate"](L["move"](m, [0.0, -(radius + out), z]), "z", az)


def turn_y(m):
    """Turn a mesh modelled along +Z so it points along -Y (front)."""
    return L["rotate"](m, "x", 90)


def slab(poly, depth, bevel, radius, seg=2, y=0.0):
    """Puffy slab facing -Y from a SHARP 2D outline [(x, z), ...] (counter-clockwise seen from the front),
    `depth` thick: corners rounded by `radius`, front and back edges by `bevel`."""
    steps = []
    for k in range(seg + 1):
        a = math.pi / 2 * k / seg
        steps.append([bevel * (1 - math.sin(a)), -depth / 2 + bevel * (1 - math.cos(a))])
    steps += [[st[0], -st[1]] for st in reversed(steps)]
    verts, rings = [], []
    for inset, yy in steps:
        q = L["offset_poly"](poly, inset) if inset > 1e-9 else poly
        ring = []
        for pt in L["round_poly"](q, max(radius - inset, 0.06), seg=2):
            ring.append(len(verts))
            verts.append([pt[0], y + yy, pt[1]])
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


ST.update({"loft": loft, "revolve": revolve, "torus": torus, "sweep": sweep, "rrect_path": rrect_path,
           "band": band, "align": align, "floor_at": floor_at, "arch_poly": arch_poly, "circle_poly": circle_poly,
           "on_wall": on_wall, "turn_y": turn_y, "slab": slab})
result = {"chunk": 1, "helpers": sorted(ST.keys())}

# ===== chunk 2/9: WeatherTower - the hub's landmark =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"
BODY = "Color_EEF0FF"
v_add, v_mul, v_norm = L["v_add"], L["v_mul"], L["v_norm"]


def balcony(z0, r_in, r_out, rim, n=20):
    """A round balcony: a corbel flaring out of the trunk (radius r_in at height z0), a rounded parapet
    of height `rim` and a flat deck inside it (returns the mesh and the deck height)."""
    deck = z0 + 2.6
    prof = [(r_in - 0.3, z0), (r_out - 1.1, z0 + 1.3), (r_out + 0.1, z0 + 2.45), (r_out + 0.18, deck + rim - 0.4),
            (r_out - 0.3, deck + rim), (r_out - 0.85, deck + rim - 0.3), (r_out - 0.95, deck), (0.0, deck)]
    return L["lathe"](prof, n), deck


def cup():
    """An anemometer cup: a little bowl opening toward +Z."""
    return L["lathe"]([(0.0, -0.6), (0.72, -0.3), (0.86, 0.18), (0.52, 0.02), (0.0, -0.18)], 8)


def window(p, frame, glass, radius, az, z, r=1.25):
    """A round porthole on a round wall: a fat frame ring round a glowing pane."""
    ring = ST["torus"]((0.0, 0.0, r), r, 0.36, n=10, m=4, axis="y", tall=0.3)
    L["piece"](p, frame, ST["on_wall"](ring, radius, az, z, out=0.08), crease=50, collide=False)
    pane = L["extrude"](ST["circle_poly"](r + 0.05, 12, 0.0, r), 0.5)
    L["piece"](p, glass, ST["on_wall"](pane, radius - 0.1, az, z), crease=40)


def weather_tower():
    p = L["new_prop"]("WeatherTower", 0, 180, {"Primary": "5CC8FF", "Secondary": "8A6CF0"}, solid=True, category=CAT)
    lamp = "Neon_9EE8FF"
    # Plinth and the stout lower trunk, a gentle taper
    L["piece"](p, "Secondary", L["puck"]((0.0, 0.0, -0.4), 10.6, 2.3, 0.85, n=20), crease=45)
    lower = [(0.0, 1.4), (8.35, 1.4), (8.1, 7.0), (7.6, 13.5), (7.15, 19.6), (0.0, 19.6)]
    L["piece"](p, BODY, L["lathe"](lower, n=20), crease=40)
    # Balcony 1, the slimmer middle trunk, balcony 2 and the round control cabin
    deck_mesh, deck = balcony(18.4, 7.15, 9.5, 1.15, n=20)
    L["piece"](p, "Primary", deck_mesh, crease=50)
    middle = [(0.0, deck - 0.2), (6.2, deck - 0.2), (5.9, 28.0), (5.6, 34.2), (0.0, 34.2)]
    L["piece"](p, BODY, L["lathe"](middle, n=18), crease=40)
    deck2_mesh, deck2 = balcony(33.4, 5.6, 7.6, 1.0, n=20)
    L["piece"](p, "Primary", deck2_mesh, crease=50)
    cabin = [(0.0, deck2 - 0.2), (4.7, deck2 - 0.2), (4.85, 39.3), (5.0, 43.2), (0.0, 43.2)]
    L["piece"](p, BODY, L["lathe"](cabin, n=18), crease=40)
    # The cabin's glowing window band with fat mullions
    L["piece"](p, lamp, L["lathe"]([(0.0, 39.2), (5.08, 39.2), (5.12, 42.1), (0.0, 42.1)], n=20), crease=40)
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        c = [5.15 * math.cos(a), 5.15 * math.sin(a)]
        L["piece"](p, "Secondary", L["tube"]([[c[0], c[1], 39.25], [c[0], c[1], 42.05]], 0.36, n=6, caps="round",
                                            cap_seg=1), crease=50, collide=False)
    # Domed roof with a rolled eave, a collar and the mast
    roof = [(0.0, 42.7), (6.0, 42.7), (6.45, 43.3), (5.9, 44.2), (4.6, 45.5), (2.6, 47.1), (0.0, 47.8)]
    L["piece"](p, "Primary", L["lathe"](roof, n=20), crease=50)
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 47.4), (1.3, 47.4), (1.3, 48.4), (0.9, 48.95), (0.0, 49.0)], n=12),
               crease=45)
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 48.6), (0.78, 48.6), (0.62, 58.9), (0.0, 58.9)], n=8), crease=40)
    # Big wind cups spinning round the mast
    L["piece"](p, "Primary", L["ball"]((0.0, 0.0, 53.4), 1.0, seg=2), crease=60, collide=False)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        out = [math.cos(a), math.sin(a), 0.0]
        tip = [3.3 * out[0], 3.3 * out[1], 53.4]
        L["piece"](p, "Secondary", L["tube"]([[0.0, 0.0, 53.4], tip], 0.34, n=6, caps="flat"), crease=40, collide=False)
        L["piece"](p, "Color_FFFFFF", L["move"](L["scale"](ST["align"](cup(), [-out[1], out[0], 0.0]), 1.45), tip),
                   crease=50, collide=False)
    # The weather vane: a fat arrow with a cloud-puff tail, and a ball on top
    arrow = L["round_poly"]([[-2.6, -0.42], [1.7, -0.42], [1.7, -1.4], [4.0, 0.0], [1.7, 1.4], [1.7, 0.42], [-2.6, 0.42]],
                            0.2, seg=1)
    L["piece"](p, "Primary", L["move"](L["extrude"](arrow, 0.55, bevel=0.17, seg=1), [0.0, 0.0, 57.6]), crease=40,
               collide=False)
    for x, z, r in ((-3.3, 57.9, 1.3), (-2.45, 57.0, 0.95)):
        L["piece"](p, "Color_FFFFFF", L["ball"]((x, 0.0, z), [r, 0.55, r], seg=2), crease=60, collide=False)
    L["piece"](p, "Secondary", L["ball"]((0.0, 0.0, 59.3), 0.85, seg=2), crease=60, collide=False)
    # Radar dish on balcony 1 at the front right, on a stubby post, facing out and up
    a = math.radians(-50)
    base = [8.2 * math.cos(a), 8.2 * math.sin(a), deck]
    L["piece"](p, "Secondary", L["lathe"]([(0.0, deck - 0.1), (0.75, deck - 0.1), (0.55, deck + 1.7), (0.0, deck + 1.7)],
                                         n=10, center=(base[0], base[1], 0.0)), crease=40)
    dish = L["lathe"]([(0.0, 0.0), (1.7, 0.25), (3.1, 1.05), (3.4, 1.6), (3.0, 1.55), (1.6, 0.72), (0.0, 0.52)], n=16)
    feed = L["tube"]([[0.0, 0.0, 0.4], [0.0, 0.0, 2.4]], 0.26, n=6, caps="flat")
    aim = v_norm([0.42, -0.72, 0.55])
    top = [base[0], base[1], deck + 2.7]
    L["piece"](p, BODY, L["move"](ST["align"](dish, aim), top), crease=50, collide=False)
    L["piece"](p, "Secondary", L["move"](ST["align"](feed, aim), top), crease=40, collide=False)
    L["piece"](p, lamp, L["ball"](v_add(top, v_mul(aim, 2.6)), 0.55, seg=2), crease=60)
    # Arched door with a frame, glowing portholes up the trunk
    frame = L["extrude"](ST["arch_poly"](4.6, 6.4, seg=5), 0.7, bevel=0.22, seg=1)
    L["piece"](p, "Primary", ST["on_wall"](frame, 8.15, 0, 1.3, out=-0.05), crease=40)
    door = L["extrude"](ST["arch_poly"](3.3, 5.5, seg=5), 0.7, bevel=0.2, seg=1)
    L["piece"](p, "Secondary", ST["on_wall"](door, 8.15, 0, 1.6, out=0.2), crease=40)
    bolt = L["scale"](L["extrude"](L["bolt_poly"](7.6), 0.8, bevel=0.25, seg=1), [1.35, 1.0, 1.0])
    L["piece"](p, "Primary", ST["on_wall"](bolt, 7.5, 0, 12.9, out=0.05), crease=40, collide=False)
    window(p, "Primary", lamp, 7.75, -72, 8.5, r=1.2)
    window(p, "Primary", lamp, 5.95, 0, 26.6, r=1.15)
    return p


result = {"built": [L["report"](weather_tower())]}

# ===== chunk 3/9: StationBooth - the open-front station kiosk (+ the building shell helper) =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"
BODY = "Color_EEF0FF"


def shell(p, w, d, h, trim):
    """A toy building's open-front shell: a rounded floor slab (trim), back and side walls and a fat
    round column at each corner (body). Returns the outer faces' x and the back wall's front y."""
    L["piece"](p, trim, L["rounded_box"]([0.0, 0.0, 0.2], [w, d, 1.0], 0.45, seg=1), crease=50)
    xs, yb = w / 2.0 - 1.1, d / 2.0 - 1.6
    L["piece"](p, BODY, L["rounded_box"]([0.0, d / 2.0 - 1.3, (0.6 + h) / 2.0], [w - 2.6, 1.6, h - 0.6], 0.5, seg=1),
               crease=50)
    for sx in (-1.0, 1.0):
        L["piece"](p, BODY, L["rounded_box"]([sx * xs, 0.4, (0.6 + h) / 2.0], [1.6, d - 3.6, h - 0.6], 0.5, seg=1),
                   crease=50)
    col = [(0.0, 0.6), (1.5, 0.6), (1.5, 1.45), (1.22, 1.85), (1.22, h - 0.9), (1.5, h - 0.45), (1.5, h), (0.0, h)]
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            L["piece"](p, BODY, L["lathe"](col, n=10, center=(sx * xs, sy * yb, 0.0), phase=math.pi / 10), crease=50)
    return xs + 0.8, d / 2.0 - 2.1


def porthole(p, frame, glass, c, normal, r=1.1):
    """A round window facing `normal` centred on point c: a fat frame ring round a glowing pane."""
    ring = ST["torus"]((0.0, 0.0, 0.0), r, 0.34, n=10, m=4, tall=0.3)
    pane = L["extrude"](ST["circle_poly"](r + 0.05, 12), 0.5)
    pane = L["rotate"](pane, "x", -90)
    L["piece"](p, frame, L["move"](ST["align"](ring, normal), c), crease=50, collide=False)
    L["piece"](p, glass, L["move"](ST["align"](pane, normal), L["v_add"](c, L["v_mul"](normal, -0.12))), crease=40)


def awning(p, paints, x0, x1, y, z, drop=2.0, tilt=50.0, count=6):
    """A striped shop awning with scalloped ends, hanging forward from (y, z) across x0..x1."""
    w = (x1 - x0) / count
    r = w / 2.0
    poly = [[r, 0.0], [-r, 0.0], [-r, -drop]]
    for k in range(1, 6):
        a = math.pi + math.pi * k / 6
        poly.append([r * math.cos(a), -drop + 0.8 * r * math.sin(a)])
    poly.append([r, -drop])
    for i in range(count):
        m = L["extrude"](poly, 0.36, bevel=0.12, seg=1)
        m = L["rotate"](m, "x", -tilt)
        L["piece"](p, paints[i % len(paints)], L["move"](m, [x0 + w * (i + 0.5), y, z]), crease=40, collide=False)


def station_booth():
    p = L["new_prop"]("StationBooth", 30, 180, {"Primary": "5CC8FF", "Secondary": "3F8FD6"}, solid=True, category=CAT)
    side_x, back_y = shell(p, 20.0, 14.0, 15.0, "Secondary")
    # The fascia over the opening, carrying the flat sign panel (front face at y = -7.15, centre 13 up)
    L["piece"](p, BODY, L["rounded_box"]([0.0, -5.55, 13.0], [19.4, 1.9, 4.6], 0.55, seg=1), crease=50)
    panel = [[-7.2, 10.9], [7.2, 10.9], [7.2, 15.1], [-7.2, 15.1]]
    L["piece"](p, "Secondary", ST["slab"](panel, 0.6, 0.18, 0.7, seg=1, y=-6.85), crease=40)
    # A pillowy roof with a raised top tier and a round knob
    L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.0, 15.8], [21.6, 15.6, 1.7], 0.75, seg=2), crease=50)
    L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.6, 16.9], [15.0, 10.4, 1.2], 0.5, seg=1), crease=50)
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 17.3), (1.5, 17.3), (1.45, 17.8), (0.9, 18.4), (0.0, 18.55)], n=12,
                                         center=(0.0, 0.6, 0.0)), crease=50)
    # Striped awning under the sign, a counter in the opening
    awning(p, ["Primary", "Color_FFFFFF"], -8.4, 8.4, -6.55, 10.75)
    L["piece"](p, "Secondary", L["rounded_box"]([0.0, -4.2, 2.4], [12.0, 2.2, 3.4], 0.5, seg=1), crease=50)
    L["piece"](p, "Color_FFFFFF", L["rounded_box"]([0.0, -4.25, 4.35], [12.8, 2.8, 0.6], 0.25, seg=1), crease=50)
    # Glowing round windows on both sides and two lamps on the back wall inside
    for sx in (-1.0, 1.0):
        porthole(p, "Secondary", "Neon_FFF3B0", [sx * (side_x + 0.05), 0.4, 7.6], [sx, 0.0, 0.0], r=1.5)
        porthole(p, "Secondary", "Neon_FFF3B0", [sx * 4.4, back_y, 6.9], [0.0, -1.0, 0.0], r=1.15)
    return p


result = {"built": [L["report"](station_booth())]}
ST["shell"], ST["porthole"], ST["awning"] = shell, porthole, awning

# ===== chunk 4/9: WeatherLab - the sell station's lab with an observatory dome and a radar dish =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"
BODY = "Color_EEF0FF"


def weather_lab():
    p = L["new_prop"]("WeatherLab", 58, 180, {"Primary": "FFC93C", "Secondary": "3F8FD6"}, solid=True, category=CAT)
    lamp = "Neon_9EE8FF"
    side_x, back_y = ST["shell"](p, 22.0, 18.0, 12.4, "Secondary")
    L["piece"](p, BODY, L["rounded_box"]([0.0, -7.55, 11.3], [21.4, 1.9, 2.7], 0.55, seg=1), crease=50)
    L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.0, 13.2], [23.4, 19.4, 1.7], 0.75, seg=2), crease=50)
    # The rooftop sign plate at the front edge (front face at y = -9.2, centre 15.85 up)
    plate = [[-8.2, 13.75], [8.2, 13.75], [8.2, 17.95], [-8.2, 17.95]]
    L["piece"](p, "Secondary", ST["slab"](plate, 0.8, 0.22, 0.8, seg=1, y=-8.8), crease=40)
    # Observatory: a drum, a glass dome and a fat telescope poking out of it
    dc = (-4.3, 3.2)
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 13.9), (5.25, 13.9), (5.4, 14.6), (5.15, 15.25), (0.0, 15.25)], n=18,
                                         center=(dc[0], dc[1], 0.0)), crease=50)
    dome = [(0.0, 15.0), (4.85, 15.0), (4.65, 16.6), (4.0, 18.0), (2.85, 19.1), (1.4, 19.75), (0.0, 19.9)]
    L["piece"](p, "Glass_9EE8FF", L["lathe"](dome, n=18, center=(dc[0], dc[1], 0.0)), crease=50)
    aim = L["v_norm"]([0.5, -0.42, 0.76])
    foot = [dc[0], dc[1], 16.0]
    L["piece"](p, "Secondary", L["ball"](foot, 1.05, seg=2), crease=60, collide=False)
    scope = L["lathe"]([(0.0, -0.8), (0.72, -0.8), (0.8, 2.4), (0.92, 5.1), (0.0, 5.1)], n=10)
    L["piece"](p, "Primary", L["move"](ST["align"](scope, aim), foot), crease=40, collide=False)
    ring = ST["band"](0.85, 1.22, 4.6, 5.5, n=10, steps=2, fat=0.7)
    L["piece"](p, "Secondary", L["move"](ST["align"](ring, aim), foot), crease=50, collide=False)
    # Radar dish on the roof's right corner
    base = [6.9, 3.6, 14.0]
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 13.9), (1.2, 13.9), (1.15, 14.5), (0.55, 14.9), (0.5, 16.4),
                                          (0.0, 16.4)], n=10, center=(base[0], base[1], 0.0)), crease=45)
    dish = L["lathe"]([(0.0, 0.0), (1.5, 0.22), (2.75, 0.95), (3.0, 1.42), (2.65, 1.38), (1.4, 0.66), (0.0, 0.48)], n=16)
    feed = L["tube"]([[0.0, 0.0, 0.4], [0.0, 0.0, 2.2]], 0.24, n=6, caps="flat")
    dish_aim = L["v_norm"]([0.3, -0.62, 0.72])
    top = [base[0], base[1], 17.0]
    L["piece"](p, BODY, L["move"](ST["align"](dish, dish_aim), top), crease=50, collide=False)
    L["piece"](p, "Secondary", L["move"](ST["align"](feed, dish_aim), top), crease=40, collide=False)
    L["piece"](p, lamp, L["ball"](L["v_add"](top, L["v_mul"](dish_aim, 2.4)), 0.5, seg=2), crease=60)
    # Inside: a lab console with glowing buttons and a round radar screen on the back wall
    L["piece"](p, "Secondary", L["rounded_box"]([0.0, back_y - 1.3, 2.4], [12.0, 2.6, 3.6], 0.5, seg=1), crease=50)
    for x in (-3.6, -1.2, 1.2, 3.6):
        L["piece"](p, lamp, L["ball"]((x, back_y - 1.6, 4.25), [0.55, 0.55, 0.3], seg=1), crease=60)
    L["piece"](p, "Primary", L["move"](ST["align"](ST["torus"]((0.0, 0.0, 0.0), 2.6, 0.42, n=16, m=4, tall=0.36),
                                                     [0.0, -1.0, 0.0]), [0.0, back_y, 8.2]), crease=50, collide=False)
    screen = L["rotate"](L["extrude"](ST["circle_poly"](2.65, 16), 0.5), "x", -90)
    L["piece"](p, lamp, L["move"](ST["align"](screen, [0.0, -1.0, 0.0]), [0.0, back_y + 0.1, 8.2]), crease=40)
    for sx in (-1.0, 1.0):
        ST["porthole"](p, "Secondary", "Neon_FFF3B0", [sx * (side_x + 0.05), 1.0, 7.4], [sx, 0.0, 0.0], r=1.6)
    return p


result = {"built": [L["report"](weather_lab())]}
