"""Uploads the 3D UI icons to Roblox and writes their ids into src/client/UI/Icons.luau.

Every assets/ui/icons3d/<Key>.png whose key has a line "<Key> = { Id = <number>, ..." in Icons.luau is
uploaded as an Image asset through the Open Cloud Assets API, and its id replaces the number (only icons
still at Id = 0, unless --force). The game shows "rbxassetid://<id>" for the key, and the emoji fallback
until the id is set. Roblox reviews each image; it shows in game once approved.

Needs the same environment as upload_model.py (see tools/roblox/README.md): ROBLOX_API_KEY with the
"assets" API (Read + Write), and ROBLOX_CREATOR_GROUP_ID if the game belongs to a group.

    python tools/roblox/upload_icons.py              # upload every icon still at Id = 0
    python tools/roblox/upload_icons.py --only Volts,Pets --force
    python tools/roblox/upload_icons.py --dry-run
"""

import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import opencloud  # noqa: E402
import upload_model  # noqa: E402

ROOT = opencloud.ROOT
ICONS_DIR = ROOT / "assets" / "ui" / "icons3d"
ICONS_LUAU = ROOT / "src" / "client" / "UI" / "Icons.luau"
LINE = r"^(\s*{key}\s*=\s*\{{\s*Id\s*=\s*)(\d+)"
MAX_BYTES = 20 * 1024 * 1024


def read_icons():
    return ICONS_LUAU.read_bytes().decode("utf-8")  # bytes keep the file's line endings


def current_id(text, key):
    match = re.search(LINE.format(key=re.escape(key)), text, re.M)
    return int(match.group(2)) if match else None


def write_id(key, asset_id):
    text = read_icons()
    new_text, count = re.subn(
        LINE.format(key=re.escape(key)), lambda m: m.group(1) + str(asset_id), text, count=1, flags=re.M
    )
    if count != 1:
        sys.exit(f"can't find '{key} = {{ Id = <number>' in {ICONS_LUAU}")
    ICONS_LUAU.write_bytes(new_text.encode("utf-8"))


def upload_image(path, key, creator):
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        sys.exit(f"{path.name} is {len(data):,} bytes; Roblox takes at most {MAX_BYTES:,}")
    meta = {
        "assetType": "Image",
        "displayName": f"Storm Catcher icon {key}"[: upload_model.MAX_NAME],
        "description": "UI icon for Storm Catcher Simulator",
        "creationContext": {"creator": creator},
    }
    body, content_type = opencloud.multipart(
        [("request", None, None, json.dumps(meta).encode()), ("fileContent", path.name, "image/png", data)]
    )
    operation = opencloud.request("POST", f"{upload_model.ASSETS}/assets", body=body, content_type=content_type)
    asset = upload_model.wait_for(operation)
    asset_id = int(asset.get("assetId") or 0)
    if not asset_id:
        sys.exit(f"Roblox didn't return an asset id for {key}: {json.dumps(asset)}")
    return asset_id, upload_model.moderation(asset)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated icon keys (default: every icon)")
    parser.add_argument("--force", action="store_true", help="upload again even if Icons.luau already has an id")
    parser.add_argument("--dry-run", action="store_true", help="list what would be uploaded")
    args = parser.parse_args()

    text = read_icons()
    pictures = {p.stem: p for p in sorted(ICONS_DIR.glob("*.png")) if not p.stem.startswith("_")}
    keys = [k.strip() for k in args.only.split(",")] if args.only else sorted(pictures)
    todo = []
    for key in keys:
        if key not in pictures:
            sys.exit(f"no picture assets/ui/icons3d/{key}.png")
        existing = current_id(text, key)
        if existing is None:
            print(f"  skip {key}: no '{key} = {{ Id = ...' line in Icons.luau")
        elif existing > 0 and not args.force:
            print(f"  skip {key}: already uploaded ({existing})")
        else:
            todo.append(key)
    if not todo:
        print("Nothing to upload.")
        return
    if args.dry_run:
        print("Would upload: " + ", ".join(todo))
        return

    creator = upload_model.creator(False)
    reviewing = []
    for key in todo:
        try:
            asset_id, state = upload_image(pictures[key], key, creator)
        except opencloud.ApiError as error:
            sys.exit(f"upload of {key} failed: {error} (icons uploaded so far are already saved in Icons.luau)")
        write_id(key, asset_id)  # saved right away, so a later failure keeps the earlier ids
        print(f"  {key}: image {asset_id} ({state})")
        if state != "Approved":
            reviewing.append(key)
    print(f"Uploaded {len(todo)} icons; ids written to {ICONS_LUAU.relative_to(ROOT)}.")
    if reviewing:
        print(f"  Roblox is still reviewing {len(reviewing)}; they show in game (instead of the emoji) once approved.")


if __name__ == "__main__":
    main()
