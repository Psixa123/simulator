"""Uploads a model file to Roblox and points the game at it.

Uploads a .glb, .gltf or .fbx file as a Model asset through the Open Cloud Assets API, waits for Roblox to
process and approve it, and writes the new asset id into GameConfig.<config key> (the line
"GameConfig.<key> = <number>" in src/shared/Config/GameConfig.luau). The game inserts the model at server
start (pets: PetMeshService with PetMeshAssetId; map props: WorldProps with WorldPropsAssetId). Run it
again after changing the model (it uploads a new model).

Needs (environment variables, see tools/roblox/README.md):
    ROBLOX_API_KEY           Open Cloud API key with the "assets" API, Read + Write
    ROBLOX_CREATOR_GROUP_ID  only if the game belongs to a group: the model must have the same owner as
                             the game. Otherwise the model goes to the key's owner (or set
                             ROBLOX_CREATOR_USER_ID).

    python tools/roblox/upload_model.py --file assets/models/StormWorldProps.glb \\
        --config-key WorldPropsAssetId --name "Storm World Props" \\
        --description "Map props for Storm Catcher Simulator"
    ... --dry-run     show what would be sent
    ... --update      new version of the model in GameConfig.<key> (same id; Roblox only documents this
                      for .fbx files)
    ... --no-config   don't write the id into GameConfig (also when --config-key is left out)
    ... --no-wait     don't wait for Roblox to approve the model

tools/roblox/upload_pets.py is this script with the pet pack's file, key, name and description filled in.
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
GAME_CONFIG = ROOT / "src" / "shared" / "Config" / "GameConfig.luau"
ASSETS = f"{opencloud.API}/assets/v1"
FILE_TYPES = {".glb": "model/gltf-binary", ".gltf": "model/gltf+json", ".fbx": "model/fbx"}
MAX_BYTES = 20 * 1024 * 1024
MAX_NAME = 50  # Roblox's limits for an asset's display name and description
MAX_DESCRIPTION = 1000
PROCESS_SECONDS = 900
APPROVAL_SECONDS = 600
# How to make the repository's model files when they are missing
BUILD_HINTS = {
    "StormlingPets.glb": "run python tools/pets/build_pets.py --no-render first",
    "StormWorldProps.glb": "run python tools/world/build_world_pack.py first",
}


# ------------------------------------------------------------------------------ GameConfig


def config_line(key):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        sys.exit(f"--config-key must be a GameConfig field name like WorldPropsAssetId, got {key!r}")
    return re.compile(rf"^(GameConfig\.{key}\s*=\s*)(\d+)", re.M)


def read_config():
    return GAME_CONFIG.read_bytes().decode("utf-8")  # bytes keep the file's line endings on Windows


def configured_asset_id(key):
    match = config_line(key).search(read_config())
    if not match:
        sys.exit(f"can't find 'GameConfig.{key} = <number>' in {GAME_CONFIG}")
    return int(match.group(2))


def write_asset_id(key, asset_id):
    text = read_config()
    new_text, count = config_line(key).subn(lambda m: m.group(1) + str(asset_id), text, count=1)
    if count != 1:
        sys.exit(f"can't find 'GameConfig.{key} = <number>' in {GAME_CONFIG}")
    if new_text != text:
        GAME_CONFIG.write_bytes(new_text.encode("utf-8"))


# ------------------------------------------------------------------------------ Open Cloud


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


def upload(path, update_id, dry_run, name, description):
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
            "displayName": name,
            "description": description,
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
    state = state.upper()
    if state.startswith("MODERATION_STATE_"):
        state = state[len("MODERATION_STATE_") :]
    return {"APPROVED": "Approved", "REVIEWING": "Reviewing", "REJECTED": "Rejected"}.get(state, "Unknown")


def wait_for_approval(asset_id, state):
    deadline = time.time() + APPROVAL_SECONDS
    delay = 5
    while state in ("Reviewing", "Unknown") and time.time() < deadline:
        time.sleep(delay)
        delay = min(delay * 2, 30)
        state = moderation(opencloud.request("GET", f"{ASSETS}/assets/{asset_id}"))
    return state


# ------------------------------------------------------------------------------ the whole upload


def run(
    path,
    *,
    config_key=None,
    name,
    description,
    update=False,
    dry_run=False,
    no_config=False,
    no_wait=False,
    missing_hint=None,
    pending_note="servers started after approval load it.",
):
    """Uploads `path` (or a new version of the model in GameConfig.<config_key> with update=True), waits
    for approval and writes the asset id into GameConfig.<config_key> (unless no_config or no key)."""
    path = pathlib.Path(path).resolve()
    if not path.is_file():
        hint = missing_hint or BUILD_HINTS.get(path.name)
        sys.exit(f"{path} not found" + (f"; {hint}" if hint else ""))
    if not name.strip() or len(name) > MAX_NAME:
        sys.exit(f"the model's name must be 1-{MAX_NAME} characters, got {name!r}")
    if len(description) > MAX_DESCRIPTION:
        sys.exit(f"the description must be at most {MAX_DESCRIPTION} characters")
    write_config = bool(config_key) and not no_config
    if config_key:
        # Fails before uploading anything if the key isn't in GameConfig
        current_id = configured_asset_id(config_key)
    elif update:
        sys.exit("--update needs --config-key: the model to update is the one in GameConfig.<key>")
    update_id = current_id if update else 0
    if update and not update_id:
        sys.exit(f"GameConfig.{config_key} is 0, so there's nothing to update; run without --update")

    asset_id = 0
    try:
        operation = upload(path, update_id, dry_run, name, description)
        if operation is None:
            return None
        asset = wait_for(operation)
        asset_id = int(asset.get("assetId") or update_id or 0)
        if not asset_id:
            sys.exit(f"Roblox didn't return an asset id: {json.dumps(asset)}")
        state = moderation(asset)
        if not no_wait and state in ("Reviewing", "Unknown"):
            print(f"Model {asset_id} uploaded; waiting for Roblox to approve it...")
            state = wait_for_approval(asset_id, state)
    except opencloud.ApiError as error:
        if asset_id:
            fix = f"Set GameConfig.{config_key} = {asset_id} by hand, or run" if write_config else "Run"
            sys.exit(f"Model {asset_id} was uploaded, but checking on it failed ({error}). {fix} again (that uploads another copy).")
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
    if write_config:
        write_asset_id(config_key, asset_id)
        print(f"  GameConfig.{config_key} = {asset_id}")
    if state != "Approved":
        print(f"  Roblox is still reviewing it; {pending_note}")
    return asset_id


def add_common_flags(parser):
    """The flags upload_model.py and upload_pets.py share."""
    parser.add_argument("--update", action="store_true", help="upload a new version of the model already in GameConfig")
    parser.add_argument("--dry-run", action="store_true", help="print the request instead of sending it")
    parser.add_argument("--no-config", action="store_true", help="don't write the asset id into GameConfig")
    parser.add_argument("--no-wait", action="store_true", help="don't wait for Roblox to approve the model")


def default_name(path):
    """'StormWorldProps.glb' -> 'Storm World Props'"""
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", pathlib.Path(path).stem).replace("_", " ").replace("-", " ")
    return " ".join(words.split())[:MAX_NAME] or "Model"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", type=pathlib.Path, required=True, help="model file to upload (.glb, .gltf or .fbx)")
    parser.add_argument("--config-key", help="GameConfig field to write the asset id into, e.g. WorldPropsAssetId")
    parser.add_argument("--name", help="the model's name on Roblox (default: from the file name)")
    parser.add_argument("--description", default="Model for Storm Catcher Simulator", help="the model's description on Roblox")
    add_common_flags(parser)
    args = parser.parse_args(argv)
    if not args.config_key and not args.no_config and not args.dry_run:
        print("No --config-key given, so the asset id is only printed (not written into GameConfig).")
    run(
        args.file,
        config_key=args.config_key,
        name=args.name or default_name(args.file),
        description=args.description,
        update=args.update,
        dry_run=args.dry_run,
        no_config=args.no_config,
        no_wait=args.no_wait,
    )


if __name__ == "__main__":
    main()
