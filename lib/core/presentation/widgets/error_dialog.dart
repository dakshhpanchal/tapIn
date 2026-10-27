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

  /// A smaller line under [errorText], for a hint that should not read as a
  /// heading.
  final String? subtitle;

  /// Defaults to the "offline" cloud; a missing item is not an outage.
  final IconData icon;

  /// Makes the second action the main one and Retry the quiet one, for the
  /// states where retrying the same request is rarely what the user wants.
  final bool emphasizeSecondary;

  const ErrorDialog({
    super.key,
    required this.errorText,
    required this.onRefreshPressed,
    this.retryIdentifier,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.secondaryIdentifier,
    this.subtitle,
    this.icon = Icons.cloud_off_rounded,
    this.emphasizeSecondary = false,
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
          Icon(icon, size: 64, color: palette.textMuted),
          const SizedBox(height: Dimens.spacing16),
          SizedBox(
            width: double.infinity,
            child: Text(
              errorText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Dimens.spacing8),
            SizedBox(
              width: double.infinity,
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: Dimens.spacing16),
          ..._buttons(context),
        ],
      ),
    );
  }

  List<Widget> _buttons(BuildContext context) {
    final hasSecondary = secondaryLabel != null && onSecondaryPressed != null;
    final retry = Semantics(
      identifier: retryIdentifier,
      child: (hasSecondary && emphasizeSecondary)
          ? OutlinedButton.icon(
              onPressed: () => onRefreshPressed(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(S.of(context).retryLabel),
            )
          : FilledButton.icon(
              onPressed: () => onRefreshPressed(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(S.of(context).retryLabel),
            ),
    );
    if (!hasSecondary) return [retry];
    final other = Semantics(
      identifier: secondaryIdentifier,
      child: emphasizeSecondary
          ? FilledButton.icon(
              onPressed: onSecondaryPressed,
              icon: const Icon(Icons.add_rounded),
              label: Text(secondaryLabel!),
            )
          : OutlinedButton.icon(
              onPressed: onSecondaryPressed,
              icon: const Icon(Icons.add_rounded),
              label: Text(secondaryLabel!),
            ),
    );
    const gap = SizedBox(height: Dimens.spacing8);
    return emphasizeSecondary ? [other, gap, retry] : [retry, gap, other];
  }
}
