import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';

/// What a food pack says about itself: shown in Settings → Food databases and
/// kept apart from the foods so listing the packs never loads them.
class LocalFoodPackInfo {
  final String id;
  final String file;
  final String name;
  final String shortName;

  /// ISO country codes the pack suits, or `*` for anywhere.
  final List<String> regions;
  final String license;
  final String attribution;
  final String url;
  final String version;
  final int count;

  /// `foods` for ingredient databases, `dishes` for recipe databases. Dishes
  /// rank a little lower so "banana" finds the fruit before banana cake.
  final String kind;

  const LocalFoodPackInfo({
    required this.id,
    required this.file,
    required this.name,
    required this.shortName,
    required this.regions,
    required this.license,
    required this.attribution,
    required this.url,
    required this.version,
    required this.count,
    this.kind = 'foods',
  });

  factory LocalFoodPackInfo.fromJson(Map<String, dynamic> json) =>
      LocalFoodPackInfo(
        id: json['id'] as String,
        file: json['file'] as String,
        name: json['name'] as String,
        shortName: (json['short'] as String?) ?? json['name'] as String,
        regions: [for (final r in json['regions'] as List) r as String],
        license: (json['license'] as String?) ?? '',
        attribution: (json['attribution'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        version: (json['version'] as String?) ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        kind: (json['kind'] as String?) ?? 'foods',
      );

  bool get isDishes => kind == 'dishes';

  /// Meant for everyone, not one region.
  bool get isGlobal => regions.contains('*');

  bool suits(String? region) =>
      isGlobal || (region != null && regions.contains(region.toUpperCase()));
}

/// A pack's foods, read from its JSON file. A row is a list in the column
/// order named by `cols` (see tool/food_packs/common.py); it is turned into a
/// [MealEntity] only when it is shown.
class LocalFoodPack {
  final LocalFoodPackInfo info;
  final List<String> cols;
  final List<List<dynamic>> rows;

  /// Each row's lower-case name, so searching never lowers a string twice.
  final List<String> _lower;

  /// Each row's other names (local-language names, for example "kela" for
  /// banana), lower-case, or empty when the pack has none.
  final List<String> _aka;

  LocalFoodPack._(this.info, this.cols, this.rows, this._lower, this._aka);

  factory LocalFoodPack.fromJson(
    LocalFoodPackInfo info,
    Map<String, dynamic> json,
  ) {
    final cols = [for (final c in json['cols'] as List) c as String];
    final rows = [
      for (final r in json['foods'] as List) List<dynamic>.from(r as List),
    ];
    final nameAt = cols.indexOf('name');
    final akaAt = cols.indexOf('aka');
    return LocalFoodPack._(
      info,
      cols,
      rows,
      [for (final r in rows) (r[nameAt] as String).toLowerCase()],
      [
        for (final r in rows)
          akaAt >= 0 && akaAt < r.length && r[akaAt] is String
              ? (r[akaAt] as String).toLowerCase()
              : '',
      ],
    );
  }

  int get length => rows.length;

  String nameAt(int i) => rows[i][cols.indexOf('name')] as String;

  /// How well food [i]'s name fits the query words; lower is better, null when
  /// a word is missing. Every word must appear. A name that starts with the
  /// query, or has a word that does, and a shorter name, score better, so
  /// "banana" finds "Bananas, raw" before "Cake, banana, with frosting".
  double? score(int i, List<String> words, String whole) {
    final byName = _scoreName(i, words, whole);
    if (byName != null) return byName;
    // Not in the name: the other names count, but after a match on the name.
    final aka = _aka[i];
    if (aka.isEmpty) return null;
    for (final w in words) {
      if (!_startsAWord(aka, w)) return null;
    }
    // A food whose other name is exactly what was typed ("aloo" for potato)
    // beats one that only has a longer name starting that way ("aloo bukhara").
    final exact = aka.split(';').any((t) => t.trim() == whole);
    return (exact ? 0.5 : 3.5) + _lower[i].length / 40;
  }

  /// Whether some word of [text] (words end at a space, comma, semicolon or
  /// bracket) starts with [word].
  static bool _startsAWord(String text, String word) {
    var from = 0;
    while (true) {
      final at = text.indexOf(word, from);
      if (at < 0) return false;
      if (at == 0) return true;
      final before = text.codeUnitAt(at - 1);
      if (before == 0x20 ||
          before == 0x3B ||
          before == 0x2C ||
          before == 0x28) {
        return true;
      }
      from = at + 1;
    }
  }

  double? _scoreName(int i, List<String> words, String whole) {
    final name = _lower[i];
    var total = 0.0;
    for (final w in words) {
      final at = name.indexOf(w);
      if (at < 0) return null;
      if (at == 0) {
        total += 0;
      } else if (name.codeUnitAt(at - 1) == 0x20 ||
          name.codeUnitAt(at - 1) == 0x2C ||
          name.codeUnitAt(at - 1) == 0x28) {
        total += 2; // starts a later word
      } else {
        total += 5; // inside a word
      }
    }
    if (name == whole) total -= 10;
    // "Potato, raw" names the food itself; "Potato flour" is another food.
    // A name that opens with the query as its head word (then a comma, or
    // nothing) goes first, and an unprocessed food a little ahead of that.
    final headEnd = whole.length;
    if (name.startsWith(whole) &&
        (name.length == headEnd || name.codeUnitAt(headEnd) == 0x2C)) {
      total -= 1.5;
    } else if (words.isNotEmpty) {
      // Plurals: "banana" heads "Bananas, raw".
      final first = words.first;
      if (name.startsWith(first) &&
          name.length > first.length &&
          name.codeUnitAt(first.length) == 0x73 /* s */ &&
          (name.length == first.length + 1 ||
              name.codeUnitAt(first.length + 1) == 0x2C)) {
        total -= 1.5;
      }
    }
    if (name.contains(', raw')) total -= 0.5;
    // Foods with more of the name beyond the query rank after plainer ones.
    return total + name.length / 40;
  }

  MealEntity toMeal(int i) {
    final row = rows[i];
    double? v(String col) {
      final at = cols.indexOf(col);
      if (at < 0) return null;
      final x = row[at];
      return x is num ? x.toDouble() : null;
    }

    final portions = <MealPortionEntity>[];
    final rawPortions = row[cols.indexOf('portions')];
    if (rawPortions is List) {
      for (final p in rawPortions) {
        final label = p[0] as String;
        final grams = (p[1] as num).toDouble();
        if (grams > 0) {
          portions.add(
            MealPortionEntity(
              label: label,
              gramWeight: grams,
              localized: true,
              englishLabel: label,
            ),
          );
        }
      }
    }
    final first = portions.isEmpty ? null : portions.first;
    return MealEntity(
      code: '${info.id}:${row[cols.indexOf('code')]}',
      name: row[cols.indexOf('name')] as String,
      brands: null,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: first?.gramWeight,
      servingUnit: 'g',
      servingSize: first == null
          ? null
          : '${first.label} (${_grams(first.gramWeight)} g)',
      nutriments: MealNutrimentsEntity(
        energyKcal100: v('kcal'),
        carbohydrates100: v('carbs'),
        fat100: v('fat'),
        proteins100: v('protein'),
        sugars100: v('sugars'),
        saturatedFat100: v('satfat'),
        fiber100: v('fibre'),
        monounsaturatedFat100: v('mufa'),
        polyunsaturatedFat100: v('pufa'),
        transFat100: v('trans'),
        cholesterol100: v('cholesterol'),
        sodium100: v('sodium'),
        potassium100: v('potassium'),
        magnesium100: v('magnesium'),
        calcium100: v('calcium'),
        iron100: v('iron'),
        zinc100: v('zinc'),
        phosphorus100: v('phosphorus'),
        vitaminA100: v('vitA'),
        vitaminC100: v('vitC'),
        vitaminD100: v('vitD'),
        vitaminB6100: v('vitB6'),
        vitaminB12100: v('vitB12'),
        niacin100: v('niacin'),
      ),
      // Like every reference food database in the app, tagged `fdc` (the
      // enum is stored in Hive); the real origin is in [backendSource].
      source: MealSourceEntity.fdc,
      backendSource: info.id,
      portions: portions,
    );
  }

  static String _grams(double g) =>
      g == g.roundToDouble() ? g.toInt().toString() : g.toStringAsFixed(1);
}
