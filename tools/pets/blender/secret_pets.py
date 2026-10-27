"""The nine Secret Stormlings, modelled in Blender (one build function per pet).

Each function returns a kit.Pet whose parts are filed by pack role (see tools/pets/README.md, "Mesh pack
contract"); build_secret_pets.py finishes (merge, triangulate, fit the budget), exports and renders them.
Modelling space: Z up, the pet faces -Y, its left side is +X (WingL), 1 unit = 1 stud, origin = pet centre.
"""

import math

from mathutils import Vector

import features as F
import kit
from kit import Pet, Surface, curve_tube, decal, sweep


# --------------------------------------------------------------------------------------- shared bodies

def cloud_body(name, puffs=None, voxel=0.028):
    """A fluffy cumulus: a union of round puffs (voxel remesh) with soft creases between them."""
    puffs = puffs or [
        ((0.0, 0.0, -0.05), (1.08, 0.98, 0.92)),     # core (the face sits on it)
        ((-0.92, 0.08, -0.3), (0.66, 0.66, 0.62)),   # side puffs
        ((0.92, 0.08, -0.3), (0.66, 0.66, 0.62)),
        ((-1.36, 0.16, -0.55), (0.42, 0.42, 0.4)),   # outer little puffs
        ((1.36, 0.16, -0.55), (0.42, 0.42, 0.4)),
        ((-0.5, 0.1, 0.62), (0.6, 0.6, 0.56)),       # top puffs
        ((0.5, 0.1, 0.62), (0.6, 0.6, 0.56)),
        ((0.0, 0.18, 0.88), (0.58, 0.58, 0.52)),
        ((0.0, 0.62, 0.0), (0.9, 0.7, 0.85)),        # back
        ((-0.55, -0.05, -0.75), (0.5, 0.5, 0.36)),   # flat-ish underside
        ((0.55, -0.05, -0.75), (0.5, 0.5, 0.36)),
    ]
    return kit.blob_union(name, puffs, voxel=voxel, smooth=5, smooth_factor=0.5)


def round_body(name, rx=1.04, ry=1.0, rz=0.95, bottom=-0.86, level=4, belly=0.06, cheeks=0.05):
    """The chibi "Round" body: a quad sphere, a bit wider than tall, with a flattened seat, a soft belly and
    full cheeks."""
    obj = kit.quad_sphere(name, 1.0, level)

    def shape(co):
        x, y, z = co
        p = Vector((x * rx, y * ry, z * rz))
        # soft seat: squash the bottom cap upward
        if p.z < bottom + 0.25:
            t = (bottom + 0.25 - p.z)
            p.z = bottom + 0.25 - t * 0.55
        # belly pushes forward a little below the middle
        p.y -= belly * max(0.0, -y) * math.exp(-((z + 0.35) ** 2) / 0.18)
        # cheeks: puff out sideways at face height
        p.x += cheeks * x * math.exp(-((z + 0.12) ** 2) / 0.08) * max(0.0, -y)
        return p

    return kit.deform(obj, shape)


def bean_body(name, width=0.92, depth=0.88, bottom=-0.98, top=1.25, level=4):
    """The "Bean" body: an egg, wide at the bottom, with a soft seat."""
    obj = kit.quad_sphere(name, 1.0, level)
    mid = (top + bottom) / 2
    half = (top - bottom) / 2

    def shape(co):
        x, y, z = co
        k = 1.0 - 0.16 * z  # egg taper: wider at the bottom
        p = Vector((x * width * k, y * depth * k, mid + z * half))
        if p.z < bottom + 0.2:
            t = bottom + 0.2 - p.z
            p.z = bottom + 0.2 - t * 0.6
        return p

    return kit.deform(obj, shape)


def feet(pet, body, role="Body", x=0.42, z=-0.82, y=-0.42, r=0.21, toe_beans=False):
    out = []
    for side in (-1, 1):
        foot = kit.quad_sphere(f"foot{side}", 1.0, 2, loc=(side * x, y, z), scale=(r, r * 1.25, r * 0.72))
        out.append(foot)
    pet.add(role, *out)
    return out


# --------------------------------------------------------------------------------------- 1. Eye of the Storm

def eye_of_the_storm():
    """A fluffy white storm cloud with a glowing hurricane eye on its brow, a gold crown, a cyan halo,
    sky-blue feathered wings and wind streaks swirling around its base."""
    pet = Pet("EyeOfTheStorm")
    body = cloud_body("body")
    pet.add("Body", body)
    F.face(pet, body, eye_x=0.38, eye_z=-0.08, eye_rx=0.19, eye_ry=0.24, mouth="cat", mouth_z=-0.4,
           mouth_w=0.1)
    surf = Surface(body)
    # glowing hurricane emblem on the brow: two spiral arms around an eye dot
    emblem = []
    for k in range(2):
        pts = F.spiral_points(turns=0.7, r0=0.07, r1=0.22, n=12, phase=math.pi * k + 0.4, cx=0.0, cz=0.42)
        path = kit.surface_path(surf, pts, offset=0.025)
        emblem.append(curve_tube(f"arm{k}", path, 0.04, taper=[1.0 - 0.7 * i / 11 for i in range(len(path))]))
    emblem.append(decal("eyedot", body, surf.front(0.0, 0.42), 0.065, 0.065, offset=0.012, dome=0.03, rings=3,
                        segments=18))
    pet.add("Neon_3CB4FF", *emblem)
    # crown on the top puff
    top, _ = surf.hit((0, 0.1, 5), (0, 0, -1))
    gold, tips = F.crown("crown", top.z - 0.1, radius=0.34, height=0.32, points=5, base_y=0.1, tilt=-0.15)
    pet.add("Color_FFD23C", *gold)
    front_gem = Vector((0, 0.1, top.z - 0.1)) + Vector((0, -0.36, 0.06))
    pet.add("Neon_3CB4FF", F.gem("gem", front_gem, 0.06))
    # halo
    pet.add("Neon_54C4FF@SpinY", F.halo("halo", top.z + 0.42, radius=0.42, tube=0.05))
    # wings (left = +X)
    wing = F.feather_wing("wing", (1.05, 0.4, 0.3), span=0.95, count=5, base_angle=-5, fan=85, width=0.19,
                          sweep_back=0.45)
    pet.add("Accent@WingL", *wing)
    pet.add("Accent@WingR", *F.mirrored(wing))
    pet.pivot("WingL", (1.05, 0.4, 0.3))
    pet.pivot("WingR", (-1.05, 0.4, 0.3))
    # wind streaks: three tilted ribbons around the base (spin about the vertical axis)
    swirl = []
    for i in range(3):
        a0 = 2 * math.pi * i / 3
        pts, radii = [], []
        for k in range(16):
            t = k / 15
            a = a0 + t * 1.7
            r = 1.62 + 0.12 * t
            pts.append((math.cos(a) * r, math.sin(a) * r, -0.85 + 0.4 * t))
            w = math.sin(math.pi * t) ** 0.7
            radii.append((0.025 * w + 0.004, 0.1 * w + 0.01))
        swirl.append(sweep(f"streak{i}", pts, radii, sides=8, up=(0, 0, 1)))
    pet.add("Accent@SpinY", *swirl)
    return pet


# --------------------------------------------------------------------------------------- 2. Thunderclap Kirin

