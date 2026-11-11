import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';

class _FakeConfig implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// A recents list the test can hide foods from, like the real store.
class _FakeIntake implements GetIntakeUsecase {
  final List<IntakeEntity> all;
  final hiddenCodes = <String?>{};
  _FakeIntake(this.all);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => [
    for (final i in all)
      if (!hiddenCodes.contains(i.meal.code)) i,
  ];

  @override
  Future<void> hideFromRecents(MealEntity meal) async =>
      hiddenCodes.add(meal.code);

  @override
  Future<void> showInRecents(MealEntity meal) async =>
      hiddenCodes.remove(meal.code);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

MealEntity _meal(String code, String name) => MealEntity(
  code: code,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.custom,
);

IntakeEntity _intake(MealEntity meal) => IntakeEntity(
  id: meal.code!,
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  dateTime: DateTime(2026, 11, 1),
  meal: meal,
);

void main() {
  final coffee = _meal('coffee', 'Cold Coffee');
  final oats = _meal('oats', 'Oats');
  late _FakeIntake intake;
  late RecentMealBloc bloc;

  setUp(() {
    intake = _FakeIntake([_intake(coffee), _intake(oats)]);
    bloc = RecentMealBloc(intake, _FakeConfig());
  });

  tearDown(() => bloc.close());

  Future<List<String?>> names() async {
    // The next loaded state after whatever was just added.
    final state = await bloc.stream.firstWhere(
      (s) => s is RecentMealLoadedState,
    );
    return [
      for (final m in (state as RecentMealLoadedState).recentMeals) m.name,
    ];
  }

  test(
    'removing a food drops it from the list and Undo brings it back',
    () async {
      bloc.add(const LoadRecentMealEvent(searchString: ''));
      expect(await names(), ['Cold Coffee', 'Oats']);

      bloc.add(RemoveRecentMealEvent(coffee));
      expect(await names(), ['Oats']);

      bloc.add(RestoreRecentMealEvent(coffee));
      expect(await names(), ['Cold Coffee', 'Oats']);
    },
  );

  test('the search text is kept when a food is removed', () async {
    bloc.add(const LoadRecentMealEvent(searchString: 'o'));
    expect(await names(), ['Cold Coffee', 'Oats']);

    bloc.add(const LoadRecentMealEvent(searchString: 'oat'));
    expect(await names(), ['Oats']);

    bloc.add(RemoveRecentMealEvent(coffee));
    // Coffee is not in the 'oat' view, and the view stays filtered.
    expect(await names(), ['Oats']);
  });

  test('removing the last food leaves an empty list', () async {
    bloc.add(const LoadRecentMealEvent(searchString: ''));
    await names();
    bloc.add(RemoveRecentMealEvent(coffee));
    await names();
    bloc.add(RemoveRecentMealEvent(oats));
    expect(await names(), isEmpty);
  });
}
