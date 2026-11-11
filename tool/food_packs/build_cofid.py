"""Builds assets/food_packs/cofid.json from the UK's McCance and Widdowson's
Composition of Foods Integrated Dataset (CoFID), 2021.

Published by the UK government under the Open Government Licence v3.0. Download
the .xlsx from https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid

    pip install openpyxl
    python3 build_cofid.py <cofid.xlsx> <out.json>

Values printed "Tr" (trace) count as 0; "N" (not measured) and blanks are left
out; a bracketed value "[1.2]" (an estimate) is used as the number inside.
"""
import re
import sys

import openpyxl

from common import clean_name, num, physically_possible, write_pack, COLS

# (sheet, code row cell) -> column
WANTED = {
    "1.3 Proximates": {
        "KCALS": "kcal", "PROT": "protein", "FAT": "fat", "CHO": "carbs",
        "TOTSUG": "sugars", "SATFOD": "satfat", "AOACFIB": "fibre",
        "MONOFOD": "mufa", "POLYFOD": "pufa", "FODTRANS": "trans",
        "CHOL": "cholesterol",
    },
    "1.4 Inorganics": {
        "NA": "sodium", "K": "potassium", "MG": "magnesium", "CA": "calcium",
        "FE": "iron", "ZN": "zinc", "P": "phosphorus",
    },
    "1.5 Vitamins": {
        "RETEQU": "vitA", "VITC": "vitC", "VITD": "vitD", "VITB6": "vitB6",
        "VITB12": "vitB12", "NIAC": "niacin",
    },
}


def value(cell):
    if cell is None:
        return None
    t = str(cell).strip()
    if t in ("", "N", "n/a"):
        return None
    if t.lower() == "tr":
        return 0.0
    t = re.sub(r"[\[\]()]", "", t)
    try:
        return float(t)
    except ValueError:
        return None


def main(xlsx, out_path):
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
    foods = {}
    for sheet, mapping in WANTED.items():
        rows = list(wb[sheet].iter_rows(values_only=True))
        codes = {i: str(c) for i, c in enumerate(rows[1]) if c}
        for r in rows[3:]:
            code = r[0]
            if not code or not r[1]:
                continue
            entry = foods.setdefault(
                str(code).strip(),
                {"name": str(r[1]).strip(), "group": str(r[3] or "")},
            )
            for i, c in codes.items():
                col = mapping.get(c)
                if col and i < len(r):
                    entry[col] = value(r[i])
    out = []
    for code, d in foods.items():
        if d.get("kcal") is None or not physically_possible(d):
            continue
        line = [code, clean_name(d["name"]), ""]
        for col in COLS[3:-1]:
            line.append(num(d.get(col), 2))
        line.append([])
        out.append(line)
    out.sort(key=lambda r: r[1].lower())
    meta = {
        "id": "cofid",
        "name": "UK Composition of Foods (CoFID)",
        "short": "CoFID",
        "regions": ["GB", "IE"],
        "license": "Open Government Licence v3.0",
        "attribution": "McCance and Widdowson's Composition of Foods Integrated "
                       "Dataset 2021, Public Health England / Office for Health "
                       "Improvement and Disparities. Contains public sector "
                       "information licensed under the Open Government Licence "
                       "v3.0.",
        "url": "https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid",
        "version": "CoFID 2021",
    }
    write_pack(out_path, meta, out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
