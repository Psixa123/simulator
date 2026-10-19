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

# ===== chunk 1/9: helpers shared by the structures =====
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
        m = L["extrude"](poly, 0.55, bevel=0.18, seg=1)
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

# ===== chunk 5/9: RebirthShrine and ForecastTower =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"
BODY = "Color_EEF0FF"


def rebirth_shrine():
    """Round platform, four pillars holding glowing braziers and a swirl portal ring in the middle.
    MapService floats a spinning crystal in the ring (10.5 up) and puts the prompt in the centre."""
    p = L["new_prop"]("RebirthShrine", 86, 180, {"Primary": "E2D8FF", "Secondary": "8A6CF0"}, solid=True, category=CAT)
    glow = "Neon_B58CFF"
    # Two-tier platform: a pale stone footing and a purple floor with a glowing swirl inlaid in it
    L["piece"](p, "Primary", L["puck"]((0.0, 0.0, -0.4), 9.0, 1.55, 0.6, n=22), crease=45)
    L["piece"](p, "Secondary", L["puck"]((0.0, 0.0, 0.85), 7.8, 1.05, 0.42, n=22), crease=45)
    for k in range(3):
        a0 = 2 * math.pi * k / 3 + 0.35
        path, radii = [], []
        for i in range(8):
            t = i / 7.0
            r = 6.5 - 3.7 * t
            path.append([r * math.cos(a0 + 2.0 * t), r * math.sin(a0 + 2.0 * t), 1.9])
            radii.append(0.6 - 0.28 * t)
        arm = L["tube"](path, radii, n=6, caps="round", cap_seg=1)
        L["piece"](p, glow, L["warp"](arm, lambda q: [q[0], q[1], 1.9 + (q[2] - 1.9) * 0.35]), crease=60)
    # Four pillars on the diagonals: purple foot, pale shaft and capital, a purple brazier with a glowing orb
    foot = [(0.0, 1.7), (1.5, 1.7), (1.5, 2.45), (1.2, 2.95), (0.0, 2.95)]
    shaft = [(0.0, 2.7), (1.05, 2.7), (0.97, 10.8), (1.18, 11.3), (1.42, 11.85), (1.42, 12.35), (0.0, 12.35)]
    cup = [(0.0, 12.2), (0.75, 12.2), (1.3, 12.75), (1.42, 13.35), (1.2, 13.6), (0.0, 13.45)]
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c = (6.85 * math.cos(a), 6.85 * math.sin(a), 0.0)
        L["piece"](p, "Secondary", L["lathe"](foot, n=10, center=c), crease=50)
        L["piece"](p, "Primary", L["lathe"](shaft, n=10, center=c), crease=50)
        L["piece"](p, "Secondary", L["lathe"](cup, n=10, center=c), crease=50)
        L["piece"](p, glow, L["ball"]((c[0], c[1], 14.15), 0.95, seg=2), crease=60)
    # The pedestal and its cradle holding the portal ring, the ring and its glowing inner rim
    ped = [(0.0, 1.8), (2.35, 1.8), (2.35, 2.35), (1.75, 2.95), (1.4, 3.6), (1.5, 4.2), (2.05, 4.75), (2.15, 5.15),
           (0.0, 5.15)]
    L["piece"](p, "Primary", L["lathe"](ped, n=12), crease=50)
    zc = 10.5
    L["piece"](p, "Secondary", ST["torus"]((0.0, 0.0, zc), 5.05, 1.0, n=24, m=8, axis="y", tall=1.2), crease=50)
    L["piece"](p, glow, ST["torus"]((0.0, 0.0, zc), 4.0, 0.36, n=24, m=5, axis="y", tall=0.5), crease=60)
    # A fat purple sparkle on a stone knob on top
    L["piece"](p, "Primary", L["lathe"]([(0.0, 15.3), (1.2, 15.3), (1.3, 16.0), (1.0, 16.6), (0.0, 16.7)], n=10),
               crease=50, collide=False)
    star = L["extrude"](L["round_poly"](L["star_poly"](4, 1.9, 0.78), 0.22, seg=1), 1.0, bevel=0.3, seg=1)
    L["piece"](p, "Secondary", L["move"](star, [0.0, 0.0, 18.2]), crease=40, collide=False)
    return p


result = {"built": [L["report"](rebirth_shrine())]}


