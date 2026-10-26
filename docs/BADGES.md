# Badges

17 achievement badges, each with a 3D icon. The keys match `src/shared/Config/Badges.luau`; the game awards a badge
as soon as its `Id` there is set (see "In the game" below). Until then nothing is awarded (Studio prints
`[Achievements] <player> would earn '<badge>' (no badge Id yet)` instead).

## The badges

| Key | Name | Description (paste into the dashboard) | How it is earned | Icon |
|-----|------|----------------------------------------|------------------|------|
| `Welcome` | Welcome, Storm Chaser! | Joined Storm Catcher Simulator. Grab your vacuum and catch the weather! | Join the game | `assets/badges/Welcome.png` |
| `FirstCatch` | First Catch | Vacuumed up your very first weather cell. | Catch 1 weather cell (`Stats.CellsCaught` ≥ 1) | `assets/badges/FirstCatch.png` |
| `RareCatch` | Rare Weather | Caught a rare weather cell, like a Rainbow Mist or a Thunderhead. | Catch a Rare weather cell (`Stats.RareCaught` ≥ 1, counted from this update on) | `assets/badges/RareCatch.png` |
| `StormChaser` | Storm Chaser | Caught 1,000 weather cells. | `Stats.CellsCaught` ≥ 1,000 | `assets/badges/StormChaser.png` |
| `Zone_Thunder` | Thunder Valley | Unlocked Thunder Valley, where lightning never stops striking. | Unlock zone 2 | `assets/badges/Zone_Thunder.png` |
| `Zone_Dunes` | Dune Sea | Unlocked the Dune Sea and its whirling dust devils. | Unlock zone 3 | `assets/badges/Zone_Dunes.png` |
| `Zone_Frost` | Frostpeak | Unlocked Frostpeak, home of blizzards and aurora spirits. | Unlock zone 4 | `assets/badges/Zone_Frost.png` |
| `Zone_Volcano` | Ashfall Volcano | Unlocked Ashfall Volcano and its fire tornadoes. | Unlock zone 5 | `assets/badges/Zone_Volcano.png` |
| `Zone_Sky` | Upper Atmosphere | Reached the Upper Atmosphere, the last zone above the clouds. | Unlock zone 6 | `assets/badges/Zone_Sky.png` |
| `FirstHatch` | First Hatch | Hatched your first Stormling from a cloud egg. | Hatch 1 egg (`Stats.EggsHatched` ≥ 1) | `assets/badges/FirstHatch.png` |
| `LegendaryPet` | Legendary Luck | Hatched a Legendary Stormling. | A Legendary pet is in the pet index | `assets/badges/LegendaryPet.png` |
| `GoldenPet` | Solid Gold | Crafted a Golden pet from 5 of the same pet. | Own a Golden (or Rainbow) pet | `assets/badges/GoldenPet.png` |
| `RainbowPet` | Over the Rainbow | Crafted a Rainbow pet from 5 Golden pets. | Own a Rainbow pet | `assets/badges/RainbowPet.png` |
| `ClimateShift` | Climate Shift | Did your first Climate Shift (rebirth). | Rebirth once | `assets/badges/ClimateShift.png` |
| `MegaStorm` | Mega Storm Survivor | Helped take on a Mega Storm in the arena. | Damage a Mega Storm (`Stats.MegaStorms` ≥ 1) | `assets/badges/MegaStorm.png` |
| `StormChampion` | Storm Champion | Won an exclusive pet from a Mega Storm. | A Mega Storm exclusive pet is in the pet index (the lobby shop's Aurora Gryphon doesn't count) | `assets/badges/StormChampion.png` |
| `Millionaire` | Millionaire | Earned 1,000,000 Volts. | `TotalVolts` (lifetime Volts earned) ≥ 1,000,000 | `assets/badges/Millionaire.png` |

Every rule reads the player's saved data, so players who already qualify get the badge the next time they join
(zones, rebirths, pets, catches, hatches, Mega Storms, Volts). The one exception is `RareCatch`: rare catches were not
counted before, so it is earned by the next rare cell caught.

## Create them on the Creator Dashboard

1. Open the [Creator Dashboard](https://create.roblox.com/dashboard/creations) and select **Storm Catcher Simulator**
   (universe 10770508589). Go to **Engagement → Badges** (called **Associated Items → Badges** in older layouts) and
   click **Create a Badge**. (Another way in: hover the experience's thumbnail, click **⋯** and choose **Create Badge**.)
2. **Upload Image**: pick the badge's PNG from `assets/badges/` (512×512; Roblox crops it to a circle, and all the
   art is already inside that circle).
3. **Name** and **Description**: copy them from the table above. Leave **Badge is Enabled** on (a disabled badge
   is hidden on the game page and can't be earned).
4. Click **Create Badge**, then open it and copy its **Badge ID** (the number in its URL / on its page).

**Cost:** Roblox lets you create **5 badges per experience for free in each 24-hour period (GMT)**; each further
badge in that period costs **100 Robux** (create.roblox.com/docs/production/publishing/badges, checked October 2026).
All 17 for free takes 4 days, e.g.:

- Day 1: Welcome, FirstCatch, FirstHatch, Zone_Thunder, ClimateShift (the ones most players earn first)
- Day 2: RareCatch, Zone_Dunes, MegaStorm, GoldenPet, LegendaryPet
- Day 3: StormChaser, Zone_Frost, Zone_Volcano, Millionaire, StormChampion
- Day 4: Zone_Sky, RainbowPet

## In the game

Send the badge IDs back (Key → ID); they go into the `Id = 0` of each badge in `src/shared/Config/Badges.luau`.
A badge works as soon as its ID is in and the game is published; the others keep waiting.

`src/server/Services/AchievementService.luau` (named so it isn't confused with Roblox's `BadgeService`) watches the
player data that the other services already change (`DataService.Changed`, plus a check on join and every 20 s) and
awards each badge whose rule the data meets, in its own thread so the game never waits on Roblox:

- `BadgeService:UserHasBadgeAsync` once per badge per session (the answer is cached), then
  `BadgeService:AwardBadgeAsync`, both in `pcall`;
- a failed call is retried after 15 s, then 30 s, 60 s, ... (at most 5 tries per badge per session; the next join
  tries again);
- checks are batched: at most one per player every half second.

Roblox shows its own "badge earned" notification, so the game adds none. The only data change is a new counter,
`Stats.RareCaught` (DataService template, counted in `WeatherService` when a Rare cell is caught).

Tests: `tests/mock/Badges.spec.luau` (in `python3 tests/mock/run_mock_tests.py`).

## Icons

The icons are 3D medals made with the same pipeline as the store icons: SketchUp models
(`tools/icons/sketchup_badge_icons.py`: the medals, the trophy, the egg shell), the game's own models for the rest
(zone emblems, pets, store heroes, UI icons; `tools/icons/badge_scenes.py`), rendered by
`python3 tools/icons/render_icons.py --set badges` and laid out by `assets/source/badges3d.html`
(`python3 tools/render_art.py badges`). See `tools/icons/README.md`, "Badge icons".
