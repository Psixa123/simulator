# Roblox upload tools (Open Cloud)

These scripts put the game and the pet models on Roblox without opening Studio, through Roblox's
official Open Cloud API. Claude can run them from a cloud session, and you can run them on your own computer.

| Script | What it does |
|--------|--------------|
| `upload_pets.py` | Uploads `assets/models/StormlingPets.glb` as a Model on your account (or group) and writes its id into `GameConfig.PetMeshAssetId`. When a server starts, `PetMeshService` inserts that model into `ReplicatedStorage.PetMeshes`, so every pet uses its mesh model. Run it again after changing the pets: it uploads a new version of the same model. |
| `publish_place.py` | Builds the place with Rojo and publishes it to your experience (or saves it with `--saved`). |

Only the Python standard library is needed (and `rojo` for `publish_place.py`).

## One-time setup

1. **Create an API key.** Go to [Creator Dashboard → Open Cloud → API Keys](https://create.roblox.com/dashboard/credentials)
   → **Create API Key**. If the game belongs to a group, create the key in that group.
   - Under **Access Permissions** add:
     - **Assets API**: `Read` and `Write` (for `upload_pets.py`).
     - **Place Publishing**: pick your experience, `Write` (for `publish_place.py`).
   - **Accepted IP Addresses**: add `0.0.0.0/0` (cloud sessions don't have a fixed address).
   - Set an expiration date if you like, then **Save & Generate Key** and copy the key.
2. **Store it as a secret, not in the code or the chat.**
   - *Claude cloud session*: open the environment's settings (the environment menu in the session's
     title bar → **Edit**) and add an environment variable `ROBLOX_API_KEY` with the key. New sessions
     pick it up.
   - *Your own computer (PowerShell)*: `$env:ROBLOX_API_KEY = "<the key>"` (only for that window).
3. **The ids** (not secret; also environment variables):

   | Variable | Where to find it |
   |----------|------------------|
   | `ROBLOX_CREATOR_USER_ID` | The number in your profile URL (`roblox.com/users/<id>/profile`). Use this if the game is yours… |
   | `ROBLOX_CREATOR_GROUP_ID` | …or this if the game belongs to a group (the number in the group's URL). Set only one. |
   | `ROBLOX_UNIVERSE_ID` | Creator Dashboard → your experience → the **⋯** menu → **Copy Universe ID** |
   | `ROBLOX_PLACE_ID` | The number in the game's URL (`roblox.com/games/<id>/...`) |

   The pet model must have **the same owner as the game** (both yours, or both the group's), or Roblox
   won't let the game load it.

## Use

```powershell
python tools/roblox/upload_pets.py              # upload (or update) the pets, write the id into GameConfig
python tools/roblox/publish_place.py --yes      # build and publish the game (players get it on new servers)
```

`--dry-run` on either script shows what would be sent without sending it. `upload_pets.py --new` uploads a
new model instead of updating the one in `GameConfig`. `publish_place.py --saved` saves a version you can
open in Studio without publishing it to players.

After `upload_pets.py`, commit the changed `GameConfig.luau` so the id stays with the code.

## Good to know

- **Roblox checks every upload.** The pets appear in game once the model is approved, usually within minutes.
- **Publishing replaces the whole place** with what's in this repository. Anything added to the place only
  in Studio is gone afterwards (export it first: right-click → **Save to File…**). The experience's name,
  icon, thumbnails, gamepasses and developer products are not part of the place and stay as they are.
- **A pack that's already in the place wins.** If you imported `PetMeshes` in Studio, or saved it as
  `assets/models/PetMeshes.rbxm` for Rojo, `PetMeshService` leaves it alone.
- **Nothing breaks without it.** With `PetMeshAssetId = 0`, or if the model can't be loaded, the pets use
  their built-in models (Studio's Output says why).
- **Keep the key private.** Anyone with it can upload to and publish your experience. If it leaks, delete it
  on the API Keys page and make a new one.
