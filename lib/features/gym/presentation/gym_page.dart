import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/active_workout_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/gym_transfer_ui.dart';
import 'package:opennutritracker/features/gym/presentation/reorder_sheet.dart';
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';
import 'package:opennutritracker/features/gym/presentation/workout_editor_screen.dart';

/// The Gym tab: your planned workouts (start one, then log reps as you go),
/// a quick workout, and history. The cubit is provided above the Navigator.
class GymPage extends StatefulWidget {
  const GymPage({super.key});

  @override
  State<GymPage> createState() => _GymPageState();
}

class _GymPageState extends State<GymPage> {
  @override
  void initState() {
    super.initState();
    context.read<GymCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GymCubit, GymState>(
      builder: (context, state) {
        if (!state.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final cubit = context.read<GymCubit>();
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            120,
          ),
          children: [
            if (state.active != null) ...[
              _ActiveCard(session: state.active!),
              const SizedBox(height: Dimens.spacing16),
            ],
            _WeekCard(sessions: state.sessions),
            const SizedBox(height: Dimens.spacing16),
            Row(
              children: [
                Expanded(child: Text('My workouts', style: text.titleMedium)),
                IconButton(
                  tooltip: 'Import workouts',
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () => importWorkouts(context),
                ),
                IconButton(
                  tooltip: 'Export workouts',
                  icon: const Icon(Icons.file_upload_outlined),
                  onPressed: state.routines.isEmpty && state.sessions.isEmpty
                      ? null
                      : () => exportWorkouts(context),
                ),
                IconButton(
                  tooltip: 'Reorder workouts',
                  icon: const Icon(Icons.swap_vert_rounded),
                  onPressed: state.routines.length < 2
                      ? null
                      : () => _reorderWorkouts(context, state.routines),
                ),
              ],
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('New workout'),
              onPressed: () => _openEditor(context),
            ),
            const SizedBox(height: Dimens.spacing8),
            if (state.routines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
                child: Text(
                  'Create a workout with its exercises and sets. When you do '
                  'it, you log the reps for each set.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: mutedColor(context)),
                ),
              )
            else
              for (final r in state.routines)
                _WorkoutTile(routine: r, canStart: state.active == null),
            if (state.active == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.flash_on_rounded, size: 18),
                  label: const Text('Quick workout'),
                  onPressed: () async {
                    await cubit.startEmptyWorkout();
                    if (context.mounted) _openActive(context);
                  },
                ),
              ),
            const SizedBox(height: Dimens.spacing16),
            Text('History', style: text.titleMedium),
            const SizedBox(height: Dimens.spacing8),
            if (state.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
                child: Text(
                  'Finished workouts show up here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: mutedColor(context)),
                ),
              )
            else
              for (final s in state.sessions)
                _SessionTile(session: s, useLb: state.useLb),
          ],
        );
      },
    );
  }
}

Future<void> _reorderWorkouts(
  BuildContext context,
  List<Routine> routines,
) async {
  final cubit = context.read<GymCubit>();
  final order = await showReorderSheet(
    context,
    title: 'Reorder workouts',
    items: [for (final r in routines) r.name],
  );
  if (order != null) {
    await cubit.reorderRoutines([for (final i in order) routines[i]]);
  }
}

void _openEditor(BuildContext context, {Routine? existing}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutEditorScreen(existing: existing),
    ),
  );
}

void _openActive(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ActiveWorkoutScreen()));
}

class _ActiveCard extends StatelessWidget {
  final WorkoutSession session;
  const _ActiveCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Skipped exercises are left out of the count.
    final counted = session.exercises.where((e) => !e.skipped);
    final done = counted.fold<int>(
      0,
      (n, e) => n + e.sets.where((s) => s.done).length,
    );
    final total = counted.fold<int>(0, (n, e) => n + e.sets.length);
    return AppCard(
      color: scheme.primaryContainer,
      onTap: () => _openActive(context),
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Row(
        children: [
          Icon(Icons.fitness_center_rounded, color: scheme.onPrimaryContainer),
          const SizedBox(width: Dimens.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  '${session.name} · $done of $total sets done',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _openActive(context),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  final Routine routine;
  final bool canStart;
  const _WorkoutTile({required this.routine, required this.canStart});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final text = Theme.of(context).textTheme;
    final sets = routine.exercises.fold<int>(0, (n, e) => n + e.sets.length);
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        // Tapping the workout opens it: starts it, or goes back to the one
        // already in progress.
        onTap: () async {
          if (canStart) await cubit.startFromRoutine(routine);
          if (context.mounted) _openActive(context);
        },
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing12,
          Dimens.spacing4,
          Dimens.spacing12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(routine.name, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${routine.exercises.length} exercises · $sets sets',
                    style: text.bodySmall?.copyWith(color: mutedColor(context)),
                  ),
                  Text(
                    routine.exercises.map((e) => e.name).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: mutedColor(context)),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: canStart
                  ? () async {
                      await cubit.startFromRoutine(routine);
                      if (context.mounted) _openActive(context);
                    }
                  : null,
              child: const Text('Start'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _openEditor(context, existing: routine);
                if (v == 'delete') cubit.deleteRoutine(routine.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final bool useLb;
  const _SessionTile({required this.session, required this.useLb});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(session.name, style: text.titleSmall)),
                Text(
                  dateText(session.startedAt),
                  style: text.bodySmall?.copyWith(color: mutedColor(context)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              // Volume is kg moved; plate-only workouts have none to show.
              '${sessionSetCount(session)} sets'
              '${sessionVolume(session) > 0 ? ' · ${volumeText(sessionVolume(session), useLb)}' : ''}',
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
            Text(
              session.exercises.map((e) => e.name).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// This week's totals and how the sets were spread over muscle groups.
class _WeekCard extends StatelessWidget {
  final List<WorkoutSession> sessions;
  const _WeekCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - DateTime.monday),
    );
    final week = [
      for (final s in sessions)
        if (!s.startedAt.isBefore(weekStart)) s,
    ];
    final counts = setsPerMuscle(week).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: text.titleMedium),
          const SizedBox(height: Dimens.spacing12),
          Wrap(
            spacing: Dimens.spacing24,
            runSpacing: Dimens.spacing12,
            children: [
              _stat(context, 'Workouts', '${week.length}'),
              _stat(
                context,
                'Sets',
                '${week.fold(0, (n, s) => n + sessionSetCount(s))}',
              ),
            ],
          ),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing16),
            for (final e in counts.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(e.key.label, style: text.bodySmall),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: e.value / counts.first.value,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${e.value}',
                        textAlign: TextAlign.end,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => SizedBox(
    width: 100,
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
}
