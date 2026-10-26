# Storm Catcher Simulator - prop kit, category "gear" (tools/world/sketchup/gear.py)
#
# The gear every storm catcher carries (src/server/Services/CharacterGear.luau places these with
# WorldProps.Place and welds them to the character): the Storm Vacuum held in the right hand and the
# Storm Tank worn on the back. Send lib.py first (all its chunks), then each "# ===== chunk" block
# below as one build_model call, in order: chunk 1 stores the shared helpers in session_state["GR"].
#
# Units: studs (piece() converts to inches), Z up, front -Y, like every prop - but the ORIGIN is
# where the gear is held, not the centre of a base (both are in build_world_pack.py's PIVOT_PROPS):
#   VacuumGun   origin = the centre of the pistol grip (the Tool's Handle; Grip = identity), the
#               barrel along -Y with its axis 0.66 studs above the grip, the nozzle mouth at y = -2.75.
#   VacuumPack  origin = the centre of the harness plate (the tank's "Plate", welded behind the
#               torso). Its show side - the glass tank - faces -Y (the front); CharacterGear turns
#               it 180 degrees so the tank sits behind the wearer. The glass chamber is centred
#               0.72 studs in front of the plate and leaves room for CharacterGear's glowing "Fill"
#               (a 1.05-stud-wide cylinder up to 1.8 studs tall, centred on the plate's height).
# Paints (CharacterGear repaints them with the Climate Shift looks): Primary = shell, Secondary =
# dark trim, Tertiary = accent stripes (the look's glow colour, matte), Neon = glow, Glass = chambers.
# Remember the mirror: the game's +X (the wearer's right) is -X here. The props sit side by side on
# the row y = 270.

# ===== chunk 1/4: helpers shared by the gear =====
L = session_state["L"]
GR = session_state.setdefault("GR", {})


def along_y(m, y_start, z_axis, sx=1.0):
    """A shape built around the Z axis (z = 0 at its start) laid down along -Y: its axis becomes the
    line x = 0, z = z_axis, starting at y_start and running towards the front (-Y). sx squeezes it
    sideways (oval sections)."""
    m = L["rotate"](m, "x", 90)  # (x, y, z) -> (x, -z, y)
    if sx != 1.0:
        m = L["scale"](m, [sx, 1.0, 1.0])
    return L["move"](m, (0.0, y_start, z_axis))


def facing_back(m):
    """A shape built facing up (+Z) turned to face the back (+Y)."""
    return L["rotate"](m, "x", -90)  # (x, y, z) -> (x, z, -y)


def torus(center, big, small, n=16, m=6, axis="z", sx=1.0):
    """Doughnut (radius `big`, tube radius `small`) around a Z axis, or with axis="y" around a line
    parallel to Y (rings around the barrel). sx squeezes it sideways."""
    verts, faces = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            rad = big + small * math.cos(b)
            verts.append([rad * math.cos(a), rad * math.sin(a), small * math.sin(b)])
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            faces.append([i * m + j, i2 * m + j, i2 * m + j2, i * m + j2])
    mesh = L["orient"]({"v": verts, "f": faces})
    if axis == "y":
        mesh = L["rotate"](mesh, "x", 90)
    if sx != 1.0:
        mesh = L["scale"](mesh, [sx, 1.0, 1.0])
    return L["move"](mesh, center)


def band(radius, t0, t1, lip=0.035, n=16):
    """A raised stripe for along_y(): a ring `lip` proud of `radius` from t0 to t1 with chamfered
    edges (its inside is hidden in the body it wraps)."""
    e = min(0.025, (t1 - t0) * 0.3)
    prof = [(radius - 0.05, t0), (radius + lip, t0 + e), (radius + lip, t1 - e), (radius - 0.05, t1)]
    return L["lathe"](prof, n)


def disc(radius, height, bevel=0.02, n=12):
    """A flat coin around the Z axis from z = 0 to `height`, its top edge chamfered."""
    return L["lathe"]([(0.0, 0.0), (radius, 0.0), (radius, height - bevel), (radius - bevel, height),
                       (0.0, height)], n)


def side_slab(center, length, height, thick, radius):
    """A rounded-rectangle plate facing +-X (vent panels): `length` along Y, `height` along Z."""
    poly = L["round_poly"]([[-length / 2, -height / 2], [length / 2, -height / 2], [length / 2, height / 2],
                            [-length / 2, height / 2]], radius, 2)
    m = L["rotate"](L["extrude"](poly, thick, 0.0), "z", 90)  # the polygon in the YZ plane
    return L["move"](m, center)


