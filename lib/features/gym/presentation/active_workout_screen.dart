import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/workout_summary_screen.dart';

/// Logging a workout: exercises, sets with weight and reps, a rest timer.
/// Every change is saved immediately by [GymCubit].
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  static const _defaultRest = 90;

  Timer? _ticker;
  int _restRemaining = 0;
  int _restTotal = _defaultRest;

  @override
  void initState() {
    super.initState();
    // One tick a second drives both the elapsed clock and the rest countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_restRemaining > 0) {
          _restRemaining--;
          if (_restRemaining == 0) HapticFeedback.heavyImpact();
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startRest() => setState(() {
    _restTotal = _defaultRest;
    _restRemaining = _defaultRest;
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    return BlocConsumer<GymCubit, GymState>(
      // The workout can end from elsewhere (finish, discard): leave then.
      listenWhen: (a, b) => a.active != null && b.active == null,
      listener: (context, state) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
      builder: (context, state) {
        final session = state.active;
        if (session == null) return const Scaffold();
        return PopScope(
          // Leaving keeps the workout; the gym tab offers "Resume".
          canPop: true,
          child: Scaffold(
            appBar: AppBar(
              title: GestureDetector(
                onTap: () => _rename(context, cubit, session),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.name, overflow: TextOverflow.ellipsis),
                    Text(
                      formatClock(session.duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: mutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'discard') _discard(context, cubit);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'discard',
                      child: Text('Discard workout'),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _finish(context, cubit, session),
                  child: const Text('Finish'),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                120,
              ),
              children: [
                for (var i = 0; i < session.exercises.length; i++)
                  _ExerciseCard(
                    key: ValueKey('${session.id}-$i-${session.exercises[i].exerciseId}'),
                    index: i,
                    exercise: session.exercises[i],
                    previous: lastPerformance(
                      state.sessions,
                      session.exercises[i].exerciseId,
                    ),
                    useLb: state.useLb,
                    onSetDone: _startRest,
                  ),
                const SizedBox(height: Dimens.spacing8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add exercise'),
                  onPressed: () => _addExercise(context, cubit),
                ),
              ],
            ),
            bottomSheet: _restRemaining > 0
                ? _RestBar(
                    remaining: _restRemaining,
                    total: _restTotal,
                    onAdjust: (delta) => setState(() {
                      _restRemaining = (_restRemaining + delta).clamp(0, 600);
                      if (delta > 0 && _restRemaining > _restTotal) {
                        _restTotal = _restRemaining;
                      }
                    }),
                    onSkip: () => setState(() => _restRemaining = 0),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _addExercise(BuildContext context, GymCubit cubit) async {
    final picked = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (picked != null) await cubit.addExercise(picked);
  }

  Future<void> _rename(
    BuildContext context,
    GymCubit cubit,
    WorkoutSession session,
  ) async {
    final controller = TextEditingController(text: session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) await cubit.renameWorkout(name);
  }

  Future<void> _discard(BuildContext context, GymCubit cubit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('Everything logged in this workout is deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.discardWorkout();
  }

  Future<void> _finish(
    BuildContext context,
    GymCubit cubit,
    WorkoutSession session,
  ) async {
    final pending = session.exercises.fold<int>(
      0,
      (n, e) => n + e.sets.where((s) => !s.done).length,
    );
    final anyDone = session.exercises.any((e) => e.sets.any((s) => s.done));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(anyDone ? 'Finish workout?' : 'Nothing logged'),
        content: Text(
          !anyDone
              ? 'No set is marked done, so finishing discards this workout.'
              : pending > 0
              ? '$pending unfinished ${pending == 1 ? 'set is' : 'sets are'} '
                    'left out of the workout.'
              : 'Save this workout to your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(anyDone ? 'Finish' : 'Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    final result = await cubit.finishWorkout();
    if (result != null) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutSummaryScreen(finished: result),
        ),
      );
    }
  }
}

class _RestBar extends StatelessWidget {
  final int remaining;
  final int total;
  final void Function(int delta) onAdjust;
  final VoidCallback onSkip;

  const _RestBar({
    required this.remaining,
    required this.total,
    required this.onAdjust,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.spacing16,
            vertical: Dimens.spacing8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rest ${formatClock(Duration(seconds: remaining))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => onAdjust(-15),
                    child: const Text('−15'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => onAdjust(15),
                    child: const Text('+15'),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Skip rest',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: onSkip,
                  ),
                ],
              ),
              LinearProgressIndicator(
                value: total == 0 ? 0 : remaining / total,
                minHeight: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final int index;
  final WorkoutExercise exercise;
  final WorkoutExercise? previous;
  final bool useLb;
  final VoidCallback onSetDone;

  const _ExerciseCard({
    super.key,
    required this.index,
    required this.exercise,
    required this.previous,
    required this.useLb,
    required this.onSetDone,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final text = Theme.of(context).textTheme;
    final unit = weightUnitLabel(useLb);
    final last = previous == null
        ? null
        : workingSets(previous!)
              .map((s) => '${weightText(s.weightKg, useLb)}×${s.reps}')
              .join('  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing12),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name, style: text.titleMedium),
                      Text(
                        exercise.muscle.label,
                        style: text.bodySmall?.copyWith(
                          color: mutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => cubit.removeExercise(index),
                ),
              ],
            ),
            if (last != null && last.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing4),
                child: Text(
                  'Last time: $last',
                  style: text.bodySmall?.copyWith(color: mutedColor(context)),
                ),
              ),
            const SizedBox(height: Dimens.spacing12),
            Row(
              children: [
                const SizedBox(width: 36, child: Text('Set')),
                Expanded(
                  child: Center(
                    child: Text(
                      exercise.kind == ExerciseKind.bodyweight
                          ? '+$unit'
                          : unit,
                    ),
                  ),
                ),
                const Expanded(child: Center(child: Text('Reps'))),
                const SizedBox(width: 48),
              ],
            ),
            for (var s = 0; s < exercise.sets.length; s++)
              _SetRow(
                key: ValueKey('${exercise.exerciseId}-$s'),
                number: _workingNumber(s),
                set: exercise.sets[s],
                useLb: useLb,
                onChanged: (next) => cubit.updateSet(index, s, (_) => next),
                onDone: (done) {
                  cubit.updateSet(
                    index,
                    s,
                    (set) => set.copyWith(done: done),
                  );
                  if (done) onSetDone();
                },
                onToggleWarmup: () => cubit.updateSet(
                  index,
                  s,
                  (set) => set.copyWith(warmup: !set.warmup),
                ),
                onDelete: () => cubit.removeSet(index, s),
              ),
            const SizedBox(height: Dimens.spacing4),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add set'),
              onPressed: () => cubit.addSet(index),
            ),
          ],
        ),
      ),
    );
  }

  /// Working sets are numbered 1, 2, 3...; warm-ups show "W".
  String _workingNumber(int s) {
    if (exercise.sets[s].warmup) return 'W';
    var n = 0;
    for (var i = 0; i <= s; i++) {
      if (!exercise.sets[i].warmup) n++;
    }
    return '$n';
  }
}

class _SetRow extends StatefulWidget {
  final String number;
  final SetEntry set;
  final bool useLb;
  final ValueChanged<SetEntry> onChanged;
  final ValueChanged<bool> onDone;
  final VoidCallback onToggleWarmup;
  final VoidCallback onDelete;

  const _SetRow({
    super.key,
    required this.number,
    required this.set,
    required this.useLb,
    required this.onChanged,
    required this.onDone,
    required this.onToggleWarmup,
    required this.onDelete,
  });

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(text: _weightText(widget.set));
    _reps = TextEditingController(text: _repsText(widget.set));
  }

  String _weightText(SetEntry s) =>
      s.weightKg == 0 ? '' : weightText(s.weightKg, widget.useLb);
  String _repsText(SetEntry s) => s.reps == 0 ? '' : '${s.reps}';

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    // Sets shift when one above is deleted; follow the values unless the user
    // is typing in the field right now.
    final weight = _weightText(widget.set);
    if (double.tryParse(_weight.text.replaceAll(',', '.')) !=
            double.tryParse(weight) &&
        _weight.text != weight) {
      _weight.text = weight;
    }
    final reps = _repsText(widget.set);
    if (int.tryParse(_reps.text) != int.tryParse(reps) && _reps.text != reps) {
      _reps.text = reps;
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _emit() {
    final w = double.tryParse(_weight.text.replaceAll(',', '.')) ?? 0;
    final r = int.tryParse(_reps.text) ?? 0;
    widget.onChanged(
      widget.set.copyWith(
        weightKg: fromDisplayWeight(w, widget.useLb),
        reps: r,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = widget.set.done;
    return Container(
      color: done ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: PopupMenuButton<String>(
              tooltip: 'Set options',
              padding: EdgeInsets.zero,
              onSelected: (v) =>
                  v == 'delete' ? widget.onDelete() : widget.onToggleWarmup(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'warmup',
                  child: Text(
                    widget.set.warmup ? 'Make working set' : 'Mark as warm-up',
                  ),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete set')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  widget.number,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.set.warmup ? scheme.tertiary : null,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _field(_weight, decimal: true)),
          Expanded(child: _field(_reps, decimal: false)),
          SizedBox(
            width: 48,
            child: Checkbox(
              value: done,
              onChanged: (v) => widget.onDone(v ?? false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, {required bool decimal}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: TextField(
      controller: c,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
      ],
      onChanged: (_) => _emit(),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 10),
      ),
    ),
  );
}
