"""Writes assets/food_packs/manifest.json from the packs next to it.

The manifest holds each pack's name, regions, licence and credit, without the
foods, so Settings can list the packs without loading them.

    python3 build_manifest.py ../../assets/food_packs
"""
import glob
import json
import os
import sys


def main(folder):
    packs = []
    for path in sorted(glob.glob(os.path.join(folder, "*.json"))):
        name = os.path.basename(path)
        if name == "manifest.json":
            continue
        with open(path, encoding="utf-8") as f:
            pack = json.load(f)
        meta = {k: v for k, v in pack.items() if k not in ("cols", "foods")}
        meta["file"] = name
        packs.append(meta)
    # Region packs first, global ones last: the order they are searched in.
    packs.sort(key=lambda p: ("*" in p["regions"], p["id"]))
    out = os.path.join(folder, "manifest.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"packs": packs}, f, ensure_ascii=False, indent=1)
    print(f"wrote {out}: {[p['id'] for p in packs]}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
