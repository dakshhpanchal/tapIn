"""Builds assets/food_packs/usda.json from USDA FoodData Central.

Sources (public domain, CC0 1.0): SR Legacy (2018-04) and Foundation Foods
(2025-04-24). Download the two CSV zips from https://fdc.nal.usda.gov/download-datasets,
unzip them, and pass the two folders:

    python3 build_usda.py <sr_legacy_dir> <foundation_dir> <out.json>

Foundation Foods are newer analytical data, so where both name the same food the
Foundation row wins.
"""
import csv
import sys
from collections import defaultdict

from common import clean_name, num, physically_possible, prefer_natural, write_pack, COLS

# column -> FoodData Central nutrient ids, first one present wins
NUTRIENTS = {
    "kcal": [1008, 2048, 2047],
    "protein": [1003],
    "fat": [1004],
    "carbs": [1005, 1050],
    "sugars": [2000],
    "satfat": [1258],
    "fibre": [1079],
    "mufa": [1292],
    "pufa": [1293],
    "trans": [1257],
    "cholesterol": [1253],
    "sodium": [1093],
    "potassium": [1092],
    "magnesium": [1090],
    "calcium": [1087],
    "iron": [1089],
    "zinc": [1095],
    "phosphorus": [1091],
    "vitA": [1106],
    "vitC": [1162],
    "vitD": [1114],
    "vitB6": [1175],
    "vitB12": [1178],
    "niacin": [1167],
}


def read(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        yield from csv.DictReader(f)


def load(folder, data_type, prefix):
    cats = {r["id"]: r["description"] for r in read(folder + "/food_category.csv")}
    units = {r["id"]: r["name"] for r in read(folder + "/measure_unit.csv")}
    foods = {}
    for r in read(folder + "/food.csv"):
        if r["data_type"] == data_type:
            foods[r["fdc_id"]] = r
    values = defaultdict(dict)
    wanted = {i for ids in NUTRIENTS.values() for i in ids}
    for r in read(folder + "/food_nutrient.csv"):
        if r["fdc_id"] in foods and int(r["nutrient_id"]) in wanted and r["amount"] != "":
            values[r["fdc_id"]][int(r["nutrient_id"])] = float(r["amount"])
    portions = defaultdict(list)
    for r in read(folder + "/food_portion.csv"):
        if r["fdc_id"] not in foods or not r["gram_weight"]:
            continue
        unit = units.get(r["measure_unit_id"], "")
        amount = float(r["amount"] or 1)
        qty = f"{amount:g}"
        extra = (r["portion_description"] or r["modifier"] or "").strip()
        if unit and unit != "undetermined":
            label = f"{qty} {unit}" + (f", {extra}" if extra else "")
        else:
            # SR Legacy keeps the household measure in the modifier.
            label = f"{qty} {extra}" if extra else qty
        # "1 serving" says nothing; keep it only when it is all there is.
        seq = int(r["seq_num"]) if r["seq_num"] else 999
        portions[r["fdc_id"]].append((seq, label, float(r["gram_weight"])))
    out = {}
    for fid, r in foods.items():
        have = values.get(fid, {})
        row = {}
        for col, ids in NUTRIENTS.items():
            row[col] = next((have[i] for i in ids if i in have), None)
        if row["kcal"] is None:
            continue
        if not physically_possible(row):
            continue
        ps = sorted(portions.get(fid, []))
        seen, plist = set(), []
        for _, label, grams in ps:
            if label in seen or grams <= 0:
                continue
            seen.add(label)
            plist.append([label, num(grams, 1)])
        row["portions"] = prefer_natural(plist)[:6]
        row["name"] = clean_name(r["description"]).replace(
            " (Includes foods for USDA's Food Distribution Program)", "")
        row["category"] = cats.get(r["food_category_id"], "")
        row["code"] = f"{prefix}{fid}"
        out[fid] = row
    return out


def main(sr_dir, found_dir, out_path):
    sr = load(sr_dir, "sr_legacy_food", "sr")
    fn = load(found_dir, "foundation_food", "fn")
    by_name = {}
    for row in sr.values():
        by_name[row["name"].lower()] = row
    for row in fn.values():
        by_name[row["name"].lower()] = row  # Foundation replaces SR
    rows = sorted(by_name.values(), key=lambda r: r["name"].lower())
    foods = []
    for r in rows:
        line = [r["code"], r["name"], r["category"]]
        for col in COLS[3:-1]:
            line.append(num(r[col], 2))
        line.append(r["portions"])
        foods.append(line)
    meta = {
        "id": "usda",
        "name": "USDA FoodData Central",
        "short": "USDA",
        "regions": ["*"],
        "license": "CC0 1.0 (public domain)",
        "attribution": "U.S. Department of Agriculture, Agricultural Research "
                       "Service. FoodData Central: SR Legacy (2018) and "
                       "Foundation Foods (April 2025). fdc.nal.usda.gov",
        "url": "https://fdc.nal.usda.gov",
        "version": "SR Legacy 2018-04 + Foundation Foods 2025-04",
    }
    write_pack(out_path, meta, foods)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
