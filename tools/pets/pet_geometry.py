# =============================================================================
# Stormling pet geometry - Storm Catcher Simulator
# =============================================================================
#
# One pure-Python file that describes every pet ("Stormling") as smooth cartoon
# triangle meshes. It is used in two places:
#   * tools/pets/build_pets.py (normal Python) runs this file and exports the
#     Roblox mesh pack (assets/models/StormlingPets.glb / .obj) + preview renders.
#   * The Trimble SketchUp MCP sandbox: the file is pasted verbatim into
#     build_model and sketchup_layout() gives every mesh in SketchUp axes.
#
# SANDBOX RULES (keep them when editing!): the file must not load modules (the
# `math` module is pre-loaded), must not run dynamic code, open files, call the
# type/setattr builtins or touch double-underscore attributes; no classes, no
# f-string format specs, no printing. Only plain functions, dicts, lists,
# tuples and these builtins: range, len, min, max, abs, int, float, str, list,
# dict, tuple, enumerate, isinstance, sorted, sum.
# `python tools/pets/build_pets.py --check` enforces all of this.
#
# MESH PACK CONTRACT (see tools/pets/README.md):
#   * Roblox studs, Y up, the pet's front faces -Z, origin = pet centre.
#     Body "radius" is ~1 stud (PetModels.Scale applies rarity/tier scale).
#   * build_pet(pet_id) -> [{"name": role, "verts": [(x,y,z)], "tris": [(i,j,k)]}]
#     Roles: Body, Accent (tintable), Eye, Shine, Blush, Mouth,
#     Color_RRGGBB, Neon_RRGGBB, Ice_RRGGBB, an "@WingL|WingR|Wag|SpinY|SpinZ"
#     suffix for animated pieces, Pivot@<Anim> hinge markers (0.1 cube) and the
#     Root marker (0.2 cube at the origin).
#   * Triangles are wound counter-clockwise seen from outside (right-handed).
#     Shared vertices = smooth shading, duplicated vertices = hard edges.
#
# Entry points: build_pet(pet_id), build_all(), PET_IDS, PETS, DESIGN,
# role_color(role, look), pack_offset(index), to_sketchup(meshes, inches_per_stud),
# sketchup_layout(pet_ids, inches_per_stud).
# =============================================================================

PI = math.pi
TAU = math.pi * 2.0
UP = (0.0, 1.0, 0.0)


# ----------------------------------------------------------------------------- scalar helpers

def rad(deg):
    return deg * PI / 180.0


