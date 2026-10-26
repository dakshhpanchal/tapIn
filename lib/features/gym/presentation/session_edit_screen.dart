import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/editable_exercise.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/reorder_sheet.dart';

/// Corrects a finished workout: its name, date, every set's weight and reps,
/// the machine setting and note, and which sets and exercises it has.
class SessionEditScreen extends StatefulWidget {
  final WorkoutSession session;
  const SessionEditScreen({super.key, required this.session});

  @override
  State<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends State<SessionEditScreen> {
  late final TextEditingController _name;
  late DateTime _startedAt;
  late final Duration _duration;
  late final bool _useLb;
  late final List<EditableExercise> _exercises;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _useLb = context.read<GymCubit>().state.useLb;
    _name = TextEditingController(text: s.name);
    _startedAt = s.startedAt;
    _duration = s.duration;
    _exercises = [
      for (final e in s.exercises)
        EditableExercise.from(e, useLb: _useLb, note: e.note),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    for (final e in _exercises) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (time == null) return;
    setState(
      () => _startedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _reorder() async {
    final order = await showReorderSheet(
      context,
      title: 'Reorder exercises',
      items: [for (final e in _exercises) e.base.name],
    );
    if (order == null) return;
    final moved = [for (final i in order) _exercises[i]];
    setState(() {
      _exercises
        ..clear()
        ..addAll(moved);
    });
  }

  Future<void> _addExercise() async {
    final picked = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (picked == null) return;
    setState(
      () => _exercises.add(
        EditableExercise(WorkoutExercise.of(picked), [EditableSet()], note: ''),
      ),
    );
  }

  /// The workout as edited: sets with no reps are dropped (a set of zero is not
  /// a set), and an exercise left with no sets goes with them.
  WorkoutSession? _build() {
    final exercises = <WorkoutExercise>[];
    for (final e in _exercises) {
      final sets = e.toSets(useLb: _useLb, loggedOnly: true);
      if (sets.isEmpty) continue;
      exercises.add(
        e.base.copyWith(
          sets: sets,
          setting: e.setting.text.trim(),
          note: e.note.text.trim(),
        ),
      );
    }
    if (exercises.isEmpty) return null;
    final name = _name.text.trim();
    return widget.session.copyWith(
      name: name.isEmpty ? widget.session.name : name,
      startedAt: _startedAt,
      endedAt: _startedAt.add(_duration),
      exercises: exercises,
    );
  }

  Future<void> _save() async {
    final updated = _build();
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one set with reps, or delete the workout.',
          ),
        ),
      );
      return;
    }
    final navigator = Navigator.of(context);
    await context.read<GymCubit>().updateSession(updated);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit workout'),
        actions: [
          IconButton(
            tooltip: 'Reorder exercises',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: _exercises.length < 2 ? null : _reorder,
          ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing32,
        ),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Workout name'),
          ),
          const SizedBox(height: Dimens.spacing8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('${dateText(_startedAt)}, ${timeText(_startedAt)}'),
            subtitle: const Text('Tap to change the date and time'),
            onTap: _pickWhen,
          ),
          const SizedBox(height: Dimens.spacing8),
          for (final e in _exercises)
            ExerciseEditCard(
              key: e.key,
              exercise: e,
              useLb: _useLb,
              showReps: true,
              noteLabel: 'Note for next time',
              onRemove: () => setState(() {
                _exercises.remove(e);
                e.dispose();
              }),
              onAddSet: () =>
                  setState(() => e.sets.add(nextSetFor(e, showReps: true))),
              onDeleteSet: (i) => setState(() => e.sets.removeAt(i).dispose()),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exercise'),
            onPressed: _addExercise,
          ),
        ],
      ),
    );
  }
}