def strap(path, width, thick, n=8):
    """Flat strap along a path that stays in one x = const plane: a round tube squashed sideways
    into an oval `width` wide (along X) and `thick` thick."""
    m = L["tube"](path, thick / 2.0, n=n, caps="round", cap_seg=2)
    return L["scale"](m, [width / thick, 1.0, 1.0], about=(path[0][0], 0.0, 0.0))


GR.update({"along_y": along_y, "facing_back": facing_back, "torus": torus, "band": band, "disc": disc,
           "side_slab": side_slab, "strap": strap})
result = {"chunk": 1, "helpers": len(GR)}

# ===== chunk 2/4: VacuumGun - motor housing, stripes, rear dial, vents, energy chamber =====
L = session_state["L"]
GR = session_state["GR"]
CAT = "gear"
AXIS = 0.66  # height of the barrel axis above the grip centre
SQUEEZE = 0.9  # the housing is a little narrower than it is tall
Y_REAR = 0.84  # where the housing starts; it runs 1.94 studs towards the front
HOUSING = [(0.44, 0.0), (0.52, 0.08), (0.57, 0.25), (0.59, 0.5), (0.59, 0.95), (0.575, 1.3), (0.54, 1.6),
           (0.48, 1.82), (0.43, 1.94)]


def housing_radius(t):
    for k in range(len(HOUSING) - 1):
        (r0, t0), (r1, t1) = HOUSING[k], HOUSING[k + 1]
        if t0 <= t <= t1:
            return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    return HOUSING[-1][0]


def vacuum_housing(p):
    L["piece"](p, "Primary", GR["along_y"](L["lathe"](HOUSING, n=16), Y_REAR, AXIS, SQUEEZE), crease=50)
    # Accent stripes: a wide one behind the vents, one near the front
    for t0, t1 in ((0.26, 0.42), (1.34, 1.5)):
        r = max(housing_radius(t0), housing_radius(t1))
        L["piece"](p, "Tertiary", GR["along_y"](GR["band"](r, t0, t1), Y_REAR, AXIS, SQUEEZE), crease=50)
    # Rear cap: a dark dome closing the housing, with a pressure dial facing the player
    cap = [(0.0, 0.0), (0.26, 0.0), (0.42, 0.05), (0.5, 0.14), (0.52, 0.28)]
    L["piece"](p, "Secondary", GR["along_y"](L["lathe"](cap, n=16), 1.04, AXIS, SQUEEZE), crease=50)
    bezel = GR["facing_back"](GR["disc"](0.25, 0.07, 0.025))
    L["piece"](p, "Tertiary", L["move"](bezel, (0.0, 1.0, AXIS)), crease=50)
    face = GR["facing_back"](GR["disc"](0.19, 0.1, 0.02))
    L["piece"](p, "Color_FFFFFF", L["move"](face, (0.0, 1.0, AXIS)), crease=50)
    needle = L["extrude"]([[-0.035, -0.04], [0.035, -0.04], [0.012, 0.15], [-0.012, 0.15]], 0.04, 0.0)
    L["piece"](p, "Color_233066", L["move"](L["rotate"](needle, "y", -35), (0.0, 1.115, AXIS)), crease=30)


def vacuum_vents(p):
    # A dark vent panel on each side of the housing with three glowing slots
    for side in (-1.0, 1.0):
        L["piece"](p, "Secondary", GR["side_slab"]((side * 0.5, 0.1, AXIS - 0.02), 0.64, 0.4, 0.12, 0.08), crease=50)
        for dz in (-0.11, 0.0, 0.11):
            z = AXIS - 0.02 + dz
            slot = L["tube"]([(side * 0.56, 0.3, z), (side * 0.56, -0.1, z)], 0.032, n=6, caps="round", cap_seg=1)
            L["piece"](p, "Neon_46C8FF", slot, crease=60)


def vacuum_chamber(p):
    # The energy chamber: a glass capsule along the barrel, half sunk into a raised spine on top of
    # the housing, with a glowing core inside
    zc = 1.34
    L["piece"](p, "Primary", L["rounded_box"]((0.0, -0.06, 1.16), [0.56, 1.3, 0.34], 0.14, seg=2), crease=50)
    L["piece"](p, "Secondary", L["rounded_box"]((0.0, -0.06, 1.3), [0.62, 1.16, 0.1], 0.05, seg=1), crease=50)
    L["piece"](p, "Glass_C8F0FF", L["tube"]([(0.0, 0.26, zc), (0.0, -0.38, zc)], 0.25, n=12, caps="round",
                                             cap_seg=3), crease=60)
    L["piece"](p, "Neon_46C8FF", L["tube"]([(0.0, 0.22, zc), (0.0, -0.34, zc)], 0.14, n=10, caps="round",
                                            cap_seg=2), crease=60)