def antler(name, base, side):
    """A branching kirin antler: a tapered main beam sweeping up, out and back, with two forward tines
    (bevelled curves: round, smooth and cheap)."""
    b = Vector(base)
    sx = side
    beam = [b + Vector((0, 0, -0.08)), b + Vector((sx * 0.06, 0.02, 0.18)), b + Vector((sx * 0.16, 0.08, 0.4)),
            b + Vector((sx * 0.3, 0.16, 0.58)), b + Vector((sx * 0.38, 0.22, 0.66))]
    tine1 = [b + Vector((sx * 0.07, 0.03, 0.2)), b + Vector((sx * 0.2, -0.04, 0.3)),
             b + Vector((sx * 0.28, -0.1, 0.42))]
    tine2 = [b + Vector((sx * 0.17, 0.09, 0.42)), b + Vector((sx * 0.24, 0.0, 0.56)),
             b + Vector((sx * 0.26, -0.06, 0.68))]
    return [curve_tube(name, beam, 0.085, taper=[1.0, 0.9, 0.72, 0.5, 0.2], bevel_resolution=2, resolution=4),
            curve_tube(name + "t1", tine1, 0.06, taper=[0.9, 0.7, 0.25], bevel_resolution=2, resolution=4),
            curve_tube(name + "t2", tine2, 0.055, taper=[0.9, 0.7, 0.25], bevel_resolution=2, resolution=4)]


def bolt_mane(surf, name, center, angles, size, set_back=0.25, depth=0.1):
    """A lion's mane of lightning: bolts standing out of the head's silhouette (seen from the front) at the
    given angles (degrees, 0 = the pet's left/+X, 90 = up), set back behind the face."""
    out = []
    c = Vector(center)
    for i, ang in enumerate(angles):
        a = math.radians(ang)
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        origin = c + Vector((0, set_back, 0))
        loc, n = surf.hit(origin + d * 3.0, -d)
        if loc is None:
            continue
        sz = size[i] if isinstance(size, (list, tuple)) else size
        bolt = F.bolt(f"{name}{i}", (0, 0, 0), scale=sz, depth=depth, bevel=0.024)
        kit.transform(bolt, loc=(0, 0, sz * 0.8))  # stand on its lower end
        kit.transform(bolt, rot=(0, -(a - math.pi / 2), 0))  # point outward (Z -> d)
        kit.transform(bolt, loc=tuple(loc - d * 0.08))
        out.append(bolt)
    return out


def thunder_kirin():
    """A chibi deer-dragon standing on a little storm cloud: navy egg body, gold antlers, ears and hooves,
    a crest of glowing lightning bolts, gold chest scales, long dragon whiskers, a wagging tail with a
    bolt tuft and two bolts orbiting on a tilted ring."""
    pet = Pet("ThunderKirin")
    body = bean_body("body", width=0.9, depth=0.86, bottom=-0.92, top=1.2)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.31, eye_z=0.3, eye_rx=0.165, eye_ry=0.21, mouth="cat", mouth_z=0.04,
                  mouth_w=0.085, blush_z=0.1)
    # a glowing thunderbolt emblem on the chest (half sunk into the body)
    loc, n = surf.front(0.0, -0.42)
    emblem = F.bolt("chestbolt", (0, 0, 0), scale=0.27, depth=0.08, bevel=0.025)
    emblem.data.transform(Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4())
    emblem.data.transform(kit.Matrix.Translation(loc + n * 0.005))
    pet.add("Neon_FFE14A", emblem)
    # antlers + deer ears
    for side in (-1, 1):
        loc, n = surf.toward((side * 0.3, 0.05, 1.05))
        pet.add("Accent", *antler(f"antler{side}", tuple(loc - n * 0.04), side))
        ear_root = Vector((side * 0.44, 0.1, 0.78))
        tip = ear_root + Vector((side * 0.4, 0.02, -0.02))
        ear = F.feather(f"ear{side}", ear_root, tip - ear_root, 0.42, 0.13, thickness=0.06, curl=-0.1 * side,
                        bend_axis=(0, 1, 0), tip=0.9)
        pet.add("Body", ear)
        inner = F.feather(f"earin{side}", ear_root + Vector((side * 0.04, -0.035, 0.0)), tip - ear_root, 0.34,
                          0.075, thickness=0.03, curl=-0.1 * side, bend_axis=(0, 1, 0), tip=0.9)
        pet.add("Accent", inner)
    # lightning mane: glowing bolts fanning out behind the head like a lion's mane
    pet.add("Neon_FFE14A", *bolt_mane(surf, "mane", (0, 0, 0.32), [-28, 0, 28, 152, 180, 208],
                                      [0.26, 0.3, 0.27, 0.27, 0.3, 0.26], set_back=0.12))
    # legs with gold hooves, standing on a little cloud
    for side in (-1, 1):
        for (x, y, top_z) in ((0.33, -0.42, -0.55), (0.5, 0.32, -0.55)):
            leg = sweep(f"leg{side}{y}", [(side * x, y, top_z), (side * (x + 0.02), y - 0.02, -0.82),
                                          (side * (x + 0.03), y - 0.03, -0.95)], [0.15, 0.14, 0.13], sides=12)
            pet.add("Body", kit.subsurf(leg, 1))
            hoof = kit.lathe(f"hoof{side}{y}", [(0.0, -0.12), (0.135, -0.12), (0.155, -0.08), (0.15, 0.0),
                                                 (0.13, 0.03), (0.0, 0.03)], segments=20)
            kit.transform(hoof, loc=(side * (x + 0.03), y - 0.03, -0.98))
            pet.add("Accent", kit.subsurf(hoof, 1))
    cloud = kit.blob_union("cloud", [
        ((0.0, -0.05, -1.18), (0.62, 0.55, 0.22)), ((-0.62, -0.25, -1.14), (0.36, 0.34, 0.24)),
        ((0.62, -0.25, -1.14), (0.36, 0.34, 0.24)), ((-0.72, 0.35, -1.13), (0.36, 0.36, 0.25)),
        ((0.72, 0.35, -1.13), (0.36, 0.36, 0.25)), ((0.0, 0.62, -1.12), (0.4, 0.34, 0.25)),
        ((-0.3, -0.55, -1.15), (0.3, 0.26, 0.22)), ((0.3, -0.55, -1.15), (0.3, 0.26, 0.22)),
    ], voxel=0.03, smooth=4)
    pet.add("Color_F4F6FF", cloud)
    # tail with a bolt tuft (wags)
    root = Vector((0.0, 0.72, -0.5))
    tail_pts = [root, root + Vector((0, 0.3, -0.06)), root + Vector((0, 0.55, 0.12)), root + Vector((0, 0.62, 0.4))]
    pet.add("Body@Wag", kit.subsurf(sweep("tail", tail_pts, [0.085, 0.07, 0.06, 0.05], sides=10), 1))
    tuft = F.bolt("tuft", (0, 0, 0), scale=0.24, depth=0.1, rot=(0, 0, math.pi / 2))
    kit.transform(tuft, rot=(-0.35, 0, 0))
    kit.transform(tuft, loc=tuple(tail_pts[-1] + Vector((0, 0.04, 0.2))))
    puff = kit.quad_sphere("tuftball", 1.0, 2, loc=tuple(tail_pts[-1]), scale=(0.11, 0.11, 0.11))
    pet.add("Accent@Wag", tuft, puff)
    pet.pivot("Wag", tuple(root))
    # orbit: a thin tilted ring with two bolts riding on it
    orbit = [F.orbit_ring("orbit", 1.25, -0.3, tube=0.032, tilt=0.3)]
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.5
        b = F.bolt(f"obolt{i}", (0, 0, 0), scale=0.19, depth=0.08, rot=(0, 0, a + math.pi / 2), bevel=0.022)
        kit.transform(b, loc=(math.cos(a) * 1.25, math.sin(a) * 1.25, 0))
        kit.transform(b, rot=(0.3, 0, 0))
        kit.transform(b, loc=(0, 0, -0.3))
        orbit.append(b)
    pet.add("Neon_FFE14A@SpinY", *orbit)
    return pet


# --------------------------------------------------------------------------------------- 3. Sandstorm Sphinx

def sphere_dir(theta, phi):
    """Direction from polar angle theta (0 = up) and azimuth phi (0 = front/-Y, + toward the pet's left/+X)."""
    return Vector((math.sin(theta) * math.sin(phi), -math.sin(theta) * math.cos(phi), math.cos(theta)))


