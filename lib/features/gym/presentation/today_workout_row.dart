import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';

/// Home screen, above Breakfast: what kind of day today is. The name of the
/// workout done today (Upper, Lower...), "Rest day", or a nudge when neither is
/// logged yet, with a one-tap way to log a rest day.
///
/// Reads the gym data itself and shows nothing where there is none (such as in
/// tests that build the Home page alone).
class TodayWorkoutRow extends StatefulWidget {
  /// Only for tests; the app's own cubit is used otherwise.
  final GymCubit? cubit;
  const TodayWorkoutRow({super.key, this.cubit});

  @override
  State<TodayWorkoutRow> createState() => _TodayWorkoutRowState();
}

class _TodayWorkoutRowState extends State<TodayWorkoutRow> {
  late final GymCubit? _cubit =
      widget.cubit ??
      (locator.isRegistered<GymCubit>() ? locator<GymCubit>() : null);

  @override
  void initState() {
    super.initState();
    // Tabs build when first opened, so the gym data may not be loaded yet.
    final cubit = _cubit;
    if (cubit != null && !cubit.state.loaded) cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<GymCubit, GymState>(
      bloc: cubit,
      builder: (context, state) {
        if (!state.loaded) return const SizedBox.shrink();
        final now = DateTime.now();
        final today = GymCubit.dayKey(now);
        bool isToday(DateTime d) => GymCubit.dayKey(d) == today;

        // Oldest first, so a second workout reads after the first.
        final names = <String>[];
        for (final s in state.sessions.reversed) {
          if (isToday(s.startedAt) && !names.contains(s.name)) {
            names.add(s.name);
          }
        }
        final active = state.active;
        final inProgress = active != null && isToday(active.startedAt);
        if (inProgress && !names.contains(active.name)) names.add(active.name);
        final rest = state.restDays.contains(today);

        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        late final IconData icon;
        late final String title;
        Widget? trailing;
        var muted = false;
        if (names.isNotEmpty) {
          icon = Icons.fitness_center_rounded;
          title = names.join(' · ');
          if (inProgress) {
            trailing = Text(
              'In progress',
              style: text.labelSmall?.copyWith(color: scheme.primary),
            );
          }
        } else if (rest) {
          icon = Icons.self_improvement_rounded;
          title = 'Rest day';
          trailing = IconButton(
            tooltip: 'Not a rest day',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => cubit.setRestDay(now, false),
          );
        } else {
          icon = Icons.fitness_center_outlined;
          title = 'No workout yet';
          muted = true;
          trailing = TextButton(
            onPressed: () => cubit.setRestDay(now, true),
            child: const Text('Rest day'),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Dimens.spacing16,
            vertical: Dimens.spacing4,
          ),
          child: AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing16,
              vertical: Dimens.spacing8,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Dimens.spacing8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: muted ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        );
      },
    );
  }
}
