# Roblox upload tools (Open Cloud)

These scripts put the pet models and the game on Roblox without opening Studio, through Roblox's
official Open Cloud API. Claude can run them from a cloud session, and you can run them on your own computer.

| Script | What it does |
|--------|--------------|
| `upload_pets.py` | Uploads `assets/models/StormlingPets.glb` as a Model on your account (or group), waits for Roblox to approve it and writes its id into `GameConfig.PetMeshAssetId`. When a server starts, `PetMeshService` inserts that model into `ReplicatedStorage.PetMeshes`, so every pet uses its mesh model. Run it again after changing the pets (it uploads a new model). |
| `upload_icons.py` | Uploads the 3D UI icons (`assets/ui/icons3d/<Key>.png`) as Image assets and writes each id into `src/client/UI/Icons.luau`. Icons still at `Id = 0` are uploaded; `--force` re-uploads, `--only Volts,Pets` limits it. The game shows each icon's emoji until its id is set and Roblox has approved the image. |
| `upload_model.py` | The same upload for any model file and `GameConfig` key, e.g. the world prop pack (see [World props and other models](#world-props-and-other-models)). `upload_pets.py` is this script with the pet pack filled in. |
| `publish_place.py` | Builds the place with Rojo and publishes it to your game (or only saves a version with `--saved`). |

Only the Python standard library is needed (and `rojo` for `publish_place.py`).

## One-time setup

1. **Publish the game from Studio once** if you haven't yet. Open Cloud can update a place, not create one.
2. **Create an API key.** Go to [Creator Dashboard → Open Cloud → API Keys](https://create.roblox.com/dashboard/credentials?activeTab=ApiKeysTab)
   → **Create API Key** and give it a name.
   - Under **Access Permissions**, choose these APIs one at a time with **Select API System**:
     - **assets**: operations **Read** and **Write** (for `upload_pets.py` and `upload_model.py`).
     - **universe-places**: pick your game, operation **Write** (for `publish_place.py`).
   - Under **Security**, leave **Restrict IP addresses** off (cloud sessions don't have a fixed address).
   - Optionally set an expiration date. Then **Save & Generate Key** and copy the key.
   - A key that isn't used for 60 days expires on its own. Switch it off and on again to revive it.
3. **Store it as a secret, not in the code or the chat.**
   - *Claude cloud session*: open the environment's settings (the environment menu in the session's
     title bar → **Edit**) and add the environment variable `ROBLOX_API_KEY` with the key. New sessions
     pick it up.
   - *Your own computer (PowerShell)*: `$env:ROBLOX_API_KEY = "<the key>"` (only for that window).
4. **Tell the scripts which game** (these ids aren't secret; also environment variables):

   | Variable | Needed for | Where to find it |
   |----------|------------|------------------|
   | `ROBLOX_PLACE_ID` | publishing | The number in the game's URL (`roblox.com/games/<id>/...`) |
   | `ROBLOX_CREATOR_GROUP_ID` | uploading, only if the game belongs to a **group** | The number in the group's URL (`roblox.com/groups/<id>/...`) |
   | `ROBLOX_UNIVERSE_ID` | optional | Looked up from the place id automatically |
   | `ROBLOX_CREATOR_USER_ID` | optional | Without it, models go to the key's owner |

   The pet model must have **the same owner as the game** (both yours, or both the group's), or the game
   can't load it.

## Use

```powershell
python tools/roblox/upload_pets.py              # upload the pets, wait for approval, write the id into GameConfig
python tools/roblox/publish_place.py --yes      # build and publish the game (new servers get it)
```

- `--dry-run` on either script shows what would be sent, without sending it.
- `upload_pets.py --no-wait` doesn't wait for Roblox's approval.
- `upload_pets.py --update` uploads a new version of the model already in `GameConfig` instead of a new
  model. Roblox only documents this for `.fbx` files, so it may not work with the `.glb`.
- `publish_place.py --saved` saves a version you can open in Studio, without publishing it to players.

After `upload_pets.py`, commit the changed `GameConfig.luau` so the id stays with the code, then publish.

## World props and other models

`upload_model.py` uploads any `.glb`/`.gltf`/`.fbx` and writes its id into the `GameConfig` field you name
(the line `GameConfig.<key> = <number>` must already be there). For the SketchUp world prop pack
(`tools/world/README.md`):

```powershell
python tools/roblox/upload_model.py --file assets/models/StormWorldProps.glb --config-key WorldPropsAssetId --name "Storm World Props" --description "Map props for Storm Catcher Simulator"
```

When a server starts, `WorldProps` (used by `MapService`) inserts that model into
`ServerStorage.WorldProps` and places the props from it; a `WorldProps` pack already in `ServerStorage`
or `ReplicatedStorage` wins. With `WorldPropsAssetId = 0`, or if the model can't be loaded, the map
builds its props from parts. `--dry-run`, `--update`, `--no-config` and `--no-wait` work as for
`upload_pets.py`; without `--config-key` the id is only printed. Upload the pack again whenever
`build_world_pack.py` changes it, so the meshes match `WorldPropsData.luau`.

## Good to know

- **Roblox checks every upload.** The script waits up to 10 minutes for approval. Servers started before
  approval use the built-in pets.
- **Uploaded models become packages** in your inventory (Toolbox → Inventory → My Packages). That's normal.
- **Publishing replaces the whole place** with what's in this repository. Anything added to the place only
  in Studio is gone afterwards (export it first: right-click → **Save to File…**). The game's name, icon,
  thumbnails, gamepasses and developer products are not part of the place and stay as they are.
- **Close Studio before publishing.** Roblox refuses (409 Conflict) while the place is open in Studio or
  Team Create.
- **A pack that's already in the place wins.** If you imported `PetMeshes` in Studio, or saved it as
  `assets/models/PetMeshes.rbxm` for Rojo, `PetMeshService` leaves it alone.
- **Nothing breaks without it.** With `PetMeshAssetId = 0`, or if the model can't be loaded, the pets use
  their built-in models (Studio's Output says why).
- **Keep the key private.** Anyone with it can upload to and publish your game. If it leaks, delete it on
  the API Keys page and make a new one.
