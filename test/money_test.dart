import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/bill/domain/money.dart';

void main() {
  group('parseMinor', () {
    test('reads whole amounts', () {
      expect(parseMinor('2400'), 240000);
      expect(parseMinor('0'), 0);
      expect(parseMinor('1'), 100);
    });

    test('reads decimals', () {
      expect(parseMinor('2400.50'), 240050);
      expect(parseMinor('0.99'), 99);
    });

    test('pads a single decimal place', () {
      // "2400.5" is fifty paise, not five.
      expect(parseMinor('2400.5'), 240050);
    });

    test('truncates rather than rounding up', () {
      // Never invent money the table did not agree to.
      expect(parseMinor('10.567'), 1056);
      expect(parseMinor('10.999'), 1099);
    });

    test('forgives what people actually type at a table', () {
      expect(parseMinor('₹2,400'), 240000);
      expect(parseMinor(' 2400 '), 240000);
      expect(parseMinor('2,400.50'), 240050);
      expect(parseMinor('\$12.30'), 1230);
    });

    test('handles a leading decimal point', () {
      expect(parseMinor('.50'), 50);
    });

    test('returns null for nothing usable', () {
      expect(parseMinor(''), isNull);
      expect(parseMinor('   '), isNull);
      expect(parseMinor('abc'), isNull);
      expect(parseMinor('₹'), isNull);
    });

    test('returns null for a mangled number', () {
      expect(parseMinor('1.2.3'), isNull);
    });
  });

  group('formatMoney', () {
    test('hides the decimals on a round number', () {
      // Nobody writes ₹600.00 on a napkin.
      expect(formatMoney(60000, localeName: 'en_IN'), '₹600');
    });

    test('shows them when there are paise', () {
      expect(formatMoney(60050, localeName: 'en_IN'), '₹600.50');
    });

    test('groups the Indian way', () {
      // ₹2,40,000 — not ₹240,000. This is the whole reason the locale is
      // pinned rather than left to the machine running the test.
      expect(formatMoney(24000000, localeName: 'en_IN'), '₹2,40,000');
    });

    test('groups the Western way elsewhere', () {
      expect(formatMoney(24000000, localeName: 'en_US'), '\$240,000');
    });

    test('falls back rather than throwing on an unknown locale', () {
      // A bad locale must not take the split screen down with it.
      final out = formatMoney(60050, localeName: 'not-a-locale');
      expect(out, contains('600'));
    });

    test('round-trips through parseMinor', () {
      for (final minor in [0, 1, 99, 100, 240050, 24000000]) {
        expect(parseMinor(formatMoney(minor, localeName: 'en_IN')), minor);
      }
    });
  });
}