def hood_shell(name, surf, center, theta_max, lift=0.05, thickness=0.05, rings=12, segments=40, puff=0.0,
               smooth=0):
    """A shell over the head (a headdress / hood): the region from the top down to theta_max(phi), lifted
    `lift` off the body surface (cast from `center`), solidified and smoothed."""
    c = Vector(center)
    verts, faces = [], []
    top_loc, top_n = surf.hit(c + Vector((0, 0, 4)), (0, 0, -1))
    verts.append(top_loc + top_n * lift)
    for r in range(1, rings + 1):
        for j in range(segments):
            phi = 2 * math.pi * j / segments
            theta = theta_max(phi) * r / rings
            d = sphere_dir(theta, phi)
            loc, n = surf.hit(c + d * 4.0, -d)
            if loc is None:
                loc, n = c + d, d
            bulge = puff * math.sin(math.pi * r / rings)
            verts.append(loc + n * (lift + bulge))
    for j in range(segments):
        faces.append((0, 1 + (j + 1) % segments, 1 + j))
    for r in range(1, rings):
        a0 = 1 + (r - 1) * segments
        a1 = 1 + r * segments
        for j in range(segments):
            faces.append((a0 + j, a0 + (j + 1) % segments, a1 + (j + 1) % segments, a1 + j))
    obj = kit.mesh_object(name, verts, faces)
    kit.fix_normals(obj)
    kit.fix_normals_outward(obj, Vector((0, 0, 1)))
    kit.modifier(obj, "SOLIDIFY", thickness=thickness, offset=-1.0, use_rim=True, use_even_offset=True)
    obj = kit.bake(obj)
    return kit.subsurf(obj, smooth) if smooth else obj


def sandstorm_sphinx():
    """A sphinx kitten: sand-gold round body lying in the sphinx pose (front paws forward), a blue-and-gold
    striped nemes headdress with lappets, a gold uraeus cobra with a glowing gem, kohl-lined aqua eyes, a
    jewelled usekh collar, falcon wings, a lion tail, a sun halo and little gold pyramids orbiting."""
    pet = Pet("SandstormSphinx")
    body = round_body("body", rx=1.02, ry=0.98, rz=0.95, bottom=-0.86)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.35, eye_z=0.02, eye_rx=0.17, eye_ry=0.21, kohl=True, mouth="cat",
                  mouth_z=-0.24, mouth_w=0.09)
    # front paws (sphinx pose) and the haunches
    for side in (-1, 1):
        paw = sweep(f"paw{side}", [(side * 0.4, -0.35, -0.7), (side * 0.42, -0.75, -0.76), (side * 0.43, -1.02, -0.77)],
                    [(0.19, 0.16), (0.18, 0.15), (0.0, 0.0)], sides=12, up=(0, 0, 1))
        pet.add("Body", kit.subsurf(paw, 1))
    # nemes headdress: hood over the head (from the brow down behind the cheeks) + two lappets
    def edge(phi):
        k = math.sqrt(max(0.0, (1 - math.cos(phi)) / 2))
        return math.radians(56 + 48 * k)

    hood = hood_shell("hood", surf, (0, 0, 0), edge, lift=0.045, thickness=0.06, puff=0.06)
    pet.add("Accent", hood)
    hsurf = Surface(hood)
    stripes = []
    for k in range(1, 5):
        pts = []
        for j in range(33):
            phi = 2 * math.pi * j / 32
            theta = edge(phi) * (1.0 - 0.17 * k)
            d = sphere_dir(theta, phi)
            loc, n = hsurf.hit(d * 4.0, -d)
            if loc is not None:
                pts.append(loc + n * 0.004)
        stripes.append(curve_tube(f"stripe{k}", pts[:-1], 0.032, closed=True, resolution=1))
    # headband along the brow edge (thicker)
    band = []
    for j in range(41):
        phi = 2 * math.pi * j / 40
        d = sphere_dir(edge(phi) * 0.985, phi)
        loc, n = hsurf.hit(d * 4.0, -d)
        if loc is not None:
            band.append(loc + n * 0.0)
    stripes.append(curve_tube("headband", band[:-1], 0.045, closed=True, resolution=1))
    # lappets hanging in front of the shoulders, with gold bands
    for side in (-1, 1):
        pts, ups = [], []
        for x, z in ((0.6, 0.2), (0.63, 0.0), (0.66, -0.2), (0.69, -0.4), (0.7, -0.5)):
            loc, n = surf.front(side * x, z)
            pts.append(loc + n * 0.075)
            ups.append(n)
        lap = sweep(f"lappet{side}", pts, [(0.15, 0.04), (0.16, 0.042), (0.17, 0.045), (0.18, 0.045), (0.0, 0.0)],
                    sides=12, up=tuple(ups[0]))
        lap = kit.subsurf(lap, 1)
        pet.add("Accent", lap)
        lsurf = Surface(lap)
        for k, z in enumerate((-0.05, -0.2, -0.35)):
            line = []
            for t in range(7):
                x = side * (0.64 + 0.03 * k) + (-0.17 + 0.34 * t / 6)
                loc, n = lsurf.front(x, z)
                if loc is not None:
                    line.append(loc + n * 0.003)
            if len(line) > 2:
                stripes.append(curve_tube(f"lapband{side}{k}", line, 0.026, resolution=2))
    pet.add("Color_FFD23C", *stripes)
    # little cat ears poking out of the headdress (pink inner ears)
    for side in (-1, 1):
        loc, n = hsurf.toward((side * 0.52, 0.08, 0.78))
        d = (n + Vector((side * 0.25, 0, 0.4))).normalized()
        ear = F.feather(f"ear{side}", loc - d * 0.12, d, 0.42, 0.2, thickness=0.09, curl=0.0, bend_axis=(0, 1, 0),
                        tip=1.2)
        inner = F.feather(f"earin{side}", loc - d * 0.02 + Vector((0, -0.05, 0)), d, 0.28, 0.11, thickness=0.03,
                          curl=0.0, bend_axis=(0, 1, 0), tip=1.2)
        pet.add("Body", ear)
        pet.add("Blush", inner)
    # uraeus: a gold cobra rearing on the brow, with a glowing gem
    brow, bn = hsurf.front(0.0, 0.62)
    cobra = [brow - bn * 0.02, brow + Vector((0, -0.05, 0.08)), brow + Vector((0, -0.03, 0.18)),
             brow + Vector((0, -0.07, 0.27))]
    gold = [curve_tube("cobra", cobra, 0.045, taper=[1.0, 0.95, 0.9, 0.85], bevel_resolution=2)]
    hood_c = kit.quad_sphere("cobrahood", 1.0, 2, loc=tuple(brow + Vector((0, -0.04, 0.24))), scale=(0.1, 0.035, 0.11))
    head = kit.quad_sphere("cobrahead", 1.0, 2, loc=tuple(brow + Vector((0, -0.09, 0.33))), scale=(0.05, 0.055, 0.04))
    gold += [hood_c, head]
    pet.add("Color_FFD23C", *gold)
    pet.add("Neon_50FFE2", F.gem("cobragem", brow + Vector((0, -0.08, 0.235)), 0.045))
    # usekh collar: two gold arcs with turquoise beads
    collar, beads = [], []
    for k, (z, width) in enumerate(((-0.42, 0.62), (-0.56, 0.5))):
        pts = []
        for t in range(11):
            a = math.pi * t / 10
            pts.append((math.cos(a) * width, z - math.sin(a) * 0.12))
        path = kit.surface_path(surf, pts, offset=0.02)
        collar.append(curve_tube(f"collar{k}", path, 0.035, resolution=2))
        for t in range(1, 10, 2 if k == 0 else 3):
            a = math.pi * t / 10
            loc, n = surf.front(math.cos(a) * width, z - math.sin(a) * 0.12 - 0.06)
            if loc is not None:
                beads.append(kit.quad_sphere(f"bead{k}{t}", 1.0, 1, loc=tuple(loc + n * 0.02), scale=(0.04, 0.04, 0.04)))
    pet.add("Color_FFD23C", *collar)
    pet.add("Neon_50FFE2", *beads)
    pet.flat_roles.add("Neon_50FFE2")
    # falcon wings
    wing = F.feather_wing("wing", (0.92, 0.42, 0.25), span=1.08, count=5, base_angle=-5, fan=80, width=0.2,
                          thickness=0.045, sweep_back=0.5, curl=0.22, tip=0.5)
    pet.add("Accent@WingL", *wing)
    pet.add("Accent@WingR", *F.mirrored(wing))
    pet.pivot("WingL", (0.92, 0.42, 0.25))
    pet.pivot("WingR", (-0.92, 0.42, 0.25))
    # lion tail: out behind, curling up, with a tuft
    root = Vector((0.0, 0.82, -0.55))
    tail = [root, root + Vector((0.08, 0.3, -0.04)), root + Vector((0.16, 0.52, 0.18)), root + Vector((0.14, 0.58, 0.45)),
            root + Vector((0.06, 0.48, 0.66))]
    tuft = kit.quad_sphere("tuft", 1.0, 2, loc=tuple(tail[-1] + Vector((0, -0.03, 0.05))), scale=(0.11, 0.11, 0.14))
    pet.add("Body@Wag", kit.subsurf(sweep("tail", tail, [0.08, 0.07, 0.06, 0.055, 0.05], sides=10), 1), tuft)
    pet.pivot("Wag", tuple(root))
    # sun halo and an orbit of little gold pyramids
    spin = [F.halo("halo", 1.35, radius=0.42, tube=0.05)]
    for i in range(3):
        a = 2 * math.pi * i / 3
        pyr = kit.lathe(f"pyr{i}", [(0.0, 0.0), (0.13, 0.0), (0.0, 0.17)], segments=4, smooth=False)
        kit.transform(pyr, loc=(math.cos(a) * 1.4, math.sin(a) * 1.4, -0.07), rot=(0, 0, a + math.pi / 4))
        kit.transform(pyr, rot=(0.2, 0, 0))
        spin.append(pyr)
    spin.append(F.orbit_ring("sandring", 1.4, 0.0, tube=0.018, tilt=0.2))
    pet.add("Neon_FFD65A@SpinY", *spin)
    return pet