def clamp(x, lo, hi):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(t):
    t = clamp(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def spow(x, p):
    # sign-preserving power (never produces complex numbers)
    if x > 0:
        return x ** p
    if x < 0:
        return -((-x) ** p)
    return 0.0


def ease_ends(i, n, k):
    # parameter 0..1 with samples bunched near both ends (k = 0 -> uniform)
    t = i / float(n)
    return lerp(t, 0.5 - 0.5 * math.cos(PI * t), k)


# ----------------------------------------------------------------------------- vector helpers

def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vmad(a, b, s):
    return (a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def vlen(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def vnorm(a):
    length = vlen(a)
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (a[0] / length, a[1] / length, a[2] / length)


def vlerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def perpendicular(v):
    # any unit vector perpendicular to v
    if abs(v[1]) < 0.9:
        return vnorm(vcross(v, UP))
    return vnorm(vcross(v, (1.0, 0.0, 0.0)))


def ydir(yaw, pitch):
    # unit direction from the body centre: yaw 0 = front (-Z), +yaw -> +X, +pitch -> up (degrees)
    cy = math.cos(rad(pitch))
    return (math.sin(rad(yaw)) * cy, math.sin(rad(pitch)), -math.cos(rad(yaw)) * cy)


# ----------------------------------------------------------------------------- meshes

def new_mesh():
    return {"verts": [], "tris": []}


def append_mesh(dst, src):
    base = len(dst["verts"])
    dst["verts"].extend(src["verts"])
    for t in src["tris"]:
        dst["tris"].append((t[0] + base, t[1] + base, t[2] + base))
    return dst


def merge_meshes(meshes):
    out = new_mesh()
    for m in meshes:
        append_mesh(out, m)
    return out


def flip_mesh(m):
    return {"verts": list(m["verts"]), "tris": [(t[0], t[2], t[1]) for t in m["tris"]]}


def map_mesh(m, fn):
    return {"verts": [fn(p) for p in m["verts"]], "tris": list(m["tris"])}


def unweld_mesh(m):
    # every triangle gets its own vertices -> flat (faceted) shading
    verts = []
    tris = []
    for t in m["tris"]:
        base = len(verts)
        verts.append(m["verts"][t[0]])
        verts.append(m["verts"][t[1]])
        verts.append(m["verts"][t[2]])
        tris.append((base, base + 1, base + 2))
    return {"verts": verts, "tris": tris}


def qkey(p):
    return (int(math.floor(p[0] * 100000.0 + 0.5)), int(math.floor(p[1] * 100000.0 + 0.5)),
            int(math.floor(p[2] * 100000.0 + 0.5)))


def weld_mesh(m):
    index = {}
    verts = []
    remap = []
    for p in m["verts"]:
        k = qkey(p)
        if k in index:
            remap.append(index[k])
        else:
            index[k] = len(verts)
            remap.append(len(verts))
            verts.append(p)
    tris = []
    for t in m["tris"]:
        a = remap[t[0]]
        b = remap[t[1]]
        c = remap[t[2]]
        if a != b and b != c and a != c:
            tris.append((a, b, c))
    return {"verts": verts, "tris": tris}


def signed_volume(m):
    v = m["verts"]
    total = 0.0
    for t in m["tris"]:
        total += vdot(v[t[0]], vcross(v[t[1]], v[t[2]]))
    return total / 6.0


def orient_outward(m):
    # closed meshes only: make the signed volume positive
    if signed_volume(m) < 0:
        return flip_mesh(m)
    return m


def mesh_bounds(m):
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for p in m["verts"]:
        for i in range(3):
            if p[i] < lo[i]:
                lo[i] = p[i]
            if p[i] > hi[i]:
                hi[i] = p[i]
    return (tuple(lo), tuple(hi))


def tri_count(meshes):
    return sum([len(m["tris"]) for m in meshes])


# ----------------------------------------------------------------------------- transforms
# A transform is a 3x4 affine matrix ((r00, r01, r02, tx), (r10, ...), (r20, ...)).

def xf_identity():
    return ((1.0, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0))


def xf_translate(x, y, z):
    return ((1.0, 0.0, 0.0, x), (0.0, 1.0, 0.0, y), (0.0, 0.0, 1.0, z))


def xf_scale(sx, sy, sz):
    return ((sx, 0.0, 0.0, 0.0), (0.0, sy, 0.0, 0.0), (0.0, 0.0, sz, 0.0))


def xf_rot_x(a):
    c = math.cos(a)
    s = math.sin(a)
    return ((1.0, 0.0, 0.0, 0.0), (0.0, c, -s, 0.0), (0.0, s, c, 0.0))


def xf_rot_y(a):
    c = math.cos(a)
    s = math.sin(a)
    return ((c, 0.0, s, 0.0), (0.0, 1.0, 0.0, 0.0), (-s, 0.0, c, 0.0))


def xf_rot_z(a):
    c = math.cos(a)
    s = math.sin(a)
    return ((c, -s, 0.0, 0.0), (s, c, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0))


def xf_rot_axis(axis, a):
    x, y, z = vnorm(axis)
    c = math.cos(a)
    s = math.sin(a)
    t = 1.0 - c
    return ((t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0.0),
            (t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0.0),
            (t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0.0))


def xf_basis(xa, ya, za, origin):
    # columns are the local axes expressed in world space
    return ((xa[0], ya[0], za[0], origin[0]), (xa[1], ya[1], za[1], origin[1]), (xa[2], ya[2], za[2], origin[2]))


def xf_frame(origin, y_dir, z_hint):
    # local +Y along y_dir, local +Z as close as possible to z_hint (right-handed)
    y = vnorm(y_dir)
    z = vsub(z_hint, vmul(y, vdot(z_hint, y)))
    if vlen(z) < 1e-6:
        z = perpendicular(y)
    z = vnorm(z)
    x = vcross(y, z)
    return xf_basis(x, y, z, origin)


def xf_mul(a, b):
    # a after b (apply b first)
    rows = []
    for i in range(3):
        r = a[i]
        rows.append((r[0] * b[0][0] + r[1] * b[1][0] + r[2] * b[2][0],
                     r[0] * b[0][1] + r[1] * b[1][1] + r[2] * b[2][1],
                     r[0] * b[0][2] + r[1] * b[1][2] + r[2] * b[2][2],
                     r[0] * b[0][3] + r[1] * b[1][3] + r[2] * b[2][3] + r[3]))
    return (rows[0], rows[1], rows[2])


def xf_chain(xfs):
    # apply xfs[0] first, then xfs[1], ...
    out = xf_identity()
    for x in xfs:
        out = xf_mul(x, out)
    return out


def xf_point(m, p):
    return (m[0][0] * p[0] + m[0][1] * p[1] + m[0][2] * p[2] + m[0][3],
            m[1][0] * p[0] + m[1][1] * p[1] + m[1][2] * p[2] + m[1][3],
            m[2][0] * p[0] + m[2][1] * p[1] + m[2][2] * p[2] + m[2][3])


def xf_dir(m, d):
    return (m[0][0] * d[0] + m[0][1] * d[1] + m[0][2] * d[2],
            m[1][0] * d[0] + m[1][1] * d[1] + m[1][2] * d[2],
            m[2][0] * d[0] + m[2][1] * d[1] + m[2][2] * d[2])


def xf_det(m):
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def transform_mesh(m, xf):
    out = {"verts": [xf_point(xf, p) for p in m["verts"]], "tris": list(m["tris"])}
    if xf_det(xf) < 0:
        out = flip_mesh(out)
    return out


def xform(m, xfs):
    return transform_mesh(m, xf_chain(xfs))


def translate_mesh(m, x, y, z):
    return transform_mesh(m, xf_translate(x, y, z))


def scale_mesh(m, sx, sy, sz):
    return transform_mesh(m, xf_scale(sx, sy, sz))


def rotate_mesh(m, axis, angle):
    return transform_mesh(m, xf_rot_axis(axis, angle))


def mirror_x(m):
    return transform_mesh(m, xf_scale(-1.0, 1.0, 1.0))


# ----------------------------------------------------------------------------- curves

def bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    a = u * u * u
    b = 3.0 * u * u * t
    c = 3.0 * u * t * t
    d = t * t * t
    return (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
            a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
            a * p0[2] + b * p1[2] + c * p2[2] + d * p3[2])


def bezier_points(ctrl, n, ease=0.0):
    return [bezier(ctrl[0], ctrl[1], ctrl[2], ctrl[3], ease_ends(i, n, ease)) for i in range(n + 1)]


def catmull_rom(points, per_segment):
    # smooth curve through every point (end points duplicated)
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0 = pts[i - 1]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[i + 2]
        for j in range(per_segment):
            t = j / float(per_segment)
            t2 = t * t
            t3 = t2 * t
            out.append(tuple([0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * t + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2
                                     + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3) for k in range(3)]))
    out.append(points[-1])
    return out


def polyline_length(points):
    total = 0.0
    for i in range(1, len(points)):
        total += vlen(vsub(points[i], points[i - 1]))
    return total


def resample_polyline(points, n):
    # n+1 points evenly spaced by arc length
    lengths = [0.0]
    for i in range(1, len(points)):
        lengths.append(lengths[-1] + vlen(vsub(points[i], points[i - 1])))
    total = lengths[-1]
    out = []
    j = 0
    for i in range(n + 1):
        target = total * i / float(n)
        while j < len(points) - 2 and lengths[j + 1] < target:
            j += 1
        span = lengths[j + 1] - lengths[j]
        t = 0.0 if span < 1e-12 else (target - lengths[j]) / span
        out.append(vlerp(points[j], points[j + 1], clamp(t, 0.0, 1.0)))
    return out


# ----------------------------------------------------------------------------- section stitching

def stitch_sections(sections, closed=False):
    # sections: list of ("pole", point) or ("ring", [points]); rings share one length.
    # Rings run counter-clockwise around the travel direction (see tube()).
    verts = []
    ids = []
    for s in sections:
        if s[0] == "pole":
            ids.append(len(verts))
            verts.append(s[1])
        else:
            start = len(verts)
            verts.extend(s[1])
            ids.append(list(range(start, start + len(s[1]))))
    tris = []
    count = len(sections)
    pairs = [(i, i + 1) for i in range(count - 1)]
    if closed:
        pairs.append((count - 1, 0))
    for (i, j) in pairs:
        a = ids[i]
        b = ids[j]
        a_ring = isinstance(a, list)
        b_ring = isinstance(b, list)
        if a_ring and b_ring:
            m = len(a)
            for k in range(m):
                k1 = (k + 1) % m
                tris.append((a[k], a[k1], b[k1]))
                tris.append((a[k], b[k1], b[k]))
        elif b_ring:
            m = len(b)
            for k in range(m):
                tris.append((a, b[(k + 1) % m], b[k]))
        elif a_ring:
            m = len(a)
            for k in range(m):
                tris.append((b, a[k], a[(k + 1) % m]))
    return {"verts": verts, "tris": tris}


# ----------------------------------------------------------------------------- primitives

CUBE_FACES = (
    ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
    ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
    ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
    ((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
    ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
    ((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
)


def grid_faces(coords_u, coords_v, point_fn):
    # Six welded cube-face grids. point_fn(normal, ua, va, a, b) -> point.
    verts = []
    tris = []
    index = {}
    for face in CUBE_FACES:
        nrm = face[0]
        ua = face[1]
        va = face[2]
        rows = []
        for b in coords_v:
            row = []
            for a in coords_u:
                p = point_fn(nrm, ua, va, a, b)
                k = qkey(p)
                if k not in index:
                    index[k] = len(verts)
                    verts.append(p)
                row.append(index[k])
            rows.append(row)
        nu = len(coords_u) - 1
        nv = len(coords_v) - 1
        for j in range(nv):
            for i in range(nu):
                a = rows[j][i]
                b = rows[j][i + 1]
                c = rows[j + 1][i + 1]
                d = rows[j + 1][i]
                if (i * 2 < nu) == (j * 2 < nv):
                    tris.append((a, b, c))
                    tris.append((a, c, d))
                else:
                    tris.append((a, b, d))
                    tris.append((b, c, d))
    return weld_mesh({"verts": verts, "tris": tris})


def quad_sphere(n):
    # unit sphere from an equal-angle subdivided cube (no poles, even triangles)
    n = max(2, int(n))
    coords = [math.tan((i / float(n) * 2.0 - 1.0) * PI / 4.0) for i in range(n + 1)]

    def point(nrm, ua, va, a, b):
        return vnorm((nrm[0] + ua[0] * a + va[0] * b, nrm[1] + ua[1] * a + va[1] * b, nrm[2] + ua[2] * a + va[2] * b))
    return grid_faces(coords, coords, point)


def radial_mesh(surface_fn, n):
    # star-shaped surface: maps every unit direction of a quad sphere through surface_fn
    return map_mesh(quad_sphere(n), surface_fn)


def ellipsoid(rx, ry, rz, n=6):
    return scale_mesh(quad_sphere(n), rx, ry, rz)


def uv_sphere(rx, ry, rz, seg=12, rings=8):
    profile = []
    for i in range(rings + 1):
        a = -PI / 2.0 + PI * i / float(rings)
        profile.append((math.cos(a), math.sin(a)))
    m = lathe(profile, seg)
    return scale_mesh(m, rx, ry, rz)


def lathe(profile, sides=16, cap0="flat", cap1="flat"):
    # Revolve profile [(radius, y), ...] (listed bottom -> top) around the Y axis.
    # Radius 0 at an end makes a pole; otherwise the end is capped flat (or left open).
    sections = []
    if profile[0][0] > 1e-9 and cap0 == "flat":
        sections.append(("pole", (0.0, profile[0][1], 0.0)))
    for (r, y) in profile:
        if r <= 1e-9:
            sections.append(("pole", (0.0, y, 0.0)))
        else:
            ring = []
            for k in range(sides):
                a = TAU * k / float(sides)
                ring.append((r * math.cos(a), y, -r * math.sin(a)))
            sections.append(("ring", ring))
    if profile[-1][0] > 1e-9 and cap1 == "flat":
        sections.append(("pole", (0.0, profile[-1][1], 0.0)))
    return stitch_sections(sections)


def tube(path, radii, sides=8, cap0="round", cap1="round", up=None, cap_steps=3, roll=0.0):
    # Sweep an ellipse along a polyline using rotation-minimising frames.
    # radii: one value per path point, a number or (rx, ry); rx follows the frame
    #        "normal" N (initialised from `up`), ry the binormal B = T x N.
    # A radius of 0 at an end makes a pointed pole; caps: "round", "flat", "none".
    n = len(path)
    tangents = []
    for i in range(n):
        if i == 0:
            d = vsub(path[1], path[0])
        elif i == n - 1:
            d = vsub(path[n - 1], path[n - 2])
        else:
            d = vsub(path[i + 1], path[i - 1])
        tangents.append(vnorm(d))
    t0 = tangents[0]
    if up is None:
        normal = perpendicular(t0)
    else:
        normal = vsub(up, vmul(t0, vdot(up, t0)))
        normal = perpendicular(t0) if vlen(normal) < 1e-6 else vnorm(normal)
    if roll != 0.0:
        normal = xf_dir(xf_rot_axis(t0, roll), normal)
    frames = []
    for i in range(n):
        t = tangents[i]
        normal = vsub(normal, vmul(t, vdot(normal, t)))
        normal = perpendicular(t) if vlen(normal) < 1e-6 else vnorm(normal)
        frames.append((t, normal, vcross(t, normal)))

    def rxy(r):
        if isinstance(r, tuple) or isinstance(r, list):
            return (float(r[0]), float(r[1]))
        return (float(r), float(r))

    def ring(p, frame, rx, ry):
        out = []
        for k in range(sides):
            a = TAU * k / float(sides)
            ca = math.cos(a)
            sa = math.sin(a)
            out.append((p[0] + frame[1][0] * ca * rx + frame[2][0] * sa * ry,
                        p[1] + frame[1][1] * ca * rx + frame[2][1] * sa * ry,
                        p[2] + frame[1][2] * ca * rx + frame[2][2] * sa * ry))
        return out

    sections = []
    r0 = rxy(radii[0])
    if max(r0) <= 1e-9:
        sections.append(("pole", path[0]))
    else:
        if cap0 == "flat":
            sections.append(("pole", path[0]))
        elif cap0 == "round":
            depth = (r0[0] + r0[1]) * 0.5
            sections.append(("pole", vmad(path[0], frames[0][0], -depth)))
            for j in range(cap_steps, 0, -1):
                phi = (PI / 2.0) * j / float(cap_steps + 1)
                sections.append(("ring", ring(vmad(path[0], frames[0][0], -depth * math.sin(phi)), frames[0],
                                              r0[0] * math.cos(phi), r0[1] * math.cos(phi))))
        sections.append(("ring", ring(path[0], frames[0], r0[0], r0[1])))
    for i in range(1, n - 1):
        r = rxy(radii[i])
        sections.append(("ring", ring(path[i], frames[i], max(r[0], 1e-5), max(r[1], 1e-5))))
    r1 = rxy(radii[n - 1])
    last = path[n - 1]
    if max(r1) <= 1e-9:
        sections.append(("pole", last))
    else:
        sections.append(("ring", ring(last, frames[n - 1], r1[0], r1[1])))
        if cap1 == "flat":
            sections.append(("pole", last))
        elif cap1 == "round":
            depth = (r1[0] + r1[1]) * 0.5
            for j in range(1, cap_steps + 1):
                phi = (PI / 2.0) * j / float(cap_steps + 1)
                sections.append(("ring", ring(vmad(last, frames[n - 1][0], depth * math.sin(phi)), frames[n - 1],
                                              r1[0] * math.cos(phi), r1[1] * math.cos(phi))))
            sections.append(("pole", vmad(last, frames[n - 1][0], depth)))
    return stitch_sections(sections)


def sweep(ctrl, n, radius_fn, sides=8, up=None, cap0="round", cap1="round", ease=0.0, t0=0.0, t1=1.0, cap_steps=3):
    # Tube along a cubic bezier (4 control points) or a catmull-rom list (more points);
    # radius_fn(t) -> r or (rx, ry) with t in [t0, t1] of the full curve.
    if len(ctrl) == 4:
        dense = bezier_points(ctrl, 64)
    else:
        dense = catmull_rom(ctrl, 16)
    dense = resample_polyline(dense, 96)
    path = []
    radii = []
    for i in range(n + 1):
        t = lerp(t0, t1, ease_ends(i, n, ease))
        f = t * 96.0
        j = int(clamp(math.floor(f), 0, 95))
        path.append(vlerp(dense[j], dense[j + 1], f - j))
        radii.append(radius_fn(t))
    return tube(path, radii, sides, cap0, cap1, up, cap_steps)


def taper_fn(r0, r1, power=1.0):
    # radius function for sweep(): r0 at t=0 -> r1 at t=1
    def fn(t):
        return r0 + (r1 - r0) * (t ** power)
    return fn


def horn_fn(r0, power=1.6, curve=0.85):
    # radius function with a rounded point at t=1
    def fn(t):
        return r0 * (max(0.0, 1.0 - t ** power) ** curve)
    return fn


def fade_fn(r0, power=0.8, floor=0.004):
    def fn(t):
        return r0 * ((1.0 - t) ** power) + floor
    return fn


def capsule(radius, length, sides=12, rings=4):
    # along Y, centred on the origin
    half = length * 0.5
    return tube([(0.0, -half, 0.0), (0.0, half, 0.0)], [radius, radius], sides, "round", "round",
                (1.0, 0.0, 0.0), rings)


def cone(r0, r1, height, sides=10, tip_round=0.0, rings=1):
    # frustum / cone along +Y from y=0; tip_round > 0 rounds the top with that radius
    profile = [(r0, 0.0)]
    top = height
    if tip_round > 0.0:
        top = height - tip_round
    for i in range(1, rings + 1):
        t = i / float(rings)
        profile.append((lerp(r0, max(r1, tip_round), t), top * t))
    if tip_round > 0.0:
        rr = max(r1, tip_round)
        for j in range(1, 4):
            phi = (PI / 2.0) * j / 4.0
            profile.append((rr * math.cos(phi), top + tip_round * math.sin(phi)))
        profile.append((0.0, top + tip_round))
    return lathe(profile, sides, "flat", "flat")


def torus(major, minor, seg=24, sides=8):
    # ring in the XZ plane around the Y axis
    sections = []
    for i in range(seg):
        th = TAU * i / float(seg)
        e = (math.cos(th), 0.0, -math.sin(th))
        c = vmul(e, major)
        ring = []
        for k in range(sides):
            ph = TAU * k / float(sides)
            ring.append(vadd(c, vadd(vmul(e, minor * math.cos(ph)), (0.0, minor * math.sin(ph), 0.0))))
        sections.append(("ring", ring))
    return orient_outward(stitch_sections(sections, True))


def torus_arc(major, minor, start, end, seg=16, sides=8):
    # partial ring (angles in radians, in the XZ plane) with rounded ends
    path = []
    for i in range(seg + 1):
        th = lerp(start, end, i / float(seg))
        path.append((major * math.cos(th), 0.0, -major * math.sin(th)))
    return tube(path, [minor] * (seg + 1), sides, "round", "round", UP)


def rounded_box(hx, hy, hz, r, flat=1, steps=3):
    # box with half-sizes hx, hy, hz and rounded edges of radius r (flat faces stay flat)
    r = min(r, hx, hy, hz)

    def coords(h):
        inner = h - r
        band = [inner + r * math.tan(PI / 4.0 * j / float(steps)) for j in range(steps + 1)]
        mid = [lerp(-inner, inner, i / float(flat)) for i in range(1, flat)]
        return [-v for v in band[::-1]] + mid + band

    cx = coords(hx)
    cy = coords(hy)
    cz = coords(hz)

    def point(nrm, ua, va, a, b):
        # nrm/ua/va are axis-aligned: work out which axis each one is
        q = [0.0, 0.0, 0.0]
        for ax in range(3):
            q[ax] = nrm[ax] * (hx, hy, hz)[ax] + ua[ax] * a + va[ax] * b
        inner = (clamp(q[0], -(hx - r), hx - r), clamp(q[1], -(hy - r), hy - r), clamp(q[2], -(hz - r), hz - r))
        return vadd(inner, vmul(vnorm(vsub(tuple(q), inner)), r))

    verts = []
    tris = []
    index = {}
    for face in CUBE_FACES:
        nrm = face[0]
        ua = face[1]
        va = face[2]
        au = 0 if ua[0] != 0 else (1 if ua[1] != 0 else 2)
        av = 0 if va[0] != 0 else (1 if va[1] != 0 else 2)
        lists = (cx, cy, cz)
        cu = lists[au]
        cv = lists[av]
        rows = []
        for b in cv:
            row = []
            for a in cu:
                p = point(nrm, ua, va, a, b)
                k = qkey(p)
                if k not in index:
                    index[k] = len(verts)
                    verts.append(p)
                row.append(index[k])
            rows.append(row)
        for j in range(len(cv) - 1):
            for i in range(len(cu) - 1):
                tris.append((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1]))
                tris.append((rows[j][i], rows[j + 1][i + 1], rows[j + 1][i]))
    return orient_outward(weld_mesh({"verts": verts, "tris": tris}))


def box(hx, hy, hz):
    # plain hard-edged box (marker cubes)
    m = new_mesh()
    for face in CUBE_FACES:
        nrm = face[0]
        ua = face[1]
        va = face[2]
        base = len(m["verts"])
        for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            m["verts"].append(((nrm[0] + ua[0] * a + va[0] * b) * hx, (nrm[1] + ua[1] * a + va[1] * b) * hy,
                               (nrm[2] + ua[2] * a + va[2] * b) * hz))
        m["tris"].append((base, base + 1, base + 2))
        m["tris"].append((base, base + 2, base + 3))
    return m


# ----------------------------------------------------------------------------- 2D shapes + extrusion

def poly_area(poly):
    total = 0.0
    for i in range(len(poly)):
        a = poly[i - 1]
        b = poly[i]
        total += a[0] * b[1] - b[0] * a[1]
    return total * 0.5


def _cross2(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _in_tri(p, a, b, c):
    d1 = _cross2(a, b, p)
    d2 = _cross2(b, c, p)
    d3 = _cross2(c, a, p)
    return d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12


def triangulate(poly):
    # ear clipping for a simple counter-clockwise polygon -> index triples (CCW)
    idx = list(range(len(poly)))
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 5000:
        guard += 1
        found = False
        count = len(idx)
        for i in range(count):
            a = idx[i - 1]
            b = idx[i]
            c = idx[(i + 1) % count]
            if _cross2(poly[a], poly[b], poly[c]) <= 1e-12:
                continue
            ok = True
            for j in idx:
                if j == a or j == b or j == c:
                    continue
                if _in_tri(poly[j], poly[a], poly[b], poly[c]):
                    ok = False
                    break
            if ok:
                tris.append((a, b, c))
                idx.pop(i)
                found = True
                break
        if not found:
            break
    for i in range(1, len(idx) - 1):
        tris.append((idx[0], idx[i], idx[i + 1]))
    return tris


def inset_poly(poly, d):
    # move every vertex of a CCW polygon inwards by d (mitred, clamped)
    out = []
    n = len(poly)
    for i in range(n):
        p0 = poly[i - 1]
        p1 = poly[i]
        p2 = poly[(i + 1) % n]
        e1 = (p1[0] - p0[0], p1[1] - p0[1])
        e2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1 = math.sqrt(e1[0] * e1[0] + e1[1] * e1[1]) or 1.0
        l2 = math.sqrt(e2[0] * e2[0] + e2[1] * e2[1]) or 1.0
        n1 = (e1[1] / l1, -e1[0] / l1)
        n2 = (e2[1] / l2, -e2[0] / l2)
        m = (n1[0] + n2[0], n1[1] + n2[1])
        ml = math.sqrt(m[0] * m[0] + m[1] * m[1])
        if ml < 1e-9:
            m = n1
            scale = 1.0
        else:
            m = (m[0] / ml, m[1] / ml)
            scale = min(1.0 / max(m[0] * n1[0] + m[1] * n1[1], 1e-3), 2.2)
        out.append((p1[0] - m[0] * d * scale, p1[1] - m[1] * d * scale))
    return out


def extrude(poly, depth, bevel=0.0, steps=2):
    # Extrude a 2D polygon (XY) along Z, centred on z=0, with a rounded bevel.
    # Front cap faces -Z (towards the viewer of a pet).
    if poly_area(poly) < 0:
        poly = poly[::-1]
    half = depth * 0.5
    bevel = min(bevel, half * 0.95)
    profile = []  # (inset, z) from front to back
    if bevel > 0.0:
        for k in range(steps + 1):
            a = (PI / 2.0) * k / float(steps)
            profile.append((bevel * (1.0 - math.sin(a)), -half + bevel * (1.0 - math.cos(a))))
        for k in range(steps, -1, -1):
            a = (PI / 2.0) * k / float(steps)
            profile.append((bevel * (1.0 - math.sin(a)), half - bevel * (1.0 - math.cos(a))))
    else:
        profile = [(0.0, -half), (0.0, half)]
    verts = []
    rings = []
    for (ins, z) in profile:
        shape = inset_poly(poly, ins) if ins > 1e-9 else poly
        start = len(verts)
        for p in shape:
            verts.append((p[0], p[1], z))
        rings.append(list(range(start, start + len(shape))))
    tris = []
    n = len(poly)
    for j in range(len(rings) - 1):
        a = rings[j]
        b = rings[j + 1]
        for k in range(n):
            k1 = (k + 1) % n
            tris.append((a[k], a[k1], b[k1]))
            tris.append((a[k], b[k1], b[k]))
    cap = triangulate(poly)
    front = rings[0]
    back = rings[-1]
    for (a, b, c) in cap:
        tris.append((front[a], front[c], front[b]))
        tris.append((back[a], back[b], back[c]))
    return {"verts": verts, "tris": tris}


def star_poly(points, r_out, r_in, rotation=0.0):
    out = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = PI / 2.0 + rotation + PI * i / float(points)
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def bolt_poly(size):
    pts = [(0.30, 0.50), (-0.20, 0.02), (0.02, 0.02), (-0.18, -0.50), (0.26, 0.04), (0.04, 0.04)]
    return [(p[0] * size, p[1] * size) for p in pts]


def crescent_poly(r, thickness, seg=18):
    # moon crescent: outer arc + inner arc (opening to the right)
    pts = []
    for i in range(seg + 1):
        a = PI / 2.0 + PI * i / float(seg)
        pts.append((r * math.cos(a) * 0.95, r * math.sin(a)))
    inner_c = r * thickness
    for i in range(seg - 1, 0, -1):
        a = PI / 2.0 + PI * i / float(seg)
        x = r * math.cos(a) * 0.95
        pts.append((x * (1.0 - thickness) + inner_c * 0.4, r * math.sin(a) * 0.82))
    return pts


def heart_poly(size, seg=24):
    pts = []
    for i in range(seg):
        t = TAU * i / float(seg)
        x = 16.0 * math.sin(t) ** 3
        y = 13.0 * math.cos(t) - 5.0 * math.cos(2 * t) - 2.0 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 17.0 * size, y / 17.0 * size))
    return pts


def blob_poly(points, seg=12):
    # closed smooth outline through control points (catmull-rom in 2D)
    pts3 = [(p[0], p[1], 0.0) for p in points]
    loop = pts3 + pts3[:3]
    out = []
    for i in range(1, len(points) + 1):
        p0 = loop[i - 1]
        p1 = loop[i]
        p2 = loop[i + 1]
        p3 = loop[i + 2]
        for j in range(seg):
            t = j / float(seg)
            t2 = t * t
            t3 = t2 * t
            out.append(tuple([0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * t + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2
                                     + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3) for k in range(2)]))
    return out


def leaf(length, width, thickness, sides=8, rings=8, tip=0.75, base=0.45, bend=0.0, up=None):
    # Flattened leaf / feather / petal along +X from the origin, width in the XY plane,
    # thickness along Z; bend > 0 curls the tip towards +Y.
    path = []
    radii = []
    for i in range(rings + 1):
        t = i / float(rings)
        path.append((length * t, bend * length * t * t, 0.0))
        w = math.sin(PI * (t ** base)) if t < 1.0 else 0.0
        w = spow(max(w, 0.0), tip)
        radii.append((width * w, thickness * w))
    radii[0] = 0.0
    radii[-1] = 0.0
    return tube(path, radii, sides, "none", "none", (0.0, 1.0, 0.0) if up is None else up)


# =============================================================================
# Pets
# =============================================================================

# ----------------------------------------------------------------------------- colours + roles

HEX_DIGITS = "0123456789ABCDEF"
EYE_DARK = (28, 26, 38)
SHINE_WHITE = (255, 255, 255)
BLUSH_PINK = (255, 140, 170)
MOUTH_INK = (62, 30, 46)
GOLD = (255, 210, 60)
GEM_RED = (255, 60, 110)
WHITE = (255, 255, 255)
TONGUE = (255, 120, 150)
SPINE = (255, 245, 210)
STALK = (75, 79, 94)
FLAME_OUT = (255, 140, 40)
FLAME_IN = (255, 225, 90)
BOLT_YELLOW = (255, 225, 74)
BIRD_FEET = (255, 160, 60)
FLOWER_CENTRE = (255, 225, 80)


def rgb_hex(c):
    out = ""
    for v in c:
        v = int(clamp(int(v + 0.5), 0, 255))
        out += HEX_DIGITS[v // 16] + HEX_DIGITS[v % 16]
    return out


def hex_rgb(s):
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def fixed_role(c):
    return "Color_" + rgb_hex(c)


def neon_role(c):
    return "Neon_" + rgb_hex(c)


def ice_role(c):
    return "Ice_" + rgb_hex(c)


def role_base(name):
    # "Accent@WingL" -> ("Accent", "WingL"); "Body" -> ("Body", None)
    at = name.find("@")
    if at < 0:
        return (name, None)
    return (name[:at], name[at + 1:])


def role_color(name, look):
    # Preview colouring that matches the game: -> {"rgb", "material", "transparency", "visible", "tint"}
    base = role_base(name)[0]
    out = {"rgb": (200, 200, 200), "material": "SmoothPlastic", "transparency": 0.0, "visible": True, "tint": None}
    if base == "Root" or base == "Pivot":
        out["visible"] = False
        out["transparency"] = 1.0
    elif base == "Body":
        out["rgb"] = look["Color"]
        out["tint"] = "Body"
    elif base == "Accent":
        out["rgb"] = look["Accent"]
        out["tint"] = "Accent"
    elif base == "Eye":
        if look.get("EyeColor"):
            out["rgb"] = look["EyeColor"]
            out["material"] = "Neon"
        else:
            out["rgb"] = EYE_DARK
    elif base == "Shine":
        out["rgb"] = SHINE_WHITE
        out["material"] = "Neon"
    elif base == "Blush":
        out["rgb"] = BLUSH_PINK
        out["transparency"] = 0.35
    elif base == "Mouth":
        out["rgb"] = MOUTH_INK
    elif base.startswith("Color_"):
        out["rgb"] = hex_rgb(base[6:])
    elif base.startswith("Neon_"):
        out["rgb"] = hex_rgb(base[5:])
        out["material"] = "Neon"
    elif base.startswith("Ice_"):
        out["rgb"] = hex_rgb(base[4:])
        out["material"] = "Ice"
    return out


# ----------------------------------------------------------------------------- pet table
# Mirrors Pets.Pets[*].Look in src/shared/Config/Pets.luau (build_pets.py checks it).

def _pet(name, rarity, body, color, accent, features, effect, eye):
    return {"Name": name, "Rarity": rarity, "Body": body, "Color": color, "Accent": accent,
            "Features": list(features), "Effect": effect, "EyeColor": eye}


PETS = {
    "Puffling": _pet("Puffling", "Common", "Cloud", (250, 252, 255), (180, 215, 255), [], None, None),
    "Droplet": _pet("Droplet", "Uncommon", "Drop", (90, 170, 255), (190, 230, 255), [], None, None),
    "Sunny": _pet("Sunny", "Rare", "Round", (255, 215, 60), (255, 150, 40), ["Rays"], "Glow", None),
    "Prism": _pet("Prism", "Epic", "Cloud", (255, 185, 225), (130, 220, 255), ["Halo"], "Rainbow", None),
    "BreezeKing": _pet("Breeze King", "Legendary", "Cloud", (255, 255, 255), (255, 205, 60), ["Crown", "Wings"], "Sparkle", None),
    "Static": _pet("Static", "Common", "Round", (150, 155, 172), (255, 230, 80), ["Antenna"], None, None),
    "Zappy": _pet("Zappy", "Uncommon", "Bean", (255, 225, 70), (255, 255, 210), ["BunnyEars", "Bolt"], "Zap", None),
    "VoltBat": _pet("Volt Bat", "Rare", "Round", (92, 62, 142), (255, 220, 70), ["Wings", "Ears"], "Zap", None),
    "ThunderPup": _pet("Thunder Pup", "Epic", "Round", (82, 122, 205), (255, 230, 90), ["Ears", "Tail", "Bolt"], "Zap", None),
    "StormLord": _pet("Storm Lord", "Legendary", "Cloud", (62, 62, 88), (255, 225, 60), ["Horns", "Crown"], "Zap", (255, 235, 90)),
    "Sandy": _pet("Sandy", "Common", "Round", (232, 202, 142), (200, 160, 100), [], None, None),
    "CactusCub": _pet("Cactus Cub", "Uncommon", "Bean", (92, 172, 82), (255, 120, 170), ["Spikes", "Flower"], None, None),
    "DustBunny": _pet("Dust Bunny", "Rare", "Round", (215, 186, 136), (255, 240, 212), ["BunnyEars", "Tail"], "Smoke", None),
    "Scarab": _pet("Scarab", "Epic", "Bean", (40, 170, 160), (255, 200, 60), ["Horns", "Wings"], "Sparkle", None),
    "MirageDjinn": _pet("Mirage Djinn", "Legendary", "Drop", (80, 222, 255), (255, 205, 60), ["Crown", "Halo"], "Glow", None),
    "Snowball": _pet("Snowball", "Common", "Round", (245, 250, 255), (150, 200, 255), [], None, None),
    "Icicle": _pet("Icicle", "Uncommon", "Crystal", (170, 225, 255), (230, 250, 255), [], "Snow", None),
    "Frostbite": _pet("Frostbite", "Rare", "Bean", (42, 46, 62), (255, 150, 40), ["Beak", "Belly"], "Snow", None),
    "AuroraFox": _pet("Aurora Fox", "Epic", "Round", (240, 245, 255), (110, 255, 190), ["Ears", "Tail"], "Glow", None),
    "YetiKing": _pet("Yeti King", "Legendary", "Round", (235, 240, 250), (120, 190, 255), ["Horns", "Crown"], "Snow", None),
    "Ember": _pet("Ember", "Common", "Round", (255, 120, 40), (255, 210, 80), ["Flame"], None, None),
    "Coal": _pet("Coal", "Uncommon", "Cube", (52, 46, 46), (255, 110, 30), ["Cracks"], None, None),
    "LavaPup": _pet("Lava Pup", "Rare", "Round", (230, 80, 30), (255, 200, 60), ["Ears", "Tail"], "Fire", None),
    "PhoenixChick": _pet("Phoenix Chick", "Epic", "Round", (255, 90, 50), (255, 210, 70), ["Wings", "Beak", "Flame"], "Fire", None),
    "InfernoDrake": _pet("Inferno Drake", "Legendary", "Bean", (150, 32, 32), (255, 150, 40), ["Horns", "Wings", "Tail"], "Fire", (255, 200, 60)),
    "Stardust": _pet("Stardust", "Common", "Round", (150, 120, 255), (255, 240, 150), [], "Sparkle", None),
    "Comet": _pet("Comet", "Uncommon", "Drop", (90, 150, 255), (200, 240, 255), [], "Sparkle", None),
    "Nebula": _pet("Nebula", "Rare", "Cloud", (220, 120, 255), (120, 200, 255), ["Halo"], "Sparkle", None),
    "Moonbeam": _pet("Moonbeam", "Epic", "Round", (212, 216, 240), (255, 250, 200), ["Ears", "Halo"], "Glow", None),
    "GalaxyGuardian": _pet("Galaxy Guardian", "Legendary", "Bean", (38, 22, 74), (255, 120, 240), ["Crown", "Wings", "Halo"], "Sparkle", (120, 230, 255)),
    "TempestTitan": _pet("Tempest Titan", "Exclusive", "Cloud", (210, 235, 255), (120, 200, 255), ["Horns", "Wings", "Crown"], "Sparkle", None),
    "VoltWyrm": _pet("Volt Wyrm", "Exclusive", "Bean", (92, 72, 162), (255, 230, 80), ["Horns", "Wings", "Bolt"], "Zap", (255, 240, 120)),
    "FrostColossus": _pet("Frost Colossus", "Exclusive", "Cube", (190, 230, 255), (255, 255, 255), ["Horns", "Crown"], "Snow", (90, 200, 255)),
    "CycloneDrake": _pet("Cyclone Drake", "Exclusive", "Bean", (255, 110, 40), (255, 220, 90), ["Horns", "Wings", "Tail"], "Fire", (255, 245, 160)),
    "MaelstromSpirit": _pet("Maelstrom Spirit", "Exclusive", "Cloud", (122, 62, 222), (255, 150, 240), ["Halo", "Wings", "Crown"], "Rainbow", (255, 200, 250)),
    "RainbowRoc": _pet("Rainbow Roc", "Exclusive", "Round", (255, 248, 252), (255, 120, 200), ["Wings", "Beak", "Crown", "Tail"], "Rainbow", (120, 220, 255)),
    "Sunbeam": _pet("Sunbeam", "Epic", "Round", (255, 235, 120), (255, 255, 255), ["Rays", "Halo"], "Glow", None),
}

# Pet index order (same as Pets.IndexOrder)
PET_IDS = [
    "Puffling", "Droplet", "Sunny", "Prism", "BreezeKing",
    "Static", "Zappy", "VoltBat", "ThunderPup", "StormLord",
    "Sandy", "CactusCub", "DustBunny", "Scarab", "MirageDjinn",
    "Snowball", "Icicle", "Frostbite", "AuroraFox", "YetiKing",
    "Ember", "Coal", "LavaPup", "PhoenixChick", "InfernoDrake",
    "Stardust", "Comet", "Nebula", "Moonbeam", "GalaxyGuardian",
    "Sunbeam", "TempestTitan", "VoltWyrm", "FrostColossus", "CycloneDrake", "MaelstromSpirit", "RainbowRoc",
]

# Per-pet design choices on top of the Look (styles of features + small signature details)
DESIGN = {
    "Puffling": {"mouth": "smile", "underpuffs": True},
    "Droplet": {"mouth": "smile", "drop_shine": True},
    "Sunny": {"mouth": "open"},
    "Prism": {"mouth": "smile", "underpuffs": True},
    "BreezeKing": {"mouth": "smile", "wings": "feather"},
    "Static": {"mouth": "cat", "bolt_cheeks": True, "no_blush": True},
    "Zappy": {"mouth": "cat", "bunny": "upright", "bolt": "ears"},
    "VoltBat": {"mouth": "fang", "ears": "bat", "wings": "bat"},
    "ThunderPup": {"mouth": "open", "ears": "pup", "tail": "pup", "bolt": "forehead", "feet": True},
    "StormLord": {"mouth": "smile", "horns": "devil", "cloud": "storm", "horn_scale": 1.3},
    "Sandy": {"mouth": "smile", "ripples": True, "freckles": True},
    "CactusCub": {"mouth": "smile", "ribs": 9, "arms": True},
    "DustBunny": {"mouth": "cat", "bunny": "flop", "tail": "puff", "feet": True},
    "Scarab": {"mouth": "smile", "horns": "beetle", "wings": "insect", "back_stripe": True},
    "MirageDjinn": {"mouth": "smile", "drop": "djinn"},
    "Snowball": {"mouth": "open", "cowlick": True},
    "Icicle": {"mouth": "smile", "shards": True},
    "Frostbite": {"mouth": None, "feet": "bird", "eye_rims": True, "beak": "penguin"},
    "AuroraFox": {"mouth": "cat", "ears": "fox", "tail": "fox", "cheek_tufts": True, "feet": True},
    "YetiKing": {"mouth": "open", "horns": "ox", "face_mask": True, "cheek_tufts": True},
    "Ember": {"mouth": "open"},
    "Coal": {"mouth": "open", "eye_rims": True},
    "LavaPup": {"mouth": "open", "ears": "pup", "tail": "lava", "feet": True},
    "PhoenixChick": {"mouth": None, "wings": "feather", "feet": "bird", "beak": "chick"},
    "InfernoDrake": {"mouth": "smile", "horns": "dragon", "wings": "bat", "tail": "dragon", "belly_accent": True, "belly_plates": True, "belly_pitch": -36.0, "belly_size": 0.9},
    "Stardust": {"mouth": "smile", "star_mark": True},
    "Comet": {"mouth": "smile", "drop": "comet", "streaks": True},
    "Nebula": {"mouth": "smile", "underpuffs": True},
    "Moonbeam": {"mouth": "cat", "ears": "cat", "moon_mark": True},
    "GalaxyGuardian": {"mouth": "smile", "wings": "feather", "star_freckles": True},
    "TempestTitan": {"mouth": "open", "horns": "devil", "wings": "feather"},
    "VoltWyrm": {"mouth": "fang", "horns": "dragon", "wings": "bat", "bolt": "top", "belly_accent": True, "belly_plates": True, "belly_pitch": -36.0, "belly_size": 0.9},
    "FrostColossus": {"mouth": "open", "horns": "ice", "shards": True},
    "CycloneDrake": {"mouth": "smile", "horns": "dragon", "wings": "bat", "tail": "dragon", "belly_accent": True, "belly_plates": True, "belly_pitch": -36.0, "belly_size": 0.9},
    "MaelstromSpirit": {"mouth": "smile", "wings": "feather"},
    "RainbowRoc": {"mouth": None, "wings": "feather", "tail": "bird", "feet": "bird", "beak": "chick"},
    "Sunbeam": {"mouth": "open"},
}


def is_dark(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0 < 0.3


# ----------------------------------------------------------------------------- bodies
# Every body is a star-shaped surface S(d): unit direction from the origin -> surface point.

def surf_normal(S, d):
    t1 = perpendicular(d)
    t2 = vcross(d, t1)
    e = 0.002
    p1 = S(vnorm(vmad(d, t1, e)))
    p2 = S(vnorm(vmad(d, t1, -e)))
    p3 = S(vnorm(vmad(d, t2, e)))
    p4 = S(vnorm(vmad(d, t2, -e)))
    n = vnorm(vcross(vsub(p1, p2), vsub(p3, p4)))
    if vdot(n, d) < 0:
        n = vmul(n, -1.0)
    return n


def egg_surface(rx, ry, rz, pear=0.0, yoff=0.0, ribs=0, rib=0.0, flat=0.0):
    def S(d):
        k = 1.0 - pear * d[1]
        if ribs > 0:
            yaw = math.atan2(d[0], -d[2])
            k *= 1.0 + rib * math.cos(ribs * yaw) * (1.0 - d[1] * d[1])
        y = d[1] * ry
        if flat > 0.0 and d[1] < 0.0:
            y *= 1.0 - flat * d[1] * d[1]
        return (d[0] * rx * k, y + yoff, d[2] * rz * k)
    return S


CLOUD_PUFFS = [
    ((0.0, 0.0, 0.0), 1.0),
    ((0.9, -0.22, 0.1), 0.7),
    ((-0.9, -0.22, 0.1), 0.7),
    ((0.4, 0.62, 0.2), 0.64),
    ((-0.38, 0.6, 0.26), 0.6),
    ((0.0, 0.5, 0.6), 0.6),
    ((0.6, -0.45, 0.5), 0.58),
    ((-0.6, -0.45, 0.5), 0.58),
]

STORM_PUFFS = [
    ((0.0, 0.0, 0.0), 1.0),
    ((0.95, -0.28, 0.1), 0.68),
    ((-0.95, -0.28, 0.1), 0.68),
    ((0.5, 0.6, 0.18), 0.6),
    ((-0.5, 0.6, 0.18), 0.6),
    ((0.0, 0.78, 0.25), 0.55),
    ((0.0, 0.45, 0.62), 0.6),
    ((0.62, -0.42, 0.52), 0.6),
    ((-0.62, -0.42, 0.52), 0.6),
]


def cloud_surface(puffs, k):
    def S(d):
        ts = []
        for (c, r) in puffs:
            b = d[0] * c[0] + d[1] * c[1] + d[2] * c[2]
            disc = b * b - (c[0] * c[0] + c[1] * c[1] + c[2] * c[2] - r * r)
            if disc >= 0.0:
                t = b + math.sqrt(disc)
                if t > 0.0:
                    ts.append(t)
        m = max(ts)
        s = 0.0
        for t in ts:
            s += math.exp(k * (t - m))
        t = m + math.log(s) / k
        return (d[0] * t, d[1] * t, d[2] * t)
    return S


def drop_surface(tip, sharp, curl_z, curl_x, start=0.35):
    def polar(d):
        s = d[1]
        rho = 1.0 + tip * (s ** sharp) if s > 0.0 else 1.0
        return (d[0] * rho, d[1] * rho * (0.93 if s < 0.0 else 1.0), d[2] * rho)

    def warp(p):
        h = max(0.0, p[1] - start)
        return (p[0] + curl_x * h * h, p[1], p[2] + curl_z * h * h)

    def S(d):
        return warp(polar(d))
    return (S, polar, warp)


def cube_surface(half, e):
    def S(d):
        s = abs(d[0]) ** e + abs(d[1]) ** e + abs(d[2]) ** e
        r = half / (s ** (1.0 / e))
        return (d[0] * r, d[1] * r, d[2] * r)
    return S


def polyhedron_surface(m):
    planes = []
    v = m["verts"]
    for t in m["tris"]:
        n = vnorm(vcross(vsub(v[t[1]], v[t[0]]), vsub(v[t[2]], v[t[0]])))
        planes.append((n, vdot(n, v[t[0]])))

    def S(d):
        best = 1e9
        for (n, h) in planes:
            c = vdot(n, d)
            if c > 1e-6:
                r = h / c
                if r < best:
                    best = r
        return (d[0] * best, d[1] * best, d[2] * best)
    return S


def gem_surface(radius, bottom, low, high, top, sides=6, sharp=14.0):
    # Soft polyhedron: hexagonal prism (a flat facet faces the front) with pyramid ends.
    # Radial distance = soft minimum over the facet planes -> flat facets, rounded edges.
    planes = []
    for k in range(sides):
        yaw = TAU * k / float(sides)
        sx = math.sin(yaw)
        sz = -math.cos(yaw)
        planes.append(((sx, 0.0, sz), radius))
        length = math.sqrt((top - high) ** 2 + radius * radius)
        n = (sx * (top - high) / length, radius / length, sz * (top - high) / length)
        planes.append((n, radius * top / length))
        length = math.sqrt((low - bottom) ** 2 + radius * radius)
        n = (sx * (low - bottom) / length, -radius / length, sz * (low - bottom) / length)
        planes.append((n, -radius * bottom / length))

    def S(d):
        total = 0.0
        for (n, h) in planes:
            c = (n[0] * d[0] + n[1] * d[1] + n[2] * d[2]) / h
            if c > 0.0:
                total += c ** sharp
        r = 1.0 / (total ** (1.0 / sharp))
        return (d[0] * r, d[1] * r, d[2] * r)
    return S


def gem(radius, bottom, low, high, top, n=6, sides=6, sharp=20.0):
    return radial_mesh(gem_surface(radius, bottom, low, high, top, sides, sharp), n)


def crystal(radius, bottom, low, high, top, sides=6, taper=0.9):
    profile = [(0.0, bottom), (radius, low), (radius * taper, high), (0.0, top)]
    return unweld_mesh(lathe(profile, sides, "none", "none"))


FACE_DEFAULTS = {
    "pitch": -4.0, "eye_u": 0.35, "eye_v": 0.08, "eye_rx": 0.152, "eye_ry": 0.192, "mouth_v": -0.15,
    "blush_u": 0.57, "blush_v": -0.1, "blush": True, "mouth_w": 1.0,
}

FACE_BY_BODY = {
    "Round": {},
    "Cloud": {"pitch": -9.0, "eye_u": 0.34, "blush_u": 0.56},
    "Drop": {"pitch": -15.0, "eye_u": 0.32, "eye_v": 0.05, "blush_u": 0.54},
    "Bean": {"pitch": 2.0, "eye_u": 0.3, "eye_rx": 0.138, "eye_ry": 0.178, "blush_u": 0.52},
    "Cube": {"pitch": 0.0, "eye_u": 0.31, "eye_v": 0.1, "blush": False, "blush_u": 0.55},
    "Crystal": {"pitch": 3.0, "eye_u": 0.23, "eye_v": 0.06, "eye_rx": 0.115, "eye_ry": 0.15, "mouth_v": -0.14,
                "blush": False, "mouth_w": 0.8},
}


def make_body(ctx):
    look = ctx["look"]
    design = ctx["design"]
    kind = look["Body"]
    q = ctx["q"]
    body = {"kind": kind, "extra": []}
    if kind == "Cloud":
        puffs = STORM_PUFFS if design.get("cloud") == "storm" else CLOUD_PUFFS
        S = cloud_surface(puffs, 11.0)
        mesh = radial_mesh(S, lod(ctx, 14))
    elif kind == "Drop":
        style = design.get("drop")
        if style == "djinn":
            S, polar, warp = drop_surface(0.95, 9.0, 0.22, 0.0, 0.5)
        elif style == "comet":
            S, polar, warp = drop_surface(1.0, 7.0, 0.95, 0.0, 0.15)
        else:
            S, polar, warp = drop_surface(0.85, 10.0, 0.16, 0.0, 0.4)
        dense = []
        for i in range(401):
            ph = -PI / 2.0 + PI * i / 400.0
            p = polar((math.cos(ph), math.sin(ph), 0.0))
            dense.append((p[0], p[1], 0.0))
        rings = lod(ctx, 30)
        prof = resample_polyline(dense, rings)
        profile = [(max(0.0, p[0]), p[1]) for p in prof]
        profile[0] = (0.0, profile[0][1])
        profile[-1] = (0.0, profile[-1][1])
        mesh = map_mesh(lathe(profile, lod(ctx, 32)), warp)
        body["profile"] = [(p[0], p[1]) for p in dense]
        body["warp"] = warp
    elif kind == "Bean":
        ribs = design.get("ribs", 0)
        S = egg_surface(0.92, 1.17, 0.88, 0.1, 0.08, ribs, 0.035 if ribs else 0.0, 0.12)
        mesh = radial_mesh(S, lod(ctx, 12))
    elif kind == "Cube":
        S = cube_surface(0.98, 5.0)
        mesh = radial_mesh(S, lod(ctx, 12))
    elif kind == "Crystal":
        S = gem_surface(0.84, -1.02, -0.34, 0.5, 1.75, 6, 30.0)
        mesh = unweld_mesh(radial_mesh(S, lod(ctx, 16)))
    else:
        S = egg_surface(1.04, 0.97, 1.0, 0.06, 0.0, 0, 0.0, 0.1)
        mesh = radial_mesh(S, lod(ctx, 12))
    body["S"] = S
    body["mesh"] = mesh
    face = dict(FACE_DEFAULTS)
    for k in FACE_BY_BODY.get(kind, {}):
        face[k] = FACE_BY_BODY[kind][k]
    body["face"] = face
    return body


def surface_at(body, yaw, pitch):
    d = ydir(yaw, pitch)
    return (body["S"](d), surf_normal(body["S"], d))


def height_at(ctx, x, z, radius=0.12):
    best = None
    for p in ctx["body"]["mesh"]["verts"]:
        dx = p[0] - x
        dz = p[2] - z
        if dx * dx + dz * dz < radius * radius:
            if best is None or p[1] > best:
                best = p[1]
    if best is None:
        best = ctx["body"]["S"](UP)[1]
    return best


def body_top(ctx):
    return ctx["body"]["S"](UP)[1]


# ----------------------------------------------------------------------------- decals (painted-on bumps)

def body_patch(body, yaw, pitch):
    # (u, v) in studs on the tangent plane at a body point -> (surface point, normal)
    S = body["S"]
    d0 = ydir(yaw, pitch)
    p0 = S(d0)
    n0 = surf_normal(S, d0)
    tu = vcross(n0, UP)
    tu = (1.0, 0.0, 0.0) if vlen(tu) < 1e-6 else vnorm(tu)
    tv = vcross(tu, n0)

    def fn(u, v):
        q = (p0[0] + tu[0] * u + tv[0] * v, p0[1] + tu[1] * u + tv[1] * v, p0[2] + tu[2] * u + tv[2] * v)
        d = vnorm(q)
        return (S(d), surf_normal(S, d))
    return fn


def dome_patch(patch, cu, cv, rx, ry, height, lift, dome=0.5):
    # surface of a decal dome (for stacking decals, e.g. eye shines)
    def raw(u, v):
        rho2 = (u / rx) ** 2 + (v / ry) ** 2
        h = lift + height * (max(0.0, 1.0 - rho2) ** dome)
        s, n = patch(cu + u, cv + v)
        return (vmad(s, n, h), n)

    def fn(u, v):
        p, n = raw(u, v)
        e = 0.004
        a = raw(u + e, v)[0]
        b = raw(u - e, v)[0]
        c = raw(u, v + e)[0]
        d = raw(u, v - e)[0]
        m = vnorm(vcross(vsub(a, b), vsub(c, d)))
        if vdot(m, n) < 0:
            m = vmul(m, -1.0)
        return (p, m)
    return fn


def decal(patch, cu, cv, rx, ry, height=0.03, lift=0.01, rings=3, seg=16, rot=0.0, skirt=0.03, dome=0.5,
          squash_top=1.0, shape=None):
    # Dome-shaped decal that hugs the surface; its rim tucks under the surface.
    cr = math.cos(rot)
    sr = math.sin(rot)

    def at(lu, lv, h):
        u = cu + lu * cr - lv * sr
        v = cv + lu * sr + lv * cr
        s, n = patch(u, v)
        return vmad(s, n, h)

    def local(a, rho):
        lu = math.cos(a) * rx * rho
        lv = math.sin(a) * ry * rho
        if shape is not None:
            f = shape(a)
            lu *= f
            lv *= f
        if lv > 0.0:
            lv *= squash_top
        return (lu, lv)

    sections = [("pole", at(0.0, 0.0, lift + height))]
    for i in range(1, rings + 1):
        rho = i / float(rings)
        h = lift + height * (max(0.0, 1.0 - rho * rho) ** dome)
        ring = []
        for k in range(seg):
            lu, lv = local(TAU * k / float(seg), rho)
            ring.append(at(lu, lv, h))
        sections.append(("ring", ring))
    ring = []
    grow = 1.0 + 0.015 / max(min(rx, ry), 0.01)
    for k in range(seg):
        lu, lv = local(TAU * k / float(seg), grow)
        ring.append(at(lu, lv, -skirt))
    sections.append(("ring", ring))
    return stitch_sections(sections)


def surface_path(patch, uvs, lift):
    out = []
    for (u, v) in uvs:
        s, n = patch(u, v)
        out.append(vmad(s, n, lift))
    return out


# ----------------------------------------------------------------------------- context helpers

def lod(ctx, n, lo=3):
    return max(lo, int(n * ctx["q"] + 0.5))


def add(ctx, role, mesh):
    parts = ctx["parts"]
    if role not in parts:
        parts[role] = []
        ctx["order"].append(role)
    parts[role].append(mesh)


def add_pivot(ctx, anim, point):
    ctx["pivots"][anim] = point


def pair(ctx, role_fn, mesh_fn):
    # build a +X-side mesh, mirror it for the -X side; role_fn(side) -> role name
    for side in (-1, 1):
        m = mesh_fn(side)
        add(ctx, role_fn(side), m)


# ----------------------------------------------------------------------------- face

def build_face(ctx):
    body = ctx["body"]
    look = ctx["look"]
    design = ctx["design"]
    f = body["face"]
    patch = body_patch(body, 0.0, f["pitch"])
    ctx["face_patch"] = patch
    erx = f["eye_rx"] * design.get("eye_scale", 1.0)
    ery = f["eye_ry"] * design.get("eye_scale", 1.0)
    ev = f["eye_v"]
    seg = lod(ctx, 20, 10)
    rims = design.get("eye_rims") or (is_dark(look["Color"]) and not look.get("EyeColor") and look["Body"] != "Bean")
    if design.get("face_mask"):
        add(ctx, "Accent", decal(patch, 0.0, -0.02, f["eye_u"] + erx + 0.13, ery + 0.2, 0.012, 0.004, 3, lod(ctx, 24, 12),
                                 skirt=0.03, dome=0.4, shape=mask_shape))
    for side in (-1, 1):
        cu = side * f["eye_u"]
        lift = 0.012
        if design.get("face_mask"):
            lift = 0.03
        if rims:
            add(ctx, "Color_FFFFFF", decal(patch, cu, ev, erx + 0.035, ery + 0.035, 0.004, lift - 0.004, 2, seg, skirt=0.03))
        add(ctx, "Eye", decal(patch, cu, ev, erx, ery, 0.05, lift, lod(ctx, 4, 2), seg, rot=side * rad(-4.0), skirt=0.03))
        eye_surface = dome_patch(patch, cu, ev, erx, ery, 0.05, lift)
        add(ctx, "Shine", decal(eye_surface, erx * 0.3, ery * 0.36, erx * 0.36, erx * 0.36, 0.012, 0.003, 2,
                                lod(ctx, 12, 8), skirt=0.01))
        add(ctx, "Shine", decal(eye_surface, -erx * 0.34, -ery * 0.42, erx * 0.17, erx * 0.17, 0.008, 0.003, 1,
                                lod(ctx, 8, 6), skirt=0.01))
        if f["blush"] and not design.get("no_blush"):
            add(ctx, "Blush", decal(patch, side * f["blush_u"], f["blush_v"], 0.12, 0.072, 0.008, 0.006, 2,
                                    lod(ctx, 14, 8), rot=side * rad(6.0), skirt=0.02))
    mouth = design.get("mouth", "smile")
    mv = f["mouth_v"]
    w = f["mouth_w"]
    if design.get("face_mask"):
        mv -= 0.02
    mlift = 0.012 + (0.03 if design.get("face_mask") else 0.0)
    radius = 0.021
    if mouth == "smile":
        uvs = [(u * 0.075 * w, mv - 0.042 * (1.0 - u * u)) for u in [lerp(-1.0, 1.0, i / 10.0) for i in range(11)]]
        add(ctx, "Mouth", tube(surface_path(patch, uvs, mlift), [radius] * len(uvs), 6, "round", "round", None, 2))
    elif mouth == "cat" or mouth == "fang":
        uvs = []
        for i in range(17):
            u = lerp(-1.0, 1.0, i / 16.0)
            uvs.append((u * 0.1 * w, mv + 0.012 - 0.036 * abs(math.sin(PI * u))))
        add(ctx, "Mouth", tube(surface_path(patch, uvs, mlift), [radius * 0.9] * len(uvs), 6, "round", "round", None, 2))
        if mouth == "fang":
            for side in (-1, 1):
                s, n = patch(side * 0.05 * w, mv - 0.03)
                base = vmad(s, n, -0.01)
                fang = cone(0.026, 0.0, 0.075, 6, 0.008)
                fang = xform(fang, [xf_rot_x(PI), xf_frame(base, vnorm(vadd(n, (0.0, 0.25, 0.0))), (0.0, 0.0, 1.0))])
                fang = transform_mesh(cone(0.024, 0.0, 0.07, 6, 0.008),
                                      xf_mul(xf_frame(vmad(base, n, 0.012), vnorm(vadd((0.0, -1.0, 0.0), vmul(n, 0.35))),
                                                      n), xf_identity()))
                add(ctx, fixed_role(WHITE), fang)
    elif mouth == "open":
        def dshape(a):
            return 1.0
        add(ctx, "Mouth", decal(patch, 0.0, mv + 0.012, 0.085 * w, 0.075, 0.006, mlift - 0.004, 3, lod(ctx, 18, 10),
                                skirt=0.02, squash_top=0.18, shape=dshape))
        mouth_surface = dome_patch(patch, 0.0, mv + 0.012, 0.085 * w, 0.075, 0.006, mlift - 0.004)
        add(ctx, fixed_role(TONGUE), decal(mouth_surface, 0.0, -0.035, 0.05 * w, 0.028, 0.004, 0.002, 2,
                                           lod(ctx, 12, 8), skirt=0.006))


def mask_shape(a):
    # yeti face mask: wide at the eyes, rounded chin
    s = math.sin(a)
    return 1.0 - 0.18 * max(0.0, -s) * abs(math.cos(a)) + 0.05 * s


# ----------------------------------------------------------------------------- features

EAR_STYLES = {
    # mid / tip: curve control points in ear lengths (x = outwards, y = up, z = back)
    "cat": {"yaw": 33.0, "pitch": 50.0, "len": 0.56, "wid": 0.27, "thick": 0.12, "tilt": 16.0, "lean": 6.0,
            "mid": (0.02, 0.72, 0.0), "tip": (0.05, 1.0, 0.0), "turn": 12.0},
    "fox": {"yaw": 33.0, "pitch": 47.0, "len": 0.74, "wid": 0.29, "thick": 0.12, "tilt": 14.0, "lean": 4.0,
            "mid": (0.02, 0.72, 0.01), "tip": (0.06, 1.0, 0.02), "turn": 10.0},
    "bat": {"yaw": 38.0, "pitch": 42.0, "len": 0.8, "wid": 0.34, "thick": 0.11, "tilt": 30.0, "lean": 4.0,
            "mid": (0.03, 0.72, 0.0), "tip": (0.1, 1.0, 0.0), "turn": 18.0},
    "pup": {"yaw": 46.0, "pitch": 40.0, "len": 0.6, "wid": 0.3, "thick": 0.11, "tilt": 34.0, "lean": 0.0,
            "mid": (0.16, 0.95, -0.1), "tip": (0.5, 0.6, -0.34), "turn": 16.0},
}


def ear_meshes(ctx, L, W, T, mid, tip, side):
    ctrl = [(0.0, -0.14, 0.0), (0.0, 0.32 * L, 0.0), vmul(mid, L), vmul(tip, L)]

    def width(t):
        return W * (max(0.0, 1.0 - t ** 1.8) ** 0.7)

    def thick(t):
        return T * (max(0.0, 1.0 - t ** 2.2) ** 0.6) * (1.0 - 0.35 * t)

    def rf(t):
        return (width(t), thick(t))
    n = lod(ctx, 9, 5)
    outer = sweep(ctrl, n, rf, lod(ctx, 9, 6), (1.0, 0.0, 0.0), "round", "round", 0.25)
    pts = bezier_points(ctrl, 64)
    path = []
    radii = []
    m = lod(ctx, 7, 4)
    for i in range(m + 1):
        tau = i / float(m)
        t = lerp(0.14, 0.86, tau)
        p = pts[int(t * 64)]
        env = math.sin(PI * (0.5 + 0.5 * tau)) ** 0.6 if tau < 1.0 else 0.0
        path.append((p[0], p[1], p[2] - thick(t) * 0.62))
        radii.append((width(t) * 0.6 * env, thick(t) * 0.42 * env))
    inner = tube(path, radii, lod(ctx, 8, 6), "round", "none", (1.0, 0.0, 0.0))
    if side < 0:
        outer = mirror_x(outer)
        inner = mirror_x(inner)
    return (outer, inner)


def feat_ears(ctx):
    st = EAR_STYLES[ctx["design"].get("ears", "cat")]
    body = ctx["body"]
    scale = ctx["design"].get("ear_scale", 1.0)
    for side in (-1, 1):
        p, n = surface_at(body, side * st["yaw"], st["pitch"])
        outer, inner = ear_meshes(ctx, st["len"] * scale, st["wid"] * scale, st["thick"] * scale, st["mid"], st["tip"], side)
        tilt = rad(st["tilt"])
        lean = rad(st["lean"])
        y_dir = vnorm((side * math.sin(tilt), math.cos(tilt), math.sin(lean)))
        xf = xf_chain([xf_rot_y(side * rad(st["turn"])), xf_frame(vmad(p, n, -0.06), y_dir, (0.0, 0.0, 1.0))])
        add(ctx, "Body", transform_mesh(outer, xf))
        add(ctx, "Accent", transform_mesh(inner, xf))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), body_top(ctx) + 0.45 * scale)


def feat_bunny_ears(ctx):
    body = ctx["body"]
    style = ctx["design"].get("bunny", "upright")
    L = 1.0
    W = 0.15
    T = 0.08
    for side in (-1, 1):
        flop = style == "flop" and side > 0
        if flop:
            ctrl = [(0.0, -0.12, 0.0), (0.02, 0.42 * L, 0.0), (0.3 * L, 0.78 * L, -0.06), (0.62 * L, 0.6 * L, -0.12)]
        else:
            ctrl = [(0.0, -0.12, 0.0), (0.0, 0.4 * L, 0.0), (0.06 * L, 0.78 * L, 0.06), (0.1 * L, L, 0.14)]

        def width(t):
            return W * (0.72 + 0.5 * math.sin(PI * min(1.0, t * 1.05))) * (max(0.0, 1.0 - t ** 4) ** 0.5)

        def thick(t):
            return T * (1.0 - 0.3 * t) * (max(0.0, 1.0 - t ** 4) ** 0.5)

        def rf(t, width=width, thick=thick):
            return (width(t), thick(t))
        outer = sweep(ctrl, lod(ctx, 12, 7), rf, lod(ctx, 9, 6), (1.0, 0.0, 0.0), "round", "round", 0.2)
        pts = bezier_points(ctrl, 64)
        path = []
        radii = []
        m = lod(ctx, 9, 5)
        for i in range(m + 1):
            tau = i / float(m)
            t = lerp(0.16, 0.9, tau)
            p = pts[int(t * 64)]
            env = math.sin(PI * (0.5 + 0.5 * tau)) ** 0.5 if tau < 1.0 else 0.0
            path.append((p[0], p[1], p[2] - thick(t) * 0.6))
            radii.append((width(t) * 0.55 * env, thick(t) * 0.45 * env))
        inner = tube(path, radii, lod(ctx, 8, 6), "round", "none", (1.0, 0.0, 0.0))
        if side < 0:
            outer = mirror_x(outer)
            inner = mirror_x(inner)
        p, n = surface_at(body, side * 17.0, 66.0)
        tilt = rad(9.0)
        y_dir = vnorm((side * math.sin(tilt), math.cos(tilt), math.sin(rad(6.0))))
        xf = xf_chain([xf_rot_y(side * rad(8.0)), xf_frame(vmad(p, n, -0.05), y_dir, (0.0, 0.0, 1.0))])
        add(ctx, "Body", transform_mesh(outer, xf))
        add(ctx, "Accent", transform_mesh(inner, xf))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), body_top(ctx) + 0.9)


HORN_STYLES = {
    "devil": {"yaw": 40.0, "pitch": 52.0, "r": 0.13, "pts": [(0.0, -0.12, 0.0), (0.1, 0.22, 0.02), (0.1, 0.45, 0.06), (-0.04, 0.6, 0.1)]},
    "dragon": {"yaw": 34.0, "pitch": 50.0, "r": 0.13, "pts": [(0.0, -0.12, 0.0), (0.04, 0.24, 0.05), (0.08, 0.46, 0.22), (0.06, 0.55, 0.5)]},
    "ram": {"yaw": 58.0, "pitch": 40.0, "r": 0.17, "ridges": 6,
            "pts": [(0.0, -0.1, 0.0), (0.06, 0.15, 0.08), (0.24, 0.25, 0.15), (0.4, 0.12, 0.14), (0.42, -0.1, 0.03),
                    (0.3, -0.21, -0.08), (0.18, -0.13, -0.13)]},
    "ox": {"yaw": 56.0, "pitch": 40.0, "r": 0.15, "ridges": 3,
           "pts": [(0.0, -0.1, 0.0), (0.2, 0.04, 0.02), (0.38, 0.18, 0.04), (0.42, 0.42, 0.0)]},
    "ice": {"yaw": 40.0, "pitch": 44.0, "r": 0.17, "facets": 5, "pts": [(0.0, -0.12, 0.0), (0.1, 0.2, 0.04), (0.24, 0.38, 0.08), (0.4, 0.5, 0.1)]},
}


def horn_mesh(ctx, st, scale, side):
    pts = [vmul(p, scale) for p in st["pts"]]
    r0 = st["r"] * scale
    ridges = st.get("ridges", 0)

    def rf(t):
        r = r0 * (max(0.0, 1.0 - t ** 1.5) ** 0.9) * (1.0 - 0.45 * t)
        if ridges:
            r *= 1.0 + 0.08 * (math.cos(t * PI * 2.0 * ridges) ** 2) * (1.0 - t)
        return r
    sides = st.get("facets", lod(ctx, 9, 6))
    n = lod(ctx, 14 if ridges else 10, 6)
    m = sweep(pts, n, rf, sides, (1.0, 0.0, 0.0), "round", "round", 0.15)
    if st.get("facets"):
        m = unweld_mesh(m)
    if side < 0:
        m = mirror_x(m)
    return m


def feat_horns(ctx):
    body = ctx["body"]
    style = ctx["design"].get("horns", "devil")
    scale = ctx["design"].get("horn_scale", 1.0)
    if style == "beetle":
        p, n = surface_at(body, 0.0, 46.0)
        pts = [(0.0, -0.12, 0.0), (0.0, 0.22, -0.1), (0.0, 0.5, -0.12), (0.0, 0.66, 0.02)]

        def rf(t):
            return 0.13 * (max(0.0, 1.0 - t ** 1.6) ** 0.85) * (1.0 - 0.4 * t)
        big = sweep(pts, lod(ctx, 12, 6), rf, lod(ctx, 9, 6), (1.0, 0.0, 0.0), "round", "round", 0.15)
        xf = xf_frame(vmad(p, n, -0.05), vnorm(vadd(n, (0.0, 0.6, 0.0))), (0.0, 0.0, 1.0))
        add(ctx, "Accent", transform_mesh(big, xf))
        for side in (-1, 1):
            p2, n2 = surface_at(body, side * 30.0, 36.0)
            small = sweep([(0.0, -0.08, 0.0), (0.02, 0.1, 0.0), (0.06, 0.2, 0.02), (0.1, 0.27, 0.06)], lod(ctx, 7, 4),
                          horn_fn(0.06, 1.6, 0.85), lod(ctx, 7, 5), (1.0, 0.0, 0.0),
                          "round", "round", 0.15)
            if side < 0:
                small = mirror_x(small)
            add(ctx, "Accent", transform_mesh(small, xf_frame(vmad(p2, n2, -0.03), vnorm(vadd(n2, (0.0, 0.4, 0.0))),
                                                              (0.0, 0.0, 1.0))))
        ctx["head_top"] = max(ctx.get("head_top", 0.0), body_top(ctx) + 0.4)
        return
    st = HORN_STYLES[style]
    yaw = st["yaw"]
    pitch = st["pitch"]
    if ctx["look"]["Body"] == "Cube":
        pitch += 4.0
    for side in (-1, 1):
        p, n = surface_at(body, side * yaw, pitch)
        m = horn_mesh(ctx, st, scale, side)
        y_dir = vnorm(vadd(vmul(n, 0.6), (0.0, 0.7, 0.0)))
        xf = xf_frame(vmad(p, n, -0.05), y_dir, (0.0, 0.0, 1.0))
        add(ctx, "Accent", transform_mesh(m, xf))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), body_top(ctx) + 0.35 * scale)


