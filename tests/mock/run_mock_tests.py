"""Runs the Luau mock tests for the pet mesh pack outside Roblox.

Bundles tests/mock/RobloxMock.luau, the game modules under test and the spec into one script and runs
it with the `luau` command line (https://github.com/luau-lang/luau/releases). Set LUAU=path/to/luau if
it isn't on your PATH.

    python tests/mock/run_mock_tests.py
"""

import os
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
}
SPECS = ["PetMeshes.spec.luau"]


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def bundle(spec):
    chunks = [read(os.path.join(MOCK, "RobloxMock.luau")), "local __sources = {}"]
    for name, path in MODULES.items():
        chunks.append(f'__sources["{name}"] = function(script)\n{read(os.path.join(ROOT, path))}\nend')
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
