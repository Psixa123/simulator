"""Cycles (CPU) preview renders of a Blender-built pet: transparent background, key/fill/rim lighting (plus
a soft bounce) and an inverted-hull ink outline like the game's three.js previews. (EEVEE needs a GPU/EGL
context, which the headless bpy module doesn't have on a server, so the renders use Cycles on the CPU.)

The views match tools/pets/viewer.html (hero / front / side / back), converted to Blender axes (the pet
faces -Y here): viewer direction (gx, gy, gz) -> Blender (-gx, gz, gy).
"""

import math

import bpy
from mathutils import Vector

from kit import FACE_ROLES, link

VIEWS = {
    "hero": (-0.38, 0.24, -1.0),
    "front": (0.0, 0.06, -1.0),
    "side": (-1.0, 0.06, 0.0),
    "back": (0.35, 0.35, 1.0),
}
INK = (0.11, 0.10, 0.20)


def setup(size=768, samples=64):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 16
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    world = bpy.data.worlds.get("PetWorld") or bpy.data.worlds.new("PetWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.62, 0.70, 0.86, 1.0)
    bg.inputs["Strength"].default_value = 0.32
    scene.world = world


def _area(name, location, energy, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.size = size
    obj = link(bpy.data.objects.new(name, data))
    obj.location = location
    direction = -Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def lights(radius=1.5):
    """Key (warm, front-left-top), fill (cool, front-right), rim (behind, top) and a soft bottom bounce."""
    k = max(radius, 1.0)
    out = [
        _area("Key", (-3.2 * k, -4.0 * k, 4.2 * k), 520 * k * k, (1.0, 0.95, 0.88), 3.0 * k),
        _area("Fill", (4.5 * k, -3.2 * k, 1.0 * k), 170 * k * k, (0.82, 0.88, 1.0), 4.0 * k),
        _area("Rim", (2.0 * k, 5.0 * k, 3.4 * k), 700 * k * k, (1.0, 1.0, 1.0), 2.5 * k),
        _area("Bounce", (0.0, -2.0 * k, -4.0 * k), 70 * k * k, (0.85, 0.82, 1.0), 5.0 * k),
    ]
    return out


def ink_material():
    mat = bpy.data.materials.get("InkOutline")
    if mat:
        return mat
    mat = bpy.data.materials.new("InkOutline")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ink = nt.nodes.new("ShaderNodeEmission")
    ink.inputs["Color"].default_value = (*INK, 1.0)
    ink.inputs["Strength"].default_value = 1.0
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
    nt.links.new(ink.outputs["Emission"], mix.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def outline(objs, thickness=0.024):
    """Inverted hulls (pushed out along the normals, faces flipped, backfaces see-through)."""
    hulls = []
    for obj in objs:
        role = obj.name.split(".", 1)[-1]
        if role.split("@")[0] in FACE_ROLES or role in ("Root",) or role.startswith("Pivot"):
            continue
        mesh = obj.data.copy()
        mesh.materials.clear()
        mesh.materials.append(ink_material())
        for v in mesh.vertices:
            v.co = v.co + v.normal * thickness
        mesh.flip_normals()
        hull = link(bpy.data.objects.new(obj.name + "#ink", mesh))
        hull.visible_shadow = False
        hull.visible_diffuse = False
        hull.visible_glossy = False
        hull.visible_transmission = False
        hulls.append(hull)
    return hulls


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        for v in obj.data.vertices:
            co = obj.matrix_world @ v.co
            lo = Vector(map(min, lo, co))
            hi = Vector(map(max, hi, co))
    return lo, hi


def render_views(objs, out_prefix, views=("hero", "front", "side", "back"), size=768, samples=64):
    """Renders <out_prefix>_<view>.png for each view; returns the paths."""
    setup(size, samples)
    visible = [o for o in objs if not o.hide_render]
    lo, hi = bounds(visible)
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.5)
    rig = lights(radius / 1.4)
    hulls = outline(visible)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens_unit = "FOV"
    cam_data.angle = math.radians(30)
    cam = link(bpy.data.objects.new("Cam", cam_data))
    bpy.context.scene.camera = cam
    paths = []
    try:
        for view in views:
            gx, gy, gz = VIEWS[view]
            d = Vector((-gx, gz, gy)).normalized()
            dist = radius / math.sin(math.radians(15)) * 1.04
            cam.location = center + d * dist
            cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
            cam_data.clip_start = 0.05
            cam_data.clip_end = dist * 4
            path = f"{out_prefix}_{view}.png"
            bpy.context.scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            paths.append(path)
    finally:
        for obj in hulls + rig + [cam]:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
    return paths
