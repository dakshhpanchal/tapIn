import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/food_region.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_source.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/food_sources_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

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

Map<String, dynamic> _meta(String id, String name, List<String> regions) => {
  'id': id,
  'file': '$id.json',
  'name': name,
  'short': id.toUpperCase(),
  'regions': regions,
  'license': 'Licence of $id',
  'attribution': 'Credit line for $id',
  'url': 'https://example.org/$id',
  'version': '1',
  'count': 1234,
};

_Bundle _bundle() => _Bundle({
  'assets/food_packs/manifest.json': jsonEncode({
    'packs': [
      _meta('indb', 'Indian Nutrient Databank', ['IN']),
      _meta('usda', 'USDA FoodData Central', ['*']),
    ],
  }),
});

class _Config implements GetConfigUsecase {
  Map<String, bool> toggles = {};
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

class _AddConfig implements AddConfigUsecase {
  Map<String, bool>? saved;
  @override
  Future<void> setConfigFoodSourceToggles(Map<String, bool> toggles) async =>
      saved = Map.of(toggles);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Provider extends Fake implements HiveDBProvider {
  @override
  final Box<String> gymMetaBox;
  _Provider(this.gymMetaBox);
}

void main() {
  late _Config config;
  late _AddConfig addConfig;

  setUp(() async {
    config = _Config();
    addConfig = _AddConfig();
    final box = await Hive.openBox<String>('meta', bytes: Uint8List(0));
    locator.registerSingleton<HiveDBProvider>(_Provider(box));
    locator.registerSingleton<GetConfigUsecase>(config);
    locator.registerSingleton<AddConfigUsecase>(addConfig);
  });

  tearDown(() async {
    await Hive.close();
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester, {bool backend = false}) async {
    tester.view.physicalSize = const Size(400 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: FoodSourcesScreen(
          localFoods: LocalFoodSource(bundle: _bundle()),
          backendConfigured: backend,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the databases built into the app with licence and count', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Built into the app'), findsOneWidget);
    expect(find.text('USDA FoodData Central'), findsOneWidget);
    expect(find.textContaining('1234 foods · Licence of usda'), findsOneWidget);
    // INDB is for India, so it is not offered to a device with no region.
    expect(find.text('Indian Nutrient Databank'), findsNothing);
  });

  testWidgets('a build without a backend does not offer the online databases', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Open Food Facts'), findsOneWidget);
    expect(find.text('FoodData Central (Foundation Foods)'), findsNothing);
    expect(find.text('Bundeslebensmittelschlüssel (BLS)'), findsNothing);
  });

  testWidgets('a build with a backend still offers them', (tester) async {
    await open(tester, backend: true);
    expect(find.text('FoodData Central (Foundation Foods)'), findsOneWidget);
  });

  testWidgets('picking India brings its database in, marked for the region', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Region'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('India'));
    await tester.pumpAndSettle();

    expect(FoodRegion.savedChoice(), 'IN');
    expect(find.text('Indian Nutrient Databank'), findsOneWidget);
    expect(find.textContaining('For your region'), findsOneWidget);
    // The region's own database is listed before the global one.
    final indb = tester.getTopLeft(find.text('Indian Nutrient Databank')).dy;
    final usda = tester.getTopLeft(find.text('USDA FoodData Central')).dy;
    expect(indb < usda, isTrue);
  });

  testWidgets(
    '"Other" keeps only the worldwide databases, and Automatic undoes it',
    (tester) async {
      await FoodRegion.choose('IN');
      await open(tester);
      expect(find.text('Indian Nutrient Databank'), findsOneWidget);

      await tester.tap(find.text('Region'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other (worldwide databases only)'));
      await tester.pumpAndSettle();
      expect(FoodRegion.savedChoice(), 'ZZ');
      expect(find.text('Indian Nutrient Databank'), findsNothing);
      expect(find.text('USDA FoodData Central'), findsOneWidget);

      await tester.tap(find.text('Region'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Automatic'));
      await tester.pumpAndSettle();
      expect(FoodRegion.savedChoice(), isNull);
    },
  );

  testWidgets('switching a database off is saved, and its credit goes', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Credit line for usda'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'USDA FoodData Central'),
    );
    await tester.pumpAndSettle();
    expect(addConfig.saved, {'usda': false});
    expect(find.text('Credit line for usda'), findsNothing);
  });

  testWidgets('a database switched off earlier shows as off', (tester) async {
    config.toggles = {'usda': false};
    await open(tester);
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'USDA FoodData Central'),
    );
    expect(tile.value, isFalse);
  });
}
