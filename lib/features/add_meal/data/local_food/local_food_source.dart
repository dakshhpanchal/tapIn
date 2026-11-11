import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_pack.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// The food databases that ship inside the app (assets/food_packs). They are
/// read from the app bundle, so they work offline and need no server. Which
/// ones are searched, and in what order, depends on the user's region.
class LocalFoodSource {
  static const manifestPath = 'assets/food_packs/manifest.json';
  static final _log = Logger('LocalFoodSource');

  final AssetBundle _bundle;
  LocalFoodSource({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  Future<List<LocalFoodPackInfo>>? _infos;
  final Map<String, Future<LocalFoodPack?>> _packs = {};

  /// Every pack the app carries, from its small manifest.
  Future<List<LocalFoodPackInfo>> packs() => _infos ??= _readManifest();

  Future<List<LocalFoodPackInfo>> _readManifest() async {
    try {
      final raw = await _bundle.loadString(manifestPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return [
        for (final p in json['packs'] as List)
          LocalFoodPackInfo.fromJson(p as Map<String, dynamic>),
      ];
    } catch (e) {
      _log.warning('No food pack manifest: $e');
      return const [];
    }
  }

  Future<LocalFoodPack?> _load(LocalFoodPackInfo info) => _packs.putIfAbsent(
    info.id,
    () async {
      try {
        final raw = await _bundle.loadString('assets/food_packs/${info.file}');
        // Parsed off the UI thread: the biggest pack is a couple of MB.
        final json = await compute(_decode, raw);
        return LocalFoodPack.fromJson(info, json);
      } catch (e, st) {
        _log.warning('Could not read food pack ${info.id}', e, st);
        return null;
      }
    },
  );

  static Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  /// The packs to search, best first: those made for [region], then the global
  /// ones, with [enabled] deciding which are left out.
  Future<List<LocalFoodPackInfo>> packsFor(
    String? region, {
    bool Function(String packId)? enabled,
  }) async {
    final all = await packs();
    final suitable = [
      for (final p in all)
        if (p.suits(region) && (enabled?.call(p.id) ?? true)) p,
    ];
    // Region-specific first; within each group the manifest's order.
    return [
      ...suitable.where((p) => !p.isGlobal),
      ...suitable.where((p) => p.isGlobal),
    ];
  }

  /// Foods matching [query] in the packs for [region], at most [limit].
  Future<List<MealEntity>> search(
    String query, {
    String? region,
    bool Function(String packId)? enabled,
    int limit = 20,
  }) async {
    final whole = query.trim().toLowerCase();
    if (whole.isEmpty) return const [];
    final words = whole.split(RegExp(r'\s+'));
    final infos = await packsFor(region, enabled: enabled);

    // (score, pack order, index): better score first, then the region's own
    // packs ahead of the global ones.
    final found = <({double score, int pack, int index, LocalFoodPack from})>[];
    for (var order = 0; order < infos.length; order++) {
      final pack = await _load(infos[order]);
      if (pack == null) continue;
      for (var i = 0; i < pack.length; i++) {
        final s = pack.score(i, words, whole);
        if (s != null) {
          // Recipes rank a little below ingredients of the same name, and a
          // database made for the user's own region a little above the
          // worldwide ones: its fruit and vegetables are the local ones.
          final score =
              s +
              (pack.info.isDishes ? 1.5 : 0) -
              (pack.info.isGlobal ? 0 : 1.0);
          found.add((score: score, pack: order, index: i, from: pack));
        }
      }
    }
    found.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      return a.pack.compareTo(b.pack);
    });
    return [for (final f in found.take(limit)) f.from.toMeal(f.index)];
  }
}
