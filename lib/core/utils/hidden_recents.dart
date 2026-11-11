import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// Foods taken off the Recents list on purpose, for example a Quick add typed
/// once. Recents is built from what has been logged, so hiding never touches
/// the diary: it only remembers, per food, when it was hidden. A food that is
/// logged again after that comes back by itself.
class HiddenRecents {
  static const _key = 'hidden_recents';

  final Box<String> _box;
  HiddenRecents(this._box);

  /// The key Recents already groups a food by.
  static String keyOf(MealEntity meal) => meal.code ?? meal.name ?? '';

  Map<String, int> _read() {
    final raw = _box.get(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in decoded.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      // Unreadable: treat as nothing hidden rather than hiding by mistake.
      return {};
    }
  }

  Future<void> _write(Map<String, int> value) async {
    await _box.put(_key, jsonEncode(value));
  }

  /// Takes [meal] off Recents as of [at] (now by default).
  Future<void> hide(MealEntity meal, {DateTime? at}) async {
    final all = _read();
    all[keyOf(meal)] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await _write(all);
  }

  /// Puts [meal] back on Recents.
  Future<void> show(MealEntity meal) async {
    final all = _read();
    if (all.remove(keyOf(meal)) != null) await _write(all);
  }

  /// Whether a food whose latest log was at [lastLogged] stays off Recents.
  /// Logging it again after it was hidden brings it back.
  bool isHidden(MealEntity meal, DateTime lastLogged) {
    final hiddenAt = _read()[keyOf(meal)];
    if (hiddenAt == null) return false;
    return lastLogged.millisecondsSinceEpoch <= hiddenAt;
  }
}