# --------------------------------------------------------------------------------------- 4. Blizzard Monarch

def crystal(name, base, direction, height, radius, facets=6, flat=True):
    """A hexagonal ice crystal (prism with a pointed tip) standing on `base` along `direction`."""
    obj = kit.lathe(name, [(0.0, -0.05), (radius, -0.05), (radius * 1.05, height * 0.68), (0.0, height)],
                    segments=facets, smooth=not flat)
    up = Vector(direction).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(up).to_matrix().to_4x4()
    obj.data.transform(rot)
    obj.data.transform(kit.Matrix.Translation(Vector(base)))
    obj.data.update()
    return obj


def snowflake(name, surf, center, size=0.15, radius=0.02, offset=0.02):
    """A glowing six-armed snowflake drawn on the surface (curves), with a little V on every arm."""
    cx, cz = center
    out = []
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        d = (math.cos(a), math.sin(a))
        arm = [(cx, cz), (cx + d[0] * size * 0.5, cz + d[1] * size * 0.5), (cx + d[0] * size, cz + d[1] * size)]
        out.append(curve_tube(f"{name}a{k}", kit.surface_path(surf, arm, offset), radius, taper=[1.0, 1.0, 0.7],
                              resolution=2))
        for s in (-1, 1):
            b = a + s * 0.75
            p0 = (cx + d[0] * size * 0.55, cz + d[1] * size * 0.55)
            p1 = (p0[0] + math.cos(b) * size * 0.32, p0[1] + math.sin(b) * size * 0.32)
            out.append(curve_tube(f"{name}v{k}{s}", kit.surface_path(surf, [p0, p1], offset), radius * 0.8,
                                  taper=[1.0, 0.6], resolution=2))
    return out


def blizzard_monarch():
    """A snow-fox monarch: a fluffy white round body with cheek and chest fluff, tall fox ears, an ice
    crystal crown, a glowing snowflake on the brow, ice-blue butterfly wings with raised veins, a big
    fluffy tail and snow crystals orbiting."""
    pet = Pet("BlizzardMonarch")
    body = round_body("body", rx=1.02, ry=0.98, rz=0.95, bottom=-0.86, cheeks=0.06)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.36, eye_z=0.02, eye_rx=0.175, eye_ry=0.22, mouth="cat", mouth_z=-0.24,
                  mouth_w=0.09)
    # fluff: cheek tufts and a chest ruff (rounded pointy tufts)
    fluff = []
    # a royal snow-fluff collar: a ring of soft puffs round the neck (merged into one smooth blob)
    puffs = []
    for k in range(11):
        a = math.radians(-180 + 36 * k)  # from the left side, round the front, to the right side
        if abs(math.degrees(a) + 90) > 100:
            continue
        x, y = math.cos(a) * 0.86, math.sin(a) * 0.82
        r = 0.2 if abs(math.degrees(a) + 90) < 60 else 0.17
        puffs.append(((x, y, -0.48 - 0.05 * math.cos(a * 2)), (r, r * 0.9, r * 0.85)))
    fluff.append(kit.blob_union("collar", puffs, voxel=0.025, smooth=4))
    pet.add("Body", *fluff)
    # tall fox ears with ice-blue insides
    for side in (-1, 1):
        loc, n = surf.toward((side * 0.5, 0.05, 0.85))
        d = (n * 0.5 + Vector((side * 0.18, 0.04, 1.0))).normalized()
        pet.add("Body", F.feather(f"ear{side}", loc - d * 0.1, d, 0.62, 0.24, thickness=0.11, curl=0.0,
                                  bend_axis=(0, 1, 0), tip=1.25))
        pet.add("Accent", F.feather(f"earin{side}", loc - d * 0.02 + Vector((0, -0.07, 0)), d, 0.46, 0.13,
                                    thickness=0.05, curl=0.0, bend_axis=(0, 1, 0), tip=1.25))
    # ice crown: a tiara of crystals, tallest in the middle
    crown = []
    for k, (x, h, r) in enumerate(((-0.3, 0.22, 0.06), (-0.15, 0.32, 0.07), (0.0, 0.46, 0.085), (0.15, 0.32, 0.07),
                                   (0.3, 0.22, 0.06))):
        loc, n = surf.toward((x, -0.12, 0.95))
        d = (n * 0.6 + Vector((0, 0, 1))).normalized()
        crown.append(crystal(f"crown{k}", loc - d * 0.06, d, h, r))
    band = []
    for t in range(13):
        x = -0.38 + 0.76 * t / 12
        loc, n = surf.toward((x, -0.1 - 0.15 * (1 - (x / 0.38) ** 2), 0.92))
        band.append(loc + n * 0.015)
    crown.append(curve_tube("crownband", band, 0.04, resolution=2))
    pet.add("Ice_8CCDFF", *crown)
    pet.flat_roles.add("Ice_8CCDFF")
    # glowing snowflake on the brow + a gem in the crown
    pet.add("Neon_96EBFF", *snowflake("flake", surf, (0.0, 0.45), size=0.13, radius=0.02))
    loc, n = surf.toward((0.0, -0.3, 0.92))
    pet.add("Neon_96EBFF", F.gem("crowngem", loc + n * 0.06, 0.06))
    # butterfly wings (ice blue) with raised veins
    fore = [(0.0, 0.0), (0.25, 0.3), (0.62, 0.68), (0.95, 0.86), (1.12, 0.74), (1.06, 0.42), (0.78, 0.16), (0.34, -0.04)]
    hind = [(0.0, -0.02), (0.36, -0.12), (0.7, -0.36), (0.8, -0.62), (0.62, -0.78), (0.36, -0.62), (0.12, -0.3)]
    wing = F.lobe_wing("wing", (0.82, 0.4, 0.3), [fore, hind], thickness=0.05, sweep_back=0.45, lift=0.1)
    pet.add("Accent@WingL", *wing)
    pet.add("Accent@WingR", *F.mirrored(wing))
    pet.pivot("WingL", (0.82, 0.4, 0.3))
    pet.pivot("WingR", (-0.82, 0.4, 0.3))
    # big fluffy tail curling up behind
    root = Vector((0.0, 0.8, -0.55))
    pts = [root, root + Vector((0.1, 0.3, -0.05)), root + Vector((0.25, 0.55, 0.15)), root + Vector((0.3, 0.62, 0.48)),
           root + Vector((0.22, 0.5, 0.8)), root + Vector((0.12, 0.38, 0.95))]
    tail = sweep("tail", pts, [0.12, 0.2, 0.26, 0.26, 0.2, 0.0], sides=12)
    pet.add("Body@Wag", kit.subsurf(tail, 1))
    pet.pivot("Wag", tuple(root))
    # snow crystals orbiting on a tilted ring
    spin = []
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.3
        flake = F.star(f"oflake{i}", (0, 0, 0), size=0.15, depth=0.05, points=6, inner=0.38, rot=(0, 0, a + math.pi / 2))
        kit.transform(flake, loc=(math.cos(a) * 1.42, math.sin(a) * 1.42, 0))
        kit.transform(flake, rot=(0.25, 0, 0))
        kit.transform(flake, loc=(0, 0, -0.15))
        spin.append(flake)
        shard = crystal(f"oshard{i}", (0, 0, -0.08), (0, 0, 1), 0.2, 0.04)
        a2 = a + math.pi / 3
        kit.transform(shard, loc=(math.cos(a2) * 1.42, math.sin(a2) * 1.42, 0))
        kit.transform(shard, rot=(0.25, 0, 0))
        kit.transform(shard, loc=(0, 0, -0.15))
        spin.append(shard)
    pet.add("Ice_CDF0FF@SpinY", *spin)
    pet.flat_roles.add("Ice_CDF0FF@SpinY")
    return pet


