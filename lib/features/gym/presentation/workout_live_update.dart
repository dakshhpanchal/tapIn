import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// What the running-workout notification says, worked out from the workout.
class WorkoutLiveSummary {
  final String title;

  /// "Bench press · set 2 of 3", or a word on what to do when there is none.
  final String text;
  final int doneSets;
  final int totalSets;

  /// Sets in each exercise that is still in the workout, in order: the
  /// segments of the progress bar.
  final List<int> segments;
  final DateTime startedAt;

  const WorkoutLiveSummary({
    required this.title,
    required this.text,
    required this.doneSets,
    required this.totalSets,
    required this.segments,
    required this.startedAt,
  });

  /// Everything that appears in the notification except the running clock, so
  /// it is only posted again when something the user can see has changed.
  String get key =>
      '$title|$text|$doneSets|$totalSets|$segments|'
      '${startedAt.millisecondsSinceEpoch}';
}

/// The notification for [session]: its name, where the user is up to, and how
/// many sets are ticked. Skipped exercises are left out, like on the workout
/// screen.
WorkoutLiveSummary summarizeWorkout(WorkoutSession session) {
  final counted = [
    for (final e in session.exercises)
      if (!e.skipped) e,
  ];
  final totalSets = counted.fold<int>(0, (n, e) => n + e.sets.length);
  final doneSets = counted.fold<int>(
    0,
    (n, e) => n + e.sets.where((s) => s.done).length,
  );

  String text;
  if (counted.isEmpty || totalSets == 0) {
    text = 'Add an exercise to start logging';
  } else if (doneSets >= totalSets) {
    text = 'All sets done. Finish when you are ready.';
  } else {
    // The first set not ticked yet, in the first exercise that has one.
    final current = counted.firstWhere((e) => e.sets.any((s) => !s.done));
    final index = current.sets.indexWhere((s) => !s.done);
    text = '${current.name} · set ${index + 1} of ${current.sets.length}';
  }

  return WorkoutLiveSummary(
    title: session.name,
    text: text,
    doneSets: doneSets,
    totalSets: totalSets,
    segments: [for (final e in counted) e.sets.length],
    startedAt: session.startedAt,
  );
}

/// Shows the workout in progress as a notification. On Android 16+ it is a
/// Live Update (a status bar chip with the elapsed time, and a card on the lock
/// screen with a progress bar); before that, an ordinary ongoing notification.
/// Does nothing on other platforms and in tests.
class WorkoutLiveUpdate {
  static const _channel = MethodChannel('com.tapin.app/workout_live');
  static final _log = Logger('WorkoutLiveUpdate');

  String? _lastKey;
  bool _clearedStale = false;
  bool _askedPermission = false;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Brings the notification in line with [active]: shown and updated while a
  /// workout is running, removed when there is none (including one left over
  /// from before the app was closed).
  Future<void> sync(WorkoutSession? active) async {
    if (!_supported) return;
    try {
      if (active == null) {
        if (_lastKey != null || !_clearedStale) {
          _lastKey = null;
          _clearedStale = true;
          await _channel.invokeMethod<void>('cancel');
        }
        return;
      }
      _clearedStale = true;
      final summary = summarizeWorkout(active);
      if (summary.key == _lastKey) return;
      _lastKey = summary.key;
      await _ensurePermission();
      await _channel.invokeMethod<void>('show', {
        'title': summary.title,
        'text': summary.text,
        'startedAtMillis': summary.startedAt.millisecondsSinceEpoch,
        'doneSets': summary.doneSets,
        'totalSets': summary.totalSets,
        'segments': summary.segments,
        'channelName': 'Workout in progress',
        'channelDescription':
            'Shows your running workout and its timer while you train.',
      });
    } on MissingPluginException {
      _log.warning('Workout notification: no native handler');
      // No native side here (tests, other platforms).
    } on PlatformException catch (e) {
      _log.warning('Workout notification failed: ${e.message}');
    }
  }

  /// Asks for notification permission the first time a workout is shown, if it
  /// has not been given yet. The workout itself never depends on the answer.
  Future<void> _ensurePermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    try {
      final enabled =
          await _channel.invokeMethod<bool>('areNotificationsEnabled') ?? true;
      if (enabled) return;
      if (locator.isRegistered<NotificationService>()) {
        await locator<NotificationService>().requestPermission();
      }
    } catch (e) {
      _log.fine('Could not check notification permission: $e');
    }
  }
}
