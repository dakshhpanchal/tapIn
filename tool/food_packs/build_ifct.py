"""Builds assets/food_packs/ifct.json from the Indian Food Composition Tables
2017 (IFCT), ICMR-National Institute of Nutrition, Hyderabad: 542 raw and
cooked Indian foods (fruit, vegetables, greens, cereals, pulses, dairy, meat,
fish...), measured across six regions.

The values are those of the book (Longvah T, Ananthan R, Bhaskarachary K,
Venkaiah K. Indian Food Composition Tables 2017). This reads the structured
copy published by Subhajit Sahu under AGPL-3.0:

    git clone https://github.com/nodef/ifct2017
    python3 build_ifct.py ifct2017 out.json

That copy stores every nutrient in grams per 100 g and energy in kJ, so values
are converted to the units tapIn uses (mg, ug, kcal). Vitamin A is worked out
in retinol activity equivalents (retinol + beta-carotene/12 + other
provitamin carotenoids/24). Local names in many Indian languages are kept as
search-only aliases, so "kela" finds banana.
"""
import csv
import re
import sys

from common import COLS, clean_name, num, physically_possible, write_pack

KJ_PER_KCAL = 4.184
G_TO_MG = 1000.0
G_TO_UG = 1_000_000.0


def f(row, col):
    v = row.get(col)
    if v in (None, "", "NaN", "nan"):
        return None
    try:
        x = float(v)
    except ValueError:
        return None
    return x if x == x else None


def scaled(row, col, k):
    v = f(row, col)
    return None if v is None else v * k


def total(row, cols, k):
    vals = [f(row, c) for c in cols]
    vals = [v for v in vals if v is not None]
    return sum(vals) * k if vals else None


def aliases(lang):
    """"H. Kela; Tam. Vazhai pazham" -> ["Kela", "Vazhai pazham"]."""
    out = []
    for part in (lang or "").split(";"):
        part = part.strip()
        # Drop a leading language tag such as "H.", "Tam.", "Kash.".
        part = re.sub(r"^[A-Za-z]{1,5}\.\s*", "", part).strip(" .")
        if part and part.lower() not in (a.lower() for a in out):
            out.append(part)
    return out


def main(folder, out_path):
    with open(f"{folder}/compositions/index.csv", newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    foods = []
    for r in rows:
        kj = f(r, "enerc")
        if kj is None:
            continue
        retinol = f(r, "retol") or 0.0
        rae = (
            retinol
            + (f(r, "cartb") or 0.0) / 12
            + ((f(r, "carta") or 0.0) + (f(r, "crypxb") or 0.0)) / 24
        ) * G_TO_UG
        has_a = any(f(r, c) is not None for c in ("retol", "cartb", "carta", "crypxb"))
        d = {
            "kcal": kj / KJ_PER_KCAL,
            "protein": f(r, "protcnt"),
            "fat": f(r, "fatce"),
            "carbs": f(r, "choavldf"),
            "sugars": total(r, ("frus", "glus", "sucs", "mals", "lactose"), 1.0),
            "satfat": f(r, "fasat"),
            "fibre": f(r, "fibtg"),
            "mufa": f(r, "fams"),
            "pufa": f(r, "fapu"),
            "trans": None,
            "cholesterol": scaled(r, "cholc", G_TO_MG),
            "sodium": scaled(r, "na", G_TO_MG),
            "potassium": scaled(r, "k", G_TO_MG),
            "magnesium": scaled(r, "mg", G_TO_MG),
            "calcium": scaled(r, "ca", G_TO_MG),
            "iron": scaled(r, "fe", G_TO_MG),
            "zinc": scaled(r, "zn", G_TO_MG),
            "phosphorus": scaled(r, "p", G_TO_MG),
            "vitA": rae if has_a else None,
            "vitC": scaled(r, "vitc", G_TO_MG),
            "vitD": total(r, ("ergcal", "chocal"), G_TO_UG),
            "vitB6": scaled(r, "vitb6c", G_TO_MG),
            "vitB12": None,
            "niacin": scaled(r, "nia", G_TO_MG),
        }
        if not physically_possible(d):
            continue
        line = [r["code"], clean_name(r["name"]), r.get("grup", "")]
        for col in COLS[3:-1]:
            line.append(num(d[col], 2))
        line.append([])
        line.append("; ".join(aliases(r.get("lang"))))
        foods.append(line)
    foods.sort(key=lambda x: x[1].lower())
    meta = {
        "id": "ifct",
        "name": "Indian Food Composition Tables 2017 (IFCT)",
        "short": "IFCT",
        "regions": ["IN"],
        "kind": "foods",
        "license": "IFCT 2017 values, ICMR-NIN; digital copy AGPL-3.0",
        "attribution": "Indian Food Composition Tables 2017: Longvah T, Ananthan "
                       "R, Bhaskarachary K, Venkaiah K. ICMR-National Institute "
                       "of Nutrition, Hyderabad. Digital copy by Subhajit Sahu "
                       "(github.com/nodef/ifct2017, AGPL-3.0). Values are per "
                       "100 g edible portion, as in the book.",
        "url": "https://www.nin.res.in/ebooks/IFCT2017.pdf",
        "version": "IFCT 2017, 542 foods",
    }
    write_pack(out_path, meta, foods, cols=COLS + ["aka"])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
