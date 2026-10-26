# Storm Catcher Simulator - extraction digest (tools/icons/digest.py)
#
# Sent to the Trimble SketchUp MCP sandbox in the SAME build_model call as tools/world/sketchup/extract.py,
# pasted right after it: it replaces extract.py's `result` (megabytes of polygons) with a short digest per
# prop. `python3 tools/icons/import_icons.py --set store verify <saved result>` runs the same two scripts on
# the offline dry run and compares: when every prop matches, the dry run IS what SketchUp would hand back,
# polygon for polygon, and it is written as the source (no need to pull the polygons through the tool).
#
#   result = {"storm_icons_digest": 1, "props": {id: [pieces, faces, vertices, ordered, unordered]}}
#
# ordered = a hash of every piece's paint, vertex table and face loops in extraction order; unordered = the
# same geometry hashed in a way that ignores the order of pieces, vertices and faces (so a mismatch that is
# only an ordering difference shows up as: ordered differs, unordered matches).
# Sandbox rules: no imports, no dunders, no ord()/any()/all().

MOD = 2147483647
CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_#"


def text_hash(s):
    h = 5381
    for ch in s:
        h = (h * 33 + CHARS.find(ch) + 2) % MOD
    return h


def prop_digest(prop):
    ordered, unordered, faces, verts = 7, 0, 0, 0
    for piece in prop["pieces"]:
        paint = text_hash(piece["paint"])
        ordered = (ordered * 131 + paint) % MOD
        v = piece["v"]
        coords = [int(round(x * 100)) for x in v]
        for c in coords:
            ordered = (ordered * 31 + c) % MOD
        part = 0
        for i in range(0, len(coords), 3):
            part = (part + (coords[i] * 1000003 + coords[i + 1] * 10007 + coords[i + 2] * 101 + paint) % MOD) % MOD
        for face in piece["f"]:
            faces += 1
            for loop in face:
                ordered = (ordered * 17 + len(loop)) % MOD
                for k in loop:
                    ordered = (ordered * 13 + k) % MOD
                    part = (part + coords[3 * k] * 7 + coords[3 * k + 1] * 3 + coords[3 * k + 2]) % MOD
        unordered = (unordered + part) % MOD
        verts += len(v) // 3
    return [len(prop["pieces"]), faces, verts, ordered, unordered]


result = {"storm_icons_digest": 1, "props": dict([(p["id"], prop_digest(p)) for p in result["props"]]),
          "skipped": result.get("skipped", [])}