def vacuum_gun_start():
    paints = {"Primary": "A0AAC0", "Secondary": "3A4052", "Tertiary": "46C8FF"}
    p = L["new_prop"]("VacuumGun", 0, 270, paints, solid=False, category=CAT)
    vacuum_housing(p)
    vacuum_vents(p)
    vacuum_chamber(p)
    return p


session_state["VacuumGun"] = vacuum_gun_start()
result = {"started": "VacuumGun", "tris": session_state["VacuumGun"]["tris"]}

# ===== chunk 3/4: VacuumGun - ribbed neck, flared nozzle, grip, trigger and guard =====
L = session_state["L"]
GR = session_state["GR"]
AXIS = 0.66
Y_NOZZLE = -1.86  # where the nozzle bell starts; its lip is at y = -2.75


def vacuum_nozzle(p):
    # Ribbed neck: three soft rings between the housing and the nozzle
    ribs = [(0.37 + 0.07 * (0.5 - 0.5 * math.cos(math.pi * k / 2)), 0.9 * k / 12) for k in range(13)]
    L["piece"](p, "Secondary", GR["along_y"](L["lathe"](ribs, n=12), -1.0, AXIS), crease=60)
    # Flared bell out to a rolled lip, then back in to a shallow intake
    bell = [(0.38, 0.0), (0.45, 0.18), (0.57, 0.4), (0.69, 0.56), (0.78, 0.74), (0.66, 0.84), (0.56, 0.73),
            (0.5, 0.64), (0.0, 0.62)]
    L["piece"](p, "Primary", GR["along_y"](L["lathe"](bell, n=16), Y_NOZZLE, AXIS), crease=50)
    L["piece"](p, "Secondary", GR["torus"]((0.0, Y_NOZZLE - 0.8, AXIS), 0.765, 0.085, n=16, m=5, axis="y"),
               crease=60)
    # Glowing ring inside the mouth around a dark intake floor
    L["piece"](p, "Neon_46C8FF", GR["torus"]((0.0, Y_NOZZLE - 0.71, AXIS), 0.55, 0.05, n=16, m=4, axis="y"),
               crease=60)
    L["piece"](p, "Color_233066", GR["along_y"](GR["disc"](0.52, 0.04, 0.01, n=12), Y_NOZZLE - 0.58, AXIS),
               crease=50)


def vacuum_grip(p):
    # Pistol grip under the housing, raked back, a rounded foot at the bottom
    path = [(0.0, -0.06, 0.32), (0.0, -0.02, 0.1), (0.0, 0.04, -0.14), (0.0, 0.1, -0.36), (0.0, 0.13, -0.46)]
    grip = L["tube"](path, [0.2, 0.2, 0.205, 0.215, 0.22], n=10, caps="round", cap_seg=2)
    L["piece"](p, "Secondary", L["scale"](grip, [0.82, 1.0, 1.0]), crease=60)
    L["piece"](p, "Primary", L["ball"]((0.0, 0.15, -0.53), [0.22, 0.29, 0.11], seg=2), crease=60)
    # Trigger and its guard
    trig = GR["strap"]([(0.0, -0.2, 0.16), (0.0, -0.3, 0.08), (0.0, -0.345, -0.02), (0.0, -0.33, -0.12)],
                       0.15, 0.11, n=8)
    L["piece"](p, "Color_FFC43C", trig, crease=60)
    guard = [(0.0, -0.58, 0.2), (0.0, -0.62, 0.04), (0.0, -0.57, -0.14), (0.0, -0.44, -0.26), (0.0, -0.26, -0.31),
             (0.0, -0.08, -0.3)]
    L["piece"](p, "Secondary", L["tube"](guard, 0.06, n=8, caps="round", cap_seg=2), crease=60)


p = session_state["VacuumGun"]
vacuum_nozzle(p)
vacuum_grip(p)
result = {"built": [L["report"](p)]}

# ===== chunk 4/4: VacuumPack - glass storm tank on a harness plate, straps, hose port, badge =====
L = session_state["L"]
GR = session_state["GR"]
CAT = "gear"
TY = -0.72  # the tank's axis is 0.72 studs in front of the plate (behind the wearer in the game)


