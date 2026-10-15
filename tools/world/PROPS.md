# Storm World prop catalog

The contract between the SketchUp modelling scripts (`tools/world/sketchup/<category>.py`) and the
map builder (`src/server/Services/MapService.luau`, which places props with `WorldProps.Place`).
Ids are final: MapService refers to them by name, and falls back to its own part-built version while a
prop is missing from the pack. Sizes are approximate (studs: width × height × depth) and paints follow
`docs/STYLE_GUIDE.md` ("Prop kit"): `Primary`/`Secondary`/`Tertiary` are recoloured per biome by
MapService, `Color_`/`Neon_`/`Glass_` are fixed. **Solid** props get `collide = True` on their
main pieces (players bump into them); everything else is walk-through decoration.

Look for every prop: chunky, inflated, rounded, toy-like, readable from far away; slightly
exaggerated proportions (big tops, short thick stems); no thin or spiky parts; ≤ 3,000 triangles.
Front faces −Y in SketchUp (−Z in Roblox); origin at the centre of the base, base at z = 0 (a little
may sink below 0 so it sits in the ground).

## nature (`sketchup/common.py` + `sketchup/nature.py`)
| Id | Size | Paints | Notes |
| --- | --- | --- | --- |
| TreeRound | 12 × 14 × 10 | trunk `Color_A8724C`, Primary, Secondary | done (prototype) |
| TreeTall | 9 × 18 × 9 | trunk `Color_A8724C`, Primary, Secondary | cotton-candy tree: slim curved trunk, 2–3 stacked round tiers |
| TreePine | 9 × 17 × 9 | trunk `Color_8A5A3C`, Primary, Tertiary | 3 stacked soft cones; Tertiary = snow caps (white in Frostpeak, same as Primary elsewhere) |
| TreePalm | 10 × 16 × 10 | trunk `Color_C8925A`, Primary | curved segmented trunk, 5–6 fat leaves, 2–3 coconuts `Color_7A4E2E` |
| BushRound | 6 × 4 × 5 | Primary, Secondary | 3–4 blobs |
| FlowerPatch | 6 × 2 × 6 | mound Primary, petals Secondary + Tertiary, centres `Color_FFE15A` | 5–7 flowers on a grass mound |
| Mushroom | 5 × 6 × 5 | stem `Color_FFF4E0`, cap Primary, spots `Color_FFFFFF` | one big cartoon mushroom + a small one |
| RockCluster | 9 × 4 × 8 | Primary, Secondary | done (prototype) solid |
| RockTall | 6 × 10 × 6 | Primary, Secondary | tall rounded boulder stack, solid |
| CrystalCluster | 6 × 8 × 6 | Primary, Secondary, tips `Neon_FFFFFF`? (small) | 4–5 chunky faceted crystals on a rock base |
| Fence | 10 × 4 × 1 | Primary (posts/pickets), Secondary (rails) | one 10-stud picket section with round posts at both ends |
| GrassTuft | 2 × 1.5 × 2 | Primary | small clump of 5–7 fat blades |

## landmarks (`sketchup/landmarks.py`)
| Id | Size | Paints | Notes |
| --- | --- | --- | --- |
| Windmill | 14 × 30 × 14 | body `Color_FFF4E0`, roof Primary, trim Secondary | tower without blades, hub at front, 20 studs up |
| WindmillBlades | 22 × 22 × 2 | Primary, Secondary | 4 blades around a hub, origin at the hub centre (MapService spins it) |
| HayBale | 5 × 4 × 4 | `Color_F2C94C`, bands `Color_C8963E` | round bale |
| TeslaTower | 8 × 24 × 8 | Primary (metal), Secondary (coils), `Neon_9EE8FF` orb | tapered tower, ring coils, glowing orb on top; solid |
| StormCloud | 14 × 8 × 10 | cloud Primary, Secondary, bolt `Neon_FFE15A` | dark puffy cloud with a fat bolt hanging below; origin at the bolt's tip |
| LightningRod | 3 × 10 × 3 | Primary, tip `Neon_FFE15A` | |
| Cactus | 5 × 9 × 4 | Primary, Secondary (stripes/flower) | saguaro with 2 arms, a flower on top |
| Pyramid | 30 × 22 × 30 | Primary, Secondary (steps/trim), cap `Color_FFE15A` | stepped, rounded edges; solid |
| SandArch | 22 × 16 × 8 | Primary, Secondary | wind-worn rock arch; solid legs |
| OasisPool | 16 × 2 × 12 | rim Primary, water `Glass_5CC8FF` | kidney-shaped pool with a rocky rim |
| Igloo | 14 × 8 × 14 | `Color_EAF6FF`, block lines Secondary | dome with tunnel entrance; solid |
| Snowman | 5 × 8 × 5 | `Color_FFFFFF`, scarf Primary, nose `Color_FF9F1C`, eyes/buttons `Color_233066` | |
| IceCastleTower | 12 × 32 × 12 | Primary (ice), Secondary, windows `Neon_BDF4FF` | round tower, crenellations, cone roof; solid |
| Volcano | 60 × 40 × 60 | Primary (rock), Secondary, lava `Neon_FF7A2E` | big cone with a glowing crater and 2–3 lava streaks; solid |
| LavaSpire | 6 × 14 × 6 | Primary, glow cracks `Neon_FF7A2E` | |
| SteamVent | 6 × 2 × 6 | Primary, inner `Neon_FFB15C` | rocky ring; MapService adds the steam particles |
| FloatingIsland | 16 × 10 × 14 | grass Primary, rock Secondary, Tertiary | flat grassy top, rocky cone underneath |
| StarLamp | 3 × 10 × 3 | post Primary, star `Neon_FFE15A` | |
| CloudBank | 24 × 10 × 14 | `Color_FFFFFF`, shading Secondary | big cluster of puffs |
| CitadelTower | 14 × 34 × 14 | Primary, Secondary, Tertiary (roof), windows `Neon_FFF3B0` | floating-sky castle tower; solid |
| AuroraArch | 26 × 18 × 4 | `Glass_9EF0D8`, `Glass_B58CFF` | ribbon arch of 2–3 translucent bands |

