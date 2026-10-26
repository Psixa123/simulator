"""Badge models made from the game's other models (tools/icons/README.md, "Badge icons").

The badge medals and the trophy / egg shell are SketchUp models (tools/icons/sketchup_badge_icons.py ->
assets/source/world/badge_icons.json). render_icons.py --set badges calls add_scenes() on that source before it
writes the GLB, which adds:

  Badge_Zone_<Zone>     a zone medal: a face-less medal (Badge_Frame_<Colour>) holding the zone emblem's enamel
                        face and scene (assets/source/world/zone_emblems.json, its gold coin and ring left out)
  Badge_HatchScene      the cracked egg (Badge_HatchEgg) with a Puffling in it wearing the egg's top (Badge_HatchCap)
  Badge_PetLegendary    the Breeze King, a Legendary pet (tools/pets/pet_geometry.py)
  Badge_PetGolden       a Golden Thunder Pup (the game's golden tier colours, src/shared/Models/PetModels.luau)
  Badge_PetRainbow      a Rainbow Zappy (the rainbow tier's pastel hue per tinted part) under the Rainbow icon's arc
  Badge_RareWeather     the Rainbow UI icon (rainbow on clouds) with the Star icon (assets/source/world/icons.json)

Everything is in the icon source layout (SketchUp inches, Z up, front -Y, pieces named by paint), so it is shaded,
outlined and lit like the SketchUp models. The other badge heroes are existing renders (assets/source/badges3d.html).
"""

import colorsys
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD_SOURCE = ROOT / "assets" / "source" / "world"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import store_scenes  # noqa: E402  (pets, placing helpers)

INCH = store_scenes.INCH
pets = store_scenes.pets

# Zone medals: zone emblem key -> the medal colour it sits in (sketchup_badge_icons.py, chunk 2)
ZONE_FRAMES = {"Hub": "Teal", "Thunder": "Purple", "Dunes": "Sand", "Frost": "Ice", "Volcano": "Lava", "Sky": "Cosmic"}
# The first pieces of every zone emblem are its medal: [gold coin, enamel face, gold ring]; the coin and the
# ring are left out (the badge medal replaces them), the face and everything after it is the zone's scene
EMBLEM_DROP = (0, 2)

# PetModels.luau: the golden tier's colours, the rainbow tier's hue step and saturations
GOLD, GOLD_ACCENT = (255, 202, 58), (255, 160, 35)
RAINBOW_HUE_STEP = 0.11
RAINBOW_SATURATION = {"Body": 0.42, "Accent": 0.62}
# Badge_HatchScene: the egg is scaled up so the pet fits in it; PET_SINK = share of the pet below the crack
EGG_SCALE, PET_SCALE, PET_SINK = 1.45, 1.3, 0.2


def load(name):
    path = WORLD_SOURCE / name
    return json.loads(path.read_text(encoding="utf-8"))["props"] if path.is_file() else {}


def points(piece):
    v = piece["v"]
    return [(v[i], v[i + 1], v[i + 2]) for i in range(0, len(v), 3)]


def with_points(piece, pts, paint=None):
    out = dict(piece, v=[round(c, 2) for p in pts for c in p])
    if paint:
        out.update(paint=paint, rgb=paint.split("_")[1])
    return out


def transform(pieces, scale=1.0, turn=0.0, tilt=0.0, at=(0.0, 0.0, 0.0), about=(0.0, 0.0, 0.0)):
    """Pieces (inches) scaled and turned about `about` (turn: about Z, tilt: about Y, +X goes down), then moved
    so `about` lands on `at` (inches)."""
    ct, st = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    cl, sl = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    out = []
    for piece in pieces:
        pts = []
        for x, y, z in points(piece):
            x, y, z = (x - about[0]) * scale, (y - about[1]) * scale, (z - about[2]) * scale
            x, y = x * ct - y * st, x * st + y * ct
            x, z = x * cl - z * sl, x * sl + z * cl
            pts.append((x + at[0], y + at[1], z + at[2]))
        out.append(with_points(piece, pts))
    return out


def bounds(pieces):
    pts = [p for piece in pieces for p in points(piece)]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return lo, hi


def prop(pieces):
    return {"solid": False, "slot": [0, 0, 0], "paints": {}, "pieces": pieces}


