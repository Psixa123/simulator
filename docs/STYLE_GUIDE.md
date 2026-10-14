# Storm Catcher Simulator – Art Direction: "Sky Lab"

The game's own look: a bright, toy-like **weather laboratory floating in the sky**. Players are storm
chasers with weather vacuums, so everything borrows from weather and weather instruments: puffy
clouds, lightning bolts, raindrops, rainbows, radar dishes, wind vanes, weather balloons, glass jars
full of captured storms. Shapes are chunky and rounded, colours are candy-bright, outlines are a deep
storm-navy "ink", and lighting is sunny and soft.

Three rules for every screen and every prop:

1. **Readable at a glance.** Big silhouettes, one idea per object, high contrast between a thing and
   what's behind it.
2. **Soft and chunky.** No thin parts and no sharp corners: everything is inflated, rounded and a bit
   oversized, like a toy.
3. **Weather everywhere.** When a shape is decorative, make it a cloud, a bolt, a drop or an
   instrument.

## 1. Palette

| Token | Colour | Use |
| --- | --- | --- |
| Ink | `#233066` | outlines (2–3 px), text on light surfaces |
| InkSoft | `#5B6A9E` | secondary text |
| Cloud → Mist | `#FFFFFF` → `#EAF3FF` | window and card bodies (top → bottom) |
| Haze | `#D5E5FB` | insets, tracks, empty slots |
| Sky | `#5CC8FF` → `#2F86F2` | primary accent: window header bands, active tabs |
| Bolt | `#FFE15A` → `#FFAA1F` | Volts, highlights, "new" |
| Rain | `#54E0FF` → `#1E9BEF` | energy, the storm jar's liquid |
| Storm | `#A98BFF` → `#6B4BE6` | premium, Climate Shift (rebirth), rare things |
| Leaf | `#7BE36A` → `#33B24A` | buy, confirm, sell |
| Coral | `#FF7A85` → `#E43A58` | close, delete, danger, badges |
| Sunset | `#FFB15C` → `#F2702A` | warnings, boosts |

Pet rarity colours stay as in `Config/Pets.luau`.

## 2. Interface

### Typography
* **Fredoka One** (`Enum.Font.FredokaOne`) for titles, numbers and buttons; **Gotham** Bold/Medium for
  body text.
* On light surfaces text is **Ink** with no stroke. On coloured surfaces (buttons, header bands) and
  over the 3D world it is **white with a stroke**: Ink over the world, a darker shade of the surface
  colour on buttons (×0.55).