# --------------------------------------------------------------------------------------- 5. Tempest Phoenix

def flame(name, root, direction, length, width, curl=0.35, thickness=0.07, bend_axis=(0, 1, 0)):
    """A flame tongue: a plump plume that narrows to a curling point."""
    return F.feather(name, root, direction, length, width, thickness=thickness, curl=curl, bend_axis=bend_axis,
                     tip=1.6)


def plume(name, points, width, thickness=0.035, sides=10):
    """A long flat tail plume along `points` (widest two thirds along, round-ended)."""
    n = len(points)
    radii = []
    for i in range(n):
        t = i / (n - 1)
        w = width * (0.45 + 0.55 * math.sin(math.pi * min(t / 0.7, 1.0) / 2)) if t < 0.85 else width * math.sqrt(
            max(0.0, 1 - ((t - 0.85) / 0.15) ** 2)) * 0.98
        radii.append((max(w, 0.0), thickness))
    radii[-1] = (0.0, 0.0)
    return kit.subsurf(sweep(name, points, radii, sides=sides, up=(0, 1, 0)), 1)


def tempest_phoenix():
    """A phoenix chick: round scarlet body with a golden scalloped chest, a crest of glowing flame plumes,
    a little orange beak and feet, golden wings with flame-tipped feathers and three long tail plumes that
    curl at the ends."""
    pet = Pet("TempestPhoenix")
    body = round_body("body", rx=1.0, ry=0.98, rz=0.97, bottom=-0.86)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.36, eye_z=0.08, eye_rx=0.175, eye_ry=0.22, mouth=None, blush_z=-0.15)
    # golden chest with a scalloped (feathery) lower edge
    def scallop(a):
        if math.sin(a) > 0:
            return 1.0
        return 0.9 + 0.1 * abs(math.cos(a * 3.5))

    chest = decal("chest", body, surf.front(0.0, -0.48), 0.52, 0.36, offset=0.012, dome=0.03, rings=5, segments=40,
                  shape=scallop)
    pet.add("Accent", chest)
    # beak (orange) and little three-toed feet
    tip_loc, n = surf.front(0.0, -0.1)
    beak = sweep("beak", [tip_loc - n * 0.06, tip_loc + n * 0.06, tip_loc + n * 0.16 + Vector((0, 0, -0.04)),
                          tip_loc + n * 0.21 + Vector((0, 0, -0.08))], [(0.14, 0.09), (0.12, 0.08), (0.06, 0.05), (0.0, 0.0)],
                 sides=10, up=(0, 0, 1))
    orange = [kit.subsurf(beak, 1)]
    for side in (-1, 1):
        base = Vector((side * 0.35, -0.45, -0.86))
        for k in (-1, 0, 1):
            d = Vector((side * 0.05 + k * 0.32, -1.0, -0.15)).normalized()
            orange.append(sweep(f"toe{side}{k}", [base, base + d * 0.14, base + d * 0.24], [0.065, 0.055, 0.0], sides=8))
    pet.add("Color_FFB43C", *orange)
    # crest: three big flame plumes curling back (orange) with brighter inner flames (yellow)
    outer, inner = [], []
    for k, (x, lean, ln, curl) in enumerate(((-0.24, -0.45, 0.62, 0.3), (0.0, 0.0, 0.9, -0.2), (0.24, 0.45, 0.62, -0.3))):
        loc, n = surf.toward((x, 0.12, 0.95))
        d = Vector((lean, 0.22, 1.0)).normalized()
        outer.append(flame(f"crest{k}", loc - d * 0.12, d, ln, 0.2, curl=curl, thickness=0.08, bend_axis=(0, 1, 0)))
        inner.append(flame(f"crestin{k}", loc - d * 0.04 + Vector((0, -0.075, 0)), d, ln * 0.64, 0.11, curl=curl,
                           thickness=0.05, bend_axis=(0, 1, 0)))
    pet.add("Neon_FF8C28", *outer)
    pet.add("Neon_FFE15A", *inner)
    # golden wings with flame-tipped feathers
    wing = F.feather_wing("wing", (0.9, 0.35, 0.15), span=1.0, count=6, base_angle=-10, fan=88, width=0.17,
                          thickness=0.05, sweep_back=0.45, curl=0.3, tip=0.9)
    pet.add("Accent@WingL", *wing)
    pet.add("Accent@WingR", *F.mirrored(wing))
    pet.pivot("WingL", (0.9, 0.35, 0.15))
    pet.pivot("WingR", (-0.9, 0.35, 0.15))
    # three long tail plumes sweeping back and up, curling at the ends
    root = Vector((0.0, 0.8, -0.35))
    plumes = []
    for k, (spread, rise) in enumerate(((-0.55, 0.75), (0.0, 1.05), (0.55, 0.75))):
        pts = []
        for i in range(12):
            t = i / 11
            a = spread * t
            r = 0.85 * t
            p = root + Vector((math.sin(a) * r, math.cos(a) * r, rise * (t ** 1.4)))
            pts.append(p)
        # curl: the tip rolls over backwards
        end = pts[-1]
        out = (pts[-1] - pts[-2]).normalized()
        down = Vector((0, 0, -1))
        for i in range(1, 6):
            ang = math.pi * i / 5
            pts.append(end + out * (0.14 * math.sin(ang)) + down * (0.14 * (1 - math.cos(ang))) * 0.8)
        plumes.append(plume(f"plume{k}", pts, 0.17 if k != 1 else 0.19, thickness=0.04))
    pet.add("Accent@Wag", *plumes)
    pet.pivot("Wag", tuple(root))
    return pet


