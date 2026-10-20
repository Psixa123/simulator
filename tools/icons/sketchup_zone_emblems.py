# Storm Catcher Simulator - 3D zone emblems (tools/icons/sketchup_zone_emblems.py)
#
# One chunky medallion per region (src/shared/Config/Zones.luau: the hub and the six zones), shown on the
# zone title card (src/client/UI/Overlays/ZoneTitle.luau). Modelled in Trimble SketchUp and rendered like
# the UI icons (tools/icons/README.md, "Zone emblems"): a gold coin rim around an enamel face in the biome
# palette (docs/STYLE_GUIDE.md), with a bold raised symbol of the biome on it.
#
# Send to SketchUp with build_model, in order: tools/world/sketchup/lib.py (4 chunks, the first with
# clean: true), chunks 1-2 of tools/icons/sketchup_icons.py (the icon helpers, session_state["IC"]), then
# every "# ===== chunk" block below (chunk 1 stores the emblem helpers in session_state["ZE"]), then
# tools/world/sketchup/extract.py.
#
# Contract (same as the icons): every emblem is a top-level group "Prop_Zone_<ZoneKey>" (category
# "icons") made of leaf groups named by paint (Color_RRGGBB). Units: studs, Z up, the emblem's face
# looks at -Y, origin at the centre of its base; about 4.6 studs across.
#
# Sandbox rules (checked by `python3 tools/icons/import_icons.py check`): no imports (math is
# pre-loaded), no eval/exec/open/type/setattr, no dunders, no classes, no any()/all().

# ===== chunk 1/4: emblem helpers (session_state["ZE"]) - the medal, clipped scenery, suns, clouds =====
L = session_state["L"]
IC = session_state["IC"]
ZE = session_state.setdefault("ZE", {})
P = IC["P"]
CZ = 2.35      # height of the medal's centre
FACE_R = 1.8   # radius of the enamel face
FACE_Y = -0.53  # the face's front plane (symbols sit in front of it)
GOLD, GOLD_L = "Color_FFB52E", "Color_FFD54A"


def new_emblem(key, slot):
    """Start (or rebuild) the group Prop_Zone_<key>; emblems sit side by side on a row, 8 studs apart."""
    return IC["new_icon"]("Zone_" + key, slot)


def medal(p, face):
    """The shared frame: a thick gold coin, an enamel face in the biome colour and a raised gold ring."""
    L["piece"](p, GOLD, IC["disc"]((0, 0, CZ), 2.25, 0.86, 0.36, n=56), crease=50)
    L["piece"](p, face, IC["disc"]((0, -0.43, CZ), FACE_R, 0.2, 0.06, n=56), crease=50)
    L["piece"](p, GOLD_L, IC["torus"]((0, -0.5, CZ), 1.93, 0.21, n=56, m=10), crease=60)


def clip_below(wave, r=FACE_R - 0.04, n=32, soft=0.18):
    """Outline (counter-clockwise from the front) of the part of the face circle (radius r, centred on
    the medal) that lies below the curve z = wave(x) (face-local x, z): hills, dunes, mountains. The two
    corners where the curve meets the circle are rounded off over `soft`, so slab bevels can't fold."""
    def edge(sign):
        lo, hi = 0.0, r
        for k in range(40):
            mid = (lo + hi) / 2.0
            x = sign * mid
            if x * x + wave(x) ** 2 < r * r:
                lo = mid
            else:
                hi = mid
        return sign * lo

    def bend(a, c, b, seg=5):
        return [[(1 - t) ** 2 * a[0] + 2 * t * (1 - t) * c[0] + t * t * b[0],
                 (1 - t) ** 2 * a[1] + 2 * t * (1 - t) * c[1] + t * t * b[1]] for t in [k / seg for k in range(1, seg)]]

    xl, xr = edge(-1.0), edge(1.0)
    al, ar = math.atan2(wave(xl), xl), math.atan2(wave(xr), xr)
    if ar < al:
        ar += 2 * math.pi
    da, dx = soft / r, soft * 0.8
    arc = [[r * math.cos(al + da + (ar - al - 2 * da) * k / n), r * math.sin(al + da + (ar - al - 2 * da) * k / n)]
           for k in range(n + 1)]
    top = [[xr - dx + (xl - xr + 2 * dx) * k / n, wave(xr - dx + (xl - xr + 2 * dx) * k / n)] for k in range(n + 1)]
    return (arc + bend(arc[-1], [xr, wave(xr)], top[0]) + top + bend(top[-1], [xl, wave(xl)], arc[0]))


