"""Store heroes made from the game's own models (tools/icons/README.md, "Store icons").

Most store heroes are SketchUp models (tools/icons/sketchup_store_icons.py -> assets/source/world/store_icons.json).
A few show things the game already has a model of, and use that model instead of a copy:

  Store_AuroraGryphon  the Aurora Gryphon pet          tools/pets/pet_geometry.py (the StormlingPets.glb meshes)
  Store_PetSlots       three pets side by side          Puffling, Zappy and Thunder Pup, the same way
  Store_AutoCatch      the Storm Vacuum (gear prop      assets/source/world/gear.json (tools/world/sketchup/gear.py),
                       VacuumGun) + the store model     added to the SketchUp part (the cloud and the suction beam)

render_icons.py --set store calls add_scenes() on the loaded source before it writes the GLB. Everything is
turned into the icon source layout (SketchUp inches, Z up, front -Y, pieces named by paint), so the scenes are
shaded, outlined and lit exactly like the SketchUp heroes.
"""

import json
import math
import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
GEAR = ROOT / "assets" / "source" / "world" / "gear.json"
INCH = 12.0  # inches per stud

sys.path.insert(0, str(ROOT / "tools" / "pets"))
import build_pets  # noqa: E402  (tools/pets: loads pet_geometry.py the way the SketchUp sandbox runs it)

pets = SimpleNamespace(**build_pets.load_geometry())

# Pets per scene: (pet id, foot position in studs, scale, turn in degrees to the left)
PET_SCENES = {
    "Store_AuroraGryphon": [("AuroraGryphon", (0.0, 0.0, 0.0), 2.4, 0)],
    "Store_PetSlots": [("Puffling", (-2.35, 0.9, 0.0), 1.55, 22), ("Zappy", (2.35, 0.9, 0.0), 1.55, -22),
                       ("ThunderPup", (0.0, -0.5, 0.0), 1.9, 0)],
}
# The vacuum gun in Store_AutoCatch: scaled, its barrel (gear.py: along -Y) turned to +X and raised, its grip
# (the prop's origin) moved to `at` (studs). sketchup_store_icons.py (chunk 10, NOZZLE) aims the beam at the
# nozzle mouth this puts at nozzle() - keep the two in step.
GUN = {"scale": 2.3, "turn": 90.0, "raise": 24.0, "at": (-2.6, 0.0, 1.0)}
GUN_NOZZLE = (0.0, -2.75, 0.66)  # gear.py: the nozzle mouth, on the barrel axis
# The gun's tint paints for the store (its gear.json defaults are the plain grey of the starter look)
GUN_PAINTS = {"Primary": "D5DCF2", "Secondary": "3A4052", "Tertiary": "46C8FF"}


def hexrgb(rgb):
    return "".join(f"{int(round(c)):02X}" for c in rgb)


def mix(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def blush_paint(look):
    """The pets' blush is a see-through pink; here it is solid, so it is pre-mixed with the body colour."""
    return "Color_" + hexrgb(mix(look["Color"], pets.BLUSH_PINK, 0.6))


def pet_paint(role, look):
    """Paint name of a pet mesh role (tools/pets/README.md, "Roles"), or None for invisible markers."""
    base = pets.role_base(role)[0]
    info = pets.role_color(role, look)
    if not info["visible"]:
        return None
    if base == "Blush":
        return blush_paint(look)
    if base == "Shine" or info["material"] == "Neon":
        return "Neon_" + hexrgb(info["rgb"])
    return "Color_" + hexrgb(info["rgb"])


def place(verts, scale, turn, raise_deg, at):
    """Studs (x, y, z) -> scaled, turned about Z, raised (turned about Y: +X goes up), moved, in inches."""
    ct, st = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    cr, sr = math.cos(math.radians(-raise_deg)), math.sin(math.radians(-raise_deg))
    out = []
    for x, y, z in verts:
        x, y, z = x * scale, y * scale, z * scale
        x, y = x * ct - y * st, x * st + y * ct
        x, z = x * cr + z * sr, -x * sr + z * cr
        out.append([round((x + at[0]) * INCH, 2), round((y + at[1]) * INCH, 2), round((z + at[2]) * INCH, 2)])
    return out


def pet_pieces(pet_id, foot, scale, turn):
    """One pet as icon source pieces, standing on `foot` (studs), facing the front turned by `turn` degrees."""
    look = pets.PETS[pet_id]
    meshes = pets.build_pet(pet_id)
    # Roblox studs (Y up, front -Z) -> SketchUp axes (Z up, front -Y): (x, y, z) -> (-x, z, y)
    sk = [{"name": m["name"], "v": [(-p[0], p[2], p[1]) for p in m["verts"]], "tris": m["tris"]} for m in meshes]
    low = min(p[2] for m in sk if pet_paint(m["name"], look) for p in m["v"])
    pieces = []
    for m in sk:
        paint = pet_paint(m["name"], look)
        if not paint:
            continue
        verts = place([(x, y, z - low) for x, y, z in m["v"]], scale, turn, 0.0, foot)
        pieces.append({"paint": paint, "rgb": paint.split("_")[1], "alpha": 255, "collide": None, "crease": 50,
                       "v": [c for p in verts for c in p], "f": [[list(t)] for t in m["tris"]]})
    return pieces


def nozzle():
    """Where the gun's nozzle mouth ends up in Store_AutoCatch (studs)."""
    return [c / INCH for c in place([GUN_NOZZLE], GUN["scale"], GUN["turn"], GUN["raise"], GUN["at"])[0]]


def gun_pieces():
    """The VacuumGun prop of the world source, placed by GUN, its tint paints made fixed colours."""
    if not GEAR.is_file():
        return []
    gun = json.loads(GEAR.read_text(encoding="utf-8"))["props"].get("VacuumGun")
    if not gun:
        return []
    pieces = []
    for piece in gun["pieces"]:
        paint = piece["paint"]
        if paint in GUN_PAINTS:
            paint = "Color_" + GUN_PAINTS[paint]
        v = piece["v"]
        studs = [(v[i] / INCH, v[i + 1] / INCH, v[i + 2] / INCH) for i in range(0, len(v), 3)]
        verts = place(studs, GUN["scale"], GUN["turn"], GUN["raise"], GUN["at"])
        pieces.append(dict(piece, paint=paint, rgb=paint.split("_")[1], v=[c for p in verts for c in p]))
    return pieces


def add_scenes(props):
    """The loaded store source + the pet scenes, with the vacuum gun added to Store_AutoCatch."""
    props = dict(props)
    for key, cast in PET_SCENES.items():
        pieces = []
        for pet_id, foot, scale, turn in cast:
            pieces += pet_pieces(pet_id, foot, scale, turn)
        props[key] = {"solid": False, "slot": [0, 0, 0], "paints": {}, "pieces": pieces}
    if "Store_AutoCatch" in props:
        gun = gun_pieces()
        if gun:
            props["Store_AutoCatch"] = dict(props["Store_AutoCatch"], pieces=props["Store_AutoCatch"]["pieces"] + gun)
    return props


if __name__ == "__main__":
    print("nozzle at", [round(c, 2) for c in nozzle()])
