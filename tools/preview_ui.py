#!/usr/bin/env python3
"""Renders the game's real Roblox interface without Roblox, so UI work can be checked visually.

Runs the real client code - src/client/Main.client.luau with UI/UI.luau, UI/Theme.luau, the Panels and
Overlays, and the HUD built by Controllers/InterfaceController.luau + HudController.luau (and the other
controllers that build interface: Monetization, MegaStorm, Objective, Radar, Sound) - under the `luau`
command line in a Roblox GUI mock (tools/ui_preview/*.luau), with realistic fake player data served by a
fake server. A layout pass computes every object's AbsolutePosition / AbsoluteSize like Roblox (UDim2,
AnchorPoint, SizeConstraint, UIScale, UIPadding, UIListLayout incl. flex and wrapping, UIGridLayout,
UIPageLayout, AutomaticSize, ScrollingFrame canvases, UIAspectRatioConstraint, UISizeConstraint,
UITextSizeConstraint, ZIndex, Visible, ClipsDescendants, Rotation, the top bar inset) and breaks text into
lines (TextScaled, TextWrapped, TextTruncate, RichText) with glyph metrics measured in Chromium. Then
tools/ui_preview/page.js paints it in headless Chromium - background x UIGradient (Rotation, transparency),
UICorner, UIStroke as a ring on frames and as an outline on text (emoji included), TextStrokeTransparency,
legacy borders, images, pet pictures in ViewportFrames, scroll bars, Fredoka One / Gotham, emoji - over a
sky-island backdrop with Roblox's own top bar, chat window and player list, and saves a PNG.

Usage (from the repo root):
    python3 tools/preview_ui.py                              HUD at 1280x720 -> build/ui_preview/hud.png
    python3 tools/preview_ui.py --panel Upgrades             open a panel (a module in src/client/UI/Panels: Shop Pets
                                                             Upgrades Rebirth Rewards Settings Teleport Egg)
                                                             -> build/ui_preview/Upgrades.png
    python3 tools/preview_ui.py --panel Shop --tab Volts     the panel's OnOpen argument: Shop/Pets/Rewards tab,
                                                             an egg id for Egg (--panel Egg --tab FrostEgg)
    python3 tools/preview_ui.py --screen 390x844 --panel Pets          a phone (portrait)
    python3 tools/preview_ui.py --screen desktop,phone --all           HUD + every panel on both screens
    python3 tools/preview_ui.py --panel Pets --click Grid/p2           select pet p2 (clicks, see --click)
    python3 tools/preview_ui.py --panel Pets --click Grid/p5 --click Detail/Delete   ... and open the confirm
    python3 tools/preview_ui.py --notify "Hatched Sunny!|Success" --notify "Need 6.55M Volts|Error"
    python3 tools/preview_ui.py --run "task.spawn(Registry.HatchOverlay.Play, {Egg = 'MeadowEgg',
        Results = {{Id = 'Sunny', New = true}, {Id = 'Droplet', Golden = true}}})" --settle 2.5
    python3 tools/preview_ui.py --run "Registry.InterfaceController.BigText('ZONE UNLOCKED!', nil, 'Dune Sea')"
    python3 tools/preview_ui.py --data new                   a first-time player (also: mid (default), late)
    python3 tools/preview_ui.py --data-json '{"Volts": 5, "Boosts": {"Luck": "+600"}}'   tweak the data
    python3 tools/preview_ui.py --panel Upgrades --compare docs/ui_mockup.png      side by side with the mockup
    python3 tools/preview_ui.py --blank --run-file tools/ui_preview/examples/skylab_kit.luau --bg none --no-core \
        --name skylab_kit --compare docs/ui_components.png     a component test without the game's client

Options:
    --screen S        WxH or a preset: desktop (1280x720), phone (390x844, portrait), phone-landscape (844x390),
                      tablet (1024x768); comma-separated for several. Screens under 600 px on the short side
                      and the presets phone/tablet are touch screens (TouchEnabled, no keyboard, no chat window,
                      the game's phone HUD scale); --touch / --no-touch override. Note: Roblox runs phones in
                      landscape unless StarterGui.ScreenOrientation says otherwise (the game doesn't), so
                      phone-landscape is what phone players see; phone (portrait) is the worst case.
    --inset N         Roblox top bar height (default 58, the current top bar)
    --safe-area L,R,B device safe-area insets in pixels (a notch: e.g. --screen 844x390 --safe-area 47,47,21);
                      ScreenGuis with ScreenInsets CoreUISafeInsets / DeviceSafeInsets keep out of them
    --panel NAME      open a panel after loading (InterfaceController.OpenPanel); --tab ARG is its OnOpen argument
    --all             render the HUD and every panel (one PNG each: hud, panel_<Name>)
    --click PATH      fire a GuiButton's MouseButton1Down/Up/Click and Activated, after --panel (repeatable, in
                      order). PATH is a suffix of the button's path under the PlayerGui, e.g. "Close",
                      "Pets/Content/Tabs/Index", "Grid/p3" (pet uid p3); visible buttons win. --tree lists paths.
    --run CODE        Luau run in the client after the clicks (repeatable). It sees Registry, UI, Theme, Client
                      (the client folder), PlayerGui, Data / ServerData (the player's data), Open(name, ...),
                      Click(path), Wait(s), SetData(key, value) (server-side change + DataChanged), FireClient(remote,
                      ...) (a server -> client event, e.g. FireClient("Effect", "MegaWarning")), and the Roblox globals
    --run-file FILE   the same, from a file
    --before CODE     Luau run before the client starts (repeatable; --before-file FILE): patch a module or the
                      data the UI is built from, e.g. "require(Client.UI.Icons).Volts.Image = 'assets/ui/Volts.png'"
                      to see an icon that isn't uploaded yet. Sees Client, ServerData, SetData, require, PlayerGui.
    --blank           don't start the game's client: an empty PlayerGui for --run snippets (component tests;
                      the game's modules can still be required, e.g. require(Client.UI.Viewport))
    --notify T|KIND   show a toast (Info, Success, Error, Warning, Reward)
    --data NAME       mid (default: zone 3, 12.4M Volts, 3 Climate Shifts, 15 pets incl. golden/rainbow, a boost,
                      a daily reward and a gift ready), new (DataService's defaults), late (all unlocked, maxed)
    --data-json J     JSON (or a .json file) merged over the data; "+N" / "-N" strings = now +- N seconds
    --studio          RunService:IsStudio() = true (Studio-only notes and test purchases show)
    --restricted      the player can't buy paid random items (Volts packs hidden)
    --loading         keep the loading screen up (the server never answers GetData)
    --stub LIST       controllers replaced with stand-ins (default: Effects,Vacuum,Pet,Zone,Hazard,World - they
                      drive the 3D world); "none" runs every controller for real; --real NAME takes one off
    --boot S          simulated seconds before the actions (default 2: the loading screen is gone)
    --settle S        simulated seconds after the last action (default 1). Tweens apply their end values when
                      played, so this is for task.delay / Completed handlers; toasts disappear after 3.4 s.
    --bg B            sky-island (default: tools/ui_preview/backdrop.svg, the world from docs/ui_mockup.html),
                      sky (plain gradient), none (checkerboard), or an image file in the repo
    --no-topbar       no Roblox top bar buttons; --no-chat: no chat window (desktop draws one, and the HUD moves
                      its menu below it like in game); --no-playerlist: no player list (desktop draws Roblox's
                      list with the leaderstats, top right); --no-core: none of Roblox's own UI (also the jump
                      button drawn on touch screens)
    --outline         debug: outline every drawn object with its name
    --compare IMG     also write <name>_compare.png: IMG (e.g. docs/ui_mockup.png) and the preview side by side
    --no-pet-renders  don't render missing pet pictures (see ViewportFrames below)
    --scale K         device pixel ratio of the PNG (default 1: one PNG pixel = one Roblox pixel)
    --out PATH        PNG file, or a folder (default build/ui_preview); --name NAME sets the file name
    --tree            print the PlayerGui tree (positions, sizes, text, text size) to the terminal
    --keep-going      render even when the client code raised errors or hit a mock gap
    --jobs N          renders in parallel (default 4)
    --luau PATH       the luau binary (default: $LUAU, then PATH); --timeout S per luau run (default 120)

Output (in --out):
    <name>.png        the screenshot (about 1 s per render after the first run)
    <name>.json       the PlayerGui tree: every ScreenGui / GuiObject with Position (= AbsolutePosition, GUI space:
                      y = 0 is the bottom of the top bar), Screen (x, y in PNG pixels), Size (= AbsoluteSize),
                      Visible / Shown, ZIndex, LayoutOrder, Text + TextSize (+ TextOverflows), Image, and the UI
                      components on it; plus Warnings, Errors, Gaps, Notes, Actions and Stats of the run
    cache/            metrics.json (font metrics), preview_bundle_<name>.luau (the Luau that ran), page data
    pets/             pet pictures rendered for ViewportFrames (cached)

What is mocked: Instance classes (strict for GUI classes: an unknown property or a wrong type fails like in
Roblox; permissive for parts / models / sounds), datatypes, Enum, Font, TweenService (end values applied when
Play is called, Completed fires after the tween's time), RunService (60 frames per simulated second, events,
BindToRenderStep), UserInputService, GuiService (GetGuiInset), TextService, HttpService (JSON), the other
services the client touches, remotes (a fake server answers GetData, SetSetting and Equip/Unequip; other calls
get {Ok = false}), and the player data. AbsoluteSize / AbsolutePosition change signals fire at the end of a
frame like in Roblox. Not drawn: BillboardGuis / SurfaceGuis (in-world), particles, the 3D world (the backdrop
stands in for it).
ViewportFrames: a pet is drawn with a picture of it, framed like Viewport.luau's camera: rendered on first use
with tools/pets/viewer.html (the pet mesh pack assets/models/StormlingPets.glb, game colours for Golden /
Rainbow; needs three.js in tools/pets, tools/world or tools/preview node_modules) into build/ui_preview/pets/,
else build/pets/<PetId>.png or docs/mockup/pets/<PetId>.png (tinted for Golden / Rainbow), else a cartoon
stand-in in the pet's colours. Undiscovered pets are silhouettes, eggs are drawn as eggs.
Images: rbxassetid://<id> is looked up in tools/ui_preview/asset_map.json ({"<id>": "assets/ui/Volts.png"}), then
in the game code: a line of src/**/*.luau holding the id and either a repo picture path or a key named like a
picture in assets/ui (`Volts = { Image = "rbxassetid://123456" }` -> assets/ui/Volts.png). An Image set to a
repo path (assets/ui/Volts.png) is drawn directly (preview only: Roblox needs an asset id, see --before);
anything else is a hatched placeholder (listed in the output).
Examples: tools/ui_preview/examples/skylab_kit.luau builds the Sky Lab kit (docs/ui_components.png) from plain
instances - candy buttons with lip and shine, cloud window header, tiles with pet viewports, capsules, round
HUD buttons, badges, toasts - and shows how a --run-file snippet is written.
Fonts: Fredoka One and Luckiest Guy from assets/source/fonts, Gotham drawn with Montserrat (tools/ui_preview/
fonts, the closest free face), other fonts with the system sans; emoji with the system emoji font.

When the client code uses something the mock lacks, the run stops with a message naming it and the game line
that used it (also when the game wrapped it in a pcall: MOCK GAP). Add it to tools/ui_preview (classes in
mock_instances.luau, services in mock_services.luau, layout / text in mock_layout.luau, the player data and
stand-ins in Boot.luau, drawing in page.js) and run again. A real Roblox error (bad property, wrong type) is
reported as ERROR with the game's file and line.

Requirements: luau (https://github.com/luau-lang/luau/releases, or LUAU=path), Chromium (Playwright's headless
shell in PLAYWRIGHT_BROWSERS_PATH, /opt/pw-browsers or ~/.cache/ms-playwright, a system Chrome, or CHROME_PATH),
Python 3.9+; Pillow is optional (crops pet pictures, --compare).
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "tools" / "ui_preview"
PARTS = ["mock_core.luau", "mock_instances.luau", "mock_layout.luau", "mock_services.luau"]
PROJECT = ROOT / "default.project.json"
OUT = ROOT / "build" / "ui_preview"
CLIENT = "StarterPlayer/StarterPlayerScripts/Client"
KNOWN_PANELS = ["Shop", "Pets", "Upgrades", "Rebirth", "Rewards", "Settings", "Teleport", "Egg"]
# the panels are the modules in src/client/UI/Panels (new ones are picked up by --all)
_found = sorted(f.name.split(".")[0] for f in (ROOT / "src" / "client" / "UI" / "Panels").glob("*.lua*"))
PANELS = [n for n in KNOWN_PANELS if n in _found] + [n for n in _found if n not in KNOWN_PANELS] or KNOWN_PANELS
DEFAULT_STUBS = ["EffectsController", "VacuumController", "PetController", "ZoneController", "HazardController", "WorldController"]
PRESETS = {
    "desktop": (1280, 720, False),
    "phone": (390, 844, True),
    "phone-landscape": (844, 390, True),
    "tablet": (1024, 768, True),
}
PET_ART_DIRS = [ROOT / "build" / "pets", ROOT / "docs" / "mockup" / "pets"]
FONT_FILES = [ROOT / "assets" / "source" / "fonts" / "FredokaOne-Regular.ttf", ROOT / "assets" / "source" / "fonts" / "LuckiestGuy-Regular.ttf",
              HERE / "fonts" / "Montserrat-latin.woff2", HERE / "metrics.html"]


# --------------------------------------------------------------------------------------- tools

def find_luau(explicit):
    for candidate in (explicit, os.environ.get("LUAU"), shutil.which("luau")):
        if candidate and os.path.exists(candidate):
            return candidate
    return None


def find_browser():
    candidates = [os.environ.get("CHROME_PATH", "")]
    browsers = os.environ.get("PLAYWRIGHT_BROWSERS_PATH")
    for base in ([browsers] if browsers else []) + ["/opt/pw-browsers", os.path.expanduser("~/.cache/ms-playwright")]:
        candidates += sorted(glob.glob(os.path.join(base, "chromium_headless_shell-*/chrome-linux/headless_shell")), reverse=True)
        candidates += sorted(glob.glob(os.path.join(base, "chromium-*/chrome-linux/chrome")), reverse=True)
    candidates += ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome",
                   r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    return None


THREE_DIRS = [ROOT / "tools" / d / "node_modules" for d in ("pets", "world", "preview")]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def translate_path(self, path):
        # tools/pets/viewer.html imports ./node_modules/three: serve it from whichever tools/* has it installed
        local = super().translate_path(path)
        marker = "/tools/pets/node_modules/"
        clean = path.split("?", 1)[0]
        if marker in clean and not os.path.exists(local):
            rest = clean.split(marker, 1)[1]
            for directory in THREE_DIRS:
                candidate = directory / rest
                if candidate.is_file():
                    return str(candidate)
        return local

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def start_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def chrome(browser, url, size, extra, timeout=120):
    command = [browser, "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
               "--force-color-profile=srgb", "--font-render-hinting=none", f"--window-size={size[0]},{size[1]}"]
    command += extra + [url]
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)


# --------------------------------------------------------------------------------------- font metrics

def font_metrics(browser, port):
    """Glyph advance widths of the preview fonts, measured once in Chromium and cached."""
    stamp = hashlib.sha1()
    for path in FONT_FILES:
        stamp.update(path.name.encode())
        stamp.update(str(path.stat().st_size if path.exists() else 0).encode())
    stamp.update(browser.encode())
    key = stamp.hexdigest()[:16]
    cache = OUT / "cache" / "metrics.json"
    if cache.exists():
        try:
            data = json.loads(cache.read_text(encoding="utf-8"))
            if data.get("Key") == key:
                return data
        except (OSError, ValueError):
            pass
    url = f"http://127.0.0.1:{port}/tools/ui_preview/metrics.html"
    result = chrome(browser, url, (400, 300), ["--virtual-time-budget=15000", "--dump-dom"])
    match = re.search(r'<pre id="out">(.*?)</pre>', result.stdout, re.S)
    if not match or match.group(1).strip() in ("", "pending"):
        sys.exit("could not measure the fonts in Chromium (tools/ui_preview/metrics.html):\n" + result.stderr[-2000:])
    text = match.group(1).replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
    data = json.loads(text)
    if not data.get("Check", {}).get("fredokaLoaded"):
        print("  warning: Fredoka One did not load in Chromium; text sizes may be off")
    data["Key"] = key
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data), encoding="utf-8")
    return data


def metrics_luau(metrics):
    fonts = []
    for key, widths in metrics["Fonts"].items():
        entries = ",".join(f"[{int(cp)}]={w:g}" for cp, w in widths.items())
        fonts.append(f"[{json.dumps(key)}]={{{entries}}}")
    avg = ",".join(f"[{json.dumps(k)}]={v:g}" for k, v in metrics["Avg"].items())
    return f"M.Metrics = {{ Fonts = {{{','.join(fonts)}}}, Avg = {{{avg}}}, Emoji = {metrics['Emoji']:g} }}\n"


# --------------------------------------------------------------------------------------- the luau bundle

def long_string(text):
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(lua_value(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(k)}] = {lua_value(v)}" for k, v in value.items() if v is not None) + "}"
    if value is None:
        return "nil"
    raise TypeError(f"can't write {value!r} as Luau")


def script_kind(filename):
    for suffix, kind in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".server.lua", "Script"),
                         (".client.lua", "LocalScript"), (".luau", "ModuleScript"), (".lua", "ModuleScript")):
        if filename.endswith(suffix):
            return filename[: -len(suffix)], kind
    return None, None


def project_entries(tree, path, out):
    """Walks default.project.json like Rojo: (kind, instance path, payload) entries."""
    for name, node in tree.items():
        if name.startswith("$") or not isinstance(node, dict):
            continue
        child_path = f"{path}/{name}" if path else name
        class_name = node.get("$className")
        source = node.get("$path")
        if isinstance(source, dict):
            source = source.get("optional")
        if source:
            full = ROOT / source
            if full.is_dir():
                out.append(("node", child_path, class_name or "Folder"))
                directory_entries(full, child_path, out)
            elif full.is_file():
                stem, kind = script_kind(full.name)
                if kind:
                    out.append(("script" if kind != "ModuleScript" else "module", child_path, full))
        elif class_name and path:
            out.append(("node", child_path, class_name))
        if node.get("$properties"):
            out.append(("props", child_path, node["$properties"]))
        project_entries(node, child_path, out)


def directory_entries(directory, path, out):
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            init = next((entry / n for n in ("init.luau", "init.lua", "init.client.luau") if (entry / n).exists()), None)
            if init:
                out.append(("module", f"{path}/{entry.name}", init))
            else:
                out.append(("node", f"{path}/{entry.name}", "Folder"))
            directory_entries(entry, f"{path}/{entry.name}", out)
        elif entry.is_file() and not entry.name.startswith("init."):
            stem, kind = script_kind(entry.name)
            if kind == "ModuleScript":
                out.append(("module", f"{path}/{stem}", entry))
            elif kind == "LocalScript":
                out.append(("script", f"{path}/{stem}", entry))
            elif kind:
                out.append(("node", f"{path}/{stem}", kind))


SKIP = ("ServerScriptService/", "ServerStorage/")  # server code never runs on the client


def build_bundle(config, metrics):
    chunks = ["local M = {}"]
    for part in PARTS:
        source = (HERE / part).read_text(encoding="utf-8")
        chunks.append(f";(function(...)\n{source}\nend)(M)")
    chunks.append(metrics_luau(metrics))
    chunks.append(f"M.Config = {lua_value(config)}")
    chunks.append("M.Screen = M.Config.Screen")
    entries = []
    project_entries(json.loads(PROJECT.read_text(encoding="utf-8"))["tree"], "", entries)
    for kind, path, payload in entries:
        if path.startswith(SKIP):
            continue
        if kind == "node":
            chunks.append(f"M.Node({json.dumps(path)}, {json.dumps(payload)})")
        elif kind in ("module", "script"):
            chunk = payload.relative_to(ROOT).as_posix()
            source = payload.read_text(encoding="utf-8")
            fn = "M.Module" if kind == "module" else "M.Script"
            chunks.append(f"{fn}({json.dumps(path)}, {json.dumps(chunk)}, {long_string(source)})")
        elif kind == "props":
            props = {k: v for k, v in payload.items() if isinstance(v, (bool, int, float, str, list))}
            chunks.append(f"M.SetProps({json.dumps(path)}, {lua_value(props)})")
    boot = (HERE / "Boot.luau").read_text(encoding="utf-8")
    chunks.append(f";(function(...)\n{boot}\nend)(M)")
    return "\n".join(chunks) + "\n"


def run_luau(luau, bundle_path, timeout):
    started = time.time()
    try:
        result = subprocess.run([luau, str(bundle_path)], capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"the luau run took longer than {timeout}s (an endless loop?); bundle: {bundle_path}", 0
    dump = None
    other = []
    for line in result.stdout.splitlines():
        if line.startswith("@@UI@@"):
            dump = json.loads(line[len("@@UI@@"):])
        elif line.strip():
            other.append(line)
    if dump is None:
        message = "\n".join(other[-30:] + [result.stderr.strip()[-3000:]])
        return None, f"the client failed before the dump (exit code {result.returncode}):\n{message}\nbundle: {bundle_path}", 0
    return dump, None, time.time() - started


# --------------------------------------------------------------------------------------- assets

def load_asset_map():
    path = HERE / "asset_map.json"
    if not path.exists():
        return {}
    try:
        return {str(k): v for k, v in json.loads(path.read_text(encoding="utf-8")).items()}
    except ValueError as error:
        print(f"  warning: {path.relative_to(ROOT)}: {error}")
        return {}


IMAGE_DIRS = [ROOT / "assets" / "ui", ROOT / "assets"]


def auto_asset_map():
    """Asset ids in the game code mapped to repo pictures, so uploaded icons draw without asset_map.json:
    a line of src/**/*.luau with an id (6+ digits) and either a repo path to a .png/.jpg on the same line
    (`Volts = { Id = 1234567 }, -- assets/ui/Volts.png`) or a key that names a picture in assets/ui
    (`Volts = 1234567,` or `Volts = { Image = "rbxassetid://1234567", ... }` -> assets/ui/Volts.png)."""
    pictures = {}
    for directory in IMAGE_DIRS:
        if directory.is_dir():
            for path in directory.iterdir():
                if path.suffix.lower() in (".png", ".jpg", ".jpeg"):
                    pictures.setdefault(path.stem.lower(), path.relative_to(ROOT).as_posix())
    found = {}
    for source in (ROOT / "src").rglob("*.luau"):
        try:
            text = source.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line in text.splitlines():
            ids = re.findall(r"(?<![\w.])(\d{6,})(?![\w.])", line)
            if not ids:
                continue
            path = re.search(r"((?:assets|docs|build)/[\w./-]+\.(?:png|jpe?g))", line)
            key = re.match(r"\s*\[?[\"']?(\w+)[\"']?\]?\s*=", line)
            target = path.group(1) if path and (ROOT / path.group(1)).is_file() else (
                pictures.get(key.group(1).lower()) if key else None)
            if target:
                for asset_id in ids:
                    found.setdefault(asset_id, target)
    return found


def resolve_image(src, asset_map):
    """Image property -> URL under the server root (or None)."""
    match = re.match(r"rbxassetid://(\d+)", src) or re.match(r"https?://www\.roblox\.com/asset/\?id=(\d+)", src)
    candidate = None
    if match and match.group(1) in asset_map:
        candidate = asset_map[match.group(1)]
    elif src in asset_map:
        candidate = asset_map[src]
    elif not re.match(r"^[a-z]+://", src):
        candidate = src
    if candidate:
        path = (ROOT / candidate).resolve()
        if path.is_file() and ROOT in path.parents:
            return "/" + path.relative_to(ROOT).as_posix()
    return None


PET_GLB = ROOT / "assets" / "models" / "StormlingPets.glb"
PET_CACHE = OUT / "pets"
pet_lock = threading.Lock()


def three_available():
    return any((d / "three" / "build" / "three.module.js").is_file() for d in THREE_DIRS)


def render_pets(keys, ctx):
    """Renders the pets shown in viewports with tools/pets/viewer.html (the mesh pack, game tier colours)
    into build/ui_preview/pets/<PetId>_<Tier>.png, once (again when the pack changes)."""
    if ctx.get("no_pet_renders") or not PET_GLB.is_file() or not three_available():
        return
    with pet_lock:
        todo = []
        for key in keys:
            pet, tier = key.split(":")
            target = PET_CACHE / f"{pet}_{tier}.png"
            if not target.is_file() or target.stat().st_mtime < PET_GLB.stat().st_mtime:
                todo.append((pet, tier, target))
        if not todo:
            return
        PET_CACHE.mkdir(parents=True, exist_ok=True)
        print(f"  rendering {len(todo)} pet pictures with tools/pets/viewer.html (cached in {PET_CACHE.relative_to(ROOT)})")

        def one(job):
            pet, tier, target = job
            url = f"http://127.0.0.1:{ctx['port']}/tools/pets/viewer.html?pet={pet}&view=hero&tier={tier}&size=320"
            result = chrome(ctx["browser"], url, (320, 320), ["--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                            "--default-background-color=00000000", "--virtual-time-budget=20000", f"--screenshot={target}"])
            return target.is_file() or result.returncode

        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(one, todo))


def trimmed(path):
    """A copy of a picture cropped to its opaque pixels (cached; the original without Pillow)."""
    try:
        from PIL import Image
    except ImportError:
        return path
    target = PET_CACHE / "trim" / f"{path.parent.name}_{path.name}"
    if target.is_file() and target.stat().st_mtime >= path.stat().st_mtime:
        return target
    with pet_lock:
        image = Image.open(path).convert("RGBA")
        box = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if box:
            image = image.crop(box)
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
    return target


def pet_art(keys):
    """Picture per "PetId:Tier": an exact render from the cache, else a Normal picture (page.js tints it)."""
    art = {}
    for key in keys:
        pet, tier = key.split(":")
        exact = PET_CACHE / f"{pet}_{tier}.png"
        if exact.is_file():
            art[key] = {"Url": "/" + trimmed(exact).relative_to(ROOT).as_posix(), "Tier": tier}
            continue
        normal = PET_CACHE / f"{pet}_Normal.png"
        found = normal if normal.is_file() else next((d / f"{pet}.png" for d in PET_ART_DIRS if (d / f"{pet}.png").is_file()), None)
        if found:
            art[key] = {"Url": "/" + trimmed(found).relative_to(ROOT).as_posix(), "Tier": "Normal"}
    return art


# --------------------------------------------------------------------------------------- one render

def parse_screen(text, args):
    text = text.strip().lower()
    if text in PRESETS:
        w, h, touch = PRESETS[text]
    else:
        match = re.match(r"^(\d+)x(\d+)$", text)
        if not match:
            sys.exit(f"--screen: expected WxH or one of {', '.join(PRESETS)}, got {text!r}")
        w, h = int(match.group(1)), int(match.group(2))
        touch = min(w, h) < 600
    if args.touch:
        touch = True
    if args.no_touch:
        touch = False
    return w, h, touch


def screen_config(w, h, touch, args):
    screen = {"W": w, "H": h, "InsetTop": args.inset, "Touch": touch, "SafeLeft": 0, "SafeRight": 0, "SafeBottom": 0}
    if args.safe_area:
        values = [int(v) for v in re.findall(r"\d+", args.safe_area)]
        if not values or len(values) > 3:
            sys.exit("--safe-area: expected L,R[,B] in pixels, e.g. 47,47,21")
        values += [values[0]] * (2 - len(values)) if len(values) < 2 else []
        screen["SafeLeft"], screen["SafeRight"] = values[0], values[1]
        screen["SafeBottom"] = values[2] if len(values) > 2 else 0
    if not touch and not (args.no_chat or args.no_core):
        # Roblox's chat window: top left, under the top bar
        screen["Chat"] = [8, args.inset + 6, min(400, round(w * 0.32)), min(222, round(h * 0.31))]
    return screen


def make_config(job, args):
    actions = []
    if job.get("panel"):
        actions.append({"Kind": "panel", "Name": job["panel"], "Args": [job["tab"]] if job.get("tab") else []})
    for path in args.click or []:
        actions.append({"Kind": "click", "Path": path})
    for item in args.notify or []:
        text, _, kind = item.partition("|")
        actions.append({"Kind": "notify", "Text": text, "Type": kind or "Info"})
    for index, code in enumerate(args.run or []):
        actions.append({"Kind": "run", "Code": code, "Name": f"--run #{index + 1}"})
    for path in args.run_file or []:
        actions.append({"Kind": "run", "Code": Path(path).read_text(encoding="utf-8"), "Name": path})
    before = [{"Kind": "run", "Code": code, "Name": f"--before #{i + 1}"} for i, code in enumerate(args.before or [])]
    before += [{"Kind": "run", "Code": Path(path).read_text(encoding="utf-8"), "Name": path} for path in args.before_file or []]
    stubs = [] if args.stub.lower() == "none" else [s if s.endswith("Controller") else s + "Controller" for s in args.stub.split(",") if s]
    for name in args.real or []:
        name = name if name.endswith("Controller") else name + "Controller"
        stubs = [s for s in stubs if s != name]
    data_json = None
    if args.data_json:
        candidate = Path(args.data_json)
        data_json = candidate.read_text(encoding="utf-8") if candidate.is_file() else args.data_json
        json.loads(data_json)  # fail early on bad JSON
    return {
        "Screen": job["screen"],
        "Studio": args.studio,
        "Restricted": args.restricted,
        "Chat": "Chat" in job["screen"],
        "Data": args.data,
        "DataJson": data_json,
        "DataDelay": 1e9 if args.loading else None,
        "Stubs": stubs,
        "BootSeconds": 0.6 if args.loading else args.boot,
        "SettleSeconds": args.settle,
        "Actions": actions,
        "Before": before,
        "Blank": args.blank,
        "ClientPath": CLIENT,
        "MainPath": CLIENT + "/Main",
        "Tree": True,
    }


def print_report(name, dump, seconds):
    for message in dump.get("Prints", []):
        print(f"  [{name}] print: {message}")
    for message in dump.get("Warnings", []):
        print(f"  [{name}] warn: {message}")
    errors = dump.get("Errors", [])
    for message in errors:
        print(f"  [{name}] ERROR: " + message.replace("\n", "\n         "))
    hidden = [g for g in dump.get("Gaps", []) if not any(g["Message"] in e for e in errors)]
    for gap in hidden:
        where = f" (at {gap['Where']})" if gap.get("Where") else ""
        if gap.get("Maybe"):
            print(f"  [{name}] warn: {gap['Message']}{where} - caught by a pcall in the game code")
        else:
            print(f"  [{name}] MOCK GAP: {gap['Message']}{where} - caught by a pcall in the game code")
    for action in dump.get("Actions", []):
        print(f"  [{name}] {action}")
    stats = dump.get("Stats", {})
    print(f"  [{name}] luau {seconds:.1f}s: {stats.get('Instances')} gui instances, {stats.get('Drawn')} drawn, "
          f"{stats.get('Layouts')} layout passes, {stats.get('SimSeconds', 0):.1f} simulated s")
    real_gaps = [g for g in hidden if not g.get("Maybe")]
    return bool(errors or real_gaps)


def print_tree(nodes, depth=0):
    for node in nodes:
        pos, size = node.get("Position"), node.get("Size")
        geo = f" @({pos[0]:.0f},{pos[1]:.0f}) {size[0]:.0f}x{size[1]:.0f}" if pos and size else ""
        flags = ""
        if node.get("Visible") is False:
            flags += " hidden"
        if node.get("Enabled") is False:
            flags += " disabled"
        text = f' "{node["Text"][:40]}" ({node.get("TextSize")}px)' if node.get("Text") else ""
        print(f"{'  ' * depth}{node['Name']} [{node['Class']}]{geo}{flags}{text}")
        if node.get("Visible") is not False and node.get("Enabled") is not False:
            print_tree(node.get("Children", []), depth + 1)


def render_job(job, args, ctx):
    name = job["name"]
    config = make_config(job, args)
    bundle = build_bundle(config, ctx["metrics"])
    bundle_path = OUT / "cache" / f"preview_bundle_{name}.luau"
    bundle_path.write_text(bundle, encoding="utf-8")
    dump, error, seconds = run_luau(ctx["luau"], bundle_path, args.timeout)
    if error:
        return name, None, error
    failed = print_report(name, dump, seconds)
    out_png = job["png"]
    out_png.parent.mkdir(parents=True, exist_ok=True)
    tree = {"Screen": dump["Screen"], "Tree": dump.get("Tree"), "Warnings": dump.get("Warnings"), "Errors": dump.get("Errors"),
            "Gaps": dump.get("Gaps"), "Notes": dump.get("Notes"), "Actions": dump.get("Actions"), "Stats": dump.get("Stats")}
    out_png.with_suffix(".json").write_text(json.dumps(tree, indent=1, ensure_ascii=False), encoding="utf-8")
    if args.tree:
        print(f"  [{name}] PlayerGui tree: @(AbsolutePosition) in GUI space (PNG y - {dump['Screen']['InsetTop']}), "
              "AbsoluteSize; hidden subtrees are not expanded")
        print_tree(dump.get("Tree") or [])
    if failed and not args.keep_going:
        return name, None, "the client code raised errors or hit a mock gap (see above; --keep-going renders anyway)"

    asset_map = ctx["asset_map"]
    assets = {}
    missing = []
    for src in dump.get("Images", []):
        url = resolve_image(src, asset_map)
        if url:
            assets[src] = url
        else:
            missing.append(src)
    if missing:
        print(f"  [{name}] images drawn as placeholders (add them to tools/ui_preview/asset_map.json): {', '.join(missing[:8])}"
              + (" ..." if len(missing) > 8 else ""))
    render_pets(dump.get("Pets", []), ctx)
    art = pet_art(dump.get("Pets", []))
    without = sorted({k.split(':')[0] for k in dump.get("Pets", [])} - {k.split(':')[0] for k in art})
    if without:
        print(f"  [{name}] pets drawn as stand-ins (no picture: needs assets/models/StormlingPets.glb and three.js "
              f"in tools/pets or tools/world node_modules): {', '.join(without)}")
    background, background_url = args.bg, None
    if background == "sky-island":
        background_url = "/tools/ui_preview/backdrop.svg"
    elif background not in ("sky", "none"):
        path = Path(background).resolve()
        if not path.is_file() or ROOT not in path.parents:
            return name, None, f"--bg {background}: not an image file inside the repo"
        background_url = "/" + path.relative_to(ROOT).as_posix()
    page = {
        "Screen": dump["Screen"],
        "Items": dump["Items"],
        "Assets": assets,
        "PetArt": art,
        "Player": dump.get("Player"),
        "Options": {"Background": background, "BackgroundUrl": background_url, "TopBar": not (args.no_topbar or args.no_core),
                    "ChatWindow": not (args.no_chat or args.no_core), "PlayerList": not (args.no_playerlist or args.no_core),
                    "TouchControls": not args.no_core, "Outline": args.outline},
    }
    page_path = OUT / "cache" / f"page_{name}.json"
    page_path.write_text(json.dumps(page, ensure_ascii=False), encoding="utf-8")
    w, h = dump["Screen"]["W"], dump["Screen"]["H"]
    url = f"http://127.0.0.1:{ctx['port']}/tools/ui_preview/page.html?data=/{page_path.relative_to(ROOT).as_posix()}"
    tmp_png = OUT / "cache" / f"shot_{name}.png"
    if tmp_png.exists():
        tmp_png.unlink()
    result = chrome(ctx["browser"], url, (w, h), [f"--force-device-scale-factor={args.scale}", "--virtual-time-budget=20000",
                                                  f"--screenshot={tmp_png}"], timeout=args.timeout)
    if not tmp_png.exists():
        return name, None, "Chromium did not write a screenshot:\n" + result.stderr[-2000:]
    shutil.move(str(tmp_png), out_png)
    if args.compare:
        compare(Path(args.compare), out_png)
    return name, out_png, None


def compare(reference, png):
    """<name>_compare.png: the reference picture (e.g. docs/ui_mockup.png) and the preview side by side."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("  --compare needs Pillow (pip install pillow)")
        return
    left = Image.open(reference).convert("RGB")
    right = Image.open(png).convert("RGB")
    height = max(left.height, right.height)
    scale_l, scale_r = height / left.height, height / right.height
    left = left.resize((round(left.width * scale_l), height), Image.LANCZOS)
    right = right.resize((round(right.width * scale_r), height), Image.LANCZOS)
    sheet = Image.new("RGB", (left.width + right.width + 12, height + 30), (35, 48, 102))
    sheet.paste(left, (0, 30))
    sheet.paste(right, (left.width + 12, 30))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), f"reference: {reference.name}", fill="white")
    draw.text((left.width + 20, 8), f"preview: {png.name}", fill="white")
    target = png.with_name(png.stem + "_compare.png")
    sheet.save(target)
    print(f"  wrote {target.relative_to(ROOT) if ROOT in target.parents else target}")


