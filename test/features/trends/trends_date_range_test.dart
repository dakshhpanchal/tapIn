import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';

void main() {
  final now = DateTime(2026, 11, 11);

  setUpAll(() => initializeDateFormatting('en'));

  group('formatDateRange', () {
    test('two dates in this year read as a short range', () {
      expect(
        formatDateRange(
          DateTime(2026, 10, 14),
          DateTime(2026, 11, 10),
          'en',
          now: now,
        ),
        'Oct 14 – Nov 10',
      );
    });

    test('one day reads as a single date', () {
      expect(
        formatDateRange(
          DateTime(2026, 11, 10),
          DateTime(2026, 11, 10),
          'en',
          now: now,
        ),
        'Nov 10',
      );
    });

    test('a range that reaches into another year shows the years', () {
      expect(
        formatDateRange(
          DateTime(2025, 12, 28),
          DateTime(2026, 1, 3),
          'en',
          now: now,
        ),
        'Dec 28, 2025 – Jan 3, 2026',
      );
    });

    test('a whole range in an earlier year also shows the year', () {
      expect(
        formatDateRange(
          DateTime(2025, 3, 1),
          DateTime(2025, 3, 7),
          'en',
          now: now,
        ),
        'Mar 1, 2025 – Mar 7, 2025',
      );
    });
  });

  group('periodSpan', () {
    // A 30-day window ending Tuesday 10 Nov 2026 starts Monday 12 Oct.
    final windowStart = DateTime(2026, 10, 12);
    final windowEnd = DateTime(2026, 11, 10);

    test('a full week keeps its Monday to Sunday', () {
      final span = periodSpan(
        DateTime(2026, 10, 19),
        false,
        windowStart,
        windowEnd,
      );
      expect(span.start, DateTime(2026, 10, 19));
      expect(span.end, DateTime(2026, 10, 25));
    });

    test('the current week stops at the last counted day', () {
      final span = periodSpan(
        DateTime(2026, 11, 9),
        false,
        windowStart,
        windowEnd,
      );
      expect(span.start, DateTime(2026, 11, 9));
      expect(span.end, DateTime(2026, 11, 10));
    });

    test('a week that began before the window starts on its first day', () {
      final span = periodSpan(
        DateTime(2026, 10, 5),
        false,
        windowStart,
        windowEnd,
      );
      // Mon 5 Oct to Sun 11 Oct lies wholly before the window, so only the
      // window's own first day can be shown; callers never ask for such a
      // week because no logged day falls in it.
      expect(span.start, DateTime(2026, 10, 12));
    });

    test('a month is cut to the window at both ends', () {
      final oct = periodSpan(DateTime(2026, 10), true, windowStart, windowEnd);
      expect(oct.start, DateTime(2026, 10, 12));
      expect(oct.end, DateTime(2026, 10, 31));
      final nov = periodSpan(DateTime(2026, 11), true, windowStart, windowEnd);
      expect(nov.start, DateTime(2026, 11, 1));
      expect(nov.end, DateTime(2026, 11, 10));
    });

    test('a month in the middle covers the whole month', () {
      final span = periodSpan(
        DateTime(2026, 9),
        true,
        DateTime(2026, 8, 1),
        DateTime(2026, 11, 10),
      );
      expect(span.start, DateTime(2026, 9, 1));
      expect(span.end, DateTime(2026, 9, 30));
    });
  });
}