def forecast_tower():
    """A screen tower on two legs: the flat 12 x 8 screen area (front at y = -3, centre 14 up, where MapService
    puts its SurfaceGui) sits inside a fat bezel; speakers on the sides, a cloud and an antenna on the roof."""
    p = L["new_prop"]("ForecastTower", 110, 180, {"Primary": "5CC8FF", "Secondary": "3F8FD6"}, solid=True, category=CAT)
    L["piece"](p, "Secondary", L["rounded_box"]([0.0, 0.3, 0.4], [12.6, 5.4, 1.6], 0.65, seg=1), crease=50)
    leg = [(0.0, 1.0), (1.45, 1.0), (1.45, 1.55), (1.12, 2.1), (1.0, 5.0), (0.98, 8.9), (0.0, 8.9)]
    for sx in (-1.0, 1.0):
        L["piece"](p, "Primary", L["lathe"](leg, n=12, center=(sx * 4.2, 0.3, 0.0)), crease=50)
        L["piece"](p, "Secondary", ST["band"](0.95, 1.3, 5.6, 6.5, n=12, center=(sx * 4.2, 0.3, 0.0), steps=2, fat=0.7),
                   crease=50)
    # The screen housing (front face at y = -2.82) and the bezel round the screen area
    L["piece"](p, BODY, L["rounded_box"]([0.0, 0.18, 14.0], [14.2, 6.0, 11.4], 1.05, seg=2), crease=50)
    L["piece"](p, "Primary", ST["sweep"](ST["rrect_path"](12.95, 8.95, 0.9, seg=3, center=(0.0, -2.86, 14.0)), 0.48,
                                         n=8), crease=50, collide=False)
    # Round speakers on both sides
    for sx in (-1.0, 1.0):
        spk = ST["align"](L["puck"]((0.0, 0.0, 0.0), 1.75, 0.7, 0.3, n=14), [sx, 0.0, 0.0])
        L["piece"](p, "Secondary", L["move"](spk, [sx * 6.95, 0.18, 14.0]), crease=45, collide=False)
        L["piece"](p, "Primary", L["ball"]((sx * 7.5, 0.18, 14.0), [0.42, 0.75, 0.75], seg=2), crease=60, collide=False)
    # A pillowy roof, a white cloud resting on it and a little antenna with a ball
    L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.18, 20.1], [15.2, 7.0, 1.4], 0.66, seg=2), crease=50)
    for c, r in (((-2.5, 0.3, 21.25), [1.9, 1.7, 1.45]), ((0.1, 0.2, 21.6), [2.3, 2.0, 1.75]),
                 ((2.5, 0.4, 21.2), [1.6, 1.5, 1.3])):
        L["piece"](p, "Color_FFFFFF", L["ball"](c, r, seg=4), crease=60, collide=False)
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 20.6), (0.42, 20.6), (0.32, 22.3), (0.0, 22.3)], n=8,
                                         center=(5.5, 0.9, 0.0)), crease=40, collide=False)
    L["piece"](p, "Primary", L["ball"]((5.5, 0.9, 22.55), 0.68, seg=2), crease=60, collide=False)
    return p


result["built"].append(L["report"](forecast_tower()))

# ===== chunk 6/9: EggIncubator and SellMachine =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"