def crown_mesh(ctx, R, H, spike, points, thick):
    per = 4
    K = points * per
    b = thick * 0.35
    sections = []
    tips = []
    for k in range(K):
        th = PI / 2.0 + TAU * k / float(K)
        ph = points * (th - PI / 2.0) / TAU
        frac = ph - math.floor(ph + 0.5)
        tri = 1.0 - 2.0 * abs(frac)
        top = H + spike * tri
        c = math.cos(th)
        s = -math.sin(th)

        def ro(y):
            return R + 0.07 * y / (H + spike)
        loop = [(ro(0.0) - thick + b, 0.0), (ro(0.0) - b, 0.0), (ro(b), b), (ro(top - b), top - b),
                (ro(top) - b, top), (ro(top) - thick + b, top), (ro(top - b) - thick, top - b), (ro(b) - thick, b)]
        sections.append(("ring", [(r * c, y, r * s) for (r, y) in loop]))
        if k % per == 0:
            tips.append((ro(top) - thick * 0.5, top, th))
    band = orient_outward(stitch_sections(sections, True))
    balls = []
    for (r, y, th) in tips:
        balls.append(translate_mesh(uv_sphere(0.05, 0.05, 0.05, lod(ctx, 8, 6), lod(ctx, 5, 4)),
                                    r * math.cos(th), y + 0.03, -r * math.sin(th)))
    gems = []
    for (a, sz) in ((PI / 2.0, 1.0), (PI / 2.0 + TAU / points, 0.7), (PI / 2.0 - TAU / points, 0.7)):
        g = unweld_mesh(uv_sphere(0.065 * sz, 0.08 * sz, 0.04, 6, 4))
        r = R + 0.035
        gems.append(transform_mesh(g, xf_mul(xf_translate(r * math.cos(a), H * 0.5, -r * math.sin(a)),
                                              xf_rot_y(a - PI / 2.0))))
    return (merge_meshes([band] + balls), merge_meshes(gems))


