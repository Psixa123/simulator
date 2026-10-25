"""Runs the Luau mock tests for the pet mesh pack, the server's pack loaders, WorldProps, the admin commands
(AdminService) and the map outside Roblox.

Bundles tests/mock/RobloxMock.luau, the game modules under test and the spec into one script and runs
it with the `luau` command line (https://github.com/luau-lang/luau/releases). Set LUAU=path/to/luau if
it isn't on your PATH.

The map contract test (MapContracts.luau) needs the whole game tree and a far bigger Roblox mock, so it
runs through tools/preview_map.py (its mock runtime, no browser), once with the prop pack and once without.
So does the full-boot test (FullBoot.luau, through tests/mock/full_boot.py): every server service booted by
the real Main.server.luau, a player joining, walking to zone 1 and vacuuming weather through the real
client controllers (desktop click and phone tap), dying and respawning; plus the map's boundary walls.

    python tests/mock/run_mock_tests.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOCK = os.path.join(ROOT, "tests", "mock")
MODULES = {
    "Pets": "src/shared/Config/Pets.luau",
    "PetModels": "src/shared/Models/PetModels.luau",
    "PetController": "src/client/Controllers/PetController.luau",
    "PetMeshService": "src/server/Services/PetMeshService.luau",
    "WorldProps": "src/server/Services/WorldProps.luau",
    "WorldPropsData": "src/shared/Config/WorldPropsData.luau",  # generated; optional
    # Admin.spec.luau: AdminService with the real configs and formulas
    "AdminService": "src/server/Services/AdminService.luau",
    "GameConfig": "src/shared/Config/GameConfig.luau",
    "Monetization": "src/shared/Config/Monetization.luau",
    "Zones": "src/shared/Config/Zones.luau",
    "Weather": "src/shared/Config/Weather.luau",
    "Formulas": "src/shared/Formulas.luau",
    "Format": "src/shared/Util/Format.luau",
    # Purchase.spec.luau: the lobby shop pet's receipt through the real MonetizationService and PetService
    "MonetizationService": "src/server/Services/MonetizationService.luau",
    "PetService": "src/server/Services/PetService.luau",
    "MapLayout": "src/shared/Config/MapLayout.luau",
}
OPTIONAL = {"WorldPropsData"}
SPECS = ["PetMeshes.spec.luau", "PetMeshService.spec.luau", "WorldProps.spec.luau", "Admin.spec.luau", "Purchase.spec.luau"]
MAP_SPEC = "MapContracts.luau"


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def module_source(path):
    # Each module becomes a function body, where Luau only allows local type aliases
    return re.sub(r"^export type ", "type ", read(path), flags=re.M)


def bundle(spec):
    chunks = [read(os.path.join(MOCK, "RobloxMock.luau")), "local __sources = {}"]
    for name, path in MODULES.items():
        path = os.path.join(ROOT, path)
        if name in OPTIONAL and not os.path.exists(path):
            continue
        chunks.append(f'__sources["{name}"] = function(script)\n{module_source(path)}\nend')
    chunks.append(read(os.path.join(MOCK, spec)))
    return "\n".join(chunks)


def run_map_test(luau, label, extra):
    """MapService contract test in the preview tool's mock runtime; returns True when it passed."""
    with tempfile.TemporaryDirectory() as out:
        command = [sys.executable, os.path.join(ROOT, "tools", "preview_map.py"), "--script",
                   os.path.join(MOCK, MAP_SPEC), "--dump-only", "--no-start", "--keep-going", "--luau", luau,
                   "--out", out] + extra
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        world_path = os.path.join(out, "world.json")
        if result.returncode != 0 or not os.path.exists(world_path):
            print(result.stdout + result.stderr)
            print(f"Map contract test ({label}): the mock run failed")
            return False
        with open(world_path, encoding="utf-8") as handle:
            world = json.load(handle)
    prints = [str(line) for line in world.get("Prints", [])]
    problems = [line for line in prints if line.startswith("MAPTEST FAIL")]
    problems += [f"ERROR {error}" for error in world.get("Errors", [])]
    problems += [f"MOCK GAP {gap['Message']}" for gap in world.get("Gaps", []) if not gap.get("Maybe")]
    if world.get("Terrain", {}).get("Fills"):
        problems.append(f"FAIL the map uses Roblox Terrain ({len(world['Terrain']['Fills'])} fills)")
    done = [line for line in prints if line.startswith("MAPTEST DONE")]
    parts = [line.split()[-1] for line in prints if line.startswith("MAPTEST PARTS")]
    if not done:
        problems.append("FAIL the contract checks did not finish")
    for problem in problems:
        print(problem)
    summary = done[0][len("MAPTEST DONE "):] if done else "did not finish"
    print(f"Map contract test ({label}): {summary}, {parts[0] if parts else '?'} parts")
    return not problems


def run_boot_test(luau, label, extra):
    """The full-boot simulation (tests/mock/full_boot.py); returns True when it passed."""
    with tempfile.TemporaryDirectory() as out:
        command = [sys.executable, os.path.join(MOCK, "full_boot.py"), "--luau", luau, "--out", out] + extra
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        world_path = os.path.join(out, "world.json")
        if result.returncode != 0 or not os.path.exists(world_path):
            print(result.stdout + result.stderr)
            print(f"Full-boot test ({label}): the mock run failed")
            return False
        with open(world_path, encoding="utf-8") as handle:
            world = json.load(handle)
    prints = [str(line) for line in world.get("Prints", [])]
    problems = [line for line in prints if line.startswith("BOOTTEST FAIL")]
    done = [line for line in prints if line.startswith("BOOTTEST DONE")]
    if not done:
        problems.append("FAIL the full-boot scenario did not finish")
    for problem in problems:
        print(problem)
    summary = done[0][len("BOOTTEST DONE "):] if done else "did not finish"
    print(f"Full-boot test ({label}): {summary}")
    return not problems


def main():
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        sys.exit("luau not found: install it or set LUAU=path/to/luau")
    failed = False
    with tempfile.TemporaryDirectory() as folder:
        for spec in SPECS:
            path = os.path.join(folder, spec.replace(".spec", ".bundle"))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(bundle(spec))
            result = subprocess.run([luau, path])
            failed = failed or result.returncode != 0
    luau_path = os.path.abspath(luau) if os.path.exists(luau) else luau
    for label, extra in (("with the prop pack", []), ("part-built props only", ["--no-pack"])):
        failed = not run_map_test(luau_path, label, extra) or failed
    for label, extra in (("with the prop pack", []), ("part-built props only", ["--no-pack"])):
        failed = not run_boot_test(luau_path, label, extra) or failed
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