def egg_incubator():
    """A round pedestal with a cushion under a tall glass dome. MapService floats the egg inside (about 6 up)."""
    p = L["new_prop"]("EggIncubator", 130, 180, {"Primary": "EEF0FF", "Secondary": "5CC8FF"}, solid=True, category=CAT)
    base = [(0.0, -0.3), (5.55, -0.3), (5.8, 0.1), (5.7, 0.6), (5.05, 1.1), (4.7, 1.6), (4.8, 2.15), (5.3, 2.55),
            (5.45, 2.95), (5.3, 3.2), (0.0, 3.2)]
    L["piece"](p, "Primary", L["lathe"](base, n=24), crease=50)
    # A fat rolled band round the waist, four round feet and the collar the dome sits in
    L["piece"](p, "Secondary", ST["torus"]((0.0, 0.0, 1.6), 4.75, 0.45, n=24, m=6), crease=60)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        L["piece"](p, "Secondary", L["ball"]((5.15 * math.cos(a), 5.15 * math.sin(a), 0.3), [1.15, 1.15, 0.85], seg=3),
                   crease=60)
    L["piece"](p, "Secondary", L["lathe"]([(4.3, 3.0), (5.0, 3.0), (5.2, 3.4), (5.0, 3.85), (4.3, 3.85)], n=24),
               crease=50)
    # A round dial on the front of the waist band
    dial = ST["align"](L["puck"]((0.0, 0.0, 0.0), 1.05, 0.55, 0.22, n=14), [0.0, -1.0, 0.0])
    L["piece"](p, "Primary", L["move"](dial, [0.0, -5.0, 1.6]), crease=45, collide=False)
    L["piece"](p, "Secondary", L["ball"]((0.0, -5.5, 1.6), [0.5, 0.3, 0.5], seg=2), crease=60, collide=False)
    # The cushion the egg rests on, seen through the glass
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 3.1), (3.5, 3.1), (3.8, 3.45), (3.55, 3.8), (2.2, 3.95), (0.0, 3.8)],
                                         n=20), crease=50, collide=False)
    # The glass dome: a short drum and a round top
    dome = [(0.0, 3.5), (4.5, 3.5), (4.5, 6.9)]
    for k in range(1, 7):
        a = math.pi / 2 * k / 6
        dome.append((4.5 * math.cos(a), 6.9 + 4.5 * math.sin(a)))
    L["piece"](p, "Glass_DFF6FF", L["lathe"](dome, n=24), crease=50)
    # Two arched ribs over the glass, crossing under the cap
    for deg in (45, 135):
        c, sn = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        rib = [[4.62 * c, 4.62 * sn, 3.7]]
        for k in range(13):
            phi = math.pi * k / 12
            rib.append([4.62 * math.cos(phi) * c, 4.62 * math.cos(phi) * sn, 6.9 + 4.62 * math.sin(phi)])
        rib.append([-4.62 * c, -4.62 * sn, 3.7])
        L["piece"](p, "Secondary", L["tube"](rib, 0.36, n=6, caps="flat"), crease=50, collide=False)
    # A cap and knob on top
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 11.0), (1.55, 11.0), (1.7, 11.4), (1.35, 11.8), (0.0, 11.85)], n=16),
               crease=50, collide=False)
    L["piece"](p, "Primary", L["ball"]((0.0, 0.0, 12.05), 0.6, seg=3), crease=60, collide=False)
    return p


result = {"built": [L["report"](egg_incubator())]}


def sell_machine():
    """A chunky storm-jar machine: a puffy body with a glowing bolt and a coin chute, a glass jar with a little
    storm cloud inside, a fat lid."""
    p = L["new_prop"]("SellMachine", 148, 180, {"Primary": "7BE36A", "Secondary": "33B24A"}, solid=True, category=CAT)
    L["piece"](p, "Secondary", L["rounded_box"]([0.0, 0.0, 0.4], [10.0, 8.0, 1.6], 0.65, seg=2), crease=50)
    L["piece"](p, "Primary", L["rounded_box"]([0.0, 0.1, 3.55], [8.6, 6.6, 5.1], 1.45, seg=2), crease=50)
    # A big glowing bolt on the front, the coin slot and the chute tray with a coin in it
    bolt = L["extrude"](L["round_poly"](L["bolt_poly"](4.0), 0.12, seg=1), 0.6, bevel=0.2, seg=1)
    L["piece"](p, "Neon_FFE15A", L["move"](bolt, [-1.6, -3.2, 3.65]), crease=40)
    L["piece"](p, "Secondary", L["rounded_box"]([2.15, -3.25, 4.55], [2.4, 0.7, 1.5], 0.32, seg=1), crease=50,
               collide=False)
    L["piece"](p, "Color_233066", L["rounded_box"]([2.15, -3.55, 4.55], [1.5, 0.3, 0.38], 0.12, seg=1), crease=50,
               collide=False)
    L["piece"](p, "Secondary", L["rounded_box"]([2.15, -3.45, 2.15], [2.9, 1.5, 1.2], 0.45, seg=1), crease=50,
               collide=False)
    coin = ST["align"](L["puck"]((0.0, 0.0, -0.22), 0.85, 0.44, 0.18, n=14), [0.0, -1.0, 0.25])
    L["piece"](p, "Color_FFC93C", L["move"](coin, [2.15, -3.75, 3.05]), crease=45, collide=False)
    # The jar: a collar, the glass, a little storm cloud with a bolt inside, a fat lid and a glowing knob
    L["piece"](p, "Secondary", L["lathe"]([(0.0, 5.8), (3.05, 5.8), (3.35, 6.2), (3.35, 6.65), (3.05, 7.0),
                                          (0.0, 7.0)], n=20), crease=50)
    jar = [(0.0, 6.8), (2.6, 6.8), (2.72, 7.3), (2.72, 10.55), (2.55, 11.0), (0.0, 11.0)]
    L["piece"](p, "Glass_54E0FF", L["lathe"](jar, n=20), crease=50)
    for c, r in (((-0.95, 0.0, 9.65), [1.0, 0.95, 0.85]), ((0.35, 0.1, 9.9), [1.2, 1.05, 1.0]),
                 ((1.35, 0.0, 9.55), [0.8, 0.75, 0.7])):
        L["piece"](p, "Color_FFFFFF", L["ball"](c, r, seg=3), crease=60, collide=False)
    mini = L["extrude"](L["round_poly"](L["bolt_poly"](2.3), 0.08, seg=1), 0.45, bevel=0.14, seg=1)
    L["piece"](p, "Neon_FFE15A", L["move"](mini, [0.15, -0.3, 8.3]), crease=40)
    lid = [(0.0, 10.8), (2.85, 10.8), (3.15, 11.1), (3.15, 11.5), (2.8, 11.85), (1.9, 12.15), (0.9, 12.3), (0.0, 12.32)]
    L["piece"](p, "Secondary", L["lathe"](lid, n=20), crease=50)
    L["piece"](p, "Neon_FFE15A", L["ball"]((0.0, 0.0, 12.5), [0.66, 0.66, 0.5], seg=3), crease=60)
    return p


