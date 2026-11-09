import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// Remembers the range chip picked on Trends (7, 30, 90, 365 days, or 0 for
/// All), so the tab opens on it next time. Kept in the same encrypted box as
/// the other small gym/app flags, under its own key.
class TrendsRangePrefs {
  static const _key = 'trends_range_days';
  static const defaultDays = 7;
  static const allowed = {0, 7, 30, 90, 365};

  static int read() {
    try {
      final raw = locator<HiveDBProvider>().gymMetaBox.get(_key);
      final days = int.tryParse(raw ?? '');
      return days != null && allowed.contains(days) ? days : defaultDays;
    } catch (_) {
      // Storage not ready (or not set up): start on the default.
      return defaultDays;
    }
  }

  static Future<void> save(int days) async {
    try {
      await locator<HiveDBProvider>().gymMetaBox.put(_key, '$days');
    } catch (_) {
      // Not remembering is harmless; the chip still works for this visit.
    }
  }
}