def tank_body(p):
    c = (0.0, TY, 0.0)
    # The glass window (CharacterGear's glowing Fill rises inside it) between two rounded caps
    glass = [(0.6, -0.98), (0.64, -0.62), (0.655, 0.0), (0.64, 0.62), (0.6, 0.98)]  # a slightly barrelled jar
    L["piece"](p, "Glass_C8F0FF", L["lathe"](glass, n=24, center=c), crease=60)
    bottom = [(0.0, -1.4), (0.42, -1.39), (0.62, -1.35), (0.72, -1.27), (0.76, -1.16), (0.76, -1.03), (0.66, -0.95)]
    L["piece"](p, "Primary", L["lathe"](bottom, n=24, center=c), crease=50)
    top = [(0.66, 0.95), (0.76, 1.02), (0.76, 1.13), (0.69, 1.27), (0.54, 1.39), (0.3, 1.47), (0.0, 1.49)]
    L["piece"](p, "Primary", L["lathe"](top, n=24, center=c), crease=50)
    L["piece"](p, "Tertiary", L["lathe"]([(0.72, -1.2), (0.795, -1.18), (0.795, -1.04), (0.72, -1.02)], n=24,
                                         center=c), crease=50)
    L["piece"](p, "Neon_46C8FF", GR["torus"]((0.0, TY, 1.075), 0.775, 0.05, n=24, m=5), crease=60)
    # Two rails down the sides hold the caps together, a bolt head at each end
    for side in (-1.0, 1.0):
        x = side * 0.72
        L["piece"](p, "Secondary", L["tube"]([(x, TY, -1.02), (x, TY, 1.02)], 0.07, n=8, caps="flat"), crease=60)
        for z in (-1.06, 1.06):
            L["piece"](p, "Color_FFC43C", L["ball"]((side * 0.81, TY, z), [0.06, 0.09, 0.09], seg=2), crease=60)


def tank_fittings(p):
    # Hose port: an elbow out of the top's shoulder towards the wearer's right (+X here: the turn about
    # Y in the game undoes the mirror), ending in a yellow collar
    port = [(0.3, TY, 1.3), (0.33, TY, 1.48), (0.42, TY, 1.6), (0.56, TY, 1.64), (0.7, TY, 1.64)]
    L["piece"](p, "Secondary", L["tube"](port, 0.12, n=10, caps="flat"), crease=60)
    collar = L["rotate"](GR["disc"](0.17, 0.1, 0.03, n=12), "y", 90)  # facing +X
    L["piece"](p, "Color_FFC43C", L["move"](collar, (0.66, TY, 1.64)), crease=50)
    # Storm badge on the front of the top cap, tilted up towards the camera: a yellow bolt on a white disc
    bolt = L["rotate"](L["extrude"](L["bolt_poly"](0.26), 0.04, 0.0), "x", -90)  # lying on the face, tip down
    parts = (("Secondary", GR["disc"](0.21, 0.06, 0.02, n=12)), ("Color_FFFFFF", GR["disc"](0.16, 0.08, 0.02, n=12)),
             ("Color_FFC43C", L["move"](bolt, (0.0, 0.0, 0.1))))
    for paint, m in parts:
        m = L["rotate"](m, "x", 67)  # face -Y, tilted 23 degrees up like the dome under it
        L["piece"](p, paint, L["move"](m, (0.0, TY - 0.66, 1.18)), crease=50)


def tank_harness(p):
    # Harness plate against the wearer's back, with padded straps hooking over the shoulders (+Y here)
    L["piece"](p, "Secondary", L["rounded_box"]((0.0, 0.0, 0.0), [1.2, 0.24, 1.74], 0.1, seg=1), crease=50)
    for side in (-1.0, 1.0):
        x = side * 0.7
        path = [(x, 0.06, 0.48), (x, 0.17, 0.6), (x, 0.32, 0.68), (x, 0.55, 0.69), (x, 0.74, 0.64)]
        L["piece"](p, "Color_5B6A9E", GR["strap"](path, 0.28, 0.12, n=8), crease=60)
        L["piece"](p, "Color_FFC43C", L["rounded_box"]((x, 0.06, 0.42), [0.24, 0.14, 0.14], 0.05, seg=1), crease=50)


def vacuum_pack():
    paints = {"Primary": "A0AAC0", "Secondary": "3A4052", "Tertiary": "46C8FF"}
    p = L["new_prop"]("VacuumPack", 8, 270, paints, solid=False, category=CAT)
    tank_body(p)
    tank_fittings(p)
    tank_harness(p)
    return p


result = {"built": [L["report"](vacuum_pack())]}