result["built"].append(L["report"](sell_machine()))

# ===== chunk 7/9: ZoneGate and LeaderboardFrame =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"


def gate_outline(w, zb, a, apex, top, crown, steps=12):
    """Front outline (x, z) of the gate's arch panel, counter-clockwise: from pillar centre to pillar centre
    (x = -w .. w), a gently curved top (top at the ends, top + crown in the middle) and a round arch cut
    out underneath, springing from (+-a, zb) up to `apex`."""
    pts = [[w, zb], [w, top]]
    for k in range(1, steps):
        x = w - 2.0 * w * k / steps
        pts.append([x, top + crown * (1.0 - (x / w) ** 2)])
    pts += [[-w, top], [-w, zb]]
    for k in range(steps + 1):
        t = math.pi * k / steps
        pts.append([-a * math.cos(t), zb + (apex - zb) * math.sin(t)])
    return pts


def zone_gate():
    """A big rounded arch over the 16-stud path: two fat pillars at x = +-16 with domed caps and a curved arch
    panel between them. MapService hangs its sign (25 x 5.4, centre 24 up) on both faces of the panel."""
    p = L["new_prop"]("ZoneGate", 0, 230, {"Primary": "EEF0FF", "Secondary": "5CC8FF", "Tertiary": "3F8FD6"}, solid=True,
                      category=CAT)
    w, zb, a, apex, top, crown = 16.0, 15.0, 11.9, 20.3, 27.75, 0.9
    L["piece"](p, "Secondary", L["extrude"](gate_outline(w, zb, a, apex, top, crown), 8.4, bevel=0.9, seg=2), crease=50)
    # Rounded trims along the panel's top and round the arch
    ridge = [[x, 0.0, top + crown * (1.0 - (x / w) ** 2) - 0.1] for x in [w - 2.0 * w * k / 12 for k in range(13)]]
    L["piece"](p, "Tertiary", ST["sweep"](ridge, [0.62, 4.45], n=8, closed=False), crease=50)
    arc = []
    for k in range(13):
        t = math.pi * k / 12
        arc.append([a * math.cos(t) * 1.02, 0.0, zb - 0.6 + (apex - zb + 0.6) * math.sin(t)])
    L["piece"](p, "Tertiary", ST["sweep"](arc, [0.55, 4.45], n=8, closed=False), crease=50)
    shaft = [(0.0, 1.6), (4.72, 1.6), (4.68, 8.0), (4.64, 16.0), (4.6, 28.6), (0.0, 28.6)]
    cap = [(0.0, 28.2), (4.5, 28.2), (5.1, 28.55), (5.4, 29.2), (5.25, 29.85), (4.65, 30.15), (0.0, 30.15)]
    dome = [(0.0, 30.0), (4.6, 30.0), (4.3, 30.8), (3.4, 31.45), (2.1, 31.8), (0.0, 31.9)]
    for sx in (-1.0, 1.0):
        c = (sx * w, 0.0, 0.0)
        L["piece"](p, "Tertiary", L["puck"]((c[0], 0.0, -0.35), 5.6, 2.25, 0.75, n=16), crease=45)
        L["piece"](p, "Primary", L["lathe"](shaft, n=16, center=c), crease=40)
        L["piece"](p, "Tertiary", ST["band"](4.6, 5.2, 7.4, 8.9, n=16, center=c, steps=4, fat=0.6), crease=50)
        L["piece"](p, "Tertiary", L["lathe"](cap, n=16, center=c), crease=50)
        L["piece"](p, "Primary", L["lathe"](dome, n=16, center=c), crease=50)
    # A little white cloud resting on top of the arch
    for c, r in (((-2.6, 0.2, 29.0), [2.3, 2.0, 1.75]), ((0.3, -0.1, 29.6), [2.8, 2.3, 2.2]),
                 ((3.0, 0.3, 28.9), [2.0, 1.8, 1.55])):
        L["piece"](p, "Color_FFFFFF", L["ball"](c, r, seg=4), crease=60, collide=False)
    return p


