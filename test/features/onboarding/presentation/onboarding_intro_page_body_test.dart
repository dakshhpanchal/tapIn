import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    // The widget shows AppConst.getVersionNumber() in a FutureBuilder, which
    // calls PackageInfo.fromPlatform(). Mock it so the widget renders in tests.
    PackageInfo.setMockInitialValues(
      appName: 'tapIn',
      packageName: 'com.tapin.app',
      version: '1.0.0',
      buildNumber: '68',
      buildSignature: '',
    );
  });

  Future<List<(bool, bool)>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <(bool, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: OnboardingIntroPageBody(
            setPageContent: (active, data) => calls.add((active, data)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('has no privacy-policy checkbox or link', (tester) async {
    await pump(tester);
    expect(find.byType(Checkbox), findsOneWidget); // data collection only
    expect(find.textContaining('privacy policy'), findsNothing);
  });

  testWidgets('Start is reported active from the first frame', (tester) async {
    final calls = await pump(tester);
    expect(calls.first, (true, false));
  });

  testWidgets('the data-collection checkbox reports (true, true)',
      (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(calls.last, (true, true));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}
