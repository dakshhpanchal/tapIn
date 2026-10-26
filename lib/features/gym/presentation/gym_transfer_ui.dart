import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';

/// Saves all workouts to a JSON file the user picks the place for.
Future<void> exportWorkouts(BuildContext context) async {
  final cubit = context.read<GymCubit>();
  final messenger = ScaffoldMessenger.of(context);
  final json = cubit.exportJson();
  final now = DateTime.now();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  try {
    final saved = await FilePicker.saveFile(
      fileName: 'tapin-workouts-$stamp.json',
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
    if (saved != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Workouts exported.')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
  }
}

/// Explains the file format, lets the user pick a file, and reports the result.
Future<void> importWorkouts(BuildContext context) async {
  final cubit = context.read<GymCubit>();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import workouts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a .json file with your workouts. Exercises you do not '
              'have yet are created from their names, and importing the same '
              'file again does not duplicate anything. Weights are kg, or '
              'plates when an exercise has "plates": true; "setting" holds the '
              'machine setting. To convert your own notes, tap "Copy format" '
              'and paste it into a chat together with them.',
            ),
            const SizedBox(height: Dimens.spacing12),
            Text('Example', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: Dimens.spacing4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Dimens.spacing8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SelectableText(
                gymImportExample,
                style: TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: gymImportPrompt));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Format copied. Paste it into a chat with your workouts.',
                  ),
                ),
              );
            }
          },
          child: const Text('Copy format'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Choose file'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  String message;
  try {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    final path = picked.path;
    if (path == null) {
      throw const GymImportException('The file could not be read.');
    }
    final plan = await cubit.importJson(await File(path).readAsString());
    message = _summary(plan);
  } on GymImportException catch (e) {
    message = e.message;
  } on FileSystemException {
    message = 'The file could not be read.';
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import'),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String _summary(GymImportPlan plan) {
  if (plan.isEmpty && plan.sessionsSkipped == 0 && plan.workoutsUpdated == 0) {
    return plan.warnings.isEmpty
        ? 'The file had no workouts or history to import.'
        : 'Nothing was imported.\n\n${plan.warnings.join('\n')}';
  }
  final lines = <String>[
    if (plan.workouts.isNotEmpty)
      '${plan.workouts.length} workout${plan.workouts.length == 1 ? '' : 's'} '
          '(${plan.workoutsUpdated} replaced an existing one)',
    if (plan.sessions.isNotEmpty)
      '${plan.sessions.length} logged workout${plan.sessions.length == 1 ? '' : 's'}',
    if (plan.sessionsSkipped > 0)
      '${plan.sessionsSkipped} already in your history, skipped',
    if (plan.updatedExercises.isNotEmpty)
      '${plan.updatedExercises.length} existing exercise${plan.updatedExercises.length == 1 ? '' : 's'} updated (name, muscle group or plates)',
    if (plan.newExercises.isNotEmpty)
      '${plan.newExercises.length} new exercise${plan.newExercises.length == 1 ? '' : 's'}',
  ];
  return [
    'Imported:',
    ...lines.map((l) => '• $l'),
    if (plan.warnings.isNotEmpty) ...[
      '',
      'Skipped:',
      ...plan.warnings.map((w) => '• $w'),
    ],
  ].join('\n');
}