def scenery(p, paint, wave, y, depth=0.24, bevel=0.07):
    """A flat slab of scenery (hill, dune, peak) filling the face below wave(x), its front at y - depth/2."""
    L["piece"](p, paint, IC["slab"](clip_below(wave), depth, bevel, y=y, z=CZ, support=0.03), crease=50)


def sun(p, c, r, core="Color_FFE14D", ray="Color_FFA526", y=-0.66, rays=10):
    """A cartoon sun at face-local c = (x, z): a puffy disc on a ring of rounded rays."""
    star = L["star_poly"](rays, r * 1.45, r * 1.05)
    L["piece"](p, ray, IC["slab"](star, 0.2, 0.05, y=y + 0.05, x=c[0], z=CZ + c[1], corner=r * 0.16, support=0.015),
               crease=50)
    L["piece"](p, core, IC["disc"]((c[0], y - 0.08, CZ + c[1]), r, 0.36, 0.15, n=36), crease=50)


def cloud_poly(circles, n=48, floor=None):
    """Outline of a union of circles [(x, z, r), ...] seen from their centroid (puffy clouds); floor cuts
    the bottom flat at that z."""
    cx = sum([c[0] for c in circles]) / len(circles)
    cz = sum([c[1] for c in circles]) / len(circles)
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        d = [math.cos(t), math.sin(t)]
        best = 0.0
        for x, z, r in circles:
            ox, oz = x - cx, z - cz
            b = ox * d[0] + oz * d[1]
            h = b * b - (ox * ox + oz * oz - r * r)
            if h >= 0:
                best = max(best, b + math.sqrt(h))
        if floor is not None and d[1] < -1e-6 and cz + best * d[1] < floor:
            best = (floor - cz) / d[1]
        pts.append([cx + best * d[0], cz + best * d[1]])
    return pts


def cloud(p, paint, circles, y, depth, floor=None, power=0.5):
    """A puffy cushion cloud in front of the face (circles in face-local x, z)."""
    poly = cloud_poly(circles, floor=floor)
    L["piece"](p, paint, IC["pillow"](poly, depth, center=(0.0, y, CZ), rings=5, power=power), crease=60)


def sparkle(p, paint, c, r, y, points=4, depth=0.22):
    """A small puffy star at face-local c (4 points = a twinkle, 5 = a star)."""
    inner = 0.42 if points == 4 else 0.5
    poly = L["round_poly"](L["star_poly"](points, r, r * inner), r * 0.12, seg=2)
    L["piece"](p, paint, IC["pillow"](IC["move2"](poly, c[0], c[1]), depth, center=(0.0, y, CZ), rings=4,
                                      power=0.6), crease=60)


def heart(w):
    """Heart outline about w wide, its point at the origin, the lobes up (+z) - a clover leaf."""
    pts = []
    for i in range(40):
        t = 2 * math.pi * i / 40
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append([x * w / 32.0, (z + 17) * w / 32.0])
    return pts


ZE.update({"CZ": CZ, "FACE_R": FACE_R, "FACE_Y": FACE_Y, "new_emblem": new_emblem, "medal": medal,
           "clip_below": clip_below, "scenery": scenery, "sun": sun, "cloud_poly": cloud_poly, "cloud": cloud,
           "sparkle": sparkle, "heart": heart})
