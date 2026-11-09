import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// Remembers which look the exercise progress chart uses, by its name. Kept in
/// the same encrypted box as the other small gym flags, under its own key.
class ProgressStylePrefs {
  static const _key = 'gym_progress_style';

  static String? read() {
    try {
      return locator<HiveDBProvider>().gymMetaBox.get(_key);
    } catch (_) {
      // Storage not ready (or not set up): start on the default look.
      return null;
    }
  }

  static Future<void> save(String name) async {
    try {
      await locator<HiveDBProvider>().gymMetaBox.put(_key, name);
    } catch (_) {
      // Not remembering is harmless; the choice still holds for this visit.
    }
  }
}
