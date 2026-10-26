import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

/// One set being edited: its text boxes, kept for as long as the screen lives
/// so typing is never interrupted by a rebuild.
class EditableSet {
  final TextEditingController weight;
  final TextEditingController reps;
  final bool warmup;
  final Key key = UniqueKey();

  EditableSet({String weight = '', String reps = '', this.warmup = false})
    : weight = TextEditingController(text: weight),
      reps = TextEditingController(text: reps);

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

/// An exercise being edited, in a workout plan or in a logged workout.
class EditableExercise {
  final WorkoutExercise base;
  final List<EditableSet> sets;
  final TextEditingController setting;

  /// The plan's standing note, or the note for next time, depending on which
  /// screen this is for.
  final TextEditingController note;
  final Key key = UniqueKey();

  EditableExercise(this.base, this.sets, {required String note})
    : setting = TextEditingController(text: base.setting),
      note = TextEditingController(text: note);

  /// [e] as it is now, with its weights shown in the user's unit.
  factory EditableExercise.from(
    WorkoutExercise e, {
    required bool useLb,
    required String note,
  }) => EditableExercise(e, [
    for (final set in e.sets)
      EditableSet(
        weight: set.weightKg == 0
            ? ''
            : weightShown(set.weightKg, plates: e.plates, useLb: useLb),
        reps: set.reps == 0 ? '' : '${set.reps}',
        warmup: set.warmup,
      ),
  ], note: note);

  /// The sets as typed. [loggedOnly] drops sets without reps and marks the rest
  /// done (a logged workout); otherwise every set is kept, because in a plan
  /// the number of sets is the point and reps are logged later.
  List<SetEntry> toSets({required bool useLb, required bool loggedOnly}) {
    final result = <SetEntry>[];
    for (final s in sets) {
      final reps = int.tryParse(s.reps.text.trim()) ?? 0;
      if (loggedOnly && reps <= 0) continue;
      final typed =
          double.tryParse(s.weight.text.trim().replaceAll(',', '.')) ?? 0;
      result.add(
        SetEntry(
          weightKg: weightStored(typed, plates: base.plates, useLb: useLb),
          reps: reps,
          done: loggedOnly,
          warmup: s.warmup,
        ),
      );
    }
    return result;
  }

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
    setting.dispose();
    note.dispose();
  }
}

/// The card for one [EditableExercise]: its sets (weight, and reps when
/// [showReps]), the machine setting and a note. Changes to the list of sets are
/// reported through the callbacks, so the screen owning the list rebuilds.
class ExerciseEditCard extends StatelessWidget {
  final EditableExercise exercise;
  final bool useLb;
  final bool showReps;
  final String noteLabel;
  final VoidCallback onRemove;
  final VoidCallback onAddSet;
  final void Function(int index) onDeleteSet;

  const ExerciseEditCard({
    super.key,
    required this.exercise,
    required this.useLb,
    required this.showReps,
    required this.noteLabel,
    required this.onRemove,
    required this.onAddSet,
    required this.onDeleteSet,
  });

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final text = Theme.of(context).textTheme;
    final unit = unitFor(plates: e.base.plates, useLb: useLb);
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing12),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(e.base.name, style: text.titleMedium)),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing8),
            Row(
              children: [
                const SizedBox(width: 36, child: Text('Set')),
                Expanded(
                  child: Center(
                    child: Text(
                      e.base.kind == ExerciseKind.bodyweight ? '+$unit' : unit,
                    ),
                  ),
                ),
                if (showReps)
                  const Expanded(child: Center(child: Text('Reps'))),
                const SizedBox(width: 40),
              ],
            ),
            for (var s = 0; s < e.sets.length; s++)
              Row(
                key: e.sets[s].key,
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      e.sets[s].warmup ? 'W' : '${_workingNumber(e, s)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: _field(e.sets[s].weight, decimal: true)),
                  if (showReps)
                    Expanded(child: _field(e.sets[s].reps, decimal: false)),
                  IconButton(
                    tooltip: 'Delete set',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => onDeleteSet(s),
                  ),
                ],
              ),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add set'),
              onPressed: onAddSet,
            ),
            const SizedBox(height: Dimens.spacing8),
            TextField(
              controller: e.setting,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Machine setting',
                prefixIcon: Icon(Icons.tune_rounded, size: 20),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            TextField(
              controller: e.note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                labelText: noteLabel,
                prefixIcon: const Icon(Icons.sticky_note_2_outlined, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _workingNumber(EditableExercise e, int index) =>
      e.sets.take(index + 1).where((s) => !s.warmup).length;

  static Widget _field(TextEditingController c, {required bool decimal}) =>
      Padding(
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
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
}

/// A new set for [e] starting from the one above it, the usual next step.
EditableSet nextSetFor(EditableExercise e, {required bool showReps}) =>
    EditableSet(
      weight: e.sets.isEmpty ? '' : e.sets.last.weight.text,
      reps: !showReps || e.sets.isEmpty ? '' : e.sets.last.reps.text,
    );