result = {"chunk": 1, "helpers": len(ZE)}

# ===== chunk 2/4: Hub (Storm Station: a house on a cloud), Meadows (Sunny Plains: sun over clover hills) =====
L = session_state["L"]
IC = session_state["IC"]
ZE = session_state["ZE"]
P = IC["P"]
CZ = ZE["CZ"]


def hub():
    p = ZE["new_emblem"]("Hub", 0)
    ZE["medal"](p, "Color_5CC8FF")
    ZE["sparkle"](p, "Color_FFFFFF", (-1.02, 0.72), 0.3, -0.62)
    ZE["sparkle"](p, "Color_FFFFFF", (1.12, 0.42), 0.22, -0.62)
    # the station: a chunky white house with a coral roof, a glowing round window and a blue door
    body = L["rounded_box"]((0.0, -0.72, CZ - 0.3), [1.56, 0.46, 1.12], 0.16, seg=2)
    L["piece"](p, "Color_EEF0FF", body, crease=40)
    roof = [[-1.12, 0.12], [1.12, 0.12], [0.0, 1.08]]
    L["piece"](p, P["coral"], IC["slab"](roof, 0.6, 0.12, y=-0.76, z=CZ + 0.08, corner=0.2, support=0.04), crease=50)
    L["piece"](p, P["bolt"], IC["disc"]((0.0, -1.08, CZ + 0.5), 0.2, 0.16, 0.06, n=24), crease=50)
    door = L["round_poly"]([[-0.24, -0.86], [0.24, -0.86], [0.24, -0.26], [-0.24, -0.26]], 0.2, seg=3)
    L["piece"](p, P["sky_d"], IC["slab"](door, 0.14, 0.04, y=-0.98, z=CZ, x=0.0, support=0.0), crease=50)
    for x in (-0.52, 0.52):
        L["piece"](p, "Color_8FDBFF", IC["disc"]((x, -0.98, CZ - 0.3), 0.15, 0.12, 0.04, n=20), crease=50)
    # a weather vane on the roof ridge
    L["piece"](p, P["inksoft"], L["tube"]([(0.0, -0.76, CZ + 1.12), (0.0, -0.76, CZ + 1.42)], 0.06, n=8), crease=60)
    L["piece"](p, P["bolt"], L["ball"]((0.0, -0.76, CZ + 1.48), 0.11, seg=3), crease=60)
    # a fluffy cloud the station floats on
    ZE["cloud"](p, "Color_FFFFFF", [(-0.95, -1.0, 0.36), (-0.4, -0.92, 0.44), (0.25, -0.95, 0.44),
                                    (0.88, -1.02, 0.34), (0.0, -1.2, 0.36)], -0.86, 0.5, floor=-1.4)
    return p


def clover(p, c, w, spin, y):
    """A four-leaf clover at face-local c, leaves about w long, turned by spin degrees."""
    for i in range(4):
        ang = 45 + 90 * i + spin
        leaf = IC["rot2"](ZE["heart"](w), ang - 90)
        leaf = IC["move2"](leaf, c[0], c[1])
        piv = [c[0] + 0.45 * w * math.cos(math.radians(ang)), c[1] + 0.45 * w * math.sin(math.radians(ang))]
        L["piece"](p, P["leaf"] if i % 2 == 0 else "Color_6BDA5A",
                   IC["pillow"](leaf, 0.26, center=(0.0, y - 0.02 * i, CZ), pivot=piv, rings=4, power=0.55),
                   crease=60)


