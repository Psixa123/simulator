# Storm Catcher Simulator - 3D store heroes (tools/icons/sketchup_store_icons.py)
#
# The hero models of the gamepass and developer product icons (src/shared/Config/Monetization.luau): bigger,
# more detailed versions of the 3D UI icons (a jewelled crown, a stack of volt coins, a glowing energy drop,
# a storm tank, eggs, a radar scope...). Modelled in Trimble SketchUp, rendered like the UI icons by
# tools/icons/render_icons.py --set store, then put on the sunburst badges by assets/source/store3d.html
# (tools/render_art.py). See tools/icons/README.md, "Store icons".
#
# Send to SketchUp with build_model, in order: tools/world/sketchup/lib.py (4 chunks, the first with
# clean: true), chunks 1-2 of tools/icons/sketchup_icons.py (the icon helpers, session_state["IC"]), then
# every "# ===== chunk" block below (chunk 1 stores the store helpers in session_state["ST"]), then
# tools/world/sketchup/extract.py.
#
# Contract (same as the icons): every hero is a top-level group "Prop_Store_<Key>" (category "icons") made of
# leaf groups named by paint (Color_RRGGBB, Glass_RRGGBB for see-through glass, Neon_RRGGBB for glows and
# shine streaks). Units: studs, Z up, the hero's front looks at -Y, origin at the centre of its base; about
# 5-7 studs across. The pets (AuroraGryphon, PetSlots) and the vacuum gun (AutoCatch) are not in here: they
# come from tools/pets and tools/world/sketchup/gear.py (tools/icons/store_scenes.py places them).
#
# Sandbox rules (checked by `python3 tools/icons/import_icons.py check`): no imports (math is
# pre-loaded), no eval/exec/open/type/setattr, no dunders, no classes, no any()/all().

# ===== chunk 1/12: store helpers (session_state["ST"]) - paints, facing, coins, coin stacks, gems =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state.setdefault("ST", {})
P = IC["P"]

# The icon palette P plus the store's extra steps. Two golds alternate in coin stacks so every coin gets its
# own ink line (pieces of one paint share a mesh).
Q = {"gold": "Color_FFB52E", "gold2": "Color_FFC23A", "rim": "Color_FFCF3A", "emboss": "Color_FFF6E2",
     "gold_d": "Color_F59A23", "ruby": "Color_FF3D6E", "sapphire": "Color_3DA8FF", "emerald": "Color_3FD37A",
     "amethyst": "Color_A66BFF", "pearl": "Color_FFF8EE", "velvet": "Color_C92A62", "steel": "Color_C3CCF0",
     "steel_d": "Color_8794CC", "wood": "Color_D9884A", "wood_d": "Color_A45F2E", "glow": "Neon_8FF0FF",
     "glow_y": "Neon_FFE36B", "shine": "Neon_FFFFFF"}


def new_store(key, slot):
    """Start (or rebuild) the group Prop_Store_<key>; heroes sit side by side on a row, 12 studs apart."""
    return L["new_prop"]("Store_" + key, 12.0 * slot, 0.0, {}, solid=False, category="icons")


def facing(m, normal, at, spin=0.0):
    """Turn a mesh modelled facing the front (-Y) around its origin so that its front looks along `normal`
    (its top stays as upright as it can), spun by `spin` degrees about that normal, and move it to `at`."""
    m = L["rotate"](m, "x", -90)
    if spin:
        m = L["rotate"](m, "z", spin)
    return IC["align"](m, normal, at)


def put(p, parts, normal, at, spin=0.0):
    """Add [(paint, mesh, crease), ...] modelled facing the front around the origin, turned by facing()."""
    for paint, m, crease in parts:
        L["piece"](p, paint, facing(m, normal, at, spin), crease=crease)


def coin_parts(r=1.0, thick=0.36, body=None, back=False, n=44, rim=True):
    """A Volts coin facing the front around the origin: gold disc, raised rim ring, embossed bolt (both
    faces when `back`); n = segments round the rim (fewer for small coins in heaps), rim=False: no ring."""
    body = body or Q["gold"]
    bolt = IC["bolt_shape"](r * 1.22)
    parts = [(body, IC["disc"]((0, 0, 0), r, thick, min(0.15 * r, 0.42 * thick), n=n), 50)]
    for side in ((-1, 1) if back else (-1,)):
        outline = bolt if side < 0 else [[-q[0], q[1]] for q in reversed(bolt)]
        if rim:
            parts.append((Q["rim"], IC["torus"]((0, side * 0.46 * thick, 0), 0.83 * r, 0.09 * r, n=n, m=8), 60))
        parts.append((Q["emboss"], IC["slab"](outline, 0.7 * thick, 0.05 * r, y=side * 0.45 * thick,
                                              corner=0.12 * r), 50))
    return parts


def coin(p, at, normal, r=1.0, thick=0.36, spin=0.0, body=None, back=False, n=44, rim=True):
    put(p, coin_parts(r, thick, body, back, n, rim), normal, at, spin)


def coin_stack(p, base, count, r=1.0, h=0.34, seed=1, wobble=0.07, top=True, paints=None):
    """Coins lying flat, stacked from `base` (the bottom of the stack), each nudged a little; the top one
    shows its rim and bolt. Returns the height of the stack's top face."""
    rnd = L["rng"](seed)
    paints = paints or (Q["gold"], Q["gold2"])
    z = base[2]
    for i in range(count):
        c = (base[0] + (rnd() * 2 - 1) * wobble * r, base[1] + (rnd() * 2 - 1) * wobble * r, z + h / 2.0)
        paint = paints[i % len(paints)]
        if i == count - 1 and top:
            coin(p, c, [0, 0, 1], r, h, spin=(rnd() * 2 - 1) * 14, body=paint)
        else:
            L["piece"](p, paint, L["puck"]((c[0], c[1], z), r, h, min(0.12, h * 0.4), n=40, seg=2), crease=50)
        z += h
    return z


def gem_parts(r, h, paint, facets=8):
    """A brilliant-cut gem facing the front around the origin: flat table, crown, girdle, pointed pavilion
    (flat-shaded facets)."""
    prof = [(0.0, -0.62 * h), (r, 0.0), (r, 0.1 * h), (0.62 * r, 0.38 * h), (0.0, 0.38 * h)]
    m = front_lathe(prof, facets)
    return [(paint, m, 12)]


def front_lathe(prof, n, phase=None):
    """lib lathe() around the Y axis, its +Z end towards the front (-Y)."""
    return IC["front"](L["lathe"](prof, n=n, phase=math.pi / n if phase is None else phase))


def gem(p, at, normal, r, h, paint, facets=8, spin=0.0):
    put(p, gem_parts(r, h, paint, facets), normal, at, spin)


ST.update({"Q": Q, "new_store": new_store, "facing": facing, "put": put, "coin_parts": coin_parts, "coin": coin,
           "coin_stack": coin_stack, "gem_parts": gem_parts, "gem": gem, "front_lathe": front_lathe})
result = {"chunk": 1, "helpers": len(ST)}

# ===== chunk 2/12: store helpers - eggs, clovers, clouds, arrows, hourglasses, surface wraps =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def egg_point(t, h, r, k=0.13):
    """(radius, height) of the egg outline at t in [0, pi] (0 = bottom tip, pi = top)."""
    return (r * math.sin(t) * (1 + k * math.cos(t)), h / 2 * (1 - math.cos(t)))