result = {"built": [L["report"](zone_gate())]}


def leaderboard_frame():
    """A stand for a leaderboard: a board whose flat 16 x 18 screen area (front at y = -1.5, centre 13 up, where
    MapService puts its SurfaceGui) sits in a fat bezel, between two posts, with a crest and a star on top."""
    p = L["new_prop"]("LeaderboardFrame", 36, 230, {"Primary": "FFC93C", "Secondary": "5B6A9E"}, solid=True,
                      category=CAT)
    L["piece"](p, "Secondary", L["rounded_box"]([0.0, 0.0, 0.55], [20.0, 4.6, 2.0], 0.8, seg=2), crease=50)
    post = [(0.0, 1.3), (1.65, 1.3), (1.65, 1.95), (1.35, 2.45), (1.25, 3.0), (1.2, 22.4), (0.0, 22.4)]
    for sx in (-1.0, 1.0):
        c = (sx * 9.55, 0.0, 0.0)
        L["piece"](p, "Primary", L["lathe"](post, n=12, center=c), crease=50)
        L["piece"](p, "Secondary", ST["band"](1.15, 1.5, 21.0, 22.0, n=12, center=c, steps=4, fat=0.6), crease=50)
        L["piece"](p, "Secondary", L["ball"]((c[0], 0.0, 23.25), 1.4, seg=3), crease=60, collide=False)
    L["piece"](p, "Color_EEF0FF", L["rounded_box"]([0.0, 0.0, 13.0], [18.2, 3.0, 20.2], 0.75, seg=2), crease=50)
    L["piece"](p, "Primary", ST["sweep"](ST["rrect_path"](16.95, 18.95, 1.0, seg=3, center=(0.0, -1.55, 13.0)), 0.48,
                                         n=8), crease=50, collide=False)
    # The crest over the board with a big white star
    crest = [[-7.4, 22.1], [7.4, 22.1], [7.4, 23.5], [0.0, 25.4], [-7.4, 23.5]]
    L["piece"](p, "Primary", ST["slab"](crest, 2.6, 0.55, 1.4, seg=2), crease=45)
    star = L["extrude"](L["round_poly"](L["star_poly"](5, 1.75, 0.82), 0.2, seg=1), 0.7, bevel=0.24, seg=1)
    L["piece"](p, "Color_FFFFFF", L["move"](star, [0.0, -1.35, 23.75]), crease=40, collide=False)
    return p


result["built"].append(L["report"](leaderboard_frame()))

# ===== chunk 8/9: CliffSegment and CloudPuff =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"