def meadows():
    p = ZE["new_emblem"]("Meadows", 1)
    ZE["medal"](p, "Color_8FDBFF")
    ZE["sun"](p, (0.56, 0.62), 0.48)
    ZE["cloud"](p, "Color_FFFFFF", [(-0.95, 0.62, 0.3), (-0.55, 0.78, 0.38), (-0.12, 0.62, 0.3)], -0.74, 0.36,
                floor=0.42)
    # two rolling hills: a pale one behind, a bright one in front
    ZE["scenery"](p, "Color_A8F07A", lambda x: -0.02 + 0.26 * math.cos(1.25 * (x - 0.75)), -0.6)
    ZE["scenery"](p, "Color_4CC94A", lambda x: -0.5 + 0.2 * math.cos(1.4 * (x + 0.75)), -0.68, depth=0.28)
    # a big four-leaf clover on the front hill and two little flowers
    clover(p, (-0.62, -0.72), 0.78, 8, -0.86)
    L["piece"](p, P["leaf_d"], L["tube"]([(-0.62, -0.84, CZ - 0.78), (-0.5, -0.84, CZ - 1.1)], 0.08, n=8),
               crease=60)
    for x, z in ((0.55, -0.5), (1.02, -0.78)):
        ZE["sparkle"](p, "Color_FFFFFF", (x, z), 0.2, -0.86, points=5, depth=0.16)
        L["piece"](p, P["bolt"], L["ball"]((x, -0.95, CZ + z), [0.08, 0.05, 0.08], seg=3), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (hub, meadows)]}

# ===== chunk 3/4: Thunder (Thunder Valley: thundercloud and bolt), Dunes (Dune Sea: dunes, sun, cactus) =====
L = session_state["L"]
IC = session_state["IC"]
ZE = session_state["ZE"]
P = IC["P"]
CZ = ZE["CZ"]


def drop(p, c, h, y):
    """A small raindrop at face-local c (its middle), h tall, the tip up."""
    pts = []
    for k in range(32):
        t = 2 * math.pi * k / 32
        pts.append([c[0] - 0.42 * h * math.sin(t) * math.sin(t / 2), c[1] + 0.5 * h * math.cos(t)])
    L["piece"](p, P["rain"], IC["pillow"](pts, 0.2, center=(0.0, y, CZ), pivot=[c[0], c[1] - 0.15 * h], rings=4,
                                          power=0.6), crease=60)


def thunder():
    p = ZE["new_emblem"]("Thunder", 2)
    ZE["medal"](p, "Color_6F5FE0")
    ZE["sparkle"](p, "Color_FFE14D", (-1.15, -0.55), 0.24, -0.62)
    ZE["sparkle"](p, "Color_FFE14D", (1.2, -0.42), 0.2, -0.62)
    drop(p, (-0.92, -1.1), 0.42, -0.66)
    drop(p, (0.98, -1.05), 0.36, -0.66)
    # the bolt drops out of the cloud, its tip breaking over the bottom of the rim
    bolt = IC["rot2"](IC["bolt_shape"](2.3), -10)
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.4, 0.12, y=-0.74, x=0.12, z=CZ - 0.78, corner=0.24), crease=50)
    # a puffy thundercloud: a darker underside and a pale lavender top
    puffs = [(-0.82, 0.36, 0.46), (-0.22, 0.66, 0.62), (0.52, 0.56, 0.54), (0.98, 0.26, 0.4), (0.05, 0.2, 0.5)]
    ZE["cloud"](p, "Color_B9AEF7", [(x, z - 0.12, r) for x, z, r in puffs], -0.86, 0.6, floor=-0.08)
    ZE["cloud"](p, "Color_F1EEFF", puffs, -1.0, 0.52, floor=0.12)
    return p


def cactus(p, x, z, h, y, paint="Color_34C28C"):
    """A saguaro: a fat trunk h tall from face-local (x, z) and two arms."""
    r = 0.15 * h
    L["piece"](p, paint, L["tube"]([(x, y, CZ + z), (x, y, CZ + z + h)], r, n=12), crease=60)
    for side, at, up in ((-1, 0.38, 0.32), (1, 0.52, 0.26)):
        arm = [(x, y, CZ + z + at * h), (x + side * 0.3 * h, y, CZ + z + at * h),
               (x + side * 0.32 * h, y, CZ + z + (at + up) * h)]
        L["piece"](p, paint, L["tube"](arm, 0.72 * r, n=10), crease=60)


