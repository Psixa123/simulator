# Storm Catcher Simulator – Art Direction

Target look: the bright, chunky, glossy "big simulator" cartoon style that top Roblox pet
simulators use (Pet Simulator 99 was the reference the owner pointed at). We borrow the
*qualities* of that style – readable silhouettes, candy colours, soft lighting, toy-like UI –
never its assets, logos, names or exact layouts. Everything is built from our own code and art.

## 1. Interface

### Feel
Toy-like and friendly. Light panels on top of a colourful world, big rounded shapes, thick
outlines on text, buttons that look pressable (3D edge), generous spacing, emoji/icon art in
saturated colours. One glance should tell a 9-year-old what every button does.

### Palette
| Token | Colour | Use |
| --- | --- | --- |
| Panel | `#FFFFFF` → `#EEF3FF` (top→bottom gradient) | window body |
| PanelStroke | `#C7D2F2` (4 px) + outer ink `#2B3467` (2 px) | window outline |
| Card | `#F4F7FF`, stroke `#D9E1F7` | cards / tiles inside windows |
| Ink | `#2B3467` | text on light panels (titles, values) |
| SubInk | `#6E7BA8` | secondary text on light panels |
| HudText | `#FFFFFF` with 2.5–3 px stroke `#1B1F3B` | any text drawn over the 3D world |
| Volts | `#FFC928` → `#FF9F1A` | currency |
| Energy | `#5BD8FF` → `#2E9BFF` | tank / energy |
| Buttons | Green `#6BE05A`→`#2FB344`, Blue `#5CC2FF`→`#2C86F0`, Yellow `#FFD84A`→`#F5A623`, Red `#FF6B7A`→`#E2364F`, Purple `#B58CFF`→`#7A4BF0`, Pink `#FF8AD0`→`#E0479E`, Teal `#5BE8D3`→`#1FB3A3`, Gray `#C3CBE3`→`#8E99BD` | |

Rarity colours stay as in `Config/Pets.luau`.

### Typography
* Titles, numbers, buttons: **Fredoka One** (`Enum.Font.FredokaOne`).
* Body text: Gotham Bold / Medium.
* HUD and button text is white with a dark stroke (button text stroke = a darker shade of the
  button colour, e.g. green button → `#1E7A2E`). Text on light panels is `Ink`, no stroke.

### Components
* **Window** – white→ice-blue gradient body, corner radius 24, 4 px light stroke inside a 2 px
  ink outline, soft drop shadow (a transparent dark copy offset 6 px down). The title sits at the
  top-left in Ink Fredoka 34 px, next to a 64 px rounded-square **icon badge** (accent gradient,
  white glyph, ink outline) that overlaps the window's top-left corner. The close button is a red
  3D square overlapping the top-right corner. No coloured header bar.
* **3D button** – rounded 14, face = vertical gradient of the button colour plus a white "shine"
  strip on the top 40 %, under it a darker *base* (button colour × 0.65) peeking out 5 px below.
  Pressing moves the face down 3 px (base stays). White Fredoka label with a darker stroke.
* **Card / tile** – `Card` fill, 2 px stroke, radius 16. Item tiles (pets, eggs, passes) get a
  rarity/accent gradient top half and the item art centred; name under it in Ink.
* **Pill** – full-round capsule. Currency pills: white→ice gradient, 3 px ink stroke, a large
  glossy icon overlapping the left end, value in white Fredoka with a 3 px ink stroke, and a small
  green "+" button on the right where buying makes sense.
* **Progress bar** – ink-outlined capsule, inset track `#DCE4FA`, gradient fill with a shine strip.
* **Toast** – white pill with an accent-coloured left icon circle, Ink text.
* **Badge** – red circle with white number / "!", ink outline, pops when it appears.

### HUD layout
* **Left column (vertically centred):** big square menu buttons (72 px, 2 columns on wide
  screens, 1 column on phones): white rounded square, ink outline, glossy icon, white label with
  ink stroke underneath; red badge top-right when something is claimable.
