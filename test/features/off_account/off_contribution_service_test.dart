import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/off_account/data/off_account_storage.dart';
import 'package:opennutritracker/features/off_account/data/off_contribution_service.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';

const _login = OffCredentials('daksh', 'hunter2-secret');

const _product = OffProductSubmission(
  barcode: '8901234567890',
  name: ' Test Bar ',
  brands: 'Acme',
  quantity: '40 g',
  servingSize: '40 g',
  energyKcal: 450,
  fat: 20.5,
  saturatedFat: 8,
  carbohydrates: 55,
  sugars: 30,
  fiber: 4,
  proteins: 9,
  salt: 0.25,
);

OffContributionService _service(
  Future<http.Response> Function(http.MultipartRequest request) answer, [
  List<http.MultipartRequest>? seen,
]) => OffContributionService(
  clientFactory: () => MockClient.streaming((request, body) async {
    // Rebuild the request the service made so its fields can be read.
    final multipart = request as http.MultipartRequest;
    seen?.add(multipart);
    final response = await answer(multipart);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }),
  userAgent: () async => 'tapIn/2.5.0 (Android; https://example.test)',
  appVersion: () async => '2.5.0',
);

void main() {
  group('uploading a product', () {
    test(
      'sends the label facts as form fields, with units, and the login',
      () async {
        final seen = <http.MultipartRequest>[];
        final service = _service(
          (r) async => http.Response(
            '{"status":1,"status_verbose":"fields saved"}',
            200,
          ),
          seen,
        );

        await service.uploadProduct(
          _login,
          _product,
          comment: 'Added with tapIn',
        );

        final request = seen.single;
        expect(
          request.url.toString(),
          'https://world.openfoodfacts.org/cgi/product_jqm2.pl',
        );
        expect(request.method, 'POST');
        final f = request.fields;
        expect(f['code'], '8901234567890');
        expect(f['product_name'], 'Test Bar'); // trimmed
        expect(f['brands'], 'Acme');
        expect(f['quantity'], '40 g');
        expect(f['serving_size'], '40 g');
        expect(f['nutrition_data_per'], '100g');
        expect(f['nutriment_energy-kcal'], '450');
        expect(f['nutriment_energy-kcal_unit'], 'kcal');
        expect(f['nutriment_fat'], '20.5');
        expect(f['nutriment_fat_unit'], 'g');
        expect(f['nutriment_saturated-fat'], '8');
        expect(f['nutriment_carbohydrates'], '55');
        expect(f['nutriment_sugars'], '30');
        expect(f['nutriment_fiber'], '4');
        expect(f['nutriment_proteins'], '9');
        expect(f['nutriment_salt'], '0.25');
        expect(f['app_name'], 'tapIn');
        expect(f['app_version'], '2.5.0');
        expect(f['comment'], 'Added with tapIn');
        expect(f['lc'], 'en');
        expect(f['user_id'], 'daksh');
        expect(f['password'], 'hunter2-secret');
      },
    );

    test(
      'the password goes in the body, never the URL, and the agent identifies the app',
      () async {
        final seen = <http.MultipartRequest>[];
        final service = _service(
          (r) async => http.Response('{"status":1}', 200),
          seen,
        );
        await service.uploadProduct(_login, _product, comment: 'x');
        expect(seen.single.url.toString(), isNot(contains('hunter2')));
        expect(seen.single.url.query, isEmpty);
        expect(seen.single.headers['User-Agent'], startsWith('tapIn/'));
      },
    );

    test('fields left empty are not sent, so nothing gets blanked', () {
      final fields = const OffProductSubmission(
        barcode: '8901234567890',
        name: 'Plain',
        energyKcal: 100,
      ).toFields(language: 'en', appVersion: '1', comment: 'c');
      expect(fields.containsKey('brands'), isFalse);
      expect(fields.containsKey('quantity'), isFalse);
      expect(fields.containsKey('serving_size'), isFalse);
      expect(fields.containsKey('nutriment_fat'), isFalse);
      expect(fields.containsKey('nutriment_fat_unit'), isFalse);
      expect(fields['nutriment_energy-kcal'], '100');
    });

    test('numbers are plain decimals without trailing zeros', () {
      final fields = const OffProductSubmission(
        barcode: '8901234567890',
        name: 'n',
        fat: 12.0,
        sugars: 0.1 + 0.2, // 0.30000000000000004
        proteins: 7.125,
      ).toFields(language: 'en', appVersion: '1', comment: 'c');
      expect(fields['nutriment_fat'], '12');
      expect(fields['nutriment_sugars'], '0.3');
      expect(fields['nutriment_proteins'], '7.125');
    });

    test('a refusal from Open Food Facts surfaces its reason', () async {
      final service = _service(
        (r) async => http.Response(
          '{"status":0,"status_verbose":"no code or invalid code"}',
          200,
        ),
      );
      await expectLater(
        service.uploadProduct(_login, _product, comment: 'x'),
        throwsA(
          isA<OffContributionException>().having(
            (e) => e.message,
            'message',
            'no code or invalid code',
          ),
        ),
      );
    });

    test(
      'bad credentials, a busy server and junk answers are told apart',
      () async {
        await expectLater(
          _service(
            (r) async => http.Response('no', 403),
          ).uploadProduct(_login, _product, comment: 'x'),
          throwsA(isA<OffLoginRejectedException>()),
        );
        await expectLater(
          _service(
            (r) async =>
                http.Response('slow', 429, headers: {'retry-after': '5'}),
          ).uploadProduct(_login, _product, comment: 'x'),
          throwsA(
            isA<OffUnavailableException>().having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 5),
            ),
          ),
        );
        await expectLater(
          _service(
            (r) async => http.Response('<html>', 200),
          ).uploadProduct(_login, _product, comment: 'x'),
          throwsA(isA<OffContributionException>()),
        );
      },
    );

    test('no error or log text ever contains the password', () async {
      final attempts = <Future<void>>[
        _service(
          (r) async =>
              http.Response('{"status":0,"status_verbose":"nope"}', 200),
        ).uploadProduct(_login, _product, comment: 'x'),
        _service(
          (r) async => http.Response('no', 403),
        ).uploadProduct(_login, _product, comment: 'x'),
        _service(
          (r) async => http.Response('down', 503),
        ).uploadProduct(_login, _product, comment: 'x'),
      ];
      for (final attempt in attempts) {
        try {
          await attempt;
          fail('should have failed');
        } catch (e) {
          expect('$e', isNot(contains('hunter2')));
        }
      }
      expect('$_login', isNot(contains('hunter2')));
    });
  });

  group('checking a login', () {
    test('accepted when a session starts', () async {
      final seen = <http.MultipartRequest>[];
      final service = _service(
        (r) async => http.Response(
          '',
          200,
          headers: {'set-cookie': 'session=abc; path=/'},
        ),
        seen,
      );
      await service.verifyLogin(_login);
      expect(seen.single.url.path, '/cgi/session.pl');
      expect(seen.single.fields, {
        'user_id': 'daksh',
        'password': 'hunter2-secret',
      });
    });

    test('refused on 403, or on a 200 that starts no session', () async {
      await expectLater(
        _service((r) async => http.Response('Error', 403)).verifyLogin(_login),
        throwsA(isA<OffLoginRejectedException>()),
      );
      await expectLater(
        _service((r) async => http.Response('', 200)).verifyLogin(_login),
        throwsA(isA<OffLoginRejectedException>()),
      );
    });
  });

  group('the saved login', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('is stored, read back, and cleared', () async {
      final storage = OffAccountStorage(const FlutterSecureStorage());
      expect(await storage.read(), isNull);
      await storage.save(_login);
      final back = await storage.read();
      expect(back!.username, 'daksh');
      expect(back.password, 'hunter2-secret');
      await storage.clear();
      expect(await storage.read(), isNull);
    });
  });
}
