# Storm Catcher Simulator - 3D badge models (tools/icons/sketchup_badge_icons.py)
#
# The SketchUp parts of the Roblox badge icons (src/shared/Config/Badges.luau, docs/BADGES.md): the round
# medal every badge is built on - a scalloped seal, a fat glossy rim and an enamel face, one medal per badge
# colour - and the heroes no other icon set has: a gold trophy (Storm Champion) and a hatched egg's shell
# (First Hatch). tools/icons/badge_scenes.py adds the rest (zone scenes from the zone emblems, pets, store
# heroes), render_icons.py --set badges renders them and assets/source/badges3d.html lays out each badge.
# See tools/icons/README.md, "Badge icons".
#
# Send to SketchUp with build_model, in order: tools/world/sketchup/lib.py (4 chunks, the first with
# clean: true), chunks 1-2 of tools/icons/sketchup_icons.py (the icon helpers, session_state["IC"]), then
# every "# ===== chunk" block below (chunk 1 stores the badge helpers in session_state["BG"]), then
# tools/world/sketchup/extract.py.
#
# Contract (same as the icons): every model is a top-level group "Prop_Badge_<Name>" (category "icons") made
# of leaf groups named by paint (Color_RRGGBB, Neon_FFFFFF for shine). Units: studs, Z up, the front looks
# at -Y, origin at the centre of the base. The medal is centred on (0, 0, CZ) with the same centre and face
# plane as the zone emblems (sketchup_zone_emblems.py), so badge_scenes.py can put a zone's scene in it.
#
# Sandbox rules (checked by `python3 tools/icons/import_icons.py check`): no imports (math is
# pre-loaded), no eval/exec/open/type/setattr, no dunders, no classes, no any()/all().

# ===== chunk 1/4: badge helpers (session_state["BG"]) - colour steps, scalloped seal, the medal =====
L = session_state["L"]
IC = session_state["IC"]
BG = session_state.setdefault("BG", {})
CZ = 2.35       # height of the medal's centre (as the zone emblems)
FACE_R = 1.8    # radius of the enamel face (as the zone emblems)
SEAL_R = 2.42   # mean radius of the scalloped seal behind the rim
LOBES = 22      # scallops round the seal


