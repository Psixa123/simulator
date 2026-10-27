# Stormling pet meshes

The 47 pets ("Stormlings", 9 of them Secret pets) as polished cartoon meshes: smooth chibi bodies, big glossy eyes with
highlights, blush, little mouths, layered wings, curled tails, inner ears, toe beans, crowns, halos...
Every pet keeps its look from `src/shared/Config/Pets.luau` (body type, features, colours, effect).

| File | What it is |
| --- | --- |
| `pet_geometry.py` | **Sandbox-safe** pure-Python geometry library + all 47 pet designs. |
| `build_pets.py` | Exports the Roblox mesh pack and renders previews (normal Python). |
| `viewer.html` | three.js preview page used for the renders (works in any browser too). |
| `../../assets/models/StormlingPets.glb` | Mesh pack: `PetMeshes -> <PetId> -> <PetId>.<Role>` nodes. |
| `../../assets/models/StormlingPets.obj/.mtl` | Same pack as a flat list of `<PetId>.<Role>` objects. |
| `../../build/pets/` | Preview renders (`<PetId>.png`, `sheet.png`, ...); not committed. |

## Regenerating

```sh
cd tools/pets && npm install && cd ../..      # once: three.js 0.169.0 for the previews
python tools/pets/build_pets.py               # validate + export the pack + hero renders + sheet.png
python tools/pets/build_pets.py --check       # validate only
python tools/pets/build_pets.py --no-render   # export only (no browser needed)
python tools/pets/build_pets.py --views --tiers --anim 0.1   # front/side/back/top, Golden/Rainbow, posed
python tools/pets/build_pets.py --pets Puffling,VoltBat       # render a few pets only
```

Needs Python 3.9+ with numpy and Pillow. Renders use headless Chrome/Chromium (`CHROME_PATH`, a
Playwright headless shell, or a system Chrome) with three.js. The exporter writes glTF/OBJ itself
(no trimesh/pygltflib), and the GLB passes the Khronos glTF validator with no errors or warnings.

`--check` (and every build) verifies:

* `pet_geometry.py` is sandbox-safe: an AST scan (no imports, no dunders, no eval/exec/open/type/setattr,
  no classes, only allowed builtins) **and** a real run with only those builtins available,
* the pet table matches `Pets.luau` (ids, names, rarities, body, colours, eye colour, features, effect),
* every pet follows the contract below (role names, Root/Pivot markers, budgets, outward winding,
  spinning parts centred on their spin axis).

## Editing the designs

Everything lives in `pet_geometry.py`:

* `PETS` mirrors `Pets.luau` (the build fails if they disagree, so update both).
* `DESIGN[petId]` picks feature styles and signature details: `ears` (cat/fox/bat/pup),
  `bunny` (upright/flop), `horns` (devil/dragon/ox/ram/ice/beetle), `wings` (feather/bat/insect),
  `tail` (pup/lava/fox/puff/dragon/bird), `mouth` (smile/cat/fang/open/None), `drop`, `cloud`, and details
  such as `feet`, `cheek_tufts`, `underpuffs`, `belly_accent`, `star_mark`, `moon_mark`, `ripples`...
* Body shapes are star-shaped surfaces `S(direction) -> point` (`egg_surface`, `cloud_surface` = smooth
  union of puffs, `drop_surface`, `cube_surface`, `gem_surface`). Faces and markings are "decals":
  thin domes projected onto the body surface (`body_patch` + `decal`).
* Primitives: `quad_sphere`, `uv_sphere`, `ellipsoid`, `lathe`, `tube` / `sweep` (rotation-minimising
  frames, elliptical sections, tapered radii), `capsule`, `cone`, `torus`, `torus_arc`, `rounded_box`,
  `leaf`, `extrude` (bevelled 2D shapes: `star_poly`, `bolt_poly`, `heart_poly`, `crescent_poly`), and
  transform helpers `xf_*`, `transform_mesh`, `mirror_x`.

### Sandbox rules (the file is pasted into the Trimble SketchUp MCP sandbox)

