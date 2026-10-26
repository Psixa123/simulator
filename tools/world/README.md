# World prop kit: SketchUp → Roblox mesh pack

The island props (trees, rocks, lamps, crystals, landmarks…) are modelled in **Trimble SketchUp**,
pulled out of SketchUp as polygons and packed into one Roblox mesh pack. Art direction and the
contract live in `docs/STYLE_GUIDE.md` ("Prop kit (SketchUp)"); this file is the how-to.

```
tools/world/sketchup/lib.py        helper library, sent to SketchUp in 4 chunks (session_state["L"])
tools/world/sketchup/<category>.py  prop build scripts (common.py = TreeRound, RockCluster, LampPost;
                                    gear.py = VacuumGun, VacuumPack, the player's gear for CharacterGear)
tools/world/sketchup/extract.py     sent to SketchUp: returns every Prop_* group as polygons
            │  (build_model result, saved by the agent harness to a tool-result file)
            ▼
tools/world/import_sketchup.py      → assets/source/world/<category>.json  (raw SketchUp polygons)
            ▼
tools/world/build_world_pack.py     → assets/models/StormWorldProps.glb
                                    → src/shared/Config/WorldPropsData.luau  (generated)
                                    → build/world/<PropId>.png, build/world/sheet.png  (previews)
```

Other files: `offline_sketchup.py` (runs the SketchUp scripts locally against a stand-in of the
SketchUp API, for `--check` and quick previews), `viewer.html` (three.js preview renderer),
`assets/source/world/StormWorldProps_prototypes.skp` (showcase model of the prototypes), and one
`StormWorldProps_<category>.skp` per category as last built in SketchUp (e.g. `StormWorldProps_gear.skp`).

**Gear props** (`gear.py`) are not map props: `src/server/Services/CharacterGear.luau` places them with
`WorldProps.Place` and welds them to the player's Tool Handle / tank Plate. Their origin is where they are held
(see `PROPS.md`, "gear"), so they are in `build_world_pack.py`'s `PIVOT_PROPS`. To see them on characters (the
real CharacterGear, four Climate Shift looks and tank fills):

```
python3 tools/preview_map.py --script tools/world/GearPreview.luau --out build/preview/gear \
    --shot "back target=0.5,3.8,0 az=25 el=20 dist=9" --shot "row target=12,3.5,0 az=25 el=15 dist=30 size=1400x600"
```

## The contract

* **Units and axes.** SketchUp: 12 in = 1 stud, Z up, the prop's **front faces −Y**, the origin at the
  **centre of its base**. Build scripts work in studs; `piece()` converts. The pack is in studs, Y up,
  front −Z: `rbx = (−x, z, y) / 12`.
* **Groups.** Every prop is a top-level group `Prop_<PropId>` made of **leaf groups named by paint**:
  `Primary`, `Secondary`, `Tertiary` (recoloured per biome when placed) or a fixed colour
  `Color_RRGGBB`, `Neon_RRGGBB` (glows), `Glass_RRGGBB` (see-through). Several leaf groups may share a
  paint (one per blob); the pack merges them into one mesh `<PropId>.<Paint>`. Nested groups and
  component instances are fine: a leaf takes the nearest paint name above it.
* **Defaults.** Tint paints get a SketchUp material `<PropId>_<Paint>` in the prop's default colour;
  that material's colour is what the pack records as the default (change it in SketchUp to change
  the default).
* **Look.** Inflated, rounded, chunky; no thin parts; at most **3,000 triangles per prop**. Sink
  ground-touching parts a little below z = 0 (roots, rock bases) so they look planted.
* **Metadata** (attribute dictionaries, set by `new_prop()` / `piece()`): `storm_prop` on the prop
  group (`id`, `category`, `solid`, `paint_*` defaults) and `storm_piece` on leaf groups (`crease`
  angle for smooth shading, `collide` override).

## Adding a prop

