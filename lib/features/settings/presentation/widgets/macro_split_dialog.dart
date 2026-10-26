import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/utils/reload_diary_and_trends.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Rounds three macro percentage shares to integers that sum to exactly 100.
///
/// Uses the largest-remainder method so the result stays as close as possible
/// to the unconstrained ratio. Independent `.round()` is unsafe here: two
/// half-up `.5` remainders produce 101, and `SettingsBloc.setMacroGoals`
/// truncates via `toInt()/100`.
@visibleForTesting
(int carbs, int protein, int fat) roundMacroPercentsToHundred(
  double carbsPct,
  double proteinPct,
  double fatPct,
) {
  const defaultCarbs = 60.0;
  const defaultProtein = 15.0;
  const defaultFat = 25.0;

  final values = [carbsPct, proteinPct, fatPct];
  final total = values.fold<double>(0, (sum, v) => sum + v);
  final scaled = total <= 0
      ? const [defaultCarbs, defaultProtein, defaultFat]
      : [for (final v in values) v * 100.0 / total];

  final floors = [for (final v in scaled) v.floor()];
  final remaining = 100 - floors.reduce((a, b) => a + b);
  final order = List<int>.generate(3, (i) => i)
    ..sort((a, b) {
      final fracCmp = (scaled[b] - floors[b]).compareTo(scaled[a] - floors[a]);
      if (fracCmp != 0) return fracCmp;
      // Prefer the originally larger share; fall back to lower index for a
      // deterministic triple when both remainder and magnitude match.
      final sizeCmp = scaled[b].compareTo(scaled[a]);
      if (sizeCmp != 0) return sizeCmp;
      return a.compareTo(b);
    });
  final result = List<int>.from(floors);
  for (var i = 0; i < remaining; i++) {
    result[order[i]]++;
  }
  return (result[0], result[1], result[2]);
}

/// Distributes the daily kcal goal across carbohydrate, protein and fat.
///
/// Every macro shows its share in % and the grams it works out to at today's
/// kcal goal. Editing one rebalances the others so the trio always adds up to
/// 100%; a locked macro keeps its value while the rest absorb the change.
/// Typed values apply as soon as they are valid, not only on blur.
class MacroSplitDialog extends StatefulWidget {
  final SettingsBloc settingsBloc;
  final HomeBloc homeBloc;

  const MacroSplitDialog({
    super.key,
    required this.settingsBloc,
    required this.homeBloc,
  });

  @override
  State<MacroSplitDialog> createState() => _MacroSplitDialogState();
}

class _MacroSplitDialogState extends State<MacroSplitDialog> {
  static const double _defaultCarbsPct = 60;
  static const double _defaultProteinPct = 15;
  static const double _defaultFatPct = 25;
  static const double _minMacroPct = 5;
  static const double _maxMacroPct = 90;
  static const _kcalPerGram = {
    _MacroField.carbs: 4.0,
    _MacroField.protein: 4.0,
    _MacroField.fat: 9.0,
  };

  static const _presets = <(String, double, double, double)>[
    ('Default', 60, 15, 25),
    ('Balanced', 45, 25, 30),
    ('High protein', 35, 35, 30),
    ('Low carb', 25, 35, 40),
  ];

  final Map<_MacroField, double> _pct = {
    _MacroField.carbs: _defaultCarbsPct,
    _MacroField.protein: _defaultProteinPct,
    _MacroField.fat: _defaultFatPct,
  };
  final Set<_MacroField> _locked = {};
  double _kcalGoal = 0;
  bool _loaded = false;
  bool _syncingControllers = false;

