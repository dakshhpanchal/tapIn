import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The Save button every editing screen shows in its app bar, so saving a food,
/// a recipe or a workout looks and reads the same.
class AppBarSaveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool saving;
  final String? identifier;

  const AppBarSaveButton({
    super.key,
    required this.onPressed,
    this.saving = false,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: Dimens.spacing16),
      child: Semantics(
        identifier: identifier,
        child: FilledButton(
          onPressed: saving ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing20),
          ),
          child: saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : Text(Localizations.of<S>(context, S)?.buttonSaveLabel ?? 'Save'),
        ),
      ),
    );
  }
}
