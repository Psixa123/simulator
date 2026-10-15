"""Uploads the Stormling pet mesh pack to Roblox and points the game at it.

Uploads assets/models/StormlingPets.glb as a Model asset through the Open Cloud Assets API, waits for
Roblox to process and approve it, and writes the new asset id into GameConfig.PetMeshAssetId. At server
start PetMeshService inserts that model into ReplicatedStorage.PetMeshes, so the pets use the meshes
without importing anything in Studio. Run it again after changing the pets (it uploads a new model).

Needs (environment variables, see tools/roblox/README.md):
    ROBLOX_API_KEY           Open Cloud API key with the "assets" API, Read + Write
    ROBLOX_CREATOR_GROUP_ID  only if the game belongs to a group: the model must have the same owner as
                             the game. Otherwise the model goes to the key's owner (or set
                             ROBLOX_CREATOR_USER_ID).

    python tools/roblox/upload_pets.py              # upload, wait for approval, write the id into GameConfig
    python tools/roblox/upload_pets.py --dry-run    # show what would be sent
    python tools/roblox/upload_pets.py --update     # new version of the model in GameConfig (same id;
                                                    # Roblox only documents this for .fbx files)

The work is done by upload_model.py (the same upload for any model file and GameConfig key).
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import upload_model  # noqa: E402  (the generic uploader; this script fills in the pet pack)

ROOT = upload_model.ROOT
PACK = ROOT / "assets" / "models" / "StormlingPets.glb"
CONFIG_KEY = "PetMeshAssetId"
DISPLAY_NAME = "Stormling Pets"
DESCRIPTION = "Pet models for Storm Catcher Simulator"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", type=pathlib.Path, default=PACK, help="model file to upload (default: StormlingPets.glb)")
    upload_model.add_common_flags(parser)
    args = parser.parse_args()
    upload_model.run(
        args.file,
        config_key=CONFIG_KEY,
        name=DISPLAY_NAME,
        description=DESCRIPTION,
        update=args.update,
        dry_run=args.dry_run,
        no_config=args.no_config,
        no_wait=args.no_wait,
        missing_hint="run python tools/pets/build_pets.py --no-render first",
        pending_note="the pets switch to the meshes on servers started after approval.",
    )


if __name__ == "__main__":
    main()
