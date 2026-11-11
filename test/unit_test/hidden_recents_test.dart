import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/hidden_recents.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

MealEntity _meal(String code, String name) => MealEntity(
  code: code,
  name: name,
  url: null,
  mealQuantity: '100',
  mealUnit: 'gml',
  servingQuantity: 100,
  servingUnit: 'g',
  servingSize: '1 serving',
  nutriments: MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 10,
    fat100: 2,
    proteins100: 3,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

IntakeEntity _intake(MealEntity meal, DateTime at) => IntakeEntity(
  id: '${meal.code}-${at.millisecondsSinceEpoch}',
  unit: 'serving',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  dateTime: at,
  meal: meal,
);

/// What the data source returns: the newest intake of each food.
class _FakeIntakes extends Fake implements IntakeRepository {
  List<IntakeEntity> recent;
  _FakeIntakes(this.recent);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;
}

class _FakeRecipes extends Fake implements RecipeRepository {}

void main() {
  late Box<String> box;
  late HiddenRecents hidden;

  setUp(() async {
    box = await Hive.openBox<String>('hidden', bytes: Uint8List(0));
    hidden = HiddenRecents(box);
  });

  tearDown(() async => Hive.close());

  final coffee = _meal('coffee', 'Cold Coffee');
  final oats = _meal('oats', 'Oats');

  test('nothing is hidden at first', () {
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 1)), isFalse);
  });

  test('a hidden food stays hidden until it is logged again', () async {
    await hidden.hide(coffee, at: DateTime(2026, 11, 5, 12));
    // Last logged before it was hidden: still hidden.
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 5, 9)), isTrue);
    // Logged again afterwards: back.
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 6, 9)), isFalse);
    // Other foods are not affected.
    expect(hidden.isHidden(oats, DateTime(2026, 11, 5, 9)), isFalse);
  });

  test('show puts it back straight away', () async {
    await hidden.hide(coffee, at: DateTime(2026, 11, 5, 12));
    await hidden.show(coffee);
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 5, 9)), isFalse);
  });

  test('the choice survives reopening the store', () async {
    await hidden.hide(coffee, at: DateTime(2026, 11, 5, 12));
    expect(
      HiddenRecents(box).isHidden(coffee, DateTime(2026, 11, 5, 9)),
      isTrue,
    );
  });

  test('an unreadable value hides nothing', () async {
    await box.put('hidden_recents', 'not json');
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 5, 9)), isFalse);
  });

  test('a food with no code is told apart by name', () async {
    final noCode = MealEntity(
      code: null,
      name: 'Plain rice',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: _meal('x', 'x').nutriments,
      source: MealSourceEntity.custom,
    );
    await hidden.hide(noCode, at: DateTime(2026, 11, 5, 12));
    expect(hidden.isHidden(noCode, DateTime(2026, 11, 5, 9)), isTrue);
    expect(hidden.isHidden(coffee, DateTime(2026, 11, 5, 9)), isFalse);
  });

  group('the recents list', () {
    test('leaves out hidden foods and keeps the rest in order', () async {
      final usecase = GetIntakeUsecase(
        _FakeIntakes([
          _intake(coffee, DateTime(2026, 11, 5, 9)),
          _intake(oats, DateTime(2026, 11, 4, 9)),
        ]),
        _FakeRecipes(),
        hiddenRecents: hidden,
      );
      expect((await usecase.getRecentIntake()).map((i) => i.meal.name), [
        'Cold Coffee',
        'Oats',
      ]);

      await usecase.hideFromRecents(coffee);
      expect((await usecase.getRecentIntake()).map((i) => i.meal.name), [
        'Oats',
      ]);

      await usecase.showInRecents(coffee);
      expect((await usecase.getRecentIntake()).map((i) => i.meal.name), [
        'Cold Coffee',
        'Oats',
      ]);
    });

    test('logging a hidden food again brings it back', () async {
      final repo = _FakeIntakes([_intake(coffee, DateTime(2026, 11, 5, 9))]);
      final usecase = GetIntakeUsecase(
        repo,
        _FakeRecipes(),
        hiddenRecents: hidden,
      );
      await hidden.hide(coffee, at: DateTime(2026, 11, 5, 12));
      expect(await usecase.getRecentIntake(), isEmpty);

      repo.recent = [
        _intake(coffee, DateTime.now().add(const Duration(minutes: 1))),
      ];
      expect(await usecase.getRecentIntake(), hasLength(1));
    });

    test('without a store everything shows, and hiding does nothing', () async {
      final usecase = GetIntakeUsecase(
        _FakeIntakes([_intake(coffee, DateTime(2026, 11, 5, 9))]),
        _FakeRecipes(),
      );
      await usecase.hideFromRecents(coffee);
      expect(await usecase.getRecentIntake(), hasLength(1));
    });
  });
}