def egg(p, base, h, r, paint, spot_paint, spots, lean=(0.0, 0.0), spin=0.0, k=0.13):
    """An egg h tall and r wide standing on `base`, with spots [(t, azimuth degrees (-90 = front), size), ...]
    (a 4th value = that spot's own paint); lean = (degrees to the right, degrees forward) about its bottom."""
    def place(m):
        m = L["rotate"](m, "z", spin) if spin else m
        return L["move"](L["rotate"](L["rotate"](m, "y", lean[0]), "x", lean[1]), base)

    L["piece"](p, paint, place(L["lathe"]([egg_point(math.pi * i / 28, h, r, k) for i in range(29)], n=48)),
               crease=60)
    for spot in spots:
        t, az, size = spot[:3]
        rr, z = egg_point(t, h, r, k)
        a = math.radians(az)
        dr = r * (math.cos(t) * (1 + k * math.cos(t)) - k * math.sin(t) ** 2)
        dz = h / 2 * math.sin(t)
        nn = math.hypot(dr, dz)
        normal = [dz / nn * math.cos(a), dz / nn * math.sin(a), -dr / nn]
        m = IC["decal"]((rr * math.cos(a), rr * math.sin(a), z), normal, size, size * 0.9, 0.36 * size,
                        sink=0.16 * size)
        L["piece"](p, spot[3] if len(spot) > 3 else spot_paint, place(m), crease=60)


def heart(w):
    """Heart outline about w wide, its point at the origin, the lobes up (+z)."""
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append([x * w / 32.0, (z + 17) * w / 32.0])
    return pts


def clover_parts(size=1.0, stem=True):
    """A four-leaf clover facing the front around its centre (about 4.6 * size across), two greens."""
    parts = []
    for i in range(4):
        ang = 45 + 90 * i
        c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        leaf = IC["move2"](IC["rot2"](heart(2.25 * size), ang - 90), 0.1 * size * c, 0.1 * size * s)
        parts.append((P["leaf"] if i % 2 == 0 else "Color_6BDA5A",
                      IC["pillow"](leaf, 0.8 * size, center=(0.0, -0.04 * i * size, 0.0),
                                   pivot=[1.05 * size * c, 1.05 * size * s], rings=5, power=0.55), 60))
    if stem:
        path = [(0.05 * size, 0.3 * size, -0.6 * size), (0.22 * size, 0.28 * size, -1.2 * size),
                (0.55 * size, 0.2 * size, -1.8 * size), (1.05 * size, 0.12 * size, -2.3 * size)]
        parts.append((P["leaf_d"], L["tube"](path, [0.26 * size, 0.24 * size, 0.22 * size, 0.2 * size], n=12,
                                             caps="round"), 60))
    return parts


def cloud(p, center, s=1.0, paint="Color_FFFFFF", seed=5, flat=None):
    """A puffy cartoon cloud about 4.4 * s wide around `center` (flat = paint of a flatter underside)."""
    cx, cy, cz = center
    for (x, y, z), r in (((-1.35, 0.0, 0.35), 0.95), ((0.05, 0.1, 0.8), 1.3), ((1.4, 0.0, 0.4), 0.92),
                         ((-0.6, -0.3, 0.0), 0.9), ((0.75, -0.3, 0.0), 0.92)):
        L["piece"](p, paint, L["blob"]((cx + x * s, cy + y * s, cz + z * s), r * s, squash=0.92, lump=0.03,
                                       seed=seed, seg=7), crease=60)
    L["piece"](p, flat or paint, L["rounded_box"]((cx, cy, cz - 0.1 * s), [3.9 * s, 1.7 * s, 1.0 * s], 0.48 * s,
                                                  seg=3), crease=40)


def arrow(p, path, radius, paint, head=2.2, flat=0.7):
    """A puffy arrow along `path`: a tube (squashed to `flat` across its path's plane) ending in a fat
    rounded cone head `head` times its radius."""
    d = L["v_norm"](L["v_sub"](path[-1], path[-2]))
    L["piece"](p, paint, L["tube"](path[:-1], radius, n=14, caps="round"), crease=60)
    hr = radius * head
    cone = L["lathe"]([(0.0, 0.0), (hr, 0.0), (hr * 0.98, 0.12 * hr), (0.2 * hr, 1.5 * hr), (0.0, 1.62 * hr)], n=24)
    L["piece"](p, paint, IC["align"](cone, d, path[-2]), crease=50)


def lookup(prof, z):
    """Radius of a lathe profile [(r, z), ...] (z rising) at height z (linear in between)."""
    for i in range(len(prof) - 1):
        (r0, z0), (r1, z1) = prof[i][:2], prof[i + 1][:2]
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return prof[-1][0] if z > prof[-1][1] else prof[0][0]


def wrap(m, prof, center=(0.0, 0.0), sink=0.12):
    """Bend a slab modelled facing the front (its back face at y = 0) onto a lathe surface around the
    vertical axis at `center`: every vertex keeps its depth below the surface (minus `sink`)."""
    def bend(q):
        r = lookup(prof, q[2])
        x = q[0] - center[0]
        y0 = -math.sqrt(max(0.0, r * r - x * x))
        return [q[0], center[1] + y0 + q[1] + sink, q[2]]
    return L["warp"](m, bend)


def hourglass(p, base, h=4.2, r=1.45, frame=None, sand="Neon_6FE8FF", glass="Glass_D9F4FF"):
    """An hourglass on `base`: gold end plates and posts, glass bulbs, glowing sand mostly run out."""
    frame = frame or Q["gold"]
    x0, y0, z0 = base
    for z in (0.0, h - 0.42):
        L["piece"](p, frame, L["puck"]((x0, y0, z0 + z), r, 0.42, 0.16, n=40), crease=50)
    for i in range(3):
        a = math.radians(-60 + 120 * i)
        q = (x0 + 0.9 * r * math.cos(a), y0 + 0.9 * r * math.sin(a))
        L["piece"](p, Q["rim"], L["tube"]([(q[0], q[1], z0 + 0.3), (q[0], q[1], z0 + h - 0.3)], 0.12, n=10,
                                          caps="flat"), crease=60)
    neck, half = 0.16, (h - 0.84) / 2.0
    bulb = [(0.0, 0.0)] + [(neck + (0.78 * r - neck) * math.sin(math.pi * t / 12) ** 0.8, half * t / 12)
                           for t in range(1, 13)] + [(0.0, half)]
    L["piece"](p, glass, L["lathe"](bulb, n=36, center=(x0, y0, z0 + 0.42)), crease=60)
    top = [(0.0, 0.0)] + [(q[0], half - q[1]) for q in reversed(bulb[1:-1])] + [(0.0, half)]
    L["piece"](p, glass, L["lathe"](top, n=36, center=(x0, y0, z0 + 0.42 + half)), crease=60)
    pile = [(0.0, 0.0), (0.72 * r, 0.0), (0.66 * r, 0.25 * half), (0.36 * r, 0.52 * half), (0.0, 0.62 * half)]
    L["piece"](p, sand, L["lathe"](pile, n=32, center=(x0, y0, z0 + 0.5)), crease=60)
    rest = [(0.0, 0.0), (0.3 * r, 0.12 * half), (0.6 * r, 0.42 * half), (0.0, 0.42 * half)]
    L["piece"](p, sand, L["lathe"](rest, n=32, center=(x0, y0, z0 + 0.42 + half + 0.06)), crease=60)
    L["piece"](p, sand, L["tube"]([(x0, y0, z0 + 0.42 + half), (x0, y0, z0 + 0.5 + 0.6 * half)], 0.07, n=8,
                                  caps="round"), crease=60)


