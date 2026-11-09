import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// Remembers the sort and group choices on the gym lists, so each list opens
/// the way it was left. Kept in the same encrypted box as the other small gym
/// flags, one key per list.
class ListPrefs {
  /// The saved choice for [key], or [fallback] when nothing is saved, the
  /// saved name no longer exists, or storage is not ready.
  static T restore<T extends Enum>(List<T> values, String key, T fallback) {
    try {
      final name = locator<HiveDBProvider>().gymMetaBox.get(key);
      return values.firstWhere((v) => v.name == name, orElse: () => fallback);
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> remember(String key, Enum value) async {
    try {
      await locator<HiveDBProvider>().gymMetaBox.put(key, value.name);
    } catch (_) {
      // Not remembering is harmless; the choice still holds for this visit.
    }
  }
}
