import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/food_region.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_pack.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';

const _cols = [
  'code',
  'name',
  'category',
  'kcal',
  'protein',
  'fat',
  'carbs',
  'sugars',
  'satfat',
  'fibre',
  'mufa',
  'pufa',
  'trans',
  'cholesterol',
  'sodium',
  'potassium',
  'magnesium',
  'calcium',
  'iron',
  'zinc',
  'phosphorus',
  'vitA',
  'vitC',
  'vitD',
  'vitB6',
  'vitB12',
  'niacin',
  'portions',
];

List<dynamic> _food(
  String code,
  String name,
  num kcal, {
  List<List<dynamic>> portions = const [],
}) => [
  code,
  name,
  '',
  kcal,
  1,
  2,
  3,
  4,
  null,
  5,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  portions,
];

Map<String, dynamic> _pack(
  String id,
  List<String> regions,
  List<List<dynamic>> foods, {
  String kind = 'foods',
}) => {
  'kind': kind,
  'id': id,
  'name': '$id database',
  'short': id.toUpperCase(),
  'regions': regions,
  'license': 'Test licence',
  'attribution': 'Credit for $id',
  'url': 'https://example.org/$id',
  'version': '1',
  'count': foods.length,
  'cols': _cols,
  'foods': foods,
};

class _Bundle extends CachingAssetBundle {
  final Map<String, String> files;
  _Bundle(this.files);

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw Exception('Unable to load asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.view(bytes.buffer);
  }
}

_Bundle _bundle() {
  final india = _pack(
    'indb',
    ['IN'],
    [
      _food('1', 'Banana chips', 520),
      _food(
        '2',
        'Aloo gobi',
        90,
        portions: [
          ['1 bowl', 250],
        ],
      ),
    ],
    kind: 'dishes',
  );
  final usda = _pack(
    'usda',
    ['*'],
    [
      _food(
        'a',
        'Bananas, raw',
        89,
        portions: [
          ['1 medium', 118],
          ['1 cup, sliced', 150],
        ],
      ),
      _food('b', 'Cake, banana, with frosting', 380),
      _food('c', 'Potatoes, raw', 77),
      _food('d', 'Spinach, raw', 23),
    ],
  );
  String meta(Map<String, dynamic> p) => jsonEncode({
    for (final e in p.entries)
      if (e.key != 'cols' && e.key != 'foods') e.key: e.value,
  });
  return _Bundle({
    'assets/food_packs/manifest.json': jsonEncode({
      'packs': [
        {...jsonDecode(meta(india)), 'file': 'indb.json'},
        {...jsonDecode(meta(usda)), 'file': 'usda.json'},
      ],
    }),
    'assets/food_packs/indb.json': jsonEncode(india),
    'assets/food_packs/usda.json': jsonEncode(usda),
  });
}

Map<String, dynamic> _packInfo(String id, List<String> regions) => {
  for (final e in _pack(id, regions, const []).entries)
    if (e.key != 'cols' && e.key != 'foods') e.key: e.value,
};