No `import` lines (`math` is pre-loaded), no `eval`/`exec`/`open`/`type()`/`setattr`, no dunder
attributes, no classes, and only these builtins: `range len min max abs int float str list dict tuple
enumerate isinstance sorted sum`. `build_pets.py --check` enforces this.

In SketchUp: paste the file, then use `sketchup_layout()` - it returns every mesh already converted
to SketchUp axes (Z up, the pet's front facing -Y, inches; 1 stud = 12 in by default) on the same grid
as the GLB/OBJ, with its preview colour, e.g. one group per `entry["name"]`. Root/Pivot markers have
`visible = False`.

## Mesh pack contract

* **Units/axes:** Roblox studs, Y up, the pet's front faces -Z, origin = pet centre (same origin as the
  procedural model's Root part). Body "radius" is about 1 stud at unit scale; `PetModels.Scale` still
  applies the rarity/tier scale. In the files the pets sit on a grid (8 columns, 6 studs apart), so
  always measure from each pet's `Root`.
* **Roles** (mesh names; the game colours by role, so file material colours only matter for previews):
  * `Body` -> `look.Color`, tintable (`Tint = "Body"`); `Accent` -> `look.Accent`, tintable (`Tint = "Accent"`)
  * `Eye` -> `look.EyeColor` (Neon) or near-black; `Shine` -> white Neon highlights;
    `Blush` -> pink, ~0.35 transparency; `Mouth` -> dark ink
  * fixed colours: `Color_RRGGBB` (SmoothPlastic), `Neon_RRGGBB` (Neon), `Ice_RRGGBB` (Ice)
  * animated pieces end in `@WingL`, `@WingR`, `@Wag`, `@SpinY` or `@SpinZ` (the PetController
    animations). Hinged ones (`WingL`, `WingR`, `Wag`) have a `Pivot@<Anim>` marker: a 0.1-stud cube
    centred on the hinge. `SpinY`/`SpinZ` pieces spin around the pet origin and are centred on that axis.
  * `Root`: a 0.2-stud cube centred on the origin - the scale and origin reference
    (`factor = 0.2 / Root.Size.X`, origin = Root position). `Root` and `Pivot@*` are invisible in game.
* **GLB:** node hierarchy `PetMeshes -> <PetId> -> <PetId>.<Role>`; each piece's node and mesh are both named
  `<PetId>.<Role>` (so an importer that flattens the per-pet nodes or names parts after meshes still gives
  usable names), and its node has `extras` with the role, preview rgb, material, transparency and tint.
  **OBJ:** flat objects named `<PetId>.<Role>`. In Roblox the pack lives in `ReplicatedStorage.PetMeshes`
  (imported in Studio, or uploaded with `tools/roblox/upload_pets.py` and inserted by `PetMeshService`);
  pieces may be named `<PetId>.<Role>` at any depth, or `<Role>` inside a model named after the pet.
* **Topology:** triangles wound counter-clockwise seen from outside; shared vertices are smooth-shaded,
  duplicated vertices give hard edges (crystals, gems, markers). Smooth vertex normals are exported.

## Budgets

* At most **4,000 triangles per pet** (`TRI_BUDGET`): `build_pet` lowers the tessellation level
  until the pet fits. Currently every pet is 2.7k-4.0k triangles.
* **Secret pets: at most 10,000 triangles** (`MAX_TRIS_SECRET` in `build_pets.py`, `SECRET_BUDGET` in
  `blender/build_secret_pets.py`). They are the premium, one-in-millions pets, so they get a 2.5x budget for their
  Blender models. Every role mesh stays far below Roblox's 20,000-triangle MeshPart limit (the biggest is ~2.6k),
  `PetModels` accepts up to 150 pieces per pet, and Roblox's automatic MeshPart LOD keeps far-away pets cheap.
  The pack is about 223k triangles for all 47 pets.
* At most **12 visible meshes per pet** (Root/Pivot markers not counted): static pieces with the same
  role are merged (both eyes are one `Eye` mesh, all shines one `Shine` mesh, ...).

## Secret pets

The nine Secret pets (rarity `Secret`, `Pets.Eggs[*].Secrets`: Eye of the Storm, Thunderclap Kirin, Sandstorm
Sphinx, Blizzard Monarch, Tempest Phoenix, Pyroclasm Dragon, Void Leviathan, Nova Seraph, Hypercane) are
**modelled in Blender** (next section); the pack uses those models. Their older `pet_geometry.py` versions
(below) are still built and checked, are what the SketchUp model and `export_dae.py` show, and are used with
`build_pets.py --sketchup-secrets`.

### Blender models (`tools/pets/blender/`)

| File | What it is |
| --- | --- |
| `blender/kit.py` | Headless Blender helpers: quad spheres, sweeps, lathes, metaball/voxel-remesh unions (`blob_union`), Skin-modifier trees, bevelled curves, Shrinkwrap "decals", modifier baking, the `Pet` assembler (roles, budget fitting, Root/Pivot markers, materials) and the glTF export. |
| `blender/features.py` | Reusable chibi parts: the face (domed neon eyes, ink pupils/lids/lashes, highlights, blush, mouths), feathered / membrane / fin / butterfly wings, halos, crowns, gems, bolts, stars, plated bellies. |
| `blender/secret_pets.py` | One readable build function per Secret pet (`BUILDERS`). |
| `blender/build_secret_pets.py` | Builds, exports and renders them (run with Blender's Python module). |
| `blender/render.py` | Cycles (CPU) renders: transparent background, key/fill/rim/bounce area lights, inverted-hull ink outline. |
| `blender/sheets.py` | Contact sheets: `build/pets/blender_secret_sheet.png`, `build/pets/secret_old_vs_blender.png`. |
| `../../assets/source/pets/blender/<PetId>.glb` | The exported Secret pets (a `<PetId>` node with `<PetId>.<Role>` meshes), merged into the pack by `build_pets.py`. |

```sh
python3 -m venv /tmp/blender-venv && /tmp/blender-venv/bin/pip install bpy     # once: bpy 5.x needs Python 3.13
/tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py          # all 9: export + Cycles renders
/tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py --pets Hypercane --views hero --no-export
/tmp/blender-venv/bin/python tools/pets/blender/build_secret_pets.py --blend   # also save <PetId>.blend sources
python tools/pets/build_pets.py                                                # merge into StormlingPets.glb + checks
python tools/pets/blender/sheets.py --compare                                  # contact sheets
```

How a pet is made: organic shapes start as clean quad topology (a subdivided cube pushed onto a sphere and
reshaped into the chibi "Round"/"Bean" bodies) or as unions of puffs (voxel remesh + smoothing for clouds,
collars, the kirin's cloud); limbs, tails, feathers, flames and fins are swept elliptical sections smoothed with a
Subdivision Surface; antlers, horns, mane lines and stripes are bevelled curves; eyes, pupils, blush, belly
patches and spots are discs Shrinkwrap-projected onto the body (domed, rim sunk into the surface); wings are
fans of plump feathers, Solidified membranes between finger bones, webbed fins or bevelled butterfly lobes.
`Pet.add(role, ...)` files every part under its pack role; `Pet.finish` collapse-decimates the parts to the
budget (a water-filling share by surface area; face and sticker parts are never decimated, parts on the centre
line are decimated symmetrically), merges each role into one triangulated mesh, adds the `Root` cube and the
`Pivot@<Anim>` hinges, and `export_pet` writes the GLB (turned 180 degrees about Z: Blender's -Y front becomes the
pack's -Z front; the pet's left (+X in Blender) is the pack's -X, where `WingL` lives). Modelling space is
studs, Z up, origin = pet centre. `build_pets.py` reads these GLBs (its own small glTF reader), applies the same
contract checks as for every pet (role names, Root/Pivot cubes, winding, degenerate triangles, spin pieces centred
on their axis, 10k triangles / 12 visible meshes), and writes them into the pack after the 38 older pets, so
those stay byte-identical.

### The older `pet_geometry.py` versions

They are built from the same parts as the other pets plus a premium kit that only their `DESIGN` entries switch on (so every older pet stays
byte-identical): `orbit` (tilted rings with stars, bolts, shards, pyramids, fireballs or moons that spin with
`SpinY`), `cyclone` (hurricane spiral arms), `spiral_mark` / `snowflake_mark` (glowing forehead emblems), `mane`
(a crest of lightning bolts), `nemes` + `uraeus` (sphinx headdress over a `wide_patch` hood, cobra and beard),
`gills`, `dorsal`, `glow_spots`, `crown_style` (`ice` crystals or `magma` spikes, seated with the exact
`surface_height`), `horns: antler`, `wings: seraph | fin`, `tail: kirin | phoenix`, `feet: hoof`. These run after
the features (`LATE_DETAILS`). Within the same 4,000-triangle budget a secret pet keeps a finer body and face
(`body_q`) and walks a finer quality ladder (`SECRET_LADDER`) so the extra parts don't coarsen the body. They
are appended at the end of `PET_IDS` (the pack grid), so the older pets keep their grid places.

The SketchUp model of the secret pets is `assets/source/world/SecretStormlings.skp` (one `SecretStormlings`
group, a group per pet, a sub-group per role mesh). It was built in the Trimble SketchUp MCP sandbox from
readable chunks of this file:

```sh
python3 tools/pets/make_sketchup_steps.py --max-lines 190 --out build/sketchup_secret --extract \
    --pets EyeOfTheStorm,ThunderKirin,SandstormSphinx,BlizzardMonarch,TempestPhoenix,PyroclasmDragon,VoidLeviathan,NovaSeraph,Hypercane
```

`chunk1.py` (`clean: true`) ... `chunk17.py` (each under 190 lines, normal indentation), then a checksum of
`sketchup_layout()` for those pets (it matched the offline build exactly: 35,037 triangles in 100 meshes), the
build steps, and `step_extract.py`, which reads every role group back out of SketchUp (faces, unique vertices,
a vertex checksum, bounds) for comparison with `extract_expected.json`. In the last build 97 of the 100 role
meshes matched exactly; the 3 flame meshes (Tempest Phoenix's crest, Thunderclap Kirin's tail tuft) each came
back without their zero-area needle tips (120 sliver triangles thinner than SketchUp's 0.001" tolerance, which
draw nothing in Roblox either).

## SketchUp model (`assets/models/StormlingPets.dae`)

`export_dae.py` writes every pet from `sketchup_layout()` into a COLLADA file that SketchUp opens
directly (**File → Import…**, file type COLLADA `.dae`; inches, Z up). It has one `Stormlings` node with a
node per pet (named by pet id) and one per role mesh, the preview colours as materials and smooth
normals, so it matches the Roblox pack exactly. Save it as `.skp` from SketchUp if you want one.

```powershell
python tools/pets/export_dae.py                 # writes assets/models/StormlingPets.dae
```

### Building it inside the SketchUp MCP sandbox (optional)

The same model can also be built inside Trimble SketchUp's Python sandbox (the SketchUp MCP
`build_model` tool). That sandbox forbids imports and forgets everything between calls except
`session_state`, so the library is prepared for it first:

```powershell
python tools/pets/make_sketchup_steps.py        # writes build/sketchup/chunk*.py, step_verify.py, step_build*.py
```

Run `chunk1.py` (with `clean: true`) … `chunk4.py`, then `step_verify.py` (it must print the checksum the
script printed), then every `step_build*.py`. That creates one `Stormlings` group with a group per pet
(named by pet id) and a sub-group per role mesh, using solid colours and smoothed edges.

The SketchUp model is for viewing and editing the designs. Roblox Studio can't import `.skp` or `.dae`,
so the game uses the `.glb`/`.obj` pack; if you change a design, change `pet_geometry.py` and rebuild
all of them.