# --------------------------------------------------------------------------------------- 6. Pyroclasm Dragon

def crack_paths(surf, seeds, rng_seed=7, steps=6, step=0.12):
    """Branching zig-zag lava cracks running over the surface from seed points (directions from centre)."""
    import random

    rnd = random.Random(rng_seed)
    paths = []
    for seed, heading in seeds:
        pts = []
        p = Vector(seed)
        h = Vector(heading).normalized()
        for i in range(steps):
            loc, n = surf.toward(p)
            if loc is None:
                break
            pts.append(loc + n * 0.004)
            side = n.cross(h).normalized()
            h = (h + side * rnd.uniform(-0.9, 0.9)).normalized()
            p = loc + h * step
            if i == 2 and rnd.random() < 0.8:
                bh = (h + side * (1.2 if rnd.random() < 0.5 else -1.2)).normalized()
                branch = [loc + n * 0.004]
                q = loc
                for _ in range(3):
                    q = q + bh * step * 0.8
                    bl, bn = surf.toward(q)
                    if bl is None:
                        break
                    branch.append(bl + bn * 0.004)
                    bh = (bh + bn.cross(bh).normalized() * rnd.uniform(-0.6, 0.6)).normalized()
                if len(branch) > 1:
                    paths.append(branch)
        if len(pts) > 1:
            paths.append(pts)
    return paths


def pyroclasm_dragon():
    """An obsidian chibi dragon: dark egg body split by glowing lava cracks, orange belly plates and back
    spikes, swept-back horns, a crown of molten flame spikes, slit golden eyes, little fangs, bat wings with
    orange membranes and a wagging tail ending in a spade."""
    pet = Pet("PyroclasmDragon")
    body = bean_body("body", width=0.92, depth=0.88, bottom=-0.95, top=1.22)
    snout = kit.quad_sphere("snout", 1.0, 3, loc=(0.0, -0.66, 0.02), scale=(0.4, 0.26, 0.24))
    body = F.joined("dragonbody", body, snout, consume=True)
    kit.modifier(body, "REMESH", mode="VOXEL", voxel_size=0.025, use_smooth_shade=True)
    body = kit.bake(body)
    kit.modifier(body, "SMOOTH", factor=0.5, iterations=4)
    body = kit.set_smooth(kit.bake(body))
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.31, eye_z=0.36, eye_rx=0.16, eye_ry=0.2, pupil=0.62, mouth="fang",
                  mouth_z=-0.06, mouth_w=0.12, blush=False, brows=True)
    # glowing nostrils, fangs, lava cracks
    lava = []
    for side in (-1, 1):
        lava.append(decal(f"nostril{side}", body, surf.front(side * 0.09, 0.1), 0.035, 0.025, offset=0.006,
                          rings=2, segments=12))
    pet.add("Shine", *F.fangs(body, -0.08, x=0.07, size=0.045))
    seeds = [((0.75, -0.2, 0.3), (0, 0.3, -1)), ((-0.75, -0.1, 0.1), (0, 0.4, -1)), ((0.6, 0.4, -0.3), (0, 1, 0.3)),
             ((-0.55, 0.5, -0.4), (0, 1, 0.4)), ((0.2, 0.8, 0.6), (1, 0, -0.5)), ((-0.25, 0.75, 0.2), (-1, 0, -0.6)),
             ((0.35, 0.3, 0.95), (1, 0.3, -0.4)), ((-0.3, 0.2, 1.0), (-1, 0.4, -0.4)),
             ((0.3, -0.85, -0.45), (0.6, 0, -1)), ((-0.25, -0.85, -0.35), (-0.5, 0, -1)), ((0.0, -0.9, -0.2), (0.2, 0, -1))]
    for k, path in enumerate(crack_paths(surf, seeds, steps=6, step=0.14)):
        lava.append(curve_tube(f"crack{k}", path, 0.024, taper=[0.6 + 0.4 * math.sin(math.pi * i / max(1, len(path) - 1))
                                                               for i in range(len(path))], resolution=2))
    # magma crown: a spiky orange crown with molten (glowing) tips, set back on the head
    top, _ = surf.hit((0, 0.12, 5), (0, 0, -1))
    crown, tips = F.crown("crown", top.z - 0.12, radius=0.3, height=0.2, points=5, base_y=0.12, tilt=-0.2,
                          band=0.1)
    balls = [o for o in crown if "_ball" in o.name]
    for ball in balls:
        crown.remove(ball)
    lava += balls
    pet.add("Neon_FF701C", *lava)
    # back spikes + swept-back horns
    accent = list(crown)
    for k, ang in enumerate((-40, -62, -84, -106, -128)):
        a = math.radians(ang)
        d = Vector((0.0, -math.sin(a), math.cos(a)))
        loc, n = surf.toward(Vector((0, 0, 0.2)) + d * 2, center=(0, 0, 0.2))
        accent.append(F.feather(f"spike{k}", loc - n * 0.05, (n + Vector((0, 0.5, 0))).normalized(), 0.24 - 0.02 * k,
                                0.09, thickness=0.05, curl=0.1, bend_axis=(1, 0, 0), tip=1.4))
    for side in (-1, 1):
        loc, n = surf.toward((side * 0.42, 0.1, 0.95))
        pts = [loc - n * 0.05, loc + Vector((side * 0.16, 0.12, 0.2)), loc + Vector((side * 0.26, 0.38, 0.3)),
               loc + Vector((side * 0.3, 0.6, 0.26))]
        accent.append(curve_tube(f"horn{side}", pts, 0.09, taper=[1.0, 0.8, 0.5, 0.12], bevel_resolution=2,
                                 resolution=4))
    pet.add("Accent", *accent)
    # bat wings: obsidian bones, orange membranes
    bones, membrane = F.membrane_wing("wing", (0.7, 0.35, 0.45), span=1.0, height=0.9, sweep_back=0.4)
    pet.add("Body@WingL", *bones)
    pet.add("Accent@WingL", *membrane)
    pet.add("Body@WingR", *F.mirrored(bones))
    pet.add("Accent@WingR", *F.mirrored(membrane))
    pet.pivot("WingL", (0.72, 0.35, 0.45))
    pet.pivot("WingR", (-0.72, 0.35, 0.45))
    # tail with an orange spade
    root = Vector((0.0, 0.62, -0.62))
    pts = [root, root + Vector((0.05, 0.35, -0.12)), root + Vector((0.2, 0.7, -0.05)), root + Vector((0.35, 0.95, 0.2))]
    pet.add("Body@Wag", kit.subsurf(sweep("tail", pts, [0.17, 0.12, 0.08, 0.05], sides=10), 1))
    spade = kit.extrude_outline("spade", F.smooth_outline([(0.0, 0.3), (0.16, 0.06), (0.06, 0.0), (0.0, -0.06),
                                                          (-0.06, 0.0), (-0.16, 0.06)], 5), 0.06, bevel=0.025)
    kit.set_smooth(spade, True)
    kit.transform(spade, rot=(0, 0, 0))
    d = (pts[-1] - pts[-2]).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    spade.data.transform(rot)
    spade.data.transform(kit.Matrix.Translation(pts[-1] - d * 0.02))
    pet.add("Accent@Wag", spade)
    pet.pivot("Wag", tuple(root))
    return pet


# --------------------------------------------------------------------------------------- 7. Void Leviathan

