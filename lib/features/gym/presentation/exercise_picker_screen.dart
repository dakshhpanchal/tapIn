import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

/// Search and pick an exercise. In [browse] mode, tapping a row opens that
/// exercise's progress instead of returning it.
class ExercisePickerScreen extends StatefulWidget {
  final bool browse;
  const ExercisePickerScreen({super.key, this.browse = false});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  String _query = '';
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.browse ? 'Exercises' : 'Add exercise'),
        actions: [
          IconButton(
            tooltip: 'New exercise',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _createExercise(context, cubit),
          ),
        ],
      ),
      body: BlocBuilder<GymCubit, GymState>(
        builder: (context, state) {
          final q = _query.trim().toLowerCase();
          final items = state.exercises.where((e) {
            return (_muscle == null || e.muscle == _muscle) &&
                (q.isEmpty || e.name.toLowerCase().contains(q));
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing8,
                  Dimens.spacing16,
                  Dimens.spacing4,
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search exercises',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing12,
                  ),
                  children: [
                    _chip('All', _muscle == null, () {
                      setState(() => _muscle = null);
                    }),
                    for (final m in MuscleGroup.values)
                      _chip(m.label, _muscle == m, () {
                        setState(() => _muscle = _muscle == m ? null : m);
                      }),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            q.isEmpty ? 'Create exercise' : 'Create "$_query"',
                          ),
                          onPressed: () => _createExercise(
                            context,
                            cubit,
                            initialName: _query.trim(),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          return ListTile(
                            title: Text(e.name),
                            subtitle: Text(
                              [
                                e.muscle.label,
                                if (e.equipment.isNotEmpty) e.equipment,
                                if (e.isCustom) 'Custom',
                              ].join(' · '),
                              style: TextStyle(color: mutedColor(context)),
                            ),
                            trailing: widget.browse
                                ? const Icon(Icons.chevron_right_rounded)
                                : null,
                            onTap: () => widget.browse
                                ? Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ExerciseProgressScreen(exercise: e),
                                    ),
                                  )
                                : Navigator.of(context).pop(e),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    ),
  );

  Future<void> _createExercise(
    BuildContext context,
    GymCubit cubit, {
    String initialName = '',
  }) async {
    final nameController = TextEditingController(text: initialName);
    var muscle = _muscle ?? MuscleGroup.chest;
    var kind = ExerciseKind.weighted;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New exercise'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Dimens.spacing12),
              DropdownButtonFormField<MuscleGroup>(
                initialValue: muscle,
                decoration: const InputDecoration(labelText: 'Muscle group'),
                items: [
                  for (final m in MuscleGroup.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (v) => setLocal(() => muscle = v ?? muscle),
              ),
              const SizedBox(height: Dimens.spacing12),
              SegmentedButton<ExerciseKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ExerciseKind.weighted,
                    label: Text('Weight × reps'),
                  ),
                  ButtonSegment(
                    value: ExerciseKind.bodyweight,
                    label: Text('Bodyweight'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setLocal(() => kind = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (created != true || name.isEmpty) return;
    final exercise = await cubit.createExercise(
      name: name,
      muscle: muscle,
      kind: kind,
    );
    if (!context.mounted) return;
    if (!widget.browse) Navigator.of(context).pop(exercise);
  }
}
