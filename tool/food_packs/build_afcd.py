"""Builds assets/food_packs/afcd.json from the Australian Food Composition
Database (AFCD) Release 3, by Food Standards Australia New Zealand.

FSANZ content is licensed CC BY 4.0 Australia; credit "(c) Food Standards
Australia New Zealand". Download "AFCD Release 3 - Nutrient profiles.xlsx" from
https://www.foodstandards.gov.au (Australian Food Composition Database).

    pip install openpyxl
    python3 build_afcd.py "<AFCD Release 3 - Nutrient profiles.xlsx>" <out.json>

Energy is published in kJ and converted at 4.184 kJ per kcal; trans fat (mg) is
converted to g.
"""
import re
import sys

import openpyxl

from common import clean_name, num, physically_possible, write_pack, COLS

# header text -> (column, scale)
WANTED = {
    "Energy with dietary fibre, equated (kJ)": ("kcal", 1 / 4.184),
    "Protein (g)": ("protein", 1),
    "Fat, total (g)": ("fat", 1),
    "Available carbohydrate, without sugar alcohols (g)": ("carbs", 1),
    "Total sugars (g)": ("sugars", 1),
    "Total dietary fibre (g)": ("fibre", 1),
    "Total saturated fatty acids, equated (g)": ("satfat", 1),
    "Total monounsaturated fatty acids, equated (g)": ("mufa", 1),
    "Total polyunsaturated fatty acids, equated (g)": ("pufa", 1),
    "Total trans fatty acids, imputed (mg)": ("trans", 0.001),
    "Cholesterol (mg)": ("cholesterol", 1),
    "Sodium (Na) (mg)": ("sodium", 1),
    "Potassium (K) (mg)": ("potassium", 1),
    "Magnesium (Mg) (mg)": ("magnesium", 1),
    "Calcium (Ca) (mg)": ("calcium", 1),
    "Iron (Fe) (mg)": ("iron", 1),
    "Zinc (Zn) (mg)": ("zinc", 1),
    "Phosphorus (P) (mg)": ("phosphorus", 1),
    "Vitamin A retinol equivalents (ug)": ("vitA", 1),
    "Vitamin C (mg)": ("vitC", 1),
    "Vitamin D3 equivalents (ug)": ("vitD", 1),
    "Pyridoxine (B6) (mg)": ("vitB6", 1),
    "Cobalamin (B12) (ug)": ("vitB12", 1),
    "Niacin (B3) (mg)": ("niacin", 1),
}


def main(xlsx, out_path):
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
    rows = list(wb["All solids & liquids per 100 g"].iter_rows(values_only=True))
    header_at = next(i for i, r in enumerate(rows) if r and r[0] == "Public Food Key")
    header = [re.sub(r"\s+", " ", str(c or "")).strip() for c in rows[header_at]]
    cols = {i: WANTED[h] for i, h in enumerate(header) if h in WANTED}
    missing = [h for h in WANTED if h not in header]
    if missing:
        print("not found in this release:", missing)
    out = []
    for r in rows[header_at + 1:]:
        if not r[0] or not r[3]:
            continue
        d = {}
        for i, (col, scale) in cols.items():
            v = r[i] if i < len(r) else None
            if isinstance(v, (int, float)):
                d[col] = float(v) * scale
        if d.get("kcal") is None or not physically_possible(d):
            continue
        line = [str(r[0]), clean_name(str(r[3])), ""]
        for col in COLS[3:-1]:
            line.append(num(d.get(col), 2))
        line.append([])
        out.append(line)
    out.sort(key=lambda r: r[1].lower())
    meta = {
        "id": "afcd",
        "name": "Australian Food Composition Database",
        "short": "AFCD",
        "regions": ["AU", "NZ"],
        "license": "CC BY 4.0 Australia",
        "attribution": "Australian Food Composition Database, Release 3. "
                       "(c) Food Standards Australia New Zealand. Licensed "
                       "under Creative Commons Attribution 4.0. FSANZ does not "
                       "endorse this app.",
        "url": "https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd",
        "version": "AFCD Release 3 (December 2025)",
    }
    write_pack(out_path, meta, out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