def tier_pet(pet_id, tier="Normal", scale=1.0, turn=0.0, foot=(0.0, 0.0, 0.0)):
    """A pet as icon pieces (store_scenes.pet_pieces) in a tier's colours: Golden = the golden body and accent,
    Rainbow = a pastel hue per tinted part, stepping like PetModels.colorFor."""
    saved = pets.PETS[pet_id]
    look = dict(saved)
    if tier == "Golden":
        look.update(Color=GOLD, Accent=GOLD_ACCENT)
    pets.PETS[pet_id] = look
    try:
        pieces = store_scenes.pet_pieces(pet_id, foot, scale, turn)
    finally:
        pets.PETS[pet_id] = saved
    if tier != "Rainbow":
        return pieces
    # rainbow: re-paint the tinted parts (the body and accent colours of the plain pet) one hue each
    body = "Color_" + store_scenes.hexrgb(look["Color"])
    accent = "Color_" + store_scenes.hexrgb(look["Accent"])
    out, index = [], 0
    for piece in pieces:
        tint = "Body" if piece["paint"] == body else "Accent" if piece["paint"] == accent else None
        if tint:
            index += 1
            hue = (index * RAINBOW_HUE_STEP + (0.5 if tint == "Accent" else 0.0)) % 1.0
            rgb = [c * 255 for c in colorsys.hsv_to_rgb(hue, RAINBOW_SATURATION[tint], 1.0)]
            piece = with_points(piece, points(piece), "Color_" + store_scenes.hexrgb(rgb))
        out.append(piece)
    return out


def zone_medal(props, emblems, zone):
    frame = props.get("Badge_Frame_" + ZONE_FRAMES[zone])
    emblem = emblems.get("Zone_" + zone)
    if not frame or not emblem:
        return None
    scene = [piece for i, piece in enumerate(emblem["pieces"]) if i not in EMBLEM_DROP]
    return prop(frame["pieces"] + scene)


def hatch_scene(props):
    egg, cap = props.get("Badge_HatchEgg"), props.get("Badge_HatchCap")
    if not egg or not cap:
        return None
    shell = transform(egg["pieces"], scale=EGG_SCALE)
    lo, hi = bounds(shell)
    rim = 3.21 * INCH * EGG_SCALE  # the crack line's mean height (sketchup_badge_icons.py: egg_at(CUT))
    pet = tier_pet("Puffling", scale=PET_SCALE, foot=(0.0, 0.0, 0.0))
    plo, phi = bounds(pet)
    pet = transform(pet, at=(0.0, 0.0, rim - PET_SINK * (phi[2] - plo[2])))
    plo, phi = bounds(pet)
    clo, chi = bounds(cap["pieces"])
    # the egg's top sits on the pet's head like a hat, tipped to the right
    hat = transform(cap["pieces"], scale=EGG_SCALE * 0.82, tilt=-18, about=(0.0, 0.0, clo[2]),
                    at=(0.3 * INCH, (plo[1] + phi[1]) / 2, phi[2] - 0.75 * INCH))
    return prop(shell + pet + hat)


def rainbow_pet(icons):
    """A rainbow-tier pet in front of the Rainbow icon's arc."""
    rainbow = icons.get("Rainbow")
    pet = tier_pet("Zappy", "Rainbow", scale=1.55)
    if not rainbow:
        return prop(pet)
    lo, hi = bounds(rainbow["pieces"])
    plo, phi = bounds(pet)
    arc = transform(rainbow["pieces"], scale=1.3, about=((lo[0] + hi[0]) / 2, hi[1], lo[2]),
                    at=(0.0, phi[1] + 0.8 * INCH, plo[2] + 0.2 * INCH))
    return prop(arc + pet)


def rare_weather(icons):
    rainbow, star = icons.get("Rainbow"), icons.get("Star")
    if not rainbow or not star:
        return None
    lo, hi = bounds(rainbow["pieces"])
    slo, shi = bounds(star["pieces"])
    s = 0.48
    at = (hi[0] - 0.1 * INCH, lo[1] - 0.6 * INCH, hi[2] - 0.25 * INCH)
    sparkle = transform(star["pieces"], scale=s, turn=-8, about=((slo[0] + shi[0]) / 2, (slo[1] + shi[1]) / 2,
                                                                 (slo[2] + shi[2]) / 2), at=at)
    return prop(rainbow["pieces"] + sparkle)


def add_scenes(props):
    """The loaded badge source + the scenes above."""
    props = dict(props)
    emblems = load("zone_emblems.json")
    icons = load("icons.json")
    for zone in ZONE_FRAMES:
        made = zone_medal(props, emblems, zone)
        if made:
            props["Badge_Zone_" + zone] = made
    made = hatch_scene(props)
    if made:
        props["Badge_HatchScene"] = made
    props["Badge_PetLegendary"] = prop(tier_pet("BreezeKing", scale=2.4))
    props["Badge_PetGolden"] = prop(tier_pet("ThunderPup", "Golden", scale=2.4))
    props["Badge_PetRainbow"] = rainbow_pet(icons)
    made = rare_weather(icons)
    if made:
        props["Badge_RareWeather"] = made
    return props
