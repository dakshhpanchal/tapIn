import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/reorder_sheet.dart';
import 'package:opennutritracker/features/gym/presentation/workout_summary_screen.dart';

/// Logging a workout: exercises, sets with weight and reps, what you did last
/// time, a machine setting and a note for next time, and a clock for how long
/// the workout has run.
/// Every change is saved immediately by [GymCubit].
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Redraws once a second so the elapsed time keeps running.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

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
                      'Started ${timeText(session.startedAt)} · '
                      '${formatClock(session.duration)}',
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
                    if (v == 'reorder') _reorder(context, cubit, session);
                  },
                  itemBuilder: (_) => [
                    if (session.exercises.length > 1)
                      const PopupMenuItem(
                        value: 'reorder',
                        child: Text('Reorder exercises'),
                      ),
                    const PopupMenuItem(
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
                    key: ValueKey(
                      '${session.id}-$i-${session.exercises[i].exerciseId}',
                    ),
                    index: i,
                    exercise: session.exercises[i],
                    previous: lastPerformance(
                      state.sessions,
                      session.exercises[i].exerciseId,
                    ),
                    useLb: state.useLb,
                  ),
                const SizedBox(height: Dimens.spacing8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add exercise'),
                  onPressed: () => _addExercise(context, cubit),
                ),
              ],
            ),
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

  Future<void> _reorder(
    BuildContext context,
    GymCubit cubit,
    WorkoutSession session,
  ) async {
    final order = await showReorderSheet(
      context,
      title: 'Reorder exercises',
      items: [for (final e in session.exercises) e.name],
    );
    if (order != null) await cubit.reorderExercises(order);
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
    // Skipped exercises don't count: they are left out on purpose.
    final active = session.exercises.where((e) => !e.skipped);
    final pending = active.fold<int>(
      0,
      (n, e) => n + e.sets.where((s) => !s.done).length,
    );
    final anyDone = active.any((e) => e.sets.any((s) => s.done));
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

class _ExerciseCard extends StatelessWidget {
  final int index;
  final WorkoutExercise exercise;
  final WorkoutExercise? previous;
  final bool useLb;

  const _ExerciseCard({
    super.key,
    required this.index,
    required this.exercise,
    required this.previous,
    required this.useLb,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final text = Theme.of(context).textTheme;
    final unit = unitFor(plates: exercise.plates, useLb: useLb);
    if (exercise.skipped) {
      // Collapsed while skipped, with a way back.
      return Padding(
        padding: const EdgeInsets.only(bottom: Dimens.spacing12),
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.spacing16,
            vertical: Dimens.spacing8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: text.titleSmall?.copyWith(
                        color: mutedColor(context),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      'Skipped today',
                      style: text.bodySmall?.copyWith(
                        color: mutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => cubit.setExerciseSkipped(index, false),
                child: const Text('Bring back'),
              ),
            ],
          ),
        ),
      );
    }
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
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ExerciseProgressScreen(
                              exerciseId: exercise.exerciseId,
                              name: exercise.name,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                exercise.name,
                                style: text.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.show_chart_rounded,
                              size: 18,
                              color: mutedColor(context),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        exercise.muscle.label,
                        style: text.bodySmall?.copyWith(
                          color: mutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Exercise options',
                  onSelected: (v) => v == 'skip'
                      ? cubit.setExerciseSkipped(index, true)
                      : cubit.removeExercise(index),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'skip', child: Text('Skip today')),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove from workout'),
                    ),
                  ],
                ),
              ],
            ),
            if (previous != null && previous!.note.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Dimens.spacing8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Note from last time: ${previous!.note.trim()}',
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Dimens.spacing12),
            Row(
              children: [
                const SizedBox(width: 36, child: Text('Set')),
                const Expanded(
                  flex: 3,
                  child: Center(child: Text('Last time')),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      exercise.kind == ExerciseKind.bodyweight
                          ? '+$unit'
                          : unit,
                    ),
                  ),
                ),
                const Expanded(flex: 2, child: Center(child: Text('Reps'))),
                const SizedBox(width: 48),
              ],
            ),
            for (var s = 0; s < exercise.sets.length; s++)
              _SetRow(
                key: ValueKey('${exercise.exerciseId}-$s'),
                number: _workingNumber(s),
                previous: _previousFor(s),
                set: exercise.sets[s],
                useLb: useLb,
                plates: exercise.plates,
                onChanged: (next) => cubit.updateSet(index, s, (_) => next),
                onDone: (done) {
                  cubit.updateSet(index, s, (set) => set.copyWith(done: done));
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
            const SizedBox(height: Dimens.spacing8),
            _LineField(
              key: ValueKey('setting-${exercise.exerciseId}-$index'),
              label: 'Machine setting',
              initial: exercise.setting,
              icon: Icons.tune_rounded,
              onChanged: (v) => cubit.setExerciseSetting(index, v),
            ),
            const SizedBox(height: Dimens.spacing8),
            _LineField(
              key: ValueKey('note-${exercise.exerciseId}-$index'),
              label: 'Note for next time',
              initial: exercise.note,
              icon: Icons.sticky_note_2_outlined,
              onChanged: (v) => cubit.setExerciseNote(index, v),
            ),
          ],
        ),
      ),
    );
  }

  /// What the same working set was last time, e.g. "60 kg × 8"; null for
  /// warm-ups and sets beyond what was done before.
  String? _previousFor(int s) {
    final before = previous;
    if (before == null || exercise.sets[s].warmup) return null;
    var n = 0;
    for (var i = 0; i <= s; i++) {
      if (!exercise.sets[i].warmup) n++;
    }
    final done = workingSets(before).toList();
    if (n > done.length) return null;
    final set = done[n - 1];
    return '${weightShown(set.weightKg, plates: exercise.plates, useLb: useLb)} '
        '${unitFor(plates: exercise.plates, useLb: useLb)}'
        ' × ${set.reps}';
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
  final String? previous;
  final SetEntry set;
  final bool useLb;
  final bool plates;
  final ValueChanged<SetEntry> onChanged;
  final ValueChanged<bool> onDone;
  final VoidCallback onToggleWarmup;
  final VoidCallback onDelete;

  const _SetRow({
    super.key,
    required this.number,
    required this.previous,
    required this.set,
    required this.useLb,
    required this.plates,
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

  String _weightText(SetEntry s) => s.weightKg == 0
      ? ''
      : weightShown(s.weightKg, plates: widget.plates, useLb: widget.useLb);
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
        weightKg: weightStored(w, plates: widget.plates, useLb: widget.useLb),
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
          Expanded(
            flex: 3,
            child: Text(
              widget.previous ?? '–',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: mutedColor(context)),
            ),
          ),
          Expanded(flex: 2, child: _field(_weight, decimal: true)),
          Expanded(flex: 2, child: _field(_reps, decimal: false)),
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

/// A one-line text box that saves as you type. Its text is only read when it
/// is built, so edits elsewhere never overwrite what is being typed.
class _LineField extends StatefulWidget {
  final String label;
  final String initial;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _LineField({
    super.key,
    required this.label,
    required this.initial,
    required this.icon,
    required this.onChanged,
  });

  @override
  State<_LineField> createState() => _LineFieldState();
}

class _LineFieldState extends State<_LineField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, size: 20),
      ),
    );
  }
}