def ledge(x0, x1, nx, yb, depth, zc, half, seed, e=0.5, m=8, lean=0.0, wobble=0.5, ends=0.0, lobe=0.0, period=8.0):
    """One rock band of a cliff, running along X from x0 to x1: a section with a flat back at y = yb and a
    rounded front `depth` further out (-Y), between heights zc - half and zc + half (superellipse power e).
    The front wobbles by `wobble` studs and bulges into rounded lobes `period` studs apart (`lobe` studs deep),
    lean > 0 pushes its top out further than its bottom, and ends > 0 rounds the ends off over that many studs
    (0 = flat ends, hidden inside the neighbouring segment)."""
    noise = L["lumps"](seed, 0.32)
    rings = []
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        s = 1.0
        if ends > 0:
            edge = min(x - x0, x1 - x) / ends
            s = math.sqrt(max(0.0, 1.0 - max(0.0, 1.0 - edge) ** 2)) * 0.82 + 0.18
        bump = abs(math.cos(math.pi * x / period + 2.0 * noise([x, 7.0, zc]) + seed)) ** 0.7
        d = depth * s + wobble * noise([x, 0.0, zc]) - lobe * (1.0 - bump)
        h = half * (0.6 + 0.4 * s) * (1.0 + 0.08 * noise([x, 3.0, zc]))
        ring = []
        for k in range(m + 1):
            t = math.pi / 2 - math.pi * k / m
            c, sn = max(0.0, math.cos(t)), math.sin(t)
            ce = c ** e
            se = (abs(sn) ** e) * (1.0 if sn >= 0 else -1.0)
            ring.append([x, yb - ce * (d + lean * se), zc + h * se])
        rings.append(ring)
    if ends > 0:
        mid0 = [x0, yb - 0.25 * depth, zc]
        mid1 = [x1, yb - 0.25 * depth, zc]
        rings = [[mid0]] + rings[1:-1] + [[mid1]]
    return ST["loft"](rings)


def cliff_segment():
    """One 40-stud chunk of island edge. Origin on its flat top (z = 0) at the island's boundary; it reaches 18 out
    to the front (-Y, the outside) and hangs down to z = -30 in rock bands that step back toward the island."""
    p = L["new_prop"]("CliffSegment", 80, 230, {"Primary": "6EE05A", "Secondary": "D99A62", "Tertiary": "B8754A"},
                      category=CAT)
    # The grass lip: flat on top, a soft rounded front edge and fat round drips hanging over the rock
    lip = [(0.0, 0.0), (0.6, 0.0), (0.86, -0.06), (0.965, -0.35), (1.0, -0.85), (0.985, -1.4), (0.93, -1.9),
           (0.8, -2.15), (0.55, -2.3), (0.0, -2.3)]
    noise = L["lumps"](40, 0.4)
    rings = []
    for i in range(41):
        x = -20.0 + 40.0 * i / 40
        drip = (0.5 + 0.5 * math.cos(2 * math.pi * x / 6.67 + 0.5)) ** 2.2 * (1.0 + 0.35 * noise([x, 0.0, 0.0]))
        ring = []
        for f, z in lip:
            if f >= 0.8 and z < -1.3:
                z -= 1.7 * drip * (1.0 if f > 0.9 else 0.75)
            ring.append([x, 0.6 - f * 18.8, z])
        rings.append(ring)
    L["piece"](p, "Primary", ST["loft"](rings), crease=55)
    # Chunky rock bands with lobed fronts, alternating the two rock paints, each stepping back toward the island
    bands = [("Secondary", -20.0, 20.0, 24, 17.2, -5.4, 3.8, 3, 0.7, 0.6, 0.0, 1.3),
             ("Tertiary", -20.0, 20.0, 24, 15.0, -12.0, 3.2, 7, 0.6, 0.6, 0.0, 1.4),
             ("Secondary", -19.6, 19.2, 22, 12.4, -17.9, 3.0, 11, 0.6, 0.6, 2.5, 1.4),
             ("Tertiary", -16.4, 15.4, 18, 9.6, -22.9, 2.6, 13, 0.5, 0.5, 6.0, 1.2)]
    for paint, x0, x1, nx, depth, zc, half, seed, lean, wob, ends, lobe in bands:
        L["piece"](p, paint, ledge(x0, x1, nx, 0.4, depth, zc, half, seed, e=0.45, m=8, lean=lean, wobble=wob,
                                   ends=ends, lobe=lobe, period=7.0), crease=55)
    # Round boulders hanging under it all
    for paint, c, r, seed, sg in (("Secondary", (-6.0, -4.4, -25.6), [5.8, 4.4, 4.2], 21, 4),
                                  ("Secondary", (6.4, -3.8, -25.2), [4.8, 4.0, 3.8], 22, 4),
                                  ("Tertiary", (0.4, -2.6, -27.2), [3.3, 2.9, 2.8], 23, 3)):
        lumpy = L["lumps"](seed, 2.2)
        L["piece"](p, paint, L["ball"](c, r, seg=sg, shape=lambda d: 1.0 + 0.07 * lumpy(d)), crease=55)
    return p


