# Store listing: gamepasses and developer products

Everything to type into the Creator Dashboard, with the icon for each item. The keys match
`src/shared/Config/Monetization.luau`; after creating an item, put its ID into that key's `Id`.

- **Gamepasses**: [Creator Dashboard](https://create.roblox.com/dashboard/creations) → your experience →
  **Monetization → Passes → Create a Pass**. Upload the icon, set the name and description, save, then open the
  pass → **Sales** → turn on **Item for Sale** and set the price.
- **Developer products**: **Monetization → Developer Products → Create a Developer Product**. Upload the icon and
  set the name, description and price.

Icons are 512×512 PNGs (Roblox shows pass icons in a circle; the art stays inside it). They are rendered from
`assets/source/badge.html` with `python tools/render_art.py gamepasses products`.

The in-game Shop shows the same pictures as its card art. They are uploaded separately, as plain images, by
`python tools/roblox/upload_store_icons.py`, which writes each id into the item's `Image` field (see
`tools/roblox/README.md`). Run it again with `--only <Key> --force` after re-rendering an icon.

## Gamepasses

| Key | Name | Price (R$) | Description | Icon |
|-----|------|-----------:|-------------|------|
| `VIP` | VIP | 399 | +25% Volts and energy, a VIP chat tag and a golden crown above your head. | `assets/gamepasses/VIP.png` |
| `DoubleVolts` | 2x Volts | 199 | Earn double Volts every time you sell energy. | `assets/gamepasses/DoubleVolts.png` |
| `DoubleEnergy` | 2x Energy | 249 | Your vacuum collects double energy from all weather. | `assets/gamepasses/DoubleEnergy.png` |
| `AutoCatch` | Auto Catch | 299 | Your vacuum automatically catches the nearest weather. No clicking needed! | `assets/gamepasses/AutoCatch.png` |
| `RemoteSell` | Remote Sell | 199 | Sell from anywhere and automatically sell whenever your tank is full. | `assets/gamepasses/RemoteSell.png` |
| `MegaTank` | Mega Tank | 149 | Double your Storm Tank capacity forever. | `assets/gamepasses/MegaTank.png` |
| `LuckyHatcher` | Lucky Hatcher | 249 | +50% luck for Rare, Epic and Legendary pets from every egg. | `assets/gamepasses/LuckyHatcher.png` |
| `TripleHatch` | Triple Hatch | 149 | Hatch 3 eggs at once. | `assets/gamepasses/TripleHatch.png` |
| `AutoHatch` | Auto Hatch | 99 | Keep hatching eggs automatically while you stand next to them. | `assets/gamepasses/AutoHatch.png` |
| `PetSlots` | +3 Pet Slots | 249 | Equip 3 more pets at the same time. | `assets/gamepasses/PetSlots.png` |
| `StormRadar` | Storm Radar | 149 | Get alerted whenever rare weather spawns in any zone you've unlocked, with a button that teleports you there. | `assets/gamepasses/StormRadar.png` |

## Developer products

Volts packs give a number of full tanks of your best zone's energy, so they stay worth buying at every stage.

| Key | Name | Price (R$) | Description | Icon |
|-----|------|-----------:|-------------|------|
| `VoltsSmall` | Pouch of Volts | 25 | 4 full tanks' worth of Volts from your best zone. | `assets/products/VoltsSmall.png` |
| `VoltsMedium` | Bag of Volts | 79 | 15 full tanks' worth of Volts from your best zone. | `assets/products/VoltsMedium.png` |
| `VoltsLarge` | Crate of Volts | 249 | 60 full tanks' worth of Volts from your best zone. | `assets/products/VoltsLarge.png` |
| `VoltsHuge` | Vault of Volts | 699 | 200 full tanks' worth of Volts from your best zone. The best value! | `assets/products/VoltsHuge.png` |
| `EnergyBoost` | 2x Energy (30 min) | 49 | Double energy from all weather for 30 minutes. Stacks with the 2x Energy pass. | `assets/products/EnergyBoost.png` |
| `LuckBoost` | 2x Luck (30 min) | 49 | Double hatch luck for 30 minutes. | `assets/products/LuckBoost.png` |
| `SummonMegaStorm` | Summon Mega Storm | 99 | Summon a Mega Storm for the whole server! It arrives in 20 seconds, or right after any storm that is already on its way. | `assets/products/SummonMegaStorm.png` |
| `AuroraGryphon` | Aurora Gryphon | 2,000 | An exclusive pet with glowing aurora wings: +600% energy. Every purchase adds one more to your team. | `assets/products/AuroraGryphon.png` |

The Aurora Gryphon is the lobby shop pet: the display stand in the hub and the featured card at the top of the
Shop sell it. Every purchase gives one more Aurora Gryphon (granted even when pet storage is full).
