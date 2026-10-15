# Storm Catcher Simulator - prop kit, category "common" (tools/world/sketchup/common.py)
#
# Build scripts for the props every biome uses. Send lib.py first (all its chunks), then each
# "# ===== chunk" block below as one build_model call. Units: studs (piece() converts to inches),
# Z up, front -Y, origin at the centre of the prop's base. Each prop gets a layout slot (x, y) so
# the props sit side by side in the SketchUp model.

# ===== chunk 1/3: TreeRound - chunky cartoon tree =====
L = session_state["L"]
CAT = "common"


def tree_round():
    p = L["new_prop"]("TreeRound", 0, 0, {"Primary": "4CC552", "Secondary": "8EE36B"}, solid=True, category=CAT)
    # Trunk: short, chunky, tapered and a little bent, with a root flare that splits into five
    # soft root bumps (25 segments = 5 per bump)
    trunk = L["lathe"]([(2.3, -0.3), (2.15, 0.08), (1.7, 0.6), (1.38, 1.3), (1.22, 2.3, 0.04),
                        (1.13, 3.4, 0.12, 0.02), (1.06, 4.5, 0.24, 0.05), (1.0, 6.0, 0.38, 0.08)], n=25)

    def roots(q):
        a = math.atan2(q[1], q[0])
        bump = max(0.0, math.cos(5 * a + 0.4)) ** 2
        k = 1.0 + 0.34 * bump * (1.0 - L["smoothstep"](-0.3, 1.6, q[2]))
        return [q[0] * k, q[1] * k, q[2]]

    L["piece"](p, "Color_A8724C", L["warp"](trunk, roots), crease=50, collide=True)
    # Canopy: a big puff, two side puffs and a lighter puff catching the sun on the upper front
    puffs = [((0.1, 0.45, 8.75), 4.2, 0.9, 11, 7), ((-3.05, 1.35, 7.15), 2.85, 0.88, 12, 6),
             ((2.95, -1.05, 7.4), 2.95, 0.88, 13, 6)]
    for c, r, sq, seed, seg in puffs:
        L["piece"](p, "Primary", L["blob"](c, r, squash=sq, lump=0.045, seed=seed, seg=seg), collide=False)
    L["piece"](p, "Secondary", L["blob"]((-0.85, -1.75, 10.75), 2.75, squash=0.88, lump=0.04, seed=14, seg=6),
               collide=False)
    return p


result = {"built": [L["report"](tree_round())]}

# ===== chunk 2/3: RockCluster - two boulders and a pebble =====
L = session_state["L"]
CAT = "common"


def boulder(center, radius, height, seed, sides=5, shoulders=3, soft=0.5, seg=9, squat=0.7, lean=(0.0, 0.0)):
    """A chunky faceted stone for rock(): a tilted top, near-upright sides leaning in a little,
    big shoulder bevels between them, and a flat base buried 0.5 studs under the ground."""
    r = L["rng"](seed)
    spin = 2 * math.pi * r()
    top = height - center[2]
    planes = [[[lean[0] + 0.2 * (r() - 0.5), lean[1] + 0.2 * (r() - 0.5), 1.0], top]]
    for k in range(sides):
        a = spin + 2 * math.pi * (k + 0.35 * (r() - 0.5)) / sides
        planes.append([[math.cos(a), math.sin(a), 0.18 + 0.24 * r()], radius * (0.9 + 0.16 * r())])
    for k in range(shoulders):
        b = spin + 2 * math.pi * (k + 0.5 + 0.3 * (r() - 0.5)) / shoulders
        lift = 1.0 + 0.6 * r()
        s, c = 1.0 / math.sqrt(1 + lift * lift), lift / math.sqrt(1 + lift * lift)
        planes.append([[math.cos(b), math.sin(b), lift], (radius * s + top * c) * (0.8 + 0.06 * r())])
    planes.append([[0.0, 0.0, -1.0], center[2] + radius])
    return L["rock"](center, planes, soft, seg, stretch=(1.0, 1.0, squat), floor=-0.5)


def rock_cluster():
    p = L["new_prop"]("RockCluster", 14, 0, {"Primary": "959ECB", "Secondary": "B9C0E8"}, solid=True, category=CAT)
    L["piece"](p, "Primary", boulder((-0.5, 0.5, 1.35), 2.7, 3.4, seed=5, seg=10, lean=(-0.32, 0.12)), crease=30)
    L["piece"](p, "Secondary", boulder((2.4, -1.0, 1.0), 1.55, 2.55, seed=9, soft=0.4, squat=0.85, lean=(0.25, -0.1)),
               crease=30)
    L["piece"](p, "Primary", boulder((-2.6, -2.1, 0.45), 1.05, 1.25, seed=23, sides=4, shoulders=2, soft=0.26, seg=7),
               crease=30)
    return p


result = {"built": [L["report"](rock_cluster())]}

# ===== chunk 3/3: LampPost - round post, curved arm, glowing bulb =====
L = session_state["L"]
CAT = "common"


def lamp_post():
    p = L["new_prop"]("LampPost", 26, 0, {"Primary": "5361C9", "Secondary": "FFC93C"}, solid=False, category=CAT)
    # Base: a chunky two-step plinth
    L["piece"](p, "Primary", L["puck"]((0, 0, 0), 1.4, 0.8, 0.36, n=22))
    L["piece"](p, "Primary", L["puck"]((0, 0, 0.62), 1.0, 0.72, 0.28, n=20))
    # Post: tapered round shaft
    L["piece"](p, "Primary", L["lathe"]([(0.64, 1.2), (0.58, 3.5), (0.52, 6.0), (0.48, 8.1)], n=18))
    # Trim collars
    L["piece"](p, "Secondary", L["puck"]((0, 0, 1.22), 0.8, 0.48, 0.22, n=20))
    L["piece"](p, "Secondary", L["puck"]((0, 0, 6.45), 0.68, 0.42, 0.2, n=18))
    # Curved arm (shepherd's crook) reaching out to +X, ending in the lamp head
    arc = []
    for k in range(11):
        a = math.pi * k / 10
        arc.append((1.38 - 1.38 * math.cos(a), 0.0, 8.0 + 1.38 * math.sin(a)))
    L["piece"](p, "Primary", L["tube"](arc + [(2.76, 0.0, 7.6)], 0.38, n=12, caps="flat"))
    L["piece"](p, "Secondary", L["ball"]((0.0, 0.0, 8.05), 0.56, seg=5))
    # Lamp head: a chunky dome with a rolled rim, a big glowing bulb under it
    dome = [(0.0, 7.22), (0.96, 7.22), (1.16, 7.28), (1.26, 7.42), (1.2, 7.58), (1.06, 7.7), (0.98, 7.9),
            (0.82, 8.12), (0.56, 8.3), (0.26, 8.4), (0.0, 8.43)]
    L["piece"](p, "Secondary", L["lathe"](dome, n=20, center=(2.76, 0.0, 0.0)))
    L["piece"](p, "Neon_FFF3B0", L["ball"]((2.76, 0.0, 6.72), 0.86, seg=6))
    return p


result = {"built": [L["report"](lamp_post())]}