def void_leviathan():
    """A deep-space sea serpent pup: a dark round body that tapers into a wagging tail with a fluke, cyan
    webbed fin-wings, a dorsal sail and axolotl gill fronds, rows of glowing spots, star specks, an
    anglerfish lure and a glowing halo with orbiting orbs."""
    pet = Pet("VoidLeviathan")
    body = round_body("body", rx=1.0, ry=1.0, rz=0.95, bottom=-0.86)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.36, eye_z=0.02, eye_rx=0.18, eye_ry=0.23, mouth="smile", mouth_z=-0.26,
                  mouth_w=0.1)
    # tail with a fluke (wags)
    root = Vector((0.0, 0.7, -0.35))
    pts = [root, root + Vector((0, 0.35, -0.05)), root + Vector((0, 0.68, 0.05)), root + Vector((0, 0.92, 0.22))]
    tail = kit.subsurf(sweep("tail", pts, [(0.34, 0.3), (0.24, 0.2), (0.15, 0.13), (0.09, 0.08)], sides=12), 1)
    fluke = []
    for side in (-1, 1):
        fl = F.feather(f"fluke{side}", pts[-1] - Vector((0, 0.04, 0)), (side * 0.85, 0.5, 0.25), 0.42, 0.15,
                       thickness=0.05, curl=-0.3 * side, bend_axis=(0, 0, 1), tip=0.9)
        fluke.append(fl)
    pet.add("Body@Wag", tail, *fluke)
    pet.pivot("Wag", tuple(root))
    # fin wings
    web, rays = F.fin_wing("fin", (0.86, 0.3, -0.05), span=0.85, rays=5, height=0.85, sweep_back=0.5)
    pet.add("Accent@WingL", *web, *rays)
    pet.add("Accent@WingR", *F.mirrored(web), *F.mirrored(rays))
    pet.pivot("WingL", (0.86, 0.3, -0.05))
    pet.pivot("WingR", (-0.86, 0.3, -0.05))
    # dorsal sail along the back of the head
    sail = kit.extrude_outline("sail", F.smooth_outline([(-0.45, 0.0), (-0.3, 0.32), (0.0, 0.5), (0.3, 0.42),
                                                         (0.5, 0.18), (0.55, 0.0)], 6), 0.06, bevel=0.025)
    kit.set_smooth(sail, True)
    kit.transform(sail, rot=(0, 0, math.pi / 2))  # outline X -> +Y (front to back)
    kit.transform(sail, rot=(-0.55, 0, 0))
    loc, n = surf.toward((0, 0.55, 0.8))
    kit.transform(sail, loc=tuple(loc - n * 0.12))
    accent = [sail]
    # axolotl gill fronds on the sides of the head, above the fins
    for side in (-1, 1):
        for k, ang in enumerate((62, 38, 14)):
            a = math.radians(ang)
            d = Vector((side * math.cos(a), 0.15, math.sin(a))).normalized()
            base, n = surf.toward((side * 0.72, 0.05, 0.42 + 0.12 * (1 - k)))
            accent.append(F.feather(f"gill{side}{k}", base - d * 0.12, d, 0.46 - 0.05 * abs(k - 1), 0.1,
                                    thickness=0.06, curl=0.22 * side, bend_axis=(0, 1, 0), tip=0.8))
    pet.add("Accent", *accent)
    # glowing spots (two rows along the sides) + the anglerfish lure
    glow = []
    for side in (-1, 1):
        # a curved row of glowing spots from above each eye over the head, and one along each flank
        for k in range(4):
            t = k / 3
            p = Vector((side * (0.42 + 0.12 * t), -0.75 + 1.0 * t, 0.42 + 0.3 * math.sin(math.pi * t * 0.8)))
            loc, n = surf.toward(p)
            r = 0.065 - 0.012 * k
            glow.append(decal(f"spot{side}{k}", body, (loc, n), r, r, offset=0.01, dome=0.02, rings=2, segments=14))
            p2 = Vector((side * 0.92, -0.45 + 0.85 * t, -0.3 + 0.08 * math.sin(math.pi * t)))
            loc, n = surf.toward(p2)
            r = 0.075 - 0.012 * k
            glow.append(decal(f"spot2{side}{k}", body, (loc, n), r, r, offset=0.01, dome=0.02, rings=2, segments=14))
    brow, bn = surf.front(0.0, 0.62)
    stalk = [brow - bn * 0.03, brow + Vector((0, -0.02, 0.28)), brow + Vector((0, -0.18, 0.46)), brow + Vector((0, -0.36, 0.48))]
    pet.add("Body", curve_tube("stalk", stalk, 0.035, taper=[1.0, 0.9, 0.8, 0.7], bevel_resolution=2))
    glow.append(kit.quad_sphere("lure", 1.0, 2, loc=tuple(stalk[-1] + Vector((0, -0.04, -0.05))), scale=(0.1, 0.1, 0.1)))
    pet.add("Neon_40ECFF", *glow)
    # star specks over the back
    stars = []
    for k, p in enumerate(((0.35, 0.45, 0.7), (-0.4, 0.55, 0.62), (0.15, 0.8, 0.3), (-0.2, 0.85, -0.1), (0.55, 0.65, 0.05),
                           (-0.6, 0.45, 0.2))):
        loc, n = surf.toward(p)
        st = F.star(f"speck{k}", (0, 0, 0), size=0.06, depth=0.03, points=4, inner=0.35)
        rot = Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4()
        st.data.transform(rot)
        st.data.transform(kit.Matrix.Translation(loc + n * 0.012))
        stars.append(st)
    pet.add("Neon_FFFFFF", *stars)
    # halo + orbiting orbs
    spin = [F.halo("halo", 1.32, radius=0.4, tube=0.045)]
    for i in range(3):
        a = 2 * math.pi * i / 3
        orb = kit.quad_sphere(f"orb{i}", 1.0, 2, scale=(0.07, 0.07, 0.07))
        kit.transform(orb, loc=(math.cos(a) * 1.35, math.sin(a) * 1.35, 0))
        kit.transform(orb, rot=(0.3, 0, 0))
        kit.transform(orb, loc=(0, 0, -0.1))
        spin.append(orb)
    pet.add("Neon_40ECFF@SpinY", *spin)
    return pet


# --------------------------------------------------------------------------------------- 8. Nova Seraph

