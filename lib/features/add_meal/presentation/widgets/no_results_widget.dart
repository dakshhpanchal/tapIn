import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

class NoResultsWidget extends StatelessWidget {
  final VoidCallback? onScanBarcode;
  final VoidCallback? onCreateCustomFood;
  final VoidCallback? onSearchAll;

  /// Overrides the "no results" wording, for an empty list that is not the
  /// outcome of a search.
  final IconData? icon;
  final String? title;
  final String? subtitle;

  const NoResultsWidget({
    super.key,
    this.icon,
    this.title,
    this.subtitle,
    this.onScanBarcode,
    this.onCreateCustomFood,
    this.onSearchAll,
  });

  @override
  Widget build(BuildContext context) {
    final showActions =
        onScanBarcode != null || onCreateCustomFood != null || onSearchAll != null;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyHint(
            icon: icon ?? Icons.search_off_rounded,
            title: title ?? S.of(context).noResultsFound,
            subtitle:
                subtitle ??
                (showActions ? S.of(context).noResultsSubtitle : null),
          ),
          if (showActions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing24),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: Dimens.spacing8,
                runSpacing: Dimens.spacing8,
                children: [
                  if (onScanBarcode != null)
                    Semantics(
                      identifier: 'search-no-results-scan-barcode',
                      child: OutlinedButton.icon(
                        onPressed: onScanBarcode,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(S.of(context).noResultsScanBarcode),
                      ),
                    ),
                  if (onCreateCustomFood != null)
                    Semantics(
                      identifier: 'search-no-results-create-custom-food',
                      child: FilledButton.tonalIcon(
                        onPressed: onCreateCustomFood,
                        icon: const Icon(Icons.add_circle_outline),
                        label: Text(S.of(context).noResultsCreateCustomFood),
                      ),
                    ),
                  if (onSearchAll != null)
                    Semantics(
                      identifier: 'search-no-results-search-all',
                      child: OutlinedButton.icon(
                        onPressed: onSearchAll,
                        icon: const Icon(Icons.manage_search_rounded),
                        label: Text(S.of(context).noResultsSearchAll),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
