"""Builds the game with Rojo and publishes it to a Roblox place through Open Cloud.

This replaces the whole place with what is in this repository (the same as opening a fresh
`rojo build` in Studio and publishing): anything added to the place only in Studio is gone afterwards.
Experience settings, the icon, thumbnails, gamepasses and developer products are not part of the place
and stay as they are.

The game must have been published from Studio once (Open Cloud can only update an existing place).

Needs (environment variables, see tools/roblox/README.md):
    ROBLOX_API_KEY      Open Cloud API key with the "universe-places" API, Write
    ROBLOX_PLACE_ID     the place id (the number in the game's roblox.com URL)
    ROBLOX_UNIVERSE_ID  optional: the experience (universe) id, looked up from the place id if not set

    python tools/roblox/publish_place.py --yes          # build and publish (live servers get it)
    python tools/roblox/publish_place.py --yes --saved  # save a new version without publishing it
    python tools/roblox/publish_place.py --dry-run      # build and show what would be sent
"""

import argparse
import pathlib
import shutil
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import opencloud  # noqa: E402

ROOT = opencloud.ROOT
PROJECT = ROOT / "default.project.json"
OUTPUT = ROOT / "build" / "StormCatcher.rbxl"
MAX_BYTES = 100 * 1024 * 1024


def build(output):
    rojo = shutil.which("rojo")
    if not rojo:
        sys.exit("rojo not found on PATH (https://rojo.space)")
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([rojo, "build", str(PROJECT), "-o", str(output)], check=True, cwd=ROOT)
    return output


def numeric_env(name, required=True):
    value = opencloud.env(name, required=required, hint="See tools/roblox/README.md.")
    if value and not value.isdigit():
        sys.exit(f"{name} must be a number, got {value!r}")
    return value


def universe_of(place):
    try:
        info = opencloud.request("GET", f"{opencloud.API}/universes/v1/places/{place}/universe", auth=False)
    except opencloud.ApiError as error:
        sys.exit(f"couldn't look up the experience of place {place} ({error}); set ROBLOX_UNIVERSE_ID")
    universe = str(info.get("universeId") or "")
    if not universe.isdigit():
        sys.exit(f"place {place} has no experience; check ROBLOX_PLACE_ID (publish the game from Studio once first)")
    return universe


HINTS = {
    401: "Check ROBLOX_API_KEY and that the key has the universe-places API with Write for this experience. "
    "If only publishing fails, try --saved and publish that version from Studio.",
    403: "Roblox doesn't allow publishing this place with this key (is the experience yours or your group's?).",
    404: "That place or experience doesn't exist; check ROBLOX_PLACE_ID / ROBLOX_UNIVERSE_ID.",
    409: "The place is open in Studio or Team Create: close it and try again in a couple of minutes "
    "(or the place isn't part of that experience).",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", type=pathlib.Path, help="publish this .rbxl instead of building one")
    parser.add_argument("--saved", action="store_true", help="save a version without publishing it to players")
    parser.add_argument("--dry-run", action="store_true", help="build, then print the request instead of sending it")
    parser.add_argument("--yes", action="store_true", help="confirm replacing the place's current version")
    args = parser.parse_args()

    if not args.dry_run:
        opencloud.api_key()  # fail before building if the key is missing
    place = numeric_env("ROBLOX_PLACE_ID")
    universe = numeric_env("ROBLOX_UNIVERSE_ID", required=False) or universe_of(place)
    path = args.file.resolve() if args.file else build(OUTPUT)
    if path.suffix.lower() != ".rbxl":
        sys.exit(f"{path.name}: publish a binary .rbxl place file")
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        sys.exit(f"{path.name} is {len(data):,} bytes; Roblox accepts at most {MAX_BYTES:,}")

    version_type = "Saved" if args.saved else "Published"
    url = f"{opencloud.API}/universes/v1/{universe}/places/{place}/versions?versionType={version_type}"
    if args.dry_run:
        print(f"POST {url}\n  body = {path.name} ({len(data):,} bytes, application/octet-stream)")
        return
    if not args.yes:
        sys.exit(f"This replaces place {place} with {path.name}. Run again with --yes to go ahead.")
    try:
        result = opencloud.request("POST", url, body=data, content_type="application/octet-stream")
    except opencloud.ApiError as error:
        sys.exit(f"publish failed: {error}. {HINTS.get(error.status, '')}".rstrip())
    print(f"{version_type} {path.name} as version {result.get('versionNumber', '?')} of place {place}")
    print(f"  https://www.roblox.com/games/{place}")


if __name__ == "__main__":
    main()
