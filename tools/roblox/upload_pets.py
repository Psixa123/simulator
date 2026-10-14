"""Uploads the Stormling pet mesh pack to Roblox and points the game at it.

Uploads assets/models/StormlingPets.glb as a Model asset through the Open Cloud Assets API, waits for
Roblox to process it and writes the new asset id into GameConfig.PetMeshAssetId. At server start
PetMeshService then inserts that model into ReplicatedStorage.PetMeshes, so the pets use the meshes
without importing anything in Studio. Run it again after changing the pets: it uploads a new version
of the same asset (same id).

Needs (environment variables, see tools/roblox/README.md):
    ROBLOX_API_KEY          Open Cloud API key with the Assets API "asset:read" + "asset:write" scopes
    ROBLOX_CREATOR_USER_ID  the user that owns the game, or
    ROBLOX_CREATOR_GROUP_ID the group that owns it (the model must have the same owner as the game)

    python tools/roblox/upload_pets.py              # upload (or update) and write the id into GameConfig
    python tools/roblox/upload_pets.py --dry-run    # show what would be sent
    python tools/roblox/upload_pets.py --new        # always create a new asset
"""

import argparse
import json
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import opencloud  # noqa: E402

ROOT = opencloud.ROOT
PACK = ROOT / "assets" / "models" / "StormlingPets.glb"
GAME_CONFIG = ROOT / "src" / "shared" / "Config" / "GameConfig.luau"
CONFIG_LINE = re.compile(r"^(GameConfig\.PetMeshAssetId\s*=\s*)(\d+)", re.M)
ASSETS = f"{opencloud.API}/assets/v1"
DISPLAY_NAME = "Stormling Pets"
DESCRIPTION = "Pet models for Storm Catcher Simulator"
FILE_TYPES = {".glb": "model/gltf-binary", ".gltf": "model/gltf+json", ".fbx": "model/fbx"}
POLL_SECONDS = 600


def configured_asset_id():
    match = CONFIG_LINE.search(GAME_CONFIG.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"can't find 'GameConfig.PetMeshAssetId = <number>' in {GAME_CONFIG}")
    return int(match.group(2))


def write_asset_id(asset_id):
    text = GAME_CONFIG.read_text(encoding="utf-8")
    new_text, count = CONFIG_LINE.subn(lambda m: m.group(1) + str(asset_id), text, count=1)
    if count != 1:
        sys.exit(f"can't find 'GameConfig.PetMeshAssetId = <number>' in {GAME_CONFIG}")
    if new_text != text:
        GAME_CONFIG.write_text(new_text, encoding="utf-8")


def creator():
    user = opencloud.env("ROBLOX_CREATOR_USER_ID", required=False)
    group = opencloud.env("ROBLOX_CREATOR_GROUP_ID", required=False)
    if bool(user) == bool(group):
        sys.exit(
            "Set exactly one of ROBLOX_CREATOR_USER_ID (game owned by you) or ROBLOX_CREATOR_GROUP_ID "
            "(game owned by a group). The model must have the same owner as the game."
        )
    value = user or group
    if not value.isdigit():
        sys.exit(f"the creator id must be a number, got {value!r}")
    return {"userId": value} if user else {"groupId": value}


def upload(path, asset_id, dry_run):
    content_type = FILE_TYPES.get(path.suffix.lower())
    if not content_type:
        sys.exit(f"{path.name}: upload a .glb, .gltf or .fbx file")
    data = path.read_bytes()
    if asset_id:
        method, url = "PATCH", f"{ASSETS}/assets/{asset_id}"
        meta = {"assetId": str(asset_id)}
    else:
        method, url = "POST", f"{ASSETS}/assets"
        meta = {
            "assetType": "Model",
            "displayName": DISPLAY_NAME,
            "description": DESCRIPTION,
            "creationContext": {"creator": creator()},
        }
    if dry_run:
        print(f"{method} {url}\n  request = {json.dumps(meta)}\n  fileContent = {path.name} ({len(data):,} bytes, {content_type})")
        return None
    body, multipart_type = opencloud.multipart(
        [
            ("request", None, None, json.dumps(meta).encode()),
            ("fileContent", path.name, content_type, data),
        ]
    )
    return opencloud.request(method, url, body=body, content_type=multipart_type)


def wait_for(operation):
    """Polls an Assets API operation until Roblox has processed the upload; returns the Asset."""
    operation_id = operation.get("operationId") or str(operation.get("path", "")).rsplit("/", 1)[-1]
    if not operation_id:
        sys.exit(f"unexpected response: {json.dumps(operation)}")
    deadline = time.time() + POLL_SECONDS
    delay = 2
    while not operation.get("done"):
        if time.time() > deadline:
            sys.exit(f"Roblox is still processing the upload (operation {operation_id}); run again later")
        time.sleep(delay)
        delay = min(delay * 1.5, 15)
        operation = opencloud.request("GET", f"{ASSETS}/operations/{operation_id}")
    if operation.get("error"):
        sys.exit(f"upload failed: {json.dumps(operation['error'])}")
    return operation.get("response") or {}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", type=pathlib.Path, default=PACK, help="model file to upload (default: StormlingPets.glb)")
    parser.add_argument("--new", action="store_true", help="create a new asset even if GameConfig already has one")
    parser.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    parser.add_argument("--no-config", action="store_true", help="don't write the asset id into GameConfig")
    args = parser.parse_args()

    path = args.file.resolve()
    if not path.is_file():
        sys.exit(f"{path} not found; run python tools/pets/build_pets.py --no-render first")
    existing = 0 if args.new else configured_asset_id()

    try:
        operation = upload(path, existing, args.dry_run)
        if operation is None:
            return
        asset = wait_for(operation)
    except opencloud.ApiError as error:
        if existing and error.status in (403, 404):
            sys.exit(
                f"can't update asset {existing} ({error}). Check the key's asset:write scope and that the key's "
                "owner owns the asset, or run with --new to upload a new one."
            )
        sys.exit(f"upload failed: {error}")

    asset_id = int(asset.get("assetId") or existing or 0)
    if not asset_id:
        sys.exit(f"Roblox didn't return an asset id: {json.dumps(asset)}")
    state = (asset.get("moderationResult") or {}).get("moderationState", "unknown")
    print(f"{'Updated' if existing else 'Uploaded'} {path.name} as model {asset_id} (moderation: {state})")
    print(f"  https://create.roblox.com/store/asset/{asset_id}")
    if not args.no_config:
        write_asset_id(asset_id)
        print(f"  GameConfig.PetMeshAssetId = {asset_id}")
    if state not in ("Approved", "unknown"):
        print("  The pets show up in game once Roblox has approved the model.")


if __name__ == "__main__":
    main()