def hexc(rgb):
    """[r, g, b] (0..255) -> "RRGGBB"."""
    out = ""
    for c in rgb:
        c = int(round(max(0.0, min(255.0, c))))
        out += "0123456789ABCDEF"[c // 16] + "0123456789ABCDEF"[c % 16]
    return out


def rgbc(code):
    return [int(code[0:2], 16), int(code[2:4], 16), int(code[4:6], 16)]


def tone(code, k=1.0, white=0.0):
    """A step of colour "RRGGBB": scaled by k (darker < 1), then mixed with white by `white`."""
    c = [v * k for v in rgbc(code)]
    return hexc([v + (255.0 - v) * white for v in c])


def steps(main):
    """The four paints of a medal in colour `main`: rim (light, glossy), seal (dark), face, bead (pale)."""
    return {"rim": "Color_" + tone(main, 1.0, 0.18), "seal": "Color_" + tone(main, 0.7),
            "face": "Color_" + tone(main, 0.9), "bead": "Color_" + tone(main, 1.0, 0.72)}


def seal_poly(r=SEAL_R, amp=0.085, lobes=LOBES, n=176):
    """Outline of the scalloped seal: a circle with soft round lobes."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        rr = r + amp * math.cos(lobes * t)
        pts.append([rr * math.cos(t), rr * math.sin(t)])
    return pts


def torus_arc(center, big, small, a0, a1, n=12, m=10):
    """A piece of a ring standing up facing the front (XZ plane), from angle a0 to a1 (radians, counter-
    clockwise from +X seen from the front), closed by flat end caps."""
    verts, rings = [], []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        ring = []
        for j in range(m):
            b = 2 * math.pi * j / m
            rr = big + small * math.cos(b)
            ring.append(len(verts))
            verts.append([center[0] + rr * math.cos(a), center[1] - small * math.sin(b), center[2] + rr * math.sin(a)])
        rings.append(ring)
    return L["orient"]({"v": verts, "f": L["loft_faces"](rings)})


def medal(p, paints, face=True, rim_paints=None):
    """The badge medal: scalloped seal, fat rim, a pale bead ring inside it and (face=True) the enamel face.
    rim_paints = a list of paints to split the rim into equal arcs (the rainbow medal)."""
    L["piece"](p, paints["seal"], IC["slab"](seal_poly(), 0.6, 0.08, y=0.0, z=CZ, seg=3, support=0.0), crease=50)
    if face:
        L["piece"](p, paints["face"], IC["disc"]((0, -0.43, CZ), FACE_R, 0.2, 0.06, n=64), crease=50)
    if rim_paints:
        k = len(rim_paints)
        for i in range(k):
            a0 = math.pi / 2 + 2 * math.pi * i / k
            arc = torus_arc((0, -0.5, CZ), 2.04, 0.3, a0, a0 + 2 * math.pi / k, n=14, m=12)
            L["piece"](p, rim_paints[i], arc, crease=60)
    else:
        L["piece"](p, paints["rim"], IC["torus"]((0, -0.5, CZ), 2.04, 0.3, n=64, m=12), crease=60)
    L["piece"](p, paints["bead"], IC["torus"]((0, -0.6, CZ), 1.76, 0.065, n=64, m=8), crease=60)
    # a white glint on the rim, upper left: a thin streak bulging out of the rim's front
    glint = torus_arc((0, -0.74, CZ), 1.98, 0.075, math.radians(122), math.radians(150), n=8, m=8)
    L["piece"](p, "Neon_FFFFFF", glint, crease=60)


def new_badge(name, slot):
    """Start (or rebuild) the group Prop_Badge_<name>; models sit side by side on a row, 8 studs apart."""
    return L["new_prop"]("Badge_" + name, 8.0 * slot, 0.0, {}, solid=False, category="icons")


BG.update({"CZ": CZ, "FACE_R": FACE_R, "hexc": hexc, "rgbc": rgbc, "tone": tone, "steps": steps,
           "seal_poly": seal_poly, "torus_arc": torus_arc, "medal": medal, "new_badge": new_badge})
result = {"chunk": 1, "helpers": len(BG)}

# ===== chunk 2/4: the medals, one per badge colour (Badge_Ring_<Colour>) =====
L = session_state["L"]
IC = session_state["IC"]
BG = session_state["BG"]

# Badge colours (docs/BADGES.md lists which badge wears which): full medals, and the zone medals' frames (no face
# of their own: badge_scenes.py puts the zone emblem's face and scene in them)
RINGS = [("Sky", "3AA8F5"), ("Gold", "FFB52E"), ("Indigo", "5B5FE8"), ("Pink", "FF6FAE"), ("Orange", "FF8A1E"),
         ("Berry", "D9306A"), ("Lime", "7CCB2E"), ("Steel", "8E9BD0"), ("Royal", "2F6FE0"), ("Emerald", "1FAE5E")]
FRAMES = [("Teal", "1FBFA8"), ("Purple", "9A62F0"), ("Sand", "EBA33F"), ("Ice", "6FC6F2"), ("Lava", "EF4F33"),
          ("Cosmic", "4A36C8")]
# Paints that differ from the plain colour steps (gold and steel use the store's metal paints)
SPECIAL = {"Gold": {"rim": "Color_FFC23A", "seal": "Color_F59A23", "face": "Color_FFB52E", "bead": "Color_FFF6E2"},
           "Steel": {"rim": "Color_C3CCF0", "seal": "Color_8794CC", "face": "Color_5B6A9E", "bead": "Color_EEF2FF"}}
RAINBOW = ["Color_FF5A6E", "Color_FF9A3A", "Color_FFD83A", "Color_55D46A", "Color_3EB4FF", "Color_9A6BFF"]


def rings():
    built = []
    for slot, (name, main) in enumerate(RINGS):
        p = BG["new_badge"]("Ring_" + name, slot)
        BG["medal"](p, SPECIAL.get(name) or BG["steps"](main))
        built.append(L["report"](p))
    p = BG["new_badge"]("Ring_Rainbow", len(RINGS))
    BG["medal"](p, {"seal": "Color_B9A4F5", "face": "Color_5A3FD0", "bead": "Color_FFFFFF"}, rim_paints=RAINBOW)
    built.append(L["report"](p))
    for slot, (name, main) in enumerate(FRAMES):
        p = BG["new_badge"]("Frame_" + name, len(RINGS) + 1 + slot)
        BG["medal"](p, BG["steps"](main), face=False)
        built.append(L["report"](p))
    return built


result = {"built": rings()}

# ===== chunk 3/4: Trophy (Storm Champion) - a gold cup with handles, a bolt badge, on a plinth =====
L = session_state["L"]
IC = session_state["IC"]
BG = session_state["BG"]
P = IC["P"]


def trophy():
    p = BG["new_badge"]("Trophy", 30)
    gold, gold_l, gold_d = "Color_FFC23A", "Color_FFCF3A", "Color_F59A23"
    # plinth: a navy block with a gold plate on its front
    L["piece"](p, "Color_3B3F8F", L["rounded_box"]((0, 0, 0.45), (2.9, 2.0, 0.9), 0.18), crease=40)
    L["piece"](p, gold_l, L["rounded_box"]((0, -1.0, 0.45), (1.7, 0.16, 0.42), 0.07), crease=40)
    # foot, stem and knot (one lathe), then the cup (a thick bowl: outside up, over the lip, inside down)
    foot = [(0.0, 0.9), (1.25, 0.9), (1.3, 1.02), (1.22, 1.16), (0.8, 1.28), (0.42, 1.42), (0.32, 1.7),
            (0.55, 1.86), (0.6, 1.98), (0.5, 2.1), (0.3, 2.2), (0.3, 2.42), (0.0, 2.42)]
    L["piece"](p, gold_d, L["lathe"](foot, n=40), crease=55)
    outside = [(0.0, 2.32), (0.55, 2.36), (1.05, 2.52), (1.45, 2.85), (1.72, 3.3), (1.85, 3.85), (1.9, 4.35)]
    lip = [(1.96, 4.45), (1.9, 4.55), (1.78, 4.52)]
    inside = [(1.72, 4.35), (1.62, 3.85), (1.45, 3.35), (1.1, 2.95), (0.6, 2.78), (0.0, 2.74)]
    L["piece"](p, gold, L["lathe"](outside + lip + inside, n=48), crease=55)
    # handles: fat loops on both sides
    for s in (1, -1):
        path = []
        for k in range(9):
            a = math.radians(-70 + 150 * k / 8)
            path.append((s * (1.72 + 0.62 * math.cos(a)), 0.0, 3.55 + 0.62 * math.sin(a) * 1.05))
        L["piece"](p, gold_l, IC["sweep"](path, 0.17, n=12, closed=False), crease=60)
    # front badge: a sky enamel coin with a white bolt
    L["piece"](p, "Color_2F86F2", IC["disc"]((0, -1.72, 3.55), 0.78, 0.26, 0.09, n=40), crease=50)
    L["piece"](p, gold_l, IC["torus"]((0, -1.85, 3.55), 0.74, 0.07, n=40, m=8), crease=60)
    bolt = IC["bolt_shape"](1.05)
    L["piece"](p, "Color_FFE98A", IC["slab"](bolt, 0.22, 0.05, y=-1.9, z=3.55, corner=0.1), crease=50)
    # a shine streak on the bowl
    L["piece"](p, "Neon_FFFFFF", IC["decal"]((-1.25, -1.15, 3.6), [-0.65, -0.72, 0.1], 0.12, 0.5, 0.05, sink=0.0,
                                             spin=-8), crease=60)
    return p


result = {"built": [L["report"](trophy())]}

# ===== chunk 4/4: HatchEgg + HatchCap (First Hatch) - a cracked egg's shell and its top =====
L = session_state["L"]
IC = session_state["IC"]
BG = session_state["BG"]
P = IC["P"]
EGG_H, EGG_R, EGG_K = 4.4, 1.62, 0.13   # the Eggs icon's egg (sketchup_icons.py)
CUT = 2.05      # profile angle t of the crack line (0 = bottom, pi = top)
TEETH = 7       # zigzag teeth round the crack


def egg_at(t, s=1.0):
    return (EGG_R * s * math.sin(t) * (1 + EGG_K * math.cos(t)), EGG_H / 2 * (1 - s * math.cos(t)) + (1 - s) * EGG_H / 2)


def zig(a, amp):
    """The crack's offset in t at azimuth a: a sharp zigzag of TEETH teeth."""
    x = (a * TEETH / (2 * math.pi)) % 1.0
    return amp * (1.0 - 4.0 * abs(x - 0.5))


def shell(top, amp=0.2, thick=0.88, n=56, m=14):
    """The egg's shell cut along the zigzag crack: top=False the bottom part (t from 0 up to the crack),
    True the top part (from the crack up to pi). Outside, a rim along the crack, the inside (scaled by
    thick) - a closed solid."""
    verts, outer, inner = [], [], []
    for side, s in ((outer, 1.0), (inner, thick)):
        for j in range(m + 1):
            if (not top and j == 0) or (top and j == m):
                r, z = egg_at(0.0 if not top else math.pi, s)
                side.append([len(verts)])  # the pole
                verts.append([0.0, 0.0, z])
                continue
            ring = []
            for i in range(n):
                a = 2 * math.pi * i / n
                c = CUT + zig(a, amp)
                f = j / float(m)
                t = c * f if not top else c + (math.pi - c) * f
                r, z = egg_at(t, s)
                ring.append(len(verts))
                verts.append([r * math.cos(a), r * math.sin(a), z])
            side.append(ring)
    # outside from its pole to the crack, over the rim, then the inside back to its pole
    if not top:
        rings = outer + list(reversed(inner))
    else:
        rings = list(reversed(outer)) + inner
    faces = L["loft_faces"](rings)
    return L["orient"]({"v": verts, "f": faces})


def spots(p, t_lo, t_hi, paint):
    for t, az, s in ((2.25, -96, 0.46), (1.5, -52, 0.4), (1.38, -134, 0.34), (0.82, -88, 0.33),
                     (1.95, -14, 0.3), (2.62, -150, 0.26), (0.95, -30, 0.26), (1.9, -172, 0.28), (2.75, -60, 0.3)):
        if t_lo + 0.12 < t < t_hi - 0.12:
            r, z = egg_at(t)
            a = math.radians(az)
            at = [r * math.cos(a), r * math.sin(a), z]
            dr, dz = EGG_R * math.cos(t), EGG_H / 2 * math.sin(t)
            normal = [dz * math.cos(a), dz * math.sin(a), -dr * 0.6]
            L["piece"](p, paint, IC["decal"](at, normal, s, s, 0.09, sink=0.03), crease=60)


def hatch_egg():
    p = BG["new_badge"]("HatchEgg", 31)
    L["piece"](p, "Color_C6F2A8", shell(False), crease=50)
    spots(p, 0.0, CUT - 0.2, "Color_FFE14D")
    return p


def hatch_cap():
    p = BG["new_badge"]("HatchCap", 32)
    L["piece"](p, "Color_C6F2A8", shell(True), crease=50)
    spots(p, CUT + 0.2, math.pi, "Color_FFE14D")
    return p


result = {"built": [L["report"](f()) for f in (hatch_egg, hatch_cap)]}
