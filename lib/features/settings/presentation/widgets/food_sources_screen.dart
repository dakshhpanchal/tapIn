import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/food_backend.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/off_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/food_region.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_pack.dart';
import 'package:opennutritracker/features/add_meal/data/local_food/local_food_source.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Food databases: the region whose databases are searched first,
/// and which databases the search screens draw from.
///
/// The databases built into the app work offline and are picked by region; the
/// hosted ones (USDA and BLS through the backend) are listed only when this
/// build has a backend to ask. State is persisted on
/// [ConfigEntity.foodSourceToggles]; a source not present in the map defaults
/// to enabled, so users who never visit this screen search every database.
/// Open Food Facts powers the product and barcode search and is shown as a
/// fixed, always-on entry.
class FoodSourcesScreen extends StatefulWidget {
  /// Only for tests; the app's own sources are used otherwise.
  final LocalFoodSource? localFoods;
  final bool? backendConfigured;
  const FoodSourcesScreen({super.key, this.localFoods, this.backendConfigured});

  @override
  State<FoodSourcesScreen> createState() => _FoodSourcesScreenState();
}

class _FoodSourcesScreenState extends State<FoodSourcesScreen> {
  Map<String, bool> _toggles = <String, bool>{};
  List<LocalFoodPackInfo> _packs = const [];
  String? _choice; // saved region, or null for the device's
  bool _loading = true;

  bool get _hasBackend => widget.backendConfigured ?? hasFoodBackend;

  String? get _region => _choice ?? FoodRegion.deviceRegion();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    final source = widget.localFoods ?? locator<LocalFoodSource>();
    final packs = await source.packsFor(FoodRegion.current());
    if (!mounted) return;
    setState(() {
      _toggles = Map<String, bool>.from(config.foodSourceToggles);
      _packs = packs;
      _choice = FoodRegion.savedChoice();
      _loading = false;
    });
  }

  Future<void> _toggle(String sourceCode, bool enabled) async {
    setState(() => _toggles[sourceCode] = enabled);
    await locator<AddConfigUsecase>().setConfigFoodSourceToggles(_toggles);
  }

  Future<void> _chooseRegion() async {
    final s = S.of(context);
    final device = FoodRegion.deviceRegion();
    // '' stands for "follow the device".
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.foodSourcesRegionLabel),
        children: [
          _regionOption(
            ctx,
            '',
            s.foodSourcesRegionAutomatic(
              device == null ? '—' : (FoodRegion.names[device] ?? device),
            ),
          ),
          for (final e in FoodRegion.names.entries)
            _regionOption(ctx, e.key, e.value),
          _regionOption(ctx, 'ZZ', s.foodSourcesRegionOther),
        ],
      ),
    );
    if (picked == null) return;
    await FoodRegion.choose(picked.isEmpty ? null : picked);
    // The order of the databases follows the region.
    final packs = await (widget.localFoods ?? locator<LocalFoodSource>())
        .packsFor(FoodRegion.current());
    if (!mounted) return;
    setState(() {
      _choice = FoodRegion.savedChoice();
      _packs = packs;
    });
  }

  Widget _regionOption(BuildContext ctx, String code, String label) {
    final selected = (_choice ?? '') == code;
    return SimpleDialogOption(
      onPressed: () => Navigator.of(ctx).pop(code),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (selected) const Icon(Icons.check_rounded),
        ],
      ),
    );
  }

  String get _regionLabel {
    final s = S.of(context);
    if (_choice == null) {
      final device = FoodRegion.deviceRegion();
      return s.foodSourcesRegionAutomatic(
        device == null ? '—' : (FoodRegion.names[device] ?? device),
      );
    }
    return _choice == 'ZZ'
        ? s.foodSourcesRegionOther
        : (FoodRegion.names[_choice] ?? _choice!);
  }

  /// Opens the database's public website in the in-app browser (Custom
  /// Tabs / SFSafariViewController) so the user stays inside the app.
  Future<void> _openSourceInfo(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  }

  Widget _infoButton(String url) => IconButton(
    icon: const Icon(Icons.info_outline_rounded),
    onPressed: () => _openSourceInfo(url),
  );

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final region = _region;
    return Scaffold(
      appBar: AppBar(title: Text(s.settingsFoodSourcesLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    s.foodSourcesHelpText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(s.foodSourcesRegionLabel),
                  subtitle: Text(_regionLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chooseRegion,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    s.foodSourcesRegionHelp,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_packs.isNotEmpty) ...[
                  _header(s.foodSourcesBundledTitle),
                  for (final pack in _packs)
                    SwitchListTile(
                      secondary: _infoButton(pack.url),
                      title: Text(pack.name),
                      subtitle: Text(
                        [
                          s.foodSourcesPackSubtitle(pack.count, pack.license),
                          if (!pack.isGlobal && pack.suits(region))
                            s.foodSourcesForYourRegion,
                        ].join(' · '),
                      ),
                      value: _toggles[pack.id] ?? true,
                      onChanged: (value) => _toggle(pack.id, value),
                    ),
                ],
                _header(s.foodSourcesOnlineTitle),
                SwitchListTile(
                  secondary: _infoButton(OFFConst.offWebsiteUrl),
                  title: const Text(OFFConst.offSourceName),
                  subtitle: Text(s.foodSourcesAlwaysEnabledLabel),
                  value: true,
                  onChanged: null,
                ),
                if (_hasBackend)
                  for (final sourceCode
                      in SPConst.settingsSelectableFoodSources)
                    SwitchListTile(
                      secondary: _infoButton(
                        SPConst.foodSourceWebsites[sourceCode]!,
                      ),
                      title: Text(
                        SPConst.foodSourceDisplayNames[sourceCode] ??
                            sourceCode,
                      ),
                      value: _toggles[sourceCode] ?? true,
                      onChanged: (value) => _toggle(sourceCode, value),
                    ),
                if (_packs.isNotEmpty) ...[
                  _header(s.foodSourcesCreditsTitle),
                  for (final pack in _packs)
                    if (_toggles[pack.id] ?? true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          Dimens.spacing8,
                        ),
                        child: Text(
                          pack.attribution,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  const SizedBox(height: Dimens.spacing32),
                ],
              ],
            ),
    );
  }
}
