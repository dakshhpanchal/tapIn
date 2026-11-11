"""Shared bits for the food data pack builders.

A pack is one JSON file in assets/food_packs/. Every nutrient is per 100 g in the
units tapIn uses everywhere (see MealNutrimentsEntity): energy kcal; protein,
fat, carbohydrate, sugars, fibre and the fat types in g; cholesterol and the
minerals in mg; vitamin A, D and B12 in ug; vitamin C, B6 and niacin in mg.

    {
      "id": "usda",                      # stable code, also the source key
      "name": "USDA FoodData Central",   # shown in Settings and on food chips
      "short": "USDA",
      "regions": ["*"],                  # ISO country codes, or "*" for anywhere
      "kind": "foods",                   # or "dishes" for recipe databases
      "license": "CC0 1.0",
      "attribution": "...",
      "url": "https://...",
      "version": "...",
      "cols": [... column names, in order ...],
      "foods": [[code, name, category, kcal, ...nutrients..., portions], ...]
    }

`portions` is the last column: a list of [label, grams] household measures, the
first one being the default serving.
"""
import json
import os
import re

# Column order of every food row. Keep in step with LocalFoodPack in Dart.
COLS = [
    "code", "name", "category",
    "kcal", "protein", "fat", "carbs", "sugars", "satfat", "fibre",
    "mufa", "pufa", "trans", "cholesterol",
    "sodium", "potassium", "magnesium", "calcium", "iron", "zinc", "phosphorus",
    "vitA", "vitC", "vitD", "vitB6", "vitB12", "niacin",
    "portions",
]
NUTRIENT_COLS = COLS[3:-1]


def clean_name(name: str) -> str:
    name = " ".join(name.split())
    if name.isupper():
        name = name.title()
    return name


def num(value, digits=2):
    """A number rounded for size, or None."""
    if value is None:
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v != v or v in (float("inf"), float("-inf")):
        return None
    v = round(v, digits)
    return int(v) if v == int(v) else v


_NATURAL = re.compile(
    r"\b(medium|large|small|fruit|piece|slice|each|whole|item|egg|patty|stick|"
    r"unit|fillet|breast|leg|wing|roll|bun|bar|can|bottle|packet|potato|pod|"
    r"leaf|bunch|clove|head|stalk|spear|ear|link|cookie|biscuit)\b",
    re.I,
)
_MEASURE = re.compile(r"\b(cup|tbsp|tsp|tablespoon|teaspoon|oz|fl oz|ml|l|g|serving)\b", re.I)


def prefer_natural(portions):
    """Household measures in the order a person would pick: "1 medium" before
    "1 cup, mashed". Order is otherwise kept."""
    def rank(p):
        label = p[0]
        if re.search(r"\bmedium\b", label, re.I):
            return 0  # the everyday size
        if _NATURAL.search(label):
            return 1
        if _MEASURE.search(label):
            return 3
        return 2
    return sorted(portions, key=rank)


def physically_possible(row: dict) -> bool:
    """Macros cannot add up to far more than the food weighs (per 100 g)."""
    total = sum(row.get(k) or 0 for k in ("protein", "fat", "carbs"))
    return total <= 105 and (row.get("kcal") or 0) <= 910


def write_pack(path, meta, foods, cols=None):
    pack = dict(meta)
    pack["cols"] = cols or COLS
    pack["foods"] = foods
    pack["count"] = len(foods)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(path)
    print(f"wrote {path}: {len(foods)} foods, {size/1024:.0f} KB")
