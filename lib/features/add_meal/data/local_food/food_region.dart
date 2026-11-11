import 'dart:ui';

import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';

/// The country whose food databases come first in search. By default it is the
/// device's region; the user can pick another in Settings → Food databases,
/// for example when travelling or when the phone is set to another country.
class FoodRegion {
  static const _key = 'food_region';

  /// The saved choice: an ISO country code, or null for "follow the device".
  static String? savedChoice() {
    try {
      final v = locator<HiveDBProvider>().gymMetaBox.get(_key);
      return (v == null || v.isEmpty) ? null : v.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  static Future<void> choose(String? code) async {
    try {
      final box = locator<HiveDBProvider>().gymMetaBox;
      if (code == null) {
        await box.delete(_key);
      } else {
        await box.put(_key, code.toUpperCase());
      }
    } catch (_) {
      // Not remembering is harmless; the choice still holds for this visit.
    }
  }

  /// The device's country, or null when the phone does not say.
  ///
  /// Reads the phone's whole language list and takes the first entry that names
  /// a country: the app's own language can be plain "English" (no country)
  /// while the phone is set to "English (India)", and it is the phone that says
  /// where the user is.
  static String? deviceRegion([List<Locale>? locales]) {
    for (final l in locales ?? PlatformDispatcher.instance.locales) {
      final code = l.countryCode;
      if (code != null && code.isNotEmpty) return code.toUpperCase();
    }
    return null;
  }

  /// The region in use: the user's choice, else the device's.
  static String? current() => savedChoice() ?? deviceRegion();

  /// Country names for the regions packs exist for, so Settings can list them
  /// without a localisation table. Only the countries with a pack of their own
  /// are named here; everyone else gets the global databases.
  static const names = <String, String>{
    'IN': 'India',
    'US': 'United States',
    'GB': 'United Kingdom',
    'IE': 'Ireland',
    'AU': 'Australia',
    'NZ': 'New Zealand',
    'CA': 'Canada',
  };
}
