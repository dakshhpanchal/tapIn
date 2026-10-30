import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_profile_usecase.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/l10n/app_locales.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/utils/app_locale_service.dart';
import 'package:opennutritracker/core/utils/app_locale_sync.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/logger_config.dart';
import 'package:opennutritracker/dev/gym_demo.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/main.dart';

/// Dev-only entry point: wipes the active profile and reseeds it with
/// realistic demo data (user, a year of meals and activities, weight/water
/// history, a recipe, fasting sessions), then boots straight past
/// onboarding.
///
/// Run with `flutter run -t lib/dev/main_dev.dart` (or `just dev_seed`)
/// instead of the normal `flutter run` when you want a populated app to
/// test against rather than walking onboarding by hand on every run.
Future<void> main() async {
  if (kReleaseMode) {
    throw UnsupportedError(
      'lib/dev/main_dev.dart seeds demo data and must never be built in release mode',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();
  LoggerConfig.intiLogger();
  await initLocator();

  await seedDemoData(DemoSeedOptions.dev);
  await seedGymDemo();

  final configRepo = locator<ConfigRepository>();
  // This build is for recording the app: no "sample data" banner, and the
  // seeded profile goes by a plain first name.
  await configRepo.setIsDemoData(false);
  final active = locator<GetProfilesUsecase>().getActiveProfile();
  if (active != null) {
    await locator<UpdateProfileUsecase>().updateProfile(
      ProfileEntity(
        id: active.id,
        name: 'Alex',
        createdAt: active.createdAt,
        boxSuffix: active.boxSuffix,
        imagePath: active.imagePath,
      ),
    );
  }
  final config = await configRepo.getConfig();
  // Mirrors the reconciliation in main.dart so a dev build behaves the same
  // way when the OS holds a per-app language.
  final systemLocale = await AppLocaleService.getApplicationLocale();
  final localeCode = await reconcileAppLocale(
    savedLocaleCode: await configRepo.getSelectedLocale(),
    systemLocaleTag: systemLocale.tag,
    systemTagReadFailed: systemLocale.readFailed,
    localeSyncSeeded: await configRepo.getLocaleSyncSeeded(),
    supportedLocales: appLocales(S.supportedLocales),
    persistSelectedLocale: configRepo.setSelectedLocale,
    pushToSystem: AppLocaleService.setApplicationLocale,
    readSystemTag: AppLocaleService.getApplicationLocale,
    markLocaleSyncSeeded: configRepo.setLocaleSyncSeeded,
    clearLocaleSyncSeeded: configRepo.clearLocaleSyncSeeded,
  );
  final savedLocale = localeCode != null ? Locale(localeCode) : null;
  // Light, because that is how the README screenshots are taken.
  await configRepo.setConfigAppTheme(AppThemeEntity.light);
  final savedAppTheme = await configRepo.getConfigAppTheme();

  // Lavender, deep indigo and orange from the launcher icon, on a faintly
  // lavender-tinted canvas.

  runAppWithChangeNotifiers(
    true,
    savedAppTheme,
    savedLocale,
    config.usesKilojoules,
    config.useMaterialYou,
    config.accentColor,
  );
}
