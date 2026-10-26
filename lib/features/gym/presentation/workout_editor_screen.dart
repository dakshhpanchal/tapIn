import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/editable_exercise.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/reorder_sheet.dart';

/// Plan a workout: a name and its exercises, each with its sets, the weight
/// planned for every set, the machine setting and a note. Reps are logged later,
/// when the workout is done.
class WorkoutEditorScreen extends StatefulWidget {
  final Routine? existing;
  const WorkoutEditorScreen({super.key, this.existing});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final TextEditingController _name;
  late final bool _useLb;
  late List<EditableExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _useLb = context.read<GymCubit>().state.useLb;
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _exercises = [
      for (final e in widget.existing?.exercises ?? const <WorkoutExercise>[])
        EditableExercise.from(e, useLb: _useLb, note: e.planNote),
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

  bool get _canSave => _name.text.trim().isNotEmpty && _exercises.isNotEmpty;

  Future<void> _add() async {
    final picked = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (picked == null) return;
    setState(
      () => _exercises.add(
        EditableExercise(WorkoutExercise.of(picked), [
          EditableSet(),
          EditableSet(),
          EditableSet(),
        ], note: ''),
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
    setState(() => _exercises = [for (final i in order) _exercises[i]]);
  }

  Future<void> _save() async {
    final exercises = [
      for (final e in _exercises)
        e.base.copyWith(
          sets: e.toSets(useLb: _useLb, loggedOnly: false),
          setting: e.setting.text.trim(),
          planNote: e.note.text.trim(),
        ),
    ];
    final navigator = Navigator.of(context);
    await context.read<GymCubit>().saveRoutine(
      id: widget.existing?.id,
      name: _name.text.trim(),
      exercises: exercises,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New workout' : 'Edit workout'),
        actions: [
          IconButton(
            tooltip: 'Reorder exercises',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: _exercises.length < 2 ? null : _reorder,
          ),
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing16,
          Dimens.spacing16,
          Dimens.spacing32,
        ),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Workout name',
              hintText: 'Push day',
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
          for (final e in _exercises)
            ExerciseEditCard(
              key: e.key,
              exercise: e,
              useLb: _useLb,
              showReps: false,
              noteLabel: 'Note (shown during the workout)',
              onRemove: () => setState(() {
                _exercises.remove(e);
                e.dispose();
              }),
              onAddSet: () =>
                  setState(() => e.sets.add(nextSetFor(e, showReps: false))),
              onDeleteSet: (i) => setState(() => e.sets.removeAt(i).dispose()),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exercise'),
            onPressed: _add,
          ),
        ],
      ),
    );
  }
}
