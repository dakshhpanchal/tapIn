import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/utils/env.dart';

/// Whether this build was given a food-database backend to search.
///
/// The public source builds ship placeholder values for it, and the food
/// database is then unreachable: showing a "Food" source there only produces a
/// permanent "a source is down" notice, so the UI leaves it out. Open Food
/// Facts and the user's own foods are unaffected.
/// Tests that exercise the Food source set this, since the checked-in build
/// has no backend.
@visibleForTesting
bool? foodBackendOverride;

bool get hasFoodBackend {
  if (foodBackendOverride != null) return foodBackendOverride!;
  final host = Uri.tryParse(Env.supabaseProjectUrl)?.host ?? '';
  return host.isNotEmpty && !host.endsWith('.invalid');
}