* **Top centre (under the Roblox top bar):** currency pills (Volts, then Energy/Tank).
* **Bottom centre:** the Storm Tank capacity bar as a chunky pill with the SELL button.
* **Right side:** boosts and Storm Radar alerts (already placed to avoid the jump button).
* Nothing in the top-left/top-right corners (Roblox chat/player list) – see `InterfaceController`.

### Icons
`src/client/UI/Icons.luau` maps every UI icon key to an uploaded image id (`Id`) plus an emoji
fallback. Until the images in `assets/ui/` are uploaded and their ids pasted in, the emoji is
shown, so the game always works.

## 2. World

### Overall
* No Roblox Terrain on play areas: everything is flat, **SmoothPlastic** parts in saturated
  colours with clean edges. Soft, bright, almost shadowless lighting.
* Each biome is a **"stage"**: a big rectangular play field (exactly `MapLayout.FieldBounds`) in
  the biome's ground colour with a white dashed border, surrounded by a wide rounded
  **path ring** of pale lavender tiles (`#B9C2F0` / `#C9D0F7`, faint tile seams), with path
  branches to the gate, the Weather Lab (sell pad) and the egg station in the plaza between the
  gate and the field.
* Outside the walkable area the edges are packed with chunky low-poly props so every view is
  framed and busy: candy-coloured round trees (trunk + 2–4 overlapping blobs), rocks, crystals,
  themed buildings, flags/bunting, lamps. Big readable signs (white Fredoka text, ink stroke).
* Buildings and machines are toy-like: chunky white-lavender bodies (`#EEF0FF`) with bright
  roofs and trim (blue, pink, yellow, mint), rounded edges (cylinders/balls at corners),
  glowing windows, a sign on top.

### Biome palettes (ground / field / accents)
| Biome | Ground | Field | Props |
| --- | --- | --- | --- |
| Sunny Plains | lime `#6EE05A` | grass `#8BEA5E` | pink/lilac/lime round trees, flowers, windmill, picket fences |
| Thunder Valley | indigo-violet `#7C74E8` | `#9A92F5` | purple-blue trees, tesla towers, glowing yellow bolts, storm-cloud props |
| Dune Sea | sand `#FFD27A` | `#FFE19A` | cacti, palms, turquoise oasis pools, pyramids, mirage crystals |
| Frostpeak | snow `#EAF6FF` | `#D6EEFF` | snowy pines, ice crystals, igloos, ice castle, snowmen |
| Ashfall Volcano | warm rock `#8A5A4E` | `#B5705A` | orange/red crystal spires, lava pools (neon), volcano, steam vents |
| Upper Atmosphere | lilac sky-plate `#C9B8FF` | `#E2D8FF` | floating islands, star lamps, cloud banks, citadel, aurora ribbons |

The hub (**Storm Station**) is a pale lavender plaza with the six station machines arranged
around it, the arena in the middle-west and the forecast/leaderboards facing the spawn.

### Lighting (per zone, via `Zones[i].Lighting`)
Bright midday (`ClockTime` ~13.5, `Brightness` ~3), high `OutdoorAmbient`, very soft shadows
(`ShadowSoftness` 0.8–1), `ColorCorrection` saturation +0.2–0.3, light bloom, thin tinted
atmosphere. Darker biomes (Thunder, Volcano) stay *cartoon-bright*: tinted, never gloomy.

### Performance budget
≤ 12,000 parts for the whole world. Decorative parts: `CanCollide/CanQuery/CanTouch = false`,
`CastShadow = false` for anything smaller than a tree. Reuse builder functions; no unions/meshes
(everything is generated in code).

## 3. Previewing without Roblox
`tools/preview_map.py` runs the real `MapService` in a mock Roblox runtime and renders the
resulting parts with three.js into `build/preview/*.png`, so the world can be checked from any
machine (see the script header for usage).