def dunes():
    p = ZE["new_emblem"]("Dunes", 3)
    ZE["medal"](p, "Color_9DEBF2")
    ZE["sun"](p, (-0.55, 0.62), 0.5, core="Color_FFF08A", ray="Color_FF9A3C")
    # a pale dune behind with a cactus on it, a golden dune in front
    ZE["scenery"](p, "Color_FFD983", lambda x: -0.15 + 0.55 * math.exp(-((x - 0.5) / 0.75) ** 2), -0.6)
    cactus(p, 0.62, 0.2, 0.9, -0.66)
    ZE["scenery"](p, "Color_F5A742", lambda x: -0.72 + 0.42 * math.exp(-((x + 0.65) / 0.85) ** 2), -0.72,
                  depth=0.3)
    # wind lines over the front dune
    for x0, z0, ln in ((-0.95, -0.95, 0.7), (0.05, -1.22, 0.62)):
        line = [(x0 + ln * k / 4, -0.9, CZ + z0 + 0.06 * math.sin(math.pi * k / 4)) for k in range(5)]
        L["piece"](p, "Color_FFE7B0", L["tube"](line, 0.05, n=6), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (thunder, dunes)]}

# ===== chunk 4/4: Frost (Frostpeak: snowy peak, snowflake), Volcano (Ashfall), Sky (Upper Atmosphere) =====
L = session_state["L"]
IC = session_state["IC"]
ZE = session_state["ZE"]
P = IC["P"]
CZ = ZE["CZ"]


def peak(px, top, slope, soft=0.12):
    """z = wave(x) of a mountain: a peak at (px, top) with a softly rounded tip."""
    return lambda x: top - slope * math.sqrt((x - px) ** 2 + soft * soft)


def snowflake(p, c, r, y):
    """Six puffy arms with a little V on each, at face-local c."""
    for k in range(6):
        a = math.radians(90 + 60 * k)
        tip = (c[0] + r * math.cos(a), c[1] + r * math.sin(a))
        L["piece"](p, "Color_FFFFFF", L["tube"]([(c[0], y, CZ + c[1]), (tip[0], y, CZ + tip[1])], 0.065, n=8),
                   crease=60)
        mid = (c[0] + 0.58 * r * math.cos(a), c[1] + 0.58 * r * math.sin(a))
        for s in (-1, 1):
            b = a + s * math.radians(45)
            end = (mid[0] + 0.32 * r * math.cos(b), mid[1] + 0.32 * r * math.sin(b))
            L["piece"](p, "Color_FFFFFF", L["tube"]([(mid[0], y, CZ + mid[1]), (end[0], y, CZ + end[1])], 0.055,
                                                    n=8), crease=60)
    L["piece"](p, "Color_FFFFFF", L["ball"]((c[0], y, CZ + c[1]), 0.1, seg=3), crease=60)


def frost():
    p = ZE["new_emblem"]("Frost", 4)
    ZE["medal"](p, "Color_BFE5FF")
    snowflake(p, (-0.9, 0.78), 0.42, -0.66)
    ZE["sparkle"](p, "Color_FFFFFF", (1.05, 0.95), 0.2, -0.62)
    # a pale peak behind on the right, the big blue peak in front with a wavy snow cap
    ZE["scenery"](p, "Color_8FC2FA", peak(0.75, 0.35, 1.2), -0.6)
    main = peak(-0.2, 0.92, 1.25)
    ZE["scenery"](p, "Color_4F8DEB", main, -0.68, depth=0.28)
    cap = []
    for k in range(13):
        x = -0.2 - 0.66 + 1.32 * k / 12
        cap.append([x, main(x) + 0.02])
    for k in range(1, 12):
        x = -0.2 + 0.62 - 1.24 * k / 12
        cap.append([x, 0.18 + 0.12 * math.cos(math.pi * 3 * k / 12)])
    cap = list(reversed(cap))
    L["piece"](p, "Color_FFFFFF", IC["slab"](cap, 0.2, 0.05, y=-0.86, z=CZ, corner=0.08, support=0.0), crease=50)
    # snow drifts at the foot
    ZE["scenery"](p, "Color_F4FAFF", lambda x: -1.05 + 0.18 * math.cos(2.2 * x), -0.78, depth=0.22)
    return p


