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
MAX_BYTES = 20 * 1024 * 1024
PROCESS_SECONDS = 900
APPROVAL_SECONDS = 600


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


def numeric(name, value):
    if not value.isdigit():
        sys.exit(f"{name} must be a number, got {value!r}")
    return value


def key_owner():
    """The user id the API key belongs to (Open Cloud key introspection)."""
    info = opencloud.request(
        "POST", f"{opencloud.API}/api-keys/v1/introspect", json_body={"apiKey": opencloud.api_key()}, auth=False
    )
    if info.get("enabled") is False or info.get("expired"):
        sys.exit("The API key is disabled or expired: re-enable it on the Creator Dashboard API Keys page.")
    owner = info.get("authorizedUserId")
    if not owner:
        sys.exit("Couldn't tell who owns the API key; set ROBLOX_CREATOR_USER_ID.")
    return str(owner)


def creator(dry_run):
    user = opencloud.env("ROBLOX_CREATOR_USER_ID", required=False)
    group = opencloud.env("ROBLOX_CREATOR_GROUP_ID", required=False)
    if user and group:
        sys.exit("Set ROBLOX_CREATOR_USER_ID or ROBLOX_CREATOR_GROUP_ID, not both.")
    if group:
        return {"groupId": numeric("ROBLOX_CREATOR_GROUP_ID", group)}
    if user:
        return {"userId": numeric("ROBLOX_CREATOR_USER_ID", user)}
    if dry_run:
        return {"userId": "<the API key's owner>"}
    owner = key_owner()
    print(f"Uploading as user {owner} (the key's owner). If the game belongs to a group, set ROBLOX_CREATOR_GROUP_ID.")
    return {"userId": owner}


def upload(path, update_id, dry_run):
    content_type = FILE_TYPES.get(path.suffix.lower())
    if not content_type:
        sys.exit(f"{path.name}: upload a .glb, .gltf or .fbx file")
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        sys.exit(f"{path.name} is {len(data):,} bytes; Roblox takes at most {MAX_BYTES:,} per upload")
    if update_id:
        method, url = "PATCH", f"{ASSETS}/assets/{update_id}"
        meta = {"assetId": str(update_id)}
    else:
        method, url = "POST", f"{ASSETS}/assets"
        meta = {
            "assetType": "Model",
            "displayName": DISPLAY_NAME,
            "description": DESCRIPTION,
            "creationContext": {"creator": creator(dry_run)},
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
    deadline = time.time() + PROCESS_SECONDS
    delay = 1
    while not operation.get("done"):
        if time.time() > deadline:
            sys.exit(f"Roblox is still processing the upload (operation {operation_id}); try again later")
        time.sleep(delay)
        delay = min(delay * 2, 15)
        operation = opencloud.request("GET", f"{ASSETS}/operations/{operation_id}")
    if operation.get("error"):
        sys.exit(f"Roblox couldn't process the upload: {json.dumps(operation['error'])}")
    return operation.get("response") or {}


def moderation(asset):
    """'Approved', 'Reviewing', 'Rejected' or 'Unknown' (the API spells them MODERATION_STATE_APPROVED etc.)."""
    state = str((asset.get("moderationResult") or {}).get("moderationState") or "")
    state = state.upper().removeprefix("MODERATION_STATE_")
    return {"APPROVED": "Approved", "REVIEWING": "Reviewing", "REJECTED": "Rejected"}.get(state, "Unknown")


def wait_for_approval(asset_id, state):
    deadline = time.time() + APPROVAL_SECONDS
    delay = 5
    while state in ("Reviewing", "Unknown") and time.time() < deadline:
        time.sleep(delay)
        delay = min(delay * 2, 30)
        state = moderation(opencloud.request("GET", f"{ASSETS}/assets/{asset_id}"))
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", type=pathlib.Path, default=PACK, help="model file to upload (default: StormlingPets.glb)")
    parser.add_argument("--update", action="store_true", help="upload a new version of the model already in GameConfig")
    parser.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    parser.add_argument("--no-config", action="store_true", help="don't write the asset id into GameConfig")
    parser.add_argument("--no-wait", action="store_true", help="don't wait for Roblox to approve the model")
    args = parser.parse_args()

    path = args.file.resolve()
    if not path.is_file():
        sys.exit(f"{path} not found; run python tools/pets/build_pets.py --no-render first")
    update_id = configured_asset_id() if args.update else 0
    if args.update and not update_id:
        sys.exit("GameConfig.PetMeshAssetId is 0, so there's nothing to update; run without --update")

    try:
        operation = upload(path, update_id, args.dry_run)
        if operation is None:
            return
        asset = wait_for(operation)
        asset_id = int(asset.get("assetId") or update_id or 0)
        if not asset_id:
            sys.exit(f"Roblox didn't return an asset id: {json.dumps(asset)}")
        state = moderation(asset)
        if not args.no_wait:
            state = wait_for_approval(asset_id, state)
    except opencloud.ApiError as error:
        hint = ""
        if error.status in (401, 403):
            hint = " Check ROBLOX_API_KEY and that the key has the assets API with Read and Write."
        elif "moderated" in str(error):
            hint = " Roblox's text filter rejected the model's name or description."
        sys.exit(f"upload failed: {error}.{hint}")

    print(f"{'Updated' if update_id else 'Uploaded'} {path.name} as model {asset_id} (moderation: {state})")
    print(f"  https://create.roblox.com/store/asset/{asset_id}")
    if state == "Rejected":
        sys.exit("Roblox rejected the model, so GameConfig was not changed.")
    if not args.no_config:
        write_asset_id(asset_id)
        print(f"  GameConfig.PetMeshAssetId = {asset_id}")
    if state != "Approved":
        print("  Roblox is still reviewing it; the pets switch to the meshes on servers started after approval.")


if __name__ == "__main__":
    main()