ST.update({"egg_point": egg_point, "egg": egg, "heart": heart, "clover_parts": clover_parts, "cloud": cloud,
           "arrow": arrow, "lookup": lookup, "wrap": wrap, "hourglass": hourglass})
result = {"chunk": 2, "helpers": len(ST)}

# ===== chunk 3/12: VIP (jewelled crown), DoubleVolts (coin stacks and a flipping coin) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def crown_peak(a, peaks=5, a0=-math.pi / 2):
    """0..1 height of the crown's spikes at angle a: 1 at a peak (one faces the front), 0 between them."""
    u = ((a - a0) * peaks / (2 * math.pi)) % 1.0
    d = 2.0 * min(u, 1.0 - u)
    return (1.0 - d) ** 1.35


def vip():
    p = ST["new_store"]("VIP", 0)
    # the crown: a thick gold cup whose upper wall is pulled up into five spikes
    cup = [(0.0, 0.0), (1.95, 0.0), (2.06, 0.08), (2.1, 0.3), (2.15, 0.8), (2.2, 1.3), (2.24, 1.72), (2.2, 1.86),
           (2.06, 1.92), (1.92, 1.86), (1.86, 1.62), (1.8, 1.05), (1.74, 0.5), (1.68, 0.36), (0.0, 0.36)]
    zb, lift = 0.7, 1.3

    def spike(q):
        k = crown_peak(math.atan2(q[1], q[0]))
        return [q[0], q[1], q[2] if q[2] <= zb else zb + (q[2] - zb) * (1.0 + lift * k)]

    L["piece"](p, Q["gold"], L["warp"](L["lathe"](cup, n=80), spike), crease=55)
    top = zb + (1.92 - zb) * (1.0 + lift)
    # a quilted velvet cushion inside (six puffs break up its highlight), a gold orb with a cross on top
    quilt = lambda d: 1.0 + 0.07 * math.cos(6 * math.atan2(d[1], d[0])) * L["smoothstep"](0.1, 0.7, d[2])
    L["piece"](p, Q["velvet"], L["ball"]((0, 0, 1.45), [1.9, 1.9, 1.3], seg=12, shape=quilt), crease=60)
    L["piece"](p, Q["rim"], L["ball"]((0, 0, 2.95), 0.42, seg=6), crease=60)
    L["piece"](p, Q["rim"], L["tube"]([(0, 0, 3.3), (0, 0, 3.85)], 0.11, n=10, caps="round"), crease=60)
    L["piece"](p, Q["rim"], L["tube"]([(-0.22, 0, 3.62), (0.22, 0, 3.62)], 0.11, n=10, caps="round"), crease=60)
    # pearls on the five tips, a darker band round the base
    for i in range(5):
        a = -math.pi / 2 + 2 * math.pi * i / 5
        L["piece"](p, Q["pearl"], L["ball"]((2.06 * math.cos(a), 2.06 * math.sin(a), top + 0.2), 0.36, seg=6),
                   crease=60)
    L["piece"](p, Q["gold_d"], IC["torus"]((0, 0, 0.42), 2.14, 0.26, n=64, m=10, axis="z"), crease=60)
    # jewels: rubies, sapphires and emeralds round the band, a big ruby on the front spike
    for deg, paint, r in ((-90, Q["ruby"], 0.36), (-50, Q["sapphire"], 0.28), (-130, Q["sapphire"], 0.28),
                          (-10, Q["emerald"], 0.26), (-170, Q["emerald"], 0.26), (30, Q["ruby"], 0.26),
                          (150, Q["ruby"], 0.26)):
        a = math.radians(deg)
        n = [math.cos(a), math.sin(a), 0.0]
        ST["gem"](p, (2.36 * n[0], 2.36 * n[1], 0.42), n, r, 0.5 * r, paint, facets=8)
    for deg, paint, z, r in ((-90, Q["ruby"], 2.05, 0.42), (-18, Q["sapphire"], 1.95, 0.3),
                             (-162, Q["sapphire"], 1.95, 0.3)):
        a = math.radians(deg)
        n = [math.cos(a), math.sin(a), 0.12]
        ST["gem"](p, (2.2 * n[0], 2.2 * n[1], z), n, r, 0.55 * r, paint, facets=8)
    return p


def double_volts():
    p = ST["new_store"]("DoubleVolts", 1)
    # a tall stack behind on the left, a shorter one on the right, a low one in front
    ST["coin_stack"](p, (-1.1, 0.55, 0.0), 9, r=1.0, h=0.34, seed=3)
    ST["coin_stack"](p, (1.2, 0.75, 0.0), 6, r=1.0, h=0.34, seed=7)
    ST["coin_stack"](p, (-0.05, -1.05, 0.0), 3, r=0.95, h=0.34, seed=11)
    # a big coin flipping up in front of the stacks, both faces embossed
    ST["coin"](p, (0.95, -0.7, 3.15), L["v_norm"]([-0.3, -0.9, 0.32]), r=1.3, thick=0.44, spin=-12, back=True)
    # two coins leaning against the stacks
    ST["coin"](p, (-2.05, -0.45, 0.82), L["v_norm"]([-0.25, -0.75, 0.6]), r=0.8, thick=0.3, spin=20)
    ST["coin"](p, (2.2, -0.35, 0.78), L["v_norm"]([0.35, -0.8, 0.5]), r=0.75, thick=0.3, spin=15)
    return p


result = {"built": [L["report"](f()) for f in (vip, double_volts)]}