  late final Map<_MacroField, TextEditingController> _controllers;
  late final Map<_MacroField, FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final f in _MacroField.values) f: TextEditingController(),
    };
    _focusNodes = {
      for (final f in _MacroField.values)
        f: FocusNode()..addListener(() => _onFocusChanged(f)),
    };
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// A field that was left mid-edit (empty, out of range) snaps back to the
  /// value on screen once it loses focus.
  void _onFocusChanged(_MacroField field) {
    if (!mounted || _focusNodes[field]!.hasFocus) return;
    _syncControllers();
  }

  Future<void> _load() async {
    final carbs = await widget.settingsBloc.getUserCarbGoalPct();
    final protein = await widget.settingsBloc.getUserProteinGoalPct();
    final fat = await widget.settingsBloc.getUserFatGoalPct();
    // Grams are a nicety; a failed goal lookup just hides them.
    var kcal = 0.0;
    try {
      kcal = await widget.settingsBloc.getCurrentKcalGoal();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pct[_MacroField.carbs] = (carbs ?? _defaultCarbsPct / 100) * 100;
      _pct[_MacroField.protein] = (protein ?? _defaultProteinPct / 100) * 100;
      _pct[_MacroField.fat] = (fat ?? _defaultFatPct / 100) * 100;
      _kcalGoal = kcal;
      _loaded = true;
    });
    _syncControllers();
  }

  /// Rewrites the text fields from [_pct]; [except] is left alone so the
  /// field being typed into doesn't jump under the cursor.
  void _syncControllers({_MacroField? except}) {
    _syncingControllers = true;
    try {
      for (final f in _MacroField.values) {
        if (f == except) continue;
        _controllers[f]!.text = _pct[f]!.round().toString();
      }
    } finally {
      _syncingControllers = false;
    }
  }

  /// Sets [field] to [target] and rebalances the unlocked others so the
  /// total stays 100. Returns false when nothing can move (both others
  /// locked).
  void _setMacro(_MacroField field, double target) {
    final others = [
      for (final f in _MacroField.values)
        if (f != field) f,
    ];
    final free = [
      for (final f in others)
        if (!_locked.contains(f)) f,
    ];
    if (free.isEmpty) return;
    final lockedSum = [
      for (final f in others)
        if (_locked.contains(f)) _pct[f]!,
    ].fold<double>(0, (a, b) => a + b);
    final upper = (100 - lockedSum - _minMacroPct * free.length).clamp(
      _minMacroPct,
      _maxMacroPct,
    );
    final value = target.clamp(_minMacroPct, upper).toDouble();
    final remaining = 100 - lockedSum - value;
    final freeTotal = free.fold<double>(0, (a, f) => a + _pct[f]!);
    setState(() {
      _pct[field] = value;
      for (final f in free) {
        final share = freeTotal <= 0 ? 1 / free.length : _pct[f]! / freeTotal;
        _pct[f] = remaining * share;
      }
      // Enforce the floor on the unlocked others, shaving the rest off the
      // larger one.
      if (free.length == 2) {
        final a = free[0], b = free[1];
        if (_pct[a]! < _minMacroPct) {
          _pct[b] = _pct[b]! - (_minMacroPct - _pct[a]!);
          _pct[a] = _minMacroPct;
        } else if (_pct[b]! < _minMacroPct) {
          _pct[a] = _pct[a]! - (_minMacroPct - _pct[b]!);
          _pct[b] = _minMacroPct;
        }
      }
    });
  }

  void _onTextChanged(_MacroField field, String text) {
    if (_syncingControllers) return;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < _minMacroPct || parsed > _maxMacroPct) {
      return;
    }
    _setMacro(field, parsed.toDouble());
    _syncControllers(except: field);
  }

  void _applyPreset(double carbs, double protein, double fat) {
    setState(() {
      _locked.clear();
      _pct[_MacroField.carbs] = carbs;
      _pct[_MacroField.protein] = protein;
      _pct[_MacroField.fat] = fat;
    });
    _syncControllers();
  }

  void _toggleLock(_MacroField field) {
    setState(() {
      if (_locked.contains(field)) {
        _locked.remove(field);
      } else if (_locked.length < 2) {
        // Locking all three would leave nothing able to move.
        _locked.add(field);
      }
    });
  }

  Future<void> _save() async {
    // Independent `.round()` can sum to 99 or 101, and setMacroGoals stores
    // via toInt()/100 — so balance to an exact 100% integer triple first.
    final rounded = roundMacroPercentsToHundred(
      _pct[_MacroField.carbs]!,
      _pct[_MacroField.protein]!,
      _pct[_MacroField.fat]!,
    );
    await widget.settingsBloc.setMacroGoals(
      rounded.$1.toDouble(),
      rounded.$2.toDouble(),
      rounded.$3.toDouble(),
    );
    widget.settingsBloc.add(LoadSettingsEvent());
    widget.homeBloc.add(const LoadItemsEvent());
    await widget.settingsBloc.updateTrackedDay(
      await widget.settingsBloc.getCurrentLogicalDay(),
    );
    reloadDiaryAndTrends();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _gramsLabel(_MacroField f) {
    if (_kcalGoal <= 0) return '';
    final grams = _kcalGoal * _pct[f]! / 100 / _kcalPerGram[f]!;
    return '≈ ${grams.round()} g';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final total = _pct.values.fold<double>(0, (a, b) => a + b).round();
    final labels = {
      _MacroField.carbs: s.carbsLabel,
      _MacroField.protein: s.proteinLabel,
      _MacroField.fat: s.fatLabel,
    };
    const colors = {
      _MacroField.carbs: Colors.orange,
      _MacroField.protein: Colors.blue,
      _MacroField.fat: Colors.green,
    };
    const ids = {
      _MacroField.carbs: 'macro-split-carbs',
      _MacroField.protein: 'macro-split-protein',
      _MacroField.fat: 'macro-split-fat',
    };
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              s.settingsMacroSplitLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _loaded
                ? () => _applyPreset(
                    _defaultCarbsPct,
                    _defaultProteinPct,
                    _defaultFatPct,
                  )
                : null,
            child: Text(s.buttonResetLabel),
          ),
        ],
      ),
      content: !_loaded
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in _presets)
                        ActionChip(
                          label: Text(p.$1),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _applyPreset(p.$2, p.$3, p.$4),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$total% total'
                    '${_kcalGoal > 0 ? ' · ${_kcalGoal.round()} kcal' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final f in _MacroField.values)
                    _MacroRow(
                      label: labels[f]!,
                      gramsLabel: _gramsLabel(f),
                      value: _pct[f]!,
                      color: colors[f]!,
                      locked: _locked.contains(f),
                      controller: _controllers[f]!,
                      focusNode: _focusNodes[f]!,
                      semanticIdentifier: ids[f]!,
                      onSliderChanged: (v) {
                        _setMacro(f, v);
                        _syncControllers();
                      },
                      onTextChanged: (t) => _onTextChanged(f, t),
                      onLockToggled: () => _toggleLock(f),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.dialogCancelLabel),
        ),
        Semantics(
          identifier: 'macro-split-save',
          child: TextButton(
            onPressed: _loaded ? _save : null,
            child: Text(s.dialogOKLabel),
          ),
        ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final String gramsLabel;
  final double value;
  final Color color;
  final bool locked;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String semanticIdentifier;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onLockToggled;

  const _MacroRow({
    required this.label,
    required this.gramsLabel,
    required this.value,
    required this.color,
    required this.locked,
    required this.controller,
    required this.focusNode,
    required this.semanticIdentifier,
    required this.onSliderChanged,
    required this.onTextChanged,
    required this.onLockToggled,
  });

  @override
  Widget build(BuildContext context) {
    const min = _MacroSplitDialogState._minMacroPct;
    const max = _MacroSplitDialogState._maxMacroPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                gramsLabel.isEmpty ? label : '$label  $gramsLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Lock',
              icon: Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 20,
              ),
              onPressed: onLockToggled,
            ),
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(88),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                onChanged: onTextChanged,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.2),
          ),
          child: Semantics(
            identifier: semanticIdentifier,
            child: Slider(
              min: min,
              max: max,
              value: value.clamp(min, max),
              divisions: (max - min).toInt(),
              onChanged: locked
                  ? null
                  : (v) => onSliderChanged(v.roundToDouble()),
            ),
          ),
        ),
      ],
    );
  }
}

enum _MacroField { carbs, protein, fat }
