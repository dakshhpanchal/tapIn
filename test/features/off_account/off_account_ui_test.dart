import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/off_account/data/off_account_storage.dart';
import 'package:opennutritracker/features/off_account/data/off_contribution_service.dart';
import 'package:opennutritracker/features/off_account/presentation/off_account_dialog.dart';
import 'package:opennutritracker/features/off_account/presentation/off_contribution_screen.dart';

void main() {
  late OffAccountStorage storage;
  late List<http.Request> sent;

  OffContributionService service(http.Response Function(http.Request) h) {
    sent = [];
    return OffContributionService(
      clientFactory: () => MockClient((r) async {
        sent.add(r);
        return h(r);
      }),
      userAgent: () async => 'tapIn/test',
      appVersion: () async => '1',
    );
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = OffAccountStorage();
  });

  testWidgets('rejects an email address without calling the network', (
    tester,
  ) async {
    final svc = service((_) => http.Response('', 200));
    await tester.pumpWidget(
      MaterialApp(
        home: OffAccountDialog(storage: storage, service: svc),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not your email'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('wrong password is not saved', (tester) async {
    final svc = service((_) => http.Response('', 403));
    await tester.pumpWidget(
      MaterialApp(
        home: OffAccountDialog(storage: storage, service: svc),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user');
    await tester.enterText(find.byType(TextField).at(1), 'bad');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not accept'), findsOneWidget);
    expect(await storage.read(), isNull);
  });

  testWidgets('good login is saved and log out clears it', (tester) async {
    final svc = service(
      (_) => http.Response(
        '',
        200,
        headers: {'set-cookie': 'session=abc; Path=/'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OffAccountDialog(storage: storage, service: svc),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Logged in as user.'), findsOneWidget);
    expect((await storage.read())?.username, 'user');
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(await storage.read(), isNull);
  });

  testWidgets('form blocks implausible numbers before sending', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final svc = service((_) => http.Response('{"status":1}', 200));
    await storage.save(const OffCredentials('user', 'pw'));
    await tester.pumpWidget(
      MaterialApp(
        home: OffContributionScreen(
          initial: const OffProductSubmission(
            barcode: '123',
            name: 'Oats',
            energyKcal: 380,
            fat: 60,
            carbohydrates: 60,
          ),
          storage: storage,
          service: svc,
        ),
      ),
    );
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('add up to more than 100'), findsOneWidget);
    expect(sent, isEmpty);
  });
}
