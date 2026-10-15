"""Runs the Luau mock tests for the pet mesh pack, the server's pack loaders and WorldProps outside Roblox.

Bundles tests/mock/RobloxMock.luau, the game modules under test and the spec into one script and runs
it with the `luau` command line (https://github.com/luau-lang/luau/releases). Set LUAU=path/to/luau if
it isn't on your PATH.

    python tests/mock/run_mock_tests.py
"""

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
}
OPTIONAL = {"WorldPropsData"}
SPECS = ["PetMeshes.spec.luau", "PetMeshService.spec.luau", "WorldProps.spec.luau"]


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
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
