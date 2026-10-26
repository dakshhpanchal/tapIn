import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum NewFoodMode { nutrition, ingredients }

/// The one "New food" screen is two forms behind a toggle: type in nutrition
/// values, or build the food from ingredients. Both creation screens show
/// this under their app bar while a new food is being made; picking the other
/// mode swaps the screen in place.
class NewFoodModeSwitch extends StatelessWidget implements PreferredSizeWidget {
  final NewFoodMode current;
  final bool usesImperialUnits;

  const NewFoodModeSwitch({
    super.key,
    required this.current,
    this.usesImperialUnits = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        Dimens.spacing8,
      ),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<NewFoodMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: NewFoodMode.nutrition,
              label: Text(s.foodModeNutritionLabel),
            ),
            ButtonSegment(
              value: NewFoodMode.ingredients,
              label: Text(s.foodModeIngredientsLabel),
            ),
          ],
          selected: {current},
          onSelectionChanged: (picked) {
            if (picked.first == current) return;
            openNewFood(
              context,
              picked.first,
              usesImperialUnits: usesImperialUnits,
              replace: true,
            );
          },
        ),
      ),
    );
  }
}

/// Opens the New food screen in [mode]; [replace] swaps the current screen
/// instead of stacking another on top.
Future<void> openNewFood(
  BuildContext context,
  NewFoodMode mode, {
  bool usesImperialUnits = false,
  bool replace = false,
}) {
  final navigator = Navigator.of(context);
  final route = mode == NewFoodMode.ingredients
      ? NavigationOptions.recipeBuilderRoute
      : NavigationOptions.editMealRoute;
  final Object arguments = mode == NewFoodMode.ingredients
      ? const RecipeBuilderArguments(newFood: true)
      : EditMealScreenArguments(
          DateTime.now(),
          MealEntity.empty(),
          IntakeTypeEntity.breakfast,
          usesImperialUnits,
          editOnly: true,
          newFood: true,
        );
  return replace
      ? navigator.pushReplacementNamed(route, arguments: arguments)
      : navigator.pushNamed(route, arguments: arguments);
}