1. **Write the build script** in `tools/world/sketchup/<category>.py` (or add a chunk to an existing
   one). Each `# ===== chunk` block is one `build_model` call: keep it under ~200 lines, plain
   readable Python, no imports (`math` is pre-loaded), no `eval/exec/open/type/setattr`, no dunders,
   no classes, no `any()/all()`. Only `session_state` survives between calls.

   ```python
   # ===== chunk 1/1: Mushroom - a fat cartoon toadstool =====
   L = session_state["L"]
   CAT = "plains"


   def mushroom():
       # layout slot (x, y) in studs keeps the props apart in the SketchUp model
       p = L["new_prop"]("Mushroom", 38, 0, {"Primary": "FF6F8E", "Secondary": "FFF4E8"}, solid=False, category=CAT)
       L["piece"](p, "Secondary", L["lathe"]([(0.9, -0.2), (0.75, 1.2), (0.6, 2.4)], n=16))
       L["piece"](p, "Primary", L["blob"]((0, 0, 2.6), 2.0, squash=0.55, seed=3), collide=False)
       return p


   result = {"built": [L["report"](mushroom())]}
   ```

   Library (`L[...]`, all sizes in studs; meshes are `{"v": [[x, y, z]...], "f": [[i, j, k...]...]}`):

   | Function | Makes |
   | --- | --- |
   | `ball(c, r or [rx, ry, rz], seg, shape)` / `blob(c, r, squash, lump, seed, seg)` | spheres, soft lumpy puffs (canopies, clouds, bushes) |
   | `rock(c, planes, soft, seg, stretch, floor)` | faceted-but-soft boulders (convex planes, rounded by `soft`) |
   | `lathe(profile, n, center)` / `arc_profile(...)` | lofted solids of revolution; `(r, z, dx, dy)` rings bend them; r = 0 ends close in a point |
   | `puck(c, r, h, bevel, n)` / `cone(c, r0, r1, h, n, round_top)` | rounded discs and plinths, tapered cylinders and cones |
   | `rounded_box(c, [w, d, h], radius, seg)` | boxes with all edges rounded |
   | `tube(path, r or [r...], n, caps)` | round tubes along a path (arms, branches, pipes) with round/flat/open caps |
   | `extrude(poly, depth, bevel)` + `star_poly`, `bolt_poly`, `round_poly`, `offset_poly` | 2D shapes (stars, lightning bolts, signs) as bevelled slabs facing −Y |
   | `merge`, `move`, `scale`, `rotate`, `warp(m, fn)`, `flip`, `orient` | mesh edits (`warp` = any per-vertex function: bends, tapers, root bumps) |
   | `rng(seed)`, `lumps(seed, freq)`, `smoothstep`, `v_*` | deterministic noise and vector helpers |
   | `new_prop(id, x, y, paints, solid, category)` | (re)starts the `Prop_<id>` group at a layout slot |
   | `piece(prop, paint, mesh, crease=40, collide=None)` | adds a leaf group; edges under `crease`° are soft + smooth (in SketchUp and in the pack) |
   | `report(prop)` | size / triangle summary for the `build_model` result |

2. **Preview without SketchUp** (optional, fast): `python3 tools/world/offline_sketchup.py <category>`
   then `python3 tools/world/build_world_pack.py --source build/world/offline` and look at
   `build/world/offline/*.png`. Iterate on the script until it looks right.
3. **Build in SketchUp** with the Trimble SketchUp MCP. Before the first `build_model` of a session
   call `list_skills` and read every baseline skill. Then: `build_model` with `clean: true` and lib.py
   chunk 1, then chunks 2–4, then the category script's chunks (one call each). Check each result:
   `warnings` must be empty (a warning means SketchUp refused some faces) and `size` must be sane.
   Rebuilding a prop replaces its group, so you can iterate on one chunk.
4. **Extract**: send `tools/world/sketchup/extract.py` as one `build_model` call (set `ONLY = [...]`
   to extract some props). ~1,000 faces ≈ 60 KB of result; the harness saves large results to a
   tool-result file and names it in the error message. Do not read it into context.
5. **Import**: `python3 tools/world/import_sketchup.py <tool-result file>` writes/updates
   `assets/source/world/<category>.json` (props in the extraction replace props of the same id; add
   `--replace` to rewrite the whole category file). A small inline result can be saved to a `.json`
   file and imported the same way.
6. **Pack and render**: `python3 tools/world/build_world_pack.py` (needs `npm install` in
   `tools/world` once for three.js, and Chrome/Chromium for renders; `--no-render` skips them,
   `--views` adds front/side/back/top, `--props A,B` renders some). **Look at every render** in
   `build/world/` and go back to step 1 until the prop reads as a polished chunky cartoon prop.
7. **Check**: `python3 tools/world/build_world_pack.py --check` (sandbox safety of every script, a dry
   run of all build scripts, the contract for every source prop, and that the GLB and Luau module
   are up to date). Commit the script, the source JSON, the GLB and the Luau module together.
8. Optionally `save_model` to refresh `assets/source/world/StormWorldProps_prototypes.skp` (download
   the returned URL with `curl -L`).

## The pack

`assets/models/StormWorldProps.glb`: scene root `WorldProps` → one node per prop `<PropId>` (laid out
like the SketchUp slots) → one node + mesh per paint `<PropId>.<Paint>` plus a 1-stud cube
`<PropId>.Root` centred on the prop's origin (scale and position reference; hide it in game). Normals
are smooth within each piece's crease angle. Node extras carry `paint`, `kind`, `rgb` and `collide`;
materials carry the paint colour (Neon → emissive, Glass → alpha 0.45).

`src/shared/Config/WorldPropsData.luau` (generated, do not edit) lists per prop: `Category`, `Size`,
`Center`, `Footprint` (radius around the origin), `Collide` (the script's `solid` flag), `Tris`,
`Paints` (default tint colours) and `Pieces` (`Name`, `Paint`, `Kind`, `Color`, `Center`, `Size`,
`Collide`, `Tris`). A piece's `Collide` is false for canopies, glass and neon even on solid props.

## Previews

`viewer.html` renders one prop of a pack with three.js: soft sky lighting, SmoothPlastic-like
shading, a 3 px Ink (`#233066`) outline, a soft contact shadow, glowing Neon, and an invisible ground
at y = 0 that hides buried parts. Serve the repo root (`python3 -m http.server`) and open
`/tools/world/viewer.html?prop=TreeRound`; options: `view=hero|front|side|back|top`, `size=512`,
`paints=Primary:FF7AB0,Secondary:FFD1E6` (biome recolour), `shade=standard|toon`, `outline=0`,
`shadow=0`, `ground=0`, `bg=1`, `glb=<url>`.
