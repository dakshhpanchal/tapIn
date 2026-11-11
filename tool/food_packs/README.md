# Food data packs

tapIn ships its food databases inside the app, as one JSON file per database in
`assets/food_packs/`. They are searched offline; which ones are used depends on
the user's region (Settings → Food databases).

The pack files are generated, not edited. Each `build_*.py` here turns a public
download into a pack, and `build_manifest.py` lists them in
`assets/food_packs/manifest.json` (name, regions, licence, credit), which is what
Settings shows. Rebuild a pack, then rebuild the manifest.

| Pack | Regions | Source | Licence / terms |
|---|---|---|---|
| `usda` | everywhere | USDA FoodData Central: SR Legacy 2018 + Foundation Foods 2025 | CC0 1.0, public domain |
| `ifct` | India | Indian Food Composition Tables 2017, ICMR-NIN, via the structured copy at github.com/nodef/ifct2017 | Book values © ICMR-NIN; the digital copy is AGPL-3.0 (compatible with this app's GPL-3.0) |
| `indb` | India | Indian Nutrient Databank, 1,014 Indian dishes | No licence stated; published as "publicly and freely available" |
| `cofid` | UK, Ireland | McCance and Widdowson's Composition of Foods, 2021 | Open Government Licence v3.0 |
| `cnf` | Canada | Canadian Nutrient File 2015, Health Canada | Free use with credit "Canadian Nutrient File, Health Canada, 2015"; values unmodified; not an official version |
| `afcd` | Australia, NZ | Australian Food Composition Database, Release 3 | CC BY 4.0, credit "(c) Food Standards Australia New Zealand" |

Every pack's licence and credit line is shown in Settings → Food databases.

## Format

All nutrients are per 100 g in the units tapIn uses (see `common.py`): energy in
kcal; protein, fat, carbohydrate, sugars, fibre and fat types in g; cholesterol
and minerals in mg; vitamin A, D and B12 in µg; vitamin C, B6 and niacin in mg.
`portions` is a list of `[label, grams]` household measures, the first being the
default serving. A pack may add an `aka` column of other names (the IFCT pack
keeps local-language names, so "kela" finds banana). `kind: "dishes"` marks a
recipe database, which ranks a little below ingredient databases of the same name.

## Adding a database for another country

1. Check its licence allows redistribution inside an app, and note the credit it
   requires.
2. Write `build_<id>.py` after the others: read the download, convert to the
   units above, drop rows that are not physically possible, call `write_pack`.
3. Add the pack's id to `SPConst` (`foodSourceDisplayNames`, `foodSourceShortNames`,
   `foodSourceWebsites`) and its countries to `FoodRegion.names`, then run
   `build_manifest.py`. A test fails until all of that is in place.

Needs Python 3 (and `openpyxl` for the Excel-based packs).
