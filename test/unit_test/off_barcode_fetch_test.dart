import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';

const _found =
    '{"code":"123","status":1,"status_verbose":"product found",'
    '"product":{"code":"123","product_name":"Test"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'tapIn',
      packageName: 'test',
      version: '0.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  OFFDataSource sourceAnswering(
    List<http.Response> answers,
    List<http.BaseRequest> seen,
  ) {
    var i = 0;
    return OFFDataSource(
      clientFactory: () => MockClient((request) async {
        seen.add(request);
        return answers[i < answers.length ? i++ : answers.length - 1];
      }),
    );
  }

  group('barcode lookup against a busy Open Food Facts', () {
    test('a 429 is retried, and a later answer is used', () async {
      final seen = <http.BaseRequest>[];
      final source = sourceAnswering([
        http.Response('slow down', 429, headers: {'retry-after': '0'}),
        http.Response(_found, 200),
      ], seen);

      final result = await source.fetchBarcodeResults('123');

      expect(seen, hasLength(2));
      expect(result.product.code, '123');
    });

    test('a lasting 503 ends as a "busy" error after three tries', () async {
      final seen = <http.BaseRequest>[];
      final source = sourceAnswering([
        http.Response('down', 503, headers: {'retry-after': '0'}),
      ], seen);

      await expectLater(
        source.fetchBarcodeResults('123'),
        throwsA(
          isA<OffUnavailableException>().having(
            (e) => e.statusCode,
            'status',
            503,
          ),
        ),
      );
      expect(seen, hasLength(3));
    });

    test('a missing product is not retried and is not "busy"', () async {
      final seen = <http.BaseRequest>[];
      final source = sourceAnswering([http.Response('{}', 404)], seen);

      await expectLater(
        source.fetchBarcodeResults('123'),
        throwsA(isA<ProductNotFoundException>()),
      );
      expect(seen, hasLength(1));
    });

    test('requests identify as tapIn, not as OpenNutriTracker', () async {
      final seen = <http.BaseRequest>[];
      final source = sourceAnswering([http.Response(_found, 200)], seen);
      await source.fetchBarcodeResults('123');
      final agent = seen.single.headers['User-Agent']!;
      expect(agent, startsWith('tapIn/'));
      expect(agent, contains('github.com/dakshhpanchal/tapIn'));
    });
  });

  group('Retry-After', () {
    test('seconds are read; dates and junk are ignored', () {
      expect(
        OffUnavailableException.parseRetryAfter('7'),
        const Duration(seconds: 7),
      );
      expect(OffUnavailableException.parseRetryAfter(' 0 '), Duration.zero);
      expect(
        OffUnavailableException.parseRetryAfter(
          'Wed, 21 Oct 2026 07:28:00 GMT',
        ),
        isNull,
      );
      expect(OffUnavailableException.parseRetryAfter('-3'), isNull);
      expect(OffUnavailableException.parseRetryAfter(null), isNull);
    });

    test('429 and 5xx mean busy; 404 and 200 do not', () {
      for (final code in [429, 500, 502, 503, 504]) {
        expect(
          OffUnavailableException.isUnavailable(code),
          isTrue,
          reason: '$code',
        );
      }
      for (final code in [200, 400, 404]) {
        expect(
          OffUnavailableException.isUnavailable(code),
          isFalse,
          reason: '$code',
        );
      }
    });
  });
}