def feat_crown(ctx):
    look = ctx["look"]
    design = ctx["design"]
    kind = look["Body"]
    R = design.get("crown_r", 0.39)
    if kind == "Drop":
        R = 0.27
    H = 0.17
    spike = 0.19
    cx = design.get("crown_x", 0.0)
    cz = 0.06
    if kind == "Cloud":
        cz = 0.12
    seat = 0.0
    for k in range(12):
        a = TAU * k / 12.0
        seat += height_at(ctx, cx + R * 0.85 * math.cos(a), cz + R * 0.85 * math.sin(a), 0.1)
    seat = seat / 12.0 - 0.05
    band, gems = crown_mesh(ctx, R, H, spike, 5, 0.06)
    tilt = rad(design.get("crown_tilt", -8.0))
    xf = xf_chain([xf_rot_z(tilt), xf_rot_x(rad(-6.0)), xf_translate(cx, seat, cz)])
    if kind == "Drop":
        # a little crown perched on the tip
        centre, axis = drop_seat(ctx, R * 0.9)
        band, gems = crown_mesh(ctx, R, H * 0.9, spike * 0.9, 5, 0.05)
        seat = centre[1] - 0.04
        xf = xf_chain([xf_rot_z(rad(-8.0)), xf_frame(vmad(centre, axis, -0.04), axis, (0.0, 0.0, 1.0))])
    add(ctx, fixed_role(GOLD), transform_mesh(band, xf))
    add(ctx, neon_role(GEM_RED), transform_mesh(gems, xf))
    ctx["crown_top"] = seat + H + spike + 0.08
    ctx["head_top"] = max(ctx.get("head_top", 0.0), ctx["crown_top"])


