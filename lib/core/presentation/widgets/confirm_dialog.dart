import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Asks the user to confirm. Cancel is a quiet text button and the
/// confirmation a filled one, in the error colour when it destroys something,
/// so every confirmation in the app reads and behaves the same way.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? content,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content == null ? null : Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(Localizations.of<S>(ctx, S)?.dialogCancelLabel ?? 'Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
