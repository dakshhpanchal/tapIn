import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

IntakeEntity _intake(String unit, double amount, double? servingQuantity) =>
    IntakeEntity(
      id: 'i',
      unit: unit,
      amount: amount,
      type: IntakeTypeEntity.breakfast,
      dateTime: DateTime(2026, 10, 1),
      meal: MealEntity(
        code: 'c',
        name: 'Oats',
        brands: null,
        thumbnailImageUrl: null,
        mainImageUrl: null,
        url: null,
        mealQuantity: '300',
        mealUnit: 'g',
        servingQuantity: servingQuantity,
        servingUnit: 'g',
        servingSize: '1 servings',
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.custom,
      ),
    );

void main() {
  test('a serving-logged intake shows servings, not grams', () {
    expect(intakeServingCount(_intake('serving', 150, 300)), 0.5);
    expect(intakeServingCount(_intake('serving', 200, 100)), 2);
    expect(formatServingCount(1.5), '1.5');
    expect(formatServingCount(2), '2');
    expect(formatServingCount(1 / 3), '0.33');
  });

  test('gram-logged or serving-less intakes keep their gram display', () {
    expect(intakeServingCount(_intake('g', 100, 300)), isNull);
    expect(intakeServingCount(_intake('serving', 100, null)), isNull);
    expect(intakeServingCount(_intake('serving', 100, 0)), isNull);
  });
}