### Components
* **Cloud window** – Cloud→Mist gradient body, corner 26, 3 px Ink outline, a soft shadow (Ink at 75 %
  transparency, 6 px lower). A **Sky header band** (60 px) runs across the top with the title in white
  Fredoka 32 (3 px Ink stroke). Three white **cloud puffs** (circles with the same outline) rise above
  the band's right half, so every window has a cloud silhouette. A 76 px round **weather badge**
  (white face, 4 px Bolt ring, Ink outline, the panel's 3D icon) overlaps the top-left corner, and a
  48 px round Coral **close button** with a white ✕ overlaps the top-right corner.
* **Candy button** – corner 14 (or a pill), vertical gradient face, 2–3 px Ink outline, a 5 px darker
  **lip** under the face (colour ×0.62), a white **shine** over the top 35 % (75 % transparent).
  Pressing pushes the face down 3 px onto the lip; hovering scales it to 1.04. Label: white Fredoka
  with a darker stroke.
* **Tile** – Cloud fill, 2 px Haze stroke, corner 18. Item tiles show the item's art on a rounded
  rarity-coloured **pedestal** (the bottom 30 % of the tile) with the name in Ink above it; the
  selected tile gets a 3 px Sky outline and a slight lift.
* **Capsule** (currency) – Cloud→Mist pill with a 3 px Ink outline, a 54 px glossy 3D icon
  overlapping its left end, the value in Ink Fredoka 26, and a small Leaf "+" candy button on the
  right where buying makes sense.
* **Storm jar** (tank / progress) – a glass capsule: Haze track, 3 px Ink outline, a Rain-gradient
  liquid fill with a white shine stripe and a few bubble dots drifting up, the jar icon on the left
  and the amount in Ink Fredoka. When full, the jar wobbles and glows.
* **Tabs** – pills inside a Haze track; the active tab is a Sky candy pill.
* **Badge** – Coral circle with a white number or "!", Ink outline; it pops when it appears.
* **Toast** – a Cloud pill with a 2 px Ink outline and a coloured round icon disk on the left; it slides
  down from the top and bounces once.

### HUD layout
* **Left:** a column of round **weather-badge buttons** (68 px circles: white face, 3 px Sky ring, Ink
  outline, 3D icon, white Fredoka label with Ink stroke underneath). Two columns on wide screens, one on
  phones. A Coral badge on the top-right of a button when something is claimable.
* **Top centre** (under the Roblox top bar): currency capsules – Volts, then Climate Shifts.
* **Bottom centre:** the Storm jar (tank) with a big Leaf **SELL** candy button to its right.
* **Right:** active boosts as round timers, and Storm Radar alerts.
* Nothing in the top-left or top-right corners (Roblox chat and player list).

### Icons
Icons are small **3D objects modelled in SketchUp** (volt coin, raindrop, paw, egg, shopping bag,
arrow, gift, globe with pin, swirl, gear, book, radar dish, lock, check, star, rainbow, clover, jar,
fist, target, wing, ticket, calendar, thundercloud, coin bag, …) and rendered as glossy PNGs with a
soft toon shade, an Ink outline and a highlight (`assets/ui/`). `src/client/UI/Icons.luau` maps each
icon key to its uploaded image id plus an emoji fallback, so the game works before the images are
uploaded.

## 3. World

### Overall: sky islands
* Every region (the Storm Station hub and the six zones) is the flat top of a **giant floating island**.
  The playable strip is unchanged (`MapLayout`), but beyond the side boundaries the island ends in
  chunky **layered cliffs** (a grass/snow/sand lip, then bands of rock) that drop into a **sea of
  cartoon clouds**. No Roblox Terrain: everything is SmoothPlastic parts plus the SketchUp prop pack.
* The ground is the biome's colour. Each zone's weather **field** (exactly `MapLayout.FieldBounds`) is a
  slightly raised pad in a lighter shade with a white dashed border. A light **path** of rounded pavers
  runs along the middle of the island to every zone, with branches to the Weather Lab (sell pad) and
  the egg incubator in the plaza between the gate and the field.
* The island edges are packed with props so every view is framed: trees, rocks, crystals, themed
  landmarks, lamps, fences, signs. Signs are big white Fredoka text with an Ink stroke.
* Buildings and machines look like toys: chunky white-lavender bodies (`#EEF0FF`) with bright roofs and
  trim, rounded edges, round glowing windows, a sign on top.

### Biomes
| Zone | Ground / field | Props |
| --- | --- | --- |
| Storm Station (hub) | lavender plaza `#C9D0F7` / `#DDE2FB` | weather tower landmark, six station buildings, lamps, planters, round trees |
| Sunny Plains | lime `#6EE05A` / `#8BEA5E` | round pink/lilac/lime trees, flower patches, mushrooms, windmill, picket fences, hay bales |
| Thunder Valley | violet `#7C74E8` / `#9A92F5` | blue-purple trees, tesla towers, storm clouds with bolts, purple crystals, lightning rods |
| Dune Sea | sand `#FFD27A` / `#FFE19A` | cacti, palms, pyramids, oasis pools, sandstone arches |
| Frostpeak | snow `#EAF6FF` / `#D6EEFF` | snowy pines, ice crystals, igloos, snowmen, ice castle |
| Ashfall Volcano | warm rock `#8A5A4E` / `#B5705A` | volcano, lava rock spires, glowing crystals, lava pools, steam vents |
| Upper Atmosphere | lilac `#C9B8FF` / `#E2D8FF` | small floating islands, star lamps, cloud banks, citadel towers, aurora arches |

### Prop kit (SketchUp)
Props are modelled in Trimble SketchUp (`tools/world/sketchup/`), pulled out of SketchUp as meshes and
packed into `assets/models/StormWorldProps.glb`. See `tools/world/README.md` for the pipeline.

* **Units and axes:** in SketchUp, 12 in = 1 stud, Z up, the prop's front facing −Y, origin at the
  centre of its base. In the pack: studs, Y up, front −Z.
* **Pieces:** every prop is a group `Prop_<PropId>` made of leaf groups named by **paint**:
  `Primary`, `Secondary`, `Tertiary` (recoloured per biome when placed), or a fixed colour
  `Color_RRGGBB`, `Neon_RRGGBB` (glows) or `Glass_RRGGBB` (see-through). In the pack each piece is
  named `<PropId>.<Paint>` and every prop has a 1-stud `Root` cube at its origin for scale and position.
* **Look:** inflated, rounded forms (lofted solids, blobs, domes, rounded boxes), smooth-shaded, no
  thin parts, at most about 3,000 triangles per prop.

### Lighting (per zone, via `Zones[i].Lighting`)
Bright midday (`ClockTime` ~13.5, `Brightness` ~3), high `OutdoorAmbient`, very soft shadows,
`ColorCorrection` saturation +0.2–0.3, light bloom, a thin tinted atmosphere. Darker biomes (Thunder,
Volcano) stay cartoon-bright: tinted, never gloomy.

### Performance
At most 12,000 parts in the whole world. Decorative parts and props: `CanCollide/CanQuery/CanTouch =
false` unless players should bump into them (buildings, big rocks), and `CastShadow = false` for
anything smaller than a tree. Props are clones of the same few meshes, which Roblox draws efficiently.

## 4. Previewing without Roblox
`tools/preview_map.py` runs the real `MapService` in a mock Roblox runtime and renders the result (parts
and prop meshes) with three.js into `build/preview/*.png`, so the world can be checked from any machine
(see the script header for usage).
