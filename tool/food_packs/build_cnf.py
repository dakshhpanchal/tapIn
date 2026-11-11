"""Builds assets/food_packs/cnf.json from the Canadian Nutrient File 2015.

Health Canada: the file "may be downloaded and used without further permission"
provided Health Canada is named as the source ("Canadian Nutrient File, Health
Canada, 2015"), values are not modified, and it is not presented as official.
Download the CSV zip from the Canadian Nutrient File page on canada.ca, unzip,
then:

    python3 build_cnf.py <csv_dir> <out.json>
"""
import csv
import sys
from collections import defaultdict

from common import clean_name, num, physically_possible, prefer_natural, write_pack, COLS

# NutrientCode -> column
CODES = {
    "208": "kcal", "203": "protein", "204": "fat", "205": "carbs",
    "269": "sugars", "606": "satfat", "291": "fibre", "645": "mufa",
    "646": "pufa", "605": "trans", "601": "cholesterol", "307": "sodium",
    "306": "potassium", "304": "magnesium", "301": "calcium", "303": "iron",
    "309": "zinc", "305": "phosphorus", "320": "vitA", "401": "vitC",
    "328": "vitD", "415": "vitB6", "418": "vitB12", "406": "niacin",
}


def read(folder, name):
    with open(f"{folder}/{name}", newline="", encoding="latin-1") as f:
        yield from csv.DictReader(f)


def main(folder, out_path):
    id_to_col = {}
    for r in read(folder, "NUTRIENT NAME.csv"):
        if r["NutrientCode"] in CODES:
            id_to_col[r["NutrientID"]] = CODES[r["NutrientCode"]]
    groups = {r["FoodGroupID"]: r["FoodGroupName"].strip()
              for r in read(folder, "FOOD GROUP.csv")}
    foods = {r["FoodID"]: r for r in read(folder, "FOOD NAME.csv")}
    values = defaultdict(dict)
    for r in read(folder, "NUTRIENT AMOUNT.csv"):
        col = id_to_col.get(r["NutrientID"])
        if col and r["FoodID"] in foods and r["NutrientValue"] != "":
            values[r["FoodID"]][col] = float(r["NutrientValue"])
    measures = {r["MeasureID"]: r["MeasureDescription"].strip()
                for r in read(folder, "MEASURE NAME.csv")}
    portions = defaultdict(list)
    for r in read(folder, "CONVERSION FACTOR.csv"):
        label = measures.get(r["MeasureID"], "")
        if r["FoodID"] in foods and label and label != "100g" and r["ConversionFactorValue"]:
            grams = float(r["ConversionFactorValue"]) * 100
            if grams > 0:
                portions[r["FoodID"]].append([label, num(grams, 1)])

    out = []
    for fid, f in foods.items():
        d = values.get(fid, {})
        if d.get("kcal") is None or not physically_possible(d):
            continue
        line = [f"c{fid}", clean_name(f["FoodDescription"]),
                groups.get(f["FoodGroupID"], "")]
        for col in COLS[3:-1]:
            line.append(num(d.get(col), 2))
        line.append(prefer_natural(portions.get(fid, []))[:6])
        out.append(line)
    out.sort(key=lambda r: r[1].lower())
    meta = {
        "id": "cnf",
        "name": "Canadian Nutrient File",
        "short": "CNF",
        "regions": ["CA"],
        "license": "Health Canada terms (free use with attribution)",
        "attribution": "Canadian Nutrient File, Health Canada, 2015. Reference "
                       "only, not an official version and not medical advice.",
        "url": "https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data.html",
        "version": "CNF 2015",
    }
    write_pack(out_path, meta, out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
