import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_detail_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/custom_meals_tab.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/recipe_list_item.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "My foods": one list for everything the user created themselves — recipes
/// built from ingredients and single foods entered from a nutrition label.
/// They are one concept here; the only difference is how they are edited.
class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

/// A row in the unified list: exactly one of [recipe] / [meal] is set.
class _FoodRow {
  final RecipeEntity? recipe;
  final MealEntity? meal;
  const _FoodRow.recipe(RecipeEntity this.recipe) : meal = null;
  const _FoodRow.meal(MealEntity this.meal) : recipe = null;

  /// Selection key; prefixed so a recipe id can't collide with a meal code.
  String get key => recipe != null
      ? 'r:${recipe!.id}'
      : 'm:${CustomMealsTab.keyFor(meal!)}';
  String get name => (recipe?.name ?? meal?.name ?? '').toString();
}

class _RecipesPageState extends State<RecipesPage> with WidgetsBindingObserver {
  late RecipesBloc _bloc;
  late CustomMealsBloc _customMealsBloc;
  late TextEditingController _searchController;
  String _searchQuery = '';
  String? _activeTag;
  bool _usesImperialUnits = false;
  // Multi-select state. Empty set = normal mode.
  final Set<String> _selectedKeys = {};
  bool get _selectionMode => _selectedKeys.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = locator<RecipesBloc>();
    _customMealsBloc = locator<CustomMealsBloc>()..add(LoadCustomMealsEvent());
    _searchController = TextEditingController();
    _bloc.add(const LoadRecipesEvent());
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (mounted) {
      setState(() => _usesImperialUnits = config.usesImperialFoodUnits);
    }
  }

  void _reload() {
    _bloc.add(const LoadRecipesEvent());
    _customMealsBloc.add(LoadCustomMealsEvent());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Standalone pushed screen (reached from Add and from You): it owns its
    // Scaffold + AppBar so the title bar clears the status bar / notch.
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.myFoodsLabel),
        actions: [
          PopupMenuButton<_FoodAction>(
            tooltip: s.addLabel,
            icon: const Icon(Icons.add),
            onSelected: (action) => _onAddSelected(context, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _FoodAction.newRecipe,
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(s.createRecipeTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _FoodAction.newFood,
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(s.newCustomMealLabel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _FoodAction.importRecipe,
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner_outlined),
                    const SizedBox(width: Dimens.spacing12),
                    Text(s.importRecipeLabel),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: MultiBlocProvider(
        providers: [
          BlocProvider<RecipesBloc>.value(value: _bloc),
          BlocProvider<CustomMealsBloc>.value(value: _customMealsBloc),
        ],
        child: BlocListener<CustomMealsBloc, CustomMealsState>(
          listenWhen: (prev, curr) => curr is CustomMealsMergedState,
          listener: (context, state) {
            if (state is CustomMealsMergedState) {
              showCustomMealsMergedSnackbar(context, state);
            }
          },
          child: _buildList(),
        ),
      ),
    );
  }

  Future<void> _onAddSelected(BuildContext context, _FoodAction action) async {
    switch (action) {
      case _FoodAction.newRecipe:
        await Navigator.of(
          context,
        ).pushNamed(NavigationOptions.recipeBuilderRoute);
      case _FoodAction.newFood:
        await Navigator.of(context).pushNamed(
          NavigationOptions.editMealRoute,
          arguments: EditMealScreenArguments(
            DateTime.now(),
            MealEntity.empty(),
            IntakeTypeEntity.breakfast,
            false,
            editOnly: true,
          ),
        );
      case _FoodAction.importRecipe:
        await Navigator.of(
          context,
        ).pushNamed(NavigationOptions.importRecipeScannerRoute);
    }
    if (mounted) _reload();
  }

  Widget _buildList() {
    return BlocBuilder<RecipesBloc, RecipesState>(
      bloc: _bloc,
      builder: (context, recipesState) {
        return BlocBuilder<CustomMealsBloc, CustomMealsState>(
          bloc: _customMealsBloc,
          builder: (context, mealsState) {
            final loading =
                recipesState is RecipesLoading ||
                recipesState is RecipesInitial ||
                mealsState is CustomMealsLoadingState ||
                mealsState is CustomMealsInitial;
            if (loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (recipesState is RecipesFailed) {
              // Don't expose raw exception text to users.
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    S.of(context).recipesLoadErrorLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final recipes = recipesState is RecipesLoaded
                ? recipesState.recipes
                : const <RecipeEntity>[];
            final meals = mealsState is CustomMealsLoadedState
                ? mealsState.meals
                : const <MealEntity>[];
            final rows = <_FoodRow>[
              for (final r in recipes) _FoodRow.recipe(r),
              for (final m in meals) _FoodRow.meal(m),
            ]..sort(
                (a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
            if (rows.isEmpty) return _buildEmptyState(context);
            return _buildContent(context, rows, recipes, meals);
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<_FoodRow> rows,
    List<RecipeEntity> recipes,
    List<MealEntity> meals,
  ) {
    final q = _searchQuery.trim().toLowerCase();
    // Tags exist on recipes only; the chip row is skipped when none have any.
    final allTags = recipes.expand((r) => r.tags).toSet().toList()..sort();
    if (_activeTag != null && !allTags.contains(_activeTag)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? setState(() => _activeTag = null) : null,
      );
    }
    final filtered = rows.where((row) {
      final matchesQuery = q.isEmpty || row.name.toLowerCase().contains(q);
      final matchesTag =
          _activeTag == null ||
          (row.recipe != null && row.recipe!.tags.contains(_activeTag));
      return matchesQuery && matchesTag;
    }).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing12,
            Dimens.spacing16,
            Dimens.spacing4,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.surfaceMuted,
              hintText: S.of(context).searchLabel,
              prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        color: palette.textMuted,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (allTags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing4,
                  ),
                  child: ChoiceChip(
                    label: Text(S.of(context).recipesFilterAllLabel),
                    selected: _activeTag == null,
                    onSelected: (_) => setState(() => _activeTag = null),
                  ),
                ),
                for (final tag in allTags)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimens.spacing4,
                    ),
                    child: ChoiceChip(
                      label: Text(tag),
                      selected: _activeTag == tag,
                      onSelected: (selected) =>
                          setState(() => _activeTag = selected ? tag : null),
                    ),
                  ),
              ],
            ),
          ),
        if (_selectionMode) _buildSelectionBar(context),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Dimens.spacing32),
                    child: Text(
                      S.of(context).myFoodsEmptyLabel,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.spacing8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, filtered[index], meals, palette),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    _FoodRow row,
    List<MealEntity> allMeals,
    AppPalette palette,
  ) {
    final isSelected = _selectedKeys.contains(row.key);
    void toggleSelected() => setState(() {
      if (!_selectedKeys.remove(row.key)) _selectedKeys.add(row.key);
    });

    final recipe = row.recipe;
    if (recipe != null) {
      return RecipeListItem(
        recipe: recipe,
        isSelected: isSelected,
        onTap: () async {
          if (_selectionMode) return toggleSelected();
          await Navigator.of(context).pushNamed(
            NavigationOptions.recipeDetailRoute,
            arguments: RecipeDetailArguments(recipeId: recipe.id),
          );
          if (mounted) _reload();
        },
        onLongPress: () => setState(() => _selectedKeys.add(row.key)),
      );
    }

    final meal = row.meal!;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing4,
      ),
      child: AppCard(
        color: isSelected ? accent.withValues(alpha: 0.12) : null,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: Dimens.borderRadiusL,
          onTap: () async {
            if (_selectionMode) return toggleSelected();
            await CustomMealsTab.openEditMeal(
              context,
              meal,
              _usesImperialUnits,
            );
            if (mounted) _reload();
          },
          onLongPress: () => setState(() => _selectedKeys.add(row.key)),
          child: Padding(
            padding: const EdgeInsets.all(Dimens.spacing12),
            child: Row(
              children: [
                MealLeadingThumbnail(meal: meal),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (meal.brands != null) ...[
                        const SizedBox(height: Dimens.spacing4),
                        Text(
                          meal.brands!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: accent, size: 24)
                else if (allMeals.length >= 2)
                  Semantics(
                    identifier: 'custom-foods-merge-open',
                    child: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: palette.textMuted,
                      ),
                      tooltip: S.of(context).customMealsRowMoreTooltip,
                      onSelected: (value) {
                        if (value == 'merge') {
                          CustomMealsTab.startMerge(context, meal, allMeals);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem<String>(
                          value: 'merge',
                          child: Text(S.of(context).customMealsMergeAction),
                        ),
                      ],
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textMuted,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing4,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing8,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Dimens.borderRadiusM,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.dialogCancelLabel,
            icon: Icon(Icons.close_rounded, color: accent),
            onPressed: () => setState(_selectedKeys.clear),
          ),
          Expanded(
            child: Text(
              s.selectionCountLabel(_selectedKeys.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: s.dialogDeleteLabel,
            icon: Icon(Icons.delete_outline_rounded, color: accent),
            onPressed: _onBulkDelete,
          ),
        ],
      ),
    );
  }

  Future<void> _onBulkDelete() async {
    final s = S.of(context);
    final count = _selectedKeys.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteSelectedRecipesConfirmTitle(count)),
        content: Text(s.recipeDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.dialogDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleteRecipe = locator<DeleteRecipeUseCase>();
    for (final key in _selectedKeys) {
      if (key.startsWith('r:')) {
        await deleteRecipe.delete(key.substring(2));
      } else {
        _customMealsBloc.add(DeleteCustomMealEvent(key.substring(2)));
      }
    }
    if (!mounted) return;
    setState(_selectedKeys.clear);
    _bloc.add(const LoadRecipesEvent());
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(Dimens.spacing24),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.menu_book_rounded, size: 56, color: accent),
            ),
            const SizedBox(height: Dimens.spacing24),
            Text(
              S.of(context).myFoodsEmptyLabel,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Dimens.spacing8),
            Text(
              S.of(context).recipesEmptyHint,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _FoodAction { newRecipe, newFood, importRecipe }