def drop_seat(ctx, R):
    # (centre, axis) where the drop's tip is R wide: the crown is "worn" around the tip
    body = ctx["body"]
    prof = body["profile"]
    y = prof[-1][1]
    for (r, yy) in prof[::-1]:
        if r >= R:
            y = yy
            break
    warp = body["warp"]
    centre = warp((0.0, y, 0.0))
    axis = vnorm(vsub(warp((0.0, y + 0.05, 0.0)), warp((0.0, y - 0.05, 0.0))))
    return (centre, axis)


def feat_halo(ctx):
    look = ctx["look"]
    top = max(ctx.get("head_top", 0.0), body_top(ctx))
    y = top + 0.24
    if look["Body"] == "Drop":
        y = max(body_top(ctx), ctx.get("crown_top", 0.0)) + 0.1
    m = torus(0.5, 0.058, lod(ctx, 28, 14), lod(ctx, 7, 5))
    m = translate_mesh(m, 0.0, y, 0.04)
    add(ctx, neon_role(look["Accent"]) + "@SpinY", m)


def feather_wing(ctx, size):
    # right wing (+X): layered rounded feathers fanning out from the hinge at the origin
    parts = []
    feathers = [(52.0, 1.0, 0.25, 0.0), (28.0, 0.95, 0.25, 0.04), (5.0, 0.82, 0.23, 0.08), (-18.0, 0.64, 0.2, 0.12)]
    for (ang, L, W, z) in feathers:
        m = leaf(L * size, W * size, 0.065 * size, lod(ctx, 7, 5), lod(ctx, 7, 5), 0.6, 0.55, 0.22)
        m = xform(m, [xf_rot_z(rad(ang)), xf_translate(0.0, 0.0, z * size)])
        parts.append(m)
    covert = leaf(0.5 * size, 0.27 * size, 0.08 * size, lod(ctx, 7, 5), lod(ctx, 6, 4), 0.55, 0.5, 0.1)
    parts.append(xform(covert, [xf_rot_z(rad(25.0)), xf_translate(0.0, 0.02, -0.05 * size)]))
    return merge_meshes(parts)