result = {"built": [L["report"](cliff_segment())]}


def lobes(balls, seg=6, hide=(), floor=None):
    """A cartoon cloud: one round ball per lobe [x, y, z, rx, ry, rz] (+ its own seg). Faces buried inside another
    lobe (or inside a ball of `hide`, e.g. the lobes of another paint) never show and are left out."""
    every = list(balls) + list(hide)
    verts, faces = [], []
    for i, b in enumerate(balls):
        m = L["ball"](b[:3], b[3:6], b[6] if len(b) > 6 else seg)
        if floor is not None:
            m = ST["floor_at"](m, floor)
        inside = []
        for q in m["v"]:
            inside.append([j for j, o in enumerate(every) if j != i and ((q[0] - o[0]) / o[3]) ** 2 +
                           ((q[1] - o[1]) / o[4]) ** 2 + ((q[2] - o[2]) / o[5]) ** 2 < 0.98])
        index = {}
        for f in m["f"]:
            shared = inside[f[0]]
            for k in f[1:]:
                shared = [j for j in shared if j in inside[k]]
            if shared:
                continue
            for k in f:
                if k not in index:
                    index[k] = len(verts)
                    verts.append(m["v"][k])
            faces.append([index[k] for k in f])
    return {"v": verts, "f": faces}


def cloud_puff():
    """A big round cumulus for the cloud sea: a tall crown of white lobes over a flatter tinted belly."""
    p = L["new_prop"]("CloudPuff", 126, 230, {"Secondary": "DCE6FA"}, category=CAT)
    tops = [[0.5, 0.3, 6.6, 7.4, 6.6, 5.6, 7], [-7.6, 1.2, 5.2, 5.6, 5.2, 4.4, 6], [8.0, -0.6, 5.0, 5.4, 5.0, 4.2, 6],
            [-12.4, 0.2, 3.4, 3.4, 3.6, 2.8, 5], [12.6, 0.8, 3.3, 3.2, 3.4, 2.7, 5], [-2.6, -6.0, 4.4, 4.8, 3.6, 3.4, 5],
            [4.2, -5.4, 4.0, 4.4, 3.4, 3.1, 5], [-1.8, 6.6, 4.6, 5.0, 3.6, 3.4, 5], [5.6, 5.4, 4.2, 4.0, 3.4, 3.0, 5],
            [-3.6, -1.6, 10.2, 3.6, 3.4, 2.6, 5], [3.4, 1.0, 10.6, 3.0, 2.9, 2.3, 5]]
    belly = [[-6.6, 0.4, 1.9, 6.4, 6.4, 2.1], [2.0, 0.2, 1.8, 7.6, 7.6, 2.2], [9.4, 0.4, 1.8, 5.2, 5.4, 2.0],
             [-12.6, 0.4, 1.6, 3.4, 3.6, 1.7], [13.2, 0.8, 1.5, 3.2, 3.4, 1.6]]
    L["piece"](p, "Color_FFFFFF", lobes(tops, seg=5, hide=belly), crease=60)
    L["piece"](p, "Secondary", lobes(belly, seg=5, hide=tops, floor=-0.2), crease=60)
    return p


result["built"].append(L["report"](cloud_puff()))

# ===== chunk 9/9: Bench, SignPost and Planter =====
L = session_state["L"]
ST = session_state["ST"]
CAT = "structures"


def bent(points, r=0.6, steps=3):
    """A path through `points` [(y, z), ...] at x = 0 with each inner corner rounded off by an arc of about r."""
    out = [[0.0, points[0][0], points[0][1]]]
    for i in range(1, len(points) - 1):
        p0, p1, p2 = points[i - 1], points[i], points[i + 1]
        d0 = [p0[0] - p1[0], p0[1] - p1[1]]
        d2 = [p2[0] - p1[0], p2[1] - p1[1]]
        l0, l2 = math.hypot(d0[0], d0[1]), math.hypot(d2[0], d2[1])
        t = min(r, 0.45 * l0, 0.45 * l2)
        a = [p1[0] + d0[0] / l0 * t, p1[1] + d0[1] / l0 * t]
        b = [p1[0] + d2[0] / l2 * t, p1[1] + d2[1] / l2 * t]
        for k in range(steps + 1):
            u = k / steps
            out.append([0.0, (1 - u) ** 2 * a[0] + 2 * u * (1 - u) * p1[0] + u * u * b[0],
                        (1 - u) ** 2 * a[1] + 2 * u * (1 - u) * p1[1] + u * u * b[1]])
    out.append([0.0, points[-1][0], points[-1][1]])
    return out


