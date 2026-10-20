"""Runs tests/mock/FullBoot.luau: the whole server boot and a player's client in tools/preview_map.py's mock runtime.

preview_map.py bundles the server code only and runs one service; the full-boot test also needs the client
modules (StarterPlayer, which preview_map leaves out) and the real src/server/Main.server.luau, which it
gets here as the ModuleScript ServerScriptService.Server.MainBoot (FullBoot requires it to boot every service
in Main.server's order, with its pcalls). Prints preview_map's output; the world dump (world.json in --out)
holds the BOOTTEST lines that tests/mock/run_mock_tests.py reads.

    python3 tests/mock/full_boot.py --out /tmp/boot [--no-pack] [--luau PATH]
    (any other preview_map.py option is passed on, e.g. --shot "...", without --dump-only, to render it)
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import preview_map  # noqa: E402

preview_map.SKIP_SOURCES = ()  # the client modules too: FullBoot runs the player's client

_build_bundle = preview_map.build_bundle


def build_bundle(args, pack):
    text = _build_bundle(args, pack)
    with open(os.path.join(ROOT, "src", "server", "Main.server.luau"), encoding="utf-8") as handle:
        main = handle.read()
    module = ('__mock.Module("ServerScriptService/Server/MainBoot", "src/server/Main.server.luau", '
              + preview_map.long_string(main + "\nreturn true") + ")\n")
    index = text.rindex("__mock.Run(")
    return text[:index] + module + text[index:]


preview_map.build_bundle = build_bundle


def main(argv):
    options = ["--script", os.path.join(ROOT, "tests", "mock", "FullBoot.luau"), "--keep-going", "--sim-seconds", "300"]
    if "--shot" not in argv and "--region" not in argv:
        options.append("--dump-only")
    preview_map.main(options + argv)


if __name__ == "__main__":
    main(sys.argv[1:])
