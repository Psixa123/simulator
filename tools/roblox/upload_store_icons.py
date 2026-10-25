"""Uploads the store art to Roblox as Image assets and writes each id into the game code.

* Badges: assets/gamepasses/<Key>.png and assets/products/<Key>.png (rendered by tools/render_art.py from
  assets/source/badge.html) for every key of Monetization.Gamepasses / Monetization.Products. The id goes
  into that entry in src/shared/Config/Monetization.luau as a line `Image = <id>, -- <picture>` right under
  its `Id = ...,` line; the Shop panel shows it as the item's card art.
* Shop art: assets/ui/shop/<Key>.png for every `<Key> = <number>,` line of the ART table in
  src/client/UI/Panels/Shop.luau (the sunburst behind the cards and the Robux glyph on the buy buttons).

Pictures whose id is still missing or 0 are uploaded (all of them with --force). Every id is written as
soon as its upload finishes, so an interrupted run keeps what it already uploaded. Roblox reviews each
image; the game shows it once approved (until then the Shop draws its 3D icon instead). This doesn't
change the icons of the passes and products themselves on the Creator Dashboard: upload the same PNGs
there when you create them (see docs/STORE_LISTING.md).

Needs the same environment as upload_icons.py (see tools/roblox/README.md): ROBLOX_API_KEY with the
"assets" API (Read + Write), and ROBLOX_CREATOR_GROUP_ID if the game belongs to a group.

    python tools/roblox/upload_store_icons.py              # upload every picture without an id yet
    python tools/roblox/upload_store_icons.py --only AuroraGryphon,VIP --force
    python tools/roblox/upload_store_icons.py --dry-run    # list what would be uploaded
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
MONETIZATION = ROOT / "src" / "shared" / "Config" / "Monetization.luau"
SHOP = ROOT / "src" / "client" / "UI" / "Panels" / "Shop.luau"
BADGE_DIRS = {"Gamepasses": ROOT / "assets" / "gamepasses", "Products": ROOT / "assets" / "products"}
ART_DIR = ROOT / "assets" / "ui" / "shop"
MAX_BYTES = 20 * 1024 * 1024


def read(path):
    return path.read_bytes().decode("utf-8")  # bytes keep the file's line endings


def write(path, text):
    path.write_bytes(text.encode("utf-8"))


def table_span(text, opener):
    """(start, end) of the table that starts with the line `opener` and ends at the next line `}`."""
    start = text.find(opener)
    if start < 0:
        return None
    end = re.compile(r"^\}", re.M).search(text, start)
    return start, (end.start() if end else len(text))


# ------------------------------------------------------------------------------------- Monetization.luau

def monetization_keys(text):
    """[(table, key)] for every entry of Monetization.Gamepasses and Monetization.Products."""
    keys = []
    for table in BADGE_DIRS:
        span = table_span(text, f"Monetization.{table} = {{")
        if span:
            for match in re.finditer(r"^\t(\w+)\s*=\s*\{[ \t]*$", text[span[0]:span[1]], re.M):
                keys.append((table, match.group(1)))
    return keys


def entry_span(text, table, key):
    """(start, end) of `<key> = { ... }` inside Monetization.<table>, or None."""
    span = table_span(text, f"Monetization.{table} = {{")
    if not span:
        return None
    head = re.compile(rf"^(\t){re.escape(key)}\s*=\s*\{{[ \t]*$", re.M).search(text, span[0], span[1])
    if not head:
        return None
    tail = re.compile(r"^\t\},?", re.M).search(text, head.end(), span[1])
    return head.start(), (tail.start() if tail else span[1])


IMAGE_LINE = re.compile(r"^([ \t]*)Image\s*=\s*(\d+)[^\n]*$", re.M)
ID_LINE = re.compile(r"^([ \t]*)Id\s*=\s*\d+\s*,[^\n]*$", re.M)


def badge_id(text, table, key):
    span = entry_span(text, table, key)
    if not span:
        return None
    match = IMAGE_LINE.search(text, span[0], span[1])
    return int(match.group(2)) if match else 0


def write_badge_id(table, key, asset_id, picture):
    text = read(MONETIZATION)  # read again right before writing: other people edit this file too
    span = entry_span(text, table, key)
    if not span:
        sys.exit(f"can't find '{key} = {{' in Monetization.{table} ({MONETIZATION.relative_to(ROOT)})")
    existing = IMAGE_LINE.search(text, span[0], span[1])
    if existing:
        line = f"{existing.group(1)}Image = {asset_id}, -- {picture}"
        text = text[: existing.start()] + line + text[existing.end():]
    else:
        id_line = ID_LINE.search(text, span[0], span[1])
        if not id_line:
            sys.exit(f"Monetization.{table}.{key} has no 'Id = <number>,' line to put the Image under")
        newline = "\r\n" if "\r\n" in text else "\n"
        line = f"{newline}{id_line.group(1)}Image = {asset_id}, -- {picture}"
        text = text[: id_line.end()] + line + text[id_line.end():]
    write(MONETIZATION, text)


# ------------------------------------------------------------------------------------- Shop.luau ART

ART_OPENER = "local ART = {"


def art_line(key):
    return re.compile(rf"^([ \t]*){re.escape(key)}\s*=\s*(\d+)\s*,[^\n]*$", re.M)


def art_id(text, key):
    span = table_span(text, ART_OPENER)
    match = span and art_line(key).search(text, span[0], span[1])
    return int(match.group(2)) if match else None


def write_art_id(key, asset_id, picture):
    text = read(SHOP)
    span = table_span(text, ART_OPENER)
    match = span and art_line(key).search(text, span[0], span[1])
    if not match:
        sys.exit(f"can't find '{key} = <number>,' in the ART table of {SHOP.relative_to(ROOT)}")
    line = f"{match.group(1)}{key} = {asset_id}, -- {picture}"
    write(SHOP, text[: match.start()] + line + text[match.end():])


# ------------------------------------------------------------------------------------- upload

def upload_image(path, key, creator):
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        sys.exit(f"{path.name} is {len(data):,} bytes; Roblox takes at most {MAX_BYTES:,}")
    meta = {
        "assetType": "Image",
        "displayName": f"Storm Catcher shop {key}"[: upload_model.MAX_NAME],
        "description": "Shop art for Storm Catcher Simulator",
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


def collect():
    """{key: (picture path, current id or None, writer)} for every badge and every piece of shop art."""
    items = {}
    money = read(MONETIZATION)
    for table, key in monetization_keys(money):
        picture = BADGE_DIRS[table] / f"{key}.png"
        if picture.is_file():
            rel = picture.relative_to(ROOT).as_posix()
            items[key] = (picture, badge_id(money, table, key), lambda i, t=table, k=key, r=rel: write_badge_id(t, k, i, r))
    shop = read(SHOP)
    for picture in sorted(ART_DIR.glob("*.png")) if ART_DIR.is_dir() else []:
        key = picture.stem
        rel = picture.relative_to(ROOT).as_posix()
        items.setdefault(key, (picture, art_id(shop, key), lambda i, k=key, r=rel: write_art_id(k, i, r)))
    return items


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated keys (pass / product keys or shop art names; default: all)")
    parser.add_argument("--force", action="store_true", help="upload again even if the code already has an id")
    parser.add_argument("--dry-run", action="store_true", help="list what would be uploaded")
    args = parser.parse_args()

    items = collect()
    keys = [k.strip() for k in args.only.split(",") if k.strip()] if args.only else list(items)
    todo = []
    for key in keys:
        if key not in items:
            sys.exit(f"no picture for '{key}' (assets/gamepasses, assets/products or assets/ui/shop, with a "
                     f"matching Monetization entry or Shop ART line)")
        picture, existing, _ = items[key]
        if existing is None:
            print(f"  skip {key}: no '{key} = <number>,' line in the ART table of Shop.luau")
        elif existing > 0 and not args.force:
            print(f"  skip {key}: already uploaded ({existing})")
        else:
            todo.append(key)
    if not todo:
        print("Nothing to upload.")
        return
    if args.dry_run:
        for key in todo:
            print(f"  would upload {items[key][0].relative_to(ROOT).as_posix()}")
        print(f"Would upload {len(todo)} pictures.")
        return

    creator = upload_model.creator(False)
    reviewing = []
    touched = set()
    for key in todo:
        picture, _, save = items[key]
        try:
            asset_id, state = upload_image(picture, key, creator)
        except opencloud.ApiError as error:
            sys.exit(f"upload of {key} failed: {error} (the pictures uploaded before it are already saved)")
        save(asset_id)  # saved right away, so a later failure keeps the earlier ids
        touched.add((SHOP if picture.parent == ART_DIR else MONETIZATION).relative_to(ROOT).as_posix())
        print(f"  {key}: image {asset_id} ({state})")
        if state != "Approved":
            reviewing.append(key)
    print(f"Uploaded {len(todo)} pictures; ids written to {' and '.join(sorted(touched))}.")
    if reviewing:
        print(f"  Roblox is still reviewing {len(reviewing)}; they show in game once approved.")


if __name__ == "__main__":
    main()