def bench():
    """A chunky park bench: two fat seat slats and two back slats on bent round legs."""
    p = L["new_prop"]("Bench", 150, 230, {"Primary": "FFB15C", "Secondary": "5B6A9E"}, solid=True, category=CAT)
    front = bent([(-0.72, -0.15), (-0.72, 1.3), (0.85, 1.3)], r=0.45)
    back = bent([(0.85, -0.15), (0.85, 1.3), (1.22, 3.2)], r=0.5)
    for sx in (-1.0, 1.0):
        for path in (front, back):
            leg = L["move"](L["tube"](path, 0.3, n=8, caps="round", cap_seg=2), [sx * 2.2, 0.0, 0.0])
            L["piece"](p, "Secondary", leg, crease=50)
    for y in (-0.5, 0.35):
        L["piece"](p, "Primary", L["rounded_box"]([0.0, y, 1.78], [6.0, 0.8, 0.52], 0.23, seg=1), crease=45)
    for z in (2.3, 2.95):
        slat = L["rounded_box"]([0.0, 0.0, 0.0], [6.0, 0.44, 0.56], 0.2, seg=1)
        L["piece"](p, "Primary", L["move"](L["rotate"](slat, "x", -11), [0.0, 0.83 + (z - 1.3) * 0.2, z]), crease=45)
    return p


result = {"built": [L["report"](bench())]}


def sign_post():
    """A sign board on two round posts: a white board (front at y = -0.35, 5.4 x 2.8 centred 6 up, where MapService
    puts its sign) in a fat trim frame, the posts behind it with ball tops."""
    p = L["new_prop"]("SignPost", 162, 230, {"Primary": "A8724C", "Secondary": "5CC8FF"}, category=CAT)
    post = [(0.0, -0.3), (0.7, -0.3), (0.7, 0.15), (0.55, 0.5), (0.48, 0.9), (0.46, 7.4), (0.0, 7.4)]
    for sx in (-1.0, 1.0):
        L["piece"](p, "Primary", L["lathe"](post, n=10, center=(sx * 2.2, 0.42, 0.0)), crease=50)
        L["piece"](p, "Primary", L["ball"]((sx * 2.2, 0.42, 7.7), 0.64, seg=3), crease=60)
    L["piece"](p, "Color_FFFFFF", L["rounded_box"]([0.0, 0.0, 6.0], [5.5, 0.7, 2.9], 0.24, seg=1), crease=45)
    L["piece"](p, "Secondary", ST["sweep"](ST["rrect_path"](5.85, 3.25, 0.62, seg=3, center=(0.0, -0.02, 6.0)),
                                           [0.32, 0.5], n=8), crease=50)
    return p


result["built"].append(L["report"](sign_post()))


def planter():
    """A round planter: a foot ring, a gently bellied body and a fat rolled rim, soil inside (a tree goes in it,
    2 studs up)."""
    p = L["new_prop"]("Planter", 176, 230, {"Primary": "FFB15C"}, solid=True, category=CAT)
    prof = [(0.0, -0.3), (4.0, -0.3), (4.22, -0.05), (4.22, 0.25), (4.05, 0.47), (4.14, 0.78), (4.3, 1.15),
            (4.38, 1.4), (4.6, 1.5), (4.78, 1.75), (4.75, 2.02), (4.52, 2.22), (4.15, 2.24), (3.9, 2.06), (3.82, 1.76),
            (0.0, 1.76)]
    L["piece"](p, "Primary", L["lathe"](prof, n=36), crease=50)
    soil = [(0.0, 1.55), (3.82, 1.55), (3.8, 1.82), (2.8, 1.92), (0.0, 1.96)]
    L["piece"](p, "Color_6B4A35", L["lathe"](soil, n=24), crease=50, collide=False)
    return p


result["built"].append(L["report"](planter()))
