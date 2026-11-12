import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/off_account/data/off_contribution_service.dart';

void main() {
  test('a corrected product shows the sent figures and keeps the rest', () {
    const meal = MealEntity(
      code: '8901764175022',
      name: 'Maaza',
      url: null,
      mealQuantity: '200',
      mealUnit: 'ml',
      servingQuantity: 200,
      servingUnit: 'ml',
      servingSize: '200 ml',
      nutriments: MealNutrimentsEntity(
        energyKcal100: 10,
        carbohydrates100: 2,
        fat100: 0,
        proteins100: 0,
        sugars100: 2,
        saturatedFat100: null,
        fiber100: null,
        calcium100: 7,
      ),
      source: MealSourceEntity.off,
      detailed: true,
    );
    const sent = OffProductSubmission(
      barcode: '8901764175022',
      name: 'Maaza',
      energyKcal: 55,
      carbohydrates: 13.5,
      fat: 0.2,
      proteins: 0.1,
      salt: 0.025,
    );
    final updated = applySubmission(meal, sent);
    expect(updated.nutriments.energyKcal100, 55);
    expect(updated.nutriments.carbohydrates100, 13.5);
    expect(updated.nutriments.sugars100, 2); // not sent: kept
    expect(updated.nutriments.sodium100, closeTo(10, 1e-9));
    expect(updated.nutriments.calcium100, 7);
    expect(updated.detailed, isTrue);
    expect(updated.servingSize, '200 ml');
  });
}
