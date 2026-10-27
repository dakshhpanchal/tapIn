import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('Retry alone by default', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _wrap(ErrorDialog(errorText: 'Oops', onRefreshPressed: () => retried++)),
    );
    expect(find.text('Oops'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(retried, 1);
  });

  testWidgets('an optional second action sits under Retry', (tester) async {
    var added = 0;
    await tester.pumpWidget(
      _wrap(
        ErrorDialog(
          errorText: 'Not found',
          onRefreshPressed: () {},
          secondaryLabel: 'Add this product',
          onSecondaryPressed: () => added++,
        ),
      ),
    );
    await tester.tap(find.text('Add this product'));
    expect(added, 1);
  });
}