## structures (`sketchup/structures.py`)
Hub and zone buildings. MapService keeps the gameplay parts (prompt hosts, sell pad trigger, signs,
SurfaceGuis) and places these around them, so leave the noted openings and flat sign areas.
| Id | Size | Paints | Notes |
| --- | --- | --- | --- |
| WeatherTower | 22 × 60 × 22 | body `Color_EEF0FF`, Primary (roof/trim), Secondary, `Neon_9EE8FF` lights | the hub's landmark: tapered tower, balconies, radar dish, wind cups, a weather vane on top; solid |
| StationBooth | 20 × 16 × 14 | body `Color_EEF0FF`, Primary (roof/awning), Secondary (trim), windows `Neon_FFF3B0` | generic open-front booth for Upgrades / Shop / Rewards; a flat sign panel above the opening (front, 12 × 3 studs, centre 13 studs up); recoloured per station; solid back/sides |
| WeatherLab | 22 × 20 × 18 | body `Color_EEF0FF`, Primary, Secondary, dome `Glass_9EE8FF` | building with an observatory dome and a radar dish; open front; solid |
| RebirthShrine | 18 × 20 × 18 | Primary (stone), Secondary, swirl `Neon_B58CFF` | round platform, pillars, a glowing swirl portal ring |
| ForecastTower | 14 × 22 × 6 | body `Color_EEF0FF`, Primary, Secondary | screen tower: a flat front screen area 12 × 8 studs centred 14 studs up (MapService adds the SurfaceGui) |
| EggIncubator | 12 × 12 × 12 | base Primary, Secondary, dome `Glass_DFF6FF` | round pedestal with a glass dome (the egg model sits inside) |
| SellMachine | 10 × 12 × 8 | body Primary, Secondary, jar `Glass_54E0FF`, `Neon_FFE15A` bolt | a fat storm-jar machine with a coin chute; stands beside the sell pad; solid |
| ZoneGate | 40 × 30 × 8 | Primary (pillars), Secondary (arch), Tertiary (trim) | big rounded arch over the 16-stud path; a flat sign area on the arch front 24 × 5 studs centred 24 studs up; solid pillars |
| CliffSegment | 40 × 30 × 18 | lip Primary (grass/snow/sand), rock Secondary, Tertiary bands | one chunk of island edge: flat top at z = 0 along the playable side, layered rock below to z = −30, front (−Y) = the outside |
| CloudPuff | 30 × 12 × 20 | `Color_FFFFFF`, Secondary | a big cloud for the cloud sea under and around the islands |
| Bench | 6 × 3 × 2 | Primary (seat), Secondary (legs) | |
| SignPost | 6 × 8 × 1 | Primary (post), board `Color_FFFFFF`, Secondary trim | a sign board on two round posts; flat board front 5 × 2.5 studs centred 6 studs up |
| Planter | 9 × 2 × 9 | Primary | round planter ring (a tree goes in it) |
| LeaderboardFrame | 20 × 24 × 3 | Primary, Secondary, `Color_EEF0FF` | a stand with a flat screen 16 × 18 studs centred 13 studs up (MapService adds the SurfaceGui) |
