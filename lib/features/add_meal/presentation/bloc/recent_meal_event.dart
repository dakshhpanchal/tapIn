part of 'recent_meal_bloc.dart';

abstract class RecentMealEvent extends Equatable {
  const RecentMealEvent();
}

/// Reads recent history from storage, then filters it by [searchString].
/// Fired on open, submit, chip taps and Retry.
class LoadRecentMealEvent extends RecentMealEvent {
  final String searchString;

  /// an empty `searchString` will load all RecentMeal
  const LoadRecentMealEvent({required this.searchString});

  @override
  List<Object?> get props => [];
}

/// Takes a food off Recents. The diary entries are left alone, and a food
/// that is logged again comes back.
class RemoveRecentMealEvent extends RecentMealEvent {
  final MealEntity meal;

  const RemoveRecentMealEvent(this.meal);

  @override
  List<Object?> get props => [meal.code, meal.name];
}

/// Puts a removed food back on Recents (Undo).
class RestoreRecentMealEvent extends RecentMealEvent {
  final MealEntity meal;

  const RestoreRecentMealEvent(this.meal);

  @override
  List<Object?> get props => [meal.code, meal.name];
}

/// Search-as-you-type over recent history, fired on every keystroke.
/// Filters the history already in memory and only reads storage when
/// nothing has been loaded yet.
class RecentMealSearchChangedEvent extends RecentMealEvent {
  final String searchString;

  const RecentMealSearchChangedEvent({required this.searchString});

  @override
  List<Object?> get props => [searchString];
}