def bat_wing(ctx, size):
    # right wing (+X): scalloped membrane (extruded) + bones; returns (membrane, bones)
    pts = [(0.0, 0.2), (0.35, 0.45), (0.72, 0.68), (0.95, 0.62), (1.1, 0.42), (1.18, 0.12)]
    sc = []
    tips = [(1.18, 0.12), (0.86, -0.12), (0.5, -0.22), (0.12, -0.12)]
    for i in range(len(tips) - 1):
        a = tips[i]
        b = tips[i + 1]
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
        ctrl = (mid[0] - 0.06, mid[1] + 0.12)
        for j in range(1, 6):
            t = j / 6.0
            u = 1.0 - t
            sc.append((u * u * a[0] + 2 * u * t * ctrl[0] + t * t * b[0], u * u * a[1] + 2 * u * t * ctrl[1] + t * t * b[1]))
        sc.append(b)
    outline = pts + sc + [(0.0, -0.05)]
    outline = [(p[0] * size, p[1] * size) for p in outline]
    membrane = extrude(outline, 0.05 * size, 0.022 * size, 2)
    bones = []
    wrist = (0.95 * size, 0.62 * size, 0.0)
    arm = [(0.0, 0.18 * size, 0.0), (0.4 * size, 0.46 * size, 0.0), wrist]
    bones.append(tube(catmull_rom(arm, 4), [0.05 * size] * 9, lod(ctx, 6, 5), "round", "round", (0.0, 0.0, 1.0), 2))
    for tip in tips[:3]:
        path = [wrist, ((wrist[0] + tip[0] * size) * 0.5, (wrist[1] + tip[1] * size) * 0.5, 0.0), (tip[0] * size, tip[1] * size, 0.0)]
        bones.append(tube(path, [0.032 * size, 0.026 * size, 0.0], lod(ctx, 5, 4), "round", "round", (0.0, 0.0, 1.0), 1))
    claw = cone(0.04 * size, 0.0, 0.12 * size, 5, 0.01)
    bones.append(transform_mesh(claw, xf_frame(vadd(wrist, (0.0, 0.03 * size, 0.0)), (-0.3, 1.0, 0.0), (0.0, 0.0, 1.0))))
    return (membrane, merge_meshes(bones))


def insect_wing(ctx, size):
    fore = leaf(1.0 * size, 0.24 * size, 0.03 * size, lod(ctx, 6, 4), lod(ctx, 7, 5), 0.7, 0.55, 0.12)
    hind = leaf(0.78 * size, 0.2 * size, 0.03 * size, lod(ctx, 6, 4), lod(ctx, 6, 4), 0.7, 0.55, 0.05)
    return merge_meshes([xform(fore, [xf_rot_z(rad(34.0))]), xform(hind, [xf_rot_z(rad(4.0)), xf_translate(0.0, 0.0, 0.05)])])


def feat_wings(ctx):
    look = ctx["look"]
    body = ctx["body"]
    style = ctx["design"].get("wings", "feather")
    kind = look["Body"]
    size = ctx["design"].get("wing_size", 0.95)
    yaw = 96.0
    pitch = 12.0
    if kind == "Cloud":
        yaw = 108.0
        pitch = 16.0
        size *= 1.05
    if kind == "Bean":
        pitch = 18.0
    for side in (-1, 1):
        anim = "WingL" if side < 0 else "WingR"
        p, n = surface_at(body, side * yaw, pitch)
        hinge = vmad(p, n, -0.12)
        if style == "bat":
            membrane, bones = bat_wing(ctx, size)
            raise_a = rad(24.0)
            sweep_a = rad(-18.0)
        elif style == "insect":
            membrane = insect_wing(ctx, size)
            bones = None
            raise_a = rad(26.0)
            sweep_a = rad(-34.0)
        else:
            membrane = feather_wing(ctx, size)
            bones = None
            raise_a = rad(16.0)
            sweep_a = rad(-16.0)
        chain = [xf_rot_z(raise_a), xf_rot_y(sweep_a)]
        if side < 0:
            chain.append(xf_scale(-1.0, 1.0, 1.0))
        chain.append(xf_translate(hinge[0], hinge[1], hinge[2]))
        xf = xf_chain(chain)
        add(ctx, "Accent@" + anim, transform_mesh(membrane, xf))
        if bones is not None:
            add(ctx, "Body@" + anim, transform_mesh(bones, xf))
        add_pivot(ctx, anim, hinge)


def feat_tail(ctx):
    body = ctx["body"]
    look = ctx["look"]
    style = ctx["design"].get("tail", "pup")
    kind = look["Body"]
    pitch = -28.0 if kind != "Bean" else -38.0
    p, n = surface_at(body, 180.0, pitch)
    base = vmad(p, n, -0.12)
    body_parts = []
    accent_parts = []
    if style == "fox":
        pts = [(0.0, 0.0, 0.0), (0.0, 0.12, 0.38), (0.0, 0.55, 0.66), (0.0, 1.02, 0.62), (0.0, 1.32, 0.38)]

        def rf(t):
            return 0.13 + 0.25 * math.sin(PI * min(1.0, t * 1.05)) ** 0.8 if t < 0.95 else 0.0

        def rf_body(t):
            return 0.12 + 0.3 * (math.sin(PI * min(t, 1.0) * 0.95) ** 0.8)

        def rf_tip(t):
            k = (t - 0.62) / 0.38
            return (0.12 + 0.31 * (math.sin(PI * t * 0.95) ** 0.8)) * 1.04 * (max(0.0, 1.0 - k ** 2.5) ** 0.6)
        body_parts.append(sweep(pts, lod(ctx, 12, 6), rf_body, lod(ctx, 10, 6), (1.0, 0.0, 0.0), "round", "round", 0.0,
                                0.0, 0.7))
        accent_parts.append(sweep(pts, lod(ctx, 8, 5), rf_tip, lod(ctx, 10, 6), (1.0, 0.0, 0.0), "round", "round", 0.0,
                                  0.62, 1.0))
    elif style == "puff":
        puffs = [((0.0, 0.0, 0.0), 0.2), ((0.11, 0.07, 0.04), 0.14), ((-0.1, 0.08, 0.03), 0.14), ((0.0, -0.08, 0.08), 0.14),
                 ((0.02, 0.12, -0.04), 0.13)]
        m = radial_mesh(cloud_surface(puffs, 22.0), lod(ctx, 6, 4))
        accent_parts.append(translate_mesh(m, 0.0, 0.05, 0.22))
    elif style == "dragon":
        pts = [(0.0, 0.0, 0.0), (0.0, -0.06, 0.42), (0.1, 0.06, 0.8), (0.04, 0.32, 1.02), (-0.06, 0.52, 1.0)]

        def rf(t):
            return 0.19 * (1.0 - 0.85 * t)
        body_parts.append(sweep(pts, lod(ctx, 14, 7), rf, lod(ctx, 9, 6), (1.0, 0.0, 0.0), "round", "round", 0.0))
        spade = extrude(heart_poly(0.2, lod(ctx, 20, 12)), 0.06, 0.025, 1)
        end = pts[-1]
        prev = pts[-2]
        tdir = vnorm(vsub(end, prev))
        accent_parts.append(transform_mesh(xform(spade, [xf_rot_z(PI), xf_translate(0.0, 0.16, 0.0)]),
                                           xf_frame(end, tdir, (1.0, 0.0, 0.0))))
    elif style == "bird":
        for (ang, L) in ((-24.0, 0.75), (0.0, 0.88), (24.0, 0.75)):
            f = leaf(L, 0.17, 0.05, lod(ctx, 6, 4), lod(ctx, 7, 5), 0.6, 0.5, 0.25)
            f = xform(f, [xf_rot_y(-PI / 2.0), xf_rot_x(rad(-38.0)), xf_rot_y(rad(ang))])
            accent_parts.append(f)
        body_parts.append(ellipsoid(0.18, 0.15, 0.22, lod(ctx, 4, 3)))
    else:
        # pup / lava: perky curved tail with an accent tip
        pts = [(0.0, 0.0, 0.0), (0.0, 0.1, 0.3), (0.0, 0.42, 0.46), (0.0, 0.7, 0.36)]

        def rf(t):
            return 0.11 * (1.0 - 0.3 * t)
        body_parts.append(sweep(pts, lod(ctx, 10, 6), rf, lod(ctx, 8, 6), (1.0, 0.0, 0.0), "round", "round", 0.0, 0.0, 0.8))
        tip = pts[-1]
        if style == "lava":
            fl = flame_mesh(ctx, 0.17, 0.42, 0.06)
            accent_parts.append(transform_mesh(fl, xf_translate(tip[0], tip[1] - 0.12, tip[2] - 0.04)))
        else:
            accent_parts.append(translate_mesh(ellipsoid(0.135, 0.15, 0.135, lod(ctx, 5, 3)), tip[0], tip[1] - 0.04, tip[2]))
    # orient: tail space +Z = away from the body
    back = vnorm((n[0], 0.0, n[2])) if abs(n[0]) + abs(n[2]) > 1e-3 else (0.0, 0.0, 1.0)
    xf = xf_basis(vcross(UP, back), UP, back, base)
    for m in body_parts:
        add(ctx, "Body@Wag", transform_mesh(m, xf))
    for m in accent_parts:
        add(ctx, "Accent@Wag", transform_mesh(m, xf))
    add_pivot(ctx, "Wag", base)


