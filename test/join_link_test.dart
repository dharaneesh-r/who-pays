import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/room/domain/join_link.dart';

void main() {
  group('forCode', () {
    test('builds an https link a phone camera will offer to open', () {
      expect(JoinLink.forCode('ABCD'), '${JoinLink.host}/j/ABCD');
    });

    test('uppercases the code', () {
      expect(JoinLink.forCode('abcd'), endsWith('/j/ABCD'));
    });
  });

  group('parse', () {
    test('reads the app\'s own link', () {
      expect(JoinLink.parse('${JoinLink.host}/j/WXYZ'), 'WXYZ');
    });

    test('reads a bare code, in any case', () {
      expect(JoinLink.parse('WXYZ'), 'WXYZ');
      expect(JoinLink.parse('wxyz'), 'WXYZ');
      expect(JoinLink.parse('  wxyz  '), 'WXYZ');
    });

    test('reads a custom-scheme link', () {
      expect(JoinLink.parse('whopays://join/WXYZ'), 'WXYZ');
    });

    test('reads a code in the query string', () {
      expect(JoinLink.parse('https://example.com/join?code=wxyz'), 'WXYZ');
    });

    test('rejects codes containing I or O, which rooms never use', () {
      // The alphabet skips them because they are misread aloud as 1 and 0.
      expect(JoinLink.parse('ABIO'), isNull);
      expect(JoinLink.parse('IIII'), isNull);
    });

    test('rejects anything that is not a code', () {
      expect(JoinLink.parse(null), isNull);
      expect(JoinLink.parse(''), isNull);
      expect(JoinLink.parse('   '), isNull);
      expect(JoinLink.parse('ABC'), isNull);
      expect(JoinLink.parse('ABCDE'), isNull);
      expect(JoinLink.parse('12345'), isNull);
      expect(JoinLink.parse('https://example.com/'), isNull);
      expect(JoinLink.parse('https://malicious.example/j/notacode'), isNull);
    });

    test('takes the last matching path segment, not the first', () {
      expect(JoinLink.parse('https://example.com/ABCD/j/WXYZ'), 'WXYZ');
    });
  });
}