# ===== chunk 4/12: DoubleEnergy (glowing drop), MegaTank and InfiniteTank (storm tanks) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def drop_profile(r0=1.75, tip=5.0):
    """Lathe profile of a plump raindrop: a ball r0 at the bottom pulling up into a soft tip at `tip`."""
    phi0 = math.radians(32)
    prof = [(0.0, 0.0)]
    for k in range(1, 12):
        a = -math.pi / 2 + (phi0 + math.pi / 2) * k / 11
        prof.append((r0 * math.cos(a), r0 + r0 * math.sin(a)))
    p0 = (r0 * math.cos(phi0), r0 + r0 * math.sin(phi0))
    c1 = (p0[0] - 0.61 * r0 * math.sin(phi0), p0[1] + 0.61 * r0 * math.cos(phi0))
    end = (0.1 * r0, tip - 0.07 * r0)
    for k in range(1, 10):
        t = k / 9.0
        prof.append(((1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * c1[0] + t * t * end[0],
                     (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * c1[1] + t * t * end[1]))
    return prof + [(0.06 * r0, tip - 0.03 * r0), (0.0, tip)]


def double_energy():
    p = ST["new_store"]("DoubleEnergy", 2)
    prof = drop_profile(1.75, 5.0)
    L["piece"](p, P["rain"], L["lathe"](prof, n=48), crease=60)
    # a big bolt embossed on the front, bent onto the drop
    bolt = IC["slab"](IC["rot2"](IC["bolt_shape"](2.85), -6), 0.5, 0.11, y=-0.25, z=2.0, corner=0.27)
    L["piece"](p, Q["rim"], ST["wrap"](bolt, prof, sink=0.14), crease=50)
    L["piece"](p, Q["shine"], IC["decal"]((-0.95, -1.22, 2.65), [-0.6, -0.78, 0.2], 0.18, 0.5, 0.08, sink=0.02,
                                          spin=-25), crease=60)
    # a crackling energy ring round the drop and two little droplets splashing off it
    ring = L["rotate"](L["rotate"](IC["torus"]((0, 0, 0), 2.55, 0.16, n=64, m=10, axis="z"), "x", 64), "y", -22)
    L["piece"](p, Q["rim"], L["move"](ring, (0.0, 0.0, 1.95)), crease=60)
    for x, z, s, tilt in ((-2.15, 3.55, 0.3, 26), (2.25, 0.95, 0.24, -30)):
        small = L["lathe"]([(q[0] * s, q[1] * s) for q in prof], n=24)
        L["piece"](p, P["rain"], L["move"](L["rotate"](small, "y", tilt), (x, -0.4, z)), crease=60)
    return p


def tank(p, liquid, level, lid=True, glass="Glass_9FE3FF", cap="Color_EEF0FF", trim=None):
    """A chunky storm tank: white-lavender end caps with gold trim, a glass drum on steel posts, glowing
    liquid up to `level` (0..1) with bubbles; lid = a closed top with a valve wheel."""
    trim = trim or Q["rim"]
    L["piece"](p, cap, L["puck"]((0, 0, 0), 2.0, 0.8, 0.32, n=48), crease=50)
    L["piece"](p, trim, IC["torus"]((0, 0, 0.62), 1.86, 0.12, n=56, m=8, axis="z"), crease=60)
    for i in range(10):
        a = math.radians(-90 + 18 + 36 * i)
        L["piece"](p, Q["steel_d"], L["ball"]((2.0 * math.cos(a), 2.0 * math.sin(a), 0.36), 0.1, seg=3), crease=60)
    L["piece"](p, glass, L["lathe"]([(0.0, 0.7), (1.62, 0.7), (1.66, 1.0), (1.66, 4.0), (1.62, 4.3), (0.0, 4.3)],
                                    n=48), crease=60)
    top = 0.8 + 3.3 * level
    L["piece"](p, liquid, L["lathe"]([(0.0, 0.78), (1.5, 0.78), (1.54, 1.0), (1.54, top - 0.12), (1.46, top),
                                      (0.0, top)], n=48), crease=60)
    for x, z, r in ((-0.6, 1.5, 0.2), (0.35, 2.2, 0.15), (0.75, 1.25, 0.12), (-0.2, 2.75, 0.1), (0.9, 3.0, 0.13)):
        if z + r < top:
            L["piece"](p, Q["shine"], L["ball"]((x, -1.3, z), r, seg=4), crease=60)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        q = (1.82 * math.cos(a), 1.82 * math.sin(a))
        L["piece"](p, Q["steel"], L["tube"]([(q[0], q[1], 0.7), (q[0], q[1], 4.3)], 0.16, n=12, caps="flat"),
                   crease=60)
        L["piece"](p, Q["steel_d"], L["ball"]((q[0], q[1], 0.66), 0.22, seg=4), crease=60)
    if lid:
        L["piece"](p, cap, L["puck"]((0, 0, 4.2), 2.0, 0.8, 0.32, n=48), crease=50)
        L["piece"](p, trim, IC["torus"]((0, 0, 4.38), 1.86, 0.12, n=56, m=8, axis="z"), crease=60)
        L["piece"](p, Q["steel"], L["puck"]((0, 0, 4.95), 1.05, 0.4, 0.16, n=36), crease=50)
        L["piece"](p, Q["steel_d"], L["tube"]([(0, 0, 5.3), (0, 0, 5.75)], 0.18, n=12, caps="flat"), crease=60)
        L["piece"](p, P["coral"], IC["torus"]((0, 0, 5.78), 0.62, 0.13, n=32, m=8, axis="z"), crease=60)
        for k in range(3):
            a = math.radians(30 + 120 * k)
            L["piece"](p, P["coral"], L["tube"]([(0, 0, 5.78), (0.6 * math.cos(a), 0.6 * math.sin(a), 5.78)],
                                                0.08, n=8, caps="round"), crease=60)
    return top


def mega_tank():
    p = ST["new_store"]("MegaTank", 3)
    tank(p, "Neon_19C3FF", 0.82)
    # a gold bolt badge on the front of the lid
    ST["coin"](p, (0.0, -1.95, 4.6), [0, -1, 0.05], r=0.62, thick=0.26)
    return p


def lemniscate(a, n=64):
    """The infinity sign: a closed figure-eight about 2a wide in the XZ plane."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        d = 1.0 + math.sin(t) ** 2
        pts.append((a * math.cos(t) / d, 0.0, a * math.sin(t) * math.cos(t) / d))
    return pts


def infinite_tank():
    p = ST["new_store"]("InfiniteTank", 4)
    tank(p, "Neon_A65CFF", 0.97)
    # a big gold infinity sign floating in front of the tank
    sign = L["rotate"](IC["sweep"](lemniscate(2.45), 0.42, n=18, closed=True, flat=0.7), "x", -10)
    L["piece"](p, Q["gold"], L["move"](sign, (0.0, -2.45, 1.75)), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (double_energy, mega_tank, infinite_tank)]}

# ===== chunk 5/12: RemoteSell (remote control beaming coins), StormRadar (radar scope with a sweep) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def remote_sell():
    p = ST["new_store"]("RemoteSell", 5)
    lean = lambda m: L["move"](L["rotate"](L["rotate"](m, "x", -16), "y", 14), (-0.9, 0.3, 0.2))
    # a chunky handheld remote: sky body, white face plate, a little screen, a big sell button and keys
    L["piece"](p, P["sky_d"], lean(L["rounded_box"]((0, 0, 2.0), [2.1, 0.95, 4.0], 0.42, seg=3)), crease=40)
    L["piece"](p, P["cloud"], lean(L["rounded_box"]((0, -0.42, 2.0), [1.66, 0.3, 3.5], 0.14, seg=2)), crease=40)
    L["piece"](p, P["ink"], lean(L["rounded_box"]((0, -0.58, 3.25), [1.26, 0.12, 0.66], 0.1, seg=2)), crease=40)
    L["piece"](p, "Neon_7DFFB0", lean(L["rounded_box"]((-0.18, -0.63, 3.25), [0.72, 0.06, 0.22], 0.05, seg=1)),
               crease=40)
    L["piece"](p, P["leaf"], lean(IC["disc"]((0, -0.68, 2.2), 0.52, 0.34, 0.13, n=32)), crease=50)
    L["piece"](p, Q["rim"], lean(IC["slab"](IC["bolt_shape"](0.62), 0.16, 0.04, y=-0.86, z=2.2, corner=0.06)),
               crease=50)
    for i, (x, z) in enumerate(((-0.42, 1.25), (0.0, 1.25), (0.42, 1.25), (-0.42, 0.78), (0.0, 0.78), (0.42, 0.78))):
        paint = P["coral"] if i == 2 else P["steel"]
        L["piece"](p, paint, lean(L["rounded_box"]((x, -0.6, z), [0.3, 0.16, 0.26], 0.07, seg=2)), crease=40)
    # the antenna and its radio waves
    L["piece"](p, P["inksoft"], lean(L["tube"]([(0.62, 0, 3.9), (0.78, 0, 5.15)], 0.1, n=10, caps="flat")),
               crease=60)
    L["piece"](p, P["coral"], lean(L["ball"]((0.8, 0, 5.3), 0.24, seg=5)), crease=60)
    tip = lean(L["ball"]((0.8, 0, 5.3), 0.01, seg=1))["v"][0]
    for rr in (0.75, 1.3, 1.85):
        arc = [(tip[0] + rr * math.cos(math.radians(a)), tip[1] - 0.2, tip[2] + rr * math.sin(math.radians(a)))
               for a in range(-15, 76, 9)]
        L["piece"](p, P["white"], IC["sweep"](arc, 0.15, n=10, closed=False, flat=0.7), crease=60)
    # coins flying out to the right
    for (x, y, z), n, r, spin in (((2.35, -0.3, 3.0), [0.45, -0.8, 0.4], 0.62, -20),
                                  ((2.0, -0.6, 1.25), [0.2, -0.9, 0.38], 0.72, 10),
                                  ((3.15, 0.1, 4.55), [0.6, -0.6, 0.5], 0.5, -35)):
        ST["coin"](p, (x, y, z), L["v_norm"](n), r=r, thick=0.24, spin=spin, back=True, n=32)
    return p


def pie(r, a0, a1, steps=12):
    """2D pie slice outline (counter-clockwise) of radius r from angle a0 to a1 (degrees)."""
    pts = [[0.0, 0.0]]
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        pts.append([r * math.cos(a), r * math.sin(a)])
    return pts


def storm_radar():
    p = ST["new_store"]("StormRadar", 6)
    tilt = lambda m: L["move"](L["rotate"](m, "x", 28), (0.0, 0.2, 2.45))
    # the scope: a thick steel housing, a dark screen, glowing rings and a crosshair
    L["piece"](p, Q["steel"], tilt(IC["disc"]((0, 0, 0), 2.4, 1.0, 0.36, n=56)), crease=50)
    L["piece"](p, Q["steel_d"], tilt(IC["torus"]((0, -0.5, 0), 2.08, 0.16, n=56, m=8)), crease=60)
    L["piece"](p, "Color_0E4A55", tilt(IC["disc"]((0, -0.46, 0), 1.98, 0.2, 0.06, n=56)), crease=50)
    for rr in (0.7, 1.35):
        L["piece"](p, "Neon_6DFFD2", tilt(IC["torus"]((0, -0.56, 0), rr, 0.045, n=48, m=6)), crease=60)
    for a in (0, 90):
        L["piece"](p, "Neon_6DFFD2", tilt(L["rotate"](L["tube"]([(-1.9, -0.56, 0), (1.9, -0.56, 0)], 0.04, n=6,
                                                                 caps="flat"), "y", a)), crease=60)
    # the sweep: a see-through green wedge with a bright leading edge
    L["piece"](p, "Glass_5DFFC8", tilt(IC["slab"](pie(1.92, 20, 78), 0.1, 0.0, y=-0.6, seg=1)), crease=30)
    L["piece"](p, "Neon_D9FFF0", tilt(L["tube"]([(0, -0.64, 0), (1.92 * math.cos(math.radians(78)), -0.64,
                                                  1.92 * math.sin(math.radians(78)))], 0.07, n=8, caps="round")),
               crease=60)
    L["piece"](p, "Neon_D9FFF0", tilt(L["ball"]((0, -0.62, 0), 0.16, seg=4)), crease=60)
    # blips: a red rare-weather ping with its ring, two yellow ones
    L["piece"](p, "Neon_FF4D7A", tilt(L["ball"]((0.95, -0.62, 0.62), 0.2, seg=4)), crease=60)
    L["piece"](p, P["coral"], tilt(IC["torus"]((0.95, -0.62, 0.62), 0.42, 0.06, n=32, m=6)), crease=60)
    for x, z in ((-0.85, -0.6), (-0.3, 1.05)):
        L["piece"](p, "Neon_FFE36B", tilt(L["ball"]((x, -0.62, z), 0.14, seg=4)), crease=60)
    # a little storm cloud popping out of the red ping
    ping = tilt(L["ball"]((0.95, -0.62, 0.62), 0.01, seg=1))["v"][0]
    ST["cloud"](p, (ping[0] + 0.45, ping[1] - 0.5, ping[2] + 1.45), 0.36, "Color_8A72EC", seed=5)
    bolt = IC["rot2"](IC["bolt_shape"](0.8), -10)
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.24, 0.05, y=ping[1] - 0.85, x=ping[0] + 0.45, z=ping[2] + 1.05,
                                        corner=0.08), crease=50)
    # a stand under the scope
    L["piece"](p, Q["steel_d"], L["puck"]((0, 0.4, 0), 1.4, 0.4, 0.16, n=40), crease=50)
    L["piece"](p, Q["steel_d"], L["tube"]([(0, 0.45, 0.3), (0, 0.45, 1.2)], 0.36, n=16, caps="flat"), crease=60)
    return p


result = {"built": [L["report"](f()) for f in (remote_sell, storm_radar)]}

# ===== chunk 6/12: LuckyHatcher (egg and clover), TripleHatch (nest of three eggs), AutoHatch (egg in arrows) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]
SPOTS = [(2.2, -96, 0.5), (1.45, -50, 0.42), (1.35, -136, 0.38), (0.8, -86, 0.36), (1.95, -10, 0.34),
         (2.6, -150, 0.3), (0.95, -24, 0.3), (1.9, -172, 0.32), (2.7, -60, 0.26), (0.7, -150, 0.3)]


def lucky_hatcher():
    p = ST["new_store"]("LuckyHatcher", 7)
    spots = [s + (("Color_FFB21E",) if i % 3 == 1 else ()) for i, s in enumerate(SPOTS)]
    ST["egg"](p, (-0.45, 0.2, 0.0), 5.0, 1.85, "Color_F7FAFF", P["sky"], spots, lean=(-6, 0), spin=8)
    # a lucky four-leaf clover in front, a little gold star beside it
    ST["put"](p, ST["clover_parts"](0.62), L["v_norm"]([0.25, -0.9, 0.25]), (1.45, -1.25, 1.75), spin=-12)
    star = L["round_poly"](L["star_poly"](5, 0.62, 0.3), 0.08, seg=2)
    L["piece"](p, P["bolt"], IC["pillow"](IC["move2"](star, -2.25, 3.95), 0.36, center=(0, -0.6, 0), rings=4),
               crease=60)
    return p


def nest(p, c, r=2.45, straw="Color_D9A250", straw_l="Color_F0C470"):
    """A round straw nest: a fat ring, a bowl inside and loose straws wrapped round it."""
    L["piece"](p, straw, IC["torus"]((c[0], c[1], c[2] + 0.62), r, 0.72, n=56, m=12, axis="z"), crease=60)
    L["piece"](p, straw, L["puck"]((c[0], c[1], c[2]), r, 0.55, 0.25, n=48), crease=50)
    rnd = L["rng"](9)
    for i in range(22):
        a0 = 2 * math.pi * i / 22 + rnd() * 0.2
        span, lift, side = 0.55 + 0.35 * rnd(), rnd() * 0.5 - 0.25, 1 if i % 2 else -1
        path = []
        for k in range(7):
            a = a0 + span * k / 6
            b = math.pi * (k / 6.0) * side + lift
            path.append((c[0] + (r + 0.78 * math.cos(b)) * math.cos(a), c[1] + (r + 0.78 * math.cos(b)) * math.sin(a),
                         c[2] + 0.62 + 0.78 * math.sin(b)))
        L["piece"](p, straw_l, L["tube"](path, 0.07, n=6, caps="round"), crease=60)


def triple_hatch():
    p = ST["new_store"]("TripleHatch", 8)
    nest(p, (0.0, 0.0, 0.0))
    ST["egg"](p, (-1.45, -0.2, 0.45), 3.5, 1.3, P["leaf_l"], P["bolt"], SPOTS, lean=(-20, 4), spin=20)
    ST["egg"](p, (1.5, -0.25, 0.45), 3.4, 1.27, P["sky_l"], P["white"], SPOTS, lean=(19, 4), spin=-15)
    ST["egg"](p, (0.0, 0.35, 0.55), 4.1, 1.5, P["bolt"], P["cream"], SPOTS, lean=(0, 3))
    return p


def ring_path(rr, a0, a1, steps=18, center=(0.0, 0.0, 0.0), tilt=(16, -18)):
    """Points of an arc of radius rr (degrees a0 -> a1) in the front plane, tilted back by tilt[0] and turned
    by tilt[1] degrees, around `center`."""
    pts = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        q = L["rot_point"](L["rot_point"]([rr * math.cos(a), 0.0, rr * math.sin(a)], "x", tilt[0]), "z", tilt[1])
        pts.append((center[0] + q[0], center[1] + q[1], center[2] + q[2]))
    return pts


def auto_hatch():
    p = ST["new_store"]("AutoHatch", 9)
    ST["egg"](p, (0.0, 0.0, 0.0), 4.4, 1.62, P["pink"], P["white"], SPOTS, lean=(4, 0), spin=-10)
    # two fat white arrows chasing each other round the egg
    for a0, a1 in ((200, 335), (20, 155)):
        ST["arrow"](p, ring_path(2.55, a0, a1, center=(0.0, 0.3, 2.2)), 0.3, P["white"], head=2.1)
    return p


result = {"built": [L["report"](f()) for f in (lucky_hatcher, triple_hatch, auto_hatch)]}

# ===== chunk 7/12: coin heaps, VoltsSmall (pouch of volts), VoltsMedium (bag of volts) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def heap(p, c, rx, h, count, seed=1, r=0.5, ry=None, inner=None):
    """A mound of coins: a gold dome (rx wide, ry deep, h high, centred on c at its foot) covered in coins
    lying along its surface at slightly random tilts."""
    ry = ry or rx
    L["piece"](p, inner or Q["gold_d"], L["ball"](c, [rx, ry, h], seg=8, shape=None), crease=60)
    rnd = L["rng"](seed)
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        z = 1.0 - (i + 0.5) / count * 0.92
        rho = math.sqrt(max(0.0, 1 - z * z))
        a = golden * i + rnd() * 0.3
        d = [rho * math.cos(a), rho * math.sin(a), z]
        at = (c[0] + rx * d[0], c[1] + ry * d[1], c[2] + h * d[2])
        n = L["v_norm"]([d[0] / rx + (rnd() - 0.5) * 0.5, d[1] / ry + (rnd() - 0.5) * 0.5, d[2] / h + 0.3])
        ST["coin"](p, at, n, r=r * (0.85 + 0.3 * rnd()), thick=0.18, spin=rnd() * 360,
                   body=Q["gold"] if i % 2 else Q["gold2"], n=24, rim=False)


def sack(paint, s=1.0, ruffle=0.14):
    """A fat cloth sack (round belly, cinched neck, ruffled top), about 4.3 * s tall."""
    prof = IC["smooth_profile"]([(0.0, 0.0), (1.0, 0.04), (1.65, 0.38), (1.95, 1.0), (1.92, 1.7), (1.6, 2.35),
                                 (1.05, 2.85), (0.66, 3.15), (0.55, 3.32), (0.72, 3.5), (1.05, 3.72), (1.18, 3.95),
                                 (0.95, 4.15), (0.45, 4.26), (0.0, 4.3)], steps=3)

    def fold(q):
        a = math.atan2(q[1], q[0])
        w = math.cos(6 * a + 0.6)
        f = 1.0 + ruffle * w * L["smoothstep"](3.35, 3.85, q[2])
        lift = 0.16 * w * L["smoothstep"](3.7, 4.05, q[2]) * min(1.0, math.hypot(q[0], q[1]) / 0.9)
        return [q[0] * f * s, q[1] * f * s, (q[2] + lift) * s]

    return L["warp"](L["lathe"](prof, n=60), fold)


def volts_small():
    p = ST["new_store"]("VoltsSmall", 10)
    # a little sky-blue pouch tied with a gold cord, a gold bolt patch, a coin peeking out of its top
    L["piece"](p, P["sky"], L["move"](sack(P["sky"], 0.9), (0.0, 0.3, 0.0)), crease=60)
    L["piece"](p, Q["rim"], IC["torus"]((0, 0.3, 2.98), 0.6, 0.17, n=32, m=10, axis="z"), crease=60)
    L["piece"](p, Q["rim"], L["tube"]([(0.45, -0.2, 2.95), (0.75, -0.45, 2.45), (0.7, -0.6, 1.95)], 0.1, n=8,
                                      caps="round"), crease=60)
    L["piece"](p, Q["rim"], L["ball"]((0.7, -0.62, 1.9), 0.2, seg=4), crease=60)
    L["piece"](p, Q["gold"], ST["wrap"](IC["slab"](IC["bolt_shape"](1.75), 0.4, 0.09, y=-0.2, z=1.45, x=-0.15,
                                                    corner=0.18), [(1.75 * q[0], q[1]) for q in
                                                                   [(1.0, 0.0), (1.08, 0.9), (1.05, 1.6), (0.9, 2.2)]],
                                         center=(0.0, 0.3), sink=0.1), crease=50)
    ST["coin"](p, (0.25, 0.25, 3.85), L["v_norm"]([0.1, -0.7, 0.6]), r=0.6, thick=0.22, spin=10)
    # three coins spilled in front
    ST["coin"](p, (-1.55, -0.95, 0.12), [0, 0, 1], r=0.62, thick=0.24, spin=-8)
    ST["coin"](p, (1.65, -0.75, 0.62), L["v_norm"]([0.3, -0.8, 0.45]), r=0.7, thick=0.26, spin=8)
    ST["coin"](p, (-1.55, -0.95, 0.36), [0, 0, 1], r=0.55, thick=0.24, spin=12)
    return p


def open_sack(s=1.0):
    """A fat cloth sack with its neck tied and its top folded open into a wavy mouth (about 3.9 * s tall);
    the mouth's floor is at 3.35 * s, for a heap of coins."""
    prof = IC["smooth_profile"]([(0.0, 0.0), (1.0, 0.04), (1.65, 0.38), (1.95, 1.0), (1.92, 1.7), (1.6, 2.35),
                                 (1.12, 2.82), (0.92, 3.05), (1.02, 3.3), (1.38, 3.62), (1.56, 3.84), (1.5, 3.94),
                                 (1.3, 3.8), (1.0, 3.5), (0.0, 3.35)], steps=3)

    def fold(q):
        w = math.cos(6 * math.atan2(q[1], q[0]) + 0.6)
        lip = L["smoothstep"](3.25, 3.85, q[2])
        return [q[0] * (1.0 + 0.1 * w * lip) * s, q[1] * (1.0 + 0.1 * w * lip) * s, (q[2] + 0.18 * w * lip) * s]

    return L["warp"](L["lathe"](prof, n=60), fold)


def volts_medium():
    p = ST["new_store"]("VoltsMedium", 11)
    # a big money sack folded open, a heap of coins in its mouth, a few more spilled around it
    L["piece"](p, P["leaf"], L["move"](open_sack(1.15), (0.0, 0.3, 0.0)), crease=60)
    L["piece"](p, Q["rim"], IC["torus"]((0, 0.3, 3.45), 1.1, 0.2, n=40, m=10, axis="z"), crease=60)
    heap(p, (0.0, 0.3, 3.75), 1.45, 0.85, 14, seed=4, r=0.44)
    L["piece"](p, Q["rim"], IC["slab"](IC["bolt_shape"](2.3), 0.9, 0.15, y=-1.95, z=1.75, x=-0.15, corner=0.25),
               crease=50)
    ST["coin_stack"](p, (-2.05, -0.6, 0.0), 4, r=0.75, h=0.28, seed=5)
    ST["coin"](p, (1.95, -0.9, 0.7), L["v_norm"]([0.35, -0.8, 0.45]), r=0.75, thick=0.26, spin=10)
    ST["coin"](p, (0.6, -2.1, 0.12), [0, 0, 1], r=0.6, thick=0.24, spin=-20)
    return p


ST.update({"heap": heap, "sack": sack, "open_sack": open_sack})
result = {"built": [L["report"](f()) for f in (volts_small, volts_medium)]}

# ===== chunk 8/12: VoltsLarge (crate of volts), VoltsHuge (vault of volts) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def crate(p, c, w=4.2, d=3.1, h=2.7):
    """A wooden crate (planks between darker corner posts, gold corner caps), open on top."""
    x0, y0, z0 = c
    for k in range(3):
        z = z0 + 0.25 + (h - 0.3) * (k + 0.5) / 3
        ph = (h - 0.3) / 3 - 0.08
        for sy in (-1, 1):
            L["piece"](p, Q["wood"], L["rounded_box"]((x0, y0 + sy * (d / 2 - 0.12), z), [w - 0.5, 0.26, ph], 0.08,
                                                      seg=2), crease=40)
        for sx in (-1, 1):
            L["piece"](p, Q["wood"], L["rounded_box"]((x0 + sx * (w / 2 - 0.12), y0, z), [0.26, d - 0.5, ph], 0.08,
                                                      seg=2), crease=40)
    L["piece"](p, Q["wood_d"], L["rounded_box"]((x0, y0, z0 + 0.15), [w - 0.2, d - 0.2, 0.3], 0.1, seg=2), crease=40)
    for sx in (-1, 1):
        for sy in (-1, 1):
            q = (x0 + sx * (w / 2 - 0.22), y0 + sy * (d / 2 - 0.22))
            L["piece"](p, Q["wood_d"], L["rounded_box"]((q[0], q[1], z0 + h / 2), [0.5, 0.5, h], 0.14, seg=2),
                       crease=40)
            for z in (z0 + 0.3, z0 + h - 0.3):
                L["piece"](p, Q["gold"], L["rounded_box"]((q[0], q[1], z), [0.62, 0.62, 0.5], 0.14, seg=2),
                           crease=40)
    # a diagonal brace across the front
    L["piece"](p, Q["wood_d"], L["tube"]([(x0 - w / 2 + 0.55, y0 - d / 2 - 0.05, z0 + 0.55),
                                          (x0 + w / 2 - 0.55, y0 - d / 2 - 0.05, z0 + h - 0.55)], 0.15, n=10,
                                         caps="round"), crease=60)


def volts_large():
    p = ST["new_store"]("VoltsLarge", 12)
    crate(p, (0.0, 0.2, 0.0))
    ST["heap"](p, (0.0, 0.2, 2.35), 2.0, 1.35, 30, seed=8, r=0.5, ry=1.45)
    # coins spilling over the front edge and stacks beside the crate
    ST["coin"](p, (-1.0, -1.45, 2.55), L["v_norm"]([-0.2, -0.85, 0.5]), r=0.6, thick=0.22, spin=-10, n=32)
    ST["coin"](p, (0.9, -1.5, 2.45), L["v_norm"]([0.25, -0.8, 0.5]), r=0.55, thick=0.22, spin=15, n=32)
    ST["coin_stack"](p, (-2.65, -1.0, 0.0), 5, r=0.7, h=0.27, seed=12)
    ST["coin_stack"](p, (2.6, -1.2, 0.0), 3, r=0.7, h=0.27, seed=13)
    ST["coin"](p, (0.2, -2.25, 0.12), [0, 0, 1], r=0.62, thick=0.24, spin=-18)
    return p


def vault(p, c, w=4.2, d=2.8, h=4.1):
    """A steel safe: rounded body with feet, a round door with a gold spoke wheel, a dial and hinges."""
    x0, y0, z0 = c
    L["piece"](p, Q["steel"], L["rounded_box"]((x0, y0, z0 + 0.25 + h / 2), [w, d, h], 0.45, seg=3), crease=40)
    for sx in (-1, 1):
        L["piece"](p, Q["steel_d"], L["rounded_box"]((x0 + sx * (w / 2 - 0.5), y0, z0 + 0.15), [0.7, d - 0.4, 0.4],
                                                     0.14, seg=2), crease=40)
    door = (x0 + 0.1, y0 - d / 2, z0 + 0.25 + h / 2)
    L["piece"](p, Q["steel_d"], IC["disc"]((door[0], door[1] - 0.05, door[2]), 1.68, 0.36, 0.14, n=56), crease=50)
    L["piece"](p, Q["steel"], IC["disc"]((door[0], door[1] - 0.22, door[2]), 1.42, 0.3, 0.12, n=56), crease=50)
    for k in range(12):
        a = 2 * math.pi * k / 12
        L["piece"](p, Q["rim"], L["ball"]((door[0] + 1.55 * math.cos(a), door[1] - 0.26, door[2] + 1.55 * math.sin(a)),
                                          0.08, seg=3), crease=60)
    hub = (door[0], door[1] - 0.6, door[2])
    L["piece"](p, Q["gold"], IC["torus"](hub, 0.85, 0.12, n=40, m=8), crease=60)
    for k in range(4):
        a = math.pi / 4 + math.pi / 2 * k
        tip = (hub[0] + 1.1 * math.cos(a), hub[1], hub[2] + 1.1 * math.sin(a))
        L["piece"](p, Q["gold"], L["tube"]([(hub[0], door[1] - 0.4, hub[2]), tip], 0.09, n=8, caps="flat"), crease=60)
        L["piece"](p, Q["rim"], L["ball"](tip, 0.18, seg=4), crease=60)
    L["piece"](p, Q["rim"], IC["disc"](hub, 0.36, 0.3, 0.1, n=32), crease=50)
    L["piece"](p, P["ink"], IC["disc"]((x0 + w / 2 - 0.55, y0 - d / 2 - 0.05, z0 + h - 0.35), 0.28, 0.2, 0.06, n=24),
               crease=50)
    for z in (door[2] - 1.0, door[2] + 1.0):
        L["piece"](p, Q["steel_d"], L["tube"]([(door[0] - 1.72, door[1] - 0.12, z - 0.32),
                                               (door[0] - 1.72, door[1] - 0.12, z + 0.32)], 0.16, n=12, caps="round"),
                   crease=60)


def volts_huge():
    p = ST["new_store"]("VoltsHuge", 13)
    vault(p, (0.0, 0.6, 0.0))
    # a big heap of coins in front of the vault, stacks and gold bars round it, coins on its roof
    ST["heap"](p, (0.0, -1.35, 0.0), 2.7, 1.25, 24, seed=21, r=0.66, ry=1.5)
    ST["coin_stack"](p, (-2.75, -0.2, 0.0), 7, r=0.72, h=0.27, seed=31)
    ST["coin_stack"](p, (2.75, -0.1, 0.0), 5, r=0.72, h=0.27, seed=32)
    ST["heap"](p, (0.3, 0.6, 4.75), 1.3, 0.6, 10, seed=33, r=0.42, ry=0.9)
    bar = L["warp"](L["rounded_box"]((0.0, 0.0, 0.32), [1.7, 0.85, 0.64], 0.12, seg=2),
                    lambda q: [q[0] * (1.0 - 0.22 * q[2] / 0.64), q[1] * (1.0 - 0.3 * q[2] / 0.64), q[2]])
    for (x, y, z), spin in (((-1.9, -2.5, 0.0), 28), ((2.0, -2.45, 0.0), -22)):
        L["piece"](p, Q["gold2"], L["move"](L["rotate"](bar, "z", spin), (x, y, z)), crease=40)
    return p


result = {"built": [L["report"](f()) for f in (volts_large, volts_huge)]}

# ===== chunk 9/12: EnergyBoost and LuckBoost (30-minute hourglasses) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def energy_boost():
    p = ST["new_store"]("EnergyBoost", 14)
    ST["hourglass"](p, (-0.55, 0.35, 0.0), sand="Neon_3FD8FF")
    # a big lightning bolt in front of the hourglass
    bolt = IC["rot2"](IC["bolt_shape"](3.3), -12)
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.75, 0.16, y=-1.55, x=1.2, z=1.75, corner=0.34), crease=50)
    return p