def feat_rays(ctx):
    look = ctx["look"]
    rays = []
    count = 10
    for i in range(count):
        a = PI / 2.0 + TAU * i / float(count)
        long_ray = i % 2 == 0
        L = 0.62 if long_ray else 0.44
        W = 0.17 if long_ray else 0.13
        start = 0.86

        def rf(t, W=W):
            return (W * (1.0 - t) ** 0.9 + 0.012, W * 0.55 * (1.0 - t) ** 0.9 + 0.01)
        path = [(start + L * j / 4.0, 0.0, 0.0) for j in range(5)]
        radii = [rf(j / 4.0) for j in range(5)]
        radii[-1] = 0.0
        m = tube(path, radii, lod(ctx, 7, 5), "round", "round", (0.0, 1.0, 0.0), 2)
        rays.append(transform_mesh(m, xf_mul(xf_rot_z(a), xf_translate(0.0, 0.0, 0.32))))
    add(ctx, "Accent@SpinZ", merge_meshes(rays))


def flame_mesh(ctx, R, H, curl):
    def tongue(R, H, curl, lean):
        pts = [(0.0, 0.0, 0.0), (lean * 0.3, H * 0.35, 0.0), (lean * 0.6 + curl * 0.3, H * 0.7, 0.0), (lean + curl, H, 0.02)]

        def rf(t):
            if t >= 1.0:
                return 0.0
            return R * (math.sin(PI * min(1.0, 0.25 + t * 0.9)) ** 0.9) * (1.0 - t) ** 0.55
        return sweep(pts, lod(ctx, 10, 6), rf, lod(ctx, 9, 6), (1.0, 0.0, 0.0), "round", "round", 0.2)
    parts = [tongue(R, H, curl, 0.0),
             translate_mesh(tongue(R * 0.62, H * 0.62, 0.05, 0.12), R * 0.55, -0.02, 0.02),
             translate_mesh(tongue(R * 0.62, H * 0.55, -0.05, -0.12), -R * 0.55, -0.02, 0.02)]
    return merge_meshes(parts)


def feat_flame(ctx):
    top = body_top(ctx)
    outer = flame_mesh(ctx, 0.27, 0.75, -0.08)
    inner = flame_mesh(ctx, 0.15, 0.42, -0.04)
    add(ctx, neon_role(FLAME_OUT), translate_mesh(outer, 0.0, top - 0.2, 0.06))
    add(ctx, neon_role(FLAME_IN), translate_mesh(inner, 0.0, top - 0.17, -0.07))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), top + 0.5)


def feat_bolt(ctx):
    look = ctx["look"]
    where = ctx["design"].get("bolt", "top")
    color = BOLT_YELLOW
    if is_dark(look["Color"]) is False and look["Color"][0] > 230 and look["Color"][1] > 200:
        color = (255, 170, 30)
    m = extrude(bolt_poly(0.62), 0.12, 0.04, 2)
    if where == "forehead":
        patch = body_patch(ctx["body"], 0.0, 40.0)
        s, n = patch(0.0, 0.0)
        m = extrude(bolt_poly(0.5), 0.07, 0.028, 2)
        xf = xf_frame(vmad(s, n, 0.0), vnorm(vcross(n, (1.0, 0.0, 0.0))), vmul(n, -1.0))
        add(ctx, neon_role(color), transform_mesh(xform(m, [xf_rot_z(rad(-8.0))]), xf))
        return
    top = max(body_top(ctx), ctx.get("head_top", 0.0) - 0.5)
    if where == "ears":
        pos = (0.0, body_top(ctx) + 0.2, -0.3)
    else:
        pos = (0.0, top + 0.36, 0.0)
    add(ctx, neon_role(color), xform(m, [xf_rot_z(rad(-10.0)), xf_rot_x(rad(-12.0)), xf_translate(pos[0], pos[1], pos[2])]))


SPIKE_SPOTS = [(70.0, 20.0), (-70.0, 25.0), (110.0, -10.0), (-115.0, -5.0), (150.0, 35.0), (-150.0, 30.0), (180.0, -20.0),
               (60.0, -35.0), (-60.0, -30.0), (95.0, 50.0), (-95.0, 52.0), (130.0, -45.0), (-130.0, -42.0), (20.0, 62.0),
               (-25.0, 64.0), (175.0, 55.0)]


def feat_spikes(ctx):
    body = ctx["body"]
    parts = []
    for (yaw, pitch) in SPIKE_SPOTS:
        p, n = surface_at(body, yaw, pitch)
        t = perpendicular(n)
        b = vcross(n, t)
        for j in range(3):
            a = TAU * j / 3.0 + yaw
            dirv = vnorm(vadd(n, vadd(vmul(t, 0.45 * math.cos(a)), vmul(b, 0.45 * math.sin(a)))))
            sp = cone(0.022, 0.0, 0.13, 5, 0.0)
            parts.append(transform_mesh(sp, xf_frame(vmad(p, n, -0.01), dirv, perpendicular(dirv))))
    add(ctx, fixed_role(SPINE), merge_meshes(parts))


def feat_flower(ctx):
    look = ctx["look"]
    x = 0.28
    z = 0.0
    y = height_at(ctx, x, z, 0.12)
    petals = []
    count = 5
    for i in range(count):
        a = TAU * i / float(count)
        pt = leaf(0.27, 0.12, 0.05, lod(ctx, 6, 4), lod(ctx, 5, 4), 0.5, 0.45, 0.25)
        petals.append(xform(pt, [xf_rot_z(rad(18.0)), xf_rot_y(a)]))
    centre = uv_sphere(0.085, 0.07, 0.085, lod(ctx, 10, 6), lod(ctx, 6, 4))
    xf = xf_chain([xf_rot_z(rad(-22.0)), xf_rot_x(rad(-15.0)), xf_translate(x, y + 0.02, z)])
    add(ctx, "Accent", transform_mesh(merge_meshes(petals), xf))
    add(ctx, fixed_role(FLOWER_CENTRE), transform_mesh(translate_mesh(centre, 0.0, 0.05, 0.0), xf))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), y + 0.15)


def feat_beak(ctx):
    style = ctx["design"].get("beak", "chick")
    patch = ctx["face_patch"]
    f = ctx["body"]["face"]
    s, n = patch(0.0, f["mouth_v"] + 0.05)
    big = 1.0 if style == "chick" else 0.85
    upper = cone(0.13 * big, 0.0, 0.2 * big, lod(ctx, 10, 6), 0.03, 2)
    upper = scale_mesh(upper, 1.0, 1.0, 0.68)
    lower = scale_mesh(cone(0.1 * big, 0.0, 0.12 * big, lod(ctx, 10, 6), 0.025, 1), 1.0, 1.0, 0.55)
    frame = xf_frame(vmad(s, n, -0.04), vnorm(vadd(n, (0.0, -0.12, 0.0))), (0.0, 1.0, 0.0))
    add(ctx, "Accent", transform_mesh(xform(upper, [xf_translate(0.0, 0.0, 0.018)]), frame))
    add(ctx, "Accent", transform_mesh(xform(lower, [xf_translate(0.0, -0.02, -0.06)]), frame))


def feat_belly(ctx):
    patch = body_patch(ctx["body"], 0.0, -22.0)
    add(ctx, fixed_role((245, 245, 250)), decal(patch, 0.0, 0.0, 0.62, 0.66, 0.012, 0.004, 4, lod(ctx, 28, 14),
                                                skirt=0.03, dome=0.3))


def feat_antenna(ctx):
    look = ctx["look"]
    top = body_top(ctx)
    pts = [(0.0, top - 0.12, 0.0), (0.0, top + 0.2, 0.02), (0.08, top + 0.45, 0.06), (0.16, top + 0.56, 0.06)]
    stalk = sweep(pts, lod(ctx, 8, 5), taper_fn(0.038, 0.0285), lod(ctx, 7, 5), (1.0, 0.0, 0.0), "round", "round", 0.0)
    base = translate_mesh(scale_mesh(uv_sphere(0.1, 0.05, 0.1, lod(ctx, 10, 6), lod(ctx, 5, 4)), 1.0, 1.0, 1.0), 0.0, top - 0.01, 0.0)
    add(ctx, fixed_role(STALK), merge_meshes([stalk, base]))
    ball = ellipsoid(0.15, 0.15, 0.15, lod(ctx, 5, 3))
    add(ctx, neon_role(look["Accent"]), translate_mesh(ball, 0.17, top + 0.66, 0.06))
    ctx["head_top"] = max(ctx.get("head_top", 0.0), top + 0.7)


CRACKS = [
    [(-62.0, 30.0), (-70.0, 18.0), (-64.0, 6.0), (-74.0, -8.0), (-68.0, -22.0)],
    [(58.0, 40.0), (66.0, 28.0), (60.0, 16.0), (70.0, 4.0)],
    [(66.0, 28.0), (78.0, 34.0), (88.0, 30.0)],
    [(-20.0, 70.0), (0.0, 64.0), (14.0, 70.0), (30.0, 62.0)],
    [(130.0, 10.0), (140.0, -6.0), (132.0, -22.0), (144.0, -36.0)],
    [(-140.0, 30.0), (-152.0, 16.0), (-144.0, 2.0)],
    [(-152.0, 16.0), (-166.0, 12.0)],
    [(20.0, -55.0), (36.0, -48.0), (46.0, -58.0)],
    [(-30.0, -40.0), (-42.0, -30.0), (-38.0, -18.0)],
    [(100.0, 60.0), (120.0, 52.0), (130.0, 62.0)],
    [(-100.0, -40.0), (-110.0, -52.0), (-98.0, -64.0)],
]


def feat_cracks(ctx):
    look = ctx["look"]
    body = ctx["body"]
    parts = []
    for crack in CRACKS:
        pts = []
        dense = []
        for i in range(len(crack) - 1):
            a = crack[i]
            b = crack[i + 1]
            for j in range(3):
                t = j / 3.0
                dense.append((lerp(a[0], b[0], t), lerp(a[1], b[1], t)))
        dense.append(crack[-1])
        for (yaw, pitch) in dense:
            p, n = surface_at(body, yaw, pitch)
            pts.append(vmad(p, n, 0.0))
        radii = [0.06 * (1.0 - 0.6 * abs(i / float(len(pts) - 1) - 0.35)) for i in range(len(pts))]
        parts.append(tube(pts, radii, 5, "round", "round", None, 1))
    add(ctx, neon_role(look["Accent"]), merge_meshes(parts))


# ----------------------------------------------------------------------------- signature details

def detail_feet(ctx):
    body = ctx["body"]
    style = ctx["design"].get("feet")
    look = ctx["look"]
    for side in (-1, 1):
        p, n = surface_at(body, side * 26.0, -62.0)
        if style == "bird":
            foot = ellipsoid(0.15, 0.06, 0.2, lod(ctx, 4, 3))
            toes = []
            for a in (-0.45, 0.0, 0.45):
                toe = ellipsoid(0.055, 0.045, 0.12, lod(ctx, 3, 2))
                toes.append(xform(toe, [xf_translate(0.0, 0.0, -0.12), xf_rot_y(a)]))
            m = merge_meshes([foot] + toes)
            role = "Accent" if ctx["look"]["Features"].count("Beak") and look["Accent"][0] > 200 and look["Accent"][1] < 180 else fixed_role(BIRD_FEET)
            add(ctx, role, translate_mesh(m, p[0] * 0.9, p[1] - 0.04, p[2] - 0.06))
        else:
            paw = ellipsoid(0.2, 0.15, 0.24, lod(ctx, 5, 3))
            add(ctx, "Body", translate_mesh(paw, p[0] * 0.92, p[1] + 0.02, p[2] - 0.06))
            # toe beans on the paw front
            beans = []
            for (dx, dy, r) in ((0.0, -0.02, 0.06), (-0.075, 0.035, 0.035), (0.0, 0.055, 0.035), (0.075, 0.035, 0.035)):
                beans.append(translate_mesh(ellipsoid(r, r * 0.85, r * 0.6, 2), p[0] * 0.92 + dx, p[1] + 0.0 + dy, p[2] - 0.06 - 0.215))
            add(ctx, fixed_role((255, 160, 185)), merge_meshes(beans))


def detail_underpuffs(ctx):
    # soft accent-coloured cloud base peeking out under the body (front and sides only)
    puffs = [((0.0, 0.0, 0.0), 0.6), ((0.62, 0.02, 0.06), 0.46), ((-0.62, 0.02, 0.06), 0.46), ((0.0, 0.0, 0.3), 0.5)]
    m = radial_mesh(cloud_surface(puffs, 12.0), lod(ctx, 8, 5))
    add(ctx, "Accent", translate_mesh(scale_mesh(m, 1.0, 0.75, 0.9), 0.0, -0.72, 0.02))


