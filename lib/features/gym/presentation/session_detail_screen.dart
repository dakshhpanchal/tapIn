import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

/// A finished workout: totals and every set, with options to repeat it, save
/// it as a routine, or delete it.
class SessionDetailScreen extends StatelessWidget {
  final WorkoutSession session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final useLb = cubit.state.useLb;
    final text = Theme.of(context).textTheme;
    final unit = weightUnitLabel(useLb);
    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
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
                  Text(e.name, style: text.titleMedium),
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
                            '${weightText(e.sets[i].weightKg, useLb)} $unit'
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
