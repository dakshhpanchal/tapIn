"""Builds assets/food_packs/indb.json from the Indian Nutrient Databank (INDB).

INDB is 1,014 Indian recipes with nutrients per 100 g and per household serving,
published with the paper in Current Developments in Nutrition (2024) and in
https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-. The repository
carries no licence file; the paper says the files are "publicly and freely
available". Its raw-food half (ICMR-NIN IFCT 2017) is not in the repository.

    pip install openpyxl
    python3 build_indb.py INDB.xlsx out.json

The serving weight is not a column, so it is worked out from the energy of one
serving against the energy per 100 g.
"""
import sys

import openpyxl

from common import clean_name, num, physically_possible, write_pack, COLS

CATEGORY = {
    "ASC": "Indian recipes (Art & Science of Cooking)",
    "BFP": "Indian recipes (Basic Food Preparation)",
    "OSR": "Indian recipes (open-source recipes)",
}


def main(xlsx, out_path):
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
    rows = list(wb.worksheets[0].iter_rows(values_only=True))
    idx = {name: i for i, name in enumerate(rows[0])}

    def get(r, col, scale=1.0):
        v = r[idx[col]] if col in idx else None
        if v in (None, "", "NA", "Tr", "N"):
            return None
        try:
            return float(v) * scale
        except (TypeError, ValueError):
            return None

    foods = []
    for r in rows[1:]:
        code = r[idx["food_code"]]
        name = r[idx["food_name"]]
        if not code or not name:
            continue
        kcal = get(r, "energy_kcal")
        if kcal is None:
            continue
        d = {
            "kcal": kcal,
            "protein": get(r, "protein_g"),
            "fat": get(r, "fat_g"),
            "carbs": get(r, "carb_g"),
            # INDB has free sugars only, not total sugars, so none is given.
            "sugars": None,
            "satfat": get(r, "sfa_mg", 0.001),
            "fibre": get(r, "fibre_g"),
            "mufa": get(r, "mufa_mg", 0.001),
            "pufa": get(r, "pufa_mg", 0.001),
            "trans": None,
            "cholesterol": get(r, "cholesterol_mg"),
            "sodium": get(r, "sodium_mg"),
            "potassium": get(r, "potassium_mg"),
            "magnesium": get(r, "magnesium_mg"),
            "calcium": get(r, "calcium_mg"),
            "iron": get(r, "iron_mg"),
            "zinc": get(r, "zinc_mg"),
            "phosphorus": get(r, "phosphorus_mg"),
            "vitA": get(r, "vita_ug"),
            "vitC": get(r, "vitc_mg"),
            "vitB6": get(r, "vitb6_mg"),
            "vitB12": None,
            "niacin": get(r, "vitb3_mg"),
        }
        d2, d3 = get(r, "vitd2_ug"), get(r, "vitd3_ug")
        d["vitD"] = None if d2 is None and d3 is None else (d2 or 0) + (d3 or 0)
        if not physically_possible(d):
            continue

        portions = []
        unit = r[idx["servings_unit"]] if "servings_unit" in idx else None
        serving_kcal = get(r, "unit_serving_energy_kcal")
        if unit and serving_kcal and kcal > 0:
            grams = serving_kcal / kcal * 100
            if 5 <= grams <= 1500:
                portions.append([f"1 {str(unit).strip()}", num(grams, 0)])

        line = [str(code), clean_name(str(name)), CATEGORY.get(str(code)[:3], "Indian recipes")]
        for col in COLS[3:-1]:
            line.append(num(d[col], 2))
        line.append(portions)
        foods.append(line)

    foods.sort(key=lambda f: f[1].lower())
    meta = {
        "id": "indb",
        "name": "Indian Nutrient Databank (INDB)",
        "short": "INDB",
        # Recipes, not ingredients: plain foods rank first in search.
        "kind": "dishes",
        "regions": ["IN"],
        "license": "No licence stated; published as publicly and freely available",
        "attribution": "Indian Nutrient Databank (INDB), Lindsay Jaacks et al., "
                       "Current Developments in Nutrition, 2024. Recipe values "
                       "derived from ICMR-NIN Indian Food Composition Tables "
                       "2017, with UK (CoFID) and USDA values for ingredients "
                       "not in IFCT.",
        "url": "https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-",
        "version": "INDB, 1,014 recipes",
    }
    write_pack(out_path, meta, foods)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
