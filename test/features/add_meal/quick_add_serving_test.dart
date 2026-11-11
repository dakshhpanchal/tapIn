import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

MealEntity _meal({
  required double? servingQuantity,
  required String servingUnit,
  required String servingSize,
  String mealUnit = 'gml',
  String? mealQuantity = '100',
  MealSourceEntity source = MealSourceEntity.custom,
}) => MealEntity(
  code: 'quick',
  name: 'Cold Coffee',
  url: null,
  mealQuantity: mealQuantity,
  mealUnit: mealUnit,
  servingQuantity: servingQuantity,
  servingUnit: servingUnit,
  servingSize: servingSize,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 161,
    carbohydrates100: 20,
    fat100: 5,
    proteins100: 4,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
);

/// Quick add as it was stored before it saved a serving.
MealEntity legacy() =>
    _meal(servingQuantity: null, servingUnit: 'gml', servingSize: '');

/// Quick add as it is stored now.
MealEntity current() =>
    _meal(servingQuantity: 100, servingUnit: 'g', servingSize: '1 serving');

IntakeEntity _intake(MealEntity meal, String unit) => IntakeEntity(
  id: 'i',
  unit: unit,
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  dateTime: DateTime(2026, 1, 1),
  meal: meal,
);

Widget _card(IntakeEntity intake) => ChangeNotifierProvider<EnergyUnitProvider>(
  create: (_) => EnergyUnitProvider(usesKilojoules: false),
  child: MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: IntakeCard(
        key: const ValueKey('card'),
        intake: intake,
        firstListElement: false,
        usesImperialUnits: false,
      ),
    ),
  ),
);

void main() {
  group('an older Quick add', () {
    test('is recognised and counts as one serving of 100', () {
      expect(legacy().isLegacyQuickAdd, isTrue);
      expect(legacy().scalableServingQuantity, 100);
    });

    test('a scanned or typed food is not mistaken for one', () {
      // Another unit, another quantity, a real serving, or another source.
      expect(
        _meal(
          servingQuantity: null,
          servingUnit: 'gml',
          servingSize: '',
          mealUnit: 'g',
        ).isLegacyQuickAdd,
        isFalse,
      );
      expect(
        _meal(
          servingQuantity: null,
          servingUnit: 'gml',
          servingSize: '',
          mealQuantity: '250',
        ).isLegacyQuickAdd,
        isFalse,
      );
      expect(
        _meal(
          servingQuantity: null,
          servingUnit: 'gml',
          servingSize: '30 g',
        ).isLegacyQuickAdd,
        isFalse,
      );
      expect(
        _meal(
          servingQuantity: null,
          servingUnit: 'gml',
          servingSize: '',
          source: MealSourceEntity.off,
        ).isLegacyQuickAdd,
        isFalse,
      );
      // Nothing to scale on a custom food with no serving at all.
      expect(
        _meal(
          servingQuantity: null,
          servingUnit: 'gml',
          servingSize: '',
          mealQuantity: null,
        ).scalableServingQuantity,
        isNull,
      );
    });

    testWidgets('reads as 1 serving in the diary, not 100 g/ml', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_intake(legacy(), 'g')));
      await tester.pumpAndSettle();
      expect(find.text('1 serving'), findsOneWidget);
      expect(find.textContaining('g/ml'), findsNothing);
    });
  });

  group('a Quick add made now', () {
    test('is a serving of 100 g and not flagged as an older one', () {
      expect(current().isLegacyQuickAdd, isFalse);
      expect(current().scalableServingQuantity, 100);
    });

    testWidgets('reads as 1 serving in the diary', (tester) async {
      await tester.pumpWidget(_card(_intake(current(), 'serving')));
      await tester.pumpAndSettle();
      expect(find.text('1 serving'), findsOneWidget);
      expect(find.textContaining('g/ml'), findsNothing);
    });

    test('its calories are unchanged by being a serving', () {
      expect(_intake(current(), 'serving').totalKcal, closeTo(161, 0.001));
      expect(_intake(legacy(), 'g').totalKcal, closeTo(161, 0.001));
    });
  });
}