def detail_drop_shine(ctx):
    patch = body_patch(ctx["body"], 32.0, 30.0)
    add(ctx, "Accent", decal(patch, 0.0, 0.0, 0.09, 0.22, 0.012, 0.006, 2, lod(ctx, 14, 8), rot=rad(-25.0), skirt=0.02))
    add(ctx, "Accent", decal(patch, 0.1, -0.3, 0.05, 0.05, 0.01, 0.006, 1, lod(ctx, 10, 6), skirt=0.02))


def detail_streaks(ctx):
    for (yaw, pitch, L) in ((150.0, 40.0, 0.26), (-160.0, 30.0, 0.2), (180.0, 55.0, 0.3)):
        patch = body_patch(ctx["body"], yaw, pitch)
        add(ctx, "Accent", decal(patch, 0.0, 0.0, 0.06, L, 0.012, 0.006, 2, lod(ctx, 12, 8), rot=rad(-15.0), skirt=0.02))


def detail_cheek_tufts(ctx):
    body = ctx["body"]
    for side in (-1, 1):
        p, n = surface_at(body, side * 70.0, -20.0)
        x = vnorm((n[0], 0.0, n[2]))
        z = vcross(x, UP)
        tufts = []
        for (dy, L, a) in ((0.09, 0.24, 18.0), (-0.02, 0.27, -6.0), (-0.12, 0.2, -30.0)):
            tf = leaf(L, 0.1, 0.08, lod(ctx, 6, 4), lod(ctx, 5, 4), 0.55, 0.4, 0.0)
            tufts.append(xform(tf, [xf_rot_z(rad(a)), xf_translate(-0.1, dy, 0.0)]))
        add(ctx, "Body", transform_mesh(merge_meshes(tufts), xf_basis(x, UP, z, p)))


def detail_cowlick(ctx):
    top = body_top(ctx)
    pts = [(0.0, top - 0.1, 0.05), (0.0, top + 0.12, 0.0), (0.08, top + 0.26, -0.06), (0.2, top + 0.24, -0.1)]
    m = sweep(pts, lod(ctx, 9, 5), fade_fn(0.08), lod(ctx, 7, 5), (1.0, 0.0, 0.0), "round", "round", 0.1)
    pts2 = [(0.0, top - 0.1, 0.1), (-0.02, top + 0.08, 0.08), (-0.12, top + 0.17, 0.06), (-0.2, top + 0.13, 0.05)]
    m2 = sweep(pts2, lod(ctx, 8, 5), fade_fn(0.06), lod(ctx, 7, 5), (1.0, 0.0, 0.0), "round", "round", 0.1)
    add(ctx, "Accent", merge_meshes([m, m2]))


def emblem(ctx, poly, depth, pitch, role, scale=1.0, rot=0.0):
    patch = body_patch(ctx["body"], 0.0, pitch)
    s, n = patch(0.0, 0.0)
    m = extrude([(p[0] * scale, p[1] * scale) for p in poly], depth, depth * 0.4, 2)
    xf = xf_frame(vmad(s, n, depth * 0.15), vnorm(vcross(n, (1.0, 0.0, 0.0))), vmul(n, -1.0))
    add(ctx, role, transform_mesh(xform(m, [xf_rot_z(rot)]), xf))


def detail_star_mark(ctx):
    emblem(ctx, star_poly(5, 0.15, 0.065), 0.06, 36.0, "Accent", 1.0, rad(-8.0))


def detail_moon_mark(ctx):
    emblem(ctx, crescent_poly(0.2, 0.45), 0.07, 36.0, "Accent", 1.0, rad(-20.0))


def detail_freckles(ctx):
    patch = ctx["face_patch"]
    f = ctx["body"]["face"]
    for side in (-1, 1):
        for (du, dv) in ((-0.06, 0.07), (0.0, 0.1), (0.06, 0.07)):
            add(ctx, "Accent", decal(patch, side * (f["blush_u"] + du), f["blush_v"] + dv, 0.02, 0.02, 0.006, 0.006, 1,
                                     8, skirt=0.01))


def detail_ripples(ctx):
    # wavy dune ripples across the top of the head
    body = ctx["body"]
    lines = []
    for (pitch, span, phase) in ((50.0, 56.0, 0.0), (65.0, 62.0, 1.3)):
        pts = []
        for i in range(17):
            yaw = lerp(-span, span, i / 16.0)
            p, n = surface_at(body, yaw, pitch + 2.5 * math.sin(yaw / 14.0 + phase))
            pts.append(p)
        radii = [0.032 * (math.sin(PI * i / 16.0) ** 0.4) + 0.004 for i in range(17)]
        lines.append(tube(pts, radii, 6, "round", "round", None, 2))
    add(ctx, "Accent", merge_meshes(lines))


def detail_star_freckles(ctx):
    body = ctx["body"]
    stars = []
    for (yaw, pitch, s) in ((60.0, 35.0, 1.0), (-70.0, 25.0, 0.8), (100.0, -20.0, 0.9), (-105.0, -30.0, 1.0), (150.0, 30.0, 1.0),
                            (-150.0, 45.0, 0.8), (180.0, -10.0, 1.0), (30.0, -55.0, 0.7), (-35.0, 62.0, 0.8)):
        p, n = surface_at(body, yaw, pitch)
        st = extrude(star_poly(4, 0.07 * s, 0.025 * s), 0.025, 0.008, 1)
        stars.append(transform_mesh(st, xf_frame(vmad(p, n, 0.005), perpendicular(n), vmul(n, -1.0))))
    add(ctx, neon_role((255, 255, 255)), merge_meshes(stars))


def detail_belly_accent(ctx):
    design = ctx["design"]
    pitch = design.get("belly_pitch", -50.0)
    size = design.get("belly_size", 1.0)
    patch = body_patch(ctx["body"], 0.0, pitch)
    rx = 0.42 * size
    ry = 0.4 * size
    add(ctx, "Accent", decal(patch, 0.0, 0.0, rx, ry, 0.014, 0.004, 3, lod(ctx, 24, 12), skirt=0.03, dome=0.3))
    if design.get("belly_plates"):
        belly = dome_patch(patch, 0.0, 0.0, rx, ry, 0.014, 0.004, 0.3)
        plates = []
        for v in (0.14 * size, -0.06 * size):
            half = rx * math.sqrt(max(0.0, 1.0 - (v / ry) ** 2)) * 0.9
            uvs = [(lerp(-half, half, i / 10.0), v - 0.025 * math.sin(PI * i / 10.0)) for i in range(11)]
            plates.append(tube(surface_path(belly, uvs, 0.0), [0.022] * 11, 6, "round", "round", None, 2))
        add(ctx, "Body", merge_meshes(plates))


def detail_back_stripe(ctx):
    body = ctx["body"]
    pts = []
    for i in range(9):
        pitch = lerp(60.0, -40.0, i / 8.0)
        p, n = surface_at(body, 180.0, pitch)
        pts.append(vmad(p, n, 0.0))
    add(ctx, "Accent", tube(pts, [0.035] * len(pts), 6, "round", "round", None, 2))


def detail_arms(ctx):
    body = ctx["body"]
    for side in (-1, 1):
        p, n = surface_at(body, side * 88.0, -8.0)
        pts = [(0.0, 0.0, 0.0), (0.22, 0.0, 0.0), (0.3, 0.12, 0.0), (0.3, 0.3, 0.0)]
        m = sweep(pts, lod(ctx, 8, 5), taper_fn(0.13, 0.104), lod(ctx, 9, 6), (0.0, 0.0, 1.0), "round", "round", 0.0)
        if side < 0:
            m = mirror_x(m)
        add(ctx, "Body", translate_mesh(m, p[0] - side * 0.12, p[1], p[2] + 0.02))


def detail_shards(ctx):
    look = ctx["look"]
    kind = look["Body"]
    parts = []
    n = lod(ctx, 5, 3)
    if kind == "Crystal":
        for (side, sc, ang, x, y, z) in ((1, 1.0, -34.0, 0.42, 0.72, 0.28), (-1, 0.8, 30.0, -0.38, 0.62, 0.34),
                                         (1, 0.6, -60.0, 0.78, -0.42, 0.18), (-1, 0.55, 58.0, -0.76, -0.48, 0.16)):
            g = unweld_mesh(gem(0.2 * sc, -0.3 * sc, -0.1 * sc, 0.5 * sc, 0.85 * sc, n))
            parts.append(xform(g, [xf_rot_y(rad(30.0)), xf_rot_x(rad(16.0)), xf_rot_z(rad(ang)), xf_translate(x, y, z)]))
    else:
        for side in (-1, 1):
            g = unweld_mesh(gem(0.15, -0.2, -0.05, 0.3, 0.62, n))
            parts.append(xform(g, [xf_rot_z(side * rad(-30.0)), xf_rot_x(rad(18.0)), xf_translate(side * 0.66, 0.66, 0.4)]))
    add(ctx, "Accent", merge_meshes(parts))


def detail_bolt_cheeks(ctx):
    patch = ctx["face_patch"]
    f = ctx["body"]["face"]
    for side in (-1, 1):
        s, n = patch(side * (f["blush_u"] + 0.01), f["blush_v"] - 0.01)
        m = extrude(bolt_poly(0.42), 0.05, 0.018, 1)
        xf = xf_frame(vmad(s, n, 0.006), vnorm(vcross(n, (1.0, 0.0, 0.0))), vmul(n, -1.0))
        add(ctx, "Accent", transform_mesh(xform(m, [xf_rot_z(side * rad(15.0))]), xf))


FEATURES = {
    "Ears": feat_ears, "BunnyEars": feat_bunny_ears, "Horns": feat_horns, "Antenna": feat_antenna,
    "Flower": feat_flower, "Flame": feat_flame, "Crown": feat_crown, "Bolt": feat_bolt, "Halo": feat_halo,
    "Wings": feat_wings, "Tail": feat_tail, "Rays": feat_rays, "Spikes": feat_spikes, "Beak": feat_beak,
    "Belly": feat_belly, "Cracks": feat_cracks,
}

# head pieces first (so the crown/halo/bolt know how tall the head is), the halo last
FEATURE_ORDER = ["Belly", "Beak", "Spikes", "Cracks", "Ears", "BunnyEars", "Horns", "Antenna", "Flower", "Flame", "Crown",
                 "Bolt", "Halo", "Wings", "Tail", "Rays"]

DETAILS = [
    ("feet", detail_feet), ("underpuffs", detail_underpuffs), ("drop_shine", detail_drop_shine),
    ("streaks", detail_streaks), ("cheek_tufts", detail_cheek_tufts), ("cowlick", detail_cowlick),
    ("star_mark", detail_star_mark), ("moon_mark", detail_moon_mark), ("freckles", detail_freckles),
    ("star_freckles", detail_star_freckles), ("belly_accent", detail_belly_accent), ("back_stripe", detail_back_stripe),
    ("arms", detail_arms), ("shards", detail_shards), ("bolt_cheeks", detail_bolt_cheeks), ("ripples", detail_ripples),
]


# ----------------------------------------------------------------------------- assembly

ROLE_ORDER = ["Body", "Accent", "Eye", "Shine", "Blush", "Mouth"]


def named(name, m):
    return {"name": name, "verts": m["verts"], "tris": m["tris"]}


def role_sort_key(name):
    base, anim = role_base(name)
    if name == "Root":
        return (0, 0, name)
    if base == "Pivot":
        return (4, 0, name)
    if anim is not None:
        return (3, 0, name)
    if base in ROLE_ORDER:
        return (1, ROLE_ORDER.index(base), name)
    return (2, 0, name)


def build_pet_at(pet_id, q):
    look = PETS[pet_id]
    ctx = {"id": pet_id, "look": look, "design": DESIGN.get(pet_id, {}), "q": q, "parts": {}, "order": [], "pivots": {}}
    body = make_body(ctx)
    ctx["body"] = body
    add(ctx, "Body", body["mesh"])
    build_face(ctx)
    for (key, fn) in DETAILS:
        if ctx["design"].get(key):
            fn(ctx)
    for feature in FEATURE_ORDER:
        if feature in look["Features"]:
            FEATURES[feature](ctx)
    out = [named("Root", box(0.1, 0.1, 0.1))]
    roles = sorted(ctx["order"], key=role_sort_key)
    for role in roles:
        out.append(named(role, merge_meshes(ctx["parts"][role])))
    for anim in sorted(ctx["pivots"]):
        p = ctx["pivots"][anim]
        out.append(named("Pivot@" + anim, translate_mesh(box(0.05, 0.05, 0.05), p[0], p[1], p[2])))
    return out


TRI_BUDGET = 4000


def build_pet(pet_id, budget=TRI_BUDGET):
    # Highest detail that fits the triangle budget
    meshes = None
    for q in (1.0, 0.88, 0.78, 0.68, 0.6, 0.52):
        meshes = build_pet_at(pet_id, q)
        if tri_count(meshes) <= budget:
            return meshes
    return meshes


def build_all(budget=TRI_BUDGET):
    out = {}
    for pet_id in PET_IDS:
        out[pet_id] = build_pet(pet_id, budget)
    return out


# Layout of the exported pack: pets on a grid (in studs), each pet relative to its own Root.
PACK_COLUMNS = 8
PACK_SPACING = 6.0


def pack_offset(index):
    # grid position (x, y, z) in studs of the pet at PET_IDS[index]
    row = index // PACK_COLUMNS
    col = index % PACK_COLUMNS
    return ((col - (PACK_COLUMNS - 1) / 2.0) * PACK_SPACING, 0.0, row * PACK_SPACING)


def to_sketchup(meshes, inches_per_stud=12.0, offset=(0.0, 0.0, 0.0)):
    # Roblox (Y up, front -Z) -> SketchUp (Z up, front -Y) in inches. It is a proper rotation
    # (x, y, z) -> (-x, z, y), so the counter-clockwise outward winding is kept.
    out = []
    for m in meshes:
        verts = [(-(p[0] + offset[0]) * inches_per_stud, (p[2] + offset[2]) * inches_per_stud,
                  (p[1] + offset[1]) * inches_per_stud) for p in m["verts"]]
        out.append({"name": m["name"], "verts": verts, "tris": list(m["tris"])})
    return out


def sketchup_layout(pet_ids=None, inches_per_stud=12.0, include_markers=True):
    # Everything a SketchUp build needs, on the same grid as the GLB/OBJ pack:
    # [{"pet", "role", "name": "<PetId>.<Role>", "rgb", "material", "transparency", "visible", "verts", "tris"}]
    out = []
    ids = PET_IDS if pet_ids is None else pet_ids
    for pet_id in ids:
        look = PETS[pet_id]
        meshes = to_sketchup(build_pet(pet_id), inches_per_stud, pack_offset(PET_IDS.index(pet_id)))
        for m in meshes:
            info = role_color(m["name"], look)
            if not info["visible"] and not include_markers:
                continue
            out.append({"pet": pet_id, "role": m["name"], "name": pet_id + "." + m["name"], "rgb": info["rgb"],
                        "material": info["material"], "transparency": info["transparency"],
                        "visible": info["visible"], "verts": m["verts"], "tris": m["tris"]})
    return out
