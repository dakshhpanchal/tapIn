import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/session_edit_screen.dart';

/// A finished workout: totals and every set, with options to repeat it, save
/// it as a routine, or delete it.
class SessionDetailScreen extends StatelessWidget {
  /// The workout as it was when opened; the latest saved version is shown
  /// instead once it is found, so an edit shows up here straight away.
  final WorkoutSession session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GymCubit, GymState>(
      builder: (context, state) => _SessionDetail(
        session:
            state.sessions.where((s) => s.id == session.id).firstOrNull ??
            session,
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  final WorkoutSession session;
  const _SessionDetail({required this.session});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final useLb = cubit.state.useLb;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
          IconButton(
            tooltip: 'Edit workout',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'routine':
                  await _saveRoutine(context, cubit);
                case 'delete':
                  await _delete(context, cubit);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'routine', child: Text('Save as routine')),
              PopupMenuItem(value: 'delete', child: Text('Delete workout')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateText(session.startedAt),
                  style: text.bodyMedium?.copyWith(color: mutedColor(context)),
                ),
                const SizedBox(height: Dimens.spacing12),
                Wrap(
                  spacing: Dimens.spacing24,
                  runSpacing: Dimens.spacing12,
                  children: [
                    _stat(context, 'Time', formatDuration(session.duration)),
                    if (sessionVolume(session) > 0)
                      _stat(
                        context,
                        'Volume',
                        volumeText(sessionVolume(session), useLb),
                      ),
                    _stat(context, 'Sets', '${sessionSetCount(session)}'),
                  ],
                ),
              ],
            ),
          ),
          for (final e in session.exercises) ...[
            const SizedBox(height: Dimens.spacing12),
            AppCard(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExerciseProgressScreen(
                          exerciseId: e.exerciseId,
                          name: e.name,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.name, style: text.titleMedium)),
                        Icon(
                          Icons.show_chart_rounded,
                          size: 18,
                          color: mutedColor(context),
                        ),
                      ],
                    ),
                  ),
                  if (e.setting.trim().isNotEmpty)
                    Text(
                      'Setting: ${e.setting.trim()}',
                      style: text.bodySmall?.copyWith(
                        color: mutedColor(context),
                      ),
                    ),
                  if (e.note.trim().isNotEmpty)
                    Text(
                      'Note: ${e.note.trim()}',
                      style: text.bodySmall?.copyWith(
                        color: mutedColor(context),
                      ),
                    ),
                  const SizedBox(height: Dimens.spacing8),
                  for (var i = 0; i < e.sets.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              e.sets[i].warmup ? 'W' : '${_number(e, i)}',
                              style: text.bodyMedium?.copyWith(
                                color: mutedColor(context),
                              ),
                            ),
                          ),
                          Text(
                            '${weightShown(e.sets[i].weightKg, plates: e.plates, useLb: useLb)} '
                            '${unitFor(plates: e.plates, useLb: useLb)}'
                            ' × ${e.sets[i].reps}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Dimens.spacing24),
          FilledButton.icon(
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Repeat workout'),
            onPressed: () => _repeat(context, cubit),
          ),
        ],
      ),
    );
  }

  int _number(WorkoutExercise e, int index) =>
      e.sets.take(index + 1).where((s) => !s.warmup).length;

  Widget _stat(BuildContext context, String label, String value) => SizedBox(
    width: 110,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: mutedColor(context)),
        ),
      ],
    ),
  );

  Future<void> _repeat(BuildContext context, GymCubit cubit) async {
    if (cubit.state.active != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish your current workout first.')),
      );
      return;
    }
    await cubit.startFromRoutine(
      Routine(id: session.id, name: session.name, exercises: session.exercises),
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _saveRoutine(BuildContext context, GymCubit cubit) async {
    final controller = TextEditingController(text: session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as routine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Routine name'),
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
    if (name == null || name.isEmpty) return;
    await cubit.saveAsRoutine(session, name);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved "$name".')));
    }
  }

  void _edit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionEditScreen(session: session),
      ),
    );
  }

  Future<void> _delete(BuildContext context, GymCubit cubit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text('This removes it from your history and records.'),
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
    if (ok != true) return;
    await cubit.deleteSession(session.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}