class _Products implements ProductsRepository {
  int backendCalls = 0;
  @override
  Future<List<MealEntity>> getSupabaseFoodsByString(
    String searchString, {
    bool forResolution = false,
  }) async {
    backendCalls++;
    throw Exception('no backend');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Intake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  Map<String, bool> toggles = const {};
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    foodSourceToggles: toggles,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Custom implements CustomMealDataSource {
  @override
  List<MealDBO> getAllCustomMeals() => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Recipes implements RecipeDataSource {
  @override
  List<RecipeDBO> getAllRecipes() => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Cache implements RemoteSearchCacheDataSource {
  final stored = <MealDBO>[];
  @override
  List<MealDBO> getAllByMostRecentlyTouched() => const [];
  @override
  Future<void> cacheFromSearch(Iterable<MealDBO> incoming) async =>
      stored.addAll(incoming);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFoodSource', () {
    late LocalFoodSource source;
    setUp(() => source = LocalFoodSource(bundle: _bundle()));

    test('lists the packs from the manifest without loading foods', () async {
      final packs = await source.packs();
      expect(packs.map((p) => p.id), ['indb', 'usda']);
      expect(packs.first.regions, ['IN']);
      expect(packs.last.isGlobal, isTrue);
      expect(packs.first.license, 'Test licence');
    });

    test('a missing manifest means no packs, not a crash', () async {
      final empty = LocalFoodSource(bundle: _Bundle({}));
      expect(await empty.packs(), isEmpty);
      expect(await empty.search('banana'), isEmpty);
    });

    test('the region\'s own packs come first, then the global ones', () async {
      final india = await source.packsFor('IN');
      expect(india.map((p) => p.id), ['indb', 'usda']);
      final us = await source.packsFor('US');
      expect(us.map((p) => p.id), ['usda']);
      final none = await source.packsFor(null);
      expect(none.map((p) => p.id), ['usda']);
      // Codes are matched without regard to case.
      expect((await source.packsFor('in')).map((p) => p.id), ['indb', 'usda']);
    });

    test('a switched-off pack is left out', () async {
      final found = await source.search(
        'banana',
        region: 'IN',
        enabled: (id) => id != 'usda',
      );
      expect(found.map((m) => m.name), ['Banana chips']);
    });

    test('plain foods rank before dishes that only mention the word', () async {
      final found = await source.search('banana', region: 'US');
      expect(found.map((m) => m.name), [
        'Bananas, raw',
        'Cake, banana, with frosting',
      ]);
    });

    test(
      'for India, plain fruit still comes before an Indian dish of that name',
      () async {
        // Banana chips (INDB) and Bananas, raw (USDA) start the same; the recipe
        // database ranks a little lower.
        final found = await source.search('banana', region: 'IN');
        expect(found.first.name, 'Bananas, raw');
        expect(found.map((m) => m.name), contains('Banana chips'));
      },
    );

    test('the food itself comes before products made from it', () async {
      final bundle = _Bundle({
        'assets/food_packs/manifest.json': jsonEncode({
          'packs': [
            {
              ..._packInfo('cnf', ['CA']),
              'file': 'cnf.json',
            },
          ],
        }),
        'assets/food_packs/cnf.json': jsonEncode(
          _pack(
            'cnf',
            ['CA'],
            [
              _food('1', 'Potato flour', 357),
              _food('2', 'Potato pancakes', 268),
              _food('3', 'Potato, flesh, raw', 70),
              _food('4', 'Potatoes, raw', 77),
            ],
          ),
        ),
      });
      final found = await LocalFoodSource(
        bundle: bundle,
      ).search('potato', region: 'CA');
      expect(found.take(2).map((m) => m.name).toSet(), {
        'Potato, flesh, raw',
        'Potatoes, raw',
      });
    });

    test(
      'another name finds a food, after a match on the name itself',
      () async {
        final cols = [..._cols, 'aka'];
        List<dynamic> row(String code, String name, String aka) => [
          ..._food(code, name, 50),
          aka,
        ];
        final pack = {
          ..._pack(
            'ifct',
            ['IN'],
            [
              row('1', 'Banana, ripe', 'Kela; Vazhai pazham'),
              row('2', 'Kelp, dried', ''),
              row('3', 'Spinach', 'Palak; Palong shak'),
            ],
          ),
          'cols': cols,
        };
        final bundle = _Bundle({
          'assets/food_packs/manifest.json': jsonEncode({
            'packs': [
              {
                ..._packInfo('ifct', ['IN']),
                'file': 'ifct.json',
              },
            ],
          }),
          'assets/food_packs/ifct.json': jsonEncode(pack),
        });
        final source = LocalFoodSource(bundle: bundle);
        // "kel" starts a local name of banana and the real name of kelp: the
        // name match comes first.
        final kel = await source.search('kel', region: 'IN');
        expect(kel.map((m) => m.name), ['Kelp, dried', 'Banana, ripe']);
        // A whole local name finds the food.
        expect(
          (await source.search('palak', region: 'IN')).single.name,
          'Spinach',
        );
        expect(
          (await source.search('vazhai pazham', region: 'IN')).single.name,
          'Banana, ripe',
        );
        // A fragment in the middle of a local name does not.
        expect(await source.search('alak', region: 'IN'), isEmpty);
      },
    );

    test('every word has to be in the name', () async {
      expect((await source.search('raw potatoes')).map((m) => m.name), [
        'Potatoes, raw',
      ]);
      expect(await source.search('banana spinach'), isEmpty);
      expect(await source.search('   '), isEmpty);
    });

    test('an exact name beats a longer one that contains it', () async {
      final found = await source.search('spinach, raw');
      expect(found.first.name, 'Spinach, raw');
    });

    test('the limit is respected', () async {
      final found = await source.search('a', limit: 2);
      expect(found, hasLength(2));
    });

    test('a food becomes a meal with the units the app uses', () async {
      final banana = (await source.search('bananas')).single;
      expect(banana.code, 'usda:a');
      expect(banana.source, MealSourceEntity.fdc);
      expect(banana.backendSource, 'usda');
      expect(banana.mealUnit, 'g');
      expect(banana.nutriments.energyKcal100, 89);
      expect(banana.nutriments.proteins100, 1);
      expect(banana.nutriments.fiber100, 5);
      expect(banana.nutriments.sodium100, isNull);
      expect(banana.portions.map((p) => p.label), [
        '1 medium',
        '1 cup, sliced',
      ]);
      expect(banana.portions.first.gramWeight, 118);
      // The first portion is the default serving.
      expect(banana.servingQuantity, 118);
      expect(banana.servingSize, '1 medium (118 g)');
      expect(banana.scalableServingQuantity, 118);
    });

    test('a food with no portion has no serving to scale', () async {
      final potato = (await source.search('potatoes')).single;
      expect(potato.portions, isEmpty);
      expect(potato.servingQuantity, isNull);
      expect(potato.scalableServingQuantity, isNull);
    });

    test(
      'the same name in two packs stays two foods with their own codes',
      () async {
        final both = await source.search('banana', region: 'IN');
        expect(both.map((m) => m.code).toSet(), hasLength(both.length));
        expect(both.map((m) => m.backendSource), contains('indb'));
        expect(both.map((m) => m.backendSource), contains('usda'));
      },
    );
  });

  group('FoodRegion', () {
    test('reads the country from the device locale', () {
      expect(FoodRegion.deviceRegion([const Locale('en', 'in')]), 'IN');
      expect(FoodRegion.deviceRegion([const Locale('en', 'GB')]), 'GB');
      expect(FoodRegion.deviceRegion([const Locale('en')]), isNull);
      expect(FoodRegion.deviceRegion(const []), isNull);
    });

    test('a language with no country does not hide the one after it', () {
      // The app set to plain English, the phone to English (India).
      expect(
        FoodRegion.deviceRegion([const Locale('en'), const Locale('en', 'IN')]),
        'IN',
      );
      // The first country named wins.
      expect(
        FoodRegion.deviceRegion([
          const Locale('en', 'US'),
          const Locale('hi', 'IN'),
        ]),
        'US',
      );
    });

    test('without storage the saved choice is empty, not an error', () {
      expect(FoodRegion.savedChoice(), isNull);
    });

    test('every country that has a pack is named for Settings', () async {
      final raw = await rootBundle.loadString(LocalFoodSource.manifestPath);
      final packs = [
        for (final p in (jsonDecode(raw) as Map)['packs'] as List)
          LocalFoodPackInfo.fromJson(p as Map<String, dynamic>),
      ];
      for (final p in packs.where((p) => !p.isGlobal)) {
        for (final r in p.regions) {
          expect(
            FoodRegion.names.containsKey(r),
            isTrue,
            reason: '$r of ${p.id}',
          );
        }
      }
    });
  });

  group('the search use case', () {
    late _Products products;
    late _Config config;
    late _Cache cache;

    SearchProductsUseCase build({required bool backend, String? region}) =>
        SearchProductsUseCase(
          products,
          _Intake(),
          _Custom(),
          cache,
          _Recipes(),
          config,
          localFoods: LocalFoodSource(bundle: _bundle()),
          backendConfigured: backend,
          region: () => region,
        );

    setUp(() {
      products = _Products();
      config = _Config();
      cache = _Cache();
    });

    test(
      'without a backend, the bundled foods answer and nothing is called',
      () async {
        final result = await build(
          backend: false,
          region: 'IN',
        ).searchFDCFoodByString('banana');
        expect(products.backendCalls, 0);
        expect(result.remoteSourceFailed, isFalse);
        expect(result.meals.map((m) => m.name), contains('Bananas, raw'));
        expect(result.meals.map((m) => m.name), contains('Banana chips'));
        // Bundled foods are not copied into the search cache.
        expect(cache.stored, isEmpty);
      },
    );

    test(
      'a failing backend is not a failure while there are local foods',
      () async {
        final result = await build(
          backend: true,
          region: 'US',
        ).searchFDCFoodByString('banana');
        expect(products.backendCalls, 1);
        expect(result.remoteSourceFailed, isFalse);
        expect(result.meals, isNotEmpty);
      },
    );

    test(
      'a failing backend with nothing local still reports the failure',
      () async {
        final result = await build(
          backend: true,
          region: 'US',
        ).searchFDCFoodByString('zzzzz');
        expect(result.remoteSourceFailed, isTrue);
      },
    );

    test(
      'a short query skips the network but still searches the device',
      () async {
        final result = await build(
          backend: true,
          region: 'US',
        ).searchFDCFoodByString('spin', skipRemote: true);
        expect(products.backendCalls, 0);
        expect(result.meals.map((m) => m.name), ['Spinach, raw']);
      },
    );

    test('switching a database off in Settings removes its foods', () async {
      config.toggles = {'usda': false};
      final result = await build(
        backend: false,
        region: 'IN',
      ).searchFDCFoodByString('banana');
      expect(result.meals.map((m) => m.backendSource).toSet(), {'indb'});
    });

    test('the region decides which database leads on a tie', () async {
      // "raw" is in USDA names only; "chips" only in INDB: both regions find them.
      final india = await build(
        backend: false,
        region: 'IN',
      ).searchFDCFoodByString('chips');
      expect(india.meals.single.backendSource, 'indb');
      final us = await build(
        backend: false,
        region: 'US',
      ).searchFDCFoodByString('chips');
      expect(us.meals, isEmpty);
    });
  });

  group('the databases shipped in the app', () {
    late LocalFoodSource source;
    setUp(() => source = LocalFoodSource());

    test('the manifest lists every pack with its licence and credit', () async {
      final packs = await source.packs();
      expect(
        packs.map((p) => p.id),
        containsAll(['usda', 'indb', 'ifct', 'cofid', 'cnf', 'afcd']),
      );
      for (final p in packs) {
        expect(p.name, isNotEmpty, reason: p.id);
        expect(p.license, isNotEmpty, reason: p.id);
        expect(p.attribution, isNotEmpty, reason: p.id);
        expect(p.url, startsWith('https://'), reason: p.id);
        expect(p.regions, isNotEmpty, reason: p.id);
      }
    });

    test(
      'every pack has a name, short name and link for the source chips',
      () async {
        for (final p in await source.packs()) {
          expect(
            SPConst.foodSourceDisplayNames.containsKey(p.id),
            isTrue,
            reason: p.id,
          );
          expect(
            SPConst.foodSourceShortNames.containsKey(p.id),
            isTrue,
            reason: p.id,
          );
          expect(
            SPConst.foodSourceWebsites.containsKey(p.id),
            isTrue,
            reason: p.id,
          );
        }
      },
    );

    test(
      'everyday fruit and vegetables are found in the global pack',
      () async {
        for (final q in [
          'banana raw',
          'spinach raw',
          'tomatoes raw',
          'carrots raw',
          'apples raw',
        ]) {
          final found = await source.search(q, region: 'US');
          expect(found, isNotEmpty, reason: q);
          expect(found.first.backendSource, 'usda', reason: q);
          expect(
            found.first.nutriments.energyKcal100,
            inInclusiveRange(10, 120),
            reason: q,
          );
        }
      },
    );

    test(
      'Indian dishes are found for India and not for the United States',
      () async {
        final india = await source.search('chapati', region: 'IN');
        expect(india.map((m) => m.backendSource), contains('indb'));
        final us = await source.search('chapati', region: 'US');
        expect(us.map((m) => m.backendSource), isNot(contains('indb')));
      },
    );

    test(
      'for India, Indian produce comes first, found by English or local name',
      () async {
        for (final (query, expected) in [
          ('banana', 'Banana'),
          ('palak', 'Spinach'),
          ('aloo', 'Potato'),
          ('baingan', 'Brinjal'),
          ('bhindi', 'Ladies finger'),
          ('tomato', 'Tomato'),
          ('mango', 'Mango'),
        ]) {
          final found = await source.search(query, region: 'IN');
          expect(found, isNotEmpty, reason: query);
          expect(found.first.backendSource, 'ifct', reason: query);
          expect(found.first.name, startsWith(expected), reason: query);
        }
        // "Kela" is Hindi for banana and plantain alike, so both are offered.
        final kela = await source.search('kela', region: 'IN');
        expect(kela.first.backendSource, 'ifct');
        expect(
          kela.map((m) => m.name).any((n) => (n ?? '').startsWith('Banana')),
          isTrue,
        );
      },
    );

    test(
      'Indian produce is not offered ahead of other regions by local name',
      () async {
        // "palak" means nothing in the worldwide databases.
        expect(await source.search('palak', region: 'US'), isEmpty);
        expect(await source.search('kela', region: 'GB'), isEmpty);
      },
    );

    test('IFCT values are in the units the app uses', () async {
      final banana = (await source.search('banana', region: 'IN')).first;
      final n = banana.nutriments;
      // Banana, ripe: 463 kJ in the book is about 111 kcal.
      expect(n.energyKcal100, inInclusiveRange(95, 125));
      expect(n.carbohydrates100, inInclusiveRange(20, 30));
      expect(n.fiber100, inInclusiveRange(1, 4));
      // Minerals and vitamin C are in mg (not g), vitamin A in ug.
      expect(n.calcium100, inInclusiveRange(1, 50));
      expect(n.vitaminC100, inInclusiveRange(1, 60));
      final spinach = (await source.search('spinach', region: 'IN')).first;
      expect(spinach.nutriments.vitaminA100, greaterThan(100));
      expect(spinach.nutriments.iron100, inInclusiveRange(0.5, 10));
    });

    test('each region finds its own database for a common food', () async {
      for (final (region, id) in [
        ('GB', 'cofid'),
        ('CA', 'cnf'),
        ('AU', 'afcd'),
      ]) {
        final found = await source.search('potato', region: region);
        expect(found.map((m) => m.backendSource), contains(id), reason: region);
      }
    });

    test(
      'every food is plausible: energy and macros agree within reason',
      () async {
        for (final p in await source.packs()) {
          final raw = await rootBundle.loadString(
            'assets/food_packs/${p.file}',
          );
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final pack = LocalFoodPack.fromJson(p, json);
          expect(pack.length, p.count, reason: p.id);
          var checked = 0;
          for (var i = 0; i < pack.length; i += 7) {
            final m = pack.toMeal(i);
            final n = m.nutriments;
            expect(m.name, isNotEmpty, reason: '${p.id} #$i');
            expect(n.energyKcal100, isNotNull, reason: m.name);
            expect(
              n.energyKcal100!,
              inInclusiveRange(0, 910),
              reason: '${p.id} ${m.name}',
            );
            final macros =
                (n.proteins100 ?? 0) +
                (n.fat100 ?? 0) +
                (n.carbohydrates100 ?? 0);
            expect(macros, lessThanOrEqualTo(105), reason: '${p.id} ${m.name}');
            checked++;
          }
          expect(checked, greaterThan(50), reason: p.id);
        }
      },
    );

    test('codes are unique across all packs', () async {
      final seen = <String>{};
      for (final p in await source.packs()) {
        final raw = await rootBundle.loadString('assets/food_packs/${p.file}');
        final pack = LocalFoodPack.fromJson(
          p,
          jsonDecode(raw) as Map<String, dynamic>,
        );
        for (var i = 0; i < pack.length; i++) {
          final code = '${p.id}:${pack.rows[i][0]}';
          expect(seen.add(code), isTrue, reason: code);
        }
      }
    });
  });
}
