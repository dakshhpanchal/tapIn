import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

/// Pick one of your exercises, or create a new one. There is no built-in
/// list: exercises are whatever you add.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

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
        title: const Text('Add exercise'),
        actions: [
          IconButton(
            tooltip: 'New exercise',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _create(context, cubit),
          ),
        ],
      ),
      body: BlocBuilder<GymCubit, GymState>(
        builder: (context, state) {
          final q = _query.trim().toLowerCase();
          final items = [
            for (final e in state.exercises)
              if ((_muscle == null || e.muscle == _muscle) &&
                  (q.isEmpty || e.name.toLowerCase().contains(q)))
                e,
          ];
          if (state.exercises.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No exercises yet.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Dimens.spacing12),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create exercise'),
                      onPressed: () => _create(context, cubit),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing8,
                  Dimens.spacing16,
                  Dimens.spacing8,
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
                          label: Text('Create "${_query.trim()}"'),
                          onPressed: () =>
                              _create(context, cubit, initialName: _query),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          return ListTile(
                            title: Text(e.name),
                            subtitle: Text(
                              e.plates
                                  ? '${e.muscle.label} · plates'
                                  : e.muscle.label,
                              style: TextStyle(color: mutedColor(context)),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Exercise options',
                              onSelected: (v) => v == 'edit'
                                  ? _edit(context, cubit, e)
                                  : _delete(context, cubit, e),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                            onTap: () => Navigator.of(context).pop(e),
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

  /// Name, muscle group and whether weight is logged in machine plates.
  /// Returns null when cancelled or the name is empty.
  Future<({String name, MuscleGroup muscle, bool plates})?> _askDetails(
    BuildContext context, {
    required String title,
    required String confirm,
    String name = '',
    MuscleGroup? muscle,
    bool plates = false,
  }) async {
    final controller = TextEditingController(text: name.trim());
    var chosenMuscle = muscle ?? _muscle ?? MuscleGroup.chest;
    var usesPlates = plates;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Dimens.spacing12),
              DropdownButtonFormField<MuscleGroup>(
                initialValue: chosenMuscle,
                decoration: const InputDecoration(labelText: 'Muscle group'),
                items: [
                  for (final m in MuscleGroup.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (v) =>
                    setLocal(() => chosenMuscle = v ?? chosenMuscle),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Weight in plates'),
                subtitle: const Text('Machine stack, instead of kg'),
                value: usesPlates,
                onChanged: (v) => setLocal(() => usesPlates = v),
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
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
    final result = controller.text.trim();
    controller.dispose();
    if (confirmed != true || result.isEmpty) return null;
    return (name: result, muscle: chosenMuscle, plates: usesPlates);
  }

  Future<void> _create(
    BuildContext context,
    GymCubit cubit, {
    String initialName = '',
  }) async {
    final details = await _askDetails(
      context,
      title: 'New exercise',
      confirm: 'Create',
      name: initialName,
    );
    if (details == null) return;
    final exercise = await cubit.createExercise(
      details.name,
      muscle: details.muscle,
      plates: details.plates,
    );
    if (context.mounted) Navigator.of(context).pop(exercise);
  }

  Future<void> _edit(BuildContext context, GymCubit cubit, Exercise e) async {
    final details = await _askDetails(
      context,
      title: 'Edit exercise',
      confirm: 'Save',
      name: e.name,
      muscle: e.muscle,
      plates: e.plates,
    );
    if (details == null) return;
    await cubit.updateExercise(
      e,
      name: details.name,
      muscle: details.muscle,
      plates: details.plates,
    );
  }

  Future<void> _delete(BuildContext context, GymCubit cubit, Exercise e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${e.name}"?'),
        content: const Text(
          'It is removed from this list. Workouts you already logged keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.deleteExercise(e.id);
  }
}