def luck_boost():
    p = ST["new_store"]("LuckBoost", 15)
    ST["hourglass"](p, (-0.55, 0.35, 0.0), sand="Neon_7CF56B")
    # a four-leaf clover in front of the hourglass
    ST["put"](p, ST["clover_parts"](0.6), L["v_norm"]([0.2, -0.9, 0.3]), (1.2, -1.45, 2.15), spin=-10)
    return p


result = {"built": [L["report"](f()) for f in (energy_boost, luck_boost)]}

# ===== chunk 10/12: SummonMegaStorm (tornado under a thundercloud), AutoCatch (the cloud and the suction beam) =====
L = session_state["L"]
IC = session_state["IC"]
ST = session_state["ST"]
P, Q = IC["P"], ST["Q"]


def summon_mega_storm():
    p = ST["new_store"]("SummonMegaStorm", 16)
    # the funnel: stacked rings getting wider towards the top, swaying, in two purples
    bands = 9
    for i in range(bands):
        t = i / (bands - 1.0)
        z = 0.35 + 3.9 * t
        rr = 0.3 + 1.45 * t ** 1.2
        sway = 0.5 * math.sin(t * 3.3 + 0.4) * (1.0 - 0.6 * t)
        paint = P["storm_l"] if i % 2 == 0 else "Color_A88BFF"
        L["piece"](p, paint, IC["torus"]((sway, 0.0, z), rr, 0.25 + 0.1 * t, n=48, m=10, axis="z", squash=1.25),
                   crease=60)
    L["piece"](p, P["storm_d"], L["lathe"]([(0.0, 0.0), (0.3, 0.1), (0.5, 0.5), (0.0, 0.6)], n=24,
                                           center=(0.5 * math.sin(0.4), 0.0, 0.0)), crease=60)
    # wind streaks wrapped round the front of the funnel
    for z, rr, a0, a1 in ((1.3, 1.05, 205, 300), (2.5, 1.55, 235, 335), (3.5, 2.0, 200, 285)):
        arc = [(rr * math.cos(math.radians(a)), rr * math.sin(math.radians(a)), z + 0.25 * math.sin(math.radians(a)))
               for a in range(a0, a1 + 1, 6)]
        L["piece"](p, P["white"], L["tube"](arc, 0.1, n=8, caps="round"), crease=60)
    # a wide, dark thundercloud on top: a flat base under a row of puffs
    top, under = "Color_8A72EC", "Color_6447C9"
    L["piece"](p, under, L["rounded_box"]((0.0, 0.2, 4.9), [6.0, 2.7, 1.2], 0.58, seg=3), crease=40)
    for (x, y, z), r in (((-2.3, 0.25, 5.35), 0.95), ((-1.2, 0.4, 5.85), 1.25), ((0.2, 0.45, 6.05), 1.4),
                         ((1.55, 0.35, 5.75), 1.2), ((2.5, 0.2, 5.3), 0.9), ((-0.6, -0.35, 5.35), 1.0),
                         ((0.95, -0.35, 5.3), 1.0)):
        L["piece"](p, top, L["blob"]((x, y, z), r, squash=0.85, lump=0.04, seed=6, seg=7), crease=60)
    for x, z, s, rot in ((-2.6, 2.85, 2.1, 12), (2.7, 2.45, 1.8, -14)):
        L["piece"](p, P["bolt"], IC["slab"](IC["rot2"](IC["bolt_shape"](s), rot), 0.5, 0.12, y=-0.7, x=x, z=z,
                                            corner=0.2), crease=50)
    return p