# --------------------------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog="See the header of tools/preview_ui.py for details.")
    parser.add_argument("--screen", default="1280x720")
    parser.add_argument("--inset", type=int, default=58)
    parser.add_argument("--touch", action="store_true")
    parser.add_argument("--no-touch", action="store_true")
    parser.add_argument("--panel")
    parser.add_argument("--tab")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--click", action="append")
    parser.add_argument("--run", action="append")
    parser.add_argument("--run-file", action="append")
    parser.add_argument("--before", action="append")
    parser.add_argument("--before-file", action="append")
    parser.add_argument("--blank", action="store_true")
    parser.add_argument("--safe-area")
    parser.add_argument("--notify", action="append")
    parser.add_argument("--data", default="mid", choices=["new", "mid", "late"])
    parser.add_argument("--data-json")
    parser.add_argument("--studio", action="store_true")
    parser.add_argument("--restricted", action="store_true")
    parser.add_argument("--loading", action="store_true")
    parser.add_argument("--stub", default=",".join(DEFAULT_STUBS))
    parser.add_argument("--real", action="append")
    parser.add_argument("--boot", type=float, default=2.0)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--bg", default="sky-island")
    parser.add_argument("--no-topbar", action="store_true")
    parser.add_argument("--no-chat", action="store_true")
    parser.add_argument("--no-playerlist", action="store_true")
    parser.add_argument("--no-core", action="store_true")
    parser.add_argument("--outline", action="store_true")
    parser.add_argument("--scale", type=float, default=1)
    parser.add_argument("--out")
    parser.add_argument("--name")
    parser.add_argument("--tree", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--luau")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--jobs", type=int, default=4, help="renders in parallel (default 4)")
    parser.add_argument("--no-pet-renders", action="store_true")
    parser.add_argument("--compare")
    args = parser.parse_args()

    if args.panel and args.panel not in PANELS:
        print(f"  note: --panel {args.panel} is not one of {', '.join(PANELS)} (passed to OpenPanel anyway)")
    luau = find_luau(args.luau)
    if not luau:
        sys.exit("luau not found: install it (https://github.com/luau-lang/luau/releases) or set LUAU=path/to/luau")
    browser = find_browser()
    if not browser:
        sys.exit("Chromium not found: install Playwright's chromium (npx playwright install chromium-headless-shell) "
                 "or set CHROME_PATH")

    screens = [parse_screen(s, args) for s in args.screen.split(",") if s.strip()]
    targets = [(None, None)] + [(p, None) for p in PANELS] if args.all else [(args.panel, args.tab)]
    out_arg = Path(args.out) if args.out else OUT
    jobs = []
    for w, h, touch in screens:
        for panel, tab in targets:
            base = args.name or (("panel_" + panel if args.all else panel) if panel else "hud")
            if args.name is None and tab:
                base += "_" + re.sub(r"\W+", "", tab)
            name = base if len(screens) == 1 else f"{base}_{w}x{h}"
            if out_arg.suffix.lower() == ".png" and len(screens) * len(targets) == 1:
                png = out_arg
            else:
                png = (out_arg if out_arg.suffix.lower() != ".png" else out_arg.parent) / f"{name}.png"
            jobs.append({"name": name, "panel": panel, "tab": tab, "screen": screen_config(w, h, touch, args), "png": png.resolve()})

    (OUT / "cache").mkdir(parents=True, exist_ok=True)
    server = start_server()
    started = time.time()
    try:
        ctx = {"luau": luau, "browser": browser, "port": server.server_address[1], "asset_map": {**auto_asset_map(), **load_asset_map()},
               "no_pet_renders": args.no_pet_renders}
        ctx["metrics"] = font_metrics(browser, ctx["port"])
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(lambda job: render_job(job, args, ctx), jobs))
    finally:
        server.shutdown()
    failed = False
    for name, png, error in results:
        if error:
            failed = True
            print(f"  [{name}] FAILED: {error}")
        else:
            shown = png.relative_to(ROOT) if ROOT in png.parents else png
            print(f"  wrote {shown} (+ .json)")
    print(f"  done in {time.time() - started:.1f}s")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