def nova_seraph():
    """A seraph chick: a soft cream round body with a curl on top, two pairs of golden feathered wings, a
    feather ruff, a gold diadem with a pink star gem, a glowing halo with orbiting star sparkles and a
    happy open smile."""
    pet = Pet("NovaSeraph")
    body = round_body("body", rx=1.0, ry=0.98, rz=0.96, bottom=-0.86)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.36, eye_z=0.04, eye_rx=0.18, eye_ry=0.23, mouth=None)
    F.open_mouth(pet, body, -0.24, w=0.085, h=0.065)
    # a little curl on top
    top, n = surf.hit((0.0, -0.05, 4.0), (0, 0, -1))
    curl = [top - Vector((0, 0, 0.05))]
    for i in range(1, 9):
        a = math.pi * 1.6 * i / 8
        r = 0.16 * (1 - i / 10)
        curl.append(top + Vector((0, -math.sin(a) * r, 0.12 + (1 - math.cos(a)) * r * 0.9)))
    pet.add("Body", curve_tube("curl", curl, 0.06, taper=[1.0 - 0.75 * i / 8 for i in range(9)], bevel_resolution=2))
    # feather ruff under the chin
    ruff = []
    for k in range(5):
        x = -0.44 + 0.22 * k
        loc, n = surf.front(x, -0.5 + 0.14 * (x / 0.44) ** 2)
        d = (n * 0.8 + Vector((x * 0.9, 0, -0.75))).normalized()
        ruff.append(F.feather(f"ruff{k}", loc - d * 0.12 - n * 0.03, d, 0.3, 0.15, thickness=0.06,
                              curl=0.1 * (1 if x > 0 else -1), bend_axis=(0, 1, 0), tip=0.5))
    pet.add("Accent", *ruff)
    # gold diadem with a star, pink gem
    band = []
    for t in range(13):
        x = -0.5 + 1.0 * t / 12
        loc, n = surf.front(x, 0.5 + 0.22 * abs(x / 0.5) ** 1.5)
        band.append(loc + n * 0.015)
    gold = [curve_tube("diadem", band, 0.024, resolution=2)]
    loc, n = surf.front(0.0, 0.5)
    st = F.star("diademstar", (0, 0, 0), size=0.13, depth=0.05, inner=0.45)
    rot = Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4()
    st.data.transform(rot)
    st.data.transform(kit.Matrix.Translation(loc + n * 0.04))
    gold.append(st)
    pet.add("Color_FFD23C", *gold)
    pet.add("Neon_FFAAF0", F.gem("diademgem", loc + n * 0.085, 0.045))
    pet.flat_roles.add("Neon_FFAAF0")
    # two pairs of wings per side: a big upper pair and a smaller lower pair
    upper = F.feather_wing("wingU", (0.86, 0.38, 0.3), span=1.05, count=5, base_angle=5, fan=80, width=0.19,
                           thickness=0.05, sweep_back=0.42, curl=0.22, tip=0.3)
    lower = F.feather_wing("wingD", (0.84, 0.42, -0.15), span=0.7, count=4, base_angle=-60, fan=50, width=0.16,
                           thickness=0.045, sweep_back=0.55, curl=-0.2, coverts=2, arm=False, tip=0.3)
    pet.add("Accent@WingL", *upper, *lower)
    pet.add("Accent@WingR", *F.mirrored(upper), *F.mirrored(lower))
    pet.pivot("WingL", (0.86, 0.4, 0.1))
    pet.pivot("WingR", (-0.86, 0.4, 0.1))
    # halo with star sparkles orbiting on a tilted ring
    spin = [F.halo("halo", top.z + 0.42, radius=0.42, tube=0.05)]
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.4
        sp = F.star(f"spark{i}", (0, 0, 0), size=0.12, depth=0.05, points=4, inner=0.32, rot=(0, 0, a + math.pi / 2))
        kit.transform(sp, loc=(math.cos(a) * 1.35, math.sin(a) * 1.35, 0))
        kit.transform(sp, rot=(0.3, 0, 0))
        kit.transform(sp, loc=(0, 0, -0.05))
        spin.append(sp)
    pet.add("Neon_FFD65A@SpinY", *spin)
    return pet


# --------------------------------------------------------------------------------------- 9. Hypercane

def hypercane():
    """The ultimate storm: a black thundercloud with magenta devil horns, a gold crown, a magenta halo,
    bat wings, cyan lightning bolts striking from its underside and hurricane bands spiralling around it."""
    pet = Pet("Hypercane")
    puffs = [
        ((0.0, 0.0, -0.05), (1.08, 0.98, 0.92)),
        ((-0.95, 0.08, -0.25), (0.68, 0.66, 0.64)),
        ((0.95, 0.08, -0.25), (0.68, 0.66, 0.64)),
        ((-1.4, 0.18, -0.5), (0.44, 0.42, 0.42)),
        ((1.4, 0.18, -0.5), (0.44, 0.42, 0.42)),
        ((-0.55, 0.12, 0.66), (0.62, 0.6, 0.58)),
        ((0.55, 0.12, 0.66), (0.62, 0.6, 0.58)),
        ((0.0, 0.2, 0.95), (0.6, 0.58, 0.55)),
        ((-1.05, 0.3, 0.3), (0.45, 0.45, 0.45)),
        ((1.05, 0.3, 0.3), (0.45, 0.45, 0.45)),
        ((0.0, 0.62, 0.05), (0.92, 0.7, 0.88)),
        ((-0.55, -0.05, -0.75), (0.52, 0.5, 0.36)),
        ((0.55, -0.05, -0.75), (0.52, 0.5, 0.36)),
    ]
    body = cloud_body("body", puffs)
    pet.add("Body", body)
    surf = F.face(pet, body, eye_x=0.38, eye_z=-0.06, eye_rx=0.19, eye_ry=0.23, pupil=0.7, mouth="fang",
                  mouth_z=-0.36, mouth_w=0.11, brows=True)
    pet.add("Shine", *F.fangs(body, -0.38, x=0.06, size=0.04))
    # horns
    horns = []
    for side in (-1, 1):
        loc, n = surf.toward((side * 0.62, 0.05, 1.05))
        pts = [loc - n * 0.08, loc + Vector((side * 0.12, 0.0, 0.2)), loc + Vector((side * 0.2, 0.04, 0.42)),
               loc + Vector((side * 0.1, 0.06, 0.6))]
        horns.append(curve_tube(f"horn{side}", pts, 0.12, taper=[1.0, 0.82, 0.5, 0.08], bevel_resolution=2, resolution=4))
    pet.add("Accent", *horns)
    # gold crown, tilted on the top puff
    top, _ = surf.hit((0, 0.2, 5), (0, 0, -1))
    gold, _tips = F.crown("crown", top.z - 0.1, radius=0.3, height=0.3, points=5, base_y=0.18, tilt=-0.18)
    pet.add("Color_FFD23C", *gold)
    # lightning bolts striking from the underside
    bolts = []
    for k, (x, y, s, r) in enumerate(((-0.75, -0.25, 0.26, 0.25), (0.15, -0.45, 0.3, -0.12), (0.85, -0.1, 0.24, -0.3))):
        loc, n = surf.hit((x, y, -5), (0, 0, 1))
        b = F.bolt(f"bolt{k}", (0, 0, 0), scale=s, depth=0.08, rot=(0, r, 0), bevel=0.022)
        kit.transform(b, loc=tuple(loc + Vector((0, 0, -s * 0.85))))
        bolts.append(b)
    # glowing eye-of-the-hurricane spiral on the brow
    for k in range(2):
        pts = F.spiral_points(turns=0.7, r0=0.06, r1=0.2, n=12, phase=math.pi * k + 0.4, cx=0.0, cz=0.38)
        path = kit.surface_path(surf, pts, offset=0.025)
        bolts.append(curve_tube(f"sp{k}", path, 0.035, taper=[1.0 - 0.7 * i / 11 for i in range(len(path))]))
    pet.add("Neon_50E6FF", *bolts)
    # bat wings
    bones, membrane = F.membrane_wing("wing", (1.15, 0.45, 0.35), span=0.95, height=0.85, sweep_back=0.35)
    pet.add("Accent@WingL", *bones, *membrane)
    pet.add("Accent@WingR", *F.mirrored(bones), *F.mirrored(membrane))
    pet.pivot("WingL", (1.17, 0.45, 0.35))
    pet.pivot("WingR", (-1.17, 0.45, 0.35))
    # hurricane bands: three puffy spiral arms around the base
    arms = []
    for i in range(3):
        a0 = 2 * math.pi * i / 3
        pts, radii = [], []
        for k in range(18):
            t = k / 17
            a = a0 + t * 2.5
            r = 1.25 + 0.75 * t
            pts.append((math.cos(a) * r, math.sin(a) * r, -0.62 + 0.1 * t))
            w = (1.0 - t) ** 0.7 * min(1.0, 4 * t + 0.35)
            radii.append((0.2 * w + 0.01, 0.075 * w + 0.01))
        radii[-1] = (0.0, 0.0)
        arms.append(kit.subsurf(sweep(f"band{i}", pts, radii, sides=10, up=(0, 0, 1)), 1))
    pet.add("Accent@SpinY", *arms)
    pet.add("Neon_FF54DC@SpinY", F.halo("halo", top.z + 0.5, radius=0.42, tube=0.05))
    return pet


BUILDERS = {
    "EyeOfTheStorm": eye_of_the_storm,
    "ThunderKirin": thunder_kirin,
    "SandstormSphinx": sandstorm_sphinx,
    "BlizzardMonarch": blizzard_monarch,
    "TempestPhoenix": tempest_phoenix,
    "PyroclasmDragon": pyroclasm_dragon,
    "VoidLeviathan": void_leviathan,
    "NovaSeraph": nova_seraph,
    "Hypercane": hypercane,
}
