import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/reorder_sheet.dart';

/// Plan a workout: a name, its exercises, and how many sets of each. The reps
/// and weights are logged later, when the workout is done.
class WorkoutEditorScreen extends StatefulWidget {
  final Routine? existing;
  const WorkoutEditorScreen({super.key, this.existing});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final TextEditingController _name;
  late List<WorkoutExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _exercises = [...?widget.existing?.exercises];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && _exercises.isNotEmpty;

  void _setCount(int index, int count) {
    final e = _exercises[index];
    final sets = [...e.sets];
    while (sets.length < count) {
      // A new set starts from the one above it, the usual next step.
      sets.add(
        sets.isEmpty
            ? const SetEntry()
            : SetEntry(weightKg: sets.last.weightKg, reps: sets.last.reps),
      );
    }
    if (sets.length > count) sets.removeRange(count, sets.length);
    setState(() => _exercises[index] = e.copyWith(sets: sets));
  }

  Future<void> _add() async {
    final picked = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (picked == null) return;
    setState(
      () => _exercises.add(
        WorkoutExercise.of(
          picked,
          sets: const [SetEntry(), SetEntry(), SetEntry()],
        ),
      ),
    );
  }

  Future<void> _reorder() async {
    final order = await showReorderSheet(
      context,
      title: 'Reorder exercises',
      items: [for (final e in _exercises) e.name],
    );
    if (order == null) return;
    setState(() => _exercises = [for (final i in order) _exercises[i]]);
  }

  Future<void> _save() async {
    await context.read<GymCubit>().saveRoutine(
      id: widget.existing?.id,
      name: _name.text.trim(),
      exercises: _exercises,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
        padding: const EdgeInsets.all(Dimens.spacing16),
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
          for (var i = 0; i < _exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Dimens.spacing8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing16,
                  vertical: Dimens.spacing8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_exercises[i].name, style: text.titleSmall),
                    ),
                    IconButton(
                      tooltip: 'Fewer sets',
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: _exercises[i].sets.length > 1
                          ? () => _setCount(i, _exercises[i].sets.length - 1)
                          : null,
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${_exercises[i].sets.length} sets',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'More sets',
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () =>
                          _setCount(i, _exercises[i].sets.length + 1),
                    ),
                    IconButton(
                      tooltip: 'Remove exercise',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: mutedColor(context),
                      ),
                      onPressed: () => setState(() => _exercises.removeAt(i)),
                    ),
                  ],
                ),
              ),
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