# AutoCatch: the vacuum gun itself is the game's own (tools/world/sketchup/gear.py, prop VacuumGun), placed by
# tools/icons/store_scenes.py (GUN: x2.3, barrel turned to +X and raised 32 degrees, grip at (-2.4, 0, 0.6)), so
# its nozzle mouth is at about (2.16, 0.0, 5.24). This model holds what it catches: a cloud and a glowing beam.
NOZZLE = (2.16, 0.0, 5.24)
AIM = L["v_norm"]([math.cos(math.radians(32)), 0.0, math.sin(math.radians(32))])


def auto_catch():
    p = ST["new_store"]("AutoCatch", 17)
    far = L["v_add"](NOZZLE, L["v_mul"](AIM, 3.1))
    ST["cloud"](p, (far[0] + 0.7, far[1] + 0.3, far[2] + 0.7), 1.2, P["white"], seed=3, flat=P["cloud"])
    beam = L["lathe"]([(0.0, 0.0), (0.66, 0.0), (1.65, 3.0), (0.0, 3.0)], n=40)
    L["piece"](p, "Glass_8FF0FF", IC["align"](beam, AIM, L["v_add"](NOZZLE, L["v_mul"](AIM, 0.1))), crease=60)
    # raindrops and a little bolt being pulled into the nozzle
    for k, s in ((1.2, 0.22), (2.1, 0.28), (2.8, 0.2)):
        c = L["v_add"](NOZZLE, L["v_mul"](AIM, k))
        off = 0.35 if k != 2.1 else -0.4
        L["piece"](p, P["rain"], L["ball"]((c[0], c[1] - 0.2, c[2] + off), [s, s, s * 1.3], seg=4), crease=60)
    bolt = IC["rot2"](IC["bolt_shape"](0.9), 30)
    c = L["v_add"](NOZZLE, L["v_mul"](AIM, 1.7))
    L["piece"](p, P["bolt"], IC["slab"](bolt, 0.25, 0.05, y=c[1] - 0.3, x=c[0], z=c[2] - 0.25, corner=0.08),
               crease=50)
    return p


result = {"built": [L["report"](f()) for f in (summon_mega_storm, auto_catch)]}
