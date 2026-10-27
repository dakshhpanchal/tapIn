import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

class ErrorDialog extends StatelessWidget {
  final String errorText;
  final VoidCallback onRefreshPressed;

  /// Locale-independent `Semantics` identifier for the Retry button, so UI
  /// drivers can find it (AGENTS.md, "Accessibility identifiers"). Callers
  /// name it after their surface, e.g. `search-all-retry`.
  final String? retryIdentifier;

  /// An optional second action under Retry, such as "Add this product".
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final String? secondaryIdentifier;

  const ErrorDialog({
    super.key,
    required this.errorText,
    required this.onRefreshPressed,
    this.retryIdentifier,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.secondaryIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing24,
        64,
        Dimens.spacing24,
        Dimens.spacing24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: palette.textMuted),
          const SizedBox(height: Dimens.spacing16),
          SizedBox(
            width: double.infinity,
            child: Text(
              errorText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            identifier: retryIdentifier,
            child: FilledButton.icon(
              onPressed: () => onRefreshPressed(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(S.of(context).retryLabel),
            ),
          ),
          if (secondaryLabel != null && onSecondaryPressed != null) ...[
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: secondaryIdentifier,
              child: OutlinedButton.icon(
                onPressed: onSecondaryPressed,
                icon: const Icon(Icons.add_rounded),
                label: Text(secondaryLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