def volcano():
    p = ZE["new_emblem"]("Volcano", 5)
    ZE["medal"](p, "Color_FFB27A")
    # ash puffs rising from the crater
    ZE["cloud"](p, "Color_8D7A96", [(-0.1, 0.82, 0.34), (0.32, 1.02, 0.4), (0.75, 1.2, 0.28)], -0.7, 0.4)
    # the cone, a lava cap with drips, and glowing embers
    cone = lambda x: min(0.42, 0.42 - 1.75 * (abs(x) - 0.42))
    ZE["scenery"](p, "Color_8A5A4E", lambda x: cone(x) - 0.2, -0.64, depth=0.28)
    ZE["scenery"](p, "Color_B5705A", lambda x: min(-0.95, cone(x) - 0.2), -0.74, depth=0.2)
    lava = [[-0.5, 0.24], [-0.32, 0.24], [-0.36, -0.12], [-0.22, -0.3], [-0.1, -0.1], [0.04, -0.62],
            [0.2, -0.1], [0.3, 0.02], [0.4, -0.2], [0.5, 0.24], [0.62, 0.24], [0.5, 0.32], [-0.38, 0.32]]
    L["piece"](p, "Color_FF6A1F", IC["slab"](lava, 0.16, 0.04, y=-0.84, z=CZ, corner=0.08, support=0.0), crease=50)
    L["piece"](p, "Color_FFD23F", IC["slab"](L["round_poly"]([[-0.4, 0.26], [0.42, 0.26], [0.32, 0.34],
                                                               [-0.3, 0.34]], 0.04, seg=2), 0.2, 0.04, y=-0.86,
                                             z=CZ, support=0.0), crease=50)
    for x, z, r in ((-0.68, 0.62, 0.1), (-0.95, 0.2, 0.08), (1.0, 0.5, 0.09), (0.62, 0.48, 0.07)):
        L["piece"](p, "Color_FFD23F", L["ball"]((x, -0.7, CZ + z), r, seg=3), crease=60)
    return p


def sky():
    p = ZE["new_emblem"]("Sky", 6)
    ZE["medal"](p, "Color_4B36B8")
    for c, r, paint, pts in (((-1.0, 0.7), 0.3, "Color_FFFFFF", 4), ((1.0, 0.82), 0.24, "Color_FFE14D", 5),
                             ((1.15, -0.62), 0.22, "Color_FFFFFF", 4), ((-0.98, -0.72), 0.2, "Color_FFE14D", 5),
                             ((0.1, 1.28), 0.16, "Color_FFFFFF", 4)):
        ZE["sparkle"](p, paint, c, r, -0.62, points=pts)
    # a ringed planet: pink with a pale band, a gold ring tilted towards the viewer
    centre = (0.0, -0.8, CZ)
    L["piece"](p, "Color_FF8CDC", L["ball"](centre, [0.82, 0.62, 0.82], seg=8), crease=60)
    band = L["ball"]((0.0, 0.0, 0.0), [0.835, 0.635, 0.16], seg=8)
    band = L["move"](L["rotate"](band, "y", -18), centre)
    L["piece"](p, "Color_FFC2EE", band, crease=60)
    ring = IC["torus"]((0.0, 0.0, 0.0), 1.18, 0.11, n=48, m=8, axis="z", squash=0.6)
    ring = L["rotate"](L["rotate"](ring, "x", -72), "y", -18)
    L["piece"](p, P["bolt"], L["move"](ring, centre), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (frost, volcano, sky)]}
